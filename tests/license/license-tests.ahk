; ==============================================================================
;  T2.3 — lib/license.ahk unit tests (headless)
;  Usage: AutoHotkey64.exe /ErrorStdOut license-tests.ahk
;  Exit 0 = all pass, Exit 1 = failures. Requires fixtures.json (gen-fixtures.mjs).
;
;  Implements the 13-test list from session-T2.3 (+ claim edge cases). Uses dependency
;  injection (test dat path + machine-id override + nowOverride) so every test is
;  offline and deterministic. Real JWTs are minted by gen-fixtures.mjs with qs-2026.
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\dpapi.ahk
#Include %A_ScriptDir%\..\..\lib\ed25519.ahk
#Include %A_ScriptDir%\..\..\lib\license.ahk

global gPass := 0, gFail := 0
Assert(name, cond) {
    global gPass, gFail
    if (cond)
        FileAppend("  PASS  " name "`n", "*"), gPass++
    else
        FileAppend("  FAIL  " name "`n", "*"), gFail++
}

fxPath := A_ScriptDir . "\fixtures.json"
if !FileExist(fxPath) {
    FileAppend("FATAL: fixtures.json missing — run: node tests/license/gen-fixtures.mjs`n", "*")
    ExitApp(1)
}
fx := JSON.Parse(FileRead(fxPath, "UTF-8"))
NOW := fx["now"]                       ; fixed reference unix time
TEST_MACHINE := fx["testMachineId"]
JWTS := fx["jwts"]
DAY := 86400

; ── Test harness wiring: isolated dat file + injected machine id ──────────────
datPath := A_Temp . "\qs-license-test-" . A_TickCount . ".dat"
LicenseTest_SetDatPath(datPath)
LicenseTest_SetMachineId(TEST_MACHINE)
DeleteDat() {
    global datPath
    if FileExist(datPath)
        FileDelete(datPath)
    if FileExist(datPath ".corrupt")
        FileDelete(datPath ".corrupt")
}
SeedDat(jwt := "", trialStartedAtIso := "", machineId := "") {
    global TEST_MACHINE
    m := Map()
    m["trialStartedAt"]       := trialStartedAtIso
    m["trialMachineId"]       := (machineId != "" ? machineId : TEST_MACHINE)
    m["licenseJwt"]           := jwt
    m["licenseEmail"]         := ""
    m["lastValidation"]       := ""
    m["lastValidationResult"] := ""
    m["stateVersion"]         := 1
    License_WriteDat(m)
}

; ─── Test 1: fresh install → INSTALLED; InitTrial → TRIAL_ACTIVE ──────────────
FileAppend("State machine — trial`n", "*")
DeleteDat()
Assert("T1: no dat → INSTALLED", CheckLicenseState(NOW)["state"] = "INSTALLED")
InitTrial(NOW)
r1 := CheckLicenseState(NOW)
Assert("T1: after InitTrial → TRIAL_ACTIVE", r1["state"] = "TRIAL_ACTIVE")
Assert("T1: daysRemaining = 14", r1["daysRemaining"] = 14)

; ─── Test 2: 13 days in → TRIAL_ACTIVE, daysRemaining = 1 ──────────────────────
DeleteDat()
SeedDat("", License_UnixToIso(NOW - 13 * DAY))
r2 := CheckLicenseState(NOW)
Assert("T2: 13d in → TRIAL_ACTIVE", r2["state"] = "TRIAL_ACTIVE")
Assert("T2: daysRemaining = 1", r2["daysRemaining"] = 1)

; ─── Test 3: 15 days in → TRIAL_EXPIRED ───────────────────────────────────────
DeleteDat()
SeedDat("", License_UnixToIso(NOW - 15 * DAY))
Assert("T3: 15d in → TRIAL_EXPIRED", CheckLicenseState(NOW)["state"] = "TRIAL_EXPIRED")

; ─── Test 4: clock rollback (trialStartedAt in the future) → TRIAL_EXPIRED ─────
DeleteDat()
SeedDat("", License_UnixToIso(NOW + 5 * DAY))
Assert("T4: start in future → TRIAL_EXPIRED", CheckLicenseState(NOW)["state"] = "TRIAL_EXPIRED")

; ─── Test 5: valid JWT, exp in future → LICENSED ──────────────────────────────
FileAppend("State machine — license JWT`n", "*")
DeleteDat()
SeedDat(JWTS["valid"])
r5 := CheckLicenseState(NOW)
Assert("T5: valid JWT → LICENSED", r5["state"] = "LICENSED")
Assert("T5: email surfaced", r5["email"] = "buyer@example.com")

; ─── Test 6: valid JWT, exp 3 days ago → GRACE_PERIOD ─────────────────────────
DeleteDat()
SeedDat(JWTS["grace"])
Assert("T6: exp 3d ago → GRACE_PERIOD", CheckLicenseState(NOW)["state"] = "GRACE_PERIOD")

; ─── Test 7: valid JWT, exp 10 days ago → RE_VALIDATION_NEEDED ────────────────
DeleteDat()
SeedDat(JWTS["revalidate"])
Assert("T7: exp 10d ago → RE_VALIDATION_NEEDED", CheckLicenseState(NOW)["state"] = "RE_VALIDATION_NEEDED")

; ─── Test 8: tampered claim (signature invalid) → LICENSE_REVOKED ─────────────
DeleteDat()
parts := StrSplit(JWTS["valid"], ".")
tampered := parts[1] "." parts[2] "x" "." parts[3]   ; mutate payload → sig breaks
SeedDat(tampered)
Assert("T8: tampered payload → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")

; ─── Test 9: signed by wrong key → LICENSE_REVOKED ────────────────────────────
DeleteDat()
SeedDat(JWTS["wrongKey"])
Assert("T9: wrong signing key → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")

; ─── Claim edge cases (spec §3.4) ─────────────────────────────────────────────
DeleteDat()
SeedDat(JWTS["wrongMachine"])
Assert("T9b: machine mismatch → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")
DeleteDat()
SeedDat(JWTS["wrongIss"])
Assert("T9c: wrong issuer → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")
DeleteDat()
SeedDat(JWTS["wrongKid"])
Assert("T9d: unknown kid → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")
; alg:none / algorithm confusion must be rejected (forge header alg=none, drop sig)
DeleteDat()
hdrNone := Ed25519_Base64UrlEncode(_TestStrBuf('{"alg":"none","typ":"JWT","kid":"qs-2026"}'))
pl := StrSplit(JWTS["valid"], ".")[2]
SeedDat(hdrNone "." pl ".")
Assert("T9e: alg:none → LICENSE_REVOKED", CheckLicenseState(NOW)["state"] = "LICENSE_REVOKED")

; ─── Test 10/11: /activate response parsing (offline; pure function) ──────────
FileAppend("Activation response parsing`n", "*")
okResp := License_ParseActivateResponse(200, '{"jwt":"' JWTS["valid"] '","email":"buyer@example.com","exp":' (NOW + 10*DAY) '}')
Assert("T10: 200 → ok", okResp["ok"] = true)
Assert("T10: 200 → jwt extracted", okResp["jwt"] = JWTS["valid"])
already := License_ParseActivateResponse(403, '{"error":"forbidden","code":"already_activated"}')
Assert("T11: 403 already_activated → not ok", already["ok"] = false)
Assert("T11: 403 code surfaced", already["code"] = "already_activated")
Assert("T11: 403 → friendly message", InStr(already["message"], "another"))
invalid := License_ParseActivateResponse(403, '{"error":"forbidden","code":"invalid"}')
Assert("T11b: 403 invalid → message", InStr(invalid["message"], "not"))
rl := License_ParseActivateResponse(429, '{"error":"rate_limited"}')
Assert("T11c: 429 → retry message", InStr(rl["message"], "try again") || InStr(rl["message"], "shortly"))

; ─── Test 12: machine ID stability + format (real machine) ────────────────────
FileAppend("Machine ID`n", "*")
DeleteDat()                 ; no persisted trialMachineId → exercise live MAC+ProductID path
LicenseTest_ClearMachineId()
mid1 := ComputeMachineId()
mid2 := ComputeMachineId()
Assert("T12: machine id = 32 hex chars", RegExMatch(mid1, "^[0-9a-f]{32}$"))
Assert("T12: machine id stable across calls", mid1 = mid2)
LicenseTest_SetMachineId(TEST_MACHINE)

; ─── Test 13: DPAPI encryption (round-trip + not plaintext) ───────────────────
FileAppend("DPAPI storage`n", "*")
DeleteDat()
SeedDat(JWTS["valid"], License_UnixToIso(NOW - 4*DAY))
raw := FileRead(datPath, "UTF-8")
Assert("T13: on-disk dat is not plaintext JSON", !InStr(raw, "trialMachineId") && !InStr(raw, JWTS["valid"]))
back := License_ReadDat()
Assert("T13: decrypts back to the stored JWT", back["licenseJwt"] = JWTS["valid"])

; ─── Build-time trust anchor in license.ahk's TRUSTED_KEYS (I-c) ──────────────
FileAppend("Trust anchor (I-c)`n", "*")
Assert("qs-2026 in TRUSTED_KEYS", LICENSE_TRUSTED_KEYS.Has("qs-2026"))
Assert("TRUSTED_KEYS[qs-2026] sha256 == 761d22df…",
    _TestBufHex(Sha256(Ed25519_Base64UrlDecode(LICENSE_TRUSTED_KEYS["qs-2026"]))) = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b")

; ─── Recording-gate predicate ─────────────────────────────────────────────────
FileAppend("Recording gate`n", "*")
Assert("TRIAL_ACTIVE allows recording", LicenseAllowsRecording("TRIAL_ACTIVE"))
Assert("LICENSED allows recording", LicenseAllowsRecording("LICENSED"))
Assert("GRACE_PERIOD allows recording", LicenseAllowsRecording("GRACE_PERIOD"))
Assert("TRIAL_EXPIRED blocks recording", !LicenseAllowsRecording("TRIAL_EXPIRED"))
Assert("LICENSE_REVOKED blocks recording", !LicenseAllowsRecording("LICENSE_REVOKED"))
Assert("RE_VALIDATION_NEEDED blocks recording", !LicenseAllowsRecording("RE_VALIDATION_NEEDED"))
Assert("PAYWALL_BLOCKING blocks recording", !LicenseAllowsRecording("PAYWALL_BLOCKING"))

DeleteDat()
FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)

; local test helpers
_TestStrBuf(str) {
    n := StrPut(str, "UTF-8") - 1
    b := Buffer(n)
    StrPut(str, b, "UTF-8")
    return b
}
_TestBufHex(buf) {
    s := ""
    Loop buf.Size
        s .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return s
}
