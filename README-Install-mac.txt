FlameBot Desktop + MT4/MT5 EA Bundle (macOS)

1) Open FlameBot
   - Open FlameBot.app

   Note: If macOS shows a security warning (Gatekeeper):
   - Right-click FlameBot.app -> Open

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
