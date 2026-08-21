//+------------------------------------------------------------------+
//|                                      PremGoldAdvisorV1.4.mq5     |
//| PremGoldAdvisor V1.4 — XAUUSD M5 multi-TP basket EA              |
//| Built from zero for V1.4 (not derived from V1.3 source).         |
//|                                                                  |
//| DISCLAIMER: For testing and risk management only.                |
//| No profitability is guaranteed. Backtest thoroughly with         |
//| realistic spread, commission and slippage before live use.       |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property link      ""
#property version   "1.40"
#property description "PremGoldAdvisor V1.4 — XAUUSD M5 entry-level basket EA"
#property description "NOT financial advice. No guaranteed profits. Backtest first."
#property strict

#include "Include/PGA/PGA_Types.mqh"
#include "Include/PGA/PGA_Errors.mqh"
#include "Include/PGA/PGA_Symbol.mqh"
#include "Include/PGA/PGA_Risk.mqh"
#include "Include/PGA/PGA_Basket.mqh"
#include "Include/PGA/PGA_Candle.mqh"
#include "Include/PGA/PGA_Trade.mqh"
#include "Include/PGA/PGA_Manage.mqh"
#include "Include/PGA/PGA_Entry.mqh"
#include "Include/PGA/PGA_Recovery.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General ==="
input string            InpTradeSymbol        = "XAUUSD";           // Trade symbol (empty = chart symbol)
input ENUM_TIMEFRAMES   InpTimeframe          = PERIOD_M5;          // Working timeframe
input long              InpMagicNumber        = 140001;             // Magic number
input double            InpLotSize            = 0.01;               // Lot size per order
input ulong             InpMaxSlippagePoints  = 30;                 // Max slippage (points)
input bool              InpAllowBothDirections= true;               // Allow buy+sell same candle
input int               InpMaxActiveBaskets   = 6;                  // Max active baskets
input bool              InpEnableBuy          = true;               // Enable Buy baskets
input bool              InpEnableSell         = true;               // Enable Sell baskets

input group "=== Entry Distances (price units) ==="
input double            InpBuyEntryDistance   = 2.00;               // Buy entry above candle open
input double            InpSellEntryDistance  = 2.00;               // Sell entry below candle open

input group "=== Take Profit Distances (price units from entry) ==="
input double            InpTP1Distance        = 1.00;               // TP1 distance
input double            InpTP2Distance        = 2.00;               // TP2 distance
input double            InpTP3Distance        = 3.00;               // TP3 distance
input double            InpTP4Distance        = 4.00;               // TP4 distance
input double            InpTP5Distance        = 5.00;               // TP5 distance

input group "=== Stop Loss / Break-Even ==="
input double            InpInitialSLDistance  = 5.00;               // Initial SL distance (0 = disabled)
input double            InpBreakEvenBuffer    = 0.10;               // Break-even buffer after TP1

input group "=== Risk Filters ==="
input double            InpMaxSpread          = 0.50;               // Max spread (price); 0 = off
input bool              InpUseSessionFilter   = false;              // Enable session filter
input int               InpSessionStartHour   = 1;                  // Session start hour (server)
input int               InpSessionEndHour     = 23;                 // Session end hour (server)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CPGASymbol         g_symbol;
CPGARisk           g_risk;
CPGABasketManager  g_baskets;
CPGACandleEngine   g_candle;
CPGATradeExecutor  g_exec;
CPGAManager        g_manager;
CPGAEntryEngine    g_entry;
CPGARecovery       g_recovery;

string             g_symbolName;

//+------------------------------------------------------------------+
//| Validate inputs                                                  |
//+------------------------------------------------------------------+
bool PGA_ValidateInputs(void)
{
   if(InpTimeframe != PERIOD_M5)
      PGA_LogWarn("Designed for M5. Current InpTimeframe=" + EnumToString(InpTimeframe));

   if(InpLotSize <= 0.0)
   {
      PGA_LogError("Lot size must be > 0");
      return false;
   }
   if(InpBuyEntryDistance < 0.0 || InpSellEntryDistance < 0.0)
   {
      PGA_LogError("Entry distances must be >= 0");
      return false;
   }
   if(InpTP1Distance <= 0.0 || InpTP2Distance <= InpTP1Distance ||
      InpTP3Distance <= InpTP2Distance || InpTP4Distance <= InpTP3Distance ||
      InpTP5Distance <= InpTP4Distance)
   {
      PGA_LogError("TP distances must be strictly increasing: TP1 < TP2 < TP3 < TP4 < TP5");
      return false;
   }
   if(InpInitialSLDistance < 0.0)
   {
      PGA_LogError("Initial SL distance cannot be negative");
      return false;
   }
   if(InpBreakEvenBuffer < 0.0)
   {
      PGA_LogError("Break-even buffer cannot be negative");
      return false;
   }
   if(InpMaxActiveBaskets < 1)
   {
      PGA_LogError("Max active baskets must be >= 1");
      return false;
   }
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23)
   {
      PGA_LogError("Session hours must be 0..23");
      return false;
   }
   if(!InpEnableBuy && !InpEnableSell)
   {
      PGA_LogError("Both Buy and Sell are disabled");
      return false;
   }

   if(InpInitialSLDistance == 0.0)
   {
      PGA_LogWarn("======================================================");
      PGA_LogWarn("WARNING: InitialSL = 0 — INITIAL STOP LOSS DISABLED.");
      PGA_LogWarn("Potential loss is UNLIMITED until TP1 trailing starts.");
      PGA_LogWarn("======================================================");
   }

   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   PGA_LogInfo("Initializing PremGoldAdvisor V1.4");
   PGA_LogInfo("Disclaimer: testing/risk-management tool only — no guaranteed profit.");

   if(!PGA_ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_symbolName = InpTradeSymbol;
   StringTrimLeft(g_symbolName);
   StringTrimRight(g_symbolName);
   if(StringLen(g_symbolName) == 0)
      g_symbolName = _Symbol;

   if(!g_symbol.Init(g_symbolName))
      return INIT_FAILED;

   string volReason;
   if(!g_symbol.IsValidVolume(InpLotSize, volReason))
   {
      PGA_LogError(volReason);
      return INIT_PARAMETERS_INCORRECT;
   }

   g_risk.Init(&g_symbol,
               InpMaxSpread,
               InpUseSessionFilter,
               InpSessionStartHour,
               InpSessionEndHour,
               InpMaxActiveBaskets,
               InpEnableBuy,
               InpEnableSell);

   g_baskets.Init(g_symbolName, InpMagicNumber);
   g_candle.Init(&g_symbol, InpTimeframe, InpBuyEntryDistance, InpSellEntryDistance);
   g_exec.Init(&g_symbol, InpMagicNumber, InpMaxSlippagePoints, InpLotSize);
   g_manager.Init(&g_symbol, &g_exec, &g_baskets);
   g_entry.Init(&g_symbol, &g_risk, &g_candle, &g_baskets, &g_exec,
                InpAllowBothDirections,
                InpTP1Distance, InpTP2Distance, InpTP3Distance,
                InpTP4Distance, InpTP5Distance,
                InpInitialSLDistance, InpBreakEvenBuffer);
   g_recovery.Init(&g_symbol, &g_baskets, &g_candle,
                   InpTP1Distance, InpTP2Distance, InpTP3Distance,
                   InpTP4Distance, InpTP5Distance,
                   InpInitialSLDistance, InpBreakEvenBuffer);

   // Reconstruct open baskets / candle flags after restart
   g_recovery.Reconstruct();

   if(!g_candle.HasValidPlan())
      g_candle.OnNewCandle();

   g_candle.SaveState(InpMagicNumber);

   PGA_LogInfo("PremGoldAdvisor V1.4 ready on " + g_symbolName +
               " TF=" + EnumToString(InpTimeframe) +
               " magic=" + IntegerToString(InpMagicNumber));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_candle.SaveState(InpMagicNumber);
   PGA_LogInfo("Deinitialized. Reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1) New M5 candle → reset triggers and recalculate entry levels
   if(g_candle.OnNewCandle())
   {
      g_baskets.ClearFinishedExceptCurrentCandle(g_candle.CurrentCandleTime());
      g_candle.SaveState(InpMagicNumber);
   }

   if(!g_candle.HasValidPlan())
      return;

   // 2) Manage open baskets (TP / BE / trailing)
   g_manager.ManageAll();

   // 3) Watch for entry-level touches (no immediate trade on candle open)
   g_entry.ProcessTouches();
}

//+------------------------------------------------------------------+
//| Trade transaction — keep management responsive after fills       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_POSITION)
   {
      g_manager.ManageAll();
   }
}

//+------------------------------------------------------------------+
//| Tester note                                                      |
//+------------------------------------------------------------------+
double OnTester()
{
   // Soft metric only — strategy is not optimized for guaranteed profit
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
