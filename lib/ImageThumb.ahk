; Session-only clipboard image thumbnails via GDI+
; Prefer CF_DIB over CF_BITMAP to avoid stride/corruption artifacts (vertical seams).
; Official docs: https://www.autohotkey.com/docs/v2/

ThumbDir := A_Temp "\ClipboardManager"
ThumbMaxEdge := 320
MaxPreviewWidth := 320
MaxPreviewHeight := 200
GdipToken := 0
ThumbCounter := 0

EnsureThumbDir() {
    global ThumbDir
    if !DirExist(ThumbDir)
        DirCreate(ThumbDir)
}

GdipEnsureStarted() {
    global GdipToken
    if GdipToken
        return true
    if !DllCall("GetModuleHandle", "str", "gdiplus", "ptr")
        DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(24, 0)
    NumPut("uint", 1, si, 0)  ; GdiplusVersion = 1
    if DllCall("gdiplus\GdiplusStartup", "ptr*", &token := 0, "ptr", si, "ptr", 0)
        return false
    GdipToken := token
    return true
}

GdipShutdown() {
    global GdipToken
    if GdipToken {
        DllCall("gdiplus\GdiplusShutdown", "ptr", GdipToken)
        GdipToken := 0
    }
}

; Read width/height of an image file (PNG thumb). Returns false on failure.
GetImageFileSize(path, &width, &height) {
    width := 0
    height := 0
    if (path = "" || !FileExist(path))
        return false
    if !GdipEnsureStarted()
        return false
    pBitmap := 0
    if DllCall("gdiplus\GdipLoadImageFromFile", "wstr", path, "ptr*", &pBitmap) || !pBitmap
        return false
    DllCall("gdiplus\GdipGetImageWidth", "ptr", pBitmap, "uint*", &width)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pBitmap, "uint*", &height)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    return (width > 0 && height > 0)
}

; Fit src size into max box, keep aspect ratio. Never upscale above source.
FitImageSize(srcW, srcH, maxW, maxH, &outW, &outH) {
    if (srcW < 1 || srcH < 1) {
        outW := maxW
        outH := maxH
        return
    }
    scale := Min(maxW / srcW, maxH / srcH, 1.0)
    outW := Max(1, Integer(Round(srcW * scale)))
    outH := Max(1, Integer(Round(srcH * scale)))
}

; BITMAPINFOHEADER / CF_DIB helpers
DibBitsOffset(pInfo) {
    biSize := NumGet(pInfo, 0, "uint")
    biBitCount := NumGet(pInfo, 14, "ushort")
    biCompression := NumGet(pInfo, 16, "uint")
    biClrUsed := NumGet(pInfo, 32, "uint")
    offset := biSize
    ; BI_BITFIELDS = 3; masks follow BITMAPINFOHEADER when biSize == 40
    if (biCompression = 3 && biSize = 40)
        offset += 12
    if (biBitCount <= 8) {
        nColors := biClrUsed ? biClrUsed : (1 << biBitCount)
        offset += nColors * 4
    }
    return offset
}

; Read width/height while image is still on the clipboard (prefer CF_DIB).
GetClipboardBitmapSize(&width, &height) {
    width := 0
    height := 0
    if !DllCall("OpenClipboard", "ptr", 0)
        return false
    ok := false
    ; CF_DIB = 8
    if (hMem := DllCall("GetClipboardData", "uint", 8, "ptr")) {
        if (pInfo := DllCall("GlobalLock", "ptr", hMem, "ptr")) {
            width := Abs(NumGet(pInfo, 4, "int"))
            height := Abs(NumGet(pInfo, 8, "int"))
            ok := (width > 0 && height > 0)
            DllCall("GlobalUnlock", "ptr", hMem)
        }
    } else if DllCall("IsClipboardFormatAvailable", "uint", 2) {
        hBM := DllCall("GetClipboardData", "uint", 2, "ptr")
        if hBM {
            bm := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
            if DllCall("GetObject", "ptr", hBM, "int", bm.Size, "ptr", bm) {
                width := NumGet(bm, 4, "int")
                height := NumGet(bm, 8, "int")
                ok := (width > 0 && height > 0)
            }
        }
    }
    DllCall("CloseClipboard")
    return ok
}

BuildImagePreviewLabel(width := 0, height := 0) {
    stamp := FormatTime(, "HH:mm:ss")
    if (width > 0 && height > 0)
        return "Image " stamp " - " width "x" height
    return "Image " stamp
}

GetPngEncoderClsid(&clsid) {
    clsid := Buffer(16, 0)
    return DllCall("ole32\CLSIDFromString",
        "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}",
        "ptr", clsid) = 0
}

; Create GDI+ bitmap from clipboard CF_DIB (avoids CF_BITMAP seam artifacts).
CreateGdipBitmapFromClipboardDib() {
    if !DllCall("OpenClipboard", "ptr", 0)
        return 0
    pBitmap := 0
    hMem := DllCall("GetClipboardData", "uint", 8, "ptr")  ; CF_DIB
    if hMem {
        pInfo := DllCall("GlobalLock", "ptr", hMem, "ptr")
        if pInfo {
            bits := pInfo + DibBitsOffset(pInfo)
            DllCall("gdiplus\GdipCreateBitmapFromGdiDib", "ptr", pInfo, "ptr", bits, "ptr*", &pBitmap)
            DllCall("GlobalUnlock", "ptr", hMem)
        }
    }
    DllCall("CloseClipboard")
    return pBitmap
}

; Fallback: CF_BITMAP via GetDIBits into a 32bpp top-down DIB section, then GDI+.
CreateGdipBitmapFromClipboardBitmap() {
    if !DllCall("OpenClipboard", "ptr", 0)
        return 0
    hClip := DllCall("GetClipboardData", "uint", 2, "ptr")
    if !hClip {
        DllCall("CloseClipboard")
        return 0
    }

    bm := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
    if !DllCall("GetObject", "ptr", hClip, "int", bm.Size, "ptr", bm) {
        DllCall("CloseClipboard")
        return 0
    }
    width := NumGet(bm, 4, "int")
    height := NumGet(bm, 8, "int")
    if (width < 1 || height < 1) {
        DllCall("CloseClipboard")
        return 0
    }

    ; BITMAPINFO for 32bpp BI_RGB top-down
    bmi := Buffer(44, 0)
    NumPut("uint", 40, bmi, 0)          ; biSize
    NumPut("int", width, bmi, 4)
    NumPut("int", -height, bmi, 8)      ; top-down
    NumPut("ushort", 1, bmi, 12)        ; planes
    NumPut("ushort", 32, bmi, 14)       ; bit count
    NumPut("uint", 0, bmi, 16)          ; BI_RGB

    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    hDib := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bmi, "uint", 0,
        "ptr*", &pBits := 0, "ptr", 0, "uint", 0, "ptr")
    if hDib && pBits {
        DllCall("GetDIBits", "ptr", hdc, "ptr", hClip, "uint", 0, "uint", height,
            "ptr", pBits, "ptr", bmi, "uint", 0)
    }
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    DllCall("CloseClipboard")

    if !hDib
        return 0

    pBitmap := 0
    ; Use positive height in header for GdipCreateBitmapFromGdiDib
    NumPut("int", height, bmi, 8)
    DllCall("gdiplus\GdipCreateBitmapFromGdiDib", "ptr", bmi, "ptr", pBits, "ptr*", &pBitmap)
    DllCall("DeleteObject", "ptr", hDib)
    return pBitmap
}

; Save a scaled PNG thumbnail of the current clipboard image. Returns path or "".
SaveClipboardThumbnail() {
    global ThumbDir, ThumbMaxEdge, ThumbCounter
    if !GdipEnsureStarted()
        return ""
    EnsureThumbDir()

    pBitmap := 0
    if DllCall("IsClipboardFormatAvailable", "uint", 8)
        pBitmap := CreateGdipBitmapFromClipboardDib()
    if !pBitmap && DllCall("IsClipboardFormatAvailable", "uint", 2)
        pBitmap := CreateGdipBitmapFromClipboardBitmap()
    if !pBitmap
        return ""

    DllCall("gdiplus\GdipGetImageWidth", "ptr", pBitmap, "uint*", &srcW := 0)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pBitmap, "uint*", &srcH := 0)
    if (srcW < 1 || srcH < 1) {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return ""
    }

    scale := Min(ThumbMaxEdge / srcW, ThumbMaxEdge / srcH, 1.0)
    dstW := Max(1, Integer(Round(srcW * scale)))
    dstH := Max(1, Integer(Round(srcH * scale)))

    pThumb := 0
    if DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", dstW, "int", dstH, "int", 0,
        "int", 0x26200A, "ptr", 0, "ptr*", &pThumb) || !pThumb {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return ""
    }

    graphics := 0
    if DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pThumb, "ptr*", &graphics) || !graphics {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pThumb)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return ""
    }
    DllCall("gdiplus\GdipSetInterpolationMode", "ptr", graphics, "int", 7)
    DllCall("gdiplus\GdipDrawImageRectI", "ptr", graphics, "ptr", pBitmap,
        "int", 0, "int", 0, "int", dstW, "int", dstH)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", graphics)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

    if !GetPngEncoderClsid(&clsid) {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pThumb)
        return ""
    }

    ThumbCounter += 1
    path := ThumbDir "\thumb_" A_TickCount "_" ThumbCounter ".png"
    status := DllCall("gdiplus\GdipSaveImageToFile", "ptr", pThumb, "wstr", path, "ptr", clsid, "ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pThumb)
    if status || !FileExist(path)
        return ""
    return path
}

DeleteThumbFile(path) {
    if (path = "" || !FileExist(path))
        return
    try FileDelete(path)
}

DeleteThumbForItem(item) {
    if !IsObject(item)
        return
    if item.Has("thumbPath")
        DeleteThumbFile(item["thumbPath"])
}

CleanupAllThumbFiles() {
    global ClipHistory, ThumbDir
    for item in ClipHistory
        DeleteThumbForItem(item)
    if DirExist(ThumbDir) {
        try {
            Loop Files ThumbDir "\thumb_*.png", "F"
                FileDelete(A_LoopFileFullPath)
        } catch {
        }
    }
    GdipShutdown()
}
