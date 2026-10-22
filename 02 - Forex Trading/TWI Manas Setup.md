---
status: active
project: forex-trading
type: reference
---
# TWI Manas Setup

Pine v6 indicator built 2026-10-04 (~3 AM PT) on Adam's "Brand new fresh indicator using this image": six sketches posted by **JR_MANAS** (3 sell setups on the top row, the 3 mirror buy setups below). Source: `TWI Manas Setup.pine` (vault master; the deployed script differs only in a shorter header comment). Reference backtest: `Manas Setup Backtest.py` (read-only, MT5 bars, same logic).

**Status:** compiled 0 errors / 0 warnings (server check + editor). **v3 shipped 2026-10-04 ~3:20 AM (Adam: "Yes"):** "Require the $$ grab" now defaults OFF and the scorecard text is shortened (funnel as `413 > 156 > 90 > 48`, separate History and Status rows) so it fits a phone; compiled 0/0, saved over the same script (v2 -> v3, count still 50, no other script touched). **Adam's existing phone instance keeps its old saved inputs (the $$ requirement ON, old table text); to get v3 he must remove and re-add it, or just switch the $$ input off.** Saved as a NEW script via Make-a-copy: **"TWI Manas Setup", id `USER;d1bca7aef93b4f149129feb82f1ebbe5`** (script count 49 -> 50; every other script's timestamp unchanged). **Seen running on Adam's PHONE 2026-10-04 ~2:45 AM** (his phone layout accepted it): zones, BOS/$$ tags, WIN/LOSS labels and the table all render as designed. On the DESKTOP gold chart TradingView's Basic plan (2 indicators per chart) blocked adding it every time (see "The chart cap" below), so the first verification was compile + a Python replica, then his phone screenshots. Alerts are written (READY / FILL / WIN / LOSS) but none created. Not published.

## How I read the sketches (confirm or correct)
Every sketch is the same chain, sell as drawn, buy mirrored:
1. **Extreme:** the high (low) is either a **Sweep** of the previous swing, a **Double top/bottom**, or a **Plain** extreme.
2. **BOS:** price closes through the swing that started the move (the leg-start swing).
3. **$$:** price takes the internal liquidity, read as the swing formed by the first bounce after the BOS.
4. **Entry box:** price returns to the zone at the extreme (the candle at the origin), then the move continues (long arrow).
Unclear in the sketches: what "$$" exactly marks (I used the bounce swing), the zone height, the stop and the target (the arrow is open-ended). Those are inputs.

## Rules as built
Pivots L=3/R=3, confirmed (no repaint). **Origin:** Double if the extreme is within 0.3 ATR of the prior swing; Sweep if it exceeds the prior swing and price closes back below it; else Plain (each type can be switched off). **Zone** = the extreme candle high down to its low, capped at 1.5 ATR. **BOS** = a close through the leg-start swing before a close beyond the zone (expires after 150 bars). **$$** = the highest confirmed swing after the BOS that sits below the zone; "taken" when a bar's high exceeds it (switchable). **Entry** = a limit at the zone's near edge (or middle). **Stop** = beyond the zone + 0.25 ATR. **Target** = the lowest low since the extreme (Structure) or 1.5/2/3R; skip if RR < 1.0. Fill bar: only the stop counts. One setup per side. Table: R scorecard by sell/buy and by origin type, a funnel (armed > BOS > $$ > filled), "History since", and a standing **UNVALIDATED** tag.

## Reference backtest (2020-2026, MT5 bars, net of cost, 4 variants fixed in advance, 5 market/timeframe sets)
| R / PF | V0: as drawn ($$ required, structure target) | **V1: no $$ requirement** | V2: 2R target | V3: entry at zone middle |
|---|---|---|---|---|
| Gold H1 | −68.8R / 0.70 | −2.1R / 0.99 | −67.7R / 0.68 | −134R / 0.44 |
| Gold H4 | −5.9R / 0.90 | +11.4R / 1.15 | −10.4R / 0.79 | −2.5R / 0.96 |
| USDJPY H1 | −34R / 0.84 | +56R / 1.18 | −51R / 0.74 | −55R / 0.75 |
| EURUSD H1 | −13R / 0.95 | +81R / 1.23 | −32R / 0.86 | −66R / 0.74 |
| GBPUSD H1 | −45R / 0.81 | +41.5R / 1.12 | −21R / 0.90 | −42R / 0.82 |

**Read:**
- **As drawn it loses on all five sets.** Requiring the $$ grab removes ~40% of the fills and turns the model negative; dropping it (V1) makes four of five sets modestly positive (PF 1.12-1.23, both halves positive on EURUSD/GBPUSD/gold H4, USDJPY's second half ~flat; gold H1 breakeven).
- **V1 was chosen AFTER seeing V0 fail, so it's exposed to data-mining** (4 variants x 5 sets, all on this one history).
- **The profit follows the trend, not the pattern:** V1 sells lose on gold and USDJPY (up-trending: sells -47R gold H1, -31R USDJPY) and win on EURUSD/GBPUSD (sells +72R, +30R); V1 buys win on gold H1/H4 and USDJPY (+45R, +28R, +88R). Same pattern as the EMA ribbon: with-trend fades pay, counter-trend ones don't.
- **Origin type doesn't matter much:** Sweep is not special (V1 gold H1 sweep -44R, double +17R, plain +25R; elsewhere all three are mildly positive). Doubles are the rarest (11-68 trades).
- **Structure target beats 2R; entry at the zone edge beats the middle** (the middle entry shows win rates of 6-13%).
- Compare with the earlier same-family models: [[TWI SMC POI]] Reversal (72 trades -7R at 1.5R), [[TWI BOS Trap Entry]]. Same conclusion: no edge from the pattern alone.

## The chart cap (why it could not go on the desktop chart)
Adam's TradingView plan is **Basic = 2 indicators per chart**. The desktop gold chart already held 3 (Adaptive Head and Shoulders Detector, TWI fxalexg HS, Sweep Reversal Map [Herman]); the TWI EMA Ribbon had been added as a 4th (it worked once, unexplained). On 2026-10-04 the add for Manas triggered TradingView's "More indicators" upgrade pop-up three ways (editor "Add to chart", the Indicators dialog > My scripts, and after hiding the 3 others: **hidden indicators still count**). To free a slot I removed my own TWI EMA Ribbon, but Manas was still blocked and the ribbon can't be re-added either. **Net state: the chart has Adam's original 3; both new indicators (ribbon, Manas) are saved but off the chart.** Needs Adam's decision (drop two of the three to run one of mine, or upgrade the plan). Did not use `layout_new` (opens a second tab; the one-tab rule in [[TradingView Chart Drawing]]).

## Related
[[TWI SMC POI]], [[TWI BOS Trap Entry]], [[TWI Liquidity Sweep BOS]], [[TWI EMA Ribbon]], [[EMA Ribbon Trend Research]], [[Forex Trading]]

## First live read on Adam's phone (2026-10-04 2:45-2:48 AM, XAUUSD 30m, history since 2026-01-01, 8,933 bars)
Table: **48 trades, 17% win, -28R, PF 0.3**; sell 22 tr 14% -14.5R; buy 26 tr 19% -13.5R; Sweep 17 tr 18% -9.5R; Double 9 tr 0% -9R; Plain 22 tr 23% -9.5R; funnel armed 413 > BOS 156 > $$ 90 > filled 48; dropped: RR 0, cancelled 287. **Cross-check:** my Python replica on the MT5 feed for the same dates (30m, since 2026-01-01, no cost): 54 trades, 17% win, -14.1R, PF 0.69 (sell -2.0R, buy -12.2R). Trade count and win rate match closely, so the Pine implements the rules; the R total differs because the two feeds cut candles differently and a 17% win rate lives on a few large winners. Cosmetic: the last table row is clipped on the phone ("UNVALIDATE...") and BOS/LOSS labels overlap at times. Adam's screenshots show clean reactions at several sweep zones (a WIN +1.5R, several LOSS -1R); one SELL Sweep at ~4,300 lost as gold kept rising.

## Adam's claim: "the sweep signals are good buy and sell signals, not all are winners" (tested the same night)
Script `Manas Setup Sweep-Trend Test.py`. Variants fixed in advance: sweep-only vs all origins, with/without the $$ requirement (V0/V1), with an entry-time trend filter (sell only below EMA89 / bear ribbon stack, buy only above / bull stack).
- **Self-caught look-ahead error:** the first version of the trend filter used the fill bar's own close/EMA, which is unknown when a resting limit fills. It showed PF 2-4 with both sides winning on every market, which was an artifact. Corrected to use only the previous bar's trend; the real numbers are below. (Lesson: any filter on an intrabar limit fill must use data from before that bar.)
- **Sweep vs all origins (V1, no $$):** gold H1 -27.5R vs all -2.1R; gold H4 +0.5R vs +11.4R; USDJPY +62.5R vs +56.2R; EURUSD +80.6R vs +75.9R; GBPUSD +57R vs +41.5R. **Sweeps are not reliably better than the other origins** (as drawn, V0 sweep-only: gold H1 -44.6R, gold H4 -8.7R, USDJPY -27R, EURUSD -9.8R, GBPUSD +12.5R).
- **Trend filter (prev bar) on sweeps, V1:** gold H1 +22R PF 1.33 (vs -27.5R), gold H4 +8.9R PF 1.51 (31 tr), EURUSD +42R PF 1.70, **USDJPY -5.5R PF 0.92 (vs +62.5R), GBPUSD +4.5R PF 1.07 (vs +57R)**; it cuts the trade count by ~70% and helps only on some markets. The ribbon-stack version is weaker still (14-50 trades per set). **No consistent improvement.**
- Verdict: the zones mark real reaction points, but mechanically taking every sweep signal has no reliable edge (win rate 18-35%, payoff doesn't cover the losses); use it as a scanner/map and apply judgement, not as an auto-signal.
