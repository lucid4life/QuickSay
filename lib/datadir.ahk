; =============================================================================
; lib/datadir.ahk — single source of truth for the QuickSay user-data root
; T1.8 / T1.3-023
; =============================================================================
; Production (compiled / installed): user data lives in %APPDATA%\QuickSay\.
;   This co-locates config / history / statistics / dictionary / audio / logs and
;   the onboarding marker with T2.3's license.dat (lib/license.ahk also resolves
;   to %APPDATA%\QuickSay\), so trial/license state survives an uninstall of the
;   program dir, and the uninstall "don't keep data" path can wipe user content
;   WITHOUT touching the anti-abuse trial file.
; Development (uncompiled): the script dir, so the test harnesses + live runs
;   keep using Development\config.json, Development\data\, etc. unchanged.
;
; Shared by EVERY process that touches user data — QuickSay.ahk (tray/settings
; mode), settings_ui.ahk (standalone settings), onboarding_ui.ahk (wizard) — so
; they can never disagree about where config lives (a split-brain bug). It
; depends ONLY on built-ins (A_IsCompiled, A_ScriptDir, EnvGet), never on a
; script global, so it is safe to call from a class static initializer
; regardless of #Include order.
; =============================================================================

GetDataDir() {
    if (A_IsCompiled)
        return EnvGet("APPDATA") . "\QuickSay"
    return A_ScriptDir
}

; Diagnostic log path under the data root (data\logs\). Returned by a function
; (not a global) so the ~50 call sites need no per-function `global` declaration.
; Resolves + ensures the logs dir once per process (cached) so an early
; FileAppend never fails on a missing directory and the hot path stays cheap.
GetDebugLogPath() {
    static path := ""
    if (path = "") {
        dir := GetDataDir() . "\data\logs"
        if !DirExist(dir)
            try DirCreate(dir)
        path := dir . "\debug_log.txt"
    }
    return path
}

; Create the data directory tree (idempotent). Does NOT pre-create data\audio /
; data\logs before migration would run — see BootstrapDataDir ordering.
EnsureDataDirs() {
    root := GetDataDir()
    for sub in ["", "\data", "\data\audio", "\data\logs"] {
        d := root . sub
        if !DirExist(d)
            try DirCreate(d)
    }
}

; One-time migration: when running installed (data root != script dir) and a
; legacy {app}-relative install left config/data behind, MOVE it to the data
; root. Idempotent (per-item: only moves when the source exists and the target
; does not) and non-destructive (never delete-then-write; the source is left
; intact on any failure). The bundled, read-only changelog.json stays in
; {app}\data (it ships with the installer and is not user data).
; The override params exist only for the test harness (tests/datadir) — in dev
; GetDataDir() == A_ScriptDir so real migration never runs; the overrides let the
; full orchestration be exercised against synthetic temp dirs. Production callers
; pass nothing.
MigrateLegacyDataIfNeeded(legacyOverride := "", dataOverride := "") {
    dataRoot := (dataOverride != "") ? dataOverride : GetDataDir()
    legacy   := (legacyOverride != "") ? legacyOverride : A_ScriptDir
    if (dataRoot = legacy)            ; dev: data already lives in the script dir
        return
    ; Nothing to migrate? (fresh install — no legacy footprint)
    if (!FileExist(legacy . "\config.json")
        && !FileExist(legacy . "\dictionary.json")
        && !DirExist(legacy . "\data"))
        return
    if !DirExist(dataRoot)
        try DirCreate(dataRoot)
    _MoveLegacyItem(legacy . "\config.json",     dataRoot . "\config.json")
    _MoveLegacyItem(legacy . "\dictionary.json", dataRoot . "\dictionary.json")
    if DirExist(legacy . "\data") {
        if !DirExist(dataRoot . "\data")
            try DirCreate(dataRoot . "\data")
        Loop Files, legacy . "\data\*", "FD" {
            if (A_LoopFileName = "changelog.json")   ; bundled read-only asset — stays in {app}
                continue
            _MoveLegacyItem(A_LoopFileFullPath, dataRoot . "\data\" . A_LoopFileName)
        }
    }
}

; Move one file or directory only if the source exists and the target does NOT.
; Never overwrites an already-migrated item; never destroys the source on error.
_MoveLegacyItem(src, dst) {
    srcAttr := FileExist(src)            ; "" if missing; contains "D" for a directory
    if (srcAttr = "")
        return
    if (FileExist(dst) != "" || DirExist(dst) != "")   ; already migrated — leave both
        return
    try {
        if InStr(srcAttr, "D")
            DirMove(src, dst, 1)          ; move directory (target confirmed absent)
        else
            FileMove(src, dst, 0)         ; move file, do NOT overwrite
    } catch {
        ; Leave the source intact on any failure — never lose user data.
    }
}

; Seed a clean default config from the bundled config.example.json template when
; no config exists and nothing was migrated. This keeps the installer from ever
; shipping the developer's live config (T1.3-001) while still giving fresh
; installs a pristine config.json (no key, launchAtStartup=0, real soundTheme).
; (dataOverride/templateOverride: test-harness seams only — see above.)
SeedConfigIfMissing(dataOverride := "", templateOverride := "") {
    cfg := ((dataOverride != "") ? dataOverride : GetDataDir()) . "\config.json"
    if FileExist(cfg)
        return
    template := (templateOverride != "") ? templateOverride : (A_ScriptDir . "\config.example.json")
    if !FileExist(template)
        return
    try FileCopy(template, cfg, 0)
}

; Convenience: run the full first-touch bootstrap in the correct order —
; migrate legacy data first, then fill in any missing dirs, then seed a clean
; config only if there is still none. Called early by each entry process.
BootstrapDataDir() {
    MigrateLegacyDataIfNeeded()
    EnsureDataDirs()
    SeedConfigIfMissing()
}
