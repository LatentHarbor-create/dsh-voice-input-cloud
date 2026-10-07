@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-voice.ps1" %*
set "launcherExit=%ERRORLEVEL%"
if not "%launcherExit%"=="0" pause
exit /b %launcherExit%
