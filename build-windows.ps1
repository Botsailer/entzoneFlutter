# Run from PowerShell: .\build-windows.ps1
# Builds the Windows app, then packages all required files into one setup EXE.
& (Join-Path $PSScriptRoot 'tool\build_windows_installer.ps1')
if (-not $?) { exit 1 }
