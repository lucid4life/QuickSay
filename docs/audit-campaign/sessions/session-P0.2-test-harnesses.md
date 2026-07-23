# Session P0.2 — Test Harnesses + Baseline Inventory

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/P0.2-test-harnesses`
> **Parallel-safe with:** — (Phase 0 is serial; nothing else runs while this lands)
> **Depends on:** P0.1 (plugins + `quicksay-go-to-paid` skill activated)
> **Blocks:** ALL of Phase 1 (every audit and fix session in Track 1 and Track 2 leans on these harnesses)
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort high`. This is scaffolding work, not deep reasoning — but it is the foundation every later session stands on, so do it carefully. Sonnet 4.6 has a 200K context window; this session reads several source files plus tool output, so close out finished sub-tasks from your working set as you go.

---

## Prompt to paste

You are building the test infrastructure for the entire QuickSay beta→production audit campaign. Every Track 1 audit and every Track 2 build that follows will use the three harnesses you create here. If a harness is flaky or hard to run, it poisons 16 downstream sessions — so the bar is "runs green from one command, on a clean checkout, with a copy-paste invocation in the README."

This session also re-verifies 6 suspect items from the starting surface inventory and writes the campaign's baseline document. **You write test code and a baseline doc only — you make ZERO changes to QuickSay application source** (`QuickSay.ahk`, `lib/*.ahk`, `gui/*`, `onboarding_ui.ahk`, `widget-overlay.ahk`, `setup.iss`, `release.ps1`). The one exception is documented below in "The one allowed source touch."

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). Hold `Ctrl+Win`, speak, release — transcript types at the cursor. It uses the Groq Whisper API for transcription and optionally Groq GPT-OSS 20B for LLM cleanup. The settings and onboarding UIs are HTML/CSS/JS rendered inside an embedded Chromium (WebView2). Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — full architecture, file map, runtime-directory split (Development/ vs repo root vs installed app), AHK v2 gotchas, the `0x5555` IPC contract.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign structure. §6 "Cross-cutting infrastructure" defines the exact `tests/` layout you are building. You will update the Status Tracker at the end.
3. `docs/audit-campaign/research/tooling-research.md` — §2 (Playwright over CDP for WebView2, the canonical Microsoft path), §8 (Whisper STT regression corpora). These are your build specs.
4. `docs/audit-campaign/research/app-surface-inventory.md` — the "6 things flagged" section at the bottom is your re-verification checklist (Phase 4).

### What you are building (3 harnesses + 1 baseline doc)

Per MASTER-PLAN.md §6, everything lives under `Development/tests/`:

| Component | Path | One-command entry point |
|---|---|---|
| (a) WebView2 UI driver | `Development/tests/playwright/` | `node tests/playwright/run.mjs <settings\|onboarding>` (or `npm test` inside the dir) |
| (b) Whisper transcription regression | `Development/tests/transcription/` | `pwsh tests/transcription/run-stt-regression.ps1` |
| (c) AHK live runner | `Development/tests/live-runner.ps1` | `pwsh tests/live-runner.ps1` |
| Baseline inventory doc | `docs/audit-campaign/findings/P0.2-baseline.md` | (committed artifact) |

`Development/tests/` **IS committed to git**. But it must be excluded from the installer scope so it is never bundled into the shipped `.exe`/installer. See "Phase 5 — installer exclusion" below.

---

### Phase 1 — Harness (a): Playwright-over-CDP for the WebView2 UIs

QuickSay's settings window and onboarding wizard are HTML/CSS/JS inside WebView2. Microsoft officially documents driving WebView2 with Playwright over the Chrome DevTools Protocol (CDP). Per `tooling-research.md` §2:

- App side: WebView2 must be launched with `--remote-debugging-port=9222`. There are two ways to inject this:
  1. Set the `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` environment variable **before** the WebView2 COM environment is created. (Process-wide, zero source change — preferred.)
  2. Pass it through the `AdditionalBrowserArguments` option on the environment-options object. QuickSay's wrapper exposes this at `lib/WebView2.ahk:1125` / `:1142`. (Requires a source change — avoid unless option 1 fails.)
- Connect side (Playwright/Node):
  ```js
  import { chromium } from 'playwright';
  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const context = browser.contexts()[0];
  const page = context.pages()[0];
  ```

Reference implementation: `Haprog/playwright-cdp` (linked in `tooling-research.md` §2) is the exact CDP→WebView2 pattern.

#### Build steps

1. **Decide the launch contract.** The harness must be able to:
   - Launch the settings UI: the binary runs with `--settings` (per CLAUDE.md "Process Model" — same `QuickSay.exe`, mode-switched at line ~53). When running uncompiled, that is `AutoHotkey64.exe QuickSay.ahk --settings`.
   - Launch the onboarding wizard: `AutoHotkey64.exe onboarding_ui.ahk`.
   - Inject `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` into the child process environment (PowerShell: `$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'` before launch; or pass via the Node `child_process.spawn` env). Use a **unique** `WEBVIEW2_USER_DATA_FOLDER` per run (a temp dir) so tests never cross-contaminate, per `tooling-research.md` §2.

2. **Try option 1 first (env var, no source change).** Launch QuickSay with the env var set, then `connectOverCDP('http://localhost:9222')`. If a page appears in `browser.contexts()`, you are done — document this in the baseline as "zero source change required."

3. **If option 1 does not surface a debuggable target,** fall back to option 2 — see "The one allowed source touch" below.

4. **Write a small Node harness** at `Development/tests/playwright/run.mjs` that:
   - Takes one arg: `settings` or `onboarding`.
   - Spawns the right AHK process with the debug-port env var + a fresh user-data folder.
   - Polls `http://localhost:9222/json` until a page is available (timeout ~15s, clear error if it never appears).
   - Connects over CDP, grabs the page, and runs a tiny **smoke assertion**: settings → the General tab heading is present in the DOM; onboarding → the first wizard step renders.
   - Takes a screenshot to `tests/playwright/artifacts/<target>-smoke.png`.
   - Cleanly tears down (close the CDP connection, kill the AHK child, remove the temp user-data folder).
   - Exits `0` on success, non-zero with a readable message on failure.
   - Exposes reusable helpers (`launchUI()`, `connect()`, `screenshot()`, `teardown()`) so T1.2 and T1.4 can `import` them rather than re-implementing.

5. **Add `tests/playwright/package.json`** with `playwright` as a dependency and a `"test"` script. Run `npm install` and confirm Playwright's chromium is NOT separately downloaded for CDP-connect (CDP attaches to the existing WebView2 Chromium — you do not need `npx playwright install`). Document the install steps in the dir's README.

6. Invoke the `playwright-skill:playwright-skill` skill when you reach the connect/assert/screenshot loop — it knows the clean script patterns.

**Done-gate for (a):** `node tests/playwright/run.mjs settings` launches the settings UI, connects, asserts a known element, screenshots, and exits 0. Same for `onboarding`. The README documents the one command and prerequisites.

#### The one allowed source touch (only if option 1 fails)

If — and only if — the env-var injection does not produce a CDP-debuggable target, you may add a **single, test-gated** branch in the WebView2 init path: when `A_Args` contains `--test-mode` (or env `QUICKSAY_TEST_MODE=1`), set `AdditionalBrowserArguments := "--remote-debugging-port=9222"` on the environment options at the call site that builds them (near `lib/WebView2.ahk:1125`). It must be a no-op in normal runs. If you take this path:
- Keep the diff to under ~10 lines.
- Guard it so production builds never open the port.
- Document the exact diff in the baseline doc and flag it for T1.2/T1.3 to review as a security item ("debug port must never open in a signed release build").
- This is the ONLY source change permitted in P0.2. Everything else is read-only.

---

### Phase 2 — Harness (b): Whisper transcription regression corpus + runner

Per `tooling-research.md` §8, you need three buckets of audio. For P0.2, build a **minimal but real** corpus — enough to baseline and to be expanded by T2.6 (the full regression-corpus session). Do not over-collect; T2.6 owns the large corpus.

#### Corpus to assemble

```
Development/tests/transcription/
  audio/
    baseline/        # 8-12 LibriSpeech test-clean clips with known ground-truth transcripts
    hallucination/   # 3-5 silence/noise clips sourced from sachaarbonel/whisper-hallucinations
    edge/            # self-generate via ffmpeg: silence.wav, white-noise.wav, sub-500ms.wav
  expected.json      # ground-truth transcripts + per-clip expectations (incl. "should be rejected as hallucination")
  run-stt-regression.ps1
  README.md
```

- **baseline/** — pull a small subset of LibriSpeech `test-clean` (https://www.openslr.org/12). 8-12 clips is plenty. Record each clip's known transcript in `expected.json`.
- **hallucination/** — pull 3-5 clips from the `sachaarbonel/whisper-hallucinations` HuggingFace dataset (https://huggingface.co/datasets/sachaarbonel/whisper-hallucinations). These are silence/noise inputs that make Whisper emit phantom text ("Thank you for watching", etc.). In `expected.json` mark each as `"expectHallucination": true`.
- **edge/** — generate with the bundled FFmpeg (`Development/ffmpeg.exe`):
  - `silence.wav` — e.g. `ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 2 silence.wav`
  - `white-noise.wav` — e.g. `ffmpeg -f lavfi -i anoisesrc=d=2:c=white:r=16000 white-noise.wav`
  - `sub-500ms.wav` — a ~300ms clip (below QuickSay's 500ms minimum — should never reach the API).

If any dataset download is blocked or rate-limited in your environment, generate synthetic stand-ins with FFmpeg and clearly mark them as synthetic placeholders in `expected.json` and the README, so T2.6 knows to swap them for the real corpus. Do not block the session on a download.

#### The runner — `run-stt-regression.ps1`

- Reads `expected.json`.
- For each clip: POSTs the WAV to Groq Whisper (`https://api.groq.com/openai/v1/audio/transcriptions`, model `whisper-large-v3-turbo`) using the same multipart shape QuickSay uses (mirror `lib/http.ahk`'s `HttpPostFile()` contract — but reimplement in PowerShell, do NOT call into the AHK source).
- The API key comes from an env var (`$env:GROQ_API_KEY`), NEVER from the user's encrypted `config.json` and NEVER hardcoded. If the env var is unset, the runner prints a clear "set GROQ_API_KEY to run live STT tests; running in offline-assert-only mode" message and skips the network calls (so the harness still "runs" green in CI without a key).
- For `baseline/` clips: compute Word Error Rate (WER) against the ground truth, print per-clip WER and a corpus-average, and assert WER stays under a documented threshold (record the observed baseline WER — don't invent a number; measure it).
- For `hallucination/` and `edge/` clips: assert the transcript is empty OR would be caught by a hallucination filter. (You cannot call `IsWhisperHallucination()` directly from PowerShell — instead, record the raw Groq output for each so T1.1/T2.6 can later assert the AHK filter catches it. The runner's job here is to capture and store, not to re-implement the filter.)
- Writes a results file `tests/transcription/results/<timestamp>.json` and exits 0 if all assertions hold.

**Done-gate for (b):** `pwsh tests/transcription/run-stt-regression.ps1` runs end-to-end. With `GROQ_API_KEY` set it does live WER + hallucination capture; without it, it runs in offline-assert-only mode and still exits 0. README documents both.

---

### Phase 3 — Harness (c): AHK live runner

`Development/tests/live-runner.ps1` is the workhorse the audit and fix sessions use to observe a running QuickSay instance. Per MASTER-PLAN.md §6 it: starts `QuickSay.ahk` under `AutoHotkey64.exe`, tails `data/logs/debug.txt`, and prints state.

#### Requirements

- **Launch:** Start `QuickSay.ahk` via `& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" QuickSay.ahk` (path per CLAUDE.md "Debugging" section). Accept an optional `-Settings` switch that appends `--settings`, and an optional `-TestMode` switch that sets `QUICKSAY_TEST_MODE=1` / the debug-port env var so this runner composes with harness (a).
- **Debug logging:** The runner must ensure `debugLogging` is on so there is something to tail. Do this WITHOUT editing the source: set it in `config.json` (the runner may write a temp config or toggle the existing field), and restore the prior value on teardown. Document the approach.
- **Tail:** Stream `data/logs/debug.txt` (path per CLAUDE.md: `Development\data\logs\debug.txt`) live to the console with timestamps. Handle the file not existing yet (poll until it appears). PowerShell: `Get-Content -Path <log> -Wait -Tail 0`.
- **State print:** Surface the current state by parsing the tail (recording / processing / idle / error transitions). A simple regex over the log lines is fine — the goal is "a human or a later session can watch what the app is doing in real time."
- **Teardown:** On Ctrl+C or a `-DurationSeconds <n>` timeout, kill the QuickSay process cleanly (it owns a tray icon and possibly an FFmpeg child — kill the tree), and restore any config it changed.
- **Safety:** Never delete user data. Never touch `%APPDATA%\QuickSay\` except to temporarily flip `debugLogging` (with restore). Operate against the `Development/data/` working copy where possible.

**Done-gate for (c):** `pwsh tests/live-runner.ps1` starts QuickSay, prints "started", tails the debug log live, and on `Ctrl+C` (or after `-DurationSeconds`) cleanly stops the process and restores config. README documents `-Settings`, `-TestMode`, `-DurationSeconds`.

---

### Phase 4 — Re-verify the 6 flagged items + write the baseline doc

The starting surface inventory (`docs/audit-campaign/research/app-surface-inventory.md`) is explicitly marked **partial / unverified**. Its bottom section lists "The 6 things flagged as surprising / broken-looking." Your job is NOT to fix any of them (those are owned by T1.1/T1.5/T1.6) — it is to **confirm or refute each with a file:line citation** so the audit sessions start from facts, not hypotheses.

Re-verify each, read-only, citing source:

1. **Model hardcoding** — confirm STT (`whisper-large-v3-turbo`) and LLM (`openai/gpt-oss-20b`) models are hardcoded with no UI customization. Cite the exact lines in `QuickSay.ahk` where each model string lives.
2. **`contextAwareModes`** — the field exists (default 0). Confirm or refute that any code actually reads it and switches modes by foreground window. CLAUDE.md mentions `GetContextModeId()` — does it exist and is it wired? Cite.
3. **`keepLastRecordings`** — confirm whether audio cleanup/retention is wired anywhere, or orphaned. Cite the read site in `LoadConfig()` and search for any consumer.
4. **File-sync uncertainty** — list every JSON write of `config.json` and `history.json` and whether each uses `AtomicWriteFile()` + the config mutex. A small table is enough. Cite lines.
5. **Version format mismatch** — confirm `lastSeenVersion: "1.9.0-beta"` (config) vs the resource/`localVersion` strings. Note that `setup.iss:5` defines `MyAppVersion "1.9.0"` and `setup.iss:14/:34/:38` consume it — record every divergent version string and its location. (T1.6 fixes; you only locate.)
6. **History clear bug** — confirm the user-reported "clear, then reappears" race surface exists (settings-process write vs tray-process deferred write). Cite the clear-history handler and the tray's history-write site. (T1.5 fixes; you only locate.)

Also record one **factual discrepancy you should sanity-check**: the surface inventory claims **7 sound themes** (including `default` and `silent`), while CLAUDE.md says **6** (bloom, click, crystal, mechanical, neon, subtle) and the `sounds/` directory on disk contains 6. Note the actual on-disk count and theme names in the baseline so T1.4 inherits the correct number.

Use the `superpowers:systematic-debugging` skill while tracing items 4–6.

#### Write `docs/audit-campaign/findings/P0.2-baseline.md`

(The `docs/audit-campaign/findings/` directory does not exist yet — create it.) The baseline doc contains:

- **Harness inventory** — the three harnesses, their exact one-command invocations, prerequisites (Node + Playwright for (a), `GROQ_API_KEY` for live (b), AutoHotkey v2 for (c)), and known limitations.
- **The 6 re-verifications** — each item: CONFIRMED / REFUTED / PARTIAL, with file:line evidence and a one-line owner tag (e.g. "owned by T1.5", "owned by T1.6").
- **Sound theme count correction** — the verified on-disk theme list.
- **Measured STT baseline** — the corpus-average WER you actually observed (or "not measured — no API key in this run" if offline).
- **The one allowed source touch** — if you took it, the exact diff and the security flag for T1.2/T1.3.
- **Environment notes** — Node version, Playwright version, AutoHotkey path, anything a later session needs to reproduce the harnesses.

---

### Phase 5 — Installer exclusion + commit

`Development/tests/` is committed to git but must **never** ship inside the installer. Confirm `setup.iss` does not pull `tests/` into the `[Files]` section. The `[Files]` lines copy specific paths (`gui\*`, `lib\*`, `64bit\*`, `sounds\*`, named files) — `tests\` is not among them, so it is excluded by omission. **Verify this is true** (read `setup.iss` `[Files]`) and record it in the baseline. Do NOT add a glob that would sweep `tests/` in. If you find any wildcard that would catch `tests/`, flag it for T1.3 (do not fix it here — `setup.iss` is T1.3's surface).

Then commit on the session branch:

- Use the `commit-commands:commit` skill.
- Stage: everything under `Development/tests/`, the new `docs/audit-campaign/findings/P0.2-baseline.md`, the MASTER-PLAN.md Status Tracker update, and (only if you took it) the single WebView2 test-mode diff.
- Do NOT stage downloaded corpus binaries if they are large — if the LibriSpeech/hallucination WAVs are sizeable, add a `tests/transcription/audio/.gitignore` note + a `fetch-corpus.ps1` script that re-downloads them, and commit the script instead of the binaries. Small edge-case WAVs you generated are fine to commit. Document the choice in the README.
- Commit message: `P0.2 — test harnesses (Playwright/CDP, STT regression, AHK live runner) + baseline inventory`.
- Open a PR against `main`.

---

### Done When

The following are all true. Do not declare complete without verifying each — run the command and read the output.

- [ ] `node tests/playwright/run.mjs settings` launches the settings WebView2 UI, connects over CDP on port 9222, asserts a known element, writes a screenshot, exits 0.
- [ ] `node tests/playwright/run.mjs onboarding` does the same for the onboarding wizard.
- [ ] `pwsh tests/transcription/run-stt-regression.ps1` runs end-to-end (live with `GROQ_API_KEY`, offline-assert-only without), exits 0, writes a results file.
- [ ] `pwsh tests/live-runner.ps1` starts QuickSay, tails `data/logs/debug.txt` live, prints state, and stops cleanly (Ctrl+C or `-DurationSeconds`) restoring any config it changed.
- [ ] Each harness directory has a README with the exact one-command invocation and prerequisites.
- [ ] `docs/audit-campaign/findings/P0.2-baseline.md` exists with: harness inventory, all 6 re-verifications (CONFIRMED/REFUTED/PARTIAL + file:line + owner tag), the verified sound-theme count, measured WER baseline (or offline note), and the installer-exclusion confirmation.
- [ ] `setup.iss` confirmed NOT to bundle `tests/` (recorded in baseline). No source change to `setup.iss`.
- [ ] Zero changes to QuickSay application source EXCEPT the single optional WebView2 test-mode diff (documented + flagged if taken). `git diff` against the source files shows nothing else.
- [ ] MASTER-PLAN.md Status Tracker updated: `P0.2 — Test harnesses + baseline inventory` → ✅ done.
- [ ] Branch `audit/P0.2-test-harnesses` committed. PR opened against `main`.

### What NOT to do

- ❌ Do not modify QuickSay application source beyond the single optional WebView2 test-mode branch. This is infrastructure, not app code.
- ❌ Do not fix any of the 6 flagged items. You confirm/refute and tag the owner session. T1.1, T1.5, T1.6 do the fixing.
- ❌ Do not read the user's real Groq API key out of `config.json` for harness (b). The key comes from `$env:GROQ_API_KEY` only, or the run goes offline-assert-only.
- ❌ Do not bundle `tests/` into the installer. Do not add a wildcard to `setup.iss`.
- ❌ Do not download the full LibriSpeech / Common Voice corpora. Build the minimal subset; T2.6 owns the large corpus.
- ❌ Do not run `npx playwright install` to download a separate Chromium — CDP attaches to the existing WebView2 Chromium. If something insists on a browser download, stop and reconsider the connect path.
- ❌ Do not leave the WebView2 remote-debugging port open in any path a production build can hit. If you added the test-mode branch, prove it is gated.
- ❌ Do not commit large binary WAVs without considering repo bloat — prefer a `fetch-corpus.ps1` for the heavy datasets.
- ❌ Do not skip the baseline doc. The 6 re-verifications are the whole point of starting Phase 1 from facts.

### Estimated time

Phase 1 (Playwright/CDP harness): 60-90 min (most of the risk is the first successful CDP connect). Phase 2 (STT corpus + runner): 45-60 min. Phase 3 (live runner): 30-45 min. Phase 4 (re-verify 6 + baseline doc): 45-60 min. Phase 5 (exclusion + commit): 15 min. **Total wall-clock: ~3.5-4.5 hours.**

### When you're done

Report back with:
- The three exact one-command invocations, copy-pasteable.
- For each of the 6 flagged items: CONFIRMED / REFUTED / PARTIAL and the file:line that settled it.
- Whether you needed the WebView2 test-mode source touch (and if so, the diff + the security flag you left for T1.2/T1.3).
- The verified sound-theme count and names (resolving the 6-vs-7 discrepancy).
- The measured STT baseline WER, or "offline — no key this run."
- Any harness limitation a downstream session must know about (e.g. "Playwright connect needs the app fully booted; allow 5s before connecting").
- Confirmation MASTER-PLAN.md Status Tracker is updated and the PR is open.
