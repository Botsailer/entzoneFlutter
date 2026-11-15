Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'assets/img/depressedzone-icon.png'
$original = [System.Drawing.Image]::FromFile($source)

function Save-IconPng([string]$path, [int]$size, [double]$fill = 1.0) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Black)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $inner = [int][Math]::Round($size * $fill)
        $inset = [int][Math]::Floor(($size - $inner) / 2)
        $graphics.DrawImage($original, $inset, $inset, $inner, $inner)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    $iosDirectory = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    $iosManifest = Get-Content -Raw (Join-Path $iosDirectory 'Contents.json') | ConvertFrom-Json
    foreach ($entry in $iosManifest.images) {
        if (-not $entry.filename) { continue }
        $points = [double]($entry.size.Split('x')[0])
        $scale = [int]($entry.scale.TrimEnd('x'))
        Save-IconPng (Join-Path $iosDirectory $entry.filename) ([int]($points * $scale))
    }

    $macDirectory = Join-Path $projectRoot 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    foreach ($size in @(16, 32, 64, 128, 256, 512, 1024)) {
        Save-IconPng (Join-Path $macDirectory "app_icon_$size.png") $size
    }

    $webDirectory = Join-Path $projectRoot 'web'
    Save-IconPng (Join-Path $webDirectory 'favicon.png') 16
    foreach ($size in @(192, 512)) {
        Save-IconPng (Join-Path $webDirectory "icons/Icon-$size.png") $size
        Save-IconPng (Join-Path $webDirectory "icons/Icon-maskable-$size.png") $size 0.78
    }
}
finally {
    $original.Dispose()
}

Write-Output 'Updated iOS, macOS, and web icons.'
