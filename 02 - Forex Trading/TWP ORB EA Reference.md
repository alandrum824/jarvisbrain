---
status: active
project: forex-trading
type: reference
---

# TWP ORB EA Reference

Captured from live config screenshots (TradeWithPat TWP ORB EA v1.13.1, EURUSD.b H1) on account 108.181.193.243, and from mobile history/chart on account D3101:81322. Source: Claude.ai chat session, screenshots dated 2026.07.16 (config) and 2026.08.04–05 (trade history).

## Strategy

Opening Range Breakout (ORB) on EURUSD. EA runs on 5-minute timeframe; range built during London session starting at custom 12:00 time, over 75 minutes. Entries sought for 115 minutes after the range window closes. Entry mode: Instant Retrace.

## Position Sizing

- **Lots mode:** Static
- **Lots/Risk:** 0.35
- No risk-based scaling — static lot size regardless of account balance.

## Stop Loss / Take Profit

- **SL mode:** ATR — value shows **0.0**
- **TP mode:** ATR — value shows **1.5**
- **ATR period:** 200, on 5-minute timeframe

⚠️ **Open question:** SL at 0.0 in ATR mode is either a real misconfiguration (no stop loss active) or the EA treats 0.0 as "use default ATR multiplier." Needs confirming with TradeWithPat docs or support before trusting this on a live account — a stop that isn't actually set is how accounts blow up.

## Grid System

- **Enable grid:** true
- **Trade only if no other open trade:** true
- **Grid distance multiplier:** 1.00, 1.00, 1.25, 1.00, 1.50, 1.25, 1.50...
- **Grid volume multiplier:** same ladder

⚠️ **Open question:** grid trading stacks trades by design, but "trade only if no other open trade" blocks new entries while one is open. These two settings look contradictory — unclear if/when the grid logic can ever actually fire. Needs checking against TWP docs.

## Filters (mostly disabled)

- Trend Filter (EMA): false
- S/R Filter: false
- Filter FVG and S&D: false
- Trade engulf only: false
- Max trades at a time: 1
- Max trades per session: 2
- Max spread: 50

This EA is running close to raw ORB logic — no extra confirmation layers active.

## News Filter

- Source: MQL5.com
- High-impact news: filtered, 30 min before/after
- Moderate/Low-impact news: NOT filtered
- Currencies checked: USD, EUR, GBP, CHF, JPY, AUD, CAD, NZD

## Account Notes

- Config screenshots are from account **108.181.193.243** (username Alandrum24).
- Trade history/chart screenshots are from a **different** account, **D3101:81322** — balance ran 299.82 → 350.59 (+50.77) on a string of EURUSD trades, Aug 4, 2026.
- D3101:81322 does **not** match the broken login noted in Active Priorities (ending 8996721, AAAFxGlobal-5 Real) — so there are at least 2-3 distinct TWP accounts in play. Needs sorting out which account is which before touching lot sizing on the $800 account — see [[Active Priorities]].
- 0.35 static lots looks aggressive for an $800 account depending on actual pip risk once the SL=0.0 question above is resolved.

## How this compares to [[TWP24 EURUSD Sets]]
That note documents Adam's own validated-profitable config on a *different* account: 0.60 lots, grid ON, up to 3 concurrent/3 per session, rarely hit the $300/day cap — with the lesson being lot size itself (not the grid) is what blew things up when pushed too high. This note's 108.181.193.243 config (0.35 static lots, grid ON but seemingly self-contradicting via "trade only if no other open trade") is a *different* setup on a *different* account, not the same validated one. Don't treat the two as the same reference point when sizing the $800 account.

## Related

- [[Active Priorities]]
- [[TWP24 EURUSD Sets]]
- [[Review Trades and Risk Management]]
