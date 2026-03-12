// Resolve symbol for a given signal_id by scanning positions and orders
string ResolveSymbolForSignal(const string signal_id)
{
   if(StringLen(signal_id) == 0)
      return "";

   int ptotal = PositionsTotal();
   for(int pi = 0; pi < ptotal; pi++)
   {
      ulong pticket = PositionGetTicket(pi);
      if(pticket == 0)
         continue;
      string pcomment = PositionGetString(POSITION_COMMENT);
      // HARD FILTER: resolve symbol only from trades whose comment contains the exact signal_id/target_id token
      if(StringFind(pcomment, signal_id) >= 0)
         return PositionGetString(POSITION_SYMBOL);
   }

   int ototal = OrdersTotal();
   for(int oi = ototal - 1; oi >= 0; oi--)
   {
      ulong ticket = OrderGetTicket(oi);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;

      string ocomment = OrderGetString(ORDER_COMMENT);
      // HARD FILTER: resolve symbol only from orders whose comment contains the exact signal_id/target_id token
      if(StringFind(ocomment, signal_id) >= 0)
         return OrderGetString(ORDER_SYMBOL);
   }

   return "";
}

// Extract a signal_id token from a trade/order comment.
// Expected formats include: "sig_<id>_tpN" or comments containing the id.
// Extract signal_id token from a trade/order comment
// New format: tp1|g{group_id}|s{signal_id}
// Old format: grp_{group_id}|sig_{signal_id}|tp1
string ExtractSignalIdFromComment(const string comment)
{
   if(StringLen(comment) == 0)
      return "";
   
   // Try new format first: |s{signal_id}
   int pos = StringFind(comment, "|s");
   if(pos >= 0)
   {
      int start = pos + 2; // after "|s"
      int len = StringLen(comment);
      int end = start;
      while(end < len)
      {
         int ch = StringGetCharacter(comment, end);
         if(ch == '|') break;
         end++;
      }
      return StringSubstr(comment, start, end - start);
   }
   
   // Fall back to old format: sig_{signal_id}
   pos = StringFind(comment, "sig_");
   if(pos == -1)
      {
         // If comment starts with 's' (front-truncated), extract after the leading 's'
         if(StringLen(comment) > 0 && StringGetCharacter(comment, 0) == 's')
         {
            int startNoPipe = 1; // after leading 's'
            int lenNoPipe = StringLen(comment);
            int endNoPipe = startNoPipe;
            while(endNoPipe < lenNoPipe)
            {
               int ch = StringGetCharacter(comment, endNoPipe);
               if(ch == '|' || ch == ' ' || ch == ',' || ch == ';' || ch == ')' || ch == '(') break;
               endNoPipe++;
            }
            return StringSubstr(comment, startNoPipe, endNoPipe - startNoPipe);
         }
         return comment; // Fallback: use the whole comment as identifier substring
      }
   int start = pos + 4; // after "sig_"
   int len = StringLen(comment);
   int end = start;
   while(end < len)
   {
      int ch = StringGetCharacter(comment, end);
      if(ch == '_' || ch == ' ' || ch == '|' || ch == ',' || ch == ';' || ch == ')' || ch == '(')
         break;
      end++;
   }
   return StringSubstr(comment, start, end - start);
}

// Extract group_id token from a trade/order comment
// New format: tp1|g{group_id}|s{signal_id}
// Old format: grp_{group_id}|sig_{signal_id}|tp1
string ExtractGroupIdFromComment(const string comment)
{
   if(StringLen(comment) == 0)
      return "";
   
   // Try new format first: |g{group_id}
   int pos = StringFind(comment, "|g");
   if(pos >= 0)
   {
      int start = pos + 2; // after "|g"
      int len = StringLen(comment);
      int end = start;
      while(end < len)
      {
         int ch = StringGetCharacter(comment, end);
         if(ch == '|') break;
         end++;
      }
      return StringSubstr(comment, start, end - start);
   }
   
   // Fall back to old format: grp_{group_id}
   pos = StringFind(comment, "grp_");
   if(pos == -1)
      return "";
   int start = pos + 4; // after "grp_"
   int len = StringLen(comment);
   int end = start;
   while(end < len)
   {
      int ch = StringGetCharacter(comment, end);
      if(ch == '_' || ch == ' ' || ch == '|' || ch == ',' || ch == ';' || ch == ')' || ch == '(')
         break;
      end++;
   }
   return StringSubstr(comment, start, end - start);
}

// Resolve any active signal_id for a given symbol by scanning positions and pendings.
// Returns a suitable identifier substring that existing handlers can match via StringFind.
string ResolveActiveSignalIdForSymbol(const string symbol)
{
   if(StringLen(symbol) == 0)
      return "";
   // Scan open positions first
   int ptotal = PositionsTotal();
   for(int i = 0; i < ptotal; i++)
   {
      ulong pticket = PositionGetTicket(i);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      if(psym != symbol)
         continue;
      string pcomment = PositionGetString(POSITION_COMMENT);
      string pid = ExtractSignalIdFromComment(pcomment);
      if(StringLen(pid) > 0)
         return pid;
   }
   // Then scan pending orders
   int ototal = OrdersTotal();
   for(int j = 0; j < ototal; j++)
   {
      ulong oticket = OrderGetTicket(j);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      if((int)omagic != gMagicNumber)
         continue;
      string osym = OrderGetString(ORDER_SYMBOL);
      if(osym != symbol)
         continue;
      string ocomment = OrderGetString(ORDER_COMMENT);
      string oid = ExtractSignalIdFromComment(ocomment);
      if(StringLen(oid) > 0)
         return oid;
   }
   return "";
}

// --- trade_uid idempotency (restart-safe) ---------------------------------
int gTradeUidTtlSec = 3600;
ulong gLastTradeUidCleanupMs = 0;

uint FBFnv1a32(const string s)
{
   uint h = 2166136261;
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      h ^= (uchar)StringGetCharacter(s, i);
      h *= 16777619;
   }
   return h;
}

string FBTradeUidKey(const string uid)
{
   if(StringLen(uid) == 0)
      return "";
   return "FB.TUID." + StringFormat("%08X", FBFnv1a32(uid));
}

bool FBHasExecutedTradeUid(const string uid)
{
   if(StringLen(uid) == 0)
      return false;

   // If TTL is disabled, do not persistently block re-entry.
   if(gTradeUidTtlSec <= 0)
      return false;
   string key = FBTradeUidKey(uid);
   if(StringLen(key) == 0)
      return false;
   if(!GlobalVariableCheck(key))
      return false;

   // Expire old keys to avoid permanent blocks.
   double ts = GlobalVariableGet(key);
   datetime now = TimeCurrent();
   if(ts > 0 && (now - (datetime)ts) > gTradeUidTtlSec)
   {
      GlobalVariableDel(key);
      return false;
   }
   return true;
}

void FBRememberTradeUid(const string uid)
{
   if(StringLen(uid) == 0)
      return;
   if(gTradeUidTtlSec <= 0)
      return;
   string key = FBTradeUidKey(uid);
   if(StringLen(key) == 0)
      return;
   GlobalVariableSet(key, (double)TimeCurrent());
}

void FBCleanupTradeUidGlobals()
{
   if(gTradeUidTtlSec <= 0)
      return;

   datetime now = TimeCurrent();
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, "FB.TUID.") != 0)
         continue;

      double ts = GlobalVariableGet(name);
      if(ts <= 0 || (now - (datetime)ts) > gTradeUidTtlSec)
         GlobalVariableDel(name);
   }
}

// --- Telegram trade-control rejection idempotency (restart-safe) ------------
// If a trade-control command arrives while its toggle is OFF, treat it as
// permanently discarded for that *Telegram message id* (signal_id/target_id).
// If the backend ever re-sends the same message later, we must NOT execute it.
string FBRejectedCmdKey(const string action, const string uid)
{
   string a = action;
   StringToLower(a);
   string u = uid;
   if(StringLen(u) == 0)
      return "";
   return "FB.RCMD." + StringFormat("%08X", FBFnv1a32(a + "|" + u));
}

bool FBHasRejectedCmd(const string action, const string uid)
{
   if(StringLen(uid) == 0)
      return false;
   // Use same TTL as trade_uid dedupe to avoid unbounded GlobalVariables growth.
   if(gTradeUidTtlSec <= 0)
      return false;
   string key = FBRejectedCmdKey(action, uid);
   if(StringLen(key) == 0)
      return false;
   if(!GlobalVariableCheck(key))
      return false;
   double ts = GlobalVariableGet(key);
   datetime now = TimeCurrent();
   if(ts > 0 && (now - (datetime)ts) > gTradeUidTtlSec)
   {
      GlobalVariableDel(key);
      return false;
   }
   return true;
}

void FBRememberRejectedCmd(const string action, const string uid)
{
   if(StringLen(uid) == 0)
      return;
   if(gTradeUidTtlSec <= 0)
      return;
   string key = FBRejectedCmdKey(action, uid);
   if(StringLen(key) == 0)
      return;
   GlobalVariableSet(key, (double)TimeCurrent());
}
//+------------------------------------------------------------------+
//| FlameBot Signal EA                                               |
//| Fetches text signals from an HTTP endpoint and places trades.    |
//| Designed to recognise symbols flexibly and honour TP/SL/entry.   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- Inputs
input string InpServerUrl = "https://web-production-49c22.up.railway.app"; // Server base URL
input string InpUserId    = "";                                   // FlameBot ID (read-only input)
input string InpLicense   = "";                                   // License key     (read-only input)
input int    InpPollMs    = 1000;                                  // Poll interval
input int    InpRequestTimeoutMs = 15000;                          // Network request timeout (ms)
input int    InpTradeUidTtlSec = 3600;                              // trade_uid dedupe TTL seconds (0 disables)
input int    InpBackendRefreshSec = 15;                            // refresh server settings every X seconds
input bool   InpUseTimerForSettings = true;                        // Keep settings updated even without ticks (recommended)
input bool   InpLogTradeStatePushes = false;                       // Debug: log every trade-state push (noisy)
input int    InpLogLevel = 2;                                      // 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG
input bool   InpPrintStartupStatus = false;                        // Print startup status lines (log level, etc.)
input double InpDeviationUSDPerMicroLot = 1.0;                     // Max allowed deviation in USD per 0.01 lot (converted to account currency before enforcing)
input double InpRiskAccount = 0.0;                                 // Risk amount in account deposit currency (normalized to USD before lot sizing). 0=use legacy lot sizing
input bool   InpLogToFile = true;                                  // Write FlameBot logs to MQL5/Files (clean log)
input string InpLogFileName = "FlameBot.log";                     // Log file name under MQL5/Files
input bool   InpMirrorLogsToTerminal = true;                       // Also print FlameBot logs to Terminal

//--- Logging control
enum FB_LOG_LEVEL
{
   FB_LOG_ERROR = 0,
   FB_LOG_WARN  = 1,
   FB_LOG_INFO  = 2,
   FB_LOG_DEBUG = 3
};

int gLogLevel = FB_LOG_INFO;

int ClampLogLevel(const int v)
{
   if(v < FB_LOG_ERROR)
      return FB_LOG_ERROR;
   if(v > FB_LOG_DEBUG)
      return FB_LOG_DEBUG;
   return v;
}

bool LogEnabled(const int level)
{
   return(gLogLevel >= level);
}

bool gFileLogFailed = false;

void FBWriteLogLine(const string msg)
{
   if(!InpLogToFile)
      return;

   const int handle = FileOpen(InpLogFileName, FILE_TXT|FILE_WRITE|FILE_READ|FILE_SHARE_WRITE|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      if(!gFileLogFailed)
      {
         gFileLogFailed = true;
         if(InpMirrorLogsToTerminal)
            Print(StringFormat("[FlameBot][WARN] File logging disabled: FileOpen failed (%d)", GetLastError()));
      }
      return;
   }

   FileSeek(handle, 0, SEEK_END);
   const string line = TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS) + " " + msg;
   FileWrite(handle, line);
   FileClose(handle);
}

bool FBShouldMirrorToTerminal(const int level, const string msg)
{
   if(!InpMirrorLogsToTerminal)
      return false;

   // Suppress noisy startup INFO lines in the Terminal/Journals.
   // (They can still be written to the log file.)
   if(level == FB_LOG_INFO)
   {
      if(StringFind(msg, "[FlameBot][INFO] EA build tag:") >= 0)
         return false;
      if(StringFind(msg, "[FlameBot][INFO] Timer enabled") >= 0)
         return false;
   }
   return true;
}

void FBEmitLog(const string msg, const int level)
{
   FBWriteLogLine(msg);
   if(FBShouldMirrorToTerminal(level, msg))
      Print(msg);
}

void FBLogError(const string msg)
{
   if(!LogEnabled(FB_LOG_ERROR))
      return;
   FBEmitLog(msg, FB_LOG_ERROR);
}

void FBLogWarn(const string msg)
{
   if(!LogEnabled(FB_LOG_WARN))
      return;
   FBEmitLog(msg, FB_LOG_WARN);
}

void FBLogInfo(const string msg)
{
   if(!LogEnabled(FB_LOG_INFO))
      return;
   FBEmitLog(msg, FB_LOG_INFO);
}

void FBLogDebug(const string msg)
{
   if(!LogEnabled(FB_LOG_DEBUG))
      return;
   FBEmitLog(msg, FB_LOG_DEBUG);
}

//--- Mutable credentials (decoupled from inputs to avoid modifying constants)
string gUserId     = "";
string gLicenseKey = "";
bool   gAuthReady  = false;
bool   gLoginOk    = false;
bool   gLoginBlocked = false;
string gLoginBlockReason = "";
bool   gLoginBlockLogged = false;
bool   gAutoConnectAttempted = false;

//--- Account type (authoritative from backend license)
string gAccountType = "UNKNOWN";   // "prop" | "normal" | UNKNOWN
bool   gIsPropAccount = false;      // derived from gAccountType
bool   gAccountTypeReady = false;   // true after login response parsed

//--- Backend settings
string gLotMode = "default"; // default | custom
double gCustomLot = 0.0;
bool   gLotSettingsLoaded = false;
bool   gLotConfigured = false;
bool   gLotPendingLogged = false;

string gAllowedSymbols[];
bool   gSymbolSettingsLoaded = false;
bool   gSymbolConfigured = false;
bool   gSymbolPendingLogged = false;
string gSymbolMode = "default";

//--- PSL (Per-Symbol Lot) settings
struct PSLItem
{
   string symbol;
   double lot;
};
PSLItem gPSLLots[];
bool   gPSLConfigured = false;
bool   gPSLSettingsLoaded = false;

//--- Active Trade Mode (GLS or PSL)
string gExecutionMode = "gls"; // "gls" or "psl" - set by backend
string gLastExecutionMode = "";
bool   gTradeModeLoaded = false;

bool   gTradingUnlocked = false;
bool   gWaitingAnnounced = false;
bool   gLoginAnnounced = false;
bool   gSymbolsPushedOnce = false;
bool   gHeartbeatSent = false;
string gLastHeartbeatResponse = "";
bool   gConnectionDown = false; // connection-loss state (for one-shot logs)
bool   gFastTimer = false;
bool   gTimerStarted = false;

bool FBEnableTimerSafe()
{
   if(!InpUseTimerForSettings)
      return false;

   ResetLastError();
   int secsToTry[3] = {1, 2, 5};
   for(int ti = 0; ti < 3; ti++)
   {
      int sec = secsToTry[ti];
      if(EventSetTimer(sec))
      {
         gTimerStarted = true;
         if(LogEnabled(FB_LOG_INFO))
            FBLogInfo(StringFormat("[FlameBot][INFO] Timer enabled | interval_sec=%d", sec));
         return true;
      }
      int err = GetLastError();
      if(LogEnabled(FB_LOG_WARN))
         FBLogWarn(StringFormat("[FlameBot][WARN] Timer enable failed | interval_sec=%d | err=%d", sec, err));
      ResetLastError();
   }

   gTimerStarted = false;
   FBLogWarn("[FlameBot][WARN] Timer disabled: EA will rely on ticks only (may idle when market is quiet/closed)");
   return false;
}

void FBSetTimerMode(const bool fast)
{
   // Match MT4 behavior: use a simple 1-second timer (no millisecond timer mode).
   if(!InpUseTimerForSettings)
      return;
   if(gFastTimer == fast)
      return;
   EventKillTimer();
   gTimerStarted = false;
   FBEnableTimerSafe();
   gFastTimer = fast;
}

string FBAuthorPanelSuppressKey()
{
   return StringFormat("FlameBot.AuthPanel.Suppress.%I64d", (long)ChartID());
}

bool FBIsAuthPanelSuppressed()
{
   return GlobalVariableCheck(FBAuthorPanelSuppressKey());
}

void FBSuppressAuthPanel()
{
   string k = FBAuthorPanelSuppressKey();
   GlobalVariableTemp(k);
   GlobalVariableSet(k, 1.0);
}

void FBClearAuthPanelSuppression()
{
   string k = FBAuthorPanelSuppressKey();
   if(GlobalVariableCheck(k))
      GlobalVariableDel(k);
}

void FBMarkConnectionDownOnce()
{
   if(gConnectionDown)
      return;
   // Force visibility even when InpLogLevel=0 (ERROR-only)
   FBLogError("[FlameBot][WARN] Connection lost. Check your internet connection.");
   gConnectionDown = true;
}

void FBMarkConnectionUpOnce()
{
   if(!gConnectionDown)
      return;
   // Force visibility even when InpLogLevel=0 (ERROR-only)
   FBLogError("[FlameBot][INFO] Connection restored.");
   gConnectionDown = false;
}

//--- Terminal identity (stable per MetaTrader installation)
string gTerminalId = "";

//--- FX conversion (USD reference -> account currency execution)
const double FB_BASE_THRESHOLD_USD = 1.0; // canonical $1 reference unit
string gAccountCurrency = "";
double gUsdToAccRate = 1.0;
bool   gUsdToAccRateValid = false;
ulong  gUsdToAccRateLastMs = 0;
string gUsdToAccSymbol = "";
ulong  gFxRateErrorLastMs = 0;

double gAccToUsdRate = 1.0;
bool   gAccToUsdRateValid = false;
ulong  gAccToUsdRateLastMs = 0;
string gAccToUsdSymbol = "";
ulong  gAccFxRateErrorLastMs = 0;

string FBUpper(const string s)
{
   string t = s;
   StringToUpper(t);
   return t;
}

bool FBStartsWith(const string s, const string prefix)
{
   int plen = StringLen(prefix);
   if(plen <= 0)
      return(true);
   if(StringLen(s) < plen)
      return(false);
   return(StringSubstr(s, 0, plen) == prefix);
}

string FBGetAccountCurrency()
{
   if(gAccountCurrency == "")
      gAccountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   return gAccountCurrency;
}

bool FBTryGetBid(const string symbol, double &bid)
{
   MqlTick tick;
   if(!SymbolSelect(symbol, true))
      return(false);
   if(!SymbolInfoTick(symbol, tick))
      return(false);
   if(tick.bid <= 0.0)
      return(false);
   bid = tick.bid;
   return(true);
}

bool FBFindBestSymbolByPrefix(const string prefix, string &bestSymbol, double &bestBid)
{
   bestSymbol = "";
   bestBid = 0.0;

   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      string sym = SymbolName(i, true);
      if(!FBStartsWith(sym, prefix))
         continue;

      double bid = 0.0;
      if(!FBTryGetBid(sym, bid))
         continue;

      if(bestSymbol == "" || StringLen(sym) < StringLen(bestSymbol))
      {
         bestSymbol = sym;
         bestBid = bid;
      }
   }

   return(bestSymbol != "");
}

bool FBComputeUsdToAccountRate(double &rate, string &pairUsed)
{
   string acc = FBUpper(FBGetAccountCurrency());
   if(acc == "")
      return(false);
   if(acc == "USD")
   {
      rate = 1.0;
      pairUsed = "USD";
      return(true);
   }

   string directPrefix = "USD" + acc;
   double bid = 0.0;

   if(FBTryGetBid(directPrefix, bid))
   {
      rate = bid;
      pairUsed = directPrefix;
      return(true);
   }

   string best = "";
   if(FBFindBestSymbolByPrefix(directPrefix, best, bid))
   {
      rate = bid;
      pairUsed = best;
      return(true);
   }

   string invPrefix = acc + "USD";
   if(FBTryGetBid(invPrefix, bid) && bid > 0.0)
   {
      rate = 1.0 / bid;
      pairUsed = invPrefix;
      return(true);
   }

   if(FBFindBestSymbolByPrefix(invPrefix, best, bid) && bid > 0.0)
   {
      rate = 1.0 / bid;
      pairUsed = best;
      return(true);
   }

   return(false);
}

bool FBGetUsdToAccountRate(double &rate)
{
   ulong now = GetTickCount64();
   if(gUsdToAccRateValid && (now - gUsdToAccRateLastMs) < 60000)
   {
      rate = gUsdToAccRate;
      return(true);
   }

   double r = 0.0;
   string pair = "";
   if(!FBComputeUsdToAccountRate(r, pair))
   {
      gUsdToAccRateValid = false;
      gUsdToAccRate = 1.0;
      gUsdToAccRateLastMs = now;
      gUsdToAccSymbol = "";
      rate = 0.0;

      if(now - gFxRateErrorLastMs > 30000)
      {
         string acc = FBGetAccountCurrency();
         FBLogError(StringFormat("[FlameBot][ERROR] Missing FX conversion for USD->%s. Need symbol USD%s or %sUSD (or broker suffix variant). Blocking trades for safety.", acc, acc, acc));
         gFxRateErrorLastMs = now;
      }
      return(false);
   }

   gUsdToAccRateValid = true;
   gUsdToAccRate = r;
   gUsdToAccRateLastMs = now;
   gUsdToAccSymbol = pair;
   rate = r;
   return(true);
}

bool FBConvertUsdToAccount(const double amountUsd, double &amountAcc)
{
   double rate = 0.0;
   if(!FBGetUsdToAccountRate(rate))
      return(false);
   amountAcc = amountUsd * rate;
   return(true);
}

//--- Logging state
bool   gLotFinalPrinted = false;
bool   gSymbolFinalPrinted = false;
string gLotPrintedMode = "";
double gLotPrintedCustom = 0.0;
string gSymbolPrintedMode = "";
int    gSymbolPrintedCount = 0;

//--- PSL Logging state (mirrors GLS pattern)
bool   gPSLFinalPrinted = false;
int    gLastPSLCount = -1;

//--- Trade Control Toggle state
bool   gAllowMessageClose = false;
bool   gAllowMessageBreakeven = false;
bool   gAllowSecureHalf = false;
bool   gTogglesPrinted = false;

//--- Entry strategy mode for range signals ("market_edge" | "range_distributed")
string gEntryMode = "market_edge";
bool   gEntryModePrinted = false;

// Trade-state push log control
bool   gTradeStateLogPrinted = false;
bool   gTradeStatesSummaryPrinted = false;

// Push trade-state snapshot on trade events (throttled)
ulong  gLastTradeTxnPushMs = 0;
int    gTradeTxnPushThrottleMs = 800;
bool   gTradeTxnPushPending = false;
ulong  gTradeTxnPushPendingSinceMs = 0;

//--- Multiple signals-per-symbol toggle (default OFF)
bool   gAllowMultipleSignalsPerSymbol = false;
bool   gAllowMultiPrinted = false;

//--- Time-based Trade Scheduler (Pause / Resume EA)
// Uses broker server time (TimeCurrent). 0=Sunday..6=Saturday.
bool   gSchedulerActive = false;
int    gSchedulerPauseDay = -1;
string gSchedulerPauseTime = "";   // "HH:MM"
int    gSchedulerResumeDay = -1;
string gSchedulerResumeTime = "";  // "HH:MM"
bool   gSchedulerPaused = false;    // persisted across restarts
string gSchedulerLastPauseDate = "";  // YYYYMMDD
string gSchedulerLastResumeDate = ""; // YYYYMMDD
bool   gSchedulerPrinted = false;

//--- Change tracking
string gLastLotMode      = "";
double gLastCustomLot    = -1.0;
string gLastSymbolMode   = "";
int    gLastSymbolCount  = -1;
string gLastMWMode       = "";
int    gLastMWCount      = -1;
bool   gSymbolSyncDone   = false;
bool   gSymbolWaitingAnnounced = false;
ulong  gLastBackendRefresh = 0;
ulong  gLastHeartbeatAttemptMs = 0;

//--- Internal state
struct Signal
{
   string type;          // BUY, SELL, BUY_LIMIT, SELL_STOP, etc
   string pair;          // symbol string (e.g. XAUUSD)
   double entry;         // primary entry price (TP1)
   bool   hasEntry;
   double entry2;        // secondary entry price (TP2)
   bool   hasEntry2;     // true if entry range detected
   double sls[];         // stop losses (multiple: sl1, sl2, sl3...)
   int    sl_indices[];  // indices for SL updates (-1 = apply to all)
   bool   hasSL;         // true if at least one SL is present
   double tps[];         // take profits
   int    tp_indices[];  // indices for TP updates (-1 = apply to all)
   string tp_errors[];   // messages about skipped/duplicate TP parsing
   bool   updateAll_SL;  // true if "sl:" without index (apply to all)
   bool   updateAll_TP;  // true if "tp:" without index (apply to all)
};

struct SignalTradeMap
{
   string signal_id;
   ulong  tickets[];
};

SignalTradeMap gSignalTrades[];
string symbol_aliases[][2];
CTrade trade;
ulong  last_poll = 0;
int    gMagicNumber = 123456; // Magic number for order identification

//--- Forward declarations
string GetTradeCommand();
void ExecuteTradeCommand(const string commandJson);
void ExecuteBreakeven(const string scope, const string symbol, const string direction, const string signal_id="", const string group_id="");
void ExecuteCloseTrade(const string scope, const string symbol, const string direction, const string signal_id="", const string group_id="", const bool require_exact=false);
void ExecuteSecureHalf(const string scope, const string symbol, const string direction, const string signal_id="", bool apply_breakeven=false, const string group_id="");

// HTTP diagnostics helpers
string FBStripUrlQuery(const string url);
string FBHttpBodySnippet(const string body, const int maxLen);
string FBHttpDiagSummary();

string SchedulerFileName();
void FBSchedulerLoadState();
void FBSchedulerSaveState();
string FBNowDateStamp();
string FBNowHHMM();
void FBSchedulerCloseAllEATradesAndPendings();
void FBSchedulerTick();

//+------------------------------------------------------------------+
//| Utility helpers                                                  |
//+------------------------------------------------------------------+
bool IsDigitOrDot(ushort ch)
{
   return((ch >= '0' && ch <= '9') || ch == '.');
}

void TrimString(string &text)
{
   StringTrimLeft(text);
   StringTrimRight(text);
}

string StringLower(const string text)
{
   string tmp = text;
   StringToLower(tmp);
   return tmp;
}

uint HashStringFNV1a32(const string text)
{
   uint hash = 2166136261;
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(text, i);
      hash ^= (uint)ch;
      hash *= 16777619;
   }
   return hash;
}

string GetTerminalId()
{
   string base =
      TerminalInfoString(TERMINAL_PATH) + "|" +
      TerminalInfoString(TERMINAL_NAME);
   return StringFormat("%u", HashStringFNV1a32(base));
}

bool CommentMatchesSignalIdTruncSafe(const string comment, const string signal_id)
{
   if(StringLen(comment) == 0 || StringLen(signal_id) == 0)
      return false;

   if(StringFind(comment, signal_id) != -1)
      return true;

   int colonPos = StringFind(signal_id, ":");
   if(colonPos <= 0)
      return false;

   string signalBase = StringSubstr(signal_id, 0, colonPos);
   string signalSuffix = StringSubstr(signal_id, colonPos + 1);
   if(StringLen(signalSuffix) == 0)
      return false;

   // New format token: |s{base}:{suffix}
   // We require the (possibly truncated) suffix present in the comment to be a prefix of the true suffix.
   // This avoids accidentally matching other signals from the same group/chat when comments are truncated.
   string sToken = StringFormat("|s%s:", signalBase);
   int sPos = StringFind(comment, sToken);
   if(sPos != -1)
   {
      int suffixStart = sPos + StringLen(sToken);
      string commentSuffix = StringSubstr(comment, suffixStart);
      int endPipe = StringFind(commentSuffix, "|");
      if(endPipe != -1)
         commentSuffix = StringSubstr(commentSuffix, 0, endPipe);

      if(StringLen(commentSuffix) > 0 && StringFind(signalSuffix, commentSuffix) == 0)
         return true;
   }

   // Alternate compact token: s{base}:{suffix} (no leading pipe)
   string sToken2 = StringFormat("s%s:", signalBase);
   int sPos2 = StringFind(comment, sToken2);
   if(sPos2 != -1)
   {
      int suffixStart2 = sPos2 + StringLen(sToken2);
      string commentSuffix2 = StringSubstr(comment, suffixStart2);
      int endPipe2 = StringFind(commentSuffix2, "|");
      if(endPipe2 != -1)
         commentSuffix2 = StringSubstr(commentSuffix2, 0, endPipe2);

      if(StringLen(commentSuffix2) > 0 && StringFind(signalSuffix, commentSuffix2) == 0)
         return true;
   }

   // Old format token: sig_{base}:{suffix}
   string sTokenOld = StringFormat("sig_%s:", signalBase);
   int sPosOld = StringFind(comment, sTokenOld);
   if(sPosOld != -1)
   {
      int suffixStartOld = sPosOld + StringLen(sTokenOld);
      int len = StringLen(comment);
      int end = suffixStartOld;
      while(end < len)
      {
         int ch = StringGetCharacter(comment, end);
         if(ch == '_' || ch == ' ' || ch == '|' || ch == ',' || ch == ';' || ch == ')' || ch == '(')
            break;
         end++;
      }
      string commentSuffixOld = StringSubstr(comment, suffixStartOld, end - suffixStartOld);
      if(StringLen(commentSuffixOld) > 0 && StringFind(signalSuffix, commentSuffixOld) == 0)
         return true;
   }

   return false;
}

bool IsValidFlamebotId(const string user_id)
{
   if(StringLen(user_id) < 3)
      return(false);
   return(StringFind(user_id, "FB-") == 0);
}

string AuthFileName()
{
   // Per-terminal auth file (prevents sharing credentials across different terminals)
   return StringFormat("auth_%s.json", gTerminalId);
}

string SchedulerFileName()
{
   // Per-terminal scheduler state file (persists pause across EA restarts)
   return StringFormat("scheduler_%s.json", gTerminalId);
}

// --- Minimal credential obfuscation (NOT encryption) -------------------------
// Goal: avoid storing raw credentials in plaintext files.
// Format: obf:<hex>
string FBHexEncode(const string s)
{
   string out = "";
   for(int i = 0; i < StringLen(s); i++)
   {
      int v = (int)StringGetCharacter(s, i);
      v = v ^ 0x5A;
      out += StringFormat("%02X", v & 0xFF);
   }
   return out;
}

string FBHexDecode(const string hex)
{
   string out = "";
   int n = StringLen(hex);
   if(n < 2)
      return "";
   for(int i = 0; i + 1 < n; i += 2)
   {
      string b = StringSubstr(hex, i, 2);
      int v = (int)StringToInteger("0x" + b);
      v = v ^ 0x5A;
      out += StringFormat("%c", v);
   }
   return out;
}

string FBProtect(const string s)
{
   if(s == "")
      return "";
   return "obf:" + FBHexEncode(s);
}

string FBUnprotect(const string s)
{
   if(StringFind(s, "obf:") == 0)
      return FBHexDecode(StringSubstr(s, 4));
   return s;
}

void SaveAuth(const string user_id, const string license_key)
{
   int handle = FileOpen(AuthFileName(), FILE_WRITE);
   if(handle != INVALID_HANDLE)
   {
      string json = "{ \"terminal_id\": \"" + gTerminalId + "\", \"user_id\": \"" + FBProtect(user_id) + "\", \"license_key\": \"" + FBProtect(license_key) + "\" }";
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

bool LoadAuth(string &user_id, string &license_key)
{
   // Never read legacy FILE_COMMON auth (privacy). If it exists, delete it.
   if(FileIsExist("auth.json", FILE_COMMON))
      FileDelete("auth.json", FILE_COMMON);

   if(!FileIsExist(AuthFileName()))
      return(false);

   int handle = FileOpen(AuthFileName(), FILE_READ);
   if(handle == INVALID_HANDLE)
      return(false);

   string json = FileReadString(handle);
   FileClose(handle);

   int pos0 = StringFind(json, "\"terminal_id\"");
   int pos1 = StringFind(json, "\"user_id\"");
   int pos2 = StringFind(json, "\"license_key\"");
   if(pos0 == -1 || pos1 == -1 || pos2 == -1)
      return(false);

   int start = StringFind(json, "\"", pos0 + 13) + 1;
   int end   = StringFind(json, "\"", start);
   string tid = StringSubstr(json, start, end - start);
   if(tid != gTerminalId)
   {
      ClearSavedAuth();
      user_id = "";
      license_key = "";
      return(false);
   }

   start = StringFind(json, "\"", pos1 + 10) + 1;
   end   = StringFind(json, "\"", start);
   user_id   = FBUnprotect(StringSubstr(json, start, end - start));

   start = StringFind(json, "\"", pos2 + 15) + 1;
   end   = StringFind(json, "\"", start);
   license_key = FBUnprotect(StringSubstr(json, start, end - start));
   if(!IsValidFlamebotId(user_id))
   {
      ClearSavedAuth();
      user_id = "";
      license_key = "";
      return(false);
   }
   return(true);
}

void ClearSavedAuth()
{
   // Delete per-terminal auth
   FileDelete(AuthFileName());
   // Also delete legacy common auth if present
   if(FileIsExist("auth.json", FILE_COMMON))
      FileDelete("auth.json", FILE_COMMON);
}

void FBSchedulerSaveState()
{
   int handle = FileOpen(SchedulerFileName(), FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return;

   string json = "{ \"terminal_id\": \"" + gTerminalId + "\", \"paused\": \"" + (gSchedulerPaused ? "1" : "0") + "\", \"last_pause_date\": \"" + gSchedulerLastPauseDate + "\", \"last_resume_date\": \"" + gSchedulerLastResumeDate + "\" }";
   FileWriteString(handle, json);
   FileClose(handle);
}

void FBSchedulerLoadState()
{
   if(!FileIsExist(SchedulerFileName()))
      return;

   int handle = FileOpen(SchedulerFileName(), FILE_READ);
   if(handle == INVALID_HANDLE)
      return;

   string json = FileReadString(handle);
   FileClose(handle);

   string tid = "";
   if(!ExtractJsonString(json, "terminal_id", tid) || tid != gTerminalId)
   {
      FileDelete(SchedulerFileName());
      return;
   }

   string pausedStr = "";
   if(ExtractJsonString(json, "paused", pausedStr))
   {
      StringToLower(pausedStr);
      gSchedulerPaused = (pausedStr == "1" || pausedStr == "true" || pausedStr == "yes");
   }
   string d = "";
   if(ExtractJsonString(json, "last_pause_date", d))
      gSchedulerLastPauseDate = d;
   d = "";
   if(ExtractJsonString(json, "last_resume_date", d))
      gSchedulerLastResumeDate = d;
}

string FBNowDateStamp()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

string FBNowHHMM()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return StringFormat("%02d:%02d", dt.hour, dt.min);
}

string FBDowName(const int dow)
{
   switch(dow)
   {
      case 0: return "Sunday";
      case 1: return "Monday";
      case 2: return "Tuesday";
      case 3: return "Wednesday";
      case 4: return "Thursday";
      case 5: return "Friday";
      case 6: return "Saturday";
   }
   return "N/A";
}

void FBSchedulerCloseAllEATradesAndPendings()
{
   int closed = 0;
   int deleted = 0;

   int ptotal = PositionsTotal();
   for(int i = ptotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         continue;
      if(trade.PositionClose(ticket))
         closed++;
   }

   int ototal = OrdersTotal();
   for(int oi = ototal - 1; oi >= 0; oi--)
   {
      ulong oticket = OrderGetTicket(oi);
      if(oticket == 0)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != gMagicNumber)
         continue;
      if(trade.OrderDelete(oticket))
         deleted++;
   }

   FBLogInfo(StringFormat("[FlameBot][INFO] Scheduler pause cleanup | closed_positions=%d | deleted_pendings=%d", closed, deleted));
}

void FBSchedulerTick()
{
   // If scheduler is turned OFF, ensure we are not stuck in paused state.
   if(!gSchedulerActive)
   {
      if(gSchedulerPaused)
      {
         gSchedulerPaused = false;
         gSchedulerLastResumeDate = FBNowDateStamp();
         FBSchedulerSaveState();
         FBLogInfo("[FlameBot][INFO] Scheduler disabled: EA unlocked (trading enabled)");
      }
      return;
   }

   if(gSchedulerPauseDay < 0 || gSchedulerResumeDay < 0)
      return;
   if(StringLen(gSchedulerPauseTime) < 4 || StringLen(gSchedulerResumeTime) < 4)
      return;

   // Parse configured HH:MM times into minutes-since-midnight
   int pauseMinutes = -1;
   int resumeMinutes = -1;
   {
      int sep = StringFind(gSchedulerPauseTime, ":");
      if(sep > 0)
      {
         int hh = (int)StringToInteger(StringSubstr(gSchedulerPauseTime, 0, sep));
         int mm = (int)StringToInteger(StringSubstr(gSchedulerPauseTime, sep + 1));
         if(hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59)
            pauseMinutes = hh * 60 + mm;
      }
      sep = StringFind(gSchedulerResumeTime, ":");
      if(sep > 0)
      {
         int hh2 = (int)StringToInteger(StringSubstr(gSchedulerResumeTime, 0, sep));
         int mm2 = (int)StringToInteger(StringSubstr(gSchedulerResumeTime, sep + 1));
         if(hh2 >= 0 && hh2 <= 23 && mm2 >= 0 && mm2 <= 59)
            resumeMinutes = hh2 * 60 + mm2;
      }
   }
   if(pauseMinutes < 0 || resumeMinutes < 0)
      return;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int dow = dt.day_of_week;
   string hhmm = StringFormat("%02d:%02d", dt.hour, dt.min);
   string today = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);

   int nowMinutes = dt.hour * 60 + dt.min;

   // Weekly window model:
   // pause at (PauseDay, PauseTime) and remain paused until (ResumeDay, ResumeTime), wrapping over week.
   int nowW    = dow * 1440 + nowMinutes;
   int pauseW  = gSchedulerPauseDay * 1440 + pauseMinutes;
   int resumeW = gSchedulerResumeDay * 1440 + resumeMinutes;

   bool shouldBePaused = false;
   if(pauseW == resumeW)
   {
      // Zero-length window => never paused (safer default)
      shouldBePaused = false;
   }
   else if(pauseW < resumeW)
   {
      shouldBePaused = (nowW >= pauseW && nowW < resumeW);
   }
   else
   {
      // Wraps across end-of-week
      shouldBePaused = (nowW >= pauseW || nowW < resumeW);
   }

   if(shouldBePaused)
   {
      if(!gSchedulerPaused)
      {
         FBLogInfo(StringFormat("[FlameBot][INFO] Scheduler window: EA locked (trading paused) | Now=%s @ %s | window=%s @ %s -> %s @ %s | closing EA trades + pausing entries",
                               FBDowName(dow), hhmm,
                               FBDowName(gSchedulerPauseDay), gSchedulerPauseTime,
                               FBDowName(gSchedulerResumeDay), gSchedulerResumeTime));
         FBSchedulerCloseAllEATradesAndPendings();
         gSchedulerPaused = true;
         gSchedulerLastPauseDate = today;
         FBSchedulerSaveState();
      }
      return;
   }

   if(gSchedulerPaused)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Scheduler window: EA unlocked (trading enabled) | Now=%s @ %s | window=%s @ %s -> %s @ %s",
                            FBDowName(dow), hhmm,
                            FBDowName(gSchedulerPauseDay), gSchedulerPauseTime,
                            FBDowName(gSchedulerResumeDay), gSchedulerResumeTime));
      gSchedulerPaused = false;
      gSchedulerLastResumeDate = today;
      FBSchedulerSaveState();
   }
}

bool ExtractJsonString(const string json, const string key, string &value)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos == -1)
      return(false);

   pos = StringFind(json, ":", pos);
   if(pos == -1)
      return(false);

   int len = StringLen(json);
   pos++;
   while(pos < len)
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch == ' ')
         pos++;
      else
         break;
   }

   if(pos >= len)
      return(false);

   if(StringGetCharacter(json, pos) == '"')
   {
      int start = pos + 1;
      int end = StringFind(json, "\"", start);
      if(end == -1)
         return(false);
      value = StringSubstr(json, start, end - start);
      return(true);
   }

   int endPos = pos;
   while(endPos < len && StringGetCharacter(json, endPos) != ',' && StringGetCharacter(json, endPos) != '}')
      endPos++;

   value = StringSubstr(json, pos, endPos - pos);
   TrimString(value);
   return(true);
}

bool ExtractJsonArrayStrings(const string json, const string key, string &values[])
{
   ArrayResize(values, 0);
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos == -1)
      return(false);

   pos = StringFind(json, "[", pos);
   int end = StringFind(json, "]", pos);
   if(pos == -1 || end == -1 || end <= pos)
      return(false);

   string slice = StringSubstr(json, pos + 1, end - pos - 1);
   string rawItems[];
   int count = StringSplit(slice, ',', rawItems);
   for(int i = 0; i < count; i++)
   {
      string item = rawItems[i];
      TrimString(item);
      if(StringLen(item) >= 2 && StringGetCharacter(item, 0) == '"' && StringGetCharacter(item, StringLen(item) - 1) == '"')
         item = StringSubstr(item, 1, StringLen(item) - 2);
      if(item != "")
      {
         int sz = ArraySize(values);
         ArrayResize(values, sz + 1);
         values[sz] = item;
      }
   }
   return(ArraySize(values) > 0);
}

bool ExtractJsonObject(const string json, const string key, string &objJson)
{
   objJson = "";
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos == -1)
      return(false);

   pos = StringFind(json, ":", pos);
   if(pos == -1)
      return(false);
   pos++;

   int len = StringLen(json);
   while(pos < len)
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch == ' ')
         pos++;
      else
         break;
   }
   if(pos >= len)
      return(false);

   if(StringGetCharacter(json, pos) != '{')
      return(false);

   int start = pos;
   int depth = 0;
   for(int i = pos; i < len; i++)
   {
      ushort ch = StringGetCharacter(json, i);
      if(ch == '{')
         depth++;
      else if(ch == '}')
      {
         depth--;
         if(depth == 0)
         {
            objJson = StringSubstr(json, start, i - start + 1);
            return(true);
         }
      }
   }
   return(false);
}

string FBJsonEscape(const string s)
{
   string out = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch == '\\')
         out += "\\\\";
      else if(ch == '"')
         out += "\\\"";
      else if(ch == '\r')
         out += "\\r";
      else if(ch == '\n')
         out += "\\n";
      else if(ch == '\t')
         out += "\\t";
      else
         out += CharToString((uchar)ch);
   }
   return(out);
}

string FBJsonPriceOrNull(const double price, const int digits)
{
   if(price <= 0.0)
      return("null");
   return(DoubleToString(price, digits));
}

string BuildOpenPositionsJson()
{
   string out = "[";
   bool first = true;

   int ptotal = PositionsTotal();
   for(int i = 0; i < ptotal; i++)
   {
      ulong pticket = PositionGetTicket(i);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side = (ptype == POSITION_TYPE_BUY) ? "buy" : "sell";
      string comment = PositionGetString(POSITION_COMMENT);
      string sig = ExtractSignalIdFromComment(comment);
      string gid = ExtractGroupIdFromComment(comment);

      double pl = 0.0;
      // POSITION_COMMISSION is deprecated in newer MT5 builds.
      // Use profit+swap for a stable live P/L number.
      pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      string item = "{";
      item += "\"ticket\":" + IntegerToString((long)pticket);
      item += ",\"symbol\":\"" + FBJsonEscape(sym) + "\"";
      item += ",\"kind\":\"active\"";
      item += ",\"side\":\"" + side + "\"";
      item += ",\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2);
      item += ",\"price_open\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), digits);
      item += ",\"sl\":" + FBJsonPriceOrNull(PositionGetDouble(POSITION_SL), digits);
      item += ",\"tp\":" + FBJsonPriceOrNull(PositionGetDouble(POSITION_TP), digits);
      item += ",\"profit\":" + DoubleToString(pl, 2);
      item += ",\"magic\":" + IntegerToString((long)PositionGetInteger(POSITION_MAGIC));
      item += ",\"comment\":\"" + FBJsonEscape(comment) + "\"";
      item += ",\"signal_id\":\"" + FBJsonEscape(sig) + "\"";
      item += ",\"group_id\":\"" + FBJsonEscape(gid) + "\"";
      item += ",\"time_open\":" + IntegerToString((long)PositionGetInteger(POSITION_TIME));
      item += "}";

      if(!first)
         out += ",";
      out += item;
      first = false;
   }

   int ototal = OrdersTotal();
   for(int j = 0; j < ototal; j++)
   {
      ulong oticket = OrderGetTicket(j);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != gMagicNumber)
         continue;

      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isPending = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT || otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_STOP || otype == ORDER_TYPE_BUY_STOP_LIMIT || otype == ORDER_TYPE_SELL_STOP_LIMIT);
      if(!isPending)
         continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      string side = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_BUY_STOP_LIMIT) ? "buy" : "sell";
      string comment = OrderGetString(ORDER_COMMENT);
      string sig = ExtractSignalIdFromComment(comment);
      string gid = ExtractGroupIdFromComment(comment);

      double pl = 0.0;

      string item = "{";
      item += "\"ticket\":" + IntegerToString((long)oticket);
      item += ",\"symbol\":\"" + FBJsonEscape(sym) + "\"";
      item += ",\"kind\":\"pending\"";
      item += ",\"side\":\"" + side + "\"";
      item += ",\"order_type\":" + IntegerToString((int)otype);
      item += ",\"volume\":" + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2);
      item += ",\"price_open\":" + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), digits);
      item += ",\"sl\":" + FBJsonPriceOrNull(OrderGetDouble(ORDER_SL), digits);
      item += ",\"tp\":" + FBJsonPriceOrNull(OrderGetDouble(ORDER_TP), digits);
      item += ",\"profit\":" + DoubleToString(pl, 2);
      item += ",\"magic\":" + IntegerToString((long)OrderGetInteger(ORDER_MAGIC));
      item += ",\"comment\":\"" + FBJsonEscape(comment) + "\"";
      item += ",\"signal_id\":\"" + FBJsonEscape(sig) + "\"";
      item += ",\"group_id\":\"" + FBJsonEscape(gid) + "\"";
      item += ",\"time_open\":" + IntegerToString((long)OrderGetInteger(ORDER_TIME_SETUP));
      item += "}";

      if(!first)
         out += ",";
      out += item;
      first = false;
   }

   out += "]";
   return(out);
}

bool FBCommandUidProcessed(const string uid)
{
   if(StringLen(uid) == 0)
      return(false);
   string key = "FB_CMD_" + uid;
   return(GlobalVariableCheck(key));
}

void FBMarkCommandUidProcessed(const string uid)
{
   if(StringLen(uid) == 0)
      return;
   string key = "FB_CMD_" + uid;
   GlobalVariableSet(key, (double)TimeCurrent());
}

string BuildEndpointUrl(const string path)
{
   string base = InpServerUrl;
   
   // Remove query string if present
   int q = StringFind(base, "?");
   if(q != -1)
      base = StringSubstr(base, 0, q);
   
   // Ensure base ends with / and path doesn't start with /
   if(StringLen(base) > 0 && StringGetCharacter(base, StringLen(base) - 1) != '/')
      base += "/";
   
   return(base + path);
}

//--- Symbol aliases -------------------------------------------------
int AddAlias(int idx, const string alias, const string symbol)
{
   if(alias == "" || symbol == "")
      return idx;

   string key = alias;
   StringToLower(key);

   ArrayResize(symbol_aliases, idx + 1);
   symbol_aliases[idx][0] = key;
   symbol_aliases[idx][1] = symbol;
   return(idx + 1);
}


void BuildSymbolAliases()
{
   ArrayResize(symbol_aliases, 0);
   int idx = 0;

   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      string lower = name;
      StringToLower(lower);

      idx = AddAlias(idx, name, name);
      idx = AddAlias(idx, lower, name);
      idx = AddAlias(idx, "#" + lower, name);

      string compact = name;
      StringReplace(compact, "/", "");
      string compactLower = compact;
      StringToLower(compactLower);
      idx = AddAlias(idx, compactLower, name);
   }

   string nick[][2] =
   {
      {"gold", "XAUUSD"}, {"silver", "XAGUSD"}, {"oil", "WTIUSD"}, {"brent", "UKOIL"},
      {"btc", "BTCUSD"},  {"bitcoin", "BTCUSD"}, {"eth", "ETHUSD"}, {"ethereum", "ETHUSD"},
      {"euro", "EURUSD"}, {"cable", "GBPUSD"}, {"jpy", "USDJPY"},   {"aussie", "AUDUSD"},
      {"kiwi", "NZDUSD"}, {"swissy", "USDCHF"}, {"cad", "USDCAD"},
      {"nas", "NAS100"},  {"nasdaq", "NAS100"}, {"dow", "US30"},    {"dj30", "US30"},
      {"spx", "SPX500"},  {"sp500", "SPX500"}, {"s&p", "SPX500"},   {"dax", "DE30"},
      {"ftse", "FTSE100"},{"nikkei", "JP225"}
   };

   int nickCount = ArrayRange(nick, 0);
   for(int i = 0; i < nickCount; i++)
   {
      string n = nick[i][0];
      string lower = n;
      StringToLower(lower);
      idx = AddAlias(idx, lower, nick[i][1]);
      idx = AddAlias(idx, "#" + lower, nick[i][1]);
   }

   ArrayResize(symbol_aliases, idx);
   FBLogInfo(StringFormat("[FlameBot][INFO] Symbol aliases built: %d", idx));
}

string FindSymbolByAlias(string alias)
{
   string key = alias;
   StringToLower(key);

   int total = ArrayRange(symbol_aliases, 0);
   for(int i = 0; i < total; i++)
   {
      if(symbol_aliases[i][0] == key)
         return(symbol_aliases[i][1]);
   }
   return("");
}

bool IsSymbolBannedKeyword(const string s)
{
   string banned[] = {"buy","sell","limit","stop","entry","sl","tp","long","short","up","down"};
   for(int i = 0; i < ArraySize(banned); i++)
   {
      if(s == banned[i])
         return(true);
   }
   return(false);
}

string MatchSymbol(string input_symbol)
{
   if(input_symbol == "")
      return("");

   string cleaned = input_symbol;
   StringToLower(cleaned);
   StringReplace(cleaned, "#", "");
   StringReplace(cleaned, "/", "");
   StringReplace(cleaned, "_", "");
   StringReplace(cleaned, " ", "");
   StringReplace(cleaned, "\r", "");
   StringReplace(cleaned, "\n", "");

   if(IsSymbolBannedKeyword(cleaned))
      return("");

   string aliasSym = FindSymbolByAlias(cleaned);
   if(aliasSym != "")
      return(aliasSym);

   string up = cleaned;
   StringToUpper(up);
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      string tmp = name;
      StringToUpper(tmp);
      if(tmp == up)
         return(name);
   }

   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      string upName = name;
      StringToUpper(upName);
      if(StringFind(upName, up) != -1)
      {
         FBLogInfo(StringFormat("[FlameBot][INFO] Fuzzy matched '%s' to '%s'", up, name));
         return(name);
      }
   }

   return("");
}

// Extract a tradable symbol from free-form text using existing fuzzy matching
string ExtractSymbolFromText(const string text)
{
   string lines[];
   int lineCount = StringSplit(text, '\n', lines);
   for(int i = 0; i < lineCount; i++)
   {
      string line = lines[i];
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "")
         continue;

      string words[];
      int wc = StringSplit(line, ' ', words);
      for(int w = 0; w < wc; w++)
      {
         string word = words[w];
         StringTrimLeft(word);
         StringTrimRight(word);
         string sanitized = word;
         StringReplace(sanitized, ":", "");
         StringReplace(sanitized, "@", "");
         StringReplace(sanitized, "#", "");
         string compact = sanitized;
         StringReplace(compact, "/",
         "");

         string sym = FindSymbolByAlias(sanitized);
         if(sym == "" && compact != "")
            sym = FindSymbolByAlias(compact);
         // Normalize alias to actual broker symbol via fuzzy MatchSymbol
         if(sym != "")
         {
            string brokerSym = MatchSymbol(sym);
            if(brokerSym != "")
               return(brokerSym);
            return(sym);
         }
         sym = MatchSymbol(sanitized);
         if(sym == "" && compact != "")
            sym = MatchSymbol(compact);
         if(sym != "")
            return(sym);
      }
   }

   // Fallback: scan all tokens when lines are not informative
   string fallback = text;
   StringToLower(fallback);
   StringReplace(fallback, "\r", " ");
   StringReplace(fallback, "\n", " ");
   StringReplace(fallback, ":", " ");
   StringReplace(fallback, ",", " ");
   StringReplace(fallback, ";", " ");

   string wordsAll[];
   int wcAll = StringSplit(fallback, ' ', wordsAll);
   for(int i2 = 0; i2 < wcAll; i2++)
   {
      string w = wordsAll[i2];
      StringTrimLeft(w);
      StringTrimRight(w);
      if(StringLen(w) >= 3 && !IsSymbolBannedKeyword(w))
      {
         string m = MatchSymbol(w);
         if(m != "")
            return(m);
      }
   }
   return("");
}


//--- TP helpers -----------------------------------------------------
void AddUniqueTP(Signal &signal, double tp_price, const string reason)
{
   // Allow tp_price = 0.0 for "tp: open" (no TP set)
   if(tp_price < 0.0)
      return;

   // Allow duplicate TPs - each TP gets its own trade position
   int sz = ArraySize(signal.tps);
   ArrayResize(signal.tps, sz + 1);
   signal.tps[sz] = tp_price;
}

bool ExtractTPValueFromToken(const string token, double &value)
{
   string text = token;
   StringToLower(text);

   // Recognize "open" as valid (create trade with no TP)
   // This function is only called in TP keyword context, so "open" here means TP=open
   if(StringFind(text, "open") != -1)
   {
      value = 0.0;
      FBLogDebug("[FlameBot][DEBUG] Parsed tp: open -> 0.0");
      return true; // Create trade with TP=0
   }

   int len   = StringLen(text);
   int start = 0;

   int tpPos = StringFind(text, "tp");
   if(tpPos != -1)
      start = tpPos + 2;

   int lastDelim = -1;
   string delims[] = {":", "@", "=", "-"};
   for(int d = 0; d < ArraySize(delims); d++)
   {
      int pos = StringFind(text, delims[d]);
      while(pos != -1)
      {
         lastDelim = pos;
         pos = StringFind(text, delims[d], pos + 1);
      }
   }

   if(lastDelim != -1 && lastDelim + 1 > start)
      start = lastDelim + 1;

   string digits = "";
   bool   started = false;

   for(int i = start; i < len; i++)
   {
      ushort ch = StringGetCharacter(text, i);
      if(IsDigitOrDot(ch))
      {
         digits += CharToString((uchar)ch);
         started = true;
      }
      else if(started)
         break;
   }

   if(digits == "" || StringLen(digits) < 3)
      return(false);

   value = StringToDouble(digits);
   return(value > 0.0);
}

//--- Number parsing --------------------------------------------------
bool FindNumberAfterKeyword(const string text, const string keyword, double &value)
{
   string lower = text;
   StringToLower(lower);
   string key = keyword;
   StringToLower(key);

   int pos = StringFind(lower, key);
   if(pos == -1)
      return(false);

   pos += StringLen(key);
   int len = StringLen(lower);

   while(pos < len)
   {
      ushort ch = StringGetCharacter(lower, pos);
      if(ch == ' ' || ch == ':' || ch == '-' || ch == '@')
         pos++;
      else
         break;
   }

   string numStr = "";
   while(pos < len)
   {
      ushort ch = StringGetCharacter(lower, pos);
      if(IsDigitOrDot(ch))
      {
         numStr += CharToString((uchar)ch);
         pos++;
      }
      else
         break;
   }

   if(numStr == "")
      return(false);

   value = StringToDouble(numStr);
   return(true);
}

bool FindNumberAfterAt(const string text, double &value)
{
   string lower = text;
   StringToLower(lower);
   int len = StringLen(lower);

   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(lower, i);
      if(ch == '@')
      {
         int pos = i + 1;
         string numStr = "";
         while(pos < len)
         {
            ushort c = StringGetCharacter(lower, pos);
            if(IsDigitOrDot(c))
            {
               numStr += CharToString((uchar)c);
               pos++;
            }
            else
               break;
         }
         if(numStr != "")
         {
            value = StringToDouble(numStr);
            return(true);
         }
      }
   }
   return(false);
}

int ExtractAllNumbers(const string text, double &nums[])
{
   ArrayResize(nums, 0);
   string lower = text;
   StringToLower(lower);
   int len = StringLen(lower);
   string token = "";

   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(lower, i);
      if(IsDigitOrDot(ch))
      {
         token += CharToString((uchar)ch);
      }
      else
      {
         if(token != "" && StringLen(token) >= 3)
         {
            double val = StringToDouble(token);
            int size = ArraySize(nums);
            ArrayResize(nums, size + 1);
            nums[size] = val;
         }
         token = "";
      }
   }
   if(token != "" && StringLen(token) >= 3)
   {
      double val = StringToDouble(token);
      int size = ArraySize(nums);
      ArrayResize(nums, size + 1);
      nums[size] = val;
   }
   return(ArraySize(nums));
}

double PriceMatchEpsilonForSymbol(const string symbol)
{
   // Used to decide whether two prices are effectively the same.
   // Must be tight enough for FX (e.g., 1.9544 vs 1.95965 are NOT the same).
   double point = 0.0;
   if(StringLen(symbol) > 0)
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;
   return(MathMax(point * 2.0, 0.0000001));
}

//+------------------------------------------------------------------+
//| Parsing                                                          |
//+------------------------------------------------------------------+
bool ParseSignal(const string text, Signal &signal)
{
   signal.type = "";
   signal.pair = "";
   signal.entry = 0;
   signal.hasEntry = false;
   signal.entry2 = 0;
   signal.hasEntry2 = false;
   ArrayResize(signal.sls, 0);
   signal.hasSL = false;
   ArrayResize(signal.tps, 0);
   ArrayResize(signal.tp_errors, 0);

   string textLower = text;
   StringToLower(textLower);

   string lines[];
   int lineCount = StringSplit(text, '\n', lines);
   
   // 🔥 CRITICAL: PARSE ENTRY RANGE FROM HEADER LINE FIRST (before ANY number extraction)
   // Format: "SYMBOL BUY/SELL price1 - price2" or "SYMBOL BUY/SELL price1-price2"
   // This MUST happen before ExtractAllNumbers to prevent entry prices from becoming TPs
   if(lineCount > 0)
   {
      string firstLine = lines[0];
      StringTrimLeft(firstLine);
      StringTrimRight(firstLine);
      
      // Check if first line contains dash (entry range indicator)
      if(StringFind(firstLine, "-") != -1)
      {
         // Extract all numbers from first line only
         double headerNums[];
         int headerNumCount = ExtractAllNumbers(firstLine, headerNums);
         
         // Look for pattern: consecutive numbers with dash between them
         for(int h = 0; h < headerNumCount - 1; h++)
         {
            double n1 = headerNums[h];
            double n2 = headerNums[h + 1];
            
            // Build search patterns - try multiple decimal formats
            string patterns1[];
            ArrayResize(patterns1, 3);
            patterns1[0] = DoubleToString(n1, 0);  // No decimals
            patterns1[1] = DoubleToString(n1, 2);  // 2 decimals
            patterns1[2] = DoubleToString(n1, 5);  // 5 decimals
            
            string patterns2[];
            ArrayResize(patterns2, 3);
            patterns2[0] = DoubleToString(n2, 0);
            patterns2[1] = DoubleToString(n2, 2);
            patterns2[2] = DoubleToString(n2, 5);
            
            // Try to find these numbers with dash between them
            bool foundRange = false;
            for(int p1 = 0; p1 < 3 && !foundRange; p1++)
            {
               for(int p2 = 0; p2 < 3 && !foundRange; p2++)
               {
                  int pos1 = StringFind(firstLine, patterns1[p1]);
                  int pos2 = StringFind(firstLine, patterns2[p2]);
                  
                  if(pos1 != -1 && pos2 != -1 && pos2 > pos1)
                  {
                     string between = StringSubstr(firstLine, pos1 + StringLen(patterns1[p1]), pos2 - pos1 - StringLen(patterns1[p1]));
                     StringTrimLeft(between);
                     StringTrimRight(between);
                     
                     if(between == "-" || between == " -" || between == "- " || between == " - ")
                     {
                        signal.entry = n1;
                        signal.hasEntry = true;
                        signal.entry2 = n2;
                        signal.hasEntry2 = true;
                        foundRange = true;
                        FBLogInfo(StringFormat("[FlameBot][INFO] Entry range detected from header: %.5f - %.5f", n1, n2));
                     }
                  }
               }
            }
            
            if(foundRange)
               break;
         }
      }
   }
   
   // Now parse symbol (entry prices are already captured if present)
   for(int i = 0; i < lineCount && signal.pair == ""; i++)
   {
      string line = lines[i];
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "")
         continue;

      string words[];
      int wc = StringSplit(line, ' ', words);
      for(int w = 0; w < wc; w++)
      {
         string word = words[w];
         StringTrimLeft(word);
         StringTrimRight(word);
         string sanitized = word;
         StringReplace(sanitized, ":", "");
         StringReplace(sanitized, "@", "");
         StringReplace(sanitized, "#", "");
         string compact = sanitized;
         StringReplace(compact, "/", "");

         string sym = FindSymbolByAlias(sanitized);
         if(sym == "" && compact != "")
            sym = FindSymbolByAlias(compact);

         if(sym == "")
            sym = MatchSymbol(sanitized);
         if(sym == "" && compact != "")
            sym = MatchSymbol(compact);

         if(sym != "")
         {
            signal.pair = sym;
            break;
         }
      }
   }

   string buys[]  = {"buy", "long", "up"};
   string sells[] = {"sell", "short", "down"};

   for(int i = 0; i < ArraySize(buys) && signal.type == ""; i++)
   {
      if(StringFind(textLower, buys[i]) != -1)
         signal.type = "BUY";
   }

   for(int i = 0; i < ArraySize(sells) && signal.type == ""; i++)
   {
      if(StringFind(textLower, sells[i]) != -1)
         signal.type = "SELL";
   }

   // Refine type with explicit pending keywords if present
   if(signal.type != "")
   {
      bool hasLimit = (StringFind(textLower, "limit") != -1);
      bool hasStop  = (StringFind(textLower, "stop")  != -1);
      if(signal.type == "BUY")
      {
         if(hasLimit)
            signal.type = "BUY_LIMIT";
         else if(hasStop)
            signal.type = "BUY_STOP";
      }
      else if(signal.type == "SELL")
      {
         if(hasLimit)
            signal.type = "SELL_LIMIT";
         else if(hasStop)
            signal.type = "SELL_STOP";
      }
   }

   // 🔥 Check for "sl: open" or "sl open" first (means no SL, similar to tp: open)
   // Use exact pattern matching to avoid false positives
   if(StringFind(textLower, "sl: open") != -1 || 
      StringFind(textLower, "sl:open") != -1 || 
      StringFind(textLower, "sl open") != -1 ||
      StringFind(textLower, "nsl: open") != -1 ||   // Handle \nsl: open (escaped newline)
      StringFind(textLower, "nsl:open") != -1 ||
      StringFind(textLower, "nsl open") != -1)
   {
      ArrayResize(signal.sls, 1);
      signal.sls[0] = 0.0;  // SL = 0 means open (no SL)
      signal.hasSL = true;
      FBLogInfo("[FlameBot][INFO] SL parsed as 'open' -> 0.0 (no stop loss)");
   }

   // 🔥 Parse multiple SLs (sl, sl1, sl2, sl3, etc.) - IMPROVED VERSION
   // First pass: scan all text for "slN:" patterns using FindNumberAfterKeyword
   // Only if we haven't already set sl: open
   if(!signal.hasSL || (ArraySize(signal.sls) == 1 && signal.sls[0] == 0.0 && StringFind(textLower, "sl1") != -1))
   {
      // Detect whether message contains indexed SLs (sl<digit>), e.g., sl1/sl2.
      // If indexed SLs exist, we MUST ignore any plain "sl" to avoid accidentally parsing "sl" inside "sl1" -> 1.0.
      bool hasIndexedSL = false;
      {
         int lenSL = StringLen(textLower);
         int p = 0;
         while(true)
         {
            p = StringFind(textLower, "sl", p);
            if(p < 0)
               break;
            if(p + 2 < lenSL)
            {
               ushort ch = StringGetCharacter(textLower, p + 2);
               if(ch >= '0' && ch <= '9')
               {
                  hasIndexedSL = true;
                  break;
               }
            }
            p += 2;
         }
      }

      // Reset if we're going to parse indexed SLs
      if(hasIndexedSL)
      {
         ArrayResize(signal.sls, 0);
         signal.hasSL = false;
      }
      
      // If indexed SLs exist, do NOT include plain "sl" in the first-pass scan.
      // Otherwise, allow plain "sl" for single-SL messages.
      string slKeywords[];
      if(hasIndexedSL)
      {
         string tmp[] = {"sl1", "sl2", "sl3", "sl4", "sl5"};
         ArrayResize(slKeywords, ArraySize(tmp));
         for(int kk = 0; kk < ArraySize(tmp); kk++)
            slKeywords[kk] = tmp[kk];
      }
      else
      {
         string tmp[] = {"sl1", "sl2", "sl3", "sl4", "sl5", "sl"};
         ArrayResize(slKeywords, ArraySize(tmp));
         for(int kk = 0; kk < ArraySize(tmp); kk++)
            slKeywords[kk] = tmp[kk];
      }
      for(int k = 0; k < ArraySize(slKeywords); k++)
      {
         double sl_val = 0.0;
         if(FindNumberAfterKeyword(textLower, slKeywords[k], sl_val))
         {
            if(sl_val > 0.0)
            {
               // Allow duplicate SLs - each SL index maps to its TP
               int sz = ArraySize(signal.sls);
               ArrayResize(signal.sls, sz + 1);
               signal.sls[sz] = sl_val;
               signal.hasSL = true;
               FBLogDebug(StringFormat("[FlameBot][DEBUG] SL%d parsed (keyword '%s'): %.5f", sz + 1, slKeywords[k], sl_val));
            }
         }
      }
   }
   
   // Second pass: line-by-line token scan for edge cases
   // If indexed SLs exist anywhere in the message, ignore any plain (non-indexed) SL tokens.
   bool hasIndexedSL2 = false;
   {
      int lenSL2 = StringLen(textLower);
      int p2 = 0;
      while(true)
      {
         p2 = StringFind(textLower, "sl", p2);
         if(p2 < 0)
            break;
         if(p2 + 2 < lenSL2)
         {
            ushort ch2 = StringGetCharacter(textLower, p2 + 2);
            if(ch2 >= '0' && ch2 <= '9')
            {
               hasIndexedSL2 = true;
               break;
            }
         }
         p2 += 2;
      }
   }
   for(int i = 0; i < lineCount; i++)
   {
      string line = lines[i];
      string lineLower = line;
      StringToLower(lineLower);

      string tokens[];
      int tc = StringSplit(lineLower, ' ', tokens);
      for(int t = 0; t < tc; t++)
      {
         string tok = tokens[t];
         StringTrimLeft(tok);
         StringTrimRight(tok);
         if(tok == "")
            continue;

         string stripped = tok;
         StringReplace(stripped, "\r", "");
         StringReplace(stripped, "\n", "");
         StringReplace(stripped, ":", "");
         StringReplace(stripped, ";", "");
         StringReplace(stripped, ",", "");

         // Check for SL keywords: sl, sl1, sl2, stoploss, stop_loss, s/l
         // When indexed SLs exist, ignore plain "sl" and generic stop-loss synonyms.
         bool isSLKeyword = ((stripped == "sl" && !hasIndexedSL2) || 
                             stripped == "sl1" || stripped == "sl2" || stripped == "sl3" ||
                             stripped == "sl4" || stripped == "sl5" ||
                             (!hasIndexedSL2 && StringFind(stripped, "stoploss") == 0) ||
                             (!hasIndexedSL2 && StringFind(stripped, "stop_loss") == 0) ||
                             (stripped == "s/l" && !hasIndexedSL2));
         if(!isSLKeyword)
            continue;

         double sl_val = 0.0;
         bool have_val = false;

         // Extract value properly from SL token
         int colonPos = StringFind(tok, ":");
         int eqPos = StringFind(tok, "=");
         int delimPos = MathMax(colonPos, eqPos);
         
         if(delimPos != -1 && delimPos + 1 < StringLen(tok))
         {
            string valPart = StringSubstr(tok, delimPos + 1);
            StringTrimLeft(valPart);
            StringTrimRight(valPart);
            if(StringLen(valPart) >= 2)
            {
               sl_val = StringToDouble(valPart);
               if(sl_val > 0.0)
                  have_val = true;
            }
         }

         // Try next token if current doesn't have value
         if(!have_val && t + 1 < tc)
         {
            string nextTok = tokens[t + 1];
            StringTrimLeft(nextTok);
            StringTrimRight(nextTok);
            if(StringLen(nextTok) >= 2)
            {
               double testVal = StringToDouble(nextTok);
               if(testVal > 0.0)
               {
                  sl_val = testVal;
                  have_val = true;
               }
            }
         }

         if(have_val && sl_val > 0.0)
         {
            // Allow duplicate SLs - each SL index maps to its TP
            int sz = ArraySize(signal.sls);
            ArrayResize(signal.sls, sz + 1);
            signal.sls[sz] = sl_val;
            signal.hasSL = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] SL%d parsed (token scan): %.5f", sz + 1, sl_val));
         }
      }
   }

   // Fallback: try other keywords if no SLs found yet
   if(!signal.hasSL)
   {
      double sl_val = 0.0;
      if(FindNumberAfterKeyword(textLower, "stop loss", sl_val) ||
         FindNumberAfterKeyword(textLower, "stoploss", sl_val) ||
         FindNumberAfterKeyword(textLower, "s/l", sl_val) ||
         FindNumberAfterAt(textLower, sl_val))
      {
         if(sl_val > 0.0)
         {
            ArrayResize(signal.sls, 1);
            signal.sls[0] = sl_val;
            signal.hasSL = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] SL (fallback) parsed: %.5f", sl_val));
         }
      }
   }

   for(int i = 0; i < lineCount; i++)
   {
      string line = lines[i];
      string lineLower = line;
      StringToLower(lineLower);

      string tokens[];
      int tc = StringSplit(lineLower, ' ', tokens);
      for(int t = 0; t < tc; t++)
      {
         string tok = tokens[t];
         StringTrimLeft(tok);
         StringTrimRight(tok);
         if(tok == "")
            continue;

         string stripped = tok;
         StringReplace(stripped, "\r", "");
         StringReplace(stripped, "\n", "");
         StringReplace(stripped, ":", "");
         StringReplace(stripped, ";", "");
         StringReplace(stripped, ",", "");

         bool isTpKeyword = (StringFind(stripped, "tp") == 0 ||
                             StringFind(stripped, "takeprofit") == 0 ||
                             StringFind(stripped, "take_profit") == 0);
         if(!isTpKeyword)
            continue;

         double tp_val = 0.0;
         bool have_val = false;

         if(!have_val)
            have_val = ExtractTPValueFromToken(tok, tp_val);

         if(!have_val && t + 1 < tc)
         {
            string nextTok = tokens[t + 1];
            StringTrimLeft(nextTok);
            StringTrimRight(nextTok);
            have_val = ExtractTPValueFromToken(nextTok, tp_val);
         }

         if(have_val)
            AddUniqueTP(signal, tp_val, "tp keyword");
      }

      // Fallback: if line contains exact "tp: open" or "tpN: open" pattern
      // Check for patterns: "tp: open", "tp:open", "tp open", "tp1: open", etc.
      if(StringFind(lineLower, "tp: open") != -1 || 
         StringFind(lineLower, "tp:open") != -1 || 
         StringFind(lineLower, "tp open") != -1 ||
         StringFind(lineLower, "tp1: open") != -1 ||
         StringFind(lineLower, "tp1:open") != -1 ||
         StringFind(lineLower, "tp2: open") != -1 ||
         StringFind(lineLower, "tp2:open") != -1 ||
         StringFind(lineLower, "tp3: open") != -1 ||
         StringFind(lineLower, "tp3:open") != -1 ||
         StringFind(lineLower, "tp4: open") != -1 ||
         StringFind(lineLower, "tp5: open") != -1)
      {
         AddUniqueTP(signal, 0.0, "tp open fallback");
      }
   }

   double nums[];
   int numCount = ExtractAllNumbers(textLower, nums);

   // Remove all parsed SL values from nums array
   if(signal.hasSL && ArraySize(signal.sls) > 0)
   {
      int writeIdx = 0;
      for(int i = 0; i < numCount; i++)
      {
         bool isSL = false;
         for(int s = 0; s < ArraySize(signal.sls); s++)
         {
            if(MathAbs(nums[i] - signal.sls[s]) < 0.0000001)
            {
               isSL = true;
               break;
            }
         }
         if(!isSL)
            nums[writeIdx++] = nums[i];
      }
      ArrayResize(nums, writeIdx);
      numCount = writeIdx;
   }

   if(ArraySize(signal.tps) > 0)
   {
      int writeIdx2 = 0;
      for(int i = 0; i < numCount; i++)
      {
         double v = nums[i];
         bool match = false;
         for(int j = 0; j < ArraySize(signal.tps); j++)
         {
            if(MathAbs(signal.tps[j] - v) < 0.0000001)
            {
               match = true;
               break;
            }
         }
         if(!match)
            nums[writeIdx2++] = v;
      }
      ArrayResize(nums, writeIdx2);
      numCount = writeIdx2;
   }

   bool expectEntry =
      (StringFind(textLower, "entry") != -1 ||
       StringFind(textLower, "@")     != -1);

   // 🔥 SAFETY CHECK: Remove entry prices from nums array if they were detected from header
   if(signal.hasEntry || signal.hasEntry2)
   {
      double entryEps = (signal.pair != "") ? PriceMatchEpsilonForSymbol(signal.pair) : 0.0001;
      int writeIdx = 0;
      for(int i = 0; i < numCount; i++)
      {
         double v = nums[i];
         bool isEntry = false;
         
         if(signal.hasEntry && MathAbs(v - signal.entry) <= entryEps)
            isEntry = true;
         if(signal.hasEntry2 && MathAbs(v - signal.entry2) <= entryEps)
            isEntry = true;
         
         if(!isEntry)
            nums[writeIdx++] = v;
         else
            FBLogDebug(StringFormat("[FlameBot][DEBUG] Excluded entry price %.5f from TP candidates", v));
      }
      ArrayResize(nums, writeIdx);
      numCount = writeIdx;
   }

   // Fallback number assignment (if no entry range detected from header)
   for(int i = 0; i < numCount; i++)
   {
      double v = nums[i];
      if(expectEntry && !signal.hasEntry)
      {
         signal.entry = v;
         signal.hasEntry = true;
      }
      else
      {
         // 🔥 FINAL SAFETY CHECK: Never add entry prices as TPs
         double entryEps = (signal.pair != "") ? PriceMatchEpsilonForSymbol(signal.pair) : 0.0001;
         bool isEntryPrice = false;
         if(signal.hasEntry && MathAbs(v - signal.entry) <= entryEps)
            isEntryPrice = true;
         if(signal.hasEntry2 && MathAbs(v - signal.entry2) <= entryEps)
            isEntryPrice = true;
         
         if(isEntryPrice)
         {
            FBLogError(StringFormat("[FlameBot][ERROR] Entry price %.5f incorrectly detected as TP - skipped", v));
         }
         else
         {
            AddUniqueTP(signal, v, "fallback number");
         }
      }
   }

   if(signal.pair == "")
   {
      string fallback = textLower;
      StringReplace(fallback, "\r", " ");
      StringReplace(fallback, "\n", " ");
      StringReplace(fallback, ":", " ");
      StringReplace(fallback, ",", " ");
      StringReplace(fallback, ";", " ");

      string wordsAll[];
      int wcAll = StringSplit(fallback, ' ', wordsAll);
      for(int i = 0; i < wcAll && signal.pair == ""; i++)
      {
         string w = wordsAll[i];
         StringTrimLeft(w);
         StringTrimRight(w);
         if(StringLen(w) >= 6 && !IsSymbolBannedKeyword(w))
         {
            string m = MatchSymbol(w);
            if(m != "")
               signal.pair = m;
         }
      }
   }

   if(signal.pair == "" || signal.type == "")
   {
      FBLogError(StringFormat("[FlameBot][ERROR] ParseSignal missing essentials | pair='%s' | type='%s'", signal.pair, signal.type));
      return(false);
   }

   if(!signal.hasSL && ArraySize(signal.tps) == 0 && !signal.hasEntry)
   {
      FBLogError("[FlameBot][ERROR] ParseSignal missing price levels (no SL/TP/entry)");
      return(false);
   }

   return(true);
}

bool ParseUpdateOnly(const string text, Signal &signal)
{
   signal.hasSL = false;
   ArrayResize(signal.sls, 0);
   ArrayResize(signal.sl_indices, 0);
   ArrayResize(signal.tps, 0);
   ArrayResize(signal.tp_indices, 0);
   signal.updateAll_SL = false;
   signal.updateAll_TP = false;

   string lower = text;
   StringToLower(lower);
   
   // Replace escaped newlines with actual newlines for line-by-line parsing
   StringReplace(lower, "\\n", "\n");
   
   // === PARSE SL UPDATES ===
   // Check for "sl open" / "sl: open" first (remove SL)
   if(StringFind(lower, "sl: open") != -1 || StringFind(lower, "sl:open") != -1 || 
      StringFind(lower, "sl open") != -1 || StringFind(lower, "nsl: open") != -1 ||
      StringFind(lower, "nsl:open") != -1 || StringFind(lower, "nsl open") != -1)
   {
      ArrayResize(signal.sls, 1);
      ArrayResize(signal.sl_indices, 1);
      signal.sls[0] = 0.0;
      signal.sl_indices[0] = -1;  // -1 means apply to ALL trades
      signal.hasSL = true;
      signal.updateAll_SL = true;
      FBLogInfo("[FlameBot][INFO] UPDATE: SL open -> remove SL from ALL trades");
   }
   // Check for indexed SL: sl1, sl2, sl3, etc. (supports up to sl100)
   else
   {
      for(int idx = 1; idx <= 100; idx++)
      {
         string slKey = "sl" + IntegerToString(idx);
         double sl_val = 0.0;
         
         // Check for slN: open (remove SL for specific trade)
         string slOpenPattern = slKey + ": open";
         string slOpenPattern2 = slKey + ":open";
         if(StringFind(lower, slOpenPattern) != -1 || StringFind(lower, slOpenPattern2) != -1)
         {
            int sz = ArraySize(signal.sls);
            ArrayResize(signal.sls, sz + 1);
            ArrayResize(signal.sl_indices, sz + 1);
            signal.sls[sz] = 0.0;
            signal.sl_indices[sz] = idx;  // 1-based index
            signal.hasSL = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: SL%d open -> remove SL from trade %d", idx, idx));
         }
         else if(FindNumberAfterKeyword(lower, slKey, sl_val))
         {
            int sz = ArraySize(signal.sls);
            ArrayResize(signal.sls, sz + 1);
            ArrayResize(signal.sl_indices, sz + 1);
            signal.sls[sz] = sl_val;
            signal.sl_indices[sz] = idx;  // 1-based index
            signal.hasSL = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: SL%d = %.5f (trade %d only)", idx, sl_val, idx));
         }
      }
      
      // Check for non-indexed "sl:" or "sl " (apply to ALL trades)
      if(!signal.hasSL)
      {
         double sl_val = 0.0;
         if(FindNumberAfterKeyword(lower, "sl", sl_val) ||
            FindNumberAfterKeyword(lower, "stop loss", sl_val) ||
            FindNumberAfterKeyword(lower, "stoploss", sl_val))
         {
            // Make sure it's not sl1, sl2, etc. (already handled above)
            ArrayResize(signal.sls, 1);
            ArrayResize(signal.sl_indices, 1);
            signal.sls[0] = sl_val;
            signal.sl_indices[0] = -1;  // -1 means apply to ALL trades
            signal.hasSL = true;
            signal.updateAll_SL = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: SL = %.5f (ALL trades)", sl_val));
         }
      }
   }
   
   // === PARSE TP UPDATES ===
   // Check for "tp open" / "tp: open" first (remove TP)
   if(StringFind(lower, "tp: open") != -1 || StringFind(lower, "tp:open") != -1 || 
      StringFind(lower, "tp open") != -1)
   {
      ArrayResize(signal.tps, 1);
      ArrayResize(signal.tp_indices, 1);
      signal.tps[0] = 0.0;
      signal.tp_indices[0] = -1;  // -1 means apply to ALL trades
      signal.updateAll_TP = true;
      FBLogInfo("[FlameBot][INFO] UPDATE: TP open -> remove TP from ALL trades");
   }
   else
   {
      // Check for indexed TP: tp1, tp2, tp3, etc. (supports up to tp100)
      for(int idx = 1; idx <= 100; idx++)
      {
         string tpKey = "tp" + IntegerToString(idx);
         double tp_val = 0.0;
         
         // Check for tpN: open (remove TP for specific trade)
         string tpOpenPattern = tpKey + ": open";
         string tpOpenPattern2 = tpKey + ":open";
         if(StringFind(lower, tpOpenPattern) != -1 || StringFind(lower, tpOpenPattern2) != -1)
         {
            int sz = ArraySize(signal.tps);
            ArrayResize(signal.tps, sz + 1);
            ArrayResize(signal.tp_indices, sz + 1);
            signal.tps[sz] = 0.0;
            signal.tp_indices[sz] = idx;  // 1-based index
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: TP%d open -> remove TP from trade %d", idx, idx));
         }
         else if(FindNumberAfterKeyword(lower, tpKey, tp_val))
         {
            int sz = ArraySize(signal.tps);
            ArrayResize(signal.tps, sz + 1);
            ArrayResize(signal.tp_indices, sz + 1);
            signal.tps[sz] = tp_val;
            signal.tp_indices[sz] = idx;  // 1-based index
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: TP%d = %.5f (trade %d only)", idx, tp_val, idx));
         }
      }
      
      // Check for non-indexed "tp:" or "tp " (apply to ALL trades)
      if(ArraySize(signal.tps) == 0)
      {
         double tp_val = 0.0;
         if(FindNumberAfterKeyword(lower, "tp", tp_val) ||
            FindNumberAfterKeyword(lower, "take profit", tp_val) ||
            FindNumberAfterKeyword(lower, "takeprofit", tp_val))
         {
            ArrayResize(signal.tps, 1);
            ArrayResize(signal.tp_indices, 1);
            signal.tps[0] = tp_val;
            signal.tp_indices[0] = -1;  // -1 means apply to ALL trades
            signal.updateAll_TP = true;
            FBLogInfo(StringFormat("[FlameBot][INFO] UPDATE: TP = %.5f (ALL trades)", tp_val));
         }
      }
   }

   return (signal.hasSL || ArraySize(signal.tps) > 0);
}

//+------------------------------------------------------------------+
//| Risk helpers                                                     |
//+------------------------------------------------------------------+
double CalculateLotSize(bool isPropAccount)
{
   // IMPORTANT: This formula is USD-calibrated. Equity MUST be normalized to USD first.
   double equityAcc = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityUSD = 0.0;
   if(!FBConvertAccountToUsd(equityAcc, equityUSD))
      return(0.0); // fail-safe: block trading if FX pair missing

   double effective_equity = isPropAccount ? equityUSD * 0.05 : equityUSD;
   double risk_percent = 0.000022;
   double lot_size = effective_equity * risk_percent;
   if(lot_size < 0.01)
      lot_size = 0.01;
   if(lot_size > 50.0)
      lot_size = 50.0;
   return(NormalizeDouble(lot_size, 2));
}

bool IsTradeProfitableEnough(const string symbol, bool isBuy, double current_price, double tp, double lot)
{
   double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point_size  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point_value <= 0.0 || point_size <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Could not retrieve symbol info for " + symbol);
      return(false);
   }

   double point_distance = MathAbs(tp - current_price) / point_size;
   double potential_profit = point_distance * point_value * (lot / 0.01);
   double min_profit = 0.0;
   double min_profit_usd = FB_BASE_THRESHOLD_USD * (lot / 0.01);
   if(!FBConvertUsdToAccount(min_profit_usd, min_profit))
      return(false); // fail-safe: cannot determine USD->account currency conversion
   FBLogDebug(StringFormat("[FlameBot][DEBUG] Checking TP: %s | TP=%.5f Curr=%.5f Potential=%.2f %s Min=%.2f %s", symbol, tp, current_price, potential_profit, FBGetAccountCurrency(), min_profit, FBGetAccountCurrency()));
   return(potential_profit >= min_profit);
}

bool HasPriceMovedTooFar(const string symbol, bool isBuy, double current_price, double entry_price, double lot)
{
   double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point_size  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point_value <= 0.0 || point_size <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Could not retrieve symbol info for " + symbol);
      return(false);
   }

   double points_diff = (current_price - entry_price) / point_size;
   double dollar_move_signed = points_diff * point_value * lot; // tick_value is per 1 lot
   double dollar_move = MathAbs(dollar_move_signed);
   double thresholdUSD = (FB_BASE_THRESHOLD_USD * InpDeviationUSDPerMicroLot) * (lot / 0.01);
   double thresholdAcc = 0.0;
   if(!FBConvertUsdToAccount(thresholdUSD, thresholdAcc))
      return(true); // fail-safe: block trade if conversion is unavailable

   // Only reject adverse slippage: BUY -> price above entry; SELL -> price below entry
   bool adverse = isBuy ? (points_diff > 0) : (points_diff < 0);
   if(!adverse)
   {
      // Favorable slippage — allow, regardless of magnitude
      FBLogInfo(StringFormat("[FlameBot][INFO] %s: favorable slippage %.2f %s (entry=%.5f, current=%.5f, lot=%.2f)", symbol, dollar_move, FBGetAccountCurrency(), entry_price, current_price, lot));
      return(false);
   }

   if(dollar_move >= thresholdAcc)
   {
      FBLogWarn(StringFormat("[FlameBot][WARN] %s: adverse deviation %.2f %s >= threshold %.2f %s (entry=%.5f, current=%.5f, lot=%.2f)", symbol, dollar_move, FBGetAccountCurrency(), thresholdAcc, FBGetAccountCurrency(), entry_price, current_price, lot));
      return(true);
   }
   return(false);
}

bool IsSignalValid(const Signal &signal, bool isBuy, double entry, double sl)
{
   if(!signal.hasEntry || !signal.hasSL)
      return(true);

   if(isBuy && sl >= entry)
   {
      FBLogError("[FlameBot][ERROR] Invalid BUY: SL >= Entry");
      return(false);
   }

   if(!isBuy && sl <= entry)
   {
      FBLogError("[FlameBot][ERROR] Invalid SELL: SL <= Entry");
      return(false);
   }

   for(int i = 0; i < ArraySize(signal.tps); i++)
   {
      double tp = signal.tps[i];

      // Skip validation for tp: open (tp = 0)
      if(tp == 0.0)
         continue;

      if(isBuy)
      {
         if(tp <= entry || tp <= sl)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] TP%d invalid for BUY (<= Entry/SL). Will skip this TP.", i+1));
            continue;
         }
      }
      else
      {
         if(tp >= entry || tp >= sl)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] TP%d invalid for SELL (>= Entry/SL). Will skip this TP.", i+1));
            continue;
         }
      }
   }

   return(true);
}

ENUM_ORDER_TYPE GetSmartOrderType(bool isBuy, double entry, double current)
{
   if(isBuy)
      return(entry < current ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP);

   return(entry > current ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);
}

bool IsPendingOrderPriceValid(ENUM_ORDER_TYPE type, double entry, double current)
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:  return(entry < current);
      case ORDER_TYPE_BUY_STOP:   return(entry > current);
      case ORDER_TYPE_SELL_LIMIT: return(entry > current);
      case ORDER_TYPE_SELL_STOP:  return(entry < current);
   }
   return(true);
}

bool EnsureSymbolReady(const string symbol)
{
   // Enable symbol in Market Watch
   if(!SymbolSelect(symbol, true))
   {
      FBLogError("[FlameBot][ERROR] Symbol not allowed by broker: " + symbol);
      return(false);
   }
   
   FBLogDebug("[FlameBot][DEBUG] Waiting for symbol data to load: " + symbol);
   
   // Open chart to force symbol data loading
   long chart = ChartOpen(symbol, PERIOD_M1);
   
   // Retry up to 10 times with 500ms delay
   int retries = 0;
   int maxRetries = 10;
   
   while(retries < maxRetries)
   {
      Sleep(500);  // Wait 500ms for data to load
      
      MqlTick tick;
      if(SymbolInfoTick(symbol, tick) && tick.bid > 0 && tick.ask > 0)
      {
         // Check symbol properties
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         
         if(tickValue > 0 && point > 0)
         {
            FBLogDebug(StringFormat("[FlameBot][DEBUG] Symbol ready: %s | Bid=%s Ask=%s", symbol, DoubleToString(tick.bid, 5), DoubleToString(tick.ask, 5)));
            if(chart > 0)
               ChartClose(chart);
            return(true);
         }
      }
      
      retries++;
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Retry %d/%d waiting for %s...", retries, maxRetries, symbol));
   }
   
   // Cleanup
   if(chart > 0)
      ChartClose(chart);
   
   FBLogError(StringFormat("[FlameBot][ERROR] Symbol properties not ready after %d retries: %s", maxRetries, symbol));
   return(false);
}

bool IsLotValidForSymbol(const string symbol, double lot)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lot < minLot || lot > maxLot)
      return(false);

   if(stepLot <= 0.0)
      return(false);

   double steps = (lot - minLot) / stepLot;
   double nearest = MathRound(steps);
   if(MathAbs(steps - nearest) > 1e-8)
      return(false);

   return(true);
}

bool DetermineLotSize(const string symbol, bool isPropAccount, const double entry_price, const double sl_price, double &lot)
{
   // Check execution mode and use ONLY that mode's logic
   if(gExecutionMode == "psl")
   {
      // PSL MODE: Use ONLY per-symbol lots
      if(!gPSLConfigured)
      {
         FBLogError("[FlameBot][ERROR] [PSL MODE] PSL not configured - trade blocked");
         return false;
      }
      
      // PSL STRICT GATE: Symbol MUST exist in PSL list
      bool found = false;
      for(int i = 0; i < ArraySize(gPSLLots); i++)
      {
         if(gPSLLots[i].symbol == symbol)
         {
            lot = gPSLLots[i].lot;
            found = true;
            break;
         }
      }
      
      if(!found)
      {
         FBLogError(StringFormat("[FlameBot][ERROR] [PSL MODE] Symbol %s not in PSL - trade BLOCKED", symbol));
         return false;
      }
      
      // Validate lot for symbol
      if(!IsLotValidForSymbol(symbol, lot))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] [PSL MODE] Invalid lot %.2f for %s", lot, symbol));
         return false;
      }
      
      return true;
   }
   
   // GLS MODE: Use GLS lot logic (UNCHANGED)
   if(gLotMode == "custom")
   {
      lot = gCustomLot;
      if(!IsLotValidForSymbol(symbol, lot))
      {
         FBLogError("[FlameBot][ERROR] [GLS MODE] Invalid lot size received from server");
         return(false);
      }
      return(true);
   }

   // Use EA calculated lot (default GLS behavior)
   if(InpRiskAccount > 0.0)
   {
      if(!FBCalcLotFromRiskAccount(symbol, entry_price, sl_price, InpRiskAccount, lot))
         return(false);
      return(true);
   }

   lot = CalculateLotSize(isPropAccount);
   if(lot <= 0.0)
      return(false);
   return(true);
}

bool IsSymbolAllowed(const string symbol)
{
   // Check execution mode and use ONLY that mode's logic
   if(gExecutionMode == "psl")
   {
      // PSL MODE: Only symbols in PSL list are allowed
      if(!gPSLConfigured)
         return false;
      
      for(int i = 0; i < ArraySize(gPSLLots); i++)
      {
         if(gPSLLots[i].symbol == symbol)
            return true;
      }
      return false;
   }
   
   // GLS MODE: Use GLS symbol filtering (UNCHANGED)
   if(gSymbolMode == "default" || !gSymbolSettingsLoaded)
      return(true);

   string target = symbol;
   StringToUpper(target);
   for(int i = 0; i < ArraySize(gAllowedSymbols); i++)
   {
      if(target == gAllowedSymbols[i])
         return(true);
   }

   FBLogError("[FlameBot][ERROR] Symbol rejected (custom mode): " + symbol);
   return(false);
}

bool EnsureSymbolEnabledAndAllowed(const string symbol)
{
   if(gSymbolMode == "custom" && !IsSymbolAllowed(symbol))
      return(false);

   return EnsureSymbolReady(symbol);
}

//+------------------------------------------------------------------+
//| Backend sync                                                     |
//+------------------------------------------------------------------+
void UpdateTradingUnlock()
{
   // IMPORTANT: Settings must NEVER unlock unless the backend has accepted login.
   // This prevents "ghost unlock" when a second EA is rejected but can still fetch defaults.
   bool session_ok = (gAuthReady && gLoginOk && gHeartbeatSent && gAccountTypeReady);
   bool ready = (session_ok && gLotConfigured && gSymbolConfigured);

   if(ready && !gTradingUnlocked)
   {
      gTradingUnlocked = true;
      gWaitingAnnounced = false;
      FBLogInfo("[FlameBot][INFO] Trading unlocked. User settings confirmed.");
      FBLogInfo("[FlameBot] Settings are now unlocked in the Desktop App");
   }

   if(!ready)
   {
      gTradingUnlocked = false;
      gWaitingAnnounced = false;
   }
}

void HandleLotFinalizationLog()
{
   // Only log GLS lot finalization when GLS is the active execution mode
   if(gExecutionMode != "gls")
      return;
   
   if(!gLotConfigured)
   {
      gLotFinalPrinted = false;
      gLotPrintedMode = "";
      gLotPrintedCustom = 0.0;
      return;
   }

   bool changed = (gLotMode != gLastLotMode);
   if(gLotMode == "custom" && MathAbs(gCustomLot - gLastCustomLot) > 0.0000001)
      changed = true;

   if(!changed)
      return;

   if(gLotMode == "custom")
      FBLogInfo(StringFormat("[FlameBot][INFO] Lot settings finalized | mode=custom | custom=%.2f", gCustomLot));
   else
      FBLogInfo("[FlameBot][INFO] Lot settings finalized | mode=default");

   gLastLotMode   = gLotMode;
   gLastCustomLot = gCustomLot;

   gLotFinalPrinted = true;
   gLotPrintedMode = gLotMode;
   gLotPrintedCustom = gCustomLot;
}

void HandleSymbolFinalizationLog()
{
   // Only log GLS symbol finalization when GLS is the active execution mode
   if(gExecutionMode != "gls")
      return;
   
   if(!gSymbolConfigured)
   {
      gSymbolFinalPrinted = false;
      gSymbolPrintedMode = "";
      gSymbolPrintedCount = 0;
      return;
   }

   int count = ArraySize(gAllowedSymbols);
   bool changed = (gSymbolMode != gLastSymbolMode) || (gSymbolMode == "custom" && count != gLastSymbolCount);

   if(!changed)
      return;

   gSymbolSyncDone = false;

   if(gSymbolMode == "custom")
      FBLogInfo(StringFormat("[FlameBot][INFO] Symbol settings finalized | mode=custom | count=%d", count));
   else
      FBLogInfo("[FlameBot][INFO] Symbol settings finalized | mode=default");

   gLastSymbolMode  = gSymbolMode;
   gLastSymbolCount = count;

   gSymbolFinalPrinted = true;
   gSymbolPrintedMode = gSymbolMode;
   gSymbolPrintedCount = count;
}

void HandlePSLFinalizationLog()
{
   // Only log PSL finalization when PSL is the active execution mode
   if(gExecutionMode != "psl")
      return;
   
   if(!gPSLConfigured)
   {
      gPSLFinalPrinted = false;
      gLastPSLCount = -1;
      return;
   }

   int count = ArraySize(gPSLLots);
   bool changed = (count != gLastPSLCount);

   if(!changed)
      return;

   FBLogInfo(StringFormat("[FlameBot][INFO] PSL Symbol and Lot settings finalized | count=%d", count));
   gLastPSLCount = count;
   gPSLFinalPrinted = true;
}

void SyncMarketWatchWithUserSettings()
{
   // Sync Market Watch based on execution mode
   if(gExecutionMode == "psl")
   {
      // PSL MODE: Add only symbols in PSL list
      if(!gPSLConfigured)
         return;
      
      // Disable all symbols first
      int all = SymbolsTotal(false);
      for(int i = 0; i < all; i++)
      {
         string sym = SymbolName(i, false);
         SymbolSelect(sym, false);
      }
      
      // Enable only PSL symbols
      for(int i = 0; i < ArraySize(gPSLLots); i++)
      {
         SymbolSelect(gPSLLots[i].symbol, true);
      }
      
      int count = ArraySize(gPSLLots);
      if(gLastMWMode != "psl" || gLastMWCount != count)
      {
         FBLogInfo(StringFormat("[FlameBot][INFO] Market Watch updated: PSL mode (%d symbols enabled)", count));
         gLastMWMode  = "psl";
         gLastMWCount = count;
      }
      return;
   }
   
   // GLS MODE: Use GLS symbol filtering (UNCHANGED)
   if(!gSymbolConfigured)
      return;

   if(gSymbolMode == "default")
   {
      int all = SymbolsTotal(false);
      for(int i = 0; i < all; i++)
      {
         string sym = SymbolName(i, false);
         SymbolSelect(sym, true);
      }

      if(gLastMWMode != "default")
      {
         FBLogInfo("[FlameBot][INFO] Market Watch updated: DEFAULT mode (all symbols enabled)");
         gLastMWMode  = "default";
         gLastMWCount = -1;
      }
      return;
   }

   int all = SymbolsTotal(false);
   for(int i = 0; i < all; i++)
   {
      string sym = SymbolName(i, false);
      SymbolSelect(sym, false);
   }

   for(int i = 0; i < ArraySize(gAllowedSymbols); i++)
      SymbolSelect(gAllowedSymbols[i], true);

   int count = ArraySize(gAllowedSymbols);

   if(gLastMWMode != "custom" || gLastMWCount != count)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Market Watch updated: CUSTOM mode (%d symbols enabled)", count));
      gLastMWMode  = "custom";
      gLastMWCount = count;
   }
}

bool FetchLotSettings()
{
   if(!gAuthReady)
      return(false);

   string url = BuildEndpointUrl("get_lot_settings");
   string body = "{" +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"platform\":\"mt5\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"account_type\":\"" + gAccountType + "\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"" +
   "}";
   string response = HttpPostJson(url, body);
   if(response == "")
   {
      if(LogEnabled(FB_LOG_DEBUG))
         FBLogDebug("[FlameBot][DEBUG] Lot settings fetch failed (empty response)");
      return(false);
   }

   string status = "";
   if(!ExtractJsonString(response, "status", status) || status != "OK")
   {
      string msg = "";
      ExtractJsonString(response, "message", msg);
      if(status == "INVALID")
      {
         if(msg != "")
            FBLogError("[FlameBot][ERROR] Lot settings rejected: " + msg);
         else
            FBLogError("[FlameBot][ERROR] Lot settings rejected: " + response);

         string m = msg;
         StringToLower(m);
         if(StringFind(m, "invalid license") != -1 || StringFind(m, "unknown flamebot id") != -1)
            ResetCredentialsAfterInvalid();
      }
      else
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Lot settings response invalid (url=%s, %s): %s", FBStripUrlQuery(url), FBHttpDiagSummary(), response));
      }
      return(false);
   }

   string configuredRaw;
   gLotConfigured = false;
   if(ExtractJsonString(response, "lot_configured", configuredRaw))
   {
      string lc = configuredRaw;
      StringToLower(lc);
      gLotConfigured = (lc == "true" || lc == "1");
   }

   string mode;
   if(ExtractJsonString(response, "lot_mode", mode))
   {
      StringToLower(mode);
      gLotMode = mode;
   }

   string customLotRaw;
   if(ExtractJsonString(response, "custom_lot", customLotRaw))
      gCustomLot = StringToDouble(customLotRaw);
   
   // Extract execution_mode
   string execMode;
   if(ExtractJsonString(response, "execution_mode", execMode))
   {
      StringToLower(execMode);
      if(execMode == "psl" || execMode == "gls")
         gExecutionMode = execMode;
   }
   
   // Extract trade control toggles
   string allowCloseStr, allowBEStr, allowSecureHalfStr, allowMultiStr;
   bool prevClose = gAllowMessageClose;
   bool prevBE = gAllowMessageBreakeven;
   bool prevSecureHalf = gAllowSecureHalf;
   bool prevMulti = gAllowMultipleSignalsPerSymbol;
   
   if(ExtractJsonString(response, "allow_message_close", allowCloseStr))
   {
      StringToLower(allowCloseStr);
      gAllowMessageClose = (allowCloseStr == "true" || allowCloseStr == "1");
   }
   if(ExtractJsonString(response, "allow_message_breakeven", allowBEStr))
   {
      StringToLower(allowBEStr);
      gAllowMessageBreakeven = (allowBEStr == "true" || allowBEStr == "1");
   }
   if(ExtractJsonString(response, "allow_secure_half", allowSecureHalfStr))
   {
      StringToLower(allowSecureHalfStr);
      gAllowSecureHalf = (allowSecureHalfStr == "true" || allowSecureHalfStr == "1");
   }
   if(ExtractJsonString(response, "allow_multiple_signals_per_symbol", allowMultiStr))
   {
      StringToLower(allowMultiStr);
      gAllowMultipleSignalsPerSymbol = (allowMultiStr == "true" || allowMultiStr == "1");
   }

   // Extract trade scheduler (Pause / Resume)
   bool prevSchedActive = gSchedulerActive;
   int prevPauseDay = gSchedulerPauseDay;
   string prevPauseTime = gSchedulerPauseTime;
   int prevResumeDay = gSchedulerResumeDay;
   string prevResumeTime = gSchedulerResumeTime;

   string schedActiveStr;
   if(ExtractJsonString(response, "scheduler_active", schedActiveStr))
   {
      StringToLower(schedActiveStr);
      gSchedulerActive = (schedActiveStr == "true" || schedActiveStr == "1");
   }
   else
   {
      gSchedulerActive = false;
   }

   string pdStr;
   if(ExtractJsonString(response, "scheduler_pause_day", pdStr))
   {
      TrimString(pdStr);
      if(pdStr == "" || pdStr == "null")
         gSchedulerPauseDay = -1;
      else
         gSchedulerPauseDay = (int)StringToInteger(pdStr);
   }
   else
   {
      gSchedulerPauseDay = -1;
   }

   if(gSchedulerPauseDay < 0 || gSchedulerPauseDay > 6)
      gSchedulerPauseDay = -1;

   string ptStr;
   if(ExtractJsonString(response, "scheduler_pause_time", ptStr))
   {
      TrimString(ptStr);
      gSchedulerPauseTime = (ptStr == "null") ? "" : ptStr;
   }
   else
   {
      gSchedulerPauseTime = "";
   }

   string rdStr;
   if(ExtractJsonString(response, "scheduler_resume_day", rdStr))
   {
      TrimString(rdStr);
      if(rdStr == "" || rdStr == "null")
         gSchedulerResumeDay = -1;
      else
         gSchedulerResumeDay = (int)StringToInteger(rdStr);
   }
   else
   {
      gSchedulerResumeDay = -1;
   }

   if(gSchedulerResumeDay < 0 || gSchedulerResumeDay > 6)
      gSchedulerResumeDay = -1;

   string rtStr;
   if(ExtractJsonString(response, "scheduler_resume_time", rtStr))
   {
      TrimString(rtStr);
      gSchedulerResumeTime = (rtStr == "null") ? "" : rtStr;
   }
   else
   {
      gSchedulerResumeTime = "";
   }

   if(!gSchedulerPrinted || prevSchedActive != gSchedulerActive || prevPauseDay != gSchedulerPauseDay || prevPauseTime != gSchedulerPauseTime || prevResumeDay != gSchedulerResumeDay || prevResumeTime != gSchedulerResumeTime)
   {
      if(LogEnabled(FB_LOG_INFO))
      {
         MqlDateTime nowDt;
         TimeToStruct(TimeCurrent(), nowDt);
         string nowHHMM = StringFormat("%02d:%02d", nowDt.hour, nowDt.min);
         string nowDOW  = FBDowName(nowDt.day_of_week);
         FBLogInfo(StringFormat("[FlameBot][INFO] Scheduler | Active=%s | Now=%s @ %s | EA pauses: %s @ %s | EA resumes: %s @ %s",
                     gSchedulerActive ? "ON" : "OFF",
                     nowDOW, nowHHMM,
                     FBDowName(gSchedulerPauseDay), gSchedulerPauseTime,
                     FBDowName(gSchedulerResumeDay), gSchedulerResumeTime));
      }
      gSchedulerPrinted = true;
   }
   
   // Extract entry strategy mode for range signals
   string prevEntryMode = gEntryMode;
   string entryMode;
   if(ExtractJsonString(response, "entry_mode", entryMode))
   {
      StringToLower(entryMode);
      if(entryMode == "market_edge" || entryMode == "range_distributed")
         gEntryMode = entryMode;
   }
   
   // Print confirmation when toggles change or first load (combined line incl. multiple-signals)
   if(!gTogglesPrinted || prevClose != gAllowMessageClose || prevBE != gAllowMessageBreakeven || prevSecureHalf != gAllowSecureHalf || prevMulti != gAllowMultipleSignalsPerSymbol)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Telegram Trade Control | Close=%s | Breakeven=%s | Secure-Half=%s | Multiple signals per symbol=%s", gAllowMessageClose ? "ON" : "OFF", gAllowMessageBreakeven ? "ON" : "OFF", gAllowSecureHalf ? "ON" : "OFF", gAllowMultipleSignalsPerSymbol ? "ON" : "OFF"));
      gTogglesPrinted = true;
      gAllowMultiPrinted = true;
   }

   // Print finalized entry mode when first loaded or changed
   if(!gEntryModePrinted || prevEntryMode != gEntryMode)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Entry mode finalized | mode=%s", gEntryMode));
      gEntryModePrinted = true;
   }

   gLotSettingsLoaded = true;

   if(!gLotConfigured)
   {
      if(!gLotPendingLogged)
      {
         FBLogInfo("[FlameBot][INFO] Waiting for lot configuration");
         gLotPendingLogged = true;
      }
   }
   else
   {
      gLotPendingLogged = false;
   }

   HandleLotFinalizationLog();
   HandleSymbolFinalizationLog();
   SyncMarketWatchWithUserSettings();
   UpdateTradingUnlock();
   FBSchedulerTick();
   return(true);
}

bool FetchSymbolSettings()
{
   if(!gAuthReady)
      return(false);

   string url = BuildEndpointUrl("get_symbol_settings");
   string body = "{" +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"platform\":\"mt5\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"account_type\":\"" + gAccountType + "\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"" +
   "}";

   string response = HttpPostJson(url, body);
   if(response == "")
   {
      if(LogEnabled(FB_LOG_DEBUG))
         FBLogDebug("[FlameBot][DEBUG] Symbol settings fetch failed (empty response)");
      return(false);
   }

   string status = "";
   if(!ExtractJsonString(response, "status", status) || status != "OK")
   {
      string msg = "";
      ExtractJsonString(response, "message", msg);
      if(status == "INVALID")
      {
         if(msg != "")
            FBLogError("[FlameBot][ERROR] Symbol settings rejected: " + msg);
         else
            FBLogError("[FlameBot][ERROR] Symbol settings rejected: " + response);

         string m = msg;
         StringToLower(m);
         if(StringFind(m, "invalid license") != -1 || StringFind(m, "unknown flamebot id") != -1)
            ResetCredentialsAfterInvalid();
      }
      else
      {
         FBLogError("[FlameBot][ERROR] Symbol settings response invalid: " + response);
      }
      return(false);
   }

   string configuredRaw;
   gSymbolConfigured = false;
   if(ExtractJsonString(response, "symbol_configured", configuredRaw))
   {
      string sc = configuredRaw;
      StringToLower(sc);
      gSymbolConfigured = (sc == "true" || sc == "1");
   }

   string modeRaw = "";
   if(ExtractJsonString(response, "symbol_mode", modeRaw))
   {
      StringToLower(modeRaw);
      gSymbolMode = (modeRaw == "custom" ? "custom" : "default");
   }
   else
   {
      gSymbolMode = "default";
   }

   if(ExtractJsonArrayStrings(response, "symbols_allowed", gAllowedSymbols))
   {
      for(int i = 0; i < ArraySize(gAllowedSymbols); i++)
         StringToUpper(gAllowedSymbols[i]);
   }
   else
   {
      ArrayResize(gAllowedSymbols, 0);
   }

   if(gSymbolMode == "custom" && ArraySize(gAllowedSymbols) == 0)
      gSymbolMode = "default";

   gSymbolSettingsLoaded = true;

   bool modeChanged  = (gSymbolMode != gLastSymbolMode);
   bool countChanged = (ArraySize(gAllowedSymbols) != gLastSymbolCount);

   if(!gSymbolConfigured)
   {
      if(!gSymbolPendingLogged)
      {
         FBLogInfo("[FlameBot][INFO] Waiting for symbol configuration");
         gSymbolPendingLogged = true;
      }
      return(true);
   }

   gSymbolPendingLogged = false;

   bool shouldSync = (modeChanged || countChanged);

   HandleSymbolFinalizationLog();

   if(shouldSync)
      SyncMarketWatchWithUserSettings();
   UpdateTradingUnlock();
   AnnounceWaitingIfNeeded();

   return(true);
}

bool FetchPSLSettings()
{
   if(!gAuthReady)
      return false;

   if(!gAccountTypeReady)
      return false;

   string url = BuildEndpointUrl("get_psl_settings");
   string body = "{" +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"platform\":\"mt5\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"account_type\":\"" + gAccountType + "\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"" +
   "}";

   string response = HttpPostJson(url, body);
   if(response == "")
   {
      if(LogEnabled(FB_LOG_DEBUG))
         FBLogDebug("[FlameBot][DEBUG] [PSL] No reply while loading PSL settings");
      return false;
   }

   string status;
   if(!ExtractJsonString(response, "status", status) || status != "OK")
   {
      FBLogError(StringFormat(
         "[FlameBot][ERROR] [PSL] Settings invalid (url=%s, %s) status='%s' body='%s'",
         FBStripUrlQuery(url),
         FBHttpDiagSummary(),
         status,
         FBHttpBodySnippet(response, 240)
      ));
      return false;
   }

   // Extract per_symbol_lots object
   string per_symbol_lots_str;
   int startPos = StringFind(response, "\"per_symbol_lots\":");
   if(startPos == -1)
   {
      FBLogWarn("[FlameBot][WARN] [PSL] No per_symbol_lots in response");
      ArrayResize(gPSLLots, 0);
      gPSLConfigured = false;
      gPSLSettingsLoaded = true;
      return true;
   }

   startPos = StringFind(response, "{", startPos);
   int endPos = StringFind(response, "}", startPos);
   if(startPos == -1 || endPos == -1)
   {
      FBLogWarn("[FlameBot][WARN] [PSL] Malformed per_symbol_lots");
      ArrayResize(gPSLLots, 0);
      gPSLConfigured = false;
      gPSLSettingsLoaded = true;
      return true;
   }

   string pslJson = StringSubstr(response, startPos + 1, endPos - startPos - 1);
   
   // Parse symbol:lot pairs
   ArrayResize(gPSLLots, 0);
   string pairs[];
   int pairCount = StringSplit(pslJson, ',', pairs);
   
   for(int i = 0; i < pairCount; i++)
   {
      string pair = pairs[i];
      int colonPos = StringFind(pair, ":");
      if(colonPos == -1)
         continue;
      
      // Extract symbol
      string symbolPart = StringSubstr(pair, 0, colonPos);
      StringReplace(symbolPart, "\"", "");
      StringReplace(symbolPart, " ", "");
      TrimString(symbolPart);
      
      // Extract lot
      string lotPart = StringSubstr(pair, colonPos + 1);
      StringReplace(lotPart, " ", "");
      TrimString(lotPart);
      double lotValue = StringToDouble(lotPart);
      
      if(symbolPart != "" && lotValue > 0)
      {
         int idx = ArraySize(gPSLLots);
         ArrayResize(gPSLLots, idx + 1);
         gPSLLots[idx].symbol = symbolPart;
         gPSLLots[idx].lot = lotValue;
      }
   }

   // Extract psl_configured flag
   string configuredStr;
   if(ExtractJsonString(response, "psl_configured", configuredStr))
   {
      StringToLower(configuredStr);
      gPSLConfigured = (configuredStr == "true" || configuredStr == "1");
   }
   else
   {
      gPSLConfigured = (ArraySize(gPSLLots) > 0);
   }

   gPSLSettingsLoaded = true;
   return true;
}

void RefreshBackendSettings()
{
   FetchLotSettings();
   FetchSymbolSettings();
   FetchPSLSettings();
   
   // Log mode activation when execution_mode changes
   if(gLotSettingsLoaded && gSymbolSettingsLoaded && gPSLSettingsLoaded)
   {
      if(gExecutionMode != gLastExecutionMode)
      {
         // CLEAR OLD STATE FIRST - prevent stale logs from previous mode
         // Reset GLS tracking
         gLastLotMode      = "";
         gLastCustomLot    = -1.0;
         gLastSymbolMode   = "";
         gLastSymbolCount  = -1;
         gLastMWMode       = "";
         gLastMWCount      = -1;
         
         // Reset PSL tracking
         gLastPSLCount     = -1;
         gPSLFinalPrinted  = false;
         
         // Reset GLS finalization state
         gLotFinalPrinted    = false;
         gSymbolFinalPrinted = false;
         gSymbolSyncDone     = false;
         
         // Now print the mode activation
         if(gExecutionMode == "gls")
            FBLogInfo("[FlameBot][INFO] GLS mode activated");
         else if(gExecutionMode == "psl")
            FBLogInfo("[FlameBot][INFO] PSL mode activated");
         
         gLastExecutionMode = gExecutionMode;
      }
      
      // Call finalization handlers (gated by execution_mode inside each handler)
      // These also handle within-mode changes (e.g., default→custom in GLS)
      HandleLotFinalizationLog();
      HandleSymbolFinalizationLog();
      HandlePSLFinalizationLog();
      
      // Sync Market Watch
      SyncMarketWatchWithUserSettings();
   }
}

bool PushSymbolsToBackend()
{
   if(gSymbolsPushedOnce)
      return(true);

   if(!gAuthReady)
      return(false);

   int total = SymbolsTotal(false);
   if(total <= 0)
   {
      FBLogError("[FlameBot][ERROR] No symbols found to push.");
      return(false);
   }

   gSymbolsPushedOnce = true;

   string payload = "{ \"user_id\": \"" + gUserId +
                    "\", \"license_key\": \"" + gLicenseKey +
                    "\", \"platform\": \"mt5\"" +
                    ", \"terminal_id\": \"" + gTerminalId + "\"" +
                    ", \"symbols\": [";

   bool first = true;
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(name == "")
         continue;

      if(!first)
         payload += ",";

      payload += "\"" + name + "\"";
      first = false;
   }
   payload += "] }";

   FBLogDebug(StringFormat("[FlameBot][DEBUG] Updating symbols list: sending %d symbols", total));

   uchar data[];
   int len = StringLen(payload);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (uchar)payload[i];

   uchar result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest(
      "POST",
      BuildEndpointUrl("push_symbols"),
      headers,
      "",
      InpRequestTimeoutMs,
      data,
      ArraySize(data),
      result,
      respHeaders
   );

   if(res == -1)
   {
      FBMarkConnectionDownOnce();
      if(LogEnabled(FB_LOG_DEBUG))
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Symbols update failed (code=%d)", GetLastError()));
      return(false);
   }

   if(ArraySize(result) == 0)
   {
      // Treat empty reply as connection-down so the loss message prints immediately.
      FBMarkConnectionDownOnce();
      FBLogError("[FlameBot][ERROR] Symbols update failed (no reply)");
      return(false);
   }

   FBMarkConnectionUpOnce();

   string response = CharArrayToString(result, 0, ArraySize(result));

   string status = "";
   if(ExtractJsonString(response, "status", status) && status == "OK")
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Symbols updated successfully (%d available)", total));
      return(true);
   }

   FBLogError("[FlameBot][ERROR] Symbols update failed: " + response);
   return(false);
}

bool SendEaHeartbeat()
{
   if(!gAuthReady)
      return(false);

   string payload =
      "{"
      "\"user_id\":\"" + gUserId + "\","
      "\"license_key\":\"" + gLicenseKey + "\","
      "\"ea_id\":\"FLAME_RUNMT5\","
      "\"platform\":\"mt5\"," 
      "\"terminal_id\":\"" + gTerminalId + "\"" 
      "}";

   uchar data[];
   int len = StringLen(payload);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (uchar)payload[i];

   uchar result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest(
      "POST",
      BuildEndpointUrl("ea/heartbeat"), // [FlameBot][INFO] FIXED
      headers,
      "",
      InpRequestTimeoutMs,
      data,
      ArraySize(data),
      result,
      respHeaders
   );

   if(res == -1)
   {
      gLastHeartbeatResponse = "Connection check failed";
      gHeartbeatSent = false;
      FBMarkConnectionDownOnce();
      return(false);
   }

   if(ArraySize(result) == 0)
   {
      gLastHeartbeatResponse = "Connection check failed (no reply)";
      gHeartbeatSent = false;
      FBMarkConnectionDownOnce();
      return(false);
   }

   string response = CharArrayToString(result, 0, ArraySize(result));
   gLastHeartbeatResponse = response;

   FBMarkConnectionUpOnce();

   string status = "";
   if(!ExtractJsonString(response, "status", status))
   {
      FBLogWarn("[FlameBot][WARN] Connection check rejected: invalid response");
      gHeartbeatSent = false;
      FBMarkConnectionUpOnce();
      return(false);
   }
   if(status == "LOGGED_OUT")
   {
      FBLogError("[FlameBot][ERROR] Session ended. Stopping EA.");
      gHeartbeatSent = false;
      FBMarkConnectionUpOnce();
      LogoutEA();
      return(false);
   }
   if(status != "OK")
   {
      FBLogWarn("[FlameBot][WARN] Connection check rejected by server");
      gHeartbeatSent = false;
      FBMarkConnectionUpOnce();
      return(false);
   }

   gHeartbeatSent = true;
   FBMarkConnectionUpOnce();

   return(true);
}

bool SendEaLogin()
{
   if(!gAuthReady)
      return(false);

   // Pre-login MUST be UNKNOWN. Never default to normal.
   gAccountType = "UNKNOWN";
   gIsPropAccount = false;
   gAccountTypeReady = false;

   string payload =
      "{"
      "\"user_id\":\"" + gUserId + "\","
      "\"license_key\":\"" + gLicenseKey + "\","
      "\"ea_id\":\"FLAME_RUNMT5\","
      "\"platform\":\"mt5\"," 
      "\"terminal_id\":\"" + gTerminalId + "\"" 
      "}";

   uchar data[];
   int len = StringLen(payload);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (uchar)payload[i];

   uchar result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest(
      "POST",
      BuildEndpointUrl("ea/login"),
      headers,
      "",
      InpRequestTimeoutMs,
      data,
      ArraySize(data),
      result,
      respHeaders
   );

   if(res == -1)
   {
      gLastHeartbeatResponse = "Login request failed";
      gLoginOk = false;
      FBLogWarn("[FlameBot][WARN] Login failed (connection)");
      FBMarkConnectionDownOnce();
      return(false);
   }

   if(ArraySize(result) == 0)
   {
      gLastHeartbeatResponse = "Empty login response";
      gLoginOk = false;
      FBMarkConnectionDownOnce();
      return(false);
   }

   string response = CharArrayToString(result, 0, ArraySize(result));
   gLastHeartbeatResponse = response;

   FBMarkConnectionUpOnce();

   string status = "";
   string message = "";
   if(!ExtractJsonString(response, "status", status))
   {
      FBLogWarn("[FlameBot][WARN] Login rejected: invalid response");
      gLoginOk = false;
      return(false);
   }
   ExtractJsonString(response, "message", message);
   if(status != "OK")
   {
      FBLogWarn("[FlameBot][WARN] Login rejected by server");
      gLoginOk = false;

      gAccountType = "UNKNOWN";
      gIsPropAccount = false;
      gAccountTypeReady = false;

      // If license already active elsewhere, stop all auto-retries until user manually logs in.
      if(status == "INVALID" && (StringFind(message, "already active") != -1 || StringFind(message, "License already active") != -1))
      {
         gLoginBlocked = true;
         gLoginBlockReason = (message == "" ? "License already active" : message);
         gLoginBlockLogged = false;
      }
      return(false);
   }

   gLoginOk = true;
   FBMarkConnectionUpOnce();
   gLoginBlocked = false;
   gLoginBlockReason = "";
   gLoginBlockLogged = false;

   // Backend is single source of truth for account_type.
   // This prevents local inputs from overriding prop/normal behavior.
   string at = "";
   if(ExtractJsonString(response, "account_type", at) || ExtractJsonString(response, "active_account_type", at))
   {
      StringToLower(at);
      if(at == "prop" || at == "normal")
      {
         gAccountType = at;
         gIsPropAccount = (at == "prop");
         gAccountTypeReady = true;
      }
   }

   // Strict requirement: treat login as failed without a valid account_type.
   if(!gAccountTypeReady)
   {
      FBLogWarn("[FlameBot][WARN] Login response missing/invalid account_type. Trading remains locked.");
      gLoginOk = false;
      return(false);
   }

   return(true);
}


//+------------------------------------------------------------------+
//| Trade handling                                                   |
//+------------------------------------------------------------------+
void RememberTradeTicket(const string signalId, ulong ticket)
{
   int idx = -1;
   for(int k = 0; k < ArraySize(gSignalTrades); k++)
   {
      if(gSignalTrades[k].signal_id == signalId)
      {
         idx = k;
         break;
      }
   }
   if(idx == -1)
   {
      idx = ArraySize(gSignalTrades);
      ArrayResize(gSignalTrades, idx + 1);
      gSignalTrades[idx].signal_id = signalId;
      ArrayResize(gSignalTrades[idx].tickets, 0);
   }

   // Avoid duplicates (important when backfilling from live positions/orders)
   for(int i = 0; i < ArraySize(gSignalTrades[idx].tickets); i++)
   {
      if(gSignalTrades[idx].tickets[i] == ticket)
         return;
   }

   int tsz = ArraySize(gSignalTrades[idx].tickets);
   ArrayResize(gSignalTrades[idx].tickets, tsz + 1);
   gSignalTrades[idx].tickets[tsz] = ticket;
}

bool HasAnyActiveTradeOnSymbol(const string symbol)
{
   // Check open positions
   int ptotal = PositionsTotal();
   for(int i = 0; i < ptotal; i++)
   {
      ulong pticket = PositionGetTicket(i);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(psym == symbol && (int)pmagic == gMagicNumber)
         return(true);
   }

   // Check pending orders
   int ototal = OrdersTotal();
   for(int j = 0; j < ototal; j++)
   {
      ulong oticket = OrderGetTicket(j);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      string osym = (string)OrderGetString(ORDER_SYMBOL);
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      if(osym == symbol && (int)omagic == gMagicNumber)
         return(true);
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Trade State Reporting (for state-aware AI decisions)             |
//+------------------------------------------------------------------+
bool GetSymbolTradeState(const string symbol, bool &has_pending, bool &has_active, string &direction, 
                         double &entry_price, double &sl_price, string &signal_id)
{
   has_pending = false;
   has_active = false;
   direction = "";
   entry_price = 0;
   sl_price = 0;
   signal_id = "";
   
   // Check open positions
   int ptotal = PositionsTotal();
   for(int i = 0; i < ptotal; i++)
   {
      ulong pticket = PositionGetTicket(i);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(psym != symbol || (int)pmagic != gMagicNumber)
         continue;
      
      has_active = true;
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      direction = (ptype == POSITION_TYPE_BUY) ? "buy" : "sell";
      entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      sl_price = PositionGetDouble(POSITION_SL);
      signal_id = ExtractSignalIdFromComment(PositionGetString(POSITION_COMMENT));
   }

   // Check pending orders
   int ototal = OrdersTotal();
   for(int j = 0; j < ototal; j++)
   {
      ulong oticket = OrderGetTicket(j);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      string osym = OrderGetString(ORDER_SYMBOL);
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      if(osym != symbol || (int)omagic != gMagicNumber)
         continue;
      
      has_pending = true;
      if(direction == "")  // Only set if not already set by active trade
      {
         ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         direction = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_BUY_STOP) ? "buy" : "sell";
         entry_price = OrderGetDouble(ORDER_PRICE_OPEN);
         sl_price = OrderGetDouble(ORDER_SL);
         signal_id = ExtractSignalIdFromComment(OrderGetString(ORDER_COMMENT));
      }
   }
   
   return(has_pending || has_active);
}

bool PushTradeStateToBackend(const string symbol)
{
   if(!gAuthReady || symbol == "")
      return(false);
   
   bool has_pending = false;
   bool has_active = false;
   string direction = "";
   double entry_price = 0;
   double sl_price = 0;
   string signal_id = "";
   string open_positions_json = "[]";
   
   GetSymbolTradeState(symbol, has_pending, has_active, direction, entry_price, sl_price, signal_id);

   open_positions_json = BuildOpenPositionsJson();
   
   // Build JSON payload
   string payload = "{" +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"platform\":\"mt5\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"," +
      "\"symbol\":\"" + symbol + "\"," +
      "\"has_pending_order\":" + (has_pending ? "true" : "false") + "," +
      "\"has_active_trade\":" + (has_active ? "true" : "false") + "," +
      "\"direction\":\"" + direction + "\"," +
      "\"entry_price\":" + DoubleToString(entry_price, 5) + "," +
      "\"sl\":" + DoubleToString(sl_price, 5) + "," +
      "\"signal_id\":\"" + signal_id + "\"," +
      "\"open_positions\":" + open_positions_json +
   "}";
   
   char data[];
   int len = StringLen(payload);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (char)StringGetCharacter(payload, i);
   
   char result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   
   int res = WebRequest(
      "POST",
      BuildEndpointUrl("ea/push_trade_state"),
      headers,
      InpRequestTimeoutMs,
      data,
      result,
      respHeaders
   );
   
   if(res == -1)
   {
      FBMarkConnectionDownOnce();
      FBLogWarn("[FlameBot][WARN] Failed to push trade state for " + symbol);
      return(false);
   }

   FBMarkConnectionUpOnce();

   if(InpLogTradeStatePushes)
   {
      string resp = "";
      if(ArraySize(result) > 0)
         resp = CharArrayToString(result, 0, ArraySize(result));
      if(StringLen(resp) > 160)
         resp = StringSubstr(resp, 0, 160) + "...";
      if(LogEnabled(FB_LOG_DEBUG))
         FBLogDebug(StringFormat("[FlameBot][DEBUG] State update sent | symbol=%s | reply=%s", symbol, resp));
   }

   if((InpLogTradeStatePushes || !gTradeStateLogPrinted) && LogEnabled(FB_LOG_DEBUG))
   {
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Trade state pushed | symbol=%s | pending=%s | active=%s",
                              symbol, has_pending ? "Y" : "N", has_active ? "Y" : "N"));
      if(!InpLogTradeStatePushes)
         gTradeStateLogPrinted = true;
   }
   return(true);
}

void ExecuteClosePending(const string symbol, const string signal_id, const string group_id)
{
   FBLogInfo(StringFormat("[FlameBot][INFO] CLOSE_PENDING | symbol=%s | signal_id=%s | group_id=%s", symbol, signal_id, group_id));
   
   int cancelled = 0;
   int ototal = OrdersTotal();
   
   for(int i = ototal - 1; i >= 0; i--)
   {
      ulong oticket = OrderGetTicket(i);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      if((int)omagic != gMagicNumber)
         continue;
      
      // Symbol filter
      if(symbol != "" && OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      
      string orderComment = OrderGetString(ORDER_COMMENT);
      
      // Signal/Group matching - require exact signal_id match extracted from comment
      if(StringLen(signal_id) > 0)
      {
         string found = ExtractSignalIdFromComment(orderComment);
         if(StringLen(found) == 0 || found != signal_id)
            continue;
      }
      
      if(StringLen(group_id) > 0)
      {
         bool hasGroupMatch = false;
         string parsed = ExtractGroupIdFromComment(orderComment);
         if(StringLen(parsed) > 0 && parsed == group_id)
            hasGroupMatch = true;
         else
         {
            // Fallback: derive group from signal token (format chat_id:msg_id)
            string sig = ExtractSignalIdFromComment(orderComment);
            int colon = StringFind(sig, ":");
            if(colon > 0)
            {
               string derived = StringSubstr(sig, 0, colon);
               if(derived == group_id)
                  hasGroupMatch = true;
            }
         }
         if(!hasGroupMatch)
            continue;
      }
      
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      
      req.action = TRADE_ACTION_REMOVE;
      req.order = oticket;
      
      if(!OrderSend(req, res))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Failed to delete pending | ticket=%d | error=%d", oticket, GetLastError()));
         continue;
      }
      
      cancelled++;
      FBLogInfo(StringFormat("[FlameBot][INFO] Pending cancelled | ticket=%d | symbol=%s", oticket, OrderGetString(ORDER_SYMBOL)));
   }
   
   if(cancelled > 0)
      FBLogInfo(StringFormat("[FlameBot][INFO] CLOSE_PENDING complete | cancelled=%d", cancelled));
   else
      FBLogInfo("[FlameBot][INFO] No pending orders found to cancel");
}

void PushAllTradeStatesToBackend()
{
   if(!gAuthReady)
      return;
   
   // Collect all unique symbols with active trades/orders
   string activeSymbols[];
   int symbolCount = 0;
   
   // Check positions
   int ptotal = PositionsTotal();
   for(int i = 0; i < ptotal; i++)
   {
      ulong pticket = PositionGetTicket(i);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      if((int)pmagic != gMagicNumber)
         continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      
      // Check if symbol already in array
      bool found = false;
      for(int j = 0; j < symbolCount; j++)
      {
         if(activeSymbols[j] == sym)
         {
            found = true;
            break;
         }
      }
      
      if(!found)
      {
         ArrayResize(activeSymbols, symbolCount + 1);
         activeSymbols[symbolCount] = sym;
         symbolCount++;
      }
   }
   
   // Check pending orders
   int ototal = OrdersTotal();
   for(int i = 0; i < ototal; i++)
   {
      ulong oticket = OrderGetTicket(i);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      if((int)omagic != gMagicNumber)
         continue;
      
      string sym = OrderGetString(ORDER_SYMBOL);
      
      // Check if symbol already in array
      bool found = false;
      for(int j = 0; j < symbolCount; j++)
      {
         if(activeSymbols[j] == sym)
         {
            found = true;
            break;
         }
      }
      
      if(!found)
      {
         ArrayResize(activeSymbols, symbolCount + 1);
         activeSymbols[symbolCount] = sym;
         symbolCount++;
      }
   }
   
   // Push state for each active symbol
   for(int i = 0; i < symbolCount; i++)
   {
      PushTradeStateToBackend(activeSymbols[i]);
   }

   // CRITICAL: if there are no active symbols, still push one snapshot.
   // Otherwise the backend never receives the empty open_positions[] after the last trade closes.
   if(symbolCount == 0)
   {
      string fallback = Symbol();
      if(fallback == "")
         fallback = _Symbol;
      if(fallback != "")
         PushTradeStateToBackend(fallback);
   }
   
   if(symbolCount > 0 && (InpLogTradeStatePushes || !gTradeStatesSummaryPrinted) && LogEnabled(FB_LOG_DEBUG))
   {
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Trade states pushed | symbols=%d", symbolCount));
      if(!InpLogTradeStatePushes)
         gTradeStatesSummaryPrinted = true;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!gAuthReady)
      return;
   if(gLoginBlocked || !gLoginOk || !gAccountTypeReady)
      return;

   ulong now = GetTickCount64();
   if(gLastTradeTxnPushMs > 0 && (now - gLastTradeTxnPushMs) < (ulong)gTradeTxnPushThrottleMs)
   {
      // MT5 can emit multiple trade transactions during a close.
      // If we throttle the *final* one (where the position is gone), the UI can show a ghost trade.
      gTradeTxnPushPending = true;
      if(gTradeTxnPushPendingSinceMs == 0)
         gTradeTxnPushPendingSinceMs = now;
      return;
   }
   gLastTradeTxnPushMs = now;
   gTradeTxnPushPending = false;
   gTradeTxnPushPendingSinceMs = 0;

   PushAllTradeStatesToBackend();
}

bool PlaceTrades(const Signal &signal, const string userTag, bool isPropAccount, const string group_id="")
{
   if(StringLen(group_id) == 0 || group_id == "0")
   {
      FBLogError("[FlameBot][ERROR] Signal rejected: missing group id");
      return(false);
   }
   if(!gTradingUnlocked)
   {
      FBLogWarn("[FlameBot][WARN] Trading locked: waiting for Desktop App settings (lot & symbols)");
      return(false);
   }

   string symbol = MatchSymbol(signal.pair);
   if(symbol == "")
   {
      FBLogError("[FlameBot][ERROR] Symbol not found from pair: " + signal.pair);
      return(false);
   }

   if(!EnsureSymbolEnabledAndAllowed(symbol))
   {
      FBLogWarn(StringFormat("[FlameBot][WARN] Trade aborted - symbol not ready: %s", symbol));
      return(false);
   }

   // Enforce single-signal-per-symbol rule when disabled
   if(!gAllowMultipleSignalsPerSymbol)
   {
      if(HasAnyActiveTradeOnSymbol(symbol))
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Signal ignored: %s already has an active signal (multiple signals disabled)", symbol));
         return(false);
      }
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      FBLogError("[FlameBot][ERROR] Failed to get price for " + symbol);
      return(false);
   }
   if(LogEnabled(FB_LOG_DEBUG))
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Tick | symbol=%s | bid=%.5f | ask=%.5f | last=%.5f | time=%s",
                              symbol, tick.bid, tick.ask, tick.last, TimeToString((datetime)tick.time, TIME_DATE|TIME_SECONDS)));

   string typeLower = signal.type;
   StringToLower(typeLower);
   bool isBuy = (StringFind(typeLower, "buy") == 0);

   double current_price = isBuy ? tick.ask : tick.bid;
   
   // Entry range logic
   bool hasEntryRange = signal.hasEntry2;
   double entry1 = signal.hasEntry ? signal.entry : current_price;   // Primary entry (TP1)
   double entry2 = signal.hasEntry2 ? signal.entry2 : entry1;        // Secondary entry (TP2)
   
   // Determine order type for TP1 based on price position
   ENUM_ORDER_TYPE order_type_tp1;
   if(hasEntryRange)
   {
      // Normalize bounds for range logic
      double low  = MathMin(entry1, entry2);
      double high = MathMax(entry1, entry2);

      if(isBuy)
      {
         if(current_price > high)
         {
            // Above top: both legs should be pending at the entries
            order_type_tp1 = GetSmartOrderType(true, entry1, current_price);
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f above range [%.5f-%.5f]: TP1=Pending@%.5f, TP2=Pending@%.5f", current_price, low, high, entry1, entry2));
         }
         else if(current_price >= low && current_price <= high)
         {
            // Inside band: TP1 market, TP2 pending at other entry
            order_type_tp1 = ORDER_TYPE_BUY;
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f in range [%.5f-%.5f]: TP1=Market, TP2=Pending@%.5f", current_price, low, high, entry2));
         }
         else // current_price < low
         {
            // Below band: allow market on TP1, TP2 pending at other entry
            order_type_tp1 = ORDER_TYPE_BUY;
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f below range [%.5f-%.5f]: TP1=Market, TP2=Pending@%.5f", current_price, low, high, entry2));
         }
      }
      else // SELL
      {
         if(current_price < low)
         {
            // Below bottom: both legs pending at entries
            order_type_tp1 = GetSmartOrderType(false, entry1, current_price);
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f below range [%.5f-%.5f]: TP1=Pending@%.5f, TP2=Pending@%.5f", current_price, low, high, entry1, entry2));
         }
         else if(current_price >= low && current_price <= high)
         {
            // Inside band: TP1 market, TP2 pending at other entry
            order_type_tp1 = ORDER_TYPE_SELL;
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f in range [%.5f-%.5f]: TP1=Market, TP2=Pending@%.5f", current_price, low, high, entry2));
         }
         else // current_price > high
         {
            // Above top: both legs pending at entries (with correct type)
            order_type_tp1 = GetSmartOrderType(false, entry1, current_price);
            FBLogInfo(StringFormat("[FlameBot][INFO] Price %.5f above range [%.5f-%.5f]: TP1=Pending@%.5f, TP2=Pending@%.5f", current_price, low, high, entry1, entry2));
         }
      }
   }
   else
   {
      // Single-entry signals: default to MARKET; use pending only if text explicitly contains 'limit' or 'stop'
      bool explicitPending = (StringFind(typeLower, "limit") != -1 || StringFind(typeLower, "stop") != -1);
      if(explicitPending)
      {
         // Respect explicit pending keyword strictly
         bool wantLimit = (StringFind(typeLower, "limit") != -1);
         bool wantStop  = (StringFind(typeLower, "stop")  != -1);
         if(isBuy)
            order_type_tp1 = wantLimit ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
         else
            order_type_tp1 = wantLimit ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;

         if(!IsPendingOrderPriceValid(order_type_tp1, entry1, current_price))
         {
            FBLogError(StringFormat("[FlameBot][ERROR] Explicit pending type conflicts with price relation | type=%d entry=%.5f current=%.5f", (int)order_type_tp1, entry1, current_price));
            return(false);
         }

         if(order_type_tp1 == ORDER_TYPE_BUY_LIMIT)
            FBLogInfo(StringFormat("[FlameBot][INFO] Single-entry (explicit limit): BUY LIMIT @ %.5f (current=%.5f)", entry1, current_price));
         else if(order_type_tp1 == ORDER_TYPE_BUY_STOP)
            FBLogInfo(StringFormat("[FlameBot][INFO] Single-entry (explicit stop): BUY STOP @ %.5f (current=%.5f)", entry1, current_price));
         else if(order_type_tp1 == ORDER_TYPE_SELL_LIMIT)
            FBLogInfo(StringFormat("[FlameBot][INFO] Single-entry (explicit limit): SELL LIMIT @ %.5f (current=%.5f)", entry1, current_price));
         else if(order_type_tp1 == ORDER_TYPE_SELL_STOP)
            FBLogInfo(StringFormat("[FlameBot][INFO] Single-entry (explicit stop): SELL STOP @ %.5f (current=%.5f)", entry1, current_price));
      }
      else
      {
         order_type_tp1 = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         FBLogInfo(StringFormat("[FlameBot][INFO] Single-entry: Using MARKET order (entry=%.5f, current=%.5f)", entry1, current_price));
      }
   }
   
   // Legacy variable for backward compatibility
   ENUM_ORDER_TYPE order_type = order_type_tp1;
   double entry_price = entry1;

   // Get first SL for validation (individual SLs are assigned per TP during trade placement)
   double sl = (signal.hasSL && ArraySize(signal.sls) > 0) ? signal.sls[0] : 0.0;

   // 🔥 CRITICAL: Create clean TP array (remove any entry prices that leaked in)
   double cleanTPs[];
   ArrayResize(cleanTPs, 0);
   
   if(signal.hasEntry || signal.hasEntry2)
   {
      for(int i = 0; i < ArraySize(signal.tps); i++)
      {
         double tp = signal.tps[i];
         bool isEntry = false;
         
         if(signal.hasEntry && MathAbs(tp - signal.entry) < 0.0001)
            isEntry = true;
         if(signal.hasEntry2 && MathAbs(tp - signal.entry2) < 0.0001)
            isEntry = true;
         
         if(!isEntry)
         {
            int sz = ArraySize(cleanTPs);
            ArrayResize(cleanTPs, sz + 1);
            cleanTPs[sz] = tp;
         }
         else
         {
            FBLogDebug(StringFormat("[FlameBot][DEBUG] CRITICAL: Removed entry price %.5f from TP array (was incorrectly added as TP%d)", tp, i+1));
         }
      }
   }
   else
   {
      // No entry range: copy all TPs
      ArrayResize(cleanTPs, ArraySize(signal.tps));
      ArrayCopy(cleanTPs, signal.tps);
   }
   
   // Debug: Show final TP array
   if(LogEnabled(FB_LOG_DEBUG))
   {
      string tpDebug = "";
      for(int d = 0; d < ArraySize(cleanTPs); d++)
      {
         tpDebug += DoubleToString(cleanTPs[d], 5);
         if(d < ArraySize(cleanTPs) - 1)
            tpDebug += ", ";
      }
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Final TP array for validation: [%s]", tpDebug));
   }

   // 🔥 CRITICAL FIX: Resolve final entry price for TP1 BEFORE validation
   // If TP1 is MARKET, use current_price for validation
   // If TP1 is LIMIT/STOP, use entry1 for validation
   double validation_entry_price = entry_price;
   if(order_type_tp1 == ORDER_TYPE_BUY || order_type_tp1 == ORDER_TYPE_SELL)
   {
      // TP1 will execute at market → use current price for validation
      validation_entry_price = current_price;
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Validation: Using market price %.5f (TP1 is market order)", validation_entry_price));
   }
   else
   {
      // TP1 is pending → use entry1 for validation
      validation_entry_price = entry1;
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Validation: Using entry price %.5f (TP1 is pending order)", validation_entry_price));
   }

   // Validate using cleanTPs (not signal.tps - which may have entry prices)
   Signal validationSignal = signal;
   ArrayResize(validationSignal.tps, ArraySize(cleanTPs));
   ArrayCopy(validationSignal.tps, cleanTPs);

   if(!IsSignalValid(validationSignal, isBuy, validation_entry_price, sl))
   {
      FBLogError("[FlameBot][ERROR] Signal rejected by validation.");
      return(false);
   }

   double lot = 0.0;
   if(!DetermineLotSize(symbol, isPropAccount, validation_entry_price, sl, lot))
      return(false);

   // USD-based deviation rejection applies ONLY to MARKET orders (never to LIMIT/STOP)
   bool isMarketOrder = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_SELL);
   if(isMarketOrder)
   {
      // Single-entry with explicit entry: compare against entry price
      if(signal.hasEntry && !signal.hasEntry2)
      {
         if(HasPriceMovedTooFar(symbol, isBuy, current_price, entry1, lot))
            return(false);
      }
      // No entry provided: pure market signal → compare current vs current (no-op path retained)
      else if(!signal.hasEntry && !signal.hasEntry2)
      {
         if(HasPriceMovedTooFar(symbol, isBuy, current_price, current_price, lot))
            return(false);
      }
      // Range signals (hasEntry2) may have market TP1 inside band; pending TP2 unaffected
   }
   else
   {
      // Pending orders: skip deviation check entirely
      FBLogInfo("[FlameBot][INFO] Skipping deviation check for pending order (LIMIT/STOP).");
   }

   trade.SetExpertMagicNumber(gMagicNumber);

   double placedTPs[];
   ArrayResize(placedTPs, 0);

   // Debug: show parsed TP slots (including tp: open -> 0.0)
   int tpCountDbg = ArraySize(cleanTPs);
   string tpListDbg = "";
   for(int dbg = 0; dbg < tpCountDbg; dbg++)
   {
      tpListDbg += DoubleToString(cleanTPs[dbg], 5);
      if(dbg < tpCountDbg - 1)
         tpListDbg += ",";
   }
   FBLogDebug(StringFormat("[FlameBot][DEBUG] Parsed TPs count=%d [%s]", tpCountDbg, tpListDbg));

   // Debug: show parsed SL slots (multiple SL support)
   int slCountDbg = ArraySize(signal.sls);
   string slListDbg = "";
   for(int sdbg = 0; sdbg < slCountDbg; sdbg++)
   {
      slListDbg += DoubleToString(signal.sls[sdbg], 5);
      if(sdbg < slCountDbg - 1)
         slListDbg += ",";
   }
   FBLogDebug(StringFormat("[FlameBot][DEBUG] Parsed SLs count=%d [%s]", slCountDbg, slListDbg));

   // Handle case: no TPs (tp: open)
   if(ArraySize(cleanTPs) == 0)
   {
      // Place group first to avoid truncation chopping the group id
      string comment = (StringLen(group_id) > 0)
         ? StringFormat("g%s|s%s", group_id, userTag)
         : StringFormat("sig_%s", userTag);
      trade.SetExpertMagicNumber(gMagicNumber);
      bool result = false;
      
      if(order_type == ORDER_TYPE_BUY)
      {
         result = trade.Buy(lot, symbol, 0, sl, 0, comment);
      }
      else if(order_type == ORDER_TYPE_SELL)
      {
         result = trade.Sell(lot, symbol, 0, sl, 0, comment);
      }
      else if(order_type == ORDER_TYPE_BUY_LIMIT)
      {
         result = trade.BuyLimit(lot, entry_price, symbol, sl, 0, 0, 0, comment);
      }
      else if(order_type == ORDER_TYPE_SELL_LIMIT)
      {
         result = trade.SellLimit(lot, entry_price, symbol, sl, 0, 0, 0, comment);
      }
      else if(order_type == ORDER_TYPE_BUY_STOP)
      {
         result = trade.BuyStop(lot, entry_price, symbol, sl, 0, 0, 0, comment);
      }
      else if(order_type == ORDER_TYPE_SELL_STOP)
      {
         result = trade.SellStop(lot, entry_price, symbol, sl, 0, 0, 0, comment);
      }

      if(result)
      {
         ulong ticket = trade.ResultOrder();
         FBLogInfo(StringFormat("[FlameBot][INFO] Trade placed: %s %s | SL=%.5f | TP=open | Lot=%.2f", signal.type, symbol, sl, lot));
         RememberTradeTicket(userTag, ticket);
         bool pushed = PushTradeStateToBackend(symbol);
         if(InpLogTradeStatePushes && LogEnabled(FB_LOG_DEBUG))
            FBLogDebug(StringFormat("[FlameBot][DEBUG] Trade state push (order_placed) | symbol=%s | %s", symbol, pushed ? "OK" : "FAILED"));
         return(true);
      }
      else
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Trade failed: %s", GetLastError()));
         return(false);
      }
   }

   for(int i = 0; i < ArraySize(cleanTPs); i++)
   {
      double tp_price = cleanTPs[i];

      // 🔥 Determine SL for this specific TP (multiple SL support)
      // Match SL index with TP index: sl1->tp1, sl2->tp2, etc.
      // If fewer SLs than TPs, use the last available SL
      double tp_sl = 0.0;
      if(signal.hasSL && ArraySize(signal.sls) > 0)
      {
         if(i < ArraySize(signal.sls))
            tp_sl = signal.sls[i];           // Use matching SL for this TP
         else
            tp_sl = signal.sls[ArraySize(signal.sls) - 1];  // Use last SL if not enough
      }

      // Determine order type and entry for this specific TP first
      ENUM_ORDER_TYPE tp_order_type;
      double tp_entry_price;
      
      if(hasEntryRange)
      {
         // Entry range logic:
         // TP1 (i==0): Use order_type_tp1 and entry1
         // TP2+ (i>=1): Pending entry determined by entry_mode
         if(i == 0)
         {
            tp_order_type = order_type_tp1;
            tp_entry_price = entry1;
         }
         else
         {
            double low = MathMin(entry1, entry2);
            double high = MathMax(entry1, entry2);
            if(gEntryMode == "market_edge")
            {
               double edgePrice = (isBuy ? low : high);
               tp_order_type = GetSmartOrderType(isBuy, edgePrice, current_price);
               tp_entry_price = edgePrice;
               if(isBuy)
               {
                  if(edgePrice > current_price)
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: BUY STOP @ %.5f (current=%.5f)", edgePrice, current_price));
                  else
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: BUY LIMIT @ %.5f (current=%.5f)", edgePrice, current_price));
               }
               else
               {
                  if(edgePrice < current_price)
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: SELL STOP @ %.5f (current=%.5f)", edgePrice, current_price));
                  else
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: SELL LIMIT @ %.5f (current=%.5f)", edgePrice, current_price));
               }
            }
            else // range_distributed
            {
               int totalPending = MathMax(1, ArraySize(cleanTPs) - 1);
               double fraction = (double)i / (double)totalPending;
               double distPrice = low + fraction * (high - low);
               tp_order_type = GetSmartOrderType(isBuy, distPrice, current_price);
               tp_entry_price = distPrice;
               if(isBuy)
               {
                  if(distPrice > current_price)
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: BUY STOP @ %.5f (current=%.5f)", distPrice, current_price));
                  else
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: BUY LIMIT @ %.5f (current=%.5f)", distPrice, current_price));
               }
               else
               {
                  if(distPrice < current_price)
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: SELL STOP @ %.5f (current=%.5f)", distPrice, current_price));
                  else
                     FBLogDebug(StringFormat("[FlameBot][DEBUG] TP resolved: SELL LIMIT @ %.5f (current=%.5f)", distPrice, current_price));
               }
            }
         }
      }
      else
      {
         tp_order_type = order_type;
         tp_entry_price = entry_price;
      }

      // Validation: only market orders must pass profitability; pending orders are exempt
      if(tp_price > 0.0)
      {
         // Allow duplicate TPs - place separate trades for each TP level

         if(signal.hasSL && tp_sl > 0.0)
         {
            if(isBuy && tp_price <= tp_sl)
            {
               FBLogError(StringFormat("[FlameBot][ERROR] TP%d skipped: TP <= SL for BUY (SL=%.5f)", i+1, tp_sl));
               continue;
            }
            if(!isBuy && tp_price >= tp_sl)
            {
               FBLogError(StringFormat("[FlameBot][ERROR] TP%d skipped: TP >= SL for SELL (SL=%.5f)", i+1, tp_sl));
               continue;
            }
         }

         // Profitability check applies ONLY to single-entry market orders; range signals are exempt
         if((tp_order_type == ORDER_TYPE_BUY || tp_order_type == ORDER_TYPE_SELL) && signal.hasEntry && !signal.hasEntry2)
         {
            if(!IsTradeProfitableEnough(symbol, isBuy, current_price, tp_price, lot))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] TP%d skipped: not profitable enough (single-entry market)", i+1));
               continue;
            }
         }
      } // End validation block

      bool ok = false;
      // Build canonical comment (preferred format)
      string comment = StringFormat("tp%d|g%s|s%s", i+1, group_id, userTag);
      // If comment exceeds MT5's 31-char limit, choose a compact alternate
      // that preserves BOTH full signal_id and full group_id by shortening the TP token.
      // Compact format: s{signal}|g{group}|t{N} → fits within 31 chars for typical ids.
      if(StringLen(comment) > 31)
      {
         string alt = StringFormat("s%s|g%s|t%d", userTag, group_id, i+1);
         comment = alt;
      }

      if(tp_order_type == ORDER_TYPE_BUY)
         ok = trade.Buy(lot, symbol, current_price, tp_sl, tp_price, comment);
      else if(tp_order_type == ORDER_TYPE_SELL)
         ok = trade.Sell(lot, symbol, current_price, tp_sl, tp_price, comment);
      else if(tp_order_type == ORDER_TYPE_BUY_LIMIT)
         ok = trade.BuyLimit(lot, tp_entry_price, symbol, tp_sl, tp_price, ORDER_TIME_GTC, 0, comment);
      else if(tp_order_type == ORDER_TYPE_SELL_LIMIT)
         ok = trade.SellLimit(lot, tp_entry_price, symbol, tp_sl, tp_price, ORDER_TIME_GTC, 0, comment);
      else if(tp_order_type == ORDER_TYPE_BUY_STOP)
         ok = trade.BuyStop(lot, tp_entry_price, symbol, tp_sl, tp_price, ORDER_TIME_GTC, 0, comment);
      else if(tp_order_type == ORDER_TYPE_SELL_STOP)
         ok = trade.SellStop(lot, tp_entry_price, symbol, tp_sl, tp_price, ORDER_TIME_GTC, 0, comment);

      if(ok)
      {
         if(tp_price > 0.0)
            FBLogInfo(StringFormat("[FlameBot][INFO] TP%d placed: %s %s | SL=%.5f | TP=%.5f | Lot=%.2f", i+1, signal.type, symbol, tp_sl, tp_price, lot));
         else
            FBLogInfo(StringFormat("[FlameBot][INFO] TP%d placed: %s %s | SL=%.5f | TP=open | Lot=%.2f", i+1, signal.type, symbol, tp_sl, lot));
         RememberTradeTicket(userTag, trade.ResultOrder());

         // Push state after each successful leg so backend sees pending/active immediately.
         bool pushedLeg = PushTradeStateToBackend(symbol);
         if(InpLogTradeStatePushes && LogEnabled(FB_LOG_DEBUG))
            FBLogDebug(StringFormat("[FlameBot][DEBUG] Trade state push (tp%d_placed) | symbol=%s | %s", i+1, symbol, pushedLeg ? "OK" : "FAILED"));

         int sz = ArraySize(placedTPs);
         ArrayResize(placedTPs, sz+1);
         placedTPs[sz] = tp_price;
      }
      else
      {
         FBLogError(StringFormat("[FlameBot][ERROR] TP%d failed: %s", i+1, trade.ResultComment()));
      }
   }

   return(ArraySize(placedTPs) > 0);
}

void ModifyExistingTrades(const Signal &signal, const string targetSignalId)
{
   for(int i = 0; i < ArraySize(gSignalTrades); i++)
   {
      if(gSignalTrades[i].signal_id != targetSignalId)
         continue;

      for(int j = 0; j < ArraySize(gSignalTrades[i].tickets); j++)
      {
         ulong ticket = gSignalTrades[i].tickets[j];
         if(!PositionSelectByTicket(ticket))
            continue;

         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         int tradeIndex = j + 1;  // 1-based index (trade 1, trade 2, etc.)

         bool changed = false;

         // === APPLY SL UPDATES ===
         if(signal.hasSL && ArraySize(signal.sls) > 0)
         {
            for(int s = 0; s < ArraySize(signal.sls); s++)
            {
               int targetIdx = signal.sl_indices[s];
               
               // -1 means apply to ALL trades, or match specific index
               if(targetIdx == -1 || targetIdx == tradeIndex)
               {
                  sl = signal.sls[s];
                  changed = true;
                  if(targetIdx == -1)
                     FBLogInfo(StringFormat("[FlameBot] Trade %d: Applying SL=%.5f (ALL)", tradeIndex, sl));
                  else
                     FBLogInfo(StringFormat("[FlameBot] Trade %d: Applying SL=%.5f (indexed)", tradeIndex, sl));
                  break;  // Apply first matching SL
               }
            }
         }

         // === APPLY TP UPDATES ===
         if(ArraySize(signal.tps) > 0)
         {
            for(int t = 0; t < ArraySize(signal.tps); t++)
            {
               int targetIdx = signal.tp_indices[t];
               
               // -1 means apply to ALL trades, or match specific index
               if(targetIdx == -1 || targetIdx == tradeIndex)
               {
                  tp = signal.tps[t];
                  changed = true;
                  if(targetIdx == -1)
                     FBLogInfo(StringFormat("[FlameBot] Trade %d: Applying TP=%.5f (ALL)", tradeIndex, tp));
                  else
                     FBLogInfo(StringFormat("[FlameBot] Trade %d: Applying TP=%.5f (indexed)", tradeIndex, tp));
                  break;  // Apply first matching TP
               }
            }
         }

         if(changed)
         {
            trade.PositionModify(ticket, sl, tp);
            FBLogInfo(StringFormat("[FlameBot] Updated trade %I64u (index %d) | SL=%.2f | TP=%.2f", ticket, tradeIndex, sl, tp));
         }
      }
   }
}

bool HasTradesForSignal(const string signalId)
{
   if(StringLen(signalId) == 0)
      return(false);

   // Fast path: in-memory mapping
   for(int i = 0; i < ArraySize(gSignalTrades); i++)
   {
      if(gSignalTrades[i].signal_id == signalId && ArraySize(gSignalTrades[i].tickets) > 0)
         return(true);
   }

   // Restart-safe path: scan live positions and pending orders and backfill mapping.
   bool found = false;
   int ptotal = PositionsTotal();
   for(int pi = 0; pi < ptotal; pi++)
   {
      ulong pt = PositionGetTicket(pi);
      if(pt == 0)
         continue;
      if(!PositionSelectByTicket(pt))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         continue;

      string pc = PositionGetString(POSITION_COMMENT);
      string extracted = ExtractSignalIdFromComment(pc);
      if(extracted == signalId || StringFind(pc, signalId) >= 0)
      {
         RememberTradeTicket(signalId, pt);
         found = true;
      }
   }

   int ototal = OrdersTotal();
   for(int oi = 0; oi < ototal; oi++)
   {
      ulong ot = OrderGetTicket(oi);
      if(ot == 0)
         continue;
      if(!OrderSelect(ot))
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != gMagicNumber)
         continue;

      string oc = OrderGetString(ORDER_COMMENT);
      string extracted = ExtractSignalIdFromComment(oc);
      if(extracted == signalId || StringFind(oc, signalId) >= 0)
      {
         found = true;
      }
   }

   if(found)
      return(true);

   return(false);
}

//+------------------------------------------------------------------+
//| Networking helper                                                |
//+------------------------------------------------------------------+
string FBStripUrlQuery(const string url)
{
   int q = StringFind(url, "?");
   if(q < 0)
      return url;
   return StringSubstr(url, 0, q);
}

//--- Last HTTP request diagnostics (best-effort)
int    gLastHttpStatus = 0;
int    gLastWebRequestError = 0;
string gLastHttpRespHeaders = "";
string gLastHttpUrl = "";
string gLastHttpMethod = "";

string FBHttpStatusLine(const string headers)
{
   string h = headers;
   int n = StringFind(h, "\n");
   if(n < 0)
      n = StringLen(h);
   string line = StringSubstr(h, 0, n);
   StringReplace(line, "\r", "");
   StringReplace(line, "\n", "");
   TrimString(line);
   return line;
}

string FBHttpBodySnippet(const string body, const int maxLen)
{
   string s = body;
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   TrimString(s);
   if(maxLen > 0 && StringLen(s) > maxLen)
      s = StringSubstr(s, 0, maxLen) + "...";
   return s;
}

string FBHttpDiagSummary()
{
   string line = FBHttpStatusLine(gLastHttpRespHeaders);
   if(line != "")
      return StringFormat("http=%d last_error=%d (%s)", gLastHttpStatus, gLastWebRequestError, line);
   return StringFormat("http=%d last_error=%d", gLastHttpStatus, gLastWebRequestError);
}

string HttpGet(const string url)
{
   uchar post[];
   uchar result[];
   string respHeaders = "";

   gLastHttpMethod = "GET";
   gLastHttpUrl = FBStripUrlQuery(url);
   gLastHttpRespHeaders = "";
   gLastWebRequestError = 0;
   gLastHttpStatus = 0;

   int res = WebRequest("GET", url, "", "", InpRequestTimeoutMs, post, 0, result, respHeaders);
   gLastHttpStatus = res;
   gLastHttpRespHeaders = respHeaders;

   if(res == -1)
   {
      gLastWebRequestError = GetLastError();
      FBMarkConnectionDownOnce();
      return "";
   }

   if(ArraySize(result) == 0)
   {
      // Force connection-down on empty body so the user always sees the connection-lost log
      // before any subsequent "empty response" error logs.
      FBMarkConnectionDownOnce();
      return "";
   }
   // MT4 mirror: mark restored only when there is a non-empty response body.
   FBMarkConnectionUpOnce();
   return CharArrayToString(result, 0, ArraySize(result));
}

string HttpPostJson(const string url, const string jsonBody)
{
   uchar data[];
   uchar result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";

   gLastHttpMethod = "POST";
   gLastHttpUrl = FBStripUrlQuery(url);
   gLastHttpRespHeaders = "";
   gLastWebRequestError = 0;
   gLastHttpStatus = 0;

   int len = StringLen(jsonBody);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (uchar)StringGetCharacter(jsonBody, i);

   int res = WebRequest("POST", url, headers, "", InpRequestTimeoutMs, data, ArraySize(data), result, respHeaders);
   gLastHttpStatus = res;
   gLastHttpRespHeaders = respHeaders;

   if(res == -1)
   {
      gLastWebRequestError = GetLastError();
      FBMarkConnectionDownOnce();
      return "";
   }

   if(ArraySize(result) == 0)
   {
      FBMarkConnectionDownOnce();
      return "";
   }
   FBMarkConnectionUpOnce();
   return CharArrayToString(result, 0, ArraySize(result));
}

string GetTradeCommand()
{
   if(!gAuthReady)
      return "NONE";

   if(!gLoginOk || !gHeartbeatSent || !gAccountTypeReady)
      return "NONE";
   
   string url = BuildEndpointUrl("get_command");
   string body = "{" +
      "\"flamebot_id\":\"" + gUserId + "\"," +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"platform\":\"mt5\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"account_type\":\"" + gAccountType + "\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"" +
   "}";
   string response = HttpPostJson(url, body);
   
   if(response == "" || response == "NONE")
      return "NONE";
   
   if(response == "INVALID")
   {
      FBLogWarn("[FlameBot][WARN] Session invalid. Please sign in again.");
      return "INVALID";
   }
   // Suppress noisy logs and execution for direct commands missing group_id.
   // EXCEPTION: system-style commands (e.g., refresh_symbols) must be allowed.
   string src = "", gid = "", action = "";
   ExtractJsonString(response, "source", src);
   ExtractJsonString(response, "group_id", gid);
   ExtractJsonString(response, "action", action);
   bool isDirect = (StringLen(src) == 0 || src == "direct");
   if(isDirect && StringLen(gid) == 0 && action != "refresh_symbols" && action != "notice")
      return "NONE";

   FBLogDebug("[FlameBot][DEBUG] Update received from server: " + response);
   return response;
}

void ExecuteTradeCommand(const string commandJson)
{
   string action, scope, symbol, direction, source, signal_id, group_id;
   string target_id = "";
   
   if(!ExtractJsonString(commandJson, "action", action))
   {
      FBLogError("[FlameBot][ERROR] Invalid command format");
      return;
   }

   // Notification-only: backend uses this to explain why a Telegram command was rejected
   // (e.g., toggle OFF). It must never trigger trading.
   if(action == "notice")
   {
      string reason = "";
      ExtractJsonString(commandJson, "reason", reason);
      if(StringLen(reason) > 0)
         FBLogWarn("[FlameBot][WARN] " + reason);
      else
         FBLogWarn("[FlameBot][WARN] NOTICE");
      return;
   }

   // Manual symbols refresh (UI-triggered): ALWAYS push full symbol list, even if unchanged.
   if(action == "refresh_symbols")
   {
      FBLogInfo("[FlameBot][INFO] Symbols refresh requested — pushing symbols now");
      gSymbolsPushedOnce = false;
      PushSymbolsToBackend();
      return;
   }

   // Trade Bunker command: close one EA-managed trade/order by ticket.
   if(action == "close_trade")
   {
      string cmd_uid = "";
      string ticketStr = "";
      string guardObj = "";
      ExtractJsonString(commandJson, "command_uid", cmd_uid);
      ExtractJsonString(commandJson, "ticket", ticketStr);
      ExtractJsonObject(commandJson, "guardrails", guardObj);
      ExtractJsonString(commandJson, "group_id", group_id);
      TrimString(group_id);

      // If no ticket is provided, fall through to legacy symbol-level close logic.
      if(StringLen(ticketStr) > 0)
      {
         if(StringLen(cmd_uid) > 0 && FBCommandUidProcessed(cmd_uid))
         {
            if(LogEnabled(FB_LOG_DEBUG))
               FBLogDebug(StringFormat("[FlameBot][DEBUG] close_trade skipped (duplicate command_uid) | uid=%s", cmd_uid));
            return;
         }

         ulong ticket = (ulong)StringToInteger(ticketStr);
         if(ticket == 0)
         {
            FBLogError("[FlameBot][ERROR] close_trade rejected: invalid ticket");
            return;
         }

         // Extract guardrails
         string gr_group = "", gr_signal = "", gr_kind = "", gr_symbol = "";
         if(StringLen(guardObj) > 0)
         {
            ExtractJsonString(guardObj, "group_id", gr_group);
            ExtractJsonString(guardObj, "signal_id", gr_signal);
            ExtractJsonString(guardObj, "kind", gr_kind);
            ExtractJsonString(guardObj, "symbol", gr_symbol);
            TrimString(gr_group);
         }
         if(StringLen(group_id) == 0 && StringLen(gr_group) > 0)
            group_id = gr_group;

         bool ok = true;
         string sym_to_push = "";

         if(PositionSelectByTicket(ticket))
         {
            if((int)PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: not an EA-managed position | ticket=%I64u", ticket));
               return;
            }

            string sym = PositionGetString(POSITION_SYMBOL);
            sym_to_push = sym;
            string comment = PositionGetString(POSITION_COMMENT);
            ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            if(StringLen(group_id) > 0)
            {
               string cg = ExtractGroupIdFromComment(comment);
               if(StringLen(cg) == 0 || cg != group_id)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: group mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_signal) > 0)
            {
               string cs = ExtractSignalIdFromComment(comment);
               if(StringLen(cs) == 0 || cs != gr_signal)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: signal mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_symbol) > 0)
            {
               string s1 = sym;
               string s2 = gr_symbol;
               StringToUpper(s1);
               StringToUpper(s2);
               if(s1 != s2)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: symbol mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_kind) > 0)
            {
               string k = gr_kind;
               StringToLower(k);
               if(k == "pending")
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: kind mismatch | ticket=%I64u", ticket));
                  return;
               }
            }

            double vol = PositionGetDouble(POSITION_VOLUME);
            MqlTick tick;
            if(!SymbolInfoTick(sym, tick))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] close_trade failed: no tick | sym=%s", sym));
               ok = false;
            }
            else
            {
               MqlTradeRequest req;
               MqlTradeResult res;
               ZeroMemory(req);
               ZeroMemory(res);
               req.action = TRADE_ACTION_DEAL;
               req.symbol = sym;
               req.position = ticket;
               req.magic = gMagicNumber;
               req.volume = vol;
               req.deviation = 10;
               req.type = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               req.price = (ptype == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
               req.comment = "TB_close";
               if(!OrderSend(req, res))
               {
                  FBLogError(StringFormat("[FlameBot][ERROR] close_trade failed | ticket=%I64u | err=%d", ticket, GetLastError()));
                  ok = false;
               }
            }
         }
         else if(OrderSelect(ticket))
         {
            if((int)OrderGetInteger(ORDER_MAGIC) != gMagicNumber)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: not an EA-managed order | ticket=%I64u", ticket));
               return;
            }

            ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            bool isPending = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT || otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_STOP || otype == ORDER_TYPE_BUY_STOP_LIMIT || otype == ORDER_TYPE_SELL_STOP_LIMIT);
            if(!isPending)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: unsupported order type | ticket=%I64u", ticket));
               return;
            }

            string sym = OrderGetString(ORDER_SYMBOL);
            sym_to_push = sym;
            string comment = OrderGetString(ORDER_COMMENT);

            if(StringLen(group_id) > 0)
            {
               string cg = ExtractGroupIdFromComment(comment);
               if(StringLen(cg) == 0 || cg != group_id)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: group mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_signal) > 0)
            {
               string cs = ExtractSignalIdFromComment(comment);
               if(StringLen(cs) == 0 || cs != gr_signal)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: signal mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_symbol) > 0)
            {
               string s1 = sym;
               string s2 = gr_symbol;
               StringToUpper(s1);
               StringToUpper(s2);
               if(s1 != s2)
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: symbol mismatch | ticket=%I64u", ticket));
                  return;
               }
            }
            if(StringLen(gr_kind) > 0)
            {
               string k = gr_kind;
               StringToLower(k);
               if(k == "active")
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: kind mismatch | ticket=%I64u", ticket));
                  return;
               }
            }

            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            req.action = TRADE_ACTION_REMOVE;
            req.order = ticket;
            req.symbol = sym;
            if(!OrderSend(req, res))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] close_trade pending delete failed | ticket=%I64u | err=%d", ticket, GetLastError()));
               ok = false;
            }
         }
         else
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] close_trade rejected: ticket not found | ticket=%I64u", ticket));
            return;
         }

         if(ok && StringLen(cmd_uid) > 0)
            FBMarkCommandUidProcessed(cmd_uid);
         if(ok)
         {
            if(StringLen(sym_to_push) > 0)
               PushTradeStateToBackend(sym_to_push);
            else
               PushAllTradeStatesToBackend();
         }
         return;
      }
   }

   // Trade Bunker command: modify one EA-managed trade/order by ticket.
   if(action == "modify_trade")
   {
      string cmd_uid = "";
      string ticketStr = "";
      string changesObj = "";
      string guardObj = "";
      ExtractJsonString(commandJson, "command_uid", cmd_uid);
      ExtractJsonString(commandJson, "ticket", ticketStr);
      ExtractJsonObject(commandJson, "changes", changesObj);
      ExtractJsonObject(commandJson, "guardrails", guardObj);
      ExtractJsonString(commandJson, "group_id", group_id);
      TrimString(group_id);

      if(StringLen(cmd_uid) > 0 && FBCommandUidProcessed(cmd_uid))
      {
         if(LogEnabled(FB_LOG_DEBUG))
            FBLogDebug(StringFormat("[FlameBot][DEBUG] modify_trade skipped (duplicate command_uid) | uid=%s", cmd_uid));
         return;
      }

      ulong ticket = (ulong)StringToInteger(ticketStr);
      if(ticket == 0)
      {
         FBLogError("[FlameBot][ERROR] modify_trade rejected: invalid ticket");
         return;
      }

      // Extract guardrails
      string gr_group = "", gr_signal = "", gr_kind = "", gr_symbol = "";
      if(StringLen(guardObj) > 0)
      {
         ExtractJsonString(guardObj, "group_id", gr_group);
         ExtractJsonString(guardObj, "signal_id", gr_signal);
         ExtractJsonString(guardObj, "kind", gr_kind);
         ExtractJsonString(guardObj, "symbol", gr_symbol);
         TrimString(gr_group);
      }
      if(StringLen(group_id) == 0 && StringLen(gr_group) > 0)
         group_id = gr_group;

      // Parse changes
      double newSl = 0.0, newTp = 0.0, newVol = 0.0;
      bool hasSl = false, hasTp = false, hasVol = false;
      if(StringLen(changesObj) > 0)
      {
         string slStr = "", tpStr = "", volStr = "";
         if(ExtractJsonString(changesObj, "sl", slStr))
         {
            hasSl = true;
            if(slStr == "null") newSl = 0.0; else newSl = StringToDouble(slStr);
         }
         if(ExtractJsonString(changesObj, "tp", tpStr))
         {
            hasTp = true;
            if(tpStr == "null") newTp = 0.0; else newTp = StringToDouble(tpStr);
         }
         if(ExtractJsonString(changesObj, "volume", volStr))
         {
            hasVol = true;
            if(volStr == "null") newVol = 0.0; else newVol = StringToDouble(volStr);
         }
      }
      if(!hasSl && !hasTp && !hasVol)
      {
         FBLogWarn("[FlameBot][WARN] modify_trade ignored: no supported changes");
         return;
      }

      bool ok = true;
      string sym_to_push = "";

      // Try position first.
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: not an EA-managed position | ticket=%I64u", ticket));
            return;
         }

         string sym = PositionGetString(POSITION_SYMBOL);
         sym_to_push = sym;
         string comment = PositionGetString(POSITION_COMMENT);
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(StringLen(group_id) > 0)
         {
            string cg = ExtractGroupIdFromComment(comment);
            if(StringLen(cg) == 0 || cg != group_id)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: group mismatch | ticket=%I64u", ticket));
               return;
            }
         }
         if(StringLen(gr_signal) > 0)
         {
            string cs = ExtractSignalIdFromComment(comment);
            if(StringLen(cs) == 0 || cs != gr_signal)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: signal mismatch | ticket=%I64u", ticket));
               return;
            }
         }

         double curVol = PositionGetDouble(POSITION_VOLUME);
         double curSl = PositionGetDouble(POSITION_SL);
         double curTp = PositionGetDouble(POSITION_TP);
         double desiredSl = hasSl ? newSl : curSl;
         double desiredTp = hasTp ? newTp : curTp;

         if(hasVol && newVol > 0.0 && newVol < curVol)
         {
            double closeVol = curVol - newVol;
            MqlTick tick;
            if(!SymbolInfoTick(sym, tick))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] modify_trade failed: no tick | sym=%s", sym));
               ok = false;
            }
            else
            {
               MqlTradeRequest req;
               MqlTradeResult res;
               ZeroMemory(req);
               ZeroMemory(res);
               req.action = TRADE_ACTION_DEAL;
               req.symbol = sym;
               req.position = ticket;
               req.magic = gMagicNumber;
               req.volume = closeVol;
               req.deviation = 10;
               req.type = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               req.price = (ptype == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
               req.comment = "TB_partial_close";
               if(!OrderSend(req, res))
               {
                  FBLogError(StringFormat("[FlameBot][ERROR] modify_trade partial close failed | ticket=%I64u | err=%d", ticket, GetLastError()));
                  ok = false;
               }
            }
         }

         if(ok && (hasSl || hasTp))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            req.action = TRADE_ACTION_SLTP;
            req.symbol = sym;
            req.position = ticket;
            req.magic = gMagicNumber;
            req.sl = desiredSl;
            req.tp = desiredTp;
            if(!OrderSend(req, res))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] modify_trade SLTP failed | ticket=%I64u | err=%d", ticket, GetLastError()));
               ok = false;
            }
         }
      }
      else if(OrderSelect(ticket))
      {
         if((int)OrderGetInteger(ORDER_MAGIC) != gMagicNumber)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: not an EA-managed order | ticket=%I64u", ticket));
            return;
         }

         ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         bool isPending = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT || otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_STOP || otype == ORDER_TYPE_BUY_STOP_LIMIT || otype == ORDER_TYPE_SELL_STOP_LIMIT);
         if(!isPending)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: unsupported order type | ticket=%I64u", ticket));
            return;
         }

         string sym = OrderGetString(ORDER_SYMBOL);
         sym_to_push = sym;
         string comment = OrderGetString(ORDER_COMMENT);
         if(StringLen(group_id) > 0)
         {
            string cg = ExtractGroupIdFromComment(comment);
            if(StringLen(cg) == 0 || cg != group_id)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: group mismatch | ticket=%I64u", ticket));
               return;
            }
         }
         if(StringLen(gr_signal) > 0)
         {
            string cs = ExtractSignalIdFromComment(comment);
            if(StringLen(cs) == 0 || cs != gr_signal)
            {
               FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: signal mismatch | ticket=%I64u", ticket));
               return;
            }
         }

         double curVol = OrderGetDouble(ORDER_VOLUME_CURRENT);
         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         double curSl = OrderGetDouble(ORDER_SL);
         double curTp = OrderGetDouble(ORDER_TP);
         datetime exp = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         double desiredSl = hasSl ? newSl : curSl;
         double desiredTp = hasTp ? newTp : curTp;

         if(hasVol && newVol > 0.0 && MathAbs(newVol - curVol) > 0.000001)
         {
            // delete + recreate
            {
               MqlTradeRequest req;
               MqlTradeResult res;
               ZeroMemory(req);
               ZeroMemory(res);
               req.action = TRADE_ACTION_REMOVE;
               req.order = ticket;
               if(!OrderSend(req, res))
               {
                  FBLogError(StringFormat("[FlameBot][ERROR] modify_trade pending delete failed | ticket=%I64u | err=%d", ticket, GetLastError()));
                  ok = false;
               }
            }

            if(ok)
            {
               MqlTradeRequest req;
               MqlTradeResult res;
               ZeroMemory(req);
               ZeroMemory(res);
               req.action = TRADE_ACTION_PENDING;
               req.symbol = sym;
               req.type = otype;
               req.volume = newVol;
               req.price = price;
               req.sl = desiredSl;
               req.tp = desiredTp;
               req.magic = gMagicNumber;
               req.comment = comment;
               req.deviation = 10;
               if(exp > 0)
               {
                  req.type_time = ORDER_TIME_SPECIFIED;
                  req.expiration = exp;
               }
               if(!OrderSend(req, res))
               {
                  FBLogError(StringFormat("[FlameBot][ERROR] modify_trade pending recreate failed | sym=%s | err=%d", sym, GetLastError()));
                  ok = false;
               }
            }
         }
         else if(ok && (hasSl || hasTp))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            req.action = TRADE_ACTION_MODIFY;
            req.order = ticket;
            req.symbol = sym;
            req.price = price;
            req.sl = desiredSl;
            req.tp = desiredTp;
            if(exp > 0)
            {
               req.type_time = ORDER_TIME_SPECIFIED;
               req.expiration = exp;
            }
            if(!OrderSend(req, res))
            {
               FBLogError(StringFormat("[FlameBot][ERROR] modify_trade pending modify failed | ticket=%I64u | err=%d", ticket, GetLastError()));
               ok = false;
            }
         }
      }
      else
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] modify_trade rejected: ticket not found | ticket=%I64u", ticket));
         return;
      }

      if(ok && StringLen(cmd_uid) > 0)
         FBMarkCommandUidProcessed(cmd_uid);
      if(ok)
      {
         if(StringLen(sym_to_push) > 0)
            PushTradeStateToBackend(sym_to_push);
         else
            PushAllTradeStatesToBackend();
      }
      return;
   }

   FBLogInfo(StringFormat("[FlameBot] Trade command received | action=%s | scope=%s | symbol=%s | direction=%s | source=%s | signal_id=%s | group_id=%s",
               action, scope, symbol, direction, source, signal_id, group_id));
   
   // Execute based on action type
   // Prefer using target_id when it references existing trades (update commands)
   ExtractJsonString(commandJson, "target_id", target_id);
   bool isLinked = (StringLen(signal_id) > 0) || (StringLen(target_id) > 0) || (source == "reply" || source == "edit");

   string match_signal_id = signal_id;
   if(StringLen(target_id) > 0)
   {
      // If trades exist for target_id, prefer that for matching/operations
      if(HasTradesForSignal(target_id))
         match_signal_id = target_id;
      else if(!HasTradesForSignal(signal_id))
         match_signal_id = target_id; // fallback attempt even if HasTradesForSignal misses
   }

   // Unlinked command support: apply only if symbol has active trades/orders
   if(!isLinked && (action == "set_breakeven" || action == "close_trade" || action == "secure_half" || action == "secure_half_and_be"))
   {
      if(StringLen(symbol) == 0)
      {
         FBLogError("[FlameBot][ERROR] Command ignored: no symbol specified");
         return;
      }
      if(StringLen(group_id) == 0)
      {
         FBLogInfo("[FlameBot] Command skipped: group mismatch (command group does not own these trades)");
         return;
      }
      if(!HasAnyActiveTradeOnSymbol(symbol))
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Unlinked command ignored: no active trades for %s", symbol));
         return;
      }
      // Resolve only signal_id belonging to this group. Use matched id preference when available.
      string activeId = "";
      int ptotal = PositionsTotal();
      for(int pi = 0; pi < ptotal && StringLen(activeId)==0; pi++)
      {
         ulong pt = PositionGetTicket(pi);
         if(pt==0) continue;
         if(!PositionSelectByTicket(pt)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         string pc = PositionGetString(POSITION_COMMENT);
         string posGroup = ExtractGroupIdFromComment(pc);
         if(posGroup != "" && posGroup != group_id)
         {
            FBLogInfo(StringFormat("[FlameBot] Skip position (group mismatch) | ticket=%I64u | sym=%s | comment=%s | found_grp=%s | expected_grp=%s",
                        pt, PositionGetString(POSITION_SYMBOL), pc, posGroup, group_id));
            continue;
         }
         activeId = ExtractSignalIdFromComment(pc);
      }
      int ototal = OrdersTotal();
      for(int oi = 0; oi < ototal && StringLen(activeId)==0; oi++)
      {
         ulong ot = OrderGetTicket(oi);
         if(ot==0) continue;
         if(!OrderSelect(ot)) continue;
         if(OrderGetInteger(ORDER_MAGIC) != gMagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != symbol) continue;
         string oc = OrderGetString(ORDER_COMMENT);
         string ordGroup = ExtractGroupIdFromComment(oc);
         if(ordGroup != "" && ordGroup != group_id)
         {
            FBLogInfo(StringFormat("[FlameBot] Skip pending (group mismatch) | ticket=%I64u | sym=%s | comment=%s | found_grp=%s | expected_grp=%s",
                        ot, OrderGetString(ORDER_SYMBOL), oc, ordGroup, group_id));
            continue;
         }
            activeId = ExtractSignalIdFromComment(oc);
      }
      if(StringLen(activeId) == 0)
      {
         FBLogInfo("[FlameBot] Command skipped: group mismatch (command group does not own these trades)");
         return;
      }
      FBLogInfo(StringFormat("[FlameBot][INFO] Command applied | symbol=%s | group_id=%s", symbol, group_id));
      if(action == "set_breakeven")
         ExecuteBreakeven("signal", symbol, "", activeId, group_id);
      else if(action == "close_trade")
         ExecuteCloseTrade("signal", symbol, "", activeId, group_id, false);
      else
         ExecuteSecureHalf("signal", symbol, "", activeId, gAllowMessageBreakeven, group_id);
      return;
   }

   // Linked command path (prefer match_signal_id when present)
   if(action == "set_breakeven")
      ExecuteBreakeven(scope, symbol, direction, match_signal_id, group_id);
   else if(action == "close_trade")
      ExecuteCloseTrade(scope, symbol, direction, match_signal_id, group_id, false);
   else if(action == "close_pending")
      ExecuteClosePending(symbol, match_signal_id, group_id);
   else if(action == "secure_half")
      ExecuteSecureHalf(scope, symbol, direction, match_signal_id, gAllowMessageBreakeven, group_id);
   else if(action == "secure_half_and_be")
      ExecuteSecureHalf(scope, symbol, direction, match_signal_id, gAllowMessageBreakeven, group_id);
   else
      FBLogWarn(StringFormat("[FlameBot][WARN] Unknown command action: %s", action));
}

void ExecuteBreakeven(const string scope, const string symbol, const string direction, const string signal_id, const string group_id)
{
   // CRITICAL: ALL commands must be signal-scoped
   if(signal_id == "")
   {
      FBLogError("[FlameBot][ERROR] REJECTED: Breakeven command requires signal_id (no account-wide control allowed)");
      return;
   }
   
   // If signal_id provided, extract symbol from matching trades
   string resolvedSymbol = symbol;
   if(symbol == "")
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber) continue;
         
         string posComment = PositionGetString(POSITION_COMMENT);
         if(StringFind(posComment, signal_id) != -1)
         {
            resolvedSymbol = PositionGetString(POSITION_SYMBOL);
            break;
         }
      }
   }
   
   FBLogDebug(StringFormat("[FlameBot][DEBUG] ExecuteBreakeven | scope=%s | symbol=%s | direction=%s | signal_id=%s | group_id=%s",
                  scope, resolvedSymbol, direction, signal_id, group_id));
   
   if(resolvedSymbol == "")
   {
      FBLogWarn(StringFormat("[FlameBot][WARN] No open-position symbol found for signal_id=%s; proceeding to close by signal_id and cancel pendings.", signal_id));
      // Do NOT return; continue to close loop (filtered by signal_id) and pending cancellation.
   }
   
   int modified = 0;
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber)
         continue;
      
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      string posComment = PositionGetString(POSITION_COMMENT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string posTypeStr = (posType == POSITION_TYPE_BUY) ? "buy" : "sell";
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(posSymbol, SYMBOL_BID) : SymbolInfoDouble(posSymbol, SYMBOL_ASK);

      // [FlameBot][INFO] REQUIRED: Signal ID is a HARD filter (no group-level fallback).
      // Modify/close ONLY if the comment contains the exact target_id/signal_id token.
      if(StringFind(posComment, signal_id) < 0)
         continue;
      
      // Direction filtering (optional)
      if(direction != "" && posTypeStr != direction)
         continue;
      
      // Check profit state
      bool inProfit = (posType == POSITION_TYPE_BUY && currentPrice > entryPrice) ||
                      (posType == POSITION_TYPE_SELL && currentPrice < entryPrice);
      bool inLoss = (posType == POSITION_TYPE_BUY && currentPrice < entryPrice) ||
                    (posType == POSITION_TYPE_SELL && currentPrice > entryPrice);
      
      // If trade is in LOSS, close it immediately (price crossed entry against trade)
      if(inLoss)
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Trade in LOSS - closing instead of BE | ticket=%I64u | symbol=%s | entry=%.5f | current=%.5f",
                        ticket, posSymbol, entryPrice, currentPrice));
         
         if(!trade.PositionClose(ticket))
         {
            FBLogError(StringFormat("[FlameBot][ERROR] Failed to close losing trade | ticket=%I64u | error=%d", ticket, GetLastError()));
            continue;
         }
         
         FBLogInfo(StringFormat("[FlameBot][INFO] Closed losing trade | ticket=%I64u | symbol=%s", ticket, posSymbol));
         modified++;
         continue;
      }
      
      // If not in profit, skip (at entry or too close)
      if(!inProfit)
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Breakeven skipped (at entry, not enough profit) | ticket=%I64u | symbol=%s", ticket, posSymbol));
         continue;
      }
      
      // Safety check: Never widen SL
      if(currentSL != 0.0)
      {
         double slDistance = MathAbs(entryPrice - currentSL);
         double newDistance = 0.0;  // BE is at entry
         
         if(newDistance > slDistance)
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] Breakeven blocked (would widen SL) | ticket=%I64u | current_sl=%.5f | entry=%.5f",
                           ticket, currentSL, entryPrice));
            continue;
         }
      }
      
      // Modify to breakeven
      double tp = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(ticket, entryPrice, tp))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Breakeven modify failed | ticket=%I64u | error=%d", ticket, GetLastError()));
         continue;
      }
      
      FBLogInfo(StringFormat("[FlameBot][INFO] Breakeven set | ticket=%I64u | symbol=%s | entry=%.5f", ticket, posSymbol, entryPrice));
      modified++;
   }
   
   // Also cancel any pending orders associated with this command (limits/stops)
   string tsymbol = symbol;
   if(StringLen(tsymbol) == 0)
   {
      tsymbol = ResolveSymbolForSignal(signal_id);
      if(StringLen(tsymbol) > 0)
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Resolved symbol for breakeven cancel | signal_id=%s -> symbol=%s", signal_id, tsymbol));
      else
         FBLogWarn(StringFormat("[FlameBot][WARN] Symbol not resolved for breakeven cancel; skipping symbol filter (still requires target_id match) | signal_id=%s", signal_id));
   }
   int cancelled = 0;
   int ototal = OrdersTotal();
   FBLogDebug(StringFormat("[FlameBot][DEBUG] Checking pending orders for cancellation | scope=%s | symbol=%s | signal_id=%s | direction=%s | orders_total=%d", scope, tsymbol, signal_id, direction, ototal));
   for(int oi = 0; oi < ototal; oi++)
   {
      ulong oticket = OrderGetTicket(oi);
      if(oticket == 0)
         continue;

      if(!OrderSelect(oticket))
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skip pending | ticket=%I64u | reason=OrderSelect failed", oticket));
         continue;
      }

      string osymbol = OrderGetString(ORDER_SYMBOL);
      if(StringLen(tsymbol) > 0 && osymbol != tsymbol)
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skip pending | ticket=%I64u | symbol=%s (target=%s)", oticket, osymbol, tsymbol));
         continue;
      }

      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isPending = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT ||
                        otype == ORDER_TYPE_BUY_STOP  || otype == ORDER_TYPE_SELL_STOP);
      if(!isPending)
         continue;

      string ocomment = OrderGetString(ORDER_COMMENT);

      // [FlameBot][INFO] REQUIRED: pending cancellations must be signal-scoped.
      // Cancel ONLY if the comment contains the exact target_id/signal_id token.
      if(StringFind(ocomment, signal_id) < 0)
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skip pending | ticket=%I64u | reason=signal_id mismatch | comment=%s", oticket, ocomment));
         continue;
      }

      if(!trade.OrderDelete(oticket))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Failed to delete pending order | ticket=%I64u | error=%d", oticket, GetLastError()));
         continue;
      }
      cancelled++;
      FBLogInfo(StringFormat("[FlameBot][INFO] Pending order cancelled | ticket=%I64u | comment=%s", oticket, ocomment));
   }

   if(modified > 0)
      FBLogInfo(StringFormat("[FlameBot][INFO] Breakeven completed | modified=%d trades", modified));
   else
      FBLogInfo("[FlameBot][INFO] No trades modified (none met breakeven criteria)");

   if(cancelled > 0)
      FBLogInfo(StringFormat("[FlameBot][INFO] Command applied | symbol=%s | group_id=%s", tsymbol, group_id));
}

void ExecuteSecureHalf(const string scope, const string symbol, const string direction, const string signal_id, bool apply_breakeven, const string group_id)
{
   // Toggle guard
   if(!gAllowSecureHalf)
   {
      FBLogWarn("[FlameBot][WARN] Secure-half command BLOCKED (toggle is OFF)");
      return;
   }
   
   // Signal ID required for secure-half
   if(signal_id == "")
   {
      FBLogError("[FlameBot][ERROR] ABORT: Secure-half requires signal_id (cannot close half without knowing which signal ladder)");
      return;
   }
   
   // Resolve symbol from signal_id if not provided
   string resolvedSymbol = symbol;
   if(symbol == "")
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber) continue;
         string posComment = PositionGetString(POSITION_COMMENT);
         if(StringFind(posComment, signal_id) != -1)
         {
            resolvedSymbol = PositionGetString(POSITION_SYMBOL);
            break;
         }
      }
   }
   
   FBLogDebug(StringFormat("[FlameBot][DEBUG] ExecuteSecureHalf | scope=%s | symbol=%s | direction=%s | signal_id=%s | apply_be=%s | group_id=%s", 
               scope, resolvedSymbol, direction, signal_id, apply_breakeven ? "true" : "false", group_id));
   
   // 1. Collect all positions matching this signal_id
   struct TPPosition
   {
      ulong ticket;
      int tp_index;  // Extracted from comment format sig_{id}_tp{N}
      string symbol;
   };
   
   TPPosition positions[];
   ArrayResize(positions, 0);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber) continue;
      
      string posComment = PositionGetString(POSITION_COMMENT);
      string posSymbol = PositionGetString(POSITION_SYMBOL);

      // [FlameBot][INFO] REQUIRED: Signal ID is a HARD filter (no group-level fallback).
      // Secure-half must only act on positions whose comment contains the exact target_id/signal_id token.
      if(StringFind(posComment, signal_id) < 0)
         continue;
      
      // Extract TP index from comment
      // Support both new and old formats: t{N} or tp{N} tokens at start or after '|' or '_'
      int tp_idx = 0;
      bool found_tp = false;
      int lenC = StringLen(posComment);

      // 1) Token after a separator like '|t' or '|tp' or '_t' or '_tp'
      int sepPos = -1;
      sepPos = StringFind(posComment, "|t");
      if(sepPos == -1) sepPos = StringFind(posComment, "|tp");
      if(sepPos == -1) sepPos = StringFind(posComment, "_t");
      if(sepPos == -1) sepPos = StringFind(posComment, "_tp");
      if(sepPos >= 0)
      {
         int start = sepPos + 2; // position after '|t' or '_t'
         // If token was '|tp' or '_tp', adjust to skip the 'p' char if present
         if(start < lenC && StringGetCharacter(posComment, start) == 'p')
            start++;

         int j = start;
         string digits = "";
         while(j < lenC)
         {
            ushort ch = StringGetCharacter(posComment, j);
            if(ch >= '0' && ch <= '9')
               digits += CharToString((uchar)ch);
            else
               break;
            j++;
         }
         if(StringLen(digits) > 0)
         {
            tp_idx = (int)StringToInteger(digits);
            if(tp_idx > 0) found_tp = true;
         }
      }

      // 2) If not found, check start-of-string patterns: 'tN' or 'tpN' or 'tp' at start
      if(!found_tp && lenC > 0)
      {
         // starts with 't' or 'tp'
         if(StringGetCharacter(posComment, 0) == 't' || (StringLen(posComment) > 1 && StringSubstr(posComment,0,2) == "tp"))
         {
            int start = 1; // after 't'
            if(StringSubstr(posComment,0,2) == "tp") start = 2;
            int j = start;
            string digits = "";
            while(j < lenC)
            {
               ushort ch = StringGetCharacter(posComment, j);
               if(ch >= '0' && ch <= '9')
                  digits += CharToString((uchar)ch);
               else
                  break;
               j++;
            }
            if(StringLen(digits) > 0)
            {
               tp_idx = (int)StringToInteger(digits);
               if(tp_idx > 0) found_tp = true;
            }
         }
      }
      
      if(!found_tp)
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Position has signal_id but no tp index | ticket=%I64u | comment=%s", ticket, posComment));
         continue;
      }
      
      // Add to array
      int count = ArraySize(positions);
      ArrayResize(positions, count + 1);
      positions[count].ticket = ticket;
      positions[count].tp_index = tp_idx;
      positions[count].symbol = posSymbol;
   }
   
   int total_positions = ArraySize(positions);
   
   if(total_positions == 0)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] No positions found for signal_id=%s", signal_id));
      return;
   }
   
   // 2. Sort by TP index (lowest first) - simple bubble sort
   for(int i = 0; i < total_positions - 1; i++)
   {
      for(int j = 0; j < total_positions - i - 1; j++)
      {
         if(positions[j].tp_index > positions[j+1].tp_index)
         {
            TPPosition temp = positions[j];
            positions[j] = positions[j+1];
            positions[j+1] = temp;
         }
      }
   }
   
   // 3. Calculate close count = floor(N/2)
   // Enhancement (no behavior change for N>=2): if there is only one position, secure-half should close it.
   int close_count = (total_positions == 1) ? 1 : (int)MathFloor(total_positions / 2.0);
   
   if(close_count == 0)
   {
      FBLogInfo(StringFormat("[FlameBot][INFO] Only %d position(s) in ladder - nothing to close (floor(N/2)=0)", total_positions));
      return;
   }
   
   FBLogInfo(StringFormat("[FlameBot] Secure-Half Plan | total=%d | closing=%d (lowest TPs) | remaining=%d", 
               total_positions, close_count, total_positions - close_count));
   
   // 4. Close lowest close_count positions
   int closed = 0;
   for(int i = 0; i < close_count; i++)
   {
      ulong ticket = positions[i].ticket;
      string posSymbol = positions[i].symbol;
      int tp_idx = positions[i].tp_index;
      
      if(!trade.PositionClose(ticket))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Secure-half close failed | ticket=%I64u | tp_index=%d | error=%d", ticket, tp_idx, GetLastError()));
         continue;
      }
      
      FBLogInfo(StringFormat("[FlameBot][INFO] Secure-half closed | ticket=%I64u | symbol=%s | tp_index=%d", ticket, posSymbol, tp_idx));
      closed++;
   }
   
   FBLogInfo(StringFormat("[FlameBot][INFO] Secure-Half Close Complete | closed=%d/%d positions", closed, close_count));
   
   // 5. Cancel any pending orders associated with this signal and symbol
   string tsymbol = symbol;
   if(StringLen(tsymbol) == 0 && total_positions > 0)
      tsymbol = positions[0].symbol;

   int cancelled = 0;
   int ototal = OrdersTotal();
   FBLogInfo(StringFormat("[FlameBot] Checking pending orders for cancellation (secure-half) | scope=%s | symbol=%s | signal_id=%s | orders_total=%d", scope, tsymbol, signal_id, ototal));
   for(int oi = 0; oi < ototal; oi++)
   {
      ulong oticket = OrderGetTicket(oi);
      if(oticket == 0)
         continue;
      if(!OrderSelect(oticket))
         continue;

      string osymbol = OrderGetString(ORDER_SYMBOL);
      if(osymbol != tsymbol)
         continue;

      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isPending = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT ||
                        otype == ORDER_TYPE_BUY_STOP  || otype == ORDER_TYPE_SELL_STOP);
      if(!isPending)
         continue;

      string ocomment = OrderGetString(ORDER_COMMENT);
      long omagic = (long)OrderGetInteger(ORDER_MAGIC);
      bool magic_ok = (omagic == gMagicNumber) || (StringLen(signal_id) > 0 && StringFind(ocomment, signal_id) != -1);
      if(!magic_ok)
         continue;

      // Require signal_id match for secure-half
      if(StringLen(signal_id) > 0 && StringFind(ocomment, signal_id) == -1)
         continue;

      // Enforce group match (supports both formats)
      if(StringLen(group_id) > 0)
      {
         bool hasGroupMatch = (StringFind(ocomment, StringFormat("|g%s", group_id)) != -1) ||
                              (StringFind(ocomment, StringFormat("grp_%s", group_id)) != -1);
         if(!hasGroupMatch)
            continue;
      }

      if(!trade.OrderDelete(oticket))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Failed to delete pending order | ticket=%I64u | error=%d", oticket, GetLastError()));
         continue;
      }
      cancelled++;
      FBLogInfo(StringFormat("[FlameBot][INFO] Pending order cancelled | ticket=%I64u | comment=%s", oticket, ocomment));
   }

   // 5. If apply_breakeven, set BE on remaining positions
   if(apply_breakeven && closed > 0)
   {
      FBLogInfo(StringFormat("[FlameBot] Applying breakeven to remaining %d position(s)...", total_positions - close_count));
      ExecuteBreakeven(scope, symbol, direction, signal_id, group_id);
   }
}

void ExecuteCloseTrade(const string scope, const string symbol, const string direction, const string signal_id, const string group_id, const bool require_exact)
{
   // CRITICAL: ALL commands must be signal-scoped
   if(signal_id == "")
   {
      FBLogError("[FlameBot][ERROR] REJECTED: Close command requires signal_id (no account-wide control allowed)");
      return;
   }
   
   // If signal_id provided, extract symbol from matching trades/orders (trunc-safe)
   string resolvedSymbol = symbol;
   if(symbol == "")
      resolvedSymbol = ResolveSymbolForSignal(signal_id);
   
   FBLogDebug(StringFormat("[FlameBot][DEBUG] ExecuteCloseTrade | scope=%s | symbol=%s | direction=%s | signal_id=%s | group_id=%s", 
               scope, resolvedSymbol, direction, signal_id, group_id));
   
   if(resolvedSymbol == "")
   {
      FBLogWarn(StringFormat("[FlameBot][WARN] No symbol found for signal_id=%s; proceeding with signal_id-only filtering.", signal_id));
   }
   
   int closed = 0;
   int total = PositionsTotal();
   FBLogDebug(StringFormat("[FlameBot][DEBUG] Total positions: %d", total));
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != gMagicNumber)
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skipping ticket=%I64u (magic=%d, expected=%d)", ticket, magic, gMagicNumber));
         continue;
      }
      
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      string posComment = PositionGetString(POSITION_COMMENT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string posTypeStr = (posType == POSITION_TYPE_BUY) ? "buy" : "sell";
      FBLogDebug(StringFormat("[FlameBot][DEBUG] Checking position | ticket=%I64u | symbol=%s | type=%s | magic=%d | comment=%s", 
            ticket, posSymbol, posTypeStr, magic, posComment));

      // HARD SYMBOL FILTER: if we have a symbol (from command or resolution), never touch other symbols.
      if(resolvedSymbol != "" && posSymbol != resolvedSymbol)
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skipping ticket=%I64u (symbol mismatch): pos=%s, target=%s", ticket, posSymbol, resolvedSymbol));
         continue;
      }

      // Signal/Group ID matching (handles comment truncation like MT4)
      // New format: tp{N}|g{group_id}|s{signal_id}
      // Old format: grp_{group_id}|sig_{signal_id}|tp{N}
      bool signalMatch = (StringFind(posComment, signal_id) != -1);
      // Only allow truncation-safe matching when caller did not request exact-match (e.g., not a reply/target_id)
      if(!signalMatch && !require_exact)
      {
         // Prefer suffix-aware truncation match first (prevents closing other signals in the same group).
         if(CommentMatchesSignalIdTruncSafe(posComment, signal_id))
            signalMatch = true;
      }
      if(!signalMatch)
      {
         FBLogInfo("[FlameBot] Skipping (signal_id mismatch)");
         continue;
      }

      // Group ID enforcement (supports both formats)
      if(StringLen(group_id) > 0)
      {
         bool hasGroupMatch = (StringFind(posComment, StringFormat("|g%s", group_id)) != -1) ||
                              (StringFind(posComment, StringFormat("g%s", group_id)) != -1) ||
                              (StringFind(posComment, StringFormat("grp_%s", group_id)) != -1);
         if(!hasGroupMatch)
         {
            FBLogInfo("[FlameBot] Command skipped: group mismatch (command group does not own these trades)");
            continue;
         }
      }
      
      // Direction filtering (optional - if empty, match any)
      if(direction != "" && 
         ((direction == "buy" && posType != POSITION_TYPE_BUY) ||
          (direction == "sell" && posType != POSITION_TYPE_SELL)))
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Skipping (direction mismatch): pos=%s, target=%s", posTypeStr, direction));
         continue;
      }
      
      FBLogInfo(StringFormat("[FlameBot] Closing position | ticket=%I64u | symbol=%s | type=%s", ticket, posSymbol, posTypeStr));
      
      // Close position
      if(!trade.PositionClose(ticket))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Close failed | ticket=%I64u | error=%d", ticket, GetLastError()));
         continue;
      }
      
      FBLogInfo(StringFormat("[FlameBot][INFO] Trade closed | ticket=%I64u | symbol=%s", ticket, posSymbol));
      closed++;
   }

   if(closed > 0)
      FBLogInfo(StringFormat("[FlameBot][INFO] Command applied | symbol=%s | group_id=%s", resolvedSymbol, group_id));
   else
      FBLogInfo("[FlameBot][INFO] No trades closed (none matched criteria)");

   // Also cancel any pending orders for this signal (works even if there were no positions)
   int cancelled = 0;
   int ototal2 = OrdersTotal();
   string d2 = StringLower(direction);
   for(int oi2 = ototal2 - 1; oi2 >= 0; oi2--)
   {
      ulong oticket2 = OrderGetTicket(oi2);
      if(oticket2 == 0)
         continue;

      if(!OrderSelect(oticket2))
      {
         FBLogInfo(StringFormat("[FlameBot] Skip pending | ticket=%I64u | reason=OrderSelect failed", oticket2));
         continue;
      }

      ENUM_ORDER_TYPE otype2 = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isPending2 = (otype2 == ORDER_TYPE_BUY_LIMIT || otype2 == ORDER_TYPE_SELL_LIMIT ||
                         otype2 == ORDER_TYPE_BUY_STOP  || otype2 == ORDER_TYPE_SELL_STOP);
      if(!isPending2)
         continue;

      long omagic2 = (long)OrderGetInteger(ORDER_MAGIC);
      if(omagic2 != gMagicNumber)
         continue;

      string ocomment2 = OrderGetString(ORDER_COMMENT);
      if(StringLen(signal_id) > 0 && (StringFind(ocomment2, signal_id) == -1 && !CommentMatchesSignalIdTruncSafe(ocomment2, signal_id)))
         continue; // only delete pendings belonging to this signal

      // Enforce group match on pending orders (supports both formats)
      if(StringLen(group_id) > 0)
      {
         bool hasGroupMatch = (StringFind(ocomment2, StringFormat("|g%s", group_id)) != -1) ||
                              (StringFind(ocomment2, StringFormat("g%s", group_id)) != -1) ||
                              (StringFind(ocomment2, StringFormat("grp_%s", group_id)) != -1);
         if(!hasGroupMatch)
            continue;
      }

      // Optional symbol filter: only if we resolved one
      if(resolvedSymbol != "" && OrderGetString(ORDER_SYMBOL) != resolvedSymbol)
         continue;

      // Optional direction filter
      if(d2 == "buy" && !(otype2 == ORDER_TYPE_BUY_LIMIT || otype2 == ORDER_TYPE_BUY_STOP))
         continue;
      if(d2 == "sell" && !(otype2 == ORDER_TYPE_SELL_LIMIT || otype2 == ORDER_TYPE_SELL_STOP))
         continue;

      if(!trade.OrderDelete(oticket2))
      {
         FBLogError(StringFormat("[FlameBot][ERROR] Failed to delete pending order | ticket=%I64u | error=%d", oticket2, GetLastError()));
         continue;
      }
      cancelled++;
      FBLogInfo(StringFormat("[FlameBot][INFO] Pending order cancelled | ticket=%I64u | comment=%s", oticket2, ocomment2));
   }

   if(cancelled > 0)
      FBLogInfo(StringFormat("[FlameBot][INFO] Command applied | symbol=%s | group_id=%s", resolvedSymbol, group_id));
}

void ResetCredentialsAfterInvalid()
{
   // Best-effort: release backend lock before clearing local creds.
   if(gAuthReady)
      NotifyBackendLogout();
   FBLogError("[FlameBot][ERROR] Invalid license detected. Please re-login from Desktop App.");
   gUserId = "";
   gLicenseKey = "";
   gAuthReady = false;
   gLoginOk = false;
   gLoginBlocked = false;
   gLoginBlockReason = "";
   gLoginBlockLogged = false;
   gLotSettingsLoaded = false;
   gSymbolSettingsLoaded = false;
   gSymbolMode = "default";
   gLoginAnnounced = false;
   gLotConfigured = false;
   gSymbolConfigured = false;
   gTradingUnlocked = false;
   gWaitingAnnounced = false;
   gLotFinalPrinted = false;
   gSymbolFinalPrinted = false;
   gLotPrintedMode = "";
   gLotPrintedCustom = 0.0;
   gSymbolPrintedMode = "";
   gSymbolPrintedCount = 0;
   ArrayResize(gAllowedSymbols, 0);
   ClearSavedAuth();
   FBClearAuthPanelSuppression();
   RemoveAuthPanel();
   CreateAuthPanel();
   gSymbolPendingLogged = false;
   gLotPendingLogged = false;
   gSymbolsPushedOnce   = false;
   gHeartbeatSent = false;
}

// Notify backend to release the per-license session lock.
void NotifyBackendLogout()
{
   if(!gAuthReady)
      return;

   string payload =
      "{" 
      "\"user_id\":\"" + gUserId + "\"," 
      "\"license_key\":\"" + gLicenseKey + "\"," 
      "\"ea_id\":\"FLAME_RUNMT5\"," 
      "\"platform\":\"mt5\"," 
      "\"terminal_id\":\"" + gTerminalId + "\"" 
      "}";

   uchar data[];
   int len = StringLen(payload);
   ArrayResize(data, len);
   for(int i = 0; i < len; i++)
      data[i] = (uchar)payload[i];

   uchar result[];
   string respHeaders = "";
   string headers = "Content-Type: application/json\r\n";

   WebRequest(
      "POST",
      BuildEndpointUrl("ea/logout"),
      headers,
      "",
      InpRequestTimeoutMs,
      data,
      ArraySize(data),
      result,
      respHeaders
   );
}

void LogoutEA()
{
   // Best-effort: release backend lock before clearing local creds.
   if(gAuthReady)
      NotifyBackendLogout();
   FBLogWarn("[FlameBot] EA logged out by user. Manual re-login required.");
   gUserId = "";
   gLicenseKey = "";
   gAuthReady = false;
   gLoginOk = false;
   gLoginBlocked = false;
   gLoginBlockReason = "";
   gLoginBlockLogged = false;
   gLotSettingsLoaded = false;
   gSymbolSettingsLoaded = false;
   gSymbolMode = "default";
   gLoginAnnounced = false;
   gLotConfigured = false;
   gSymbolConfigured = false;
   gTradingUnlocked = false;
   gWaitingAnnounced = false;
   gLotFinalPrinted = false;
   gSymbolFinalPrinted = false;
   gLotPrintedMode = "";
   gLotPrintedCustom = 0.0;
   gSymbolPrintedMode = "";
   gSymbolPrintedCount = 0;
   gPSLConfigured = false;
   gPSLSettingsLoaded = false;
   gPSLFinalPrinted = false;
   gLastPSLCount = -1;
   gExecutionMode = "gls";
   gTradeModeLoaded = false;
   gAllowMessageClose = false;
   gAllowMessageBreakeven = false;
   gAllowSecureHalf = false;
   gAllowMultipleSignalsPerSymbol = false;
   gTogglesPrinted = false;
   gEntryMode = "market_edge";
   gEntryModePrinted = false;
   ArrayResize(gAllowedSymbols, 0);
   ClearSavedAuth();
   FBClearAuthPanelSuppression();
   RemoveAuthPanel();
   CreateAuthPanel();
   gSymbolPendingLogged = false;
   gLotPendingLogged = false;
   gSymbolsPushedOnce   = false;
   gHeartbeatSent = false;
   gLastBackendRefresh = 0;
}

//+------------------------------------------------------------------+
//| GUI helpers                                                      |
//+------------------------------------------------------------------+
void CreateAuthPanel()
{
   int x = 10, y = 20;
   int w = 320, h = 140;

   string panel = "auth_panel";
   ObjectCreate(0, panel, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panel, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, panel, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, panel, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, panel, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, panel, OBJPROP_COLOR, clrDarkSlateGray);
   ObjectSetInteger(0, panel, OBJPROP_BACK, true);
   ObjectSetInteger(0, panel, OBJPROP_SELECTABLE, false);

   int mx = x + 12;
   int my = y + 12;

   ObjectCreate(0, "lbl_user", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "lbl_user", OBJPROP_XDISTANCE, mx);
   ObjectSetInteger(0, "lbl_user", OBJPROP_YDISTANCE, my);
   ObjectSetString(0, "lbl_user", OBJPROP_TEXT, "FlameBot ID:");
   ObjectSetInteger(0, "lbl_user", OBJPROP_COLOR, clrBlack);

   ObjectCreate(0, "edit_user", OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, "edit_user", OBJPROP_XDISTANCE, mx + 110);
   ObjectSetInteger(0, "edit_user", OBJPROP_YDISTANCE, my - 2);
   ObjectSetInteger(0, "edit_user", OBJPROP_XSIZE, 180);
   ObjectSetInteger(0, "edit_user", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, "edit_user", OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, "edit_user", OBJPROP_COLOR, clrBlack);
   ObjectSetString(0, "edit_user", OBJPROP_TEXT, gUserId);

   ObjectCreate(0, "lbl_license", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "lbl_license", OBJPROP_XDISTANCE, mx);
   ObjectSetInteger(0, "lbl_license", OBJPROP_YDISTANCE, my + 36);
   ObjectSetString(0, "lbl_license", OBJPROP_TEXT, "License Key:");
   ObjectSetInteger(0, "lbl_license", OBJPROP_COLOR, clrBlack);

   ObjectCreate(0, "edit_license", OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, "edit_license", OBJPROP_XDISTANCE, mx + 110);
   ObjectSetInteger(0, "edit_license", OBJPROP_YDISTANCE, my + 34);
   ObjectSetInteger(0, "edit_license", OBJPROP_XSIZE, 180);
   ObjectSetInteger(0, "edit_license", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, "edit_license", OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, "edit_license", OBJPROP_COLOR, clrBlack);
   ObjectSetString(0, "edit_license", OBJPROP_TEXT, gLicenseKey);

   ObjectCreate(0, "btn_save", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "btn_save", OBJPROP_XDISTANCE, mx + 30);
   ObjectSetInteger(0, "btn_save", OBJPROP_YDISTANCE, my + 80);
   ObjectSetInteger(0, "btn_save", OBJPROP_XSIZE, 90);
   ObjectSetInteger(0, "btn_save", OBJPROP_YSIZE, 24);
   ObjectSetString(0, "btn_save", OBJPROP_TEXT, "Save");
   ObjectSetInteger(0, "btn_save", OBJPROP_BGCOLOR, clrAliceBlue);

   ObjectCreate(0, "btn_cancel", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "btn_cancel", OBJPROP_XDISTANCE, mx + 140);
   ObjectSetInteger(0, "btn_cancel", OBJPROP_YDISTANCE, my + 80);
   ObjectSetInteger(0, "btn_cancel", OBJPROP_XSIZE, 90);
   ObjectSetInteger(0, "btn_cancel", OBJPROP_YSIZE, 24);
   ObjectSetString(0, "btn_cancel", OBJPROP_TEXT, "Cancel");
   ObjectSetInteger(0, "btn_cancel", OBJPROP_BGCOLOR, clrWhiteSmoke);
}

void RemoveAuthPanel()
{
   string objs[] = {"auth_panel", "lbl_user", "edit_user", "lbl_license", "edit_license", "btn_save", "btn_cancel"};
   for(int i = 0; i < ArraySize(objs); i++)
      ObjectDelete(0, objs[i]);
}

//+------------------------------------------------------------------+
//| GUI callbacks                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "btn_save")
   {
      string newUser = ObjectGetString(0, "edit_user", OBJPROP_TEXT);
      string newKey  = ObjectGetString(0, "edit_license", OBJPROP_TEXT);

      StringTrimLeft(newUser);  StringTrimRight(newUser);
      StringTrimLeft(newKey);   StringTrimRight(newKey);

      if(newUser == "" || newKey == "")
      {
         Alert("[FlameBot][ERROR] FlameBot ID and License Key are required.");
         return;
      }
      if(!IsValidFlamebotId(newUser))
      {
         Alert("[FlameBot][ERROR] Invalid FlameBot ID. Please login from Desktop App.");
         return;
      }

      gUserId     = newUser;
      gLicenseKey = newKey;
      gAuthReady  = true;

      gLoginAnnounced      = false;
      gLotConfigured       = false;
      gSymbolConfigured    = false;
      gTradingUnlocked     = false;
      gWaitingAnnounced    = false;
      gLotFinalPrinted     = false;
      gSymbolFinalPrinted  = false;
      gLotPrintedMode      = "";
      gLotPrintedCustom    = 0.0;
      gSymbolPrintedMode   = "";
      gSymbolPrintedCount  = 0;
      gPSLFinalPrinted     = false;
      gLastPSLCount        = -1;
      gSymbolsPushedOnce   = false;
      gHeartbeatSent       = false;
      gLoginOk             = false;
      gAccountType         = "UNKNOWN";
      gIsPropAccount       = false;
      gAccountTypeReady    = false;
      gLoginBlocked        = false;
      gLoginBlockReason    = "";
      gLoginBlockLogged    = false;
      gAutoConnectAttempted = true;

      FBLogInfo(StringFormat("[FlameBot] Logging in FlameBot ID %s", gUserId));

      if(!SendEaLogin())
      {
         FBLogError(StringFormat("[FlameBot][ERROR] EA login failed: %s", gLastHeartbeatResponse));
         return;
      }

      if(!SendEaHeartbeat())
      {
         FBLogError(StringFormat("[FlameBot][ERROR] EA login failed: %s", gLastHeartbeatResponse));
         return;
      }

      SaveAuth(gUserId, gLicenseKey);
      RemoveAuthPanel();

      FBLogInfo("[FlameBot][INFO] EA login successful");
      FBLogInfo(StringFormat("[FlameBot][INFO] Credentials saved via GUI for FlameBot ID %s", gUserId));
      gHeartbeatSent = true;
      PushSymbolsToBackend();
      RefreshBackendSettings();
      AnnounceWaitingIfNeeded();
   }

   if(sparam == "btn_cancel")
   {
      RemoveAuthPanel();
      gAuthReady = (gUserId != "" && gLicenseKey != "");
      if(!gAuthReady)
      {
         Alert("[FlameBot][ERROR] Credentials not set. Trading paused.");
         CreateAuthPanel();
      }
   }
}

//+------------------------------------------------------------------+
//| Expert events                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   gLogLevel = ClampLogLevel(InpLogLevel);
   gTradeUidTtlSec = (int)InpTradeUidTtlSec;
   if(gTradeUidTtlSec < 0)
      gTradeUidTtlSec = 0;

   // Startup banner: write to file only (avoid cluttering Terminal/Experts).
   FBWriteLogLine(StringFormat("[FlameBot][INFO] let watch started | build_ts=%s | mirror=%s | log_to_file=%s | file=%s",
                               TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS),
                               InpMirrorLogsToTerminal ? "ON" : "OFF",
                               InpLogToFile ? "ON" : "OFF",
                               InpLogFileName));

   FBCleanupTradeUidGlobals();
   gLastTradeUidCleanupMs = GetTickCount64();
   if(InpPrintStartupStatus)
   {
      if(gLogLevel >= FB_LOG_INFO)
         FBLogInfo(StringFormat("[FlameBot][INFO] Log level=%d (0=ERROR,1=WARN,2=INFO,3=DEBUG)", gLogLevel));
      else if(gLogLevel == FB_LOG_WARN)
         FBLogWarn(StringFormat("[FlameBot][WARN] Log level=%d (0=ERROR,1=WARN,2=INFO,3=DEBUG)", gLogLevel));
      else
         FBLogError(StringFormat("[FlameBot][ERROR] Log level=%d (0=ERROR,1=WARN,2=INFO,3=DEBUG)", gLogLevel));
   }

   BuildSymbolAliases();

   gTerminalId = GetTerminalId();

   FBSchedulerLoadState();
   if(gSchedulerPaused)
      FBLogWarn("[FlameBot][WARN] Scheduler state restored: EA is currently PAUSED");

   // Privacy + correctness: do not auto-use input credentials.
   // Only use per-terminal saved auth, otherwise require GUI login.
   gUserId     = "";
   gLicenseKey = "";

   string savedUser = "";
   string savedKey  = "";
   if(LoadAuth(savedUser, savedKey))
   {
      gUserId = savedUser;
      gLicenseKey = savedKey;
   }

   gAuthReady = (gUserId != "" && gLicenseKey != "");
   gLoginOk = false;
   gHeartbeatSent = false;
   gAccountType = "UNKNOWN";
   gIsPropAccount = false;
   gAccountTypeReady = false;

   if(gAuthReady)
   {
      FBLogInfo("[FlameBot][INFO] Credentials loaded. EA will connect automatically.");
      if(!FBIsAuthPanelSuppressed())
      {
         CreateAuthPanel();
         FBSuppressAuthPanel();
      }

      // Validate session immediately on startup.
      // If the license is already active elsewhere, this must NOT unlock settings.
      if(!gAutoConnectAttempted)
      {
         gAutoConnectAttempted = true;
         if(SendEaLogin() && SendEaHeartbeat())
         {
            PushSymbolsToBackend();
            RefreshBackendSettings();
            AnnounceWaitingIfNeeded();
         }
      }
   }

   else
   {
      FBLogInfo("[FlameBot][INFO] Provide credentials in the panel to start.");
      CreateAuthPanel();
   }

   last_poll = GetTickCount64();
   gTimerStarted = false;
   if(InpUseTimerForSettings)
      FBEnableTimerSafe();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(gAuthReady)
      NotifyBackendLogout();
   if(InpUseTimerForSettings && gTimerStarted)
      EventKillTimer();
   RemoveAuthPanel();

   // If user removes the EA from the chart, allow the panel to show again on next attach.
   if(reason == REASON_REMOVE)
      FBClearAuthPanelSuppression();
}

void PollSignalsAndCommandsIfDue();

void FBMaybeFlushTradeTxnPush()
{
   if(!gAuthReady)
      return;
   if(gLoginBlocked || !gLoginOk || !gAccountTypeReady)
      return;
   if(!gTradeTxnPushPending)
      return;

   ulong now = GetTickCount64();
   if(gLastTradeTxnPushMs > 0 && (now - gLastTradeTxnPushMs) < (ulong)gTradeTxnPushThrottleMs)
      return;

   gTradeTxnPushPending = false;
   gTradeTxnPushPendingSinceMs = 0;
   gLastTradeTxnPushMs = now;
   PushAllTradeStatesToBackend();
}

void OnTimer()
{
   // Match MT4: keep polling even when no ticks.
   if(!gAuthReady)
      return;
   PollSignalsAndCommandsIfDue();
}

void RefreshBackendSettingsIfNeeded()
{
   ulong now = GetTickCount64();

   // Match MT4: throttle backend refresh
   if(now - gLastBackendRefresh < (ulong)(InpBackendRefreshSec * 1000))
      return;
   gLastBackendRefresh = now;

   // Never auto-login here. Login is allowed only on startup (once) or manual GUI save.
   if(!gLoginOk || gLoginBlocked)
      return;

   // Hard gate: do not poll backend settings/trade-state until account_type is known.
   if(!gAccountTypeReady)
      return;

   // Always attempt heartbeat
   bool heartbeat_ok = SendEaHeartbeat();
   if(!heartbeat_ok)
   {
      if(StringFind(gLastHeartbeatResponse, "LOGGED_OUT") != -1)
         return;
      return;
   }

   // Push trade states to backend (for state-aware AI decisions)
   PushAllTradeStatesToBackend();

   // Only fetch settings if EA is alive
   RefreshBackendSettings();
}



void AnnounceWaitingIfNeeded()
{
   if(!gAuthReady)
      return;

   if(gLoginBlocked)
   {
      if(!gLoginBlockLogged)
      {
         FBLogWarn(StringFormat("[FlameBot][WARN] Login blocked: %s", (gLoginBlockReason == "" ? "License already active (sign-in required)" : gLoginBlockReason)));
         gLoginBlockLogged = true;
      }
      return;
   }

   // Don't show lot/symbol "waiting" messages unless login succeeded.
   if(!gLoginOk)
      return;

   if(!gLotConfigured && !gLotPendingLogged)
   {
      FBLogInfo("[FlameBot][INFO] Waiting for lot configuration");
      gLotPendingLogged = true;
   }

   if(!gSymbolConfigured && !gSymbolPendingLogged)
   {
      FBLogInfo("[FlameBot][INFO] Waiting for symbol configuration");
      gSymbolPendingLogged = true;
   }

   if(gLotConfigured && gSymbolConfigured)
   {
      gLotPendingLogged = false;
      gSymbolPendingLogged = false;
   }
}

void OnTick()
{
   PollSignalsAndCommandsIfDue();
}

void PollSignalsAndCommandsIfDue()
{
   ulong now = GetTickCount64();
   if(gTradeUidTtlSec > 0 && (now - gLastTradeUidCleanupMs) > (ulong)(15 * 60 * 1000))
   {
      FBCleanupTradeUidGlobals();
      gLastTradeUidCleanupMs = now;
   }
   if(now - last_poll < (ulong)InpPollMs)
      return;
   last_poll = now;

   if(!gAuthReady)
      return;

   // Flush any pending post-transaction snapshot (handles throttled close events).
   FBMaybeFlushTradeTxnPush();

   RefreshBackendSettingsIfNeeded();

   // Apply scheduler rules (broker server time) even when trading is otherwise waiting.
   FBSchedulerTick();

   // Hard gate: do not poll signals/commands/trading until login+heartbeat AND account_type is known.
   if(!gLoginOk || !gHeartbeatSent || !gAccountTypeReady)
   {
      if(!gTradingUnlocked)
         AnnounceWaitingIfNeeded();
      return;
   }

   if(!gTradingUnlocked)
      AnnounceWaitingIfNeeded();

   string url = BuildEndpointUrl("get_signal");
   string body = "{" +
      "\"flamebot_id\":\"" + gUserId + "\"," +
      "\"user_id\":\"" + gUserId + "\"," +
      "\"license_key\":\"" + gLicenseKey + "\"," +
      "\"platform\":\"mt5\"," +
      "\"ea_id\":\"FLAME_RUNMT5\"," +
      "\"terminal_id\":\"" + gTerminalId + "\"" +
   "}";
   string response = HttpPostJson(url, body);
   if(response == "" || response == "NONE")
   {
      // No new signal, but still poll for backend commands (e.g. refresh_symbols).
      FBLogDebug("[FlameBot][DEBUG] Checking for trade commands...");
      string commandResponse = GetTradeCommand();
      FBLogDebug("[FlameBot][DEBUG] Command check result: " + commandResponse);
      if(commandResponse == "INVALID")
      {
         ResetCredentialsAfterInvalid();
         return;
      }
      if(commandResponse != "NONE" && commandResponse != "")
      {
         FBLogInfo("[FlameBot][INFO] Executing pending command");
         ExecuteTradeCommand(commandResponse);
      }
      return;
   }


   if(response == "INVALID")
   {
      ResetCredentialsAfterInvalid();
      return;
   }

   FBLogDebug("[FlameBot][DEBUG] Raw response received:");
   FBLogDebug("[FlameBot][DEBUG] " + response);

   string signalType = "";
   string signalId   = "";
   string targetId   = "";
   string rawText    = "";
   string groupId    = "";
   string tradeUid   = "";

   if(!ExtractJsonString(response, "type", signalType))
   {
      FBLogError("[FlameBot][ERROR] Invalid signal format (missing type)");
      return;
   }

   ExtractJsonString(response, "signal_id", signalId);
   ExtractJsonString(response, "target_id", targetId);
   ExtractJsonString(response, "trade_uid", tradeUid);
   ExtractJsonString(response, "raw_text", rawText);
   ExtractJsonString(response, "group_id", groupId);
   TrimString(groupId);

   FBLogDebug(StringFormat("[FlameBot][DEBUG] Signal details | type=%s | signal_id=%s | target_id=%s | group_id=%s", signalType, signalId, targetId, groupId));
   string effectiveSignalId = (StringLen(targetId) > 0) ? targetId : signalId;

   Signal s;
   bool isUpdate = (signalType == "UPDATE_SIGNAL");

   if(isUpdate)
   {
      // Check if this is a COMMAND (close/breakeven) instead of SL/TP modification
      string lowerText = rawText;
      StringToLower(lowerText);
      
      bool isCloseCommand = (StringFind(lowerText, "close") != -1 || StringFind(lowerText, "exit") != -1);
      bool isBreakevenCommand = (StringFind(lowerText, "be ") != -1 || StringFind(lowerText, "breakeven") != -1 || 
                                  StringFind(lowerText, "set be") != -1 || StringFind(lowerText, "setbe") != -1);
      
      if(isCloseCommand || isBreakevenCommand)
      {
         FBLogDebug(StringFormat("[FlameBot][DEBUG] Command detected in UPDATE_SIGNAL: %s", rawText));

         string cmdUid = effectiveSignalId;
         string cmdAction = isCloseCommand ? "close" : "breakeven";
         if(FBHasRejectedCmd(cmdAction, cmdUid))
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] UPDATE_SIGNAL %s ignored (previously rejected)", (isCloseCommand ? "CLOSE" : "BREAKEVEN")));
            return;
         }
         
         // [FlameBot][INFO] TOGGLE ENFORCEMENT - Check before execution
         if(isCloseCommand && !gAllowMessageClose)
         {
            FBRememberRejectedCmd(cmdAction, cmdUid);
            FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL CLOSE ignored (toggle OFF)");
            return;
         }
         
         if(isBreakevenCommand && !gAllowMessageBreakeven)
         {
            FBRememberRejectedCmd(cmdAction, cmdUid);
            FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL BREAKEVEN ignored (toggle OFF)");
            return;
         }
         
         // CRITICAL: Always use signal_id when available (ignore "all" keyword)
         string action = isCloseCommand ? "close_trade" : "set_breakeven";
         
         // For signal-scoped commands, pass the signal_id to filter trades
         if(HasTradesForSignal(effectiveSignalId))
         {
            FBLogInfo(StringFormat("[FlameBot][INFO] Executing %s | signal_id=%s", action, targetId));
            if(isCloseCommand)
               ExecuteCloseTrade("signal", "", "", targetId, groupId, true);
            else
               ExecuteBreakeven("signal", "", "", targetId, groupId);
         }
         else
         {
            FBLogWarn("[FlameBot][WARN] No trades found for this signal");
         }
         
         // 🔥 CRITICAL: Consume the command from queue to prevent duplicate execution
         // The desktop app stores this command in pending_commands, so we must remove it
         GetTradeCommand();
      }
      else if(HasTradesForSignal(effectiveSignalId))
      {
         // Check if this is a trade command disguised as UPDATE_SIGNAL
         string lowerText = rawText;
         StringToLower(lowerText);
         
         bool isSecureHalfCommand = (StringFind(lowerText, "secure half") != -1 || 
                                     StringFind(lowerText, "secure 50") != -1 || 
                                     StringFind(lowerText, "close half") != -1);
         bool isBreakevenCommand = (StringFind(lowerText, "breakeven") != -1 || 
                                   StringFind(lowerText, "break even") != -1 || 
                                   StringFind(lowerText, "set be") != -1);
         bool isCloseCommand = (StringFind(lowerText, "close all") != -1 || 
                               StringFind(lowerText, "close") != -1);
         
         // Route to appropriate command handler
         if(isSecureHalfCommand)
         {
            FBLogInfo(StringFormat("[FlameBot] Secure-half command detected in signal | target=%s", targetId));

            string cmdUid2 = effectiveSignalId;
            if(FBHasRejectedCmd("secure_half", cmdUid2))
            {
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL SECURE-HALF ignored (previously rejected)");
               return;
            }
            if(!gAllowSecureHalf)
            {
               FBRememberRejectedCmd("secure_half", cmdUid2);
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL SECURE-HALF ignored (toggle OFF)");
               return;
            }
            
            // Apply breakeven based on user preference toggle only
            bool applyBreakeven = gAllowMessageBreakeven;
            ExecuteSecureHalf("signal", "", "", targetId, applyBreakeven, groupId);
         }
         else if(isBreakevenCommand && !isSecureHalfCommand)
         {
            FBLogInfo(StringFormat("[FlameBot] Breakeven command detected in signal | target=%s", targetId));

            string cmdUid3 = effectiveSignalId;
            if(FBHasRejectedCmd("breakeven", cmdUid3))
            {
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL BREAKEVEN ignored (previously rejected)");
               return;
            }
            if(!gAllowMessageBreakeven)
            {
               FBRememberRejectedCmd("breakeven", cmdUid3);
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL BREAKEVEN ignored (toggle OFF)");
               return;
            }
            ExecuteBreakeven("signal", "", "", targetId, groupId);
         }
         else if(isCloseCommand)
         {
            FBLogInfo(StringFormat("[FlameBot] Close command detected in signal | target=%s", targetId));

            string cmdUid4 = effectiveSignalId;
            if(FBHasRejectedCmd("close", cmdUid4))
            {
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL CLOSE ignored (previously rejected)");
               return;
            }
            if(!gAllowMessageClose)
            {
               FBRememberRejectedCmd("close", cmdUid4);
               FBLogWarn("[FlameBot][WARN] UPDATE_SIGNAL CLOSE ignored (toggle OFF)");
               return;
            }
            ExecuteCloseTrade("signal", "", "", targetId, groupId, true);
         }
         else
         {
            // Standard SL/TP modification logic
            if(ParseUpdateOnly(rawText, s))
            {
               if(!gTradingUnlocked)
               {
                  FBLogDebug("[FlameBot][DEBUG] Dry-run mode: update received, trade modification blocked.");
                  return;
               }

               FBLogInfo(StringFormat("[FlameBot][INFO] Update received - modifying trades | target_id=%s", targetId));
               ModifyExistingTrades(s, targetId);
            }
            else
            {
               FBLogWarn("[FlameBot][WARN] Update signal ignored (no SL/TP found)");
            }
         }
      }
      else
      {
         if(ParseSignal(rawText, s))
         {
                if(gSchedulerPaused)
                {
                   FBLogInfo("[FlameBot][INFO] Scheduler paused: trade entry blocked");
                   return;
                }
            if(!gTradingUnlocked)
            {
               FBLogDebug("[FlameBot][DEBUG] Dry-run mode: update can open trade, but trading is locked.");
               return;
            }

            if(StringLen(groupId) == 0 || groupId == "0")
            {
               FBLogError("[FlameBot][ERROR] Signal rejected: missing group id");
               return;
            }
            FBLogInfo(StringFormat("[FlameBot][INFO] Update received - placing new trade | signal_id=%s", signalId));
               string dedupeUid2 = (StringLen(tradeUid) > 0) ? tradeUid : signalId;
               if(FBHasExecutedTradeUid(dedupeUid2))
               {
                  FBLogWarn(StringFormat("[FlameBot][WARN] Duplicate trade_uid blocked (update-open) | trade_uid=%s | group_id=%s", dedupeUid2, groupId));
               }
               else
               {
                  // Always tag trades with signal_id for command targeting.
                  string tagSignalId2 = (StringLen(signalId) > 0) ? signalId : dedupeUid2;
                  if(PlaceTrades(s, tagSignalId2, gIsPropAccount, groupId))
                  {
                     FBRememberTradeUid(dedupeUid2);
                     SaveAuth(gUserId, gLicenseKey);
                  }
               }
         }
         else
         {
            FBLogWarn("[FlameBot][WARN] Update signal ignored (not a valid trade yet)");
         }
      }
   }
   else
   {
      // Pre-parse command handling to prevent admin commands from being treated as NEW_SIGNAL trades
      string lowerCmd = rawText;
      StringToLower(lowerCmd);
      bool isCloseCmd  = (StringFind(lowerCmd, "close") != -1 || StringFind(lowerCmd, "exit") != -1);
      bool isBECmd     = (StringFind(lowerCmd, "breakeven") != -1 || StringFind(lowerCmd, "break even") != -1 || StringFind(lowerCmd, "set be") != -1 || StringFind(lowerCmd, "setbe") != -1);
      bool isSecureCmd = (StringFind(lowerCmd, "secure half") != -1 || StringFind(lowerCmd, "secure 50") != -1 || StringFind(lowerCmd, "close half") != -1);

      if(isCloseCmd || isBECmd || isSecureCmd)
      {
         // 🔗 REPLY CHAIN: Check if this NEW_SIGNAL is a reply to an existing signal (targetId)
         // If targetId exists and has trades, use that for command execution
         if(StringLen(targetId) > 0 && HasTradesForSignal(targetId))
         {
            FBLogInfo(StringFormat("[FlameBot] Reply chain detected | NEW_SIGNAL command is reply to signal: %s", targetId));

            string cmdUid5 = targetId;
            if(isCloseCmd && FBHasRejectedCmd("close", cmdUid5))
            {
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL CLOSE ignored (previously rejected)");
               return;
            }
            if(isBECmd && FBHasRejectedCmd("breakeven", cmdUid5))
            {
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL BREAKEVEN ignored (previously rejected)");
               return;
            }
            if(isSecureCmd && FBHasRejectedCmd("secure_half", cmdUid5))
            {
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL SECURE-HALF ignored (previously rejected)");
               return;
            }
            
            if(isCloseCmd && !gAllowMessageClose)
            {
               FBRememberRejectedCmd("close", cmdUid5);
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL CLOSE ignored (toggle OFF)");
               return;
            }
            if(isBECmd && !gAllowMessageBreakeven)
            {
               FBRememberRejectedCmd("breakeven", cmdUid5);
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL BREAKEVEN ignored (toggle OFF)");
               return;
            }
            if(isSecureCmd && !gAllowSecureHalf)
            {
               FBRememberRejectedCmd("secure_half", cmdUid5);
               FBLogWarn("[FlameBot][WARN] NEW_SIGNAL SECURE-HALF ignored (toggle OFF)");
               return;
            }
            
            // Execute command on the linked signal's trades
            if(isCloseCmd)
            {
               FBLogInfo(StringFormat("[FlameBot] Close command via reply chain | target=%s", targetId));
               ExecuteCloseTrade("signal", "", "", targetId, groupId, true);
            }
            else if(isBECmd)
            {
               FBLogInfo(StringFormat("[FlameBot] Breakeven command via reply chain | target=%s", targetId));
               ExecuteBreakeven("signal", "", "", targetId, groupId);
            }
            else if(isSecureCmd)
            {
               FBLogInfo(StringFormat("[FlameBot] Secure-half command via reply chain | target=%s", targetId));
               ExecuteSecureHalf("signal", "", "", targetId, gAllowMessageBreakeven, groupId);
            }
            return;
         }
         
         // Fallback: No reply chain, use symbol-based matching
         string cmdUid6 = signalId;
         if(isCloseCmd && FBHasRejectedCmd("close", cmdUid6))
         {
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL CLOSE ignored (previously rejected)");
            return;
         }
         if(isBECmd && FBHasRejectedCmd("breakeven", cmdUid6))
         {
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL BREAKEVEN ignored (previously rejected)");
            return;
         }
         if(isSecureCmd && FBHasRejectedCmd("secure_half", cmdUid6))
         {
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL SECURE-HALF ignored (previously rejected)");
            return;
         }

         if(isCloseCmd && !gAllowMessageClose)
         {
            FBRememberRejectedCmd("close", cmdUid6);
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL CLOSE ignored (toggle OFF)");
            return;
         }
         if(isBECmd && !gAllowMessageBreakeven)
         {
            FBRememberRejectedCmd("breakeven", cmdUid6);
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL BREAKEVEN ignored (toggle OFF)");
            return;
         }
         if(isSecureCmd && !gAllowSecureHalf)
         {
            FBRememberRejectedCmd("secure_half", cmdUid6);
            FBLogWarn("[FlameBot][WARN] NEW_SIGNAL SECURE-HALF ignored (toggle OFF)");
            return;
         }

         // Extract symbol from text and normalize to broker symbol
         string cmdSymbol = ExtractSymbolFromText(rawText);
         if(cmdSymbol != "")
            cmdSymbol = MatchSymbol(cmdSymbol);

         if(cmdSymbol == "")
         {
            FBLogError("[FlameBot][ERROR] Command ignored: unable to resolve symbol from text");
            return;
         }

         if(StringLen(groupId) == 0)
         {
            FBLogWarn("[FlameBot][WARN] Command skipped: group mismatch (command group does not own these trades)");
            return;
         }
         if(!HasAnyActiveTradeOnSymbol(cmdSymbol))
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] Unlinked command ignored: no active trades for %s", cmdSymbol));
            return;
         }

         // Resolve a usable signal_id from active comments (group-specific)
         string activeId = "";
         int ptotal2 = PositionsTotal();
         for(int pi2 = 0; pi2 < ptotal2 && StringLen(activeId)==0; pi2++)
         {
            ulong pt2 = PositionGetTicket(pi2);
            if(pt2==0) continue;
            if(!PositionSelectByTicket(pt2)) continue;
            if(PositionGetInteger(POSITION_MAGIC) != gMagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != cmdSymbol) continue;
            string pc2 = PositionGetString(POSITION_COMMENT);
            string commentGroup = ExtractGroupIdFromComment(pc2);
            if(commentGroup != "" && commentGroup != groupId)
            {
                  FBLogDebug(StringFormat("[FlameBot][DEBUG] Skip position (group mismatch) | ticket=%I64u | sym=%s | comment=%s | found_grp=%s | expected_grp=%s",
                                    pt2, PositionGetString(POSITION_SYMBOL), pc2, commentGroup, groupId));
               continue;
            }
            activeId = ExtractSignalIdFromComment(pc2);
         }
         int ototal3 = OrdersTotal();
         for(int oi3 = 0; oi3 < ototal3 && StringLen(activeId)==0; oi3++)
         {
            ulong ot3 = OrderGetTicket(oi3);
            if(ot3==0) continue;
            if(!OrderSelect(ot3)) continue;
            if(OrderGetInteger(ORDER_MAGIC) != gMagicNumber) continue;
            if(OrderGetString(ORDER_SYMBOL) != cmdSymbol) continue;
            string oc3 = OrderGetString(ORDER_COMMENT);
            string orderGroup = ExtractGroupIdFromComment(oc3);
            if(orderGroup != "" && orderGroup != groupId)
            {
                  FBLogDebug(StringFormat("[FlameBot][DEBUG] Skip pending (group mismatch) | ticket=%I64u | sym=%s | comment=%s | found_grp=%s | expected_grp=%s",
                                    ot3, OrderGetString(ORDER_SYMBOL), oc3, orderGroup, groupId));
               continue;
            }
            activeId = ExtractSignalIdFromComment(oc3);
         }
         if(StringLen(activeId) == 0)
         {
            FBLogWarn("[FlameBot][WARN] Command skipped: group mismatch (command group does not own these trades)");
            return;
         }

         FBLogInfo(StringFormat("[FlameBot][INFO] Command applied | symbol=%s | group_id=%s", cmdSymbol, groupId));
         if(isCloseCmd)
            ExecuteCloseTrade("signal", cmdSymbol, "", activeId, groupId);
         else if(isBECmd)
            ExecuteBreakeven("signal", cmdSymbol, "", activeId, groupId);
         else
            ExecuteSecureHalf("signal", cmdSymbol, "", activeId, gAllowMessageBreakeven, groupId);
         return;
      }

      if(ParseSignal(rawText, s))
      {
         if(gSchedulerPaused)
         {
            FBLogInfo("[FlameBot][INFO] Scheduler paused: trade entry blocked");
            return;
         }
         if(!gTradingUnlocked)
         {
            FBLogDebug("[FlameBot][DEBUG] Dry-run mode: new signal received, trading locked.");
            return;
         }

         if(StringLen(groupId) == 0 || groupId == "0")
         {
            FBLogError("[FlameBot][ERROR] Signal rejected: missing group id");
            return;
         }
         FBLogInfo(StringFormat("[FlameBot][INFO] New signal - placing trades | signal_id=%s | group_id=%s", signalId, groupId));
         string dedupeUid = (StringLen(tradeUid) > 0) ? tradeUid : signalId;
         if(FBHasExecutedTradeUid(dedupeUid))
         {
            FBLogWarn(StringFormat("[FlameBot][WARN] Duplicate trade_uid blocked (new) | trade_uid=%s | group_id=%s", dedupeUid, groupId));
         }
         else
         {
            // Always tag trades with signal_id for command targeting.
            string tagSignalId = (StringLen(signalId) > 0) ? signalId : dedupeUid;
            if(PlaceTrades(s, tagSignalId, gIsPropAccount, groupId))
            {
               FBRememberTradeUid(dedupeUid);
               SaveAuth(gUserId, gLicenseKey);
            }
         }
      }
      else
      {
         FBLogError("[FlameBot][ERROR] Failed to parse NEW signal");
      }
   }
   
   // Poll for trade control commands (breakeven, close)
   FBLogDebug("[FlameBot][DEBUG] Checking for trade commands...");
   string commandResponse = GetTradeCommand();
   if(commandResponse == "INVALID")    {       ResetCredentialsAfterInvalid();       return;    }
   FBLogDebug("[FlameBot][DEBUG] Command check result: " + commandResponse);
   if(commandResponse != "NONE" && commandResponse != "INVALID" && commandResponse != "")
   {
      FBLogInfo("[FlameBot][INFO] Executing pending command");
      ExecuteTradeCommand(commandResponse);
   }
}

bool FBComputeAccountToUsdRate(double &rate, string &pairUsed)
{
   string acc = FBUpper(FBGetAccountCurrency());
   if(acc == "")
      return(false);
   if(acc == "USD")
   {
      rate = 1.0;
      pairUsed = "USD";
      return(true);
   }

   string directPrefix = acc + "USD";
   double bid = 0.0;

   if(FBTryGetBid(directPrefix, bid))
   {
      rate = bid;
      pairUsed = directPrefix;
      return(true);
   }

   string best = "";
   if(FBFindBestSymbolByPrefix(directPrefix, best, bid))
   {
      rate = bid;
      pairUsed = best;
      return(true);
   }

   string invPrefix = "USD" + acc;
   if(FBTryGetBid(invPrefix, bid) && bid > 0.0)
   {
      rate = 1.0 / bid;
      pairUsed = invPrefix;
      return(true);
   }

   if(FBFindBestSymbolByPrefix(invPrefix, best, bid) && bid > 0.0)
   {
      rate = 1.0 / bid;
      pairUsed = best;
      return(true);
   }

   return(false);
}

bool FBGetAccountToUsdRate(double &rate)
{
   ulong now = GetTickCount64();
   if(gAccToUsdRateValid && (now - gAccToUsdRateLastMs) < 60000)
   {
      rate = gAccToUsdRate;
      return(true);
   }

   double r = 0.0;
   string pair = "";
   if(!FBComputeAccountToUsdRate(r, pair))
   {
      gAccToUsdRateValid = false;
      gAccToUsdRate = 1.0;
      gAccToUsdRateLastMs = now;
      gAccToUsdSymbol = "";
      rate = 0.0;

      if(now - gAccFxRateErrorLastMs > 30000)
      {
         string acc = FBGetAccountCurrency();
         FBLogError(StringFormat("[FlameBot][ERROR] Missing FX conversion for %s->USD. Need symbol %sUSD or USD%s (or broker suffix variant). Blocking trades for safety.", acc, acc, acc));
         gAccFxRateErrorLastMs = now;
      }
      return(false);
   }

   gAccToUsdRateValid = true;
   gAccToUsdRate = r;
   gAccToUsdRateLastMs = now;
   gAccToUsdSymbol = pair;
   rate = r;
   return(true);
}

bool FBConvertAccountToUsd(const double amountAcc, double &amountUsd)
{
   double rate = 0.0;
   if(!FBGetAccountToUsdRate(rate))
      return(false);
   amountUsd = amountAcc * rate;
   return(true);
}

double FBFloorToStep(const double value, const double step)
{
   if(step <= 0.0)
      return value;
   return(MathFloor(value / step) * step);
}

int FBVolumeDigitsFromStep(const double step)
{
   if(step <= 0.0)
      return 2;

   double x = step;
   int digits = 0;
   while(digits < 8)
   {
      double nearest = MathRound(x);
      if(MathAbs(x - nearest) <= 1e-8)
         break;
      x *= 10.0;
      digits++;
   }
   return digits;
}

bool FBCalcLotFromRiskAccount(const string symbol, const double entry_price, const double sl_price, const double riskAccInput, double &lot)
{
   lot = 0.0;
   if(riskAccInput <= 0.0)
      return(false);
   if(entry_price <= 0.0 || sl_price <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Risk lot sizing requires a valid SL. Trade blocked.");
      return(false);
   }

   double riskUsd = 0.0;
   if(!FBConvertAccountToUsd(riskAccInput, riskUsd))
      return(false);

   // Canonical pipeline: Account -> USD -> Account (execution)
   double riskAccExec = 0.0;
   if(!FBConvertUsdToAccount(riskUsd, riskAccExec))
      return(false);

   double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point_size  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point_value <= 0.0 || point_size <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Could not retrieve symbol info for " + symbol);
      return(false);
   }

   double points_to_sl = MathAbs(entry_price - sl_price) / point_size;
   if(points_to_sl <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Invalid SL distance for risk sizing. Trade blocked.");
      return(false);
   }

   // point_value is treated consistently with existing deviation/profit logic
   double risk_per_1lot = points_to_sl * point_value;
   if(risk_per_1lot <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Could not compute risk-per-lot for " + symbol);
      return(false);
   }

   double rawLot = riskAccExec / risk_per_1lot;

   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   int volDigits  = FBVolumeDigitsFromStep(stepLot);

   if(stepLot <= 0.0 || minLot <= 0.0 || maxLot <= 0.0)
   {
      FBLogError("[FlameBot][ERROR] Invalid volume constraints for " + symbol);
      return(false);
   }

   // Clamp then floor to step so we don't exceed the user's risk.
   rawLot = MathMax(minLot, MathMin(maxLot, rawLot));
   double steps = (rawLot - minLot) / stepLot;
   double floored = minLot + MathFloor(steps) * stepLot;
   if(floored < minLot)
      floored = minLot;

   lot = NormalizeDouble(floored, volDigits);
   if(!IsLotValidForSymbol(symbol, lot))
   {
      // As a fallback, try strict minLot
      lot = NormalizeDouble(minLot, volDigits);
      if(!IsLotValidForSymbol(symbol, lot))
      {
         FBLogError("[FlameBot][ERROR] Risk sizing produced an invalid lot for " + symbol);
         return(false);
      }
   }

   FBLogDebug(StringFormat("[FlameBot][DEBUG] Risk sizing: input=%.2f %s -> %.2f USD -> %.2f %s | points_to_sl=%.1f | risk/1lot=%.2f %s | lot=%.2f", riskAccInput, FBGetAccountCurrency(), riskUsd, riskAccExec, FBGetAccountCurrency(), points_to_sl, risk_per_1lot, FBGetAccountCurrency(), lot));
   return(true);
}
