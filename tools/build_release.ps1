param(
    [string]$GodotPath = "",
    [string]$IsccPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Builds = Join-Path $Root "builds"
$Dist = Join-Path $Root "dist"

function Resolve-Godot {
    param([string]$Requested)
    if ($Requested -and (Test-Path $Requested)) { return (Resolve-Path $Requested).Path }
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $packages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $found = Get-ChildItem $packages -Filter "Godot*_console.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*GodotEngine.GodotEngine*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Godot console executable not found. Install Godot or pass -GodotPath."
}

function Resolve-Iscc {
    param([string]$Requested)
    if ($Requested -and (Test-Path $Requested)) { return (Resolve-Path $Requested).Path }
    $command = Get-Command iscc -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $default = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"
    if (Test-Path $default) { return $default }
    throw "Inno Setup compiler not found. Install with: winget install --id JRSoftware.InnoSetup --exact"
}

$Godot = Resolve-Godot $GodotPath
$Iscc = Resolve-Iscc $IsccPath
New-Item -ItemType Directory -Force $Builds, $Dist | Out-Null

Write-Host "[1/4] Running game rule tests..." -ForegroundColor Cyan
& $Godot --headless --path $Root --script res://tests/run_tests.gd
if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE" }

Write-Host "[2/4] Exporting Windows game/server executable..." -ForegroundColor Cyan
& $Godot --headless --path $Root --export-release "Windows Desktop" (Join-Path $Builds "CatWar.exe")
if ($LASTEXITCODE -ne 0) { throw "Godot export failed with exit code $LASTEXITCODE" }

Write-Host "[3/4] Verifying offline AI mode..." -ForegroundColor Cyan
& (Join-Path $Builds "CatWar.exe") --headless -- --ai-smoke
if ($LASTEXITCODE -ne 0) { throw "Exported executable smoke test failed with exit code $LASTEXITCODE" }

Write-Host "[4/4] Building Windows installer..." -ForegroundColor Cyan
& $Iscc (Join-Path $Root "installer\CatWar.iss")
if ($LASTEXITCODE -ne 0) { throw "Installer build failed with exit code $LASTEXITCODE" }

Write-Host "Build complete:" -ForegroundColor Green
Write-Host "  Game/server: $(Join-Path $Builds 'CatWar.exe')"
Write-Host "  Installer:   $(Join-Path $Dist 'CatWarSetup.exe')"
