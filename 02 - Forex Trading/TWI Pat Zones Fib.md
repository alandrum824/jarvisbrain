---
status: active
project: forex-trading
type: reference
---
# TWI Pat Zones Fib

TradingView Pine v6 indicator built 2026-09-25 from Trade With Pat's method, as Adam described it: "He trades on 1 hr zones with m5 entry retracement at 70-80 fib zones." Method write-up and the live 9/25 example: [[Chart Analysis Notes]] (2026-09-25 entry).

## What it does
- **H1 zones** (zone timeframe input, default 60): supply = the H1 swing-high candle from its body top to its high; demand = the H1 swing-low candle from its low to its body bottom (3-bar pivots, non-repainting via previous closed H1 bar + lookahead). Keeps 4 per side; removed on a close through the far side.
- **M5 leg**: a swing high within 0.5 ATR of H1 supply → the leg runs to the lowest low since (buys mirror from demand). Minimum leg size 1.5 ATR.
- **Entry**: shades the **70–80% fib band** of the leg. Default trigger = **rejection close** (the candle trades to the 70% line and closes back beyond it). Alternative = a limit at the band midpoint. One entry per leg; a close beyond the leg origin kills it. Alerts on SELL/BUY.
- **Scorecard**: stop = beyond the leg origin + 0.1 ATR; target = the leg extreme (or an R multiple); SL-first conservative OHLC; 96-bar timeout.

## Deployment
- Vault source: `02 - Forex Trading/TWI Pat Zones Fib.pine`. `pine_check` 0 errors / 0 warnings.
- TradingView script **"TWI Pat Zones Fib", id `USER;74b942a30ef7444d8e22d6e1c2d50640`**, created via Make-a-copy (44 → 45 scripts), then source injected. v3 = current. OB FVG IDM (v6), ORB (v4) and SMC POI (v6) were verified untouched.
- **Bug caught on first run:** `zTime != lastSupT` is `na` (treated as false) in Pine v6 while `lastSupT` is still `na`, so no zone was ever created (0 boxes, 0 trades). Fixed with `na(lastSupT) or ...`. Worth remembering for any "new since last" check.
- **On the chart:** OANDA:XAUUSD **5m**, with Sweep Reversal Map [Herman]. **TWI OB FVG IDM was removed from the chart** to make room (2-indicator Basic cap); it's still saved.

## First read (2026-09-25, loaded 5m history, small sample)
| Trigger | Trades | Win % | Total |
|---|---|---|---|
| Rejection close (default) | 51 (14 sells / 37 buys) | 45% | −8.6R |
| Limit at band mid | 84 | 23% | −16.3R |
The zones match Adam's hand-drawn H1 order block (demand 4244.27–4255.52 / 4244.82–4253.18). As a mechanical rule the band entry is negative on this sample, the same verdict as the other SMC variants. It's useful as a map for Pat-style discretionary entries; not a proven edge.

## Related
[[TWI OB FVG IDM]] · [[Chart Analysis Notes]] · [[TWP ORB EA Reference]]
