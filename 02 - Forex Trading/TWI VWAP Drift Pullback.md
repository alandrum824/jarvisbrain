---
status: active
project: forex-trading
type: reference
---
# TWI VWAP Drift Pullback

New MQL5 EA (`TWI VWAP Drift Pullback.mq5` / compiled as `TWIVwapDriftPullback.mq5`), built 2026-09-02 from a 3-rule VWAP drift-pullback strategy Adam found in a trading video (screenshots of a "DriftPullback VWAP Indicator" on @NQ).

## Source location
- Vault master copy: `02 - Forex Trading/TWI VWAP Drift Pullback.mq5`
- Deployed (not attached) to RisenAdam: `MQL5/Experts/Advisors/TWIVwapDriftPullback.mq5`
- Compiled via `MetaEditor64.exe` CLI: **0 errors, 0 warnings**, first pass
- Not compiled on RisenMOM — not needed until a backtest is run there (MBT's MT5 connection is currently auth-broken, see [[MBT (MT5 Backtest Toolkit)]] and today's daily note)

## Logic (exactly the 3 rules + 1 trigger from Adam's screenshots)
Evaluated on a configurable `TradeTF` (default M5), using a session-anchored VWAP computed on-chart (no external indicator needed — cumulative typical-price×volume, reset at the start of each new day, with a real backfill on `OnInit`/day-rollover so VWAP is correct immediately instead of starting cold mid-session).

**Bias (regime filter), re-evaluated every new bar:**
- Long bias: close > VWAP, VWAP now > VWAP `Lookback15Min` minutes ago, price up ≥ `PctThreshold1Hour`% over `Lookback1Hour` minutes.
- Short bias: mirror — close < VWAP, VWAP falling over the same window, price down ≥ the same threshold.
- Minute-based lookbacks auto-convert to bar counts off `TradeTF` (e.g. 15 min = 3 bars on M5), so changing `TradeTF` doesn't require re-tuning the lookback inputs.

**Trigger (fires once per bias episode, resets when bias changes):**
- Long bias → first red (close < open) candle = BUY.
- Short bias → first green (close > open) candle = SELL.

**Stop / target:** SL = the trigger candle's wick (low for buys, high for sells) plus an ATR buffer (`SLBufferATRmult`, default 0.10× ATR). TP = `RR_Multiplier` × the SL distance — **1.5R, per Adam's explicit answer** (his "1.5" / "R:R" replies this session).

**Lot sizing / caps:** same `LOT_FIXED`/`LOT_DYNAMIC` (%-risk) pattern as [[TWI OB Hunter]] and [[TWI Scalp Pro]]. `MaxConcurrentTrades` (default 1) blocks stacking.

## Deliberately left out (scope discipline)
No session/day-of-week filter, no zone drawing, no display options — Adam's own words were "this is all I want," so the build stayed to exactly the 3 rules + trigger + the SL/TP he confirmed, nothing extra bolted on.

## Status (2026-09-02)
Compiled clean, deployed to RisenAdam's Experts folder. Not attached to any live chart.

### Real first backtest (2026-09-02)
`mbt`'s `ping`/`get_config` (targets RisenAdam, the live terminal) were still hitting `MT5 initialize failed: (-6, 'Terminal: Authorization failed')` — unresolved, unrelated to the tester path. `run_strategy_tester` targets RisenMOM separately and worked once two real blockers were cleared:
- A first attempt hijacked into an already-running orphaned RisenMOM instance (2.2s, no report) — force-killed that `terminal64.exe` (PID confirmed via `ExecutablePath`, RisenAdam's live PID left untouched) and retried.
- A second attempt (48s, ran real but no report) used plain `EURUSD` — this broker (OANDA-Demo-1, same as every other RisenMOM test tonight) needs the `.sim` suffix, confirmed from that run's own Tester log showing prior sessions traded `EURUSD.sim`. Compiled the EA onto RisenMOM (0 errors/0 warnings) and retried with the correct symbol.

**Real result — EURUSD.sim, M5, every_tick, full available history, $400 deposit:** net **-$56.79**, profit factor **0.66**, expected payoff **-$0.06/trade**, Sharpe **-5.0**, recovery factor -0.99, **983 total trades**, max drawdown $57.27 balance / $57.34 equity (~14.3% of deposit). A real net loser on untuned defaults — high trade count (983 over the available history) means the bias/trigger logic fires often, but the edge itself isn't there yet at these default inputs (`Lookback15Min=15`, `Lookback1Hour=60`, `PctThreshold1Hour=0.10`, `SLBufferATRmult=0.10`, `RR_Multiplier=1.5`).

**Not a candidate for live deployment as-is** — same bar applied to every other EA in this vault before going live (see [[TWI OB Hunter]], [[ZeroPoint]]).

### "Tap & close" trigger fix (2026-09-02) — real improvement on EURUSD, does NOT hold on XAUUSD
Adam shared a second TradeWithPat video ("The EASIEST Trade Entry Model — Tap & Close") whose rule directly tightened the vague part of the original trigger: a pullback candle isn't enough on its own — it must **wick into the VWAP zone AND close back beyond it** (real reject/reclaim, not just any opposite-color candle near VWAP). Added `tappedZoneLong`/`tappedZoneShort` checks (`lowC <= vwapNow && closeC > vwapNow` for longs, mirrored for shorts) gating the existing red/green trigger. Recompiled clean on both terminals (0/0).

**EURUSD.sim retest, same window:** trades collapsed 983 → **42**, net **-$56.79 → +$3.61**, PF **0.66 → 1.35**, Sharpe **-5.0 → 15.98**, drawdown **14.3% → ~1.2%**. Confirms the overtrigger theory — cutting the false pullbacks fixed the shape completely.

**XAUUSD.sim, same fixed EA, same window:** net **-$78.91**, PF 0.91, Sharpe -5.0, 360 trades, drawdown **$181.53/$185.18 — over 45% of the $400 deposit.** The EURUSD edge does **not** transfer to gold — worse, gold's volatility makes it actively dangerous size-wise on this account, not just unprofitable.

**Honest read:** the EURUSD "tap & close" result (42 trades, PF 1.35, Sharpe 15.98) reads more like a small-sample win than a proven, transferable edge — same caution as every other EA here before going live. The XAUUSD failure is real evidence against trusting it yet, not proof the concept is dead. Real next step, not yet done: a second EURUSD window (different date range) to see if the EURUSD result itself is stable year-to-year, the same test [[TWI Sniper ORB]] failed (+$136 one window, -$33 the next). Parked for now — Adam redirected to [[TWI OB Hunter]]'s M5-entry upgrade instead.
