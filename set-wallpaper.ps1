# set-wallpaper.ps1 — Wallpaper client for Windows lab PCs
# Polls server, downloads and applies wallpaper if version changed

$ErrorActionPreference = "Stop"

$BaseUrl    = "https://scriptman.budiluhur.web.id/api/labscript"
$DataDir    = "C:\ProgramData\LabScriptManager"
$ConfigFile = "$DataDir\config.txt"
$VersionFile = "$DataDir\version.txt"
$WallpaperFile = "$DataDir\wallpaper.jpg"

# Ensure data directory exists
if (!(Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

# Read lab_id from config
if (!(Test-Path $ConfigFile)) {
    Write-Host "Config file not found: $ConfigFile"
    Write-Host "Create it with just the lab_id number, e.g.: 1"
    exit 0
}
$LabId = (Get-Content $ConfigFile -Raw).Trim()

# Read local version (0 if not exists)
$LocalVersion = 0
if (Test-Path $VersionFile) {
    $LocalVersion = [int](Get-Content $VersionFile -Raw).Trim()
}

# Check server version
try {
    $VersionUrl = "$BaseUrl/version?lab_id=$LabId"
    $Response = Invoke-RestMethod -Uri $VersionUrl -Method Get -TimeoutSec 15
} catch {
    Write-Host "Failed to check version: $($_.Exception.Message)"
    exit 0
}

$ServerVersion = $Response.version

# No active wallpaper on server
if ($null -eq $ServerVersion) {
    Write-Host "No active wallpaper on server"
    exit 0
}

# Compare versions
if ($ServerVersion -eq $LocalVersion) {
    Write-Host "Wallpaper up to date (version $LocalVersion)"
    exit 0
}

Write-Host "New wallpaper available: server v$ServerVersion vs local v$LocalVersion"

# Download wallpaper
try {
    $CurrentUrl = "$BaseUrl/current?lab_id=$LabId"
    Invoke-WebRequest -Uri $CurrentUrl -OutFile $WallpaperFile -TimeoutSec 60
} catch {
    Write-Host "Failed to download wallpaper: $($_.Exception.Message)"
    exit 0
}

# Set wallpaper via Win32 API
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class Wallpaper {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int SystemParametersInfo(
            int uAction, int uParam, string lpvParam, int fuWinIni
        );

        public static void Set(string path) {
            // SPI_SETDESKWALLPAPER = 0x0014
            // SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 0x03
            SystemParametersInfo(0x0014, 0, path, 0x03);
        }
    }
"@ -ErrorAction SilentlyContinue

    [Wallpaper]::Set($WallpaperFile)
    Write-Host "Wallpaper applied: $WallpaperFile"
} catch {
    Write-Host "Failed to set wallpaper: $($_.Exception.Message)"
    exit 0
}

# Save new version
$ServerVersion | Out-File -FilePath $VersionFile -NoNewline -Encoding ascii
Write-Host "Version updated to $ServerVersion"
