param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
$AgentDirectory = [IO.Path]::GetFullPath($InstallDirectory)
$AgentExecutables = @(
    (Join-Path $AgentDirectory 'PCRemoteAgent.exe'),
    (Join-Path $AgentDirectory 'ChzzkAutoWatch.exe')
)

function Get-InstalledAgentProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='PCRemoteAgent.exe' OR Name='ChzzkAutoWatch.exe'" |
        Where-Object { $_.ExecutablePath -and $AgentExecutables -contains $_.ExecutablePath })
}

# Stop supervisors before their workers, so recovery cannot launch another worker.
# Match full executable paths: other users' or other installations' processes are left alone.
$AgentProcesses = @(Get-InstalledAgentProcesses)
foreach ($AgentProcess in @($AgentProcesses | Where-Object { $_.CommandLine -notmatch '--worker' })) {
    Stop-Process -Id $AgentProcess.ProcessId -Force -ErrorAction SilentlyContinue
}
foreach ($AgentProcess in @($AgentProcesses | Where-Object { $_.CommandLine -match '--worker' })) {
    Stop-Process -Id $AgentProcess.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 300
if (@(Get-InstalledAgentProcesses).Count -ne 0) {
    throw 'PC Remote Agent is still running. Close it from the tray and retry.'
}
