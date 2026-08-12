; Settings GUI — Features 4, 5, 8, 9
; Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm

SettingsGui := ""

ShowSettingsGui(*) {
    global SettingsGui
    if IsObject(SettingsGui) {
        try SettingsGui.Destroy()
    }

    SettingsGui := Gui("+AlwaysOnTop", "Clipboard Manager Settings")
    SettingsGui.OnEvent("Close", (*) => SettingsGui.Destroy())
    SettingsGui.OnEvent("Escape", (*) => SettingsGui.Destroy())

    SettingsGui.Add("Text", "x10 y15 w120", "Hotkey:")
    hotkeyEdit := SettingsGui.Add("Edit", "x140 y12 w200 h24 vHotkeyEdit", GetSetting("Hotkey"))
    SettingsGui.Add("Text", "x10 y48 w120", "Max history size:")
    maxEdit := SettingsGui.Add("Edit", "x140 y45 w80 h24 Number vMaxEdit", GetSetting("MaxHistorySize"))

    SettingsGui.Add("Text", "x10 y82 w120", "Auto-delete hours:")
    autoEdit := SettingsGui.Add("Edit", "x140 y79 w80 h24 Number vAutoEdit", GetSetting("AutoDeleteHours"))
    SettingsGui.Add("Text", "x230 y82 w160", "(0 = disabled)")

    excludeCheck := SettingsGui.Add("Checkbox", "x10 y115 w330 vExcludeCheck", "Exclude password-manager applications")
    excludeCheck.Value := (GetSetting("ExcludePasswordManagers") = "1") ? 1 : 0

    SettingsGui.Add("Text", "x10 y148 w330", "Extra excluded apps (one .exe per line):")
    extraEdit := SettingsGui.Add("Edit", "x10 y170 w360 h90 WantTab vExtraEdit", ExtraAppsToMultiline())

    startupCheck := SettingsGui.Add("Checkbox", "x10 y275 w330 vStartupCheck", "Start with Windows")
    startupCheck.Value := StartupShortcutExists() ? 1 : 0

    SettingsGui.Add("Text", "x10 y305 w360", "Password-manager exclusion skips capture when the focused app's process matches the built-in or extra list. Content from other apps is not filtered as passwords.")

    saveBtn := SettingsGui.Add("Button", "x10 y360 w100 h30 Default", "Save")
    cancelBtn := SettingsGui.Add("Button", "x120 y360 w100 h30", "Cancel")
    saveBtn.OnEvent("Click", (*) => SaveSettingsFromGui(hotkeyEdit, maxEdit, autoEdit, excludeCheck, extraEdit, startupCheck))
    cancelBtn.OnEvent("Click", (*) => SettingsGui.Destroy())

    SettingsGui.Show("w390 h405")
}

SaveSettingsFromGui(hotkeyEdit, maxEdit, autoEdit, excludeCheck, extraEdit, startupCheck) {
    global SettingsGui
    newHotkey := Trim(hotkeyEdit.Value)
    newMax := Trim(maxEdit.Value)
    newAuto := Trim(autoEdit.Value)

    if (newMax = "" || Integer(newMax) < 1) {
        MsgBox("Max history size must be at least 1.", "Settings", "Icon!")
        return
    }
    if (newAuto = "" || Integer(newAuto) < 0) {
        MsgBox("Auto-delete hours must be 0 or greater.", "Settings", "Icon!")
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
    SetSetting("ExtraExcludedApps", ExtraAppsFromMultiline(extraEdit.Value))
    SetSetting("StartWithWindows", startupCheck.Value ? "1" : "0")
    SaveConfig()

    EnforceHistoryLimit()
    ApplyStartWithWindows(startupCheck.Value = 1)
    SetupAutoDeleteTimer()

    SettingsGui.Destroy()
    MsgBox("Settings saved.", "Clipboard Manager", "T2")
}

StartupShortcutPath() {
    return A_Startup "\ClipboardManager.lnk"
}

StartupShortcutExists() {
    return FileExist(StartupShortcutPath()) != ""
}

ApplyStartWithWindows(enable) {
    linkPath := StartupShortcutPath()
    if enable {
        try FileCreateShortcut(A_ScriptFullPath, linkPath, A_ScriptDir, , "Clipboard Manager")
        catch as err
            MsgBox("Could not create startup shortcut:`n" err.Message, "Settings", "Icon!")
    } else {
        if FileExist(linkPath) {
            try FileDelete(linkPath)
            catch as err
                MsgBox("Could not remove startup shortcut:`n" err.Message, "Settings", "Icon!")
        }
    }
}
