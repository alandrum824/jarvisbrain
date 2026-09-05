---
status: active
project: meta
type: reference
---
# Polymarket (Prediction Markets)

Public, no-key API for pulling real-money prediction-market odds — used to help Adam think through sports-game decisions by seeing what the market actually implies, alongside real stats from [[Public ESPN API]]. Informational only: Jarvis surfaces odds and analysis, it does not place trades or move money on Polymarket.

## Verified live 2026-09-05

**Gamma API**, base `https://gamma-api.polymarket.com`, no auth needed for reads:

- `GET /public-search?q=<team names>` — best way to find a specific game's market. Returns the event with its market(s), `outcomes` (e.g. `["Patriots","Seahawks"]`) and `outcomePrices` (e.g. `["0.37","0.63"]` — these ARE the market-implied win probabilities, since a share resolving to $1 trades at its probability).
- `GET /markets?limit=N&active=true&closed=false&order=volume24hr&ascending=false` — top markets by recent volume, for browsing rather than searching a known matchup.
- `GET /events?tag_slug=nfl&active=true&closed=false` — browse by sport/league tag (works for `nfl`; other leagues' exact tag slugs not yet enumerated).

Confirmed real example: "Patriots vs. Seahawks" (2026-09-10 game) — Polymarket had Seahawks 63% / Patriots 37%, $216k liquidity, matched against ESPN's scoreboard entry for the same game.

## How Jarvis uses this
On request, WebFetch the relevant Gamma API URL (already auto-allowed, no phone confirmation needed) alongside an ESPN scoreboard/stats pull, and present both together: real stats/injuries/form from ESPN, market-implied probability from Polymarket. Decision support, not a betting recommendation engine — Adam makes the call.

## Boundaries
Reading odds and analyzing is fine. Actually placing a trade/bet on Polymarket (or anywhere) is a real money-movement action and is not something Jarvis does autonomously — that stays a human action if Adam ever wants to act on the analysis.

## Related
[[Public ESPN API]] — the stats/schedule half of this pairing.
