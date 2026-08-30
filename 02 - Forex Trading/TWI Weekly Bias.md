---
status: active
project: forex-trading
type: reference
---
# TWI Weekly Bias

TradingView Pine v6 indicator (script id `USER;ea6433d9f8554e73a1793e5149adf988`, shorttitle "TWI WkBias") — a "buy the week or sell the week" dashboard, built 2026-08-25 from a real, sourced ICT/SMC framework Adam found in a trading-education video (SMC + Volume Profile, weekly liquidity-sweep bias). See [[Malaysian SNR x Orderflow]] for the real Pine Editor tooling breakdown and working fallback method this build had to use.

## What it does
One clean verdict up top — **BUY WEEK / SELL WEEK / LEAN BUY / LEAN SELL / WAIT** — built from three layers, each shown in the dashboard for anyone who wants the detail:

1. **Weekly bias (liquidity sweep):** tracks the previous week's high/low; if price sweeps below the prior week's low and closes back above it, bias flips Bullish ("Swept W Low"); sweep-and-reclaim the prior week's high the same way flips it Bearish ("Swept W High"). This is the actual ICT "AMD" (Accumulation/Manipulation/Distribution) mechanism, not invented logic — matches exactly what Adam's source video showed.
2. **Daily bias (close-based break):** close above/below the previous day's high/low, same "Close > Prev D High" / "Close < Prev D Low" phrasing as the video.
3. **Market structure (BOS/CHoCH):** multi-timeframe (H4 + a configurable LTF, default 1H) pivot-based structure break detection via `request.security`, reporting Direction + "Confirmed Shift" stage — same skeleton as [[TWI True North]]'s BOS/CHoCH logic, applied at two fixed timeframes here instead of one.
4. **Volume Profile POC:** rolling-lookback (default 50 bars) volume-weighted price-bucket POC, same bucketed-volume technique as [[TWI Scalp POC]], plotted as a line.

**Verdict logic:** Weekly direction is the anchor. If Daily and H4 both agree with the weekly sweep direction (all three same sign), verdict is the strong call (BUY WEEK / SELL WEEK). If weekly has a direction but the others don't fully agree, verdict softens to LEAN BUY / LEAN SELL. If weekly is still "Forming" (no sweep yet this week), verdict is WAIT.

## Design intent
Adam's ask was explicit: "easy to understand." Deliberately built as a single big-picture verdict rather than a wall of confluence rows guests have to interpret themselves — the supporting Weekly/Daily/H4/LTF/POC rows exist for anyone who wants to check the verdict's work, not as the primary readout.

## Status
Compiled clean (0 errors), added to chart, and verified against real live data on FX:GBPJPY — first real pull showed `TWI Weekly Bias: LEAN SELL | Weekly: Bearish (Swept W High) | Daily: Bullish (Close > Prev D High) | H4: Bullish (Confirmed Shift) | LTF: Bullish (Confirmed Shift) | POC: 217.366`, a coherent, sane read (weekly disagreeing with daily/H4 correctly produced a LEAN call, not a false strong call). Not yet run on gold or over any real sample size — one live snapshot, not a backtest.

## Update 2026-08-25 — v2: order blocks, buy/sell signals, compact mobile dashboard
Adam's feedback on v1 was direct and specific: *"no order blocks plotted no buy and sell I don't get how to use this and dash board way to big for mobile fix please."* v1 only had reference lines + a 6-row dashboard table — no way to actually act on it. Rebuilt same day:

- **Order blocks:** on a local (chart-timeframe) structure break — a close crossing the last swing pivot high/low, pivot length configurable (`pivLenLocal`, default 5) — the script scans back up to `obLookback` bars (default 15) for the most recent opposite-colored candle and draws it as a box (`box.new`, extends `obExtend` bars forward, default 25), blue for bullish OBs, orange for bearish. Verified live: **33 order block boxes drawn** on the first real chart check, visibly plotted with "OB" labels.
- **Buy/sell signals:** same local structure break drives `plotshape` triangles — green BUY below-bar, red SELL above-bar — gated by `requireWeeklyAgree` (default on: only signals that don't contradict the weekly bias fire, so it's not spamming signals against its own weekly call). Verified live: green BUY triangles fired and rendered on the chart.
- **Compact mobile dashboard:** new `compactDash` toggle (default on) collapses the dashboard from 6 rows to 2 — `WkBias | <verdict>` and `Detail | W▲ D▼ H4▲ L▼` (arrow-glyph shorthand for weekly/daily/H4/LTF direction) — plus a `dashPos` input to relocate it (default top-left). Verified live: dashboard rendered exactly as `WkBias | LEAN SELL` / `Detail | W▼ D▲ H4▲ L▲`, both rows fitting easily on a mobile screen width.
- Full uncompacted dashboard (original 6-row Weekly/Daily/H4/LTF/POC breakdown) still available by turning `compactDash` off — nothing removed, just made optional.

**Injection note:** the normal `pine_set_source`/`pine_smart_compile` tool path was still down (same outage as v1 — see [[Malaysian SNR x Orderflow]]), so v2 was injected via the same clipboard-paste fallback. This version's source has non-ASCII arrow glyphs (▲▼–) in it, which required switching from plain `atob()` to UTF-8-safe decoding (`TextDecoder('utf-8')` over the raw bytes) — plain `atob()` would have corrupted those characters. Worth remembering for any future indicator with non-ASCII characters injected this way.

## Update 2026-08-25 (later same day) — dashboard position fix
Adam shared real mobile screenshots (XAUUSD 15m) confirming order blocks, POC line, and buy/sell triangles all rendering correctly on his phone — but the dashboard (`dashPos` default `top_left`) was sitting directly behind TradingView's own symbol legend ("Gold Spot / U.S. Dollar"), hiding most of the compact readout — only "H4▲ L▼" was visible, the rest covered. Changed the default to `bottom_left` and re-injected/recompiled (same clipboard-paste fallback, same script id, same study — no duplicate created). Verified via screenshot on FX:GBPJPY: dashboard now sits clear in the bottom-left, no longer covered by any TradingView chrome (only slightly touches TradingView's own logo watermark, not a functional element).

## Open items
- Not backtested — no sense yet of how often the weekly sweep call, or the new buy/sell signals, are actually right.
- H4/LTF timeframes are fixed defaults (4H / 1H) — not yet tuned per instrument.
- Order block / signal pivot length (`pivLenLocal`, default 5) not yet tuned — untested whether 5 is too tight/loose for GBPJPY's typical noise.
- Not yet compared against [[TWI True North]]'s existing BOS/CHoCH logic for consistency between the two indicators.
