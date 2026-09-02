---
status: active
project: forex-trading
type: log
---
# Chart Analysis Notes

Running log of discretionary chart analysis and strategy discussion with Adam — separate from [[Review Trades and Risk Management]], which is specifically about reviewing the automated TWP ORB EA's trades. This note is where manual chart reads, levels, and terminology land so a future session (voice or terminal) doesn't start cold. Append new entries under a dated heading; don't rewrite old ones.

## Standing job (2026-09-01): live trade-assistant role, XAUUSD focus
Adam asked Jarvis to become an ongoing live trade assistant — read charts, apply the frameworks already documented below (Sweep+MSS+Fib+OB, Ghost Trading, Market Structure HH/HL/LH/LL+BOS/CHoCH), and call out high-probability setups on demand, teaching the reasoning alongside each call. Scope: XAUUSD only for now. Reuses the existing [[TWI Sweep MSS IDM BOS OB]] indicator (already live on OANDA:XAUUSD 15m) and [[TWI Weekly Bias]] for HTF context — no new indicator needed to start. This note is the job's home; new live reads land under dated headings below as before.

## 2026-09-02 — XAUUSD 15m, first live read under the new trade-assistant role
Chart set OANDA:XAUUSD 15m, both custom indicators live ([[TWI Sweep MSS IDM BOS OB]] + [[TWI Weekly Bias]] — replaced the default RSI Bars/ADX to fit TradingView Basic's 2-indicator cap, same constraint noted in [[TWI Scalp POC]]).

**Real sequence confirmed against actual OHLCV, not just label proximity:** sharp selloff from ~4449 down to a swing low of **4315.8** (bar 1788307200, O4324.455/H4330.55/L4315.8/C4328.355) on **volume 11,139 vs a ~2,000-3,800 local baseline** — a real 3-5x spike, not noise. The indicator's SWEEP label sits exactly on that bar's low (4315.8). Next bar closed 4328.345→4329.925, current price 4331.495 (`quote_get`) — price reclaimed back above the swept low on the volume spike, classic liquidity-sweep-and-reverse.

**Order block zone (from `data_get_pine_boxes`):** 4316.285–4322.005 — sits right against the sweep wick, matches the OB definition (last down candle before the reversal impulse).

**Not yet a confirmed entry.** No MSS/BOS label has printed above the sweep yet — the indicator hasn't confirmed the structure shift. Watching for a 15m close back above the nearest lines-above-price (4344.545 / 4347.575 / 4351.765) as the real MSS confirmation before calling this tradeable.

**Context:** [[TWI Weekly Bias]] table reads `WkBias: BUY WEEK`, `Detail: W▲ D– H4▲ L▼` — weekly and H4 lean bullish, daily neutral, LTF bearish (matches the sharp intraday drop that just got swept).

**Standing plan given to Adam:** wait for the MSS close-confirmation above ~4345-4351 before treating this as a real long; if it comes, OB retest (4316-4322) is the ideal entry zone, invalidation below 4315.8, first real target near the historical TARGET/line cluster at 4396.5/4404.3.

## 2026-09-02 — EURUSD, 15m zone + 5m pullback entry, clean win
Adam's own manual read, mobile MT5: marked a supply zone on the 15m (1.15904-1.15932, matching the swing highs there), waited for the 5m pullback into that zone, entered short, price dropped straight through to 1.15785 with no real retest — RSI (14) sliding from ~30 (15m) to ~26.6 (5m) on the drop, no bounce. Adam's own words: "played out perfect." Real, clean confirmation of his standing 15m-zone/5m-entry approach — logged as a win, no correction needed.

## Terminology Adam uses
- **Order block (OB):** the last down-close (bearish) candle immediately before an impulsive up-move that breaks structure. Marked as a box spanning that candle's high to low, typically extended forward in time. (Bearish OB is the mirror: last up-close candle before an impulsive drop.)
- **MSS (Market Structure Shift):** the point where price breaks prior structure, confirming a directional shift (e.g. "MSS (Bullish)" marks confirmation of an upward shift).
- Adam trades off a custom TradingView template called **"Pafx Secret indicator"** — draws Fib retracements, MSS labels, long/short position boxes automatically on his charts.

## Lessons (fold corrections in here over time)
- **No broker's feed "previews" another's.** GBPUSD trades on dozens of interbank venues at once — OANDA (TradingView's chart feed) and AAAFx (Adam's real broker) both just window into roughly the same underlying market. Any moment one ticks first is noise from two separate feeds, not a real lead/lag edge. Confirmed 2026-08-18 after Adam noticed TradingView "almost gives a look into the future" — real answer: don't time real entries off what the OANDA chart does first.
- **Recalculate COMBINED risk every time a position gets added to an existing idea, not just the new position in isolation.** On 2026-08-18's GBPUSD short, a third manual entry (0.5 lots @ 1.35440, stacked on the existing 0.5 lots @ 1.35382) pushed total risk to stop to ~$395 — on an ~$800-885 account, that's ~45-49% of the account on one stop-out, even though each individual position looked reasonable-ish alone and the combined R:R (~1.55:1) looked fine. Adam caught it himself after seeing the real combined number and said he should've waited before adding the third.
- **Stacking into a move that hasn't confirmed yet compounds the fill-status-confusion risk from earlier the same night** (see the fill-status correction above) — don't add to a position based on "it's about to tap" without the same rigor (real OHLCV history, not zone-proximity guessing) used to confirm the first fill.
- **2026-08-19, rejection confirmed:** Adam drew his own Fib on mobile (synced live to the Desktop chart, same TradingView account) anchored 1=1.35717 (the sweep high itself, not the wider 1.35806 stop) to 0=1.35194, with 0.81-0.84 (1.35618-1.35633) flagged by his strategy as the rejection zone. Price pushed up through it — RSI hit 73 (1H) and 75 (M5), both overbought — then the M5 candle wicked to 1.3566 and closed back down to 1.35617/1.35619, confirmed on both OANDA's feed and Adam's own broker. Real confirmation: overbought + exact rejection-zone tap + closed reversal candle, not just "it's overbought so it should turn." Bearish structure re-validated. Watching for follow-through back through 0.71/0.618 (1.35565/1.35517) toward the 1.34798 target next.
- **FINAL OUTCOME, 2026-08-19: stopped out, real loss.** After hours of chop through a rejection candle, double top, engulfing candle, FVG retest, head-and-shoulders, and triple top — all of which pointed bearish — price broke the OB down to 1.35502 (the real trigger, finally), then reversed hard and ran straight through the sweep high and the stop, closing at 1.36075+ (269 pips above where tracking started). All three positions closed within the same second, confirmed from Adam's real broker history:
  - 0.5 @ 1.35382 → 1.35718: −$168.00
  - 0.5 @ 1.35383 → 1.35724: −$170.50
  - 0.5 @ 1.35446 → 1.35722: −$138.00
  - **Total: −$476.50 on 1.5 lots combined** — roughly 55-60% of an ~$800-885 account on one trade.
  - Correction to the tracking above: "two trades at 1.35382" were actually two separate 0.5-lot positions (1.35382 and 1.35383), not one netted 0.5 — the running combined-P/L estimates through the night understated true exposure by treating them as one position.
  - **Real lesson, not a technicals lesson:** every layer of confluence tracked overnight (RSI, double top, engulfing candle, H&S neckline, triple top) pointed the same direction and the market still reversed hard against all of it. Confluence stacking increases confidence, not certainty — it never guarantees direction. The account-threatening part wasn't being wrong; it was sizing three adds into an already-losing idea, which turned a normal bad trade into a 55-60%-of-account loss. This directly validates the earlier 2026-08-18 lesson about recalculating combined risk on every add — it wasn't heeded here since the adds happened before that lesson was written.
- **2026-08-18 decision: no further adds on this trade.** Price did confirm a real tap through 1.35518 on both OANDA and AAAFx shortly after the third position went in, but Adam held the line — decided to ride out the existing 1.0 lot combined position (SL 1.35806, TP ~1.34798) rather than stack a fourth on top of the already-flagged ~$395/~45-49%-of-account risk. Applying the lesson immediately, not just writing it down.

## 2026-08-20 (afternoon) — 10-pair TWI True North scan + real gold BUY LIMIT order review

**Scan result: zero ACTIVE setups** across GBPUSD, XAUUSD, EURUSD, USDJPY, AUDUSD, USDCHF, USDCAD, NZDUSD, XAGUSD, EURJPY (5m) — every pair's last tracked signal already resolved (mostly TP2 HIT, a couple STOPPED). Same blunt-but-correct outcome as the first scan on 2026-08-19. GBPUSD (Live Score 7/10, needs 6) and XAGUSD (6/10, right at threshold) were the closest to a fresh signal, still waiting on the actual crossover+RSI trigger — high confluence alone doesn't fire an entry.

**Real broker gold trade (overnight, lost)**: Adam reported a loss on the manual XAUUSD trade from the previous night. Not visible from TradingView — no MT5 account connection — so unconfirmed mechanically, but consistent with price action: current price (~4529.66) is above both the real stop (4480) and target (4515) from that trade, meaning it most likely hit the 4480 stop first and the market rallied afterward without the position in it.

**New pending order reviewed (screenshot from Adam's phone, MT5 mobile, XAUUSD M15):** BUY LIMIT 0.02 lots at 4466.79, SL 4446.47, TP marked ~4529.

**Real finding: the TP was already trading even with current price before the order even filled.** Price was sitting at 4529.33 — right on the TP line — while the entry (4466.79) hadn't been touched. The entry level itself was technically sound (sits almost exactly on the 61.8% retracement of the 4446→4534 impulse, stop placed just below the origin of that rally — standard POI/demand-zone logic), but the reward leg of the trade had already happened without the position in it. If the pullback to 4466 never comes, the order just expires; if it does fill later, the TP is stale — it marks a level price already visited, not new upside ahead of price. RSI was 58.93 (mid-range, no exhaustion signal either direction). Flagged to Adam to either move the TP to a real level ahead of price or cancel the order; his to handle from his phone.

**Standing lesson from this one:** always check a pending order's TP against *current* price before evaluating its R:R — a technically well-placed entry can still be attached to a target that's already been reached, which silently breaks the reward side of the trade's math without anything about the setup itself looking wrong.

## 2026-08-20 — USDJPY 15m short off [[Momentum Signal Suite]], closed manually for a small loss (~$4)

First real trade taken off the rebuilt indicator. Full record because the outcome is instructive and cheap.

**The setup:** SELL fired at **4/8 — the exact minimum score** the system allows (threshold was 4). Entry 158.439, SL 158.591, TP1 158.287, TP2 158.135. HTF Bias Bearish, descending trendline overhead intact, price rejected off the 158.72 high. Adam was set for **TP1 only**.

**The structural problem, flagged before it played out:** the anchored **Previous Day POC sat at 158.411 — between entry and TP1**. Both targets were on the far side of yesterday's highest-volume price, so the trade could not pay without cutting through the day's magnet level. Also flagged: a *bullish* TL BREAK label fired moments before the bearish signal — conflicting structure, i.e. chop.

**What actually happened:**
1. Price broke below the POC — one confirmed 15m close at **158.395**.
2. It could not hold. Next bar **reclaimed back above** the POC (158.424).
3. Once reclaimed, it ran up and tagged **158.488**, through the 158.486 invalidation level.
4. Adam exited manually before the stop for roughly **−$4**.

**Lessons banked:**
- **The POC reclaim is the invalidation tell, and it fires before the stop does.** A break below the anchored POC that immediately gets bought back above is a failed breakdown — that reclaim was the exit signal, and it appeared while the trade was still near breakeven. Watch the reclaim, not just the stop.
- **A minimum-score signal is a minimum-quality signal.** 4/8 means half the confluences were absent. It is not invalid, but it is the weakest thing the system will print — size and expectations should reflect that. Consider whether minimum-score signals are worth taking at all, or whether the floor should be 5.
- **Shorting/buying into an anchored POC that sits between entry and target is a structural flaw in the trade, not a detail.** Check where PD POC sits relative to entry and TP *before* taking the signal.
- **Correct handling of a 1:1 target:** TP1 (1.5 ATR) against SL (1.5 ATR) is 1:1, which loses money at the 40–48% win rates measured on this indicator. The fix offered was tightening the stop to structure (~158.51, above the 158.486/158.503 swing highs), converting 1:1 into ~2.1:1 without needing TP2. Note also that an earlier "move to breakeven" suggestion was **withdrawn as wrong** once price reclaimed the POC — breakeven at 158.439 sat only 1.5 pips from price and would have been noise-stopped.
- **Contrast with 2026-08-19's −$476.50:** same fundamental situation (a directional idea that failed), radically different outcome, purely because of sizing and a fast manual exit. Small loss on a weak signal is the system working correctly.

**Alerts left standing on FX:USDJPY** (ids 5416277989 / 5416279157 / 5416281651): >158.486 warning, <158.400 POC break, <158.287 TP1. All fire at 1m resolution, so they trip on wicks — treat a fire as "go look," not confirmation. Delete when stale.

## 2026-08-19 — USDJPY, fresh setup scanned for after the GBPUSD loss (higher-timeframe confluence check, per Adam's explicit ask)
Scanned majors on 4H for context before drilling in, per the GBPUSD lesson above (never fought the higher-timeframe trend, this time checking it first). EURUSD's clean 4H uptrend (1.15548→1.16763, accelerating volume) confirmed the reversal that stopped out GBPUSD was broad USD weakness, not GBP-specific — useful context for not fighting the same move on other USD pairs.

**USDJPY, 1H, real setup, not yet played out:**
- Sweep high: **159.78**
- MSS confirmed by a genuine breakdown candle (159.158→158.162, 98-pip range) on **volume 35,042** — 3-5x the surrounding average, real participation not noise
- Order Block: the small consolidation just before the breakdown, ~159.09-159.19
- Fib 0 (recent low): **158.044**. Fib 0.71 entry zone: **159.277**. Fib 0.618: **159.117**.
- As of this note, price is sitting at 158.17-158.59, still below the entry zone — **hasn't retraced up into 159.12-159.28 yet**. The trade is watching for that retest-and-reject, not assuming it happens. Plotted on TradingView Desktop (1H) with the same label conventions as the GBPUSD framework.
- Explicitly not confirmed as "the move" the way GBPUSD's overnight setup falsely felt confirmed multiple times — applying the lesson from that trade: wait for the actual retest-and-reject candle before treating this as real.

## Standing setup framework #2: Market Structure (HH/HL/LH/LL + BOS/CHoCH + multi-timeframe bias)
A second, distinct framework from Sweep+MSS+Fib+OB above — added 2026-08-19 from screenshots of a YouTube market-structure video Adam shared. The on-chart indicator is **Structure OS by Lewis-Kelly** (invite-only, [tradingview.com/script/SVUkldyr-Structure-OS](https://www.tradingview.com/script/SVUkldyr-Structure-OS/)) — confirmed by name match to the on-screen "Structure OS" label, not guessed.

**Swing labels:**
- **HH** (Higher High) — new upside extreme.
- **HL** (Higher Low) — pullback holds above the prior low.
- **LH** (Lower High) — pullback fails below the prior high.
- **LL** (Lower Low) — new downside extreme.
- Uptrend = a sequence of HH+HL. Downtrend = a sequence of LH+LL.

**BOS vs CHoCH — the critical rule is close-based, not wick-based:**
- **BOS (Break of Structure)**: a candle **closes** beyond the swing level *in the direction of the current trend* — confirms continuation.
- **CHoCH (Change of Character)**: a candle **closes** beyond the swing level *against* the prevailing trend — signals a reversal.
- **Wicks through a level don't count.** Only a close beyond the structural level triggers either event. (This is a stricter, more reliable rule than eyeballing a wick — directly avoids the kind of "did it really break or just wick through" ambiguity that caused real confusion on the GBPUSD trade the same night this was saved.)

**Directional Bias table (Weekly/Daily):** compares the previous candle's close against the prior period's high/low. Bullish if close > prior period high, Bearish if close < prior period low. Also flags **sweeps** — when a high/low was broken intra-period but the close came back inside the range (same concept as the Liquidity Sweep in the other framework, just defined mechanically here).

**Market Structure table (per-timeframe, H4/15M/1M, multi-timeframe):** for each timeframe higher than the current chart, reports direction (bullish/bearish) and a **stage**: Shift, Confirmed Shift, Expansion, or Continuation. Only timeframes above the active chart are shown — read the higher timeframes for context, then drop down for the actual entry.

**Internal structure (iBOS/iCHoCH):** the same 3-candle-close confirmation logic, but confined inside the current swing range and resetting on every new swing break — tracks pullbacks *within* a swing separately from full swing-level reversals.

**How to actually use it (inferred from the screenshots' sequence, not yet trade-tested):** check the Directional Bias table for Weekly/Daily context first, then the Market Structure table for higher-timeframe (e.g. H4) confirmation, then drop to a lower timeframe (15M) and watch for a CHoCH against the H4 bias followed by a BOS confirming the new direction — i.e., multi-timeframe alignment before entry, similar in spirit to the "1h → 15m → 5m" sequence already used for Sweep+MSS+Fib+OB.

**Not yet used on a real trade** — this is a fresh addition, saved for reference and comparison against the existing framework, not validated in practice yet.

## Standing setup framework #3: Ghost Trading ("Boo Trading") — added 2026-08-20
Adam's own named pattern, given to Jarvis as a full spec to learn, trade, explain, and eventually code. A short-bias (bearish) reversal pattern, best on gold 5m/15m but works on majors too. Distinct from Sweep+MSS+Fib+OB above — no Fib required, entry is the engulfing candle's own close, not a retracement level.

**Anatomy (why it looks like a ghost on the chart):**
1. **Big Push (the "impulse")** — a strong directional candle/run that sets a clear swing high (short bias) or low (long bias).
2. **Consolidation (the "ghost body")** — price coils into a tight range/flag. Traders get trapped here expecting continuation.
3. **Liquidity Sweep (the "ghost head")** — a wick spikes above the swing high (or below the swing low), sweeping resting stops, then the candle **closes back inside or below the consolidation range**.
4. **Bearish Engulfing (confirmation)** — a strong candle immediately after (or as part of) the sweep engulfs the prior 1-2 candles and closes below their opens. This is what confirms the real move is down, not the sweep alone.

**Entry:** wait for the full sequence, then enter on the engulfing candle's close, or on a small retrace into its body. Want HTF (15m/1H) context: a prior structure shift or clear resistance overhead.

**Stop:** just above the high of the sweep wick (the "ghost head" tip). On 0.01 lot gold, typical risk is $20-35 depending on wick height.

**Target:** primary = nearest demand zone/order block/prior support below. Secondary = 1.5R-3R. Optional partial at 1R.

**Quality filters:** prefer it forming after a genuine BOS to the downside; RSI *not* extremely oversold on entry timeframe; avoid if the engulfing candle is already huge and deep into the next support (immediate-reversal risk).

**What a detector needs to check, in order** (for a future Pine/MQL5 build, not built yet): (1) a strong impulse candle/sequence, (2) a tight low-volatility consolidation range, (3) a candle breaking the recent high with a long upper wick that closes back inside the range, (4) a subsequent/concurrent candle engulfing the prior 1-2 and closing below their opens, (5) optional volume spike or HTF bias as a bonus filter, not a gate — consistent with the standing no-hard-gates rule already applied to [[TWI True North]] and [[TWI Sniper ORB]].

**Live example, same day it was given (2026-08-20, gold M15, real):** Adam's chart showed the pattern legibly — a strong impulse off the 4446 low up through the 4509-4534 consolidation, a wick spiking toward the top of the visible range sweeping the recent swing high, and a marked bearish reversal candle right after. RSI at the time was 50.98 — squarely mid-range, passing the "not extremely oversold/overbought" filter. A real SELL 0.01 was showing live on the chart, floating ~-$1.16 (a fresh fill). **Confirmed by Adam: SL 4550, TP 4470.** Entry back-calculated from the floating P/L (-$1.16 on 0.01 lot ≈ $1.16 adverse move) at roughly 4520. Risk ≈ $30 (SL 4550 − entry ~4520), reward ≈ $50 (entry ~4520 − TP 4470), **R:R ≈ 1.67:1** — the $30 risk sits right inside the framework's own "$20-35 on 0.01 lot" range, and 4550 lines up with where the sweep wick's high looked to be on the screenshot, so the stop is correctly placed per the spec (just above the ghost head), not guessed. **Real confluence spotted**: TP 4470 sits almost on top of the 4466.79 demand zone identified earlier the same session (the BUY LIMIT's entry level, from the 61.8% retracement read) — meaning if this short plays out to target, price walks right up to filling that resting buy limit too. Two independent reads landing on the same zone from opposite directions is a real signal the level matters, not a coincidence to ignore. Per [[Forex Trading Fundamentals#Risk management|the breakeven win-rate math]], 1.67:1 needs >37.5% of similar Ghost setups to win to be profitable over time — achievable if the pattern holds up, worth tracking outcome-by-outcome once Adam has taken a few. Separately, the earlier-flagged stale BUY LIMIT TP (was sitting at the already-passed ~4529 level) had been moved down to 4470.39, just above its 4466.79 entry — the fix from the earlier review was applied.

## Custom indicator built 2026-08-19: "Momentum Signal Suite"
Adam shared screenshots of three different vendor indicators (a free scalping system, a "Power Trend" MA-ribbon system, and a paid "X DIAMANTE" signal service) and asked for a clean combination of the same *ideas* — BUY/SELL signal labels, a trend-strength read, auto S/R zones, a win/loss tracker — built fresh, not copying anyone's actual code or branding (none of those vendors' source was available anyway; only their rendered charts).

**What it does:** EMA(9)/EMA(21) cross filtered by RSI generates BUY/SELL labels; a win/loss tracker checks each signal's outcome after a configurable lookahead (ATR-multiple threshold) and keeps a running win rate; pivot-based S/R zone boxes; a stats table. All of this computes every bar regardless of display settings.

**Display is signals-only by default** (Adam's ask, 2026-08-19) — three toggles (`Show EMA Lines`, `Show S/R Zones`, `Show Stats Table`) default to off, so only the BUY/SELL labels render, but the underlying EMA/RSI/zone/win-loss logic keeps running underneath and can be switched on any time.

**Built as an on-chart overlay only** (`overlay=true`) — a real Pine constraint discovered while building it: one script's output is either bound to the main price pane or to its own separate pane, never both. A below-chart oscillator/histogram companion (matching the "trend-strength meter" panels in the reference screenshots) would need a second, separate script (`overlay=false`) added alongside this one — not built yet, flagged as a natural next step if Adam wants the oscillator piece too.

Compiled clean (`pine_smart_compile`, zero errors), saved to TradingView cloud, and confirmed live on the chart via `chart_get_state` before screenshotting the working result to Adam.

## Standing setup framework: Sweep + MSS + Fib + OB
Adam's core discretionary playbook (source: a Facebook post from "The Ultimate Trader," saved as reference 2026-08-18 — already applied to the XAUUSD and GBPUSD setups below before this was written down). Four confirmations, in sequence:
1. **Liquidity Sweep** — price wicks past a prior high/low (taking out resting stops) before reversing — the "Sell Side Liquidity" / "Protected High" sweep.
2. **MSS (Market Structure Shift)** — the reversal breaks prior structure, confirming direction (see MSS definition above).
3. **Fibonacci** — draw the retracement from the sweep extreme (0) to the post-MSS swing (1); the 0.71 level is the flagged entry zone in the reference post.
4. **Order Block (OB)** — the last opposing-color candle before the impulsive MSS move, used as the precise entry/confirmation zone (see OB definition above).
Entry is where the Fib pullback (toward 0.71) meets the OB zone. Use this sequence as the checklist for any new discretionary setup review, not just gold/GBPUSD.

## 2026-08-17 — XAUUSD (Gold) order block + general session
- Identified and marked a **bullish order block on XAUUSD (OANDA), 1h chart**: box from **4,325.000 (top) to 4,311.847 (bottom)** — the last red candle before the sharp rally into the "MSS (Bullish)" break shown on his Pafx template. Fib anchors on his chart: 0 = 4,311.847 (the OB low), 1 = 4,437.560 (swing high).
- Voice-line conversation (separate session, same evening) covered: USD/CHF bearish momentum (support ~0.8029, next floor ~0.7759–0.7759 range, RSI hit ~16 = deep oversold, Fed easing bias vs. flat SNB as the driver), and EUR/USD America-session dynamics (soft US data / dollar weakness as the theme, 1.1280 as a watched downside level).
- See [[TradingView Chart Drawing]] for how the order block box actually got placed on the chart.

## 2026-08-18 — XAUUSD (Gold) full round-trip back to the order block
- Read the chart live via the **TradingView Desktop app** (new CDP transport — see [[TradingView Chart Drawing]]), 15m timeframe, Adam's saved Pafx template.
- Since the 2026-08-17 bullish order block (4,311.847–4,325.000) and MSS break, price rallied all the way to the 4,437.560 swing high (the Fib "1" anchor) — then fully reversed, breaking down through every retracement level (0.618, 0.71, 0.84) back to **4,331.93**, sitting right on top of the same order block it launched from.
- Adam's indicator flagged a **"Liquidity Sweep"** near the recent low, ahead of this retest.
- Read given to Adam: holds 4,311.847 → OB validates again, classic retest-and-continue; closes below it → OB is dead and the bullish MSS is invalidated. No clean signal yet — price is sitting in the decision zone.

## 2026-08-18 — GBPUSD short, Sweep+MSS+Fib+OB framework, real order placed
- Prompted by a Facebook post Adam shared (see the [[Chart Analysis Notes#Standing setup framework Sweep + MSS + Fib + OB|framework]] above, saved from that same post) — a live GBPUSD short mirroring the gold trade's structure: liquidity swept above the recent 1H swing high (~1.357), MSS down, entry off the OB/Fib zone.
- Adam drew and placed a real **Sell Limit** independently on TradingView mobile. Corrected two things before it went live: his first SL sat with zero buffer right on the exact swept high (real whipsaw risk) — widened; his position size was 15.4% account risk on an $885 balance — flagged and resized.
- **Final order, confirmed 2026-08-18 via TradingView Desktop's native short-position tool (`tradingview-mcp`'s `draw_get_properties`):** Entry **1.35518**, Stop **1.35806** (288 points / ~28.8 pips, above the swept high — the widened buffer), Target **1.34790** (728 points / ~72.8 pips), R:R ≈ 2.5:1.
- Plotted the same zone on Desktop for visual reference (drawn, verified via screenshot, then removed once the more precise native position-tool numbers above were pulled — no need for two overlapping approximations of the same trade).
- **Reconstructed the Fib math and confirmed it matches the framework exactly:** treating stop 1.35806 as the "1" anchor and target 1.34790 as the "0" anchor, entry 1.35518 lands at the **0.71 retracement** — within a pip of the framework post's own stated entry level. Strong confirmation the Pafx template used the same 0.71 rule documented above.
- **Plotted the full Sweep+MSS+Fib+OB framework on TradingView Desktop** via `tradingview-mcp`'s `draw_shape` (first full production use of the tool, not just a test): "Liquidity Sweep" label at the swept wick, "MSS (Bearish)" label at the breakdown candle, an Order Block box on the pre-sweep consolidation candle, and three full-width Fib lines (1 / 0.71 / 0) at the real stop/entry/target prices. Screenshot-verified and sent to Adam. Native `short_position` risk box left in place alongside it, not removed.

### Fill-status correction (2026-08-18, important — read before touching this trade again)
Voice-line's Jarvis told Adam the 1.35518 entry had "already traded through" and he was in the trade, reasoning from price sitting *below* the OB zone as if that confirmed a fill. **That reasoning is backwards for a Sell Limit** — a sell limit fills when price rises *up to* the limit price, not when it falls below it. Terminal-session Jarvis then made its own error in the opposite direction: checked only the most recent ~15 hours of bars, saw price below 1.35518, and told Adam the entry had *never* been hit at all — also wrong, from too short a lookback window.

**The actual verified history** (pulled the full OHLCV series back through the sweep, checked every bar's high, not just current price):
- Sweep + MSS breakdown occurred ~1786953600–1786986000 (swept up to 1.3571, broke down through 1.35444).
- **Real retest into the OB zone**: bars from 1787007600–1787014800 traded up to **1.35542** — above the 1.35518 entry. If Adam's original Sell Limit was live on his broker, it almost certainly filled in this window.
- Price then continued down to a low of 1.35197 (bar 1787036400), and has ranged roughly 1.352–1.354 since.
- **Adam separately, manually placed two more sell trades at 1.35382** — a later, worse entry than the plan (sold lower than the planned 1.35518), entered after price had already fallen well past the OB zone.
- **Confirmed via Adam's real broker screenshot (AAAFx, his actual live account — separate from TradingView Desktop's OANDA chart feed, which is why the two platforms show slightly different prices):** combined position **0.5 lots**, entry ~1.35382, **SL 1.35806** (matches the plan exactly), floating P/L **−$29.60** at check time. Risk to stop ≈ 42.4 pips ≈ **$212** at 0.5 lots; reward to the 1.34790 target ≈ 59.2 pips ≈ **$296**; R:R ≈ **1.4:1**.
- The "SELL 1.35421" / other order-looking tags seen on the TradingView Desktop screenshot are **not** Adam's real AAAFx position — `data_get_trades` (Strategy Tester) came back empty, and AAAFx isn't connected to TradingView. Likely just TradingView's own price-axis labels or an unrelated demo click. Don't confuse these with the real trade.

**Standing rule going forward, for any session (voice or terminal):** never declare a pending limit/stop order "filled" from price-vs-zone proximity alone. Pull the actual OHLCV history back to when the order was placed and check whether any bar's high (for a sell limit / buy stop) or low (for a buy limit / sell stop) actually crossed the order price. A short recent-bars window is not enough — check back to the order's actual placement time.
