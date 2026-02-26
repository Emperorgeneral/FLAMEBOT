# FlameBot Bundle (Windows)

This folder is a build workspace for producing Windows and macOS releases.
On Windows, we now ship a single Inno Setup installer EXE that installs:
- FlameBot desktop app (PyQt5 + Telethon)
- MT4 EA binary (`.ex4`)
- MT5 EA binary (`.ex5`)

## Build (Windows)

```powershell
cd C:\Users\Michael Favour\Documents\FlameBot
.\build_windows.ps1   # builds portable onedir and installer
```

Outputs:
- Portable folder: `dist\\FlameBot` (for debugging)
- Windows installer: `dist\\FlameBot-Setup-v<version>.exe` (primary)
- Windows zip: `dist\\FlameBot-Windows.zip` (contains the installer + `eas/` + helper scripts)

## What users download

Ship either the installer EXE directly, or the ZIP package if you want users to access the EA files directly.
- The installer sets up FlameBot under `Program Files\\FlameBot` with shortcuts.
- The ZIP contains the installer EXE and the `eas/` folder for manual EA access.