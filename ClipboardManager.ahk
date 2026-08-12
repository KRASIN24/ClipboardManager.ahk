#Requires AutoHotkey v2.0
#SingleInstance Force

; Clipboard Manager - entry point
; Official AutoHotkey v2 docs: https://www.autohotkey.com/docs/v2/
; Modules keep dependencies flowing inward toward app state (no circular includes).

#Include "lib\Logger.ahk"
#Include "lib\Config.ahk"
#Include "lib\History.ahk"
#Include "lib\Persistence.ahk"
#Include "lib\Capture.ahk"
#Include "lib\Hotkeys.ahk"
#Include "lib\GuiHistory.ahk"
#Include "lib\GuiSettings.ahk"
#Include "lib\Tray.ahk"

LoadConfig()
LoadHistoryFromDisk()
InitTray()
InitHotkeyFromConfig()

if IsMonitoringPaused()
    StopClipboardMonitoring()
else
    StartClipboardMonitoring()

SetupAutoDeleteTimer()
OnExit(OnScriptExit)

try LogInfo("Clipboard Manager started")
Persistent()

SetupAutoDeleteTimer() {
    SetTimer(PurgeExpiredHistory, 0)  ; clear previous
    hours := Integer(GetSetting("AutoDeleteHours"))
    if (hours > 0) {
        ; Check every 5 minutes
        SetTimer(PurgeExpiredHistory, 5 * 60 * 1000)
        PurgeExpiredHistory()
    }
}
