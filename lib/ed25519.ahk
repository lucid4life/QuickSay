; ==============================================================================
;  lib/ed25519.ahk — offline Ed25519 (EdDSA) signature VERIFICATION for AHK v2
;
;  Shared verifier per T2 spec §3.4 / §8.1. Used by:
;    • lib/license.ahk  (T2.3) — verify license JWTs
;    • CheckForUpdates() (T2.5) — verify signed version.json
;
;  Verification only (no signing, no RNG): all inputs are public, so the code is
;  intentionally NOT constant-time — timing is irrelevant for verifying public data.
;
;  Public API:
;    VerifyEd25519(msg, sig, pubKey) -> true/false   (msg: Buffer|String; sig: 64-byte Buffer; pubKey: 32-byte Buffer)
;    Sha512(buf) -> 64-byte Buffer
;    Sha256(buf) -> 32-byte Buffer
;    Ed25519_Base64UrlDecode(str) -> Buffer
;    Ed25519_Base64UrlEncode(buf) -> String
;
;  Crypto background: edwards25519 over GF(2^255-19). Verify check is the
;  (non-cofactored) group equation [S]B == R + [k]A, k = SHA512(R||A||M) mod L.
;  Reference structure ported from RFC 8032 Appendix (extended homogeneous coords,
;  no per-op inversion; point equality via cross-multiplication).
;
;  Bignum representation: little-endian Array of base-2^17 limbs (limb[1] = LSB).
;  255 = 15*17 exactly, so 2^255 starts at limb[16] — making the mod-p fold
;  (2^255 ≡ 19) perfectly limb-aligned and cheap.
; ==============================================================================
#Requires AutoHotkey v2.0

; ───────────────────────────── SHA via Windows BCrypt ────────────────────────
_BCryptHash(algW, dataBuf, outLen) {
    hAlg := 0, hHash := 0
    if (DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlg, "wstr", algW, "ptr", 0, "uint", 0) != 0)
        throw Error("BCryptOpenAlgorithmProvider failed for " algW)
    try {
        if (DllCall("bcrypt\BCryptCreateHash", "ptr", hAlg, "ptr*", &hHash, "ptr", 0, "uint", 0, "ptr", 0, "uint", 0, "uint", 0) != 0)
            throw Error("BCryptCreateHash failed")
        if (dataBuf.Size > 0)
            DllCall("bcrypt\BCryptHashData", "ptr", hHash, "ptr", dataBuf, "uint", dataBuf.Size, "uint", 0)
        out := Buffer(outLen, 0)
        DllCall("bcrypt\BCryptFinishHash", "ptr", hHash, "ptr", out, "uint", outLen, "uint", 0)
    } finally {
        if (hHash)
            DllCall("bcrypt\BCryptDestroyHash", "ptr", hHash)
        if (hAlg)
            DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
    }
    return out
}
Sha512(buf) => _BCryptHash("SHA512", _AsBuf(buf), 64)
Sha256(buf) => _BCryptHash("SHA256", _AsBuf(buf), 32)

; Coerce a String (UTF-8, no terminator) or Buffer to a Buffer
_AsBuf(x) {
    if (x is Buffer)
        return x
    if (x is String) {
        n := StrPut(x, "UTF-8") - 1
        b := Buffer(n < 0 ? 0 : n)
        if (n > 0)
            StrPut(x, b, "UTF-8")
        return b
    }
    throw Error("_AsBuf: expected Buffer or String")
}

; ───────────────────────────── base64url ─────────────────────────────────────
_B64Rev() {
    rev := Map()
    abc := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    Loop StrLen(abc)
        rev[SubStr(abc, A_Index, 1)] := A_Index - 1
    return rev
}
Ed25519_Base64UrlDecode(s) {
    static rev := _B64Rev()
    bits := 0, nbits := 0, out := []
    Loop StrLen(s) {
        c := SubStr(s, A_Index, 1)
        if (c = "=" || !rev.Has(c))
            continue
        bits := (bits << 6) | rev[c]
        nbits += 6
        if (nbits >= 8) {
            nbits -= 8
            out.Push((bits >> nbits) & 0xFF)
        }
    }
    buf := Buffer(out.Length, 0)
    Loop out.Length
        NumPut("UChar", out[A_Index], buf, A_Index - 1)
    return buf
}
Ed25519_Base64UrlEncode(buf) {
    static abc := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    s := "", bits := 0, nbits := 0
    Loop buf.Size {
        bits := (bits << 8) | NumGet(buf, A_Index - 1, "UChar")
        nbits += 8
        while (nbits >= 6) {
            nbits -= 6
            s .= SubStr(abc, ((bits >> nbits) & 0x3F) + 1, 1)
        }
    }
    if (nbits > 0)
        s .= SubStr(abc, ((bits << (6 - nbits)) & 0x3F) + 1, 1)
    return s
}

; ───────────────────────────── bignum core (base 2^17) ───────────────────────
global _ED_BITS := 17, _ED_BASE := 131072, _ED_MASK := 131071

_BnTrim(a) {
    n := a.Length
    while (n > 1 && a[n] = 0)
        n--
    if (n = a.Length)
        return a
    out := []
    Loop n
        out.Push(a[A_Index])
    return out
}
_BnIsZero(a) {
    Loop a.Length
        if (a[A_Index] != 0)
            return false
    return true
}
_BnClone(a) {
    out := []
    Loop a.Length
        out.Push(a[A_Index])
    return out
}
_BnFromInt(n) {
    if (n = 0)
        return [0]
    a := []
    while (n > 0) {
        a.Push(n & _ED_MASK)
        n := n >> _ED_BITS
    }
    return a
}
_BnCmp(a, b) {   ; -1 if a<b, 0 if a=b, 1 if a>b
    a := _BnTrim(a), b := _BnTrim(b)
    if (a.Length != b.Length)
        return a.Length < b.Length ? -1 : 1
    i := a.Length
    while (i >= 1) {
        if (a[i] != b[i])
            return a[i] < b[i] ? -1 : 1
        i--
    }
    return 0
}
_BnAdd(a, b) {
    n := Max(a.Length, b.Length)
    res := [], carry := 0
    Loop n {
        i := A_Index
        t := (i <= a.Length ? a[i] : 0) + (i <= b.Length ? b[i] : 0) + carry
        res.Push(t & _ED_MASK)
        carry := t >> _ED_BITS
    }
    if (carry)
        res.Push(carry)
    return res
}
_BnSub(a, b) {   ; assumes a >= b
    res := [], borrow := 0
    Loop a.Length {
        i := A_Index
        t := a[i] - (i <= b.Length ? b[i] : 0) - borrow
        if (t < 0) {
            t += _ED_BASE
            borrow := 1
        } else
            borrow := 0
        res.Push(t)
    }
    return _BnTrim(res)
}
_BnMul(a, b) {
    res := []
    Loop (a.Length + b.Length)
        res.Push(0)
    Loop a.Length {
        i := A_Index
        ai := a[i]
        if (ai = 0)
            continue
        carry := 0
        Loop b.Length {
            j := A_Index
            idx := i + j - 1
            t := res[idx] + ai * b[j] + carry
            res[idx] := t & _ED_MASK
            carry := t >> _ED_BITS
        }
        idx := i + b.Length
        while (carry) {
            t := res[idx] + carry
            res[idx] := t & _ED_MASK
            carry := t >> _ED_BITS
            idx++
        }
    }
    return _BnTrim(res)
}
_BnMulSmall(a, k) {   ; a * small-int k  (unreduced)
    res := [], carry := 0
    Loop a.Length {
        t := a[A_Index] * k + carry
        res.Push(t & _ED_MASK)
        carry := t >> _ED_BITS
    }
    while (carry) {
        res.Push(carry & _ED_MASK)
        carry := carry >> _ED_BITS
    }
    return res.Length ? res : [0]
}
_BnShl1(a) {
    res := [], carry := 0
    Loop a.Length {
        t := (a[A_Index] << 1) | carry
        res.Push(t & _ED_MASK)
        carry := t >> _ED_BITS
    }
    if (carry)
        res.Push(carry)
    return res
}
_BnShr1(a) {
    res := [], carry := 0
    i := a.Length
    while (i >= 1) {
        cur := a[i] + (carry << _ED_BITS)
        res.InsertAt(1, cur >> 1)
        carry := cur & 1
        i--
    }
    return _BnTrim(res)
}
_BnBit(a, i) {
    li := (i // _ED_BITS) + 1
    if (li > a.Length)
        return 0
    return (a[li] >> Mod(i, _ED_BITS)) & 1
}
_BnBitLen(a) {
    a := _BnTrim(a)
    if (a.Length = 1 && a[1] = 0)
        return 0
    top := a.Length, v := a[top], bits := (top - 1) * _ED_BITS
    while (v > 0) {
        bits++
        v := v >> 1
    }
    return bits
}
; generic remainder a mod m (binary long division) — used for k mod L
_BnMod(a, m) {
    if (_BnCmp(a, m) < 0)
        return _BnClone(a)
    r := [0]
    i := _BnBitLen(a) - 1
    while (i >= 0) {
        r := _BnShl1(r)
        if (_BnBit(a, i))
            r[1] := r[1] | 1
        if (_BnCmp(r, m) >= 0)
            r := _BnSub(r, m)
        i--
    }
    return r
}
_BnFromBytesLE(buf, len := 0) {
    if (len = 0)
        len := buf.Size
    totalBits := len * 8
    nLimbs := (totalBits + _ED_BITS - 1) // _ED_BITS
    a := []
    Loop nLimbs
        a.Push(0)
    Loop totalBits {
        bitIdx := A_Index - 1
        byteVal := NumGet(buf, bitIdx // 8, "UChar")
        if ((byteVal >> Mod(bitIdx, 8)) & 1) {
            li := (bitIdx // _ED_BITS) + 1
            a[li] := a[li] | (1 << Mod(bitIdx, _ED_BITS))
        }
    }
    return _BnTrim(a)
}

; ───────────────────────────── field arithmetic mod p = 2^255-19 ─────────────
global _ED_P := "", _ED_L := "", _ED_ONE := "", _ED_ZERO := "", _ED_D := ""
global _ED_I := "", _ED_B := "", _ED_EXP_INV := "", _ED_EXP_SQRT := ""

_FpReduce(a) {
    global _ED_P
    a := _BnTrim(a)
    while (a.Length > 15) {
        low := [], hi := []
        Loop 15
            low.Push(a[A_Index])
        Loop (a.Length - 15)
            hi.Push(a[15 + A_Index])
        a := _BnAdd(low, _BnMulSmall(hi, 19))
        a := _BnTrim(a)
    }
    while (_BnCmp(a, _ED_P) >= 0)
        a := _BnSub(a, _ED_P)
    ; build a fresh, exactly-15-limb canonical element (never mutate the input —
    ; _BnTrim can return the input by reference, and the constants must stay intact)
    res := []
    Loop 15
        res.Push(A_Index <= a.Length ? a[A_Index] : 0)
    return res
}
_FpIsZero(a) {
    r := _FpReduce(a)
    Loop r.Length
        if (r[A_Index] != 0)
            return false
    return true
}
_FpAdd(a, b) => _FpReduce(_BnAdd(a, b))
_FpSub(a, b) {
    global _ED_P
    ; a + p - b  (keeps positive; both a,b are reduced < p)
    return _FpReduce(_BnSub(_BnAdd(a, _ED_P), b))
}
_FpMul(a, b) => _FpReduce(_BnMul(a, b))
_FpSqr(a) => _FpReduce(_BnMul(a, a))
_FpMulSmall(a, k) => _FpReduce(_BnMulSmall(a, k))
_FpModExp(base, expBn) {
    global _ED_ONE
    result := _BnClone(_ED_ONE)
    b := _FpReduce(base)
    bl := _BnBitLen(expBn)
    i := 0
    while (i < bl) {
        if (_BnBit(expBn, i))
            result := _FpMul(result, b)
        b := _FpSqr(b)
        i++
    }
    return result
}
_FpInv(a) {
    global _ED_EXP_INV
    return _FpModExp(a, _ED_EXP_INV)   ; a^(p-2) mod p
}
_FpNeg(a) {
    global _ED_ZERO
    return _FpSub(_ED_ZERO, a)
}

; ───────────────────────────── curve points (extended coords [X,Y,Z,T]) ──────
_PtAdd(P, Q) {
    global _ED_D
    A := _FpMul(_FpSub(P[2], P[1]), _FpSub(Q[2], Q[1]))
    B := _FpMul(_FpAdd(P[2], P[1]), _FpAdd(Q[2], Q[1]))
    C := _FpMulSmall(_FpMul(_FpMul(P[4], Q[4]), _ED_D), 2)
    D := _FpMulSmall(_FpMul(P[3], Q[3]), 2)
    E := _FpSub(B, A)
    F := _FpSub(D, C)
    G := _FpAdd(D, C)
    H := _FpAdd(B, A)
    return [_FpMul(E, F), _FpMul(G, H), _FpMul(F, G), _FpMul(E, H)]
}
_PtMul(s, P) {
    global _ED_ZERO, _ED_ONE
    Q := [_BnClone(_ED_ZERO), _BnClone(_ED_ONE), _BnClone(_ED_ONE), _BnClone(_ED_ZERO)]
    PP := P
    bl := _BnBitLen(s)
    i := 0
    while (i < bl) {
        if (_BnBit(s, i))
            Q := _PtAdd(Q, PP)
        PP := _PtAdd(PP, PP)
        i++
    }
    return Q
}
_PtEqual(P, Q) {
    ; X1*Z2 == X2*Z1 and Y1*Z2 == Y2*Z1  (mod p)
    if (!_FpIsZero(_FpSub(_FpMul(P[1], Q[3]), _FpMul(Q[1], P[3]))))
        return false
    if (!_FpIsZero(_FpSub(_FpMul(P[2], Q[3]), _FpMul(Q[2], P[3]))))
        return false
    return true
}
; decode a 32-byte compressed point → [X,Y,Z,T], or "" on failure (fail closed)
_PtDecompress(buf) {
    global _ED_P, _ED_ONE, _ED_ZERO, _ED_D, _ED_I, _ED_EXP_SQRT
    if (buf.Size != 32)
        return ""
    ; copy + extract sign bit (bit 255 = top bit of byte 31)
    yb := Buffer(32)
    DllCall("RtlMoveMemory", "ptr", yb, "ptr", buf, "uptr", 32)
    sign := (NumGet(yb, 31, "UChar") >> 7) & 1
    NumPut("UChar", NumGet(yb, 31, "UChar") & 0x7F, yb, 31)
    y := _BnFromBytesLE(yb, 32)
    if (_BnCmp(y, _ED_P) >= 0)
        return ""
    y2 := _FpSqr(y)
    u := _FpSub(y2, _ED_ONE)
    v := _FpAdd(_FpMul(_ED_D, y2), _ED_ONE)
    x2 := _FpMul(u, _FpInv(v))
    if (_FpIsZero(x2)) {
        if (sign)
            return ""
        x := _BnClone(_ED_ZERO)
    } else {
        x := _FpModExp(x2, _ED_EXP_SQRT)
        if (!_FpIsZero(_FpSub(_FpSqr(x), x2)))
            x := _FpMul(x, _ED_I)
        if (!_FpIsZero(_FpSub(_FpSqr(x), x2)))
            return ""
    }
    xr := _FpReduce(x)
    if ((xr[1] & 1) != sign)
        x := _FpNeg(x)
    xr := _FpReduce(x)
    ; x==0 with sign set is invalid
    isZero := true
    Loop xr.Length
        if (xr[A_Index] != 0)
            isZero := false
    if (isZero && sign)
        return ""
    return [xr, _FpReduce(y), _BnClone(_ED_ONE), _FpMul(xr, y)]
}

; ───────────────────────────── one-time constant init ────────────────────────
_BnFromHexBE(hex) {
    if (SubStr(hex, 1, 2) = "0x")
        hex := SubStr(hex, 3)
    if (Mod(StrLen(hex), 2) != 0)
        hex := "0" hex
    nbytes := StrLen(hex) // 2
    buf := Buffer(nbytes)
    Loop nbytes {
        byteVal := Integer("0x" SubStr(hex, (A_Index - 1) * 2 + 1, 2))
        NumPut("UChar", byteVal, buf, nbytes - A_Index)   ; reverse BE → LE
    }
    return _BnFromBytesLE(buf, nbytes)
}
_Ed25519Init() {
    global _ED_P, _ED_L, _ED_ONE, _ED_ZERO, _ED_D, _ED_I, _ED_B, _ED_EXP_INV, _ED_EXP_SQRT
    static done := false
    if (done)
        return
    _ED_ZERO := [0]
    _ED_ONE := _BnFromInt(1)
    _ED_P := _BnFromHexBE("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed")
    _ED_L := _BnFromHexBE("1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed")
    _ED_EXP_INV := _BnSub(_ED_P, _BnFromInt(2))                 ; p-2
    ; (p+3)/8  (p+3 divisible by 8)
    _ED_EXP_SQRT := _BnShr1(_BnShr1(_BnShr1(_BnAdd(_ED_P, _BnFromInt(3)))))
    ; d = -121665 / 121666 (mod p)
    _ED_D := _FpMul(_FpNeg(_BnFromInt(121665)), _FpInv(_BnFromInt(121666)))
    ; sqrt(-1) = 2^((p-1)/4) mod p ; (p-1)/4
    expI := _BnShr1(_BnShr1(_BnSub(_ED_P, _BnFromInt(1))))
    _ED_I := _FpModExp(_BnFromInt(2), expI)
    ; base point B: By = 4/5 ; Bx = recover_x(By, 0)
    By := _FpMul(_BnFromInt(4), _FpInv(_BnFromInt(5)))
    Bx := _RecoverX(By, 0)
    _ED_B := [Bx, By, _BnClone(_ED_ONE), _FpMul(Bx, By)]
    done := true
}
_RecoverX(y, sign) {
    global _ED_ONE, _ED_ZERO, _ED_D, _ED_I, _ED_EXP_SQRT
    y2 := _FpSqr(y)
    u := _FpSub(y2, _ED_ONE)
    v := _FpAdd(_FpMul(_ED_D, y2), _ED_ONE)
    x2 := _FpMul(u, _FpInv(v))
    x := _FpModExp(x2, _ED_EXP_SQRT)
    if (!_FpIsZero(_FpSub(_FpSqr(x), x2)))
        x := _FpMul(x, _ED_I)
    xr := _FpReduce(x)
    if ((xr[1] & 1) != sign)
        x := _FpNeg(x)
    return _FpReduce(x)
}

; ───────────────────────────── public verify ─────────────────────────────────
VerifyEd25519(msg, sig, pubKey) {
    global _ED_L, _ED_B
    try {
        _Ed25519Init()
        msgBuf := _AsBuf(msg)
        if (!(sig is Buffer) || sig.Size != 64)
            return false
        if (!(pubKey is Buffer) || pubKey.Size != 32)
            return false
        A := _PtDecompress(pubKey)
        if (A == "")
            return false
        Rbuf := _BufSlice(sig, 0, 32)
        Sbuf := _BufSlice(sig, 32, 32)
        R := _PtDecompress(Rbuf)
        if (R == "")
            return false
        S := _BnFromBytesLE(Sbuf, 32)
        if (_BnCmp(S, _ED_L) >= 0)         ; S must be canonical (< L)
            return false
        hinput := _BufCat([Rbuf, pubKey, msgBuf])
        h := Sha512(hinput)
        k := _BnMod(_BnFromBytesLE(h, 64), _ED_L)
        sB := _PtMul(S, _ED_B)
        kA := _PtMul(k, A)
        rhs := _PtAdd(R, kA)
        return _PtEqual(sB, rhs)
    } catch {
        return false   ; any internal failure → fail closed
    }
}

_BufSlice(buf, off, len) {
    out := Buffer(len)
    DllCall("RtlMoveMemory", "ptr", out, "ptr", buf.Ptr + off, "uptr", len)
    return out
}
_BufCat(bufs) {
    total := 0
    for b in bufs
        total += b.Size
    out := Buffer(total)
    pos := 0
    for b in bufs {
        if (b.Size > 0)
            DllCall("RtlMoveMemory", "ptr", out.Ptr + pos, "ptr", b, "uptr", b.Size)
        pos += b.Size
    }
    return out
}
