---
status: active
project: forex-trading
type: reference
---
# TWI fxalexg HS (Pine indicator, V1)

Version 1, the **original, un-optimized** build of [[fxalexg HS Strategy Spec]], made 2026-09-30 (~7:30 PM) on Adam's "Yes". Source: `TWI fxalexg HS.pine` (this folder).

**Status:**
- Created with Make a copy… of TWI HS Pullback. The editor title was verified as "TWI fxalexg HS" before loading.
- **Compiled clean and saved** (after two Pine return-type fixes).
- **On the desktop chart since ~8 PM 2026-09-30.** Adam swapped indicators himself; the chart now has Adaptive H&S Detector, TWI fxalexg HS, Sweep Reversal Map. It runs without runtime errors.

## Video rules implemented
- LS → NP1 → head beyond the LS → **flip: a candle closes beyond NP1** (the pattern exists; the neckline slopes the reversal way).
- NP2 = the extreme from the head until the next confirmed neckline-side swing. NP2 must be beyond NP1.
- **Aggressive (high risk):**
  - The right shoulder is inside the LS zone (|RS − LS| ≤ tolerance) with an engulfing or morning/evening-star close.
  - Enter at the close. Stop beyond the head (default) or beyond the RS; both are video options.
- **Confirmed (actual trade):**
  - A neckline break, then a retest within N bars, then an engulfing or star closing on the right side of the neckline.
  - Enter at the close.
- **Pattern death:**
  - price trades through the head ("fake H&S");
  - after the aggressive entry, a close back beyond the RS;
  - a close back through the neckline during the retest phase.
- Style input: Both (scale in) / Aggressive only / Confirmed only.

## TEST defaults (not video rules)
- Swings: 2/2 bars (confirmation delay 2).
- Head beyond LS: 0.25 ATR. Shoulders level within 0.5 ATR. Zone pad 0.25 ATR.
- LS→head leg: 3–60 bars. Setup age: 150 bars.
- Break = close beyond, buffer 0. Retest tolerance: 0.3 ATR within 30 bars.
- Star middle body ≤ 30% of its range.
- Confirmed stop: beyond the 3-bar retest swing + 0.1 ATR.
- TP: measured move (head-to-neckline depth from the neckline at entry). The alternative is fixed R (4R, from the PENDING 4.01 screenshot).
- MinRR 0.
- Strong-level filter (prior swing within 0.5 ATR) and prior-trend filter (≥ 3 ATR into the LS): **both OFF** by default.

## Scorecard
Columns for Aggressive / Confirmed / Combined:
- trades, W/L, win rate, net R, expectancy, PF, max DD
- average planned R:R, average stop in ATR

Plus: aggressive trades whose pattern later broke the neckline vs died first, and filter/TP states.

Alerts: aggressive buy/sell, confirmed buy/sell.

## Related
[[TWI HS Pullback]] (Adam's silver-trade rules, the head-to-head comparison on the same chart), [[fxalexg HS Strategy Spec]].

## V1 baseline scorecards (untouched defaults, OANDA, read by Jarvis 2026-09-30 ~8 PM)
| Market / TF | History from | Aggressive (n, win%, net, PF) | Confirmed (n, win%, net, PF) | Combined net / PF |
|---|---|---|---|---|
| XAUUSD M30 | 2026-01-01 | 23, 22%, −8.8R, 0.51 | 10, 10%, −7.1R, 0.21 | −15.9R / 0.41 |
| XAUUSD H1 | 2025-01-01 | 24, 17%, −6.4R, 0.68 | 16, 44%, +5.3R, 1.59 | −1.1R / 0.96 |
| XAUUSD H4 | 2023-01-02 | 14, 36%, +24.2R, 3.69 | 8, 13%, −5.7R, 0.18 | +18.5R / 2.16 |
| GBPJPY H1 | 2025-01-01 | 20, 30%, +1.4R, 1.10 | 19, 37%, +0.5R, 1.04 | +2.0R / 1.08 |
| GBPJPY H4 | 2023-01-01 | 19, 32%, +1.6R, 1.13 | 13, 54%, +10.8R, 2.80 | +12.4R / 1.65 |

Read:
- **Every sample is small** (8–24 trades per cell). Nothing here is proof yet.
- M30 (not one of his timeframes) loses badly.
- His timeframes (H1/H4) range from flat to positive. GBPJPY H4 confirmed (his example market and TF): 13 trades, 54% win, +10.8R, PF 2.8.
- Aggressive entries die before the neckline break 13–21 times out of 14–24. That's consistent with "high risk"; the gold H4 +24R rests on a few large winners.
- Aggressive average stops are ~2.5 ATR (stop beyond the head), vs ~1.4 ATR for confirmed.

**Display bug:**
- An LS/HEAD label is drawn for every candidate, including ones that never flip. In a trend that means a HEAD label on every swing.
- Necklines are extended right indefinitely and become steep rays.
- Fix pending Adam's OK: draw only on the flip, delete on death, end the neckline at the break or death.
