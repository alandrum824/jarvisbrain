---
status: active
project: forex-trading
type: reference
---
# TWI Scalp Pro Signals

TradingView Pine v6 indicator, built 2026-08-23 as a **visual-only companion to [[TWI Scalp Pro]]** — mirrors the EA's exact entry logic so Adam can manually take the same setups without the EA placing real orders. Script: `TWI Scalp Pro Signals` (id `USER;c16cf30621f84f879653167524148990`), shorttitle "TWI Scalp". Live on the chart, compiled clean.

## Why this exists
Adam asked for a way to manually trade TWI Scalp Pro's setups. Rather than inventing a new strategy, this ports the EA's mechanics 1:1 from `TWI Scalp Pro.mq5` so what Adam sees on the chart is exactly what the EA would have done.

## What it mirrors from the EA, exactly
- **Sessions**: Asian (off by default) / London / New York, each an independently configurable `HHMM-HHMM` exchange-time window, or "use all sessions." Same defaults as the EA (London 0800-0815, New York 1330-1345).
- **Opening Range**: high/low captured during the session window.
- **H1 EMA(50) trend filter**: uptrend = H1 close above the EMA.
- **Entry**: the signal "arms" once a bar closes back inside the OR (so a chart loaded mid-breakout doesn't fire immediately) — same as the EA's `signalArmed` guard — then fires when a candle's **close** crosses the OR extreme in the trend direction.
- **Stop**: opposite side of the OR (+ optional pip buffer). **Target**: entry ± risk × RR multiplier (default 2.8, matching the EA).
- **Entry window**: signals only considered within N minutes (default 240) after the OR closes.
- **Day-of-week filter** and **max signals per session per day** (default 1) — same as the EA.

## One deliberate difference (documented, not a bug)
The EA scans **M1** bars internally to build the OR regardless of chart timeframe. This indicator captures the OR from **whatever chart timeframe it's running on** instead — simpler, transparent for manual trading, and avoids Pine's multi-timeframe `security()` repainting risk. **Run this on the M5 chart** (the EA's default `EntryTF`) for the closest match; the dashboard's "Run on" row confirms M5 is detected.

## Visuals
- OR box while building, dotted extension lines once captured, one set per session.
- BUY/SELL label at the signal bar with entry/SL/TP prices spelled out, so a real order can be placed by hand immediately.
- Status dashboard (top-left): trend bias, each session's live state (off / building OR / waiting / armed watching / signal taken / window closed), and timeframe confirmation.
- Two alertconditions (`TWI Scalp Buy Signal` / `TWI Scalp Sell Signal`) so it can push to Adam's phone.

## Build/verify record
- One real compile error caught and fixed before it ever reached Adam: three helper functions (`f_updateSession`, `f_drawSession`, `f_drawSignal`) had ambiguous implicit return types because their last statement was a conditional whose branches returned inconsistent types (`void` vs. a real type) — Pine infers a function's return type from its last statement. Fixed by appending an explicit trailing `true` to each, unrelated to the actual drawing/logic. Recompiled clean: 0 errors.
- Deployed via the proven-safe "Make a copy" method (banked in [[Malaysian SNR x Orderflow]]'s gotcha) — copied an existing script to guarantee a genuinely new slot, confirmed script count 28→29, then injected this source. No collision with any other script.
- **Verified against real chart data, not just a clean compile**: pulled 33 live signals off the chart history, spot-checked the R:R math (e.g. risk 0.00334 × 2.8 = reward 0.00935 — exact match), confirmed BUY/SELL SL/TP directions are correct, confirmed max-one-signal-per-session-per-day is holding.

## Open / next
- Not compared side-by-side against the actual EA's own trade log yet — the chart-timeframe-OR vs. EA's M1-scan-OR difference should be small but hasn't been empirically checked.
- Asian session off by default, matching the EA — enable if Adam wants to manually watch it too.

## Related
- [[TWI Scalp Pro]] — the EA this mirrors
- [[Active Priorities]]
