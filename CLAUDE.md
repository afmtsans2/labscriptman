# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LabScriptManager — centralized lab management platform for Budi Luhur schools. Manages wallpaper deployment and one-click software installation to Windows lab PCs via API + scheduled task/script.

Production URL: `https://scriptman.budiluhur.web.id`

## Commands

```bash
# Docker (primary way to run)
docker compose up -d              # start app + nginx
docker compose exec app php artisan migrate
docker compose exec app php artisan tinker

# Tests (uses in-memory SQLite, see phpunit.xml)
docker compose exec app php artisan test
docker compose exec app php artisan test --filter=ExampleTest   # single test

# Local dev (if PHP available on host)
composer install
php artisan migrate
php artisan serve                 # http://localhost:8000
composer dev                      # artisan dev (vite + server)
npm install && npm run dev        # vite dev server
npm run build                     # production assets

# Lint
composer exec pint                # Laravel Pint (PSR-12 + Laravel style)
```

## Architecture

### Two-Part System

**Server (this repo root)** — Laravel 13 + Filament 3 admin panel, Dockerized with PHP-FPM + Nginx. PostgreSQL via external Docker network `database_db-network`.

**Client (Windows PCs)** — Two subsystems:
1. **Wallpaper:** PowerShell script (`set-wallpaper.ps1` / `resources/scripts/wallpaper-template.ps1`) runs as Windows Scheduled Task. Polls API → downloads wallpaper → applies via `SystemParametersInfo` Win32 call.
2. **Software Installer:** PowerShell script (`resources/scripts/installer-template.ps1`) served dynamically via API. Downloads software list from server, installs silently. Launched via per-unit `.bat` files.

### Data Model

```
Unit (name, slug, description)
  ├── has many Lab
  └── has many SoftwarePackage

Lab (name, description, unit_id nullable)
  ├── has many Wallpaper (image_path, version, is_active, lab_id nullable)
  └── has many Device (hostname, local_version, ip_address, last_checkin_at)

SoftwarePackage (unit_id, name, file_name, source_type, silent_args, sort_order, is_active)
  ├── source_type: 'upload' (file in storage) or 'url' (external link)
  ├── file_path: path in storage (when upload)
  ├── download_url: external URL (when url)
  ├── source_unit_id: nullable FK → Unit (share installer from another unit)
  └── advanced_config: JSON (postCopy, postRun, postCommand, preDownload)

Wallpaper with lab_id=NULL = global (fallback for all labs)
Setting (key-value store, primary key = key string)
  └── polling_interval_minutes (default 15)
```

**Key behavior:** `Wallpaper::saved()` enforces single-active-per-scope — when a wallpaper is activated, all others in same lab (or global scope) are deactivated. Version auto-increments on `image_path` change.

**Device online status:** `Device::isOnline()` checks `last_checkin_at` within `2 × polling_interval_minutes`.

**Unit slug auto-generation:** `Unit::creating()` generates slug from name via `Str::slug()` if not set.

### API Endpoints (all under `/api/labscript/`)

#### Wallpaper Endpoints (existing)
| Endpoint | Method | Purpose |
|---|---|---|
| `/version?lab_id=` | GET | Current active wallpaper version (falls back to global) |
| `/current?lab_id=` | GET | Download active wallpaper image binary |
| `/interval` | GET | Polling interval in minutes |
| `/checkin` | POST | Device heartbeat (hostname, lab_id, local_version) |
| `/script-raw/{lab}` | GET | Generated PS1 script with lab_id/interval injected |
| `/script/{lab}` | GET | Downloads `.bat` installer for a lab |

#### Installer Endpoints
| Endpoint | Method | Purpose |
|---|---|---|
| `/installer-script` | GET | Serve `installer-template.ps1` dynamically. `?unit=SLUG` auto-selects unit |
| `/installer-bat/{unit:slug}` | GET | Download `.bat` launcher for a specific unit |
| `/units` | GET | List all units `[{id, name, slug}]` |
| `/units/{unit:slug}/software` | GET | Software list for a unit (list.json format) |
| `/units/{unit:slug}/download/{software}` | GET | Stream installer file (upload type). `?file=` for auxiliary files |

**Wallpaper resolution:** lab-specific first → fallback to global (`lab_id=NULL`).

### Admin Panel (Filament)

Path: `/admin` (login required, Amber primary color)

Navigation groups:
- **Wallpaper:** Wallpapers (CRUD, file upload, max 20MB)
- **Installer:** Units (CRUD + "Download Install.bat"), Software Packages (CRUD, upload/URL, advanced config)
- **Monitoring:** Devices (read-only, online/offline filter), Labs (CRUD + unit assignment)
- **Sistem:** Pengaturan (polling interval)
- **Dashboard:** DeviceOverview widget (total/online/offline stats)

### Client Script Templates (`resources/scripts/`)

- `wallpaper-template.ps1` — Wallpaper PS1 with `{{LAB_ID}}` and `{{INTERVAL_MINUTES}}` placeholders
- `installer-template.ps1` — Software installer PS1 with `{{BASE_URL}}` and `{{AUTO_UNIT}}` placeholders. Fetches unit list and software from API, downloads and installs silently with progress bars.
- `installer-downloader-template.bat` — `.bat` wrapper for wallpaper installer
- `installer-polyglot-template.bat` — Polyglot `.bat` for wallpaper

Client data stored at `C:\ProgramData\LabScriptManager\` (wallpaper) and `C:\Temp\Installer\` (software installer) on Windows PCs.

### Docker Setup

- `docker/php/Dockerfile` — PHP 8.3-FPM with pgsql, gd, zip, intl extensions
- `docker/nginx/default.conf` — Nginx reverse proxy, 100MB upload limit
- `docker/php/uploads.ini` — PHP upload limits (100MB)
- Port: `8000:80`
- External network: `database_db-network` for shared PostgreSQL

### File Storage

- Wallpapers: `storage/app/public/wallpapers/`
- Software installers: `storage/app/public/installers/{unit_slug}/`

### wallpaper-manager/ Subdirectory

Older/separate Laravel app (appears to be previous version). Main app is at repo root.

## Conventions

- DB: PostgreSQL (prod), SQLite in-memory (tests)
- File storage: `public` disk
- UI labels in Indonesian (Bahasa) — "Pengaturan", "Interval Polling (menit)", etc.
- No authentication on API endpoints (clients are lab PCs on trusted network)
- `Setting` model used as simple key-value store, not Laravel config
- Unit routes use `{unit:slug}` route model binding
