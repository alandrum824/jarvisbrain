---
status: active
project: forex-trading
type: reference
---
# Bias → Location → Confirmation → Management (BLCM framework)

Trading framework Adam captured from a YouTube/TradingView walkthrough (EURUSD 15m, "SMC Engine" layout, discretionary trader) on 2026-09-03. **This is the architecture Adam wants the next EA built on — from scratch, not bolted onto [[TWI TakeProfit SMC EA]].**

## Why it matters
Every EA worked on 2026-09-03 ([[TWI SR Sweep Reclaim]], [[TWI TakeProfit SMC EA]]) failed the same way: **many independent conditions required simultaneously**, producing near-zero trade frequency. This framework is **sequential** — each stage asks only its own question, and a stage can only be reached once the prior one is satisfied. That is structurally immune to the AND-stack failure.

## The four stages, as the source presents them

**1) Bias of the day** — decide direction *first*, before hunting entries. Answer is only `BUY / SELL / NEUTRAL`.
Source lists: market structure, volume-profile analysis, buyer/seller interactions, Candle Range Theory.

**2) Location of bias execution** — a bullish bias does **not** mean buy anywhere. Wait for price to reach an area where executing that bias makes sense.
Source lists: volume profile, interaction levels (AMT).
This is the anti-chasing stage.

**3) Confirmation** — only once price is *at* the location, ask whether the market is actually reacting properly.
Source lists: market structure, MTF analysis, volume profile.

**4) Management** — a separate stage, not one fixed TP.
Source lists: trailing, partialling, price action, liquidity levels, AMT.
Example: partial at first internal liquidity/high, another at next structural level, runner trails beneath newly formed higher lows, exit if structure breaks against the position.

## Adam's automation mapping (XAUUSD)
- **H1** = bias
- **M15** = location / context
- **M5** = confirmation / entry
- M5 confirmation may be CHoCH/BOS, displacement, rejection/engulf, or reclaim **in the bias direction** (any one of them — not all).

## Adam's caution on volume profile (important)
On MT5 spot FX/CFD symbols like XAUUSD, "volume" is usually **broker-specific tick volume**, not centralised exchange volume. So volume profile **must not be a mandatory hard filter initially**:

- Market structure = backbone
- Location = required
- Price-action / MTF confirmation = required
- **Volume profile = supporting context / score only**

Then test empirically whether POC/VAH/VAL/HVN/LVN actually improve results on this broker's data before promoting it.

## Target state machine
```
STATE 1 — DETERMINE BIAS      -> BUY / SELL / NEUTRAL
STATE 2 — WAIT FOR LOCATION   -> price reaches favourable execution area
STATE 3 — WAIT FOR CONFIRM    -> lower-TF structure/reaction confirms
STATE 4 — EXECUTE             -> proper risk sizing
STATE 5 — MANAGE              -> liquidity targets + partials + structure trail
```

## Carry-overs that must come with it (hard-won on 2026-09-03)
- **Risk integrity from [[TWI TakeProfit SMC EA]] v2.30**: size from real dollar risk via `OrderCalcProfit()`, round lots **down** only, never floor a sub-minimum lot up and trade anyway, absolute pre-send risk ceiling, `RISK_CHECK` logged every order. That repair turned a −$22.74 result into +$218 and cut drawdown from 37% to 4.2%.
- **Funnel instrumentation from the start** — per-stage counters and shadow evaluation. Both EAs tonight were flying blind until instrumented.
- **MFE/MAE in R per trade** — the diagnostic that overturned two wrong diagnoses.
- **Check the tester input dump every run** — see [[MBT (MT5 Backtest Toolkit)]] for the `.set` cache that silently overrides compiled defaults.
- **Do not invent rules the source doesn't have.** The invented `MinSweepATR` floor in [[TWI SR Sweep Reclaim]] silently deleted the majority of valid setups.

## Status
Framework captured 2026-09-03. **Nothing built yet** — the two core definitions (what concretely constitutes "bias", and what concretely constitutes "location" once volume profile is demoted to score) still need Adam's call before code, precisely so they aren't invented.

## Related
- [[TWI TakeProfit SMC EA]] — current EA; risk model to reuse
- [[TWI SR Sweep Reclaim]] — the over-filtering failure this architecture avoids
- [[Active Priorities]]
