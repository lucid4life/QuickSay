; ==============================================================================
;  lib/crash-optin-ui.ahk — First-run crash-reporting opt-in modal (T2.4)
;
;  A small WebView2 window shown once on first run after this feature ships
;  (crash_reporting_prompted=false). Matches the paywall/onboarding visual
;  language via gui/crash-optin.html + gui/settings.css design tokens.
;
;  Consent contract (spec §6.5): default OFF until the user answers. Whatever they
;  pick → CrashOptInUI.OnAnswer.Call(optedIn:bool). No envelope is ever sent before
;  this resolves. If WebView2 is unavailable, a native Yes/No MsgBox still captures
;  consent (so the modal can never silently fail open).
;
;  Bridge (mirrors PaywallUI):
;    JS → AHK : postMessage(JSON{action:"answer", data:{optedIn:bool}})
; ==============================================================================
#Requires AutoHotkey v2.0

class CrashOptInUI {
    static gui := ""
    static wvc := ""
    static wv := ""
    static OnAnswer := ""           ; callback(optedIn:bool)
    static _answered := false
    static _iconBig := 0
    static _iconSmall := 0

    static Show() {
        if (this.gui) {                          ; already open → focus
            try WinActivate("ahk_id " this.gui.Hwnd)
            return
        }
        this._answered := false

        htmlPath := A_ScriptDir "\gui\crash-optin.html"
        if !FileExist(htmlPath) {
            this._FallbackMsgBox()
            return
        }

        this.gui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "QuickSay")
        this.gui.OnEvent("Close", (*) => CrashOptInUI._OnCloseWithoutAnswer())

        iconPath := A_ScriptDir "\gui\assets\icon.ico"
        if FileExist(iconPath) {
            this._iconBig   := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", 32, "Int", 32, "UInt", 0x10, "Ptr")
            this._iconSmall := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", 16, "Int", 16, "UInt", 0x10, "Ptr")
            if (this._iconBig) {
                SendMessage(0x0080, 1, this._iconBig, , "ahk_id " this.gui.Hwnd)
                SendMessage(0x0080, 0, this._iconSmall ? this._iconSmall : this._iconBig, , "ahk_id " this.gui.Hwnd)
            }
        }

        this.gui.Show("w460 h500")   ; tall enough for the full card incl. "No thanks" (card ≈ 475px)
        try {
            this.wvc := WebView2.create(this.gui.Hwnd)
            this.wv := this.wvc.CoreWebView2
            this.wv.add_WebMessageReceived(ObjBindMethod(this, "OnWebMessage"))
            q := Chr(34)
            this.wv.AddScriptToExecuteOnDocumentCreated("var m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';m.content=" q "default-src 'self' 'unsafe-inline'; img-src 'self' data:;" q ";document.head.appendChild(m);")
            this.wv.Navigate("file:///" StrReplace(htmlPath, "\", "/"))
            this.gui.Move(,, 460, 500)
            this.CenterWindow(this.gui)
            this.wvc.Fill()
        } catch as err {
            this.Close()
            this._FallbackMsgBox()
        }
    }

    static OnWebMessage(wv, args) {
        try {
            msg := JSON.Parse(args.WebMessageAsJson)
            if (Type(msg) = "String")
                msg := JSON.Parse(msg)
            action := (Type(msg) = "Map" && msg.Has("action")) ? msg["action"] : ""
            if (action = "answer") {
                optedIn := (msg.Has("data") && Type(msg["data"]) = "Map" && msg["data"].Has("optedIn"))
                    ? (msg["data"]["optedIn"] = true || msg["data"]["optedIn"] = 1) : false
                this._Resolve(optedIn)
            }
        } catch as err {
            OutputDebug("CrashOptInUI.OnWebMessage error: " err.Message)
        }
    }

    static _FallbackMsgBox() {
        ; Native consent capture if WebView2 / HTML is unavailable. Defaults to "No".
        res := MsgBox("Help us fix bugs?`n`nQuickSay can send anonymous crash reports — no transcripts, no audio, no personal information.`n`nTurn on anonymous crash reports?",
            "QuickSay", "YesNo Icon?")
        this._Resolve(res = "Yes")
    }

    static _Resolve(optedIn) {
        if (this._answered)
            return
        this._answered := true
        cb := this.OnAnswer
        this.Close()
        if (cb != "")
            try cb.Call(optedIn ? true : false)
    }

    ; Closing the window without clicking a button = "No thanks" (stay OFF, but
    ; mark prompted so we don't nag again).
    static _OnCloseWithoutAnswer() {
        this._Resolve(false)
    }

    static _PostToJs(fn, data) {
        if (this.wv)
            try this.wv.PostWebMessageAsString(JSON.Stringify(Map("function", fn, "data", data)))
    }

    static CenterWindow(g) {
        g.GetPos(,, &w, &h)
        MonitorGetWorkArea(, &l, &t, &r, &b)
        g.Move(l + (r - l - w) // 2, t + (b - t - h) // 2)
    }

    static Close(*) {
        if (this._iconBig) {
            DllCall("DestroyIcon", "Ptr", this._iconBig)
            this._iconBig := 0
        }
        if (this._iconSmall) {
            DllCall("DestroyIcon", "Ptr", this._iconSmall)
            this._iconSmall := 0
        }
        if (this.gui)
            try this.gui.Destroy()
        this.gui := ""
        this.wv := ""
        this.wvc := ""
    }
}
