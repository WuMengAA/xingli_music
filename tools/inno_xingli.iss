; 星璃音乐 · Windows 正式安装向导（Inno Setup 7）
; 源：build/windows/x64/runner/Release（含全部 DLL + data/）
#define MyAppName "星璃音乐"
#define MyAppVersion "0.26.8.19"
#define MyAppPublisher "Stellara"
#define MySrc "D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release"
#define MyOut "D:\Stellara\Music\xingli_music\release"
#define MyIcon "D:\Stellara\Music\xingli_music\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{8F6E1A2B-3C5D-4A7E-9B12-7F4D6E2C1A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#MyOut}
OutputBaseFilename=星璃音乐_0.26.8.19_alpha_cl02_pc_星尘初聚_win_setup
SetupIconFile={#MyIcon}
UninstallDisplayIcon={#MyIcon}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64os
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
DirExistsWarning=no
; 卸载时清理整个安装目录
UninstallFilesDir={app}\Uninstall

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#MySrc}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\xingli_music.exe"; WorkingDir: "{app}"
Name: "{group}\{#MyAppName} 卸载"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\xingli_music.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{app}\xingli_music.exe"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
