; ==============================================================================
;  scripts/dev/dev-license.ahk — LOCAL DEVELOPER helper (NOT shipped, NOT signed
;  into a release). Lets the app owner mint/inspect a developer license against
;  their own license.dat using the real lib/license.ahk code paths, so the JWT's
;  machine binding and storage format match production exactly.
;
;  Modes (first CLI arg):
;    machineid          -> writes ComputeMachineId() to %TEMP%\qs_devlicense.out
;    inject <jwtFile>   -> stores the JWT from <jwtFile> into license.dat (DPAPI),
;                          then writes the resulting state to the .out file
;    state              -> writes CheckLicenseState() to the .out file
;
;  Output always goes to %TEMP%\qs_devlicense.out (UTF-8) so a GUI-subsystem AHK
;  process can hand a value back to the calling shell reliably.
; ==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include C:\QuickSay\Development\lib\JSON.ahk
#Include C:\QuickSay\Development\lib\dpapi.ahk
#Include C:\QuickSay\Development\lib\ed25519.ahk
#Include C:\QuickSay\Development\lib\license.ahk

_DevOut := A_Temp "\qs_devlicense.out"
mode := A_Args.Length >= 1 ? A_Args[1] : "state"

try {
    if (mode = "machineid") {
        _DevWrite(_DevOut, ComputeMachineId())
    } else if (mode = "inject") {
        if (A_Args.Length < 2)
            throw Error("inject mode needs a JWT file path")
        jwt := Trim(FileRead(A_Args[2], "UTF-8"), " `r`n`t")
        email := A_Args.Length >= 3 ? A_Args[3] : "dev@quicksay.app"
        _StoreLicenseJwt(jwt, email, 0, "dev-license")
        st := CheckLicenseState()
        _DevWrite(_DevOut, "state=" st["state"] " email=" st["email"] " exp=" st["exp"])
    } else {
        st := CheckLicenseState()
        _DevWrite(_DevOut, "state=" st["state"] " days=" st["daysRemaining"] " email=" st["email"] " exp=" st["exp"])
    }
} catch as e {
    _DevWrite(_DevOut, "ERROR: " e.Message)
}
ExitApp

_DevWrite(path, text) {
    f := FileOpen(path, "w", "UTF-8")
    f.Write(text)
    f.Close()
}
