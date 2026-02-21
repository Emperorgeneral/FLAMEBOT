# FlameBot Bundle (Windows)

This folder is a small build workspace for producing a single Windows download that contains:
- FlameBot desktop app (PyQt5 + Telethon)
- MT4 EA binary (`.ex4`)
- MT5 EA binary (`.ex5`)

## Build (Windows)

```powershell
cd C:\Users\Michael Favour\Documents\FlameBot
.\build_windows.ps1
```

Output:
- `dist\FlameBot-Windows.zip`

## What users download

Ship the `FlameBot-Windows.zip` file on your website.
It contains `FlameBot.exe` plus an `eas\` folder and `Install_EAs.ps1`.
