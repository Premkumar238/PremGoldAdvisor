//+------------------------------------------------------------------+
//| PGA_Risk.mqh — spread, session, basket-limit guards              |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_RISK_MQH
#define PGA_RISK_MQH

#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"

class CPGARisk
{
private:
   CPGASymbol *m_sym;
   double      m_maxSpreadPrice;
   int         m_sessionStartHour;
   int         m_sessionEndHour;
   bool        m_useSessionFilter;
   int         m_maxActiveBaskets;
   bool        m_enableBuy;
   bool        m_enableSell;

public:
   CPGARisk(void)
      : m_sym(NULL),
        m_maxSpreadPrice(0.0),
        m_sessionStartHour(0),
        m_sessionEndHour(23),
        m_useSessionFilter(false),
        m_maxActiveBaskets(10),
        m_enableBuy(true),
        m_enableSell(true) {}

   void Init(CPGASymbol *sym,
             const double maxSpreadPrice,
             const bool useSessionFilter,
             const int sessionStartHour,
             const int sessionEndHour,
             const int maxActiveBaskets,
             const bool enableBuy,
             const bool enableSell)
   {
      m_sym = sym;
      m_maxSpreadPrice = maxSpreadPrice;
      m_useSessionFilter = useSessionFilter;
      m_sessionStartHour = sessionStartHour;
      m_sessionEndHour = sessionEndHour;
      m_maxActiveBaskets = MathMax(1, maxActiveBaskets);
      m_enableBuy = enableBuy;
      m_enableSell = enableSell;
   }

   bool EnableBuy(void)  const { return m_enableBuy; }
   bool EnableSell(void) const { return m_enableSell; }
   int  MaxActiveBaskets(void) const { return m_maxActiveBaskets; }

   double CurrentSpreadPrice(void) const
   {
      if(m_sym == NULL)
         return 0.0;
      const double ask = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_ASK);
      const double bid = SymbolInfoDouble(m_sym.SymbolName(), SYMBOL_BID);
      return ask - bid;
   }

   bool IsSpreadOk(string &reason) const
   {
      if(m_maxSpreadPrice <= 0.0)
         return true;

      const double spread = CurrentSpreadPrice();
      if(spread > m_maxSpreadPrice + 1.0e-12)
      {
         reason = "Spread too wide: " + DoubleToString(spread, m_sym.Digits()) +
                  " > max " + DoubleToString(m_maxSpreadPrice, m_sym.Digits());
         return false;
      }
      return true;
   }

   bool IsInTradingSession(string &reason) const
   {
      if(!m_useSessionFilter)
         return true;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      const int hour = dt.hour;

      bool inside;
      if(m_sessionStartHour <= m_sessionEndHour)
         inside = (hour >= m_sessionStartHour && hour <= m_sessionEndHour);
      else
         inside = (hour >= m_sessionStartHour || hour <= m_sessionEndHour); // overnight window

      if(!inside)
      {
         reason = "Outside trading session (" +
                  IntegerToString(m_sessionStartHour) + "-" +
                  IntegerToString(m_sessionEndHour) + ")";
         return false;
      }
      return true;
   }

   bool CanOpenNewBasket(const int activeBasketCount, string &reason) const
   {
      if(activeBasketCount >= m_maxActiveBaskets)
      {
         reason = "Max active baskets reached (" + IntegerToString(m_maxActiveBaskets) + ")";
         return false;
      }

      string spreadReason;
      if(!IsSpreadOk(spreadReason))
      {
         reason = spreadReason;
         return false;
      }

      string sessionReason;
      if(!IsInTradingSession(sessionReason))
      {
         reason = sessionReason;
         return false;
      }

      return true;
   }
};

#endif // PGA_RISK_MQH
