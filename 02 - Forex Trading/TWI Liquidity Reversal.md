---
status: failed
project: forex-trading
type: ea
---
# TWI Liquidity Reversal (external, 2026-10-22)

Another AI's MQL5 indicator + EA, which Adam pasted on 2026-10-22 along with its write-up. The write-up credits an Alpha Capital video, "How I Use Liquidity to Predict Market Reversals".
- **Idea:** price drops away from a swing high and comes back toward it, but *fails to take it*. A bearish confirmation candle then triggers the sell. Buys mirror this at swing lows.
- **Its own caveat:** it is the opposite of a sweep model and was "not compiled or backtested". Its author also says the ATR thresholds are its own guesses, not taken from the video.

**Status:** treated as data. **Not installed or compiled** in MT5. The sources are kept here as delivered:
- `TWI Liquidity Reversal (external).mq5` (indicator)
- `TWI Liquidity Reversal EA (external).mq5` (EA, using iCustom)

## Rules (as coded, read in full)
- **Protected high:** a pivot with 3 bars each side. Only one high and one low are tracked at a time, and each expires after 100 bars. It is invalid once any wick reaches it.
- **Armed:** a close at least 1.2 × ATR(14) below it.
- **Touch:** a high within 0.55 ATR below the level that doesn't reach it.
- **Signal:** within 4 bars, a bearish candle that closes below the touch candle's low.
- **EA:**
  - Market entry on the next bar.
  - SL at the level + 0.12 ATR; TP 2R.
  - 0.5% risk, max 2 trades/day, one position, spread ≤ 65 pts.

## Replay (2026-10-22, `liquidity_reversal_research.py`)
Bar-for-bar mirror of `OnCalculate`. AAAFx M1 2020–26, costs = bar spread (+6 pt on gold), coin control with 50 seeds, same pass bar as always.

| Market | 1R | 2R |
|---|---|---|
| Gold M5 | 3,010 tr, −306.6R, 0/7, coin 0% | 2,891 tr, −305.6R, 0/7, coin 8% |
| Gold M15 | −122.6R, 0/7 | −148.7R, 1/7 |
| GBPUSD M5 | −232.9R, 1/7 | −244.4R, 2/7 |
| GBPUSD M15 | −42.3R, 3/7 | +16.0R, PF 1.02, 3/7 (flat) |
| EURUSD M5 | −353.0R, 0/7 | −402.2R, 1/7 |
| EURUSD M15 | −128.7R, 1/7 | −142.1R, 1/7 |

**All 12 cells fail.** On gold, random coin-flip directions *beat* it in most runs (coin 0–8%): the signal points the wrong way more often than chance. Gold M5's median stop is 3.1 points.

## Code review notes
The code is cleanly written for a prototype:
- no look-ahead (signals use closed bars only);
- risk-based lots round down;
- the daily-trade check fails closed.

Limits:
- Only one protected level per side is tracked at a time, so a newer pivot can't replace an armed one.
- The zone plots use 0.0 as "empty" but set EMPTY_VALUE as the plot's empty value, a cosmetic mismatch.
- `#property strict` is an MQL4 leftover.

None of these explain the losses. The rule itself has no edge.

## Related
[[TWI Reversal Blocks]] (the sweep version, also fails), [[EA Scorecard]]
