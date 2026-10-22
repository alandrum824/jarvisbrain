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

## Spec prompt v1 (Adam, built with Grok, shared 2026-09-24) + Jarvis review
Adam's master prompt defines PolyEdge as a multi-sport edge engine (MLB/NFL/NBA/NHL/NCAAF/NCAAB) with four separate outputs (model probability, data quality, market edge across three prices, decision BET/LEAN/WATCH/WAIT/PASS), sport-specific critical inputs, log-odds math with capped features, injury impact vs informational, VERIFIED/LIMITED/WAIT/PASS status, confidence ≠ win probability, freshness in PT, snapshot audit, per-sport backtests, and priority order data integrity → model → calibration → market → edge → bet.
**Review, main gaps:** (1) no numeric thresholds for BET/LEAN/WATCH; (2) the market should be the baseline prior with capped adjustments, not an optional signal; (3) no rule for when the model disagrees with BOTH books and Polymarket (usually model error, so cap at WATCH); (4) the Polymarket price must be the executable ask at stake size after fees, and resolution rules must match the book market; (5) no stake sizing; (6) no promotion gate (no BET until a version has enough backtested/paper bets and passes calibration); (7) the LLM can't compute or store: probabilities, gates and snapshots must live in code (the Base44 app), with the LLM explaining; (8) track PASSes with prices to test whether the gate is too strict; (9) WAIT needs a re-check time per sport. A paste-in v2 add-on block was given to Adam.
**Grok app cards reviewed the same day (Adam's phone, 11:36):** MLB Mets @ Nationals Sat 9/26 1:05 PM, "PolyEdge pick NATIONALS 56% vs market 44%, +12 pts, MODERATE PICK, medium confidence 58"; NCAAF Clemson vs California, "LEAN CALIFORNIA 63% vs 49%, +14 pts, LOW confidence 22". Both are the same failure pattern as the Jaguars +17 case (a double-digit edge against a liquid market = the model's own error until proven otherwise). Against his own spec: no data quality %, no VERIFIED/WAIT status, one market price instead of three, no starting pitchers or QB shown, and MLB picked ~a day before lineups (should be WAIT). The Cal LEAN at confidence 22 should be WATCH/PASS. The Base44 rebuild's MODEL_SUSPECT (>8 pt) gate would have blocked both.
**Grok Build upgrade prompt given to Adam (2026-09-24):** upgrade, don't rebuild; market-as-prior log-odds (±0.35 logit cap); hard gates in code (MODEL_SUSPECT >8 pts, disagrees-with-both → WATCH, critical-input → LIMITED, confidence <40 → no LEAN/BET, single-factor → PASS, dedupe); thresholds (BET ≥4 pts net vs Polymarket ask after fees, VERIFIED, confidence ≥60, books agree, liquidity, resolution match; 0.25 Kelly cap 1%); role-weighted injuries; decision-first card with three prices, Missing / Risk / Why, times in PT; Odds API as an owner-entered secret; immutable snapshots + per-sport/market tracking + a 100-pick promotion gate (PAPER until then); 7 acceptance tests (the Nats/Cal cards must come out WATCH/WAIT).

## Upgraded Grok app, cards reviewed 2026-09-25 12:38 AM PT (Adam's phone)
Cards: NCAAF UCLA vs Maryland WAIT (QB unconfirmed, conf 22, re-check 9:00 AM); NHL Jets vs Avalanche PASS "Below 50%, favors Colorado" with a WAIT · conf 14 sub-line; NFL Jets vs Lions PASS "Below 50%, favors Detroit", WAIT · conf 22; MLB Rays @ Phillies WAIT "starting pitchers not confirmed", conf 58, re-check 12:40 PM. Every card: Odds "—", "MARKET VALIDATION UNAVAILABLE".
**Better:** the gates now block instead of printing +12 leans; missing inputs listed; PT times; per-source timestamps; "This is not a bet."
**Defects:**
1. **MLB probable-pitcher parse is broken (VERIFIED).** ESPN scoreboard for 2026-09-25 lists probables for 15 of 17 games, incl. PHI Cristopher Sanchez vs TB Freddy Peralta. Path: `events[].competitions[0].competitors[].probables[]` (name `probableStartingPitcher`, `athlete.displayName`). The app says "not confirmed", so it's reading the wrong path or wants a "confirmed" flag that ESPN doesn't give.
2. **"Below 50%" PASS logic:** it evaluates only one listed side. When the model favors the other team, it should evaluate that team against its own price, not pass.
3. **Status contradiction:** a PASS headline with a WAIT sub-status on the same card. One status per card.
4. **Confidence not capped by missing critical inputs:** 58 on the MLB card with SP + books missing vs 22 elsewhere. Missing a critical input should cap it (≤30).
5. **Odds API not connected** on every card, so no card can ever reach BET. The gate behaves correctly. Needs Adam's own key as a server-side secret.
**Refinement from the Live list (12:41 AM, same unpatched build: 0 picks, 118 PASS, 9 WAIT):** the app DOES read the names (Jonah Tong, Lake Bachar, Joey Daccord show on WAIT rows) but still says "ESPN unconfirmed". So defect 1 is the **gate** treating ESPN's `probableStartingPitcher` as unconfirmed, not a parse miss. Verified on ESPN: Mets @ Nationals today has no NYM probable, so that WAIT is correct; the two Mets rows are a real series (9/25 and 9/26), not a dupe. 118 passes vs 0 picks suggests defect 2 (one-sided "Below 50%") is behind many of the passes.
6. **NCAAF "QB not confirmed":** college starting QBs are rarely formally confirmed, so this can WAIT forever. Use the probable starter (last start / depth chart) with a flag.

**Patch prompt given to Adam (2026-09-25 ~12:45 AM):** items 0–6 = probables gated as unconfirmed → treat as PRESENT; ESPN path; evaluate both sides / drop "Below 50%"; one status per card; confidence ≤30 when a critical input is missing; probable QB/goalie rule; acceptance test (TB@PHI shows Peralta vs Sanchez; 15 MLB games with probables leave WAIT unless another input is missing; no dual statuses; PASS reasons listed).

## Patched build checked 2026-09-25 1:14 AM PT
**Passed (verified on ESPN):** all 5 MLB WAITs for 9/26 are correct (each game is missing one side's probable: ATL, TEX, BOS, PHI). Mets @ Nats 9/25 WAIT is correct, with confidence capped at 30 and a re-check 3h before. Rays @ Phillies 9/25 left the WAIT list. PASS reasons are now counted by reason. One status per card. Bears WAIT is correct and actually understated: ESPN has Caleb Williams **Doubtful** and Tyson Bagent Questionable, but the card only names Bagent.
**Still wrong:** the Mets @ Nats 9/26 **WATCH Nationals 55% vs Polymarket 44%, +11 pts**. The same game flagged 9/24 at +12. The "Why" lists only SMALL home advantage + SMALL run differential, and the probables (Tong vs Irvin) aren't used. Two small factors on a **50% prior** = 55%, so the +11 "edge" is just the gap between 50% and the market, not information. Fix: market-as-prior (start from the devigged/Polymarket price, apply capped logit adjustments), and >8 pts vs market → MODEL SUSPECT. Cosmetic: "MODEL ONLY — MARKET VALIDATION UNAVAILABLE" printed twice. The Odds API key is still not connected.

**Odds API key (2026-09-25 ~1:20 AM):** Adam shared his The Odds API key in the terminal chat. Validated with the no-cost /v4/sports call: HTTP 200, free tier, **500 requests/month, 0 used**. The key value is NOT stored in the vault. It belongs only in the app's server-side secret, which Adam enters himself. Budget: 500/mo won't cover per-minute polling; the app must cache (e.g. one h2h pull per sport a few times a day, ~1 credit per sport per market per region).

## Base44 rebuild FIXED — market-as-prior (2026-09-25 ~2:15 AM PT) — status: code done + checkpointed, NOT published, build not verified through MCP
Adam: "Fix poly edge on base 44." Checkpoints: before `6ab643c05b098d640f060b1d`, after `6ab645614873a0eaa67003f0`.
**Evidence that drove it (season backtest, 2,080 MLB games 2026, DraftKings closing lines from ESPN summary `pickcenter`, point-in-time run differential rebuilt from scores):** market log-loss 0.6777, old app model 0.6882 (worse than the market), coin flip 0.6931. Logistic fit result ~ market logit + RD: RD z = −0.29, so team strength adds nothing once the price is known. The old model disagreed with the market by >4pt on 54% of games; its 2–4pt "picks" returned +1% over 442 bets (noise). Replaying the old model on 9/25 gave 8/17 MODEL_SUSPECT with 10–20pt gaps (raw early-season ERA × 0.30 logit, RD up to 1.1 logit). Historic ESPN pitcher ERA is season-to-date (lookahead), so the pitcher factor can't be backtested from ESPN. Scripts: session scratchpad `pe_backtest_pull.py` / `pe_backtest_eval.py` / `pe_test/harness.mjs`.
**Changes:**
1. `shared/model.ts` rewritten: fair = devigged sportsbook consensus (market as prior); team factors shown as "(priced in)" with 0 weight; only the news signal adjusts (±0.05, total cap ±0.10 logit). Edge = Polymarket ASK cheaper than fair after costs (0.5pt at ask, 1pt at mid). PICK ≥2pt with multi-book consensus and books agreeing within 4pt; LEAN 1–2pt or single book; PRICE SUSPECT >8pt; PASS on <$5k liquidity, no starter, no line, no Polymarket.
2. `shared/oddsapi.ts` (new): The Odds API h2h consensus (median of per-book no-vig probs), server-side secret `ODDS_API_KEY`, 3h cache, 15 calls/day cap, pauses under 50 credits, shows credits left on Sources. Match = same teams, nearest kickoff within 3h.
3. **Polymarket matching bug (verified):** a 7:10 PM PT game is the next day in UTC, so the first slug tried was TOMORROW's game in the series. LAA@SEA 9/25 matched the 9/26 market (Angels 37.5¢ vs the real 44.5¢), a fake 6.7pt PICK. Fix: event `startTime` must be within 3h of ESPN kickoff (also separates doubleheaders), in both `src/lib/polymarket.js` and `shared/polymarket.ts`. Prices now use bestAsk / 1−bestBid (buy price), not the midpoint.
4. `gradePicks` could never run: it imported `fetchScoreboard`, which `espn.ts` never exported. Added (direct + allorigins/codetabs fallback). Grouping is by league, so college picks now get graded.
5. Copy: "Sharp books vs Polymarket", MODEL SUSPECT → PRICE SUSPECT, Sources gate text, askPolyEdge prompt.
**Verified locally on the live 9/25 slate:** with the fixes, 16 PASS / 1 LEAN / 0 PICK (DK line); with the 9-book consensus it's all within ~1pt, as expected for efficient markets. Odds API credits: 498 left after 2 test calls.
**Adam to do:** add Base44 secret `ODDS_API_KEY` himself; publish when ready (platform API blocked for this MCP token, so neither preview nor deploy is reachable from here); rotate the key since it passed through chat.

**LIVE CONFIRMED (Adam's phone, 2026-09-25 3:29 AM PT):** published, and the Odds API consensus is working (the BAL@NYY card reads "consensus of 7 books"). Rays@Phillies shows Poly 39.0 vs fair 39.7, matching the local test. The old key's counter still shows only Jarvis's 1 test call, so the app runs on a rotated key. 17 Saturday games showed "Odds not posted": correct, since at 3:30 AM ESPN had 0/14 Saturday lines and the Odds API listed only Friday's 17 games. **Fixed the same session** (checkpoint `6ab64d98094be129b70de789`, needs a publish): the card headline read "0 pts" next to a real 1.6pt edge (it computed model − fair, which is always 0 now). Columns are now Sharp Fair / Polymarket / Edge (net pts); "Model still favours" → "The books still favour"; the suspect headline → "Price Suspect"; passes list above the empty "Odds not posted yet" cards.

**Clemson @ Cal, 2026-09-25 7:30 PM PT (checked ~7:55 AM PT):** DraftKings CLEM −130 / CAL +110 (opened −115 / −105, so money is moving to Clemson), spread CLEM −2.5, total 51.5. Devigged fair: Clemson 54.3%, Cal 45.7%. Polymarket (`cfb-clmsn-cah-2026-09-25`, $665k liquidity): Clemson bid .55 / ask .56, so Cal costs .45. Edge: Clemson −1.7pt, Cal +0.7pt before costs, so **PASS**; the market agrees within ~1pt. The Grok app's earlier "LEAN CALIFORNIA 63%" was ~17pt off.
**NEW BUG FOUND (verified): Polymarket CFB slugs don't use ESPN abbreviations.** This game is `cfb-clmsn-cah-…` (CLEM→clmsn, CAL→cah), so the Base44 app's slug lookup (ESPN abbrs, aliases only for MLB) can't match college games, and every NCAAF card will say "No live Polymarket price". Fix options: a `public-search` fallback by team names with the `startTime`-within-3h + not-closed guards, or a verified CFB alias table. Not fixed yet.

## Grok board measured + v5 redesign prompt (2026-10-05)
Baseline numbers, the problems seen and the Patch 3 prompt are in [[PolyEdge Upgrade Prompt v4]] (Patch 3) and `PolyEdge v5 Redesign Prompt (Grok).txt`. Base44 (main board) was not touched; Adam's request targeted the Grok board.

## Related
[[Jarvis Remote Control]] — the other Grok-hosted app, and the reason the `.grok.me` URL pattern is familiar.

## Revamp v3 spec (Adam, 2026-09-29 ~12:30 AM PT) — DECIDED, building
Adam's new spec: mobile-first pick board (iPhone, one column, 44px+ tap targets, never places bets). Sticky bar with search, All/MLB/NFL/NHL/CFB chips (last choice remembered) and Today/Tomorrow/Week. Home order: LIVE NOW → Top Picks → date-headed games → collapsed Passes. Compact cards (PT time, full names, pick, model vs market, gap, tier), expandable detail. "Sports Xs ago · Market Ys ago" plus STALE→PASS (pregame >15 min, live >60 s). Live needs a live price + score + clock or it's a PASS. LIVE NOW tab with SNIPE (late game, leader ≥80% live win, ≥5 pts over price, data <60 s, no pause/score-price lag) and "SMALL UPSIDE" at ≥90¢. Immutable pick snapshots; RECORD tab grading picks AND passes (hit rate/ROI by tier and sport); Polymarket CSV upload with real P&L. Tiers: Small ≥+6 gap / conf 55+, Moderate ≥+8 / conf 55+, Lean ≥+10 with conf <55 or model-only. MLB with no starter → at most LEAN + "Starter TBD". Confidence = data quality only.
**Conflict surfaced:** the spec's team-stats model (records/form/home/diff/SP from a 50% base) is the approach the 2026-09-25 backtest showed loses to the market (log-loss 0.688 vs 0.678; the Jaguars +17 error). **Adam's decision:** upgrade the existing app `6aae5695dbc22f6715196ad4` to the v3 layout/features, **keep market-as-prior as the engine**, show his team-stats estimate on each card as a second number, and have RECORD grade both side by side.

## v3 BUILT 2026-09-29 ~1:10 AM PT — status: LIVE (Adam published it himself 1:32 AM PT, checkpoint 6abb72265b9b0a962af9df0c, public_without_login confirmed via API)
Checkpoints `6abb70a70c834191e09a9087` → `6abb72265b9b0a962af9df0c` (final). Preview only; the live URL `https://poly-edge-terminal.base44.app` still serves the old UI until a deploy. Backend functions went live on commit.
**Architecture (all verified live):**
- **Browser fetches** ESPN (one `?dates=` day per call; ranges return HTTP 400; CFB needs `groups=80`; MLB postseason needs explicit dates), Polymarket, and the CLOB. Code: `src/lib/{espn,markets,engine,lines,store,record,time,filters}`.
- **Polymarket discovery:** `gamma /markets?sports_market_types=moneyline&tag_id=<MLB 100381 | NFL 450 | NHL 899 | CFB 100351>&closed=false&order=gameStartTime&ascending=true&game_start_date_min/max`. `order=gameStartTime` is required (without it the NFL tag returns 100 season-series markets first). The `/events` listing is 30–40 MB per league: never use it from a phone. Matching = both outcome names match both teams + kickoff within 3h; a tie = unsure = null. Fixes found in testing: dedupe repeated slugs (cfb-templ-sfl listed twice), strip accents (San José St, Montréal), verified alias `louisiana monroe → ul monroe`. Live test: MLB 12/16 (the 4 misses are TBD playoff games), NFL 1/1, NHL 32/34, CFB 54/59 (misses have no market).
- **Prices:** `POST clob.polymarket.com/prices [{token_id, side:"SELL"}]`. SELL returns the best ASK = the buy price (BUY returns the bid). CORS open. 60s pregame, 15s live.
- **Books:** `getLines` function (public) → Odds API consensus, now incl. NHL; 4h cache, 15/day cap; 487 credits left at build time. ESPN DraftKings line as fallback.
- **Engine unchanged in spirit (market as prior):** favored side by books; gap = books − Polymarket ask; tiers on the net edge (0.5pt cost): MODERATE ≥3, SMALL ≥2 (both need conf ≥55 + multi-book + books within 4pt), LEAN ≥1; >8pt = PRICE SUSPECT; <$5k liquidity = PASS. No Polymarket = "Model only" (engine PASS). MLB no starter → max LEAN + "Starter TBD". STALE (pregame >15 min, live >60s) → forced PASS.
- **Team model (Adam's spec, second line, own RECORD track):** records regressed to .500, differential/game, last-10 form, home field, MLB starter ERA; spec tiers exactly (Small ≥6/conf 55, Moderate ≥8/conf 55, Lean ≥10 or model-only). When books are unavailable the headline falls back to it, capped at LEAN, and the **locked 8-pt gate** applies (MODEL SUSPECT → PASS); first render showed White Sox +14.6 / Braves +8.0 leans from it, now blocked.
- **Confidence** = data quality only: ESPN confirmed 30, standings 15, injuries 15 (CFB feed has ~1 item → counts as unavailable), MLB starters 15, sharp line 15 (single book 9), fresh 10; normalized to 100.
- **Live:** score/time-only win % (normal on the final margin with a one-possession floor; checked vs published tables, e.g. NFL up 7 with 5:00 = 88%, NHL P3 10:00 up 1 = 79%, MLB top 7 up 3 = 89%). SNIPE only when late (MLB 7th+, NFL/CFB Q4, NHL P3+), leader ≥80%, ≥5pt over the ask, both feeds <60s, not paused (halftime/end period/delay), and the price has moved since the last score change. Ask ≥90¢ → "SMALL UPSIDE · max return X%".
- **Record:** `Snapshot` (write-once; RLS update/delete locked; server timestamp) and `Grade` entities via public functions `savePicks` / `saveFinals` (server re-reads ESPN summary directly or via proxy → `verified`; only games with a saved call get graded) / `getRecord`. Tracks: engine, team, snipe, pass. ROI = 1u at the saved Polymarket price. CSV P&L is parsed and stored on the device only (localStorage), matched by both teams + date.
- **No login:** auth pages, AuthContext and ProtectedRoute removed. The app's `public_settings` must be switched to `public_without_login` at deploy time; flipping it before the deploy would just show visitors the old login page.
- Removed: old Live/Discover/Watchlist/Track/Sources pages, buildModel/gradePicks/askPolyEdge functions (the LLM news signal is gone), old shared model/polymarket/espn. The legacy `Pick` ledger (old model's records) and `Watchlist` entity were kept, unused.
- Interpretation calls, flagged to Adam: the spec's "score the side the model favors" is followed literally (so underdog price edges show as negative gaps = PASS); engine without a Polymarket price = PASS labelled "Model only" (it has no edge to measure), while the team track applies the spec's model-only LEAN.
**Tested:** eslint clean, production build OK; functions tested live without writing fake ledger data; iPhone 390px CDP emulation: no horizontal scroll on any tab, every tap target ≥44px. The first preview render already saved real calls (3 team-model, 10 passes).
**Test harness (repeatable):** `~/pe_cdp/drive.mjs <outdir>` drives headless Chrome over CDP at iPhone size (Node 24 has a built-in WebSocket). Plain `chrome --headless --window-size=390` can't go below ~500px wide on Windows, and ESPN blocks the HeadlessChrome UA, so set an iPhone UA.
**Update 2026-09-29 1:40 AM PT — LIVE (deployed by Jarvis via the platform API, checkpoint `6abb793d6e016bc73acf91f9`):** Adam saw "137 passes" (Week view) and said "Do it" to scoring the side with the bigger edge. The **engine now scores whichever side has the larger books-fair − Polymarket-ask gap** (it was the favorite only, so underpriced underdogs showed as negative gaps = PASS). The team model still scores its favorite, per the spec. Pass rows show their best side + gap, and the Passes header counts the small positive gaps. Live week check after the change: NFL Rams @ Eagles **MODERATE on the Eagles** (3-book consensus 42.8% vs 39¢, +3.8), MLB Cubs @ Padres LEAN on the Cubs (9-book 46.5% vs 45¢), Yankees LEAN (team fallback, +6.3), 1 CFB LEAN; the White Sox +14.6 / Braves +8.0 team-fallback outliers are still blocked by the 8-pt gate. Deploys now work from the MCP token: `POST /api/apps/{id}/deploy {checkpoint_id}`.
**Update 2026-09-29 1:52 AM PT — Tiers v2 LIVE (checkpoint `6abb7c30d33c058bd122036a`, deployed):** Adam's rules, verbatim intent: gap = model % − Polymarket **best ask** (no separate cost deduction for tiers). **Books edge:** Moderate = gap 3+ with 5+ books; Small = gap 2+ with 5+ books; fewer than 5 books caps at Lean (a 2+ gap with <5 books = Lean; 1.5–2 with <5 books = PASS); Lean = 1.5+ with 5+ books. **Team model:** Lean only, at gap 2.5+. Existing caps kept (conf <55, books >4 pts apart, MLB starter TBD, stale, 8-pt gate). Each card is labelled "Books edge" or "Team model"; the headline is the Books edge call, else a Team model Lean, else PASS. **Split** = the two favor opposite teams → tag + cap at Lean. RECORD tracks renamed "Books edge" / "Team model" (graded separately, whichever one headlines; retired tiers still listed if calls exist). Pass rows are two lines: date · time PT · sport, then the full matchup. The 8-pt gate on the team model now also checks against the books when there is no Polymarket price (Temple @ USF was +15 vs the books and slipped through). Week slate after the change: Books edge Leans on the Cubs (9 books, +1.52, Split), the Eagles (3 books, +3.8, capped), Wyoming (+1.7, Split) and 1 more; Team model Leans on 6 games, most of them Split. **Cubs stays LEAN, not PASS:** its gap is +1.52 with 9 books, above the 1.5 line, and Split caps at Lean but doesn't pass.
**Open with Adam:** does he bet on Polymarket US? The board prices come from international Polymarket (gamma/clob), which is restricted for US users. If his US-app price for the same game (e.g. the Cubs) differs, the board has to pull from the US app instead.
**Update 2026-09-29 2:08 AM PT — prices now from POLYMARKET US (deployed, checkpoint `6abb7fc6234ea87d842c8852`):** Adam bets in the Polymarket US app, which is a SEPARATE order book (Cubs 46¢ on US vs 45¢ international at the same moment; his app matched the US numbers exactly). Verified:
- Public gateway `https://gateway.polymarket.us`, no key, CORS open. The US game slug = the international slug with `aec-` in front (checked MLB/NHL/NFL/CFB). Games missing on US (e.g. Steelers–Browns) get no market.
- **Batched read:** `GET /v1/markets?limit=100&slug=aec-a&slug=aec-b…` (60 slugs → 59 back in 0.6s, ~5 KB each). `marketSides[].price` = each team's BUY price (the long side's best ask, and 1 − best bid for the other), identical to `/v1/markets/{slug}/bbo` and to the app's buttons. `long:true` = first-listed (away) team, but matched by NAME every time.
- **Rate limit:** ~4 quick requests, then HTTP 429 with `retry-after: 10`. The per-game `/bbo` is unusable for a board; everything is batched (≤60 per call, 2.5s apart; live 15s, pregame 60s, "not on US" rechecked every 30 min).
- The `/v1/markets` listing itself is dominated by futures/props (1,000 open "sports" markets, 43 games), so games are looked up by slug, never listed. The listing filter needs `sportsMarketTypes=SPORTS_MARKET_TYPE_MONEYLINE` (plain `MONEYLINE` = HTTP 400).
- The international gamma listing is still used to IDENTIFY games (names + kickoff); the CLOB price code was removed.
- Full live check at US prices: MLB 8/8, NFL 12/12, NHL 21/21, CFB 56/57 priced with verified sides. Every MLB game on 9/29 is a Books-edge PASS (Cubs +0.52, White Sox −0.2 at 46.5¢); the week's Books-edge Leans are all CFB longshots (5–16%), all Split.
**Twitter/X:** Adam asked to "use twitter also for live updates and sources", sent github.com/d60/twikit, then said "Don't use" (read as: not twikit). Twikit is an unofficial Python scraper that logs in with an X account (ToS risk, account-ban risk, needs his X password, can't run in a browser or the Base44 worker). The official X API read access is paid. **Dropped (Adam, 2026-09-29 ~2:10 AM: "No" to pricing the paid X API).** Reason given: breaking news reprices Polymarket and the books within seconds, before a tweet scanner could act.

**Decision 2026-09-29 ~2:15 AM PT (Adam):** the **Base44 board is the main board.** The old Grok board's "market" numbers are wrong: at 1:43 AM Adam saw the Braves at 63.5¢ (buy 64¢) while the Grok board showed 51% (+8), and the Yankees at 55.5¢ vs its 51% (+7). Its fresh-looking "Market 3.4s ago" labels sit on a wrong number (likely the wrong outcome or a stale snapshot), which probably explains the Eagles-type losses. **Don't rebuild the Grok board on Wednesday unless its market feed is fixed first.** 
**Strong favorite tier LIVE 2026-09-29 2:24 AM PT (checkpoint `6abb83c5e72c876e2d96d6e5`):** Adam's spec. Green tier, separate from Pick/Lean, shown only when ALL hold: both engines favor the same team (books' favorite = the team model's side); books no-vig fair 60–80% with 5+ books; US best ask 60–80¢ and at or below fair (gap ≥0); fresh, pregame; MLB starters listed. With no books, MLB/NFL may use the Team model alone, but that card caps at Lean (flag "Strong favorite · books missing"; still 8-pt gated). Card: "{team} · Strong favorite · X% to win · price Y¢ · gap Z". Top Picks: Picks/Leans first, then Strong favorites. Own RECORD track ("strong" / tier STRONG; Snapshot enums extended). Passes exclude strong-favorite games. At deploy, 0 games qualified: every 60–80% favorite missed one rule (Braves 63.5¢ vs fair 63.3; Air Force 59.5¢ < 60¢; Chiefs team model disagrees; Bills/Seahawks/Wisconsin priced 0.5–1.6¢ over fair). Favorites usually trade slightly over fair, so expect this tier to be rare.
**CORRECTION 2026-09-29 2:30 AM PT (checked against Polymarket US + a 9-book consensus):** the Grok board's MARKET numbers are right. Its "Braves 51%" and "Yankees 51%" cards are **Wednesday 9/30** games (US: Braves 50.5¢, Yankees 51.0¢). The 63.5¢ Braves price in the note was **Tuesday's** game (Sale starting). The Grok board's real problem is its **model**. Its NFL picks sit 10–14 pts off BOTH the books and Polymarket, which agree with each other within ~1 pt: Cowboys 58% vs books 43.8 / US 44¢; Jaguars 56% vs 42.9 / 43.5¢; Giants 58% vs 49.0 / 48.5¢; 49ers 62% vs 57.4 / 57.2¢. That's the same failure as the Jaguars +17 case. Base44 stays the main board, for this reason; the Grok board would need its MODEL fixed (market as prior), not its feed. Base44's own read of the same games: Wed Braves = MODEL SUSPECT (team model 60% vs 50.5¢, >8 pts, no books line yet); Wed Yankees = Team model Lean +6.3; the NFL games = PASS (books edge ≤1 pt).
**Grok board market page read 2026-09-29 2:33 AM PT** (`pine-bolt-prairie-brook.grok.me/market/aec-mlb-phi-atl-2026-09-30`, the current Grok URL, rendered at iPhone size): Braves 59% vs market 51%, "+8 pts, MODERATE PICK, confidence 58, DATA VERIFIED ✓". Its own breakdown: "Net model view PolyEdge 41% / Market 50% / gap −8.3" (the same number from the Phillies' side, so it's labeling, not a contradiction), built from factors home +4.0, run differential +3.8, team strength +1.4, injuries −0.4, "Other factors · 6 unavailable". That's still the additive 50%-prior model from the 9/18 review, with **no starting pitchers** (both probables TBD for Wednesday) and no sportsbook line, stamped as verified. Market quality 99/100 and a 0.5¢ spread; the market price (~50.5¢) is correct. It now has an "X INTELLIGENCE / Grok/X" panel (showing no input).
**Security 2026-09-29 ~2:45 AM PT:** Adam pasted a Polymarket US API key ID and its **private key** into the terminal chat. Values NOT stored anywhere and NOT used. Per docs.polymarket.us: key ID → `X-PM-Access-Key`, secret = base64 Ed25519 private key, requests signed with `X-PM-Timestamp` + `X-PM-Signature`; **no read-only scopes are documented**, so the key can trade. Told Adam to revoke it at polymarket.us/developer. Recommendation: don't put a trading key into the public, no-login PolyEdge app (any server function exposing his history would be readable by anyone with the link); use History screenshots for the ledger instead.
**2:47 AM:** Adam: "Forget api". No Polymarket US API integration. The exposed key's revocation isn't confirmed; it's still flagged to him. Ledger via History screenshots if he wants one.

## Decision engine spec (Adam, 2026-10-02 ~9:20 PM PT) — REVIEWED, awaiting go
Adam's 32-section spec: rebuild PolyEdge as a disciplined decision engine for NFL/NBA/MLB/NHL. Fewer, better decisions. Probability and confidence are scored separately (0–100 bands). CRITICAL/IMPORTANT/SUPPLEMENTAL inputs, each VERIFIED/PROJECTED/STALE/MISSING with a timestamp, and a missing critical input → WAITING FOR DATA / PASS. Multi-book devigged consensus, a market-quality score, fair odds, a **max buy price** with a safety margin (VALUE / MARGINAL / VALUE GONE), and rules-based PASS/LEAN/PLAY/STRONG PLAY. Factor contributions are shown in points from a BASE MARKET with factor caps. Separate engines per sport (NHL goalie/GSAx/5v5 xG, MLB SP xERA/FIP/SIERA + bullpen fatigue, NFL QB/EPA/CPOE, NBA lineups/on-off). Also: injury impact (UNKNOWN, never 0), rest/travel, line movement + CLV, calibration buckets, edge buckets, per-sport/market records, EWMA recency + outlier regression, a market-disagreement alert, factor agreement, an uncertainty range, "what changes the pick", pregame rechecks with change-only notifications, DATA COMPLETE/PARTIAL/STALE/WAITING badges, a reproducible snapshot with model version, backtest/out-of-sample weights, and Brier/log-loss.
**Jarvis review:** it's consistent with the locked market-as-prior engine (its "BASE MARKET + factors" layout is the same thing). Pushback:
1. The 2026-09-25 backtest found team stats add ~0 once the price is known, so factor weights have to start small and capped (a few pts total) until each sport's backtest earns more. +6–7 pt edges will be rare, and that's correct.
2. Odds API budget: rechecks + opening/closing lines for CLV + market quality across 4 sports won't fit 500 free credits/mo. Paid 20K = $30/mo.
3. Adam trades Polymarket US in cents, so the max buy price shows in ¢ alongside the American odds.
4. Polymarket US is mainly moneyline, so the spread/total tracks are skipped unless he bets them.
5. Notifications need a channel, since the app is public with no login.
6. Data sources are mostly free, but the deep stats (GSAx, SIERA, EPA, on/off) have to be sourced per sport.
**Proposed phases:** (1) engine: per-sport factor engines on the market prior, input statuses, confidence, uncertainty range, fair odds / max buy, tiers, the disagreement alert, what-changes, versioned snapshots, new card; (2) market: line movement, open/close capture, CLV, rechecks + notifications; (3) proof: calibration/edge buckets, Brier/log-loss, per-sport backtests to set the weights.
**Sharks card check (Adam's screenshot of the Grok board, 8:54 PM PT 10/02; checked ~9:30 PM):** Kings @ Sharks, Sat 10/3 7:00 PM PT, regular season. Grok card: LEAN Sharks 59% vs Polymarket 52%, +7, "Model only", confidence 19, books "—". **Measured:** DraftKings (via ESPN) SJ −120 / LA +100, unchanged since open, devigged = **Sharks 52.2%**. Polymarket US buy prices: Sharks 53¢, Kings 48¢. The books and Polymarket agree within ~1 pt. At 53¢ the Sharks cost ~0.8 pt MORE than fair, so the edge is negative = **PASS**. The +7 is the 50%-prior model's own error again (the same failure as the Jaguars +17 case). The spec's example numbers (52.2% books) are this exact game. Its factor values (goalie +2.4 etc.) are illustrative, not measured.

## v4 decision engine BUILT on Base44 (2026-10-02 ~9:15–9:55 PM PT) — status: LIVE (Adam: "yes"; published 2026-10-02 10:00 PM PT, checkpoint 6ac08a3b, public_without_login)
Adam: "fix the base 44 poly edge to" (his go for code edits, per the 9/29 Base44-main-board decision). Checkpoints `6ac0876d1475526e760216ec` → `6ac08a3b5d27d557bdd49f05` (final).
**Engine (`src/lib/model.js`, new):** p_model = sigmoid(logit(books no-vig consensus) + sport factors), each factor capped at ±0.08 logit and all of them together at ±0.15 (~2 / ~3.7 pts). Factors wired: MLB starter FIP (MLB Stats API, regressed with 50 IP of ballast, ×0.06 logit per run), and NHL/NBA rest (back-to-back, 3-in-4, from the 4 prior days of ESPN scores). These are shown as "in the price" and not added: home field, records/differential, form, injuries listed OUT. Questionable/GTD injuries lower confidence, and their impact shows as UNKNOWN. Inputs are CRITICAL / IMPORTANT / SUPPLEMENTAL with VERIFIED / PROJECTED / STALE / MISSING statuses:
- MLB probables come from MLB's official list (VERIFIED), and lineups are CRITICAL.
- NHL goalies come from ESPN probables, so they're always PROJECTED: NHL caps at LEAN with "WAIT FOR GOALIE CONFIRMATION".
- NBA lineups are PROJECTED (no feed).
- NFL QB health comes from the injury report.
- CFB QB is IMPORTANT only (no feed).

Confidence starts at 100 and subtracts:
- −10: this version isn't validated yet
- −15 per projected critical input
- −10 per missing important input
- books: one book −20, 2–4 books −10
- −15 if the books disagree by more than 3 pts
- −15 early season
- −15 if one factor drives most of the move
- up to −15 for Q/GTD players

A missing critical input caps confidence at 30. Range = model ± (2 + 0.08 × (100 − conf)). Max buy = model − max(1.5, 0.25 × range width). Price status: VALUE, MARGINAL (up to 1.5¢ over max buy), VALUE GONE.

Tiers:
- LEAN: edge ≥1.5, conf ≥40, VALUE or MARGINAL.
- PLAY: edge ≥3, conf ≥60, 3+ books within 3 pts, no projected or missing critical input, VALUE.
- STRONG PLAY: locked (shown as PLAY) until a version validates.
- WAITING (with "LEAN/PLAY possible"): a critical input is still coming.

PASS gates: stale, no US market, price suspect (>8 pts from the books), liquidity under $5k, model suspect, and **price outside 15–85¢**. That band was added after the first preview, where all 5 leans were 4–19¢ longshots; an even vig split overstates longshots. A model-vs-books disagreement over 5 pts caps the call at LEAN. Both sides are evaluated. Each card gets what-changes-this lines plus a spec-style summary sentence. The strong-favorite tag is kept, now on the v4 numbers (it no longer needs the team model).
**Retired:** the records-based team model, Books-edge MODERATE/SMALL tiers, the standings fetch (`engine.js` is now live-only; `lines.js` devigs via model.js).
**Data/feeds:**
- NBA added: ESPN basketball/nba, Polymarket tag 745, Odds API basketball_nba.
- MLB Stats API (`statsapi.mlb.com`, CORS open) supplies probables, season lines and lineups.
- The ESPN scoreboard's DK open + current line drives line movement.
- Lines only fetch for leagues with games still to play, and they **wait for the first ESPN slate**. Bug found: the first tick fired before games loaded and pulled MLB only, so every card read 1 book.

**Record:**
- Snapshot gets track `v4` and tiers SEEN / LEAN / PLAY / PRED (PRED = first read within 90 min of the start, used for calibration).
- New Snapshot fields: model_version, books_pct/n, max_buy, range, price_status, market_quality, and a `detail` JSON (inputs, factor steps, confidence items, quality, line move, prices).
- Grade gets open/close moneylines from the ESPN summary `pickcenter` (verified on a final NHL game). Fallback: the board's last-seen pregame line ("device-last"). It also stores the last Polymarket ask.
- Record tab, per model version: plays W-L, ROI, average CLV, % beat close, Brier + log loss (model vs books vs Polymarket), calibration buckets, edge buckets, and a VALIDATED flag (100+ graded, Brier ≤ books, CLV > 0). Old tracks sit under "Earlier versions".
- **Fixed:** the board marked snapshots as sent even when the server saved 0. Now only server-confirmed keys count.

**Verified:**
- Model unit tests: Kings @ Sharks → PASS (Kings side −0.2); devig −150/+130 = 57.98/42.02; factor cap = 2.00 pts max; no books → WAITING; MLB starter missing → WAITING at conf 30; a cheap underdog gets evaluated; the PLAY path works.
- Lint: 0 errors. Build OK.
- iPhone 390px preview: no sideways scroll, every tap target ≥44px, 3 LEANs out of 96 priced games (the CFB 9-book consensus now reaches the cards).
**Winning method (bank it):** backend functions on this app do NOT go live on a checkpoint. The preview calls the LIVE functions: getRecord had no new fields, and savePicks returned saved:0 for v4. Deploy them with `POST /api/apps/{id}/coding/redeploy-function/{name}` {code}, or publish. Dead end to skip: assuming "functions go live on commit" (true on 9/29, not now). Debugging tip: headless runs MUST set the iPhone UA, because ESPN blocks HeadlessChrome and the board then shows 0 games. Harness: `~/pe_cdp/v4.mjs` (cards) + `net3.mjs` (captures function requests and responses).
**LIVE 2026-10-02 10:00 PM PT:** Adam said "yes". `POST /deploy {checkpoint_id: 6ac08a3b…}` published the board AND redeployed all 4 functions; no separate redeploy-function call was needed. Verified: getRecord returns modelVersion/closeHome, getLines returns NBA (5 books), and loading the live board saved v4 SEEN snapshots ("PolyEdge MLB v4.0" with 9 books, "PolyEdge NHL v4.0" with 5 books, max_buy and price_status filled). The NFL card still read 1 book in the preview because the live getLines served cached NFL lines from 10/01.
**Grok board (`pine-crane-meadow-cactus.grok.me`), Adam's screenshots 9:38 PM:** the v4 prompt is applied and the fake picks are gone, but 5 bugs remain:
1. "Waiting for books" even though ESPN has DK lines (IND −205 / WSH +170 → 64.5/35.5; ARI −142 / NYG +120 → 56.3/43.7).
2. PASS and waiting shown as two statuses on one card.
3. A live game still sits on a pregame card ("re-check 11 AM").
4. "Confidence 0".
5. Rest listed as missing.

Patch prompt sent to Adam (text in [[PolyEdge Upgrade Prompt v4]] → Patch 1).

## Favorite-longshot finding: switch the vig removal to the POWER method (2026-10-02 ~10:15 PM PT) — LIVE on Base44 (Adam: "Yes"; deployed 2026-10-02 10:17 PM PT, checkpoint 6ac08fce910f3e65fb93de40)
Adam's screenshots of the Grok board after Patch 1 (`cabin-velvet-bolt-forge.grok.me`, the URL changed again): the books now load (the ESPN fallback works) and there's one status per card, but every LEAN is an underdog at 5–23¢ on one book. The board's math matches ESPN (proportional devig is computed correctly). The problem is the method: books load their margin onto longshots, so splitting it evenly overstates the dog. Base44 v4 showed the same thing (Buffalo LEAN on a 9-book proportional consensus).
| Underdog | ML | Proportional | Power | Shin | Polymarket ask |
|---|---|---|---|---|---|
| Merrimack @ Yale | +361 / −510 | 20.6 | 18.1 | 19.0 | 18¢ |
| Elon @ UNH (UNH) | −415 / +304 | 23.5 | 21.3 | 22.1 | 21¢ |
| WMU @ Buffalo (BUF) | −535 / +400 | 19.2 | 17.1 | 17.9 | 17¢ |
| MIA @ MIN (MIA) | +410 / −550 | 18.8 | 16.7 | 17.5 | 17¢ |
| Vandy @ UGA | +1400 / −3200 | 6.4 | 3.7 | 4.8 | 5¢ |
Polymarket sits within 0.3 pts of the power-method number on 4 of 5 (Vanderbilt is 1.3 under: 3.7 vs 5¢). With power, every "edge" lands between −1.3 and +0.3, so all PASS. Power method: find k ≥ 1 with a^k + h^k = 1 (bisection), fair = a^k / h^k. Near-even games barely move (−120/+100 → 52.3/47.7 vs 52.2 proportional). **Grok Patch 2 sent** (text in [[PolyEdge Upgrade Prompt v4]]): power devig everywhere, 15–85¢ band, 1-book confidence cap 55. **Base44 done:** `powerDevig` in model.js (used by devig → lines.js ESPN fallback, line movement, record closeFair) and in oddsapi.ts per-book before the median. The cache key moved to `oddsapi:pw:<sport>` so the old proportional cache can't linger. Tested: +400/−535 → 17.13/82.87, −120/+100 → 52.32/47.68, the Buffalo case PASS (+0.1), the Sharks case PASS. Verified live: the 9-book CFB consensus has Buffalo at 17.1% (was 19.2%); NFL Dolphins @ Vikings MIN 84.7% on 9 books (MIA 15.3% vs 17¢ = negative edge). Odds API 486 credits left.

## SportsGameOdds as the odds source — requested 2026-10-02 ~10:50 PM PT, on hold for plan/budget
Adam's spec: SportsGameOdds API (key in env `SPORTSGAMEODDS_API_KEY`, never displayed); NFL/NBA/MLB/NHL/NCAAF full-game moneyline from every US book; devig per book (byBookmaker, not their consensus); 10-min cache; batch per league; "Books unavailable" on a limit/outage, never 0%; ESPN/DraftKings stays as the fallback.
**Verified from their docs (2026-10-02):** base `https://api.sportsgameodds.com/v2`, header `x-api-key`; `GET /events?leagueID=NFL,NBA,MLB,NHL,NCAAF&oddsAvailable=true&oddID=points-home-game-ml-home,...`; odds at `event.odds.<oddID>.byBookmaker.<bookmakerID>` with `american`, `available`, `lastUpdatedAt`; teams `teams.home.names.long`; start `status.startsAt`; paging via `nextCursor`. **Billing is per OBJECT = per event returned** (one game with 20 books and 100 markets = 1 object). Plans: Amateur free = 10 req/min, **2,500 objects/month**, 9 books, 10-min updates; Rookie $99/mo = 100k objects, 77 books, 3-min; Pro $299/mo = unlimited, 82 books.
**Budget math:** ~100–150 upcoming events across 5 leagues on a 10-min refresh ≈ 15–20k objects/DAY. The free tier lasts well under a day; Rookie ($99) covers roughly one full refresh every ~45–60 min, not every 10. The spec's 10-minute cadence across all 5 leagues effectively needs Pro, or a narrower window (only games starting in the next ~24h, and only when someone has the board open).
Base44 secret check: only `ODDS_API_KEY` exists; `SPORTSGAMEODDS_API_KEY` is not set yet (Adam enters it himself).
**Adam: "Free" (2026-10-02 ~10:55 PM).** Free = 2,500 games/month ≈ 83/day, so SportsGameOdds can't be the main source (one refresh of all 5 leagues ≈ 100–150 games). The Odds API free tier is far better value for the slate: 1 request = every game in a league with ~9 books (500 requests/month). Recommendation given: keep The Odds API as the main consensus and use SportsGameOdds free as a targeted second opinion, only for LEAN/PLAY candidates inside ~3h of start, plus their closing line (~20–40 games/day, under budget). Awaiting Adam's pick.
**Adam: "Yes 20-40" → BUILT 2026-10-02 ~11:15 PM PT as a targeted second opinion (checkpoint saved, NOT deployed, no key yet).**
- `base44/shared/sgo.ts` + function `getSgo`: games ≤10 per call. Known eventIDs are refetched in one `eventIDs=` request (1 object each). Unknown games: one request per (league, kickoff ±10 min) with `limit` capped by what's left today, so games sharing a kickoff resolve together; matched by team names (long/medium/short) + start within 3h. Per book: `byBookmaker[id].odds` (falls back to `.american`), unavailable books skipped, power devig. 10-min cache per game (`sgo:g:<espnId>`). Hard caps 80/day and 2,400/month counted from the events actually returned (`sgo:day:` / `sgo:month:` in DataCache). No key / 429 / outage → status offline/paused, board keeps running.
- Board (`store.jsx`): candidates = LEAN, PLAY, or WAITING-with-provisional, starting within 180 min; checked in 3 phases (when it first qualifies; ≤60 min; ≤15 min = closing), max 10 per minute. The feeds footer shows SportsGameOdds status + today/month usage.
- `lines.js fairFor`: merges per-book numbers from The Odds API (`consensus().perBook`, newly returned) and SportsGameOdds, deduped by book (aliases: williamhill_us→caesars, mybookieag→mybookie, betonlineag→betonline); where both have a book, SGO's fresher number wins; median + spread over the union; source label "N-book consensus (Odds API + SportsGameOdds)". ESPN DK stays the fallback. (The Odds API cache from before this change lacks perBook until its 4h TTL rolls.)
- Tests: lint 0 errors, build OK, offline parse test on a docs-shaped event (DK +400/−535 → 17.13; unavailable book skipped). Not testable live until Adam adds the secret.
- Next: Adam adds Base44 secret `SPORTSGAMEODDS_API_KEY` himself (Dashboard → Settings → Secrets), then deploy + live check.
**LIVE 2026-10-02 11:55 PM PT.** Adam couldn't add the secret in the dashboard, so he pasted the key in chat. Jarvis stored it with `POST /api/apps/{id}/secrets` (Base44 shows it masked; the value is NOT in the vault). Then deployed checkpoint `6ac0a3b245827ca2bfaef6ff` (getSgo is live). **Live test:** White Sox @ Guardians (ESPN 401907990) → eventID `O85ZMMPsGPxGKp9xnAPS`, **9 books** (draftkings, fanduel, betmgm, unibet, williamhill, bovada, espnbet, pointsbet, caesars), Cleveland 58.3–60.1% per book after power devig; cost **1 object** (usedToday 1/80, month 1/2,400). Note: SGO lists `williamhill` and `caesars` as separate IDs; the merge alias folds them into one book (same US operator), so they count as 1. The key passed through chat: regenerate it on SportsGameOdds and re-set the secret if Adam wants it out of the transcript.

## v5 redesign + speed pass on Base44 (built 2026-10-05, CHECKPOINTED 6ac35bdfc22e42b553e37cb1 (the platform labels it with the old name 'SportsGameOdds API Active'), NOT YET DEPLOYED - waiting on Adam's OK)
Engine untouched (model, tiers, power devig, 15-85c band, confidence, max buy, snapshots, record: same numbers). Look: new tokens (bg #0A0E14, tier colors play mint / lean amber / waiting blue / pass slate), Inter + JetBrains Mono (numbers) + Space Grotesk, normal-case team names, solid surfaces (blur only on header and nav). Header 92px sticky (brand, feed dot + "updated Xs ago", search icon, scrollable sport chips), day control + four tap-to-filter tiles (Play/Lean/Waiting/Pass) below. PLAY/LEAN get a full card with a price ladder (Model / Books / Polymarket markers, edge pill, max buy vs now); everything else is a compact row (40 shown, "Show more"); detail sections are folded. Opaque 3-tab nav, Live and Record lazy-loaded.
Speed: root cause of the ~11 s first price was the 5 s timer gating market match -> price fetch; each feed finishing now triggers the next step (120 ms coalesced). Also: shared 10 s clock for age labels (cards no longer re-evaluate every 5 s), 30 s slate tick, cards evaluated at real time (keeps SNIPE/STALE age gates exact), pause when tab hidden, yesterday/rest/injury feeds wait for first prices, lazy snapshot JSON, memoized cards, ESPN logos via combiner at 72px (66 KB -> 4 KB each), preconnects.
Measured on preview (dev server, so JS weight not comparable): first price ~1.2 s after first paint (baseline ~10 s after), idle 45 s = 2 requests / 1 KB (baseline 9-12 / 47-61 KB). Production numbers to be taken after deploy. Files: index.html, tailwind.config.js, src/index.css, App.jsx, Layout, TopBar, GameCard, bits, Board, LiveNow, store.jsx, espn.js, time.js, new lib/useNow.js. Rollback: previous checkpoint 6ac0a3b245827ca2bfaef6ff.

### v5 production measurement (live, 3 runs, iPhone 390px headless, 2026-10-05)
First price **3.5 s median (3.5 / 3.5 / 4.8) vs 11.1 s before**. First content 1.5-2.3 s (was 1.2-1.8, no gain). Load 85 requests / ~1,480 KB (was 58 / 1,557: more requests because logos are individual lazy small files, bytes about the same; ESPN ~750 KB and gamma-api 285 KB dominate). Initial JS 151 KB (was 154). Idle 60 s: 12-15 requests / 61-66 KB (**no improvement** vs 9-12 / 47-61; my earlier preview reading of 2 requests was wrong). Long tasks 0-1, max 57 ms. DOM 525 nodes. **Steady-state cause:** ESPN today+tomorrow x 6 leagues re-polled every 60 s even with nothing live. Proposed fix (needs Adam's OK): poll a league's pregame slate every 5 min unless it has a live game.

### Parked ideas (2026-10-06, Adam: "Nvm for now"; nothing changed, v5 stays as deployed)
Live board checked: no bugs seen, first price ~3 s. Proposed, not built: (1) Sort toggle Time | Edge on the game list; (2) collapse "No Polymarket US market" rows into one fold; (3) group rows by start-time slot; (4) idle-traffic fix: re-poll a league's pregame slate every 5 min unless it has a live game (idle is 12-15 req / 61-66 KB per min today).

## 10/08 builder change (Adam, via the Base44 builder) + Jarvis review (2026-10-09 ~12:45 AM PT)
**Change found in the builder chat; it was not in the vault.** Base44 builder turn on 2026-10-08 ~1:59 PM PT (checkpoint `6ac804401cfccdc1677fa62e`, live). It added:
- An ESPN predictor factor (MLB/NFL/CFB): 0.35 × the logit gap vs the books, inside the existing caps, cached 30 min.
- The default window is now Today + Tomorrow.
- "Opportunity Radar" UI: near-triggers, "APPROACHING TRIGGER / ALMOST A LEAN" cards.
- **Looser gates:** LEAN 1.5→**1.2** pts and conf 40→**35**; a new WATCH at 0.3; price band 15–85¢→**10–90¢**; min liquidity $5k→**$2.5k**; strong favorite 60–80%→**58–85%** with 4+ books.

PLAY, STRONG PLAY, the stale/suspect/disagreement passes and the record are unchanged.

**BUG (verified 2026-10-09): CFB is priced from a 6-day-old Odds API pull.**
- DataCache `oddsapi:pw:americanfootball_ncaaf` was last written 2026-10-03 05:17 UTC (no `perBook` field, `remaining` 487). NFL/MLB/NHL caches are current.
- Each CFB refresh spends a credit, but the cache write fails silently (`setCached` swallows errors; likely the payload size, unconfirmed). The daily cap of 16 is hit every day (10/05–10/09).
- After the cap, the "using last pull" path serves the 10/03 snapshot, which carries early 2–3-book openers for the 10/10 games.
- Result: the Thursday 10/08 3:41 PM PT CFB LEANs are fake edges taken straight from that stale data. They're in the record as PENDING.

| Pick | Stale consensus | Fresh 9-book consensus | Polymarket |
|---|---|---|---|
| Florida | 86.8 (2 books) | 81.0 | 81¢ |
| Texas | 78.9 (3 books) | 74.6 | 74.5¢ |
| Oregon | 82.7 (3 books) | 80.5 | 79.5¢ |
| BYU | 85.4 (2 books) | 78.9 (1-book DK) | 78.5¢ |

The same stale data also produced the LSU, Indiana and Iowa LEANs. The 7-day stale window expires ~10/10 05:17 UTC; CFB then falls back to ESPN DK only.

**Other findings:**
- (a) Strong favorite = model ≈ market (gap 0.0–1.5): it isn't an edge, yet it's graded as a call. Celtics 58% / conf 30 and Lakers conf 25 qualified.
- (b) NBA preseason LEAN (Lakers, conf 35).
- (c) "88% of the way to a LEAN / needs 0.1¢" turns passes into near-bets; 0.1¢ is noise.
- (d) Record so far (v4): plays 8-9 across sports. CFB avg CLV +1.1 / 88.9% beat close (n=9) may be contaminated by the stale fair line. Too small to judge either way.

**Proposed fix (awaiting Adam's go):**
1. Make the cache write report failure, find the CFB write cause, and stop re-spending credits on a failed write.
2. Never serve lines older than ~6h as a fair line: STALE → PASS.
3. Exclude stale-source calls from the record.
**Workflow note (Adam, 2026-10-09):** "I'm using grok" = Adam writes the change prompts with Grok and runs them through the **Base44 builder on this same app**. That's why builder-made changes (like 10/08) don't show up in the vault. Before reviewing, always read the builder chat (`GET /api/apps/{id}/chat/full-conversation`, limit 2–3) for turns since the last vault entry.

**Decision 2026-10-12 ~4:15 PM PT (Adam: "Skip"):** a single-team fan pundit (Joe Torosian, a Rams Facebook Live show, ~3 viewers, pick "Rams 42, Bills 24") was proposed as a PolyEdge input and rejected. Reasons: no track record, a one-team homer bias, and the books already price what he knows. A Pundit RECORD track was offered and declined. Any future pundit has to clear the v4 VALIDATED bar (100+ graded picks, CLV > 0) before feeding the model, so only high-volume, multi-team pickers are worth tracking.

## Live audit + data-expansion plan (2026-10-20 ~2:40 PM PT) — findings verified, nothing changed
Adam: "Check out app base 44 poly edge and make it better, logically, with more opportunities" + "think of creative ways to get more data." Base44 connector was signed out (Adam re-authed; this session needs a restart to load the tools), so this is a read of the public live board (`~/pe_cdp/audit20.mjs`, output `~/pe_cdp/a20/`) — code and builder chat NOT yet read.
**Undocumented:** the board now runs **v4.1** (CFB/MLB/NBA/NFL/NHL v4.1 tracks on RECORD) — a builder change not in the vault. Read the builder chat before touching code.
**RECORD (v4.0, graded):** CFB 47-36, ROI −13.1%, CLV +0.5, beat close 47% (n=165 read) · NFL 11-5, +34.1%, CLV +1.3, 41% · NHL 7-4, +26.9%, CLV +1.5, 54.5% · MLB 4-3, +10.4%, CLV +0.1 · NBA 4-4, −0.7%, CLV −0.9, beat close 12.5%. CLV says NHL/NFL show signs of real edge; CFB is the biggest sample and is losing; NBA is losing to the close.
**Defects seen:**
1. **Live SNIPE is losing on fake gaps:** Nebraska @ Oregon SNIPE 80.2% vs 46¢ (+34.2) LOSS; Colts SNIPE 80.9% vs 71.5¢ (+9.4) LOSS. A score-and-clock-only win % can't see possession/field position; a 34-pt gap vs a liquid market is the model's error (same lesson as the pregame 8-pt gate).
2. NBA live card shows "Live win NaN%" (no NBA live model).
3. Strong favorite still graded as a call at gaps of 0.1–0.9 and conf 25–40 (flagged 10/09, still there).
4. Same game logged under several tiers (FIU LEAN 10/18 + STRONG 10/20; Browns LEAN + PLAY; Canadiens STRONG + LEAN), which muddies the W-L.
5. Only 30 priced markets scanned in the default Today + Tomorrow window.
**New data sources verified 2026-10-20 (free, no key):**
- **ESPN `summary?event=<id>` → `winprobability[]`** (play-by-play home win %, possession-aware; 499 points on a finished NBA game). Fixes SNIPE and the NBA NaN.
- **Kalshi public API** `api.elections.kalshi.com/trade-api/v2/markets?series_ticker=KXNHLGAME|KXNBAGAME|KXNFLGAME|KXNCAAFGAME&status=open` → open game moneylines (94 NHL, 104 NBA, 56 NFL, 200+ CFB), `yes_ask_dollars` per team. A second prediction market = cross-market disagreement signals and a sanity check on Polymarket US.
**APPROVED 2026-10-20 ~2:45 PM PT (Adam: "Yes fix it and publish"):** build + publish in this order: (1) SNIPE/live on ESPN `winprobability` (fixes NBA NaN), (2) Kalshi as a second prediction market, (3) per-sport thresholds from the record, (4) steam detection + confirmed NHL goalies. Also fold in: strong favorites not graded as calls at ~0 edge, one tier per game in the record. FIRST read the builder chat (v4.1 is undocumented) and checkpoint before editing. Blocked only on the Base44 tools loading (needs a Claude Code restart).
