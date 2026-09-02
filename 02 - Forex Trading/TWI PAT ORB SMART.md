---
status: active
project: forex-trading
type: reference
---
# TWI PAT ORB SMART

New MQL5 EA (`TWI_PatORB_Smart_v1.mq5`), built 2026-09-01 from Adam's own detailed spec — an upgrade of the "Trade With Pat" Opening Range Breakout, not a new strategy. Core untouched: first 15-minute candle of the session = Opening Range; BUY only on a close above Range High, SELL only on a close below Range Low; preferred entry is breakout + retest, not a chase. Everything else exists to filter out weak setups.

**Completely separate from [[TWI OB Hunter]]** — different file, different magic number (260901 vs 20260831), no shared logic. Adam explicitly confirmed this distinction while it was being built.

## Where it lives
- Vault master copy: `02 - Forex Trading/TWI_PatORB_Smart_v1.mq5`
- Deployed (not attached) to RisenAdam: `MQL5/Experts/Advisors/TWI_PatORB_Smart_v1.mq5`
- Compiled clean via MetaEditor64 CLI: **0 errors, 0 warnings** (~900 lines, first compile)

## What it does
Dual independent sessions (London + New York, plus an optional Custom session) — each gets its own Opening Range, bias, trade count, and failed-breakout state; they never share or contaminate each other. Broker GMT offset auto-detected from `TimeTradeServer() - TimeGMT()`, rechecked daily for DST.

Full pipeline per Adam's spec, all implemented for real (not stubs):
1. **Opening Range** — built from real M1 bars over the session's first 15 minutes, independent of chart timeframe. No trades while forming.
2. **Breakout confirmation** — requires a candle close beyond the range by a configurable ATR-based minimum distance (default 0.12 ATR), on the confirmation timeframe (default M5).
3. **Entry modes** — Immediate, Range-Edge Retest, Midpoint Retracement, and Smart Retest (default). Smart Retest tries the range edge first, then a real 3-candle FVG detected off the breakout impulse, then the midpoint as a late fallback — plus an immediate-fallback path if the breakout score is already STRONG (≥80) and price hasn't chased more than 0.6 ATR, so the EA isn't dead on a genuine trend day.
4. **Trend filter** — EMA20/50/200 stack on H1, with a "soft align" allowance (fast>med, price>slow) scored slightly lower than a full stack. Counter-trend trades are blocked unless explicitly allowed and scoring ≥85 with ADX≥25.
5. **EMA50 slope filter** — real slope-over-N-bars check, ATR-normalized.
6. **Chop/market-state engine** — combines ADX, ATR-vs-its-own-average, EMA separation + recent crosses, failed-breakout count, and a real 6-candle "flat structure" check into TRENDING/NEUTRAL/CHOP. Only TRENDING allows new entries.
7. **Range size filter** — rejects the session outright if the opening range is under 0.45 or over 2.20 ATR.
8. **Momentum score (0-100)** — body/range, close position, RSI distance from 50, a directional-movement proxy (see honest note below), displacement vs ATR, and breakout-still-holding follow-through.
9. **Breakout Quality Score (0-100)** — the real gate, weighted exactly per Adam's spec (trend 18, slope 12, ADX 12, momentum 18, candle quality 12, ATR regime 8, range quality 10, retest quality 10). Every block or approval prints a plain-English reason to the Experts log and the dashboard.
10. **Fake breakout protection** — a close back inside the range after confirmation registers a failed breakout, starts a real cooldown, and after 2 failures on *both* sides locks that session's direction for the rest of the day.
11. **One-direction rule** — locks to the direction of the first real trade; a flip requires a genuine bias-reset structure change (H1 EMA cross), capped at `InpMaxDirFlips` (1 by default).
12. **Late entry protection** — skips (and marks as a fresh failed breakout) if price has already run more than the ATR-based chase limit from the edge.
13. **Risk management** — equity-based position sizing from real tick value/size, daily loss % cap (blocks new trades only, doesn't touch open ones), max trades per session and per day. No martingale, no grid, no scale-in — hard-coded, not just a toggle.
14. **Stop loss** — picks the tighter of a swing-based and an edge-based candidate, clamped between a min and max ATR distance.
15. **Profit management** — partial close at 1R (only after a real continuation candle, not a spike tick), breakeven move gated the same way, then ATR trailing after 1.2R with an optional structure-trail (5-bar swing) after 1.5R.
16. **Session control** — London/New York/Custom, each independently toggleable.
17. **News filter** — off by default; when on, uses the real native MQL5 economic calendar API (`CalendarValueHistory`/`CalendarEventById`/`CalendarCountryById`), auto-disabled in the Strategy Tester.
18. **Dashboard** — on-chart `Comment()` block per active session (range levels, ATR-multiple, ADX, EMA stack, slope, bias, market state, trade counts, last decision) plus real drawn chart objects: range box (gray forming → teal valid → orange rejected-size), ORH/ORL/MID lines, FVG zone box, and buy/sell arrow+text markers on fills.
19. **Journal** — every decision prints a structured line (`time | symbol | session | side | score | mom | adx | state | mode | result`), with an optional CSV (`TWI_PatORB_Journal.csv` in `MQL5/Files/`) when `InpLogCSV` is on.

## Honest implementation notes — read before trusting a specific score
- The Momentum Score's "+DI vs -DI in breakout direction" sub-factor uses a 3-bar directional price-change-vs-ATR proxy, not the raw +DI/-DI buffers, since MQL5's `iADX` handle only exposes the combined ADX line by default in the buffer index used here. Directionally reasonable, not a literal +DI/-DI read.
- `InpRelaxedMode` and a handful of small `Get...()` accessor functions exist so the effective thresholds (min score, min momentum, ADX chop) can be loosened without touching risk rules — wired through, not yet exercised in any real test.
- `InpAllowScaleIn` exists as an input for interface completeness (matching the spec's field list) but scale-in is never implemented — there is no code path that would add to a losing or winning position beyond the single partial-close-then-trail sequence.

## Lot sizing (added 2026-09-01, mid-first-test)
`InpLotMode` now selects between three sizing modes: `LOT_RISK_PERCENT` (default — original equity-risk-%-off-SL-distance math), `LOT_FIXED` (same lot every trade, `InpFixedLot`), and `LOT_BALANCE_SCALED` (lots = current balance ÷ `InpBalancePerLot`, recalculated fresh each trade off whatever the balance is at that moment — a static formula, dynamic input, matching the convention seen in the vendor TWP ORB EA's `iLotsMode=2` elsewhere in this vault). Compiled clean after adding it (0 errors/0 warnings). Added and recompiled *while* the first real backtest was running — safe, since the running tester process already has its own loaded copy of the EA; only a future run picks up the change.

## Usability additions (2026-09-01, same session, mid-first-test)
Added after Adam asked for these directly, on top of everything above:
- **Days of Week** — `TradeMonday`...`TradeSunday` booleans (Sat/Sun off by default), gates new entries per session; open positions are always still managed regardless of the day.
- **Daily Profit lock** — `InpMaxDailyProfitPercent` (0 = off) stops new trades once today's profit hits that % of day-start balance, same mechanism as the existing daily loss cap, tracked as a separate flag so the dashboard says which one fired.
- **Funded Trader mode** (`InpFundedTraderMode`) — turns on two real prop-firm-style protections: `InpMaxOverallDrawdownPercent` (default 8%, measured from the highest equity watermark since the EA attached — sticky, does not reset daily, matching how real prop firms measure max DD) and `InpFlatBeforeWeekend` (closes every EA-opened position before a configurable Friday hour).
- **Live Account gate** (`InpLiveAccountConfirm`) — a real safety rail, not cosmetic: if the account is live (`ACCOUNT_TRADE_MODE_REAL`) and this is false, `OpenTrade()` refuses to place the order and logs why. Demo and Strategy Tester are never blocked by this. Has to be a deliberate, explicit true before the EA will touch real money.
- **Master switch** (`InpTradingEnabled`) — pause all new entries without touching any other input or removing the EA.
- **Panic button** — a real on-chart button ("PANIC: CLOSE + STOP") that closes every EA-opened position on this symbol and pauses new entries for the rest of the session in one click.
- **Trade alerts** (`InpAlertOnTrade`) — a terminal `Alert()` on every fill and on every block where the score was still STRONG (≥80), so a rejected high-quality setup doesn't just scroll past in the Journal unnoticed.
- **Lot sizing modes** — `InpLotMode` selects Risk % (original), Fixed, or Balance-Scaled (lots = current balance ÷ a dollar figure you set, recalculated fresh each trade).

All compiled clean (0 errors/0 warnings) each step. Added and recompiled while the first real backtest was already running in the tester — safe, since a running tester process has its own already-loaded copy of the EA; these changes apply to the next run.

## Dashboard rebuild (2026-09-01, same session)
Adam asked for a "cooler," easier-to-read panel after seeing the plain white `Comment()` text dashboard in a live screenshot. `Comment()` can't do per-line colors in MQL5, so the dashboard was rebuilt as real chart objects (`OBJ_RECTANGLE_LABEL` background + stacked `OBJ_LABEL` lines), purple/blue themed (deep purple-navy background, purple border, blue title) with red/green kept deliberately for pass-fail states only (approved/blocked, profit/loss, market state) — a beginner reads red/green instantly, so that signal wasn't sacrificed for the theme. Sits just below the panic button, auto-sizes to however many sessions are enabled, cleans up its own leftover lines each redraw. Compiled clean (0 errors/0 warnings).

## RETRACTED: first "backtest result" and the "session-gating bug" it led to (2026-09-01)
Everything originally written here under "First backtest result" and "Source-level debugging session" was **wrong — not about this EA at all.** Root cause: [[MBT (MT5 Backtest Toolkit)]] was called with a forward-slash expert path (`"Advisors/TWI_PatORB_Smart_v1"`); MT5's tester `.ini` format requires a backslash for subfolder paths, so the path silently failed to resolve and MT5 fell back to testing its own **stock `Examples\Moving Average\Moving Average.ex5`** instead — with a normal-looking successful MBT response and a real metrics-bearing report, no error anywhere.

Everything that followed was chasing a bug in Moving Average, not TWI PAT ORB SMART: the -$340.74/2,036-trades result, the "12 trades on day one," the GMT-offset investigation, the "155/156 days breach the trade cap" finding, the multi-hour full-file debugging session, even the temporary debug-`Print()` instrumentation added to this EA's source and then reverted. The instrumentation itself is what caught the mistake — the debug lines never appeared anywhere until the expert path was fixed to use a backslash, at which point they showed the EA's actual trade-window and trade-count gating working exactly as designed (confirmed via `mbt/Tester/logs/<Agent>/logs/*.log`, not the exported `.htm` report, which never carries `Print()` output). Full account of the MBT bug itself lives in [[MBT (MT5 Backtest Toolkit)]] — this note only tracks what it means for this EA.

**Net effect: the session-gating / one-direction-lock / trade-cap logic in this EA has NOT been shown to be buggy.** A short instrumented re-run (Dec 1-5, 2025) with the corrected backslash path showed the gates behaving correctly.

## Real first backtest result (2026-09-01, corrected path + dashboard disabled)
XAUUSD.sim, M5, every-tick, $400 deposit, full available history (2025-09-01 to 2026-08-28), default inputs except `InpShowDashboard`/`InpDrawZones` forced off (headless-only optimization, see [[MBT (MT5 Backtest Toolkit)]] — doesn't touch trading logic).

**Result: net loss, but plausible and real this time.** Net profit -$257.04, profit factor 0.53, expected payoff -$1.53/trade, Sharpe -5.0, recovery factor -0.97, max balance drawdown $262.06 / max equity drawdown $265.21, **168 total trades over the year** — roughly 0.65 trades/day, a believable count for a 2-session, heavily-filtered ORB system (unlike the earlier retracted "2,036 trades" figure, which was never this EA). Trade count and timing consistency with the verified gating logic (confirmed correct via debug instrumentation, see retraction above) make this the first genuinely trustworthy result for this EA.

**Reading it honestly: this is not yet a working edge.** Profit factor 0.53 and Sharpe -5.0 are both decisively negative — this isn't "needs a bit of tuning," it's a losing strategy as currently configured, at default inputs, on this one symbol. Before writing this off entirely: only one symbol tested, only default (not relaxed) mode, and the EA's own honest-implementation notes flag the momentum score's directional-movement proxy as an approximation, not a literal +DI/-DI read — worth revisiting before concluding the underlying breakout-quality concept itself is unsound.

## Why it's losing (2026-09-01, real diagnostic, not guesswork)
Parsed the actual report: joined each trade's approval score (carried in the order comment, `TWI-PORB <session> S<score>`) against its real P&L from the Deals table, for all 155 matched round-trip trades.

- **The quality/momentum score has ~zero predictive power.** Mean score of winners (73.0) vs. losers (71.9) — a 1-point gap, statistically noise. Win rate doesn't improve meaningfully even in the top score bucket (85-89 still only 33.3%). The Breakout Quality Score pipeline is not actually distinguishing good setups from bad ones on this symbol/period.
- **Session is the real, clean lever.** London: 36.4% win rate, -$54.74 total. **New York: 21.3% win rate, -$210.11 total** — NY alone accounts for ~82% of the whole year's loss, at barely half London's win rate.
- Direction is a smaller factor: buys 25.8% win rate (-$164.65), sells 31.0% (-$100.20) — both negative, not the main driver.
- Next real test: re-run with `UseNewYork=false` (London-only) via the same `set_file` override method, to see whether isolating the better session actually turns this positive rather than just smaller-negative.

## EURUSD real result (2026-09-01)
Same pipeline (correct backslash path, dashboard/drawing disabled via `.set` override), full year, $400 deposit. Took ~66 minutes real time to complete (major FX pairs carry far denser tick data than gold under `every_tick` — had to raise the direct-script timeout to 5400s after a first attempt hit a 60-minute cap at 86% done).

**Net -$93.43, profit factor 0.69, expected payoff -$0.29/trade, Sharpe -5.0, recovery factor -0.97, max drawdown $93.43/$96.62, 326 trades.** Still a loser, but notably less bad than XAUUSD: smaller relative loss (-23% vs -64% of deposit), profit factor closer to breakeven (0.69 vs 0.53), roughly double the trade count (more liquid pair, more genuine breakouts). GBPJPY test queued next.

## Grid / recovery feature added (2026-09-01, capped by design, untested)
Adam noticed the vendor "Pat" TWP ORB (the system this EA upgrades) appears to use an uncapped "recovery system" (grid/martingale) — plausibly why the vendor's own results look better than this EA's raw signal quality. Built a real but deliberately capped version rather than copying the vendor's approach outright, given [[Active Priorities]] already has a real prior incident: grid trading on the vendor TWP ORB EA confirmed to margin-call an account directly at anything beyond minimum lot size.

New inputs, all under a master `InpUseGrid` switch (**default `false`** — nothing changes unless explicitly turned on):
- `InpGridMaxAdds` (default 2) — hard cap on additional entries per trade, never unlimited.
- `InpGridSpacingATR` (default 0.5) — each add requires price to move this many ATR further adverse than the last fill.
- `InpGridMaxTotalLot` (default 0.05) — absolute ceiling on combined volume, an independent circuit breaker.
- **Flat lot sizing, not martingale** — every add uses the same lot size as the original entry, never multiplied.
- **Total $ risk is pinned, not compounding** — `RecalcGridStopLoss()` recomputes the stop after every add so the whole group's total dollar risk stays equal to the ORIGINAL single-trade risk (derived from that trade's own lot × SL distance, works across all three `InpLotMode` modes). The stop gets numerically tighter (in price terms) as volume grows; total risk does not grow with each add. This is the key difference from what margin-called the vendor EA — a real invalidation level always exists.
- Implementation relies on netting-account behavior (confirmed on both RisenAdam/AAAFxGlobal and RisenMOM/OANDA-Demo-1): additional same-direction market orders blend into the existing position server-side, so no separate multi-ticket tracking was needed — `g_active`'s single-position model still applies, just refreshed after each add.
- Compiled clean (0 errors/0 warnings), deployed to both terminals. **Not yet tested** — next step is a real backtest with `InpUseGrid=true` via the same `set_file` override pipeline, compared directly against the no-grid baseline (XAUUSD: -$257.04, PF 0.53, 168 trades) to see whether it actually helps or just delays/reshapes the same loss.

## Status
Compiled clean (dashboard/drawing restored to `true` defaults post-test), deployed to both RisenAdam and RisenMOM (RisenMOM's `.ex5` freshly recompiled; RisenAdam's `.mq5` source updated but not separately recompiled since it's not attached to any chart). **Not attached to any live chart.** One real, trustworthy backtest exists (above) — net losing at default settings on XAUUSD. Not validated on EURUSD/GBPJPY. Nowhere near a live-use conversation.

## CORRECTION: bare-bones rebuild superseded everything above (2026-09-01, later same day)
Everything above this point (the full-featured scoring/retest/chop-engine version, its dashboard, grid feature, and the "why it's losing" score-vs-outcome diagnostic) describes a version of this EA that **no longer exists in the file**. At some point after that diagnostic (found the Breakout Quality Score had ~zero correlation with outcome — 73.0 mean score for winners vs 71.9 for losers), the EA was rebuilt from scratch into a bare-bones textbook ORB: first-15-min range, close-beyond-range + small ATR buffer to enter, no retest wait, no FVG, no scoring, no trend/chop/ADX filters, no partials/trailing (single fixed-R target). This rebuild was never logged in a daily note or here — discovered only when reading the live source file for an unrelated task. Core structure (dual London/NY sessions, direction-lock, day-of-week gating, grid/recovery module, lot-sizing modes, panic button, live-account gate) survived the rebuild; the scoring/retest/dashboard/partial-exit machinery did not.

**No backtest exists yet for the bare-bones version.** The -$257.04/PF 0.53 XAUUSD result and the -$93.43 EURUSD result above were both against the old scored/retest version — they do NOT describe the current file and should not be used to judge it.

## Volume confirmation gate added (2026-09-01, same day, post-rebuild)
Real outside research (firecrawl web search, false-breakout literature) found: breaks under ~1.5-2x the recent average volume are far more likely liquidity sweeps than genuine expansion, and this is called the single most reliable real-time breakout tell across multiple sources. Cross-checked against this EA's own now-superseded diagnostic above — the score that had zero predictive power never included any volume component at all, so this is a genuinely new signal, not a re-weighting of an existing one. Also found: XAUUSD fakes out ~62% intraday vs EURUSD ~58% (matches the EA's own EURUSD result beating XAUUSD in relative terms), and London's ~35-40% share of daily FX volume vs New York's thinner flow structurally supports the earlier NY-session-is-the-problem finding (also from the now-superseded scored version, but the underlying session-liquidity mechanism still applies).

Added to `EvaluateBreakoutAndEnter()`: two new inputs `InpMinVolumeMult` (default 1.5, 0 = disabled) and `InpVolumeAvgBars` (default 20), a new `AvgVolumeExcludingBar1()` helper (average tick_volume over bars 2-21 on `InpConfirmTF`), and a hard gate right after direction is determined — blocks the trade and logs why if the breakout bar's tick_volume is under the multiple of the recent average. No scoring, no retest, no other logic touched. Compiled clean (0 errors/0 warnings) on RisenMOM; RisenAdam's `.mq5` source updated but not separately recompiled (not attached to any chart). **Not yet backtested.**

Also identified but not implemented: `InpConfirmTF` is already a runtime input (default M5) — testing M15 instead requires only a `.set` override at backtest time, no source change, since false-breakout rates drop meaningfully from M5 to M15 per the same research. A 2-bar real-bodied follow-through gate was considered and explicitly rejected — it would reintroduce a wait-state the bare-bones rebuild was deliberately built to remove.

## Next steps
- **Run the first real backtest of the bare-bones + volume-gate version** (XAUUSD baseline first, matching the old test conditions: $400 deposit, full year, every-tick) — nothing above this line is trustworthy for the current code.
- Compare `InpMinVolumeMult=1.5` (on) vs `0` (off) on the same period to isolate whether the gate actually helps.
- Test `InpConfirmTF=PERIOD_M15` via `.set` override against the M5 baseline, both with the volume gate on.
- Recompile RisenAdam's copy before ever testing/attaching there directly.
- Confirm the dashboard/objects still look right on a live chart — never visually verified even before the rebuild.

## Related
- [[TWI OB Hunter]] — a different EA built the same night; explicitly not related.
- [[Build TWP Set Files]] — general `.set`/EA-file conventions used elsewhere in this vault (not directly applicable here since this is a from-scratch build, not a vendor EA's input file).
