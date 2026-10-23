# =========================================================
# ONE-CLICK INSTALLER - MULTI UNIT
# Sekolah Budi Luhur - LabScriptManager
# =========================================================

$ErrorActionPreference = "Stop"

$baseUrl  = "{{BASE_URL}}"
$autoUnit = "{{AUTO_UNIT}}"
$tempDir  = "C:\Temp\Installer"
$logFile  = "$tempDir\install_log.txt"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# =========================================================
# FUNGSI - Download dengan progress percentage
# =========================================================
function Get-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$DisplayName
    )

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "Mozilla/5.0"
    $response = $request.GetResponse()
    $totalBytes = $response.ContentLength
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object System.IO.FileStream $OutFile, ([System.IO.FileMode]::Create)

    $buffer = New-Object byte[] 1MB
    $totalRead = 0
    $lastPercent = -1

    try {
        do {
            $read = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $targetStream.Write($buffer, 0, $read)
                $totalRead += $read

                if ($totalBytes -gt 0) {
                    $percent = [math]::Floor(($totalRead / $totalBytes) * 100)
                    if ($percent -ne $lastPercent) {
                        $mbRead  = [math]::Round($totalRead / 1MB, 1)
                        $mbTotal = [math]::Round($totalBytes / 1MB, 1)
                        Write-Progress -Activity "Download: $DisplayName" -Status "$percent% ($mbRead MB / $mbTotal MB)" -PercentComplete $percent
                        $lastPercent = $percent
                    }
                }
            }
        } while ($read -gt 0)
    } finally {
        $targetStream.Close()
        $responseStream.Close()
        $response.Close()
        Write-Progress -Activity "Download: $DisplayName" -Completed
    }
}

# =========================================================
# FUNGSI - Tunggu dialog muncul lalu kirim SendKeys
# =========================================================
function Confirm-DialogWindow {
    param(
        [string]$TitleContains,
        [string]$Keys = "{ENTER}",
        [int]$TimeoutSeconds = 30
    )

    Add-Type -AssemblyName System.Windows.Forms
    $shell = New-Object -ComObject WScript.Shell
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $done = $false

    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds -and -not $done) {
        $target = Get-Process | Where-Object {
            $_.MainWindowTitle -and $_.MainWindowTitle -like "*$TitleContains*"
        } | Select-Object -First 1

        if ($target) {
            Start-Sleep -Milliseconds 400
            $activated = $shell.AppActivate($target.Id)
            if ($activated) {
                Start-Sleep -Milliseconds 400
                [System.Windows.Forms.SendKeys]::SendWait($Keys)
                $done = $true
            }
        } else {
            Start-Sleep -Milliseconds 500
        }
    }

    return $done
}

# =========================================================
# FUNGSI - Download file installer/tambahan (switchable)
# =========================================================
function Get-InstallerFile {
    param(
        [string]$Url,
        [string]$FileName,
        [string]$DisplayName
    )

    $localPath = Join-Path $tempDir $FileName
    $localDir  = Split-Path $localPath -Parent
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
    }

    Get-FileWithProgress -Url $Url -OutFile $localPath -DisplayName $DisplayName
    return $localPath
}

# =========================================================
# LOOP UTAMA
# =========================================================
$keepRunning = $true

while ($keepRunning) {

    # =====================================================
    # STEP 1 - Ambil daftar unit dari server
    # =====================================================
    $unitList = $null
    try {
        $rawJson = Invoke-WebRequest -Uri "$baseUrl/units" -UseBasicParsing | Select-Object -ExpandProperty Content
        $unitList = $rawJson | ConvertFrom-Json
    } catch {
        Write-Host ""
        Write-Host "GAGAL mengambil daftar unit dari server!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Read-Host "Tekan ENTER untuk keluar"
        exit 1
    }

    if (-not $unitList -or $unitList.Count -eq 0) {
        Write-Host "Tidak ada unit yang tersedia di server." -ForegroundColor Red
        Read-Host "Tekan ENTER untuk keluar"
        exit 1
    }

    # =====================================================
    # STEP 2 - Pilih Unit (atau auto-select jika ada parameter)
    # =====================================================
    $selectedUnit = $null
    $isOther      = $false
    $isAktivasi   = $false
    $isWallpaper  = $false

    if ($autoUnit -and $autoUnit -ne "") {
        $selectedUnit = $unitList | Where-Object { $_.slug -eq $autoUnit } | Select-Object -First 1
        if (-not $selectedUnit) {
            Write-Host "Unit '$autoUnit' tidak ditemukan di server!" -ForegroundColor Red
            $autoUnit = ""
        }
    }

    if (-not $selectedUnit) {
        Clear-Host
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host "   ONE-CLICK INSTALLER - SEKOLAH BUDI LUHUR"          -ForegroundColor Cyan
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Pilih Unit:" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $unitList.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $unitList[$i].name)
        }
        $otherIndex      = $unitList.Count + 1
        $activasiIndex   = $unitList.Count + 2
        $wallpaperIndex  = $unitList.Count + 3
        Write-Host ("  [{0}] Other (Pilih Aplikasi Sendiri)" -f $otherIndex)
        Write-Host ("  [{0}] Aktivasi Windows & Office" -f $activasiIndex)
        Write-Host ("  [{0}] Set Wallpaper Lab" -f $wallpaperIndex)
        Write-Host ("  [0] Keluar")
        Write-Host ""

        $selectedIndex = -1
        $validInput = $false
        while (-not $validInput) {
            $inputVal = Read-Host "Masukkan nomor (0-$wallpaperIndex)"
            if ([int]::TryParse($inputVal, [ref]$selectedIndex)) {
                if ($selectedIndex -eq 0) {
                    $keepRunning = $false
                    $validInput = $true
                } elseif ($selectedIndex -ge 1 -and $selectedIndex -le $wallpaperIndex) {
                    $validInput = $true
                }
            }
        }

        if (-not $keepRunning) { break }

        $isOther     = ($selectedIndex -eq $otherIndex)
        $isAktivasi  = ($selectedIndex -eq $activasiIndex)
        $isWallpaper = ($selectedIndex -eq $wallpaperIndex)
        if (-not $isOther -and -not $isAktivasi -and -not $isWallpaper) {
            $selectedUnit = $unitList[$selectedIndex - 1]
        }
    }

    # =====================================================
    # STEP 3a - Aktivasi Windows & Office (MAS)
    # =====================================================
    if ($isAktivasi) {
        Write-Host ""
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host "   AKTIVASI WINDOWS & OFFICE"                         -ForegroundColor Cyan
        Write-Host "   Microsoft Activation Scripts (MAS)"                -ForegroundColor Cyan
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[*] Menjalankan MAS dari massgrave.dev ..." -ForegroundColor Yellow
        Write-Host ""

        try {
            Invoke-RestMethod https://get.activated.win | Invoke-Expression
        } catch {
            Write-Host ""
            Write-Host "GAGAL menjalankan MAS: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "Coba jalankan manual di PowerShell (sebagai Admin):" -ForegroundColor Yellow
            Write-Host '  irm https://get.activated.win | iex' -ForegroundColor White
        }

        Write-Host ""
        Read-Host "Tekan ENTER untuk kembali ke menu awal"
        continue
    }

    # =====================================================
    # STEP 3b - Set Wallpaper Lab
    # =====================================================
    if ($isWallpaper) {
        Write-Host ""
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host "   SET WALLPAPER LAB"                                 -ForegroundColor Cyan
        Write-Host "=================================================="  -ForegroundColor Cyan
        Write-Host ""

        # Ambil daftar lab dari server
        $labList = $null
        try {
            $rawJson = Invoke-WebRequest -Uri "$baseUrl/labs" -UseBasicParsing | Select-Object -ExpandProperty Content
            $labList = $rawJson | ConvertFrom-Json
        } catch {
            Write-Host "GAGAL mengambil daftar lab dari server!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host ""
            Read-Host "Tekan ENTER untuk kembali ke menu awal"
            continue
        }

        if (-not $labList -or $labList.Count -eq 0) {
            Write-Host "Tidak ada lab yang tersedia di server." -ForegroundColor Red
            Read-Host "Tekan ENTER untuk kembali ke menu awal"
            continue
        }

        Write-Host "Pilih Lab:" -ForegroundColor Yellow
        Write-Host ""
        for ($i = 0; $i -lt $labList.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $labList[$i].name)
        }
        Write-Host ("  [0] Kembali")
        Write-Host ""

        $labIndex = -1
        $labValid = $false
        while (-not $labValid) {
            $labInput = Read-Host "Masukkan nomor lab (0-$($labList.Count))"
            if ([int]::TryParse($labInput, [ref]$labIndex)) {
                if ($labIndex -eq 0) {
                    $labValid = $true
                } elseif ($labIndex -ge 1 -and $labIndex -le $labList.Count) {
                    $labValid = $true
                }
            }
        }

        if ($labIndex -eq 0) { continue }

        $selectedLab = $labList[$labIndex - 1]
        $labId = $selectedLab.id

        Write-Host ""
        Write-Host "Lab dipilih: $($selectedLab.name)" -ForegroundColor Green
        Write-Host "[*] Mendownload wallpaper installer script ..." -ForegroundColor Yellow

        try {
            $scriptUrl  = "$baseUrl/script-raw/$labId"
            $scriptDest = "C:\ProgramData\LabScriptManager\set-wallpaper.ps1"
            $dataDir    = "C:\ProgramData\LabScriptManager"

            if (-not (Test-Path $dataDir)) {
                New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            }

            Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptDest -UseBasicParsing -TimeoutSec 30
            Write-Host "[OK] Script downloaded" -ForegroundColor Green

            # Spawn proses baru (gak bisa & langsung karena iex context + here-string)
            # -NoNewWindow supaya output keliatan di terminal yang sama
            Write-Host "[*] Menjalankan installer wallpaper ..." -ForegroundColor Yellow
            Write-Host ""
            $proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDest`"" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host ""
                Write-Host "[OK] Wallpaper untuk lab '$($selectedLab.name)' berhasil di-setup!" -ForegroundColor Green
                Write-Host "     Scheduled task akan otomatis update wallpaper secara berkala." -ForegroundColor Green
            } else {
                Write-Host ""
                Write-Host "Installer selesai dengan exit code $($proc.ExitCode)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host ""
            Write-Host "GAGAL setup wallpaper: $_" -ForegroundColor Red
        }

        Write-Host ""
        Read-Host "Tekan ENTER untuk kembali ke menu awal"
        continue
    }

    # =====================================================
    # STEP 3 - Ambil daftar software
    # =====================================================
    $appList = $null

    if ($isOther) {
        Write-Host ""
        Write-Host "[*] Mengumpulkan daftar software dari semua unit ..." -ForegroundColor Yellow
        $combined = @()
        $seenKeys = @{}

        foreach ($u in $unitList) {
            $softwareUrl = "$baseUrl/units/$($u.slug)/software"
            try {
                $rawJson = Invoke-WebRequest -Uri $softwareUrl -UseBasicParsing | Select-Object -ExpandProperty Content
                $parsed  = $rawJson | ConvertFrom-Json
                foreach ($item in $parsed) {
                    $item | Add-Member -NotePropertyName "sourceUnit" -NotePropertyValue $u.name -Force
                    $dedupKey = "$($item.name)|$($item.file)|$($item.downloadUrl)"
                    if (-not $seenKeys.ContainsKey($dedupKey)) {
                        $seenKeys[$dedupKey] = $true
                        $combined += $item
                    }
                }
            } catch {
                continue
            }
        }

        $appList = $combined
    } else {
        $softwareUrl = "$baseUrl/units/$($selectedUnit.slug)/software"
        Write-Host ""
        Write-Host "Unit dipilih: $($selectedUnit.name)" -ForegroundColor Green
        Write-Host "[*] Mengambil daftar software dari server ..." -ForegroundColor Yellow

        try {
            $rawJson = Invoke-WebRequest -Uri $softwareUrl -UseBasicParsing | Select-Object -ExpandProperty Content
            $appList = $rawJson | ConvertFrom-Json
        } catch {
            Write-Host ""
            Write-Host "GAGAL mengambil daftar software!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host ""
            Read-Host "Tekan ENTER untuk kembali ke menu awal"
            continue
        }
    }

    if (-not $appList -or $appList.Count -eq 0) {
        Write-Host "Daftar software kosong untuk unit ini." -ForegroundColor Red
        Read-Host "Tekan ENTER untuk kembali ke menu awal"
        continue
    }

    # =====================================================
    # STEP 4 - Kalau "Other", checklist; kalau unit biasa, install semua
    # =====================================================
    if ($isOther) {
        Write-Host "[*] Silakan pilih aplikasi yang ingin diinstall (tahan CTRL/SHIFT untuk pilih banyak), lalu klik OK." -ForegroundColor Yellow
        $selectedApps = $appList | Select-Object name, file, args, downloadUrl, preDownload, postCopy, postRun, postCommand, sourceUnit |
            Out-GridView -Title "Pilih Aplikasi yang Ingin Diinstall (dari semua unit)" -PassThru

        if (-not $selectedApps -or $selectedApps.Count -eq 0) {
            Write-Host "Tidak ada aplikasi yang dipilih." -ForegroundColor Red
            Read-Host "Tekan ENTER untuk kembali ke menu awal"
            continue
        }
        $appsToInstall = $selectedApps
        $unitDisplayName = "Other"
    } else {
        $appsToInstall = $appList
        $unitDisplayName = $selectedUnit.name
    }

    # =====================================================
    # STEP 5 - Download & Install
    # =====================================================
    "===== Instalasi dimulai: $(Get-Date) | Unit: $unitDisplayName =====" | Out-File $logFile -Append

    Write-Host ""
    Write-Host "=== Mulai instalasi untuk: $unitDisplayName ===" -ForegroundColor Cyan
    Write-Host "Total software: $($appsToInstall.Count)"
    Write-Host ""

    $success = 0
    $failed  = @()

    foreach ($app in $appsToInstall) {
        $name       = $app.name
        $fileName   = $app.file
        $installArg = $app.args
        $downloadUrl = $app.downloadUrl

        Write-Host "[*] Download: $name ..." -ForegroundColor Yellow
        $downloadOk = $true
        $localPath = $null
        try {
            $localPath = Get-InstallerFile -Url $downloadUrl -FileName $fileName -DisplayName $name
        } catch {
            Write-Host "    GAGAL download $name : $_" -ForegroundColor Red
            "GAGAL DOWNLOAD - $name : $_" | Out-File $logFile -Append
            $failed += $name
            $downloadOk = $false
        }
        if (-not $downloadOk) { continue }
        Write-Host "    Download selesai: $name" -ForegroundColor Green

        # =================================================
        # PRE-DOWNLOAD
        # =================================================
        if ($app.preDownload) {
            foreach ($preItem in $app.preDownload) {
                $preFile = if ($preItem.file) { $preItem.file } else { $preItem }
                $preUrl  = if ($preItem.downloadUrl) { $preItem.downloadUrl } else { $preItem }
                $preName = Split-Path $preFile -Leaf

                Write-Host "[*] Pre-download: $preName ..." -ForegroundColor Yellow
                try {
                    Get-InstallerFile -Url $preUrl -FileName $preName -DisplayName $preName | Out-Null
                } catch {
                    Write-Host "    GAGAL pre-download $preName : $_" -ForegroundColor Red
                    "GAGAL PREDOWNLOAD - $preName : $_" | Out-File $logFile -Append
                }
            }
        }

        # Ganti placeholder {tempDir} di argumen
        if ($installArg -and $installArg -like "*{tempDir}*") {
            $installArg = $installArg -replace '\{tempDir\}', $tempDir
        }

        Write-Host "[*] Install: $name ..." -ForegroundColor Yellow
        $installOk = $false
        try {
            $proc = Start-Process -FilePath $localPath -ArgumentList $installArg -PassThru
            $startTime = Get-Date

            while (-not $proc.HasExited) {
                $elapsed = (Get-Date) - $startTime
                $elapsedStr = "{0:mm}:{0:ss}" -f $elapsed
                Write-Progress -Activity "Install: $name" -Status "Sedang menginstal... ($elapsedStr)" -PercentComplete -1
                Start-Sleep -Milliseconds 500
            }
            Write-Progress -Activity "Install: $name" -Completed

            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                if ($proc.ExitCode -eq 3010) {
                    Write-Host "    OK: $name terinstall (perlu restart PC)" -ForegroundColor Green
                    "SUKSES (PERLU RESTART) - $name" | Out-File $logFile -Append
                } else {
                    Write-Host "    OK: $name terinstall" -ForegroundColor Green
                    "SUKSES - $name" | Out-File $logFile -Append
                }
                $success++
                $installOk = $true
            } else {
                Write-Host "    GAGAL: $name (exit code $($proc.ExitCode))" -ForegroundColor Red
                "GAGAL INSTALL - $name (exit code $($proc.ExitCode))" | Out-File $logFile -Append
                $failed += $name
            }
        } catch {
            Write-Host "    ERROR install $name : $_" -ForegroundColor Red
            "ERROR INSTALL - $name : $_" | Out-File $logFile -Append
            $failed += $name
        }

        # =================================================
        # POST-COPY
        # =================================================
        if ($installOk -and $app.postCopy) {
            foreach ($copyItem in $app.postCopy) {
                $srcName = Split-Path $copyItem.source -Leaf
                $srcDownloadUrl = if ($copyItem.downloadUrl) { $copyItem.downloadUrl } else { $downloadUrl }
                $destPath = $copyItem.destination

                Write-Host "[*] Menyalin file tambahan: $srcName -> $destPath ..." -ForegroundColor Yellow
                try {
                    $srcLocalPath = Get-InstallerFile -Url $srcDownloadUrl -FileName $srcName -DisplayName $srcName

                    $destDir = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }

                    Copy-Item -Path $srcLocalPath -Destination $destPath -Force

                    Write-Host "    OK: file berhasil disalin ke $destPath" -ForegroundColor Green
                    "SUKSES POSTCOPY - $srcName -> $destPath" | Out-File $logFile -Append
                } catch {
                    Write-Host "    GAGAL menyalin file tambahan: $_" -ForegroundColor Red
                    "GAGAL POSTCOPY - $srcName -> $destPath : $_" | Out-File $logFile -Append
                }
            }
        }

        # =================================================
        # POST-RUN
        # =================================================
        if ($installOk -and $app.postRun) {
            foreach ($runItem in $app.postRun) {
                $srcUrl  = if ($runItem.downloadUrl) { $runItem.downloadUrl } else { $downloadUrl }
                $srcName = Split-Path $runItem.source -Leaf
                $srcLocalPath = Join-Path $tempDir $srcName

                Write-Host "[*] Menjalankan file konfigurasi: $srcName ..." -ForegroundColor Yellow
                try {
                    Get-InstallerFile -Url $srcUrl -FileName $srcName -DisplayName $srcName | Out-Null
                    Start-Process -FilePath $srcLocalPath

                    if ($runItem.waitForDialog) {
                        $titlePattern = $runItem.waitForDialog.titleContains
                        $keysToSend   = if ($runItem.waitForDialog.keys) { $runItem.waitForDialog.keys } else { "{ENTER}" }
                        $timeout      = if ($runItem.waitForDialog.timeoutSeconds) { $runItem.waitForDialog.timeoutSeconds } else { 30 }

                        Write-Host "    Menunggu dialog '$titlePattern' ..." -ForegroundColor Yellow
                        $dismissed = Confirm-DialogWindow -TitleContains $titlePattern -Keys $keysToSend -TimeoutSeconds $timeout

                        if ($dismissed) {
                            Write-Host "    OK: dialog otomatis ditutup" -ForegroundColor Green
                            "SUKSES AUTODISMISS - $titlePattern" | Out-File $logFile -Append
                        } else {
                            Write-Host "    Dialog '$titlePattern' tidak terdeteksi dalam $timeout detik" -ForegroundColor Red
                            "TIMEOUT AUTODISMISS - $titlePattern" | Out-File $logFile -Append
                        }
                    } else {
                        Write-Host "    OK: $srcName dijalankan." -ForegroundColor Green
                    }

                    "SUKSES POSTRUN - $srcName" | Out-File $logFile -Append
                } catch {
                    Write-Host "    GAGAL menjalankan $srcName : $_" -ForegroundColor Red
                    "GAGAL POSTRUN - $srcName : $_" | Out-File $logFile -Append
                }
            }
        }

        # =================================================
        # POST-COMMAND
        # =================================================
        if ($installOk -and $app.postCommand) {
            foreach ($cmdItem in $app.postCommand) {
                $filePath = $null

                if ($cmdItem.download) {
                    $dlUrl  = if ($cmdItem.downloadUrl) { $cmdItem.downloadUrl } else { $downloadUrl }
                    $dlName = Split-Path $cmdItem.download -Leaf

                    Write-Host "[*] Download file untuk command: $dlName ..." -ForegroundColor Yellow
                    try {
                        $filePath = Get-InstallerFile -Url $dlUrl -FileName $dlName -DisplayName $dlName
                    } catch {
                        Write-Host "    GAGAL download $dlName : $_" -ForegroundColor Red
                        "GAGAL POSTCOMMAND DOWNLOAD - $dlName : $_" | Out-File $logFile -Append
                        continue
                    }
                }

                $cmdExe  = $cmdItem.exe
                $cmdArgs = $cmdItem.args
                if ($filePath) {
                    $cmdArgs = $cmdArgs -replace '\{file\}', $filePath
                }

                Write-Host "[*] Menjalankan: $cmdExe $cmdArgs ..." -ForegroundColor Yellow
                try {
                    $cmdProc = Start-Process -FilePath $cmdExe -ArgumentList $cmdArgs -Wait -PassThru -NoNewWindow
                    if ($cmdProc.ExitCode -eq 0) {
                        Write-Host "    OK: command berhasil" -ForegroundColor Green
                        "SUKSES POSTCOMMAND - $cmdExe $cmdArgs" | Out-File $logFile -Append
                    } else {
                        Write-Host "    GAGAL: command exit code $($cmdProc.ExitCode)" -ForegroundColor Red
                        "GAGAL POSTCOMMAND - $cmdExe $cmdArgs (exit code $($cmdProc.ExitCode))" | Out-File $logFile -Append
                    }
                } catch {
                    Write-Host "    ERROR menjalankan command: $_" -ForegroundColor Red
                    "ERROR POSTCOMMAND - $cmdExe $cmdArgs : $_" | Out-File $logFile -Append
                }
            }
        }

        Write-Host ""
    }

    # =====================================================
    # Ringkasan
    # =====================================================
    "===== Instalasi selesai: $(Get-Date) =====" | Out-File $logFile -Append

    Write-Host "=================================================="  -ForegroundColor Cyan
    Write-Host "Unit      : $unitDisplayName"
    Write-Host "Berhasil  : $success / $($appsToInstall.Count)" -ForegroundColor Green
    if ($failed.Count -gt 0) {
        Write-Host "Gagal     : $($failed -join ', ')" -ForegroundColor Red
    } else {
        Write-Host "Semua software berhasil diinstall!" -ForegroundColor Green
    }
    Write-Host "Log       : $logFile"
    Write-Host "=================================================="  -ForegroundColor Cyan
    Write-Host ""

    # Kalau auto-unit, tidak loop
    if ($autoUnit -and $autoUnit -ne "") {
        $keepRunning = $false
    } else {
        Read-Host "Tekan ENTER untuk kembali ke menu awal (atau tutup jendela ini untuk keluar)"
    }
}

Write-Host ""
Write-Host "Terima kasih. Program ditutup." -ForegroundColor Cyan
Start-Sleep -Seconds 2
