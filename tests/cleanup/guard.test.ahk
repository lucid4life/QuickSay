;==============================================================================
; E.2 — cleanup sanity guard + artifact filter unit tests (AHK-native driver)
;
; Exercises the REAL functions in lib/cleanup-guard.ahk and
; lib/artifact-filter.ahk (no copies, no drift).
; Driven by run-guard-tests.ps1:
;   A_Args[1] = results file (TSV: name<TAB>PASS|FAIL[<TAB>detail])
;
; Run standalone:
;   AutoHotkey64.exe guard.test.ahk results.txt
;==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%\..\..\lib\cleanup-guard.ahk
#Include %A_ScriptDir%\..\..\lib\artifact-filter.ahk

global ResultFile := A_Args.Length >= 1 ? A_Args[1] : A_ScriptDir . "\results.txt"

if FileExist(ResultFile)
    FileDelete(ResultFile)

Record(name, ok, detail := "") {
    global ResultFile
    line := name . "`t" . (ok ? "PASS" : "FAIL")
    if (detail != "")
        line .= "`t" . detail
    FileAppend(line . "`n", ResultFile, "UTF-8")
}

T(name, fn) {
    try {
        r := fn()
        Record(name, r[1], r.Length > 1 ? r[2] : "")
    } catch as e {
        Record(name, false, "EXCEPTION: " . e.Message)
    }
}

; Expect the guard to FAIL with a specific reason
ExpectTrip(raw, cleaned, reason) {
    g := CleanupSanityCheck(raw, cleaned)
    if (g["ok"])
        return [false, "expected trip '" . reason . "' but guard passed"]
    if (g["reason"] != reason)
        return [false, "expected '" . reason . "' got '" . g["reason"] . "'"]
    return [true]
}

; Expect the guard to PASS
ExpectOk(raw, cleaned) {
    g := CleanupSanityCheck(raw, cleaned)
    return g["ok"] ? [true] : [false, "guard tripped unexpectedly: " . g["reason"]]
}

; ---------------------------------------------------------------------------
; CleanupSanityCheck
; ---------------------------------------------------------------------------
T("guard-01 empty output trips", () =>
    ExpectTrip("say something useful here", "", "empty-output"))

T("guard-02 meta-response trips", () =>
    ExpectTrip("testing one two three", "You have not provided the raw speech transcript.", "meta-response"))

T("guard-03 meta-response variant trips", () =>
    ExpectTrip("hello hello", "No transcript was provided. Please provide the transcript.", "meta-response"))

T("guard-04 answer-lead trips", () =>
    ExpectTrip("should I use react or vue for this project?", "Yes, you should use React for this project.", "answer-lead"))

T("guard-05 answer-lead allowed when speaker said it", () =>
    ExpectOk("yes, let's go with the second option for now.", "Yes, let's go with the second option for now."))

T("guard-06 injected trailing ack trips", () =>
    ExpectTrip("I think we are ready for the launch tomorrow morning.", "I think we are ready for the launch tomorrow morning. Yes.", "injected-trailing-ack"))

T("guard-07 trailing ack allowed when raw ends with it", () =>
    ExpectOk("we are ready for the launch tomorrow. okay.", "We are ready for the launch tomorrow. Okay."))

T("guard-08 question lost trips", () =>
    ExpectTrip("can you check whether the deploy finished?", "Check whether the deploy finished.", "question-lost"))

T("guard-09 question kept passes", () =>
    ExpectOk("can you check whether the deploy finished?", "Can you check whether the deploy finished?"))

T("guard-10 length explosion trips", () => ExpectTrip(
    "how do I publish an app to the microsoft store?",
    "How do I publish an app to the Microsoft Store? To publish an app to the Microsoft Store you first need to register a developer account which costs a one time fee of nineteen dollars for individuals. Then you package your application using MSIX and submit it through Partner Center where it goes through certification review before appearing in the store listing.",
    "length-explosion"))

T("guard-11 email scaffold ratio passes", () => ExpectOk(
    "just wanted to follow up on the invoice from last week can you send it over when you get a chance",
    "Hi,`n`nJust wanted to follow up on the invoice from last week. Can you send it over when you get a chance?`n`nBest regards,"))

T("guard-12 over-deletion trips", () => ExpectTrip(
    "please set up the tunnels on my linux computer and let me know if I need to create an account with tailscale or fast api before you start",
    "Please set up the tunnels.",
    "over-deletion"))

T("guard-13 filler-trim ratio passes", () => ExpectOk(
    "um so basically I think we should uh you know just ship it tomorrow morning",
    "I think we should ship it tomorrow morning."))

T("guard-14 markdown fence trips", () => ExpectTrip(
    "first we update the docs then we tag the release",
    "``````text`nFirst we update the docs, then we tag the release.`n``````",
    "format-scaffold"))

T("guard-15 transcript tag trips", () => ExpectTrip(
    "hello there how are you doing",
    "<transcript>Hello there, how are you doing?</transcript>",
    "format-scaffold"))

T("guard-15b transcript tag reason is format-scaffold", () => (
    (g := CleanupSanityCheck("hello there how are you doing today friend",
        "<transcript>Hello there, how are you doing today friend.</transcript>"))["ok"]
        ? [false, "guard passed"] : [g["reason"] = "format-scaffold", "got " . g["reason"]]))

T("guard-16 full replacement trips", () => ExpectTrip(
    "remind me to check the parasitic draw on the silverado fuse box this weekend",
    "The quarterly report shows strong growth across all business segments this year.",
    "low-overlap"))

T("guard-17 faithful cleanup passes", () => ExpectOk(
    "so I have a 2017 chevrolet silverado and I've been having issues with a parasitic draw I believe it's the HMI",
    "I have a 2017 Chevrolet Silverado and I've been having issues with a parasitic draw. I believe it's the HMI."))

T("guard-18 hedges kept passes", () => ExpectOk(
    "maybe I'll set that up this weekend I think we should probably test both",
    "Maybe I'll set that up this weekend. I think we should probably test both."))

; ---------------------------------------------------------------------------
; StripTrailingArtifacts — E.2 ack-after-question extension
; ---------------------------------------------------------------------------
StripEq(input, expected) {
    got := StripTrailingArtifacts(input)
    return (got = expected) ? [true] : [false, "got '" . got . "'"]
}

T("strip-01 ack after question stripped", () =>
    StripEq("Are we good to go with the new session? Okay.", "Are we good to go with the new session?"))

T("strip-02 yes after question stripped", () =>
    StripEq("Is each reply being run through a humanizer? Yes.", "Is each reply being run through a humanizer?"))

T("strip-03 ack after statement kept", () =>
    StripEq("The macro videos don't talk about position sizing. Okay.", "The macro videos don't talk about position sizing. Okay."))

T("strip-04 legit yes content kept", () =>
    StripEq("The answer is yes, we should proceed.", "The answer is yes, we should proceed."))

T("strip-05 thank you after boundary still stripped", () =>
    StripEq("Please run the analysis. Thank you.", "Please run the analysis."))

T("strip-06 inline thank you kept", () =>
    StripEq("I wanted to say thank you for the help", "I wanted to say thank you for the help"))

T("strip-07 mid-question ack kept", () =>
    StripEq("Is it okay to deploy now? Let me know your thoughts.", "Is it okay to deploy now? Let me know your thoughts."))

; NOTE: the outro strip regex consumes the sentence-final period too — long-standing
; behavior shared with the PS port; asserted as-is.
T("strip-08 outro artifact stripped", () =>
    StripEq("Update the config file. Thanks for watching!", "Update the config file"))

; ---------------------------------------------------------------------------
; IsWhisperHallucination — regression (unchanged behavior)
; ---------------------------------------------------------------------------
T("halluc-01 thank you filtered", () =>
    [IsWhisperHallucination("Thank you."), ""])

T("halluc-02 real speech kept", () =>
    [!IsWhisperHallucination("Please update the config file tonight."), ""])

T("halluc-03 repeated phrase filtered", () =>
    [IsWhisperHallucination("you you you you you"), ""])

ExitApp(0)
