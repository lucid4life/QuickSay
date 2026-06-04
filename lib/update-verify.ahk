; ==============================================================================
;  lib/update-verify.ahk — T2.5 signed version.json verification (offline, FAIL-CLOSED)
;
;  Verifies the Ed25519 signature on the auto-update manifest BEFORE
;  CheckForUpdates() trusts any field. Uses the shared verifier lib/ed25519.ahk
;  (spec §8.1) and the canonicalization recipe in spec §7.2.
;
;  Fails CLOSED: a missing / malformed / invalid signature, an unknown keyId, a
;  malformed manifest, or any internal error → { ok:false } (treated as "no
;  update available"). NEVER fails open.
;
;  Public API:
;    VerifyUpdateManifest(bodyText) -> Map:
;        ok(bool), reason(str), version, download_url, changelog(Array),
;        installer_sha256, released_at, keyId
;    UpdateManifest_Canonical(parsedMap) -> canonical signed-payload String (§7.2)
;
;  Trust anchor: TRUSTED_UPDATE_KEYS[keyId] = raw-32 base64url public key (§8.1).
;  The matching PRIVATE key lives ONLY in the CF secret store + offline backup,
;  never in this repo (release.ps1 reads it from a secret at sign time).
;
;  Requires lib/JSON.ahk + lib/ed25519.ahk (both already #Included by QuickSay.ahk).
; ==============================================================================
#Requires AutoHotkey v2.0

; keyId -> raw-32-byte Ed25519 public key, base64url (spec §8.1). ONE shared key
; signs both license JWTs and version.json; rotation = add a new keyId entry here
; and ship it before the signer switches keys (non-breaking via this map).
; Build-time trust-anchor assert (I-c): SHA-256 of the decoded qs-2026 key must
; equal 761d22df…fde09b — verified by tests/update/update-tests.ahk.
global TRUSTED_UPDATE_KEYS := Map(
    "qs-2026", "UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8"
)

; Escape one string for canonical JSON per spec §7.2 — byte-for-byte like Node
; JSON.stringify: minimal RFC 8259 (escape " and \ ; control chars U+0000–U+001F
; as \b \t \n \f \r or \u00xx). NO '/' escaping. Non-ASCII passes through raw —
; surrogate-pair halves each fall through unchanged and are re-encoded to UTF-8
; by the Ed25519 layer (StrPut UTF-8), matching Buffer.from(str,'utf8').
_UpdateJsonEscape(s) {
    out := ""
    Loop Parse, s {
        ch := A_LoopField
        code := Ord(ch)
        if (ch == '"')
            out .= '\"'
        else if (ch == "\")
            out .= "\\"
        else if (code == 0x08)
            out .= "\b"
        else if (code == 0x09)
            out .= "\t"
        else if (code == 0x0A)
            out .= "\n"
        else if (code == 0x0C)
            out .= "\f"
        else if (code == 0x0D)
            out .= "\r"
        else if (code < 0x20)
            out .= Format("\u{:04x}", code)
        else
            out .= ch
    }
    return out
}

; Build the canonical signed payload (spec §7.2) from a PARSED manifest Map.
; Object with exactly the six signed keys in lexicographic order, compact
; separators, changelog element order preserved. (Caller guarantees the six
; fields exist + are the right types.)
;
; Note: legitimately-signed bodies emit non-ASCII as raw UTF-8 (never \u-escaped);
; the byte-identity test (#9) pins that. AHK strings are UTF-16, so an attacker
; who rewrites a char to its \uXXXX / surrogate-pair escaped form parses to the
; identical code units — re-canonicalizing to identical bytes (same signed content)
; or, if anything differs, failing the signature check. It cannot mis-trust
; DIFFERENT content as valid (fail-closed) — proven by the F1 test.
UpdateManifest_Canonical(m) {
    clStr := ""
    for item in m["changelog"]
        clStr .= (A_Index > 1 ? "," : "") . '"' . _UpdateJsonEscape(item . "") . '"'
    s := "{"
    s .= '"changelog":[' . clStr . "],"
    s .= '"download_url":"'     . _UpdateJsonEscape(m["download_url"] . "")     . '",'
    s .= '"installer_sha256":"' . _UpdateJsonEscape(m["installer_sha256"] . "") . '",'
    s .= '"keyId":"'            . _UpdateJsonEscape(m["keyId"] . "")            . '",'
    s .= '"released_at":"'      . _UpdateJsonEscape(m["released_at"] . "")      . '",'
    s .= '"version":"'          . _UpdateJsonEscape(m["version"] . "")          . '"'
    s .= "}"
    return s
}

; Verify a fetched version.json body. Returns the result Map (see header).
VerifyUpdateManifest(bodyText) {
    global TRUSTED_UPDATE_KEYS
    res := Map("ok", false, "reason", "", "version", "", "download_url", "",
               "changelog", [], "installer_sha256", "", "released_at", "", "keyId", "")
    try {
        ; 1. Parse JSON
        try {
            parsed := JSON.Parse(bodyText)
        } catch {
            res["reason"] := "parse error"
            return res
        }
        if (!(parsed is Map)) {
            res["reason"] := "manifest not a JSON object"
            return res
        }

        ; 2. All signed fields + the signature must be present
        for f in ["version", "download_url", "changelog", "installer_sha256", "released_at", "keyId", "signature"] {
            if (!parsed.Has(f)) {
                res["reason"] := "missing field: " . f
                return res
            }
        }

        ; 3. Types (fail closed on anything malformed)
        if (Type(parsed["changelog"]) != "Array") {
            res["reason"] := "changelog not an array"
            return res
        }
        for f in ["version", "download_url", "installer_sha256", "released_at", "keyId", "signature"] {
            if (Type(parsed[f]) != "String") {
                res["reason"] := "field not a string: " . f
                return res
            }
        }
        for item in parsed["changelog"] {
            if (Type(item) != "String") {
                res["reason"] := "changelog entry not a string"
                return res
            }
        }

        keyId  := parsed["keyId"]
        sigB64 := parsed["signature"]

        ; 4. keyId must resolve to a trusted public key
        if (!TRUSTED_UPDATE_KEYS.Has(keyId)) {
            res["reason"] := "unknown keyId: " . keyId
            return res
        }
        pubKey := Ed25519_Base64UrlDecode(TRUSTED_UPDATE_KEYS[keyId])
        if (!(pubKey is Buffer) || pubKey.Size != 32) {
            res["reason"] := "bad trusted key"
            return res
        }

        ; 5. signature must decode to a 64-byte Ed25519 signature
        if (sigB64 == "") {
            res["reason"] := "missing signature"
            return res
        }
        sig := Ed25519_Base64UrlDecode(sigB64)
        if (!(sig is Buffer) || sig.Size != 64) {
            res["reason"] := "bad signature length"
            return res
        }

        ; 6. rebuild the canonical payload and verify
        canon := UpdateManifest_Canonical(parsed)
        if (!VerifyEd25519(canon, sig, pubKey)) {
            res["reason"] := "signature invalid"
            return res
        }

        ; verified — surface the trusted fields
        res["ok"]               := true
        res["version"]          := parsed["version"]
        res["download_url"]     := parsed["download_url"]
        res["changelog"]        := parsed["changelog"]
        res["installer_sha256"] := parsed["installer_sha256"]
        res["released_at"]      := parsed["released_at"]
        res["keyId"]            := keyId
        return res
    } catch as e {
        ; crash-safe backstop: any unexpected error → fail closed
        res["ok"] := false
        res["reason"] := "verify error"
        return res
    }
}
