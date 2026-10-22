---
status: active
project: forex-trading
type: reference
---
# Ai Monster EA Pro Review

Adam uploaded `Ai_MONSTER_EA_PRO_V4.1.5_1.zip` on 2026-10-12 with no text. Contents were extracted to the session scratchpad only (an untrusted archive). **Nothing was installed, compiled or run.**

## What's in the zip
- `AI MONSTER EA PRO V4.1.5.ex5`: **compiled and encrypted only, no source.** The logic can't be read or verified.
- `KEY.txt`: a 10-byte activation key. The value is not recorded here. A key shipped inside a shared zip usually means a passed-around or leaked copy.
- PDFs: install steps, an input guide, an "EA not working" checklist, and a disclaimer.
- Presets: Low / Medium / High risk for XAUUSD, EURUSD, GBPUSD, USDJPY, EURNZD, GBPNZD and BTCUSD.

## What the inputs reveal (from the input guide and the gold presets)
- **Entries:** pending orders around the candle before entry ("Candle A"), cancelled after 5 candles. `maxBodySize=30`. Trades both directions.
- **Gold preset:**
  - **TP 20 pips; SL = 5 × Candle A's range**, with a trailing stop.
  - Low risk = 0.01 lots, High risk = 0.05 lots.
  - Trades 01:00–23:00.
- **Account-level exits:** close everything at +100% equity or −20% equity ("low risk"), with `enableEARestart=true`, meaning it **starts again after a 20% loss**.
- **Its own instructions:**
  - Run it on **at least 5 pairs at once**, which multiplies exposure.
  - Enable **"Allow DLL imports" and "Allow WebRequest"**. A closed binary with DLL access can run any code on the PC; WebRequest can send account data out.
  - The disclaimer promises "fast and significant profits" and warns of "full loss of your investment".

## Verdict (2026-10-12): don't install it on the live terminal
- **No edge evidence.** "AI" with no stated logic, no live track record in the package, and a small-target / wide-stop structure: about a 20-pip target against a 5× candle stop. That's the high-win-rate geometry the [[EA Scorecard]] shows fails without a directional edge.
- **Security:** DLL + WebRequest on the terminal that holds account 8996721 is an unacceptable risk for an unverifiable binary.
- **Risk design:** a −20% equity stop that auto-restarts, spread across 5+ pairs, is a blow-up profile on a ~$400 account.
- **If it's ever tested:** strategy tester only, DLL imports OFF, after the [[TWI Gold Asia Breakout]] shadow trade is closed, because a tester run stops the shadow terminal.

## Related
[[EA Scorecard]] · [[Dominant EA PRO Review]] (same pattern) · [[EA Licensing and Anti-Piracy]]
