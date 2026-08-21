//+------------------------------------------------------------------+
//| PGA_Recovery.mqh — rebuild baskets after MT5 / EA restart        |
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

   double TrailAfter(const PGA_Basket &b, const int tpHit) const
   {
      if(tpHit <= 0) return b.initialSL;
      if(tpHit == 1) return b.breakEvenPrice;
      if(tpHit >= 2 && tpHit <= 4) return b.tp[tpHit - 1];
      return b.currentTrailSL;
   }

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

      // Map basketId -> provisional basket
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
               PGA_LogError("Recovery basket overflow");
               continue;
            }
            tIdx = tempCount++;
            ZeroMemory(temp[tIdx]);
            temp[tIdx].id = basketId;
            temp[tIdx].inUse = true;
            temp[tIdx].state = PGA_BASKET_ACTIVE;
            temp[tIdx].direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                   ? PGA_DIR_BUY : PGA_DIR_SELL;
            temp[tIdx].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            temp[tIdx].candleTime = (datetime)(basketId / 10UL); // inverse of MakeBasketId
            temp[tIdx].highestTPHit = 0;

            // Rebuild TP / SL geometry from entry + configured distances
            if(temp[tIdx].direction == PGA_DIR_BUY)
            {
               for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
                  temp[tIdx].tp[s] = m_sym.NormalizePrice(temp[tIdx].entryPrice + m_tpDist[s]);
               temp[tIdx].initialSL = (m_initialSLDistance > 0.0)
                                      ? m_sym.NormalizePrice(temp[tIdx].entryPrice - m_initialSLDistance)
                                      : 0.0;
               temp[tIdx].breakEvenPrice = m_sym.NormalizePrice(temp[tIdx].entryPrice + m_breakEvenBuffer);
            }
            else
            {
               for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
                  temp[tIdx].tp[s] = m_sym.NormalizePrice(temp[tIdx].entryPrice - m_tpDist[s]);
               temp[tIdx].initialSL = (m_initialSLDistance > 0.0)
                                      ? m_sym.NormalizePrice(temp[tIdx].entryPrice + m_initialSLDistance)
                                      : 0.0;
               temp[tIdx].breakEvenPrice = m_sym.NormalizePrice(temp[tIdx].entryPrice - m_breakEvenBuffer);
            }
            temp[tIdx].currentTrailSL = temp[tIdx].initialSL;

            for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
            {
               temp[tIdx].legs[s].slot = s;
               temp[tIdx].legs[s].ticket = 0;
               temp[tIdx].legs[s].takeProfit = temp[tIdx].tp[s];
               temp[tIdx].legs[s].closed = true; // assume closed until found
            }
         }

         temp[tIdx].legs[slot].ticket = ticket;
         temp[tIdx].legs[slot].closed = false;
         temp[tIdx].legs[slot].takeProfit = temp[tIdx].tp[slot];

         // Prefer broker SL if tighter
         const double posSL = PositionGetDouble(POSITION_SL);
         if(posSL > 0.0)
            temp[tIdx].currentTrailSL = posSL;
      }

      // Infer highest TP hit from missing lower slots
      for(int t = 0; t < tempCount; t++)
      {
         int inferred = 0;
         for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
         {
            if(temp[t].legs[s].closed)
               inferred = s;
            else
               break;
         }
         temp[t].highestTPHit = inferred;
         if(inferred > 0)
            temp[t].currentTrailSL = m_sym.NormalizePrice(TrailAfter(temp[t], inferred));

         m_baskets.UpsertRecoveredBasket(temp[t]);
         PGA_LogInfo("Recovered basket id=" + IntegerToString((long)temp[t].id) +
                     " dir=" + (temp[t].direction == PGA_DIR_BUY ? "BUY" : "SELL") +
                     " openLegs=" + IntegerToString(CountOpenLegs(temp[t])) +
                     " highestTP=" + IntegerToString(temp[t].highestTPHit));
      }

      // Restore candle trigger flags from GV and/or recovered baskets
      if(!m_candle.LoadState(magic))
      {
         // Force plan for current candle; triggers inferred from baskets
         m_candle.OnNewCandle();
      }

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

      PGA_LogInfo("Recovery complete. Active baskets=" + IntegerToString(m_baskets.CountActive()));
   }

private:
   int CountOpenLegs(const PGA_Basket &b) const
   {
      int n = 0;
      for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
         if(!b.legs[s].closed) n++;
      return n;
   }
};

#endif // PGA_RECOVERY_MQH
