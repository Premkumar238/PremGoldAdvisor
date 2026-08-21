//+------------------------------------------------------------------+
//| PGA_Candle.mqh — M5 candle detection and entry levels            |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_CANDLE_MQH
#define PGA_CANDLE_MQH

#include "PGA_Types.mqh"
#include "PGA_Errors.mqh"
#include "PGA_Symbol.mqh"

class CPGACandleEngine
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   PGA_CandlePlan m_plan;
   double         m_buyEntryDistance;
   double         m_sellEntryDistance;
   CPGASymbol    *m_sym;

public:
   CPGACandleEngine(void)
      : m_symbol(""),
        m_tf(PERIOD_M5),
        m_buyEntryDistance(0.0),
        m_sellEntryDistance(0.0),
        m_sym(NULL)
   {
      ZeroMemory(m_plan);
   }

   void Init(CPGASymbol *sym,
             const ENUM_TIMEFRAMES tf,
             const double buyEntryDistance,
             const double sellEntryDistance)
   {
      m_sym = sym;
      m_symbol = (sym != NULL ? sym.SymbolName() : _Symbol);
      m_tf = tf;
      m_buyEntryDistance = buyEntryDistance;
      m_sellEntryDistance = sellEntryDistance;
      ZeroMemory(m_plan);
   }

   bool HasValidPlan(void) const { return m_plan.valid; }
   PGA_CandlePlan GetPlan(void) const { return m_plan; }
   void SetPlan(const PGA_CandlePlan &plan) { m_plan = plan; }

   datetime CurrentCandleTime(void) const
   {
      return iTime(m_symbol, m_tf, 0);
   }

   bool OnNewCandle(void)
   {
      const datetime t = CurrentCandleTime();
      if(t <= 0)
         return false;

      if(m_plan.valid && m_plan.candleTime == t)
         return false;

      const double openPrice = iOpen(m_symbol, m_tf, 0);
      if(openPrice <= 0.0)
      {
         PGA_LogError("Failed to read M5 open price");
         return false;
      }

      m_plan.candleTime = t;
      m_plan.openPrice = (m_sym != NULL) ? m_sym.NormalizePrice(openPrice) : openPrice;
      m_plan.buyEntryLevel = (m_sym != NULL)
                             ? m_sym.NormalizePrice(m_plan.openPrice + m_buyEntryDistance)
                             : m_plan.openPrice + m_buyEntryDistance;
      m_plan.sellEntryLevel = (m_sym != NULL)
                              ? m_sym.NormalizePrice(m_plan.openPrice - m_sellEntryDistance)
                              : m_plan.openPrice - m_sellEntryDistance;
      m_plan.buyTriggered = false;
      m_plan.sellTriggered = false;
      m_plan.valid = true;

      PGA_LogInfo("New M5 candle " + TimeToString(t, TIME_DATE|TIME_MINUTES) +
                  " open=" + DoubleToString(m_plan.openPrice, (m_sym != NULL ? m_sym.Digits() : _Digits)) +
                  " buyLvl=" + DoubleToString(m_plan.buyEntryLevel, (m_sym != NULL ? m_sym.Digits() : _Digits)) +
                  " sellLvl=" + DoubleToString(m_plan.sellEntryLevel, (m_sym != NULL ? m_sym.Digits() : _Digits)));
      return true;
   }

   void MarkBuyTriggered(void)  { m_plan.buyTriggered = true; }
   void MarkSellTriggered(void) { m_plan.sellTriggered = true; }

   void RestoreTriggerFlags(const bool buyTriggered, const bool sellTriggered)
   {
      m_plan.buyTriggered = buyTriggered;
      m_plan.sellTriggered = sellTriggered;
   }

   // Persist candle plan across restarts via GlobalVariables
   void SaveState(const long magic) const
   {
      if(!m_plan.valid)
         return;
      const string key = "PGA14_" + IntegerToString(magic) + "_";
      GlobalVariableSet(key + "candle", (double)m_plan.candleTime);
      GlobalVariableSet(key + "open", m_plan.openPrice);
      GlobalVariableSet(key + "buyLvl", m_plan.buyEntryLevel);
      GlobalVariableSet(key + "sellLvl", m_plan.sellEntryLevel);
      GlobalVariableSet(key + "buyTrig", m_plan.buyTriggered ? 1.0 : 0.0);
      GlobalVariableSet(key + "sellTrig", m_plan.sellTriggered ? 1.0 : 0.0);
   }

   bool LoadState(const long magic)
   {
      const string key = "PGA14_" + IntegerToString(magic) + "_";
      if(!GlobalVariableCheck(key + "candle"))
         return false;

      const datetime saved = (datetime)GlobalVariableGet(key + "candle");
      const datetime nowCandle = CurrentCandleTime();
      if(saved != nowCandle)
         return false;

      m_plan.candleTime = saved;
      m_plan.openPrice = GlobalVariableGet(key + "open");
      m_plan.buyEntryLevel = GlobalVariableGet(key + "buyLvl");
      m_plan.sellEntryLevel = GlobalVariableGet(key + "sellLvl");
      m_plan.buyTriggered = (GlobalVariableGet(key + "buyTrig") > 0.5);
      m_plan.sellTriggered = (GlobalVariableGet(key + "sellTrig") > 0.5);
      m_plan.valid = true;

      PGA_LogInfo("Restored candle plan for " + TimeToString(saved, TIME_DATE|TIME_MINUTES) +
                  " buyTrig=" + (m_plan.buyTriggered ? "Y" : "N") +
                  " sellTrig=" + (m_plan.sellTriggered ? "Y" : "N"));
      return true;
   }
};

#endif // PGA_CANDLE_MQH
