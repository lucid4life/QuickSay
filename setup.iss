; QuickSay Installer Script for Inno Setup
; Version 2.3 — Built from Development/ folder

#define MyAppName "QuickSay"
#define MyAppVersion "2.3"
#define MyAppPublisher "QuickSay"
#define MyAppURL "https://quicksay.app"
#define MyAppExeName "QuickSay-Launcher.exe"

[Setup]
AppId={{8B0A5C22-1234-5678-ABCD-1234567890AB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=installer
OutputBaseFilename=QuickSay_Setup_v{#MyAppVersion}
SetupIconFile=dist\gui\assets\icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\gui\assets\icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupicon"; Description: "Run QuickSay when Windows starts"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main scripts (interpreter mode — compiled AHK .exe + .ahk source)
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\AutoHotkey64.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\QuickSay-Launcher.ahk"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\QuickSay-Next.ahk"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\settings_ui.ahk"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\onboarding_ui.ahk"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\record.bat"; DestDir: "{app}"; Flags: ignoreversion

; Config — only install if not already present (preserve user settings on upgrade)
Source: "dist\config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "dist\dictionary.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

; GUI files
Source: "dist\gui\*"; DestDir: "{app}\gui"; Flags: ignoreversion recursesubdirs createallsubdirs

; Libraries
Source: "dist\lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs createallsubdirs

; Sounds
Source: "dist\sounds\*"; DestDir: "{app}\sounds"; Flags: ignoreversion recursesubdirs createallsubdirs

; FFmpeg — bundled for audio device support (USB mics, Bluetooth headsets, etc.)
Source: "dist\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion

; WebView2 bootstrapper — installs runtime if not present (needed for Settings + Onboarding UI)
Source: "dist\redist\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Dirs]
Name: "{app}\data"; Permissions: users-modify
Name: "{app}\data\audio"; Permissions: users-modify

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up runtime files but NOT user data
Type: files; Name: "{app}\raw.wav"
Type: files; Name: "{app}\record.bat"
Type: files; Name: "{app}\response.txt"
Type: files; Name: "{app}\payload.json"
Type: files; Name: "{app}\clean_response.txt"
Type: files; Name: "{app}\log.txt"
Type: files; Name: "{app}\debug_log.txt"
Type: files; Name: "{app}\hotkey_debug.log"
Type: files; Name: "{app}\ffmpeg_stderr.txt"
Type: files; Name: "{app}\ffmpeg_stdout.txt"
Type: files; Name: "{app}\data\onboarding_debug.log"
Type: files; Name: "{app}\data\onboarding_done"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

function IsWebView2Installed(): Boolean;
var
  RegValue: string;
begin
  // Check per-user install
  Result := RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', RegValue);
  if Result then
    Result := (RegValue <> '') and (RegValue <> '0.0.0.0');
  if not Result then
  begin
    // Check per-machine install
    Result := RegQueryStringValue(HKLM, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', RegValue);
    if Result then
      Result := (RegValue <> '') and (RegValue <> '0.0.0.0');
  end;
  if not Result then
  begin
    // Check WOW6432Node (64-bit systems)
    Result := RegQueryStringValue(HKLM, 'Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', RegValue);
    if Result then
      Result := (RegValue <> '') and (RegValue <> '0.0.0.0');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if not IsWebView2Installed() then
    begin
      // Install WebView2 Runtime silently
      Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

// Preserve user data on uninstall — ask before removing config/history
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('Do you want to keep your QuickSay settings and history?' #13#10 +
              '(config.json, dictionary, history, recordings)',
              mbConfirmation, MB_YESNO) = IDNO then
    begin
      DelTree(ExpandConstant('{app}\data'), True, True, True);
      DeleteFile(ExpandConstant('{app}\config.json'));
      DeleteFile(ExpandConstant('{app}\dictionary.json'));
    end;
  end;
end;
