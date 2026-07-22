#Requires AutoHotkey v2.0
#SingleInstance Off
#Include C:\QuickSay\Development\lib\JSON.ahk
#Include C:\QuickSay\Development\lib\dpapi.ahk
#Include C:\QuickSay\Development\lib\ed25519.ahk
#Include C:\QuickSay\Development\lib\license.ahk

out := A_Temp "\qs_devlicense.out"
lines := []

dat := License_ReadDat()
persisted := (dat != "" && dat.Has("trialMachineId")) ? dat["trialMachineId"] : "(none)"
lines.Push("persisted trialMachineId : " persisted)
lines.Push("ComputeMachineId()       : " ComputeMachineId())
lines.Push("_ComputeMachineIdLive()  : " _ComputeMachineIdLive())

jwt := (dat != "" && dat.Has("licenseJwt")) ? dat["licenseJwt"] : ""
if (jwt != "") {
    parts := StrSplit(jwt, ".")
    pl := (parts.Length = 3) ? _DecodeJwtSeg(parts[2]) : ""
    if (pl is Map) {
        lines.Push("jwt.machine claim        : " (pl.Has("machine") ? pl["machine"] : "(none)"))
        lines.Push("jwt.iss                  : " (pl.Has("iss") ? pl["iss"] : "(none)"))
        lines.Push("jwt.exp                  : " (pl.Has("exp") ? pl["exp"] : "(none)"))
    }
    sres := _VerifyJwtStatic(jwt)
    lines.Push("VerifyJwtStatic.valid    : " (sres["valid"] ? "true" : "false"))
} else {
    lines.Push("jwt                      : (none in license.dat)")
}

st := CheckLicenseState()
lines.Push("CheckLicenseState.state  : " st["state"])
lines.Push("DatPath                  : " License_DatPath())

f := FileOpen(out, "w", "UTF-8")
f.Write(_DevJoin(lines))
f.Close()
ExitApp

_DevJoin(arr) {
    s := ""
    for v in arr
        s .= v "`n"
    return s
}
