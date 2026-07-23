# Transcription-quality dogfood loop (E.2)

The one-line habit: **dictate normally; whenever a transcription comes out
imperfect, tray-menu → "⚑ Flag Last Transcription."** That's it — every
annoyance becomes a captured test case.

## What's running on this machine (enabled 2026-07-14)

- `saveAudioRecordings: 1` and `keepLastRecordings: 100` in
  `%APPDATA%\QuickSay\config.json` (pre-E.2 values backed up at
  `config.json.e2-dogfood-backup`). Every dictation now stores its WAV in
  `%APPDATA%\QuickSay\data\audio\`; rotation keeps the newest 100
  (rotation is safe post-T1.5).
- History already stores `rawText` (Whisper) + `cleanedText` (post-LLM) per
  entry, so each flagged entry is a full **raw / cleaned / audio triple**.

## The flag

The tray item marks the newest history entry `"flagged": true`
(`FlagNewestHistoryEntry()` in `lib/history-core.ahk`, mutex + fresh-read +
atomic write like every other history mutation). Flag promptly — the audio
file rotates out after 100 more recordings.

> The ⚑ item ships with the E.2 build (branch `audit/E.2-transcription-lab`);
> the installed 1.9.0-beta doesn't have it yet. Until the rc2 build (E.5) is
> installed, audio + raw/cleaned still land for every dictation — imperfect
> ones can be harvested by timestamp instead of the flag.

## Harvesting (E.3 / E.5)

```powershell
# list flagged entries
node -e "const h=require(process.env.APPDATA+'/QuickSay/data/history.json'); for (const e of h) if (e.flagged) console.log(e.id, e.timestamp, e.audioFile)"
```

For each flagged entry: add the WAV (if the user approves that specific clip)
to `tests/transcription/corpus/` expectations, and/or add the rawText to
`tests/cleanup/local-corpus/` (gitignored — real dictation never gets
committed). Re-run both suites; fix; repeat.

## Related suites

| Suite | Run | Cost |
|---|---|---|
| Cleanup guard + artifact filter + bias units | `pwsh tests\cleanup\run-guard-tests.ps1` | offline |
| Cleanup LLM regression (probes + local corpus) | `pwsh tests\cleanup\run-cleanup-tests.ps1 -IncludeLocalCorpus` | Groq API |
| STT regression (T2.6 + jargon) | `pwsh tests\transcription\run-stt-regression.ps1 -CompareBaseline` | Groq API |
| History (incl. flag) | `pwsh tests\history\run-tests.ps1` | offline |
