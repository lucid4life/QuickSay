;==============================================================================
; lib/cleanup-guard.ahk — post-LLM-cleanup sanity guard (E.2)
;
; A wrong cleanup must never beat the raw transcript. After the Groq cleanup
; call returns, both call sites (QuickSay.ahk live-recording and
; file-transcription paths) run CleanupSanityCheck(raw, cleaned); on any
; failure the pipeline falls back to the raw text (dictionary regexes and the
; artifact stripper still apply downstream).
;
; The rules mirror the harmful-pattern catalog from the E.2 full-history
; mining: assistant-style answers, no-transcript meta-responses, injected
; trailing acknowledgments, lost questions, runaway generation, over-deletion,
; format scaffolding, and full-replacement outputs.
;
; Pure functions, no globals — exercised directly by tests/cleanup/guard.test.ahk.
;==============================================================================

; Count words the cheap way the rest of the app does (whitespace split).
CleanupGuard_WordCount(text) {
    n := 0
    for w in StrSplit(Trim(text), [" ", "`n", "`t"]) {
        if (w != "")
            n++
    }
    return n
}

; First word of text, lowercased, punctuation stripped.
CleanupGuard_FirstWord(text) {
    if RegExMatch(Trim(text), "i)^[^a-z0-9]*([a-z0-9']+)", &m)
        return StrLower(m[1])
    return ""
}

; Fraction of raw's distinct words (len >= 3) that survive into cleaned.
; Catches full-replacement outputs (fabricated reports, echoed system prompts)
; that pass every length test.
CleanupGuard_Overlap(rawText, cleanedText) {
    rawWords := Map()
    for w in StrSplit(RegExReplace(StrLower(rawText), "[^a-z0-9' ]+", " "), " ") {
        if (StrLen(w) >= 3)
            rawWords[w] := true
    }
    if (rawWords.Count = 0)
        return 1.0
    cleanedLower := " " . RegExReplace(StrLower(cleanedText), "[^a-z0-9' ]+", " ") . " "
    hits := 0
    for w in rawWords
        if InStr(cleanedLower, " " . w . " ")
            hits++
    return hits / rawWords.Count
}

; Main guard. Returns Map("ok", true/false, "reason", "...").
; Conservative by design: it only fires on patterns that are near-certain
; assistant-mode failures, never on aggressive-but-plausible edits.
CleanupSanityCheck(rawText, cleanedText) {
    raw := Trim(rawText)
    cleaned := Trim(cleanedText)

    if (cleaned = "")
        return Map("ok", false, "reason", "empty-output")

    ; 1. Meta-responses about the transcript ("You have not provided...")
    if RegExMatch(cleaned, "i)(you have not provided|no transcript (was|is|has been)?\s*(provided|given)|please provide (the|a|your) (raw )?(speech )?transcript|^as an ai\b)")
        return Map("ok", false, "reason", "meta-response")

    ; 2. Assistant answer-lead the speaker didn't dictate
    if RegExMatch(cleaned, "i)^(yes|no|sure|okay|certainly|absolutely)[,.!]\s") || RegExMatch(cleaned, "i)^(of course|i can|i will|i'll|here (is|are)|great question)\b") {
        if (CleanupGuard_FirstWord(cleaned) != CleanupGuard_FirstWord(raw))
            return Map("ok", false, "reason", "answer-lead")
    }

    ; 3. Injected trailing acknowledgment ("... . Yes.")
    if RegExMatch(cleaned, "i)[.!?]\s+(yes|no|okay|sure|yeah)[.!]?\s*$", &ack) {
        if !RegExMatch(raw, "i)\b" . ack[1] . "[.!?, ]*$")
            return Map("ok", false, "reason", "injected-trailing-ack")
    }

    ; 4. Question lost entirely (raw asked something; cleaned asks nothing)
    if (InStr(raw, "?") && !InStr(cleaned, "?"))
        return Map("ok", false, "reason", "question-lost")

    rawWords := CleanupGuard_WordCount(raw)
    cleanedWords := CleanupGuard_WordCount(cleaned)

    ; 5. Runaway generation (report writing, invented content). Bound is
    ;    generous so Email-mode scaffolding never trips it.
    if (cleanedWords > rawWords * 2 + 12)
        return Map("ok", false, "reason", "length-explosion")

    ; 6. Over-deletion: most of a real dictation vanished
    if (rawWords >= 12 && cleanedWords < rawWords * 0.4)
        return Map("ok", false, "reason", "over-deletion")

    ; 7. Format scaffolding that must never be typed at a cursor
    if (InStr(cleaned, "``````") || InStr(cleaned, "<transcript>") || InStr(cleaned, "</transcript>"))
        return Map("ok", false, "reason", "format-scaffold")

    ; 8. Full replacement: output shares almost no vocabulary with the input
    if (rawWords >= 8 && CleanupGuard_Overlap(raw, cleaned) < 0.35)
        return Map("ok", false, "reason", "low-overlap")

    return Map("ok", true, "reason", "")
}
