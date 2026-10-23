<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SoftwarePackage extends Model
{
    protected $fillable = [
        'unit_id',
        'name',
        'file_name',
        'source_type',
        'file_path',
        'download_url',
        'source_unit_id',
        'silent_args',
        'advanced_config',
        'sort_order',
        'is_active',
    ];

    protected $casts = [
        'advanced_config' => 'array',
        'is_active' => 'boolean',
        'sort_order' => 'integer',
    ];

    public function unit(): BelongsTo
    {
        return $this->belongsTo(Unit::class);
    }

    public function sourceUnit(): BelongsTo
    {
        return $this->belongsTo(Unit::class, 'source_unit_id');
    }
}
