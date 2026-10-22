---
status: active
project: forex-trading
type: reference
---
# TWI HS Pullback (Pine indicator)

Pine v6 built 2026-09-30 (~1:55 AM). Adam asked "Make me indicator" after the MT5 headless backtest of [[TWI HS Pullback EA]] was blocked, and /permissions couldn't be changed over Remote Control. Same rules as the EA. Source: `TWI HS Pullback.pine` (this folder).

**Status:**
- Created with Make a copy… of TWI HTF Bias OB. The editor title was verified as "TWI HS Pullback" before loading the source, so the original wasn't touched.
- Loaded with `pine set --file`, then **compiled clean and saved**.
- **Not on a chart:** the desktop layout already has 4 indicators, and Add-to-chart threw the Basic-plan "2 indicators" upgrade popup (closed).
- **Scorecard not read yet.**

## What it does
- **Pattern:** H&S / inverse H&S from the last three confirmed swings. Draws LS/HEAD/RS labels and a dashed neckline.
- **Entry:** pullback after the RS push, or a neckline break + retest (input). Draws a BUY/SELL label with the R:R, plus SL and TP lines.
- **Exits:**
  - Virtual trade played forward bar by bar.
  - Breakeven after a close through the neckline.
  - Same-bar SL + TP counts as a loss.
- **Scorecard table:** trades, W/L/BE, win rate, net R, avg R, PF, max DD in R, the date it starts from, and the live state (armed/open).
- **Alerts:** pattern formed (each side), buy signal, sell signal.
- **Defaults** match the EA: pivot 5, head ≥ 0.5 ATR, shoulders ≤ 1.5 ATR apart, prior trend 40 bars / 1 ATR, push body 1.2 ATR, pullback 0.3 ATR, rejection 60%, expiry 40 bars, stop buffer 0.1 ATR, TP 1.0 × measured move, min 1.5R.

## Related
[[TWI HS Pullback EA]], [[Chart Analysis Notes]], [[TradingView Chart Drawing]] (the new-script method).

## First scorecard (Adam's phone, 2026-09-30 ~7:13 PM)
GBPJPY 1H, default inputs, pullback mode, since 2025-01-02:
- **16 trades: 3 W / 8 L / 5 BE**, win rate 19%, **net −2.5R**, avg −0.16R, **PF 0.69**, max DD 6R. **No edge** at defaults; a small sample.
- The live example on that chart was an "inverse H&S" whose neckline **sloped down**. Under [[fxalexg HS Strategy Spec]] that's invalid until the post-head structure point closes above the pre-head one. That rule is missing from this indicator by design (it came from Adam's silver trade, not the video).
