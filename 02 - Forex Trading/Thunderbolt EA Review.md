---
status: active
project: forex-trading
type: reference
---
# Thunderbolt EA Review

Adam uploaded `THUNDERBOLT_EA_3.5_PRO.zip` on 2026-10-12 with no text. It was extracted to the session scratchpad only; I read the install guide and the gold presets in full. **Nothing was installed, compiled or run.**

## What's in the zip
- `THUNDERBOLT EA 3.5 PRO.ex5`: compiled only, no source. Seller: "Institutional Traders" (contact by WhatsApp/Telegram). It needs a per-account activation key.
- Normal and Aggressive presets for 11 symbols, including XAUUSD (plus an "Exness only" gold set with every distance ×10).
- An install guide built around a rented VPS, with H1 charts.

## What the gold presets do (Normal vs Aggressive)
- **`Martingale=true`, `Martingale_Multiple=2.0`: the lot DOUBLES after each loss.**
- **`Agr_Mod=true`: up to 4 open positions at once (Normal) or 9 (Aggressive).**
- SL 600 pts ($6.00 on 2-digit gold), TP 700 pts. Breakeven at +180 pts, trailing from +250 pts. Spread cap 400 pts. Trades 01:00–23:59.
- Entries come from a Stochastic(21,12,9) plus support/resistance zones it draws on the chart.

## Verdict (2026-10-12): don't run it. It's a martingale
- **Doubling math at 0.01 with a $6 stop:** six losses in a row cost 0.01 + 0.02 + 0.04 + 0.08 + 0.16 + 0.32 = 0.63 lots × $6 ≈ **$378**, roughly the whole ~$400 account. That's one position; Normal mode allows 4 at once.
- Six straight losses is routine for a 50/50 entry over a year of trades. Martingales show smooth equity until that streak arrives, then wipe the account ([[EA Scorecard]]: grids and martingales, [[Dominant EA PRO Review]], 9–21 wipeouts).
- A gold stop of $6 is about 1.5 M5 ATR right now, so noise hits it constantly, and each hit doubles the next lot.
- There's no published logic or track record in the package, and the binary can't be checked.

## SAFE gold preset (2026-10-12, Adam: "Fix thunderbolt settings make it better")
File: `Thunderbolt XAUUSD SAFE.set` (this folder; UTF-16 like the originals, so MT5's Load button reads it). It's the Normal gold preset with only the ruin mechanics removed:
| Input | Original | SAFE | Why |
|---|---|---|---|
| Martingale | true | **false** | no lot doubling after losses |
| Martingale_Multiple | 2.0 | **1.0** | belt and braces |
| Agr_Mod | true | **false** | no stacking |
| Nb_pos_Agr | 4 | **1** | one position at a time |
| InpMax_Spread | 400 pts | **60** | AAAFx gold runs ~33–52 pts; 400 allowed rollover spikes |
| MagicNumber | 7777777 | 7777001 | distinct from any copy running the original |

Unchanged: 0.01 lots, SL 600 / TP 700 pts ($6 / $7), breakeven, trailing, Stochastic entries.

**What SAFE does and doesn't fix:** the worst case per trade is now one 0.01 loss (~$6 + spread), not a doubling chain. **Whether the entries make money is unknown.** The binary is locked, the logic is unpublished, and it needs a per-account key from the seller (`USER_Key=0` in the presets), so it can't run or be tested without buying one. A $6 stop on gold is ~1.5 M5 ATRs, and the spread is 5–9% of it per trade.

## Related
[[EA Scorecard]] · [[Dominant EA PRO Review]] · [[Ai Monster EA Pro Review]] (same night, same pattern)
