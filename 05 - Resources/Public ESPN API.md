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

## Moneylines: the exact JSON path (verified 2026-09-19 — bank this)
The scoreboard carries **both sides** of the DraftKings moneyline, but **not** where you'd expect. `competitions[0].awayTeamOdds.moneyLine` / `.homeTeamOdds.moneyLine` are **always `null`** — a dead end that looks like "ESPN only gives one side." The real values live at:

```
competitions[0].odds[0].moneyline.away.close.odds   e.g. "+114"
competitions[0].odds[0].moneyline.home.close.odds   e.g. "-137"
competitions[0].odds[0].moneyline.away.open.odds    ← opening line, i.e. free line-movement data
```
`odds[0].details` ("CHW -137") is favourite-only, so it can't be devigged on its own.

**Verified live on all 15 MLB games for 2026-09-19**: every game had both sides, and the computed vig came out 4.5–4.8% across the board — matching the ~4.5% figure in [[Finding Polymarket Edges]]. The full devig pipeline (both sides → implied → normalise → fair value) works end-to-end off this free feed with no key.

**Timing constraint:** odds only appear close to game day. The same query for the *next* day returned 15 scheduled games with **zero** odds. Any app must treat "odds not posted yet" as a normal state, not an outage.

**Probable starting pitchers** are inline at `competitors[].probables[].athlete.displayName`. **Injuries are not** on the scoreboard — see below.

Same moneyline path verified on **NFL** and **college football** too (CFB: 19 of 22 games carried a usable moneyline). Not MLB-only.

## Injuries: the silent-empty trap (verified 2026-09-19)
`site.api.espn.com/apis/site/v2/sports/<sport>/<league>/teams/<id>/injuries` returns **HTTP 200 with an empty body `{}`**. It looks like a working endpoint returning "no injuries." It is not — it never returns data. **This is almost certainly the root cause of [[PolyEdge]]'s dead injury panel**, where sixteen injuries all rendered "−0.0 pts / Impact LOW."

The endpoint that actually works is the **core** API:
```
sports.core.api.espn.com/v2/sports/<sport>/leagues/<league>/teams/<id>/injuries?limit=50
```
It returns `items[]` of `$ref` URLs, not objects, so each injury needs a follow-up fetch. Each injury payload carries `status` ("Day-To-Day", "Out", IL variants), `type.description`, `details.returnDate`, and an **`athlete.$ref`** — and the athlete's position requires yet another fetch. So weighting an injury by player importance costs 2 extra calls per injury (~13 injuries/team → ~26 calls/team, ~52/game).

**Consequence for any app:** injuries must be cached hard (6–12 hours; they change slowly) or the request count explodes. But severity (`status`) and position (via the athlete ref) are genuinely available — so "weight injuries by importance" is achievable, it just is not free.

## Status
**In active use as of 2026-09-05.** Verified live: `https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard` returns real scheduled/live games (schedule, status, teams). Paired with [[Polymarket (Prediction Markets)]] to give Adam schedule/stats + market-implied odds together for sports decisions, on request, via plain WebFetch — no extra code, no API key, no confirmation prompt (WebFetch is already auto-allowed on the JARVIS Bridge).
