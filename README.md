````markdown
# FlameBot Releases (ZIP-only)

This workspace builds release ZIPs for both Windows and macOS. Users download a ZIP and unzip locally to access the app and EAs.

Contents included in ZIPs:
- FlameBot desktop app (PyQt5 + Telethon)
- MT4 EA binary (`.ex4`)
- MT5 EA binary (`.ex5`)

## Build (Windows)

```powershell
cd C:\Users\Michael Favour\Documents\FlameBot
.\build_windows.ps1   # builds portable onedir and package ZIP
```

Outputs:
- Portable folder: `dist\\FlameBot` (for debugging)
- Windows ZIP: `dist\\FlameBot-Windows.zip` (contains installer + `eas/` + helper scripts)
- macOS ZIP: `dist/FlameBot-macOS.zip`

## What users download

Download the ZIP for your OS and unzip it. On Windows, the ZIP also includes an installer EXE if you prefer a guided setup, but the release page only provides ZIP assets.
````