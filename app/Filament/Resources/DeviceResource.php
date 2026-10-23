<?php

namespace App\Filament\Resources;

use App\Filament\Resources\DeviceResource\Pages;
use App\Models\Device;
use App\Models\Setting;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class DeviceResource extends Resource
{
    protected static ?string $model = Device::class;

    protected static ?string $navigationIcon = 'heroicon-o-computer-desktop';

    protected static ?string $navigationGroup = 'Monitoring';

    protected static ?int $navigationSort = 1;

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        $threshold = (int) Setting::get('polling_interval_minutes', 15) * 2;

        return $table
            ->columns([
                Tables\Columns\TextColumn::make('hostname')
                    ->searchable()
                    ->sortable(),
                Tables\Columns\TextColumn::make('lab.name')
                    ->default('Global')
                    ->label('Lab')
                    ->sortable(),
                Tables\Columns\TextColumn::make('local_version')
                    ->label('Version')
                    ->sortable(),
                Tables\Columns\TextColumn::make('ip_address')
                    ->label('IP Address'),
                Tables\Columns\TextColumn::make('last_checkin_at')
                    ->label('Last Checkin')
                    ->since()
                    ->sortable(),
                Tables\Columns\IconColumn::make('is_online')
                    ->label('Status')
                    ->state(fn (Device $record) => $record->isOnline())
                    ->boolean()
                    ->trueIcon('heroicon-o-signal')
                    ->falseIcon('heroicon-o-signal-slash')
                    ->trueColor('success')
                    ->falseColor('danger'),
            ])
            ->defaultSort('last_checkin_at', 'desc')
            ->filters([
                Tables\Filters\SelectFilter::make('lab_id')
                    ->relationship('lab', 'name')
                    ->label('Lab'),
                Tables\Filters\Filter::make('online')
                    ->label('Online')
                    ->query(fn (Builder $query) => $query->where('last_checkin_at', '>=', now()->subMinutes(
                        (int) Setting::get('polling_interval_minutes', 15) * 2
                    ))),
                Tables\Filters\Filter::make('offline')
                    ->label('Offline')
                    ->query(fn (Builder $query) => $query->where(function ($q) {
                        $q->whereNull('last_checkin_at')
                          ->orWhere('last_checkin_at', '<', now()->subMinutes(
                              (int) Setting::get('polling_interval_minutes', 15) * 2
                          ));
                    })),
            ])
            ->actions([
                //
            ])
            ->bulkActions([
                Tables\Actions\BulkActionGroup::make([
                    Tables\Actions\DeleteBulkAction::make(),
                ]),
            ]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListDevices::route('/'),
        ];
    }
}
