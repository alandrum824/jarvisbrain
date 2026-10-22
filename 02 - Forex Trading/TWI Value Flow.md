---
status: active
project: forex-trading
type: reference
---
# TWI Value Flow

TradingView Pine v6 indicator built 2026-10-21 from a YouTube video Adam screenshotted (volume profile / value migration / OTE Fib / "best move is gone" discipline; https://youtu.be/6XK4yzgT9M0, not watched, built from 14 screenshots, 2 more didn't arrive). Adam: "Study this figure it out and build me new indicator" → spec proposed → "Yes". Companion to [[TWI Volume OB Trend]] (separate script, TWI-VOB untouched).

**Status (2026-10-21 ~6:10 PM PT): SAVED + ON THE CHART, NOT BACKTESTED.** Script `USER;60c4afd3ce104692810f0c087bda9567` ("TWI Value Flow", shorttitle TWI-VF, v3.0), created by Make-a-copy of TWI-VOB then loaded from `TWI Value Flow.pine` (this folder); script count 58 → 59, TWI-VOB still v11.0 with its modified time unchanged. Added to OANDA:XAUUSD 30m (study `GY8PdI`, next to TWI-VOB and the LuxAlgo toolkit). First read: VALUE ▼ migrating down 2d; today POC 4116.86 / VA 4107.50–4123.78; prior POC 4118.51 / VA 4113.40–4133.86; OTE 4110.41–4116.86 is a buy leg against value (marked "counter, ignored"); 0 of 2 signals, range 0.44× ADR; verdict "SELL rallies into 4113.395–4133.855". History shows the cap of 2 signals firing most days, so it is not selective yet; needs a backtest before trusting the signals.

**v4.0 (~6:45 PM PT, Adam "Yes make it easier to understand"):** from Adam's phone screenshot. (1) Bug: the verdict said "no zone above to sell into" while price sat inside the prior value area; the prior POC is now a level for the plan and the signals (sell a rejection at the prior VAL **or POC**; buys mirror with VAH or POC). (2) Panel moved to bottom right and rewritten in plain English: "▼ SELLERS IN CONTROL · 2d", Yday value, Yday fair price (POC), Price now (above/inside/below yday value), Today so far, Pullback zone, Signals used, and a two-line plan ("SELL a rally to 4113.39 / (yday value bottom, wait for rejection)"). Prices show one decimal fewer. (3) Chart labels renamed: "yday value top / fair price / value bottom", OTE box = "pullback zone", A+ = ★. (4) Today's histogram capped at 60% of the session's bars so far and made see-through. (5) Counter-trend pullback zones hidden (new input to show them). Compile 0/0, saved v4.0, chart updated by itself, 17 inputs read back on defaults. First read: sellers in control 2d, price below yday value, 1 of 2 signals used (a SELL at the yday fair price ~4119.5 under the new rule), plan "SELL a rally to 4113.39".

**v5.0 (~6:50 PM PT, Adam "Yes"):** the plan row moved from the bottom of the panel to right under the header. On the phone, TradingView's lightning button sat on the plan text. Compile 0/0, saved v5.0, read back in the new order.

## Rules (all inputs adjustable)
- **Session profile:** each OANDA daily candle's bars, volume (tick volume) spread evenly across the rows each bar covers, 40 rows. POC = busiest row; value area = grow from the POC toward the busier neighbour until 70% of volume. Today's profile drawn as a histogram at the session start (blue = value area, gold = outside), with POC (red) and VAH/VAL lines.
- **Staircase:** each finished day leaves a VAH–VAL box + POC line (last 5), tinted by its migration. The prior day's VAH/POC/VAL extend right as dashed lines labeled "prior VAH …".
- **Migration:** finished day vs the day before: POC higher AND VAL higher = ▲ up; POC lower AND VAH lower = ▼ down; else ◆ balance. Streak counted. Bias for signals = last finished day's migration.
- **OTE:** last swing leg from 15-candle pivots; zone = 0.705–0.886 retracement. Dead once price closes past the leg's start. Only a leg in the migration direction is tradable; **A+** when it overlaps the prior value area.
- **Signal:** value ▼ → a bar wicks up into the prior VAL or prior POC or the sell OTE (highest high of 3 bars) and closes back below it as a red candle → SELL. Value ▲ → mirror (prior VAH or POC) → BUY. "★" when both a value level and the OTE were hit, or the OTE was hit and it overlaps prior value. Closed bars only.
- **Best-move guard:** max 2 signals per day, 3 bars apart, none once today's range ≥ 0.9× the daily ATR(14) (panel: "DONE · best move is gone").
- **Panel (bottom right, plain English since v4):** who's in control + streak, yday value / fair price, where price is vs yday value, today so far, pullback zone, signals used, plan (SELL a rally to / BUY a dip to the nearest level, WAIT, or DONE for today).
- **Alerts:** Value Flow SELL, Value Flow BUY, Entered prior value area.

## Left out (on purpose)
- **Gamma exposure / negative gamma:** needs an options chain; spot gold has none (only GLD / COMEX options as a proxy, paid data).
- **Footprint / delta, order book:** need exchange order flow; OANDA spot gold has none.

## Related
[[TWI Volume OB Trend]], [[TradingView Chart Drawing]]
