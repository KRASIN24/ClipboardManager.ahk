; Settings load/save — Feature 1+
; Official docs: https://www.autohotkey.com/docs/v2/lib/IniRead.htm

ConfigFilePath := A_ScriptDir "\ClipboardManager.ini"

; Easy-to-extend built-in password-manager process names (case-insensitive match).
; Per-app disable: DisabledBuiltInExcludedApps.
; Custom apps: ExtraExcludedApps (all known) + DisabledExtraExcludedApps (unchecked).
BuiltInExcludedApps := [
    "KeePass.exe",
    "KeePassXC.exe",
    "Bitwarden.exe",
    "1Password.exe",
    "LastPass.exe",
    "Dashlane.exe",
    "Enpass.exe"
]

; Runtime settings map
AppConfig := Map()

LoadConfig() {
    global AppConfig, ConfigFilePath
    defaults := Map(
        "MaxHistorySize", "40",
        "Hotkey", "#v",
        "MonitoringPaused", "0",
        "ExcludePasswordManagers", "1",
        "DisabledBuiltInExcludedApps", "",
        "ExtraExcludedApps", "",
        "DisabledExtraExcludedApps", "",
        "AutoDeleteHours", "0",
        "StartWithWindows", "0"
    )
    AppConfig := Map()
    for key, defaultVal in defaults {
        AppConfig[key] := IniRead(ConfigFilePath, "Settings", key, defaultVal)
    }
    SaveConfig()
}

SaveConfig() {
    global AppConfig, ConfigFilePath
    for key, val in AppConfig {
        IniWrite(val, ConfigFilePath, "Settings", key)
    }
}

GetSetting(name) {
    global AppConfig
    if AppConfig.Has(name)
        return AppConfig[name]
    return ""
}

SetSetting(name, value) {
    global AppConfig
    AppConfig[name] := String(value)
}

GetMaxHistorySize() {
    size := Integer(GetSetting("MaxHistorySize"))
    if (size < 1)
        size := 1
    return size
}

IsExcludePasswordManagersEnabled() {
    return GetSetting("ExcludePasswordManagers") = "1"
}

IsMonitoringPaused() {
    return GetSetting("MonitoringPaused") = "1"
}

ParseExeList(raw) {
    list := []
    if (raw = "")
        return list
    for part in StrSplit(raw, ",") {
        name := Trim(part)
        if (name != "")
            list.Push(name)
    }
    return list
}

JoinExeList(list) {
    result := ""
    for index, name in list {
        if (index > 1)
            result .= ","
        result .= name
    }
    return result
}

ExeListToSet(list) {
    set := Map()
    for name in list
        set[StrLower(name)] := true
    return set
}

GetExtraExcludedAppsList() {
    return ParseExeList(GetSetting("ExtraExcludedApps"))
}

GetDisabledBuiltInExcludedApps() {
    return ParseExeList(GetSetting("DisabledBuiltInExcludedApps"))
}

GetDisabledExtraExcludedApps() {
    return ParseExeList(GetSetting("DisabledExtraExcludedApps"))
}

IsBuiltInApp(exeName) {
    global BuiltInExcludedApps
    target := StrLower(exeName)
    for name in BuiltInExcludedApps {
        if (StrLower(name) = target)
            return true
    }
    return false
}

IsBuiltInExclusionEnabled(exeName) {
    return !ExeListToSet(GetDisabledBuiltInExcludedApps()).Has(StrLower(exeName))
}

IsExtraExclusionEnabled(exeName) {
    return !ExeListToSet(GetDisabledExtraExcludedApps()).Has(StrLower(exeName))
}

SetDisabledBuiltInExcludedApps(list) {
    SetSetting("DisabledBuiltInExcludedApps", JoinExeList(list))
}

SetExtraExcludedApps(list) {
    SetSetting("ExtraExcludedApps", JoinExeList(list))
}

SetDisabledExtraExcludedApps(list) {
    SetSetting("DisabledExtraExcludedApps", JoinExeList(list))
}

GetAllExcludedApps() {
    global BuiltInExcludedApps
    merged := []
    if IsExcludePasswordManagersEnabled() {
        for name in BuiltInExcludedApps {
            if IsBuiltInExclusionEnabled(name)
                merged.Push(name)
        }
    }
    for name in GetExtraExcludedAppsList() {
        if IsExtraExclusionEnabled(name)
            merged.Push(name)
    }
    return merged
}
