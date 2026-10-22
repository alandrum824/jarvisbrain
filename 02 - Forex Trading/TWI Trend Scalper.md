---
status: active
project: forex-trading
type: reference
---
# TWI Trend Scalper

MQL5 scalping EA built 2026-10-12 (~3:05 PM PT) from Adam's gold M5 phone chart: "Support and resistance and trendline psar and ema 200 and ema 50 and ema 21 for cross build as scalping mlq5 ea" → "Build". Source: `TWI Trend Scalper.mq5` (this folder).

**Status (v1.02): still FAILS the 2020–26 gold test. v1.01 was 3/7 years, −$250. The best v1.02 variant (pattern stop, breaks only) is +$271 but positive in only 3/7 years, and almost all of it comes from 2026. Don't run it live.** Compiled on the laptop AAAFx terminal, **0 errors / 0 warnings**, deployed as `MQL5\Experts\Advisors\TWITrendScalper.mq5` (byte-identical to the vault copy). **Not attached. UNTESTED.** **Smoke test 2026-10-12** (`stg\trendscalper\smoke.py`: XAUUSD M5, 2025-10-01 to 2026-10-10, 1-min OHLC, $10k, defaults, 0.01):
- The mechanics work: 14 trades, 4 wins, −$46.30, PF 0.55, equity DD 1.03%. That sample is too small to judge.
- **The defaults choke it.** 1,163 signal bars led to only 14 entries:
  - **576 skipped by the 1R room filter** and **531 by the 3 ATR max stop**. Right after a flip, the PSAR dot sits at the far extreme, so using it for the stop makes stops too wide.
  - Location passed 1,121 times, so bounce-or-break is too loose to filter anything.
  - "Signals" counts every qualifying bar, not every cross.

**Odds going in (from the [[EA Scorecard]]):** zone fades on gold have failed against random entries every time. Gold's ~52-pt AAAFx spread eats small stops. EMA trend signals on gold only held on H4 longs ([[EMA Ribbon Trend Research]]). PSAR has never been tested. Adam chose to build before testing.

## Logic (closed M5 bars)
1. **Bias:** close above the EMA 200 → buys only; below → sells only.
2. **Trigger:** the EMA 21 crossed the EMA 50 in the bias direction within the last 3 bars.
3. **PSAR:** dots on the trade side. `SARFlipBars` (default 0 = off) can also require a recent flip.
4. **Location** (`LOC_BOUNCE_OR_BREAK`, the default):
   - **Bounce:** a bar in the last 6 tagged support (buy) or resistance (sell) within 0.3 ATR, and the signal bar closed back on the right side. Levels are the 5 nearest swing levels (fractal strength 3, last 150 bars) or a trendline through the last two swings.
   - **Break:** a bar in the last 6 closed through a falling resistance line or swing high (buy), or a rising support line or swing low (sell).
   - Swings only count once they're confirmed, so there's no look-ahead.
   - **Room:** skip if the next opposing level is closer than 1R. This exists to stop "buying into the 200 / an old box".
5. **Exits:**
   - **SL:** beyond the extreme of the last 5 bars or the PSAR dot (whichever is further), plus 0.2 ATR. Never tighter than 0.5 ATR or 5× spread; skip the trade if it's wider than 3 ATR.
   - **TP:** 2R.
   - Optional and off by default: BE, PSAR trail, opposite-cross exit.
6. **Guards:**
   - One position at a time, a hard SL on every order, no grid.
   - Session 03:00–12:00 NY, at most 6 trades/day, 3% daily loss stop.
   - Spread cap 60 pts, 3-bar cooldown.
   - **Flat at 16:50 NY, no entries until 18:05**: gold's daily break, after Adam's 2026-10-12 trade sat through the 17:00 close with a tight stop.

## v1.01 (2026-10-12, Adam: "Yes"): compiled 0/0, deployed, NOT attached
The v1.00 source is backed up at `stg\trendscalper\TWITrendScalper_v100.mq5`.
- **`TPMode = TP_MEASURED` (default), Adam's method:**
  - A **break** targets the break level + the pattern height. The height is the highest high minus the lowest low, from `MeasureExtraBars` (10) before the broken line's oldest anchor swing to the signal bar.
  - A **bounce** targets the next opposing level.
  - Both are capped 0.1 ATR short of the next opposing level (his "just under the box"). With no level and no pattern, it falls back to 2R.
  - Skipped if the target is under 1R (`MinTPR`); clipped at 6R (`MaxTPR`).
  - `TP_RR` keeps the v1.00 2R + room filter.
- **Stop from the swing extreme only.** `UseSARInStop=false`; true = v1.00.
- **One entry per EMA cross.** Stats count crosses, not bars, and each skipped cross is tallied once, under its last skip reason.
- **Tighter location:** 3 levels, a 3-bar lookback, 0.2 ATR touch tolerance (was 5 / 6 / 0.3). Breaks are checked before bounces.

### v1.01 gold 2020–26 (MT5, 1-min OHLC, $10k, 0.01 fixed, defaults; `stg\trendscalper\years.py`)
| Year | Net | PF | Trades | Win % | Equity DD |
|---|---|---|---|---|---|
| 2020 | −$51.47 | 0.87 | 170 | 34% | 0.8% |
| 2021 | +$53.52 | 1.18 | 179 | 39% | 0.6% |
| 2022 | −$22.37 | 0.93 | 154 | 34% | 1.0% |
| 2023 | +$33.99 | 1.09 | 185 | 40% | 0.8% |
| 2024 | −$9.36 | 0.98 | 161 | 35% | 1.1% |
| 2025 | −$261.91 | 0.68 | 161 | 25% | 3.2% |
| 2026 (to 10-10) | +$7.39 | 1.01 | 129 | 36% | 3.1% |

**Verdict: FAILS the [[EA Scorecard]] bar.** Total −$250 over 1,139 trades (about −$0.22 a trade at 0.01). 3 of 7 years are positive, and 2026 is flat. The coin-flip control was not built because a loser needs no control.
- **The gold spread costs about as much as the edge.** At ~52 pts, the spread is ~$0.52 a trade at 0.01, so before cost the signal is roughly +$0.30 a trade. That is an estimate: the tester already includes the spread, and the 1-min OHLC spread varies.
- **The location filter still barely filters:** 13–21 crosses a year are skipped for location. Bounce-or-break near *some* level is almost always true.
- **Fixed 0.01 on a price that doubled** makes later years' dollar swings larger. 2025's loss is partly that, but its PF of 0.68 is bad on any scale.
- The obvious next test, given that cost is the problem: the same EA on EURUSD (0–2 pt spread). Not run yet.

## v1.02 (2026-10-12, Adam: "Stop loss should of been below triangle" → "Test it"): compiled 0/0, deployed, NOT attached
The v1.01 source is backed up at `stg\trendscalper\TWITrendScalper_v101.mq5`. New input `StopMode`:
- `STOP_SWING` is the default and identical to v1.01.
- `STOP_PATTERN` puts the SL beyond the structure that invalidates the setup, plus `SLBufferATR`:
  - **Break:** the opposite triangle line at the signal bar (the rising support line for a buy, the falling resistance line for a sell). If there is none, the nearest swing low or high beyond entry.
  - **Bounce:** the level it bounced off.
  - It falls back to the swing stop if nothing is found.
- Test runner: `stg\trendscalper\years2.py <tag> key=value...` (yearly 2020–26 gold).

### v1.02 pattern-stop results, gold 2020–26 (same setup as v1.01; MaxStopATR raised to 6)
| Year | v1.01 swing stop | A: pattern stop, bounce+break | B: pattern stop, breaks only |
|---|---|---|---|
| 2020 | −$51 (PF 0.87) | −$129 (0.74) | −$84 (0.82) |
| 2021 | +$54 (1.18) | +$61 (1.17) | +$57 (1.15) |
| 2022 | −$22 (0.93) | +$21 (1.05) | −$20 (0.95) |
| 2023 | +$34 (1.09) | −$25 (0.94) | −$21 (0.95) |
| 2024 | −$9 (0.98) | −$59 (0.89) | −$37 (0.93) |
| 2025 | −$262 (0.68) | +$1 (1.00) | +$56 (1.07) |
| 2026 to 10-10 | +$7 (1.01) | +$306 (1.27) | +$321 (1.30) |
| **Total** | **−$250 / 1,139 tr** | **+$176 / 1,662 tr** | **+$271 / 1,503 tr** |

**Read:**
- **The pattern stop rescued the two volatile, trending years** (2025 and 2026), where tight swing stops got hunted, just like Adam's live trade today.
- **It didn't fix 2020–2024**, which are still mostly negative. B excluding 2026 is −$50 over 1,322 trades.
- **Still FAILS the scorecard bar:** B is positive in 3 of 7 years, A in 3 plus a flat 2025. The total depends on one 9-month window.
- **Dollar caveat:** fixed 0.01 lots on a price that has more than doubled since 2020 weights 2025–26 more heavily in dollars. The PF column is the fairer comparison.
- **Not tuned:** this is the first test of the idea. B (breaks only + pattern stop) is the best variant so far. Next would be EURUSD (cost) or a coin control; neither has been run.

## Adam's TP method (2026-10-12; built into v1.01 as TP_MEASURED)
On the live trade he moved the TP to "the end of the move": a **measured move**. He takes the height of the pattern (the drop/leg into the triangle, low ~4156 to high ~4178) and projects it from the breakout (~4171) with an arrow (~4192). Then he sets the TP just under the prior supply box (4184–4187), at **4187.23**. The live trade: long 0.01 @ 4171.89, SL 4169, after the falling trendline broke.

## Related
[[EA Scorecard]] · [[TWI ORB Momentum]] (time/sizing code source) · [[Forex Trading Fundamentals]] (S/R primer)
