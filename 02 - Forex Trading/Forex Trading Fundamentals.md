---
status: active
project: forex-trading
type: reference
---
# Forex Trading Fundamentals

Jarvis's core forex knowledge base — researched 2026-08-20 to build genuine trading literacy, not just relay Adam's own indicator output back to him. This is the **textbook**: general, durable concepts. [[Chart Analysis Notes]] is the **applied log** — Adam's real setups, terminology, and dated lessons. [[TWI True North]] and [[TWI Sniper ORB]] are **where these concepts got encoded into code**. Read this note for grounding, then check those for how it plays out on Adam's actual charts and accounts.

## Risk management

**The 1-2% rule.** Cap risk on any single trade to 1-2% of account equity. The reasoning is drawdown math, not superstition: at 1% risk, 20 consecutive losses still leaves 82% of capital — enough to review and recover. At 10% risk, 20 straight losses effectively ends the account. Conservative traders sit closer to 1%; a higher win-rate strategy can justify stretching toward 2%.

**Expectancy is the real scorecard, not win rate alone.** `Expectancy = (Win Rate × Avg Win) − (Loss Rate × Avg Loss)`. A system can win most of its trades and still lose money if the losses are big enough, or lose most of its trades and still print if the winners are big enough. **Breakeven win rate = 1 / (1 + R:R)** — at 1:1 you need 50% just to break even; at 1:2, only 33.3%; at 1:3, 25%. This is the exact math behind the [[Chart Analysis Notes#2026-08-20 — USDJPY 15m short off Momentum Signal Suite, closed manually for a small loss (~$4)|USDJPY 1:1-target lesson]] already banked: a 1:1 TP loses money at the 40-48% win rate measured on that indicator, and tightening the stop to structure to make it ~2.1:1 was the actual fix, not chasing a higher win rate.

**Correlation risk — the "diversified" trap.** EUR/USD and GBP/USD are strongly correlated: both are USD-counter pairs, so any dollar move shows up in both simultaneously. Open long EURUSD, long GBPUSD, long AUDUSD at 1% risk each, thinking that's diversified — the dollar spikes on a data surprise and all three stop out together. Correlation isn't fixed: it's strongest during the London-NY overlap, weakest in the Asia session, and **spikes toward +1.0 during high-impact news**, meaning a normally-spread-out book can suddenly behave like one concentrated bet exactly when volatility is highest. This is the mechanism behind Adam's own [[Chart Analysis Notes#Lessons (fold corrections in here over time)|2026-08-18 GBPUSD lesson]] (recalculate *combined* risk on every add, not each position in isolation) — and it applies directly to any multi-pair scan (the EA's forex profile allows up to 6 trades/day across pairs): several USD-pair signals firing the same direction in the same session isn't 6 independent trades, it's one leveraged dollar bet wearing six coats.

## Sessions

Three overlapping windows: **Asia (Tokyo)**, **London**, **New York** — broker-server-time dependent, always verify against the actual account, not a generic GMT chart. The **London-New York overlap (roughly 8am-12pm ET / 1pm-5pm GMT)** is the highest-volume window of the entire trading day — over 50% of daily forex volume, tightest spreads, strongest moves. Major US data (NFP, CPI, FOMC) drops at 8:30am ET, squarely inside this window, which is exactly why it's also the highest-volatility stretch. **This is a direct check against [[TWI Sniper ORB]]'s session config**: its default London window is 08:00-12:00 and New York is 13:30-17:00 broker time — worth confirming those actually land on the real overlap once Adam's broker's server-time offset is nailed down, since that overlap window is where session volume (and range-breakout reliability) is genuinely concentrated, not evenly spread across all three sessions.

## Opening Range Breakout (ORB)

Standard practice matches what's already built: define the range from the **first candle of the session** (commonly 15-30 minutes; M15 is the most popular retail choice), require a **candle close beyond the range**, not just a wick, to confirm the breakout, place the stop at the range extreme or midpoint, and target 2-3x the risk. **This confirms [[TWI Sniper ORB]]'s core mechanics are standard, proven practice, not an improvised structure** — `InpRequireCloseBeyond = true` and the 2R default target both match the textbook version exactly.

**The known failure mode is directly relevant to yesterday's diagnosis.** ORB strategies have a well-documented false-breakout problem on lower-volatility instruments and sessions — tight ranges and quiet liquidity produce breakouts that fail to follow through. This is the same dynamic already flagged for **EURUSD's 1-trade backtest**: a tight pair with a conservative spread cap and a fixed minimum-range filter will starve for signals exactly where gold (much wider natural range) won't. It's a structural property of ORB itself, not just an input-tuning problem — worth remembering before assuming every quiet backtest window is a bug.

## ICT / Smart Money Concepts (ties directly to Adam's own terminology)

These match what's already logged in [[Chart Analysis Notes#Terminology Adam uses]] and what's coded into [[TWI True North]] and [[TWI Sniper ORB]] — confirming Adam's playbook is built on real, named concepts, not invented vocabulary:

- **Order Block (OB):** the last opposing-direction candle immediately before an impulsive move that breaks structure. A fresh institutional footprint — price often returns to it once before continuing.
- **Fair Value Gap (FVG):** a three-candle gap — a literal price void between candle 1's high and candle 3's low, created by a fast move. Price often revisits these to "rebalance" before continuing. This is exactly what `ScanPOI()` hunts for in [[TWI Sniper ORB]].
- **Liquidity Sweep:** a wick that pushes past a prior high/low — clearing resting stop orders — immediately before a reversal. Same concept as the "Sell Side/Buy Side Liquidity" sweep in Adam's Sweep+MSS+Fib+OB framework, and one of [[TWI True North]]'s 10 scored confluences.
- **Breaker Block (new to the vault, not yet used anywhere):** a *failed* order block — price closed through it, took the liquidity beyond it, and now the same zone flips to work as support/resistance in the opposite direction. Genuinely different from a plain OB (which is a continuation zone) — a breaker is a reversal zone born from a failure. Not currently a confluence in either indicator. Per the standing 2026-08-19 decision that indicator complexity is capped and new ideas have to earn their place against a cut, this isn't a "just add it" — flag it to Adam as a candidate only if a real setup shows the existing 10 confluences missed something a breaker would have caught.

## Standing gotchas already banked elsewhere (pointers, not repeated here)

- Fill-status confirmation requires the real OHLCV history back to order placement, never "price vs. zone" proximity guessing — [[Chart Analysis Notes#Fill-status correction (2026-08-18, important — read before touching this trade again)]].
- No broker feed "previews" another — TradingView's OANDA feed and Adam's real AAAFx broker are two separate windows into the same market, not a lead/lag edge — [[Chart Analysis Notes#Lessons (fold corrections in here over time)]].
- BOS vs. CHoCH is **close-based, not wick-based** — [[Chart Analysis Notes#Standing setup framework #2: Market Structure (HH/HL/LH/LL + BOS/CHoCH + multi-timeframe bias)]].
