# PremGoldAdvisor V1.3

MetaTrader 5 Expert Advisor: **M5 dual ladder** — on each new 5-minute candle the bot opens **5 Buy + 5 Sell** market orders, each with its own take-profit (TP1–TP5), then trails stop-loss on the remaining side as targets are hit.

Compile `PremGoldAdvisor.mq5` in MetaEditor (F7) to produce `PremGoldAdvisor.ex5`.

This EA does **not** guarantee profit. Hedged ladders can lose on the opposite side. Backtest and forward-test on demo before any live use.

## Install

1. Copy the `PremGoldAdvisor V1.3` folder into `MQL5/Experts/`.
2. Open `PremGoldAdvisor.mq5` in MetaEditor and compile (F7).
3. Attach it to an **XAUUSD (Gold)** chart. Prefer an **M5** chart (the EA uses `InpWorkTimeframe = M5` by default even if the chart TF differs).
4. Allow Algo Trading.
5. Optional: load `PremGoldAdvisor.set` on the Inputs tab.

## Strategy

**Entries**

- Trigger: new bar on the working timeframe (default M5).
- Opens 10 market orders at once: Buy1…Buy5 and Sell1…Sell5.
- Same candle is never used twice (anti-duplicate).
- By default, a new cycle waits until previous EA positions are flat (`InpAllowStackCycles = false`). Enable stacking only if you intentionally want overlapping cycles.

**Take-profit ladder**

Each order gets its own broker TP:

| Order | Take profit |
|---|---|
| Buy1 / Sell1 | TP1 |
| Buy2 / Sell2 | TP2 |
| Buy3 / Sell3 | TP3 |
| Buy4 / Sell4 | TP4 |
| Buy5 / Sell5 | TP5 |

Distances are configurable as **price** (default) or **points**.

**Trailing stop (per side, independent)**

Example for Buys when price moves up:

1. TP1 touched → Buy1 closes at TP; remaining Buy SL → **entry (break-even)**
2. TP2 touched → Buy2 closes at TP; remaining Buy SL → **TP1**
3. TP3 touched → remaining Buy SL → **TP2**
4. TP4 touched → remaining Buy SL → **TP3**
5. TP5 touched → final Buy closes at TP5

Sells use the same logic in reverse. SL never moves backward.

**Initial protective SL**

`InpInitialSl` (default `3.00` price on gold) is placed on every order at open. Set to `0` for no initial SL (higher risk).

## Key inputs

| Setting | Default | Notes |
|---|---|---|
| Lot size | 0.01 | Per order (10 × lot per cycle) |
| Magic | 130213 | Isolates V1.3 from other EAs |
| TP1…TP5 | 0.50 … 2.50 | Price distance (gold) |
| Initial SL | 3.00 | Price distance; 0 = none |
| Max spread | 0.80 | Price units |
| Allow stack cycles | false | Safer default |
| Working TF | M5 | Change only if you know why |

## Panel

On-chart panel shows status, open Buy/Sell counts, TP-hit / trail step, last action, and block reason. **PAUSE** / **CLOSE ALL** buttons included.

## Notes

- Broker stop-level / freeze-level rules are enforced; trail updates retry on the next tick if price is too close.
- State (ladder levels, trail steps, last opened bar) is stored in terminal global variables so a chart reload can recover.
- Tune TP distances to your broker’s XAUUSD digit format (2 or 3 digits) and typical M5 range.
