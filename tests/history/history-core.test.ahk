;==============================================================================
; T1.5 — history/retention regression tests (AHK-native unit driver)
;
; Exercises the REAL functions in lib/history-core.ahk (no copies, no drift).
; Driven by run-tests.ps1, which passes:
;   A_Args[1] = results file (TSV: name<TAB>PASS|FAIL[<TAB>detail])
;   A_Args[2] = scratch working directory (created fresh, deleted after)
;
; Run standalone:
;   AutoHotkey64.exe history-core.test.ahk results.txt _tmp
;==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\history-core.ahk

global ResultFile := A_Args.Length >= 1 ? A_Args[1] : A_ScriptDir . "\results.txt"
global WorkDir    := A_Args.Length >= 2 ? A_Args[2] : A_ScriptDir . "\_tmp"

if DirExist(WorkDir)
    DirDelete(WorkDir, true)
DirCreate(WorkDir)
if FileExist(ResultFile)
    FileDelete(ResultFile)

; ---------------------------------------------------------------------------
; harness helpers
; ---------------------------------------------------------------------------
Record(name, ok, detail := "") {
    global ResultFile
    line := name . "`t" . (ok ? "PASS" : "FAIL")
    if (detail != "")
        line .= "`t" . detail
    FileAppend(line . "`n", ResultFile, "UTF-8")
}

T(name, fn) {
    try {
        r := fn()                       ; [ok] or [ok, detail]
        Record(name, r[1], r.Length > 1 ? r[2] : "")
    } catch as e {
        Record(name, false, "EXCEPTION: " . e.Message)
    }
}

MakeEntry(id, text) {
    return Map(
        "appContext", "test",
        "audioFile", "",
        "cleanedText", text,
        "duration", 100,
        "hotkey", "^LWin",
        "id", id,
        "rawText", text,
        "timestamp", "2026-05-29 00:00:00",
        "wordCount", 1)
}

; Seed history.json INDEPENDENTLY of the code under test (direct JSON write).
; Produces a newest-first array: arr[1]="e<count>" (newest) ... arr[count]="e1" (oldest).
SeedHistory(path, count) {
    arr := []
    Loop count {
        n := count - A_Index + 1
        arr.Push(MakeEntry("e" . n, "text" . n))
    }
    txt := JSON.Stringify(arr, "  ")
    if FileExist(path)
        FileDelete(path)
    FileAppend(txt, path, "UTF-8-RAW")
    return arr
}

ContainsId(arr, id) {
    for e in arr
        if (e["id"] = id)
            return true
    return false
}

MakeWavs(dir, n) {
    if !DirExist(dir)
        DirCreate(dir)
    Loop n {
        i := A_Index
        fname := dir . "\r" . Format("{:02}", i) . ".wav"
        if FileExist(fname)
            FileDelete(fname)
        FileAppend("RIFFfake", fname, "UTF-8-RAW")
        ; monotonically increasing mtime: r01 oldest ... rNN newest
        mt := "20260501" . "00" . Format("{:02}", i) . "00"
        FileSetTime(mt, fname, "M")
    }
}

CountWavs(dir) {
    c := 0
    Loop Files, dir . "\*.wav"
        c++
    return c
}

; Models the deferred-write tail: the generation guard then the read-modify-write.
DoDeferredWrite(historyFile, entry, retention, scheduledGen, currentGen) {
    if (!ShouldWriteHistory(scheduledGen, currentGen))
        return false
    arr := ReadHistoryArray(historyFile)
    arr := BuildHistoryArray(arr, entry, retention)
    WriteHistoryArray(historyFile, arr)
    return true
}

; ---------------------------------------------------------------------------
; RETENTION (tests 1-5)
; ---------------------------------------------------------------------------
Test_01() {                                   ; 95 + 1 @100 -> 96
    global WorkDir
    hp := WorkDir . "\h1.json"
    SeedHistory(hp, 95)
    arr := ReadHistoryArray(hp)
    arr := BuildHistoryArray(arr, MakeEntry("new", "newtext"), 100)
    WriteHistoryArray(hp, arr)
    got := ReadHistoryArray(hp)
    return [got.Length = 96, "len=" . got.Length]
}

Test_02() {                                   ; 100 + 1 @100 -> 100, oldest trimmed
    global WorkDir
    hp := WorkDir . "\h2.json"
    SeedHistory(hp, 100)
    arr := ReadHistoryArray(hp)
    arr := BuildHistoryArray(arr, MakeEntry("new", "newtext"), 100)
    WriteHistoryArray(hp, arr)
    got := ReadHistoryArray(hp)
    ok := got.Length = 100 && got[1]["id"] = "new" && !ContainsId(got, "e1")
    return [ok, "len=" . got.Length . " head=" . got[1]["id"] . " hasOldest=" . ContainsId(got, "e1")]
}

Test_03() {                                   ; 250 legacy @100 -> trims to 100 (migration)
    global WorkDir
    hp := WorkDir . "\h3.json"
    SeedHistory(hp, 250)
    arr := ReadHistoryArray(hp)
    arr := BuildHistoryArray(arr, MakeEntry("new", "newtext"), 100)
    WriteHistoryArray(hp, arr)
    got := ReadHistoryArray(hp)
    return [got.Length = 100, "len=" . got.Length]
}

Test_04() {                                   ; retention 0 = unlimited
    global WorkDir
    hp := WorkDir . "\h4.json"
    SeedHistory(hp, 5)
    arr := ReadHistoryArray(hp)
    arr := BuildHistoryArray(arr, MakeEntry("new", "newtext"), 0)
    WriteHistoryArray(hp, arr)
    got := ReadHistoryArray(hp)
    return [got.Length = 6, "len=" . got.Length]
}

Test_05() {                                   ; order preserved: oldest dropped, newest kept
    global WorkDir
    hp := WorkDir . "\h5.json"
    SeedHistory(hp, 3)                         ; newest-first: e3, e2, e1
    arr := ReadHistoryArray(hp)
    arr := BuildHistoryArray(arr, MakeEntry("e4", "t4"), 3)
    WriteHistoryArray(hp, arr)
    got := ReadHistoryArray(hp)
    ok := got.Length = 3 && got[1]["id"] = "e4" && got[2]["id"] = "e3" && got[3]["id"] = "e2"
    return [ok, "order=" . got[1]["id"] . "," . got[2]["id"] . "," . got[3]["id"]]
}

; ---------------------------------------------------------------------------
; AUDIO RETENTION (tests 6-8) — gated by saveRecordings at the call site
; ---------------------------------------------------------------------------
Test_06() {                                   ; 15 wav, keep 10, save ON -> 10 remain, 5 oldest deleted
    global WorkDir
    dir := WorkDir . "\audio6"
    MakeWavs(dir, 15)
    deleted := PruneAudioIfEnabled(true, dir, 10)
    remaining := CountWavs(dir)
    ok := remaining = 10 && deleted = 5 && !FileExist(dir . "\r01.wav") && FileExist(dir . "\r15.wav")
    return [ok, "rem=" . remaining . " del=" . deleted]
}

Test_07() {                                   ; 15 wav, keep 10, save OFF -> no prune, 15 remain
    global WorkDir
    dir := WorkDir . "\audio7"
    MakeWavs(dir, 15)
    deleted := PruneAudioIfEnabled(false, dir, 10)
    remaining := CountWavs(dir)
    return [remaining = 15 && deleted = -1, "rem=" . remaining . " del=" . deleted]
}

Test_08() {                                   ; keep 0, save ON -> all deleted
    global WorkDir
    dir := WorkDir . "\audio8"
    MakeWavs(dir, 15)
    deleted := PruneAudioIfEnabled(true, dir, 0)
    remaining := CountWavs(dir)
    return [remaining = 0 && deleted = 15, "rem=" . remaining . " del=" . deleted]
}

; ---------------------------------------------------------------------------
; CLEAR-HISTORY RACE (test 9 + resurrection)
; ---------------------------------------------------------------------------
Test_09() {                                   ; in-flight write dropped when a clear advanced the generation
    global WorkDir
    hp := WorkDir . "\h9.json"                 ; file absent = just cleared
    wrote := DoDeferredWrite(hp, MakeEntry("inflight", "x"), 100, 0, 1)
    got := ReadHistoryArray(hp)
    return [wrote = false && got.Length = 0, "wrote=" . wrote . " len=" . got.Length]
}

Test_09b() {                                  ; write proceeds normally when no clear happened
    global WorkDir
    hp := WorkDir . "\h9b.json"
    wrote := DoDeferredWrite(hp, MakeEntry("normal", "x"), 100, 0, 0)
    got := ReadHistoryArray(hp)
    return [wrote = true && got.Length = 1, "wrote=" . wrote . " len=" . got.Length]
}

Test_09c() {                                  ; old entries NEVER resurrect after a clear (structural re-read)
    global WorkDir
    hp := WorkDir . "\h9c.json"
    SeedHistory(hp, 5)                         ; pre-clear entries
    FileDelete(hp)                             ; clear deletes the file
    wrote := DoDeferredWrite(hp, MakeEntry("after", "x"), 100, 0, 0)   ; gen not advanced -> write proceeds
    got := ReadHistoryArray(hp)
    ok := got.Length = 1 && got[1]["id"] = "after"
    return [ok, "len=" . got.Length . " head=" . (got.Length ? got[1]["id"] : "-")]
}

; ---------------------------------------------------------------------------
; CORRUPTION / ATOMICITY (test 10)
; ---------------------------------------------------------------------------
Test_10() {                                   ; two sequential RMW writes leave valid, complete JSON
    global WorkDir
    hp := WorkDir . "\h10.json"
    SeedHistory(hp, 10)
    a := ReadHistoryArray(hp)
    a := BuildHistoryArray(a, MakeEntry("w1", "x"), 100)
    WriteHistoryArray(hp, a)
    b := ReadHistoryArray(hp)
    b := BuildHistoryArray(b, MakeEntry("w2", "y"), 100)
    WriteHistoryArray(hp, b)
    got := ReadHistoryArray(hp)
    ok := got.Length = 12 && got[1]["id"] = "w2" && got[2]["id"] = "w1" && !FileExist(hp . ".tmp")
    return [ok, "len=" . got.Length . " head=" . got[1]["id"]]
}

Test_10b() {                                  ; transcript containing "}," and "id": survives (kills T1.1-017 string-surgery)
    global WorkDir
    hp := WorkDir . "\h10b.json"
    SeedHistory(hp, 2)
    nasty := 'code: function() {}, and "id": 5 weird'
    a := ReadHistoryArray(hp)
    a := BuildHistoryArray(a, MakeEntry("nasty", nasty), 100)
    WriteHistoryArray(hp, a)
    got := ReadHistoryArray(hp)
    ok := got.Length = 3 && got[1]["cleanedText"] = nasty
    return [ok, "len=" . got.Length]
}

; ---------------------------------------------------------------------------
; HISTORY COUNT (T1.2-012: count parsed entries, not file lines)
; ---------------------------------------------------------------------------
Test_12() {
    global WorkDir
    hp := WorkDir . "\h12.json"
    SeedHistory(hp, 10)                         ; pretty-printed -> far more than 10 physical lines
    cnt := HistoryEntryCount(hp)
    return [cnt = 10, "count=" . cnt]
}

; ---------------------------------------------------------------------------
; CORRUPT / NON-ARRAY PRESERVATION (no silent data loss)
; ---------------------------------------------------------------------------
Test_13() {                                   ; non-array (legacy object) file is preserved, not lost
    global WorkDir
    hp := WorkDir . "\h13.json"
    if FileExist(hp)
        FileDelete(hp)
    if FileExist(hp . ".corrupt")
        FileDelete(hp . ".corrupt")
    FileAppend('{"legacy":"object","id":"x"}', hp, "UTF-8-RAW")
    got := ReadHistoryArray(hp)
    ok := (got is Array) && got.Length = 0 && FileExist(hp . ".corrupt")
    return [ok, "len=" . got.Length . " backedUp=" . FileExist(hp . ".corrupt")]
}

; ---------------------------------------------------------------------------
; CONFIG MERGE (T1.2-009 lost-update: apply delta to a fresh read, preserve the rest)
; ---------------------------------------------------------------------------
Test_11c() {                                  ; updates don't clobber keys written by another writer
    cfg := Map("a", 1, "lastUpdateCheck", "tray-wrote-this", "currentMode", "standard")
    MergeConfigKeys(cfg, Map("currentMode", "email"), [])
    ok := cfg["currentMode"] = "email" && cfg["lastUpdateCheck"] = "tray-wrote-this" && cfg["a"] = 1
    return [ok, "mode=" . cfg["currentMode"] . " keep=" . cfg["lastUpdateCheck"]]
}

Test_11d() {                                  ; deletes remove only requested keys
    cfg := Map("a", 1, "currentMode", "email", "startTourOnOpen", true)
    MergeConfigKeys(cfg, Map(), ["startTourOnOpen"])
    ok := !cfg.Has("startTourOnOpen") && cfg["currentMode"] = "email" && cfg["a"] = 1
    return [ok, "hasFlag=" . cfg.Has("startTourOnOpen")]
}

; ---------------------------------------------------------------------------
; run
; ---------------------------------------------------------------------------
T("01_retention_add_under_cap_keeps_96",     Test_01)
T("02_retention_at_cap_trims_oldest",        Test_02)
T("03_retention_migration_trims_bloated",    Test_03)
T("04_retention_zero_is_unlimited",          Test_04)
T("05_retention_order_newest_kept",          Test_05)
T("06_audio_save_on_trims_to_keepcount",     Test_06)
T("07_audio_save_off_no_prune",              Test_07)
T("08_audio_keepcount_zero_deletes_all",     Test_08)
T("09_clear_inflight_write_dropped",         Test_09)
T("09b_write_proceeds_when_no_clear",        Test_09b)
T("09c_no_resurrection_after_clear",         Test_09c)
T("10_concurrent_writes_no_corruption",      Test_10)
T("10b_nasty_text_no_corruption",            Test_10b)
T("12_entry_count_not_line_count",           Test_12)
T("13_nonarray_file_preserved_not_lost",     Test_13)
T("11c_merge_preserves_unrelated_keys",      Test_11c)
T("11d_merge_deletes_requested_keys",        Test_11d)

FileAppend("__DONE__`n", ResultFile, "UTF-8")
ExitApp(0)
