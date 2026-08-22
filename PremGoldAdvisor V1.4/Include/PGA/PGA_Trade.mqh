//+------------------------------------------------------------------+
//| PGA_Trade.mqh — sequential single-order execution                |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_TRADE_MQH
#define PGA_TRADE_MQH

#include <Trade\Trade.mqh>
#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"
#include "PGA_Basket.mqh"

class CPGATradeExecutor
{
private:
   CTrade      m_trade;
   CPGASymbol *m_sym;
   long        m_magic;
   ulong       m_deviation;
   double      m_lot;

   void ApplyFillingMode(const string symbol)
   {
      const long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   bool ResolveTicketByComment(const string comment, ulong &ticket)
   {
      ticket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong t = PositionGetTicket(i);
         if(t == 0 || !PositionSelectByTicket(t))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym.SymbolName())
            continue;
         if(PositionGetString(POSITION_COMMENT) == comment)
         {
            ticket = t;
            return true;
         }
      }
      return false;
   }

public:
   CPGATradeExecutor(void) : m_sym(NULL), m_magic(0), m_deviation(10), m_lot(0.01) {}

   void Init(CPGASymbol *sym, const long magic, const ulong deviationPoints, const double lot)
   {
      m_sym = sym;
      m_magic = magic;
      m_deviation = deviationPoints;
      m_lot = lot;

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints((uint)deviationPoints);
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      ApplyFillingMode(sym.SymbolName());
   }

   // Open exactly ONE stage order. Never opens multiple legs.
   bool OpenStageOrder(PGA_Basket &basket, const int stage)
   {
      if(m_sym == NULL)
         return false;
      if(stage < 1 || stage > PGA_LEGS_PER_BASKET)
         return false;

      // CRITICAL: never more than one open order in this sequence
      int liveCount = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong t = PositionGetTicket(i);
         if(t == 0 || !PositionSelectByTicket(t))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym.SymbolName())
            continue;
         ulong id = 0;
         int slot = 0;
         if(!CPGABasketManager::ParseComment(PositionGetString(POSITION_COMMENT), id, slot))
            continue;
         if(id == basket.id)
            liveCount++;
      }
      if(liveCount > 0)
      {
         PGA_LogError("Refusing to open stage " + IntegerToString(stage) +
                      " — sequence already has " + IntegerToString(liveCount) +
                      " open order(s). Max allowed = 1.");
         return false;
      }
      if(basket.activeTicket != 0 && PositionSelectByTicket(basket.activeTicket))
      {
         PGA_LogError("Refusing to open stage " + IntegerToString(stage) +
                      " — activeTicket still open");
         return false;
      }

      string volReason;
      const double volume = m_sym.NormalizeVolume(m_lot);
      if(!m_sym.IsValidVolume(volume, volReason))
      {
         PGA_LogError("Invalid lot size: " + volReason);
         return false;
      }

      const double marketPrice = (basket.direction == PGA_DIR_BUY)
                                 ? SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK)
                                 : SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);

      // TP from THIS order's market entry + configured stage distance
      double tp = 0.0;
      double sl = 0.0;
      double be = 0.0;
      if(basket.direction == PGA_DIR_BUY)
      {
         tp = m_sym.NormalizePrice(marketPrice + basket.tpDistance[stage]);
         sl = (basket.initialSLDistance > 0.0)
              ? m_sym.NormalizePrice(marketPrice - basket.initialSLDistance) : 0.0;
         be = m_sym.NormalizePrice(marketPrice + basket.breakEvenBuffer);
      }
      else
      {
         tp = m_sym.NormalizePrice(marketPrice - basket.tpDistance[stage]);
         sl = (basket.initialSLDistance > 0.0)
              ? m_sym.NormalizePrice(marketPrice + basket.initialSLDistance) : 0.0;
         be = m_sym.NormalizePrice(marketPrice - basket.breakEvenBuffer);
      }

      string stopReason;
      const ENUM_ORDER_TYPE otype = (basket.direction == PGA_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!m_sym.IsStopValid(otype, marketPrice, sl, tp, stopReason))
      {
         PGA_LogError("Stage " + IntegerToString(stage) + " stop validation failed: " + stopReason);
         return false;
      }

      const string comment = CPGABasketManager::BuildComment(basket.id, stage);
      const string dirLabel = (basket.direction == PGA_DIR_BUY) ? "BUY" : "SELL";

      ResetLastError();
      bool ok = false;
      if(basket.direction == PGA_DIR_BUY)
         ok = m_trade.Buy(volume, m_sym.SymbolName(), 0.0, sl, tp, comment);
      else
         ok = m_trade.Sell(volume, m_sym.SymbolName(), 0.0, sl, tp, comment);

      MqlTradeResult result;
      result.retcode = m_trade.ResultRetcode();
      result.deal = m_trade.ResultDeal();
      result.order = m_trade.ResultOrder();
      result.volume = m_trade.ResultVolume();
      result.price = m_trade.ResultPrice();
      result.comment = m_trade.ResultComment();
      result.bid = 0;
      result.ask = 0;
      result.request_id = 0;
      result.retcode_external = 0;

      PGA_LogTradeResult(dirLabel + " #" + IntegerToString(stage) + " open", result);

      if(!ok)
      {
         PGA_LogError("Failed to open " + dirLabel + " #" + IntegerToString(stage));
         return false;
      }

      ulong ticket = 0;
      if(!ResolveTicketByComment(comment, ticket))
         ticket = m_trade.ResultOrder();

      double fillPrice = (result.price > 0.0) ? result.price : marketPrice;
      fillPrice = m_sym.NormalizePrice(fillPrice);

      // Recalculate TP/SL from actual fill if needed (same distances)
      if(basket.direction == PGA_DIR_BUY)
      {
         tp = m_sym.NormalizePrice(fillPrice + basket.tpDistance[stage]);
         sl = (basket.initialSLDistance > 0.0)
              ? m_sym.NormalizePrice(fillPrice - basket.initialSLDistance) : 0.0;
         be = m_sym.NormalizePrice(fillPrice + basket.breakEvenBuffer);
      }
      else
      {
         tp = m_sym.NormalizePrice(fillPrice - basket.tpDistance[stage]);
         sl = (basket.initialSLDistance > 0.0)
              ? m_sym.NormalizePrice(fillPrice + basket.initialSLDistance) : 0.0;
         be = m_sym.NormalizePrice(fillPrice - basket.breakEvenBuffer);
      }

      // Align broker TP/SL to fill-based levels if they differ
      if(ticket != 0 && PositionSelectByTicket(ticket))
      {
         const double curTP = PositionGetDouble(POSITION_TP);
         const double curSL = PositionGetDouble(POSITION_SL);
         if(MathAbs(curTP - tp) > m_sym.Point() * 0.5 || MathAbs(curSL - sl) > m_sym.Point() * 0.5)
         {
            if(!m_trade.PositionModify(ticket, sl, tp))
               PGA_LogWarn("Could not realign SL/TP after fill for stage " + IntegerToString(stage));
         }
      }

      basket.stage = (ENUM_PGA_STAGE)stage;
      basket.activeTicket = ticket;
      basket.activeEntry = fillPrice;
      basket.activeTP = tp;
      basket.activeSL = sl;
      basket.activeBreakEven = be;
      basket.breakEvenApplied = false;
      basket.waitingNextOpen = false;

      basket.legs[stage].ticket = ticket;
      basket.legs[stage].slot = stage;
      basket.legs[stage].entryPrice = fillPrice;
      basket.legs[stage].takeProfit = tp;
      basket.legs[stage].stopLoss = sl;
      basket.legs[stage].opened = true;
      basket.legs[stage].closed = false;

      PGA_LogInfo(dirLabel + " #" + IntegerToString(stage) + " opened" +
                  " entry=" + DoubleToString(fillPrice, m_sym.Digits()) +
                  " TP" + IntegerToString(stage) + "=" + DoubleToString(tp, m_sym.Digits()) +
                  " SL=" + DoubleToString(sl, m_sym.Digits()) +
                  " ticket=" + IntegerToString(ticket) +
                  " [" + CPGABasketManager::StageName(basket.stage) + "]");
      return true;
   }

   bool CloseActiveOrder(PGA_Basket &basket, const string reason)
   {
      const int stage = (int)basket.stage;
      if(stage < 1 || stage > PGA_LEGS_PER_BASKET)
         return false;

      const ulong ticket = basket.activeTicket;
      if(ticket == 0 || !PositionSelectByTicket(ticket))
      {
         basket.legs[stage].closed = true;
         basket.activeTicket = 0;
         return true;
      }

      ResetLastError();
      if(!m_trade.PositionClose(ticket))
      {
         PGA_LogError("Close " + (basket.direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                      " #" + IntegerToString(stage) + " failed (" + reason + ")");
         return false;
      }

      // Confirm closed
      if(PositionSelectByTicket(ticket))
      {
         PGA_LogError("Close requested but position still open ticket=" + IntegerToString(ticket));
         return false;
      }

      basket.legs[stage].closed = true;
      basket.activeTicket = 0;
      PGA_LogInfo((basket.direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                  " #" + IntegerToString(stage) + " closed (" + reason + ")");
      return true;
   }

   bool ModifyActiveSL(PGA_Basket &basket, const double newSL)
   {
      const ulong ticket = basket.activeTicket;
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return false;

      const double tp = PositionGetDouble(POSITION_TP);
      const double curSL = PositionGetDouble(POSITION_SL);
      if(MathAbs(curSL - newSL) < m_sym.Point() * 0.5)
         return true;

      ResetLastError();
      if(!m_trade.PositionModify(ticket, newSL, tp))
      {
         PGA_LogError("Modify SL failed ticket=" + IntegerToString(ticket) +
                      " newSL=" + DoubleToString(newSL, m_sym.Digits()) +
                      " ret=" + PGA_TradeRetcodeDescription(m_trade.ResultRetcode()));
         return false;
      }

      basket.activeSL = newSL;
      return true;
   }
};

#endif // PGA_TRADE_MQH
