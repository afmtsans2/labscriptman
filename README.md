# LabScriptManager

Centralized lab management platform for Budi Luhur schools. Manages wallpaper deployment and (soon) software installation scripts for Windows lab PCs across all school units.

Built with [Laravel](https://laravel.com) + [Filament](https://filamentphp.com).

## Features

- **Wallpaper Management** — Upload, assign per-lab wallpapers. Windows clients auto-sync via polling API.
- **Device Monitoring** — Track online/offline status of lab PCs via heartbeat checkins.
- **Lab Management** — Organize PCs by lab/unit, generate installer scripts per lab.
- **Settings** — Configurable polling interval from admin panel.

## Setup

```bash
# Docker
docker compose up -d
docker compose exec app php artisan migrate

# Local
composer install
php artisan migrate
php artisan serve
```

Admin panel: `/admin`

## License

[MIT](https://opensource.org/licenses/MIT)
