;==============================================================================
; lib/artifact-filter.ahk — Whisper hallucination detection + trailing-artifact
; stripping (extracted from QuickSay.ahk in E.2 so tests/cleanup can exercise
; the REAL functions; PowerShell mirror: tests/transcription/lib/hallucination.ps1
; — keep the two in sync).
;==============================================================================


; Detects known Whisper hallucination patterns that occur when no real speech
; is present (silence, background noise, etc.)
; Returns true if the text is a known hallucination pattern
IsWhisperHallucination(text) {
    if (StrLen(text) = 0)
        return true

    cleaned := Trim(text, " `t`n`r")

    if (StrLen(cleaned) = 0)
        return true

    ; Punctuation-only text is a hallucination (e.g., ".", "...", "!", ",")
    if RegExMatch(cleaned, "^[.!?,;:\-\s]+$")
        return true

    ; Strip trailing punctuation for comparison
    stripped := RegExReplace(cleaned, "[.!?,;:\s]+$", "")
    stripped := Trim(stripped)

    if (StrLen(stripped) = 0)
        return true

    ; Check for known single-phrase hallucinations (case-insensitive)
    hallucinations := [
        "Thank you for watching",
        "Thanks for watching",
        "Thank you",
        "Thanks",
        "Subscribe",
        "Like and subscribe",
        "Please subscribe",
        "Please like and subscribe",
        "Don't forget to subscribe",
        "Thanks for listening",
        "Thank you for listening",
        "See you in the next video",
        "See you next time",
        "Bye",
        "Goodbye"
    ]

    for hallucination in hallucinations {
        if (StrCompare(stripped, hallucination, false) = 0)
            return true
    }

    ; Check for YouTube-style outro patterns (case-insensitive)
    if RegExMatch(cleaned, "i)^(thank you for (watching|listening)|thanks for (watching|listening)|like (and|&) subscribe|please subscribe|don'?t forget to (like|subscribe))[\s.!]*$")
        return true

    ; Check for entirely repeated phrases (same phrase 3+ times)
    ; e.g., "Thank you. Thank you. Thank you." or "you you you you"
    if RegExMatch(cleaned, "i)^(.{2,50}?)[\s,.!?]*(\1[\s,.!?]*){2,}$")
        return true

    ; Language-agnostic: single-word output is likely a hallucination artifact
    ; Whisper produces brief single-token artifacts from silence/noise in any language
    wordCount := StrSplit(Trim(stripped), " ", " ").Length
    if (wordCount <= 1)
        return true

    return false
}

; Strip known trailing Whisper hallucination artifacts from otherwise valid speech
; e.g., "My actual dictation. Thank you." → "My actual dictation."
StripTrailingArtifacts(text) {
    ; Unambiguous trailing Whisper hallucination phrases — always strip from end
    artifacts := [
        "Thanks for watching",
        "Thank you for watching",
        "Thanks for listening",
        "Thank you for listening",
        "Please subscribe",
        "Like and subscribe",
        "Please like and subscribe",
        "Don't forget to subscribe",
        "See you in the next video",
        "See you next time"
    ]
    for artifact in artifacts {
        text := RegExReplace(text, "i)[\s,.!?]*\Q" . artifact . "\E[\s.!?]*$", "")
    }

    ; "Thank you" / "Goodbye" / "Bye" — only strip when after a sentence boundary
    ; Matches: "Real words. Thank you." but NOT "I wanted to say thank you"
    text := RegExReplace(text, "i)(?<=[.!?])\s*(Thank you|Thanks|Goodbye|Bye)\.?\s*$", "")

    ; E.2: one-word acknowledgment hallucinated right after a dictated question
    ; ("...good to go with the new session? Okay." / "...through a humanizer? Yes.").
    ; Whisper answers the speaker's own question from trailing silence/breath —
    ; the top real-world "it answered my question / random yes" trigger. Only
    ; fires when the ack is the very last word AND directly follows a '?'.
    text := RegExReplace(text, "i)(?<=\?)\s*(Yes|Yeah|Yep|No|Nope|Sure|Okay|OK)[.!]?\s*$", "")

    return Trim(text)
}
