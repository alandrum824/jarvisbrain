---
status: active
project: forex-trading
type: reference
---
# SMC Playbook (Imperial FX)

Part of [[Forex Trading]]. Source: the "IMPERIAL FX SMC PDF FILE" (Mr. Henry / Gold Market Dominator branding, 27 pages, 24 numbered sections), sent by Adam as phone screenshots on 2026-09-29. Studied in full by Jarvis. This note restates it in our own words and turns it into a checklist. It is not a copy of the PDF.

**What the PDF is:** a clean beginner's glossary of standard ICT/SMC concepts, followed by one entry model. Every page closes with a pitch for the paid "Gold Market Dominator" group. There's nothing proprietary in it and no stats, win rates or backtests. It is the same material behind [[TWI Sweep MSS IDM BOS OB]], [[TWI SMC POI]], [[TWI Liquidity Sweep BOS]], [[TWI OB FVG IDM]] and [[Bias Location Confirmation Management Framework]]. None of those found a mechanical edge. **Its value is as a discipline checklist, not as a new signal.**

**Gaps in what Adam sent:** section 07 was not in the screenshots, and the PDF never defines FVG in what we have (07 may be it; unconfirmed). The lower parts of 13, 14 and 15 were cut off by the phone toolbar.

## The concepts, one line each
**Structure**
- **01 BOS:** a close beyond the last swing in the trend's direction, meaning the trend continues. Close-based, not wick-based (matches [[Chart Analysis Notes]]).
- **02 ChoCH:** the first close beyond the last swing *against* the trend. The first warning of a reversal, not proof of one.
- **03 Internal structure:** the small swings inside a leg. Use them for entry timing on the lower timeframe.
- **04 External structure:** the major swing highs and lows. Use them for bias on Daily/H4. Internal breaks do not change the external bias.

**Zones**
- **05 Order block:** the last opposite candle before the impulsive move that broke structure.
- **06 Breaker block:** a failed OB. Price closes through it, and the zone flips polarity.
- **08 Supply / 09 Demand:** the base a strong drop or rally left from. The same idea as an OB, drawn wider.
- **20 POI:** any zone where you expect a reaction. Stronger when several overlap (OB + FVG + supply/demand) **and** it lines up with bias. A POI without bias is just a random box.

**Liquidity**
- **10 Liquidity:** resting stops above equal highs/swing highs (buy-side) and below equal lows/swing lows (sell-side).
- **11 Stop hunt:** a wick through that level, then a close back inside. That's the sweep.
- **12 Inducement:** an obvious-looking "clean" setup or early POI placed to trap early entries before the real zone. If a setup looks too obvious, the real one is usually past it.

**Premium / discount (PD array)**
- **13–15:** take the dealing range from swing low to swing high. Above 50% is premium (look to sell), below is discount (look to buy), and the 50% line is equilibrium, which often reacts. Buys come from discount and sells from premium, never the reverse.

**Market phases (Wyckoff-style)**
- **16 Accumulation:** a range after a downtrend with repeated sweeps of the lows, then a breakout up.
- **17 Distribution:** a range after an uptrend with repeated sweeps of the highs, then a breakdown.
- **18 Reaccumulation / 19 Redistribution:** a pause inside a trend. It's a continuation, not a reversal. Don't fade it.

**Execution**
- **21 Displacement:** big bodies, small wicks, little retracement, FVGs left behind. It proves intent. **No displacement after a sweep = no trade.**
- **22 Mitigation:** price returns to the OB that launched the displacement to fill the remaining orders. This is the entry event.
- **23 Refinement:** H4 gives the POI, M15 gives the ChoCH/BOS inside it, and M5 gives the mini OB for entry. The stop goes under the refined OB, so it's tighter and the R:R improves.
- **24 Entry model:** HTF bias → sweep → displacement → return to OB/FVG → LTF ChoCH → enter.

## The pre-trade checklist (all 7 or no trade)
Taken from the "All concepts connected" page, with the risk gate from Adam's own record added at the end.

1. **Bias:** is Daily/H4 external structure HH/HL (buy) or LH/LL (sell)? If it's unclear or mixed, **no trade.** ([[TWI HTF Bias OB]] shows this.)
2. **Liquidity target:** which equal highs/lows or key swing is price drawn to? That becomes the TP.
3. **Sweep:** has a wick taken the liquidity on the *opposite* side, in line with the bias, and closed back inside?
4. **Displacement:** did a strong impulse leave the sweep and break structure?
5. **POI:** the OB/FVG that displacement left behind. It must sit in **discount for buys and premium for sells.**
6. **Refine and enter:** did price return to the POI, and did M15/M5 print a ChoCH inside it? Only then place the entry. The SL goes beyond the refined OB or the sweep wick.
7. **Target:** is the TP at the step-2 liquidity? Only take it if that's **≥ 2R**.
8. **Size gate (ours, not the PDF's):** the lot size comes from `mt5ro.py risk` at ≤2% of balance. **No adding to a loser, ever.** This step decides whether the account survives; steps 1–7 only decide whether a setup is good.

## Why step 8 is there
The 45-day journal in [[Review Trades and Risk Management]] shows the account isn't losing for lack of SMC knowledge. It's losing on size and averaging down:
- Average loss was 2.6× the average win.
- Trades of 0.30 lots or more lost −$682.
- The 9/21 EURUSD average-down lost −$434.

A perfect checklist at 25% risk per trade still blows the account.

## Grading log (gold)
Adam picked **gold** for live grading (2026-09-29). Each row: date/time, the checklist result, the call, and later the outcome.

- **2026-09-29 ~3:15 PM PT, XAUUSD (OANDA feed), price ~4178.** Bias SELL: the Daily is making LH/LL, and Monday's displacement 4275→4111 broke the 4235 low. ✅ Target: equal lows at 4110.87/4111.52 (+4113.49 Tue). ✅ Sweep: Tuesday ran the H4 highs at 4171/4175 up to 4185.39, but hasn't closed back under. ⏳ Displacement down: none yet. ❌ Location: range 4275.33→4110.87, EQ 4193.10; price is **below** EQ = discount, the wrong side for a sell. ❌ POI: H4 FVG **4198.09–4227.23** (in premium), with the origin up to ~4275 behind it. Size: a stop above the FVG (~$27) at 0.01 lot = ~$27 = **11% of $237**, which fails the 2% gate. Only an M5-refined stop of about $4–5 fits. **Call: NO TRADE now.** Wait for a rally into 4198–4227 → M15/M5 ChoCH down → sell, target ~4111. Outcome: pending.
