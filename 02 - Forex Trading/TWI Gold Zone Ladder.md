---
status: tested-no-edge
project: forex-trading
type: reference
---
# TWI Gold Zone Ladder

Gold M5 supply/demand zone EA. Adam asked on 2026-10-11 for a combination of the GenWealth™ Gold "SDP model" (zone sells with a TP1/TP2/TP3 runner ladder) and DOMINANT EA PRO V6.3 by jeebsoft (a martingale grid: SL 0, 1.5× lot after a loss, 25 adds, close-all at 50% of money). The martingale was rejected. Adam's answer: "No build it your way". So every trade has a hard stop, there's no grid and no adding, and from Dominant only the time window, breakeven and kill-switch ideas carry over.

**Status: TESTED 2026-10-11, NO EDGE. No EA code written.** We ran the multi-year test first so we wouldn't repeat [[TWI OB Hunter]], and it failed (see Results). Whether to build anyway is Adam's call, pending. Research script: `zone_ladder_research.py`.

## Spec (pre-declared, not tuned)
1. **Setup:** the [[TWI EQ Liquidity OB]] v10 trigger on M5. A swing high/low (3/3 pivots) either equals a prior swing (≤ 0.15 ATR) or sweeps it (0.05–2 ATR beyond it, then closes back). After that, a close breaks the swing in between (BOS/CHoCH) within 40 bars.
2. **Zones:** the entry zone is the advance block, i.e. the last opposite candle before the break (if it's taller than 1.5 ATR, its body is used). The stop area is the top block / sweep candle.
3. **Entry:** price returns into the advance block, and an M5 candle closes back out of it in the trade direction. The order goes in at market on the next M5 open.
4. **Stop:** beyond the top block + 0.1 ATR. Risk has to be between 0.15 and 4 ATR. The trade is invalidated after 2 closes beyond the stop area or a close beyond the equal level. The retest window is 120 bars.
5. **Ladder:** 50% at 1R and the stop moves to entry. Then 25% at 2R and 25% at 3R. Max hold is 24 h.
6. **Risk:** 1% per trade, one trade at a time, Mon–Fri. No new trades after −3% on the day.
7. **Never:** martingale, grid, averaging, or a trade without a stop.

## Research method
- **Data:** AAAFx gold M1 from 2020-01-02 to 2026-10-09 (`C:\Users\aland\stg\obh\XAUUSD_M1.csv`, see [[MBT (MT5 Backtest Toolkit)]]). Exits are resolved on M1 using the bar spread + 6 pts. Same-bar ties count as stops. After TP1, the breakeven check starts on the TP1 bar itself.
- **Controls:** random-zone twins (same setups, with the zone moved to a random distance drawn from the real distance pool) and random-time entries (same direction mix, stop size and management).
- **Baseline:** fixed 2R on the same entries.
- **Fixes vs the 2026-10-07 EQ research:**
  - That script credited a trade with TP2 even after it had come back to entry following TP1. This inflated its "half TP1 + BE" numbers. Here the trade closes at entry.
  - That script used a flat 0.35 cost. Here the real bar spread is used.

## Results (2026-10-11, 1-seed smoke run, log `C:\Users\aland\stg\obh\zone_ladder_smoke.log`)
15,088 setups and 5,295 signals over 2020–26, taken one trade at a time under the −3R daily cap.

| Management | Trades | Total | Avg/trade | Win | PF | Twin (shifted zones) | Random-time entries |
|---|---|---|---|---|---|---|---|
| **Ladder 1R/2R/3R + BE** | 3,545 | **−284.1R** | −0.080R | 46% | 0.85 | −227.6R | −190.2R |
| Fixed 2R | 3,453 | −141.8R | −0.041R | 32% | 0.94 | −156.6R | −100.7R |

- **The ladder loses in 6 of 7 years.** 2025 was its only positive year, at +6R. Fixed 2R had three positive years (2023, 2025, 2026).
- **Real zones do worse than random entry times** under both management styles, so the zone subtracts value.
- **The ladder is worse than fixed 2R.** It wins more often (46%), but banking half at 1R and then getting stopped at BE gives the expectancy away, and the spread takes a bigger share of each small win.
- **Cost alone is about −0.05R per trade.** Random-time entries lose that much with no signal, so any gold M5 scalp has to clear that first.
- **The 2026-10-07 EQ result (+0.21R on gold M5) doesn't survive this test.** Three things flattered it: the bug that credited TP2 after a return to entry (67–78% of TP1 hits came back to entry), the flat 0.35 cost, and a single 17-month window.
- One seed is a thin control. The verdict doesn't depend on it, though: the strategy loses money on its own and sits below random-time entries.
