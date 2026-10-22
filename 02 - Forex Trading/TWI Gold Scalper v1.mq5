//+------------------------------------------------------------------+
//|                                        TWI_Gold_Scalper_v1.mq5   |
//|  XAUUSD M5 trend-pullback scalper with Account Guard.            |
//|  Magic 260816. UNCOMPILED - compile in MetaEditor, test on demo. |
//|                                                                  |
//|  Rules (hard): every trade has a broker-side SL; one position at |
//|  a time; NO grid, NO martingale, NO averaging, NO doubling.      |
//|  The guard can only shrink size or block new entries.           |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- Strategy
input group "Strategy"
input ENUM_TIMEFRAMES SignalTF       = PERIOD_M5;  // signal timeframe
input int      FastEMA               = 20;         // M5 fast EMA (pullback line)
input int      SlowEMA               = 50;         // M5 slow EMA (trend)
input ENUM_TIMEFRAMES TrendTF        = PERIOD_H1;  // higher-timeframe trend
input int      TrendEMA              = 50;         // H1 EMA
input int      ATRPeriod             = 14;
input double   SLBufferATR           = 0.2;        // SL beyond signal candle, x ATR
input double   MinRiskATR            = 0.5;        // skip if SL distance < this x ATR
input double   MaxRiskATR            = 2.0;        // skip if SL distance > this x ATR
input double   TakeProfitR           = 1.5;        // TP in R
input int      TimeStopBars          = 12;         // close after N signal bars (0 = off)

input group "Trade management"
input bool     UseBreakeven          = true;
input double   BreakevenAtR          = 1.0;        // move SL to entry (+spread) at +1R
input bool     UseTrailing           = false;
input double   TrailStartR           = 1.0;
input double   TrailATR              = 1.0;        // trail distance x ATR

input group "Risk & sizing"
input double   RiskPercent           = 0.5;        // % equity risked per trade (max 2)
input int      StreakN               = 3;          // after N losses in a row ...
input double   StreakFactor          = 0.5;        // ... risk x this factor
input int      MaxTradesPerDay       = 4;

input group "Account Guard"
input double   DailyLossPct          = 2.0;        // pause to next server day (0 = off)
input double   WeeklyLossPct         = 5.0;        // pause to next server week (0 = off)
input double   PeakDDKillPct         = 15.0;       // kill switch vs balance high-water mark (0 = off)
input bool     HeadroomSizing        = true;       // a loss at SL can never cross the kill floor
input double   CommPerLot            = 7.0;        // round-turn commission estimate (headroom only)
input double   MarginSafetyPct       = 50.0;       // free margin after order >= this % of equity
input bool     GuardRearm            = false;      // set true -> OK -> back to false to re-arm after a trip

input group "Filters"
input double   MaxSpreadPoints       = 60;         // absolute cap (points)
input double   SpreadMedianMult      = 2.0;        // and <= this x recent median spread (0 = off)
input int      LondonStartMin        = 480;        // London session start, LONDON local minutes (08:00)
input int      LondonEndMin          = 720;        // 12:00
input int      NYStartMin            = 510;        // NY session start, NEW YORK local minutes (08:30)
input int      NYEndMin              = 720;        // 12:00
input int      ServerUTCOffsetHours  = 3;          // broker server time - UTC (summer), check your broker!
input bool     UseNewsFilter         = true;       // MT5 economic calendar, high-impact USD
input int      NewsMinutes           = 15;
input bool     NoFridayAfternoon     = true;       // no new entries Friday after NY noon
input bool     FridayClose           = true;       // flatten Friday at FridayCloseNYMin
input int      FridayCloseNYMin      = 900;        // 15:00 New York

input group "Misc"
input long     Magic                 = 260816;
input int      SlippagePoints        = 30;

CTrade trade;
int hFast, hSlow, hTrend, hATR;
datetime lastBar = 0;
string GV;                        // global-variable prefix (per login)
double spreadBuf[288]; int spreadN = 0, spreadI = 0;

//+------------------------------------------------------------------+
//| Time helpers: DST-aware London/New York local time from UTC      |
//+------------------------------------------------------------------+
datetime NthSunday(int year, int mon, int n)          // n=0 -> last Sunday
{
   MqlDateTime s; ZeroMemory(s); s.year = year; s.mon = mon; s.day = 1;
   datetime t = StructToTime(s);
   if(n == 0)
   {
      s.mon = mon + 1; if(s.mon > 12) { s.mon = 1; s.year++; }
      t = StructToTime(s) - 86400;                      // last day of month
      MqlDateTime d; TimeToStruct(t, d);
      return t - d.day_of_week * 86400;
   }
   MqlDateTime d; TimeToStruct(t, d);
   int add = (7 - d.day_of_week) % 7;
   return t + (add + 7 * (n - 1)) * 86400;
}
datetime UtcNow() { return TimeCurrent() - ServerUTCOffsetHours * 3600; }
int LocalMinutes(datetime utc, bool london)
{
   MqlDateTime u; TimeToStruct(utc, u);
   int off;
   if(london)
   {
      datetime a = NthSunday(u.year, 3, 0) + 3600, b = NthSunday(u.year, 10, 0) + 3600;
      off = (utc >= a && utc < b) ? 1 : 0;
   }
   else
   {
      datetime a = NthSunday(u.year, 3, 2) + 7 * 3600, b = NthSunday(u.year, 11, 1) + 6 * 3600;
      off = (utc >= a && utc < b) ? -4 : -5;
   }
   MqlDateTime l; TimeToStruct(utc + off * 3600, l);
   return l.hour * 60 + l.min;
}
int NYWeekday(datetime utc)
{
   MqlDateTime u; TimeToStruct(utc, u);
   datetime a = NthSunday(u.year, 3, 2) + 7 * 3600, b = NthSunday(u.year, 11, 1) + 6 * 3600;
   MqlDateTime l; TimeToStruct(utc + ((utc >= a && utc < b) ? -4 : -5) * 3600, l);
   return l.day_of_week;
}
datetime DayStart(datetime t)  { return t - (t % 86400); }
datetime WeekStart(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   int back = (d.day_of_week + 6) % 7;                 // Monday = 0
   return DayStart(t) - back * 86400;
}

//+------------------------------------------------------------------+
//| Account Guard (state survives restarts in global variables)      |
//+------------------------------------------------------------------+
double GGet(string k, double def) { return GlobalVariableCheck(GV + k) ? GlobalVariableGet(GV + k) : def; }
void   GSet(string k, double v)   { GlobalVariableSet(GV + k, v); }

void GuardInit()
{
   GV = "TGS_G_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_";
   if(GuardRearm || !GlobalVariableCheck(GV + "PEAK"))
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      GSet("PEAK", bal); GSet("PEAKT", (double)TimeCurrent()); GSet("TRIP", 0);
      Print("GUARD armed: peak=", DoubleToString(bal, 2));
   }
}
double GuardFloor() { return PeakDDKillPct > 0 ? GGet("PEAK", 0) * (1.0 - PeakDDKillPct / 100.0) : -DBL_MAX; }

void GuardTrip(string why)
{
   if(GGet("TRIP", 0) > 0) return;
   GSet("TRIP", 1);
   string m = "TWI Gold Scalper GUARD TRIPPED: " + why + ". No new trades until manual re-arm.";
   Print(m); Alert(m);
}

void GuardUpdate()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > GGet("PEAK", bal)) { GSet("PEAK", bal); GSet("PEAKT", (double)TimeCurrent()); }
   double fl = GuardFloor();
   if(PeakDDKillPct > 0 && AccountInfoDouble(ACCOUNT_EQUITY) < fl)
      GuardTrip("equity " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + " < floor " + DoubleToString(fl, 2));
   Comment("TWI Gold Scalper v1  |  guard ", (GGet("TRIP", 0) > 0 ? "TRIPPED" : "armed"),
           "  peak ", DoubleToString(GGet("PEAK", 0), 2), "  floor ", DoubleToString(fl, 2));
}

// realized P/L of our magic since 'from' (BUY/SELL deals only, so deposits are ignored)
double RealizedSince(datetime from, int &losses, int &trades)
{
   losses = 0; trades = 0; double sum = 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != Magic) continue;
      long ty = HistoryDealGetInteger(d, DEAL_TYPE);
      if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL) continue;
      long en = HistoryDealGetInteger(d, DEAL_ENTRY);
      double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
               + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      sum += p;
      if((en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY) && p < 0) losses++;
      if(en == DEAL_ENTRY_IN) trades++;                // entries (for the per-day cap)
   }
   return sum;
}

int LossStreak()
{
   datetime from = (datetime)GGet("PEAKT", 0);
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != Magic) continue;
      long en = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY) continue;
      double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
               + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      if(p < 0) n++; else break;
   }
   return n;
}

bool GuardAllowsNewTrade(string &why)
{
   if(GGet("TRIP", 0) > 0) { why = "guard tripped"; return false; }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   int l, n;
   double dayPL = RealizedSince(DayStart(TimeCurrent()), l, n);
   if(DailyLossPct > 0 && dayPL <= -(bal - dayPL) * DailyLossPct / 100.0) { why = "daily loss limit - paused to next day"; return false; }
   int entriesToday = 0, x;
   RealizedSince(DayStart(TimeCurrent()), x, entriesToday);
   if(MaxTradesPerDay > 0 && entriesToday >= MaxTradesPerDay) { why = "max trades per day"; return false; }
   double wkPL = RealizedSince(WeekStart(TimeCurrent()), l, n);
   if(WeeklyLossPct > 0 && wkPL <= -(bal - wkPL) * WeeklyLossPct / 100.0) { why = "weekly loss limit - paused to next week"; return false; }
   return true;
}

// risk-% lot size with step rounding, anti-streak, headroom and margin checks. Returns 0 = skip.
double GuardLots(ENUM_ORDER_TYPE type, double price, double sl)
{
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double pl = 0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, price, sl, pl) || pl >= 0) { Print("lot calc failed"); return 0; }
   double lossPerLot = -pl;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = MathMin(RiskPercent, 2.0);
   int st = LossStreak();
   if(StreakN > 0 && st >= StreakN) risk *= StreakFactor;
   double lots = MathFloor(eq * risk / 100.0 / lossPerLot / step) * step;
   if(HeadroomSizing && PeakDDKillPct > 0)
   {
      double room = AccountInfoDouble(ACCOUNT_BALANCE) - GuardFloor();
      double lotsH = MathFloor(room / (lossPerLot + CommPerLot) / step) * step;
      if(lotsH < minL) { GuardTrip("no headroom above kill floor for even the minimum lot"); return 0; }
      lots = MathMin(lots, lotsH);
   }
   if(lots < minL)
   {
      string m = "TWI Gold Scalper: min lot " + DoubleToString(minL, 2) + " would risk " +
                 DoubleToString(minL * lossPerLot / eq * 100.0, 2) + "% > allowed " + DoubleToString(risk, 2) + "% - HALTED (no trade).";
      Print(m); Alert(m);
      return 0;
   }
   lots = MathMin(lots, maxL);
   double mg = 0;
   while(lots >= minL)
   {
      if(!OrderCalcMargin(type, _Symbol, lots, price, mg)) return 0;
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) - mg >= eq * MarginSafetyPct / 100.0) break;
      lots -= step;
   }
   if(lots < minL) { Print("margin safety: skip"); return 0; }
   lots = NormalizeDouble(lots, 2);
   PrintFormat("SIZE eq=%.2f risk=%.2f%% streak=%d lossPerLot=%.2f lots=%.2f floor=%.2f", eq, risk, st, lossPerLot, lots, GuardFloor());
   return lots;
}

//+------------------------------------------------------------------+
//| Filters                                                          |
//+------------------------------------------------------------------+
bool InSession()
{
   datetime u = UtcNow();
   int lm = LocalMinutes(u, true), nm = LocalMinutes(u, false);
   return (lm >= LondonStartMin && lm < LondonEndMin) || (nm >= NYStartMin && nm < NYEndMin);
}
bool SpreadOK()
{
   double sp = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp > MaxSpreadPoints) return false;
   if(SpreadMedianMult <= 0 || spreadN < 20) return true;
   double tmp[]; ArrayResize(tmp, spreadN); ArrayCopy(tmp, spreadBuf, 0, 0, spreadN); ArraySort(tmp);
   return sp <= SpreadMedianMult * MathMax(tmp[spreadN / 2], 5.0);
}
bool NewsBlocked()
{
   if(!UseNewsFilter || MQLInfoInteger(MQL_TESTER)) return false;   // calendar is not available in the tester
   MqlCalendarValue v[];
   datetime now = TimeCurrent();
   if(CalendarValueHistory(v, now - NewsMinutes * 60, now + NewsMinutes * 60, NULL, "USD") <= 0) return false;
   for(int i = 0; i < ArraySize(v); i++)
   {
      MqlCalendarEvent e;
      if(CalendarEventById(v[i].event_id, e) && e.importance == CALENDAR_IMPORTANCE_HIGH) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double Buf(int h, int shift) { double b[1]; return CopyBuffer(h, 0, shift, 1, b) == 1 ? b[0] : EMPTY_VALUE; }

bool HasPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
      { ticket = t; return true; }
   }
   return false;
}

void ManagePosition(ulong t)
{
   if(!PositionSelectByTicket(t)) return;
   long   ty   = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double R = GlobalVariableCheck(GV + "R_" + IntegerToString((long)t)) ? GlobalVariableGet(GV + "R_" + IntegerToString((long)t)) : MathAbs(open - sl);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Friday close / time stop
   datetime u = UtcNow();
   if(FridayClose && NYWeekday(u) == 5 && LocalMinutes(u, false) >= FridayCloseNYMin) { trade.PositionClose(t); return; }
   if(TimeStopBars > 0 && TimeCurrent() - ot >= TimeStopBars * PeriodSeconds(SignalTF)) { trade.PositionClose(t); return; }
   if(R <= 0) return;

   double newSL = sl, atr = Buf(hATR, 1);
   if(ty == POSITION_TYPE_BUY)
   {
      double prof = bid - open;
      if(UseBreakeven && prof >= BreakevenAtR * R) newSL = MathMax(newSL, open + (ask - bid));
      if(UseTrailing && prof >= TrailStartR * R && atr != EMPTY_VALUE) newSL = MathMax(newSL, bid - TrailATR * atr);
      if(newSL > sl + _Point) trade.PositionModify(t, NormalizeDouble(newSL, dg), tp);
   }
   else
   {
      double prof = open - ask;
      if(UseBreakeven && prof >= BreakevenAtR * R) newSL = MathMin(newSL, open - (ask - bid));
      if(UseTrailing && prof >= TrailStartR * R && atr != EMPTY_VALUE) newSL = MathMin(newSL, ask + TrailATR * atr);
      if(newSL < sl - _Point) trade.PositionModify(t, NormalizeDouble(newSL, dg), tp);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(RiskPercent <= 0 || RiskPercent > 2.0) { Print("RiskPercent must be in (0, 2]"); return INIT_PARAMETERS_INCORRECT; }
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) Print("WARNING: designed for XAUUSD only");
   hFast  = iMA(_Symbol, SignalTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, SignalTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, TrendTF, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, SignalTF, ATRPeriod);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE || hATR == INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(SlippagePoints);
   GuardInit();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   IndicatorRelease(hFast); IndicatorRelease(hSlow); IndicatorRelease(hTrend); IndicatorRelease(hATR);
   Comment("");
}

void OnTick()
{
   GuardUpdate();
   ulong t = 0;
   bool has = HasPosition(t);
   if(has) ManagePosition(t);

   datetime bt = iTime(_Symbol, SignalTF, 0);
   if(bt == lastBar) return;                         // act once per new signal bar
   lastBar = bt;
   spreadBuf[spreadI] = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   spreadI = (spreadI + 1) % 288; if(spreadN < 288) spreadN++;

   if(has || HasPosition(t)) return;                 // one position at a time, never add
   if(!InSession()) return;
   datetime u = UtcNow();
   if(NoFridayAfternoon && NYWeekday(u) == 5 && LocalMinutes(u, false) >= 720) return;

   // closed-bar values (shift 1)
   double o = iOpen(_Symbol, SignalTF, 1), h = iHigh(_Symbol, SignalTF, 1), l = iLow(_Symbol, SignalTF, 1), c = iClose(_Symbol, SignalTF, 1);
   double f = Buf(hFast, 1), s = Buf(hSlow, 1), atr = Buf(hATR, 1), ht = Buf(hTrend, 1);
   double hc = iClose(_Symbol, TrendTF, 1);
   if(f == EMPTY_VALUE || s == EMPTY_VALUE || atr == EMPTY_VALUE || ht == EMPTY_VALUE || atr <= 0) return;

   int dir = 0;
   if(hc > ht && f > s && l <= f && c > f && c > o) dir = 1;
   if(hc < ht && f < s && h >= f && c < f && c < o) dir = -1;
   if(dir == 0) return;

   string why;
   if(!GuardAllowsNewTrade(why)) { Print("NO TRADE: ", why); return; }
   if(!SpreadOK())  { Print("NO TRADE: spread"); return; }
   if(NewsBlocked()) { Print("NO TRADE: news window"); return; }

   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = dir == 1 ? ask : bid;
   double sl = dir == 1 ? l - SLBufferATR * atr : h + SLBufferATR * atr;
   double R = (price - sl) * dir;
   if(R < MinRiskATR * atr || R > MaxRiskATR * atr) { Print("NO TRADE: SL distance out of range"); return; }
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(R <= minStop) { Print("NO TRADE: SL inside broker stop level"); return; }
   double tp = price + dir * TakeProfitR * R;
   ENUM_ORDER_TYPE ot = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lots = GuardLots(ot, price, sl);
   if(lots <= 0) return;

   sl = NormalizeDouble(sl, dg); tp = NormalizeDouble(tp, dg);
   bool ok = dir == 1 ? trade.Buy(lots, _Symbol, 0, sl, tp, "TGS v1") : trade.Sell(lots, _Symbol, 0, sl, tp, "TGS v1");
   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      ulong pt = 0;
      if(HasPosition(pt)) GlobalVariableSet(GV + "R_" + IntegerToString((long)pt), R);   // original 1R for BE/trail
      PrintFormat("ENTRY %s lots=%.2f price=%.2f sl=%.2f tp=%.2f R=%.2f", dir == 1 ? "BUY" : "SELL", lots, price, sl, tp, R);
   }
   else Print("Order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+
