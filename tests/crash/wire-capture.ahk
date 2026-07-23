; ==============================================================================
;  T2.4 — PII wire-capture (Phase 6, gate 2)
;  Builds the ACTUAL envelope bytes for a synthetic error stuffed with EVERY
;  secret, and writes them to a file so an external grep can prove zero leakage.
;  Usage: AutoHotkey64.exe /ErrorStdOut wire-capture.ahk <outfile>
;  (No network. The secrets below are fake — never real keys/tokens.)
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\crash-reporter.ahk

out := A_Args.Length >= 1 ? A_Args[1] : (A_ScriptDir "\captured-envelope.txt")

FAKE_KEY  := "gsk_ABCDEFGHIJ0123456789abcdefXYZ987654321zzzzzzzz"
FAKE_JWT  := "eyJhbGciOiJFZERTQSIsImtpZCI6InFzLTIwMjYifQ.eyJzdWIiOiJkZWFkYmVlZiIsImVtYWlsIjoiYUBiLmNvbSJ9.Zm9vYmFyc2lnbmF0dXJlZmFrZQ"
USER      := "abeek"
MACHINE   := "DESKTOP-QSTEST9"
USERPATH  := "C:\Users\" USER "\AppData\Roaming\QuickSay\config.json"
AUDIOPATH := "C:\Users\" USER "\AppData\Local\Programs\QuickSay Beta\data\audio\QS_20260527_1423.wav"

CrashReporterTest_SetUserName(USER)
CrashReporterTest_SetComputerName(MACHINE)

msg := "Unhandled: key=" FAKE_KEY " jwt=" FAKE_JWT " host=" MACHINE " wrote " AUDIOPATH
; os_version deliberately carries the machine name here to prove the scrub strips it
; on the wire (security review: os_version is the one allowlisted free-ish string field).
ctx := Map("release", "1.9.0", "environment", "beta", "os_version", "Windows 11 " MACHINE,
           "hotkey_mode", "hold", "last_action", "transcribing",
           "line_file", USERPATH, "line_number", 207, "this_func", "StopAndProcess")
ctx["transcript"]  := "PRIVATE TRANSCRIPT: my bank PIN is 1234"
ctx["finalText"]   := "PRIVATE TRANSCRIPT 2"

env := CrashReporter_BuildEnvelope(Map("type", "OSError", "message", msg), ctx)

if FileExist(out)
    FileDelete(out)
FileAppend(env, out, "UTF-8-RAW")
FileAppend("`n--- captured " StrLen(env) " bytes ---`n", "*")
ExitApp(0)
