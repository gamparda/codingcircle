#ifndef ManagedAgentPath
  #error ManagedAgentPath must point to the verified PCRemoteAgent.exe
#endif
#ifndef ManagedAgentVersion
  #error ManagedAgentVersion is required
#endif

[Setup]
AppId={{713BC021-4647-49CE-A3D3-F433055CD945}
AppName=PC Remote Agent (Internal Management)
AppVersion={#ManagedAgentVersion}
AppPublisher=Coding Circle
AppSupportURL=https://github.com/gamparda/chzzk-pc-remote-control
DefaultDirName={localappdata}\ChzzkAutoWatch
DisableDirPage=yes
DefaultGroupName=PC Remote Agent
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
Uninstallable=yes
UninstallDisplayIcon={app}\PCRemoteAgent.exe
OutputBaseFilename=PCRemoteAgentSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#ManagedAgentVersion}.0
VersionInfoDescription=PC Remote Agent - Internal Management

[Files]
Source: "{#ManagedAgentPath}"; DestDir: "{app}"; DestName: "PCRemoteAgent.exe"; Flags: ignoreversion
Source: "..\tools\managed_agent_config.json"; DestDir: "{app}"; DestName: "config.json"; Flags: onlyifdoesntexist uninsneveruninstall
Source: "managed_agent_stop.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userstartup}\ChzzkAutoWatch"; Filename: "{app}\PCRemoteAgent.exe"; WorkingDir: "{app}"
Name: "{group}\PC Remote Agent"; Filename: "{app}\PCRemoteAgent.exe"; WorkingDir: "{app}"
Name: "{group}\Stop PC Remote Agent"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\managed_agent_stop.ps1"" -InstallDirectory ""{app}"""; WorkingDir: "{app}"
Name: "{group}\Uninstall PC Remote Agent"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\PCRemoteAgent.exe"; WorkingDir: "{app}"; Flags: nowait

[Code]
function StopAgent(ScriptPath: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ScriptPath +
    '" -InstallDirectory "' + ExpandConstant('{app}') + '"', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
  if Result then
    Result := ResultCode = 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  ExtractTemporaryFile('managed_agent_stop.ps1');
  if not StopAgent(ExpandConstant('{tmp}\managed_agent_stop.ps1')) then
    Result := 'Could not stop the existing PC Remote Agent. Close it from the tray and retry.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := StopAgent(ExpandConstant('{app}\managed_agent_stop.ps1'));
end;
