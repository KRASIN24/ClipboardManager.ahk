; History picker GUI — Features 1, 6, 7 + on-demand image side preview
; Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm

HistoryListCtrl := ""
SearchEditCtrl := ""
EmptyStatusCtrl := ""
PreviewPicCtrl := ""
PreviewLabelCtrl := ""
CurrentSearchQuery := ""
PreviewExpanded := false
PasteBtn := ""
DeleteBtn := ""
PinBtn := ""
ClearBtn := ""

EmptyHistoryMessage := "Clipboard history is empty"

ShowClipboardHistory(*) {
    global ClipHistory, MainGui, HistoryListCtrl, SearchEditCtrl, CurrentSearchQuery
    global VisibleHistoryIndexes, PreviewPicCtrl, PreviewLabelCtrl, PreviewExpanded
    global EmptyStatusCtrl, EmptyHistoryMessage
    global PasteBtn, DeleteBtn, PinBtn, ClearBtn

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

    ; Shown instead of MsgBox when there is nothing to list
    EmptyStatusCtrl := MainGui.Add("Text", "x10 y120 w400 h40 Center", EmptyHistoryMessage)
    EmptyStatusCtrl.Visible := false

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
    if (ClipHistory.Length > 0)
        HistoryListCtrl.Focus()
    else
        SearchEditCtrl.Focus()
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
    ; ListBox has no .Length — LB_RESETCONTENT clears all rows
    try SendMessage(0x0184, 0, 0, HistoryListCtrl)  ; LB_RESETCONTENT
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
    UpdateEmptyHistoryState()
    ; Do not auto-show preview on open/refresh — only after user changes selection
    HideImagePreview()
}

UpdateEmptyHistoryState() {
    global ClipHistory, HistoryListCtrl, EmptyStatusCtrl, EmptyHistoryMessage
    global PasteBtn, DeleteBtn, PinBtn, ClearBtn
    isEmpty := (ClipHistory.Length = 0)
    if IsObject(EmptyStatusCtrl) {
        EmptyStatusCtrl.Text := EmptyHistoryMessage
        EmptyStatusCtrl.Visible := isEmpty
    }
    if IsObject(HistoryListCtrl)
        HistoryListCtrl.Visible := !isEmpty
    try PasteBtn.Enabled := !isEmpty
    try DeleteBtn.Enabled := !isEmpty
    try PinBtn.Enabled := !isEmpty
    try ClearBtn.Enabled := !isEmpty
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
    if (item["type"] = "image") {
        previewPath := ""
        if item.Has("thumbPath") && (item["thumbPath"] != "") {
            previewPath := ResolveMediaPath(item["thumbPath"])
            if !FileExist(previewPath)
                previewPath := ""
        }
        if (previewPath = "" && item.Has("imagePath")) {
            previewPath := ResolveMediaPath(item["imagePath"])
            if !FileExist(previewPath)
                previewPath := ""
        }
        if (previewPath != "") {
            ShowImagePreview(previewPath)
            return
        }
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
    if !IsObject(HistoryListCtrl) || !HistoryListCtrl.Visible
        return 0
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
        if (selectedItem["type"] = "image") {
            ; Prefer saved PNG — browser "Copy image" ClipboardAll often includes HTML/URL
            ; formats that Ctrl+V pastes instead of the bitmap.
            pasted := false
            if selectedItem.Has("imagePath") && (selectedItem["imagePath"] != "")
                pasted := SetClipboardFromImageFile(selectedItem["imagePath"])
            if !pasted {
                content := selectedItem.Has("content") ? selectedItem["content"] : ""
                if (Type(content) = "ClipboardAll" && content.Size > 0) {
                    A_Clipboard := content
                    pasted := true
                }
            }
            if !pasted
                return
            ClipWait(2)
        } else {
            A_Clipboard := selectedItem["content"]
            if (selectedItem["type"] = "text")
                ClipWait(1)
            else
                ClipWait(2)
        }
        Send("^v")
    } else if IsObject(MainGui) {
        MainGui.Destroy()
    }
}

DeleteSelected(*) {
    global ClipHistory, HistoryListCtrl
    selectedIndex := ResolveSelectedHistoryIndex()
    if (selectedIndex < 1)
        return
    DeleteHistoryAt(selectedIndex)
    RefreshHistoryList()
    if (ClipHistory.Length > 0 && IsObject(HistoryListCtrl))
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
    global ClipHistory
    if (ClipHistory.Length = 0)
        return
    result := MsgBox("Clear all unpinned clipboard history?`n(Pinned items are kept.)", "Confirm", "YesNo 4096")
    if (result = "Yes") {
        ClearUnpinnedHistory()
        RefreshHistoryList()
    }
}
