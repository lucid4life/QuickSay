# Session T2.4 — Crash Reporting via Sentry Envelope (BUILD)

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/T2.4-crash-reporting`
> **Parallel-safe with:** T2.2, T2.3, T2.5, T2.6, all of Track 1 (different files — you create `lib/crash-reporter.ahk` and add a handler + a settings toggle; no overlap with the paywall/worker/update sessions)
> **Depends on:** T2.1 (`docs/audit-campaign/specs/T2-production-systems-design.md` — the spec defines the opt-in copy, the Sentry DSN location, and the PII allowlist policy)
> **Blocks:** M.1 (integration wires crash reporting into the rc1 build)
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort high`. The build is mechanical, but the **PII scrub is security-critical** — do not rush Phase 4. There is no `xhigh` on Sonnet; `high` is correct.

---

## Prompt to paste

You are building QuickSay's crash/error reporting. When the app hits an unhandled error, it should send a scrubbed report to Sentry so production bugs are visible — **without ever leaking a single byte of user-sensitive data**. There is **no Sentry SDK for AutoHotkey**; you will POST directly to Sentry's **envelope endpoint** over HTTP (per the research). The reporting is **opt-in** (a first-run modal + a settings toggle) and **throttled** (max 5/hour).

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). It has no crash visibility today — a production AHK bug is invisible to the developer. Per the research, the cheapest robust path is a direct multipart/JSON POST to Sentry's `/api/{project}/envelope/` endpoint from AHK's existing `HttpPostFile()` / HTTP layer. No native SDK, no Crashpad (AHK runtime crashes that kill the process are out of scope — we capture AHK-level unhandled errors and exceptions via a global handler).

This data flows to a third party (Sentry). QuickSay's whole pitch is local-first privacy. **The PII scrub is the most important part of this session.** A crash report must NEVER contain: the Groq API key, the license JWT, transcript text, audio file paths, the Windows username, or the machine name. Strip all of these to placeholders before the envelope leaves the machine.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — file map, config system, DPAPI, `HttpPostFile()`/`HttpGet()` in `lib/http.ahk`, `EscapeJson()` utility (~line 1891), debug log location (`data/logs/debug.txt`), UX Priorities.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, §6 endpoints (`SENTRY_DSN` is a secret; only the project-public DSN, not auth), Status Tracker (update at end), risk register (Sentry rate-limit row → the 5/hr throttle).
3. `docs/audit-campaign/specs/T2-production-systems-design.md` — **the spec.** It defines: the exact opt-in modal copy, where the Sentry DSN lives (compiled constant vs config), and the PII allowlist policy. If the spec is missing or ambiguous on any of these, **stop and ask** before writing code.
4. `docs/audit-campaign/research/tooling-research.md` — §5 "Crash Reporting / Telemetry" (Sentry envelope endpoint is the pick; `HttpPostFile()` is directly usable; explicit allowlist of context fields, redact aggressively).
5. `docs/audit-campaign/research/competitor-backend-research.md` — §4 "Crash reporting" (Sentry envelope POST from AHK; PII-leak risk; "explicit allowlist of context fields, redact aggressively").
6. **Invoke the `quicksay-go-to-paid` skill** — it carries the exact Sentry envelope wire format and header/auth details. Use it as the source for the envelope structure; don't reinvent the format from memory.

### The Sentry envelope format (authoritative source = `quicksay-go-to-paid` skill)

A Sentry **envelope** is a newline-delimited body POSTed to:

```
POST https://oXXXXXX.ingest.sentry.io/api/{PROJECT_ID}/envelope/
```

with auth via the `X-Sentry-Auth` header (or `?sentry_key=` query param) carrying the **public** DSN key only. The body is:

```
{ "event_id": "<32-hex>", "sent_at": "<iso8601>" }\n          <- envelope header
{ "type": "event" }\n                                       <- item header
{ ...the error event JSON... }                              <- item payload
```

The error event payload contains `level`, `platform`, `release`, `environment`, `exception` (type + value), `tags`, `contexts`, `extra`, and `timestamp`. **Get the exact field shape from the `quicksay-go-to-paid` skill / Sentry envelope docs — do not approximate.** Verify your envelope is accepted by Sentry (Phase 5 sends a real test event).

### Scope — files you may create or touch

| File | Action | Why |
|---|---|---|
| `Development/lib/crash-reporter.ahk` | **CREATE** | The whole crash-reporting module: global handler hook, envelope builder, PII scrub, throttle, POST |
| `Development/QuickSay.ahk` | **MODIFY** | Install the global error handler (`OnError`) early in startup; wire opt-in state |
| `Development/lib/settings-ui.ahk` | **MODIFY** | Add the "Crash reporting" toggle handler (read/write config) |
| `Development/gui/settings.html` | **MODIFY** | Add the toggle UI in the Privacy/Advanced section |
| `Development/gui/crash-optin.html` (or reuse a modal in settings) | **CREATE if needed** | First-run opt-in modal — match `settings.css` design tokens |
| `Development/config.example.json` | **MODIFY** | Document new fields: `crashReportingEnabled`, `crashReportingPrompted` |
| `Development/tests/crash/*` | **CREATE** | PII-scrub unit tests + throttle test + envelope-shape test |

**Forbidden** (other sessions):
- `lib/license.ahk`, `gui/paywall.*` → T2.3
- `Backend/license-worker/*` → T2.2
- `release.ps1`, `version.json` signing → T1.6, T2.5
- `lib/http.ahk` core — you may **import/call** `HttpPostFile()`/`HttpGet()`, but do not modify them without explicit reason
- Telemetry / PostHog → T2.7 (optional, separate). Crash reporting ≠ analytics; do not bundle them.

### Phase 1 — Read the spec, lock the contract

Open `docs/audit-campaign/specs/T2-production-systems-design.md`. Confirm and write down:
- **Opt-in modal copy** (verbatim from the spec).
- **DSN location** — is the DSN a compiled constant in the AHK source, or read from config, or fetched? (Spec decides. The DSN public key is NOT a secret, but baking it in means it ships with the binary; follow the spec.)
- **Environment tag** — `beta` vs `production` (likely keyed off the release channel / version suffix).
- **PII allowlist** — the spec's explicit list of fields that ARE allowed in a report. Everything else is stripped. (See Phase 4 for the floor.)

If any of these are missing from the spec, ask the user — do not assume.

### Phase 2 — TDD: write the tests first

Invoke `superpowers:test-driven-development`.

Create `Development/tests/crash/` with a runner (`run-tests.ps1`) and these cases. Match whatever unit-test convention P0.2 settled on (e.g. `ahk-testlib` or inline asserts).

**PII-scrub tests (the critical ones):**
1. Envelope built from an error whose message contains a Groq API key (`gsk_...`) → the scrubbed envelope contains `[REDACTED_API_KEY]`, never the key.
2. Error message contains a license JWT (`eyJ...` three dot-separated base64 segments) → scrubbed to `[REDACTED_JWT]`.
3. Error context contains a file path with the Windows username (`C:\Users\abeek\...`) → username segment scrubbed to `C:\Users\[USER]\...`.
4. Error context contains an audio path (`...\data\audio\QS_20260527_1423.wav`) → path scrubbed / filename removed.
5. Error message contains transcript-looking free text passed as an "extra" → transcript fields are NEVER included (the builder only includes allowlisted context, so a transcript field simply isn't attached).
6. Machine name / computer name (`A_ComputerName`) is NOT present anywhere in the envelope.
7. **Grep gate:** given a fully-built envelope for a synthetic error stuffed with ALL of the above secrets, a regex sweep for `gsk_`, `eyJ`, the literal username, `.wav`, `A_ComputerName`'s value finds **zero** matches.

**Throttle tests:**
8. 5 reports in one hour → all 5 sent.
9. 6th report within the same hour → dropped (not sent), and the drop is noted in `debug.txt` when `debugLogging`.
10. After the hour window rolls, the counter resets and sending resumes.

**Opt-in gate tests:**
11. `crashReportingEnabled=false` → `ReportError()` is a no-op (no POST attempted).
12. `crashReportingEnabled=true` → `ReportError()` builds + attempts the POST.
13. Never-prompted state (`crashReportingPrompted=false`) → reporting defaults OFF until the user answers the modal (no silent sending before consent).

**Envelope-shape test:**
14. The built envelope parses: line 1 is valid JSON (envelope header w/ `event_id`), line 2 is `{"type":"event"}`, line 3 is valid JSON with `exception`, `release`, `environment`, `level`.

Run them — they MUST fail before implementation.

### Phase 3 — Implement `lib/crash-reporter.ahk`

Pure, testable functions. Suggested surface:

- `CrashReporter_Install()` — sets the global `OnError` handler (AHK v2 `OnError(callback)`) and a top-level `try/catch` wrapper guidance. Called once, early in `QuickSay.ahk` startup, BEFORE anything risky runs. The handler must itself be crash-safe (a bug in the reporter must never mask or replace the original error — log, attempt send, return to let AHK's default handling continue).
- `CrashReporter_BuildEnvelope(errObj, context)` → string. Builds the 3-line envelope. Uses the existing `EscapeJson()` for string embedding (CLAUDE.md says reuse it, don't hand-roll StrReplace chains).
- `CrashReporter_Scrub(text)` → string. The PII scrubber (Phase 4). Applied to EVERY string field before it enters the envelope.
- `CrashReporter_Send(envelope)` → bool. POSTs to the Sentry envelope endpoint via `HttpPostFile()`/`HttpGet()`-equivalent. Honors the throttle. Honors opt-in. Times out fast (≤5s) and never blocks the hot path / UI.
- `CrashReporter_ShouldSend()` → bool. Combines opt-in check + throttle check.
- Throttle state: a small ring (timestamps of the last sends) persisted in memory (and optionally a tiny file so throttle survives restart-loops — your call, document it). Max 5 in any rolling 60-minute window; drop excess.

Allowed context fields (the allowlist — see Phase 4): `release` (version), `os` (Windows version string, generic — e.g. "Windows 11 26200" — NOT the machine name), `environment` (`beta`/`production`), `hotkey_mode` (`hold`/`tap`), `last_action` (a coarse enum like `recording`/`transcribing`/`idle`/`paste` — NOT the content), `A_ThisFunc`/`A_LineFile`/`A_LineNumber` (code location — `A_LineFile` is a path; scrub the username from it).

### Phase 4 — PII scrub (security-critical)

Invoke the **security-auditor** review (the `comprehensive-review` security agent, or the `security-scanning` plugin's threat-modeling skill if active). PII review here is non-negotiable.

The scrub MUST strip (to placeholders) — this is the **floor**, the spec's allowlist refines it:

| Sensitive thing | Pattern | Replacement |
|---|---|---|
| Groq API key | `gsk_[A-Za-z0-9]+` (and any value read from `groqApiKey`) | `[REDACTED_API_KEY]` |
| License JWT | three base64url segments joined by `.` (`eyJ...\.[...]\.[...]`) | `[REDACTED_JWT]` |
| Windows username in paths | `C:\Users\<name>\` and `%USERPROFILE%` expansions | `C:\Users\[USER]\` |
| Audio file paths | `...\data\audio\QS_*.wav` | filename stripped → `[AUDIO_FILE]` |
| Transcript text | any field carrying transcribed content | **never attached** (omit, don't scrub) |
| Machine / computer name | `A_ComputerName` value | never attached |
| Full home dir / APPDATA paths | scrub the user segment | `[USER]` placeholder |

Design principle: **allowlist, not blocklist.** The envelope builder attaches ONLY the explicitly-allowed context fields. The `Scrub()` regex pass is a second line of defense for any free-text (the exception message, the code location path) that slips through. Both layers run.

Crucially: do not let the reporter READ `groqApiKey` at all unless you must — the less it touches secrets, the less it can leak. If the exception message happens to contain a key (e.g. an HTTP error echoed a header), the regex scrub catches it.

### Phase 5 — First-run opt-in modal + settings toggle

- **Opt-in modal:** On first run after this feature ships (`crashReportingPrompted=false`), show a small modal (use `settings.css` design tokens; match the paywall/onboarding visual language). Copy comes from the spec. Plain English, Dad Test: "Help us fix bugs? QuickSay can send anonymous crash reports (no transcripts, no audio, no personal info). [Yes, help out] [No thanks]". Whatever the user picks → set `crashReportingEnabled` accordingly and `crashReportingPrompted=true`. **Default OFF until answered** (no sending before consent).
- **Settings toggle:** Add a "Send anonymous crash reports" toggle in the Privacy/Advanced section of `gui/settings.html`, wired through `lib/settings-ui.ahk` to read/write `crashReportingEnabled` in config (atomic write + mutex). Flipping it OFF immediately stops all reporting. Flipping ON resumes.
- Document `crashReportingEnabled` and `crashReportingPrompted` in `config.example.json`.

### Phase 6 — Live verification

Invoke `superpowers:verification-before-completion`. Real evidence per gate.

1. **Real test event reaches Sentry:** With reporting opted-IN and the DSN configured, trigger a deliberate error — add a temporary `throw Error("T2.4 crash-reporting test")` behind a hidden tray-menu item or a test flag, run it, and confirm the event appears in the Sentry project dashboard **within 10 seconds**. Screenshot or paste the Sentry event ID. Remove the temporary throw.
2. **PII grep on the wire:** Capture the actual envelope bytes for a synthetic error stuffed with a fake API key + fake JWT + a user path + an audio path (write it to a file in the test, do NOT send real secrets). Grep the captured envelope for `gsk_`, `eyJ`, the username, `.wav`, the computer name → **zero matches**. Paste the grep result.
3. **Throttle holds:** Fire 6 errors in <1 min → exactly 5 envelopes sent, 6th dropped + logged. Paste the debug.txt lines.
4. **Opt-out honored:** Set `crashReportingEnabled=false`, fire an error → no POST attempted (assert via the test double / no network call). Set `crashReportingPrompted=false`, fire an error before answering the modal → no POST.
5. **No hot-path impact:** The reporter never blocks dictation. Confirm a normal record→transcribe→paste cycle is unaffected with reporting ON.
6. `code-review` on the diff; address P0/P1. Re-run the security-auditor on `Scrub()` specifically.

### Done When

- [ ] `lib/crash-reporter.ahk` exists: `Install`, `BuildEnvelope`, `Scrub`, `Send`, `ShouldSend`, throttle, all documented.
- [ ] Global `OnError` handler installed early in `QuickSay.ahk` startup; reporter is crash-safe (never masks the original error).
- [ ] Sentry envelope format matches the `quicksay-go-to-paid` skill / Sentry docs (proven by gate 1: a real test event appears in Sentry within 10s).
- [ ] PII scrub strips API key, JWT, username paths, audio paths; never attaches transcripts or machine name. **PII grep on the envelope is clean** (gate 2).
- [ ] Throttle caps at 5/hour, drops excess with a debug log (gate 3).
- [ ] Opt-in modal shows on first run (spec copy), defaults OFF until answered; settings toggle works; both `crashReportingEnabled`/`crashReportingPrompted` honored (gate 4).
- [ ] `config.example.json` documents the new fields.
- [ ] All 14 unit tests pass (`tests/crash/run-tests.ps1`).
- [ ] No regression: dictation works with reporting ON (gate 5).
- [ ] `code-review` + security-auditor re-run on `Scrub()`; P0/P1 addressed.
- [ ] Branch `audit/T2.4-crash-reporting` committed; PR opened against `main`.
- [ ] MASTER-PLAN.md Status Tracker updated: `T2.4 — Crash reporting` → ✅ done.

### What NOT to do

- ❌ Do not send anything before consent. `crashReportingEnabled` defaults OFF until the user answers the modal. No silent first-run sending.
- ❌ Do not include transcript text, audio bytes/paths, the Groq API key, the license JWT, the Windows username, or the machine name in any report — ever. Allowlist, not blocklist.
- ❌ Do not bundle a Sentry SDK or Crashpad/Breakpad. Direct envelope POST only (per research). True native-runtime crashes that kill the AHK process are explicitly out of scope.
- ❌ Do not block the dictation hot path or the UI on the network POST. Fast timeout, fire-and-forget, never `Sleep` the recording flow.
- ❌ Do not let a bug in the reporter swallow or replace the user's actual error. The handler logs + attempts send, then lets normal error handling proceed.
- ❌ Do not put the Sentry DSN secret-auth (the `sentry_secret`) anywhere. Only the **public** DSN key ships with the app (per MASTER-PLAN §6).
- ❌ Do not add product analytics / event tracking here. That's T2.7 (optional), a separate concern.
- ❌ Do not modify `lib/http.ahk` internals — call its functions.
- ❌ Do not exceed the throttle to "be safe" — 5/hr is the cap (MASTER-PLAN risk register: Sentry rate-limit flood).
- ❌ Do not refactor unrelated startup code "while you're in there." Flag via `spawn_task`.

### Estimated time

Phase 1 (spec): 15 min. Phase 2 (14 tests): 60 min. Phase 3 (module): 90 min. Phase 4 (scrub + security review): 60 min. Phase 5 (modal + toggle): 45 min. Phase 6 (live verification): 45 min. **Total wall-clock: ~5 hours.**

### When you're done

Report back with:
- The Sentry event ID + screenshot proving a real test event landed within 10s.
- The PII grep result on a synthetic-secrets envelope (must be zero matches) — paste it.
- The 14 test names + pass/fail (should be 14/14).
- The exact allowlist of fields the envelope carries.
- The opt-in modal copy you shipped (verbatim) and where the toggle lives in settings.
- Any ambiguity in T2.1's spec (opt-in copy / DSN location / allowlist) and how you resolved it.
- Anything out of scope you noticed — flag via `spawn_task`.
