---
status: active
project: forex-trading
type: reference
---
# Gold EA Market Survey

2026-10-12, Adam: "Study goal learn gold charts look at gold EA's all over the Internet see which ones are successful and start work from there. Build me a EA" → "Gold". This note covers what the publicly successful gold EAs actually do and how their logic tests on our AAAFx data. The test lives in `gold_breakout_research.py` (this folder).

## What the market shows (web, 2026-10-12)
Every source is a vendor or reseller page. Myfxbook proves that the trades happened, not that they will repeat. Treat every number here as marketing until it is replayed.

| EA | Logic (as published) | Claimed record |
|---|---|---|
| **Gold Reaper** (Profalgo) | XAUUSD H1. Several sub-strategies break S/R levels over different lookbacks; hard SL; **trailing exit, no fixed TP**; mostly longs; no grid | Myfxbook +312%, max DD 15.2% (length not stated). Vendor says #1 on MQL5 for 7+ months |
| **Gold Trade Pro** (Profalgo) | Seven daily S/R breakout strategies | Myfxbook +169–198%, DD 12–15% |
| **Gold Breakout EA** (MQL5 code base 77691, free) | H4 close > 20-bar high, close > EMA200, buy at market, SL 2×ATR(20), TP 2R, longs only | Backtest 2020–26 (MetaQuotes demo): 198 trades, PF 1.77, DD 11.4%. Mostly 2024–25. With shorts on: PF 1.28 |
| **Aurum Range Breakout** | Asian range 00–05 GMT, OCO stops ±5% of width, SL other side, TP 1R, flat 16:00 GMT, range 0.1–0.8 daily ATR | Backtest 2021–26: 1,250 trades, PF 1.19, DD 9.5%. Author: fails on EURUSD/GBPUSD/USDJPY/BTC (PF 0.84–1.05) |
| **Goldie Razor V2** (pro-scalper.com/gold-eraser-v2; checked 2026-10-12 at Adam's request) | H1 rolling N-bar range, buy stop above / sell stop below (+10 pt buffer), OCO, all sessions toggleable; exits: "fast profit lock" within a few points, BE at +8 pts, retrace exit, trail, TP extensions; SL/TP values not given | **None.** No backtest, live signal or Myfxbook; price not stated (buy via Gmail). The entry is close to our passing breakout family, but the micro-exits are the small-win shape that failed every test |
| **Gold Scalper for MT5 ("Gold Scalper PRO")**, MQL5 #178437, Andrei Mikheev, FREE (checked 2026-10-12) | M1/M5 gold, entry logic undisclosed ("internal trading logic"), BE + trailing; says no grid/martingale. A reviewer saw TP 550010 / SL 10010 points | **None.** No backtest or live signal on the page. 4.5★ from 11 reviews, one unverified FTMO-pass claim and one failed backtest. Upsells a "Premium Set File" by private message; a reviewer flagged a hacked-account $47 offer. Seller notice (2026-07-23): products unavailable while the seller account is under review |
| **"Turkmen Gold Sniper Scalper" v16.30** (github.com/mad808/gold-scalper-mt5, open source, 6★; all 1,015 lines read 2026-10-12) | M5: EMA13 > 34 plus RSI ≤ 48 (ADX < 25) or ≤ 30 (trend) → 3 buys (sells mirrored); **martingale grid ×1.6, up to 8 levels**, ATR step $1.20–4.00 widening per level; basket trailing exit at +40 pts; **broker SL/TP = 0 on every order** (all exits are EA-side); $5 basket stop, 240-min time stop, 95% equity stop; AutoLot 0.01 per $60 | **None** ("educational"; README badge says "Martingale Grid", "$20 min deposit"). On ~$400, AutoLot = 0.06 × 3 = 0.18 lots, so the spread alone (~$6) exceeds the $5 basket stop the moment it enters. It would churn spread losses every signal. Rejected |
| **PFK Alpha EA V1.0 MT5** (yoforex.org post; checked 2026-10-12) | No strategy given ("cutting-edge algorithms"); "multiple pairs"; adjustable SL/TP, loss threshold; aimed at prop challenges | **None.** No developer named, no results, no risk warning. The title says "FREE DOWNLOAD" while the text says $75/month. YoForex is a redistribution site (several Drive EAs carry its tag) that pushes WhatsApp "custom AI bots". Not downloaded |
| **ATB 15m Gold Scalper** v1.08 (algotoolbox.com, freeware .ex5; checked 2026-10-12) | M15 gold: close crosses EMA 9 with RSI(14) on the same side of 50 → market order; SL = 4-bar extreme; TP ladder 50/30/20% at 1/2/3 × a 10-pt step, BE after TP1; optional loss-recovery lot increase | **Backtest only, 4 months** (2026-06-08 → 10-08, Exness cent): +246%, **PF 1.18, 39% balance DD, run with the recovery (lot-up-after-loss) mode ON**; the prose and screenshot disagree. Exness affiliate links. Same family as the M5/M15 EMA scalps that failed here. **The zip shared to Adam's Drive (2026-10-13, from another account)** has the locked .ex5 plus the "15m gold 10k ECN" set file: **loss recovery ON with no caps** (`InpUseRec=true`, +0.05 lot per loss on a 0.03 base, `RecCap=0`, `MaxMultLots=0`, no daily reset, persists across restarts), **daily loss limit off**, `MaxLot=0`, hedging allowed, spread guard 300 pts. Telegram screenshots showed the panel balance going from 9,211 (Sept 30) to 5,987 (Oct 12) cent, possibly the same account. Not installed |
| Golden Forex Scalping, "IS Best Gold", etc. | Scalpers / undisclosed | 70–150%/month claims, or "verified" labels on backtests. **Ignored as red flags** |

**The common thread:** the gold EAs that last are **breakout / trend-following on H1–H4, with long bias, wide ATR stops, and trailing or fixed-R exits**. None of them are M5 scalpers or zone fades. That matches our own [[EA Scorecard]]: gold scalps and zone fades fail, and gold trend only held on H4 longs ([[EMA Ribbon Trend Research]]).

**The trap:** gold went from about $1,500 to about $4,000 over 2020–26. Any long-biased system looks good on that. So the test adds a **DRIFT control** (random-time longs with the same stop and exit) next to the coin flip. A breakout has to beat simply being long gold.

## MQL5 market study: verified signals only (2026-10-12 ~11:50 PM, Adam: "study gold ea mlq5 and find a good one")
The rule: an MQL5 signal is broker-connected, so it's the only kind of result here that can't be typed in. Vendor pages, reviews and backtests don't count.
| EA | Live evidence | Verdict |
|---|---|---|
| **The Gold Reaper MT5** (Profalgo, product 111357, $949 or rent $399/3 mo; 4.49★, 116 reviews; v5.1, updated 2026-10-02) | **Signal 2265877:** XAUUSD only, started 2024-10-22 (**102 weeks**), **+354%**, 895 trades, 72% wins, **PF 2.33**, max balance DD 6.6% (relative 16.9%), equity DD 7.2%, avg hold 4 h, ~13 trades/week. Broker CapitalPointTrading, 1:500; real/demo not shown. **Caveat:** "80% of growth achieved within 31 days" of 711, so the profit is lumpy. Runs "30% max DD" settings | **Best candidate found.** H1 S/R breakouts via pending orders, SL + TP on every trade, no grid or martingale. The same family as our passing EA. Mixed reviews (one user drained in a month). Developer says backtests show up to 30% DD |
| Profalgo portfolio signal 2204998 (Gold Reaper + Gold Trade Pro + Daytrade Pro + others) | 215 weeks, +895%, but **26 symbols**, PF 1.16, balance DD 22%, monthly −6.3% at the time | Not a clean gold read |
| Quantum Emperor MT5 (Puscasu) | **GBPUSD**, not gold. It "divides the next position" to recover losing batches; a reviewer calls it a grid | Excluded |
| Quantum Queen MT5 (Puscasu, gold) | A third-party review calls it a trend-following **grid** with six strategies; no signal stats found | Excluded |
| AI Gold Sniper / AI Gold Trading | Buyers report big SL clusters vs the backtest; the author's real-account signal was wiped out | Excluded |
| Blodsalgo EAs (Growth/Pivot/Stability Killer) | Figures only on the vendor's own blog | Unverified |

**Next proof step (not done):** the Gold Reaper has a free MQL5 demo for the strategy tester. Running it 2020–26 on AAAFx gold would test the real EA on our broker's spreads, beside [[TWI Gold Asia Breakout]]. It needs the MQL5 Market download in the terminal (Adam's MQL5 login) and a tester slot after the shadow trade closes.

## Replay on our data (pre-registered, gold 2020-01 → 2026-10)
Five cells, rules copied from the published descriptions, 50-run controls. Summary: `stg\obh\gold_breakout_summary.csv`.

| Cell | Trades | R | PF | Years + | Beats coin | Beats DRIFT | Verdict |
|---|---|---|---|---|---|---|---|
| **DON_H4 LONG** (code base 77691 as published) | 195 | **+74.7** | **1.71** | 5/7 | 98% | 96% | **PASS** |
| DON_H4 BOTH | 317 | +48.7 | 1.25 | 4/7 | 96% | n/a | fail (years) |
| DON_H1T LONG (Profalgo-style 48-bar break + 3 ATR trail) | 447 | +58.1 | 1.27 | 4/7 | 98% | **32%** | fail: it's just gold drift |
| DON_H1T BOTH | 766 | +54.4 | 1.15 | 4/7 | 94% | n/a | fail |
| **ASIA BOTH** (Aurum rules as published) | 1,607 | **+74.2** | 1.12 | **6/7** | **100%** | n/a | **PASS** |

- **DON_H4 LONG** years: 2020 −1.0, 2021 −14.0, 2022 +1.0, 2023 +16.0, 2024 +29.0, 2025 +36.0, 2026 +7.7. It reproduces the author's own MetaQuotes backtest almost exactly (198 trades, PF 1.77 vs our 195, PF 1.71) on a different broker's data. 2022 is only just positive, and most of the R is from the 2024–25 bull run, but it still beats random longs taken in the same market (96%).
- **ASIA BOTH** years: 2020 +2.6, 2021 −12.3, 2022 +1.8, 2023 +8.6, 2024 +22.5, 2025 +20.5, 2026 +30.5. **Not drift:** shorts (738 trades, +40.4R, PF 1.14) earn more than longs (869, +33.8R, PF 1.10), and shorts carry 2022–23 when longs lose. Thin per trade (+0.046R), so cost-sensitive. It matches the author's report that 2022–23 were flat.
- **5 cells were tested, so about 0.25 false passes are expected at 95%.** Two passes, both with published outside backtests that agree, is meaningful. Both still need the MT5 second engine.
- **The two complement each other:** DON_H4 is a long-only swing trade (about 29 trades a year, multi-day holds); ASIA is a two-sided day trade (about 240 a year, flat by 16:00 GMT).

## MT5 second engine and the build (2026-10-12)
Both passes were built as EAs and run in the MT5 tester (1-min OHLC, $10k, 0.01, 2020–26):
- **[[TWI Gold Asia Breakout]]: PASSES.** 1,600 trades, PF 1.33, **6/7 years** (2021 −$42 is the only loss), equity DD 2.6%. It matches the replay trade for trade. **Our first gold EA to pass the scorecard.**
- **[[TWI Gold Breakout]] (H4 longs): lead only.** 188 trades, PF 1.50, +$1,683, but **4/7 years**. 2020–22 lose, 2023–26 win big. It's a trend-follower.

## Gold scalping-pattern mining (2026-10-12, Adam: "study gold patterned find a scalping pattern that works and make it an ea"): NONE found
Script: `gold_pattern_mining.py` (this folder). Results: `stg\obh\gold_pattern_mining.csv`. Pre-registered:
- **Data split:** discovery 2020–23, holdout 2024–26.
- **Measure:** returns in units of the 14-day ATR, net of spread + 6 pt markup, **minus the same-year long drift**.
- **90 cells, every hold ≤ 60 min:**
  - (A) the first 5/15-minute move at 5 events, continued or faded: Asia 19:00, London 03:00, COMEX 08:20, NY 09:30, 10:00.
  - (B) each NY hour, long or short.
  - (C) M5 shock bars (> 2.5 ATR, closing in the outer third), continued or faded.
- **Bar:** discovery |t| ≥ 3.2, then holdout t ≥ 2 and positive in 2024, 2025 and 2026.

**Result: 0 of 90 cells pass discovery, and 0 pass holdout.** The best discovery t was 2.45. Every open-move, hour-drift and shock-bar scalp is noise once spread and drift are removed.
- **The one tempting cell is a data artifact:** HOUR18 LONG (buy the 18:00 NY reopen, hold 60 min). It has holdout t 4.6 and is +$1.28/oz/trade at 18:00. **It vanishes at 18:05** (−$0.03/oz, 3/7 years) and stays dead at 18:15 and 18:30. The "edge" is the reopen print itself: a stale or illiquid first quote that live orders can't fill at, because reopen spreads blow out. It's also only measurable from 2022 (the earlier clock has no 18:00 bar). **Not tradable.**
- **Conclusion:** on AAAFx gold, short-hold patterns don't beat the 52-pt spread. The only gold intraday edge we have holds for hours: [[TWI Gold Asia Breakout]]. Its own scalp versions (0.5R / 0.3R / 2 h) fail too.

## Related
[[EA Scorecard]] · [[EMA Ribbon Trend Research]] · [[TWI ORB Momentum]] (gold failed there in MT5) · [[TWI Gold ORB]]
