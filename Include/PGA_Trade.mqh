#ifndef PGA_TRADE_MQH
#define PGA_TRADE_MQH

#include <Trade/Trade.mqh>
#include "PGA_Inputs.mqh"
#include "PGA_Utils.mqh"
#include "PGA_Logger.mqh"
#include "PGA_State.mqh"
#include "PGA_Indicators.mqh"
#include "PGA_Filters.mqh"
#include "PGA_Risk.mqh"

CTrade g_trade;

int PgaCountOurPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
     }
   return count;
  }

bool PgaSelectOurPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      return PositionSelectByTicket(ticket);
     }
   return false;
  }

void PgaRecoverOpenPosition()
  {
   if(!PgaSelectOurPosition())
     {
      g_managedTicket = 0;
      g_trailActive   = false;
      PgaSaveState();
      return;
     }

   g_managedTicket = (ulong)PositionGetInteger(POSITION_TICKET);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   long   type = PositionGetInteger(POSITION_TYPE);

   if(sl > 0.0)
     {
      if(type == POSITION_TYPE_BUY)
         g_trailActive = (sl > open);
      else
         g_trailActive = (sl < open);
     }
   else
      g_trailActive = false;

   PgaLog(StringFormat("Recovered position ticket=%I64u %s sl=%s trail=%s",
                       g_managedTicket,
                       PgaSideText(type),
                       DoubleToString(sl, _Digits),
                       (g_trailActive ? "on" : "off")));
   PgaSaveState();
  }

void PgaConfigureTrade()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(PgaFillingMode());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   g_trade.SetAsyncMode(false);
  }

bool PgaClosePosition(const string reason)
  {
   if(!PgaSelectOurPosition())
      return false;

   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double vol    = PositionGetDouble(POSITION_VOLUME);
   double price  = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   if(!g_trade.PositionClose(ticket))
     {
      PgaLog("Close failed ticket=" + IntegerToString((int)ticket) + " ret=" + IntegerToString(g_trade.ResultRetcode()) + " " + g_trade.ResultRetcodeDescription());
      return false;
     }

   PgaLogTrade("EXIT", PgaSideText(type), ticket, vol, price, sl, tp,
               reason + " | profit=" + DoubleToString(profit, 2));
   g_lastCloseTime = TimeCurrent();
   g_managedTicket = 0;
   g_trailActive   = false;
   PgaSaveState();
   return true;
  }

bool PgaOpenPosition(const bool isBuy, const string signalReason)
  {
   if(PgaCountOurPositions() > 0)
     {
      g_blockReason = "Already in a trade";
      return false;
     }

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   if(!PgaCalcStops(isBuy, price, sl, tp))
     {
      g_blockReason = "Invalid stop calculation";
      return false;
     }

   double lot = PgaSelectLot(MathAbs(price - sl));
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string reason = "";
   if(!PgaMarginOk(orderType, lot, price, reason))
     {
      g_blockReason = reason;
      PgaLog("Entry blocked: " + reason);
      return false;
     }

   string comment = isBuy ? "PGA Buy" : "PGA Sell";
   bool ok = false;
   if(isBuy)
      ok = g_trade.Buy(lot, _Symbol, 0.0, sl, tp, comment);
   else
      ok = g_trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(!ok)
     {
      PgaLog("Entry failed " + comment + " ret=" + IntegerToString(g_trade.ResultRetcode()) + " " + g_trade.ResultRetcodeDescription());
      g_blockReason = "Order rejected: " + g_trade.ResultRetcodeDescription();
      return false;
     }

   ulong ticket = 0;
   if(PgaSelectOurPosition())
     {
      ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double fill = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl2 = 0.0, tp2 = 0.0;
      if(PgaCalcStops(isBuy, fill, sl2, tp2))
        {
         sl = sl2;
         tp = tp2;
         g_trade.PositionModify(ticket, sl, tp);
        }
      price = fill;
     }
   if(ticket == 0)
      ticket = g_trade.ResultOrder();

   g_managedTicket = ticket;
   g_trailActive   = false;
   g_lastSignalDir = isBuy ? 1 : -1;
   g_lastSignalBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   PgaSaveState();

   PgaLogTrade("ENTRY", isBuy ? "BUY" : "SELL", ticket, lot, g_trade.ResultPrice(), sl, tp, signalReason);
   g_status = isBuy ? "Long position" : "Short position";
   return true;
  }

void PgaManageTrailing()
  {
   if(!InpUseTrailingStop || g_atr <= 0.0)
      return;
   if(!PgaSelectOurPosition())
      return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ulong  ticket= (ulong)PositionGetInteger(POSITION_TICKET);

   double activate = InpTrailActivateATR * g_atr;
   double profitDist = (type == POSITION_TYPE_BUY) ? (bid - open) : (open - ask);
   if(!g_trailActive)
     {
      if(profitDist < activate)
         return;
      g_trailActive = true;
      PgaLog("Trailing activated ticket=" + IntegerToString((int)ticket) + " profitDist=" + DoubleToString(profitDist, _Digits));
     }

   double trailDist = PgaTrailDistance();
   if(PgaAdxWeakening() || PgaStochApproachingExit(type))
      trailDist *= InpTrailTightenFactor;

   int minPoints = PgaStopsLevelPoints();
   double minDist = minPoints * _Point;
   if(trailDist < minDist)
      trailDist = minDist;
   if(trailDist <= 0.0)
      return;

   double newSl = sl;
   if(type == POSITION_TYPE_BUY)
     {
      newSl = PgaNormalizePrice(bid - trailDist);
      if(newSl <= sl)
         return;
      if(newSl >= bid - minDist && minDist > 0.0)
         newSl = PgaNormalizePrice(bid - minDist);
      if(newSl <= sl)
         return;
     }
   else
     {
      newSl = PgaNormalizePrice(ask + trailDist);
      if(sl > 0.0 && newSl >= sl)
         return;
      if(minDist > 0.0 && newSl <= ask + minDist)
         newSl = PgaNormalizePrice(ask + minDist);
      if(sl > 0.0 && newSl >= sl)
         return;
     }

   if(!g_trade.PositionModify(ticket, newSl, tp))
     {
      PgaLog("Trail modify failed ret=" + IntegerToString(g_trade.ResultRetcode()) + " " + g_trade.ResultRetcodeDescription());
      return;
     }
   PgaSaveState();
  }

void PgaManageExits()
  {
   if(!PgaSelectOurPosition())
     {
      if(g_managedTicket != 0)
        {
         g_lastCloseTime = TimeCurrent();
         g_managedTicket = 0;
         g_trailActive   = false;
         PgaSaveState();
        }
      return;
     }

   long type = PositionGetInteger(POSITION_TYPE);
   if(InpUseStochExit)
     {
      if(type == POSITION_TYPE_BUY && PgaStochExitBuy())
        {
         PgaClosePosition("Stochastic reached " + DoubleToString(InpExitLevel, 1));
         return;
        }
      if(type == POSITION_TYPE_SELL && PgaStochExitSell())
        {
         PgaClosePosition("Stochastic reached " + DoubleToString(InpExitLevel, 1));
         return;
        }
     }

   PgaManageTrailing();
  }

bool PgaDuplicateSignal(const int dir)
  {
   datetime closedBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(closedBar == 0)
      return true;
   if(g_lastSignalBar == closedBar && g_lastSignalDir == dir)
      return true;
   return false;
  }

void PgaTryEntries()
  {
   if(PgaCountOurPositions() > 0)
     {
      g_status = "In trade";
      g_blockReason = "";
      return;
     }

   string reason = "";
   if(!PgaCommonFiltersAllow(reason))
     {
      g_status = "Blocked";
      g_blockReason = reason;
      return;
     }

   if(PgaBuySignal())
     {
      if(PgaDuplicateSignal(1))
        {
         g_status = "Scanning";
         g_blockReason = "Duplicate buy signal ignored";
         return;
        }
      if(!PgaFiltersAllowBuy(reason))
        {
         g_status = "Blocked";
         g_blockReason = reason;
         return;
        }
      PgaOpenPosition(true, StringFormat("Stoch K/D %.1f/%.1f cross up in buy zone, ADX %.1f ATR %s",
                                         g_k, g_d, g_adx, DoubleToString(g_atr, _Digits)));
      return;
     }

   if(PgaSellSignal())
     {
      if(PgaDuplicateSignal(-1))
        {
         g_status = "Scanning";
         g_blockReason = "Duplicate sell signal ignored";
         return;
        }
      if(!PgaFiltersAllowSell(reason))
        {
         g_status = "Blocked";
         g_blockReason = reason;
         return;
        }
      PgaOpenPosition(false, StringFormat("Stoch K/D %.1f/%.1f cross down in sell zone, ADX %.1f ATR %s",
                                          g_k, g_d, g_adx, DoubleToString(g_atr, _Digits)));
      return;
     }

   g_status = "Scanning";
   g_blockReason = "";
  }

#endif
