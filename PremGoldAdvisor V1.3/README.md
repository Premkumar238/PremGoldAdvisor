# PremGoldAdvisorV1.3

MetaTrader 5 Expert Advisor for **XAUUSD** on the **M5** timeframe.

**Breakout touch entries:** on each new M5 candle the EA only calculates Buy/Sell entry levels, then waits. It opens **one** order when that level is touched, then adds the next order only after the previous TP is locked.

Compile `PremGoldAdvisorV1.3.mq5` in MetaEditor (F7) to produce `PremGoldAdvisorV1.3.ex5`.

This EA does **not** guarantee profit. Backtest and forward-test on demo with realistic spread, commission and slippage before any live use.

## Install

1. Copy the `PremGoldAdvisor V1.3` folder into `MQL5/Experts/`.
2. Open `PremGoldAdvisorV1.3.mq5` in MetaEditor and compile (F7).
3. Attach to **XAUUSD** on an **M5** chart. Enable Algo Trading.
4. Optional: load `PremGoldAdvisorV1.3.set`.

## Strategy

**New M5 candle (no orders yet)**

- Record candle open
- `Buy Entry  = Open + BuyEntryDistance`
- `Sell Entry = Open − SellEntryDistance`
- Status → **WAITING TOUCH**

Example: Open `3400` → Buy `3402`, Sell `3398` (with distance `2.00`).

**Entries (one order at a time)**

| Event | Action |
|---|---|
| Ask reaches Buy level | Open **1 Buy** (not 5) |
| Buy TP1 touched | Move remaining SL → **TP1**, then open Buy #2 |
| Buy TP2 touched | Move remaining SL → **TP2**, then open Buy #3 |
| Buy TP3 / TP4 | Same: lock SL at that TP, then open the next order |
| Buy TP5 touched | Ladder complete (orders close at TP5) |
| Bid reaches Sell level | Same sequence on the Sell side |

Each side **starts** at most once per candle. Extra orders are added only after the previous TP is locked. New add-on orders use SL at the last locked TP so they are scratch if price returns.

`AllowBothDirections`:

- `true` — Buy and Sell may both trigger on the same candle
- `false` — after one side triggers, the other is blocked for that candle

**Trailing / scale-in ladder**

- At first open: **Initial SL** (or none if `InitialSL = 0` — unlimited risk warning logged)
- After **TP1**: remaining SL → **TP1**, then open order 2
- After **TP2**: remaining SL → **TP2**, then open order 3
- After **TP3**: remaining SL → **TP3**, then open order 4
- After **TP4**: remaining SL → **TP4**, then open order 5
- After **TP5**: ladder complete

SL only moves in the protective direction (never backward).

This does **not** remove all loss: if price never reaches TP1, the first order can still hit the initial SL. Broker min-stop distance can delay the TP lock. Add-on fills can still lose a small amount to spread/slippage.

## Key inputs

| Setting | Default | Notes |
|---|---|---|
| Buy entry distance | 2.00 | Above M5 open |
| Sell entry distance | 2.00 | Below M5 open |
| Allow both directions | true | Independent Buy/Sell triggers |
| Enable Buy / Enable Sell | true | Per-side master switches |
| TP1…TP5 | 0.50 … 2.50 | From first fill; lock + scale-in rungs |
| Initial SL | 5.00 | On the first order only; `0` = none (unlimited risk) |
| Scale in on TP | true | Open next order only after previous TP is locked |
| Break-even buffer | 0.10 | Extra cushion past net BE |
| Compensate spread at BE | true | Cover spread at TP1 trail |
| Max active baskets | 2 | Concurrent Buy/Sell baskets |
| Max spread | 0.80 | Block new entries if exceeded |
| Magic number | 130213 | Position identification |

## Restart / reconnection

On init the EA:

- Loads GlobalVariable state
- Scans open positions by Magic Number
- Rebuilds TP ladder and trail step
- Blocks duplicate entries for an already-triggered candle

## Panel

Shows status, armed Buy/Sell levels, open counts, TP-hit / trail step, last action. **PAUSE** / **CLOSE ALL** buttons included.

## Disclaimer

For **testing and risk management** only. Past backtests do not predict future results. Always validate in the MT5 Strategy Tester before live trading.
