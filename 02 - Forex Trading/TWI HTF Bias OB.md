---
status: active
project: forex-trading
type: reference
---
# TWI HTF Bias OB

TradingView Pine v6 indicator, built 2026-09-28 at Adam's request: "build me indicator h4 and daily showing bullish or bearish dashboard and marks out order blocks like I asked you." Source: `TWI HTF Bias OB.pine` (this folder). TradingView script name "TWI HTF Bias OB", made through Make a copy… of [[TWI Pat Zones Fib]] and then replaced with this source.

**Status (2026-09-29, v2):** the [[SMC Playbook (Imperial FX)]] checklist has been built in (Adam: "Yes"). v2 loaded into the same TradingView script (`USER;6aea131bbea04cc8a1ba3b1c60a49ece`), then **compiled clean and saved**. The editor title was verified as TWI HTF Bias OB before saving. **Still not on a chart:** the XAUUSD chart has 4 indicators (LuxAlgo SMC, TWI Pat Zones Fib, Sweep Reversal Map, Natural Momentum), and the Basic plan blocks adding more. **Live 4:23 PM 2026-09-29:** Adam added it himself on his phone (XAUUSD 4H, alongside Sweep Reversal Map + LuxAlgo SMC). The checklist values match Jarvis's hand grade exactly: bias bearish, target 4110.87, POI 4198.085–4227.23, 2.7R, stop 4230.37, 0.01 lot = $32.28 → TOO WIDE. **Display bug on the phone:** the step-name and ✅/❌ columns are squeezed to near zero, and the bottom verdict row shows blank. The likely cause is the long detail text making the table wider than the portrait screen; not confirmed. The desktop layout doesn't have it, so it couldn't be read programmatically. **Fix v2.1 (Adam: "Yes"), same evening:** the checklist moved to its own compact 2-column table: `✅ Bias | D+H4 bear`, with the verdict on the top row. There's a new "Checklist position" input (default Bottom Left) and a "Checklist text" input (Small/Tiny/Normal). **All merged cells were removed**, including the main dashboard's D+H4 verdict row, which is now 4 plain cells, because the merged rows are the ones that rendered blank. Compiled clean and saved after verifying the editor title; **Phone display confirmed by Adam ("Yes looks good", ~4:45 PM 2026-09-29).** The v1 source is recoverable from pine-facade version history.

## What it does
- **Structure:** swing highs/lows N bars each side (default 3). A close through the last swing high/low = **BOS** if it's with the current trend, **CHoCH** if it flips it. Same method as the manual GBPUSD markup on 2026-09-28.
- **Order blocks:** the last opposite-colored candle before the break, searched back to the extreme of that leg. Boxes extend right; the border turns dashed with "(tested)" once price comes back into the box; the box is deleted once price **closes** through it. Default: max 5 per side.
- **Dashboard (table):** Daily, H4 and chart TF rows (bias, last break, level) plus a verdict row: both bullish → "buys at bull OBs", both bearish → "sells at bear OBs", otherwise "wait for alignment".
- **HTF zones:** the latest valid H4 and Daily bull/bear OB drawn as thicker boxes.
- **Non-repainting HTF:** H4/Daily values come from the last **closed** HTF bar (`[1]` + `lookahead_on`), so the dashboard doesn't flicker on a live candle.
- **Alerts:** bullish CHoCH, bearish CHoCH, and Daily + H4 aligning.

## v2 additions (2026-09-29): the SMC checklist
- **Dealing range:** the H4 (or Daily) leg that made the last break, stretched as it makes new extremes. Shaded **premium** (above 50%) and **discount** (below), with a dashed EQ line.
- **Sweeps:** a wick through an unbroken chart-TF swing that closes back inside is marked "sweep".
- **Displacement:** candles whose body is ≥ 1.5× ATR(14) and ≥ 60% of the range get triangles.
- **FVGs:** 3-candle gaps get dotted boxes, deleted once price closes through them.
- **Checklist table (v2.1: its own 2-column table; the verdict is the top row):**
  1. Bias
  2. Target: the range extreme in the bias direction
  3. Sweep: opposite-side, within 40 bars
  4. Displacement: after the sweep
  5. Location: premium for sells, discount for buys
  6. POI: the nearest live OB or FVG reaching into the correct half, flagged when price is in it
  7. Shift: a break in the bias direction after the sweep
  8. R:R: entry at the POI edge, stop beyond the POI + 0.1 ATR, target the range extreme, ≥ 2R by default
  9. Size: what 0.01 lot risks, and the max lot at 2%
  
  The verdict row names the first failing step.
- **Risk inputs:**
  - Balance: typed in by hand, default 237.26; it is not read from the broker.
  - Risk %.
  - Contract size: 100 for gold; 100000 for USD-quoted FX; not valid for JPY or CAD-quoted pairs.
- **New alerts:** "Checklist ALL PASS" and "Price entered POI".
- **Honest limits:**
  - The shift row reads the chart timeframe. Real refinement still means dropping to M15/M5 by hand.
  - The checklist gates discipline; it is not a tested edge.

## Related
[[TradingView Chart Drawing]] (the new-script method, and how to recover an overwrite), [[TWI OB FVG IDM]] (the older SMC map with BOS/CHoCH), [[Forex Trading]].
