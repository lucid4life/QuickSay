; ==============================================================================
;  QuickSay Floating Widget — GDI+ status pill
;  Click to toggle recording, drag to reposition
;  Uses GDI class from lib/GDI.ahk (loaded via web-overlay.ahk)
; ==============================================================================

class FloatingWidget {
    static gui := ""
    static width := 44
    static height := 44
    static isVisible := false
    static currentStatus := "idle"  ; idle, recording, processing, error
    static pulsePhase := 0
    static posX := 0
    static posY := 0
    static isDragging := false
    static _captured := false       ; SetCapture active (mousedown state)
    static dragStartWinX := 0
    static dragStartWinY := 0
    static mouseDownX := 0
    static mouseDownY := 0
    static wasClick := true
    static timerFn := ""
    static configFile := A_ScriptDir "\config.json"

    static Show(config := "") {
        if (this.isVisible)
            return

        ; Get position from config (internal keys: widget_x, widget_y)
        this.posX := 0
        this.posY := 0
        if (Type(config) = "Map") {
            if config.Has("widget_x")
                this.posX := config["widget_x"]
            if config.Has("widget_y")
                this.posY := config["widget_y"]
        }
        ; If in-memory config didn't have position, try reading from file
        if (this.posX = 0 && this.posY = 0) {
            try {
                configText := FileRead(this.configFile, "UTF-8")
                cfg := JSON.Parse(configText)
                if (Type(cfg) = "Map") {
                    if cfg.Has("widgetX")
                        this.posX := cfg["widgetX"]
                    if cfg.Has("widgetY")
                        this.posY := cfg["widgetY"]
                }
            }
        }

        ; Validate saved position is on a current monitor
        if (this.posX != 0 || this.posY != 0) {
            onScreen := false
            monCount := MonitorGetCount()
            Loop monCount {
                MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)
                if (this.posX >= mL && this.posX < mR && this.posY >= mT && this.posY < mB) {
                    onScreen := true
                    break
                }
            }
            if (!onScreen) {
                this.posX := 0
                this.posY := 0
            }
        }

        ; Default position: right edge, vertical center of active monitor
        if (this.posX = 0 && this.posY = 0) {
            MonitorGetWorkArea(MonitorGetPrimary(), &_mL, &monTop, &monRight, &monBottom)
            try {
                activeHwnd := WinExist("A")
                if (activeHwnd) {
                    WinGetPos(&winX, &winY, &winW, &winH, activeHwnd)
                    winCenterX := winX + (winW // 2)
                    winCenterY := winY + (winH // 2)
                    monCount := MonitorGetCount()
                    Loop monCount {
                        MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                        if (winCenterX >= mLeft && winCenterX < mRight && winCenterY >= mTop && winCenterY < mBottom) {
                            monRight := mRight
                            monTop := mTop
                            monBottom := mBottom
                            break
                        }
                    }
                }
            }
            this.posX := monRight - this.width - 12
            this.posY := monTop + (monBottom - monTop - this.height) // 2
        }

        ; Ensure GDI+ is started
        GDI.Startup()

        ; Create layered window — WS_EX_NOACTIVATE (0x08000000) prevents focus steal
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 +E0x08000000")
        this.gui.Show("x" this.posX " y" this.posY " w" this.width " h" this.height " NoActivate")

        ; Mouse handlers
        this.gui.OnEvent("Close", (*) => this.Hide())

        ; Store bound method references so Hide() can unregister the same objects
        this._boundLButtonDown := ObjBindMethod(this, "OnLButtonDown")
        this._boundLButtonUp := ObjBindMethod(this, "OnLButtonUp")
        this._boundMouseMove := ObjBindMethod(this, "OnMouseMove")
        this._boundRButtonUp := ObjBindMethod(this, "OnRButtonUp")
        this._boundMouseActivate := ObjBindMethod(this, "OnMouseActivate")
        OnMessage(0x201, this._boundLButtonDown)  ; WM_LBUTTONDOWN
        OnMessage(0x202, this._boundLButtonUp)    ; WM_LBUTTONUP
        OnMessage(0x200, this._boundMouseMove)    ; WM_MOUSEMOVE
        OnMessage(0x205, this._boundRButtonUp)    ; WM_RBUTTONUP
        OnMessage(0x21, this._boundMouseActivate) ; WM_MOUSEACTIVATE

        this.isVisible := true
        this.currentStatus := "idle"
        this.pulsePhase := 0

        ; Bind render callback (used by timer when animating)
        this.timerFn := ObjBindMethod(this, "DrawFrame")

        ; Initial state is idle — render once, no continuous timer needed
        this.DrawFrame()
    }

    static Hide() {
        if (!this.isVisible)
            return

        ; Save current position before destroying GUI
        if (this.gui && this.posX != 0 && this.posY != 0)
            this.SavePosition()

        if (this.timerFn) {
            SetTimer(this.timerFn, 0)
            this.timerFn := ""
        }

        ; Release capture if active
        if (this._captured) {
            DllCall("ReleaseCapture")
            this._captured := false
        }

        ; Unregister using the same bound references from Show()
        if (this._boundLButtonDown)
            OnMessage(0x201, this._boundLButtonDown, 0)
        if (this._boundLButtonUp)
            OnMessage(0x202, this._boundLButtonUp, 0)
        if (this._boundMouseMove)
            OnMessage(0x200, this._boundMouseMove, 0)
        if (this._boundRButtonUp)
            OnMessage(0x205, this._boundRButtonUp, 0)
        if (this._boundMouseActivate)
            OnMessage(0x21, this._boundMouseActivate, 0)
        this._boundLButtonDown := ""
        this._boundLButtonUp := ""
        this._boundMouseMove := ""
        this._boundRButtonUp := ""
        this._boundMouseActivate := ""

        DarkTooltip.Destroy()

        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }

        this.isVisible := false
    }

    static SetStatus(status) {
        prevStatus := this.currentStatus
        this.currentStatus := status

        if (status = prevStatus)
            return

        if (status = "recording") {
            ; Start animation loop for pulsing glow
            this.pulsePhase := 0
            if (this.timerFn)
                SetTimer(this.timerFn, 33)
        } else {
            ; Static states (idle, processing, error) — stop timer, render once
            if (this.timerFn)
                SetTimer(this.timerFn, 0)
            this.DrawFrame()
        }
    }

    static DrawFrame() {
        if (!this.isVisible || !this.gui)
            return

        w := this.width
        h := this.height

        ; Create per-frame bitmap (same pattern as web-overlay.ahk)
        pBitmap := GDI.CreateBitmap(w, h)
        g := GDI.GraphicsFromImage(pBitmap)
        GDI.Clear(g, 0x00000000)

        ; Background circle
        bgBrush := GDI.CreateSolidBrush(0xE00F0F12)
        GDI.FillEllipse(g, bgBrush, 0, 0, w - 1, h - 1)
        GDI.DeleteBrush(bgBrush)

        ; Rim
        rimPen := GDI.CreatePen(0x30FFFFFF, 1)
        GDI.DrawEllipse(g, rimPen, 1, 1, w - 3, h - 3)
        GDI.DeletePen(rimPen)

        ; Status dot
        dotSize := 12
        dotX := (w - dotSize) / 2
        dotY := (h - dotSize) / 2

        switch this.currentStatus {
            case "idle":
                dotColor := 0xFF34d399  ; green
            case "recording":
                ; Pulsing teal
                this.pulsePhase += 0.1
                alpha := Round(180 + 75 * Sin(this.pulsePhase))
                dotColor := (alpha << 24) | 0x22d3c5
                ; Glow ring
                glowAlpha := Round(40 + 30 * Sin(this.pulsePhase))
                glowBrush := GDI.CreateSolidBrush((glowAlpha << 24) | 0x22d3c5)
                GDI.FillEllipse(g, glowBrush, dotX - 4, dotY - 4, dotSize + 8, dotSize + 8)
                GDI.DeleteBrush(glowBrush)
            case "processing":
                dotColor := 0xFFfbbf24  ; yellow
            case "error":
                dotColor := 0xFFf87171  ; red
            default:
                dotColor := 0xFF34d399
        }

        ; Draw shape per state (accessibility: not color-only)
        if (this.currentStatus = "processing") {
            ; Hollow ring — distinguishable from filled circle for colorblind users
            ringPen := GDI.CreatePen(dotColor, 2.5)
            GDI.DrawEllipse(g, ringPen, dotX + 1, dotY + 1, dotSize - 2, dotSize - 2)
            GDI.DeletePen(ringPen)
        } else if (this.currentStatus = "error") {
            ; X mark — clearly distinct from circles for colorblind users
            xPen := GDI.CreatePen(dotColor, 2.5)
            xPad := 2  ; inset from dot edges
            GDI.DrawLine(g, xPen, dotX + xPad, dotY + xPad, dotX + dotSize - xPad, dotY + dotSize - xPad)
            GDI.DrawLine(g, xPen, dotX + dotSize - xPad, dotY + xPad, dotX + xPad, dotY + dotSize - xPad)
            GDI.DeletePen(xPen)
        } else {
            ; idle / recording — filled circle (recording already has glow ring)
            dotBrush := GDI.CreateSolidBrush(dotColor)
            GDI.FillEllipse(g, dotBrush, dotX, dotY, dotSize, dotSize)
            GDI.DeleteBrush(dotBrush)
        }

        ; Update layered window using GDI helper
        hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        GDI.UpdateLayeredWindow(this.gui.Hwnd, hdc, w, h, pBitmap)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)

        ; Cleanup per-frame resources
        GDI.DeleteGraphics(g)
        GDI.DisposeImage(pBitmap)
    }

    static OnLButtonDown(wParam, lParam, msg, hwnd) {
        if (!this.gui || hwnd != this.gui.Hwnd)
            return

        ; Record mouse position for click vs drag detection
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        this.mouseDownX := mx
        this.mouseDownY := my
        this.isDragging := false
        this.wasClick := true
        this.gui.GetPos(&wx, &wy)
        this.dragStartWinX := wx
        this.dragStartWinY := wy

        ; Capture mouse for manual drag (avoids system modal loop that steals focus)
        this._captured := true
        DllCall("SetCapture", "Ptr", this.gui.Hwnd)
        return 0
    }

    static OnLButtonUp(wParam, lParam, msg, hwnd) {
        if (!this.gui || !this._captured)
            return

        DllCall("ReleaseCapture")
        this._captured := false

        if (this.wasClick) {
            ; Single click — toggle recording (focus stays on previous window)
            global isRecording
            if (isRecording)
                StopAndProcess()
            else
                StartRecording()
        } else if (this.isDragging) {
            ; Drag ended — save position wherever the user placed it
            this.SavePosition()
        }

        this.isDragging := false
        this.wasClick := false
        return 0
    }

    static OnMouseMove(wParam, lParam, msg, hwnd) {
        if (!this.gui)
            return

        ; Handle drag during mouse capture
        if (this._captured) {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            dx := mx - this.mouseDownX
            dy := my - this.mouseDownY

            ; Detect drag threshold
            if (this.wasClick && (Abs(dx) > 5 || Abs(dy) > 5)) {
                this.wasClick := false
                this.isDragging := true
            }

            ; Move window manually (no system modal loop = no focus steal)
            if (this.isDragging) {
                newX := this.dragStartWinX + dx
                newY := this.dragStartWinY + dy
                this.gui.Move(newX, newY)
                this.posX := newX
                this.posY := newY
            }
            return 0
        }

        ; Tooltip on hover (only when not captured, only for our window)
        if (hwnd = this.gui.Hwnd) {
            statusText := "QuickSay"
            switch this.currentStatus {
                case "idle": statusText := "QuickSay — Ready"
                case "recording": statusText := "QuickSay — Recording..."
                case "processing": statusText := "QuickSay — Processing..."
                case "error": statusText := "QuickSay — Error"
            }
            DarkTooltip.Show(statusText, 1250)
        }
    }

    static OnRButtonUp(wParam, lParam, msg, hwnd) {
        if (!this.gui || hwnd != this.gui.Hwnd)
            return

        ; Get current mode name
        global Config
        currentMode := "Standard"
        try {
            if (Config.Has("currentMode")) {
                modeId := Config["currentMode"]
                ; Read config file to find mode name from modes array
                configText := FileRead(this.configFile, "UTF-8")
                cfg := JSON.Parse(configText)
                if (Type(cfg) = "Map" && cfg.Has("modes")) {
                    modes := cfg["modes"]
                    if (HasProp(modes, "Length")) {
                        Loop modes.Length {
                            m := modes[A_Index]
                            if (Type(m) = "Map" && m.Has("id") && m["id"] = modeId) {
                                currentMode := m["name"]
                                break
                            }
                        }
                    }
                }
            }
        }

        widgetMenu := Menu()
        widgetMenu.Add("Mode: " . currentMode, (*) => "")
        widgetMenu.Disable("Mode: " . currentMode)
        widgetMenu.Add()  ; separator
        widgetMenu.Add("Transcribe File...", (*) => TranscribeFile())
        widgetMenu.Add()  ; separator
        widgetMenu.Add("Open Settings", (*) => LaunchSettings())
        widgetMenu.Add("Hide Widget", (*) => this.HideAndUpdateConfig())
        widgetMenu.Add()  ; separator
        widgetMenu.Add("Quit QuickSay", (*) => ExitApp())

        widgetMenu.Show()
        return 0
    }

    static HideAndUpdateConfig() {
        this.Hide()
        ; Update config to disable widget
        try {
            configText := FileRead(this.configFile, "UTF-8")
            cfg := JSON.Parse(configText)
            if (Type(cfg) = "Map") {
                cfg["showWidget"] := false
                jsonStr := JSON.Stringify(cfg, "  ")
                tmpFile := this.configFile . ".tmp"
                try FileDelete(tmpFile)
                FileAppend(jsonStr, tmpFile, "UTF-8")
                FileMove(tmpFile, this.configFile, 1)
            }
        }
    }

    static OnMouseActivate(wParam, lParam, msg, hwnd) {
        if (!this.gui || hwnd != this.gui.Hwnd)
            return
        return 3  ; MA_NOACTIVATE — prevent widget from stealing focus
    }

    static SnapToEdge() {
        if (!this.gui)
            return

        this.gui.GetPos(&wx, &wy)

        ; Find which monitor the widget is currently on
        MonitorGetWorkArea(MonitorGetPrimary(), &monLeft, &_mT, &monRight, &_mB)
        widgetCenterX := wx + this.width / 2
        widgetCenterY := wy + this.height / 2
        try {
            monCount := MonitorGetCount()
            Loop monCount {
                MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (widgetCenterX >= mLeft && widgetCenterX < mRight && widgetCenterY >= mTop && widgetCenterY < mBottom) {
                    monLeft := mLeft
                    monRight := mRight
                    break
                }
            }
        }

        monCenter := monLeft + (monRight - monLeft) / 2
        centerX := wx + this.width / 2

        ; Snap to nearest horizontal edge of the current monitor
        if (centerX < monCenter)
            newX := monLeft + 8  ; Left edge
        else
            newX := monRight - this.width - 8  ; Right edge

        this.posX := newX
        this.posY := wy
        this.gui.Move(this.posX, this.posY)
    }

    static SavePosition() {
        ; Update in-memory Config so re-show uses saved position
        global Config
        try {
            Config["widget_x"] := this.posX
            Config["widget_y"] := this.posY
        }
        ; Write to config file with mutex lock
        hMutex := AcquireConfigLock()
        try {
            configPath := this.configFile
            if !FileExist(configPath)
                return
            content := FileRead(configPath, "UTF-8")
            cfg := JSON.Parse(content)
            if (Type(cfg) != "Map")
                return
            cfg["widgetX"] := this.posX
            cfg["widgetY"] := this.posY
            jsonStr := JSON.Stringify(cfg, "  ")
            tmpFile := configPath . ".tmp"
            try FileDelete(tmpFile)
            FileAppend(jsonStr, tmpFile, "UTF-8")
            FileMove(tmpFile, configPath, 1)
        } finally {
            ReleaseConfigLock(hMutex)
        }
    }
}

; ==============================================================================
;  DarkTooltip — custom dark tooltip to replace native ToolTip()
;  Background #1e1e22, text #f0f0f3, Segoe UI 9pt, non-focus-stealing.
;  On Win11, uses DwmSetWindowAttribute for rounded corners.
; ==============================================================================

class DarkTooltip {
    static _gui := ""
    static _timerFn := ""
    static _text := ""

    static Show(text, duration := 2000) {
        ; If already showing the same text, just reset the auto-hide timer
        if (this._gui && this._text = text) {
            if (this._timerFn)
                SetTimer(this._timerFn, -duration)
            return
        }

        this.Destroy()
        this._text := text

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)

        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
        g.BackColor := "1e1e22"
        g.MarginX := 8
        g.MarginY := 5
        g.SetFont("s9 c0xf0f0f3", "Segoe UI")
        g.AddText(, text)

        ; Show offscreen first to measure, then reposition near cursor
        g.Show("x-9999 y-9999 NoActivate")
        g.GetPos(, , &w, &h)

        ; Position: offset right and above cursor, clamped to screen
        tipX := mx + 16
        tipY := my - h - 8

        ; Clamp to primary work area
        MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
        if (tipX + w > mR)
            tipX := mx - w - 8
        if (tipY < mT)
            tipY := my + 20
        if (tipX < mL)
            tipX := mL + 4

        g.Move(tipX, tipY)

        ; 1px border via WinSetRegion is too complex; use DWM border on Win11
        try {
            ; DWMWA_BORDER_COLOR = 34
            borderColor := 0x003a3a3e  ; BGR for #3e3a3a (subtle gray)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd,
                "Int", 34, "UInt*", &borderColor, "Int", 4)
            ; DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2
            cornerPref := 2
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd,
                "Int", 33, "Int*", &cornerPref, "Int", 4)
        }

        this._gui := g

        ; Auto-hide after duration
        this._timerFn := ObjBindMethod(this, "Destroy")
        SetTimer(this._timerFn, -duration)
    }

    static Destroy() {
        this._text := ""
        if (this._timerFn) {
            SetTimer(this._timerFn, 0)
            this._timerFn := ""
        }
        if (this._gui) {
            this._gui.Destroy()
            this._gui := ""
        }
    }
}

; Export functions
ShowFloatingWidget(config := "") {
    FloatingWidget.Show(config)
}

HideFloatingWidget() {
    FloatingWidget.Hide()
}

UpdateWidgetStatus(status) {
    if FloatingWidget.isVisible
        FloatingWidget.SetStatus(status)
}
