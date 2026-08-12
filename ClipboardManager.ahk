#Requires AutoHotkey v2.0
#SingleInstance Force

; Global variables
ClipHistory := []
MaxHistorySize := 40 ; Max of the items held in memory at once, after exceding the last will be poped
MainGui := ""
LastClipboardContent := ""
IgnoreNextChange := false
LastChangeTime := 0
DebounceDelay := 100  ; milliseconds

; Monitor clipboard changes
OnClipboardChange(AddToHistory)

; Hotkey to show clipboard history (Win + v)
#v::ShowClipboardHistory()

; Simple content comparison function
IsSameContent(content1, content2) {
    if (Type(content1) != Type(content2))
        return false
    
    ; For text, direct comparison
    if (Type(content1) = "String")
        return content1 = content2
    
    ; For binary data, compare size first (quick check)
    if (content1.Size != content2.Size)
        return false
    
    ; Compare first 100 bytes for binary data (reasonable compromise)
    compareSize := Min(content1.Size, 100)
    Loop compareSize {
        if (NumGet(content1, A_Index-1, "UChar") != NumGet(content2, A_Index-1, "UChar"))
            return false
    }
    return true
}

AddToHistory(DataType) {
    global IgnoreNextChange, ClipHistory, LastClipboardContent, MaxHistorySize, LastChangeTime, DebounceDelay
    
    ; Skip if we're ignoring this change (we just pasted something)
    if (IgnoreNextChange) {
        IgnoreNextChange := false
        return
    }
    ; DataType: 0=empty, 1=text, 2=non-text (images, files, etc.)
    if (DataType = 0)
        return
    ; Enhanced debounce - longer delay for images
    currentTime := A_TickCount
    if (DataType = 2) {
        ; For images, use a longer debounce period (500ms)
        if (currentTime - LastChangeTime < 500) {
            return
        }
    } else if (DataType = 1) {
        ; For text, shorter debounce (100ms) but check content
        if (currentTime - LastChangeTime < DebounceDelay) {
            if (A_Clipboard = LastClipboardContent) {
                return ; Same text content
            }
        }
    }
    LastChangeTime := currentTime
    newItem := Map()
    currentContent := ""
    
    if (DataType = 1 && A_Clipboard != "") {
        ; Text data - increased preview length to 150 characters
        currentContent := A_Clipboard
        newItem["type"] := "text"
        newItem["content"] := A_Clipboard
        newItem["preview"] := StrReplace(SubStr(A_Clipboard, 1, 150), "`n", " ")
        if (StrLen(A_Clipboard) > 150)
            newItem["preview"] .= "..."
    } else if (DataType = 2) {
        ; Binary data (images, files, etc.)
        currentContent := ClipboardAll()
        if (DllCall("IsClipboardFormatAvailable", "uint", 2)) { ; CF_BITMAP
            newItem["type"] := "image"
            newItem["content"] := currentContent
            newItem["preview"] := "Screenshot"
        } else {
            newItem["type"] := "other"
            newItem["content"] := currentContent
            newItem["preview"] := "Other_data"
        }
    } else {
        return
    }
    
    ; Check if this content is the same as the last one
    if (IsSameContent(currentContent, LastClipboardContent))
        return
    ; Check if this content already exists in history
    for existingItem in ClipHistory {
        if (IsSameContent(currentContent, existingItem["content"]))
            return ; Don't add duplicate
    }
    ClipHistory.InsertAt(1, newItem)
    LastClipboardContent := currentContent
    if (ClipHistory.Length > MaxHistorySize)
        ClipHistory.Pop()
}

ShowClipboardHistory() {
    global ClipHistory, MainGui
    
    if (ClipHistory.Length = 0) {
        MsgBox("No clipboard history available", "Clipboard History")
        return
    }
    
    ; Create GUI
    MainGui := Gui("+AlwaysOnTop", "Clipboard History")
    MainGui.OnEvent("Close", (*) => MainGui.Destroy())
    
    ; Create ListBox
    HistoryList := MainGui.Add("ListBox", "x10 y10 w400 h200 VScroll")
    
    ; Populate list with previews
    for index, item in ClipHistory {
        typeIcon := ""
        switch item["type"] {
            case "text":
                typeIcon := "📝 "
            case "image":
                typeIcon := "📷 "
            case "other":
                typeIcon := "📄 "
        }
        HistoryList.Add([typeIcon . item["preview"]])
    }
    
    ; Select first item by default
    HistoryList.Choose(1)
    
    ; Add buttons
    PasteBtn := MainGui.Add("Button", "x10 y220 w80 h30 Default", "Paste")
    DeleteBtn := MainGui.Add("Button", "x100 y220 w80 h30", "Delete")
    CancelBtn := MainGui.Add("Button", "x190 y220 w80 h30", "Cancel")
    ClearBtn := MainGui.Add("Button", "x280 y220 w80 h30", "Clear All")

    ; Make Paste button the default (optional - adds visual indication)
    PasteBtn.Default := true
    
    ; Event handlers
    PasteBtn.OnEvent("Click", (*) => PasteSelected(HistoryList))
    DeleteBtn.OnEvent("Click", (*) => DeleteSelected(HistoryList))
    CancelBtn.OnEvent("Click", (*) => MainGui.Destroy())
    ClearBtn.OnEvent("Click", (*) => ClearHistory())
    HistoryList.OnEvent("DoubleClick", (*) => PasteSelected(HistoryList))
    
    ; Handle Escape key
    MainGui.OnEvent("Escape", (*) => MainGui.Destroy())
    
    MainGui.Show("w420 h260")
    HistoryList.Focus()
}

PasteSelected(HistoryList) {
    global ClipHistory, MainGui, IgnoreNextChange
    
    selectedIndex := HistoryList.Value
    if (selectedIndex > 0 && selectedIndex <= ClipHistory.Length) {
        selectedItem := ClipHistory[selectedIndex]
        
        ; Close GUI first
        MainGui.Destroy()
        
        ; Wait a moment for GUI to close
        Sleep(50)
        
        ; Set flag to ignore the next clipboard change (our paste)
        IgnoreNextChange := true
        
        ; Set clipboard based on type
        if (selectedItem["type"] = "text") {
            A_Clipboard := selectedItem["content"]
            ClipWait(1)
        } else {
            ; For images and other binary data
            A_Clipboard := selectedItem["content"]
            ClipWait(2)
        }
        
        Send("^v")
    } else {
        MainGui.Destroy()
    }
}

ClearHistory() {
    global ClipHistory, LastClipboardContent, MainGui
    
    ; Make MsgBox system modal (always on top)
    result := MsgBox("Clear all clipboard history?", "Confirm", "YesNo 4096")
    if (result = "Yes") {
        ClipHistory := []
        LastClipboardContent := ""
        MainGui.Destroy()
    }
}

DeleteSelected(HistoryList) {
    global ClipHistory, MainGui
    
    selectedIndex := HistoryList.Value
    if (selectedIndex > 0 && selectedIndex <= ClipHistory.Length) {
        ; Remove item from history
        ClipHistory.RemoveAt(selectedIndex)
        
        ; Remove item from ListBox
        HistoryList.Delete(selectedIndex)
        
        ; If list is now empty, close GUI
        if (ClipHistory.Length = 0) {
            MsgBox("Clipboard history is now empty", "Info")
            MainGui.Destroy()
            return
        }
        
        ; Adjust selection after deletion
        if (selectedIndex <= ClipHistory.Length) {
            HistoryList.Choose(selectedIndex)  ; Keep same position
        } else {
            HistoryList.Choose(ClipHistory.Length)  ; Select last item
        }
        
        HistoryList.Focus()  ; Return focus to list
    }
}
