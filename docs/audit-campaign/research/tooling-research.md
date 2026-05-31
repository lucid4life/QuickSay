# QuickSay Production-Hardening Tooling Research

_Research date: 2026-05-27. Scope: open-source tools to audit, lint, test, ship and monitor a Windows AutoHotkey v2 + WebView2 + Inno Setup desktop app._

---

## TL;DR — Top 12 Picks Ranked

| # | Pick | Topic | Why | Effort | Form |
|---|------|-------|-----|--------|------|
| 1 | **thqby/vscode-autohotkey2-lsp** | AHK lint/format | The de-facto AHK v2 language server. Lint, format, static analysis, signature help. Actively maintained. | S | Dev tool |
| 2 | **Playwright + CDP over WebView2** | WebView2 testing | Microsoft's officially documented path. Add `--remote-debugging-port` to WebView2 init and `connectOverCDP()`. | M | Test framework |
| 3 | **VolantisDev/ahk-testlib** | AHK testing | Modular, opinionated, AHK v2-native unit tests. Pair with `holy-tao/ahkunit` VS Code runner. | M | Library |
| 4 | **sentry-native + Crashpad** | Crash reporting | Industry standard. The `/minidump/` HTTP endpoint is callable directly from AHK via `HttpPostFile()` if you don't want the C SDK. | M | SaaS / library |
| 5 | **WinSparkle** | Auto-update | Battle-tested, Appcast XML, simple drop-in. Far less brittle than Squirrel.Windows (which is essentially abandoned). | M | Library |
| 6 | **Keygen.sh** (or self-host CF Workers + KV) | License keys | RESTful API, SOC 2 Type II as of Jan 2026, free tier. Or fork `lokst/license-key-generator` for self-host. | S–M | SaaS or self-host |
| 7 | **Azure Trusted Signing (OV-equivalent)** | Code signing | EV no longer buys SmartScreen reputation. Stay on Azure Trusted Signing; focus on download volume. | — | Already in use |
| 8 | **Mozilla Common Voice + LibriSpeech test-clean + whisper-hallucinations** | STT regression | Three corpora cover clean speech, accents, and silence/noise edge cases. | M | Dataset |
| 9 | **AutoHotUnit** | AHK testing (alt) | Has proper CI exit codes — useful in GitHub Actions if `ahk-testlib` proves too opinionated. | S | Library |
| 10 | **`iscc.exe /Qp` + custom precheck script** | Inno Setup audit | No real "iss-lint" exists. Write a PowerShell pre-flight that parses `Source:` lines and asserts each file exists. | S | Skill (Claude) |
| 11 | **mark-wiemer/ahkpp** (AHK++) | AHK alt lint/format | Backup if `thqby` LSP causes false positives. Less aggressive analysis. | S | Dev tool |
| 12 | **Microsoft Desktop App Certification checklist** | Production checklist | Old but still the most concrete Win32 readiness baseline. Pair with SmartScreen reputation guidance. | S | Documentation |

**Claude Code skill candidates:** #2 (`webview2-playwright-test`), #8 (`whisper-regression-suite`), #10 (`inno-setup-preflight`), and a meta-skill bundling #1 + #3 + #9 (`ahk-quality-gate`). The rest are libraries QuickSay imports or services it calls.

---

## 1. AutoHotkey v2 Quality Tools

The ecosystem is thin but functional. Almost everything centers on two competing VS Code language servers.

| Tool | URL | Stars (approx) | v2 support | Last activity | Verdict |
|---|---|---|---|---|---|
| **vscode-autohotkey2-lsp** (thqby) | https://github.com/thqby/vscode-autohotkey2-lsp | ~600 | Native v2 | Active 2026 | **Primary pick.** Real LSP — diagnostics, hover, signature help, format. CLI extraction possible. |
| **AHK++** (mark-wiemer/ahkpp) | https://github.com/mark-wiemer/ahkpp | ~250 | Both v1+v2 | Active 2026 | Backup. Formatter directives, lighter analysis. |
| **ahklint** (imaginationac) | https://github.com/imaginationac/ahklint | <50 | v1 only | Abandoned ~2014 | Skip. |
| **eight04/ahk-linter** | https://github.com/eight04/ahk-linter | <50 | v1, dev on hold | Abandoned | Skip — author redirects to thqby LSP. |
| **AutoHotKey-Script-Formatter** (TheMaster1127) | https://github.com/TheMaster1127/AutoHotKey-Script-Formatter | <50 | Both | Sporadic | Manual GUI — not CI-friendly. Skip. |

**Testing frameworks:**

| Tool | URL | v2 | CI exit codes | Verdict |
|---|---|---|---|---|
| **VolantisDev/ahk-testlib** | https://github.com/VolantisDev/ahk-testlib | Yes | Yes | **Primary pick.** Convention `*.test.ahk`, modular. |
| **joshuacc/AutoHotUnit** | https://github.com/joshuacc/AutoHotUnit | Yes | Yes (designed for GH Actions) | Strong backup. |
| **Uberi/Yunit** (v2 branch) | https://github.com/Uberi/Yunit | v2-beta+ | Partial | Mature but minimal. |
| **holy-tao/ahkunit** | https://github.com/holy-tao/ahkunit | Yes | — | VS Code runner UI on top of Yunit-style tests. |
| **Chunjee/assert.ahk** | https://github.com/Chunjee/assert.ahk | Yes | Yes | Assertion helpers — pair with one of above. |

**Dead-code detection:** No mature tool exists. The thqby LSP flags unused locals; for unused functions you'd write a regex sweep across `lib/*.ahk` against the call graph. Reasonable Claude skill: "scan AHK source for top-level functions never referenced."

**Integration effort:** S to add LSP + formatter as VS Code config; M to wire `ahk-testlib` into a GitHub Action.

---

## 2. WebView2 Testing

**Verdict: Playwright over CDP works in 2026 and is officially documented by Microsoft.**

Microsoft Learn publishes a step-by-step guide: https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/playwright

**Required app-side change:**
- Set `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` before `CoreWebView2Environment` creation, OR pass it through `EnsureCoreWebView2Async`. For QuickSay's `lib/WebView2.ahk` wrapper, this means setting the env var before COM init when `QUICKSAY_TEST_MODE=1`.
- Set a unique `WEBVIEW2_USER_DATA_FOLDER` per test to avoid cross-contamination.

**Connect side:**
```js
const browser = await chromium.connectOverCDP('http://localhost:9222');
const context = browser.contexts()[0];
const page = context.pages()[0];
```

**Alternative:** `Haprog/playwright-cdp` (https://github.com/Haprog/playwright-cdp) — minimal example of CDP→WebView2 from Tauri, directly applicable. ~30 stars but exactly the pattern you need.

**Inspector route:** Right-click → Inspect inside a WebView2 launches Edge DevTools — fine for manual debugging, but not scriptable. Use CDP for automation.

**Integration effort:** M — touching the AHK COM init path is the riskiest bit. One-time work, then settings/onboarding UIs are fully scriptable.

**This is a strong Claude Code skill candidate:** "Spin up QuickSay with debug port, run a Playwright script against the settings WebView, take screenshots, assert state."

---

## 3. Inno Setup Hardening / Audit

**No real linter exists.** No `iss-lint`, no static analyzer, no published GitHub topic. ISCC.exe will tell you about syntactically invalid scripts and missing `Source:` files at compile time, but only the ones it actually processes.

**What works:**
- `idleberg/sublime-innosetup` and `flycheck-innosetup.el` — syntax highlighting + parse errors, editor-only.
- `DomGries/InnoDependencyInstaller` (https://github.com/DomGries/InnoDependencyInstaller) — not lint, but the gold-standard dependency-bootstrap pattern (.NET, VC++, etc.). 1.6k stars, active.
- `teeks99/inno-test` — only useful as an example, not a framework.

**Practical audit approach (recommended):**
Write a PowerShell preflight that:
1. Parses `setup.iss` for `Source: "<path>"` patterns
2. Resolves each path against `Development/`
3. Fails fast if any file is missing
4. Runs ISCC with `/Qp` (quiet but show progress)
5. Performs a silent install (`installer.exe /VERYSILENT /SUPPRESSMSGBOXES /LOG=install.log`) into a sandbox dir
6. Verifies registry keys (`HKCU\Software\QuickSay`), uninstall entry, expected files at `%LOCALAPPDATA%\Programs\QuickSay Beta\`
7. Runs `unins000.exe /VERYSILENT` and asserts cleanup

This is exactly the kind of work that should become a **Claude Code skill** (`inno-setup-preflight`) — script lives in `Development/scripts/` and the skill knows how to run it.

**Integration effort:** S — a few hundred lines of PowerShell.

---

## 4. Windows Desktop App Production Checklists

**Microsoft does publish requirements**, but they're scattered across docs and partly archived:

- **SmartScreen reputation guidance** — https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation (the current, canonical doc)
- **Desktop certification requirements** — https://learn.microsoft.com/en-us/previous-versions/windows/win32/win_cert/certification-requirements-for-windows-desktop-apps (marked "previous-versions" but still the most concrete Win32 checklist)
- **Windows App Certification Kit (WACK)** — bundled with Windows SDK, runs static + dynamic checks on installed apps

**EV vs OV in 2026 — the answer has flipped:**
- Years ago, EV → instant SmartScreen reputation. **That is no longer true.**
- Microsoft now states (Q&A confirmed Feb 2026): reputation is per-hash + per-publisher and must be earned via downloads, EV or not.
- **Recommendation: stay on Azure Trusted Signing.** EV is no longer worth the premium for solo devs. The Azure Trusted Signing cert QuickSay already uses is functionally equivalent to OV for SmartScreen purposes — the differentiator is download volume, not cert type.

**Concrete checklist items to enforce:**
- Manifest declares supported Windows versions via GUIDs (Win10/Win11)
- DPI-aware manifest entry
- No `LoadLibrary` interception of system DLLs
- Consistent ProductName/ProductVersion across `QuickSay.exe`, installer, uninstaller
- Every binary signed with same cert (so Microsoft analytics groups them)
- Uninstaller removes all user data only with explicit consent

**Integration effort:** S — codify as a release-time checklist in `release.ps1` or as a Claude skill `production-readiness-audit`.

---

## 5. Crash Reporting / Telemetry

**The simplest "POST JSON to receive a crash" stack for a solo AHK dev:**

| Option | URL | Effort | Cost | Verdict |
|---|---|---|---|---|
| **Sentry `/minidump/` endpoint** | https://docs.sentry.io/platforms/native/guides/minidumps/ | M | Free tier 5k events/mo | **Primary pick.** Multipart POST — directly callable from `HttpPostFile()`. No SDK required. |
| **Sentry `/envelope/` endpoint (JSON)** | https://develop.sentry.dev/sdk/data-model/envelopes/ | M | Same | If you want JSON-only events (no minidumps), this is the path. |
| **sentry-native (C SDK + Crashpad)** | https://github.com/getsentry/sentry-native | L | Free tier | Heaviest. Wraps SEH, writes minidumps. Probably overkill for AHK. |
| **BugSplat** | https://www.bugsplat.com/ | M | Paid (no free tier for prod) | Strong on game/native; pricing is the blocker. |
| **Backtrace** | (Sauce Labs) | L | Enterprise pricing | Skip for solo dev. |
| **Self-host: CF Worker → R2 + Discord webhook** | — | M | Effectively free | Strong DIY option. Worker accepts POST, writes JSON to R2, pings Discord. ~50 lines. |

**Concrete AHK plan:**
- Wrap `QuickSay.ahk` top-level in `try/catch` and a global `OnError` handler.
- Build a JSON payload with `version`, `os`, `last action`, stack-ish info (`A_ThisFunc`, `A_LineFile`, `A_LineNumber`).
- `HttpPostFile()` to either Sentry envelope endpoint or a CF Worker.
- For true Win32 crashes (the AHK runtime itself dies), only Crashpad/Breakpad catches it. Probably not worth the effort yet.

**Sentry curl example (works from anywhere):**
```bash
curl -X POST "https://oXXX.ingest.sentry.io/api/PROJECT_ID/minidump/?sentry_key=YOUR_PUBLIC_KEY" \
  -F upload_file_minidump=@crash.dmp \
  -F 'sentry={"release":"quicksay@1.9.1","tags":{"hotkey_mode":"hold"}}'
```

**Integration effort:** M.

---

## 6. Auto-Update Mechanisms

QuickSay's current homegrown `version.json` check is fine functionally; the question is whether to invest in a framework.

| Tool | URL | Stars | Active | Verdict |
|---|---|---|---|---|
| **WinSparkle** | https://github.com/vslavik/winsparkle | ~850 | Yes (active author) | **Best fit.** Appcast XML, signature-verified, mature, lightweight. Callable from AHK via DllCall. |
| **Squirrel.Windows** | https://github.com/Squirrel/Squirrel.Windows | ~5.3k | Effectively abandoned (no commits in years) | Skip. Use Squirrel for Mac/Velopack only. |
| **NetSparkle** | https://github.com/NetSparkleUpdater/NetSparkle | ~1.4k | Yes | .NET only — not useful for AHK. |
| **Velopack** | https://github.com/velopack/velopack | ~3k | Yes | Squirrel's spiritual successor. Modern, cross-platform, but .NET-centric. |

**Recommendation:** Keep the homegrown check (it's working) but adopt WinSparkle's **Appcast XML format** as the wire schema. That gives you a migration path without ripping anything out. If/when you want UI polish, swap to WinSparkle proper — it's a single DLL with a DllCall surface AHK can hit.

**Integration effort:** S to adopt Appcast format; M to fully integrate WinSparkle.

---

## 7. License Key Validation

QuickSay is free today but the user is heading to production — license keys for a future paid tier are a likely need.

| Option | URL | Verdict |
|---|---|---|
| **Keygen.sh** | https://keygen.sh/ | **Primary pick.** SOC 2 Type II (Jan 2026), free tier, node-locked + floating + offline + subscription models, Go/Rust/C SDKs (callable from AHK via DllCall or just HTTP). |
| **Cryptolens** | https://help.cryptolens.io/ | Solid alternative; offline activation strong; pricing higher. |
| **Self-host: CF Workers + KV** | https://github.com/lokst/license-key-generator | **Reference repo exists** — fork it. ~$0/mo at QuickSay's scale. |
| **Easy Cloudflare KV** | https://mecanik.dev/en/products/easy-cloudflare-kv/ | Niche, fewer features than rolling your own. |

**Recommended pattern for QuickSay specifically:**

1. Issue keys: `QS-XXXX-XXXX-XXXX-XXXX` (Crockford base32)
2. CF Worker endpoint: `POST https://license.quicksay.app/v1/activate` with `{key, machine_id}` — machine_id is hashed Windows machine GUID
3. KV stores `key → {tier, max_activations, activations: [machine_id...]}`
4. On activation, Worker issues a signed JWT (Ed25519, 90-day expiry) — app caches it, re-validates monthly
5. Offline grace: JWT signature lets the app verify without re-contacting the server

This pattern is robust enough for an indie product and costs nothing on CF's free tier.

**Integration effort:** M for self-host; S for Keygen.sh.

---

## 8. Whisper STT Regression Testing

You need three buckets of audio to catch real-world bugs:

| Corpus | URL | Use |
|---|---|---|
| **LibriSpeech `test-clean`** (subset) | https://www.openslr.org/12 | Clean read speech, ~5 hours. Baseline WER tracking. |
| **Mozilla Common Voice** (English `dev`) | https://commonvoice.mozilla.org/en/datasets | Accents, age/gender variation. Subset 50–100 clips. |
| **sachaarbonel/whisper-hallucinations** | https://huggingface.co/datasets/sachaarbonel/whisper-hallucinations | 7,890 known-bad inputs (silence/noise → hallucinated text). Direct test for `IsWhisperHallucination()`. |
| **Synthetic silence/pure-noise** | self-generate via FFmpeg | Edge cases for the 500ms minimum / VAD path. |

**Recommended QuickSay regression suite layout:**
```
tests/audio/
  baseline/        # 20 LibriSpeech clips with known transcripts
  accents/         # 20 Common Voice clips (mixed)
  hallucination/   # 50 clips from whisper-hallucinations dataset
  edge/            # silence.wav, noise.wav, sub-500ms.wav, 5min-max.wav
expected.json      # ground truth transcripts
run-stt-regression.ps1  # POSTs each to Groq, computes WER, flags hallucinations
```

**Research backing:** Calm-Whisper (arxiv 2505.12969, May 2026) found 3 of 20 attention heads cause 75%+ of hallucinations. Validates the layered defense QuickSay already does (`IsWhisperHallucination()` + LLM cleanup).

**Strong Claude skill candidate:** `whisper-regression-suite` — knows the dataset, knows how to compute WER, knows how to flag regressions between QuickSay releases.

**Integration effort:** M — collecting and curating the corpus is the bulk.

---

## Sources

- https://github.com/thqby/vscode-autohotkey2-lsp
- https://github.com/mark-wiemer/ahkpp
- https://github.com/VolantisDev/ahk-testlib
- https://github.com/joshuacc/AutoHotUnit
- https://github.com/Uberi/Yunit
- https://github.com/holy-tao/ahkunit
- https://github.com/Chunjee/assert.ahk
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/playwright
- https://playwright.dev/docs/webview2
- https://github.com/Haprog/playwright-cdp
- https://github.com/DomGries/InnoDependencyInstaller
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- https://learn.microsoft.com/en-us/previous-versions/windows/win32/win_cert/certification-requirements-for-windows-desktop-apps
- https://docs.sentry.io/platforms/native/guides/minidumps/
- https://develop.sentry.dev/sdk/data-model/envelopes/
- https://github.com/getsentry/sentry-native
- https://winsparkle.org/
- https://github.com/vslavik/winsparkle
- https://github.com/NetSparkleUpdater/NetSparkle
- https://github.com/velopack/velopack
- https://keygen.sh/
- https://help.cryptolens.io/examples/key-verification
- https://github.com/lokst/license-key-generator
- https://www.openslr.org/12 (LibriSpeech)
- https://commonvoice.mozilla.org/en/datasets
- https://huggingface.co/datasets/sachaarbonel/whisper-hallucinations
- https://arxiv.org/abs/2505.12969 (Calm-Whisper)
