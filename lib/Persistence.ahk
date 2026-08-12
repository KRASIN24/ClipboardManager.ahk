; History persistence — text + images (files/other stay session-only).
; Image binaries live under media\; history.json stores paths + metadata.
; Official docs: https://www.autohotkey.com/docs/v2/lib/FileOpen.htm

HistoryFilePath := A_ScriptDir "\history.json"
HistoryTmpPath := A_ScriptDir "\history.json.tmp"
SavePending := false

ScheduleHistorySave() {
    global SavePending
    SavePending := true
    SetTimer(FlushHistorySave, -300)  ; debounce 300ms
}

FlushHistorySave(*) {
    global SavePending
    if !SavePending
        return
    SavePending := false
    SaveHistoryToDisk()
}

LoadHistoryFromDisk() {
    global ClipHistory, HistoryFilePath, LastClipboardContent
    if !FileExist(HistoryFilePath) {
        ClipHistory := []
        return
    }
    try {
        raw := FileRead(HistoryFilePath, "UTF-8")
        items := ParseHistoryJson(raw)
        ClipHistory := []
        textCount := 0
        imageCount := 0
        for item in items {
            t := item["type"]
            if (t = "text") {
                ClipHistory.Push(item)
                textCount++
            } else if (t = "image") {
                imgAbs := ResolveMediaPath(item.Has("imagePath") ? item["imagePath"] : "")
                if (imgAbs = "" || !FileExist(imgAbs))
                    continue
                item["imagePath"] := imgAbs
                if item.Has("thumbPath") && (item["thumbPath"] != "") {
                    thumbAbs := ResolveMediaPath(item["thumbPath"])
                    item["thumbPath"] := FileExist(thumbAbs) ? thumbAbs : ""
                }
                item["content"] := ""  ; paste uses imagePath after restart
                ClipHistory.Push(item)
                imageCount++
            }
        }
        SortPinnedToTop()
        if (ClipHistory.Length > 0)
            LastClipboardContent := ClipHistory[1]["content"]
        else
            LastClipboardContent := ""
        try LogInfo("History loaded (" textCount " text, " imageCount " image)")
    } catch as err {
        ClipHistory := []
        LastClipboardContent := ""
        try LogWarn("Failed to load history: " err.Message)
    }
}

SaveHistoryToDisk() {
    global ClipHistory, HistoryFilePath, HistoryTmpPath
    ; Persist text and images; files/other remain session-only
    persistItems := []
    for item in ClipHistory {
        if (item["type"] = "text") {
            persistItems.Push(item)
        } else if (item["type"] = "image") {
            if item.Has("imagePath") && (item["imagePath"] != "") && FileExist(ResolveMediaPath(item["imagePath"]))
                persistItems.Push(item)
        }
    }
    json := BuildHistoryJson(persistItems)
    try {
        if FileExist(HistoryTmpPath)
            FileDelete(HistoryTmpPath)
        FileAppend(json, HistoryTmpPath, "UTF-8")
        FileMove(HistoryTmpPath, HistoryFilePath, true)
    } catch as err {
        try LogError("Failed to save history: " err.Message)
        try {
            if FileExist(HistoryTmpPath)
                FileDelete(HistoryTmpPath)
        } catch {
        }
    }
}

OnScriptExit(ExitReason, *) {
    ; Clear unpinned items on Windows shutdown/logoff so tokens etc. do not survive reboot
    if ((ExitReason = "Shutdown" || ExitReason = "Logoff") && IsClearUnpinnedOnShutdownEnabled()) {
        ClearUnpinnedHistory()
        try LogInfo("Cleared unpinned history on " ExitReason)
    }
    FlushHistorySave()
    SaveHistoryToDisk()
    CleanupAllThumbFiles()
}

BuildHistoryJson(items) {
    parts := []
    for item in items {
        pinned := (item.Has("pinned") && item["pinned"]) ? "true" : "false"
        created := item.Has("createdAt") ? item["createdAt"] : A_Now
        t := item["type"]
        ; Never serialize ClipboardAll binary into JSON
        contentStr := (t = "image") ? "" : item["content"]
        obj := "{"
            . '"type":' JsonString(t) ","
            . '"content":' JsonString(contentStr) ","
            . '"preview":' JsonString(item["preview"]) ","
            . '"pinned":' pinned ","
            . '"createdAt":' JsonString(created)
        if (t = "image") {
            imgRel := ToRelativeMediaPath(item.Has("imagePath") ? item["imagePath"] : "")
            thumbRel := ToRelativeMediaPath(item.Has("thumbPath") ? item["thumbPath"] : "")
            obj .= ',"imagePath":' JsonString(imgRel)
            obj .= ',"thumbPath":' JsonString(thumbRel)
        }
        obj .= "}"
        parts.Push(obj)
    }
    body := ""
    for index, part in parts {
        if (index > 1)
            body .= ","
        body .= part
    }
    return "[" body "]"
}

JsonString(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return '"' s '"'
}

; Minimal JSON array parser for our history shape (objects with string/bool fields)
ParseHistoryJson(raw) {
    raw := Trim(raw)
    items := []
    if (raw = "" || raw = "[]")
        return items
    if (SubStr(raw, 1, 1) != "[" || SubStr(raw, -1) != "]")
        throw Error("Invalid history JSON")

    pos := 2
    len := StrLen(raw)
    while (pos < len) {
        SkipJsonWs(raw, &pos)
        if (SubStr(raw, pos, 1) = "]") {
            pos++
            break
        }
        if (SubStr(raw, pos, 1) != "{")
            throw Error("Expected object")
        objEnd := FindMatchingBrace(raw, pos)
        objText := SubStr(raw, pos, objEnd - pos + 1)
        items.Push(ParseHistoryObject(objText))
        pos := objEnd + 1
        SkipJsonWs(raw, &pos)
        if (SubStr(raw, pos, 1) = ",") {
            pos++
            continue
        }
        if (SubStr(raw, pos, 1) = "]") {
            pos++
            break
        }
        throw Error("Invalid history JSON separator")
    }
    SkipJsonWs(raw, &pos)
    if (pos <= StrLen(raw))
        throw Error("Trailing garbage in history JSON")
    return items
}

SkipJsonWs(raw, &pos) {
    while (pos <= StrLen(raw)) {
        ch := SubStr(raw, pos, 1)
        if (ch = " " || ch = "`t" || ch = "`n" || ch = "`r")
            pos++
        else
            break
    }
}

FindMatchingBrace(raw, startPos) {
    depth := 0
    inString := false
    escape := false
    i := startPos
    len := StrLen(raw)
    while (i <= len) {
        ch := SubStr(raw, i, 1)
        if inString {
            if escape {
                escape := false
            } else if (ch = "\") {
                escape := true
            } else if (ch = '"') {
                inString := false
            }
        } else {
            if (ch = '"')
                inString := true
            else if (ch = "{")
                depth++
            else if (ch = "}") {
                depth--
                if (depth = 0)
                    return i
            }
        }
        i++
    }
    throw Error("Unbalanced braces")
}

ParseHistoryObject(objText) {
    item := Map()
    item["type"] := JsonExtractString(objText, "type")
    item["content"] := JsonExtractString(objText, "content")
    item["preview"] := JsonExtractString(objText, "preview")
    item["createdAt"] := JsonExtractString(objText, "createdAt")
    if (item["createdAt"] = "")
        item["createdAt"] := A_Now
    item["pinned"] := JsonExtractBool(objText, "pinned")
    imagePath := JsonExtractString(objText, "imagePath")
    thumbPath := JsonExtractString(objText, "thumbPath")
    if (imagePath != "")
        item["imagePath"] := imagePath
    if (thumbPath != "")
        item["thumbPath"] := thumbPath
    return item
}

JsonExtractString(objText, key) {
    ; Find "key": then parse JSON string
    needle := '"' key '":'
    idx := InStr(objText, needle)
    if !idx
        return ""
    pos := idx + StrLen(needle)
    SkipJsonWs(objText, &pos)
    if (SubStr(objText, pos, 1) != '"')
        return ""
    pos++
    out := ""
    len := StrLen(objText)
    while (pos <= len) {
        ch := SubStr(objText, pos, 1)
        if (ch = "\") {
            pos++
            esc := SubStr(objText, pos, 1)
            switch esc {
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case '"': out .= '"'
                case "\": out .= "\"
                default: out .= esc
            }
            pos++
            continue
        }
        if (ch = '"')
            break
        out .= ch
        pos++
    }
    return out
}

JsonExtractBool(objText, key) {
    needle := '"' key '":'
    idx := InStr(objText, needle)
    if !idx
        return false
    pos := idx + StrLen(needle)
    SkipJsonWs(objText, &pos)
    fragment := SubStr(objText, pos, 5)
    return (SubStr(fragment, 1, 4) = "true")
}
