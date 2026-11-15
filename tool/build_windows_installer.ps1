param(
    [switch]$SkipFlutterBuild,
    [string]$FlutterPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content (Join-Path $projectRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw 'Could not read the application version from pubspec.yaml.'
}
$version = $Matches[1]

if (-not $SkipFlutterBuild) {
    if (-not $FlutterPath) {
        $flutterCommand = Get-Command flutter.bat, flutter -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($flutterCommand) {
            $FlutterPath = $flutterCommand.Source
        }
        elseif ($env:FLUTTER_ROOT) {
            $FlutterPath = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
        }
        elseif (Test-Path 'E:\flutter\bin\flutter.bat') {
            $FlutterPath = 'E:\flutter\bin\flutter.bat'
        }
        else {
            throw 'Flutter was not found. Pass -FlutterPath with the path to flutter.bat.'
        }
    }
    Push-Location $projectRoot
    try {
        # Windows PowerShell turns some native stderr lines into error records.
        # Flutter's NuGet notice is nonfatal; its exit code decides success.
        $ErrorActionPreference = 'Continue'
        & $FlutterPath build windows --release
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed ($LASTEXITCODE)." }
    }
    finally {
        $ErrorActionPreference = 'Stop'
        Pop-Location
    }
}

$release = Join-Path $projectRoot 'build\windows\x64\runner\Release'
foreach ($required in @('depressedzone.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat')) {
    if (-not (Test-Path (Join-Path $release $required))) {
        throw "Windows release is missing $required. Run without -SkipFlutterBuild."
    }
}

$installerDir = Join-Path $projectRoot 'build\installer'
New-Item -ItemType Directory -Path $installerDir -Force | Out-Null
$redist = Join-Path $installerDir 'vc_redist.x64.exe'
if (-not (Test-Path $redist)) {
    Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $redist
}
$signature = Get-AuthenticodeSignature -FilePath $redist
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'The Visual C++ redistributable is not signed by Microsoft.'
}

$isccCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 was not found. Install JRSoftware.InnoSetup with winget.' }

& $iscc "/DAppSource=$release" "/DAppVersion=$version" "/DRedistSource=$redist" "/O$installerDir" (Join-Path $PSScriptRoot 'windows_installer.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed ($LASTEXITCODE)." }

$output = Join-Path $installerDir "depressedzone-$version-windows-x64-setup.exe"
if (-not (Test-Path $output)) { throw "Installer output was not found: $output" }
Get-Item $output | Select-Object FullName, Length, LastWriteTime
