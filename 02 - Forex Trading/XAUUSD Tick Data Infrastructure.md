---
status: active
project: forex-trading
type: reference
---
# XAUUSD Tick Data Infrastructure

The data tracks behind the long-sample validation of [[TWI Liquidity Sweep OB EA]] (V1 code frozen). Approved by Adam 2026-09-23: **use both tracks.** Only infrastructure/data work; no strategy changes.

## Research hierarchy (never mix categories in one performance claim)
1. **AAAFx real ticks** → broker-specific validation / final confirmation.
2. **Dukascopy real ticks** → long-history strategy research / intrabar sequencing (MARKET DATA, not AAAFx execution).
3. **AAAFx M1 history + synthetic ticks** → funnel and signal-frequency research only.

## Track 0 — live AAAFx commission (DONE 2026-09-23)
Read-only history dump (`TWIDealAudit.mq5`) of account 8996721: **1,973 deals, $0 commission and $0 fee on every deal; XAUUSD 348 completed positions, $0 commission on both opening and closing deals.** AAAFx is spread-only here. Swap is the only extra cost (overnight). Details and sample positions: [[TWI Liquidity Sweep OB EA]].

## Track 1 — AAAFx real-tick archive (LIVE 2026-09-23)
- **Location:** `C:\Users\aland\OneDrive\Desktop\jarvis\data\AAAFx_XAUUSD_Ticks\`. OneDrive-backed and deliberately **outside the vault git repo** (hundreds of MB and growing). Its `README.md` is the full spec and runbook.
- **Contents so far:** Sept 11–22, 2026: 8 trading days, **7,322,947 ticks**, matching the Strategy Tester's count exactly. One gzip CSV per server day (`time_msc,bid,ask,last,volume,volume_real,flags`), `manifest.csv` with one row per calendar day (weekends marked, missing weekdays flagged `GAP`), and a SHA-256 round trip verified for each day. Validation: 0 negative spreads, 0 zero prices, 0 non-monotonic rows. Each day runs 01:00:00.4–.7 → 23:59:5x server time, and the max intra-day gap is 7.8–13.0 s. A native `.tkc` copy is in `native_mt5_cache/`. Size: about 43 MB of gz for 8 days (~5.4 MB/day).
- **Tools (sources in this folder):** `TWITickExport.mq5` (read-only script: CopyTicksRange per day → CSV, then closes the terminal) and `archive_ticks.py` (in the archive folder: validate → gzip → verify → manifest; idempotent; refuses to overwrite a day that differs).
- **KEY FACT, account spread markup:** the stored/exported feed is the **raw** server feed. The live account sees **bid −3 points / ask +3 points (+6 spread)**. Verified live (`TWISpreadLiveCheck.mq5`: live 52 vs stored 46 on every sample) and in the tester (every tick's spread = raw + 6, identical histograms). The tester on the real `XAUUSD` symbol applies it automatically, so V1's spread gate of 55 was calibrated on the true account spread. **Any replay from the archive outside that symbol must add ±3 points.** The archive files themselves are never altered.
- **Weekly process (manual, nothing scheduled):** once a week (Saturday), one export launch from the day after the last archived date → `archive_ticks.py` → check the manifest → copy the `.tkc` → clean up. Backoff: if the broker drops the connection or returns 0 ticks on a weekday, stop; wait at least 5 h and make one retry; never hammer. Full steps: the archive `README.md`.
- **Deadline logic:** the broker keeps about 8–11 trading days, so a weekly pull keeps the archive continuous. A missed week shows up as `GAP` rows and can't be recovered from AAAFx later.

## Track 2 — Dukascopy depth data (IN PROGRESS)
- **Location:** `C:\Users\aland\OneDrive\Desktop\jarvis\data\Dukascopy_XAUUSD\` (`duka_decode.py` decoder/validator, `duka_fetch.py` polite resumable downloader, `samples/`, `fetch_log.csv`).
- **Format (validated):** hourly `.bi5` = LZMA, 20-byte big-endian records (ms offset, ask, bid, ask vol, bid vol); UTC hours; month index is 0-based in the URL. **Price scale ÷1000 confirmed** against AAAFx's own M1 bars (Mar 10 AAAFx ~5,139; Dukascopy Mar 11 ~5,187).
- **1-hour sample (2026-03-11 10:00 UTC): PASSED.** 8,584 ticks, 0 non-monotonic, 0 outside-hour, 0 negative spreads, 0 zero prices, 0 trailing bytes, 3-decimal precision, max gap 11.2 s, 60 clean M1 bars, volumes present on every tick. Dukascopy spread median 0.640 ($0.64; ~64 AAAFx points), so it's wider than AAAFx raw. **Keep genuine Dukascopy spreads; never reshape them to AAAFx's.**
- **CLEAN DAY 2026-03-11: PASSED (2026-09-23).** Report: `clean_day_validation_2026-03-11.txt` (tool `clean_day_validate.py`). **23 valid hours + 1 genuine empty hour (21:00 UTC, HTTP 200 / 0 bytes), 0 missing, 0 malformed, 296,659 ticks, 0 non-monotonic across the whole day, 0 negative or zero spreads, 0 zero prices.** Spread (0.001 units): min 100, median 730, p95 790, p99 1154, max 10844, which is about 73 AAAFx points typical, wider than AAAFx. Largest market-hours gap is 33.5 s; the only bigger gap is the 1 h daily break. 1,380 reconstructed BID M1 bars, **exactly AAAFx's day length.** **Hour by hour vs AAAFx M1 at UTC+3: 60/60 bars matched in every hour** (59 in hour 01), with median |close diff| $0.23–0.40 per hour. The empty 21:00 UTC hour matches AAAFx's 00:00–01:00 server break (0 AAAFx bars there). Whole day: UTC+3 median $0.305 over 1,379 bars vs $6.5–9.7 for every other offset. The persistent ~$0.30 level difference is feed-to-feed (Dukascopy vs AAAFx pricing), not a time error. The download needed repeated 503/429 backoffs; nothing invalid was kept.
- **Timezone (validated on 5 hours):** AAAFx server = **UTC+3** on 2026-03-11 (median M1 close difference $0.27 at +3 vs $6–10 at other offsets). That's consistent with AAAFx following US DST (switched 2026-03-08), so **Jan → early March is probably UTC+2. Unverified; needs a winter sample.**
- **Rate limiting (hit 2026-09-23):** about 12 fast requests (1/s) triggered connection drops, then **HTTP 429 "Too Many Requests"**. Error bodies (113 bytes) are deleted, never kept as data. The downloader now waits 12 s per request with exponential backoff (60 s → 30 min cap). The 429 body points to Dukascopy's data-export instructions page, which hasn't been opened (external link; needs Adam's OK). A full Jan–Aug download is about 4,100 hourly files, so **~14+ hours at the polite rate**. It's a long background job, and only allowed after the clean-day validation passes.
- **Custom symbol plan:** `XAUUSD_DUKA_RESEARCH`, a separate MT5 custom symbol with genuine Dukascopy bid/ask. Never overwrite production `XAUUSD`. Contract conventions mapped for research only.

## Gates before the full Jan–Aug Dukascopy download (Adam, 2026-09-23)
Both must PASS first: (1) clean-day validation of 2026-03-11 (all 24 hours, hour-by-hour vs AAAFx M1), and (2) **the historical AAAFx server-time/DST regime, proven from broker history** (Jan, Feb, early March, late March, June, August, plus the exact transition date), not inferred from any DST calendar. Until then: no full download and no import. V1 stays frozen.

## Gate 2 progress — AAAFx server-time regime (2026-09-23 ~23:10 PT, from broker history)
Read directly from AAAFx's own M1 history (`AAAFx_M1_bars_2026-01-01_to_2026-08-31_servertime.csv`), by finding the daily 1-hour break:
- **Through Fri 2026-03-06:** the break is at **22:00–23:00** in the exported timestamps, which is gold's winter break in UTC. **tz_align on Dukascopy agrees: Jan 15 = UTC+0 (0.265 median, 34x confidence), Feb 18 = UTC+0 (0.255, 17x).**
- **From Mon 2026-03-09:** the break is at **00:00–01:00**, i.e. **UTC+3** (Mar 11 whole day: 0.305, 1,379 bars, 21.5x).
- **The switch sits inside the weekend closure** (last bar Fri 03-06 21:59 → next Mon 03-09 01:00), so no traded hour is ambiguous.
- **It's a 3-hour jump, not a DST hour.** The broker's history before Mar 9 is stored at UTC+0. So the offset table is `[.., 2026-03-06 22:00 UTC) → +0` and `[2026-03-06 22:00 UTC, ..) → +3`. It's from broker bars, not a DST calendar.
- **Still to confirm with Dukascopy:** 03-05, 03-09, late March, June and August (one 09:00 UTC hour each). The fetch was stopped mid-run when Adam redirected to a Pine indicator; `duka_fetch.py` resumes cleanly.

## Time handling design (Dukascopy UTC → AAAFx server time → V1 sessions)
- **Raw layer (immutable):** Dukascopy `.bi5` files and any decoded copies stay in **UTC**, unmodified.
- **Offset table (evidence layer):** `aaafx_offset_table.csv`, a list of `[from_utc, to_utc) → offset_hours` intervals **measured** from AAAFx history (`tz_align.py`: Dukascopy BID M1 vs AAAFx M1 closes per date). Each interval carries the dates that proved it. The transition instant is pinned to the market-closed gap where the measured offset changes, and a transition inside market hours is flagged, not guessed.
- **Derived/import layer only:** when building the MT5 custom symbol `XAUUSD_DUKA_RESEARCH`, each tick's server timestamp = `utc + offset(utc)` looked up in that table. It's a pure per-tick table lookup: no fixed +3 across the year, and no hindsight (the offset depends only on the tick's own UTC time). The custom symbol's ticks are then in AAAFx server time, so V1's `CurrentSession()` (08:00–11:00 / 13:00–17:00 server) classifies them exactly as it would on AAAFx.
- **Checks after import:** (a) spot-check that M1 bars built from the imported custom-symbol ticks line up with AAAFx M1 bars at offset 0 on every validation date; (b) the 1-hour ambiguity at a transition can't create duplicate or backward server timestamps (the transition sits in a market-closed window, and it gets verified).

## Spread handling (never mix feeds)
- **AAAFx:** raw archived feed spread (unchanged in the files) **+ observed account markup of 3 points per side (+6) = effective account spread** (≈46 + 6 = 52 points typical). The markup is documented, never written into the raw files. It's applied only where a replay needs the account's view (the real-symbol tester already does this).
- **Dukascopy:** authentic Dukascopy bid/ask and spread, kept exactly as delivered (≈0.64 median on the Mar 11 sample, roughly 64 AAAFx points). **Never reshaped to look like AAAFx.** Consequence: V1's `MaxSpreadPoints=55` gate would block most Dukascopy ticks. The research import must decide how the spread gate is treated (a research-only input override, documented), and that's an open decision for Adam, not an assumption.

## Related
- [[TWI Liquidity Sweep OB EA]] — the strategy this data serves (V1 frozen, MaxSpreadPoints 55)
- [[MBT (MT5 Backtest Toolkit)]] — tester gotchas (throttling, `.set` cache, heredoc trap)
- [[Active Priorities]]
