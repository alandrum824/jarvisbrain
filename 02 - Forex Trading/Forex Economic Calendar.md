---
status: active
project: forex-trading
type: reference
---
# Forex Economic Calendar

Free, no-key economic calendar feed — the same data ForexFactory's calendar widget uses, mirrored at Fair Economy. Lets me check for high-impact news events (NFP, rate decisions, CPI, etc.) around TWP ORB's trades, since news volatility is a real risk factor for [[Review Trades and Risk Management]].

## Endpoint
```
https://nfs.faireconomy.media/ff_calendar_thisweek.json
```
No API key. Only the current-week window is available — `today`/`nextweek`/`lastweek`/`thismonth` variants of the URL all 404, so pull `thisweek` and filter by date client-side for anything outside "right now."

## Fields per event
```json
{"title":"...","country":"USD","date":"2026-08-17T08:30:00-04:00","impact":"High","forecast":"...","previous":"..."}
```
- `country` — the currency the event moves (USD, EUR, GBP, JPY, etc.), not a country code.
- `impact` — `Low` / `Medium` / `High` (occasionally `Holiday`).
- `date` — ISO 8601 with the feed's own UTC offset baked in.

## How to use it for TWP ORB (EUR/USD)
1. Pull the feed, filter `country` to `USD` or `EUR`.
2. Filter `impact` to `Medium` or `High`.
3. Cross-reference event times against the trade timestamps under review — flag any trade opened within roughly 15-30 min of a High-impact USD/EUR event as a news-risk factor, per the [[Review Trades and Risk Management]] quality bar (specific, not vague).

## Status
Wired in as a reference/data source only — not polled automatically, no alerting. Pull it on demand during a trade review, or if asked "any big news today/this week."
