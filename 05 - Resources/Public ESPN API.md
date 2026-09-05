---
status: active
project: meta
type: reference
---
# Public ESPN API

Reference doc repo for ESPN's undocumented public API: [pseudo-r/Public-ESPN-API](https://github.com/pseudo-r/Public-ESPN-API). Source for sports data — Adam wants it on hand for sports info.

## What it is
Community-maintained documentation mapping ESPN's public (unofficial) API endpoints across 17 sports and 139 leagues, including NFL, NBA, MLB, NHL, MLS, Premier League, and more.

## Access
- **No API key required** — endpoints are publicly accessible.
- Repo notes excessive requests may get blocked; recommends caching and respecting rate limits.

## What it exposes
- Live scores and scoreboards
- Team rosters and schedules
- Player stats and profiles
- Injury reports and transactions
- Standings and rankings
- Betting odds and probabilities
- Play-by-play data
- News articles

Base domains: `site.api.espn.com`, `sports.core.api.espn.com`, `cdn.espn.com`, plus others — full curl examples are in the repo's docs.

## Also in the repo
- A Django service wrapping the API with persistence, background jobs, and OpenAPI docs, if a hosted/persistent layer is ever needed instead of hitting ESPN directly.
- Example real-world apps (Sportly) built on it.

## Status
**In active use as of 2026-09-05.** Verified live: `https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard` returns real scheduled/live games (schedule, status, teams). Paired with [[Polymarket (Prediction Markets)]] to give Adam schedule/stats + market-implied odds together for sports decisions, on request, via plain WebFetch — no extra code, no API key, no confirmation prompt (WebFetch is already auto-allowed on the JARVIS Bridge).
