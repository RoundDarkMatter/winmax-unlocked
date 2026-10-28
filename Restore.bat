@echo off
rem Puts GPD's official BIOS 1.16 code back (keeps your settings). Read README.md first.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0WinMaxBIOS.ps1\" -Restore'"
