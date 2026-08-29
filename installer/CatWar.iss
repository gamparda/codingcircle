#define MyAppName "Cat War"
#define MyAppVersion "0.3.0"
#define MyAppPublisher "Coding Circle"
#define MyAppExeName "CatWar.exe"

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
OutputDir=..\dist
OutputBaseFilename=CatWarSetup
SetupIconFile=..\assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion=0.3.0.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Cat War Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면 바로가기 만들기"; GroupDescription: "추가 바로가기:"; Flags: unchecked

[Files]
Source: "..\builds\CatWar.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\server\StartServer.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ASSET_SOURCES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Cat War"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Cat War Dedicated Server"; Filename: "{app}\StartServer.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\사용 설명서"; Filename: "{app}\README.md"
Name: "{group}\Cat War 제거"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Cat War"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Cat War 실행"; Flags: nowait postinstall skipifsilent
