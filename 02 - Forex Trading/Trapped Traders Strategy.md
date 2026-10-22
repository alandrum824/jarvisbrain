---
status: active
project: forex-trading
type: strategy-spec
---
# Trapped Traders Strategy

Adam's price-action model (sent 2026-10-06 with screenshots from a video: "2 TRAPPED TRADERS", "TRAPPED SHORTS", "BUY TO EXIT"). **Status: SPEC + DESIGN APPROVED by Adam 2026-10-06. Built: [[TWI Trapped Traders]] (`TWI Trapped Traders.pine`, compiles clean, not yet run on a chart) (identify the sequence only; no trades, no EA). Labeled UNVALIDATED until tested.**

## Core logic
Not a plain S/R strategy. A crowd enters at an obvious level; price breaks hard against them; they are trapped. When price RETURNS to their entry area they must exit: trapped shorts BUY to close, trapped longs SELL to close. Trade WITH that forced flow. Positions are inferred from structure, never known.

## Sequence (mandatory)
Obvious level -> traders position against it -> level breaks with real force (body closes, displacement, structure shift, not a wick) -> price moves away -> price returns to the entry area (the trap zone, narrow) -> confirmation -> enter in the direction of the break.
- **Setup 1, bullish (trapped shorts):** resistance/high -> shorts enter -> breaks UP -> zone = original resistance/short-entry area -> return -> LONG.
- **Setup 2, bearish (trapped longs):** exact inverse -> SHORT.
- Not valid on their own: flipped level, a touch, a wick, one candle crossing, an FVG, a sweep (confluence only).

## Entry / stop / targets
- Confirmation (default): rejection wick, engulfing, strong close, LTF CHoCH/BOS, sweep + reclaim, can't close through the zone. Aggressive in-zone entry only if exceptional.
- Invalid: see correction 2 (structural, not one candle).
- Stop: beyond structural invalidation (zone / sweep extreme / structure that must hold), not a fixed number.
- Targets: see correction 3.

## Quality score 0-10
Plus: obvious major level, multiple prior reactions, strong displacement, body acceptance, structure agrees, moved meaningfully away first, clean first retest, strong rejection, sweep+reclaim, good RR, HTF agreement. Minus: weak level, tiny/wick-only break, immediate chop, multiple retests, zone already consumed, entry into opposing structure, poor RR, countertrend without evidence. 9-10 A+, 8 A, 7 B, 6 marginal, <=5 PASS.

## Rules
- **First clean retest preferred;** second weaker; repeated = PASS.
- HTF = bias and major levels; trading TF = the trap; LTF only for entry confirmation.
- PASS unless Jarvis can state: who is trapped, roughly where they entered, why, which way they must trade to exit, why the return helps. Output "PASS - NO CLEAR TRAPPED-TRADER SETUP" otherwise; "MORE CHART CONTEXT REQUIRED" if the screenshot lacks candles.
- Per-setup output: Direction (LONG/SHORT/PASS), Original Level, Trap Type, Trap Zone, Why trapped, Breakout confirmation, Return/retest status, Entry trigger, Entry zone, Stop, TP1-3, RR, Quality 0-10, Status (WAITING FOR TRAP / TRAP CONFIRMED / WAITING FOR RETEST / WAITING FOR CONFIRMATION / ENTRY VALID / INVALIDATED / PASS).
- Chart analysis order (12 steps): structure -> obvious highs/lows -> likely entries -> is one side trapped -> mark zone -> price moved away -> first return? -> reaction -> invalidation -> targets -> score -> LONG/SHORT/WAIT/PASS. Never invent what isn't on the chart.

## Build notes (for later, after Adam confirms)
- Target: TradingView Pine indicator. Adam's plan is TradingView Basic: 2 indicators per chart (see [[TradingView Chart Drawing]]).
- Lesson from earlier tests ([[TWI Manas Setup]], [[EMA Ribbon Trend Research]]): zone-retest signals looked good on charts but had no reliable edge when taken mechanically; plan a backtest and label the indicator UNVALIDATED until it earns otherwise.
- Related: [[TWI BOS Trap Entry]].

## Adam's sign-off corrections (2026-10-06) - these override anything above that conflicts
1. **No "have to exit exactly on the retest."** Some shorts/longs stopped out during the breakout. Wording: when price returns toward the area where trapped traders likely entered, traders who REMAIN trapped may use the return to exit closer to breakeven (shorts must buy to close, longs must sell to close). That exit flow can combine with new breakout/retest traders and help reinforce continuation. We never claim to see actual positions.
2. **Invalidation is structural, not one candle.** A small penetration or an isolated candle close through the trap zone does not automatically invalidate. Invalidation needs meaningful acceptance beyond the zone, failure to reclaim it, and/or structure confirming the continuation thesis failed.
3. **Targets:** TP1 = nearest meaningful opposing swing/liquidity; TP2 = the high/low created by the breakout/expansion; TP3 = next external level. Inverse for shorts. TP1 and the breakout high may be the same level; do not force them to differ (dedupe).
4. **Core concept vs our filters.** CORE (defines the setup): obvious level -> traders fade it -> level breaks -> traders trapped -> price returns toward their entry -> their exits support continuation. FILTERS (our quality control, kept but optional and kept separate in code): 0-10 scoring, first-retest preference, HTF bias, CHoCH/BOS confirmation, minimum R:R.
Examples confirmed correct: bullish 100 resistance -> shorts -> break up -> trapped -> return near 100 -> surviving shorts BUY TO EXIT -> continuation; bearish mirror at 50. We do NOT buy merely because resistance became support; the reason is the trapped shorts.

## Indicator design corrections (Adam, 2026-10-06, final) - binding on the Pine build
1. Core state machine = level -> evidence traders reacted there -> breakout/trap -> move away -> return. **Confirmation is an entry filter, not part of whether traders are trapped;** it only decides whether ENTRY VALID fires.
2. "Obvious level" = a prominent confirmed swing high/low OR a repeated level (not 2 touches always). Prior-day/session levels are candidates but need an actual reaction before the break.
3. **Strictly non-repainting:** confirmed bars only, pivots confirmed before use, no future bars/lookahead, trap zone frozen once the trap is confirmed and never moved, alerts once per state transition at bar close.
4. Structural invalidation operationalized as inputs (acceptance beyond the wrong side + failure to reclaim, or strong displacement against); a wick or tiny close through the zone must not kill it.
5. Never invent entry/stop/targets: show N/A if there is no legitimate structural stop or distinct next target; TP dedupe stays on. Score and HTF/CHoCH/R:R filters must be fully disable-able without changing whether a trap is detected.
- Defaults (not optimized, adjustable): ATR(14), zone tolerance ~0.20 ATR, breakout body >= 0.50 ATR, close meaningfully beyond zone, move-away >= 0.75 ATR, first clean retest preferred.
- **Debug Mode:** shows why a candidate did or did not advance: LEVEL FOUND -> REACTION CONFIRMED -> TRAP CONFIRMED -> MOVED AWAY -> FIRST RETEST -> CONFIRMATION PASSED/FAILED.
- No EA, no automated trading.
