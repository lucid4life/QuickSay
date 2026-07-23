;==============================================================================
; lib/history-core.ahk — history + audio retention core (T1.5)
;
; The single source of truth for mutating data/history.json and pruning
; data/audio/. Pure, dependency-light helpers so the regression suite
; (tests/history/) can exercise the REAL code with no copied bodies.
;
; Invariant: every history mutation is a fresh read -> JSON.Parse -> modify ->
; trim -> atomic write. There is NO long-lived in-memory history cache, so a
; write can never resurrect entries a "Clear History" just deleted.
;
; Requires JSON (lib/JSON.ahk) to be included by the host before use.
; Included by QuickSay.ahk (production) and tests/history/*.test.ahk (tests).
;==============================================================================

; Fresh read of history.json as a JSON array. Missing / empty / corrupt -> [].
; A corrupt file is preserved once as <file>.corrupt before we start clean, so a
; legacy file mangled by the old string-surgery trim (T1.1-017) is never silently
; destroyed.
ReadHistoryArray(historyFile) {
    if !FileExist(historyFile)
        return []
    try {
        txt := Trim(FileRead(historyFile, "UTF-8"))
        if (txt = "" || txt = "[]")
            return []
        parsed := JSON.Parse(txt)
        if (parsed is Array)
            return parsed
        ; Valid JSON but not an array (unexpected/legacy object format) — fall
        ; through to the preserve-then-reset path so nothing is silently lost.
        throw Error("history.json is not a JSON array")
    } catch {
        try {
            if (FileExist(historyFile) && !FileExist(historyFile . ".corrupt"))
                FileCopy(historyFile, historyFile . ".corrupt")
        }
        return []
    }
}

; Keep only the most-recent `limit` entries. history is newest-first, so the
; newest are kept and the OLDEST are dropped. limit <= 0 means unlimited.
TrimHistoryToRetention(history, limit) {
    if (limit <= 0)
        return history
    if (history.Length <= limit)
        return history
    trimmed := []
    Loop limit
        trimmed.Push(history[A_Index])
    return trimmed
}

; Prepend the new entry (newest-first), then enforce retention. A bloated legacy
; array is brought into line on this first append after upgrade (migration).
BuildHistoryArray(existing, newEntry, limit) {
    existing.InsertAt(1, newEntry)
    return TrimHistoryToRetention(existing, limit)
}

; Atomic write of the array as pretty JSON: tmp + rename (atomic on NTFS),
; matching AtomicWriteFile semantics. Real JSON serialization replaces the
; fragile string surgery, so a transcript containing "}," or "id": can no longer
; corrupt the file.
WriteHistoryArray(historyFile, history) {
    text := JSON.Stringify(history, "  ")
    tmpPath := historyFile . ".tmp"
    if FileExist(tmpPath)
        FileDelete(tmpPath)
    FileAppend(text, tmpPath, "UTF-8-RAW")
    FileMove(tmpPath, historyFile, 1)
}

; Delete all but the newest `keepCount` *.wav (by mtime). keepCount <= 0 deletes
; every file. Never throws — a prune failure must not block saving a recording.
; Returns the number of files deleted.
PruneAudioDirectory(dirPath, keepCount) {
    deleted := 0
    try {
        if !DirExist(dirPath)
            return 0
        lines := ""
        Loop Files, dirPath . "\*.wav"
            lines .= A_LoopFileTimeModified . "`t" . A_LoopFileFullPath . "`n"
        if (lines = "")
            return 0
        ; mtime is a zero-padded YYYYMMDDHH24MISS string, so lexicographic sort =
        ; chronological. "R" => descending => newest first.
        sorted := Sort(Trim(lines, "`n"), "R")
        idx := 0
        Loop Parse, sorted, "`n" {
            idx++
            if (idx > keepCount) {
                parts := StrSplit(A_LoopField, "`t", , 2)
                if (parts.Length >= 2 && FileExist(parts[2])) {
                    FileDelete(parts[2])
                    deleted++
                }
            }
        }
    }
    return deleted
}

; Gate the prune by the saveRecordings toggle. When saving is OFF we leave any
; existing files alone (the user may want them); returns -1 to signal "skipped".
PruneAudioIfEnabled(saveRecordings, dirPath, keepCount) {
    if (!saveRecordings)
        return -1
    return PruneAudioDirectory(dirPath, keepCount)
}

; A deferred history write is void if a "Clear History" advanced the generation
; after the recording was scheduled. scheduledGen < 0 disables the guard (used by
; the file-transcription path, which is not subject to the clear race).
ShouldWriteHistory(scheduledGen, currentGen) {
    if (scheduledGen < 0)
        return true
    return scheduledGen = currentGen
}

; Authoritative entry count = parsed array length (NOT physical line count, which
; over-counts the pretty-printed file >2x — T1.2-012).
HistoryEntryCount(historyFile) {
    return ReadHistoryArray(historyFile).Length
}

; Mark the newest history entry as flagged (E.2 dogfood: "this transcription
; was imperfect — capture it as a test case"). Fresh read -> mutate -> atomic
; write, same invariant as every other mutation here. Caller holds the config
; mutex. Returns the flagged entry's id, or "" when there is nothing to flag.
FlagNewestHistoryEntry(historyFile) {
    history := ReadHistoryArray(historyFile)
    if (history.Length = 0)
        return ""
    entry := history[1]
    if (Type(entry) != "Map")
        return ""
    entry["flagged"] := true
    WriteHistoryArray(historyFile, history)
    return entry.Has("id") ? entry["id"] : "(unidentified)"
}

; Apply a delta (updates + deletes) to a config Map in place and return it. Used
; under the config mutex by the settings RMW handlers so a fresh-read config is
; modified and written back without clobbering keys another process wrote
; (lost-update, T1.2-009).
MergeConfigKeys(cfg, updates, deletes := "") {
    for k, v in updates
        cfg[k] := v
    if IsObject(deletes) {
        for k in deletes
            if cfg.Has(k)
                cfg.Delete(k)
    }
    return cfg
}
