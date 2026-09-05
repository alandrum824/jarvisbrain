---
status: built-untested
project: forex-trading
type: reference
---
# TWI Gold MTF Grid

MQL5 EA built from Adam's written spec on 2026-09-04. Multi-timeframe trend + overbought/oversold + candlestick execution engine for XAU/USD, with an optional grid module for managing floating losses.

**Status: compiled 0 errors / 0 warnings. Never run. No backtest exists yet.**

## Source location
- Vault master: `02 - Forex Trading/TWI Gold MTF Grid.mq5`
- Deployed: `MQL5/Experts/Advisors/TWIGoldMTFGrid.mq5` (RisenMOM terminal)
- Spec called for $100,000 starting capital — that is a tester/account setting, not code. Sizing is percent-of-equity so it scales to any deposit.

## Decision stack
Sequential; each stage only runs if the previous one passed.

| TF | Question | Method |
|---|---|---|
| H4 | Overall trend | EMA 21/55 + optional ADX ≥ 18 + optional fast-EMA slope |
| H1 | Confirm trend | EMA 21/55. **Must match H4 or no trade.** |
| M30 | Overbought/oversold | RSI 14 (+ optional Stochastic 14/3/3) |
| M15 | Overbought/oversold | Same. **If M30 and M15 disagree the EA pauses new entries.** |
| M5 | Execution trigger | Candlestick pattern matching the direction |

Default is *pullback* mode (`InpRequireCounterOBOS=true`): buy oversold inside an uptrend. Setting it false flips to momentum mode.

## Non-repainting
Every indicator buffer and every candle is read at shift ≥ 1 — closed bars only. Decisions run once per closed M5 bar, never intrabar. No ZigZag, no fractals, nothing with lookahead.

## Patterns (all closed-bar, individually switchable)
Engulfing, pin bar (hammer / shooting star), morning/evening star, piercing line / dark cloud cover, inside-bar breakout. Signal bar must span ≥ `InpPatMinBodyATR` × ATR so noise bars don't qualify.

## Broker adaptation
Reads and applies at every order: digits, point, tick size, volume min/max/step, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, filling mode via `SetTypeFillingBySymbol`, account leverage and margin mode. Sizing derives from `OrderCalcProfit()`; every send is pre-checked with `OrderCalcMargin()` against free margin (`InpMaxMarginPercent`, default 30%). Lots round **DOWN only** — the house rule from [[TWI TakeProfit SMC EA]]. Warns at init if grid is on but the account is NETTING (adds will merge instead of stacking).

## The gate-cost switches — why they exist
`InpGateTrendH4 / InpGateTrendH1 / InpGateOBOSAgree / InpGatePattern` each turn one gate off, and every rejection is counted by reason in the deinit funnel.

This exists because [[TWI TakeProfit SMC EA]] stacked six simultaneous AND-gates and produced almost no trades, and it took a rebuild to find out which gate was responsible. Five gates here is the same shape. **When trade count comes back low, read the funnel — do not guess and do not start tuning thresholds.**

## Grid module — read before enabling
Adds to positions that are **losing**. Defaults chosen to be non-explosive:

- `InpGridLotMultiplier = 1.0` — flat adds, **not** a martingale. Above 1.0 it is one, and init prints a warning.
- `InpMaxGridPositions = 5`
- `InpBasketMaxLossPercent = 5.0` — unconditional kill switch, checked before basket TP, closes everything.
- `InpGridNoIndividualSL = true` — with grid on, the basket stop governs; the SL distance still sizes the position.
- Spacing: fixed points, ATR multiple, or progressive (step × level).

Adam was told plainly that grid-on-losers is the risk in this design and asked for it anyway. That is his call, logged here.

## Not yet done
- No backtest of any kind. Trade count, expectancy, gate costs all unknown.
- Session filter — the spec never asked for one and none was invented (same discipline as [[TWI SMC Auction Flow]]).
- No news filter.

## Related
- [[TWI Gold ORB]] — built the same day, separate EA, unrelated strategy
- [[TWI TakeProfit SMC EA]] — the AND-stack failure this design instruments against
- [[TWI SMC Auction Flow]] — risk sizing and funnel-diagnostics pattern reused here
- [[Active Priorities]]
