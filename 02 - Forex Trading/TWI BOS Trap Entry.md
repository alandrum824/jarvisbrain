---
status: active
project: forex-trading
type: reference
---
# TWI BOS Trap Entry

TradingView Pine v6 indicator built 2026-09-07 from video screenshots Adam shared (XAUUSD 15M/30M, an SMC trader walking through his entry model). Script id `USER;595c368420b54e4faf5e0dc87bad658a`.

**Vault master source: `02 - Forex Trading/TWI BOS Trap Entry.pine`** — written to the vault BEFORE anything touched the Pine Editor, closing the backup gap that made the 2026-09-05 overwrite incident so expensive (see [[TWI Tap & Close]]).

## The model (bullish case; bearish is mirrored)
1. **BOS** — a confirmed swing high is broken by a close. Structure is now bullish. Dashed line + "BOS" label.
2. **Order Block** — the last down candle before the impulse that caused the BOS. Drawn as the zone (full wick range by default, body-only optional).
3. **Trap / Inducement (IDM)** — the first shallow swing low printed *after* the BOS and sitting *above* the OB. This is the level early buyers pile into and get stopped out of. Dotted line + label.
4. **The sweep is mandatory** — price must trade through that IDM level before the OB counts as tradable. No sweep, no signal. This is the whole point of the model and the gate most OB indicators skip.
5. **Entry** — price then taps the OB zone; optionally confirmed by a close back out of it.
6. **Breaker Block** — an OB that gets closed through is retained as a BB for the opposite side (the "OB & BB" in the source video).

Ships with R-multiple SL/TP projection boxes (default 2R), `alert()` + `alertcondition()` both directions, and per-zone cleanup so old boxes are deleted rather than accumulating — the chart-wash bug learned from [[TWI Tap & Close]]. Also carries the hidden anchor plot (`plot(close, display = display.none)`) so it overlays candles instead of dropping into its own pane — same fix, same reason.

## Status
- **v2 compiled clean, 0 errors**, live on Adam's XAUUSD 30m chart.
- Not backtested. One live signal taken so far, and it lost — see below.

## First live signal, 2026-09-07/08: LOST −$16.31
Adam took the indicator's short manually on XAUUSD 30m. Position #8112221, SELL 0.01 @ 4419.81, SL 4435.00, TP 4387.95 (he later widened TP to 4380.00). Stopped out at **4436.12 for −$16.31** — $1.12 worse than the planned −$15.19 because of slippage through the stop. Real risk per gold trade runs slightly above the on-screen number.

Jarvis had a Python/MT5 watcher running on it (break-even move armed at a 4400 touch, which never triggered — price went the other way from the moment it was armed).

**Post-mortem from the actual M30 bars:**

| Time (UTC) | Close | Tick volume |
|---|---|---|
| 21:00 | 4406.10 | 5,040 |
| 02:30 | 4423.03 | 18,750 |
| 03:00 | 4421.44 | 31,615 |
| 03:30 | 4426.13 | 22,494 |
| 04:00 | **4432.70** | 31,572 |

1. **Counter-trend entry into a live impulse.** The 02:30 bar broke +12 points on more than double the prior volume; every bar after closed higher. The short was taken at 03:43 on a shallow dip inside that rally.
2. **Volume showed buyers going through the zone, not sellers defending it.** 31,615 then 31,572 on the pushing bars. A supply zone with that much size moving through it is not rejecting.
3. **Stop sat inside the noise band** — 4435.00, barely above the 4430.15 swing high, i.e. right on the overhead liquidity. The 04:00 bar spiked to 4435.62, filled at 4436.12, then closed back at 4432.70. Taken by 62 cents.

**Honest caveat: point 3 did not cost a winner.** Price was still 4434.36 half an hour later — held, the trade was still down ~$14. The stop capped a loser, it did not rob a good trade. The setup was wrong, not just unlucky in its stop placement.

## v2 changes (2026-09-08) — both fixes came out of that loss
1. **`obMaxAge` 300 → 60.** At 300 bars a 30m zone stayed armed for 150 hours — over six days. The bearish OB that fired this short came from a much older leg (visible in Adam's own screenshot: the BOS label sits back on the Sept 4-5 selloff). The script was holding a stale directional bias.
2. **Momentum gate added** (`useMomGate`, `momLen` default 10). Higher highs *and* higher lows over the lookback = momentum is up, so shorts are blocked; mirrored for longs. v1 had no such check — its only bearish invalidation was `close > bearTop`, and the entry fires on the *tap*, which happens before that ever triggers. This gate would have blocked the losing trade.
3. **Blocked signals are plotted as small grey x marks** (`showBlocks`). Deliberate: the filter has to be judgeable on the chart rather than trusted blindly — if it turns out to be blocking good trades, that needs to be visible.

## v3 (2026-09-08) — wick-tap entry, and three rules tested and rejected
Adam described his NZDUSD entry as *"it blew past fake right into real tap with wick and took off."* That "wick" detail was testable, and it won.

A Python replica of the Pine logic (`twi_bos_trap_backtest.py`, same folder) was run over seven datasets — XAUUSD M15/M30/H1, EURUSD M15/M30, GBPUSD M30, NZDUSD M15, 20k bars each. All results are 2R fixed target, SL wins same-bar ties, **no spread or slippage modelled**.

| Variant | Trades | Total | Expectancy |
|---|---|---|---|
| v1 (no gate, close-confirm) | 442 | +8R | +0.018R |
| v2 (gate, close-confirm) | 213 | +36R | +0.169R |
| **v3 (gate, wick tap)** | **270** | **+57R** | **+0.211R** |
| gate + deepest-OB pick | 320 | −20R | −0.063R |
| gate + fake-must-break-first | 332 | −11R | −0.033R |
| gate + strict BOS (depth 2) | 225 | +33R | +0.147R |
| gate + strict BOS (depth 3) | 187 | +29R | +0.155R |

**Shipped: wick-tap entry** (`confirmClose` now defaults false). Beat close-confirmation on 5 of 7 datasets and produced 27% more trades.

**Rejected, with reasons — all three came from real observations Adam made, and all three failed the data:**
1. *"There's a trap order block before the real one — don't mark the fake."* Implemented as "pick the deepest opposing candle, not the nearest." Lost on 5 of 7. It just reaches further back and grabs unrelated zones; trade count ballooned 442 → 681 and quality collapsed.
2. *Same observation, re-implemented as sequencing:* the shallow zone must be violated before the deep one arms. Also lost on 5 of 7, and dragged the gate from +0.169R to −0.103R.
3. *"Real order block BOS/CHoCH needs to be above or below previous price."* Implemented as: the break must clear the highest of the last 2-3 swing highs, not just the most recent pivot. **Helped on 4 datasets, hurt on 3, aggregate below baseline** — the signature of noise, not edge. Flag left in the script (`strict_bos`, `bos_depth`) for a future re-test on more data.

**A real bug was found in the strict-BOS test itself** and fixed before results were read: the once-per-level dedup still compared against `swing_high` while the break used the stricter level, so a strict BOS could re-fire on the same break. Pre-fix and post-fix numbers differed materially. Worth remembering — a filter test can fail for reasons that have nothing to do with the filter.

## Honest caveats on all of the above
- **No spread or slippage in any of these numbers.** The one real trade slipped 1.12 points on a 15-point stop (7% of risk). A haircut of that size pulls +0.211R toward +0.13R.
- **Not 270 independent samples.** XAUUSD M15/M30/H1 overlap heavily — the same moves are counted repeatedly. Real independent sample is roughly half.
- **Multiple variants were tried on the same data.** Each additional test raises the chance the surviving one looks good by luck.
- **The entry model still contributes nothing on its own.** v1 was flat across 442 trades; the momentum gate is carrying the entire result. A strategy whose edge lives entirely in one filter is fragile, and that has not changed.

## Live trades so far
| Date | Instrument | Result |
|---|---|---|
| 2026-09-07 | XAUUSD short 0.01 | **−$16.31** (stopped, 1.12 slippage) |
| 2026-09-08 | NZDUSD long 0.05 | **−$1.45** (closed manually mid-range, not SL/TP) |

The NZDUSD trade also surfaced a **risk-management issue independent of the indicator**: Adam entered at 0.58803 when the signal fired near 0.58710, but kept the stop at the order-block edge. Chasing ~9 pips turned a ~3.9:1 setup into 0.92:1 — below break-even for a model that wins ~38%. Entering at the signal price matters more than any filter discussed above.

## v4-v6 (2026-09-08) and the four rejected "real vs fake order block" attempts

**Shipped:**
- **v4 — signal info panel.** Exact entry / stop / target / risk / R:R / zone printed on the chart, and the same numbers embedded in the alert text. Built because both live losses traced to hand-adjusted levels, not to the model (see below).
- **v5 — stop buffer as a fraction of zone height**, `slBufZone`, default 0.25. Measured +0.273R over 271 trades vs +0.207R with the stop flush to the zone edge. **Not monotonic** (50% buffer was *worse* than 0%), so a good part of that margin is probably noise — it ships because it's the best of four settings and has a mechanical reason, not because the edge is proven.
- **v6 — panel age + STALE flag.** v5's panel showed the last signal forever with no age. On Adam's 30m gold chart it displayed an entry of **4025 while price was 4404** — a months-old signal that read exactly like a live setup. Genuine hazard, fixed the moment it was spotted: age in bars, red "(STALE)" past `obMaxAge`, direction cell greyed.

**Also measured and shipped in v3:** wick-tap entry (`confirmClose` off) beat close-confirmation, +0.211R over 270 trades vs +0.169R over 213, better on 5 of 7 datasets.

### Four attempts at "use the real OB, not the fake one" — all rejected on data
Adam repeatedly (and correctly) observed on live charts that price blows through a shallow "fake" order block and only reacts at a deeper one. Every mechanical encoding of that idea underperformed the plain nearest-OB rule:

| Attempt | What it did | Result |
|---|---|---|
| 1. Deepest candle | Pick the deepest opposing candle in the 20-bar window, not the nearest | −0.048R (lost on 5 of 7) |
| 2. Sequential trap | Shallow zone must be violated before the deep zone arms | −0.036R (lost on 5 of 7) |
| 3. Strict BOS | Break must clear the last 2-3 swing highs, not just the latest pivot | +0.147R — below the +0.207R baseline; helped 4, hurt 3 |
| 4. Origin-anchored OB | Anchor the zone to the extreme that started the impulse leg, unlimited lookback | +0.121R at age 60 (only 91 trades), −0.013R at age 200 |

Baseline for comparison: **nearest OB, gate on, wick entry, 25% buffer = +0.273R over 271 trades.**

**The honest conclusion after four tries:** either the discretionary read isn't reducible to these rules, or the effect looks much larger in hindsight on a chart whose outcome is already known than it is in forward data. Attempt 4 is the most interesting failure — origin zones did show 50% win rates on three datasets, but on samples of 10-12 trades sitting next to a 23.5% on another. Not evidence.

All four remain behind flags in `twi_bos_trap_backtest.py` (`skip_trap`, `seq_trap`, `strict_bos`, `origin_ob`) for a future re-test on more data. **Do not re-derive them from scratch.**

### A test-harness bug worth remembering
The strict-BOS test initially looked worse than it was: the once-per-level dedup still compared against `swing_high` while the break used the stricter level, so a strict BOS could re-fire on the same break. Pre-fix and post-fix numbers differed materially. **A filter test can fail for reasons that have nothing to do with the filter.**

### The finding that mattered more than any filter
Both live losses came from moving the system's own numbers, not from the model:

| Trade | System level | What was used | Cost |
|---|---|---|---|
| XAUUSD short | Stop ~4442 (far side of OB) | Stop 4435 | −$16.31 instead of +$17 — price peaked **4440.69** then fell to 4402 |
| NZDUSD long | Entry ~0.58710 | Entered 0.58803 | 3.9:1 became 0.92:1 |

A night of filter work bought maybe +0.2R. These two hand-adjustments cost a $34 swing and a blown 3.9:1. **The panel exists so the levels are numbers on screen instead of something to estimate off a chart.**

### Attempts 5 and 6 — cluster zones and volume scoring (both rejected)
Adam noticed two more real things on live charts: his hand-drawn order blocks are ~10-point **clusters** where the script draws 3-point single candles, and those clusters **line up with volume-profile nodes**. Both were the most promising ideas of the night — the cluster idea had prior support from his own [[TWI SR Sweep Reclaim]] finding that cluster zones beat single-candle zones, and volume was the first idea that added *independent* information rather than re-slicing the same price structure.

| Variant | Trades | Total | Expectancy |
|---|---|---|---|
| **Single-candle (baseline)** | **270** | **+72R** | **+0.267R** |
| Cluster zone | 83 | +10R | +0.120R |
| Volume ≥ average density | 203 | +43R | +0.212R |
| Cluster + volume | 78 | +21R | +0.269R |

Cluster+volume matches baseline expectancy on **a third of the trades** — same answer, less precision, more variance. Its per-dataset split is the tell: every gold run strong (+1.000R on M15, +0.667R M30, +0.500R H1) but NZDUSD −0.500R and GBPUSD −0.333R. The three gold runs are one market on overlapping timeframes — effectively a single 37-trade sample, not three.

Volume caveat: gold is spot, so MT5 gives **tick volume** (price-update count), not traded contracts. An activity proxy, not real volume.

## The conclusion after six variants
Six ideas tested against the same seven datasets in one session; none beat a plain nearest-candle order block. At that count, roughly one variant *will* look good by chance, so the winners can no longer be trusted. **This stopped being research and became mining.** Further hand-crafted rules are not the path — the baseline isn't winning because it's clever, it's winning because there isn't much signal here to find.

## Forward logging (started 2026-09-08)
`twi_forward_logger.py` — the honest sample. Records every signal from its start time onward with levels frozen at fire time, then fills in only the outcome from real subsequent bars.

- Watches XAUUSD M15/M30, EURUSD M15/M30, GBPUSD M30, NZDUSD M15; polls every 5 minutes.
- Writes `twi_forward_log.csv`; cutoff state in `twi_forward_state.json`.
- **Reuses `twi_bos_trap_backtest.run()`**, so the logged strategy and the tested strategy cannot drift apart.
- Settings frozen at the measured baseline (gate on, wick entry, 25% stop buffer). **Do not tune while the sample builds** — changing the strategy mid-sample destroys it.

**A real bug was caught on its very first run.** It logged a signal from an hour *before* logging began and scored it a loss — the exact backfilling the script exists to prevent. Cause: MT5 bar timestamps are in **broker server time (UTC+3 on Risen)** while the cutoff was real UTC, so ~3 hours of completed signals slipped through. Fixed by anchoring the cutoff to the newest available bar's server time; the log and state file were deleted and restarted clean. **Remember this whenever comparing MT5 bar times to wall-clock UTC.**

Target: 20-30 closed forward signals before drawing any conclusion.

## Still to do
- Log every signal (entry, exit, R result) over 20-30 samples before judging whether there is an edge here. One losing trade proves nothing either way; so would one winner.
- No backtest exists. Trade frequency unknown.

## The "Make a copy" method worked — first clean run of it
This is the first script created since the overwrite incident, and the safe method from [[TWI Tap & Close]] held up exactly as written:
1. Opened the Pine Editor with an existing script loaded.
2. Clicked the script-name dropdown → **"Make a copy…"** → typed the new name → Enter.
3. **Verified via `pine_list_scripts` that the script count went 35 → 36 and a genuinely new id existed** before writing a single line.
4. Only then `pine_set_source` + save.
5. Re-listed afterwards and confirmed [[TWI Tap & Close]] (modified 1788660643), "TWI Scalper Pro 24 w/TP", and the `USER;a4a888de…` slot all kept their original timestamps — nothing overwritten.

**One live oddity worth knowing:** `pine_open` reported it had loaded "TWI Scalper Pro 24 w/TP" and `pine_get_source` returned that script's code, but the editor header still read **"TWI Tap & Close"** — the API-level buffer and the UI-bound slot disagreed. A save at that moment could plausibly have hit the wrong script. The copy step made it moot (the copy was taken from whatever was truly bound), but it confirms the underlying lesson: **never trust `pine_get_source` alone as proof of which slot you are about to write to — verify with `pine_list_scripts` ids.**

## Related
- [[TWI Tap & Close]] — where the Pine Editor overwrite gotcha, the safe copy method, the anchor-plot fix, and the zone-cleanup lesson all come from.
- [[TWI Sweep MSS IDM BOS OB]] — the SMC concept note covering this same sweep → MSS → inducement → BOS → OB sequence.
- [[TWI Scalp POC]] — the other finished indicator parked behind the same 2-indicator plan cap.
