<?php

namespace App\Filament\Resources;

use App\Filament\Resources\SoftwarePackageResource\Pages;
use App\Models\SoftwarePackage;
use Filament\Forms;
use Filament\Forms\Form;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

class SoftwarePackageResource extends Resource
{
    protected static ?string $model = SoftwarePackage::class;

    protected static ?string $navigationIcon = 'heroicon-o-cube';

    protected static ?string $navigationGroup = 'Installer';

    protected static ?int $navigationSort = 2;

    protected static ?string $navigationLabel = 'Software Packages';

    public static function form(Form $form): Form
    {
        return $form
            ->schema([
                Forms\Components\Section::make('Informasi Dasar')
                    ->schema([
                        Forms\Components\Select::make('unit_id')
                            ->relationship('unit', 'name')
                            ->required()
                            ->searchable()
                            ->preload()
                            ->label('Unit'),
                        Forms\Components\TextInput::make('name')
                            ->required()
                            ->maxLength(255)
                            ->label('Nama Software'),
                        Forms\Components\TextInput::make('file_name')
                            ->required()
                            ->maxLength(255)
                            ->helperText('Nama file installer, boleh termasuk subfolder (mis. SPSS/spss27.exe)')
                            ->label('Nama File'),
                        Forms\Components\Radio::make('source_type')
                            ->options([
                                'upload' => 'Upload File',
                                'url' => 'External URL',
                            ])
                            ->default('upload')
                            ->required()
                            ->live()
                            ->label('Sumber File'),
                        Forms\Components\FileUpload::make('file_path')
                            ->directory('installers')
                            ->disk('public')
                            ->maxSize(102400) // 100MB
                            ->visible(fn (Forms\Get $get) => $get('source_type') === 'upload')
                            ->label('File Installer'),
                        Forms\Components\TextInput::make('download_url')
                            ->url()
                            ->maxLength(2048)
                            ->visible(fn (Forms\Get $get) => $get('source_type') === 'url')
                            ->label('Download URL')
                            ->helperText('URL langsung ke file installer (Google Drive, index server, dll)'),
                        Forms\Components\TextInput::make('silent_args')
                            ->maxLength(500)
                            ->default('')
                            ->helperText('Argumen silent install (/S, /VERYSILENT /NORESTART, dll). Placeholder {tempDir} diganti otomatis.')
                            ->label('Silent Arguments'),
                        Forms\Components\Select::make('source_unit_id')
                            ->relationship('sourceUnit', 'name')
                            ->searchable()
                            ->preload()
                            ->nullable()
                            ->helperText('Opsional: gunakan file installer dari unit lain (mis. BERBUDI pakai file SMAKT)')
                            ->label('Source Unit'),
                        Forms\Components\TextInput::make('sort_order')
                            ->numeric()
                            ->default(0)
                            ->label('Urutan'),
                        Forms\Components\Toggle::make('is_active')
                            ->default(true)
                            ->label('Aktif'),
                    ])->columns(2),

                Forms\Components\Section::make('Advanced Config')
                    ->schema([
                        Forms\Components\Textarea::make('advanced_config')
                            ->json()
                            ->rows(10)
                            ->columnSpanFull()
                            ->helperText('JSON config untuk postCopy, postRun, postCommand, preDownload. Contoh: {"postCopy": [{"source": "SPSS/lservrc", "destination": "C:\\\\Program Files\\\\IBM\\\\SPSS\\\\Statistics\\\\27\\\\lservrc"}]}')
                            ->label('Advanced Configuration'),
                    ])->collapsed(),
            ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('sort_order')
            ->columns([
                Tables\Columns\TextColumn::make('unit.name')
                    ->sortable()
                    ->searchable()
                    ->label('Unit'),
                Tables\Columns\TextColumn::make('name')
                    ->searchable()
                    ->sortable()
                    ->label('Nama'),
                Tables\Columns\TextColumn::make('file_name')
                    ->limit(30)
                    ->label('File'),
                Tables\Columns\TextColumn::make('source_type')
                    ->badge()
                    ->color(fn (string $state): string => match ($state) {
                        'upload' => 'primary',
                        'url' => 'warning',
                        default => 'gray',
                    })
                    ->label('Sumber'),
                Tables\Columns\TextColumn::make('sort_order')
                    ->sortable()
                    ->label('Urutan'),
                Tables\Columns\ToggleColumn::make('is_active')
                    ->label('Aktif'),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('unit_id')
                    ->relationship('unit', 'name')
                    ->label('Unit'),
                Tables\Filters\SelectFilter::make('source_type')
                    ->options([
                        'upload' => 'Upload',
                        'url' => 'External URL',
                    ])
                    ->label('Sumber'),
            ])
            ->actions([
                Tables\Actions\EditAction::make(),
            ])
            ->bulkActions([
                Tables\Actions\BulkActionGroup::make([
                    Tables\Actions\DeleteBulkAction::make(),
                ]),
            ]);
    }

    public static function getRelations(): array
    {
        return [];
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListSoftwarePackages::route('/'),
            'create' => Pages\CreateSoftwarePackage::route('/create'),
            'edit' => Pages\EditSoftwarePackage::route('/{record}/edit'),
        ];
    }
}
