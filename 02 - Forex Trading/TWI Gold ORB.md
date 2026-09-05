---
status: built-untested
project: forex-trading
type: reference
---
# TWI Gold ORB

Single-file MQL5 reimplementation of the **GOLD_ORB** EA by Ulysses O. Andulte (`github.com/yulz008/GOLD_ORB`, 2022), built 2026-09-04 at Adam's request after he sent the mcpmarket skill listing for it.

**Status: compiled 0 errors / 0 warnings. Never run. No backtest exists yet.**

## Why it was rebuilt rather than cloned
The upstream repo does not compile on current MT5 builds:
- `int OnInit()` ends with `return("Initialization Success")` — returning a string from an int function.
- The input `LossStreakCounter` collides with the function `LossStreakCounter()`.
- It pulls ten custom includes plus a vendored copy of the whole MQL5 Math/Alglib library (~5 MB) that the strategy never uses.

The shipped `.ex5` was built on an older build and was **not** run — never execute a third-party binary.

## Source location
- Vault master: `02 - Forex Trading/TWI Gold ORB.mq5`
- Deployed: `MQL5/Experts/Advisors/TWIGoldORB.mq5`
- Upstream source pulled to scratch for reading only; not kept.

## Strategy (H1, XAU/USD)
1. Trading day starts at `InpStartHour` server time (default 01:00); all state resets.
2. The **first candle of the day** defines the range. A wick longer than `InpLongWickPoints` (500) is treated as noise and the **body** edge is used instead.
3. Later candles may **extend** the range — but only if the wick edge *and* the body edge both improve by more than `InpMinRangeUpdate` (0.1). Any extension **resets the consolidation counter**.
4. The range is tradable only after surviving `InpCandleComposition` (3) candles without extension.
5. Entry when a candle **closes** beyond the final range — bullish body high above range high, bearish body low below range low. Close-based, so non-repainting.
6. SL 400 points, TP 1200 points. Wide trail: 700 points behind price, arms at +100, 10-point step.
7. One long and one short per day (`InpMaxTradePerDay=2`), or one trade total (=1).

## THE BUG IN THE ORIGINAL — this is the finding
```cpp
if(100*((balance - capital)/capital) < -1*MaxEquityDrawdownPercent)
   printf(...);
   execute_trade = false;     // <-- no braces
```
`execute_trade = false` is **outside the if**. It runs unconditionally on every tick whenever `MaxEquityDrawdownPercent != 0`. The code default is `10`, and with the default `SlopeDetection=false` / `LossStreakCounter=0` nothing ever sets it back true.

**So the published EA, at its code defaults, never places a single live trade — only virtual ones.** The shipped `Input/default_input.set` sets `MaxEquityDrawdownPercent=0.0`, which sidesteps the bug without fixing it. Anyone who loads the EA without that set file gets an EA that silently does nothing.

Same disease as the [[TWI SMC Auction Flow]] bug table: a flag describing *market/risk state* also carrying an *execution side effect*, so the state can never be re-read honestly.

## Deviations from the original (all deliberate)
| # | Change |
|---|---|
| D1 | Equity-drawdown halt properly scoped (the bug above) |
| D2 | Sizing rewritten: `OrderCalcProfit()`, round **DOWN**, skip when budget can't buy one min lot. Original's `VerifyVolume()` raised sub-minimum volume **up** to the minimum — silently over-risking — and used `MathRound`, which can round risk above budget |
| D3 | Daily trade cap always enforced. Original set its direction flags only when `trades_per_day` was exactly 1 or 2; at 3+ no flag was ever set and entries were unlimited |
| D4 | Trail parameters (700/100/10) were hardcoded — now inputs |
| D5 | Long-wick threshold (500) and min range update (0.1) were hardcoded — now inputs |
| D6 | Chart objects had fixed names that collided across days — now unique per day and optional |

Day sequencing, range construction, extension rules, counter reset semantics and the signal test are reproduced **exactly**.

## Virtual book
Kept from the original: every signal is recorded in a virtual book that keeps running even when live trading is halted, so the loss-streak and equity-slope modules can detect recovery and re-enable live trading. `InpSlopeDetection` and `InpLossStreakCount` default off, as upstream.

## Assessment (Jarvis, unprompted)
Fixed 400/1200-point stops on gold don't scale with volatility. Over Jun 2025 – May 2026 gold ran 3354 → 4497; a 400-point stop is a completely different ATR fraction at each end of that. Expect the geometry to be the weak point, not the range logic. Upstream published screenshots and no numbers.

## Related
- [[TWI Gold MTF Grid]] — built the same day, separate EA, unrelated strategy
- [[TWP ORB EA Reference]] — the ORB EA Adam actually runs on EURUSD
- [[TWI Sniper ORB]], [[TWI Range Breakout]] — other breakout work
- [[Active Priorities]]
