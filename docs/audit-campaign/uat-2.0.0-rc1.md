# QuickSay v2.0.0-rc1 — Manual UAT Checklist

> **Build:** v2.0.0-rc1 (signed) — binary `localVersion` = `2.0.0`; installer `QuickSay_Beta_v2.0_Setup.exe` (Azure-signed, ~30.5 MB), `version.json` Ed25519-signed (key `qs-2026`). rc1 is an **internal** build (not published to R2 / GitHub).
> **License endpoint:** **STAGING** — the app points at `https://license-staging.quicksay.app` (NOT production). All trial/activation traffic in this UAT hits staging. M.3 flips it to `license.quicksay.app`.
> **Date prepared:** 2026-06-06
> **Prepared by:** M.2 (script written by Claude; **executed by the user on a fresh VM**).
>
> **Run on a FRESH Windows VM** (Windows Sandbox or a clean Hyper-V VM / clean local Windows user account). Estimated total: **~45–60 min**.
>
> **GATE (MASTER-PLAN §7):** Launch (M.3) does **not** proceed until **every item is PASS or explicitly WAIVED with a written reason** in the Result Summary. A dev-box "pass" does not count — the whole point is a machine that has never seen QuickSay.

---

## ⚠️ Read before you start — two blockers the preparer flagged

1. **🔴 Item 13 (license activation) is BLOCKED until the LemonSqueezy test store is wired.**
   The staging Worker's `LEMONSQUEEZY_API_KEY` is still a **placeholder** (T2.2 README §"Before the `/activate` end-to-end works"), and **no staging test license key has been recorded anywhere** (the README still shows `<FILL IN>`). As deployed, `/activate` returns **`403 invalid` for *any* key**. Until someone (a) sets a real **test-mode** LS API key on the staging Worker, (b) creates a QuickSay test product + test license key in LemonSqueezy test mode, and (c) records that key in this doc's pre-flight, **Item 13's happy path cannot pass.** See Item 13 for what to do (provision first, or WAIVE with reason).

2. **🟡 Microphone-dependent items (6, 7, 8, 9, 11) need a real mic in the VM.**
   **Windows Sandbox does not expose an audio input device by default**, so dictation will not work there. For the dictation items use a **Hyper-V VM with microphone pass-through enabled**, or a **fresh local Windows user account on physical hardware**. (Items 1–5, 10, 12, 13, 14 do not need a mic and run fine in Sandbox.)

---

## Pre-flight (VM setup)

**P-1. VM requirements**
- Windows 10 (1809+) or Windows 11, x64.
- For dictation items: a working microphone (see blocker #2 above).
- Internet access (the app contacts the staging license Worker for trial-status + pricing + activation).
- WebView2 runtime: the installer bundles + installs it if missing — no manual step.

**P-2. Get the build onto the VM**
- Copy the signed rc1 installer to the VM Desktop:
  - Source on the dev box: `C:\QuickSay\Development\installer\QuickSay_Beta_v2.0_Setup.exe`
  - (Confirm it is the M.1-signed artifact: right-click → Properties → Digital Signatures shows publisher **QuickSay**.)

**P-3. Get the staging test license key (for Item 13)**
- Record it here before you start: **Staging test license key: `____________________________`**  `[CONFIRM — not yet provisioned; see blocker #1]`
- Format will look like `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`. This is a **TEST** key and only works against the **staging** Worker.

**P-4. Confirm NO prior QuickSay residue (clean room)** — open PowerShell in the VM and run:
```powershell
# All four must be ABSENT on a truly clean machine:
Test-Path "$env:LOCALAPPDATA\Programs\QuickSay Beta"          # program files   → expect False
Test-Path "$env:APPDATA\QuickSay"                             # user data + license.dat → expect False
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name QuickSay -EA SilentlyContinue  # autorun → expect error/blank
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -EA SilentlyContinue | Where-Object { $_.GetValue('DisplayName') -like 'QuickSay*' }  # uninstall entry → expect nothing
```
If any returns `True` / a value, this is not a clean machine — reset the VM before proceeding.

**Reference — where things live once installed (compiled build):**
| What | Path |
|---|---|
| Program files | `%LOCALAPPDATA%\Programs\QuickSay Beta\` (`{autopf}\QuickSay Beta` for a per-user install) |
| Config / dictionary | `%APPDATA%\QuickSay\config.json`, `…\dictionary.json` |
| History / stats / audio / logs / onboarding marker | `%APPDATA%\QuickSay\data\` |
| License + trial state | `%APPDATA%\QuickSay\license.dat` (**DPAPI-encrypted** — cannot be hand-edited) |
| Autorun (when enabled) | `HKCU\…\CurrentVersion\Run\QuickSay` |

**Default hotkey:** hold **Ctrl+Win**, speak, release (hold mode). 14-day trial.

---

## The 14 items

> Ordered for natural state build: clean install → onboarding → use during trial → expiry/paywall/activation → uninstall. Each item maps 1:1 to a required UAT topic (coverage map in the Result Summary). Each takes < 5 min.

### Item 1 — Clean install (no prior residue)
- **Why it matters:** The installer is the very first thing every paying customer touches; it must land files correctly and register cleanly on a machine that has never seen QuickSay.
- **Setup:** Clean VM with no QuickSay residue (pre-flight P-4 all absent). Installer copied to Desktop (P-2).
- **Action:**
  1. Double-click `QuickSay_Beta_v2.0_Setup.exe`.
  2. Observe the SmartScreen / UAC behavior on launch (note exactly what appears).
  3. Complete the wizard with default options (do **not** finish onboarding yet — that's Item 2; if it offers "Run mic check and setup" at the end, leave it ticked).
  4. After it finishes, in PowerShell run:
     ```powershell
     Test-Path "$env:LOCALAPPDATA\Programs\QuickSay Beta\QuickSay.exe"   # expect True
     (Get-AuthenticodeSignature "$env:LOCALAPPDATA\Programs\QuickSay Beta\QuickSay.exe").Status   # expect Valid
     Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" | Where-Object { $_.GetValue('DisplayName') -like 'QuickSay*' } | ForEach-Object { $_.GetValue('DisplayName') }   # expect "QuickSay Beta"
     ```
- **Expected:**
  - Installer runs to completion; `QuickSay.exe` exists at the path above; its signature is **Valid** and the publisher shown is **QuickSay**.
  - An uninstall entry **"QuickSay Beta"** is registered.
  - **SmartScreen:** a "Windows protected your PC" **warning that you can click through** (More info → Run anyway) is **acceptable — note it**. A **hard block with no run-anyway option is a FAIL.** (Reputation is earned by download volume; a signed-but-low-reputation warning is expected pre-launch.)
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 2 — Onboarding wizard end-to-end
- **Why it matters:** First-run is where a non-technical user either succeeds or gives up (the "Dad Test"). The API-key step must read as plain English, not jargon.
- **Setup:** Item 1 complete; onboarding has not been run (marker absent).
- **Action:**
  1. Let the onboarding wizard launch (or Start menu → **QuickSay** → it runs the wizard on first run).
  2. Walk through every step: connection/API-key entry, microphone check, hotkey practice (if present), and Finish.
  3. For the key step, paste a **valid Groq API key** when asked (you need one for the dictation items; a free key from the Groq console works).
  4. After Finish, in PowerShell:
     ```powershell
     Test-Path "$env:APPDATA\QuickSay\data\onboarding_done"   # expect True
     ```
- **Expected:**
  - The wizard completes without errors; the tray icon appears afterward.
  - The key step uses **plain-English framing** (e.g. "free AI account" / "connection key"), not raw "API key / LLM" jargon `[CONFIRM exact wording against gui/onboarding.html]`.
  - A mic check and (if present) a hotkey-practice step appear.
  - The `onboarding_done` marker file now exists at `%APPDATA%\QuickSay\data\`.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 3 — Trial countdown shows the expected days
- **Why it matters:** The trial is the core of the paid model; on a fresh install the user must see they have ~14 days, and the nudge must not appear too early.
- **Setup:** Items 1–2 complete; this is a fresh trial (just installed today).
- **Action:**
  1. Open **Settings** (tray icon → Settings, or the tray menu).
  2. Go to the **License** tab.
  3. Read the trial status / countdown.
- **Expected:**
  - The License tab shows an **active trial with ~14 days remaining** (13–14 depending on the hour).
  - The trial **countdown banner / TrayTip does NOT appear yet** — by design it only starts at **day 11 of 14 (≤ 4 days remaining)**, once per launch (T2.3 decision U2). On day-0 you should see the calm License-tab countdown only, no nag.
  - A **"🔑 License / Unlock…"** affordance is available in the tray menu from day 1 (T2.3 U3).
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 4 — Dictation in Notepad
- **Why it matters:** Typing the transcript at the cursor is the entire product. This is the non-negotiable core path.
- **Setup:** Trial active (Item 3); a working mic; Notepad open with the cursor in the text area.
- **Action:**
  1. Open **Notepad** and click into the blank document.
  2. **Hold Ctrl+Win**, clearly say: *"The quick brown fox jumps over the lazy dog."*, then **release**.
  3. Wait for processing.
- **Expected:** The sentence (or a faithful transcription of it) is typed into Notepad at the cursor within a few seconds. The recording widget appeared while holding and dismissed on release.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 5 — Dictation in Chrome
- **Why it matters:** Most users dictate into a browser; SendInput must land text into web inputs the same as native fields.
- **Setup:** Trial active; mic working; Chrome (or Edge) open.
- **Action:**
  1. Open Chrome, click into the **address bar** *or* a text box (e.g. the search field on a blank Google page).
  2. **Hold Ctrl+Win**, say: *"Testing dictation inside the browser."*, **release**.
- **Expected:** The transcript appears in the focused browser field, correct and complete.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 6 — Dictation in a terminal (Shift+Insert paste path)
- **Why it matters:** Terminals reject the normal paste path; QuickSay uses **Shift+Insert** for terminal windows (CLAUDE.md). This verifies that special path lands.
- **Setup:** Trial active; mic working.
- **Action:**
  1. Open **Windows Terminal** (or PowerShell). Click into the prompt.
  2. **Hold Ctrl+Win**, say: *"echo hello from the terminal"*, **release**.
- **Expected:** The transcript appears at the terminal prompt (typed via the Shift+Insert path), correct and complete — no missing/garbled characters, no silent failure.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 7 — Audio device switch (FFmpeg path)
- **Why it matters:** Windows MCI only captures the default mic; a non-default device uses the bundled FFmpeg dshow path. This proves that path works end-to-end.
- **Setup:** Trial active; the VM/host has **at least two input devices** (or one non-default named device). If only one mic exists, mark this item **N/A — single device** and note it.
- **Action:**
  1. Settings → audio/microphone setting → select a **non-default** input device (a named device, not "Default").
  2. Save / close settings.
  3. Open Notepad, **hold Ctrl+Win**, say: *"Recording through the selected microphone."*, **release**.
- **Expected:** Transcription still works with the newly selected device (the FFmpeg `-f dshow` capture path). Transcript is correct.
- **Pass / Fail:** ☐ Pass  ☐ Fail  ☐ N/A (single device)
- **Notes:** _______________________________________________

### Item 8 — Settings persistence across restart
- **Why it matters:** Settings that silently reset destroy trust. Config must survive a full app restart.
- **Setup:** Trial active; app running.
- **Action:**
  1. In Settings, change **three** distinct things: e.g. **Sound theme** (pick a different theme), **Hotkey mode** (hold ↔ tap), and any one **toggle** (e.g. an AI-cleanup or startup toggle). Note what you set.
  2. Fully **exit** QuickSay (tray icon → **Exit** — not just close the window).
  3. Relaunch QuickSay from the Start menu.
  4. Reopen Settings.
- **Expected:** All three changes are still applied exactly as you left them. (Optional cross-check: `%APPDATA%\QuickSay\config.json` reflects the changes.)
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 9 — History retention enforcement (T1.5 fix) + clear-history race
- **Why it matters:** A shipped regression here means unbounded history growth or "ghost" entries reappearing after a clear. This proves the T1.5 fixes are in the build.
- **Setup:** Trial active; mic working.
- **Action (retention cap):**
  1. Set history retention to **3**. Use the Settings **History retention** control if present `[CONFIRM control exists]`; otherwise close the app, edit `%APPDATA%\QuickSay\config.json` to set `"historyRetention": 3`, save, relaunch.
  2. Dictate **5** short phrases (e.g. "one", "two", "three", "four", "five"), one per hold-release.
  3. Open the **History** view in Settings and count the entries.
- **Expected (retention):** Only the **3 most recent** entries remain ("three", "four", "five"); the two oldest were dropped (not the newest).
- **Action (clear-history race):**
  4. Click **Clear history** in Settings.
  5. Immediately dictate **one** new phrase (e.g. "after clear").
  6. Re-open the History view.
- **Expected (race):** History shows **only** the single new "after clear" entry. The previously cleared entries do **NOT** reappear (the T1.5 resurrection race is fixed).
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 10 — Hotkey collision warning (T1.7)
- **Why it matters:** If a chosen hotkey is already taken, the app must say so clearly instead of silently never recording.
- **Setup:** App running (trial active is fine).
- **Action:**
  1. Settings → hotkey setting → change the hotkey to something likely to collide / be Windows-reserved (e.g. **Win+L**, or another combo the OS owns), and save.
- **Expected:** The app shows a **clear conflict warning** (a banner / alert in Settings, and/or on the onboarding "Done" step) explaining the hotkey can't be used — rather than silently accepting a dead hotkey. After observing, **set the hotkey back to Ctrl+Win** for the remaining items.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 11 — Accessibility: full keyboard navigation (T1.7)
- **Why it matters:** Keyboard-only and screen-reader users must be able to operate every setting. Proves the T1.7 a11y work shipped.
- **Setup:** Settings window open; **do not touch the mouse** for this item.
- **Action:**
  1. From the Settings window, press **Tab** / **Shift+Tab** to move through every control; use **Enter** / **Space** to activate buttons, toggles, and dropdowns.
  2. Try to reach and operate: each tab, every toggle, the dropdowns, the text inputs, and the legal/footer links.
- **Expected:**
  - **Every** interactive control is reachable and operable by keyboard alone.
  - **Focus is always visibly indicated** (a clear focus ring/outline on the focused control).
  - There's a working **skip link** / logical focus order; no control is a keyboard trap.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 12 — Paywall on trial expiry
- **Why it matters:** When the trial ends, recording must be gated behind the paywall — but the app must still open so the user can buy. This is the monetization gate.
- **Setup:** Trial currently active. `license.dat` is **DPAPI-encrypted and cannot be hand-edited**, so expiry is induced via the **system clock** (the app records `trialStartedAt` at real install time; jumping the clock forward past 14 days expires it; the clock-rollback guard means this can't be "undone" by moving back).
- **Action:**
  1. Fully **exit** QuickSay (tray → Exit).
  2. Windows **Settings → Time & language → Date & time** → turn **OFF** "Set time automatically", then **Set the date manually** to **15 days in the future**.
  3. **Relaunch** QuickSay from the Start menu.
  4. Press and hold **Ctrl+Win** and try to dictate.
  5. When the paywall appears, **close** it (X), then press **Ctrl+Win** again.
- **Expected:**
  - On the first hotkey press, recording is **refused** and a **paywall window** appears: *"Your free trial has ended,"* with a price line and a **"Get my license"** button (price is fetched live from staging `GET /pricing` — expect *"$39 USD · one-time, lifetime — Launch price: N left"*).
  - **Closing the paywall does NOT enable recording**; pressing the hotkey again **re-shows the paywall** (gate is on recording, not the window — T2.3 U1).
  - **Settings, the tray menu, and the paywall itself still open** — only recording is blocked.
  - (Leave the clock forward — Item 13 activates while expired. You'll restore the clock after Item 13.)
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

### Item 13 — License activation with the STAGING test key
- **Why it matters:** The purchase-to-unlock path is how every customer gets out of the paywall. This verifies activation against the **staging** Worker end-to-end. **(Uses STAGING — `license-staging.quicksay.app`, not production.)**
- **Setup:** Item 12 done — app is in the paywall (TRIAL_EXPIRED, recording blocked), clock still +15 days. You have the staging test key from pre-flight P-3.
- **🔴 Precondition (see blocker #1):** This item **cannot pass** unless the staging Worker has a real **test-mode** `LEMONSQUEEZY_API_KEY` and a recorded test key. With the placeholder still in place, `/activate` returns **403** for any key, so you'll see the graceful error path, **not** the unlock. If the key isn't provisioned yet → **WAIVE this item with the reason "staging LS test store not yet provisioned (T2.2 README §activate)"**, and re-run it once it is.
- **Action:**
  1. In the paywall, click **"I already purchased — enter my license key."**
  2. Paste the **staging test license key** (P-3) into the input.
  3. Click **Activate**.
- **Expected (happy path, once provisioned):**
  - Activation succeeds; a *"QuickSay is now licensed. Thank you!"* confirmation appears; the **paywall dismisses**; pressing **Ctrl+Win** now records normally (recording restored, state **LICENSED**).
  - Settings → License tab now shows a **licensed** status (not trial).
- **Expected (not-yet-provisioned, current state):** A clear, friendly error like *"Activation failed (error 403). Please try again, or email support@quicksay.app."* — the error path works, but the happy path is unverified → item is **WAIVED/blocked** per the precondition.
- **After this item:** restore the clock — Windows **Date & time** → turn **"Set time automatically"** back **ON**.
- **Pass / Fail:** ☐ Pass  ☐ Fail  ☐ WAIVED (reason: ________________)
- **Notes:** _______________________________________________

### Item 14 — Clean uninstall (no residue, user data per policy)
- **Why it matters:** A messy uninstall (ghost autorun, leftover program files) erodes trust and trips antivirus heuristics. User data + license must be handled per the documented policy.
- **Setup:** App installed; close QuickSay first is not required (the uninstaller stops it), but exiting via the tray first is cleaner.
- **Action:**
  1. Uninstall via **Settings → Apps → Installed apps → QuickSay Beta → Uninstall** (or run `unins000.exe` in the program folder). Use the standard uninstaller.
  2. After it finishes, in PowerShell:
     ```powershell
     Test-Path "$env:LOCALAPPDATA\Programs\QuickSay Beta"                          # program files → expect False
     Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name QuickSay -EA SilentlyContinue   # autorun → expect error/blank (GONE)
     Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" | Where-Object { $_.GetValue('DisplayName') -like 'QuickSay*' }   # uninstall entry → expect nothing
     Test-Path "$env:APPDATA\QuickSay\license.dat"                                 # license/trial → expect True (PRESERVED by design)
     Test-Path "$env:APPDATA\QuickSay\config.json"                                # user config → expect True (PRESERVED)
     ```
- **Expected — what should be GONE:**
  - Program files at `%LOCALAPPDATA%\Programs\QuickSay Beta\` — **removed**.
  - The `HKCU\…\Run\QuickSay` autorun value — **removed** (T1.3-025 fix; no ghost autorun pointing at a deleted exe).
  - Start-menu / startup / desktop shortcuts — **removed**.
  - The **"QuickSay Beta"** uninstall registry entry — **gone**.
- **Expected — what should REMAIN (documented policy):**
  - `%APPDATA%\QuickSay\` is **intentionally left intact** — including `license.dat` (so the trial can't be reset by reinstalling — anti-abuse), plus `config.json`, `dictionary.json`, and `data\` (history/stats). rc1 has **no in-uninstaller "also remove my data" checkbox** — that user-facing data-removal affordance is an M.3 item `[CONFIRM: confirm rc1 leaves all of %APPDATA%\QuickSay\ with no removal prompt]`.
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _______________________________________________

---

## Result Summary

**Coverage map (all 14 required topics present):**
| Required topic | Item # |
|---|---|
| Clean install | 1 |
| Onboarding wizard | 2 |
| Trial countdown | 3 |
| Dictation — Notepad | 4 |
| Dictation — Chrome | 5 |
| Dictation — terminal | 6 |
| Audio device switch | 7 |
| Settings persistence | 8 |
| History retention + race | 9 |
| Hotkey collision warning | 10 |
| Accessibility keyboard nav | 11 |
| Paywall on expiry | 12 |
| License activation (staging key) | 13 |
| Clean uninstall | 14 |

**Tally:** _____ / 14 PASS · _____ FAIL · _____ WAIVED · _____ N/A

**Blockers found (must be empty or fully waived before M.3):**
- _______________________________________________
- _______________________________________________

**`[CONFIRM]` items resolved before/while running (preparer flagged these):**
- Item 2 — exact plain-English key-step wording in `gui/onboarding.html`.
- Item 9 — whether a History-retention control exists in Settings (else use the `config.json` edit).
- Item 13 — **staging LS test store + test license key must be provisioned** (blocker #1) — else WAIVE.
- Item 14 — confirm rc1 leaves all of `%APPDATA%\QuickSay\` with no in-uninstaller removal prompt.

**Gate decision (MASTER-PLAN §7):**
- ☐ **PASS — cleared for M.3** (every item PASS, or WAIVED with a written reason below).
- ☐ **BLOCKED — do not launch** (one or more unwaived FAILs).

**Written waivers (item # + reason + who approved):**
- _______________________________________________

**Sign-off:** Tester ____________________   Date __________   Build: v2.0.0-rc1 (staging)

---

### One-line instruction to start
> Spin up a fresh Windows VM (Hyper-V with mic pass-through for the dictation items; Windows Sandbox is fine for the non-mic items), copy `C:\QuickSay\Development\installer\QuickSay_Beta_v2.0_Setup.exe` to it, fill in the staging test license key in Pre-flight P-3 (provision it first — blocker #1), then work Items 1→14 top to bottom. rc1 talks to the **staging** license worker, not production.
