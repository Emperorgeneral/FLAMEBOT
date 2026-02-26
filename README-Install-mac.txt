FlameBot Desktop + MT4/MT5 EA Bundle (macOS)

1) Open FlameBot
   - Open FlameBot.app

   Note: If macOS shows a security warning (Gatekeeper):
   - Right-click FlameBot.app -> Open

   Telegram API credentials
   - The app ships with embedded Telegram API ID/Hash (managed mode). No telegram_app.json is shipped in the zip.
   - Optional override without a rebuild: create ~/.tg_copier/telegram_app.json
     {
       "api_id": 1234567,
       "api_hash": "your_api_hash"
     }
     Relaunch FlameBot after adding this file.

2) Install EAs (choose one)
   A) In-app (recommended):
      - Open FlameBot
      - Go to Settings
         - Click "Install MT4/MT5 EA"
         - If prompted, select the destination folder(s):
            - MT4: MQL4/Experts (or MQL4/Experts/Advisors)
            - MT5: MQL5/Experts (or MQL5/Experts/Advisors)

   B) Manual:
      - In MetaTrader: File -> Open Data Folder
      - Copy:
        eas/mt4/FLAMEBOTMT4 EA.ex4 -> MQL4/Experts/(Advisors)
        eas/mt5/FLAMEBOT MT5 EA.ex5 -> MQL5/Experts/(Advisors)

After copying:
- Restart MetaTrader, then attach the EA to a chart.

 EA prerequisites (MT4 Options -> Expert Advisors):
 - Allow automated trading
 - Allow DLL imports
 - Allow WebRequest for listed URL and add:
    https://web-production-49c22.up.railway.app