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

## Status (2026-09-22)
- **Compiled clean, deployed, NOT attached to any chart.**
- **Zero backtests. No performance claim of any kind is being made.** V1's goal is objective rules, correct execution, no repainting, good logging and clean data — not profit.
- Real next step is the first XAUUSD M1 backtest. Recommended initial settings and the specific things to examine are in the session log for 2026-09-22.
- **Reminder before any run:** per [[MBT (MT5 Backtest Toolkit)]], read the input dump at the top of the tester log and confirm the values match intent — `MQL5\Profiles\Tester\TWILiquiditySweepOBEA.set` will silently override compiled defaults.

## Research observations from published examples (2026-09-22) — hypotheses only, NOT applied to V1

Adam supplied real published trade examples from the strategy's source material, observing a recurring pattern: narrow OB/mitigation-zone entries, SL beyond local structural invalidation, published targets commonly ~3R-3.6R, sometimes an instruction to move to breakeven or close early after favorable movement, and entries sitting close to the OB rather than far after the move already ran.

**Two published examples (reference only, not backtested, not evidence of expectancy):**
- Example A — SELL, SL=4368.858, TP=4342.467, stated RR=3.16, implied entry≈4362.51
- Example B — SELL, SL=4355.51, TP=4341.60, stated RR=3.65, implied entry≈4352.52

**Explicitly NOT used to tune V1** — its defaults (2.0R fixed target, no breakeven/partials) stay as originally shipped and measured in the baseline. These are candidate follow-up experiments only, to run AFTER the baseline has real numbers behind it:

- **H1:** Compare 2R vs 2.5R vs 3R vs 3.5R fixed exits.
- **H2:** Test breakeven activation at +0.75R, +1R, and +1.5R.
- **H3:** Compare `ENTRY_MARKET_TOUCH`, `ENTRY_OB_MIDPOINT`, and `ENTRY_REJECTION_CONFIRMATION`.
- **H4:** Compare narrow single-candle OB against `UseOBCluster` cluster OB.
- **H5:** Analyze MFE to determine whether winners commonly reach 3R before reversing (**blocked** — this EA does not currently record MFE/MAE; see the Status section).

## Longer real-tick data — options investigated 2026-09-22, PROPOSAL ONLY, nothing downloaded/imported

**A. Another local broker/server with deeper XAUUSD real-tick history:** checked. Only one MT5 terminal is installed on this machine (`C:\Program Files\AAAFx Global MT5 Terminal`, the same AAAFxGlobal-5 Real account used throughout this EA's work). RisenMOM (OANDA-Demo-1) exists in earlier vault history but lives on a separate machine/account (`C:\Users\Administrator`, where [[MBT (MT5 Backtest Toolkit)]] is installed) not reachable from here. **No local option A exists without installing new software or accessing a different machine — needs Adam's call.**

**B. Whether this broker exposes older real ticks on explicit request:** inconclusive — blocked by the live connectivity failure below before it could be tested cleanly. Working hypothesis, not yet confirmed: many retail MT5 brokers retain full tick-level history only for a rolling window (commonly 30-90 days), with only bar (OHLC) data surviving further back — consistent with real ticks beginning almost exactly at "now minus ~11 days" rather than at some older, meaningful calendar boundary. If connectivity recovers, worth one clean re-check, but don't expect a different answer.

**Tick-history download connectivity blocker (2026-09-22), unresolved:** after the one successful download (216MB, confirmed real ticks begin 2026-09-11), every subsequent `run_strategy_tester`-style headless launch requesting tick history — for XAUUSD **and** EURUSD, ruling out a symbol-specific cause — fails identically within 1-2 seconds: `preliminary downloading of history ticks started` → `...canceled` → `no history data, stop testing`. Basic network connectivity and DNS to the broker's domain both confirmed working (ping + nslookup). Tried and ruled out: deleting a suspected corrupted local `.tkc` cache, cooldowns of 30s/90s/5min between attempts, cross-symbol test. The failure is specific to MT5's tick-history download service for this account/session, not a general network outage, and not time-based (5 minutes made no difference). **Not yet resolved — needs either a longer wait tried later, or Adam checking the AAAFx account/connection directly.**

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
