@echo off
setlocal
rem dsh-boot-suite maintenance entry for Windows.
rem This file must stay pure ASCII: cmd.exe decodes batch files with the system ANSI
rem code page (GBK on Chinese Windows), so non-ASCII bytes would turn into mojibake.
rem All Chinese menu text lives in tools\windows\setup.ps1.
rem Entry script: tools/windows/setup.ps1
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\setup.ps1"
if errorlevel 1 echo [x] setup.ps1 exited with an error. Read the messages above.
echo.
pause
