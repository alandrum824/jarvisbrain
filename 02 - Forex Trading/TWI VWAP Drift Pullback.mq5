//+------------------------------------------------------------------+
//|                              TWI VWAP Drift Pullback.mq5         |
//|  3-rule VWAP drift-pullback EA.                                  |
//|  BIAS (evaluated on TradeTF, using session-anchored VWAP):        |
//|   LONG  : close > VWAP, VWAP rising over Lookback15Min,           |
//|           price up >= PctThreshold1Hour over Lookback1Hour.       |
//|   SHORT : mirror (close < VWAP, VWAP falling, price down).        |
//|  TRIGGER (fires once per bias episode, "tap & close" confirmed):  |
//|   LONG  bias -> red   candle wicks into VWAP AND closes above it  |
//|   SHORT bias -> green candle wicks into VWAP AND closes below it  |
//|  SL = trigger candle's wick +/- ATR buffer. TP = RR_Multiplier*R. |
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
input long             MagicNumber          = 20260902;
input ENUM_TIMEFRAMES  TradeTF              = PERIOD_M5;   // timeframe bias + trigger are evaluated on

input group "=== Bias Rules ==="
input int              Lookback15Min        = 15;          // minutes; auto-converted to bars on TradeTF
input int              Lookback1Hour        = 60;           // minutes; auto-converted to bars on TradeTF
input double           PctThreshold1Hour    = 0.10;          // required % move over Lookback1Hour to establish bias

input group "=== Stop / Target ==="
input int              AtrPeriod            = 14;
input double           SLBufferATRmult      = 0.10;          // extra buffer beyond the trigger candle's wick
input double           RR_Multiplier        = 1.5;

input group "=== Risk / Lot Sizing ==="
input ENUM_LOT_MODE    LotMode              = LOT_FIXED;
input double           FixedLotSize         = 0.01;
input double           RiskPercent          = 1.0;           // used when LotMode == LOT_DYNAMIC

input group "=== Trade Caps ==="
input int              MaxConcurrentTrades  = 1;

//----------------- VWAP history (index 0 = most recently CLOSED bar, growing "bars ago") -----------------
double   vwapHist[];
int      vwapHistCount = 0;
double   cumPV = 0, cumV = 0;
datetime cumDayStart = 0;

int      atrHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

int      biasState = 0;     // 0 = none, 1 = long, 2 = short
bool     episodeTriggered = false;

//+------------------------------------------------------------------+
int PeriodMinutesOf()
  {
   int secs = PeriodSeconds(TradeTF);
   return (int)MathMax(1, secs / 60);
  }

int BarsFor(int minutes)
  {
   return (int)MathMax(1, MathRound((double)minutes / PeriodMinutesOf()));
  }

datetime DayStartOf(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
  }

//+------------------------------------------------------------------+
void PushVwap(double v)
  {
   int n = ArraySize(vwapHist);
   if(n < 400)
     {
      ArrayResize(vwapHist, n + 1);
      n++;
     }
   for(int i = n - 1; i > 0; i--)
      vwapHist[i] = vwapHist[i - 1];
   vwapHist[0] = v;
   vwapHistCount = ArraySize(vwapHist);
  }

//+------------------------------------------------------------------+
// Backfill cumulative VWAP state from the start of today's session up
// through the most recently closed bar, so VWAP is correct immediately
// on attach instead of starting cold at zero mid-session.
void BackfillVwap()
  {
   ArrayResize(vwapHist, 0);
   cumPV = 0; cumV = 0;
   datetime nowT = TimeCurrent();
   cumDayStart = DayStartOf(nowT);

   int oldestShift = iBarShift(_Symbol, TradeTF, cumDayStart, false);
   if(oldestShift <= 0)
      oldestShift = 1;
   if(oldestShift > 400)
      oldestShift = 400;

   for(int shift = oldestShift; shift >= 1; shift--)
     {
      double hi = iHigh(_Symbol, TradeTF, shift);
      double lo = iLow(_Symbol, TradeTF, shift);
      double cl = iClose(_Symbol, TradeTF, shift);
      long   vol = iTickVolume(_Symbol, TradeTF, shift);
      double typical = (hi + lo + cl) / 3.0;
      cumPV += typical * (double)vol;
      cumV  += (double)vol;
      double vwapNow = (cumV > 0) ? cumPV / cumV : cl;
      PushVwap(vwapNow);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   atrHandle = iATR(_Symbol, TradeTF, AtrPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("TWI VWAP Drift Pullback: failed to create ATR handle");
      return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(MagicNumber);
   BackfillVwap();
   lastBarTime = iTime(_Symbol, TradeTF, 0);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
  }

//+------------------------------------------------------------------+
double CalcLot(double slDistance)
  {
   if(LotMode == LOT_FIXED)
      return FixedLotSize;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0)
      return FixedLotSize;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lots = (lossPerLot > 0) ? riskMoney / lossPerLot : FixedLotSize;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

//+------------------------------------------------------------------+
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
void OnTick()
  {
   datetime curBarTime = iTime(_Symbol, TradeTF, 0);
   if(curBarTime == lastBarTime)
      return;   // only evaluate once per new bar
   lastBarTime = curBarTime;

   // New trading day -> reset VWAP accumulation cleanly via backfill.
   if(DayStartOf(TimeCurrent()) != cumDayStart)
     {
      BackfillVwap();
     }
   else
     {
      // Roll the just-closed bar (shift 1) into the cumulative VWAP.
      double hi = iHigh(_Symbol, TradeTF, 1);
      double lo = iLow(_Symbol, TradeTF, 1);
      double cl = iClose(_Symbol, TradeTF, 1);
      long   vol = iTickVolume(_Symbol, TradeTF, 1);
      double typical = (hi + lo + cl) / 3.0;
      cumPV += typical * (double)vol;
      cumV  += (double)vol;
      double vwapNow = (cumV > 0) ? cumPV / cumV : cl;
      PushVwap(vwapNow);
     }

   int bars15 = BarsFor(Lookback15Min);
   int bars60 = BarsFor(Lookback1Hour);
   if(vwapHistCount <= MathMax(bars15, bars60))
      return;   // not enough VWAP history yet today

   double vwapNow  = vwapHist[0];
   double vwap15Ago = vwapHist[bars15];
   double closeNow = iClose(_Symbol, TradeTF, 1);
   double closePast60 = iClose(_Symbol, TradeTF, 1 + bars60);
   if(closePast60 <= 0)
      return;
   double pctChange = (closeNow - closePast60) / closePast60 * 100.0;

   bool longBias  = (closeNow > vwapNow) && (vwapNow > vwap15Ago) && (pctChange >= PctThreshold1Hour);
   bool shortBias = (closeNow < vwapNow) && (vwapNow < vwap15Ago) && (pctChange <= -PctThreshold1Hour);

   int newBias = longBias ? 1 : (shortBias ? 2 : 0);
   if(newBias != biasState)
     {
      biasState = newBias;
      episodeTriggered = false;
     }

   if(biasState == 0 || episodeTriggered)
      return;
   if(CountOpenPositions() >= MaxConcurrentTrades)
      return;

   double openC = iOpen(_Symbol, TradeTF, 1);
   double closeC = iClose(_Symbol, TradeTF, 1);
   double highC = iHigh(_Symbol, TradeTF, 1);
   double lowC  = iLow(_Symbol, TradeTF, 1);
   bool isRed   = closeC < openC;
   bool isGreen = closeC > openC;

   // "Tap & close" confirmation (TradeWithPat model): the trigger candle must
   // actually wick INTO the VWAP zone, then CLOSE back beyond it -- a real
   // reject/reclaim, not just any opposite-color candle near VWAP.
   bool tappedZoneLong  = (lowC <= vwapNow) && (closeC > vwapNow);
   bool tappedZoneShort = (highC >= vwapNow) && (closeC < vwapNow);

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) <= 0)
      return;
   double atrBuffer = atrBuf[0] * SLBufferATRmult;

   if(biasState == 1 && isRed && tappedZoneLong)
     {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = lowC - atrBuffer;
      double risk = entry - sl;
      if(risk <= 0) return;
      double tp = entry + risk * RR_Multiplier;
      double lots = CalcLot(risk);
      if(trade.Buy(lots, _Symbol, 0, sl, tp, "TWI VWAP Drift Pullback"))
         episodeTriggered = true;
     }
   else if(biasState == 2 && isGreen && tappedZoneShort)
     {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = highC + atrBuffer;
      double risk = sl - entry;
      if(risk <= 0) return;
      double tp = entry - risk * RR_Multiplier;
      double lots = CalcLot(risk);
      if(trade.Sell(lots, _Symbol, 0, sl, tp, "TWI VWAP Drift Pullback"))
         episodeTriggered = true;
     }
  }
//+------------------------------------------------------------------+
