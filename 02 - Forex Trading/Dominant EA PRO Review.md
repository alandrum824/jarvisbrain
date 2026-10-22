---
status: reviewed-rejected
project: forex-trading
type: reference
---
# Dominant EA PRO Review

A commercial MT5 EA (DOMINANT EA PRO V6.3 by jeebsoft) that a vendor in the "Institutional Traders" Telegram chat posted settings for on 2024-11-06. Adam sent the settings screenshots on 2026-10-11 and asked whether it could be built and fixed. It's a locked .ex5 tied to a `USER_KEY`, so there's no source code and the entry logic is hidden. The settings only show that it uses MA 20, ATR 5, MACD 5/20/5 and Bollinger 20/2.

## What the settings do
- **Entry:** SL 0 (no stop). Aggressive mode opens 4 positions at once, and the vendor's tester shot shows 9 × 0.01 buys at the same second.
- **Adds:** a new position every 50 points against the last fill, with the lot multiplied by 1.5 each time, up to 25 adds (single add capped at 8 lots). **That's a martingale grid.**
- **Exits:** a unified basket TP of +150 points. Breakeven starts at +70 and locks +30. Everything closes at a 50% loss of money.
- On gold, 50 points is $0.50, so all 25 adds fit inside a $12.50 move. Gold makes that kind of move against you routinely.

## Test (2026-10-11), `dominant_grid_research.py`, log `C:\Users\aland\stg\obh\dominant_grid.log`
**Setup.**
- Data: AAAFx M1, 2020-01-02 to 2026-10-09. Bar spread, plus 6 pts on gold. Pessimistic within each bar.
- Account: $400 at 1:500. The live account's leverage was modelled, including add refusal on free margin and a 50% stop-out.
- Blowup: the balance drops below $50. When that happens, a new $400 is deposited and the run continues.

**Entries.** The real logic is hidden, so I used two stand-ins:
- BB/MACD: a Bollinger wick-and-close back inside the band, plus a MACD cross.
- Random bars.

**Results.**

| Market | Entry | Version | Baskets | Win | **Blowups** | First blowup | Max lots held | Net after redeposits |
|---|---|---|---|---|---|---|---|---|
| Gold | BB/MACD | Original | 3,469 | 94.5% | **21** | 2020-02-04 | 48.3 | +$52,209 |
| Gold | BB/MACD | Fixed (flat, 3 adds, −3% stop) | 3,578 | 50.5% | 10 | 2020-04-28 | 0.07 | −$4,299 |
| Gold | Random | Original | 3,538 | 99.0% | 1 | 2020-04-03 | 120.3 | +$43,027 |
| GBPUSD | BB/MACD | Original | 2,923 | 96.2% | **9** | 2020-03-24 | 32.3 | −$1,330 |
| GBPUSD | BB/MACD | Fixed | 3,083 | 61.6% | 5 | 2021-02-15 | 0.07 | −$2,205 |
| GBPUSD | Random | Original | 3,120 | 98.3% | 4 | 2021-01-25 | 120.3 | +$50,175 |

## Read
- **The 94–99% win rate is real, and so is the wipeout.** A $400 start blew up within 1–3 months on the BB entries: 21 times on gold and 9 on GBPUSD over the 7 years. Max drawdown was 97–100% in every original run.
- **The positive "net" figures are luck, not edge.** They only appear when a run happens to compound to a huge balance before the next wipeout, and the single worst baskets lost $24k–$55k. Random entries "earn" as much as the indicator entries, so the signal adds nothing. It's the gambler's ruin path.
- **It can't be fixed.** Cap the martingale (flat lots, 3 adds, −3% basket stop) and the win rate drops to 50–64%, and it loses steadily: −$4.3k gold, −$2.2k GBPUSD, 5–10 redeposits. The high win rate came only from the martingale's recovery, and the entries have no edge to fall back on.
- **Verdict: do not run it, and do not build a clone.** This matches [[TWI Gold MTF Grid]]'s warning and the prior margin-call incident on the vendor TWP ORB grid ([[TWI PAT ORB SMART]]).

## "DOMINANT EA LATEST" package (Adam uploaded the zip 2026-10-12 ~11:08 PM; read, not installed)
Contents: `DOMINANT EA FIX.ex5` (locked, dated 2024-11-21), Low/Medium/Aggressive presets for XAUUSD, XAUUSD-Exness, EURUSD and GBPUSD, and two PDFs. Same seller as [[Thunderbolt EA Review]] ("Institutional Traders", per-account key, M6 chart, "minimum deposit $50").
- **The "Low risk" gold preset is still a no-stop martingale grid:**
  - `SL_Points=0`.
  - An add every 50 pts ($0.50) against the position, lot ×1.5, up to **10** adds (single add capped at 0.5 lots).
  - Basket TP of 60 pts.
  - **Account stop at a 98% drawdown** (`Maximum_capitalretracementpercentagestoplossclosing=98`).
- **Aggressive preset:** 13 positions at once and up to **50** adds.
- **Low-risk math from 0.01:** 11 entries hold about 1.6 lots after just a $5 move against them. Every further $1 against costs about $160, so a $3 move past the last add takes a ~$400 account.
- **Verdict unchanged:** this is the structure tested above (9–21 wipeouts; the capped "fixed" version still loses). The "FIX" in the filename doesn't change the presets' grid.

## Related
- [[TWI Gold Zone Ladder]]: the hard-stop alternative tested the same day. No edge.
