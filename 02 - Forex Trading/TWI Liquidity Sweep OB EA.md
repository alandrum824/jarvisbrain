---
status: active
project: forex-trading
type: reference
---
# TWI Liquidity Sweep OB EA

MQL5 EA built 2026-09-22 from Adam's full written spec: **liquidity sweep → break of structure → order block retest**, for XAUUSD on M1. Deliberately a **separate strategy** from [[TWI Liquidity Sweep BOS]] so the two can be compared; neither shares code with the other.

## Source location
- Vault master copy: `02 - Forex Trading/TWI Liquidity Sweep OB EA.mq5`
- Deployed **(not attached)**: `MQL5/Experts/Advisors/TWILiquiditySweepOBEA.mq5` on the live AAAFx/RisenAdam terminal
- **Compiled clean, 0 errors / 0 warnings**, both before and after the look-ahead audit fix and the R-accounting fix (below). `.ex5` current build.

## ⚠️ PRELIMINARY SYNTHETIC-TICK RESEARCH ONLY — 2026-01-01 to 2026-08-31 run (2026-09-22)

**Reclassified 2026-09-22, on Adam's explicit instruction. NOT A VALID REAL-TICK BASELINE. Do not use to choose parameters, judge the strategy, or optimize anything.**

A 191-trade run was executed over Jan 1 – Aug 31 2026 requesting `Model=4` ("Every tick based on real ticks"). It was initially and **incorrectly** reported as fully real-tick. The tester log's own disclosure line was missed at first read:
```
XAUUSD: ticks data begins from 2026.09.11 00:00
```
**This broker's real XAUUSD tick history only goes back to ~2026-09-11** — about 11 days before "today" in this session (2026-09-22). M1 *bar* (OHLC) data goes back to 2025-01-01, a completely different and much lower-fidelity thing. For a requested range outside real-tick coverage, MT5's every-tick-based-on-real-ticks model does not fail or warn — it **silently generates synthetic ticks from the M1/M5/H1 bars** for the missing portion. That is what happened here: essentially the entire Jan–Aug window ran on synthetic, bar-derived ticks, not genuine ones, despite the correct model being requested.

**Full run log preserved:** `02 - Forex Trading/TWI Liquidity Sweep OB EA - SYNTHETIC Run Log (2026-09-22).log` (231,152 lines, the complete tester log for this run, input dump through final funnel). Kept for later comparison against a genuine real-tick sample — **never for optimization or parameter judgment.**

**Preserved for reference only (SYNTHETIC / BAR-DERIVED TICKS):**
- 191 trades entered, 52 wins / 139 losses, win rate 27.23%
- Final balance $8,284.73 on $10,000 (net **-$1,715.27**), profit factor 0.70, max consecutive losses 14
- Full funnel: 31,684 swing points → 54,661 setups/sweeps → 16,845 confirmed reclaims → 1,531 confirmed BOS → 1,277 valid OBs → 892 retests → 191 entries
- This run is also where the R-multiple accounting bug (below) was caught — its R-based numbers (avg R, total R, BUY/SELL R, session R, bucket R) were additionally corrupted by that bug on top of being synthetic-tick data, so they're not even reproduced here.

**Intrabar dependency audit (code review, no EA changes, 2026-09-22):** every setup-detection rule (sweep, reclaim, BOS, OB identification, OB-touch decision, rejection confirmation) reads only closed-bar OHLC (`shift ≥ 1`) — **CLOSED-BAR SAFE**, and since MT5's synthetic-tick generator reproduces real M1 OHLC exactly and only synthesizes the intrabar path, the funnel shape from the synthetic run is probably a reasonably honest signal-frequency picture. What's genuinely corrupted: **entry fill price** (MIXED — go/no-go is bar-safe, but the modeled fill approximates the new bar's open rather than real intrabar microstructure) and **SL/TP sequencing** (INTRABAR ORDER DEPENDENT — on any bar wide enough to touch both the SL and a 2R TP zone, MT5's synthetic path assumption can flip a win to a loss or vice versa; this is delegated entirely to the tester engine, not this EA's own logic). Breakeven/trail would also be INTRABAR ORDER DEPENDENT if enabled — currently OFF by default in V1, so not exercised, but this is why H2 needs real ticks before it means anything.

**Process fix banked from this incident:** three back-to-back tester runs reused the identical `Report=` filename with `ReplaceReport=1`, and an interrupted run overwrote the completed run's `.htm` report with a blank/zeroed one before it could be read. Separately, reusing the same date range across repeated launches corrupted the local tick cache (`bases/<server>/ticks/XAUUSD/202609.tkc` shrank from 216MB to 37MB mid-session, then every subsequent run failed with "no history data, stop testing" until the corrupted file was deleted). **Going forward: every tester run gets a unique `Report=` filename encoding EA + symbol + model + date range + a run timestamp, never reused across runs. `ReplaceReport=1` only replaces that run's own retry, never a different logical run.** If tick downloads start failing with "no history data" after a prior success, suspect a corrupted local `.tkc` cache first — delete it and let the next run re-download clean, per [[MBT (MT5 Backtest Toolkit)]]'s existing gotcha list (adding this one).

## How this differs from [[TWI Liquidity Sweep BOS]]
Same opening sequence, different entry object and a much heavier operational layer.

| | TWI Liquidity Sweep BOS | **This EA** |
|---|---|---|
| Entry object | fib / FVG / OB of the BOS leg | **order block only**, three zone definitions |
| Timeframe | symbol-agnostic, M15 default | **XAUUSD M1 specifically** |
| Direction handling | one setup at a time | **two independent state machines**, long and short run concurrently |
| Sessions / days | none | full two-session + weekday filter |
| Daily risk governor | none | trades/day, losses/day, daily loss %, daily target |
| Visuals | 4 debug lines | full labelled setup drawing for Strategy Tester review |
| Stats | funnel counters | funnel + win rate + avg R + PF + max consecutive losses + BUY/SELL/session splits |

## The nine ambiguous rules and how each was pinned down

Every one of these was a place the spec could have been implemented with hindsight baked in.

1. **"a valid recent swing low" for BOS** — frozen at sweep-confirmation time as the most recent *confirmed* swing on the opposite side that still sits beyond current price. Stored in the setup and **never re-selected**. This is the single most important no-repaint rule in the file, and it is now **self-auditing**: every swing carries both the bar it printed on and the bar it became *knowable* on (`confirmedTime`, set when `SwingBarsRight` bars have closed after it). `FindBOSReference` rejects any swing whose `confirmedTime` is later than the current bar — a guard that cannot fire by construction, which is exactly why asserting it turns the no-hindsight claim into something verifiable instead of something to take on trust. The frozen reference is printed the instant it is chosen, with both timestamps and the sweep bar time, so the Strategy Tester log can be read back line by line to confirm no level was ever picked with hindsight.
2. **"last bullish candle before the displacement responsible for the BOS"** — scan backwards from the BOS candle toward the sweep bar, first opposing candle wins, bounded by `MaxOBSearchBars`. Fully deterministic, closed bars only.
3. **"valid bullish candle cluster"** — `UseOBCluster`, **default OFF**. [[TWI BOS Trap Entry]] measured cluster zones at +0.120R against +0.267R for single-candle zones over seven datasets. The option exists; the default follows the evidence.
4. **"equal highs count as liquidity"** — merged at swing-confirmation time into one level priced at the cluster extreme (where stops actually rest), carrying a touch count. Once a level is used by a setup it is **locked** and can never be merged into again, so a level's price can never move retroactively.
5. **"the sweep cannot simply be a breakout"** — two mechanical tests: a close back inside within `MaxSweepConfirmationBars`, plus an optional `MaxSweepPoints` cap that retires the level as a genuine break. Failing either retires the level so it is not retried.
6. **"closes decisively above the sweep high"** — `close > sweepExtreme + InvalidationBufferPoints`. A wick never invalidates, mirroring the rule that a wick never retires a liquidity level.
7. **`TP_STRUCTURE_LOW`** — implemented as the displacement extreme (lowest low between the BOS bar and entry), tracked forward bar by bar. Not a re-derived swing, so it cannot shift.
8. **HTF structure bias** — confirmed HTF pivots only, read from shift ≥ 1 with right-side bars closed. **Mixed structure returns "no clean bias" and blocks the trade** rather than guessing a direction.
9. **MT5 news calendar** — **deliberately not built.** `IsHighImpactNewsWindow()` is a clearly marked stub that always returns false, and `OnInit` prints a warning if `UseNewsFilter` is switched on. Calendar functions return no data inside the Strategy Tester on most builds; wiring them would make backtests behave differently from live. Adam's spec explicitly asked for a marked interface instead of something unstable.

## Sweep depth: measured in V1, never filtered on (Adam's call, 2026-09-22)
The original spec asked for `MinSweepPoints`. It was first implemented with a low default, then **Adam changed it to disabled outright** — V1 collects the sweep-depth distribution rather than filtering on an unproven threshold. This is the correct call and it matches what [[TWI SR Sweep Reclaim]] v3.00 already established the hard way: **6 of 10 otherwise-valid setups penetrated the level by exactly 0.00**, and a 0.05-ATR floor was silently deleting the majority of them.

**As shipped:**
- `UseMinSweepDepthFilter = false`, `MinSweepPoints = 0`. The threshold code exists but is bypassed entirely.
- A pure touch (`penetration == 0`) is deliberately **allowed** to arm a setup. Only `pen < 0` (price never reached the level) is rejected.
- `MaxSweepPoints` is kept and still functional — it protects against treating a genuine breakout as a sweep, which is a different question from minimum depth.
- Depth is measured at detection **and re-measured at sweep confirmation**, since the extreme can extend while waiting for the close back inside. The confirmed value is the one recorded.

**Depth buckets** (`0 / 1-10 / 11-25 / 26-50 / 51-100 / 100+` points) track setups, trades, wins, win rate, total R and average R separately, printed as a table in the end-of-test summary. This is the data that decides whether a `MinSweepPoints` threshold is ever justified. If the filter is switched on, the summary **labels the buckets as CENSORED** and `OnInit` prints a warning, so a filtered run can never be mistaken for a measurement of the real distribution.

The summary also carries the honest caveat that a bucket under ~20 trades is not evidence.

## Look-ahead audit (step 9, performed before the EA was signed off)
Checked every price read in the file:
- `ScanForNewSwing` evaluates shift `1 + SwingBarsRight`; the newest bar it inspects is shift 1. Never bar 0.
- All setup-stage logic reads shift 1 and 2 only.
- `CurrentATR()` uses `CopyBuffer(..., 1, 1)` — last closed bar.
- `HTFStructureBullish` walks from shift `1 + BiasSwingBars`; minimum shift inspected is 1.
- The swing registry only ever contains pivots already confirmed at the moment of any query, so filtering by pivot *bar time* cannot surface a swing that was not yet knowable.
- Trade management runs every tick but reads only live bid/ask and the open position — no bar data, so it cannot repaint.

**One real defect was found and fixed by this audit**, not by the compiler: the rejection-confirmation stage originally required a bar *after* the tapping bar, which silently discarded every setup that tapped the OB and rejected inside the same candle — common on M1 gold. The confirmation test was extracted into `RejectionConfirmed()` and is now evaluated on the tapping bar as well. Both paths read closed-bar data only, so no look-ahead was introduced.

## Status (2026-09-23) — STRATEGY CODE FROZEN AGAIN (Adam)

| Milestone | State |
|---|---|
| V1 execution validated (real ticks) | ✅ Micro Validation B |
| Risk sizing validated | ✅ 0.45–0.50%/trade |
| R accounting validated | ✅ hand-checked, R_INVALID 0 |
| AAAFx spread compatibility | ✅ MaxSpreadPoints 55 promoted |
| Long-sample edge validation | ⏳ needs months of real XAUUSD ticks |

**Frozen:** no strategy or H1–H8 changes. **The only permitted housekeeping (Adam, 2026-09-23), both reporting-only and never touching execution:** (1) session split filed by ENTRY time instead of close time (defect #3); (2) reports state explicitly that the tester currently assumes $0 commission. **Both DONE 2026-09-23 ~1:47 AM (Adam approved the exact edits):**
- #1: new `Setup.entrySession` field, reset in `ResetSetup`, set with `CurrentSession()` at the single trade-open point (next to `TRADE_ACTIVE`), and read by `RecordClosedTrade` instead of `CurrentSession()`. Summary lines are relabeled "(by entry time)". Session eligibility and trading logic are untouched.
- #2: `st_sumCommission` / `st_sumSwap` are added inside `RecordClosedTrade` from the same per-position deal aggregation R RESULT uses. `RecordClosedTrade` runs exactly once per position (`ResetSetup` clears the ticket right after), so partial-close deals are never double-counted. The summary prints the totals plus the $0-commission NOTE.
- The diff against the pre-edit backup (`tester_configs/V1_spread55_validated_backup_20260923/`: source, `.ex5`, `.set`) is exactly those lines. Compiled 0/0 on build 6116 (no terminal update). Vault = deployed (md5 `4e569632…`). The `.set` is unchanged (no input changed).
- **Determinism check PASSED:** the exact Run B config was re-run on the cached real ticks (report `determinismB_housekeeping_OBEA_XAUUSD_M1_realticks_20260911-20260922_20260923_0148`). **All 11,5xx simulated-time log lines are identical to Run B**: every deal, position/deal ID, entry/exit timestamp, price, SL/TP, lots, fill, RISK CHECK, R BASE, and R RESULT, and the whole funnel. The only differences are the expected summary lines: **S1 3 / S2 6 / Outside 0** (was 3/5/1) and **commission $0.00 / swap $0.00**. Net $155.04, PF 1.62, 9 trades, max DD $199.17: identical. Log archived: `TWI Liquidity Sweep OB EA - REAL-TICK Determinism Check (housekeeping) Log (2026-09-23).log`.

Defects #1 (OB-invalidated counter label) and #2 (merged-pool knowable timestamp) stay reported and unfixed.

**TRACK 0 — live AAAFx commission VERIFIED 2026-09-23 ~1:57 AM (read-only).** A script (`TWIDealAudit.mq5`, in this folder: it only reads history, then calls TerminalClose) dumped the whole deal history of account 8996721 (AAAFxGlobal-5 Real). Before launch it was confirmed that no chart on this terminal has an EA attached. Result: **1,973 deals across all symbols, 0 with non-zero commission, 0 with non-zero fee.** XAUUSD: 696 deals = **348 completed positions (2026-04-13 → 2026-09-23), commission $0 on opening AND closing deals, fee $0.** **AAAFx is spread-only on this account.** The cost of trading gold is the ~52-point spread, which the real-tick tests already include. Swap is the only non-price cost: 6 XAU closing deals carried swap (−$2.41 per 0.03-lot overnight position, −$14.46 total). V1 already includes swap in NetPnL because swap posts on the closing deal. Sample positions: 6579591, 6579623, 6594272, 8103402, 8112221, 8196723 (all $0 cost); 6947064 and 6948478 (−$2.41 swap each); 7541660 and 7541829 (0.14 lots, $0 cost). **So the $0-commission tester assumption matches live AAAFx, and defect #4 stays banked** (harmless on this account; it would matter on any commission account). Side note for the same fix: V1's comment says MT5 has no separate fee field, but `DEAL_FEE` does exist (also $0 here).

**Defect #4 found while doing this (report only, NOT fixed; it would change R, which the freeze forbids):** the NetPnL aggregation sums only `DEAL_ENTRY_OUT` deals. If a broker charges commission on the ENTRY deal (common on MT5 commission accounts), that cost is left out of NetPnL and Final R. It's moot while commission is $0, but it has to be resolved together with the live-AAAFx commission check before any live/commission-bearing conclusions.

## Status (2026-09-22)
- **Compiled clean, deployed, NOT attached to any chart.**
- **No valid backtest yet. No performance claim of any kind is being made.** The one 191-trade run (Jan–Aug 2026) ran almost entirely on synthetic ticks and is reclassified as research only (see the 2026-09-22 daily note and the archived run log). Two accounting bugs (tick value 100x off, R-multiple math) were fixed before it counted. V1's goal is objective rules, correct execution, no repainting, good logging and clean data — not profit.
- **V1 default updated 2026-09-23: MaxSpreadPoints 55** (AAAFx broker-compatibility correction; see the PROMOTED section). Every other V1 rule is unchanged, and the V1 lock is still in force. Real-tick runs so far: Micro Baseline A (spread 50, 0 trades) and Micro Validation B (spread 55, 9 trades, execution validated). Next: a longer real-tick dataset.
- **UNBLOCKED 2026-09-23 ~1:14 AM:** the tick download worked again after about 5 hours of no requests (the 09-22 failures were the broker dropping the connection on tick requests; see [[MBT (MT5 Backtest Toolkit)]]). **Confirmed real XAUUSD tick coverage from the Tester log: 2026-09-11 → 2026-09-22** (37MB, about 8 trading days). Anything before 09-11 is synthetic. The micro-baseline ran 2026-09-23 and produced **0 trades**: the spread gate (50) is below the real in-session spread (51-53). See the section below. **Waiting on Adam's decision about the spread gate before any longer real-tick run.** A longer sample needs Adam's go on Dukascopy data (option C below).
- **Reminder before any run:** per [[MBT (MT5 Backtest Toolkit)]], read the input dump at the top of the tester log and confirm the values match intent — `MQL5\Profiles\Tester\TWILiquiditySweepOBEA.set` will silently override compiled defaults.

## REAL-TICK MICRO BASELINE A — DEFAULT GATE VALIDATION (2026-09-23 ~1:22 AM). Result: 0 trades. PRESERVED, do not discard.

**Adam's classification:** the run established that the strategy funnel operates on real ticks, but the default spread gate is incompatible with normal AAAFx XAUUSD conditions.

**Run:** V1 exactly as shipped, XAUUSD M1, every tick based on real ticks, 2026-09-11 00:00 → 2026-09-23 00:00 (tester's own from/to line), $10,000, RiskPercent 0.5. MT5 terminal and agent build **6116** (LiveUpdate tried to run automatically at launch, the same way the tick-audit run did; it didn't apply). Account leverage came out **1:100** (the config asked for 500, and the account caps it). Real ticks: **7,322,947 ticks, 11,040 M1 bars**. **Exact first real tick 2026.09.11 01:00:00, last 2026.09.22 23:59:58 server time** (measured by the spread audit below). The 11,040 M1 bars equal exactly 8 days × 1,380 minutes, so every day runs 01:00–24:00 server time. That's the broker's normal gold day, so **Sep 11 is a full standard day, not partial.** (A 09-23 draft guessed "~00:53"; that was wrong. Pre-01:00 pivots came from M1 bar history, not ticks.) Config: `tester_configs/microbaseline_OBEA_XAUUSD_M1_realticks_20260911-20260922_20260923_0120.ini` (+ `.htm`). Full tester log archived here: `TWI Liquidity Sweep OB EA - REAL-TICK Micro Baseline A Log (2026-09-23).log`.

**Preflight (all verified before launch):** the vault source and the terminal source are byte-identical (md5 `e368d02f…`). The cached `.set` matched the compiled defaults on all 93 inputs, enums checked against their definitions, so nothing was overriding V1. BE/partials/bias are OFF, TP_FIXED_RR 2.0, SL_SWEEP_EXTREME, and MaxSpreadPoints 50.

**Funnel (real 8 trading days vs synthetic 172 trading days, per day):**

| Stage | Real | /day | Synthetic /day | Conversion real | Conversion syn |
|---|---|---|---|---|---|
| Liquidity levels registered | 1,438 | 179.8 | 184.2 | | |
| Sweep attempts | 2,821 | 352.6 | 317.8 | | |
| Confirmed sweeps/reclaims | 754 | 94.3 | 97.9 | 26.7% | 30.8% |
| BOS confirmations | 58 | 7.3 | 8.9 | 7.7% | 9.1% |
| Valid OBs | 48 | 6.0 | 7.4 | 82.8% | 83.4% |
| OB retests | 33 | 4.1 | 5.2 | 68.8% | 69.9% |
| Entry confirmations (rejection) | 25 | 3.1 | 4.0 | 75.8% | 77.1% |
| **Trades entered** | **0** | **0** | 1.11 | **0%** | 27.8% |

**Why zero:** all 25 confirmed entries were stopped at the final gates. **15 were outside the session windows. The 10 that fired inside a session were ALL blocked by `MaxSpreadPoints=50`**: the real spread at those moments was 51 (×1), 52 (×6), and 53 (×3) points. The synthetic run's spread gate blocked **0** setups out of 688. The synthetic tick model uses a spread under 50, so it never tested this gate at all. It's the same trap as [[TWI TakeProfit SMC EA]]'s 25-point spread gate on gold.

**Consequences:** sizing, R accounting, fills, SL/TP handling, and the R BASE/R RESULT audit were **never exercised** (0 RISK CHECK lines, 0 positions). R_INVALID = 0 only because nothing traded. The setup-detection funnel is the part that did validate: its conversion rates match the synthetic run within about 1-4 points at every stage, which means the closed-bar logic behaves the same on real ticks. The synthetic and real windows don't overlap, so no individual setup can be compared across both.

**Diagnostic defects found (report only, NOT fixed, V1 lock):**
1. The `OB invalidated` counter reads 500 against only 48 valid OBs. It also counts pre-BOS "sweep extreme violated — the raid failed" resets (494 of them), so the label is wrong. Logic is unaffected.
2. The frozen-BOS-reference log line can show "printed at" LATER than "confirmed/knowable at" (e.g. printed 23:32, knowable 21:19). `AddOrMergeSwing` updates a merged equal-level pool's `time` (and possibly `price`) but not its `confirmedTime`. **Not real look-ahead:** merges only happen when the newer swing itself becomes confirmed (≤ the current bar). It does weaken the audit trail for merged pools.

### Real spread distribution (TWISpreadAudit, 2026-09-23, read-only tool, same real ticks as Run A)
Tool: `TWISpreadAudit.mq5` (in this folder; never trades). It records `SYMBOL_SPREAD`, exactly what V1's gate reads, on all 7,322,947 ticks. Only 4 ticks disagreed with round((ask−bid)/point). Full output: `TWI Spread Audit - XAUUSD real ticks 2026-09-11 to 09-22.txt`.

| Group (per tick) | n | min | median | mean | p75 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|---|---|---|---|
| All | 7,322,947 | 37 | 52 | 52.56 | 53 | 53 | 53 | 55 | ≥5000 (tool cap) |
| Session 1 (08–11) | 911,720 | 37 | 52 | 52.29 | 53 | 53 | 53 | 55 | 186 |
| Session 2 (13–17) | 1,640,161 | 37 | 52 | 52.37 | 53 | 53 | 53 | 54 | ≥5000 (tool cap) |
| Outside sessions | 4,771,066 | 37 | 52 | 52.68 | 53 | 53 | 53 | 56 | 1800 |

Per-minute weighting (last tick of each minute) gives the same picture: median 52, p95 53, p99 53. The sessions don't overlap as V1 defines them (the 11:00–13:00 gap), so there's no overlap bucket.

In-session ticks at 51–53 points: **about 96% (S1 96.1%, S2 96.0%); 52 alone is about 65%.** At or under 50 points (what V1's gate allowed): **only 2.6% (S1) / 2.8% (S2).** Cumulative: ≤53 = 98.7–98.8%, ≤55 = 99.2%, ≤60 = 99.4–99.5%. Above that it's a thin expansion tail.

**The 10 rejected in-session entries (51 ×1, 52 ×6, 53 ×3) were at completely normal spreads,** the three most common values, all at or below the p95 (53). None happened during unusual widening.

**Classification: `MaxSpreadPoints = 50` is a BROKER-COMPATIBILITY DEFECT in the V1 default, not a strategy-performance failure.** Proposed ceiling (from the unconditional distribution only, not from trade outcomes): pending Adam's approval before any change.

## REAL-TICK MICRO VALIDATION B — BROKER-COMPATIBLE SPREAD 55 (2026-09-23 ~1:35 AM). EXECUTION VALIDATED.

**Adam approved `MaxSpreadPoints = 55`** as the smallest broker-compatible ceiling from the unconditional spread distribution (about 99.2% of in-session ticks). **The only change from Run A.** It was passed through the ini's `[TesterInputs]` (all 77 inputs copied from the V1 `.set`; a diff showed exactly one line changed). The V1 `.set` was backed up first (`tester_configs/TWILiquiditySweepOBEA_V1defaults_backup_20260923_0134.set`) and its md5 was unchanged after the run, so 55 did NOT leak into the cache. The tester input dump confirmed MaxSpreadPoints=55 and RiskPercent=0.5. Build 6116, same 7,322,947 real ticks. Report `tester_configs/microvalidationB_spread55_OBEA_XAUUSD_M1_realticks_20260911-20260922_20260923_0134.htm`. Log archived: `TWI Liquidity Sweep OB EA - REAL-TICK Micro Validation B spread55 Log (2026-09-23).log`.

**Funnel B:** levels 1,432 → sweeps 2,816 → confirmed 741 → BOS 60 → valid OBs 49 → retests 33 → entry confirmations 25 → **trades 9**. Blocked: session 15, spread **0**, daily limits 1. (Counts differ from Run A by a handful because open trades and daily limits change later setup state. That's expected once trades exist.)

**Run A's 25 confirmations → Run B:** 9 traded (9 of the 10 that spread had blocked), 15 still blocked by session (the same timestamps), 1 blocked by daily limits (2026-09-18 16:02, after 2 losses that day; the 10th former spread block), **0 blocked by spread.** No new operational issue.

**Execution validation:** risk per trade 0.4495–0.4995% of equity (lots round down; all ≤ 0.5%, none near the 0.55% ceiling). R_INVALID 0 of 9. Every Final R = NetPnL / InitialRiskMoney checked by hand, and gross P&L = price difference × lots × 100 checked by hand for trades 1–5. Commission, swap, and fees were $0.00 on every trade in the tester; **whether the live AAAFx account charges commission is unverified.** No broker rejections of any kind (no requote, invalid stops, no money, etc.). Entries filled at the tick price. SL/TP fills: TPs at +3 to +7 pts better than the level, **one TP gap +134 pts** (trade 5, 2.24R), SLs 0–3 pts adverse, and **one SL slipped 17 pts** (trade 9, −1.02R, realized loss 0.5055% of equity).

**LOW SAMPLE SIZE — EXECUTION VALIDATION ONLY:** 9 trades, 4W/5L, 44.4%, net +$155.04, PF 1.62, total R +3.26, avg R +0.362, avg winner +2.07R, avg loser −1.00R, max DD $199.17 (1.92%), max consecutive losses 4. BUY 5 (2W, +1.23R), SELL 4 (2W, +2.02R). By entry time: Session 1 = 3, Session 2 = 6, outside = 0.

**Diagnostic defect #3 (report only):** the EA's session split files trades by **close** time, not entry. It reported S1 3 / S2 5 / Outside 1, where the "outside" trade is #3 (entered 15:42 in S2, TP hit 17:00:57). No trade entered outside a session.

**Run B is preserved unchanged** as the evidence for the compatibility correction below (its `.htm`/`.ini` md5s were checked after the promotion: `f11c3bca…` / `f7a64259…`).

### PROMOTED 2026-09-23 ~1:42 AM (Adam approved): `MaxSpreadPoints = 55` is now the permanent V1 default

**Why 55 (AAAFx XAUUSD real-tick audit, Sept 11–22):** normal spread is 51–53 points, median 52, p95 53, p99 about 54–55. 55 covers about 99.2% of in-session ticks and still rejects abnormal widening (spikes to 186 and ≥5000 points). The old default of 50 was a **broker-compatibility defect**: it passed only about 2.7% of in-session ticks. It was not a strategy-performance issue. The threshold came only from the unconditional spread distribution, never from trade outcomes.

**Exactly two changes, nothing else:**
1. Source line 202: `input int MaxSpreadPoints = 50;` → `= 55; // AAAFx XAUUSD broker-compatible; real-tick spread audit 2026-09-23`. Edited in the vault first, then deployed. A diff showed that as the only changed line.
2. Tester cache `MQL5\Profiles\Tester\TWILiquiditySweepOBEA.set`: `MaxSpreadPoints=50||50||1||500||N` → `55||50||1||500||N` (value only; UTF-16LE + CRLF preserved). A diff against the pre-change backup (`tester_configs/TWILiquiditySweepOBEA_V1defaults_backup_20260923_0134.set`) showed that as the only changed line.

**Verified:** compiled 0 errors / 0 warnings (build 6116). The vault and deployed source are byte-identical (md5 `484f4baa…`). A programmatic check of all 77 compiled defaults against the `.set` found **0 mismatches**, with MaxSpreadPoints 55 in both. No other input changed. [[TWI Liquidity Sweep BOS]] was not touched; it has no spread gate, so this defect doesn't apply to it. The strategy was not re-run (the configuration was verified statically).

## V1 LOCK + post-baseline research hypotheses (Adam, 2026-09-23) — applies to BOTH sweep EAs

**V1 LOCK (Adam, 2026-09-23, reaffirmed):** nothing below goes into this EA or [[TWI Liquidity Sweep BOS]] before there is an honest real-tick baseline. That means no trendline filter, no reversal-pattern requirement, no 3R target, no origin-of-move target, no breakeven logic, and no extra confluence of any kind. V1 defaults (2.0R fixed target, no BE/partials) stay exactly as shipped.

**Order of work (locked):** real-tick data validation → honest V1 baseline → analyze failure modes and MFE → then test **ONE hypothesis at a time**.

**The screenshots are reference examples only. They are NOT evidence of expectancy.**

### Hypothesis list — do NOT implement any of these yet

- **H1 — Exit distance.** Compare 2R / 2.5R / 3R / 3.5R.
- **H2 — Breakeven management.** Compare BE at +0.75R / +1R / +1.5R / no BE.
- **H3 — OB entry method.** Compare OB touch (`ENTRY_MARKET_TOUCH`) / OB midpoint (`ENTRY_OB_MIDPOINT`) / rejection confirmation (`ENTRY_REJECTION_CONFIRMATION`).
- **H4 — OB definition.** Compare a single opposing candle against a small candle cluster (`UseOBCluster`).
- **H5 — MFE analysis.** Measure how often trades reach +1R / +1.5R / +2R / +2.5R / +3R / +4R before reversal or stop. **Prerequisite:** the EA does not record MFE/MAE yet, so it needs that logging first. That's logging only, not a strategy change, and it still needs Adam's confirmation before the code is touched.
- **H6 — Trendline confluence.** Test whether requiring alignment with a valid descending trendline (shorts) or ascending trendline (longs) improves expectancy. **The trendline must be defined mechanically from confirmed swing points only. No hand-drawn hindsight.**
- **H7 — Reversal-pattern confluence.** Require a reversal pattern at the liquidity extreme before the MSS/BOS. Test each candidate **separately; don't combine them into one filter at first**: (a) double bottom / double top, (b) bullish / bearish engulfing, (c) rejection candle / pin bar.
- **H8 — Structural target.** Compare the nearest liquidity target against an origin-of-move / opposing structural high-low target. Especially relevant to the ~3R+ examples.

### Reference examples (not backtested, not evidence of expectancy)

The pattern Adam observed across published examples: narrow OB/mitigation-zone entries, the SL beyond local structural invalidation, published targets usually around 3R-3.6R, occasional BE/close-early instructions, and entries close to the OB.

- Example A — SELL, SL=4368.858, TP=4342.467, stated RR=3.16, implied entry≈4362.51
- Example B — SELL, SL=4355.51, TP=4341.60, stated RR=3.65, implied entry≈4352.52 (IMPFX(VIP) Telegram, IMPERIALFX1 chart, FOREXCOM:XAUUSD, 2026-09-21)
- Example C — SELL, XAUUSD M1, 2026-09-23 ~00:28 UTC, read off a phone screenshot so approximate: entry ≈4360.60 at the bottom of a marked bearish OB, SL ≈4364.47, TP ≈4348.44, RR ≈3.1, TP hit about 45 min later. Same IMPFX source. **Source caveat:** a 25-subscriber paid channel that posts only winners, so heavy selection bias.
- Example D — BUY, XAUUSD 5m, "Liquidity Gold" (Facebook, 2026-09-24): a double bottom at a key level (~4245.8 on their feed) after a BOS, target the equal highs (EQH ~4283), SL under the key level. **Checked against OANDA 5m bars:** bottoms 4244.27 (~13:30 UTC) and 4244.82 (~15:10 UTC), no break below ~4241; a spike to **4288.56 at ~16:15 UTC** hit the EQH target about an hour after the second bottom. **One winning post from a public channel: selection bias applies.** It supports H7(a) (double-bottom reversal) as a reference only.
- Example E — SELL idea, XAUUSD H1, "Hamada Fx" (Facebook reel dated 2026-08-19, shared 2026-09-25): an uptrend of BOS, BOS, BOS → CHoCH → BOS down → **supply zone 4394–4410** at the origin of the drop, projected retrace into supply then a drop to ~4310. **Checked against AAAFx M1 history (server time): FAILED.** Price first reached the zone on 2026-08-19 15:00 (that hour: high 4442.41) and **closed through it** (16:00 high 4466.21). Aug 19 ran 4323.89 → 4524.31, then gold kept rallying to 4697.00 by Aug 25. A stop above the zone was hit within 1–2 hours. **A losing published example, a useful counterweight to the winners-only posts.**
- Educational graphics (2026-09-23): "Forex School" liquidity sweep + BOS short (this is already [[TWI Liquidity Sweep BOS]]'s logic); "Flux Forex" retest + lower high + trendline confluence (→ H6); "FX PULSE" reversal entry: reversal pattern at the low → close above the "trend shift" lower high → pullback entry → target at the leg's origin (→ H7, H8).

## Longer real-tick data — options investigated 2026-09-22, PROPOSAL ONLY, nothing downloaded/imported

**A. Another local broker/server with deeper XAUUSD real-tick history:** checked. Only one MT5 terminal is installed on this machine (`C:\Program Files\AAAFx Global MT5 Terminal`, the same AAAFxGlobal-5 Real account used throughout this EA's work). RisenMOM (OANDA-Demo-1) exists in earlier vault history but lives on a separate machine/account (`C:\Users\Administrator`, where [[MBT (MT5 Backtest Toolkit)]] is installed) not reachable from here. **No local option A exists without installing new software or accessing a different machine — needs Adam's call.**

**B. Whether this broker exposes older real ticks on explicit request:** inconclusive — blocked by the live connectivity failure below before it could be tested cleanly. Working hypothesis, not yet confirmed: many retail MT5 brokers retain full tick-level history only for a rolling window (commonly 30-90 days), with only bar (OHLC) data surviving further back — consistent with real ticks beginning almost exactly at "now minus ~11 days" rather than at some older, meaningful calendar boundary. If connectivity recovers, worth one clean re-check, but don't expect a different answer.

**Tick-history download connectivity blocker (2026-09-22), unresolved:** after the one successful download (216MB, confirmed real ticks begin 2026-09-11), every subsequent `run_strategy_tester`-style headless launch requesting tick history — for XAUUSD **and** EURUSD, ruling out a symbol-specific cause — fails identically within 1-2 seconds: `preliminary downloading of history ticks started` → `...canceled` → `no history data, stop testing`. Basic network connectivity and DNS to the broker's domain both confirmed working (ping + nslookup). Tried and ruled out: deleting a suspected corrupted local `.tkc` cache, cooldowns of 30s/90s/5min between attempts, cross-symbol test. The failure is specific to MT5's tick-history download service for this account/session, not a general network outage, and not time-based (5 minutes made no difference). **RESOLVED 2026-09-23:** a wait did it. The root cause is in the terminal log: the broker dropped the connection about 80 ms after each tick-history request (likely throttling after heavy pulls). The 01:11 run downloaded cleanly.

**C. Import external bid/ask tick history into a custom symbol — proposed source, pending Adam's approval:**
- **Proposed source: Dukascopy Bank's free historical tick data** (dukascopy.com/swiss/english/marketwatch/historical-data/ or via the widely-used free "Dukascopy Tick Data downloader" tooling). The standard, most reputable free source in the retail algo-trading community for exactly this use case.
- **Available date range:** XAUUSD tick data back to roughly 2010-2013 depending on exact feed (well over a decade — more than enough to dwarf this broker's ~11-day window).
- **Bid/ask:** yes, both sides included natively.
- **Timezone:** UTC.
- **XAUUSD digits/point convention:** Dukascopy typically quotes gold at 3 decimal places (0.001 tick) via their own contract spec, which does **not** match AAAFx's 2-decimal (0.01 point, 100oz contract) convention — this is a real mapping step, not a straight drop-in.
- **Spread behavior:** Dukascopy's own historical spread reflects their liquidity, not AAAFx's. Using it means either accepting Dukascopy's spread/price action as a proxy, or importing only price and applying AAAFx's own typical spread synthetically.
- **Known limitations:** a different liquidity provider's price feed is not identical to AAAFx's real fills — useful for testing execution *logic* (sequencing, no-repaint, state machine correctness) over a much longer real-tick sample, but any P&L/expectancy conclusion would carry an extra "different broker's price action" caveat on top of everything else.
- **Mapping to AAAFx's contract spec:** would need a price-scale conversion (Dukascopy's decimal convention → AAAFx's 100oz/0.01-point convention) and import as a genuine MT5 custom symbol (via `Symbols.raw`/custom symbol tools or a `.hst`/tick-CSV import script) rather than overwriting the real XAUUSD symbol.

**Awaiting Adam's approval before touching any of this.**

## Related
- [[TWI Liquidity Sweep BOS]] — the sibling strategy this one is meant to be compared against
- [[TWI SR Sweep Reclaim]] — source of the minimum-sweep-depth finding
- [[TWI BOS Trap Entry]] — source of the cluster-zone and wick-tap findings
- [[MBT (MT5 Backtest Toolkit)]] — the tester `.set` cache trap
- [[Active Priorities]]
