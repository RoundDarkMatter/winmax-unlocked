# GPD Win Max (2020) – Unlocked BIOS 1.16 with LPDDR4X-3733

An updated take on the **unlocked 3733 MHz BIOS for the original GPD Win Max (2020, i5-1035G7)**, with **WinMax BIOS Tool**, a guided
installer that backs up your chip, keeps your own settings, verifies everything it writes, and can undo itself.

## Performance

GPD's official BIOS runs the soldered LPDDR4X at **3200 MT/s**, below the **3733 MT/s** the chips are rated for. This
BIOS runs them at their rated speed:

| | Official BIOS | This BIOS | Change |
|---|---|---|---|
| Memory speed | 3200 MT/s | **3733 MT/s** | **+16.7 %** |
| Peak memory bandwidth (128-bit LPDDR4X) | 51.2 GB/s | **59.7 GB/s** | **+16.7 %** |
| Access latency (tAA) | 17.50 ns | 17.14 ns | -2 % |

The integrated Iris Plus G7 graphics share this memory and are usually limited by its bandwidth, so games and other
GPU work benefit most. Real-world gains depend on the workload and are generally smaller than the 16.7 % bandwidth
increase. CPU-only tasks change little.

> ⚠️ **Flashing a modified BIOS can brick your device.** If the write fails *and* the machine is turned off, or if your
> RAM cannot run at 3733 MT/s, the only recovery is an external SPI programmer. Use this at your own risk.

## Credits

- **[p3k163](https://github.com/p3k163)** – created the original
  [GPD-Win-Max-3733MHz-Unlocked-BIOS](https://github.com/p3k163/GPD-Win-Max-3733MHz-Unlocked-BIOS) mod: the menu
  unlock and the 3733 MT/s memory change. **All three firmware changes in this repository are ported byte-for-byte
  from that work.** This project only re-applies them to GPD's newer build and adds a safer installer.
- **GPD (Shenzhen GPD Technology Co., Ltd.)** – the original firmware (BIOS 1.16).
- **Intel** – the Flash Programming Tool (FPTW64). It is **not** included here; the installer extracts it from GPD's
  official update package.

## What is different from the original mod

| | Original p3k163 mod (2021) | This version |
|---|---|---|
| Base firmware | GPD 1.16 build from **11/25/2020** | GPD 1.16 build from **10/19/2021** (GPD's latest, the Windows 11 / TPM release) |
| Your settings (NVRAM) | Replaced with the mod author's own NVRAM (their settings, boot entries and saved RAM training) | **Your own NVRAM is kept**; only the saved RAM training is reset so it retrains at 3733 |
| Flashing | Manual `fptw64` command | Guided installer: backup, checks, verified write, automatic retry/restore |
| Undo | Reflash a backup by hand | `Restore.bat` puts GPD's official code back (keeps your settings) |

## What the mod changes

Only three modules differ from GPD's official BIOS 1.16 (10/19/2021):

1. **Setup** – the hidden *Advanced* submenus (CPU, Power & Performance, Thermal, PCH-FW, ACPI, USB, PCI, NVMe, …) and
   the *Save & Exit* options are visible.
2. **AMITSE** – the **Chipset** tab is visible (memory, graphics, PCH-IO, SATA, serial IO settings).
3. **PlatformInitPreMem** – the built-in LPDDR4X memory table (SPD) allows **3733 MT/s** instead of 3200 MT/s
   (the speed the RAM chips are rated for). About 16 % more memory bandwidth, which mostly helps the iGPU.

Everything else is GPD's firmware unchanged. The ME firmware, EC firmware and flash descriptor are never written.

## Requirements

- GPD Win Max **2020** (model G1619-01, i5-1035G7). **Not** for the Win Max 2021 or Win Max 2.
- GPD's **official BIOS 1.16 (October 2021)** already installed. Download `WINMAX.1.16.GPD.zip` from GPD
  (linked from GPD's [Windows 11 BIOS announcement](https://twitter.com/softwincn/status/1458365812671082500) →
  [Google Drive](https://drive.google.com/file/d/1btxdsDfB4jMxIKk1Tdiwpk0i9bWaHuZi/view?usp=sharing)) and run it once
  if you are on an older version. Keep the zip – the installer needs it.
- Windows 10/11, charger connected, battery above 30 %.
- **Memory Integrity** (Windows Security → Device security → Core isolation) **off** – the flash tool cannot load its
  driver otherwise.
- If BitLocker / Device Encryption is on, the installer offers to suspend it for one reboot.

## How to install

1. Download this repository (Code → Download ZIP) and extract it.
2. Put `WINMAX.1.16.GPD.zip` (GPD's official package) in the same folder (or leave it in your Downloads folder).
3. Double-click **`Install.bat`** and accept the administrator prompt.
4. The installer will:
   - make a **full backup** of the flash chip (read twice and compared) in a `work-…` folder – copy it somewhere safe;
   - check that you are on GPD's official 1.16 and stop if not;
   - ask you to type `FLASH`, then write the BIOS, read it back and verify it.
5. **While it writes (1–3 minutes): keep the charger in, keep the lid open, don't press the power button.**
6. Restart when it says **DONE**. The first boot retrains the memory: a black screen for up to 1–2 minutes and
   possibly one extra restart is normal. Don't power it off.
7. Check the result: Task Manager → Performance → Memory → *Speed: 3733 MT/s*.

If the write does not verify, the installer retries and then writes your original BIOS back automatically. It never
reboots by itself.

## Undo

Double-click **`Restore.bat`**. It writes GPD's original 1.16 code back (from `WINMAX.1.16.OFFICIAL.rom`)
and keeps your settings. The memory retrains at 3200 MT/s on the next boot.

`WINMAX.1.16.OFFICIAL.rom` is GPD's original BIOS region with a clean factory NVRAM (no personal data). Flashing it
directly with `FPTW64 -f WINMAX.1.16.OFFICIAL.rom -bios` also restores stock, but resets all BIOS settings and boot
entries to factory defaults.

## If something goes wrong

- **Unstable at 3733** (crashes, freezes): enter the BIOS and go to *Chipset → System Agent (SA) Configuration →
  Memory Configuration*. Set **Maximum Memory Frequency = 3200** *and* **Fast Boot = Disabled** for one boot (otherwise
  the saved 3733 training is reused), then turn Fast Boot back on. Or run `Restore.bat`.
- **Does not boot at all** (black screen every time): write the `backup_full.rom` the installer made with an SPI
  programmer (CH341A **with 3.3 V I/O** + SOIC-8 clip; the chip is a Winbond W25Q128, JEDEC ID EF4018). Disconnect the
  battery first.
- **Do not** use GPD's own updater or AMI AFU to flash `WINMAX.1.16.UNLOCKED.3733.rom` – its signature check rejects
  modified images. Flash it only with this installer (or `FPTW64 -f <file> -bios`).

Be careful with the unlocked menus: some options can make the machine unbootable. Change only what you understand.

## Files

| File | Purpose |
|---|---|
| `WINMAX.1.16.UNLOCKED.3733.rom` | BIOS region image (10 MB): GPD 1.16 (10/19/2021) + the three changes, GPD's factory NVRAM |
| `WINMAX.1.16.OFFICIAL.rom` | GPD's original, unmodified BIOS 1.16 (10/19/2021) region (10 MB) with GPD's clean factory NVRAM, byte-identical to the BIOS region inside GPD's `WINMAX.1.16.GPD.bin`. Used by the restore option; also a clean reference/recovery image |
| `WinMaxBIOS.ps1` | The installer |
| `Install.bat` | Starts the installer as administrator |
| `Restore.bat` | Starts the installer in restore mode |
| `SHA256SUMS.txt` | Checksums |

## Technical notes

- The BIOS region is written with `FPTW64 -f final.rom -bios -y`, where `final.rom` = your live NVRAM area
  (region `0x0–0x6FFFF`) + the image's code area. FPT only reprograms the 4 KB blocks that differ (about 2 MB).
- The saved MRC training (`MemoryConfig`, GUID `C94F8C4D-9B9A-45FE-8A55-238B67302643`) is deleted the way AMI's NVRAM
  driver deletes variables (clearing the record's valid bit) in the **live** NVRAM store. Units can have one store
  (`0x0`) or two (`0x0` retired + `0x30000` live); the installer finds the live one.
- The recompressed main firmware volume was verified by running the firmware's own LZMA decoders under emulation.
  Intel Boot Guard is not provisioned on this model, so modified firmware is not rejected at boot.

## Disclaimer

Provided as-is, without warranty. Not affiliated with or endorsed by GPD or Intel. The firmware remains the property of
its respective owners.
