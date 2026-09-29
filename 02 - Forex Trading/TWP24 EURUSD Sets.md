---
status: active
project: forex-trading
type: reference
---
# TWP24 EURUSD Sets

Five session-specific `.set` files for the TWP ORB EA on EURUSD, built with the grid system disabled — Adam's call after deciding the grid was too risky, even though in practice it rarely hit the $300 daily drawdown cap.

## Where they live
`C:\Users\aland\HQ\TWP24 EURUSD Sets\` — `twp24 EURUSD NY.set`, `AMERICA.set`, `LONDON.set`, `EUROPE.set`, `ASIA.set`.

**Not yet staged into a terminal.** No MT4/MT5 install tied to TWP was found on this machine, so these are sitting in the HQ folder, not a terminal's Presets/Sets folder. They need to be moved into the right terminal manually, or Jarvis needs the exact terminal path to do it.

## How they were built
Base: TWP Robot's own shipped **EURUSD AMERICA** preset (v1.13.1, downloaded 2026-07-08) — the only EURUSD set file found on the machine. Per session file, only the session-window selector and its matching DST region were changed (mapped from TWP's own other session set files, not guessed). Each file got its own magic number so they don't collide if more than one runs at the same time. Everything else — lot size, TP, entry logic (instant retrace off the opening-range edge), filters, risk caps — was left exactly as TWP shipped it: **still the stock 0.10 fixed lot size**, not resized for Adam's account.

## Open — lot sizing was never finished
Adam asked to resize these for an **$800 account**. Context he gave: 0.60 lots, up to 3 concurrent trades, up to 3 trades per session, with the grid on, worked fine and was profitable at that size — it rarely hit his $300 daily drawdown cap. What actually blew it up wasn't the grid or the trade-count caps, it was that he eventually pushed the **lot size itself too high**. So the grid/3-concurrent/3-per-session structure is the validated part; lot size is the variable to size conservatively for $800.

That resizing question was never answered — the session hit a technical bug (voice-line's brain desynced after an interrupted turn and started returning empty replies) before Jarvis could respond, and the fix required a restart that wiped the conversation. See [[Review Trades and Risk Management]] for the general risk-review job; this note is the state to pick the lot-sizing work back up from.

**Do not size these from theory.** Work it from the account balance, the $300/day and 4%/8% drawdown caps already in the base file, and Adam's stated risk tolerance — and confirm with him before calling it final, per the no-live-changes-without-confirmation rule.

## Also open: live account login
Last login attempt (2026-08-16) to the live account (ending 8996721, AAAFxGlobal-5 Real) failed with "invalid account" four times in a row and the terminal shut down. Account number or credentials may be stale, or the EA may be running on a different machine/VPS entirely. **Superseded 2026-08-30: login works fine now** — confirmed live and authenticating cleanly throughout the entire overnight session (see below). Whatever caused the 2026-08-16 failure had resolved itself by the time of this session.

## 2026-08-29/30 — real backtest data replaces the theory (lot-sizing question substantially answered)

A long overnight session ran real Strategy Tester backtests (not theory) against account 8996721's actual balance (~$391–$420 across the night) instead of the assumed $800. Key findings, all at $400 deposit / 0.01 lots (the real broker minimum) unless noted:

**Stock `EURUSD America.set` (vendor default, grid ON, 8-level ladder):** 0.01 lots → 416 trades, +$83.70 net, PF 1.78, Sharpe 2.11. At 0.30 lots the same config **got margin-called** on 2025.11.05 (stop-out 18% of the test period, account fell from $400 to $179.34) — direct proof that 0.30 lots + this grid ladder is too large for a $400 account, full stop. Grid OFF at the same 0.30 lots survived clean (+$18.05) — the grid, not the raw position size alone, was the primary driver of the blowup, though even grid-off still showed 32.63% equity drawdown at that size.

**Community-sourced files** (from a TradeWithPat Discord thread, "custom-setfiles" channel — author dananiq22, gold leg credited to joewiller92, EU leg to birdseedlw66; explicitly built and shared as **prop-firm-friendly configs, calibrated for a $25,000 account** — author's own words: "adjust accordingly" for other sizes): `EURUSD_M5_NYSE_NO_GRID.set` (real no-grid build, `iSLMode=2/iSL=2.2` — a real, non-ambiguous stop) tested at native 0.01 lots: **100 trades, -$0.10 net, PF 1.00, Sharpe -0.01, but only 6.73% equity drawdown — the tightest risk control of anything tested all night.** Flat, but genuinely safe. The gold companion file (`XAUUSD Breakout Asia.set`, substituted for the author's exact "S/D Asia" file which isn't in this machine's library) at scaled-down 0.01 lots: 10 trades only (too small a sample), -$0.92 net. At the file's native 0.6 lots (correctly proportioned for $25k, NOT $400) it would be wildly oversized — confirmed by testing a different community file's native 0.5-lot size on $400, which also got margin-called.

**A "3 trades at once / 3 per session" regular-tier EURUSD config** (Adam's own real historical usage, confirmed via real MT5 mobile screenshots) was rebuilt from the stock `EURUSD America.set` base with `iMaxTradesAtOnce=3`/`iMaxTradesDaily=3` (up from the stock default of 1/1) at 0.01 lots: **764 trades, +$167.51 net, PF 2.16, Sharpe 3.45, win 76.31%** — the best EURUSD dollar result of the night. Saved as `EURUSD America 3x3.set` in this same folder, with `iLots=0.01` and `User=Alandrum24` baked in (the saved file initially still had the vendor's 0.1-lot default — caught and fixed before it went live).

**4-symbol portfolio replication** (Adam's real "~$300 to ~$970" trading history, clarified as EURUSD+GBPJPY+CHFJPY+gold run simultaneously, not a single file): ran all four legs independently at $400/0.01 lots — EURUSD (above, +$167.51), GBPJPY NYSE (+$82.72, PF 2.24, Sharpe 5.20, DD 4.17%/14.09%), CHFJPY NYSE (+$47.33, PF 2.44, Sharpe 8.20, DD only 1.30%/5.34% — tightest of the four), XAUUSD Breakout Asia (+$681.04, PF 1.41, Sharpe 3.05, but the riskiest — 37.82% equity DD, largest single loss -$72.06). **Naive sum ≈ $978.60 — explicitly NOT a real combined-account number**, since MT5's Strategy Tester gave each leg its own separate $400 rather than one shared pool; a real account running all four would face shared margin and shared drawdown caps. A true merged-timeline equity curve was offered as a follow-up but not yet built.

**Real bug found and worked around:** the compiled `TWP ORB EA.ex5` **hung indefinitely** (confirmed via flat CPU over repeated checks, not just slow) on two different grid-ladder configs during testing tonight, for reasons never definitively isolated (not simply ladder depth — a 10-level CHFJPY ladder ran clean while a smaller 3-level one hung). Safe to force-kill mid-hang since it's Strategy Tester/demo only, no capital at risk from doing so. Worth knowing if a future backtest run on this EA appears to sit doing nothing — check CPU progress before assuming it's just slow.

## Live deployment (2026-08-30) — three legs attached on RisenAdam, real money

Adam confirmed via direct terminal action (not Jarvis/Claude, who has no GUI control over MT5 — checked and confirmed no automation tool reaches MT5, only file/CLI access): **EURUSD, GBPJPY, and XAUUSD charts attached with TWP ORB EA on RisenAdam**, using the three ready-to-load `.set` files built and verified above, all at `iLots=0.01`:
- `regular (most popular)\g_EURUSD America\EURUSD America 3x3.set`
- `regular (most popular)\g_GBPJPY NYSE\GBPJPY NYSE 0.01.set` (new file, built tonight, same GBPJPY NYSE config confirmed clean in the portfolio test above)
- `regular (most popular)\_XAUUSD Asia\XAUUSD Breakout Asia 0.01.set` (new file, built tonight)

AutoTrading confirmed ON by Adam directly. CHFJPY was intentionally left off this initial deployment (only 3 of the 4 tested legs went live). Gold dashboard screenshot confirmed correct load: magic number 900790009, TP 8x/SL 1x, EMA(250) filter all matching the built file. **ZeroPoint was explicitly discussed and NOT added** — see [[ZeroPoint]] for that decision. Next real step, not yet done: verify EURUSD and GBPJPY dashboards the same way, and check the Experts log tab (not just the visual dashboard) for a clean init on all three.

### Pulled back to EURUSD-only (2026-08-31/09-01)
GBPJPY and gold charts were both removed. GBPJPY came off Adam's own call closing charts before bed (2026-08-31, ~06:47 server time). Gold ran on through the night and took two straight losing shorts — real closed trades: -$35.70 (07:35 server time, the EA's own `iMaxHolding=600` time exit) and -$7.29 (~01:47 server time 09-01, Adam manually closed it early from mobile, reason=MOBILE). Balance after both: $371.89. Adam decided to stop there rather than let gold keep bleeding and run **EURUSD America only** for now — the `EURUSD America 3x3.set` config above is the one to reattach. GBPJPY and gold `.set` files stay built and validated in this folder if Adam wants to bring either back later, but neither is live right now. Confirmed via live MT5 check 2026-08-31 ~23:15: balance $371.89, zero open positions, no trades since the two above — matches this account.

#### Gold leg's real risk profile decoded (2026-08-31, from the exact deployed file)
Read `regular (most popular)\_XAUUSD Asia\XAUUSD Breakout Asia 0.01.set` directly (magic 900790009 — matches the dashboard screenshot Adam confirmed at go-live). **This was never a "missing stop-loss" bug** — the earlier open question about `iSL=0` (from [[TWP ORB EA Reference]]) doesn't apply to this file at all:
- `iLotsMode=1` (static), `iLots=0.01` — fixed, not auto-scaled.
- `iSLMode=2`, `iSL=1`, `iATR_=200`, `iATRTimeframe=15` — a real stop, almost certainly 1x the 200-period M15 ATR on gold. `iTPMode=2`, `iTP=8` — TP is 8x that same unit. An 8:1 reward:risk ratio needs a high win rate to be profitable, and the 1x-ATR stop itself is a wide, real dollar distance on gold.
- `iMaxHolding=600` (minutes = 10 hours) — this, not the stop-loss, is what actually closed the -$35.70 trade. The position sat inside its (wide) SL band for the full 10 hours without ever getting stopped out.
- `iUseAdvancedRisk=false` — the 4%/8% daily/overall drawdown circuit breaker present in other TWP configs is **off** on this file. Nothing at the EA level was capping cumulative risk on this leg beyond the single-trade SL and the 10-hour timer.

**Real read:** the stop-loss exists and is real, it's just wide relative to a ~$370 account, and there's no account-level drawdown breaker backing it up on this leg. If gold comes back, the lever isn't "add a stop" — it's tightening `iSL` below 1x ATR, shortening `iMaxHolding`, or turning on `iUseAdvancedRisk` with a real cap.

**Fix applied 2026-09-01 (Adam confirmed):** edited `XAUUSD Breakout Asia 0.01.set` directly — `iMaxHolding` 600→180 (10hr→3hr time-based exit), `iUseAdvancedRisk` false→true (activates the existing `iDailyDrawdown=4`/`iOverallDrawdown=8` caps). **Left `iMaxCapital=11000` untouched and still unconfirmed** — don't know if the 4%/8% drawdown % is computed against this field or against real account balance; if it's the former, those caps are effectively meaningless on a ~$370 account (4% of $11,000 = $440, bigger than the whole account). Worth confirming before trusting the breaker actually brakes. `iSL` (the 1x-ATR stop itself) left as-is, still not tightened. Not re-attached live — gold stays off RisenAdam per the EURUSD-only decision above until Adam decides to bring it back.

**Backtest attempt failed twice (2026-08-31 ~23:32-23:37):** staged this exact file into the terminal's tester cache (`MQL5\Profiles\Tester\TWP ORB EA.set`) and ran it via the native Strategy Tester. First run hung — flat CPU for several minutes, no report, matching the known hang bug below. Force-killed (tester-only, no capital at risk), tester cache restored from backup. Second attempt (tighter Aug-only window, fastest tick model) never even spawned a tester process — no report, no log entry. Not worth a third attempt without deeper diagnosis; the decoded `.set` values above are the reliable source for this config's real behavior, not backtest output.

## GBPUSD FTMO sets, fitted to Adam's account and backtested (2026-09-27)

Adam supplied 3 TWP ORB EA sets (GBPUSD **Asian / London / NYSE**, saved 2026-09-01 by another TWP user for a **$100K FTMO** challenge) and said: "Adjust it and try the grid, make it fit and test it" → "Just add it to our current EA configuration so it fits ours."

**Final sets:** `C:\Users\aland\HQ\TWP GBPUSD Sets\GBPUSD {Asian|London|NYSE} grid (Adam).set`, with the originals in `originals (FTMO 100K)\`. **The only change is `User` → Adam's TWP login** (verified by diff). Nothing else needed to change:
- **`iLotsMode=1` is % of balance** (see the correction in [[Build TWP Set Files]]), so their 0.2% / 0.2% / 0.1% already scales down to $400. The EA traded the 0.01 minimum lot, with the grid adding 0.02–0.03 legs.
- **Two attempted "fits" broke it:** `iLots=0.01` (= 0.01%) and `iMaxCapital=400` each produced **zero trades**. Per the vendor manual, `iMaxCapital` is a **profit target** ("Maximum account equity": close all and stop once equity reaches it), so 400 on a $400 account meant "target already hit". 1000 and 105000 are just far-off targets (identical results at $400).
- **The `iMaxCapital` question is answered:** the 10% overall drawdown cap is measured on equity from when the EA started. Three runs stopped dead at exactly **10.03% equity DD (~$40)** and never traded again.

**Backtests** (EA v1.13 from `Downloads\TWP-ROBOT-v1.13.1.zip`, installed on the laptop terminal as `Advisors\TWPORBEA`; AAAFx GBPUSD M5, 1-minute OHLC like the vendor, $400, 1:100 (the account's cap; the vendor used 1:500), inputs via `ExpertParameters=`, confirmed in the input dump). `iGMTShift` 3 for Mar 9 – Sep 26 2026, 0 for Mar 10 2025 – Mar 6 2026 (AAAFx history is UTC+0 before the switch):

| Set | Window | Trades | Win % | Net | PF | Max equity DD | Notes |
|---|---|---|---|---|---|---|---|
| **Asian** | 2026 (6.5 mo) | 312 | 79% | **+$24.10** | 1.21 | 7.6% ($32) | |
| **Asian** | 2025–26 (12 mo) | 450 | 79% | **+$61.54** | 1.38 | 12.5% ($66) | |
| **London** | 2026 | 247 | 81% | **+$65.47** | 2.38 | 6.1% ($27) | |
| London | 2025–26 | 43 | 42% | −$38.03 | 0.22 | 10.1% | 10% breaker hit 2025-04-02, dead after |
| NYSE | 2026 | 54 | 56% | −$38.17 | 0.37 | 10.0% | breaker hit 2026-03-30 |
| NYSE | 2025–26 | 97 | 73% | −$23.52 | 0.68 | 10.0% | breaker hit 2025-04-28 |

**Read:** Asian is the only set positive in both windows (a small edge, 79% wins, 7–12% DD). London made money in 2026 but blew the breaker within 3 weeks the year before. NYSE hit the breaker in both. **Recommendation: Asian only, or Asian + London if Adam accepts that London's 2025 failure mode could recur. Drop NYSE.** The breaker shutting the EA off permanently at −10% (it needs a manual restart) is the real protection here.

**Asian set, like-for-like with the EURUSD no-grid test (2026-09-27, Adam: "Yea"):** every tick plus 2024–25, rebuilt from the final HQ file (`iMaxCapital` 105000, confirmed).

| Window | Model | Trades | Win % | Net | PF | Max equity DD | Last trade |
|---|---|---|---|---|---|---|---|
| 2026 (6.5 mo) | 1-min OHLC | 312 | 79% | +$24.10 | 1.21 | 7.6% | 2026-09-24 (ran to the end) |
| 2026 | every tick | 317 | 74% | +$28.70 | 1.26 | 7.3% | 2026-09-24 (ran to the end) |
| 2025–26 | 1-min OHLC | 450 | 79% | +$61.54 | 1.38 | 12.5% | **2025-12-17: 10% breaker, dead ~2.5 months** |
| 2025–26 | every tick | 479 | 75% | +$75.84 | 1.48 | 10.1% | **2025-12-22: 10% breaker** |
| 2024–25 | 1-min OHLC | 81 | 68% | **−$36.42** | 0.44 | 10.5% | **2024-04-25: breaker after 6 weeks, dead 10 months** |
| 2024–25 | every tick | 84 | 65% | **−$34.35** | 0.45 | 10.0% | **2024-04-25: breaker** |

**Correction to the earlier read:** the 2025–26 "+$62" profit was banked before the grid dragged it into the 10% breaker in December. **The breaker tripped in 2 of 3 years**; live, that means a stopped EA until someone restarts it, and restarting just re-arms the same drawdown. **The Asian grid set fails the comparison. The EURUSD no-grid set (positive in all 6 runs, no breaker trips) is the only one of today's sets worth considering.**

**Not tested:** all sets on one account at once (the tester runs one set per test, so combined DD could exceed any single run), every-tick modelling, and whether the news filter works in the tester (`iNewsHigh=false` was only tried while `iMaxCapital=400` was blocking everything).

## EURUSD M5 NYSE No-Grid set (2026-09-27)

Adam supplied `EURUSD_M5_NYSE_NO_GRID.set` (another trader's, saved 2026-03-21, pre-v1.13 format). It already fits a $400 account: **`iLotsMode=0` static 0.01 lots, grid off, real stop (`iSLMode=2`, SL 2.2 / TP 0.75), 1 trade per day, a 55-minute NYSE range with a 10-minute entry window, EntryMode 2 (retest 50%), advanced risk off.** The only change is `User`. File: `C:\Users\aland\HQ\TWP EURUSD NYSE No Grid\EURUSD M5 NYSE no grid (Adam).set`, with the original in `original\`. Its old key `iDstRegion` still loads as `DstRegion=1` (checked in the input dump).

Same method as the GBPUSD runs ($400, 1:100, 1-minute OHLC, `iGMTShift` 3 / 0):

| Window | Trades | Win % | Net | PF | Max equity DD | Avg win / loss |
|---|---|---|---|---|---|---|
| Mar 9 – Sep 26 2026 | 49 | 61% | **+$18.62** | 1.28 | 7.0% ($29) | $2.83 / −$3.46 |
| Mar 10 2025 – Mar 6 2026 | 95 | 63% | **+$74.40** | 1.45 | 7.4% ($36) | $4.07 / −$4.71 |

**Deeper test (Adam: "Test it I mean", not live):** every-tick mode (ticks generated from M1, not real ticks; this broker only keeps a few weeks of real ticks) plus a third year. The 2024–25 offset of 0 was proven from 135 Fridays of EURUSD bars (see [[Build TWP Set Files]]).

| Window | Model | Trades | Win % | Net | PF | Max equity DD | Worst losing streak |
|---|---|---|---|---|---|---|---|
| 2026 (6.5 mo) | 1-min OHLC | 49 | 61% | +$18.62 | 1.28 | 7.0% | 3 (−$21.90) |
| 2026 | every tick | 49 | 63% | +$16.67 | 1.24 | 7.9% | 3 (−$21.95) |
| 2025–26 | 1-min OHLC | 95 | 63% | +$74.40 | 1.45 | 7.4% | 4 (−$17.40) |
| 2025–26 | every tick | 93 | 68% | +$108.36 | 1.73 | 7.3% | 4 (−$17.52) |
| 2024–25 | 1-min OHLC | 91 | 62% | +$12.82 | 1.08 | 11.3% | 8 (−$38.42) |
| 2024–25 | every tick | 94 | 64% | +$30.93 | 1.19 | 9.3% | 5 (−$24.45) |

**Positive in all 6 runs across 2.5 years:** every-tick total about +$156 on $400 (~15%/yr). But it's uneven: 2025–26 carries most of it, and 2024–25 was thin (PF 1.08–1.19, DD up to 11%, a streak of 8 losses). Costs are a non-issue: EURUSD history spread is 0–2 points and commission is $0. **Verdict: the most defensible set of the day. A modest, real-looking edge with capped risk, not a money machine.** It's low frequency (~2 trades a week).

**Trailing stop + 0.25 lots (2026-09-27, Adam: "Run a trailing stop on the eurusd no grid run a .25 lot size").** Every tick, $400, same 3 windows. Trailing semantics are from the vendor manual (see [[Build TWP Set Files]]). This set's TP is 0.75× the SL, so trailing can only lock in partial gains; it can never let a trade run past TP.

| Variant | 2024–25 | 2025–26 | 2026 | 2.5-yr net | Worst equity DD |
|---|---|---|---|---|---|
| **Baseline 0.01, no trail** | +$30.93 PF 1.19 | +$108.36 PF 1.73 | +$16.67 PF 1.24 | **+$155.96** | 9.3% |
| 0.01, trail 50%/50% of TP | +$12.09 PF 1.10 | +$30.46 PF 1.24 | +$17.36 PF 1.39 | +$59.91 | 9.7% |
| 0.01, trail 25%/50% of TP | +$2.91 PF 1.03 | −$11.29 PF 0.91 | −$24.34 PF 0.53 | −$32.72 | 8.9% |
| 0.01, HiLo(20) trail | −$13.66 PF 0.66 | −$11.25 PF 0.72 | −$20.95 PF 0.06 | −$45.86 | 5.3% |
| **0.25 lots, no trail** | +$768 but **85.8% DD** | +$2,703, 34.9% DD | **−$264, 80% DD, stopped trading after 4 trades (2026-03-26)** | — | **85.8%** |
| 0.25 lots, trail 50/50 | −$188, 75.9% DD, stopped 2024-09-18 | −$254, stopped after 8 trades | −$127, stopped after 4 trades | — | 75.9% |

**Verdict:** trailing hurts in every form. The 50/50 variant keeps it positive but cuts profit by ~60%, and the tighter ones turn it into a loser. **0.25 lots is 25× the size on the same $400:** an average loss becomes ~$86 (about 21% of the account), and 0.25 EURUSD needs ~$290 of margin at 1:100, so two losses leave too little margin to open the next trade. The 2025–26 "+$2,703" is a lucky opening sequence, not repeatable; the other two starts blew the account up. **At the same risk as the tested 0.01 on $400, 0.25 lots needs about $10,000.** To grow with the account instead, use `iLotsMode=2` (1 lot per X balance) with `iLots=40000` = 0.01 per $400 (compounds).

**Compounding tested (Adam: "Yea"):** `iLotsMode=2, iLots=40000`, every tick, $400. Results are **identical to static 0.01 in every window** (2026 +$16.67, 2025–26 +$108.36, 2024–25 +$30.93), and a continuous 2-year run (2024-03-11 → 2026-03-06) made **+$129.73, PF 1.41, 187 trades, DD 9.3%**, every trade at 0.01. Balance/40,000 only rounds up to 0.02 once the account reaches $800, which this edge doesn't get to within the tested history. **It's harmless and self-scaling, but it won't speed anything up at this balance.** Saved as `HQ\TWP EURUSD NYSE No Grid\EURUSD M5 NYSE no grid compounding (Adam).set` (only `iLotsMode`/`iLots` differ from the static file, verified by diff).

## Job
[[Build TWP Set Files]] — the actual `.set` file format (verified by reading these files directly) and a parameter glossary, for any future lot-sizing/config work on these files.

## Related reference
[[TWP ORB EA Reference]] — config/trade-history screenshots from two *other* TWP accounts (108.181.193.243 and D3101:81322), neither of which is the broken 8996721 login above. Different lot sizing (0.35 static) and a possibly-contradictory grid setup — don't confuse it with this note's validated 0.60-lot/grid-on config when sizing the $800 account.
