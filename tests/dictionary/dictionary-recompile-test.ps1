# =============================================================================
# T1.8 / T1.4-025 regression guard — "Learn from Selection" must take effect now
# =============================================================================
# The bug: AddToDictionary() mutated the in-memory Dictionary and rewrote
# dictionary.json, showed "Added N correction(s)", but NEVER recompiled the live
# match structures (DictCompiledPattern / DictReplacements) that ApplyDictionary
# actually uses. So a learned correction did nothing until the next 0x5555 reload
# or an app restart — the success toast was lying.
#
# The fix: AddToDictionary() must call CompileDictionaryPattern() after the
# successful AtomicWriteFile(), so the new word applies to the very next
# transcription.
#
# This is a static-source regression guard (there is no runnable dictionary
# harness — the dictionary engine lives inside the QuickSay.ahk monolith and the
# tray app cannot be exercised headlessly). It parses the REAL AddToDictionary
# body out of QuickSay.ahk and asserts the recompile call exists and is ordered
# AFTER the file write. It FAILS on the pre-fix code and PASSES on the fix.
# Exit code 0 = pass, 1 = fail.
# =============================================================================

$ErrorActionPreference = "Stop"
$repo   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # tests\dictionary -> Development
$source = Join-Path $repo "QuickSay.ahk"

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS: $msg" -ForegroundColor Green }
    else       { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host "T1.8 dictionary-recompile regression guard" -ForegroundColor Cyan
Assert (Test-Path $source) "QuickSay.ahk exists at $source"

$lines = Get-Content $source

# Locate the AddToDictionary(...) function and walk its brace-balanced body.
$startIdx = ($lines | Select-String -Pattern '^\s*AddToDictionary\s*\(' | Select-Object -First 1).LineNumber
Assert ($null -ne $startIdx) "AddToDictionary() is defined in QuickSay.ahk"

$body = New-Object System.Collections.Generic.List[string]
if ($null -ne $startIdx) {
    $depth = 0
    $seenOpen = $false
    for ($i = $startIdx - 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $body.Add($line)
        $depth += ([regex]::Matches($line, '\{')).Count
        $depth -= ([regex]::Matches($line, '\}')).Count
        if (($line -match '\{')) { $seenOpen = $true }
        if ($seenOpen -and $depth -le 0) { break }
    }
}
$bodyText = ($body -join "`n")

# Core assertions.
Assert ($bodyText -match 'AtomicWriteFile\(DictionaryFile') "AddToDictionary still writes dictionary.json (AtomicWriteFile)"
Assert ($bodyText -match 'CompileDictionaryPattern\(\)') "AddToDictionary calls CompileDictionaryPattern() (THE FIX)"

# Ordering: the recompile must come AFTER the file write so it reflects the
# just-persisted Dictionary state (the in-memory map is mutated earlier still).
$writeIdx   = ($body | Select-String -Pattern 'AtomicWriteFile\(DictionaryFile' | Select-Object -First 1).LineNumber
$recompIdx  = ($body | Select-String -Pattern 'CompileDictionaryPattern\(\)'     | Select-Object -First 1).LineNumber
Assert (($null -ne $writeIdx) -and ($null -ne $recompIdx) -and ($recompIdx -gt $writeIdx)) `
       "CompileDictionaryPattern() is ordered AFTER AtomicWriteFile()"

if ($fail -eq 0) {
    Write-Host "`nALL PASS (dictionary recompile guard)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$fail ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
