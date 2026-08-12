; Settings load/save — Feature 1+
; Official docs: https://www.autohotkey.com/docs/v2/lib/IniRead.htm

ConfigFilePath := A_ScriptDir "\ClipboardManager.ini"

; Easy-to-extend built-in password-manager process names (case-insensitive match).
; Only include names verified against real Windows process names / vendor docs.
; Extend via ExtraExcludedApps in Settings for anything else.
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
    global AppConfig, ConfigFilePath, BuiltInExcludedApps
    defaults := Map(
        "MaxHistorySize", "40",
        "Hotkey", "#v",
        "MonitoringPaused", "0",
        "ExcludePasswordManagers", "1",
        "ExtraExcludedApps", "",
        "AutoDeleteHours", "0",
        "StartWithWindows", "0"
    )
    AppConfig := Map()
    for key, defaultVal in defaults {
        AppConfig[key] := IniRead(ConfigFilePath, "Settings", key, defaultVal)
    }
    ; Ensure INI exists with current values
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

GetExtraExcludedAppsList() {
    raw := GetSetting("ExtraExcludedApps")
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

; Convert multiline edit (one exe per line) to comma-separated INI value
ExtraAppsFromMultiline(text) {
    list := []
    for line in StrSplit(text, "`n", "`r") {
        name := Trim(line)
        if (name != "")
            list.Push(name)
    }
    result := ""
    for index, name in list {
        if (index > 1)
            result .= ","
        result .= name
    }
    return result
}

ExtraAppsToMultiline() {
    list := GetExtraExcludedAppsList()
    result := ""
    for index, name in list {
        if (index > 1)
            result .= "`n"
        result .= name
    }
    return result
}

GetAllExcludedApps() {
    global BuiltInExcludedApps
    merged := []
    if IsExcludePasswordManagersEnabled() {
        for name in BuiltInExcludedApps
            merged.Push(name)
    }
    for name in GetExtraExcludedAppsList()
        merged.Push(name)
    return merged
}
