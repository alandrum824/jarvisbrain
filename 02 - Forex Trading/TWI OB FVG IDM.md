---
status: active
project: forex-trading
type: reference
---
# TWI OB FVG IDM

One simple TradingView Pine v6 map, built 2026-09-24 ~04:00 PT. Adam: "I want one simple indicator it marks out order blocks and fvg with inducement liquidity grabs on order blocks", plus "and bullish candles, bullish harami". No stats or research tables, on purpose. It came after the [[TWI SMC POI]] research showed that neither mechanized model had a reliable edge. This is a visual map for discretionary reading, not a backtested strategy.

## What it draws (bull shown, bear mirrored)
- **Strong order block:** the last bearish candle (searched up to 5 bars back) right before a displacement candle that leaves a **bullish FVG** (`low > high[2]`). This is Adam's rule: strong OBs have the FVG after them. Box = that candle's high–low. **Removed** when a candle closes below it (option: a wick). Up to 6 live per side.
- **FVG:** the 3-candle gap, boxed, removed once filled. Up to 8 per side.
- **Inducement (IDM):** the latest small swing low (2 bars each side) that forms after the OB and above it, as a yellow dotted line. When price takes it out: an "IDM" tag.
- **Signal "OB + IDM":** price taps the OB **after** (or on the same bar as) the IDM grab → label + alert. If it taps without an IDM grab, the OB is used and there's no signal.
- **Confirmation candle:** for 3 bars after the tap, a **harami** or **engulfing** candle inside the OB → "Harami ✓" / "Engulf ✓" (+ "IDM" if the grab happened) + alert.
- Used OBs are erased by default (`Keep used OBs` toggle). One "Any alert() function call" alert covers the OB+IDM tap and the confirmations.

## Build / deploy
- Vault source: `02 - Forex Trading/TWI OB FVG IDM.pine`. **`pine_check` 0/0**, and the checked source equals the vault file.
- TradingView script **"TWI OB FVG IDM", id `USER;a412a6665a164d129603b487f909ba9b`**, created by Make-a-copy (43 → 44 scripts); v3 = current (the `showUsed` default went false after the first on-chart read hit the 500-box cap with every used OB kept). Each save was verified in the script list; SMC POI (v6) and ORB (v4) were untouched.
- **On the chart:** layout `uJnBMo6l`, **OANDA:XAUUSD 5m**, with Sweep Reversal Map [Herman]. SMC POI and TWI ORB Trend Retest are saved but OFF the chart (2-indicator Basic cap).
- **Gotcha:** changing an input default doesn't update an indicator already on a chart (the instance keeps its own settings). Remove and re-add it to pick up new defaults.
- The first read (gold 5m, loaded history) was full of OB+IDM, IDM, Harami ✓ and Engulf ✓ prints. The labels hit the 500 cap, so the oldest roll off. **Nothing here is measured. It's a map, not an edge claim.**

## v4 scorecard (2026-09-24 ~17:07 PT, Adam: "let's do it") + first 6-market read
Every signal is scored as a trade: entry = the signal candle's close, stop = the OB far edge + 10% of OB height, target 1.5R, SL-first when both are hit, unresolved after 288 bars = closed at market. Buckets: OB + IDM tap / Confirm + IDM ✓ / Confirm ✓ (no IDM). Saved as script v4 (verified; SMC POI v6 and ORB v4 untouched). At 1.5R, breakeven = a 40% win rate.

| Market (OANDA) | OB + IDM | Confirm + IDM ✓ | Confirm ✓ no IDM | ALL |
|---|---|---|---|---|
| XAUUSD 15m | 225, 36%, −22.5R | 57, 44%, +5.5R | 132, 42%, +5.5R | 414, −11.5R |
| XAUUSD 5m | 212, 37%, −17R | 53, 43%, +4.5R | 129, 45%, +16R | 394, +3.5R |
| GBPAUD 5m | 192, 39%, −4.5R | 67, 39%, −2R | 150, 41%, +5R | 409, −1.5R |
| GBPAUD 15m | 205, 39%, −7.5R | 68, 40%, −0.5R | 153, 39%, −6.97R | 426, −14.97R |
| EURUSD 15m | 213, 41%, +2.59R | 75, 36%, −7.5R | 187, 43%, +13R | 475, +8.09R |
| EURUSD 5m | 207, 44%, +23R | 67, 46%, +10.5R | 179, 31%, −39R | 453, −5.5R |
| **Total** | **1,254, −25.9R** | **387, +10.5R (+0.03/trade)** | **930, −6.5R** | **2,571, −21.9R** |

**Read:** every bucket sits at ~39–41% wins at 1.5R, which is right at breakeven. The raw OB+IDM tap loses in 4 of 6 markets. Confirm + IDM is the only positive bucket overall, but it's positive in just 3 of 6. **No edge as built.** The "worked perfect" morning was a sample of one.

## v5 research grid (2026-09-24 ~17:30 PT, Adam: "study this and make it better using AI" / "build the indicator to be successful")
Added (script v5, verified; SMC POI v6 and ORB v4 untouched): each signal is scored in parallel at 1/1.5/2/3R and split by filters: active session (07–17 UTC), 1H HH/HL trend agreement, strong gap (displacement FVG ≥ 0.5 ATR), **Adam's big-candles rule** ("OBs with multiple big candles following them are the best entries… institutions moving large money… setting up for the return and their entry"): ≥ 2 candles with body ≥ 0.8 ATR within 3 bars after the OB, plus session+big. Rule to keep a filter: better on ≥ 5 of 6 markets.
**In-sample (XAUUSD / GBPAUD / EURUSD × 5m / 15m), 72 cells:** the only 6/6 cell was **CONF+IDM at 3R: +62R over 386 trades**; CONF+IDM + trend at 3R was +25R/123, also 6/6. Adam's big-candles rule: TAP big candles +17.6R/196 at 2R (4/6), CONF+IDM big +19R/73 at 3R (4/6), so it doesn't pass 5/6. Trend and session filters mostly made things worse.
**OUT-OF-SAMPLE CHECK on unseen markets (GBPUSD, USDJPY × 5m / 15m): CONF+IDM at 3R = −7.8 / −1 / −9.4 / +1.8 → −16.4R over 284 trades. FAILED.** CONF+IDM + trend at 3R: +10 / −3 / −3 / −6 → failed. Other cells swing sign between the two market sets (e.g. CONF-all at 3R: −35.9R in-sample vs +107R on USDJPY+GBPUSD). **Conclusion: with 72 combinations tested, the in-sample winner was luck; no filter/target combination generalizes. Defaults were NOT changed on this evidence.** Caveat: TradingView loads only ~2–3 weeks of 5m / ~7 weeks of 15m per market, so every cell is a small sample. A real verdict needs years of data (the MT5 / Dukascopy path).

## v6 market-structure layer (2026-09-25 ~12:30 AM PT, Adam: "Indicator")
Built from two reels Adam shared: **Hamada Fx** (XAUUSD H1: BOS, BOS, BOS, CHoCH, BOS, supply zone at the origin, sell the retrace) and **Trading Chart** (LH/LL downtrend, CHoCH on the close above the last LH, demand zone at the LL candles, buy the retrace, aim for a high R). Script v6, saved and verified (modified 1790321063; SMC POI v6 and ORB v4 untouched).
- **What it draws:** swing BOS (gray) / CHoCH (orange) lines and labels from 5-bar pivots. A **Supply / Demand Zone** is drawn from the last opposite candle at the extreme (the origin) of the breaking move. Zone tap + harami/engulf = **SUPPLY ✓ / DEMAND ✓**, with an alert, scored as its own scorecard row "Supply/Demand ✓".
- **Setting "Zone created on":** `CHoCH` (default, Trading Chart reel) or `First BOS after CHoCH` (Hamada reel). Also: swing size, zones kept per side, colours.
- **Results, H1 (TradingView history):**

| Market | Mode | 1.5R | 3R |
|---|---|---|---|
| XAUUSD H1 | CHoCH | 65 trades, 32%, −12.2R | 65, 26%, +3.3R |
| XAUUSD H1 | First BOS after CHoCH | 34, 41%, +1R | 34, 26%, +2R |
| EURUSD H1 | CHoCH | — | 84, 24%, −4R |
| EURUSD H1 | First BOS after CHoCH | — | 37, 19%, −9R |

**Read:** neither version has an edge. Gold is noise-level positive at 3R, and EURUSD loses in both modes. It's the same verdict as every other SMC variant here: the zones are a good **map** of where to look, not a mechanical entry. The Hamada Aug-19 example itself was a loss (Example E in [[TWI Liquidity Sweep OB EA]]). Defaults were left at CHoCH / 1.5R.

## Related
- [[TWI SMC POI]] — the research that led here
- [[TWI ORB Trend Retest]] — the other saved indicator (currently off the chart)
- [[Malaysian SNR x Orderflow]] — the Pine save-slot gotchas followed for this build
