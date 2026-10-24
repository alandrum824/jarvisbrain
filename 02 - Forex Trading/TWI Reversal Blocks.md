---
status: active
project: forex-trading
type: indicator
---
# TWI Reversal Blocks (TWI-RB)

Pine v6 indicator built 2026-10-22 from 5 video screenshots Adam sent (a gold 5m trader, OANDA XAUUSD, Mon 27 Jul '26): "I want an indicator that marks out these blocks". Adam approved the rules below ("Yes").

**Status (2026-10-23 ~6:10 PM PT): v3 live** (TradingView v8.0): M15 protected zones on the chart plus the third-return watch. The v2 notes below are history.
- TradingView script "TWI Reversal Blocks", id `USER;649279259270423786d487adb8bf5f60`. Saved over v1; TradingView keeps v1 in its version history, and git commit 3f7b9b9 has the v1 `.pine`.
- Server compile 0/0. Running on Adam's chart (TradingView pine version 4.0).
- Visual only: no tap circles. The alerts are "new zone" and "zone touched" notifications.
- **The v1 backtests below test the v1 rules.** At default settings, v2 makes nearly the same zones (see v2 below), so the verdict stands: a map for Adam's discretion, not a signal.

Source: `TWI Reversal Blocks.pine` in this folder. Backtest: `reversal_blocks_research.py`, which uses the same block rules.

## The model (from the video)
Price runs an old high, can't hold above it and drops hard. The block over that failed high is where price "has no reason" to go again. The first tap back into it is the reversal. A high that only pulled back and kept going gets no block ("no point to mark that area").

## Rules (sell side; buys mirror on swept lows)
1. **Old high:** a swing high, 5 candles each side (input). It counts as liquidity until price trades through it.
2. **Sweep:** a new swing high whose up-leg (from the last swing low) traded through an old high formed before that leg.
3. **Rejection:** a close below the leg's starting low, with no high above the sweep high first. 100 bars max.
4. **Block:** from the sweep high down to the swept old high, or to the sweep candle's body top if lower. Tag: "No reason for this high to get taken". Newest 3 per side stay live.
5. **Tap:** the first touch back into a live block puts a circle on the candle and fires an alert ("Reversal Block Tap - sell / buy / any").
6. **Broken:** a close through the far side turns the block grey and stops it extending.

## Backtest (2026-10-22, AAAFx gold M1 2020-01 → 2026-10)
`reversal_blocks_research.py`: same block rules as the Pine; M5 P5 (primary), M5 P3, M15 P5.
- **Trade:** a limit at the block's near edge on the first touch after confirmation, with the stop at the far edge. A touch on a breaking bar still counts.
- **Exits:** 1R, 2R, or the broken leg low.
- **Costs:** bar spread + 6 pt. One position at a time.
- **Control:** coin flip, 50 seeds.
- **Pass bar (pre-registered):** ≥5/7 years, PF ≥ 1.15, beats ≥95% of coins.

| Bars | Exit | Trades | Net R | PF | Win | Years + |
|---|---|---|---|---|---|---|
| M5 P5 | 1R | 7,350 | −798.5 | 0.78 | 38% | 0/7 |
| M5 P5 | 2R | 6,707 | −929.3 | 0.78 | 24% | 0/7 |
| M5 P5 | leg low | 7,113 | −1,280.4 | 0.71 | 23% | 0/7 |
| M5 P3 | 2R | 9,930 | −1,378.2 | 0.77 | 23% | 0/7 |
| M15 P5 | 1R | 2,447 | −127.3 | 0.89 | 44% | 1/7 |
| M15 P5 | 2R | 2,266 | −105.5 | 0.93 | 30% | 2/7 |
| M15 P5 | leg low | 2,393 | −295.3 | 0.81 | 27% | 0/7 |

**None pass.**
- **Why it fails:** the blocks are tiny. The median M5 block is 1.3 points tall, so the spread is a big slice of every stop.
- **Before costs there is a small real edge:** M5 2R is +407.8R (+0.061R/trade), M15 2R is +107.3R. Every cell also beats 100% of the coin runs. The blocks do point the right way slightly more often than chance, but not by enough to pay the spread.
- **By stop size** (M5 2R, after costs):
  - under 1 point: −0.231R/trade;
  - 2–4 points: −0.030;
  - 4+ points: −0.044.
- On M15, blocks over 4 points are **+40.6R over 759 trades, 4/7 years**. That's found after the fact, not a pass. Lead only.
- **The video's own day (07-27):** the replay finds the main block at 4094.92–4106.03 (sweep 03:25 NY). It only confirms at 08:20 NY, because "close below the leg start" waited for the later sell-off. So the video's tap is not counted. The video trader marks the block right after the first drop, which is looser than our rule.

## MT5 EA test (2026-10-22; Adam: "Test it as ea now")
`TWI Reversal Blocks EA.mq5` (this folder), terminal copy `MQL5\Experts\Advisors\TWIReversalBlocksEA.mq5`, v1.00, compiled 0/0.
- **Tester only:** OnInit refuses to run outside the strategy tester, because the replay failed.
- **Engine:** the same block engine as the Pine and the replay, on `SignalTF` bars (M5 default).
- **Orders:** while flat, a limit sits at every live block's near edge, with SL at the far edge and TP at 1R, 2R or the leg level. When a position opens, all other orders are pulled. A touch while in a trade uses that block up. Max hold 48 h.
- **Summary line:** "LIVE/TEST: trades … R … PF … | year:R".

Runner: `C:\Users\aland\stg\obh\rbea_mt5_runs.py`. XAUUSD M1, 1-min OHLC (limit entries fill at their price), $100k, 0.1 lots, yearly windows 2020–2026. Outputs: `rbea_runs.out` and `rbea_runs_h4.out`. R per year comes from the EA's summary line (MT5 vs replay):

| Config | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 | Total | Replay |
|---|---|---|---|---|---|---|---|---|---|
| M5 P5 2R | −68.3 | −138.3 | −239.0 | −211.7 | −191.7 | −94.0 | −71.6 | **6,085 tr, −1,014.6R, 0/7** | −929.3R |
| M15 P5 2R | +18.7 | −2.3 | −67.6 | −38.7 | −47.4 | −28.5 | −29.9 | **2,166 tr, −195.7R, 1/7** | −105.5R |
| M15 2R, blocks ≥ 4 pt (the replay lead) | +7.2 | +13.3 | −11.1 | +9.1 | −3.0 | +2.4 | −11.9 | **760 tr, +6.0R, 4/7, +0.008R/tr** | +40.6R |

**MT5 confirms the replay: no edge.**
- **M5** is within ~9% of the replay, losing every year.
- **M15** loses in R. In dollars at fixed 0.1 lots it is about +$2,240, but only because the tall blocks risk more dollars per trade. Per unit of risk it loses.
- **The ≥4-point lead is flat in MT5** (+6R over 760 trades), so it's not a pass. A fixed 4-point floor also lets in more trades as the gold price rises (2025–26: 185 and 211 trades vs ~70 a year before).
- **Verdict:** keep the indicator as a chart map only. There's no EA to build from it.
- The tester runs closed the live terminal from ~17:00 to 17:40 PT. It was relaunched plainly and both shadow EAs (gold Asia, NAS100 ORB) logged "loaded successfully" at 17:40:21.

## Adam's live trade + GBPUSD replay (2026-10-22 evening)
- **Adam's trade:** a manual GBPUSD M5 sell off a hand-drawn block (top ~1.34195, from the 22 Oct ~09:00 swept high, bottom ~1.34065). "It worked." Fills are confirmed from his MT5 history screenshot (see the hand-trade log below).
- **GBPUSD replay** (`reversal_blocks_fx.py`, same rules, costs and coin control as the gold run, 2020–26):

| Bars | Exit | Trades | Net R | PF | Win | Years + |
|---|---|---|---|---|---|---|
| M5 (median block 3.9 pips) | 1R | 7,957 | −486.7 | 0.87 | 40% | 1/7 |
| M5 | 2R | 7,333 | −633.0 | 0.86 | 26% | 1/7 |
| M15 (median 7.4 pips) | 1R | 2,759 | −195.7 | 0.86 | 42% | 2/7 |
| M15 | 2R | 2,608 | −186.6 | 0.89 | 28% | 1/7 |

- Stops of 10 pips or more are still negative (M5 1R −0.029R/trade; M15 −0.065).
- **Verdict:** it fails on GBPUSD as well. The mechanical rule doesn't hold up there either. Adam's hand-picked blocks are a different, discretionary filter, and only a log of his own trades can measure that.

## Third-touch entry (Adam's model, 2026-10-22)
**Adam's description:** after a big push down from the swept highs, price comes back to the block, makes a fake move down, and **the entry is the third touch**.

**Replay** (`reversal_blocks_nth_touch.py`, same blocks, costs and coin control):
- Entry on the 1st, 2nd or 3rd separate touch of the block's near edge.
- A new touch needs price to leave the block first. Two versions were run: any bar that misses the edge, or a move of at least one block height away (the "fake move").
- Exits at 1R or 2R.

**Results: all 48 cells fail.**

| Market | Touch | 1R | 2R |
|---|---|---|---|
| GBPUSD M5 | 1st / 3rd | −0.061 / −0.092 R/tr | −0.086 / −0.139 |
| GBPUSD M15 | 1st / 3rd | −0.071 / −0.076 | −0.072 / −0.058 (686 tr, −40R, 3/7) |
| Gold M5 | 1st / 3rd | −0.109 / −0.080 | −0.139 / −0.111 |
| Gold M15 | 1st / 3rd | −0.052 / −0.008 | −0.047 / **+0.022 (688 tr, +14.9R, PF 1.04, 3/7)** |

- Waiting for the 3rd touch cuts the number of trades (and so the total loss) by about two-thirds. On GBPUSD the result per trade doesn't get better.
- Gold M15 improves to roughly breakeven, but that is still not a pass.
- Requiring the one-block-height fake move makes it worse. On gold M15, 3rd touch 2R drops to −45R, worse than the coin flip half the time.
- Adam's hand-picked entries may still differ; the hand-trade log measures that.

## Hand-trade log (Adam's discretionary block trades)
The mechanical rule fails, so the open question is whether Adam's hand-picked blocks have an edge. Log every one: entry, stop, exit, R. About 30 trades are needed before judging it.

| # | Date (server) | Pair | Side | Block | Entry | Stop | Exit | Pips | R | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-23 05:04 close | GBPUSD M5 | sell, 2 × 0.2 (3rd touch) | 1.34065–1.34195 | 1.34050 / 1.34054 | block top ~1.34195 (Adam confirmed; 14.5 / 14.1 pips) | 1.33938 | +11.2 / +11.6 | +0.77 / +0.82 | MT5 history screenshot |
| 2 | 2026-10-23 (open at 02:36 PT) | AUDUSD M5 | sell, 2 × 0.35 (later taps) | ~0.7019–0.70245, drawn by the TWI-RB indicator (Adam's TradingView screenshot) | 0.70215 / 0.70203 | just above the block top (~0.7025, Adam: "Above the block"; ~3.5 / ~4.7 pips); trailed to 0.70191 (in profit) | open, TP 0.70069 | +7.4 / +6.2 floating (closes at the ask 0.70141) | open; TP ≈ +4R / +2.9R, stop now locks ≈ +0.7R / +0.3R | chart screenshot |

## Trailing stop (Adam: "Add trailing stop loss", 2026-10-22)
`reversal_blocks_trailing.py`, 1st-touch block entries, no fixed TP. Variants:
- At +A R, move the stop to breakeven, then trail G R behind the best price (A = 0.5 / 1 / 1.5; G = 0.3 / 0.5 / 0.75 / 1).
- Classic trail 1R from entry, and breakeven + 2R TP.

**Result: all 36 cells (GBPUSD, EURUSD, gold; M5 and M15) are negative.**
- Best: EURUSD M15 BE@1R trail 0.3R, −94.6R, 3/7.
- GBPUSD M5 BE@1R trail 0.5R: −705R, 1/7.
- Gold M5: about −1,000R in every variant.

**Bug caught:** the first pass showed GBPUSD M5 at +458R, 6/7 years. That came from counting the fill minute's high/low (partly *before* the limit filled) as profit toward the breakeven trigger. With the fill minute excluded, it collapses to −705R. The fixed-TP sims allow a TP inside the fill minute, a smaller bias of the same kind (optimistic), and they still fail.

## v2: protected liquidity zones (built 2026-10-23, Adam: "Yes")
Built from another AI's spec that Adam pasted.

**v1 audit:** v1 already required a sweep. Its real gaps:
- no displacement size;
- any 5-bar swing counted as liquidity;
- no overlap check;
- the swept high wasn't shown;
- the box was backdated with no confirmation mark;
- it plotted tap circles.

**v2 rules (inputs in brackets):**
- **Liquidity:** a swing high with [5] candles each side. A sweep pivot uses [5].
- **Sweep:** the new swing high's up-leg trades through liquidity that was confirmed before the leg.
- **Confirmation, before price takes the sweep high:** a close at least [1.5] ATR(14) below the sweep high, plus [on] a close below the leg start (structure break), within [100] bars.
- **Zone:** sweep high down to the far edge [Swept level or body (wider)]. Other choices: Sweep candle body / Swept level / Origin candle (the last up candle).
- **One zone per area:** if it overlaps a live same-side zone by at least [20]%, only the more extreme sweep is kept.
- **Limits:** [3] per side; expire after [300] bars. Broken zones are hidden [off].
- **Marks:**
  - a dotted line at the swept high;
  - a short thick line at the sweep high;
  - a dotted vertical at the confirmation candle (the zone is created there; its left edge shows the sweep);
  - optional internal-high line [off].
- **No repaint:** a zone is created on its confirmation candle and only changes on a close through it or on expiry.

**Defaults changed after the first look:**
- Overlap 50 → 20%: the AUDUSD stack overlapped by only ~33%.
- Broken zones shown → hidden.

**Validation** (`reversal_blocks_v2_audit.py`): a Python port with an event log, run on the 300–318 bars loaded on the live charts. Its live zones match the Pine boxes on the chart; one GBPUSD M15 edge differs because the chart's history starts earlier.

| Chart (bars) | v1 zones made | v2 zones made | v2 live |
|---|---|---|---|
| AUDUSD M5 (10-22 11:30 → 10-23 13:55 PT) | 9 | 7 | 3 buy |
| GBPUSD M5 (10-22 13:00 → 10-23 13:55) | 6 | 6 | 2 sell + 1 buy (+1 older) |
| GBPUSD M15 (10-20 11:00 → 10-23 13:45) | 8 | 8 | 3 sell |

- **The 1.5 ATR displacement filter rejected nothing here.** By the time the leg start breaks, the move is already 2.3–7.5 ATR. Raising it to about 3 would start filtering.
- **Merging is what removes boxes.** AUDUSD sweeps 0.70202 and 0.70238 were merged into existing zones.
- **Most rejections:** price took the sweep high before confirming.
- **Adam's trade #2 zone:** AUDUSD SELL 0.70218–0.70238 (sweep 0.70238 at 10-22 18:45 PT took 0.70218) confirmed at 19:10 at 5.9 ATR, and broke with a close above at 10-23 05:20 PT.
- **Before/after screenshots** in `C:\Users\aland\tradingview-mcp\screenshots\`: `rb_v1_before_{GBPUSD_M15,GBPUSD_M5,AUDUSD_M5}.png` and `rb_v2_after_*.png`.

**Tool trap (banked in [[TradingView Chart Drawing]]):** `indicator_set_inputs` on this study wiped its inputs and broke it ("Can't parse pine"). Fixed by removing it and re-adding it from the editor.

## v3 request (2026-10-23 evening, built: see v3 below)
**Adam's spec:**
- Too many protected highs, some just lower highs.
- M15 zones should come first and show on M5, with M5 zones as an option.
- Frozen zones and one per event.
- A subtle "third-return watch" when price comes back to the first internal high after a fake selloff, firing on approach, not on a candle close.
- The protected high stays the invalidation.
- No repaint, and the confirmation time must be shown.
- Controls for sensitivity, displacement, structure break, lifespan and max zones.
- An audit of the 3 GBPUSD M5 sell boxes.
- Never mix up the external sweep (which makes the zone) with the internal sweep (his entry).

**Audit of the 3 GBPUSD M5 sell zones (v2):** chart bars plus M15 bars; strength = how many bars on each side the swept high stays the highest.

| Zone | Swept high (formed) | Strength M5 / M15 | Sweep | Displacement | Break | Verdict |
|---|---|---|---|---|---|---|
| 1.34066–1.34078 | 1.34072, 10-22 10:15 PT | — (before M5 data) / 30 left, 28 right | 17:35 PT, +0.6 pip | 13.8 ATR(M5) to 10-23 00:00 | close below leg start (M15 view: confirmed 21:15) | **Pass**: an established session high, swept |
| 1.33913–1.33946 | equal highs 1.33913, 21:45 and 22:40 PT | 10 / 2 | 23:20 PT, +3.3 pips | 11.7 ATR | 23:55 | **Fail**: a 1-hour internal double top inside the selloff from zone 1 (a lower high), not an established swing. Not a candidate on M15. |
| 1.3387–1.33885 | 1.33877, 10-23 01:30 PT | 18 left, 51 right / 6, 16 | 05:50 PT, +0.8 pip | 6.2 ATR | 10:05 | **Pass (weaker)**: a 4-hour-old M15 swing, swept, then a big drop. The M15 engine keeps it too. |

None of the three was ever traded through afterwards. The M15 engine removes the failing zone and keeps the two genuine ones, which is the evidence for item 2.

## v3: M15 zones + third-return watch (built 2026-10-23 evening, Adam: "Yes")
TradingView script version 8.0 (versions 5–7 were build steps). Server compile 0/0. On the chart, status calculated with no error.

**Changes:**
1. **Zone timeframe [15]:** the engine runs inside `request.security` on closed candles: values shifted one candle, `lookahead_on`, so nothing changes once printed. Zones are drawn by time on the chart. On a chart at or above the zone timeframe, the chart timeframe is used.
2. **Established-high strength [5 candles each side on the zone timeframe]:** this is what removes 5m-only swings.
3. **Chart-timeframe zones** [off]: dashed and faint, with their own max [2].
4. **Internal sweeps are not zones** [on]: a sweep that stays under a live zone's protected high, inside it or within the internal-high distance below it, is that zone's internal sweep (Adam's entry), not a new zone. Mirrored for lows.
5. **Frozen zones:** created once. They end only on a closed candle through the protected extreme, or after the lifespan [48 h]. Broken zones are removed; v3 has no grey option.
6. **Third-return watch on chart candles** (mirrored for buys):
   - **Internal high:** the first swing high [3 each side] after confirmation that is below the protected high and within [1.5 ATR] of the zone bottom. Drawn as a dotted line.
   - **Fake run:** a low at least [1.0 ATR] below the internal high.
   - **Return:** high ≥ internal high − [0.25 ATR]. A faint diamond plus alert, once per zone, on approach; no candle close needed. A sweep of the internal high is fine.
   - ATR is the chart timeframe's.
7. **Confirmation time** in the box label ("conf MM-dd HH:mm", PT) plus the dotted vertical.
8. **Alerts:** New protected zone; Third-return watch sell / buy / any.
9. **No tap circles.**

**Bugs caught during the build:**
- An `na` comparison made the first zone-timeframe zone never print. Fixed with `na(lastHB) or …`.
- The first v3 still drew the 5:35 PM sweep of 1.34072 as a zone. That was zone A's internal sweep, so the internal-sweep rule was added.
- The box reader (`data_get_pine_boxes`) can't read boxes placed by time. Read the lines instead: the study `_graphics._indexes` map line x values to chart bars.

**Validation (what the chart drew, times PT):**
- **GBPUSD M5:** two sell zones.
  - **A 1.34095–1.34192:**
    - The 01:15 10-22 M15 sweep of an older 1.34095 high (formed before the loaded history). Confirmed 03:00.
    - Internal high 1.34072 at 10:15. Fake run to 1.34006. Watch diamond at 10:55.
    - The internal sweep at 17:35 was *not* turned into a zone, and the big drop followed.
  - **C 1.3384–1.33885:** sweep 05:45 10-23 of 1.33877 (01:30), confirmed 10:15.
  - **Gone:** 1.33913–1.33946 (failed the audit) and 1.34064–1.34078 (internal sweep).
- **GBPUSD M15:**
  - Same zones A and C. Internal high 1.34072.
  - The watch on M15 fired at 17:30 10-22, right before the internal sweep. M15 swings and ATR are bigger, so it fires later than on M5.
  - 5 diamonds in the loaded history.
- **AUDUSD M5:**
  - Two buy zones live: 0.69942–0.69952 (older) and 0.7005–0.70124 (sweep about 22:00 10-22, confirmed 05:30 10-23).
  - No sell zones live: price rallied through them.
  - Sell watch diamonds at 08:50 10-22, 00:05 10-23 and 07:50 10-23. Their zones later broke and were removed, so the diamonds stand alone.
  - The 00:05 diamond is about an hour after Adam's trade #2 sells (~22:30–23:00 PT, read off his MT5 screenshot).

**Not tested:**
- chart-timeframe zones (off by default);
- "Origin candle" edge;
- alerts firing live;
- real-time (tick-by-tick) behaviour.

The market was closed during the build, so everything was checked on historical candles. Screenshots: `rb_v3_after_{GBPUSD_M5,GBPUSD_M15,AUDUSD_M5}.png` in the tradingview-mcp screenshots folder.

## Related
[[Liquidity Sweep Demand Zone]] (sweep → a different zone; failed on gold), [[EA Scorecard]], [[TradingView Chart Drawing]] (save method)
