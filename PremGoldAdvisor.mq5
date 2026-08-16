//+------------------------------------------------------------------+
//|                                          PremGoldAdvisor.mq5     |
//|                           PremGoldAdvisor v1.0 for MetaTrader 5  |
//|                                                                  |
//|  XAUUSD M1 advisor with Stochastic entries, optional EMA/ADX/    |
//|  ATR/spread/session/news filters, ATR targets, and ATR trailing. |
//|                                                                  |
//|  This EA does not guarantee profit or a high win rate. Gold on   |
//|  M1 is noisy and conditions change. Evaluate with backtests and  |
//|  forward tests before any live use. Aim: positive expectancy,    |
//|  controlled drawdown, and consistent risk — not promised results.|
//|                                                                  |
//|  Compile in MetaEditor to produce PremGoldAdvisor.ex5.           |
//|  Copy this folder to: MQL5/Experts/PremGoldAdvisor/              |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property link      ""
#property version   "1.00"
#property description "XAUUSD M1 advisor: Stochastic(8,3,3) with modular EMA/ADX/ATR/session/news/spread filters."
#property description "No martingale, grid, averaging, or hedging. One trade at a time. Magic 19987."
#property description "Does not guarantee profit. Backtest and forward-test before live use."

#include "Include/PGA_Inputs.mqh"
#include "Include/PGA_Logger.mqh"
#include "Include/PGA_Utils.mqh"
#include "Include/PGA_State.mqh"
#include "Include/PGA_Indicators.mqh"
#include "Include/PGA_Filters.mqh"
#include "Include/PGA_Risk.mqh"
#include "Include/PGA_Trade.mqh"
#include "Include/PGA_Dashboard.mqh"

int OnInit()
  {
   if(InpFixedLot <= 0.0 && InpLotMode == LOT_FIXED)
     {
      Print("Invalid fixed lot size.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotMode == LOT_RISK_PERCENT && InpRiskPercent <= 0.0)
     {
      Print("Invalid risk percent.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSLPips <= 0.0)
     {
      Print("Stop loss pips must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpStrictSymbol && !PgaIsGoldSymbol(_Symbol))
      PgaLog("Warning: designed for XAUUSD/Gold. Current symbol is " + _Symbol);

   if(InpStrictTimeframe && Period() != PERIOD_M1)
      PgaLog("Warning: designed for M1. Current timeframe is " + EnumToString(Period()));

   if(!PgaIndicatorsInit())
      return INIT_FAILED;

   PgaConfigureTrade();
   PgaLoadState();
   PgaResetDayIfNeeded();
   if(g_peakEquity <= 0.0)
      g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   PgaRecoverOpenPosition();
   g_lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   g_status = "Scanning";
   PgaLog(StringFormat("Initialized on %s %s | pip=%s SL=%s lots=%s magic=%I64u",
                       _Symbol, EnumToString(Period()),
                       DoubleToString(PgaPipSize(), 3),
                       DoubleToString(PgaStopDistancePrice(), _Digits),
                       (InpLotMode == LOT_FIXED ? "fixed" : "risk%"),
                       InpMagic));
   PgaDashboardUpdate();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PgaSaveState();
   PgaIndicatorsRelease();
   PgaUiDelete();
   Comment("");
  }

void OnTick()
  {
   PgaResetDayIfNeeded();
   PgaUpdatePeakEquity();

   if(!PgaIndicatorsUpdate())
     {
      g_status = "Waiting for data";
      PgaDashboardUpdate();
      return;
     }

   bool tradeAllowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
                       (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   if(tradeAllowed)
      PgaManageExits();

   if(!tradeAllowed)
     {
      g_status = "Blocked";
      g_blockReason = "Algo trading disabled";
     }
   else
     {
      bool newBar = PgaIsNewBar(g_lastBarTime);
      if(newBar)
         PgaTryEntries();
      else if(PgaCountOurPositions() == 0 && g_status != "Blocked")
         g_status = "Scanning";
     }

   PgaDashboardUpdate();
   PgaSaveState();
   ChartRedraw(0);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why = "Position close";
   if(reason == DEAL_REASON_SL)
      why = "Stop loss";
   else if(reason == DEAL_REASON_TP)
      why = "Take profit";
   else if(reason == DEAL_REASON_SO)
      why = "Stop out";
   else if(reason == DEAL_REASON_EXPERT)
      why = "EA close";

   if(reason != DEAL_REASON_EXPERT)
      PgaLog(StringFormat("EXIT deal=%I64u profit=%.2f reason=%s", trans.deal, profit, why));

   g_lastCloseTime = TimeCurrent();
   g_managedTicket = 0;
   g_trailActive   = false;
   PgaSaveState();
  }

double OnTester()
  {
   // Custom metric: net profit / (1 + max relative drawdown).
   // Higher is better; still not a promise of live results.
   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(dd < 0.0)
      dd = 0.0;
   return profit / (1.0 + dd);
  }
