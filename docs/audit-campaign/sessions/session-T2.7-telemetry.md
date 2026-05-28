# Session T2.7 — Opt-In PostHog Telemetry (BUILD) — **OPTIONAL**

> ⚠️ **OPTIONAL SESSION.** Only run this if the user explicitly wants opt-in telemetry shipped *before* launch. It is NOT on the critical path to v2.0.0. The MASTER-PLAN lists it as optional (session 19). If launch is the priority, skip this and run it post-launch. **Confirm with the user that they want this before starting.**

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/T2.7-telemetry`
> **Parallel-safe with:** all other Track 2 sessions (different new file + isolated emit points), all of Track 1
> **Depends on:** T2.1 (the spec locks telemetry as OFF-by-default, PostHog, aggregate-only — implement to that contract). Soft-depends on T1.1 findings for the exact emit-point locations.
> **Blocks:** nothing (leaf feature).
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort high`, AND confirm the user actually wants telemetry pre-launch.

---

## Prompt to paste

You are building QuickSay's **opt-in, off-by-default** product telemetry. The entire design philosophy is: privacy is part of QuickSay's marketing positioning ("zero telemetry" is literally on the website today), so this feature must be (a) off unless the user explicitly turns it on, (b) aggregate and anonymous only, and (c) auditable — a privacy-conscious user can read exactly what is sent. If you cannot make a privacy reviewer comfortable, do not ship it.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). It currently sends **zero** telemetry — the website advertises "zero telemetry." This session adds **opt-in** analytics via **PostHog's HTTP capture API** (no SDK — direct POST from AHK, same pattern as the Groq API calls). Default is **OFF**. The toggle lives in settings with a clear, honest label. Aggregate anonymized events only — never anything that could identify a user or reveal what they dictated.

The indie archetype (SuperWhisper advertises "no usage tracking"; Whispering ships a user-toggleable `analytics.ts`; Wispr uses PostHog) supports opt-in PostHog with a visible event list as the privacy-respecting norm. This must match that norm or exceed it.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — `EscapeJson()`, `AtomicWriteFile()`, config mutex, `HttpPostFile`/`lib/http.ahk`, config field normalization (snake_case external / camelCase internal), the IPC `0x5555` reload model.
2. `C:\QuickSay\docs\audit-campaign\MASTER-PLAN.md` — for the Status Tracker.
3. `C:\QuickSay\docs\audit-campaign\specs\T2-production-systems-design.md` — telemetry is OFF-by-default, PostHog HTTP, aggregate-only. Honor whatever contract the spec sets (config field name, opt-in UX touchpoint).
4. `C:\QuickSay\docs\audit-campaign\research\competitor-backend-research.md` — §4 telemetry section (the event allowlist + "default OFF for the EU/CCPA win" + "document every event") and the §1 table (SuperWhisper "no usage tracking", Whispering's auditable `analytics.ts`).
5. The `quicksay-go-to-paid` skill — invoke it. The "Telemetry — OFF by default" locked decision and the PII scrub discipline from the Sentry section apply here too.
6. Memory note: the Website CLAUDE.md says brand voice uses **"zero telemetry"** — so if telemetry ships, the website copy will need updating (that's M.3's problem, but FLAG it; do not change the website here).

Use `context7` to pull current PostHog **capture API** docs (the `/capture/` and/or `/i/v0/e/` endpoint, payload shape, `distinct_id` semantics) before writing the POST.

### The privacy contract (non-negotiable)

**Events allowed (aggregate, anonymized):**
- `app_started` — props: app version, OS build bucket, install-id (anonymous, see below).
- `recording_completed` — props: **duration bucket** (e.g. `<5s`, `5-15s`, `15-60s`, `>60s` — NEVER the raw duration if it could fingerprint, and NEVER the transcript), llm_cleanup_enabled (bool), mode (the preset name like "Standard"/"Email" — NOT custom mode text).
- `settings_changed` — props: which setting key changed (e.g. `soundTheme`, `hotkeyMode`) — NEVER the value if the value is PII-adjacent (never the API key, never custom dictionary content, never a custom hotkey string that could fingerprint).
- `crash_reported` — props: error class/category only (coordinate with T2.4's scrub list — never the message if it could contain a transcript).
- `update_check` / `update_installed` — props: from-version, to-version.

**NEVER sent, under any circumstance:**
- Transcript text (`finalText`, `rawText`) or any substring of it.
- Audio file paths or audio content.
- Custom dictionary entries (spoken or written).
- History contents.
- License key or license JWT.
- Email address.
- Groq API key.
- Machine name, username, full file paths, MAC address.

**Anonymous install id:** a random UUID generated once on first opt-in, stored in config, never derived from machine id / MAC / email. It is NOT the trial `trialMachineId` and must not be correlatable to it. If telemetry is turned off and back on, regenerate it (so opt-out genuinely breaks the timeline).

### Scope — files you create or touch

| File | Action | Why |
|---|---|---|
| `Development/lib/telemetry.ahk` | **CREATE** | The whole telemetry module: opt-in gate, event allowlist, payload builder (with scrub), batched/throttled PostHog POST, anonymous install-id management |
| `Development/QuickSay.ahk` | **MODIFY** | Add the minimal emit calls at the allowed event points (app start, recording complete, update check/installed). Each call is a one-liner that no-ops when telemetry is off. |
| `Development/lib/settings-ui.ahk` | **MODIFY** | Handle the settings toggle action; emit `settings_changed` (allowlisted keys only) |
| `Development/gui/settings.html` | **MODIFY** | Add the toggle UI: clear honest label + a "what we collect" disclosure listing the exact event names |
| `Development/config.example.json` | **MODIFY** | Document the new fields (`telemetryEnabled` default false, `telemetryInstallId` empty) with comments |
| `Development/tests/telemetry/*` | **CREATE** | Unit tests: off-by-default, scrub, allowlist enforcement, install-id behavior, throttle |
| `Development/docs/telemetry-events.md` | **CREATE** | The committed, human-readable list of every event + every property (the auditable surface, per research §4) |

**Forbidden:**
- ❌ `Development/setup.iss`, `release.ps1` — installer/release changes belong to M.1/M.3.
- ❌ `Backend/license-worker/*` (T2.2), `Website/*` (M.3), the crash module owned by T2.4 (you may *coordinate* the scrub list with it but do not edit its files).
- ❌ `lib/http.ahk` core (import it, don't modify it without explicit reason).

### Phase 1 — Plan + write the auditable event doc first

Write `Development/docs/telemetry-events.md` BEFORE writing code. List every event, every property, the exact bucket boundaries, and a one-line "why we collect this." This doc is the contract; the code must not emit anything not in this doc. If you later find you need a property that isn't here, you add it here first (and re-check it against the privacy contract).

Confirm the config field name + opt-in UX touchpoint against the T2.1 spec. If they differ, the spec wins — flag the difference to the user.

### Phase 2 — Tests first

Invoke `superpowers:test-driven-development`. Test list (`Development/tests/telemetry/`):
1. Telemetry OFF by default on fresh config → `EmitEvent("app_started")` makes NO HTTP call.
2. Telemetry ON → `EmitEvent("app_started")` builds a payload and would POST (mock the POST; assert payload shape).
3. Payload NEVER contains: a transcript string passed in, the API key, the email, a file path, the machine name, the MAC. (Feed each as a tempting field and assert it's scrubbed/absent.)
4. Event allowlist: `EmitEvent("some_unlisted_event")` is rejected/no-op (can't accidentally ship a new event without adding it to the allowlist + doc).
5. `recording_completed` sends a duration **bucket**, never the raw ms.
6. `settings_changed` sends the key name but NOT a disallowed value (e.g. changing the API key emits `settings_changed{key:"groqApiKey"}` with NO value).
7. Anonymous install-id: generated once on first opt-in; stable while on; regenerated if toggled off→on.
8. install-id is NOT equal to `trialMachineId` and is not derived from MAC/ProductID.
9. Throttle/batch: rapid events don't fire one POST each (define the batching/throttle policy and assert it).
10. Network failure on POST is swallowed — telemetry NEVER blocks or breaks dictation.

Run them; they must fail before implementation.

### Phase 3 — Implement `lib/telemetry.ahk`

- `TelemetryEnabled()` — reads config; the master gate. Every public function checks it first and no-ops if off.
- `GetOrCreateInstallId()` — random UUID, stored in config, regenerated on off→on transition.
- `EmitEvent(name, props := Map())` — (1) gate check, (2) allowlist check against the events in `telemetry-events.md`, (3) scrub props through a deny-list + bucket transforms, (4) enqueue, (5) throttled flush via existing `SetTimer` (no new thread/process).
- `FlushTelemetry()` — builds the PostHog capture payload (use `EscapeJson` for strings), POSTs via `lib/http.ahk`, swallows all errors. Never on the dictation hot path — defer like the existing history/stats writes.
- Scrub helpers — a hard deny-list (api key, jwt, email, transcript, paths, machine name, MAC) plus the duration→bucket and value→omit transforms.

Wire the emit points in `QuickSay.ahk` as minimal one-liners at: app start, recording complete (with the duration bucket + mode + llm flag), update check, update installed. Each is a no-op when off.

### Phase 4 — Settings UI

- A toggle in settings (Processing or a new Privacy section — match the existing tab structure you find). Label honestly: e.g. **"Help improve QuickSay — send anonymous usage stats (off by default)"**.
- A disclosure ("What's collected?") that lists the exact event names and links/points to `telemetry-events.md`. No dark patterns — the OFF state must be the obvious default and toggling on is a deliberate act.
- Wire the toggle through the existing WebView2 action → `settings-ui.ahk` → config write (AtomicWriteFile + mutex) → `0x5555` reload so the tray process picks up the new state. On enabling, generate the install-id. On disabling, stop emitting immediately and regenerate the install-id next time it's enabled.

### Phase 5 — Privacy audit

Invoke `ai-privacy-assessment` AND `security-auditor` over the diff and a captured sample payload. The audit must confirm:
- [ ] Off by default — fresh install sends nothing until the user opts in.
- [ ] Captured a real sample payload (with telemetry on, do an app_started + a recording_completed) and inspected it: contains NO transcript, no PII, no API key, no email, no paths, no machine name/MAC.
- [ ] Every emitted event is in `telemetry-events.md`; nothing emits that isn't documented.
- [ ] install-id is anonymous and uncorrelated to license/trial identity.
- [ ] Opt-out genuinely stops all collection (no residual POSTs after toggle off).
- [ ] PostHog endpoint + project key are the only telemetry destination; the project key is the public capture key (safe in the binary), never a personal/admin PostHog token.

### Done When

- [ ] `Development/docs/telemetry-events.md` exists and lists every event + property.
- [ ] `lib/telemetry.ahk` implemented: gate, install-id, allowlist, scrub, throttled POST.
- [ ] Emit points wired in `QuickSay.ahk` (no-op when off, off the hot path).
- [ ] Settings toggle + honest label + "what's collected" disclosure shipped; defaults OFF.
- [ ] All 10 unit tests pass (`tests/telemetry/run-tests.ps1` or the harness P0.2 settled on).
- [ ] Privacy audit (`ai-privacy-assessment` + `security-auditor`) passes; sample payload inspected and clean.
- [ ] `config.example.json` documents `telemetryEnabled` (false) + `telemetryInstallId` (empty).
- [ ] No regressions: dictation works identically with telemetry on AND off; a POST failure never breaks recording.
- [ ] FLAG for M.3: the website says "zero telemetry" — if this ships, that copy needs revisiting. (Do NOT change the website here; just note it in your report and consider `spawn_task`.)
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: T2.7 → ✅ (or note it was skipped if the user declines).
- [ ] Branch `audit/T2.7-telemetry` committed (use `commit-commands:commit`). PR opened against `main`.

### What NOT to do

- ❌ Do not ship telemetry ON by default. Ever. Off is the only acceptable default.
- ❌ Do not send transcript text, audio, dictionary, history, email, license key, API key, machine name, username, MAC, or full paths. Not even hashed.
- ❌ Do not use a PostHog SDK or add a heavy dependency. Direct HTTP POST via the existing `lib/http.ahk`.
- ❌ Do not emit any event that isn't in `telemetry-events.md`.
- ❌ Do not derive the install-id from machine id, MAC, ProductID, or email. Random UUID only.
- ❌ Do not put telemetry on the dictation hot path or let a network failure break/slow recording.
- ❌ Do not edit the website (the "zero telemetry" copy is M.3's call) or the crash module (T2.4).
- ❌ Do not commit a personal/admin PostHog API token — only the public capture/project key.

### Estimated time

Phase 1 (event doc + plan): 30 min. Phase 2 (tests): 45 min. Phase 3 (module): 90 min. Phase 4 (settings UI): 45 min. Phase 5 (privacy audit): 30 min. **Total wall-clock: ~3.5–4 hours.**

### When you're done

Report back with:
- A captured sample payload (the actual JSON sent for `app_started` + `recording_completed`) so the user can eyeball it.
- The full event list from `telemetry-events.md`.
- Confirmation that fresh-install sends nothing and opt-out stops everything.
- The privacy-audit outcome.
- The "zero telemetry" website-copy flag for M.3, and whether you filed a `spawn_task` for it.
