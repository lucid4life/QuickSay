; QuickSay Beta v1.8 Installer Script for Inno Setup
; Beta v1.8 Release — Visual overhaul + installer branding

#define MyAppName "QuickSay Beta"
#define MyAppVersion "1.8.0"
#define MyAppVerName "QuickSay Beta v1.8"
#define MyAppPublisher "QuickSay"
#define MyAppURL "https://quicksay.app"
#define MyAppExeName "QuickSay.exe"

[Setup]
AppId={{8B0A5C22-1234-5678-ABCD-1234567890AB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppVerName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\QuickSay Beta
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=installer
OutputBaseFilename=QuickSay_Beta_v1.8_Setup
SetupIconFile=gui\assets\icon.ico
LicenseFile=docs\LICENSE_AGREEMENT.rtf
Compression=lzma
SolidCompression=yes
WizardStyle=modern
WizardImageFile=gui\assets\wizard_large.bmp
WizardSmallImageFile=gui\assets\wizard_small.bmp
WizardImageBackColor=$120F0F
UninstallDisplayIcon={app}\gui\assets\icon.ico
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=QuickSay Beta — Voice-to-text dictation for Windows
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=Welcome to QuickSay
WelcomeLabel2=QuickSay turns your voice into text — anywhere on Windows.%n%nThis will install QuickSay Beta v1.8 on your computer. You'll need a free Groq API key to get started.
FinishedHeadingLabel=You're all set.
FinishedLabel=QuickSay Beta is ready to go. Launch it to complete a quick mic check and start dictating.
ClickFinish=Click Finish to begin.

[Tasks]
Name: "desktopicon"; Description: "Add a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "startupicon"; Description: "Launch QuickSay on startup"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; === CORE EXECUTABLES ===
; Main compiled executable (unified single-process version)
Source: "QuickSay.exe"; DestDir: "{app}"; Flags: ignoreversion

; Onboarding executable (first-time setup wizard)
Source: "QuickSay-Setup.exe"; DestDir: "{app}"; Flags: ignoreversion

; AHK Runtime for fallback script execution
Source: "AutoHotkey64.exe"; DestDir: "{app}"; Flags: ignoreversion

; FFmpeg — bundled for audio device support (USB mics, Bluetooth headsets, etc.)
Source: "ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion

; === FALLBACK SCRIPTS ===
Source: "onboarding_ui.ahk"; DestDir: "{app}"; Flags: ignoreversion

; === USER CONFIG (preserve on upgrade) ===
Source: "config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "dictionary.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

; === APP DATA (changelog for What's New feature) ===
Source: "data\changelog.json"; DestDir: "{app}\data"; Flags: ignoreversion

; === GUI (HTML, CSS, assets — exclude wizard BMPs from distribution) ===
Source: "gui\*"; DestDir: "{app}\gui"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "wizard_large.bmp,wizard_small.bmp"

; === LIBRARIES (WebView2, JSON, GDI, etc.) ===
Source: "lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs createallsubdirs

; === WebView2 64-bit loader DLL ===
Source: "64bit\*"; DestDir: "{app}\64bit"; Flags: ignoreversion recursesubdirs createallsubdirs

; === SOUND THEMES (exclude dev files) ===
Source: "sounds\*"; DestDir: "{app}\sounds"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.py,README.md"

; === LEGAL DOCUMENTS (exclude dev-only legal analysis) ===
Source: "docs\LICENSE_AGREEMENT.rtf"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "docs\LICENSES.html"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "docs\PRIVACY_POLICY.html"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "docs\TERMS_OF_SERVICE.html"; DestDir: "{app}\docs"; Flags: ignoreversion

; === THIRD-PARTY LICENSES ===
Source: "LICENSES\*"; DestDir: "{app}\LICENSES"; Flags: ignoreversion recursesubdirs createallsubdirs

; === PRIMARY LICENSE ===
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

; === WebView2 RUNTIME BOOTSTRAPPER (auto-install if missing, deleted after) ===
Source: "redist\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Dirs]
Name: "{app}\data"; Permissions: users-modify
Name: "{app}\data\audio"; Permissions: users-modify

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
; Launch onboarding for first-time installs (no onboarding_done marker)
; Otherwise launch main app
Filename: "{app}\QuickSay-Setup.exe"; Description: "Run mic check and setup"; Flags: nowait postinstall skipifsilent; Check: not OnboardingAlreadyDone
Filename: "{app}\{#MyAppExeName}"; Description: "Launch QuickSay"; Flags: nowait postinstall skipifsilent unchecked; Check: OnboardingAlreadyDone

[UninstallDelete]
; Clean up runtime/temp files (NOT user data)
Type: files; Name: "{app}\raw.wav"
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
// Check if onboarding was already completed (marker file exists)
function OnboardingAlreadyDone(): Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\data\onboarding_done'));
end;

// Close running QuickSay processes before install/uninstall
procedure CloseQuickSayProcesses();
var
  ResultCode: Integer;
begin
  // Kill compiled QuickSay processes (Settings is now part of QuickSay.exe)
  Exec('taskkill.exe', '/F /IM QuickSay.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM QuickSay-Setup.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Also kill any AHK processes that might be running scripts
  Exec('taskkill.exe', '/F /IM AutoHotkey64.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Small delay to ensure processes are fully terminated
  Sleep(500);
end;

function InitializeSetup(): Boolean;
begin
  // Close QuickSay before installing/upgrading
  CloseQuickSayProcesses();
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

// Close QuickSay before uninstalling
function InitializeUninstall(): Boolean;
begin
  CloseQuickSayProcesses();
  Result := True;
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
