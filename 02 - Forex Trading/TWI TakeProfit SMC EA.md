---
status: active
project: forex-trading
type: reference
---
# TWI TakeProfit SMC EA

MQL5 EA built from the TakeProfit / Forex Blog (TakeProfit EXCLUSIVE) Telegram chart language — BOS/CHoCH structure, order blocks, FVGs, weak-high/strong-low liquidity tags, equilibrium, and the T-P1/T-P2/T-P3 partial-target ladder. Adam supplied the file 2026-09-03 as the next EA after [[TWI SR Sweep Reclaim]].

## Source location
- Vault master copy: `02 - Forex Trading/TWI TakeProfit SMC EA.mq5`
- Deployed (not attached) to RisenAdam and RisenMOM: `MQL5/Experts/Advisors/TWITakeProfitSMC.mq5`
- Compiles clean on both terminals: **0 errors, 0 warnings**

## The spread bug that hid everything (2026-09-03)
The EA's first two backtests returned **zero trades**. Instrumentation showed why:

```
Bars processed: 2024
Spread points seen: min=250 avg=264.9 max=1480 (limit=25)
Blocked by spread: 2024
Reached TryEntries: 0
```

`InpMaxSpreadPoints = 25` against a 2-digit gold symbol whose spread runs ~250-265 points (~$2.50). **The spread gate blocked 100% of bars — the strategy code never executed once.** Raised to 400 (permits normal ~265, still blocks the ~1480 news spikes). Nothing about the strategy could be judged before this was fixed.

Related and worse: the first "fix" appeared not to work because of the tester `.set` cache overriding compiled defaults — see [[MBT (MT5 Backtest Toolkit)]] for that gotcha, which also invalidated entry-mode claims in the [[TWI SR Sweep Reclaim]] v3.x runs.

## v2.00 — entry architecture rebuild (Adam's spec, 2026-09-03)
The original design required **six independent conditions simultaneously** (structure shift AND equilibrium AND RSI AND channel AND rejection candle AND zone touch) on top of four pre-gates — an architecture that produces near-zero frequency and does not reflect the source material. Adam's instruction was explicit: **redesign the confluence logic, do not just loosen thresholds.**

Three layers now:
- **Layer A — hard gates (unchanged):** spread, session, daily-loss halt, Friday close, max positions. Operational protections only.
- **Core (all three mandatory):** `STRUCTURE + LOCATION + PRICE ACTION`.
- **Score (grades, never vetoes):** everything else, `MinConfluenceScore` (default 6).

Specific changes:
- **Two setup families**, no longer sharing one checklist: `BOS_CONTINUATION` and `CHOCH_REVERSAL`.
- **LOCATION is an OR:** `zoneTouch || brokenStructureRetest || keyLevelRetest`.
- **PRICE ACTION is an OR:** engulfing, rejection bar, or decisive reclaim close.
- **RSI demoted to confluence and its polarity corrected.** The original `RSI_AllowsBuy()` demanded RSI ≤ 46 for a *bullish continuation* — logically hostile, since continuation usually carries momentum. Now scores when RSI > 50 or rising; it can no longer reject anything.
- **Channel and equilibrium demoted to score.** Equilibrium became a `DISCOUNT/EQUILIBRIUM/PREMIUM` context rather than an exact 50% intersection.
- **Shadow evaluation:** every condition is evaluated even after one fails, and each candidate logs both `OriginalANDLogic` and `NewCoreLogic` verdicts — so filter value is measured, not asserted.
- **Zero-trade guard is diagnostic only** (`ZERO_TRADE_DIAGNOSTIC`); it never loosens a rule to manufacture a trade, per Adam's explicit instruction.
- **Structure-based targets:** TP1 nearest internal swing, TP2 next supply/demand zone, TP3 external liquidity, RR to each logged, R-multiple only as fallback.

## First real result (XAUUSD.sim M15, Aug 1 – Sep 2 2026, $400, every-tick)
Report: `mbt/reports/TWITakeProfitSMC_20260903_205610.htm`

**Architecture comparison on identical candidates — the point of the exercise:**

| | |
|---|---|
| Candidates evaluated | 387 |
| OLD all-AND logic would accept | **8** |
| NEW core+score logic accepts | **47** |
| Accepted by NEW only | 41 |

Roughly **6× more setups from restructuring alone**, no thresholds loosened. Adam's architectural diagnosis was correct.

**Funnel:** 2024 bars → spread blocked 38 → TryEntries 388 → raw structure events 387 (BOS bull 77 / bear 35, CHoCH bull 112 / bear 163) → valid location 149 (zoneTouch 124, brokenRetest 37, keyLevel 9) → price action 100 (bullEngulf 10, bearEngulf 13, rejectionBar 56, reclaim ~21) → core setups BUY 24 / SELL 27 → score pass 47 / fail 4 → entries BUY 24 / SELL 23.

**Trades (94 = 47 signals × TP1/TP2 tickets):**

| Metric | Value |
|---|---|
| Win rate | **63.8%** (60W / 34L) |
| Long / short win rate | 62.5% / 65.2% (balanced) |
| Profit factor | 0.94 |
| Avg win / avg loss | **+$6.39 / −$11.86** |
| Net | −$22.74 |
| Max balance DD | $112.62 (28%) |
| Max equity DD | $147.30 (37%) |
| Worst losing streak | 8 trades, −$112.32 |

## v2.30 — position sizing was the real bug (2026-09-03)
Exit-geometry forensics (MFE/MAE in R) overturned the "stops too wide" diagnosis. Variant A control showed **avg win 0.93R vs avg loss −0.97R, expectancy +0.238R, R-based PF 1.68 — positive in R while losing in dollars.** The cause was uncontrolled position sizing, not exits:

```
risk$ per trade:  min $1.44 | median $12.72 | max $52.09   (on a $400 account)
riskPts == risk$ for every trade  ->  0.01 lots every time
```

`CalcLots()` wanted a sub-minimum lot (0.5% of $400 = $2) and **floored it up to the broker minimum and traded anyway**, so actual risk was just the stop distance — **0.36% to 13% of the account per trade**. Wins landed on tight-stop (small $) trades, losses on wide-stop (large $) trades: R-positive, dollar-negative.

**Repair (money management only, strategy frozen):**
- `GetRiskMoney()` uses `OrderCalcProfit()` against the broker's real contract spec, not `points × lots`.
- `ComputeSafeLots()` sizes from real dollar risk, **rounds down only**, and **never floors a sub-minimum lot up to trade anyway** — if one minimum lot would exceed permitted risk the setup is refused (`RISK_REJECT_MIN_LOT`).
- `InpMaxActualRiskPercent` (0.60%) is an absolute pre-send ceiling, recomputed on the final entry/stop/lot and independent of every entry rule.
- `RISK_CHECK` logged before every order; stop-outs landing far from −1R are counted as risk-model mismatches.
- **Structural stops untouched** — Adam's rule: "too large for this account → skip", never "move the stop so 0.01 fits".

### Results

| | A ($400) | B ($10,000) | Old broken sizing |
|---|---|---|---|
| Trades | 4 | 138 | 94 |
| Setups refused for risk | 94 | 0 | n/a |
| Actual risk % (min/avg/max) | 0.37/0.48/0.60 | 0.27/0.44/0.53 | 0.36 → **13.0** |
| Win rate | 50% (n=4) | 60.9% | 63.8% |
| Avg win / avg loss | — | 0.72R / −0.99R | 0.93R / −0.97R |
| Expectancy | — | **+0.049R** | +0.238R |
| R-based PF | — | 1.13 | 1.68 |
| Net | +$8.03 | +$218.37 | −$22.74 |
| Max equity DD | $6.92 | $417.59 (4.2%) | $147.30 (37%) |

Zero risk-model mismatches in both runs — sizing math and actual fills agree.

**The finding that matters: the earlier +0.238R was flattered by the broken sizing, not merely obscured by it.** Averaging R across positions whose dollar risk varied 36:1 was never like-for-like. The clean figure is **+0.049R per deal with R-PF 1.13** — a thin edge carried entirely by the 60.9% hit rate, with payoff now *worse* than 1:1 (0.72R win vs 0.99R loss).

**$400 cannot trade this strategy on gold at 0.5% risk** — 94 of 96 setups correctly refused. The old 94-trade run existed only because up to 13% risk was silently permitted; one such trade could have taken a third of the account.

**Not validated.** One month, one symbol, one trending regime, thin edge. Next per Adam: longer history, genuine out-of-sample, multiple regimes — before any parameter work.

## Real open items
- **The loss is geometry, not setup quality.** A 63.8% win rate is genuinely good; it still nets negative because **average loss is 1.86× average win** — TP1/TP2 take profit at structure targets while losers run to a full stop. Fixing this is about risk/reward, not more filters.
- **37% equity drawdown on a $400 account is not survivable** at these settings regardless of edge.
- **The score gate is nearly inert** — it rejected only 4 of 51 core setups (distribution `6:12 7:3 8:11 9:6 10:8 11:4 13:3`). The three core conditions do the real filtering, so `MinConfluenceScore=6` is currently untested as a discriminator.
- **Nothing has been optimised**, per Adam's standing instruction. No parameter tuning until the architecture is judged right.

## Known code issues found on read-through (not yet fixed)
1. **`AtrValue()` creates and releases an indicator handle on every call** — called from `BestZone()`, `PriceInZone()`, `FindOrderBlocks()`, so repeatedly per bar. Slow, and a freshly created handle can return no data, silently yielding ATR = 0 and zeroing every ATR-scaled buffer. Should be one cached handle from `OnInit`.
2. **Arbitrary trend seed in `BuildBOS_CHoCH()`** — the initial BULL/BEAR choice comes from whichever of the first two swings came first, and that seed decides whether early events are labelled CHoCH or BOS.
3. **`z.mitigated` assigned twice** in both `FindOrderBlocks` and `FindFVGs`; the first assignment is dead and its expression is wrong anyway.
4. **`InpMaxTrades = 2` interacts with the TP1/TP2 split** — one signal opens two positions and consumes the entire budget, so effectively one signal at a time and never a simultaneous long and short.

## Related
- [[TWI SR Sweep Reclaim]] — the previous EA; same over-filtering failure mode, diagnosed the same way
- [[MBT (MT5 Backtest Toolkit)]] — the tester `.set` cache gotcha found during this work
- [[Active Priorities]]
