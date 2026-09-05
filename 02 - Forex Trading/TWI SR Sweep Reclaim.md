---
status: active
project: forex-trading
type: reference
---
# TWI SR Sweep Reclaim

New MQL5 EA (`TWI SR Sweep Reclaim.mq5` / compiled as `TWISRSweepReclaim.mq5`), built 2026-09-03 from Adam's own spec — an explicit state-machine version of the "only S/R strategy you'll ever need" YouTube approach (impulse → resistance → break → flip → retest → liquidity sweep → reclaim → confirmation → entry), with every discretionary term turned into an exact rule per his write-up.

## Source location
- Vault master copy: `02 - Forex Trading/TWI SR Sweep Reclaim.mq5`
- Deployed (not attached) to RisenAdam and RisenMOM: `MQL5/Experts/Advisors/TWISRSweepReclaim.mq5`
- Compiled clean via `MetaEditor64.exe` CLI on both terminals: **0 errors, 0 warnings**, second pass (first pass had 2 cosmetic "unchecked OrderSend return" warnings, fixed by capturing the return value)

## Logic
Explicit state machine (`EA_STATE`), not a pile of if-statements, running across three configurable timeframes (`TrendTF`=H1, `StructureTF`=M15, `EntryTF`=M5 by default — symbol-agnostic, not gold-only):

1. **SEARCH_TREND** — HH+HL (bull) or LH+LL (bear) from the last two confirmed swing highs/lows on `StructureTF` (fractal-style, `SwingLeftBars`/`SwingRightBars`, closed candles only — no repaint). Also requires the qualifying impulse leg to be ≥ `MinImpulseATR`×ATR and bigger than the leg before it.
2. Zone built from the confirmed swing (resistance from a swing high in a bull trend, support from a swing low in a bear trend), padded by `ZonePaddingATR`.
3. **WAIT_FOR_BREAKOUT** — closed `StructureTF` candle must close beyond the zone by `BreakoutBufferATR`×ATR with a body ≥ `MinBreakoutBodyATR`×ATR. Cancels back to SEARCH_TREND if the structural trend flips first.
4. **WAIT_FOR_RETEST** — old resistance is now support (or vice versa); waits up to `MaxRetestBars` `StructureTF` bars for price to tag back into the zone.
5. **WAIT_FOR_SWEEP** (now watching `EntryTF`, the finer timeframe) — a candle must wick through the zone by ≥ `MinSweepATR`×ATR and close back on the reclaim side, with the reclaim strictness configurable (`SweepReclaimLevel`: zone low / mid / high). Times out after `MaxSweepWaitBars`.
6. **WAIT_FOR_CONFIRMATION** — next `EntryTF` candle must close beyond the sweep candle's own high (bull) / low (bear) — the one clean, non-subjective substitute for "read the candlestick pattern." Times out after `MaxConfirmationBars`.
7. **Entry** — either market-on-confirmation-close or a Buy/Sell Stop above/below the confirmation candle (`EntryMode`, defaults to the stop-order version so price has to prove continuation). SL beyond the sweep wick + `SLBufferATR`. TP: `TP_STRUCTURE` (next opposite swing), `TP_FIXED_RR`, or `TP_HYBRID` (structure target, but skip the trade if RR < `MinRR`) — hybrid is the default, matching Adam's stated preference.
8. **Management** — breakeven at `BreakevenR` (default 1R), ATR trail at `TrailStartR` (default 1.5R). One position per symbol (`MaxPositions`), no martingale/grid/averaging anywhere in the code.

Risk-based lot sizing off `RiskPercent` of balance (same `CalcLots` pattern as the other TWI EAs), respecting broker min/max/step.

## What's deliberately NOT in v1
Per Adam's own instruction in the spec: no RSI/MACD/stochastic/EMA stack, no FVG/order-block confirmation layer, no ADX. Pure structure + level + break + retest + sweep + reclaim first, so a backtest can show exactly where the raw price-action edge fails before adding filters one at a time.

## ⚠️ Correction (2026-09-03): every v3.x run used stop-order entry, not entry-on-close
Discovered while debugging the SMC EA: the MT5 tester loads `MQL5\Profiles\Tester\TWISRSweepReclaim.set` and **overrides compiled defaults** (see [[MBT (MT5 Backtest Toolkit)]]). A cache written at 16:19 forced `EntryMode=1` (`ENTRY_STOP_ABOVE_CONFIRM`) through the v3.00, v3.10 and v3.20 runs, even though v3.00 changed the source default to `ENTRY_MARKET_ON_CONFIRM` to implement Adam's "BUY AT CLOSE".

**What actually ran:** a Buy/Sell Stop beyond the engulf candle plus `EntryBufferATR`, cancelled after `PendingExpiryBars` (6 M5 bars) if price never continued — an extra undocumented filter. `VALID ENTRIES` therefore counted *orders placed*, not fills, which is why it sometimes exceeded the report's `total_trades`.

**Still valid** (all computed before order placement): RR failures 8→1 under v3.10, no-target 6→4 under v3.20, the `penetration=0.00 ATR` finding, and every funnel count.
**Not valid as previously written:** v3.x trade counts, fills, P&L interpretation, and the entry-mechanics sections of the two baseline documents generated for those runs.

## v2 rewrite (2026-09-03, Adam's refined spec + real bug fixes)
Full rewrite after the first backtest's funnel diagnostics exposed the real problems, not guessed at:
- **Real bug fixed: `TrendTF` (H1) was a dead input.** v1 computed "trend" off `StructureTF` (M15) everywhere, including as the invalidation check re-run every single M15 bar — a normal pullback inside an intact trend read as "no trend" and killed 73% of qualified setups (confirmed via instrumented funnel counters, not assumption). v2 actually uses `TrendTF` for H1 bias, checked at the M15 and M5 stages, and only resets on a real bias flip — matching the original multi-timeframe intent (H1 direction / M15 structure / M5 entry) that v1 never actually implemented.
- Dropped the impulse-magnitude gate (`MinImpulseATR`) entirely per Adam's simplified spec — zone identification is now just "H1 bias + nearest M15 swing," no separate impulse-size filter.
- Sweep now has a **maximum** depth (`MaxSweepATR`, new) as well as the minimum — "sweep too deep" is a real skip condition, not just "sweep too shallow."
- Collapsed the old separate `WAIT_FOR_CONFIRMATION` stage (close beyond the sweep candle's high, up to 10 bars) into a strict **same-candle-or-next-candle** reclaim past the zone midpoint — matches Adam's literal spec, removes an entire multi-bar-timeout gate that was extra attrition beyond what he wanted.
- TP is now explicitly fixed at `FixedRR` (2R default) once the nearest-structure-target feasibility check (`MinRR`, 1.5R default) passes — not the structure target price itself. Matches Adam's own worked example exactly (Entry 3349.32, SL 3346.85, TP 3354.26 = precisely 2× the 2.47 risk).
- **Debug drawing added** (`DebugDraw`, on by default): every zone, breakout, pullback tag, sweep, reclaim, entry, and invalidation/timeout event is drawn directly on the chart (rectangles for zones, arrows/text for events) — so a run can be inspected visually, not just through counters.
- **Per-trade diagnostic log added** (`DebugTradeLog`, on by default): every sent trade prints a full `TRADE #N` block (H1 bias, M15 zone, breakout strength, pullback bars, sweep depth, reclaim close, entry/SL/risk/TP/RR) matching the format Adam specified, so a loss can be explained from the Journal instead of re-guessed.
- Funnel counters (`DebugStats`) kept and relabeled to match the new stage names (`h1Flip`, `pullbackTimeout`/`pullbackTag`, `sweepTooDeep`, etc).

## Funnel evidence so far (2026-09-03, XAUUSD.sim M5, Aug 1 – Sep 2, $400, every-tick)
All from instrumented counters printed by the EA itself, not inference. Same window every run, so these are comparable:

| Version | Trades | Dominant leak |
|---|---|---|
| v1 (M15 "trend" recomputed per bar) | 1 | `trendFlipReset` 83 of 113 qualified setups (73%) |
| v1 + structural-invalidation fix | 3 sent / 2 closed | `structInvalid` 75 of 117 (64%) |
| v2 (real H1 bias via `TrendTF`, collapsed confirmation) | 1 | `sweepTooDeep` 9 of 21 tagged (43%), then `skipRR` 3 of 4 valid sweeps (75%) |
| v2 + **cluster zones** (mismatch #1 fixed) | 3 | `sweepTooDeep` 9 + `insufficientRR` 5 = 14 of 19 tagged |

### Cluster-zone result (2026-09-03) — the fix works, confirmed by the funnel
Baseline for this run recorded at `mbt\reports\TWISRSweepReclaim_BASELINE_20260903_182536.md` (+ matching `.set`): source MD5 `8ce8e1b4fca5d5e801575ff8a70c4c04`, `.ex5` MD5 `001b21379c5f1edb83e5e073752e1d4e`. Report: `TWISRSweepReclaim_20260903_182536.htm`.

Cluster zones vs v2, identical window and every other setting unchanged:
- **No-liquidity-sweep timeouts 7 → 1 (−86%)** and **sweep+reclaim confirmed 4 → 8 (2×)** — the real signal. Wider, genuinely-touched levels get swept; one-candle slivers were being ignored by price.
- Valid entries 1 → 3 (byproduct, not the goal). Breakouts (35→36), retest tags (21→19), H1-flip rejects (26→25) essentially unchanged, which is what "changed zone construction only" should look like.
- "H1 bias windows 60 → 214" is **not** comparable: a zone failing the touch test now leaves the EA in search state to re-count next bar, so that line counts attempts. Zones armed = 60 in both.

**Zone quality is improved but still short of the source video's bands:**
- Many zones are bare-minimum `touches=2 | bars=2`; the video's are 5-8 bar consolidations. `MinClusterTouches=2` lets thin ones through (Adam's spec said "preferably 3 when available" — not yet enforced).
- Width clamps bind often (several zones sit exactly at the 0.60 ATR max, one at the 0.10 min).
- **Same level re-armed as multiple zones** (e.g. 4085.66/4083.80 logged at both 02:30 and 06:30; 4420.80/4419.67 at 14:15 and 15:45) — early evidence for the zone-lifespan item (#4).
- Good clusters do occur: `touches=9 | bars=13`, `touches=6 | bars=13`, `touches=4 | bars=9`.

**Results (n=3, not judgeable):** 0 wins / 3 losses, win rate 0%, avg loss −0.68R, all 3 long, net −$19.41. Avg loss below 1R means the breakeven/trail logic is cutting losers before full stop.

### v3.00 — engulf confirmation replaces the invented sweep-depth rule (2026-09-03)
Adam spotted from further video screenshots that the source strategy's entry trigger is a **bullish/bearish engulfing candle at the level, "ENTRY ON CLOSE"** — there is no measured ATR sweep depth anywhere in it. The 0.05–0.40 ATR penetration box was something this build invented, and it was killing 9 of 19 tagged setups. Adam's call: **keep the level-interaction requirement, delete only the measured-depth rule**, and test it before the swing-scale item. Baseline: `TWISRSweepReclaim_BASELINE_20260903_184311.md` / `.set`, source MD5 `3f260d7210added7f53e9a5102dc257f`, `.ex5` `6956c6a12a363b3d33619791ed411d3c`.

Changes (only these): `MinSweepATR`/`MaxSweepATR` removed as inputs entirely; confirmation is now a body-based engulf (`close2<open2 && close1>open1 && open1<=close2 && close1>=open2` for bull, mirrored for bear); reclaim test is now **close beyond the zone edge** (`close1 > ZoneHigh` / `< ZoneLow`), not the midpoint; SL sits beyond the two-candle rejection extreme + buffer. Penetration depth is still measured and logged per entry **for research only — it never rejects a trade**, so its predictive value can be tested empirically later instead of assumed.

| Stage | cluster build | v3 engulf |
|---|---|---|
| Zones armed | 60 | 56 |
| Detected M15 breakouts | 36 | 32 |
| Retest tagged | 19 | 16 |
| Confirmed (sweep+reclaim → engulf) | 8 | **10** |
| Insufficient RR | 5 | **8** |
| VALID ENTRIES | 3 | 2 |
| Wins / losses | 0 / 3 | 0 / 2 |
| Avg loss | −0.68R | −1.00R |
| Long / short | 3 / 0 | 1 / 1 |
| Net | −$19.41 | −$21.68 |

**Real findings:**
- **`Insufficient RR` now kills 8 of 10 confirmed setups (80%) — target selection is conclusively the dominant bottleneck.** `FindStructureTarget()` inspects only the last two swings, so right after a breakout it treats recently-broken structure or noise as the next opposing level. **Do not lower `MinRR`; fix the algorithm.**
- **6 of 10 confirmed engulfs had `penetration=0.00 ATR`** — price touched the zone and engulfed without piercing it at all. The old `MinSweepATR=0.05` floor was silently deleting the majority of valid setups. Hard evidence the invented rule was the wrong model.
- Shorts appeared (1 vs 0) — the old depth+midpoint combination was effectively long-biased on this data.
- Avg loss moved to exactly −1.00R (clean full stops) from −0.68R.
- Minor upstream drift (zones 60→56, breakouts 36→32) is **not** a logic change: a setup dying at a different bar returns the EA to search state at a different time, so a slightly different swing sequence gets evaluated. Perfect isolation isn't achievable in a sequential state machine.

**Next by evidence:** fix the structure-target algorithm. Then swing scale (#4), then impulse/pullback context (#3), then zone lifespan (#2).

### v3.10 — structure-target selection only (2026-09-03). Question answered.
Replaced `FindStructureTarget()` (last-two-swings) with a **zone registry**: every level the EA identifies is stored with id/type/high/low/created/broken, `broken` updated each M15 bar on a decisive close through it. Target = nearest valid unbroken opposing zone, excluding `ENTRY_ZONE` / `INVALIDATED` / `ALREADY_BROKEN` / `WRONG_SIDE` / `DUPLICATE`; TP at that zone's near edge ∓ `TargetBufferATR` (new input, 0.10 ATR, matching existing buffer convention). **No fallback** — no valid zone means the setup is rejected, never given an invented target. `MinRR=1.5` deliberately left active so the experiment isolated selection. Baseline `..._184311` files; report `TWISRSweepReclaim_20260903_190150.htm`.

| Stage | v3.00 | v3.10 |
|---|---|---|
| Engulf confirmed | 10 | 10 (frozen correctly) |
| Setups with target found | — | 3 |
| No valid structure target | — | **6** |
| Rejected max positions | 0 | 1 |
| **RR fail** | **8** | **1** |
| RR pass | 2 | 2 |
| VALID ENTRIES | 2 | 2 |
| Avg loss | −1.00R | −0.50R |
| Net | −$21.68 | −$11.87 |

**Confirmed:** the old last-two-swings algorithm was manufacturing artificially poor RR — failures collapsed 8 → 1. Adam's diagnosis was right; `MinRR` was never the problem.

**New bottleneck, and it's a design flaw in this build, not the market:** the registry is populated *only when a setup arms a zone* (56 zones in the month), so in a trend every recorded resistance below price is already `ALREADY_BROKEN`, and swing highs *above* price were never catalogued at all — the EA only ever remembers the one level it is actively trading. All 6 `NO_VALID_STRUCTURE_TARGET` events are bull setups during August's gold uptrend, exactly that signature.

**Next isolated experiment:** populate the registry from *every* cluster-built M15 swing level continuously (target **supply**), rather than only from armed setups. Distinct change from target *selection* — do not fold it in silently with anything else.

### v3.20 — persistent structure map (2026-09-03). Map works; the 1.5R gate is now the proven problem.
Separated **zone lifetime from setup lifetime**. Zones carry `ACTIVE/FLIPPED/BROKEN/INVALIDATED/MERGED` plus created/registered/originSwing/lastInteraction/breakTime/touches. Every M15 bar the just-confirmable swing bar (it has `SwingRightBars` *closed* bars after it) is checked and its cluster zone filed — both types, continuously, regardless of whether a setup is running. Invalidation now needs the **body** test as well as the buffer (a wick no longer retires a level). Near-identical levels **merge** (earliest creation kept, touches accumulated, geometry untouched). Report `TWISRSweepReclaim_20260903_191801.htm`.

| Stage | v3.10 | v3.20 |
|---|---|---|
| Engulf confirmed | 10 | 10 (frozen) |
| Target candidates considered | ~30 | **1139** |
| Setups with a target | 3 | **5** |
| No valid structure target | 6 | **4** |
| RR pass | 2 | **1** |
| RR fail | 1 | **4** |
| VALID ENTRIES | 2 | 1 |

**Lookahead audit: `FUTURE_ZONE` = 0.** Two independent guards (zones only built from swing-confirmable bars with closed bars after them; explicit `registered > entryTime` exclusion). No zone was ever targeted before it was legitimately known.

**The decisive finding.** Adam pre-registered the conditional: *if RR rejections stay at 70-80% even with properly selected zones, the 1.5R gate itself is incompatible with the source strategy.* **It did — 4 of 5 correctly-selected persistent structural targets fail RR (80%).** Actual planned RRs: **1.20 / 0.05 / 1.40 / 0.36 / 3.69**. Several are legitimate targets that simply sit nearer than 1.5R.

**Second finding: all 4 remaining no-target cases are `NO_TARGET_ALL_BROKEN`** — during August's gold uptrend every catalogued resistance genuinely had been broken. That is the market, not a bug: a rule demanding 1.5R of room to prior structure will structurally refuse trend continuation into blue sky.

**Two open strategy decisions (Adam's call, not parameter tuning):**
1. Remove `MinRR` as a gate while continuing to log RR — the experiment Adam pre-registered for exactly this result.
2. Blue-sky targeting needs a fallback that is *not* invented structure (measured move, swing projection, or fixed-R) for the `ALL_BROKEN` case.

**v2 funnel in full:** `trend=60 → breakoutWait=60 | h1Flip=26 breakoutTimeout=0 breakoutHit=35 | pullbackTimeout=13 pullbackTag=21 | sweepTimeout=7 sweepTooDeep=9 sweepHit=4 | skipRR=3 SENT=1`

**Adam's read (agreed, 2026-09-03):** the `skipRR` rejections are a **target-selection problem, not an RR problem** — `FindStructureTarget()` only inspects the last two swings, so right after a legitimate breakout it can mistake recently-broken structure or nearby noise for the next opposing level. **Do not lower `MinRR` (1.5) to fix this.** Fix the target-identification algorithm instead.

### Agreed fix order (Adam, 2026-09-03) — one change at a time, same test window, no parameter optimization until detection is right
1. **Cluster zones** (mismatch #1 vs the source video) — in progress.
2. **Meaningful swing scale** — M15 3/3 pivots currently flag every tiny wiggle as a level. Deliberately ordered *before* zone lifespan: letting bad zones persist would make things worse, so identify the right level first.
3. **Impulse/pullback context** — the video's real sequence is *impulse → consolidation/rejection cluster terminating that impulse → resistance*, not "swing high → resistance." v2 dropped the impulse gate entirely; it should come back as context for which levels are worth trading.
4. **Zone lifespan** — the video's zones extend forward until price returns; the EA's expire on bar-count timeouts.
Then: revisit the sweep-depth cap (test 0.40 → 0.60 → 0.80 ATR, **comparing expectancy, not trade count**), and fix the structure-target algorithm — before ever touching the 1.5R minimum.

## Status (2026-09-03: first backtest run, sample too thin to judge)
- Compiled clean on both terminals.
- **Not attached to any chart.**
- First real backtest (RisenMOM, `XAUUSD.sim`, M5, every-tick, 2026-05-01→09-02, $400 deposit): **only 3 total trades in 4 months.** Net +$34.86, PF 175.3, Sharpe 3.32 — **not meaningful at n=3**, one loss flips all of it. The state machine's own strictness (trend + impulse + breakout + retest + sweep + reclaim all required) is why setups are this rare, not a bug per se.
- **Real anomaly flagged, not yet explained:** `balance_dd_max` 0.13% vs `equity_dd_max` 16.15% on the same run — one trade carried a large floating loss before closing favorably. Check that specific trade in the report before trusting the SL/management logic.
- **Real next step:** re-run over a much longer window (1yr+) and on EURUSD too, to get an actual sample size before judging whether the edge is real. Report: `C:\Users\Administrator\mbt\reports\TWISRSweepReclaim_20260903_160916.htm`.

## Related
- [[Active Priorities]]
- [[Chart Analysis Notes]]
