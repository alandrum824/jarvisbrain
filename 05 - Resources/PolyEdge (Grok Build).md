---
status: active
project: meta
type: reference
---
# PolyEdge (Grok Build)

Adam's sports-prediction/edge-detection app, built via SuperGrok's "Build with Grok" (same tool used for [[TWI Sniper ORB]]) — separate from [[RetroVault (CeeloEdge)]], which is the Base44 version of a similar idea. Shows PolyEdge's own model probability against live Polymarket market price per game, flags large disagreements as possible edges.

## Stack (as of 2026-09-06/07)
- **Polymarket US TypeScript SDK** (`Polymarket/polymarket-us-typescript`, `PolymarketUS` import) — market-price source.
- **Public ESPN API** (`pseudo-r/Public-ESPN-API`) — team/schedule/roster/stats/predictor data.
- **`brodyautomates/polymarket-pipeline`** — used as an architecture reference for event matching, materiality, calibration/backtesting (not run directly; see [[Polymarket Pipeline]] for that repo's own standalone setup).
- `runesleo/polymarket-toolkit` — secondary Polymarket analysis layer, not core to the prediction engine.

## Bug #1 found and fixed 2026-09-06: FBS/FCS classification blindness
Model gave Villanova (FCS) a 45% win probability against Louisville (FBS Power/ACC) — real market had Louisville at ~96-98%, the sane number for that tier gap. Root cause: ESPN's scoreboard endpoint never inlines `groups`, only `conferenceId`, and the model had no tier signal at all.

**Fix shipped by Grok:**
- Classification now derived from `conferenceId` (ACC/Big Ten/SEC/Big 12 etc. = Power; Patriot/CAA/SWAC/etc. = FCS; group 18 = FBS Independents, not FCS).
- Power-vs-FCS tier gap is now an explicit ~48pt model input, not a soft tie-break — thin early-season records can't erase it.
- If classification is missing on both sides, model returns `INSUFFICIENT_DATA` instead of defaulting to 45/55.
- If model vs. live Polymarket price diverges >28pts, the quote still displays but is flagged `DATA GAP / NEEDS REVIEW` instead of being sold as a real edge. Market price is never copied into the model itself.
- Admin "Data audit" now dumps the raw ESPN features (conference, tier, rank, record, point differential) that fed each row, so future bugs like this are checkable from the UI.
- Re-verified: Villanova/Louisville now reads model 3% / market 4% / Louisville 97%, 1pt residual, status OK.

## Open issue: confidence score looks bucketed, not computed
Observed exact-duplicate confidence values across unrelated games:
- Dolphins/Raiders (NFL) and Missouri/Kansas (NCAAF) both showed **Confidence 74**.
- Ravens/Colts and Bears/Panthers (both NFL) both showed **Confidence 11**.
- Same-tier-gap NCAAF games (Colgate/Central Michigan, Wagner/James Madison) showed 37 and 34 — close but not identical.

Pattern suggests confidence may be clustering by category/sport bucket rather than being computed per-game from real inputs (sample size, data completeness, variance). Not yet confirmed as a bug — flagged to Grok, asked to show the actual calculation path. Unresolved as of 2026-09-07.

## Also open: model disagrees with Polymarket on same-tier games (no classification issue)
Several "VERY LARGE DISAGREEMENT" flags remain on normal same-tier matchups after the FBS/FCS fix (e.g. Dolphins 62% vs market 37%, Missouri 89% vs market 69%). Asked Grok to run a real calibration/reliability backtest — bucket historical predicted probabilities against actual outcomes — to check whether the model is systematically overconfident generally, rather than patching individual games. Not yet run.

## Requested 2026-09-06: The Odds API as a second market reference
Asked Grok to wire in `the-odds-api` (consensus sportsbook odds — DraftKings/FanDuel/Pinnacle, devigged) alongside Polymarket, to distinguish "model is wrong" from "Polymarket is thin/mispriced and this is a real opportunity":
- Model agrees with Odds API but Polymarket is the outlier → flag `REAL OPPORTUNITY`.
- Model disagrees with both → flag `MODEL SUSPECT` (likely another data/calibration bug, not an edge).
- All three agree → no flag.
- Show all three raw numbers on the card, log which bucket each game lands in for later hit-rate checking.
- Start on Odds API's free/lowest tier — cost not justified until the system's proven out.

Status: prompt handed to Grok, not yet confirmed built.

## Related
- [[RetroVault (CeeloEdge)]] — the Base44 sibling app, same underlying idea (ESPN + Polymarket → sports signal), separate codebase.
- [[Polymarket (Prediction Markets)]], [[Public ESPN API]] — the free data-source notes both apps share.
- [[Polymarket Pipeline]] — the standalone clone of the architecture-reference repo.
- [[TWI Sniper ORB]] — other SuperGrok "Build with Grok" project, same build tool.
