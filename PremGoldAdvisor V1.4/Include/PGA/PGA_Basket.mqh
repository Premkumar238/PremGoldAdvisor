//+------------------------------------------------------------------+
//| PGA_Basket.mqh — sequential sequence registry                    |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_BASKET_MQH
#define PGA_BASKET_MQH

#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"

class CPGABasketManager
{
private:
   PGA_Basket m_baskets[PGA_MAX_BASKETS];
   long       m_magic;
   string     m_symbol;

   void ClearBasket(PGA_Basket &b)
   {
      b.id = 0;
      b.candleTime = 0;
      b.direction = PGA_DIR_BUY;
      b.triggerEntryLevel = 0.0;
      b.initialSLDistance = 0.0;
      b.breakEvenBuffer = 0.0;
      b.stage = PGA_STAGE_NONE;
      b.activeTicket = 0;
      b.activeEntry = 0.0;
      b.activeTP = 0.0;
      b.activeSL = 0.0;
      b.activeBreakEven = 0.0;
      b.breakEvenApplied = false;
      b.waitingNextOpen = false;
      b.state = PGA_BASKET_INACTIVE;
      b.inUse = false;
      for(int t = 0; t <= PGA_LEGS_PER_BASKET; t++)
         b.tpDistance[t] = 0.0;
      for(int i = 0; i <= PGA_LEGS_PER_BASKET; i++)
      {
         b.legs[i].ticket = 0;
         b.legs[i].slot = i;
         b.legs[i].entryPrice = 0.0;
         b.legs[i].takeProfit = 0.0;
         b.legs[i].stopLoss = 0.0;
         b.legs[i].closed = true;
         b.legs[i].opened = false;
      }
   }

public:
   CPGABasketManager(void) : m_magic(0), m_symbol("")
   {
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
         ClearBasket(m_baskets[i]);
   }

   void Init(const string symbol, const long magic)
   {
      m_symbol = symbol;
      m_magic = magic;
   }

   long Magic(void) const { return m_magic; }
   string SymbolName(void) const { return m_symbol; }

   static string BuildComment(const ulong basketId, const int slot)
   {
      return PGA_COMMENT_PREFIX + "|" + IntegerToString((long)basketId) + "|" + IntegerToString(slot);
   }

   static bool ParseComment(const string comment, ulong &basketId, int &slot)
   {
      basketId = 0;
      slot = 0;
      string parts[];
      const int n = StringSplit(comment, '|', parts);
      if(n < 3)
         return false;
      if(parts[0] != PGA_COMMENT_PREFIX)
         return false;
      basketId = (ulong)StringToInteger(parts[1]);
      slot = (int)StringToInteger(parts[2]);
      if(slot < 1 || slot > PGA_LEGS_PER_BASKET || basketId == 0)
         return false;
      return true;
   }

   static ulong MakeBasketId(const datetime candleTime, const ENUM_PGA_DIRECTION dir)
   {
      return (ulong)candleTime * 10UL + (ulong)dir + 1UL;
   }

   static string StageName(const ENUM_PGA_STAGE stage)
   {
      switch(stage)
      {
         case PGA_STAGE_1:        return "STAGE_1";
         case PGA_STAGE_2:        return "STAGE_2";
         case PGA_STAGE_3:        return "STAGE_3";
         case PGA_STAGE_4:        return "STAGE_4";
         case PGA_STAGE_5:        return "STAGE_5";
         case PGA_STAGE_COMPLETE: return "COMPLETE";
         default:                 return "NONE";
      }
   }

   int FindIndexById(const ulong basketId) const
   {
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         if(m_baskets[i].inUse && m_baskets[i].id == basketId)
            return i;
      }
      return -1;
   }

   int AllocateSlot(void)
   {
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         if(!m_baskets[i].inUse)
            return i;
      }
      return -1;
   }

   int CountActive(void) const
   {
      int count = 0;
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         if(m_baskets[i].inUse && m_baskets[i].state == PGA_BASKET_ACTIVE)
            count++;
      }
      return count;
   }

   bool HasActiveBasketForCandle(const datetime candleTime, const ENUM_PGA_DIRECTION dir) const
   {
      const ulong id = MakeBasketId(candleTime, dir);
      const int idx = FindIndexById(id);
      if(idx < 0)
         return false;
      return (m_baskets[idx].state == PGA_BASKET_ACTIVE || m_baskets[idx].state == PGA_BASKET_DONE);
   }

   // Create sequence shell only — does NOT open any orders.
   bool CreateSequence(const datetime candleTime,
                       const ENUM_PGA_DIRECTION dir,
                       const double triggerLevel,
                       const double &tpDistances[],
                       const double initialSLDistance,
                       const double breakEvenBuffer,
                       const CPGASymbol &sym,
                       PGA_Basket &outBasket)
   {
      ClearBasket(outBasket);

      const int idx = AllocateSlot();
      if(idx < 0)
      {
         PGA_LogError("No free sequence slots");
         return false;
      }

      outBasket.id = MakeBasketId(candleTime, dir);
      outBasket.candleTime = candleTime;
      outBasket.direction = dir;
      outBasket.triggerEntryLevel = sym.NormalizePrice(triggerLevel);
      outBasket.initialSLDistance = initialSLDistance;
      outBasket.breakEvenBuffer = breakEvenBuffer;
      outBasket.stage = PGA_STAGE_NONE;
      outBasket.activeTicket = 0;
      outBasket.waitingNextOpen = false;
      outBasket.breakEvenApplied = false;
      outBasket.state = PGA_BASKET_ACTIVE;
      outBasket.inUse = true;

      for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
      {
         outBasket.tpDistance[s] = tpDistances[s];
         outBasket.legs[s].slot = s;
         outBasket.legs[s].closed = true;
         outBasket.legs[s].opened = false;
         outBasket.legs[s].ticket = 0;
      }

      m_baskets[idx] = outBasket;
      PGA_LogInfo("Sequence created id=" + IntegerToString((long)outBasket.id) +
                  " dir=" + (dir == PGA_DIR_BUY ? "BUY" : "SELL") +
                  " trigger=" + DoubleToString(outBasket.triggerEntryLevel, sym.Digits()) +
                  " mode=SEQUENTIAL (max 1 open order)");
      return true;
   }

   void UpdateStored(const PGA_Basket &basket)
   {
      const int idx = FindIndexById(basket.id);
      if(idx >= 0)
         m_baskets[idx] = basket;
   }

   void MarkComplete(PGA_Basket &basket)
   {
      basket.stage = PGA_STAGE_COMPLETE;
      basket.state = PGA_BASKET_DONE;
      basket.activeTicket = 0;
      basket.waitingNextOpen = false;
      PGA_LogInfo((basket.direction == PGA_DIR_BUY ? "Buy" : "Sell") +
                  " sequence complete id=" + IntegerToString((long)basket.id));
      UpdateStored(basket);
   }

   void ClearFinishedExceptCurrentCandle(const datetime currentCandle)
   {
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         if(!m_baskets[i].inUse)
            continue;
         if(m_baskets[i].state == PGA_BASKET_DONE && m_baskets[i].candleTime != currentCandle)
            ClearBasket(m_baskets[i]);
      }
   }

   bool UpsertRecoveredBasket(const PGA_Basket &basket)
   {
      int idx = FindIndexById(basket.id);
      if(idx < 0)
         idx = AllocateSlot();
      if(idx < 0)
         return false;
      m_baskets[idx] = basket;
      return true;
   }

   int BasketCount(void) const { return PGA_MAX_BASKETS; }

   bool GetBasketCopy(const int index, PGA_Basket &out) const
   {
      if(index < 0 || index >= PGA_MAX_BASKETS)
         return false;
      out = m_baskets[index];
      return out.inUse;
   }

   // Count currently open EA positions for this sequence (must be 0 or 1)
   int CountOpenPositionsForBasket(const ulong basketId) const
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong t = PositionGetTicket(i);
         if(t == 0 || !PositionSelectByTicket(t))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         ulong id = 0;
         int slot = 0;
         if(!ParseComment(PositionGetString(POSITION_COMMENT), id, slot))
            continue;
         if(id == basketId)
            n++;
      }
      return n;
   }
};

#endif // PGA_BASKET_MQH
