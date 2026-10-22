//+------------------------------------------------------------------+
//|                                        TWI HS Pullback EA.mq5    |
//|                                                                  |
//|  Head & shoulders (regular = sell, inverse = buy), entered on    |
//|  the PULLBACK after the right shoulder's push - Adam's silver    |
//|  trade of 2026-09-30, written as rules.                          |
//|                                                                  |
//|  1. PATTERN (inverse / buy): the last three confirmed swing lows |
//|     = LS, HEAD, RS. Head lower than both shoulders by at least   |
//|     HeadMinATR. Shoulders within ShoulderTolATR of each other.   |
//|     Neckline = line through the highest high between LS-HEAD and |
//|     HEAD-RS. Optional: a real decline before the LS (reversal).  |
//|  2. PUSH: a strong candle off the right shoulder - body at least |
//|     ImpulseATR x ATR, in the trade direction.                    |
//|  3. PULLBACK: price dips at least PullbackATR x ATR from the push |
//|     high, stays above the RS, and the bar closes as a rejection  |
//|     (closes up, in the top part of its range).                   |
//|  4. ENTRY: market on the next bar. SL under the RS (or under     |
//|     both shoulders) + buffer. TP = measured move (neckline +     |
//|     head depth x TPFactor).                                      |
//|  5. MANAGEMENT: a bar that CLOSES beyond the neckline moves the  |
//|     stop to breakeven.                                           |
//|  Mode NECK_RETEST instead waits for a close through the neckline |
//|  and enters on the retest of it.                                 |
//|  Regular H&S (sell) is the exact mirror.                         |
//|                                                                  |
//|  Closed bars only, evaluated once per new bar. No repaint.       |
//|  No grid, no martingale, no averaging. One position at a time.   |
//|  Lot size from risk % with OrderCalcProfit (broker tick-value    |
//|  quirks, like AAAFx gold, can't fool it). Skips the trade if the |
//|  minimum lot would risk more than the limit.                     |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property description "Head & shoulders / inverse H&S. Entry on the pullback after the right shoulder's push, SL under the shoulder(s), TP = measured move."

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_HS_DIR   { DIR_BOTH = 0, DIR_LONG_ONLY = 1, DIR_SHORT_ONLY = 2 };
enum ENUM_HS_ENTRY { ENTRY_PULLBACK = 0,   // pullback after the RS push (Adam's way)
                     ENTRY_NECK_RETEST = 1 // close through the neckline, then retest
                   };
enum ENUM_HS_STOP  { STOP_UNDER_RS = 0, STOP_UNDER_BOTH = 1 };

input group "Pattern"
input ENUM_HS_DIR   Direction        = DIR_BOTH;
input int           PivotLen         = 5;     // bars each side of a swing
input int           Lookback         = 200;   // bars scanned for the pattern
input double        HeadMinATR       = 0.5;   // head beyond both shoulders by at least this x ATR
input double        ShoulderTolATR   = 1.5;   // max gap between the two shoulders, x ATR
input bool          RequirePriorTrend= true;  // a real move into the LS (makes it a reversal)
input int           PriorBars        = 40;    // bars before the LS checked for that move
input double        PriorTrendATR    = 1.0;   // prior extreme beyond the neckline by x ATR

input group "Entry"
input ENUM_HS_ENTRY EntryMode        = ENTRY_PULLBACK;
input double        ImpulseATR       = 1.2;   // push candle body >= x ATR
input double        PullbackATR      = 0.3;   // pullback depth from the push extreme, x ATR
input double        RejectFrac       = 0.6;   // rejection: close in the top (bottom) 60% of the bar
input double        RetestTolATR     = 0.3;   // NECK_RETEST: how close to the neckline counts as a retest
input int           MaxBarsAfterRS   = 40;    // setup expires this many bars after the RS

input group "Exits"
input ENUM_HS_STOP  StopMode         = STOP_UNDER_RS;
input double        StopBufferATR    = 0.1;
input double        TPFactor         = 1.0;   // 1.0 = full measured move
input double        MinRR            = 1.5;   // skip if the target pays less than this
input bool          BreakevenOnNeck  = true;  // SL to entry after a close beyond the neckline

input group "Risk"
input double        RiskPercent      = 2.0;   // % of balance risked per trade
input double        FixedLots        = 0.0;   // >0 overrides risk sizing
input double        MaxLots          = 0.05;  // hard cap
input int           MaxSpreadPoints  = 60;
input long          Magic            = 26093001;
input bool          DrawPattern      = true;

struct HSSetup
  {
   bool     armed;
   int      dir;        // +1 buy (inverse H&S), -1 sell (regular H&S)
   datetime tLS, tH, tRS, tN1, tN2;
   double   pLS, pH, pRS, pN1, pN2;
   bool     pushSeen;
   double   pushExt;    // highest high (buy) / lowest low (sell) since the push
   bool     neckBroken; // NECK_RETEST: closed through the neckline
   datetime usedRS;     // last RS time already traded or rejected
  };

HSSetup  L, S;
int      atrHandle = INVALID_HANDLE;
datetime lastBar   = 0;
// neckline of the open trade, for breakeven
datetime posN1 = 0, posN2 = 0; double posP1 = 0, posP2 = 0; int posDir = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   atrHandle = iATR(_Symbol, _Period, 14);
   if(atrHandle == INVALID_HANDLE) return(INIT_FAILED);
   trade.SetExpertMagicNumber(Magic);
   ZeroMemory(L); ZeroMemory(S);
   L.dir = 1; S.dir = -1;
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason) { if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle); }

//+------------------------------------------------------------------+
double ATR1() { double b[]; if(CopyBuffer(atrHandle, 0, 1, 1, b) != 1) return 0; return b[0]; }

// swing at shift s (s >= PivotLen+1 so every bar in the window is closed)
bool IsPivotLow(int s)
  { double v = iLow(_Symbol, _Period, s);
    for(int k = 1; k <= PivotLen; k++)
       if(iLow(_Symbol, _Period, s - k) < v || iLow(_Symbol, _Period, s + k) <= v) return false;
    return true; }
bool IsPivotHigh(int s)
  { double v = iHigh(_Symbol, _Period, s);
    for(int k = 1; k <= PivotLen; k++)
       if(iHigh(_Symbol, _Period, s - k) > v || iHigh(_Symbol, _Period, s + k) >= v) return false;
    return true; }

// neckline value at shift s
double NeckAt(datetime t1, double p1, datetime t2, double p2, int s)
  {
   int s1 = iBarShift(_Symbol, _Period, t1), s2 = iBarShift(_Symbol, _Period, t2);
   if(s1 == s2) return p2;
   return p1 + (p2 - p1) * double(s1 - s) / double(s1 - s2);
  }

bool HasPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) return true;
   return false;
  }

//+------------------------------------------------------------------+
// Find the latest pattern for one direction. Returns true and fills x.
bool FindPattern(HSSetup &x, double atr)
  {
   int piv[3]; int n = 0;
   for(int s = PivotLen + 1; s < Lookback && n < 3; s++)
      if(x.dir == 1 ? IsPivotLow(s) : IsPivotHigh(s)) piv[n++] = s;
   if(n < 3) return false;
   int sRS = piv[0], sH = piv[1], sLS = piv[2];
   double pRS = x.dir == 1 ? iLow(_Symbol, _Period, sRS) : iHigh(_Symbol, _Period, sRS);
   double pH  = x.dir == 1 ? iLow(_Symbol, _Period, sH)  : iHigh(_Symbol, _Period, sH);
   double pLS = x.dir == 1 ? iLow(_Symbol, _Period, sLS) : iHigh(_Symbol, _Period, sLS);
   // head beyond both shoulders
   if(x.dir == 1 && !(pH < pLS - HeadMinATR * atr && pH < pRS - HeadMinATR * atr)) return false;
   if(x.dir == -1 && !(pH > pLS + HeadMinATR * atr && pH > pRS + HeadMinATR * atr)) return false;
   if(MathAbs(pLS - pRS) > ShoulderTolATR * atr) return false;
   // neckline points: extreme between LS-H and H-RS
   int s1 = x.dir == 1 ? iHighest(_Symbol, _Period, MODE_HIGH, sLS - sH - 1, sH + 1)
                       : iLowest(_Symbol, _Period, MODE_LOW, sLS - sH - 1, sH + 1);
   int s2 = x.dir == 1 ? iHighest(_Symbol, _Period, MODE_HIGH, sH - sRS - 1, sRS + 1)
                       : iLowest(_Symbol, _Period, MODE_LOW, sH - sRS - 1, sRS + 1);
   if(s1 < 0 || s2 < 0) return false;
   double p1 = x.dir == 1 ? iHigh(_Symbol, _Period, s1) : iLow(_Symbol, _Period, s1);
   double p2 = x.dir == 1 ? iHigh(_Symbol, _Period, s2) : iLow(_Symbol, _Period, s2);
   // neckline must sit on the right side of both shoulders
   if(x.dir == 1 && (p1 <= pLS || p2 <= pRS)) return false;
   if(x.dir == -1 && (p1 >= pLS || p2 >= pRS)) return false;
   if(RequirePriorTrend)
     {
      int sp = x.dir == 1 ? iHighest(_Symbol, _Period, MODE_HIGH, PriorBars, sLS + 1)
                          : iLowest(_Symbol, _Period, MODE_LOW, PriorBars, sLS + 1);
      if(sp < 0) return false;
      double pp = x.dir == 1 ? iHigh(_Symbol, _Period, sp) : iLow(_Symbol, _Period, sp);
      if(x.dir == 1 && pp < p1 + PriorTrendATR * atr) return false;
      if(x.dir == -1 && pp > p1 - PriorTrendATR * atr) return false;
     }
   datetime tRS = iTime(_Symbol, _Period, sRS);
   if(tRS == x.usedRS) return false;
   x.tLS = iTime(_Symbol, _Period, sLS); x.pLS = pLS;
   x.tH  = iTime(_Symbol, _Period, sH);  x.pH  = pH;
   x.tRS = tRS;                          x.pRS = pRS;
   x.tN1 = iTime(_Symbol, _Period, s1);  x.pN1 = p1;
   x.tN2 = iTime(_Symbol, _Period, s2);  x.pN2 = p2;
   return true;
  }

//+------------------------------------------------------------------+
void Draw(HSSetup &x)
  {
   if(!DrawPattern) return;
   string p = "TWIHS_" + (x.dir == 1 ? "L_" : "S_") + TimeToString(x.tRS, TIME_DATE | TIME_MINUTES) + "_";
   color c = x.dir == 1 ? clrLimeGreen : clrTomato;
   ObjectCreate(0, p + "neck", OBJ_TREND, 0, x.tN1, x.pN1, x.tN2, x.pN2);
   ObjectSetInteger(0, p + "neck", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, p + "neck", OBJPROP_RAY_RIGHT, true);
   string nm[3] = {"LS", "HEAD", "RS"}; datetime tt[3]; double pp[3];
   tt[0] = x.tLS; tt[1] = x.tH; tt[2] = x.tRS; pp[0] = x.pLS; pp[1] = x.pH; pp[2] = x.pRS;
   for(int i = 0; i < 3; i++)
     {
      ObjectCreate(0, p + nm[i], OBJ_TEXT, 0, tt[i], pp[i]);
      ObjectSetString(0, p + nm[i], OBJPROP_TEXT, nm[i]);
      ObjectSetInteger(0, p + nm[i], OBJPROP_COLOR, c);
      ObjectSetInteger(0, p + nm[i], OBJPROP_ANCHOR, x.dir == 1 ? ANCHOR_UPPER : ANCHOR_LOWER);
     }
  }

//+------------------------------------------------------------------+
double CalcLots(int dir, double entry, double sl)
  {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(FixedLots > 0) return MathMin(FixedLots, MaxLots);
   double loss = 0;
   if(!OrderCalcProfit(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, loss) || loss >= 0)
      return 0;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lots = MathFloor(riskMoney / -loss / step) * step;
   lots = MathMin(MathMin(lots, MaxLots), vmax);
   if(lots < vmin)
     {
      PrintFormat("TWI HS: skip - min lot %.2f risks %.2f, over the %.1f%% limit (%.2f)", vmin, -loss * vmin, RiskPercent, riskMoney);
      return 0;
     }
   return NormalizeDouble(lots, 2);
  }

void TryEnter(HSSetup &x, double atr)
  {
   x.usedRS = x.tRS;   // one shot per pattern, whatever happens below
   x.armed  = false;
   if(HasPosition()) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints) { Print("TWI HS: skip - spread"); return; }
   double entry = x.dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double shoulder = StopMode == STOP_UNDER_BOTH ? (x.dir == 1 ? MathMin(x.pLS, x.pRS) : MathMax(x.pLS, x.pRS)) : x.pRS;
   double sl = x.dir == 1 ? shoulder - StopBufferATR * atr : shoulder + StopBufferATR * atr;
   int sH = iBarShift(_Symbol, _Period, x.tH);
   double depth = MathAbs(NeckAt(x.tN1, x.pN1, x.tN2, x.pN2, sH) - x.pH);
   double tp = NeckAt(x.tN1, x.pN1, x.tN2, x.pN2, 0) + x.dir * depth * TPFactor;
   double risk = MathAbs(entry - sl), reward = x.dir * (tp - entry);
   if(risk <= 0 || reward <= 0 || reward / risk < MinRR)
     { PrintFormat("TWI HS: skip - R:R %.2f under %.2f", risk > 0 ? reward / risk : 0, MinRR); return; }
   double lots = CalcLots(x.dir, entry, sl);
   if(lots <= 0) return;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, dg); tp = NormalizeDouble(tp, dg);
   bool ok = x.dir == 1 ? trade.Buy(lots, _Symbol, 0, sl, tp, "TWI HS inverse")
                        : trade.Sell(lots, _Symbol, 0, sl, tp, "TWI HS regular");
   if(ok)
     {
      posN1 = x.tN1; posP1 = x.pN1; posN2 = x.tN2; posP2 = x.pN2; posDir = x.dir;
      PrintFormat("TWI HS: %s %.2f @ %.5f SL %.5f TP %.5f (%.1fR)", x.dir == 1 ? "BUY" : "SELL", lots, entry, sl, tp, reward / risk);
     }
   else PrintFormat("TWI HS: order failed %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
void Step(HSSetup &x, double atr)
  {
   if(x.dir == 1 && Direction == DIR_SHORT_ONLY) return;
   if(x.dir == -1 && Direction == DIR_LONG_ONLY) return;
   // a newer pattern replaces the current one
   HSSetup y = x;
   if(FindPattern(y, atr) && y.tRS != x.tRS)
     {
      x = y; x.armed = true; x.pushSeen = false; x.neckBroken = false;
      x.pushExt = x.dir == 1 ? -DBL_MAX : DBL_MAX;
      // catch a push that already happened while the RS was being confirmed
      int sRS = iBarShift(_Symbol, _Period, x.tRS);
      for(int s = sRS - 1; s >= 2; s--)
        {
         double o = iOpen(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
         if(x.dir * (c - o) >= ImpulseATR * atr) x.pushSeen = true;
         if(x.pushSeen) x.pushExt = x.dir == 1 ? MathMax(x.pushExt, iHigh(_Symbol, _Period, s)) : MathMin(x.pushExt, iLow(_Symbol, _Period, s));
        }
      Draw(x);
      PrintFormat("TWI HS: %s pattern LS %.5f HEAD %.5f RS %.5f neck %.5f/%.5f", x.dir == 1 ? "inverse" : "regular", x.pLS, x.pH, x.pRS, x.pN1, x.pN2);
     }
   if(!x.armed) return;
   double o = iOpen(_Symbol, _Period, 1), h = iHigh(_Symbol, _Period, 1), l = iLow(_Symbol, _Period, 1), c = iClose(_Symbol, _Period, 1);
   int sRS = iBarShift(_Symbol, _Period, x.tRS);
   // invalidation: close beyond the right shoulder, or too old
   if((x.dir == 1 && c < x.pRS) || (x.dir == -1 && c > x.pRS) || sRS > MaxBarsAfterRS)
     { x.armed = false; x.usedRS = x.tRS; return; }
   double neck = NeckAt(x.tN1, x.pN1, x.tN2, x.pN2, 1);
   double rng = h - l;
   bool reject = rng > 0 && (x.dir == 1 ? (c > o && (c - l) >= RejectFrac * rng) : (c < o && (h - c) >= RejectFrac * rng));
   if(EntryMode == ENTRY_PULLBACK)
     {
      bool pushNow = x.dir * (c - o) >= ImpulseATR * atr;
      if(pushNow && !x.pushSeen) { x.pushSeen = true; x.pushExt = x.dir == 1 ? h : l; return; }
      if(!x.pushSeen) return;
      bool dipped = x.dir == 1 ? (l <= x.pushExt - PullbackATR * atr && l > x.pRS)
                               : (h >= x.pushExt + PullbackATR * atr && h < x.pRS);
      if(dipped && reject && !pushNow) { TryEnter(x, atr); return; }
      x.pushExt = x.dir == 1 ? MathMax(x.pushExt, h) : MathMin(x.pushExt, l);
     }
   else
     {
      if(!x.neckBroken) { if(x.dir * (c - neck) > 0) x.neckBroken = true; return; }
      bool touched = x.dir == 1 ? (l <= neck + RetestTolATR * atr) : (h >= neck - RetestTolATR * atr);
      if(touched && reject && x.dir * (c - neck) > 0) TryEnter(x, atr);
     }
  }

//+------------------------------------------------------------------+
void ManageBreakeven()
  {
   if(!BreakevenOnNeck || posDir == 0) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(posDir * (sl - open) >= 0) return;             // already at or past breakeven
      double neck = NeckAt(posN1, posP1, posN2, posP2, 1);
      if(posDir * (iClose(_Symbol, _Period, 1) - neck) > 0)
         if(trade.PositionModify(PositionGetInteger(POSITION_TICKET), NormalizeDouble(open, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), tp))
            Print("TWI HS: neckline closed through, stop to breakeven");
      return;
     }
   posDir = 0;   // position gone
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar) return;
   lastBar = t;
   if(Bars(_Symbol, _Period) < Lookback + PivotLen + PriorBars + 5) return;
   double atr = ATR1();
   if(atr <= 0) return;
   ManageBreakeven();
   Step(L, atr);
   Step(S, atr);
  }
//+------------------------------------------------------------------+
