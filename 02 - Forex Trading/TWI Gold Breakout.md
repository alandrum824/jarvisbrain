---
status: active
project: forex-trading
type: reference
---
# TWI Gold Breakout

MQL5 gold H4 breakout EA built 2026-10-12 (~6:30 PM PT) from the [[Gold EA Market Survey]]. Adam: "look at gold EA's all over the Internet see which ones are successful and start work from there. Build me a EA" → "Gold". Source: `TWI Gold Breakout.mq5` (this folder).

**Status: compiled 0/0 on the laptop AAAFx terminal, deployed as `MQL5\Experts\Advisors\TWIGoldBreakout.mq5` (byte-identical to the vault copy). NOT attached. Passes the replay; MT5 agrees overall but only 4 of 7 years are positive. It's a lead, not a pass: it pays when gold trends up.**

## Rules (closed H4 bars; defaults = the MQL5 code-base 77691 rules as published)
- **BUY:** bar 1 closes above the highest high of the 20 bars before it, bar 2 did not, and bar 1 closed above EMA 200. Market buy.
- **SELL:** mirror, off by default (`AllowShort=false`). With shorts on, the replay fell to 4/7 years.
- **SL** 2 × ATR(20) from the fill. **TP** 2R (`EXIT_TARGET`), or `EXIT_TRAIL` (a chandelier at the extreme since entry − 3 ATR, checked each new bar).
- One position per magic (20261013), a hard SL on every order (closed at once if none is attached), no grid. Skips the trade if the spread is more than 10% of the stop.
- Sizing: `LOTS_FIXED` 0.01 (default) or `LOTS_RISK_PERCENT` 1%.

## Evidence
**Replay** (`gold_breakout_research.py`, 2020-01 → 2026-10, NY-aligned H4 bars): 195 trades, +74.7R, PF 1.71, 46% wins, 5/7 years. It beat the coin flip 98% and random-time longs 96%.

**MT5 tester** (`stg\trendscalper\gbyears.py`, broker H4 bars, 1-min OHLC, $10k, 0.01 fixed):

| Year | Net | PF | Trades | Win % | Equity DD | Replay R |
|---|---|---|---|---|---|---|
| 2020 | −$89 | 0.82 | 31 | 42% | 2.2% | −1.0 |
| 2021 | −$159 | 0.43 | 19 | 26% | 2.1% | −14.0 |
| 2022 | −$82 | 0.75 | 24 | 33% | 1.6% | +1.0 |
| 2023 | +$105 | 1.41 | 25 | 44% | 1.3% | +16.0 |
| 2024 | +$428 | 2.22 | 33 | 58% | 1.0% | +29.0 |
| 2025 | +$1,152 | 3.00 | 36 | 61% | 2.6% | +36.0 |
| 2026 to 10-10 | +$349 | 1.33 | 19 | 47% | 5.1% | +7.7 |
| **2020–26 single run** | **+$1,683** | **1.50** | **188** | 46% | **4.5%** | +74.7 |

**Read:**
- **The two engines agree on the shape:** 2020–22 flat to losing, 2023–26 strongly positive, PF 1.50 vs 1.71. The broker's H4 bars start at a different hour than the replay's, so the agreement is not a bar-alignment fluke.
- **It is a trend-follower.** It loses small in ranging or choppy gold (2020–22) and makes most of its money in the 2023–26 bull run. The random-longs control says the breakout timing still adds value over just being long, but a long sideways or bear year would look like 2021.
- **Fixed 0.01 on a price that doubled** weights the later years more in dollars. Use the PF column to compare years.
- Not tuned: every number is the published default.

## Related
[[Gold EA Market Survey]] · [[TWI Gold Asia Breakout]] · [[EA Scorecard]] · [[EMA Ribbon Trend Research]] (gold H4 longs held there too)
