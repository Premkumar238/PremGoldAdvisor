//+------------------------------------------------------------------+
//| PGA_Trade.mqh — market order execution for basket legs           |
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
      m_trade.SetTypeFillingBySymbol(sym.SymbolName());
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   bool OpenBasketPositions(PGA_Basket &basket)
   {
      if(m_sym == NULL)
         return false;

      string volReason;
      const double volume = m_sym.NormalizeVolume(m_lot);
      if(!m_sym.IsValidVolume(volume, volReason))
      {
         PGA_LogError("Invalid lot size: " + volReason);
         return false;
      }

      int opened = 0;
      for(int slot = 1; slot <= PGA_LEGS_PER_BASKET; slot++)
      {
         const string comment = CPGABasketManager::BuildComment(basket.id, slot);
         const double tp = basket.tp[slot];
         const double sl = basket.initialSL;

         string stopReason;
         const ENUM_ORDER_TYPE otype = (basket.direction == PGA_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         const double price = (basket.direction == PGA_DIR_BUY)
                              ? SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK)
                              : SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);

         // Validate stops against market
         if(!m_sym.IsStopValid(otype, price, sl, tp, stopReason))
         {
            PGA_LogError("Slot " + IntegerToString(slot) + " stop validation failed: " + stopReason);
            // Continue attempting remaining slots only if none opened yet? Prefer abort cleanly.
            if(opened == 0)
               return false;
            continue;
         }

         bool ok = false;
         ResetLastError();
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

         PGA_LogTradeResult((basket.direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                            " slot " + IntegerToString(slot), result);

         if(!ok)
         {
            PGA_LogError("Failed to open slot " + IntegerToString(slot));
            continue;
         }

         ulong ticket = 0;
         if(!ResolveTicketByComment(comment, ticket))
         {
            // Fallback: use deal -> position
            ticket = m_trade.ResultOrder();
         }

         basket.legs[slot].ticket = ticket;
         basket.legs[slot].closed = false;
         basket.legs[slot].takeProfit = tp;
         opened++;
         // Keep planned entryPrice for TP/BE geometry; fills may slip slightly.
      }

      if(opened == 0)
      {
         PGA_LogError("No legs opened for basket " + IntegerToString((long)basket.id));
         basket.state = PGA_BASKET_INACTIVE;
         basket.inUse = false;
         return false;
      }

      if(opened < PGA_LEGS_PER_BASKET)
         PGA_LogWarn("Partial basket open: " + IntegerToString(opened) + "/" +
                     IntegerToString(PGA_LEGS_PER_BASKET) + " legs");

      // Mark unopened legs as closed so trailing logic ignores them
      for(int slot = 1; slot <= PGA_LEGS_PER_BASKET; slot++)
      {
         if(basket.legs[slot].ticket == 0)
            basket.legs[slot].closed = true;
      }

      return true;
   }

   bool CloseLeg(PGA_Basket &basket, const int slot, const string reason)
   {
      if(slot < 1 || slot > PGA_LEGS_PER_BASKET)
         return false;
      if(basket.legs[slot].closed)
         return true;

      const ulong ticket = basket.legs[slot].ticket;
      if(ticket == 0 || !PositionSelectByTicket(ticket))
      {
         basket.legs[slot].closed = true;
         return true;
      }

      ResetLastError();
      const bool ok = m_trade.PositionClose(ticket);
      if(!ok)
      {
         PGA_LogError("Close leg " + IntegerToString(slot) + " failed (" + reason + ")");
         return false;
      }

      basket.legs[slot].closed = true;
      PGA_LogInfo("Closed leg " + IntegerToString(slot) + " basket=" +
                  IntegerToString((long)basket.id) + " reason=" + reason);
      return true;
   }

   bool ModifyLegSL(const ulong ticket, const double newSL)
   {
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
      return true;
   }

private:
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
};

#endif // PGA_TRADE_MQH
