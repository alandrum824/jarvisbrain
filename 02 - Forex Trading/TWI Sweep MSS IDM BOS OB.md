---
status: active
project: forex-trading
type: reference
---
# TWI Sweep MSS IDM BOS OB

TradingView Pine Script v6 indicator (`//@version=6`), built 2026-09-01 from Adam's own ICT/SMC reference diagrams: plots the full **Sweep → MSS → IDM → BOS → Order Block → Accumulation → Target** sequence directly on the chart.

## Where it lives
- Saved to Adam's TradingView account as script name **"TWI Sweep MSS IDM BOS OB"** (internal script id `USER;a4a888ded0eb4c9e94602ea09e357a6e`), indicator title `TWI Sweep-MSS-IDM-BOS-OB`.
- **Live on chart** — Adam manually applied it to OANDA:XAUUSD, 15m, 2026-09-01. Confirmed visually firing SWEEP, MSS, IDM, BOS labels, an ORDER BLOCK box, and a TARGET line in real time.

## Note on how this script's slot was created
This reused an existing saved script slot that was previously **"TWI HTF Zone Sniper"** (a two-stage HTF Stochastic/chart-RSI reversal system Adam had built earlier) — `pine_new` did not actually detach from the currently-open script before the source got injected and saved, so that prior script's code was overwritten. **Adam confirmed this was fine, no recovery needed.** Renamed the script slot afterward to avoid the stale "TWI HTF Zone Sniper" label sitting on unrelated content. If "TWI HTF Zone Sniper" is ever wanted back, it is not recoverable from this vault — nothing of its source was captured before the overwrite.

## Logic (translated from ICT concepts, not from the TWI OB Hunter EA — has real differences)
1. **Swing tracking** — major structure via `ta.pivothigh`/`ta.pivotlow` (`swingLen`, default 3), separate fast (1,1) pivots for MSS/IDM detection.
2. **Sweep** — a bar wicks past a recent unswept major swing by `sweepMinATRmult × ATR` and closes back inside.
3. **MSS** — first fast-pivot break in the reversal direction after the sweep.
4. **IDM** — the next fast pivot in the *continuation* direction after MSS (the inducement pullback point).
5. **BOS** — close breaks the original major structural level the sweep was anchored to.
6. **Order Block** — last opposite-colour candle before the BOS leg (scanned backward from the BOS bar, nearest match wins).
7. **Accumulation** — watches forward after BOS for price to stay within an ATR-buffered band around the OB for `minAccumBars`; draws the zone once confirmed.
8. **Target** — nearest unswept opposite-side major swing beyond the BOS level, drawn as a dashed line + label.

This is a genuinely more complete implementation of the diagram than [[TWI OB Hunter]]'s MQL5 EA — that EA has no MSS/IDM stage at all (flagged as an open gap in its own note). Worth comparing behavior between the two if Adam wants to bring that distinction back into the EA.

## Status
Visually confirmed working (real labels/zones drawn, matches the reference diagram's sequence). **Not backtested, not validated for signal quality or win rate** — this is a visualization/study tool right now, not a strategy with performance numbers behind it, unlike [[TWI OB Hunter]] which has real (if currently unprofitable) backtest data. Treat any resemblance between the two as coincidental until someone actually measures this one.

## Related
- [[TWI OB Hunter]] — the MQL5 EA version of a similar sweep/OB concept, missing the MSS/IDM stages this indicator has.
- [[TWP ORB EA Reference]]
