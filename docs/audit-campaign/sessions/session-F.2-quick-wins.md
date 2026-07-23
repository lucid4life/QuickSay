# Session F.2: Competitive Quick Wins (language auto-detect, STT model picker, friendly 429s, prompt i18n)

> **Model:** Fable 5 (`/model claude-fable-5`), Opus 4.8 acceptable
> **Effort:** high (`/effort high`)
> **Branch:** `feature/F.2-quick-wins` (Development repo), **off `main`** (stack consolidated to main at 3b8a44a, 2026-07-22).
> **Parallel-safe with:** F.4 (research spike, no app code). NOT parallel with F.1 (shared `QuickSay.ahk`).
> **Depends on:** nothing. FIRST in the pre-launch chain (decided 2026-07-22): F.2 -> F.1 -> E.3 -> E.4 -> E.5 (rc2) -> UAT -> M.3 launch. F.3 is post-launch (v2.1).
> **Why:** Competitive deep-dive 2026-07-22: rivals advertise "100+ languages, auto-detected" while QuickSay already ships 25 languages but hides the model choice entirely and cannot auto-detect. Groq free-tier verification showed the real usage ceiling is 20 requests/min (Whisper) and 30 requests/min (LLM), so burst users WILL see 429s that currently read as generic errors.

---

## Prompt to paste

You are shipping four small, high-visibility improvements to QuickSay: a language "Auto-detect" option, a user-facing STT model picker, friendly Groq rate-limit (429) handling, and language-neutral cleanup prompts. Each is independently shippable; land them as separate commits in this order.

### Evidence already in hand (codebase recon + official Groq verification, 2026-07-22; build on it, do not re-derive)

- **Language is ALWAYS sent to Whisper.** All three call sites build `formFields := Map("model", sttModel, "language", lang)` with `lang` defaulting to `"en"`: `QuickSay.ahk:1129/1139` (file path), `QuickSay.ahk:3260/3280` (live path), `onboarding_ui.ahk:676/684` (demo). `HttpPostFile()` (`lib/http.ahk:36`) writes a multipart part for every key present, no skip-if-empty. Whisper auto-detect requires the field ABSENT. Fix: conditional construction (`if (lang != "" && lang != "auto") formFields["language"] := lang`) in all three sites.
- **FOUR near-duplicate language maps exist:** tray code-to-name Map `QuickSay.ahk:507-515` (25 languages), two name-to-code maps at `QuickSay.ahk:~1131` and `~3262` (each carries a "keep in sync" comment), and a third copy in `onboarding_ui.ahk:674-684` that no comment tracks. Factor into ONE shared function/Map before adding "auto" so it lands once, not four times. Settings dropdown: `gui/settings.html:320-346`.
- **`sttModel` has ZERO UI.** Default `whisper-large-v3-turbo` is set in 6 places (`QuickSay.ahk:1128, 1551, 1893, 3258`, `onboarding_ui.ahk:331-332, 675`, `config.example.json:3`); no settings control, no tray entry, no validation anywhere (value passes straight to the API). Verified model menu (Groq docs 2026-07-22): exactly TWO STT models exist, `whisper-large-v3-turbo` ($0.04/hr paid tier, fast) and `whisper-large-v3` ($0.111/hr, max accuracy); `distil-whisper-large-v3-en` was deprecated Aug 2025. Free-tier limits are identical for both (20 RPM, 2,000 RPD, 7,200 audio-sec/hr, 28,800 audio-sec/day). Add the picker next to the Language section (`gui/settings.html:315-348`), with a hard allow-list of those two IDs.
- **Whisper-bias caveat for the picker:** `lib/whisper-bias.ahk` budgets (~224 tokens, 600 chars) and the live-path-only rule (`QuickSay.ahk:3282`; file path deliberately excluded per `QuickSay.ahk:1135-1138`, measured WER 1.2%->6.5% on long audio) were measured against turbo. Re-run the T2.6 corpus + E.2 harness against `whisper-large-v3` before exposing it, and record results in the findings doc.
- **429 handling:** Groq returns `retry-after` (seconds) on 429 plus `x-ratelimit-remaining-*` headers on all responses (verified official). The Whisper POST goes through `HttpPostFile()` (`lib/http.ahk`) and the LLM POST through `HttpPostJson()` (`QuickSay.ahk:3670-3703`). Today a 429 surfaces as a generic failure. Free-tier ceilings that users can realistically hit: 20 req/min Whisper, 30 req/min LLM (daily caps are effectively unreachable for dictation: heavy 60 min/day use is 12.5% of the audio-sec/day cap).
- **English-tuned cleanup:** the four mode prompts in `GetDefaultModes()` (`QuickSay.ahk:1586-1626` AND `lib/settings-ui.ahk:798`, dual-sync rule per CLAUDE.md) hardcode English filler lists ("um, uh, er...") and English slang whitelists (Casual mode). `lib/artifact-filter.ahk` hallucination phrase lists (`:33-49`, `:78-89`) are English-only; only the single-word fallback (`:65-69`) is language-agnostic. The E.2 cleanup harness (`tests/cleanup/`) is the regression gate for any prompt edit.

### Phase 1: Language auto-detect (S)
1. Factor the four language maps into one shared source (respect the two existing "keep in sync" comments; delete them once unified). Note `onboarding_ui.ahk` is a separate process; the share mechanism must work for both binaries (a lib include, like `lib/settings-ui.ahk` already is).
2. Add "Auto-detect" as the first option (`value="auto"`) in the settings dropdown and tray submenu; conditional-omit the `language` field in all three call sites.
3. Test: dictate in English and one non-English language you can fake (or use a saved corpus clip) with language=auto; confirm the request lacks the field (debug log) and transcription still lands.

### Phase 2: STT model picker (S)
1. Settings dropdown "Transcription model": Fast (whisper-large-v3-turbo, recommended) / Max accuracy (whisper-large-v3). Plain-English labels, Dad Test. Allow-list validation in `ParseConfig` (reject unknown values, fall back to turbo).
2. Wire through the existing config round-trip (`ParseConfig` string-keys table `QuickSay.ahk:1892-1902` pattern; settings save path in `lib/settings-ui.ahk`).
3. Run T2.6 corpus + E.2 cleanup harness against whisper-large-v3 with biasing on; record WER deltas in findings. If biasing misbehaves on v3, gate the bias prompt to turbo only and say so in findings.

### Phase 3: Friendly 429 handling (S)
1. In both HTTP helpers, detect status 429, read `retry-after`, and surface a plain-English tray/overlay message: "Groq's free-tier speed limit reached. Wait N seconds and try again." Distinguish from auth failures (401/403) and network errors.
2. Optional, if trivial: auto-retry ONCE after `retry-after` seconds for the LLM cleanup call only (never auto-retry the Whisper call: the user has moved on).
3. Add a probe to the existing HTTP-adjacent tests if a harness exists; otherwise document manual verification (mock via a local responder or by burst-triggering on a test key).

### Phase 4: Language-neutral cleanup prompts (S-M)
1. Rewrite the filler-removal instruction in all four mode prompts to be language-generic ("remove filler words and verbal tics in whatever language the transcript is in, such as...") while KEEPING the English examples as examples, not an exhaustive list. Both `GetDefaultModes()` copies, byte-identical.
2. Run the FULL E.2 cleanup harness; the guardrails (never answer, never inject) must stay green. Any regression: revert and record.
3. `artifact-filter.ahk` non-English hallucination phrases: add only well-documented Whisper artifacts for the top languages if sources exist; otherwise leave and file a findings note (do not invent phrase lists). Keep the PowerShell port (`tests/transcription/lib/hallucination.ps1`) in sync if touched.

### Done When
- [ ] One shared language map; "Auto-detect" works end to end (field absent on the wire, verified via debug log).
- [ ] Model picker ships with two validated options; T2.6 + cleanup harness results for whisper-large-v3 recorded in findings; bias-prompt decision documented.
- [ ] 429s show the friendly message with the retry-after value; 401/403 unchanged (existing error recovery flows intact).
- [ ] Mode prompts language-generalized in BOTH `GetDefaultModes()` copies; E.2 cleanup harness fully green; custom-mode migration note (users with saved old prompts) documented.
- [ ] All suites green (history 19, license, crash, telemetry, update, cleanup, dictionary, T2.6 corpus).
- [ ] Findings doc `C:\QuickSay\docs\audit-campaign\findings\F.2-quick-wins.md`; code PR from `feature/F.2-quick-wins`.

### What NOT to do
- Do not add languages beyond the existing 25 in this session (separate decision; the map refactor makes it trivial later).
- Do not expose a free-text model field; hard allow-list only.
- Do not enable the bias prompt on the file-transcription path (E.2 measured WER degradation; the comment at `QuickSay.ahk:1135-1138` stands).
- Do not touch the hotkey layer or recording pipeline (that is F.1's territory; keep the diff surface disjoint).
- Do not invent non-English hallucination phrase lists without a citable source.

### Estimated time
Phase 1: ~1 h. Phase 2: ~1 h (plus corpus runs). Phase 3: ~45 min. Phase 4: ~1 h. Total: ~3.5-4 h.

### When you're done, report back with
- WER table: turbo vs v3, bias on/off, T2.6 + spontaneous tiers.
- The exact new mode-prompt wording (for the user's sign-off, since it ships to all users).
- Whether 429 auto-retry was included or skipped, and why.
