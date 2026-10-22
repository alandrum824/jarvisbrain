---
status: active
project: forex-trading
type: reference
---
# Google Drive EA Library

Inventory of the EAs, presets and indicators in Adam's Google Drive (alandrum24@gmail.com). Done 2026-10-12 ~11:15 PM PT; Adam: "Search Google Drive and look at ea I have". Search: titles containing .ex4/.ex5/.mq4/.mq5/.set/EA/robot/bot, 3 pages (~250 hits, including duplicates and a few false matches such as photos with "EA" in the filename). **Nothing was downloaded to the terminal or run** except the two small source files read below.

## What's there (by kind)
- **Locked binaries (.ex4 / .ex5), no source:** the large majority, 2021–2026. **Most are .ex4 = MetaTrader 4, which can't run on the AAAFx MT5 terminal at all.**
  - **Crack-site copies:** ForexCracked.com (~12 zips), YoForexPremium (5), eafx.monster (6), fxsignalspot (3), mt4cracked; plus many `_fix` builds.
  - **Examples:** Odin, Vision Scalper, Gold Hitter, Forex Flex, CITY ScalperX2, TPS Gold Scalper, Punisher Scalper, RoyalPrince Scalper, Sharp Shooter, ClevrFX, Quick Money, Alpha Gold/GI/Rare, XAU Miner, XAU Pro, PIP Club ProfitMax, Thanos, SecrectTOP, Omega Bot, KIKIEA, Black Diamond, Red Dragon, Smart Neural, Project Evolution Breakout Scalper, NSA Prop Firm Robot.
- **Grid / recovery by their own names:**
  - MT4 Forex Grid EA Free, FX_eTrader_Grid, AdvanceGridMax, Forex Free Zone Recovery EA.
  - Waka Waka and Quantum Emperor are widely known as grid systems, but that isn't verified here.
- **"Institutional Traders" family (same seller):**
  - DOMINANT EA V2, V3 PRO, V4.3, V5.3 PRO, V6 PRO, LATEST: a no-stop martingale grid, see [[Dominant EA PRO Review]].
  - THUNDERBOLT EA 3.5 PRO (3 copies): a martingale, see [[Thunderbolt EA Review]].
  - AI MONSTER PREMIUM V1.7.1 (.ex5): the Monster line, see [[Ai Monster EA Pro Review]].
- **Adam's own TWP material:** TWP-ROBOT 1.08 / 1.09 zips and his sets (EURUSD_AMERICA / LONDON / ASIA, EURUSD_M5_NYSE_NO_GRID, "eurusd america tweaked", XAUUSD_GOLD, "gold nyse", Daily_Profit_Target_Setup, Aggressive_Growth_Setup). Already covered in [[TWP24 EURUSD Sets]] / [[TWP ORB EA Reference]].
- **Source code (.mq4/.mq5) that can be read and tested:**
  - **EAs:** Slingshots_EA_3.02, Life Changer EA (Full .mq4, "With iVolume" .mq4, source .rar), Gorilla EA V6 Monster (.mq4, 232 KB), Forex Mega LLC V5.02 (source .rar).
  - **Indicators and tools, not EAs:** "#The Holy Grail", ApexArrow / ApexSniper, MACD Candles, Daily Range Calculator, sefc084.

## Read and tested (2026-10-12)
- **"#The Holy Grail (1).mq4": an indicator, not an EA.** It's an OBV divergence indicator (header "obv divergence.mq4", © 2017 "VOLUME WAVE"): arrows and alerts on OBV vs price divergences. It places no trades.
- **Slingshots_EA_3.02.mq4 (source "Exp_Slingshot Rev_1.00, 2022.03.04"): FAILS.**
  - **Rules:** fade the 04:15→08:30 server-time move (down → BUY, up → SELL) with three orders: 30-pip SL, TP 1R/2R/3R, no time exit. Pip-based, so it's built for FX (on gold a "30-pip" stop is $0.30).
  - **Replay** (`slingshot_research.py`, server = NY+7, M15, 2020–26, 50-seed coin flip):

| Market | Trades | R | PF | Years + | Beats coin |
|---|---|---|---|---|---|
| EURUSD | 977 | −8.0 | 0.99 | 4/7 | 52% |
| GBPUSD | 1,220 | +37.2 | 1.06 | 4/7 | 92% |
| USDJPY | 1,274 | −52.2 | 0.93 | 3/7 | 10% |

- **Life Changer EA Full.mq4: martingale grid (read in full, 1,658 lines).** It's a decompiled ex4 (header "Ex4toMq4Decompiler"); the trial-expiry and no-backtest checks are commented out.
  - **Entry:** an Aroon-style signal over 70 bars (the high/low position oscillator crossing ±50); sells also need tick volume < 30 on the current bar.
  - **Grid:** when price goes **12 pips against** the last order, it adds a new order at **lot × 1.23ⁿ**, up to **20 orders** per side. The basket TP moves to the average price + 5 pips.
  - **Stop:** the first order's 300-pip SL is copied to every add. TP 30 pips.
  - **Scope:** it scans 13 FX pairs (no gold by default) and trades up to 2 symbols at once.
  - **Exposure:** 20 orders from 0.01 is about 2.7 lots inside a 228-pip move. That margin-calls a ~$400 account long before the 300-pip stop.
- **Gorilla EA V6 Monster.mq4: three Ilan martingales in one EA (read in full, 2,717 lines).** "Ilan Hilo", "Ilan 1.5" and "Ilan 1.6" run side by side, each with its own magic.
  - **Grid:** each engine adds an order every **PipStep 30 points** against the last one, at **lot × 1.55ⁿ**, up to 10 orders. All orders share TP = average price + 100 points. Trailing starts at +13 points.
  - **First trades:** Ilan 1.5 opens a fresh first trade each H1 bar and Ilan 1.6 each M1 bar (from the last two closes; Hilo and 1.6 use an H1 RSI 30/70 filter).
  - **No stop loss.** `Stoploss_* = 40` is computed but never applied (orders are sent with SL 0), and `UseEquityStop` is off by default.
  - **`MaxLots = 0.01` only caps the base lot,** not the multiplied adds. One engine's 10 orders ≈ 1.43 lots; three engines ≈ **4.3 lots on one symbol, with no stop.** On 2-digit gold, PipStep 30 = $0.30, so all 10 adds fit inside a $3 move.
  - **The "Variable_Earnings" close-all closes EVERY position on the account** (`Close_BUY`/`Close_SELL` don't filter by symbol or magic), so it would close Adam's manual trades too. Then it emails and removes itself.
- **Forex Mega LLC V5.02 (source .rar): not read.** The Drive connector returned it inline (not saved to disk) as a compressed RAR5. It needs the file itself (drag it into chat) to extract.

## Read
- **Nothing in the Drive has shown an edge.** The two families with published logic are martingales. The two source EAs read so far are an indicator and a fade that loses.
- **Every EA with readable code in the Drive is now read:** Slingshot (fails), Life Changer and Gorilla (martingales), plus the Holy Grail indicator. Only Forex Mega (a compressed .rar) remains. Everything else is a locked binary, mostly MT4.
- The working EAs remain ours: [[TWI Gold Asia Breakout]] and [[TWI ORB Momentum]] ([[EA Scorecard]]).

## Related
[[EA Scorecard]] · [[EA Licensing and Anti-Piracy]]
