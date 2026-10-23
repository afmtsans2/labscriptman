<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('devices', function (Blueprint $table) {
            $table->id();
            $table->string('hostname');
            $table->foreignId('lab_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedInteger('local_version')->default(0);
            $table->string('ip_address')->nullable();
            $table->timestamp('last_checkin_at')->nullable();
            $table->timestamps();

            $table->unique(['hostname', 'lab_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('devices');
    }
};
