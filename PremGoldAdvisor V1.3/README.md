# PremGoldAdvisor V1.3

MetaTrader 5 Expert Advisor: **M5 dual ladder with touch entries**.

On each new 5-minute candle the bot **only calculates** Buy and Sell entry levels, then **waits**. It opens a side only when that level is touched.

Compile `PremGoldAdvisor.mq5` in MetaEditor (F7) to produce `PremGoldAdvisor.ex5`.

This EA does **not** guarantee profit. Backtest and forward-test on demo before any live use.

## Install

1. Copy the `PremGoldAdvisor V1.3` folder into `MQL5/Experts/`.
2. Open `PremGoldAdvisor.mq5` in MetaEditor and compile (F7).
3. Attach to **XAUUSD** (prefer M5 chart). Enable Algo Trading.
4. Optional: load `PremGoldAdvisor.set`.

## Strategy

**Candle open (no orders yet)**

- `Buy level  = M5 Open − BuyEntryOffset`
- `Sell level = M5 Open + SellEntryOffset`
- Status becomes **WAITING TOUCH**

**Entries (independent sides)**

| Event | Action |
|---|---|
| Price touches Buy level | Open **5 Buy** orders (TP1–TP5) |
| Buy level never touched | No Buy orders that candle |
| Price touches Sell level | Open **5 Sell** orders (TP1–TP5) |
| Sell level never touched | No Sell orders that candle |

Each side opens at most once per candle. If a level is never touched, that side stays flat.

By default `InpRequireLeaveFirst = true` so a level that is already near the market at the candle open must be left first, then retested — avoids instant fills on the open tick.

**Stops**

- At open: **protective initial SL** (`InpInitialSl`) — not break-even.
- After **TP1**: TP1 order closes; remaining 4 get SL at **net break-even** (optional spread + commission compensation).
- After **TP2**: remaining SL → TP1
- After **TP3**: remaining SL → TP2
- After **TP4**: remaining SL → TP3
- After **TP5**: final order closes; basket complete

SL never moves backward. Buy and Sell baskets are managed independently.

## Key inputs

| Setting | Default | Notes |
|---|---|---|
| Buy entry offset | 0.20 | Below M5 open |
| Sell entry offset | 0.20 | Above M5 open |
| TP1…TP5 | 0.50 … 2.50 | From fill price |
| Initial SL | 3.00 | Protective; `0` = none |
| Compensate spread at BE | true | Net BE after TP1 |
| Commission per 1.0 lot | 0.0 | Round-turn, account currency |
| BE extra points | 0 | Extra cushion past net BE |
| Allow stack cycles | false | Block new basket while same side still open |

## Panel

Shows status, armed Buy/Sell levels, open counts, TP-hit / trail step, last action. **PAUSE** / **CLOSE ALL** buttons included.
