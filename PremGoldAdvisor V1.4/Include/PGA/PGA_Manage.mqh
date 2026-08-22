//+------------------------------------------------------------------+
//| PGA_Manage.mqh — sequential TP → close → open next stage         |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_MANAGE_MQH
#define PGA_MANAGE_MQH

#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"
#include "PGA_Basket.mqh"
#include "PGA_Trade.mqh"
#include "PGA_Risk.mqh"

class CPGAManager
{
private:
   CPGASymbol         *m_sym;
   CPGATradeExecutor  *m_exec;
   CPGABasketManager  *m_baskets;
   CPGARisk           *m_risk;

   bool IsActivePositionOpen(const PGA_Basket &basket) const
   {
      if(basket.activeTicket == 0)
         return false;
      return PositionSelectByTicket(basket.activeTicket);
   }

   bool PriceReachedActiveTP(const PGA_Basket &basket) const
   {
      if(basket.activeTP <= 0.0)
         return false;

      if(basket.direction == PGA_DIR_BUY)
      {
         const double bid = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);
         return (bid + 1.0e-12 >= basket.activeTP);
      }

      const double ask = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK);
      return (ask <= basket.activeTP + 1.0e-12);
   }

   void ApplyBreakEvenIfNeeded(PGA_Basket &basket)
   {
      if(basket.breakEvenApplied || basket.breakEvenBuffer <= 0.0)
         return;
      if(!IsActivePositionOpen(basket))
         return;

      bool reached = false;
      if(basket.direction == PGA_DIR_BUY)
      {
         const double bid = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);
         reached = (bid + 1.0e-12 >= basket.activeBreakEven);
      }
      else
      {
         const double ask = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK);
         reached = (ask <= basket.activeBreakEven + 1.0e-12);
      }

      if(!reached)
         return;

      string reason;
      const ENUM_POSITION_TYPE ptype = (basket.direction == PGA_DIR_BUY)
                                       ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      const double curSL = PositionSelectByTicket(basket.activeTicket)
                           ? PositionGetDouble(POSITION_SL) : basket.activeSL;

      if(!m_sym.CanModifySL(ptype, basket.activeBreakEven, curSL, reason))
         return;

      if(m_exec.ModifyActiveSL(basket, basket.activeBreakEven))
      {
         basket.breakEvenApplied = true;
         PGA_LogInfo("Break-even applied on " +
                     (basket.direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                     " #" + IntegerToString((int)basket.stage) +
                     " SL=" + DoubleToString(basket.activeBreakEven, m_sym.Digits()));
      }
   }

   bool WasClosedByTakeProfit(const PGA_Basket &basket, const int stage) const
   {
      const ulong ticket = basket.legs[stage].ticket;
      const double tpLevel = basket.legs[stage].takeProfit > 0.0
                             ? basket.legs[stage].takeProfit
                             : basket.activeTP;

      if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent() + 60))
         return false;

      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         const ulong deal = HistoryDealGetTicket(i);
         if(deal == 0)
            continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != m_baskets.Magic())
            continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_sym.SymbolName())
            continue;

         const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
            continue;

         const ulong dealPosId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(ticket != 0 && dealPosId != 0 && dealPosId != ticket)
            continue;

         const long reason = HistoryDealGetInteger(deal, DEAL_REASON);
         const double closePrice = HistoryDealGetDouble(deal, DEAL_PRICE);

         if(reason == DEAL_REASON_TP)
            return true;

         if(tpLevel > 0.0 && MathAbs(closePrice - tpLevel) <= m_sym.TickSize() * 5.0)
            return true;
      }
      return false;
   }

   // Returns true only when TP event is confirmed AND position is fully closed.
   bool ProcessStageTP(PGA_Basket &basket)
   {
      const int stage = (int)basket.stage;
      if(stage < 1 || stage > PGA_LEGS_PER_BASKET)
         return false;

      const bool open = IsActivePositionOpen(basket);
      const bool priceHit = PriceReachedActiveTP(basket);
      const string dirLabel = (basket.direction == PGA_DIR_BUY) ? "BUY" : "SELL";

      // Still open: close only when price touches TP, then confirm closed
      if(open)
      {
         ApplyBreakEvenIfNeeded(basket);

         if(!priceHit)
            return false;

         PGA_LogInfo("TP" + IntegerToString(stage) + " hit — closing " +
                     dirLabel + " #" + IntegerToString(stage));

         if(!m_exec.CloseActiveOrder(basket, "TP" + IntegerToString(stage)))
            return false;

         if(IsActivePositionOpen(basket))
         {
            PGA_LogError("TP close not confirmed — will not open next stage yet");
            return false;
         }

         PGA_LogInfo("TP" + IntegerToString(stage) + " reached — " +
                     dirLabel + " #" + IntegerToString(stage) + " closed successfully");
         return true;
      }

      // Position already gone (broker TP/SL). Confirm it was a TP before progressing.
      const bool tpConfirmed = priceHit || WasClosedByTakeProfit(basket, stage);

      basket.legs[stage].closed = true;
      basket.activeTicket = 0;

      if(!tpConfirmed)
      {
         PGA_LogWarn(dirLabel + " #" + IntegerToString(stage) +
                     " closed without TP confirmation — sequence stopped");
         m_baskets.MarkComplete(basket);
         return false;
      }

      PGA_LogInfo("TP" + IntegerToString(stage) + " reached — " +
                  dirLabel + " #" + IntegerToString(stage) + " closed successfully");
      return true;
   }

   void OpenNextOrComplete(PGA_Basket &basket)
   {
      const int finishedStage = (int)basket.stage;

      if(finishedStage >= PGA_LEGS_PER_BASKET)
      {
         m_baskets.MarkComplete(basket);
         return;
      }

      // Risk checks before opening next sequential order
      string reason;
      if(m_risk != NULL && !m_risk.IsSpreadOk(reason))
      {
         PGA_LogWarn("Next stage delayed: " + reason);
         basket.waitingNextOpen = true;
         m_baskets.UpdateStored(basket);
         return;
      }

      const int nextStage = finishedStage + 1;
      PGA_LogInfo("Opening " + (basket.direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                  " #" + IntegerToString(nextStage) + " after TP" +
                  IntegerToString(finishedStage));

      if(!m_exec.OpenStageOrder(basket, nextStage))
      {
         PGA_LogError("Failed to open stage " + IntegerToString(nextStage) +
                      " — will retry while sequence active");
         basket.waitingNextOpen = true;
         m_baskets.UpdateStored(basket);
         return;
      }

      basket.waitingNextOpen = false;
      m_baskets.UpdateStored(basket);
   }

public:
   CPGAManager(void) : m_sym(NULL), m_exec(NULL), m_baskets(NULL), m_risk(NULL) {}

   void Init(CPGASymbol *sym, CPGATradeExecutor *exec, CPGABasketManager *baskets, CPGARisk *risk = NULL)
   {
      m_sym = sym;
      m_exec = exec;
      m_baskets = baskets;
      m_risk = risk;
   }

   void ManageBasket(PGA_Basket &basket)
   {
      if(!basket.inUse || basket.state != PGA_BASKET_ACTIVE)
         return;
      if(basket.stage == PGA_STAGE_COMPLETE || basket.stage == PGA_STAGE_NONE)
         return;

      // Retry pending next-stage open (previous TP already confirmed)
      if(basket.waitingNextOpen && !IsActivePositionOpen(basket))
      {
         OpenNextOrComplete(basket);
         return;
      }

      // Wait for current stage TP → close confirmed → open next
      if(!ProcessStageTP(basket))
      {
         m_baskets.UpdateStored(basket);
         return;
      }

      // TP confirmed and position closed — open next stage only now
      OpenNextOrComplete(basket);
   }

   void ManageAll(void)
   {
      for(int i = 0; i < m_baskets.BasketCount(); i++)
      {
         PGA_Basket b;
         if(!m_baskets.GetBasketCopy(i, b))
            continue;
         if(b.state != PGA_BASKET_ACTIVE)
            continue;
         ManageBasket(b);
      }
   }
};

#endif // PGA_MANAGE_MQH
