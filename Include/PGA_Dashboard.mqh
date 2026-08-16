#ifndef PGA_DASHBOARD_MQH
#define PGA_DASHBOARD_MQH

#include "PGA_Inputs.mqh"
#include "PGA_Utils.mqh"
#include "PGA_State.mqh"
#include "PGA_Indicators.mqh"
#include "PGA_Trade.mqh"

#define PGA_PREFIX "PGA_UI_"

color PGA_GOLD     = C'212,175,55';
color PGA_BG       = C'18,18,20';
color PGA_PANEL    = C'28,28,32';
color PGA_TEXT     = C'230,230,230';
color PGA_MUTED    = C'160,160,168';
color PGA_GREEN    = C'46,204,113';
color PGA_RED      = C'231,76,60';
color PGA_LINE     = C'58,58,64';

void PgaUiDelete()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PGA_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

void PgaRect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, border);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

void PgaLabel(const string name, const int x, const int y, const string text,
              const int size, const color clr, const bool bold = false)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial" : "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

bool PgaDealIsOurs(const ulong ticket)
  {
   if(!HistoryDealSelect(ticket))
      return false;
   if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
      return false;
   if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
      return false;
   long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   return (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY);
  }

void PgaCollectStats(const datetime fromTime, int &trades, int &wins, double &profit)
  {
   trades = 0;
   wins   = 0;
   profit = 0.0;
   if(!HistorySelect(fromTime, TimeCurrent()))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || !PgaDealIsOurs(ticket))
         continue;
      double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      trades++;
      profit += p;
      if(p > 0.0)
         wins++;
     }
  }

double PgaFloatingProfit()
  {
   if(!PgaSelectOurPosition())
      return 0.0;
   return PositionGetDouble(POSITION_PROFIT)
        + PositionGetDouble(POSITION_SWAP);
  }

string PgaMoney(const double value)
  {
   return AccountInfoString(ACCOUNT_CURRENCY) + " " + DoubleToString(value, 2);
  }

color PgaSignColor(const double value)
  {
   if(value > 0.0)
      return PGA_GREEN;
   if(value < 0.0)
      return PGA_RED;
   return PGA_TEXT;
  }

void PgaDashboardUpdate()
  {
   if(!InpShowDashboard)
     {
      PgaUiDelete();
      return;
     }

   int x = InpDashboardX;
   int y = InpDashboardY;
   int w = 312;
   int h = 318;

   PgaRect(PGA_PREFIX + "bg", x, y, w, h, PGA_PANEL, PGA_GOLD);
   PgaRect(PGA_PREFIX + "head", x, y, w, 36, PGA_BG, PGA_GOLD);
   PgaLabel(PGA_PREFIX + "title", x + 12, y + 8, "PremGoldAdvisor  v1.0", 11, PGA_GOLD, true);

   int row = y + 46;
   int lx = x + 14;
   int vx = x + 148;
   int step = 18;

   string statusLine = g_status;
   color statusClr = PGA_TEXT;
   if(g_status == "Blocked")
      statusClr = PGA_RED;
   else if(g_status == "In trade" || StringFind(g_status, "position") >= 0)
      statusClr = PGA_GREEN;
   else if(g_status == "Scanning")
      statusClr = PGA_GOLD;

   PgaLabel(PGA_PREFIX + "s1", lx, row, "Status", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v1", vx, row, statusLine, 9, statusClr);
   row += step;

   string reason = g_blockReason;
   if(StringLen(reason) > 34)
      reason = StringSubstr(reason, 0, 34) + "...";
   PgaLabel(PGA_PREFIX + "s2", lx, row, "Filter", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v2", vx, row, (StringLen(reason) == 0 ? "-" : reason), 9, PGA_MUTED);
   row += step;

   int trend = PgaTrendDirection();
   color trendClr = (trend > 0 ? PGA_GREEN : (trend < 0 ? PGA_RED : PGA_TEXT));
   PgaLabel(PGA_PREFIX + "s3", lx, row, "Trend", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v3", vx, row, PgaTrendText(), 9, trendClr);
   row += step;

   PgaLabel(PGA_PREFIX + "s4", lx, row, "ADX(14)", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v4", vx, row, DoubleToString(g_adx, 1) + (g_adx >= InpAdxMin ? "  OK" : "  weak"), 9,
            (g_adx >= InpAdxMin ? PGA_GREEN : PGA_RED));
   row += step;

   PgaLabel(PGA_PREFIX + "s5", lx, row, "Stochastic", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v5", vx, row, StringFormat("K %.1f   D %.1f", g_k, g_d), 9, PGA_TEXT);
   row += step;

   double spread = PgaSpreadPoints();
   PgaLabel(PGA_PREFIX + "s6", lx, row, "Spread", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v6", vx, row, DoubleToString(spread, 1) + " points", 9,
            (!InpUseSpreadFilter || spread <= InpMaxSpreadPoints) ? PGA_GREEN : PGA_RED);
   row += step;

   PgaLabel(PGA_PREFIX + "s7", lx, row, "ATR(14)", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v7", vx, row, DoubleToString(g_atr, _Digits), 9,
            (!InpUseAtrFilter || g_atr >= InpMinAtr) ? PGA_GREEN : PGA_RED);
   row += step;

   double floating = PgaFloatingProfit();
   PgaLabel(PGA_PREFIX + "s8", lx, row, "Current profit", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v8", vx, row, PgaMoney(floating), 9, PgaSignColor(floating));
   row += step;

   int dayTrades = 0, dayWins = 0;
   double dayProfit = 0.0;
   PgaCollectStats(PgaDayStart(TimeCurrent()), dayTrades, dayWins, dayProfit);
   dayProfit += floating;

   PgaLabel(PGA_PREFIX + "s9", lx, row, "Daily profit", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v9", vx, row, PgaMoney(dayProfit), 9, PgaSignColor(dayProfit));
   row += step;

   int lookbackTrades = 0, lookbackWins = 0;
   double lookbackProfit = 0.0;
   datetime from = TimeCurrent() - (datetime)InpStatsLookbackDays * 86400;
   PgaCollectStats(from, lookbackTrades, lookbackWins, lookbackProfit);
   double winRate = (lookbackTrades > 0 ? (100.0 * lookbackWins / lookbackTrades) : 0.0);

   PgaLabel(PGA_PREFIX + "s10", lx, row, "Trades / Win rate", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v10", vx, row,
            IntegerToString(lookbackTrades) + "   " + DoubleToString(winRate, 1) + "%", 9, PGA_TEXT);
   row += step;

   double dd = PgaCurrentDrawdownPercent();
   PgaLabel(PGA_PREFIX + "s11", lx, row, "Drawdown", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v11", vx, row, DoubleToString(dd, 2) + "%", 9, (dd > 0.01 ? PGA_RED : PGA_GREEN));
   row += step;

   PgaLabel(PGA_PREFIX + "s12", lx, row, "Lot mode", 9, PGA_MUTED);
   PgaLabel(PGA_PREFIX + "v12", vx, row,
            (InpLotMode == LOT_FIXED ? "Fixed " + DoubleToString(InpFixedLot, 2)
                                     : "Risk " + DoubleToString(InpRiskPercent, 1) + "%"),
            9, PGA_TEXT);
   row += step;

   PgaLabel(PGA_PREFIX + "foot", lx, y + h - 22,
            _Symbol + "  " + EnumToString(_Period) + "  magic " + IntegerToString((int)InpMagic),
            8, PGA_MUTED);
  }

#endif
