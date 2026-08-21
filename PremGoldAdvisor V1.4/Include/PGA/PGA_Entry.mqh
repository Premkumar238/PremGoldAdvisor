//+------------------------------------------------------------------+
//| PGA_Entry.mqh — touch detection and basket entry orchestration   |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_ENTRY_MQH
#define PGA_ENTRY_MQH

#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"
#include "PGA_Risk.mqh"
#include "PGA_Candle.mqh"
#include "PGA_Basket.mqh"
#include "PGA_Trade.mqh"

class CPGAEntryEngine
{
private:
   CPGASymbol         *m_sym;
   CPGARisk           *m_risk;
   CPGACandleEngine   *m_candle;
   CPGABasketManager  *m_baskets;
   CPGATradeExecutor  *m_exec;
   bool                m_allowBothDirections;
   double              m_tpDist[6];
   double              m_initialSLDistance;
   double              m_breakEvenBuffer;

public:
   CPGAEntryEngine(void)
      : m_sym(NULL),
        m_risk(NULL),
        m_candle(NULL),
        m_baskets(NULL),
        m_exec(NULL),
        m_allowBothDirections(true),
        m_initialSLDistance(0.0),
        m_breakEvenBuffer(0.0)
   {
      ArrayInitialize(m_tpDist, 0.0);
   }

   void Init(CPGASymbol *sym,
             CPGARisk *risk,
             CPGACandleEngine *candle,
             CPGABasketManager *baskets,
             CPGATradeExecutor *exec,
             const bool allowBothDirections,
             const double tp1, const double tp2, const double tp3,
             const double tp4, const double tp5,
             const double initialSLDistance,
             const double breakEvenBuffer)
   {
      m_sym = sym;
      m_risk = risk;
      m_candle = candle;
      m_baskets = baskets;
      m_exec = exec;
      m_allowBothDirections = allowBothDirections;
      m_tpDist[1] = tp1;
      m_tpDist[2] = tp2;
      m_tpDist[3] = tp3;
      m_tpDist[4] = tp4;
      m_tpDist[5] = tp5;
      m_initialSLDistance = initialSLDistance;
      m_breakEvenBuffer = breakEvenBuffer;
   }

   void ProcessTouches(void)
   {
      if(!m_candle.HasValidPlan())
         return;

      PGA_CandlePlan plan = m_candle.GetPlan();
      const double ask = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK);
      const double bid = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);

      // Buy touch: Ask reaches/crosses buy entry level
      if(m_risk.EnableBuy() && !plan.buyTriggered)
      {
         if(ask + 1.0e-12 >= plan.buyEntryLevel)
         {
            if(CanTriggerDirection(PGA_DIR_BUY, plan))
            {
               TryOpen(PGA_DIR_BUY, plan.buyEntryLevel, plan);
               m_candle.SetPlan(plan);
               return; // refresh plan next tick after state change
            }
         }
      }

      // Sell touch: Bid reaches/crosses sell entry level
      if(m_risk.EnableSell() && !plan.sellTriggered)
      {
         if(bid <= plan.sellEntryLevel + 1.0e-12)
         {
            if(CanTriggerDirection(PGA_DIR_SELL, plan))
            {
               TryOpen(PGA_DIR_SELL, plan.sellEntryLevel, plan);
               m_candle.SetPlan(plan);
            }
         }
      }
   }

private:
   bool CanTriggerDirection(const ENUM_PGA_DIRECTION dir, const PGA_CandlePlan &plan) const
   {
      if(!m_allowBothDirections)
      {
         if(dir == PGA_DIR_BUY && plan.sellTriggered)
         {
            PGA_LogInfo("Buy blocked: opposite side already triggered (AllowBothDirections=false)");
            return false;
         }
         if(dir == PGA_DIR_SELL && plan.buyTriggered)
         {
            PGA_LogInfo("Sell blocked: opposite side already triggered (AllowBothDirections=false)");
            return false;
         }
      }

      // One basket per direction per candle
      if(m_baskets.HasActiveBasketForCandle(plan.candleTime, dir))
      {
         PGA_LogWarn("Duplicate basket prevented for candle direction");
         return false;
      }

      string reason;
      if(!m_risk.CanOpenNewBasket(m_baskets.CountActive(), reason))
      {
         PGA_LogWarn("Entry blocked: " + reason);
         return false;
      }
      return true;
   }

   void TryOpen(const ENUM_PGA_DIRECTION dir, const double entryLevel, PGA_CandlePlan &plan)
   {
      // Mark trigger immediately to enforce one-shot per candle/direction
      if(dir == PGA_DIR_BUY)
      {
         plan.buyTriggered = true;
         m_candle.MarkBuyTriggered();
      }
      else
      {
         plan.sellTriggered = true;
         m_candle.MarkSellTriggered();
      }
      m_candle.SaveState(m_baskets.Magic());

      PGA_LogInfo((dir == PGA_DIR_BUY ? "BUY" : "SELL") +
                  " entry level touched @ " +
                  DoubleToString(entryLevel, m_sym.Digits()) +
                  " market Ask=" + DoubleToString(SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK), m_sym.Digits()) +
                  " Bid=" + DoubleToString(SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID), m_sym.Digits()));

      PGA_Basket basket;
      if(!m_baskets.CreateBasket(plan.candleTime, dir, entryLevel, m_tpDist,
                                 m_initialSLDistance, m_breakEvenBuffer, *m_sym, basket))
      {
         PGA_LogError("Failed to create basket structure");
         return;
      }

      if(!m_exec.OpenBasketPositions(basket))
      {
         PGA_LogError("Basket open failed id=" + IntegerToString((long)basket.id));
         // Keep trigger flag true to avoid repeated attempts on same candle after hard failures.
         // Remove empty basket slot.
         basket.state = PGA_BASKET_DONE;
         basket.inUse = true;
         m_baskets.UpdateStored(basket);
         return;
      }

      m_baskets.UpdateStored(basket);
   }
};

#endif // PGA_ENTRY_MQH
