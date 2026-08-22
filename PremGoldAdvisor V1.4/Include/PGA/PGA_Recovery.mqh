//+------------------------------------------------------------------+
//| PGA_Recovery.mqh — rebuild sequential state after restart        |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_RECOVERY_MQH
#define PGA_RECOVERY_MQH

#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"
#include "PGA_Basket.mqh"
#include "PGA_Candle.mqh"

class CPGARecovery
{
private:
   CPGASymbol        *m_sym;
   CPGABasketManager *m_baskets;
   CPGACandleEngine  *m_candle;
   double             m_tpDist[6];
   double             m_initialSLDistance;
   double             m_breakEvenBuffer;

public:
   CPGARecovery(void)
      : m_sym(NULL),
        m_baskets(NULL),
        m_candle(NULL),
        m_initialSLDistance(0.0),
        m_breakEvenBuffer(0.0)
   {
      ArrayInitialize(m_tpDist, 0.0);
   }

   void Init(CPGASymbol *sym,
             CPGABasketManager *baskets,
             CPGACandleEngine *candle,
             const double tp1, const double tp2, const double tp3,
             const double tp4, const double tp5,
             const double initialSLDistance,
             const double breakEvenBuffer)
   {
      m_sym = sym;
      m_baskets = baskets;
      m_candle = candle;
      m_tpDist[1] = tp1;
      m_tpDist[2] = tp2;
      m_tpDist[3] = tp3;
      m_tpDist[4] = tp4;
      m_tpDist[5] = tp5;
      m_initialSLDistance = initialSLDistance;
      m_breakEvenBuffer = breakEvenBuffer;
   }

   void Reconstruct(void)
   {
      const long magic = m_baskets.Magic();
      const string symbol = m_baskets.SymbolName();

      PGA_Basket temp[PGA_MAX_BASKETS];
      int tempCount = 0;
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         temp[i].inUse = false;
         temp[i].id = 0;
      }

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         ulong basketId = 0;
         int slot = 0;
         if(!CPGABasketManager::ParseComment(PositionGetString(POSITION_COMMENT), basketId, slot))
         {
            PGA_LogWarn("Open position ticket=" + IntegerToString(ticket) +
                        " has unrecognized comment; skipped for recovery");
            continue;
         }

         int tIdx = -1;
         for(int t = 0; t < tempCount; t++)
         {
            if(temp[t].id == basketId)
            {
               tIdx = t;
               break;
            }
         }

         if(tIdx < 0)
         {
            if(tempCount >= PGA_MAX_BASKETS)
            {
               PGA_LogError("Recovery sequence overflow");
               continue;
            }
            tIdx = tempCount++;
            ZeroMemory(temp[tIdx]);
            temp[tIdx].id = basketId;
            temp[tIdx].inUse = true;
            temp[tIdx].state = PGA_BASKET_ACTIVE;
            temp[tIdx].direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                   ? PGA_DIR_BUY : PGA_DIR_SELL;
            temp[tIdx].candleTime = (datetime)(basketId / 10UL);
            temp[tIdx].triggerEntryLevel = PositionGetDouble(POSITION_PRICE_OPEN);
            temp[tIdx].initialSLDistance = m_initialSLDistance;
            temp[tIdx].breakEvenBuffer = m_breakEvenBuffer;
            temp[tIdx].waitingNextOpen = false;
            temp[tIdx].breakEvenApplied = false;

            for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
            {
               temp[tIdx].tpDistance[s] = m_tpDist[s];
               temp[tIdx].legs[s].slot = s;
               temp[tIdx].legs[s].ticket = 0;
               temp[tIdx].legs[s].closed = true;
               temp[tIdx].legs[s].opened = (s < slot); // prior stages assumed done
               if(s < slot)
               {
                  temp[tIdx].legs[s].opened = true;
                  temp[tIdx].legs[s].closed = true;
               }
            }
         }

         // Sequential mode: only ONE live position expected
         temp[tIdx].stage = (ENUM_PGA_STAGE)slot;
         temp[tIdx].activeTicket = ticket;
         temp[tIdx].activeEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         temp[tIdx].activeTP = PositionGetDouble(POSITION_TP);
         temp[tIdx].activeSL = PositionGetDouble(POSITION_SL);

         if(temp[tIdx].direction == PGA_DIR_BUY)
            temp[tIdx].activeBreakEven = m_sym.NormalizePrice(temp[tIdx].activeEntry + m_breakEvenBuffer);
         else
            temp[tIdx].activeBreakEven = m_sym.NormalizePrice(temp[tIdx].activeEntry - m_breakEvenBuffer);

         if(temp[tIdx].activeTP <= 0.0)
         {
            if(temp[tIdx].direction == PGA_DIR_BUY)
               temp[tIdx].activeTP = m_sym.NormalizePrice(temp[tIdx].activeEntry + m_tpDist[slot]);
            else
               temp[tIdx].activeTP = m_sym.NormalizePrice(temp[tIdx].activeEntry - m_tpDist[slot]);
         }

         temp[tIdx].legs[slot].ticket = ticket;
         temp[tIdx].legs[slot].slot = slot;
         temp[tIdx].legs[slot].entryPrice = temp[tIdx].activeEntry;
         temp[tIdx].legs[slot].takeProfit = temp[tIdx].activeTP;
         temp[tIdx].legs[slot].stopLoss = temp[tIdx].activeSL;
         temp[tIdx].legs[slot].opened = true;
         temp[tIdx].legs[slot].closed = false;
      }

      for(int t = 0; t < tempCount; t++)
      {
         // If somehow multiple opens for same id, keep highest slot and warn
         const int live = m_baskets.CountOpenPositionsForBasket(temp[t].id);
         if(live > 1)
            PGA_LogWarn("Recovery found " + IntegerToString(live) +
                        " open orders for sequence " + IntegerToString((long)temp[t].id) +
                        " (expected max 1)");

         m_baskets.UpsertRecoveredBasket(temp[t]);
         PGA_LogInfo("Recovered sequence id=" + IntegerToString((long)temp[t].id) +
                     " dir=" + (temp[t].direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                     " stage=" + CPGABasketManager::StageName(temp[t].stage) +
                     " ticket=" + IntegerToString(temp[t].activeTicket));
      }

      if(!m_candle.LoadState(magic))
         m_candle.OnNewCandle();

      if(m_candle.HasValidPlan())
      {
         PGA_CandlePlan plan = m_candle.GetPlan();
         for(int t = 0; t < tempCount; t++)
         {
            if(temp[t].candleTime != plan.candleTime)
               continue;
            if(temp[t].direction == PGA_DIR_BUY)
               plan.buyTriggered = true;
            else
               plan.sellTriggered = true;
         }
         m_candle.SetPlan(plan);
         m_candle.SaveState(magic);
      }

      PGA_LogInfo("Recovery complete. Active sequences=" + IntegerToString(m_baskets.CountActive()));
   }
};

#endif // PGA_RECOVERY_MQH
