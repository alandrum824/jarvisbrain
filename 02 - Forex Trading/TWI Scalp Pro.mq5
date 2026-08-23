//+------------------------------------------------------------------+
//|                                              TWI Scalp Pro.mq5   |
//|  Session-based aggressive Opening Range Breakout EA.             |
//|  Entry: first EntryTF candle to CLOSE beyond the session's       |
//|  Opening Range in the direction of the H1 trend filter.          |
//|  Stop: opposite side of the range. Target: risk x RR_Multiplier. |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE
  {
   LOT_FIXED,
   LOT_DYNAMIC
  };

input group "=== General ==="
input long             MagicNumber      = 20260822;
input ENUM_TIMEFRAMES  EntryTF          = PERIOD_M5;   // candle whose CLOSE triggers entry
input int              EMA_Period       = 50;
input ENUM_TIMEFRAMES  EMA_TF           = PERIOD_H1;   // trend filter timeframe
input double           RR_Multiplier    = 2.8;
input int              SL_BufferPips    = 0;           // extra pips beyond the OR extreme for SL
input int              EntryWindowMinutes = 240;       // how long after the OR closes a breakout is still tradeable

input group "=== Sessions (times are broker/server time, HH:MM) ==="
input bool             UseAllSessions   = false;
input bool             TradeAsian       = false;
input string           AsianStart       = "00:00";
input string           AsianEnd         = "00:15";
input bool             TradeLondon      = true;
input string           LondonStart      = "08:00";
input string           LondonEnd        = "08:15";
input bool             TradeNewYork     = true;
input string           NewYorkStart     = "13:30";
input string           NewYorkEnd       = "13:45";

input group "=== Days of Week ==="
input bool             TradeMonday      = true;
input bool             TradeTuesday     = true;
input bool             TradeWednesday   = true;
input bool             TradeThursday    = true;
input bool             TradeFriday      = true;
input bool             TradeSaturday    = false;
input bool             TradeSunday      = false;

input group "=== Risk / Lot Sizing ==="
input ENUM_LOT_MODE    LotMode          = LOT_FIXED;
input double           FixedLotSize     = 0.01;
input double           RiskPercent      = 1.0;         // used when LotMode == LOT_DYNAMIC

input group "=== Trade Caps ==="
input int              MaxConcurrentTrades = 1;
input int              MaxTradesPerSession = 1;

//--- session bookkeeping
struct SessionInfo
  {
   string   name;
   bool     enabled;
   int      startMin;
   int      endMin;
   double   orHigh;
   double   orLow;
   bool     orCaptured;
   datetime capturedDay;   // midnight of the day the OR was captured for
   int      tradesTaken;
   bool     signalArmed;   // true once we've seen a close still inside the range post-capture, so the very first stale bar doesn't fire
  };

SessionInfo sessions[3];
CTrade      trade;
int         emaHandle = INVALID_HANDLE;
datetime    lastEntryBarTime = 0;

//+------------------------------------------------------------------+
int ParseMinutes(const string hhmm)
  {
   string parts[];
   int n = StringSplit(hhmm, ':', parts);
   if(n < 2)
      return 0;
   return (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
  }

//+------------------------------------------------------------------+
datetime MidnightOf(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
bool DayAllowed(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
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
int OnInit()
  {
   sessions[0].name = "Asian";   sessions[0].enabled = UseAllSessions || TradeAsian;
   sessions[0].startMin = ParseMinutes(AsianStart); sessions[0].endMin = ParseMinutes(AsianEnd);

   sessions[1].name = "London";  sessions[1].enabled = UseAllSessions || TradeLondon;
   sessions[1].startMin = ParseMinutes(LondonStart); sessions[1].endMin = ParseMinutes(LondonEnd);

   sessions[2].name = "NewYork"; sessions[2].enabled = UseAllSessions || TradeNewYork;
   sessions[2].startMin = ParseMinutes(NewYorkStart); sessions[2].endMin = ParseMinutes(NewYorkEnd);

   for(int i = 0; i < 3; i++)
     {
      sessions[i].orCaptured  = false;
      sessions[i].capturedDay = 0;
      sessions[i].tradesTaken = 0;
      sessions[i].signalArmed = false;
     }

   emaHandle = iMA(_Symbol, EMA_TF, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
     {
      Print("TWI Scalp Pro: failed to create EMA handle");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
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
// Capture the opening range for a session once its window has closed
// for the current day, by scanning M1 bars across the window.
void CaptureOpeningRange(SessionInfo &s, datetime now)
  {
   datetime today = MidnightOf(now);
   if(s.orCaptured && s.capturedDay == today)
      return; // already captured today

   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;
   if(nowMin < s.endMin)
      return; // window hasn't closed yet today

   datetime windowStart = today + s.startMin * 60;
   datetime windowEnd   = today + s.endMin * 60;

   int shiftStart = iBarShift(_Symbol, PERIOD_M1, windowStart, true);
   int shiftEnd   = iBarShift(_Symbol, PERIOD_M1, windowEnd, true);
   if(shiftStart < 0 || shiftEnd < 0)
      return; // not enough history yet

   int hi = MathMax(shiftStart, shiftEnd);
   int lo = MathMin(shiftStart, shiftEnd);

   double orHigh = -DBL_MAX, orLow = DBL_MAX;
   for(int i = lo; i <= hi; i++)
     {
      double h = iHigh(_Symbol, PERIOD_M1, i);
      double l = iLow(_Symbol, PERIOD_M1, i);
      if(h > orHigh) orHigh = h;
      if(l < orLow)  orLow  = l;
     }

   if(orHigh <= -DBL_MAX || orLow >= DBL_MAX)
      return;

   s.orHigh      = orHigh;
   s.orLow       = orLow;
   s.orCaptured  = true;
   s.capturedDay = today;
   s.tradesTaken = 0;
   s.signalArmed = false;

   PrintFormat("TWI Scalp Pro: %s OR captured — High %.5f / Low %.5f", s.name, orHigh, orLow);
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
void TryEnter(SessionInfo &s, datetime now)
  {
   if(!s.enabled || !s.orCaptured)
      return;
   if(!DayAllowed(now))
      return;
   if(s.tradesTaken >= MaxTradesPerSession)
      return;
   if(CountOpenTrades() >= MaxConcurrentTrades)
      return;

   datetime today       = MidnightOf(now);
   datetime windowEnd   = today + s.endMin * 60;
   if((now - windowEnd) > EntryWindowMinutes * 60)
      return; // past the entry window for this session today

   double emaBuf[];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaBuf) < 1)
      return;
   double ema = emaBuf[0];
   double htfClose = iClose(_Symbol, EMA_TF, 0);
   bool uptrend = htfClose > ema;

   double close1 = iClose(_Symbol, EntryTF, 1);
   double close2 = iClose(_Symbol, EntryTF, 2);

   // arm the signal once we see a bar that's still inside/behind the range,
   // so a bar loaded mid-breakout on EA start doesn't fire immediately
   if(!s.signalArmed)
     {
      if(close2 <= s.orHigh && close2 >= s.orLow)
         s.signalArmed = true;
      else
         return;
     }

   double point = _Point;
   double buffer = SL_BufferPips * point * 10; // treat input as "pips" (10x point on 5-digit brokers)

   if(uptrend && close1 > s.orHigh && close2 <= s.orHigh)
     {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = s.orLow - buffer;
      double risk  = entry - sl;
      if(risk <= 0) return;
      double tp    = entry + risk * RR_Multiplier;
      double lot   = CalcLot(risk);
      if(trade.Buy(lot, _Symbol, entry, sl, tp, "TWI Scalp Pro " + s.name))
         s.tradesTaken++;
     }
   else if(!uptrend && close1 < s.orLow && close2 >= s.orLow)
     {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = s.orHigh + buffer;
      double risk  = sl - entry;
      if(risk <= 0) return;
      double tp    = entry - risk * RR_Multiplier;
      double lot   = CalcLot(risk);
      if(trade.Sell(lot, _Symbol, entry, sl, tp, "TWI Scalp Pro " + s.name))
         s.tradesTaken++;
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   for(int i = 0; i < 3; i++)
      CaptureOpeningRange(sessions[i], now);

   // only evaluate entries on a fresh EntryTF bar close
   datetime barTime = iTime(_Symbol, EntryTF, 0);
   if(barTime == lastEntryBarTime)
      return;
   lastEntryBarTime = barTime;

   for(int i = 0; i < 3; i++)
      TryEnter(sessions[i], now);
  }
//+------------------------------------------------------------------+
