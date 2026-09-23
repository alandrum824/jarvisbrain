---
status: active
project: forex-trading
type: reference
---
# TWI Liquidity Sweep BOS

MQL5 EA built 2026-09-22 from Adam's one-line spec: **liquidity level → sweep → close back inside → BOS → retracement → entry → SL beyond sweep → TP at liquidity / fixed R:R.**

## Source location
- Vault master copy: `02 - Forex Trading/TWI Liquidity Sweep BOS.mq5` (written before anything touched the terminal)
- Deployed **(not attached)** to the live AAAFx/RisenAdam terminal: `MQL5/Experts/Advisors/TWILiquiditySweepBOS.mq5`
- **Compiled clean via MetaEditor64 CLI: 0 errors, 0 warnings** (1252 ms). `.ex5` verified present, 62,316 bytes.

## Why this is a new EA and not a duplicate
Checked against the three existing sweep-flavoured builds before writing a line — the sequence is genuinely different in each:

| Build | Sequence | Form |
|---|---|---|
| [[TWI SR Sweep Reclaim]] | trend → S/R zone → **breakout** → retest → sweep → engulf → entry | EA |
| [[TWI BOS Trap Entry]] | **BOS first** → order block → inducement → sweep of the IDM → tap the OB | Pine indicator |
| **This one** | **sweep first** → reclaim → BOS → retracement → entry | EA |

The distinguishing stage is **BOS-then-retracement**. SR Sweep Reclaim enters immediately on an engulf at the level; this one requires structure to actually break after the raid, then waits for the pullback. That's the classic ICT/SMC reversal model and nothing in the vault implemented it as an EA.

## Logic (bearish case; bullish mirrored)

State machine, closed bars only, evaluated once per new bar — nothing can repaint.

1. **Liquidity level registry.** Confirmed fractal pivots (`SwingLeftBars`/`SwingRightBars`, only registered once `SwingRightBars` closed bars exist after the pivot). Near-equal levels **merge** within `EqualLevelATRmult` × ATR and accumulate a `touches` count, so equal highs/lows — where stops actually rest — register as one strong level instead of three weak ones. Levels are built **continuously**, not only when a setup is running: that decoupling of zone lifetime from setup lifetime is the fix that made SR Sweep Reclaim's target selection work at all (v3.20).
2. **Sweep.** A closed bar's *wick* trades beyond the level. The level is retired as `LEVEL_BROKEN` (not swept) if a decisive **body** close clears it by `LevelBreakATRmult` — a wick never retires a level, and that distinction is the entire strategy. Among levels swept on the same bar it picks the strongest pool (most touches), nearest as tie-break.
3. **Close back inside.** Same bar, or within `MaxReclaimBars`. No reclaim means it was a breakout, not a raid — setup dies.
4. **BOS.** The most recent confirmed swing on the opposite side of the sweep becomes the protected swing; a close through it confirms the shift. If price takes out the sweep extreme again before that happens, the raid failed and the setup is killed.
5. **Retracement.** Three modes — `RETRACE_FIB` (default, fib of the BOS leg, re-anchored live while the impulse is still extending), `RETRACE_FVG` (the fair value gap inside the impulse), `RETRACE_OB` (last opposing candle before the impulse, full range or body-only).
6. **Entry.** `ENTRY_ZONE_TOUCH` (wick tap) by default, or `ENTRY_CONFIRM_CLOSE`.
7. **SL** beyond the sweep extreme + `StopBufferATRmult`. **TP** via `TARGET_HYBRID` (default): nearest unswept opposing liquidity if it offers ≥ `MinRR`, otherwise fall back to fixed R:R rather than refusing the trade.

Risk-based lot sizing off `RiskPercent` with broker min/max/step clamping, `SYMBOL_TRADE_STOPS_LEVEL` guard before every send, one position per symbol. No grid, no martingale, no averaging.

## Defaults set from prior evidence, not taste

These are the four places where an earlier TWI build already paid the discovery tax, so this one starts where that one finished:

- **`MinSweepATRmult = 0.0`.** SR Sweep Reclaim v3.00 proved a minimum sweep-depth rule was invented — **6 of 10 otherwise-valid setups penetrated the level by exactly 0.00 ATR**, and the 0.05 floor was silently deleting the majority of them. Depth is still measured and printed on every trade, so its predictive value can be tested empirically later instead of assumed. `MaxSweepATRmult` is kept (2.0) because a *too-deep* sweep genuinely is trend continuation — that guard earned its place in TWI OB Hunter and TWI AMD iFVG.
- **`EntryMode = ENTRY_ZONE_TOUCH`.** TWI BOS Trap Entry measured wick-tap at **+0.211R over 270 trades vs +0.169R over 213** for close-confirmation, better on 5 of 7 datasets.
- **`TargetMode = TARGET_HYBRID` with `MinRR = 1.0`.** SR Sweep Reclaim v3.20 pre-registered this exact question and answered it: with *correctly* selected persistent structural targets, a hard 1.5R gate still rejected **4 of 5** setups, and all remaining no-target cases were genuine blue sky in a trend. So the gate is lowered and given a fixed-RR fallback instead of refusing the trade.
- **`BreakevenR = 0.0` and `TrailStartR = 0.0` — management OFF by default.** SR Sweep Reclaim's early runs showed avg loss −0.68R instead of −1.00R because BE/trail were cutting losers early, which muddies every R statistic in the report. Measure the raw edge first, then switch management on as a deliberate, isolated experiment.

`UseHTFBias` also ships **off**. This is a reversal model by construction, so a trend filter fights it — but BOS Trap Entry's momentum gate turned out to carry that strategy's entire edge, so this is the single most interesting thing to test first.

## Diagnostics
- **Funnel counters** printed on deinit: levels registered → sweeps → too deep / no reclaim → reclaims → no protected swing / BOS timeout → BOS → no zone / retrace timeout → taps → confirm timeout / invalidated / bias / stops-level / max-positions → ENTRIES. Every prior TWI EA needed exactly this to find where setups were dying; it's built in from v1.
- **Per-trade block** (`DebugTradeLog`): direction, liquidity level + touch count, sweep extreme + depth in ATR, protected swing, retrace zone and which mode built it, entry/SL/risk/lots, TP with RR and **which rule produced the target**.
- **Chart drawing** (`DebugDraw`) for level / sweep / protected swing / zone, suppressed in the tester.

## Status (2026-09-22)
- **Compiled clean, deployed to the live terminal, NOT attached to any chart.**
- **Zero backtests. No evidence of any kind yet** — nothing here has been measured, and every default above is inherited reasoning from other strategies, not a result on this one.
- **Real next step: a backtest on a long window before judging anything.** Per [[MBT (MT5 Backtest Toolkit)]], read the input dump at the top of the tester log first and confirm the values match intent — `MQL5\Profiles\Tester\TWILiquiditySweepBOS.set` will silently override compiled defaults, which cost a full evening on two earlier EAs.

## Related
- [[TWI SR Sweep Reclaim]] — where the no-invented-sweep-depth, persistent-registry, and RR-gate findings come from
- [[TWI BOS Trap Entry]] — where the wick-tap and momentum-gate evidence comes from
- [[TWI Sweep MSS IDM BOS OB]] — the SMC concept note for this family of sequences
- [[MBT (MT5 Backtest Toolkit)]] — the tester `.set` cache trap
- [[Active Priorities]]
