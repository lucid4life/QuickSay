# =============================================================================
# scripts/release-rollback.ps1 — source-rollback helpers for release.ps1
# T1.8 / T1.3-011
# =============================================================================
# release.ps1 STEP 1 rewrites ~7 source files (+ changelog.json + VERSION) BEFORE
# it compiles, signs, builds the installer, uploads to R2, and signs version.json.
# If the run dies mid-way (the documented Azure-sign hang, an ISCC failure, an R2
# failure, a missing Ed25519 key in STEP 6), the tree is left dirtied with a
# bumped-but-unreleased version and no rollback.
#
# These three pure functions let release.ps1 snapshot every file the version
# rewrite can touch BEFORE mutating, then restore them in a finally{} if the run
# does not reach success. They are kept here (not inline) so the snapshot/restore
# logic is unit-testable in isolation (tests/release/rollback-test.ps1) without
# running the full build pipeline. They take all inputs as parameters and read no
# script-global state, so they are safe to dot-source from anywhere.
# =============================================================================

# Derive the set of absolute paths the rewrite path (STEP 1) can mutate.
# DRY: the dev-repo, Rewrite=$true entries come straight from T1.6's
# $VersionTargets, so a new version location added there is auto-protected.
# $ExtraRelative covers the bespoke files STEP 1 also writes that are not in the
# table (LICENSE_AGREEMENT.rtf, changelog.json, VERSION).
function Get-ReleaseSnapshotPaths {
    param(
        [Parameter(Mandatory)] [array]  $VersionTargets,
        [Parameter(Mandatory)] [string] $DevDir,
        [string[]] $ExtraRelative = @()
    )
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($t in $VersionTargets) {
        if (-not $t.Rewrite) { continue }
        if ($t.ContainsKey('Repo') -and $t.Repo -eq 'website') { continue }
        [void]$set.Add((Join-Path $DevDir $t.File))
    }
    foreach ($rel in $ExtraRelative) {
        [void]$set.Add((Join-Path $DevDir $rel))
    }
    return @($set)
}

# Capture the exact bytes of each existing path. Returns a hashtable {path -> byte[]}.
# Files that do not exist yet are simply not captured (Restore won't recreate them).
function Save-ReleaseSnapshot {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $snap = @{}
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $snap[$p] = [System.IO.File]::ReadAllBytes($p)
        }
    }
    return $snap
}

# Restore every captured file to its pre-snapshot bytes. Returns the count restored.
# Best-effort: a single file failing to restore does not abort the rest.
function Restore-ReleaseSnapshot {
    param([Parameter(Mandatory)] [hashtable] $Snapshot)
    $restored = 0
    foreach ($p in @($Snapshot.Keys)) {
        try {
            [System.IO.File]::WriteAllBytes($p, $Snapshot[$p])
            $restored++
        } catch {
            Write-Host "   FAILED to restore: $p — $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    return $restored
}
