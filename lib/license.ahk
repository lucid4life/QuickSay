; ==============================================================================
;  lib/license.ahk — QuickSay trial + license state machine (T2.3)
;
;  Implements T2 spec §5 (trial enforcement) + §3 verify-side. Single source of
;  truth for license/trial state: DPAPI-encrypted %APPDATA%\QuickSay\license.dat.
;
;  Dependencies (provided by the includer — QuickSay.ahk / the test driver):
;    lib/JSON.ahk    (JSON.Parse / JSON.Stringify)
;    lib/dpapi.ahk   (DPAPIEncrypt / DPAPIDecrypt)
;    lib/ed25519.ahk (VerifyEd25519 / Sha256 / Ed25519_Base64UrlDecode / _AsBuf)
;
;  This module deliberately does NOT depend on QuickSay.ahk internals (config
;  lock, http helpers) so it loads and unit-tests standalone. It serialises its
;  own license.dat writes with a dedicated named mutex and decodes HTTP responses
;  with a private UTF-8 helper.
;
;  Public API (app):
;    EnsureLicenseOnStartup()  · CheckLicenseState([nowUnix]) · InitTrial([nowUnix])
;    ComputeMachineId()        · LicenseAllowsRecording(state)
;    ActivateLicense(key)      · RefreshLicense() · ReportTrialConsumed()
;    CheckTrialStatusBestEffort(machineId)
;    LicenseFetchPricing()
;  CheckLicenseState returns Map("state","daysRemaining","email","exp").
;  States: INSTALLED · TRIAL_ACTIVE · TRIAL_EXPIRED · LICENSED · GRACE_PERIOD
;          · RE_VALIDATION_NEEDED · LICENSE_REVOKED  (TRIAL_EXPIRED/REVOKED ⇒ paywall).
; ==============================================================================
#Requires AutoHotkey v2.0

; ── Compiled constants (baked into the binary) ────────────────────────────────
; Trust anchor: kid → raw-32 base64url Ed25519 public key (spec §8.1; sha256 = 761d22df…fde09b).
global LICENSE_TRUSTED_KEYS := Map("qs-2026", "UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8")
global LICENSE_ISS := "license.quicksay.app"
; Staging now; M.3 flips to https://license.quicksay.app (spec §2.7 / §8.3).
global LICENSE_WORKER_URL := "https://license-staging.quicksay.app"
; TODO(M.3): real LemonSqueezy checkout URL — product id is assigned at launch (do NOT hardcode the price).
global LEMONSQUEEZY_PRODUCT_URL := ""

global LICENSE_TRIAL_DAYS := 14
global LICENSE_DAY_SECONDS := 86400
global LICENSE_CLOCK_LEEWAY := 60          ; spec D7
global LICENSE_GRACE_SECONDS := 604800     ; 7 days (spec §3.2)

; ── Test/injection points (no effect in production) ───────────────────────────
global _LicenseDatPathOverride := ""
global _LicenseMachineIdOverride := ""
; full functions (NOT fat-arrow): an arrow body assumes-local and would never write the global
LicenseTest_SetDatPath(p) {
    global _LicenseDatPathOverride
    _LicenseDatPathOverride := p
}
LicenseTest_SetMachineId(m) {
    global _LicenseMachineIdOverride
    _LicenseMachineIdOverride := m
}
LicenseTest_ClearMachineId() {
    global _LicenseMachineIdOverride
    _LicenseMachineIdOverride := ""
}

; ── Time helpers (UTC unix seconds) ───────────────────────────────────────────
_NowUnix() => DateDiff(A_NowUTC, "19700101000000", "Seconds")
License_UnixToIso(unix) {
    s := DateAdd("19700101000000", unix, "Seconds")
    return SubStr(s,1,4) "-" SubStr(s,5,2) "-" SubStr(s,7,2) "T" SubStr(s,9,2) ":" SubStr(s,11,2) ":" SubStr(s,13,2) "Z"
}
License_IsoToUnix(iso) {
    if !RegExMatch(iso, "^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})", &m)
        return 0
    return DateDiff(m[1] m[2] m[3] m[4] m[5] m[6], "19700101000000", "Seconds")
}

; ── license.dat path + storage (DPAPI) ────────────────────────────────────────
License_DatPath() {
    global _LicenseDatPathOverride
    if (_LicenseDatPathOverride != "")
        return _LicenseDatPathOverride
    return EnvGet("APPDATA") "\QuickSay\license.dat"
}
_NewDatObj() {
    m := Map()
    m["trialStartedAt"]       := ""
    m["trialMachineId"]       := ""
    m["licenseJwt"]           := ""
    m["licenseEmail"]         := ""
    m["lastValidation"]       := ""
    m["lastValidationResult"] := ""
    m["stateVersion"]         := 1
    return m
}
_LicLock() {
    h := DllCall("CreateMutexW", "ptr", 0, "int", 0, "wstr", "Local\QuickSayLicenseDatLock", "ptr")
    if (h)
        DllCall("WaitForSingleObject", "ptr", h, "uint", 5000)
    return h
}
_LicUnlock(h) {
    if (h) {
        DllCall("ReleaseMutex", "ptr", h)
        DllCall("CloseHandle", "ptr", h)
    }
}
License_WriteDat(obj) {
    path := License_DatPath()
    enc := DPAPIEncrypt(JSON.Stringify(obj))
    if (enc = "")
        return false
    SplitPath(path, , &dir)
    if (dir != "" && !DirExist(dir))
        DirCreate(dir)
    h := _LicLock()
    try {
        tmp := path ".tmp"
        if FileExist(tmp)
            FileDelete(tmp)
        FileAppend(enc, tmp, "UTF-8")
        if FileExist(path)
            FileDelete(path)
        FileMove(tmp, path, 1)
    } finally {
        _LicUnlock(h)
    }
    return true
}
_BackupCorrupt(path) {
    try {
        if FileExist(path ".corrupt")
            FileDelete(path ".corrupt")
        FileMove(path, path ".corrupt", 1)
    }
    return ""
}
License_ReadDat() {
    path := License_DatPath()
    if !FileExist(path)
        return ""
    enc := ""
    try
        enc := FileRead(path, "UTF-8")
    catch
        return ""
    if (enc = "")
        return ""
    ; NOTE: local must NOT be named "json" — AHK identifiers are case-insensitive,
    ; so a `json` local would shadow the JSON class and break JSON.Parse below.
    plain := DPAPIDecrypt(Trim(enc, " `r`n`t"))
    if (plain = "")
        return _BackupCorrupt(path)
    obj := ""
    try
        obj := JSON.Parse(plain)
    catch
        return _BackupCorrupt(path)
    if !(obj is Map)
        return _BackupCorrupt(path)
    return obj
}

; ── Machine id (spec §5.3): SHA256(MAC + Windows ProductID), 32 hex chars ──────
ComputeMachineId() {
    global _LicenseMachineIdOverride
    if (_LicenseMachineIdOverride != "")
        return _LicenseMachineIdOverride
    ; capture-once: prefer the persisted trialMachineId for stability across NIC toggles
    dat := License_ReadDat()
    if (dat != "" && dat.Has("trialMachineId") && dat["trialMachineId"] is String && dat["trialMachineId"] != "")
        return dat["trialMachineId"]
    return _ComputeMachineIdLive()
}
_ComputeMachineIdLive() {
    combined := _GetPrimaryMac() . _GetWindowsProductId()
    return SubStr(_BufToHexLower(Sha256(_AsBuf(combined))), 1, 32)
}
_GetWindowsProductId() {
    try
        return RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductId")
    catch
        return ""
}
; First non-loopback / non-tunnel adapter with a 6-byte MAC (prefer Up). GetAdaptersAddresses.
_GetPrimaryMac() {
    size := 15000
    buf := Buffer(size, 0)
    ret := DllCall("iphlpapi\GetAdaptersAddresses", "uint", 0, "uint", 0, "ptr", 0, "ptr", buf, "uint*", &size)
    if (ret = 111) {               ; ERROR_BUFFER_OVERFLOW
        buf := Buffer(size, 0)
        ret := DllCall("iphlpapi\GetAdaptersAddresses", "uint", 0, "uint", 0, "ptr", 0, "ptr", buf, "uint*", &size)
    }
    if (ret != 0)
        return ""
    best := "", firstAny := ""
    p := buf.Ptr
    while (p) {
        ifType    := NumGet(p + 100, "UInt")     ; IfType  (24 = loopback, 131 = tunnel)
        operStatus:= NumGet(p + 104, "UInt")     ; OperStatus (1 = Up)
        physLen   := NumGet(p + 88,  "UInt")     ; PhysicalAddressLength
        if (ifType != 24 && ifType != 131 && physLen = 6) {
            mac := ""
            Loop 6
                mac .= Format("{:02x}", NumGet(p + 80 + A_Index - 1, "UChar"))
            if (firstAny = "")
                firstAny := mac
            if (operStatus = 1 && best = "")
                best := mac
        }
        p := NumGet(p + 8, "Ptr")                ; Next
    }
    return best != "" ? best : firstAny
}
_BufToHexLower(buf) {
    s := ""
    Loop buf.Size
        s .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return s
}

; ── JWT verification (spec §3.4 — fail closed at every step) ───────────────────
_DecodeJwtSeg(seg) {
    buf := Ed25519_Base64UrlDecode(seg)
    if (buf.Size = 0)
        return ""
    str := StrGet(buf.Ptr, buf.Size, "UTF-8")
    try
        return JSON.Parse(str)
    catch
        return ""
}
_MapStr(m, key) {
    if !(m is Map) || !m.Has(key)
        return ""
    v := m[key]
    return (v is String) ? v : ""
}
_RevokedResult() => Map("state", "LICENSE_REVOKED", "exp", 0, "email", "")

; In-memory verify cache (process lifetime). The Ed25519 verify is ~1–2 s, so we
; run it once per distinct token: keyed on the exact JWT string, a different token
; always misses and re-verifies (a local attacker cannot make a forged token reuse
; a prior "valid" verdict). The time-based state is always re-derived from `now`.
global _LicVCacheJwt := "", _LicVCacheValid := false, _LicVCacheExp := 0, _LicVCacheEmail := ""
LicenseClearVerifyCache() {
    global _LicVCacheJwt, _LicVCacheValid, _LicVCacheExp, _LicVCacheEmail
    _LicVCacheJwt := "", _LicVCacheValid := false, _LicVCacheExp := 0, _LicVCacheEmail := ""
}

; Crypto + claim verification (the expensive, cacheable part). → Map(valid, exp, email).
_VerifyJwtStatic(jwt) {
    global LICENSE_TRUSTED_KEYS, LICENSE_ISS
    try {
        parts := StrSplit(jwt, ".")
        if (parts.Length != 3)
            return Map("valid", false, "exp", 0, "email", "")
        hdr := _DecodeJwtSeg(parts[1])
        pl  := _DecodeJwtSeg(parts[2])
        if !(hdr is Map) || !(pl is Map)
            return Map("valid", false, "exp", 0, "email", "")
        ; pin algorithm + type (defeats alg:none / algorithm confusion)
        if (_MapStr(hdr, "alg") != "EdDSA")
            return Map("valid", false, "exp", 0, "email", "")
        if (_MapStr(hdr, "typ") != "JWT")
            return Map("valid", false, "exp", 0, "email", "")
        kid := _MapStr(hdr, "kid")
        if !LICENSE_TRUSTED_KEYS.Has(kid)
            return Map("valid", false, "exp", 0, "email", "")
        pub := Ed25519_Base64UrlDecode(LICENSE_TRUSTED_KEYS[kid])
        sig := Ed25519_Base64UrlDecode(parts[3])
        if (sig.Size != 64)
            return Map("valid", false, "exp", 0, "email", "")
        if !VerifyEd25519(parts[1] "." parts[2], sig, pub)
            return Map("valid", false, "exp", 0, "email", "")
        if (_MapStr(pl, "iss") != LICENSE_ISS)
            return Map("valid", false, "exp", 0, "email", "")
        if (_MapStr(pl, "machine") != ComputeMachineId())
            return Map("valid", false, "exp", 0, "email", "")
        return Map("valid", true, "exp", (pl.Has("exp") ? Integer(pl["exp"]) : 0), "email", _MapStr(pl, "email"))
    } catch {
        return Map("valid", false, "exp", 0, "email", "")
    }
}
_VerifyJwt(jwt, now) {
    global _LicVCacheJwt, _LicVCacheValid, _LicVCacheExp, _LicVCacheEmail
    global LICENSE_CLOCK_LEEWAY, LICENSE_GRACE_SECONDS
    if (jwt != _LicVCacheJwt) {
        s := _VerifyJwtStatic(jwt)
        _LicVCacheJwt := jwt
        _LicVCacheValid := s["valid"]
        _LicVCacheExp := s["exp"]
        _LicVCacheEmail := s["email"]
    }
    if (!_LicVCacheValid)
        return _RevokedResult()
    effExp := _LicVCacheExp + LICENSE_CLOCK_LEEWAY
    if (now < effExp)
        st := "LICENSED"
    else if (now < effExp + LICENSE_GRACE_SECONDS)
        st := "GRACE_PERIOD"
    else
        st := "RE_VALIDATION_NEEDED"
    return Map("state", st, "exp", _LicVCacheExp, "email", _LicVCacheEmail)
}

; ── State machine ─────────────────────────────────────────────────────────────
_LicResult(state, days, email, exp) => Map("state", state, "daysRemaining", days, "email", email, "exp", exp)

CheckLicenseState(nowUnix := 0) {
    global LICENSE_TRIAL_DAYS, LICENSE_DAY_SECONDS, LICENSE_CLOCK_LEEWAY
    now := nowUnix > 0 ? nowUnix : _NowUnix()
    dat := License_ReadDat()
    if (dat = "")
        return _LicResult("INSTALLED", 0, "", 0)
    jwt := (dat.Has("licenseJwt")) ? dat["licenseJwt"] : ""
    if (jwt is String && jwt != "") {
        v := _VerifyJwt(jwt, now)
        return _LicResult(v["state"], 0, v["email"], v["exp"])
    }
    startIso := (dat.Has("trialStartedAt") && dat["trialStartedAt"] is String) ? dat["trialStartedAt"] : ""
    if (startIso = "")
        return _LicResult("INSTALLED", 0, "", 0)
    startUnix := License_IsoToUnix(startIso)
    if (startUnix <= 0)
        return _LicResult("INSTALLED", 0, "", 0)
    ; clock rollback: a start time in the (meaningful) future is tamper → expire (spec §5.4)
    if (startUnix > now + LICENSE_CLOCK_LEEWAY)
        return _LicResult("TRIAL_EXPIRED", 0, "", 0)
    elapsed := now - startUnix
    trialLen := LICENSE_TRIAL_DAYS * LICENSE_DAY_SECONDS
    if (elapsed < trialLen) {
        remaining := Ceil((trialLen - elapsed) / (LICENSE_DAY_SECONDS * 1.0))
        return _LicResult("TRIAL_ACTIVE", remaining, "", 0)
    }
    return _LicResult("TRIAL_EXPIRED", 0, "", 0)
}

InitTrial(nowUnix := 0) {
    now := nowUnix > 0 ? nowUnix : _NowUnix()
    dat := License_ReadDat()
    if (dat = "")
        dat := _NewDatObj()
    dat["trialStartedAt"] := License_UnixToIso(now)
    dat["trialMachineId"] := ComputeMachineId()
    if !dat.Has("stateVersion")
        dat["stateVersion"] := 1
    License_WriteDat(dat)
    return CheckLicenseState(now)
}

; Recording is allowed only in these states (spec §5.2/§5.7).
LicenseAllowsRecording(state) =>
    (state = "TRIAL_ACTIVE" || state = "LICENSED" || state = "GRACE_PERIOD" || state = "INSTALLED")

; ── HTTP (self-contained WinHTTP — does not depend on lib/http.ahk) ────────────
_LicHttp(method, url, bodyObj := "") {
    res := Map("status", 0, "body", "", "error", "")
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(5000, 5000, 10000, 10000)
        http.Open(method, url, false)
        if (bodyObj != "") {
            http.SetRequestHeader("Content-Type", "application/json")
            http.Send(JSON.Stringify(bodyObj))
        } else {
            http.Send()
        }
        res["status"] := http.Status
        res["body"]   := _LicUtf8Decode(http.ResponseBody)
    } catch as e {
        res["error"] := e.Message
    }
    return res
}
_LicUtf8Decode(responseBody) {
    try {
        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(responseBody)
        stream.Position := 0
        stream.Type := 2
        stream.Charset := "utf-8"
        text := stream.ReadText()
        stream.Close()
        return text
    } catch {
        return ""
    }
}

; ── Activation flow (spec §2.3 /activate) ─────────────────────────────────────
License_ParseActivateResponse(status, body) {
    res := Map("ok", false, "jwt", "", "email", "", "exp", 0, "code", "", "message", "")
    obj := ""
    try
        obj := (body != "") ? JSON.Parse(body) : ""
    catch
        obj := ""
    if (status = 200 && obj is Map && obj.Has("jwt") && obj["jwt"] is String) {
        res["ok"]    := true
        res["jwt"]   := obj["jwt"]
        res["email"] := (obj.Has("email") && obj["email"] is String) ? obj["email"] : ""
        res["exp"]   := obj.Has("exp") ? Integer(obj["exp"]) : 0
        return res
    }
    code := (obj is Map && obj.Has("code") && obj["code"] is String) ? obj["code"] : ""
    res["code"]    := code
    res["message"] := _ActivateMessage(status, code)
    return res
}
_ActivateMessage(status, code) {
    if (status = 403) {
        if (code = "already_activated")
            return "This license is already activated on another machine. Use that machine, or deactivate it first from its Settings."
        if (code = "invalid")
            return "That license key was not found. Please double-check it and try again."
        return "Activation was refused. Please check your license key."
    }
    if (status = 429)
        return "Too many attempts right now. Please wait a moment and try again shortly."
    if (status = 400)
        return "That doesn't look like a valid license key. Please re-check and re-enter it."
    if (status = 503)
        return "Activation is temporarily unavailable. Please try again in a minute."
    if (status = 0)
        return "Couldn't reach the license server. Check your internet connection and try again."
    return "Activation failed (error " status "). Please try again, or email support@quicksay.app."
}
; Activate a license key → on success stores the JWT and returns ok. Returns the parsed result Map.
ActivateLicense(licenseKey) {
    global LICENSE_WORKER_URL
    body := Map("license_key", licenseKey, "machine_id", ComputeMachineId())
    r := _LicHttp("POST", LICENSE_WORKER_URL "/activate", body)
    parsed := License_ParseActivateResponse(r["status"], r["body"])
    if (parsed["ok"])
        _StoreLicenseJwt(parsed["jwt"], parsed["email"], parsed["exp"], "activate:200")
    return parsed
}
_StoreLicenseJwt(jwt, email, exp, resultTag) {
    dat := License_ReadDat()
    if (dat = "")
        dat := _NewDatObj()
    dat["licenseJwt"]           := jwt
    dat["licenseEmail"]         := email
    dat["lastValidation"]       := License_UnixToIso(_NowUnix())
    dat["lastValidationResult"] := resultTag
    License_WriteDat(dat)
    LicenseClearVerifyCache()
}
_ClearLicenseJwt(resultTag) {
    dat := License_ReadDat()
    if (dat = "")
        return
    dat["licenseJwt"]           := ""
    dat["lastValidation"]       := License_UnixToIso(_NowUnix())
    dat["lastValidationResult"] := resultTag
    License_WriteDat(dat)
    LicenseClearVerifyCache()
}

; Re-sign a fresh 14-day JWT (spec §2.3 /refresh). 403 → revoke locally (→ paywall).
RefreshLicense() {
    global LICENSE_WORKER_URL
    dat := License_ReadDat()
    if (dat = "" || !(dat.Has("licenseJwt")) || !(dat["licenseJwt"] is String) || dat["licenseJwt"] = "")
        return Map("ok", false, "code", "no_license", "message", "No license to refresh.")
    body := Map("jwt", dat["licenseJwt"], "machine_id", ComputeMachineId())
    r := _LicHttp("POST", LICENSE_WORKER_URL "/refresh", body)
    if (r["status"] = 200) {
        obj := ""
        try
            obj := JSON.Parse(r["body"])
        catch
            obj := ""
        if (obj is Map && obj.Has("jwt") && obj["jwt"] is String) {
            email := (dat.Has("licenseEmail") && dat["licenseEmail"] is String) ? dat["licenseEmail"] : ""
            _StoreLicenseJwt(obj["jwt"], email, obj.Has("exp") ? Integer(obj["exp"]) : 0, "refresh:200")
            return Map("ok", true, "code", "", "message", "")
        }
    }
    if (r["status"] = 403) {
        _ClearLicenseJwt("refresh:403")     ; revoked / machine mismatch / bad signature
        return Map("ok", false, "code", "revoked", "message", "Your license is no longer valid.")
    }
    ; 503 / network → keep current state (grace absorbs it)
    return Map("ok", false, "code", "unavailable", "message", "Couldn't reach the license server.")
}

; ── Trial-reset gate (spec §5.4 — best-effort, fail-open) ──────────────────────
CheckTrialStatusBestEffort(machineId) {
    global LICENSE_WORKER_URL
    r := _LicHttp("GET", LICENSE_WORKER_URL "/trial/status?machineId=" machineId)
    if (r["status"] != 200)
        return false                       ; fail-open: offline / error → not blocked
    obj := ""
    try
        obj := JSON.Parse(r["body"])
    catch
        return false
    if (obj is Map && obj.Has("blocked"))
        return (obj["blocked"] = true || obj["blocked"] = 1)
    return false
}
ReportTrialConsumed() {
    global LICENSE_WORKER_URL
    dat := License_ReadDat()
    mid := (dat != "" && dat.Has("trialMachineId") && dat["trialMachineId"] is String && dat["trialMachineId"] != "")
        ? dat["trialMachineId"] : ComputeMachineId()
    try _LicHttp("POST", LICENSE_WORKER_URL "/trial/report", Map("trialMachineId", mid))   ; fire-and-forget
}
LicenseFetchPricing() {
    global LICENSE_WORKER_URL
    r := _LicHttp("GET", LICENSE_WORKER_URL "/pricing")
    if (r["status"] != 200)
        return ""
    try
        return JSON.Parse(r["body"])
    catch
        return ""
}

; ── Startup orchestration ─────────────────────────────────────────────────────
; First launch (no dat): best-effort fail-open /trial/status gate, else start the trial.
; Returns the current state Map. (The expensive JWT crypto-verify runs here, once.)
EnsureLicenseOnStartup() {
    global LICENSE_TRIAL_DAYS, LICENSE_DAY_SECONDS
    dat := License_ReadDat()
    if (dat = "") {
        mid := _ComputeMachineIdLive()
        if (CheckTrialStatusBestEffort(mid)) {
            ; this machine already consumed its trial → start expired (no fresh trial)
            d := _NewDatObj()
            d["trialMachineId"]       := mid
            d["trialStartedAt"]       := License_UnixToIso(_NowUnix() - (LICENSE_TRIAL_DAYS + 1) * LICENSE_DAY_SECONDS)
            d["lastValidationResult"] := "trial_blocked"
            License_WriteDat(d)
        } else {
            InitTrial()
        }
    }
    state := CheckLicenseState()
    ; fire the trial-consumed report once when we first observe expiry
    if (state["state"] = "TRIAL_EXPIRED")
        _MaybeReportTrialOnce()
    return state
}
_MaybeReportTrialOnce() {
    dat := License_ReadDat()
    if (dat = "")
        return
    already := (dat.Has("lastValidationResult") && dat["lastValidationResult"] is String) ? dat["lastValidationResult"] : ""
    if (already = "trial_reported" || already = "trial_blocked")
        return
    ReportTrialConsumed()
    dat["lastValidationResult"] := "trial_reported"
    License_WriteDat(dat)
}
