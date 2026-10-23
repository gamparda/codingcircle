[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
if (-not ('PCRemoteAgent.NativePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
namespace PCRemoteAgent {
    public static class NativePath {
        [DllImport("kernel32.dll", EntryPoint = "GetLongPathNameW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        public static extern uint GetLongPathName(string path, StringBuilder result, uint length);
    }
}
'@
}

function Get-LongAgentPath([string]$Path) {
    $FullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $FullPath)) { return $FullPath }
    $Buffer = New-Object Text.StringBuilder 32768
    $Length = [PCRemoteAgent.NativePath]::GetLongPathName($FullPath, $Buffer, $Buffer.Capacity)
    if ($Length -eq 0) { throw (New-Object ComponentModel.Win32Exception ([Runtime.InteropServices.Marshal]::GetLastWin32Error())) }
    if ($Length -ge $Buffer.Capacity) { throw 'Agent path is too long.' }
    return $Buffer.ToString()
}

# Hosted Windows runners use TEMP under C:\Users\RUNNER~1, while process image
# APIs return C:\Users\runneradmin. Normalize DOS aliases explicitly on both sides.
$AgentDirectory = Get-LongAgentPath $InstallDirectory
Write-Verbose "Agent install directory: $AgentDirectory"
$AgentExecutables = @(
    (Join-Path $AgentDirectory 'PCRemoteAgent.exe'),
    (Join-Path $AgentDirectory 'ChzzkAutoWatch.exe')
)

function Get-InstalledAgentProcesses {
    # Use native process handles for image paths and lifetime checks. WMI can omit
    # ExecutablePath on service-hosted runners, even for processes owned by this user.
    foreach ($Candidate in @(Get-Process -Name PCRemoteAgent, ChzzkAutoWatch -ErrorAction SilentlyContinue)) {
        try { $CandidatePath = $Candidate.Path } catch { continue }
        Write-Verbose "Inspecting process $($Candidate.Id): $CandidatePath"
        if ($CandidatePath) {
            try { $CandidatePath = Get-LongAgentPath $CandidatePath } catch { continue }
        }
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
