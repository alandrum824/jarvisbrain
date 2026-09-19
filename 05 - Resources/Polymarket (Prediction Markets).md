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

## The resolved-market trap (verified 2026-09-19 — read before writing any matching code)
**`/public-search` ranks stale, already-resolved markets above the live one.** Searching `q=Royals Pirates` returned three **2025** events, all `closed: true`, with `outcomePrices` of `["0","1"]`. Any code that takes the first search hit gets a settled market priced at 0%/100% — which reads as a colossal edge and is entirely fake. This is a prime suspect for the absurd double-digit "leans" in [[PolyEdge]].

Proof, same matchup, two adjacent slugs:
| Slug | closed | prices | liquidity | acceptingOrders |
|---|---|---|---|---|
| `mlb-kc-pit-2026-09-18` | **true** | `["0","1"]` | null | false |
| `mlb-kc-pit-2026-09-19` | false | `["0.485","0.515"]` | $89,117 | true |

**Rules that follow:**
1. Never trust `/public-search` ordering. Always filter `closed: false` and `acceptingOrders: true`, and treat `liquidity: null` as a dead market.
2. Prefer resolving by slug: `GET /events?slug=mlb-<away>-<home>-<YYYY-MM-DD>`. It is deterministic and avoids fuzzy title matching.
3. **Team order in the slug is not reliably away-home** — `mlb-pit-kc-2026-09-18` returned no event while `mlb-kc-pit-...` did. Try both orders before giving up.
4. Events also carry non-moneyline side markets ("Will there be a run scored in the first inning?"). Match on the game-title market, never blindly on `markets[0]`.

## Both "browse by league" endpoints are dead ends (verified 2026-09-19)
- **`/markets?closed=false&tag_slug=mlb` silently IGNORES `tag_slug`.** It returned 100 markets — Xi Jinping, the 2028 Democratic nomination, Newsom, AOC. **Zero MLB.** Any name-matching against that list is matching against noise, and it fails silently rather than erroring.
- **`/events?tag_slug=mlb` returns season FUTURES only** (World Series champion, AL/NL MVP, Cy Young) — no individual games.

**So the only verified way to price a specific game is the deterministic slug**, below.

## The slug method (verified 15/15 on a full MLB board)
```
GET /events?slug={league}-{away}-{home}-{YYYY-MM-DD}
```
`league` is `mlb` / `nfl` (NFL confirmed: `nfl-jax-den-2026-09-20`). Team order is not reliably away-home, so **try both orders**.

**Abbreviations are ESPN's, lowercased — with exactly two exceptions found:** `CHW → cws` and `ATH → oak`. Everything else (`kc`, `sf`, `sd`, `tb`, `wsh`, `nyy`, `laa`…) works as the plain lowercase ESPN abbreviation. **Adding "obvious" aliases like `KC → kcr` or `SF → sfg` BREAKS working lookups** — that guess was made and caught in testing before it shipped. Verify a slug before adding any alias.

## One event holds ~27 markets — use `sportsMarketType`
A single game event carries moneyline, spreads (**with the team order reversed**), totals, team totals, NRFI, first-five innings, and extra-innings markets. Matching on "the question contains both team names" can land on a spread and report it as a win probability. **Filter on `sportsMarketType === "moneyline"`.** Also require `acceptingOrders !== false`, `liquidity > 0`, and reject any price at exactly 0 or 1.

## Python/urllib note
Polymarket returns **403 to the default `python-urllib` User-Agent.** Any browser UA works. (ESPN is the mirror image — it 403s a bare `Mozilla/5.0` from urllib but accepts curl's default.)

**Cross-check that confirms the whole pipeline:** for KC @ PIT on 2026-09-19, DraftKings devigged fair value (via [[Public ESPN API]]) was KC 48.0% / PIT 52.0%; live Polymarket was KC 48.5% / PIT 51.5%. **A 0.5-point gap** — squarely in line with the ~1-point efficiency measured in [[Finding Polymarket Edges]], and further evidence that real edges do not live in liquid game markets.

## How Jarvis uses this
On request, WebFetch the relevant Gamma API URL (already auto-allowed, no phone confirmation needed) alongside an ESPN scoreboard/stats pull, and present both together: real stats/injuries/form from ESPN, market-implied probability from Polymarket. Decision support, not a betting recommendation engine — Adam makes the call.

## Boundaries
Reading odds and analyzing is fine. Actually placing a trade/bet on Polymarket (or anywhere) is a real money-movement action and is not something Jarvis does autonomously — that stays a human action if Adam ever wants to act on the analysis.

## Related
[[Public ESPN API]] — the stats/schedule half of this pairing.
