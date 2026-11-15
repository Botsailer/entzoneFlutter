Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'assets/img/depressedzone-tv-banner.png'
$androidDirectory = Join-Path $projectRoot 'android/app/src/main/res/drawable-nodpi'
$iosDirectory = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/LaunchImage.imageset'

New-Item -ItemType Directory -Path $androidDirectory -Force | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $androidDirectory 'depressedzone_splash.png') -Force

$original = [System.Drawing.Image]::FromFile($source)
try {
    foreach ($variant in @(
        @{ Name = 'LaunchImage.png'; Width = 280; Height = 158 },
        @{ Name = 'LaunchImage@2x.png'; Width = 560; Height = 315 },
        @{ Name = 'LaunchImage@3x.png'; Width = 840; Height = 473 }
    )) {
        $bitmap = [System.Drawing.Bitmap]::new($variant.Width, $variant.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($original, 0, 0, $variant.Width, $variant.Height)
            $bitmap.Save((Join-Path $iosDirectory $variant.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
}
finally {
    $original.Dispose()
}

Write-Output 'Updated Android and iOS splash assets.'
