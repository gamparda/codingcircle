param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
$AgentDirectory = [IO.Path]::GetFullPath($InstallDirectory)
if (Test-Path -LiteralPath $AgentDirectory -PathType Container) {
    $AgentDirectory = (Get-Item -LiteralPath $AgentDirectory -Force).FullName
}
$AgentExecutables = @(
    (Join-Path $AgentDirectory 'PCRemoteAgent.exe'),
    (Join-Path $AgentDirectory 'ChzzkAutoWatch.exe')
)

function Get-InstalledAgentProcesses {
    # Use native process handles for image paths and lifetime checks. WMI can omit
    # ExecutablePath on service-hosted runners, even for processes owned by this user.
    foreach ($Candidate in @(Get-Process -Name PCRemoteAgent, ChzzkAutoWatch -ErrorAction SilentlyContinue)) {
        try { $CandidatePath = $Candidate.Path } catch { continue }
        if (-not $CandidatePath -or $AgentExecutables -notcontains $CandidatePath) { continue }
        $Metadata = Get-CimInstance Win32_Process -Filter "ProcessId=$($Candidate.Id)"
        [pscustomobject]@{ Process = $Candidate; ProcessId = $Candidate.Id; CommandLine = $Metadata.CommandLine }
    }
}

# Stop supervisors before their workers, so recovery cannot launch another worker.
# Match full executable paths: other users' or other installations' processes are left alone.
$AgentProcesses = @(Get-InstalledAgentProcesses)
foreach ($AgentProcess in @($AgentProcesses | Where-Object { $_.CommandLine -notmatch '--worker' })) {
    try {
        if (-not $AgentProcess.Process.HasExited) { $AgentProcess.Process.Kill() }
    } catch {
        if (-not $AgentProcess.Process.HasExited) { throw }
    }
}
foreach ($AgentProcess in @($AgentProcesses | Where-Object { $_.CommandLine -match '--worker' })) {
    try {
        if (-not $AgentProcess.Process.HasExited) { $AgentProcess.Process.Kill() }
    } catch {
        if (-not $AgentProcess.Process.HasExited) { throw }
    }
}
foreach ($AgentProcess in $AgentProcesses) {
    if (-not $AgentProcess.Process.WaitForExit(5000)) { throw 'Timed out waiting for PC Remote Agent to exit.' }
}
if (@(Get-InstalledAgentProcesses).Count -ne 0) {
    throw 'PC Remote Agent is still running. Close it from the tray and retry.'
}
