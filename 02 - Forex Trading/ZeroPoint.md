---
status: active
project: forex-trading
type: reference
---
# ZeroPoint

Pre-existing MQL5 Expert Advisor running on RisenAdam (`MQL5\Experts\Advisors\ZeroPoint.mq5`), XAUUSD.sim M15. Volume-profile-based mean-reversion system (bins price into a profile, trades off it). Not a TWI or TWP build — separate lineage.

## Bug fixed (2026-08-29)
Real array-out-of-range crash in the volume-profile bin-filling loop: `idxLo` was clamped for the lower bound but not the upper bound, so a specific price/range combination let an invalid index reach the write loop. Fix: added `if(idxLo >= ProfileBins) idxLo = ProfileBins - 1;` right after the existing lower-bound clamp. Recompiled clean, verified with a fresh 3-month and 12-month re-run with no crash.

## Volatility filter added (2026-08-29)
The unfiltered EA was regime-dependent — lost money in high-volatility stretches. Diagnosed the real mechanism (not guessed) and added a daily-scale ATR filter: new inputs `VolFilterEnabled` (true), `VolFilterTF` (D1), `VolFilterATRPeriod` (14), `VolFilterBaselineBars` (100), `VolFilterMaxRatio` (1.5) — blocks entry when today's daily ATR exceeds 1.5x its 100-day baseline. New `volFilterAtrHandle`, wired into `TryEnter()` alongside the existing spread/session guards.

**Validated result, 12-month backtest, XAUUSD.sim M15:** 184 trades, +$242.82 net, PF 1.06, Sharpe 0.94, max DD 8.8% — vs. unfiltered -$566.13 net, PF 0.91, Sharpe -1.39, DD 17.4%. The filter turned a real loser into a real (if thin) winner.

**Honest read, forced by Adam's "$243 over a year?" pushback:** this is a thin edge, not a strong one — gold itself returned roughly +33% buy-and-hold over the same window, so $242.82 on $10,000 (≈2.4%) is weak in absolute terms even though it's a genuine statistical improvement over the unfiltered version. PF 1.06 / Sharpe 0.94 is "no longer broken," not "proven edge."

## Decision (2026-08-30): parked, not running
Discussed alongside the TWP ORB EA live deployment (see [[TWP24 EURUSD Sets]]) — Adam asked whether ZeroPoint was worth running now. Recommendation given and accepted: no. Two reasons — (1) its own validated edge (Sharpe 0.94) is weaker than what the three freshly-deployed TWP legs are showing (Sharpe 2–8 range on the same $400-scale backtests), and (2) it would be a *third* independent system touching XAUUSD on the same small real account (alongside TWIORB24 and TWP's gold leg), adding concentrated, uncoordinated gold exposure rather than real diversification. **Not attached to any chart. Let the three live TWP legs prove out first before adding anything else.**

## Related
- [[TWI Sniper ORB]] — the other custom EA on this account, same "don't stack more systems" logic applied there too
- [[TWP24 EURUSD Sets]] — tonight's live TWP deployment this decision was weighed against
- [[Active Priorities]]
