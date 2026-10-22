---
status: active
project: forex-trading
type: indicator
---
# TWI EQ Liquidity OB

TradingView Pine v6 indicator built 2026-10-07 from 8 frames of a video Adam sent (XAUUSD 1m, presenter drawing the setup by hand). Source: `TWI EQ Liquidity OB.pine` in this folder (444 lines). **Status: compiles clean (0/0) server-side and in the editor; SAVED to Adam's TradingView as a new script "TWI EQ Liquidity OB" via Make-a-copy (count 52 -> 53; Trapped Traders scripts and Manas untouched). NOT on a chart (Basic 2-indicator cap), not run, UNVALIDATED.** Places no trades.

## The setup (as restated to Adam and confirmed: "Yes build")
- **Sell:** equal highs (two confirmed swing highs within 0.15 ATR, 3-60 bars apart, nothing traded above them in between, middle low at least 0.5 ATR below) -> a CLOSE breaks that middle low (BOS) within 40 bars -> the order block ("water block" in the captions) is frozen at the BOS: the last up candle at or up to 5 bars before the 2nd top (its body if the candle is taller than 1.5 ATR) -> price returns into the zone -> entry on a rejection close (or on touch, input).
- **Buy:** exact mirror with equal lows.
- "FB" in the captions read as FVG: a fair value gap anywhere in the break leg is flagged and can be required (off by default).
- Invalidation: 2 closes beyond the far edge of the zone, or a close beyond the equal level. Expiry: no BOS in 40 bars, no retest in 60 bars.
- Stop: beyond the retest extreme / zone / equal level + 0.1 ATR (N/A if risk outside 0.15-4 ATR). Targets: nearest confirmed swing pivots beyond entry (TP1, TP2), N/A if none; R:R >= 1.5 filter (switchable).
- Non-repainting (confirmed bars only, confirmed pivots, frozen zones); alerts once per transition at bar close; Debug mode labels every step and why a setup stopped; table shows the live setup and a running record (entries / TP1 first / stop first).

## Honest limits
- Close cousin of the "Double top/bottom" origin in [[TWI Manas Setup]], which tested 9 trades / 0% win / -9R on gold 30m. The video is 1m, which is noisier. Backtest (Python replica on MT5 bars) before trusting it.
- "Water block" = order block and "FB" = FVG are interpretations of auto-captions.

## v2 (2026-10-07, after Adam's phone screenshot; Adam: "Mark out entry zone with block and yes fix it")
Adam's phone run (XAUUSD 5m) showed EQL/EQH/BOS working and the table sprawling over the candles; the orange supply box on his screenshot was HIS drawing (the indicator's EQH at ~4113.3 sat inside it). Changes (523 lines, compiles 0/0, saved over the same script):
- **Entry zone block:** the order block is now fixed the moment the equal level is confirmed (frozen, never moves) and drawn right away as a faint dotted "sell/buy zone (needs BOS)"; at the BOS it becomes a solid filled box with a 2 px border, "SELL ZONE (OB)" / "BUY ZONE (OB+FVG)" text and a dashed midline (like Adam's hand-drawn box); finished setups turn gray and show their end state (PASS / INVALID / ENTRY). Inputs: zone fill transparency (75), show pending zone (on).
- **Compact phone table** by default (Setup + short status, Zone, Entry/Stop, TP1/TP2, R:R, Record); full table and table position are inputs.
- Adam must remove and re-add the indicator on his phone to pick up v2 (same as Trapped Traders).

## v4 (2026-10-07 ~4:50 PM PT; Adam: "Let's non repaint add stop above zone and trust the process fix this")
Context: on US30 5m the indicator found EQH ~51,190, BOS, sell zone ~51,150-51,180, then marked it PASS just as price returned ~4.5 h later (most likely the 60-bar retest timer, possibly the R:R filter). Adam took the short himself (~51,158, stop ~51,209 above the equal highs). Changes (535 lines, compiles 0/0, saved over the same script):
- **Stop placement input, default "Beyond the zone"**: stop = the zone's far edge + 0.1 ATR (above the zone for sells, below for buys). The old "Beyond the equal level" (also covers the retest extreme) is the alternative.
- **Retest window 60 -> 120 bars.**
- **R:R filter OFF by default** ("trust the process"): every confirmed retest now prints entry, stop and targets; the filter is still an input.
- **Table shows why the last setup ended** ("Last setup" / "Why" rows) when nothing is live.
- Still non-repainting (confirmed bars, confirmed pivots, frozen zones). Changing inputs recalculates history; that is a settings change, not repainting.
- Note: with the stop just beyond the zone, a retest wick that already poked past the zone can sit beyond the stop; that is Adam's chosen rule.

## v5 (2026-10-07 evening; Adam: "huge take profit on these moves like previous low" + 2 video frames, then "Yes")
Old targets (nearest pivots) were too close: on Adam's US30 short TP1/TP2 were ~51,143/51,128 while price ran to ~51,064. The teacher's frames target the origin of the rally (~4153 under the 4154-4156 zones). Changes (560 lines, compiles 0/0, saved over the same script):
- **TP2 = the previous low/high the move into the equal level started from** ("origin"): for a sell, the lowest low walking back from the 1st touch until an earlier high above the equal level (cap: `originLook` 150 bars); buys mirror. Fixed when the setup is created (non-repainting).
- **TP1 = the nearest swing before that** (partial / move stop to entry); if no swing sits before the origin, the origin becomes TP1 and TP2 is blank. Labels read "(prev low)" / "(prev high)".
- **R:R now measured to the final target** (TP2 when present). Win stats still count TP1-first vs stop-first.
- Inputs: `useOrigin` (on), `originLook` (150).

## v6 (2026-10-07 ~6:15 PM PT; Adam: "We need this cleaned up")
Adam's US30 phone chart was cluttered: doubled "EQH EQH" / "BOS BOS" (a 3rd top re-pairing into a duplicate setup), ghost "ENTRY"/"PASS" text in old boxes, stale STOP/TP labels from finished trades. His screenshots still showed v4 targets (no "(prev low)" tags), i.e. the phone copy had not been re-added after v5. Changes (574 lines, compiles 0/0, saved):
- **Clean chart (default on):** drawings of finished setups (PASS / INVALID / closed trades) are erased; live setups plus the newest `histKeep` (1) finished trade stay. Setups stay in memory, so the table's "last setup / why" and the record still work.
- **Dedupe:** a new equal pair whose first touch is an existing setup's second touch (triple top/bottom) no longer spawns a duplicate setup.
- Finished boxes carry no text in clean mode.
- Adam declined the backup "broken-low retest" entry ("I don't think it will pull back, I think straight to my TP"); not built.

## v7 (2026-10-07 ~6:25 PM PT; Adam: "Yes" to the previous-low fix)
v6 confirmed loaded on Adam's phone (single EQH/BOS, record 32 -> 30 after dedupe), but the first US30 sell still showed TP2 51,104.3 with no "(prev low)": the walk-back stopped at the day's 51,209 spike right before the equal highs, so the "origin" sat too close and fell back to the nearest pivots. Fix (575 lines, compiles 0/0, saved): a higher high (lower low for buys) only ends the walk-back once the low found is at least `originMinATR` (3.0 ATR) from the equal level; otherwise it keeps looking back (still capped at `originLook` 150 bars). Expected on that chart: first sell -> morning low in the 50,900s; second sell unchanged at ~51,090. **Verified on Adam's phone 6:22 PM:** first US30 sell now shows TP1 51,113.5 and "TP2 50868.42 (prev low)" = the low the morning rally started from.

> **2026-10-11 correction:** the research below overstates the half+BE result. `follow()` kept credited TP2 when a trade had already come back to entry after TP1 (it should close at 0), and it used a flat 0.35 cost on gold. The corrected multi-year gold M5 test (2020–26, real bar spread, M1 exits) loses: see [[TWI Gold Zone Ladder]].

## Pattern research (2026-10-07 night; Adam: "Learn the pattern you see why it does what it does")
Script: [[TWI EQ Liquidity OB Research.py]] (Python replica of v7 rules, read-only MT5 bars from the AAAFx terminal, cost = spread: US30 5.2 pts, gold 0.35). Scratch follow-up `C:\Users\aland\stg\eqob_why.py`; trades CSV `C:\Users\aland\stg\eqob_research_trades.csv`. Default inputs, nothing tuned to this data. Bar-level sim, entry at the rejection close, stop first if both in one bar, 288-bar max hold.

| Set | Trades | TP1 before stop | Final target | Stopped | All at TP1 | All at prev low | **Half TP1 + BE + rest** |
|---|---|---|---|---|---|---|---|
| US30 M5 (17 mo) | 736 | 69% | 26% | 72% | -0.14R, PF 0.63 | +0.12R, PF 1.13 | **+0.18R, PF 1.48, win 55%** |
| Gold M5 (17 mo) | 670 | 69% | 26% | 72% | -0.07R, PF 0.80 | -0.03R, PF 0.96 | **+0.15R, PF 1.43, win 68%** |
| US30 M15 (4 yr) | 703 | 67% | 26% | 73% | -0.09R, PF 0.77 | +0.06R, PF 1.07 | **+0.17R, PF 1.45** |
| Gold M15 (4 yr) | 723 | 66% | 28% | 71% | -0.09R, PF 0.76 | +0.01R, PF 1.01 | **+0.13R, PF 1.35** |

What the pattern does and why:
1. **TP1 is close (median 0.43R) and gets hit ~69%** — that is the table's "good percentage". Banking everything there LOSES on all four sets, because a stop costs 1R.
2. **After TP1, price comes back to entry 67-78% of the time** before the final target (the bounce Adam saw twice today). The nearest swing is opposite-side liquidity; price reacts there.
3. **The stop sits right at the equal level** (median ~0 ATR from it; below it ~60% of the time), and **price trades back through the equal level after entry ~95% of the time**. The equal highs/lows are still unswept liquidity when we enter, so price usually returns for them. Half the stopped trades still reach the final target later, but only after going ~3 ATR past the stop, so a wider stop doesn't save them: stop beyond the EQ +0.25/0.5/1.0 ATR all turned the system negative (~-0.03 to -0.05R).
4. **Edge comes from management:** half off at TP1, stop to entry, rest to the previous low/high = the only consistently positive way (+0.13 to +0.18R per trade, ~40 trades/month per symbol on M5).
5. Filters were noise: FVG helps gold but hurts US30; sells vs buys and retest speed flip between sets; hour-of-day buckets too small.
Open idea (proposed to Adam): require the equal level to be swept FIRST (sweep -> BOS -> OB), so we sell after the liquidity is taken instead of under it.

## Advance water block test + v8 (2026-10-07 night; Adam: "Yes sir" to build and test the teacher's advance block)
From the teacher's frames: after the CHoCH/BOS he enters at the **advance water block** (supply at the break level, below the top block), stop up near the top block. Research script now has `entryZone` ("top"/"advance") and `stopAt` ("zone"/"top"); advance block = last opposite candle before the breaking candle, back to the 2nd touch (BOS candle body if none; body if > 1.5 ATR). Half at TP1 + BE + rest to prev low:

| Set | v7 top block, stop above it | Advance block, stop above it | **Advance block, stop above TOP (teacher)** |
|---|---|---|---|
| US30 M5 | +0.182R PF 1.48 (736) | +0.050R PF 1.10 | **+0.159R PF 1.50 (819), stop 67%** |
| Gold M5 | +0.146R PF 1.43 (670) | +0.143R PF 1.34 | **+0.208R PF 1.79 (751), stop 61%** |
| US30 M15 | +0.167R PF 1.45 (703) | +0.052R PF 1.10 | **+0.130R PF 1.36 (772)** |
| Gold M15 | +0.127R PF 1.35 (723) | +0.045R PF 1.10 | **+0.132R PF 1.40 (777)** |

Read: the teacher's version ties v7 on average R per trade (~+0.16R), wins on PF in 3 of 4 sets, takes ~10% more trades, gets stopped less (61-67% vs 71-73%) and reaches the previous low more (31-36% vs 26-28%); clearly better on gold M5, slightly worse on US30. A tight stop on the advance block is the worst of the three (stop sits inside the noise). Not an across-the-board upgrade.
**v8 (613 lines, compiles 0/0, saved):** input "Entry zone" = "Advance block (stop above the top block)" (default) or "Top block (stop above it)". At the BOS the advance block is frozen and drawn as the solid "SELL/BUY ZONE (advance block)" with a dashed midline; the top block becomes a faint "stop area (top block)". Entry = touch of the advance block + rejection close; stop/invalidation beyond the top block's far edge; targets unchanged. Table "Zone" shows the entry zone.
**v8 seen on Adam's phone (8:50 PM):** the second US30 sell (never reached the top block, so v7 sat on WAIT RETEST) entered at the advance block ~17:30 (SELL OB+FVG), stop 51,161.85, TP1 51,107.66 hit, TP2 51,090.57 (prev low) reached on the run to ~51,035. Record 30 -> 38 trades (29 TP1 / 9 SL).
**v9 (2026-10-07, Adam: "Yes"):** table's "last" zone row now shows the advance block when that entry zone is in use (it showed the top block). Compiles 0/0, saved.

## Sweep-first test (2026-10-07 ~9:25 PM PT; Adam: "This is the setup we're looking for" - his live gold sell: sweep of the high -> CHoCH -> lower high -> drop)
Research script `trigger="sweep"`: a new swing high runs a prior swing high (within 60 bars) by 0.05-2 ATR and closes back below it within the 3 confirm bars; CHoCH = close below the low between; entry at the advance block; stop above the sweep. Half at TP1 + BE + rest to prev low:

| Set | A equal highs (v9 default) | **B sweep -> CHoCH -> advance block** | C sweep -> top block entry |
|---|---|---|---|
| US30 M5 | +0.159R PF 1.50 (819) | +0.149R PF 1.48 (905) | +0.066R PF 1.17 |
| Gold M5 | +0.208R PF 1.79 (751) | +0.117R PF 1.38 (813) | +0.086R PF 1.23 |
| US30 M15 | +0.130R PF 1.36 (772) | +0.121R PF 1.38 (859) | +0.123R PF 1.35 |
| Gold M15 | +0.132R PF 1.40 (777) | +0.203R PF 1.78 (808) | +0.199R PF 1.59 |

Read: the sweep trigger ties the equal-highs trigger on average (~+0.15R/trade, ~10% more setups); it is not an upgrade by itself. What holds across every test: entry at the advance block (the break-level lower high), stop above the top/sweep, half at TP1 + BE + rest to the previous low. Entering at the top block is consistently weaker. The two triggers could run side by side for more setups at the same edge (overlap not measured yet).
**v10 (2026-10-07 ~10:00 PM PT; Adam: "Yes" to adding the sweep trigger):** input "Setup trigger" = "Equal levels + sweeps" (default) / "Equal levels only" / "Sweeps only". Sweep = a new confirmed swing high runs the prior swing high (within 60 bars) by 0.05 ATR to `sweepMaxATR` (2.0) and a close since the pivot bar is back below it (buys mirror); labeled "SWEEP" instead of EQH/EQL. Same BOS (close beyond the low between), advance-block entry, stop above the top/sweep, TP1/TP2 as before. 626 lines, compiles 0/0, saved. Same logic as research trigger "sweep" (B: ~+0.15R/trade with half+BE). Overlap between the two triggers not measured.
**v11 (2026-10-07 ~10:40 PM PT; Adam: "Fix it"):** overlapping pending zones (EQH sell zone over EQL buy zone on US30) printed their labels on top of each other; the pending buy-zone label now sits bottom-left of its box, the sell-zone label stays top-right. Display only. Compiles 0/0, saved.
**v12 (2026-10-07 ~10:55 PM PT; Adam: "Yes"):** active-zone labels shortened and pinned: advance box reads just "SELL ZONE"/"BUY ZONE" (tiny, right edge) instead of spilling "(advance block)" text across candles; the top block reads "stop area" pinned to its far edge (top for sells, bottom for buys) so it stops landing on older TP labels. Display only. Compiles 0/0, saved. v10+ confirmed on Adam's phone at 10:50 PM (record 38 -> 54 with sweeps).
