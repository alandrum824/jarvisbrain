---
status: active
project: forex-trading
type: reference
---
# TWI SMC POI

MQL5 EA built 2026-09-23 (evening) when Adam said "let's simplify our EA" and then "just follow these images". It's built straight from two "Forex School" graphics: **"BOS + Liquidity Sweep + OB = High Probability Long"** and **"Liquidity Sweep to Point of Interest — The Classic SMC Short"**.

**It's a new, separate EA. [[TWI Liquidity Sweep OB EA]] and [[TWI Liquidity Sweep BOS]] stay frozen under the V1 lock, untouched.** Adam chose "New" over lifting the lock.

## How it differs from the OB EA
The OB EA is a **reversal** model: sweep → BOS → OB retest. The graphics show a **continuation** model: BOS first → a pullback sweeps post-BOS liquidity → price taps the POI → the target is opposing liquidity. The sweep is the trigger into the zone, not the start of the setup. That's closer to [[TWI BOS Trap Entry]]'s order.

## Rules (long; short mirrored)
1. **BOS:** a bar closes above the last confirmed swing high (fractal, `SwingBars` each side, registered only after the right-side bars have closed). Each swing can be broken once.
2. **POI:** the last bearish candle at or before the low of the leg that caused the break. Zone = that candle's open (top) down to the leg low (bottom).
3. **Target (BSL):** the highest high since the leg low. It extends with price until the sweep, then freezes.
4. **Sweep:** a pullback bar's low takes out a swing low that formed after the BOS and sits above the POI (inducement).
5. **Entry:** a buy limit at the POI top edge ("LTF POI"). If the sweep bar already closed inside the zone, it enters at market.
6. **SL** below the POI + `SLBufferPoints`. **TP** at the BSL − `TPBufferPoints`. Skip if RR < `MinRR`.
7. **Cancel:** POI touched before any sweep; a close through the POI; a new high above the frozen target before the fill; or `MaxSetupBars` since the BOS.

One setup at a time. New BOS events while a setup is running are marked used but ignored, so the inducement sweep can't hijack the setup as an opposite BOS. All setup logic reads closed bars only. The BOS bar itself is skipped.

**Two simplifications (told to Adam before the build):**
- No separate lower-timeframe refinement: the "LTF POI" is the zone's proximal edge.
- The short graphic's sweep sits at the leg low, not on the pullback. The target rule still lands on that low.

## Inputs (12)
`MagicNumber` 20260923 · `TradeComment` · `SwingBars` 3 · `MaxOBSearchBars` 20 · `MaxSetupBars` 240 · `SLBufferPoints` 30 · `TPBufferPoints` 0 · `MinRR` 1.0 · `RiskPercent` 0.5 · `RiskOvershootTolerancePercent` 10 · `MaxSpreadPoints` 55 · `DebugMode` true.

**Removed compared with the OB EA:** sessions, daily governor, HTF bias, BE, partials, concurrent long/short setups, rejection confirmation, displacement filter, news stub, visuals.

**Carried over (accounting, already validated on real ticks):**
- `OrderCalcProfit()`-only sizing, because this broker's `SYMBOL_TRADE_TICK_VALUE` is 100x wrong.
- The risk-overshoot ceiling.
- The 55-point spread gate. It's checked when the order is placed; a resting limit can still fill in a later spike.
- The stops-level skip (never widened).

**Improved over the OB EA:**
- `InitialRiskMoney` is frozen at the **actual fill price** (`POSITION_PRICE_OPEN`).
- NetPnL sums **every** deal of the position (entry + exit: profit, commission, swap, `DEAL_FEE`), via `HistorySelectByPosition`. The OB EA's defect #4 therefore doesn't exist here.

**Summary on deinit:** funnel (BOS → no POI → armed → touched before sweep → closed through the POI → swept → RR/spread/stops/risk/order-fail → placed → target taken/timeout → filled), then trades, W/L, win rate, net, PF, max consecutive losses, total/avg R, R_INVALID, BUY/SELL splits and costs.

## Source location
- Vault master: `02 - Forex Trading/TWI SMC POI.mq5`
- Deployed **(not attached)**: `MQL5/Experts/Advisors/TWISMCPOI.mq5` on the AAAFx/RisenAdam terminal. Vault = deployed, md5 `387a5e07…`.
- **Compiled 0 errors / 0 warnings** (the first pass had one uninitialized-variable warning, now fixed). No tester `.set` cache exists yet.

## Status (2026-09-23 21:42 PT)
- **v1.01: compiled, deployed, NOT attached.** Both Run 1 defects are fixed. On 8 real-tick days: M1 loses (stops too close to the spread), M5 −4.5R on 12 trades, M15 +3.3R on 9 trades (one winner). **No edge claim at any timeframe; the sample is too small.**
- Next: a long-sample M15/M5 run on the Dukascopy data once it's cleared. Read the tester input dump first ([[MBT (MT5 Backtest Toolkit)]] `.set` trap: a `TWISMCPOI.set` cache now exists). Use a unique `Report=` name.

## REAL-TICK RUN 1 — M1, AAAFx Sept 11–22 (2026-09-23 22:41 PT). LOSER, LOW SAMPLE.
Config `tester_configs/smcpoi_v1_XAUUSD_M1_realticks_20260911-20260922_20260923_2239.ini` (+ `.htm`). The input dump matched the compiled defaults, with no `.set` cache. Real ticks: 7,322,947 (the same set as the OB EA's runs A/B). Leverage capped at 1:100. Log archived: `TWI SMC POI - REAL-TICK Run 1 M1 Log (2026-09-23).log`.

**Funnel:** BOS 240 → armed 240 → POI touched before sweep 103 / closed through the POI 13 → swept 124 → RR low 1, spread 1 → placed 122 → target taken before fill 60, timeout 6 → **filled 56**.
**Result:** 56 trades, 7W/49L (12.5%), net **−$1,249.99**, PF 0.47, total **−31.80R** (avg −0.568R), max 12 losses in a row. BUY 28 (−28.76R), SELL 28 (−3.04R). Costs $0. R_INVALID 0.

**Why it loses: stops are too small for gold's spread on M1.** Median SL 192 pts, against a ~52-pt spread. Median planned RR 4.46.

| SL distance | n | wins | total R |
|---|---|---|---|
| 0–100 pts | 4 | 0 | −12.48 |
| 100–150 | 12 | 0 | −12.32 |
| 150–250 | 21 | 2 | −8.41 |
| 250–400 | 15 | 4 | +2.48 |
| 400+ | 4 | 1 | −1.06 |

Under 250 pts: 37 trades, 2 wins, −33.2R. 250+ pts: 19 trades, 5 wins, +1.4R. One stop was 35 pts, smaller than the spread. It's the same trap family as [[TWI TakeProfit SMC EA]]'s gold spread issue, but here it's in the zone geometry, not a gate. The graphics are almost certainly a higher timeframe.

**Two real defects of mine, found in this run (report only, not fixed yet — code edit needs Adam's confirmation):**
1. **Pending limits rest over the weekend.** A Friday 23:16 buy limit (4344.31, SL 4342.40) filled at Monday's gap open at **4341.44, already below its stop**, and was stopped at 4333.09: −$208.75 on a planned $47.75 risk (**−4.37× planned risk**).
2. **The R base breaks when the fill is beyond the SL.** The fill-to-SL distance shrank to 0.96, so InitialRiskMoney = $24.00 and the trade printed **−8.70R**. Against planned risk it's −4.37R. The actual-fill R base needs a fallback to planned risk when the fill lands beyond the stop.

## v1.01 — both defects FIXED (Adam approved, 2026-09-23 ~22:45 PT)
1. **`FridayCutoffHour` = 23** (new input, 13 total). From 23:00 server time Friday, any pending limit is deleted and any waiting setup is dropped. Nothing new gets armed; BOS flags still update. Open *positions* are not force-closed; that wasn't part of the fix.
2. **Fill beyond the SL → R base = planned risk** (`plannedRiskMoney`, the projected loss at placement). The trade is flagged `FILLED BEYOND SL` in R BASE and counted in the summary.
Compiled 0/0, vault = deployed (md5 `03eebdff…`). Run 1 left a `TWISMCPOI.set` cache behind, so every v1.01 run passes all 13 inputs via `[TesterInputs]`, and each dump was checked.

## REAL-TICK v1.01 — M1 / M5 / M15, same Sept 11–22 ticks (2026-09-23 22:49–22:57 PT)
Configs/reports `tester_configs/smcpoi_v101_XAUUSD_{M1,M5,M15}_realticks_20260911-20260922_20260923_2249.*`. All three input dumps matched. All three used the same 7,322,947 real ticks. Logs archived: `TWI SMC POI - REAL-TICK v1.01 {M1,M5,M15} Log (2026-09-23).log`.

| | M1 | M5 | M15 |
|---|---|---|---|
| BOS → swept → placed → filled | 245 → 121 → 120 → 54 | 53 → 28 → 27 → 12 | 24 → 12 → 12 → 9 |
| Friday cancels / filled beyond SL | 7 / 0 | 2 / 0 | 1 / 0 |
| Trades, W/L | 54, 7/47 (13.0%) | 12, 2/10 (16.7%) | 9, 2/7 (22.2%) |
| Net / PF | −$990.79 / 0.54 | −$201.31 / 0.58 | **+$88.59 / 1.25** |
| Total R / avg R | −22.10 / −0.409 | −4.54 / −0.378 | **+3.33 / +0.370** |
| Median SL | 202 pts | 592 pts | 626 pts |
| Worst loss | −1.66R | −1.09R | −1.15R |

**Read:**
- The Friday fix removed the weekend gap trade. M1 went from −31.8R (Run 1) to −22.1R, but it's still a clear loser with spread-sized stops.
- On M5/M15, stops are 3–12× the spread and **every loser is a clean −1.0 to −1.15R**, so the spread problem is gone at those timeframes.
- M15's +3.33R rests on **9 trades, and one +7.95R winner carries it**. Take that one out and it's negative. **Not evidence of an edge.**
- Win rates are low (13–22%) against high planned RR (median ~4–5R). The targets are far liquidity, so this model lives or dies on the rare big winner, and it needs hundreds of trades to judge.

**Next:** a long sample on M15 (and M5). That depends on the Dukascopy Jan–Aug data ([[XAUUSD Tick Data Infrastructure]]), whose full download is still gated on the AAAFx DST-regime proof. Note: Dukascopy's native spread (~64 pts) exceeds the 55 gate, so the gate has to be handled for that data.

## Pine v6 indicator version (2026-09-23 ~23:20 PT, Adam: "build a Pine Script version 6 indicator instead")
- **Source:** `02 - Forex Trading/TWI SMC POI.pine` (287 lines). **Compiled 0 errors / 0 warnings on TradingView's server** (`pine_check`, the code with comments stripped). **Not on any chart yet**: nothing was added to the TradingView layout, and no Pine Editor slot was touched.
- **Same rules as EA v1.01:** BOS on close → POI (last opposing candle at the leg extreme; open → leg extreme) → target extends until the sweep → a post-BOS swing above the POI (below it for shorts) gets swept → limit at the POI edge (or at the sweep bar's close if it closed inside) → SL beyond the POI + buffer, TP at BSL/SSL → the same cancellations. A BOS only arms if the setup was idle when the bar closed, which mirrors the EA's check order.
- **Chart:** the POI box (greyed when dropped, with a reason label), BOS line, BSL/SSL target line, LQ Sweep marker, entry/SL/TP lines, BUY/SELL fill labels, WIN/LOSS labels in R. Stats table: live state, BOS/swept/filled, trades, win rate, total R, PF in R.
- **Alerts:** `alert()` fires on bar close for sweep + order level, limit filled, TP/SL hit. Use "Any alert() function call".
- **Differences from the EA (on purpose):**
  - Everything runs on confirmed bars, from OHLC.
  - If a bar touches both SL and TP, it's scored a **LOSS**.
  - On the fill bar only the SL counts, because OHLC can't show the order of events.
  - There's no spread (TradingView charts bid only) and no lot sizing: results are in R.
  - The Friday cutoff defaults to **16:00 exchange time** (OANDA:XAUUSD = New York; gold closes Fri 17:00 NY), not the EA's 23:00 server time.
- **SAVED + ON THE CHART 2026-09-23 ~23:28 PT (Adam: "save it and take any indicator").** Saved as a NEW TradingView script **"TWI SMC POI", id `USER;c3be6a54b4a04287be24cd1f4f109e73`**, created with the banked Make-a-copy method (script count 41 → 42; all other scripts' `modified` timestamps unchanged). Source = the `pine_check`-verified code: the same logic as the vault `.pine`, with the vault copy's long rules comments trimmed to a 1-line header; editor footer "2 · Today, 23:27". Added via the editor's **Add to chart** on the synced layout `uJnBMo6l`, switched to **OANDA:XAUUSD 15m** (it was FX:CADJPY 30m). **Nothing removed:** the chart only had "Sweep Reversal Map [Herman]", so it's now 2 studies (TWI SMC POI `lv1OY5` + Sweep Reversal Map `aiX5lR`).
- **First on-chart read (OANDA:XAUUSD 15m, loaded history, conservative OHLC scoring):** BOS 125 → swept 68 → filled 30. **30 trades, 3 wins (10%), −16.95R, PF 0.37 (in R).** The labels confirm the full pipeline is drawing (BOS, BSL/SSL, LQ Sweep, SELL LIMIT RR 10.07, BUY, LOSS −1R, the drop reasons). It hits the 500-label cap, so the oldest labels roll off. **A second, independent sample (a different feed, a longer window than the 8-day tester run) that also says the model doesn't pay as-is.**
- **v1.1 display cleanup (Adam: "go", 2026-09-24 ~03:27 PT; trade rules unchanged):** cancelled setups are erased (toggle "Show cancelled setups" shows them as tiny grey "x" tags with the reason as a tooltip); only the live setup plus the last `keepN`=5 finished trades stay on the chart (fixed per-trade drawing sets, trimmed FIFO); BOS/BSL/SSL/LQ are tiny tags with tooltips; position-tool TP/SL boxes (light while pending, stronger once filled); order label "SELL LIMIT 2.1R" with levels in the tooltip; table defaults bottom-right with a position input. `pine_check` 0/0; the vault `.pine` = deployed. **Saved as script v3 (`c3be…`), verified in `pine_list_scripts`.** Along the way `pine_open` mis-bound and saved into the ORB slot; it was reverted (see [[Malaysian SNR x Orderflow]] gotcha 2026-09-24). Rendering not yet eyeballed by me: the desktop chart carries the ORB; Adam's phone layout has SMC POI.
- **Fourth sample (Adam's phone, 2026-09-24 03:17): GBPAUD 5m, 27 trades, 9 wins (33.3%), +9.48R, PF 1.53.** The first positive read. It contrasts with GBPAUD 15m (−16.45R), so it's too small and too mixed to call.
- **REMOVED FROM THE CHART 2026-09-24 ~02:19 PT** to make room for [[TWI ORB Trend Retest]] (2-indicator cap). The script is still saved (`USER;c3be6a54…`).
- **Third sample (Adam's phone, 2026-09-23 23:34): GBPAUD 15m**, BOS 145 → swept 67 → filled 34, **34 trades, 4 wins (11.8%), −16.45R, PF 0.45**. A different instrument with the same result as gold: the model loses mechanically across feeds and pairs.
- **Adam's phone chart (screenshot 2026-09-23 23:27)** showed the same synced XAUUSD 15m with Sweep Reversal (hidden) and **two MSNR copies** (one hidden, one showing old-style raw "E" engulfing flags, which suggests the pre-BUY/SELL-filter version). Cosmetic cleanup is offered, not done.
- **Caveats (kept for reference):**
  - The TradingView Basic plan caps a chart at **2 indicators**.
  - Per [[TWI Tap & Close]], `pine_new` has overwritten a real script slot before. Save it as a new script only, never over an existing one.

## v1.2 research + v2.0 Reversal model (2026-09-24 ~03:40–04:00 PT, Adam: "re-evaluate strategy and make it better", then 5 more graphics "use these to better our strategy")
**v1.2 research table** (saved as script v4): every swept setup is simulated in parallel, 2 entries (limit at the POI edge vs market at the sweep close) x 5 targets (1R/1.5R/2R/3R/structure), all vs a filter column. OHLC-conservative. **CONTINUATION, 6 markets (OANDA XAUUSD/GBPAUD/EURUSD, 5m+15m), totals, limit entry (~190 trades/cell):** 1R −3R, **1.5R +7.5R (~42% win, positive in 4/6)**, 2R −18R, 3R −7R, **structure BSL −32.5R (the worst setting, i.e. the old default)**. The HTF-trend filter made every column worse. Close entry: great on gold 5m (+12R @3R) but negative in aggregate. Adverse-selection signal on gold 5m: limit MFE 0.48R vs close 1.16R, but it didn't generalize.
**Adam's 5 graphics (Trading for Beginners)** are all the REVERSAL model: sweep of a swing (close back inside) → MSS/CHoCH close through the opposite swing → OB at the start of the move (often an FVG) → limit on the retest; one says RR 1.5 explicitly; two require an older HTF OB; one a confirmation candle.
**v2.0 (script v5/v6, Adam "yes"):** Model input Reversal (default) / Continuation; Target input 1R/1.5R/2R/3R/Structure (**default 1.5R for both**); `mssBars` 20; shared order engine; research filter column = FVG (Reversal) / HTF trend (Continuation). **Research bug found and fixed (v2.0.1, script v6):** research limit legs were cancelled at the structure level, which in Reversal is right at price. Now they cancel at the live TP level like the live engine. Verified: research "Limit – all" count = live fills on every market.
**REVERSAL, same 6 markets, live 1.5R limit:** EURUSD 5m 11 trades −8.5R · EURUSD 15m 22 −2R · GBPAUD 5m 11 −1R · GBPAUD 15m 14 +3.5R · XAUUSD 5m 5 −2.5R · XAUUSD 15m 9 +3.5R → **72 trades, 36% win, −7R**. Research totals (limit): **1R +6R (54% win)**, 1.5R −7R, 2R −6R, 3R −8R. Close entry negative everywhere except gold 15m (+19.5R @1.5R, 38 trades). **The FVG filter did not help** (mostly worse). Fill rate is low (208 placed → 72 filled).
**Verdict:** neither model has a reliable edge on this data. Best found: **Continuation + 1.5R = +7.5R/~195 trades (~42% win)**; Reversal + 1R = +6R/72 (54% win). Both ≈ breakeven (+0.04–0.08R/trade). The graphics' model is not better than the continuation model once mechanized.

## Related
- [[TWI Liquidity Sweep OB EA]] — the frozen reversal sibling, the source of the sizing/R code
- [[TWI Liquidity Sweep BOS]] — the frozen sweep-first sibling
- [[TWI BOS Trap Entry]] — the closest prior sequence (BOS first → OB → IDM sweep → tap)
- [[XAUUSD Tick Data Infrastructure]] — the real-tick data
- [[Active Priorities]]
