; History picker GUI — Features 1, 6, 7
; Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm

HistoryListCtrl := ""
SearchEditCtrl := ""
CurrentSearchQuery := ""

ShowClipboardHistory(*) {
    global ClipHistory, MainGui, HistoryListCtrl, SearchEditCtrl, CurrentSearchQuery, VisibleHistoryIndexes

    if (ClipHistory.Length = 0) {
        MsgBox("No clipboard history available", "Clipboard History")
        return
    }

    if IsObject(MainGui) {
        try MainGui.Destroy()
    }

    CurrentSearchQuery := ""
    MainGui := Gui("+AlwaysOnTop", "Clipboard History")
    MainGui.OnEvent("Close", (*) => MainGui.Destroy())
    MainGui.OnEvent("Escape", (*) => MainGui.Destroy())

    MainGui.Add("Text", "x10 y12 w50", "Search:")
    SearchEditCtrl := MainGui.Add("Edit", "x60 y10 w350 h24")
    SearchEditCtrl.OnEvent("Change", (*) => OnSearchChanged())

    HistoryListCtrl := MainGui.Add("ListBox", "x10 y44 w400 h180 VScroll")
    RefreshHistoryList()

    PasteBtn := MainGui.Add("Button", "x10 y234 w70 h30 Default", "Paste")
    DeleteBtn := MainGui.Add("Button", "x85 y234 w70 h30", "Delete")
    PinBtn := MainGui.Add("Button", "x160 y234 w70 h30", "Pin")
    ClearBtn := MainGui.Add("Button", "x235 y234 w70 h30", "Clear")
    SettingsBtn := MainGui.Add("Button", "x310 y234 w100 h30", "Settings")

    PasteBtn.Default := true
    PasteBtn.OnEvent("Click", (*) => PasteSelected())
    DeleteBtn.OnEvent("Click", (*) => DeleteSelected())
    PinBtn.OnEvent("Click", (*) => PinSelected())
    ClearBtn.OnEvent("Click", (*) => ClearHistory())
    SettingsBtn.OnEvent("Click", (*) => (MainGui.Destroy(), ShowSettingsGui()))
    HistoryListCtrl.OnEvent("DoubleClick", (*) => PasteSelected())

    MainGui.Show("w420 h275")
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
