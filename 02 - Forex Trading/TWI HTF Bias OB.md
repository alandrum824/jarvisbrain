---
status: active
project: forex-trading
type: reference
---
# TWI HTF Bias OB

TradingView Pine v6 indicator, built 2026-09-28 at Adam's request: "build me indicator h4 and daily showing bullish or bearish dashboard and marks out order blocks like I asked you." Source: `TWI HTF Bias OB.pine` (this folder). TradingView script name "TWI HTF Bias OB", made through Make a copy… of [[TWI Pat Zones Fib]] and then replaced with this source.

**Status (2026-09-28):** compiled clean and saved. **Not on a chart:** the GBPUSD 1H chart already has 4 indicators and the Basic plan caps new additions at 2. Adam has to choose what to remove. Untested on a live chart.

## What it does
- **Structure:** swing highs/lows N bars each side (default 3). A close through the last swing high/low = **BOS** if it's with the current trend, **CHoCH** if it flips it. Same method as the manual GBPUSD markup on 2026-09-28.
- **Order blocks:** the last opposite-colored candle before the break, searched back to the extreme of that leg. Boxes extend right; the border turns dashed with "(tested)" once price comes back into the box; the box is deleted once price **closes** through it. Default: max 5 per side.
- **Dashboard (table):** Daily, H4 and chart TF rows (bias, last break, level) plus a verdict row: both bullish → "buys at bull OBs", both bearish → "sells at bear OBs", otherwise "wait for alignment".
- **HTF zones:** the latest valid H4 and Daily bull/bear OB drawn as thicker boxes.
- **Non-repainting HTF:** H4/Daily values come from the last **closed** HTF bar (`[1]` + `lookahead_on`), so the dashboard doesn't flicker on a live candle.
- **Alerts:** bullish CHoCH, bearish CHoCH, and Daily + H4 aligning.

## Related
[[TradingView Chart Drawing]] (the new-script method, and how to recover an overwrite), [[TWI OB FVG IDM]] (the older SMC map with BOS/CHoCH), [[Forex Trading]].
