---
status: active
project: forex-trading
type: reference
---
# TWI Precision Structure

TradingView Pine v6 indicator + matching strategy, handed over by Adam on 2026-10-19 (written by another AI against a `spec.md` v1.0 and a Python replay we don't have; its author never compiled it). Adam: "Make it a trading view indicator" → "Save to my scripts".

**Status (2026-10-19): indicator SAVED to Adam's TradingView scripts with the review fixes (below), v3.0.** Script `USER;48a3fc9e2f4a40558465752276658848`, name/title "TWI Precision Structure". v2.0 = the upload unchanged (restore point); v3.0 = fixed. Both files server-compile 0 errors / 0 warnings. Created with the Make-a-copy method from [[TradingView Chart Drawing]] (the editor had opened on [[TWI Gold Asia Breakout]], which was verified unchanged afterward). **Not on a chart** (Basic plan, 2 per chart). The strategy version is NOT saved to TradingView.

Sources in this folder: `TWI Precision Structure.pine` (indicator, 376 lines) and `TWI Precision Structure Strategy.pine` (same signal block + orders).

## What it does
- **Strategy A (on by default):** confirmed pivot high broken by a close with a displacement body (≥0.8 ATR) and H1 bias agreeing (HH+HL from H1 pivots, previous closed H1 bar, no repaint) → zone = newest FVG in the leg, else last bearish candle (Demand/OB), else a 0.25-ATR retest band at the broken swing → entry on a bullish close back above the zone within 20 bars. SL = zone low − 0.2 ATR, TP 2R. Filters: risk 0.3–3 ATR, cost ≤10% of risk, no older swing high between entry and target, score ≥90. Shorts are the same engine on mirrored prices.
- **Strategy B (off by default):** double bottom / inverse H&S (and mirrored tops), neckline break with a 0.5-ATR body, retest entry.
- Draws zones, BOS labels, BUY/SELL with score, entry/SL/TP lines, a dashboard; alerts on BUY/SELL.

## Review findings — FIXED 2026-10-19 (Adam: "Fix it", then "Yes" to the exact changes)
1. **Score gate was a no-op:** with HTF + displacement required, every zone already scored 25+25+20+zone(10–20) ≥ 80. **Fix: default min score 90.** Now FVG passes alone (90), Demand/OB needs an engulf/pin (95; 85 without), Retest needs one too (90; 80 without). Fewer signals.
2. **FVG/OB search stopped at the newest candidate** (`break` outside the size check). **Fix: `break` moved inside**, so it takes the newest correctly sized gap / bearish candle in the leg.
3. **Strategy charged no costs.** **Fix: commission 0.235 per unit per side (= 0.47 round trip, gold), slippage 0** (0.47 already includes slip). Change it in Properties for other symbols. TradingView still has no spread modelling beyond that.
4. **Indicator's unused `maxHold` input removed** (the strategy keeps it).
Fixes 1–2 are in both files; the strategy file (vault only) also has fix 3.

## Not done
No backtest or chart read yet. Not measured against the [[EA Scorecard]].
