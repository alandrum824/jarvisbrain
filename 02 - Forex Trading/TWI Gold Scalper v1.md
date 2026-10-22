---
status: active
project: forex-trading
type: reference
---
# TWI Gold Scalper v1

Adam uploaded `TWI_Gold_Scalper_v1.mq5` + `gold_scalper_claude_brief.md` on 2026-10-12 (~10:55 PM), a handoff from another AI. Source: `TWI Gold Scalper v1.mq5` (this folder, unchanged from the upload). Magic 260816.

**Status: compiled 0 errors / 0 warnings with no changes needed.** Deployed as `MQL5\Experts\Advisors\TWIGoldScalper.mq5` (byte-identical). **NOT attached.** The brief's tester checks (SL on every order, guard trip + restart persistence, min-lot halt alert) are **not run yet**: a tester run kills the live terminal, which holds the [[TWI Gold Asia Breakout]] shadow trade until 16:00 GMT.

## Entry: FAILS (the brief says so, and our data agrees)
H1 close vs EMA50 + M5 EMA20/50 trend; the M5 bar dips to EMA20 and closes back beyond it as a trend-coloured candle; SL = signal candle extreme ± 0.2 ATR (0.5–2 ATR), TP 1.5R, BE at 1R, 12-bar time stop; London 08–12 / NY 08:30–12 local.
- **The author's test:** 2023–26 at −0.22R/trade, PF 0.63; 2020–23 at −0.33R, PF 0.50; no better than a coin flip.
- **Ours:** the same idea in `pullback_scalper_research.py` (gold −285 to −389R, 1/7 years).

## The chassis (the reusable part)
- **Account Guard, persisted in terminal global variables:**
  - Daily realized loss ≥ 2% pauses trading to the next server day; weekly ≥ 5% pauses to the next week.
  - Equity 15% under the peak balance trips a kill switch with an Alert; it only re-arms via `GuardRearm`.
  - Headroom sizing means a loss at the SL can't cross the kill floor; at least 50% free margin is kept.
- **Sizing and limits:** risk-% sizing via OrderCalcProfit, capped at 2%, with risk halved after 3 losses in a row. If the min lot would over-risk, it halts with an Alert. One position, max 4 trades/day.
- **Filters:** spread ≤ 60 pts and ≤ 2× the recent median; high-impact USD news ±15 min (live only); no entries after Friday NY noon; flat Friday 15:00 NY.

## Review notes (logic not changed)
1. **Clock on AAAFx:** `ServerUTCOffsetHours=3` is fixed. AAAFx is NY+7 now (UTC+3 in US summer, **UTC+2 in US winter**), so sessions run 1 h off in winter. In tester history before 2026-03-07 the server was UTC+0, so backtest sessions are **3 h off**. It needs the AAAFx clock from [[TWI Gold Asia Breakout]] before any tester result means anything.
2. **On a ~$400 account at the default 0.5% (≈$2 budget),** a 0.01 gold loss at a 0.5–2 ATR M5 stop is ~$2–8, so the min-lot halt Alert fires on most signals. It would rarely trade.
3. Both the daily-loss check and the per-day trade cap call `RealizedSince` (two history scans per signal). Harmless.

## Related
[[TWI Gold Asia Breakout]] (the entry that passes) · [[EA Scorecard]] · [[Thunderbolt EA Review]] (the brief borrowed and rejected ideas from it)
