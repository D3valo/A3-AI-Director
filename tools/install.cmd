@echo off
rem Builds and installs the director mod (see install.ps1). Works from Command Prompt, PowerShell or a double-click,
rem which would otherwise open the .ps1 in Notepad.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
