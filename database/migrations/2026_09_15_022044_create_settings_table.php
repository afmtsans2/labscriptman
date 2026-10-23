<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('settings', function (Blueprint $table) {
            $table->string('key')->primary();
            $table->text('value')->nullable();
        });

        DB::table('settings')->insert([
            'key' => 'polling_interval_minutes',
            'value' => '15',
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('settings');
    }
};
