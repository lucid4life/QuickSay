; ==============================================================================
;  lib/crash-reporter.ahk — Opt-in crash/error reporting via Sentry envelope POST
;  (T2.4). Spec: docs/audit-campaign/specs/T2-production-systems-design.md §6.
;
;  QuickSay has no native Sentry SDK. On an unhandled AHK error this module builds
;  a Sentry "envelope" (newline-delimited JSON) and POSTs it straight to the Sentry
;  ingest endpoint. It is:
;    • opt-in        — nothing is ever sent before the user answers the first-run
;                      modal (crashReportingPrompted=false → hard no-op; default OFF).
;    • PII-scrubbed  — ALLOWLIST, not blocklist: the envelope carries ONLY the
;                      fields in §6.4. A regex Scrub() is a second line of defense
;                      over the two free-text fields (exception.value, line_file).
;                      It NEVER carries: the Groq key, the license JWT, transcript
;                      text, audio paths, the Windows username, or the machine name.
;    • throttled     — max 5 sends per rolling 60 minutes; excess dropped + logged.
;    • crash-safe    — a bug inside the reporter must NEVER mask the user's real
;                      error: the OnError handler is fully try-wrapped and returns 0
;                      so AHK's default error handling still proceeds.
;
;  Public surface (also the unit-test contract — tests/crash/crash-tests.ahk):
;    CrashReporter_Install()                 install the global OnError handler
;    CrashReporter_Configure(optsMap)        set enabled/prompted/dsn/release/env/debug
;    CrashReporter_Scrub(text)        -> str the PII scrubber (pure)
;    CrashReporter_BuildEnvelope(err,ctx)->str the 3-line envelope (allowlist only)
;    CrashReporter_ShouldSend()       -> bool opt-in check (enabled AND prompted)
;    CrashReporter_Send(envelope)     -> bool POST honoring opt-in + throttle
;    CrashReporter_ReportError(err,ctx)->bool build + send (the report entry point)
;    CrashReporter_IngestUrl()        -> str  ingest URL derived from the DSN
;
;  Design note: this module reads NO global app state on its hot paths — all config
;  is injected via Configure() (the app calls it after LoadConfig and on reload).
;  That keeps every function above unit-testable offline with an injected send-hook.
; ==============================================================================
#Requires AutoHotkey v2.0

; ── Compiled constants (set at M.1/M.3 — see spec §6.2 / §8.3) ────────────────
; The PUBLIC Sentry DSN only (never the sentry_secret). Standard DSN form:
;   https://<publicKey>@o<ORG>.ingest.sentry.io/<PROJECT>
; Empty by default → crash reporting builds nothing and sends nothing until the
; DSN is baked in. M.1 sets the staging/project DSN; M.3 confirms it for prod.
global SENTRY_DSN_PUBLIC := ""
; Release channel tag on every event. M.3 flips this to "production".
global SENTRY_ENVIRONMENT := "beta"

; ── Module state (injected; never read from global Config directly) ───────────
global g_CrashCfg := Map("enabled", false, "prompted", false, "dsn", "",
    "release", "0.0.0", "environment", "beta", "debug", false, "debugFile", "")
global g_CrashRing   := []     ; unix timestamps of allowed sends (rolling 60-min window)
global g_CrashDrops  := 0      ; count of throttle drops (introspection)
global g_CrashInstalled := false

; Test/DI seams (default to real host values when unset)
global g_CrashNow      := ""   ; clock override (unix seconds)
global g_CrashSendHook := ""   ; fn(url, body) -> http status; replaces the network POST
global g_CrashUser     := ""   ; identity override for the scrub (default A_UserName)
global g_CrashMachine  := ""   ; identity override for the scrub (default A_ComputerName)

; ──────────────────────────────────────────────────────────────────────────────
;  Configuration
; ──────────────────────────────────────────────────────────────────────────────
CrashReporter_Configure(opts) {
    global g_CrashCfg
    if (Type(opts) != "Map")
        return
    for k in ["enabled", "prompted", "dsn", "release", "environment", "debug", "debugFile"]
        if (opts.Has(k))
            g_CrashCfg[k] := opts[k]
}

; ──────────────────────────────────────────────────────────────────────────────
;  PII scrub (security-critical) — spec §6.4.
;  Second line of defense over free text; the allowlist in BuildEnvelope is the
;  load-bearing control (F12). Applied to EVERY string field before it enters the wire.
;
;  Accepted residuals (security review 2026-06-02; backstop-only, allowlist is the
;  real control, and exception.value is a single error string — not a multi-line log):
;    • A `gsk_` key split by literal whitespace/newline mid-token is not stitched back
;      (real Groq key-echo errors are contiguous; a whitespace-tolerant key rule would
;      greedily eat following diagnostic words — a worse tradeoff than the rare split).
;    • A JWT split by a newline INSIDE a base64 segment (not at a dot boundary) is not
;      rejoined. Dot-boundary wraps and 2-segment tokens ARE handled (rule 1).
;    • The username/computer-name backstops over-redact when the name is a common
;      substring (privacy-favoring: over-redaction is safe, never a leak).
; ──────────────────────────────────────────────────────────────────────────────
CrashReporter_Scrub(text) {
    if (!IsSet(text) || Type(text) != "String" || text = "")
        return (IsSet(text) ? text : "")
    out := text

    ; 1) License JWT. Anchor on the HEADER: a JWT header is compact base64url(JSON)
    ;    beginning `{"alg"…` → it base64url-encodes to "eyJ" (the only reliable
    ;    anchor — the PAYLOAD does NOT always start "eyJ": a pretty-printed payload
    ;    `{ "…"}` encodes to "eyA"/"ewo", security review). So: header starts "eyJ",
    ;    then 1-OR-2 more base64url segments (a truncated 2-segment token still
    ;    carries the PII-bearing `email` claim), whitespace tolerated AROUND the dots
    ;    (a token wrapped at a segment boundary). Run before the key rule. Privacy-
    ;    favoring: an `eyJ…`-prefixed identifier followed by `.token` may be
    ;    over-redacted — acceptable for a backstop. Residual (accepted, documented):
    ;    a newline INSIDE a base64 segment is not stitched back together.
    out := RegExReplace(out, "eyJ[A-Za-z0-9_\-]+\s*\.\s*[A-Za-z0-9_\-]+(?:\s*\.\s*[A-Za-z0-9_\-]+)?", "[REDACTED_JWT]")

    ; 2) Groq API key
    out := RegExReplace(out, "gsk_[A-Za-z0-9]+", "[REDACTED_API_KEY]")

    ; 3) Audio paths / any stray .wav filename → drop the filename entirely.
    ;    (Matches the filename token before '.wav'; stops at a path separator/space.)
    out := RegExReplace(out, "i)[^\\/\s`"]*\.wav", "[AUDIO_FILE]")

    ; 4) Windows username inside a path: drive:\Users\<name>\ and UNC \\host\..\Users\<name>\
    out := RegExReplace(out, "i)((?:[A-Za-z]:|\\\\[^\\]+)\\Users\\)[^\\/`"]+", "${1}[USER]")

    ; 5) Unexpanded %USERPROFILE%
    out := RegExReplace(out, "i)%USERPROFILE%", "C:\Users\[USER]")

    ; 6) Identity backstops — the literal username / computer name anywhere in free
    ;    text (case-insensitive). Guarded by a min length so a 1-2 char name can't
    ;    nuke unrelated text. Privacy-favoring: over-scrubbing is safe.
    u := _CrashUser()
    if (StrLen(u) >= 3)
        out := StrReplace(out, u, "[USER]")
    m := _CrashMachine()
    if (StrLen(m) >= 3)
        out := StrReplace(out, m, "[MACHINE]")

    return out
}

; ──────────────────────────────────────────────────────────────────────────────
;  Envelope builder — spec §6.3. ALLOWLIST: only the §6.4 fields are attached.
;  Any non-allowlisted key in `ctx` (a transcript, a path, etc.) is simply ignored.
; ──────────────────────────────────────────────────────────────────────────────
CrashReporter_BuildEnvelope(errMap, ctx) {
    eid := _CrashEventId()
    now := _CrashNowUnix()

    line1 := JSON.Stringify(Map("event_id", eid, "sent_at", _CrashUnixToIso(now)))
    line2 := JSON.Stringify(Map("type", "event", "content_type", "application/json"))

    errType := CrashReporter_Scrub(_CrashCtxStr(errMap, "type", "Error"))
    errMsg  := CrashReporter_Scrub(_CrashCtxStr(errMap, "message", ""))

    ev := Map()
    ev["event_id"]    := eid
    ev["timestamp"]   := now
    ev["level"]       := "error"
    ev["platform"]    := "native"
    ev["release"]     := "quicksay@" _CrashCtxStr(ctx, "release", "0.0.0")
    ev["environment"] := _CrashCtxStr(ctx, "environment", "beta")
    ev["exception"]   := Map("values", [ Map("type", errType, "value", errMsg) ])
    ev["tags"]        := Map(
        "hotkey_mode", _CrashCtxStr(ctx, "hotkey_mode", "hold"),
        "last_action", _CrashCtxStr(ctx, "last_action", "idle"))
    ; os_version is scrubbed too: spec §6.4 says contexts.os is "generic build, NEVER
    ; the machine name". Today the caller passes A_OSVersion (a build like 10.0.26200),
    ; but scrubbing here makes the "never machine name" clause enforced in code, not just
    ; by the input happening to be safe (security review P1).
    ev["contexts"]    := Map("os", Map("name", "Windows", "version", CrashReporter_Scrub(_CrashCtxStr(ctx, "os_version", ""))))
    ev["extra"]       := Map(
        "line_file",   CrashReporter_Scrub(_CrashCtxStr(ctx, "line_file", "")),
        "line_number", _CrashCtxInt(ctx, "line_number", 0),
        "this_func",   CrashReporter_Scrub(_CrashCtxStr(ctx, "this_func", "")))

    return line1 "`n" line2 "`n" JSON.Stringify(ev)
}

; ──────────────────────────────────────────────────────────────────────────────
;  Opt-in + throttle + send
; ──────────────────────────────────────────────────────────────────────────────
CrashReporter_ShouldSend() {
    global g_CrashCfg
    ; Hard no-op until the user has answered the modal (prompted) AND opted in.
    return (g_CrashCfg["enabled"] = true) && (g_CrashCfg["prompted"] = true)
}

CrashReporter_Send(envelope) {
    global g_CrashSendHook, g_CrashDrops
    if (!CrashReporter_ShouldSend())
        return false

    url := CrashReporter_IngestUrl()
    if (url = "" && g_CrashSendHook = "")
        return false                       ; no DSN configured + no hook → nothing to send

    if (!_CrashThrottleAllow()) {
        g_CrashDrops += 1
        _CrashDebug("crash report dropped (throttle: max 5 per 60 min)")
        return false
    }

    if (g_CrashSendHook != "") {
        status := g_CrashSendHook.Call(url, envelope)
        return (status >= 200 && status < 300)
    }
    return _CrashHttpPost(url, envelope)
}

CrashReporter_ReportError(errMap, ctx) {
    ; Entry point used by the OnError adapter and by tests. Crash-safe.
    if (!CrashReporter_ShouldSend())
        return false
    try {
        return CrashReporter_Send(CrashReporter_BuildEnvelope(errMap, ctx))
    } catch as e {
        _CrashDebug("crash report build/send failed: " e.Message)
        return false
    }
}

CrashReporter_IngestUrl() {
    global g_CrashCfg
    dsn := g_CrashCfg["dsn"]
    if (Type(dsn) != "String" || dsn = "")
        return ""
    ; Standard DSN form: https://<publicKey>@<host>/<projectId>
    if !RegExMatch(dsn, "^https://([^@]+)@([^/]+)/(.+)$", &m)
        return ""
    return "https://" m[2] "/api/" m[3] "/envelope/?sentry_key=" m[1] "&sentry_version=7"
}

; ──────────────────────────────────────────────────────────────────────────────
;  Global handler install — spec §6.7. Installed early in QuickSay.ahk startup.
; ──────────────────────────────────────────────────────────────────────────────
CrashReporter_Install() {
    global g_CrashInstalled
    if (g_CrashInstalled)
        return
    OnError(_CrashOnError)
    g_CrashInstalled := true
}

_CrashOnError(thrown, mode) {
    ; CRASH-SAFE: a bug in the reporter must never mask or replace the user's real
    ; error. Everything is try-wrapped, and we return 0 so AHK's DEFAULT error
    ; handling still runs (the user still sees / the app still does what it would).
    try {
        errMap := Map()
        errMap["type"]    := IsObject(thrown) ? Type(thrown) : "Error"
        errMap["message"] := IsObject(thrown)
            ? (thrown.HasProp("Message") ? String(thrown.Message) : String(thrown))
            : String(thrown)
        CrashReporter_ReportError(errMap, _CrashGatherContext(thrown))
    }
    return 0   ; 0/"" → do NOT suppress; default handling proceeds
}

_CrashGatherContext(thrown) {
    global g_CrashCfg
    ctx := Map()
    ctx["release"]     := g_CrashCfg["release"]
    ctx["environment"] := g_CrashCfg["environment"]
    ctx["os_version"]  := A_OSVersion                 ; generic build, NEVER the machine name
    ctx["hotkey_mode"] := _CrashHotkeyMode()
    ctx["last_action"] := _CrashLastAction()
    ctx["this_func"]   := (IsObject(thrown) && thrown.HasProp("What")) ? String(thrown.What) : A_ThisFunc
    ctx["line_file"]   := (IsObject(thrown) && thrown.HasProp("File")) ? String(thrown.File) : A_LineFile
    ctx["line_number"] := (IsObject(thrown) && thrown.HasProp("Line")) ? Integer(thrown.Line) : 0
    return ctx
}

; last_action derived from already-audited app signals (spec §6.7) — no new hot-path
; instrumentation, no content. Coarse enum only.
_CrashLastAction() {
    global isRecording, isProcessing
    if (IsSet(isRecording) && isRecording)
        return "recording"
    if (IsSet(isProcessing) && isProcessing)
        return "transcribing"
    return "idle"
}

_CrashHotkeyMode() {
    global Config
    if (IsSet(Config) && Type(Config) = "Map") {
        if (Config.Has("hotkey_mode") && Config["hotkey_mode"] != "")
            return Config["hotkey_mode"]
        if (Config.Has("hotkeyMode") && Config["hotkeyMode"] != "")
            return Config["hotkeyMode"]
    }
    return "hold"
}

; ──────────────────────────────────────────────────────────────────────────────
;  Internals
; ──────────────────────────────────────────────────────────────────────────────
_CrashThrottleAllow() {
    global g_CrashRing
    now := _CrashNowUnix()
    fresh := []
    for ts in g_CrashRing
        if (now - ts < 3600)
            fresh.Push(ts)
    g_CrashRing := fresh
    if (fresh.Length >= 5)
        return false
    g_CrashRing.Push(now)
    return true
}

_CrashHttpPost(url, body) {
    ; Raw text-body POST. Fast timeouts (≤5 s) and fire-and-forget — never blocks
    ; the dictation hot path. (lib/http.ahk only does multipart; this is the one
    ; raw-body case, kept self-contained so the module stays unit-testable.)
    try {
        st := ComObject("ADODB.Stream")
        st.Type := 2, st.Charset := "utf-8", st.Open()
        st.WriteText(body)
        st.Position := 0, st.Type := 1, st.Position := 3   ; skip UTF-8 BOM
        bytes := st.Read()
        st.Close()

        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(3000, 3000, 5000, 5000)
        http.Open("POST", url, false)
        http.SetRequestHeader("Content-Type", "application/x-sentry-envelope")
        http.Send(bytes)
        return (http.Status >= 200 && http.Status < 300)
    } catch {
        return false
    }
}

_CrashDebug(msg) {
    global g_CrashCfg
    if (!g_CrashCfg["debug"])
        return
    line := "[" A_Now "] [crash-reporter] " msg
    if (g_CrashCfg["debugFile"] != "") {
        try FileAppend(line "`n", g_CrashCfg["debugFile"])
    } else {
        OutputDebug(line)
    }
}

_CrashEventId() {
    s := ""
    Loop 32
        s .= Format("{:x}", Random(0, 15))
    return s
}

_CrashNowUnix() {
    global g_CrashNow
    if (g_CrashNow != "")
        return g_CrashNow
    return DateDiff(A_NowUTC, "19700101000000", "Seconds")
}

_CrashUnixToIso(u) {
    t := DateAdd("19700101000000", u, "Seconds")     ; UTC
    return FormatTime(t, "yyyy") "-" FormatTime(t, "MM") "-" FormatTime(t, "dd")
        . "T" FormatTime(t, "HH") ":" FormatTime(t, "mm") ":" FormatTime(t, "ss") "Z"
}

_CrashUser() {
    global g_CrashUser
    return (g_CrashUser != "") ? g_CrashUser : A_UserName
}
_CrashMachine() {
    global g_CrashMachine
    return (g_CrashMachine != "") ? g_CrashMachine : A_ComputerName
}

_CrashCtxStr(m, key, def) {
    if (Type(m) = "Map" && m.Has(key) && m[key] != "")
        return String(m[key])
    return def
}
_CrashCtxInt(m, key, def) {
    if (Type(m) = "Map" && m.Has(key) && IsInteger(m[key]))
        return Integer(m[key])
    return def
}

; ──────────────────────────────────────────────────────────────────────────────
;  Test seams (no-ops in production; used by tests/crash/crash-tests.ahk)
; ──────────────────────────────────────────────────────────────────────────────
CrashReporterTest_Reset() {
    global g_CrashRing, g_CrashDrops, g_CrashSendHook, g_CrashNow, g_CrashCfg
    g_CrashRing := []
    g_CrashDrops := 0
    g_CrashSendHook := ""
    g_CrashNow := ""
    g_CrashCfg := Map("enabled", false, "prompted", false, "dsn", "",
        "release", "0.0.0", "environment", "beta", "debug", false, "debugFile", "")
}
CrashReporterTest_SetNow(u) {
    global g_CrashNow
    g_CrashNow := u
}
CrashReporterTest_SetSendHook(fn) {
    global g_CrashSendHook
    g_CrashSendHook := fn
}
CrashReporterTest_SetUserName(n) {
    global g_CrashUser
    g_CrashUser := n
}
CrashReporterTest_SetComputerName(n) {
    global g_CrashMachine
    g_CrashMachine := n
}
CrashReporterTest_DropCount() {
    global g_CrashDrops
    return g_CrashDrops
}
