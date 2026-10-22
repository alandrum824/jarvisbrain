---
status: active
project: forex-trading
type: reference
---
# EMA Ribbon Trend Research

Adam asked (2026-10-03 ~3 AM PT): "What about trend buy and sell with ribbon ema". He had shown a "Power Trend" MA-ribbon vendor system on 2026-08-19 (see [[Chart Analysis Notes]], [[Momentum Signal Suite]]). This is the evidence run before building anything. Script: `EMA Ribbon Backtest.py` (read-only: pulls bars through the MT5 link, no order functions; run with the `mt5-readonly` venv, see [[MT5 Read-Only Link]]).

## Rules tested
Ribbon = EMAs 8/13/21/34/55/89. **BUY** when the ribbon first becomes fully stacked bullish (8>13>21>34>55>89) with the close above the 8; **SELL** mirrored. Entry = next bar open. Exit = EMA8 crosses EMA21 against the trade, or an initial stop at 2 × ATR(14). If a bar touches the stop it is scored −1R. Cost = the broker's *current* spread per trade (conservative: gold read 218 points on a closed-market Saturday vs ~52 normally). Data: AAAFx terminal bars, 2020 to 2026-10-02 (M15 only 2024+).

## Results (flip entry, 2 ATR stop, R net of spread)
| | M15 | H1 | H4 |
|---|---|---|---|
| XAUUSD | −211R / 1,492 trades (PF 0.80) | −42R / 985 (PF 0.94) | **+69.5R / 244 (PF 1.50)** |
| EURUSD | −647R (PF 0.50) | −137R (PF 0.79) | −10R (PF 0.93) |
| GBPUSD | −722R (PF 0.49) | −202R (PF 0.70) | −9R (PF 0.94) |
| USDJPY | −373R (PF 0.69) | −60R (PF 0.91) | −3R (PF 0.98) |

A "pullback to EMA21" entry variant gave the same picture (gold H4 +25R / 74 trades; everything on M15/H1 negative, but that table includes the SHORT side, see the correction below).

## What survived scrutiny, and what didn't
- **Gold H4 held up under a 12-setting grid** (4 ribbon sets × stops 1.5/2/3 ATR): all 12 positive, +34R to +89R, PF 1.25–1.63. First half of history +18.5R (PF 1.26), second half +54.6R (PF 1.84). Roughly 36 trades a year.
- **It is the BUY side only.** Longs +54R to +104R in every setting; **shorts lose in all 12** (−6R to −40R). Gold rose from ~1,500 to ~4,100 over this window, so this reads as "ride gold's bull trend", not a symmetrical trend system.
- **Silver (also trended up) does not confirm it:** XAGUSD H4 is negative or flat in 11 of 12 settings (best +8.5R, PF 1.07). So "ribbon works on metals" is not supported; it's gold, in this window.
- **CORRECTED 2026-10-03 (see the filter test below): the "fast timeframes lose" claim was about BOTH sides combined.** The SHORT side was the drag. Long-only (what the indicator marks) is positive on gold M15/M30/H1 and USDJPY H1, with a thinner edge per trade than gold H4; EURUSD/GBPUSD H1 are flat to negative.
- **Account-size problem:** gold H4 ATR(14) is ~$38–40, so a 2 ATR stop is ~$80 = **0.01 lot risks ~27% of a $300 account** (1.5 ATR: 20%; H1 2 ATR: 12%). That breaks the 2% size gate in [[SMC Playbook (Imperial FX)]] / [[Review Trades and Risk Management]]. Needs ≈ $4,000 to fit 2% at 0.01 lot.

## Verdict (not yet shown to Adam as a build decision)
A ribbon is a good **trend-state display and a long-only gold H4 entry filter**; it's **not** a short signal (in this 2020-2026 sample; the shorts lost because these markets didn't trend down, which is not a test of a downtrend regime). The in-sample bias (a 6-year gold bull) is unresolved: this proves the ribbon rode that trend, not that it works through a gold downtrend or range.
**Built 2026-10-03 (Adam: "Yes"): see [[TWI EMA Ribbon]].** Original proposal: Pine v6 ribbon (6 EMAs coloured by stack state), BUY marks when the stack completes, "exit longs / trend loosening" instead of SELL entries, higher-timeframe gating, an on-chart R tracker, alerts, and a loud "fast timeframe: this loses" warning below H4.

## Filter test: can RSI or Bollinger Bands improve it? (2026-10-03, Adam's question)
Scripts: `EMA Ribbon Filter Test.py` (gold H4/H1, EURUSD H4, GBPUSD H4) and `EMA Ribbon Filter Test 2 (fast TF).py` (gold M30/M15, EURUSD/GBPUSD/USDJPY H1). Read-only. **Long-only** (the indicator's actual BUY side), same rules as the base (stop 2 ATR, exit EMA8<EMA21), cost 0.5 on gold. **Eleven variants fixed before running, all reported.** The caveat is multiple testing: ~11 variants x 4+ markets, all on the whole history (the halves split below is only a partial out-of-sample check).

**Base, long-only:** gold H4 136 trades +90.8R PF 2.28 (maxDD 10.1R; halves PF 1.59 / 3.19) · gold H1 533 trades +137R PF 1.47 (halves 1.08 / 1.92) · EURUSD H4 +11R PF 1.17 · GBPUSD H4 −0.6R.

| Filter at the signal bar | Gold H4 (n, R, PF, maxDD) | Verdict |
|---|---|---|
| **RSI(14) < 70** | 130, +95.1R, **2.46**, **8.1R** | **small, consistent gain**: also better on gold H1 (PF 1.47→1.59, maxDD 44.5→33.8R), gold M15 (1.27→1.31), EURUSD H4/H1, GBPUSD H1; neutral on GBPUSD H4 and USDJPY H1 (−0.0). On gold H4 it removes only 6 trades, so by itself that's weak evidence; the H1 sample (30 removed trades that lost ~20R) is the stronger one |
| RSI < 65 | 121, +90.7R, 2.51, 10.6R | similar to 70, fewer trades |
| RSI > 55 (momentum) | 129, +81.6R, 2.13 | worse |
| RSI > 80 as an extra exit | 169, +83.7R, 1.93 | worse (cuts winners) |
| BB close below the upper band | 117, +92.5R, 2.57 | mixed (H1 first half PF 1.02) |
| BB %B < 0.8 (not stretched) | 106, +87.8R, 2.66 | best avg R but fewer trades, GBPUSD −8R, H1 weaker; **not consistent** |
| BB bands expanding / squeeze before | 93-108, +58R to +71R | worse everywhere; negative on EURUSD |
| Exit on close < BB basis (SMA20) | 268, +64.4R, 1.72 | much worse; the ribbon's EMA8/21 exit is better |

**Takeaway:** neither RSI nor Bollinger Bands is a big improvement. The ribbon's edge is the trend itself. The only filter worth keeping is the sensible "don't chase" one, **skip the BUY when RSI(14) >= 70** (a +0.02 to +0.07 R/trade nudge and lower drawdown), as an optional toggle. Both band filters and both extra exits are not worth adding.

## Long-only, other timeframes and markets (the correction)
| | n | total R | PF | halves PF |
|---|---|---|---|---|
| XAUUSD M15 (2024-26) | 822 | +127R | 1.27 | 1.24 / 1.30 |
| XAUUSD M30 (2020-26) | 940 | +126.5R | 1.23 | **0.86** / 1.64 (2020-23 lost -38R) |
| XAUUSD H1 | 533 | +137R | 1.47 | 1.08 / 1.92 |
| **USDJPY H1** | 532 | **+145R** | **1.54** | **1.55 / 1.52** (steady) |
| EURUSD H1 | 515 | −13.6R | 0.95 | 0.91 / 0.99 |
| GBPUSD H1 | 508 | −20R | 0.93 | 0.87 / 0.99 |
**Pattern:** the buy side pays where the market trended UP in this window (gold 1,500 to 4,100, USDJPY 103 to 150+), and does nothing on EURUSD/GBPUSD, which ranged or fell. That is trend-following behaving normally, not a special edge, and it says nothing about how it would do if gold or USDJPY reversed. The indicator's "FAST TF: this loses" banner and "tested edge: gold H4 only" row are therefore wrong and need rewording (see [[TWI EMA Ribbon]]).

## Order-block test: do OB areas improve the ribbon? (2026-10-03, Adam: "What about order block areas")
Script: `EMA Ribbon OB Test.py` (read-only, long-only, same costs/exit as above). Prior context: as standalone entries, OBs found no edge ([[TWI OB Hunter]], [[TWI SMC POI]], [[TWI OB FVG IDM]]); this tests them as location for the ribbon BUY. **One mechanical OB definition only** (impulse bar: bullish, range >= 1.5 ATR, body >= 60%, closes above the prior 10-bar high; OB = the last bearish candle within the 5 bars before it; zone = that candle's low..high; dies on a close below its low or after 150 bars), so this tests that definition, not "order blocks" in general. Four variants fixed in advance:

| Variant | Gold H4 (n / R / PF / maxDD; halves PF) | Gold H1 | USDJPY H1 | EURUSD H4 | GBPUSD H4 |
|---|---|---|---|---|---|
| base | 136 / +90.8 / 2.28 / 10.1; 1.59, 3.19 | 533 / +137 / 1.47 | 532 / +145 / 1.54 | 130 / +11 / 1.17 | 147 / −0.6 / 0.99 |
| **A: an active OB within 3 ATR below the signal** | **84 / +86.7 / 3.19 / 8.8; 2.36, 4.06** | 301 / +89 / 1.53 (maxDD 44.5→20.9) | 309 / +68 / **1.40** | 77 / +13 / 1.36 | 95 / −15 / **0.72** |
| B: signal bar at the OB | 52 / +22 / 1.76 (1st half 0.49) | 185 / +41 / 1.35 | 175 / +13.5 / 1.13 | 44 / +6.5 / 1.29 | 55 / −16.5 / 0.50 |
| C: OB-pullback entry, OB stop (the Imperial FX model) | 67 / +56 / 2.79 (1st half 1.28) | 234 / +40 / 1.31 | 249 / +37 / 1.25 | 57 / +3 / 1.10 | 68 / −20 / 0.47 |
| D: ribbon BUY, stop under the OB | 135 / +62 / 1.93 | 518 / +139 / 1.54 | 519 / +132 / 1.55 | 125 / +9 / 1.16 | 145 / −2.4 / 0.96 |

**Read:**
- **A is the only one that looks good, and only on gold H4 (PF 2.28 -> 3.19, better in both halves) and EURUSD H4.** It cuts trades by ~40%, keeps the total R about the same, raises R per trade, and lowers drawdown. But it is **worse on USDJPY H1 and GBPUSD H4**, and on gold H1 it halves the total R (PF only +0.06). Mixed across markets = weak evidence of a general rule; could be a gold-specific fit.
- **C, the textbook OB-pullback entry, is worse than just taking the ribbon BUY** on every set (lower total R, lower PF).
- **B hurts.** **D (stop under the OB) does not tighten the stop** (gold H4 median stop 19.9 -> 22.0, i.e. wider, over the whole history; today's ATR makes a 2 ATR gold H4 stop ~$80), so it does nothing for the $300-account sizing problem and lowers PF.
- Verdict: **don't make OB a rule.** Possible use: draw the bullish OB zones as context and tag a BUY "OB support nearby" (A) as information, not a gate.

## Pullback-entry test: buy when price dips back into the ribbon (2026-10-03, Adam: "What about entry when price pulls back into ribbon")
Scripts: `EMA Ribbon Pullback Test.py` (entries/exits) and `EMA Ribbon Pullback Test 2 (stops).py` (tighter stop, real price points). Long-only, same costs. Pullback signal = the ribbon is stacked (8>13>21>34>55>89) and the bar dips into a ribbon line then closes back above it; edge-triggered, only while flat; entry next open. **Round 1 variants fixed in advance** (P1 low<=EMA21 & close>EMA8; P2 low<=EMA13 & close>EMA8; P3 low<=EMA34 & close>EMA21; P4 reclaim EMA8; P5 low<=EMA55 & close>EMA34; exits X1 = EMA8<EMA21 or X2 = close<EMA34; U1 = first-stack OR P1). **Round 2 (added after seeing round 1, so more exposed to data-mining):** P1/P2 with a stop at the lowest low of the last 3 bars - 0.25 ATR (skipped if it is <0.5 or >3 ATR away).

| 2 ATR stop, exit X1 (PF / total R / maxDD in R) | Gold H4 | Gold H1 | USDJPY H1 | EURUSD H4 | GBPUSD H4 |
|---|---|---|---|---|---|
| base first-stack BUY | 2.28 / +90.8 / 10.1 | 1.47 / +137 / 44.5 | 1.54 / +145 / 25.8 | 1.17 / +11 / 17.3 | 0.99 / −0.6 / 20.4 |
| **P2 (dip to EMA13, close>EMA8)** | **2.52 / +86.9 / 10.5** (halves 1.91, 3.22) | **1.73 / +163.6 / 34.9** (1.18, 2.49) | **1.67 / +147.5 / 20.1** (1.81, 1.53) | 1.10 / +5.4 / 18.4 | 0.88 / −7.2 / 13.4 |
| P1 (dip to EMA21) | 2.62 / +72.6 / **5.8** (2.17, 3.09) | 1.71 / +136 / 25.0 (1.29, 2.22) | 1.48 / +88 / 22.7 | 1.10 / +4 | 1.00 / +0.2 |
| P3 (dip to EMA34) | 2.99 / +64.7 / 4.6 | 1.91 / +127 / 19.2 | 1.50 / +66 | 1.00 / 0.0 | 0.82 / −6.3 |
| P4 reclaim / P5 deep | worse / too few trades (41) | | | | |
| U1 first-stack OR P1 | **identical to base** (a pullback signal rarely occurs while flat in an intact stack), so pullback entries REPLACE the first-stack BUY, they don't add to it. They miss trends that never dip, which is why total R/points drop. |

**The R-inflation trap (checked):** the 3-bar-low stop looks huge in R (gold H4 P2: +174R, PF 3.17, median stop 15.2 vs 19.9) but in real price points it earns LESS than base: gold H4 base +$2,253 per 1.00 oz-lot vs P2/3-bar +$1,848 (P1/3-bar +$1,030); gold H1 +$2,209 vs P2/2ATR +$2,634 vs P2/3-bar +$2,351; USDJPY H1 +4,341 pips vs P2/2ATR +4,303 vs P2/3-bar +3,949; the worst single loss on gold H4 falls from −$140 to −$70. So tighter stops cut loss size and win rate, and R rises only because R's denominator shrank. R is the right unit when sizing by risk (account large enough); points are the right unit at a fixed minimum lot, which is Adam's $300 situation.

**Verdict:** P2 with a 2 ATR stop is the cleanest improvement over the first-stack BUY: better PF on gold H4/H1 and USDJPY H1 with equal or lower drawdown and about equal net points on USDJPY/gold-H4, slightly worse on EURUSD H4 and GBPUSD H4 (markets where the ribbon doesn't pay anyway). It has an intuitive reason (buying a dip in a confirmed trend instead of the first, extended bar). **Treat it as promising, not proven:** by now ~25 variants have been run on this one history, only the halves split is out-of-sample, and the pending forward test hasn't started. The 3-bar-low stop shrinks per-trade loss (gold H4 median stop -24%) but doesn't solve the $300-account sizing: at today's ATR a 3-bar stop on gold H4 is still ~$55-60 per 0.01 lot (about 19% of $300).

## M5 pullback scalper test (2026-10-12, Adam: "Let's do pull backs scalper in trend" → "Yes", test first)
Script: `pullback_scalper_research.py` (this folder). Summary: `stg\obh\pullback_scalper_summary.csv`. All rules were **pre-registered** before any run:
- **Trend:** last closed H1 bar has close > EMA50 and EMA21 > EMA50 (mirror for down), and the M5 EMA21 is on the same side of the M5 EMA50.
- **Signal:** an M5 bar dips to the EMA21 and closes back beyond it as a trend-colored candle. Edge-triggered (6 bars).
- **Session and limits:** 03:00–12:00 NY, one trade at a time, −3R daily cap.
- **Stop:** the 3-bar extreme + 0.25 ATR, at least max(0.5 ATR, 5× spread); skipped if over 3 ATR.
- **Targets:** SWING (the last confirmed swing, 1–4R, else 1.5R) or a fixed 1.5R.
- **Exits:** resolved on M1 with the real bar spread, flat 16:50 NY.
- **Control:** a 50-run coin flip (same bars, stops and R targets, random direction).

**Result: FAILS.** 17 of 18 cells (3 markets × 2 targets × both/long/short) fail. Totals for both directions:

| Market | SWING target | 1.5R target |
|---|---|---|
| XAUUSD | −389R / 3,961 tr, PF 0.83, 1/7 yrs | −285R / 3,811 tr, PF 0.88, 1/7 yrs |
| EURUSD | −127R / 3,417 tr, PF 0.94, 2/7 yrs | −50R / 3,312 tr, PF 0.97, 4/7 yrs |
| USDJPY | −192R / 3,367 tr, PF 0.90, 0/7 yrs | −75R / 3,212 tr, PF 0.96, 2/7 yrs |

- **The only nominal pass is USDJPY 1.5R longs:** +15.8R over 1,898 trades (+0.008R/trade, PF 1.01), 5/7 years, beats the coin flip 96%. With 18 cells tested, about one false pass at 95% is expected by chance, and +0.008R doesn't survive any real-world slippage. **Not an edge.**
- **Gold longs lose to the coin flip.** SWING longs beat it 0% of the time: buying M5 dips in a gold uptrend did worse than random direction. Gold shorts beat the coin flip 72–82% but are still net negative.
- **Consistent with the 10-03 finding above:** the same pullback idea pays on gold H4/H1 and USDJPY H1, and dies on M15 and below. M5 noise plus the spread eat it.
