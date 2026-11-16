; Rossi Windows 安装器（Inno Setup 7）
;
; 由 script/build/build_windows.dart 调用：
;   ISCC.exe -dAppVersion=... -dVersionQuad=... -dStageDir=... -dOutputDir=... breeze.iss
;
; 手动编译（需先构建 Flutter Windows Release）：
;   "%ProgramFiles%\Inno Setup 7\ISCC.exe" windows-installer\breeze.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef VersionQuad
  #define VersionQuad "0.0.0.0"
#endif

#ifndef StageDir
  #define StageDir "..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\build\windows\installer"
#endif

[Setup]
AppId={{C6A4E2B1-7F90-4B13-A5D8-9E2C4F6B8A10}
AppName=Rossi
AppVersion={#AppVersion}
AppVerName=Rossi v{#AppVersion}
AppPublisher=Rossi
AppPublisherURL=https://github.com/HibernalGlow/rossi
AppSupportURL=https://github.com/HibernalGlow/rossi/issues
AppUpdatesURL=https://github.com/HibernalGlow/rossi/releases
DefaultDirName={code:GetDefaultDir}
DefaultGroupName=Rossi
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=windows-installer
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Release\rossi.exe
UninstallDisplayName=Rossi
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern dynamic
ShowLanguageDialog=yes
LanguageDetectionMethod=uilanguage
CloseApplications=no
RestartApplications=no
VersionInfoCompany=Rossi
VersionInfoDescription=Rossi 安装程序
VersionInfoProductName=Rossi
VersionInfoProductVersion={#VersionQuad}
VersionInfoTextVersion={#AppVersion}
VersionInfoVersion={#VersionQuad}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}\Release"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Rossi"; Filename: "{app}\Release\rossi.exe"; WorkingDir: "{app}\Release"
Name: "{userdesktop}\Rossi"; Filename: "{app}\Release\rossi.exe"; WorkingDir: "{app}\Release"; Tasks: desktopicon

[Run]
Filename: "{app}\Release\rossi.exe"; WorkingDir: "{app}\Release"; Description: "{cm:LaunchProgram,Rossi}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 与旧安装器一致：卸载时删除整个安装目录
Type: filesandordirs; Name: "{app}"
; 旧 Tauri 安装器留下的路径记录文件

[Code]
const
  LEGACY_UNINSTALL_KEY =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\Breeze';

// 去掉尾部分隔符，避免应用目录与注册表中的 InstallLocation 因末尾反斜杠不一致。
function NormalizeDir(const Dir: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Dir);
end;

{ 判断是否由旧 Tauri 安装器写入的卸载项。旧版 UninstallString 指向 uninstall.bat。 }
function IsLegacyBreezeInstall: Boolean;
var
  UninstallCmd: String;
begin
  Result :=
    RegQueryStringValue(HKCU, LEGACY_UNINSTALL_KEY, 'UninstallString', UninstallCmd)
    and (Pos('uninstall.bat', Lowercase(UninstallCmd)) > 0);
end;

{ Rossi 使用独立安装目录；旧 Breeze 安装保留给数据迁移与共存使用。 }
function GetDefaultDir(Param: String): String;
begin
  Result := ExpandConstant('{localappdata}\rossi');
end;

function IsAppRunning: Boolean;
var
  ResultCode: Integer;
begin
  Result :=
    Exec(ExpandConstant('{cmd}'),
      '/c tasklist /FI "IMAGENAME eq rossi.exe" /NH | find /I "rossi.exe" >nul',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    and (ResultCode = 0);
end;

{ 应用启动时会监听命名管道，任意连接都会触发优雅退出。 }
procedure SendShutdownSignal;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{cmd}'),
    '/c echo. > \\.\pipe\com.hibernalglow.rossi_shutdown_signal',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure EnsureAppClosed;
var
  I, ResultCode: Integer;
begin
  if not IsAppRunning then
    Exit;

  SendShutdownSignal;

  { 等待优雅退出，最多 15 秒；超时后强制结束。 }
  for I := 1 to 30 do
  begin
    Sleep(500);
    if not IsAppRunning then
      Exit;
  end;

  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM rossi.exe /F',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
end;

{ 旧 Breeze 的快捷方式与安装目录保留，确保两个应用可以并存。 }
procedure CleanupLegacyShortcuts;
begin
  // Rossi 使用独立名称，不会覆盖旧 Breeze 的快捷方式。
end;

{ 新旧应用共存：不删除旧 Breeze 的卸载项、安装目录或数据。 }
procedure RemoveLegacyRegistration;
begin
  // 旧应用仍需可卸载、可启动，迁移由 Rossi 首次启动逻辑负责。
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    EnsureAppClosed;
    CleanupLegacyShortcuts;

    { 整体替换旧 Release，避免残留旧 DLL / 资源；必须在 [Files] 复制前完成。 }
    DelTree(ExpandConstant('{app}\Release'), True, True, True);
    DeleteFile(ExpandConstant('{app}\uninstall.bat'));
  end
  else if CurStep = ssPostInstall then
    RemoveLegacyRegistration;
end;

function InitializeUninstall(): Boolean;
begin
  EnsureAppClosed;
  Result := True;
end;
