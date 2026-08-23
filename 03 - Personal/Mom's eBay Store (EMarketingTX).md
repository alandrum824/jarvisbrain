---
status: idea
project: personal
type: plan
---
# Mom's eBay Store (EMarketingTX)

Adam's mom, Laura Speer (b. 1963-05-27, Fort Worth, TX — see [[VAULT-INDEX]] Key People), runs the eBay store **EMarketingTX** (`ebay.com/str/emarketingtx`). Sales have dried up and she's considering shutting it down. Adam wants to use Jarvis to try to revamp/save it before that happens. As of 2026-08-21, this is at the **brainstorming stage** — no account access, no plan locked yet. Two separate Jarvis sessions worked on this the same day (this machine, and Adam's main desk box); this note merges both — see the note-history line at the bottom.

## The real goal — corrected 2026-08-21, this is the framing that matters
**This is not a growth/revenue project.** Mom's actual motivation for getting rid of the store is to **clear physical inventory and free up space in her house** — the store is just the disposal mechanism. This reframes everything: the win condition is fast inventory turnover, not maximizing per-item revenue or rebuilding a sustainable storefront. A full SEO/algorithm/Promoted-Listings revamp (see "Working theory" below) is likely overkill for this goal — bulk/lot listings, steeper blanket discounts, and non-eBay disposal routes (Facebook Marketplace bulk lots, donation, consignment) may clear space faster than optimizing one-at-a-time eBay sales.

## Store snapshot (pulled 2026-08-21, main desk session — the fuller read)
- 100% positive feedback, ~2.3K feedback count
- 5.7K items sold all-time, 298 followers
- **517 active listings right now**
- Inventory: mostly women's resale clothing (blouses, dresses, tunics, cardigans, jackets), some men's shirts/ties/shorts, a few hats
- Recurring brands: Lane Bryant, Liz Claiborne, Avenue, Umgee, Cato, Alfred Dunner, Coldwater Creek — leans plus-size/petite women's resale
- Pricing pattern: everything listed "or Best Offer," priced roughly 70–75% off stated retail (e.g. a $12.99 blouse offered at $3.25)

## Partial cross-check (this machine, same day — smaller sample, different method)
Direct `WebFetch` on the store page and individual listing pages **failed outright — 5 timeouts total**, so this machine's Jarvis couldn't load the store directly. Found a workaround: `WebSearch` with `site:ebay.com/itm emarketingtx` surfaces individual indexed listing titles/prices even though the pages themselves won't fetch. Pulled a small sample this way (7 items, not the full 517): titles like "Notations Womens Blouse Size 4X Black Brown Animal Print Button Up Short Sleeve" ($13.99), "OUTKAST STANKONIA CHROME TRACKLIST TEE" ($23.39), "Elie Tahari Womens Pants Size 6" — a slightly different brand mix than the recurring brands above (this machine's sample happened to catch some higher-end/novelty pieces the other session's fuller pull didn't call out), decent keyword-rich titles, $6.99–$8.99 USPS Ground Advantage shipping. Read this as confirmation the store is real and reasonably well-titled, not as a contradiction of the fuller snapshot above — small sample vs. a near-complete one.

## Why sales dried up (Adam's read)
Confirmed reason: **sales have dried up** — not a profitability or time-burnout complaint, the store's traffic/sales itself has fallen off.

## Access
**None yet.** Adam hasn't gotten login access for Jarvis to work hands-on. Until that changes, this is analysis/recommendations only — no direct edits to listings, pricing, or store settings.

**Two ways to eventually get real structured access, not yet chosen:**
1. **Manual export** — Laura (or Adam) exports her active listings as a CSV from eBay Seller Hub (Reports section). No API/credentials needed, works today.
2. **eBay Developer API** — free eBay Developer Program signup (developer.ebay.com), generates app keys, unlocks real structured access AND actual automation (bulk repricing, listing rewrites, scheduled relisting). Adam doesn't know how to do this yet — Jarvis offered to walk him through it, not yet started.

## Working theory (original framing — now secondary given the real goal above)
Prices already look aggressive (25–30% of retail), so a pure pricing fix is unlikely to be the lever. More likely culprits for an established store with good feedback going quiet:
- eBay's search algorithm deprioritizes stale, unrefreshed listings over time regardless of quality — relisting cadence and Promoted Listings spend matter more than most sellers assume.
- No visible cross-platform presence (Poshmark/Mercari/Depop) — all traffic dependent on eBay's own search algorithm.
- Needs real account data (views/watchers/sell-through rate, Promoted Listings usage, listing age) before committing to a specific fix — this is a hypothesis, not a diagnosis.

## Open Questions
- Get account access (or at minimum, seller-side analytics/reports) to move from hypothesis to diagnosis.
- Timeline: how soon does mom want the house space back? Sets how aggressive the clearance needs to be.
- Is she open to non-eBay disposal (bulk lot sale, donation, consignment) if it clears space faster than continuing to sell one item at a time, or does it need to stay an eBay-only effort?

## Note history
Started independently by two Jarvis sessions on 2026-08-21 (this machine as "Laura's eBay Store", the main desk machine as "Mom's eBay Store (EMarketingTX)") — merged into this one on 2026-08-22 after a `git pull` surfaced both. The main desk session's snapshot and the "real goal" correction are the load-bearing content; this machine's contribution is the access-method finding and a small cross-check sample.

## Related
- [[Automated POD Stores (Adam and Mom)]] — separate new venture with mom, not related to clearing this inventory.
- [[Active Priorities]]
