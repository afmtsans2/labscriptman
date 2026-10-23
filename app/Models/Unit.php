<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Unit extends Model
{
    protected $fillable = ['name', 'slug', 'description'];

    protected static function booted(): void
    {
        static::creating(function (Unit $unit) {
            if (empty($unit->slug)) {
                $unit->slug = Str::slug($unit->name);
            }
        });
    }

    public function labs(): HasMany
    {
        return $this->hasMany(Lab::class);
    }

    public function softwarePackages(): HasMany
    {
        return $this->hasMany(SoftwarePackage::class);
    }
}
