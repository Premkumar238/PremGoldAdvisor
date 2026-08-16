#ifndef PGA_STATE_MQH
#define PGA_STATE_MQH

#include "PGA_Inputs.mqh"
#include "PGA_Logger.mqh"
#include "PGA_Utils.mqh"

#define PGA_GV_PREFIX "PGA_19987_"

datetime g_lastBarTime       = 0;
datetime g_lastCloseTime     = 0;
datetime g_lastSignalBar     = 0;
int      g_lastSignalDir     = 0;     // 1 buy, -1 sell
ulong    g_managedTicket     = 0;
bool     g_trailActive       = false;
double   g_peakEquity        = 0.0;
double   g_dayStartEquity    = 0.0;
datetime g_dayStartStamp     = 0;
string   g_status            = "Initializing";
string   g_blockReason       = "";

string PgaGvName(const string key)
  {
   return PGA_GV_PREFIX + IntegerToString((int)InpMagic) + "_" + _Symbol + "_" + key;
  }

void PgaGvSet(const string key, const double value)
  {
   GlobalVariableSet(PgaGvName(key), value);
  }

double PgaGvGet(const string key, const double fallback = 0.0)
  {
   string name = PgaGvName(key);
   if(!GlobalVariableCheck(name))
      return fallback;
   return GlobalVariableGet(name);
  }

void PgaSaveState()
  {
   PgaGvSet("LastClose", (double)g_lastCloseTime);
   PgaGvSet("LastSigBar", (double)g_lastSignalBar);
   PgaGvSet("LastSigDir", (double)g_lastSignalDir);
   PgaGvSet("Ticket", (double)g_managedTicket);
   PgaGvSet("Trail", g_trailActive ? 1.0 : 0.0);
   PgaGvSet("PeakEq", g_peakEquity);
   PgaGvSet("DayEq", g_dayStartEquity);
   PgaGvSet("DayTs", (double)g_dayStartStamp);
  }

void PgaLoadState()
  {
   g_lastCloseTime  = (datetime)PgaGvGet("LastClose", 0);
   g_lastSignalBar  = (datetime)PgaGvGet("LastSigBar", 0);
   g_lastSignalDir  = (int)PgaGvGet("LastSigDir", 0);
   g_managedTicket  = (ulong)PgaGvGet("Ticket", 0);
   g_trailActive    = (PgaGvGet("Trail", 0) > 0.5);
   g_peakEquity     = PgaGvGet("PeakEq", AccountInfoDouble(ACCOUNT_EQUITY));
   g_dayStartEquity = PgaGvGet("DayEq", AccountInfoDouble(ACCOUNT_EQUITY));
   g_dayStartStamp  = (datetime)PgaGvGet("DayTs", 0);
  }

void PgaResetDayIfNeeded()
  {
   datetime today = PgaDayStart(TimeCurrent());
   if(g_dayStartStamp != today)
     {
      g_dayStartStamp  = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      PgaSaveState();
     }
  }

void PgaUpdatePeakEquity()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peakEquity)
      g_peakEquity = equity;
  }

double PgaCurrentDrawdownPercent()
  {
   if(g_peakEquity <= 0.0)
      return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return (g_peakEquity - equity) / g_peakEquity * 100.0;
  }

double PgaDailyLossPercent()
  {
   if(g_dayStartEquity <= 0.0)
      return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity >= g_dayStartEquity)
      return 0.0;
   return (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
  }

#endif
