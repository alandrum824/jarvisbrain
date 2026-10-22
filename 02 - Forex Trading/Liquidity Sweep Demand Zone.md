---
status: active
project: forex-trading
type: indicator
---
# Liquidity Sweep Demand Zone (LS-DZ)

Pine v6 indicator. Adam uploaded it on 2026-10-11 ("Build this and save in my scripts"); the file was named `liquidity-demand-zone-unvalidated.pine`, author unknown.

**Status:**
- **v3 rebuilt to match the source diagram** (Adam: "Yes", 2026-10-11).
- Saved over the same TradingView script, id `USER;5fe244fb6cf644ed951f3d8a738f6b94`. The editor footer reads "3 · Today, 23:01".
- The server compile gives 0 errors and 0 warnings.
- Not on a chart (2-indicator cap).
- **Backtest: FAILS on gold, all 8 variants** (see below).
- Places no trades.

Source: `Liquidity Sweep Demand Zone.pine` in this folder, 210 lines. Backtest: `ls_demand_zone_research.py` in this folder; it applies the same rules as the indicator.

## The model (v3 rules, matching the diagram)
Long side; the short side is the exact mirror.

1. **Swings and break.** Swings are confirmed pivots, 3 bars each side by default. A close above the last swing high is the break (BOS). The lowest low since that swing high is the higher low; it must sit above the swing low before the high.
2. **Demand zone.** The higher-low candle, from its low to its high. It only exists after the break.
3. **Liquidity.** Swing lows formed after the break and above the zone; the lowest of them is the sell-side liquidity (orange dashed line). The trigger line (yellow) is the highest high since that swing low.
4. **Entry.** A sweep below the liquidity, then a tap of the zone top, then the first close back above the trigger gives a BUY label, an SL line at the zone bottom, and a TP line. The TP is the high made after the break (skipped if under 1R) or a fixed 2R.
5. **Kill.** The setup dies on a close below the zone, on 48 bars after the sweep with no entry, or when a new break replaces it. Killed zones turn grey.
6. **Alerts:** "LS-DZ Buy" and "LS-DZ Sell".

v1, the uploaded file, swept the wrong side and entered on the tap. It was replaced.

## Backtest (2026-10-11, AAAFx M1 2020-01 → 2026-10, XAUUSD)
**Method:** bars are built from M1 on the NY clock and exits are run on M1. Costs are the bar spread plus a 6-point markup. One position at a time, maximum hold 2 days. The control is a coin flip: 50 seeds, same entries, same R. The pass bar was set beforehand: ≥5 of 7 years positive, PF ≥ 1.15, and beating ≥95% of the coin runs.

| Bars | Swing | Target | Trades | Net R | PF | Years + | Beats coin |
|---|---|---|---|---|---|---|---|
| 5m | 3 | peak | 14 | −2.5 | 0.72 | 3/6 | 46% |
| 5m | 3 | 2R | 542 | −41.4 | 0.89 | 1/7 | 36% |
| 5m | 5 | peak | 9 | +0.1 | 1.02 | 4/6 | 48% |
| 5m | 5 | 2R | 377 | −16.2 | 0.94 | 2/7 | 50% |
| 15m | 3 | peak | 2 | +0.2 | 1.21 | 1/2 | 24% |
| 15m | 3 | 2R | 214 | −3.5 | 0.97 | 4/7 | 28% |
| 15m | 5 | peak | 6 | −1.2 | 0.71 | 2/4 | 40% |
| 15m | 5 | 2R | 127 | +8.1 | 1.10 | 4/7 | 66% |

- **None pass.**
- **The diagram's own target, the post-break high, is almost never ≥1R.** Entering at the range top with the stop under the zone puts the target too close, so 95%+ of setups get skipped.
- **With 2R the results are coin-flip level.** The setup is also rare: about 20–80 trades a year.

## Source diagram vs. the script (2026-10-11)
Adam sent the source: 5 frames of a @Prop-Firm-Trader YouTube short ("THIS Gold Strategy Made Her 6 FIGURES", 5m & 15m). In order, the frames show:
1. An uptrend of higher highs and higher lows.
2. The demand zone sits at the higher low. It is "not valid" until the rally from it breaks the previous swing high, and after that break it is "high-quality".
3. The pullback then builds a small consolidation **above** the zone, with "Liquidity" marked under its lows.
4. Price sweeps those lows down into the demand zone and reverses.
5. The entry (yellow dot) is on the way back up, at the consolidation's top line, so it comes after the reclaim, not on the tap.

**The uploaded script differs in 4 ways:**
1. Its long trade needs a sweep of **highs**; the diagram sweeps the **sell-side lows** into the zone.
2. It validates a zone by a 1.5 ATR move away from it, not by a break of the prior high.
3. It has no higher-high / higher-low trend check.
4. It enters on the zone tap rather than on the reclaim.

Fixed in v3 (above).

## Companion script: LS-DZ Signals (2026-10-11; Adam: "Make this")
Adam uploaded `liquidity-demand-zone-signals-unvalidated.pine`, author unknown. It is the **v1 logic plus a trade-level engine**.

**Status:**
- Saved as a new TradingView script, "LS-DZ Signals", id `USER;52adf4183eee4cb6a4fd514ea9e823a7`, v2. Made with Make-a-copy (count 54 → 55); LS-DZ v3 untouched.
- The editor reports 0 errors.
- Not on a chart, UNVALIDATED, not backtested.

Source: `LS-DZ Signals.pine` in this folder, 390 lines.
- **2026-10-12 ~11:20 PM:** accidentally overwritten as v4 by the TWI Gold Asia Breakout code (the `pine_new` bug, see [[TradingView Chart Drawing]]). **Restored the same minute from this vault file as v5** (identical to v3). Script id unchanged.

**What it draws:**
- Long: a sweep of equal highs, then a tap of a demand zone gives a BUY label with entry, SL, TP1 and TP2 lines.
  - SL = zone bottom minus 0.2 ATR.
  - TP1 = the swept level; the signal is skipped if that's under 1.5R.
  - TP2 = 2R.
- One active signal per side. The result is tagged "✓ TP2 +2R" or "✗ SL -1R".
- Short is the mirror.

**Two fixes from the uploaded file:**
1. `ta.highest`/`ta.lowest` moved out of the `if` blocks.
2. SL/TP are checked from the bar after entry. As uploaded, the entry bar's own low could print an instant false "-1R".

**v3 declutter (2026-10-11 23:51; Adam's GBPUSD 5m phone screenshot, "Needs to be fixed"):** display only, the signals are unchanged.
- Swing circles became tiny triangles (plotshape).
- Only the newest 3 zones per side are drawn (input "Zones drawn per side"); older zones still count for signals.
- Zones and lines extend 10 bars, not 60.
- Swept liquidity lines stop at the sweep bar instead of crossing the chart.
- The Liquidity and Sweep text is tiny.
- The editor footer reads "3 · Today, 23:51", 0 errors.
- v2 backup: `stg\obh\LS-DZ_Signals_v2_backup.pine`.
- **The phone chart only updates once the indicator is removed and re-added.**

**Caveat:** it keeps v1's mismatches with the diagram (the long sweeps highs, entry on the tap, no break-of-structure zone test). Its ✓/✗ tags are not a backtest: there are no costs, and the counting starts after the entry bar's close.

## Caveats
- This is the same family as setups that have already failed backtests: sweep → zone → tap. See [[TWI EQ Liquidity OB]], [[TWI Gold Zone Ladder]] and [[EA Scorecard]].
- The gold test above says the BUY/SELL labels are not an edge. Use them as a visual of the model only.
- Not yet tested on other markets.

## Saving method used
The banked Make-a-copy method from [[Malaysian SNR x Orderflow]]:
1. `pine_open` (it failed once; the retry worked).
2. Copied from TWI EQ Liquidity OB.
3. The new name was set and the script count went from 53 to 54.
4. Before `pine_set_source` + Ctrl+S, the editor title read "Liquidity Sweep Demand Zone".

After saving, the new id was at v2, and TWI EQ Liquidity OB was untouched (v12, same modified timestamp).
