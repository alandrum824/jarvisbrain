---
status: active
project: forex-trading
type: reference
---
# TWI EMA Ribbon

Pine v6 indicator built 2026-10-03 (~4 AM PT) on Adam's "Yes" to the build proposed in [[EMA Ribbon Trend Research]]: trend buy marks and "trend loosening" exits from a 6-EMA ribbon. Source: `TWI EMA Ribbon.pine` (vault master; functionally identical to the deployed script, the deployed copy has a shorter header comment).

**Status:** compiled 0 errors / 0 warnings (server check + editor). Saved as a NEW TradingView script via the banked Make-a-copy method: **"TWI EMA Ribbon", id `USER;e764afb5d2a44bb4ab1801607f38f761`**, script count 48 -> 49, and the script it was copied from (TWI fxalexg HS) kept its old modified timestamp. **Was on the desktop gold chart (entity `KtisaC`) until 2026-10-04, when I removed it to try to make room for [[TWI Manas Setup]]; it cannot be re-added** (TradingView Basic plan = 2 indicators per chart, the chart holds 3 of Adam's). The script is still saved. Alerts are written but none are created yet. Not published.

## Rules (same as the backtest)
- Ribbon = EMAs 8/13/21/34/55/89 (inputs). **BUY** when the ribbon first becomes fully stacked bullish (e1>e2>...>e6) with the close above e1. Entry is the NEXT bar open.
- Stop = 2.0 x ATR(14) (input). A bar touching the stop is scored -1R, also on the entry bar.
- **EXIT ("trend loosening")** when EMA8 crosses below EMA21 at the bar close.
- The bearish stack is NOT a short entry. It only turns the ribbon red. Optional research toggle tracks it as shorts (off by default; shorts lost in all 12 tested settings).
- Optional HTF gate (HTF close vs its EMA50, off, **untested**).
- Closed bars only; nothing repaints. Results are in R with an optional per-trade cost input (default 0).

## On the chart
Ribbon coloured by state (green = bull stack, red = bear stack, grey = mixed/loosening) with fills, BUY marks, EXIT/STOP labels showing the R, the open trade's stop line, and a 9-row table: state, long trades/win%, total/avg R, PF, open trade, shorts (research), **tested edge** (green only on gold), **timeframe warning** (red banner below H4), **history since** (date + bar count).

## First live read (2026-10-03)
- **XAUUSD H4 (OANDA, since 2023-01-02, 5,811 bars): 70 long trades, 42.9% win, +62.8R, avg +0.9R, PF 3.0.**
- **Same window in my MT5-data backtest: 134 trades, 33.6% win, +58.2R, PF 1.84** (by year 2023 +5R, 2024 +9R, 2025 +28R, 2026 +16R). The net R agrees; the trade counts differ because OANDA's H4 bars are cut at different hours than the broker's, which changes when the stack flips. Don't read the TradingView PF 3.0 as better than the backtest.
- The six-year MT5 figure (2020-2026: +69.5R, PF 1.50, 244 trades) is still the number to trust, and it is all buy side in a gold bull run (see [[EMA Ribbon Trend Research]]).
- **XAUUSD 30m, since 2026-01-01 only (8,934 bars): 98 trades, 29.6% win, +23.5R, PF 1.45** while the table shows the red "FAST TF" banner (**the banner is wrong for the buy side, see the correction in the next bullet**). That is nine months of gold's run; it conflicts with the 2.5-year MT5 test, where gold M15 lost -211R and H1 -42R. M30 itself was not tested. Treat the banner as the standing rule until a longer M30 test says otherwise.

## Caveats
- **Corrected 2026-10-03:** the banner and the "tested edge" row overstated the weakness. Long-only (the BUY marks) is positive on gold M15/M30/H1 (PF 1.2-1.5, thinner than H4's 2.3) and **USDJPY H1 (+145R, PF 1.54, steady in both halves)**; flat/negative on EURUSD/GBPUSD and silver. The earlier "loses" results included shorts. Pending Adam's OK: reword the banner (orange, thinner edge on lower timeframes) and the edge row, and add an optional "skip BUY when RSI >= 70" input. See [[EMA Ribbon Trend Research]].
- A 2 ATR stop on gold H4 is ~$80, so 0.01 lot risks ~27% of a $300 account (it breaks the 2% size gate).
- TradingView's history depth depends on the plan (this chart loads from 2023 on H4, from 2026 on 30m), so the table's numbers cover different spans on different timeframes; always read the "History since" row.

## Related
[[EMA Ribbon Trend Research]], [[Momentum Signal Suite]], [[TWI True North]], [[TradingView Chart Drawing]], [[Forex Trading]]
