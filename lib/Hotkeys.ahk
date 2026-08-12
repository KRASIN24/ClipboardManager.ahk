; Dynamic hotkey registration — Feature 4
; Official docs: https://www.autohotkey.com/docs/v2/lib/Hotkey.htm

CurrentHotkey := ""

ApplyHotkey(newKey) {
    global CurrentHotkey
    newKey := Trim(newKey)
    if (newKey = "") {
        MsgBox("Hotkey cannot be empty.", "Settings", "Icon!")
        return false
    }
    try {
        if (CurrentHotkey != "" && CurrentHotkey != newKey) {
            try Hotkey(CurrentHotkey, "Off")
        }
        Hotkey(newKey, (*) => ShowClipboardHistory())
        CurrentHotkey := newKey
        SetSetting("Hotkey", newKey)
        return true
    } catch as err {
        ; Restore previous if we disabled it
        if (CurrentHotkey != "") {
            try Hotkey(CurrentHotkey, (*) => ShowClipboardHistory())
        }
        MsgBox("Invalid hotkey: " newKey "`n`n" err.Message, "Settings", "Icon!")
        return false
    }
}

InitHotkeyFromConfig() {
    key := GetSetting("Hotkey")
    if (key = "")
        key := "#v"
    if !ApplyHotkey(key) {
        ApplyHotkey("#v")
        SaveConfig()
    }
}
