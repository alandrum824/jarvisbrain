---
status: active
project: forex-trading
type: reference
---
# TWI ORB Trend Retest

TradingView Pine v6 indicator built 2026-09-24 (~2:00 AM PT) from five frames of a trading video Adam shared: "Trending markets (up trend) — aggressive buy entries", "top of the range entry after break", 5m entries inside 15m bullish structure, an 8.7-pip opening range, a 7-pip stop, an 18.9-pip "more aggressive target" (RR 2.7). The example was AUDUSD 5m on CMC Markets, 30 Apr 2026. Related family: [[TWI Sniper ORB]] and [[TWI PAT ORB SMART]] (EAs). This one is an indicator, not an EA.

## Rules (long; short mirrored)
1. **Trend:** 15m structure bullish = last confirmed 15m swing high > the previous one AND last swing low > the previous one (HH + HL). Read from the previous closed 15m bar (`request.security(... trendCalc()[1], lookahead_on)`), so no repaint.
2. **Opening range:** high/low of **09:30–09:45 New York** on the chart timeframe (5m = 3 candles). This is how the video's grey box and ORH/ORL read.
3. **Break:** a candle **closes** above ORH inside the entry window (09:45–12:00 NY).
4. **Entry:** "top of the range entry after break" = a **limit at ORH**, filled on the pullback from the next bar on. Option: enter at the breakout close.
5. **Stop:** ORL − 10% of range height. **Target:** 2.7R.
6. **Cancel:** a close back through the other side of the range ("failed break"); TP reached before the retest ("ran without retest"); no retest in 12 bars; window closed. **One trade per day.** Anything still open is closed at **16:00 NY** (flat-by).

All inputs are adjustable (sessions, timezone, trend TF/swing size, entry mode, long/short, SL buffer, RR, retest bars, table position). The table defaults to **bottom right** so it doesn't cover the legend (a lesson from TWI SMC POI on Adam's phone).

**Scoring is conservative (OHLC only):** a bar touching both SL and TP = loss; on the fill bar only the SL counts. There's no spread. Results are in R.

**Display:** grey OR box, yellow ORH/ORL, a TradingView-position-tool-style green/red TP/SL boxes from the break, BREAK UP/DOWN + limit price, BUY/SELL on fill, WIN/LOSS in R, grey boxes + reason on cancels. Table: state, 15m trend, breaks/filled, trades, win rate, total R, PF. **Alerts** (one "Any alert() function call" alert covers all): break + order levels, retest filled, exit.

## Build / deploy (2026-09-24)
- Vault source: `02 - Forex Trading/TWI ORB Trend Retest.pine`. **`pine_check`: 0 errors / 0 warnings**, and the checked source is byte-identical to the vault file.
- Saved as a NEW TradingView script **"TWI ORB Trend Retest", id `USER;2d857ec8e25a4fd78c94c8734ff7ad94`**, via Make-a-copy of TWI SMC POI, then source injected, then saved (footer "2 · Today, 02:19").
- **On the chart:** layout `uJnBMo6l` switched to **OANDA:XAUUSD 5m**. At the 2-indicator cap, **TWI SMC POI was removed from the chart** (it's the proven loser; still saved as a script) to make room. The chart now has TWI ORB Trend Retest + Sweep Reversal Map [Herman].

## First on-chart read (OANDA:XAUUSD 5m, loaded history, 2026-09-24 02:20 PT)
Breaks 11 → filled 9. **9 trades, 5 wins (55.6%), +1.14R, PF 1.29.** 15m trend at the time: DOWN.
- **Honest read:** 9 trades is nothing. Several "wins" are small flat-by-16:00 exits (+0.38R, +0.06R), which means the 2.7R target is rarely reached intraday on gold. It's worth watching whether a lower RR or a structure target does better. **It hasn't been tested on AUDUSD, the video's own pair.**

## Related
- [[TWI SMC POI]] — the previous build tonight (lost on 3 samples), which this replaced on the chart
- [[TWI Sniper ORB]], [[TWI PAT ORB SMART]], [[TWI Scalp Pro]] — ORB EAs
- [[Active Priorities]]
