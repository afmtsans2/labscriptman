<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Wallpaper extends Model
{
    protected $fillable = ['lab_id', 'image_path', 'version', 'is_active', 'uploaded_by'];

    protected $casts = [
        'is_active' => 'boolean',
        'version' => 'integer',
    ];

    protected static function booted(): void
    {
        static::creating(function (Wallpaper $wallpaper) {
            $wallpaper->version = 1;
        });

        static::updating(function (Wallpaper $wallpaper) {
            if ($wallpaper->isDirty('image_path')) {
                $wallpaper->version = $wallpaper->version + 1;
            }
        });

        static::saved(function (Wallpaper $wallpaper) {
            if ($wallpaper->is_active) {
                // Query builder langsung — tidak trigger Eloquent events, no infinite loop
                $query = static::where('id', '!=', $wallpaper->id)
                    ->where('is_active', true);

                if ($wallpaper->lab_id === null) {
                    $query->whereNull('lab_id');
                } else {
                    $query->where('lab_id', $wallpaper->lab_id);
                }

                $query->update(['is_active' => false]);
            }
        });
    }

    public function lab(): BelongsTo
    {
        return $this->belongsTo(Lab::class);
    }

    public function uploadedBy(): BelongsTo
    {
        return $this->belongsTo(\App\Models\User::class, 'uploaded_by');
    }
}
