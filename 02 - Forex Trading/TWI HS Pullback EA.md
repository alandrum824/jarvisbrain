---
status: active
project: forex-trading
type: reference
---
# TWI HS Pullback EA

MQL5 EA built 2026-09-30 (~1:25 AM) from Adam's request: "make a head and shoulder like both of these trades… both shoulders push up and pull back and enter on that pull back with stop loss under the shoulders" → "To mlq5 ea". The rules are taken from his XAGUSD H1 inverse-H&S trade that night. Source: `TWI HS Pullback EA.mq5` (this folder).

**Status:**
- Compiled clean on the laptop AAAFx terminal via the MetaEditor64 CLI: **0 errors, 0 warnings.** Deployed as `MQL5\Experts\Advisors\TWIHSPullback.mq5`, byte-identical to the vault copy.
- **Not attached to any chart. Not backtested yet** (see below).

## Logic
- **Pattern:** the last three confirmed fractal swings (PivotLen 5).
  - Inverse (buy): the head is ≥ 0.5 ATR below both shoulders, and the shoulders are within 1.5 ATR of each other.
  - The neckline runs through the highest highs of the LS–H and H–RS legs.
  - Optional prior-trend check: the high in the 40 bars before the LS must be ≥ neckline + 1 ATR, so the pattern is a reversal.
  - Regular (sell) = the mirror.
- **Entry (PULLBACK mode, default):**
  1. Push: a candle body ≥ 1.2 ATR in the trade direction after the RS.
  2. Pullback ≥ 0.3 ATR from the push extreme, staying beyond the RS.
  3. A rejection bar: closes in the trade direction, in the top/bottom 60% of its range.
  4. Market entry at the next bar.
- **NECK_RETEST mode:** a close through the neckline, then a retest within 0.3 ATR with a rejection close.
- **Exits:**
  - SL under the RS (or under both shoulders) + 0.1 ATR.
  - TP = measured move: neckline + head depth × TPFactor 1.0.
  - Skip if R:R < 1.5.
  - Stop to breakeven after a bar closes through the neckline.
- **Other rules:**
  - The setup dies on a close beyond the RS, or 40 bars after the RS.
  - One shot per pattern and one position at a time.
  - No grid, martingale or averaging.
- **Risk:**
  - RiskPercent 2 (lots from `OrderCalcProfit`, so AAAFx's gold tick-value quirk can't fool it). MaxLots 0.05.
  - **Skips the trade if the minimum lot would exceed the risk limit.** At ~$300 that will skip most silver/gold setups on H1.

## Testing (blocked 2026-09-30)
Adam: "Test it after try h1".
- **Planned run:** H1, 1-minute OHLC, 2024-09-30 → 2026-09-29, $10,000, 1% risk, MaxLots 100, drawing off; on XAGUSD, XAUUSD, EURUSD, GBPUSD, USDJPY, AUDUSD.
- **Configs written:** `tester_configs\hspull_v100_<SYM>_H1_m1ohlc_20240930-20260929_20260930.ini`.
- **Why it's blocked:**
  - The headless tester needs the live terminal closed (`/config` only works on a fresh launch).
  - Jarvis closed it, but the **headless launch was denied by the Claude Code auto-mode permission classifier** ("Interfere With Workloads").
  - The terminal was relaunched right away. Status was checked after the relaunch: connected, the 3 silver positions intact with SL/TP.
- **Second attempt (Adam: "2 run it on gold"):** even closing the terminal was denied by the classifier. His go-ahead in chat doesn't clear it. It needs a permission rule in Claude Code settings.
- **Runner saved:** `mt5-readonly/run_hs_test.sh <SYMBOLS>`. It closes the terminal, runs each config, then relaunches the terminal.
- **Options for Adam:**
  - Run it in the Strategy Tester GUI himself.
  - Add a permission rule so Jarvis can close the terminal and run the headless batch.

## Related
[[Chart Analysis Notes]] (the XAGUSD inverse H&S that inspired it), [[SMC Playbook (Imperial FX)]], [[MBT (MT5 Backtest Toolkit)]] (tester gotchas).
