//+------------------------------------------------------------------+
//| PGA_Symbol.mqh — symbol specs, price normalize, stop checks      |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_SYMBOL_MQH
#define PGA_SYMBOL_MQH

#include "PGA_Errors.mqh"

class CPGASymbol
{
private:
   string m_symbol;
   int    m_digits;
   double m_point;
   double m_tickSize;
   double m_tickValue;
   double m_volumeMin;
   double m_volumeMax;
   double m_volumeStep;
   int    m_stopsLevel;
   int    m_freezeLevel;

public:
   CPGASymbol(void) : m_symbol(""), m_digits(0), m_point(0.0), m_tickSize(0.0),
                      m_tickValue(0.0), m_volumeMin(0.0), m_volumeMax(0.0),
                      m_volumeStep(0.0), m_stopsLevel(0), m_freezeLevel(0) {}

   bool Init(const string symbol)
   {
      m_symbol = symbol;
      if(!SymbolSelect(m_symbol, true))
      {
         PGA_LogError("Failed to select symbol: " + m_symbol);
         return false;
      }

      m_digits      = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point       = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tickSize    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_volumeMin   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_volumeMax   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_volumeStep  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stopsLevel  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      if(m_tickSize <= 0.0)
         m_tickSize = m_point;
      if(m_point <= 0.0)
      {
         PGA_LogError("Invalid point size for " + m_symbol);
         return false;
      }

      PGA_LogInfo("Symbol ready: " + m_symbol +
                  " digits=" + IntegerToString(m_digits) +
                  " point=" + DoubleToString(m_point, m_digits) +
                  " tick=" + DoubleToString(m_tickSize, m_digits) +
                  " stops=" + IntegerToString(m_stopsLevel) +
                  " freeze=" + IntegerToString(m_freezeLevel));
      return true;
   }

   string SymbolName(void)   const { return m_symbol; }
   int    Digits(void)       const { return m_digits; }
   double Point(void)        const { return m_point; }
   double TickSize(void)     const { return m_tickSize; }
   double VolumeMin(void)    const { return m_volumeMin; }
   double VolumeMax(void)    const { return m_volumeMax; }
   double VolumeStep(void)   const { return m_volumeStep; }
   int    StopsLevel(void)   const { return m_stopsLevel; }

   double NormalizePrice(const double price) const
   {
      if(m_tickSize <= 0.0)
         return NormalizeDouble(price, m_digits);

      const double ticks = MathRound(price / m_tickSize);
      return NormalizeDouble(ticks * m_tickSize, m_digits);
   }

   double NormalizeVolume(const double volume) const
   {
      if(m_volumeStep <= 0.0)
         return volume;

      double v = MathFloor(volume / m_volumeStep + 1.0e-12) * m_volumeStep;
      v = MathMax(m_volumeMin, MathMin(m_volumeMax, v));
      return NormalizeDouble(v, 8);
   }

   bool IsValidVolume(const double volume, string &reason) const
   {
      const double v = NormalizeVolume(volume);
      if(v < m_volumeMin - 1.0e-12)
      {
         reason = "Volume below minimum (" + DoubleToString(m_volumeMin, 2) + ")";
         return false;
      }
      if(v > m_volumeMax + 1.0e-12)
      {
         reason = "Volume above maximum (" + DoubleToString(m_volumeMax, 2) + ")";
         return false;
      }
      const double steps = (v - m_volumeMin) / m_volumeStep;
      if(MathAbs(steps - MathRound(steps)) > 1.0e-6 && m_volumeStep > 0.0)
      {
         reason = "Volume not aligned to step (" + DoubleToString(m_volumeStep, 2) + ")";
         return false;
      }
      return true;
   }

   double MinStopDistancePrice(void) const
   {
      return (double)m_stopsLevel * m_point;
   }

   bool IsStopValid(const ENUM_ORDER_TYPE orderType,
                    const double price,
                    const double sl,
                    const double tp,
                    string &reason) const
   {
      const double minDist = MinStopDistancePrice();
      const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      if(orderType == ORDER_TYPE_BUY)
      {
         if(sl > 0.0 && (price - sl) < minDist - 1.0e-12)
         {
            reason = "Buy SL too close to price (min=" + DoubleToString(minDist, m_digits) + ")";
            return false;
         }
         if(tp > 0.0 && (tp - price) < minDist - 1.0e-12)
         {
            reason = "Buy TP too close to price (min=" + DoubleToString(minDist, m_digits) + ")";
            return false;
         }
         if(sl > 0.0 && sl >= bid)
         {
            reason = "Buy SL must be below Bid";
            return false;
         }
         if(tp > 0.0 && tp <= ask)
         {
            // Opening market buy: TP must be above market; allow near equality check via minDist above
         }
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         if(sl > 0.0 && (sl - price) < minDist - 1.0e-12)
         {
            reason = "Sell SL too close to price (min=" + DoubleToString(minDist, m_digits) + ")";
            return false;
         }
         if(tp > 0.0 && (price - tp) < minDist - 1.0e-12)
         {
            reason = "Sell TP too close to price (min=" + DoubleToString(minDist, m_digits) + ")";
            return false;
         }
         if(sl > 0.0 && sl <= ask)
         {
            reason = "Sell SL must be above Ask";
            return false;
         }
      }

      return true;
   }

   bool CanModifySL(const ENUM_POSITION_TYPE posType,
                    const double newSL,
                    const double currentSL,
                    string &reason) const
   {
      if(newSL <= 0.0)
      {
         reason = "New SL is zero/disabled";
         return false;
      }

      const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      const double minDist = MinStopDistancePrice();

      if(posType == POSITION_TYPE_BUY)
      {
         if(newSL >= bid - minDist + 1.0e-12)
         {
            reason = "Buy trail SL too close to Bid";
            return false;
         }
         // Only tighten (move up)
         if(currentSL > 0.0 && newSL <= currentSL + 1.0e-12)
         {
            reason = "Buy trail would not improve protection";
            return false;
         }
      }
      else
      {
         if(newSL <= ask + minDist - 1.0e-12)
         {
            reason = "Sell trail SL too close to Ask";
            return false;
         }
         // Only tighten (move down)
         if(currentSL > 0.0 && newSL >= currentSL - 1.0e-12)
         {
            reason = "Sell trail would not improve protection";
            return false;
         }
      }
      return true;
   }
};

#endif // PGA_SYMBOL_MQH
