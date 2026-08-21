# PremGoldAdvisorV1.3

MetaTrader 5 Expert Advisor for **XAUUSD** on the **M5** timeframe.

**Breakout touch entries:** on each new M5 candle the EA only calculates Buy/Sell entry levels, then waits. It opens a side only when that level is touched (no immediate orders on the open).

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

**Entries**

| Event | Action |
|---|---|
| Ask reaches Buy level | Open **5 Buy** orders (TP1–TP5) |
| Buy level never touched | No Buy orders that candle |
| Bid reaches Sell level | Open **5 Sell** orders (TP1–TP5) |
| Sell level never touched | No Sell orders that candle |

Each side triggers at most **once per candle**. Baskets are managed independently.

`AllowBothDirections`:

- `true` — Buy and Sell may both trigger on the same candle
- `false` — after one side triggers, the other is blocked for that candle

**Trailing ladder**

- At open: **Initial SL** (or none if `InitialSL = 0` — unlimited risk warning logged)
- After **TP1**: close TP1 ticket; remaining SL → **net break-even** (+ `BreakEvenBuffer`, optional spread/commission)
- After **TP2**: remaining SL → TP1
- After **TP3**: remaining SL → TP2
- After **TP4**: remaining SL → TP3
- After **TP5**: basket complete

SL only moves in the protective direction (never backward).

## Key inputs

| Setting | Default | Notes |
|---|---|---|
| Buy entry distance | 2.00 | Above M5 open |
| Sell entry distance | 2.00 | Below M5 open |
| Allow both directions | true | Independent Buy/Sell triggers |
| Enable Buy / Enable Sell | true | Per-side master switches |
| TP1…TP5 | 0.50 … 2.50 | From fill price |
| Initial SL | 5.00 | Protective; `0` = none (unlimited risk) |
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
