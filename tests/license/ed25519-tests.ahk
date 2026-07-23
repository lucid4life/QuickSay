; ==============================================================================
;  T2.3 — lib/ed25519.ahk unit tests (headless, no running QuickSay needed)
;  Usage: AutoHotkey64.exe /ErrorStdOut ed25519-tests.ahk
;  Exit 0 = all pass, Exit 1 = failures. Requires fixtures.json (gen-fixtures.mjs).
;
;  Covers: SHA-512 KAT · RFC 8032 §7.1 Ed25519 KAT · Node interop (non-ASCII msg)
;          · tamper rejection · wrong-key rejection · build-time public-key
;          SHA-256 trust-anchor assert (spec §8.1 I-c).
; ==============================================================================
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\ed25519.ahk

global gPass := 0, gFail := 0

Assert(name, cond) {
    global gPass, gFail
    if (cond) {
        FileAppend("  PASS  " name "`n", "*"), gPass++
    } else {
        FileAppend("  FAIL  " name "`n", "*"), gFail++
    }
}

; hex string → Buffer of raw bytes
HexToBuf(hex) {
    n := StrLen(hex) // 2
    buf := Buffer(n)
    Loop n
        NumPut("UChar", Integer("0x" . SubStr(hex, (A_Index - 1) * 2 + 1, 2)), buf, A_Index - 1)
    return buf
}

; Buffer → lowercase hex string
BufToHex(buf) {
    s := ""
    Loop buf.Size
        s .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return s
}

; ASCII/UTF-8 string → Buffer (no null terminator)
StrToBuf(str) {
    n := StrPut(str, "UTF-8") - 1
    buf := Buffer(n)
    StrPut(str, buf, "UTF-8")
    return buf
}

; Flip one byte in a copy of a buffer
FlipByte(buf, idx) {
    cp := Buffer(buf.Size)
    DllCall("RtlMoveMemory", "ptr", cp, "ptr", buf, "uptr", buf.Size)
    NumPut("UChar", NumGet(cp, idx, "UChar") ^ 0xFF, cp, idx)
    return cp
}

fxPath := A_ScriptDir . "\fixtures.json"
if !FileExist(fxPath) {
    FileAppend("FATAL: fixtures.json missing — run: node tests/license/gen-fixtures.mjs`n", "*")
    ExitApp(1)
}
fx := JSON.Parse(FileRead(fxPath, "UTF-8"))

; ─── SHA-512 known-answer vectors (NIST) ──────────────────────────────────────
FileAppend("SHA-512 KAT`n", "*")
Assert("SHA-512('') matches",
    BufToHex(Sha512(StrToBuf(""))) = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
Assert("SHA-512('abc') matches",
    BufToHex(Sha512(StrToBuf("abc"))) = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")

; ─── RFC 8032 §7.1 TEST 2 — independent Ed25519 KAT ───────────────────────────
FileAppend("RFC 8032 Ed25519 KAT`n", "*")
rfcPub := HexToBuf(fx["rfc8032"]["pubHex"])
rfcMsg := HexToBuf(fx["rfc8032"]["msgHex"])
rfcSig := HexToBuf(fx["rfc8032"]["sigHex"])
Assert("RFC8032 TEST2 verifies (valid)", VerifyEd25519(rfcMsg, rfcSig, rfcPub) = true)
Assert("RFC8032 tampered signature rejected", VerifyEd25519(rfcMsg, FlipByte(rfcSig, 10), rfcPub) = false)
Assert("RFC8032 tampered message rejected",   VerifyEd25519(FlipByte(rfcMsg, 0), rfcSig, rfcPub) = false)
Assert("RFC8032 wrong public key rejected",   VerifyEd25519(rfcMsg, rfcSig, FlipByte(rfcPub, 5)) = false)

; ─── Node interop (independent fresh keypair; non-ASCII message) ──────────────
FileAppend("Node interop`n", "*")
ipPub := HexToBuf(fx["interop"]["pubHex"])
ipMsg := HexToBuf(fx["interop"]["msgHex"])
ipSig := HexToBuf(fx["interop"]["sigHex"])
Assert("interop verifies (valid)", VerifyEd25519(ipMsg, ipSig, ipPub) = true)
Assert("interop accepts string message", VerifyEd25519(StrToBuf(fx["interop"]["msgUtf8"]), ipSig, ipPub) = true)
Assert("interop tampered sig rejected", VerifyEd25519(ipMsg, FlipByte(ipSig, 32), ipPub) = false)

; ─── Malformed inputs fail closed ─────────────────────────────────────────────
FileAppend("Malformed inputs fail closed`n", "*")
Assert("sig wrong length (63) rejected", VerifyEd25519(rfcMsg, Buffer(63, 0), rfcPub) = false)
Assert("pubkey wrong length (31) rejected", VerifyEd25519(rfcMsg, rfcSig, Buffer(31, 0)) = false)
Assert("all-zero sig rejected", VerifyEd25519(rfcMsg, Buffer(64, 0), rfcPub) = false)

; ─── Build-time trust-anchor assert (spec §8.1 I-c) ───────────────────────────
FileAppend("Trust anchor (I-c)`n", "*")
qsRaw := Ed25519_Base64UrlDecode("UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8")
Assert("qs-2026 raw pubkey decodes to 32 bytes", qsRaw.Size = 32)
Assert("qs-2026 raw pubkey SHA-256 == 761d22df…fde09b",
    BufToHex(Sha256(qsRaw)) = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b")

FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
