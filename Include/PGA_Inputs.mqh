#ifndef PGA_INPUTS_MQH
#define PGA_INPUTS_MQH

//+------------------------------------------------------------------+
//| PremGoldAdvisor v1.0 — inputs (all filters are independently     |
//| toggleable for Strategy Tester optimization).                    |
//+------------------------------------------------------------------+

enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,          // Fixed lot size
   LOT_RISK_PERCENT = 1    // Risk percent of equity
  };

enum ENUM_PIP_MODE
  {
   PIP_AUTO = 0,           // Auto (XAUUSD: 0.10)
   PIP_MANUAL = 1          // Manual pip size
  };

enum ENUM_NEWS_FAIL_MODE
  {
   NEWS_FAIL_ALLOW = 0,    // Allow trades if calendar unavailable
   NEWS_FAIL_BLOCK = 1     // Block trades if calendar unavailable
  };

enum ENUM_NEWS_IMPORTANCE
  {
   NEWS_IMP_HIGH = 0,      // High impact only
   NEWS_IMP_MODERATE = 1,  // Moderate and high
   NEWS_IMP_LOW = 2        // All published events
  };

input group "=== General ==="
input ulong             InpMagic                = 19987;           // Magic number
input ENUM_PIP_MODE     InpPipMode              = PIP_AUTO;        // Pip size mode
input double            InpManualPipSize        = 0.10;            // Manual pip size (if Manual)
input bool              InpStrictSymbol         = true;            // Warn if symbol is not Gold
input bool              InpStrictTimeframe      = false;           // Warn if timeframe is not M1
input int               InpSlippagePoints       = 30;              // Max slippage (points)

input group "=== Stochastic (8,3,3) ==="
input int               InpStochK               = 8;               // %K period
input int               InpStochD               = 3;               // %D period
input int               InpStochSlowing         = 3;               // Slowing
input double            InpBuyZoneLow           = 5.0;             // Buy zone low
input double            InpBuyZoneHigh          = 20.0;            // Buy zone high
input double            InpSellZoneLow          = 80.0;            // Sell zone low
input double            InpSellZoneHigh         = 95.0;            // Sell zone high
input double            InpExitLevel            = 50.0;            // Primary exit (Stochastic)

input group "=== Trend filter (EMA) ==="
input bool              InpUseEmaFilter         = true;            // Enable EMA trend filter
input int               InpEmaPeriod            = 200;             // EMA period
input ENUM_APPLIED_PRICE InpEmaPrice            = PRICE_CLOSE;     // EMA applied price

input group "=== Trend strength (ADX) ==="
input bool              InpUseAdxFilter         = true;            // Enable ADX filter
input int               InpAdxPeriod            = 14;              // ADX period
input double            InpAdxMin               = 20.0;            // Minimum ADX to trade
input double            InpAdxStrong            = 40.0;            // Strong-trend ADX (wider TP)
input double            InpAdxRange             = 28.0;            // Ranging ADX ceiling (smaller TP)

input group "=== Volatility (ATR) ==="
input bool              InpUseAtrFilter         = false;           // Enable ATR volatility filter
input int               InpAtrPeriod            = 14;              // ATR period
input double            InpMinAtr               = 0.10;            // Minimum ATR (price) to allow entries

input group "=== Spread filter ==="
input bool              InpUseSpreadFilter      = true;            // Enable max-spread filter
input int               InpMaxSpreadPoints      = 300;             // Maximum allowed spread (points)

input group "=== Session filter (GMT) ==="
input bool              InpUseSessionFilter     = true;            // Enable London/NY session filter
input int               InpLondonStartHour      = 12;              // London start hour (GMT)
input int               InpLondonEndHour        = 16;              // London end hour (GMT, exclusive)
input int               InpNewYorkStartHour     = 12;              // New York start hour (GMT)
input int               InpNewYorkEndHour       = 16;              // New York end hour (GMT, exclusive)
input bool              InpUseFridayCutoff      = true;            // Stop new entries late Friday
input int               InpFridayCutoffHourGmt  = 19;              // Friday cutoff hour (GMT)

input group "=== News filter (USD) ==="
input bool              InpUseNewsFilter        = false;           // Enable high-impact USD news filter
input ENUM_NEWS_IMPORTANCE InpNewsImportance    = NEWS_IMP_HIGH;   // Minimum news importance
input int               InpNewsMinutesBefore    = 30;              // Minutes before event to block
input int               InpNewsMinutesAfter     = 15;              // Minutes after event to block
input ENUM_NEWS_FAIL_MODE InpNewsFailMode       = NEWS_FAIL_ALLOW; // If calendar is unavailable
input string            InpNewsCurrencies       = "USD";           // Currencies to watch (comma-separated)

input group "=== Stops and targets ==="
input double            InpSLPips               = 80.0;            // Stop loss (pips)
input double            InpTPAtrMultiplier      = 1.5;             // Base TP = multiplier × ATR
input double            InpTPTrendBoost         = 1.30;            // TP boost in strong trends
input double            InpTPRangeCut           = 0.70;            // TP cut in ranging markets
input bool              InpUseDynamicTP         = true;            // Enable ATR-based take profit
input bool              InpUseStochExit         = false;           // Close when Stochastic reaches exit level

input group "=== ATR trailing stop ==="
input bool              InpUseTrailingStop      = true;            // Enable ATR trailing stop
input double            InpTrailActivateATR     = 0.6;             // Activate after profit of X × ATR
input double            InpTrailDistanceATR     = 0.8;             // Trail distance in ATR
input double            InpTrailTightenFactor   = 0.50;            // Tighten factor when conditions met
input double            InpTrailTightenStochGap = 10.0;            // Tighten when Stoch is this close to exit

input group "=== Risk management ==="
input ENUM_LOT_MODE     InpLotMode              = LOT_FIXED;       // Lot sizing method
input double            InpFixedLot             = 0.01;            // Fixed lot (default)
input double            InpRiskPercent          = 3.0;             // Risk percent (if Risk percent mode)
input double            InpMarginBuffer         = 1.20;            // Required margin × this must be free
input int               InpCooldownSeconds      = 300;             // Minimum seconds between trades
input double            InpMaxDailyLossPercent  = 0.0;             // Max daily loss % (0 = disabled)
input double            InpMaxDrawdownPercent   = 0.0;             // Max equity drawdown % (0 = disabled)

input group "=== Dashboard and logging ==="
input bool              InpShowDashboard        = true;            // Show on-chart dashboard
input bool              InpLogToJournal         = true;            // Log entries/exits to Experts journal
input bool              InpLogToFile            = false;           // Also log to Common/Files
input int               InpStatsLookbackDays    = 30;              // Closed-trade stats lookback (days)
input int               InpDashboardX           = 12;              // Dashboard X offset
input int               InpDashboardY           = 24;              // Dashboard Y offset

#endif
