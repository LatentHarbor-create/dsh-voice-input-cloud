@echo off
setlocal
if "%~1"=="" goto menu
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-voice.ps1" %*
set "launcherExit=%ERRORLEVEL%"
if not "%launcherExit%"=="0" powershell.exe -NoLogo -NoProfile -Command "[void](Read-Host 'Press Enter to close')"
exit /b %launcherExit%

:menu
title DSH Voice Service Control
if exist "%~dp0paths.json" goto localMenu
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-voice.ps1" -Menu
exit /b %ERRORLEVEL%

:localMenu
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-voice.ps1" -Menu -SettingsPath "%~dp0paths.json"
exit /b %ERRORLEVEL%
