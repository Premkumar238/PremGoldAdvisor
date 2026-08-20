//+------------------------------------------------------------------+
//|                                            PremGoldAdvisor.mq5   |
//|                         PremGoldAdvisor V1.2                     |
//|  AI Trend EMA-ribbon advisor (Pine "AI TREND NEW PANEL" port)    |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor V1.2"
#property link      ""
#property version   "2.00"
#property description "PremGoldAdvisor V1.2 — AI Trend EMA ribbon (30-60). Buys when the ribbon stacks bullish, sells when it stacks bearish. Percent SL with TP1-TP4. Does not guarantee profit."

#include <Trade/Trade.mqh>

#define CLR_BG        C'12,12,16'
#define CLR_CARD      C'22,22,28'
#define CLR_LINE      C'48,44,32'
#define CLR_GOLD      C'212,175,55'
#define CLR_GOLD2     C'240,205,90'
#define CLR_GREEN     C'0,186,90'
#define CLR_RED       C'220,52,62'
#define CLR_BLUE      C'40,90,200'
#define CLR_TEXT      C'236,236,240'
#define CLR_MUTED     C'148,148,156'
#define CLR_BTN       C'32,28,18'
#define CLR_BTN2      C'42,22,26'
#define CLR_NAVY      C'0,0,90'
#define CLR_LIME      C'0,230,119'
#define CLR_GRAY      C'90,90,96'

enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,          // Fixed lot size
   LOT_RISK_PERCENT = 1    // Risk percent of equity
  };

enum ENUM_DASH_SIZE
  {
   DASH_SMALL = 0,         // Small
   DASH_NORMAL = 1,        // Normal
   DASH_LARGE = 2          // Large
  };

input group "=== Core ==="
input bool              InpTradeEnabled         = true;     // Enable auto trading
input ENUM_LOT_MODE     InpLotMode              = LOT_FIXED; // Lot sizing
input double            InpLotSize              = 0.01;     // Fixed lot size
input double            InpRiskPercent          = 1.0;      // Risk % of equity (if Risk percent)
input ulong             InpMagic                = 120212;   // Magic number
input int               InpDeviationPoints      = 30;       // Max slippage (points)
input int               InpMaxRetries           = 3;        // Order send retries
input string            InpComment              = "PGA-V1.2"; // Order comment
input bool              InpReverseOnOpposite    = true;     // Close and reverse on opposite ribbon flip
input bool              InpOneTradeOnly         = true;     // Never stack extra positions

input group "=== EMA Ribbon (Pine) ==="
input int               InpEma1                 = 30;       // EMA 1
input int               InpEma2                 = 35;       // EMA 2
input int               InpEma3                 = 40;       // EMA 3
input int               InpEma4                 = 45;       // EMA 4
input int               InpEma5                 = 50;       // EMA 5
input int               InpEma6                 = 60;       // EMA 6
input bool              InpShowEmaOnChart       = true;     // Overlay EMA ribbon on chart

input group "=== Multi-Timeframe Dashboard ==="
input ENUM_TIMEFRAMES   InpTf1                  = PERIOD_M15; // TF 1
input ENUM_TIMEFRAMES   InpTf2                  = PERIOD_M30; // TF 2
input ENUM_TIMEFRAMES   InpTf3                  = PERIOD_H1;  // TF 3
input ENUM_TIMEFRAMES   InpTf4                  = PERIOD_H4;  // TF 4
input ENUM_TIMEFRAMES   InpTf5                  = PERIOD_D1;  // TF 5
input int               InpHtfFast              = 20;       // HTF fast EMA
input int               InpHtfSlow              = 50;       // HTF slow EMA
input bool              InpUseHtfFilter         = false;    // Require HTF majority with the signal
input int               InpHtfMinAgree          = 3;        // Minimum HTF timeframes that must agree (1-5)

input group "=== Risk / Targets (Pine) ==="
input double            InpStopLossPct          = 0.17;     // Stop Loss %
input double            InpTp1Multiplier        = 1.0;      // TP1 multiplier
input double            InpTp2Multiplier        = 2.0;      // TP2 multiplier
input double            InpTp3Multiplier        = 3.0;      // TP3 multiplier
input double            InpTp4Multiplier        = 4.0;      // TP4 multiplier
input bool              InpUsePartialClose      = true;     // Partial close at TP1-TP3
input double            InpTp1ClosePercent      = 25.0;     // Close % at TP1
input double            InpTp2ClosePercent      = 25.0;     // Close % at TP2
input double            InpTp3ClosePercent      = 25.0;     // Close % at TP3
input int               InpBrokerTpLevel        = 4;        // Broker take-profit level (1-4)
input bool              InpBreakevenOnTp1       = true;     // Move SL to entry when TP1 is touched
input bool              InpTrailSlOnEachTp      = true;     // Trail SL to previous TP as TP2/TP3/TP4 are touched
input int               InpBreakevenOffsetPoints = 0;       // Extra points past entry (0 = exact entry / zero)

input group "=== ATR Filter ==="
input bool              InpUseAtrFilter         = true;     // Enable ATR filter
input int               InpAtrPeriod            = 14;       // ATR period
input double            InpMinAtr               = 0.50;     // Minimum ATR to allow entries

input group "=== Filters ==="
input double            InpMaxSpread            = 0.80;     // Max spread in price (0=off)
input int               InpStartHour            = 0;        // Trading start hour (server)
input int               InpEndHour              = 23;       // Trading end hour (server)
input bool              InpCloseOnFriday        = false;    // Close all late Friday
input int               InpFridayCloseHour      = 21;       // Friday close hour (server)
input int               InpCooldownSeconds      = 0;        // Seconds to wait after a close (0=off)

input group "=== Display ==="
input bool              InpShowPanel            = true;     // Show on-chart panel
input ENUM_DASH_SIZE    InpDashboardSize        = DASH_NORMAL; // Panel text size
input int               InpPanelX               = 12;       // Panel X offset
input int               InpPanelY               = 18;       // Panel Y offset
input bool              InpShowLevels           = true;     // Draw entry / SL / TP lines
input bool              InpShowNumbers          = true;     // Show price labels on levels
input bool              InpShowSignalLabels     = true;     // Show BUY / SELL labels
input int               InpLineLength           = 8;        // Level line length (bars)
input bool              InpApplyChartTheme      = true;     // Dark gold chart theme
input bool              InpAlerts               = true;     // Alert on new signals

CTrade         g_trade;
int            g_digits = 2;
double         g_point  = 0.01;
double         g_tickSize = 0.01;
long           g_stopsLevel = 0;

int            g_emaHandle[6];
int            g_atrHandle = INVALID_HANDLE;
int            g_htfFastHandle[5];
int            g_htfSlowHandle[5];
string         g_chartMaName[6];

double         g_ema[6];
double         g_emaPrev[6];
double         g_atr = 0.0;
bool           g_bullish = false;
bool           g_bearish = false;
bool           g_bullishPrev = false;
bool           g_bearishPrev = false;
bool           g_htfTrend[5];
bool           g_htfReady[5];

int            g_signalState = 0;     // 1=long, -1=short, 0=none
datetime       g_lastBarTime = 0;
datetime       g_lastCloseTime = 0;
datetime       g_signalBarTime = 0;
double         g_entry = 0.0;
double         g_sl = 0.0;
double         g_tp[5];               // 1..4 used
double         g_entryVolume = 0.0;
bool           g_tpHit[5];
bool           g_trailDone[5];        // 1=SL at entry, 2=SL at TP1, 3=SL at TP2, 4=SL at TP3
bool           g_paused = false;
bool           g_flattening = false;
string         g_status = "READY";
string         g_lastAction = "-";
string         g_blockReason = "";
double         g_lastBookedProfit = 0.0;
double         g_todayProfit = 0.0;
datetime       g_lastStatsTime = 0;
int            g_labelSeq = 0;

const string   PFX = "PGA12_";
int            PANEL_W = 318;
int            PANEL_H = 548;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_stopsLevel = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(g_tickSize <= 0.0)
      g_tickSize = g_point;

   if(InpEma1 < 1 || InpEma2 < 1 || InpEma3 < 1 || InpEma4 < 1 || InpEma5 < 1 || InpEma6 < 1)
     {
      Alert("PremGoldAdvisor V1.2: EMA periods must be >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0)
     {
      Alert("PremGoldAdvisor V1.2: lot size must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpStopLossPct <= 0.0)
     {
      Alert("PremGoldAdvisor V1.2: Stop Loss % must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBrokerTpLevel < 1 || InpBrokerTpLevel > 4)
     {
      Alert("PremGoldAdvisor V1.2: Broker TP level must be 1-4.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetAsyncMode(false);
   ConfigureFilling();

   if(!CreateIndicators())
      return INIT_FAILED;

   LoadState();
   RecoverOpenPosition();
   g_lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   g_status = "READY";
   g_lastAction = "AI Trend engine started";

   if(InpApplyChartTheme)
      ApplyChartTheme();
   if(InpShowPanel)
      CreatePanel();

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   PrintFormat("PremGoldAdvisor V1.2 | %s %s | SL %.3f%% | TP x%.1f/%.1f/%.1f/%.1f | magic %I64u",
               _Symbol, EnumToString(Period()),
               InpStopLossPct,
               InpTp1Multiplier, InpTp2Multiplier, InpTp3Multiplier, InpTp4Multiplier,
               InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveState();
   ReleaseIndicators();
   DeletePanel();
   DeleteLevels();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   RefreshStats();

   if(!UpdateIndicators())
     {
      g_status = "WAITING DATA";
      UpdatePanel();
      return;
     }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_status = "AUTO TRADING OFF";
      UpdatePanel();
      return;
     }

   if(g_flattening)
     {
      FinishFlatten();
      UpdatePanel();
      return;
     }

   if(g_paused)
     {
      g_status = "PAUSED";
      ManageOpenTrade();
      UpdatePanel();
      return;
     }

   if(InpCloseOnFriday && IsFridayCloseTime())
     {
      if(CountPositions() > 0)
         StartFlatten("Friday close");
      g_status = "FRIDAY CLOSE";
      UpdatePanel();
      return;
     }

   ManageOpenTrade();

   bool newBar = IsNewBar();
   if(newBar && InpTradeEnabled && !g_paused)
      TryEntries();

   if(CountPositions() > 0)
      g_status = (g_signalState == 1 ? "LONG" : (g_signalState == -1 ? "SHORT" : "IN TRADE"));
   else if(g_status != "BLOCKED" && g_status != "OFF HOURS" && g_status != "SPREAD WIDE" && g_status != "FRIDAY CLOSE")
      g_status = "SCANNING";

   DrawLevels();
   UpdatePanel();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == PFX + "BTN_CLOSE")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      StartFlatten("MANUAL CLOSE");
      UpdatePanel();
     }
   else if(sparam == PFX + "BTN_PAUSE")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      g_paused = !g_paused;
      g_status = g_paused ? "PAUSED" : "SCANNING";
      g_lastAction = g_paused ? "Paused by trader" : "Resumed";
      UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                   + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why = "Position close";
   if(reason == DEAL_REASON_SL)
      why = "Stop loss";
   else if(reason == DEAL_REASON_TP)
      why = "Take profit";
   else if(reason == DEAL_REASON_SO)
      why = "Stop out";
   else if(reason == DEAL_REASON_EXPERT)
      why = "EA close";

   g_lastCloseTime = TimeCurrent();
   g_lastBookedProfit = profit;
   if(CountPositions() == 0)
     {
      g_lastAction = StringFormat("%s  $%.2f", why, profit);
      if(reason == DEAL_REASON_SL || reason == DEAL_REASON_TP || reason == DEAL_REASON_SO)
         g_status = (reason == DEAL_REASON_SL ? "STOPPED" : "TARGET HIT");
     }
   SaveState();
  }

//+------------------------------------------------------------------+
bool CreateIndicators()
  {
   for(int i = 0; i < 6; i++)
      g_emaHandle[i] = INVALID_HANDLE;
   g_atrHandle = INVALID_HANDLE;
   for(int i = 0; i < 5; i++)
     {
      g_htfFastHandle[i] = INVALID_HANDLE;
      g_htfSlowHandle[i] = INVALID_HANDLE;
     }

   int periods[6];
   periods[0] = InpEma1;
   periods[1] = InpEma2;
   periods[2] = InpEma3;
   periods[3] = InpEma4;
   periods[4] = InpEma5;
   periods[5] = InpEma6;

   for(int i = 0; i < 6; i++)
     {
      g_emaHandle[i] = iMA(_Symbol, PERIOD_CURRENT, periods[i], 0, MODE_EMA, PRICE_CLOSE);
      g_chartMaName[i] = "";
      if(g_emaHandle[i] == INVALID_HANDLE)
        {
         Print("PremGoldAdvisor V1.2: failed to create EMA handle ", periods[i]);
         return false;
        }
     }

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("PremGoldAdvisor V1.2: failed to create ATR handle");
      return false;
     }

   ENUM_TIMEFRAMES tfs[5];
   tfs[0] = InpTf1;
   tfs[1] = InpTf2;
   tfs[2] = InpTf3;
   tfs[3] = InpTf4;
   tfs[4] = InpTf5;
   for(int i = 0; i < 5; i++)
     {
      g_htfFastHandle[i] = iMA(_Symbol, tfs[i], InpHtfFast, 0, MODE_EMA, PRICE_CLOSE);
      g_htfSlowHandle[i] = iMA(_Symbol, tfs[i], InpHtfSlow, 0, MODE_EMA, PRICE_CLOSE);
      g_htfReady[i] = false;
      g_htfTrend[i] = false;
      if(g_htfFastHandle[i] == INVALID_HANDLE || g_htfSlowHandle[i] == INVALID_HANDLE)
         PrintFormat("PremGoldAdvisor V1.2: HTF EMA handle failed for %s", EnumToString(tfs[i]));
     }

   if(InpShowEmaOnChart)
      AddRibbonToChart();
   return true;
  }

//+------------------------------------------------------------------+
void AddRibbonToChart()
  {
   for(int i = 0; i < 6; i++)
     {
      if(g_emaHandle[i] == INVALID_HANDLE)
         continue;
      if(!ChartIndicatorAdd(0, 0, g_emaHandle[i]))
         continue;
      int total = ChartIndicatorsTotal(0, 0);
      if(total > 0)
         g_chartMaName[i] = ChartIndicatorName(0, 0, total - 1);
     }
  }

//+------------------------------------------------------------------+
void ReleaseIndicators()
  {
   if(InpShowEmaOnChart)
     {
      for(int i = 0; i < 6; i++)
        {
         if(g_chartMaName[i] != "")
            ChartIndicatorDelete(0, 0, g_chartMaName[i]);
        }
     }
   for(int i = 0; i < 6; i++)
     {
      if(g_emaHandle[i] != INVALID_HANDLE)
         IndicatorRelease(g_emaHandle[i]);
      g_emaHandle[i] = INVALID_HANDLE;
     }
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   g_atrHandle = INVALID_HANDLE;
   for(int i = 0; i < 5; i++)
     {
      if(g_htfFastHandle[i] != INVALID_HANDLE)
         IndicatorRelease(g_htfFastHandle[i]);
      if(g_htfSlowHandle[i] != INVALID_HANDLE)
         IndicatorRelease(g_htfSlowHandle[i]);
      g_htfFastHandle[i] = INVALID_HANDLE;
      g_htfSlowHandle[i] = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
bool CopyShift(const int handle, const int shift, double &value)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 0, shift + 1, buf) < shift + 1)
      return false;
   value = buf[shift];
   return (value != EMPTY_VALUE && value == value);
  }

//+------------------------------------------------------------------+
bool UpdateIndicators()
  {
   for(int i = 0; i < 6; i++)
     {
      if(!CopyShift(g_emaHandle[i], 1, g_ema[i]))
         return false;
      if(!CopyShift(g_emaHandle[i], 2, g_emaPrev[i]))
         return false;
     }
   if(!CopyShift(g_atrHandle, 1, g_atr))
      return false;

   g_bullish = (g_ema[0] > g_ema[1] && g_ema[1] > g_ema[2] && g_ema[2] > g_ema[3] && g_ema[3] > g_ema[4] && g_ema[4] > g_ema[5]);
   g_bearish = (g_ema[0] < g_ema[1] && g_ema[1] < g_ema[2] && g_ema[2] < g_ema[3] && g_ema[3] < g_ema[4] && g_ema[4] < g_ema[5]);
   g_bullishPrev = (g_emaPrev[0] > g_emaPrev[1] && g_emaPrev[1] > g_emaPrev[2] && g_emaPrev[2] > g_emaPrev[3] && g_emaPrev[3] > g_emaPrev[4] && g_emaPrev[4] > g_emaPrev[5]);
   g_bearishPrev = (g_emaPrev[0] < g_emaPrev[1] && g_emaPrev[1] < g_emaPrev[2] && g_emaPrev[2] < g_emaPrev[3] && g_emaPrev[3] < g_emaPrev[4] && g_emaPrev[4] < g_emaPrev[5]);

   for(int i = 0; i < 5; i++)
     {
      double fast = 0.0, slow = 0.0;
      g_htfReady[i] = (CopyShift(g_htfFastHandle[i], 1, fast) && CopyShift(g_htfSlowHandle[i], 1, slow));
      g_htfTrend[i] = (g_htfReady[i] && fast > slow);
     }
   return true;
  }

//+------------------------------------------------------------------+
bool AtrOk()
  {
   if(!InpUseAtrFilter)
      return true;
   return (g_atr > InpMinAtr);
  }

//+------------------------------------------------------------------+
int HtfAgreeCount(const bool wantBull)
  {
   int n = 0;
   for(int i = 0; i < 5; i++)
     {
      if(!g_htfReady[i])
         continue;
      if(g_htfTrend[i] == wantBull)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
bool HtfAllows(const bool isBuy, string &reason)
  {
   if(!InpUseHtfFilter)
      return true;
   int need = MathMax(1, MathMin(5, InpHtfMinAgree));
   int got = HtfAgreeCount(isBuy);
   if(got >= need)
      return true;
   reason = StringFormat("HTF agree %d/%d (need %d)", got, 5, need);
   return false;
  }

//+------------------------------------------------------------------+
bool LongSignalRaw()
  {
   return (!g_bullishPrev && g_bullish);
  }

//+------------------------------------------------------------------+
bool ShortSignalRaw()
  {
   return (!g_bearishPrev && g_bearish);
  }

//+------------------------------------------------------------------+
void TryEntries()
  {
   if(!IsTradingHour())
     {
      g_status = "OFF HOURS";
      g_blockReason = "Outside trading hours";
      return;
     }
   if(SpreadTooWide())
     {
      g_status = "SPREAD WIDE";
      g_blockReason = "Spread above maximum";
      return;
     }
   if(InpCooldownSeconds > 0 && g_lastCloseTime > 0)
     {
      int elapsed = (int)(TimeCurrent() - g_lastCloseTime);
      if(elapsed < InpCooldownSeconds)
        {
         g_blockReason = StringFormat("Cooldown %ds", InpCooldownSeconds - elapsed);
         return;
        }
     }

   bool atr_ok = AtrOk();
   bool longRaw = LongSignalRaw();
   bool shortRaw = ShortSignalRaw();
   bool longSig = longRaw && g_signalState != 1 && atr_ok;
   bool shortSig = shortRaw && g_signalState != -1 && atr_ok;

   if(longRaw && !atr_ok)
      g_blockReason = StringFormat("ATR %s below min", DoubleToString(g_atr, g_digits));
   if(shortRaw && !atr_ok)
      g_blockReason = StringFormat("ATR %s below min", DoubleToString(g_atr, g_digits));

   if(longSig)
     {
      string why = "";
      if(!HtfAllows(true, why))
        {
         g_status = "BLOCKED";
         g_blockReason = why;
         return;
        }
      HandleSignal(true);
      return;
     }
   if(shortSig)
     {
      string why = "";
      if(!HtfAllows(false, why))
        {
         g_status = "BLOCKED";
         g_blockReason = why;
         return;
        }
      HandleSignal(false);
      return;
     }

   g_blockReason = "";
  }

//+------------------------------------------------------------------+
void HandleSignal(const bool isBuy)
  {
   int dir = isBuy ? 1 : -1;
   int openCount = CountPositions();

   if(openCount > 0)
     {
      if(!SelectOurPosition())
        {
         g_lastAction = "Could not select open position";
         return;
        }
      long openType = PositionGetInteger(POSITION_TYPE);
      bool sameDir = ((isBuy && openType == POSITION_TYPE_BUY) || (!isBuy && openType == POSITION_TYPE_SELL));
      if(sameDir)
        {
         g_signalState = dir;
         SaveState();
         return;
        }
      if(!InpReverseOnOpposite)
        {
         g_blockReason = "Opposite signal ignored - trade open";
         return;
        }
      CloseAllPositions("Reverse");
      if(CountPositions() > 0)
        {
         g_lastAction = "Waiting to reverse - close pending";
         return;
        }
     }

   if(!OpenPosition(isBuy))
      return;

   g_signalState = dir;
   g_signalBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   ResetTpHits();
   PlaceSignalLabel(isBuy);
   if(InpAlerts)
     {
      string msg = StringFormat("PremGoldAdvisor V1.2 %s %s %s at %s",
                                (isBuy ? "BUY" : "SELL"), _Symbol, EnumToString(Period()),
                                DoubleToString(g_entry, g_digits));
      Alert(msg);
     }
   SaveState();
  }

//+------------------------------------------------------------------+
bool OpenPosition(const bool isBuy)
  {
   if(InpOneTradeOnly && CountPositions() > 0)
     {
      g_blockReason = "Already in a trade";
      return false;
     }

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0, tp = 0.0;
   CalcLevels(isBuy, price, sl, g_tp[1], g_tp[2], g_tp[3], g_tp[4]);
   tp = BrokerTp();
   if(!ValidateStops(isBuy, price, sl, tp))
     {
      g_blockReason = "Stops too close to market";
      g_lastAction = g_blockReason;
      return false;
     }

   double lot = SelectLot(MathAbs(price - sl));
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string why = "";
   if(!MarginOk(type, lot, price, why))
     {
      g_blockReason = why;
      g_lastAction = why;
      return false;
     }

   bool ok = false;
   for(int attempt = 0; attempt < InpMaxRetries; attempt++)
     {
      ResetLastError();
      if(isBuy)
         ok = g_trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment);
      else
         ok = g_trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);
      if(ok)
         break;
      PrintFormat("PremGoldAdvisor V1.2 entry failed %s ret=%s",
                  (isBuy ? "BUY" : "SELL"), g_trade.ResultRetcodeDescription());
      WaitMs(80);
      ConfigureFilling();
     }
   if(!ok)
     {
      g_blockReason = "Order rejected: " + g_trade.ResultRetcodeDescription();
      g_lastAction = g_blockReason;
      return false;
     }

   if(SelectOurPosition())
     {
      double fill = PositionGetDouble(POSITION_PRICE_OPEN);
      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      CalcLevels(isBuy, fill, sl, g_tp[1], g_tp[2], g_tp[3], g_tp[4]);
      tp = BrokerTp();
      if(ValidateStops(isBuy, fill, sl, tp))
         g_trade.PositionModify(ticket, sl, tp);
      g_entry = fill;
      g_sl = sl;
      g_entryVolume = PositionGetDouble(POSITION_VOLUME);
     }
   else
     {
      g_entry = price;
      g_sl = sl;
      g_entryVolume = lot;
     }

   g_status = isBuy ? "LONG" : "SHORT";
   g_lastAction = StringFormat("%s  %s  SL %s  TP4 %s",
                               (isBuy ? "BUY" : "SELL"),
                               DoubleToString(g_entry, g_digits),
                               DoubleToString(g_sl, g_digits),
                               DoubleToString(g_tp[4], g_digits));
   g_blockReason = "";
   PrintFormat("PremGoldAdvisor V1.2 ENTRY %s price=%s sl=%s tp1=%s tp4=%s lot=%.2f",
               (isBuy ? "BUY" : "SELL"),
               DoubleToString(g_entry, g_digits),
               DoubleToString(g_sl, g_digits),
               DoubleToString(g_tp[1], g_digits),
               DoubleToString(g_tp[4], g_digits),
               lot);
   return true;
  }

//+------------------------------------------------------------------+
void CalcLevels(const bool isBuy, const double entry,
                double &sl, double &tp1, double &tp2, double &tp3, double &tp4)
  {
   double pct = InpStopLossPct / 100.0;
   if(isBuy)
     {
      sl  = entry * (1.0 - pct);
      tp1 = entry * (1.0 + pct * InpTp1Multiplier);
      tp2 = entry * (1.0 + pct * InpTp2Multiplier);
      tp3 = entry * (1.0 + pct * InpTp3Multiplier);
      tp4 = entry * (1.0 + pct * InpTp4Multiplier);
     }
   else
     {
      sl  = entry * (1.0 + pct);
      tp1 = entry * (1.0 - pct * InpTp1Multiplier);
      tp2 = entry * (1.0 - pct * InpTp2Multiplier);
      tp3 = entry * (1.0 - pct * InpTp3Multiplier);
      tp4 = entry * (1.0 - pct * InpTp4Multiplier);
     }
   sl  = NormalizePrice(sl);
   tp1 = NormalizePrice(tp1);
   tp2 = NormalizePrice(tp2);
   tp3 = NormalizePrice(tp3);
   tp4 = NormalizePrice(tp4);
  }

//+------------------------------------------------------------------+
double BrokerTp()
  {
   int lvl = InpBrokerTpLevel;
   if(lvl < 1)
      lvl = 1;
   if(lvl > 4)
      lvl = 4;
   return g_tp[lvl];
  }

//+------------------------------------------------------------------+
bool ValidateStops(const bool isBuy, const double price, double &sl, double &tp)
  {
   double minDist = MinStopDistance();
   if(isBuy)
     {
      if(price - sl < minDist)
         sl = NormalizePrice(price - minDist);
      if(tp > 0.0 && tp - price < minDist)
         tp = NormalizePrice(price + minDist);
      if(sl >= price || (tp > 0.0 && tp <= price))
         return false;
     }
   else
     {
      if(sl - price < minDist)
         sl = NormalizePrice(price + minDist);
      if(tp > 0.0 && price - tp < minDist)
         tp = NormalizePrice(price - minDist);
      if(sl <= price || (tp > 0.0 && tp >= price))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   if(!SelectOurPosition())
     {
      if(g_entryVolume > 0.0 && CountPositions() == 0)
         g_entryVolume = 0.0;
      return;
     }

   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   g_signalState = isBuy ? 1 : -1;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   if(g_entry <= 0.0)
      g_entry = open;
   if(g_sl <= 0.0)
      g_sl = PositionGetDouble(POSITION_SL);
   if(g_tp[1] <= 0.0)
      CalcLevels(isBuy, g_entry, g_sl, g_tp[1], g_tp[2], g_tp[3], g_tp[4]);
   if(g_entryVolume <= 0.0)
      g_entryVolume = PositionGetDouble(POSITION_VOLUME);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low  = iLow(_Symbol, PERIOD_CURRENT, 0);

   if(isBuy)
     {
      if(high >= g_tp[1] || bid >= g_tp[1])
         g_tpHit[1] = true;
      if(high >= g_tp[2] || bid >= g_tp[2])
         g_tpHit[2] = true;
      if(high >= g_tp[3] || bid >= g_tp[3])
         g_tpHit[3] = true;
      if(high >= g_tp[4] || bid >= g_tp[4])
         g_tpHit[4] = true;
     }
   else
     {
      if(low <= g_tp[1] || ask <= g_tp[1])
         g_tpHit[1] = true;
      if(low <= g_tp[2] || ask <= g_tp[2])
         g_tpHit[2] = true;
      if(low <= g_tp[3] || ask <= g_tp[3])
         g_tpHit[3] = true;
      if(low <= g_tp[4] || ask <= g_tp[4])
         g_tpHit[4] = true;
     }

   UpdateTrailingStops();

   if(InpUsePartialClose)
     {
      TryPartial(1, InpTp1ClosePercent);
      TryPartial(2, InpTp2ClosePercent);
      TryPartial(3, InpTp3ClosePercent);
     }
  }

//+------------------------------------------------------------------+
int HighestTpHit()
  {
   for(int i = 4; i >= 1; i--)
     {
      if(g_tpHit[i])
         return i;
     }
   return 0;
  }

//+------------------------------------------------------------------+
void UpdateTrailingStops()
  {
   int hit = HighestTpHit();
   if(hit <= 0)
      return;

   if(hit == 1)
     {
      TrailToEntry();
      return;
     }

   if(!InpTrailSlOnEachTp)
     {
      TrailToEntry();
      return;
     }

   double target = g_tp[hit - 1];
   if(target <= 0.0)
      return;

   string action = StringFormat("TP%d hit — SL trailed to TP%d", hit, hit - 1);
   if(MoveStopToPrice(target, g_trailDone[hit], action))
      MarkTrailDoneUpTo(hit);
  }

//+------------------------------------------------------------------+
void TrailToEntry()
  {
   if(!InpBreakevenOnTp1)
      return;
   if(!SelectOurPosition())
      return;
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double offset = InpBreakevenOffsetPoints * g_point;
   double target = isBuy ? NormalizePrice(open + offset) : NormalizePrice(open - offset);
   if(MoveStopToPrice(target, g_trailDone[1], "TP1 hit — SL moved to entry"))
      MarkTrailDoneUpTo(1);
  }

//+------------------------------------------------------------------+
void MarkTrailDoneUpTo(const int level)
  {
   int last = MathMax(1, MathMin(4, level));
   for(int i = 1; i <= last; i++)
      g_trailDone[i] = true;
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
bool MoveStopToPrice(const double target, bool &doneFlag, const string action)
  {
   if(doneFlag || target <= 0.0)
      return false;
   if(!SelectOurPosition())
      return false;

   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = MinStopDistance();
   double newSL  = NormalizePrice(target);

   if(isBuy)
     {
      if(sl > 0.0 && newSL <= sl + g_tickSize * 0.5)
        {
         doneFlag = true;
         g_sl = sl;
         SaveState();
         return true;
        }
      if(newSL >= bid || (bid - newSL) < minDist)
         return false;
     }
   else
     {
      if(sl > 0.0 && newSL >= sl - g_tickSize * 0.5)
        {
         doneFlag = true;
         g_sl = sl;
         SaveState();
         return true;
        }
      if(newSL <= ask || (newSL - ask) < minDist)
         return false;
     }

   if(!g_trade.PositionModify(ticket, newSL, tp))
     {
      PrintFormat("PremGoldAdvisor V1.2: %s failed ret=%s",
                  action, g_trade.ResultRetcodeDescription());
      return false;
     }

   g_sl = newSL;
   doneFlag = true;
   g_lastAction = StringFormat("%s %s", action, DoubleToString(newSL, g_digits));
   Print("PremGoldAdvisor V1.2 ", g_lastAction);
   SaveState();
   return true;
  }

//+------------------------------------------------------------------+
void TryPartial(const int level, const double percent)
  {
   if(!g_tpHit[level] || percent <= 0.0)
      return;
   if(!SelectOurPosition())
      return;

   static bool done[5] = {false, false, false, false, false};
   static ulong lastTicket = 0;
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   if(ticket != lastTicket)
     {
      for(int i = 0; i < 5; i++)
         done[i] = false;
      lastTicket = ticket;
     }
   if(done[level])
      return;

   double vol = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double closeVol = NormalizeLot(g_entryVolume * percent / 100.0);
   if(closeVol < minLot)
     {
      done[level] = true;
      return;
     }
   if(vol - closeVol < minLot)
     {
      done[level] = true;
      return;
     }
   if(closeVol > vol)
      closeVol = vol;

   if(g_trade.PositionClosePartial(ticket, closeVol))
     {
      done[level] = true;
      g_lastAction = StringFormat("Partial TP%d  %.2f lots", level, closeVol);
      Print("PremGoldAdvisor V1.2 ", g_lastAction);
     }
  }

//+------------------------------------------------------------------+
void ResetTpHits()
  {
   for(int i = 0; i < 5; i++)
     {
      g_tpHit[i] = false;
      g_trailDone[i] = false;
     }
  }

//+------------------------------------------------------------------+
void RecoverOpenPosition()
  {
   if(!SelectOurPosition())
      return;
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   g_signalState = isBuy ? 1 : -1;
   g_entry = PositionGetDouble(POSITION_PRICE_OPEN);
   g_sl = PositionGetDouble(POSITION_SL);
   g_entryVolume = PositionGetDouble(POSITION_VOLUME);
   double calcSl = 0.0;
   CalcLevels(isBuy, g_entry, calcSl, g_tp[1], g_tp[2], g_tp[3], g_tp[4]);
   for(int i = 0; i < 5; i++)
      g_trailDone[i] = false;
   double bePrice = g_entry;
   if(InpBreakevenOffsetPoints != 0)
      bePrice = isBuy ? (g_entry + InpBreakevenOffsetPoints * g_point)
                      : (g_entry - InpBreakevenOffsetPoints * g_point);
   g_trailDone[1] = StopAlreadyAtOrBeyond(isBuy, g_sl, bePrice);
   g_trailDone[2] = StopAlreadyAtOrBeyond(isBuy, g_sl, g_tp[1]);
   g_trailDone[3] = StopAlreadyAtOrBeyond(isBuy, g_sl, g_tp[2]);
   g_trailDone[4] = StopAlreadyAtOrBeyond(isBuy, g_sl, g_tp[3]);
   g_status = isBuy ? "LONG" : "SHORT";
   g_lastAction = "Recovered open position";
  }

//+------------------------------------------------------------------+
void StartFlatten(const string reason)
  {
   g_flattening = true;
   g_status = "CLOSING ALL";
   g_lastAction = reason;
   FinishFlatten();
  }

//+------------------------------------------------------------------+
void FinishFlatten()
  {
   CloseAllPositions(g_lastAction);
   if(CountPositions() > 0)
     {
      g_status = "CLOSING ALL";
      return;
     }
   g_flattening = false;
   g_status = "FLAT";
   g_lastAction = "Closed all positions";
   g_lastCloseTime = TimeCurrent();
   DeleteLevels();
   SaveState();
  }

//+------------------------------------------------------------------+
void CloseAllPositions(const string reason)
  {
   for(int pass = 0; pass < 8; pass++)
     {
      bool remaining = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!IsOurPosition())
            continue;
         if(!g_trade.PositionClose(ticket, (ulong)InpDeviationPoints))
            remaining = true;
        }
      if(!remaining)
         break;
     }
   PrintFormat("PremGoldAdvisor V1.2: %s | left pos=%d", reason, CountPositions());
  }

//+------------------------------------------------------------------+
int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(IsOurPosition())
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
bool SelectOurPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOurPosition())
         continue;
      return PositionSelectByTicket(ticket);
     }
   return false;
  }

//+------------------------------------------------------------------+
bool IsOurPosition()
  {
   return (PositionGetString(POSITION_SYMBOL) == _Symbol
           && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//+------------------------------------------------------------------+
double BasketProfit()
  {
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(!IsOurPosition())
         continue;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return profit;
  }

//+------------------------------------------------------------------+
double SelectLot(const double slDistance)
  {
   if(InpLotMode != LOT_RISK_PERCENT)
      return NormalizeLot(InpLotSize);
   if(slDistance <= 0.0)
      return NormalizeLot(InpLotSize);

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double money    = equity * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickVal <= 0.0)
      return NormalizeLot(InpLotSize);

   double ticks = slDistance / tickSize;
   if(ticks <= 0.0)
      return NormalizeLot(InpLotSize);
   return NormalizeLot(money / (ticks * tickVal));
  }

//+------------------------------------------------------------------+
bool MarginOk(const ENUM_ORDER_TYPE type, const double lot, const double price, string &reason)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin))
     {
      reason = "OrderCalcMargin failed";
      return false;
     }
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free < margin * 1.2)
     {
      reason = StringFormat("Free margin %.2f < required %.2f", free, margin * 1.2);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void ConfigureFilling()
  {
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC && (filling & SYMBOL_FILLING_FOK) == 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK && (filling & SYMBOL_FILLING_IOC) == 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
void WaitMs(const int ms)
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
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t <= 0)
      return false;
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

//+------------------------------------------------------------------+
void RefreshStats()
  {
   if(TimeCurrent() == g_lastStatsTime)
      return;
   g_lastStatsTime = TimeCurrent();
   g_todayProfit = TodayClosedProfit();
  }

//+------------------------------------------------------------------+
double TodayClosedProfit()
  {
   datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(from, TimeCurrent() + 1))
      return g_todayProfit;

   double profit = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;
      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                + HistoryDealGetDouble(ticket, DEAL_SWAP)
                + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   return profit;
  }

//+------------------------------------------------------------------+
string GvName(const string key)
  {
   return "PGA12_" + IntegerToString((int)InpMagic) + "_" + _Symbol + "_" + key;
  }

//+------------------------------------------------------------------+
void SaveState()
  {
   GlobalVariableSet(GvName("State"), (double)g_signalState);
   GlobalVariableSet(GvName("Entry"), g_entry);
   GlobalVariableSet(GvName("SL"), g_sl);
   GlobalVariableSet(GvName("TP1"), g_tp[1]);
   GlobalVariableSet(GvName("TP2"), g_tp[2]);
   GlobalVariableSet(GvName("TP3"), g_tp[3]);
   GlobalVariableSet(GvName("TP4"), g_tp[4]);
   GlobalVariableSet(GvName("Vol"), g_entryVolume);
   GlobalVariableSet(GvName("LastClose"), (double)g_lastCloseTime);
   GlobalVariableSet(GvName("SigBar"), (double)g_signalBarTime);
   GlobalVariableSet(GvName("Hit1"), g_tpHit[1] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Hit2"), g_tpHit[2] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Hit3"), g_tpHit[3] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Hit4"), g_tpHit[4] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("BE"), g_trailDone[1] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Trail1"), g_trailDone[2] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Trail2"), g_trailDone[3] ? 1.0 : 0.0);
   GlobalVariableSet(GvName("Trail3"), g_trailDone[4] ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
void LoadState()
  {
   if(!GlobalVariableCheck(GvName("State")))
      return;
   g_signalState   = (int)GlobalVariableGet(GvName("State"));
   g_entry         = GlobalVariableGet(GvName("Entry"));
   g_sl            = GlobalVariableGet(GvName("SL"));
   g_tp[1]         = GlobalVariableGet(GvName("TP1"));
   g_tp[2]         = GlobalVariableGet(GvName("TP2"));
   g_tp[3]         = GlobalVariableGet(GvName("TP3"));
   g_tp[4]         = GlobalVariableGet(GvName("TP4"));
   g_entryVolume   = GlobalVariableGet(GvName("Vol"));
   g_lastCloseTime = (datetime)GlobalVariableGet(GvName("LastClose"));
   g_signalBarTime = (datetime)GlobalVariableGet(GvName("SigBar"));
   g_tpHit[1]      = (GlobalVariableGet(GvName("Hit1")) > 0.5);
   g_tpHit[2]      = (GlobalVariableGet(GvName("Hit2")) > 0.5);
   g_tpHit[3]      = (GlobalVariableGet(GvName("Hit3")) > 0.5);
   g_tpHit[4]      = (GlobalVariableGet(GvName("Hit4")) > 0.5);
   g_trailDone[1] = (GlobalVariableGet(GvName("BE")) > 0.5);
   g_trailDone[2] = (GlobalVariableGet(GvName("Trail1")) > 0.5);
   g_trailDone[3] = (GlobalVariableGet(GvName("Trail2")) > 0.5);
   g_trailDone[4] = (GlobalVariableGet(GvName("Trail3")) > 0.5);
  }

//+------------------------------------------------------------------+
void ApplyChartTheme()
  {
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'8,8,10');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'210,210,214');
   ChartSetInteger(0, CHART_COLOR_GRID, C'36,36,42');
   ChartSetInteger(0, CHART_COLOR_CHART_UP, CLR_GREEN);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, CLR_RED);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, CLR_GREEN);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, CLR_RED);
   ChartSetInteger(0, CHART_COLOR_BID, CLR_GOLD);
   ChartSetInteger(0, CHART_COLOR_ASK, CLR_RED);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, true);
   ChartSetInteger(0, CHART_SHOW_GRID, true);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void PlaceSignalLabel(const bool isBuy)
  {
   if(!InpShowSignalLabels)
      return;
   g_labelSeq++;
   string name = PFX + "SIG_" + IntegerToString(g_labelSeq);
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 1);
   double atrPad = (g_atr > 0.0 ? g_atr * 0.5 : 10.0 * g_point);
   double price = isBuy ? (iLow(_Symbol, PERIOD_CURRENT, 1) - atrPad)
                        : (iHigh(_Symbol, PERIOD_CURRENT, 1) + atrPad);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? CLR_GREEN : CLR_RED);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetString(0, name, OBJPROP_TEXT, isBuy ? "BUY" : "SELL");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(g_labelSeq > 80)
     {
      ObjectDelete(0, PFX + "SIG_" + IntegerToString(g_labelSeq - 80));
     }
  }

//+------------------------------------------------------------------+
void DrawLevels()
  {
   if(!InpShowLevels)
     {
      DeleteLevels();
      return;
     }
   if(g_signalState == 0 || g_entry <= 0.0)
     {
      DeleteLevels();
      return;
     }

   datetime t1 = g_signalBarTime;
   if(t1 <= 0)
      t1 = iTime(_Symbol, PERIOD_CURRENT, 1);
   datetime t2 = TimeCurrent() + (datetime)(PeriodSeconds() * MathMax(1, InpLineLength));

   DrawTrend(PFX + "L_ENTRY", t1, g_entry, t2, g_entry, CLR_BLUE, "ENTRY");
   DrawTrend(PFX + "L_SL",    t1, g_sl,    t2, g_sl,    CLR_RED,  "SL");
   DrawTrend(PFX + "L_TP1",   t1, g_tp[1], t2, g_tp[1], CLR_GREEN,"TP1");
   DrawTrend(PFX + "L_TP2",   t1, g_tp[2], t2, g_tp[2], CLR_GREEN,"TP2");
   DrawTrend(PFX + "L_TP3",   t1, g_tp[3], t2, g_tp[3], CLR_GREEN,"TP3");
   DrawTrend(PFX + "L_TP4",   t1, g_tp[4], t2, g_tp[4], CLR_GREEN,"TP4");

   DrawFill(PFX + "F_SL", t1, g_sl, t2, g_entry, C'80,20,20');
   DrawFill(PFX + "F_TP", t1, g_entry, t2, g_tp[4], C'20,70,40');
  }

//+------------------------------------------------------------------+
void DrawTrend(const string name, const datetime t1, const double p1,
               const datetime t2, const double p2, const color clr, const string tag)
  {
   if(p1 <= 0.0)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);

   if(!InpShowNumbers)
      return;
   string lbl = name + "_TXT";
   if(ObjectFind(0, lbl) < 0)
      ObjectCreate(0, lbl, OBJ_TEXT, 0, t2, p1);
   ObjectSetInteger(0, lbl, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, lbl, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, lbl, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, lbl, OBJPROP_TEXT, "  " + tag + " " + DoubleToString(p1, g_digits));
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void DrawFill(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr)
  {
   if(p1 <= 0.0 || p2 <= 0.0)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
  }

//+------------------------------------------------------------------+
void DeleteLevels()
  {
   string names[] = {"L_ENTRY","L_SL","L_TP1","L_TP2","L_TP3","L_TP4","F_SL","F_TP"};
   for(int i = 0; i < ArraySize(names); i++)
     {
      ObjectDelete(0, PFX + names[i]);
      ObjectDelete(0, PFX + names[i] + "_TXT");
     }
  }

//+------------------------------------------------------------------+
int FontSize()
  {
   if(InpDashboardSize == DASH_SMALL)
      return 7;
   if(InpDashboardSize == DASH_LARGE)
      return 9;
   return 8;
  }

//+------------------------------------------------------------------+
string TrendText()
  {
   if(g_bullish)
      return "BULLISH";
   if(g_bearish)
      return "BEARISH";
   return "NEUTRAL";
  }

//+------------------------------------------------------------------+
color TrendColor()
  {
   if(g_bullish)
      return CLR_LIME;
   if(g_bearish)
      return CLR_RED;
   return CLR_GRAY;
  }

//+------------------------------------------------------------------+
string SignalText()
  {
   if(g_signalState == 1)
      return "BUY";
   if(g_signalState == -1)
      return "SELL";
   return "NONE";
  }

//+------------------------------------------------------------------+
string TpHitsText()
  {
   if(g_tpHit[4])
      return "TP4 HIT";
   if(g_tpHit[3])
      return "TP3 HIT";
   if(g_tpHit[2])
      return "TP2 HIT";
   if(g_tpHit[1])
      return "TP1 HIT";
   return "NONE";
  }

//+------------------------------------------------------------------+
string HtfCell(const int idx)
  {
   if(!g_htfReady[idx])
      return "--";
   return (g_htfTrend[idx] ? "UP" : "DN");
  }

//+------------------------------------------------------------------+
string TfShort(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      default:         return EnumToString(tf);
     }
  }

//+------------------------------------------------------------------+
void CreatePanel()
  {
   Comment("");
   int x = InpPanelX;
   int y = InpPanelY;
   int fs = FontSize();

   MakeRect(PFX + "BG",     x, y,      PANEL_W, PANEL_H, CLR_BG, CLR_GOLD);
   MakeRect(PFX + "HDR",    x, y,      PANEL_W, 58,      C'20,16,8', CLR_GOLD);
   MakeRect(PFX + "ACCENT", x, y + 58, PANEL_W, 3,       CLR_GOLD, CLR_GOLD);
   MakeRect(PFX + "CARD1",  x + 10, y + 72,  PANEL_W - 20, 168, CLR_CARD, CLR_LINE);
   MakeRect(PFX + "CARD2",  x + 10, y + 250, PANEL_W - 20, 92,  CLR_CARD, CLR_LINE);
   MakeRect(PFX + "CARD3",  x + 10, y + 352, PANEL_W - 20, 118, CLR_CARD, CLR_LINE);

   MakeLabel(PFX + "TITLE",  x + 16, y + 8,  "PREMGOLD ADVISOR", CLR_GOLD2, 13, "Segoe UI Semibold");
   MakeLabel(PFX + "SUB",    x + 16, y + 32, "V1.2  AI TREND ENGINE", CLR_MUTED, 8, "Segoe UI");
   MakeLabel(PFX + "STATUS", x + 188, y + 32, "READY", CLR_GREEN, 8, "Segoe UI Semibold");

   int lx = x + 22;
   int vx = x + 150;
   int row = y + 82;
   int step = 18;

   MakeLabel(PFX + "L_TRD", lx, row, "TREND", CLR_MUTED, fs);
   MakeLabel(PFX + "V_TRD", vx, row, "NEUTRAL", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_SIG", lx, row, "SIGNAL", CLR_MUTED, fs);
   MakeLabel(PFX + "V_SIG", vx, row, "NONE", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_ENT", lx, row, "ENTRY", CLR_MUTED, fs);
   MakeLabel(PFX + "V_ENT", vx, row, "-", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_SL",  lx, row, "STOP LOSS", CLR_MUTED, fs);
   MakeLabel(PFX + "V_SL",  vx, row, "-", CLR_RED, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_TP12", lx, row, "TP1 / TP2", CLR_MUTED, fs);
   MakeLabel(PFX + "V_TP12", vx, row, "-", CLR_GREEN, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_TP34", lx, row, "TP3 / TP4", CLR_MUTED, fs);
   MakeLabel(PFX + "V_TP34", vx, row, "-", CLR_GREEN, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_HIT", lx, row, "TP HITS", CLR_MUTED, fs);
   MakeLabel(PFX + "V_HIT", vx, row, "NONE", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_FIL", lx, row, "FILTER", CLR_MUTED, fs);
   MakeLabel(PFX + "V_FIL", vx, row, "-", CLR_MUTED, fs, "Consolas");

   row = y + 260;
   MakeLabel(PFX + "L_MTF", lx, row, "MULTI-TIMEFRAME", CLR_GOLD, fs, "Segoe UI Semibold");
   row += step;
   MakeLabel(PFX + "L_H12", lx, row, TfShort(InpTf1) + " / " + TfShort(InpTf2), CLR_MUTED, fs);
   MakeLabel(PFX + "V_H12", vx, row, "- / -", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_H34", lx, row, TfShort(InpTf3) + " / " + TfShort(InpTf4), CLR_MUTED, fs);
   MakeLabel(PFX + "V_H34", vx, row, "- / -", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_H5",  lx, row, TfShort(InpTf5), CLR_MUTED, fs);
   MakeLabel(PFX + "V_H5",  vx, row, "-", CLR_TEXT, fs, "Consolas");

   row = y + 362;
   MakeLabel(PFX + "L_BAL", lx, row, "BALANCE", CLR_MUTED, fs);
   MakeLabel(PFX + "V_BAL", vx, row, "0.00", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_FLT", lx, row, "FLOATING", CLR_MUTED, fs);
   MakeLabel(PFX + "V_FLT", vx, row, "0.00", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_DAY", lx, row, "TODAY", CLR_MUTED, fs);
   MakeLabel(PFX + "V_DAY", vx, row, "0.00", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_SPR", lx, row, "SPREAD / ATR", CLR_MUTED, fs);
   MakeLabel(PFX + "V_SPR", vx, row, "-", CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "L_SYM", lx, row, "SYM / TF", CLR_MUTED, fs);
   MakeLabel(PFX + "V_SYM", vx, row, _Symbol, CLR_TEXT, fs, "Consolas");
   row += step;
   MakeLabel(PFX + "V_ACT", lx, row, "-", CLR_MUTED, 7);

   MakeButton(PFX + "BTN_CLOSE", x + 10, y + 500, 144, 36, "CLOSE ALL", CLR_BTN2, CLR_TEXT);
   MakeButton(PFX + "BTN_PAUSE", x + 164, y + 500, 144, 36, "PAUSE", CLR_BTN, CLR_GOLD2);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
      return;
   if(ObjectFind(0, PFX + "BG") < 0)
      CreatePanel();

   double basket = BasketProfit();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   color stClr = CLR_GOLD2;
   if(g_status == "LONG" || g_status == "SCANNING" || g_status == "TARGET HIT")
      stClr = CLR_GREEN;
   else if(g_status == "SHORT" || g_status == "STOPPED" || g_status == "AUTO TRADING OFF" || g_status == "BLOCKED")
      stClr = CLR_RED;
   else if(g_status == "PAUSED" || g_status == "OFF HOURS")
      stClr = CLR_GOLD;

   SetText(PFX + "STATUS", g_status, stClr);
   SetText(PFX + "V_TRD",  TrendText(), TrendColor());
   SetText(PFX + "V_SIG",  SignalText(), (g_signalState == 1 ? CLR_LIME : (g_signalState == -1 ? CLR_RED : CLR_GRAY)));
   SetText(PFX + "V_ENT",  g_entry > 0.0 ? DoubleToString(g_entry, g_digits) : "-", CLR_BLUE);
   SetText(PFX + "V_SL",   g_sl > 0.0 ? DoubleToString(g_sl, g_digits) : "-", CLR_RED);
   SetText(PFX + "V_TP12", (g_tp[1] > 0.0 ? DoubleToString(g_tp[1], g_digits) : "-") + " / " +
                           (g_tp[2] > 0.0 ? DoubleToString(g_tp[2], g_digits) : "-"), CLR_GREEN);
   SetText(PFX + "V_TP34", (g_tp[3] > 0.0 ? DoubleToString(g_tp[3], g_digits) : "-") + " / " +
                           (g_tp[4] > 0.0 ? DoubleToString(g_tp[4], g_digits) : "-"), CLR_GREEN);
   SetText(PFX + "V_HIT",  TpHitsText(), (g_tpHit[1] ? CLR_LIME : CLR_TEXT));
   string filt = g_blockReason;
   if(StringLen(filt) > 28)
      filt = StringSubstr(filt, 0, 28) + "...";
   SetText(PFX + "V_FIL",  StringLen(filt) == 0 ? "-" : filt, CLR_MUTED);

   color c1 = g_htfReady[0] ? (g_htfTrend[0] ? CLR_LIME : CLR_RED) : CLR_MUTED;
   color c3 = g_htfReady[2] ? (g_htfTrend[2] ? CLR_LIME : CLR_RED) : CLR_MUTED;
   color c5 = g_htfReady[4] ? (g_htfTrend[4] ? CLR_LIME : CLR_RED) : CLR_MUTED;
   SetText(PFX + "V_H12", HtfCell(0) + " / " + HtfCell(1), c1);
   SetText(PFX + "V_H34", HtfCell(2) + " / " + HtfCell(3), c3);
   SetText(PFX + "V_H5",  HtfCell(4), c5);

   color fltClr = (basket > 0.0 ? CLR_GREEN : (basket < 0.0 ? CLR_RED : CLR_TEXT));
   color dayClr = (g_todayProfit > 0.0 ? CLR_GREEN : (g_todayProfit < 0.0 ? CLR_RED : CLR_TEXT));
   SetText(PFX + "V_BAL", DoubleToString(balance, 2), CLR_TEXT);
   SetText(PFX + "V_FLT", (basket >= 0.0 ? "+" : "") + DoubleToString(basket, 2), fltClr);
   SetText(PFX + "V_DAY", (g_todayProfit >= 0.0 ? "+" : "") + DoubleToString(g_todayProfit, 2), dayClr);
   SetText(PFX + "V_SPR", DoubleToString(spread, g_digits) + " / " + DoubleToString(g_atr, g_digits),
           SpreadTooWide() ? CLR_RED : CLR_TEXT);
   SetText(PFX + "V_SYM", _Symbol + " | " + TfShort(Period()), CLR_TEXT);
   SetText(PFX + "V_ACT", g_lastAction, CLR_TEXT);

   ObjectSetString(0, PFX + "BTN_PAUSE", OBJPROP_TEXT, g_paused ? "RESUME" : "PAUSE");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void MakeRect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void MakeLabel(const string name, const int x, const int y, const string text, const color clr, const int size, const string font = "Segoe UI")
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void MakeButton(const string name, const int x, const int y, const int w, const int h, const string text, const color bg, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_GOLD);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void SetText(const string name, const string text, const color clr)
  {
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void DeletePanel()
  {
   Comment("");
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
