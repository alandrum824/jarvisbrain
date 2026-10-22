---
status: active
project: forex-trading
type: reference
---
# TWI ORB Momentum

MQL5 EA built 2026-09-27 (~5:50 AM) after a night of testing showed that **the only thing positive in all three AAAFx years was the [[TWP ORB EA Reference|TWP ORB EA]] "EURUSD M5 NYSE NO GRID" preset** (see [[TWP24 EURUSD Sets]]). Every mechanical version of Pat's discretionary model failed that bar (see [[TWI ORB Demand Pullback]]). Adam chose "1": rebuild the proven momentum logic in our own EA, plus a London session. Source: `TWI ORB Momentum.mq5` (this folder).

**Status (2026-10-11): v1.32 compiled 0 errors / 0 warnings on the laptop AAAFx terminal (`MQL5\Experts\Advisors\TWIORBMomentum.mq5`, byte-identical to the vault copy). Backtested; not attached anywhere; nothing live. FTMO presets are in this folder; 2026-10-12 tests: 0 breaches in 24 single-leg runs, Phase 1 passes 6/12, Phase 2 passes 11/12 (see the v1.32 section).**

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

## 2020–26 replay + coin-flip control (2026-10-11)
Script `orb_momentum_longrun_research.py` replays v1.20 on AAAFx M1 data from 2020-01-02 to 2026-10-09 (`C:\Users\aland\stg\obh`):
- Cost: the entry bar's own spread.
- Clock: the proven AAAFx clock (London time before 2022-03-27).
- Control: 50 runs with a coin-flip direction instead of the break direction.

**Replay vs MT5 v1.20 at 0.01 (the engines agree):**

| Window | Replay | MT5 v1.20 |
|---|---|---|
| 2023–24 | +$15.25, 49 trades | +$18.42, 50 trades |
| 2024–25 | +$20.24, 59 trades | +$23.53, 61 trades |
| 2025–26 | +$90.67, 66 trades | +$85.39, 66 trades |
| 2026 | +$5.19, 31 trades | +$8.76, 33 trades |

**All markets and sessions:**

| Market / session | Trades | R | PF | Win | Years + | Beats coin flip |
|---|---|---|---|---|---|---|
| **EURUSD NY** | 405 | **+32.2** | 1.21 | 63% | **6/7** (2021 −10.9R) | **96%** |
| EURUSD London | 472 | −36.1 | 0.84 | 54% | 3/7 | 10% |
| GBPUSD NY | 444 | −0.9 | 0.99 | 58% | 4/7 | 76% |
| GBPUSD London | 492 | +4.2 | 1.02 | 59% | 3/7 | 40% |
| USDJPY NY | 394 | −4.3 | 0.97 | 58% | 5/7 | 68% |
| **USDJPY London** | 525 | **+36.1** | 1.18 | 63% | **6/7** | **100%** |
| Gold NY | 355 | +15.9 | 1.11 | 60% | 4/7 | 94% |
| Gold London | 471 | −5.9 | 0.97 | 58% | 3/7 | 50% |

EURUSD NY by year: 2020 +10.9R, 2021 −10.9R, 2022 +4.7R, 2023 +1.1R, 2024 +4.3R, 2025 +14.9R, 2026 +7.1R.

**Read:**
- **EURUSD NY is the first strategy in the vault to beat its random control.** The never-seen 2020 and 2022 are both positive.
- **USDJPY London is a strong lead.** It came out of 8 cells tested together, so it needs its own MT5 confirmation before it counts.
- Full context in [[EA Scorecard]].

## MT5 tester confirmation 2022–26 (2026-10-11)
Ran headless with `C:\Users\aland\stg\obh\orbmom_mt5_runs.py` and `_risk.py`: every tick, 1:100, v1.20. The windows start 2022-04-04, because before 2022-03-27 the AAAFx clock is London time, which the EA's `ApplyUTC0History` doesn't model. The reports are in the laptop terminal under `tester_configs\orbmomentum_v120_<SYM>_M5_<sess>_{001|002risk}_everytick_*_20261011_*`.

| Leg | 2022–23 | 2023–24 | 2024–25 | 2025–26 | 2026 | Read |
|---|---|---|---|---|---|---|
| **EURUSD NY, 0.01, $200** | **+$43.84 PF 1.28** (new) | +$18.42 | +$23.53 | +$85.39 | +$8.76 | **5/5 positive** |
| USDJPY London, 0.01, $200 | +$79.83 | −$7.56 | +$105.37 | −$25.31 | +$12.16 | 3/5, lumpy |
| **USDJPY London, 0.5% risk, $10k** | **+$523 PF 1.42** | **+$93 PF 1.06** | **+$662 PF 1.66** | **+$192 PF 1.12** | **+$43 PF 1.04** | **5/5 positive, DD ≤ 3.6%** |
| Gold NY, 0.01, $10k | +$44 | +$165 | −$250 | +$398 | +$410 | 4/5, DD $432 |
| Gold NY, 0.5% risk, $10k | −$118 | +$251 | −$260 | +$450 | +$125 (26 trades, risk skips) | 3/5, fails |
| Gold London, 0.01, $10k | −$83 | −$36 | −$17 | +$422 | +$451 | 2/5, fails |

**Why USDJPY needs risk sizing:**
- Trade by trade, the replay and MT5 agree on direction 100% of the time and on outcome 99% (2025–26: 80 matched trades).
- The edge is real in R in every window.
- At a fixed 0.01, the stop size varies with the range. In 2023–24 and 2025–26 the losses fell on wider-range days, so in dollars a loss outweighed a win.
- Constant-% risk turns every window positive.
- The catch is that 0.5% risk needs roughly $1,000+ before the lot math rises above the 0.01 minimum on USDJPY. On ~$200, a USDJPY trade risks ~2% at 0.01.

**Gold:** the R edge doesn't hold up in MT5 once trades are sized properly. Dropped.

## Independent check by Grok (2026-10-11; Adam sent the chart)
- **Setup:** same v1.20 spec, no tuning. Data is **Dukascopy** bid/ask, 2020-01 to 2026-10, with **$7/lot commission** and estimated swap. AAAFx's verified commission is $0, so Grok's costs are harsher than ours.
- **EURUSD NY:**
  - 410 trades, **+0.031R/trade (95% CI −0.053 to +0.114)**, about +13R.
  - Beats the coin flip 97%.
  - At 1% risk on $10k: +11.8% net, max DD $2,103.
  - Positive in 4/7 years by avg R. 2021 was deeply negative, and 2023 and 2024 were slightly negative.
- **USDJPY London:**
  - 513 trades, **+0.049R/trade (CI −0.025 to +0.123)**, about +25R.
  - Beats the coin flip 100%.
  - At 1% risk: +25.1% net, max DD $1,208.
  - Positive in 3/7 years at 0.01 lot.
- **Gold NY:** −0.004R/trade, beats the coin flip 86%, −3.1% at 1% risk. **Fails.**
- **Failures:** EURUSD London, GBPUSD London and gold London all fail, the same as ours.
- **Read:** an independent second data feed confirms the same two legs and the same failures, so the direction signal is real. **The edge is thin, though.**
  - Grok's per-trade expectancy is +0.03 to +0.05R, and both confidence intervals include zero.
  - Our AAAFx replay ($0 commission) shows about +0.08R (EURUSD) and +0.07R (USDJPY).
  - The $7/lot commission alone costs about 0.015R/trade on EURUSD.
  - Marginal years flip sign between data feeds, and a few strong years (2020, 2025, 2022/2024 on USDJPY) carry the total.
- **Expect:** roughly +2–5% a year per leg at 1% risk, with 12–21% drawdowns. It's a real but small edge, not a money machine.

## FTMO $10k 2-Step Challenge simulation (2026-10-11; Adam: "run it against FTMO rules 10k 2 step challenge")
Script `orb_momentum_ftmo_research.py`, log `C:\Users\aland\stg\obh\orbmom_ftmo.log`.
- **Rules modelled:** Phase 1 +10%, Phase 2 +5%; Max Daily Loss 5% and Max Loss 10% of the initial $10k; minimum 4 trading days; no time limit.
- **Trades and costs:** the 2020–26 AAAFx replay trades, with **$7/lot commission** subtracted (−0.015R/trade EURUSD, −0.023R USDJPY).
- **Sizing:** fixed $ risk per trade.
- **Starts:** 301 weekly start dates, 2020–2025. They overlap, so they're correlated (a 2021 start shares the same drawdown).

| Set | Risk/trade | Pass BOTH phases | Fail (10% max loss) | Fail (daily) | Phase 1 median | Phase 2 median |
|---|---|---|---|---|---|---|
| EURUSD only | 1.0% | 64% | 28% | 0% | 554 d | 117 d |
| EURUSD only | 2.0% | 52% | 47% | 0% | 171 d | 97 d |
| **Both legs** | **1.0%** | **68%** | 32% | 0% | **205 d** | 114 d |
| **Both legs** | **1.5%** | **63%** | 37% | 0% | **102 d** | 87 d |
| Both legs | 2.0% | 57% | 43% | 0% | 76 d | 42 d |
| Both legs | 2.5% | 34% | 37% | 29% | 42 d | 16 d |

**Stress test at Grok's thinner edge** (−0.03R/trade more): both legs 1.0% = 64%, 1.5% = 60%, 2.0% = 46%.

**Read:**
- 1–1.5% risk with both legs passes about 6 times in 10.
- It's slow: Phase 1 takes ~3–7 months and Phase 2 another ~3–4.
- **Never above 2%.** At 2.5%, two same-day stops (London + NY) hit the 5% daily limit.
- The failures are 10% max-loss breaches during the long flat stretches (2021). This is a thin edge pushed through a hard floor.

**External FTMO test (2026-10-11, Adam sent the chart):** 1,760 starts. Plain 1% passes ~54%. A 1.5% → 0.75% drawdown-step risk rule passes ~55%, with 15% passing within 6 months. Fixed 2–2.5% fails most of the time. No-Friday reaches ~81%, but that is in-sample and the Friday effect isn't significant. The switches it mentions are NOT in this EA (still v1.20).

## New-legs scan (2026-10-11; Adam: "how can we pass faster" → "yea run them")
Script `orb_momentum_newlegs_research.py` ran the v1.20 rules unchanged on 16 new market/session cells. Each session is anchored to its local open: NY 09:30, London 08:00, Tokyo 09:00. AAAFx M1 data: FX from 2020, indices from 2022-03 (UK100 from 2020-09). Each cell was checked against 50 coin-flip runs.

The pass bar was **pre-registered** before any results: beats the coin flip in ≥ 95% of runs, ≥ 5/7 years positive (4/5 for shorter histories), and net > 0.

**Only US30 NY passed:**
- 249 trades, **+30.0R, +0.121R/tr**, PF 1.34, 64% win.
- 5/5 years positive: 2022 +11.0, 2023 +3.8, 2024 +0.9, 2025 +9.7, 2026 +4.7.
- Beat **100%** of coin-flip runs (coin median −0.1R).
- With ~16 cells tested, about one pass is what chance alone would produce. That's why US30 still had to be confirmed in MT5 (below).

**Failed:**
- NAS100 NY (+7.9R, beat the coin flip only 70%)
- SPX500 NY (88%, 3/5 years)
- GER30 London (80%, 3/5)
- UK100 London (−34.5R)
- JPN225 Tokyo (62%)
- AUDUSD NY (86%, 4/7)
- AUDUSD London and Tokyo
- USDCAD NY and London
- AUDJPY Tokyo and London
- USDJPY Tokyo (−49R)
- EURUSD Tokyo (−53R)
- EURUSD London (−29R)

Every Tokyo cell lost.

**US30 vs EURUSD NY:** they traded on the same day on only 66 of US30's 249 trade days. R correlation 0.17, and both lost on the same day only 14% of the time. They're mostly independent, so US30 adds R/year rather than doubling the same bet.

**MT5 confirmation (every tick, 0.5% risk):**
- **At $10k the result is distorted.** US30's minimum lot is 0.01 = $0.10/pt, and its 2.2× stops are 400–900 pts. So 135 setups were skipped for risk, all on wide-range days (results: +$203 / +$99 / −$214 / +$37 / +$36).
- **At $100k (no skips), it matches the replay: 243 vs 247 trades.**

| Window | Trades | Net | PF | R |
|---|---|---|---|---|
| 2022–23 | 82 | +$4,189 | 1.28 | +8.99R |
| 2023–24 | 43 | +$2,024 | 1.26 | +4.12R |
| 2024–25 | 49 | −$187 | 0.98 | −0.11R |
| 2025–26 | 44 | +$375 | 1.04 | +0.94R |
| 2026 | 25 | +$2,138 | 1.58 | +4.69R |

Total **+18.6R (~+0.08R/tr)**. Four of the five windows are positive, and the fifth (2024–25) is flat. The edge is weaker than the replay's, but **it passes. Promoted to leg 3.**
- On a $10k FTMO account at 1.5% risk ($150), a 0.01 US30 lot fits. Check FTMO's US30 contract spec before going live (the symbol name and $/pt may differ from AAAFx).

**FTMO 2-Step $10k with 3 legs:**
- Starts run weekly from 2022-04 to 2025-10 (184 starts, the US30 history window). US30 was stressed down to its MT5 edge (+0.076R/tr), with spread only on US30 and $7/lot commission on FX.

| Legs | R/yr | 1.0% risk | 1.5% risk |
|---|---|---|---|
| 2 legs | 14.5 | pass 99%, median 338 d, 17% within 6 mo | 97%, 210 d, 39% within 6 mo |
| **3 legs** | **~19–21** | **100%, 232 d, 29% within 6 mo** | **90%, 139 d, 60% within 6 mo** |

At 2.0% risk with 3 legs, the pass rate falls to 62% and 12% of starts fail the daily limit. Three trades in one day can go −6%.

**Caveat:** the absolute pass rates are flattered. This window skips 2020–21, including EURUSD's −10.9R in 2021. From 2020, the 2-leg pass rate was 63–68%, not 97–99%. **The reliable part is the relative gain: the 3rd leg cuts the median time to pass by about a third and doubles the share that pass within 6 months.** Stay at ≤ 1.5% risk.

## v1.30 (2026-10-11; Adam: "Yea") — compiled 0/0, deployed to the laptop terminal, NOT attached
- **Files:**
  - Vault `TWI ORB Momentum.mq5` = deployed `MQL5\Experts\Advisors\TWIORBMomentum.mq5`.
  - v1.20 backups: `C:\Users\aland\stg\obh\TWIORBMomentum_v120_backup.mq5/.ex5`. The v1.20 binary is also installed as `Advisors\TWIORBMomentum120.ex5`, for comparisons only.
- **New inputs.** All off by default, so trading is identical to v1.20.
  - **Lot modes:** `LotMode` = Fixed (static) / Risk % (auto) / **Balance-scaled** (`BalancePerLot`: 0.01 lot per X balance).
  - **Trade days:** `TradeMonday`…`TradeFriday`. `TradeFriday=false` is Grok's SkipFriday.
  - **Drawdown-step risk:** `UseDDRiskScheme`, `DDRiskTriggerPct` 4, `DDRiskReducedPercent` 0.75. Risk % mode only: RiskPercent normally, the reduced % while balance sits ≥ 4% below its peak.
  - **Prop guard:** `UsePropGuard`, `PropInitialBalance` 10000, `PropDailyLossPct` 5, `PropMaxLossPct` 10, `PropSafetyBufferPct` 1, `PropTargetPct` 10 (set 5 for Phase 2, 0 once funded). How it works:
    - The daily floor is measured from max(balance, equity) at **Prague midnight** (FTMO's day).
    - The max-loss floor is static.
    - Both trip 1% early.
    - **Before each trade:** if this trade's SL plus every open SL on the account (all symbols, all EAs) could breach a floor, the trade is skipped.
    - **On every tick:** at a floor, it closes our positions and halts. A daily halt lasts until the next Prague day; a max-loss halt is permanent. At the target it closes and halts.
    - State is account-wide in terminal global variables (`TWIORBM_<login>_*`), so the 3 charts share it and restarts keep it. The tester clears these at the start of each run.
- **Regression check:** v1.30 with defaults matches the real v1.20 binary run on the same data, every number identical (EURUSD 2025–26: $79.49, 66 trades).
  - The +$85.39 from September doesn't reproduce with *either* binary. The tester's price history was updated since then (re-exported 2020+ data). Old dollar figures are about ±$6 per window from this.
- **Guard tests (MT5, every tick, $10k):**

| Test | Setup | Result |
|---|---|---|
| A | EURUSD NY, 1.5% + DD-step, guard on, Phase 1 target 10% | **Target hit 2023-01-05** (9 months from 2022-04-04). 53 trades, no floor hits, closed and halted. 3 trades sized at the reduced 0.75%. |
| B | US30 NY, deliberately oversized 4% risk, guard on, no target | Daily floor tripped 2022-06-15 (equity 10,399.28 vs floor 10,399.56), closed, resumed the next FTMO day. After that, almost every trade was **blocked before entry**, because a 4% stop would breach the 4% buffered daily floor (14 trades in 4.5 yrs). Works as designed. |
| C | EURUSD, `TradeFriday=false` | 59 trades vs 65, Friday switch confirmed. |

- **Operating note:** with three legs at 1.5%, the pre-trade check blocks a third trade on the same Prague day while the other two are still open (1.5 × 3 = 4.5% > the 4% buffered limit). That's the protection that stops the 2% daily-limit failures seen in simulation.
- **On FTMO's server:** set `ApplyUTC0History=false` (that fix is AAAFx-history only). Check the US30 symbol name and $/pt. Attach on 3 charts (EURUSD: `UseNY`; USDJPY: `UseLondon` + `UseNY=false`; US30: `UseNY`), all Risk % 1.5, `UseDDRiskScheme` + `UsePropGuard` on.

## v1.31 (2026-10-11; Adam sent Grok's v1.30 fix list) — compiled 0/0, deployed to the laptop terminal, NOT attached
v1.30 backup: `C:\Users\aland\stg\obh\TWIORBMomentum_v130_backup.mq5/.ex5`. All fixes keep the defaults identical to v1.20.

**Fixes:**
1. **DD step:** `DDRiskReducedPercent` is replaced by `DDRiskFactor` (0.5 = half of RiskPercent, must be < 1), so it can never raise risk.
2. **No room near the floor:**
   - Lots shrink to fit the room above the floor.
   - If even the min lot doesn't fit, it counts FTMO days. After `PropStuckDays` (5) such days it sets halt 4 and sends an alert (Print + Alert + SendNotification).
3. **Target:**
   - The target only fires after `PropMinTradingDays` (4).
   - It closes everything, then stays halted only if the *balance* is ≥ target. Otherwise it resumes.
   - Alert on the pass.
4. **Shared state across charts:**
   - Halt and day start are re-read from global variables every tick. The first chart to see a new FTMO day records the start.
   - A halt closes every position in our magic range on **any** symbol.
5. **UTC+0-history fix:** only applies when the account company/server contains "AAAFx". Live, it also checks the server clock is NY+7 and alerts if not.
6. **Low-priority items:**
   - Lot normalization.
   - `MaxRiskPerTradePct` ceiling for fixed and balance-scaled modes.
   - A foreign position with no SL triggers a warning instead of blocking (equity floors still cover it).

**Tests (MT5, every tick):**

| Test | Result |
|---|---|
| R: regression, defaults, EURUSD 2025–26 | Identical to the real v1.20 binary |
| T: target 0.3% | "Target reached but only 1/2/3 of 4 trading days, still trading" → halted at 4 days, balance 10,068.72 ≥ target, pass alert ✓ |
| A: EURUSD Phase 1, 1.5% + DD factor 0.5 | Target 2023-01-05 after 53 trading days, balance 11,000.04, 0 floor hits. Same as v1.30 ✓ |
| B: US30 at an oversized 4% | v1.30 froze at 14 trades. v1.31 shrank lots 211 times, 242 trades, +$8,398, 22 daily-floor stops (each a −4% day capped by the guard), 0 max-loss hits ✓ |

**Not testable in the tester:** live cross-chart sync (the tester runs one chart). Verify on a demo account with EURUSD + USDJPY attached together before live.

## Grok / Muse versions (2026-10-11), reviewed in full
- **v1.40 ("Muse"):** v1.30 + robustness extras (deviation cap, trade-allowed gate, adopted-position risk restore, optional entry buffer / retry / ATR filter / breakeven / bad-fill). **None of the 5 fixes.**
- **v1.41:** the DD step is fixed (validated + latched until a new peak), plus scale-to-room. **Still has** the target lock, unsynced halts and the UTC0 default.
- **v1.42:**
  - Adds per-tick halt re-read, a no-room log line (no alert, no halt), `PropTargetLockPct`, and the UTC0 default → false.
  - **Still has the target lock** (no resume, no minimum trading days).
  - `PropTargetLockPct` > 0 can freeze an account just under the target (no trades → can't reach it).
  - The UTC0=false default mis-times every AAAFx backtest before 2026-03-07.
- **Adam's presets:** Phase 1/2 + Aggressive. EURUSD-only, 1% risk (Aggressive 2%), DD off. The v1.42 set has ApplyUTC0History=false.
- Test batch: `stg\obh\preset_tests_142.py`, 4 presets × {v1.42, v1.31} × 4 FTMO starts (Apr 2022/23/24/25, 18-month windows, EURUSD NY, $10k). AAAFx tests force ApplyUTC0History=true. Summary script: `stg\obh\preset142_summary.py` (reads the tester agent log).
- **Results (2026-10-11).** Each cell gives the target date and days from the start:

  | Preset | Apr 2022 | Apr 2023 | Apr 2024 | Apr 2025 | Passed |
  |---|---|---|---|---|---|
  | Phase 1, 1% | 2023-03-23 (353d) | not reached in 18 mo (+3.6%) | 2025-04-21 (385d) | 2025-10-09 (191d) | 3/4, slow |
  | Phase 1 Aggressive, 2% | 2022-06-13 (70d) | **−9%, dead** (guard stopped at the 9,100 floor) | 2024-10-15 (197d) | 2025-07-07 (97d) | 3/4, 1 dead |
  | Phase 2, 1% | 2022-06-13 (70d) | 2024-08-14 (499d) | 2024-10-15 (197d) | 2025-07-07 (97d) | 4/4 |
  | Phase 2 Aggressive, 2% | 2022-05-12 (38d) | **−9%, dead** | 2024-07-10 (100d) | 2025-06-16 (76d) | 3/4, 1 dead |

  - **v1.42 and v1.31 placed the same trades with the same results in 31 of 32 runs.** The exception is the 2023 Aggressive window. There, v1.31 stopped 2 trades earlier and called a no-room halt with an alert on 2023-08-21. v1.42 kept trying and logged "no room" every day for over a year.
  - **Muse's extras don't change the edge;** they are plumbing. No FTMO hard breach happened in any run: the guard always stopped 1% before the line.
  - **2% risk kills 1 challenge in 4** (the 2023 chop). 1% never dies but takes 6–16 months, and one start never got there.
  - My earlier recommendation (1.5% + DD-step + both legs) is still untested in this batch. The single v1.31 run at 1.5% + DD-step hit Phase 1 on 2023-01-05.

## v1.32 (2026-10-11; Adam: "Yes" to merging Muse's additions + 6 presets): compiled 0/0, deployed to the laptop terminal, NOT attached
v1.31 plus the useful parts of Muse v1.40–1.42. Every new switch is off or 0 by default, so trading is identical to v1.31; the regression run is in the batch below.

**Merged:**
- `MaxDeviationPoints` = 10 (entry slippage cap).
- Trade-allowed gate (EA/account/terminal) with an hourly warning. The guard still runs while trading is paused.
- Symbol trade-mode check at init.
- Adopted positions restore their risk from the SL, so R stats survive a restart.
- `EntryBufferPoints`.
- `RetryTransientReject`: spread, sizing and soft prop rejects keep watching the window; a halt always ends the day.
- ATR range filter (`UseRangeFilter`, M15 ATR14, 0.25–1.75).
- Breakeven (`UseBreakeven`, 0.5R).
- `MaxBadFillPoints`.
- `DDRiskLatch`: reduced risk until a new balance peak. Default false = v1.31 behavior.
- Input validation. AvgR and bad-fill counts in the summary.

**Not merged:**
- `PropTargetLockPct`: it can freeze an account just under the target.
- The UTC0 default = false: it mis-times AAAFx tests. v1.31 already ignores the UTC0 fix on non-AAAFx brokers.
- Muse's DD-reduced-percent and scale-down code: v1.31's factor and `PropFitLots` already cover both.

**Files and backups:**
- v1.31 backup: `stg\obh\TWIORBMomentum_v131_backup.*`.
- Build script: `stg\obh\make_v132.py`.

**Presets** are in this folder, 6 files: `TWI ORB Momentum FTMO10k {Phase1|Phase2} {EURUSD NY|USDJPY London|US30 NY}.set`.
- 1.5% risk, DD-step on (4% trigger, factor 0.5), guard on (buffer 1%, minimum 4 trading days, stuck-halt 5 days).
- Target 10% for Phase 1, 5% for Phase 2.
- `ApplyUTC0History=true` is safe on FTMO (ignored automatically there).
- Run all three legs of the same phase on one account; the halt and day state are shared across charts.

**Tests:** `stg\obh\preset_tests_132.py`. It runs regression R, then the 6 presets × 4 FTMO starts (Apr 2022/23/24/25, 18-month windows), each leg on its own chart. Parsed by `stg\obh\preset132_summary.py`.

**Results (2026-10-12).** Each cell is calendar days to the target, or where the account stood after 18 months. A dash means no FTMO breach and still trading.

| Preset | Apr 2022 | Apr 2023 | Apr 2024 | Apr 2025 | Passes |
|---|---|---|---|---|---|
| P1 EURUSD NY | 276d | − (−3.0%) | 358d | 111d | 3/4 |
| P1 US30 NY | 185d | − (+4.0%) | − (+1.7%) | − (+8.5%) | 1/4 |
| P1 USDJPY London | 98d | − (+2.7%) | 210d | − (+0.1%) | 2/4 |
| P2 EURUSD NY | 56d | − (−3.0%) | 119d | 77d | 3/4 |
| P2 US30 NY | 52d | 241d | 88d | 56d | 4/4 |
| P2 USDJPY London | 60d | 221d | 114d | 400d | 4/4 |

- **No max-loss or daily-floor hits in any of the 24 runs.** At 1.5% with DD-step, no single leg ever came close to dying.
- **Phase 1 single-leg passes 6 of 12; Phase 2 passes 11 of 12.** The April 2023 start is the hard one: on a rough sum of the three legs' P/L it is about +3.7% after 18 months, so even the combined account would not pass Phase 1.
- The P1 EURUSD April 2022 run hit the target on 2023-01-05 with 53 trading days, the same as the earlier single v1.31 1.5% + DD-step run. That is consistent with v1.32 trading like v1.31.
- **Caveats.** Each leg had its own $10k chart, so the shared-account behaviour (combined drawdown, one halt for all three legs) is untested. Cross-chart sync needs a demo check before FTMO goes live. Phase 2 really starts the day Phase 1 passes, not in April.
- **Regression passed (2026-10-12).** R2 (`v132_regress.py`, every input explicit at default): 65 trades, $81.59. The v1.31 binary re-run on the same day's data (`stg\obh\v131_rerun.py`) gave the identical 65 / $81.59, with all 133 deal lines matching. The old $79.49 / 66 reference came from earlier tester data; that's data drift, not a code change. **Use 65 / $81.59 as the reference from now on.**

**Tester gotcha (banked 2026-10-11):** any input left out of `[TesterInputs]` takes the **previous run's value**, not the EA default.
- The first v1.32 regression run inherited the guard on and a 5% target from the preceding Phase 2 batch. The equity of 200 was under the 9,100 floor, so it halted at once: 0 trades, invalid.
- **Always pass every input.** `v132_regress.py` does, using the preset with defaults swapped in.
- The presets cover all 61 v1.32 inputs (verified by diff).

## Build prompt (given to Adam 2026-10-11, on his "give me strategy in a prompt")
This is a self-contained spec of v1.20 plus the validated market list, so the EA can be rebuilt or explained anywhere. The same rules are in "Rules" above. The prompt was sent in chat.

## Open

- [x] Out-of-sample 2023–24: done (NY-only positive; London failed, now off).
- [ ] Deployment decision is Adam's. The live terminal and account 8996721 are on the VPS (unreachable since 2026-09-25, see [[Jarvis Remote Control]]).
