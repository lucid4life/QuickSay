#Requires AutoHotkey v2.0
#SingleInstance

; ==============================================================================
; QuickSay Launcher v2.3
; Strict AHK v2 Syntax - No #Persistent
; ==============================================================================

; --- GLOBAL VARIABLES ---
global EngineScript := A_ScriptDir "\QuickSay-Next.ahk"
global SettingsScript := A_ScriptDir "\settings_ui.ahk"
global OnboardingScript := A_ScriptDir "\onboarding_ui.ahk"
global HistoryFile := A_ScriptDir "\data\history.json"
global StatsFile := A_ScriptDir "\data\statistics.json"

; --- AHK RUNTIME ---
; When compiled, A_AhkPath points to the compiled .exe itself (useless for child scripts).
; We ship AutoHotkey64.exe alongside as the runtime interpreter for child .ahk scripts.
global AhkRuntime := A_ScriptDir "\AutoHotkey64.exe"
if !FileExist(AhkRuntime) {
    ; Fallback: if running from source (not compiled), use A_AhkPath
    AhkRuntime := A_AhkPath
}

global EnginePID := 0
global CurrentStatusItem := "Engine: Stopped" ; Track current menu item name for renaming

; --- FIRST RUN: Show onboarding wizard before anything else ---
if NeedsOnboarding() {
    RunOnboarding()
}

; --- SETUP TRAY ---
SetupTray()

; --- STARTUP ---
StartEngine()
SetTimer(CheckEngineHealth, 5000) ; Monitor every 5 seconds

; --- MESSAGE HANDLERS ---
; Listen for status updates from Engine (0x5556)
OnMessage(0x5556, HandleStatusUpdate)


; ==============================================================================
; FUNCTIONS
; ==============================================================================

SetupTray() {
    global CurrentStatusItem
    
    Tray := A_TrayMenu
    Tray.Delete() ; Clear default items

    ; Status Indicator (Non-clickable, but we track its name)
    Tray.Add(CurrentStatusItem, MenuStatusHandler) 
    Tray.Disable(CurrentStatusItem)
    Tray.Add() ; Separator

    ; Main Actions
    Tray.Add("Settings", LaunchSettings)
    Tray.Add("Restart Engine", RestartEngine)
    Tray.Add("Reload Config", SendReloadToEngine)
    Tray.Add() ; Separator
    
    ; Data
    Tray.Add("Test Recording", TestRecording)
    Tray.Add() ; Separator

    ; Exit
    Tray.Add("Exit", ExitAppClean)

    ; Set Default Action
    Tray.Default := "Settings"
    
    ; Initial Tooltip
    A_IconTip := "QuickSay v2.3"

    ; Custom tray icon
    iconPath := A_ScriptDir "\gui\assets\icon.ico"
    if FileExist(iconPath)
        TraySetIcon(iconPath)
}

StartEngine() {
    global EnginePID, EngineScript
    
    ; Check if already running via PID
    if (EnginePID > 0 && ProcessExist(EnginePID))
        return
        
    ; Check via Window Class to be safe (prevent duplicates)
    DetectHiddenWindows(true)
    if WinExist("QuickSay-Next.ahk ahk_class AutoHotkey") {
        EnginePID := WinGetPID("QuickSay-Next.ahk ahk_class AutoHotkey")
        UpdateStatusDisplay(1) ; Assume Idle if found running
        return
    }
    
    ; Launch
    try {
        if FileExist(EngineScript) {
            Run(AhkRuntime ' "' EngineScript '"', A_ScriptDir, "Hide", &EnginePID)
            UpdateStatusDisplay(1) ; Idle
        } else {
            MsgBox("Engine script not found: " EngineScript, "Error", 16)
        }
    } catch as err {
        MsgBox("Failed to launch engine: " err.Message, "Launcher Error", 16)
    }
}

CheckEngineHealth() {
    global EnginePID
    
    isRunning := false
    if (EnginePID > 0 && ProcessExist(EnginePID)) {
        isRunning := true
    } else {
        ; Double check if process exists but we lost PID track
        DetectHiddenWindows(true)
        if WinExist("QuickSay-Next.ahk ahk_class AutoHotkey") {
            EnginePID := WinGetPID("QuickSay-Next.ahk ahk_class AutoHotkey")
            isRunning := true
        }
    }
    
    if (!isRunning) {
        UpdateStatusDisplay(0) ; Stopped
    }
}

RestartEngine(*) {
    global EnginePID
    if (EnginePID > 0 && ProcessExist(EnginePID)) {
        ProcessClose(EnginePID)
    }
    Sleep(500)
    StartEngine()
    TrayTip("QuickSay", "Engine restarted manually", 1)
}

SendReloadToEngine(*) {
    DetectHiddenWindows(true)
    if WinExist("QuickSay-Next.ahk ahk_class AutoHotkey") {
        PostMessage(0x5555, 1, 0)
        TrayTip("QuickSay", "Reload signal sent", 1)
    } else {
        StartEngine()
    }
}

HandleStatusUpdate(wParam, lParam, msg, hwnd) {
    ; wParam: 1=Idle, 2=Recording, 3=Processing
    UpdateStatusDisplay(wParam)
}

UpdateStatusDisplay(statusCode) {
    global CurrentStatusItem
    
    newStatus := "Engine: Stopped"
    tipText := "QuickSay - Stopped"
    
    if (statusCode == 1) {
        newStatus := "Engine: Idle"
        tipText := "QuickSay v2.3 - Idle"
    } else if (statusCode == 2) {
        newStatus := "Engine: Recording..."
        tipText := "QuickSay v2.3 - Recording..."
    } else if (statusCode == 3) {
        newStatus := "Engine: Processing..."
        tipText := "QuickSay v2.3 - Processing..."
    } else if (statusCode == 0) {
        newStatus := "Engine: Stopped"
        tipText := "QuickSay v2.3 - Stopped"
    }
    
    ; Only rename if changed
    if (CurrentStatusItem != newStatus) {
        try {
            A_TrayMenu.Rename(CurrentStatusItem, newStatus)
            CurrentStatusItem := newStatus
        } catch {
            ; If rename fails, maybe item missing? Rebuild?
            ; For now, just ignore
        }
    }
    
    A_IconTip := tipText
}

LaunchSettings(*) {
    global SettingsScript
    try {
        if FileExist(SettingsScript)
            Run(AhkRuntime ' "' SettingsScript '"')
        else
            MsgBox("Settings script not found.", "Error", 16)
    } catch as err {
        MsgBox("Failed to open settings: " err.Message)
    }
}

TestRecording(*) {
    MsgBox("Please press your configured hotkey to test recording.", "Test Mode")
}



ExitAppClean(*) {
    global EnginePID
    
    ; Kill Engine
    if (EnginePID > 0 && ProcessExist(EnginePID)) {
        ProcessClose(EnginePID)
    }
    
    ; Kill Settings if open
    DetectHiddenWindows(true)
    if WinExist("QuickSay Settings") {
        WinClose("QuickSay Settings")
    }
    
    ExitApp()
}

MenuStatusHandler(*) {
    ; No-op
}

; ==============================================================================
; ONBOARDING (First-Run Wizard)
; ==============================================================================

NeedsOnboarding() {
    ; Show onboarding if:
    ; 1. No config.json exists (fresh install), OR
    ; 2. Config exists but API key is empty AND onboarding marker doesn't exist
    markerFile := A_ScriptDir "\data\onboarding_done"

    if FileExist(markerFile)
        return false  ; Already completed onboarding

    if !FileExist(A_ScriptDir "\config.json")
        return true   ; Fresh install — no config at all

    ; Config exists — check if API key is empty
    try {
        raw := FileRead(A_ScriptDir "\config.json", "UTF-8")
        if RegExMatch(raw, '"groqApiKey"\s*:\s*"([^"]*)"', &match) {
            if (match[1] == "")
                return true  ; Config exists but no API key set
        }
    }

    return false
}

RunOnboarding() {
    global OnboardingScript
    if !FileExist(OnboardingScript) {
        ; Onboarding script missing — skip gracefully
        return
    }

    ; Run onboarding wizard and WAIT for it to complete
    try {
        RunWait(AhkRuntime ' "' OnboardingScript '"', A_ScriptDir)
    } catch as err {
        ; If onboarding fails, continue anyway — user can set key in Settings
    }

    ; After onboarding, reload config if engine is running
    Sleep(300)
    SendReloadToEngine()
}
