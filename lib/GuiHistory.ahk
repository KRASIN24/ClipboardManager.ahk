; History picker GUI — Features 1, 6, 7 + on-demand image side preview
; Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm

HistoryListCtrl := ""
SearchEditCtrl := ""
PreviewPicCtrl := ""
PreviewLabelCtrl := ""
CurrentSearchQuery := ""
PreviewExpanded := false

ShowClipboardHistory(*) {
    global ClipHistory, MainGui, HistoryListCtrl, SearchEditCtrl, CurrentSearchQuery
    global VisibleHistoryIndexes, PreviewPicCtrl, PreviewLabelCtrl, PreviewExpanded

    if (ClipHistory.Length = 0) {
        MsgBox("No clipboard history available", "Clipboard History")
        return
    }

    if IsObject(MainGui) {
        try MainGui.Destroy()
    }

    CurrentSearchQuery := ""
    PreviewExpanded := false
    MainGui := Gui("+AlwaysOnTop", "Clipboard History")
    MainGui.OnEvent("Close", (*) => MainGui.Destroy())
    MainGui.OnEvent("Escape", (*) => MainGui.Destroy())

    MainGui.Add("Text", "x10 y12 w50", "Search:")
    SearchEditCtrl := MainGui.Add("Edit", "x60 y10 w350 h24")
    SearchEditCtrl.OnEvent("Change", (*) => OnSearchChanged())

    HistoryListCtrl := MainGui.Add("ListBox", "x10 y44 w400 h200 VScroll")
    HistoryListCtrl.OnEvent("Change", (*) => UpdatePreviewPane())
    HistoryListCtrl.OnEvent("DoubleClick", (*) => PasteSelected())

    PreviewLabelCtrl := MainGui.Add("Text", "x420 y44 w240", "Preview")
    PreviewPicCtrl := MainGui.Add("Picture", "x420 y64 w240 h180")
    PreviewLabelCtrl.Visible := false
    PreviewPicCtrl.Visible := false

    PasteBtn := MainGui.Add("Button", "x10 y254 w70 h30 Default", "Paste")
    DeleteBtn := MainGui.Add("Button", "x85 y254 w70 h30", "Delete")
    PinBtn := MainGui.Add("Button", "x160 y254 w70 h30", "Pin")
    ClearBtn := MainGui.Add("Button", "x235 y254 w70 h30", "Clear")
    SettingsBtn := MainGui.Add("Button", "x310 y254 w100 h30", "Settings")

    PasteBtn.Default := true
    PasteBtn.OnEvent("Click", (*) => PasteSelected())
    DeleteBtn.OnEvent("Click", (*) => DeleteSelected())
    PinBtn.OnEvent("Click", (*) => PinSelected())
    ClearBtn.OnEvent("Click", (*) => ClearHistory())
    SettingsBtn.OnEvent("Click", (*) => (MainGui.Destroy(), ShowSettingsGui()))

    RefreshHistoryList()
    ; Compact window until an image is selected
    MainGui.Show("w420 h295")
    HistoryListCtrl.Focus()
}

OnSearchChanged() {
    global SearchEditCtrl, CurrentSearchQuery
    CurrentSearchQuery := SearchEditCtrl.Value
    RefreshHistoryList()
}

RefreshHistoryList() {
    global ClipHistory, HistoryListCtrl, CurrentSearchQuery, VisibleHistoryIndexes
    if !IsObject(HistoryListCtrl)
        return
    HistoryListCtrl.Delete()
    VisibleHistoryIndexes := []
    query := StrLower(Trim(CurrentSearchQuery))
    for index, item in ClipHistory {
        hay := StrLower(item["preview"] (item["type"] = "text" ? item["content"] : ""))
        if (query = "" || InStr(hay, query)) {
            VisibleHistoryIndexes.Push(index)
            HistoryListCtrl.Add([FormatItemLabel(item)])
        }
    }
    if (VisibleHistoryIndexes.Length > 0)
        HistoryListCtrl.Choose(1)
    ; Do not auto-show preview on open/refresh — only after user changes selection
    HideImagePreview()
}

UpdatePreviewPane(*) {
    global ClipHistory, PreviewPicCtrl
    if !IsObject(PreviewPicCtrl)
        return

    selectedIndex := ResolveSelectedHistoryIndex()
    if (selectedIndex < 1 || selectedIndex > ClipHistory.Length) {
        HideImagePreview()
        return
    }

    item := ClipHistory[selectedIndex]
    if (item["type"] = "image" && item.Has("thumbPath") && FileExist(item["thumbPath"])) {
        ShowImagePreview(item["thumbPath"])
        return
    }
    HideImagePreview()
}

ShowImagePreview(thumbPath) {
    global MainGui, PreviewPicCtrl, PreviewLabelCtrl, PreviewExpanded, SearchEditCtrl
    global MaxPreviewWidth, MaxPreviewHeight

    srcW := 0
    srcH := 0
    if !GetImageFileSize(thumbPath, &srcW, &srcH) {
        HideImagePreview()
        return
    }

    dispW := 0
    dispH := 0
    FitImageSize(srcW, srcH, MaxPreviewWidth, MaxPreviewHeight, &dispW, &dispH)

    previewX := 420
    gap := 10
    winW := previewX + dispW + gap
    listSearchW := winW - 70

    try {
        PreviewLabelCtrl.Move(previewX, 44, dispW, 16)
        PreviewLabelCtrl.Visible := true

        ; Re-apply size every click so aspect ratio matches this image
        PreviewPicCtrl.Move(previewX, 64, dispW, dispH)
        PreviewPicCtrl.Opt("w" dispW " h" dispH)
        PreviewPicCtrl.Value := thumbPath
        PreviewPicCtrl.Visible := true

        try SearchEditCtrl.Move(, , listSearchW)
        MainGui.Show("w" winW " h295")
        PreviewExpanded := true
    } catch {
        HideImagePreview()
    }
}

HideImagePreview() {
    global MainGui, PreviewPicCtrl, PreviewLabelCtrl, PreviewExpanded, SearchEditCtrl
    try {
        PreviewPicCtrl.Visible := false
        PreviewLabelCtrl.Visible := false
        try PreviewPicCtrl.Value := ""
    } catch {
    }
    if PreviewExpanded {
        PreviewExpanded := false
        try SearchEditCtrl.Move(, , 350)
        try MainGui.Show("w420 h295")
    }
}

ResolveSelectedHistoryIndex() {
    global HistoryListCtrl, VisibleHistoryIndexes
    visible := HistoryListCtrl.Value
    if (visible < 1 || visible > VisibleHistoryIndexes.Length)
        return 0
    return VisibleHistoryIndexes[visible]
}

PasteSelected(*) {
    global ClipHistory, MainGui, IgnoreNextChange
    selectedIndex := ResolveSelectedHistoryIndex()
    if (selectedIndex > 0 && selectedIndex <= ClipHistory.Length) {
        selectedItem := ClipHistory[selectedIndex]
        MainGui.Destroy()
        Sleep(50)
        IgnoreNextChange := true
        A_Clipboard := selectedItem["content"]
        if (selectedItem["type"] = "text")
            ClipWait(1)
        else
            ClipWait(2)
        Send("^v")
    } else if IsObject(MainGui) {
        MainGui.Destroy()
    }
}

DeleteSelected(*) {
    global ClipHistory, MainGui, HistoryListCtrl
    selectedIndex := ResolveSelectedHistoryIndex()
    if (selectedIndex < 1)
        return
    DeleteHistoryAt(selectedIndex)
    if (ClipHistory.Length = 0) {
        MsgBox("Clipboard history is now empty", "Info")
        MainGui.Destroy()
        return
    }
    RefreshHistoryList()
    HistoryListCtrl.Focus()
}

PinSelected(*) {
    global ClipHistory, HistoryListCtrl
    selectedIndex := ResolveSelectedHistoryIndex()
    if (selectedIndex < 1)
        return
    TogglePinAt(selectedIndex)
    RefreshHistoryList()
    HistoryListCtrl.Focus()
}

ClearHistory(*) {
    global ClipHistory, MainGui
    result := MsgBox("Clear all unpinned clipboard history?`n(Pinned items are kept.)", "Confirm", "YesNo 4096")
    if (result = "Yes") {
        ClearUnpinnedHistory()
        if (ClipHistory.Length = 0)
            MainGui.Destroy()
        else
            RefreshHistoryList()
    }
}
