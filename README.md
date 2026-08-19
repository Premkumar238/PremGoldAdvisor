# PremGoldAdvisor v1.0

MetaTrader 5 Expert Advisor for **XAUUSD (Gold)** on **M1**.

Compile `PremGoldAdvisor.mq5` in MetaEditor to produce `PremGoldAdvisor.ex5`.

## Honest scope

This EA does **not** guarantee profit, a high win rate, or “success.” Gold on the 1-minute chart is noisy, and market conditions change. A reasonable goal is **positive expectancy**, **controlled drawdown**, and **consistent risk management**.

Results depend on broker, spread, slippage, gold volatility, and the dates you test. Use Strategy Tester and a demo forward test before any live account.

## Install

1. Copy the `PremGoldAdvisor` folder into `MQL5/Experts/`.
2. Open `PremGoldAdvisor.mq5` in MetaEditor and compile (F7).
3. Attach `PremGoldAdvisor` to an XAUUSD M1 chart.
4. Allow Algo Trading.

Folder layout:

```
MQL5/Experts/PremGoldAdvisor/
  PremGoldAdvisor.mq5
  Include/
    PGA_Inputs.mqh
    PGA_Logger.mqh
    PGA_Utils.mqh
    PGA_State.mqh
    PGA_Indicators.mqh
    PGA_Filters.mqh
    PGA_Risk.mqh
    PGA_Trade.mqh
    PGA_Dashboard.mqh
```

## Strategy

**Entry (closed candle only)**

- Stochastic (8,3,3)
- Buy: %K and %D both in 5–10, and %K crosses above %D
- Sell: %K and %D both in 90–95, and %K crosses below %D

**Optional filters** (each can be switched off in Inputs)

| Filter | Default rule |
|---|---|
| EMA 200 | Buy only above, sell only below |
| ADX(14) | Trade only if ADX > 25 |
| ATR(14) | Skip very quiet markets (ATR below minimum) |
| Spread | Trade only if spread ≤ max points |
| Session | London and New York (GMT hours), skip Asia |
| News | Block new entries around high-impact USD events |

**Exits**

- Optional: Stochastic reaches 50 (off by default on live preset)
- Stop loss: 80 pips (configurable)
- Take profit: `1.5 × ATR`, larger in strong ADX trends, smaller when ADX is closer to ranging
- Trailing: activate after ~0.6×ATR profit, trail ~0.8×ATR, tighten if ADX weakens or Stochastic nears 50

**Risk**

- Default: fixed lot `0.01`
- Optional: risk `3%` of equity per trade (do not use both at once — pick one in Inputs)
- One open trade, magic `19987`
- No martingale, grid, averaging down, or hedging
- Cooldown after a close, free-margin check, duplicate-signal ignore
- Restores trailing/management after MT5 restart

## Pip size on Gold

Default pip size is **0.10**, so **80 pips = $8.00**. If your broker or your own definition treats $1.00 as one pip, set pip mode to Manual and pip size to `1.0` (then 80 pips = $80.00).

## Live defaults (v1.0 preset)

Tuned for more realistic live/demo entries on XAUUSD M1:

| Setting | Default |
|---|---|
| Buy zone | 5–20 |
| Sell zone | 80–95 |
| ADX minimum | 20 |
| Session (GMT) | 12:00–16:00 (London/NY overlap) |
| Max spread | 300 points |
| News filter | Off |
| ATR volatility filter | Off |
| Stop loss | 80 pips |
| Stochastic exit at 50 | Off |

**Buy still requires:** Stochastic cross in buy zone, price above EMA 200, ADX ≥ 20, inside session, spread OK.

After updating source files, recompile in MetaEditor (F7), remove the EA from the chart, and attach it again. Click **Reset** on the Inputs tab if old values remain.

## News filter

Uses the MT5 economic calendar. In Strategy Tester the calendar is often incomplete or unavailable. If that happens, the default is to **allow** trades (`News calendar unavailable` = Allow). Switch that input to Block if you want the tester to skip periods when news data is missing.

## Suggested testing

- Model: Every tick based on real ticks when possible
- Symbol: XAUUSD, period M1
- Test with filters on, then optimize individual filter toggles
- Watch spread sensitivity and session hours for your broker’s GMT offset (sessions are defined in **GMT**, not server time)
- Forward test on demo before live

Win rate on the dashboard is a lookback statistic, not a forecast.
