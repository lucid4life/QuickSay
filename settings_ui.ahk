;@Ahk2Exe-SetCompanyName QuickSay
;@Ahk2Exe-SetDescription QuickSay Beta v1.9 Settings
;@Ahk2Exe-SetFileVersion 1.9.0.0
;@Ahk2Exe-SetProductName QuickSay Beta v1.9
;@Ahk2Exe-SetProductVersion 1.9.0.0
;@Ahk2Exe-SetCopyright Copyright (c) 2024-2026 QuickSay
;@Ahk2Exe-SetOrigFilename QuickSay-Settings.exe
;@Ahk2Exe-SetMainIcon gui\assets\icon.ico

#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; --- SET APP IDENTITY FOR WINDOWS TASKBAR ---
; Ensures this process groups with the main launcher (same AppUserModelID)
DllCall("Shell32\SetCurrentProcessExplicitAppUserModelID", "WStr", "QuickSay.VoiceToText.1.9")

; ==============================================================================
; QuickSay Beta v1.9 Settings UI (WebView2)
; Uses shared SettingsUI class from lib/settings-ui.ahk
; ==============================================================================

#Include %A_ScriptDir%\lib\WebView2.ahk
#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\lib\dpapi.ahk
#Include %A_ScriptDir%\lib\ed25519.ahk
#Include %A_ScriptDir%\lib\license.ahk
#Include %A_ScriptDir%\lib\settings-ui.ahk

; ==============================================================================
; STARTUP
; ==============================================================================
try {
    try {
        SettingsUI.Show()
    } catch as err {
        MsgBox("Show Error: " err.Message)
    }
} catch as err {
    MsgBox("Fatal Error: " err.Message, "QuickSay Settings", 16)
}
