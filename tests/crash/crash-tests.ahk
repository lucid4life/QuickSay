; ==============================================================================
;  T2.4 — lib/crash-reporter.ahk unit tests (headless)
;  Usage: AutoHotkey64.exe /ErrorStdOut crash-tests.ahk
;  Exit 0 = all pass, Exit 1 = failures.
;
;  Implements the 14-test list from session-T2.4. Every test is offline and
;  deterministic: the network POST is replaced by an injected send-hook, and
;  the clock / identity (username, computer name) are injected so the PII scrub
;  is exercised against KNOWN secrets regardless of the host this runs on.
;
;  The PII tests (1-7) are the security-critical ones: the grep gate (test 7)
;  proves a fully-built envelope stuffed with every secret leaks ZERO bytes.
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\crash-reporter.ahk

global gPass := 0, gFail := 0
Assert(name, cond) {
    global gPass, gFail
    if (cond)
        FileAppend("  PASS  " name "`n", "*"), gPass++
    else
        FileAppend("  FAIL  " name "`n", "*"), gFail++
}

; ── Known synthetic secrets (NEVER real) ──────────────────────────────────────
FAKE_KEY  := "gsk_ABCDEFGHIJ0123456789abcdefXYZ987654321zzzzzzzz"
FAKE_JWT  := "eyJhbGciOiJFZERTQSIsImtpZCI6InFzLTIwMjYifQ.eyJzdWIiOiJkZWFkYmVlZiIsImVtYWlsIjoiYUBiLmNvbSJ9.Zm9vYmFyc2lnbmF0dXJlZmFrZQ"
USER      := "abeek"
MACHINE   := "DESKTOP-QSTEST9"
USERPATH  := "C:\Users\" USER "\AppData\Roaming\QuickSay\config.json"
AUDIOPATH := "C:\Users\" USER "\AppData\Local\Programs\QuickSay Beta\data\audio\QS_20260527_1423.wav"

; Inject deterministic identity so scrub targets are known on any host
CrashReporterTest_SetUserName(USER)
CrashReporterTest_SetComputerName(MACHINE)

; ─── PII scrub — the security-critical cases (spec §6.4) ──────────────────────
FileAppend("PII scrub`n", "*")

; T1: Groq API key → [REDACTED_API_KEY]
s1 := CrashReporter_Scrub("HTTP 401 from Groq using key " FAKE_KEY " denied")
Assert("T1: api key redacted",       InStr(s1, "[REDACTED_API_KEY]"))
Assert("T1: api key gone",           !InStr(s1, "gsk_"))

; T2: License JWT → [REDACTED_JWT]
s2 := CrashReporter_Scrub("refresh failed for token " FAKE_JWT " (machine mismatch)")
Assert("T2: jwt redacted",           InStr(s2, "[REDACTED_JWT]"))
Assert("T2: jwt gone",               !InStr(s2, "eyJ"))

; T2b: 2-segment JWT (header.payload, signature truncated) still carries the
;      PII-bearing email claim → must redact (security review).
twoSeg := "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiJ4IiwiZW1haWwiOiJhQGIuY29tIn0"
Assert("T2b: 2-seg jwt redacted",    !InStr(CrashReporter_Scrub("clip " twoSeg " end"), "eyJ"))

; T2c: JWT wrapped at a dot boundary (newline between segments) → must redact.
wrapped := "token eyJhbGciOiJFZERTQSJ9.`neyJzdWIiOiJ4In0.`nZm9vc2ln rest"
Assert("T2c: dot-wrapped jwt redacted", !InStr(CrashReporter_Scrub(wrapped), "eyJ"))

; T3: Windows username in a path → C:\Users\[USER]\...
s3 := CrashReporter_Scrub("could not open " USERPATH)
Assert("T3: username scrubbed",      InStr(s3, "C:\Users\[USER]\"))
Assert("T3: username gone",          !InStr(s3, USER))

; T4: Audio path → filename removed, no .wav survives
s4 := CrashReporter_Scrub("ffmpeg failed writing " AUDIOPATH)
Assert("T4: audio filename stripped", !InStr(s4, ".wav"))
Assert("T4: audio QS_ name gone",     !InStr(s4, "QS_20260527"))

; T5: transcript passed as an arbitrary 'extra' is NEVER attached (allowlist)
ctx5 := Map("release", "1.9.0", "environment", "beta", "this_func", "StopAndProcess")
ctx5["transcript"]   := "my private medical diagnosis is xyz"     ; not allowlisted
ctx5["finalText"]    := "secret transcript text"                  ; not allowlisted
env5 := CrashReporter_BuildEnvelope(Map("type", "Error", "message", "boom"), ctx5)
Assert("T5: transcript not attached", !InStr(env5, "private medical") && !InStr(env5, "secret transcript"))

; T6: machine / computer name is NEVER present in a built envelope
ctx6 := Map("release", "1.9.0", "environment", "beta", "os_version", "10.0.26200",
            "line_file", USERPATH, "line_number", 42, "this_func", "Foo")
env6 := CrashReporter_BuildEnvelope(Map("type", "OSError", "message", "ran on " MACHINE), ctx6)
Assert("T6: computer name absent",    !InStr(env6, MACHINE))

; T6b: os_version is the one allowlisted string field — it MUST be scrubbed too, so
;      a machine name landing there (spec §6.4 "never machine name") cannot leak.
ctx6b := Map("release", "1.9.0", "environment", "beta", "os_version", "Windows 11 " MACHINE,
             "line_file", "C:\app\x.ahk", "line_number", 1, "this_func", "Foo")
env6b := CrashReporter_BuildEnvelope(Map("type", "Error", "message", "x"), ctx6b)
Assert("T6b: machine in os_version scrubbed", !InStr(env6b, MACHINE))

; T7: GREP GATE — envelope stuffed with EVERY secret leaks zero bytes
msg7 := "boom key=" FAKE_KEY " jwt=" FAKE_JWT " host=" MACHINE " file=" AUDIOPATH
ctx7 := Map("release", "1.9.0", "environment", "beta", "os_version", "10.0.26200",
            "hotkey_mode", "hold", "last_action", "transcribing",
            "line_file", USERPATH, "line_number", 99, "this_func", "Bar")
ctx7["transcript"] := "leak me"
env7 := CrashReporter_BuildEnvelope(Map("type", "Error", "message", msg7), ctx7)
Assert("T7 grep: no gsk_",            !RegExMatch(env7, "gsk_"))
Assert("T7 grep: no eyJ (jwt)",       !RegExMatch(env7, "eyJ"))
Assert("T7 grep: no username",        !InStr(env7, USER))
Assert("T7 grep: no .wav",            !InStr(env7, ".wav"))
Assert("T7 grep: no computer name",   !InStr(env7, MACHINE))
Assert("T7 grep: no transcript",      !InStr(env7, "leak me"))

; ─── Throttle (spec §6.5: max 5 / rolling 60 min) ─────────────────────────────
FileAppend("Throttle`n", "*")
CrashReporterTest_Reset()
CrashReporter_Configure(Map("enabled", true, "prompted", true,
    "dsn", "https://pub0key@o12345.ingest.sentry.io/678", "release", "1.9.0",
    "environment", "beta", "debug", true))
captured := []
CrashReporterTest_SetSendHook((url, body) => (captured.Push(url), 200))
T0 := 1748620800
CrashReporterTest_SetNow(T0)

sent := 0
Loop 5
    sent += CrashReporter_Send("env" A_Index) ? 1 : 0
Assert("T8: 5 reports in one hour all sent", sent = 5 && captured.Length = 5)

; T9: 6th within the same hour is dropped + drop recorded
sixth := CrashReporter_Send("env6")
Assert("T9: 6th dropped",            sixth = false && captured.Length = 5)
Assert("T9: drop was recorded",      CrashReporterTest_DropCount() = 1)

; T10: after the hour rolls, the counter resets and sending resumes
CrashReporterTest_SetNow(T0 + 3601)
seventh := CrashReporter_Send("env7")
Assert("T10: window rolled → sends again", seventh = true && captured.Length = 6)

; ─── Opt-in gate (spec §6.5: default OFF until consent) ───────────────────────
FileAppend("Opt-in gate`n", "*")

; T11: enabled=false → ReportError is a no-op (no POST attempted)
CrashReporterTest_Reset()
CrashReporter_Configure(Map("enabled", false, "prompted", true,
    "dsn", "https://pub0key@o12345.ingest.sentry.io/678", "release", "1.9.0", "environment", "beta"))
posts11 := []
CrashReporterTest_SetSendHook((url, body) => (posts11.Push(1), 200))
r11 := CrashReporter_ReportError(Map("type", "Error", "message", "x"), Map("release", "1.9.0"))
Assert("T11: opt-out → no-op",       r11 = false && posts11.Length = 0)
Assert("T11: ShouldSend false",      CrashReporter_ShouldSend() = false)

; T12: enabled=true → ReportError builds + attempts the POST
CrashReporterTest_Reset()
CrashReporter_Configure(Map("enabled", true, "prompted", true,
    "dsn", "https://pub0key@o12345.ingest.sentry.io/678", "release", "1.9.0", "environment", "beta"))
posts12 := []
CrashReporterTest_SetSendHook((url, body) => (posts12.Push(1), 200))
r12 := CrashReporter_ReportError(Map("type", "Error", "message", "x"), Map("release", "1.9.0"))
Assert("T12: opt-in → POST attempted", r12 = true && posts12.Length = 1)
Assert("T12: ShouldSend true",       CrashReporter_ShouldSend() = true)

; T13: never-prompted (prompted=false) → reporting OFF until the modal is answered
CrashReporterTest_Reset()
CrashReporter_Configure(Map("enabled", false, "prompted", false,
    "dsn", "https://pub0key@o12345.ingest.sentry.io/678", "release", "1.9.0", "environment", "beta"))
posts13 := []
CrashReporterTest_SetSendHook((url, body) => (posts13.Push(1), 200))
r13 := CrashReporter_ReportError(Map("type", "Error", "message", "x"), Map("release", "1.9.0"))
Assert("T13: not prompted → no send", r13 = false && posts13.Length = 0)

; ─── Envelope shape (spec §6.3: newline-delimited 3-line envelope) ────────────
FileAppend("Envelope shape`n", "*")
ctx14 := Map("release", "1.9.0", "environment", "beta", "os_version", "10.0.26200",
             "hotkey_mode", "tap", "last_action", "idle",
             "line_file", "C:\app\QuickSay.ahk", "line_number", 1234, "this_func", "Main")
env14 := CrashReporter_BuildEnvelope(Map("type", "ValueError", "message", "bad input"), ctx14)
lines := StrSplit(env14, "`n")
Assert("T14: at least 3 lines",      lines.Length >= 3)
h1 := JSON.Parse(lines[1])
Assert("T14: line1 has event_id",    Type(h1) = "Map" && h1.Has("event_id") && StrLen(h1["event_id"]) = 32)
h2 := JSON.Parse(lines[2])
Assert("T14: line2 type=event",      Type(h2) = "Map" && h2["type"] = "event")
ev := JSON.Parse(lines[3])
Assert("T14: line3 has exception",   Type(ev) = "Map" && ev.Has("exception"))
Assert("T14: line3 release",         ev.Has("release") && ev["release"] = "quicksay@1.9.0")
Assert("T14: line3 environment",     ev.Has("environment") && ev["environment"] = "beta")
Assert("T14: line3 level=error",     ev.Has("level") && ev["level"] = "error")

FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
