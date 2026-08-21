---
status: active
project: forex-trading
type: reference
---
# TWI True North

Custom TradingView Pine v6 indicator (script id `USER;1e200c5068ec4033b831509ff88709b5`, entity id `8s59Ed` on Adam's live chart). Built with Jarvis on 2026-08-20 as a full rebuild replacing [[Momentum Signal Suite]] — same underlying TradingView script slot, completely new architecture. Name: TWI = Adam's "Trading With Integrity" brand; True North = the market's real direction, found through structure shift, not hype.

**Mechanical note:** this replaced Momentum Signal Suite's code entirely (same script ID, title changed). It was not created as a second, separate script — `pine_new` only opens a blank editor; saving into it overwrote the existing slot. There is no way to run both side by side without rebuilding one from scratch.

## Core architecture
**Structure sets direction. Previous Day POC decides the entry.** Everything else is scored confluence, never a hard gate — the standing rule from tonight's build after hard-AND filter stacking zeroed signal output twice.

### Break of Structure / Change of Character
The market moves in swings (HH/HL uptrend, LH/LL downtrend) until structure breaks. This indicator distinguishes:
- **BOS** — a swing break in the *same* direction as the prevailing structure. Routine continuation, quiet label.
- **CHoCH** — a swing break *against* the prevailing structure. The market's first tell that character is changing. Loud gold ⚡ label, plus a native `alertcondition()` so TradingView can push it straight to Adam's phone without a manually-set price alert.

Tracked via a persistent `structureTrend` state (1/-1/0); a break's type is classified by comparing to that state *before* it updates.

### Previous Day POC — accept or reject fair value
Anchored volume-profile Point of Control for the last *completed* daily session, locked as a level carrying into the current session. The bar's **close** decides the outcome when price tests it:
- **REJECT** — pierces through, closes back on the origin side. Highest conviction (validated same night on a real USDJPY trade — this is the exact pattern that would have caught the winning long Adam spotted before the losing short the EMA-cross version took).
- **HELD** — tests, bounces without piercing, only counts if backed by fresh structure agreement.
- Closing inside a small margin of the POC = indecision, no trade.

### Confluence score — out of 10, none of them gates
ADX strength · Volume vs average · RSI above/below 50 · close beyond Fast EMA · clear of nearest S/R wall · dynamic trendline break · order block confluence · liquidity sweep (stop hunt + reversal) · imbalance (3-bar Fair Value Gap) · discount/premium (price vs. the midpoint of the current swing range). One dial: `Minimum Confluence Score to Fire` (default 6/10).

### HTF Bias — context, not scored
Deliberately excluded from the score. Stored at signal time as "With Trend" / "Counter-Trend" next to Side. This fixed a real gap found the same night: HTF Bias sitting inside the score meant it silently canceled out against other conditions instead of *telling* Adam he was taking a countertrend bounce with a ceiling, not a fresh trend trade.

### Trade state tracking
`Status`: ACTIVE (blue) / TP1 HIT / TP2 HIT (seafoam) / STOPPED (red) / --. Entry/SL/TP dim to grey once resolved. SL checked before TP so a bar sweeping both counts as a loss. Built 2026-08-20 after Adam correctly read a long-dead USDJPY BUY as if it were live — the dashboard had no concept of a trade ending until this was added.

## Dashboard (12 rows, tiny text, top-left)
Title · Status · Structure (trend + BOS/CHoCH + Disc/Prem) · POC Decision · Signal Score (X/10 + trigger, e.g. "7/10 POC REJ") · Live Score (building confluence + threshold) · Side (+ With/Counter-Trend) · Entry · SL · TP1/TP2 · HTF Context · PD POC.

## Reference material this was built from
Adam shared an ICT/SMC course clip (Currency Pros) showing a compact checklist (HTF Alignment ❌, Break of Structure ✅, Liquidity Sweep ✅, Imbalance ✅, Trade Score 75) and a POC-retracement entry ("that's a very good confluence for me — that tells me my [entry]"). The checklist showing a red X on HTF Alignment while still scoring 75 is what proved HTF should be context, not a score item — TWI True North's HTF Context row reproduces that exact observed behavior. Two Harlan Trades clips (previous-day POC as a magnet level, structure/higher-lows) fed the anchored POC concept.

## Validated same night against a real trade
USDJPY 15m: the EMA-cross version of the indicator sold a pullback in an uptrend (textbook wrong-side signal — a bearish EMA cross fires exactly when a healthy uptrend pulls back). Adam took a small manual loss, then correctly read the reversal live: "it pushed passed poc came back down swept liquidity and looks like it may push up." That exact sequence — BOS up, pullback into POC, liquidity sweep, reversal — is what TWI True North's REJECT case is built to catch, and what the removed EMA-cross trigger could not.

## Bugs found and fixed
- **2026-08-20, CHoCH direction mismatch**: Adam caught this by observation on the live gold chart — a bearish `⚡ CHoCH ▼` label followed shortly by a `BUY` signal, which looked contradictory. Verified via `data_get_pine_labels` and confirmed real. Root cause: the dashboard's `⚡` tag only checked whether the *last structural event was any CHoCH*, not whether that CHoCH's *direction* matched the trade being tagged — so a bearish CHoCH could falsely flag an unrelated bullish POC rejection as "riding a fresh bullish character change." The underlying trigger logic was correct (POC REJECT is designed to fire independent of current structure, since a rejection is often the earliest tell of a reversal, before structure officially flips) — only the dashboard label was wrong. Fixed by adding `lastCHoCHDir` (stores which direction the last CHoCH actually broke) and checking it matches the signal's own side before showing `⚡`.

## Open / next
- Fresh build, not yet watched over real market hours.
- No backtest/forward-test run.
- Liquidity Sweep and BOS/CHoCH are currently independent detectors (not required to occur in sequence) — a stricter v2 could require the sweep to immediately precede the CHoCH, matching the classic "stop hunt then reversal" pattern more tightly.
- Three price-level alerts from the Momentum Signal Suite era are still armed on FX:USDJPY (ids 5416277989 / 5416279157 / 5416281651) — unrelated to this indicator's own `alertcondition()`, should be reviewed/cleared separately.
