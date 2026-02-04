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
    static width := 78  ; Tighter Width
    static height := 22 ; Narrower Height
    static isVisible := false
    static animTimer := 0
    static seconds := 0
    static timerCallback := 0
    static hideCallback := 0
    static currentState := "recording"
    static wavePhase := 0
    static blendFactor := 0.0
    static smoothedPeak := 0.0
    
    ; Logo #6 EXACT Shape (y offsets from center - Scaled for 22px height)
    static staticCurve := [0, 0, -6.5, -1.2, -0.8, -1.2, -6.5, 0, 0] 
    
    ; Colors
    ; FROSTED GLASS (Readable on Dark & Light)
    static cBgBase := 0xC5FFFFFF   ; 77% White (Frosted/Milky Glass)
    static cBgGloss := 0x50FFFFFF  ; Stronger Glare
    
    ; Layers
    static cHalo     := 0x15FF6B35 ; Wide Faint Aura/Vibe
    static cGlow     := 0x50FF6B35 ; Soft Orange Glow
    static cRim      := 0xA0FFFFFF ; Sharp Inner White Rim
    
    static cLine := 0xFFFF6B35     
    static cText := 0xFFCC4400     ; Vibrant Burnt Orange (High visibility on White)
    static cTimer := 0xFFCC4400    ; Match Text
    
    static Init() {
        GDI.Startup()
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
        
        if (state = "recording") {
            this.width := 75   ; "0:00"
            this.cLine := 0xFFFF6B35 ; Orange
            this.cText := 0xFFCC4400
        } else if (state = "command") {
            this.width := 90   ; "Command"
            this.cLine := 0xFF8A2BE2 ; Purple
            this.cText := 0xFF4B0082 ; Indigo
        } else if (state = "processing") {
            this.width := 102  ; "Processing"
            this.cLine := 0xFFFF6B35 ; Orange
            this.cText := 0xFFCC4400
        } else if (state = "success")
            this.width := 90   ; "Success" ~40px. 46+40 = 86. Width 90 fits nicely.
        else if (state = "error")
            this.width := 75   
            
        ; Position bottom center (above taskbar)
        posX := (A_ScreenWidth - this.width) // 2
        posY := A_ScreenHeight - this.height - 65
        
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
        if (state = "success" || state = "error") {
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

            ; --- DRAW CONTINUOUS WAVE ---
            pPen := GDI.CreatePen(this.cLine, 1.6)
            GDI.SetPenCap(pPen, 2, 2)

            centerY := this.height / 2

            ; Draw Wave (Positioned Left - Shifted Right for Balance)
            startX := 9
            waveWidth := 30
            numPoints := 60
            step := waveWidth / (numPoints - 1)

            prevX := startX
            prevY := centerY

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
                    boost := (targetPeak > 0.01) ? (targetPeak ** 0.4) * 11 : 0
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
                currY := centerY + currentYOffset

                if (i > 1)
                    GDI.DrawLine(g, pPen, prevX, prevY, currX, currY)

                prevX := currX
                prevY := currY
            }
            GDI.DeletePen(pPen)

            ; --- TEXT DRAWING (Unified Layout) ---
            str := (this.currentState = "recording") ? (this.seconds // 60) ":" Format("{:02}", Mod(this.seconds, 60)) : this.currentState

            this.DrawText(g, str, 46, 5, (this.currentState = "recording"))

            ; Commit
            hdc := DllCall("GetDC", "Ptr", 0)
            GDI.UpdateLayeredWindow(this.gui.Hwnd, hdc, this.width, this.height, pBitmap)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
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
        NumPut("Float", 120, rect, 8), NumPut("Float", 20, rect, 12)
        
        DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", text, "Int", -1, "Ptr", hFont, "Ptr", rect, "Ptr", 0, "Ptr", pBrush)
        
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        DllCall("gdiplus\GdipDeleteFont", "Ptr", hFont)
        DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", hFamily)
    }
    
    static Update(state) {
        this.currentState := state
        if (!this.isVisible)
            this.Show(state)
        ; Re-trigger show logic to handle resize
        this.Show(state)
    }
    
    static Hide() {
        this.isVisible := false
        if (this.gui)
            this.gui.Hide()
        if (this.animTimer)
             SetTimer(this.animTimer, 0), this.animTimer := 0
        if (this.timerCallback)
             SetTimer(this.timerCallback, 0), this.timerCallback := 0
        if (this.hideCallback)
             SetTimer(this.hideCallback, 0)
    }
}

; === EXPORT FUNCTIONS ===
ShowRecordingOverlay(state := "recording") {
    RecordingOverlay.Show(state)
}

UpdateRecordingOverlay(state) {
    RecordingOverlay.Update(state)
}

HideRecordingOverlay() {
    RecordingOverlay.Hide()
}
