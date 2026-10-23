# One-Click Installer — Sekolah Budi Luhur

Sistem instalasi software otomatis untuk PC lab komputer di semua unit sekolah
(SMA/SMK/SMP/SD/TK Karang Tengah, SD/TK Pondok Aren, BERBUDI). Teknisi cukup
double-click satu file `.bat` di PC target, pilih unit dari menu, dan semua
software untuk unit itu otomatis ke-download + terinstall tanpa interaksi
manual (kecuali kasus tertentu yang memang butuh, dijelaskan di bawah).

## Arsitektur

```
PC target (Windows)
  └─ double-click Install.bat
       └─ minta UAC (admin) sekali di awal
       └─ iex (DownloadString install-unit.ps1 dari server)
            └─ tampilkan menu pilih unit
            └─ fetch list.json dari folder unit yang dipilih
            └─ download + install tiap software di list.json
            └─ tangani langkah tambahan (copy file, run file, CLI command)
            └─ tampilkan ringkasan, loop balik ke menu

Server: indexof.budiluhur.web.id  (Nginx static file server + autoindex,
        diekspos via Cloudflare Tunnel, TANPA auth — masih tahap testing)
```

Semua source of truth ada di server. PC target cuma butuh 1 file kecil
(`Install.bat`); `install-unit.ps1` yang berat logic-nya selalu ditarik ulang
dari server tiap kali dijalankan, jadi update logic = update 1 file di server,
tidak perlu sebar ulang apapun ke PC.

## Struktur folder di server

```
indexof.budiluhur.web.id/
  ├── install-unit.ps1          <- script utama (lihat lampiran di bawah)
  ├── SMAKT/
  │     ├── list.json
  │     ├── winrarx64.exe
  │     ├── SPSS/
  │     │     ├── spss27.exe
  │     │     └── lservrc
  │     ├── EXAMBL/
  │     │     ├── SEB39.exe
  │     │     └── config.seb
  │     ├── vscode64.exe
  │     ├── MeshAgent.exe
  │     └── VEYON-LABKOM2/
  │           ├── veyon.exe
  │           ├── config-veyon-labkom2.json
  │           └── public_key_labkom2.pem
  ├── SMKKT/
  │     └── list.json (+ installer2 unit ini)
  ├── SMPKT/, SDKT/, SDPA/, TKKT/, TKPA/   <- pola sama, isi menyusul
  └── BERBUDI/
        ├── list.json            <- beberapa entry menunjuk balik ke SMAKT/
        └── meshagentarm64-PCBERBUDI.exe
```

Folder `Other/` yang tadinya dibuat terpisah **sudah tidak dipakai** — menu
"Other" di script sekarang otomatis menggabungkan `list.json` dari semua unit
lain (lihat bagian "Other (Pilih Aplikasi Sendiri)" di bawah).

## `Install.bat` — launcher di PC target

```bat
@echo off
:: =========================================================
:: LAUNCHER - One-Click Installer Sekolah Budi Luhur
:: Double-click file ini untuk menjalankan installer
:: Langsung minta hak Administrator (UAC) tanpa pengecekan
:: Script utama selalu ditarik terbaru dari server
:: =========================================================

powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"iex (New-Object Net.WebClient).DownloadString(''https://indexof.budiluhur.web.id/install-unit.ps1'')\"' -Verb RunAs"
```

Catatan: elevasi UAC sengaja dihandle di level `.bat` (langsung minta admin,
tanpa pengecekan `net session`/`fltmc` — sempat dicoba dan tidak reliable di
semua PC), makanya `install-unit.ps1` sendiri **tidak** punya logic
self-elevate lagi.

## `install-unit.ps1` — script utama (isi lengkap saat ini)

```powershell
# =========================================================
# ONE-CLICK INSTALLER - MULTI UNIT
# Sekolah Budi Luhur - AF Mediatech
# =========================================================

$ErrorActionPreference = "Stop"

$baseUrl = "https://indexof.budiluhur.web.id"
$tempDir = "C:\Temp\Installer"
$logFile = "$tempDir\install_log.txt"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# --- Mapping Unit (Nama Tampilan -> Nama Folder di server) ---
$units = [ordered]@{
    "SMA Karang Tengah" = "SMAKT"
    "SMK Karang Tengah" = "SMKKT"
    "SMP Karang Tengah" = "SMPKT"
    "SD Karang Tengah"  = "SDKT"
    "SD Pondok Aren"    = "SDPA"
    "TK Karang Tengah"  = "TKKT"
    "TK Pondok Aren"    = "TKPA"
    "BERBUDI"           = "BERBUDI"
    "Other (Pilih Aplikasi Sendiri)" = "Other"
}

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
# FUNGSI - Tunggu dialog muncul lalu kirim SendKeys (auto-dismiss)
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
# LOOP UTAMA - biar bisa ulang ke menu awal
# =========================================================
$keepRunning = $true

while ($keepRunning) {

    # =====================================================
    # STEP 1 - Pilih Unit
    # =====================================================
    Clear-Host
    Write-Host "=================================================="  -ForegroundColor Cyan
    Write-Host "   ONE-CLICK INSTALLER - SEKOLAH BUDI LUHUR"          -ForegroundColor Cyan
    Write-Host "=================================================="  -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Pilih Unit:" -ForegroundColor Yellow
    Write-Host ""

    $unitNames = @($units.Keys)
    for ($i = 0; $i -lt $unitNames.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $unitNames[$i])
    }
    Write-Host ("  [0] Keluar")
    Write-Host ""

    $selectedIndex = -1
    $validInput = $false
    while (-not $validInput) {
        $inputVal = Read-Host "Masukkan nomor unit (0-$($unitNames.Count))"
        if ([int]::TryParse($inputVal, [ref]$selectedIndex)) {
            if ($selectedIndex -eq 0) {
                $keepRunning = $false
                $validInput = $true
            } elseif ($selectedIndex -ge 1 -and $selectedIndex -le $unitNames.Count) {
                $validInput = $true
            }
        }
    }

    if (-not $keepRunning) { break }

    $unitName   = $unitNames[$selectedIndex - 1]
    $folderName = $units[$unitName]

    Write-Host ""
    Write-Host "Unit dipilih: $unitName" -ForegroundColor Green
    Write-Host ""

    # =====================================================
    # STEP 2 - Ambil daftar software dari server
    #   - Unit biasa: ambil list.json dari folder unit itu
    #   - "Other"   : gabungkan list.json dari SEMUA unit,
    #                 dengan dedup + hormati sourceFolder manual
    # =====================================================
    $appList = $null

    if ($folderName -eq "Other") {
        Write-Host "[*] Mengumpulkan daftar software dari semua unit ..." -ForegroundColor Yellow
        $combined = @()
        $seenKeys = @{}

        foreach ($otherUnitName in $unitNames) {
            $otherFolder = $units[$otherUnitName]
            if ($otherFolder -eq "Other") { continue }

            $otherListUrl = "$baseUrl/$otherFolder/list.json"
            try {
                $rawJson = Invoke-WebRequest -Uri $otherListUrl -UseBasicParsing | Select-Object -ExpandProperty Content
                $parsed  = $rawJson | ConvertFrom-Json
                foreach ($item in $parsed) {
                    # Kalau list.json sudah menentukan sourceFolder sendiri
                    # (mis. menunjuk installer di folder unit lain), jangan ditimpa.
                    if (-not $item.PSObject.Properties['sourceFolder'] -or [string]::IsNullOrWhiteSpace($item.sourceFolder)) {
                        $item | Add-Member -NotePropertyName "sourceFolder" -NotePropertyValue $otherFolder -Force
                    }
                    $item | Add-Member -NotePropertyName "sourceUnit" -NotePropertyValue $otherUnitName -Force

                    # Dedup: software yang sama dirujuk dari lebih dari satu unit
                    # (nama+file+sourceFolder identik) hanya muncul sekali di checklist.
                    $dedupKey = "$($item.name)|$($item.file)|$($item.sourceFolder)"
                    if (-not $seenKeys.ContainsKey($dedupKey)) {
                        $seenKeys[$dedupKey] = $true
                        $combined += $item
                    }
                }
            } catch {
                # Unit tanpa list.json dilewati saja, tidak dianggap error
                continue
            }
        }

        $appList = $combined
    } else {
        $listUrl = "$baseUrl/$folderName/list.json"
        Write-Host "[*] Mengambil daftar software dari server ..." -ForegroundColor Yellow

        try {
            $jsonRaw = Invoke-WebRequest -Uri $listUrl -UseBasicParsing | Select-Object -ExpandProperty Content
            $parsed  = $jsonRaw | ConvertFrom-Json
            foreach ($item in $parsed) {
                if (-not $item.PSObject.Properties['sourceFolder'] -or [string]::IsNullOrWhiteSpace($item.sourceFolder)) {
                    $item | Add-Member -NotePropertyName "sourceFolder" -NotePropertyValue $folderName -Force
                }
            }
            $appList = $parsed
        } catch {
            Write-Host ""
            Write-Host "GAGAL mengambil list.json dari $listUrl" -ForegroundColor Red
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
    # STEP 3 - Kalau "Other", munculin checklist (Out-GridView)
    #          Kalau unit biasa, install semua langsung
    # =====================================================
    if ($folderName -eq "Other") {
        Write-Host "[*] Silakan pilih aplikasi yang ingin diinstall (tahan CTRL/SHIFT untuk pilih banyak), lalu klik OK." -ForegroundColor Yellow
        $selectedApps = $appList | Select-Object name, file, args, preDownload, postCopy, postRun, postCommand, sourceFolder, sourceUnit |
            Out-GridView -Title "Pilih Aplikasi yang Ingin Diinstall (dari semua unit)" -PassThru

        if (-not $selectedApps -or $selectedApps.Count -eq 0) {
            Write-Host "Tidak ada aplikasi yang dipilih." -ForegroundColor Red
            Read-Host "Tekan ENTER untuk kembali ke menu awal"
            continue
        }
        $appsToInstall = $selectedApps
    } else {
        $appsToInstall = $appList
    }

    # =====================================================
    # STEP 4 - Download & Install
    # =====================================================
    "===== Instalasi dimulai: $(Get-Date) | Unit: $unitName =====" | Out-File $logFile -Append

    Write-Host ""
    Write-Host "=== Mulai instalasi untuk: $unitName ===" -ForegroundColor Cyan
    Write-Host "Total software: $($appsToInstall.Count)"
    Write-Host ""

    $success = 0
    $failed  = @()

    foreach ($app in $appsToInstall) {
        $name       = $app.name
        $fileName   = $app.file
        $installArg = $app.args
        $appFolder  = if ($app.sourceFolder) { $app.sourceFolder } else { $folderName }
        $url        = "$baseUrl/$appFolder/$fileName"
        $localPath  = Join-Path $tempDir $fileName
        $localDir   = Split-Path $localPath -Parent

        if (-not (Test-Path $localDir)) {
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        }

        Write-Host "[*] Download: $name ..." -ForegroundColor Yellow
        $downloadOk = $true
        try {
            Get-FileWithProgress -Url $url -OutFile $localPath -DisplayName $name
        } catch {
            Write-Host "    GAGAL download $name : $_" -ForegroundColor Red
            "GAGAL DOWNLOAD - $name : $_" | Out-File $logFile -Append
            $failed += $name
            $downloadOk = $false
        }
        if (-not $downloadOk) { continue }
        Write-Host "    Download selesai: $name" -ForegroundColor Green

        # =================================================
        # PRE-DOWNLOAD - download file tambahan SEBELUM installer
        # dijalankan (mis. file config yang dipakai lewat argumen
        # /ApplyConfig= saat instalasi berjalan, contoh: Veyon).
        # =================================================
        if ($app.preDownload) {
            foreach ($preItem in $app.preDownload) {
                $preUrl  = "$baseUrl/$appFolder/$preItem"
                $preName = Split-Path $preItem -Leaf
                $prePath = Join-Path $tempDir $preName

                Write-Host "[*] Pre-download: $preName ..." -ForegroundColor Yellow
                try {
                    Get-FileWithProgress -Url $preUrl -OutFile $prePath -DisplayName $preName
                } catch {
                    Write-Host "    GAGAL pre-download $preName : $_" -ForegroundColor Red
                    "GAGAL PREDOWNLOAD - $preName : $_" | Out-File $logFile -Append
                }
            }
        }

        # Ganti placeholder {tempDir} di argumen dengan path folder temp absolut
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

            # Exit code 0 = sukses normal. 3010 = ERROR_SUCCESS_REBOOT_REQUIRED
            # (sukses tapi butuh restart PC untuk menyelesaikan, umum pada
            # installer WiX Bootstrapper/Burn yang memasang prasyarat seperti
            # .NET Runtime). Keduanya dianggap sukses di sini.
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                if ($proc.ExitCode -eq 3010) {
                    Write-Host "    OK: $name terinstall (perlu restart PC untuk menyelesaikan)" -ForegroundColor Green
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
        # POST-COPY - copy/replace file tambahan setelah install
        # (mis. file lisensi lservrc buat SPSS, SebClientSettings.seb
        # buat SEB supaya ke-load tanpa dialog konfirmasi)
        # =================================================
        if ($installOk -and $app.postCopy) {
            foreach ($copyItem in $app.postCopy) {
                $srcUrl  = "$baseUrl/$appFolder/$($copyItem.source)"
                $srcName = Split-Path $copyItem.source -Leaf
                $srcLocalPath = Join-Path $tempDir $srcName
                $destPath = $copyItem.destination

                Write-Host "[*] Menyalin file tambahan: $srcName -> $destPath ..." -ForegroundColor Yellow
                try {
                    Get-FileWithProgress -Url $srcUrl -OutFile $srcLocalPath -DisplayName $srcName

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
        # POST-RUN - download lalu jalankan file (mis. config.seb
        # versi lama sebelum ditemukan cara postCopy yang lebih clean).
        # Kalau ada "waitForDialog", script otomatis tunggu dialog
        # muncul lalu kirim tombol via SendKeys.
        # =================================================
        if ($installOk -and $app.postRun) {
            foreach ($runItem in $app.postRun) {
                $srcUrl  = "$baseUrl/$appFolder/$($runItem.source)"
                $srcName = Split-Path $runItem.source -Leaf
                $srcLocalPath = Join-Path $tempDir $srcName

                Write-Host "[*] Menjalankan file konfigurasi: $srcName ..." -ForegroundColor Yellow
                try {
                    Get-FileWithProgress -Url $srcUrl -OutFile $srcLocalPath -DisplayName $srcName
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
                            Write-Host "    Dialog '$titlePattern' tidak terdeteksi dalam $timeout detik (mungkin perlu diklik manual)" -ForegroundColor Red
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
        # POST-COMMAND - download file (opsional) lalu jalankan
        # command CLI dari aplikasi yang baru terinstall.
        # Contoh: veyon-cli.exe authkeys import.
        # Placeholder {file} di "args" diganti path lokal file
        # yang baru didownload.
        # =================================================
        if ($installOk -and $app.postCommand) {
            foreach ($cmdItem in $app.postCommand) {
                $filePath = $null

                if ($cmdItem.download) {
                    $dlUrl  = "$baseUrl/$appFolder/$($cmdItem.download)"
                    $dlName = Split-Path $cmdItem.download -Leaf
                    $filePath = Join-Path $tempDir $dlName

                    Write-Host "[*] Download file untuk command: $dlName ..." -ForegroundColor Yellow
                    try {
                        Get-FileWithProgress -Url $dlUrl -OutFile $filePath -DisplayName $dlName
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
    Write-Host "Unit      : $unitName"
    Write-Host "Berhasil  : $success / $($appsToInstall.Count)" -ForegroundColor Green
    if ($failed.Count -gt 0) {
        Write-Host "Gagal     : $($failed -join ', ')" -ForegroundColor Red
    } else {
        Write-Host "Semua software berhasil diinstall!" -ForegroundColor Green
    }
    Write-Host "Log       : $logFile"
    Write-Host "=================================================="  -ForegroundColor Cyan
    Write-Host ""

    Read-Host "Tekan ENTER untuk kembali ke menu awal (atau tutup jendela ini untuk keluar)"
}

Write-Host ""
Write-Host "Terima kasih. Program ditutup." -ForegroundColor Cyan
Start-Sleep -Seconds 2
```

## Skema `list.json`

Tiap folder unit punya `list.json` berisi array object. Field yang didukung:

| Field | Wajib? | Fungsi |
|---|---|---|
| `name` | ya | Nama tampilan software |
| `file` | ya | Path relatif ke installer, relatif terhadap `sourceFolder` (boleh pakai subfolder, mis. `SPSS/spss27.exe`) |
| `args` | ya | Argumen silent install. Bisa mengandung placeholder `{tempDir}` (diganti `C:\Temp\Installer`) |
| `sourceFolder` | tidak | Override folder asal file (default: folder unit yang sedang dipilih). Dipakai kalau installer sebenarnya ada di folder unit lain (lihat kasus BERBUDI di bawah) |
| `preDownload` | tidak | Array path relatif; didownload ke `$tempDir` **sebelum** installer utama dijalankan (dipakai kalau argumen `args` butuh file itu sudah ada, mis. `/ApplyConfig=`) |
| `postCopy` | tidak | Array `{ source, destination }`; setelah install sukses, download `source` lalu copy paksa (`-Force`) ke `destination` (path absolut Windows) |
| `postRun` | tidak | Array `{ source, waitForDialog? }`; setelah install sukses, download `source` lalu jalankan (`Start-Process`). `waitForDialog: { titleContains, keys, timeoutSeconds }` opsional untuk auto-dismiss dialog via SendKeys |
| `postCommand` | tidak | Array `{ download?, exe, args }`; setelah install sukses, opsional download file dulu, lalu jalankan `exe` dengan `args` (placeholder `{file}` diganti path file yang didownload) |

Field `preDownload`/`postCopy`/`postRun`/`postCommand`/`sourceFolder` **wajib**
ikut disebutkan di baris `Select-Object` pada blok "Other" (STEP 3) — kalau
field baru ditambahkan ke skema ini di masa depan, baris itu harus diupdate
juga, kalau tidak field baru akan otomatis ke-strip saat lewat menu "Other"
(bug ini pernah kejadian dan sudah diperbaiki untuk field yang ada sekarang).

### Contoh lengkap per software yang sudah dikonfigurasi

**WinRAR** (NSIS installer, paling simpel):
```json
{
  "name": "WinRAR",
  "file": "winrarx64.exe",
  "args": "/S"
}
```

**IBM SPSS Statistics 27** (InstallShield/MSI, butuh file lisensi):
```json
{
  "name": "IBM SPSS Statistics 27",
  "file": "SPSS/spss27.exe",
  "args": "/S /v/qn",
  "postCopy": [
    {
      "source": "SPSS/lservrc",
      "destination": "C:\\Program Files\\IBM\\SPSS\\Statistics\\27\\lservrc"
    }
  ]
}
```

**Safe Exam Browser** (WiX Bootstrapper/Burn; config di-copy langsung ke
lokasi default settings SEB supaya ke-load otomatis TANPA dialog konfirmasi
apapun — ini solusi final, lebih baik daripada `postRun` + SendKeys yang
dicoba sebelumnya):
```json
{
  "name": "Safe Exam Browser",
  "file": "EXAMBL/SEB39.exe",
  "args": "/quiet /norestart",
  "postCopy": [
    {
      "source": "EXAMBL/config.seb",
      "destination": "C:\\ProgramData\\SafeExamBrowser\\SebClientSettings.seb"
    }
  ]
}
```
Catatan: exit code installer ini bisa `3010` (sukses, butuh restart) — sudah
dihandle sebagai sukses di script.

**Visual Studio Code** (Inno Setup):
```json
{
  "name": "Visual Studio Code",
  "file": "vscode64.exe",
  "args": "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath"
}
```

**MeshCentral Agent** (file spesifik per device group, didownload langsung
dari dashboard MeshCentral — sudah embed info server + grup):
```json
{
  "name": "MeshCentral Agent - Labkom Lantai 2",
  "file": "MeshAgent.exe",
  "args": "-fullinstall"
}
```

**Veyon Agent** (install komponen Service saja tanpa Master, apply config
lewat parameter resmi installer `/ApplyConfig` yang butuh path absolut —
makanya pakai `preDownload` — lalu import public key lewat `veyon-cli.exe`
via `postCommand`):
```json
{
  "name": "Veyon Agent - Labkom 2",
  "file": "VEYON-LABKOM2/veyon.exe",
  "preDownload": [
    "VEYON-LABKOM2/config-veyon-labkom2.json"
  ],
  "args": "/S /NoMaster /ApplyConfig={tempDir}\\config-veyon-labkom2.json",
  "postCommand": [
    {
      "download": "VEYON-LABKOM2/public_key_labkom2.pem",
      "exe": "C:\\Program Files\\Veyon\\veyon-cli.exe",
      "args": "authkeys import labkom2admin/public \"{file}\""
    }
  ]
}
```

**Contoh `sourceFolder` (BERBUDI memakai installer yang sama dengan SMAKT)**
— `BERBUDI/list.json`:
```json
[
  {
    "name": "WinRAR",
    "file": "winrarx64.exe",
    "args": "/S",
    "sourceFolder": "SMAKT"
  },
  {
    "name": "IBM SPSS Statistics 27",
    "file": "SPSS/spss27.exe",
    "args": "/S /v/qn",
    "sourceFolder": "SMAKT",
    "postCopy": [
      {
        "source": "SPSS/lservrc",
        "destination": "C:\\Program Files\\IBM\\SPSS\\Statistics\\27\\lservrc"
      }
    ]
  },
  {
    "name": "Safe Exam Browser",
    "file": "EXAMBL/SEB39.exe",
    "args": "/quiet /norestart",
    "sourceFolder": "SMAKT"
  },
  {
    "name": "MeshCentral Agent - BERBUDI",
    "file": "meshagentarm64-PCBERBUDI.exe",
    "args": "-fullinstall"
  }
]
```
Item terakhir sengaja **tidak** diberi `sourceFolder` karena file itu memang
cuma ada di `BERBUDI/` sendiri (default fallback: folder unit yang dipilih).

## Menu "Other (Pilih Aplikasi Sendiri)"

Alih-alih punya folder `Other/` terpisah yang perlu diisi ulang installer
yang sudah ada di unit lain, menu ini men-scan `list.json` dari **semua**
folder unit, menggabungkannya jadi satu daftar, dedup berdasarkan
`name|file|sourceFolder`, lalu menampilkan checklist (`Out-GridView`) supaya
teknisi bisa pilih software campuran dari unit manapun untuk diinstall ke 1
PC (berguna untuk PC yang butuh kombinasi software di luar paket standar
unitnya).

## Cheat sheet tipe installer & argumen silent

Ditemukan lewat trial-error selama development (tiap installer beda-beda,
jangan asumsi satu argumen berlaku untuk semua):

| Tipe installer | Ciri-ciri | Argumen silent |
|---|---|---|
| NSIS | Kecil, ringan (WinRAR) | `/S` |
| Inno Setup | (VS Code) | `/VERYSILENT /NORESTART` |
| InstallShield/MSI wrapper | (SPSS) — installer nampilin dialog berisi daftar parameter command line kalau di-run tanpa argumen | `/S /v/qn` |
| WiX Bootstrapper/Burn | (Safe Exam Browser) — ada halaman "License agreement" + tombol Install/Close terpisah | `/quiet /norestart` atau `/passive /norestart`; exit code sukses bisa `0` atau `3010` |

Kalau argumen silent belum diketahui: coba jalankan installer dengan
`installer.exe /?` dulu (WiX Burn suka menampilkan daftar switch kalau
argumen salah), atau cek dokumentasi resmi vendor — jangan asal tebak lalu
asumsikan gagal karena argumen; dialog GUI yang muncul saat testing biasanya
pertanda argumen salah, bukan installer-nya rusak.

## Riwayat bug yang sudah diperbaiki (jangan diulang)

1. **`$PSCommandPath` kosong saat script dijalankan via `iex (DownloadString ...)`**
   — logic self-elevate di dalam `.ps1` tidak bisa pakai `$PSCommandPath`
   karena script dieksekusi dari memory, bukan file fisik. Solusi: elevasi
   dipindah ke `Install.bat` (langsung `-Verb RunAs` tanpa syarat), bukan di
   `.ps1`.
2. **Subfolder di path lokal belum dibuat sebelum download** — kalau `file`
   punya subfolder (mis. `SPSS/spss27.exe`), `Invoke-WebRequest -OutFile`
   gagal dengan "Could not find a part of the path" kalau folder `SPSS`
   belum ada di `$tempDir`. Solusi: selalu `New-Item -ItemType Directory`
   dulu untuk parent folder sebelum download.
3. **`Select-Object` di blok "Other" men-strip field yang tidak disebutkan
   eksplisit** — setiap kali field baru ditambahkan ke skema `list.json`
   (`postCommand`, `preDownload`), baris `Select-Object name, file, args, ...`
   di STEP 3 harus diupdate juga, atau field baru itu akan hilang saat
   software dipilih lewat menu "Other" walau ada di JSON aslinya.
4. **`sourceFolder` ditimpa paksa (`-Force`) tanpa cek nilai existing** — dua
   tempat (fetch unit biasa & fetch gabungan "Other") awalnya selalu
   menimpa `sourceFolder` jadi nama folder unit yang sedang diproses, walau
   item itu sudah menentukan `sourceFolder` sendiri di JSON (kasus BERBUDI
   yang menunjuk ke SMAKT). Solusi: hanya set `sourceFolder` kalau field itu
   belum ada / kosong di JSON aslinya.
5. **Dialog SEB "Configuration Successful" tetap muncul dan mengubah hasil
   sama saja mau diklik Yes atau ditutup** — awalnya dicoba auto-dismiss
   pakai `Confirm-DialogWindow` (SendKeys), tapi solusi yang jauh lebih
   bersih ditemukan: taruh file config langsung di
   `C:\ProgramData\SafeExamBrowser\SebClientSettings.seb` via `postCopy` —
   ini dianggap "pengaturan bawaan" oleh SEB, bukan "config asing yang
   dibuka", sehingga tidak ada dialog konfirmasi sama sekali.
6. **Exit code 3010 dianggap gagal** — untuk installer berbasis WiX
   Bootstrapper/Burn, `3010` = `ERROR_SUCCESS_REBOOT_REQUIRED` (sukses,
   butuh restart), bukan error. Sekarang ditangani sebagai sukses dengan
   catatan khusus di log.
7. **Argumen `/ApplyConfig=` butuh path absolut** karena `veyon-cli` dipanggil
   installer dari working directory yang berbeda — path relatif tidak
   berfungsi. Solusi: fitur `preDownload` + placeholder `{tempDir}`.

## Hal yang masih perlu diperhatikan / TODO

- Server `indexof.budiluhur.web.id` saat ini **tanpa autentikasi** (masih
  tahap testing) — pertimbangkan basic auth atau Cloudflare Access sebelum
  dipakai produksi penuh, terutama untuk installer berlisensi (SPSS, dll).
- Folder unit yang belum diisi (`SMPKT`, `SDKT`, `SDPA`, `TKKT`, `TKPA`)
  masih kosong — menu "Other" akan otomatis skip unit yang belum punya
  `list.json` tanpa error, jadi aman untuk diisi bertahap.
- Nama key Veyon (`authkeys import <nama>/public`) hanya boleh berisi huruf
  (tidak boleh underscore/angka) — perhatikan ini kalau menambah lab baru
  dengan Veyon.
- Kalau menambah field baru ke skema `list.json` di masa depan, ingat update
  baris `Select-Object` di STEP 3 (lihat riwayat bug #3).
