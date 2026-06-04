; Headless driver: verify a version.json file with the REAL app verifier.
; Usage: AutoHotkey64.exe /ErrorStdOut verify-file.ahk <path-to-version.json>
; Prints "ok=<bool> reason=<str> version=<str>"; exit 0 if ok, 1 if rejected, 2 on bad args.
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\..\lib\ed25519.ahk
#Include %A_ScriptDir%\..\..\lib\update-verify.ahk

if (A_Args.Length < 1) {
    FileAppend("usage: verify-file.ahk <version.json>`n", "*")
    ExitApp(2)
}
path := A_Args[1]
if !FileExist(path) {
    FileAppend("file not found: " path "`n", "*")
    ExitApp(2)
}
r := VerifyUpdateManifest(FileRead(path, "UTF-8"))
FileAppend("ok=" (r["ok"] ? "true" : "false") " reason=`"" r["reason"] "`" version=" r["version"] "`n", "*")
ExitApp(r["ok"] ? 0 : 1)
