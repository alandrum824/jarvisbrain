//+------------------------------------------------------------------+
//|                              TWI Liquidity Sweep OB EA.mq5       |
//|                                                                  |
//|  LIQUIDITY SWEEP -> BREAK OF STRUCTURE -> ORDER BLOCK RETEST     |
//|  Primary market: XAUUSD.  Primary execution timeframe: M1.       |
//|                                                                  |
//|  SELL sequence (BUY is the exact mirror):                        |
//|   1. A confirmed swing HIGH is registered as resting liquidity.   |
//|      Near-equal highs merge into one level priced at the cluster  |
//|      extreme, which is where stops actually sit.                  |
//|   2. Price trades above that level by >= MinSweepPoints.          |
//|   3. Price returns and CLOSES back below the level within         |
//|      MaxSweepConfirmationBars. No close back inside = it was a    |
//|      breakout, not a raid, and the level is retired.              |
//|   4. Price CLOSES below the swing low that was the most recent    |
//|      CONFIRMED structural low at the moment the sweep completed.  |
//|      That reference is frozen when the sweep confirms and is      |
//|      never re-selected afterwards.                                |
//|   5. The last bullish candle between the sweep bar and the BOS    |
//|      bar becomes the bearish order block.                         |
//|   6. Price retraces into the OB and produces bearish rejection.   |
//|   7. SELL. SL beyond the sweep extreme + buffer. TP per mode.     |
//|                                                                  |
//|  NO REPAINTING:                                                  |
//|   - Every setup decision is taken on CLOSED bars only (shift>=1). |
//|   - A swing point is only registered once SwingBarsRight bars     |
//|     have CLOSED after it. It can never be relocated afterwards,   |
//|     and once a level has been used by a setup it is LOCKED        |
//|     against any further merging.                                  |
//|   - No indicator or price is ever read from bar 0 for a signal.   |
//|   - Trade management reads only the live price, never a future    |
//|     bar, so it is safe to run on every tick.                      |
//|                                                                  |
//|  NOT PRESENT BY DESIGN: martingale, grid, averaging into losers,  |
//|  post-entry stop widening or stop removal.                        |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property description "Liquidity sweep -> BOS -> order block retest. XAUUSD M1. Objective rules, no repainting, heavy logging."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_SETUP_STATE
  {
   SEARCH_LIQUIDITY,
   WAIT_SWEEP,
   WAIT_RETURN_INSIDE,
   WAIT_BOS,
   FIND_OB,
   WAIT_OB_RETEST,
   WAIT_ENTRY_CONFIRMATION,
   TRADE_ACTIVE,
   SETUP_COMPLETE,
   SETUP_INVALID
  };

enum ENUM_OB_ZONE_MODE
  {
   OB_FULL_RANGE,        // high to low of the OB candle
   OB_OPEN_TO_EXTREME,   // bearish OB = open->high, bullish OB = open->low
   OB_BODY               // open/close body only
  };

enum ENUM_ENTRY_METHOD
  {
   ENTRY_MARKET_TOUCH,          // enter as soon as the OB near edge is touched
   ENTRY_OB_MIDPOINT,           // wait for price to reach the OB midpoint
   ENTRY_REJECTION_CONFIRMATION // wait for a confirmed rejection candle
  };

enum ENUM_REJECTION_METHOD
  {
   REJ_CLOSE_BEYOND_MIDPOINT,   // candle closes back past the OB midpoint
   REJ_CLOSE_BEYOND_PREV_CANDLE // candle closes beyond the previous candle's extreme
  };

enum ENUM_SL_MODE
  {
   SL_SWEEP_EXTREME,
   SL_OB_EXTREME,
   SL_ATR,
   SL_FIXED_POINTS
  };

enum ENUM_TP_MODE
  {
   TP_FIXED_RR,
   TP_PREVIOUS_LIQUIDITY,
   TP_STRUCTURE_EXTREME,
   TP_PARTIAL_RR_RUNNER
  };

enum ENUM_BIAS_MODE
  {
   BIAS_OFF,
   BIAS_M5_STRUCTURE,
   BIAS_M15_STRUCTURE,
   BIAS_EMA
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED,
   LOT_PERCENT_RISK
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== General ==="
input long              MagicNumber              = 20260922;
input ENUM_TIMEFRAMES   ExecutionTF              = PERIOD_M1;  // primary execution timeframe
input string            TradeComment             = "TWI LiqSweepOB";

input group "=== 1. Liquidity (swing detection) ==="
input int               SwingBarsLeft            = 3;     // bars to the LEFT that must be lower/higher
input int               SwingBarsRight           = 3;     // bars to the RIGHT. A swing is only CONFIRMED once this many bars have CLOSED after it
input bool              UseEqualLevels           = true;  // merge near-equal highs/lows into one liquidity pool
input int               EqualLevelTolerancePoints= 50;    // how close two swings must be to count as "equal"
input int               MaxSwingPoints           = 300;   // registry cap
input int               SwingMaxAgeBars          = 1500;  // forget swings older than this

input group "=== 2. Liquidity sweep ==="
input bool              UseMinSweepDepthFilter   = false; // V1 IS DELIBERATELY OFF. Collect sweep-depth data first; do not filter on an unproven minimum penetration
input int               MinSweepPoints           = 0;     // only applied when UseMinSweepDepthFilter is true
input int               MaxSweepPoints           = 0;     // sweep deeper than this = genuine breakout, level retired. 0 = no cap. Kept as real protection
input bool              RequireCloseBackInside   = true;  // require a CLOSE back inside, not just a wick return
input int               MaxSweepConfirmationBars = 3;     // bars allowed to get back inside

input group "=== 3. Break of structure ==="
input bool              RequireCloseForBOS       = true;  // require a CLOSE beyond the structural swing, not a wick
input int               MaxBarsSweepToBOS        = 10;    // bars allowed between sweep confirmation and BOS
input int               BOSBufferPoints          = 0;     // extra distance the BOS must clear

input group "=== 3b. Displacement quality filter ==="
input bool              UseDisplacementFilter    = true;
input int               ATRPeriod                = 14;
input double            DisplacementATRMultiplier= 1.0;   // BOS candle body must be >= this x ATR

input group "=== 4. Order block ==="
input ENUM_OB_ZONE_MODE OBZoneMode               = OB_OPEN_TO_EXTREME;
input bool              UseOBCluster             = false; // merge consecutive same-colour candles into one OB. OFF by default - measured worse in TWI BOS Trap Entry
input int               MaxOBSearchBars          = 20;    // how far back from the BOS bar to look for the OB candle
input int               MinOBSizePoints          = 0;     // reject an OB thinner than this. 0 = off

input group "=== 5. Retest / entry ==="
input ENUM_ENTRY_METHOD   EntryMethod            = ENTRY_REJECTION_CONFIRMATION;
input ENUM_REJECTION_METHOD RejectionMethod      = REJ_CLOSE_BEYOND_MIDPOINT;
input int               MaxOBRetestBars          = 60;    // bars the OB stays valid waiting for a retest
input int               MaxConfirmationBars      = 5;     // bars allowed for rejection confirmation after the OB is touched
input bool              InvalidateOBIfBroken     = true;
input int               InvalidationBufferPoints = 20;    // close beyond sweep extreme by this much kills the setup

input group "=== Stop loss ==="
input ENUM_SL_MODE      SLMode                   = SL_SWEEP_EXTREME;
input int               SLBufferPoints           = 30;
input double            SLATRMultiplier          = 1.5;   // SL_ATR only
input int               FixedSLPoints            = 300;   // SL_FIXED_POINTS only

input group "=== Take profit ==="
input ENUM_TP_MODE      TPMode                   = TP_FIXED_RR;
input double            RiskRewardRatio          = 2.0;
input int               TPBufferPoints           = 20;    // stop short of the target level by this much

input group "=== Optional trade management (ALL default OFF) ==="
input bool              UseBreakeven             = false;
input double            BreakevenTriggerR        = 1.0;
input int               BreakevenOffsetPoints    = 0;
input bool              UsePartialClose          = false;
input double            PartialCloseR            = 1.0;
input double            PartialClosePercent      = 50.0;
input double            RunnerRR                 = 4.0;   // TP_PARTIAL_RR_RUNNER target for the remainder

input group "=== Higher-timeframe bias (optional) ==="
input ENUM_BIAS_MODE    BiasMode                 = BIAS_OFF;
input int               BiasSwingBars            = 3;     // swing sensitivity used by structure bias modes
input int               BiasEMAPeriod            = 50;    // EMA_BIAS only

input group "=== Session filter (broker server time) ==="
input bool              UseSessionFilter         = true;
input string            Session1Start            = "08:00";
input string            Session1End              = "11:00";
input bool              UseSession2              = true;
input string            Session2Start            = "13:00";
input string            Session2End              = "17:00";
input bool              TradeMonday              = true;
input bool              TradeTuesday             = true;
input bool              TradeWednesday           = true;
input bool              TradeThursday            = true;
input bool              TradeFriday              = true;
input bool              CloseTradesOutsideSession= false;

input group "=== Volatility / spread safety ==="
input int               MaxSpreadPoints          = 55; // AAAFx XAUUSD broker-compatible; real-tick spread audit 2026-09-23
input int               MinATRPoints             = 0;     // 0 = off
input int               MaxATRPoints             = 0;     // 0 = off
input bool              UseNewsFilter            = false; // see IsHighImpactNewsWindow() - deliberately a STUB, not wired

input group "=== Risk / position sizing ==="
input ENUM_LOT_MODE     LotMode                  = LOT_PERCENT_RISK;
input double            RiskPercent              = 0.5;
input double            FixedLotSize             = 0.01;
input double            RiskOvershootTolerancePercent = 10.0; // final projected risk may exceed RiskPercent by at most this relative %. Broker minimum lot can force this; beyond it, the trade is REJECTED rather than oversized
input int               MaxTradesPerDay          = 3;
input int               MaxLossesPerDay          = 2;
input double            DailyLossLimitPercent    = 0.0;   // 0 = off
input bool              StopTradingAfterDailyTarget = false;
input double            DailyProfitTargetPercent = 0.0;   // 0 = off

input group "=== Visuals ==="
input bool              ShowVisuals              = true;
input bool              KeepHistoricalDrawings   = true;
input int               MaxChartObjects          = 600;

input group "=== Diagnostics ==="
input bool              DebugMode                = true;
input bool              PrintSummaryOnDeinit     = true;

//====================================================================
// TYPES
//====================================================================
struct SwingPoint
  {
   double            price;
   datetime          time;          // the bar the pivot actually printed on
   datetime          confirmedTime; // the bar at which it became KNOWABLE to the EA
   bool              isHigh;
   int               touches;       // how many near-equal swings merged into this level
   bool              swept;
   bool              broken;
   bool              locked;        // used by a setup - never merge into it again
  };

struct Setup
  {
   bool              isShort;
   ENUM_SETUP_STATE  state;

   double            levelPrice;      // the swept liquidity level
   datetime          levelTime;
   int               levelTouches;

   double            sweepExtreme;    // furthest point of the raid
   datetime          sweepBarTime;
   double            sweepPoints;     // measured penetration in points - recorded for analysis, not used to reject unless the filter is explicitly enabled
   int               depthBucket;     // which sweep-depth bucket this setup belongs to
   int               barsSinceSweep;

   double            bosLevel;        // frozen structural swing at sweep-confirmation time
   datetime          bosLevelTime;
   datetime          bosBarTime;
   int               barsSinceConfirm;

   double            obTop;
   double            obBottom;
   datetime          obBarTime;
   int               barsSinceOB;

   bool              obTouched;
   int               barsSinceTouch;

   double            structExtreme;   // displacement extreme, used by TP_STRUCTURE_EXTREME

   ulong             posTicket;         // = the position's own ticket, MT5's stable unique position identifier
   double            entryPrice;
   double            entrySL;
   double            entryRisk;         // price-distance risk (entry-SL), used only for R-based management triggers (BE/trail), NOT for R-multiple accounting
   double            initialRiskMoney;  // dollar risk at the ORIGINAL SL and ACTUAL lots, via OrderCalcProfit(), frozen at entry - NEVER recomputed, the sole denominator for RMultiple
   bool              riskValid;         // false if initialRiskMoney could not be established - such a trade is flagged R_INVALID, never faked
   bool              beDone;
   bool              partialDone;
   int               entrySession; // session at ENTRY (reporting only)
  };

//====================================================================
// GLOBALS
//====================================================================
SwingPoint g_swings[];
Setup      g_short;
Setup      g_long;

int      atrHandle     = INVALID_HANDLE;
int      biasEMAHandle = INVALID_HANDLE;
datetime lastBarTime   = 0;

string   g_objNames[];
int      g_objSeq = 0;

double   g_point = 0.0;

// session parsing
int      g_s1StartMin = 0, g_s1EndMin = 0, g_s2StartMin = 0, g_s2EndMin = 0;

// daily tracking
int      g_dayStamp        = -1;
double   g_dayStartBalance = 0.0;
int      g_tradesToday     = 0;
int      g_lossesToday     = 0;
bool     g_dayBlocked      = false;

// statistics
int    st_swingsRegistered = 0;
int    st_setupsDetected   = 0;
int    st_sweeps           = 0;
int    st_sweepsConfirmed  = 0;
int    st_sweepNoReturn    = 0;
int    st_sweepTooDeep     = 0;
int    st_bosConfirmed     = 0;
int    st_bosTimeout       = 0;
int    st_displacementFail = 0;
int    st_obFound          = 0;
int    st_obNotFound       = 0;
int    st_obRetests        = 0;
int    st_obExpired        = 0;
int    st_obInvalidated    = 0;
int    st_confirmTimeout   = 0;
int    st_blockedSession   = 0;
int    st_blockedSpread    = 0;
int    st_blockedATR       = 0;
int    st_blockedBias      = 0;
int    st_blockedDaily     = 0;
int    st_blockedStopLevel = 0;
int    st_blockedMargin    = 0;
int    st_tradesEntered    = 0;
int    st_wins = 0, st_losses = 0, st_breakevens = 0, st_rInvalid = 0;
int    st_buyTrades = 0, st_sellTrades = 0;
int    st_buyWins = 0, st_sellWins = 0;
double st_buyR = 0.0, st_sellR = 0.0;
double st_sumR = 0.0;
double st_grossProfit = 0.0, st_grossLoss = 0.0;
int    st_consecLosses = 0, st_maxConsecLosses = 0;
int    st_sess1Trades = 0, st_sess2Trades = 0, st_sessOtherTrades = 0;
double st_sess1R = 0.0, st_sess2R = 0.0, st_sessOtherR = 0.0;
double st_sumCommission = 0.0, st_sumSwap = 0.0;   // reporting only - summed once per finalized position

//--------------------------------------------------------------------
// SWEEP-DEPTH BUCKETS
//
// The whole point of running V1 with the depth filter OFF: measure
// whether penetration depth predicts anything before deciding that a
// MinSweepPoints threshold is justified. Buckets: 0 / 1-10 / 11-25 /
// 26-50 / 51-100 / 100+ points.
//--------------------------------------------------------------------
#define DEPTH_BUCKETS 6
int    st_bucketSetups[DEPTH_BUCKETS];
int    st_bucketTrades[DEPTH_BUCKETS];
int    st_bucketValidR[DEPTH_BUCKETS];   // trades in this bucket with a valid frozen InitialRiskMoney - the correct avgR denominator
int    st_bucketWins[DEPTH_BUCKETS];
double st_bucketR[DEPTH_BUCKETS];

int DepthBucket(double depthPoints)
  {
   if(depthPoints <   1.0) return 0;
   if(depthPoints <=  10.0) return 1;
   if(depthPoints <=  25.0) return 2;
   if(depthPoints <=  50.0) return 3;
   if(depthPoints <= 100.0) return 4;
   return 5;
  }

string DepthBucketName(int b)
  {
   switch(b)
     {
      case 0: return "0 pts      ";
      case 1: return "1-10 pts   ";
      case 2: return "11-25 pts  ";
      case 3: return "26-50 pts  ";
      case 4: return "51-100 pts ";
      case 5: return "100+ pts   ";
     }
   return "?          ";
  }

//====================================================================
// UTILITY
//====================================================================
double Pts(int points) { return points * g_point; }

double NormPrice(double p) { return NormalizeDouble(p, _Digits); }

void Dbg(string msg)
  {
   if(!DebugMode) return;
   PrintFormat("[%s] %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS), msg);
  }

double CurrentATR()
  {
   if(atrHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) <= 0) return 0.0;
   return buf[0];
  }

string StateName(ENUM_SETUP_STATE s)
  {
   switch(s)
     {
      case SEARCH_LIQUIDITY:        return "SEARCH_LIQUIDITY";
      case WAIT_SWEEP:              return "WAIT_SWEEP";
      case WAIT_RETURN_INSIDE:      return "WAIT_RETURN_INSIDE";
      case WAIT_BOS:                return "WAIT_BOS";
      case FIND_OB:                 return "FIND_OB";
      case WAIT_OB_RETEST:          return "WAIT_OB_RETEST";
      case WAIT_ENTRY_CONFIRMATION: return "WAIT_ENTRY_CONFIRMATION";
      case TRADE_ACTIVE:            return "TRADE_ACTIVE";
      case SETUP_COMPLETE:          return "SETUP_COMPLETE";
      case SETUP_INVALID:           return "SETUP_INVALID";
     }
   return "?";
  }

//====================================================================
// CHART VISUALS
//====================================================================
bool VisualsOn()
  {
   if(!ShowVisuals) return false;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return false;
   return true;
  }

void RegisterObject(string name)
  {
   int n = ArraySize(g_objNames);
   ArrayResize(g_objNames, n + 1);
   g_objNames[n] = name;

   while(ArraySize(g_objNames) > MaxChartObjects)
     {
      ObjectDelete(0, g_objNames[0]);
      ArrayRemove(g_objNames, 0, 1);
     }
  }

void DrawHLineSeg(string tag, datetime t1, datetime t2, double price, color c,
                  ENUM_LINE_STYLE style, int width, string text)
  {
   if(!VisualsOn()) return;
   string name = StringFormat("TWIOB_%s_%d", tag, g_objSeq++);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   if(text != "") ObjectSetString(0, name, OBJPROP_TEXT, text);
   RegisterObject(name);
  }

void DrawBox(string tag, datetime t1, double p1, datetime t2, double p2, color c)
  {
   if(!VisualsOn()) return;
   string name = StringFormat("TWIOB_%s_%d", tag, g_objSeq++);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, false);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   RegisterObject(name);
  }

void DrawLabel(string tag, datetime t, double price, string text, color c, bool above)
  {
   if(!VisualsOn()) return;
   string name = StringFormat("TWIOB_%s_%d", tag, g_objSeq++);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   RegisterObject(name);
  }

void DrawArrow(string tag, datetime t, double price, int code, color c)
  {
   if(!VisualsOn()) return;
   string name = StringFormat("TWIOB_%s_%d", tag, g_objSeq++);
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price)) return;
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   RegisterObject(name);
  }

void ClearAllObjects()
  {
   ObjectsDeleteAll(0, "TWIOB_");
   ArrayResize(g_objNames, 0);
  }

//====================================================================
// SWING REGISTRY
//
// A swing is registered ONLY when SwingBarsRight bars have closed
// after it. Evaluating from bar 1, that is shift 1 + SwingBarsRight.
// Nothing here can look into the future, and a registered price is
// never relocated once a setup has locked it.
//====================================================================
void AddOrMergeSwing(double price, bool isHigh, datetime when)
  {
   if(UseEqualLevels)
     {
      double tol = Pts(EqualLevelTolerancePoints);
      for(int i = 0; i < ArraySize(g_swings); i++)
        {
         if(g_swings[i].isHigh != isHigh) continue;
         if(g_swings[i].swept || g_swings[i].broken || g_swings[i].locked) continue;
         if(MathAbs(g_swings[i].price - price) > tol) continue;

         // Equal highs / equal lows: one pool of resting liquidity.
         // Keep the true extreme - that is where the stops sit.
         g_swings[i].price = isHigh ? MathMax(g_swings[i].price, price)
                                    : MathMin(g_swings[i].price, price);
         g_swings[i].touches++;
         g_swings[i].time = when;
         return;
        }
     }

   int n = ArraySize(g_swings);
   if(n >= MaxSwingPoints)
     {
      ArrayRemove(g_swings, 0, 1);
      n = ArraySize(g_swings);
     }
   ArrayResize(g_swings, n + 1);
   g_swings[n].price   = price;
   g_swings[n].time    = when;
   // The pivot only becomes knowable now, once SwingBarsRight bars have
   // closed after it. Recording this lets the debug log PROVE that no
   // BOS reference was selected before the EA could legitimately see it.
   g_swings[n].confirmedTime = iTime(_Symbol, ExecutionTF, 1);
   g_swings[n].isHigh  = isHigh;
   g_swings[n].touches = 1;
   g_swings[n].swept   = false;
   g_swings[n].broken  = false;
   g_swings[n].locked  = false;
   st_swingsRegistered++;

   if(DebugMode)
      Dbg(StringFormat("Swing %s detected: %s", isHigh ? "high" : "low",
                       DoubleToString(price, _Digits)));

   DrawHLineSeg(isHigh ? "SwHi" : "SwLo", when,
                when + (datetime)(20 * PeriodSeconds(ExecutionTF)),
                price, isHigh ? clrSilver : clrSilver, STYLE_DOT, 1, "");
  }

void ScanForNewSwing()
  {
   int s = 1 + SwingBarsRight;
   if(Bars(_Symbol, ExecutionTF) < s + SwingBarsLeft + 2) return;

   double h = iHigh(_Symbol, ExecutionTF, s);
   double l = iLow(_Symbol,  ExecutionTF, s);
   datetime t = iTime(_Symbol, ExecutionTF, s);

   bool isHi = true, isLo = true;
   for(int k = 1; k <= SwingBarsLeft; k++)
     {
      if(iHigh(_Symbol, ExecutionTF, s + k) >= h) isHi = false;
      if(iLow(_Symbol,  ExecutionTF, s + k) <= l) isLo = false;
     }
   for(int k = 1; k <= SwingBarsRight; k++)
     {
      if(iHigh(_Symbol, ExecutionTF, s - k) >= h) isHi = false;
      if(iLow(_Symbol,  ExecutionTF, s - k) <= l) isLo = false;
     }

   if(isHi) AddOrMergeSwing(h, true,  t);
   if(isLo) AddOrMergeSwing(l, false, t);
  }

void AgeOutSwings()
  {
   datetime cutoff = iTime(_Symbol, ExecutionTF, 1)
                     - (datetime)(SwingMaxAgeBars * PeriodSeconds(ExecutionTF));
   for(int i = ArraySize(g_swings) - 1; i >= 0; i--)
      if(g_swings[i].time < cutoff)
         ArrayRemove(g_swings, i, 1);
  }

//+------------------------------------------------------------------+
//| Most recent CONFIRMED swing on the opposite side, frozen at the   |
//| moment the sweep confirms. This is the BOS reference.             |
//+------------------------------------------------------------------+
bool FindBOSReference(bool forShort, datetime notAfter, datetime nowBarTime,
                      double mustBeBeyond,
                      double &outPrice, datetime &outTime, datetime &outConfirmedTime)
  {
   bool found = false;
   datetime best = 0;
   double bestPrice = 0.0;
   datetime bestConfirmed = 0;

   for(int i = 0; i < ArraySize(g_swings); i++)
     {
      if(g_swings[i].isHigh == forShort) continue;   // short needs a swing LOW
      if(g_swings[i].broken) continue;

      // (a) structural relevance: the pivot must PRINT before the sweep
      if(g_swings[i].time > notAfter) continue;

      // (b) hard no-hindsight guard: the pivot must also have been
      //     KNOWABLE by now. This can never fail by construction - the
      //     registry only ever holds confirmed pivots - but asserting it
      //     is what makes the no-hindsight claim checkable rather than
      //     something you have to take on trust.
      if(g_swings[i].confirmedTime > nowBarTime) continue;

      // must still be unbroken relative to current price, or there is
      // nothing left to break
      if(forShort && g_swings[i].price >= mustBeBeyond) continue;
      if(!forShort && g_swings[i].price <= mustBeBeyond) continue;

      if(g_swings[i].time >= best)
        {
         best = g_swings[i].time;
         bestPrice = g_swings[i].price;
         bestConfirmed = g_swings[i].confirmedTime;
         found = true;
        }
     }
   if(found) { outPrice = bestPrice; outTime = best; outConfirmedTime = bestConfirmed; }
   return found;
  }

//+------------------------------------------------------------------+
//| Nearest unswept opposing liquidity - used by TP_PREVIOUS_LIQUIDITY|
//+------------------------------------------------------------------+
bool FindOpposingLiquidity(bool forShort, double fromPrice, double &outPrice)
  {
   bool found = false;
   double best = 0.0;
   for(int i = 0; i < ArraySize(g_swings); i++)
     {
      if(g_swings[i].isHigh == forShort) continue;
      if(g_swings[i].swept || g_swings[i].broken) continue;
      double p = g_swings[i].price;
      if(forShort)
        {
         if(p >= fromPrice) continue;
         if(!found || p > best) { best = p; found = true; }
        }
      else
        {
         if(p <= fromPrice) continue;
         if(!found || p < best) { best = p; found = true; }
        }
     }
   if(found) outPrice = best;
   return found;
  }

//====================================================================
// FILTERS
//====================================================================
bool ParseHHMM(string s, int &outMinutes)
  {
   string parts[];
   if(StringSplit(s, (ushort)':', parts) != 2) return false;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return false;
   outMinutes = h * 60 + m;
   return true;
  }

bool InWindow(int nowMin, int startMin, int endMin)
  {
   if(startMin == endMin) return false;
   if(startMin < endMin) return (nowMin >= startMin && nowMin < endMin);
   return (nowMin >= startMin || nowMin < endMin);   // crosses midnight
  }

// returns 0 = outside, 1 = session 1, 2 = session 2
int CurrentSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   if(InWindow(nowMin, g_s1StartMin, g_s1EndMin)) return 1;
   if(UseSession2 && InWindow(nowMin, g_s2StartMin, g_s2EndMin)) return 2;
   return 0;
  }

bool DayAllowed()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
     {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
     }
   return false;   // weekend
  }

bool SessionAllowsTrading()
  {
   if(!UseSessionFilter) return true;
   if(!DayAllowed()) return false;
   return (CurrentSession() != 0);
  }

bool SpreadOK()
  {
   if(MaxSpreadPoints <= 0) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= MaxSpreadPoints);
  }

bool ATROK()
  {
   if(MinATRPoints <= 0 && MaxATRPoints <= 0) return true;
   double atr = CurrentATR();
   if(atr <= 0) return true;
   double atrPts = atr / g_point;
   if(MinATRPoints > 0 && atrPts < MinATRPoints) return false;
   if(MaxATRPoints > 0 && atrPts > MaxATRPoints) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| NEWS FILTER - DELIBERATE STUB.                                    |
//|                                                                   |
//| MT5's calendar functions (CalendarValueHistory etc.) return no    |
//| data inside the Strategy Tester on most builds, and are not       |
//| available at all on some brokers. Wiring them here would make     |
//| backtests behave differently from live trading, which is exactly  |
//| the kind of quiet dishonesty this EA is meant to avoid.           |
//|                                                                   |
//| To add a real filter later, implement it in THIS function only    |
//| and return true while a high-impact USD event is inside the       |
//| blackout window. Nothing else needs to change.                    |
//+------------------------------------------------------------------+
bool IsHighImpactNewsWindow()
  {
   if(!UseNewsFilter) return false;
   return false;   // <-- intentionally not implemented; see comment above
  }

//====================================================================
// HIGHER-TIMEFRAME BIAS
//====================================================================
bool HTFStructureBullish(ENUM_TIMEFRAMES tf, bool &valid)
  {
   valid = false;
   int need = 4 * (BiasSwingBars + 1) + 6;
   if(Bars(_Symbol, tf) < need) return false;

   double highs[]; double lows[];
   datetime hT[]; datetime lT[];
   ArrayResize(highs, 0); ArrayResize(lows, 0);

   // walk back over CLOSED bars only, collecting confirmed pivots
   for(int s = 1 + BiasSwingBars; s <= need && (ArraySize(highs) < 2 || ArraySize(lows) < 2); s++)
     {
      double h = iHigh(_Symbol, tf, s);
      double l = iLow(_Symbol,  tf, s);
      bool isHi = true, isLo = true;
      for(int k = 1; k <= BiasSwingBars; k++)
        {
         if(iHigh(_Symbol, tf, s + k) >= h) isHi = false;
         if(iLow(_Symbol,  tf, s + k) <= l) isLo = false;
         if(iHigh(_Symbol, tf, s - k) >= h) isHi = false;
         if(iLow(_Symbol,  tf, s - k) <= l) isLo = false;
        }
      if(isHi && ArraySize(highs) < 2)
        {
         int n = ArraySize(highs); ArrayResize(highs, n + 1); highs[n] = h;
        }
      if(isLo && ArraySize(lows) < 2)
        {
         int n = ArraySize(lows); ArrayResize(lows, n + 1); lows[n] = l;
        }
     }

   if(ArraySize(highs) < 2 || ArraySize(lows) < 2) return false;
   valid = true;
   // highs[0]/lows[0] are the most recent
   bool hh = (highs[0] > highs[1]);
   bool hl = (lows[0]  > lows[1]);
   bool lh = (highs[0] < highs[1]);
   bool ll = (lows[0]  < lows[1]);

   if(hh && hl) return true;
   if(lh && ll) return false;
   valid = false;   // mixed structure - no clean bias
   return false;
  }

bool BiasAllows(bool wantShort)
  {
   if(BiasMode == BIAS_OFF) return true;

   if(BiasMode == BIAS_EMA)
     {
      if(biasEMAHandle == INVALID_HANDLE) return true;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(biasEMAHandle, 0, 1, 1, buf) <= 0) return true;
      double px = iClose(_Symbol, ExecutionTF, 1);
      bool bullish = (px > buf[0]);
      return (wantShort ? !bullish : bullish);
     }

   ENUM_TIMEFRAMES tf = (BiasMode == BIAS_M5_STRUCTURE) ? PERIOD_M5 : PERIOD_M15;
   bool valid = false;
   bool bullish = HTFStructureBullish(tf, valid);
   if(!valid) return false;   // no clean HTF structure = no trade
   return (wantShort ? !bullish : bullish);
  }

//====================================================================
// DAILY LIMITS
//====================================================================
void ResetDailyIfNeeded()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int stamp = dt.year * 1000 + dt.day_of_year;
   if(stamp == g_dayStamp) return;

   g_dayStamp        = stamp;
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_tradesToday     = 0;
   g_lossesToday     = 0;
   g_dayBlocked      = false;
  }

bool DailyLimitsAllow()
  {
   if(g_dayBlocked) return false;

   if(MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay)
     {
      g_dayBlocked = true;
      Dbg("Daily limit: max trades per day reached");
      return false;
     }
   if(MaxLossesPerDay > 0 && g_lossesToday >= MaxLossesPerDay)
     {
      g_dayBlocked = true;
      Dbg("Daily limit: max losses per day reached");
      return false;
     }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_dayStartBalance > 0)
     {
      double pct = (bal - g_dayStartBalance) / g_dayStartBalance * 100.0;
      if(DailyLossLimitPercent > 0 && pct <= -DailyLossLimitPercent)
        {
         g_dayBlocked = true;
         Dbg(StringFormat("Daily limit: loss limit hit (%.2f%%)", pct));
         return false;
        }
      if(StopTradingAfterDailyTarget && DailyProfitTargetPercent > 0 && pct >= DailyProfitTargetPercent)
        {
         g_dayBlocked = true;
         Dbg(StringFormat("Daily target reached (%.2f%%) - standing down", pct));
         return false;
        }
     }
   return true;
  }

//====================================================================
// POSITION SIZING
//
// CRITICAL, 2026-09-22: this broker's raw SYMBOL_TRADE_TICK_VALUE
// (and _PROFIT / _LOSS variants) for XAUUSD reports 0.01, but
// OrderCalcProfit() for a real 1.0-lot, $1.00 price move returns
// $100.00 - the CORRECT figure (contract size 100 x tick size 0.01
// = $1.00/tick/lot). The raw field is wrong by 100x on this account.
// A sizing formula built on that field would oversize every trade
// by roughly 100x. This function NEVER reads that field for sizing -
// only OrderCalcProfit(), MT5's own authoritative trade-engine
// calculation, decides lot size. The raw fields are still read and
// printed on every check, but purely as a diagnostic record of why
// this broker's XAUUSD specification was misleading.
//====================================================================
bool ComputeRiskSizedLots(bool isShort, double entry, double sl,
                          double &outLots, double &outProjectedLoss,
                          double &outProjectedLossPct, string &outFailReason)
  {
   outLots = 0.0; outProjectedLoss = 0.0; outProjectedLossPct = 0.0; outFailReason = "";

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;

   if(LotMode == LOT_FIXED)
     {
      double f = MathFloor(FixedLotSize / lotStep) * lotStep;
      outLots = MathMax(minLot, MathMin(maxLot, f));
      if(outLots <= 0) { outFailReason = "fixed lot size resolved to zero"; return false; }
      return true;
     }

   // ---- diagnostic-only dump of the broker's raw, unreliable fields ----
   double rawTickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double rawTickValueP = 0.0, rawTickValueL = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT, rawTickValueP);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS, rawTickValueL);
   double rawTickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double rawContract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   string rawDump = StringFormat(
      "Diagnostic-only broker raw fields (NEVER used for sizing): TICK_VALUE=%.6f TICK_VALUE_PROFIT=%.6f TICK_VALUE_LOSS=%.6f TICK_SIZE=%.6f CONTRACT_SIZE=%.2f",
      rawTickValue, rawTickValueP, rawTickValueL, rawTickSize, rawContract);

   // ---- step 1: dollar risk allowed, off EQUITY per spec ----
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (RiskPercent / 100.0);

   // ---- step 2: authoritative 1-lot loss at SL via OrderCalcProfit ----
   ENUM_ORDER_TYPE otype = isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double profitAtSL = 0.0;
   ResetLastError();
   bool calcOk = OrderCalcProfit(otype, _Symbol, 1.0, entry, sl, profitAtSL);
   if(!calcOk)
     {
      outFailReason = StringFormat("OrderCalcProfit (1.0 lot probe) failed, error=%d", GetLastError());
      Print("RISK CHECK FAILED: ", outFailReason, "  ", rawDump);
      return false;
     }

   // ---- step 3: absolute 1-lot loss ----
   double riskPerLot = MathAbs(profitAtSL);
   if(riskPerLot <= 0.0)
     {
      outFailReason = StringFormat("riskPerLot <= 0 (OrderCalcProfit returned %.4f for entry=%s sl=%s)",
                                   profitAtSL, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits));
      Print("RISK CHECK FAILED: ", outFailReason, "  ", rawDump);
      return false;
     }

   // ---- step 4: raw lots ----
   double rawLots = riskMoney / riskPerLot;

   // ---- step 5: normalize. Floor only - never round up past intended
   //      risk. The broker minimum is a hard floor we cannot trade
   //      below; if it forces more risk than requested, step 6 below
   //      catches it and rejects the trade rather than oversizing. ----
   double finalLots = MathFloor(rawLots / lotStep) * lotStep;
   if(finalLots < minLot) finalLots = minLot;
   if(finalLots > maxLot) finalLots = maxLot;

   if(finalLots <= 0)
     {
      outFailReason = "normalized lot size resolved to zero";
      Print("RISK CHECK FAILED: ", outFailReason, "  ", rawDump);
      return false;
     }

   // ---- step 6: re-verify the ACTUAL projected loss at the final lot size ----
   ResetLastError();
   double expectedLossAtSL = 0.0;
   bool calcOk2 = OrderCalcProfit(otype, _Symbol, finalLots, entry, sl, expectedLossAtSL);
   if(!calcOk2)
     {
      outFailReason = StringFormat("OrderCalcProfit (final verification) failed, error=%d", GetLastError());
      Print("RISK CHECK FAILED: ", outFailReason, "  ", rawDump);
      return false;
     }

   double projectedLoss    = MathAbs(expectedLossAtSL);
   double projectedLossPct = (equity > 0) ? (projectedLoss / equity * 100.0) : 0.0;
   double maxAllowedPct    = RiskPercent * (1.0 + RiskOvershootTolerancePercent / 100.0);

   Print("RISK CHECK:");
   PrintFormat("  Equity=$%.2f", equity);
   PrintFormat("  TargetRisk=%.2f%% ($%.2f)", RiskPercent, riskMoney);
   PrintFormat("  Entry=%s  SL=%s  SLDistance=%s",
              DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
              DoubleToString(MathAbs(entry - sl), _Digits));
   PrintFormat("  1-lot SL loss (OrderCalcProfit)=$%.2f", riskPerLot);
   PrintFormat("  RawLots=%.4f  FinalLots=%.2f", rawLots, finalLots);
   PrintFormat("  ProjectedLoss=$%.2f  ActualRisk=%.4f%%  (tolerance ceiling %.4f%%)",
              projectedLoss, projectedLossPct, maxAllowedPct);
   Print("  ", rawDump);

   if(projectedLossPct > maxAllowedPct)
     {
      outFailReason = StringFormat(
         "projected risk %.4f%% exceeds tolerance ceiling %.4f%% (target %.2f%% + %.1f%% overshoot allowance) - broker minimum lot forces more risk than requested",
         projectedLossPct, maxAllowedPct, RiskPercent, RiskOvershootTolerancePercent);
      Print("RISK CHECK FAILED: ", outFailReason);
      return false;
     }

   outLots             = finalLots;
   outProjectedLoss    = projectedLoss;
   outProjectedLossPct = projectedLossPct;
   return true;
  }

bool MarginOK(bool isShort, double lots, double price)
  {
   double margin = 0.0;
   ENUM_ORDER_TYPE type = isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin)) return true;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (margin < freeMargin * 0.9);
  }

//====================================================================
// SETUP HELPERS
//====================================================================
void ResetSetup(Setup &s, bool isShort, string reason)
  {
   if(reason != "" && DebugMode)
      Dbg(StringFormat("%s setup reset: %s", isShort ? "SELL" : "BUY", reason));

   s.isShort          = isShort;
   s.state            = SEARCH_LIQUIDITY;
   s.levelPrice       = 0.0;  s.levelTime = 0; s.levelTouches = 0;
   s.sweepExtreme     = 0.0;  s.sweepBarTime = 0; s.sweepPoints = 0.0;
   s.depthBucket      = 0;
   s.barsSinceSweep   = 0;
   s.bosLevel         = 0.0;  s.bosLevelTime = 0; s.bosBarTime = 0;
   s.barsSinceConfirm = 0;
   s.obTop            = 0.0;  s.obBottom = 0.0; s.obBarTime = 0; s.barsSinceOB = 0;
   s.obTouched        = false; s.barsSinceTouch = 0;
   s.structExtreme    = 0.0;
   s.posTicket        = 0;
   s.entryPrice       = 0.0;  s.entrySL = 0.0; s.entryRisk = 0.0;
   s.initialRiskMoney = 0.0;  s.riskValid = false;
   s.beDone           = false; s.partialDone = false;
   s.entrySession     = 0;
  }

void MarkSwingSwept(double price, bool isHigh)
  {
   for(int i = 0; i < ArraySize(g_swings); i++)
      if(g_swings[i].isHigh == isHigh && MathAbs(g_swings[i].price - price) < g_point)
        {
         g_swings[i].swept  = true;
         g_swings[i].locked = true;
         return;
        }
  }

void MarkSwingBroken(double price, bool isHigh)
  {
   for(int i = 0; i < ArraySize(g_swings); i++)
      if(g_swings[i].isHigh == isHigh && MathAbs(g_swings[i].price - price) < g_point)
        {
         g_swings[i].broken = true;
         g_swings[i].locked = true;
         return;
        }
  }

//====================================================================
// STAGE 1 + 2: find liquidity and detect the sweep
//====================================================================
void StateSearchLiquidity(Setup &s)
  {
   double high1  = iHigh(_Symbol,  ExecutionTF, 1);
   double low1   = iLow(_Symbol,   ExecutionTF, 1);
   double close1 = iClose(_Symbol, ExecutionTF, 1);
   datetime t1   = iTime(_Symbol,  ExecutionTF, 1);

   int    bestIdx = -1;
   double bestPen = 0.0;
   int    bestTouches = -1;

   for(int i = 0; i < ArraySize(g_swings); i++)
     {
      if(g_swings[i].isHigh != s.isShort) continue;   // SELL hunts swing highs
      if(g_swings[i].swept || g_swings[i].broken) continue;
      if(g_swings[i].time >= t1) continue;

      double lvl = g_swings[i].price;
      double pen = s.isShort ? (high1 - lvl) : (lvl - low1);

      // Price must at least REACH the level for this to be a liquidity test.
      // A pure touch (pen == 0) is deliberately allowed: SR Sweep Reclaim
      // v3.00 found the majority of valid setups penetrated by exactly zero.
      if(pen < 0) continue;

      // The minimum-depth threshold is an OPTIONAL, OFF-BY-DEFAULT filter.
      // V1 collects depth data rather than filtering on an unproven number.
      if(UseMinSweepDepthFilter && pen < Pts(MinSweepPoints)) continue;

      // strongest pool of liquidity first, deepest penetration as tie-break
      if(g_swings[i].touches > bestTouches ||
         (g_swings[i].touches == bestTouches && pen > bestPen))
        {
         bestIdx = i; bestTouches = g_swings[i].touches; bestPen = pen;
        }
     }

   if(bestIdx < 0) return;

   double lvl = g_swings[bestIdx].price;
   double pen = bestPen;

   if(MaxSweepPoints > 0 && pen > Pts(MaxSweepPoints))
     {
      st_sweepTooDeep++;
      g_swings[bestIdx].broken = true;
      g_swings[bestIdx].locked = true;
      Dbg(StringFormat("%s: level %s cleared by %.0f points - breakout, not a sweep. Level retired.",
                       s.isShort ? "SELL" : "BUY", DoubleToString(lvl, _Digits), pen / g_point));
      return;
     }

   s.levelPrice   = lvl;
   s.levelTime    = g_swings[bestIdx].time;
   s.levelTouches = g_swings[bestIdx].touches;
   s.sweepExtreme = s.isShort ? high1 : low1;
   s.sweepBarTime = t1;
   s.sweepPoints  = pen / g_point;
   s.barsSinceSweep = 0;
   g_swings[bestIdx].locked = true;

   s.depthBucket = DepthBucket(s.sweepPoints);

   st_sweeps++;
   st_setupsDetected++;

   Dbg(StringFormat("%s: liquidity swept. level=%s extreme=%s depth=%.0f points (touches=%d)",
                    s.isShort ? "SELL" : "BUY",
                    DoubleToString(lvl, _Digits),
                    DoubleToString(s.sweepExtreme, _Digits),
                    s.sweepPoints, s.levelTouches));

   DrawHLineSeg("Liq", s.levelTime, t1 + (datetime)(60 * PeriodSeconds(ExecutionTF)),
                lvl, clrGold, STYLE_SOLID, 2, "");
   DrawArrow("Swp", t1, s.sweepExtreme, s.isShort ? 234 : 233,
             s.isShort ? clrRed : clrLime);
   DrawLabel("SwpTxt", t1, s.sweepExtreme,
             s.isShort ? "SELL SWEEP" : "BUY SWEEP",
             s.isShort ? clrRed : clrLime, s.isShort);

   // did it already close back inside on the sweep bar itself?
   bool backInside = s.isShort ? (close1 < lvl) : (close1 > lvl);
   if(!RequireCloseBackInside)
      backInside = s.isShort ? (close1 < s.sweepExtreme) : (close1 > s.sweepExtreme);

   if(backInside)
     {
      ConfirmSweep(s);
      return;
     }

   Dbg(StringFormat("%s: waiting for close back %s liquidity",
                    s.isShort ? "SELL" : "BUY", s.isShort ? "below" : "above"));
   s.state = WAIT_RETURN_INSIDE;
  }

//====================================================================
// STAGE 3: close back inside
//====================================================================
void StateWaitReturnInside(Setup &s)
  {
   s.barsSinceSweep++;
   double high1  = iHigh(_Symbol,  ExecutionTF, 1);
   double low1   = iLow(_Symbol,   ExecutionTF, 1);
   double close1 = iClose(_Symbol, ExecutionTF, 1);

   // a deeper raid on the same level extends the sweep extreme,
   // so the recorded depth has to follow it
   if(s.isShort) s.sweepExtreme = MathMax(s.sweepExtreme, high1);
   else          s.sweepExtreme = MathMin(s.sweepExtreme, low1);

   s.sweepPoints = (s.isShort ? (s.sweepExtreme - s.levelPrice)
                              : (s.levelPrice - s.sweepExtreme)) / g_point;
   s.depthBucket = DepthBucket(s.sweepPoints);

   if(MaxSweepPoints > 0)
     {
      double pen = s.isShort ? (s.sweepExtreme - s.levelPrice) : (s.levelPrice - s.sweepExtreme);
      if(pen > Pts(MaxSweepPoints))
        {
         st_sweepTooDeep++;
         MarkSwingBroken(s.levelPrice, s.isShort);
         ResetSetup(s, s.isShort, "sweep extended into a genuine breakout");
         return;
        }
     }

   bool backInside = s.isShort ? (close1 < s.levelPrice) : (close1 > s.levelPrice);
   if(backInside)
     {
      ConfirmSweep(s);
      return;
     }

   if(s.barsSinceSweep >= MaxSweepConfirmationBars)
     {
      st_sweepNoReturn++;
      MarkSwingBroken(s.levelPrice, s.isShort);
      ResetSetup(s, s.isShort,
                 StringFormat("no close back inside within %d bars - breakout, not a raid",
                              MaxSweepConfirmationBars));
     }
  }

//+------------------------------------------------------------------+
//| Sweep confirmed. FREEZE the BOS reference here and never          |
//| re-select it - this is the single most important no-repaint rule. |
//+------------------------------------------------------------------+
void ConfirmSweep(Setup &s)
  {
   st_sweepsConfirmed++;
   double close1 = iClose(_Symbol, ExecutionTF, 1);
   datetime nowBar = iTime(_Symbol, ExecutionTF, 1);

   // final measured depth for this setup, recorded before anything else
   s.sweepPoints = (s.isShort ? (s.sweepExtreme - s.levelPrice)
                              : (s.levelPrice - s.sweepExtreme)) / g_point;
   s.depthBucket = DepthBucket(s.sweepPoints);
   st_bucketSetups[s.depthBucket]++;

   Dbg(StringFormat("%s: Sweep confirmed: level=%s extreme=%s depth=%.0f points [bucket %s]",
                    s.isShort ? "SELL" : "BUY",
                    DoubleToString(s.levelPrice, _Digits),
                    DoubleToString(s.sweepExtreme, _Digits),
                    s.sweepPoints, DepthBucketName(s.depthBucket)));

   MarkSwingSwept(s.levelPrice, s.isShort);

   double bosPrice = 0.0; datetime bosTime = 0; datetime bosConfirmed = 0;
   if(!FindBOSReference(s.isShort, s.sweepBarTime, nowBar, close1,
                        bosPrice, bosTime, bosConfirmed))
     {
      ResetSetup(s, s.isShort, "no confirmed structural swing available to break");
      return;
     }

   s.bosLevel     = bosPrice;
   s.bosLevelTime = bosTime;
   s.barsSinceConfirm = 0;
   s.state = WAIT_BOS;

   // The frozen reference is printed the instant it is chosen, with the
   // time it became knowable, so the Strategy Tester log can be read back
   // to verify the level was never picked with hindsight.
   Dbg(StringFormat("%s: Sweep confirmed. Frozen %s BOS reference = %s, swing printed at %s, confirmed/knowable at %s (sweep bar %s). FROZEN - never re-selected.",
                    s.isShort ? "SELL" : "BUY",
                    s.isShort ? "bearish" : "bullish",
                    DoubleToString(bosPrice, _Digits),
                    TimeToString(bosTime, TIME_DATE | TIME_MINUTES),
                    TimeToString(bosConfirmed, TIME_DATE | TIME_MINUTES),
                    TimeToString(s.sweepBarTime, TIME_DATE | TIME_MINUTES)));

   DrawHLineSeg("BOSref", bosTime,
                iTime(_Symbol, ExecutionTF, 1) + (datetime)(40 * PeriodSeconds(ExecutionTF)),
                bosPrice, clrDodgerBlue, STYLE_DASH, 1, "");
  }

//====================================================================
// STAGE 4: break of structure
//====================================================================
void StateWaitBOS(Setup &s)
  {
   s.barsSinceConfirm++;
   double open1  = iOpen(_Symbol,  ExecutionTF, 1);
   double high1  = iHigh(_Symbol,  ExecutionTF, 1);
   double low1   = iLow(_Symbol,   ExecutionTF, 1);
   double close1 = iClose(_Symbol, ExecutionTF, 1);
   datetime t1   = iTime(_Symbol,  ExecutionTF, 1);

   // the raid failed if price takes out the sweep extreme again
   if(s.isShort ? (high1 > s.sweepExtreme) : (low1 < s.sweepExtreme))
     {
      st_obInvalidated++;
      ResetSetup(s, s.isShort, "sweep extreme violated before BOS - the raid failed");
      return;
     }

   double buf = Pts(BOSBufferPoints);
   bool bos;
   if(RequireCloseForBOS)
      bos = s.isShort ? (close1 < s.bosLevel - buf) : (close1 > s.bosLevel + buf);
   else
      bos = s.isShort ? (low1 < s.bosLevel - buf)   : (high1 > s.bosLevel + buf);

   if(bos)
     {
      // displacement quality
      if(UseDisplacementFilter)
        {
         double atr = CurrentATR();
         double body = MathAbs(close1 - open1);
         if(atr > 0 && body < atr * DisplacementATRMultiplier)
           {
            st_displacementFail++;
            Dbg(StringFormat("%s: BOS candle body %.0f pts below displacement threshold %.0f pts - rejected",
                             s.isShort ? "SELL" : "BUY", body / g_point,
                             (atr * DisplacementATRMultiplier) / g_point));
            ResetSetup(s, s.isShort, "displacement filter rejected the BOS candle");
            return;
           }
        }

      st_bosConfirmed++;
      s.bosBarTime = t1;
      s.structExtreme = s.isShort ? low1 : high1;
      MarkSwingBroken(s.bosLevel, !s.isShort);

      Dbg(StringFormat("%s: BOS confirmed %s %s",
                       s.isShort ? "SELL" : "BUY",
                       s.isShort ? "below" : "above",
                       DoubleToString(s.bosLevel, _Digits)));

      DrawArrow("BOS", t1, s.isShort ? low1 : high1, 233, clrDodgerBlue);
      DrawLabel("BOSTxt", t1, s.isShort ? low1 : high1,
                s.isShort ? "SELL BOS" : "BUY BOS", clrDodgerBlue, !s.isShort);

      s.state = FIND_OB;
      StateFindOB(s);
      return;
     }

   if(s.barsSinceConfirm >= MaxBarsSweepToBOS)
     {
      st_bosTimeout++;
      ResetSetup(s, s.isShort,
                 StringFormat("no BOS within %d bars of sweep confirmation", MaxBarsSweepToBOS));
     }
  }

//====================================================================
// STAGE 5: order block identification
//
// The OB is the LAST opposing candle between the sweep bar and the
// BOS bar. Scanning backwards from the BOS candle makes this fully
// deterministic and uses only bars that have already closed.
//====================================================================
void StateFindOB(Setup &s)
  {
   int bosShift = iBarShift(_Symbol, ExecutionTF, s.bosBarTime, false);
   int swpShift = iBarShift(_Symbol, ExecutionTF, s.sweepBarTime, false);
   if(bosShift < 0 || swpShift < 0 || swpShift < bosShift)
     {
      st_obNotFound++;
      ResetSetup(s, s.isShort, "bar index lookup failed while searching for the OB");
      return;
     }

   int limit = MathMin(swpShift, bosShift + MaxOBSearchBars);
   int found = -1;

   for(int sh = bosShift; sh <= limit; sh++)
     {
      double o = iOpen(_Symbol,  ExecutionTF, sh);
      double c = iClose(_Symbol, ExecutionTF, sh);
      bool opposing = s.isShort ? (c > o) : (c < o);   // bearish OB = last BULLISH candle
      if(opposing) { found = sh; break; }
     }

   if(found < 0)
     {
      st_obNotFound++;
      ResetSetup(s, s.isShort, "no opposing candle between the sweep and the BOS - no valid OB");
      return;
     }

   double oTop = iHigh(_Symbol, ExecutionTF, found);
   double oBot = iLow(_Symbol,  ExecutionTF, found);
   double oOpen  = iOpen(_Symbol,  ExecutionTF, found);
   double oClose = iClose(_Symbol, ExecutionTF, found);

   // optional cluster: absorb consecutive same-colour candles
   if(UseOBCluster)
     {
      int sh = found + 1;
      while(sh <= limit)
        {
         double o2 = iOpen(_Symbol,  ExecutionTF, sh);
         double c2 = iClose(_Symbol, ExecutionTF, sh);
         bool same = s.isShort ? (c2 > o2) : (c2 < o2);
         if(!same) break;
         oTop = MathMax(oTop, iHigh(_Symbol, ExecutionTF, sh));
         oBot = MathMin(oBot, iLow(_Symbol,  ExecutionTF, sh));
         oOpen = o2;
         sh++;
        }
      found = sh - 1;
     }

   double top, bot;
   switch(OBZoneMode)
     {
      case OB_FULL_RANGE:
         top = oTop; bot = oBot;
         break;
      case OB_BODY:
         top = MathMax(oOpen, oClose); bot = MathMin(oOpen, oClose);
         break;
      case OB_OPEN_TO_EXTREME:
      default:
         // bearish OB = open->high, bullish OB = open->low
         if(s.isShort) { top = oTop; bot = MathMin(oOpen, oTop); }
         else          { top = MathMax(oOpen, oBot); bot = oBot; }
         break;
     }

   if(top <= bot)
     {
      st_obNotFound++;
      ResetSetup(s, s.isShort, "degenerate OB zone");
      return;
     }
   if(MinOBSizePoints > 0 && (top - bot) < Pts(MinOBSizePoints))
     {
      st_obNotFound++;
      ResetSetup(s, s.isShort, StringFormat("OB thinner than %d points", MinOBSizePoints));
      return;
     }

   s.obTop     = top;
   s.obBottom  = bot;
   s.obBarTime = iTime(_Symbol, ExecutionTF, found);
   s.barsSinceOB = 0;
   s.obTouched = false;
   st_obFound++;

   Dbg(StringFormat("%s: %s OB detected %s - %s",
                    s.isShort ? "SELL" : "BUY",
                    s.isShort ? "bearish" : "bullish",
                    DoubleToString(bot, _Digits), DoubleToString(top, _Digits)));

   DrawBox("OB", s.obBarTime, top,
           s.bosBarTime + (datetime)(MaxOBRetestBars * PeriodSeconds(ExecutionTF)), bot,
           s.isShort ? clrTomato : clrMediumSeaGreen);
   DrawLabel("OBTxt", s.obBarTime, s.isShort ? top : bot,
             s.isShort ? "BEARISH OB" : "BULLISH OB",
             s.isShort ? clrTomato : clrMediumSeaGreen, s.isShort);

   s.state = WAIT_OB_RETEST;
   Dbg(StringFormat("%s: waiting for OB retest", s.isShort ? "SELL" : "BUY"));
  }

//====================================================================
// STAGE 6: wait for the retest
//====================================================================
void StateWaitOBRetest(Setup &s)
  {
   s.barsSinceOB++;
   double high1  = iHigh(_Symbol,  ExecutionTF, 1);
   double low1   = iLow(_Symbol,   ExecutionTF, 1);
   double close1 = iClose(_Symbol, ExecutionTF, 1);

   // track the displacement extreme for TP_STRUCTURE_EXTREME
   if(s.isShort) s.structExtreme = MathMin(s.structExtreme, low1);
   else          s.structExtreme = MathMax(s.structExtreme, high1);

   if(SetupInvalidated(s)) { ResetSetup(s, s.isShort, ""); return; }

   if(s.barsSinceOB >= MaxOBRetestBars)
     {
      st_obExpired++;
      ResetSetup(s, s.isShort,
                 StringFormat("OB expired - no retest within %d bars", MaxOBRetestBars));
      return;
     }

   double nearEdge = s.isShort ? s.obBottom : s.obTop;
   double mid      = (s.obTop + s.obBottom) / 2.0;

   bool touched = s.isShort ? (high1 >= nearEdge) : (low1 <= nearEdge);
   if(!touched) return;

   if(!s.obTouched)
     {
      s.obTouched = true;
      s.barsSinceTouch = 0;
      st_obRetests++;
      Dbg(StringFormat("%s: OB touched", s.isShort ? "SELL" : "BUY"));
     }

   switch(EntryMethod)
     {
      case ENTRY_MARKET_TOUCH:
         TryEnter(s);
         return;

      case ENTRY_OB_MIDPOINT:
        {
         bool reachedMid = s.isShort ? (high1 >= mid) : (low1 <= mid);
         if(reachedMid) TryEnter(s);
         else Dbg(StringFormat("%s: OB touched, waiting for midpoint", s.isShort ? "SELL" : "BUY"));
         return;
        }

      case ENTRY_REJECTION_CONFIRMATION:
      default:
         // the tapping bar itself may already be the rejection candle
         if(RejectionConfirmed(s))
           {
            Dbg(StringFormat("%s: rejection confirmed on the tapping bar",
                             s.isShort ? "SELL" : "BUY"));
            TryEnter(s);
            return;
           }
         s.state = WAIT_ENTRY_CONFIRMATION;
         s.barsSinceTouch = 0;
         Dbg(StringFormat("%s: OB touched, waiting for rejection confirmation",
                          s.isShort ? "SELL" : "BUY"));
         return;
     }
  }

//====================================================================
// STAGE 7: rejection confirmation
//
// Extracted into its own test so the SAME bar that taps the OB can
// also be the rejection candle. Requiring a later bar would have
// silently thrown away every setup that tapped and rejected inside
// one candle - common on M1 gold. This reads only closed-bar data
// either way, so it adds no look-ahead.
//====================================================================
bool RejectionConfirmed(Setup &s)
  {
   double open1  = iOpen(_Symbol,  ExecutionTF, 1);
   double close1 = iClose(_Symbol, ExecutionTF, 1);
   double prevHigh = iHigh(_Symbol, ExecutionTF, 2);
   double prevLow  = iLow(_Symbol,  ExecutionTF, 2);
   double mid = (s.obTop + s.obBottom) / 2.0;

   bool directional = s.isShort ? (close1 < open1) : (close1 > open1);
   if(!directional) return false;

   if(RejectionMethod == REJ_CLOSE_BEYOND_MIDPOINT)
      return s.isShort ? (close1 < mid) : (close1 > mid);

   return s.isShort ? (close1 < prevLow) : (close1 > prevHigh);
  }

bool SetupInvalidated(Setup &s)
  {
   if(!InvalidateOBIfBroken) return false;
   double close1 = iClose(_Symbol, ExecutionTF, 1);
   double invalidate = s.isShort ? s.sweepExtreme + Pts(InvalidationBufferPoints)
                                 : s.sweepExtreme - Pts(InvalidationBufferPoints);
   bool broken = s.isShort ? (close1 > invalidate) : (close1 < invalidate);
   if(broken)
     {
      st_obInvalidated++;
      Dbg(StringFormat("%s: setup invalidated - price closed %s the sweep extreme",
                       s.isShort ? "SELL" : "BUY", s.isShort ? "above" : "below"));
     }
   return broken;
  }

void StateWaitEntryConfirmation(Setup &s)
  {
   s.barsSinceTouch++;
   s.barsSinceOB++;

   if(SetupInvalidated(s)) { ResetSetup(s, s.isShort, ""); return; }

   if(RejectionConfirmed(s))
     {
      Dbg(StringFormat("%s: rejection confirmed", s.isShort ? "SELL" : "BUY"));
      TryEnter(s);
      return;
     }

   if(s.barsSinceTouch >= MaxConfirmationBars)
     {
      st_confirmTimeout++;
      ResetSetup(s, s.isShort,
                 StringFormat("no rejection confirmation within %d bars", MaxConfirmationBars));
     }
  }

//====================================================================
// ENTRY
//====================================================================
void TryEnter(Setup &s)
  {
   // ---- gates, each logged separately so misses are diagnosable ----
   if(!SessionAllowsTrading())
     {
      st_blockedSession++;
      ResetSetup(s, s.isShort, "outside trading session / day");
      return;
     }
   if(IsHighImpactNewsWindow())
     {
      ResetSetup(s, s.isShort, "inside news blackout window");
      return;
     }
   if(!SpreadOK())
     {
      st_blockedSpread++;
      ResetSetup(s, s.isShort,
                 StringFormat("spread %d exceeds limit %d",
                              (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), MaxSpreadPoints));
      return;
     }
   if(!ATROK())
     {
      st_blockedATR++;
      ResetSetup(s, s.isShort, "ATR outside the configured band");
      return;
     }
   if(!BiasAllows(s.isShort))
     {
      st_blockedBias++;
      ResetSetup(s, s.isShort, "higher-timeframe bias disagrees");
      return;
     }
   if(!DailyLimitsAllow())
     {
      st_blockedDaily++;
      ResetSetup(s, s.isShort, "daily limits reached");
      return;
     }
   if(CountOurPositions() > 0)
     {
      ResetSetup(s, s.isShort, "a position is already open");
      return;
     }

   double atr = CurrentATR();
   double entry = s.isShort ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(entry <= 0) { ResetSetup(s, s.isShort, "no price available"); return; }

   // ---- stop loss ----
   double sl = 0.0;
   switch(SLMode)
     {
      case SL_OB_EXTREME:
         sl = s.isShort ? s.obTop + Pts(SLBufferPoints) : s.obBottom - Pts(SLBufferPoints);
         break;
      case SL_ATR:
         sl = s.isShort ? entry + atr * SLATRMultiplier : entry - atr * SLATRMultiplier;
         break;
      case SL_FIXED_POINTS:
         sl = s.isShort ? entry + Pts(FixedSLPoints) : entry - Pts(FixedSLPoints);
         break;
      case SL_SWEEP_EXTREME:
      default:
         sl = s.isShort ? s.sweepExtreme + Pts(SLBufferPoints)
                        : s.sweepExtreme - Pts(SLBufferPoints);
         break;
     }

   double risk = MathAbs(entry - sl);
   if(risk <= 0) { ResetSetup(s, s.isShort, "zero risk distance"); return; }

   // ---- take profit ----
   double tp = 0.0;
   string tpSource = "";
   double fixedTP = s.isShort ? entry - risk * RiskRewardRatio : entry + risk * RiskRewardRatio;

   switch(TPMode)
     {
      case TP_PREVIOUS_LIQUIDITY:
        {
         double liq = 0.0;
         if(FindOpposingLiquidity(s.isShort, entry, liq))
           {
            tp = s.isShort ? liq + Pts(TPBufferPoints) : liq - Pts(TPBufferPoints);
            tpSource = "previous liquidity";
           }
         else
           {
            tp = fixedTP; tpSource = "fixed RR (no opposing liquidity found)";
           }
         break;
        }
      case TP_STRUCTURE_EXTREME:
        {
         double se = s.structExtreme;
         bool usable = s.isShort ? (se < entry - Pts(TPBufferPoints))
                                 : (se > entry + Pts(TPBufferPoints));
         if(usable)
           {
            tp = s.isShort ? se + Pts(TPBufferPoints) : se - Pts(TPBufferPoints);
            tpSource = "structure extreme";
           }
         else
           {
            tp = fixedTP; tpSource = "fixed RR (structure extreme already passed)";
           }
         break;
        }
      case TP_PARTIAL_RR_RUNNER:
         tp = s.isShort ? entry - risk * RunnerRR : entry + risk * RunnerRR;
         tpSource = "runner RR";
         break;
      case TP_FIXED_RR:
      default:
         tp = fixedTP; tpSource = "fixed RR";
         break;
     }

   // ---- broker minimum stop distance. Never bypassed: we skip instead. ----
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * g_point;
   if(minDist > 0 && (MathAbs(entry - sl) <= minDist || MathAbs(tp - entry) <= minDist))
     {
      st_blockedStopLevel++;
      ResetSetup(s, s.isShort,
                 StringFormat("SL/TP inside broker stops level (%d points) - trade skipped, never widened",
                              (int)stopsLevel));
      return;
     }

   entry = NormPrice(entry);
   sl    = NormPrice(sl);
   tp    = NormPrice(tp);

   double lots = 0.0, projLoss = 0.0, projLossPct = 0.0;
   string riskFail = "";
   if(!ComputeRiskSizedLots(s.isShort, entry, sl, lots, projLoss, projLossPct, riskFail))
     {
      ResetSetup(s, s.isShort, "risk sizing rejected the trade - " + riskFail);
      return;
     }
   if(!MarginOK(s.isShort, lots, entry))
     {
      st_blockedMargin++;
      ResetSetup(s, s.isShort, "insufficient free margin");
      return;
     }

   bool ok = s.isShort ? trade.Sell(lots, _Symbol, 0.0, sl, tp, TradeComment)
                       : trade.Buy(lots,  _Symbol, 0.0, sl, tp, TradeComment);
   if(!ok)
     {
      Dbg(StringFormat("ORDER FAILED: retcode=%d %s",
                       trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      ResetSetup(s, s.isShort, "order send failed");
      return;
     }

   s.posTicket  = FindOurPositionTicket();
   s.entryPrice = entry;
   s.entrySL    = sl;
   s.entryRisk  = risk;
   s.beDone     = false;
   s.partialDone= false;
   s.state      = TRADE_ACTIVE;
   s.entrySession = CurrentSession();

   // ---- freeze InitialRiskMoney: the R-multiple denominator, NEVER
   //      recomputed after this point regardless of BE/trail/partials.
   //      Uses the ACTUAL executed lots, ACTUAL entry, ORIGINAL SL - not
   //      SYMBOL_TRADE_TICK_VALUE, not a 1.0-lot assumption. ----
   ENUM_ORDER_TYPE otypeR = s.isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double lossAtOriginalSL = 0.0;
   ResetLastError();
   bool riskCalcOk = OrderCalcProfit(otypeR, _Symbol, lots, entry, sl, lossAtOriginalSL);
   if(riskCalcOk && MathAbs(lossAtOriginalSL) > 0.0)
     {
      s.initialRiskMoney = MathAbs(lossAtOriginalSL);
      s.riskValid = true;
     }
   else
     {
      s.initialRiskMoney = 0.0;
      s.riskValid = false;
      Print("R BASE WARNING: could not establish InitialRiskMoney at entry, error=", GetLastError(),
            " - this trade's R result will be flagged R_INVALID");
     }

   st_tradesEntered++;
   g_tradesToday++;
   if(s.isShort) st_sellTrades++; else st_buyTrades++;

   datetime t1 = iTime(_Symbol, ExecutionTF, 1);
   DrawArrow("Ent", t1, entry, s.isShort ? 242 : 241, s.isShort ? clrRed : clrLime);
   DrawLabel("EntTxt", t1, entry, s.isShort ? "SELL ENTRY" : "BUY ENTRY",
             s.isShort ? clrRed : clrLime, !s.isShort);
   DrawHLineSeg("SL", t1, t1 + (datetime)(60 * PeriodSeconds(ExecutionTF)), sl, clrRed, STYLE_DOT, 1, "SL");
   DrawHLineSeg("TP", t1, t1 + (datetime)(60 * PeriodSeconds(ExecutionTF)), tp, clrLime, STYLE_DOT, 1, "TP");

   Dbg(StringFormat("%s OPENED @ %s  SL=%s  TP=%s  risk=%.0f pts  lots=%.2f  RR=%.2f  (TP source: %s)",
                    s.isShort ? "SELL" : "BUY",
                    DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                    DoubleToString(tp, _Digits), risk / g_point, lots,
                    MathAbs(tp - entry) / risk, tpSource));

   Print("R BASE:");
   PrintFormat("  PositionID=%I64u  Direction=%s", s.posTicket, s.isShort ? "SELL" : "BUY");
   PrintFormat("  Entry=%s  OriginalSL=%s  Lots=%.2f",
              DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), lots);
   PrintFormat("  InitialRiskMoney=$%.2f  (riskValid=%s)",
              s.initialRiskMoney, s.riskValid ? "true" : "false");
  }

//====================================================================
// POSITION TRACKING + MANAGEMENT
//====================================================================
int CountOurPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         c++;
     }
   return c;
  }

ulong FindOurPositionTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return tk;
     }
   return 0;
  }

void RecordClosedTrade(Setup &s)
  {
   // Aggregate the COMPLETE deal history for this specific position
   // ticket - not just the most recent DEAL_ENTRY_OUT - so a partial
   // close followed by a final close (UsePartialClose) sums correctly
   // instead of only capturing the last leg. Filtered by DEAL_POSITION_ID,
   // not just symbol+magic, so it can never bleed into a different
   // trade's deals if two positions closed within the lookback window.
   double grossProfit = 0.0, commission = 0.0, swap = 0.0;
   bool anyDealFound = false;
   if(s.posTicket != 0 && HistorySelect(TimeCurrent() - 86400 * 10, TimeCurrent() + 60))
     {
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         if((ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID) != s.posTicket) continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         grossProfit += HistoryDealGetDouble(d, DEAL_PROFIT);
         commission  += HistoryDealGetDouble(d, DEAL_COMMISSION);
         swap        += HistoryDealGetDouble(d, DEAL_SWAP);
         anyDealFound = true;
        }
     }

   double fees = 0.0;   // MT5's deal model exposes profit/commission/swap only - no separate broker "fee" field on this account
   double netPnL = grossProfit + commission + swap + fees;
   st_sumCommission += commission;   // reporting only
   st_sumSwap       += swap;         // reporting only
   double profit = netPnL;   // win/loss classification and dollar P&L stats use the same authoritative net figure

   // ---- R accounting: InitialRiskMoney is FROZEN at entry, never
   //      recomputed here. If it was never established, the trade is
   //      flagged R_INVALID and excluded from every R aggregate rather
   //      than inserting a fabricated number. ----
   bool rInvalid = !anyDealFound || !s.riskValid || s.initialRiskMoney <= 0.0;
   double rMultiple = 0.0;
   if(!rInvalid)
      rMultiple = netPnL / s.initialRiskMoney;
   else
      st_rInvalid++;

   if(profit > 0)      { st_wins++;   st_consecLosses = 0; st_grossProfit += profit; }
   else if(profit < 0) { st_losses++; g_lossesToday++; st_consecLosses++;
                         st_grossLoss += MathAbs(profit);
                         if(st_consecLosses > st_maxConsecLosses) st_maxConsecLosses = st_consecLosses; }
   else                { st_breakevens++; }

   int b = s.depthBucket;
   int sess = s.entrySession;

   if(!rInvalid)
     {
      st_sumR += rMultiple;
      if(s.isShort) st_sellR += rMultiple; else st_buyR += rMultiple;

      if(sess == 1)      st_sess1R += rMultiple;
      else if(sess == 2) st_sess2R += rMultiple;
      else               st_sessOtherR += rMultiple;

      if(b >= 0 && b < DEPTH_BUCKETS) { st_bucketR[b] += rMultiple; st_bucketValidR[b]++; }
     }

   if(s.isShort) { if(profit > 0) st_sellWins++; } else { if(profit > 0) st_buyWins++; }
   if(sess == 1)      st_sess1Trades++;
   else if(sess == 2) st_sess2Trades++;
   else               st_sessOtherTrades++;
   if(b >= 0 && b < DEPTH_BUCKETS)
     {
      st_bucketTrades[b]++;
      if(profit > 0) st_bucketWins[b]++;
     }

   Dbg(StringFormat("%s CLOSED  netPnL=%.2f  R=%s  [sweep depth %.0f pts, bucket %s]",
                    s.isShort ? "SELL" : "BUY", netPnL,
                    rInvalid ? "R_INVALID" : DoubleToString(rMultiple, 2),
                    s.sweepPoints, DepthBucketName(b)));

   Print("R RESULT:");
   PrintFormat("  PositionID=%I64u", s.posTicket);
   PrintFormat("  InitialRiskMoney=$%.2f", s.initialRiskMoney);
   PrintFormat("  GrossProfit=$%.2f  Commission=$%.2f  Swap=$%.2f  Fees=$%.2f", grossProfit, commission, swap, fees);
   PrintFormat("  NetPnL=$%.2f", netPnL);
   if(rInvalid)
      Print("  FinalR=R_INVALID  (InitialRiskMoney could not be recovered for this position - excluded from all R aggregates)");
   else
      PrintFormat("  FinalR=%.2f", rMultiple);
  }

void ManageOpenTrade(Setup &s)
  {
   if(s.posTicket == 0 || !PositionSelectByTicket(s.posTicket))
     {
      if(s.posTicket != 0) RecordClosedTrade(s);
      ResetSetup(s, s.isShort, "");
      return;
     }

   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double vol   = PositionGetDouble(POSITION_VOLUME);
   double px    = s.isShort ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(s.entryRisk <= 0) return;

   double rNow = (s.isShort ? (open - px) : (px - open)) / s.entryRisk;

   // ---- partial close ----
   if(UsePartialClose && !s.partialDone && rNow >= PartialCloseR)
     {
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double closeVol = vol * (PartialClosePercent / 100.0);
      if(lotStep > 0) closeVol = MathFloor(closeVol / lotStep) * lotStep;

      if(closeVol >= minLot && (vol - closeVol) >= minLot)
        {
         if(trade.PositionClosePartial(s.posTicket, closeVol))
           {
            s.partialDone = true;
            Dbg(StringFormat("Partial close %.2f lots at %.2fR", closeVol, rNow));
           }
        }
      else
        {
         s.partialDone = true;   // cannot split this size - don't retry every tick
         Dbg("Partial close skipped: volume cannot be split above broker minimum");
        }
     }

   // ---- breakeven. Only ever tightens; never widens or removes a stop. ----
   if(UseBreakeven && !s.beDone && rNow >= BreakevenTriggerR)
     {
      double newSL = s.isShort ? open - Pts(BreakevenOffsetPoints)
                               : open + Pts(BreakevenOffsetPoints);
      newSL = NormPrice(newSL);
      bool improves = s.isShort ? (newSL < curSL || curSL == 0)
                                : (newSL > curSL || curSL == 0);
      long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      bool farEnough = (MathAbs(px - newSL) > stopsLevel * g_point);

      if(improves && farEnough)
        {
         if(trade.PositionModify(s.posTicket, newSL, curTP))
           {
            s.beDone = true;
            Dbg(StringFormat("Stop moved to breakeven at %.2fR", rNow));
           }
        }
     }
  }

//====================================================================
// STATE MACHINE DRIVER
//====================================================================
void RunSetup(Setup &s)
  {
   switch(s.state)
     {
      case SEARCH_LIQUIDITY:        StateSearchLiquidity(s);      break;
      case WAIT_RETURN_INSIDE:      StateWaitReturnInside(s);     break;
      case WAIT_BOS:                StateWaitBOS(s);              break;
      case FIND_OB:                 StateFindOB(s);               break;
      case WAIT_OB_RETEST:          StateWaitOBRetest(s);         break;
      case WAIT_ENTRY_CONFIRMATION: StateWaitEntryConfirmation(s);break;
      case TRADE_ACTIVE:            /* managed on every tick */   break;
      default:                      ResetSetup(s, s.isShort, ""); break;
     }
  }

//====================================================================
// STATISTICS SUMMARY
//====================================================================
void PrintSummary()
  {
   int totalClosed  = st_wins + st_losses + st_breakevens;
   int validRTrades = totalClosed - st_rInvalid;
   double winRate = (totalClosed > 0)  ? (100.0 * st_wins / totalClosed) : 0.0;
   double avgR    = (validRTrades > 0) ? (st_sumR / validRTrades) : 0.0;   // expectancy in R - averaged only over trades with a valid frozen InitialRiskMoney
   double pf      = (st_grossLoss > 0) ? (st_grossProfit / st_grossLoss) : 0.0;

   Print("=====================================================================");
   Print("        TWI LIQUIDITY SWEEP OB EA  -  SETUP FUNNEL & RESULTS         ");
   Print("=====================================================================");
   PrintFormat(" Swing points registered      : %d", st_swingsRegistered);
   PrintFormat(" Total setups detected        : %d", st_setupsDetected);
   PrintFormat(" Liquidity sweeps             : %d", st_sweeps);
   PrintFormat("   sweep too deep (breakout)  : %d", st_sweepTooDeep);
   PrintFormat("   no close back inside       : %d", st_sweepNoReturn);
   PrintFormat(" Sweeps confirmed             : %d", st_sweepsConfirmed);
   PrintFormat("   BOS timeout                : %d", st_bosTimeout);
   PrintFormat("   displacement filter fail   : %d", st_displacementFail);
   PrintFormat(" Confirmed BOS events         : %d", st_bosConfirmed);
   PrintFormat("   no valid OB found          : %d", st_obNotFound);
   PrintFormat(" Valid OBs                    : %d", st_obFound);
   PrintFormat("   OB expired (no retest)     : %d", st_obExpired);
   PrintFormat("   OB invalidated             : %d", st_obInvalidated);
   PrintFormat(" OB retests                   : %d", st_obRetests);
   PrintFormat("   confirmation timeout       : %d", st_confirmTimeout);
   Print("---------------------------------------------------------------------");
   Print(" Entry gates that blocked a ready setup:");
   PrintFormat("   session / day              : %d", st_blockedSession);
   PrintFormat("   spread                     : %d", st_blockedSpread);
   PrintFormat("   ATR band                   : %d", st_blockedATR);
   PrintFormat("   HTF bias                   : %d", st_blockedBias);
   PrintFormat("   daily limits               : %d", st_blockedDaily);
   PrintFormat("   broker stops level         : %d", st_blockedStopLevel);
   PrintFormat("   margin                     : %d", st_blockedMargin);
   Print("---------------------------------------------------------------------");
   PrintFormat(" TRADES ENTERED               : %d", st_tradesEntered);
   PrintFormat("   wins / losses / breakeven  : %d / %d / %d", st_wins, st_losses, st_breakevens);
   PrintFormat("   win rate                   : %.2f%%", winRate);
   PrintFormat("   R_INVALID (excluded from R): %d", st_rInvalid);
   PrintFormat("   average R (expectancy)     : %.3f  (over %d valid-R trades)", avgR, validRTrades);
   PrintFormat("   total R                    : %.2f", st_sumR);
   PrintFormat("   profit factor              : %.2f", pf);
   PrintFormat("   max consecutive losses     : %d", st_maxConsecLosses);
   Print("---------------------------------------------------------------------");
   PrintFormat(" BUY  : %d trades, %d wins, total %.2fR", st_buyTrades,  st_buyWins,  st_buyR);
   PrintFormat(" SELL : %d trades, %d wins, total %.2fR", st_sellTrades, st_sellWins, st_sellR);
   Print("---------------------------------------------------------------------");
   PrintFormat(" Session 1 (by entry time)       : %d trades, total %.2fR", st_sess1Trades, st_sess1R);
   PrintFormat(" Session 2 (by entry time)       : %d trades, total %.2fR", st_sess2Trades, st_sess2R);
   PrintFormat(" Outside session (by entry time) : %d trades, total %.2fR", st_sessOtherTrades, st_sessOtherR);
   Print("---------------------------------------------------------------------");
   PrintFormat(" Total commission             : $%.2f", st_sumCommission);
   PrintFormat(" Total swap                   : $%.2f", st_sumSwap);
   Print(" NOTE: commission is taken from the tester's symbol specification. $0 means the tester assumed no commission; live AAAFx commission must be verified separately.");
   Print("---------------------------------------------------------------------");
   Print(" SWEEP DEPTH ANALYSIS - does penetration depth predict anything?");
   PrintFormat(" depth filter was %s",
               UseMinSweepDepthFilter
               ? StringFormat("ON at %d points - THESE BUCKETS ARE CENSORED", MinSweepPoints)
               : "OFF - full uncensored distribution");
   Print("   bucket        setups   trades    wins    winrate     totalR      avgR");
   for(int b = 0; b < DEPTH_BUCKETS; b++)
     {
      double wr  = (st_bucketTrades[b] > 0) ? (100.0 * st_bucketWins[b] / st_bucketTrades[b]) : 0.0;
      double avg = (st_bucketValidR[b] > 0) ? (st_bucketR[b] / st_bucketValidR[b]) : 0.0;
      PrintFormat("   %s %6d   %6d  %6d   %7.2f%%  %9.2f %9.3f",
                  DepthBucketName(b), st_bucketSetups[b], st_bucketTrades[b],
                  st_bucketWins[b], wr, st_bucketR[b], avg);
     }
   Print(" NOTE: a bucket with under ~20 trades is not evidence of anything.");
   Print("=====================================================================");
  }

//====================================================================
// LIFECYCLE
//====================================================================
int OnInit()
  {
   if(SwingBarsLeft < 1 || SwingBarsRight < 1)
     {
      Print("ERROR: SwingBarsLeft and SwingBarsRight must both be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(RiskRewardRatio <= 0)
     {
      Print("ERROR: RiskRewardRatio must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(LotMode == LOT_PERCENT_RISK && RiskPercent <= 0)
     {
      Print("ERROR: RiskPercent must be > 0 when using PERCENT_RISK sizing");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(UsePartialClose && (PartialClosePercent <= 0 || PartialClosePercent >= 100))
     {
      Print("ERROR: PartialClosePercent must sit between 0 and 100");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!ParseHHMM(Session1Start, g_s1StartMin) || !ParseHHMM(Session1End, g_s1EndMin))
     {
      Print("ERROR: Session1 times must be HH:MM (24h broker server time)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(UseSession2 && (!ParseHHMM(Session2Start, g_s2StartMin) || !ParseHHMM(Session2End, g_s2EndMin)))
     {
      Print("ERROR: Session2 times must be HH:MM (24h broker server time)");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(g_point <= 0)
     {
      Print("ERROR: could not read symbol point size");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   atrHandle = iATR(_Symbol, ExecutionTF, ATRPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("ERROR: failed to create ATR handle");
      return INIT_FAILED;
     }

   if(BiasMode == BIAS_EMA)
     {
      biasEMAHandle = iMA(_Symbol, ExecutionTF, BiasEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(biasEMAHandle == INVALID_HANDLE)
        {
         Print("ERROR: failed to create bias EMA handle");
         return INIT_FAILED;
        }
     }

   ArrayResize(g_swings, 0);
   ArrayResize(g_objNames, 0);
   ArrayInitialize(st_bucketSetups, 0);
   ArrayInitialize(st_bucketTrades, 0);
   ArrayInitialize(st_bucketValidR, 0);
   ArrayInitialize(st_bucketWins,   0);
   ArrayInitialize(st_bucketR,      0.0);
   ResetSetup(g_short, true,  "");
   ResetSetup(g_long,  false, "");
   ResetDailyIfNeeded();

   if(UseMinSweepDepthFilter)
      Print("NOTE: UseMinSweepDepthFilter is ON at ", MinSweepPoints,
            " points. The sweep-depth buckets in the summary will be CENSORED - "
            "setups below the threshold never enter the sample. Turn it off to measure the real distribution.");

   if(UseNewsFilter)
      Print("NOTE: UseNewsFilter is ON but IsHighImpactNewsWindow() is a deliberate stub - "
            "no news filtering is actually happening. See the comment above that function.");

   Print("TWI Liquidity Sweep OB EA initialised on ", _Symbol,
         "  TF=", EnumToString(ExecutionTF), "  point=", DoubleToString(g_point, 8));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(PrintSummaryOnDeinit) PrintSummary();
   if(atrHandle     != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(biasEMAHandle != INVALID_HANDLE) IndicatorRelease(biasEMAHandle);
   if(!KeepHistoricalDrawings) ClearAllObjects();
  }

bool IsNewBar()
  {
   datetime t = iTime(_Symbol, ExecutionTF, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
  }

void OnTick()
  {
   // Management runs every tick - it reads only the live price and the
   // open position, never a future bar, so this cannot repaint.
   if(g_short.state == TRADE_ACTIVE) ManageOpenTrade(g_short);
   if(g_long.state  == TRADE_ACTIVE) ManageOpenTrade(g_long);

   if(!IsNewBar()) return;

   ResetDailyIfNeeded();

   if(CloseTradesOutsideSession && !SessionAllowsTrading() && CountOurPositions() > 0)
     {
      if(g_short.state == TRADE_ACTIVE && g_short.posTicket != 0)
         trade.PositionClose(g_short.posTicket);
      if(g_long.state == TRADE_ACTIVE && g_long.posTicket != 0)
         trade.PositionClose(g_long.posTicket);
     }

   // Registry is maintained continuously, independent of setup state.
   ScanForNewSwing();
   AgeOutSwings();

   RunSetup(g_short);
   RunSetup(g_long);
  }

double OnTester()
  {
   int validRTrades = st_wins + st_losses + st_breakevens - st_rInvalid;
   if(validRTrades < 1) return 0.0;
   return st_sumR / validRTrades;   // average R (expectancy) as the optimisation criterion
  }
//+------------------------------------------------------------------+
