<# : batch portion
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~f0" %*
exit /b %errorlevel%
: end batch / begin PowerShell #>

# set-wallpaper.ps1 — Self-installing wallpaper client for Windows lab PCs
# Lab ID: {{LAB_ID}} | Polling interval: {{INTERVAL_MINUTES}} minutes
# Generated from admin panel — will auto-elevate to Administrator

param([switch]$RunOnly)

# --- Self-elevate to Administrator if needed (skip in RunOnly mode) ---
if (-not $RunOnly) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        } catch {
            Write-Host "Instalasi dibatalkan: permission Administrator ditolak." -ForegroundColor Red
            Write-Host "Script ini membutuhkan hak Administrator untuk mendaftarkan Scheduled Task."
            pause
        }
        exit
    }
}

$ErrorActionPreference = "Stop"

# --- Config (injected from server) ---
$LabId            = "{{LAB_ID}}"
$IntervalMinutes  = {{INTERVAL_MINUTES}}
$BaseUrl          = "https://scriptman.budiluhur.web.id/api/labscript"
$DataDir          = "C:\ProgramData\LabScriptManager"
$ScriptDest       = "$DataDir\set-wallpaper.ps1"
$LauncherDest     = "$DataDir\launcher.vbs"
$ConfigFile       = "$DataDir\config.txt"
$VersionFile      = "$DataDir\version.txt"
$IntervalFile     = "$DataDir\current-interval.txt"
$WallpaperFile    = "$DataDir\wallpaper.jpg"
$TaskName         = "LabScriptManager"

# --- VBS launcher content (window = 0 = fully hidden) ---
$VbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$ScriptDest"" -RunOnly", 0, False
"@

# --- Update Scheduled Task interval if server changed it ---
function Update-IntervalFromServer {
    try {
        $Response = Invoke-RestMethod -Uri "$BaseUrl/interval" -Method Get -TimeoutSec 10
        $ServerInterval = [int]$Response.interval_minutes
    } catch {
        return
    }

    if ($ServerInterval -lt 5) { return }

    $LocalInterval = $IntervalMinutes
    if (Test-Path $IntervalFile) {
        $LocalInterval = [int](Get-Content $IntervalFile -Raw).Trim()
    }

    if ($ServerInterval -eq $LocalInterval) { return }

    try {
        $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $ServerInterval)
        Set-ScheduledTask -TaskName $TaskName -Trigger $Trigger | Out-Null
        $ServerInterval | Out-File -FilePath $IntervalFile -NoNewline -Encoding ascii
    } catch {
        # fail silently, will retry next cycle
    }
}

# --- Send checkin to server ---
function Send-Checkin {
    try {
        $LocalVersion = 0
        if (Test-Path $VersionFile) {
            $LocalVersion = [int](Get-Content $VersionFile -Raw).Trim()
        }

        $Body = @{
            hostname = $env:COMPUTERNAME
            lab_id = $LabId
            local_version = $LocalVersion
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$BaseUrl/checkin" -Method Post -Body $Body `
            -ContentType "application/json" -TimeoutSec 10 | Out-Null
    } catch {
        # checkin failure must not block sync
    }
}

# --- Wallpaper sync function ---
function Sync-Wallpaper {
    if (!(Test-Path $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }

    $LocalVersion = 0
    if (Test-Path $VersionFile) {
        $LocalVersion = [int](Get-Content $VersionFile -Raw).Trim()
    }

    try {
        $VersionUrl = "$BaseUrl/version?lab_id=$LabId"
        $Response = Invoke-RestMethod -Uri $VersionUrl -Method Get -TimeoutSec 15
    } catch {
        Write-Host "Failed to check version: $($_.Exception.Message)"
        return
    }

    $ServerVersion = $Response.version

    if ($null -eq $ServerVersion) {
        Write-Host "No active wallpaper on server"
        return
    }

    if ($ServerVersion -eq $LocalVersion) {
        Write-Host "Wallpaper up to date (version $LocalVersion)"
        return
    }

    Write-Host "New wallpaper available: server v$ServerVersion vs local v$LocalVersion"

    try {
        $CurrentUrl = "$BaseUrl/current?lab_id=$LabId"
        Invoke-WebRequest -Uri $CurrentUrl -OutFile $WallpaperFile -TimeoutSec 60
    } catch {
        Write-Host "Failed to download wallpaper: $($_.Exception.Message)"
        return
    }

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
                SystemParametersInfo(0x0014, 0, path, 0x03);
            }
        }
"@ -ErrorAction SilentlyContinue

        [Wallpaper]::Set($WallpaperFile)
        Write-Host "Wallpaper applied: $WallpaperFile"
    } catch {
        Write-Host "Failed to set wallpaper: $($_.Exception.Message)"
        return
    }

    $ServerVersion | Out-File -FilePath $VersionFile -NoNewline -Encoding ascii
    Write-Host "Version updated to $ServerVersion"
}

# --- Extract pure PS1 from this polyglot file and save to destination ---
function Install-Script {
    $sourceContent = Get-Content -Path $PSCommandPath -Raw
    # Remove batch portion (everything before the closing #> marker line)
    $ps1Content = $sourceContent -replace '(?s)^.*?: end batch / begin PowerShell #>\r?\n', ''
    $ps1Content | Out-File -FilePath $ScriptDest -Encoding utf8 -Force
}

# --- If RunOnly: check interval, sync, checkin, exit (100% non-interactive) ---
if ($RunOnly) {
    Update-IntervalFromServer
    Sync-Wallpaper
    Send-Checkin
    exit 0
}

# --- Installation (interactive, run manually by admin) ---
Write-Host "=== LabScriptManager Installer ===" -ForegroundColor Cyan
Write-Host "Lab ID       : $LabId"
Write-Host "Interval     : $IntervalMinutes menit"
Write-Host ""

if (!(Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

# Extract pure PS1 (without batch header) to permanent location
Install-Script
Write-Host "[OK] Script installed to $ScriptDest" -ForegroundColor Green

$VbsContent | Out-File -FilePath $LauncherDest -Encoding ascii -Force
Write-Host "[OK] VBS launcher created: $LauncherDest" -ForegroundColor Green

$LabId | Out-File -FilePath $ConfigFile -NoNewline -Encoding ascii
Write-Host "[OK] Config written (lab_id=$LabId)" -ForegroundColor Green

$IntervalMinutes | Out-File -FilePath $IntervalFile -NoNewline -Encoding ascii

$Action = New-ScheduledTaskAction -Execute "wscript.exe" `
    -Argument "`"$LauncherDest`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
    Write-Host "[OK] Scheduled Task updated (interval: $IntervalMinutes menit)" -ForegroundColor Green
} else {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
        -RunLevel Highest -Description "LabScriptManager — auto-update lab wallpaper from server" | Out-Null
    Write-Host "[OK] Scheduled Task created (interval: $IntervalMinutes menit)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Menjalankan sinkronisasi pertama..." -ForegroundColor Yellow
Sync-Wallpaper
Send-Checkin

Write-Host ""
Write-Host "=== Instalasi selesai ===" -ForegroundColor Cyan
Write-Host "Lab ID       : $LabId"
Write-Host "Interval     : setiap $IntervalMinutes menit"
Write-Host "Script       : $ScriptDest"
Write-Host "Launcher     : $LauncherDest"
Write-Host "Task         : $TaskName"
pause
