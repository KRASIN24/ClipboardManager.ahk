; In-memory clipboard history CRUD — Features 1, 7, 9
; Official docs: https://www.autohotkey.com/docs/v2/

ClipHistory := []
LastClipboardContent := ""
IgnoreNextChange := false
MainGui := ""
; Maps ListBox visible row -> ClipHistory index (for search)
VisibleHistoryIndexes := []

IsSameContent(content1, content2) {
    if (Type(content1) != Type(content2))
        return false
    if (Type(content1) = "String")
        return content1 = content2
    if (content1.Size != content2.Size)
        return false
    compareSize := Min(content1.Size, 100)
    Loop compareSize {
        if (NumGet(content1, A_Index - 1, "UChar") != NumGet(content2, A_Index - 1, "UChar"))
            return false
    }
    return true
}

MakeHistoryItem(type, content, preview) {
    item := Map()
    item["type"] := type
    item["content"] := content
    item["preview"] := preview
    item["pinned"] := false
    item["createdAt"] := A_Now  ; YYYYMMDDHH24MISS
    return item
}

HistoryHasDuplicate(content) {
    global ClipHistory, LastClipboardContent
    if IsSameContent(content, LastClipboardContent)
        return true
    for existingItem in ClipHistory {
        if IsSameContent(content, existingItem["content"])
            return true
    }
    return false
}

AddHistoryItem(item) {
    global ClipHistory, LastClipboardContent
    ClipHistory.InsertAt(1, item)
    LastClipboardContent := item["content"]
    EnforceHistoryLimit()
    SortPinnedToTop()
    try LogInfo("Clipboard captured (" item["type"] ")")
    ScheduleHistorySave()
}

EnforceHistoryLimit() {
    global ClipHistory
    maxSize := GetMaxHistorySize()
    ; Remove oldest unpinned items until within limit
    while (ClipHistory.Length > maxSize) {
        removed := false
        ; Walk from end (oldest) and remove first unpinned
        i := ClipHistory.Length
        while (i >= 1) {
            pinned := ClipHistory[i].Has("pinned") && ClipHistory[i]["pinned"]
            if !pinned {
                DeleteThumbForItem(ClipHistory[i])
                ClipHistory.RemoveAt(i)
                removed := true
                break
            }
            i--
        }
        if !removed
            break  ; all remaining are pinned
    }
}

SortPinnedToTop() {
    global ClipHistory
    pinned := []
    unpinned := []
    for item in ClipHistory {
        if (item.Has("pinned") && item["pinned"])
            pinned.Push(item)
        else
            unpinned.Push(item)
    }
    ClipHistory := []
    for item in pinned
        ClipHistory.Push(item)
    for item in unpinned
        ClipHistory.Push(item)
}

DeleteHistoryAt(index) {
    global ClipHistory
    if (index < 1 || index > ClipHistory.Length)
        return false
    DeleteThumbForItem(ClipHistory[index])
    ClipHistory.RemoveAt(index)
    try LogInfo("History entry deleted")
    ScheduleHistorySave()
    return true
}

; Clear All clears only unpinned entries (Feature 7)
ClearUnpinnedHistory() {
    global ClipHistory, LastClipboardContent
    kept := []
    for item in ClipHistory {
        if (item.Has("pinned") && item["pinned"]) {
            kept.Push(item)
        } else {
            DeleteThumbForItem(item)
        }
    }
    ClipHistory := kept
    if (ClipHistory.Length = 0)
        LastClipboardContent := ""
    ScheduleHistorySave()
}

TogglePinAt(index) {
    global ClipHistory
    if (index < 1 || index > ClipHistory.Length)
        return
    item := ClipHistory[index]
    if !item.Has("pinned")
        item["pinned"] := false
    item["pinned"] := !item["pinned"]
    SortPinnedToTop()
    ScheduleHistorySave()
}

; Remove unpinned items older than AutoDeleteHours (Feature 9)
PurgeExpiredHistory() {
    global ClipHistory
    hours := Integer(GetSetting("AutoDeleteHours"))
    if (hours <= 0)
        return
    cutoff := DateAdd(A_Now, -hours, "Hours")
    i := ClipHistory.Length
    changed := false
    while (i >= 1) {
        item := ClipHistory[i]
        pinned := item.Has("pinned") && item["pinned"]
        created := item.Has("createdAt") ? item["createdAt"] : A_Now
        if (!pinned && created < cutoff) {
            DeleteThumbForItem(item)
            ClipHistory.RemoveAt(i)
            changed := true
        }
        i--
    }
    if changed
        ScheduleHistorySave()
}

FormatItemLabel(item) {
    typeIcon := ""
    switch item["type"] {
        case "text":
            typeIcon := "📝 "
        case "image":
            typeIcon := "📷 "
        case "file":
            typeIcon := "📁 "
        default:
            typeIcon := "📄 "
    }
    pinIcon := (item.Has("pinned") && item["pinned"]) ? "📌 " : ""
    return pinIcon . typeIcon . item["preview"]
}
