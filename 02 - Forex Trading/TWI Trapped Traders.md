---
status: active
project: forex-trading
type: indicator
---
# TWI Trapped Traders

TradingView Pine v6 indicator built 2026-10-06 from [[Trapped Traders Strategy]] (Adam approved the spec, the design, and five final corrections). Source: `TWI Trapped Traders.pine` in this folder (747 lines; the saved TradingView copy matches it). **Status (2026-10-06): SAVED to Adam's TradingView account as a NEW script "TWI Trapped Traders" (id USER;a6cfac83c7f64f1b90e40e9fe81fdc44, via Make-a-copy; script count 50 -> 51; TWI Manas Setup verified untouched, modified stamp unchanged). Compiles clean in the editor (0 errors, 0 warnings after moving previous-bar reads to globals). NOT yet added to any chart (his gold chart is at the Basic cap: Advance SMC ICT V10.5 + TWI Manas Setup), NOT run, NOT validated. Labeled UNVALIDATED.** It identifies the sequence only; it places no trades and there is no EA.

## What it does
Core state machine (defines "trapped"): obvious level -> evidence traders reacted there -> breakout/trap -> move away -> return. Statuses: WAITING FOR TRAP, TRAP CONFIRMED, WAITING FOR RETEST, WAITING FOR CONFIRMATION, ENTRY VALID, INVALIDATED, PASS. Confirmation (rejection wick / engulfing / strong close / sweep+reclaim) only decides whether ENTRY VALID fires.
- **Levels:** a prominent swing (12/6 pivot) alone, OR a repeated level (2+ minor 5/3 swings within 0.20 ATR), OR the prior-day high/low (needs a rejection first). Zone = narrow band around the cluster (width = spread + tolerance).
- **Trap:** close beyond the zone by >= 0.10 ATR with a candle body >= 0.50 ATR, or 2 consecutive closes beyond. Zone is FROZEN at that moment. **Moved away:** >= 0.75 ATR beyond the zone. **Return:** price touches the near edge; first retest preferred, 3+ retests = PASS.
- **Structural invalidation (inputs):** 3 consecutive closes beyond the far edge (each >= 0.10 ATR), or one displacement candle (body >= 1.0 ATR) closing beyond. A wick or one tiny close does not kill it.
- **Stop / targets never invented:** stop = beyond the retest/sweep extreme or far zone edge, plus 0.10 ATR; if the risk is outside 0.15-4.0 ATR the stop shows N/A and the setup is PASS. Targets = nearest major swing / prior-day level, the breakout extreme, and the next external swing, de-duplicated; missing ones show N/A.
- **Quality filters (all switchable, never change trap detection):** 0-10 score (>= 7), first retest only, R:R >= 1.5 to TP1 (all ON by default); higher-timeframe EMA agreement and chart-TF minor BOS (OFF by default); master switch.
- **Non-repainting:** all logic runs on confirmed bars only; pivots used only after confirmation; prior-day/HTF values use the standard `[1]` + lookahead form (last completed bar); alerts once per transition at bar close (use "Any alert() function call").
- **Debug mode:** shows LEVEL FOUND -> REACTION -> TRAP -> MOVED AWAY -> RETEST -> CONFIRMATION PASSED/FAILED per candidate, with the number that blocked it (for example "break body 0.31 ATR < 0.50"), plus dotted candidate boxes and transition labels.
- **Table:** all fields from Adam's output list, a PASS statement ("NO CLEAR TRAPPED-TRADER SETUP") when nothing qualifies, and a running record (entries, TP1 first, stop first; stop assumed first if both hit in one bar).

## Honest limits
- Compile-checked only. Behavior (zone placement, trap detection, false positives) is unverified until it is run on real charts and compared with the video examples. Defaults are not optimized (Adam: no tuning until real data).
- The "CHoCH/BOS" filter is a chart-timeframe minor structure break, not a true lower-timeframe CHoCH.
- Earlier tests in this vault found mechanical zone-retest signals had no reliable edge ([[TWI Manas Setup]]); backtest before trusting it.
- TradingView Basic plan: 2 indicators per chart ([[TradingView Chart Drawing]]). This is one indicator, but Adam's desktop gold chart already holds three, so it needs a free slot or another chart.

## Second version: Adam's uploaded script (2026-10-06, "Build this")
Adam attached `trapped-traders-unvalidated.pine` (a different implementation of the same strategy, from another assistant). Built, NOT merged with the first one: both exist side by side.
- Vault files: `Trapped Traders (uploaded draft).pine` (byte-for-byte original) and `Trapped Traders (uploaded draft, compile-fixed).pine` (what was saved). Only compile fixes were made, no logic changes: (1) four untyped `x = na` declarations typed as float (v6 rejects them), (2) the stateful `ta.pivothigh/pivotlow/lowest/highest/change` calls were hoisted from inside `if barstate.isconfirmed` to global scope (Pine consistency warning), (3) short title cut from 16 to 8 characters (limit 10).
- Saved in TradingView as a NEW script "Trapped Traders (uploaded)" (id USER;7b3dced3c30e4b0180260e41366039a2; count 51 -> 52). My "TWI Trapped Traders" and "TWI Manas Setup" verified untouched (modified stamps unchanged). Compiles with 0 errors, 0 warnings. **Not added to any chart (Basic cap), not run, UNVALIDATED.**
- Differences from my version: no Debug mode and no per-candidate "why it stalled"; a single reaction is enough (min reactions = 1) so it will flag more traps; fixed-width zone (+/-0.2 ATR around the level); stop = far zone edge + 0.3 ATR with no risk-size sanity check; quality filters are score-only (no master switch, no first-retest-only or R:R gate); HTF bias uses `lookahead_off` on a live bar (can flicker intrabar; only matters if its HTF toggle is on, default off); oldest-zone cap can delete an active zone if none are finished (only past 20 zones); the table refreshes on bar close only.

### Declutter pass on the uploaded script (2026-10-06, after Adam's phone screenshot, "Yes")
Adam's phone screenshot (XAUUSD 15m) showed the dashboard table sprawling over the chart, zone-box text covering candles, and four TRAPPED LONGS ZONE boxes stacked within a few bars in a downtrend. Fixed in `Trapped Traders (uploaded draft, compile-fixed).pine` (850 lines) and re-saved over the TradingView script "Trapped Traders (uploaded)" (now v3, count still 52, compiles with 0 errors / 0 warnings; TWI Trapped Traders and TWI Manas Setup untouched):
- **Compact phone-size table** (default ON): 7 short rows (status, zone, entry/stop, TP1/2/3, R:R | quality, note); full table still available by turning it off; table position is an input.
- **Zone-box text OFF by default** (input "Write text inside zone boxes"); LONG/SHORT/RETEST labels now tiny.
- **Minimum gap between same-direction traps** (inputs: 10 bars and 1.5 ATR from an active zone): a break inside that gap is absorbed by the existing zone (the level is consumed and nothing is drawn), so a trend no longer spawns a stack of zones.
- Logic otherwise unchanged. NOT verified on a chart: Adam must remove and re-add the indicator on his phone to pick up the new version (his phone copy still showed the old title "TT [UNVALIDATED]").
