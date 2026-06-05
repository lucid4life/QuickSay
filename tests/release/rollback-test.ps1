# =============================================================================
# T1.8 / T1.3-011 — release.ps1 source-rollback tests
# =============================================================================
# Exercises the REAL snapshot/restore helpers (scripts/release-rollback.ps1) that
# release.ps1 uses, simulating a mid-run failure: snapshot -> mutate source ->
# restore -> assert the tree is byte-for-byte back to the pre-release state.
# Also statically asserts release.ps1 is wired to use them (try/finally + gate).
# Exit 0 = pass, 1 = fail.
# =============================================================================

$ErrorActionPreference = "Stop"
$repo   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # tests\release -> Development
. (Join-Path $repo "scripts\release-rollback.ps1")

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS: $msg" -ForegroundColor Green }
    else       { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:fail++ }
}
function Section($t) { Write-Host "`n[$t]" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
Section "Get-ReleaseSnapshotPaths derivation (DRY from `$VersionTargets)"
# ---------------------------------------------------------------------------
$fakeTargets = @(
    @{ File='QuickSay.ahk';        Rewrite=$true;  Label='a' }
    @{ File='QuickSay.ahk';        Rewrite=$true;  Label='dup (same file)' }   # de-duped
    @{ File='setup.iss';           Rewrite=$true;  Label='b' }
    @{ File='gui\settings.html';   Rewrite=$false; Label='not rewritten' }     # excluded
    @{ File='src\Footer.astro';    Rewrite=$true;  Repo='website'; Label='website' } # excluded
)
$paths = Get-ReleaseSnapshotPaths -VersionTargets $fakeTargets -DevDir "C:\dev" `
            -ExtraRelative @("VERSION", "data\changelog.json")
Assert ($paths -contains "C:\dev\QuickSay.ahk")        "includes rewritten dev file (QuickSay.ahk)"
Assert ($paths -contains "C:\dev\setup.iss")           "includes rewritten dev file (setup.iss)"
Assert ($paths -contains "C:\dev\VERSION")             "includes extra file (VERSION)"
Assert ($paths -contains "C:\dev\data\changelog.json") "includes extra file (changelog.json)"
Assert (-not ($paths -contains "C:\dev\gui\settings.html")) "excludes Rewrite=`$false targets"
Assert (-not ($paths -contains "C:\dev\src\Footer.astro"))  "excludes website-repo targets"
Assert (($paths | Where-Object { $_ -eq "C:\dev\QuickSay.ahk" }).Count -eq 1) "de-duplicates repeated files"

# ---------------------------------------------------------------------------
Section "Save/Restore round-trip — simulated mid-run failure"
# ---------------------------------------------------------------------------
$sandbox = Join-Path $env:TEMP ("qs-rollback-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
try {
    $f1 = Join-Path $sandbox "QuickSay.ahk"
    $f2 = Join-Path $sandbox "VERSION"
    $unrelated = Join-Path $sandbox "unrelated.txt"
    Set-Content -LiteralPath $f1 -Value "localVersion := `"1.9.0`"" -NoNewline -Encoding UTF8
    Set-Content -LiteralPath $f2 -Value "1.9.0" -NoNewline -Encoding UTF8
    Set-Content -LiteralPath $unrelated -Value "leave me alone" -NoNewline -Encoding UTF8

    $orig1 = [System.IO.File]::ReadAllBytes($f1)
    $orig2 = [System.IO.File]::ReadAllBytes($f2)
    $origU = [System.IO.File]::ReadAllBytes($unrelated)

    # 1. Snapshot (only the two tracked source files; NOT the unrelated file)
    $snap = Save-ReleaseSnapshot -Paths @($f1, $f2)
    Assert ($snap.Count -eq 2) "snapshot captured exactly the 2 tracked files"

    # 2. Mutate (STEP 1 bump) + create a half-built artifact, then "fail"
    Set-Content -LiteralPath $f1 -Value "localVersion := `"1.9.1`"" -NoNewline -Encoding UTF8
    Set-Content -LiteralPath $f2 -Value "1.9.1" -NoNewline -Encoding UTF8
    Set-Content -LiteralPath $unrelated -Value "user edited this during the run" -NoNewline -Encoding UTF8
    Assert ((Get-Content $f2 -Raw) -eq "1.9.1") "VERSION was bumped (pre-failure state)"

    # 3. Restore (what release.ps1's finally{} does on failure)
    $n = Restore-ReleaseSnapshot -Snapshot $snap
    Assert ($n -eq 2) "restore reported 2 files"

    $new1 = [System.IO.File]::ReadAllBytes($f1)
    $new2 = [System.IO.File]::ReadAllBytes($f2)
    $newU = [System.IO.File]::ReadAllBytes($unrelated)
    Assert ([System.Linq.Enumerable]::SequenceEqual($orig1, $new1)) "QuickSay.ahk restored byte-for-byte"
    Assert ([System.Linq.Enumerable]::SequenceEqual($orig2, $new2)) "VERSION restored byte-for-byte"
    Assert (-not [System.Linq.Enumerable]::SequenceEqual($origU, $newU)) "unrelated file NOT touched by restore (left as user edited)"
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Section "release.ps1 is wired to the rollback guard"
# ---------------------------------------------------------------------------
$rel = Get-Content (Join-Path $repo "release.ps1") -Raw
Assert ($rel -match 'scripts\\release-rollback\.ps1')           "release.ps1 dot-sources the rollback helper"
Assert ($rel -match 'Save-ReleaseSnapshot')                     "release.ps1 captures a snapshot before STEP 1"
Assert ($rel -match '(?m)^\s*try\s*\{')                         "release.ps1 opens a try block around the pipeline"
Assert ($rel -match '(?ms)finally\s*\{.*Restore-ReleaseSnapshot') "release.ps1 restores in finally{}"
Assert ($rel -match 'ReleaseSucceeded\s*=\s*\$true')            "release.ps1 sets the success flag on completion"

if ($fail -eq 0) {
    Write-Host "`nALL PASS (release rollback)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$fail ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
