; QuickSay Beta v1.9 Installer Script for Inno Setup
; Beta v1.9 Release — Visual overhaul + installer branding

#define MyAppName "QuickSay Beta"
#define MyAppVersion "1.9.0"
#define MyAppVerName "QuickSay Beta v1.9"
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
OutputBaseFilename=QuickSay_Beta_v1.9_Setup
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
WelcomeLabel2=QuickSay turns your voice into text — anywhere on Windows.%n%nThis will install QuickSay Beta v1.9 on your computer. You'll need a free Groq API key to get started.
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

; === CONFIG SEED TEMPLATE (clean defaults — NO secrets) ===
; T1.8 / T1.3-001: the installer must NOT ship the developer's live config.json —
; it carries a DPAPI-encrypted API key + personal prefs and (via launchAtStartup=1)
; silently armed autorun on every fresh install. Ship the pristine
; config.example.json as a read-only template instead; on first run the app seeds
; %APPDATA%\QuickSay\config.json from it (SeedConfigIfMissing in QuickSay.ahk).
; User config + dictionary now live under %APPDATA%\QuickSay\ (T1.3-023) and are
; preserved across upgrades by the app's migrate-or-seed logic, not the installer.
Source: "config.example.json"; DestDir: "{app}"; Flags: ignoreversion

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
; T1.8 / T1.3-023: user data now lives under %APPDATA%\QuickSay\ (co-located with
; license.dat). Pre-create the tree so first run is clean. uninsneveruninstall +
; the keep-prompt (CurUninstallStepChanged) own its removal — and license.dat is
; always preserved so an uninstall/reinstall can never reset a trial.
Name: "{userappdata}\QuickSay"; Flags: uninsneveruninstall
Name: "{userappdata}\QuickSay\data"; Flags: uninsneveruninstall
Name: "{userappdata}\QuickSay\data\audio"; Flags: uninsneveruninstall
Name: "{userappdata}\QuickSay\data\logs"; Flags: uninsneveruninstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\gui\assets\icon.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
; Launch onboarding for first-time installs (no onboarding_done marker)
; Otherwise launch main app
Filename: "{app}\QuickSay-Setup.exe"; Description: "Run mic check and setup"; Flags: nowait postinstall skipifsilent; Check: not OnboardingAlreadyDone
Filename: "{app}\{#MyAppExeName}"; Description: "Launch QuickSay"; Flags: nowait postinstall skipifsilent unchecked; Check: OnboardingAlreadyDone

[UninstallRun]
; T1.8 / T1.3-025: the APP (settings process) registers autorun via the value
; HKCU\Software\Microsoft\Windows\CurrentVersion\Run\QuickSay -> "{app}\QuickSay.exe".
; The installer owns a *different* startup mechanism ({userstartup} shortcut), so
; it never knew about this Run value — leaving it behind after uninstall pointing
; at a now-deleted exe (a ghost autorun / login error). Delete it on uninstall.
; (We intentionally do NOT delete it on normal app exit — when launchAtStartup is
;  on, the value is supposed to persist across reboots.)
Filename: "{cmd}"; Parameters: "/c reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v QuickSay /f"; Flags: runhidden; RunOnceId: "DelRunKey"

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
  // T1.8 / T1.3-023: the marker now lives under %APPDATA%\QuickSay\ for new
  // installs; also honor the legacy {app} location so upgrades from a pre-2.0
  // build do not re-run onboarding (the app migrates the marker on first launch).
  Result := FileExists(ExpandConstant('{userappdata}\QuickSay\data\onboarding_done'))
         or FileExists(ExpandConstant('{app}\data\onboarding_done'));
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

// Preserve user data on uninstall — ask before removing config/history.
// T1.8 / T1.3-023: user data lives under %APPDATA%\QuickSay\ now, and the
// trial/license file (license.dat) is ALWAYS preserved — deleting it would let a
// trial be reset via uninstall/reinstall, defeating the anti-abuse design.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  dataRoot: string;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    dataRoot := ExpandConstant('{userappdata}\QuickSay');
    if MsgBox('Do you want to keep your QuickSay settings and history?' #13#10 +
              '(config.json, dictionary, history, recordings)' #13#10#13#10 +
              'Your license / trial is always kept.',
              mbConfirmation, MB_YESNO) = IDNO then
    begin
      // Remove user content only. license.dat sits directly under the data root
      // (NOT under \data) and is intentionally left untouched here.
      DelTree(dataRoot + '\data', True, True, True);
      DeleteFile(dataRoot + '\config.json');
      DeleteFile(dataRoot + '\dictionary.json');
    end;
  end;
end;
