//+------------------------------------------------------------------+
//|                                            PremGoldAdvisor.mq5   |
//|                         PremGoldAdvisor V1.1                     |
//|  XAUUSD M5 straddle-grid scalper (Buy Stop + Sell Stop ladder)   |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor V1.1"
#property link      ""
#property version   "1.80"
#property description "XAUUSD M5 STEEV 10+10. Close a cycle only in net profit, then place a fresh 10+10. Cancels the opposite side after a fill. Does not flatten at a loss."

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

input group "=== Core ==="
input double            InpLotSize              = 0.01;     // Lot size per pending order
input int               InpLevels               = 10;       // Buy Stop + Sell Stop count (each side)
input double            InpGridStep             = 0.30;     // Distance between levels (price)
input double            InpFirstDistance        = 0.30;     // Distance from Ask/Bid to first stop
input double            InpBasketStopLossUSD    = 0.00;     // Optional loss cap, 0=off (profit-only close)
input double            InpMinCloseProfitUSD    = 0.50;     // Close ALL only when net floating profit >= this ($)
input int               InpMaxCyclesPerBar      = 2;        // Cycle counter wrap
input int               InpMaxHoldSeconds       = 0;        // Unused - never force-close at a loss
input int               InpBreakevenPips        = 20;       // Move SL to entry after this profit (never SL into a loss)
input int               InpTrailingPips         = 30;       // Trail in profit only

input group "=== Filters ==="
input double            InpMaxSpread            = 0.80;     // Max spread in price units (0=off)
input bool              InpRequireM5            = true;     // Trade only on M5 chart
input int               InpStartHour            = 0;        // Trading start hour (server)
input int               InpEndHour              = 23;       // Trading end hour (server)
input bool              InpCloseOnFriday        = false;    // Close all and stop on Friday
input int               InpFridayCloseHour      = 21;       // Friday close hour (server)

input group "=== Execution ==="
input ulong             InpMagic                = 110110;   // Magic number
input int               InpDeviationPoints      = 30;       // Max slippage in points
input int               InpMaxRetries           = 3;        // Order send/close retries
input string            InpComment              = "PGA-V1.1"; // Order comment

input group "=== Interface ==="
input bool              InpShowPanel            = true;     // Show STEEV-style on-chart panel
input int               InpPanelX               = 12;       // Panel X offset
input int               InpPanelY               = 18;       // Panel Y offset
input bool              InpApplyChartTheme      = true;     // Dark gold chart theme

CTrade         g_trade;
int            g_digits = 2;
double         g_point  = 0.01;
double         g_tickSize = 0.01;
long           g_stopsLevel = 0;
datetime       g_lastPlaceAttempt = 0;
datetime       g_cycleStartTime = 0;
datetime       g_lastStatsTime = 0;
bool           g_paused = false;
bool           g_tradingAllowed = true;
string         g_status = "READY";
string         g_lastAction = "-";
double         g_lastBookedProfit = 0.0;
double         g_todayProfit = 0.0;
int            g_cycles = 0;
int            g_cyclesThisBar = 0;
bool           g_flattening = false;
string         g_flattenReason = "";
double         g_flattenBooked = 0.0;

const string   PFX = "PGA_";
const int      PANEL_W = 292;
const int      PANEL_H = 438;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_stopsLevel = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(g_tickSize <= 0.0)
      g_tickSize = g_point;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetAsyncMode(false);
   ConfigureFilling();

   if(InpLevels < 1 || InpLevels > 50)
     {
      Alert("PremGoldAdvisor: Levels must be 1-50.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || InpGridStep <= 0.0 || InpFirstDistance <= 0.0)
     {
      Alert("PremGoldAdvisor: Lot, grid step and first distance must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxCyclesPerBar < 1)
     {
      Alert("PremGoldAdvisor: Max cycles per candle must be >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }

   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("PremGoldAdvisor warning: hedging account is recommended. Netting will merge same-direction fills.");

   if(InpRequireM5 && Period() != PERIOD_M5)
      Print("PremGoldAdvisor: attach this EA on M5. Current TF=", EnumToString(Period()));

   g_cyclesThisBar = 0;
   g_cycleStartTime = 0;
   g_flattening = false;
   g_flattenReason = "";
   g_flattenBooked = 0.0;
   g_paused = false;
   g_tradingAllowed = true;
   g_status = "READY";

   if(InpApplyChartTheme)
      ApplyChartTheme();

   if(InpShowPanel)
      CreatePanel();

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   PrintFormat("PremGoldAdvisor M5 | close only if net profit >= $%.2f | then new 10+10 | %s step=%.2f",
               InpMinCloseProfitUSD, _Symbol, InpGridStep);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeletePanel();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   RefreshStats();

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
      UpdatePanel();
      return;
     }

   if(!g_tradingAllowed)
     {
      UpdatePanel();
      return;
     }

   if(InpRequireM5 && Period() != PERIOD_M5)
     {
      g_status = "USE M5 CHART";
      UpdatePanel();
      return;
     }

   if(InpCloseOnFriday && IsFridayCloseTime())
     {
      if(CountPositions() > 0 && BasketProfit() >= InpMinCloseProfitUSD)
         StartFlatten(BasketProfit(), "Friday profit");
      else
         DeleteAllPendings();
      g_status = "FRIDAY CLOSE";
      UpdatePanel();
      return;
     }

   if(!IsTradingHour())
     {
      g_status = "OFF HOURS";
      UpdatePanel();
      return;
     }

   double basket = BasketProfit();
   bool hitSL = (InpBasketStopLossUSD > 0.0 && basket <= -InpBasketStopLossUSD);

   if(CountPositions() > 0)
     {
      CancelOppositeSide();
      ManageTrailingStops();
     }

   if(CountPositions() > 0 && basket >= InpMinCloseProfitUSD)
     {
      StartFlatten(basket, "M5 PROFIT");
      UpdatePanel();
      return;
     }

   if(hitSL && InpBasketStopLossUSD > 0.0)
     {
      StartFlatten(basket, "BASKET SL");
      UpdatePanel();
      return;
     }

   int positions = CountPositions();
   int pendings  = CountPendings();
   int buyPos, sellPos, buyPend, sellPend;
   CountSides(buyPos, sellPos, buyPend, sellPend);

   if(positions == 0 && (buyPend != InpLevels || sellPend != InpLevels))
     {
      if(pendings > 0)
        {
         DeleteAllPendings();
         g_lastAction = "Cleared leftover orders - no hold";
        }
      if(g_cyclesThisBar >= InpMaxCyclesPerBar)
         g_cyclesThisBar = 0;
      PlaceFreshLadder("M5 10+10", true);
     }

   if(CountPositions() > 0 || CountPendings() > 0)
      g_status = StringFormat("CYCLE %d / %d", MathMin(g_cyclesThisBar + 1, InpMaxCyclesPerBar), InpMaxCyclesPerBar);

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
      StartFlatten(BasketProfit(), "MANUAL CLOSE");
      UpdatePanel();
     }
   else if(sparam == PFX + "BTN_PAUSE")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      g_paused = !g_paused;
      g_status = g_paused ? "PAUSED" : "HUNTING GOLD";
      g_lastAction = g_paused ? "Paused by trader" : "Resumed";
      UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
void StartFlatten(const double booked, const string reason)
  {
   g_flattening = true;
   g_flattenBooked = booked;
   g_flattenReason = reason;
   g_status = "CLOSING ALL";
   g_lastAction = "Closing every position and pending";
   FinishFlatten();
  }

//+------------------------------------------------------------------+
void FinishFlatten()
  {
   CloseAll(g_flattenReason);

   if(CountPositions() + CountPendings() > 0)
     {
      g_status = "CLOSING ALL";
      g_lastAction = StringFormat("Still closing  pos=%d  pend=%d", CountPositions(), CountPendings());
      return;
     }

   g_flattening = false;
   g_lastBookedProfit = g_flattenBooked;
   g_cycles++;
   g_cyclesThisBar++;
   g_status = "CYCLE CLOSED";
   g_lastAction = StringFormat("Closed ALL  %s  $%.2f", g_flattenReason, g_flattenBooked);

   if(g_cyclesThisBar >= InpMaxCyclesPerBar)
      g_cyclesThisBar = 0;

   PlaceFreshLadder("M5 10+10", true);
  }

//+------------------------------------------------------------------+
bool ShouldFlattenNow(const double basket)
  {
   if(basket >= InpMinCloseProfitUSD)
      return true;
   if(AnyPositionInProfit())
      return true;
   return false;
  }

//+------------------------------------------------------------------+
string FlattenReason(const double basket)
  {
   if(basket >= InpMinCloseProfitUSD)
      return "OVERALL PROFIT";
   if(AnyPositionInProfit())
      return "TRADE PROFIT - CLOSE ALL";
   return "CLOSE ALL";
  }

//+------------------------------------------------------------------+
bool AnyPositionInProfit()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOurPosition())
         continue;
      double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(p >= InpMinCloseProfitUSD)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool PlaceFreshLadder(const string why, const bool resetClock)
  {
   if(CountPositions() > 0)
      return false;

   int buyPos, sellPos, buyPend, sellPend;
   CountSides(buyPos, sellPos, buyPend, sellPend);
   if(buyPend == InpLevels && sellPend == InpLevels)
      return true;

   DeleteAllPendings();

   if(SpreadTooWide())
     {
      g_status = "SPREAD WIDE";
      g_lastAction = why + " delayed - spread";
      return false;
     }
   g_lastPlaceAttempt = TimeCurrent();
   if(resetClock || g_cycleStartTime == 0)
      g_cycleStartTime = TimeCurrent();
   if(!PlaceStraddleGrid())
     {
      DeleteAllPendings();
      g_status = "PLACE FAIL";
      g_lastAction = why + " failed - leftovers cleared";
      return false;
     }
   g_status = "HUNTING GOLD";
   g_lastAction = StringFormat("%s  %d/%d  M5  %d buy + %d sell", why, MathMin(g_cyclesThisBar + 1, InpMaxCyclesPerBar), InpMaxCyclesPerBar, InpLevels, InpLevels);
   return true;
  }

//+------------------------------------------------------------------+
bool CycleTimedOut()
  {
   if(InpMaxHoldSeconds <= 0)
      return false;
   if(g_cycleStartTime == 0)
      return false;
   if(CountPositions() + CountPendings() == 0)
      return false;
   return ((TimeCurrent() - g_cycleStartTime) >= InpMaxHoldSeconds);
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   if(g_digits == 3 || g_digits == 5)
      return g_point * 10.0;
   return g_point;
  }

//+------------------------------------------------------------------+
double TrailDistance()
  {
   if(InpTrailingPips <= 0)
      return 0.0;
   double dist = InpTrailingPips * PipSize();
   return MathMax(dist, MinStopDistance());
  }

//+------------------------------------------------------------------+
void ManageTrailingStops()
  {
   double beDist = (InpBreakevenPips > 0 ? InpBreakevenPips * PipSize() : 0.0);
   double trail  = TrailDistance();
   if(beDist <= 0.0 && trail <= 0.0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minGap = MinStopDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOurPosition())
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double newSL = sl;

      if(type == POSITION_TYPE_BUY)
        {
         double profitDist = bid - open;
         if(beDist > 0.0 && profitDist < beDist)
            continue;
         newSL = open;
         if(trail > 0.0)
            newSL = MathMax(newSL, bid - trail);
         newSL = NormalizePrice(MathMax(newSL, open));
         if(bid - newSL < minGap)
            continue;
         if(sl > 0.0 && newSL <= sl)
            continue;
         if(newSL >= bid || newSL < open)
            continue;
        }
      else
        {
         double profitDist = open - ask;
         if(beDist > 0.0 && profitDist < beDist)
            continue;
         newSL = open;
         if(trail > 0.0)
            newSL = MathMin(newSL, ask + trail);
         newSL = NormalizePrice(MathMin(newSL, open));
         if(newSL - ask < minGap)
            continue;
         if(sl > 0.0 && newSL >= sl)
            continue;
         if(newSL <= ask || newSL > open)
            continue;
        }

      g_trade.PositionModify(ticket, newSL, tp);
     }
  }

//+------------------------------------------------------------------+
int CycleSecondsLeft()
  {
   if(g_cycleStartTime == 0 || InpMaxHoldSeconds <= 0)
      return InpMaxHoldSeconds;
   int left = InpMaxHoldSeconds - (int)(TimeCurrent() - g_cycleStartTime);
   if(left < 0)
      left = 0;
   return left;
  }

//+------------------------------------------------------------------+
void WaitMs(const int ms)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   Sleep(ms);
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
bool PlaceStraddleGrid()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double minDist = MinStopDistance();
   double firstBuy  = MathMax(InpFirstDistance, minDist);
   double firstSell = MathMax(InpFirstDistance, minDist);
   double lot = NormalizeLot(InpLotSize);
   int placedBuy = 0;
   int placedSell = 0;

   for(int i = 0; i < InpLevels; i++)
     {
      double buyPrice = NormalizePrice(ask + firstBuy + i * InpGridStep);
      if(buyPrice > ask && SendPending(ORDER_TYPE_BUY_STOP, buyPrice, lot, 0.0))
         placedBuy++;
     }

   for(int i = 0; i < InpLevels; i++)
     {
      double sellPrice = NormalizePrice(bid - firstSell - i * InpGridStep);
      if(sellPrice < bid && sellPrice > 0.0 && SendPending(ORDER_TYPE_SELL_STOP, sellPrice, lot, 0.0))
         placedSell++;
     }

   PrintFormat("PremGoldAdvisor: placed BuyStop=%d SellStop=%d Bid=%s Ask=%s",
               placedBuy, placedSell,
               DoubleToString(bid, g_digits),
               DoubleToString(ask, g_digits));

   return (placedBuy == InpLevels && placedSell == InpLevels);
  }

//+------------------------------------------------------------------+
bool SendPending(ENUM_ORDER_TYPE type, double price, double lot, double sl)
  {
   for(int attempt = 0; attempt < InpMaxRetries; attempt++)
     {
      ResetLastError();
      bool ok = false;
      if(type == ORDER_TYPE_BUY_STOP)
         ok = g_trade.BuyStop(lot, price, _Symbol, sl, 0.0, ORDER_TIME_GTC, 0, InpComment);
      else
         ok = g_trade.SellStop(lot, price, _Symbol, sl, 0.0, ORDER_TIME_GTC, 0, InpComment);

      if(ok)
         return true;

      PrintFormat("PremGoldAdvisor pending failed type=%s price=%s sl=%s ret=%s",
                  EnumToString(type), DoubleToString(price, g_digits), DoubleToString(sl, g_digits), g_trade.ResultRetcodeDescription());
      WaitMs(80);
      ConfigureFilling();
     }
   return false;
  }

//+------------------------------------------------------------------+
void CloseAll(const string reason)
  {
   double before = BasketProfit();
   g_lastAction = reason;
   for(int pass = 0; pass < 12; pass++)
     {
      DeleteAllPendings();
      CloseAllPositions();
      if(CountPositions() + CountPendings() == 0)
         break;
     }
   PrintFormat("PremGoldAdvisor: %s | flatten pass done | basket was $%.2f | left pos=%d pend=%d",
               reason, before, CountPositions(), CountPendings());
  }

//+------------------------------------------------------------------+
void DeleteAllPendings()
  {
   DeletePendingSide(true);
   DeletePendingSide(false);
  }

//+------------------------------------------------------------------+
void CancelOppositeSide()
  {
   int buyPos, sellPos, buyPend, sellPend;
   CountSides(buyPos, sellPos, buyPend, sellPend);
   if(buyPos > 0 && sellPos == 0 && sellPend > 0)
      DeletePendingSide(false);
   if(sellPos > 0 && buyPos == 0 && buyPend > 0)
      DeletePendingSide(true);
  }

//+------------------------------------------------------------------+
void DeletePendingSide(const bool deleteBuys)
  {
   for(int pass = 0; pass < 8; pass++)
     {
      bool remaining = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(!IsOurOrder())
            continue;
         ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         bool isBuy = (t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_BUY_LIMIT);
         if(deleteBuys != isBuy)
            continue;
         if(!CancelPending(ticket))
            remaining = true;
        }
      if(!remaining)
         break;
     }
  }

//+------------------------------------------------------------------+
bool CancelPending(const ulong ticket)
  {
   if(g_trade.OrderDelete(ticket))
      return true;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_REMOVE;
   request.order  = ticket;
   request.magic  = InpMagic;
   return OrderSend(request, result);
  }

//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int pass = 0; pass < 10; pass++)
     {
      bool remaining = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(!IsOurPosition())
            continue;
         if(!CloseOnePosition(ticket))
            remaining = true;
        }
      if(!remaining)
         break;
     }
  }

//+------------------------------------------------------------------+
bool CloseOnePosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return true;
   if(!IsOurPosition())
      return true;

   if(g_trade.PositionClose(ticket, (ulong)InpDeviationPoints))
      return true;

   if(!PositionSelectByTicket(ticket))
      return true;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double price  = (type == POSITION_TYPE_BUY
                    ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                    : SymbolInfoDouble(_Symbol, SYMBOL_ASK));

   ENUM_ORDER_TYPE_FILLING fills[3];
   fills[0] = ORDER_FILLING_IOC;
   fills[1] = ORDER_FILLING_FOK;
   fills[2] = ORDER_FILLING_RETURN;

   for(int f = 0; f < 3; f++)
     {
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = _Symbol;
      request.volume   = volume;
      request.type     = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      request.position = ticket;
      request.price    = price;
      request.deviation= (uint)InpDeviationPoints;
      request.magic    = InpMagic;
      request.comment  = InpComment;
      request.type_filling = fills[f];
      if(OrderSend(request, result))
         return true;
     }
   PrintFormat("PremGoldAdvisor: close failed ticket=%s ret=%s",
               IntegerToString((long)ticket), g_trade.ResultRetcodeDescription());
   return false;
  }

//+------------------------------------------------------------------+
double BasketProfit()
  {
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOurPosition())
         continue;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return profit;
  }

//+------------------------------------------------------------------+
void CountSides(int &buyPos, int &sellPos, int &buyPend, int &sellPend)
  {
   buyPos = sellPos = buyPend = sellPend = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(!IsOurPosition())
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buyPos++;
      else
         sellPos++;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(!IsOurOrder())
         continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_BUY_LIMIT)
         buyPend++;
      else if(t == ORDER_TYPE_SELL_STOP || t == ORDER_TYPE_SELL_LIMIT)
         sellPend++;
     }
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
int CountPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(IsOurOrder())
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
bool IsOurPosition()
  {
   return (PositionGetString(POSITION_SYMBOL) == _Symbol
           && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//+------------------------------------------------------------------+
bool IsOurOrder()
  {
   return (OrderGetString(ORDER_SYMBOL) == _Symbol
           && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic);
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
   return NormalizeDouble(lot, 2);
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
void CreatePanel()
  {
   Comment("");
   int x = InpPanelX;
   int y = InpPanelY;

   MakeRect(PFX + "BG",     x, y,      PANEL_W, PANEL_H, CLR_BG, CLR_GOLD);
   MakeRect(PFX + "HDR",    x, y,      PANEL_W, 62,      C'20,16,8', CLR_GOLD);
   MakeRect(PFX + "ACCENT", x, y + 62, PANEL_W, 3,       CLR_GOLD, CLR_GOLD);
   MakeRect(PFX + "CARD1",  x + 10, y + 78,  PANEL_W - 20, 118, CLR_CARD, CLR_LINE);
   MakeRect(PFX + "CARD2",  x + 10, y + 206, PANEL_W - 20, 118, CLR_CARD, CLR_LINE);
   MakeRect(PFX + "CARD3",  x + 10, y + 334, PANEL_W - 20, 46,  CLR_CARD, CLR_LINE);

   MakeLabel(PFX + "TITLE",    x + 16, y + 10, "PREMGOLD ADVISOR", CLR_GOLD2, 13, "Segoe UI Semibold");
   MakeLabel(PFX + "SUB",      x + 16, y + 34, "XAUUSD  M5  HUNT ENGINE", CLR_MUTED, 8, "Segoe UI");
   MakeLabel(PFX + "STATUS",   x + 168, y + 34, "READY", CLR_GREEN, 8, "Segoe UI Semibold");

   MakeLabel(PFX + "L_BAL",    x + 22, y + 88,  "BALANCE", CLR_MUTED, 8);
   MakeLabel(PFX + "V_BAL",    x + 150, y + 86, "0.00", CLR_TEXT, 11, "Consolas");
   MakeLabel(PFX + "L_EQ",     x + 22, y + 110, "EQUITY", CLR_MUTED, 8);
   MakeLabel(PFX + "V_EQ",     x + 150, y + 108, "0.00", CLR_TEXT, 11, "Consolas");
   MakeLabel(PFX + "L_FLT",    x + 22, y + 132, "FLOATING", CLR_MUTED, 8);
   MakeLabel(PFX + "V_FLT",    x + 150, y + 130, "0.00", CLR_TEXT, 11, "Consolas");
   MakeLabel(PFX + "L_DAY",    x + 22, y + 154, "TODAY", CLR_MUTED, 8);
   MakeLabel(PFX + "V_DAY",    x + 150, y + 152, "0.00", CLR_TEXT, 11, "Consolas");
   MakeLabel(PFX + "L_LAST",   x + 22, y + 176, "LAST BOOKED", CLR_MUTED, 8);
   MakeLabel(PFX + "V_LAST",   x + 150, y + 174, "0.00", CLR_GOLD, 11, "Consolas");

   MakeLabel(PFX + "L_SPR",    x + 22, y + 216, "SPREAD", CLR_MUTED, 8);
   MakeLabel(PFX + "V_SPR",    x + 22, y + 234, "0.00", CLR_TEXT, 10, "Consolas");
   MakeLabel(PFX + "L_LOT",    x + 150, y + 216, "LOT", CLR_MUTED, 8);
   MakeLabel(PFX + "V_LOT",    x + 150, y + 234, "0.01", CLR_TEXT, 10, "Consolas");

   MakeLabel(PFX + "L_BUYP",   x + 22, y + 258, "BUY STOP", CLR_MUTED, 8);
   MakeLabel(PFX + "V_BUYP",   x + 22, y + 276, "0", CLR_GREEN, 10, "Consolas");
   MakeLabel(PFX + "L_SELLP",  x + 150, y + 258, "SELL STOP", CLR_MUTED, 8);
   MakeLabel(PFX + "V_SELLP",  x + 150, y + 276, "0", CLR_RED, 10, "Consolas");

   MakeLabel(PFX + "L_CYC",    x + 22, y + 300, "CYCLE", CLR_MUTED, 8);
   MakeLabel(PFX + "V_CYC",    x + 22, y + 318, "0/2", CLR_GOLD2, 10, "Consolas");
   MakeLabel(PFX + "L_TMR",    x + 150, y + 300, "CLOSE", CLR_MUTED, 8);
   MakeLabel(PFX + "V_TMR",    x + 150, y + 318, "PROFIT", CLR_GREEN, 10, "Consolas");

   MakeLabel(PFX + "V_INFO",   x + 22, y + 346, "M5  close only in profit  then new 10+10", CLR_MUTED, 8);
   MakeLabel(PFX + "V_ACT",    x + 22, y + 364, "-", CLR_TEXT, 8);

   MakeButton(PFX + "BTN_CLOSE", x + 10, y + 390, 132, 36, "CLOSE ALL", CLR_BTN2, CLR_TEXT);
   MakeButton(PFX + "BTN_PAUSE", x + 150, y + 390, 132, 36, "PAUSE", CLR_BTN, CLR_GOLD2);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   if(ObjectFind(0, PFX + "BG") < 0)
      CreatePanel();

   int buyPos, sellPos, buyPend, sellPend;
   CountSides(buyPos, sellPos, buyPend, sellPend);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   double basket = BasketProfit();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   color stClr = CLR_GOLD2;
   if(g_status == "HUNTING GOLD")
      stClr = CLR_GREEN;
   else if(StringFind(g_status, "WAIT") >= 0 || g_status == "PAUSED" || g_status == "OFF HOURS")
      stClr = CLR_GOLD;
   else if(StringFind(g_status, "FAIL") >= 0 || g_status == "STOPPED OUT" || g_status == "AUTO TRADING OFF")
      stClr = CLR_RED;

   color fltClr = (basket > 0.0 ? CLR_GREEN : (basket < 0.0 ? CLR_RED : CLR_TEXT));
   color dayClr = (g_todayProfit > 0.0 ? CLR_GREEN : (g_todayProfit < 0.0 ? CLR_RED : CLR_TEXT));

   SetText(PFX + "SUB",    StringFormat("%s   M5 STEEV GRID", _Symbol), CLR_MUTED);
   SetText(PFX + "STATUS", g_status, stClr);
   SetText(PFX + "V_BAL",  DoubleToString(balance, 2), CLR_TEXT);
   SetText(PFX + "V_EQ",   DoubleToString(equity, 2), CLR_TEXT);
   SetText(PFX + "V_FLT",  (basket >= 0.0 ? "+" : "") + DoubleToString(basket, 2), fltClr);
   SetText(PFX + "V_DAY",  (g_todayProfit >= 0.0 ? "+" : "") + DoubleToString(g_todayProfit, 2), dayClr);
   SetText(PFX + "V_LAST", DoubleToString(g_lastBookedProfit, 2), CLR_GOLD);
   SetText(PFX + "V_SPR",  DoubleToString(spread, g_digits), (SpreadTooWide() ? CLR_RED : CLR_TEXT));
   SetText(PFX + "V_LOT",  DoubleToString(InpLotSize, 2), CLR_TEXT);
   SetText(PFX + "V_BUYP", IntegerToString(buyPend) + "  /  " + IntegerToString(buyPos) + " open", CLR_GREEN);
   SetText(PFX + "V_SELLP", IntegerToString(sellPend) + "  /  " + IntegerToString(sellPos) + " open", CLR_RED);
   int shownCycle = g_cyclesThisBar;
   if(buyPos + sellPos + buyPend + sellPend > 0)
      shownCycle = MathMin(g_cyclesThisBar + 1, InpMaxCyclesPerBar);
   SetText(PFX + "V_CYC",  StringFormat("%d / %d", shownCycle, InpMaxCyclesPerBar), CLR_GOLD2);
   SetText(PFX + "V_TMR",  "PROFIT", CLR_GREEN);
   SetText(PFX + "V_INFO", StringFormat("M5 profit-only >= $%s  step %s",
            DoubleToString(InpMinCloseProfitUSD, 2), DoubleToString(InpGridStep, 2)), CLR_MUTED);
   SetText(PFX + "V_ACT",  g_lastAction, CLR_TEXT);

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
