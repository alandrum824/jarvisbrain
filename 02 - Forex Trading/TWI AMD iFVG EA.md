---
status: active
project: forex-trading
type: reference
---
# TWI AMD iFVG EA

New MQL5 EA (`TWI AMD iFVG EA.mq5` / compiled as `TWIAMDiFVGEA.mq5`), built 2026-09-02 from a "Trades By Slade" TikTok Adam shared: Accumulation → Manipulation → Distribution, entered off an inverted Fair Value Gap. Built as its own separate EA (Adam's explicit call, not folded into [[TWI OB Hunter]]).

## Source location
- Vault master copy: `02 - Forex Trading/TWI AMD iFVG EA.mq5`
- Deployed (not attached) to RisenAdam and RisenMOM: `MQL5/Experts/Advisors/TWIAMDiFVGEA.mq5`
- Compiled clean via `MetaEditor64.exe` CLI on both terminals: **0 errors, 0 warnings**, first pass

## Logic
1. **Accumulation** — real tight-range detection over `AccumulationBars` (default 15), but ATR-relative (`AccumulationATRmult`, default 1.5× ATR) rather than a raw point threshold. That choice is deliberate: tonight's [[TWI 9AM CR Model EA]] build got its point-based thresholds miscalibrated for XAUUSD (a $0.001-point symbol made a real $25 range read as "25,000 points"), so this EA is built ATR-relative from the start to self-scale across forex/gold/indices without separate per-symbol tuning.
2. **Manipulation** — a wick beyond the locked range, dual-bounded (`SweepMinATRmult`/`MaxSweepATRmult`, same 0.10/3.0 defaults just validated on [[TWI OB Hunter]]'s own review pass tonight) so it's neither noise nor a real trend continuation. Requires a close back inside the range within `ReclaimBars`.
3. **iFVG** — same FVG lifecycle (ACTIVE → PARTIALLY_FILLED → INVERTED) already built and proven twice tonight ([[TWI 9AM CR Model EA]], and the concept behind [[TWI OB Hunter]]'s zones). Only an inverted zone matching the trade direction, formed at/after the manipulation bar, is eligible.
4. **Distribution** — retrace into the IFVG, confirm via `EntryMode` (default `IFVG_REJECTION_CLOSE`: wick into the zone, close back beyond it), enter toward `TargetMode` (default `OPPOSITE_RANGE` — the far side of the accumulation range; `MEASURED_MOVE` and `FIXED_RR` also available).

SL = manipulation extreme ± `StopBufferATRmult` × ATR. RR filtered at `MinimumRR` (default 2.0) before any entry. Risk-based lot sizing identical pattern to every other EA built tonight (equity × RiskPercent ÷ real tick value, normalized to symbol volume step/min/max).

Not session-gated (unlike the 9AM model) — continuously re-bases to a fresh accumulation range after each completed setup or invalidation, so it can fire at any time of day the pattern actually forms.

## Status (2026-09-02)
Compiled clean, deployed to both terminals, not attached to any chart. First backtest running.
