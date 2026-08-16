#ifndef PGA_FILTERS_MQH
#define PGA_FILTERS_MQH

#include "PGA_Inputs.mqh"
#include "PGA_Utils.mqh"
#include "PGA_Indicators.mqh"
#include "PGA_State.mqh"

int PgaNewsImportanceThreshold()
  {
   if(InpNewsImportance == NEWS_IMP_LOW)
      return (int)CALENDAR_IMPORTANCE_LOW;
   if(InpNewsImportance == NEWS_IMP_MODERATE)
      return (int)CALENDAR_IMPORTANCE_MODERATE;
   return (int)CALENDAR_IMPORTANCE_HIGH;
  }

void PgaSplitCurrencies(string &list[])
  {
   string raw = InpNewsCurrencies;
   StringTrimLeft(raw);
   StringTrimRight(raw);
   if(StringLen(raw) == 0)
      raw = "USD";
   StringReplace(raw, " ", "");
   int n = StringSplit(raw, ',', list);
   if(n <= 0)
     {
      ArrayResize(list, 1);
      list[0] = "USD";
     }
  }

bool PgaNewsWindowBlocks(string &reason)
  {
   datetime now = TimeGMT();
   datetime from = now - (datetime)InpNewsMinutesBefore * 60;
   datetime to   = now + (datetime)InpNewsMinutesAfter * 60;

   string currencies[];
   PgaSplitCurrencies(currencies);

   int threshold = PgaNewsImportanceThreshold();
   bool anyQueryOk = false;

   for(int c = 0; c < ArraySize(currencies); c++)
     {
      MqlCalendarValue values[];
      int n = CalendarValueHistory(values, from, to, NULL, currencies[c]);
      if(n < 0)
         continue;

      anyQueryOk = true;
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent evt;
         if(!CalendarEventById(values[i].event_id, evt))
            continue;
         if((int)evt.importance < threshold)
            continue;

         datetime eventTime = values[i].time;
         reason = StringFormat("News: %s (%s) at %s GMT",
                               evt.name, currencies[c],
                               TimeToString(eventTime, TIME_DATE | TIME_MINUTES));
         return true;
        }
     }

   if(!anyQueryOk)
     {
      if(InpNewsFailMode == NEWS_FAIL_BLOCK)
        {
         reason = "News calendar unavailable";
         return true;
        }
     }
   return false;
  }

bool PgaInSession(string &reason)
  {
   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);

   if(InpUseFridayCutoff && gmt.day_of_week == 5 && gmt.hour >= InpFridayCutoffHourGmt)
     {
      reason = "Friday cutoff";
      return false;
     }
   if(gmt.day_of_week == 6 || gmt.day_of_week == 0)
     {
      reason = "Weekend";
      return false;
     }

   int h = gmt.hour;
   bool london = (h >= InpLondonStartHour && h < InpLondonEndHour);
   bool ny     = (h >= InpNewYorkStartHour && h < InpNewYorkEndHour);
   if(london || ny)
      return true;

   reason = "Outside London/NY session";
   return false;
  }

bool PgaFiltersAllowBuy(string &reason)
  {
   if(InpUseEmaFilter && PgaTrendDirection() <= 0)
     {
      reason = "EMA: price not above trend";
      return false;
     }
   if(InpUseAdxFilter && g_adx < InpAdxMin)
     {
      reason = StringFormat("ADX %.1f < %.1f", g_adx, InpAdxMin);
      return false;
     }
   if(InpUseAtrFilter && g_atr < InpMinAtr)
     {
      reason = StringFormat("ATR %s below minimum", DoubleToString(g_atr, _Digits));
      return false;
     }
   return true;
  }

bool PgaFiltersAllowSell(string &reason)
  {
   if(InpUseEmaFilter && PgaTrendDirection() >= 0)
     {
      reason = "EMA: price not below trend";
      return false;
     }
   if(InpUseAdxFilter && g_adx < InpAdxMin)
     {
      reason = StringFormat("ADX %.1f < %.1f", g_adx, InpAdxMin);
      return false;
     }
   if(InpUseAtrFilter && g_atr < InpMinAtr)
     {
      reason = StringFormat("ATR %s below minimum", DoubleToString(g_atr, _Digits));
      return false;
     }
   return true;
  }

bool PgaCommonFiltersAllow(string &reason)
  {
   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      reason = "Symbol trading disabled";
      return false;
     }

   if(InpUseSpreadFilter)
     {
      double spread = PgaSpreadPoints();
      if(spread > (double)InpMaxSpreadPoints)
        {
         reason = StringFormat("Spread %.1f > %d points", spread, InpMaxSpreadPoints);
         return false;
        }
     }

   if(InpUseSessionFilter && !PgaInSession(reason))
      return false;

   if(InpUseNewsFilter && PgaNewsWindowBlocks(reason))
      return false;

   if(InpCooldownSeconds > 0 && g_lastCloseTime > 0)
     {
      int elapsed = (int)(TimeCurrent() - g_lastCloseTime);
      if(elapsed < InpCooldownSeconds)
        {
         reason = StringFormat("Cooldown %ds remaining", InpCooldownSeconds - elapsed);
         return false;
        }
     }

   if(InpMaxDailyLossPercent > 0.0 && PgaDailyLossPercent() >= InpMaxDailyLossPercent)
     {
      reason = "Daily loss limit reached";
      return false;
     }

   if(InpMaxDrawdownPercent > 0.0 && PgaCurrentDrawdownPercent() >= InpMaxDrawdownPercent)
     {
      reason = "Max drawdown limit reached";
      return false;
     }

   return true;
  }

#endif
