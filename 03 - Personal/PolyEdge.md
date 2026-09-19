---
status: active
project: personal
type: reference
---
# PolyEdge

Adam's Grok-built sports prediction-market app. Runs an independent model against Polymarket's prices and surfaces games where the two disagree. Tagline on the app: "Independent model vs market. Pass when the data is weak."

## Where it lives

- **Live URL:** `https://baker-giant-branch-grove.grok.me`
- **Dead URL — don't retry:** `bamboo-mist-acre-fair.grok.me` returns Grok's own "App not found — Could not find an app associated with..." page. Confirmed in a real browser, so it is **not** an auth or session problem; Grok has no app on that subdomain. Grok's auto-generated `adjective-noun-noun-noun` subdomains change when an app is renamed, so treat any old one as stale rather than broken.
- Hosted on Grok's app platform, same family as [[Jarvis Remote Control]]'s `jarvis24.grok.me`. Carries a "Created with Grok / Remix" badge.

## What it does

Sidebar: Live · Discover · Watchlist · Track · Sources. An "Ask PolyEdge" assistant sits bottom-right. On the review date it showed 146 open games and 4 picks for the day, all MLB.

Each pick gives a model probability, the market probability, the gap in points, a confidence score, and a sizing label ("SMALL PICK"). A detail page per game breaks down the factors, the probability history, injuries, market quality, and data-source health, plus a paper-trading simulator explicitly marked "Simulated entries only. Never sent to Polymarket."

## Review (2026-09-18)

**Verdict: the plumbing is stronger than the model.**

**Genuinely good — and unusual for a retail tool:**
- **Market-quality panel** (spread 0.5¢, liquidity, volume, seconds since last update). Most tools sell an edge without telling you whether it's fillable. This is a trader's instinct showing.
- Data-source status board, "Event match ✓ Verified", and an audit trail.
- Paper simulation walled off from real orders.
- "Pass when the data is weak" as a stated operating principle.

**The model's arithmetic does reconcile** — worth recording because it looks wrong at first glance. Factors are additive points from a **50% prior**: 50 + 11.9 − 4.0 + 3.4 − 0.3 = 61.0%, exactly the model's displayed 61%. The page never states the 50% baseline, so it reads as unexplained next to the "GAP +7.1 pts" figure. The fix is labelling, not maths.

**Real problems, worst first:**
1. **No starting-pitcher factor.** For a single MLB game this is the single largest input, and it is absent entirely. The model leans on run differential for +11.9 of its +11.0 net — a season-long, backward-looking aggregate is effectively the whole model.
2. **The injury factor is decorative.** Sixteen injuries listed; every one shows `−0.0 pts / Impact LOW`, including a starting shortstop (Dansby Swanson) and a frontline starter (Justin Steele). It lists injuries, it doesn't model them.
3. **It breaks its own rule.** "Other factors · 6 unavailable" — six of ten factors missing, yet it still emits a pick at MEDIUM CONFIDENCE stamped DATA VERIFIED ✓. The product promises "pass when the data is weak" and then doesn't pass.
4. **Odds source OFFLINE**, so there's no vig-free sportsbook consensus to sanity-check Polymarket against, and no true expected value — only model vs one comparatively thin market.
5. **Structural:** additive point adjustments on a raw probability scale aren't probability-coherent; stack enough factors and it can run past 100%. Harmless at 61%, wrong on a strong lean. Log-odds is the correct form.
6. **Timestamps mix timezones** — probability history shows 1:30 AM entries for a 3:40 PM PT game.
7. Cosmetic: a card read "+5 pts" while displaying 53% vs 49%, i.e. rounding the underlying values and the displayed integers separately.

**Recommended order of work:** starting pitchers first (biggest missing input), then the confidence gate so it stops emitting picks on half a dataset, then the injury weights.

## PROOF the old model is broken, not the market (2026-09-19)
The screenshot's **#5 lean, "JAGUARS 59%, +17 pts"**, measured against two independent markets for the same game (`nfl-jax-den-2026-09-20`):

| Source | Jaguars |
|---|---|
| PolyEdge "LEAN" | **59%** |
| DraftKings, devigged | 42.8% |
| Polymarket live ($583k liquidity) | 41.5% |

The sharp book and the prediction market agree within 1.3 points. **The model was ~16 points wrong, and the "+17 pt edge" was simply the size of its own error.** This is the concrete case for the >8pt MODEL_SUSPECT gate: that card would never have shipped.
Also visible in the screenshots and now explained: picks #1 and #2 were the same game (Royals/Pirates) at +10 and +11 — a dedupe failure plus an inconsistent market snapshot between the two reads.

## Base44 rebuild — BUILDING 2026-09-19 (status: created, build in progress, untested)
**Base44 app id `6aae5695dbc22f6715196ad4`** — editor: `https://app.base44.com/apps/6aae5695dbc22f6715196ad4/editor/preview`. Created fresh (no prior Base44 app matched "poly"). Adam granted "full permission" to build it through without step-by-step confirmation.
### Build log (2026-09-19, ~1–3 AM)
**Turn 1 produced entities only and reported `ready`.** `Pick`/`Watchlist`/`DataCache` schemas existed, but `src/App.jsx` was the untouched scaffold with no routes and `src/pages` held only auth screens. Caught by reading the code, not by trusting the status — the same "Base44's own progress claims aren't evidence" lesson already recorded in [[O For the Love of Coffee]]. **Turn 2** (re-sent with the verified ESPN JSON path and a worked devig example) built the real thing: `Live/Discover/Watchlist/Track/Sources` pages, `PickCard`/`StateBadge`/`CalibrationChart`/`AskAssistant`/`EmptyBoard` components, and four backend functions (`fetchGames`, `buildModel`, `gradePicks`, `askPolyEdge`) over `shared/{espn,polymarket,model,cache}.ts`.

**What the builder got right on its own:** log-odds from a logit-0 prior, position-and-status-weighted injuries (a real table, not decoration), bullpen honestly marked unavailable so it counts toward the gate, and the full PASS / NO_ODDS / MODEL_SUSPECT / PICK state machine.

**Three real defects found by review + live testing, all fixed by hand (checkpoint `6aae5c9b…` before, `6aae5d44…` after):**
1. **Polymarket integration was dead on arrival.** It called `/markets?tag_slug=mlb`, which silently ignores the filter and returns political markets. Rewritten to the verified slug method — now **15/15 games matched**. Full detail in [[Polymarket (Prediction Markets)]].
2. **Unclamped sigmoid.** `1/(1+Math.exp(-50))` is exactly `1.0` in float64, so a large stacked logit would display a 100% pick. Found by a reference implementation's own self-check failing. Clamped to 0.1–99.9%.
3. **A regression I introduced and caught before it shipped:** guessed abbreviation aliases (`KC→kcr`, `SF→sfg`, `SD→sdp`, `TB→tbr`, `WSH→was`) would have broken four *working* lookups. Only `CHW→cws` and `ATH→oak` are real. Verify, never guess.

**Known constraint, not yet resolved:** ESPN blocks the Base44 Worker's egress (403 on TLS/IP fingerprint), so `shared/espn.ts` falls back through public CORS proxies (allorigins, codetabs, cors.lol) with an optional `SCRAPER_API_KEY` secret. Free proxies are flaky and can vanish — this is the app's most fragile dependency and Adam has not been asked about the ScraperAPI key.

**Reference implementation** for verifying the app's numbers: `polyedge_ref.py` (session scratchpad — move somewhere permanent if it stays useful). It reproduces the devig, the log-odds prior, and the pass gate, and demonstrated that a null 50% model still emits 9 picks from 15 games — proof the gate must key on data completeness first, gap size second.

Spec sent to the builder: ESPN free feed (MLB/NFL/CFB) incl. probable starting pitchers; The Odds API as a **server-side secret Adam enters himself** with hourly caching for the free tier, and a visible "MARKET REFERENCE OFFLINE" state when absent; Polymarket gamma-api for market price; **log-odds model with a stated 50% prior**; importance-weighted injuries; **hard pass gate** (missing inputs or >~8pt disagreement → MODEL SUSPECT, no pick; ≥2pt after spread to qualify as a pick); dedupe by game id; local-timezone consistency; and a **calibration ledger** (auto-graded picks, hit rate, ROI, calibration curve) as the real product. Screens: Live / Discover / Watchlist / Track / Sources + Ask assistant.


Adam's call: **fresh Base44 app** (not an upgrade of [[RetroVault (CeeloEdge)]]), same dark look as the Grok app but "premium, hot, new, future-looking," and better underneath. Data: the free ESPN feed from [[Public ESPN API]] (verified 2026-09-19: MLB scoreboard carries probable starting pitchers; injuries are a separate per-team endpoint; odds were empty only on already-Final games, upcoming games unchecked) plus Adam's free **The Odds API** key as the multi-book/Pinnacle reference. The key lives ONLY as a server-side Base44 secret entered by Adam himself, never in front-end code, the vault, or chat; the free tier is small, so cache odds. Zapier is optional (Google Sheets ledger backup), not core.
Screenshot evidence for why the model needs fixing: the Grok app listed one game (Royals vs Pirates) twice as picks #1 and #2, and showed +15/+17-pt "leans" that contradict the measured ~1-pt market efficiency in [[Finding Polymarket Edges]].

## Related
[[Jarvis Remote Control]] — the other Grok-hosted app, and the reason the `.grok.me` URL pattern is familiar.
