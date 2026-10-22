---
status: active
project: forex-trading
type: reference
---
# Order Block and FVG Playbook

The master note for order blocks (OB) and fair value gaps (FVG). Built 2026-10-10 when Adam said "learn everything about order blocks and fvg, we need to master this strategy." Start here for anything OB/FVG. It pulls together outside research and every measured result in this vault. Glossary detail beyond this lives in [[SMC Playbook (Imperial FX)]]. Live graded reads go in that note's grading log, and the applied chart history is in [[Chart Analysis Notes]].

## The bottom line first
- **The definitions are not the bottleneck.** The vault has had them right since August. Ten-plus builds coded them, and none of the pure mechanical OB/FVG entries showed a robust edge.
- **Outside rigorous tests agree.** No independent study found a statistically significant OB/FVG edge once it was compared with random entries. Positive numbers come from vendors, who never publish a random-zone control.
- **What does show up, both outside and here:** zones *react* often, but a reaction isn't a profitable trade. The money comes (or doesn't) from **which zones you take, the stop, and trade management**, not from the zone itself.
- **So "mastery" means three things:** (1) an A+ filter that throws out most zones, (2) management that harvests the reaction (partials/BE), (3) one honest multi-year test with a random-zone control. Plus the size gate, which is what has actually been costing the account (see [[SMC Playbook (Imperial FX)#Why step 8 is there]]).

## Definitions (tight)
- **Order block (OB):** the last opposite-colour candle before a displacement move that breaks structure. Bullish OB = last down candle before the up-impulse. Zone = that candle's high–low (some traders use body only, and the open-to-50% is the "refined" part).
- **Fair value gap (FVG):** a 3-candle imbalance. Bullish: candle 1's high is below candle 3's low, and the gap between them is the FVG. Bearish mirrors it.
- **Consequent encroachment (CE):** the 50% midpoint of an FVG (or OB). The standard entry: limit at CE, stop beyond the whole zone.
- **Displacement:** big bodies, small wicks, and it leaves an FVG behind. It proves intent. No displacement, no valid OB.
- **Unmitigated:** price hasn't returned to the zone yet. The **first touch** is the trade, and later touches are weaker.
- **Mitigated / invalidated:** a candle *closes* through the far edge. The zone is dead as an OB.
- **Inversion FVG (iFVG):** an FVG that price closed through, which now flips and acts from the other side.
- **Breaker block:** a failed OB that **swept liquidity first**, then got broken by a structure shift, so the zone flips polarity. It's a reversal zone.
- **Mitigation block:** like a breaker, but the swing failed to take the prior high/low before the shift (no sweep). Usually read as weaker or continuation.
- **Balanced price range (BPR):** the overlap of a bullish and a bearish FVG. Traders treat it as a strong magnet, but nobody has measured that.
- **Premium / discount:** above 50% of the dealing range is premium (sell there), and below is discount (buy there).

Sources disagree on mitigation vs breaker in the details. These definitions are the majority reading, not ICT's own text.

## The A+ zone checklist (all must pass, otherwise it's just a box)
1. **HTF bias agrees** (Daily/H4 HH/HL for buys, LH/LL for sells). See [[TWI HTF Bias OB]].
2. **It swept liquidity first**: the move into the OB took a prior swing/equal high or low. An OB in the middle of a range that took nothing gets ignored.
3. **Displacement out of it left an FVG** (the "strong OB" rule already coded in [[TWI OB FVG IDM]]).
4. **It caused a BOS/CHoCH** on a close, not a wick.
5. **Correct side of the range**: buy OBs in discount, sell OBs in premium.
6. **Unmitigated, first touch only.**
7. **Size: zone height ≥ 1× ATR(14).** This is the one feature with a large-sample measured effect (below). Our own ≥ 0.5 ATR "strong gap" filter didn't pass 5/6 markets, so the bar here is higher.
8. **Room to a target ≥ 2R**: opposing liquidity (equal highs/lows, a swing) sits at least 2R away.
9. **LTF confirmation inside the zone**: an M5 tap-and-close / ChoCH, not a blind limit. This is the one change that flipped an EA here from losing to winning (see [[TWI OB Hunter]]).
10. **Size gate:** ≤ 2% risk from `mt5ro.py risk`, and no adding to a loser.

**Entry / stop / target:** enter on the LTF confirmation inside the zone (or a limit at CE if there's no confirmation model). The stop goes beyond the zone, or the sweep wick if that's further, plus a buffer that covers the spread (gold's ~52-pt spread killed tight stops in [[TWI SMC POI]]). TP1 goes at the nearest opposing liquidity: take half there and move to breakeven. The runner targets the next liquidity pool.

## What outside research found (2026-10-10)
| Source | What was tested | Result |
|---|---|---|
| StatOasis (Sep 2026) | OB, FVG, sweep, OTE coded as rules; 648 backtests on SPY/QQQ/DIA/IWM daily, random-entry + buy-and-hold controls | No significant edge. OB best (SPY t = +1.22), FVG t = −0.08. OB beat random entries in 56–82% of variants (the only family that did on all 4 markets), but 0/648 beat buy-and-hold. Daily bars only, no costs. |
| Tangirala, SSRN preprint (2026) | 44 SMC detectors from 2 popular Pine indicators, 496 S&P stocks, 2010–26 | 38/44 looked "significant" vs zero. Against each stock's own baseline + multiple-test correction: **none beat random entry.** Concepts picked in-sample earned −31 bp out of sample. |
| IndicatorEdge | Sweep → structure shift → FVG entry in session windows, EURUSD M1 2019–25, 0.5-pip cost, 54 variants | **0 of 54 profitable.** PF 0.42–0.89. Best win rate 56% was still −0.05R. |
| AlgoTraderPro (vendor) | ~250k FVG/OB zones, crypto perps, 15m–1D, with held-out coins | Grade A (≥ 1 ATR) zones rejected **~75%** of the time vs **~58%** for small (< 0.5 ATR), and it replicated on held-out coins. But "a 3:1 target was hit only about as often as breakeven requires." OB proximity to an FVG added nothing. 62–86% of rejections happen on the first touching candle. |
| QuantTradingDiscoveries (paywalled) | EURUSD FVGs 2022–25 | 63.7% of FVGs never fill, so "gaps always fill" is a myth. A 5-point filter kept 27% of setups and claims 66.5% wins at 2.3R, but the filter is behind the paywall, with no costs or OOS shown. Unverified. |
| Fill-rate claims generally | Various | Gold FVG "fill rate" claims range from 29% to 89.5% depending on how "fill" is defined. Treat any single number as meaningless unless the definition is given. |

## What we measured ourselves
- [[TWI OB FVG IDM]]: 2,571 scored signals over 6 markets, **−21.9R**. The in-sample best (CONF+IDM 3R, +62R) **failed out of sample** (−16.4R). There's no edge as a mechanical entry.
- [[TWI OB Hunter]]: sweep → BOS → OB, instant entry = PF 0.96 (loses). **With the M5 tap-and-close confirmation + invalidation fixes: EURUSD PF 1.18, XAUUSD PF 1.21.** This is the best OB result in the vault, but it's **one 12-month window, no walk-forward**, and gold isn't viable at $400.
- **[[TWI OB Hunter]] multi-year + random-zone control (2026-10-10): the best lead failed.** On 2020–26 AAAFx M1 data it loses on all 4 markets (EURUSD −138.8R, GBPUSD −162.9R, USDJPY −105.6R, gold −42.2R; PF 0.85–0.95), and the real OBs beat their random twins only 34–72% of the time, which is noise. The 2026-09-02 PF 1.18/1.21 was one lucky year (2025).
- [[TWI EQ Liquidity OB]] (~2,800 trades, US30 + gold): all-at-TP1 loses despite 69% hits; half at TP1 + BE + runner looked positive (+0.13–0.18R, PF 1.35–1.48). **Overturned on 2026-10-11:** the script still credited TP2 after a trade had come back to entry. The corrected 2020–26 gold test, [[TWI Gold Zone Ladder]], loses with the ladder at −0.080R/trade, which is worse than random-time entries.
- [[TWI SMC POI]], [[TWI Liquidity Sweep OB EA]], [[TWI SMC Auction Flow]], [[TWI HTF Bias OB]] / v6 supply-demand rows: none robust. SMC Auction Flow's BUY side was +0.108R while SELL was −0.298R (failed OOS overall).

**The pattern across both:** high reaction rates and thin or negative expectancy as a raw entry. The apparent positives from *confirmation + management* did not survive multi-year testing (OB Hunter on 2026-10-10, Zone Ladder on 2026-10-11). That matches the outside finding that results usually come from trade geometry, not the zone.

## The path to mastery (proposed 2026-10-10; step 1 RAN 2026-10-10 and FAILED, see above)
1. **DONE, FAILED (2026-10-10). Honest test of the best lead:** [[TWI OB Hunter]] tap-and-close on multi-year data (EURUSD first; gold on Dukascopy data at a $10K test balance), walk-forward by year, **plus a random-zone control** (same-size zones at random places, same entries/stops/management). If OB Hunter doesn't beat its random twin, the OB isn't the edge.
2. **Add the A+ filters one at a time** (≥ 1 ATR size, sweep-first, discount/premium, first touch), keeping each only if it improves ≥ 5 of 6 markets/years, the same rule used in [[TWI OB FVG IDM]].
3. **Test management separately:** half-at-TP1 + BE vs fixed 2R/3R on the same entries, since the EQ Liquidity OB result says this is where the money is.
4. **Discretionary track in parallel:** grade every live OB/FVG read against the checklist above in the [[SMC Playbook (Imperial FX)]] grading log, A+ only, to build a real sample of Adam's own judgment.

## 2026-10-13 follow-up
OB candle types, Demand 1/Gap/Demand 2, real vs fake zones and return types were all tested on gold 2020–26 with honest limit fills. Only a gap entry with a deep stop (M15, PF 1.07) is a thin lead; the FVG works best as a filter on breakouts (v1.04 A+). Full table: [[Chart Lessons Study]].

## Sources
- [StatOasis: I Backtested ICT / SMC — What Survives](https://statoasis.com/overfit/research/ict-backtest-what-survives)
- [Tangirala, Do Smart Money Concepts Predict Returns? (SSRN)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7483658)
- [IndicatorEdge: Smart Money Concepts research](https://indicatoredge.io/smart-money-research)
- [AlgoTraderPro: FVGs that hold (5,400-gap study)](https://algotraderpro.io/blog/how-to-trade-fvgs-that-hold/)
- [QuantTradingDiscoveries: FVG backtest EURUSD](https://quanttradingdiscoveries.substack.com/p/fair-value-gap-backtest-results-eurusd)
- [FXNX: Mitigation vs Breaker Block](https://fxnx.com/en/blog/ict-mitigation-vs-breaker-block-entry-rules)
- [MQL5 blog: Breaker blocks, 3 conditions](https://www.mql5.com/en/blogs/post/773691)
