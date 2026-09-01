; 星璃音乐 · Windows 正式安装向导（Inno Setup 7）
; 源：build/windows/x64/runner/Release（含全部 DLL + data/）
#define MyAppName "星璃音乐"
#define MyAppVersion "0.26.8.31"
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
OutputBaseFilename=星璃音乐_0.26.8.31_beta_cl03_pc_win_setup
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

; 应用私有数据目录：放数据库/封面/歌词/音效（不再塞进用户"文档"）。
; PrivilegesRequired=lowest → 标准用户装到 Program Files，需显式放行写权限，
; 否则 app 运行时写 {app}\data 会被系统拒（appDataDir() 会降级到 AppData）。
[Dirs]
Name: "{app}\data"; Permissions: users-modify

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\xingli_music.exe"; WorkingDir: "{app}"
Name: "{group}\{#MyAppName} 卸载"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\xingli_music.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{app}\xingli_music.exe"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
