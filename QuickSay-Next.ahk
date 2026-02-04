#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
#Include lib\web-overlay.ahk

; ═══════════════════════════════════════════════════════════════════════════════
;  QuickSay v2.2 - Voice-to-Text with Modern Web Overlay (Waveform Cat!)
;  The fastest voice dictation tool - 200ms transcription via Groq
; ═══════════════════════════════════════════════════════════════════════════════

; --- GLOBAL PATHS ---
global ScriptDir := A_ScriptDir
global ConfigFile := ScriptDir . "\config.json"
global DictionaryFile := ScriptDir . "\dictionary.json"
global HistoryFile := ScriptDir . "\data\history.json"
global StatsFile := ScriptDir . "\data\statistics.json"
global AudioDir := ScriptDir . "\data\audio"
global SoundsDir := ScriptDir . "\sounds"

; --- GLOBAL STATE ---
global isRecording := false
global Config := Map()
global Dictionary := Map()
global StartTime := 0
global CurrentHotkey := ""  ; Track currently registered hotkey
global FFmpegPID := 0       ; Track FFmpeg process for non-default mic recording

; --- LAUNCHER INTEGRATION ---
PostMessageToLauncher(statusCode) {
    DetectHiddenWindows(true)
    if WinExist("QuickSay-Launcher.ahk ahk_class AutoHotkey")
        PostMessage(0x5556, statusCode, 0)
}
OnMessage(0x5555, HandleLauncherMessage)
HandleLauncherMessage(wParam, lParam, msg, hwnd) {
    if (wParam = 1) {
        LoadConfig()
        LoadDictionary()
        RegisterHotkey()  ; Re-register in case hotkey changed
    }
}

; --- LOAD CONFIGURATION ---
LoadConfig()
LoadDictionary()

; --- REGISTER HOTKEY FROM CONFIG ---
RegisterHotkey()

; --- STARTUP (Silent) ---
PreWarm()
RecordingOverlay.Show("recording") ; Force init
RecordingOverlay.Hide()

; --- SIGNAL READY ---
PostMessageToLauncher(1)
PlaySound("start")

; ═══════════════════════════════════════════════════════════════════════════════
;  CONFIGURATION FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════

LoadConfig() {
    global Config, ConfigFile
    
    if FileExist(ConfigFile) {
        try {
            configText := FileRead(ConfigFile)
            ; Parse JSON manually (AHK v2 doesn't have built-in JSON)
            Config := ParseSimpleJson(configText)
        } catch {
            Config := GetDefaultConfig()
        }
    } else {
        Config := GetDefaultConfig()
    }
}

GetDefaultConfig() {
    cfg := Map()
    cfg["groq_api_key"] := ""
    cfg["stt_model"] := "whisper-large-v3-turbo"
    cfg["llm_model"] := "llama-3.3-70b-versatile"
    cfg["llm_cleanup"] := true
    cfg["sounds_enabled"] := true
    cfg["save_recordings"] := true
    cfg["max_recordings"] := 100
    cfg["history_enabled"] := true
    cfg["max_history"] := 500
    cfg["language"] := "en"
    cfg["dictionary_enabled"] := true
    return cfg
}

LoadDictionary() {
    global Dictionary, DictionaryFile
    
    if FileExist(DictionaryFile) {
        try {
            dictText := FileRead(DictionaryFile)
            Dictionary := ParseDictionaryJson(dictText)
        } catch {
            Dictionary := Map()
        }
    } else {
        Dictionary := Map()
    }
}

ParseSimpleJson(jsonText) {
    ; Simple JSON parser for config
    result := Map()
    
    ; Extract groqApiKey (primary field — may be DPAPI-encrypted or plaintext)
    if RegExMatch(jsonText, '"groqApiKey":\s*"([^"]*)"', &match) {
        rawKey := match[1]
        if (rawKey != "" && SubStr(rawKey, 1, 4) != "gsk_") {
            ; Looks encrypted (not plaintext gsk_ prefix) — try DPAPI decrypt
            try {
                decrypted := DPAPIDecrypt(rawKey)
                if (decrypted != "" && SubStr(decrypted, 1, 4) == "gsk_")
                    rawKey := decrypted
            }
        }
        result["groq_api_key"] := rawKey
    } else if RegExMatch(jsonText, '"api_key":\s*"([^"]*)"', &match) {
        ; Legacy fallback for old config files
        result["groq_api_key"] := match[1]
    }
    
    ; Extract stt_model
    if RegExMatch(jsonText, '"stt_model":\s*"([^"]*)"', &match)
        result["stt_model"] := match[1]
    else
        result["stt_model"] := "whisper-large-v3-turbo"
    
    ; Extract llm_model
    if RegExMatch(jsonText, '"llm_model":\s*"([^"]*)"', &match)
        result["llm_model"] := match[1]
    else
        result["llm_model"] := "llama-3.3-70b-versatile"
    
    ; Extract booleans - check for presence in JSON, default to true for most
    result["llm_cleanup"] := InStr(jsonText, '"llm_cleanup": false') ? false : true
    result["sounds_enabled"] := InStr(jsonText, '"sounds_enabled": false') ? false : true
    result["save_recordings"] := InStr(jsonText, '"save_recordings": false') ? false : true
    result["history_enabled"] := InStr(jsonText, '"enabled": false') ? false : true
    result["dictionary_enabled"] := InStr(jsonText, '"dictionary_enabled": false') ? false : true
    
    ; Extract language
    if RegExMatch(jsonText, '"language":\s*"([^"]*)"', &match)
        result["language"] := match[1]
    else
        result["language"] := "en"
    
    ; Extract audioDevice
    if RegExMatch(jsonText, '"audioDevice":\s*"([^"]*)"', &match)
        result["audioDevice"] := match[1]
    else
        result["audioDevice"] := "Default"

    ; Extract hotkey
    if RegExMatch(jsonText, '"hotkey":\s*"([^"]*)"', &match)
        result["hotkey"] := match[1]
    else
        result["hotkey"] := "^LWin"

    ; Extract enableLLMCleanup (Settings UI uses camelCase)
    if RegExMatch(jsonText, '"enableLLMCleanup":\s*(true|false|0|1)', &match) {
        val := match[1]
        result["llm_cleanup"] := (val = "true" || val = "1") ? true : false
    }

    ; Extract playSounds (Settings UI uses camelCase)
    if RegExMatch(jsonText, '"playSounds":\s*(true|false|0|1)', &match) {
        val := match[1]
        result["sounds_enabled"] := (val = "true" || val = "1") ? true : false
    }

    ; Extract saveAudioRecordings (Settings UI uses camelCase)
    if RegExMatch(jsonText, '"saveAudioRecordings":\s*(true|false|0|1)', &match) {
        val := match[1]
        result["save_recordings"] := (val = "true" || val = "1") ? true : false
    }

    ; Extract stickyMode (tap-to-toggle recording)
    if RegExMatch(jsonText, '"stickyMode":\s*(true|false|0|1)', &match) {
        val := match[1]
        result["sticky_mode"] := (val = "true" || val = "1") ? true : false
    } else {
        result["sticky_mode"] := false
    }

    return result
}

ParseDictionaryJson(jsonText) {
    result := Map()

    ; Format 1: Array of {spoken, written} objects (used by settings_ui.ahk)
    ; e.g. [{"spoken":"groq","written":"Groq"}, ...]
    pos := 1
    while RegExMatch(jsonText, '"spoken"\s*:\s*"([^"]+)"\s*,\s*"written"\s*:\s*"([^"]+)"', &arrMatch, pos) {
        result[arrMatch[1]] := arrMatch[2]
        pos := arrMatch.Pos + arrMatch.Len
    }
    if (result.Count > 0)
        return result

    ; Format 2: Legacy corrections block (old format)
    ; e.g. {"corrections": {"key": "value", ...}}
    if RegExMatch(jsonText, '"corrections":\s*\{([^}]+)\}', &match) {
        corrections := match[1]
        pos := 1
        while RegExMatch(corrections, '"([^"]+)":\s*"([^"]+)"', &kvMatch, pos) {
            result[kvMatch[1]] := kvMatch[2]
            pos := kvMatch.Pos + kvMatch.Len
        }
    }

    return result
}

; ═══════════════════════════════════════════════════════════════════════════════
;  SOUND FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════

PlaySound(soundType) {
    global Config, SoundsDir
    
    if !Config.Has("sounds_enabled") || !Config["sounds_enabled"]
        return
    
    ; Try to play WAV file first
    wavFile := SoundsDir . "\" . soundType . ".wav"
    if FileExist(wavFile) {
        SoundPlay(wavFile)
        return
    }
    
    ; Fallback to system beeps
    switch soundType {
        case "start":
            SoundBeep(1000, 150)
        case "stop":
            SoundBeep(600, 150)
        case "error":
            SoundBeep(300, 200)
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
;  HISTORY FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════

SaveToHistory(rawText, cleanedText, durationMs, audioFile := "") {
    global HistoryFile, Config
    
    if !Config.Has("history_enabled") || !Config["history_enabled"]
        return
    
    ; Create history entry
    timestamp := FormatTime(, "yyyy-MM-ddTHH:mm:ss")
    wordCount := StrSplit(cleanedText, " ").Length
    activeWindow := WinGetTitle("A")
    
    ; Generate UUID-like ID
    entryId := FormatTime(, "yyyyMMddHHmmss") . "_" . Random(1000, 9999)
    
    ; Create JSON entry
    entry := '{"id": "' . entryId . '", '
    entry .= '"timestamp": "' . timestamp . '", '
    entry .= '"duration_ms": ' . durationMs . ', '
    entry .= '"word_count": ' . wordCount . ', '
    entry .= '"raw_text": "' . EscapeJson(rawText) . '", '
    entry .= '"cleaned_text": "' . EscapeJson(cleanedText) . '", '
    entry .= '"audio_file": "' . audioFile . '", '
    entry .= '"app_context": "' . EscapeJson(activeWindow) . '"}'
    
    ; Read existing history
    if FileExist(HistoryFile) {
        historyText := FileRead(HistoryFile)
        
        ; Insert new entry into entries array
        if InStr(historyText, '"entries": []') {
            ; Empty array - replace with new entry
            historyText := StrReplace(historyText, '"entries": []', '"entries": [' . entry . ']')
        } else if InStr(historyText, '"entries": [') {
            ; Add to existing array
            historyText := StrReplace(historyText, '"entries": [', '"entries": [' . entry . ', ')
        }
        
        ; Write back
        try {
            FileDelete(HistoryFile)
            FileAppend(historyText, HistoryFile)
        }
    }
    
    ; Update statistics
    UpdateStatistics(wordCount, durationMs)
}

EscapeJson(text) {
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, '"', '\"')
    text := StrReplace(text, "`n", "\n")
    text := StrReplace(text, "`r", "")
    text := StrReplace(text, "`t", " ")
    return text
}

UpdateStatistics(wordCount, durationMs) {
    global StatsFile
    
    if !FileExist(StatsFile)
        return
    
    try {
        statsText := FileRead(StatsFile)
        
        ; Parse and update total_words
        if RegExMatch(statsText, '"total_words":\s*(\d+)', &match) {
            newTotal := Integer(match[1]) + wordCount
            statsText := RegExReplace(statsText, '"total_words":\s*\d+', '"total_words": ' . newTotal)
        }
        
        ; Update total_transcriptions
        if RegExMatch(statsText, '"total_transcriptions":\s*(\d+)', &match) {
            newTotal := Integer(match[1]) + 1
            statsText := RegExReplace(statsText, '"total_transcriptions":\s*\d+', '"total_transcriptions": ' . newTotal)
        }
        
        ; Update total_duration_ms
        if RegExMatch(statsText, '"total_duration_ms":\s*(\d+)', &match) {
            newTotal := Integer(match[1]) + durationMs
            statsText := RegExReplace(statsText, '"total_duration_ms":\s*\d+', '"total_duration_ms": ' . newTotal)
        }
        
        ; Update time saved (assuming 40 WPM typing = 1.5 sec per word)
        if RegExMatch(statsText, '"total_time_saved_minutes":\s*(\d+)', &match) {
            timeSavedMinutes := Integer(match[1]) + Round(wordCount * 1.5 / 60)
            statsText := RegExReplace(statsText, '"total_time_saved_minutes":\s*\d+', '"total_time_saved_minutes": ' . timeSavedMinutes)
        }
        
        ; Update last_used
        timestamp := FormatTime(, "yyyy-MM-ddTHH:mm:ss")
        statsText := RegExReplace(statsText, '"last_used":\s*"[^"]*"', '"last_used": "' . timestamp . '"')
        
        ; Set first_used if empty
        if InStr(statsText, '"first_used": ""') {
            statsText := StrReplace(statsText, '"first_used": ""', '"first_used": "' . timestamp . '"')
        }
        
        FileDelete(StatsFile)
        FileAppend(statsText, StatsFile)
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
;  DICTIONARY FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════

ApplyDictionary(text) {
    global Dictionary, Config
    
    if !Config.Has("dictionary_enabled") || !Config["dictionary_enabled"]
        return text
    
    for key, value in Dictionary {
        ; Case-insensitive replacement
        text := RegExReplace(text, "i)\b" . key . "\b", value)
    }
    
    return text
}

; ═══════════════════════════════════════════════════════════════════════════════
;  VOICE COMMANDS
; ═══════════════════════════════════════════════════════════════════════════════

ProcessVoiceCommands(text) {
    ; Navigation and formatting commands
    text := RegExReplace(text, "i)\b(new line|newline)\b", "`n")
    text := RegExReplace(text, "i)\b(new paragraph|paragraph break)\b", "`n`n")
    text := RegExReplace(text, "i)\b(tab key|insert tab)\b", "`t")
    
    ; Deletion commands - these mark text for deletion
    text := RegExReplace(text, "i)\bdelete that\b", "[[DELETE_LAST]]")
    text := RegExReplace(text, "i)\bscratch that\b", "[[DELETE_LAST]]")
    text := RegExReplace(text, "i)\bundo that\b", "[[DELETE_LAST]]")
    text := RegExReplace(text, "i)\bbackspace\b", "[[BACKSPACE]]")
    
    ; Punctuation commands
    text := RegExReplace(text, "i)\bperiod\b", ".")
    text := RegExReplace(text, "i)\bfull stop\b", ".")
    text := RegExReplace(text, "i)\bcomma\b", ",")
    text := RegExReplace(text, "i)\bquestion mark\b", "?")
    text := RegExReplace(text, "i)\bexclamation point\b", "!")
    text := RegExReplace(text, "i)\bexclamation mark\b", "!")
    text := RegExReplace(text, "i)\bcolon\b", ":")
    text := RegExReplace(text, "i)\bsemicolon\b", ";")
    text := RegExReplace(text, "i)\bdash\b", "-")
    text := RegExReplace(text, "i)\bhyphen\b", "-")
    text := RegExReplace(text, "i)\bopen parenthesis\b", "(")
    text := RegExReplace(text, "i)\bclose parenthesis\b", ")")
    text := RegExReplace(text, "i)\bopen bracket\b", "[")
    text := RegExReplace(text, "i)\bclose bracket\b", "]")
    text := RegExReplace(text, "i)\bopen quote\b", '"')
    text := RegExReplace(text, "i)\bclose quote\b", '"')
    text := RegExReplace(text, "i)\bquote\b", '"')
    text := RegExReplace(text, "i)\bapostrophe\b", "'")
    text := RegExReplace(text, "i)\bellipsis\b", "...")
    
    ; Symbol commands
    text := RegExReplace(text, "i)\bat sign\b", "@")
    text := RegExReplace(text, "i)\bhash sign\b", "#")
    text := RegExReplace(text, "i)\bhashtag\b", "#")
    text := RegExReplace(text, "i)\bdollar sign\b", "$")
    text := RegExReplace(text, "i)\bpercent sign\b", "%")
    text := RegExReplace(text, "i)\bampersand\b", "&")
    text := RegExReplace(text, "i)\basterisk\b", "*")
    text := RegExReplace(text, "i)\bstar\b", "*")
    text := RegExReplace(text, "i)\bplus sign\b", "+")
    text := RegExReplace(text, "i)\bequals sign\b", "=")
    text := RegExReplace(text, "i)\bunderscore\b", "_")
    text := RegExReplace(text, "i)\bslash\b", "/")
    text := RegExReplace(text, "i)\bbackslash\b", "\")
    text := RegExReplace(text, "i)\bpipe\b", "|")
    
    ; Formatting commands
    text := RegExReplace(text, "i)\ball caps\b", "[[CAPS_ON]]")
    text := RegExReplace(text, "i)\bend caps\b", "[[CAPS_OFF]]")
    
    ; Clean up any double spaces from replacements
    text := RegExReplace(text, " {2,}", " ")
    
    ; Clean up spaces before punctuation
    text := RegExReplace(text, " ([.,!?;:])", "$1")
    
    return text
}

ExecuteSpecialCommands(text) {
    ; Handle [[DELETE_LAST]] - delete previously pasted text
    if InStr(text, "[[DELETE_LAST]]") {
        ; Select all and delete (user's last paste)
        Send("^a")
        Sleep(50)
        Send("{Delete}")
        text := StrReplace(text, "[[DELETE_LAST]]", "")
        text := Trim(text)
    }
    
    ; Handle [[BACKSPACE]]
    while InStr(text, "[[BACKSPACE]]") {
        Send("{Backspace}")
        text := StrReplace(text, "[[BACKSPACE]]", "", , , 1)
    }
    
    ; Handle caps mode
    if InStr(text, "[[CAPS_ON]]") {
        ; Find text between CAPS_ON and CAPS_OFF
        if RegExMatch(text, "\[\[CAPS_ON\]\](.*?)\[\[CAPS_OFF\]\]", &match) {
            upperText := StrUpper(match[1])
            text := RegExReplace(text, "\[\[CAPS_ON\]\].*?\[\[CAPS_OFF\]\]", upperText, , 1)
        } else {
            ; CAPS_ON without OFF - uppercase rest of text
            pos := InStr(text, "[[CAPS_ON]]")
            beforeCaps := SubStr(text, 1, pos - 1)
            afterCaps := SubStr(text, pos + 11)
            text := beforeCaps . StrUpper(afterCaps)
        }
    }
    
    ; Clean up any remaining markers
    text := StrReplace(text, "[[CAPS_ON]]", "")
    text := StrReplace(text, "[[CAPS_OFF]]", "")
    
    return text
}

; ═══════════════════════════════════════════════════════════════════════════════
;  MICROPHONE DEVICE SELECTION
;  Default device → MCI (instant, zero-latency)
;  Specific device → FFmpeg with DirectShow (reliable for all device types)
; ═══════════════════════════════════════════════════════════════════════════════

GetFFmpegPath() {
    ; Check bundled copy first (shipped with installer), then WinGet, then PATH
    path := A_ScriptDir "\ffmpeg.exe"
    if FileExist(path)
        return path
    path := EnvGet("LOCALAPPDATA") "\Microsoft\WinGet\Links\ffmpeg.exe"
    if FileExist(path)
        return path
    return ""
}

StopFFmpegProcess(pid) {
    ; Stop FFmpeg and ensure WAV file is usable.
    ;
    ; Since FFmpeg launched hidden doesn't have a console for graceful 'q' shutdown,
    ; we force-kill it. The WAV file may have incorrect headers (size=0), so we
    ; fix the RIFF/data headers after killing based on actual file size.
    global ScriptDir

    FileAppend("StopFFmpegProcess: Killing PID " . pid . "`n", ScriptDir . "\debug_log.txt")
    ProcessClose(pid)
    ProcessWaitClose(pid, 2)
    Sleep(100)  ; Let filesystem flush
}

FixWavHeader(filePath) {
    ; Fix WAV file headers after FFmpeg was force-killed.
    ; FFmpeg writes 0xFFFFFFFF placeholder sizes in RIFF/data headers.
    ; When killed abruptly these remain wrong. We patch both:
    ;   1. RIFF size at offset 4  → fileSize - 8
    ;   2. "data" chunk size      → fileSize - (dataChunkOffset + 4)
    ;
    ; IMPORTANT: FFmpeg may write extra sub-chunks (LIST, fact) between "fmt "
    ; and "data", so we SCAN for the actual "data" chunk position rather than
    ; assuming a fixed offset.
    global ScriptDir

    if !FileExist(filePath) {
        FileAppend("FixWavHeader: File not found: " . filePath . "`n", ScriptDir . "\debug_log.txt")
        return false
    }

    fileSize := FileGetSize(filePath)
    if (fileSize < 44) {
        FileAppend("FixWavHeader: File too small (" . fileSize . " bytes), not a valid WAV`n", ScriptDir . "\debug_log.txt")
        return false
    }

    f := FileOpen(filePath, "rw")
    if !f {
        FileAppend("FixWavHeader: Cannot open file`n", ScriptDir . "\debug_log.txt")
        return false
    }

    ; Verify RIFF header
    riff := f.Read(4)
    if (riff != "RIFF") {
        FileAppend("FixWavHeader: Not a RIFF file (got '" . riff . "')`n", ScriptDir . "\debug_log.txt")
        f.Close()
        return false
    }

    oldRiffSize := f.ReadUInt()  ; offset 4
    wave := f.Read(4)            ; offset 8, should be "WAVE"

    ; Calculate correct RIFF size
    correctRiffSize := fileSize - 8

    ; --- Scan for "data" chunk ---
    ; Start at offset 12 (after RIFF + size + WAVE)
    ; Walk through chunks: each has 4-byte ID + 4-byte size + [size] bytes of data
    dataChunkOffset := 0
    pos := 12
    while (pos < fileSize - 8) {
        f.Seek(pos)
        chunkId := f.Read(4)
        if (StrLen(chunkId) < 4)
            break  ; EOF or read error

        chunkSize := f.ReadUInt()

        if (chunkId == "data") {
            ; Found it! The size field is at pos+4
            dataChunkOffset := pos + 4
            FileAppend("FixWavHeader: Found 'data' chunk at offset " . pos . " (size field at " . dataChunkOffset . "), current size=" . chunkSize . "`n", ScriptDir . "\debug_log.txt")
            break
        }

        ; Move to next chunk: pos + 8 (header) + chunkSize
        ; Chunks are word-aligned (padded to even size)
        nextPos := pos + 8 + chunkSize
        if (Mod(chunkSize, 2) == 1)
            nextPos += 1  ; Padding byte for odd-sized chunks
        if (nextPos <= pos)
            break  ; Safety: prevent infinite loop
        pos := nextPos
    }

    if (dataChunkOffset == 0) {
        FileAppend("FixWavHeader: Could not find 'data' chunk! File may be corrupt.`n", ScriptDir . "\debug_log.txt")
        f.Close()
        return false
    }

    ; Calculate correct data size: everything after the data size field to EOF
    correctDataSize := fileSize - (dataChunkOffset + 4)

    ; Check if headers already correct
    if (oldRiffSize == correctRiffSize) {
        FileAppend("FixWavHeader: Headers already correct (RIFF size=" . oldRiffSize . ")`n", ScriptDir . "\debug_log.txt")
        f.Close()
        return true
    }

    FileAppend("FixWavHeader: Fixing headers. File=" . fileSize . " bytes`n", ScriptDir . "\debug_log.txt")
    FileAppend("  RIFF size: " . oldRiffSize . " → " . correctRiffSize . "`n", ScriptDir . "\debug_log.txt")
    FileAppend("  data size at offset " . dataChunkOffset . ": → " . correctDataSize . "`n", ScriptDir . "\debug_log.txt")

    ; Patch RIFF chunk size at offset 4
    f.Seek(4)
    f.WriteUInt(correctRiffSize)

    ; Patch data chunk size at the actual offset we found
    f.Seek(dataChunkOffset)
    f.WriteUInt(correctDataSize)

    f.Close()
    FileAppend("FixWavHeader: Headers fixed successfully`n", ScriptDir . "\debug_log.txt")
    return true
}

IsDeviceAvailable(deviceName) {
    ; Check if a named audio capture device is currently connected.
    ; Uses WASAPI IMMDeviceEnumerator to enumerate active capture endpoints
    ; and match by friendly name. Same approach as AudioMeter._FindDeviceByName().
    try {
        enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

        ; EnumAudioEndpoints(eCapture=1, DEVICE_STATE_ACTIVE=1)
        ComCall(3, enumerator, "int", 1, "int", 1, "ptr*", &collection := 0)
        if !collection
            return false

        ; GetCount
        ComCall(3, collection, "uint*", &count := 0)

        ; PKEY_Device_FriendlyName
        PKEY := Buffer(20)
        DllCall("ole32\CLSIDFromString", "Str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", PKEY)
        NumPut("uint", 14, PKEY, 16)

        found := false
        Loop count {
            idx := A_Index - 1
            ComCall(4, collection, "uint", idx, "ptr*", &device := 0)
            if !device
                continue

            try {
                ComCall(4, device, "int", 0, "ptr*", &propStore := 0)
                if propStore {
                    propVar := Buffer(24, 0)
                    ComCall(5, propStore, "ptr", PKEY, "ptr", propVar)

                    vt := NumGet(propVar, 0, "ushort")
                    if (vt == 31) {  ; VT_LPWSTR
                        pStr := NumGet(propVar, 8, "ptr")
                        friendlyName := StrGet(pStr, "UTF-16")

                        if (InStr(friendlyName, deviceName) || InStr(deviceName, friendlyName)) {
                            found := true
                        }
                    }
                    DllCall("ole32\PropVariantClear", "ptr", propVar)
                    ObjRelease(propStore)
                }
            }

            ObjRelease(device)
            if found
                break
        }

        ObjRelease(collection)
        return found
    } catch {
        return false
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
;  DYNAMIC HOTKEY REGISTRATION
;  Strategy: Default (^LWin) uses hardcoded combo keys for reliable Up detection.
;  Custom hotkeys use Hotkey() with KeyWait for hold-to-record.
; ═══════════════════════════════════════════════════════════════════════════════

RegisterHotkey() {
    global Config, CurrentHotkey, ScriptDir

    ; Get hotkey from config (default: ^LWin = Ctrl+Win)
    newHotkey := Config.Has("hotkey") ? Config["hotkey"] : "^LWin"
    if (newHotkey == "" || newHotkey == "none")
        newHotkey := "^LWin"

    ; If same hotkey is already registered, skip
    if (newHotkey == CurrentHotkey)
        return

    ; Unregister old custom hotkey if one exists
    if (CurrentHotkey != "" && CurrentHotkey != "^LWin") {
        try Hotkey(CurrentHotkey, "Off")
    }

    if (newHotkey == "^LWin") {
        ; Default hotkey uses hardcoded combo keys (defined below)
        ; Nothing to register dynamically - the LCtrl & LWin:: blocks handle it
        CurrentHotkey := "^LWin"
        FileAppend("Default hotkey active: ^LWin (hardcoded combo)`n", ScriptDir . "\debug_log.txt")
    } else {
        ; Custom hotkey: use Hotkey() with KeyWait inside for hold-to-record
        try {
            Hotkey(newHotkey, OnCustomHotkeyPressed)
            CurrentHotkey := newHotkey
            FileAppend("Custom hotkey registered: " . newHotkey . "`n", ScriptDir . "\debug_log.txt")
        } catch as err {
            FileAppend("Custom hotkey FAILED for '" . newHotkey . "': " . err.Message . " - falling back to default`n", ScriptDir . "\debug_log.txt")
            CurrentHotkey := "^LWin"
        }
    }
}

; === CUSTOM HOTKEY HANDLER ===
OnCustomHotkeyPressed(ThisHotkey) {
    global isRecording, StartTime, ScriptDir, CurrentHotkey, Config

    if (Config.Has("sticky_mode") && Config["sticky_mode"]) {
        ; STICKY MODE: tap toggles recording on/off
        if (isRecording)
            StopAndProcess()
        else
            StartRecording()
    } else {
        ; HOLD-TO-RECORD: press starts, release stops
        if (isRecording)
            return

        StartRecording()

        ; Extract the trigger key from the hotkey string to wait for its release
        ; E.g. "^!k" → wait for "k", "^F2" → wait for "F2"
        waitKey := RegExReplace(CurrentHotkey, "[\^!+#]", "")  ; Strip modifier prefixes
        if (waitKey == "")
            waitKey := "LWin"  ; Fallback

        KeyWait(waitKey)
        StopAndProcess()
    }
}

; === DEFAULT HOTKEY: Hardcoded LCtrl & LWin combo (most reliable) ===
; These only fire when CurrentHotkey == "^LWin" (default mode)
LCtrl & LWin::
{
    global CurrentHotkey, isRecording, Config
    if (CurrentHotkey != "^LWin")
        return  ; Custom hotkey is active, ignore default

    if (Config.Has("sticky_mode") && Config["sticky_mode"]) {
        ; STICKY MODE: tap toggles recording
        if (isRecording)
            StopAndProcess()
        else
            StartRecording()
    } else {
        StartRecording()
    }
}

LCtrl & LWin Up::
{
    global CurrentHotkey, Config
    if (CurrentHotkey != "^LWin")
        return  ; Custom hotkey is active, ignore default

    ; In sticky mode, key-up does nothing (tap-to-stop uses key-down)
    if (Config.Has("sticky_mode") && Config["sticky_mode"])
        return

    StopAndProcess()
}

; === SHARED RECORDING FUNCTIONS ===
StartRecording() {
    global isRecording, StartTime, TempFile, ScriptDir, Config, FFmpegPID

    if (isRecording)
        return

    StartTime := A_TickCount
    isRecording := true
    PostMessageToLauncher(2)  ; Signal Recording

    PlaySound("start")

    if FileExist("raw.wav")
        try FileDelete("raw.wav")

    ShowRecordingOverlay("recording")

    ; --- AUDIO CAPTURE ---
    audioDevice := Config.Has("audioDevice") ? Config["audioDevice"] : "Default"

    if (audioDevice == "" || audioDevice == "Default") {
        ; DEFAULT DEVICE: Use MCI (instant, zero-latency, proven reliable)
        DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
        DllCall("winmm\mciSendString", "Str", "record capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
        FileAppend("Recording started: MCI (default device)`n", ScriptDir . "\debug_log.txt")
    } else {
        ; SPECIFIC DEVICE: Use FFmpeg with DirectShow (reliable for all device types incl. Bluetooth)
        ; First check if the device is still connected — auto-fallback to default if not
        if !IsDeviceAvailable(audioDevice) {
            FileAppend("WARNING: Device '" . audioDevice . "' not available, falling back to MCI default`n", ScriptDir . "\debug_log.txt")
            DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
            DllCall("winmm\mciSendString", "Str", "record capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
            FileAppend("Recording started: MCI (fallback — device disconnected)`n", ScriptDir . "\debug_log.txt")
        } else {
            ffmpegPath := GetFFmpegPath()
            if (ffmpegPath == "") {
                ; FFmpeg not found — fall back to MCI default
                FileAppend("WARNING: FFmpeg not found, falling back to MCI default device`n", ScriptDir . "\debug_log.txt")
                DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
                DllCall("winmm\mciSendString", "Str", "record capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
            } else {
                ; Launch FFmpeg as background process (will be force-killed, WAV headers fixed after)
                ffmpegCmd := '"' . ffmpegPath . '" -f dshow -rtbufsize 512M -i audio="' . audioDevice . '" -ar 16000 -ac 1 -flush_packets 1 -y "' . ScriptDir . '\raw.wav"'
                FileAppend("Recording started: FFmpeg device='" . audioDevice . "'`n", ScriptDir . "\debug_log.txt")
                FileAppend("FFmpeg command: " . ffmpegCmd . "`n", ScriptDir . "\debug_log.txt")
                Run(ffmpegCmd, ScriptDir, "Hide", &FFmpegPID)
                FileAppend("FFmpeg PID: " . FFmpegPID . "`n", ScriptDir . "\debug_log.txt")
            }
        }
    }
}

StopAndProcess() {
    global isRecording, StartTime, TempFile, RawFile, PayloadFile, ScriptDir, AudioDir, Config, FFmpegPID

    if (!isRecording)
        return

    isRecording := false
    recordDuration := A_TickCount - StartTime
    PostMessageToLauncher(3)  ; Signal Processing

    PlaySound("stop")

    UpdateRecordingOverlay("processing")

    ; --- STOP & SAVE ---
    if (FFmpegPID > 0) {
        ; FFmpeg path: kill process then fix WAV headers
        StopFFmpegProcess(FFmpegPID)
        FFmpegPID := 0
        ; Fix WAV headers (FFmpeg writes size=0 when killed abruptly)
        FixWavHeader(ScriptDir . "\raw.wav")
        FileAppend("FFmpeg stopped, WAV fixed`n", ScriptDir . "\debug_log.txt")
    } else {
        ; MCI path: save and close
        DllCall("winmm\mciSendString", "Str", "save capture raw.wav wait", "Ptr", 0, "UInt", 0, "Ptr", 0)
        DllCall("winmm\mciSendString", "Str", "close capture", "Ptr", 0, "UInt", 0, "Ptr", 0)
    }

    TempFile := "raw.wav"

    if !FileExist(TempFile) {
        UpdateRecordingOverlay("error")
        PlaySound("error")
        SetTimer(() => HideRecordingOverlay(), -3000)
        PostMessageToLauncher(1)
        return
    }

    ; Save audio recording if enabled
    savedAudioPath := ""
    if Config.Has("save_recordings") && Config["save_recordings"] {
        audioFilename := "QS_" . FormatTime(, "yyyyMMdd_HHmmss") . ".wav"
        savedAudioPath := AudioDir . "\" . audioFilename
        try {
            FileCopy(TempFile, savedAudioPath)
        }
    }

    ; --- TRANSCRIBE (Groq Whisper) ---
    GroqAPIKey := GetApiKey()
    A_Clipboard := ""
    WhisperURL := "https://api.groq.com/openai/v1/audio/transcriptions"
    sttModel := Config.Has("stt_model") ? Config["stt_model"] : "whisper-large-v3-turbo"

    ; Map friendly language name to ISO code
    langRaw := Config.Has("language") ? Config["language"] : "en"
    langCodes := Map(
        "English", "en",
        "Spanish", "es",
        "French", "fr",
        "German", "de",
        "Japanese", "ja",
        "Chinese", "zh",
        "Korean", "ko"
    )
    lang := langCodes.Has(langRaw) ? langCodes[langRaw] : langRaw

    RunWait('cmd /c curl -s -X POST -H "Authorization: Bearer ' . GroqAPIKey . '" -F "file=@' . TempFile . '" -F "model=' . sttModel . '" -F "language=' . lang . '" ' . WhisperURL . ' > response.txt 2> log.txt', , "Hide")

    FileAppend("--- NEW RUN ---`n", ScriptDir . "\debug_log.txt")

    if FileExist("response.txt") {
        ResponseText := FileRead("response.txt")
        FileAppend("Whisper Raw: " . ResponseText . "`n", ScriptDir . "\debug_log.txt")

        RawText := "" ; Initialize

        if RegExMatch(ResponseText, 's)"text":"(.*?)"', &Match) {
            RawText := Match[1]
            RawText := StrReplace(RawText, "\n", "`n")
            RawText := StrReplace(RawText, '\"', '"')

            FinalText := RawText

            ; --- LLM CLEANUP (if enabled) ---
            if Config.Has("llm_cleanup") && Config["llm_cleanup"] {
                try {
                    if FileExist(PayloadFile)
                        FileDelete(PayloadFile)

                    SafeText := StrReplace(RawText, "\", "\\")
                    SafeText := StrReplace(SafeText, '"', '\"')
                    SafeText := StrReplace(SafeText, "`n", "\n")
                    SafeText := StrReplace(SafeText, "`r", "")
                    SafeText := StrReplace(SafeText, "`t", " ")

                    llmModel := Config.Has("llm_model") ? Config["llm_model"] : "llama-3.3-70b-versatile"
                    GroqPayload := '{"model": "' . llmModel . '", "messages": [{"role": "user", "content": "Clean up this transcribed speech. Fix grammar and punctuation. Return ONLY the corrected text with no explanation:\n\n' . SafeText . '"}]}'
                    FileAppend(GroqPayload, PayloadFile)

                    GroqLLMURL := "https://api.groq.com/openai/v1/chat/completions"
                    RunWait('cmd /c curl -s -X POST -H "Authorization: Bearer ' . GroqAPIKey . '" -H "Content-Type: application/json" -d @' . PayloadFile . ' --max-time 15 ' . GroqLLMURL . ' > clean_response.txt 2>> debug_log.txt', , "Hide")

                    if FileExist("clean_response.txt") {
                        CleanResponse := FileRead("clean_response.txt")
                        FileAppend("Groq LLM Clean: " . CleanResponse . "`n", ScriptDir . "\debug_log.txt")

                        if RegExMatch(CleanResponse, 's)"content":\s*"(.*?)"(?=\s*}\s*,?\s*"logprobs"|,\s*"refusal"|}\s*]\s*,)', &CleanMatch) {
                            FinalText := CleanMatch[1]
                            FinalText := StrReplace(FinalText, "\n", "`n")
                            FinalText := StrReplace(FinalText, '\"', '"')
                        } else if RegExMatch(CleanResponse, 's)"content":\s*"([^"]+)"', &CleanMatch) {
                            FinalText := CleanMatch[1]
                            FinalText := StrReplace(FinalText, "\n", "`n")
                            FinalText := StrReplace(FinalText, '\"', '"')
                        }
                    }
                }
            }

            ; Apply dictionary corrections
            FinalText := ApplyDictionary(FinalText)

            ; Process voice commands (new line, punctuation, etc.)
            FinalText := ProcessVoiceCommands(FinalText)

            ; Execute special commands (delete, backspace, caps)
            FinalText := ExecuteSpecialCommands(FinalText)

            ; Save to history
            SaveToHistory(RawText, FinalText, recordDuration, savedAudioPath)

            if (StrLen(FinalText) > 0) {
                ; Smart spacing: Check if we need a space before pasting
                oldClip := ClipboardAll()
                A_Clipboard := ""
                Send("+{Left}")  ; Select char before cursor
                Sleep(50)
                Send("^c")       ; Copy it
                Sleep(50)
                Send("{Right}")  ; Deselect, move cursor back
                charBefore := A_Clipboard
                A_Clipboard := oldClip  ; Restore original clipboard
                oldClip := ""

                ; If there's a non-space character before cursor, prepend space
                if (StrLen(charBefore) > 0 && !RegExMatch(charBefore, "[\s\n\r]")) {
                    FinalText := " " . FinalText
                }

                A_Clipboard := FinalText
                Send("^v")
                UpdateRecordingOverlay("success")
                PostMessageToLauncher(1)
                return
            }
        } else {
             ; API Error / No Text
             FileAppend("API Failure: " . ResponseText . "`n", ScriptDir . "\debug_log.txt")
             PlaySound("error")
             UpdateRecordingOverlay("error")
             SetTimer(() => HideRecordingOverlay(), -2000)
             PostMessageToLauncher(1)
             return
        }

    }

    HideRecordingOverlay()
    PostMessageToLauncher(1)
}


; ═══════════════════════════════════════════════════════════════════════════════
;  DPAPI ENCRYPTION (Windows Data Protection API)
;  Encrypts API keys so they are not stored in plaintext in config.json
;  Uses current user's Windows credentials — only decryptable by same user
; ═══════════════════════════════════════════════════════════════════════════════

DPAPIEncrypt(plainText) {
    if (plainText == "")
        return ""

    ; Convert string to UTF-8 bytes
    utf8Len := StrPut(plainText, "UTF-8") - 1  ; Exclude null terminator
    inputBuf := Buffer(utf8Len)
    StrPut(plainText, inputBuf, "UTF-8")

    ; DATA_BLOB for input
    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", utf8Len, inputBlob, 0)
    NumPut("ptr", inputBuf.Ptr, inputBlob, A_PtrSize)

    ; DATA_BLOB for output
    outputBlob := Buffer(A_PtrSize * 2, 0)

    ; CryptProtectData(pDataIn, desc, pOptionalEntropy, pvReserved, pPromptStruct, dwFlags, pDataOut)
    ; dwFlags=1 (CRYPTPROTECT_UI_FORBIDDEN) — no UI prompts
    result := DllCall("crypt32\CryptProtectData",
        "ptr", inputBlob,
        "ptr", 0,
        "ptr", 0,
        "ptr", 0,
        "ptr", 0,
        "int", 1,
        "ptr", outputBlob)

    if !result
        return ""

    ; Read output blob
    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")

    ; Convert to base64
    ; First get required buffer size
    DllCall("crypt32\CryptBinaryToStringW",
        "ptr", outPtr,
        "uint", outSize,
        "uint", 0x40000001,  ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
        "ptr", 0,
        "uint*", &b64Len := 0)

    b64Buf := Buffer(b64Len * 2)
    DllCall("crypt32\CryptBinaryToStringW",
        "ptr", outPtr,
        "uint", outSize,
        "uint", 0x40000001,
        "ptr", b64Buf,
        "uint*", &b64Len)

    ; Free the output blob
    DllCall("LocalFree", "ptr", outPtr)

    return StrGet(b64Buf, "UTF-16")
}

DPAPIDecrypt(base64Text) {
    if (base64Text == "")
        return ""

    ; Convert base64 to binary
    DllCall("crypt32\CryptStringToBinaryW",
        "str", base64Text,
        "uint", 0,
        "uint", 1,  ; CRYPT_STRING_BASE64
        "ptr", 0,
        "uint*", &binLen := 0,
        "ptr", 0,
        "ptr", 0)

    if (binLen == 0)
        return ""

    binBuf := Buffer(binLen)
    DllCall("crypt32\CryptStringToBinaryW",
        "str", base64Text,
        "uint", 0,
        "uint", 1,
        "ptr", binBuf,
        "uint*", &binLen,
        "ptr", 0,
        "ptr", 0)

    ; DATA_BLOB for input (encrypted data)
    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", binLen, inputBlob, 0)
    NumPut("ptr", binBuf.Ptr, inputBlob, A_PtrSize)

    ; DATA_BLOB for output (decrypted data)
    outputBlob := Buffer(A_PtrSize * 2, 0)

    ; CryptUnprotectData
    result := DllCall("crypt32\CryptUnprotectData",
        "ptr", inputBlob,
        "ptr", 0,
        "ptr", 0,
        "ptr", 0,
        "ptr", 0,
        "int", 1,
        "ptr", outputBlob)

    if !result
        return ""

    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")

    ; Read decrypted UTF-8 bytes back to string
    decrypted := StrGet(outPtr, outSize, "UTF-8")

    ; Free output
    DllCall("LocalFree", "ptr", outPtr)

    return decrypted
}

IsEncryptedKey(value) {
    ; Encrypted keys are base64-encoded DPAPI blobs — they do NOT start with "gsk_"
    ; Plaintext Groq keys always start with "gsk_"
    if (value == "")
        return false
    return !SubStr(value, 1, 4) == "gsk_" && StrLen(value) > 20
}

; ═══════════════════════════════════════════════════════════════════════════════
;  SYSTEM FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════

PreWarm() {
    ; Load the Windows Multimedia DLL into memory
    DllCall("LoadLibrary", "Str", "winmm.dll")
    
    ; Initialize the MCI audio capture graph by opening and closing a dummy session
    ; This absorbs the "first run" latency (~200ms) for default device recording
    DllCall("winmm\mciSendString", "Str", "open new type waveaudio alias warmup", "Ptr", 0, "UInt", 0, "Ptr", 0)
    DllCall("winmm\mciSendString", "Str", "record warmup", "Ptr", 0, "UInt", 0, "Ptr", 0)
    Sleep(50) 
    DllCall("winmm\mciSendString", "Str", "stop warmup", "Ptr", 0, "UInt", 0, "Ptr", 0)
    DllCall("winmm\mciSendString", "Str", "close warmup", "Ptr", 0, "UInt", 0, "Ptr", 0)
    
    ; Prime sounds cache
    global SoundsDir
    if FileExist(SoundsDir . "\start.wav")
        try FileRead(SoundsDir . "\start.wav")
}

; --- GROQ API KEY (loaded from config or hardcoded fallback) ---
GetApiKey() {
    global Config
    
    ; Try config first
    if Config.Has("groq_api_key") && Config["groq_api_key"] != ""
        return Config["groq_api_key"]
    
    ; Fallback to hardcoded key (for backwards compatibility)
    ; Fallback REMOVED for security
    return ""
}

WhisperURL := "https://api.groq.com/openai/v1/audio/transcriptions"

TempFile := "recording.wav"
RawFile := "raw.wav"
PayloadFile := "payload.json"
