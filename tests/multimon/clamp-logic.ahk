; T1.7 multimon clamping unit tests — runs headless, no running QuickSay needed.
; Tests the RepositionToVisible logic with synthetic monitor coordinate sets.
; Usage: AutoHotkey64.exe /ErrorStdOut clamp-logic.ahk
; Exit 0 = all pass, Exit 1 = failures.

#Requires AutoHotkey v2.0

; ─── Pure-function mirror of FloatingWidget.RepositionToVisible ───────────────
; Inputs:  posX, posY — current widget top-left
;          w, h       — widget dimensions
;          monitors   — Array of {L, T, R, B} work-area objects
;          primaryIdx — 1-based index of primary monitor
; Returns: Map with keys "x", "y", "moved" (true if position changed)
ClampWidget(posX, posY, w, h, monitors, primaryIdx := 1) {
    ; Check if the full rect fits on any monitor
    onScreen := false
    Loop monitors.Length {
        m := monitors[A_Index]
        if (posX >= m.L && posX + w <= m.R && posY >= m.T && posY + h <= m.B) {
            onScreen := true
            break
        }
    }
    if (onScreen)
        return Map("x", posX, "y", posY, "moved", false)

    ; Stranded — snap to primary monitor bottom-right corner with 12px margin
    pm := monitors[primaryIdx]
    newX := pm.R - w - 12
    newY := pm.B - h - 12
    return Map("x", newX, "y", newY, "moved", true)
}

; ─── Test infrastructure ──────────────────────────────────────────────────────
global gPass := 0, gFail := 0

Assert(name, cond) {
    global gPass, gFail
    if (cond) {
        FileAppend("  PASS  " name "`n", "*")
        gPass++
    } else {
        FileAppend("  FAIL  " name "`n", "*")
        gFail++
    }
}

; Synthetic helper: one monitor work area object
Mon(l, t, r, b) => {L: l, T: t, R: r, B: b}

; Widget dimensions match FloatingWidget.width/height
W := 44, H := 44

; ─── Test 1: Widget at (3000, 500) on single 1920×1080 monitor ───────────────
FileAppend("Test 1: off-screen widget snapped to primary`n", "*")
monitors := [Mon(0, 0, 1920, 1040)]   ; typical work area (taskbar removed ~40px)
r := ClampWidget(3000, 500, W, H, monitors, 1)
Assert("T1: moved=true",       r["moved"])
Assert("T1: x inside [0,1920)", r["x"] >= 0 && r["x"] + W <= 1920)
Assert("T1: y inside [0,1040)", r["y"] >= 0 && r["y"] + H <= 1040)

; ─── Test 2: Widget at (100, 100) already valid — NOT moved ──────────────────
FileAppend("Test 2: valid position is not moved`n", "*")
r2 := ClampWidget(100, 100, W, H, monitors, 1)
Assert("T2: moved=false", !r2["moved"])
Assert("T2: x unchanged",  r2["x"] = 100)
Assert("T2: y unchanged",  r2["y"] = 100)

; ─── Test 3: Widget partially off bottom edge ─────────────────────────────────
FileAppend("Test 3: partial clip (bottom edge) → snapped`n", "*")
; posY + H = 1040 + 10 = 1050 > 1040 (work-area bottom) → off screen
r3 := ClampWidget(100, 1010, W, H, monitors, 1)
Assert("T3: moved=true",        r3["moved"])
Assert("T3: fully fits y-axis", r3["y"] + H <= 1040)

; ─── Test 4: Dual-monitor — widget on second monitor stays on second monitor ──
FileAppend("Test 4: widget on valid second monitor — not moved`n", "*")
monitors2 := [Mon(0, 0, 1920, 1040), Mon(1920, 0, 3840, 1040)]
r4 := ClampWidget(2000, 200, W, H, monitors2, 1)
Assert("T4: moved=false",     !r4["moved"])
Assert("T4: x on monitor 2",  r4["x"] = 2000)

; ─── Test 5: Widget on now-removed second monitor (only primary remains) ──────
FileAppend("Test 5: widget on removed second monitor → snapped to primary`n", "*")
monitors1 := [Mon(0, 0, 1920, 1040)]   ; second monitor unplugged
r5 := ClampWidget(2400, 300, W, H, monitors1, 1)
Assert("T5: moved=true",            r5["moved"])
Assert("T5: x on primary [0,1920)", r5["x"] >= 0 && r5["x"] + W <= 1920)
Assert("T5: y on primary [0,1040)", r5["y"] >= 0 && r5["y"] + H <= 1040)

; ─── Summary ──────────────────────────────────────────────────────────────────
FileAppend("`n" gPass " passed, " gFail " failed`n", "*")
ExitApp(gFail > 0 ? 1 : 0)
