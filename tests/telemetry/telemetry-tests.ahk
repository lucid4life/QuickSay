; ==============================================================================
;  T2.7 — lib/telemetry.ahk unit tests (headless)
;  Usage: AutoHotkey64.exe /ErrorStdOut telemetry-tests.ahk
;  Exit 0 = all pass, Exit 1 = failures.
;
;  All 10 tests from session-T2.7. Fully offline: the HTTP POST is replaced
;  by an injected send-hook that captures what would have been sent. The
;  config write is replaced by an injected config-write hook so no real
;  config.json is touched.
;
;  Security-critical cases: tests 3-4 prove that dangerous values (transcript,
;  API key, email, file path, machine name, MAC) NEVER appear in a payload
;  regardless of what props a caller passes.
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\telemetry.ahk

global gPass := 0, gFail := 0
Assert(name, cond) {
    global gPass, gFail
    if (cond)
        FileAppend("  PASS  " name "`n", "*"), gPass++
    else
        FileAppend("  FAIL  " name "`n", "*"), gFail++
}

; ── Test infrastructure ────────────────────────────────────────────────────────

; Captured POST calls from the injected send-hook
global gCaptured := []

; Reset state between tests
ResetTelemetry() {
    global gCaptured
    gCaptured := []
    Telemetry_Reset()
}

; Mock config storage (key→value map)
global gTestConfig := Map()

; Named hook functions (AHK v2 fat-arrows don't support block bodies)
CapturingSendHook(url, body) {
    global gCaptured
    gCaptured.Push(body)
    return 200
}
FailingSendHook(url, body) {
    throw Error("simulated network failure")
}
ReadConfigHook() {
    global gTestConfig
    return gTestConfig
}
WriteConfigHook(key, val) {
    global gTestConfig
    gTestConfig[key] := val
    return true
}

; Inject the send hook so no real HTTP is made
Telemetry_SetSendHook(CapturingSendHook)

; Inject config read/write hooks so no real config.json is touched
Telemetry_SetConfigReadHook(ReadConfigHook)
Telemetry_SetConfigWriteHook(WriteConfigHook)

; ── Test 1: Telemetry OFF by default — EmitEvent makes no HTTP call ───────────
FileAppend("Off-by-default`n", "*")

ResetTelemetry()
; Default state: telemetryEnabled not set in config → off
Telemetry_Configure(Map("enabled", false, "projectKey", "test_key", "appVersion", "1.9.0"))
EmitEvent("app_started", Map("app_version", "1.9.0"))
Telemetry_FlushNow()   ; force-flush for test isolation
Assert("T1: OFF by default — no HTTP call", gCaptured.Length = 0)

; ── Test 2: Telemetry ON — EmitEvent builds + would POST ─────────────────────
FileAppend("On-fires`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "00000000-0000-0000-0000-000000000001"))
EmitEvent("app_started", Map("app_version", "1.9.0", "os_build_bucket", "11",
    "install_id", "00000000-0000-0000-0000-000000000001"))
Telemetry_FlushNow()
Assert("T2: ON — one HTTP call fired", gCaptured.Length = 1)
if (gCaptured.Length >= 1) {
    parsed := JSON.Parse(gCaptured[1])
    Assert("T2: api_key present",   parsed.Has("api_key") && parsed["api_key"] = "test_key")
    Assert("T2: batch array present", parsed.Has("batch") && Type(parsed["batch"]) = "Array"
        && parsed["batch"].Length >= 1)
    if (parsed.Has("batch") && parsed["batch"].Length >= 1) {
        evt0 := parsed["batch"][1]
        Assert("T2: event name correct", evt0.Has("event") && evt0["event"] = "app_started")
        Assert("T2: distinct_id present", evt0.Has("properties")
            && evt0["properties"].Has("distinct_id"))
    }
}

; ── Test 3: PII scrub — dangerous values are NEVER in the payload ─────────────
FileAppend("PII scrub`n", "*")

ResetTelemetry()
FAKE_KEY      := "gsk_ABCDE12345FGHIJ67890klmnopqrstuvwxyz0000test"
FAKE_JWT      := "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiJ4IiwiZW1haWwiOiJhQGIuY29tIn0.ZmFrZXNpZ25hdHVyZQ"
FAKE_EMAIL    := "buyer@example.com"
FAKE_PATH     := "C:\Users\secretuser\AppData\Roaming\QuickSay\config.json"
FAKE_MACHINE  := "DESKTOP-SECRET99"
FAKE_MAC      := "AA:BB:CC:DD:EE:FF"
FAKE_TRANSCRIPT := "my confidential medical diagnosis is xyz"

Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "aaaaaaaa-0000-0000-0000-000000000002"))
; Feed every dangerous value as a tempting prop
EmitEvent("app_started", Map(
    "groqApiKey",   FAKE_KEY,
    "licenseJwt",   FAKE_JWT,
    "email",        FAKE_EMAIL,
    "filePath",     FAKE_PATH,
    "machineName",  FAKE_MACHINE,
    "macAddress",   FAKE_MAC,
    "transcript",   FAKE_TRANSCRIPT,
    "rawText",      FAKE_TRANSCRIPT,
    "app_version",  "1.9.0"
))
Telemetry_FlushNow()
Assert("T3: at least one event flushed", gCaptured.Length >= 1)
if (gCaptured.Length >= 1) {
    raw := gCaptured[1]
    Assert("T3: API key not in payload",    !InStr(raw, "gsk_"))
    Assert("T3: JWT not in payload",        !InStr(raw, "eyJ"))
    Assert("T3: email not in payload",      !InStr(raw, "buyer@"))
    Assert("T3: file path not in payload",  !InStr(raw, "secretuser"))
    Assert("T3: machine name not in payload", !InStr(raw, "SECRET99"))
    Assert("T3: MAC not in payload",        !InStr(raw, "AA:BB:CC:DD:EE:FF"))
    Assert("T3: transcript not in payload", !InStr(raw, "medical diagnosis"))
}

; ── Test 3b: PII scrub under INNOCENT key names (HIGH-2 regression) ──────────
; The key-name denylist is the primary defense; ValueIsDangerous is second-line.
; Previously, anchored ^ caused bypass when a secret wasn't at the string start.
; This test feeds dangerous values under key names NOT in TELEMETRY_DENIED_KEYS.
FileAppend("PII scrub under innocent keys`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "a1b2c3d4-0000-0000-0000-000000000099"))
EmitEvent("app_started", Map(
    ; Dangerous values under INNOCENT key names (not in denied list)
    "error_detail",   "auth failed using key gsk_ABCDE12345FGHIJ67890klmnop0test123",
    "debug_msg",      "token: eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiJ4In0.ZmFrZXNpZ25h",
    "contact",        "buyer@example.com",
    "app_version",    "1.9.0"
))
Telemetry_FlushNow()
if (gCaptured.Length >= 1) {
    raw3b := gCaptured[1]
    Assert("T3b: embedded API key blocked (unanchored scrub)", !InStr(raw3b, "gsk_"))
    Assert("T3b: embedded JWT blocked (unanchored scrub)",     !InStr(raw3b, "eyJ"))
    Assert("T3b: email blocked (email matcher)",               !InStr(raw3b, "buyer@"))
}

; ── Test 4: Event allowlist — unlisted event is a no-op ──────────────────────
FileAppend("Allowlist`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "bbbbbbbb-0000-0000-0000-000000000003"))
EmitEvent("some_unlisted_secret_event", Map("foo", "bar"))
EmitEvent("definitely_not_allowed_event")
Telemetry_FlushNow()
Assert("T4: unlisted events produce no HTTP call", gCaptured.Length = 0)

; ── Test 5: recording_completed sends a duration bucket, not raw ms ───────────
FileAppend("Duration bucket`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "cccccccc-0000-0000-0000-000000000004"))
; Send a raw duration of 7200ms — should appear as bucket "5-15s", not "7200"
EmitEvent("recording_completed", Map(
    "duration_ms",          7200,
    "llm_cleanup_enabled",  true,
    "mode",                 "Standard"
))
Telemetry_FlushNow()
Assert("T5: one event fired", gCaptured.Length = 1)
if (gCaptured.Length >= 1) {
    parsed5 := JSON.Parse(gCaptured[1])
    Assert("T5: batch present", parsed5.Has("batch") && parsed5["batch"].Length >= 1)
    if (parsed5.Has("batch") && parsed5["batch"].Length >= 1) {
        p := parsed5["batch"][1]["properties"]
        Assert("T5: duration_bucket present", p.Has("duration_bucket"))
        Assert("T5: bucket is '5-15s'", p["duration_bucket"] = "5-15s")
        Assert("T5: raw ms not in payload", !InStr(gCaptured[1], "7200"))
        Assert("T5: duration_ms key absent", !p.Has("duration_ms"))
    }
}

; ── Test 6: settings_changed sends key name, NOT value for groqApiKey ─────────
FileAppend("settings_changed safe`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "dddddddd-0000-0000-0000-000000000005"))
; API key change — only key name should appear, never the value
EmitEvent("settings_changed", Map("changed_keys", ["groqApiKey"]))
Telemetry_FlushNow()
; groqApiKey is NOT in the allowlist → event should be silently dropped
Assert("T6: groqApiKey not in allowlist → no event fired", gCaptured.Length = 0)

; Now emit with an allowlisted key
ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "dddddddd-0000-0000-0000-000000000005"))
EmitEvent("settings_changed", Map("changed_keys", ["soundTheme"]))
Telemetry_FlushNow()
Assert("T6b: allowlisted key fires event", gCaptured.Length = 1)
if (gCaptured.Length >= 1) {
    parsed6 := JSON.Parse(gCaptured[1])
    raw := gCaptured[1]
    Assert("T6b: no API key value leaked", !InStr(raw, "gsk_"))
    if (parsed6.Has("batch") && parsed6["batch"].Length >= 1) {
        p := parsed6["batch"][1]["properties"]
        Assert("T6b: changed_keys present", p.Has("changed_keys"))
    }
}

; ── Test 7: Anonymous install-id — generated on first opt-in, stable while on ─
FileAppend("Install ID`n", "*")

gTestConfig := Map()  ; fresh config
ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key", "appVersion", "1.9.0"))
; No install ID in config yet → should be generated
id1 := Telemetry_GetOrCreateInstallId()
Assert("T7: install ID generated", id1 != "")
Assert("T7: install ID is UUID-shaped", StrLen(id1) = 36 && InStr(id1, "-"))
; Second call with same config → stable
id2 := Telemetry_GetOrCreateInstallId()
Assert("T7: install ID stable while enabled", id1 = id2)

; ── Test 8: Install-id != trialMachineId, not derived from hardware ───────────
FileAppend("Install ID isolation`n", "*")

gTestConfig := Map()
ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key", "appVersion", "1.9.0"))
id := Telemetry_GetOrCreateInstallId()
; The install ID must not be the trialMachineId (which is SHA256 of MAC+ProductID)
; We can't know the exact trialMachineId here, but we can assert it's a proper UUID
; (36 chars, 4 hyphens at positions 9, 14, 19, 24) and not a 32-char hex string
Assert("T8: not a 32-hex (not trialMachineId form)", StrLen(id) != 32)
Assert("T8: UUID form (36 chars)", StrLen(id) = 36)
hyphens := 0
loop Parse, id
    if (A_LoopField = "-")
        hyphens++
Assert("T8: has 4 hyphens (UUID form)", hyphens = 4)

; ── Test 9: Throttle/batch — rapid events flush as a batch, not one POST each ─
FileAppend("Batch/throttle`n", "*")

ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "eeeeeeee-0000-0000-0000-000000000006"))
; Emit 5 events rapidly without explicit flush
EmitEvent("app_started",          Map("app_version", "1.9.0", "os_build_bucket", "11", "install_id", "x"))
EmitEvent("update_check",         Map("current_version", "1.9.0", "update_available", false))
EmitEvent("recording_completed",  Map("duration_ms", 3000, "llm_cleanup_enabled", false, "mode", "Standard"))
EmitEvent("recording_completed",  Map("duration_ms", 12000, "llm_cleanup_enabled", true, "mode", "Email"))
EmitEvent("recording_completed",  Map("duration_ms", 90000, "llm_cleanup_enabled", false, "mode", "Code"))
; No explicit flush yet — events should be queued, not sent one-by-one
; (queue-based: sends happen only on FlushNow or timer)
Assert("T9: no immediate HTTP call on each emit (queued)", gCaptured.Length = 0)
; Now flush — all 5 events should come out as ONE batch POST
Telemetry_FlushNow()
Assert("T9: batch = exactly one POST", gCaptured.Length = 1)
if (gCaptured.Length >= 1) {
    parsed := JSON.Parse(gCaptured[1])
    ; PostHog batch endpoint uses "batch" array
    Assert("T9: payload has batch array", parsed.Has("batch") && Type(parsed["batch"]) = "Array")
    Assert("T9: batch contains 5 events", parsed["batch"].Length = 5)
}

; ── Test 10: Network failure is swallowed — telemetry never breaks recording ──
FileAppend("Failure safety`n", "*")

ResetTelemetry()
; Inject a failing send hook
Telemetry_SetSendHook(FailingSendHook)
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key",
    "appVersion", "1.9.0", "installId", "ffffffff-0000-0000-0000-000000000007"))
threwException := false
try {
    EmitEvent("app_started", Map("app_version", "1.9.0", "os_build_bucket", "11", "install_id", "x"))
    Telemetry_FlushNow()
} catch {
    threwException := true
}
Assert("T10: network failure does NOT propagate an exception", !threwException)

; Restore the capturing hook for subsequent tests
Telemetry_SetSendHook(CapturingSendHook)

; ── Test 11: Opt-out regenerates install ID (HIGH-1 regression) ──────────────
; telemetry-events.md promises: regenerated on off→on so opting out breaks timeline.
FileAppend("Opt-out regenerates ID`n", "*")

gTestConfig := Map()
ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key", "appVersion", "1.9.0"))
; Get the first install ID
idBefore := Telemetry_GetOrCreateInstallId()
Assert("T11: first ID generated",  idBefore != "")
; Simulate opt-out: call RegenerateInstallId (equivalent to user disabling telemetry)
Telemetry_RegenerateInstallId()
Assert("T11: in-memory ID cleared after opt-out",  g_TelInstallId = "")
; Re-enable and get a new ID
ResetTelemetry()
Telemetry_Configure(Map("enabled", true, "projectKey", "test_key", "appVersion", "1.9.0"))
idAfter := Telemetry_GetOrCreateInstallId()
Assert("T11: new ID generated after re-enable",  idAfter != "")
Assert("T11: new ID differs from old (timeline break)",  idBefore != idAfter)

; ── Final tally ───────────────────────────────────────────────────────────────
FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
