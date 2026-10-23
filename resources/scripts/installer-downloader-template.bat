@echo off
:: LAUNCHER - LabScriptManager Installer
:: Downloads and runs the PowerShell installer from server

:: Cek privilege admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Meminta hak Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo =======================================
echo   LabScriptManager Installer
echo   Lab ID: {{LAB_ID}}
echo =======================================
echo.

echo Mendownload installer dari server...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://scriptman.budiluhur.web.id/api/labscript/script-raw/{{LAB_ID}}' -OutFile '%TEMP%\wallpaper-installer.ps1' -TimeoutSec 30"

if not exist "%TEMP%\wallpaper-installer.ps1" (
    echo.
    echo GAGAL: Tidak bisa download installer dari server.
    echo Periksa koneksi internet dan coba lagi.
    pause
    exit /b 1
)

echo Menjalankan installer...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\wallpaper-installer.ps1"

del "%TEMP%\wallpaper-installer.ps1" >nul 2>&1
pause
