---
status: active
project: forex-trading
type: reference
---
# fxalexg HS Strategy Spec

Reverse-engineering of fxalexg's head & shoulders strategy. Video: "How this Trading Strategy Made Me $70,000 in 1 Day | Head And Shoulders Pattern" (youtu.be/JA4N8nlycXY, published 2024-02-07 per the page, 12:59 long). Done 2026-09-30 at Adam's request, as the faithful **original** before any EA build or optimization. Part of [[Forex Trading]].

**Source used:** the full auto-generated transcript, every teaching minute (0:00–11:55; the rest is promotion), read in Chrome. Frames couldn't be pulled: the video wouldn't play in the automation tab. Adam's screenshots and chart examples were **not attached** to his message. So anything purely visual is marked PENDING SCREENSHOT: the "HIGH RISK TRADE" / "ACTUAL TRADE" labels, the red X, R:R 4.01, the EMA, GBPJPY 4H.

Quotes are kept to short phrases; the rules are paraphrased.

## A. Explicit rules from the video
1. **Reversal only.** H&S is a reversal pattern, never a continuation pattern.
2. **Location is required.** Take regular H&S only at a strong resistance, after a long rally. Take inverse H&S only at a strong support, after a long decline. He says patterns that appear randomly on the chart are "not effective".
3. **Shape.** Three "triangles": two small ones (the shoulders) and one big one (the head). The head is the biggest.
4. **The pattern doesn't exist until the structure flips.** (He shows this on an inverse.) Until the swing high after the head breaks above the swing high before the head, it "can simply create a new lower low"; it's not an H&S yet. The key point: that structure point has to **close** above the previous structure point.
5. **Neckline direction is the validity test.** The neckline is drawn through the two structure points.
   - Inverse H&S: the neckline must head **up**.
   - Regular H&S: the neckline must head **down**.
   - If the second structure point hasn't broken the first, the neckline still points the old way, and the pattern is **not valid** (also the "not the ideal right shoulder" example at 10:15).
6. **Right shoulder.** It forms when price starts rejecting from the "equal left shoulder zone". The shoulders must be in more or less the same area. They're never perfectly equal: give it "breathing room", and slightly higher or lower is fine.
7. **High-risk entry:**
   - Taken at the **potential** right shoulder. It's "potential" because nothing is confirmed; it can still become a fake H&S.
   - Enter once there's a **rejection candlestick** at the shoulder zone.
   - Stop goes **either just beyond the head, or a little beyond the right shoulder.**
   - He calls it high risk, high reward.
8. **The actual trade:**
   - Entry at the **retest of the neckline**, after the **break** of the neckline: "break and retest".
   - Same confirmation candles as the shoulder entry.
   - He calls it the "normal risk" trade, the one you should be taking.
9. **Confirmation candles named:** bullish engulfing and morning star. He also mentions "retest of structure", which he explains in another video.
10. **Scaling in.** If you took the high-risk entry, you can **scale in** at the neckline retest. Otherwise the retest is your first position.
11. **Right shoulder choice is flexible.** Several swings can count as the RS ("you could also include this as your right shoulder"). What matters is the triangles, the shift of structure, and the rejection at the strong level.
12. **Timeframes.** It appears on 1H, 4H, daily and weekly. The higher the timeframe, the more respected the pattern.
13. **The neckline break confirms the reversal.** He says this in the intro, at 1:27.

## B. Visually confirmed rules
**PENDING SCREENSHOT:** none could be verified from frames.
- Supported by the transcript: the red-X example is a neckline sloping the wrong way. He literally says that one "would not be a valid head and shoulders" because the neckline is still heading up (regular H&S).
- Not mentioned in the transcript at all: the EMA, the 4.01 R:R and the TP placement. Those must come from the visuals.
- He uses TradingView's built-in Head and Shoulders drawing tool to mark patterns.

## C. Aggressive shoulder strategy (ENTRY_MODE_AGGRESSIVE_SHOULDER, HIGH RISK)
Inverse (long). The regular H&S short is the exact mirror.
1. Context: price has declined into a **strong support level**. (SUBJECTIVE, see J1.)
2. **LS:** a swing low at or near that support.
3. **NP1:** the swing high after the LS.
4. **Head:** a swing low below the LS.
5. **NP2 / structure flip:** a candle **closes above NP1**. The neckline now slopes up. The pattern now exists.
6. **Pullback into the shoulder zone:** price falls back to the LS area. It must stay above the head.
7. **Entry:** a rejection candle (bullish engulfing or morning star) inside or at the LS zone. Enter at that candle's close.
   - NecklineBreakConfirmed = FALSE.
8. **Stop**, two variants, both his:
   - (a) below the head;
   - (b) a little below the right-shoulder low.
   - "A little" = SUBJECTIVE.
9. **Target:** NOT STATED IN TRANSCRIPT (see J8).
10. **Cancel:**
    - price breaks the head before the entry (the pattern becomes a lower low);
    - the RS fails to reach the zone and price breaks the neckline first (then it's route B only);
    - the setup goes stale (SUBJECTIVE).

## D. Confirmed neckline strategy (ENTRY_MODE_CONFIRMED_NECKLINE, actual trade)
1. Steps 1–6 of C (the pattern has flipped structure, and the right shoulder has formed).
2. **Neckline:** the line through NP1 and NP2, extended forward.
3. **Break:** price breaks above the neckline. Close vs wick is NOT DEFINED (see F).
4. **Retest:** price returns to the neckline from above.
5. **Entry:** a bullish engulfing or morning star at the retest. Enter at the candle close.
6. **Stop:** **NOT STATED IN TRANSCRIPT** for this route (see J9).
7. **Target:** NOT STATED (J8).
8. **Cancel:** NOT STATED. Logical candidate: a close back below the neckline, or below the RS (SUBJECTIVE).
9. **Risk class:** CONFIRMED / NORMAL RISK.

## E. Shoulder retest rules
- In the video, the "shoulder retest" **is the original right shoulder itself**: "the right shoulder retesting the left shoulder area of interest".
- **There is no separate post-pattern shoulder retest** (price leaving, then coming back to the zone later) anywhere in the transcript. **NOT IN VIDEO.** Keep `AllowPostPatternShoulderRetest = false` for the original version.
- Number of zone tests allowed: NOT STATED.

## F. Neckline confirmation rules
- **Structure flip (pattern validity):** NP2 **closes** beyond NP1. That's explicit: "closed above".
- **Neckline break (trade confirmation):** "breaks the neckline". Close vs wick is NOT DEFINED.
  - TEST PARAMETER (not an original rule): NecklineBreakMethod = CLOSE_BEYOND (default), with WICK_BEYOND as a variant.

## G. Neckline retest rules
- Price breaks the neckline, then comes back to it ("break and retest").
- Then an engulfing or morning star in the trade direction.
- How close counts as a retest: NOT DEFINED.
  - TEST PARAMETER: low ≤ neckline + 0.3 × ATR(14), and the candle closes on the trade side.

## H. Invalid setups
- The neckline slopes the wrong way: NP2 has not closed beyond NP1. Explicit.
- No strong support/resistance at the pattern. Explicit, but undefined (J1).
- Not a reversal: no prior trend into the level. Explicit, but undefined.
- The head isn't beyond both shoulders. Implied by "biggest triangle".
- The shoulders aren't in the same zone. Explicit, tolerance undefined.
- Price exceeds the head before entry: "fake head and shoulders". Explicit for the aggressive route.
- No rejection candle: no entry. Explicit.
- Anything about R:R minimum, stale setups, pattern width or retest counts: NOT IN VIDEO.

## I. High-confidence inferences
1. The **sequence is fixed**: LS → NP1 → head → NP2 flip → RS. The aggressive entry can only come **after** the structure flip, because before it "there's no head and shoulders". This is the key difference from a textbook "buy at the right shoulder".
2. NP1 and NP2 are **swing points** (the "structure points" he refers to). The neckline is marked like TradingView's H&S tool, which anchors on swing extremes. So, likely wick-to-wick. SUBJECTIVE.
3. Both entries use the same candle-confirmation family: engulfing or morning star.
4. "Both" mode = scale-in. The aggressive position is the first entry, and the retest adds to it.
5. Stop (a) "beyond the head" is the safer variant, and (b) "a little beyond the right shoulder" is the tighter, higher-R variant. Both are his.

## J. Subjective / unknown rules
Format: ORIGINAL RULE → POSSIBLE MATHEMATICAL TEST. All tests are TEST PARAMETERS, not video rules.

1. **"Strong level of support/resistance"**: SUBJECTIVE, NEEDS DEFINITION BEFORE CODING. This is the biggest gap.
   Test options:
   - (a) the head or LS sits within 0.5 ATR of a prior swing point on the same TF that was touched ≥ 2 times in the last N bars;
   - (b) a higher-TF swing level;
   - (c) toggle off to measure the pattern alone.
2. **"After a long trend / significant time"**: SUBJECTIVE.
   Test: the move into the LS is ≥ X × ATR over the prior N bars. Or price is below/above a moving average? **No: he never mentions one. Don't add it.** Use the swing-distance test only.
3. **"Shoulders more or less the same zone"**: SUBJECTIVE.
   Test: |LS − RS| ≤ 0.5 × ATR(14). Sweep 0.25–1.0.
4. **Shoulder zone construction**: NOT DEFINED (bodies or wicks, height).
   Test: the zone = from the LS extreme wick to the LS candle's body edge, padded by ±0.25 ATR.
   The RS must **touch** the zone, must not close beyond the head, and is allowed to wick past the LS.
5. **Head prominence**: NOT DEFINED. Test: head beyond both shoulders by ≥ 0.25 × ATR.
6. **Neckline anchors**: wick vs body NOT DEFINED. Test: wicks (default).
7. **Minimum neckline slope**: NOT DEFINED. Only the sign is stated, via the close above or below.
   Test: sign only; flat counts as invalid, because NP2 must close beyond NP1.
8. **Take profit**: NOT IN TRANSCRIPT.
   Tests: (a) measured move, head-to-neckline depth projected from the break; (b) fixed 4R (PENDING SCREENSHOT for the 4.01); (c) next opposing swing.
9. **Stop for the confirmed entry**: NOT IN TRANSCRIPT.
   Tests: (a) beyond the retest candle swing + 0.1 ATR; (b) beyond the RS; (c) beyond the head.
10. **Rejection candle definitions**: named, not defined.
    - Bullish engulfing = the prior candle is bearish, the current one bullish, and the current body covers the prior body.
    - Morning star = a bearish candle, then a small-body candle (body ≤ 30% of range), then a bullish candle closing above the midpoint of the first candle.
11. **Pattern timing and width**: NOT IN VIDEO. Test: each leg 3–60 bars, whole pattern ≤ 150 bars.
12. **Risk %**: he refers to another video. Separate inputs: RiskAggressive, RiskConfirmed.
13. **Break-even, partials, trailing**: NOT IN VIDEO. The only management mentioned is scaling in.

## K. Anti-repaint implementation
- **Pivots:** fractal with L left and R right bars. A pivot at bar i is confirmed at bar i+R (PivotConfirmationDelayBars = R; default 2, test 2–5). Only confirmed pivots are used for the LS, NP1 and head.
- **LS:** DetectedAt = i_LS + R.
- **NP1:** confirmed pivot high after the LS. DetectedAt = i_NP1 + R.
- **Head:** a confirmed pivot low below the LS. DetectedAt = i_H + R. Until then it's only a lower low.
- **Structure flip:** the first bar **closing** above NP1 after the head is confirmed. This is a live event at that bar's close; no delay. If the close comes before the head pivot is confirmed, the head is still accepted, as long as the head's low remains the lowest low since NP1.
- **NP2:** the highest high from the flip bar onward until price pulls back. It's fixed once the RS candle triggers, because everything before the entry bar is known. Optionally a confirmed pivot (+R delay).
- **RS / aggressive entry:** a live event. The rejection candle closes inside the zone, so EntryAllowedAt = that bar's close (next bar's open in the EA). No RS pivot confirmation is needed. That's what makes it "potential".
- **Neckline break:** a live close beyond the neckline value computed at that bar from NP1/NP2.
- **Retest entry:** a live rejection candle at the neckline after the break.
- **Hard rule:** never use a bar after the entry bar to define any point of the pattern.

## L. MT5 parameter list
- **Direction and style:**
  - EnableBearishHS, EnableInverseHS
  - EntryStyle = CONFIRMED_ONLY / AGGRESSIVE_ONLY / BOTH (both = scale-in)
- **Pivots and pattern shape:**
  - PivotLeftBars, PivotRightBars (2/2)
  - ShoulderToleranceATR (0.5, TEST)
  - ShoulderZonePadATR (0.25, TEST)
  - MinHeadSeparationATR (0.25, TEST)
  - NecklineAnchor = WICK / BODY
  - RequireStructureFlipClose = true (VIDEO RULE)
- **Location filter:**
  - RequireLevel = true / false (VIDEO RULE, test definition)
  - LevelMethod
  - LevelToleranceATR
  - LevelMinTouches
  - LevelLookbackBars
- **Prior trend:** RequirePriorTrend, PriorTrendATR, PriorTrendBars
- **Confirmation candles:** AllowEngulfing = true, AllowMorningStar = true, MorningStarMaxBodyPct = 30
- **Neckline:**
  - NecklineBreakMethod = CLOSE / WICK
  - NecklineBreakBufferATR (0)
  - NecklineRetestToleranceATR (0.3)
- **Stops:**
  - StopMethodAggressive = BEYOND_HEAD / BEYOND_RS (both VIDEO)
  - StopMethodConfirmed = RETEST_SWING / BEYOND_RS / BEYOND_HEAD (TEST)
  - StopBufferATR (0.1)
- **Target:** TargetMethod = MEASURED / FIXED_R / NEXT_SWING, FixedR (4)
- **Gates and risk:**
  - MinRR = 0 (VIDEO: none)
  - RiskAggressivePercent, RiskConfirmedPercent
  - MaxLots, MaxSpreadPoints
- **Timing:** MaxLegBars (60), MaxPatternBars (150), MaxSetupAgeBars (40)
- **Optional:** AllowPostPatternShoulderRetest = false (NOT IN VIDEO)
- **Trade tagging:** TradeEntryType comment tag AGG_SHOULDER / CONF_NECK, plus a separate magic per type.

## M. Full pseudocode (inverse = long; short is the mirror: swap highs/lows, above/below, bullish/bearish)
```
on new closed bar:
  update confirmed pivots (confirmation delay = PivotRightBars)

  # build the candidate
  if no candidate:
     LS  = latest confirmed pivot low
     NP1 = highest confirmed pivot high after LS
     H   = confirmed pivot low after NP1 with H < LS - MinHeadSeparationATR*ATR
     if RequirePriorTrend and not PriorTrendOK(LS): skip
     if RequireLevel and not AtStrongSupport(H or LS): skip
     candidate = (LS, NP1, H), state = WAIT_FLIP

  state WAIT_FLIP:
     if low < H: candidate dies (new lower low, no H&S)
     if close > NP1: state = WAIT_RS ; flipBar = now ; NP2 = high since H
  state WAIT_RS:
     NP2 = max(NP2, high) while price is still rising from the flip
     neck(bar) = line(NP1, NP2)
     if low <= H: candidate dies (fake H&S)
     inZone = low <= LS + ShoulderZonePadATR*ATR and low > H
     if inZone and abs(lowestLowSinceNP2 - LS) <= ShoulderToleranceATR*ATR
        and BullishEngulfing or MorningStar:
          RS = lowestLowSinceNP2
          if EntryStyle in (AGGRESSIVE_ONLY, BOTH):
              SL = (StopMethodAggressive==BEYOND_HEAD ? H : RS) - StopBufferATR*ATR
              TP = Target(entry, SL)
              OpenLong(tag=AGG_SHOULDER, risk=RiskAggressivePercent)
          state = WAIT_BREAK
     if close > neck(now) before an RS formed: state = WAIT_BREAK (no aggressive entry)
  state WAIT_BREAK:
     if close < RS (or < H): candidate dies
     if NecklineBroken(close or high vs neck(now) + buffer): state = WAIT_RETEST
  state WAIT_RETEST:
     if close < neck(now) - NecklineRetestToleranceATR*ATR: candidate dies   (TEST rule)
     if low <= neck(now) + NecklineRetestToleranceATR*ATR and close > neck(now)
        and BullishEngulfing or MorningStar:
          if EntryStyle in (CONFIRMED_ONLY, BOTH):
              SL = StopConfirmed() ; TP = Target()
              OpenLong(tag=CONF_NECK, risk=RiskConfirmedPercent)
          candidate done
  any state: if bars since H > MaxSetupAgeBars: candidate dies
```

## N. Questions still unanswered (need the screenshots or Adam's call)
1. TP rule and the 4.01 R:R: what's drawn on the chart?
2. Is the EMA used? Its period? It's never mentioned in the transcript, so the default is VISUAL ONLY.
3. The stop for the confirmed retest entry.
4. Neckline break: wick or close?
5. How a "strong level" is chosen: a higher-TF level, or the number of touches?
6. The pattern labeled HIGH RISK TRADE vs ACTUAL TRADE in the screenshots: does the aggressive entry sit exactly at the LS-equal level?
7. Is a minimum R:R ever stated? The transcript says none.
8. GBPJPY 4H example: entry, stop and target prices from the screenshot, to sanity-check the pseudocode.

## Status
Spec only. Nothing built from it yet. Next: Adam's screenshots verify section B, then V1 (confirmed only), V2 (aggressive only), V3 (both), each with separate stats. Optimization is V4, always compared against untouched V1–V3. Related: [[TWI HS Pullback EA]] and [[TWI HS Pullback]] were built earlier the same night from Adam's own silver trade. They are **not** this strategy (no structure-flip rule, no candle patterns, pullback-after-push entry).
