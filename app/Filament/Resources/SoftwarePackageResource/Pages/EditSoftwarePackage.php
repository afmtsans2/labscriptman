<?php

namespace App\Filament\Resources\SoftwarePackageResource\Pages;

use App\Filament\Resources\SoftwarePackageResource;
use Filament\Actions;
use Filament\Resources\Pages\EditRecord;

class EditSoftwarePackage extends EditRecord
{
    protected static string $resource = SoftwarePackageResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\DeleteAction::make(),
        ];
    }
}
