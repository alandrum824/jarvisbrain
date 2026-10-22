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
//|  v1.30 (2026-10-11): (1) Prop-firm guard (FTMO 2-Step style), off |
//|  by default: daily floor from the Prague-midnight balance, static |
//|  max-loss floor, both with a safety buffer; a pre-trade check     |
//|  that this trade's SL plus every open SL on the account can't     |
//|  breach a floor; a tick check that closes our positions and halts |
//|  at a floor or at the profit target. (2) Trade-day switches       |
//|  Mon-Fri (TradeFriday=false = skip Fridays). (3) LOTS_BALANCE_    |
//|  SCALED: 0.01 lot per BalancePerLot of balance. (4) Optional DD-  |
//|  step risk (risk % mode): RiskPercent normally, DDRiskReduced-    |
//|  Percent while balance is >= DDRiskTriggerPct below its peak.     |
//|  With every new switch off, trading is identical to v1.20.        |
//|  v1.31 (2026-10-11): fixes from Chief's sim review - DD step is a |
//|  factor (<1, can only cut risk); the guard shrinks lots to the    |
//|  room left and halts+alerts after PropStuckDays with no room; the |
//|  target halt needs balance >= target and PropMinTradingDays, and  |
//|  resumes if closing left the balance short; halt + day start are |
//|  re-read every tick so all charts on the login act together; a    |
//|  halt closes every position in our magic range on any symbol;     |
//|  UTC+0-history fix only applies on an AAAFx account; lot volume   |
//|  normalized; MaxRiskPerTradePct ceiling for fixed/balance modes;  |
//|  foreign no-SL positions warn instead of blocking; live clock     |
//|  check against NY+7 at init.                                      |
//|  v1.32 (2026-10-11): merged from Muse v1.40-1.42, all OFF / 0 by  |
//|  default so trading is identical to v1.31: MaxDeviationPoints     |
//|  slippage cap (10); trade-allowed gate with an hourly warning;    |
//|  symbol trade-mode check; adopted positions restore their risk;   |
//|  EntryBufferPoints; RetryTransientReject; ATR range filter;       |
//|  breakeven; MaxBadFillPoints; DDRiskLatch (reduced risk until a   |
//|  new balance peak); input validation; AvgR + bad-fill in summary. |
//|  NOT merged: PropTargetLockPct (can freeze an account just under  |
//|  the target) and the UTC0 default=false (mis-times AAAFx tests).  |
//|                                                                  |
//|  Time and sizing carried over from TWI ORB Demand Pullback:       |
//|  NY+7 server clock, AAAFx UTC+0 history before 2026-03-07,        |
//|  risk mode uses OrderCalcProfit only. R accounting per position.  |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.32"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TIME_MODE { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_LOT_MODE  { LOTS_FIXED, LOTS_RISK_PERCENT, LOTS_BALANCE_SCALED };

input group "=== General ==="
input long            MagicBase                     = 20260930;  // NY +0, London +1, Asia +2, America +3
input string          TradeComment                  = "TWI ORB Momentum";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED; // fixed (static) / risk % (auto) / balance-scaled (auto)
input double          FixedLots                     = 0.01;      // LOTS_FIXED: the tested TWP size
input double          RiskPercent                   = 0.5;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;
input double          BalancePerLot                 = 10000.0;   // LOTS_BALANCE_SCALED: 0.01 lot per this much balance
input double          MaxRiskPerTradePct            = 0.0;       // fixed / balance-scaled: skip a trade whose SL risk exceeds this % of equity (0 = off)
input int             MaxSpreadPoints               = 0;         // 0 = off
input int             MaxDeviationPoints            = 10;        // max slippage on the market entry (points; 10 = 1 pip on 5-digit)
input int             MaxHoldingHours               = 0;         // 0 = off (TWP preset: off)
input bool            CloseFridayNY                 = false;     // flat at FridayCloseNY on Fridays
input string          FridayCloseNY                 = "16:50";
input bool            DebugMode                     = true;

input group "=== Strategy (TWP NYSE no-grid preset values) ==="
input int             RangeMinutes                  = 55;
input int             EntryWindowMinutes            = 10;
input double          SLRangeMult                   = 2.2;
input double          TPxSL                         = 0.75;

input group "=== Entry quality (off by default) ==="
input int             EntryBufferPoints             = 0;         // 0 = off; the touch must clear the edge by this many points
input bool            RetryTransientReject          = false;     // spread / sizing / soft prop rejects keep watching until the window ends
input int             MaxBadFillPoints              = 0;         // 0 = off; close at once if the fill is this many points worse than the signal price

input group "=== Range filter (ATR, off by default) ==="
input bool            UseRangeFilter                = false;     // skip dead/tiny or news-spike ranges
input ENUM_TIMEFRAMES RangeATRTimeframe             = PERIOD_M15;
input int             RangeATRPeriod                = 14;
input double          MinRangeATR                   = 0.25;      // skip if range < this x ATR
input double          MaxRangeATR                   = 1.75;      // skip if range > this x ATR

input group "=== Breakeven (off by default) ==="
input bool            UseBreakeven                  = false;
input double          BreakevenTriggerR             = 0.5;       // move SL when unrealized >= this x initial risk
input int             BreakevenPlusPoints           = 0;         // SL goes to entry +/- this

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

input group "=== Trade days (the session's New York trading day) ==="
input bool            TradeMonday                   = true;
input bool            TradeTuesday                  = true;
input bool            TradeWednesday                = true;
input bool            TradeThursday                 = true;
input bool            TradeFriday                   = true;      // false = skip Fridays (in-sample idea, untested OOS)

input group "=== Drawdown-step risk (LOTS_RISK_PERCENT only) ==="
input bool            UseDDRiskScheme               = false;
input double          DDRiskTriggerPct              = 4.0;       // balance this % below its peak -> reduced risk
input double          DDRiskFactor                  = 0.5;       // risk = RiskPercent x this while in that drawdown (must be < 1); back to RiskPercent once recovered
input bool            DDRiskLatch                   = false;     // true = stay reduced until the balance makes a NEW peak (false = v1.31: back to full once above the trigger)

input group "=== Prop firm guard (FTMO 2-Step style) ==="
input bool            UsePropGuard                  = false;
input double          PropInitialBalance            = 10000.0;   // the challenge's starting balance
input double          PropDailyLossPct              = 5.0;       // of the initial balance, from the day-start balance (Prague midnight)
input double          PropMaxLossPct                = 10.0;      // of the initial balance, static floor
input double          PropSafetyBufferPct           = 1.0;       // stop this many % (of initial) before each limit
input double          PropTargetPct                 = 10.0;      // close & halt at this profit; 10 = Phase 1, 5 = Phase 2, 0 = off (funded)
input int             PropMinTradingDays            = 4;         // FTMO minimum: the target halt waits until trades were opened on this many FTMO days
input int             PropStuckDays                 = 5;         // halt + alert after this many FTMO days in a row with no room for even the minimum lot

input group "=== Clock ==="
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;
input bool            ApplyUTC0History              = true;      // AAAFx-only history fix; ignored automatically on any other broker
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
   bool     rejCounted;   // a retryable reject was already counted today
   // stats
   int      trades, wins, losses, exitTP, exitSL, exitEA;
   double   net, grossP, grossL, sumR;
   int      rInvalid, skippedSpread, skippedRisk, noTouch, noBars, orderFail, trendBlocked, dayOff, propBlocked, badFill;
  };

#define NSESS 4
Sess     SS[NSESS];
int      g_ema = INVALID_HANDLE;
int      g_atr = INVALID_HANDLE;
double   g_point;
int      g_friMin;
// prop guard / DD-step state (account-wide, persisted in terminal global variables so restarts keep it)
string   g_gvPrefix;
double   g_dayStart = 0;          // max(balance, equity) at the last Prague midnight
long     g_dayKey = -1;           // Prague date (days since epoch) g_dayStart belongs to
int      g_halt = 0;              // 0 none, 1 daily floor (until next Prague day), 2 max-loss floor, 3 target reached, 4 no room left
double   g_peakBal = 0;
bool     g_ddLatched = false;     // DDRiskLatch state (persisted in a global variable)
int      g_dailyHits = 0, g_maxHits = 0, g_targetHits = 0, g_ddReducedTrades = 0, g_shrunk = 0, g_noRoom = 0, g_targetResumes = 0;
bool     g_useUTC0 = false;       // ApplyUTC0History AND the account is AAAFx (set in OnInit)
long     g_warnKey = -1, g_minDaysKey = -1;   // once-per-day log throttles

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

// server -> UTC via the NY conversion (NY offset is -4 or -5; pick the one consistent with the result)
datetime ServerToUTC(datetime srv)
  {
   datetime ny = ServerToNY(srv);
   for(int off = 4; off <= 5; off++) { datetime utc = ny + off * 3600; if(NYOffsetHours(utc) == -off) return utc; }
   return ny + 5 * 3600;
  }
datetime LastSunday(int year, int month)
  {
   datetime nextFirst = month == 12 ? StringToTime(StringFormat("%04d.01.01", year + 1)) : StringToTime(StringFormat("%04d.%02d.01", year, month + 1));
   datetime d = nextFirst - 86400;
   MqlDateTime s; TimeToStruct(d, s);
   return d - s.day_of_week * 86400;
  }
// FTMO's day resets at midnight CE(S)T (Prague): UTC+1, UTC+2 during EU summer time
long PragueDayKey(datetime srv)
  {
   datetime utc = ServerToUTC(srv);
   MqlDateTime u; TimeToStruct(utc, u);
   bool dst = utc >= LastSunday(u.year, 3) + 3600 && utc < LastSunday(u.year, 10) + 3600;
   return (long)(utc + (dst ? 2 : 1) * 3600) / 86400;
  }

//====================================================================
// PROP GUARD + DD-STEP RISK
//====================================================================
ulong PositionByMagic(long magic);
void  RecordClosed(Sess &s);

void GVSet(string k, double v) { GlobalVariableSet(g_gvPrefix + k, v); }
double GVGet(string k, double def) { return GlobalVariableCheck(g_gvPrefix + k) ? GlobalVariableGet(g_gvPrefix + k) : def; }

double DailyFloor() { return g_dayStart - (PropDailyLossPct - PropSafetyBufferPct) / 100.0 * PropInitialBalance; }
double MaxFloor()   { return PropInitialBalance * (1.0 - (PropMaxLossPct - PropSafetyBufferPct) / 100.0); }

bool OurMagic(long m) { return m >= MagicBase && m < MagicBase + NSESS; }
double TargetLevel()  { return PropInitialBalance * (1.0 + PropTargetPct / 100.0); }

void SetHalt(int h) { g_halt = h; GVSet("halt", h); }

void Alarm(string msg)
  {
   Print("PROP GUARD ALERT: ", msg);
   if(!MQLInfoInteger(MQL_TESTER)) { Alert("TWI ORB Momentum: ", msg); SendNotification("TWI ORB Momentum: " + msg); }
  }

// shared state: every chart on this login reads the same halt / day start every tick, so they act as one
void UpdatePropDay(datetime now)
  {
   g_halt = (int)GVGet("halt", g_halt);
   long key = PragueDayKey(now);
   long gvKey = (long)GVGet("dayKey", -1);
   if(gvKey == key) { g_dayKey = key; g_dayStart = GVGet("dayStart", g_dayStart); return; }
   // first chart to see this FTMO day records its start
   g_dayKey = key;
   g_dayStart = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   GVSet("dayKey", (double)g_dayKey); GVSet("dayStart", g_dayStart);
   if(g_halt == 1) { SetHalt(0); Dbg("prop guard: new FTMO day - daily halt lifted"); }
  }

// loss to SL of every open position on the account (all symbols, all EAs). Our own positions must have an SL;
// a foreign position without one is warned about once a day and left out (the equity floors still cover it).
bool OpenRiskMoney(double &risk)
  {
   risk = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double sl = PositionGetDouble(POSITION_SL), vol = PositionGetDouble(POSITION_VOLUME), cur = PositionGetDouble(POSITION_PRICE_CURRENT);
      if(sl <= 0)
        {
         if(OurMagic(PositionGetInteger(POSITION_MAGIC))) return false;
         if(g_warnKey != g_dayKey) { g_warnKey = g_dayKey; PrintFormat("PROP GUARD WARNING: position %I64u on %s has no stop loss - its risk can't be counted", tk, sym); }
         continue;
        }
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double pl = 0;
      if(!OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, vol, cur, sl, pl)) return false;
      if(pl < 0) risk += -pl;
     }
   return true;
  }

// close every position in our magic range on ANY symbol (each chart's ManagePosition records its own closes)
int CloseOurPositions(string why)
  {
   int open = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !OurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      open++;
      if(trade.PositionClose(tk)) Dbg(StringFormat("closed %I64u (%s) - %s", tk, PositionGetString(POSITION_SYMBOL), why));
     }
   return open;
  }

int OurOpenCount()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong tk = PositionGetTicket(i); if(tk != 0 && OurMagic(PositionGetInteger(POSITION_MAGIC))) n++; }
   return n;
  }

void PropGuardTick(datetime now)
  {
   if(!UsePropGuard) return;
   UpdatePropDay(now);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_halt != 2 && g_halt != 3 && eq <= MaxFloor())
     { SetHalt(2); g_maxHits++; Alarm(StringFormat("equity %.2f <= max-loss floor %.2f - closed and HALTED", eq, MaxFloor())); }
   else if(g_halt == 0 && eq <= DailyFloor())
     { SetHalt(1); g_dailyHits++; PrintFormat("PROP GUARD: equity %.2f <= daily floor %.2f - closing, halted until the next FTMO day", eq, DailyFloor()); }
   else if(g_halt == 0 && PropTargetPct > 0 && eq >= TargetLevel())
     {
      int days = (int)GVGet("tradeDays", 0);
      if(days >= PropMinTradingDays) { SetHalt(3); g_targetHits++; PrintFormat("PROP GUARD: equity %.2f reached the %.1f%% target (%d trading days) - closing", eq, PropTargetPct, days); }
      else if(g_minDaysKey != g_dayKey) { g_minDaysKey = g_dayKey; PrintFormat("PROP GUARD: target reached but only %d of %d trading days - still trading", days, PropMinTradingDays); }
     }
   if(g_halt == 1 || g_halt == 2 || g_halt == 3)
     {
      int open = CloseOurPositions(g_halt == 1 ? "daily floor" : g_halt == 2 ? "max-loss floor" : "target reached");
      // target: only stay halted if the BALANCE (after closing costs) really is at/above the target
      if(g_halt == 3 && open == 0 && OurOpenCount() == 0)
        {
         if(bal < TargetLevel()) { SetHalt(0); g_targetResumes++; PrintFormat("PROP GUARD: balance %.2f closed below the target %.2f - resuming", bal, TargetLevel()); }
         else if(GVGet("targetAlerted", 0) == 0) { GVSet("targetAlerted", 1); Alarm(StringFormat("TARGET REACHED: balance %.2f - all closed, trading halted", bal)); }
        }
     }
  }

// fit the trade to the room left above the floors (this trade's SL + every open SL). Shrinks lots if needed;
// false (and counts a no-room FTMO day) only if even the minimum lot doesn't fit.
bool PropFitLots(bool isShort, double entry, double sl, double &lots, string &why)
  {
   if(!UsePropGuard) return true;
   if(g_halt != 0) { why = StringFormat("halted (%d)", g_halt); return false; }
   double open = 0;
   if(!OpenRiskMoney(open)) { why = "one of our positions has no SL - can't bound risk"; return false; }
   double perLot = 0;
   if(!OrderCalcProfit(isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, 1.0, entry, sl, perLot) || MathAbs(perLot) <= 0) { why = "OrderCalcProfit failed"; return false; }
   double room = AccountInfoDouble(ACCOUNT_EQUITY) - open - MathMax(DailyFloor(), MaxFloor());
   if(MathAbs(perLot) * lots <= room) return true;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0) step = 0.01;
   double fit = room > 0 ? NormalizeDouble(MathFloor(room / MathAbs(perLot) / step + 1e-9) * step, 8) : 0;
   if(fit >= minLot)
     {
      Dbg(StringFormat("prop guard: lots %.2f -> %.2f to fit the room left (%.2f)", lots, fit, room));
      lots = fit; g_shrunk++; return true;
     }
   // no room for even the minimum lot: count distinct FTMO days of this since the last trade; halt + alert when stuck
   g_noRoom++;
   if((long)GVGet("noRoomKey", -1) != g_dayKey)
     {
      GVSet("noRoomKey", (double)g_dayKey);
      int streak = (int)GVGet("noRoomStreak", 0) + 1; GVSet("noRoomStreak", streak);
      if(streak >= PropStuckDays)
        { SetHalt(4); Alarm(StringFormat("no room for even the minimum lot on %d FTMO days (room %.2f) - HALTED. The challenge can't be finished at this size.", streak, room)); }
     }
   why = StringFormat("no room: %.2f left above the floor, min lot needs %.2f", room, MathAbs(perLot) * minLot);
   return false;
  }

void PropTradePlaced()
  {
   if(!UsePropGuard) return;
   GVSet("noRoomStreak", 0);
   if((long)GVGet("lastTradeDayKey", -1) != g_dayKey) { GVSet("lastTradeDayKey", (double)g_dayKey); GVSet("tradeDays", GVGet("tradeDays", 0) + 1); }
  }

double EffectiveRiskPercent()
  {
   if(!UseDDRiskScheme) return RiskPercent;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakBal = MathMax(g_peakBal, GVGet("peakBal", 0));
   if(bal > g_peakBal) { g_peakBal = bal; GVSet("peakBal", g_peakBal); }
   if(DDRiskLatch)
     {
      g_ddLatched = GVGet("ddLatch", g_ddLatched ? 1 : 0) != 0;
      if(g_ddLatched && bal >= g_peakBal) { g_ddLatched = false; GVSet("ddLatch", 0); Dbg("DD-step risk: new balance peak - full risk restored"); }
     }
   bool inDD = g_peakBal > 0 && (g_peakBal - bal) / g_peakBal * 100.0 >= DDRiskTriggerPct;
   if(DDRiskLatch && inDD && !g_ddLatched) { g_ddLatched = true; GVSet("ddLatch", 1); }
   return (inDD || (DDRiskLatch && g_ddLatched)) ? RiskPercent * DDRiskFactor : RiskPercent;
  }

double NormLots(double l, double step) { return NormalizeDouble(MathFloor(l / step + 1e-9) * step, 8); }

//====================================================================
// SIZING
//====================================================================
bool ComputeLots(bool isShort, double entry, double sl, double &lots, string &why)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   ENUM_ORDER_TYPE ot = isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(LotMode == LOTS_FIXED || LotMode == LOTS_BALANCE_SCALED)
     {
      double raw = LotMode == LOTS_FIXED ? FixedLots : 0.01 * AccountInfoDouble(ACCOUNT_BALANCE) / MathMax(BalancePerLot, 1.0);
      lots = MathMax(minLot, MathMin(maxLot, NormLots(raw, step)));
      if(lots <= 0) return false;
      if(MaxRiskPerTradePct > 0)
        {
         double plC = 0;
         if(!OrderCalcProfit(ot, _Symbol, lots, entry, sl, plC)) { why = "OrderCalcProfit failed"; return false; }
         double pctC = equity > 0 ? MathAbs(plC) / equity * 100.0 : 0;
         if(pctC > MaxRiskPerTradePct) { why = StringFormat("risk %.3f%% > MaxRiskPerTradePct %.2f%%", pctC, MaxRiskPerTradePct); return false; }
        }
      return true;
     }
   double rp = EffectiveRiskPercent();
   double pl1 = 0;
   if(!OrderCalcProfit(ot, _Symbol, 1.0, entry, sl, pl1) || MathAbs(pl1) <= 0) { why = "OrderCalcProfit failed"; return false; }
   lots = NormLots(equity * rp / 100.0 / MathAbs(pl1), step);
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   double plF = 0;
   if(!OrderCalcProfit(ot, _Symbol, lots, entry, sl, plF)) { why = "OrderCalcProfit final failed"; return false; }
   double pct = equity > 0 ? MathAbs(plF) / equity * 100.0 : 0;
   if(pct > rp * (1.0 + RiskOvershootTolerancePercent / 100.0)) { why = StringFormat("risk %.3f%% over ceiling", pct); return false; }
   if(rp != RiskPercent) g_ddReducedTrades++;
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
   s.rejCounted = false;
   MqlDateTime dt; TimeToStruct(nyDate, dt);
   bool evening = s.startMin >= 18 * 60;                 // Asia: the session belongs to Sun-Thu evenings
   bool okDay = evening ? (dt.day_of_week >= 0 && dt.day_of_week <= 4) : (dt.day_of_week >= 1 && dt.day_of_week <= 5);
   if(!s.enabled || !okDay) return;
   int tday = evening ? dt.day_of_week + 1 : dt.day_of_week;   // the trading day the session belongs to
   bool dayOn = tday == 1 ? TradeMonday : tday == 2 ? TradeTuesday : tday == 3 ? TradeWednesday : tday == 4 ? TradeThursday : TradeFriday;
   if(!dayOn) { s.dayOff++; return; }
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
   if(UseRangeFilter && g_atr != INVALID_HANDLE)
     {
      double av[];
      if(CopyBuffer(g_atr, 0, 1, 1, av) == 1 && av[0] > 0)
        {
         double rr = (s.hi - s.lo) / av[0];
         if(rr < MinRangeATR || rr > MaxRangeATR)
           { s.state = S_DONE; Dbg(StringFormat("%s: range %.2f ATR outside [%.2f, %.2f] - skipped", s.name, rr, MinRangeATR, MaxRangeATR)); return; }
        }
      else Dbg(s.name + ": ATR unavailable - range filter passed open");
     }
   s.state = S_WINDOW;
   Dbg(StringFormat("%s %s: range %s-%s (%s)", s.name, TimeToString(s.nyDate, TIME_DATE), P(s.lo), P(s.hi), P(s.hi - s.lo)));
  }

void TryEntry(Sess &s)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double buf = EntryBufferPoints * _Point;
   bool up = bid >= s.hi + buf, dn = bid <= s.lo - buf;
   if(!up && !dn) return;
   s.state = S_DONE;                         // first touch decides the day; RetryTransientReject re-opens it below
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
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints)
     {
      if(!s.rejCounted) { s.skippedSpread++; s.rejCounted = true; }
      Dbg(StringFormat("%s: spread %d > %d - %s", s.name, spread, MaxSpreadPoints, RetryTransientReject ? "will retry" : "skipped"));
      if(RetryTransientReject) s.state = S_WINDOW;
      return;
     }
   double lots; string why;
   if(!ComputeLots(sh, entry, sl, lots, why))
     {
      if(!s.rejCounted) { s.skippedRisk++; s.rejCounted = true; }
      Dbg(s.name + ": sizing rejected - " + why + (RetryTransientReject ? " (will retry)" : ""));
      if(RetryTransientReject) s.state = S_WINDOW;
      return;
     }
   if(!PropFitLots(sh, entry, sl, lots, why))
     {
      if(!s.rejCounted) { s.propBlocked++; s.rejCounted = true; }
      Dbg(s.name + ": prop guard blocked - " + why);
      if(RetryTransientReject && g_halt == 0) s.state = S_WINDOW;   // a halt always ends the day
      return;
     }
   trade.SetExpertMagicNumber(s.magic);
   bool ok = sh ? trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment + " " + s.name) : trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment + " " + s.name);
   if(!ok) { s.orderFail++; Dbg(StringFormat("%s: order failed %d %s", s.name, trade.ResultRetcode(), trade.ResultRetcodeDescription())); return; }
   ulong pos = PositionByMagic(s.magic);
   if(pos == 0) { s.orderFail++; Dbg(s.name + ": order sent but no position found"); return; }
   s.posTicket = pos; s.isShort = sh;
   PropTradePlaced();
   double fill = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME), pl = 0;
   s.riskValid = OrderCalcProfit(sh ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, vol, fill, sl, pl) && MathAbs(pl) > 0;
   s.initialRiskMoney = s.riskValid ? MathAbs(pl) : 0;
   if(MaxBadFillPoints > 0)   // fast-market protection: fill much worse than the signal price
     {
      double badPts = sh ? (entry - fill) / _Point : (fill - entry) / _Point;   // negative = price improved
      if(badPts > MaxBadFillPoints)
        {
         s.badFill++;
         Dbg(StringFormat("%s: bad fill %s vs signal %s (%.0f pts worse) - closing at once", s.name, P(fill), P(entry), badPts));
         if(trade.PositionClose(pos) && PositionByMagic(s.magic) == 0) RecordClosed(s);
         return;
        }
     }
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
   if(!closeIt && UseBreakeven && s.riskValid && s.initialRiskMoney > 0)
     {
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double openPx = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME);
      double curPx = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double upl = 0;
      if(OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol, openPx, curPx, upl) && upl >= BreakevenTriggerR * s.initialRiskMoney)
        {
         double oldSL = PositionGetDouble(POSITION_SL);
         double newSL = NormPrice(openPx + (isBuy ? 1 : -1) * BreakevenPlusPoints * _Point);
         double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 2) * _Point;
         bool farEnough = isBuy ? (curPx - newSL >= minDist) : (newSL - curPx >= minDist);
         bool improves = isBuy ? (newSL > oldSL + _Point / 2) : (oldSL <= 0 || newSL < oldSL - _Point / 2);
         if(farEnough && improves)
           {
            if(trade.PositionModify(pos, newSL, PositionGetDouble(POSITION_TP))) Dbg(StringFormat("%s: breakeven - SL %s -> %s", s.name, P(oldSL), P(newSL)));
            else Dbg(StringFormat("%s: breakeven modify failed %d %s", s.name, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
           }
        }
     }
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_friMin = ParseHHMM(FridayCloseNY);
   // the UTC+0-history fix belongs to AAAFx's broker history only
   string broker = AccountInfoString(ACCOUNT_COMPANY) + " " + AccountInfoString(ACCOUNT_SERVER);
   StringToUpper(broker);
   g_useUTC0 = ApplyUTC0History && StringFind(broker, "AAAFX") >= 0;
   if(ApplyUTC0History && !g_useUTC0) Print("ApplyUTC0History ignored: this account is not AAAFx (", AccountInfoString(ACCOUNT_SERVER), ")");
   // live: check the server clock really is NY+7 when that mode is selected
   if(!MQLInfoInteger(MQL_TESTER) && TimeMode == TIME_NY_PLUS_7)
     {
      long off = (long)(TimeTradeServer() - TimeGMT()), want = (NYOffsetHours(TimeGMT()) + 7) * 3600;
      if(MathAbs(off - want) > 900)
        { string m = StringFormat("server clock is UTC%+.1f, not NY+7 (UTC%+.0f) - set TimeMode=TIME_FIXED_UTC and ServerUTCOffsetHours, or session times will be wrong", off / 3600.0, want / 3600.0);
          Print("WARNING: ", m); Alert("TWI ORB Momentum: ", m); }
     }
   if(UseDDRiskScheme && (DDRiskFactor <= 0 || DDRiskFactor >= 1)) { Print("DDRiskFactor must be between 0 and 1 (it can only cut risk)"); return INIT_PARAMETERS_INCORRECT; }
   int nyMin = ParseHHMM(NYStart), ldMin = ParseHHMM(LondonStart), asMin = ParseHHMM(AsiaStart), amMin = ParseHHMM(AmericaStart);
   if(nyMin < 0 || ldMin < 0 || asMin < 0 || amMin < 0 || g_friMin < 0) { Print("Bad time input - use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(RangeMinutes < 1 || EntryWindowMinutes < 1 || SLRangeMult <= 0 || TPxSL <= 0) { Print("Bad strategy input"); return INIT_PARAMETERS_INCORRECT; }
   if(MaxDeviationPoints < 0 || EntryBufferPoints < 0 || MaxBadFillPoints < 0 || BreakevenPlusPoints < 0) { Print("Bad entry-guard input (negative points)"); return INIT_PARAMETERS_INCORRECT; }
   if(LotMode == LOTS_FIXED && FixedLots <= 0) { Print("FixedLots must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(LotMode == LOTS_RISK_PERCENT && RiskPercent <= 0) { Print("RiskPercent must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(UseBreakeven && BreakevenTriggerR <= 0) { Print("BreakevenTriggerR must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   int starts[NSESS] = {0, 0, 0, 0}; starts[0] = nyMin; starts[1] = ldMin; starts[2] = asMin; starts[3] = amMin;
   for(int k = 0; k < NSESS; k++)
      if(starts[k] + RangeMinutes + EntryWindowMinutes >= 24 * 60) { Print("Session window crosses midnight - not supported"); return INIT_PARAMETERS_INCORRECT; }
   long tmode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED || tmode == SYMBOL_TRADE_MODE_CLOSEONLY) { Print("Symbol is not tradeable - check SYMBOL_TRADE_MODE"); return INIT_PARAMETERS_INCORRECT; }
   if(tmode != SYMBOL_TRADE_MODE_FULL) Print("Warning: SYMBOL_TRADE_MODE is not FULL - entries in one direction may be rejected");
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(MaxDeviationPoints);
   if(UseTrendFilter)
     {
      g_ema = iMA(_Symbol, TrendTF, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_ema == INVALID_HANDLE) { Print("EMA handle failed"); return INIT_FAILED; }
     }
   if(UseRangeFilter)
     {
      if(RangeATRPeriod < 1 || MinRangeATR < 0 || MaxRangeATR <= MinRangeATR) { Print("Bad range-filter input"); return INIT_PARAMETERS_INCORRECT; }
      g_atr = iATR(_Symbol, RangeATRTimeframe, RangeATRPeriod);
      if(g_atr == INVALID_HANDLE) { Print("ATR handle failed"); return INIT_FAILED; }
     }
   if(LotMode == LOTS_BALANCE_SCALED && BalancePerLot <= 0) { Print("BalancePerLot must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(UsePropGuard && (PropInitialBalance <= 0 || PropDailyLossPct <= PropSafetyBufferPct || PropMaxLossPct <= PropSafetyBufferPct))
     { Print("Bad prop guard input (limits must exceed the safety buffer)"); return INIT_PARAMETERS_INCORRECT; }
   // account-wide state shared by every chart running this EA on the same login
   g_gvPrefix = StringFormat("TWIORBM_%I64d_", AccountInfoInteger(ACCOUNT_LOGIN));
   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(g_gvPrefix);   // every test starts clean
   g_halt    = (int)GVGet("halt", 0);
   g_dayKey  = (long)GVGet("dayKey", -1);
   g_dayStart = GVGet("dayStart", 0);
   g_peakBal = MathMax(GVGet("peakBal", 0), AccountInfoDouble(ACCOUNT_BALANCE));
   if(UseDDRiskScheme && UsePropGuard) g_peakBal = MathMax(g_peakBal, PropInitialBalance);
   g_ddLatched = GVGet("ddLatch", 0) != 0;
   if(UsePropGuard) UpdatePropDay(TimeCurrent());
   for(int i = 0; i < NSESS; i++) { ZeroMemory(SS[i]); SS[i].state = S_DONE; }
   SS[0].enabled = UseNY;     SS[0].name = "NY";     SS[0].startMin = nyMin; SS[0].magic = MagicBase;
   SS[1].enabled = UseLondon; SS[1].name = "London"; SS[1].startMin = ldMin; SS[1].magic = MagicBase + 1;
   SS[2].enabled = UseAsia;   SS[2].name = "Asia";   SS[2].startMin = asMin; SS[2].magic = MagicBase + 2;
   SS[3].enabled = UseAmerica; SS[3].name = "America"; SS[3].startMin = amMin; SS[3].magic = MagicBase + 3;
   // adopt positions already open from a previous run (their risk is restored from the SL for R stats)
   for(int i = 0; i < NSESS; i++)
     {
      ulong pos = PositionByMagic(SS[i].magic);
      if(pos == 0) continue;
      SS[i].posTicket = pos;
      SS[i].isShort = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;
      double asl = PositionGetDouble(POSITION_SL), aopen = PositionGetDouble(POSITION_PRICE_OPEN), avol = PositionGetDouble(POSITION_VOLUME), apl = 0;
      SS[i].riskValid = asl > 0 && OrderCalcProfit(SS[i].isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, avol, aopen, asl, apl) && MathAbs(apl) > 0;
      SS[i].initialRiskMoney = SS[i].riskValid ? MathAbs(apl) : 0;
      Dbg(SS[i].name + ": adopted open position " + (string)pos + (SS[i].riskValid ? StringFormat(" (risk $%.2f restored)", SS[i].initialRiskMoney) : " (no SL - R stats invalid)"));
     }
   PrintFormat("TWI ORB Momentum v1.32 on %s | trend %s | NY %s %s | London %s %s | Asia %s %s | America %s %s | range %d + window %d min | SL %.2fx range | TP %.2fx SL | %s",
               _Symbol, UseTrendFilter ? StringFormat("EMA%d %s", TrendEMAPeriod, EnumToString(TrendTF)) : "off", UseNY ? "on" : "off", NYStart, UseLondon ? "on" : "off", LondonStart, UseAsia ? "on" : "off", AsiaStart,
               UseAmerica ? "on" : "off", AmericaStart, RangeMinutes, EntryWindowMinutes, SLRangeMult, TPxSL,
               LotMode == LOTS_FIXED ? StringFormat("fixed %.2f lots", FixedLots) : LotMode == LOTS_BALANCE_SCALED ? StringFormat("0.01 lot per %.0f balance", BalancePerLot) : StringFormat("risk %.2f%%", RiskPercent));
   PrintFormat("  days M%d T%d W%d T%d F%d | UTC0 history fix %s | max risk/trade %s | DD-step risk %s | prop guard %s",
               TradeMonday, TradeTuesday, TradeWednesday, TradeThursday, TradeFriday, g_useUTC0 ? "on (AAAFx)" : "off",
               MaxRiskPerTradePct > 0 ? StringFormat("%.2f%%", MaxRiskPerTradePct) : "off",
               UseDDRiskScheme ? StringFormat("%.2f%% -> %.2f%% at -%.1f%% from peak", RiskPercent, RiskPercent * DDRiskFactor, DDRiskTriggerPct) : "off",
               UsePropGuard ? StringFormat("ON: initial %.0f, daily %.1f%% / max %.1f%% (stops %.1f%% early), target %.1f%% after %d trading days, stuck-halt %d days, day start %.2f, halt %d",
                                           PropInitialBalance, PropDailyLossPct, PropMaxLossPct, PropSafetyBufferPct, PropTargetPct, PropMinTradingDays, PropStuckDays, g_dayStart, g_halt) : "off");
   PrintFormat("  deviation %d pts | entry buffer %d pts | retry-reject %s | range filter %s | breakeven %s | bad-fill guard %s | DD latch %s",
               MaxDeviationPoints, EntryBufferPoints, RetryTransientReject ? "on" : "off",
               UseRangeFilter ? StringFormat("on [%.2f, %.2f] ATR", MinRangeATR, MaxRangeATR) : "off",
               UseBreakeven ? StringFormat("on @ %.2fR + %d pts", BreakevenTriggerR, BreakevenPlusPoints) : "off",
               MaxBadFillPoints > 0 ? StringFormat("%d pts", MaxBadFillPoints) : "off", DDRiskLatch ? "on" : "off");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime ny  = ServerToNY(now);
   datetime nyDate = (datetime)((long)ny - (long)ny % 86400);
   PropGuardTick(now);                       // the guard watches even while trading is paused
   static datetime lastTradeWarn = 0;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      if(now - lastTradeWarn >= 3600) { Print("TWI ORB Momentum: trading is not allowed (EA / account / terminal) - waiting"); lastTradeWarn = now; }
      return;
     }
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
   if(g_atr != INVALID_HANDLE) IndicatorRelease(g_atr);
   Print("==================== TWI ORB MOMENTUM SUMMARY ====================");
   for(int i = 0; i < NSESS; i++)
     {
      Sess s = SS[i];
      if(!s.enabled) continue;
      PrintFormat("%s: trades %d  W %d  L %d  WinRate %.1f%%  Net $%.2f  PF %.2f  Total R %.2f  AvgR %.2f (invalid %d) | TP %d SL %d EA %d | no touch %d, trend-blocked %d, no bars %d, spread skip %d, risk skip %d, order fail %d, bad fill %d, day off %d, prop-blocked %d%s",
                  s.name, s.trades, s.wins, s.losses, s.trades > 0 ? 100.0 * s.wins / s.trades : 0, s.net,
                  s.grossL > 0 ? s.grossP / s.grossL : 0, s.sumR, s.trades > 0 ? s.sumR / s.trades : 0, s.rInvalid, s.exitTP, s.exitSL, s.exitEA,
                  s.noTouch, s.trendBlocked, s.noBars, s.skippedSpread, s.skippedRisk, s.orderFail, s.badFill, s.dayOff, s.propBlocked, s.posTicket != 0 ? " | position still open at end" : "");
     }
   if(UseDDRiskScheme) PrintFormat("DD-step risk: %d trades sized at the reduced %.2f%%, balance peak %.2f", g_ddReducedTrades, RiskPercent * DDRiskFactor, g_peakBal);
   if(UsePropGuard) PrintFormat("Prop guard: daily-floor hits %d, max-loss hits %d, target hits %d (resumed after short close %d), lots shrunk to fit %d, no-room skips %d, trading days %d, final state %s",
                                g_dailyHits, g_maxHits, g_targetHits, g_targetResumes, g_shrunk, g_noRoom, (int)GVGet("tradeDays", 0),
                                g_halt == 0 ? "trading" : g_halt == 1 ? "daily halt" : g_halt == 2 ? "MAX-LOSS HALT" : g_halt == 3 ? "TARGET REACHED" : "NO-ROOM HALT");
   Print("===================================================================");
  }
//+------------------------------------------------------------------+
