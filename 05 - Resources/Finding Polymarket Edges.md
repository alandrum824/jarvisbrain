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

**Where the gaps concentrate:** popular teams. Recreational money overbets the Dodgers, Yankees, Chiefs, Lakers and similar brands, so the soft side is usually the unglamorous opponent. Also expect softness in the **first minutes after a maintenance window or market reopen**, when the book has not yet re-synced to the sharp price.

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

**The three to watch first when US reopens,** because they pair a brand-name favourite with recreational crowd bias:
- **LAD @ CIN** — fair value has the Dodgers at 66.3%. Crowd money loves the Dodgers, so if Polymarket prints them above ~71%, Cincinnati is the value side.
- **SD @ COL** — Colorado at 55-94 is still worth 37.7% here (Coors inflates variance and they play better at home). If Polymarket pushes San Diego past ~67%, take Colorado.
- **NYY @ MIN** — Yankees are only a 55.1% favourite on the road. Any Polymarket price above ~60% on New York is the soft side.

**Lowest-confidence game on the board: DEN @ KC.** It is Week 1, so neither team has a single current-season data point; the price is pure preseason projection plus Chiefs narrative. Highest chance of a big Polymarket-vs-sharp gap, and also the one where nobody — the book, the crowd, or Jarvis — actually knows much.

## Related
- [[PolyEdge (Grok Build)]] — the app that automates this, plus the 2026-09-14 diagnosis of why its Polymarket feed reads OFFLINE.
- [[Polymarket (Prediction Markets)]], [[Public ESPN API]] — the underlying free data sources.
