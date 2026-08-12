; Clipboard capture — Features 1, 3, 5, 10
; Official docs: https://www.autohotkey.com/docs/v2/lib/OnClipboardChange.htm

LastChangeTime := 0
DebounceDelay := 100  ; ms for text

StartClipboardMonitoring() {
    OnClipboardChange(AddToHistory, 1)
}

StopClipboardMonitoring() {
    OnClipboardChange(AddToHistory, 0)
}

SetMonitoringPaused(paused) {
    SetSetting("MonitoringPaused", paused ? "1" : "0")
    SaveConfig()
    if paused {
        StopClipboardMonitoring()
        try LogInfo("Clipboard monitoring paused")
    } else {
        StartClipboardMonitoring()
        try LogInfo("Clipboard monitoring resumed")
    }
    UpdateTrayPauseLabel()
}

IsActiveWindowExcluded() {
    try {
        procName := WinGetProcessName("A")
    } catch {
        return false
    }
    for excluded in GetAllExcludedApps() {
        if (StrLower(procName) = StrLower(excluded))
            return true
    }
    return false
}

AddToHistory(DataType) {
    global IgnoreNextChange, LastClipboardContent, LastChangeTime, DebounceDelay

    if IgnoreNextChange {
        IgnoreNextChange := false
        return
    }
    if IsMonitoringPaused()
        return
    ; DataType: 0=empty, 1=text (includes files from Explorer as text path list in some cases),
    ; 2=non-text (images, etc.)
    if (DataType = 0)
        return

    if IsActiveWindowExcluded() {
        try LogInfo("Clipboard ignored - excluded application")
        return
    }

    currentTime := A_TickCount
    if (DataType = 2) {
        if (currentTime - LastChangeTime < 500)
            return
    } else if (DataType = 1) {
        if (currentTime - LastChangeTime < DebounceDelay) {
            if (A_Clipboard = LastClipboardContent)
                return
        }
    }
    LastChangeTime := currentTime

    newItem := ""
    currentContent := ""

    ; Prefer file-list detection (CF_HDROP = 15) even when DataType is 1 or 2
    if DllCall("IsClipboardFormatAvailable", "uint", 15) {
        currentContent := ClipboardAll()
        if HistoryHasDuplicate(currentContent)
            return
        filePreview := BuildFilePreview()
        newItem := MakeHistoryItem("file", currentContent, filePreview)
        AddHistoryItem(newItem)
        return
    }

    if (DataType = 1 && A_Clipboard != "") {
        currentContent := A_Clipboard
        if HistoryHasDuplicate(currentContent)
            return
        preview := StrReplace(SubStr(A_Clipboard, 1, 150), "`n", " ")
        if (StrLen(A_Clipboard) > 150)
            preview .= "..."
        newItem := MakeHistoryItem("text", A_Clipboard, preview)
        AddHistoryItem(newItem)
        return
    }

    if (DataType = 2) {
        currentContent := ClipboardAll()
        if HistoryHasDuplicate(currentContent)
            return
        if DllCall("IsClipboardFormatAvailable", "uint", 2) { ; CF_BITMAP
            width := 0
            height := 0
            GetClipboardBitmapSize(&width, &height)
            preview := BuildImagePreviewLabel(width, height)
            newItem := MakeHistoryItem("image", currentContent, preview)
            imagePath := ""
            thumbPath := ""
            if SaveClipboardImageFiles(&imagePath, &thumbPath) {
                newItem["imagePath"] := imagePath
                if (thumbPath != "")
                    newItem["thumbPath"] := thumbPath
            }
        } else {
            newItem := MakeHistoryItem("other", currentContent, "Other_data")
        }
        AddHistoryItem(newItem)
    }
}

BuildFilePreview() {
    ; Try to show file path(s) from clipboard text if available
    clipText := ""
    try clipText := A_Clipboard
    if (clipText != "") {
        preview := StrReplace(SubStr(clipText, 1, 150), "`n", " ")
        if (StrLen(clipText) > 150)
            preview .= "..."
        return preview
    }
    return "File(s)"
}
