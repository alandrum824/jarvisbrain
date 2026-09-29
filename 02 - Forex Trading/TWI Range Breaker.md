---
status: active
project: forex-trading
type: reference
---
# TWI Range Breaker

MQL5 EA built 2026-09-27 (~1 AM) from 5 phone frames Adam sent of a Facebook/Whop ad: **"Alphoryn Systems - Range Breaker (ORB)"**, a TradingView strategy shown on MNQ (Micro Nasdaq-100 futures) 3m. Adam: "Build this but EA mql5". Source: `TWI Range Breaker.mq5` (this folder).

**Status: compiled 0 errors / 0 warnings on the AAAFx terminal on the ADAM laptop (`MQL5\Experts\Advisors\TWIRangeBreaker.mq5`, byte-identical to the vault copy). Not attached. First 4 backtests run 2026-09-27: no edge, and the vendor's result doesn't reproduce (see below). One pending-order bug is open.**

## The vendor's claim (from the frames)

| Setting | 11:00–11:05 range (their headline) | 09:30 range (same video) |
|---|---|---|
| Net | +$22,975 (+45.95% on $50K) | −$690 (−1.38%) |
| PF | 2.689 | 0.986 |
| Wins | 84/104 (80.8%) | 67/115 (58.3%) |
| Max DD | 2.97% | 15.82% |

Their stats show 0% commission. Last 365 days, $50K account.

**Why it's not trusted (raised with Adam before the build):** the edge only exists at one start time chosen after the fact (the 9:30 run on the same tool loses); ~25 per-weekday settings tuned on 104 trades; longs only on the Nasdaq in a year it went straight up; TP 40 / SL 60 means you risk 1.5 to make 1, so the break-even win rate is 60%; and it's a paid product advertised on Facebook.

## Rules as built

All times are New York.
1. **Range:** the high/low of 11:00–11:05, read from closed M1 bars (so the EA works on any chart timeframe).
2. **Quality filter:** range size must be `QMin`–`QMax` % of price (vendor: 0.1–0.5%), or the day is skipped.
3. **Entry:** buy stop at the range high / sell stop at the low, with per-weekday long/short switches. If both sides are on, it's OCO. **One trade per day.** If price is already through the edge when the range closes, it enters at market unless price is already at the TP or stop. The alternative `ENTRY_CLOSE_BEYOND` enters at market on the first M1 close outside the range.
4. **TP / SL:** entry ± TP% / SL% of the range size (vendor: 40 / 60). The SL sits inside the range.
5. **Session end, 16:00:** pendings deleted, position flattened.
6. **Daily loss limit:** 2% of the day's starting equity (the vendor's $1,000 on $50K). When hit, pendings are deleted and the position is closed. It reads **account-wide equity**, so other EAs on the same account count toward it.
7. **Sizing:** `RiskPercent` (0.5%) via `OrderCalcProfit()`, not the vendor's fixed contracts. Sizing and R accounting are copied from [[TWI SMC POI]] v1.01 (R base frozen at the actual fill, net P/L sums every deal).
8. `MaxSpreadPoints` = 0 (off) until a symbol is chosen. Spread is logged on every entry.

**Defaults:** Monday and Tuesday match the frames (trade on, longs on, shorts off, 40/60, 0.1–0.5%). **Wednesday–Friday weren't visible in the frames; their defaults are copies of Monday, not the vendor's values.** `SessionStart` (09:30) is validated only; entries run from range end to session end.

## Time handling

- `TIME_NY_PLUS_7` (default): server = NY + 7h all year. AAAFx is UTC+3 in summer, which equals NY+7.
- `TIME_FIXED_UTC`: server = UTC + `ServerUTCOffsetHours`, with NY computed from a real US DST calendar.
- `ApplyUTC0History` (on): AAAFx broker history before the 2026-03-06 weekend is stored at **UTC+0** (proven from broker bars in [[XAUUSD Tick Data Infrastructure]]). Server times before `UTC0HistoryEnd` (2026.03.07 00:00) are treated as UTC.
- Winter months after the switch (Nov 2026 on) are unverified against real broker bars.

## Broker symbol: AAAFx NAS100 (checked 2026-09-27)

AAAFx offers **`NAS100`** ("NASDAQ -100 INDEX", `CFD Indices\NAS100`), one of 90 symbols. The other indices are US30, SPX500, GER30, UK100, JPN225, AUS200, FRA40, EUSTX50, ESP35, CHN50 and BUND. Specs were read live from the terminal by one-shot scripts (`MQL5\Scripts\TWISymbolDump` / `TWISymbolSpec`, results in `MQL5\Files\`):

- Price ~30,672, digits 1, point 0.1. **Spread 15 points = 1.5 index points** (a weekend quote; check it on a live session).
- Contract size 10. **Min lot 0.01, step 0.01. 1.00 lot = $10 per index point, so 0.01 = $0.10 per point** (from `OrderCalcProfit`). Min-lot margin is $6.13. Stops level is 0.
- **`SYMBOL_TRADE_TICK_VALUE` reads 0.1 per 0.1 tick ($1/pt per lot), 10x off from `OrderCalcProfit`** — the same kind of broken tick value as XAUUSD. The EA sizes from `OrderCalcProfit` only, so it's unaffected. Never trust tick value on this broker.
- Trades 01:00–00:00 server time Mon–Fri, which covers 11:00–16:00 NY. The server is UTC+3 (live check: server 11:17 vs GMT 08:17).

**Sizing reality on the live ~$370 account:** the range filter allows 0.1–0.5% of price (~31–153 index points), so the SL (60%) runs ~18–92 points, which is **$1.84–$9.20 at the 0.01 minimum lot**. 0.5% risk is ~$1.85, so the EA's overshoot ceiling would reject almost every day live. Fine for a $10K tester run; going live would take a higher RiskPercent or a bigger balance. That's Adam's call, not changed.

## First backtests (2026-09-27, ~1:20–1:31 AM)

**Setup:** AAAFx NAS100, M3 chart (the EA reads M1), **Model=1, "1 minute OHLC"** — not real ticks (real-tick history on this broker only covers recent weeks, and requesting it over a year silently falls back to synthetic ticks). $10,000, 1:100, 0.5% risk, vendor defaults (longs only, 40/60, 0.1–0.5%, Wed–Fri = Monday copy). Inputs passed via `[TesterInputs]` and confirmed in the tester's input dump. NAS100 M1 history begins 2024-01-01. Configs and reports are in the laptop terminal's `tester_configs\rangebreaker_v100_NAS100_M3_m1ohlc_<range>_<span>_20260927_0119.*`. The EA is deployed for testing as `MQL5\Experts\Advisors\TWIRangeBreaker` (the root-folder copy was removed).

| Range | Window | Trades | Win % | Net | PF | Total R | Max equity DD |
|---|---|---|---|---|---|---|---|
| **11:00–11:05** | 2025-09-27 → 2026-09-26 | 168 | 60.7% | +$62 | 1.02 | +1.3R | 7.1% |
| 09:30–09:35 | 2025-09-27 → 2026-09-26 | 182 | 62.6% | +$425 | 1.13 | +8.5R | 6.4% |
| **11:00–11:05** | 2024-09-27 → 2025-09-26 | 164 | 52.4% | −$974 | 0.73 | −20.7R | 10.5% |
| 09:30–09:35 | 2024-09-27 → 2025-09-26 | 193* | 59.9% | −$15* | 1.00 | −0.4R | 6.1% |

\*Report figures; the EA's own summary shows 192 trades / −$49 (see the bug below).

**Verdict: the vendor's curve does not reproduce. No edge.** Their 11:00 headline (PF 2.69, 81% wins) comes out at PF 1.02 on the same year here and PF 0.73 (−10% equity) on the year before. With TP 40 / SL 60 the break-even win rate is 60%, and every run sits within a few points of it. The per-weekday split flips between years (11:00 Tuesday: +11.6R last year, −12.3R the year before), which is exactly the noise that per-day tuning curve-fits. **Caveats:** a CFD rather than MNQ futures (the prices differ slightly), a 1-minute OHLC model, and the vendor's Wed–Fri settings are unknown.

**Time alignment verified from the data, not assumed:** the last tick of Fri 2025-09-26 is 20:59:59 server (17:00 NY close = 21:00 UTC, so history is UTC+0), and Fri 2026-09-25 ends 23:59:59 (UTC+3). The 9:30 NY range lands on 13:30 server in June 2025, which is correct at UTC+0/EDT.

### Gold (XAUUSD), same settings — Adam: "Try it on gold first" (~1:34–1:45 AM)

Same four configs on AAAFx XAUUSD (M1 history from 2023-12-21). Report figures match the EA's own summary in all four (no orphan trades). Reports: `tester_configsangebreaker_v100_XAUUSD_M3_m1ohlc_*_20260927_0134.*`.

| Range | Window | Trades | Win % | Net | PF | Total R | Max equity DD |
|---|---|---|---|---|---|---|---|
| **11:00–11:05** | 2025-09-27 → 2026-09-26 | 192 | 56.2% | −$640 | 0.84 | −12.9R | 8.6% |
| 09:30–09:35 | 2025-09-27 → 2026-09-26 | 208 | 58.2% | −$317 | 0.92 | −6.5R | 6.2% |
| **11:00–11:05** | 2024-09-27 → 2025-09-26 | 121 | 58.7% | −$156 | 0.93 | −3.0R | 5.8% |
| 09:30–09:35 | 2024-09-27 → 2025-09-26 | 186 | 60.8% | +$60 | 1.02 | +1.8R | 7.2% |

**Gold is worse than the Nasdaq: 3 of 4 runs lose, and the 11:00 range loses in both years.** Every win rate sits at or under the 60% break-even. In the older year, 121 of 261 days failed the 0.1% range-quality minimum (gold's 5-minute range was often under ~$2.60). The weekday pattern flips again (e.g. Wednesday −16.3R vs +0.6R).

## Bug found in the first run (reported, NOT fixed — needs Adam's OK)

**A pending order survived its cancellation and traded untracked.** On 2025-06-19 (Juneteenth, early close), no tick arrived before the 16:00 NY session end. The next tick was at 00:00 server with the market closed, so `OrderDelete` failed ("Market closed"), but `DeletePendings()` cleared the tickets anyway. The buy stop stayed live, filled on the 01:00 reopen and hit TP (+$33.75), and the EA's stats never saw it. Only this one run was affected: the report shows 193 trades / −$14.79, while the EA's summary shows 192 / −$48.54. **Proposed fix:** (1) only forget a ticket once the delete succeeds or the order is gone, and retry every tick until then; (2) give the stop orders a server-side expiry at the session end where the symbol allows it; (3) adopt and flatten any position of ours the state machine doesn't know about.

## Open

- [ ] The pending-order bug above (awaiting Adam's go).
- [ ] Not attached to any chart. Nothing live.

## Related

- [[TWI ORB Trend Retest]] — the 09:30–09:45 ORB retest indicator (Pine).
- [[TWI Sniper ORB]], [[TWI Gold ORB]], [[TWI PAT ORB SMART]] — earlier ORB EAs; none showed a stable edge.
