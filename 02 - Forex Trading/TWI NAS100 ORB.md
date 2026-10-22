---
status: active
project: forex-trading
type: reference
---
# TWI NAS100 ORB

MQL5 EA built 2026-10-22 after Adam sent a Roboquant "9:30 box" ad ("Build this an EA mlq5") and then asked: "study and learn all different ORB strategy and make a good working one". Source: `TWI NAS100 ORB.mq5` (this folder), terminal copy `MQL5\Experts\Advisors\TWINAS100ORB.mq5` on the desktop AAAFx terminal.

**Status (2026-10-22 2:43 PM PT): v1.01 ATTACHED IN SHADOW MODE on the desktop AAAFx terminal (account 8996721), NAS100 M1 chart, Adam: "Do what you think is best". No orders; virtual trades go to `C:\Users\aland\AppData\Roaming\MetaQuotes\Terminal\Common\Files\TWI_NAS100_ORB_shadow.csv`. First possible shadow trade: 2026-10-23 after 10:00 NY.** v1.01 = v1.00 with `UseTrendFilter` default false (the no-filter config is the stronger one, below); compiled 0/0, vault copy byte-identical to the terminal copy. The 14:41 start logged "v1.01 … ENTRY_MIDPOINT … trend off … SHADOW MODE (no orders)"; the 14:43 profile start logged "loaded successfully" (attach method in [[TWI Gold Asia Breakout]]). Going live needs Adam's explicit go after the shadow log agrees with the backtest.

## How it was chosen
1. **The ad's exact rule** (`orb_930_box_research.py`, 16 pre-registered cells): 09:30–09:45 box, break, SL at the other side. Passes only on NAS100 (2R +99.8R, PF 1.16, coin 100%); gold, EURUSD and US30 fail. Fading the break loses everywhere, worse than a coin flip. Details: [[EA Scorecard]].
2. **ORB family survey** (`orb_family_research.py`, NAS100 2022-03 → 2026-10, 117 cells: 9 entry families × 1R/2R/hold-to-close + 4 filters on ORB15/30 and MID15/30). Selection pre-registered: rank on the train period (to 2024-12-31), then require holdout 2025–26 avg R > 0, PF > 1.1, beats ≥ 95% of 50 coin-flip runs, ≥ 4 of 5 years positive.
   - Families, from the research: classic ORB on 5/15/30/60-min boxes; midpoint-retest limit; Zarattini-Aziz first-candle direction (SSRN 2023: 5-min candle on QQQ, gross edge real, a 2026 replication found it zero net of costs); Crabel stretch (10-day noise from the open); filters NR7, narrow box, trend (yesterday's close vs 20-session SMA) and gap direction.
   - **Every family makes money on NAS100** (the 09:30 open's momentum is real): ORB15 2R +100R (the earlier test reproduced exactly), ORB30 1R +95R (55% wins, 5/5 years), ZA15 2R +128R (PF 1.23, 5/5, train +0.135 / holdout +0.118 R per trade, the most stable), MID30 hold-to-close +106.5R (PF 1.30, 5/5, coin 100%), Crabel +57–86R (5/5).
   - **Holding to the 16:00 close beats fixed targets** in most families; the 30-min box beats 15-min.
   - **Pre-registered winner: MID30 + TREND, hold to close**: 253 trades, +66.7R, +0.264R/trade, PF 1.41, 4/5 years, coin 96%; train +0.372 → holdout +0.090. Small sample, and the holdout fell sharply.
3. **Robustness** (same 75 cells each on US30 2022–26, gold and EURUSD 2020–26): **the NAS100 winners don't transfer.** MID30 hold: US30 +37R (coin 68%), gold −75R (1/7 years), EURUSD −92R. ZA15 2R: gold −134R, EURUSD −295R. MID30+TREND hold: gold −93R (0.71 PF). EURUSD: 0 cells pass. Cells that pass elsewhere (leads only; ~4 of 75 would pass by chance): **US30 + narrow-box filter** (ORB15+NARROW hold 557 tr +128R PF 1.39, coin 100%; ORB30+NARROW, ORB30+NR7, MID15+NARROW all pass) and **gold + gap filter** (ORB15+GAP hold 876 tr +99R PF 1.20, 5/7 years, coin 96%; ORB15+GAP 1R/2R and ORB30+GAP hold also pass). A whole filter family passing on one market is more convincing than a lone cell, but each needs its own MT5 check.

## Rules (v1.00, all inputs adjustable)
- Box = high/low of the first `BoxMinutes` (30) M1 bars from 09:30 NY. One trade per NY day.
- `EntryMode`: **BREAK** (first touch of an edge until 12:00, market; test it on every tick, not 1-min OHLC), **MIDPOINT** (default; after the first touch, a limit at the box midpoint in that direction until 12:00), **FIRST_CANDLE** (Zarattini: direction of the box candle at its close, doji < 10% body skipped).
- SL = the opposite side of the box. `TargetR` 0 (default) = no target, flat at 15:59 NY; otherwise TP = TargetR × risk.
- Filters: `UseTrendFilter` (default off since v1.01, yesterday's 15:59 close vs SMA of the last 20), `UseGapFilter` (off). A touch against a filter ends the day.
- Safety chassis per [[EA Build Prompt - What Works]]: risk % (default 1, capped at 2), halved after 3 straight losses; pauses after −2% realized day / −5% week; kill switch 15% below the peak balance (terminal global variables, manual re-arm via `ResetKillSwitch`); a stop-out can't cross the kill floor; a min lot that over-risks is skipped with an alert; positions by magic + symbol; **SHADOW mode on by default on live charts** (virtual trades to `Common\Files\TWI_NAS100_ORB_shadow.csv`, no orders; ignored in the tester).
- Clock: NY+7 server, AAAFx UTC+0 history before 2026-03-07 (same code as [[TWI ORB Momentum]]).

## MT5 tester
Runner `C:\Users\aland\stg\obh\nasorb_mt5_runs.py`: 1-min OHLC, $100k, fixed 0.1 lots, R read from the EA's summary line; yearly windows 2022-04 → 2026-10 + one full run. The tester log confirmed our EA ran (its own summary line). R per year (MT5 vs replay):

| Config | 2022 | 2023 | 2024 | 2025 | 2026 (to 10-21) | Full: trades / R / avg / PF | Replay full |
|---|---|---|---|---|---|---|---|
| **MID30 hold, no filter** | +30.4 | +9.1 | +20.8 | +24.9 | **+9.4** | **574 / +98.1R / +0.171 / 1.31, 5/5** | 557 / +106.5R / +0.191 / 1.30 |
| MID30+TREND hold (pre-registered pick, v1.00 default) | +8.0 | +20.3 | +25.6 | +15.7 | −0.9 | 264 / +72.3R / +0.274 / 1.35, 4/5 | 253 / +66.7R / +0.264 / 1.41 |
| ZA15 2R (first candle) | +23.2 | +7.2 | +31.6 | +39.1 | +0.2 | 1,032 / +105.4R / +0.102 / 1.18, 5/5 | 996 / +128.0R / +0.129 / 1.23 |
| ORB15 2R (the ad), 1-min OHLC | −4.8 | −20.5 | +7.0 | +3.0 | −33.8 | 1,169 / −46.8R / −0.040 / 0.93 | 1,128 / +100.0R |

**MID30 hold with no filter is the best result: 5/5 years in both engines, MT5 within ~8% of the replay, and the only config positive in 2026.** The three limit/candle configs match the replay closely. **The break entry doesn't:** in 1-min OHLC the tester only has 4 prices per M1 bar, so the first price past the edge is often the bar's high/low and the market entry pays the whole breakout candle. Live ticks would fill nearer the edge. **Every-tick re-run of the ad's rule (Model=0) confirms the artifact:** 2022 +21.2R, 2023 +3.9R, 2024 +32.9R, 2025 +32.6R, 2026 −17.6R = **+73.0R, 4/5 years** (replay +99.8R). The full-period window was killed when the PC ran low on memory; the yearly windows cover it. **Method lesson: test market-on-touch entries on every tick, not 1-min OHLC; limits and bar-open entries are fine on OHLC.**

## Related
[[EA Scorecard]], [[TWI ORB Momentum]], [[TWI Range Breaker]], [[EA Build Prompt - What Works]]
