<?php

namespace App\Filament\Resources;

use App\Filament\Resources\WallpaperResource\Pages;
use App\Models\Wallpaper;
use Filament\Forms;
use Filament\Forms\Form;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

class WallpaperResource extends Resource
{
    protected static ?string $model = Wallpaper::class;

    protected static ?string $navigationIcon = 'heroicon-o-photo';

    protected static ?string $navigationGroup = 'Wallpaper';

    public static function form(Form $form): Form
    {
        return $form
            ->schema([
                Forms\Components\Select::make('lab_id')
                    ->relationship('lab', 'name')
                    ->placeholder('Global (Semua Lab)')
                    ->label('Lab')
                    ->nullable(),
                Forms\Components\FileUpload::make('image_path')
                    ->image()
                    ->directory('wallpapers')
                    ->disk('public')
                    ->imagePreviewHeight('250')
                    ->maxSize(20480)
                    ->required()
                    ->columnSpanFull(),
                Forms\Components\Toggle::make('is_active')
                    ->default(true),
            ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\ImageColumn::make('image_path')
                    ->disk('public')
                    ->label('Preview')
                    ->height(60),
                Tables\Columns\TextColumn::make('lab.name')
                    ->default('Global')
                    ->label('Lab')
                    ->sortable(),
                Tables\Columns\TextColumn::make('version')
                    ->sortable(),
                Tables\Columns\IconColumn::make('is_active')
                    ->boolean()
                    ->label('Active'),
                Tables\Columns\TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable(),
            ])
            ->filters([
                //
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
        return [
            //
        ];
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListWallpapers::route('/'),
            'create' => Pages\CreateWallpaper::route('/create'),
            'edit' => Pages\EditWallpaper::route('/{record}/edit'),
        ];
    }
}
