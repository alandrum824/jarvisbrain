//+------------------------------------------------------------------+
//|                                            TWI OB Hunter.mq5     |
//|  ICT/SMC-style Order Block + Liquidity Sweep EA.                 |
//|  Logic per direction:                                            |
//|   1. Track recent swing highs/lows (fractals) on StructureTF.    |
//|   2. SWEEP: a bar wicks beyond a swing level (grabs stop-loss    |
//|      liquidity resting there) but CLOSES back on the other side. |
//|   3. BOS: within a few bars, price closes through the opposite   |
//|      recent swing (structure break confirms a real reversal,     |
//|      not just noise).                                            |
//|   4. ORDER BLOCK: the last opposite-colour candle before the     |
//|      displacement leg that caused the BOS. Its high/low become   |
//|      a zone.                                                     |
//|   5. ENTRY: price retraces back into the zone -> market order.   |
//|      If UseEntryTFConfirm, entry instead waits for a lower-      |
//|      timeframe (EntryTF) candle to "tap & close": wick into the  |
//|      zone, then CLOSE back beyond it -- real reject/reclaim, not |
//|      just a tick touching the zone.                              |
//|  Zones expire unfilled after MaxOBAgeBars and are one-shot.      |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_LOT_MODE
  {
   LOT_FIXED,
   LOT_DYNAMIC
  };

input group "=== General ==="
input long             MagicNumber        = 20260831;
input ENUM_TIMEFRAMES  StructureTF        = PERIOD_M15;  // timeframe used to find swings/sweeps/OBs
input int              SwingLookback      = 3;           // bars each side required to confirm a fractal swing
input int              MaxSwingPoints     = 8;            // how many recent swing highs/lows to remember

input group "=== Liquidity Sweep ==="
input int              AtrPeriod          = 14;
input double           SweepMinATRmult    = 0.10;         // min wick beyond the swing level, as ATR multiple, to count as a real sweep
input int              MaxBarsForBOS      = 8;             // bars allowed between the sweep and the confirming BOS

input group "=== Order Block Zone ==="
input int              MaxOBAgeBars       = 40;            // bars an unfilled zone stays valid before expiry
input double           OBBufferATRmult    = 0.05;          // small buffer added to SL beyond the zone edge
input int              MaxActiveOBs       = 6;              // oldest pruned beyond this count (per symbol/chart)

input group "=== Entry / Exit ==="
input bool             OnePerZone         = true;           // each zone can only be traded once
input bool             UseLiquidityTP     = true;            // true = target nearest opposite unswept swing instead of fixed RR
input double           RR_Multiplier      = 2.0;             // used when UseLiquidityTP == false

input group "=== Entry Timing ==="
input bool             UseEntryTFConfirm  = true;            // false = old behaviour: enter the instant price ticks into the zone
input ENUM_TIMEFRAMES  EntryTF            = PERIOD_M5;        // lower TF the tap-and-close confirmation is evaluated on

input group "=== Risk / Lot Sizing ==="
input ENUM_LOT_MODE    LotMode            = LOT_DYNAMIC;
input double           FixedLotSize       = 0.01;
input double           RiskPercent        = 1.0;             // used when LotMode == LOT_DYNAMIC

input group "=== Trade Caps ==="
input int              MaxConcurrentTrades = 1;

input group "=== Session Filter (broker/server time) ==="
input bool             UseSessionFilter   = false;
input int              SessionStartHour   = 7;
input int              SessionEndHour     = 20;
input bool             TradeMonday        = true;
input bool             TradeTuesday       = true;
input bool             TradeWednesday     = true;
input bool             TradeThursday      = true;
input bool             TradeFriday        = true;
input bool             TradeSaturday      = false;
input bool             TradeSunday        = false;

input group "=== Display ==="
input bool             ShowZones          = true;
input color            BullOBColor        = clrDodgerBlue;
input color            BearOBColor        = clrOrangeRed;

//----------------- Order block zone -----------------
struct OrderBlock
  {
   double   top;
   double   bottom;
   bool     isBullish;
   datetime createdTime;
   int      createdBarsAgo;   // age in StructureTF bars, incremented each new bar
   bool     filled;
   string   objName;
  };

OrderBlock obList[];

//----------------- Swing point memory -----------------
double   swHighPrice[]; datetime swHighTime[]; bool swHighSwept[];
double   swLowPrice[];  datetime swLowTime[];  bool swLowSwept[];

//----------------- Pending sweep -> BOS setups (one slot each direction) -----------------
bool     pendBear = false;
double   pendBearSweepLevel = 0, pendBearStructLow = 0;
int      pendBearBarsWaited = 0;

bool     pendBull = false;
double   pendBullSweepLevel = 0, pendBullStructHigh = 0;
int      pendBullBarsWaited = 0;

int      atrHandle = INVALID_HANDLE;
datetime lastStructBarTime = 0;
datetime lastEntryBarTime = 0;
int      obCounter = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   atrHandle = iATR(_Symbol, StructureTF, AtrPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("TWI OB Hunter: failed to create ATR handle");
      return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(MagicNumber);
   ArrayResize(obList, 0);
   ArrayResize(swHighPrice, 0); ArrayResize(swHighTime, 0); ArrayResize(swHighSwept, 0);
   ArrayResize(swLowPrice, 0);  ArrayResize(swLowTime, 0);  ArrayResize(swLowSwept, 0);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   for(int i = 0; i < ArraySize(obList); i++)
      ObjectDelete(0, obList[i].objName);
  }

//+------------------------------------------------------------------+
double CurrentATR()
  {
   double buf[];
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) < 1)
      return 0;
   return buf[0];
  }

//+------------------------------------------------------------------+
bool DayAllowed(datetime t)
  {
   MqlDateTime dt; TimeToStruct(t, dt);
   switch(dt.day_of_week)
     {
      case 0: return TradeSunday;
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      case 6: return TradeSaturday;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool SessionAllowed(datetime t)
  {
   if(!UseSessionFilter)
      return true;
   MqlDateTime dt; TimeToStruct(t, dt);
   if(SessionStartHour <= SessionEndHour)
      return dt.hour >= SessionStartHour && dt.hour < SessionEndHour;
   return dt.hour >= SessionStartHour || dt.hour < SessionEndHour; // wraps midnight
  }

//+------------------------------------------------------------------+
int CountOpenTrades()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
double CalcLot(double slDistance)
  {
   if(LotMode == LOT_FIXED)
      return FixedLotSize;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = _Point;
   double valuePerPoint = tickValue * (_Point / tickSize);
   double slPoints = slDistance / _Point;
   if(slPoints <= 0 || valuePerPoint <= 0)
      return FixedLotSize;

   double lot = riskMoney / (slPoints * valuePerPoint);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
  }

//+------------------------------------------------------------------+
void PushSwingHigh(double price, datetime t)
  {
   int n = ArraySize(swHighPrice);
   ArrayResize(swHighPrice, n + 1); ArrayResize(swHighTime, n + 1); ArrayResize(swHighSwept, n + 1);
   swHighPrice[n] = price; swHighTime[n] = t; swHighSwept[n] = false;
   if(ArraySize(swHighPrice) > MaxSwingPoints)
     {
      ArrayRemove(swHighPrice, 0, 1);
      ArrayRemove(swHighTime, 0, 1);
      ArrayRemove(swHighSwept, 0, 1);
     }
  }

//+------------------------------------------------------------------+
void PushSwingLow(double price, datetime t)
  {
   int n = ArraySize(swLowPrice);
   ArrayResize(swLowPrice, n + 1); ArrayResize(swLowTime, n + 1); ArrayResize(swLowSwept, n + 1);
   swLowPrice[n] = price; swLowTime[n] = t; swLowSwept[n] = false;
   if(ArraySize(swLowPrice) > MaxSwingPoints)
     {
      ArrayRemove(swLowPrice, 0, 1);
      ArrayRemove(swLowTime, 0, 1);
      ArrayRemove(swLowSwept, 0, 1);
     }
  }

//+------------------------------------------------------------------+
// Most recent NOT-yet-swept swing high/low, excluding anything at or
// after the given time (so we grab the level that was resting BEFORE it).
int LatestUnsweptHighBefore(datetime beforeTime)
  {
   for(int i = ArraySize(swHighPrice) - 1; i >= 0; i--)
      if(!swHighSwept[i] && swHighTime[i] < beforeTime)
         return i;
   return -1;
  }
int LatestUnsweptLowBefore(datetime beforeTime)
  {
   for(int i = ArraySize(swLowPrice) - 1; i >= 0; i--)
      if(!swLowSwept[i] && swLowTime[i] < beforeTime)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
void AddOrderBlock(double top, double bottom, bool isBullish, datetime t)
  {
   int n = ArraySize(obList);
   ArrayResize(obList, n + 1);
   obList[n].top = top;
   obList[n].bottom = bottom;
   obList[n].isBullish = isBullish;
   obList[n].createdTime = t;
   obList[n].createdBarsAgo = 0;
   obList[n].filled = false;
   obCounter++;
   obList[n].objName = "TWIOB_" + IntegerToString((int)MagicNumber) + "_" + IntegerToString(obCounter);

   if(ShowZones)
     {
      color c = isBullish ? BullOBColor : BearOBColor;
      datetime endTime = t + PeriodSeconds(StructureTF) * (MaxOBAgeBars + 1);
      ObjectCreate(0, obList[n].objName, OBJ_RECTANGLE, 0, t, top, endTime, bottom);
      ObjectSetInteger(0, obList[n].objName, OBJPROP_COLOR, c);
      ObjectSetInteger(0, obList[n].objName, OBJPROP_FILL, true);
      ObjectSetInteger(0, obList[n].objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, obList[n].objName, OBJPROP_WIDTH, 1);
     }

   PrintFormat("TWI OB Hunter: new %s OB zone %.5f - %.5f", isBullish ? "BULLISH" : "BEARISH", bottom, top);
  }

//+------------------------------------------------------------------+
void RemoveOrderBlock(int idx)
  {
   ObjectDelete(0, obList[idx].objName);
   ArrayRemove(obList, idx, 1);
  }

//+------------------------------------------------------------------+
// Scan StructureTF bars from 'fromShift' back to 'toShift' (inclusive,
// fromShift > toShift) for the last candle of the given colour.
// Returns the shift, or -1 if none found.
int FindLastCandle(int fromShift, int toShift, bool wantBullish)
  {
   for(int s = fromShift; s <= toShift; s++)
     {
      double o = iOpen(_Symbol, StructureTF, s);
      double c = iClose(_Symbol, StructureTF, s);
      if(wantBullish && c > o) return s;
      if(!wantBullish && c < o) return s;
     }
   return -1;
  }

//+------------------------------------------------------------------+
// Runs once per newly-closed StructureTF bar. shift=1 is the bar that
// just closed.
void OnStructureBarClose()
  {
   double atr = CurrentATR();
   if(atr <= 0) return;

   double h1 = iHigh(_Symbol, StructureTF, 1);
   double l1 = iLow(_Symbol, StructureTF, 1);
   double c1 = iClose(_Symbol, StructureTF, 1);
   datetime t1 = iTime(_Symbol, StructureTF, 1);

   // --- register a new confirmed swing point (fractal centred SwingLookback+1 bars ago) ---
   int cand = SwingLookback + 1;
   bool isHigh = true, isLow = true;
   double candHigh = iHigh(_Symbol, StructureTF, cand);
   double candLow  = iLow(_Symbol, StructureTF, cand);
   for(int k = 1; k <= SwingLookback; k++)
     {
      if(iHigh(_Symbol, StructureTF, cand - k) > candHigh || iHigh(_Symbol, StructureTF, cand + k) > candHigh) isHigh = false;
      if(iLow(_Symbol, StructureTF, cand - k)  < candLow  || iLow(_Symbol, StructureTF, cand + k)  < candLow)  isLow  = false;
     }
   if(isHigh) PushSwingHigh(candHigh, iTime(_Symbol, StructureTF, cand));
   if(isLow)  PushSwingLow(candLow,  iTime(_Symbol, StructureTF, cand));

   // --- sweep detection on the bar that just closed ---
   int hIdx = LatestUnsweptHighBefore(t1);
   if(hIdx >= 0 && h1 > swHighPrice[hIdx] + atr * SweepMinATRmult && c1 < swHighPrice[hIdx])
     {
      swHighSwept[hIdx] = true;
      int loIdx = LatestUnsweptLowBefore(swHighTime[hIdx]);
      if(loIdx >= 0 && !pendBear)
        {
         pendBear = true;
         pendBearSweepLevel = swHighPrice[hIdx];
         pendBearStructLow  = swLowPrice[loIdx];
         pendBearBarsWaited = 0;
         PrintFormat("TWI OB Hunter: sell-side liquidity swept at %.5f, watching for BOS below %.5f", pendBearSweepLevel, pendBearStructLow);
        }
     }

   int lIdx = LatestUnsweptLowBefore(t1);
   if(lIdx >= 0 && l1 < swLowPrice[lIdx] - atr * SweepMinATRmult && c1 > swLowPrice[lIdx])
     {
      swLowSwept[lIdx] = true;
      int hiIdx = LatestUnsweptHighBefore(swLowTime[lIdx]);
      if(hiIdx >= 0 && !pendBull)
        {
         pendBull = true;
         pendBullSweepLevel = swLowPrice[lIdx];
         pendBullStructHigh = swHighPrice[hiIdx];
         pendBullBarsWaited = 0;
         PrintFormat("TWI OB Hunter: buy-side liquidity swept at %.5f, watching for BOS above %.5f", pendBullSweepLevel, pendBullStructHigh);
        }
     }

   // --- BOS confirmation for a pending bearish setup ---
   if(pendBear)
     {
      pendBearBarsWaited++;
      if(c1 < pendBearStructLow)
        {
         int obShift = FindLastCandle(1, 1 + MaxBarsForBOS, true); // last bullish candle since the sweep
         if(obShift >= 0)
            AddOrderBlock(iHigh(_Symbol, StructureTF, obShift), iLow(_Symbol, StructureTF, obShift), false, iTime(_Symbol, StructureTF, obShift));
         pendBear = false;
        }
      else if(pendBearBarsWaited > MaxBarsForBOS)
        {
         pendBear = false; // setup timed out, no real displacement followed the sweep
        }
     }

   // --- BOS confirmation for a pending bullish setup ---
   if(pendBull)
     {
      pendBullBarsWaited++;
      if(c1 > pendBullStructHigh)
        {
         int obShift = FindLastCandle(1, 1 + MaxBarsForBOS, false); // last bearish candle since the sweep
         if(obShift >= 0)
            AddOrderBlock(iHigh(_Symbol, StructureTF, obShift), iLow(_Symbol, StructureTF, obShift), true, iTime(_Symbol, StructureTF, obShift));
         pendBull = false;
        }
      else if(pendBullBarsWaited > MaxBarsForBOS)
        {
         pendBull = false;
        }
     }

   // --- age out zones ---
   for(int i = ArraySize(obList) - 1; i >= 0; i--)
     {
      obList[i].createdBarsAgo++;
      if(obList[i].createdBarsAgo > MaxOBAgeBars)
         RemoveOrderBlock(i);
     }
   while(ArraySize(obList) > MaxActiveOBs)
      RemoveOrderBlock(0);
  }

//+------------------------------------------------------------------+
// Nearest opposite unswept swing beyond entry, for liquidity-target TP.
double NearestOppositeLiquidity(bool isBuy, double entry)
  {
   double best = 0;
   if(isBuy)
     {
      for(int i = 0; i < ArraySize(swHighPrice); i++)
         if(!swHighSwept[i] && swHighPrice[i] > entry)
            if(best == 0 || swHighPrice[i] < best) best = swHighPrice[i];
     }
   else
     {
      for(int i = 0; i < ArraySize(swLowPrice); i++)
         if(!swLowSwept[i] && swLowPrice[i] < entry)
            if(best == 0 || swLowPrice[i] > best) best = swLowPrice[i];
     }
   return best;
  }

//+------------------------------------------------------------------+
void TryEnterZones()
  {
   if(CountOpenTrades() >= MaxConcurrentTrades)
      return;
   datetime now = TimeCurrent();
   if(!DayAllowed(now) || !SessionAllowed(now))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = CurrentATR();

   for(int i = 0; i < ArraySize(obList); i++)
     {
      if(obList[i].filled)
         continue;

      if(obList[i].isBullish && bid <= obList[i].top && bid >= obList[i].bottom)
        {
         double entry = ask;
         double sl    = obList[i].bottom - atr * OBBufferATRmult;
         double risk  = entry - sl;
         if(risk <= 0) continue;
         double tp = UseLiquidityTP ? NearestOppositeLiquidity(true, entry) : entry + risk * RR_Multiplier;
         if(tp <= entry) tp = entry + risk * RR_Multiplier;
         double lot = CalcLot(risk);
         if(trade.Buy(lot, _Symbol, entry, sl, tp, "TWI OB Hunter"))
           {
            if(OnePerZone) obList[i].filled = true;
            if(CountOpenTrades() >= MaxConcurrentTrades) return;
           }
        }
      else if(!obList[i].isBullish && ask >= obList[i].bottom && ask <= obList[i].top)
        {
         double entry = bid;
         double sl    = obList[i].top + atr * OBBufferATRmult;
         double risk  = sl - entry;
         if(risk <= 0) continue;
         double tp = UseLiquidityTP ? NearestOppositeLiquidity(false, entry) : entry - risk * RR_Multiplier;
         if(tp >= entry || tp <= 0) tp = entry - risk * RR_Multiplier;
         double lot = CalcLot(risk);
         if(trade.Sell(lot, _Symbol, entry, sl, tp, "TWI OB Hunter"))
           {
            if(OnePerZone) obList[i].filled = true;
            if(CountOpenTrades() >= MaxConcurrentTrades) return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
// Entry gated on a lower-timeframe (EntryTF) "tap & close": the just-
// closed EntryTF candle must wick INTO the zone, then CLOSE back beyond
// it -- real reject/reclaim, not just a tick touching the zone edge.
void TryEnterZonesEntryTF()
  {
   if(CountOpenTrades() >= MaxConcurrentTrades)
      return;
   datetime now = TimeCurrent();
   if(!DayAllowed(now) || !SessionAllowed(now))
      return;

   double closeE = iClose(_Symbol, EntryTF, 1);
   double highE  = iHigh(_Symbol, EntryTF, 1);
   double lowE   = iLow(_Symbol, EntryTF, 1);
   double atr = CurrentATR();

   for(int i = 0; i < ArraySize(obList); i++)
     {
      if(obList[i].filled)
         continue;

      if(obList[i].isBullish)
        {
         bool tapped    = lowE <= obList[i].top && lowE >= obList[i].bottom;
         bool reclaimed = closeE > obList[i].top;
         if(tapped && reclaimed)
           {
            double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl    = obList[i].bottom - atr * OBBufferATRmult;
            double risk  = entry - sl;
            if(risk <= 0) continue;
            double tp = UseLiquidityTP ? NearestOppositeLiquidity(true, entry) : entry + risk * RR_Multiplier;
            if(tp <= entry) tp = entry + risk * RR_Multiplier;
            double lot = CalcLot(risk);
            if(trade.Buy(lot, _Symbol, 0, sl, tp, "TWI OB Hunter"))
              {
               if(OnePerZone) obList[i].filled = true;
               if(CountOpenTrades() >= MaxConcurrentTrades) return;
              }
           }
        }
      else
        {
         bool tapped    = highE >= obList[i].bottom && highE <= obList[i].top;
         bool reclaimed = closeE < obList[i].bottom;
         if(tapped && reclaimed)
           {
            double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl    = obList[i].top + atr * OBBufferATRmult;
            double risk  = sl - entry;
            if(risk <= 0) continue;
            double tp = UseLiquidityTP ? NearestOppositeLiquidity(false, entry) : entry - risk * RR_Multiplier;
            if(tp >= entry || tp <= 0) tp = entry - risk * RR_Multiplier;
            double lot = CalcLot(risk);
            if(trade.Sell(lot, _Symbol, 0, sl, tp, "TWI OB Hunter"))
              {
               if(OnePerZone) obList[i].filled = true;
               if(CountOpenTrades() >= MaxConcurrentTrades) return;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime barTime = iTime(_Symbol, StructureTF, 0);
   if(barTime != lastStructBarTime)
     {
      lastStructBarTime = barTime;
      if(Bars(_Symbol, StructureTF) > (SwingLookback * 2 + MaxBarsForBOS + 5))
         OnStructureBarClose();
     }

   if(UseEntryTFConfirm)
     {
      datetime entryBarTime = iTime(_Symbol, EntryTF, 0);
      if(entryBarTime != lastEntryBarTime)
        {
         lastEntryBarTime = entryBarTime;
         TryEnterZonesEntryTF();
        }
     }
   else
     {
      TryEnterZones();
     }
  }
//+------------------------------------------------------------------+
