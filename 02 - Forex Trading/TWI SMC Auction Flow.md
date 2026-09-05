---
status: active
project: forex-trading
type: reference
---
# TWI SMC Auction Flow

MQL5 EA built from scratch 2026-09-03/04 on the **Bias → Location → Confirmation → Execution → Management** framework (see [[Bias Location Confirmation Management Framework]]). Sequential state machine, deliberately not an indicator stack — each stage asks only its own question and is reached only once the previous one is satisfied.

## Source location
- Vault master: `02 - Forex Trading/TWI SMC Auction Flow.mq5`
- Deployed (not attached) both terminals: `MQL5/Experts/Advisors/TWIAuctionFlow.mq5`
- Compiles clean 0 errors / 0 warnings

## ⚠️ MANAGER IS FROZEN (Adam, 2026-09-04)
The deadlock measurement is **closed**. No management change may be made until an explicit unfreeze, and then **for bug #4 only**. Adam holds the unfreeze prompt.

## The pattern behind the bugs (Adam, 2026-09-04 — keep this)
**Three of the four bugs are the same mistake**: a field used to describe *market state* also used to describe an *execution result*.

| # | Market state | Side effect stored in the same field |
|---|---|---|
| 1 | New CHoCH **after** entry | CHoCH that already existed |
| 2 | TP1 price **reached** | Partial order **succeeded** |
| 3 | Volume on the ticket **now** | Volume **at send** |
| 4 | `DEAL_PRICE` / the fill | Pre-send BID/ASK |

> If a boolean, price, or volume is used both to describe the market and to describe an execution result, it will eventually **lock, skip, or invent R**.

Worth checking every future EA against this directly — it caught four defects here that no amount of parameter tuning would have found.

## Bug list
| # | Defect | Status |
|---|---|---|
| 1 | Opposing-CHoCH read a **standing state** as a post-entry event — closed 25 trades from conditions that already existed at entry | **Fixed** |
| 2 | **Partial-lot deadlock** — `continue` fired even when the partial never executed (`RoundDownLot(0.01×30%)=0`), permanently bypassing BE, trail, CHoCH and TP2 | **Fixed** |
| 3 | TP2 partial **sized from `initialVolume`** but validated against current volume → false `SKIPPED_INVALID_REMAINDER` while legal size remained | **Fixed** |
| 4 | **`g_live[].entry` stores the pre-send quote, not `DEAL_PRICE`** — every R calculation (MFE/MAE/"hit +1R"/BE level/realized R) is computed off a price that isn't the fill | **Reported only** |
| — | `RoundDownLot` dual meaning (refuse-entry vs skip-partial) | Reported only |
| — | Tester `Report=` path is relative, scattering reports into the terminal root | Reported only |

### Bug #4 detail (the evidence)
Trade #11, a **SELL**: `BE_REQUEST oldSL=4391.27 → requestedSL=4395.38` — **+4.11 the wrong way**; a sell stop can only move *down* toward the fill. Verification passed because it only checked `actualSL == requestedSL`, never that the stop got *safer*. `bid=4399.49` against a stored entry near 4391 on a sell cannot both be true — the stored entry is the pre-send quote, not the fill. `MFEbeforeMgmt=1.00R` therefore fired BE off a bad reference.

Same class as #1 and #2: **market state and a side effect collapsed into one field** — the fill (state) versus the quote we hoped to get (side effect).

## Architecture fixes and what each bought

**M15 owns trade validity** (H1 = context, M15 = validity, M5 = timing only). Setups are cancelled upstream the moment a closed M15 bar breaks the protected level; M5 can never resurrect a dead premise. 47% of entries had previously been taken against an already-invalid M15 structure.

| | Buggy exit | Corrected exit | + M15 gate |
|---|---|---|---|
| Deals | 36 | 35 | 21 |
| Win rate | 27.8% | — | **47.6%** |
| Expectancy | — | strongly negative | **+0.013R** |
| R-PF | — | 0.60 | **1.03** |
| Net | −$33.68 | −$307.66 | **+$7.66** |

The −$307.66 was the *first honest* number: bug #1 had been acting as an accidental ultra-tight stop, cutting 25 trades at −0.02R to −0.11R. The flattering −0.37R average loss was a defect, not an edge.

## Deadlock damage-removal measurement (closed, 2026-09-04)
Frozen-everything-else, same window, vs the M15-gate baseline:

| Bucket | Baseline | After #2+#3 | Delta |
|---|---|---|---|
| MFE > +1R then realized ≤ −0.8R | 3 | **1** | −2 |
| MFE > +2R then realized ≤ −0.8R | 1 | **0** | −1 |
| MFE > +3R then realized ≤ −0.8R | 1 | **0** | −1 |

- Bucket C (skipped partial → no downstream manager → original SL): **0**
- TP1 reached 6 / executed 6, **6 `PARTIAL_CLAMPED` events** — the deadlock was *prevented*, not survived. Both fixes were required.
- TP2 clamp **OBSERVED** (sizes ran 0.03-0.09, larger than expected): reached 4, executed 3, zero `SKIPPED_INVALID_REMAINDER`.
- Contamination clean: entries 21→20 (explained by positions living longer under `MaxPositions=1`), risk band 0.393/0.469/0.499 unchanged, zero risk-model mismatches.
- The single remaining +1R offender is **bug #4**, not a deadlock relapse.

## Written but NOT compiled
- **CRT / VP / AMT source modules** — `CRT_Range` (prior D1/H1/session, sweep+reclaim, bias vote only), session-fixed `VP_Profile` (POC/VAH/VAL, 70% value area, HVN/LVN, ATR-scaled bins on metals, cached per EntryTF bar never per tick), `AMT_Levels` (prior session high/low/mid, prior POC, daily open). Still to wire: ANY-of location sources, confluence points, visuals.
- Three geometry defect fixes, compiled but **defaulted off** (`InpRequireEntryRR=false`, `InpMinPartialR=0`, `InpFixDegenerateTargets=false`).
- **Session clocks were carried over verbatim from [[TWI TakeProfit SMC EA]]** — this EA never had any. Flagged rather than invented.

## Known gap: external vs internal structure
Source slides distinguish **external** structure (the big swings forming the "steps", which define levels) from **internal** structure (oscillation inside a step). This EA has **one scale** — `SwingLeft/Right=3` finds both. So the protected swing may be an internal wiggle, and location levels may be drawn from internal highs rather than step edges. Intended mapping: external → protected swing / M15 validity / location / CRT edges; internal → M5 confirmation only.

## The bug #4 unfreeze spec (Adam's exact wording — send alone, nothing rides with it)
> **UNFREEZE — BUG #4 ONLY.** Fill price vs pre-send quote.
>
> **Frozen — do not edit:** bugs #1-#3, M15 validity gate, entries, score, locations, confirmations, MaxPositions, SL geometry, target prices, BE offset input, trail rule, opposing-CHoCH semantics, risk skip-if-min-lot, clamp helper, `RoundDownLot` dual meaning, tester `Report=` path, CRT/VP/AMT (still uncompiled). Fifth bug: report only.
>
> **Defect:** `Execute()` stores `g_live[li].entry` from `SymbolInfoDouble(BID/ASK)` before send. Fill is `DEAL_PRICE`. MFE, MAE, +1R, BE and realized R all use the quote. Observed SELL: SL 4391.27 → 4395.38 (wrong way); verifier only checked `actualSL == requestedSL`; bid 4399.49 vs stored entry ~4391 cannot be a +1R sell; `MFEbeforeMgmt=1.00R` fired off the bad entry.
>
> **Fix:**
> 1. After fill, `g_live[li].entry = DEAL_PRICE` (or `POSITION_PRICE_OPEN` if it matches the deal). Overwrite on `DEAL_ENTRY_IN` for our magic if the stored value is still the pre-send quote.
> 2. Risk distance = fill → actual SL, not quote → SL.
> 3. SELL BE: new SL must be `<=` current SL and move toward fill. BUY: new SL must be `>=` current SL and move toward fill.
> 4. If requested SL is worse than current SL, log `BE_REJECTED_WORSE_SL` and do not modify.
> 5. Verifier checks **improved**, not only requested == actual.
> 6. All R math uses fill + that risk distance.
>
> Logs: `FILL_SYNC ticket=… quoteEntry=… dealPrice=… sl=… riskR_price=…` and `BE_REQUEST dir=SELL fill=… oldSL=… newSL=… improved=0|1`
>
> **Proof:** same window. That SELL must not raise SL. +1R on a sell only when `(fill - bid) / risk >= 1`. Entry count and risk band stay in the same neighbourhood. No BE-offset retune. Deliver diff + that SELL before/after. Stop.

## Queue (Adam's order)
1. ~~Deadlock damage-removal measurement~~ — closed
2. Bug #4 (fill vs quote) — **needs explicit unfreeze**
3. CRT / VP / AMT location wiring
4. External vs internal structure

## Tooling note
The `mbt` MCP server disconnected mid-session. Backtests now run by invoking `terminal64.exe /config:<ini>` directly — same thing `mbt` was wrapping. See [[MBT (MT5 Backtest Toolkit)]] for the tester `.set` cache gotcha, which still applies.

## Related
- [[Bias Location Confirmation Management Framework]]
- [[TWI TakeProfit SMC EA]] — risk model reused here
- [[TWI SR Sweep Reclaim]] — the over-filtering failure this architecture avoids
- [[Active Priorities]]
