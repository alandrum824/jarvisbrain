---
status: active
project: forex-trading
type: reference
---
# TWI 9AM CR Model EA

New MQL5 EA (`TWI 9AM CR Model EA.mq5` / compiled as `TWI9AMCRModelEA.mq5`), built 2026-09-02 from Adam's full first-principles spec: a 9AM "Central Range" liquidity-reversal model, explicitly **not** an opening-range breakout EA.

## Central rule
We are not predicting which direction the 9AM session goes. The EA waits for price to raid one boundary of the completed 8:00-9:00 AM New York H1 candle, then requires real evidence the raid failed (M1 close-back, displacement, an inverted FVG, a retrace/reject) before trading toward the *opposite* boundary. A break of the 8AM High/Low is never itself a signal.

## Source location
- Vault master copy: `02 - Forex Trading/TWI 9AM CR Model EA.mq5`
- Deployed (not attached) to RisenAdam and RisenMOM: `MQL5/Experts/Advisors/TWI9AMCRModelEA.mq5`
- Compiled clean via `MetaEditor64.exe` CLI on both terminals: **0 errors, 0 warnings**, first pass

## Sequence (state machine)
`WAIT_FOR_8AM_RANGE → WAIT_FOR_SWEEP → HIGH_SWEPT/LOW_SWEPT → WAIT_FOR_DISPLACEMENT → WAIT_FOR_IFVG → WAIT_FOR_RETRACE → WAIT_FOR_ENTRY_CONFIRMATION → TRADE_ACTIVE → DAY_COMPLETE`, exactly as specified, driven off closed M1 bars only.

1. At/after 9:00 AM NY, lock the 8-9AM H1 candle's high/low as the range.
2. Watch M1 for a sweep beyond either boundary (`MinimumSweepPoints`, capped by `MaximumSweepDistance`/`MaximumSweepATR` so a runaway breakout doesn't get faded).
3. Require a close back inside the range (`RequireCloseBackInsideRange`, with `SweepConfirmationCandles` bars to do it, `AllowDisplacementWithoutImmediateReclaim` as an escape hatch).
4. Require real displacement in the reversal direction: body ≥ `DisplacementBodyMultiplier` × the average of the last `DisplacementLookback` M1 bodies, and ≥ `MinDisplacementPoints` in absolute terms.
5. Track M1 FVGs (3-candle gaps, `MinFVGPoints` floor) through a real lifecycle (ACTIVE → PARTIALLY_FILLED → INVERTED), and only trade an **inverted** FVG matching the trade direction, formed after the sweep bar (`IFVGLookbackBars` window) — see the IFVG explanation below.
6. Wait for a retrace into that IFVG, then confirm per `EntryMode` (default `IFVG_REJECTION_CLOSE`).
7. Enter, SL beyond the sweep extreme + `StopBufferPoints`, TP at the opposite 8AM boundary by default (`TargetMode`).

## Real guardrails included
- Setup quality score (0-100, `MinimumSetupScore` gate, shown live on the dashboard).
- RR filter (`MinimumRR`, default 2.0) — computed and logged before every entry, trade rejected below threshold.
- Risk-based lot sizing (equity × `RiskPercent`, normalized to the symbol's real tick value/size/volume step — works across FX, XAUUSD, indices).
- Daily protection: `MaxDailyLossPercent`, `MaxDailyTrades`, `MaxLossesPerDay`, `StopAfterDailyProfitPercent`, `MaximumOpenRiskPercent`.
- One trade per 8AM side by default (`MaximumTradesPer8AMSide`), no automatic flip to the other side after a loss unless `AllowOppositeSideTradeAfterLoss` is explicitly on.
- Optional 8AM-range size filter, optional high-impact-news filter (gracefully no-ops if the calendar API is unavailable rather than blocking the EA).
- Four management modes (`FULL_TP` default, `BE_AT_1R`, `PARTIAL_AT_1R`, `STRUCTURE_TRAIL`).
- No martingale, no grid, no averaging into losers, no lot multiplication after losses — none of that logic exists anywhere in the file.
- Full dashboard + `[HH:MM] event` style Strategy Tester logging, including explicit `NO TRADE: <reason>` lines for every rejected setup.

## Explanation (per Adam's spec)

**1. Entry logic.** Never on the raw sweep. Sweep → close back inside the range → real displacement candle → an FVG formed during/after that reversal that later gets **inverted** by price closing through it against its original bias → retrace into that inverted zone → rejection confirmation (mode-dependent) → market entry toward the opposite 8AM boundary.

**2. IFVG detection logic (the part worth being precise about).** Every 3-candle M1 FVG found is stored with its original bias (bullish/bearish) and starts `ACTIVE`. On every new closed bar, if price closes back *through* that zone against its original bias (a bullish FVG's close drops below its bottom, or a bearish FVG's close rises above its top), it flips to `INVERTED` and its *tradeable* role becomes the opposite of its original bias. For a short setup we only ever look at IFVGs whose inverted role is **bearish** (now resistance) and that formed at or after the sweep bar — so a leftover FVG from earlier in the session never gets used. This means the entry zone is very often a bullish FVG left behind on the way *up* into the sweep, which the bearish displacement leg then closes through and inverts into resistance for the retrace-and-reject short. Mirror logic for longs.

**3. Stop-loss logic.** `SL = SweepExtreme ± StopBufferPoints` — always the real structural sweep high/low from this specific setup, never a fixed arbitrary pip stop.

**4. TP logic.** Default `OPPOSITE_8AM_RANGE`: the 8AM Low for shorts, the 8AM High for longs — the model's whole premise is a round trip across the range. `FIXED_RR` and `NEAREST_LIQUIDITY` (currently aliased to the same opposite-boundary logic — real nearest-swing-liquidity targeting wasn't built out separately, flagged as a real gap below) are the alternate modes.

**5. Timezone handling.** Every decision runs on New York wall-clock time, computed independently of the broker's own server timezone via `BrokerGMTOffset` (set once for your broker) plus a real US DST calculation (2nd Sunday of March 07:00 UTC → 1st Sunday of November 06:00 UTC) when `AutoDetectDST` is on, or a fixed `ManualNYOffsetHours` when it's off. The 8-9AM H1 bar is located by converting NY 08:00/09:00 to the broker's real clock and calling `iBarShift` — verified against a 30-minute tolerance and logged if the alignment looks wrong (a sign `BrokerGMTOffset` is mis-set).

**6. Risk calculation.** `lots = (equity × RiskPercent/100) ÷ (SL distance in ticks × tick value)`, floored to the symbol's real `SYMBOL_VOLUME_STEP` and clamped to `SYMBOL_VOLUME_MIN`/`MAX` — the same pattern already validated in [[TWI OB Hunter]] and [[TWI Scalp Pro]], works correctly across FX pip value, XAUUSD, and index contract specs since it reads the real tick value/size per symbol rather than assuming pips.

**7. Inputs to optimize first.** `MinimumSweepPoints`, `DisplacementBodyMultiplier`, `MinFVGPoints`, `MinimumSetupScore`, and `MinimumRR` are the ones most likely to gate whether this ever fires cleanly at all — start there before touching risk or management-mode inputs.

**8. Backtesting it correctly.** Use `every_tick` (not `open_prices` or a lower-fidelity model) — this EA reacts to intrabar wicks (sweeps) and body-close confirmations, exactly the kind of logic a coarse tick model can fake false signals for, per the real lesson already learned tonight on [[TWI VWAP Drift Pullback]]. Every detection function in this EA only ever reads `shift >= 1` (closed bars) — never the live-forming bar 0 — so there is no lookahead/repaint risk built in regardless of tick model, but the *fidelity* of the simulated sweep wicks still depends on tick model choice.

## Real gaps, honestly
- `NEAREST_LIQUIDITY` target mode is not separately implemented — it currently behaves identically to `OPPOSITE_8AM_RANGE`. Flagged rather than faked.
- No backtest has been run yet — next real step, same as everything else built tonight: run it on the account's actual pairs/gold via `run_strategy_tester`, `every_tick`, and read the real numbers before trusting any of this.
- Not attached to any chart on either terminal.
