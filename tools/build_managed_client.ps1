param(
    [string]$AgentPath = '',
    [string]$IsccPath = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Pin = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'managed_agent.json') -Raw | ConvertFrom-Json
$Output = Join-Path $Root 'dist\managed'

# This tool is intentionally separate from build_release.ps1 and the public Pages workflow.
# Its output must only be deployed to PCs managed by the deploying administrator.
if (-not $AgentPath) {
    $PayloadDirectory = Join-Path $Output $Pin.release
    New-Item -ItemType Directory -Path $PayloadDirectory -Force | Out-Null
    & gh release download $Pin.release --repo $Pin.repository --pattern $Pin.asset --dir $PayloadDirectory --skip-existing
    if ($LASTEXITCODE -ne 0) { throw 'Agent download failed. Authenticate gh for the private repository, or pass -AgentPath.' }
    $AgentPath = Join-Path $PayloadDirectory $Pin.asset
}
$AgentPath = (Resolve-Path -LiteralPath $AgentPath -ErrorAction Stop).Path
$Hasher = [Security.Cryptography.SHA256]::Create()
$PayloadStream = [IO.File]::OpenRead($AgentPath)
try {
    $PayloadHash = [BitConverter]::ToString($Hasher.ComputeHash($PayloadStream)).Replace('-', '').ToLowerInvariant()
} finally {
    $PayloadStream.Dispose()
    $Hasher.Dispose()
}
if ($PayloadHash -ne $Pin.sha256) {
    throw 'Agent SHA-256 mismatch. Only the pinned, verified agent release can be packaged.'
}
if (-not (Test-Path -LiteralPath (Join-Path $Root 'builds\CatWar.exe') -PathType Leaf)) {
    throw 'Build the Windows client with tools/build_release.ps1 first.'
}
if (-not $IsccPath) {
    $Compiler = Get-Command iscc -ErrorAction SilentlyContinue
    if ($Compiler) { $IsccPath = $Compiler.Source }
    else { $IsccPath = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe' }
}
$IsccPath = (Resolve-Path -LiteralPath $IsccPath -ErrorAction Stop).Path
$Release = Get-Content -LiteralPath (Join-Path $Root 'release.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $Output -Force | Out-Null

& $IsccPath '/Qp' "/O$Output" "/DManagedAgentPath=$AgentPath" "/DManagedAgentVersion=$($Pin.version)" (Join-Path $Root 'installer\PCRemoteAgent.iss')
if ($LASTEXITCODE -ne 0) { throw 'PC Remote Agent installer build failed.' }
$AgentSetup = Join-Path $Output 'PCRemoteAgentSetup.exe'
& $IsccPath '/Qp' "/O$Output" "/DMyAppVersion=$($Release.windows_version)" "/DManagedAgentSetup=$AgentSetup" (Join-Path $Root 'installer\CatWar.iss')
if ($LASTEXITCODE -ne 0) { throw 'Managed Windows client installer build failed.' }
Write-Host "Internal managed installer: $(Join-Path $Output 'CatWarManagedSetup.exe')"
