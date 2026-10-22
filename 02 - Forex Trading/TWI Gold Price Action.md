---
status: active
project: forex-trading
type: ea
---
# TWI Gold Price Action

**Status: built 2026-10-13, compiled 0 errors / 0 warnings (under a check name, then removed). Not deployed, not attached. MT5 tester 2026-10-13: Soldiers matches the replay (196 tr, PF 1.22, 5/7 years); H&S beats it (827 tr, PF 1.17, 6/7); Gap fails (3/7 years, stays OFF).** Second gold EA, separate from [[TWI Gold Asia Breakout]] (own file, magic 20261020–20261022). Built at Adam's request ("build a second ea with these strategies incorporated", "I want a brand new one") from the chart lessons in [[Chart Lessons Study]], using only the setups that held up on the 2020–26 gold replays.

Source: `02 - Forex Trading/TWI Gold Price Action.mq5` (deploy name when approved: `Advisors\TWIGoldPriceAction.mq5`).

## Modules
| # | Module | Default | Rules | Replay evidence |
|---|---|---|---|---|
| 1 | Three Soldiers / Crows, H1 (magic +0) | **ON** | 3 bars same direction, body ≥ 0.5 ATR, each closes beyond the prior close and in the top/bottom 30%; market at the next open; SL beyond bar 1 ± 0.1 ATR; TP 1R; time exit 48 bars | 194 tr, +17.4R, PF 1.23, 5/7, coin 100% (`gold_soldiers_research.py`) = PASS |
| 2 | Head & Shoulders, M15 (magic +1) | off | 5 alternating confirmed 3/3 swings, head ≥ 0.5 ATR beyond the shoulders, shoulders within 1 ATR; first neckline close within 20 bars → market; SL beyond the right shoulder + 0.1 ATR; TP measured move clipped 1–4R; time exit 96 bars | 959 tr, +84.4R, PF 1.15, 4/7, coin 98% (`gold_hs_double_research.py`) = near miss |
| 3 | FVG gap entry, M15 (magic +2) | off | impulse body ≥ 1.5 ATR leaving an FVG → limit at the near gap edge (valid 48 bars); SL beyond the impulse ± 0.1 ATR; TP 2R; time exit 48 bars | 2,794 tr, +123.7R, PF 1.07, 5/7, coin 100% (`gold_three_areas_research.py` GAP_DEEP) = thin lead |

Shared: one position per module, hard SL on every order, no grid or martingale. `RunMode = RUN_SHADOW` by default (virtual trades → `MQL5\Files\TWIGoldPA_shadow.csv`; the tester always runs LIVE). Account Guard identical to Asia Breakout v1.02 (globals prefix `TPA_G_`), counting all three magics. Wilder ATR(14) to match the replays. Sizing: fixed 0.01 or risk-%.

## Known differences from the replays (the MT5 tester decides)
- H&S swings are rebuilt each bar from the history known at that bar; the replay built them once from the full history, so a later more-extreme swing can occasionally change which pattern it saw.
- Gap: several limits can be pending at once and the first to fill cancels the rest; the replay gave priority to the oldest setup.
- Time exits count wall-clock bar periods from the fill; the replay counted M1 bars.

## Tester results (2026-10-13, MT5 1-min OHLC, $10k, 0.01 lot, AAAFx XAUUSD 2020-01-01 → 2026-10-10)
| Module | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 | Full | vs replay |
|---|---|---|---|---|---|---|---|---|---|
| Soldiers H1 | +7.90 | +99.11 | +7.58 | −37.37 | +123.56 | −126.95 | +363.45 | **196 tr, +$447.85, PF 1.22, win 52%, eqDD 3.5%** | 194 tr, PF 1.23, 5/7 → **matches** (5/7) |
| H&S M15 | −30.63 | +22.02 | +1.34 | +8.44 | +123.30 | +408.40 | +152.94 | **827 tr, +$684.63, PF 1.17, win 44%, eqDD 3.2%** | 959 tr, PF 1.15, 4/7 → **better** (6/7; 2022 is flat) |
| Gap M15 (rerun, alone) | +64.61 | −19.03 | −58.89 | −36.68 | −94.85 | +83.03 | +1,019.35 | **2,388 tr, +$920.49, PF 1.08, win 36%, eqDD 5.3%** | 2,794 tr, PF 1.07, 5/7 → **fails** (3/7; 2026 alone carries it). Stays OFF. (The first run was invalid: cached inputs left H&S on.) |

Method lesson (banked): the tester remembers the last run's inputs; **pass every module switch explicitly** on every run (`UseSoldiers`, `UseHeadShoulders`, `UseGapEntry`). After the last run, **wait for the tester terminal to exit before relaunching** with attach_gold_asia.ini, or the relaunch collides with it and EA #1 never loads (happened 10-13: shadow EA down 3:08–4:39 AM; the scripts now wait). Runner: `C:\Users\aland\stg\trendscalper\payears.py` (`runpa.sh`, `rungap.sh`).

## Next
1. Soldiers held up in MT5 (H&S too): deploy as `TWIGoldPriceAction` in SHADOW on an XAUUSD chart (any timeframe), with Adam's go-ahead.
