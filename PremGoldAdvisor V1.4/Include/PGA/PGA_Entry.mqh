//+------------------------------------------------------------------+
//| PGA_Entry.mqh — entry touch opens STAGE_1 only                   |
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

      if(m_risk.EnableBuy() && !plan.buyTriggered)
      {
         if(ask + 1.0e-12 >= plan.buyEntryLevel)
         {
            if(CanTriggerDirection(PGA_DIR_BUY, plan))
            {
               TryStartSequence(PGA_DIR_BUY, plan.buyEntryLevel, plan);
               m_candle.SetPlan(plan);
               return;
            }
         }
      }

      if(m_risk.EnableSell() && !plan.sellTriggered)
      {
         if(bid <= plan.sellEntryLevel + 1.0e-12)
         {
            if(CanTriggerDirection(PGA_DIR_SELL, plan))
            {
               TryStartSequence(PGA_DIR_SELL, plan.sellEntryLevel, plan);
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

      if(m_baskets.HasActiveBasketForCandle(plan.candleTime, dir))
      {
         PGA_LogWarn("Duplicate sequence prevented for candle direction");
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

   void TryStartSequence(const ENUM_PGA_DIRECTION dir, const double entryLevel, PGA_CandlePlan &plan)
   {
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

      const string dirLabel = (dir == PGA_DIR_BUY) ? "BUY" : "SELL";
      PGA_LogInfo(dirLabel + " entry level touched @ " +
                  DoubleToString(entryLevel, m_sym.Digits()) +
                  " → opening " + dirLabel + " #1 ONLY (sequential mode)");

      PGA_Basket basket;
      if(!m_baskets.CreateSequence(plan.candleTime, dir, entryLevel, m_tpDist,
                                   m_initialSLDistance, m_breakEvenBuffer, *m_sym, basket))
      {
         PGA_LogError("Failed to create sequence structure");
         return;
      }

      // Open STAGE 1 only — never loop 1..5
      if(!m_exec.OpenStageOrder(basket, 1))
      {
         PGA_LogError("Failed to open " + dirLabel + " #1");
         basket.state = PGA_BASKET_DONE;
         basket.stage = PGA_STAGE_COMPLETE;
         basket.inUse = true;
         m_baskets.UpdateStored(basket);
         return;
      }

      m_baskets.UpdateStored(basket);
   }
};

#endif // PGA_ENTRY_MQH
