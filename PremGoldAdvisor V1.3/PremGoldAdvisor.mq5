//+------------------------------------------------------------------+
//|                                            PremGoldAdvisor.mq5   |
//|                         PremGoldAdvisor V1.3                     |
//|  M5 dual-ladder: arm levels on candle → open side on touch only  |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor V1.3"
#property link      ""
#property version   "3.10"
#property description "PremGoldAdvisor V1.3 — On each M5 candle calculates Buy/Sell entry levels, then opens that side's 5 orders only when the level is touched. Protective initial SL; after TP1 trails remaining to net break-even. Designed for XAUUSD. Does not guarantee profit."

#include <Trade/Trade.mqh>

#define CLR_BG        C'12,12,16'
#define CLR_CARD      C'22,22,28'
#define CLR_LINE      C'48,44,32'
#define CLR_GOLD      C'212,175,55'
#define CLR_GOLD2     C'240,205,90'
#define CLR_GREEN     C'0,186,90'
#define CLR_RED       C'220,52,62'
#define CLR_TEXT      C'236,236,240'
#define CLR_MUTED     C'148,148,156'
#define CLR_BTN       C'32,28,18'
#define CLR_BTN2      C'42,22,26'

#define LEVELS        5
#define COMMENT_PREFIX "PGA13"

enum ENUM_DIST_MODE
  {
   DIST_PRICE  = 0,   // Price distance (e.g. 0.50 on gold)
   DIST_POINTS = 1    // Symbol points (_Point)
  };

input group "=== Core ==="
input bool              InpTradeEnabled          = true;        // Enable auto trading
input double            InpLotSize               = 0.01;        // Lot size per order
input ulong             InpMagic                 = 130213;      // Magic number
input int               InpDeviationPoints       = 50;          // Max slippage (points)
input int               InpMaxRetries            = 3;           // Order send retries
input string            InpComment               = "PGA-V1.3";  // Order comment tag
input ENUM_TIMEFRAMES   InpWorkTimeframe         = PERIOD_M5;   // Working timeframe

input group "=== Entry Levels (from M5 open) ==="
input ENUM_DIST_MODE    InpDistanceMode          = DIST_PRICE;  // Distance mode (entry / TP / SL)
input double            InpBuyEntryOffset        = 0.20;        // Buy level = Open - offset
input double            InpSellEntryOffset       = 0.20;        // Sell level = Open + offset
input bool              InpRequireLeaveFirst     = true;        // If level is near market, wait for leave then retest

input group "=== Take Profit Ladder ==="
input double            InpTp1                   = 0.50;        // TP1 distance from fill
input double            InpTp2                   = 1.00;        // TP2 distance from fill
input double            InpTp3                   = 1.50;        // TP3 distance from fill
input double            InpTp4                   = 2.00;        // TP4 distance from fill
input double            InpTp5                   = 2.50;        // TP5 distance from fill

input group "=== Stop Loss / Trail ==="
input double            InpInitialSl             = 3.00;        // Initial protective SL distance (0 = none)
input bool              InpTrailEnabled          = true;        // Enable TP-step trailing SL
input bool              InpBeCompensateSpread    = true;        // Net BE: cover spread at TP1 trail
input double            InpCommissionPerLot      = 0.0;         // Round-turn commission per 1.0 lot (account ccy)
input int               InpBreakevenExtraPoints  = 0;           // Extra points beyond net BE

input group "=== Cycle Control ==="
input bool              InpAllowStackCycles      = false;       // Allow new basket while same side still open
input int               InpMaxOpenPositions      = 50;          // Hard cap on EA open positions (0=off)

input group "=== Filters ==="
input double            InpMaxSpread             = 0.80;        // Max spread in price (0=off)
input int               InpStartHour             = 0;           // Trading start hour (server)
input int               InpEndHour               = 23;          // Trading end hour (server)
input bool              InpCloseOnFriday         = false;       // Close all late Friday
input int               InpFridayCloseHour       = 21;          // Friday close hour (server)

input group "=== Display ==="
input bool              InpShowPanel             = true;        // Show on-chart panel
input int               InpPanelX                = 12;          // Panel X offset
input int               InpPanelY                = 18;          // Panel Y offset
input bool              InpShowLevels            = true;        // Draw entry / TP guide lines
input bool              InpApplyChartTheme       = true;        // Dark gold chart theme
input bool              InpLogActions            = true;        // Print trail / open actions

//--- runtime
CTrade   g_trade;
int      g_digits     = 2;
double   g_point      = 0.01;
double   g_tickSize   = 0.01;
long     g_stopsLevel = 0;

datetime g_lastBarTime   = 0;
datetime g_armedBarTime  = 0;     // candle whose levels are armed
datetime g_buyOpenedBar  = 0;     // anti-duplicate buy basket
datetime g_sellOpenedBar = 0;     // anti-duplicate sell basket

double   g_barOpen   = 0.0;
double   g_buyLevel  = 0.0;       // planned touch entry (Buy)
double   g_sellLevel = 0.0;       // planned touch entry (Sell)

bool     g_buyLeftLevel  = false; // price left buy level (for retest)
bool     g_sellLeftLevel = false;
bool     g_levelsArmed   = false;

double   g_buyEntry  = 0.0;       // actual/reference fill for buy basket
double   g_sellEntry = 0.0;
double   g_buyTp[LEVELS + 1];
double   g_sellTp[LEVELS + 1];
double   g_buySlInit  = 0.0;
double   g_sellSlInit = 0.0;

int      g_buyHitLevel  = 0;
int      g_sellHitLevel = 0;
int      g_buyTrailTo   = 0;      // 0=none, 1=net BE, 2=TP1, ...
int      g_sellTrailTo  = 0;

bool     g_paused      = false;
bool     g_flattening  = false;
string   g_status      = "READY";
string   g_lastAction  = "-";
string   g_blockReason = "";

string   g_panelPrefix = "PGA13_UI_";

//+------------------------------------------------------------------+
int OnInit()
  {
   g_digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = g_point;
   g_stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   g_trade.SetExpertMagicNumber((int)InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   ConfigureFilling();

   ArrayInitialize(g_buyTp, 0.0);
   ArrayInitialize(g_sellTp, 0.0);

   LoadState();
   RecoverFromPositions();

   if(InpApplyChartTheme)
      ApplyChartTheme();
   if(InpShowPanel)
      BuildPanel();

   if(InpWorkTimeframe != PERIOD_M5)
      Print("PremGoldAdvisor V1.3 warning: working TF is not M5 (",
            EnumToString(InpWorkTimeframe), ")");

   // Arm current candle levels on attach (wait for touch — do not open immediately)
   if(InpTradeEnabled && !g_paused)
      ArmCandleLevels(false);

   g_status = g_paused ? "PAUSED" : (g_levelsArmed ? "WAITING TOUCH" : "READY");
   PrintFormat("PremGoldAdvisor V1.3 init on %s  magic=%s  lot=%.2f  TF=%s",
               _Symbol, IntegerToString((long)InpMagic), InpLotSize, EnumToString(InpWorkTimeframe));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveState();
   ObjectsDeleteAll(0, g_panelPrefix);
   ObjectsDeleteAll(0, "PGA13_LVL_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_flattening)
      return;

   if(InpCloseOnFriday && IsFridayCloseTime())
     {
      CloseAllOurPositions("Friday close");
      g_status = "FRIDAY CLOSE";
      UpdatePanel();
      return;
     }

   ManageOpenLadders();

   bool newBar = IsNewBar();
   if(newBar)
      ArmCandleLevels(true);

   if(!g_paused && InpTradeEnabled && g_levelsArmed)
      TryTriggerSides();

   if(InpShowLevels)
      DrawLevels();
   UpdatePanel();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == g_panelPrefix + "BTN_PAUSE")
     {
      g_paused = !g_paused;
      g_status = g_paused ? "PAUSED" : (g_levelsArmed ? "WAITING TOUCH" : "READY");
      g_lastAction = g_paused ? "Paused by user" : "Resumed by user";
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      SaveState();
      UpdatePanel();
     }
   else if(sparam == g_panelPrefix + "BTN_CLOSE")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      g_flattening = true;
      CloseAllOurPositions("Manual CLOSE ALL");
      g_flattening = false;
      ResetBasketState(true);
      ResetBasketState(false);
      g_status = g_paused ? "PAUSED" : (g_levelsArmed ? "WAITING TOUCH" : "READY");
      SaveState();
      UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
// Arm Buy/Sell entry levels from the new M5 open — NO orders yet
//+------------------------------------------------------------------+
void ArmCandleLevels(const bool fromNewBar)
  {
   datetime barTime = iTime(_Symbol, InpWorkTimeframe, 0);
   double   barOpen = iOpen(_Symbol, InpWorkTimeframe, 0);
   if(barTime <= 0 || barOpen <= 0.0)
     {
      g_blockReason = "No bar open";
      return;
     }

   if(!ValidateTpLadder())
     {
      g_blockReason = "Invalid TP ladder (must be ascending)";
      g_levelsArmed = false;
      return;
     }

   g_armedBarTime = barTime;
   g_barOpen      = NormalizePrice(barOpen);

   double buyOff  = DistToPrice(InpBuyEntryOffset);
   double sellOff = DistToPrice(InpSellEntryOffset);

   g_buyLevel  = NormalizePrice(g_barOpen - buyOff);
   g_sellLevel = NormalizePrice(g_barOpen + sellOff);

   // Per-candle trigger permission (anti-duplicate within this candle)
   // Do not clear open baskets — only re-arm waiting sides.
   if(fromNewBar || g_buyOpenedBar != barTime)
     {
      // keep g_buyOpenedBar if already opened this bar
     }
   if(g_buyOpenedBar != barTime)
      g_buyLeftLevel = !InpRequireLeaveFirst || !LevelIsNearMarket(true, g_buyLevel);
   else
      g_buyLeftLevel = true; // already used

   if(g_sellOpenedBar != barTime)
      g_sellLeftLevel = !InpRequireLeaveFirst || !LevelIsNearMarket(false, g_sellLevel);
   else
      g_sellLeftLevel = true;

   // If RequireLeaveFirst and price is already at/through level, force leave-first
   if(InpRequireLeaveFirst)
     {
      if(g_buyOpenedBar != barTime && LevelIsNearMarket(true, g_buyLevel))
         g_buyLeftLevel = false;
      if(g_sellOpenedBar != barTime && LevelIsNearMarket(false, g_sellLevel))
         g_sellLeftLevel = false;
     }
   else
     {
      if(g_buyOpenedBar != barTime)
         g_buyLeftLevel = true;
      if(g_sellOpenedBar != barTime)
         g_sellLeftLevel = true;
     }

   g_levelsArmed = true;
   g_blockReason = "";
   g_status = "WAITING TOUCH";
   g_lastAction = StringFormat("Armed M5 %s | Buy %s | Sell %s",
                               TimeToString(barTime, TIME_DATE|TIME_MINUTES),
                               DoubleToString(g_buyLevel, g_digits),
                               DoubleToString(g_sellLevel, g_digits));
   if(InpLogActions && fromNewBar)
      Print("PremGoldAdvisor V1.3 ", g_lastAction);
   SaveState();
  }

//+------------------------------------------------------------------+
bool LevelIsNearMarket(const bool isBuy, const double level)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pad = MathMax(ask - bid, MinStopDistance());

   if(isBuy)
     {
      // Buy level typically below market; "near" if ask already at/through it
      return (ask <= level + pad);
     }
   // Sell level typically above market; "near" if bid already at/through it
   return (bid >= level - pad);
  }

//+------------------------------------------------------------------+
void TryTriggerSides()
  {
   g_blockReason = "";

   if(!IsTradingHour())
     {
      g_blockReason = "Outside trading hours";
      return;
     }
   if(SpreadTooWide())
     {
      g_blockReason = "Spread too wide";
      return;
     }

   UpdateLeaveFlags();

   datetime barTime = g_armedBarTime;
   if(barTime <= 0)
      barTime = iTime(_Symbol, InpWorkTimeframe, 0);

   // --- Buy side ---
   if(g_buyOpenedBar != barTime && CanOpenSide(true))
     {
      if(IsLevelTouched(true, g_buyLevel))
         OpenSideBasket(true);
     }

   // --- Sell side ---
   if(g_sellOpenedBar != barTime && CanOpenSide(false))
     {
      if(IsLevelTouched(false, g_sellLevel))
         OpenSideBasket(false);
     }

   int buys = CountSide(true);
   int sells = CountSide(false);
   if(buys > 0 || sells > 0)
      g_status = StringFormat("LIVE B%d/S%d", buys, sells);
   else if(g_levelsArmed)
      g_status = "WAITING TOUCH";
  }

//+------------------------------------------------------------------+
void UpdateLeaveFlags()
  {
   if(!InpRequireLeaveFirst)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pad = MathMax(ask - bid, g_tickSize * 2.0);

   if(!g_buyLeftLevel && g_buyLevel > 0.0)
     {
      // Left = market moved away above the buy level
      if(ask > g_buyLevel + pad)
         g_buyLeftLevel = true;
     }
   if(!g_sellLeftLevel && g_sellLevel > 0.0)
     {
      // Left = market moved away below the sell level
      if(bid < g_sellLevel - pad)
         g_sellLeftLevel = true;
     }
  }

//+------------------------------------------------------------------+
bool IsLevelTouched(const bool isBuy, const double level)
  {
   if(level <= 0.0)
      return false;
   if(InpRequireLeaveFirst)
     {
      if(isBuy && !g_buyLeftLevel)
         return false;
      if(!isBuy && !g_sellLeftLevel)
         return false;
     }

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double high = iHigh(_Symbol, InpWorkTimeframe, 0);
   double low  = iLow(_Symbol, InpWorkTimeframe, 0);

   if(isBuy)
     {
      // Buy level below open: touch when price trades down to it
      // Also support level above market (buy stop): trade up through it
      if(level <= g_barOpen || g_barOpen <= 0.0)
         return (low <= level || bid <= level || ask <= level);
      return (high >= level || ask >= level);
     }

   // Sell level above open: touch when price trades up to it
   if(level >= g_barOpen || g_barOpen <= 0.0)
      return (high >= level || ask >= level || bid >= level);
   return (low <= level || bid <= level);
  }

//+------------------------------------------------------------------+
bool CanOpenSide(const bool isBuy)
  {
   if(!InpAllowStackCycles && CountSide(isBuy) > 0)
     {
      g_blockReason = isBuy ? "Buy basket still open" : "Sell basket still open";
      return false;
     }

   int openCount = CountOurPositions();
   if(InpMaxOpenPositions > 0 && openCount + LEVELS > InpMaxOpenPositions)
     {
      g_blockReason = "Max open positions cap";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void OpenSideBasket(const bool isBuy)
  {
   datetime barTime = g_armedBarTime;
   if(barTime <= 0)
      barTime = iTime(_Symbol, InpWorkTimeframe, 0);

   // Anti-duplicate for this candle/side
   if(isBuy && g_buyOpenedBar == barTime)
      return;
   if(!isBuy && g_sellOpenedBar == barTime)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
     {
      g_blockReason = "Invalid bid/ask";
      return;
     }

   double lot = NormalizeLot(InpLotSize);
   if(lot <= 0.0)
     {
      g_blockReason = "Invalid lot size";
      return;
     }

   double d1 = DistToPrice(InpTp1);
   double d2 = DistToPrice(InpTp2);
   double d3 = DistToPrice(InpTp3);
   double d4 = DistToPrice(InpTp4);
   double d5 = DistToPrice(InpTp5);
   double dSl = DistToPrice(InpInitialSl);

   int opened = 0;

   if(isBuy)
     {
      g_buyEntry = ask;
      g_buyTp[1] = NormalizePrice(ask + d1);
      g_buyTp[2] = NormalizePrice(ask + d2);
      g_buyTp[3] = NormalizePrice(ask + d3);
      g_buyTp[4] = NormalizePrice(ask + d4);
      g_buyTp[5] = NormalizePrice(ask + d5);
      // Protective initial SL only — NOT break-even
      g_buySlInit = (dSl > 0.0) ? NormalizePrice(ask - dSl) : 0.0;
      g_buyHitLevel = 0;
      g_buyTrailTo  = 0;

      for(int lvl = 1; lvl <= LEVELS; lvl++)
        {
         double sl = g_buySlInit;
         double tp = g_buyTp[lvl];
         if(!ValidateStops(true, ask, sl, tp))
           {
            g_blockReason = StringFormat("Buy%d stops invalid vs broker min distance", lvl);
            if(InpLogActions)
               Print("PremGoldAdvisor V1.3 ", g_blockReason);
            continue;
           }
         if(OpenMarket(true, lot, sl, tp, lvl))
            opened++;
        }

      g_buyOpenedBar = barTime;
      // Refresh reference entry from fills if available
      double avg = AverageOpenPrice(true);
      if(avg > 0.0)
        {
         g_buyEntry = avg;
         RebuildTpFromEntry(true, g_buyEntry);
        }
     }
   else
     {
      g_sellEntry = bid;
      g_sellTp[1] = NormalizePrice(bid - d1);
      g_sellTp[2] = NormalizePrice(bid - d2);
      g_sellTp[3] = NormalizePrice(bid - d3);
      g_sellTp[4] = NormalizePrice(bid - d4);
      g_sellTp[5] = NormalizePrice(bid - d5);
      g_sellSlInit = (dSl > 0.0) ? NormalizePrice(bid + dSl) : 0.0;
      g_sellHitLevel = 0;
      g_sellTrailTo  = 0;

      for(int lvl = 1; lvl <= LEVELS; lvl++)
        {
         double sl = g_sellSlInit;
         double tp = g_sellTp[lvl];
         if(!ValidateStops(false, bid, sl, tp))
           {
            g_blockReason = StringFormat("Sell%d stops invalid vs broker min distance", lvl);
            if(InpLogActions)
               Print("PremGoldAdvisor V1.3 ", g_blockReason);
            continue;
           }
         if(OpenMarket(false, lot, sl, tp, lvl))
            opened++;
        }

      g_sellOpenedBar = barTime;
      double avg = AverageOpenPrice(false);
      if(avg > 0.0)
        {
         g_sellEntry = avg;
         RebuildTpFromEntry(false, g_sellEntry);
        }
     }

   g_lastAction = StringFormat("%s touch @ %s → opened %d/5",
                               (isBuy ? "BUY" : "SELL"),
                               DoubleToString(isBuy ? g_buyLevel : g_sellLevel, g_digits),
                               opened);
   g_status = StringFormat("LIVE B%d/S%d", CountSide(true), CountSide(false));
   if(InpLogActions)
      Print("PremGoldAdvisor V1.3 ", g_lastAction);
   SaveState();
  }

//+------------------------------------------------------------------+
void RebuildTpFromEntry(const bool isBuy, const double entry)
  {
   double d1 = DistToPrice(InpTp1);
   double d2 = DistToPrice(InpTp2);
   double d3 = DistToPrice(InpTp3);
   double d4 = DistToPrice(InpTp4);
   double d5 = DistToPrice(InpTp5);
   if(isBuy)
     {
      g_buyTp[1] = NormalizePrice(entry + d1);
      g_buyTp[2] = NormalizePrice(entry + d2);
      g_buyTp[3] = NormalizePrice(entry + d3);
      g_buyTp[4] = NormalizePrice(entry + d4);
      g_buyTp[5] = NormalizePrice(entry + d5);
     }
   else
     {
      g_sellTp[1] = NormalizePrice(entry - d1);
      g_sellTp[2] = NormalizePrice(entry - d2);
      g_sellTp[3] = NormalizePrice(entry - d3);
      g_sellTp[4] = NormalizePrice(entry - d4);
      g_sellTp[5] = NormalizePrice(entry - d5);
     }
  }

//+------------------------------------------------------------------+
bool OpenMarket(const bool isBuy, const double lot, double sl, double tp, const int level)
  {
   string cmt = MakeComment(isBuy, level);
   bool ok = false;

   for(int attempt = 1; attempt <= InpMaxRetries; attempt++)
     {
      ResetLastError();
      if(isBuy)
         ok = g_trade.Buy(lot, _Symbol, 0.0, sl, tp, cmt);
      else
         ok = g_trade.Sell(lot, _Symbol, 0.0, sl, tp, cmt);

      if(ok)
         break;

      uint ret = g_trade.ResultRetcode();
      if(ret == TRADE_RETCODE_REQUOTE || ret == TRADE_RETCODE_PRICE_OFF ||
         ret == TRADE_RETCODE_PRICE_CHANGED || ret == TRADE_RETCODE_TIMEOUT)
        {
         SoftSleep(50 * attempt);
         ConfigureFilling();
         continue;
        }
      break;
     }

   if(!ok && InpLogActions)
      PrintFormat("PremGoldAdvisor V1.3 open %s L%d failed: %s",
                  (isBuy ? "BUY" : "SELL"), level, g_trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
void ManageOpenLadders()
  {
   if(CountOurPositions() == 0)
      return;

   if((CountSide(true) > 0 && g_buyTp[1] <= 0.0) ||
      (CountSide(false) > 0 && g_sellTp[1] <= 0.0))
      RecoverFromPositions();

   DetectTpHits(true);
   DetectTpHits(false);

   if(InpTrailEnabled)
     {
      ApplyTrailSide(true);
      ApplyTrailSide(false);
     }
  }

//+------------------------------------------------------------------+
void DetectTpHits(const bool isBuy)
  {
   if(CountSide(isBuy) == 0 && (isBuy ? g_buyTrailTo : g_sellTrailTo) <= 0)
     {
      // Basket finished — clear side state when flat after activity
      return;
     }

   double tp[];
   ArrayResize(tp, LEVELS + 1);
   for(int i = 1; i <= LEVELS; i++)
      tp[i] = isBuy ? g_buyTp[i] : g_sellTp[i];

   if(tp[1] <= 0.0)
      return;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double high = iHigh(_Symbol, InpWorkTimeframe, 0);
   double low  = iLow(_Symbol, InpWorkTimeframe, 0);

   int hit = isBuy ? g_buyHitLevel : g_sellHitLevel;

   for(int lvl = LEVELS; lvl >= 1; lvl--)
     {
      if(tp[lvl] <= 0.0)
         continue;

      bool touched = false;
      if(isBuy)
         touched = (high >= tp[lvl] || bid >= tp[lvl]);
      else
         touched = (low <= tp[lvl] || ask <= tp[lvl]);

      if(touched)
        {
         hit = MathMax(hit, lvl);
         break;
        }
     }

   if(isBuy)
      g_buyHitLevel = hit;
   else
      g_sellHitLevel = hit;
  }

//+------------------------------------------------------------------+
void ApplyTrailSide(const bool isBuy)
  {
   int hit = isBuy ? g_buyHitLevel : g_sellHitLevel;
   if(hit <= 0)
      return;

   int desiredStep = hit;   // 1=net BE, 2=SL@TP1, ...
   int applied = isBuy ? g_buyTrailTo : g_sellTrailTo;
   if(desiredStep <= applied)
      return;

   for(int step = applied + 1; step <= desiredStep; step++)
     {
      string action;
      if(step == 1)
         action = StringFormat("%s TP1 — remaining SL -> net BE", isBuy ? "BUY" : "SELL");
      else if(step >= LEVELS)
         action = StringFormat("%s TP%d — basket complete", isBuy ? "BUY" : "SELL", step);
      else
         action = StringFormat("%s TP%d — remaining SL -> TP%d", isBuy ? "BUY" : "SELL", step, step - 1);

      // Step 5: final order closes on its own broker TP — just mark trail done
      if(step >= LEVELS)
        {
         if(isBuy)
            g_buyTrailTo = step;
         else
            g_sellTrailTo = step;
         g_lastAction = action;
         SaveState();
         continue;
        }

      double target = TrailTargetPrice(isBuy, step);
      if(target <= 0.0)
         continue;

      if(MoveRemainingStopsOnSide(isBuy, step, target, action))
        {
         if(isBuy)
            g_buyTrailTo = step;
         else
            g_sellTrailTo = step;
         SaveState();
        }
      else
         break; // retry next tick
     }
  }

//+------------------------------------------------------------------+
double TrailTargetPrice(const bool isBuy, const int step)
  {
   if(step <= 0)
      return 0.0;

   if(step == 1)
      return 0.0; // computed per-position in MoveRemainingStopsOnSide (net BE)

   int tpIndex = step - 1;
   if(tpIndex < 1 || tpIndex > LEVELS)
      return 0.0;
   return isBuy ? g_buyTp[tpIndex] : g_sellTp[tpIndex];
  }

//+------------------------------------------------------------------+
// Net break-even for one position: covers spread (+ optional commission) so a
// return to entry closes near flat after costs.
//+------------------------------------------------------------------+
double NetBreakEvenSL(const bool isBuy, const double openPrice, const double volume)
  {
   double sl = openPrice;
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spread < 0.0)
      spread = 0.0;

   if(InpBeCompensateSpread)
     {
      // Buy closes on Bid; Sell closes on Ask — push SL through the spread
      if(isBuy)
         sl += spread;
      else
         sl -= spread;
     }

   double commPrice = CommissionToPrice(volume);
   if(isBuy)
      sl += commPrice;
   else
      sl -= commPrice;

   double extra = InpBreakevenExtraPoints * g_point;
   if(isBuy)
      sl += extra;
   else
      sl -= extra;

   return NormalizePrice(sl);
  }

//+------------------------------------------------------------------+
double CommissionToPrice(const double volume)
  {
   if(InpCommissionPerLot <= 0.0 || volume <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   // Money cost for this volume (round-turn), converted to price distance
   double money = InpCommissionPerLot * (volume / 1.0);
   double valuePerPrice = (tickValue / tickSize) * volume;
   if(valuePerPrice <= 0.0)
      return 0.0;
   return money / valuePerPrice;
  }

//+------------------------------------------------------------------+
bool MoveRemainingStopsOnSide(const bool isBuy, const int step,
                              const double sharedTarget, const string action)
  {
   bool any = false;
   bool allOk = true;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition())
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if(isBuy && type != POSITION_TYPE_BUY)
         continue;
      if(!isBuy && type != POSITION_TYPE_SELL)
         continue;

      int level = ParseLevelFromComment(PositionGetString(POSITION_COMMENT));
      // Orders at or below the hit TP level should already be closing via TP;
      // still trail any that remain. Prefer trailing levels > step when possible.
      if(level > 0 && level <= step && step < LEVELS)
        {
         // Level N order is the one that takes TP N — leave its TP; if still open, also protect it
        }

      any = true;
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);

      double posTarget;
      if(step == 1)
         posTarget = NetBreakEvenSL(isBuy, open, vol);
      else
         posTarget = NormalizePrice(sharedTarget);

      // Never move SL backward
      if(StopAlreadyAtOrBeyond(isBuy, sl, posTarget))
         continue;

      if(!CanPlaceStop(isBuy, posTarget))
        {
         allOk = false;
         continue;
        }

      if(!g_trade.PositionModify(ticket, posTarget, tp))
        {
         allOk = false;
         if(InpLogActions)
            PrintFormat("PremGoldAdvisor V1.3 trail fail ticket=%s %s ret=%s",
                        IntegerToString((long)ticket), action, g_trade.ResultRetcodeDescription());
         continue;
        }
     }

   if(!any)
      return true;

   if(allOk)
     {
      g_lastAction = action;
      if(InpLogActions)
         Print("PremGoldAdvisor V1.3 ", g_lastAction);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool CanPlaceStop(const bool isBuy, const double sl)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = MinStopDistance();

   if(isBuy)
     {
      if(sl >= bid)
         return false;
      if((bid - sl) < minDist)
         return false;
     }
   else
     {
      if(sl <= ask)
         return false;
      if((sl - ask) < minDist)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool StopAlreadyAtOrBeyond(const bool isBuy, const double sl, const double target)
  {
   if(sl <= 0.0 || target <= 0.0)
      return false;
   if(isBuy)
      return (sl >= target - g_tickSize * 0.5);
   return (sl <= target + g_tickSize * 0.5);
  }

//+------------------------------------------------------------------+
bool ValidateStops(const bool isBuy, const double price, double &sl, double &tp)
  {
   double minDist = MinStopDistance();

   if(isBuy)
     {
      if(sl > 0.0 && price - sl < minDist)
         sl = NormalizePrice(price - minDist);
      if(tp > 0.0 && tp - price < minDist)
         tp = NormalizePrice(price + minDist);
      if(sl > 0.0 && sl >= price)
         return false;
      if(tp <= 0.0 || tp <= price)
         return false;
     }
   else
     {
      if(sl > 0.0 && sl - price < minDist)
         sl = NormalizePrice(price + minDist);
      if(tp > 0.0 && price - tp < minDist)
         tp = NormalizePrice(price - minDist);
      if(sl > 0.0 && sl <= price)
         return false;
      if(tp <= 0.0 || tp >= price)
         return false;
     }
   sl = (sl > 0.0) ? NormalizePrice(sl) : 0.0;
   tp = NormalizePrice(tp);
   return true;
  }

//+------------------------------------------------------------------+
bool ValidateTpLadder()
  {
   double t[6];
   t[1] = InpTp1; t[2] = InpTp2; t[3] = InpTp3; t[4] = InpTp4; t[5] = InpTp5;
   for(int i = 1; i <= LEVELS; i++)
     {
      if(t[i] <= 0.0)
         return false;
      if(i > 1 && t[i] <= t[i - 1])
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
double DistToPrice(const double value)
  {
   if(value < 0.0)
      return 0.0;
   if(InpDistanceMode == DIST_POINTS)
      return value * g_point;
   return value;
  }

//+------------------------------------------------------------------+
string MakeComment(const bool isBuy, const int level)
  {
   string side = isBuy ? "B" : "S";
   string cmt = StringFormat("%s-%s%d|%s", COMMENT_PREFIX, side, level, InpComment);
   if(StringLen(cmt) > 31)
      cmt = StringFormat("%s-%s%d", COMMENT_PREFIX, side, level);
   return cmt;
  }

//+------------------------------------------------------------------+
int ParseLevelFromComment(const string cmt)
  {
   string prefix = COMMENT_PREFIX + "-";
   int pos = StringFind(cmt, prefix);
   if(pos < 0)
      return 0;
   int idx = pos + StringLen(prefix) + 1; // after B/S
   if(idx >= StringLen(cmt))
      return 0;
   int lvl = (int)StringToInteger(StringSubstr(cmt, idx, 1));
   if(lvl < 1 || lvl > LEVELS)
      return 0;
   return lvl;
  }

//+------------------------------------------------------------------+
bool IsOurPosition()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(IsOurPosition())
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
int CountSide(const bool isBuy)
  {
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(isBuy && type == POSITION_TYPE_BUY)
         count++;
      if(!isBuy && type == POSITION_TYPE_SELL)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
double AverageOpenPrice(const bool isBuy)
  {
   double sum = 0.0;
   double vol = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(isBuy && type != POSITION_TYPE_BUY)
         continue;
      if(!isBuy && type != POSITION_TYPE_SELL)
         continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      sum += PositionGetDouble(POSITION_PRICE_OPEN) * v;
      vol += v;
     }
   if(vol <= 0.0)
      return 0.0;
   return NormalizePrice(sum / vol);
  }

//+------------------------------------------------------------------+
void RecoverFromPositions()
  {
   int buys = CountSide(true);
   int sells = CountSide(false);
   if(buys == 0 && sells == 0)
      return;

   if(g_buyEntry <= 0.0 && buys > 0)
      g_buyEntry = AverageOpenPrice(true);
   if(g_sellEntry <= 0.0 && sells > 0)
      g_sellEntry = AverageOpenPrice(false);

   if(g_buyEntry > 0.0 && g_buyTp[1] <= 0.0)
      RebuildTpFromEntry(true, g_buyEntry);
   if(g_sellEntry > 0.0 && g_sellTp[1] <= 0.0)
      RebuildTpFromEntry(false, g_sellEntry);

   InferTrailFromStops(true);
   InferTrailFromStops(false);

   if(g_armedBarTime <= 0)
      g_armedBarTime = iTime(_Symbol, InpWorkTimeframe, 0);

   g_status = StringFormat("RECOVERED B%d/S%d", buys, sells);
  }

//+------------------------------------------------------------------+
void InferTrailFromStops(const bool isBuy)
  {
   double best = 0.0;
   bool found = false;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(isBuy && type != POSITION_TYPE_BUY)
         continue;
      if(!isBuy && type != POSITION_TYPE_SELL)
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
         continue;
      if(!found)
        {
         best = sl;
         found = true;
        }
      else
        {
         if(isBuy)
            best = MathMax(best, sl);
         else
            best = MathMin(best, sl);
        }
     }

   if(!found)
      return;

   int step = 0;
   double entry = isBuy ? g_buyEntry : g_sellEntry;
   double tol = g_tickSize * 2.0;

   if(entry > 0.0)
     {
      if(isBuy && best + tol >= entry)
         step = 1;
      if(!isBuy && best - tol <= entry)
         step = 1;
     }

   for(int lvl = 1; lvl <= LEVELS - 1; lvl++)
     {
      double tp = isBuy ? g_buyTp[lvl] : g_sellTp[lvl];
      if(tp <= 0.0)
         continue;
      if(isBuy && best + tol >= tp)
         step = MathMax(step, lvl + 1);
      if(!isBuy && best - tol <= tp)
         step = MathMax(step, lvl + 1);
     }

   if(isBuy)
     {
      g_buyTrailTo = MathMax(g_buyTrailTo, step);
      g_buyHitLevel = MathMax(g_buyHitLevel, step);
     }
   else
     {
      g_sellTrailTo = MathMax(g_sellTrailTo, step);
      g_sellHitLevel = MathMax(g_sellHitLevel, step);
     }
  }

//+------------------------------------------------------------------+
void CloseAllOurPositions(const string reason)
  {
   g_lastAction = reason;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition())
         continue;
      g_trade.PositionClose(ticket);
     }
   if(InpLogActions)
      Print("PremGoldAdvisor V1.3 ", reason);
  }

//+------------------------------------------------------------------+
void ResetBasketState(const bool isBuy)
  {
   if(isBuy)
     {
      g_buyEntry = 0.0;
      ArrayInitialize(g_buyTp, 0.0);
      g_buySlInit = 0.0;
      g_buyHitLevel = 0;
      g_buyTrailTo = 0;
     }
   else
     {
      g_sellEntry = 0.0;
      ArrayInitialize(g_sellTp, 0.0);
      g_sellSlInit = 0.0;
      g_sellHitLevel = 0;
      g_sellTrailTo = 0;
     }
  }

//+------------------------------------------------------------------+
void ConfigureFilling()
  {
   long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
void SoftSleep(const int ms)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   Sleep(ms);
  }

//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   if(g_tickSize > 0.0)
      price = MathRound(price / g_tickSize) * g_tickSize;
   return NormalizeDouble(price, g_digits);
  }

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0)
      stepLot = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathRound(lot / stepLot) * stepLot;
   int digits = 2;
   if(stepLot < 0.01)
      digits = 3;
   if(stepLot < 0.001)
      digits = 4;
   return NormalizeDouble(lot, digits);
  }

//+------------------------------------------------------------------+
double MinStopDistance()
  {
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double level  = (double)MathMax(g_stopsLevel, freeze);
   return level * g_point + 2.0 * g_point;
  }

//+------------------------------------------------------------------+
bool SpreadTooWide()
  {
   if(InpMaxSpread <= 0.0)
      return false;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return ((ask - bid) > InpMaxSpread);
  }

//+------------------------------------------------------------------+
bool IsTradingHour()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(InpStartHour == InpEndHour)
      return true;
   if(InpStartHour < InpEndHour)
      return (hour >= InpStartHour && hour <= InpEndHour);
   return (hour >= InpStartHour || hour <= InpEndHour);
  }

//+------------------------------------------------------------------+
bool IsFridayCloseTime()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour);
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, InpWorkTimeframe, 0);
   if(t <= 0)
      return false;
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

//+------------------------------------------------------------------+
string GvName(const string key)
  {
   return StringFormat("PGA13_%s_%s_%s", _Symbol, IntegerToString((long)InpMagic), key);
  }

//+------------------------------------------------------------------+
void SaveState()
  {
   GlobalVariableSet(GvName("ArmedBar"), (double)g_armedBarTime);
   GlobalVariableSet(GvName("BuyOpenedBar"), (double)g_buyOpenedBar);
   GlobalVariableSet(GvName("SellOpenedBar"), (double)g_sellOpenedBar);
   GlobalVariableSet(GvName("BarOpen"), g_barOpen);
   GlobalVariableSet(GvName("BuyLevel"), g_buyLevel);
   GlobalVariableSet(GvName("SellLevel"), g_sellLevel);
   GlobalVariableSet(GvName("BuyLeft"), g_buyLeftLevel ? 1.0 : 0.0);
   GlobalVariableSet(GvName("SellLeft"), g_sellLeftLevel ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Armed"), g_levelsArmed ? 1.0 : 0.0);
   GlobalVariableSet(GvName("BuyEntry"), g_buyEntry);
   GlobalVariableSet(GvName("SellEntry"), g_sellEntry);
   GlobalVariableSet(GvName("BuyHit"), (double)g_buyHitLevel);
   GlobalVariableSet(GvName("SellHit"), (double)g_sellHitLevel);
   GlobalVariableSet(GvName("BuyTrail"), (double)g_buyTrailTo);
   GlobalVariableSet(GvName("SellTrail"), (double)g_sellTrailTo);
   GlobalVariableSet(GvName("Paused"), g_paused ? 1.0 : 0.0);
   for(int i = 1; i <= LEVELS; i++)
     {
      GlobalVariableSet(GvName("BuyTp" + IntegerToString(i)), g_buyTp[i]);
      GlobalVariableSet(GvName("SellTp" + IntegerToString(i)), g_sellTp[i]);
     }
  }

//+------------------------------------------------------------------+
void LoadState()
  {
   if(GlobalVariableCheck(GvName("ArmedBar")))
      g_armedBarTime = (datetime)GlobalVariableGet(GvName("ArmedBar"));
   if(GlobalVariableCheck(GvName("BuyOpenedBar")))
      g_buyOpenedBar = (datetime)GlobalVariableGet(GvName("BuyOpenedBar"));
   if(GlobalVariableCheck(GvName("SellOpenedBar")))
      g_sellOpenedBar = (datetime)GlobalVariableGet(GvName("SellOpenedBar"));
   if(GlobalVariableCheck(GvName("BarOpen")))
      g_barOpen = GlobalVariableGet(GvName("BarOpen"));
   if(GlobalVariableCheck(GvName("BuyLevel")))
      g_buyLevel = GlobalVariableGet(GvName("BuyLevel"));
   if(GlobalVariableCheck(GvName("SellLevel")))
      g_sellLevel = GlobalVariableGet(GvName("SellLevel"));
   if(GlobalVariableCheck(GvName("BuyLeft")))
      g_buyLeftLevel = (GlobalVariableGet(GvName("BuyLeft")) > 0.5);
   if(GlobalVariableCheck(GvName("SellLeft")))
      g_sellLeftLevel = (GlobalVariableGet(GvName("SellLeft")) > 0.5);
   if(GlobalVariableCheck(GvName("Armed")))
      g_levelsArmed = (GlobalVariableGet(GvName("Armed")) > 0.5);
   if(GlobalVariableCheck(GvName("BuyEntry")))
      g_buyEntry = GlobalVariableGet(GvName("BuyEntry"));
   if(GlobalVariableCheck(GvName("SellEntry")))
      g_sellEntry = GlobalVariableGet(GvName("SellEntry"));
   if(GlobalVariableCheck(GvName("BuyHit")))
      g_buyHitLevel = (int)GlobalVariableGet(GvName("BuyHit"));
   if(GlobalVariableCheck(GvName("SellHit")))
      g_sellHitLevel = (int)GlobalVariableGet(GvName("SellHit"));
   if(GlobalVariableCheck(GvName("BuyTrail")))
      g_buyTrailTo = (int)GlobalVariableGet(GvName("BuyTrail"));
   if(GlobalVariableCheck(GvName("SellTrail")))
      g_sellTrailTo = (int)GlobalVariableGet(GvName("SellTrail"));
   if(GlobalVariableCheck(GvName("Paused")))
      g_paused = (GlobalVariableGet(GvName("Paused")) > 0.5);
   for(int i = 1; i <= LEVELS; i++)
     {
      string bk = GvName("BuyTp" + IntegerToString(i));
      string sk = GvName("SellTp" + IntegerToString(i));
      if(GlobalVariableCheck(bk))
         g_buyTp[i] = GlobalVariableGet(bk);
      if(GlobalVariableCheck(sk))
         g_sellTp[i] = GlobalVariableGet(sk);
     }
  }

//+------------------------------------------------------------------+
void ApplyChartTheme()
  {
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, CLR_BG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, CLR_TEXT);
   ChartSetInteger(0, CHART_COLOR_GRID, CLR_LINE);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, CLR_GREEN);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, CLR_RED);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, CLR_GREEN);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, CLR_RED);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
  }

//+------------------------------------------------------------------+
void BuildPanel()
  {
   ObjectsDeleteAll(0, g_panelPrefix);
   int x = InpPanelX;
   int y = InpPanelY;
   int w = 300;
   int h = 270;

   CreateRect(g_panelPrefix + "BG", x, y, w, h, CLR_CARD);
   CreateLabel(g_panelPrefix + "TITLE", x + 12, y + 10, "PremGoldAdvisor V1.3", CLR_GOLD2, 11);
   CreateLabel(g_panelPrefix + "SUB", x + 12, y + 30, "M5 levels → touch to open", CLR_MUTED, 8);

   CreateLabel(g_panelPrefix + "L_STATUS", x + 12, y + 54, "Status:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_STATUS", x + 78, y + 54, "-", CLR_TEXT, 8);

   CreateLabel(g_panelPrefix + "L_LVL", x + 12, y + 74, "Levels:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_LVL", x + 78, y + 74, "-", CLR_TEXT, 8);

   CreateLabel(g_panelPrefix + "L_POS", x + 12, y + 94, "Open:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_POS", x + 78, y + 94, "-", CLR_TEXT, 8);

   CreateLabel(g_panelPrefix + "L_HIT", x + 12, y + 114, "TP hit:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_HIT", x + 78, y + 114, "-", CLR_TEXT, 8);

   CreateLabel(g_panelPrefix + "L_TRAIL", x + 12, y + 134, "Trail:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_TRAIL", x + 78, y + 134, "-", CLR_TEXT, 8);

   CreateLabel(g_panelPrefix + "L_ACT", x + 12, y + 154, "Action:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_ACT", x + 78, y + 154, "-", CLR_GOLD, 8);

   CreateLabel(g_panelPrefix + "L_BLOCK", x + 12, y + 174, "Block:", CLR_MUTED, 8);
   CreateLabel(g_panelPrefix + "V_BLOCK", x + 78, y + 174, "-", CLR_RED, 8);

   CreateButton(g_panelPrefix + "BTN_PAUSE", x + 12, y + 210, 130, 28, "PAUSE", CLR_BTN, CLR_GOLD);
   CreateButton(g_panelPrefix + "BTN_CLOSE", x + 154, y + 210, 130, 28, "CLOSE ALL", CLR_BTN2, CLR_TEXT);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
      return;
   if(ObjectFind(0, g_panelPrefix + "BG") < 0)
      BuildPanel();

   ObjectSetString(0, g_panelPrefix + "V_STATUS", OBJPROP_TEXT, g_status);
   ObjectSetString(0, g_panelPrefix + "V_LVL", OBJPROP_TEXT,
                   StringFormat("B %s | S %s",
                                (g_buyLevel > 0.0 ? DoubleToString(g_buyLevel, g_digits) : "-"),
                                (g_sellLevel > 0.0 ? DoubleToString(g_sellLevel, g_digits) : "-")));
   ObjectSetString(0, g_panelPrefix + "V_POS", OBJPROP_TEXT,
                   StringFormat("B %d / S %d", CountSide(true), CountSide(false)));
   ObjectSetString(0, g_panelPrefix + "V_HIT", OBJPROP_TEXT,
                   StringFormat("Buy TP%d | Sell TP%d", g_buyHitLevel, g_sellHitLevel));
   ObjectSetString(0, g_panelPrefix + "V_TRAIL", OBJPROP_TEXT,
                   StringFormat("Buy step %d | Sell step %d", g_buyTrailTo, g_sellTrailTo));
   ObjectSetString(0, g_panelPrefix + "V_ACT", OBJPROP_TEXT, TrimPanelText(g_lastAction, 38));
   ObjectSetString(0, g_panelPrefix + "V_BLOCK", OBJPROP_TEXT,
                   (g_blockReason == "" ? "-" : TrimPanelText(g_blockReason, 38)));
   ObjectSetString(0, g_panelPrefix + "BTN_PAUSE", OBJPROP_TEXT, g_paused ? "RESUME" : "PAUSE");
  }

//+------------------------------------------------------------------+
string TrimPanelText(const string text, const int maxLen)
  {
   if(StringLen(text) <= maxLen)
      return text;
   return StringSubstr(text, 0, maxLen - 2) + "..";
  }

//+------------------------------------------------------------------+
void CreateRect(const string name, const int x, const int y, const int w, const int h, const color clr)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, CLR_LINE);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void CreateLabel(const string name, const int x, const int y, const string text,
                 const color clr, const int fontSize)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void CreateButton(const string name, const int x, const int y, const int w, const int h,
                  const string text, const color bg, const color fg)
  {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_LINE);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
  }

//+------------------------------------------------------------------+
void DrawLevels()
  {
   ObjectsDeleteAll(0, "PGA13_LVL_");

   if(g_buyLevel > 0.0)
      DrawHLine("PGA13_LVL_BUY", g_buyLevel, CLR_GREEN, "Buy entry level");
   if(g_sellLevel > 0.0)
      DrawHLine("PGA13_LVL_SELL", g_sellLevel, CLR_RED, "Sell entry level");
   if(g_barOpen > 0.0)
      DrawHLine("PGA13_LVL_OPEN", g_barOpen, CLR_GOLD, "M5 open");

   for(int i = 1; i <= LEVELS; i++)
     {
      if(g_buyTp[i] > 0.0 && CountSide(true) > 0)
         DrawHLine("PGA13_LVL_BTP" + IntegerToString(i), g_buyTp[i], CLR_GREEN,
                   StringFormat("B TP%d", i));
      if(g_sellTp[i] > 0.0 && CountSide(false) > 0)
         DrawHLine("PGA13_LVL_STP" + IntegerToString(i), g_sellTp[i], CLR_RED,
                   StringFormat("S TP%d", i));
     }
  }

//+------------------------------------------------------------------+
void DrawHLine(const string name, const double price, const color clr, const string tip)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
  }

//+------------------------------------------------------------------+
