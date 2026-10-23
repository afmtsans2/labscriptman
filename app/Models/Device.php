<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Device extends Model
{
    protected $fillable = ['hostname', 'lab_id', 'local_version', 'ip_address', 'last_checkin_at'];

    protected $casts = [
        'last_checkin_at' => 'datetime',
        'local_version' => 'integer',
    ];

    public function lab(): BelongsTo
    {
        return $this->belongsTo(Lab::class);
    }

    public function isOnline(): bool
    {
        if (! $this->last_checkin_at) {
            return false;
        }

        $threshold = (int) Setting::get('polling_interval_minutes', 15) * 2;

        return $this->last_checkin_at->greaterThan(now()->subMinutes($threshold));
    }
}
