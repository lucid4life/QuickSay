; ==============================================================================
;  DPAPI ENCRYPTION/DECRYPTION (Windows Data Protection API)
;  Shared library — included by QuickSay.ahk, settings_ui.ahk, onboarding_ui.ahk
;  Uses application-specific entropy so generic DPAPI tools cannot decrypt.
; ==============================================================================

; Application-specific entropy — prevents generic DPAPI decryption tools from
; extracting the key without knowing this value. NOT a secret (ships in source),
; but raises the bar from "run any DPAPI tool" to "must reverse-engineer the app".
_DPAPIEntropy() {
    static entropy := "QuickSay-v1-entropy-2026"
    entropyLen := StrPut(entropy, "UTF-8") - 1
    buf := Buffer(entropyLen)
    StrPut(entropy, buf, "UTF-8")
    blob := Buffer(A_PtrSize * 2)
    NumPut("uint", entropyLen, blob, 0)
    NumPut("ptr", buf.Ptr, blob, A_PtrSize)
    return { blob: blob, buf: buf }
}

DPAPIEncrypt(plainText) {
    if (plainText == "")
        return ""

    utf8Len := StrPut(plainText, "UTF-8") - 1
    inputBuf := Buffer(utf8Len)
    StrPut(plainText, inputBuf, "UTF-8")

    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", utf8Len, inputBlob, 0)
    NumPut("ptr", inputBuf.Ptr, inputBlob, A_PtrSize)

    ent := _DPAPIEntropy()
    outputBlob := Buffer(A_PtrSize * 2, 0)

    result := DllCall("crypt32\CryptProtectData",
        "ptr", inputBlob,
        "ptr", 0,
        "ptr", ent.blob,
        "ptr", 0,
        "ptr", 0,
        "int", 1,
        "ptr", outputBlob)

    if !result
        return ""

    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")

    DllCall("crypt32\CryptBinaryToStringW",
        "ptr", outPtr,
        "uint", outSize,
        "uint", 0x40000001,
        "ptr", 0,
        "uint*", &b64Len := 0)

    b64Buf := Buffer(b64Len * 2)
    DllCall("crypt32\CryptBinaryToStringW",
        "ptr", outPtr,
        "uint", outSize,
        "uint", 0x40000001,
        "ptr", b64Buf,
        "uint*", &b64Len)

    DllCall("LocalFree", "ptr", outPtr)

    return StrGet(b64Buf, "UTF-16")
}

DPAPIDecrypt(base64Text) {
    if (base64Text == "")
        return ""

    DllCall("crypt32\CryptStringToBinaryW",
        "str", base64Text,
        "uint", 0,
        "uint", 1,
        "ptr", 0,
        "uint*", &binLen := 0,
        "ptr", 0,
        "ptr", 0)

    if (binLen == 0)
        return ""

    binBuf := Buffer(binLen)
    DllCall("crypt32\CryptStringToBinaryW",
        "str", base64Text,
        "uint", 0,
        "uint", 1,
        "ptr", binBuf,
        "uint*", &binLen,
        "ptr", 0,
        "ptr", 0)

    inputBlob := Buffer(A_PtrSize * 2)
    NumPut("uint", binLen, inputBlob, 0)
    NumPut("ptr", binBuf.Ptr, inputBlob, A_PtrSize)

    ent := _DPAPIEntropy()
    outputBlob := Buffer(A_PtrSize * 2, 0)

    result := DllCall("crypt32\CryptUnprotectData",
        "ptr", inputBlob,
        "ptr", 0,
        "ptr", ent.blob,
        "ptr", 0,
        "ptr", 0,
        "int", 1,
        "ptr", outputBlob)

    if !result
        return ""

    outSize := NumGet(outputBlob, 0, "uint")
    outPtr := NumGet(outputBlob, A_PtrSize, "ptr")

    decrypted := StrGet(outPtr, outSize, "UTF-8")

    DllCall("LocalFree", "ptr", outPtr)

    return decrypted
}
