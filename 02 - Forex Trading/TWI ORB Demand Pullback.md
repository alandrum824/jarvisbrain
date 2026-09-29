---
status: active
project: forex-trading
type: reference
---
# TWI ORB Demand Pullback

MQL5 EA built 2026-09-27 (~3:15 AM) from 4 frames of Pat's [[TWP ORB EA Reference|TradeWithPat]] stream ("Discretion Entry", M5) after Adam said the TWP EA "specially with grid has high drawdown and trades in wrong direction". He sent 2 MT5 phone screenshots of TWP grid sells stacking 0.20–0.25 lots into a straight-up EURUSD rally (−$114 floating) as the example. Source: `TWI ORB Demand Pullback.mq5` (this folder).

**Status: compiled 0 errors / 0 warnings on the laptop AAAFx terminal (`MQL5\Experts\Advisors\TWIORBDemandPullback.mq5`, byte-identical to the vault copy). Not attached anywhere. First backtests running.**

## Pat's model (from the slides)

1. An M5 candle **closes** above the range high.
2. A retest of the range high.
3. The breakout leg leaves a fair value gap.
4. The range midline.
5. The demand zone (or an iFVG) at the base of the move. **Enter there**, SL under the range low, a partial TP, then a runner.

The TWP EA can't do this in order: its closest modes (7 "Retest range level X", 8 "FVG and S&D") don't require the confirmed breakout. See the mode map in [[Build TWP Set Files]].

## Rules as built (long; short mirrors)

1. **Range:** NY `RangeStart` 09:30 for `RangeMinutes` 15, from M1 high/low.
2. **Breakout:** a closed `EntryTF` (M5) bar **closes** beyond the range. **Trend filter (on):** longs only if that close is above the EMA 200 on H1, shorts only below. A blocked break keeps waiting for a break in the trend direction.
3. **Retest (on):** a later bar trades back to the broken edge. A close back through the far side first cancels the day.
4. **FVG (on):** a bullish gap (`low[k-1] > high[k+1]`) somewhere from the demand candle to the bar after the breakout.
5. **Demand:** the last bearish candle at or before the lowest low between range start and the breakout (5-bar search). Zone = its body top down to the lower of the two lows. **Must be at/below the midline (on).**
- **Entry:** buy limit at the zone top (market if price is already in the zone).
- **SL:** below the lower of the range low and the zone low, minus 20 points.
- **Exits:** 50% partial at 1R and SL to break-even +5 points; runner TP at 3R. Flat at 16:00 NY.
- **Cancel:** a close back through the range low before the fill, or the 12:00 NY entry cutoff.
- **One trade per day. No grid, no martingale, no averaging.** 0.5% risk via `OrderCalcProfit`; 2% daily equity cap.
- **Order hygiene** (the lesson from [[TWI Range Breaker]]'s holiday bug): pending orders are only forgotten once the broker shows none left (retried every tick), and any stray order or position with our magic is cleaned up.

On a $400 account the lot is often too small to split 50/50 (0.01 minimum); then the partial is skipped, the stop still goes to break-even at 1R, and the summary counts it (`partials … skipped`).

## Results — first batch (2026-09-27, ~3:26–3:45 AM)

Every tick, $400, 1:100, all inputs passed via `[TesterInputs]`. Reports: laptop terminal `tester_configs\orbdemand_v100_<SYM>_M5_<variant>_everytick_<span>_20260927_0326.*`. Time alignment was checked in the log (09:30 NY = 16:30 server in March 2026). "Trades" here are report deals, so a partial close counts extra.

| EURUSD variant | 2026 (6.5 mo) | 2025–26 | 2024–25 |
|---|---|---|---|
| **Default (Pat's full model)** | −$22.28 PF 0.19 | −$8.33 PF 0.73 | −$16.20 PF 0.50 |
| No trend filter | −$18.57 PF 0.49 | +$0.29 PF 1.01 | −$33.01 PF 0.43 |
| 55-min range | −$8.82 PF 0.27 | −$1.30 PF 0.92 | −$5.55 PF 0.62 |
| No partial (3R runner only) | −$17.65 PF 0.48 | −$12.00 PF 0.72 | −$18.28 PF 0.53 |
| No FVG rule | −$20.38 PF 0.32 | −$11.23 PF 0.70 | −$29.27 PF 0.37 |
| No midline rule | −$25.75 PF 0.35 | −$8.42 PF 0.83 | −$31.49 PF 0.49 |

**Verdict: no edge on EURUSD in any variant.** Losses are small (DD 2–10%), and the risk plumbing works (one position, hard stops, no stray orders). The trend filter halves the 2024–25 loss but can't rescue the entry. Without the partial, only 17–22% of trades win; the 3R runner rarely gets there.

**XAUUSD default: untestable at $400.** Risk rejects of 47 / 75 / 60 (even 0.01 lot over the gold stop exceeds 0.5% × $400), leaving 0 / 3 / 14 trades (−$0 / −$2.60 / −$5.98). A gold verdict needs a bigger test balance (e.g. $10K).

Compare: the TWP EURUSD NYSE no-grid set made +$156 over the same 2.5 years ([[TWP24 EURUSD Sets]]).

## Re-check and diagnosis (2026-09-27, ~3:50–4:15 AM; Adam: "re check EA and think how to make it better but still active")

**Code re-check:** no logic bugs found. Traced real days: timing, trend blocks, FVG/midline skips, zone and SL geometry, and order hygiene all behave as specified.

**Where it loses (default, 3 windows):** a break happened on 512 of 665 days, but only **92 fills (14% of days)**. **53% of demand limits never filled** (cutoff), and **81 of 92 fills ended at the SL** (some after BE); only 6 reached 3R. That's classic **adverse selection**: a real breakout never pulls back to deep demand, while a failed one falls straight through it.

**Offline replay** (`orb_pullback_research.py` in this folder; EURUSD M1 from `TWIBarsExportTester`, NY-time converted with the proven AAAFx clock, 0.2-pip cost, SL-first when a bar hits both, EURUSD 09:30+15 range, one trade/day):
- **Retest limit at the broken edge, SL at the midline:** looked great at M5 granularity (positive every year and target), but **with strict M1 fills (the fill bar can only lose) the edge mostly vanished**: 2024–25 negative at every target; 2025–26 and 2026 small positives (+9R/+2.5R at 1R). Not robust. **Lesson banked: judge limit-order ideas with M1-precise fills; M5 fills credit targets hit before the order would have filled.**
- **Demand zone, blind limit (the EA's idea):** 2024–25 −23R at 1R / −39R at 3R; the others ~flat. It matches the EA's own backtests, which validates the replay.
- **Demand zone + Pat-style confirmation** (Adam: "he waits for breakout and returns to demand zone"; enter only after price trades into the zone and an M5 bar closes back out of it): fewer trades (21–39/yr) and still **−6 to −19R in 2024–25**, ~flat elsewhere. Confirmation doesn't rescue it.
- Trend filter: helps some cells, not consistently.

**Conclusion:** on AAAFx EURUSD at the 09:30 NY open, "break → return to demand" has no edge in 2.5 years, blind or confirmed. What does work on this pair/time is momentum at the edge: the TWP no-grid set (instant breakout, 55-min range, wide 2.2×range SL, 0.75×SL TP) made +$156. Gold (Pat's own example) is still untested at a usable balance.

## Pat's gold videos, replayed (2026-09-27, ~4:20–4:40 AM)

Adam sent two more sets of Pat frames: (a) a **liquidity-sweep short** on gold on 2026-06-19 (equal highs, spike above the zone at the NY open, then a run down to demand), and (b) **"Elite GOLD Trading Strategy in 40 seconds"**: mark the first 15-min candle's high/low at 09:30 NY, drop to M5, enter on the first M5 candle that breaks AND closes beyond it, SL back inside the range, TP ~1.5–2× risk.

- **The 06-19 example checks out on AAAFx:** high 4183.01 at 09:10 NY, then 4147.77 by 10:00 and 4142.34 at 10:46. His ~4150 target was reached in ~40 min. One cherry-picked winner, but real.
- **Replay** (`gold_orb_research.py` in this folder; AAAFx XAUUSD M1 2024-03 → 2026-09 exported with `TWIBarsExportTester`, 911k bars; clock verified by 126/129 Friday closes at 16:58–16:59 NY; $0.55 spread per trade, $0.30 SL buffer, SL-first on ties, one trade/day, entry by 12:00):
  - **G1, Pat's gold ORB (break-close entry):** **2024–25 loses in every variant** (−12 to −64R). 2025–26 is mostly negative (best: SL at the opposite edge, TP3 +16.9R). **2026 with the H1 EMA200 trend filter is positive** (SL mid: +11R @1R, +24R @3R; 74 trades). Not robust: one good year out of three.
  - **G2, sweep & reclaim fade** (wick beyond the range edge, close back inside, fade it; SL beyond the sweep): **2024–25 −21 to −60R**, 2025–26 ~flat to negative, 2026 mixed. Not robust.
- **Conclusion across today's work:** none of Pat's mechanical rules (ORB → demand pullback, retest, gold break-close, sweep fade) shows an edge across all three AAAFx years on EURUSD or gold. **The only thing positive in all three years was the TWP EURUSD NYSE no-grid set (momentum at the edge, wide SL, quick TP).**

## Pat's full "levels" model (2026-09-27, ~4:45–5:00 AM)

Adam sent the rest of the video: **Step 2 "Levels"**. The breakout must extend **≥70% of the range size** beyond the edge (a −70% Fib); then wait for the retrace. Level 1 = the **FVG** near the edge ("if it holds, push up into a trade"). If it breaks, level 2 = the **demand zone** at the base, with an "entry confirmation" (not shown in the frames), a **tight SL just under demand**, and **TP back at the extension high**.

Replay (`orb_extension_fvg_demand_research.py` in this folder; same data, costs and strict M1 rules as above; 09:30+15 range; the first M5 close beyond it; the 70% extension required before any close back through the far side; FVG = first gap in the impulse within 25% of the range from the edge; confirmation proxy = touch the level, then an M5 close back out of it in the trade direction):

| 1R target unless noted | 2024–25 | 2025–26 | 2026 |
|---|---|---|---|
| EURUSD FVG limit | −13R | −25R | −19R |
| EURUSD FVG hold-confirm | −5R | −3R | −2R (ext +3R) |
| EURUSD demand limit | −22R | +3R (3R +37R) | −9R |
| **EURUSD demand hold-confirm** | −8R | **+14R** (2R +26R) | −3R |
| Gold FVG limit | −26R | −34R (ext +9R) | −12R |
| Gold FVG hold-confirm | −10R | +1R | −1R |
| Gold demand limit | −12R | −1R | +4R |
| **Gold demand hold-confirm** | −10R | −9R | **+9R** |

The 70% filter kept ~70–75% of breakouts (EURUSD 192/255, 203/258, 111/144; gold 167/252, 171/248, 94/140). **Same pattern as every other Pat variant: one good year per market, and the other two negative.** EURUSD's demand-confirm is strong only in 2025–26; gold's only in 2026. Not robust enough to build an EA on. The unknown piece is Pat's own "entry confirmation"; a different trigger could change this, but nothing in the replays suggests it would rescue 2024–25.

## Pat's 3-phase framework + confluence filters (2026-09-27, ~5:00–5:20 AM)

Adam sent Pat's framework slides. **Phase 1 "One candle":** the 09:30 15-min candle, mark the range, then an M5 break AND close. **Phase 2 "Levels":** S/R on M5/M15/H1, analyze the range distance (Fib 70%), buy from support and sell from resistance. **Phase 3 "Trendlines":** draw trendlines, wait for a break, use the retest as the entry. Plus live examples: buying at a major H4/daily support at the 78.6–100% Fib of a large swing, range-bound S/R, and "unmitigated FVG acts as a magnet". Phases 1–2 are mechanizable; Phase 3 and the "pick the right one" level choice are discretionary.

Added to the same replay script (`orb_extension_fvg_demand_research.py`):
- **+S/R:** the entry level is within 0.2× range size of an H1 swing high/low (3 bars each side) confirmed in the prior 7 days. **No rescue:** trades cut 50–70%, same pattern (EURUSD demand-confirm −5 / +6 / −5R; gold demand-confirm −4 / −5 / +1R).
- **+HTF location:** longs only if the level is in the bottom 25% of the prior 20 days' range (shorts, the top 25%). **The only all-positive cell found in ~200:** EURUSD FVG hold-confirm at a 2R target, **+0.8 / +2.8 / +2.8R on 12 / 9 / 6 trades.** That's ~11 trades a year, far too few to trust, and out of this many cells one positive is what chance produces. Not evidence.

**Verdict on Pat's methods as a robot:** across ORB→demand, retest, gold break-close, sweep fade, the 70% extension with FVG/demand entries, S/R confluence and HTF location, **no mechanical version holds up in all three AAAFx years with a usable trade count.** His edge (where it exists) lives in discretionary level selection. The only all-years performer remains the TWP EURUSD NYSE no-grid momentum set.

## Every session + engulfing confirmation (2026-09-27, ~5:20–5:40 AM)

Adam sent Pat's "3 Step 9:30AM Candle" short: the **15-min candle at the beginning of EACH session**, "proper displacement", then the FVG or a **level of demand**, and the **entry confirmation = a bullish engulfing pattern** (the missing piece). The example was on the Nasdaq. Exported AAAFx NAS100 M1 (909k bars; clock verified by 126 Friday closes at 16:59 NY). Replay `session_orb_engulf_research.py` in this folder: sessions Asia 20:00 / London 03:00 / NY 09:30 NY time, 15-min range, first M5 close beyond it (entries until +2.5h, flat at +6.5h), 70% displacement required, then price returns to the FVG or demand and a **two-candle engulfing** closes in the trade direction → enter at the next open. SL beyond the engulf/level ± buffer; costs as before (NAS100 1.5 pts, 1.0-pt buffer).

**First result that holds across all 3 years on more than one market: Asia session, demand + engulfing.**
- EURUSD Asia DEM+engulf: +3.4 / +7.9 / +0.5R @1R; **+15.9 / +14.5 / +1.0R @2R**; +10.5 / +16.5 / +2.4R @3R (29 / 29 / 13 trades).
- NAS100 Asia DEM+engulf: +1.9 / +5.6 / +1.7R @1R; **+8.1 / +7.3 / +7.1R @2R** (27 / 19 / 12 trades).
- EURUSD Asia ANY-level+engulf: positive all 3 years @1R (+2.1 / +12.8 / +1.1R; 51 / 54 / 25 trades).
- Gold Asia DEM mixed (+1.4 / +0.8 / −3.1R @1R). London and NY on all markets: no consistent cell (gold NY −19R 2024–25; NAS100 London negative).
- **Caveats:** ~25–30 trades/yr per market; 2026 is thin; many cells were tested (≈108 per market). But the SAME config holding on two unrelated markets in all 3 years is much stronger than a single lucky cell. **Status: strong lead, not yet an EA.** Next step if pursued: a proper MT5 EA + tester confirmation.

## Pat's daily flipped-zone swing model (2026-09-27, ~12:00 PM; video "Once You Understand Price Action", USDCAD daily)

Rules: daily structure → break of the previous swing high/low (close) → the broken swing candle becomes the flipped zone → buy/sell the pullback into it, SL beyond the zone, TP 2.5R (or the extension high). Replay `daily_flipped_zone_research.py` (AAAFx M1 2020-01 → 2026-09, 6 markets; clock: **London time (UTC+0/+1 EU DST) before 2022-03-27**, UTC+0 to 2026-03-06, UTC+3 after, proven from Friday closes).
- 5 FX pairs, limit entry 2.5R: +8.8R over 665 trades, **2021 −30R, 2025 −24R**, max DD 52R. Pat's "invalid only on a close beneath" stop: −13.8R. Confirmation close: +28.8R, 5/7 years. Fib 50–83% filter: +16.7R, 6/7 years (2025 −12R). Engulfing + TP at the extension: +6.8R, max DD 6.4R, 5/7 years.
- Gold alone: best is TP at the extension, +15.4R, 5/7 years.
- **All 6 markets, confirmation entry: +42R over 700 trades (~100/yr), 5/7 years positive (2020 −19R, 2025 −4R), max DD 39R.**
- **Verdict: a thin, lumpy edge; not robust enough for an EA.** No variant is positive in every year with a usable trade count.

## STRIKE method (Abdo Karim / Elevate FX) replay (2026-09-27, ~12:30 PM)

Source: Adam's Instagram frames + the official "STRIKE NY Session Checklist" PDF. Rules: 4H swing S/R (2 bars each side, 30-day lookback) → at the NY session (09:00–12:00 NY) an M5 bar touches a level (±0.15× the average 4H range) and rejects it with a wick (>50% of the bar) → a higher low above the rejection low (short: a lower high) → enter the next open after the M5 close beyond the structure high → SL beyond the HL/LH + buffer → TP next 4H level; skip if RR < 3; flat 16:00. Script `strike_method_research.py` (this folder; needs `daily_flipped_zone_research.py` for the loader/clock). Data: AAAFx M1 (NAS100 only from 2022-03-28).

| Variant | NAS100 (2022–26) | Gold (2020–26) | EURUSD (2020–26) |
|---|---|---|---|
| As written (RR ≥ 3, TP next 4H) | +10.6R, 39 trades, 2/5 yrs | −13.8R, 1/7 | −6.8R, 2/7 |
| Hold to TP/SL | −15.0R | −10.3R | −6.0R |
| **No RR filter, TP next 4H** | **+50.9R, 491 trades, 60% win, DD 16.6R, 5/5 yrs +** | −94.2R, 0/7 | +4.1R, 4/7 |
| Fixed 2R | +48.3R, 3/5 | −71.7R | −1.6R |
| Fixed 3R | +66.1R, 3/5 (2022 −5.6, 2026 −6.2) | −69.2R | +16.7R, 5/7 |

**The claimed 80% / 5R does not reproduce as written** (29–33% wins, 39–84 trades in 5–7 years). **But one strong lead: NAS100, the STRIKE entry with the target at the next 4H level and no RR filter, is positive in all 5 years** (+2.3 / +5.0 / +21.6 / +15.5 / +6.5R; avg win 0.8R, i.e. many small wins). Gold fails badly in every variant. Next step if pursued: a real MT5 EA + tester confirmation on NAS100 (the min lot is 0.01 = $0.10/pt; check the stop sizes vs a $200 account).
