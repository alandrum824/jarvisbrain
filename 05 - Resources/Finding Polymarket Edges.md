---
status: active
project: meta
type: guide
---
# Finding Polymarket Edges

The recurring job behind "give me bets." This is the method Jarvis runs directly, independent of whether [[PolyEdge (Grok Build)]] is working — the app automates this idea, but the idea stands on its own.

## The honest edge (read this before trusting any number below)

**Jarvis is not beating the sharp sportsbooks.** DraftKings/Pinnacle closing lines are among the best-calibrated probability estimates that exist; a cold read at a keyboard does not out-predict them, and any note claiming otherwise is overconfidence of exactly the kind already documented in [[PolyEdge (Grok Build)]]'s own bug history.

**The real, repeatable edge is venue mispricing, not superior prediction.** Polymarket is a thinner market with more recreational money than a major sportsbook. So the method is:

1. Take the sharp book's two-sided moneyline for a game.
2. Remove the vig (convert both sides to implied probability, divide each by their sum) to get **fair value** — the market's genuine estimate.
3. Compare Polymarket's price against that fair value.
4. **Bet only where Polymarket is off fair value by ≥5 percentage points.** Below that, the gap doesn't reliably clear fees, spread, and noise.

**Where the gaps concentrate — measured, not assumed.** The original hypothesis here was that recreational money overbets brand names (Dodgers, Yankees, Chiefs), leaving the unglamorous side soft. **That was tested on 2026-09-14 against nine live MLB markets and it was wrong** — see the measurement below. Polymarket's liquid game markets track the sharp book almost exactly. Do not assume brand bias; measure it every time.

## Method notes worth keeping

- American odds to probability: negative odds `-o` → `o/(o+100)`; positive odds `+o` → `100/(o+100)`.
- Vig on a normal two-sided MLB/NFL moneyline runs ~4.5%. If the two raw implied probabilities sum to far more than that, the book is unusually juiced and the fair value is less trustworthy.
- ESPN's public scoreboard API carries DraftKings both-side moneylines for free (`site.api.espn.com/apis/site/v2/sports/<sport>/<league>/scoreboard?dates=YYYYMMDD`) — no key, and it's the same free feed [[Public ESPN API]] documents.
- **Always check whether team records are genuinely empty or genuinely 0-0.** On 2026-09-14 both NFL teams showed 0-0; verified against the event's own `week.number` that it really was Week 1, not missing data. This is the same class of blindness that caused PolyEdge's FBS/FCS bug — verify, don't infer.

## Card — Monday 2026-09-14 (fair values locked while Polymarket US was down)

Polymarket US was mid planned-systems-upgrade when this was built, so these are **sharp-book fair values to compare against once it reopens**, not executed bets. Source: DraftKings via ESPN, vig removed, ~4.5% vig on every line.

| Game (away @ home) | Away FV | Home FV |
|---|---|---|
| NFL — DEN @ KC (Week 1) | 44.9% | 55.1% |
| CHW @ CLE | 41.9% | 58.1% |
| LAD @ CIN | 66.3% | 33.7% |
| DET @ TOR | 44.6% | 55.4% |
| BAL @ NYM | 47.1% | 52.9% |
| ATL @ CHC | 44.9% | 55.1% |
| NYY @ MIN | 55.1% | 44.9% |
| SF @ STL | 43.6% | 56.4% |
| SD @ COL | 62.3% | 37.7% |
| SEA @ LAA | 50.9% | 49.1% |
| MIA @ ARI | 44.8% | 55.2% |

**Lowest-confidence game on the board: DEN @ KC.** It is Week 1, so neither team has a single current-season data point; the price is pure preseason projection plus Chiefs narrative. Nobody — the book, the crowd, or Jarvis — actually knows much. Global Polymarket had no market for it at all under the expected slug.

## The measurement that changed this note (2026-09-14)

Polymarket US was down, but **global Polymarket was up and trading the same MLB games**, so the comparison was run live rather than waited on. Nine of the ten games had a market (CHW @ CLE had none). Result:

| Game | Polymarket (away) | Sharp FV (away) | Gap |
|---|---|---|---|
| LAD @ CIN | 66.5% | 66.3% | +0.2 |
| DET @ TOR | 45.5% | 44.6% | +0.9 |
| BAL @ NYM | 46.5% | 47.1% | −0.6 |
| ATL @ CHC | 45.5% | 44.9% | +0.6 |
| NYY @ MIN | 55.5% | 55.1% | +0.4 |
| SF @ STL | 44.5% | 43.6% | +0.9 |
| SD @ COL | 62.5% | 62.3% | +0.2 |
| SEA @ LAA | 50.5% | 50.9% | −0.4 |
| MIA @ ARI | 45.5% | 44.8% | +0.7 |

**Largest gap on the entire board: 0.9 points. The ≥5 point trigger never came close to firing, so the correct output for this slate was no bet.**

Markets were verified genuinely live, not stale: `acceptingOrders` true, order books enabled, `updatedAt` within minutes, roughly $90k-106k liquidity per market, one-cent spreads.

**Three things this proves, and they should shape [[PolyEdge (Grok Build)]]'s whole design:**

1. **Liquid Polymarket game markets are efficiently priced.** They are not a soft crowd book waiting to be picked off. The brand-bias assumption failed on the exact games it was supposed to work on.
2. **The spread eats small edges.** Quotes sit one cent wide, so entry is at the ask, not the mid — roughly half a point of cost before anything else. Any "edge" under about 2 points is not real after costs.
3. **"No bet" is the correct answer most nights, and an app that says so is working, not broken.** PolyEdge's "No high-confidence opportunities, PolyEdge is passing" is the honest output for a slate like this. The failure mode to fear is an app that manufactures picks to look busy.

**So where could real edge actually live?** Not in marquee, liquid, pre-priced games. The remaining candidates worth testing, none yet validated: stale prices in the minutes after real news (lineup scratches, weather, late injury), the reopen window right after a maintenance outage before the book re-syncs, genuinely thin or novel markets that no sharp book prices at all, and live in-game pricing. Each of these needs the same treatment this hypothesis got — measured against sharp fair value before being trusted.

## Competitor research: AI pick apps vs market-math tools (2026-10-09)
Prompted by a Facebook ad for **DeepChamp: Live Sports Intel** ("ChatGPT for sports intelligence").
- **DeepChamp** (Inova Platforms): LLM pick app ("BetGPT" voice/text/image chat), covers every major sport plus prediction markets, $6.99/week up to $199.99/year, 4.7 stars from about 1,100 ratings. **It publishes no track record and no CLV.** Reviewers complain about stale rosters (traded players analyzed on their old team) and slow "live" injury updates. Its own ad mockup says "Last updated 14h ago". What it sells is the experience, not an edge.
- **Same category:** Rithmm (custom AI models + picks), TipsPro ("~80% accuracy", a red flag), ZCode, SportBot AI (does publish a public accuracy page).
- **Where the professionals pay:** OddsJam ($199–299/mo: +EV and arbitrage vs. a sharp consensus) and Unabated (the "Unabated Line" = vig-free consensus of the sharpest books; reported ~$3,000/mo for API). **They sell what PolyEdge already does: book prices compared to a de-vigged sharp consensus.** None of them sells a better prediction model.
- **Evidence against prediction-first:**
  - An LLM forecasting swarm scored a Brier of 0.38 against Polymarket's 0.30.
  - Copy-trading the top Polymarket wallets lost ~13.6%.
  - 10 strategies over 10 months / 600 liquid markets all failed after ~2% fees (Action Network, Reddit test).
  - Our own 2,080-game MLB backtest: market log-loss 0.678 vs team model 0.688.
- **The favorite-longshot bias does NOT exist in Polymarket sports** (Cardozo & Rivero-Wildemauwe, arXiv 2609.12878: 588M trades). In crypto and politics, longshots lose 13–46%. In sports, longshots under 10¢ had a positive point estimate and favorites at 90¢+ returned −0.23% (equal weight). Sports prices are the best calibrated on the platform, so "fade longshots / buy heavy favorites" is not an edge there. Our 15–85¢ band is about de-vig noise, not a bias trade.
- **Conclusion:** the edge is **price and timing, not prediction**. Buy only when the Polymarket US ask is below the power-devigged sharp consensus, judge the system by CLV (not win rate), and size small. The one untested place a real edge probably lives is **lag**: the books move on news or sharp money and Polymarket US's retail book hasn't repriced yet (see "where could real edge actually live" above). Measuring it needs fast line data; the free Odds API (500/mo) and SportsGameOdds (10-min, 2,500/mo) tiers are too slow to catch a lag directly.
- Worth stealing from DeepChamp, as UX only: a chat that explains a card in plain English, favorite-team personalization, and line-movement alerts.

## Related
- [[PolyEdge]] — the live Base44 board that runs this method (market-as-prior engine).
- [[PolyEdge (Grok Build)]] — the app that automates this, plus the 2026-09-14 diagnosis of why its Polymarket feed reads OFFLINE.
- [[Polymarket (Prediction Markets)]], [[Public ESPN API]] — the underlying free data sources.
