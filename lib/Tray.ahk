; Tray menu — Feature 3
; Official docs: https://www.autohotkey.com/docs/v2/Variables.htm#TrayMenu

InitTray() {
    A_IconTip := "Clipboard Manager"
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open History", (*) => ShowClipboardHistory())
    pauseLabel := IsMonitoringPaused() ? "Resume Monitoring" : "Pause Monitoring"
    A_TrayMenu.Add(pauseLabel, (*) => TogglePauseFromTray())
    A_TrayMenu.Add("Settings", (*) => ShowSettingsGui())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open History"
}

TogglePauseFromTray(*) {
    SetMonitoringPaused(!IsMonitoringPaused())
}

UpdateTrayPauseLabel() {
    if IsMonitoringPaused() {
        try A_TrayMenu.Rename("Pause Monitoring", "Resume Monitoring")
    } else {
        try A_TrayMenu.Rename("Resume Monitoring", "Pause Monitoring")
    }
}
