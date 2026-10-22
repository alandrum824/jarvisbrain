---
status: active
project: forex-trading
type: study
---
# Chart Lessons Study

Study of the ~30 hand-drawn chart lessons Adam sent on 2026-10-13 (mostly from the @fxprosignal007 Telegram channel, plus GoldSniperFX, Smart Money Lab, PriceAction.com, The Strat and The Forex Lab). Each concept is explained in plain English, the concepts are tied into one story, and the 2020–26 gold test result is recorded next to each. Part of [[Forex Trading]]. Tight definitions of OB/FVG live in [[Order Block and FVG Playbook]], the SMC glossary in [[SMC Playbook (Imperial FX)]], and every test's numbers in [[EA Scorecard]].

## The one story all the pictures tell
1. **Big money builds a position quietly.** This is the range or accumulation: candles go sideways and stop orders pile up just above and below.
2. **It grabs those stops.** This is manipulation, a liquidity sweep, or a "trap": a quick poke through one side.
3. **It moves for real.** This is distribution or expansion: long candles (ERC/marubozu) that leave a **gap (FVG)** and **break structure (BOS)**.
4. **Price often comes back to where the move started.** That's the order block or demand/supply zone, the gap, or the broken level (a retest). Traders enter there with a stop just beyond the zone.
5. **Targets are the next pool of stops.** That's the old highs or lows ("liquidity", "target area").
6. **Timeframes stack:** 4H gives direction, 1H gives structure and liquidity, 15m shows the break, and 5m places the trade.

## The concepts, plain English

### Candles
- **Anatomy:** open, high, low, close; the body is open↔close and the wicks are the extremes. A long wick means price went there and got pushed back.
- **The Strat numbers:** 1 = *inside bar* (inside the prior bar's range, indecision); 2 = *one-side break* (takes out one side, trending); 3 = *outside bar* (takes out both sides, expansion). Read them on a higher and a lower timeframe together.
- **ERC / Marubozu:** a long candle whose body is ≥80% of its range, with little to no wick. It shows urgency, an imbalance.
- **Pin bar / hammer / inverted hammer:** a long rejection wick. The lessons rank them by wick length (strongest → indecision).
- **Engulfing:** a candle that closes past the prior opposite candle's open, so the "close" flips control.
- **Tweezer bottom/top:** two candles with matching lows/highs at a level.
- **Three white soldiers / three black crows:** three strong candles in a row, each closing further on.
- **Rising / falling three methods:** a big candle, three small counter-candles inside it, then a candle that breaks the first counter-candle's open, signalling continuation.

### Structure
- **Uptrend** = higher highs and higher lows ("perfect pullbacks" each hold above the last low). **Downtrend** = the mirror.
- **BOS (break of structure):** price closes past the last swing in the trend's direction, so the trend continues.
- **CHoCH / MSS (change of character / market structure shift):** the first break *against* the trend, so the trend may be flipping.
- **S/R flip / structure retest:** a broken swing level often gets retested from the other side ("new resistance" after support breaks).
- **Trendline + neckline break:** H&S and double-bottom pictures enter when both lines break.

### Zones
- **Demand / supply zone:** the base a strong move launched from.
- **Order block (OB):** the last opposite-colour candle before the impulse. The lessons list six "types" by that candle's shape: normal, pin, doji, engulfing, tweezer, manipulation. Their tips: strong displacement, a higher-timeframe OB, combined with a sweep + MSS + FVG, fresh (untouched).
- **Three areas from one impulse:** *Demand 1* (the base before it), *Gap* (the FVG the impulse left), *Demand 2* (the small pause right after it).
- **Real vs fake zone:** the *real* zone is the origin of the whole leg; a *fake* zone is a minor pause inside the leg, where retail sells and gets stopped out.
- **Return types:** a slow, choppy (balanced/corrective) return into a zone = trade it; a straight-line (reversal) return = skip.

### Liquidity and traps
- **Buy-side / sell-side liquidity (BSL/SSL):** clusters of stops above highs / below lows; equal highs or lows are the obvious magnets.
- **AMD:** accumulation → manipulation (a sweep of one side) → distribution (the real move the other way).
- **Sell/buy traps:** an early "confirmation" at the fake zone pulls traders in; the real entry is higher, at the origin.

### Patterns
- **Head & shoulders (and inverse):** three peaks, the middle one highest; enter on the neckline break (often with the trendline). Entry menu: neckline break, retest, FVG, breakout.
- **Double top/bottom ("butterfly"):** two tests of a level, then a break of the middle.
- **Bull/bear flag:** a sharp pole, then a tight channel against it, then a break back with the pole.

### Entries, stops, targets
- **Three entry styles at a zone:** a *pending limit* at the zone (first touch), *candle confirmation* (wait for engulfing/pin), or *pullback structure* (wait for a small break after the touch).
- **Stops** go beyond the zone or the swing; **targets** go at the next liquidity (old high/low).

### Timeframes, sessions, trader types
- **4H** = direction and big zones; **1H** = structure, liquidity, confirmation; **15m** = BOS/CHoCH, entry; **5m** = scalp entry, but noisy, with many fake breakouts.
- **Trader types:** scalper (1–5m, fast, high risk), day trader (15m–1H), swing (1H–4H), position (D/W).
- **Session timing post** (times were India time). In Pacific time: gold 6–10 AM, EURUSD 5–9 AM, USDJPY 10 PM–2 AM, GBPJPY 1–3 AM, US30 7:30 AM–1 PM, AUDUSD 5–10 PM.

## What 2020–26 gold said about each (all with real spread, a coin-flip control, 7 years)
| Concept | Result | Script |
|---|---|---|
| Trend + **FVG left by the breakout** | ✅ PASS: the v1.04 A+ trade (183 tr, PF 1.43, 5/7, beats random skipping 100%) | `gold_filters_research.py` |
| **Three soldiers / crows, H1** | ✅ PASS at 1R (194 tr, PF 1.23, 5/7, coin 100%); M15 fails | `gold_soldiers_research.py` |
| Retest of the broken Asia-range edge (limit) | 🟡 positive, and the best of the 3 entry styles | `gold_entry_types_research.py` |
| Gap entry, stop beyond the impulse candle, M15 | 🟡 thin lead (PF 1.07, 5/7) | `gold_three_areas_research.py` |
| Head & shoulders, M15 | 🟡 near miss (+84R, PF 1.15, only 4/7) | `gold_hs_double_research.py` |
| FVG filtering (skip dead gaps, trade the one that holds) | ❌ the filter hurts; a plain limit at every H1 gap is thin-positive (PF 1.07, 6/7), M15 loses | `gold_fvg_filter_research.py` |
| Engulfing / pin-bar confirmation entries | ❌ waiting for the candle costs money | `gold_entry_types_research.py`, `gold_amd_confirm_research.py` |
| AMD fake-out reversal | ❌ worse than a coin flip (−179R) | `gold_amd_confirm_research.py` |
| OB candle types (all six) | ❌ every type fails with honest fills | `gold_ob_types_research.py` |
| Demand 1, Demand 2, tight-stop gap | ❌ | `gold_three_areas_research.py` |
| Balanced vs reversal return | ❌ (looked great until a lookahead bug was removed) | `gold_return_type_research.py` |
| Real zone vs fake zone | ❌ both; the fake zone really is a trap (wins 7%) | `gold_real_vs_fake_zone_research.py` |
| Pin bars graded by strength | ❌ all 16 cells | `gold_pinbar_grade_research.py` |
| Structure retest, flags, double tops, three methods, marubozu, ERC filter | ❌ | respective `gold_*_research.py` |

## What the study adds up to
- **The vocabulary is sound; the picture-perfect examples are cherry-picked.** Each drawing shows a trade that worked. Seven years of gold shows the ones that didn't, too.
- **What survives on gold is continuation:** trade in the direction price is already pushing (breakout, trend agreement, a gap left behind). Turnaround setups (pin bars at highs/lows, fades, double tops, AMD reversals, zone bounces) lose.
- **The gap matters more than the candle shape.** An FVG adds information; ERC, marubozu, pin and engulfing shapes don't.
- **Enter at the level, not after the "confirmation".** The limit at the zone beat the engulfing and structure-break entries.
- **Higher timeframes are cleaner.** H1 results hold up far better than M5/M15, which matches the timeframe picture's "too much noise / too many fake breakouts".
- **Method lessons banked:** buy limits must fill on the ask, and filters must only use candles closed before the fill. Both bugs produced fake passes tonight before they were caught.
