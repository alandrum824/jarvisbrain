//+------------------------------------------------------------------+
//|                                              TWI NAS100 ORB.mq5 |
//|  Built 2026-10-22 from the ORB family survey (orb_family_         |
//|  research.py, NAS100 2022-26 M1 replay, coin-flip control, train  |
//|  to 2024 / holdout 2025-26). See TWI NAS100 ORB.md.               |
//|                                                                  |
//|  One trade per New York day at the 09:30 cash open:               |
//|   1. Box    - high/low of the first BoxMinutes M1 bars from 09:30.|
//|   2. Entry  - ENTRY_BREAK: first touch of an edge until LastEntry,|
//|               at market, in the direction of the touch.           |
//|               ENTRY_MIDPOINT: after that first touch, a limit at  |
//|               the box midpoint in the touch direction until       |
//|               LastEntry.                                          |
//|               ENTRY_FIRST_CANDLE: direction of the box candle     |
//|               itself (close vs 09:30 open), at market when the    |
//|               box closes; body < MinBodyPct of the box = no trade.|
//|   3. SL     - the opposite side of the box. TP = TargetR x risk,  |
//|               or none (TargetR 0) and the trade runs to FlatTime. |
//|   4. Flat   - everything closed / deleted at FlatTime (15:59 NY). |
//|  Optional filters: TREND (yesterday's 15:59 close vs the SMA of   |
//|  the last TrendSessions closes) and GAP (09:30 open vs yesterday's|
//|  close); a touch against them ends the day.                       |
//|                                                                  |
//|  Safety chassis (EA Build Prompt - What Works): risk % capped at  |
//|  2, halved after HalveAfterLosses straight losses; daily / weekly |
//|  realized-loss pause; kill switch at KillSwitchDDPct below the    |
//|  peak balance (persisted, manual re-arm); a stop-out can never    |
//|  cross the kill floor; a min lot that over-risks is skipped with  |
//|  an alert; positions found by magic + symbol; SHADOW mode default |
//|  on live charts (virtual trades to a CSV, no orders).             |
//|  Clock: NY+7 server (AAAFx), UTC+0 history before 2026-03-07.     |
//|  v1.01 (2026-10-22): UseTrendFilter default false - the no-filter |
//|  midpoint/hold config is 5/5 years in replay and MT5 (+98R), the  |
//|  filtered one 4/5 and flat in 2026. Nothing else changed.         |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_ENTRY_MODE { ENTRY_BREAK, ENTRY_MIDPOINT, ENTRY_FIRST_CANDLE };
enum ENUM_LOT_MODE   { LOTS_FIXED, LOTS_RISK_PERCENT };
enum ENUM_TIME_MODE  { TIME_NY_PLUS_7, TIME_FIXED_UTC };

input group "=== General ==="
input long            MagicNumber          = 20261022;
input string          TradeComment         = "TWI NAS100 ORB";
input bool            ShadowMode           = true;       // live charts: virtual trades logged to CSV, no orders (ignored in the tester)
input ENUM_LOT_MODE   LotMode              = LOTS_RISK_PERCENT;
input double          FixedLots            = 0.1;
input double          RiskPercent          = 1.0;        // capped at 2
input int             MaxSpreadPoints      = 0;          // 0 = off
input int             MaxDeviationPoints   = 50;
input bool            DebugMode            = true;

input group "=== Strategy ==="
input ENUM_ENTRY_MODE EntryMode            = ENTRY_MIDPOINT;
input int             BoxMinutes           = 30;
input string          SessionStart         = "09:30";    // New York time
input string          LastEntry            = "12:00";
input string          FlatTime             = "15:59";
input double          TargetR              = 0.0;        // 0 = no target, hold to FlatTime
input double          MinBodyPct           = 10.0;       // ENTRY_FIRST_CANDLE only

input group "=== Filters ==="
input bool            UseTrendFilter       = false;
input int             TrendSessions        = 20;
input bool            UseGapFilter         = false;

input group "=== Trade days ==="
input bool            TradeMonday          = true;
input bool            TradeTuesday         = true;
input bool            TradeWednesday       = true;
input bool            TradeThursday        = true;
input bool            TradeFriday          = true;

input group "=== Account guard ==="
input double          DailyLossPct         = 2.0;        // pause for the day after this realized loss
input double          WeeklyLossPct        = 5.0;        // pause for the week
input double          KillSwitchDDPct      = 15.0;       // halt below the peak balance by this much
input int             HalveAfterLosses     = 3;          // risk halved after this many straight losses (0 = off)
input bool            ResetKillSwitch      = false;      // set true once to re-arm after a kill, then back to false

input group "=== Clock ==="
input ENUM_TIME_MODE  TimeMode             = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours = 3;
input bool            ApplyUTC0History     = true;       // AAAFx-only history fix
input datetime        UTC0HistoryEnd       = D'2026.03.07 00:00';

//--- state ----------------------------------------------------------
enum ENUM_DAY_STATE { D_OFF, D_WAIT_BOX, D_WATCH, D_PENDING, D_DONE };
ENUM_DAY_STATE g_state = D_OFF;
datetime g_nyDate = 0, g_tStart, g_tBoxEnd, g_tLast, g_tFlat;
double   g_hi, g_lo, g_open, g_trend, g_gap;
int      g_startMin, g_lastMin, g_flatMin;
bool     g_useUTC0 = false, g_shadow = false;
string   g_gv;
int      g_dir = 0;

// real position
ulong    g_pos = 0;
double   g_riskMoney = 0;
// virtual (shadow) position / pending
bool     v_open = false, v_pend = false;
int      v_dir = 0;
double   v_entry, v_sl, v_tp, v_lim;
datetime v_time;

// stats
int      st_trades = 0, st_wins = 0, st_blockTrend = 0, st_blockGap = 0, st_noTouch = 0, st_noFill = 0, st_doji = 0,
         st_skipSpread = 0, st_skipRisk = 0, st_guard = 0, st_noBars = 0, st_orderFail = 0;
double   st_sumR = 0, st_gp = 0, st_gl = 0;

void Dbg(string m) { if(DebugMode) Print("[NAS100 ORB] ", m); }
string P(double p) { return DoubleToString(p, _Digits); }
double NP(double p) { return NormalizeDouble(p, _Digits); }

int ParseHHMM(string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return -1;
   int h = (int)StringToInteger(parts[0]), m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
  }

//====================================================================
// TIME - server <-> New York (same as TWI ORB Momentum)
//====================================================================
datetime NthSunday(int year, int month, int n)
  {
   datetime first = StringToTime(StringFormat("%04d.%02d.01", year, month));
   MqlDateTime f; TimeToStruct(first, f);
   int add = (7 - f.day_of_week) % 7;
   return first + (add + 7 * (n - 1)) * 86400;
  }
int NYOffsetHours(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc, d);
   datetime s = NthSunday(d.year, 3, 2) + 7 * 3600;
   datetime e = NthSunday(d.year, 11, 1) + 6 * 3600;
   return (utc >= s && utc < e) ? -4 : -5;
  }
datetime ServerToNY(datetime srv)
  {
   if(g_useUTC0 && srv < UTC0HistoryEnd) return srv + NYOffsetHours(srv) * 3600;
   if(TimeMode == TIME_NY_PLUS_7) return srv - 7 * 3600;
   datetime utc = srv - ServerUTCOffsetHours * 3600;
   return utc + NYOffsetHours(utc) * 3600;
  }
datetime NYToServer(datetime ny)
  {
   if(ServerToNY(ny + 7 * 3600) == ny) return ny + 7 * 3600;
   for(int k = -14; k <= 14; k++) { datetime s = ny + k * 3600; if(ServerToNY(s) == ny) return s; }
   return 0;
  }

//====================================================================
// DATA
//====================================================================
// close of the 15:59 NY M1 bar of an NY date (0 if that bar is missing)
double SessionClose(datetime nyDate)
  {
   datetime srv = NYToServer(nyDate + g_flatMin * 60);
   if(srv == 0) return 0;
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M1, srv, 1, r) != 1) return 0;
   if(r[0].time < srv - 300) return 0;          // nothing traded near the close that day
   return r[0].close;
  }

// yesterday's close and the SMA of the last TrendSessions closes (weekdays with a close bar)
bool PriorCloses(datetime nyDate, double &yClose, double &sma)
  {
   double c[]; ArrayResize(c, 0);
   for(int k = 1; k <= 60 && ArraySize(c) < MathMax(TrendSessions, 1); k++)
     {
      datetime d = nyDate - k * 86400;
      MqlDateTime t; TimeToStruct(d, t);
      if(t.day_of_week == 0 || t.day_of_week == 6) continue;
      double x = SessionClose(d);
      if(x <= 0) continue;
      int n = ArraySize(c); ArrayResize(c, n + 1); c[n] = x;
     }
   if(ArraySize(c) < MathMax(TrendSessions, 1)) return false;
   yClose = c[0]; sma = 0;
   for(int i = 0; i < TrendSessions; i++) sma += c[i];
   sma /= TrendSessions;
   return true;
  }

//====================================================================
// POSITIONS / ORDERS (by magic + symbol, never PositionSelect(_Symbol))
//====================================================================
ulong OurPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) return tk;
     }
   return 0;
  }
void DeleteOurOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber) trade.OrderDelete(tk);
     }
  }
int OurOrders()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber) n++;
     }
   return n;
  }

void AddStat(double R, double net)
  {
   st_trades++; st_sumR += R;
   if(net > 0) { st_wins++; st_gp += net; } else st_gl -= net;
  }

void RecordClosed()
  {
   double net = 0;
   if(HistorySelectByPosition(g_pos))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
        }
   double R = g_riskMoney > 0 ? net / g_riskMoney : 0;
   AddStat(R, net);
   Dbg(StringFormat("CLOSED %I64u net $%.2f R %.2f", g_pos, net, R));
   g_pos = 0; g_riskMoney = 0;
  }

//====================================================================
// ACCOUNT GUARD
//====================================================================
void GVSet(string k, double v) { GlobalVariableSet(g_gv + k, v); }
double GVGet(string k, double def) { return GlobalVariableCheck(g_gv + k) ? GlobalVariableGet(g_gv + k) : def; }

double RealizedSince(datetime from)
  {
   double pl = 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      pl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   return pl;
  }

// straight losing trades, newest first (closing deals of our magic over the last 60 days)
int LossStreak()
  {
   if(!HistorySelect(TimeCurrent() - 60 * 86400, TimeCurrent() + 60)) return 0;
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double net = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
      if(net < 0) n++; else break;
     }
   return n;
  }

double KillFloor() { return GVGet("peak", AccountInfoDouble(ACCOUNT_BALANCE)) * (1.0 - KillSwitchDDPct / 100.0); }

void GuardTick()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal > GVGet("peak", 0)) GVSet("peak", bal);
   if(GVGet("kill", 0) == 0 && eq <= KillFloor())
     {
      GVSet("kill", 1);
      string m = StringFormat("KILL SWITCH: equity %.2f <= %.2f (%.1f%% below peak %.2f) - closed and halted; re-arm with ResetKillSwitch", eq, KillFloor(), KillSwitchDDPct, GVGet("peak", 0));
      Print(m);
      if(!MQLInfoInteger(MQL_TESTER)) { Alert("TWI NAS100 ORB: ", m); SendNotification("TWI NAS100 ORB: " + m); }
     }
   if(GVGet("kill", 0) != 0)
     {
      ulong p = OurPosition();
      if(p != 0) trade.PositionClose(p);
      if(OurOrders() > 0) DeleteOurOrders();
     }
  }

// true = entries allowed today
bool GuardAllows(string &why)
  {
   if(GVGet("kill", 0) != 0) { why = "kill switch"; return false; }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   datetime dayStart = NYToServer(g_nyDate);
   MqlDateTime t; TimeToStruct(g_nyDate, t);
   datetime weekStart = NYToServer(g_nyDate - ((t.day_of_week + 6) % 7) * 86400);
   double dpl = RealizedSince(dayStart), wpl = RealizedSince(weekStart);
   if(dpl < 0 && -dpl >= DailyLossPct / 100.0 * (bal - dpl)) { why = StringFormat("daily loss %.2f", dpl); return false; }
   if(wpl < 0 && -wpl >= WeeklyLossPct / 100.0 * (bal - wpl)) { why = StringFormat("weekly loss %.2f", wpl); return false; }
   return true;
  }

double NormLots(double l, double step) { return NormalizeDouble(MathFloor(l / step + 1e-9) * step, 8); }

bool ComputeLots(int d, double entry, double sl, double &lots, string &why)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   ENUM_ORDER_TYPE ot = d > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double pl1 = 0;
   if(!OrderCalcProfit(ot, _Symbol, 1.0, entry, sl, pl1) || MathAbs(pl1) <= 0) { why = "OrderCalcProfit failed"; return false; }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double rp = MathMin(RiskPercent, 2.0);
   if(HalveAfterLosses > 0 && LossStreak() >= HalveAfterLosses) rp *= 0.5;
   double riskCap = eq * rp / 100.0;
   if(LotMode == LOTS_FIXED) lots = NormLots(FixedLots, step);
   else lots = NormLots(riskCap / MathAbs(pl1), step);
   if(lots > maxLot) lots = maxLot;
   if(lots < minLot)
     {
      if(LotMode == LOTS_RISK_PERCENT && MathAbs(pl1) * minLot > riskCap * 1.1)
        { why = StringFormat("min lot %.2f risks %.2f > %.2f%% cap %.2f", minLot, MathAbs(pl1) * minLot, rp, riskCap); return false; }
      lots = minLot;
     }
   // headroom: a stop-out must never cross the kill floor
   double room = eq - KillFloor();
   if(MathAbs(pl1) * lots > room)
     {
      double fit = room > 0 ? NormLots(room / MathAbs(pl1), step) : 0;
      if(fit < minLot) { why = StringFormat("no headroom above the kill floor (%.2f left)", room); return false; }
      lots = fit;
     }
   return true;
  }

//====================================================================
// SHADOW (virtual) trades
//====================================================================
void ShadowLog(string what, double exitPx)
  {
   double risk = MathAbs(v_entry - v_sl);
   double R = risk > 0 ? v_dir * (exitPx - v_entry) / risk : 0;
   AddStat(R, R);
   int h = FileOpen("TWI_NAS100_ORB_shadow.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) { Print("shadow CSV open failed ", GetLastError()); return; }
   if(FileSize(h) == 0) FileWrite(h, "ny_date", "mode", "dir", "entry_time", "entry", "sl", "tp", "exit", "exit_reason", "R");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(g_nyDate, TIME_DATE), EnumToString(EntryMode), v_dir > 0 ? "BUY" : "SELL", TimeToString(v_time),
             P(v_entry), P(v_sl), v_tp > 0 ? P(v_tp) : "-", P(exitPx), what, DoubleToString(R, 3));
   FileClose(h);
   Dbg(StringFormat("SHADOW %s closed (%s) at %s  R %.2f", v_dir > 0 ? "BUY" : "SELL", what, P(exitPx), R));
   v_open = false;
  }

void ShadowTick(datetime now)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(v_pend)
     {
      bool fill = v_dir > 0 ? ask <= v_lim : bid >= v_lim;
      if(fill) { v_pend = false; v_open = true; v_entry = v_lim; v_time = now; Dbg(StringFormat("SHADOW limit filled %s", P(v_lim))); }
     }
   if(!v_open) return;
   double px = v_dir > 0 ? bid : ask;
   if(v_dir * (px - v_sl) <= 0) ShadowLog("SL", v_sl);
   else if(v_tp > 0 && v_dir * (px - v_tp) >= 0) ShadowLog("TP", v_tp);
  }

//====================================================================
// DAY LOGIC
//====================================================================
void NewDay(datetime nyDate)
  {
   g_nyDate = nyDate; g_state = D_OFF; g_dir = 0; v_pend = false;
   MqlDateTime t; TimeToStruct(nyDate, t);
   bool on = t.day_of_week == 1 ? TradeMonday : t.day_of_week == 2 ? TradeTuesday : t.day_of_week == 3 ? TradeWednesday :
             t.day_of_week == 4 ? TradeThursday : t.day_of_week == 5 ? TradeFriday : false;
   if(!on) return;
   g_tStart  = NYToServer(nyDate + g_startMin * 60);
   g_tBoxEnd = NYToServer(nyDate + (g_startMin + BoxMinutes) * 60);
   g_tLast   = NYToServer(nyDate + g_lastMin * 60);
   g_tFlat   = NYToServer(nyDate + g_flatMin * 60);
   if(g_tStart == 0 || g_tBoxEnd == 0 || g_tLast == 0 || g_tFlat == 0) { Dbg("NY->server conversion failed"); return; }
   g_state = D_WAIT_BOX;
  }

void BuildBox()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, g_tStart, g_tBoxEnd - 1, r);
   if(n < BoxMinutes * 6 / 10 || r[0].time > g_tStart + 120) { st_noBars++; g_state = D_DONE; Dbg(StringFormat("only %d box bars - skipped", n)); return; }
   g_hi = r[0].high; g_lo = r[0].low; g_open = r[0].open;
   for(int i = 1; i < n; i++) { g_hi = MathMax(g_hi, r[i].high); g_lo = MathMin(g_lo, r[i].low); }
   double boxClose = r[n - 1].close;
   if(g_hi <= g_lo) { g_state = D_DONE; return; }
   g_trend = 0; g_gap = 0;
   if(UseTrendFilter || UseGapFilter)
     {
      double yc, sma;
      if(!PriorCloses(g_nyDate, yc, sma)) { g_state = D_DONE; Dbg("not enough prior closes for the filters - skipped"); return; }
      g_trend = yc > sma ? 1 : (yc < sma ? -1 : 0);
      g_gap = g_open > yc ? 1 : (g_open < yc ? -1 : 0);
     }
   Dbg(StringFormat("%s box %s-%s (%s) trend %+.0f gap %+.0f", TimeToString(g_nyDate, TIME_DATE), P(g_lo), P(g_hi), P(g_hi - g_lo), g_trend, g_gap));
   g_state = D_WATCH;
   if(EntryMode == ENTRY_FIRST_CANDLE)
     {
      g_state = D_DONE;
      if(MathAbs(boxClose - g_open) < MinBodyPct / 100.0 * (g_hi - g_lo)) { st_doji++; Dbg("box candle is a doji - no trade"); return; }
      Enter(boxClose > g_open ? 1 : -1);
     }
  }

bool FiltersOk(int d)
  {
   if(UseTrendFilter && g_trend != d) { st_blockTrend++; Dbg(StringFormat("%s against the trend - no trade today", d > 0 ? "BUY" : "SELL")); return false; }
   if(UseGapFilter && g_gap != d) { st_blockGap++; Dbg(StringFormat("%s against the gap - no trade today", d > 0 ? "BUY" : "SELL")); return false; }
   return true;
  }

// market entry (BREAK / FIRST_CANDLE) or the midpoint limit (MIDPOINT)
void Enter(int d)
  {
   g_state = D_DONE; g_dir = d;
   if(!FiltersOk(d)) return;
   string why;
   if(!GuardAllows(why)) { st_guard++; Dbg("guard: " + why); return; }
   if(OurPosition() != 0) { Dbg("a position is still open - no new trade"); return; }
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints) { st_skipSpread++; Dbg(StringFormat("spread %d > %d - skipped", spread, MaxSpreadPoints)); return; }
   bool mid = EntryMode == ENTRY_MIDPOINT;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entry = mid ? NP((g_hi + g_lo) / 2) : (d > 0 ? ask : bid);
   double sl = NP(d > 0 ? g_lo : g_hi);
   double risk = d * (entry - sl);
   if(risk <= 0) { Dbg("price already beyond the stop side - skipped"); return; }
   double tp = TargetR > 0 ? NP(entry + d * TargetR * risk) : 0;
   if(g_shadow)
     {
      v_dir = d; v_sl = sl; v_tp = tp; v_time = TimeCurrent();
      if(mid) { v_pend = true; v_lim = entry; g_state = D_PENDING; }
      else    { v_open = true; v_entry = entry; }
      Dbg(StringFormat("SHADOW %s %s @ %s SL %s TP %s", mid ? "limit" : "market", d > 0 ? "BUY" : "SELL", P(entry), P(sl), tp > 0 ? P(tp) : "none"));
      return;
     }
   double lots;
   if(!ComputeLots(d, entry, sl, lots, why))
     {
      st_skipRisk++; Dbg("sizing: " + why);
      if(!MQLInfoInteger(MQL_TESTER)) Alert("TWI NAS100 ORB: trade skipped - ", why);
      return;
     }
   trade.SetExpertMagicNumber(MagicNumber);
   bool ok;
   if(mid) ok = d > 0 ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment)
                      : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment);
   else    ok = d > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment) : trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment);
   if(!ok) { st_orderFail++; Dbg(StringFormat("order failed %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription())); return; }
   if(mid) { g_state = D_PENDING; Dbg(StringFormat("%s LIMIT %.2f @ %s SL %s TP %s", d > 0 ? "BUY" : "SELL", lots, P(entry), P(sl), tp > 0 ? P(tp) : "none")); return; }
   TrackFill();
  }

void TrackFill()
  {
   ulong p = OurPosition();
   if(p == 0) return;
   g_pos = p;
   bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double fill = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME), sl = PositionGetDouble(POSITION_SL), pl = 0;
   g_riskMoney = (sl > 0 && OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol, fill, sl, pl)) ? MathAbs(pl) : 0;
   Dbg(StringFormat("%s %.2f filled @ %s SL %s TP %s risk $%.2f", buy ? "BUY" : "SELL", vol, P(fill), P(sl), P(PositionGetDouble(POSITION_TP)), g_riskMoney));
  }

void Watch()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid >= g_hi) Enter(1);
   else if(bid <= g_lo) Enter(-1);
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   string broker = AccountInfoString(ACCOUNT_COMPANY) + " " + AccountInfoString(ACCOUNT_SERVER);
   StringToUpper(broker);
   g_useUTC0 = ApplyUTC0History && StringFind(broker, "AAAFX") >= 0;
   g_shadow = ShadowMode && !MQLInfoInteger(MQL_TESTER);
   g_startMin = ParseHHMM(SessionStart); g_lastMin = ParseHHMM(LastEntry); g_flatMin = ParseHHMM(FlatTime);
   if(g_startMin < 0 || g_lastMin < 0 || g_flatMin < 0) { Print("Bad time input - use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(BoxMinutes < 1 || g_startMin + BoxMinutes > g_lastMin || g_lastMin > g_flatMin) { Print("Times must run start + box <= last entry <= flat"); return INIT_PARAMETERS_INCORRECT; }
   if(TargetR < 0 || RiskPercent <= 0 || FixedLots <= 0 || TrendSessions < 1 || KillSwitchDDPct <= 0) { Print("Bad input"); return INIT_PARAMETERS_INCORRECT; }
   if(!MQLInfoInteger(MQL_TESTER) && TimeMode == TIME_NY_PLUS_7)
     {
      long off = (long)(TimeTradeServer() - TimeGMT()), want = (NYOffsetHours(TimeGMT()) + 7) * 3600;
      if(MathAbs(off - want) > 900)
        { string m = StringFormat("server clock is UTC%+.1f, not NY+7 - set TimeMode=TIME_FIXED_UTC and ServerUTCOffsetHours", off / 3600.0);
          Print("WARNING: ", m); Alert("TWI NAS100 ORB: ", m); }
     }
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(MaxDeviationPoints);
   g_gv = StringFormat("TWINASORB_%I64d_%I64d_", AccountInfoInteger(ACCOUNT_LOGIN), MagicNumber);
   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(g_gv);
   if(ResetKillSwitch) { GVSet("kill", 0); GVSet("peak", AccountInfoDouble(ACCOUNT_BALANCE)); Print("kill switch re-armed, peak reset to the balance"); }
   if(GVGet("peak", 0) < AccountInfoDouble(ACCOUNT_BALANCE)) GVSet("peak", AccountInfoDouble(ACCOUNT_BALANCE));
   g_pos = OurPosition();
   if(g_pos != 0) TrackFill();
   PrintFormat("TWI NAS100 ORB v1.01 on %s | %s | box %d min from %s, entries to %s, flat %s | target %s | trend %s | gap %s | %s | %s | kill %s",
               _Symbol, EnumToString(EntryMode), BoxMinutes, SessionStart, LastEntry, FlatTime,
               TargetR > 0 ? StringFormat("%.2fR", TargetR) : "none (hold to flat)", UseTrendFilter ? StringFormat("on (%d)", TrendSessions) : "off",
               UseGapFilter ? "on" : "off", LotMode == LOTS_FIXED ? StringFormat("fixed %.2f", FixedLots) : StringFormat("risk %.2f%%", MathMin(RiskPercent, 2.0)),
               g_shadow ? "SHADOW MODE (no orders)" : "LIVE ORDERS", GVGet("kill", 0) != 0 ? "TRIPPED" : "armed");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime ny = ServerToNY(now);
   datetime nyDate = (datetime)((long)ny - (long)ny % 86400);
   if(!g_shadow) GuardTick();
   // position bookkeeping
   if(!g_shadow)
     {
      if(g_pos == 0 && g_state == D_PENDING && OurPosition() != 0) { TrackFill(); g_state = D_DONE; }
      if(g_pos != 0 && OurPosition() == 0) RecordClosed();
     }
   else ShadowTick(now);
   if(nyDate != g_nyDate) NewDay(nyDate);
   // flat time: close and cancel everything of ours
   if(g_state != D_OFF && now >= g_tFlat)
     {
      if(g_shadow)
        {
         if(v_open) ShadowLog("FLAT", v_dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
         if(v_pend) { v_pend = false; st_noFill++; }
        }
      else
        {
         if(OurOrders() > 0) { DeleteOurOrders(); st_noFill++; }
         ulong p = OurPosition();
         if(p != 0 && trade.PositionClose(p)) Dbg("flat time - closed");
         if(g_pos != 0 && OurPosition() == 0) RecordClosed();
        }
      g_state = D_OFF;
      return;
     }
   if(!g_shadow && (!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))) return;
   if(g_state == D_WAIT_BOX && now >= g_tBoxEnd) BuildBox();
   if(g_state == D_WATCH)
     {
      if(now >= g_tLast) { st_noTouch++; g_state = D_DONE; }
      else Watch();
     }
   if(g_state == D_PENDING && now >= g_tLast)
     {
      if(g_shadow) { if(v_pend) { v_pend = false; st_noFill++; } }
      else if(OurOrders() > 0) { DeleteOurOrders(); st_noFill++; }
      g_state = D_DONE;
     }
  }

void OnDeinit(const int reason)
  {
   Print("==================== TWI NAS100 ORB SUMMARY ====================");
   PrintFormat("%s: trades %d  wins %d (%.1f%%)  total R %.2f  avg R %.3f  PF %.2f | no touch %d, no fill %d, doji %d, trend-blocked %d, gap-blocked %d, guard %d, spread %d, risk %d, no bars %d, order fail %d%s",
               g_shadow ? "SHADOW" : "LIVE/TEST", st_trades, st_wins, st_trades > 0 ? 100.0 * st_wins / st_trades : 0, st_sumR,
               st_trades > 0 ? st_sumR / st_trades : 0, st_gl > 0 ? st_gp / st_gl : 0, st_noTouch, st_noFill, st_doji, st_blockTrend, st_blockGap,
               st_guard, st_skipSpread, st_skipRisk, st_noBars, st_orderFail, GVGet("kill", 0) != 0 ? " | KILL SWITCH TRIPPED" : "");
   Print("=================================================================");
  }
//+------------------------------------------------------------------+
