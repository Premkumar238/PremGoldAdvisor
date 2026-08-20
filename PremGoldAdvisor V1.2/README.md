# PremGoldAdvisor V1.2

MetaTrader 5 Expert Advisor that trades the **AI Trend EMA ribbon** from the Pine Script *AI TREND NEW PANEL (DYNAMIC PRO)*.

Compile `PremGoldAdvisor.mq5` in MetaEditor (F7) to produce `PremGoldAdvisor.ex5`.

This EA does **not** guarantee profit. Gold is volatile, and a 0.17% stop is tight. Backtest and forward-test on demo before any live use.

## Install

1. Copy the `PremGoldAdvisor V1.2` folder into `MQL5/Experts/`.
2. Open `PremGoldAdvisor.mq5` in MetaEditor and compile (F7).
3. Attach it to a gold chart (XAUUSD). M15 or H1 is a reasonable starting point; M1 is usually too noisy for EMA 30–60.
4. Allow Algo Trading.
5. Optional: load `PremGoldAdvisor.set` on the Inputs tab.

## Strategy (matches the Pine indicator)

**Trend**

- Six EMAs: 30, 35, 40, 45, 50, 60 on close
- **Bullish** when they are stacked up: EMA1 > EMA2 > EMA3 > EMA4 > EMA5 > EMA6
- **Bearish** when they are stacked down

**Entries (closed candle only)**

- **BUY** when the ribbon *just became* bullish
- **SELL** when the ribbon *just became* bearish
- Same-direction signals are ignored until the opposite stack appears (Pine no-repeat)
- Optional ATR filter: skip if ATR(14) is below the minimum
- Opposite ribbon flip closes the open trade and reverses (on by default)

**Stops and targets**

| Level | Default |
|---|---|
| Stop loss | 0.17% from entry |
| TP1 | 1.0 × SL distance |
| TP2 | 2.0 × SL distance |
| TP3 | 3.0 × SL distance |
| TP4 | 4.0 × SL distance |

Broker take-profit is placed at **TP4**. If lot size is large enough, the EA can close 25% at TP1, TP2, and TP3. A 0.01 lot usually cannot be split, so it runs to TP4 or SL.

**Dashboard**

The on-chart panel shows trend, signal, entry/SL/TPs, TP hits, and higher-timeframe bias (M15 / M30 / H1 / H4 / D1 using EMA 20 vs EMA 50). HTF values are display-only unless you enable **Require HTF majority**.

## Defaults

| Setting | Default |
|---|---|
| Lot | 0.01 fixed |
| Magic | 120212 |
| Max spread | 0.80 price |
| ATR filter | On, min 0.50 |
| Auto trading | On |
| Chart theme / panel | On |

## Notes

- The Pine script’s stop-loss lookback input is unused in the original (stops are percent-based). V1.2 follows that: SL is **percent**, not swing lookback.
- After a stop-out, the EA will **not** re-enter the same direction until the ribbon unstacks and then stacks the other way, then stacks this way again. That is the Pine no-repeat rule.
- Use **PAUSE** / **CLOSE ALL** on the panel when you want manual control.
