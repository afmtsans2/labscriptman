<?php

namespace App\Filament\Resources\UnitResource\Pages;

use App\Filament\Resources\UnitResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListUnits extends ListRecords
{
    protected static string $resource = UnitResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\Action::make('downloadGenericInstaller')
                ->label('Download Install.bat (Menu)')
                ->icon('heroicon-o-arrow-down-tray')
                ->color('gray')
                ->url(route('api.labscript.installer-bat-generic'))
                ->openUrlInNewTab(),
            Actions\CreateAction::make(),
        ];
    }
}
