; ==============================================================================
;  T2.5 — signed version.json verification unit tests (headless)
;  Usage: AutoHotkey64.exe /ErrorStdOut update-tests.ahk
;  Exit 0 = all pass, Exit 1 = failures. Requires fixtures.json (gen-fixtures.mjs).
;
;  Covers (spec §7 / session Phase 2):
;   1 round-trip valid · 2 tampered version · 3 tampered download_url
;   4 tampered installer_sha256 · 5 stripped signature · 6 wrong key
;   7 unknown keyId · 8 RFC 8032 KAT · 9 canonicalization byte-identity (non-ASCII)
;   10 no-regression newer→offer · 11 no-regression same/older→up-to-date
;   + build-time trust-anchor assert (spec §8.1 I-c)
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\ed25519.ahk
#Include %A_ScriptDir%\..\..\lib\update-verify.ahk

global gPass := 0, gFail := 0

Assert(name, cond) {
    global gPass, gFail
    if (cond) {
        FileAppend("  PASS  " name "`n", "*"), gPass++
    } else {
        FileAppend("  FAIL  " name "`n", "*"), gFail++
    }
}

HexToBuf(hex) {
    n := StrLen(hex) // 2, buf := Buffer(n)
    Loop n
        NumPut("UChar", Integer("0x" . SubStr(hex, (A_Index - 1) * 2 + 1, 2)), buf, A_Index - 1)
    return buf
}
BufToHex(buf) {
    s := ""
    Loop buf.Size
        s .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return s
}
FlipByte(buf, idx) {
    cp := Buffer(buf.Size)
    DllCall("RtlMoveMemory", "ptr", cp, "ptr", buf, "uptr", buf.Size)
    NumPut("UChar", NumGet(cp, idx, "UChar") ^ 0xFF, cp, idx)
    return cp
}

; Minimal version comparator mirroring QuickSay.ahk CompareVersions (unchanged by
; this session): returns 1 if remote>local, 0 if equal, -1 if remote<local.
TestCmpVer(localVer, remote) {
    lp := StrSplit(localVer, "."), rp := StrSplit(remote, ".")
    Loop Max(lp.Length, rp.Length) {
        l := A_Index <= lp.Length && IsNumber(lp[A_Index]) ? Integer(lp[A_Index]) : 0
        r := A_Index <= rp.Length && IsNumber(rp[A_Index]) ? Integer(rp[A_Index]) : 0
        if (r > l)
            return 1
        if (r < l)
            return -1
    }
    return 0
}

fxPath := A_ScriptDir . "\fixtures.json"
if !FileExist(fxPath) {
    FileAppend("FATAL: fixtures.json missing — run: node tests/update/gen-fixtures.mjs`n", "*")
    ExitApp(1)
}
fx := JSON.Parse(FileRead(fxPath, "UTF-8"))
localVer := fx["local"]

; ─── 1. Round-trip: valid signed manifest accepted ────────────────────────────
FileAppend("Round-trip`n", "*")
r := VerifyUpdateManifest(fx["valid"]["body"])
Assert("1. valid manifest accepted (ok=true)", r["ok"] = true)
Assert("1. valid manifest version parsed", r["version"] = fx["valid"]["version"])

; ─── 2-4. Tampered signed fields rejected (signature invalid) ─────────────────
FileAppend("Tamper rejection`n", "*")
r := VerifyUpdateManifest(fx["tamperedVersion"])
Assert("2. tampered version rejected", r["ok"] = false)
Assert("2. tampered version reason=signature invalid", InStr(r["reason"], "signature invalid") > 0)

r := VerifyUpdateManifest(fx["tamperedUrl"])
Assert("3. tampered download_url rejected", r["ok"] = false)
Assert("3. tampered download_url reason=signature invalid", InStr(r["reason"], "signature invalid") > 0)

r := VerifyUpdateManifest(fx["tamperedSha"])
Assert("4. tampered installer_sha256 rejected", r["ok"] = false)
Assert("4. tampered installer_sha256 reason=signature invalid", InStr(r["reason"], "signature invalid") > 0)

; ─── 5. Stripped signature → fail closed ──────────────────────────────────────
FileAppend("Fail closed`n", "*")
r := VerifyUpdateManifest(fx["strippedSig"])
Assert("5. stripped signature rejected", r["ok"] = false)
Assert("5. stripped signature reason mentions signature", InStr(r["reason"], "signature") > 0)

; ─── 6. Wrong key (signed by another key, keyId still qs-2026) → rejected ──────
FileAppend("Wrong key`n", "*")
r := VerifyUpdateManifest(fx["wrongKey"])
Assert("6. wrong-key manifest rejected", r["ok"] = false)
Assert("6. wrong-key reason=signature invalid", InStr(r["reason"], "signature invalid") > 0)

; ─── 7. Unknown keyId → rejected before signature check ───────────────────────
FileAppend("Unknown keyId`n", "*")
r := VerifyUpdateManifest(fx["unknownKid"])
Assert("7. unknown keyId rejected", r["ok"] = false)
Assert("7. unknown keyId reason mentions keyId", InStr(r["reason"], "keyId") > 0)

; ─── 8. RFC 8032 §7.1 KAT — proves the Ed25519 primitive is correct ───────────
FileAppend("RFC 8032 KAT`n", "*")
rfcPub := HexToBuf(fx["rfc8032"]["pubHex"])
rfcMsg := HexToBuf(fx["rfc8032"]["msgHex"])
rfcSig := HexToBuf(fx["rfc8032"]["sigHex"])
Assert("8. RFC8032 TEST2 vector verifies", VerifyEd25519(rfcMsg, rfcSig, rfcPub) = true)
Assert("8. RFC8032 tampered sig rejected", VerifyEd25519(rfcMsg, FlipByte(rfcSig, 10), rfcPub) = false)

; ─── 9. Canonicalization byte-identity (signer ≡ verifier) with non-ASCII ─────
FileAppend("Canonicalization byte-identity`n", "*")
parsedNon := JSON.Parse(fx["nonAscii"]["body"])
rebuilt := UpdateManifest_Canonical(parsedNon)
Assert("9. AHK canonical == Node canonical (emoji+accent+slash)", rebuilt == fx["nonAscii"]["canonical"])
r := VerifyUpdateManifest(fx["nonAscii"]["body"])
Assert("9. non-ASCII manifest verifies against real signature", r["ok"] = true)

; F1 (security review): a body whose raw emoji is rewritten to 🚀 escapes.
; In UTF-16 the escaped pair equals the raw emoji's code units, so the verifier
; re-canonicalizes to identical bytes and accepts it as the SAME signed content
; (and the parsed changelog entry still contains the rocket). The security property:
; it can never accept DIFFERENT content than was signed — fail-closed otherwise.
r := VerifyUpdateManifest(fx["escapedSurrogate"])
Assert("F1. escaped-surrogate body resolves to identical signed content (accepted)", r["ok"] = true)
Assert("F1. escaped-surrogate parsed content is the SAME (rocket preserved)", InStr(r["changelog"][1], Chr(0xD83D) . Chr(0xDE80)) > 0)

; ─── 10. No regression — newer signed version is accepted and would be offered ─
FileAppend("No regression (newer → offer)`n", "*")
r := VerifyUpdateManifest(fx["valid"]["body"])
Assert("10. newer signed manifest verifies", r["ok"] = true)
Assert("10. newer than local → would offer", TestCmpVer(localVer, r["version"]) > 0)

; ─── 11. No regression — same/older signed version not offered ────────────────
FileAppend("No regression (same/older → up to date)`n", "*")
r := VerifyUpdateManifest(fx["sameVersion"]["body"])
Assert("11. same-version signed manifest verifies", r["ok"] = true)
Assert("11. same as local → no offer", TestCmpVer(localVer, r["version"]) = 0)

; ─── build-time trust anchor (spec §8.1 I-c) ──────────────────────────────────
FileAppend("Trust anchor (I-c)`n", "*")
anchorRaw := Ed25519_Base64UrlDecode(TRUSTED_UPDATE_KEYS["qs-2026"])
Assert("trust anchor decodes to 32 bytes", anchorRaw.Size = 32)
Assert("trust anchor SHA-256 == 761d22df…fde09b",
    BufToHex(Sha256(anchorRaw)) = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b")

FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
