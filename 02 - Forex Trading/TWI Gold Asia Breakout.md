---
status: active
project: forex-trading
type: reference
---
# TWI Gold Asia Breakout

MQL5 gold Asian-range breakout EA built 2026-10-12 (~6:35 PM PT) from the [[Gold EA Market Survey]] (Aurum Range Breakout's published rules). Adam: "look at gold EA's all over the Internet see which ones are successful and start work from there. Build me a EA" → "Gold". Source: `TWI Gold Asia Breakout.mq5` (this folder).

**Status: PASSES the [[EA Scorecard]] bar. It is our first gold EA to pass: 6/7 years in both engines, beat the coin flip 100%.** **v1.01 is ATTACHED in SHADOW mode** (2026-10-12 8:30 PM PT, Adam: "add this ea to my account but not live trade yet"). It runs on the laptop terminal, account 8996721 (AAAFxGlobal-5 Real), on an XAUUSD M5 chart, with **AutoTrading OFF as well**. It sends no orders: it tracks each day's trade virtually from live bid/ask and appends it to `MQL5\Files\TWIGoldAsia_shadow.csv`. Compiled 0/0; the vault copy is byte-identical to `MQL5\Experts\Advisors\TWIGoldAsiaBreakout.mq5`. The v1.00 backup is `stg\trendscalper\TWIGoldAsiaBreakout_v100.mq5`.

## Rules (all times GMT; nothing tuned, the published defaults)
1. **Range:** high and low of 00:00–05:00 (needs ≥ 200 M1 bars).
2. **Filter:** skip the day if the width is < 0.10 or > 0.80 × daily ATR(14) (yesterday's).
3. **05:00:** buy stop at high + 5% of the width, sell stop at low − 5%, **OCO** (the first fill deletes the other). SL = the other order's price (≈ 1.1 × the range), **TP 1R**. If price is already outside the range at 05:00, it takes that side at market.
4. **15:00:** cancel unfilled orders. **16:00:** close the trade. Nothing held overnight, no swap.
5. One trade a day, a hard SL on every order, no grid. Skips the day if the spread is more than 10% of the stop.
- Sizing: `LOTS_FIXED` 0.01 (default) or `LOTS_RISK_PERCENT` (0.5%). Magic 20261014.
- **Clock:** server → GMT with the AAAFx history (London time before 2022-03-27, UTC+0 until 2026-03-07, NY+7 after). On another broker, set `TimeMode`/`ServerUTCOffsetHours`.
- Daily ATR uses broker D1 bars (server days); the replay used GMT days. The small difference didn't change the result.

## v1.01 shadow mode (2026-10-12)
- **`RunMode = RUN_SHADOW` (the default):** on a live chart, no order function is ever called.
  - At 05:00 GMT it arms two virtual stop orders. A fill happens when the ask reaches the buy stop or the bid reaches the sell stop.
  - The virtual SL and TP are checked on the closing side (the bid for a buy, the ask for a sell). The 15:00 cancel and the 16:00 close work as live.
  - Each closed trade is logged to the Experts tab (`[TWI GA] SHADOW ...`) and to the CSV: fill and close server times, side, entry, SL, TP, exit, reason, R, and money at the lots it would have used.
- **`RUN_LIVE`** sends real orders. **The strategy tester always runs LIVE**, so the backtests above still apply.
- **Limits:**
  - A terminal restart loses an open virtual trade and that day's armed orders.
  - Virtual fills use the live quote, so they show the spread but not execution slippage. Slippage only shows on a demo or live order.
- **How it was attached** (the method to reuse): with the terminal closed, start it with `terminal64.exe /config:"<DATA>\tester_configs\attach_gold_asia.ini"`, which contains `[Experts] AllowLiveTrading=0, Enabled=0` and `[StartUp] Expert=Advisors\TWIGoldAsiaBreakout, Symbol=XAUUSD, Period=M5`. The log confirmed `loaded successfully`, `SHADOW MODE`, and `init ... AAAFx clock on`.
- **Outage 2026-10-14 → 10-22:** the terminal stopped with a Windows shutdown at 04:29 on 10-14 ("terminal stopped due to system shutdown") and nothing restarted it, so the shadow test logged nothing for 8 days. Found and relaunched with the attach config 2026-10-22 2:26 PM PT ("loaded successfully"). MT5 doesn't restart itself after a reboot; a startup entry would fix that (not set up).
- **Attach method corrected 2026-10-22 (the `/config` [StartUp] way is NOT persistent):** a [StartUp] chart is temporary. It isn't saved in the profile, a second [StartUp] config replaces it (launching the NAS100 attach removed this EA), and a plain restart doesn't bring it back. **Working method:** with the terminal closed, add a chart file to `MQL5\Profiles\Charts\Default\` (a copy of an existing `chartNN.chr`, UTF-16, with `symbol=` / `period_size=` changed and an `<expert>` block before `</chart>`: `name=TWIGoldAsiaBreakout`, `path=Experts\Advisors\TWIGoldAsiaBreakout.ex5`, `expertmode=1`, empty `<inputs>` = compiled defaults), list it in `order.wnd`, then start `terminal64.exe` with no config. Script: `C:\Users\aland\stg\obh\mk_charts.py`. Verified 14:43: both this EA (chart03, XAUUSD M5) and [[TWI NAS100 ORB]] (chart04, NAS100 M1) "loaded successfully".
- **Warning:** the MT5 tester runners (`gbyears.py`, `gayears.py`, `years2.py`) **kill the running terminal**, and that stops the shadow EA. After any tester run, restart the terminal with the attach config above. A normal close saves the chart in the profile, so a plain restart also reloads it.
- **Going live** needs Adam's explicit go. On ~$400, 0.01 risks about $47 on a median 2026 trade (~12% of the account), so live needs either a bigger account or a different market (see the FX test below).

## v1.02 Account Guard (2026-10-12 ~11:05 PM, Adam: "Yes" to merging the [[TWI Gold Scalper v1]] guard)
**Vault source = v1.02, compiled 0 errors / 0 warnings under a throwaway check name. NOT deployed yet.** The live terminal still runs v1.01: recompiling the attached EA's file would make MT5 reload it and drop tonight's open shadow trade. **Swap it in after 16:00 GMT (9 AM PT) on 2026-10-13.** The v1.01 backup is `stg\trendscalper\TWIGoldAsiaBreakout_v101.mq5`.
- **Guard (LIVE + tester only; SHADOW is unaffected):** state lives in terminal global variables (`TGA_G_<login>_<magic>_`), so it survives restarts.
  - **Loss pauses:** realized loss today ≥ 2% pauses to the next server day; this week ≥ 5% pauses to the next week.
  - **Kill switch:** equity 15% under the peak balance trips it with an Alert and deletes unfilled orders. Re-arm only via `GuardRearm`.
  - **Headroom sizing:** a stop can't cross the kill floor; if even the min lot can't fit, it trips.
  - **Free margin** of at least 50% after the order.
- **Sizing:** risk-% is capped at 2% and halved after 3 losses in a row (until a win or a new peak). If the min lot would over-risk, or a fixed lot breaks `MaxRiskPerTradePct`: no trade + Alert.
- **It never closes, adds to or hedges a position.** Entry, exits and the clock are unchanged from v1.01.
- **Not merged from the chassis, on purpose:** the news filter, Friday rules and spread-median filter. They would change which days trade, and the edge was tested without them. This EA is already flat by 16:00 GMT daily.
- **Test plan once deployed** (in the MT5 tester, after the shadow trade closes):
  1. **Regression:** 2020–26 $10k / 0.01 must match the v1.00 run (1,600 trades, PF 1.33) unless the guard fires.
  2. **The brief's checks:** every order has an SL, the guard trips at the set % on a small deposit, and the min-lot halt Alert fires in risk-% mode on a small deposit.

## v1.03 Retest Sniper add-on (2026-10-13 ~12:40 AM, Adam: "study order blocks fvg ... momentum ... sniper entries ... put it all together and make an ea and test ... be more determined")
**Research** (`gold_sniper_research.py`, pre-registered, 6 cells, coin control). OB/FVG/sniper entries are used as the entry on top of the proven Asia breakout direction:
| Sniper entry | Trades | R | PF | Years + | Beats coin |
|---|---|---|---|---|---|
| **RETEST (limit at the broken edge, SL range mid, TP measured move), all breakouts** | 1,502 | **+50.9** | 1.05 | 4/7 | **96%** |
| RETEST, momentum bar only (body ≥ 0.8 ATR M5) | 1,062 | +36.5 | 1.06 | 4/7 | 86% |
| FVG in the breakout leg, 2R | 752–1,059 | −42 / −105 | 0.86–0.92 | 1–2/7 | 8–20% |
| Order block (last opposite candle), 2R | 812–1,132 | −95 / −122 | 0.83–0.85 | 1–2/7 | 0–2% |

- **FVG/OB snipers fail because their stops are too tight** (median $1.40–1.78) for gold's M5 noise. The **retest sniper works on direction** (coin 96%). The momentum filter didn't help.
- **Base + retest combined** (`gold_asia_combo_research.py`): **3,109 trades, +125.1R, PF 1.08, 5/7 years, beat the coin 100%**. Caveats: the combination was chosen after seeing results, and the legs' yearly R correlates at 0.88, so it mostly adds size to the same edge (2021 −26.6R, 2022 −16.9R).
- **Built into v1.03:** `UseRetestSniper` (default **OFF**), magic + 1, one per day. After the first M5 close beyond the range it places a limit at the broken edge (or goes to market if price is already back through). SL = range midpoint, TP = edge ± width. Cancelled at 15:00, closed at 16:00 GMT. The guard counts sniper deals. LIVE/tester only (not in SHADOW).
- Compiled 0/0 under a check name; **not deployed** (the live chart still runs v1.01 shadow). **Next:** MT5 tester 2020–26 with the sniper OFF (must match ~1,600 trades, PF 1.33) and ON (does the combo hold in the second engine?).

## v1.04 FVG + Trend mode (2026-10-13 ~1:00 AM, Adam: "use zones and tread lines to help determine trend ... fvg to realize price has real momentum ... make it better" + "multi timeframe trend detection")
**Research** (`gold_filters_research.py`, pre-registered; `gold_filters_mtf_research.py`, follow-up). The base is entry at the first M5 close beyond the range, SL at the other side, 1R (REF: 1,600 trades, +31.5R, +0.020R/trade, 4/7). The filters must also beat **random trade-skipping** (keeping the same number of trades at random):
| Filter | Trades | Avg R | PF | Win | Years + | Coin | Random skip |
|---|---|---|---|---|---|---|---|
| **FVG + H1 structure trend** | **183** | **+0.149** | **1.43** | 57% | **5/7** | **100%** | **100%** |
| FVG + H1 + H4 agree (MTF, follow-up) | 66 | +0.167 | 1.51 | 55% | 5/7 | 98% | 98% |
| FVG + H4 (follow-up) | 186 | +0.089 | 1.25 | 53% | 5/7 | 98% | 90% |
| H1 + H4, no FVG (follow-up) | 143 | +0.120 | 1.33 | 56% | 5/7 | 94% | 88% |
| H4 trend | 474 | +0.070 | 1.19 | 53% | 5/7 | 94% | 92% |
| H1 trend | 463 | +0.071 | 1.19 | 54% | 3/7 | 100% | 94% |
| FVG (breakout bar leaves a gap) | 627 | +0.037 | 1.10 | 51% | 5/7 | 98% | 78% |
| ROOM (no opposing H1 swing before 1R) | 396 | +0.022 | 1.06 | 51% | 3/7 | 78% | 52% |
- **Adam's idea works:** momentum (FVG) + structure trend is **7× the per-trade edge** of unfiltered breakouts. It's the only filter that beat random skipping at 100%. Each piece alone helps only a little; the zone "room" filter adds nothing.
- Trend = the last two confirmed fractal (3/3) swing highs AND lows rising (buy) or falling (sell).
- **Daily + A+ (Adam: "We want at least one trade per day"; `gold_daily_aplus_research.py`):** keep the daily OCO breakout (1.00 trade per valid-range day, ~0.92 per weekday) and add the FVG+H1 trade as a second position: **1,790 trades, +101.4R, PF 1.15, 6/7 years, coin 100%** (2021 −20.7R is the only losing year). That beats the base alone (+74R) and base + sniper (+125R but 5/7). Combination chosen after the fact; MT5 pending.
- **Built into v1.04:** `FvgTrendMode` = OFF (default) / **ADD_ON** (daily OCO plus the A+ trade, magic + 2, closed 16:00 GMT) / REPLACE_BASE (A+ only, replacing the 05:00 OCO stops). For the A+ trade: at the first M5 close beyond the range it enters at market only if that bar left an FVG (bull: low[1] > high[3]) and the structure agrees. `TrendTimeframes` = H1 (default) / H4 / H1+H4. SL = other side − 5% width, TP 1R, flat 16:00 GMT. LIVE/tester only. Compiled 0/0 under a check name; not deployed.
- **Caveats:** only ~27 trades/year (FVG+H1) or ~10 (MTF), and 8 cells were looked at, so it **needs the MT5 tester as the second engine**.

## TradingView indicator (2026-10-12 ~11:20 PM, Adam: "make that indicator on trading view the one that works")
Saved as a new script, **"TWI Gold Asia Breakout"**, id `USER;ee6f57da0ed44bd5ad317b3e3e1d1b12`. It's on the OANDA:XAUUSD chart (set to 15m). Source: `TWI Gold Asia Breakout.pine` (this folder), compiled clean. The Pine copy was made with Make-a-copy after the `pine_new` bug.
- **What it shows:** the 00–05 UTC range box (orange = day skipped by the ATR filter), buy/sell stop lines from 05:00, BUY/SELL labels on the first touch, SL/TP lines, a ±R tag at the close (16:00 UTC, or SL/TP), and a table (status, trades, win %, total R, armed levels). Alerts: armed / BUY / SELL.
- **Same rules as the EA.** The tracker uses bar highs/lows with no spread (SL first if a bar touches both), so it reads slightly better than live.
- **First read (OANDA, 15m, the loaded history):** 70 trades, 64% wins, +11.2R. It armed **4198.76 / 4148.50 and is LONG today**, matching the EA's shadow levels (4198.71 / 4148.44 on AAAFx) to within cents. **The two independent builds agree.**

## EURUSD / GBPUSD (2026-10-12, Adam: "Try test on gbpusd and eurusd as well")
Same rules, replay (`stg\trendscalper\asia_fx.py`, 2020–26, 50-seed coin flip). **Both fail; it's a gold-only edge**, which matches the Aurum author's own report (PF 0.84–1.05 off gold):
| Market | Trades | R | PF | Years + | Beats coin |
|---|---|---|---|---|---|
| EURUSD | 1,710 | −118.9 | 0.86 | 1/7 | 32% |
| GBPUSD | 1,719 | −36.5 | 0.96 | 3/7 | 62% |
No MT5 run, because a loser needs no second engine, and an MT5 run would have killed the shadow terminal.

**All other markets (2026-10-12 ~11:12 PM, Adam: "Figure out what works and build an ea from that"):** the same rules, unchanged, on 10 more markets (`asia_breakout_markets_research.py`; pass also requires both sides positive). **0 of 10 pass:**
| Market | R | PF | Years + | Beats coin |
|---|---|---|---|---|
| USDJPY | +7.7 | 1.01 | 4/7 | 100% |
| AUDUSD | +0.5 | 1.00 | 4/7 | 68% |
| USDCAD | −79.2 | 0.90 | 2/7 | 32% |
| AUDJPY | −55.5 | 0.90 | 3/7 | 80% |
| NAS100 | −4.3 | 0.99 | 3/5 | 64% |
| US30 | −75.6 | 0.86 | 0/5 | 4% |
| SPX500 | −44.3 | 0.92 | 1/5 | 32% |
| GER30 | +21.6 | 1.04 | 3/5 | 100% (longs only +35R; 2026 −26R) |
| UK100 | −105.1 | 0.85 | 1/7 | 22% |
| JPN225 | −19.3 | 0.91 | 1/5 | 28% |

**The Asian-range breakout is a gold-specific edge** (as the Aurum author said). Gold is the market whose Asian session is a real quiet build-up that London/NY then break. No new legs.

## Scalp variants (2026-10-12, Adam: "Make me best scalper ea for gold"): all FAIL
Pre-registered, 3 cells (`stg\trendscalper\asia_scalp.py`; `asia()` gained `tpR` / `hold` params). Same entries and stop, smaller or faster exits:
| Cell | Trades | R | PF | Win % | Years + | Beats coin |
|---|---|---|---|---|---|---|
| S1 TP 0.5R | 1,607 | +6.3 | 1.01 | 64% | 3/7 | 100% |
| S2 TP 0.3R | 1,607 | −9.1 | 0.98 | 74% | 3/7 | 98% |
| S3 TP 0.5R, max 2 h | 1,607 | −13.8 | 0.96 | 53% | 3/7 | 96% |

**Read:** the direction still beats the coin flip, but **the edge lives in the follow-through to 1R.** Cutting winners short trades it for a higher win rate while the spread and the full-size losers stay. **The 1R version is the best gold scalper we can evidence.** It holds for hours, not seconds, and no separate scalper EA was built.

## Evidence
**Replay** (`gold_breakout_research.py`, 2020-01 → 2026-10): 1,607 trades, +74.2R, PF 1.12, 53% wins, 6/7 years. **Beat the coin flip 100%** (coin median −57R). Shorts (+40.4R, PF 1.14) earn as much as longs (+33.8R, PF 1.10), so it isn't gold's uptrend doing the work.

**MT5 tester** (`stg\trendscalper\gayears.py`, 1-min OHLC, $10k, 0.01 fixed):

| Year | Net | PF | Trades | Win % | Equity DD | Replay R |
|---|---|---|---|---|---|---|
| 2020 | +$101 | 1.11 | 223 | 55% | 1.3% | +2.6 |
| 2021 | −$42 | 0.95 | 252 | 46% | 1.7% | −12.3 |
| 2022 | +$42 | 1.05 | 237 | 49% | 0.7% | +1.8 |
| 2023 | +$37 | 1.05 | 244 | 51% | 1.3% | +8.6 |
| 2024 | +$380 | 1.39 | 244 | 57% | 1.4% | +22.5 |
| 2025 | +$772 | 1.50 | 220 | 55% | 2.6% | +20.5 |
| 2026 to 10-10 | +$1,364 | 1.64 | 176 | 61% | 2.4% | +30.5 |
| **2020–26 single run** | **+$2,683** | **1.33** | **1,600** | 53% | **2.6%** | +74.2 |

**Read:**
- **The two engines agree:** 1,600 vs 1,607 trades, the same losing year (2021), and the same thin 2022–23.
- **The edge is thin in quiet years** (PF ~1.05 in 2021–23) and strong when gold is volatile (2024–26). In dollars, part of the later-year size is fixed 0.01 on a doubled price.
- **Open risks:** the 1-min OHLC model fills stop orders at the exact price, so live slippage on a breakout costs something. Every-tick and a demo forward run come before real money.
- **Risk per trade at 0.01 = the stop in dollars** (1.1 × the range). Median by year: $7–11 in 2020–24, **$25 in 2025, $47 in 2026**. At today's gold, 0.01 needs about $4.7k to keep a median trade at 1% risk, or about $2.4k at 2%.

## Related
[[Gold EA Market Survey]] · [[TWI Gold Breakout]] (the H4 swing companion) · [[EA Scorecard]] · [[TWI ORB Momentum]] (the other session-break pass)
