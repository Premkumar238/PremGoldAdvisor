//+------------------------------------------------------------------+
//| PGA_Basket.mqh — basket registry and position tagging            |
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
      b.entryPrice = 0.0;
      b.initialSL = 0.0;
      b.breakEvenPrice = 0.0;
      b.currentTrailSL = 0.0;
      b.highestTPHit = 0;
      b.state = PGA_BASKET_INACTIVE;
      b.inUse = false;
      for(int t = 0; t <= PGA_LEGS_PER_BASKET; t++)
         b.tp[t] = 0.0;
      for(int i = 0; i <= PGA_LEGS_PER_BASKET; i++)
      {
         b.legs[i].ticket = 0;
         b.legs[i].slot = i;
         b.legs[i].takeProfit = 0.0;
         b.legs[i].closed = true;
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
      // Unique per candle + direction
      return (ulong)candleTime * 10UL + (ulong)dir + 1UL;
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

   bool CreateBasket(const datetime candleTime,
                     const ENUM_PGA_DIRECTION dir,
                     const double entryPrice,
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
         PGA_LogError("No free basket slots");
         return false;
      }

      outBasket.id = MakeBasketId(candleTime, dir);
      outBasket.candleTime = candleTime;
      outBasket.direction = dir;
      outBasket.entryPrice = sym.NormalizePrice(entryPrice);
      outBasket.highestTPHit = 0;
      outBasket.state = PGA_BASKET_ACTIVE;
      outBasket.inUse = true;

      if(dir == PGA_DIR_BUY)
      {
         for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
            outBasket.tp[s] = sym.NormalizePrice(outBasket.entryPrice + tpDistances[s]);

         outBasket.initialSL = (initialSLDistance > 0.0)
                               ? sym.NormalizePrice(outBasket.entryPrice - initialSLDistance)
                               : 0.0;
         outBasket.breakEvenPrice = sym.NormalizePrice(outBasket.entryPrice + breakEvenBuffer);
      }
      else
      {
         for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
            outBasket.tp[s] = sym.NormalizePrice(outBasket.entryPrice - tpDistances[s]);

         outBasket.initialSL = (initialSLDistance > 0.0)
                               ? sym.NormalizePrice(outBasket.entryPrice + initialSLDistance)
                               : 0.0;
         outBasket.breakEvenPrice = sym.NormalizePrice(outBasket.entryPrice - breakEvenBuffer);
      }

      outBasket.currentTrailSL = outBasket.initialSL;

      for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
      {
         outBasket.legs[s].slot = s;
         outBasket.legs[s].takeProfit = outBasket.tp[s];
         outBasket.legs[s].ticket = 0;
         outBasket.legs[s].closed = false;
      }

      m_baskets[idx] = outBasket;
      PGA_LogInfo("Basket created id=" + IntegerToString((long)outBasket.id) +
                  " dir=" + (dir == PGA_DIR_BUY ? "BUY" : "SELL") +
                  " entry=" + DoubleToString(outBasket.entryPrice, sym.Digits()) +
                  " initSL=" + DoubleToString(outBasket.initialSL, sym.Digits()) +
                  " BE=" + DoubleToString(outBasket.breakEvenPrice, sym.Digits()));
      return true;
   }

   void UpdateStored(const PGA_Basket &basket)
   {
      const int idx = FindIndexById(basket.id);
      if(idx >= 0)
         m_baskets[idx] = basket;
   }

   void MarkDoneIfComplete(PGA_Basket &basket)
   {
      bool anyOpen = false;
      for(int s = 1; s <= PGA_LEGS_PER_BASKET; s++)
      {
         if(!basket.legs[s].closed)
         {
            anyOpen = true;
            break;
         }
      }
      if(!anyOpen)
      {
         basket.state = PGA_BASKET_DONE;
         PGA_LogInfo("Basket complete id=" + IntegerToString((long)basket.id));
      }
      UpdateStored(basket);
   }

   void ReleaseDoneBaskets(void)
   {
      for(int i = 0; i < PGA_MAX_BASKETS; i++)
      {
         if(m_baskets[i].inUse && m_baskets[i].state == PGA_BASKET_DONE)
         {
            // Keep DONE briefly for duplicate protection within same candle; clear older ones later
         }
      }
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
};

#endif // PGA_BASKET_MQH
