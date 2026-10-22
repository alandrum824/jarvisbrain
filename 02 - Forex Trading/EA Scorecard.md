---
status: active
project: forex-trading
type: reference
---
# EA Scorecard

The one place that says which of our EAs are any good and why. Built 2026-10-11 after Adam said "check all EA, find which ones are good and why, and let's build around that". Every EA note in this folder was read in full. Update this note whenever an EA gets a real test.

**The bar for "good":**
1. Positive across multiple years on our AAAFx data, with real costs.
2. The same result in a second engine: the MT5 tester and the Python replay agree.
3. Beats a random control: random zones, random times or coin-flip direction. Beating at least 95% of random runs counts as real.

## Passed
| EA | Evidence | Why it works |
|---|---|---|
| **[[TWI ORB Momentum]] v1.20, EURUSD, NY 09:30 only** | 2020–26 replay (`orb_momentum_longrun_research.py`): **405 trades, +32.2R, PF 1.21, 63% wins, 6 of 7 years positive.** 2020 and 2022 had never been seen before and are both positive. The one bad year is 2021 (−10.9R). Beats the coin-flip control **96%** of the time (coin median +8.9R). MT5 every-tick (2023–26) agrees with the replay within 1–2 trades per window. | Explained below this table. |
| **[[TWI Gold Asia Breakout]] (gold, 00–05 GMT range, OCO stops, 1R, flat 16:00 GMT)** | 2020–26 replay (`gold_breakout_research.py`): **1,607 trades, +74.2R, PF 1.12, 6 of 7 years**, beats the coin flip **100%**; shorts earn as much as longs. MT5 (1-min OHLC, 0.01): **1,600 trades, PF 1.33, 6 of 7 years, equity DD 2.6%**. Same losing year (2021) in both. **Our first gold pass.** Gold-only: EURUSD (PF 0.86), GBPUSD (0.96) and 10 more markets (FX crosses + indices, 0/10 pass) fail. Shadow forward test running since 2026-10-12. | Session-break momentum again (like ORB Momentum): Asia sets the range, London/NY breaks it. The stop is the whole range, so normal noise rarely reaches it and the 52-pt spread is small against it. Rules from Aurum Range Breakout ([[Gold EA Market Survey]]). |

**Why ORB Momentum works:**
- It trades a liquidity event (the NY cash open) in the direction price breaks.
- The stop is wide (2.2× the opening range) and the target is close (0.75× the stop). It wins about 63% of the time, and normal noise rarely reaches the stop.
- It runs on the cheapest market we have: EURUSD at 0–2 pts spread, $0 commission.

**Second pass (2026-10-11, MT5 tester):** **USDJPY London with 0.5% risk sizing is positive in 5 of 5 windows from 2022 to 2026** (+$1,513 on $10k, DD ≤ 3.6%). It needs ~$1,000+ to size properly. Details are in [[TWI ORB Momentum]]. EURUSD NY is also positive in its unseen 2022–23 MT5 window. **Gold failed** in MT5 on both sessions.

**Third leg (2026-10-11):** **US30 NY passed** the pre-registered new-legs scan (1 of 16 cells; +0.121R/tr, 5/5 years, beat the coin flip 100%). MT5 at $100k: 4/5 windows positive, +18.6R, ~+0.08R/tr. **Promoted.** All Tokyo cells, NAS100, SPX500, GER30, UK100, AUDUSD, USDCAD and AUDJPY failed. Details are in [[TWI ORB Momentum]].

## Leads: positive in replay, not built and confirmed yet
| Lead | Evidence | Caveat |
|---|---|---|
| ~~ORB Momentum rules on **USDJPY London 03:00**~~ **PROMOTED (risk-% sizing, MT5 5/5)** | 2020–26: 525 trades, +36.1R, PF 1.18, 6 of 7 years, beats the coin flip 100% | Found among 8 session × market cells tested together, so it needs its own confirmation (MT5 tester) before it counts |
| ~~ORB Momentum on **gold NY 09:30**~~ **FAILED in MT5 with risk sizing** | +15.9R, PF 1.11, beats the coin flip 94% | Only 4 of 7 years positive. Gold's stop size at 0.01 is too big for a ~$200 account |
| **Asia session demand + engulfing** ([[TWI ORB Demand Pullback]] research) | EURUSD and NAS100, positive in all 3 years tested (2024–26) | ~25–30 trades/yr per market, about 108 cells tested, no random control yet, never built as an EA |
| **[[TWI Gold Breakout]]: gold H4 20-bar breakout, longs only, EMA200, 2 ATR SL, 2R** (2026-10-12) | Replay: 195 trades, +74.7R, PF 1.71, 5/7 years, beats the coin flip 98% and random longs 96%. MT5: 188 trades, PF 1.50, +$1,683 at 0.01 | **MT5 shows only 4/7 years** (2020–22 lose). A trend-follower that needs a gold uptrend. Built, not attached |
| **Gold Asia breakout, FVG + H1 trend filter** ([[TWI Gold Asia Breakout]] v1.04, 2026-10-13) | 183 trades, +27.2R, **+0.149R/trade (7× unfiltered)**, PF 1.43, 5/7 years, coin 100%, **beats random trade-skipping 100%**; MTF (H1+H4) 66 trades, PF 1.51 | Few trades (~27/yr); MT5 confirmation pending |
| **Gold Three White Soldiers / Three Black Crows, H1** (`gold_soldiers_research.py`, 2026-10-13, from Adam's chart image; built into [[TWI Gold Price Action]]) | 3 strong same-colour H1 bars (each body ≥ 0.5 ATR, closing higher/lower, close in the top/bottom 30%) → next open, SL beyond the first bar ± 0.1 ATR. **1R: 194 tr, +17.4R, PF 1.23, 5/7, coin 100%**; 2R: 188 tr, +32.4R, PF 1.39, 6/7, coin 88% | 4 cells tested (M15 fails: PF 0.96–0.99). Independent of the Asia breakout (any hour, ~29/yr) → candidate third leg. **MT5 tester 2026-10-13 confirms: 196 tr, PF 1.22, 5/7. H&S M15 in the same EA: 827 tr, PF 1.17, 6/7 (better than the replay)** |
| **Gold Asia breakout + Retest Sniper add-on** ([[TWI Gold Asia Breakout]] v1.03, 2026-10-13) | Replay combined: 3,109 trades, +125R, PF 1.08, 5/7 years, coin 100%; the retest leg alone +51R, coin 96%, 4/7 | Combination chosen after the fact, legs correlated 0.88 → MT5 tester confirmation pending. FVG/OB sniper entries failed (stops too tight) |
| **STRIKE method on NAS100** (same note) | 491 trades, +50.9R, 5 of 5 years, 60% wins | Fails on gold. No random control yet, never built as an EA |

## Failed: don't run, don't build on
- **Zone-based entries:**
  - [[TWI OB Hunter]]: no edge 2020–26, and no better than random zones.
  - [[TWI Gold Zone Ladder]]: worse than random entries.
  - [[TWI OB FVG IDM]].
  - [[TWI SMC POI]]: ~breakeven at best.
  - [[Liquidity Sweep Demand Zone]] (@Prop-Firm-Trader diagram, gold 2020–26): all 8 variants fail. Best: 15m 2R, +8.1R over 127 trades, 4 of 7 years, beats the coin flip 66%. The "peak" target is almost never ≥1R.
  - **CHoCH → BOS → pullback entry** (`gold_choch_research.py`, 2026-10-12, from Adam's market-structure lesson screenshots): fractal-3 swings, trend → CHoCH → lower high → BOS → enter on the next pullback swing, SL beyond it, 2R, gold 2020–26, coin control. **M5: 1,411 tr, −193.9R, PF 0.80, 0/7 yrs, worse than the coin (20%). M15: 483 tr, −34.4R, PF 0.88, 1/7 yrs, beats the coin 66%.** Fails.
  - [[TWI ORB Demand Pullback]]: Pat's model, no edge in any variant. The same goes for Adam's gold 9:00 AM Pacific candle (−104R, worse than a coin flip) and Pat's strength entry (gold −168R, NAS100 −35R).
- **EMA/PSAR trend scalping on gold:** [[TWI Trend Scalper]] v1.01 (EMA 200 bias + 21/50 cross + PSAR + S/R bounce or break, measured-move TP). 2020–26 MT5: 3 of 7 years positive, −$250 over 1,139 trades at 0.01. The spread eats roughly what the signal makes. EURUSD untested. v1.02 pattern stop (Adam's "below the triangle"), breaks only: +$271 over 1,503 trades but still 3 of 7 years, carried by 2026 (+$321).
- **M5 pullback-in-trend scalping** ([[EMA Ribbon Trend Research]], `pullback_scalper_research.py`, 2026-10-12): H1 trend + M5 EMA21 dip-and-reject, gold/EURUSD/USDJPY 2020–26, coin control. 17/18 cells fail (gold −285 to −389R). The one nominal pass (USDJPY 1.5R longs, +0.008R/trade, PF 1.01) is what chance gives across 18 cells. The idea only pays on H1/H4.
- **Small-target gold scalps on the Asia-breakout signal** ([[TWI Gold Asia Breakout]], 2026-10-12): TP 0.5R / 0.3R / 0.5R + 2 h cap all fail (PF 0.96–1.01, 3/7 years), with win rates of 53–74%. Shrinking the target throws away the edge; keep 1R.
- **EURUSD web scalpers** (`eurusd_scalper_research.py`, 2026-10-12, Adam: "Look up eurusd scalper ea and build one"): the two classes on sale, pre-registered, 2020–26, coin control. **NIGHT** (M5 Bollinger fade 18:30–22:00 NY, TP 10 / SL 20 pips): 1,921 tr, −68.3R, PF 0.87, 2/7 yrs, beats coin 80%. **LONDON_EMA** (Pineify EMA 9/21 cross 03–07 NY, TP 15 / SL 10 pips): 2,612 tr, −351.4R, PF 0.75, 1/7 yrs, worse than coin (8%). Both fail. The EURUSD scalper that passes is [[TWI ORB Momentum]] (NY 09:30: 63% wins, median stop 35–63 pips by year ≈ $3.5–6.3 risk at 0.01).
- **Gold scalping-pattern mining** ([[Gold EA Market Survey]], `gold_pattern_mining.py`, 2026-10-12): 90 short-hold cells (open moves, hour drift, shock bars), discovery 2020–23 / holdout 2024–26, drift-adjusted, net of cost. **0 pass.** The 18:00 reopen "edge" is a reopen-quote artifact that is gone by 18:05.
- **GoldTrendPullback v1.00** (Adam's upload 2026-10-12, credits andamagodwin/forex XauScalper; M5 EMA 9/21/200 pullback + RSI 45–70 rising + ADX ≥ 25, SL 1.5 ATR, 1R; replay `gold_trend_pullback_research.py`): **as coded, 1,743 trades, −114R, PF 0.88, 0/7 years.** Bug: the RSI gate isn't mirrored for shorts (RSI rising 45–70 required), so only 3 shorts in 7 years. **With that fixed: 3,520 trades, −251R, PF 0.87, 1/7 years.** Beats the coin flip 76–90%; all variants fail. Second bug: `PositionSelect(_Symbol)` on a hedging account sees the first gold position, so a manual gold trade blinds it to its own (no time stop, no flatten, possible stacking).
- **Slingshots_EA_3.02** (Adam's Google Drive, source read; `slingshot_research.py`, 2026-10-12): fade the 04:15→08:30 server move, 30-pip SL, TP 1/2/3R. EURUSD −8R (PF 0.99), GBPUSD +37R (PF 1.06, 4/7 yrs, beats the coin 92%), USDJPY −52R. Fails. Inventory: [[Google Drive EA Library]].
- **GoldORBCore v1.00** (Adam's upload 2026-10-13; another AI's build of the "NANDR ORB Core" spec; replay `gold_orb_core_research.py`): 15-min opening ranges at 5 UTC session opens (22:00, 00:00, 07:00, 12:00, 13:00), breakout on an M15 close, gold 2020–26, 6,990 breakouts. **As coded** (wait for the retest, SL = entry − broken boundary, TP 2×): **−1,645R, PF 0.61, 0/7 years.** The retest entry sits on the boundary, so the stop is about one spread (49% of stops under $1; the rest hit the $3 legacy fallback). **Direct entry, SL at the opposite boundary, 1R:** −529R, PF 0.85, 0/7, **worse than the coin flip (0%)**. **Direct, SL at the midpoint, 1.5R:** −844R, PF 0.81, 0/7, coin 0%. 15-minute gold session breakouts reverse more often than they run. Only the 5-hour Asian range works ([[TWI Gold Asia Breakout]]).
- **AMD fake-out reversal and confirmation-candle retest on the gold Asia range** (`gold_amd_confirm_research.py`, 2026-10-13, from Adam's chart-lesson images): **AMD reversal** (the breakout closes back inside within 1 h → trade opposite, SL beyond the manipulation extreme, TP the far side): **1,112 tr, −178.8R, PF 0.79, 0/7 years, worse than the coin (8%)**. On gold, a breakout that dips back inside usually still continues. **Pin bar/wick confirmation at the retest:** +28.4R, PF 1.03, 3/7, coin 94%, weaker than the plain retest sniper (+50.9R).
- **Rising/Falling Three Methods on gold** (`gold_three_methods_research.py` strict, `gold_three_methods_loose.py`, 2026-10-13): strict textbook = 12 trades in 7 years on M15 (+6.6R, too rare) and none on H1; loose (2–4 small bars inside a ≥1 ATR bar, 2R): M5 −200.6R, M15 −11.0R, H1 −3.7R. Fails.
- **Chart-lesson batch 2 on gold, 2026-10-13 (all 2020-26, real spread +6 pt, coin control):**
  - **Head & shoulders** (`gold_hs_double_research.py`, neckline-close entry, SL beyond the right shoulder, measured-move TP clipped 1–4R): M15 959 tr, +84.4R, PF 1.15, **only 4/7 years** (coin 98%); H1 265 tr, +19.2R, PF 1.13, 4/7, coin 60%. Near miss, M15 H&S is a lead, not a pass.
  - **Double top/bottom** (same file): M15 −41.5R, H1 −5.1R. Fails.
  - **Entry types at the Asia-range retest** (`gold_entry_types_research.py`): limit at the zone +85.3R, PF 1.09, 4/7 (fill slightly optimistic, ignores the spread on buy limits); **engulfing confirmation −93.9R**; pullback-structure break −0.2R. The limit at the zone is the best of the three; confirmation candles cost money on gold.
  - **OB candle types** (`gold_ob_types_research.py`, impulse ≥1.5 ATR + FVG, limit at the OB edge, SL beyond the OB, 2R): the first run showed H1 'normal OB' passing (PF 1.23, 6/7) but the limit fills ignored the spread. Fixed (buy limits fill on the ask; coin enters at the same limit price) → **H1 normal OB 200 tr, +24.2R, PF 1.19, 6/7, coin only 80%. Fails**; every other type (pin, doji, engulfing, manipulation, all) fails. **Lesson: limit-fill replays must fill buy limits on the ask, or they flatter results.**
  - **Marubozu** (`gold_marubozu_research.py`): M15 −377R / −279R; H1 1R −10.3R, 2R +29.8R PF 1.07 3/7. Fails.
  - **ERC (extended range candle) filter on the Asia breakout bar** (`gold_erc_filter_research.py`, body ≥ 80% of range): ERC −1.5R (skip 24%), ERC+H1 +3.5R, ERC+FVG+H1 +4.5R (67 tr), all fail. Re-confirms FVG+H1 (183 tr, +27.2R, PF 1.43, coin 100%, skip 100%) as the only displacement filter that adds information: **the gap left behind matters, the candle's shape doesn't.**
- **Chart-lesson batch 3 on gold, 2026-10-13 (realistic limit fills, coin control):**
  - **Three areas after one impulse** (`gold_three_areas_research.py`, impulse ≥1.5 ATR + FVG, 2R): Demand 1 (base) fails; the gap with a tight stop fails; Demand 2 (pause after the impulse) fails (M15 −97R). **Gap entry with the stop beyond the impulse candle (GAP_DEEP) M15: 2,794 tr, +123.7R, PF 1.07, 5/7, coin 100% = PASS on paper but thin** (PF 1.07, 2023 −36R, one of 8 cells tested). Lead only; H1 GAP_DEEP fails (coin 90%).
  - **Bull/bear flags** (`gold_flag_research.py`): M15 +7.2R 3/7, H1 +8.3R 4/7. Fail.
  - **Structure retest** (`gold_structure_retest_research.py`, trend-aligned swing-level break → limit at the broken level): M15 −166.9R; H1 +17.1R, 5/7, coin 80%. Fail.
  - **Balanced vs reversal return into a zone** (`gold_return_type_research.py`): the first run passed big (Demand 1 balanced M15 +70.6R, PF 1.25), but **it was lookahead**: the 'fast return' check read the close of the very bar that filled the order. With only bars closed before the fill, every cell fails (Demand 1 balanced M15 −20.6R). **Lesson: any filter on the bar that fills a limit order must use only bars closed before the fill.**
  - **Real zone vs fake zone ('sell traps')** (`gold_real_vs_fake_zone_research.py`, leg ≥ 3 ATR between confirmed swings, limit at the zone, stop 0.25 ATR beyond, TP = the leg extreme): **fake zone M15 −1,770R, win 7%; H1 −541R.** The trap is real: minor zones inside a leg get run through (the coin's opposite side wins). **Real zone M15 −354R, win 15%; H1 −105R.** The origin zone loses too with a tight stop and a full-leg target. Neither is tradable.
  - **Pin bar strength grades at a 20-bar extreme** (`gold_pinbar_grade_research.py`, strongest ≥75% wick … indecision, 1R/2R, M15/H1): **all 16 cells lose** and most are worse than a coin flip. Fading a fresh 20-bar high/low on gold with a pin bar is a losing trade at every strength. Matches the earlier finding that gold momentum continues.
  - **FVG filtering** (`gold_fvg_filter_research.py`, Expertsbazaar image 2026-10-13: skip the gaps price closes through, trade the deeper gap that holds): **the filter makes it worse.** Every gap with a limit at the near edge, H1: 2,188 tr, +97.6R, PF 1.07, 6/7, coin 100% (a technical pass but thin; the similar thin GAP_DEEP lead fell to 3/7 in MT5). Waiting for the gap to hold (RESPECT): H1 PF 1.03 4/7, M15 PF 0.83 0/7. The picture's exact setup (a newer gap died first, RESPECT_STACK): H1 617 tr PF 1.11 4/7, M15 PF 0.91. M15 loses in every variant.
- **Grids and martingales:** Life Changer (×1.23, 20 adds, 12-pip spacing) and Gorilla V6 (3 Ilan engines, ×1.55, no SL), both read from source in [[Google Drive EA Library]]; [[Thunderbolt EA Review]] (martingale ×2, 4–9 positions; read from its presets, never run), [[Dominant EA PRO Review]] (9–21 wipeouts) and the TWP grid sets (the breaker tripped in 2 of 3 years).
- **Other ORB variants:**
  - [[TWI Gold ORB]]: PF 0.64.
  - [[TWI Range Breaker]]: the vendor's curve doesn't reproduce.
  - [[TWI PAT ORB SMART]]: the scored version lost; the current bare-bones version was never tested.
  - The **London session** of ORB Momentum: 3 of 7 years positive on EURUSD.
- **Thin or one-window results:**
  - [[TWI VWAP Drift Pullback]]: 42 trades, and gold lost.
  - [[TWI TakeProfit SMC EA]]: +0.049R over one month.
  - [[TWI SMC Auction Flow]]: +0.013R over 21 deals.
  - [[TWI SR Sweep Reclaim]]: 3 trades.
  - [[TWI Liquidity Sweep OB EA]]: 9 real-tick trades.

## Never tested (no evidence either way)
- **EAs with no backtest:**
  - [[TWI 9AM CR Model EA]].
  - [[TWI AMD iFVG EA]]: a backtest was started on 09-02 and never recorded.
  - [[TWI HS Pullback EA]]: blocked by the tester permission.
  - [[TWI Liquidity Sweep BOS]].
  - [[TWI Gold MTF Grid]].
  - The BLCM engine (`TWI BLCM Engine.mq5`, no note; the framework is in [[Bias Location Confirmation Management Framework]]).
- [[Ai Monster EA Pro Review]] (third-party encrypted .ex5, 2026-10-12): not installed. It needs DLL + WebRequest, so it's untestable on the live terminal.
- **Running live with no backtest at all** (per their notes; the VPS has been unreachable since 09-25, so this is unverified):
  - [[TWI Scalp Pro]]: attached on RisenAdam and RisenMOM since August.
  - [[TWI Telegram Copy]].

## What the pattern says
1. **Momentum at a session open works. Fading zones doesn't.** Every OB/FVG/supply-demand reversal we mechanised has failed the random control. The only pass is "go with the break at the NY open".
2. **Cost decides it.** A ~52-pt gold spread kills small stops and small targets. The pass lives on EURUSD at 0–2 pts.
3. **High win rates come from geometry, not prediction:** a wide stop and a near target. That's fine when the direction signal beats a coin flip, as ORB Momentum does. A grid fakes the same win rate without any edge.
4. **One window proves nothing.** OB Hunter (PF 1.18) and EQ OB (+0.2R) both looked good on 12–17 months and failed on 7 years.

## Build plan (proposed 2026-10-11)
Build a portfolio around the one engine that passed: the ORB Momentum EA (one EA, one magic per session/market).
1. **Deploy v1.20 EURUSD NY at 0.01.** Waiting on Adam's lot size and deployment call. The VPS is unreachable, so it would have to go on the laptop terminal.
2. **Confirm USDJPY London in the MT5 tester** (every tick, 2023–26). If it holds, add it as a second leg. That's more trades without an extra lot size per trade.
3. **Port the engine to NAS100/US30 NY 09:30**, which are cheap indices that open at 09:30. Test with the same replay and coin control.
4. **Retire everything in "Failed"**, and pull Scalp Pro / OB Hunter off any live chart until they pass this bar.
