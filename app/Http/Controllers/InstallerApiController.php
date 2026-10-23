<?php

namespace App\Http\Controllers;

use App\Models\SoftwarePackage;
use App\Models\Unit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class InstallerApiController extends Controller
{
    public function units()
    {
        $units = Unit::orderBy('name')
            ->get(['id', 'name', 'slug']);

        return response()->json($units);
    }

    public function software(Unit $unit)
    {
        $packages = $unit->softwarePackages()
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->get();

        $baseUrl = rtrim(config('app.url'), '/') . '/api/labscript';

        $list = $packages->map(function (SoftwarePackage $pkg) use ($baseUrl, $unit) {
            $item = [
                'name' => $pkg->name,
                'file' => $pkg->file_name,
                'args' => $pkg->silent_args,
            ];

            // Resolve download URL
            if ($pkg->source_type === 'url') {
                $item['downloadUrl'] = $pkg->download_url;
            } else {
                // Determine which unit's folder has the file
                $sourceUnit = $pkg->source_unit_id ? $pkg->sourceUnit : $unit;
                $item['downloadUrl'] = "{$baseUrl}/units/{$sourceUnit->slug}/download/{$pkg->id}";
            }

            // Advanced config fields
            if ($pkg->advanced_config) {
                $config = $pkg->advanced_config;
                $sourceUnit = $pkg->source_unit_id ? $pkg->sourceUnit : $unit;

                if (! empty($config['postCopy'])) {
                    $item['postCopy'] = collect($config['postCopy'])->map(function ($copy) use ($baseUrl, $sourceUnit, $pkg) {
                        $downloadUrl = $pkg->source_type === 'url'
                            ? ($copy['sourceUrl'] ?? null)
                            : "{$baseUrl}/units/{$sourceUnit->slug}/download/{$pkg->id}?file=" . urlencode($copy['source']);

                        return [
                            'source' => $copy['source'],
                            'destination' => $copy['destination'],
                            'downloadUrl' => $downloadUrl,
                        ];
                    })->all();
                }

                if (! empty($config['postRun'])) {
                    $item['postRun'] = $config['postRun'];
                }

                if (! empty($config['postCommand'])) {
                    $item['postCommand'] = collect($config['postCommand'])->map(function ($cmd) use ($baseUrl, $sourceUnit, $pkg) {
                        $result = [
                            'exe' => $cmd['exe'],
                            'args' => $cmd['args'],
                        ];
                        if (! empty($cmd['download'])) {
                            $result['download'] = $cmd['download'];
                            if ($pkg->source_type !== 'url') {
                                $result['downloadUrl'] = "{$baseUrl}/units/{$sourceUnit->slug}/download/{$pkg->id}?file=" . urlencode($cmd['download']);
                            }
                        }

                        return $result;
                    })->all();
                }

                if (! empty($config['preDownload'])) {
                    $item['preDownload'] = collect($config['preDownload'])->map(function ($pre) use ($baseUrl, $sourceUnit, $pkg) {
                        if (is_string($pre)) {
                            return [
                                'file' => $pre,
                                'downloadUrl' => "{$baseUrl}/units/{$sourceUnit->slug}/download/{$pkg->id}?file=" . urlencode($pre),
                            ];
                        }

                        return $pre;
                    })->all();
                }
            }

            return $item;
        });

        return response()->json($list);
    }

    public function download(Unit $unit, SoftwarePackage $software)
    {
        // Allow downloading auxiliary files via ?file= param
        $requestedFile = request('file');

        if ($requestedFile) {
            // Serve auxiliary file from storage
            $sourceUnit = $software->source_unit_id ? $software->sourceUnit : $unit;
            $path = "installers/{$sourceUnit->slug}/{$requestedFile}";
        } else {
            if ($software->source_type !== 'upload') {
                return response()->json(['message' => 'This package uses external URL'], 400);
            }

            if (! $software->file_path) {
                return response()->json(['message' => 'No file uploaded'], 404);
            }

            $path = $software->file_path;
        }

        $disk = Storage::disk('public');

        if (! $disk->exists($path)) {
            return response()->json(['message' => 'File not found'], 404);
        }

        return $disk->response($path);
    }

    public function installerScript(Request $request)
    {
        $template = file_get_contents(resource_path('scripts/installer-template.ps1'));
        $baseUrl = rtrim(config('app.url'), '/') . '/api/labscript';

        $content = str_replace('{{BASE_URL}}', $baseUrl, $template);

        // If unit slug passed, inject auto-select
        $unitSlug = $request->query('unit');
        if ($unitSlug) {
            $content = str_replace('{{AUTO_UNIT}}', $unitSlug, $content);
        } else {
            $content = str_replace('{{AUTO_UNIT}}', '', $content);
        }

        return response($content, 200, [
            'Content-Type' => 'text/plain; charset=utf-8',
        ]);
    }

    public function installerBatGeneric()
    {
        $baseUrl = rtrim(config('app.url'), '/') . '/api/labscript';

        $content = <<<BAT
@echo off
:: LabScriptManager Installer — Pilih Unit
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Meminta hak Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (New-Object Net.WebClient).DownloadString('{$baseUrl}/installer-script')"
pause
BAT;

        return response()->streamDownload(function () use ($content) {
            echo $content;
        }, 'installer-menu.bat', [
            'Content-Type' => 'application/octet-stream',
        ]);
    }

    public function installerBat(Unit $unit)
    {
        $baseUrl = rtrim(config('app.url'), '/') . '/api/labscript';

        $content = <<<BAT
@echo off
:: LabScriptManager Installer — Unit: {$unit->name}
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Meminta hak Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (New-Object Net.WebClient).DownloadString('{$baseUrl}/installer-script?unit={$unit->slug}')"
pause
BAT;

        $filename = 'installer-' . $unit->slug . '.bat';

        return response()->streamDownload(function () use ($content) {
            echo $content;
        }, $filename, [
            'Content-Type' => 'application/octet-stream',
        ]);
    }
}
