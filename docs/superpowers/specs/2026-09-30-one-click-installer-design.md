# One-Click Software Installer — Design Spec

## Overview

Add a "Software Installer" subsystem to LabScriptManager. Admin manages software packages per school unit via Filament panel. Windows lab PCs run a generated script that pulls the software list from the API and installs everything silently.

Production URL: `https://scriptman.budiluhur.web.id`

## Data Model

### New: `units` table

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| name | string | "SMA Karang Tengah" |
| slug | string, unique | "smakt" — used in API URLs and .bat filenames |
| description | text, nullable | |
| timestamps | | |

### New: `software_packages` table

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| unit_id | FK → units | which unit this package belongs to |
| name | string | display name ("WinRAR", "IBM SPSS Statistics 27") |
| file_name | string | installer filename, may include subfolder ("SPSS/spss27.exe") |
| source_type | enum: upload, url | how the installer is obtained |
| file_path | string, nullable | path in `storage/app/public/installers/` (when source_type=upload) |
| download_url | string, nullable | external URL (when source_type=url, e.g. Google Drive link) |
| source_unit_id | FK → units, nullable | share installer from another unit (BERBUDI → SMAKT case) |
| silent_args | string | silent install arguments ("/S", "/VERYSILENT /NORESTART", etc.) |
| advanced_config | JSON, nullable | postCopy, postRun, postCommand, preDownload — same schema as current list.json |
| sort_order | integer, default 0 | controls install sequence |
| is_active | boolean, default true | |
| timestamps | | |

### Modified: `labs` table

Add column:
- `unit_id` FK → units, nullable, nullOnDelete

## Relationships

```
Unit hasMany Lab
Unit hasMany SoftwarePackage
Lab belongsTo Unit (nullable)
SoftwarePackage belongsTo Unit
SoftwarePackage belongsTo sourceUnit (nullable, self-referencing via units)
```

Existing relationships (Lab → Wallpaper, Lab → Device) unchanged.

## API Endpoints

All under `/api/labscript/`:

### Existing (unchanged)
| Endpoint | Method | Purpose |
|---|---|---|
| /version | GET | Wallpaper version |
| /current | GET | Download wallpaper image |
| /interval | GET | Polling interval |
| /checkin | POST | Device heartbeat |
| /script-raw/{lab} | GET | Generated wallpaper PS1 |
| /script/{lab} | GET | Download wallpaper .bat installer |

### New
| Endpoint | Method | Purpose |
|---|---|---|
| /installer-script | GET | Serve `install-unit.ps1` dynamically. Optional `?unit=SLUG` to auto-select unit (skip menu). |
| /installer-bat/{unit} | GET | Download `.bat` launcher for a specific unit |
| /units | GET | List all active units `[{id, name, slug}]` |
| /units/{unit}/software | GET | Software list for a unit — response format matches current `list.json` schema |
| /units/{unit}/download/{software} | GET | Stream installer file (source_type=upload only) |

### `/units/{unit}/software` response format

Matches existing `list.json` so client script logic stays the same:

```json
[
  {
    "name": "WinRAR",
    "file": "winrarx64.exe",
    "args": "/S",
    "downloadUrl": "https://scriptman.budiluhur.web.id/api/labscript/units/smakt/download/1"
  },
  {
    "name": "IBM SPSS Statistics 27",
    "file": "SPSS/spss27.exe",
    "args": "/S /v/qn",
    "downloadUrl": "https://drive.google.com/uc?export=download&id=xxx",
    "postCopy": [{"source": "SPSS/lservrc", "destination": "C:\\Program Files\\IBM\\SPSS\\Statistics\\27\\lservrc"}]
  }
]
```

Key difference from static `list.json`: `downloadUrl` is always absolute (either Laravel file endpoint or external URL). No more `sourceFolder` concept — that's handled server-side via `source_unit_id`.

`preDownload` items also get absolute `downloadUrl` resolved server-side.

## Admin Panel (Filament)

### New Resources

**UnitResource**
- Form: name, slug (auto-generated from name, editable), description
- Table: name, slug, software count, lab count
- Actions: "Download Install.bat" per unit

**SoftwarePackageResource**
- Form:
  - Basic section: name, unit (select), source_type (radio toggle), file upload (shown when upload, max 100MB) OR download_url (shown when url), file_name, silent_args, source_unit (optional select), sort_order, is_active
  - Advanced section: JSON textarea for advanced_config with helper text showing schema
- Table: name, unit, source_type badge, is_active toggle, sort_order
- Filters: by unit, by source_type

### Modified Resources

**LabResource** — add `unit_id` select field (optional, label "Unit")

### Navigation Groups

- **Wallpaper**: Wallpapers
- **Installer**: Units, Software Packages
- **Monitoring**: Labs, Devices
- **Sistem**: Settings (Pengaturan)

## Client Script

### `install-unit.ps1` (served from `/api/labscript/installer-script`)

Laravel generates this dynamically with `$baseUrl` injected. Core logic ported from existing `install-unit.ps1` (see PROJECT-ONE-CLICK-INSTALLER.md):

- `Get-FileWithProgress` — download with progress bar (kept as-is)
- `Confirm-DialogWindow` — auto-dismiss dialog via SendKeys (kept as-is)
- Unit selection menu — fetched from `/api/labscript/units` instead of hardcoded hash
- Software list — fetched from `/api/labscript/units/{slug}/software` instead of static `list.json`
- Download — uses `downloadUrl` from API response (absolute URL, either Laravel or external)
- Install loop with preDownload/postCopy/postRun/postCommand — logic unchanged
- Menu "Other" — fetch all units, combine, dedup, Out-GridView — same logic, data from API
- If `?unit=SLUG` parameter passed, skip menu and go straight to that unit

### `Install.bat` per unit (served from `/api/labscript/installer-bat/{unit}`)

```bat
@echo off
:: LabScriptManager Installer — Unit: {UNIT_NAME}
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Meminta hak Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (New-Object Net.WebClient).DownloadString('https://scriptman.budiluhur.web.id/api/labscript/installer-script?unit={SLUG}')"
pause
```

### Generic `Install.bat` (no unit, shows menu)

Same but without `?unit=` parameter. Available as download from admin panel dashboard or Units list.

## File Storage

- Upload path: `storage/app/public/installers/{unit_slug}/{filename}`
- Max upload: 100MB (Cloudflare free tier limit)
- Nginx `client_max_body_size` and PHP `upload_max_filesize`/`post_max_size` need to be raised to 100MB

## What Does NOT Change

- Wallpaper model, migration, controller, Filament resource — untouched
- Device model, checkin flow — untouched
- Setting model — untouched
- Existing wallpaper client scripts — untouched (already rebranded)

## Implementation Order

1. Migrations: create `units`, create `software_packages`, add `unit_id` to `labs`
2. Models: Unit, SoftwarePackage + relationships, update Lab model
3. API controller: InstallerApiController + routes
4. Script template: `install-unit.ps1` in `resources/scripts/`
5. Filament: UnitResource, SoftwarePackageResource
6. Filament: update LabResource (unit_id), navigation groups
7. Docker config: raise upload limits (nginx, php)
8. Update CLAUDE.md
