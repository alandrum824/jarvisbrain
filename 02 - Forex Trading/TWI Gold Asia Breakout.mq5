//+------------------------------------------------------------------+
//|                                       TWI Gold Asia Breakout.mq5 |
//|  2026-10-12. Adam: "look at gold EA's all over the Internet see   |
//|  which ones are successful and start work from there. Build me a  |
//|  EA" -> "Gold".                                                   |
//|                                                                  |
//|  The Asian-range breakout (Aurum Range Breakout rules as          |
//|  published) passed gold_breakout_research.py on 2020-26 AAAFx     |
//|  data: 1,607 trades, +74.2R, PF 1.12, 6/7 years, beat the coin    |
//|  flip 100%; shorts earn as much as longs, so it isn't gold drift. |
//|                                                                  |
//|  Rules (all times GMT/UTC):                                       |
//|   Range : high/low of 00:00-05:00.                                |
//|   Filter: skip the day if the width is < 0.10 or > 0.80 x daily   |
//|           ATR(14) (yesterday's).                                  |
//|   05:00 : buy stop at high + 5% of width, sell stop at low - 5%,  |
//|           OCO. SL = the other order's price, TP = 1R.             |
//|   15:00 : cancel unfilled orders.  16:00: close the trade.        |
//|  One trade a day, hard SL on every order, no grid.               |
//|                                                                  |
//|  v1.01: RunMode = RUN_SHADOW (default) sends NO orders on a live |
//|  chart; it tracks the same trades virtually from live bid/ask    |
//|  and appends each to MQL5\Files\TWIGoldAsia_shadow.csv. The      |
//|  strategy tester always runs as LIVE.                            |
//|                                                                  |
//|  v1.02: Account Guard (from TWI Gold Scalper v1's chassis),      |
//|  LIVE/tester only. Daily loss >= 2% pauses to the next server    |
//|  day, weekly >= 5% to the next week; equity 15% under the peak   |
//|  balance trips a kill switch (Alert; survives restarts in global |
//|  variables; re-arm with GuardRearm). Headroom sizing so a stop   |
//|  can't cross the kill floor, >= 50% free margin, risk capped at  |
//|  2%, halved after 3 losses in a row (risk-% mode). If the min    |
//|  lot would over-risk: no trade + Alert. The guard only blocks    |
//|  new orders (and deletes unfilled ones on a trip); it never      |
//|  closes, adds to or hedges a position. Entry rules unchanged.    |
//|                                                                  |
//|  v1.03: optional Retest Sniper (UseRetestSniper, default OFF):   |
//|  after the first M5 close beyond the range, a limit at the       |
//|  broken edge, SL = range midpoint, TP = measured move; magic+1.  |
//|                                                                  |
//|  v1.04: optional FVG + Trend (FvgTrendMode, default OFF): ADD_ON |
//|  keeps the daily OCO and adds an A+ trade (magic+2); REPLACE_BASE|
//|  trades only the A+ setups.                                      |
//|  enter at the first M5 close beyond the range only if that bar   |
//|  left an FVG and the H1 (or H1+H4) swing structure agrees.       |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.04"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE  { LOTS_FIXED = 0, LOTS_RISK_PERCENT = 1 };
enum ENUM_TIME_MODE { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_RUN_MODE  { RUN_SHADOW = 0, RUN_LIVE = 1 };

input group "=== General ==="
input ENUM_RUN_MODE   RunMode                       = RUN_SHADOW; // SHADOW: no orders ever sent; virtual trades from live prices, logged to Files\TWIGoldAsia_shadow.csv (the tester always runs LIVE)
input long            Magic                         = 20261014;
input string          TradeComment                  = "TWI Gold Asia";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED;
input double          FixedLots                     = 0.01;
input double          RiskPercent                   = 0.5;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;      // allow the min lot if it overshoots risk by at most this %
input double          MaxRiskPerTradePct            = 0.0;       // fixed lots: skip a day whose SL risk exceeds this % of equity (0 = off)
input double          MaxSpreadToRisk               = 0.10;      // skip the day if the spread is more than this fraction of the stop
input bool            DebugMode                     = true;

input group "=== Range + orders (GMT) ==="
input int             RangeStartMin                 = 0;         // 00:00
input int             RangeEndMin                   = 300;       // 05:00, orders placed from here
input int             CancelMin                     = 900;       // 15:00, unfilled orders cancelled
input int             CloseMin                      = 960;       // 16:00, open trade closed
input double          EntryBufferPct                = 5.0;       // stop orders this % of the range width outside it
input double          TargetR                       = 1.0;
input int             DailyATRPeriod                = 14;
input double          MinRangeATR                   = 0.10;
input double          MaxRangeATR                   = 0.80;
input int             MinRangeBars                  = 200;       // M1 bars needed inside the range window

input group "=== Account Guard (LIVE + tester) ==="
input bool            UseGuard                      = true;
input double          DailyLossPct                  = 2.0;       // realized loss today >= this % -> pause to next server day (0 = off)
input double          WeeklyLossPct                 = 5.0;       // realized loss this week >= this % -> pause to next week (0 = off)
input double          PeakDDKillPct                 = 15.0;      // equity this % under the peak balance -> kill switch (0 = off)
input bool            HeadroomSizing                = true;      // a loss at the SL can never cross the kill floor
input double          MarginSafetyPct               = 50.0;      // free margin after the order >= this % of equity
input int             StreakN                       = 3;         // risk-% mode: after N losses in a row ...
input double          StreakFactor                  = 0.5;       // ... risk x this until a win or a new peak
input bool            GuardRearm                    = false;     // set true -> OK -> back to false to re-arm after a trip

input group "=== FVG + Trend mode (v1.04; LIVE + tester) ==="
enum ENUM_FVG_MODE { FVG_OFF = 0, FVG_ADD_ON = 1, FVG_REPLACE_BASE = 2 };
input ENUM_FVG_MODE   FvgTrendMode                  = FVG_OFF;   // ADD_ON: daily OCO breakout PLUS an A+ trade when the breakout bar leaves an FVG and structure agrees (replay +101R, 6/7 yrs); REPLACE_BASE: A+ trades only (~27/yr)
input int             TrendSwingStrength            = 3;         // fractal strength for the structure trend (higher highs + higher lows)
enum ENUM_TREND_TF { TREND_H1 = 0, TREND_H4 = 1, TREND_H1_AND_H4 = 2 };
input ENUM_TREND_TF   TrendTimeframes               = TREND_H1;  // H1 (best total: 183 tr, PF 1.43) or H1+H4 agree (best per trade: 66 tr, PF 1.51)

input group "=== Retest Sniper add-on (v1.03; LIVE + tester) ==="
input bool            UseRetestSniper               = false;     // after an M5 close beyond the range: limit at the broken edge, SL range mid, TP measured move
input long            SniperMagicOffset             = 1;         // sniper orders use Magic + this

input group "=== Clock ==="
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;         // TIME_FIXED_UTC only
input bool            ApplyAAAFxHistory             = true;      // AAAFx-only history fix; ignored automatically on any other broker
input datetime        LondonHistoryEnd              = D'2022.03.27 00:00';  // AAAFx server = London time before this
input datetime        UTC0HistoryEnd                = D'2026.03.07 00:00';  // AAAFx server = UTC+0 before this

CTrade   trade;
int      hDATR = INVALID_HANDLE;
bool     g_aaafx = false;
long     g_doneDay = 0;          // UTC day whose orders were already placed (or skipped)
// today's accepted range (set by PlaceDay once the ATR filter passes) for the Retest Sniper
long     g_rngDay = 0;
double   g_rHi = 0, g_rLo = 0;
int      g_snState = 0;          // 0 waiting for an M5 close beyond the range, 1 order placed/filled, 2 done for the day
datetime g_snLastBar = 0;
int      g_snPlaced = 0, g_snFills = 0;
CTrade   snTrade;
CTrade   apTrade;                // FVG+Trend add-on trades (Magic + 2)
long     ApMagic() { return Magic + 2; }
int      g_ftState = 2;          // FVG+Trend: 0 waiting for the breakout close, 2 done for the day
datetime g_ftLastBar = 0;
int      g_ftSignals = 0, g_ftTaken = 0, g_ftNoFvg = 0, g_ftNoTrend = 0;
long     SnMagic() { return Magic + SniperMagicOffset; }
int      g_days = 0, g_placed = 0, g_fills = 0, g_skipATR = 0, g_skipBars = 0, g_skipSpread = 0, g_skipLots = 0, g_unfilled = 0, g_skipGuard = 0;
bool     g_shadow = true;

// shadow (virtual) state: 0 none, 1 orders armed, 2 in a trade
int      s_state = 0, s_dir = 0;
double   s_bs, s_ss, s_lb, s_ls, s_entry, s_sl, s_tp, s_lots;
datetime s_fillTime;

void   Dbg(string s) { if(DebugMode) Print("[TWI GA] ", s); }
string P(double v)   { return DoubleToString(v, _Digits); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }

//====================================================================
// TIME: server -> UTC
//====================================================================
datetime NthSunday(int year, int month, int n)
  {
   datetime first = StringToTime(StringFormat("%04d.%02d.01", year, month));
   MqlDateTime f; TimeToStruct(first, f);
   int add = (7 - f.day_of_week) % 7;
   return first + (add + 7 * (n - 1)) * 86400;
  }
datetime LastSunday(int year, int month)
  {
   datetime nxt = month < 12 ? StringToTime(StringFormat("%04d.%02d.01", year, month + 1)) : StringToTime(StringFormat("%04d.01.01", year + 1));
   datetime last = nxt - 86400;
   MqlDateTime d; TimeToStruct(last, d);
   return last - d.day_of_week * 86400;
  }
int NYOffsetHours(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc, d);
   datetime s = NthSunday(d.year, 3, 2) + 7 * 3600;
   datetime e = NthSunday(d.year, 11, 1) + 6 * 3600;
   return (utc >= s && utc < e) ? -4 : -5;
  }
datetime ServerToUTC(datetime srv)
  {
   if(g_aaafx && srv < LondonHistoryEnd)
     {
      MqlDateTime d; TimeToStruct(srv, d);
      bool bst = srv >= LastSunday(d.year, 3) + 3600 && srv < LastSunday(d.year, 10) + 3600;
      return srv - (bst ? 3600 : 0);
     }
   if(g_aaafx && srv < UTC0HistoryEnd) return srv;
   if(TimeMode == TIME_NY_PLUS_7)
     {
      datetime ny = srv - 7 * 3600;
      return ny - NYOffsetHours(ny + 5 * 3600) * 3600;
     }
   return srv - ServerUTCOffsetHours * 3600;
  }
int  UTCMinutes(datetime srv) { MqlDateTime d; TimeToStruct(ServerToUTC(srv), d); return d.hour * 60 + d.min; }
long UTCDayKey(datetime srv)  { MqlDateTime d; TimeToStruct(ServerToUTC(srv), d); return (long)d.year * 10000 + d.mon * 100 + d.day; }
int  UTCDow(datetime srv)     { MqlDateTime d; TimeToStruct(ServerToUTC(srv), d); return d.day_of_week; }

//====================================================================
// ACCOUNT GUARD (state survives restarts in terminal global variables)
//====================================================================
string g_gv = "";
bool   GuardOn() { return UseGuard && !g_shadow; }
double GGet(string k, double def) { return GlobalVariableCheck(g_gv + k) ? GlobalVariableGet(g_gv + k) : def; }
void   GSet(string k, double v)   { GlobalVariableSet(g_gv + k, v); }

void GuardInit()
  {
   g_gv = "TGA_G_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(Magic) + "_";
   if(GuardRearm || !GlobalVariableCheck(g_gv + "PEAK"))
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      GSet("PEAK", bal); GSet("PEAKT", (double)TimeCurrent()); GSet("TRIP", 0);
      Print("[TWI GA] GUARD armed: peak balance ", DoubleToString(bal, 2));
     }
  }
double GuardFloor() { return PeakDDKillPct > 0 ? GGet("PEAK", 0) * (1.0 - PeakDDKillPct / 100.0) : -DBL_MAX; }

void GuardTrip(string why)
  {
   if(GGet("TRIP", 0) > 0) return;
   GSet("TRIP", 1);
   string msg = "TWI Gold Asia GUARD TRIPPED: " + why + ". No new orders until GuardRearm.";
   Print("[TWI GA] ", msg); Alert(msg);
   DeletePendings("guard trip");                  // unfilled orders are new trades; open positions are left alone
  }

void GuardUpdate()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > GGet("PEAK", bal)) { GSet("PEAK", bal); GSet("PEAKT", (double)TimeCurrent()); }
   if(PeakDDKillPct > 0 && GGet("TRIP", 0) == 0 && AccountInfoDouble(ACCOUNT_EQUITY) < GuardFloor())
      GuardTrip(StringFormat("equity %.2f < floor %.2f (%.0f%% under peak %.2f)", AccountInfoDouble(ACCOUNT_EQUITY), GuardFloor(), PeakDDKillPct, GGet("PEAK", 0)));
  }

datetime ServerDayStart(datetime t)  { return t - (t % 86400); }
datetime ServerWeekStart(datetime t) { MqlDateTime d; TimeToStruct(t, d); return ServerDayStart(t) - ((d.day_of_week + 6) % 7) * 86400; }

// realized P/L of this magic since 'from' (BUY/SELL deals only, so deposits don't count)
double RealizedSince(datetime from)
  {
   double sum = 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      long dm = HistoryDealGetInteger(d, DEAL_MAGIC); if(dm != Magic && dm != SnMagic() && dm != ApMagic()) continue;
      long ty = HistoryDealGetInteger(d, DEAL_TYPE);
      if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL) continue;
      sum += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
           + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   return sum;
  }

int LossStreak()
  {
   if(!HistorySelect((datetime)GGet("PEAKT", 0), TimeCurrent() + 60)) return 0;
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      long dm = HistoryDealGetInteger(d, DEAL_MAGIC); if(dm != Magic && dm != SnMagic() && dm != ApMagic()) continue;
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
   if(!GuardOn()) return true;
   if(GGet("TRIP", 0) > 0) { why = "guard tripped"; return false; }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double day = RealizedSince(ServerDayStart(TimeCurrent()));
   if(DailyLossPct > 0 && day <= -(bal - day) * DailyLossPct / 100.0) { why = "daily loss limit - paused to next day"; return false; }
   double wk = RealizedSince(ServerWeekStart(TimeCurrent()));
   if(WeeklyLossPct > 0 && wk <= -(bal - wk) * WeeklyLossPct / 100.0) { why = "weekly loss limit - paused to next week"; return false; }
   return true;
  }

//====================================================================
bool CalcLots(bool buy, double entry, double sl, double &lots, string &why)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   double perLot = 0;
   if(!OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, perLot) || MathAbs(perLot) <= 0) { why = "OrderCalcProfit failed"; return false; }
   perLot = MathAbs(perLot);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(LotMode == LOTS_FIXED) lots = FixedLots;
   else
     {
      double rp = MathMin(RiskPercent, 2.0);
      if(GuardOn() && StreakN > 0 && LossStreak() >= StreakN) rp *= StreakFactor;
      double riskMoney = eq * rp / 100.0;
      lots = MathFloor(riskMoney / perLot / step + 1e-9) * step;
      if(lots < minLot)
        {
         if(minLot * perLot <= riskMoney * (1.0 + RiskOvershootTolerancePercent / 100.0)) lots = minLot;
         else
           {
            why = StringFormat("min lot risks %.2f > %.2f budget (%.2f%%)", minLot * perLot, riskMoney, rp);
            if(GuardOn()) Alert("TWI Gold Asia: " + why + " - HALTED for today (no trade).");
            return false;
           }
        }
     }
   lots = MathMax(minLot, MathMin(maxLot, NormalizeDouble(MathRound(lots / step) * step, 8)));
   if(LotMode == LOTS_FIXED && MaxRiskPerTradePct > 0 && lots * perLot > eq * MaxRiskPerTradePct / 100.0)
     {
      why = StringFormat("risk %.2f > %.1f%% of equity", lots * perLot, MaxRiskPerTradePct);
      if(GuardOn()) Alert("TWI Gold Asia: " + why + " - HALTED for today (no trade).");
      return false;
     }
   if(GuardOn() && HeadroomSizing && PeakDDKillPct > 0)
     {
      double room = AccountInfoDouble(ACCOUNT_BALANCE) - GuardFloor();
      double lotsH = MathFloor(room / perLot / step + 1e-9) * step;
      if(lotsH < minLot) { GuardTrip("no headroom above the kill floor for even the minimum lot"); why = "no headroom"; return false; }
      lots = MathMin(lots, lotsH);
     }
   if(GuardOn() && MarginSafetyPct > 0)
     {
      double mg = 0;
      while(lots >= minLot)
        {
         if(!OrderCalcMargin(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, entry, mg)) { why = "OrderCalcMargin failed"; return false; }
         if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) - mg >= eq * MarginSafetyPct / 100.0) break;
         lots = NormalizeDouble(lots - step, 8);
        }
      if(lots < minLot) { why = "margin safety"; return false; }
     }
   return true;
  }

ulong MyPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) return t;
     }
   return 0;
  }

int DeletePendings(string why)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic && trade.OrderDelete(t)) n++;
     }
   if(n > 0) Dbg(StringFormat("deleted %d pending (%s)", n, why));
   return n;
  }

//====================================================================
// SHADOW: virtual orders from live bid/ask, nothing is ever sent
//====================================================================
void ShadowFill(int dir, double px)
  {
   s_dir = dir; s_entry = px; s_fillTime = TimeCurrent(); s_state = 2; g_fills++;
   s_sl = dir > 0 ? s_ss : s_bs;
   s_tp = NormPrice(px + dir * TargetR * MathAbs(px - s_sl));
   s_lots = dir > 0 ? s_lb : s_ls;
   Dbg(StringFormat("SHADOW %s filled @ %s  SL %s  TP %s", dir > 0 ? "BUY" : "SELL", P(px), P(s_sl), P(s_tp)));
  }

void ShadowClose(double px, string why)
  {
   double risk = MathAbs(s_entry - s_sl), R = risk > 0 ? s_dir * (px - s_entry) / risk : 0, money = 0;
   if(!OrderCalcProfit(s_dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, s_lots, s_entry, px, money)) money = 0;
   Dbg(StringFormat("SHADOW %s closed @ %s (%s): %+.2fR, %+.2f at %.2f lots", s_dir > 0 ? "BUY" : "SELL", P(px), why, R, money, s_lots));
   string fn = "TWIGoldAsia_shadow.csv";
   bool fresh = !FileIsExist(fn);
   int h = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      if(fresh) FileWrite(h, "symbol", "fill_server", "close_server", "side", "entry", "sl", "tp", "exit", "reason", "R", "money", "lots");
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, _Symbol, TimeToString(s_fillTime), TimeToString(TimeCurrent()), s_dir > 0 ? "BUY" : "SELL", P(s_entry), P(s_sl), P(s_tp), P(px), why,
                DoubleToString(R, 3), DoubleToString(money, 2), DoubleToString(s_lots, 2));
      FileClose(h);
     }
   s_state = 0;
  }

void ShadowTick(int m)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(s_state == 1)
     {
      if(m >= CancelMin) { s_state = 0; g_unfilled++; Dbg("SHADOW orders cancelled (15:00 GMT)"); return; }
      if(ask >= s_bs)      ShadowFill(1, MathMax(ask, s_bs));
      else if(bid <= s_ss) ShadowFill(-1, MathMin(bid, s_ss));
      return;
     }
   if(s_state != 2) return;
   double px = s_dir > 0 ? bid : ask;              // the side the trade would close on
   if(s_dir * (s_sl - px) >= 0)      ShadowClose(px, "SL");
   else if(s_dir * (px - s_tp) >= 0) ShadowClose(px, "TP");
   else if(m >= CloseMin)            ShadowClose(px, "16:00 GMT");
  }

//====================================================================
// 05:00 GMT: measure the range and place the OCO pair
//====================================================================
void PlaceDay()
  {
   g_days++;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, PERIOD_M1, 1, 600, r);
   if(got <= 0) { g_skipBars++; return; }
   long today = UTCDayKey(TimeCurrent());
   double hi = -DBL_MAX, lo = DBL_MAX; int n = 0;
   for(int i = 0; i < got; i++)
     {
      if(UTCDayKey(r[i].time) != today) continue;
      int m = UTCMinutes(r[i].time);
      if(m < RangeStartMin || m >= RangeEndMin) continue;
      hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); n++;
     }
   if(n < MinRangeBars) { g_skipBars++; Dbg(StringFormat("skip: only %d range bars", n)); return; }
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(hDATR, 0, 1, 1, a) < 1 || a[0] <= 0) { g_skipATR++; return; }
   double w = hi - lo;
   if(w < MinRangeATR * a[0] || w > MaxRangeATR * a[0])
     { g_skipATR++; Dbg(StringFormat("skip: range %s vs daily ATR %s", P(w), P(a[0]))); return; }
   g_rngDay = today; g_rHi = hi; g_rLo = lo; g_snState = 0;
   double bs = NormPrice(hi + EntryBufferPct / 100.0 * w), ss = NormPrice(lo - EntryBufferPct / 100.0 * w);
   double risk = bs - ss;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(MaxSpreadToRisk > 0 && (ask - bid) > MaxSpreadToRisk * risk) { g_skipSpread++; Dbg("skip: spread vs stop"); return; }
   double gap = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   double lb, ls; string why;
   if(!CalcLots(true, bs, ss, lb, why) || !CalcLots(false, ss, bs, ls, why)) { g_skipLots++; Dbg("skip: " + why); return; }
   if(g_shadow)
     {
      g_placed++;
      s_bs = bs; s_ss = ss; s_lb = lb; s_ls = ls; s_state = 1;
      Dbg(StringFormat("SHADOW range %s-%s (w %s, ATR %s): virtual BUY STOP %s / SELL STOP %s, TP %.1fR, lots %.2f", P(lo), P(hi), P(w), P(a[0]), P(bs), P(ss), TargetR, lb));
      if(ask >= bs - gap)      ShadowFill(1, ask);
      else if(bid <= ss + gap) ShadowFill(-1, bid);
      return;
     }
   if(FvgTrendMode != FVG_OFF) g_ftState = 0;
   if(FvgTrendMode == FVG_REPLACE_BASE) { Dbg(StringFormat("FVG+Trend mode: range %s-%s armed, waiting for an M5 close beyond it", P(lo), P(hi))); return; }
   string gwhy;
   if(!GuardAllowsNewTrade(gwhy)) { g_skipGuard++; Dbg("skip: " + gwhy); return; }
   // price already outside the range at placement: take that side at market (as the replay fills at the bar open)
   if(ask >= bs - gap)
     {
      double sl = ss, tp = NormPrice(ask + TargetR * (ask - ss));
      if(trade.Buy(lb, _Symbol, 0, sl, tp, TradeComment)) { g_placed++; g_fills++; Dbg("already above range -> BUY at market"); }
      return;
     }
   if(bid <= ss + gap)
     {
      double sl = bs, tp = NormPrice(bid - TargetR * (bs - bid));
      if(trade.Sell(ls, _Symbol, 0, sl, tp, TradeComment)) { g_placed++; g_fills++; Dbg("already below range -> SELL at market"); }
      return;
     }
   bool okb = trade.BuyStop(lb, bs, _Symbol, ss, NormPrice(bs + TargetR * risk), ORDER_TIME_GTC, 0, TradeComment);
   bool oks = trade.SellStop(ls, ss, _Symbol, bs, NormPrice(ss - TargetR * risk), ORDER_TIME_GTC, 0, TradeComment);
   if(okb || oks) g_placed++;
   if(!okb || !oks) { Dbg(StringFormat("order failed (%u %s) -> cancelling the pair", trade.ResultRetcode(), trade.ResultRetcodeDescription())); DeletePendings("pair incomplete"); return; }
   Dbg(StringFormat("range %s-%s (w %s, ATR %s): BUY STOP %s / SELL STOP %s, TP %.1fR", P(lo), P(hi), P(w), P(a[0]), P(bs), P(ss), TargetR));
  }

//====================================================================
// RETEST SNIPER (v1.03): after the first M5 close beyond today's range, a limit at the broken edge,
// SL = range midpoint, TP = edge + range width (measured move). One per day. LIVE + tester only.
// Replay (gold_sniper_research.py, 2020-26): +50.9R, beat coin 96%, 4/7 years alone; with the base
// breakout +125R, 5/7 years, coin 100% (combination chosen after the fact -> MT5 confirmation pending).
//====================================================================
ulong SnPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == SnMagic()) return t;
     }
   return 0;
  }

int SnDeletePendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == SnMagic() && snTrade.OrderDelete(t)) n++;
     }
   return n;
  }

void SniperTick(int m, long day)
  {
   ulong p = SnPosition();
   if(p > 0 && m >= CloseMin) { if(snTrade.PositionClose(p)) Dbg("sniper 16:00 GMT close"); }
   if(m >= CancelMin) { if(SnDeletePendings() > 0) Dbg("sniper limit cancelled (15:00 GMT)"); return; }
   if(g_rngDay != day || g_snState != 0 || m < RangeEndMin) return;
   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b == 0 || b == g_snLastBar) return;
   g_snLastBar = b;
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   int dir = c1 > g_rHi ? 1 : (c1 < g_rLo ? -1 : 0);
   if(dir == 0) return;
   g_snState = 1;                                      // one attempt per day from here
   string gwhy;
   if(!GuardAllowsNewTrade(gwhy)) { Dbg("sniper skip: " + gwhy); g_snState = 2; return; }
   double w = g_rHi - g_rLo, mid = (g_rHi + g_rLo) / 2.0;
   double edge = dir > 0 ? g_rHi : g_rLo;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormPrice(mid), tp = NormPrice(edge + dir * w);
   double lots; string why;
   bool atMarket = dir > 0 ? ask <= edge : bid >= edge;   // already back at/through the edge
   double entry = atMarket ? (dir > 0 ? ask : bid) : edge;
   if(!CalcLots(dir > 0, entry, sl, lots, why)) { Dbg("sniper skip: " + why); g_snState = 2; return; }
   bool ok;
   if(atMarket) ok = dir > 0 ? snTrade.Buy(lots, _Symbol, 0, sl, tp, TradeComment + " SNP") : snTrade.Sell(lots, _Symbol, 0, sl, tp, TradeComment + " SNP");
   else         ok = dir > 0 ? snTrade.BuyLimit(lots, NormPrice(edge), _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment + " SNP")
                             : snTrade.SellLimit(lots, NormPrice(edge), _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment + " SNP");
   if(ok) { g_snPlaced++; if(atMarket) g_snFills++; }
   Dbg(StringFormat("sniper %s %s %.2f @ %s  SL %s (mid)  TP %s (measured)%s", dir > 0 ? "BUY" : "SELL", atMarket ? "market" : "limit",
                    lots, P(entry), P(sl), P(tp), ok ? "" : StringFormat("  FAILED %u", snTrade.ResultRetcode())));
  }

//====================================================================
// FVG + TREND MODE (v1.04): Adam's filters on the breakout. Replay (gold_filters_research.py, 2020-26):
// 183 trades, +27.2R, +0.149R/trade (7x unfiltered), PF 1.43, 57% wins, 5/7 years, beat coin 100% AND
// beat random trade-skipping 100%. Entry at the first M5 close beyond the range, if that bar left an FVG
// in the trade direction and the H1 structure (last 2 confirmed swing highs AND lows) agrees.
//====================================================================
// +1 = H1 higher highs and higher lows, -1 = lower highs and lower lows, 0 = mixed (confirmed fractals only)
int StructureTrend(ENUM_TIMEFRAMES tf)
  {
   int k = TrendSwingStrength, need = 300;
   double hh[], ll[];
   ArraySetAsSeries(hh, true); ArraySetAsSeries(ll, true);
   if(CopyHigh(_Symbol, tf, 1, need, hh) < need || CopyLow(_Symbol, tf, 1, need, ll) < need) return 0;
   double sh[2], sl[2]; int nh = 0, nl = 0;
   for(int i = k; i < need - k && (nh < 2 || nl < 2); i++)       // i = 0 is the last closed H1 bar; newest swings first
     {
      bool isH = true, isL = true;
      for(int j = 1; j <= k; j++)
        {
         if(!(hh[i] > hh[i + j]) || !(hh[i] >= hh[i - j])) isH = false;
         if(!(ll[i] < ll[i + j]) || !(ll[i] <= ll[i - j])) isL = false;
        }
      if(isH && nh < 2) sh[nh++] = hh[i];
      if(isL && nl < 2) sl[nl++] = ll[i];
     }
   if(nh < 2 || nl < 2) return 0;
   if(sh[0] > sh[1] && sl[0] > sl[1]) return 1;                    // [0] = newest
   if(sh[0] < sh[1] && sl[0] < sl[1]) return -1;
   return 0;
  }

void FvgTrendTick(int m, long day)
  {
   if(g_rngDay != day || g_ftState != 0 || m < RangeEndMin) return;
   if(m >= CancelMin) { g_ftState = 2; return; }
   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b == 0 || b == g_ftLastBar) return;
   g_ftLastBar = b;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, PERIOD_M5, 1, 3, r) < 3) return;        // r[0] = breakout candidate (last closed), r[2] two bars before
   int dir = r[0].close > g_rHi ? 1 : (r[0].close < g_rLo ? -1 : 0);
   if(dir == 0) return;
   g_ftState = 2; g_ftSignals++;                                   // first close beyond the range decides the day
   bool fvg = dir > 0 ? r[0].low > r[2].high : r[0].high < r[2].low;
   if(!fvg) { g_ftNoFvg++; Dbg("FVG+Trend: breakout without an FVG -> no trade"); return; }
   int t1 = StructureTrend(PERIOD_H1), t4 = StructureTrend(PERIOD_H4);
   bool trendOk = TrendTimeframes == TREND_H1 ? t1 == dir : (TrendTimeframes == TREND_H4 ? t4 == dir : (t1 == dir && t4 == dir));
   if(!trendOk) { g_ftNoTrend++; Dbg(StringFormat("FVG+Trend: structure H1 %d / H4 %d disagrees with %s -> no trade", t1, t4, dir > 0 ? "BUY" : "SELL")); return; }
   string gwhy;
   if(!GuardAllowsNewTrade(gwhy)) { Dbg("FVG+Trend skip: " + gwhy); return; }
   double w = g_rHi - g_rLo;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = dir > 0 ? ask : bid;
   double sl = NormPrice(dir > 0 ? g_rLo - EntryBufferPct / 100.0 * w : g_rHi + EntryBufferPct / 100.0 * w);
   double risk = dir * (entry - sl);
   if(risk <= 0) return;
   if(MaxSpreadToRisk > 0 && (ask - bid) > MaxSpreadToRisk * risk) { Dbg("FVG+Trend skip: spread vs stop"); return; }
   double tp = NormPrice(entry + dir * TargetR * risk);
   double lots; string why;
   if(!CalcLots(dir > 0, entry, sl, lots, why)) { Dbg("FVG+Trend skip: " + why); return; }
   CTrade *tt = FvgTrendMode == FVG_ADD_ON ? GetPointer(apTrade) : GetPointer(trade);
   bool ok = dir > 0 ? tt.Buy(lots, _Symbol, 0, sl, tp, TradeComment + " A+") : tt.Sell(lots, _Symbol, 0, sl, tp, TradeComment + " A+");
   if(ok) { g_ftTaken++; g_fills++; }
   Dbg(StringFormat("FVG+Trend A+ %s %.2f @ %s  SL %s  TP %s%s", dir > 0 ? "BUY" : "SELL", lots, P(entry), P(sl), P(tp), ok ? "" : StringFormat("  FAILED %u", tt.ResultRetcode())));
  }

//====================================================================
int OnInit()
  {
   if(RangeEndMin <= RangeStartMin || CancelMin <= RangeEndMin || CloseMin < CancelMin || TargetR <= 0) { Print("[TWI GA] bad inputs"); return INIT_PARAMETERS_INCORRECT; }
   hDATR = iATR(_Symbol, PERIOD_D1, DailyATRPeriod);
   if(hDATR == INVALID_HANDLE) { Print("[TWI GA] ATR handle failed"); return INIT_FAILED; }
   string broker = AccountInfoString(ACCOUNT_COMPANY) + " " + AccountInfoString(ACCOUNT_SERVER);
   StringToUpper(broker);
   g_aaafx = ApplyAAAFxHistory && StringFind(broker, "AAAFX") >= 0;
   g_shadow = RunMode == RUN_SHADOW && !MQLInfoInteger(MQL_TESTER);
   if(g_shadow) Print("[TWI GA] SHADOW MODE: no orders will be sent. Virtual trades -> MQL5\\Files\\TWIGoldAsia_shadow.csv");
   if(GuardOn())
     {
      GuardInit();
      PrintFormat("[TWI GA] guard: daily %.1f%%, weekly %.1f%%, kill %.1f%% under peak (floor %.2f), %s", DailyLossPct, WeeklyLossPct, PeakDDKillPct,
                  GuardFloor(), GGet("TRIP", 0) > 0 ? "TRIPPED (set GuardRearm to re-arm)" : "armed");
     }
   trade.SetExpertMagicNumber(Magic);
   trade.SetTypeFillingBySymbol(_Symbol);
   snTrade.SetExpertMagicNumber(SnMagic());
   apTrade.SetExpertMagicNumber(ApMagic());
   apTrade.SetTypeFillingBySymbol(_Symbol);
   snTrade.SetTypeFillingBySymbol(_Symbol);
   if(UseRetestSniper && g_shadow) Print("[TWI GA] Retest Sniper is LIVE/tester-only; it does not run in SHADOW mode");
   Dbg(StringFormat("init %s, range %02d:%02d-%02d:%02d GMT, cancel %02d:%02d, close %02d:%02d, AAAFx clock %s", _Symbol,
                    RangeStartMin / 60, RangeStartMin % 60, RangeEndMin / 60, RangeEndMin % 60, CancelMin / 60, CancelMin % 60,
                    CloseMin / 60, CloseMin % 60, g_aaafx ? "on" : "off"));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Print(StringFormat("[TWI GA] days %d | placed %d | fills %d | unfilled %d | skipped: ATR %d, bars %d, spread %d, lots %d, guard %d | guard %s | sniper placed %d",
                      g_days, g_placed, g_fills, g_unfilled, g_skipATR, g_skipBars, g_skipSpread, g_skipLots, g_skipGuard,
                      GuardOn() ? (GGet("TRIP", 0) > 0 ? "TRIPPED" : "armed") : "off", g_snPlaced));
   if(hDATR != INVALID_HANDLE) IndicatorRelease(hDATR);
  }

void OnTradeTransaction(const MqlTradeTransaction &tx, const MqlTradeRequest &rq, const MqlTradeResult &rs)
  {
   // OCO: the first stop to fill cancels the other
   if(tx.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(tx.deal) && HistoryDealGetInteger(tx.deal, DEAL_MAGIC) == Magic
      && HistoryDealGetInteger(tx.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
     {
      if(DeletePendings("OCO") > 0) g_fills++;
     }
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   int m = UTCMinutes(now);
   int dow = UTCDow(now);
   if(g_shadow)
     {
      ShadowTick(m);
      long sday = UTCDayKey(now);
      if(s_state != 0 || sday == g_doneDay || dow == 0 || dow == 6 || m < RangeEndMin || m >= CancelMin) return;
      g_doneDay = sday;
      PlaceDay();
      return;
     }
   if(GuardOn()) GuardUpdate();
   if(UseRetestSniper) SniperTick(m, UTCDayKey(now));
   ulong t = MyPosition();
   if(FvgTrendMode == FVG_REPLACE_BASE && t == 0) FvgTrendTick(m, UTCDayKey(now));
   if(FvgTrendMode == FVG_ADD_ON)
     {
      for(int i = PositionsTotal() - 1; i >= 0 && m >= CloseMin; i--)
        {
         ulong pt = PositionGetTicket(i);
         if(pt > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == ApMagic() && apTrade.PositionClose(pt)) Dbg("A+ 16:00 GMT close");
        }
      FvgTrendTick(m, UTCDayKey(now));
     }
   if(t > 0 && m >= CloseMin) { if(trade.PositionClose(t)) Dbg("16:00 GMT close"); }
   if(m >= CancelMin && DeletePendings("15:00 GMT cancel") > 0) g_unfilled++;
   if(t > 0) return;
   long day = UTCDayKey(now);
   if(day == g_doneDay || dow == 0 || dow == 6 || m < RangeEndMin || m >= CancelMin) return;
   g_doneDay = day;
   PlaceDay();
  }
//+------------------------------------------------------------------+
