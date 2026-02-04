#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon



; ==============================================================================
; QuickSay Settings UI v2.3 (WebView2)
; ==============================================================================

#Include %A_ScriptDir%\lib\WebView2.ahk
#Include %A_ScriptDir%\lib\JSON.ahk

; ═══════════════════════════════════════════════════════════════════════════════
;  DPAPI ENCRYPTION (Windows Data Protection API)
;  Shared implementation — same as QuickSay-Next.ahk
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

DPAPIDecrypt(base64Text) {
    if (base64Text == "")
        return ""
    DllCall("crypt32\CryptStringToBinaryW", "str", base64Text, "uint", 0, "uint", 1, "ptr", 0, "uint*", &binLen := 0, "ptr", 0, "ptr", 0)
    if (binLen == 0)
        return ""
    binBuf := Buffer(binLen)
    DllCall("crypt32\CryptStringToBinaryW", "str", base64Text, "uint", 0, "uint", 1, "ptr", binBuf, "uint*", &binLen, "ptr", 0, "ptr", 0)
    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", binLen, inputBlob, 0)
    NumPut("ptr", binBuf.Ptr, inputBlob, A_PtrSize)
    outputBlob := Buffer(A_PtrSize * 2, 0)
    result := DllCall("crypt32\CryptUnprotectData", "ptr", inputBlob, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "int", 1, "ptr", outputBlob)
    if !result
        return ""
    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")
    decrypted := StrGet(outPtr, outSize, "UTF-8")
    DllCall("LocalFree", "ptr", outPtr)
    return decrypted
}

class SettingsUI {
    static gui := ""
    static wv := ""
    static wvc := "" ; WebView2 Controller
    static configFile := A_ScriptDir "\config.json"
    static dictFile := A_ScriptDir "\dictionary.json"
    static historyFile := A_ScriptDir "\data\history.json"

    static statsFile := A_ScriptDir "\data\statistics.json"
    static logDir := A_ScriptDir "\data\logs"
    
    ; Show the Settings Window
    static Show() {
        ; Ensure log directory exists
        if !DirExist(this.logDir)
            DirCreate(this.logDir)
            
        this.Log("Show() called - Opening Settings Window")
        
        ; Check for existing instance
        if (this.gui && WinExist("QuickSay Settings ahk_class AutoHotkeyGUI")) {
            WinActivate("QuickSay Settings ahk_class AutoHotkeyGUI")
            return
        }
        
        ; Verify HTML exists
        htmlPath := A_ScriptDir "\gui\settings.html"
        if (!FileExist(htmlPath)) {
            MsgBox("Settings file not found: " htmlPath, "QuickSay Error", "Icon!")
            return
        }
        
        ; Create GUI
        this.gui := Gui("-Resize -MaximizeBox", "QuickSay Settings")
        this.gui.OnEvent("Close", (*) => this.Close())

        this.gui.Show("w800 h700") ; Show first to get handle

        ; Set window icon (title bar + taskbar) — must be after Show() for HWND
        iconPath := A_ScriptDir "\gui\assets\icon.ico"
        if FileExist(iconPath) {
            try {
                hIconSmall := LoadPicture(iconPath, "w24 h24", &imgType1)
                hIconBig := LoadPicture(iconPath, "w48 h48", &imgType2)
                SendMessage(0x0080, 0, hIconSmall, , "ahk_id " this.gui.Hwnd)  ; Title bar (24px)
                SendMessage(0x0080, 1, hIconBig, , "ahk_id " this.gui.Hwnd)    ; Taskbar (48px)
            }
        }
        
        ; Initialize WebView2
        try {
            ; Create WebView2 controller attached to the GUI window
			; Usage: WebView2.create(hWnd, [rect, userDataFolder, options])
            this.wvc := WebView2.create(this.gui.Hwnd)
            this.wv := this.wvc.CoreWebView2
            
            ; Configure settings
            ; this.wv.Settings.AreDefaultContextMenusEnabled := false
            ; this.wv.Settings.AreDevToolsEnabled := false
            
            ; Set up message handler
			; Use add_WebMessageReceived for thqby library
            this.wv.add_WebMessageReceived(this.OnWebMessage.Bind(this))
            
            ; Navigate
            this.wv.Navigate("file:///" StrReplace(htmlPath, "\", "/"))

            ; Adjust Layout
            this.gui.Move(,, 800, 700)
            this.CenterWindow(this.gui)
            
            ; Explicitly set bounds to fill client area
            this.gui.GetClientPos(,, &cw, &ch)
            rect := Buffer(16, 0)
            NumPut("int", 0, "int", 0, "int", cw, "int", ch, rect)
            this.wvc.Bounds := rect

        } catch as err {
            MsgBox("Failed to initialize WebView2.`n" err.Message, "QuickSay Error", "Icon!")
            this.Close()
        }
    }

    ; Handle Closing
    static Close(*) {
        if (this.gui)
            this.gui.Destroy()
        this.gui := ""
        this.wv := ""
        this.wvc := ""
    }

    ; Center Window Helper
    static CenterWindow(guiObj) {
        guiObj.GetPos(,, &w, &h)
        guiObj.Move((A_ScreenWidth - w) // 2, (A_ScreenHeight - h) // 2)
    }

    ; ==========================================================================
    ; MESSAGE HANDLING
    ; ==========================================================================
    static OnWebMessage(wv, args) {
        try {
            jsonStr := args.WebMessageAsJson
            msg := JSON.Parse(jsonStr)

            ; If double-encoded (postMessage(JSON.stringify(...))), parse again
            if (Type(msg) = "String") {
                try {
                    msg := JSON.Parse(msg)
                } catch as err {
                    OutputDebug("Message parse error: " err.Message)
                    return
                }
            }

            action := (Type(msg) = "Map" && msg.Has("action")) ? msg["action"] : ""
            OutputDebug("Action: " action)
            
            switch action {
                case "loadConfig":
                    this.HandleLoadConfig()
                case "saveConfig":
                    OutputDebug("=== SAVECONFIG HANDLER ===")
                    data := msg["data"]
                    shouldClose := msg.Has("shouldClose") ? msg["shouldClose"] : false
                    OutputDebug("Data type: " Type(data))
                    OutputDebug("Data has keys: " (data.Count > 0 ? "YES (" data.Count ")" : "NO"))
                    this.HandleSaveConfig(data, shouldClose)
                case "reloadEngineConfig":
                    this.HandleReloadEngineConfig()
                case "testGroqAPI":
                    this.HandleTestAPI(msg["data"]["apiKey"])
                case "getAudioDevices":
                    this.HandleGetAudioDevices()
                case "loadDictionary":
                    this.HandleLoadDictionary()
                case "saveDictionary":
                    this.HandleSaveDictionary(msg["data"])
                case "getHistoryCount":
                    this.HandleGetHistoryCount()
                case "clearHistory":
                    this.HandleClearHistory()
                case "viewLogs":
                    this.HandleViewLogs()
                case "closeAfterSave":
                    this.Close()
                case "closeSettings":
                    this.Close()
                case "openUrl":
                    try Run(msg["data"])
                case "importDictionary":
                    this.HandleImportDictionary()
                case "exportDictionary":
                    this.HandleExportDictionary()
                case "loadHistoryData":
                    this.HandleLoadHistoryData()
                case "loadStatisticsData":
                    this.HandleLoadStatisticsData()
                case "deleteHistoryFile":
                    this.HandleClearHistory()
            }
        } catch as err {
            OutputDebug("WebMessage Error: " err.Message)
        }
    }

    ; Reply to JS
    static SendToJS(functionName, dataObj) {
        if (!this.wv)
            return
        try {
            envelope := Map()
            envelope["function"] := functionName
            envelope["data"] := dataObj
            jsonStr := JSON.Stringify(envelope)
            this.wv.PostWebMessageAsJson(jsonStr)
            OutputDebug("SendToJS: " functionName)
        } catch as err {
            OutputDebug("SendToJS ERROR: " err.Message)
        }
    }

    ; ==========================================================================
    ; HANDLERS
    ; ==========================================================================
    
    static HandleLoadConfig() {
        cfg := this.LoadJSON(this.configFile)
        if !cfg.Has("hotkey")
            cfg["hotkey"] := "^LWin"

        ; Decrypt API key for display in Settings UI
        if (cfg.Has("groqApiKey")) {
            rawKey := cfg["groqApiKey"]
            if (rawKey != "" && SubStr(rawKey, 1, 4) != "gsk_") {
                ; Encrypted — decrypt for display
                try {
                    decrypted := DPAPIDecrypt(rawKey)
                    if (decrypted != "")
                        cfg["groqApiKey"] := decrypted
                }
            }
        }

        this.SendToJS("receiveConfig", cfg)
    }

    static HandleSaveConfig(newConfig, shouldClose := false) {
        try {
            ; Encrypt API key with DPAPI before saving to disk
            if (Type(newConfig) = "Map" && newConfig.Has("groqApiKey")) {
                plainKey := newConfig["groqApiKey"]
                if (plainKey != "" && SubStr(plainKey, 1, 4) == "gsk_") {
                    encrypted := DPAPIEncrypt(plainKey)
                    if (encrypted != "")
                        newConfig["groqApiKey"] := encrypted
                }
                ; Remove legacy api_key field if present
                if newConfig.Has("api_key")
                    newConfig.Delete("api_key")
            }

            if (this.SaveJSON(this.configFile, newConfig)) {
                ; Handle Launch at Startup registry key
                this.UpdateStartupRegistry(newConfig)

                ; Send reload signal to Engine
                DetectHiddenWindows(true)
                if WinExist("QuickSay-Next.ahk ahk_class AutoHotkey")
                    PostMessage(0x5555, 1, 0)
                ; Notify JS of success
                this.SendToJS("receiveConfigSaved", Map("success", true))
            } else {
                throw Error("SaveJSON returned false")
            }
        } catch as err {
            OutputDebug("Save failed: " err.Message)
            this.SendToJS("receiveConfigSaved", Map("success", false))
        }
    }

    static UpdateStartupRegistry(config) {
        regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
        regName := "QuickSay"

        ; Determine the launcher path
        launcherPath := A_ScriptDir "\QuickSay-Launcher.ahk"

        ; Check if launchAtStartup is enabled
        enabled := false
        if (Type(config) = "Map" && config.Has("launchAtStartup")) {
            val := config["launchAtStartup"]
            enabled := (val = true || val = 1 || val = "true")
        }

        try {
            if (enabled) {
                ; Write registry key pointing to the launcher
                RegWrite('"' . launcherPath . '"', "REG_SZ", regKey, regName)
                OutputDebug("Startup registry key SET: " launcherPath)
            } else {
                ; Delete registry key if it exists
                try RegDelete(regKey, regName)
                OutputDebug("Startup registry key REMOVED")
            }
        } catch as err {
            OutputDebug("Registry update failed: " err.Message)
        }
    }

    static HandleReloadEngineConfig() {
        ; Send reload message to QuickSay-Next.ahk engine
        DetectHiddenWindows(true)
        if WinExist("QuickSay-Next.ahk ahk_class AutoHotkey") {
            engineHwnd := WinExist("QuickSay-Next.ahk ahk_class AutoHotkey")
            PostMessage(0x5555, 1, 0,, "ahk_id " . engineHwnd)
            OutputDebug("=== Sent reload message (0x5555) to engine ===")
        } else {
            OutputDebug("=== WARNING: Engine not found, cannot send reload message ===")
        }
    }

    static HandleTestAPI(apiKey) {
        success := false
        if (apiKey = "" || !apiKey) {
             this.SendToJS("apiTestResult", false)
             return
        }
        ; Decrypt if encrypted (user may test before saving)
        if (SubStr(apiKey, 1, 4) != "gsk_") {
            try {
                decrypted := DPAPIDecrypt(apiKey)
                if (decrypted != "")
                    apiKey := decrypted
            }
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
        this.SendToJS("apiTestResult", success)
    }


    static HandleGetAudioDevices() {
        OutputDebug("=== Enumerating Audio Devices via .bat method ===")
        
        devices := []
        
        try {
            ; Check bundled copy first (shipped with installer), then WinGet
            ffmpegPath := A_ScriptDir "\ffmpeg.exe"
            if !FileExist(ffmpegPath)
                ffmpegPath := EnvGet("LOCALAPPDATA") "\Microsoft\WinGet\Links\ffmpeg.exe"

            batFile  := A_Temp "\quicksay_enum.bat"
            outFile  := A_Temp "\quicksay_devices.txt"

            OutputDebug("FFmpeg path: " ffmpegPath)
            OutputDebug("FFmpeg exists: " FileExist(ffmpegPath))

            ; Clean up any previous run
            if FileExist(outFile)
                FileDelete(outFile)

            ; --- WRITE THE .bat FILE ---
            ; The .bat handles ALL quoting/redirects natively. No AHK string hell.
            try {
                if FileExist(batFile)
                    FileDelete(batFile)
                f := FileOpen(batFile, "w")
                f.Write("@echo off" "`r`n")
                ; Use chcp 65001 to ensure UTF-8 output capture if possible
                f.Write("chcp 65001 > nul" "`r`n")
                f.Write('"' ffmpegPath '" -list_devices true -f dshow -i dummy > "' outFile '" 2>&1' "`r`n")
                f.Close()
            } catch as err {
                OutputDebug("Failed to write .bat file: " err.Message)
                return
            }

            OutputDebug("Bat file written: " batFile)

            ; --- RUN THE .bat ---
            try {
                RunWait(batFile, , "Hide")
            } catch as err {
                OutputDebug("Failed to run .bat file: " err.Message)
            }
            
            ; Wait a moment for file flush
            Sleep(200)

            OutputDebug("Output file exists: " FileExist(outFile))

            ; --- PARSE THE OUTPUT ---
            if FileExist(outFile) {
                try {
                    output := FileRead(outFile, "UTF-8")
                } catch {
                    output := FileRead(outFile) ; Fallback
                }
                OutputDebug("Output length: " StrLen(output))

                inAudioSection := false ; Kept for legacy outputs just in case
                foundCount := 0

                Loop Parse, output, "`n", "`r" {
                    line := Trim(A_LoopField)

                    ; Some FFmpeg builds use section headers, some don't.
                    ; We will support BOTH methods.
                    
                    ; Method A: Header-based state machine
                    if InStr(line, "DirectShow audio devices") {
                        inAudioSection := true
                        continue
                    }
                    if InStr(line, "DirectShow video devices") {
                        inAudioSection := false
                        ; Don't break here, in case audio comes after video in some weird build
                        continue 
                    }

                    ; Method B: Line-based type detection (Robust fallback)
                    isAudioLine := false
                    if InStr(line, "(audio)") && !InStr(line, "(video)") 
                        isAudioLine := true
                    
                    ; Combine methods: It's a valid line if we are in section OR it explicitly says (audio)
                    if (inAudioSection || isAudioLine) {
                        
                        ; Filter out "Alternative name" lines
                        if InStr(line, "Alternative name")
                            continue

                        ; Match quoted device name
                        if InStr(line, '"') {
                            ; Regex matches: anything in quotes ... followed optionally by (audio)
                            ; We rely on the isAudioLine check above to ensure it's audio related
                            if RegExMatch(line, '"([^"]+)"', &match) {
                                deviceName := match[1]
                                
                                ; Filter known false positives
                                if (deviceName != "" && deviceName != "@device_cm_") {
                                    devices.Push(deviceName)
                                    foundCount++
                                    OutputDebug("Found device: " deviceName)
                                }
                            }
                        }
                    }
                }

                OutputDebug("Total devices found: " foundCount)
                FileDelete(outFile)
            } else {
                OutputDebug("ERROR: Output file was not created. FFmpeg might have failed or path is wrong.")
            }

            ; Clean up bat
            if FileExist(batFile)
                FileDelete(batFile)

        } catch as err {
            OutputDebug("ERROR in HandleGetAudioDevices: " err.Message)
        }
        
        if (devices.Length = 0)
            devices.Push("No devices found")
        
        OutputDebug("Sending " devices.Length " devices to JS")
        this.SendToJS("receiveAudioDevices", devices)
    }


    static HandleLoadDictionary() {
        dict := []
        if FileExist(this.dictFile)
            dict := this.LoadJSON(this.dictFile)
        if !HasProp(dict, 'Length')
            dict := []
        this.SendToJS("receiveDictionary", dict)
    }

    static HandleSaveDictionary(data) {
        this.SaveJSON(this.dictFile, data)
    }

    static HandleGetHistoryCount() {
        count := 0
        if FileExist(this.historyFile) {
            Loop Read, this.historyFile
                count++
        }
        this.SendToJS("receiveHistoryCount", count)
    }

    static HandleClearHistory() {
        historyFile := this.historyFile
        
        if FileExist(historyFile) {
            try {
                FileDelete(historyFile)
                OutputDebug("History file deleted successfully")
                
                ; Send updated count (0) back to UI
                this.SendToJS("receiveHistoryCount", 0)
                
                ; Show success message via custom modal
                this.SendToJS("receiveHistoryClearResult", Map("success", true, "message", "History cleared successfully!"))
            } catch as err {
                OutputDebug("Failed to delete history: " err.Message)
                this.SendToJS("receiveHistoryClearResult", Map("success", false, "message", "Failed to clear history: " err.Message))
            }
        } else {
            OutputDebug("No history file to delete")
            this.SendToJS("receiveHistoryCount", 0)
            this.SendToJS("receiveHistoryClearResult", Map("success", true, "message", "History is already empty."))
        }
    }
    
    static HandleViewLogs() {
        logDir := this.logDir
        
        ; Create directory if it doesn't exist
        if !DirExist(logDir) {
            try {
                DirCreate(logDir)
                ; Create a README file to explain the folder
                readmePath := logDir "\README.txt"
                readmeText := "QuickSay Debug Logs`n`n"
                readmeText .= "This folder contains debug logs when 'Enable debug logging' is turned on.`n"
                readmeText .= "Logs are created automatically when the feature is enabled.`n"
                FileAppend(readmeText, readmePath, "UTF-8")
            } catch as err {
                MsgBox("Could not create log directory: " err.Message, "QuickSay", "Icon!")
                return
            }
        }
        
        ; Open the directory
        if DirExist(logDir) {
            Run('explorer.exe "' logDir '"')
        } else {
            MsgBox("Could not access log directory.", "QuickSay", "Icon!")
        }
    }
    
    static HandleImportDictionary() {
        selected := FileSelect(3, , "Import Dictionary", "JSON Files (*.json)")
        if (selected) {
            data := this.LoadJSON(selected)
            if HasProp(data, 'Length') {
                this.SaveJSON(this.dictFile, data)
                this.SendToJS("receiveDictionary", data)
            } else {
                MsgBox("Invalid dictionary format.")
            }
        }
    }

    static HandleExportDictionary() {
        selected := FileSelect("S16", "dictionary_export.json", "Export Dictionary", "JSON Files (*.json)")
        if (selected) {
            if !RegExMatch(selected, "\.json$")
                selected .= ".json"
            if FileExist(this.dictFile)
                FileCopy(this.dictFile, selected, 1)
        }
    }

    ; ==========================================================================
    ; HISTORY & STATS DATA LOADING
    ; ==========================================================================
    static HandleLoadHistoryData() {
        this.Log("═══ HandleLoadHistoryData CALLED ═══")
        

        this.Log("History file path: " this.historyFile)
        
        data := []
        if FileExist(this.historyFile) {
            this.Log("Loading History JSON...")
            data := this.LoadJSON(this.historyFile)
            if !HasProp(data, 'Length') {
                this.Log("Data is not array, converting to empty array")
                data := []
            } else {
                this.Log("Loaded " data.Length " history items")
            }
        } else {
            this.Log("History file not found.")
        }
        
        this.Log("Sending to JS: receiveHistoryData")
        ; WebView2 PostWebMessageAsJson cannot send arrays directly - wrap in Map
        wrapper := Map("history", data)
        this.SendToJS("receiveHistoryData", wrapper)
    }


    static HandleLoadStatisticsData() {
        this.Log("═══ HandleLoadStatisticsData CALLED ═══")
        this.Log("Stats file path: " this.statsFile)
        
        data := Map()
        if FileExist(this.statsFile) {
            this.Log("Loading Stats JSON...")
            data := this.LoadJSON(this.statsFile)
        } else {
            this.Log("Stats file not found.")
        }
        
        this.Log("Sending to JS: receiveStatisticsData")
        this.SendToJS("receiveStatisticsData", data)
    }

    static Log(msg) {
        try {
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            FileAppend("[" timestamp "] " msg "`n", this.logDir "\debug.txt", "UTF-8")
        }
    }

    ; ==========================================================================
    ; DEFAULTS & HELPERS
    ; ==========================================================================
    static CreateDefaultConfig() {
        defaultJson := '{"apiKey":"","hotkey":"^LWin","launchAtStartup":true,"showOverlay":true,"playSounds":true,"audioDevice":"Default","recordingQuality":"medium","saveAudioRecordings":true,"keepLastRecordings":50,"enableLLMCleanup":true,"autoRemoveFillers":true,"smartPunctuation":true,"historyRetention":500,"debugLogging":false}'
        try FileAppend(defaultJson, this.configFile, "UTF-8")
    }

    static CreateDefaultDictionary() {
        defaultDict := '[{"spoken":"groq","written":"Groq"},{"spoken":"kubernetes","written":"Kubernetes"},{"spoken":"antigravity","written":"Antigravity"},{"spoken":"sas","written":"SaaS"}]'
        try FileAppend(defaultDict, this.dictFile, "UTF-8")
    }

    ; ==========================================================================
    ; UTILS
    ; ==========================================================================
    static LoadJSON(path) {
        if !FileExist(path)
            return Map()
        try {
            text := FileRead(path, "UTF-8")
            if (text == "")
                return Map()
            return JSON.Parse(text)
        } catch as err {
            OutputDebug("LoadJSON error: " err.Message)
            return Map()
        }
    }

    static SaveJSON(path, obj) {
        try {
            text := JSON.Stringify(obj, "  ") ; Pretty print
            if FileExist(path)
                FileDelete(path)
            FileAppend(text, path, "UTF-8")
            return true
        } catch as err {
            MsgBox("Failed to save file: " path "`n" err.Message)
            return false
        }
    }
}




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
