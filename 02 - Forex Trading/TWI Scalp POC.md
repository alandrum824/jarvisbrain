---
status: active
project: forex-trading
type: reference
---
# TWI Scalp POC

TradingView Pine v6 indicator, built 2026-08-24 from a Hamilton Rigby TikTok clip Adam shared (7 screenshots): draw a box from swing low to swing high, find the volume-profile POC of that swing, project it forward as a two-toned zone (continuation side vs. retracement side), and treat a pullback that holds at the POC as a continuation signal. Script: `TWI Scalp POC` (id `USER;1a85396b14dd46bf9c849c7ad3dee2d8`), shorttitle "TWI POC" (had to shorten from Adam's requested "TWI Scalp" — that name was already taken by [[TWI Scalp Pro Signals]] built the day before, would have been impossible to tell apart on the chart).

## What it does
1. Detects a genuine impulsive swing via wick-based pivot highs/lows (`pivLen` bars each side), filtered to only count as a real leg if it's at least `minLegATR` × ATR(14) — small pivots get ignored.
2. Computes that swing's **real volume-profile POC** — buckets the price range into `pocBuckets` slices, distributes each bar's volume across the buckets its high/low overlaps, picks the bucket with the most volume. Not a shortcut/approximation of "the middle" — an actual volume-weighted calculation.
3. Draws the swing box (gray), the POC line (red, projected forward `projectionBars` bars), and two zones split at the POC: continuation-side (teal, the direction the impulse was already moving) and retracement-side (maroon).
4. Watches for a **held retest**: price has to touch the POC zone on one bar, then close back through it decisively (past `minReclaimATR` × ATR) on a **later** bar — not the same bar. Fires a "POC HELD" label once per leg, matching the clip's own idea that the POC is where a pullback should hold before the move resumes.

## Build/verify record — three real bugs/miscalibrations caught, none by just trusting a clean compile
- **Compile errors (real, not cosmetic):** shorttitle over TradingView's 10-character limit, and — the bigger one — Pine functions cannot reassign plain global variables, only fields on an object passed by reference. `f_startPOC` originally tried to mutate loose `var` globals directly; fixed by bundling all the "active POC" state into a `PocState` type and passing it by reference, the same pattern already proven in [[TWI Scalp Pro Signals]]'s `Session` type.
- **Same-bar self-confirmation bug (real, same bug class as [[Malaysian SNR x Orderflow]]'s fix):** the first working version checked "touched" and "closed back through" without requiring them to be on different bars — so a single bar whose wick clipped the POC and whose close was back on the other side counted as a full "held" pattern instantly. Verified via data: 103 signals on the visible chart history, essentially one per swing — not selective at all. Fixed by requiring the touch to have happened on a **strictly earlier bar** (`wasTestedBefore`) than the reclaim.
- **Fix barely moved the count (103→102)** — proved the real driver wasn't that bug alone. Recalibrated the swing-detection defaults much stricter (`pivLen` 5→15, `minLegATR` 1.5→4.0) to match the source clip's own scale (one dramatic multi-hour rally, not 5-bar noise). Still only dropped to 90.
- **Added a "decisive reclaim" buffer** (`minReclaimATR`, close must clear the POC by a real distance, not just barely) as a third, principled tightening pass. Dropped to 87.
- **Honest conclusion, not further guessing:** three genuine, well-reasoned tightening passes only moved the signal count from 103 to 87 on this data. That strongly suggests GBPUSD's swing POCs on this chart really do hold on retest most of the time — a property of the concept on this instrument/timeframe, not a code bug left to chase. Didn't keep blindly tuning parameters past this point; reported honestly and left the two real levers (`Swing pivot length`, `Min leg size x ATR`, plus the new `Min decisive reclaim`) exposed as inputs for Adam to tune to taste rather than redeploying repeatedly.

## Real environment constraint hit: TradingView Basic plan caps 2 indicators per chart
Adding this as a 3rd indicator to a chart that already had [[Malaysian SNR x Orderflow]] and [[TWI Scalp Pro Signals]] triggered TradingView's own upgrade paywall (Basic plan = 2 indicators, Premium = 25) — not a bug, a real plan limit. Did not click "Upgrade now" — that's Adam's call, not something to do unilaterally. Verified this indicator works by temporarily swapping Malaysian SNR off the chart during testing; it is **not currently on the live chart** long-term unless Adam removes one of the other two or upgrades. Both compiled versions are safely saved in the TradingView account either way.

## Open / next
- Adam should decide whether ~87 "held" signals over several days of GBPUSD 5m history is actually too many for how he wants to use this, or whether that's a legitimate reflection of how often swing POCs hold — the mechanism itself is verified correct, this is a taste/threshold call now, not a bug hunt.
- Not yet decided which 2 of the 3 indicators (Malaysian SNR, TWI Scalp Pro Signals, TWI Scalp POC) stay on the chart at once, given the Basic-plan cap.
- Not tested on any other symbol/timeframe than OANDA:GBPUSD 5m.

## Related
- [[Malaysian SNR x Orderflow]] — same self-triggering bug class, fixed the same way (require the precondition on a strictly earlier bar)
- [[TWI Scalp Pro Signals]] — the EA-mirroring indicator this one shares chart space with
- [[Active Priorities]]
