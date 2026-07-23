; =============================================================================
; T1.8 / T1.3-023 — lib/datadir.ahk unit tests (headless)
; =============================================================================
; Exercises the REAL data-root resolver + migration + seed helpers against
; synthetic temp dirs. Run via:  AutoHotkey64.exe /ErrorStdOut datadir-tests.ahk
; Prints "  PASS/FAIL  <name>" lines and exits 0 (all pass) or 1 (any fail).
; =============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%\..\..\lib\datadir.ahk

global gPass := 0, gFail := 0
Assert(name, cond) {
    global gPass, gFail
    if (cond) {
        gPass++
        FileAppend("  PASS  " name "`n", "*")
    } else {
        gFail++
        FileAppend("  FAIL  " name "`n", "*")
    }
}
mkfile(path, content := "x") {
    SplitPath(path, , &dir)
    if (dir != "" && !DirExist(dir))
        DirCreate(dir)
    f := FileOpen(path, "w")
    f.Write(content)
    f.Close()
}

root := A_Temp "\qs-datadir-" A_TickCount
DirCreate(root)

; ── GetDataDir: uncompiled => A_ScriptDir (keeps dev harnesses working) ───────
Assert("GetDataDir() = A_ScriptDir when uncompiled", GetDataDir() = A_ScriptDir)

; ── GetDebugLogPath: under data\logs\, creates the dir on demand ──────────────
dbg := GetDebugLogPath()
Assert("GetDebugLogPath ends in \data\logs\debug_log.txt", InStr(dbg, "\data\logs\debug_log.txt") > 0)
Assert("GetDebugLogPath ensured the logs dir exists", DirExist(GetDataDir() "\data\logs") != "")

; ── _MoveLegacyItem: file move when target absent ────────────────────────────
src := root "\src1.txt", dst := root "\dst1.txt"
mkfile(src, "hello")
_MoveLegacyItem(src, dst)
Assert("_MoveLegacyItem moved file (source gone, target present)", FileExist(dst) != "" && FileExist(src) = "")
Assert("_MoveLegacyItem preserved content", FileRead(dst) = "hello")

; ── _MoveLegacyItem: never overwrite an existing target ──────────────────────
src2 := root "\src2.txt"
mkfile(src2, "new")
mkfile(dst, "ORIGINAL")
_MoveLegacyItem(src2, dst)
Assert("_MoveLegacyItem does NOT overwrite existing target", FileRead(dst) = "ORIGINAL")
Assert("_MoveLegacyItem leaves source intact when target exists", FileExist(src2) != "")

; ── _MoveLegacyItem: missing source is a no-op (no throw) ─────────────────────
_MoveLegacyItem(root "\nope.txt", root "\nope-dst.txt")
Assert("_MoveLegacyItem no-op on missing source", FileExist(root "\nope-dst.txt") = "")

; ── _MoveLegacyItem: directory move ──────────────────────────────────────────
srcdir := root "\srcdir"
mkfile(srcdir "\a.txt", "A")
_MoveLegacyItem(srcdir, root "\dstdir")
Assert("_MoveLegacyItem moved directory", DirExist(root "\dstdir") != "" && DirExist(srcdir) = "")
Assert("_MoveLegacyItem moved dir contents", FileExist(root "\dstdir\a.txt") != "")

; ── MigrateLegacyDataIfNeeded: full orchestration, synthetic roots ───────────
legacy := root "\legacy", data := root "\data"
DirCreate(legacy)
mkfile(legacy "\config.json", "CFG")
mkfile(legacy "\dictionary.json", "DICT")
mkfile(legacy "\data\history.json", "HIST")
mkfile(legacy "\data\statistics.json", "STAT")
mkfile(legacy "\data\onboarding_done", "1")
mkfile(legacy "\data\audio\rec.wav", "WAV")
mkfile(legacy "\data\logs\debug.txt", "LOG")
mkfile(legacy "\data\changelog.json", "CHANGELOG")   ; bundled — must NOT move

MigrateLegacyDataIfNeeded(legacy, data)

Assert("migrate moved config.json (content intact)", FileExist(data "\config.json") != "" && FileRead(data "\config.json") = "CFG")
Assert("migrate moved dictionary.json", FileExist(data "\dictionary.json") != "")
Assert("migrate moved data\history.json", FileExist(data "\data\history.json") != "")
Assert("migrate moved data\statistics.json", FileExist(data "\data\statistics.json") != "")
Assert("migrate moved onboarding_done marker", FileExist(data "\data\onboarding_done") != "")
Assert("migrate moved audio dir", FileExist(data "\data\audio\rec.wav") != "")
Assert("migrate moved logs dir", FileExist(data "\data\logs\debug.txt") != "")
Assert("migrate did NOT move bundled changelog.json", FileExist(data "\data\changelog.json") = "" && FileExist(legacy "\data\changelog.json") != "")
Assert("migrate is a true move (legacy config.json gone)", FileExist(legacy "\config.json") = "")

; ── Idempotency: a second run never re-clobbers migrated/edited data ─────────
mkfile(data "\config.json", "MODIFIED-BY-USER")
MigrateLegacyDataIfNeeded(legacy, data)
Assert("migrate idempotent (doesn't re-clobber migrated config)", FileRead(data "\config.json") = "MODIFIED-BY-USER")

; ── SeedConfigIfMissing ──────────────────────────────────────────────────────
seedData := root "\seedData"
DirCreate(seedData)
tmpl := root "\template.json"
mkfile(tmpl, "TEMPLATE")
SeedConfigIfMissing(seedData, tmpl)
Assert("seed creates config from template when missing", FileExist(seedData "\config.json") != "" && FileRead(seedData "\config.json") = "TEMPLATE")
mkfile(seedData "\config.json", "USERCONFIG")
SeedConfigIfMissing(seedData, tmpl)
Assert("seed does NOT overwrite an existing config", FileRead(seedData "\config.json") = "USERCONFIG")

try DirDelete(root, true)
; GetDebugLogPath() created <A_ScriptDir>\data\logs here (dev resolver) — clean it.
try DirDelete(A_ScriptDir "\data", true)

FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
