@echo off
rem Starts a director session (see start-session.ps1). Works from Command Prompt, PowerShell or a double-click,
rem which would otherwise open the .ps1 in Notepad. Arguments are passed on, e.g. -Personality cinematic -DryRun.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-session.ps1" %*
if errorlevel 1 pause
