<?php

namespace App\Http\Controllers;

use App\Models\Device;
use App\Models\Lab;
use App\Models\Setting;
use App\Models\Wallpaper;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class WallpaperApiController extends Controller
{
    public function labs()
    {
        return response()->json(
            Lab::orderBy('name')->get(['id', 'name'])
        );
    }

    public function version(Request $request)
    {
        $wallpaper = $this->findActiveWallpaper($request->query('lab_id'));

        if (! $wallpaper) {
            return response()->json(['version' => null], 404);
        }

        return response()->json([
            'version' => $wallpaper->version,
            'lab' => $wallpaper->lab?->name ?? 'global',
        ]);
    }

    public function current(Request $request)
    {
        $wallpaper = $this->findActiveWallpaper($request->query('lab_id'));

        if (! $wallpaper) {
            return response()->json(['message' => 'No active wallpaper found'], 404);
        }

        $disk = Storage::disk('public');

        if (! $disk->exists($wallpaper->image_path)) {
            return response()->json(['message' => 'Wallpaper file not found'], 404);
        }

        return $disk->response($wallpaper->image_path);
    }

    public function interval()
    {
        return response()->json([
            'interval_minutes' => (int) Setting::get('polling_interval_minutes', 15),
        ]);
    }

    public function checkin(Request $request)
    {
        $validated = $request->validate([
            'hostname' => 'required|string|max:255',
            'lab_id' => 'nullable|integer',
            'local_version' => 'nullable|integer',
        ]);

        Device::updateOrCreate(
            [
                'hostname' => $validated['hostname'],
                'lab_id' => $validated['lab_id'] ?? null,
            ],
            [
                'local_version' => $validated['local_version'] ?? 0,
                'ip_address' => $request->ip(),
                'last_checkin_at' => now(),
            ]
        );

        return response()->json(['status' => 'ok']);
    }

    public function scriptRaw(Lab $lab)
    {
        $template = file_get_contents(resource_path('scripts/wallpaper-template.ps1'));
        $interval = Setting::get('polling_interval_minutes', 15);

        $content = str_replace(
            ['{{LAB_ID}}', '{{INTERVAL_MINUTES}}'],
            [$lab->id, $interval],
            $template
        );

        return response($content, 200, [
            'Content-Type' => 'text/plain; charset=utf-8',
        ]);
    }

    public function script(Lab $lab)
    {
        $template = file_get_contents(resource_path('scripts/installer-downloader-template.bat'));

        $content = str_replace('{{LAB_ID}}', $lab->id, $template);

        $filename = 'wallpaper-installer-' . Str::slug($lab->name) . '.bat';

        return response()->streamDownload(function () use ($content) {
            echo $content;
        }, $filename, [
            'Content-Type' => 'application/octet-stream',
        ]);
    }

    private function findActiveWallpaper(?string $labId): ?Wallpaper
    {
        if ($labId) {
            $wallpaper = Wallpaper::where('lab_id', $labId)
                ->where('is_active', true)
                ->first();

            if ($wallpaper) {
                return $wallpaper;
            }
        }

        return Wallpaper::whereNull('lab_id')
            ->where('is_active', true)
            ->first();
    }
}
