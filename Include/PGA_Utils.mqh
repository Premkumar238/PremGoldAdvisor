#ifndef PGA_UTILS_MQH
#define PGA_UTILS_MQH

#include "PGA_Inputs.mqh"

bool PgaIsGoldSymbol(const string symbol)
  {
   string u = symbol;
   StringToUpper(u);
   return (StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0);
  }

double PgaPipSize()
  {
   if(InpPipMode == PIP_MANUAL && InpManualPipSize > 0.0)
      return InpManualPipSize;

   // XAUUSD: treat 1 pip as 0.10 regardless of 2- or 3-digit quotes.
   if(PgaIsGoldSymbol(_Symbol))
      return 0.10;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return 10.0 * _Point;
   return 10.0 * _Point;
  }

double PgaSpreadPoints()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(_Point <= 0.0)
      return 0.0;
   return (ask - bid) / _Point;
  }

double PgaNormalizePrice(const double price)
  {
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

double PgaNormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   lot = MathFloor(lot / step + 1e-12) * step;
   if(lot < minLot)
      lot = minLot;
   if(lot > maxLot)
      lot = maxLot;

   int digits = 2;
   if(step < 0.01)
      digits = 3;
   if(step < 0.001)
      digits = 4;
   return NormalizeDouble(lot, digits);
  }

ENUM_ORDER_TYPE_FILLING PgaFillingMode()
  {
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

int PgaStopsLevelPoints()
  {
   int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(stops, freeze);
  }

bool PgaIsNewBar(datetime &lastBarTime)
  {
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t <= 0)
      return false;
   if(t == lastBarTime)
      return false;
   lastBarTime = t;
   return true;
  }

datetime PgaDayStart(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

string PgaSideText(const long type)
  {
   return (type == POSITION_TYPE_BUY ? "BUY" : "SELL");
  }

#endif
