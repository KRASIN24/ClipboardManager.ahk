# Clipboard Manager

AutoHotkey v2 clipboard history tool for Windows. It watches the clipboard, keeps a local history, and lets you search, pin, paste, or delete earlier items.

Official AHK v2 docs: [https://www.autohotkey.com/docs/v2/](https://www.autohotkey.com/docs/v2/)

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)

## Quick start

1. Double-click `ClipboardManager.ahk` (or run it with AutoHotkey v2).
2. Copy text, images, or files as usual.
3. Press **Win+V** (default) to open history, or use the tray icon → **Open History**.
4. Select an item → **Paste** (or double-click / Enter).

Close the picker with the window **X** or **Esc**.

## Features

- Clipboard history with configurable size limit
- Configurable global hotkey
- Search in the history window
- Pin favorites (pins survive Clear; exempt from size eviction and auto-delete)
- Delete individual entries / clear unpinned history
- Text persistence across restarts (`history.json`)
- Tray menu: Open History, Pause/Resume monitoring, Settings, Exit
- Start with Windows (Startup-folder shortcut)
- Auto-delete unpinned entries after X hours
- Types: text, image, file, other
- Exclude password-manager apps (and custom `.exe` names)
- Lightweight log file

## Tray menu

| Item | Action |
|------|--------|
| Open History | Opens the history picker |
| Pause / Resume Monitoring | Stops or resumes capturing new clipboard changes |
| Settings | Opens the settings window |
| Exit | Quits the script |

## Settings

Open **Settings** from the tray or the history window.

| Setting | Meaning |
|---------|---------|
| Hotkey | AHK hotkey string (default `#v` = Win+V) |
| Max history size | Max items kept (default 40) |
| Auto-delete hours | Remove unpinned items older than this (`0` = off) |
| Exclude password-manager applications | Skip capture when the focused app is in the built-in list |
| Extra excluded apps | One `.exe` name per line (always excluded) |
| Start with Windows | Creates/removes `%AppData%\...\Startup\ClipboardManager.lnk` |

Settings are stored in `ClipboardManager.ini` next to the script.

### Password-manager exclusions

When enabled, clipboard changes are **not** stored if the focused window’s process matches the built-in list (KeePass, KeePassXC, Bitwarden, 1Password, LastPass, Dashlane, Enpass) or your extra list.

This does **not** detect passwords by content. A password copied from Chrome, Notepad, etc. can still be stored.

## Persistence

- **Text** entries are saved to `history.json` (atomic write via a temp file).
- **Images and files** stay in memory for the current session only and are **not** restored after restart.

## Project layout

```
ClipboardManager.ahk    Entry point
ClipboardManager.ini    User settings (created on first run)
history.json            Persisted text history
ClipboardManager.log    Diagnostics log
lib/
  Config.ahk            INI load/save, built-in exclusions
  History.ahk           In-memory history CRUD, pins, limits
  Capture.ahk           OnClipboardChange, pause, exclusions
  Persistence.ahk       Text-only save/load
  Hotkeys.ahk           Dynamic hotkey bind/rebind
  GuiHistory.ahk        History picker + search
  GuiSettings.ahk       Settings UI + startup shortcut
  Tray.ahk              Tray menu
  Logger.ahk            Simple file logging
```

## Hotkey examples

| Setting value | Keys |
|---------------|------|
| `#v` | Win+V |
| `^!v` | Ctrl+Alt+V |
| `^+v` | Ctrl+Shift+V |

See [Hotkeys](https://www.autohotkey.com/docs/v2/Hotkeys.htm) in the AHK v2 docs.

## Notes

- `#SingleInstance Force` — starting the script again replaces the previous instance.
- If **Win+V** does nothing, Windows Clipboard history or another app may own that shortcut; change the hotkey in Settings.
- Keep the script running (tray icon) for monitoring to work.
