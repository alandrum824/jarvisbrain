---
status: active
project: meta
type: reference
---
# RetroVault (CeeloEdge)

Base44 app id `69c8ef0163fff3ee50858eba`. Displayed app name inside the UI is **CeeloEdge** — a real, substantial sports-pick/signal engine, not a toy: random forest model, market sanity/sharp-money detection, EV calculations, auto-learning from settled results, live odds pulls, full grading system (`src/lib/grading.js`, 54KB). Adam built this to pick NFL/MLB (and now college football) games and inform Polymarket decisions.

## Real architecture (as of 2026-09-06)
- **Data source, app-wide: ESPN Public API + Polymarket's free public API. No paid keys.** `getSportsData` and the original `getLiveOdds`/`generateSignals` functions depend on paid keys (SportsData.io, The Odds API) but are **dead code** — confirmed via full-codebase grep, nothing in the frontend calls them. The active pipeline (`getAllGamesToday`, `generateLiveSignal`, `searchGames`) was already ESPN-only before tonight; Polymarket was added tonight as the real market-price source.
- **Signal.entity** is the core data model — every pick, with 50+ scored fields (edge_score, model_probability, market_probability, pick_tier, sharp_signal, market_sanity, etc.)
- **Two separate front-ends read/generate signals differently** — this caused the real bug found tonight:
  - `src/pages/AllGames.jsx` (route `/all-games`) — fetches today's games, auto-generates a signal for up to 3 games missing one.
  - `src/pages/Signals.jsx` (route `/`, **the actual home screen**) — used to be a pure read-only view of the `Signal` table. It never fetched games or generated anything itself, so if Adam never visited `/all-games` or `/sport-picks`, home showed "No signals yet — AI is analyzing..." **forever**. This was the real "not working" root cause reported tonight, not a data/API problem.

## What changed 2026-09-06 (Adam: "it's not working, build it, add college football, just use Polymarket")

1. **Home screen (`Signals.jsx`) now actually generates signals itself** — added the same games-fetch + auto-generate-for-3-games pattern `AllGames.jsx` already had. This is the actual fix for "nothing showing."
2. **College Football added end-to-end**: `getAllGamesToday`, `generateLiveSignal`, `searchGames`, and both `Signals.jsx`/`AllGames.jsx`'s sport lists (`AllGames.jsx` already expected `'College Football'` in `VALID_SPORTS` — the backend just never fetched it). `SportLogo` also fixed to show a text-badge fallback instead of nothing for sports with no uploaded logo asset (College Football has none yet).
3. **Real Polymarket market price wired into `generateLiveSignal`** — fetches the actual open market for the specific game (`gamma-api.polymarket.com/public-search`), and the LLM prompt now instructs `market_probability` to come from the real Polymarket price when found, falling back to ESPN's predictor only when no market exists. Verified live: found real markets for MLB games, correctly returned nothing for closed/resolved markets and for small college games Polymarket doesn't cover (real coverage gap, not a bug — Polymarket has the big/ranked college matchups, not every FCS buy-game).
4. **`searchGames` rewritten** — was 100% dependent on the paid Odds API key (if missing/expired, search returned nothing, silently, with no error surfaced anywhere). Rewritten to ESPN + Polymarket, matching the rest of the app. This was a second real, likely-active bug (search is used from the search bar and EventPage).
5. Verified with a **real production build** (`npx vite build`, exit 0) — not just a syntax check — across all five edited files.

## Known remaining gap (not fixed, low priority)
UI still says "Kalshi" throughout (labels, AI prompts, the `kalshi_market` field name) even though the actual market backing every number is Polymarket now. Cosmetic — a real rename would touch `SignalDetailModal.jsx`, `TrackBetModal.jsx`, `Analyzer.jsx`, `SignalAIChat.jsx`, and the `Signal`/`TrackedBet` entity schemas. Not done — separate ask if Adam wants it.

## Related
[[Public ESPN API]], [[Polymarket (Prediction Markets)]] — the two free data sources this app now runs entirely on.
