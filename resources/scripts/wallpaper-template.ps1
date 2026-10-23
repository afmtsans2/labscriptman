# set-wallpaper.ps1 - Wallpaper client for Windows lab PCs
# Lab ID: {{LAB_ID}} | Polling interval: {{INTERVAL_MINUTES}} minutes
# Generated from admin panel

param([switch]$RunOnly)

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
        $TriggerInterval = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $ServerInterval)
        $TriggerBoot = New-ScheduledTaskTrigger -AtStartup
        Set-ScheduledTask -TaskName $TaskName -Trigger @($TriggerBoot, $TriggerInterval) | Out-Null
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

    # Set wallpaper for ALL user accounts on this PC
    try {
        $WallpaperBmp = "$DataDir\wallpaper.bmp"
        Copy-Item -Path $WallpaperFile -Destination $WallpaperBmp -Force

        # Helper: write wallpaper keys to a registry path
        function Set-WallpaperReg($RegPath) {
            if (Test-Path $RegPath) {
                Set-ItemProperty -Path $RegPath -Name Wallpaper      -Value $WallpaperBmp -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $RegPath -Name WallpaperStyle -Value "10"          -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $RegPath -Name TileWallpaper  -Value "0"           -ErrorAction SilentlyContinue
            }
        }

        # 1. Users currently logged in — hive already mounted in HKU
        $LoadedSIDs = Get-ChildItem "Registry::HKU" |
            Where-Object { $_.Name -match '^HKEY_USERS\\S-1-5-21-' -and $_.Name -notmatch '_Classes$' } |
            ForEach-Object { $_.Name -replace '^HKEY_USERS\\', '' }

        foreach ($SID in $LoadedSIDs) {
            Set-WallpaperReg "Registry::HKU\$SID\Control Panel\Desktop"
        }

        # 2. Users NOT currently logged in — load NTUSER.DAT manually
        $ProfileList = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" |
            Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $LoadedSIDs -notcontains $_.PSChildName }

        foreach ($Profile in $ProfileList) {
            $NtUser = Join-Path $Profile.ProfileImagePath "NTUSER.DAT"
            if (-not (Test-Path $NtUser)) { continue }

            $TempHive = "HKU\LSM_Temp_$($Profile.PSChildName)"
            try {
                reg load $TempHive $NtUser | Out-Null
                Set-WallpaperReg "Registry::$TempHive\Control Panel\Desktop"
            } catch {}
            finally {
                [gc]::Collect()
                reg unload $TempHive | Out-Null
            }
        }

        # 3. Apply immediately for current session
        Set-WallpaperReg "HKCU:\Control Panel\Desktop"
        try {
            Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class WP {
                [DllImport("user32.dll", CharSet = CharSet.Auto)]
                public static extern int SystemParametersInfo(int a, int b, string c, int d);
                public static void Set(string p) { SystemParametersInfo(0x0014, 0, p, 0x03); }
            }
"@ -ErrorAction SilentlyContinue
            [WP]::Set($WallpaperBmp)
        } catch {}

        # Broadcast desktop refresh to active session
        Start-Process -FilePath "RUNDLL32.EXE" -ArgumentList "user32.dll,UpdatePerUserSystemParameters ,1 ,True" -NoNewWindow -Wait -ErrorAction SilentlyContinue

        Write-Host "Wallpaper applied to $($LoadedSIDs.Count + $ProfileList.Count) user(s): $WallpaperBmp"
    } catch {
        Write-Host "Failed to set wallpaper: $($_.Exception.Message)"
        return
    }

    $ServerVersion | Out-File -FilePath $VersionFile -NoNewline -Encoding ascii
    Write-Host "Version updated to $ServerVersion"
}

# --- Self-update script from server (RunOnly mode) ---
function Update-Script {
    try {
        $TmpScript = "$DataDir\set-wallpaper-new.ps1"
        Invoke-WebRequest -Uri "$BaseUrl/script-raw/$LabId" -OutFile $TmpScript -TimeoutSec 30
        # Only replace if download succeeded and file is non-empty
        if ((Get-Item $TmpScript).Length -gt 100) {
            Move-Item -Path $TmpScript -Destination $ScriptDest -Force
        }
    } catch {
        # fail silently, keep using current script
    }
}

# --- If RunOnly: self-update, check interval, sync, checkin, exit ---
if ($RunOnly) {
    Update-Script
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

# Download fresh PS1 from server and save to permanent location
try {
    $ScriptUrl = "$BaseUrl/script-raw/$LabId"
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $ScriptDest -TimeoutSec 30
    Write-Host "[OK] Script downloaded to $ScriptDest" -ForegroundColor Green
} catch {
    # Fallback: copy current script if server unreachable
    if ($PSCommandPath) {
        Copy-Item -Path $PSCommandPath -Destination $ScriptDest -Force
    }
    Write-Host "[OK] Script copied to $ScriptDest (offline fallback)" -ForegroundColor Yellow
}

$VbsContent | Out-File -FilePath $LauncherDest -Encoding ascii -Force
Write-Host "[OK] VBS launcher created: $LauncherDest" -ForegroundColor Green

$LabId | Out-File -FilePath $ConfigFile -NoNewline -Encoding ascii
Write-Host "[OK] Config written (lab_id=$LabId)" -ForegroundColor Green

$IntervalMinutes | Out-File -FilePath $IntervalFile -NoNewline -Encoding ascii

$Action = New-ScheduledTaskAction -Execute "wscript.exe" `
    -Argument "`"$LauncherDest`""
$TriggerInterval = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$TriggerBoot = New-ScheduledTaskTrigger -AtStartup
$Triggers = @($TriggerBoot, $TriggerInterval)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Triggers -Settings $Settings | Out-Null
    Write-Host "[OK] Scheduled Task updated (interval: $IntervalMinutes menit + AtStartup)" -ForegroundColor Green
} else {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Triggers -Settings $Settings `
        -RunLevel Highest -Description "LabScriptManager - auto-update lab wallpaper from server" | Out-Null
    Write-Host "[OK] Scheduled Task created (interval: $IntervalMinutes menit + AtStartup)" -ForegroundColor Green
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
