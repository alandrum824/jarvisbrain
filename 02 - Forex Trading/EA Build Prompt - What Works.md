---
status: active
project: forex-trading
type: reference
---
# EA Build Prompt - What Works

A copy-paste prompt (2026-10-13, Adam: "Give me prompt best things that worked best ea best strategy in a prompt"). It condenses the [[EA Scorecard]], [[TWI Gold Asia Breakout]], [[TWI ORB Momentum]] and [[Gold EA Market Survey]] so any AI can build or judge an EA against what has actually been proven. Update it when the scorecard changes.

---

```
You are building/evaluating an MT5 Expert Advisor for a retail account (AAAFx, MT5, hedging, 1:500,
~$400 balance, XAUUSD spread ~33-52 points). Only build what the evidence below supports. No grid,
no martingale, no averaging down, no lot-up-after-loss "recovery". Every order carries a broker-side
SL and TP. One position per magic.

=== WHAT WORKS (tested 2020-2026, real spreads, beat a coin-flip control, confirmed in 2 engines) ===

1) GOLD ASIA RANGE BREAKOUT  (best gold result; XAUUSD only)
   - Range: high/low of 00:00-05:00 GMT (Asian session).
   - Filter: skip the day if range width < 0.10 or > 0.80 x yesterday's daily ATR(14).
   - 05:00 GMT: BUY STOP at high + 5% of width, SELL STOP at low - 5% of width, OCO (first fill
     cancels the other). If price is already outside the range at 05:00, take that side at market.
   - SL = the other side's stop price (~1.1 x range). TP = 1R. Keep the full 1R target
     (0.5R / 0.3R / 2-hour exits all FAILED - the edge is the follow-through).
   - Cancel unfilled orders 15:00 GMT; close any open trade 16:00 GMT. Nothing held overnight.
   - Results: replay 1,607 trades, +74R, PF 1.12, 6/7 years, beat coin flip 100%, shorts and longs
     both profitable (not just gold's uptrend). MT5 tester: 1,600 trades, PF 1.33, 6/7 years,
     equity DD 2.6% at 0.01 lots on $10k.
   - Gold-only: the same rules FAIL on EURUSD, GBPUSD, USDJPY, AUD/CAD pairs and all indices.
   - Risk: median stop ~$47 at 0.01 lots in 2026 (gold is volatile) -> needs ~$2.4k-4.7k for
     1-2% risk at 0.01. Thin edge in quiet years (PF ~1.05 in 2021-23).

2) ORB MOMENTUM  (session-open breakout; FX + US30)
   - NY 09:30 (New York time): range = high/low of the first 55 one-minute bars. In the next 10
     minutes the FIRST touch of a range edge enters in that direction (both edges in one bar = no
     trade). Filter: the edge must be on the trend side of the last closed H1 EMA50.
   - SL = 2.2 x range, TP = 0.75 x SL (wide stop, near target -> ~63% wins). One trade per session.
   - Passed: EURUSD NY 09:30 (405 trades, +32R, PF 1.21, 6/7 years, coin 96%);
     USDJPY London 03:00 NY time (525 trades, +36R, PF 1.18, 6/7 years, coin 100%, MT5 5/5 windows
     with 0.5% risk sizing); US30 NY (+0.12R/trade, 5/5 years). FAILED on gold in MT5.
   - Small stops on EURUSD (~35-60 pips => ~$3.50-6 risk at 0.01) fit a small account.

3) GOLD H4 20-BAR BREAKOUT, LONGS ONLY  (lead only, trend-dependent)
   - H4 close > highest high of prior 20 bars (prior bar didn't), close > EMA200 -> buy;
     SL 2 x ATR(20), TP 2R. Replay +75R PF 1.71 (beat random longs 96%), MT5 PF 1.50 but only 4/7
     years (loses in sideways gold 2020-22). Use as a secondary, not a core.

THE PATTERN: a quiet session sets a range -> the next liquid session breaks it -> trade WITH the
break, wide stop (the whole range behind you), full-size target. Edge comes from session structure,
not indicators.

=== WHAT FAILED (do not rebuild these) ===
- Any M1/M5/M15 gold scalper (EMA/RSI/ADX/PSAR/pullback/crossover): the ~$0.33-0.52 spread eats
  the edge. 90 short-hold gold patterns mined 2020-23 -> 0 survived a 2024-26 holdout.
- Zone fades: order blocks, FVGs, supply/demand, liquidity sweeps, CHoCH/BOS retests - no better
  than random zones.
- Small-target / high-win-rate exits (0.3-0.5R, breakeven at a few points, "profit lock").
- 15-minute session ranges on gold (5 sessions/day): -529R to -1,645R, worse than a coin flip.
- Every grid/martingale (Dominant, Thunderbolt, Ilan/Gorilla, Life Changer): 94-99% win rates,
  then account wipeouts (9-21 blowups in 7 years on $400).
- Marketplace "AI"/"sniper" EAs with no broker-verified live signal.

=== REQUIRED SAFETY CHASSIS (build into every EA) ===
- Account guard persisted in terminal global variables: pause after -2% realized day, -5% week;
  kill switch at equity 15% below peak balance (alert, survives restarts, manual re-arm).
- Headroom sizing: a stop-out can never cross the kill floor. Risk % capped at 2%, halved after
  3 straight losses. If even the minimum lot over-risks -> skip the trade and alert.
- Find own positions by iterating tickets and matching magic + symbol (never PositionSelect(_Symbol)
  - the account has manual trades on the same symbol).
- Correct broker clock: AAAFx server = NY+7 now (UTC+3 summer / UTC+2 winter); history before
  2026-03-07 is UTC+0 and before 2022-03-27 London time. Never hard-code a single UTC offset.
- SHADOW mode default on live charts (virtual trades logged to CSV, no orders) until a forward
  test agrees with the backtest; LIVE only on explicit go.

=== HOW TO PROVE ANY NEW IDEA BEFORE BUILDING IT ===
1. Write the rules down BEFORE looking at results (no tuning on the test data).
2. Test 2020-2026 on the broker's own M1 data with real bar spreads (+6 pt markup on gold).
3. Must be positive in >= 5 of 7 years AND PF > 1 AND beat >= 95% of 50 coin-flip runs
   (same entries, random direction). Long-only gold ideas must also beat random-time longs.
4. Confirm in a second engine (MT5 strategy tester) before it counts.
5. Only broker-verified live signals (MQL5/Myfxbook, 1+ year) count as outside evidence -
   screenshots, backtests, vendor pages and Telegram channels do not.
```

## Related
[[EA Scorecard]] · [[TWI Gold Asia Breakout]] · [[TWI ORB Momentum]] · [[TWI Gold Breakout]] · [[Gold EA Market Survey]]
