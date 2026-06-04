# lib/hallucination.ps1 — PowerShell port of IsWhisperHallucination() + StripTrailingArtifacts()
# Faithfully mirrors QuickSay.ahk:3749-3836 (IsWhisperHallucination + StripTrailingArtifacts).
# NOTE: this is a deliberate copy — if the AHK original changes, update here and flag via spawn_task.

function Test-WhisperHallucination {
    param([string]$text)

    if ([string]::IsNullOrEmpty($text)) { return $true }

    $cleaned = $text.Trim()
    if ([string]::IsNullOrEmpty($cleaned)) { return $true }

    # punctuation-only
    if ($cleaned -match '^[.!?,;:\-\s]+$') { return $true }

    $stripped = $cleaned -replace '[.!?,;:\s]+$', ''
    $stripped = $stripped.Trim()
    if ([string]::IsNullOrEmpty($stripped)) { return $true }

    # known single-phrase hallucinations (case-insensitive exact match on stripped text)
    $hallucinations = @(
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
    )
    foreach ($h in $hallucinations) {
        if ($stripped -ieq $h) { return $true }
    }

    # YouTube-style outro patterns
    if ($cleaned -imatch '^(thank you for (watching|listening)|thanks for (watching|listening)|like (and|&) subscribe|please subscribe|don''?t forget to (like|subscribe))[\s.!]*$') {
        return $true
    }

    # entirely repeated phrase (same phrase 3+ times)
    if ($cleaned -imatch '^(.{2,50}?)[\s,.!?]*(\1[\s,.!?]*){2,}$') { return $true }

    # single-word output → hallucination artifact
    # NOTE: this is a known false positive for short-utterance.wav (T1.1 finding 015).
    # "okay", "hello", "no" are rejected even though Whisper got them right.
    $wordCount = ($stripped -split '\s+' | Where-Object { $_ -ne '' }).Count
    if ($wordCount -le 1) { return $true }

    return $false
}

function Remove-TrailingArtifacts {
    param([string]$text)

    $artifacts = @(
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
    )
    foreach ($a in $artifacts) {
        $escaped = [regex]::Escape($a)
        $text = $text -ireplace "[\s,.!?]*$escaped[\s.!?]*$", ''
    }

    # "Thank you" / "Goodbye" / "Bye" only after a sentence boundary
    $text = $text -ireplace '(?<=[.!?])\s*(Thank you|Thanks|Goodbye|Bye)\.?\s*$', ''

    return $text.Trim()
}

# Apply the full QuickSay pipeline to raw Whisper output:
# StripTrailingArtifacts first, then IsWhisperHallucination.
# Returns the text that would be kept, or "" if it would be filtered.
function Get-FilteredText {
    param([string]$raw)
    if ([string]::IsNullOrEmpty($raw)) { return "" }
    $stripped = Remove-TrailingArtifacts $raw
    if (Test-WhisperHallucination $stripped) { return "" }
    return $stripped
}
