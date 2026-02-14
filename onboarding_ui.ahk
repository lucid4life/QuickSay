;@Ahk2Exe-SetCompanyName QuickSay
;@Ahk2Exe-SetDescription QuickSay Beta v1.7 Setup
;@Ahk2Exe-SetFileVersion 1.7.0.0
;@Ahk2Exe-SetProductName QuickSay Beta v1.7
;@Ahk2Exe-SetProductVersion 1.7.0.0
;@Ahk2Exe-SetCopyright Copyright (c) 2024-2026 QuickSay
;@Ahk2Exe-SetOrigFilename QuickSay-Setup.exe
;@Ahk2Exe-SetMainIcon gui\assets\icon.ico

#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; --- SET APP IDENTITY FOR WINDOWS TASKBAR ---
; Ensures this process groups with the main launcher (same AppUserModelID)
DllCall("Shell32\SetCurrentProcessExplicitAppUserModelID", "WStr", "QuickSay.VoiceToText.1.7")

; ==============================================================================
; QuickSay Beta v1.7 Onboarding Wizard (WebView2)
; First-run setup — walks user through getting a Groq API key
; ==============================================================================

#Include %A_ScriptDir%\lib\WebView2.ahk
#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\lib\dpapi.ahk
#Include %A_ScriptDir%\lib\http.ahk

; Check if launched from QuickSay tray (parent is waiting via RunWait)
global LaunchedFromTray := false
for arg in A_Args {
    if (arg = "--launched-from-tray") {
        LaunchedFromTray := true
        break
    }
}

class OnboardingUI {
    static gui := ""
    static wv := ""
    static wvc := ""
    static configFile := A_ScriptDir "\config.json"
    static cachedConfig := ""
    static micActive := false
    static testRecordFile := A_Temp "\quicksay_mic_test.wav"
    static testTranscriptionFile := A_Temp "\quicksay_transcription_test.wav"
    static transcriptionRecording := false
    static _iconBigHandle := 0         ; HICON for taskbar/Alt+Tab
    static _iconSmallHandle := 0       ; HICON for title bar
    static _boundOnGetIcon := ""       ; WM_GETICON handler reference

    static Show() {
        ; Prevent duplicates
        if (this.gui != "") {
            try this.gui.Show()
            return
        }

        htmlFile := A_ScriptDir "\gui\onboarding.html"
        if !FileExist(htmlFile) {
            MsgBox("Onboarding file not found: " htmlFile, "QuickSay Setup", 16)
            ExitApp()
        }

        ; Create window
        this.gui := Gui("+Resize -MaximizeBox", "QuickSay Setup")
        this.gui.BackColor := "0F0F12"
        this.gui.OnEvent("Close", (*) => this.OnClose())
        this.gui.OnEvent("Size", ObjBindMethod(this, "OnResize"))

        ; Load icon at the system's preferred sizes (DPI-aware)
        iconPath := A_ScriptDir "\gui\assets\icon.ico"
        if FileExist(iconPath) {
            cxBig := DllCall("GetSystemMetrics", "Int", 11)
            cyBig := DllCall("GetSystemMetrics", "Int", 12)
            cxSmall := DllCall("GetSystemMetrics", "Int", 49)
            cySmall := DllCall("GetSystemMetrics", "Int", 50)
            this._iconBigHandle := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", cxBig, "Int", cyBig, "UInt", 0x10, "Ptr")
            this._iconSmallHandle := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", cxSmall, "Int", cySmall, "UInt", 0x10, "Ptr")
        }
        ; Intercept WM_GETICON so the taskbar uses our icon instead of AHK's default
        if (this._iconBigHandle) {
            this._boundOnGetIcon := ObjBindMethod(this, "OnGetIcon")
            OnMessage(0x007F, this._boundOnGetIcon)
            ; Set WM_SETICON for title bar and Alt+Tab
            hSm := this._iconSmallHandle ? this._iconSmallHandle : this._iconBigHandle
            DllCall("SendMessage", "Ptr", this.gui.Hwnd, "UInt", 0x0080, "Ptr", 1, "Ptr", this._iconBigHandle)
            DllCall("SendMessage", "Ptr", this.gui.Hwnd, "UInt", 0x0080, "Ptr", 0, "Ptr", hSm)
        }

        this.gui.Show("w620 h720")

        ; Center on screen
        MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
        winX := (mRight - mLeft - 620) / 2 + mLeft
        winY := (mBottom - mTop - 720) / 2 + mTop
        this.gui.Move(winX, winY)

        ; Initialize WebView2
        try {
            wvc := WebView2.create(this.gui.Hwnd)
            this.wvc := wvc
            this.wv := wvc.CoreWebView2
        } catch as err {
            MsgBox("QuickSay Setup requires Microsoft Edge WebView2, which could not be loaded.`n`nPlease download it from:`nhttps://developer.microsoft.com/en-us/microsoft-edge/webview2/`n`nError: " . err.Message, "QuickSay Setup Error", "Icon!")
            this.gui.Destroy()
            return
        }

        ; Handle messages from JS
        this.wv.add_WebMessageReceived(this.OnWebMessage.Bind(this))

        ; Add CSP to restrict content to local files only
        q := Chr(34)
        this.wv.AddScriptToExecuteOnDocumentCreated("var m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';m.content=" . q . "default-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" . q . ";document.head.appendChild(m);")

        ; Navigate
        this.wv.Navigate("file:///" StrReplace(htmlFile, "\", "/"))

        ; Size WebView2 to fill window
        wvc.Fill()

        ; Re-apply WM_SETICON after WebView2 init — WebView2.create()
        ; pumps messages that can reset the per-window icon.
        if (this._iconBigHandle) {
            guiHwnd := this.gui.Hwnd
            hSm := this._iconSmallHandle ? this._iconSmallHandle : this._iconBigHandle
            SendMessage(0x0080, 1, this._iconBigHandle, , "ahk_id " guiHwnd)
            SendMessage(0x0080, 0, hSm, , "ahk_id " guiHwnd)
            ; Delayed re-apply to catch async navigation resets
            SetTimer(() => SendMessage(0x0080, 1, this._iconBigHandle, , "ahk_id " guiHwnd), -500)
        }

        ; Enforce minimum window size (600x500)
        OnMessage(0x0024, ObjBindMethod(this, "OnGetMinMaxInfo"))

        ; Listen for display changes (monitor connect/disconnect)
        OnMessage(0x7E, ObjBindMethod(this, "OnDisplayChange"))
    }

    ; Handle window resize (including DPI-triggered resizes)
    static OnResize(thisGui, MinMax, Width, Height) {
        if (MinMax = -1)  ; Minimized
            return
        if (this.wvc)
            this.wvc.Fill()
    }

    ; Handle display changes (monitor connect/disconnect)
    static OnDisplayChange(wParam, lParam, msg, hwnd) {
        if (this.wvc)
            this.wvc.Fill()
    }

    ; Enforce minimum window dimensions (WM_GETMINMAXINFO)
    static OnGetMinMaxInfo(wParam, lParam, msg, hwnd) {
        ; MINMAXINFO structure: ptMinTrackSize at offset 24
        NumPut("Int", 600, "Int", 500, lParam, 24)
    }

    ; Handle WM_GETICON — returns our custom icon for the onboarding window
    ; so the taskbar shows the QuickSay icon instead of AutoHotkey's default.
    static OnGetIcon(wParam, lParam, msg, hwnd) {
        if (this.gui && hwnd = this.gui.Hwnd && this._iconBigHandle) {
            if (wParam = 1)  ; ICON_BIG
                return this._iconBigHandle
            return this._iconSmallHandle ? this._iconSmallHandle : this._iconBigHandle
        }
    }

    static OnClose() {
        ; Only mark onboarding complete if user has configured an API key
        ; Otherwise, the wizard will reappear on next launch
        hasKey := false
        try {
            cfg := this.LoadConfig()
            if (cfg.Has("groqApiKey") && cfg["groqApiKey"] != "")
                hasKey := true
        }
        if (hasKey)
            this.MarkOnboardingDone()

        ; Clean up WM_GETICON handler and icon handles
        if (this._boundOnGetIcon) {
            OnMessage(0x007F, this._boundOnGetIcon, 0)
            this._boundOnGetIcon := ""
        }
        if (this._iconBigHandle) {
            DllCall("DestroyIcon", "Ptr", this._iconBigHandle)
            this._iconBigHandle := 0
        }
        if (this._iconSmallHandle) {
            DllCall("DestroyIcon", "Ptr", this._iconSmallHandle)
            this._iconSmallHandle := 0
        }

        ; Release WebView2 COM references BEFORE destroying GUI
        ; This ensures msedgewebview2.exe processes terminate cleanly
        this.wv := ""
        this.wvc := ""
        this.gui.Destroy()
        this.gui := ""
        ExitApp(0)
    }

    static OnWebMessage(wv, args) {
        try {
            jsonStr := args.WebMessageAsJson
            msg := ""

            ; Try parsing - handle both direct objects and double-encoded strings
            try msg := JSON.Parse(jsonStr)
            if (Type(msg) = "String") {
                try msg := JSON.Parse(msg)
            }

            if (Type(msg) != "Map")
                return

            action := msg.Has("action") ? msg["action"] : ""
            data := msg.Has("data") ? msg["data"] : ""

            if (action == "testAPI") {
                this.HandleTestAPI(data)
            } else if (action == "saveKey") {
                this.HandleSaveKey(data)
            } else if (action == "finish") {
                this.HandleFinish()
            } else if (action == "startMicLevel") {
                this.HandleStartMicLevel()
            } else if (action == "getMicLevel") {
                this.HandleGetMicLevel()
            } else if (action == "stopMicLevel") {
                this.HandleStopMicLevel()
            } else if (action == "getMicDevice") {
                this.HandleGetMicDevice()
            } else if (action == "testRecording5s") {
                this.HandleTestRecording5s()
            } else if (action == "playTestRecording") {
                this.HandlePlayTestRecording()
            } else if (action == "getMicVolume") {
                this.HandleGetMicVolume()
            } else if (action == "increaseMicVolume") {
                this.HandleIncreaseMicVolume()
            } else if (action == "startTestTranscription") {
                this.HandleStartTestTranscription()
            } else if (action == "stopTestTranscription") {
                this.HandleStopTestTranscription()
            } else if (action == "micTestSkipped") {
                this.HandleMicTestSkipped()
            } else if (action == "finishAndStartTour") {
                this.HandleFinishAndStartTour()
            } else if (action == "openURL") {
                try Run(data)
            }
        } catch as err {
            try FileAppend("[" A_Now "] OnWebMessage ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleTestAPI(apiKey) {
        if (apiKey == "" || !apiKey) {
            this.SendToJS("apiTestResult", Map("success", false, "status", 0))
            return
        }
        httpStatus := 0
        success := false
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", "https://api.groq.com/openai/v1/models", false)
            http.SetRequestHeader("Authorization", "Bearer " apiKey)
            http.SetRequestHeader("Content-Type", "application/json")
            http.Send()
            httpStatus := http.Status
            success := (httpStatus == 200)
        } catch {
            success := false
            httpStatus := 0
        }

        ; If test succeeded, save the key directly (no JS roundtrip)
        if (success) {
            try this.HandleSaveKey(apiKey)
        }

        this.SendToJS("apiTestResult", Map("success", success, "status", httpStatus))
    }

    static HandleSaveKey(apiKey) {
        if (apiKey == "")
            return

        try {
            ; Load existing config or create new one
            cfg := Map()
            if FileExist(this.configFile) {
                try {
                    raw := FileRead(this.configFile, "UTF-8")
                    cfg := JSON.Parse(raw)
                }
            }

            ; Ensure we have a valid Map
            if (Type(cfg) != "Map")
                cfg := Map()

            ; Set defaults for first-run config
            if !cfg.Has("sttModel")
                cfg["sttModel"] := "whisper-large-v3-turbo"
            if !cfg.Has("llmModel")
                cfg["llmModel"] := "openai/gpt-oss-20b"
            if !cfg.Has("language")
                cfg["language"] := "en"
            if !cfg.Has("hotkey")
                cfg["hotkey"] := "^LWin"
            if !cfg.Has("hotkeyMode")
                cfg["hotkeyMode"] := "hold"
            if !cfg.Has("playSounds")
                cfg["playSounds"] := 1
            if !cfg.Has("showOverlay")
                cfg["showOverlay"] := 1
            if !cfg.Has("enableLLMCleanup")
                cfg["enableLLMCleanup"] := 1
            if !cfg.Has("autoRemoveFillers")
                cfg["autoRemoveFillers"] := 1
            if !cfg.Has("smartPunctuation")
                cfg["smartPunctuation"] := 0
            if !cfg.Has("debugLogging")
                cfg["debugLogging"] := 0
            if !cfg.Has("recordingQuality")
                cfg["recordingQuality"] := "medium"
            if !cfg.Has("audioDevice")
                cfg["audioDevice"] := "Default"
            if !cfg.Has("launchAtStartup")
                cfg["launchAtStartup"] := 0
            if !cfg.Has("saveAudioRecordings")
                cfg["saveAudioRecordings"] := 0
            if !cfg.Has("stickyMode")
                cfg["stickyMode"] := 0
            if !cfg.Has("historyRetention")
                cfg["historyRetention"] := 100
            if !cfg.Has("keepLastRecordings")
                cfg["keepLastRecordings"] := 10

            ; Encrypt API key with DPAPI before saving
            if (SubStr(apiKey, 1, 4) == "gsk_") {
                try {
                    encrypted := DPAPIEncrypt(apiKey)
                    if (encrypted != "")
                        cfg["groqApiKey"] := encrypted
                    else {
                        cfg["groqApiKey"] := apiKey
                        TrayTip("Your API key could not be encrypted and was saved in plain text. This is less secure but will still work normally.", "QuickSay - Security Warning", 0x2)
                    }
                } catch {
                    cfg["groqApiKey"] := apiKey
                    TrayTip("Your API key could not be encrypted and was saved in plain text. This is less secure but will still work normally.", "QuickSay - Security Warning", 0x2)
                }
            } else {
                cfg["groqApiKey"] := apiKey
            }

            ; Remove legacy field
            if cfg.Has("api_key")
                cfg.Delete("api_key")

            ; Atomic write: write to .tmp then rename (prevents data loss on crash)
            jsonStr := JSON.Stringify(cfg, "  ")
            tmpPath := this.configFile . ".tmp"
            if FileExist(tmpPath)
                FileDelete(tmpPath)
            FileAppend(jsonStr, tmpPath, "UTF-8")
            FileMove(tmpPath, this.configFile, 1)
            this.InvalidateConfigCache()
        } catch as err {
            try FileAppend("[" A_Now "] HandleSaveKey ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleFinish() {
        this.FinishAndExit(false)
    }

    static HandleFinishAndStartTour() {
        this.FinishAndExit(true)
    }

    static FinishAndExit(startTour := false) {
        global LaunchedFromTray
        ; Mark onboarding complete
        this.MarkOnboardingDone()

        ; Set guided tour flags in config
        if (startTour) {
            ; Set both showGuidedTour and startTourOnOpen in a single config write
            try {
                cfg := this.LoadConfig()
                cfg["showGuidedTour"] := true
                cfg["startTourOnOpen"] := true
                jsonStr := JSON.Stringify(cfg, "  ")
                tmpPath := this.configFile . ".tmp"
                if FileExist(tmpPath)
                    FileDelete(tmpPath)
                FileAppend(jsonStr, tmpPath, "UTF-8")
                FileMove(tmpPath, this.configFile, 1)
                this.InvalidateConfigCache()
            }
        } else {
            this.SetGuidedTourFlag()
        }

        ; Only launch QuickSay if we were NOT launched from tray (i.e. installer launched us directly)
        ; When launched from tray, the parent QuickSay.exe is waiting via RunWait and will resume
        if !LaunchedFromTray {
            quicksayExe := A_ScriptDir "\QuickSay.exe"
            if FileExist(quicksayExe) {
                try Run(quicksayExe)
            }
        }

        ; Release WebView2 COM references BEFORE destroying GUI
        ; This ensures msedgewebview2.exe processes terminate cleanly
        this.wv := ""
        this.wvc := ""
        this.gui.Destroy()
        this.gui := ""

        ; Signal to launcher that onboarding is done (exit with code 0)
        ExitApp(0)
    }

    static MarkOnboardingDone() {
        ; Write a simple marker file so we don't show onboarding again
        markerFile := A_ScriptDir "\data\onboarding_done"
        try {
            if !DirExist(A_ScriptDir "\data")
                DirCreate(A_ScriptDir "\data")
            f := FileOpen(markerFile, "w")
            f.Write("1")
            f.Close()
        }
    }

    static SetGuidedTourFlag() {
        ; Set showGuidedTour flag in config so settings opens with the tour
        try {
            cfg := this.LoadConfig()
            cfg["showGuidedTour"] := true
            jsonStr := JSON.Stringify(cfg, "  ")
            tmpPath := this.configFile . ".tmp"
            if FileExist(tmpPath)
                FileDelete(tmpPath)
            FileAppend(jsonStr, tmpPath, "UTF-8")
            FileMove(tmpPath, this.configFile, 1)
            this.InvalidateConfigCache()
        }
    }

    static LoadConfig() {
        if (this.cachedConfig != "")
            return this.cachedConfig
        try {
            if FileExist(this.configFile) {
                raw := FileRead(this.configFile, "UTF-8")
                cfg := JSON.Parse(raw)
                if (Type(cfg) = "Map") {
                    this.cachedConfig := cfg
                    return cfg
                }
            }
        }
        return Map()
    }

    static InvalidateConfigCache() {
        this.cachedConfig := ""
    }

    static HandleStartMicLevel() {
        this.micActive := true
    }

    static HandleGetMicLevel() {
        if !this.micActive
            return
        try {
            ; Use WASAPI IAudioMeterInformation for peak level
            ; Create device enumerator
            enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            ; Get default capture device (eCapture=1, eConsole=0)
            ComCall(4, enumerator, "int", 1, "int", 0, "ptr*", &device := 0)
            if !device {
                this.SendToJS("micLevel", 0)
                return
            }
            ; Get IAudioMeterInformation {C02216F6-8C67-4B5B-9D00-D008E73E0064}
            GUID := Buffer(16)
            DllCall("ole32\CLSIDFromString", "Str", "{C02216F6-8C67-4B5B-9D00-D008E73E0064}", "Ptr", GUID)
            ComCall(3, device, "ptr", GUID, "uint", 7, "ptr", 0, "ptr*", &meter := 0)
            if meter {
                ; GetPeakValue
                peak := 0.0
                ComCall(3, meter, "float*", &peak)
                ObjRelease(meter)
                ; Amplify peak by 3x for better visual feedback (WASAPI peaks are often low)
                amplified := peak * 3.0
                if (amplified > 1.0)
                    amplified := 1.0
                this.SendToJS("micLevel", Round(amplified, 3))
            } else {
                this.SendToJS("micLevel", 0)
            }
            ObjRelease(device)
        } catch {
            this.SendToJS("micLevel", 0)
        }
    }

    static HandleStopMicLevel() {
        this.micActive := false
    }

    static HandleGetMicDevice() {
        try {
            cfg := this.LoadConfig()
            device := cfg.Has("audioDevice") ? cfg["audioDevice"] : "Default"
            this.SendToJS("micDeviceName", device)
        } catch {
            this.SendToJS("micDeviceName", "Default")
        }
    }

    static HandleTestRecording5s() {
        try {
            recFile := this.testRecordFile
            if FileExist(recFile)
                try FileDelete(recFile)

            ; Use MCI for simple recording (non-blocking — SetTimer instead of Sleep)
            DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias mictest", "Ptr", 0, "UInt", 0, "Ptr", 0)
            DllCall("winmm\mciSendString", "Str", "record mictest", "Ptr", 0, "UInt", 0, "Ptr", 0)

            ; Send recording progress to JS (countdown: 5, 4, 3, 2, 1)
            this.SendToJS("testRecordingProgress", 5)
            SetTimer(ObjBindMethod(this, "TestRecordingTick4"), -1000)
        } catch {
            this.SendToJS("testRecordingDone", false)
        }
    }

    static TestRecordingTick4() {
        this.SendToJS("testRecordingProgress", 4)
        SetTimer(ObjBindMethod(this, "TestRecordingTick3"), -1000)
    }

    static TestRecordingTick3() {
        this.SendToJS("testRecordingProgress", 3)
        SetTimer(ObjBindMethod(this, "TestRecordingTick2"), -1000)
    }

    static TestRecordingTick2() {
        this.SendToJS("testRecordingProgress", 2)
        SetTimer(ObjBindMethod(this, "TestRecordingTick1"), -1000)
    }

    static TestRecordingTick1() {
        this.SendToJS("testRecordingProgress", 1)
        SetTimer(ObjBindMethod(this, "FinishTestRecording"), -1000)
    }

    static FinishTestRecording() {
        try {
            recFile := this.testRecordFile
            DllCall("winmm\mciSendString", "Str", 'save mictest "' . recFile . '" wait', "Ptr", 0, "UInt", 0, "Ptr", 0)
            DllCall("winmm\mciSendString", "Str", "close mictest", "Ptr", 0, "UInt", 0, "Ptr", 0)

            success := FileExist(recFile) && FileGetSize(recFile) > 1000
            this.SendToJS("testRecordingDone", success)
        } catch {
            this.SendToJS("testRecordingDone", false)
        }
    }

    static HandlePlayTestRecording() {
        try {
            recFile := this.testRecordFile
            if FileExist(recFile)
                SoundPlay(recFile)
        }
    }

    static HandleStartTestTranscription() {
        try {
            this.transcriptionRecording := true
            recFile := this.testTranscriptionFile
            if FileExist(recFile)
                try FileDelete(recFile)

            ; Use MCI to start recording (same pattern as mic test)
            DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias transtest", "Ptr", 0, "UInt", 0, "Ptr", 0)
            DllCall("winmm\mciSendString", "Str", "record transtest", "Ptr", 0, "UInt", 0, "Ptr", 0)
        } catch as err {
            this.transcriptionRecording := false
            this.SendTranscriptionError("Failed to start recording: " err.Message)
            try FileAppend("[" A_Now "] StartTestTranscription ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleStopTestTranscription() {
        if !this.transcriptionRecording {
            this.SendToJS("testTranscriptionResult", "")
            return
        }
        this.transcriptionRecording := false

        try {
            recFile := this.testTranscriptionFile
            ; Stop and save the MCI recording
            DllCall("winmm\mciSendString", "Str", 'save transtest "' . recFile . '" wait', "Ptr", 0, "UInt", 0, "Ptr", 0)
            DllCall("winmm\mciSendString", "Str", "close transtest", "Ptr", 0, "UInt", 0, "Ptr", 0)

            ; Verify recording file exists and has content
            if (!FileExist(recFile) || FileGetSize(recFile) < 1000) {
                this.SendToJS("testTranscriptionResult", "")
                return
            }

            ; Get the API key from cached config
            apiKey := ""
            cfg := this.LoadConfig()
            if (cfg.Has("groqApiKey")) {
                apiKey := cfg["groqApiKey"]
                ; Decrypt if needed (DPAPI-encrypted keys don't start with gsk_)
                if (apiKey != "" && SubStr(apiKey, 1, 4) != "gsk_") {
                    try {
                        decrypted := DPAPIDecrypt(apiKey)
                        if (decrypted != "" && SubStr(decrypted, 1, 4) == "gsk_")
                            apiKey := decrypted
                    }
                }
            }

            if (apiKey = "") {
                this.SendTranscriptionError("No API key configured")
                return
            }

            ; Send audio to Groq Whisper API for transcription
            whisperURL := "https://api.groq.com/openai/v1/audio/transcriptions"

            ; Read STT model and language from cached config
            sttModel := cfg.Has("sttModel") ? cfg["sttModel"] : "whisper-large-v3-turbo"
            lang := "en"
            if cfg.Has("language") {
                langRaw := cfg["language"]
                langCodes := Map("English", "en", "Spanish", "es", "French", "fr", "German", "de", "Japanese", "ja", "Chinese", "zh", "Korean", "ko")
                lang := langCodes.Has(langRaw) ? langCodes[langRaw] : langRaw
            }

            ; Build multipart form data and POST to Groq
            formFields := Map("model", sttModel, "language", lang)
            apiResult := HttpPostFile(whisperURL, apiKey, recFile, formFields)

            if (apiResult["error"] != "") {
                this.SendTranscriptionError(apiResult["error"])
                return
            }

            if (apiResult["status"] != 200) {
                errorDetail := "API error (HTTP " apiResult["status"] ")"
                if RegExMatch(apiResult["body"], '"message":\s*"([^"]+)"', &errMatch)
                    errorDetail := errMatch[1]
                this.SendTranscriptionError(errorDetail)
                return
            }

            ; Parse transcribed text from response
            responseText := apiResult["body"]
            if RegExMatch(responseText, 's)"text":"((?:[^"\\]|\\.)*)"', &match) {
                transcribedText := match[1]
                transcribedText := StrReplace(transcribedText, "\n", "`n")
                transcribedText := StrReplace(transcribedText, '\"', '"')
                this.SendToJS("testTranscriptionResult", transcribedText)
            } else {
                this.SendToJS("testTranscriptionResult", "")
            }

            ; Clean up temp file
            try FileDelete(recFile)
        } catch as err {
            try {
                DllCall("winmm\mciSendString", "Str", "close transtest", "Ptr", 0, "UInt", 0, "Ptr", 0)
            }
            this.SendTranscriptionError(err.Message)
            try FileAppend("[" A_Now "] StopTestTranscription ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    ; Send transcription error back to JS with proper JSON format:
    ; {"action":"testTranscriptionResult","data":"","error":"Error message"}
    static SendTranscriptionError(errorMsg) {
        if (this.wv == "")
            return
        safeError := StrReplace(StrReplace(StrReplace(StrReplace(errorMsg, '\', '\\'), '"', '\"'), '`n', '\n'), '`r', '\r')
        jsonMsg := '{"action":"testTranscriptionResult","data":"","error":"' safeError '"}'
        try this.wv.PostWebMessageAsJson(jsonMsg)
    }

    static HandleMicTestSkipped() {
        ; Save micTestSkipped flag to config so main app can show a reminder later
        try {
            cfg := this.LoadConfig()
            cfg["micTestSkipped"] := true

            jsonStr := JSON.Stringify(cfg, "  ")
            tmpPath := this.configFile . ".tmp"
            if FileExist(tmpPath)
                FileDelete(tmpPath)
            FileAppend(jsonStr, tmpPath, "UTF-8")
            FileMove(tmpPath, this.configFile, 1)
            this.InvalidateConfigCache()
        } catch as err {
            try FileAppend("[" A_Now "] HandleMicTestSkipped ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleGetMicVolume() {
        try {
            ; Create device enumerator
            enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            ; Get default capture device (eCapture=1, eConsole=0)
            ComCall(4, enumerator, "int", 1, "int", 0, "ptr*", &device := 0)
            if !device {
                this.SendToJS("micVolume", 0)
                return
            }
            ; Get IAudioEndpointVolume {5CDF2C82-841E-4546-9722-0CF74078229A}
            GUID := Buffer(16)
            DllCall("ole32\CLSIDFromString", "Str", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", GUID)
            ComCall(3, device, "ptr", GUID, "uint", 7, "ptr", 0, "ptr*", &epVol := 0)
            if epVol {
                ; GetMasterVolumeLevelScalar (vtable index 9 in IAudioEndpointVolume)
                ComCall(9, epVol, "float*", &vol := 0.0)
                ObjRelease(epVol)
                this.SendToJS("micVolume", Round(vol, 2))
            } else {
                this.SendToJS("micVolume", 0)
            }
            ObjRelease(device)
        } catch {
            this.SendToJS("micVolume", 0)
        }
    }

    static HandleIncreaseMicVolume() {
        ; Read current volume, increase by 15%, cap at 100%
        try {
            enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            ComCall(4, enumerator, "int", 1, "int", 0, "ptr*", &device := 0)
            if !device
                return
            GUID := Buffer(16)
            DllCall("ole32\CLSIDFromString", "Str", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", GUID)
            ComCall(3, device, "ptr", GUID, "uint", 7, "ptr", 0, "ptr*", &epVol := 0)
            if epVol {
                ; GetMasterVolumeLevelScalar (vtable index 9)
                ComCall(9, epVol, "float*", &currentVol := 0.0)
                ; Increase by 15%, cap at 100%
                newVol := currentVol + 0.15
                if (newVol > 1.0)
                    newVol := 1.0
                ; SetMasterVolumeLevelScalar (vtable index 7)
                emptyGUID := Buffer(16, 0)
                ComCall(7, epVol, "float", newVol, "ptr", emptyGUID)
                ObjRelease(epVol)
                this.SendToJS("micVolumeIncreased", Map("from", Round(currentVol, 2), "to", Round(newVol, 2)))
            }
            ObjRelease(device)
        } catch as err {
            try FileAppend("[" A_Now "] IncreaseMicVolume ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static SendToJS(action, value) {
        if (this.wv == "")
            return
        ; Use PostWebMessageAsJson instead of ExecuteScript to avoid deadlock.
        ; ExecuteScript → ExecuteScriptAsync().await() blocks inside COM callbacks,
        ; causing the AHK thread to hang when called from OnWebMessage.
        ; PostWebMessageAsJson sends asynchronously — no blocking.
        if (Type(value) == "Map") {
            ; Serialize Map as JSON object
            jsonVal := "{"
            first := true
            for k, v in value {
                if !first
                    jsonVal .= ","
                first := false
                jsonVal .= '"' k '":'
                if (Type(v) == "String")
                    jsonVal .= '"' StrReplace(StrReplace(v, '\', '\\'), '"', '\"') '"'
                else
                    jsonVal .= String(v)
            }
            jsonVal .= "}"
        ; Check number FIRST (before boolean, since 0 == false in AHK)
        } else if (value is Number)
            jsonVal := String(value)
        else if (value == true)
            jsonVal := "true"
        else if (value == false)
            jsonVal := "false"
        else
            jsonVal := '"' . StrReplace(StrReplace(String(value), "\", "\\"), '"', '\"') . '"'

        jsonMsg := '{"action":"' action '","data":' jsonVal '}'
        try this.wv.PostWebMessageAsJson(jsonMsg)
    }
}

; --- LAUNCH ---
try {
    OnboardingUI.Show()
} catch as err {
    MsgBox("Onboarding Error: " err.Message, "QuickSay Setup", 16)
    ExitApp(1)
}
