# Session T2.5 — Signed Updates (Ed25519) (BUILD)

> **Model:** Opus 4.7
> **Effort:** xhigh
> **Switch commands:** `/model opus` then `/effort xhigh`
> **Branch:** `audit/T2.5-signed-updates`
> **Parallel-safe with:** T2.2, T2.3, T2.4, T2.6, all of Track 1 (different files — you touch `release.ps1`'s sign step and `QuickSay.ahk`'s verify step; coordinate with T1.6 if it's mid-flight on `release.ps1`)
> **Depends on:** T2.1 (`docs/audit-campaign/specs/T2-production-systems-design.md` — defines the Ed25519 key format, key rotation policy, the `keyId` scheme, and where the private key lives). Also coordinate with **T1.6** (it refactors `release.ps1` around `VERSION` + `--check-sync`; your sign step plugs into the same pipeline).
> **Blocks:** M.1 (integration ships signed updates in rc1).
>
> Before pasting this prompt: confirm `/model opus` (no `[1m]` — scope is bounded to two files + a key) and `/effort xhigh`. This is **security-critical cryptography** wired into the release pipeline. A mistake here means either (a) updates can be hijacked, or (b) the update channel bricks for all users. Do not rush.

---

## Prompt to paste

You are hardening QuickSay's auto-update channel so the app will only install an update it can **cryptographically prove came from you**. Today `CheckForUpdates()` fetches `https://quicksay.app/version.json` and trusts it blindly — anyone who can MITM the connection or get write access to the R2 bucket can serve a malicious "update." You will fix this by signing `version.json` with **Ed25519** during `release.ps1`, and verifying that signature inside `CheckForUpdates()` before the app trusts a single field. Unsigned or tampered manifests are rejected.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). Auto-update flow today (read it first):
- `CheckForUpdates(silent)` in `QuickSay.ahk` (~line 3392) does `HttpGet("https://quicksay.app/version.json", 10)`, parses `version`, `download_url`/`url`, and `changelog`, then `CompareVersions(localVersion, remoteVersion)` (~line 3454), and if newer offers a download (opens `download_url` in browser after an `^https://` check, ~line 3475).
- `release.ps1` (in `Development/`) writes `version.json` and uploads it to R2 during a release.
- There is **no signature anywhere**. The `^https://` URL check is the only "security."

The research (`competitor-backend-research.md` §4 "Updates") explicitly recommends: *"keep `version.json` on R2; add SHA-256 + Ed25519 signature... ship a signature field so the app verifies the installer hasn't been tampered with. Future-proofs against R2 ACL mistakes."* That is exactly this session.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — file map, `release.ps1` role, Azure signing (note: that's binary code-signing, a SEPARATE mechanism from this manifest signing), `CheckForUpdates()`, IPC.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, §6 (`ED25519_PRIVATE_KEY` is a CF secret that signs JWTs AND version.json), risk register ("Ed25519 private key loss → key in CF secret store + offline backup"), Status Tracker.
3. `docs/audit-campaign/specs/T2-production-systems-design.md` — **the spec.** It defines the Ed25519 key pair, the key-rotation policy, the `keyId` scheme, and where the private key lives. **If the spec doesn't pin down key format, rotation, or storage, stop and ask** — you must not invent a key-management policy that diverges from the worker's (T2.2) signing.
4. `docs/audit-campaign/research/tooling-research.md` — §6 (auto-update; WinSparkle's signed Appcast is the reference pattern; keep the homegrown check but add the signature).
5. `docs/audit-campaign/research/competitor-backend-research.md` — §4 "Updates" (the SHA-256 + Ed25519 recommendation).
6. **Invoke the `quicksay-go-to-paid` skill** and the **security-auditor** (`comprehensive-review` security agent or `security-scanning` threat-modeling skill if active). Crypto correctness review is mandatory.

### The threat model (write this down before coding — `ultrathink` it)

`ultrathink` — enumerate the attacks the signature must stop and the ones it does NOT:

- **Stops:** R2 bucket write-compromise serving a malicious `version.json`; MITM rewriting the manifest in flight; a typo/ACL mistake exposing the bucket; an attacker pointing the app at a fake `download_url`.
- **Must also cover the installer, not just the manifest:** signing only `version.json` lets an attacker keep a valid manifest but swap the installer at `download_url`. So the manifest must also commit to the **SHA-256 of the installer**, and the app (or the user, with a documented step) must verify the downloaded installer's hash matches the signed manifest. The Azure code-signing on the .exe is a second, independent layer (and is what SmartScreen sees) — note the relationship but don't conflate them.
- **Does NOT stop:** a compromised signing key. Hence key storage + rotation matter (Phase 5). If the private key leaks, signatures are worthless — that's why it lives in a secret store with an offline backup, never in the repo.
- **Does NOT stop:** the app being patched on disk by local malware (out of scope — that's an OS-integrity problem).

Write a short threat-model memo to `docs/audit-campaign/findings/T2.5-threat-model.md` before writing code.

### What you're building

**1. Signed `version.json` schema** (extend, don't break the existing parse):

```json
{
  "version": "2.0.0",
  "download_url": "https://.../QuickSay-Setup-2.0.0.exe",
  "changelog": ["...", "..."],
  "installer_sha256": "<hex sha256 of the installer at download_url>",
  "released_at": "2026-..T..Z",
  "keyId": "qs-update-2026",
  "signature": "<base64 Ed25519 signature over the canonical signed payload>"
}
```

- The **signed payload** is a canonical serialization of the manifest fields EXCEPT `signature` itself (define the canonicalization precisely — e.g. a specific field order, or sign a separate compact JSON string that the app reconstructs identically). Pin this down so signer and verifier agree byte-for-byte. The cleanest approach: build a canonical string (sorted keys, no whitespace) of `{version, download_url, changelog, installer_sha256, released_at, keyId}`, sign THAT, and the verifier rebuilds the same string. Document the exact recipe.
- `keyId` lets you rotate keys: the app can ship more than one trusted public key and pick by `keyId`.

**2. `release.ps1` sign step:**
- After the installer is built (so its SHA-256 is final), compute `installer_sha256`.
- Build the canonical signed payload, sign it with the Ed25519 **private key**, base64 the signature, write the full signed `version.json`, then upload to R2.
- The private key is read from a **secret** at sign time — NOT from the repo. Acceptable sources (spec decides): an environment variable populated from the CF secret store / a local secret manager, or a key file path that is `.gitignore`d and lives outside the repo. The script must FAIL LOUDLY if the key is absent (no unsigned release).
- Coordinate with T1.6: if T1.6 has refactored `release.ps1` around `VERSION` and `--check-sync`, plug the sign step in after the build + before the upload, reusing its structure.

**3. `QuickSay.ahk` verify step in `CheckForUpdates()`:**
- The Ed25519 **public key(s)** are compiled into `QuickSay.ahk` as a constant map `keyId → publicKeyBytes` (the spec says "public key compiled into QuickSay.ahk constant"). This is the trust anchor.
- After fetching `version.json`: rebuild the canonical payload, verify the `signature` against the public key matching `keyId`. Ed25519 verification in AHK: use the Windows **CNG/BCrypt** API via `DllCall` (`BCryptOpenAlgorithmProvider`/`BCryptImportKeyPair`/`BCryptVerifySignature` with the ECC/Ed25519 algorithm), OR a vetted pure-AHK Ed25519 if one exists in the bundled libs. **Verify which is actually available on the target Windows versions** — Ed25519 in CNG requires Windows build support; if it's not universally available, the spec may dictate a fallback (e.g. signify-style or an embedded constant-time verify). Confirm against the target OS floor (Win10/Win11 per the manifest) before locking the approach. Document your choice and its OS requirements.
- If the signature is **missing, malformed, or invalid**, or `keyId` is unknown: treat the manifest as untrusted → set the equivalent of `UpdateAvailable=false`, do NOT offer the download, and **log the reason** (gated by `debugLogging`, plus a generic non-alarming TrayTip only on a manual check). The app must fail **closed** (no update) — never fail open.
- On valid signature: proceed with the existing `CompareVersions` flow. If an update is offered and downloaded, the installer's SHA-256 should be checkable against `installer_sha256` (document the verification step; if the app only opens the URL in a browser today rather than downloading itself, at minimum surface/log the expected hash and note the gap for M.1 to close if it adds in-app download).

### Scope — files you may create or touch

| File | Action | Why |
|---|---|---|
| `Development/release.ps1` | **MODIFY** | Add the sign step (compute installer SHA-256, build canonical payload, Ed25519-sign, write signed version.json) |
| `Development/QuickSay.ahk` | **MODIFY** | Add signature verification in `CheckForUpdates()`; embed the public key(s) constant |
| `Development/lib/update-verify.ahk` | **CREATE (optional)** | If the Ed25519 verify logic is sizable, factor it into its own module imported by QuickSay.ahk |
| `version.json` schema | **DEFINE** | The new `installer_sha256`, `keyId`, `signature` fields (documented in the threat-model memo + CLAUDE.md) |
| `Development/tests/update/*` | **CREATE** | Sign→verify round-trip + tamper-rejection tests |
| `docs/audit-campaign/findings/T2.5-threat-model.md` | **CREATE** | The Phase-0 threat-model memo |

**Forbidden** (other sessions):
- `lib/license.ahk`, `gui/paywall.*` → T2.3 (note: license JWT signing also uses Ed25519 — SAME key family per MASTER-PLAN §6; coordinate the keyId scheme with T2.1's spec, but do NOT implement license verification here)
- `Backend/license-worker/*` → T2.2
- `lib/crash-reporter.ahk` → T2.4
- `Development/VERSION`, `--check-sync` → T1.6 (you call into the pipeline T1.6 builds; don't reimplement it)

### Phase 0 — Sync, read spec, write threat model

```powershell
git fetch origin
git checkout -b audit/T2.5-signed-updates origin/main
```

Read the T2.1 spec's signing section. Confirm: Ed25519 key format (raw 32-byte vs PKCS#8/SPKI), the `keyId` scheme, key storage, and rotation policy. If the spec is silent on any, **ask the user**. Then `ultrathink` the threat model and write `docs/audit-campaign/findings/T2.5-threat-model.md` (the bullets above, fleshed out).

### Phase 1 — Decide the Ed25519 verify mechanism (the riskiest call)

Before writing the verifier, **prove** which Ed25519 implementation works on the target OS:
- Test `BCrypt` CNG Ed25519 availability on the dev machine and confirm the minimum Windows build that supports it. If the app's supported-OS floor (Win10) doesn't reliably have CNG Ed25519, you need a fallback (vetted pure-AHK/embedded verifier, or have the spec switch the algorithm).
- Write a tiny spike: sign a known message with a known key (via a reference tool — e.g. `openssl`/`ssh-keygen`/a Python one-liner) and verify it in AHK. Get a green round-trip on a KNOWN-ANSWER test vector (use RFC 8032 test vectors) BEFORE building anything around it. A crypto verifier that "looks right" but fails on a known vector is worthless.

Record the chosen mechanism + its OS requirement in the threat-model memo.

### Phase 2 — TDD

Invoke `superpowers:test-driven-development`. Create `Development/tests/update/` with a runner and:

1. **Round-trip:** sign a sample manifest with the test private key → verify with the corresponding public key → accepted.
2. **Tampered version:** flip one char of `version` in a signed manifest → verification FAILS → app treats as no-update (`UpdateAvailable=false`) + logs reason.
3. **Tampered download_url:** change `download_url` → verification FAILS.
4. **Tampered installer_sha256:** change the hash → verification FAILS.
5. **Stripped signature:** remove the `signature` field → rejected (fail closed).
6. **Wrong key:** sign with key A, verify against key B → rejected.
7. **Unknown keyId:** `keyId` not in the app's trusted map → rejected.
8. **RFC 8032 known-answer vector:** the verifier accepts the canonical Ed25519 test vector (proves the implementation is correct, not just self-consistent).
9. **Canonicalization stability:** signer's canonical payload and verifier's reconstructed payload are byte-identical for the same manifest (the classic break point — assert it).
10. **No regression — valid update path:** a properly signed manifest with a newer version → `CheckForUpdates` offers the update exactly as before.
11. **No regression — same/older version:** signed manifest, version ≤ local → "you're up to date," no offer.

Tests MUST fail before implementation.

### Phase 3 — Implement the verifier (app side)

Build `CheckForUpdates()`'s verification (in `QuickSay.ahk` or `lib/update-verify.ahk`):
- Embed the trusted public key(s) as a `keyId → base64 publicKey` constant. Document where the matching private key lives (secret store, NOT repo).
- Parse manifest → look up `keyId` → if unknown, reject. Rebuild canonical payload → `BCryptVerifySignature` (or chosen mechanism) → on fail, reject (fail closed, log reason). On pass, continue to `CompareVersions`.
- Every rejection path logs a specific reason to `data/logs/debug.txt` when `debugLogging` (e.g. `update rejected: signature invalid`, `update rejected: unknown keyId qs-old`). The user-facing message stays generic ("Could not verify the update. Please download from quicksay.app.") to avoid leaking detail to an attacker probing the check.

### Phase 4 — Implement the signer (release side)

Add the sign step to `release.ps1`:
- Read the private key from the secret source (env var / key file outside repo). **Fail loudly** if absent.
- Compute `installer_sha256` of the freshly built installer.
- Build the canonical payload (the documented recipe — match the verifier exactly), Ed25519-sign it, base64 the signature.
- Write the complete signed `version.json` (with `installer_sha256`, `keyId`, `signature`), then upload to R2.
- PowerShell Ed25519 signing: use `dotnet`/.NET `System.Security.Cryptography` if available, or `openssl`, or a vetted CLI — whatever the dev environment reliably has. Document the dependency. Confirm the signature it produces verifies in the AHK verifier (close the loop with a real generated manifest in Phase 6).

### Phase 5 — Key management (no key in git)

- The Ed25519 **private key** must NOT be committed. Add the key file pattern to `.gitignore`. The canonical home is the CF secret store (it's the same key that signs JWTs per MASTER-PLAN §6) with an **offline backup** (1Password or equivalent — per the risk register). Document the storage + the offline-backup requirement in the threat-model memo and CLAUDE.md.
- The **public** key(s) ARE in the repo (compiled into `QuickSay.ahk`) — that's the trust anchor and is meant to be public.
- Document the **rotation** procedure (from the spec): generate a new keypair → add the new public key to the app's trusted map under a new `keyId` → ship that app version → start signing with the new key → retire the old `keyId` once enough users have upgraded. The multi-key map is what makes rotation non-breaking.

### Phase 6 — Verification

Invoke `superpowers:verification-before-completion`. Real evidence per gate.

1. **Tampered manifest rejected (end-to-end):** Take a real signed `version.json`, flip one byte, run the app's `CheckForUpdates` against it → `UpdateAvailable=false` (no download offered) + the rejection reason logged in `debug.txt`. Paste the log line.
2. **Valid signed manifest accepted:** A properly signed manifest with a newer version → update offered normally. Confirm.
3. **Real cross-tool round-trip:** Sign a manifest with `release.ps1`'s actual signer, verify it with the actual AHK verifier (not just the test double) → accepted. This proves PowerShell-signer and AHK-verifier agree on canonicalization + key format. Paste the result.
4. **Key not in git:** `git log --all -S "<a distinctive fragment of the private key>"` returns **nothing**, and `git ls-files | findstr -i "key\|.pem\|.priv"` shows no private key committed. Paste both. (Use a harmless fragment for the search — do NOT paste the actual private key into the transcript.)
5. **Fail-closed proof:** Remove the `signature` field entirely → app rejects (no update). Unknown `keyId` → rejected.
6. **All 11 unit tests pass** (`tests/update/run-tests.ps1`).
7. `code-review` + security-auditor on the diff — crypto correctness, canonicalization, key handling, fail-closed behavior. Address every finding.

### Done When

- [ ] `docs/audit-campaign/findings/T2.5-threat-model.md` written (Phase 0).
- [ ] `version.json` schema extended with `installer_sha256`, `keyId`, `signature`; canonicalization recipe documented (signer ≡ verifier byte-for-byte).
- [ ] `release.ps1` signs `version.json` with Ed25519 from a secret (NOT repo), computes `installer_sha256`, fails loudly if the key is absent.
- [ ] `CheckForUpdates()` verifies the signature against a compiled-in public key before trusting any field; **fails closed** on missing/invalid/unknown-keyId; logs the reason.
- [ ] Tampered manifest → rejected (`UpdateAvailable=false` + logged) — proven (gate 1). Valid signed → accepted (gate 2).
- [ ] Real signer↔verifier round-trip passes (gate 3). RFC 8032 known-answer vector passes (test 8).
- [ ] Private key is NOT in git (`git log --all -S` clean — gate 4); public key is compiled in; rotation procedure documented.
- [ ] All 11 unit tests pass.
- [ ] No regression in the normal update path (newer → offer; same/older → up-to-date).
- [ ] `code-review` + security-auditor run; all findings addressed.
- [ ] Branch `audit/T2.5-signed-updates` committed; PR opened against `main`.
- [ ] MASTER-PLAN.md Status Tracker updated: `T2.5 — Signed updates` → ✅ done.

### What NOT to do

- ❌ Do not commit the private key, ever. Not in `release.ps1`, not in a config, not in a test fixture that ships. The test keypair lives outside the repo or is generated at test time.
- ❌ Do not fail OPEN. If verification can't run (no public key, parse error, unknown keyId, crypto error), the answer is **no update** — never "trust it anyway."
- ❌ Do not invent a key format / rotation policy that diverges from T2.1's spec and T2.2's worker. The Ed25519 key signs BOTH JWTs and version.json (MASTER-PLAN §6) — the `keyId` scheme must be consistent.
- ❌ Do not ship a hand-rolled Ed25519 unless it passes the RFC 8032 known-answer vector. Prefer the OS CNG/BCrypt API or a vetted implementation.
- ❌ Do not sign only the manifest and ignore the installer — the manifest must commit to `installer_sha256` so an attacker can't swap the installer behind a valid manifest.
- ❌ Do not leak the rejection reason to a remote attacker in the user-facing message — keep it generic; log detail locally only.
- ❌ Do not break the existing `version.json` parse for older app versions still in the wild (they ignore the new fields; that's fine — they just don't verify, which is the pre-T2.5 status quo). New fields are additive.
- ❌ Do not implement license-JWT verification here — that's T2.3, even though it shares the key.
- ❌ Do not refactor unrelated `release.ps1` or `CheckForUpdates` logic. Flag via `spawn_task`.

### Estimated time

Phase 0 (sync + spec + threat model): 45 min. Phase 1 (verify-mechanism spike + KAT): 60 min. Phase 2 (11 tests): 60 min. Phase 3 (verifier): 90 min. Phase 4 (signer): 60 min. Phase 5 (key mgmt + docs): 30 min. Phase 6 (verification): 60 min. **Total wall-clock: ~6–7 hours.** (Crypto correctness is why this is Opus `xhigh`.)

### When you're done

Report back with:
- The chosen Ed25519 verify mechanism (CNG/BCrypt vs other) + its minimum Windows build requirement.
- The canonicalization recipe (so a future session can reproduce it exactly).
- The tampered-manifest rejection log line (gate 1) and the valid-accept confirmation (gate 2).
- The real signer↔verifier round-trip result (gate 3).
- `git log --all -S` output proving the private key is not in history (gate 4).
- The 11 test names + pass/fail (incl. the RFC 8032 KAT).
- The key-rotation procedure in 3–4 sentences.
- Any ambiguity in T2.1's spec on key format/rotation/storage and how you resolved it.
- Anything out of scope you noticed (e.g. the app opens download_url in a browser rather than downloading + hash-checking the installer itself — note for M.1) — flag via `spawn_task`.
