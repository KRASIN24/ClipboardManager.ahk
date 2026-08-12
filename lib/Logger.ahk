; Lightweight logging — Feature 11
; Official docs: https://www.autohotkey.com/docs/v2/

LogFilePath := A_ScriptDir "\ClipboardManager.log"
LogMaxBytes := 512 * 1024  ; ~512 KB cap; truncate when exceeded

LogInfo(msg) {
    LogWrite("INFO", msg)
}

LogWarn(msg) {
    LogWrite("WARN", msg)
}

LogError(msg) {
    LogWrite("ERROR", msg)
}

LogWrite(level, msg) {
    global LogFilePath, LogMaxBytes
    try {
        if FileExist(LogFilePath) {
            fileSize := FileGetSize(LogFilePath)
            if (fileSize > LogMaxBytes) {
                FileDelete(LogFilePath)
            }
        }
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg "`n"
        FileAppend(line, LogFilePath, "UTF-8")
    } catch {
        ; Never let logging crash the script
    }
}
