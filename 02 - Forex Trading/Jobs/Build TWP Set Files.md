---
status: active
project: forex-trading
type: guide
---
# Build TWP Set Files

**The job:** Help Adam build, edit, and reason about TWP ORB EA `.set` files — resize lot sizing, adjust risk, tune a session's strategy — without guessing at the format or the parameters.

## Boot chain (read these, in order, and you have the skill)
1. This note, end to end.
2. [[TWP24 EURUSD Sets]] — the five real set files, where they live, what's still unresolved (lot sizing, live login).
3. [[TWP ORB EA Reference]] — captured config from two other TWP accounts; the open questions on SL=0.0 and the grid setting.
4. [[Active Priorities]] — whether set-file work is currently flagged as open.

## The `.set` file format (verified 2026-08-18 by reading `twp24 EURUSD LONDON.set` directly — this is MT4/MT5's standard format, not TWP-specific)

Plain text, one parameter per block, up to 5 lines each:

```
iLots=0.10000000
iLots,F=0
iLots,1=0.01000000
iLots,2=0.00100000
iLots,3=0.10000000
```

- **`Name=Value`** (the bare line) — **this is the only line that matters for actually running the EA.** This is the live value.
- **`Name,F=`** — optimization flag (0/1): whether this parameter is included when running MT4/5's Strategy Tester *optimizer*. Irrelevant to live trading.
- **`Name,1=`** — optimizer start value.
- **`Name,2=`** — optimizer step value.
- **`Name,3=`** — optimizer stop value.

**When resizing lots or changing any setting for real: only ever touch the bare `Name=Value` line.** The `,1`/`,2`/`,3` lines are leftover optimizer-range metadata from whoever last ran an optimization pass — editing them does nothing to live behavior and isn't worth Adam's time unless he's specifically setting up a new optimization run.

`s1=`, `s1b=-  /   -   /    Trades    \   -   \  -` style lines are section-header dividers for the input dialog's UI grouping — cosmetic, not parameters.

## Parameter glossary, by section (from the real file's own section headers)

Meanings marked **(confirmed)** come from [[TWP ORB EA Reference]] or [[TWP24 EURUSD Sets]]. Everything else is **(unconfirmed)** — the name is a reasonable guess from MT4/5 EA convention, not verified. Don't state an unconfirmed one as fact to Adam; say it's a guess and offer to check TradeWithPat's docs.

**Trades**
- `iMagicNumber` — unique ID so multiple EA instances don't collide. **(confirmed)** — each of the 5 real set files got its own, per [[TWP24 EURUSD Sets]].
- `iLotsMode` — 1 = Static (fixed lot), other values presumably risk-% or balance-scaled. **(confirmed: mode 1 = static, per both reference notes)**
- `iLots` — the actual lot size when static. **(confirmed)**
- `iSLMode` / `iSL` — stop-loss mode and value. Mode 1 = ATR-based per [[TWP ORB EA Reference]]. **The SL=0.0-in-ATR-mode question is still open — don't assume it means "no stop."**
- `iTPMode` / `iTP` — take-profit mode/value, same pattern as SL. **(confirmed: ATR mode, TP=1.5)**
- `iATR_` / `iATRTimeframe` — ATR period (200) and the timeframe ATR is calculated on. **(confirmed)**

**Strategy**
- `iTradeSession` / `iCustomRange` / `DstRegion` — which session window and DST region the opening range is measured in. **(confirmed: session start ~12:00, custom)**
- `iRangeMinutes` — length of the opening-range window (75 min). **(confirmed)**
- `iTradeSessionMinutes` — how long after the range closes the EA still looks for entries (115 min). **(confirmed)**
- `iMaxHolding` — likely max time to hold a trade before force-closing. **(unconfirmed)**
- `iGMTShift` — broker GMT offset. **(unconfirmed, standard MT4/5 pattern)**
- `iEntryTF` — entry-signal timeframe (5 min). **(confirmed)**
- `iEntryMode` — entry trigger style; value 4 in the real file. [[TWP ORB EA Reference]] describes "Instant Retrace" as the entry mode used — **(confirmed the concept, not confirmed mode-4 = Instant Retrace specifically — worth checking)**.
- `iEntryRetestLevel`, `iEntryRetestMaxBody`, `iEntryBOMinBody`, `iSDMinCandles`, `iFVGAggressiveSetup` — retest/breakout/supply-demand/FVG entry-quality tuning. **(unconfirmed — all 0 in the real file, i.e. off/default)**

**Filters**
- `iMaxTradesAtOnce` / `iMaxTradesDaily` — trade-count caps. **(confirmed concept, matches "Max trades at a time"/"per session" in [[TWP ORB EA Reference]])**
- `iMaxSpread` — spread cap in points. **(confirmed)**
- `iFilterEMA` / `iFilterEMAPeriod`, `iFilterSR` / `iFilterSRPeriod` / `iFilterSRMinDist`, `iFilterFVG_SD`, `iFilterEngulf` — the optional confirmation filters, all off (0) in both the real file and [[TWP ORB EA Reference]]'s captured config. **(confirmed: this EA runs close to raw ORB logic, no filters active)**

**News**
- `iNewsLow` / `Moderate` / `High` + `Before`/`After` pairs — per-impact-level filtering windows in minutes. **(confirmed: only High is filtered, 30 min before/after, in the reference config — though the real set file here shows all off (0); the two don't necessarily match, they're different accounts)**
- `iNewsSymb` — currencies checked for news. **(confirmed: matches USD,EUR,GBP,CHF,JPY,AUD,CAD,NZD)**
- `iFilterHoliday` — skip trading on holidays. **(unconfirmed)**

**Grid**
- `iUseGrid` — grid on/off. **This is the setting at the center of the open contradiction question** — see [[TWP ORB EA Reference]]. In the real LONDON.set file it's actually **0 (off)**, matching [[TWP24 EURUSD Sets]]'s note that Adam's own build has the grid disabled.
- `iOpenFilter` — likely the "trade only if no other open trade" toggle flagged as contradictory with grid in [[TWP ORB EA Reference]]. **(unconfirmed name mapping — worth confirming before relying on it)**
- `iGridSetup` / `iVolumeSetup` — the distance/volume multiplier ladders. **(confirmed: matches the ladder documented in the reference note)**

**Various / Advanced Risk Management / Day of week / Dashboard / Graphics**
- `iMaxCapital`, `iDailyDrawdown` (4%), `iOverallDrawdown` (8%) — the account-level risk caps referenced throughout [[TWP24 EURUSD Sets]] as "the $300/day and 4%/8% drawdown caps already in the base file." **(confirmed)**
- `iTradeSunday` through `iTradeSaturday`, `iCloseFriday`, `iCloseFridayTime` — which days it trades and Friday close-out. **(unconfirmed specifics, self-explanatory names)**
- `iTSMode` / `iTT` / `iTS` — likely trailing-stop mode/trigger/step. **(unconfirmed)**
- `iPartialCloseValue` / `Amount` / `BE` — partial-close and break-even logic. **(unconfirmed, all 0/off in the real file)**
- Graphics/Dashboard params (`iColorRange`, `iBorder`, `iFont_color_*`, etc.) — purely cosmetic, never worth Adam's time discussing.

## Quality bar
- Never state an **(unconfirmed)** parameter's meaning as settled fact — say it's inferred from naming convention and offer to verify against TradeWithPat's own docs or support before it drives a real change.
- When actually editing a `.set` file for Adam: change only the bare `Name=Value` line, leave the `,F`/`,1`/`,2`/`,3` optimizer metadata alone unless he specifically asks to set up an optimization range.
- Never finalize a lot-size or risk change without Adam's explicit confirmation, per the no-live-changes rule already established in [[TWP24 EURUSD Sets]].
- If a parameter needed for the task at hand isn't in the glossary above, read the actual `.set` file directly rather than guessing — the format is simple and fast to parse by hand.

## Lessons (fold corrections in here over time)
-
