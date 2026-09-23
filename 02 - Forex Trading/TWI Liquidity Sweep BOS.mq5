//+------------------------------------------------------------------+
//|                                  TWI Liquidity Sweep BOS.mq5     |
//|                                                                  |
//|  Liquidity level -> sweep -> close back inside -> BOS ->         |
//|  retracement -> entry -> SL beyond sweep -> TP at liquidity      |
//|  or fixed R:R.                                                   |
//|                                                                  |
//|  1. LIQUIDITY LEVEL: confirmed fractal swing highs/lows kept in  |
//|     a persistent registry. Near-equal levels MERGE and carry a   |
//|     touch count, so equal highs/lows (where stops actually rest) |
//|     register as one strong level rather than three weak ones.    |
//|     Zone lifetime is independent of setup lifetime - the same    |
//|     fix that made TWI SR Sweep Reclaim's target selection work.  |
//|  2. SWEEP: a closed bar's WICK trades beyond the level.          |
//|     MinSweepATRmult defaults to 0.0 on purpose - SR Sweep        |
//|     Reclaim v3.00 proved a minimum-depth rule is invented and    |
//|     that 6 of 10 valid setups penetrated by exactly 0.00 ATR.    |
//|     Depth is measured and LOGGED, never used to reject.          |
//|  3. CLOSE BACK INSIDE: same bar, or within MaxReclaimBars.       |
//|     No reclaim = it was a breakout, not a raid. Setup dies.      |
//|  4. BOS: a close through the protected swing on the other side   |
//|     of the sweep. This is the confirmation the reversal is real. |
//|  5. RETRACEMENT: fib of the BOS leg (default), or the FVG or     |
//|     order block inside that leg.                                 |
//|  6. ENTRY: wick tap of the zone by default - measured at         |
//|     +0.211R vs +0.169R for close-confirmation in the TWI BOS     |
//|     Trap Entry backtests over 7 datasets.                        |
//|  7. SL beyond the sweep extreme + buffer. TP at the nearest      |
//|     opposing unswept liquidity, falling back to fixed R:R when   |
//|     there is none (blue sky) rather than refusing the trade -    |
//|     SR Sweep Reclaim v3.20 showed a hard RR gate killed 80% of   |
//|     correctly-selected targets.                                  |
//|                                                                  |
//|  Closed bars only, evaluated once per new bar. No repaint.       |
//|  No grid, no martingale, no averaging.                           |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property description "Liquidity sweep -> reclaim -> BOS -> retracement entry. SL beyond sweep, TP at opposing liquidity or fixed R:R."
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_LSB_STATE
  {
   WAIT_FOR_SWEEP,          // scanning the level registry for a raid
   WAIT_FOR_RECLAIM,        // swept, but the bar closed outside - give it a few bars
   WAIT_FOR_BOS,            // reclaimed, now the protected swing must break
   WAIT_FOR_RETRACE,        // BOS confirmed, waiting for the pullback into the zone
   WAIT_FOR_ENTRY_CONFIRM,  // zone tapped, waiting on the confirmation close
   TRADE_ACTIVE
  };

enum ENUM_RETRACE_MODE
  {
   RETRACE_FIB,             // fib level of the BOS leg
   RETRACE_FVG,             // fair value gap inside the BOS impulse
   RETRACE_OB               // last opposing candle before the BOS impulse
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_ZONE_TOUCH,        // wick tap of the zone
   ENTRY_CONFIRM_CLOSE      // tap, then a close in the trade direction
  };

enum ENUM_TARGET_MODE
  {
   TARGET_HYBRID,           // opposing liquidity if RR is acceptable, else fixed RR
   TARGET_OPPOSITE_LIQUIDITY,
   TARGET_FIXED_RR
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED,
   LOT_DYNAMIC
  };

enum ENUM_LEVEL_STATE
  {
   LEVEL_ACTIVE,
   LEVEL_SWEPT,
   LEVEL_BROKEN
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== General ==="
input long             MagicNumber           = 20260922;
input ENUM_TIMEFRAMES  StructureTF           = PERIOD_M15;  // timeframe levels and BOS are read on
input int              AtrPeriod             = 14;

input group "=== Liquidity levels ==="
input int              SwingLeftBars         = 3;           // bars either side that define a fractal pivot
input int              SwingRightBars        = 3;
input double           EqualLevelATRmult     = 0.15;        // levels within this many ATR merge into one (equal highs/lows)
input int              MinLevelTouches       = 1;           // 1 = trade single swings too; 2+ = only equal-highs/lows clusters
input double           LevelBreakATRmult     = 0.25;        // decisive BODY close beyond a level retires it (it broke, it wasn't raided)
input int              LevelMaxAgeBars       = 500;         // forget levels older than this
input int              MaxLevels             = 200;

input group "=== Sweep ==="
input double           MinSweepATRmult       = 0.0;         // minimum wick penetration. 0.0 = any penetration counts (see header)
input double           MaxSweepATRmult       = 2.0;         // deeper than this is trend continuation, not a raid. 0 = no cap
input int              MaxReclaimBars        = 3;           // bars allowed to close back inside the level

input group "=== Break of Structure ==="
input int              MaxBOSBars            = 20;          // bars allowed for the BOS after the reclaim
input double           BOSBufferATRmult      = 0.0;         // extra distance the BOS close must clear. 0 = plain close through
input double           MaxBOSDistanceATRmult = 0.0;         // skip if the protected swing is further than this from the sweep. 0 = off

input group "=== Retracement / Entry ==="
input ENUM_RETRACE_MODE RetraceMode          = RETRACE_FIB;
input double           RetraceFib            = 0.50;        // used by RETRACE_FIB
input bool             UseOBBodyOnly         = false;       // RETRACE_OB: body range instead of full wick range
input ENUM_ENTRY_MODE  EntryMode             = ENTRY_ZONE_TOUCH;
input int              MaxRetraceBars        = 20;          // bars allowed for the pullback to arrive
input int              MaxConfirmBars        = 3;           // bars allowed for the confirmation close after the tap

input group "=== Stops / Targets ==="
input double           StopBufferATRmult     = 0.10;        // beyond the sweep extreme
input ENUM_TARGET_MODE TargetMode            = TARGET_HYBRID;
input double           FixedRR               = 2.0;
input double           MinRR                 = 1.0;         // below this, TARGET_HYBRID falls back to fixed RR
input double           TargetBufferATRmult   = 0.10;        // stop short of the opposing level by this much

input group "=== Management (both OFF by default so raw R is measurable) ==="
input double           BreakevenR            = 0.0;         // move to BE at this R. 0 = off
input double           TrailStartR           = 0.0;         // start ATR trail at this R. 0 = off
input double           TrailATRmult          = 1.5;

input group "=== Optional higher-timeframe bias filter ==="
input bool             UseHTFBias            = false;       // this is a reversal model - default OFF, test before trusting
input ENUM_TIMEFRAMES  BiasTF                = PERIOD_H4;
input int              BiasMAPeriod          = 50;

input group "=== Risk / Lot Sizing ==="
input ENUM_LOT_MODE    LotMode               = LOT_DYNAMIC;
input double           RiskPercent           = 1.0;
input double           FixedLotSize          = 0.01;
input int              MaxConcurrentTrades   = 1;

input group "=== Diagnostics ==="
input bool             DebugDraw             = true;
input bool             DebugTradeLog         = true;
input bool             DebugFunnel           = true;

//====================================================================
// TYPES
//====================================================================
struct LiqLevel
  {
   double            price;         // the extreme where the liquidity rests
   bool              isHigh;        // true = buy-side liquidity above, false = sell-side below
   datetime          created;
   datetime          lastTouch;
   int               touches;
   ENUM_LEVEL_STATE  state;
  };

//====================================================================
// STATE
//====================================================================
ENUM_LSB_STATE g_state = WAIT_FOR_SWEEP;

LiqLevel g_levels[];

bool     g_pursuingShort   = false;
double   g_sweptLevelPrice = 0.0;
int      g_sweptTouches    = 0;
double   g_sweepExtreme    = 0.0;
datetime g_sweepBarTime    = 0;
double   g_sweepDepthATR   = 0.0;   // measured, logged, never used to reject
int      g_barsSinceSweep  = 0;

double   g_protectedSwing  = 0.0;
datetime g_bosBarTime      = 0;
double   g_bosExtreme      = 0.0;
int      g_barsSinceBOS    = 0;

double   g_zoneNear        = 0.0;   // the edge price first touches
double   g_zoneFar         = 0.0;
int      g_barsSinceTap    = 0;

ulong    g_activeTicket    = 0;
double   g_entryPrice      = 0.0;
double   g_entrySL         = 0.0;
double   g_entryRisk       = 0.0;
bool     g_beDone          = false;

int      atrHandle  = INVALID_HANDLE;
int      biasHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

// funnel counters
int f_levels = 0, f_sweeps = 0, f_noReclaim = 0, f_reclaims = 0, f_sweepTooDeep = 0;
int f_noProtected = 0, f_bosTimeout = 0, f_bos = 0, f_retraceTimeout = 0, f_taps = 0;
int f_confirmTimeout = 0, f_noZone = 0, f_biasBlock = 0, f_stopsLevelBlock = 0;
int f_maxPosBlock = 0, f_entries = 0, f_invalidatedPreEntry = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double CurrentATR()
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) <= 0)
      return 0.0;
   return buf[0];
  }

double NormPrice(double p)
  {
   return NormalizeDouble(p, _Digits);
  }

void ClearChartObjects()
  {
   ObjectsDeleteAll(0, "TWILSB_");
  }

void DrawLevelLine(string name, double price, color c, ENUM_LINE_STYLE style = STYLE_DASH)
  {
   if(!DebugDraw) return;
   if(MQLInfoInteger(MQL_TESTER)) return;
   string n = "TWILSB_" + name;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_COLOR, c);
      ObjectSetInteger(0, n, OBJPROP_STYLE, style);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
     }
   else
      ObjectSetDouble(0, n, OBJPROP_PRICE, price);
  }

void LogF(string msg)
  {
   PrintFormat("[%s] %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES), msg);
  }

//+------------------------------------------------------------------+
//| Risk sizing                                                      |
//+------------------------------------------------------------------+
double CalcLot(double slDistance)
  {
   if(LotMode == LOT_FIXED) return FixedLotSize;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0 || lotStep <= 0)
      return FixedLotSize;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0) return FixedLotSize;

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Higher-timeframe bias (optional)                                 |
//+------------------------------------------------------------------+
bool BiasAllows(bool wantShort)
  {
   if(!UseHTFBias) return true;
   if(biasHandle == INVALID_HANDLE) return true;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(biasHandle, 0, 0, 1, buf) <= 0) return true;

   double ma = buf[0];
   double px = iClose(_Symbol, BiasTF, 1);
   if(px <= 0) return true;

   bool biasDown = (px < ma);
   return (wantShort == biasDown);
  }

//+------------------------------------------------------------------+
//| LEVEL REGISTRY                                                   |
//|                                                                  |
//| Built continuously from every confirmable fractal pivot, not     |
//| only when a setup is running. Zone lifetime is decoupled from    |
//| setup lifetime - without this, every opposing level in a trend   |
//| reads as already-broken and targets cannot be found.             |
//+------------------------------------------------------------------+
void AddOrMergeLevel(double price, bool isHigh, datetime when, double atr)
  {
   double tol = atr * EqualLevelATRmult;

   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].isHigh != isHigh) continue;
      if(g_levels[i].state != LEVEL_ACTIVE) continue;
      if(MathAbs(g_levels[i].price - price) > tol) continue;

      // Equal high / equal low: same pool of resting liquidity.
      // Keep the true extreme so the sweep test stays honest,
      // keep the original creation time, accumulate the touch count.
      g_levels[i].price     = isHigh ? MathMax(g_levels[i].price, price)
                                     : MathMin(g_levels[i].price, price);
      g_levels[i].touches++;
      g_levels[i].lastTouch = when;
      return;
     }

   int n = ArraySize(g_levels);
   if(n >= MaxLevels)
     {
      ArrayRemove(g_levels, 0, 1);
      n = ArraySize(g_levels);
     }
   ArrayResize(g_levels, n + 1);
   g_levels[n].price     = price;
   g_levels[n].isHigh    = isHigh;
   g_levels[n].created   = when;
   g_levels[n].lastTouch = when;
   g_levels[n].touches   = 1;
   g_levels[n].state     = LEVEL_ACTIVE;
   f_levels++;
  }

//+------------------------------------------------------------------+
//| A pivot is only confirmable once SwingRightBars CLOSED bars      |
//| exist after it. Evaluating from bar 1, that is shift             |
//| 1 + SwingRightBars. Nothing here can repaint.                    |
//+------------------------------------------------------------------+
void ScanForNewSwing(double atr)
  {
   int s = 1 + SwingRightBars;
   int need = s + SwingLeftBars + 2;
   if(Bars(_Symbol, StructureTF) < need) return;

   double h = iHigh(_Symbol, StructureTF, s);
   double l = iLow(_Symbol, StructureTF, s);
   datetime t = iTime(_Symbol, StructureTF, s);

   bool isSwingHigh = true, isSwingLow = true;

   for(int k = 1; k <= SwingLeftBars; k++)
     {
      if(iHigh(_Symbol, StructureTF, s + k) >= h) isSwingHigh = false;
      if(iLow(_Symbol, StructureTF, s + k)  <= l) isSwingLow  = false;
     }
   for(int k = 1; k <= SwingRightBars; k++)
     {
      if(iHigh(_Symbol, StructureTF, s - k) >= h) isSwingHigh = false;
      if(iLow(_Symbol, StructureTF, s - k)  <= l) isSwingLow  = false;
     }

   if(isSwingHigh) AddOrMergeLevel(h, true,  t, atr);
   if(isSwingLow)  AddOrMergeLevel(l, false, t, atr);
  }

//+------------------------------------------------------------------+
//| Retire levels that genuinely BROKE (decisive body close beyond)  |
//| as opposed to being raided by a wick. A wick never retires a     |
//| level - that distinction is the whole strategy.                  |
//+------------------------------------------------------------------+
void UpdateLevelStates(double atr)
  {
   double open1  = iOpen(_Symbol,  StructureTF, 1);
   double close1 = iClose(_Symbol, StructureTF, 1);
   double bodyHi = MathMax(open1, close1);
   double bodyLo = MathMin(open1, close1);
   double buf    = atr * LevelBreakATRmult;
   datetime cutoff = iTime(_Symbol, StructureTF, 1) - (datetime)(LevelMaxAgeBars * PeriodSeconds(StructureTF));

   for(int i = ArraySize(g_levels) - 1; i >= 0; i--)
     {
      if(g_levels[i].created < cutoff)
        {
         ArrayRemove(g_levels, i, 1);
         continue;
        }
      if(g_levels[i].state != LEVEL_ACTIVE) continue;

      if(g_levels[i].isHigh)
        {
         if(bodyLo > g_levels[i].price + buf) g_levels[i].state = LEVEL_BROKEN;
        }
      else
        {
         if(bodyHi < g_levels[i].price - buf) g_levels[i].state = LEVEL_BROKEN;
        }
     }
  }

//+------------------------------------------------------------------+
//| Most recent confirmed swing on the opposite side of the sweep -  |
//| the structure that must break for the reversal to be real.       |
//+------------------------------------------------------------------+
bool FindProtectedSwing(bool forShort, datetime notAfter, double &outPrice)
  {
   bool found = false;
   datetime best = 0;
   double bestPrice = 0.0;

   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].isHigh == forShort) continue;   // short needs a swing LOW
      if(g_levels[i].created > notAfter) continue;
      if(g_levels[i].created >= best)
        {
         best = g_levels[i].created;
         bestPrice = g_levels[i].price;
         found = true;
        }
     }
   if(found) outPrice = bestPrice;
   return found;
  }

//+------------------------------------------------------------------+
//| Nearest unswept opposing liquidity for the target.               |
//+------------------------------------------------------------------+
bool FindOpposingLiquidity(bool forShort, double fromPrice, double &outPrice)
  {
   bool found = false;
   double best = 0.0;

   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].state != LEVEL_ACTIVE) continue;
      if(g_levels[i].isHigh == forShort) continue;   // short targets a swing LOW

      double p = g_levels[i].price;
      if(forShort)
        {
         if(p >= fromPrice) continue;                // must be below entry
         if(!found || p > best) { best = p; found = true; }   // nearest below
        }
      else
        {
         if(p <= fromPrice) continue;
         if(!found || p < best) { best = p; found = true; }   // nearest above
        }
     }
   if(found) outPrice = best;
   return found;
  }

//+------------------------------------------------------------------+
void ResetSetup(string reason)
  {
   if(reason != "" && DebugFunnel) LogF("SETUP RESET: " + reason);
   g_state = WAIT_FOR_SWEEP;
   g_sweptLevelPrice = 0.0; g_sweptTouches = 0;
   g_sweepExtreme = 0.0; g_sweepBarTime = 0; g_sweepDepthATR = 0.0;
   g_barsSinceSweep = 0;
   g_protectedSwing = 0.0; g_bosBarTime = 0; g_bosExtreme = 0.0; g_barsSinceBOS = 0;
   g_zoneNear = 0.0; g_zoneFar = 0.0; g_barsSinceTap = 0;
   ClearChartObjects();
  }

//+------------------------------------------------------------------+
//| STAGE 1+2: find a level whose liquidity just got raided.         |
//+------------------------------------------------------------------+
void CheckForSweep(double atr)
  {
   double high1  = iHigh(_Symbol,  StructureTF, 1);
   double low1   = iLow(_Symbol,   StructureTF, 1);
   double close1 = iClose(_Symbol, StructureTF, 1);
   datetime t1   = iTime(_Symbol,  StructureTF, 1);

   int    bestIdx = -1;
   int    bestTouches = -1;
   double bestDist = 0.0;

   for(int i = 0; i < ArraySize(g_levels); i++)
     {
      if(g_levels[i].state != LEVEL_ACTIVE) continue;
      if(g_levels[i].touches < MinLevelTouches) continue;
      if(g_levels[i].created >= t1) continue;

      double p = g_levels[i].price;
      bool swept = g_levels[i].isHigh ? (high1 > p + atr * MinSweepATRmult)
                                      : (low1  < p - atr * MinSweepATRmult);
      if(!swept) continue;

      double dist = g_levels[i].isHigh ? (high1 - p) : (p - low1);

      // Strongest pool of liquidity first (equal highs/lows), nearest as tie-break.
      if(g_levels[i].touches > bestTouches ||
         (g_levels[i].touches == bestTouches && dist < bestDist))
        {
         bestIdx = i; bestTouches = g_levels[i].touches; bestDist = dist;
        }
     }

   if(bestIdx < 0) return;

   double lvl   = g_levels[bestIdx].price;
   bool   isHi  = g_levels[bestIdx].isHigh;
   double depth = isHi ? (high1 - lvl) : (lvl - low1);

   if(MaxSweepATRmult > 0.0 && depth > atr * MaxSweepATRmult)
     {
      f_sweepTooDeep++;
      g_levels[bestIdx].state = LEVEL_BROKEN;
      if(DebugFunnel)
         LogF(StringFormat("NO TRADE: sweep %.2f ATR beyond %.5f exceeds cap - trend continuation, level retired",
                           depth / atr, lvl));
      return;
     }

   g_pursuingShort   = isHi;
   g_sweptLevelPrice = lvl;
   g_sweptTouches    = g_levels[bestIdx].touches;
   g_sweepExtreme    = isHi ? high1 : low1;
   g_sweepBarTime    = t1;
   g_sweepDepthATR   = (atr > 0) ? depth / atr : 0.0;
   g_barsSinceSweep  = 0;
   g_levels[bestIdx].state = LEVEL_SWEPT;
   f_sweeps++;

   DrawLevelLine("Level", lvl, clrGold, STYLE_SOLID);
   DrawLevelLine("Sweep", g_sweepExtreme, isHi ? clrRed : clrLime);

   if(DebugFunnel)
      LogF(StringFormat("SWEEP: %s liquidity at %.5f (touches=%d) raided to %.5f, depth=%.2f ATR",
                        isHi ? "buy-side" : "sell-side", lvl, g_sweptTouches, g_sweepExtreme, g_sweepDepthATR));

   // Did it already close back inside on the sweep bar itself?
   bool reclaimed = g_pursuingShort ? (close1 < lvl) : (close1 > lvl);
   if(reclaimed)
     {
      f_reclaims++;
      if(DebugFunnel) LogF("RECLAIM: closed back inside on the sweep bar");
      ArmBOSStage();
     }
   else
      g_state = WAIT_FOR_RECLAIM;
  }

//+------------------------------------------------------------------+
//| STAGE 3: close back inside.                                      |
//+------------------------------------------------------------------+
void HandleWaitForReclaim()
  {
   g_barsSinceSweep++;
   double close1 = iClose(_Symbol, StructureTF, 1);
   double high1  = iHigh(_Symbol,  StructureTF, 1);
   double low1   = iLow(_Symbol,   StructureTF, 1);

   // track a deeper raid on the same level
   if(g_pursuingShort) g_sweepExtreme = MathMax(g_sweepExtreme, high1);
   else                g_sweepExtreme = MathMin(g_sweepExtreme, low1);

   bool reclaimed = g_pursuingShort ? (close1 < g_sweptLevelPrice)
                                    : (close1 > g_sweptLevelPrice);
   if(reclaimed)
     {
      f_reclaims++;
      if(DebugFunnel) LogF("RECLAIM: closed back inside the level");
      ArmBOSStage();
      return;
     }

   if(g_barsSinceSweep >= MaxReclaimBars)
     {
      f_noReclaim++;
      ResetSetup(StringFormat("no reclaim within %d bars - that was a breakout, not a raid", MaxReclaimBars));
     }
  }

//+------------------------------------------------------------------+
void ArmBOSStage()
  {
   double atr = CurrentATR();

   if(!FindProtectedSwing(g_pursuingShort, g_sweepBarTime, g_protectedSwing))
     {
      f_noProtected++;
      ResetSetup("no protected swing on the opposite side - nothing to break");
      return;
     }

   if(MaxBOSDistanceATRmult > 0.0 && atr > 0.0)
     {
      double d = MathAbs(g_sweepExtreme - g_protectedSwing);
      if(d > atr * MaxBOSDistanceATRmult)
        {
         f_noProtected++;
         ResetSetup(StringFormat("protected swing %.2f ATR away - too deep to be a meaningful BOS", d / atr));
         return;
        }
     }

   DrawLevelLine("Protected", g_protectedSwing, clrDodgerBlue, STYLE_DOT);
   g_barsSinceBOS = 0;
   g_state = WAIT_FOR_BOS;

   if(DebugFunnel)
      LogF(StringFormat("ARMED: waiting for BOS %s %.5f",
                        g_pursuingShort ? "below" : "above", g_protectedSwing));
  }

//+------------------------------------------------------------------+
//| STAGE 4: break of structure.                                     |
//+------------------------------------------------------------------+
void HandleWaitForBOS(double atr)
  {
   g_barsSinceBOS++;
   double close1 = iClose(_Symbol, StructureTF, 1);
   double high1  = iHigh(_Symbol,  StructureTF, 1);
   double low1   = iLow(_Symbol,   StructureTF, 1);
   double buf    = atr * BOSBufferATRmult;

   // If price takes out the sweep extreme again before structure breaks,
   // the raid failed - the level is genuinely being run through.
   if(g_pursuingShort ? (high1 > g_sweepExtreme) : (low1 < g_sweepExtreme))
     {
      f_invalidatedPreEntry++;
      ResetSetup("sweep extreme violated before BOS - the raid failed");
      return;
     }

   bool bos = g_pursuingShort ? (close1 < g_protectedSwing - buf)
                              : (close1 > g_protectedSwing + buf);
   if(bos)
     {
      f_bos++;
      g_bosBarTime = iTime(_Symbol, StructureTF, 1);
      g_bosExtreme = g_pursuingShort ? low1 : high1;
      g_barsSinceBOS = 0;

      if(!BuildRetraceZone(atr))
        {
         f_noZone++;
         ResetSetup("BOS confirmed but no valid retracement zone could be built");
         return;
        }

      g_state = WAIT_FOR_RETRACE;
      DrawLevelLine("ZoneNear", g_zoneNear, clrOrange);
      DrawLevelLine("ZoneFar",  g_zoneFar,  clrOrange, STYLE_DOT);

      if(DebugFunnel)
         LogF(StringFormat("BOS: closed %.5f through %.5f - zone %.5f / %.5f",
                           close1, g_protectedSwing, g_zoneNear, g_zoneFar));
      return;
     }

   if(g_barsSinceBOS >= MaxBOSBars)
     {
      f_bosTimeout++;
      ResetSetup(StringFormat("no BOS within %d bars", MaxBOSBars));
     }
  }

//+------------------------------------------------------------------+
//| Build the retracement zone from the BOS leg.                     |
//| g_zoneNear is the edge price reaches first on the pullback.      |
//+------------------------------------------------------------------+
bool BuildRetraceZone(double atr)
  {
   switch(RetraceMode)
     {
      case RETRACE_FVG:  return BuildFVGZone();
      case RETRACE_OB:   return BuildOBZone();
      case RETRACE_FIB:
      default:           return BuildFibZone();
     }
  }

bool BuildFibZone()
  {
   double legLow  = MathMin(g_sweepExtreme, g_bosExtreme);
   double legHigh = MathMax(g_sweepExtreme, g_bosExtreme);
   double leg = legHigh - legLow;
   if(leg <= 0) return false;

   if(g_pursuingShort)
     {
      g_zoneNear = g_bosExtreme + leg * RetraceFib;
      g_zoneFar  = g_sweepExtreme;
     }
   else
     {
      g_zoneNear = g_bosExtreme - leg * RetraceFib;
      g_zoneFar  = g_sweepExtreme;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| FVG inside the BOS impulse. Three consecutive bars A(old) B C.   |
//| Bearish gap: low[A] > high[C]. Bullish gap: low[C] > high[A].    |
//+------------------------------------------------------------------+
bool BuildFVGZone()
  {
   int bosShift = iBarShift(_Symbol, StructureTF, g_bosBarTime, false);
   int swpShift = iBarShift(_Symbol, StructureTF, g_sweepBarTime, false);
   if(bosShift < 0 || swpShift < 0 || swpShift <= bosShift) return false;

   bool found = false;
   double nearBest = 0.0, farBest = 0.0;

   for(int s = bosShift; s <= swpShift - 2; s++)
     {
      double aLow  = iLow(_Symbol,  StructureTF, s + 2);
      double aHigh = iHigh(_Symbol, StructureTF, s + 2);
      double cLow  = iLow(_Symbol,  StructureTF, s);
      double cHigh = iHigh(_Symbol, StructureTF, s);

      if(g_pursuingShort)
        {
         if(aLow > cHigh)                      // bearish gap [cHigh .. aLow]
           {
            double nr = cHigh, fr = aLow;      // price rises, hits the bottom first
            if(!found || nr < nearBest) { nearBest = nr; farBest = fr; found = true; }
           }
        }
      else
        {
         if(cLow > aHigh)                      // bullish gap [aHigh .. cLow]
           {
            double nr = cLow, fr = aHigh;      // price falls, hits the top first
            if(!found || nr > nearBest) { nearBest = nr; farBest = fr; found = true; }
           }
        }
     }

   if(!found) return false;
   g_zoneNear = nearBest;
   g_zoneFar  = farBest;
   return true;
  }

//+------------------------------------------------------------------+
//| Order block: last opposing candle before the BOS impulse.        |
//+------------------------------------------------------------------+
bool BuildOBZone()
  {
   int bosShift = iBarShift(_Symbol, StructureTF, g_bosBarTime, false);
   int swpShift = iBarShift(_Symbol, StructureTF, g_sweepBarTime, false);
   if(bosShift < 0 || swpShift < 0 || swpShift < bosShift) return false;

   for(int s = bosShift; s <= swpShift; s++)
     {
      double o = iOpen(_Symbol,  StructureTF, s);
      double c = iClose(_Symbol, StructureTF, s);
      double h = iHigh(_Symbol,  StructureTF, s);
      double l = iLow(_Symbol,   StructureTF, s);

      bool opposing = g_pursuingShort ? (c > o) : (c < o);
      if(!opposing) continue;

      double top = UseOBBodyOnly ? MathMax(o, c) : h;
      double bot = UseOBBodyOnly ? MathMin(o, c) : l;

      if(g_pursuingShort) { g_zoneNear = bot; g_zoneFar = top; }
      else                { g_zoneNear = top; g_zoneFar = bot; }
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| STAGE 5: wait for the pullback to reach the zone.                |
//+------------------------------------------------------------------+
void HandleWaitForRetrace()
  {
   g_barsSinceBOS++;
   double high1 = iHigh(_Symbol, StructureTF, 1);
   double low1  = iLow(_Symbol,  StructureTF, 1);

   // The impulse may still be extending - the leg isn't finished until
   // price turns, so keep the fib anchored to the live extreme.
   if(RetraceMode == RETRACE_FIB)
     {
      bool extended = g_pursuingShort ? (low1 < g_bosExtreme) : (high1 > g_bosExtreme);
      if(extended)
        {
         g_bosExtreme = g_pursuingShort ? low1 : high1;
         BuildFibZone();
         DrawLevelLine("ZoneNear", g_zoneNear, clrOrange);
        }
     }

   if(g_pursuingShort ? (high1 > g_sweepExtreme) : (low1 < g_sweepExtreme))
     {
      f_invalidatedPreEntry++;
      ResetSetup("sweep extreme violated before entry");
      return;
     }

   bool tapped = g_pursuingShort ? (high1 >= g_zoneNear) : (low1 <= g_zoneNear);
   if(tapped)
     {
      f_taps++;
      g_barsSinceTap = 0;
      if(EntryMode == ENTRY_ZONE_TOUCH)
        {
         TryEnter();
         return;
        }
      g_state = WAIT_FOR_ENTRY_CONFIRM;
      if(DebugFunnel) LogF("ZONE TAPPED: waiting on confirmation close");
      return;
     }

   if(g_barsSinceBOS >= MaxRetraceBars)
     {
      f_retraceTimeout++;
      ResetSetup(StringFormat("no retracement into the zone within %d bars", MaxRetraceBars));
     }
  }

//+------------------------------------------------------------------+
//| STAGE 5b: optional confirmation close.                           |
//+------------------------------------------------------------------+
void HandleWaitForConfirm()
  {
   g_barsSinceTap++;
   double open1  = iOpen(_Symbol,  StructureTF, 1);
   double close1 = iClose(_Symbol, StructureTF, 1);
   double high1  = iHigh(_Symbol,  StructureTF, 1);
   double low1   = iLow(_Symbol,   StructureTF, 1);

   if(g_pursuingShort ? (high1 > g_sweepExtreme) : (low1 < g_sweepExtreme))
     {
      f_invalidatedPreEntry++;
      ResetSetup("sweep extreme violated before entry");
      return;
     }

   bool confirmed = g_pursuingShort ? (close1 < open1) : (close1 > open1);
   if(confirmed)
     {
      TryEnter();
      return;
     }

   if(g_barsSinceTap >= MaxConfirmBars)
     {
      f_confirmTimeout++;
      ResetSetup(StringFormat("no confirmation close within %d bars", MaxConfirmBars));
     }
  }

//+------------------------------------------------------------------+
//| STAGE 6: entry, SL beyond the sweep, TP at liquidity or fixed R. |
//+------------------------------------------------------------------+
void TryEnter()
  {
   if(!BiasAllows(g_pursuingShort))
     {
      f_biasBlock++;
      ResetSetup("higher-timeframe bias blocks this direction");
      return;
     }

   if(CountOpenPositions() >= MaxConcurrentTrades)
     {
      f_maxPosBlock++;
      ResetSetup("max concurrent trades reached");
      return;
     }

   double atr = CurrentATR();
   if(atr <= 0) { ResetSetup("no ATR"); return; }

   double entry = g_pursuingShort ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(entry <= 0) { ResetSetup("no price"); return; }

   double buffer = atr * StopBufferATRmult;
   double sl = g_pursuingShort ? g_sweepExtreme + buffer : g_sweepExtreme - buffer;
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0) { ResetSetup("zero risk distance"); return; }

   // ---- target ----
   double tp = 0.0;
   double liq = 0.0;
   bool haveLiq = FindOpposingLiquidity(g_pursuingShort, entry, liq);
   double tpBuf = atr * TargetBufferATRmult;
   double liqTP = g_pursuingShort ? liq + tpBuf : liq - tpBuf;
   double rrLiq = haveLiq ? (MathAbs(liqTP - entry) / riskDist) : 0.0;
   double fixedTP = g_pursuingShort ? entry - riskDist * FixedRR
                                    : entry + riskDist * FixedRR;
   string tpSource = "";

   switch(TargetMode)
     {
      case TARGET_FIXED_RR:
         tp = fixedTP; tpSource = "fixed RR";
         break;

      case TARGET_OPPOSITE_LIQUIDITY:
         if(!haveLiq)
           {
            ResetSetup("no opposing liquidity for the target");
            return;
           }
         tp = liqTP; tpSource = "opposing liquidity";
         break;

      case TARGET_HYBRID:
      default:
         if(haveLiq && rrLiq >= MinRR) { tp = liqTP;  tpSource = StringFormat("opposing liquidity (RR %.2f)", rrLiq); }
         else                          { tp = fixedTP; tpSource = haveLiq
                                                       ? StringFormat("fixed RR (liquidity only offered %.2fR)", rrLiq)
                                                       : "fixed RR (blue sky - no unswept liquidity)"; }
         break;
     }

   double rewardDist = MathAbs(tp - entry);
   double rr = rewardDist / riskDist;

   // ---- broker stops-level guard ----
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * _Point;
   if(minDist > 0 && (riskDist <= minDist || rewardDist <= minDist))
     {
      f_stopsLevelBlock++;
      ResetSetup(StringFormat("SL/TP inside the broker stops level (%d points)", (int)stopsLevel));
      return;
     }

   entry = NormPrice(entry);
   sl    = NormPrice(sl);
   tp    = NormPrice(tp);

   double lots = CalcLot(riskDist);
   if(lots <= 0) { ResetSetup("lot size resolved to zero"); return; }

   bool ok = g_pursuingShort ? trade.Sell(lots, _Symbol, 0.0, sl, tp, "TWI LiqSweep BOS")
                             : trade.Buy(lots,  _Symbol, 0.0, sl, tp, "TWI LiqSweep BOS");
   if(!ok)
     {
      LogF(StringFormat("ORDER FAILED: retcode=%d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      ResetSetup("order send failed");
      return;
     }

   f_entries++;
   g_activeTicket = trade.ResultOrder();
   g_entryPrice   = entry;
   g_entrySL      = sl;
   g_entryRisk    = riskDist;
   g_beDone       = false;
   g_state        = TRADE_ACTIVE;

   if(DebugTradeLog)
     {
      PrintFormat("---------------- TRADE #%d ----------------", f_entries);
      PrintFormat("  Direction      : %s", g_pursuingShort ? "SHORT" : "LONG");
      PrintFormat("  Liquidity level: %.5f  (touches=%d)", g_sweptLevelPrice, g_sweptTouches);
      PrintFormat("  Sweep extreme  : %.5f  (depth %.2f ATR)", g_sweepExtreme, g_sweepDepthATR);
      PrintFormat("  Protected swing: %.5f", g_protectedSwing);
      PrintFormat("  Retrace zone   : near %.5f  far %.5f  (%s)", g_zoneNear, g_zoneFar,
                  RetraceMode == RETRACE_FIB ? "fib" : (RetraceMode == RETRACE_FVG ? "fvg" : "ob"));
      PrintFormat("  Entry / SL     : %.5f / %.5f   risk=%.5f  lots=%.2f", entry, sl, riskDist, lots);
      PrintFormat("  TP             : %.5f   RR=%.2f   source=%s", tp, rr, tpSource);
      PrintFormat("-------------------------------------------");
     }
  }

//+------------------------------------------------------------------+
//| Management - both legs default OFF so raw R stays measurable.    |
//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   if(!PositionSelectByTicket(g_activeTicket))
     {
      g_activeTicket = 0;
      ResetSetup("");
      return;
     }
   if(BreakevenR <= 0.0 && TrailStartR <= 0.0) return;

   double atr = CurrentATR();
   bool isShort = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double px    = isShort ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_entryRisk <= 0) return;

   double rNow = (isShort ? (open - px) : (px - open)) / g_entryRisk;
   double newSL = curSL;

   if(BreakevenR > 0.0 && !g_beDone && rNow >= BreakevenR)
     {
      newSL = open;
      g_beDone = true;
     }

   if(TrailStartR > 0.0 && rNow >= TrailStartR && atr > 0)
     {
      double trail = isShort ? px + atr * TrailATRmult : px - atr * TrailATRmult;
      if(isShort) { if(trail < newSL || newSL == 0) newSL = trail; }
      else        { if(trail > newSL || newSL == 0) newSL = trail; }
     }

   newSL = NormPrice(newSL);
   bool improves = isShort ? (newSL < curSL || curSL == 0) : (newSL > curSL || curSL == 0);
   if(improves && MathAbs(newSL - curSL) > _Point)
      trade.PositionModify(g_activeTicket, newSL, curTP);
  }

//+------------------------------------------------------------------+
void RunStateMachine()
  {
   double atr = CurrentATR();
   if(atr <= 0) return;

   ScanForNewSwing(atr);
   UpdateLevelStates(atr);

   switch(g_state)
     {
      case WAIT_FOR_SWEEP:         CheckForSweep(atr);      break;
      case WAIT_FOR_RECLAIM:       HandleWaitForReclaim();  break;
      case WAIT_FOR_BOS:           HandleWaitForBOS(atr);   break;
      case WAIT_FOR_RETRACE:       HandleWaitForRetrace();  break;
      case WAIT_FOR_ENTRY_CONFIRM: HandleWaitForConfirm();  break;
      case TRADE_ACTIVE:           ManageOpenTrade();       break;
     }
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, StructureTF, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(SwingLeftBars < 1 || SwingRightBars < 1)
     {
      Print("TWI Liquidity Sweep BOS: SwingLeftBars and SwingRightBars must both be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(RetraceFib <= 0.0 || RetraceFib >= 1.0)
     {
      Print("TWI Liquidity Sweep BOS: RetraceFib must sit between 0 and 1");
      return INIT_PARAMETERS_INCORRECT;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   atrHandle = iATR(_Symbol, StructureTF, AtrPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("TWI Liquidity Sweep BOS: failed to create ATR handle");
      return INIT_FAILED;
     }

   if(UseHTFBias)
     {
      biasHandle = iMA(_Symbol, BiasTF, BiasMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(biasHandle == INVALID_HANDLE)
        {
         Print("TWI Liquidity Sweep BOS: failed to create bias MA handle");
         return INIT_FAILED;
        }
     }

   ArrayResize(g_levels, 0);
   ResetSetup("");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(DebugFunnel)
     {
      Print("================ TWI LIQUIDITY SWEEP BOS - FUNNEL ================");
      PrintFormat(" levels registered      : %d", f_levels);
      PrintFormat(" sweeps detected        : %d", f_sweeps);
      PrintFormat("   sweep too deep       : %d", f_sweepTooDeep);
      PrintFormat("   no reclaim           : %d", f_noReclaim);
      PrintFormat(" reclaims confirmed     : %d", f_reclaims);
      PrintFormat("   no protected swing   : %d", f_noProtected);
      PrintFormat("   BOS timeout          : %d", f_bosTimeout);
      PrintFormat(" BOS confirmed          : %d", f_bos);
      PrintFormat("   no retrace zone      : %d", f_noZone);
      PrintFormat("   retrace timeout      : %d", f_retraceTimeout);
      PrintFormat(" zone tapped            : %d", f_taps);
      PrintFormat("   confirm timeout      : %d", f_confirmTimeout);
      PrintFormat("   invalidated pre-entry: %d", f_invalidatedPreEntry);
      PrintFormat("   bias blocked         : %d", f_biasBlock);
      PrintFormat("   stops-level blocked  : %d", f_stopsLevelBlock);
      PrintFormat("   max-positions blocked: %d", f_maxPosBlock);
      PrintFormat(" ENTRIES                : %d", f_entries);
      Print("=================================================================");
     }
   if(atrHandle  != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(biasHandle != INVALID_HANDLE) IndicatorRelease(biasHandle);
   ClearChartObjects();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(IsNewBar())
      RunStateMachine();
  }
//+------------------------------------------------------------------+
