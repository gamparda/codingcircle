#define MyAppName "Cat War"
#ifndef MyAppVersion
#define MyAppVersion "0.3.0"
#endif
#define MyAppPublisher "Coding Circle"
#define MyAppExeName "CatWar.exe"
#ifndef ManagedAgentSetup
  #error ManagedAgentSetup must point to the verified PCRemoteAgentSetup.exe
#endif
#ifndef MySetupFilename
  #define MySetupFilename "CatWarSetup"
#endif

[Setup]
AppId={{A0FE6D27-56C8-4C57-B58B-19F7A8C9D341}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/gamparda/codingcircle
AppSupportURL=https://github.com/gamparda/codingcircle
DefaultDirName={localappdata}\Programs\Cat War
DefaultGroupName=Cat War
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
Uninstallable=yes
OutputDir=..\dist
OutputBaseFilename={#MySetupFilename}
SetupIconFile=..\assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Cat War Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면 바로가기 만들기"; GroupDescription: "추가 바로가기:"; Flags: unchecked
Name: "pcremoteagent"; Description: "PC Remote Agent 설치 및 관리 서버 운영자의 PC 원격 제어 허용"; GroupDescription: "명령 실행, 파일 접근, 화면 보기, 키보드/마우스 조작 (pc-api.ruellyya.kr):"; Flags: checkedonce

[Files]
Source: "..\builds\CatWar.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\server\StartServer.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\server\StartAssist.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ASSET_SOURCES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ManagedAgentSetup}"; DestDir: "{tmp}"; DestName: "PCRemoteAgentSetup.exe"; Flags: deleteafterinstall; Tasks: pcremoteagent; Check: ShouldInstallManagedAgent; AfterInstall: InstallManagedAgent

[Icons]
Name: "{group}\Cat War"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Cat War Dedicated Server"; Filename: "{app}\StartServer.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Keepfall Assist Server"; Filename: "{app}\StartAssist.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\사용 설명서"; Filename: "{app}\README.md"
Name: "{group}\Cat War 제거"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Cat War"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Cat War 실행"; Flags: nowait postinstall skipifsilent

[Code]
function ShouldInstallManagedAgent: Boolean;
begin
  { A silent game updater cannot obtain a new remote-control permission. }
  { Bots can explicitly opt in; existing managed installations can be updated. }
  Result := (not WizardSilent) or
    (ExpandConstant('{param:INSTALLPCREMOTEAGENT|0}') = '1') or
    RegKeyExists(HKCU64, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{713BC021-4647-49CE-A3D3-F433055CD945}_is1');
end;

procedure InstallManagedAgent;
var
  ResultCode: Integer;
begin
  if not Exec(ExpandConstant('{tmp}\PCRemoteAgentSetup.exe'),
    '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) then
    RaiseException('PC Remote Agent installation could not be started.');
  if ResultCode <> 0 then
    RaiseException(Format('PC Remote Agent installation failed (exit %d).', [ResultCode]));
end;
