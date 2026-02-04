#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; ==============================================================================
; QuickSay Onboarding Wizard v2.3 (WebView2)
; First-run setup — walks user through getting a Groq API key
; ==============================================================================

#Include %A_ScriptDir%\lib\WebView2.ahk
#Include %A_ScriptDir%\lib\JSON.ahk

; ═══════════════════════════════════════════════════════════════════════════════
;  DPAPI ENCRYPTION (Windows Data Protection API)
; ═══════════════════════════════════════════════════════════════════════════════

DPAPIEncrypt(plainText) {
    if (plainText == "")
        return ""
    utf8Len := StrPut(plainText, "UTF-8") - 1
    inputBuf := Buffer(utf8Len)
    StrPut(plainText, inputBuf, "UTF-8")
    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", utf8Len, inputBlob, 0)
    NumPut("ptr", inputBuf.Ptr, inputBlob, A_PtrSize)
    outputBlob := Buffer(A_PtrSize * 2, 0)
    result := DllCall("crypt32\CryptProtectData", "ptr", inputBlob, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "int", 1, "ptr", outputBlob)
    if !result
        return ""
    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")
    DllCall("crypt32\CryptBinaryToStringW", "ptr", outPtr, "uint", outSize, "uint", 0x40000001, "ptr", 0, "uint*", &b64Len := 0)
    b64Buf := Buffer(b64Len * 2)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", outPtr, "uint", outSize, "uint", 0x40000001, "ptr", b64Buf, "uint*", &b64Len)
    DllCall("LocalFree", "ptr", outPtr)
    return StrGet(b64Buf, "UTF-16")
}

class OnboardingUI {
    static gui := ""
    static wv := ""
    static wvc := ""
    static configFile := A_ScriptDir "\config.json"

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
        this.gui.BackColor := "F0F2F5"
        this.gui.OnEvent("Close", (*) => this.OnClose())
        this.gui.Show("w620 h720")

        ; Set window icon (title bar + taskbar)
        iconPath := A_ScriptDir "\gui\assets\icon.ico"
        if FileExist(iconPath) {
            try {
                hIconSmall := LoadPicture(iconPath, "w24 h24", &imgType1)
                hIconBig := LoadPicture(iconPath, "w48 h48", &imgType2)
                SendMessage(0x0080, 0, hIconSmall, , "ahk_id " this.gui.Hwnd)
                SendMessage(0x0080, 1, hIconBig, , "ahk_id " this.gui.Hwnd)
            }
        }

        ; Center on screen
        MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
        winX := (mRight - mLeft - 620) / 2 + mLeft
        winY := (mBottom - mTop - 720) / 2 + mTop
        this.gui.Move(winX, winY)

        ; Initialize WebView2
        wvc := WebView2.create(this.gui.Hwnd)
        this.wvc := wvc
        this.wv := wvc.CoreWebView2

        ; Handle messages from JS
        this.wv.add_WebMessageReceived(this.OnWebMessage.Bind(this))

        ; Navigate
        this.wv.Navigate("file:///" StrReplace(htmlFile, "\", "/"))

        ; Size WebView2 to fill window
        this.gui.GetClientPos(, , &cw, &ch)
        wvc.Fill()
    }

    static OnClose() {
        ; Always mark onboarding complete when window closes
        this.MarkOnboardingDone()
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
            } else if (action == "openURL") {
                try Run(data)
            }
        } catch as err {
            try FileAppend("[" A_Now "] OnWebMessage ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleTestAPI(apiKey) {
        success := false
        if (apiKey == "" || !apiKey) {
            this.SendToJS("apiTestResult", false)
            return
        }
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", "https://api.groq.com/openai/v1/models", false)
            http.SetRequestHeader("Authorization", "Bearer " apiKey)
            http.SetRequestHeader("Content-Type", "application/json")
            http.Send()
            success := (http.Status == 200)
        } catch {
            success := false
        }

        ; If test succeeded, save the key directly (no JS roundtrip)
        if (success) {
            try this.HandleSaveKey(apiKey)
        }

        this.SendToJS("apiTestResult", success)
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
                cfg["llmModel"] := "llama-3.3-70b-versatile"
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
                cfg["smartPunctuation"] := 1
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
                    else
                        cfg["groqApiKey"] := apiKey
                } catch {
                    cfg["groqApiKey"] := apiKey  ; Fallback to plain if encrypt fails
                }
            } else {
                cfg["groqApiKey"] := apiKey
            }

            ; Remove legacy field
            if cfg.Has("api_key")
                cfg.Delete("api_key")

            ; Save config using same pattern as settings_ui.ahk (FileDelete + FileAppend)
            jsonStr := JSON.Stringify(cfg, "  ")
            if FileExist(this.configFile)
                FileDelete(this.configFile)
            FileAppend(jsonStr, this.configFile, "UTF-8")
        } catch as err {
            try FileAppend("[" A_Now "] HandleSaveKey ERROR: " err.Message "`n", A_ScriptDir "\data\onboarding_debug.log")
        }
    }

    static HandleFinish() {
        ; Mark onboarding complete
        this.MarkOnboardingDone()

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
            FileAppend("1", markerFile)
        }
    }

    static SendToJS(action, value) {
        if (this.wv == "")
            return
        ; Use PostWebMessageAsJson instead of ExecuteScript to avoid deadlock.
        ; ExecuteScript → ExecuteScriptAsync().await() blocks inside COM callbacks,
        ; causing the AHK thread to hang when called from OnWebMessage.
        ; PostWebMessageAsJson sends asynchronously — no blocking.
        if (value == true || value == 1)
            jsonVal := "true"
        else if (value == false || value == 0)
            jsonVal := "false"
        else if (Type(value) == "String")
            jsonVal := '"' StrReplace(StrReplace(value, '\', '\\'), '"', '\"') '"'
        else
            jsonVal := String(value)

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
