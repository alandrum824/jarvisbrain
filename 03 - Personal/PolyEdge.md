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

## Related
[[Jarvis Remote Control]] — the other Grok-hosted app, and the reason the `.grok.me` URL pattern is familiar.
