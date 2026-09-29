//+------------------------------------------------------------------+
//|                                            TWI ORB Momentum.mq5 |
//|  Built 2026-09-27: our own version of the only set that was      |
//|  positive in all three AAAFx years - the TWP ORB EA "EURUSD M5   |
//|  NYSE NO GRID" preset (instant breakout of a 55-min opening      |
//|  range, SL 2.2x range, TP 0.75x SL) - plus a London session,     |
//|  which passed the same 3-year replay (see TWI ORB Momentum.md).  |
//|                                                                  |
//|  Per session (NY 09:30 and London 03:00, New York time):          |
//|   1. Range  - high/low of the first RangeMinutes (M1 bars).       |
//|   2. Entry  - within EntryWindowMinutes after the range, the      |
//|               FIRST touch of an edge enters in that direction     |
//|               at market (bid >= high -> buy, bid <= low -> sell). |
//|   3. SL     - SLRangeMult x range size from the fill.             |
//|      TP     - TPxSL x the SL distance. Both on the order.         |
//|   4. One trade per session per day. The position runs until SL/TP |
//|      (optional max holding / Friday flat). No grid, no averaging. |
//|  Each session has its own magic (MagicBase + index) so they never |
//|  touch each other's positions.                                    |
//|  v1.10 (2026-09-27): optional Asia (20:00 NY, Sun-Thu evenings)   |
//|  and America (08:00 NY) sessions, both OFF by default so the      |
//|  tested NY+London configuration stays the default.               |
//|  v1.20 (2026-09-27): H1 EMA50 trend filter (on) - the first touch |
//|  only trades if the edge price is on the trend side of the EMA of |
//|  the last closed H1 bar; otherwise that session is done for the  |
//|  day. Default NY only (London failed the unseen 2023-24 year).   |
//|                                                                  |
//|  Time and sizing carried over from TWI ORB Demand Pullback:       |
//|  NY+7 server clock, AAAFx UTC+0 history before 2026-03-07,        |
//|  risk mode uses OrderCalcProfit only. R accounting per position.  |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TIME_MODE { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_LOT_MODE  { LOTS_FIXED, LOTS_RISK_PERCENT };

input group "=== General ==="
input long            MagicBase                     = 20260930;  // NY +0, London +1, Asia +2, America +3
input string          TradeComment                  = "TWI ORB Momentum";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED;
input double          FixedLots                     = 0.01;      // the tested TWP size
input double          RiskPercent                   = 0.5;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;
input int             MaxSpreadPoints               = 0;         // 0 = off
input int             MaxHoldingHours               = 0;         // 0 = off (TWP preset: off)
input bool            CloseFridayNY                 = false;     // flat at FridayCloseNY on Fridays
input string          FridayCloseNY                 = "16:50";
input bool            DebugMode                     = true;

input group "=== Strategy (TWP NYSE no-grid preset values) ==="
input int             RangeMinutes                  = 55;
input int             EntryWindowMinutes            = 10;
input double          SLRangeMult                   = 2.2;
input double          TPxSL                         = 0.75;

input group "=== Trend filter ==="
input bool            UseTrendFilter                = true;      // buy only above / sell only below the EMA
input ENUM_TIMEFRAMES TrendTF                       = PERIOD_H1;
input int             TrendEMAPeriod                = 50;

input group "=== Sessions (New York time) ==="
input bool            UseNY                         = true;
input string          NYStart                       = "09:30";
input bool            UseLondon                     = false;     // v1.20: off - lost the unseen 2023-24 year (-$41)
input string          LondonStart                   = "03:00";
input bool            UseAsia                       = false;     // failed 2 of 3 years in the replay - off by default
input string          AsiaStart                     = "20:00";   // NY evening; runs Sun-Thu
input bool            UseAmerica                    = false;     // assumption: US forex open 08:00 NY (TWP manual gives no time)
input string          AmericaStart                  = "08:00";

input group "=== Clock ==="
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;
input bool            ApplyUTC0History              = true;
input datetime        UTC0HistoryEnd                = D'2026.03.07 00:00';

//--- state ----------------------------------------------------------
enum ENUM_SESS_STATE { S_WAIT_RANGE, S_WINDOW, S_DONE };

struct Sess
  {
   bool     enabled;
   string   name;
   int      startMin;
   long     magic;
   ENUM_SESS_STATE state;
   datetime nyDate;
   datetime rsSrv, reSrv, weSrv;
   double   hi, lo;
   // open position tracking (may outlive the day)
   ulong    posTicket;
   bool     isShort;
   double   initialRiskMoney;
   bool     riskValid;
   // stats
   int      trades, wins, losses, exitTP, exitSL, exitEA;
   double   net, grossP, grossL, sumR;
   int      rInvalid, skippedSpread, skippedRisk, noTouch, noBars, orderFail, trendBlocked;
  };

#define NSESS 4
Sess     SS[NSESS];
int      g_ema = INVALID_HANDLE;
double   g_point;
int      g_friMin;

//====================================================================
void Dbg(string m) { if(DebugMode) Print("[ORB Momentum] ", m); }
string P(double p) { return DoubleToString(p, _Digits); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }

int ParseHHMM(string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return -1;
   int h = (int)StringToInteger(parts[0]), m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
  }

//====================================================================
// TIME - server <-> New York (same as TWI ORB Demand Pullback)
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
   if(ApplyUTC0History && srv < UTC0HistoryEnd) return srv + NYOffsetHours(srv) * 3600;
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
// SIZING
//====================================================================
bool ComputeLots(bool isShort, double entry, double sl, double &lots, string &why)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   if(LotMode == LOTS_FIXED)
     {
      lots = MathMax(minLot, MathMin(maxLot, MathFloor(FixedLots / step + 1e-9) * step));
      return lots > 0;
     }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY), pl1 = 0;
   ENUM_ORDER_TYPE ot = isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!OrderCalcProfit(ot, _Symbol, 1.0, entry, sl, pl1) || MathAbs(pl1) <= 0) { why = "OrderCalcProfit failed"; return false; }
   lots = MathFloor((equity * RiskPercent / 100.0 / MathAbs(pl1)) / step) * step;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   double plF = 0;
   if(!OrderCalcProfit(ot, _Symbol, lots, entry, sl, plF)) { why = "OrderCalcProfit final failed"; return false; }
   double pct = equity > 0 ? MathAbs(plF) / equity * 100.0 : 0;
   if(pct > RiskPercent * (1.0 + RiskOvershootTolerancePercent / 100.0)) { why = StringFormat("risk %.3f%% over ceiling", pct); return false; }
   return true;
  }

//====================================================================
// POSITIONS
//====================================================================
ulong PositionByMagic(long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) return tk;
     }
   return 0;
  }

void RecordClosed(Sess &s)
  {
   double net = 0; bool closed = false; long reason = -1;
   if(HistorySelectByPosition(s.posTicket))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT) { closed = true; reason = HistoryDealGetInteger(d, DEAL_REASON); }
        }
   s.trades++; s.net += net;
   if(net > 0) { s.wins++; s.grossP += net; } else if(net < 0) { s.losses++; s.grossL -= net; }
   if(reason == DEAL_REASON_TP) s.exitTP++; else if(reason == DEAL_REASON_SL) s.exitSL++; else s.exitEA++;
   bool rInv = !closed || !s.riskValid || s.initialRiskMoney <= 0;
   if(rInv) s.rInvalid++; else s.sumR += net / s.initialRiskMoney;
   PrintFormat("[%s] CLOSED pos %I64u  %s  net $%.2f  R %s", s.name, s.posTicket,
               reason == DEAL_REASON_TP ? "TP" : reason == DEAL_REASON_SL ? "SL" : "EA/other", net,
               rInv ? "invalid" : DoubleToString(net / s.initialRiskMoney, 2));
   s.posTicket = 0;
  }

//====================================================================
// SESSION LOGIC
//====================================================================
void NewDay(Sess &s, datetime nyDate)
  {
   s.nyDate = nyDate;
   s.state = S_DONE;
   MqlDateTime dt; TimeToStruct(nyDate, dt);
   bool evening = s.startMin >= 18 * 60;                 // Asia: the session belongs to Sun-Thu evenings
   bool okDay = evening ? (dt.day_of_week >= 0 && dt.day_of_week <= 4) : (dt.day_of_week >= 1 && dt.day_of_week <= 5);
   if(!s.enabled || !okDay) return;
   s.rsSrv = NYToServer(nyDate + s.startMin * 60);
   s.reSrv = NYToServer(nyDate + (s.startMin + RangeMinutes) * 60);
   s.weSrv = NYToServer(nyDate + (s.startMin + RangeMinutes + EntryWindowMinutes) * 60);
   if(s.rsSrv == 0 || s.reSrv == 0 || s.weSrv == 0) { Dbg(s.name + ": NY->server conversion failed"); return; }
   s.state = S_WAIT_RANGE;
  }

void BuildRange(Sess &s)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, s.rsSrv, s.reSrv - 1, r);
   if(n < RangeMinutes * 6 / 10) { s.noBars++; s.state = S_DONE; Dbg(StringFormat("%s: only %d M1 bars in range - skipped", s.name, n)); return; }
   s.hi = r[0].high; s.lo = r[0].low;
   for(int i = 1; i < n; i++) { s.hi = MathMax(s.hi, r[i].high); s.lo = MathMin(s.lo, r[i].low); }
   if(s.hi <= s.lo) { s.state = S_DONE; return; }
   s.state = S_WINDOW;
   Dbg(StringFormat("%s %s: range %s-%s (%s)", s.name, TimeToString(s.nyDate, TIME_DATE), P(s.lo), P(s.hi), P(s.hi - s.lo)));
  }

void TryEntry(Sess &s)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool up = bid >= s.hi, dn = bid <= s.lo;
   if(!up && !dn) return;
   s.state = S_DONE;                         // first touch decides the day, trade or not
   if(PositionByMagic(s.magic) != 0) { Dbg(s.name + ": previous position still open - no new trade"); return; }
   bool sh = dn;
   if(UseTrendFilter)
     {
      double v[];
      if(CopyBuffer(g_ema, 0, 1, 1, v) != 1) { s.trendBlocked++; Dbg(s.name + ": EMA not available - skipped"); return; }
      double edge = sh ? s.lo : s.hi;
      if(sh ? edge >= v[0] : edge <= v[0])
        { s.trendBlocked++; Dbg(StringFormat("%s: %s touch against the %s EMA%d (%s) - no trade today", s.name, sh ? "SELL" : "BUY", EnumToString(TrendTF), TrendEMAPeriod, P(v[0]))); return; }
     }
   double size = s.hi - s.lo;
   double entry = sh ? bid : ask;
   double slDist = SLRangeMult * size;
   double sl = NormPrice(sh ? entry + slDist : entry - slDist);
   double tp = NormPrice(sh ? entry - TPxSL * slDist : entry + TPxSL * slDist);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints) { s.skippedSpread++; Dbg(StringFormat("%s: spread %d > %d - skipped", s.name, spread, MaxSpreadPoints)); return; }
   double lots; string why;
   if(!ComputeLots(sh, entry, sl, lots, why)) { s.skippedRisk++; Dbg(s.name + ": sizing rejected - " + why); return; }
   trade.SetExpertMagicNumber(s.magic);
   bool ok = sh ? trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment + " " + s.name) : trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment + " " + s.name);
   if(!ok) { s.orderFail++; Dbg(StringFormat("%s: order failed %d %s", s.name, trade.ResultRetcode(), trade.ResultRetcodeDescription())); return; }
   ulong pos = PositionByMagic(s.magic);
   if(pos == 0) { s.orderFail++; Dbg(s.name + ": order sent but no position found"); return; }
   s.posTicket = pos; s.isShort = sh;
   double fill = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME), pl = 0;
   s.riskValid = OrderCalcProfit(sh ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, vol, fill, sl, pl) && MathAbs(pl) > 0;
   s.initialRiskMoney = s.riskValid ? MathAbs(pl) : 0;
   Dbg(StringFormat("%s: %s %.2f @ %s  SL %s  TP %s  risk $%.2f  spread %d", s.name, sh ? "SELL" : "BUY", vol, P(fill), P(sl), P(tp), s.initialRiskMoney, spread));
  }

void ManagePosition(Sess &s, datetime now, datetime nyNow)
  {
   if(s.posTicket == 0) return;
   ulong pos = PositionByMagic(s.magic);
   if(pos == 0) { RecordClosed(s); return; }
   bool closeIt = false; string why = "";
   if(MaxHoldingHours > 0 && now - (datetime)PositionGetInteger(POSITION_TIME) >= MaxHoldingHours * 3600) { closeIt = true; why = "max holding"; }
   MqlDateTime d; TimeToStruct(nyNow, d);
   if(CloseFridayNY && d.day_of_week == 5 && d.hour * 60 + d.min >= g_friMin) { closeIt = true; why = "Friday flat"; }
   if(closeIt && trade.PositionClose(pos)) { Dbg(s.name + ": closed - " + why); if(PositionByMagic(s.magic) == 0) RecordClosed(s); }
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_friMin = ParseHHMM(FridayCloseNY);
   int nyMin = ParseHHMM(NYStart), ldMin = ParseHHMM(LondonStart), asMin = ParseHHMM(AsiaStart), amMin = ParseHHMM(AmericaStart);
   if(nyMin < 0 || ldMin < 0 || asMin < 0 || amMin < 0 || g_friMin < 0) { Print("Bad time input - use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(RangeMinutes < 1 || EntryWindowMinutes < 1 || SLRangeMult <= 0 || TPxSL <= 0) { Print("Bad strategy input"); return INIT_PARAMETERS_INCORRECT; }
   int starts[NSESS] = {0, 0, 0, 0}; starts[0] = nyMin; starts[1] = ldMin; starts[2] = asMin; starts[3] = amMin;
   for(int k = 0; k < NSESS; k++)
      if(starts[k] + RangeMinutes + EntryWindowMinutes >= 24 * 60) { Print("Session window crosses midnight - not supported"); return INIT_PARAMETERS_INCORRECT; }
   trade.SetTypeFillingBySymbol(_Symbol);
   if(UseTrendFilter)
     {
      g_ema = iMA(_Symbol, TrendTF, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_ema == INVALID_HANDLE) { Print("EMA handle failed"); return INIT_FAILED; }
     }
   for(int i = 0; i < NSESS; i++) { ZeroMemory(SS[i]); SS[i].state = S_DONE; }
   SS[0].enabled = UseNY;     SS[0].name = "NY";     SS[0].startMin = nyMin; SS[0].magic = MagicBase;
   SS[1].enabled = UseLondon; SS[1].name = "London"; SS[1].startMin = ldMin; SS[1].magic = MagicBase + 1;
   SS[2].enabled = UseAsia;   SS[2].name = "Asia";   SS[2].startMin = asMin; SS[2].magic = MagicBase + 2;
   SS[3].enabled = UseAmerica; SS[3].name = "America"; SS[3].startMin = amMin; SS[3].magic = MagicBase + 3;
   // adopt positions already open from a previous run
   for(int i = 0; i < NSESS; i++)
     {
      ulong pos = PositionByMagic(SS[i].magic);
      if(pos != 0) { SS[i].posTicket = pos; SS[i].isShort = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL; Dbg(SS[i].name + ": adopted open position " + (string)pos); }
     }
   PrintFormat("TWI ORB Momentum v1.20 on %s | trend %s | NY %s %s | London %s %s | Asia %s %s | America %s %s | range %d + window %d min | SL %.2fx range | TP %.2fx SL | %s",
               _Symbol, UseTrendFilter ? StringFormat("EMA%d %s", TrendEMAPeriod, EnumToString(TrendTF)) : "off", UseNY ? "on" : "off", NYStart, UseLondon ? "on" : "off", LondonStart, UseAsia ? "on" : "off", AsiaStart,
               UseAmerica ? "on" : "off", AmericaStart, RangeMinutes, EntryWindowMinutes,
               SLRangeMult, TPxSL, LotMode == LOTS_FIXED ? StringFormat("fixed %.2f lots", FixedLots) : StringFormat("risk %.2f%%", RiskPercent));
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime ny  = ServerToNY(now);
   datetime nyDate = (datetime)((long)ny - (long)ny % 86400);
   for(int i = 0; i < NSESS; i++)
     {
      ManagePosition(SS[i], now, ny);
      if(SS[i].nyDate != nyDate) NewDay(SS[i], nyDate);
      if(SS[i].state == S_WAIT_RANGE && now >= SS[i].reSrv) BuildRange(SS[i]);
      if(SS[i].state == S_WINDOW)
        {
         if(now >= SS[i].weSrv) { SS[i].noTouch++; SS[i].state = S_DONE; }
         else TryEntry(SS[i]);
        }
     }
  }

void OnDeinit(const int reason)
  {
   if(g_ema != INVALID_HANDLE) IndicatorRelease(g_ema);
   Print("==================== TWI ORB MOMENTUM SUMMARY ====================");
   for(int i = 0; i < NSESS; i++)
     {
      Sess s = SS[i];
      if(!s.enabled) continue;
      PrintFormat("%s: trades %d  W %d  L %d  WinRate %.1f%%  Net $%.2f  PF %.2f  Total R %.2f (invalid %d) | TP %d SL %d EA %d | no touch %d, trend-blocked %d, no bars %d, spread skip %d, risk skip %d, order fail %d%s",
                  s.name, s.trades, s.wins, s.losses, s.trades > 0 ? 100.0 * s.wins / s.trades : 0, s.net,
                  s.grossL > 0 ? s.grossP / s.grossL : 0, s.sumR, s.rInvalid, s.exitTP, s.exitSL, s.exitEA,
                  s.noTouch, s.trendBlocked, s.noBars, s.skippedSpread, s.skippedRisk, s.orderFail, s.posTicket != 0 ? " | position still open at end" : "");
     }
   Print("===================================================================");
  }
//+------------------------------------------------------------------+
