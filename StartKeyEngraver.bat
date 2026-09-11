@echo off
rem Launches LightBurn hidden/minimized (if not already running), then the kiosk.

set LIGHTBURN=C:\Program Files\LightBurn\LightBurn.exe

tasklist /FI "IMAGENAME eq LightBurn.exe" | find /I "LightBurn.exe" >nul
if not errorlevel 1 goto kiosk

if not exist "%LIGHTBURN%" (
    echo LightBurn.exe not found at %LIGHTBURN% - edit this .bat and fix the path.
    pause
    exit /b 1
)
start "" /min "%LIGHTBURN%"
rem give LightBurn time to boot and connect to the laser
timeout /t 12 /nobreak >nul

:kiosk
rem console output (including any red PowerShell errors) is also saved to console.log
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0KeyEngraver.ps1" > "%~dp0console.log" 2>&1
type "%~dp0console.log"
echo.
echo Kiosk closed. Any errors above are also saved in console.log and engraver.log in this folder.
pause
