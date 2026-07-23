; ==============================================================================
;  lib/telemetry.ahk — Opt-in, off-by-default product telemetry via PostHog
;  (T2.7). Spec: docs/audit-campaign/sessions/session-T2.7-telemetry.md.
;  Event contract: Development/docs/telemetry-events.md (code must not emit
;  anything not listed there).
;
;  Privacy architecture — three layers:
;    1. MASTER GATE: TelemetryEnabled() — a hard no-op when off (default).
;    2. ALLOWLIST:   EmitEvent() rejects any event name not in TELEMETRY_EVENTS.
;    3. SCRUB:       Telemetry_ScrubProps() drops deny-listed keys and value
;                    patterns before the payload is built.
;
;  The module is fully off the dictation hot path: events are queued in memory
;  and flushed by a deferred SetTimer (≥ 30 s between flushes). Every network
;  error is swallowed — telemetry never blocks or slows recording.
;
;  Public API (also the unit-test contract — tests/telemetry/telemetry-tests.ahk):
;    Telemetry_Configure(optsMap)         inject config (enabled, projectKey, ...)
;    TelemetryEnabled()           -> bool  master gate
;    Telemetry_GetOrCreateInstallId() -> str  UUID, stable while on, regenerated on re-enable
;    EmitEvent(name, props?)             enqueue if gate+allowlist pass
;    Telemetry_FlushNow()                force-flush queue (used by tests + exit handler)
;    Telemetry_Reset()                   clear all state (tests only)
;    Telemetry_DurationBucket(ms) -> str  "<5s" | "5-15s" | "15-60s" | ">60s"
;    Telemetry_ScrubProps(props)  -> Map  deny-listed keys / dangerous values removed
;    ; DI seams (tests only):
;    Telemetry_SetSendHook(fn)           replace the HTTP POST (fn(url, body)->status)
;    Telemetry_SetConfigReadHook(fn)     replace config read (fn()->Map)
;    Telemetry_SetConfigWriteHook(fn)    replace config write (fn(key,val)->bool)
;
;  NEVER sent (non-exhaustive; see telemetry-events.md):
;    transcript text, audio paths, API keys, license JWT, email, username,
;    machine name, MAC address, full file paths, IP address.
; ==============================================================================
#Requires AutoHotkey v2.0

; ── PostHog endpoint + public project key ─────────────────────────────────────
; EU data residency. Set POSTHOG_PROJECT_KEY at M.3 (public capture key only —
; safe in the binary; cannot read events, only write them).
global POSTHOG_ENDPOINT    := "https://eu.i.posthog.com"
global POSTHOG_PROJECT_KEY := ""   ; EMPTY by default — set at M.3

; ── Allowed event names (must match telemetry-events.md exactly) ──────────────
global TELEMETRY_EVENTS := Map(
    "app_started",          true,
    "recording_completed",  true,
    "settings_changed",     true,
    "crash_reported",       true,
    "update_check",         true,
    "update_installed",     true
)

; ── Allowed keys for settings_changed.changed_keys ────────────────────────────
global TELEMETRY_SETTINGS_KEYS := Map(
    "soundTheme",         true,
    "hotkeyMode",         true,
    "playSounds",         true,
    "showOverlay",        true,
    "enableLLMCleanup",   true,
    "autoRemoveFillers",  true,
    "smartPunctuation",   true,
    "debugLogging",       true,
    "recordingQuality",   true,
    "launchAtStartup",    true,
    "saveAudioRecordings",true,
    "historyRetention",   true,
    "accessibilityMode",  true,
    "autoPaste",          true,
    "stickyMode",         true,
    "contextAwareModes",  true,
    "showWidget",         true,
    "currentMode",        true
)

; ── Denied prop keys (values of these are always stripped) ────────────────────
; The allowlist is the primary defense; this is the second line.
global TELEMETRY_DENIED_KEYS := Map(
    "groqApiKey",         true,
    "api_key",            true,
    "apikey",             true,
    "apiKey",             true,
    "licenseJwt",         true,
    "jwt",                true,
    "token",              true,
    "email",              true,
    "filePath",           true,
    "path",               true,
    "machineName",        true,
    "computerName",       true,
    "username",           true,
    "userName",           true,
    "macAddress",         true,
    "mac",                true,
    "transcript",         true,
    "rawText",            true,
    "finalText",          true,
    "cleanedText",        true,
    "dictionary",         true,
    "history",            true,
    "trialMachineId",     true,
    "telemetryInstallId", true,
    "duration_ms",        true   ; always converted to duration_bucket
)

; ── Module state ──────────────────────────────────────────────────────────────
global g_TelEnabled     := false
global g_TelProjectKey  := ""
global g_TelAppVersion  := "0.0.0"
global g_TelInstallId   := ""
global g_TelDebug       := false
global g_TelQueue       := []      ; pending events
global g_TelLastFlush   := 0       ; unix-ms of last flush (throttle)
global g_TelFlushScheduled := false
global TELEMETRY_MIN_FLUSH_MS := 30000  ; minimum 30 s between real flushes
global TELEMETRY_MAX_QUEUE    := 20     ; flush when queue hits this

; DI seams (override in tests)
global g_TelSendHook        := ""  ; fn(url, body) -> http status
global g_TelConfigReadHook  := ""  ; fn() -> Map of config
global g_TelConfigWriteHook := ""  ; fn(key, val) -> bool

; ──────────────────────────────────────────────────────────────────────────────
;  Configuration injection
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_Configure(opts) {
    global g_TelEnabled, g_TelProjectKey, g_TelAppVersion
    global g_TelInstallId, g_TelDebug
    global POSTHOG_PROJECT_KEY

    if (Type(opts) != "Map")
        return

    if opts.Has("enabled")
        g_TelEnabled := !!(opts["enabled"])
    if opts.Has("projectKey")
        g_TelProjectKey := opts["projectKey"]
    else
        g_TelProjectKey := POSTHOG_PROJECT_KEY
    if opts.Has("appVersion")
        g_TelAppVersion := opts["appVersion"]
    if opts.Has("installId") && opts["installId"] != ""
        g_TelInstallId := opts["installId"]
    if opts.Has("debug")
        g_TelDebug := !!(opts["debug"])
}

; ──────────────────────────────────────────────────────────────────────────────
;  Master gate
; ──────────────────────────────────────────────────────────────────────────────

TelemetryEnabled() {
    global g_TelEnabled, g_TelProjectKey
    return g_TelEnabled && g_TelProjectKey != ""
}

; ──────────────────────────────────────────────────────────────────────────────
;  Anonymous install ID
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_GetOrCreateInstallId() {
    global g_TelInstallId, g_TelConfigReadHook, g_TelConfigWriteHook

    ; Return cached in-memory value if already set this session
    if (g_TelInstallId != "")
        return g_TelInstallId

    ; Try reading from config
    cfg := (g_TelConfigReadHook is Func) ? g_TelConfigReadHook() : Telemetry_ReadConfig()
    if (Type(cfg) = "Map" && cfg.Has("telemetryInstallId") && cfg["telemetryInstallId"] != "") {
        g_TelInstallId := cfg["telemetryInstallId"]
        return g_TelInstallId
    }

    ; Generate a fresh UUID (random, not derived from any machine attribute)
    g_TelInstallId := Telemetry_GenerateUUID()

    ; Persist to config
    if (g_TelConfigWriteHook is Func)
        g_TelConfigWriteHook("telemetryInstallId", g_TelInstallId)
    else
        Telemetry_WriteConfig("telemetryInstallId", g_TelInstallId)

    return g_TelInstallId
}

; Wipe the cached install ID (called when telemetry is turned OFF so that
; re-enabling generates a new UUID, breaking the timeline as promised).
Telemetry_RegenerateInstallId() {
    global g_TelInstallId, g_TelConfigWriteHook
    g_TelInstallId := ""
    if (g_TelConfigWriteHook is Func)
        g_TelConfigWriteHook("telemetryInstallId", "")
    else
        Telemetry_WriteConfig("telemetryInstallId", "")
}

; ──────────────────────────────────────────────────────────────────────────────
;  Emit — enqueue an event (gate + allowlist + scrub)
; ──────────────────────────────────────────────────────────────────────────────

EmitEvent(name, rawProps := "") {
    global g_TelQueue, TELEMETRY_EVENTS, TELEMETRY_MAX_QUEUE

    ; 1. Master gate
    if (!TelemetryEnabled())
        return

    ; 2. Allowlist — unknown event names are silently dropped
    if (!TELEMETRY_EVENTS.Has(name))
        return

    ; 3. Build safe props
    props := (Type(rawProps) = "Map") ? rawProps : Map()
    safe := Telemetry_BuildSafeProps(name, props)

    ; 4. settings_changed: if no allowlisted keys changed, skip
    if (name = "settings_changed") {
        if (!safe.Has("changed_keys") || safe["changed_keys"].Length = 0)
            return
    }

    ; 5. Install ID goes in every event's distinct_id
    installId := Telemetry_GetOrCreateInstallId()

    ; 6. Build the PostHog event object
    evt := Map(
        "event",      name,
        "timestamp",  Telemetry_NowISO8601(),
        "properties", safe
    )
    evt["properties"]["distinct_id"] := installId

    ; 7. Enqueue
    g_TelQueue.Push(evt)

    ; 8. Flush if queue is full; otherwise schedule a deferred flush
    if (g_TelQueue.Length >= TELEMETRY_MAX_QUEUE)
        Telemetry_FlushNow()
    else
        Telemetry_ScheduleFlush()
}

; ──────────────────────────────────────────────────────────────────────────────
;  Property building — event-specific transforms + scrub
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_BuildSafeProps(eventName, props) {
    ; Start with the scrubbed input
    safe := Telemetry_ScrubProps(props)

    ; Event-specific transforms
    if (eventName = "recording_completed") {
        ; duration_ms → duration_bucket (raw ms MUST NOT appear in the payload)
        ; Read from original props (before scrub removed it) then ensure it's gone from safe.
        durationMs := props.Has("duration_ms") ? props["duration_ms"] : 0
        if safe.Has("duration_ms")   ; scrub may already have removed it
            safe.Delete("duration_ms")
        safe["duration_bucket"] := Telemetry_DurationBucket(durationMs)

        ; mode: if not a known preset, emit "custom"
        if (safe.Has("mode")) {
            known := Map("standard", "Standard", "email", "Email",
                        "code", "Code", "casual", "Casual",
                        "Standard", "Standard", "Email", "Email",
                        "Code", "Code", "Casual", "Casual")
            if (!known.Has(safe["mode"]))
                safe["mode"] := "custom"
            else
                safe["mode"] := known[safe["mode"]]
        }
    }

    if (eventName = "settings_changed") {
        ; Filter changed_keys to the allowlist only
        if (props.Has("changed_keys") && Type(props["changed_keys"]) = "Array") {
            filtered := []
            for k in props["changed_keys"] {
                global TELEMETRY_SETTINGS_KEYS
                if (TELEMETRY_SETTINGS_KEYS.Has(k))
                    filtered.Push(k)
            }
            safe["changed_keys"] := filtered
        } else {
            safe["changed_keys"] := []
        }
    }

    return safe
}

; Remove denied keys and scrub dangerous value patterns
Telemetry_ScrubProps(props) {
    global TELEMETRY_DENIED_KEYS
    out := Map()
    if (Type(props) != "Map")
        return out

    for k, v in props {
        ; Drop denied keys entirely (key name is the primary check)
        if (TELEMETRY_DENIED_KEYS.Has(k))
            continue

        ; Drop values that look like API keys, JWTs, paths with usernames, or MACs
        if (Type(v) = "String" && Telemetry_ValueIsDangerous(v))
            continue

        ; For arrays (e.g. changed_keys is handled above; skip scrubbing Array values here)
        out[k] := v
    }
    return out
}

; Returns true if a string value looks like something we must never send.
; NOTE: The key-name denylist (TELEMETRY_DENIED_KEYS) is the PRIMARY defense.
; This function is the SECOND line of defence — it catches dangerous values
; that reach here under an innocent key name.  Patterns are UNANCHORED (no ^)
; so they match even when the secret is embedded in a longer string.
Telemetry_ValueIsDangerous(val) {
    if (val = "")
        return false
    ; Groq API key — unanchored so "error: key gsk_ABCDE..." is caught
    if (RegExMatch(val, "gsk_[A-Za-z0-9]{20,}"))
        return true
    ; JWT — eyJ is base64url for '{"'; a dot-separated triple catches all JWTs
    ; even when preceded by "token: " or similar prose
    if (RegExMatch(val, "eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"))
        return true
    ; Email address
    if (RegExMatch(val, "[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"))
        return true
    ; Windows path containing a username (any drive letter)
    if (RegExMatch(val, "i)\\Users\\[^\\]+\\"))
        return true
    ; MAC address (colon-separated hex pairs)
    if (RegExMatch(val, "[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}"))
        return true
    return false
}

; ──────────────────────────────────────────────────────────────────────────────
;  Duration bucketing
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_DurationBucket(ms) {
    ms := IsNumber(ms) ? Integer(ms) : 0
    if (ms < 5000)
        return "<5s"
    if (ms < 15000)
        return "5-15s"
    if (ms < 60000)
        return "15-60s"
    return ">60s"
}

; ──────────────────────────────────────────────────────────────────────────────
;  Flush — build batch POST and send
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_ScheduleFlush() {
    global g_TelFlushScheduled
    if (g_TelFlushScheduled)
        return
    g_TelFlushScheduled := true
    SetTimer(Telemetry_FlushOnTimer, -60000)   ; flush after 60 s idle
}

Telemetry_FlushOnTimer() {
    global g_TelFlushScheduled
    g_TelFlushScheduled := false
    Telemetry_FlushNow()
}

Telemetry_FlushNow() {
    global g_TelQueue, g_TelLastFlush, g_TelProjectKey
    global TELEMETRY_MIN_FLUSH_MS

    if (g_TelQueue.Length = 0)
        return

    ; Throttle: at most one flush per MIN_FLUSH_MS in the real send path.
    ; Skip the throttle when a send hook is injected (test mode).
    global g_TelSendHook
    if (!(g_TelSendHook is Func)) {
        now := A_TickCount
        if (now - g_TelLastFlush < TELEMETRY_MIN_FLUSH_MS)
            return
    }

    ; Grab all queued events and clear the queue
    events := g_TelQueue
    g_TelQueue := []

    key := (g_TelProjectKey != "") ? g_TelProjectKey : POSTHOG_PROJECT_KEY
    if (key = "")
        return   ; no project key → nothing to send

    ; Build the PostHog batch payload
    batchBody := Telemetry_BuildBatchPayload(key, events)

    ; Send — swallow all errors
    try {
        url := POSTHOG_ENDPOINT . "/batch/"
        if (g_TelSendHook is Func)
            g_TelSendHook(url, batchBody)
        else
            Telemetry_HttpPost(url, batchBody)
        g_TelLastFlush := A_TickCount
    } catch {
        ; Network failure is silently swallowed — never blocks recording
    }
}

; Build the PostHog batch JSON string
Telemetry_BuildBatchPayload(apiKey, events) {
    batchArr := "["
    for i, evt in events {
        if (i > 1)
            batchArr .= ","
        batchArr .= Telemetry_EventToJson(evt)
    }
    batchArr .= "]"

    return '{"api_key":"' . EscapeTelJson(apiKey) . '","batch":' . batchArr . '}'
}

; Serialise one event map to JSON
Telemetry_EventToJson(evt) {
    name      := evt.Has("event")     ? evt["event"]     : ""
    timestamp := evt.Has("timestamp") ? evt["timestamp"] : ""
    props     := evt.Has("properties") ? evt["properties"] : Map()

    propsJson := Telemetry_PropsToJson(props)
    return '{"event":"' . EscapeTelJson(name) . '"'
        . ',"timestamp":"' . EscapeTelJson(timestamp) . '"'
        . ',"properties":' . propsJson . '}'
}

; Serialise a props Map to JSON (handles string, number, bool, Array, Map values)
Telemetry_PropsToJson(props) {
    if (Type(props) != "Map")
        return "{}"
    out := "{"
    first := true
    for k, v in props {
        if (!first)
            out .= ","
        first := false
        out .= '"' . EscapeTelJson(k) . '":' . Telemetry_ValToJson(v)
    }
    out .= "}"
    return out
}

Telemetry_ValToJson(v) {
    t := Type(v)
    if (t = "String")
        return '"' . EscapeTelJson(v) . '"'
    if (t = "Integer" || t = "Float")
        return v
    if (t = "Array") {
        out := "["
        for i, item in v {
            if (i > 1)
                out .= ","
            out .= Telemetry_ValToJson(item)
        }
        return out . "]"
    }
    if (v = true)
        return "true"
    if (v = false)
        return "false"
    return "null"
}

; Minimal JSON string escaping (only what's needed for safe embedding)
EscapeTelJson(text) {
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, '"', '\"')
    text := StrReplace(text, "`n", "\n")
    text := StrReplace(text, "`r", "")
    text := StrReplace(text, "`t", "\t")
    return text
}

; ──────────────────────────────────────────────────────────────────────────────
;  HTTP POST (real path — not used in tests)
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_HttpPost(url, body) {
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(5000, 5000, 8000, 8000)
        http.Open("POST", url, false)
        http.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        ; Write body as UTF-8 bytes via ADODB to avoid charset issues
        stream := ComObject("ADODB.Stream")
        stream.Type := 2     ; text
        stream.Charset := "utf-8"
        stream.Open()
        stream.WriteText(body)
        stream.Position := 0
        stream.Type := 1     ; binary
        stream.Position := 3 ; skip BOM
        bodyBytes := stream.Read()
        stream.Close()
        http.Send(bodyBytes)
        return http.Status
    } catch {
        return 0
    }
}

; ──────────────────────────────────────────────────────────────────────────────
;  Config read/write (real path — not used in tests)
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_ReadConfig() {
    configPath := A_ScriptDir . "\config.json"
    if (!FileExist(configPath))
        return Map()
    try {
        text := FileRead(configPath, "UTF-8")
        parsed := JSON.Parse(text)
        return (Type(parsed) = "Map") ? parsed : Map()
    } catch {
        return Map()
    }
}

Telemetry_WriteConfig(key, val) {
    configPath := A_ScriptDir . "\config.json"
    try {
        cfg := Telemetry_ReadConfig()
        cfg[key] := val
        text := JSON.Stringify(cfg, "  ")
        ; Atomic write
        tmpPath := configPath . ".tel.tmp"
        if FileExist(tmpPath)
            try FileDelete(tmpPath)
        FileAppend(text, tmpPath, "UTF-8")
        FileMove(tmpPath, configPath, true)
        return true
    } catch {
        return false
    }
}

; ──────────────────────────────────────────────────────────────────────────────
;  UUID generation (CoCreateGuid — random, not derived from hardware)
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_GenerateUUID() {
    guid := Buffer(16, 0)
    DllCall("Ole32\CoCreateGuid", "Ptr", guid)
    str := Buffer(78, 0)
    DllCall("Ole32\StringFromGUID2", "Ptr", guid, "Ptr", str, "Int", 39)
    s := StrGet(str)
    ; Strip braces: {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} → lowercase UUID
    s := SubStr(s, 2, StrLen(s) - 2)
    return StrLower(s)
}

; ──────────────────────────────────────────────────────────────────────────────
;  Timestamp helper
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_NowISO8601() {
    ; A_Now is local time; convert to UTC approximation using A_NowUTC
    utc := A_NowUTC
    return SubStr(utc, 1, 4) . "-" . SubStr(utc, 5, 2) . "-" . SubStr(utc, 7, 2)
        . "T" . SubStr(utc, 9, 2) . ":" . SubStr(utc, 11, 2) . ":" . SubStr(utc, 13, 2) . "Z"
}

; ──────────────────────────────────────────────────────────────────────────────
;  Test DI seams
; ──────────────────────────────────────────────────────────────────────────────

Telemetry_SetSendHook(fn) {
    global g_TelSendHook
    g_TelSendHook := fn
}

Telemetry_SetConfigReadHook(fn) {
    global g_TelConfigReadHook
    g_TelConfigReadHook := fn
}

Telemetry_SetConfigWriteHook(fn) {
    global g_TelConfigWriteHook
    g_TelConfigWriteHook := fn
}

; Reset all module state (tests only)
Telemetry_Reset() {
    global g_TelEnabled, g_TelProjectKey, g_TelAppVersion, g_TelInstallId
    global g_TelDebug, g_TelQueue, g_TelLastFlush, g_TelFlushScheduled
    g_TelEnabled     := false
    g_TelProjectKey  := ""
    g_TelAppVersion  := "0.0.0"
    g_TelInstallId   := ""
    g_TelDebug       := false
    g_TelQueue       := []
    g_TelLastFlush   := 0
    g_TelFlushScheduled := false
    ; Note: send/config hooks are NOT reset (they're set once at test startup)
}
