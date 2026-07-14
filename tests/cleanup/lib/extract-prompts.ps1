# lib/extract-prompts.ps1 — pull the 4 built-in mode prompts straight out of
# QuickSay.ahk's GetDefaultModes() so the harness always exercises the REAL
# production prompt (no copied strings to drift).
#
# Also verifies the lib/settings-ui.ahk copy matches (the CLAUDE.md dual-sync
# rule) and fails loudly if the two files diverge.

function Get-AhkModePrompts {
    param([string]$DevRoot)

    $mainPath = Join-Path $DevRoot "QuickSay.ahk"
    $uiPath   = Join-Path $DevRoot "lib\settings-ui.ahk"
    if (!(Test-Path $mainPath)) { throw "QuickSay.ahk not found at $mainPath" }

    $ids = [ordered]@{ m1 = "standard"; m2 = "email"; m3 = "code"; m4 = "casual" }

    function Extract-FromFile([string]$path) {
        $src = Get-Content $path -Raw -Encoding UTF8
        $out = @{}
        foreach ($var in $ids.Keys) {
            # m1["prompt"] := "....."   (single line, AHK double-quoted string, backtick escapes)
            $pattern = [regex]::Escape($var + '["prompt"] := "') + '(.*?)"\s*$'
            $m = [regex]::Match($src, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline)
            if (!$m.Success) { throw "Could not extract $var prompt from $path" }
            $prompt = $m.Groups[1].Value
            # Unescape AHK v2 string escapes used in these prompts: `n newline, `t tab, `` literal backtick
            $prompt = $prompt -replace '``', [char]1
            $prompt = $prompt -replace '`n', "`n"
            $prompt = $prompt -replace '`t', "`t"
            $prompt = $prompt -replace [char]1, '``'
            $out[$ids[$var]] = $prompt
        }
        return $out
    }

    $main = Extract-FromFile $mainPath
    if (Test-Path $uiPath) {
        $ui = Extract-FromFile $uiPath
        foreach ($k in $main.Keys) {
            if ($main[$k] -cne $ui[$k]) {
                throw "DUAL-SYNC VIOLATION: '$k' prompt differs between QuickSay.ahk and lib/settings-ui.ahk — fix before running."
            }
        }
    }
    return $main
}
