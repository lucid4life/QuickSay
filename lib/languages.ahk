; ==============================================================================
;  lib/languages.ahk — single source of truth for STT language codes/names
;  Shared by QuickSay.ahk (tray submenu, Whisper "language" form field) and
;  onboarding_ui.ahk (demo transcription) — a separate process, same pattern
;  as lib/settings-ui.ahk / lib/http.ahk. Do NOT re-duplicate this list;
;  #Include this file instead.
; ==============================================================================

; Ordered [code, name] pairs — 25 languages. Order drives menu/dropdown
; display order, so callers should iterate this list (not a Map derived
; from it) wherever display order matters.
GetLanguageList() {
    return [
        ["en", "English"], ["es", "Spanish"], ["fr", "French"], ["de", "German"],
        ["pt", "Portuguese"], ["zh", "Chinese"], ["ja", "Japanese"], ["ko", "Korean"],
        ["ar", "Arabic"], ["hi", "Hindi"], ["it", "Italian"], ["nl", "Dutch"],
        ["ru", "Russian"], ["pl", "Polish"], ["tr", "Turkish"], ["vi", "Vietnamese"],
        ["th", "Thai"], ["id", "Indonesian"], ["sv", "Swedish"], ["da", "Danish"],
        ["no", "Norwegian"], ["fi", "Finnish"], ["cs", "Czech"], ["ro", "Romanian"],
        ["uk", "Ukrainian"]
    ]
}

; code -> display name (e.g. "en" -> "English")
GetLanguageCodeToName() {
    m := Map()
    for pair in GetLanguageList()
        m[pair[1]] := pair[2]
    return m
}

; display name -> code (normalizes legacy configs that stored the full
; language name instead of the ISO code)
GetLanguageNameToCode() {
    m := Map()
    for pair in GetLanguageList()
        m[pair[2]] := pair[1]
    return m
}

; Resolve a stored "language" config value (ISO code, legacy full name,
; "auto", or empty) to the code Whisper expects. Returns "" when the
; Whisper "language" field should be OMITTED ENTIRELY — auto-detect requires
; the field ABSENT, not an empty string.
ResolveLanguageCode(langRaw) {
    if (langRaw = "" || langRaw = "auto")
        return ""
    nameToCode := GetLanguageNameToCode()
    return nameToCode.Has(langRaw) ? nameToCode[langRaw] : langRaw
}

; Add "language" to a Whisper formFields Map, conditionally — omitted
; entirely for auto-detect/empty. Mutates and returns formFields.
AddLanguageField(formFields, langRaw) {
    code := ResolveLanguageCode(langRaw)
    if (code != "")
        formFields["language"] := code
    return formFields
}
