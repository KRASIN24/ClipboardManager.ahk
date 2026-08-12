; Settings GUI — unified scrollable exclusion checklist
; Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm

SettingsGui := ""
ExcludeAppsLV := ""
AddAppEdit := ""

ShowSettingsGui(*) {
    global SettingsGui, ExcludeAppsLV, AddAppEdit
    if IsObject(SettingsGui) {
        try SettingsGui.Destroy()
    }

    SettingsGui := Gui("+AlwaysOnTop", "Clipboard Manager Settings")
    SettingsGui.Opt("+OwnDialogs")  ; MsgBoxes appear above this window
    SettingsGui.OnEvent("Close", (*) => SettingsGui.Destroy())
    SettingsGui.OnEvent("Escape", (*) => SettingsGui.Destroy())

    y := 12
    SettingsGui.Add("Text", "x10 y" y " w120", "Hotkey:")
    hotkeyEdit := SettingsGui.Add("Edit", "x140 y" y-3 " w230 h24", GetSetting("Hotkey"))
    y += 32
    SettingsGui.Add("Text", "x10 y" y " w120", "Max history size:")
    maxEdit := SettingsGui.Add("Edit", "x140 y" y-3 " w80 h24 Number", GetSetting("MaxHistorySize"))
    y += 32
    SettingsGui.Add("Text", "x10 y" y " w120", "Auto-delete hours:")
    autoEdit := SettingsGui.Add("Edit", "x140 y" y-3 " w80 h24 Number", GetSetting("AutoDeleteHours"))
    SettingsGui.Add("Text", "x230 y" y " w140", "(0 = off)")
    y += 34

    excludeCheck := SettingsGui.Add("Checkbox", "x10 y" y " w360", "Exclude password-manager apps")
    excludeCheck.Value := (GetSetting("ExcludePasswordManagers") = "1") ? 1 : 0
    y += 26

    SettingsGui.Add("Text", "x10 y" y " w360", "Excluded apps (checked = skip capture):")
    y += 20
    ExcludeAppsLV := SettingsGui.Add("ListView", "x10 y" y " w360 h110 Checked -Multi", ["Application", "Type"])
    PopulateExcludeAppsListView()
    ExcludeAppsLV.ModifyCol(1, 230)
    ExcludeAppsLV.ModifyCol(2, 100)
    y += 118

    SettingsGui.Add("Text", "x10 y" y+3 " w28", "Add:")
    AddAppEdit := SettingsGui.Add("Edit", "x40 y" y " w200 h24", "")
    addBtn := SettingsGui.Add("Button", "x250 y" y-1 " w55 h26", "Add")
    removeBtn := SettingsGui.Add("Button", "x310 y" y-1 " w60 h26", "Remove")
    ; Enter in the Add box adds the app (Save is not Default, so Enter won't close Settings)
    addBtn.OnEvent("Click", (*) => AddCustomExcludeApp())
    AddAppEdit.OnEvent("LoseFocus", (*) => "")  ; keep reference alive
    removeBtn.OnEvent("Click", (*) => RemoveSelectedCustomExcludeApp())
    y += 34

    startupCheck := SettingsGui.Add("Checkbox", "x10 y" y " w360", "Start with Windows")
    startupCheck.Value := StartupShortcutExists() ? 1 : 0
    y += 26

    clearShutdownCheck := SettingsGui.Add("Checkbox", "x10 y" y " w360", "Clear unpinned history on shutdown / logoff")
    clearShutdownCheck.Value := IsClearUnpinnedOnShutdownEnabled() ? 1 : 0
    y += 32

    saveBtn := SettingsGui.Add("Button", "x10 y" y " w100 h30", "Save")
    cancelBtn := SettingsGui.Add("Button", "x120 y" y " w100 h30", "Cancel")
    saveBtn.OnEvent("Click", (*) => SaveSettingsFromGui(hotkeyEdit, maxEdit, autoEdit, excludeCheck, startupCheck, clearShutdownCheck))
    cancelBtn.OnEvent("Click", (*) => SettingsGui.Destroy())

    ; Enter while focus is in AddAppEdit should add, not save
    SettingsGui.OnEvent("Escape", (*) => SettingsGui.Destroy())
    ; Hotkey for Enter when Add field focused — use default button swap via Gui +Default on Add
    addBtn.Opt("+Default")

    SettingsGui.Show("w390 h" (y + 45))
    AddAppEdit.Focus()
}

SettingsMsgBox(text, title := "Settings", options := "Icon!") {
    global SettingsGui
    ; OwnDialogs is set on SettingsGui; keep AlwaysOnTop behavior for the dialog thread
    try SettingsGui.Opt("+OwnDialogs")
    return MsgBox(text, title, options)
}

PopulateExcludeAppsListView() {
    global ExcludeAppsLV, BuiltInExcludedApps
    if !IsObject(ExcludeAppsLV)
        return
    ExcludeAppsLV.Delete()

    for name in BuiltInExcludedApps {
        opts := IsBuiltInExclusionEnabled(name) ? "Check" : ""
        ExcludeAppsLV.Add(opts, name, "Built-in")
    }
    for name in GetExtraExcludedAppsList() {
        if IsBuiltInApp(name)
            continue
        opts := IsExtraExclusionEnabled(name) ? "Check" : ""
        ExcludeAppsLV.Add(opts, name, "Custom")
    }
}

NormalizeExeName(name) {
    name := Trim(name)
    if (name = "")
        return ""
    ; Strip path if pasted
    if InStr(name, "\")
        name := SubStr(name, InStr(name, "\",, -1) + 1)
    if InStr(name, "/")
        name := SubStr(name, InStr(name, "/",, -1) + 1)
    if !InStr(name, ".")
        name .= ".exe"
    return name
}

AddCustomExcludeApp(*) {
    global ExcludeAppsLV, AddAppEdit, SettingsGui
    try SettingsGui.Opt("+OwnDialogs")

    if !IsObject(ExcludeAppsLV) || !IsObject(AddAppEdit) {
        SettingsMsgBox("Exclusion list is not ready.", "Settings", "Icon!")
        return
    }

    name := NormalizeExeName(AddAppEdit.Value)
    if (name = "") {
        SettingsMsgBox("Enter an app name, e.g. MyVault.exe", "Settings", "Icon!")
        return
    }

    Loop ExcludeAppsLV.GetCount() {
        if (StrLower(ExcludeAppsLV.GetText(A_Index, 1)) = StrLower(name)) {
            SettingsMsgBox(name " is already in the list.", "Settings", "Icon!")
            return
        }
    }

    typeLabel := IsBuiltInApp(name) ? "Built-in" : "Custom"
    row := ExcludeAppsLV.Add("Check", name, typeLabel)
    if (row < 1) {
        SettingsMsgBox("Could not add " name " to the list.", "Settings", "Icon!")
        return
    }
    ExcludeAppsLV.Modify(row, "Vis Select Focus")
    AddAppEdit.Value := ""

    ; Persist customs immediately so they survive without clicking Save
    PersistExcludeListsFromListView()
    AddAppEdit.Focus()
}

RemoveSelectedCustomExcludeApp(*) {
    global ExcludeAppsLV, SettingsGui
    try SettingsGui.Opt("+OwnDialogs")

    row := ExcludeAppsLV.GetNext(0, "Focused")
    if (row < 1)
        row := ExcludeAppsLV.GetNext(0)
    if (row < 1) {
        SettingsMsgBox("Select a custom app to remove.", "Settings", "Icon!")
        return
    }
    type := ExcludeAppsLV.GetText(row, 2)
    if (type != "Custom") {
        SettingsMsgBox("Built-in apps cannot be removed.`nUncheck them instead.", "Settings", "Icon!")
        return
    }
    ExcludeAppsLV.Delete(row)
    PersistExcludeListsFromListView()
}

CollectExcludeListsFromListView(&disabledBuiltIn, &extras, &disabledExtras) {
    global ExcludeAppsLV
    disabledBuiltIn := []
    extras := []
    disabledExtras := []
    if !IsObject(ExcludeAppsLV)
        return

    checkedSet := Map()
    r := 0
    while (r := ExcludeAppsLV.GetNext(r, "Checked"))
        checkedSet[StrLower(ExcludeAppsLV.GetText(r, 1))] := true

    Loop ExcludeAppsLV.GetCount() {
        i := A_Index
        name := ExcludeAppsLV.GetText(i, 1)
        type := ExcludeAppsLV.GetText(i, 2)
        isChecked := checkedSet.Has(StrLower(name))
        if (type = "Built-in") {
            if !isChecked
                disabledBuiltIn.Push(name)
        } else {
            extras.Push(name)
            if !isChecked
                disabledExtras.Push(name)
        }
    }
}

; Write exclusion lists to INI now (used after Add/Remove)
PersistExcludeListsFromListView() {
    disabledBuiltIn := []
    extras := []
    disabledExtras := []
    CollectExcludeListsFromListView(&disabledBuiltIn, &extras, &disabledExtras)
    SetDisabledBuiltInExcludedApps(disabledBuiltIn)
    SetExtraExcludedApps(extras)
    SetDisabledExtraExcludedApps(disabledExtras)
    SaveConfig()
}

SaveSettingsFromGui(hotkeyEdit, maxEdit, autoEdit, excludeCheck, startupCheck, clearShutdownCheck) {
    global SettingsGui
    try SettingsGui.Opt("+OwnDialogs")

    newHotkey := Trim(hotkeyEdit.Value)
    newMax := Trim(maxEdit.Value)
    newAuto := Trim(autoEdit.Value)

    if (newMax = "" || Integer(newMax) < 1) {
        SettingsMsgBox("Max history size must be at least 1.", "Settings", "Icon!")
        return
    }
    if (newAuto = "" || Integer(newAuto) < 0) {
        SettingsMsgBox("Auto-delete hours must be 0 or greater.", "Settings", "Icon!")
        return
    }

    oldHotkey := GetSetting("Hotkey")
    if (newHotkey != oldHotkey) {
        if !ApplyHotkey(newHotkey)
            return
    }

    SetSetting("MaxHistorySize", Integer(newMax))
    SetSetting("AutoDeleteHours", Integer(newAuto))
    SetSetting("ExcludePasswordManagers", excludeCheck.Value ? "1" : "0")
    PersistExcludeListsFromListView()
    SetSetting("StartWithWindows", startupCheck.Value ? "1" : "0")
    SetSetting("ClearUnpinnedOnShutdown", clearShutdownCheck.Value ? "1" : "0")
    SaveConfig()

    EnforceHistoryLimit()
    ApplyStartWithWindows(startupCheck.Value = 1)
    SetupAutoDeleteTimer()

    SettingsGui.Destroy()
    MsgBox("Settings saved.", "Clipboard Manager", "T2 4096")
}

StartupShortcutPath() {
    return A_Startup "\ClipboardManager.lnk"
}

StartupShortcutExists() {
    return FileExist(StartupShortcutPath()) != ""
}

ApplyStartWithWindows(enable) {
    global SettingsGui
    try SettingsGui.Opt("+OwnDialogs")
    linkPath := StartupShortcutPath()
    if enable {
        try FileCreateShortcut(A_ScriptFullPath, linkPath, A_ScriptDir, , "Clipboard Manager")
        catch as err
            SettingsMsgBox("Could not create startup shortcut:`n" err.Message, "Settings", "Icon!")
    } else {
        if FileExist(linkPath) {
            try FileDelete(linkPath)
            catch as err
                SettingsMsgBox("Could not remove startup shortcut:`n" err.Message, "Settings", "Icon!")
        }
    }
}
