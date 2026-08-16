#ifndef PGA_RISK_MQH
#define PGA_RISK_MQH

#include "PGA_Inputs.mqh"
#include "PGA_Utils.mqh"
#include "PGA_Indicators.mqh"

double PgaStopDistancePrice()
  {
   return InpSLPips * PgaPipSize();
  }

double PgaTpMultiplier()
  {
   double mult = InpTPAtrMultiplier;
   if(g_adx >= InpAdxStrong)
      mult *= InpTPTrendBoost;
   else if(g_adx < InpAdxRange)
      mult *= InpTPRangeCut;
   return mult;
  }

double PgaTakeProfitDistance()
  {
   if(!InpUseDynamicTP || g_atr <= 0.0)
      return 0.0;
   return PgaTpMultiplier() * g_atr;
  }

double PgaTrailDistance()
  {
   double dist = InpTrailDistanceATR * g_atr;
   return dist;
  }

bool PgaCalcStops(const bool isBuy, const double entry,
                  double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   double stopDist = PgaStopDistancePrice();
   if(stopDist <= 0.0)
      return false;

   int minPoints = PgaStopsLevelPoints();
   double minDist = minPoints * _Point;

   if(isBuy)
     {
      sl = entry - stopDist;
      double tpDist = PgaTakeProfitDistance();
      if(tpDist > 0.0)
         tp = entry + tpDist;
     }
   else
     {
      sl = entry + stopDist;
      double tpDist = PgaTakeProfitDistance();
      if(tpDist > 0.0)
         tp = entry - tpDist;
     }

   if(minDist > 0.0)
     {
      if(isBuy)
        {
         if((entry - sl) < minDist)
            sl = entry - minDist;
         if(tp > 0.0 && (tp - entry) < minDist)
            tp = entry + minDist;
        }
      else
        {
         if((sl - entry) < minDist)
            sl = entry + minDist;
         if(tp > 0.0 && (entry - tp) < minDist)
            tp = entry - minDist;
        }
     }

   sl = PgaNormalizePrice(sl);
   if(tp > 0.0)
      tp = PgaNormalizePrice(tp);
   return true;
  }

double PgaLotFromRisk(const double slDistance)
  {
   if(slDistance <= 0.0)
      return InpFixedLot;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double money    = equity * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickVal <= 0.0)
      return InpFixedLot;

   double ticks = slDistance / tickSize;
   if(ticks <= 0.0)
      return InpFixedLot;

   double lot = money / (ticks * tickVal);
   return PgaNormalizeLot(lot);
  }

double PgaSelectLot(const double slDistance)
  {
   if(InpLotMode == LOT_RISK_PERCENT)
      return PgaLotFromRisk(slDistance);
   return PgaNormalizeLot(InpFixedLot);
  }

bool PgaMarginOk(const ENUM_ORDER_TYPE type, const double lot, const double price, string &reason)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin))
     {
      reason = "OrderCalcMargin failed";
      return false;
     }

   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double need = margin * InpMarginBuffer;
   if(free < need)
     {
      reason = StringFormat("Free margin %.2f < required %.2f", free, need);
      return false;
     }
   return true;
  }

#endif
