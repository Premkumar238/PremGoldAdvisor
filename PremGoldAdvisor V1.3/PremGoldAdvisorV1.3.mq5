//+------------------------------------------------------------------+
//|                                       PremGoldAdvisorV1.3.mq5    |
//|                         PremGoldAdvisor V1.3                     |
//|  XAUUSD M5 breakout: arm levels → 1 order, then scale on each TP |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor V1.3"
#property link      ""
#property version   "3.40"
#property description "PremGoldAdvisorV1.3 — On each M5 candle arms Buy/Sell levels, then opens 1 order on touch. After TP1 locks SL at TP1 and opens order 2; after TP2 locks SL at TP2 and opens order 3; same through TP5. Does not guarantee profit — initial SL can still be hit before TP1."

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

#define LEVELS         5
#define COMMENT_PREFIX "PGA13"

enum ENUM_DIST_MODE
  {
   DIST_PRICE  = 0,   // Price distance (e.g. 0.50 on gold)
   DIST_POINTS = 1    // Symbol points (_Point)
  };

input group "=== Core ==="
input bool              InpTradeEnabled          = true;        // Enable auto trading
input bool              InpEnableBuy             = true;        // Enable Buy baskets
input bool              InpEnableSell            = true;        // Enable Sell baskets
input double            InpLotSize               = 0.01;        // Lot size per order
input ulong             InpMagic                 = 130213;      // Magic number
input int               InpDeviationPoints       = 50;          // Max slippage / deviation (points)
input int               InpMaxRetries            = 3;           // Order send retries
input string            InpComment               = "PGA-V1.3";  // Order comment tag
input ENUM_TIMEFRAMES   InpWorkTimeframe         = PERIOD_M5;   // Working timeframe (M5)

input group "=== Entry Levels (from M5 open) ==="
input ENUM_DIST_MODE    InpDistanceMode          = DIST_PRICE;  // Distance mode (entry / TP / SL)
input double            InpBuyEntryDistance      = 2.00;        // Buy level = Open + distance
input double            InpSellEntryDistance     = 2.00;        // Sell level = Open - distance
input bool              InpRequireLeaveFirst     = false;       // If already near level, wait leave then retest
input bool              InpAllowBothDirections   = true;        // Allow both Buy+Sell on same candle

input group "=== Take Profit Ladder ==="
input double            InpTp1                   = 0.50;        // TP1 distance from fill
input double            InpTp2                   = 1.00;        // TP2 distance from fill
input double            InpTp3                   = 1.50;        // TP3 distance from fill
input double            InpTp4                   = 2.00;        // TP4 distance from fill
input double            InpTp5                   = 2.50;        // TP5 distance from fill

input group "=== Stop Loss / Trail ==="
input double            InpInitialSl             = 5.00;        // Initial SL on first order (0 = NONE — unlimited risk)
input bool              InpTrailEnabled          = true;        // After TPn lock remaining SL at TPn
input bool              InpScaleInOnTp           = true;        // Open next order only after previous TP is touched
input double            InpBreakEvenBuffer       = 0.10;        // Extra price buffer if interim BE is used
input bool              InpBeCompensateSpread    = true;        // Cover spread if interim BE is applied
input double            InpCommissionPerLot      = 0.0;         // Round-turn commission per 1.0 lot (account ccy)
input int               InpBreakevenExtraPoints  = 0;           // Extra points beyond net BE + buffer

input group "=== Basket / Risk Control ==="
input bool              InpAllowStackCycles      = false;       // Allow new basket while same side still open
input int               InpMaxActiveBaskets      = 2;           // Max concurrent baskets (0=off)
input int               InpMaxOpenPositions      = 50;          // Hard cap on EA open positions (0=off)

input group "=== Filters / Session ==="
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
input bool              InpLogActions            = true;        // Print trail / open actions to Experts log

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
double   g_buyLevel  = 0.0;       // planned touch entry (Buy = Open + dist)
double   g_sellLevel = 0.0;       // planned touch entry (Sell = Open - dist)

bool     g_buyLeftLevel  = false; // price left buy level (for retest)
bool     g_sellLeftLevel = false;
bool     g_levelsArmed   = false;

ulong    g_buyBasketId  = 0;      // unique basket id (Buy)
ulong    g_sellBasketId = 0;      // unique basket id (Sell)
ulong    g_nextBasketId = 1;

double   g_buyEntry  = 0.0;       // actual/reference fill for buy basket
double   g_sellEntry = 0.0;
double   g_buyTp[LEVELS + 1];
double   g_sellTp[LEVELS + 1];
double   g_buySlInit  = 0.0;
double   g_sellSlInit = 0.0;
double   g_buyTrailSl  = 0.0;     // current trailing SL reference (Buy)
double   g_sellTrailSl = 0.0;     // current trailing SL reference (Sell)

int      g_buyHitLevel  = 0;
int      g_sellHitLevel = 0;
int      g_buyTrailTo   = 0;      // 0=none, 1=SL@TP1, 2=SL@TP2, ...
int      g_sellTrailTo  = 0;
int      g_buyOpenedLevel  = 0;   // last order opened on buy ladder (0=none, 1..5)
int      g_sellOpenedLevel = 0;

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
      Print("PremGoldAdvisorV1.3 WARNING: working TF is not M5 (",
            EnumToString(InpWorkTimeframe), ")");

   if(InpInitialSl <= 0.0)
      Print("PremGoldAdvisorV1.3 WARNING: InitialSL = 0 — initial stop loss is DISABLED. Potential loss is UNLIMITED until a trail level is applied. Use only for testing with strict risk controls.");

   if(!InpEnableBuy && !InpEnableSell)
      Print("PremGoldAdvisorV1.3 WARNING: both Buy and Sell are disabled — EA will not open new baskets.");

   // Arm current candle levels on attach (wait for touch — do not open immediately)
   if(InpTradeEnabled && !g_paused)
      ArmCandleLevels(false);

   g_status = g_paused ? "PAUSED" : (g_levelsArmed ? "WAITING TOUCH" : "READY");
   PrintFormat("PremGoldAdvisorV1.3 init on %s  magic=%s  lot=%.2f  TF=%s  bothDirs=%s",
               _Symbol, IntegerToString((long)InpMagic), InpLotSize,
               EnumToString(InpWorkTimeframe),
               (InpAllowBothDirections ? "yes" : "no"));
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
   ResetSideIfFlat(true);
   ResetSideIfFlat(false);

   bool newBar = IsNewBar();
   if(newBar)
      ArmCandleLevels(true);

   if(!g_paused && InpTradeEnabled && g_levelsArmed)
      TryTriggerSides();

   if(!g_paused && InpTradeEnabled && InpScaleInOnTp)
     {
      TryScaleInSide(true);
      TryScaleInSide(false);
     }

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

   // New candle: reset per-candle trigger flags (do not wipe open basket management)
   if(fromNewBar && g_armedBarTime != barTime)
     {
      // Buy/Sell may each trigger once on THIS candle only
      // Opened-bar stamps for prior candles stay as history; compare vs barTime below
     }

   g_armedBarTime = barTime;
   g_barOpen      = NormalizePrice(barOpen);

   // Breakout levels: Buy ABOVE open, Sell BELOW open
   double buyDist  = DistToPrice(InpBuyEntryDistance);
   double sellDist = DistToPrice(InpSellEntryDistance);

   g_buyLevel  = NormalizePrice(g_barOpen + buyDist);
   g_sellLevel = NormalizePrice(g_barOpen - sellDist);

   // Per-candle leave/retest flags for sides not yet triggered on this bar
   if(g_buyOpenedBar != barTime)
     {
      if(InpRequireLeaveFirst && LevelIsNearMarket(true, g_buyLevel))
         g_buyLeftLevel = false;
      else
         g_buyLeftLevel = true;
     }
   else
      g_buyLeftLevel = true; // already used this candle

   if(g_sellOpenedBar != barTime)
     {
      if(InpRequireLeaveFirst && LevelIsNearMarket(false, g_sellLevel))
         g_sellLeftLevel = false;
      else
         g_sellLeftLevel = true;
     }
   else
      g_sellLeftLevel = true;

   g_levelsArmed = true;
   g_blockReason = "";
   g_status = "WAITING TOUCH";
   g_lastAction = StringFormat("Armed M5 %s open=%s | Buy@%s | Sell@%s",
                               TimeToString(barTime, TIME_DATE|TIME_MINUTES),
                               DoubleToString(g_barOpen, g_digits),
                               DoubleToString(g_buyLevel, g_digits),
                               DoubleToString(g_sellLevel, g_digits));
   if(InpLogActions && fromNewBar)
      Print("PremGoldAdvisorV1.3 ", g_lastAction);
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
      // Buy breakout level is ABOVE market; near if ask already at/through it
      return (ask >= level - pad);
     }
   // Sell breakout level is BELOW market; near if bid already at/through it
   return (bid <= level + pad);
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
   if(InpEnableBuy && g_buyOpenedBar != barTime && CanOpenSide(true))
     {
      if(IsLevelTouched(true, g_buyLevel))
         OpenSideBasket(true);
     }

   // --- Sell side ---
   if(InpEnableSell && g_sellOpenedBar != barTime && CanOpenSide(false))
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
      // Left buy breakout level = market dropped back below it
      if(ask < g_buyLevel - pad)
         g_buyLeftLevel = true;
     }
   if(!g_sellLeftLevel && g_sellLevel > 0.0)
     {
      // Left sell breakout level = market rose back above it
      if(bid > g_sellLevel + pad)
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
      // Buy breakout: Ask (or candle high) reaches/crosses Buy Entry Level
      return (ask >= level || high >= level);
     }

   // Sell breakout: Bid (or candle low) reaches/crosses Sell Entry Level
   return (bid <= level || low <= level);
  }

//+------------------------------------------------------------------+
bool CanOpenSide(const bool isBuy)
  {
   datetime barTime = g_armedBarTime;
   if(barTime <= 0)
      barTime = iTime(_Symbol, InpWorkTimeframe, 0);

   // One trigger per direction per candle already enforced by opened-bar stamps.
   // If both directions are disabled for this candle after first side triggers:
   if(!InpAllowBothDirections)
     {
      if(isBuy && g_sellOpenedBar == barTime)
        {
         g_blockReason = "Sell already triggered (AllowBothDirections=false)";
         return false;
        }
      if(!isBuy && g_buyOpenedBar == barTime)
        {
         g_blockReason = "Buy already triggered (AllowBothDirections=false)";
         return false;
        }
     }

   if(!InpAllowStackCycles && CountSide(isBuy) > 0)
     {
      g_blockReason = isBuy ? "Buy basket still open" : "Sell basket still open";
      return false;
     }

   int activeBaskets = CountActiveBaskets();
   if(InpMaxActiveBaskets > 0 && activeBaskets >= InpMaxActiveBaskets)
     {
      // Opening a new side only blocked if that side is currently flat
      if(CountSide(isBuy) == 0)
        {
         g_blockReason = "Max active baskets reached";
         return false;
        }
     }

   int openCount = CountOurPositions();
   if(InpMaxOpenPositions > 0 && openCount + 1 > InpMaxOpenPositions)
     {
      g_blockReason = "Max open positions cap";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
int CountActiveBaskets()
  {
   int n = 0;
   if(CountSide(true) > 0)
      n++;
   if(CountSide(false) > 0)
      n++;
   return n;
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
      g_buyBasketId = AllocateBasketId(barTime, true);
      g_buyEntry = ask;
      g_buyTp[1] = NormalizePrice(ask + d1);
      g_buyTp[2] = NormalizePrice(ask + d2);
      g_buyTp[3] = NormalizePrice(ask + d3);
      g_buyTp[4] = NormalizePrice(ask + d4);
      g_buyTp[5] = NormalizePrice(ask + d5);
      // Protective initial SL only — NOT break-even
      g_buySlInit = (dSl > 0.0) ? NormalizePrice(ask - dSl) : 0.0;
      g_buyTrailSl = g_buySlInit;
      g_buyHitLevel = 0;
      g_buyTrailTo  = 0;
      g_buyOpenedLevel = 0;

      double sl = g_buySlInit;
      double tp = g_buyTp[LEVELS];   // run to TP5; TPs 1-4 are lock + scale-in levels
      if(!ValidateStops(true, ask, sl, tp))
        {
         g_blockReason = "Buy1 stops invalid vs broker min distance";
         if(InpLogActions)
            Print("PremGoldAdvisorV1.3 ", g_blockReason);
        }
      else if(OpenMarket(true, lot, sl, tp, 1, g_buyBasketId))
         opened = 1;

      if(opened > 0)
        {
         g_buyOpenedBar = barTime;
         g_buyOpenedLevel = 1;
         double avg = AverageOpenPrice(true);
         if(avg > 0.0)
           {
            g_buyEntry = avg;
            RebuildTpFromEntry(true, g_buyEntry);
            if(dSl > 0.0)
              {
               g_buySlInit = NormalizePrice(g_buyEntry - dSl);
               g_buyTrailSl = g_buySlInit;
              }
           }
        }
     }
   else
     {
      g_sellBasketId = AllocateBasketId(barTime, false);
      g_sellEntry = bid;
      g_sellTp[1] = NormalizePrice(bid - d1);
      g_sellTp[2] = NormalizePrice(bid - d2);
      g_sellTp[3] = NormalizePrice(bid - d3);
      g_sellTp[4] = NormalizePrice(bid - d4);
      g_sellTp[5] = NormalizePrice(bid - d5);
      g_sellSlInit = (dSl > 0.0) ? NormalizePrice(bid + dSl) : 0.0;
      g_sellTrailSl = g_sellSlInit;
      g_sellHitLevel = 0;
      g_sellTrailTo  = 0;
      g_sellOpenedLevel = 0;

      double sl = g_sellSlInit;
      double tp = g_sellTp[LEVELS];
      if(!ValidateStops(false, bid, sl, tp))
        {
         g_blockReason = "Sell1 stops invalid vs broker min distance";
         if(InpLogActions)
            Print("PremGoldAdvisorV1.3 ", g_blockReason);
        }
      else if(OpenMarket(false, lot, sl, tp, 1, g_sellBasketId))
         opened = 1;

      if(opened > 0)
        {
         g_sellOpenedBar = barTime;
         g_sellOpenedLevel = 1;
         double avg = AverageOpenPrice(false);
         if(avg > 0.0)
           {
            g_sellEntry = avg;
            RebuildTpFromEntry(false, g_sellEntry);
            if(dSl > 0.0)
              {
               g_sellSlInit = NormalizePrice(g_sellEntry + dSl);
               g_sellTrailSl = g_sellSlInit;
              }
           }
        }
     }

   if(opened <= 0)
      return;

   g_lastAction = StringFormat("%s touch @ %s → opened 1/5 basket#%s (scale-in)",
                               (isBuy ? "BUY" : "SELL"),
                               DoubleToString(isBuy ? g_buyLevel : g_sellLevel, g_digits),
                               IntegerToString((long)(isBuy ? g_buyBasketId : g_sellBasketId)));
   g_status = StringFormat("LIVE B%d/S%d", CountSide(true), CountSide(false));
   if(InpLogActions)
      Print("PremGoldAdvisorV1.3 ", g_lastAction);
   SaveState();
  }

//+------------------------------------------------------------------+
ulong AllocateBasketId(const datetime barTime, const bool isBuy)
  {
   // Unique-ish id: packs candle time + direction + sequence
   ulong id = ((ulong)barTime % 1000000000) * 10 + (isBuy ? 1 : 2);
   id = id * 1000 + (g_nextBasketId % 1000);
   g_nextBasketId++;
   if(g_nextBasketId > 999000)
      g_nextBasketId = 1;
   return id;
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
bool OpenMarket(const bool isBuy, const double lot, double sl, double tp,
                const int level, const ulong basketId)
  {
   string cmt = MakeComment(isBuy, level, basketId);
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
      LogTradeError(isBuy ? "BUY" : "SELL", level, ret, g_trade.ResultRetcodeDescription());

      if(ret == TRADE_RETCODE_REQUOTE || ret == TRADE_RETCODE_PRICE_OFF ||
         ret == TRADE_RETCODE_PRICE_CHANGED || ret == TRADE_RETCODE_TIMEOUT ||
         ret == TRADE_RETCODE_TOO_MANY_REQUESTS)
        {
         SoftSleep(50 * attempt);
         ConfigureFilling();
         continue;
        }
      // Invalid stops / volume / margin / market closed — do not spam retries
      if(ret == TRADE_RETCODE_INVALID_STOPS || ret == TRADE_RETCODE_INVALID_VOLUME ||
         ret == TRADE_RETCODE_NO_MONEY || ret == TRADE_RETCODE_MARKET_CLOSED ||
         ret == TRADE_RETCODE_TRADE_DISABLED)
         break;
      break;
     }

   if(!ok && InpLogActions)
      PrintFormat("PremGoldAdvisorV1.3 open %s L%d failed: %s",
                  (isBuy ? "BUY" : "SELL"), level, g_trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
void LogTradeError(const string side, const int level, const uint ret, const string desc)
  {
   string hint = "";
   switch(ret)
     {
      case TRADE_RETCODE_INVALID_STOPS:   hint = " (invalid stops / min distance)"; break;
      case TRADE_RETCODE_INVALID_VOLUME:  hint = " (invalid volume)"; break;
      case TRADE_RETCODE_NO_MONEY:        hint = " (insufficient margin)"; break;
      case TRADE_RETCODE_MARKET_CLOSED:   hint = " (market closed)"; break;
      case TRADE_RETCODE_REQUOTE:         hint = " (requote)"; break;
      case TRADE_RETCODE_REJECT:          hint = " (rejected)"; break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS: hint = " (flood control)"; break;
      default: break;
     }
   if(InpLogActions)
      PrintFormat("PremGoldAdvisorV1.3 %s L%d ret=%u %s%s", side, level, ret, desc, hint);
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
void ResetSideIfFlat(const bool isBuy)
  {
   if(CountSide(isBuy) > 0)
      return;

   int opened = isBuy ? g_buyOpenedLevel : g_sellOpenedLevel;
   double entry = isBuy ? g_buyEntry : g_sellEntry;
   if(opened <= 0 && entry <= 0.0)
      return;

   ResetBasketState(isBuy);
   SaveState();
  }

//+------------------------------------------------------------------+
void TryScaleInSide(const bool isBuy)
  {
   if(isBuy && !InpEnableBuy)
      return;
   if(!isBuy && !InpEnableSell)
      return;
   if(CountSide(isBuy) == 0)
      return;

   int opened = isBuy ? g_buyOpenedLevel : g_sellOpenedLevel;
   int hit    = isBuy ? g_buyHitLevel    : g_sellHitLevel;
   int trail  = isBuy ? g_buyTrailTo     : g_sellTrailTo;
   if(opened <= 0 || opened >= LEVELS)
      return;
   if(hit >= LEVELS || trail >= LEVELS)
      return; // move already complete — do not add at the top
   // Only add the next ticket after the last opened order's TP is locked (no catch-up pile-up)
   if(hit < opened || trail != opened)
      return;

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
   if(InpMaxOpenPositions > 0 && CountOurPositions() + 1 > InpMaxOpenPositions)
     {
      g_blockReason = "Max open positions cap";
      return;
     }

   double lot = NormalizeLot(InpLotSize);
   if(lot <= 0.0)
      return;

   ulong basketId = isBuy ? g_buyBasketId : g_sellBasketId;
   if(basketId == 0)
      basketId = AllocateBasketId(g_armedBarTime, isBuy);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   if(isBuy)
     {
      if(g_buyTp[LEVELS] > 0.0 && (bid >= g_buyTp[LEVELS] || ask >= g_buyTp[LEVELS]))
         return;
     }
   else
     {
      if(g_sellTp[LEVELS] > 0.0 && (ask <= g_sellTp[LEVELS] || bid <= g_sellTp[LEVELS]))
         return;
     }

   int next = opened + 1;
   // New order SL = last locked TP so the add is scratch if price returns
   double sl = isBuy ? g_buyTp[trail] : g_sellTp[trail];
   double tp = isBuy ? g_buyTp[LEVELS] : g_sellTp[LEVELS];
   double price = isBuy ? ask : bid;
   if(sl <= 0.0 || tp <= 0.0)
      return;

   // Do not chase: only add while price is still near the lock (within one TP step)
   double maxAway = DistToPrice(InpTp1) + MinStopDistance();
   if(isBuy && (price - sl) > maxAway)
      return;
   if(!isBuy && (sl - price) > maxAway)
      return;

   if(!ValidateStops(isBuy, price, sl, tp))
     {
      g_blockReason = StringFormat("%s%d scale-in stops invalid", isBuy ? "Buy" : "Sell", next);
      return;
     }

   if(!OpenMarket(isBuy, lot, sl, tp, next, basketId))
      return;

   if(isBuy)
     {
      g_buyOpenedLevel = next;
      if(g_buyBasketId == 0)
         g_buyBasketId = basketId;
     }
   else
     {
      g_sellOpenedLevel = next;
      if(g_sellBasketId == 0)
         g_sellBasketId = basketId;
     }

   g_lastAction = StringFormat("%s TP%d locked → opened order %d/5 @ %s SL@TP%d",
                               isBuy ? "BUY" : "SELL",
                               trail, next,
                               DoubleToString(price, g_digits),
                               trail);
   g_status = StringFormat("LIVE B%d/S%d", CountSide(true), CountSide(false));
   if(InpLogActions)
      Print("PremGoldAdvisorV1.3 ", g_lastAction);
   SaveState();
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

   int desiredStep = hit;   // 1=SL@TP1, 2=SL@TP2, ...
   int applied = isBuy ? g_buyTrailTo : g_sellTrailTo;
   if(desiredStep <= applied)
      return;

   for(int step = applied + 1; step <= desiredStep; step++)
     {
      string action;
      if(step >= LEVELS)
         action = StringFormat("%s TP%d — ladder complete", isBuy ? "BUY" : "SELL", step);
      else
         action = StringFormat("%s TP%d — remaining SL -> TP%d, then scale-in order %d",
                               isBuy ? "BUY" : "SELL", step, step, step + 1);

      // Final TP: remaining tickets close on broker TP — just mark trail done
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
   if(step <= 0 || step >= LEVELS)
      return 0.0;
   return isBuy ? g_buyTp[step] : g_sellTp[step];
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
   double buffer = DistToPrice(InpBreakEvenBuffer);

   if(isBuy)
     {
      sl += commPrice;
      sl += buffer;
      sl += InpBreakevenExtraPoints * g_point;
     }
   else
     {
      sl -= commPrice;
      sl -= buffer;
      sl -= InpBreakevenExtraPoints * g_point;
     }

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
   double appliedTarget = 0.0;
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
      // Level N is intended to close at TP N; still protect any that remain open.
      if(level > 0 && level <= step && step < LEVELS)
        {
         // keep protecting leftover lower-level tickets if broker has not closed them yet
        }

      any = true;
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);

      double posTarget = NormalizePrice(sharedTarget);

      // Never move SL backward (only increase protection)
      if(StopAlreadyAtOrBeyond(isBuy, sl, posTarget))
        {
         appliedTarget = posTarget;
         continue;
        }

      if(!CanPlaceStop(isBuy, posTarget))
        {
         // Price is still too close to TPn for the broker min-stop.
         // Lock at net BE first so order 1 cannot fall back to the initial SL.
         double be = NetBreakEvenSL(isBuy, open, vol);
         if(be > 0.0 && !StopAlreadyAtOrBeyond(isBuy, sl, be) && CanPlaceStop(isBuy, be))
            g_trade.PositionModify(ticket, be, tp);
         allOk = false;
         continue;
        }

      if(!g_trade.PositionModify(ticket, posTarget, tp))
        {
         allOk = false;
         if(InpLogActions)
            PrintFormat("PremGoldAdvisorV1.3 trail fail ticket=%s %s ret=%s",
                        IntegerToString((long)ticket), action, g_trade.ResultRetcodeDescription());
         continue;
        }
      appliedTarget = posTarget;
     }

   if(!any)
      return true;

   if(allOk)
     {
      g_lastAction = action;
      if(appliedTarget > 0.0)
        {
         if(isBuy)
            g_buyTrailSl = appliedTarget;
         else
            g_sellTrailSl = appliedTarget;
        }
      if(InpLogActions)
         Print("PremGoldAdvisorV1.3 ", g_lastAction);
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
string MakeComment(const bool isBuy, const int level, const ulong basketId)
  {
   // Keep within MT5 31-char comment limit: PGA13-B3#123456
   string side = isBuy ? "B" : "S";
   string idShort = IntegerToString((long)(basketId % 1000000));
   string cmt = StringFormat("%s-%s%d#%s", COMMENT_PREFIX, side, level, idShort);
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
int HighestLevelOnSide(const bool isBuy)
  {
   int best = 0;
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
      int lvl = ParseLevelFromComment(PositionGetString(POSITION_COMMENT));
      if(lvl > best)
         best = lvl;
     }
   return best;
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

   datetime barTime = iTime(_Symbol, InpWorkTimeframe, 0);

   if(g_buyEntry <= 0.0 && buys > 0)
      g_buyEntry = AverageOpenPrice(true);
   if(g_sellEntry <= 0.0 && sells > 0)
      g_sellEntry = AverageOpenPrice(false);

   if(g_buyEntry > 0.0 && g_buyTp[1] <= 0.0)
      RebuildTpFromEntry(true, g_buyEntry);
   if(g_sellEntry > 0.0 && g_sellTp[1] <= 0.0)
      RebuildTpFromEntry(false, g_sellEntry);

   // Reconstruct initial SL reference if missing
   double dSl = DistToPrice(InpInitialSl);
   if(buys > 0 && g_buySlInit <= 0.0 && g_buyEntry > 0.0 && dSl > 0.0)
      g_buySlInit = NormalizePrice(g_buyEntry - dSl);
   if(sells > 0 && g_sellSlInit <= 0.0 && g_sellEntry > 0.0 && dSl > 0.0)
      g_sellSlInit = NormalizePrice(g_sellEntry + dSl);

   InferTrailFromStops(true);
   InferTrailFromStops(false);

   if(g_armedBarTime <= 0)
      g_armedBarTime = barTime;

   if(buys > 0)
     {
      int fromCmt = HighestLevelOnSide(true);
      g_buyOpenedLevel = MathMax(g_buyOpenedLevel, MathMax(fromCmt, buys));
      if(g_buyOpenedBar <= 0)
         g_buyOpenedBar = barTime;
     }
   if(sells > 0)
     {
      int fromCmt = HighestLevelOnSide(false);
      g_sellOpenedLevel = MathMax(g_sellOpenedLevel, MathMax(fromCmt, sells));
      if(g_sellOpenedBar <= 0)
         g_sellOpenedBar = barTime;
     }

   g_status = StringFormat("RECOVERED B%d/S%d", buys, sells);
   if(InpLogActions)
      PrintFormat("PremGoldAdvisorV1.3 recovered baskets Buy=%d Sell=%d entryB=%s entryS=%s",
                  buys, sells,
                  DoubleToString(g_buyEntry, g_digits),
                  DoubleToString(g_sellEntry, g_digits));
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
   double tol = g_tickSize * 2.0;

   for(int lvl = 1; lvl <= LEVELS; lvl++)
     {
      double tp = isBuy ? g_buyTp[lvl] : g_sellTp[lvl];
      if(tp <= 0.0)
         continue;
      if(isBuy && best + tol >= tp)
         step = MathMax(step, lvl);
      if(!isBuy && best - tol <= tp)
         step = MathMax(step, lvl);
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
      Print("PremGoldAdvisorV1.3 ", reason);
  }

//+------------------------------------------------------------------+
void ResetBasketState(const bool isBuy)
  {
   if(isBuy)
     {
      g_buyEntry = 0.0;
      ArrayInitialize(g_buyTp, 0.0);
      g_buySlInit = 0.0;
      g_buyTrailSl = 0.0;
      g_buyHitLevel = 0;
      g_buyTrailTo = 0;
      g_buyOpenedLevel = 0;
      g_buyBasketId = 0;
     }
   else
     {
      g_sellEntry = 0.0;
      ArrayInitialize(g_sellTp, 0.0);
      g_sellSlInit = 0.0;
      g_sellTrailSl = 0.0;
      g_sellHitLevel = 0;
      g_sellTrailTo = 0;
      g_sellOpenedLevel = 0;
      g_sellBasketId = 0;
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
   GlobalVariableSet(GvName("BuyOpenedLvl"), (double)g_buyOpenedLevel);
   GlobalVariableSet(GvName("SellOpenedLvl"), (double)g_sellOpenedLevel);
   GlobalVariableSet(GvName("BuyTrailSl"), g_buyTrailSl);
   GlobalVariableSet(GvName("SellTrailSl"), g_sellTrailSl);
   GlobalVariableSet(GvName("BuyBasketId"), (double)g_buyBasketId);
   GlobalVariableSet(GvName("SellBasketId"), (double)g_sellBasketId);
   GlobalVariableSet(GvName("NextBasketId"), (double)g_nextBasketId);
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
   if(GlobalVariableCheck(GvName("BuyOpenedLvl")))
      g_buyOpenedLevel = (int)GlobalVariableGet(GvName("BuyOpenedLvl"));
   if(GlobalVariableCheck(GvName("SellOpenedLvl")))
      g_sellOpenedLevel = (int)GlobalVariableGet(GvName("SellOpenedLvl"));
   if(GlobalVariableCheck(GvName("BuyTrailSl")))
      g_buyTrailSl = GlobalVariableGet(GvName("BuyTrailSl"));
   if(GlobalVariableCheck(GvName("SellTrailSl")))
      g_sellTrailSl = GlobalVariableGet(GvName("SellTrailSl"));
   if(GlobalVariableCheck(GvName("BuyBasketId")))
      g_buyBasketId = (ulong)GlobalVariableGet(GvName("BuyBasketId"));
   if(GlobalVariableCheck(GvName("SellBasketId")))
      g_sellBasketId = (ulong)GlobalVariableGet(GvName("SellBasketId"));
   if(GlobalVariableCheck(GvName("NextBasketId")))
      g_nextBasketId = (ulong)GlobalVariableGet(GvName("NextBasketId"));
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
   CreateLabel(g_panelPrefix + "TITLE", x + 12, y + 10, "PremGoldAdvisorV1.3", CLR_GOLD2, 11);
   CreateLabel(g_panelPrefix + "SUB", x + 12, y + 30, "1 order, then scale-in on each TP", CLR_MUTED, 8);

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
                   StringFormat("B %d/5 | S %d/5", g_buyOpenedLevel, g_sellOpenedLevel));
   ObjectSetString(0, g_panelPrefix + "V_HIT", OBJPROP_TEXT,
                   StringFormat("Buy TP%d | Sell TP%d", g_buyHitLevel, g_sellHitLevel));
   ObjectSetString(0, g_panelPrefix + "V_TRAIL", OBJPROP_TEXT,
                   StringFormat("Buy SL@TP%d | Sell SL@TP%d", g_buyTrailTo, g_sellTrailTo));
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
