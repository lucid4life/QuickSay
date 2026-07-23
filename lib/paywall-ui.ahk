; ==============================================================================
;  lib/paywall-ui.ahk — Paywall modal host (T2.3)
;
;  A separate WebView2 window (so the user can purchase even if Settings is broken).
;  Shown when the trial ends or a license is revoked. "Blocking" per spec §11 Q1:
;  the window can be closed, but recording stays disabled until activation — the
;  recording gate (StartRecording) re-shows this modal on the next hotkey press.
;
;  Bridge (mirrors SettingsUI):
;    AHK → JS : wv.PostWebMessageAsString(JSON{function,data}) → window[function](data)
;    JS → AHK : postMessage(JSON{action,data})                → PaywallUI.OnWebMessage
;
;  QuickSay.ahk sets PaywallUI.OnLicensed := <callback> to re-enable recording after
;  a successful activation.
; ==============================================================================
#Requires AutoHotkey v2.0

class PaywallUI {
    static gui := ""
    static wvc := ""
    static wv := ""
    static mode := "expired"
    static checkoutUrl := ""
    static OnLicensed := ""          ; callback invoked after a successful activation
    static _iconBig := 0
    static _iconSmall := 0

    static Show(mode := "expired") {
        ; Already open → just focus + update mode
        if (this.gui) {
            this.mode := mode
            try WinActivate("ahk_id " this.gui.Hwnd)
            this._PostToJs("setMode", Map("mode", mode))
            return
        }
        this.mode := mode

        htmlPath := A_ScriptDir "\gui\paywall.html"
        if !FileExist(htmlPath) {
            MsgBox("Your QuickSay trial has ended. The purchase screen is missing — please reinstall, or buy a license at quicksay.app.", "QuickSay", "Icon!")
            return
        }

        this.gui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "QuickSay")
        this.gui.OnEvent("Close", (*) => PaywallUI.Close())

        ; Window icon (match settings)
        iconPath := A_ScriptDir "\gui\assets\icon.ico"
        if FileExist(iconPath) {
            this._iconBig   := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", 32, "Int", 32, "UInt", 0x10, "Ptr")
            this._iconSmall := DllCall("LoadImage", "Ptr", 0, "Str", iconPath, "UInt", 1, "Int", 16, "Int", 16, "UInt", 0x10, "Ptr")
            if (this._iconBig) {
                ; DllCall (raw HWND) — works on the not-yet-shown window; AHK's SendMessage
                ; with "ahk_id" would throw "target window not found" (DetectHiddenWindows off).
                DllCall("SendMessage", "Ptr", this.gui.Hwnd, "UInt", 0x0080, "Ptr", 1, "Ptr", this._iconBig)
                DllCall("SendMessage", "Ptr", this.gui.Hwnd, "UInt", 0x0080, "Ptr", 0, "Ptr", this._iconSmall ? this._iconSmall : this._iconBig)
            }
        }

        this.gui.Show("w520 h640")
        try {
            this.wvc := WebView2.create(this.gui.Hwnd)
            this.wv := this.wvc.CoreWebView2
            this.wv.add_WebMessageReceived(ObjBindMethod(this, "OnWebMessage"))
            q := Chr(34)
            this.wv.AddScriptToExecuteOnDocumentCreated("var m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';m.content=" q "default-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" q ";document.head.appendChild(m);")
            this.wv.Navigate("file:///" StrReplace(htmlPath, "\", "/"))
            this.gui.Move(,, 520, 640)
            this.CenterWindow(this.gui)
            this.wvc.Fill()
        } catch as err {
            MsgBox("Your QuickSay trial has ended. The purchase screen needs Microsoft Edge WebView2.`nBuy or activate a license at quicksay.app.", "QuickSay", "Icon!")
            this.Close()
        }
    }

    static OnWebMessage(wv, args) {
        try {
            msg := JSON.Parse(args.WebMessageAsJson)
            if (Type(msg) = "String")
                msg := JSON.Parse(msg)
            action := (Type(msg) = "Map" && msg.Has("action")) ? msg["action"] : ""
            switch action {
                case "ready":
                    this._PostToJs("setMode", Map("mode", this.mode))
                    this._PushPricing()
                    this._PostToJs("initMachineId", Map("machineId", ComputeMachineId()))
                case "openCheckout":
                    this._OpenCheckout()
                case "activate":
                    key := (msg.Has("data") && Type(msg["data"]) = "Map" && msg["data"].Has("key")) ? msg["data"]["key"] : ""
                    this._HandleActivate(key)
                case "openUrl":
                    url := (msg.Has("data") && Type(msg["data"]) = "Map" && msg["data"].Has("url")) ? msg["data"]["url"] : ""
                    if (RegExMatch(url, "^https://"))
                        try Run(url)
                case "close":
                    this.Close()
            }
        } catch as err {
            OutputDebug("PaywallUI.OnWebMessage error: " err.Message)
        }
    }

    static _PushPricing() {
        p := LicenseFetchPricing()
        out := Map()
        if (p is Map && p.Has("price")) {
            out["available"] := true
            out["tier"] := p.Has("tier") ? p["tier"] : ""
            out["price"] := p["price"]
            out["currency"] := p.Has("currency") ? p["currency"] : "USD"
            if (p.Has("ordersRemaining") && p["ordersRemaining"] != "" && !(p["ordersRemaining"] == JSON.null))
                out["ordersRemaining"] := p["ordersRemaining"]
            out["financingAvailable"] := (p.Has("financingAvailable") && (p["financingAvailable"] = true || p["financingAvailable"] = 1))
            if (p.Has("checkoutUrl") && p["checkoutUrl"] is String)
                this.checkoutUrl := p["checkoutUrl"]
        } else {
            out["available"] := false       ; offline / worker down → "Get lifetime access", price at checkout
        }
        this._PostToJs("setPricing", out)
    }

    static _OpenCheckout() {
        global LEMONSQUEEZY_PRODUCT_URL
        url := this.checkoutUrl
        if (url = "" || !RegExMatch(url, "^https://"))
            url := LEMONSQUEEZY_PRODUCT_URL                  ; compiled placeholder (set at M.3)
        if (url = "" || !RegExMatch(url, "^https://"))
            url := "https://quicksay.app/buy"                ; last-resort fallback
        try Run(url)
    }

    static _HandleActivate(key) {
        if (Trim(key) = "") {
            this._PostToJs("setActivationResult", Map("success", false, "message", "Please paste your license key first."))
            return
        }
        result := ActivateLicense(Trim(key))                 ; HTTP + stores the JWT on success
        if (result["ok"]) {
            this._PostToJs("setActivationResult", Map("success", true, "message", "Activated — thank you! QuickSay is ready to use."))
            cb := this.OnLicensed
            ; close shortly after the success message; then notify the app to re-enable recording
            SetTimer(() => (PaywallUI.Close(), (cb != "" ? cb.Call() : 0)), -1400)
        } else {
            this._PostToJs("setActivationResult", Map("success", false, "message", result["message"]))
        }
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

    static IsOpen() => (this.gui != "")
}
