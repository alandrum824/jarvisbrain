---
status: active
project: forex-trading
type: reference
---
# TWI ORB Momentum

MQL5 EA built 2026-09-27 (~5:50 AM) after a night of testing showed that **the only thing positive in all three AAAFx years was the [[TWP ORB EA Reference|TWP ORB EA]] "EURUSD M5 NYSE NO GRID" preset** (see [[TWP24 EURUSD Sets]]). Every mechanical version of Pat's discretionary model failed that bar (see [[TWI ORB Demand Pullback]]). Adam chose "1": rebuild the proven momentum logic in our own EA, plus a London session. Source: `TWI ORB Momentum.mq5` (this folder).

**Status: v1.20 compiled 0 errors / 0 warnings on the laptop AAAFx terminal (`MQL5\Experts\Advisors\TWIORBMomentum.mq5`, byte-identical to the vault copy). Backtested; not attached anywhere; nothing live.**

**v1.10 (2026-09-27, ~6:35 AM; Adam: "run all sessions test also Asia London American and New York"):** added optional **Asia** (20:00 NY, Sun–Thu evenings, magic +2) and **America** (08:00 NY, magic +3; that start time is my assumption, since the TWP manual gives no hours) sessions, **both OFF by default**, so the tested NY+London configuration stays the default. The 2023 clock was verified from EURUSD bars (Friday closes 20:59 summer / 21:59 winter = UTC+0), and history starts 2023-04-30.

## Rules (from the TWP preset, decoded with the vendor manual + mode map in [[Build TWP Set Files]])

Per session (NY 09:30 and London 03:00, New York time; each can be switched off):
1. **Range:** high/low of the first 55 minutes (M1 bars).
2. **Entry:** within the next 10 minutes, the **first touch** of either edge (bid ≥ high → buy; bid ≤ low → sell) enters at market in that direction. The first touch decides the session, trade or not.
3. **SL = 2.2 × range size** from the fill; **TP = 0.75 × SL**; both on the order.
4. One trade per session per day. The position runs until SL/TP (optional max holding hours and Friday flat, both off by default like the preset). No new trade while that session's previous position is still open. **No grid, no averaging, no martingale.**
- Each session has its own magic (`MagicBase` = NY, `MagicBase+1` = London). **Default 0.01 fixed lots** (the tested size); a risk-% mode via `OrderCalcProfit` is available.
- Clock: NY+7 server, AAAFx UTC+0 history before 2026-03-07 (proven, see [[Build TWP Set Files]]).

## Why London (and not Asia / NY 08:00)

Replayed the TWP logic from its rules first (`orb_momentum_session_research.py`, EURUSD M1, $0.2-pip cost). The replay reproduced the TWP EA's own backtest closely (NYSE: +$20 / +$100 / +$3 vs TWP +$31 / +$108 / +$17), which confirms the decoding. Same rules on other sessions: **London 03:00 +$32 / +$58 / +$17** (PF 1.21 / 1.40 / 1.28), positive all 3 years. Asia 20:00 −$41 / −$17 / +$7 and NY 08:00 −$43 / +$27 / −$14 were rejected.

## Backtests (2026-09-27, MT5 tester, EURUSD M5, every tick, $400, 1:100, 0.01 lots)

Reports: laptop terminal `tester_configs\orbmomentum_v100_EURUSD_M5_<variant>_everytick_<span>_20260927_*.htm`.

| Variant | 2024-03-11 → 2025-03-07 | 2025-03-10 → 2026-03-06 | 2026-03-09 → 2026-09-26 | Total |
|---|---|---|---|---|
| NY only | +$17.80, PF 1.11, 87 tr, DD 8.1% | +$107.61, PF 1.84, 85 tr, DD 5.8% | +$20.28, PF 1.30, 48 tr, DD 7.9% | +$145.69 |
| London only | +$50.32, PF 1.34, 120 tr, DD 8.4% | +$39.69, PF 1.26, 96 tr, DD 6.1% | +$32.28, PF 1.54, 61 tr, DD 4.0% | +$122.29 |
| **Both (default)** | **+$68.12, PF 1.22, 207 tr, DD 10.0%** | **+$147.30, PF 1.52, 181 tr, DD 8.4%** | **+$52.56, PF 1.41, 109 tr, DD 6.4%** | **+$267.98** |

- **NY-only matches the TWP EA's own results** (+$17 / +$108 / +$31, 49 / 93 / 94 trades), so our build faithfully reproduces the vendor logic.
- **Both sessions:** ~+27% a year on $400 at 0.01, about 4 trades a week, win rate 60–66%, worst equity DD 10.0% (2024–25).
- Costs are real (every tick with AAAFx history spreads; commission $0 verified). Ticks are generated from M1 (real-tick history only covers recent weeks).

## Sizing for a $200 account (2026-09-27; Adam: "I have 200$ in my account")

Adam's live balance is now ~$200 (his figure, not verified from the terminal; the vault last showed $371.89 on 2026-09-01). 0.01 lots is the broker minimum, so risk can't be scaled down further. From the both-sessions backtests at 0.01: median loss $3.23 (1.6% of $200), 90th-percentile loss $6.71 (3.4%), worst single loss $14.49 (7.2%), worst losing streak 5 (−$24.42), **worst equity drawdown $45.63 (≈23% of $200)**. Margin is ~$12 per 0.01 EURUSD position at 1:100, fine. Expected ~$107/yr at 0.01 (≈50%/yr on $200 if the future resembles the backtest). Running one session only barely lowers the DD (NY-only $33.90, London-only $37.80), so it's not worth giving up half the trades.

## Unseen year, sessions and lot sizes (2026-09-27, ~6:35–7:05 AM)

Adam: "Run that [2023–24] and also up the lot size .10 and run all sessions", then "Run America and NY only .04 lot size". Every tick, EURUSD, all at his **$200** balance unless noted. Windows: 2023-05-08 → 2024-03-08 (**never seen before**), then the three earlier ones.

| Setup | 2023–24 | 2024–25 | 2025–26 | 2026 |
|---|---|---|---|---|
| NY+London 0.01 (old default) | **−$22.37 PF 0.93, DD 29%** | +$68.12 | +$147.30 | +$52.56 |
| NY+London 0.10 | −$146.77, DD 91% | −$100.04, DD 73% | −$141.67, DD 77% | −$95.15, DD 70% |
| All 4 sessions 0.01 | −$52.49 | −$17.57, DD 42% | +$142.17 | +$25.83 |
| All 4 sessions 0.10 | −$128.31 | −$101.02 | −$98.45 | −$150.93 |
| Asia only 0.01 | −$19.40 | −$48.88 | −$23.51 | −$1.86 |
| America (08:00) only 0.01 | −$10.72 | −$36.81 | +$18.38 | −$24.87 |
| **NY only 0.01 ($400)** | **+$18.76 PF 1.14** | +$17.80 | +$107.61 | +$20.28 |
| London only 0.01 ($400) | **−$41.13 PF 0.79** | +$50.32 | +$39.69 | +$32.28 |
| Original TWP no-grid set 0.01 ($400) | −$14.51 PF 0.91 | +$30.93 | +$108.36 | +$16.67 |
| **NY only 0.04** | **+$73.93, DD 40%** | **+$70.26, DD 50%** | **+$429.35, DD 37%** | **+$80.40, DD 54%** |
| America only 0.04 | −$44.12 | −$171.08, DD 92% | +$72.65 | −$99.67, DD 76% |
| NY+America 0.04 | +$29.81 | −$161.32, DD 92% | +$502.00 | −$182.30, DD 92% |

**Verdict:** **NY-only is the only configuration positive in all 4 years, including the unseen one.** London failed out-of-sample (it was the cause of the 2023 loss), so **NY-only should be the default** (not yet changed in code). America, Asia and "all sessions" add losses. 0.10 on $200 blows the account every year. **0.04 NY-only makes money every year but with 37–54% equity drawdowns**, meaning the account would at some point sit near half. (The DD % is relative to the running peak, so on a grown balance the dollar DD is larger.)

## H1 trend filter, drawdown reducers, simple grid (2026-09-27, ~7:10–7:30 AM)

Adam: "make sure we trend direction from 1h time frame and see if there is anything we can add to help with drawdown or simple grid". Replay (`orb_momentum_filters_research.py`, NY-only, 0.01, EURUSD M1 2023-05 → 2026-09 incl. the unseen year; closed-trade DD). Note: this replay is harsher than the MT5 EA on 2023–24 (−$7 vs the EA's +$19); use it for comparisons, not absolutes.

| Variant | 2023–24 | 2024–25 | 2025–26 | 2026 | Total | Worst DD ($ / % of $200) |
|---|---|---|---|---|---|---|
| Baseline | −$7 | +$20 | +$100 | +$3 | +$116 | $42 / 21% |
| **H1 EMA50 trend (price above/below)** | **+$15** | **+$20** | **+$90** | **+$1** | **+$125** | **$27 / 13%** |
| H1 EMA200 | −$8 | +$36 | +$65 | +$13 | +$106 | $32 |
| EMA50 & EMA200 aligned | −$17 | −$1 | +$80 | −$14 | +$47 | $41 |
| Break-even at 0.4× SL | +$36 | +$21 | +$70 | +$3 | +$129 | $38 / 19% |
| Max hold 6h | +$20 | +$10 | +$9 | +$9 | +$48 | $21 / 11% |
| Skip oversized ranges | −$33 | +$36 | +$81 | −$3 | +$82 | $58 |
| Grid, 1 add at 50% of SL (same SL/TP) | +$4 | +$13 | +$158 | +$6 | +$182 | $51 / 26% |
| EMA50 + BE0.4 | +$13 | +$9 | +$61 | +$8 | +$90 | $32 |
| EMA50 + grid | +$30 | +$17 | +$136 | −$7 | +$176 | $48 / 24% |
| EMA50 + BE0.4 + grid | +$38 | +$6 | +$95 | +$12 | +$151 | $53 / 27% |

**Verdict: the H1 EMA50 trend filter alone is the best risk-adjusted change**: all 4 years positive, worst DD cut ~37% ($42 → $27), total profit slightly up, ~25% fewer trades. Combining it with BE or the grid doesn't beat it. **The simple grid adds profit but increases drawdown (24–27%)**, the opposite of the goal. Not yet built into the EA (awaiting Adam's go on v1.20: NY-only default + H1 EMA50 filter).

## v1.20 confirmed in MT5 (2026-09-27, ~7:40–8:00 AM; Adam: "Go")

v1.20 = **NY only by default (London off) + H1 EMA50 trend filter on** (the first touch only trades if the edge is on the trend side of the last closed H1 EMA50; otherwise that session is done for the day). Compiled 0/0, vault copy byte-identical. MT5 every tick, EURUSD, **$200**, 4 windows incl. the unseen 2023–24:

| Lots | 2023–24 | 2024–25 | 2025–26 | 2026 | Total | Worst equity DD |
|---|---|---|---|---|---|---|
| **0.01** | +$18.42 PF 1.16 | +$23.53 PF 1.22 | +$85.39 PF 1.80 | +$8.76 PF 1.17 | **+$136.10** | $33.01 (15%) |
| **0.02** | +$36.29 | +$46.68 | +$170.23 | +$17.23 | **+$270.43** | $66.24 (28%) |
| 0.04 | +$72.74 | +$93.52 | +$340.61 | +$34.55 | +$541.42 | $132.42 (49%) |

Trades 50 / 61 / 66 / 33 (~65/yr); the trend filter blocked 22–34 touches per year.

**Honest comparison with NY-only without the filter (MT5, 0.01):** +$18.76 / +$17.80 / +$107.61 / +$20.28 = +$164.45, worst DD $33.90. So **in the real tester the filter did NOT cut drawdown** (≈$33 either way) and gave up ~17% of profit; the replay had overstated its benefit (its no-filter 2023 was harsher). It improved PF in 2 of 4 years (2024–25 1.22 vs 1.11; 2023–24 1.16 vs 1.14) and lowered it in 2 (2025–26 1.80 vs 1.84; 2026 1.17 vs 1.30). Roughly neutral: kept on because Adam wants trades only in the H1 trend direction and it costs little. **It is not the drawdown cure; lot size is.**

## Open

- [x] Out-of-sample 2023–24: done (NY-only positive; London failed, now off).
- [ ] Deployment decision is Adam's. The live terminal and account 8996721 are on the VPS (unreachable since 2026-09-25, see [[Jarvis Remote Control]]).
