#Requires AutoHotkey v2.0

; ==============================================================================
; MINIMAL GDI+ WRAPPER 
; ==============================================================================
class GDI {
    static hLib := 0
    static token := 0
    
    static Startup() {
        if this.hLib
            return
        this.hLib := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        if !this.hLib
            throw Error("Could not load gdiplus.dll")
            
        si := Buffer(24, 0)
        NumPut("UInt", 1, si)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token := 0, "Ptr", si, "Ptr", 0)
        this.token := token
    }
    
    static Shutdown() {
        if this.token {
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.token)
            this.token := 0
        }
        if this.hLib {
            DllCall("FreeLibrary", "Ptr", this.hLib)
            this.hLib := 0
        }
    }
    
    ; Resources
    static CreateBitmap(w, h) {
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap := 0)
        return pBitmap
    }
    static GraphicsFromImage(pBitmap) {
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &g := 0)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4) ; AntiAlias
        return g
    }
    static CreateSolidBrush(argb) {
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &pBrush := 0)
        return pBrush
    }
    static CreatePen(argb, width) {
        DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", width, "Int", 2, "Ptr*", &pPen := 0)
        return pPen
    }
    static SetPenCap(pPen, startCap, endCap) {
        DllCall("gdiplus\GdipSetPenMode", "Ptr", pPen, "Int", 2) ; Round line alignment
        DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pPen, "Int", startCap)
        DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pPen, "Int", endCap)
    }
    
    ; Drawing
    static Clear(g, argb) {
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", argb)
    }
    static DrawLine(g, pPen, x1, y1, x2, y2) {
        DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pPen, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
    }
    static FillRoundedRectangle(g, pBrush, x, y, w, h, r) {
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
        d := r * 2
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y+h-d, "Float", d, "Float", d, "Float", 0, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y+h-d, "Float", d, "Float", d, "Float", 90, "Float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", pBrush, "Ptr", path)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }
    
    static DrawRoundedRectangle(g, pPen, x, y, w, h, r) {
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
        d := r * 2
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y+h-d, "Float", d, "Float", d, "Float", 0, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y+h-d, "Float", d, "Float", d, "Float", 90, "Float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pPen, "Ptr", path)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }
    
    static DeleteBrush(pBrush) => DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
    static DeletePen(pPen) => DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
    static DeleteGraphics(g) => DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    static DisposeImage(img) => DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    
    static UpdateLayeredWindow(hwnd, hdc, w, h, pBitmap) {
        hbm := 0
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hbm, "Int", 0)
        hdcSrc := DllCall("CreateCompatibleDC", "Ptr", hdc)
        obm := DllCall("SelectObject", "Ptr", hdcSrc, "Ptr", hbm)
        
        ; pt argument (pptDst) determines position. Passing 0 (NULL) uses current window position.
        size := Buffer(8, 0)
        NumPut("Int", w, size, 0), NumPut("Int", h, size, 4)
        
        ptSrc := Buffer(8, 0)
        blend := Buffer(4, 0)
        
        ; Alpha: 255 = Full Window Opacity (We use per-pixel alpha in drawing now)
        NumPut("UChar", 255, blend, 2), NumPut("UChar", 1, blend, 3)
        
        DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", hdc, "Ptr", 0, "Ptr", size, "Ptr", hdcSrc, "Ptr", ptSrc, "Int", 0, "Ptr", blend, "Int", 2)
        
        DllCall("SelectObject", "Ptr", hdcSrc, "Ptr", obm)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcSrc)
    }
    
    static SetAcrylicAccent(hwnd, state := 1, color := 0x01000000) {
        static hUser := DllCall("LoadLibrary", "Str", "user32.dll", "Ptr")
        static setFunc := DllCall("GetProcAddress", "Ptr", hUser, "AStr", "SetWindowCompositionAttribute", "Ptr")
        
        if (setFunc) {
            accent := Buffer(16, 0)
            NumPut("UInt", 3, accent, 0)
            NumPut("UInt", 1, accent, 4)
            NumPut("UInt", color, accent, 8)
            NumPut("UInt", 0, accent, 12)
            
            data := Buffer(16)
            NumPut("UInt", 19, data, 0)
            NumPut("Ptr", accent.Ptr, data, 8)
            NumPut("UInt", 16, data, 12)
            
            DllCall(setFunc, "Ptr", hwnd, "Ptr", data)
        }
    }
}
