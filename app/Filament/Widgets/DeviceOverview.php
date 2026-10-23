<?php

namespace App\Filament\Widgets;

use App\Models\Device;
use App\Models\Setting;
use Filament\Widgets\StatsOverviewWidget as BaseWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class DeviceOverview extends BaseWidget
{
    protected static ?int $sort = 1;

    protected function getStats(): array
    {
        $threshold = (int) Setting::get('polling_interval_minutes', 15) * 2;
        $cutoff = now()->subMinutes($threshold);

        $total = Device::count();
        $online = Device::where('last_checkin_at', '>=', $cutoff)->count();
        $offline = $total - $online;

        return [
            Stat::make('Total Devices', $total)
                ->icon('heroicon-o-computer-desktop'),
            Stat::make('Online', $online)
                ->icon('heroicon-o-signal')
                ->color('success'),
            Stat::make('Offline', $offline)
                ->icon('heroicon-o-signal-slash')
                ->color('danger'),
        ];
    }
}
