FlameBot Desktop + MT4/MT5 EA Bundle (Windows)

Bundled runtime dependencies (no extra installs required)
- The packaged app includes Python runtime dependencies from requirements.txt.
- PyQt WebEngine is bundled for inline secure payment forms in-app.
- Telethon and other required Python modules are bundled into the shipped build.
- Users should not need to run pip or install Python separately to use the installer build.

1) Install and run FlameBot (recommended)
    - Run `FlameBot-Setup-v*.exe` and complete the installer wizard.
    - Launch FlameBot from the Start menu or desktop shortcut.

    Portable fallback:
    - If using the portable package instead of the installer, open `FlameBot.exe` directly.

   Telegram API credentials
   - The app ships with embedded Telegram API ID/Hash (managed mode). You will NOT see any telegram_app.json in the folder.
   - If you ever need to override without a rebuild, place a file at:
     %USERPROFILE%\.tg_copier\telegram_app.json
     {
       "api_id": 1234567,
       "api_hash": "your_api_hash"
     }
     Restart FlameBot after adding this file.

2) Install EAs (choose one)
   A) Automatic:
      - Right-click Install_EAs.ps1 > Run with PowerShell
      - Or from a PowerShell prompt in this folder:
        ./Install_EAs.ps1 -Force

   B) In-app (recommended):
      - Open FlameBot.exe
      - Go to Settings
      - Click "Install MT4/MT5 EA" and follow the prompts

   C) Manual:
      - Copy eas\FLAMEBOT MT4 EA.ex4 -> your MT4 Data Folder\MQL4\Experts\Advisors\
      - Copy eas\FLAMEBOT MT5 EA.ex5 -> your MT5 Data Folder\MQL5\Experts\Advisors\

MetaTrader Data Folder:
- In MT4/MT5: File -> Open Data Folder

After copying:
- Restart MetaTrader, then attach the EA to a chart.

 EA prerequisites (MT4 Options -> Expert Advisors):
 - Allow automated trading
 - Allow DLL imports
 - Allow WebRequest for listed URL and add:
    https://web-production-49c22.up.railway.app