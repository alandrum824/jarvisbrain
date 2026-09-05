//+------------------------------------------------------------------+
//|                                   TWI 9AM CR Model EA.mq5        |
//|  9AM "Central Range" liquidity-reversal model.                  |
//|                                                                   |
//|  CENTRAL RULE: we are NOT predicting which direction the 9AM     |
//|  session goes. We wait for price to raid one boundary of the     |
//|  completed 8:00-9:00 AM New York H1 candle, then require real    |
//|  evidence the raid failed (displacement + IFVG retrace/reject)   |
//|  before trading toward the OPPOSITE boundary. This is not an     |
//|  opening-range breakout EA -- a break of the 8AM High/Low is     |
//|  never itself a signal, only the first half of a two-sided test. |
//|                                                                   |
//|  Sequence: 8AM H1 range -> 9AM window -> sweep one side -> M1    |
//|  close-back rejection -> M1 displacement -> M1 FVG that later    |
//|  INVERTS against the sweep direction -> retrace into that IFVG   |
//|  -> confirmation -> enter toward the opposite 8AM boundary ->    |
//|  SL beyond the sweep extreme -> TP at the opposite boundary.     |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_EA_STATE
  {
   WAIT_FOR_8AM_RANGE,
   WAIT_FOR_SWEEP,
   HIGH_SWEPT,
   LOW_SWEPT,
   WAIT_FOR_DISPLACEMENT,
   WAIT_FOR_IFVG,
   WAIT_FOR_RETRACE,
   WAIT_FOR_ENTRY_CONFIRMATION,
   TRADE_ACTIVE,
   DAY_COMPLETE
  };

enum ENUM_ENTRY_MODE
  {
   IFVG_TOUCH,
   IFVG_50_PERCENT,
   IFVG_REJECTION_CLOSE,
   DISPLACEMENT_CLOSE
  };

enum ENUM_TARGET_MODE
  {
   OPPOSITE_8AM_RANGE,
   FIXED_RR,
   NEAREST_LIQUIDITY
  };

enum ENUM_MGMT_MODE
  {
   FULL_TP,
   BE_AT_1R,
   PARTIAL_AT_1R,
   STRUCTURE_TRAIL
  };

enum ENUM_SESSION_TZ
  {
   NEW_YORK
  };

enum ENUM_FVG_STATE
  {
   FVG_ACTIVE,
   FVG_PARTIALLY_FILLED,
   FVG_MITIGATED,
   FVG_INVALIDATED,
   FVG_INVERTED
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== General ==="
input long              MagicNumber                 = 20260902;
input ENUM_SESSION_TZ   SessionTimeMode             = NEW_YORK;

input group "=== Timezone ==="
input int               BrokerGMTOffset             = 2;      // broker server time minus UTC, in whole hours -- SET THIS FOR YOUR BROKER
input bool               AutoDetectDST               = true;    // auto-apply US DST (2nd Sun Mar - 1st Sun Nov) for New York's UTC offset
input int               ManualNYOffsetHours         = -5;      // used only when AutoDetectDST = false (EST=-5, EDT=-4)

input group "=== Session Window (New York time) ==="
input int               TradingStartHour            = 9;
input int               TradingStartMinute          = 0;
input int               TradingEndHour              = 11;
input int               TradingEndMinute            = 30;
input bool               CloseAtSessionEnd           = false;

input group "=== Sweep Validation ==="
input double             MinimumSweepPoints          = 20;      // min points beyond the 8AM level to count as a real sweep
input double             MaximumSweepDistance        = 150;     // max points beyond the level before the sweep looks like a runaway breakout
input bool               RequireCloseBackInsideRange = true;
input int                SweepConfirmationCandles    = 3;       // M1 bars allowed to wait for the close-back-inside confirmation
input bool               AllowDisplacementWithoutImmediateReclaim = false;
input double             MaximumSweepATR             = 2.0;     // invalidate if sweep travels beyond this many M1-ATR past the level

input group "=== Displacement ==="
input double             DisplacementBodyMultiplier  = 1.5;
input int                DisplacementLookback        = 10;      // bars averaged for the "normal" M1 body size
input double             MinDisplacementPoints        = 30;      // absolute floor on displacement body size, in points

input group "=== FVG / IFVG ==="
input double             MinFVGPoints                = 10;
input int                IFVGLookbackBars            = 30;

input group "=== Entry ==="
input ENUM_ENTRY_MODE    EntryMode                   = IFVG_REJECTION_CLOSE;
input ENUM_TARGET_MODE   TargetMode                  = OPPOSITE_8AM_RANGE;
input double              FixedRRTarget               = 3.0;     // used only when TargetMode = FIXED_RR
input double             StopBufferPoints            = 20;
input double              MinimumRR                   = 2.0;

input group "=== Setup Quality ==="
input double              MinimumSetupScore           = 70;

input group "=== Risk / Lot Sizing ==="
input double              RiskPercent                 = 0.50;
input bool                UseFixedLot                 = false;
input double              FixedLot                    = 0.01;

input group "=== Daily Protection ==="
input double              MaxDailyLossPercent         = 2.0;
input int                 MaxDailyTrades              = 2;
input int                 MaxLossesPerDay             = 2;
input double              StopAfterDailyProfitPercent = 0;       // 0 = disabled
input double              MaximumOpenRiskPercent      = 1.0;

input group "=== One-Side / Second-Side Logic ==="
input int                 MaximumTradesPer8AMSide     = 1;
input bool                AllowOppositeSideTradeAfterLoss = false;

input group "=== 8AM Range Filter ==="
input bool                Use8AMRangeFilter           = false;
input double              Minimum8AMRangePoints       = 50;
input double              Maximum8AMRangePoints       = 500;
input bool                UseATRRelativeRangeFilter   = false;

input group "=== News Filter (optional) ==="
input bool                UseNewsFilter               = false;
input int                 MinutesBeforeHighImpactNews = 15;
input int                 MinutesAfterHighImpactNews  = 15;

input group "=== Trade Management ==="
input ENUM_MGMT_MODE      ManagementMode              = FULL_TP;
input double              PartialClosePercent         = 50;      // used only when ManagementMode = PARTIAL_AT_1R

input group "=== Display ==="
input bool                ShowDashboard               = true;
input bool                ShowZonesOnChart            = true;

//====================================================================
// STRUCTS
//====================================================================
struct FVGZone
  {
   double            top;
   double            bottom;
   bool              isBullish;          // original bias when formed
   datetime          formedTime;
   ENUM_FVG_STATE    state;
   bool              invertedIsBullish;  // role after inversion (opposite of original bias)
   bool              usedForEntry;
   string            objTop;
   string            objBottom;
  };

//====================================================================
// GLOBAL STATE
//====================================================================
FVGZone   g_fvgList[];

ENUM_EA_STATE g_state = WAIT_FOR_8AM_RANGE;

double    g_8amHigh = 0, g_8amLow = 0, g_8amRange = 0;
datetime  g_currentNYDay = 0;          // NY-midnight marker for the active trading day
bool      g_rangeLocked = false;

bool      g_pursuingShort = false;     // true = high swept, pursuing short; false = low swept, pursuing long
double    g_sweepExtreme = 0;          // SweepHigh or SweepLow
datetime  g_sweepBarTime = 0;
int       g_barsWaitedForReclaim = 0;

int       g_activeFvgIdx = -1;         // index into g_fvgList of the IFVG we're tracking for entry
int       g_barsWaitedForRetrace = 0;

double    g_setupScore = 0;
double    g_lastRR = 0;

int       g_tradesHighSide = 0, g_tradesLowSide = 0;
bool      g_highSideLossOccurred = false, g_lowSideLossOccurred = false;
int       g_tradesToday = 0;
int       g_lossesToday = 0;
double    g_dailyStartEquity = 0;
double    g_dailyPL = 0;
bool      g_dailyHalted = false;
string    g_haltReason = "";

datetime  g_lastM1BarTime = 0;
int       g_atrHandleM1 = INVALID_HANDLE;

ulong     g_activeTicket = 0;
double    g_activeEntry = 0, g_activeSL = 0, g_activeTP = 0, g_activeRiskDistance = 0;
bool      g_beMoved = false;
bool      g_partialDone = false;

string    g_statusText = "Waiting for 8AM range";

//+------------------------------------------------------------------+
//| TIMEZONE                                                          |
//+------------------------------------------------------------------+
// All strategy decisions run on New York wall-clock time, independent
// of the broker's own server timezone. Two inputs bridge the gap:
//   BrokerGMTOffset  -- whole hours the broker's server clock sits
//                       ahead of UTC (set once for your broker).
//   AutoDetectDST    -- when true, New York's own UTC offset flips
//                       automatically between -5 (EST) and -4 (EDT)
//                       using the real US DST rule (2nd Sunday of
//                       March 02:00 -> 1st Sunday of November 02:00);
//                       when false, ManualNYOffsetHours is used as-is.
// Internally every "NY time" value in this EA is a normal MQL5
// datetime whose Y/M/D/H/M/S fields, when read back with
// TimeToStruct(), are the New York wall-clock fields -- it is only
// ever converted back to a real broker datetime right before touching
// any MT5 API (iTime/iBarShift/TimeCurrent comparisons).
//+------------------------------------------------------------------+
bool IsUSDST(datetime utcTime)
  {
   MqlDateTime t; TimeToStruct(utcTime, t);
   int year = t.year;

   // 2nd Sunday of March, 02:00 UTC-ish (close enough for H1/M1 strategy purposes)
   MqlDateTime marchStart; marchStart.year=year; marchStart.mon=3; marchStart.day=1;
   marchStart.hour=0; marchStart.min=0; marchStart.sec=0;
   datetime march1 = StructToTime(marchStart);
   MqlDateTime m1s; TimeToStruct(march1, m1s);
   int firstSundayMarch = 1 + ((7 - m1s.day_of_week) % 7);
   int secondSundayMarch = firstSundayMarch + 7;
   MqlDateTime dstStart; dstStart.year=year; dstStart.mon=3; dstStart.day=secondSundayMarch;
   dstStart.hour=7; dstStart.min=0; dstStart.sec=0; // 2:00 AM ET = 07:00 UTC (EST)
   datetime dstStartTime = StructToTime(dstStart);

   // 1st Sunday of November
   MqlDateTime novStart; novStart.year=year; novStart.mon=11; novStart.day=1;
   novStart.hour=0; novStart.min=0; novStart.sec=0;
   datetime nov1 = StructToTime(novStart);
   MqlDateTime n1s; TimeToStruct(nov1, n1s);
   int firstSundayNov = 1 + ((7 - n1s.day_of_week) % 7);
   MqlDateTime dstEnd; dstEnd.year=year; dstEnd.mon=11; dstEnd.day=firstSundayNov;
   dstEnd.hour=6; dstEnd.min=0; dstEnd.sec=0; // 2:00 AM ET = 06:00 UTC (EDT)
   datetime dstEndTime = StructToTime(dstEnd);

   return (utcTime >= dstStartTime && utcTime < dstEndTime);
  }

int NYOffsetHours(datetime utcTime)
  {
   if(!AutoDetectDST)
      return ManualNYOffsetHours;
   return IsUSDST(utcTime) ? -4 : -5;
  }

datetime BrokerToUTC(datetime brokerTime) { return brokerTime - BrokerGMTOffset * 3600; }
datetime UTCToBroker(datetime utcTime)    { return utcTime + BrokerGMTOffset * 3600; }

datetime UTCToNYRepr(datetime utcTime)
  {
   return utcTime + NYOffsetHours(utcTime) * 3600;
  }
datetime NYReprToUTC(datetime nyRepr)
  {
   // NYOffsetHours needs a UTC time to evaluate DST; approximate using nyRepr
   // itself (off by at most the DST offset magnitude, irrelevant for the
   // date-boundary math this is used for).
   return nyRepr - NYOffsetHours(nyRepr) * 3600;
  }

datetime GetNewYorkTime()
  {
   datetime utcNow = BrokerToUTC(TimeCurrent());
   return UTCToNYRepr(utcNow);
  }

//+------------------------------------------------------------------+
//| Returns today's NY 08:00:00 and 09:00:00 expressed as real broker |
//| datetimes, for use with iBarShift/iTime.                         |
//+------------------------------------------------------------------+
void GetNY8to9WindowBrokerTime(datetime &brokerStart, datetime &brokerEnd)
  {
   datetime nyNow = GetNewYorkTime();
   MqlDateTime nyStruct; TimeToStruct(nyNow, nyStruct);
   nyStruct.hour = 8; nyStruct.min = 0; nyStruct.sec = 0;
   datetime ny8 = StructToTime(nyStruct);
   datetime ny9 = ny8 + 3600;

   brokerStart = UTCToBroker(NYReprToUTC(ny8));
   brokerEnd   = UTCToBroker(NYReprToUTC(ny9));
  }

datetime GetNYMidnightMarker()
  {
   datetime nyNow = GetNewYorkTime();
   MqlDateTime s; TimeToStruct(nyNow, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
  }

//+------------------------------------------------------------------+
//| DAILY RESET                                                       |
//+------------------------------------------------------------------+
void ResetDailyState()
  {
   g_state = WAIT_FOR_8AM_RANGE;
   g_8amHigh = 0; g_8amLow = 0; g_8amRange = 0;
   g_rangeLocked = false;
   g_pursuingShort = false;
   g_sweepExtreme = 0; g_sweepBarTime = 0; g_barsWaitedForReclaim = 0;
   g_activeFvgIdx = -1; g_barsWaitedForRetrace = 0;
   g_setupScore = 0; g_lastRR = 0;
   g_tradesHighSide = 0; g_tradesLowSide = 0;
   g_highSideLossOccurred = false; g_lowSideLossOccurred = false;
   g_tradesToday = 0; g_lossesToday = 0;
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyPL = 0;
   g_dailyHalted = false; g_haltReason = "";
   ArrayResize(g_fvgList, 0);
   ClearChartObjects();
   g_statusText = "Waiting for 8AM range";
   PrintFormat("[%s] ---- New trading day, state reset ----", TimeToString(GetNewYorkTime(), TIME_MINUTES));
  }

void ClearChartObjects()
  {
   ObjectsDeleteAll(0, "TWI9AM_");
  }

//+------------------------------------------------------------------+
//| Build8AMRange -- locks the completed 8-9AM NY H1 candle           |
//+------------------------------------------------------------------+
bool Build8AMRange()
  {
   datetime brokerStart, brokerEnd;
   GetNY8to9WindowBrokerTime(brokerStart, brokerEnd);

   int shift = iBarShift(_Symbol, PERIOD_H1, brokerStart, false);
   if(shift < 0)
      return false;

   datetime barTime = iTime(_Symbol, PERIOD_H1, shift);
   if(MathAbs((long)barTime - (long)brokerStart) > 1800) // more than 30 min off -> bad alignment
     {
      Print("TWI 9AM CR Model: WARNING - H1 bar alignment off by more than 30min, check BrokerGMTOffset");
     }

   // Only proceed once that H1 bar is fully closed, i.e. the NEXT H1 bar exists
   if(iTime(_Symbol, PERIOD_H1, 0) < brokerEnd)
      return false;

   g_8amHigh = iHigh(_Symbol, PERIOD_H1, shift);
   g_8amLow  = iLow(_Symbol, PERIOD_H1, shift);
   g_8amRange = g_8amHigh - g_8amLow;

   if(Use8AMRangeFilter)
     {
      double rangePoints = g_8amRange / _Point;
      if(rangePoints < Minimum8AMRangePoints || rangePoints > Maximum8AMRangePoints)
        {
         PrintFormat("[%s] NO TRADE: 8AM range %.1f points outside filter [%.1f,%.1f]",
                     TimeToString(GetNewYorkTime(), TIME_MINUTES), rangePoints, Minimum8AMRangePoints, Maximum8AMRangePoints);
         g_state = DAY_COMPLETE;
         g_statusText = "8AM range filtered out for today";
         return false;
        }
     }

   g_rangeLocked = true;
   DrawLevel("TWI9AM_High", g_8amHigh, clrDodgerBlue);
   DrawLevel("TWI9AM_Low", g_8amLow, clrOrangeRed);

   PrintFormat("[%s] 8AM range locked: High=%.5f Low=%.5f Range=%.1f pts",
               TimeToString(GetNewYorkTime(), TIME_MINUTES), g_8amHigh, g_8amLow, g_8amRange / _Point);
   g_statusText = "8AM range locked, waiting for sweep";
   return true;
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
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
  }

//+------------------------------------------------------------------+
//| ATR helper (M1)                                                   |
//+------------------------------------------------------------------+
double GetM1ATR()
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandleM1, 0, 1, 1, buf) <= 0)
      return 0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| DetectHighSweep / DetectLowSweep                                  |
//| Only run on a newly-closed M1 bar. Reference shift 1 (the bar     |
//| that just closed) -- never the still-forming bar 0.               |
//+------------------------------------------------------------------+
void DetectHighSweep()
  {
   double high1 = iHigh(_Symbol, PERIOD_M1, 1);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);

   if(high1 <= g_8amHigh + MinimumSweepPoints * _Point)
      return; // no real sweep yet

   double sweepDist = (high1 - g_8amHigh) / _Point;
   double atr = GetM1ATR();
   if(sweepDist > MaximumSweepDistance)
     {
      PrintFormat("[%s] NO TRADE: sweep too large (%.1f pts > max %.1f)",
                  TimeToString(GetNewYorkTime(), TIME_MINUTES), sweepDist, MaximumSweepDistance);
      g_state = DAY_COMPLETE;
      return;
     }
   if(atr > 0 && (high1 - g_8amHigh) > atr * MaximumSweepATR)
     {
      PrintFormat("[%s] NO TRADE: sweep exceeds %.1fx M1 ATR", TimeToString(GetNewYorkTime(), TIME_MINUTES), MaximumSweepATR);
      g_state = DAY_COMPLETE;
      return;
     }

   g_sweepExtreme = high1;
   g_sweepBarTime = iTime(_Symbol, PERIOD_M1, 1);
   g_pursuingShort = true;
   g_state = HIGH_SWEPT;
   g_barsWaitedForReclaim = 0;
   DrawLevel("TWI9AM_SweepHigh", g_sweepExtreme, clrRed);
   PrintFormat("[%s] 8AM HIGH SWEPT at %.5f (%.1f pts)", TimeToString(GetNewYorkTime(), TIME_MINUTES), high1, sweepDist);

   if(!RequireCloseBackInsideRange || close1 < g_8amHigh)
     {
      g_state = WAIT_FOR_DISPLACEMENT;
      PrintFormat("[%s] close returned below 8AM high", TimeToString(GetNewYorkTime(), TIME_MINUTES));
     }
  }

void DetectLowSweep()
  {
   double low1 = iLow(_Symbol, PERIOD_M1, 1);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);

   if(low1 >= g_8amLow - MinimumSweepPoints * _Point)
      return;

   double sweepDist = (g_8amLow - low1) / _Point;
   double atr = GetM1ATR();
   if(sweepDist > MaximumSweepDistance)
     {
      PrintFormat("[%s] NO TRADE: sweep too large (%.1f pts > max %.1f)",
                  TimeToString(GetNewYorkTime(), TIME_MINUTES), sweepDist, MaximumSweepDistance);
      g_state = DAY_COMPLETE;
      return;
     }
   if(atr > 0 && (g_8amLow - low1) > atr * MaximumSweepATR)
     {
      PrintFormat("[%s] NO TRADE: sweep exceeds %.1fx M1 ATR", TimeToString(GetNewYorkTime(), TIME_MINUTES), MaximumSweepATR);
      g_state = DAY_COMPLETE;
      return;
     }

   g_sweepExtreme = low1;
   g_sweepBarTime = iTime(_Symbol, PERIOD_M1, 1);
   g_pursuingShort = false;
   g_state = LOW_SWEPT;
   g_barsWaitedForReclaim = 0;
   DrawLevel("TWI9AM_SweepLow", g_sweepExtreme, clrLime);
   PrintFormat("[%s] 8AM LOW SWEPT at %.5f (%.1f pts)", TimeToString(GetNewYorkTime(), TIME_MINUTES), low1, sweepDist);

   if(!RequireCloseBackInsideRange || close1 > g_8amLow)
     {
      g_state = WAIT_FOR_DISPLACEMENT;
      PrintFormat("[%s] close returned above 8AM low", TimeToString(GetNewYorkTime(), TIME_MINUTES));
     }
  }

//+------------------------------------------------------------------+
//| Handles the HIGH_SWEPT / LOW_SWEPT waiting-for-reclaim states     |
//+------------------------------------------------------------------+
void HandleSweptWaiting()
  {
   g_barsWaitedForReclaim++;
   double close1 = iClose(_Symbol, PERIOD_M1, 1);

   bool reclaimed;
   if(g_pursuingShort)
      reclaimed = (close1 < g_8amHigh);
   else
      reclaimed = (close1 > g_8amLow);

   if(reclaimed)
     {
      g_state = WAIT_FOR_DISPLACEMENT;
      PrintFormat("[%s] close returned back inside range", TimeToString(GetNewYorkTime(), TIME_MINUTES));
      return;
     }

   if(g_barsWaitedForReclaim > SweepConfirmationCandles)
     {
      if(AllowDisplacementWithoutImmediateReclaim)
        {
         g_state = WAIT_FOR_DISPLACEMENT;
         PrintFormat("[%s] no immediate reclaim, proceeding anyway (AllowDisplacementWithoutImmediateReclaim)",
                     TimeToString(GetNewYorkTime(), TIME_MINUTES));
        }
      else
        {
         PrintFormat("[%s] NO TRADE: no reclaim within %d bars, abandoning this side",
                     TimeToString(GetNewYorkTime(), TIME_MINUTES), SweepConfirmationCandles);
         g_state = WAIT_FOR_SWEEP; // allow the opposite side to still set up if it hasn't yet
        }
     }
  }

//+------------------------------------------------------------------+
//| DetectDisplacement                                                 |
//+------------------------------------------------------------------+
bool DetectDisplacement(bool bearish)
  {
   double sumBody = 0;
   for(int i = 2; i <= DisplacementLookback + 1; i++)
      sumBody += MathAbs(iClose(_Symbol, PERIOD_M1, i) - iOpen(_Symbol, PERIOD_M1, i));
   double avgBody = sumBody / DisplacementLookback;

   double body1 = MathAbs(iClose(_Symbol, PERIOD_M1, 1) - iOpen(_Symbol, PERIOD_M1, 1));
   bool directionOK = bearish ? (iClose(_Symbol, PERIOD_M1, 1) < iOpen(_Symbol, PERIOD_M1, 1))
                               : (iClose(_Symbol, PERIOD_M1, 1) > iOpen(_Symbol, PERIOD_M1, 1));
   if(!directionOK)
      return false;

   bool sizeOK = (body1 >= avgBody * DisplacementBodyMultiplier) && (body1 / _Point >= MinDisplacementPoints);
   return sizeOK;
  }

//+------------------------------------------------------------------+
//| FVG DETECTION                                                     |
//| Candle1 = shift3 (oldest), Candle2 = shift2, Candle3 = shift1     |
//| (most recently closed). Only ever reads closed bars (shift>=1).   |
//+------------------------------------------------------------------+
void DetectFVG()
  {
   double c1High = iHigh(_Symbol, PERIOD_M1, 3), c1Low = iLow(_Symbol, PERIOD_M1, 3);
   double c3High = iHigh(_Symbol, PERIOD_M1, 1), c3Low = iLow(_Symbol, PERIOD_M1, 1);
   datetime c3Time = iTime(_Symbol, PERIOD_M1, 1);

   // Bullish FVG: Candle3 Low > Candle1 High. Zone: Candle1 High -> Candle3 Low
   if(c3Low > c1High)
     {
      double gapPts = (c3Low - c1High) / _Point;
      if(gapPts >= MinFVGPoints)
         AddFVG(c1High, c3Low, true, c3Time);
     }
   // Bearish FVG: Candle3 High < Candle1 Low. Zone: Candle3 High -> Candle1 Low
   if(c3High < c1Low)
     {
      double gapPts = (c1Low - c3High) / _Point;
      if(gapPts >= MinFVGPoints)
         AddFVG(c3High, c1Low, false, c3Time);
     }
  }

void AddFVG(double bottom, double top, bool isBullish, datetime formedTime)
  {
   // avoid duplicate adds for the same bar
   for(int i = 0; i < ArraySize(g_fvgList); i++)
      if(g_fvgList[i].formedTime == formedTime && g_fvgList[i].isBullish == isBullish)
         return;

   int n = ArraySize(g_fvgList);
   ArrayResize(g_fvgList, n + 1);
   g_fvgList[n].top = top;
   g_fvgList[n].bottom = bottom;
   g_fvgList[n].isBullish = isBullish;
   g_fvgList[n].formedTime = formedTime;
   g_fvgList[n].state = FVG_ACTIVE;
   g_fvgList[n].invertedIsBullish = false;
   g_fvgList[n].usedForEntry = false;
   g_fvgList[n].objTop = "";
   g_fvgList[n].objBottom = "";

   if(ShowZonesOnChart && !MQLInfoInteger(MQL_TESTER))
     {
      string boxName = StringFormat("TWI9AM_FVG_%d", (int)formedTime);
      color c = isBullish ? clrTeal : clrMaroon;
      ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, formedTime, top, formedTime + PeriodSeconds(PERIOD_M1) * 20, bottom);
      ObjectSetInteger(0, boxName, OBJPROP_COLOR, c);
      ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
      ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
      g_fvgList[n].objTop = boxName;
     }
  }

//+------------------------------------------------------------------+
//| DetectIFVG -- updates lifecycle state of every tracked FVG on     |
//| each new closed M1 bar, and prunes anything older than the        |
//| lookback window.                                                  |
//+------------------------------------------------------------------+
void DetectIFVG()
  {
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   datetime cutoff = iTime(_Symbol, PERIOD_M1, 1) - IFVGLookbackBars * PeriodSeconds(PERIOD_M1);

   for(int i = ArraySize(g_fvgList) - 1; i >= 0; i--)
     {
      if(g_fvgList[i].formedTime < cutoff && g_fvgList[i].state != FVG_INVERTED)
        {
         if(g_fvgList[i].objTop != "") ObjectDelete(0, g_fvgList[i].objTop);
         ArrayRemove(g_fvgList, i, 1);
         continue;
        }

      if(g_fvgList[i].state == FVG_ACTIVE || g_fvgList[i].state == FVG_PARTIALLY_FILLED)
        {
         bool touchedInside = (close1 <= g_fvgList[i].top && close1 >= g_fvgList[i].bottom);
         if(touchedInside)
            g_fvgList[i].state = FVG_PARTIALLY_FILLED;

         bool violated = g_fvgList[i].isBullish ? (close1 < g_fvgList[i].bottom)
                                                 : (close1 > g_fvgList[i].top);
         if(violated)
           {
            g_fvgList[i].state = FVG_INVERTED;
            g_fvgList[i].invertedIsBullish = !g_fvgList[i].isBullish;
            PrintFormat("[%s] FVG formed %s inverted -> now %s IFVG [%.5f-%.5f]",
                        TimeToString(GetNewYorkTime(), TIME_MINUTES),
                        TimeToString(g_fvgList[i].formedTime, TIME_MINUTES),
                        g_fvgList[i].invertedIsBullish ? "BULLISH" : "BEARISH",
                        g_fvgList[i].bottom, g_fvgList[i].top);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Find the most recent IFVG matching the direction we need (formed  |
//| after the sweep bar), not yet used for an entry.                  |
//+------------------------------------------------------------------+
int FindEntryIFVG()
  {
   bool wantBullish = !g_pursuingShort; // short needs a bearish IFVG (resistance), long needs bullish (support)
   int best = -1;
   for(int i = 0; i < ArraySize(g_fvgList); i++)
     {
      if(g_fvgList[i].state != FVG_INVERTED) continue;
      if(g_fvgList[i].usedForEntry) continue;
      if(g_fvgList[i].invertedIsBullish != wantBullish) continue;
      if(g_fvgList[i].formedTime < g_sweepBarTime) continue; // must relate to the reversal, not stale session noise
      best = i; // keep latest match
     }
   return best;
  }

//+------------------------------------------------------------------+
//| CalculateSetupScore                                                |
//+------------------------------------------------------------------+
double CalculateSetupScore(bool closedBackInside, bool strongDisplacement, bool cleanIFVG, bool retested, double rr)
  {
   double score = 0;
   score += 25; // a valid sweep already occurred to reach this point
   if(closedBackInside) score += 15;
   if(strongDisplacement) score += 20;
   if(cleanIFVG) score += 20;
   if(retested) score += 15;
   if(rr >= MinimumRR * 1.5) score += 5; // strong R:R bonus
   return score;
  }

//+------------------------------------------------------------------+
//| CalculatePositionSize                                              |
//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
  {
   if(UseFixedLot)
      return FixedLot;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0)
      return FixedLot;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lots = (lossPerLot > 0) ? riskMoney / lossPerLot : FixedLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

//+------------------------------------------------------------------+
//| ValidateRiskReward                                                  |
//+------------------------------------------------------------------+
bool ValidateRiskReward(double entry, double sl, double tp, double &rrOut)
  {
   double riskDist = MathAbs(entry - sl);
   double rewardDist = MathAbs(tp - entry);
   if(riskDist <= 0) { rrOut = 0; return false; }
   rrOut = rewardDist / riskDist;
   return (rrOut >= MinimumRR);
  }

//+------------------------------------------------------------------+
//| Daily protection checks                                            |
//+------------------------------------------------------------------+
bool DailyLimitsOK()
  {
   if(g_dailyHalted)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPct = (g_dailyStartEquity > 0) ? (g_dailyStartEquity - equity) / g_dailyStartEquity * 100.0 : 0;
   if(dailyLossPct >= MaxDailyLossPercent)
     {
      g_dailyHalted = true; g_haltReason = "Max daily loss reached";
      return false;
     }
   if(StopAfterDailyProfitPercent > 0)
     {
      double dailyProfitPct = (g_dailyStartEquity > 0) ? (equity - g_dailyStartEquity) / g_dailyStartEquity * 100.0 : 0;
      if(dailyProfitPct >= StopAfterDailyProfitPercent)
        {
         g_dailyHalted = true; g_haltReason = "Daily profit target reached";
         return false;
        }
     }
   if(g_tradesToday >= MaxDailyTrades)
     {
      g_dailyHalted = true; g_haltReason = "Max daily trades reached";
      return false;
     }
   if(g_lossesToday >= MaxLossesPerDay)
     {
      g_dailyHalted = true; g_haltReason = "Max daily losses reached";
      return false;
     }
   return true;
  }

bool SideLimitOK()
  {
   int tradesThisSide = g_pursuingShort ? g_tradesHighSide : g_tradesLowSide;
   bool lossThisSide   = g_pursuingShort ? g_highSideLossOccurred : g_lowSideLossOccurred;
   bool lossOtherSide  = g_pursuingShort ? g_lowSideLossOccurred : g_highSideLossOccurred;

   if(tradesThisSide >= MaximumTradesPer8AMSide)
      return false;

   // If the OTHER side already lost and flipping isn't allowed, block this side too
   if(lossOtherSide && !AllowOppositeSideTradeAfterLoss)
      return false;

   return true;
  }

bool InTradingWindow()
  {
   datetime ny = GetNewYorkTime();
   MqlDateTime s; TimeToStruct(ny, s);
   int nowMin = s.hour * 60 + s.min;
   int startMin = TradingStartHour * 60 + TradingStartMinute;
   int endMin = TradingEndHour * 60 + TradingEndMinute;
   return (nowMin >= startMin && nowMin <= endMin);
  }

//+------------------------------------------------------------------+
//| News filter -- graceful degrade if calendar API unavailable       |
//+------------------------------------------------------------------+
bool NewsBlocking()
  {
   if(!UseNewsFilter)
      return false;

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - MinutesBeforeHighImpactNews * 60;
   datetime to   = TimeCurrent() + MinutesAfterHighImpactNews * 60;
   int got = CalendarValueHistory(values, from, to, "US");
   if(got < 0)
      return false; // calendar unavailable -- fail gracefully, don't block trading

   for(int i = 0; i < got; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| ExecuteTrade                                                        |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isShort, double entry, double sl, double tp, double rr, double score)
  {
   double lots = CalculatePositionSize(MathAbs(entry - sl));

   bool ok;
   if(isShort)
      ok = trade.Sell(lots, _Symbol, 0, sl, tp, "TWI9AM CR");
   else
      ok = trade.Buy(lots, _Symbol, 0, sl, tp, "TWI9AM CR");

   if(!ok)
     {
      PrintFormat("[%s] Order failed, retcode=%d", TimeToString(GetNewYorkTime(), TIME_MINUTES), trade.ResultRetcode());
      return;
     }

   g_activeTicket = trade.ResultOrder();
   g_activeEntry = entry; g_activeSL = sl; g_activeTP = tp;
   g_activeRiskDistance = MathAbs(entry - sl);
   g_beMoved = false; g_partialDone = false;

   if(isShort) g_tradesHighSide++; else g_tradesLowSide++;
   g_tradesToday++;

   PrintFormat("[%s] setup score = %.0f", TimeToString(GetNewYorkTime(), TIME_MINUTES), score);
   PrintFormat("[%s] RR = %.2f", TimeToString(GetNewYorkTime(), TIME_MINUTES), rr);
   PrintFormat("[%s] %s OPENED @ %.5f  SL=%.5f  TP=%.5f", TimeToString(GetNewYorkTime(), TIME_MINUTES),
               isShort ? "SHORT" : "LONG", entry, sl, tp);

   g_state = TRADE_ACTIVE;
   g_statusText = isShort ? "SHORT active, managing to TP" : "LONG active, managing to TP";
  }

//+------------------------------------------------------------------+
//| ManagePosition                                                      |
//+------------------------------------------------------------------+
void ManagePosition()
  {
   if(!PositionSelectByTicket(g_activeTicket))
     {
      // position closed (TP/SL hit or manually) -- record outcome and finish the day
      HandleTradeClosed();
      return;
     }

   if(ManagementMode == FULL_TP)
      return;

   double curPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY
                      ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double rMultiple = isBuy ? (curPrice - g_activeEntry) / g_activeRiskDistance
                             : (g_activeEntry - curPrice) / g_activeRiskDistance;

   if((ManagementMode == BE_AT_1R || ManagementMode == PARTIAL_AT_1R) && !g_beMoved && rMultiple >= 1.0)
     {
      trade.PositionModify(g_activeTicket, g_activeEntry, g_activeTP);
      g_beMoved = true;
      Print("Moved SL to breakeven at +1R");
     }

   if(ManagementMode == PARTIAL_AT_1R && !g_partialDone && rMultiple >= 1.0)
     {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double closeVol = NormalizeDouble(vol * (PartialClosePercent / 100.0), 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(closeVol >= minLot && closeVol < vol)
        {
         trade.PositionClosePartial(g_activeTicket, closeVol);
         g_partialDone = true;
         Print("Partial close at +1R done");
        }
     }

   if(ManagementMode == STRUCTURE_TRAIL && rMultiple >= 2.0)
     {
      double structLevel = isBuy ? iLow(_Symbol, PERIOD_M1, 1) : iHigh(_Symbol, PERIOD_M1, 1);
      double buffer = StopBufferPoints * _Point;
      double newSL = isBuy ? structLevel - buffer : structLevel + buffer;
      bool improves = isBuy ? (newSL > PositionGetDouble(POSITION_SL)) : (newSL < PositionGetDouble(POSITION_SL));
      if(improves)
         trade.PositionModify(g_activeTicket, newSL, g_activeTP);
     }
  }

void HandleTradeClosed()
  {
   // Pull the closing deal's profit from history for this ticket's order id
   if(HistorySelectByPosition(g_activeTicket))
     {
      int deals = HistoryDealsTotal();
      double profit = 0;
      for(int i = 0; i < deals; i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         profit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
        }
      g_dailyPL += profit;
      if(profit < 0)
        {
         g_lossesToday++;
         if(g_pursuingShort) g_highSideLossOccurred = true; else g_lowSideLossOccurred = true;
        }
     }
   g_activeTicket = 0;
   g_state = DAY_COMPLETE;
   g_statusText = "Trade closed, day complete";
  }

//+------------------------------------------------------------------+
//| STATE MACHINE DRIVER -- runs once per newly-closed M1 bar         |
//+------------------------------------------------------------------+
void RunStateMachine()
  {
   if(g_state == TRADE_ACTIVE)
      return; // handled every tick in OnTick, not here

   if(g_state == DAY_COMPLETE)
      return;

   if(!DailyLimitsOK())
     {
      g_state = DAY_COMPLETE;
      g_statusText = "Halted: " + g_haltReason;
      return;
     }

   bool pastWindow = !InTradingWindow() && GetNewYorkTime() > 0; // past end of window
   MqlDateTime s; TimeToStruct(GetNewYorkTime(), s);
   int nowMin = s.hour * 60 + s.min;
   int endMin = TradingEndHour * 60 + TradingEndMinute;
   bool sessionEnded = (nowMin > endMin);

   switch(g_state)
     {
      case WAIT_FOR_8AM_RANGE:
        {
         if(s.hour < 9) return; // range not ready to lock yet
         if(!Build8AMRange()) return;
         g_state = WAIT_FOR_SWEEP;
         break;
        }

      case WAIT_FOR_SWEEP:
        {
         if(sessionEnded) { g_state = DAY_COMPLETE; g_statusText = "Session ended, no sweep"; return; }
         DetectFVG(); DetectIFVG();
         DetectHighSweep();
         if(g_state == WAIT_FOR_SWEEP) DetectLowSweep();
         break;
        }

      case HIGH_SWEPT:
      case LOW_SWEPT:
        {
         DetectFVG(); DetectIFVG();
         HandleSweptWaiting();
         break;
        }

      case WAIT_FOR_DISPLACEMENT:
        {
         DetectFVG(); DetectIFVG();
         if(sessionEnded) { g_state = DAY_COMPLETE; g_statusText = "Session ended waiting for displacement"; return; }
         bool disp = DetectDisplacement(g_pursuingShort);
         if(disp)
           {
            PrintFormat("[%s] %s displacement confirmed", TimeToString(GetNewYorkTime(), TIME_MINUTES),
                        g_pursuingShort ? "bearish" : "bullish");
            if(EntryMode == DISPLACEMENT_CLOSE)
              {
               TryEnterFromDisplacement();
              }
            else
              {
               g_state = WAIT_FOR_IFVG;
              }
           }
         else
           {
            PrintFormat("[%s] NO TRADE: weak displacement", TimeToString(GetNewYorkTime(), TIME_MINUTES));
           }
         break;
        }

      case WAIT_FOR_IFVG:
        {
         DetectFVG(); DetectIFVG();
         if(sessionEnded) { g_state = DAY_COMPLETE; g_statusText = "Session ended waiting for IFVG"; return; }
         int idx = FindEntryIFVG();
         if(idx >= 0)
           {
            g_activeFvgIdx = idx;
            g_barsWaitedForRetrace = 0;
            g_state = WAIT_FOR_RETRACE;
            PrintFormat("[%s] %s IFVG detected [%.5f-%.5f]", TimeToString(GetNewYorkTime(), TIME_MINUTES),
                        g_pursuingShort ? "bearish" : "bullish", g_fvgList[idx].bottom, g_fvgList[idx].top);
           }
         else
           {
            PrintFormat("[%s] NO TRADE: no IFVG yet", TimeToString(GetNewYorkTime(), TIME_MINUTES));
           }
         break;
        }

      case WAIT_FOR_RETRACE:
        {
         DetectFVG(); DetectIFVG();
         if(sessionEnded) { g_state = DAY_COMPLETE; g_statusText = "Session ended waiting for retrace"; return; }
         if(g_activeFvgIdx < 0 || g_activeFvgIdx >= ArraySize(g_fvgList))
           {
            g_state = WAIT_FOR_IFVG; // the tracked zone got pruned, look for a fresh one
            return;
           }
         g_barsWaitedForRetrace++;

         FVGZone z = g_fvgList[g_activeFvgIdx];
         double low1 = iLow(_Symbol, PERIOD_M1, 1), high1 = iHigh(_Symbol, PERIOD_M1, 1);
         bool touched = g_pursuingShort ? (high1 >= z.bottom) : (low1 <= z.top);
         if(touched)
           {
            PrintFormat("[%s] IFVG retraced", TimeToString(GetNewYorkTime(), TIME_MINUTES));
            g_state = WAIT_FOR_ENTRY_CONFIRMATION;
           }
         break;
        }

      case WAIT_FOR_ENTRY_CONFIRMATION:
        {
         if(sessionEnded) { g_state = DAY_COMPLETE; g_statusText = "Session ended waiting for entry confirmation"; return; }
         TryEnterFromIFVG();
         break;
        }

      default:
         break;
     }
  }

//+------------------------------------------------------------------+
//| Entry attempt paths                                                |
//+------------------------------------------------------------------+
void TryEnterFromDisplacement()
  {
   if(!SideLimitOK()) { g_state = DAY_COMPLETE; return; }
   double entry = g_pursuingShort ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   AttemptEntry(entry, true, false);
  }

void TryEnterFromIFVG()
  {
   if(g_activeFvgIdx < 0 || g_activeFvgIdx >= ArraySize(g_fvgList))
     {
      g_state = WAIT_FOR_IFVG;
      return;
     }
   FVGZone z = g_fvgList[g_activeFvgIdx];
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   double open1 = iOpen(_Symbol, PERIOD_M1, 1);
   double mid = (z.top + z.bottom) / 2.0;

   bool confirmed = false;
   switch(EntryMode)
     {
      case IFVG_TOUCH:
         confirmed = true; // the touch already happened in WAIT_FOR_RETRACE
         break;
      case IFVG_50_PERCENT:
        {
         double high1 = iHigh(_Symbol, PERIOD_M1, 1), low1 = iLow(_Symbol, PERIOD_M1, 1);
         confirmed = g_pursuingShort ? (high1 >= mid) : (low1 <= mid);
         break;
        }
      case IFVG_REJECTION_CLOSE:
        {
         bool rejectionCandle = g_pursuingShort ? (close1 < open1) : (close1 > open1);
         bool closedBackOut = g_pursuingShort ? (close1 < z.bottom) : (close1 > z.top);
         confirmed = rejectionCandle && closedBackOut;
         break;
        }
      default:
         confirmed = true;
         break;
     }

   if(!confirmed)
     {
      if(g_barsWaitedForRetrace > SweepConfirmationCandles * 3)
        {
         PrintFormat("[%s] NO TRADE: IFVG never confirmed rejection", TimeToString(GetNewYorkTime(), TIME_MINUTES));
         g_state = DAY_COMPLETE;
        }
      return;
     }

   if(!SideLimitOK()) { g_state = DAY_COMPLETE; return; }
   double entry = g_pursuingShort ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   g_fvgList[g_activeFvgIdx].usedForEntry = true;
   AttemptEntry(entry, false, true);
  }

void AttemptEntry(double entry, bool fromDisplacement, bool fromIFVG)
  {
   double buffer = StopBufferPoints * _Point;
   double sl = g_pursuingShort ? g_sweepExtreme + buffer : g_sweepExtreme - buffer;

   double tp;
   switch(TargetMode)
     {
      case FIXED_RR:
         tp = g_pursuingShort ? entry - MathAbs(entry - sl) * FixedRRTarget
                               : entry + MathAbs(entry - sl) * FixedRRTarget;
         break;
      case NEAREST_LIQUIDITY:
      case OPPOSITE_8AM_RANGE:
      default:
         tp = g_pursuingShort ? g_8amLow : g_8amHigh;
         break;
     }

   double rr;
   if(!ValidateRiskReward(entry, sl, tp, rr))
     {
      PrintFormat("[%s] NO TRADE: RR %.2f below threshold %.2f", TimeToString(GetNewYorkTime(), TIME_MINUTES), rr, MinimumRR);
      g_state = DAY_COMPLETE;
      return;
     }

   if(NewsBlocking())
     {
      PrintFormat("[%s] NO TRADE: high-impact news window", TimeToString(GetNewYorkTime(), TIME_MINUTES));
      return; // stay in current state, retry next bar once the window passes
     }

   bool closedBackInside = true; // reaching this point required RequireCloseBackInsideRange logic already
   bool strongDisplacement = true;
   bool cleanIFVG = fromIFVG;
   bool retested = fromIFVG;
   double score = CalculateSetupScore(closedBackInside, strongDisplacement, cleanIFVG, retested, rr);
   g_setupScore = score; g_lastRR = rr;

   if(score < MinimumSetupScore)
     {
      PrintFormat("[%s] NO TRADE: setup score %.0f below minimum %.0f", TimeToString(GetNewYorkTime(), TIME_MINUTES), score, MinimumSetupScore);
      g_state = DAY_COMPLETE;
      return;
     }

   double openRiskPct = (AccountInfoDouble(ACCOUNT_EQUITY) > 0)
                          ? (MathAbs(entry - sl) / entry) * 100.0 : 0; // rough proxy, refined by lot calc's own risk-money targeting
   // MaximumOpenRiskPercent is enforced through CalculatePositionSize's RiskPercent-based sizing;
   // an explicit extra guard here keeps behaviour honest if RiskPercent input is ever set above it.
   if(RiskPercent > MaximumOpenRiskPercent)
     {
      PrintFormat("[%s] NOTE: RiskPercent input (%.2f%%) exceeds MaximumOpenRiskPercent (%.2f%%), sizing capped by risk calc",
                  TimeToString(GetNewYorkTime(), TIME_MINUTES), RiskPercent, MaximumOpenRiskPercent);
     }

   PrintFormat("[%s] setup score = %.0f", TimeToString(GetNewYorkTime(), TIME_MINUTES), score);
   PrintFormat("[%s] RR = %.2f", TimeToString(GetNewYorkTime(), TIME_MINUTES), rr);

   ExecuteTrade(g_pursuingShort, entry, sl, tp, rr, score);
  }

//+------------------------------------------------------------------+
//| DASHBOARD                                                          |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   if(!ShowDashboard) return;
   if(MQLInfoInteger(MQL_TESTER)) return; // headless/backtest -- no one watches this, and per-tick chart-object
                                            // redraws over a full every-tick history are extremely slow in MT5

   string lines[];
   ArrayResize(lines, 13);
   lines[0]  = "TWI 9AM CR MODEL";
   lines[1]  = "NY Time: " + TimeToString(GetNewYorkTime(), TIME_DATE | TIME_MINUTES);
   lines[2]  = StringFormat("8AM High: %.5f", g_8amHigh);
   lines[3]  = StringFormat("8AM Low: %.5f", g_8amLow);
   lines[4]  = StringFormat("Range: %.1f pts", g_8amRange / _Point);
   lines[5]  = "Current State: " + EnumToString(g_state);
   lines[6]  = StringFormat("Sweep: %.5f", g_sweepExtreme);
   lines[7]  = "Displacement: " + (g_state == HIGH_SWEPT || g_state == LOW_SWEPT || g_state == WAIT_FOR_DISPLACEMENT ? "pending" : "checked");
   lines[8]  = StringFormat("IFVG: %s", g_activeFvgIdx >= 0 && g_activeFvgIdx < ArraySize(g_fvgList) ? "tracking" : "none");
   lines[9]  = StringFormat("Setup Score: %.0f", g_setupScore);
   lines[10] = StringFormat("RR: %.2f", g_lastRR);
   lines[11] = StringFormat("Trades Today: %d   Daily P/L: %.2f", g_tradesToday, g_dailyPL);
   lines[12] = "EA Status: " + g_statusText;

   for(int i = 0; i < ArraySize(lines); i++)
     {
      string name = StringFormat("TWI9AM_Dash_%d", i);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + i * 16);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
        }
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
     }
  }

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                      |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   g_atrHandleM1 = iATR(_Symbol, PERIOD_M1, 14);
   if(g_atrHandleM1 == INVALID_HANDLE)
     {
      Print("TWI 9AM CR Model: failed to create M1 ATR handle");
      return INIT_FAILED;
     }
   g_currentNYDay = GetNYMidnightMarker();
   ResetDailyState();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandleM1 != INVALID_HANDLE)
      IndicatorRelease(g_atrHandleM1);
   ClearChartObjects();
  }

//+------------------------------------------------------------------+
//| MAIN LOOP                                                          |
//+------------------------------------------------------------------+
bool IsNewM1Bar()
  {
   datetime t = iTime(_Symbol, PERIOD_M1, 0);
   if(t != g_lastM1BarTime)
     {
      g_lastM1BarTime = t;
      return true;
     }
   return false;
  }

void OnTick()
  {
   datetime todayMarker = GetNYMidnightMarker();
   if(todayMarker != g_currentNYDay)
     {
      g_currentNYDay = todayMarker;
      ResetDailyState();
     }

   if(g_state == TRADE_ACTIVE)
     {
      ManagePosition();
      if(CloseAtSessionEnd)
        {
         MqlDateTime s; TimeToStruct(GetNewYorkTime(), s);
         int nowMin = s.hour * 60 + s.min;
         int endMin = TradingEndHour * 60 + TradingEndMinute;
         if(nowMin > endMin && g_activeTicket != 0 && PositionSelectByTicket(g_activeTicket))
           {
            trade.PositionClose(g_activeTicket);
            Print("CloseAtSessionEnd: closed active position at session end");
           }
        }
     }

   if(IsNewM1Bar())
      RunStateMachine();

   DrawDashboard();
  }
//+------------------------------------------------------------------+
