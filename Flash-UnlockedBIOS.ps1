<#
  WinMax Unlocked - unlocked BIOS 1.16 (3733 MT/s) for the GPD Win Max (2020)

  Flashes the BIOS region with Intel's Flash Programming Tool (FPTW64), keeping your own NVRAM (settings, boot
  entries, Windows key area), the ME firmware/data, the EC firmware and the flash descriptor untouched.

  What it does, in order:
    1. Safety checks (administrator, AC power, Memory Integrity, BitLocker).
    2. Gets FPTW64.exe out of GPD's official BIOS 1.16 package (it is not redistributed here).
    3. Makes a full 16 MB backup of the flash chip (read twice and compared).
    4. Refuses to continue unless the chip holds GPD's official BIOS 1.16 (October 2021 build).
    5. Builds the image to write: your live NVRAM + the unlocked BIOS code. The saved memory-training record
       is marked deleted so the memory retrains at the new speed on the next boot.
    6. Writes only the BIOS region, reads it back and verifies it. If the write does not verify it retries,
       then writes your original BIOS back. It never reboots by itself.

  Usage (from an elevated PowerShell, or just double-click Flash-UnlockedBIOS.bat):
    .\Flash-UnlockedBIOS.ps1                       install the unlocked BIOS
    .\Flash-UnlockedBIOS.ps1 -Restore              go back to GPD's official 1.16 code (keeps your NVRAM)
    .\Flash-UnlockedBIOS.ps1 -KeepMemoryTraining   do not reset the saved memory training
#>
param(
    [string]$GpdPackage,                 # path to WINMAX.1.16.GPD.zip or .exe (auto-detected next to this script / in Downloads)
    [switch]$Restore,
    [switch]$KeepMemoryTraining,
    # test-harness switches (not for normal use)
    [string]$WorkDir, [string]$FptPath, [string]$GpdBin, [switch]$Test
)
$ErrorActionPreference = 'Stop'
$Yes = [bool]$Test
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $WorkDir) { $WorkDir = Join-Path $Here ('work-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$Log = Join-Path $WorkDir 'flash.log'

# ---------------------------------------------------------------- constants
$REGION = 0xA00000                 # BIOS region size (flash 0x600000-0xFFFFFF)
$CODE = 0x70000                    # everything from here on is firmware code; below it is NVRAM
$IMAGE_NAME = 'WINMAX.1.16.UNLOCKED.3733.rom'
$IMAGE_SHA = '1563AD91B14A1582EBA58C80EDA46F660DC60128D6F11C64A495D655EAE0BA98'
$UNLOCKED_CODE_SHA = 'D1F3EB0ADC1D5B7A37FCB025CA7BDB73395CA7E20B61CEDC8C89D99F8646843A'
$OFFICIAL_CODE_SHA = '29D626167740F469A3F70CC19C7ACCEDFA8F63C24DEBC838A8E89BA835729A96'   # GPD 1.16, 10/19/2021
$OFFICIAL_NAME = 'WINMAX.1.16.OFFICIAL.rom'                                                # GPD's unmodified BIOS region, factory NVRAM
$OFFICIAL_SHA = '3654056F2E5061B279D03C399F73D33CC16DF7F9B0BD524E9FFA6A5C80C5FCE2'
$FPT_SHA = 'D3F0549AED4B1A07E3B68C17F300FDEC66897C856B3825A299CC7BD395F331CF'           # FPTW64 13.0.32.1478 from GPD's package
$GPD_BIN_SHA = 'D3F3038D3DB72066'                                                         # prefix of WINMAX.1.16.GPD.bin sha256
$NVRAM_FILE_GUID = 'A3B9F5CE6D477F499FDCE98143E0422C'    # CEF5B9A3-476D-497F-9FDC-E98143E0422C (AMI NVRAM store file)
$MEMCFG_GUID = '4D8C4FC99A9BFE458A55238B67302643'        # C94F8C4D-9B9A-45FE-8A55-238B67302643 (MRC MemoryConfig)

# ---------------------------------------------------------------- helpers
function Log($m) { Add-Content -Path $Log -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) -Encoding ascii }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c; Log $m }
function Fail($m) { Say "STOPPED: $m" 'Red'; Say "Nothing was written to the BIOS. Log: $Log" 'Yellow'; exit 2 }
function Sha([byte[]]$b, [int]$off, [int]$len) {
    $h = [Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($h.ComputeHash($b, $off, $len))).Replace('-', '')
}
function Hex([byte[]]$b, [int]$off, [int]$len) { ([BitConverter]::ToString($b, $off, $len)).Replace('-', '') }
function Confirm($question, $word) {
    if ($Yes) { return }
    $a = Read-Host "$question (type $word to continue)"
    if ($a -cne $word) { Fail 'cancelled by user' }
}
function Fpt([string]$fptArgs, [string]$outName) {
    $out = Join-Path $WorkDir $outName
    $p = Start-Process -FilePath $script:Fpt -ArgumentList $fptArgs -WorkingDirectory $WorkDir `
        -RedirectStandardOutput $out -RedirectStandardError ($out + '.err') -NoNewWindow -PassThru
    $null = $p.Handle
    while (-not $p.WaitForExit(10000)) { Write-Host '  ... working' -ForegroundColor DarkGray }
    $p.WaitForExit()
    Log "FPTW64 $fptArgs -> exit $($p.ExitCode) ; $((Get-Content $out -Tail 2 -ErrorAction SilentlyContinue) -join ' | ')"
    $p.ExitCode
}
function Dump([string]$name, [switch]$Full) {
    $p = Join-Path $WorkDir $name
    if (Test-Path $p) { Remove-Item $p -Force }
    $a = if ($Full) { "-d `"$p`"" } else { "-bios -d `"$p`"" }
    $c = Fpt $a ($name + '.txt')
    $want = if ($Full) { 0x1000000 } else { $REGION }
    if ($c -ne 0 -or -not (Test-Path $p) -or (Get-Item $p).Length -ne $want) { throw "reading the flash ($name) failed, FPT exit $c" }
    [IO.File]::ReadAllBytes($p)
}

# Find the live AMI NVRAM store and the valid MemoryConfig header in it.
function Find-MemoryConfig([byte[]]$b) {
    $live = @()
    foreach ($s in 0x0, 0x30000) {
        if ([Text.Encoding]::ASCII.GetString($b, $s + 0x28, 4) -ne '_FVH') { continue }
        if ((Hex $b ($s + 0x78) 16) -ne $NVRAM_FILE_GUID) { continue }
        $state = $b[$s + 0x8F]
        if (($state -band 0x10) -eq 0) { continue }          # DELETED flag set (erase polarity 1) -> retired store
        $live += , @($s, [BitConverter]::ToUInt32($b, $s + 0x20), $state)
    }
    if ($live.Count -ne 1) { return @{ error = "expected exactly one live NVRAM store, found $($live.Count)" } }
    $s, $fvLen, $state = $live[0]
    $o = $s + 0x90
    $hits = @()
    while ($o + 24 -lt $s + $fvLen -and [Text.Encoding]::ASCII.GetString($b, $o, 4) -eq 'NVAR') {
        $size = [BitConverter]::ToUInt16($b, $o + 4)
        if ($size -lt 10) { break }
        $attr = $b[$o + 9]
        # header record (not data-only), valid, ASCII name, GUID stored as an index
        if (($attr -band 0x88) -eq 0x80 -and ($attr -band 0x06) -eq 0x02 -and
            [Text.Encoding]::ASCII.GetString($b, $o + 11, 13) -eq "MemoryConfig`0") {
            $idx = $b[$o + 10]
            if ((Hex $b ($s + $fvLen - 16 * ($idx + 1)) 16) -eq $MEMCFG_GUID) { $hits += $o }
        }
        $o += $size
    }
    @{ store = $s; state = $state; hits = $hits }
}

# ---------------------------------------------------------------- 0. banner + administrator
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $Test -and -not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Please run this as Administrator (right-click Flash-UnlockedBIOS.bat > Run as administrator).' -ForegroundColor Red
    exit 1
}
$mode = if ($Restore) { 'RESTORE official GPD BIOS 1.16 code' } else { 'INSTALL unlocked BIOS 1.16 (3733 MT/s)' }
Say "WinMax Unlocked - $mode" 'Cyan'
Say "Work folder: $WorkDir"

# ---------------------------------------------------------------- 1. safety checks
Add-Type -AssemblyName System.Windows.Forms
$ps = [System.Windows.Forms.SystemInformation]::PowerStatus
Say ("Power: {0}, battery {1}%" -f $ps.PowerLineStatus, [int]($ps.BatteryLifePercent * 100))
if (-not $Test) {
    if ($ps.PowerLineStatus -ne 'Online') { Fail 'connect the charger first' }
    if ($ps.BatteryLifePercent -lt 0.30) { Fail 'charge the battery to at least 30% first' }
}
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
if (-not $Test -and $dg -and ($dg.SecurityServicesRunning -contains 2)) {
    Fail 'Memory Integrity (Core Isolation) is on. FPT cannot load its driver. Turn it off in Windows Security > Device security > Core isolation, reboot, and run this again.'
}
try {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On') {
        Say 'BitLocker / Device Encryption is ON. A firmware change will ask for the recovery key at boot unless it is suspended.' 'Yellow'
        Confirm 'Suspend BitLocker for one reboot?' 'YES'
        Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null
        Say 'BitLocker suspended for one reboot.'
    }
} catch { Log "BitLocker check: $($_.Exception.Message)" }

# ---------------------------------------------------------------- 2. FPTW64 from GPD's official package
$gpdBinBytes = $null
if (-not $FptPath) {
    $pkg = $GpdPackage
    if (-not $pkg) {
        $cands = @(Get-ChildItem -Path $Here, (Join-Path $env:USERPROFILE 'Downloads') -Filter 'WINMAX.1.16.GPD.*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.zip', '.exe' } | Sort-Object Extension -Descending)
        if ($cands) { $pkg = $cands[0].FullName }
    }
    if (-not $pkg -or -not (Test-Path $pkg)) {
        Fail "GPD's official BIOS package (WINMAX.1.16.GPD.zip) was not found. Download it from GPD (see README) and put it next to this script."
    }
    $x = Join-Path $WorkDir 'gpd-package'
    New-Item -ItemType Directory -Force $x | Out-Null
    $exe = $pkg
    if ($pkg -like '*.zip') { Expand-Archive -Path $pkg -DestinationPath $x -Force; $exe = Join-Path $x 'WINMAX.1.16.GPD.exe' }
    & "$env:SystemRoot\System32\tar.exe" -xf $exe -C $x FPTW64.exe WINMAX.1.16.GPD.bin 2>$null
    $FptPath = Join-Path $x 'FPTW64.exe'
    if (-not (Test-Path $FptPath)) { Fail "could not extract FPTW64.exe from $pkg" }
    $gb = Join-Path $x 'WINMAX.1.16.GPD.bin'
    if (Test-Path $gb) { $GpdBin = $gb }
}
$script:Fpt = $FptPath
if (-not $Yes) {
    if ((Get-FileHash $FptPath).Hash -ne $FPT_SHA) { Fail 'FPTW64.exe is not the expected version from GPD''s package' }
    $sig = Get-AuthenticodeSignature $FptPath
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Intel') { Fail 'FPTW64.exe signature check failed' }
}
Say 'FPTW64 found and verified (Intel-signed).'

# image to write
if ($Restore) {
    $officialPath = Join-Path $Here $OFFICIAL_NAME
    if (Test-Path $officialPath) {
        $newImage = [IO.File]::ReadAllBytes($officialPath)
        if ($newImage.Length -ne $REGION -or (Sha $newImage 0 $REGION) -ne $OFFICIAL_SHA) { Fail "$OFFICIAL_NAME is damaged (hash mismatch) - download it again" }
    } else {
        if (-not $GpdBin -or -not (Test-Path $GpdBin)) { Fail "restore needs $OFFICIAL_NAME or WINMAX.1.16.GPD.bin from GPD's package" }
        $gpdBinBytes = [IO.File]::ReadAllBytes($GpdBin)
        if ($gpdBinBytes.Length -ne 0x1000000) { Fail 'WINMAX.1.16.GPD.bin has the wrong size' }
        $newImage = New-Object byte[] $REGION
        [Array]::Copy($gpdBinBytes, 0x600000, $newImage, 0, $REGION)
    }
    $NEW_CODE_SHA = $OFFICIAL_CODE_SHA; $OLD_CODE_SHA = $UNLOCKED_CODE_SHA
} else {
    $imgPath = Join-Path $Here $IMAGE_NAME
    if (-not (Test-Path $imgPath)) { Fail "$IMAGE_NAME is missing next to this script" }
    $newImage = [IO.File]::ReadAllBytes($imgPath)
    if ($newImage.Length -ne $REGION -or (Sha $newImage 0 $REGION) -ne $IMAGE_SHA) { Fail "$IMAGE_NAME is damaged (hash mismatch) - download it again" }
    $NEW_CODE_SHA = $UNLOCKED_CODE_SHA; $OLD_CODE_SHA = $OFFICIAL_CODE_SHA
}
if ((Sha $newImage $CODE ($REGION - $CODE)) -ne $NEW_CODE_SHA) { Fail 'image to write failed its code check' }

# ---------------------------------------------------------------- 3. full backup
Say 'Making a full backup of the flash chip (16 MB, read twice) ...' 'Cyan'
$bk1 = Dump 'backup_full.rom' -Full
$bk2 = Dump 'backup_full_verify.rom' -Full
if ((Sha $bk1 0 $bk1.Length) -ne (Sha $bk2 0 $bk2.Length)) { Fail 'the two backup reads differ - the flash cannot be read reliably' }
Remove-Item (Join-Path $WorkDir 'backup_full_verify.rom')
Say "Backup OK: $(Join-Path $WorkDir 'backup_full.rom')  (copy it to a USB stick or another PC)" 'Green'

# ---------------------------------------------------------------- 4. what is on the chip now
$pre = Dump 'pre.rom'
$cur = Sha $pre $CODE ($REGION - $CODE)
if ($cur -eq $NEW_CODE_SHA) { Say 'The chip already has this BIOS - nothing to do.' 'Green'; exit 0 }
if ($cur -ne $OLD_CODE_SHA) {
    if ($Restore) { Fail 'the chip does not hold the unlocked BIOS, so there is nothing to restore with this tool' }
    Fail "the chip does not hold GPD's official BIOS 1.16 (October 2021). Install GPD's official update first (see README), then run this again."
}
for ($i = 0; $i -lt $CODE; $i++) { if ($pre[$i] -ne $bk1[0x600000 + $i]) { Fail 'NVRAM changed between the two reads - close other programs and run again' } }

# ---------------------------------------------------------------- 5. build the image: your NVRAM + new code
$final = New-Object byte[] $REGION
[Array]::Copy($pre, 0, $final, 0, $CODE)
[Array]::Copy($newImage, $CODE, $final, $CODE, $REGION - $CODE)
$mcNote = 'memory training kept'
if (-not $KeepMemoryTraining) {
    $mc = Find-MemoryConfig $final
    if ($mc.error) { Fail "NVRAM layout not recognised: $($mc.error)" }
    if ($mc.hits.Count -eq 0) { $mcNote = 'no saved memory training found (it will train fresh anyway)' }
    elseif ($mc.hits.Count -gt 1) { Fail 'more than one valid MemoryConfig record - NVRAM layout not recognised' }
    else {
        $final[$mc.hits[0] + 9] = $final[$mc.hits[0] + 9] -band 0x7F
        $mcNote = ('saved memory training marked deleted (store 0x{0:X}, record 0x{1:X})' -f $mc.store, $mc.hits[0])
    }
}
Say "NVRAM: your own NVRAM is kept; $mcNote."
$finalPath = Join-Path $WorkDir 'final.rom'
[IO.File]::WriteAllBytes($finalPath, $final)

Say ''
Say 'Ready to write the BIOS region (about 2 MB changes, 1-3 minutes).' 'Yellow'
Say 'Keep the charger connected, keep the lid OPEN, and do not press the power button until it says DONE.' 'Yellow'
Confirm 'Write the BIOS now?' 'FLASH'

# ---------------------------------------------------------------- 6. write, verify, retry / restore
Add-Type -Namespace GpdBios -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][GpdBios.Power]::SetThreadExecutionState([uint32]2147483651)    # keep system and display awake
$result = 'UNKNOWN'
$attempts = @('new', 'new', 'original', 'original')
$k = 0
$restored = $false
foreach ($what in $attempts) {
    $k++
    if ($what -eq 'original' -and $result -eq 'UNCHANGED') { break }
    if ($what -eq 'original') { $restored = $true }
    $src = if ($what -eq 'new') { $finalPath } else { Join-Path $WorkDir 'pre.rom' }
    Say "Writing ($what, attempt $k) ..." 'Cyan'
    try {
        $rc = Fpt "-f `"$src`" -bios -y" "write_$k.txt"
        $post = Dump "post_$k.rom"
        $pc = Sha $post $CODE ($REGION - $CODE)
        $same = $true
        for ($i = 0; $i -lt $REGION; $i++) { if ($post[$i] -ne $pre[$i]) { $same = $false; break } }
        $result = if ($pc -eq $NEW_CODE_SHA) { 'NEW' } elseif ($same) { 'UNCHANGED' } elseif ($pc -eq $OLD_CODE_SHA) { 'OLD' } else { 'MIXED' }
        Log "attempt $k ($what): FPT exit $rc, chip now $result"
    } catch { Log "attempt $k exception: $($_.Exception.Message)"; $result = 'UNKNOWN'; continue }
    if ($what -eq 'new' -and $result -eq 'NEW') { break }
    if ($what -eq 'new' -and $result -eq 'UNCHANGED' -and $k -eq 1) { break }
    if ($what -eq 'original' -and $result -in 'OLD', 'UNCHANGED') { break }
}

if ($result -eq 'NEW') {
    $postFull = Dump 'post_full.rom' -Full
    $descOk = (Sha $postFull 0 0x21000) -eq (Sha $bk1 0 0x21000)
    if (-not $descOk) { Say 'WARNING: the descriptor/EC area changed - do NOT reboot, keep this window open and get help.' 'Red'; while ($true) { Start-Sleep 60 } }
    [void][GpdBios.Power]::SetThreadExecutionState([uint32]2147483648)
    Say ''
    Say 'DONE - the BIOS was written and verified.' 'Green'
    Say 'Restart now. The first boot retrains the memory: a black screen for up to 1-2 minutes, maybe an extra restart. Do not power off.' 'Yellow'
    Say "Keep the backup: $(Join-Path $WorkDir 'backup_full.rom')"
    if (-not $Yes -and (Read-Host 'Restart now? (Y/N)') -match '^[Yy]') { Restart-Computer -Force }
    exit 0
}
if ($result -eq 'UNCHANGED' -and -not $restored) {
    [void][GpdBios.Power]::SetThreadExecutionState([uint32]2147483648)
    Fail 'FPT could not write the flash (it may be write-protected). Your BIOS is unchanged.'
}
if ($result -in 'OLD', 'UNCHANGED') {
    [void][GpdBios.Power]::SetThreadExecutionState([uint32]2147483648)
    Say 'The new BIOS did not verify, so your original BIOS was written back and verified. It is safe to keep using the machine.' 'Yellow'
    exit 3
}
Say 'CRITICAL: the flash content could not be verified. Do NOT restart or power off. Keep this window open (it keeps the PC awake) and ask for help.' 'Red'
Say "Your backup is $(Join-Path $WorkDir 'backup_full.rom'); try running this tool again with -Restore, or GPD's official updater." 'Red'
while ($true) { Start-Sleep 60 }
