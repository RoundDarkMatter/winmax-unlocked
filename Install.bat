@echo off
rem Starts the installer as Administrator. Read README.md first.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0WinMaxBIOS.ps1\"'"
