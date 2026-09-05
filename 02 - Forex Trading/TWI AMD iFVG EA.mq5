//+------------------------------------------------------------------+
//|                                       TWI AMD iFVG EA.mq5        |
//|  Accumulation -> Manipulation -> Distribution, entered off an     |
//|  inverted Fair Value Gap.                                         |
//|                                                                     |
//|  1. ACCUMULATION: price coils into a real tight range (range <=   |
//|     AccumulationATRmult x ATR over AccumulationBars) -- an ATR-    |
//|     relative check, not a raw point threshold, so it self-scales  |
//|     across symbols (forex vs gold) without separate calibration.  |
//|  2. MANIPULATION: price wicks beyond the range (min/max ATR       |
//|     bounded, same dual-guard as TWI OB Hunter) then closes back   |
//|     inside -- a real stop-hunt, not a breakout.                   |
//|  3. iFVG: a Fair Value Gap forms during the reversal off the      |
//|     manipulation extreme; when price later closes through it     |
//|     against its own original bias, it INVERTS and becomes the     |
//|     entry zone.                                                   |
//|  4. DISTRIBUTION: retrace into the IFVG, confirm rejection, enter |
//|     toward the opposite side of the accumulation range.           |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
enum ENUM_AMD_STATE
  {
   WAIT_FOR_ACCUMULATION,
   ACCUMULATION_LOCKED,
   WAIT_FOR_RECLAIM,
   WAIT_FOR_IFVG,
   WAIT_FOR_RETRACE,
   WAIT_FOR_ENTRY_CONFIRMATION,
   TRADE_ACTIVE
  };

enum ENUM_ENTRY_MODE
  {
   IFVG_TOUCH,
   IFVG_50_PERCENT,
   IFVG_REJECTION_CLOSE
  };

enum ENUM_TARGET_MODE
  {
   OPPOSITE_RANGE,
   MEASURED_MOVE,
   FIXED_RR
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED,
   LOT_DYNAMIC
  };

enum ENUM_FVG_STATE
  {
   FVG_ACTIVE,
   FVG_PARTIALLY_FILLED,
   FVG_INVERTED
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== General ==="
input long              MagicNumber          = 20260903;
input ENUM_TIMEFRAMES   StructureTF          = PERIOD_M5;   // timeframe the accumulation/manipulation is read on

input group "=== Accumulation ==="
input int                AccumulationBars     = 15;          // bars the range is measured over
input double              AccumulationATRmult  = 4.0;         // range must be <= this x (single-bar) ATR to count as a real base --
                                                                // note this compares a multi-bar range against single-bar ATR, so it
                                                                // needs to be well above 1.0 even for genuinely tight consolidation
input int                 AtrPeriod            = 14;

input group "=== Manipulation (sweep) ==="
input double              SweepMinATRmult      = 0.10;        // min wick beyond the range, as ATR multiple
input double              MaxSweepATRmult      = 3.0;         // invalidate if the wick travels beyond this many ATR -- trend continuation, not a raid
input int                 ReclaimBars          = 3;           // bars allowed for the close-back-inside confirmation

input group "=== FVG / IFVG ==="
input double              MinFVGATRmult        = 0.05;        // min gap size, as ATR multiple (self-scaling across symbols)
input int                 IFVGLookbackBars     = 30;

input group "=== Entry ==="
input ENUM_ENTRY_MODE     EntryMode            = IFVG_REJECTION_CLOSE;
input ENUM_TARGET_MODE    TargetMode           = OPPOSITE_RANGE;
input double              FixedRRTarget        = 3.0;
input double              StopBufferATRmult    = 0.10;
input double              MinimumRR            = 2.0;

input group "=== Risk / Lot Sizing ==="
input ENUM_LOT_MODE       LotMode              = LOT_DYNAMIC;
input double              RiskPercent          = 1.0;
input double              FixedLotSize         = 0.01;

input group "=== Trade Caps ==="
input int                 MaxConcurrentTrades  = 1;

input group "=== Display ==="
input bool                ShowZonesOnChart     = true;

//====================================================================
struct FVGZone
  {
   double            top;
   double            bottom;
   bool              isBullish;
   datetime          formedTime;
   ENUM_FVG_STATE    state;
   bool              invertedIsBullish;
   bool              usedForEntry;
  };

//====================================================================
ENUM_AMD_STATE g_state = WAIT_FOR_ACCUMULATION;

double   g_accHigh = 0, g_accLow = 0;
datetime g_accLockedTime = 0;

bool     g_pursuingShort = false;
double   g_sweepExtreme = 0;
datetime g_sweepBarTime = 0;
int      g_barsWaitedForReclaim = 0;

FVGZone  g_fvgList[];
int      g_activeFvgIdx = -1;
int      g_barsWaitedForRetrace = 0;

int      atrHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

ulong    g_activeTicket = 0;

//+------------------------------------------------------------------+
double CurrentATR()
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) <= 0)
      return 0;
   return buf[0];
  }

//+------------------------------------------------------------------+
void ClearChartObjects()
  {
   ObjectsDeleteAll(0, "TWIAMD_");
  }

void DrawLevel(string name, double price, color c)
  {
   if(!ShowZonesOnChart) return;
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
     }
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
  }

//+------------------------------------------------------------------+
void ResetToWaitForAccumulation()
  {
   g_state = WAIT_FOR_ACCUMULATION;
   g_accHigh = 0; g_accLow = 0; g_accLockedTime = 0;
   g_sweepExtreme = 0; g_sweepBarTime = 0; g_barsWaitedForReclaim = 0;
   g_activeFvgIdx = -1; g_barsWaitedForRetrace = 0;
   ClearChartObjects();
  }

//+------------------------------------------------------------------+
// ACCUMULATION: real tight range over AccumulationBars, ATR-relative.
//+------------------------------------------------------------------+
void CheckAccumulation()
  {
   double hi = iHigh(_Symbol, StructureTF, 1);
   double lo = iLow(_Symbol, StructureTF, 1);
   for(int i = 2; i <= AccumulationBars; i++)
     {
      hi = MathMax(hi, iHigh(_Symbol, StructureTF, i));
      lo = MathMin(lo, iLow(_Symbol, StructureTF, i));
     }
   double range = hi - lo;
   double atr = CurrentATR();
   if(atr <= 0) return;

   if(range <= atr * AccumulationATRmult)
     {
      g_accHigh = hi; g_accLow = lo;
      g_accLockedTime = iTime(_Symbol, StructureTF, 1);
      g_state = ACCUMULATION_LOCKED;
      DrawLevel("TWIAMD_AccHigh", g_accHigh, clrDodgerBlue);
      DrawLevel("TWIAMD_AccLow", g_accLow, clrOrangeRed);
      PrintFormat("[%s] Accumulation locked: High=%.5f Low=%.5f Range=%.2fx ATR",
                  TimeToString(TimeCurrent(), TIME_MINUTES), g_accHigh, g_accLow, range / atr);
     }
  }

//+------------------------------------------------------------------+
// MANIPULATION: sweep beyond the accumulation range, ATR dual-bounded.
//+------------------------------------------------------------------+
void CheckManipulation()
  {
   double atr = CurrentATR();
   if(atr <= 0) return;
   double high1 = iHigh(_Symbol, StructureTF, 1);
   double low1  = iLow(_Symbol, StructureTF, 1);
   double close1 = iClose(_Symbol, StructureTF, 1);

   // If price just grinds further without ever sweeping, and drifts far
   // beyond the range without a real wick-based raid, the base is stale --
   // re-lock a fresh accumulation range instead of waiting forever.
   if(high1 > g_accHigh + atr * (MaxSweepATRmult + 1) || low1 < g_accLow - atr * (MaxSweepATRmult + 1))
     {
      PrintFormat("[%s] NO TRADE: price drifted too far from accumulation without a real sweep, re-basing",
                  TimeToString(TimeCurrent(), TIME_MINUTES));
      ResetToWaitForAccumulation();
      return;
     }

   if(high1 > g_accHigh + atr * SweepMinATRmult)
     {
      if(high1 > g_accHigh + atr * MaxSweepATRmult)
        {
         PrintFormat("[%s] NO TRADE: sweep above range too large (trend continuation)", TimeToString(TimeCurrent(), TIME_MINUTES));
         ResetToWaitForAccumulation();
         return;
        }
      g_pursuingShort = true;
      g_sweepExtreme = high1;
      g_sweepBarTime = iTime(_Symbol, StructureTF, 1);
      g_barsWaitedForReclaim = 0;
      DrawLevel("TWIAMD_Sweep", g_sweepExtreme, clrRed);
      PrintFormat("[%s] MANIPULATION: swept above %.5f at %.5f", TimeToString(TimeCurrent(), TIME_MINUTES), g_accHigh, high1);
      g_state = (close1 < g_accHigh) ? WAIT_FOR_IFVG : WAIT_FOR_RECLAIM;
      return;
     }

   if(low1 < g_accLow - atr * SweepMinATRmult)
     {
      if(low1 < g_accLow - atr * MaxSweepATRmult)
        {
         PrintFormat("[%s] NO TRADE: sweep below range too large (trend continuation)", TimeToString(TimeCurrent(), TIME_MINUTES));
         ResetToWaitForAccumulation();
         return;
        }
      g_pursuingShort = false;
      g_sweepExtreme = low1;
      g_sweepBarTime = iTime(_Symbol, StructureTF, 1);
      g_barsWaitedForReclaim = 0;
      DrawLevel("TWIAMD_Sweep", g_sweepExtreme, clrLime);
      PrintFormat("[%s] MANIPULATION: swept below %.5f at %.5f", TimeToString(TimeCurrent(), TIME_MINUTES), g_accLow, low1);
      g_state = (close1 > g_accLow) ? WAIT_FOR_IFVG : WAIT_FOR_RECLAIM;
      return;
     }
  }

void HandleWaitForReclaim()
  {
   g_barsWaitedForReclaim++;
   double close1 = iClose(_Symbol, StructureTF, 1);
   bool reclaimed = g_pursuingShort ? (close1 < g_accHigh) : (close1 > g_accLow);
   if(reclaimed)
     {
      g_state = WAIT_FOR_IFVG;
      return;
     }
   if(g_barsWaitedForReclaim > ReclaimBars)
     {
      PrintFormat("[%s] NO TRADE: no reclaim within %d bars", TimeToString(TimeCurrent(), TIME_MINUTES), ReclaimBars);
      ResetToWaitForAccumulation();
     }
  }

//+------------------------------------------------------------------+
// FVG / IFVG -- same lifecycle model validated in TWI 9AM CR Model EA.
//+------------------------------------------------------------------+
void DetectFVG()
  {
   double atr = CurrentATR();
   if(atr <= 0) return;
   double c1High = iHigh(_Symbol, StructureTF, 3), c1Low = iLow(_Symbol, StructureTF, 3);
   double c3High = iHigh(_Symbol, StructureTF, 1), c3Low = iLow(_Symbol, StructureTF, 1);
   datetime c3Time = iTime(_Symbol, StructureTF, 1);

   if(c3Low > c1High && (c3Low - c1High) >= atr * MinFVGATRmult)
      AddFVG(c1High, c3Low, true, c3Time);
   if(c3High < c1Low && (c1Low - c3High) >= atr * MinFVGATRmult)
      AddFVG(c3High, c1Low, false, c3Time);
  }

void AddFVG(double bottom, double top, bool isBullish, datetime formedTime)
  {
   for(int i = 0; i < ArraySize(g_fvgList); i++)
      if(g_fvgList[i].formedTime == formedTime && g_fvgList[i].isBullish == isBullish)
         return;
   int n = ArraySize(g_fvgList);
   ArrayResize(g_fvgList, n + 1);
   g_fvgList[n].top = top; g_fvgList[n].bottom = bottom; g_fvgList[n].isBullish = isBullish;
   g_fvgList[n].formedTime = formedTime; g_fvgList[n].state = FVG_ACTIVE;
   g_fvgList[n].invertedIsBullish = false; g_fvgList[n].usedForEntry = false;
  }

void DetectIFVG()
  {
   double close1 = iClose(_Symbol, StructureTF, 1);
   datetime cutoff = iTime(_Symbol, StructureTF, 1) - IFVGLookbackBars * PeriodSeconds(StructureTF);

   for(int i = ArraySize(g_fvgList) - 1; i >= 0; i--)
     {
      if(g_fvgList[i].formedTime < cutoff && g_fvgList[i].state != FVG_INVERTED)
        {
         ArrayRemove(g_fvgList, i, 1);
         continue;
        }
      if(g_fvgList[i].state == FVG_ACTIVE)
        {
         bool touched = (close1 <= g_fvgList[i].top && close1 >= g_fvgList[i].bottom);
         if(touched) g_fvgList[i].state = FVG_PARTIALLY_FILLED;
         bool violated = g_fvgList[i].isBullish ? (close1 < g_fvgList[i].bottom) : (close1 > g_fvgList[i].top);
         if(violated)
           {
            g_fvgList[i].state = FVG_INVERTED;
            g_fvgList[i].invertedIsBullish = !g_fvgList[i].isBullish;
           }
        }
      else if(g_fvgList[i].state == FVG_PARTIALLY_FILLED)
        {
         bool violated = g_fvgList[i].isBullish ? (close1 < g_fvgList[i].bottom) : (close1 > g_fvgList[i].top);
         if(violated)
           {
            g_fvgList[i].state = FVG_INVERTED;
            g_fvgList[i].invertedIsBullish = !g_fvgList[i].isBullish;
           }
        }
     }
  }

int FindEntryIFVG()
  {
   bool wantBullish = !g_pursuingShort;
   int best = -1;
   for(int i = 0; i < ArraySize(g_fvgList); i++)
     {
      if(g_fvgList[i].state != FVG_INVERTED) continue;
      if(g_fvgList[i].usedForEntry) continue;
      if(g_fvgList[i].invertedIsBullish != wantBullish) continue;
      if(g_fvgList[i].formedTime < g_sweepBarTime) continue;
      best = i;
     }
   return best;
  }

//+------------------------------------------------------------------+
double CalcLot(double slDistance)
  {
   if(LotMode == LOT_FIXED) return FixedLotSize;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0) return FixedLotSize;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lots = (lossPerLot > 0) ? riskMoney / lossPerLot : FixedLotSize;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

int CountOpenPositions()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
void TryEnter()
  {
   if(g_activeFvgIdx < 0 || g_activeFvgIdx >= ArraySize(g_fvgList))
     {
      g_state = WAIT_FOR_IFVG;
      return;
     }
   FVGZone z = g_fvgList[g_activeFvgIdx];
   double close1 = iClose(_Symbol, StructureTF, 1);
   double mid = (z.top + z.bottom) / 2.0;

   bool confirmed = false;
   switch(EntryMode)
     {
      case IFVG_TOUCH:
         confirmed = true;
         break;
      case IFVG_50_PERCENT:
        {
         double high1 = iHigh(_Symbol, StructureTF, 1), low1 = iLow(_Symbol, StructureTF, 1);
         confirmed = g_pursuingShort ? (high1 >= mid) : (low1 <= mid);
         break;
        }
      case IFVG_REJECTION_CLOSE:
      default:
        {
         double open1 = iOpen(_Symbol, StructureTF, 1);
         bool rejectionCandle = g_pursuingShort ? (close1 < open1) : (close1 > open1);
         bool closedBackOut = g_pursuingShort ? (close1 < z.bottom) : (close1 > z.top);
         confirmed = rejectionCandle && closedBackOut;
         break;
        }
     }

   if(!confirmed)
     {
      if(g_barsWaitedForRetrace > ReclaimBars * 4)
        {
         PrintFormat("[%s] NO TRADE: IFVG never confirmed rejection", TimeToString(TimeCurrent(), TIME_MINUTES));
         ResetToWaitForAccumulation();
        }
      return;
     }

   if(CountOpenPositions() >= MaxConcurrentTrades)
      return;

   double atr = CurrentATR();
   double entry = g_pursuingShort ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double buffer = atr * StopBufferATRmult;
   double sl = g_pursuingShort ? g_sweepExtreme + buffer : g_sweepExtreme - buffer;

   double tp;
   switch(TargetMode)
     {
      case MEASURED_MOVE:
        {
         double rangeSize = g_accHigh - g_accLow;
         tp = g_pursuingShort ? g_sweepExtreme - rangeSize : g_sweepExtreme + rangeSize;
         break;
        }
      case FIXED_RR:
         tp = g_pursuingShort ? entry - MathAbs(entry - sl) * FixedRRTarget : entry + MathAbs(entry - sl) * FixedRRTarget;
         break;
      case OPPOSITE_RANGE:
      default:
         tp = g_pursuingShort ? g_accLow : g_accHigh;
         break;
     }

   double riskDist = MathAbs(entry - sl);
   double rewardDist = MathAbs(tp - entry);
   if(riskDist <= 0) return;
   double rr = rewardDist / riskDist;
   if(rr < MinimumRR)
     {
      PrintFormat("[%s] NO TRADE: RR %.2f below threshold %.2f", TimeToString(TimeCurrent(), TIME_MINUTES), rr, MinimumRR);
      ResetToWaitForAccumulation();
      return;
     }

   double lots = CalcLot(riskDist);
   g_fvgList[g_activeFvgIdx].usedForEntry = true;
   bool ok = g_pursuingShort ? trade.Sell(lots, _Symbol, 0, sl, tp, "TWI AMD iFVG")
                              : trade.Buy(lots, _Symbol, 0, sl, tp, "TWI AMD iFVG");
   if(ok)
     {
      g_activeTicket = trade.ResultOrder();
      PrintFormat("[%s] RR = %.2f", TimeToString(TimeCurrent(), TIME_MINUTES), rr);
      PrintFormat("[%s] %s OPENED @ %.5f SL=%.5f TP=%.5f", TimeToString(TimeCurrent(), TIME_MINUTES),
                  g_pursuingShort ? "SHORT" : "LONG", entry, sl, tp);
      g_state = TRADE_ACTIVE;
     }
  }

//+------------------------------------------------------------------+
void RunStateMachine()
  {
   switch(g_state)
     {
      case WAIT_FOR_ACCUMULATION:
         CheckAccumulation();
         break;
      case ACCUMULATION_LOCKED:
         DetectFVG(); DetectIFVG();
         CheckManipulation();
         break;
      case WAIT_FOR_RECLAIM:
         DetectFVG(); DetectIFVG();
         HandleWaitForReclaim();
         break;
      case WAIT_FOR_IFVG:
        {
         DetectFVG(); DetectIFVG();
         int idx = FindEntryIFVG();
         if(idx >= 0)
           {
            g_activeFvgIdx = idx;
            g_barsWaitedForRetrace = 0;
            g_state = WAIT_FOR_RETRACE;
            PrintFormat("[%s] %s IFVG detected [%.5f-%.5f]", TimeToString(TimeCurrent(), TIME_MINUTES),
                        g_pursuingShort ? "bearish" : "bullish", g_fvgList[idx].bottom, g_fvgList[idx].top);
           }
         break;
        }
      case WAIT_FOR_RETRACE:
        {
         DetectFVG(); DetectIFVG();
         if(g_activeFvgIdx < 0 || g_activeFvgIdx >= ArraySize(g_fvgList)) { g_state = WAIT_FOR_IFVG; return; }
         g_barsWaitedForRetrace++;
         FVGZone z = g_fvgList[g_activeFvgIdx];
         double low1 = iLow(_Symbol, StructureTF, 1), high1 = iHigh(_Symbol, StructureTF, 1);
         bool touched = g_pursuingShort ? (high1 >= z.bottom) : (low1 <= z.top);
         if(touched)
            g_state = WAIT_FOR_ENTRY_CONFIRMATION;
         break;
        }
      case WAIT_FOR_ENTRY_CONFIRMATION:
         TryEnter();
         break;
      case TRADE_ACTIVE:
         if(!PositionSelectByTicket(g_activeTicket))
           {
            g_activeTicket = 0;
            ResetToWaitForAccumulation();
           }
         break;
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   atrHandle = iATR(_Symbol, StructureTF, AtrPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("TWI AMD iFVG EA: failed to create ATR handle");
      return INIT_FAILED;
     }
   ResetToWaitForAccumulation();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   ClearChartObjects();
  }

bool IsNewBar()
  {
   datetime t = iTime(_Symbol, StructureTF, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
  }

void OnTick()
  {
   if(IsNewBar())
      RunStateMachine();
  }
//+------------------------------------------------------------------+
