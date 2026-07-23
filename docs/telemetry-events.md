# QuickSay Telemetry Events

**Default: OFF.** Telemetry is never sent until the user explicitly opts in via
Settings → Privacy → "Help improve QuickSay". Opting out stops all collection
immediately and regenerates the anonymous install ID so the timeline breaks.

**Backend:** PostHog HTTP capture API (no SDK). Direct `POST /capture/` from AHK
via WinHTTP COM — same mechanism as the Groq API calls in `lib/http.ahk`.
EU data residency endpoint (`eu.i.posthog.com`) to minimise data-transfer exposure.

**This document is the contract.** `lib/telemetry.ahk` enforces an allowlist —
it only emits events that appear below. Adding a new event requires updating this
doc first, then re-running the privacy audit.

---

## Events

### `app_started`

Fired once per tray-process launch (not when launched in `--settings` mode).

| Property | Type | Value / Buckets | Why we collect |
|---|---|---|---|
| `app_version` | string | e.g. `"1.9.0"` | Know which versions are live in the field |
| `os_build_bucket` | string | `"11"` or `"10"` | Understand Windows version distribution |
| `install_id` | string | anonymous UUID (§ Install ID) | Group sessions per install without identifying the user |

---

### `recording_completed`

Fired after a dictation is delivered to the cursor (successful transcription +
paste). Never fired for recordings that are too short, rejected, or errored.

| Property | Type | Value / Buckets | Why we collect |
|---|---|---|---|
| `duration_bucket` | string | `"<5s"` · `"5-15s"` · `"15-60s"` · `">60s"` | Understand typical recording lengths; NEVER the raw millisecond value |
| `llm_cleanup_enabled` | boolean | `true` / `false` | Measure AI-cleanup adoption |
| `mode` | string | `"Standard"` · `"Email"` · `"Code"` · `"Casual"` | Know which preset modes are used most; NEVER custom-mode text or a mode ID that could reveal a custom name |

**Duration bucket boundaries (ms):**

| Bucket | Range |
|---|---|
| `"<5s"` | 0 – 4 999 ms |
| `"5-15s"` | 5 000 – 14 999 ms |
| `"15-60s"` | 15 000 – 59 999 ms |
| `">60s"` | ≥ 60 000 ms |

**Mode** is the display name of the active preset. If the active mode is a
user-created custom mode, `mode` is emitted as `"custom"` (not the custom name).

---

### `settings_changed`

Fired when the user saves a changed setting from the Settings window.
Emitted with the list of changed setting key **names** only — never the values.

| Property | Type | Value | Why we collect |
|---|---|---|---|
| `changed_keys` | string[] | e.g. `["soundTheme", "hotkeyMode"]` | Understand which settings users adjust most |

**Allowlisted keys** (the only keys that may appear in `changed_keys`):

```
soundTheme  hotkeyMode  playSounds  showOverlay  enableLLMCleanup
autoRemoveFillers  smartPunctuation  debugLogging  recordingQuality
launchAtStartup  saveAudioRecordings  historyRetention  accessibilityMode
autoPaste  stickyMode  contextAwareModes  showWidget  currentMode
```

Keys not in this list are silently dropped from `changed_keys`. If `changed_keys`
is empty after filtering, the `settings_changed` event is not emitted.

**Never included in `changed_keys`:**
`groqApiKey`, `licenseJwt`, `telemetryInstallId`, `trialMachineId`, `modes`
(custom mode definitions), `dictionary`, `audioDevice`, `crashReportingEnabled`,
`crashReportingPrompted`, and any key not in the allowlist above.

---

### `crash_reported`

Fired alongside a Sentry crash-report dispatch (T2.4). Only fired if both
crash-reporting AND telemetry are enabled. Provides aggregate error-category
counts in PostHog to complement the Sentry detail view.

| Property | Type | Value | Why we collect |
|---|---|---|---|
| `error_category` | string | `"recording_error"` · `"transcription_error"` · `"ui_error"` · `"update_error"` · `"unknown_error"` | Count crash category frequency for prioritisation |

NEVER includes: the error message, the transcript, a file path containing a
username, or any field from the Sentry envelope's free-text fields.

---

### `update_check`

Fired each time the app checks for updates (on silent startup check and on
manual "Check for Updates" menu click).

| Property | Type | Value | Why we collect |
|---|---|---|---|
| `current_version` | string | e.g. `"1.9.0"` | Know which versions are still in the field |
| `update_available` | boolean | `true` / `false` | Measure how many installs are running an outdated version |

---

### `update_installed`

Fired when the user clicks "Yes" to the "Download update?" prompt and the
browser-open is executed. Indicates *intent* to install (best-effort — the
app opens a browser; it does not execute the installer directly in v2.0).

| Property | Type | Value | Why we collect |
|---|---|---|---|
| `from_version` | string | e.g. `"1.9.0"` | Know which version triggered the update |
| `to_version` | string | e.g. `"2.0.0"` | Know which version was the target |

---

## What is NEVER sent

Under any circumstance — regardless of opt-in state — these are never included:

- Transcript text (`finalText`, `rawText`) or any substring of a dictation
- Audio file paths or audio content
- Custom dictionary entries (spoken word or replacement)
- History file contents
- License key or license JWT
- Buyer email address or any email address
- Groq API key (or any API key)
- Machine name (`A_ComputerName`), Windows username (`A_UserName`)
- Full file paths containing a username
- MAC address or hardware identifiers
- IP address (PostHog may log this server-side; use of the EU endpoint means
  data is stored in the EU under GDPR-compliant terms)

---

## Anonymous Install ID

`Telemetry_GetOrCreateInstallId()` generates a random UUID (via `CoCreateGuid`)
on the first opt-in and stores it as `telemetryInstallId` in `config.json`.

Properties:
- **Not** the `trialMachineId` (no correlation to license or trial identity)
- **Not** derived from MAC address, Windows ProductID, username, or any
  machine attribute — random UUID only
- **Regenerated** each time the user turns telemetry off and back on, so
  opting out genuinely breaks the event timeline
- Stored in plaintext in `config.json` (it is intentionally anonymous and
  not a secret; it cannot be used to identify a person)

---

## Technical: PostHog payload shape

```http
POST https://eu.i.posthog.com/capture/
Content-Type: application/json

{
  "api_key": "<POSTHOG_PROJECT_KEY>",
  "event": "<event_name>",
  "properties": {
    "distinct_id": "<telemetryInstallId>",
    ... event-specific properties from the tables above ...
  },
  "timestamp": "<ISO 8601 UTC, e.g. 2026-06-04T15:30:00Z>"
}
```

`POSTHOG_PROJECT_KEY` is the **public capture key** (safe to embed in the
binary — it can only *write* events, not read them). Never the PostHog
admin token or personal API key.

Events are queued in memory (max 20) and flushed by a deferred `SetTimer`
(≥ 30 s between flushes). A network failure is swallowed silently — telemetry
never blocks or slows the dictation hot path.
