; QuickSay Modern Overlay - Smooth Continuous Wave
; Features:
; - Continuous polyline wave (oscilloscope style)
; - Audio reactive
; - Smaller text, positioned bottom center

#Requires AutoHotkey v2.0

; ==============================================================================
#Include %A_ScriptDir%\lib\GDI.ahk

; ==============================================================================
; AUDIO METER
; ==============================================================================
class AudioMeter {
    static IAudioMeterInformation := "{C02216F6-8C67-4B5B-9D00-D008E73E0064}"
    static meter := 0
    static currentDevice := ""   ; Track which device we initialized for

    static Init(deviceName := "Default") {
        ; For default device, use cache if already initialized
        ; For specific devices, ALWAYS re-initialize — device may have been
        ; disconnected since last init, leaving a stale COM pointer
        if (this.meter && this.currentDevice == deviceName && (deviceName == "Default" || deviceName == ""))
            return true

        ; Release old meter
        if (this.meter) {
            try ObjRelease(this.meter)
            this.meter := 0
        }
        this.currentDevice := deviceName

        try {
            IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

            IMMDevice := 0
            if (deviceName == "Default" || deviceName == "") {
                ; Use system default capture device
                ComCall(4, IMMDeviceEnumerator, "int", 1, "int", 0, "ptr*", &IMMDevice)
            } else {
                ; Enumerate all capture endpoints to find matching device by name
                IMMDevice := this._FindDeviceByName(IMMDeviceEnumerator, deviceName)
            }

            if !IMMDevice
                return false

            ; Get IAudioMeterInformation from the device
            meterIID := Buffer(16)
            DllCall("ole32\CLSIDFromString", "Str", this.IAudioMeterInformation, "Ptr", meterIID)
            ComCall(3, IMMDevice, "ptr", meterIID, "int", 23, "ptr", 0, "ptr*", &meterVal := 0)
            this.meter := meterVal
            ObjRelease(IMMDevice)
            return true
        } catch {
            return false
        }
    }

    static _FindDeviceByName(enumerator, targetName) {
        ; IMMDeviceEnumerator::EnumAudioEndpoints
        ; Method index 3, params: dataFlow=eCapture(1), stateMask=DEVICE_STATE_ACTIVE(1)
        ComCall(3, enumerator, "int", 1, "int", 1, "ptr*", &collection := 0)
        if !collection
            return 0

        ; IMMDeviceCollection::GetCount (method index 3)
        ComCall(3, collection, "uint*", &count := 0)

        ; PKEY_Device_FriendlyName GUID + PID
        PKEY := Buffer(20)
        DllCall("ole32\CLSIDFromString", "Str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", PKEY)
        NumPut("uint", 14, PKEY, 16)  ; PID for FriendlyName

        foundDevice := 0
        Loop count {
            idx := A_Index - 1
            ; IMMDeviceCollection::Item (method index 4)
            ComCall(4, collection, "uint", idx, "ptr*", &device := 0)
            if !device
                continue

            try {
                ; IMMDevice::OpenPropertyStore (method index 4), STGM_READ=0
                ComCall(4, device, "int", 0, "ptr*", &propStore := 0)
                if propStore {
                    ; IPropertyStore::GetValue (method index 5)
                    propVar := Buffer(24, 0)
                    ComCall(5, propStore, "ptr", PKEY, "ptr", propVar)

                    ; PROPVARIANT: vt at offset 0 (should be VT_LPWSTR=31), ptr at offset 8
                    vt := NumGet(propVar, 0, "ushort")
                    if (vt == 31) {  ; VT_LPWSTR
                        pStr := NumGet(propVar, 8, "ptr")
                        friendlyName := StrGet(pStr, "UTF-16")

                        if (InStr(friendlyName, targetName) || InStr(targetName, friendlyName)) {
                            foundDevice := device
                            DllCall("ole32\PropVariantClear", "ptr", propVar)
                            ObjRelease(propStore)
                            break  ; Don't release this device - we're returning it
                        }
                    }
                    DllCall("ole32\PropVariantClear", "ptr", propVar)
                    ObjRelease(propStore)
                }
            }

            ObjRelease(device)
        }

        ObjRelease(collection)
        return foundDevice
    }

    static GetPeak() {
        if !this.meter
            if !this.Init()
                return 0.0
        try {
            ComCall(3, this.meter, "float*", &peak := 0)
            return peak
        } catch {
            return 0.0
        }
    }
}

; ==============================================================================
; OVERLAY CLASS
; ==============================================================================
class RecordingOverlay {
    static gui := ""
    static width := 78
    static height := 26
    static isVisible := false
    static animTimer := 0
    static seconds := 0
    static timerCallback := 0
    static hideCallback := 0
    static currentState := "recording"
    static commandText := ""
    static wavePhase := 0
    static blendFactor := 0.0
    static smoothedPeak := 0.0
    static accessibilityScale := 1.0

    ; Logo #6 EXACT Shape (y offsets from center - Scaled for 22px height)
    static staticCurve := [0, 0, -6.5, -1.2, -0.8, -1.2, -6.5, 0, 0] 
    
    ; Colors — Dark Theme
    static cBgBase := 0xD90F0F12   ; 85% Dark (#0f0f12)
    static cBgGloss := 0x181A1A21  ; Subtle surface tint

    ; Layers
    static cHalo     := 0x1522D3C5 ; Faint teal aura
    static cGlow     := 0x3022D3C5 ; Soft teal glow
    static cRim      := 0x30FFFFFF ; Subtle inner rim

    static cLine := 0xFF22D3C5     ; Teal wave
    static cText := 0xFFF0F0F3     ; White text
    static cTimer := 0xFFF0F0F3    ; White timer

    ; Level bars
    static cBarActive := 0xFF22D3C5   ; Teal
    static cBarInactive := 0xFF3E3E50 ; Quaternary
    static pulsePhase := 0.0
    
    static Init() {
        GDI.Startup()
        if !this.hideCallback
            this.hideCallback := ObjBindMethod(RecordingOverlay, "Hide")
    }
    
    static Show(state := "recording") {
        if !this.gui {
            this.Init()
            this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
            this.gui.Show("NoActivate Hide w" this.width " h" this.height)
        }

        this.currentState := state
        
        ; DYNAMIC SIZING - UNIFIED MARGINS
        ; Base Text Start: x=46
        
        scale := this.accessibilityScale
        if (state = "recording") {
            this.width := Round(106 * scale)
            this.height := Round(26 * scale)
            this.cLine := 0xFF22D3C5 ; Teal
            this.cText := 0xFFF0F0F3
        } else if (state = "command") {
            this.width := Round(100 * scale)
            this.height := Round(26 * scale)
            this.cLine := 0xFF22D3C5 ; Teal
            this.cText := 0xFF22D3C5 ; Teal
        } else if (state = "processing") {
            this.width := Round(102 * scale)
            this.height := Round(26 * scale)
            this.cLine := 0xFF22D3C5 ; Teal
            this.cText := 0xFFF0F0F3
        } else if (state = "success") {
            this.width := Round(90 * scale)
            this.height := Round(26 * scale)
        } else if (state = "error") {
            this.width := Round(75 * scale)
            this.height := Round(26 * scale)
        }
            
        ; Position bottom center of the active window's monitor (above taskbar)
        MonitorGetWorkArea(MonitorGetPrimary(), &monLeft, &monTop, &monRight, &monBottom)
        try {
            ; Get active window position to determine which monitor it's on
            activeHwnd := WinExist("A")
            if (activeHwnd) {
                WinGetPos(&winX, &winY, &winW, &winH, activeHwnd)
                winCenterX := winX + (winW // 2)
                winCenterY := winY + (winH // 2)

                ; Find which monitor contains the center of the active window
                monCount := MonitorGetCount()
                Loop monCount {
                    MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                    if (winCenterX >= mLeft && winCenterX < mRight && winCenterY >= mTop && winCenterY < mBottom) {
                        monLeft := mLeft
                        monTop := mTop
                        monRight := mRight
                        monBottom := mBottom
                        break
                    }
                }
            }
        }
        posX := monLeft + ((monRight - monLeft) - this.width) // 2
        posY := monBottom - this.height - 25

        ; Move and Resize
        this.gui.Move(posX, posY, this.width, this.height)
        this.gui.Show("NoActivate")
        this.isVisible := true
        
        ; If we are recording, ensure hide timer is KILLED
        if (state = "recording") {
            SetTimer(this.hideCallback, 0) ; OFF
            this.seconds := 0
            ; Pass device name so AudioMeter connects to the correct WASAPI endpoint
            ; (enumerates capture devices and matches by friendly name)
            global Config
            deviceName := (Config.Has("audioDevice")) ? Config["audioDevice"] : "Default"
            if !AudioMeter.Init(deviceName)
                AudioMeter.Init("Default")  ; Fallback if device disconnected
            if !this.timerCallback {
                this.timerCallback := ObjBindMethod(this, "UpdateTimer")
                SetTimer(this.timerCallback, 1000)
            }
            this.blendFactor := 0.0
        }
        
        if !this.animTimer {
            this.animTimer := ObjBindMethod(this, "DrawFrame")
            SetTimer(this.animTimer, 16) ; 60 FPS
        }
        
        ; Process Auto-Hide for end states
        if (state = "command") {
            SetTimer(this.hideCallback, -800) ; 0.8s for command feedback
        } else if (state = "success" || state = "error") {
            SetTimer(this.hideCallback, -1000) ; 1.0s
        }
    }
    
    static UpdateTimer() {
        if (!this.isVisible)
            return
        this.seconds++
    }
    
    static DrawFrame() {
        if (!this.isVisible || !this.gui)
            return

        pBitmap := 0
        g := 0

        try {
            pBitmap := GDI.CreateBitmap(this.width, this.height)
            g := GDI.GraphicsFromImage(pBitmap)
            GDI.Clear(g, 0x00000000)

            ; --- MODERN FROSTED BUBBLE ---

            ; 1. Wide Halo (Vibe)
            pPenHalo := GDI.CreatePen(this.cHalo, 6)
            GDI.DrawRoundedRectangle(g, pPenHalo, 3, 3, this.width-6, this.height-6, this.height/2-3)
            GDI.DeletePen(pPenHalo)

            ; 2. Soft Glow
            pPenGlow := GDI.CreatePen(this.cGlow, 3)
            GDI.DrawRoundedRectangle(g, pPenGlow, 2, 2, this.width-4, this.height-4, this.height/2-2)
            GDI.DeletePen(pPenGlow)

            ; 3. Base White Fill (Frosted)
            pBrushBase := GDI.CreateSolidBrush(this.cBgBase)
            GDI.FillRoundedRectangle(g, pBrushBase, 2, 2, this.width-4, this.height-4, this.height/2-2)
            GDI.DeleteBrush(pBrushBase)

            ; 4. Top Gloss
            pBrushGloss := GDI.CreateSolidBrush(this.cBgGloss)
            GDI.FillRoundedRectangle(g, pBrushGloss, 4, 3, this.width-8, (this.height-4)/2, this.height/4)
            GDI.DeleteBrush(pBrushGloss)

            ; 5. Sharp Inner Rim
            pPenRim := GDI.CreatePen(this.cRim, 1)
            GDI.DrawRoundedRectangle(g, pPenRim, 3, 3, this.width-6, this.height-6, this.height/2-3)
            GDI.DeletePen(pPenRim)

            ; Logic
            targetBlend := (this.currentState = "recording" || this.currentState = "processing") ? 1.0 : 0.0
            blendSpeed := 0.04
            if (this.blendFactor < targetBlend)
                this.blendFactor := Min(1.0, this.blendFactor + blendSpeed)
            else if (this.blendFactor > targetBlend)
                this.blendFactor := Max(0.0, this.blendFactor - blendSpeed)

            ; Audio Level
            targetPeak := 0.0
            if (this.currentState = "recording") {
                raw := AudioMeter.GetPeak()
                if (raw > this.smoothedPeak)
                    this.smoothedPeak := raw
                else
                    this.smoothedPeak := Max(0, this.smoothedPeak - 0.03)
                targetPeak := this.smoothedPeak
            } else if (this.currentState = "processing")
                targetPeak := 0.3

            ; Phase
            this.wavePhase += (0.035 + (targetPeak * 0.05))

            ; --- PULSING CIRCLES (recording state) ---
            if (this.currentState = "recording") {
                this.pulsePhase += 0.04
                micCX := 16
                micCY := this.height / 2

                ; 3 concentric pulsing circles (teal, fading outward)
                Loop 3 {
                    idx := A_Index
                    phase := this.pulsePhase + (idx - 1) * 2.094  ; offset by 2π/3
                    radius := 4 + idx * 2 + Sin(phase) * 1
                    alpha := Max(0, 0x30 - idx * 0x0C)
                    circleColor := (alpha << 24) | 0x22D3C5
                    pPenCircle := GDI.CreatePen(circleColor, 1)
                    GDI.DrawEllipse(g, pPenCircle, micCX - radius, micCY - radius, radius * 2, radius * 2)
                    GDI.DeletePen(pPenCircle)
                }

                ; Mic icon (simple circle dot)
                pBrushMic := GDI.CreateSolidBrush(0xFFF0F0F3)
                GDI.FillEllipse(g, pBrushMic, micCX - 3, micCY - 3, 6, 6)
                GDI.DeleteBrush(pBrushMic)
            }

            ; --- DRAW CONTINUOUS WAVE ---
            pPen := GDI.CreatePen(this.cLine, 1.6)
            GDI.SetPenCap(pPen, 2, 2)

            centerY := this.height / 2
            waveOffsetY := 0

            ; Draw Wave
            startX := (this.currentState = "recording") ? 30 : 9
            waveWidth := (this.currentState = "recording") ? 44 : 30
            numPoints := 60
            step := waveWidth / (numPoints - 1)

            prevX := startX
            prevY := centerY + waveOffsetY

            Loop numPoints {
                i := A_Index
                progress := (i-1) / (numPoints-1)

                ; Static shape
                curveIdx := 1 + (progress * (this.staticCurve.Length - 1))
                idx1 := Floor(curveIdx)
                idx2 := Min(this.staticCurve.Length, Ceil(curveIdx))
                mix := curveIdx - idx1
                staticY := this.staticCurve[idx1] * (1-mix) + this.staticCurve[idx2] * mix

                ; Animated wave
                waveY := 0
                if (this.currentState = "recording") {
                    boost := (targetPeak > 0.01) ? (targetPeak ** 0.4) * 5 : 0
                    taper := Sin(progress * 3.14159)

                    ; TRAVELING WAVES (Flowing Right)
                    x := i * 0.4
                    w1 := Sin(x - this.wavePhase * 2.0)
                    w2 := Sin(x * 0.6 - this.wavePhase * 1.5)
                    waveY := w1 * (w2 + 0.5) * boost * taper

                } else if (this.currentState = "processing") {
                    taper := Sin(progress * 3.14159)
                    waveY := Sin(i * 0.3 - this.wavePhase * 3) * 6 * taper
                }

                ; Blend
                currentYOffset := staticY + ((waveY - staticY) * this.blendFactor)

                currX := startX + (i-1)*step
                currY := centerY + waveOffsetY + currentYOffset

                if (i > 1)
                    GDI.DrawLine(g, pPen, prevX, prevY, currX, currY)

                prevX := currX
                prevY := currY
            }
            GDI.DeletePen(pPen)

            ; --- TEXT DRAWING (Unified Layout) ---
            if (this.currentState = "recording") {
                hours := this.seconds // 3600, mins := Mod(this.seconds, 3600) // 60, secs := Mod(this.seconds, 60)
                str := (hours > 0) ? hours ":" Format("{:02}", mins) ":" Format("{:02}", secs) : mins ":" Format("{:02}", secs)
            } else if (this.currentState = "command" && this.commandText != "")
                str := this.commandText
            else
                str := this.currentState

            textX := (this.currentState = "recording") ? 76 : 46
            textY := 7
            this.DrawText(g, str, textX, textY, (this.currentState = "recording"))

            ; Commit
            hdc := DllCall("GetDC", "Ptr", 0)
            GDI.UpdateLayeredWindow(this.gui.Hwnd, hdc, this.width, this.height, pBitmap)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
        } catch {
        }

        ; Always clean up GDI resources even if an error occurred
        if (g)
            GDI.DeleteGraphics(g)
        if (pBitmap)
            GDI.DisposeImage(pBitmap)
    }
    
    static DrawText(g, text, x, y, isTimer := false) {
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &hFamily := 0)
        if !hFamily 
             DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Arial", "Ptr", 0, "Ptr*", &hFamily := 0)
        
        ; Font Size 9 (Larger), Style 0 (Regular)
        DllCall("gdiplus\GdipCreateFont", "Ptr", hFamily, "Float", 9, "Int", 0, "Int", 0, "Ptr*", &hFont := 0)
        
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", isTimer ? this.cTimer : this.cText, "Ptr*", &pBrush := 0)
        
        rect := Buffer(16, 0)
        NumPut("Float", x, rect, 0), NumPut("Float", y, rect, 4)
        NumPut("Float", 80, rect, 8), NumPut("Float", 20, rect, 12)
        
        DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", text, "Int", -1, "Ptr", hFont, "Ptr", rect, "Ptr", 0, "Ptr", pBrush)
        
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        DllCall("gdiplus\GdipDeleteFont", "Ptr", hFont)
        DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", hFamily)
    }
    
    static Update(state, text := "") {
        this.currentState := state
        this.commandText := text
        ; Show handles both initial display and resize
        this.Show(state)
    }
    
    static Hide() {
        this.isVisible := false
        if (this.animTimer)
             SetTimer(this.animTimer, 0), this.animTimer := 0
        if (this.timerCallback)
             SetTimer(this.timerCallback, 0), this.timerCallback := 0
        if (this.hideCallback)
             SetTimer(this.hideCallback, 0)
        ; Destroy GUI fully — prevents stale HWND after display changes
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
    }
}

; === EXPORT FUNCTIONS ===
ShowRecordingOverlay(state := "recording") {
    RecordingOverlay.Show(state)
}

UpdateRecordingOverlay(state, text := "") {
    RecordingOverlay.Update(state, text)
}

HideRecordingOverlay() {
    RecordingOverlay.Hide()
}
