---
status: active
project: personal
type: reference
---
# PolyEdge Upgrade Prompt v4

Paste-ready builder prompt Jarvis wrote for Adam on 2026-10-02. It turns his 32-section decision-engine spec (summarized in [[PolyEdge]]) into hard rules, numbers, and acceptance tests. It's written for whichever builder he pastes it into (the Grok board or Base44). The Kings @ Sharks 10/3 card is the main acceptance test: books 52.2% fair and [[Polymarket (Prediction Markets)|Polymarket]] US 53¢ must come out as a PASS.

```text
POLYEDGE v4 — UPGRADE (do not start over; keep the dark PolyEdge look)

GOAL
Fewer, better decisions. Most games should show PASS. Every pick must show the
price it's worth paying and the price where it stops being a bet. Upgrade the
data, the model, the decision logic, and the record-keeping, THEN the card.
Sports: NFL, NBA, MLB, NHL. Each sport gets its own factor list (below).
Polymarket US is the venue. Moneyline only.

==================================================
1. THE MODEL STARTS FROM THE MARKET (most important rule)
==================================================
The old model starts at 50% and adds points. That's why it shows things like
"Sharks 59%, +7" when the books have the Sharks at 52.2%. That +7 is the
model's own error, not an edge. Replace it:

  p_books = vig-free sportsbook consensus (section 2)
  logit(x) = ln(x / (1 - x)),  sigmoid(z) = 1 / (1 + e^-z)
  p_model = sigmoid( logit(p_books) + sum(factor_logits) )

Factor caps (until a backtest proves a factor deserves more):
  - each factor: max ±0.08 logit (~±2 pts near 50%)
  - all factors combined: max ±0.15 logit (~±3.7 pts)
  - tag every prediction "UNVALIDATED" until that sport passes section 9
Clamp p_model to 1%–99%. Never stack factors on a 50% base again.

If there are NO sportsbook odds: there's no prior. Show "WAITING FOR BOOKS",
not a probability, and the tier can't go above PASS. Never use the Polymarket
price as the prior and then compare against Polymarket — that's circular.

==================================================
2. SPORTSBOOK CONSENSUS + VIG REMOVAL
==================================================
American odds to implied probability:
  negative odds: |odds| / (|odds| + 100)     (-120 → 54.55%)
  positive odds: 100 / (odds + 100)           (+100 → 50.00%)
Remove the vig per book: fair_A = imp_A / (imp_A + imp_B).
  Example: SJ -120 / LA +100 → 54.55 / 104.55 = 52.2% SJ.
Consensus = MEDIAN of the per-book fair probabilities.
Sources: The Odds API (h2h, region us, key stored ONLY as a server-side
secret, never in front-end code), cached; fallback = ESPN scoreboard
DraftKings line at events[].competitions[0].odds[0].moneyline.{home,away}
.{open,close}.odds (count as 1 book).
Store the OPEN line and the latest line every time you fetch.

==================================================
3. POLYMARKET US PRICE
==================================================
Use the BUY price (best ask) for the side being evaluated, never the midpoint.
Public gateway, no key: GET https://gateway.polymarket.us/v1/markets?slug=...
(batch up to 60 slugs per call; slug = "aec-" + the game slug, e.g.
aec-nhl-la-sj-2026-10-03). marketSides[].price = that team's buy price.
Match teams by NAME, and kickoff must be within 3 hours of the ESPN start.
It rate-limits (~4 fast calls then 429, retry-after 10s): batch, don't loop.

==================================================
4. EVALUATE BOTH SIDES
==================================================
For each game compute edge for BOTH teams and show the better one:
  edge_pts = (p_model - polymarket_buy_price) × 100
Never PASS a game just because the model's favorite is under 50%.

==================================================
5. PRICES THE USER CAN ACT ON (in cents AND American odds)
==================================================
  Fair price      = p_model in cents (59% → 59¢ / -144)
  Safety margin   = max(1.5 pts, 0.25 × uncertainty range width)
  MAX BUY PRICE   = p_model - safety margin   (e.g. 55¢ / -122)
  Price status:
    buy price ≤ max buy             → VALUE
    within 1.5¢ above max buy       → MARGINAL (max tier LEAN)
    more than 1.5¢ above max buy    → VALUE GONE (PASS)
Prob → American: p ≥ 50%: -(p/(1-p))×100 ; p < 50%: +((1-p)/p)×100.

==================================================
6. CONFIDENCE ≠ PROBABILITY
==================================================
Confidence (0–100) = how much we trust the estimate. Start at 100, subtract:
  - each CRITICAL input missing: cap confidence at 30
  - each IMPORTANT input missing/stale: -10
  - books: 1 book -20, 2–4 books -10, books disagree >3 pts -15
  - starter/goalie/QB only PROJECTED (not confirmed): -15
  - early season (team has <10 games NHL/NBA, <15 MLB, <3 NFL): -15
  - one factor supplies >60% of the total adjustment: -15
  - model vs books gap >5 pts: -20 (section 8)
Bands: 0–29 VERY LOW, 30–49 LOW, 50–69 MODERATE, 70–84 HIGH, 85+ VERY HIGH.
A high probability must NEVER raise confidence by itself.

Uncertainty range = p_model ± (2 + 0.08 × (100 - confidence)) pts.
(confidence 80 → ±3.6; confidence 20 → ±8.4)

==================================================
7. DECISION TIERS (rules in code, not the AI's opinion)
==================================================
Default is PASS. Every rule must hold for the tier:
LEAN:  edge ≥ 1.5 pts, confidence ≥ 40, price status VALUE or MARGINAL
PLAY:  edge ≥ 3 pts, confidence ≥ 60, ≥ 3 books agreeing within 3 pts,
       all CRITICAL inputs VERIFIED, price status VALUE
STRONG PLAY: edge ≥ 5, confidence ≥ 80, ≥ 5 books, factors in ≥ 4
       categories agree, AND that sport has passed section 9. Until then
       STRONG PLAY shows as PLAY with "(not yet validated)".
WAITING FOR DATA: a CRITICAL input is missing but expected later
       (lineups, goalie, pitcher) → show the re-check time.
PASS: everything else. Always list the reason(s).
One status per card. Never show two.

==================================================
8. MARKET DISAGREEMENT
==================================================
|p_model - p_books| > 5 pts → "MARKET DISAGREEMENT" alert, list the factors
causing it, confidence -20, tier capped at LEAN.
> 8 pts → "MODEL SUSPECT" → PASS. (With the caps in section 1 this should
almost never happen; if it does, it's a bug — log it.)

==================================================
9. RECORD, CALIBRATION, CLV (this is how we find out if it works)
==================================================
Before kickoff, save a WRITE-ONCE snapshot of every game (PASSes too):
raw inputs + status of each, factor logits, p_books, # books, Polymarket
price, p_model, confidence, range, tier, max buy, timestamp (PT), and
model version (e.g. "PolyEdge NHL v4.0"). Also save the CLOSING line and
closing Polymarket price. Grade automatically from final scores.
Record page, separated by sport AND model version:
  - plays, win rate, ROI at the saved buy price
  - average CLV (closing fair % - our entry price) and % of plays beating close
  - Brier score and log loss for p_model vs p_books (the model must beat the
    books' Brier score or the factors are hurting)
  - calibration buckets 50–54, 55–59, 60–64, 65–69, 70–74, 75+:
    expected vs actual win %, count
  - edge buckets 0–2, 2–4, 4–6, 6–8, 8+: win %, ROI, CLV, count
A sport "passes" (unlocks STRONG PLAY and wider factor caps) only after 100+
graded snapshots where model Brier ≤ books Brier and average CLV > 0.

==================================================
10. SPORT FACTOR ENGINES (separate code per sport)
==================================================
Each factor = { name, logit, pts, status VERIFIED/PROJECTED/STALE/MISSING,
last_updated, source, one-line reason }. Missing = MISSING, never 0.
Injuries with an unknown effect show "Impact: UNKNOWN", never 0.0.

NHL  CRITICAL: starting goalie (+confirmed?), key injuries, books.
     Factors: goalie (GSAx / save% vs expected, starter vs backup),
     5v5 xG%, special teams, rest (back-to-back, 3-in-4), travel.
MLB  CRITICAL: probable starters, lineup, books.
     Factors: starter quality (FIP/xFIP/K-BB%, NOT W-L), bullpen
     usage last 3 days, lineup missing hitters, park, weather/wind.
     Season run differential may NOT dominate.
NFL  CRITICAL: starting QB + health, major injuries, books, weather.
     Factors: QB (EPA/play), offense/defense EPA, OL/pass rush injuries,
     rest/short week/bye, travel/time zone, wind/precip.
NBA  CRITICAL: starting lineups, star availability, minutes limits, books.
     Factors: player availability (on/off), net rating, rest
     (back-to-back, 3-in-4), travel/altitude.
Recent form: exponentially weighted, outliers (NHL 9-1, NFL 45-7, NBA +40,
MLB 15-2) regressed toward expected. No "last 5 games" counts. No
"motivation" points.
Free sources to try first: ESPN (scores, injuries, probables, DK line),
MLB Stats API (statsapi.mlb.com: probables, lineups, boxscores for bullpen
usage), NHL API (api-web.nhle.com: goalies, schedule), nflverse data
(EPA). If a source isn't available, the factor is MISSING — do not invent it.

==================================================
11. THE CARD (mobile, one column, keep the dark style, make it beautiful)
==================================================
Top: date · time PT · sport · teams with logos
Big status chip, color-coded:
  PASS (grey) · WAITING (blue) · LEAN (gold) · PLAY (green) · STRONG (bright green glow)
Then:
  SHARKS · 59% to win  (range 54–63%)
  Confidence 42/100 · LOW         (a bar, not just a number)
  Three-column compare:  POLYEDGE 59% | BOOKS 52.2% (7 books) | POLYMARKET 53¢
  Edge vs Polymarket: +6.0 pts
  Fair 59¢ (-144) · MAX BUY 55¢ (-122) · NOW 53¢ → VALUE
  Line: open SJ -120 → now SJ -120
  Data: DATA COMPLETE / DATA PARTIAL (n pending) / DATA STALE / WAITING FOR DATA
     (never "DATA VERIFIED ✓" unless every CRITICAL input is VERIFIED)
  Starter/goalie line: "Askarov — PROJECTED, not confirmed"
Expandable sections:
  WHY — a waterfall from BOOKS 52.2% through each factor (+/- pts, status)
        to MODEL 59.0%; factors against shown in red
  WHAT CHANGES THIS — auto-generated: "PASS if price > 56¢", "Recalculate if
        backup goalie starts", "Downgrade to LEAN at 55¢"
  INJURIES — player · status · impact (pts or UNKNOWN)
  AUDIT — every timestamp, model version
Final line, always in this form:
  "We estimate X%. The market prices Y. Edge Z. Confidence N because ___.
   Max price ___. This is not a bet."
PASS cards: collapsed one-liners in a "Passes" list with the reason.

==================================================
12. RE-CHECKS
==================================================
Re-run each game at: books open, morning of game, 2h before, when
starters/lineups post, 15 min before. Only alert when the tier changes, a
starter/goalie changes, the line moves ≥ 3 pts, or value disappears.
Respect the Odds API budget: cache, max 15 calls/day, show credits left.

==================================================
ACCEPTANCE TESTS (must pass before you call it done)
==================================================
1. Kings @ Sharks, Sat Oct 3 2026 7:00 PM PT. Books: SJ -120 / LA +100 →
   Sharks 52.2% fair. Polymarket US: Sharks 53¢, Kings 48¢. With factors
   capped, the card must NOT show "LEAN Sharks 59% +7". Expected: PASS or at
   most LEAN with edge ≤ ~3 pts, books column filled, max buy shown.
2. A game with no sportsbook line → "WAITING FOR BOOKS", no tier above PASS.
3. An MLB game with a probable starter missing → WAITING FOR DATA,
   confidence ≤ 30, re-check time shown.
4. A game where the underdog is the cheap side → that side is evaluated
   (no "below 50%" PASS).
5. Devig check: -150 / +130 → 58.0% / 42.0%.
6. Factor sum can never move p_model more than ~3.7 pts from p_books.
7. No card ever shows two statuses, and no PASS card says DATA VERIFIED.
8. Every saved snapshot can be re-opened and shows exactly why it got its tier.
Report what you changed, file by file, and show tests 1, 5 and 6 with numbers.
```

## Notes
- The thresholds (1.5 / 3 / 5 pts, confidence 40 / 60 / 80, caps ±0.08 / ±0.15 logit) are Jarvis's starting values, not validated. The section 9 record is what earns any change.
- Devig check for test 5: −150 → 60.0%, +130 → 43.48%, total 103.48 → 57.98% / 42.02%.

## Patch 1 (2026-10-02 ~9:45 PM PT) — for the Grok board
Sent after Adam's screenshots of the upgraded Grok board (`pine-crane-meadow-cactus.grok.me`). Asks for:
1. The ESPN DraftKings fallback (`competitions[0].odds[0].moneyline.{home,away}.{close,open}.odds`), counted as 1 book and used whenever The Odds API returns nothing. Odds API "not connected" is shown once, in sources.
2. One status per card: WAITING (blue) for data that's still coming; PASS only for real pass reasons.
3. Started games become LIVE cards (score, clock, live price, the saved "Pregame call"), with no re-check time and no Missing list.
4. "Confidence — (no estimate yet)" instead of 0, and rest computed from prior scoreboards or the NFL team schedule.

Acceptance tests:
- IND @ WSH books 64.5 / 35.5
- ARI @ NYG books 56.3 / 43.7
- Kings @ Sharks = PASS (Kings −0.2)
- one status chip per card
- a LIVE card shows no re-check time
- no "Confidence 0", and Rest isn't listed as missing when the schedule loaded

## Patch 2 (2026-10-02 ~10:20 PM PT) — power-method vig removal
All Grok-board LEANs were longshot underdogs created by proportional devig (favorite-longshot bias). Asks for the power method (a^k + h^k = 1) on every devig (consensus, ESPN fallback, open/close lines), a 15–85¢ call band, and a confidence cap of 55 with one book. Tests: +400/−535 → 17.1 / 82.9; −120/+100 → 52.3 / 47.7; Merrimack, UNH, Buffalo, Dolphins = PASS; Vanderbilt = PASS (outside the band). Full table in [[PolyEdge]].

## Patch 3 (2026-10-05 ~4 AM PT) — v5 redesign + speed, for the Grok board
Adam: "Fix this poly edge make it way better looking and more efficient", then "No base 44" (he meant the Grok board `cabin-velvet-bolt-forge.grok.me`, the URL changes on rename). Full prompt text saved as `PolyEdge v5 Redesign Prompt (Grok).txt` in this folder and sent to his phone. **Scope-locked: no engine/model/tier changes, only look and load.** Baseline I measured with `~/pe_cdp/measure.mjs` (headless iPhone 390px): **first card 10.0 s** (DOM ready 10.6 s), initial JS 133 KB + 25 KB, **steady 546 KB/min** (3 refreshes of ~180 KB), 4 long tasks (243 ms) per 60 s, 302 DOM nodes. Problems seen in the screenshots: always-open search box + two-row chips + big Today/Tomorrow buttons eat ~40% of the first screen; WAITING cards render walls of "—¢" dashes; the floating "Ask PolyEdge" pill overlaps the Watchlist/Track tabs; low-contrast grey text; ALL-CAPS team names with wide letter-spacing; no logos in the list. Asks for: design tokens, a 104px sticky header/filter bar, summary tiles, compact rows for no-data games vs full cards with a price ladder, 4-tab nav with Ask moved to the header, skeleton/offline states; and speed targets (cache-first paint <=1.5 s warm / <=4 s cold, server-side parallel + cached upstreams, slim list payload + ETag/304, adaptive polling that pauses when hidden, <=60 KB/min steady, memoized cards, <=150 KB initial JS, lazy routes and a lazy Ask). 8 acceptance tests; Grok must report before/after for first-card time and 60 s idle KB.
**For comparison, the Base44 board (poly-edge-terminal.base44.app), same script:** 59 requests / 1.56 MB on load, first card ~11 s in the headless run (it fetches ESPN/Polymarket/MLB from the browser), steady 12 requests / 61 KB per 75 s, 0 long tasks, 451 DOM nodes, initial JS 154 KB. Nothing on Base44 was changed in this turn.

## Patch 4 (2026-10-20 ~3 PM PT) — v4.2 for the Base44 builder: live fix, Kalshi, per-sport gates, steam, clean record
Written because the Base44 connector wouldn't load in Jarvis's session; Adam pastes it into the Base44 builder on app `6aae5695dbc22f6715196ad4`. Evidence behind every item is in [[PolyEdge]] → "Live audit + data-expansion plan (2026-10-20)". Sources verified 2026-10-20: ESPN `summary.winprobability`, Kalshi `KX*GAME` series (blocks browser-origin requests with 403, so server-side only). Confirmed NHL goalies were left out: no verified free confirmed-starter feed.

```text
POLYEDGE v4.2 — TARGETED UPGRADE. Do not redesign, do not start over.

DO NOT CHANGE (locked):
- Engine: model = books no-vig consensus (POWER devig) + capped factors (±0.08 each, ±0.15 total logit).
- Edge = model % − Polymarket US best ask. Polymarket US stays the price we bet at.
- PRICE SUSPECT >8 pts, stale → PASS, liquidity / price-band gates, PLAY rules, STRONG PLAY locked.
- Snapshots are write-once. Look and layout stay as they are.
Bump model_version to v4.2 on every new snapshot so the record separates it.

1) LIVE WIN % — replace the score-and-clock model
- For each LIVE game, fetch ESPN https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/summary?event={espnId}
  every 15 s. Read the LAST item of `winprobability[]`: homeWinPercentage (0–1); away = 1 − home.
- Use that as the live win %. If `winprobability` is missing or empty (e.g. NHL), keep the old
  score model BUT that game can never be a SNIPE (show "Live win (score only)").
- New gate: if live win % − Polymarket US ask > 15 pts → "LIVE SUSPECT — market knows something", PASS.
  (Nebraska @ Oregon was SNIPE 80.2% vs 46¢ = +34 and lost; the Colts +9.4 SNIPE lost.)
- Never print NaN. If the live win % can't be computed, show "—" and PASS with the reason.

2) KALSHI — second prediction market (server-side only)
- New backend function getKalshi (Kalshi returns 403 to browser requests, so never call it from the page).
  GET https://api.elections.kalshi.com/trade-api/v2/markets?series_ticker={S}&status=open&limit=200
  for S in KXNHLGAME, KXNBAGAME, KXNFLGAME, KXNCAAFGAME (and KXMLBGAME if it returns markets).
  Follow `cursor` for more pages. Cache 60 s per series in DataCache. No key needed.
- Each game has two markets, one per team: ticker like KXNHLGAME-26OCT26DETEDM-EDM,
  title "Edmonton wins". The team's BUY price = `yes_ask_dollars` (in dollars; ×100 = cents).
- Match to the ESPN game by both team names + date. The date is in the ticker: 26OCT26 = 2026-Oct-26
  (YY MON DD). Kickoff must be within 3 h. If not sure, no match (null), never guess.
- Card: show "Kalshi X¢" next to Polymarket US and books fair, in the price ladder and the Prices fold.
- Rules:
  a) MARKETS SPLIT: if Polymarket US and Kalshi differ by >4 pts on the same team → cap at LEAN, tag "Markets split".
  b) CROSS-MARKET CONFIRM: if the books fair and Kalshi agree within 1.5 pts AND Polymarket US is ≥2 pts
     cheaper than both → tag "Kalshi agrees" and +5 confidence (capped at 100). Tiers still come from
     the normal edge rules.
  c) Kalshi never creates a call by itself; it only confirms or caps.
- Store kalshi_ask on every snapshot (new field) so the record can test it later.
- Feeds footer: "Kalshi Xs ago", or "Kalshi offline" — the board must keep working without it.

3) PER-SPORT GATES (from the graded v4.0 record)
- CFB (47-36, ROI −13%, beat close 47%) and NBA (beat close 12.5%, CLV −0.9):
  LEAN needs edge ≥2.0 AND confidence ≥45; PLAY needs edge ≥3.5.
- NHL, NFL, MLB: keep the current gates.
- Put these in ONE config object per sport (leanEdge, leanConf, playEdge, playConf) so they're easy to change.
- Record tab, per sport: show n graded, avg CLV, % beat close and a note:
  "Loosen only after 100+ graded calls with CLV > 0." Don't auto-change anything.

4) STEAM — catch the price before Polymarket catches up
- Each time a game's books fair changes (Odds API consensus, SportsGameOdds, or the ESPN DraftKings line
  on every scoreboard poll), save {time, fair} for that game in memory plus DataCache (keep 24 h).
- STEAM = books fair moved ≥1.5 pts toward one team within the last 60 min AND the Polymarket US ask
  for that team moved less than half as much in the same window.
- STEAM games: amber "STEAM ↑ +X pts in Y min" tag; re-price every 30 s; sort to the top of their tier.
  STEAM never changes the tier rules — the edge vs the CURRENT fair still decides.
- When any game is within 3 h of start and has STEAM, ask SportsGameOdds for a fresh second opinion
  (inside the existing 80/day cap).

5) RECORD CLEANUP
- STRONG FAVORITE is an info tag, not a call: stop grading it in W-L / ROI (keep showing the tag on cards).
- One graded call per game per track: grade only the LAST pregame call before start. Earlier calls on the
  same game show as history under it, not as separate W-L rows.
- Calls flagged "excluded: stale lines" stay out of every stat.

ACCEPTANCE TESTS (all must pass before publishing):
1. A finished NBA game: the live card shows a real live win % from ESPN winprobability, never NaN.
2. A live game where ESPN win prob is 80% and the Polymarket ask is 46¢ → LIVE SUSPECT, PASS (not SNIPE).
3. NHL live without winprobability → shows "score only" and can't be a SNIPE.
4. getKalshi returns prices for tonight's NHL/NBA games; at least 80% of priced NHL/NBA games show a Kalshi price.
5. A CFB game with edge +1.8 and confidence 50 → PASS (it was a LEAN before). The same numbers in NHL → still LEAN.
6. Fake a books-fair move of +2 pts in 30 min with a flat Polymarket price → the STEAM tag shows.
7. Record: the Strong favorite rows are gone from the W-L; FIU (LEAN 10/18 and STRONG 10/20) counts once.
8. Kalshi down (force an error) → the board still loads and shows "Kalshi offline".
9. Kings @ Sharks style (books 52.2% vs 53¢) is still a PASS. The engine is unchanged.
10. iPhone 390 px: no sideways scroll, tap targets ≥44 px.
Then publish.
```
