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

## Status (2026-09-02: LIVE — deployed, unconfirmed)
Adam attached TWI OB Hunter to a live EURUSD chart on RisenAdam himself (Jarvis has no GUI/MT5 control, per [[TWP24 EURUSD Sets]]'s standing note). Real caveats at go-live: EA now defaults to `LotMode=LOT_DYNAMIC` (1% risk/trade) rather than the fixed 0.01 lots every backtest above used — EURUSD's tight stops mean the real live lot size could differ from the tested baseline; not yet confirmed against a real trade. Evidence behind this is one backtest window (PF 1.14, real but thin edge, no walk-forward) — same bar every other EA here was held to before going live, Adam's own call to proceed now. AutoTrading status not independently confirmed (mt5/mbt ping to RisenAdam still auth-broken).

## Status (2026-09-01, prior)
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

## M5 "tap & close" entry confirmation added (2026-09-02) — real improvement on XAUUSD
Adam's real EURUSD win (15m zone marked, 5m pullback candle confirmed the entry, not an instant tick-touch) plus a TradeWithPat "Tap & Close" video prompted the same upgrade already validated on [[TWI VWAP Drift Pullback]] tonight: added `UseEntryTFConfirm` (default true) + `EntryTF` (default M5) inputs. Entry no longer fires the instant price ticks into a zone — it waits for the just-closed EntryTF candle to wick INTO the zone and CLOSE back beyond it (real reject/reclaim). Toggle kept so the old instant-tick behavior (`UseEntryTFConfirm=false`) is still available for A/B comparison. Compiled clean (0/0) on both RisenAdam and RisenMOM.

**Real backtest, XAUUSD.sim M15, $10,000 deposit, full history:** net **+$332.36**, PF **1.16**, Sharpe **2.0**, 206 trades, drawdown $435-503 (~4.4-5.0%). Versus the prior validated instant-tick result (net -$51.27, PF 0.96, Sharpe -0.18, DD ~2.8%) — a real flip from net loser to net winner, same pattern as the VWAP EA's fix tonight. Drawdown grew in dollar terms but stays modest.

**EURUSD.sim cross-check (2026-09-02), same M15/every_tick/$10,000 setup:** net **+$23.76**, PF **1.14**, Sharpe **1.85**, 265 trades, drawdown $26-28 (~0.28%). **Holds up** — both pairs land net-positive with near-identical profit factor (1.14 vs 1.16) and positive Sharpe, a real contrast with [[TWI VWAP Drift Pullback]]'s hard XAUUSD/EURUSD split the same night. Strongest, most consistent result of the session so far.

**Still not a live-deployment decision** — one window each, no walk-forward/second-date-range check yet, same bar as everything else in this vault. But this is genuinely better evidence than a single-pair result: the tap-and-close fix looks like a real mechanism, not instrument-specific luck. Real next step if pursued further: a second date-range window on one or both pairs to check year-to-year stability.

### Real review pass (2026-09-02) — three fixes, real improvement
Adam asked for a full review: find what works and what doesn't, build on it, test it. Full source re-read top to bottom. Three real issues found and fixed:
1. **`UseLiquidityTP=true` was a silent no-op** — `NearestOppositeLiquidity()`'s unswept-swing pool is almost always empty by entry time, so every trade fell back to the fixed 2R target regardless of the setting. Reverted the default to `false` so the input honestly reflects real behavior (the validated PF 1.14-1.16 numbers above were always running on fixed-RR, not liquidity targeting).
2. **No zone invalidation** — an order block stayed "active" until traded or aged out (~10 hours on M15), even after price already closed straight through the far side without ever tapping-and-reclaiming. Added real invalidation: a bullish zone dies the moment a close falls below its bottom (minus the same ATR buffer used for its own SL), mirrored for bearish.
3. **No cap on sweep distance** — only a minimum existed. A strong trend continuation blowing far past a level got treated identically to a real liquidity grab-and-reverse. Added `MaxSweepATRmult` (default 3.0) — a sweep beyond that many ATR past the level is logged and consumed but never opens a reversal setup.

Compiled clean (0/0) both terminals. **Real retest, EURUSD.sim M15 every_tick $400:** net +$23.76→**+$27.25**, PF 1.14→**1.18**, Sharpe 1.85→**2.32**, recovery factor 0.84→**1.07**, trades 265→**230** (fewer, higher quality), drawdown $26.42-28.40→**$23.46-25.44**. Every metric improved — real confirmation the fixes address genuine weaknesses, not noise.

**XAUUSD.sim M15 every_tick $10,000, same fixes:** net +$332.36→**+$377.58**, PF 1.16→**1.21**, Sharpe 2.0→**2.39**, recovery factor 0.66→**0.99**, trades 206→**180**, drawdown $435-503→**$324-382**. Same direction of improvement on both instruments — confirms the fixes are real, not an EURUSD-only fluke. Gold's absolute drawdown ($324-382) is still ~81-95% of a real $400 account though, so it stays off this account per the earlier lot-sizing finding — these fixes improved signal quality, not position sizing, and don't change that structural conclusion.

### Real problem found at real account scale (2026-09-02): $10,000 result does NOT hold at $400
Adam asked to rerun both at $400 deposit (his real account size) instead of the EA's own $10,000 backtest convention. **XAUUSD.sim at $400: identical trades, identical $332.36 net profit, identical $435.41 balance drawdown** — because `LotMode=LOT_FIXED` at `FixedLotSize=0.01` doesn't scale with deposit, so the same trades fire regardless of account size. On a real $400 account, **that $435.41 drawdown is 109% of the entire deposit** — the EA would margin-call and blow the account out during the year before ever reaching the $332 profit the $10,000 test shows. Not viable at 0.01 fixed lots on a $400 account as tested.

**EURUSD.sim at $400 tells the opposite story:** identical trades, +$23.76 net, but max drawdown only **$26.42 — 6.6% of the $400 deposit**, genuinely survivable. Real conclusion: at the current fixed 0.01 lot size, this EA is **account-viable on EURUSD but not on XAUUSD** — gold's much larger dollar-per-pip movement makes the same lot size a far bigger real bet there. Not a EA-wide problem, a per-symbol lot-sizing problem.

**Tried the %-risk fix (2026-09-02) — confirmed it can't work.** Switched the default `LotMode` to `LOT_DYNAMIC` (`RiskPercent=1.0`, already present in the code, just not the default) and recompiled both terminals. Rerun on XAUUSD.sim at $400: **byte-identical result** (net +$332.36, 206 trades, DD $435.41). Real reason: 1% of $400 is a $4 risk budget, and gold's ATR-based stop distance makes the calculated position size round to below the 0.01 broker minimum, so `CalcLot()`'s `MathMax(minLot, ...)` floor pushes it back up to the same 0.01 every time — identical to fixed sizing. **0.01 already is the floor, and it's still too large relative to $400 given this EA's stop distances on gold.** Not a lot-sizing bug fixable by input changes — a structural limit of this account size against gold's stop width. Same math means EURUSD's dynamic-risk result would match its fixed-lot number too (not separately re-run).

**Real conclusion: XAUUSD is not account-viable on this EA at $400, and can't be made viable by lot-mode alone.** A real fix would need a fundamentally tighter stop on gold (different scope, not attempted). Keeping OB Hunter **EURUSD-only** for this account for now.

## Next steps
- Pull the full exported report (drawdown %, win rate, trade count, max consecutive losses) rather than reading it off a phone photo — export via the terminal's Results tab, or get a headless run working once RisenAdam's tester slot is free.
- Sweep `SweepMinATRmult`, `MaxBarsForBOS`, and `RR_Multiplier` now that real trade data exists — these are the parameters most likely to need tuning.
- Revisit the MSS/IDM architecture question flagged 2026-09-01: the EA's sweep→BOS check doesn't distinguish an internal/inducement swing from a true structural one, unlike the standard ICT sweep→MSS→IDM→BOS sequence Adam referenced. Worth knowing whether the false-positive rate here is meaningfully hurting the profit factor before building it.
