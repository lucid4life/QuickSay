# lib/extract-functions.ps1 — pull whole function BODIES straight out of
# QuickSay.ahk so the F.1 Voice Edit harness always exercises the REAL
# production code (no copied/rewritten logic to drift from source).
#
# Convention relied on (per QuickSay.ahk style, confirmed for every function
# this harness extracts): a top-level function starts at column 0 as
# `Name(args) {` (opening brace on the same line) and its closing brace is
# the first line afterward that is EXACTLY "}" at column 0. Nested blocks
# (for/if/try inside the function) are always indented, so they never match.

function Get-AhkFunctionBody {
    param(
        # NOT Mandatory: PowerShell's Mandatory validation rejects a [string[]]
        # argument if ANY element is an empty string — and a file's trailing
        # blank line becomes exactly that after -split "`r?`n". Presence is
        # still checked explicitly below.
        [string[]]$Lines,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Lines) { throw "extract-functions: Lines was null for '$Name'" }

    # Brace-on-same-line is baked into the match itself (not a separate check
    # afterward) so a bare CALL to the function elsewhere in the file — e.g.
    # `RegisterVoiceEditHotkey()  ; F.1 Voice Edit` in the autoexec section —
    # never gets mistaken for the column-0 DEFINITION.
    $startPattern = '^' + [regex]::Escape($Name) + '\s*\([^)]*\)\s*\{\s*$'
    $startIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $startPattern) { $startIdx = $i; break }
    }
    if ($startIdx -lt 0) {
        throw "extract-functions: could not find column-0 definition of '$Name(...) {' (brace on same line)"
    }

    $endIdx = -1
    for ($j = $startIdx + 1; $j -lt $Lines.Count; $j++) {
        if ($Lines[$j] -eq '}') { $endIdx = $j; break }
    }
    if ($endIdx -lt 0) {
        throw "extract-functions: could not find column-0 closing brace for '$Name'"
    }

    return ($Lines[$startIdx..$endIdx] -join "`n")
}

# Extracts several named top-level functions from a single source file and
# returns an ordered map Name -> body text (each body ends with its own "}").
function Get-AhkFunctions {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string[]]$Names
    )

    if (!(Test-Path $SourcePath)) { throw "extract-functions: source not found: $SourcePath" }
    $src   = Get-Content $SourcePath -Raw -Encoding UTF8
    $lines = $src -split "`r?`n"

    $out = [ordered]@{}
    foreach ($n in $Names) {
        $out[$n] = Get-AhkFunctionBody -Lines $lines -Name $n
    }
    return $out
}

# Writes the extracted functions to a generated .ahk file, in the order given,
# separated by blank lines. Returns the path written.
function Write-AhkFunctionsFile {
    param(
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Functions,
        [Parameter(Mandatory)][string]$OutPath,
        [string]$Header = ""
    )

    $outDir = Split-Path $OutPath -Parent
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $parts = @()
    if ($Header) { $parts += $Header }
    foreach ($k in $Functions.Keys) { $parts += $Functions[$k] }

    Set-Content -Path $OutPath -Value ($parts -join "`n`n") -Encoding UTF8
    return $OutPath
}
