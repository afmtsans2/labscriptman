<?php

namespace App\Filament\Pages;

use App\Models\Setting;
use Filament\Forms;
use Filament\Forms\Form;
use Filament\Notifications\Notification;
use Filament\Pages\Page;

class Settings extends Page
{
    protected static ?string $navigationIcon = 'heroicon-o-cog-6-tooth';
    protected static ?string $navigationLabel = 'Pengaturan';
    protected static ?string $title = 'Pengaturan';
    protected static ?string $navigationGroup = 'Sistem';
    protected static string $view = 'filament.pages.settings';

    public ?array $data = [];

    public function mount(): void
    {
        $this->form->fill([
            'polling_interval_minutes' => Setting::get('polling_interval_minutes', 15),
        ]);
    }

    public function form(Form $form): Form
    {
        return $form
            ->schema([
                Forms\Components\TextInput::make('polling_interval_minutes')
                    ->label('Interval Polling (menit)')
                    ->numeric()
                    ->required()
                    ->minValue(5)
                    ->default(15)
                    ->helperText('Interval waktu (dalam menit) PC client mengecek wallpaper baru. Minimal 5 menit.'),
            ])
            ->statePath('data');
    }

    public function save(): void
    {
        $data = $this->form->getState();

        Setting::set('polling_interval_minutes', $data['polling_interval_minutes']);

        Notification::make()
            ->title('Pengaturan berhasil disimpan')
            ->success()
            ->send();
    }
}
