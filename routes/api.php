<?php

use App\Http\Controllers\InstallerApiController;
use App\Http\Controllers\WallpaperApiController;
use Illuminate\Support\Facades\Route;

Route::prefix('labscript')->group(function () {
    // Wallpaper endpoints (existing)
    Route::get('/version', [WallpaperApiController::class, 'version']);
    Route::get('/current', [WallpaperApiController::class, 'current']);
    Route::get('/interval', [WallpaperApiController::class, 'interval']);
    Route::post('/checkin', [WallpaperApiController::class, 'checkin']);
    Route::get('/script-raw/{lab}', [WallpaperApiController::class, 'scriptRaw']);
    Route::get('/script/{lab}', [WallpaperApiController::class, 'script'])->name('api.labscript.script');

    Route::get('/labs', [WallpaperApiController::class, 'labs']);
    Route::get('/installer-script', [InstallerApiController::class, 'installerScript']);
    Route::get('/installer-bat/menu', [InstallerApiController::class, 'installerBatGeneric'])->name('api.labscript.installer-bat-generic');
    Route::get('/installer-bat/{unit:slug}', [InstallerApiController::class, 'installerBat'])->name('api.labscript.installer-bat');
    Route::get('/units', [InstallerApiController::class, 'units']);
    Route::get('/units/{unit:slug}/software', [InstallerApiController::class, 'software']);
    Route::get('/units/{unit:slug}/download/{software}', [InstallerApiController::class, 'download']);
});
