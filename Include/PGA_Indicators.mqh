#ifndef PGA_INDICATORS_MQH
#define PGA_INDICATORS_MQH

#include "PGA_Inputs.mqh"
#include "PGA_Logger.mqh"

int g_stochHandle = INVALID_HANDLE;
int g_emaHandle   = INVALID_HANDLE;
int g_adxHandle   = INVALID_HANDLE;
int g_atrHandle   = INVALID_HANDLE;

double g_k = 0, g_d = 0, g_kPrev = 0, g_dPrev = 0;
double g_ema = 0, g_adx = 0, g_adxPrev = 0, g_atr = 0;
double g_close1 = 0;

bool PgaIndicatorsInit()
  {
   g_stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   g_emaHandle   = iMA(_Symbol, PERIOD_CURRENT, InpEmaPeriod, 0, MODE_EMA, InpEmaPrice);
   g_adxHandle   = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
   g_atrHandle   = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);

   if(g_stochHandle == INVALID_HANDLE || g_emaHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
     {
      PgaLog("Failed to create indicator handles. error=" + IntegerToString(GetLastError()));
      return false;
     }
   return true;
  }

void PgaIndicatorsRelease()
  {
   if(g_stochHandle != INVALID_HANDLE)
      IndicatorRelease(g_stochHandle);
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   g_stochHandle = INVALID_HANDLE;
   g_emaHandle   = INVALID_HANDLE;
   g_adxHandle   = INVALID_HANDLE;
   g_atrHandle   = INVALID_HANDLE;
  }

bool PgaCopy(const int handle, const int buffer, const int count, double &dest[])
  {
   ArraySetAsSeries(dest, true);
   ResetLastError();
   if(CopyBuffer(handle, buffer, 0, count, dest) < count)
      return false;
   return true;
  }

bool PgaIndicatorsUpdate()
  {
   double k[], d[], ema[], adx[], atr[], close[];
   if(!PgaCopy(g_stochHandle, 0, 3, k))
      return false;
   if(!PgaCopy(g_stochHandle, 1, 3, d))
      return false;
   if(!PgaCopy(g_emaHandle, 0, 3, ema))
      return false;
   if(!PgaCopy(g_adxHandle, 0, 3, adx))
      return false;
   if(!PgaCopy(g_atrHandle, 0, 3, atr))
      return false;

   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3)
      return false;

   // Index 1 = last closed candle (entries wait for close).
   g_k      = k[1];
   g_d      = d[1];
   g_kPrev  = k[2];
   g_dPrev  = d[2];
   g_ema    = ema[1];
   g_adx    = adx[1];
   g_adxPrev= adx[2];
   g_atr    = atr[1];
   g_close1 = close[1];
   return true;
  }

int PgaTrendDirection()
  {
   if(g_close1 > g_ema)
      return 1;
   if(g_close1 < g_ema)
      return -1;
   return 0;
  }

string PgaTrendText()
  {
   int dir = PgaTrendDirection();
   if(dir > 0)
      return "UP (above EMA)";
   if(dir < 0)
      return "DOWN (below EMA)";
   return "FLAT";
  }

bool PgaStochInRange(const double k, const double d, const double lo, const double hi)
  {
   return (k >= lo && k <= hi && d >= lo && d <= hi);
  }

bool PgaBuyCross()
  {
   return (g_kPrev <= g_dPrev && g_k > g_d);
  }

bool PgaSellCross()
  {
   return (g_kPrev >= g_dPrev && g_k < g_d);
  }

bool PgaBuySignal()
  {
   return (PgaStochInRange(g_k, g_d, InpBuyZoneLow, InpBuyZoneHigh) && PgaBuyCross());
  }

bool PgaSellSignal()
  {
   return (PgaStochInRange(g_k, g_d, InpSellZoneLow, InpSellZoneHigh) && PgaSellCross());
  }

bool PgaStochExitBuy()
  {
   return (g_k >= InpExitLevel || g_d >= InpExitLevel);
  }

bool PgaStochExitSell()
  {
   return (g_k <= InpExitLevel || g_d <= InpExitLevel);
  }

bool PgaStochApproachingExit(const long posType)
  {
   if(posType == POSITION_TYPE_BUY)
      return (g_k >= (InpExitLevel - InpTrailTightenStochGap) ||
              g_d >= (InpExitLevel - InpTrailTightenStochGap));
   return (g_k <= (InpExitLevel + InpTrailTightenStochGap) ||
           g_d <= (InpExitLevel + InpTrailTightenStochGap));
  }

bool PgaAdxWeakening()
  {
   return (g_adx < g_adxPrev || g_adx < InpAdxMin);
  }

#endif
