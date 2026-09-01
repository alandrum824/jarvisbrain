---
status: active
project: forex-trading
type: reference
---
# TWI OB Hunter

New MQL5 EA (`TWI OB Hunter.mq5` / compiled as `TWIOBHunter.mq5`), built 2026-08-31 from Adam's request: an ICT/SMC-style order block + liquidity hunting EA.

## Source location
- Vault master copy: `02 - Forex Trading/TWI OB Hunter.mq5`
- Deployed (not attached) to RisenAdam: `MQL5/Experts/Advisors/TWIOBHunter.mq5`
- Compiled clean via MetaEditor64 CLI: **0 errors, 0 warnings**

## Logic
Per direction (bullish/bearish), a small state machine on a configurable `StructureTF` (default M15):
1. **Swing tracking** — fractal swing highs/lows (`SwingLookback` bars each side) kept in a rolling buffer (`MaxSwingPoints`).
2. **Liquidity sweep** — a bar wicks beyond a recent swing level by at least `SweepMinATRmult` × ATR but closes back on the other side (stop-hunt confirmed).
3. **BOS (break of structure)** — within `MaxBarsForBOS` bars, price closes through the opposite-side recent swing, confirming the reversal is real displacement, not noise.
4. **Order block** — the last opposite-colour candle before the displacement leg that caused the BOS. Its high/low become a zone (drawn on chart if `ShowZones`).
5. **Entry** — market order when price retraces back into the zone. One-shot per zone by default (`OnePerZone`). SL beyond the zone edge + ATR buffer; TP is either a fixed R-multiple (`RR_Multiplier`) or the nearest opposite unswept liquidity level (`UseLiquidityTP`).

Also has: fixed or %-risk dynamic lot sizing (same `CalcLot` pattern as [[TWI Scalp Pro]]), max concurrent trades, optional day-of-week/session-hour filter, zone expiry (`MaxOBAgeBars`), and a cap on how many zones stay active at once (`MaxActiveOBs`).

## Status (2026-09-01)
- Compiled clean, deployed to RisenAdam's Experts folder. Not attached to any live chart.
- **Real backtest run 2026-09-01 ~00:03-00:04** (full year, 2025.09.01-2026.08.28, XAUUSD M15, $10,000 sim deposit): ran clean twice, ~1.5-1.7s each, no hang — the earlier "backtest blocked, terminal conflict" note above no longer applied by this point. **Zero trades both runs, final balance unchanged at $10,000.00.** Log shows the sweep-detection stage firing constantly ("liquidity swept... watching for BOS") but never a single BOS confirmation or order-block-created event across the entire year.

### Real bug found and confirmed from source (2026-09-01)
`FindLastCandle()` (line 295) is called as `FindLastCandle(1, 1 + MaxBarsForBOS, true/false)` — i.e. `fromShift=1`, `toShift=9` (with the default `MaxBarsForBOS=8`). But the function body is:
```
for(int s = fromShift; s >= toShift; s--)
```
Starting at `s=1` and requiring `s >= 9` while decrementing — the loop condition fails on the very first check, every single time. `FindLastCandle` therefore **always returns -1**, `if(obShift >= 0) AddOrderBlock(...)` never runs, `obList` never gets a zone added, and `TryEnterZones()` has nothing to ever fill. This is a complete, structural block on every trade the EA could ever take — not a tuning issue, not a filter, not a market-conditions problem. Every BOS confirmation the state machine reaches (lines 364-396) is silently thrown away at the order-block step, and there's no log line on that path so the sweep messages are the only visible symptom.

**Fix (not yet applied — needs Adam's go-ahead before touching source):** the loop direction is backwards relative to how it's called. Change line 297 from `for(int s = fromShift; s >= toShift; s--)` to `for(int s = fromShift; s <= toShift; s++)` so it actually walks forward from the sweep bar out to the BOS-confirmation window.
- No parameter defaults have been validated against real data yet — can't happen until this bug is fixed, since no trade has ever fired to validate against.

### Fix applied and validated (2026-09-01)
Adam confirmed ("go"). Fixed both the vault master copy and the deployed `MQL5\Experts\Advisors\TWIOBHunter.mq5`, recompiled via MetaEditor64 CLI — 0 errors, 0 warnings. Headless re-test via the MCP tester tool silently no-op'd twice (RisenAdam terminal was live and connected — same conflict as the original "backtest blocked" note), so Adam ran it himself directly in the terminal's Strategy Tester (visual mode), default inputs, XAUUSD M15, 2025.09.01-2026.08.28, $10,000 sim deposit. Confirmed via his own screenshots:

- **The equity curve now actually moves** — real order-block zones drawing on chart, real trades firing, curve climbing from $10,000 toward ~$10,300+ over the run, instead of the dead-flat $10,000 line the bug produced.
- **Real report numbers:** Total Net Profit **+$257.49**. Gross Profit $1,275.42 / Gross Loss -$1,017.93. **Profit Factor 1.25**. History Quality 99% (23,446 bars, 1.4M ticks).
- Default config as run: `MagicNumber=20260831, StructureTF=15, SwingLookback=3, MaxSwingPoints=8, ATRPeriod=14, SweepMinATRmult=0.1` (matches shipped defaults).
- **Trade-level stats (from Adam's screenshot):** 241 total trades (482 deals). Win rate 51.04% (123 wins / 118 losses). **Long trades won 54.14% (133 taken) vs short trades only 47.22% (108 taken)** — a real asymmetry, long side notably stronger. Largest profit trade $116.06 vs largest loss -$55.12; average profit trade $10.37 vs average loss -$8.63 — real positive per-trade asymmetry backing the 1.25 profit factor. Max consecutive losses: 6 trades. Not a huge sample (241 trades/year ≈ 4-5/week) but healthy shape for a first untuned pass.

**Read: real, positive, but thin edge (PF 1.25) on untuned default parameters, from the very first trade this EA has ever taken.** Not a candidate for live deployment yet — same standard applied elsewhere in this vault (see [[ZeroPoint]], parked despite Sharpe 0.94) — this needs the parameter sweep below and a proper drawdown/robustness read before that conversation.

### Correction (2026-09-01, same session) — the +$257.49 result doesn't hold under a real tick model
Adam ran the identical test again (same inputs, same symbol/period) and this run shows **186,409,554 ticks** against the same 23,446 bars — vs. **1,405,276 ticks** in the first run above. Same bar count, ~130x the ticks: the first run used a low-fidelity tick-generation mode, this one a genuine high-fidelity "every tick" simulation. For a sweep/wick-based EA like this, tick fidelity isn't a minor detail — it's reacting to intrabar price action, and a coarse model can manufacture sweep signals that wouldn't happen against real ticks.

**Under the accurate model: Total Net Profit -$51.27, Gross Profit $1,174.41 / Gross Loss -$1,225.68, Profit Factor 0.96, Sharpe -0.18.** A net loser, not a winner. Drawdown stayed small either way (equity max 2.76%, balance max 2.67%), so the fix didn't introduce a blowup risk — it just isn't a profitable strategy as currently tuned. **The earlier "+$257.49 / PF 1.25" read was a false positive from the low-fidelity run and should not be relied on.** Bug fix confirmed working (real trades firing, real order blocks) — but "working" and "profitable" are separate questions, and this EA has only answered the first one so far.

## Next steps
- Pull the full exported report (drawdown %, win rate, trade count, max consecutive losses) rather than reading it off a phone photo — export via the terminal's Results tab, or get a headless run working once RisenAdam's tester slot is free.
- Sweep `SweepMinATRmult`, `MaxBarsForBOS`, and `RR_Multiplier` now that real trade data exists — these are the parameters most likely to need tuning.
- Revisit the MSS/IDM architecture question flagged 2026-09-01: the EA's sweep→BOS check doesn't distinguish an internal/inducement swing from a true structural one, unlike the standard ICT sweep→MSS→IDM→BOS sequence Adam referenced. Worth knowing whether the false-positive rate here is meaningfully hurting the profit factor before building it.
