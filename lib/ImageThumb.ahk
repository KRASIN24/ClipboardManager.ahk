; Clipboard image thumbnails + durable media via GDI+
; Prefer CF_DIB over CF_BITMAP to avoid stride/corruption artifacts (vertical seams).
; Official docs: https://www.autohotkey.com/docs/v2/

MediaDir := A_ScriptDir "\media"
ThumbDir := A_Temp "\ClipboardManager"  ; legacy temp; cleaned on exit only
ThumbMaxEdge := 320
MaxPreviewWidth := 320
MaxPreviewHeight := 200
GdipToken := 0
ThumbCounter := 0

EnsureMediaDir() {
    global MediaDir
    if !DirExist(MediaDir)
        DirCreate(MediaDir)
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

; Turn stored relative (media\...) or absolute path into an absolute path.
ResolveMediaPath(stored) {
    if (stored = "")
        return ""
    if (SubStr(stored, 2, 1) = ":" || SubStr(stored, 1, 2) = "\\")
        return stored
    return A_ScriptDir "\" stored
}

; Store paths relative to the script dir when under A_ScriptDir.
ToRelativeMediaPath(absPath) {
    if (absPath = "")
        return ""
    prefix := A_ScriptDir "\"
    if (InStr(absPath, prefix) = 1)
        return SubStr(absPath, StrLen(prefix) + 1)
    return absPath
}

; Read width/height of an image file (PNG). Returns false on failure.
GetImageFileSize(path, &width, &height) {
    width := 0
    height := 0
    path := ResolveMediaPath(path)
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

SaveGdipBitmapToPng(pBitmap, path) {
    if !pBitmap || (path = "")
        return false
    if !GetPngEncoderClsid(&clsid)
        return false
    status := DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBitmap, "wstr", path, "ptr", clsid, "ptr", 0)
    return (status = 0 && FileExist(path))
}

CreateScaledGdipBitmap(pBitmap, maxEdge) {
    DllCall("gdiplus\GdipGetImageWidth", "ptr", pBitmap, "uint*", &srcW := 0)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pBitmap, "uint*", &srcH := 0)
    if (srcW < 1 || srcH < 1)
        return 0
    scale := Min(maxEdge / srcW, maxEdge / srcH, 1.0)
    dstW := Max(1, Integer(Round(srcW * scale)))
    dstH := Max(1, Integer(Round(srcH * scale)))

    pThumb := 0
    if DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", dstW, "int", dstH, "int", 0,
        "int", 0x26200A, "ptr", 0, "ptr*", &pThumb) || !pThumb
        return 0

    graphics := 0
    if DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pThumb, "ptr*", &graphics) || !graphics {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pThumb)
        return 0
    }
    DllCall("gdiplus\GdipSetInterpolationMode", "ptr", graphics, "int", 7)
    DllCall("gdiplus\GdipDrawImageRectI", "ptr", graphics, "ptr", pBitmap,
        "int", 0, "int", 0, "int", dstW, "int", dstH)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", graphics)
    return pThumb
}

; Save full-resolution PNG + scaled thumb into media\. Sets absolute paths. Returns true on full save.
SaveClipboardImageFiles(&imagePath, &thumbPath) {
    global MediaDir, ThumbMaxEdge, ThumbCounter
    imagePath := ""
    thumbPath := ""
    if !GdipEnsureStarted()
        return false
    EnsureMediaDir()

    pBitmap := 0
    if DllCall("IsClipboardFormatAvailable", "uint", 8)
        pBitmap := CreateGdipBitmapFromClipboardDib()
    if !pBitmap && DllCall("IsClipboardFormatAvailable", "uint", 2)
        pBitmap := CreateGdipBitmapFromClipboardBitmap()
    if !pBitmap
        return false

    ThumbCounter += 1
    id := A_TickCount "_" ThumbCounter
    fullPath := MediaDir "\img_" id ".png"
    thumbFull := MediaDir "\thumb_" id ".png"

    if !SaveGdipBitmapToPng(pBitmap, fullPath) {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return false
    }
    imagePath := fullPath

    pThumb := CreateScaledGdipBitmap(pBitmap, ThumbMaxEdge)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    if pThumb {
        if SaveGdipBitmapToPng(pThumb, thumbFull)
            thumbPath := thumbFull
        DllCall("gdiplus\GdipDisposeImage", "ptr", pThumb)
    }
    return true
}

; Put a saved image onto the clipboard as PNG + CF_DIB (reliable paste into modern apps).
SetClipboardFromImageFile(path) {
    path := ResolveMediaPath(path)
    if (path = "" || !FileExist(path))
        return false
    if !GdipEnsureStarted()
        return false

    pBitmap := 0
    if DllCall("gdiplus\GdipLoadImageFromFile", "wstr", path, "ptr*", &pBitmap) || !pBitmap
        return false

    if !DllCall("OpenClipboard", "ptr", 0) {
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return false
    }
    DllCall("EmptyClipboard")

    placed := false

    ; Prefer registered PNG format (raw file bytes) — browsers / chat apps often expect this
    try {
        fileSize := FileGetSize(path)
        if (fileSize > 0) {
            fileBuf := FileRead(path, "RAW")
            if (fileBuf.Size = fileSize) {
                hPng := DllCall("GlobalAlloc", "uint", 0x0002, "ptr", fileSize, "ptr")  ; GMEM_MOVEABLE
                if hPng {
                    pPng := DllCall("GlobalLock", "ptr", hPng, "ptr")
                    if pPng {
                        DllCall("RtlMoveMemory", "ptr", pPng, "ptr", fileBuf.Ptr, "ptr", fileSize)
                        DllCall("GlobalUnlock", "ptr", hPng)
                        fmtPng := DllCall("RegisterClipboardFormat", "str", "PNG", "uint")
                        if fmtPng && DllCall("SetClipboardData", "uint", fmtPng, "ptr", hPng) {
                            placed := true
                            hPng := 0  ; clipboard owns it
                        }
                    }
                    if hPng
                        DllCall("GlobalFree", "ptr", hPng)
                }
            }
        }
    } catch {
    }

    ; Also offer CF_DIB for apps that don't understand PNG clipboard format
    hDib := CreateCfDibFromGdipBitmap(pBitmap)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    if hDib {
        if DllCall("SetClipboardData", "uint", 8, "ptr", hDib) {  ; CF_DIB
            placed := true
            hDib := 0
        }
        if hDib
            DllCall("GlobalFree", "ptr", hDib)
    }

    DllCall("CloseClipboard")
    return placed
}

; Build a CF_DIB global memory block from a GDI+ bitmap. Caller owns the handle until SetClipboardData.
CreateCfDibFromGdipBitmap(pBitmap) {
    if !pBitmap
        return 0
    hBitmap := 0
    if DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", pBitmap, "ptr*", &hBitmap, "uint", 0xFFFFFFFF) || !hBitmap
        return 0

    ; BITMAP structure size differs on x64
    oiSize := A_PtrSize = 8 ? 32 : 24
    oi := Buffer(oiSize + 40, 0)  ; BITMAP + room; GetObject fills BITMAP
    if !DllCall("GetObject", "ptr", hBitmap, "int", oiSize, "ptr", oi) {
        DllCall("DeleteObject", "ptr", hBitmap)
        return 0
    }

    width := NumGet(oi, 4, "int")
    height := NumGet(oi, 8, "int")
    if (width < 1 || height < 1) {
        DllCall("DeleteObject", "ptr", hBitmap)
        return 0
    }

    ; Classic CF_DIB: 32bpp bottom-up BI_RGB
    bmi := Buffer(40, 0)
    NumPut("uint", 40, bmi, 0)
    NumPut("int", width, bmi, 4)
    NumPut("int", height, bmi, 8)  ; positive = bottom-up
    NumPut("ushort", 1, bmi, 12)
    NumPut("ushort", 32, bmi, 14)
    NumPut("uint", 0, bmi, 16)  ; BI_RGB
    stride := ((width * 32 + 31) // 32) * 4
    bitsSize := stride * height
    NumPut("uint", bitsSize, bmi, 20)

    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    hMem := DllCall("GlobalAlloc", "uint", 0x0002, "ptr", 40 + bitsSize, "ptr")  ; GMEM_MOVEABLE
    if !hMem {
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
        DllCall("DeleteObject", "ptr", hBitmap)
        return 0
    }
    pMem := DllCall("GlobalLock", "ptr", hMem, "ptr")
    if !pMem {
        DllCall("GlobalFree", "ptr", hMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
        DllCall("DeleteObject", "ptr", hBitmap)
        return 0
    }
    DllCall("RtlMoveMemory", "ptr", pMem, "ptr", bmi, "ptr", 40)
    ok := DllCall("GetDIBits", "ptr", hdc, "ptr", hBitmap, "uint", 0, "uint", height,
        "ptr", pMem + 40, "ptr", bmi, "uint", 0)
    DllCall("GlobalUnlock", "ptr", hMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    DllCall("DeleteObject", "ptr", hBitmap)
    if !ok {
        DllCall("GlobalFree", "ptr", hMem)
        return 0
    }
    return hMem
}

DeleteMediaFile(path) {
    path := ResolveMediaPath(path)
    if (path = "" || !FileExist(path))
        return
    try FileDelete(path)
}

; Delete durable image + thumb files for a history item (on delete / clear / eviction).
DeleteThumbForItem(item) {
    if !IsObject(item)
        return
    if item.Has("imagePath")
        DeleteMediaFile(item["imagePath"])
    if item.Has("thumbPath")
        DeleteMediaFile(item["thumbPath"])
}

; On exit: do not wipe media\ (persisted images). Only clean legacy TEMP thumbs + shut down GDI+.
CleanupAllThumbFiles() {
    global ThumbDir
    if DirExist(ThumbDir) {
        try {
            Loop Files ThumbDir "\thumb_*.png", "F"
                FileDelete(A_LoopFileFullPath)
        } catch {
        }
    }
    GdipShutdown()
}
