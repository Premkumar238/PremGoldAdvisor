//+------------------------------------------------------------------+
//| PGA_Manage.mqh — TP hit detection, break-even, trailing SL       |
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

class CPGAManager
{
private:
   CPGASymbol         *m_sym;
   CPGATradeExecutor  *m_exec;
   CPGABasketManager  *m_baskets;

   double TrailTargetAfterTP(const PGA_Basket &basket, const int tpHit) const
   {
      // After TP1 -> break-even; after TP2 -> TP1; after TP3 -> TP2; after TP4 -> TP3
      if(tpHit <= 0)
         return basket.initialSL;
      if(tpHit == 1)
         return basket.breakEvenPrice;
      if(tpHit >= 2 && tpHit <= 4)
         return basket.tp[tpHit - 1];
      return basket.currentTrailSL;
   }

   void SyncLegClosedFlags(PGA_Basket &basket)
   {
      for(int slot = 1; slot <= PGA_LEGS_PER_BASKET; slot++)
      {
         if(basket.legs[slot].closed)
            continue;
         const ulong ticket = basket.legs[slot].ticket;
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            basket.legs[slot].closed = true;
      }
   }

   bool PriceReachedTP(const PGA_Basket &basket, const int slot) const
   {
      const double tp = basket.tp[slot];
      if(tp <= 0.0)
         return false;

      if(basket.direction == PGA_DIR_BUY)
      {
         const double bid = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);
         return (bid + 1.0e-12 >= tp);
      }
      else
      {
         const double ask = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK);
         return (ask <= tp + 1.0e-12);
      }
   }

   void ApplyTrailToRemaining(PGA_Basket &basket, const int fromSlotInclusive, const double newSL)
   {
      string reason;
      for(int slot = fromSlotInclusive; slot <= PGA_LEGS_PER_BASKET; slot++)
      {
         if(basket.legs[slot].closed)
            continue;
         const ulong ticket = basket.legs[slot].ticket;
         if(ticket == 0 || !PositionSelectByTicket(ticket))
         {
            basket.legs[slot].closed = true;
            continue;
         }

         const ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         const double curSL = PositionGetDouble(POSITION_SL);

         if(!m_sym.CanModifySL(ptype, newSL, curSL, reason))
         {
            // Not an error if already at/better than target
            continue;
         }

         if(m_exec.ModifyLegSL(ticket, newSL))
         {
            PGA_LogInfo("Trail SL updated basket=" + IntegerToString((long)basket.id) +
                        " slot=" + IntegerToString(slot) +
                        " sl=" + DoubleToString(newSL, m_sym.Digits()));
         }
      }

      // Update basket trail only if new SL is strictly more protective
      if(basket.direction == PGA_DIR_BUY)
      {
         if(newSL > basket.currentTrailSL + 1.0e-12 || basket.currentTrailSL <= 0.0)
            basket.currentTrailSL = newSL;
      }
      else
      {
         if(basket.currentTrailSL <= 0.0 || newSL < basket.currentTrailSL - 1.0e-12)
            basket.currentTrailSL = newSL;
      }
   }

public:
   CPGAManager(void) : m_sym(NULL), m_exec(NULL), m_baskets(NULL) {}

   void Init(CPGASymbol *sym, CPGATradeExecutor *exec, CPGABasketManager *baskets)
   {
      m_sym = sym;
      m_exec = exec;
      m_baskets = baskets;
   }

   void ManageBasket(PGA_Basket &basket)
   {
      if(!basket.inUse || basket.state != PGA_BASKET_ACTIVE)
         return;

      SyncLegClosedFlags(basket);

      // Process TP levels in order 1..5
      for(int level = 1; level <= PGA_LEGS_PER_BASKET; level++)
      {
         if(basket.highestTPHit >= level)
            continue;

         const bool priceHit = PriceReachedTP(basket, level);
         const bool legGone  = basket.legs[level].closed;

         // Wait until this TP is touched or the leg has already been closed (broker TP)
         if(!priceHit && !legGone)
            break;

         if(priceHit && !legGone)
            m_exec.CloseLeg(basket, level, "TP" + IntegerToString(level));

         SyncLegClosedFlags(basket);

         // Progress when price touched TP, or leg closed by broker TakeProfit
         if(!priceHit && !basket.legs[level].closed)
            break;

         basket.highestTPHit = level;
         const double trailSL = m_sym.NormalizePrice(TrailTargetAfterTP(basket, level));

         if(level < PGA_LEGS_PER_BASKET)
         {
            PGA_LogInfo("TP" + IntegerToString(level) + " reached basket=" +
                        IntegerToString((long)basket.id) +
                        " -> trail remaining to " + DoubleToString(trailSL, m_sym.Digits()));
            ApplyTrailToRemaining(basket, level + 1, trailSL);
         }
         else
         {
            PGA_LogInfo("TP5 reached basket=" + IntegerToString((long)basket.id));
         }
      }

      SyncLegClosedFlags(basket);
      m_baskets.MarkDoneIfComplete(basket);
      m_baskets.UpdateStored(basket);
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
