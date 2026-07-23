;==============================================================================
; lib/whisper-bias.ahk — custom dictionary -> Whisper biasing prompt (E.2)
;
; Whisper's `prompt` parameter primes the decoder with preceding context; a
; comma-separated glossary of correct spellings biases it toward the user's
; jargon BEFORE transcription (the dictionary regexes still run afterwards as
; the deterministic backstop).
;
; Budget: Whisper honors only ~224 tokens of prompt. We cap at maxChars=600
; (~150 tokens) for headroom. ORDERING: AHK v2 Maps enumerate in sorted key
; order (verified empirically — NOT insertion order), and the dictionary
; format carries no timestamps, so when over budget terms are dropped in
; alphabetical-by-spoken-form order. Deterministic, and the cap is not
; reached before roughly 50 typical terms.
;
; Pure function — exercised by tests/cleanup/guard.test.ahk.
;==============================================================================

; Build the biasing prompt from a dictionary Map(spoken -> written).
; Returns "" when there is nothing usable to bias with.
BuildWhisperBiasPrompt(dictionary, maxChars := 600) {
    if (Type(dictionary) != "Map" || dictionary.Count = 0)
        return ""

    ; Collect unique written forms (the spellings we want Whisper to produce),
    ; sanitized to a single line. Enumeration order: sorted by spoken form.
    seen := Map()
    terms := []
    for spoken, written in dictionary {
        w := Trim(RegExReplace(written, "[`r`n`t]+", " "))
        if (w = "" || StrLen(w) > 60)
            continue
        key := StrLower(w)
        if seen.Has(key)
            continue
        seen[key] := true
        terms.Push(w)
    }
    if (terms.Length = 0)
        return ""

    ; Natural-sentence format, NOT a bare "Glossary:" list. Measured on the
    ; T2.6 corpus (2026-07-14): the bare list echoes verbatim into the
    ; transcript on silence (it would get typed!), while the sentence form
    ; falls back to the classic "Thank you." silence hallucination that
    ; IsWhisperHallucination already filters — and biases jargon just as well.
    ; Drop first-enumerated terms until the prompt fits the budget.
    loop {
        s := ""
        for i, t in terms
            s .= (i = 1 ? "" : (i = terms.Length ? (terms.Length > 2 ? ", and " : " and ") : ", ")) . t
        prompt := "We were discussing " . s . "."
        if (StrLen(prompt) <= maxChars || terms.Length <= 1)
            return prompt
        terms.RemoveAt(1)
    }
}

; True when the transcription is just the bias prompt bleeding back out of
; Whisper (happens on silence/noise). Every content word of the output
; appearing in the prompt = echo, treat like no-speech.
IsBiasPromptEcho(rawText, biasPrompt) {
    if (biasPrompt = "" || Trim(rawText) = "")
        return false
    promptLower := " " . RegExReplace(StrLower(biasPrompt), "[^a-z0-9' ]+", " ") . " "
    words := 0
    for w in StrSplit(RegExReplace(StrLower(rawText), "[^a-z0-9' ]+", " "), " ") {
        if (StrLen(w) < 3)
            continue
        words++
        if !InStr(promptLower, " " . w . " ")
            return false
    }
    return words > 0
}

; Add the bias prompt to a Whisper formFields Map when the dictionary feature
; is enabled and has content. LIVE-DICTATION PATH ONLY: on the T2.6 corpus the
; prompt measurably degrades long-form transcription (long-2min WER 1.2% ->
; 6.5% even in sentence format), so the file-transcription path stays
; unbiased. Short hotkey dictation is where personal jargon lives.
AddWhisperBiasField(formFields) {
    global Config, Dictionary
    try {
        if (Config.Has("dictionary_enabled") && Config["dictionary_enabled"]) {
            p := BuildWhisperBiasPrompt(Dictionary)
            if (p != "")
                formFields["prompt"] := p
        }
    }
    return formFields
}
