//+------------------------------------------------------------------+
//|                                           TWI Trend Scalper.mq5 |
//|  Built 2026-10-12 from Adam's gold M5 chart: support/resistance, |
//|  trendlines, PSAR, EMA 200 bias, EMA 21/50 cross. UNTESTED.       |
//|                                                                  |
//|  On each closed bar of SignalTF (default M5):                    |
//|   1. Bias     - close above EMA200 -> buys only, below -> sells.  |
//|   2. Trigger  - EMA21 crossed EMA50 in the bias direction within  |
//|                 the last CrossLookbackBars bars (and still is).   |
//|   3. PSAR     - dots on the trade side of the signal bar          |
//|                 (SARFlipBars > 0: must also have flipped within   |
//|                 that many bars).                                  |
//|   4. Location - BOUNCE: a recent bar tagged support (buy) /       |
//|                 resistance (sell) - a swing level or a trendline  |
//|                 through the last two swings - and price is back   |
//|                 on the right side. BREAK: a recent bar closed     |
//|                 through a falling resistance line / swing high    |
//|                 (buy) or a rising support line / swing low (sell).|
//|                 MinRoomR: skip if the next opposing level is      |
//|                 closer than this many R (no buying into a wall).  |
//|   5. Exits    - SL beyond the recent extreme or the PSAR dot      |
//|                 (whichever is further) + an ATR buffer, never     |
//|                 tighter than MinStopATR x ATR or MinStopSpread-   |
//|                 Mult x spread; skip if wider than MaxStopATR.     |
//|                 TP = RewardRisk x SL. Optional BE / PSAR trail /  |
//|                 opposite-cross exit (all off).                    |
//|  One position at a time, hard SL on every order, no grid, no      |
//|  averaging. Session window, daily trade cap, daily loss stop,     |
//|  spread cap, cooldown, and flat before gold's 17:00 NY daily      |
//|  break (spreads blow out on the reopen).                          |
//|  Swings only count once confirmed (SwingStrength bars after), so  |
//|  the location test never sees a level before it existed.         |
//|                                                                  |
//|  v1.01 (2026-10-12, after the 1-yr smoke test choked on the room   |
//|  filter and PSAR-wide stops): (1) TPMode TP_MEASURED (default) -  |
//|  Adam's method: a break targets the break level + the pattern     |
//|  height (highest high - lowest low from MeasureExtraBars before   |
//|  the broken line's oldest anchor to the signal bar); a bounce     |
//|  targets the next opposing level. Either way capped just under    |
//|  the next opposing level (TPCapBufferATR), skipped if the target  |
//|  is under MinTPR, clipped at MaxTPR. (2) Stop from the swing      |
//|  extreme only (UseSARInStop=false). (3) One entry per EMA cross;  |
//|  signals/skips counted once per cross. (4) Tighter location:      |
//|  3 levels, 3-bar lookback, 0.2 ATR touch tolerance.               |
//|                                                                  |
//|  v1.02 (2026-10-12, Adam: "Stop loss should of been below        |
//|  triangle" -> "Test it"): StopMode STOP_PATTERN puts the SL       |
//|  beyond the structure that invalidates the setup - a break: the   |
//|  opposite triangle line (rising support line for a buy, falling   |
//|  resistance line for a sell) at the signal bar, else the nearest   |
//|  swing low/high beyond entry; a bounce: the level it bounced off. |
//|  Default stays STOP_SWING, so defaults trade exactly like v1.01.  |
//|                                                                  |
//|  Time and sizing carried over from TWI ORB Momentum: NY+7 server  |
//|  clock, AAAFx UTC+0 history before 2026-03-07, risk mode uses     |
//|  OrderCalcProfit only.                                            |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TIME_MODE { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_LOT_MODE  { LOTS_FIXED, LOTS_RISK_PERCENT };
enum ENUM_LOC_MODE  { LOC_OFF, LOC_BOUNCE, LOC_BREAK, LOC_BOUNCE_OR_BREAK };
enum ENUM_TP_MODE   { TP_RR, TP_MEASURED };
enum ENUM_STOP_MODE { STOP_SWING, STOP_PATTERN };

input group "=== General ==="
input long            Magic                         = 20261012;
input string          TradeComment                  = "TWI Trend Scalper";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED;
input double          FixedLots                     = 0.01;
input double          RiskPercent                   = 0.5;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;      // allow the min lot if it overshoots risk by at most this %
input double          MaxRiskPerTradePct            = 0.0;       // fixed lots: skip a trade whose SL risk exceeds this % of equity (0 = off)
input int             MaxSpreadPoints               = 60;        // AAAFx gold runs ~52 pts
input int             MaxDeviationPoints            = 20;
input bool            DebugMode                     = true;

input group "=== Signal (closed bars on SignalTF) ==="
input ENUM_TIMEFRAMES SignalTF                      = PERIOD_M5;
input int             FastEMA                       = 21;
input int             MidEMA                        = 50;
input int             TrendEMA                      = 200;
input int             CrossLookbackBars             = 3;         // the 21/50 cross must be this recent
input double          SARStep                       = 0.02;
input double          SARMax                        = 0.2;
input int             SARFlipBars                   = 0;         // 0 = dots only need to be on the trade side

input group "=== Location: support / resistance + trendlines ==="
input ENUM_LOC_MODE   LocationMode                  = LOC_BOUNCE_OR_BREAK;
input int             SwingStrength                 = 3;         // bars each side for a swing high/low
input int             SwingLookbackBars             = 150;
input int             MaxLevels                     = 3;         // nearest swing levels checked per side
input int             LocationLookbackBars          = 3;         // the touch / break must be this recent
input double          TouchToleranceATR             = 0.2;
input double          MinRoomR                      = 1.0;       // TP_RR only: skip if the next opposing level is closer (0 = off)

input group "=== Exits ==="
input int             ATRPeriod                     = 14;
input int             SLSwingBars                   = 5;         // SL beyond the extreme of the last N bars
input ENUM_STOP_MODE  StopMode                      = STOP_SWING; // STOP_PATTERN: beyond the triangle line / level that invalidates the setup
input bool            UseSARInStop                  = false;     // v1.00 behaviour: SL also beyond the PSAR dot (STOP_SWING only)
input double          SLBufferATR                   = 0.2;
input double          MinStopATR                    = 0.5;
input double          MinStopSpreadMult             = 5.0;       // stop at least this many spreads
input double          MaxStopATR                    = 3.0;       // skip the trade if the stop is wider
input ENUM_TP_MODE    TPMode                        = TP_MEASURED;
input double          RewardRisk                    = 2.0;       // TP_RR target; also TP_MEASURED's fallback when no level/pattern exists
input int             MeasureExtraBars              = 10;        // TP_MEASURED: bars before the oldest anchor included in the pattern height
input double          TPCapBufferATR                = 0.1;       // TP_MEASURED: target sits this far short of the next opposing level
input double          MinTPR                        = 1.0;       // TP_MEASURED: skip if the target is closer than this many R
input double          MaxTPR                        = 6.0;       // TP_MEASURED: clip the target at this many R
input double          BreakevenTriggerR             = 0.0;       // 0 = off
input int             BreakevenPlusPoints           = 0;
input bool            UseSARTrail                   = false;
input bool            CloseOnOppositeCross          = false;

input group "=== Session + limits (New York time) ==="
input string          SessionStartNY                = "03:00";   // London open
input string          SessionEndNY                  = "12:00";
input bool            FlatBeforeDailyBreak          = true;      // close at DailyFlatNY, no entries until 18:05 NY
input string          DailyFlatNY                   = "16:50";
input int             MaxTradesPerDay               = 6;         // 0 = no cap
input double          DailyLossLimitPct             = 3.0;       // from the NY-day starting balance; 0 = off
input int             CooldownBars                  = 3;         // bars to wait after a position closes

input group "=== Clock ==="
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;
input bool            ApplyUTC0History              = true;      // AAAFx-only history fix; ignored automatically on any other broker
input datetime        UTC0HistoryEnd                = D'2026.03.07 00:00';

//--- state ----------------------------------------------------------
int      hFast = INVALID_HANDLE, hMid = INVALID_HANDLE, hTrend = INVALID_HANDLE, hSAR = INVALID_HANDLE, hATR = INVALID_HANDLE;
bool     g_useUTC0 = false;
int      g_sessStart = 0, g_sessEnd = 0, g_flatMin = 0;
datetime g_lastBar = 0;
long     g_dayKey = -1;
int      g_tradesToday = 0;
double   g_dayStartBal = 0;
bool     g_dayStopped = false;
bool     g_hadPos = false;
datetime g_exitBarTime = 0;
double   g_initRiskDist = 0;     // SL distance at entry (0 after a restart -> BE skipped)
int      g_signals = 0, g_entries = 0, g_skipLoc = 0, g_skipRoom = 0, g_skipStop = 0, g_skipSpread = 0;
datetime g_crossTime = 0;        // bar time of the EMA cross the current signal belongs to
datetime g_countedCross = 0;     // last cross counted in the stats
datetime g_usedCross = 0;        // last cross that produced an entry (one entry per cross)
int      g_lastSkip = 0;         // 1 location, 2 room/target, 3 stop, 4 spread (per-cross stats)

struct LocInfo
  {
   bool   isBreak;
   double level;                 // the level / line value at the touch or break bar
   int    anchor;                // bar index of the oldest swing that defines it
  };

// confirmed swings on the last copied bars, nearest first
int      g_hi[], g_lo[];
double   g_hp[], g_lp[];
int      g_nh = 0, g_nl = 0;

void   Dbg(string m) { if(DebugMode) Print("[Trend Scalper] ", m); }
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
int  NYMinutes(datetime srv) { MqlDateTime d; TimeToStruct(ServerToNY(srv), d); return d.hour * 60 + d.min; }
long NYDayKey(datetime srv)  { MqlDateTime d; TimeToStruct(ServerToNY(srv), d); return (long)d.year * 10000 + d.mon * 100 + d.day; }
bool InWindow(int m, int s, int e) { return s <= e ? (m >= s && m < e) : (m >= s || m < e); }
bool InDailyBreak(int m) { return FlatBeforeDailyBreak && m >= g_flatMin && m < 18 * 60 + 5; }

//====================================================================
// DATA
//====================================================================
bool Buf(int h, int buf, int count, double &a[])
  {
   ArraySetAsSeries(a, true);
   return CopyBuffer(h, buf, 0, count, a) == count;
  }

bool GetOurPosition(ulong &ticket, bool &isBuy)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      ticket = t;
      isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      return true;
     }
   return false;
  }

void CloseOurPosition(string why)
  {
   ulong t; bool b;
   if(!GetOurPosition(t, b)) return;
   if(trade.PositionClose(t)) Dbg("closed #" + (string)t + ": " + why);
   else Dbg(StringFormat("close #%I64u failed (%u): %s", t, trade.ResultRetcode(), why));
  }

//====================================================================
// SUPPORT / RESISTANCE - swings and trendlines
//====================================================================
// r[] is series-indexed (0 = forming bar). A swing at i needs SwingStrength bars on each side,
// so the newest possible swing is at SwingStrength + 1 (all its right-side bars are closed).
int FindSwings(const MqlRates &r[], int n, bool highs, int &idx[], double &px[])
  {
   ArrayResize(idx, 0); ArrayResize(px, 0);
   int S = SwingStrength;
   for(int i = S + 1; i < n - S; i++)
     {
      double v = highs ? r[i].high : r[i].low;
      bool ok = true;
      for(int j = 1; j <= S && ok; j++)
        {
         if(highs) { if(!(v > r[i - j].high && v >= r[i + j].high)) ok = false; }
         else      { if(!(v < r[i - j].low  && v <= r[i + j].low))  ok = false; }
        }
      if(!ok) continue;
      int k = ArraySize(idx);
      ArrayResize(idx, k + 1); ArrayResize(px, k + 1);
      idx[k] = i; px[k] = v;
     }
   return ArraySize(idx);
  }

// the line through the two newest swings with index > after; falling = lower highs, rising = higher lows
bool LinePair(const int &idx[], const double &px[], int cnt, int after, bool falling, int &i1, double &p1, double &slope)
  {
   int i2;
   return LinePair2(idx, px, cnt, after, falling, i1, p1, slope, i2);
  }
bool LinePair2(const int &idx[], const double &px[], int cnt, int after, bool falling, int &i1, double &p1, double &slope, int &i2)
  {
   int a = -1;
   for(int q = 0; q < cnt; q++) if(idx[q] > after) { a = q; break; }
   if(a < 0 || a + 1 >= cnt) return false;
   i1 = idx[a]; p1 = px[a];
   double p2 = px[a + 1]; i2 = idx[a + 1];
   if(falling ? p1 >= p2 : p1 <= p2) return false;
   slope = (p1 - p2) / (double)(i2 - i1);   // price change per bar moving forward in time
   return true;
  }
double LineVal(int i1, double p1, double slope, int k) { return p1 + slope * (i1 - k); }

// buy: bar k's low tagged a support (swing low or rising line) and the signal bar closed back above it.
// sell mirrors it on resistance. Only swings confirmed by bar k count.
bool BounceAt(bool buy, const MqlRates &r[], int k, const int &idx[], const double &px[], int cnt, double tol, LocInfo &li, string &why)
  {
   double c1 = r[1].close;
   int after = k + SwingStrength, used = 0;
   for(int q = 0; q < cnt && used < MaxLevels; q++)
     {
      if(idx[q] <= after) continue;
      used++;
      double lvl = px[q];
      bool hit = buy ? (r[k].low <= lvl + tol && r[k].low >= lvl - 2 * tol && c1 > lvl)
                     : (r[k].high >= lvl - tol && r[k].high <= lvl + 2 * tol && c1 < lvl);
      if(hit)
        {
         li.isBreak = false; li.level = lvl; li.anchor = idx[q];
         why = StringFormat("%s bounce off swing level %s (bar %d)", buy ? "support" : "resistance", P(lvl), k); return true;
        }
     }
   int i1, i2; double p1, slope;
   if(LinePair2(idx, px, cnt, after, !buy, i1, p1, slope, i2))
     {
      double v = LineVal(i1, p1, slope, k), v1 = LineVal(i1, p1, slope, 1);
      bool hit = buy ? (r[k].low <= v + tol && r[k].low >= v - 2 * tol && c1 > v1)
                     : (r[k].high >= v - tol && r[k].high <= v + 2 * tol && c1 < v1);
      if(hit)
        {
         li.isBreak = false; li.level = v; li.anchor = i2;
         why = StringFormat("%s bounce off %s trendline %s (bar %d)", buy ? "support" : "resistance", buy ? "rising" : "falling", P(v), k); return true;
        }
     }
   return false;
  }

// buy: bar k closed above a falling resistance line or a swing high it was below on bar k+1, and the
// signal bar is still above it. sell mirrors it on rising support / swing lows.
bool BreakAt(bool buy, const MqlRates &r[], int k, const int &idx[], const double &px[], int cnt, LocInfo &li, string &why)
  {
   double c1 = r[1].close;
   int after = k + 1 + SwingStrength, used = 0;
   for(int q = 0; q < cnt && used < MaxLevels; q++)
     {
      if(idx[q] <= after) continue;
      used++;
      double lvl = px[q];
      bool hit = buy ? (r[k].close > lvl && r[k + 1].close <= lvl && c1 > lvl)
                     : (r[k].close < lvl && r[k + 1].close >= lvl && c1 < lvl);
      if(hit)
        {
         li.isBreak = true; li.level = lvl; li.anchor = idx[q];
         why = StringFormat("break of swing %s %s (bar %d)", buy ? "high" : "low", P(lvl), k); return true;
        }
     }
   int i1, i2; double p1, slope;
   if(LinePair2(idx, px, cnt, after, buy, i1, p1, slope, i2))
     {
      double vk = LineVal(i1, p1, slope, k), vk1 = LineVal(i1, p1, slope, k + 1), v1 = LineVal(i1, p1, slope, 1);
      bool hit = buy ? (r[k].close > vk && r[k + 1].close <= vk1 && c1 > v1)
                     : (r[k].close < vk && r[k + 1].close >= vk1 && c1 < v1);
      if(hit)
        {
         li.isBreak = true; li.level = vk; li.anchor = i2;
         why = StringFormat("break of %s trendline %s (bar %d)", buy ? "falling" : "rising", P(vk), k); return true;
        }
     }
   return false;
  }

bool LocationOK(bool buy, const MqlRates &r[], int n, double atr, LocInfo &li, string &why)
  {
   li.isBreak = false; li.level = 0; li.anchor = -1;
   if(LocationMode == LOC_OFF) { why = "location filter off"; return true; }
   bool wantBounce = LocationMode == LOC_BOUNCE || LocationMode == LOC_BOUNCE_OR_BREAK;
   bool wantBreak  = LocationMode == LOC_BREAK  || LocationMode == LOC_BOUNCE_OR_BREAK;
   double tol = TouchToleranceATR * atr;
   for(int k = 1; k <= LocationLookbackBars && k + 1 < n; k++)
     {
      if(wantBreak)
        {
         if(buy  && BreakAt(true,  r, k, g_hi, g_hp, g_nh, li, why)) return true;
         if(!buy && BreakAt(false, r, k, g_lo, g_lp, g_nl, li, why)) return true;
        }
      if(wantBounce)
        {
         if(buy  && BounceAt(true,  r, k, g_lo, g_lp, g_nl, tol, li, why)) return true;
         if(!buy && BounceAt(false, r, k, g_hi, g_hp, g_nh, tol, li, why)) return true;
        }
     }
   why = "not at support/resistance or a break";
   return false;
  }

// distance from entry to the nearest opposing level (swing or trendline now); -1 = none found
double RoomToNextLevel(bool buy, double entry)
  {
   double best = -1;
   int cnt = buy ? g_nh : g_nl;
   for(int q = 0; q < cnt; q++)
     {
      double lvl = buy ? g_hp[q] : g_lp[q];
      double d = buy ? lvl - entry : entry - lvl;
      if(d > 0 && (best < 0 || d < best)) best = d;
     }
   int i1; double p1, slope;
   bool ok = buy ? LinePair(g_hi, g_hp, g_nh, SwingStrength, true,  i1, p1, slope)
                 : LinePair(g_lo, g_lp, g_nl, SwingStrength, false, i1, p1, slope);
   if(ok)
     {
      double v = LineVal(i1, p1, slope, 0);
      double d = buy ? v - entry : entry - v;
      if(d > 0 && (best < 0 || d < best)) best = d;
     }
   return best;
  }

//====================================================================
// SIZING
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
      double riskMoney = eq * RiskPercent / 100.0;
      lots = MathFloor(riskMoney / perLot / step + 1e-9) * step;
      if(lots < minLot)
        {
         if(minLot * perLot <= riskMoney * (1.0 + RiskOvershootTolerancePercent / 100.0)) lots = minLot;
         else { why = StringFormat("min lot risks %.2f > %.2f budget", minLot * perLot, riskMoney); return false; }
        }
     }
   lots = MathMax(minLot, MathMin(maxLot, NormalizeDouble(MathRound(lots / step) * step, 8)));
   if(LotMode == LOTS_FIXED && MaxRiskPerTradePct > 0 && lots * perLot > eq * MaxRiskPerTradePct / 100.0)
     { why = StringFormat("risk %.2f > %.1f%% of equity", lots * perLot, MaxRiskPerTradePct); return false; }
   return true;
  }

//====================================================================
// ENTRY
//====================================================================
// TP_MEASURED target distance from entry. Break: break level + pattern height, the height = highest high -
// lowest low from MeasureExtraBars before the anchor to bar 1. Bounce: the next opposing level. Both capped
// TPCapBufferATR short of the next opposing level; RewardRisk fallback when neither exists; clipped at MaxTPR.
double MeasuredTarget(bool buy, const MqlRates &r[], int n, double entry, double dist, double atr, const LocInfo &li, string &how)
  {
   double room = RoomToNextLevel(buy, entry);
   double cap = room > 0 ? room - TPCapBufferATR * atr : -1;
   double tgt = -1;
   how = "";
   if(li.isBreak && li.anchor > 0)
     {
      int last = MathMin(n - 1, li.anchor + MeasureExtraBars);
      double hh = r[1].high, ll = r[1].low;
      for(int i = 1; i <= last; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
      double proj = buy ? li.level + (hh - ll) : li.level - (hh - ll);
      tgt = buy ? proj - entry : entry - proj;
      how = StringFormat("measured move %s from %s", P(hh - ll), P(li.level));
     }
   else if(cap > 0) { tgt = cap; cap = -1; how = "next opposing level"; }
   if(tgt <= 0) { tgt = RewardRisk * dist; how = StringFormat("%.1fR fallback", RewardRisk); }
   if(cap > 0 && cap < tgt) { tgt = cap; how += ", capped under the next level"; }
   if(tgt > MaxTPR * dist) { tgt = MaxTPR * dist; how += StringFormat(", clipped at %.1fR", MaxTPR); }
   return tgt;
  }

// STOP_PATTERN base price (before the ATR buffer); 0 = nothing found, use the swing stop.
// break: the opposite triangle line at bar 1 (rising support for a buy, falling resistance for a sell),
// else the nearest swing low (buy) / high (sell) beyond entry. bounce: the level it bounced off.
double PatternStopBase(bool buy, double entry, const LocInfo &li)
  {
   if(!li.isBreak) return (li.anchor >= 0 && (buy ? li.level < entry : li.level > entry)) ? li.level : 0;
   int i1; double p1, slope;
   bool ok = buy ? LinePair(g_lo, g_lp, g_nl, SwingStrength, false, i1, p1, slope)
                 : LinePair(g_hi, g_hp, g_nh, SwingStrength, true,  i1, p1, slope);
   if(ok)
     {
      double v = LineVal(i1, p1, slope, 1);
      if(buy ? v < entry : v > entry) return v;
     }
   double best = 0;
   int cnt = buy ? g_nl : g_nh;
   for(int q = 0; q < cnt; q++)
     {
      double lvl = buy ? g_lp[q] : g_hp[q];
      if(buy ? (lvl < entry && (best == 0 || lvl > best)) : (lvl > entry && (best == 0 || lvl < best))) best = lvl;
     }
   return best;
  }

// returns false with g_lastSkip set when the trade is skipped
bool TryEnter(bool buy, const MqlRates &r[], int n, double atr, double sar1, const LocInfo &li)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = buy ? ask : bid, spread = ask - bid;

   double ext = buy ? r[1].low : r[1].high;
   for(int k = 1; k <= SLSwingBars && k < n; k++) ext = buy ? MathMin(ext, r[k].low) : MathMax(ext, r[k].high);
   if(UseSARInStop) ext = buy ? MathMin(ext, sar1) : MathMax(ext, sar1);
   string stopHow = "swing";
   if(StopMode == STOP_PATTERN)
     {
      double base = PatternStopBase(buy, entry, li);
      if(base > 0) { ext = base; stopHow = "pattern"; }
     }
   double sl = buy ? ext - SLBufferATR * atr : ext + SLBufferATR * atr;
   double dist = buy ? entry - sl : sl - entry;

   double minDist = MathMax(MinStopATR * atr, MinStopSpreadMult * spread);
   minDist = MathMax(minDist, (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point);
   if(dist < minDist) { dist = minDist; sl = buy ? entry - dist : entry + dist; }
   if(dist > MaxStopATR * atr)
     { g_lastSkip = 3; Dbg(StringFormat("skip %s: stop %s = %.1f ATR > %.1f", buy ? "buy" : "sell", P(dist), dist / atr, MaxStopATR)); return false; }

   double tpDist; string how;
   if(TPMode == TP_MEASURED)
     {
      tpDist = MeasuredTarget(buy, r, n, entry, dist, atr, li, how);
      if(tpDist < MinTPR * dist)
        { g_lastSkip = 2; Dbg(StringFormat("skip %s: target only %.2fR (%s)", buy ? "buy" : "sell", tpDist / dist, how)); return false; }
     }
   else
     {
      tpDist = RewardRisk * dist; how = StringFormat("%.1fR", RewardRisk);
      if(MinRoomR > 0)
        {
         double room = RoomToNextLevel(buy, entry);
         if(room >= 0 && room < MinRoomR * dist)
           { g_lastSkip = 2; Dbg(StringFormat("skip %s: next %s only %.2fR away", buy ? "buy" : "sell", buy ? "resistance" : "support", room / dist)); return false; }
        }
     }
   double tp = buy ? entry + tpDist : entry - tpDist;

   double lots; string why;
   if(!CalcLots(buy, entry, sl, lots, why)) { Dbg("skip: " + why); return false; }

   bool ok = buy ? trade.Buy(lots, _Symbol, 0, NormPrice(sl), NormPrice(tp), TradeComment)
                 : trade.Sell(lots, _Symbol, 0, NormPrice(sl), NormPrice(tp), TradeComment);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
     {
      g_entries++; g_tradesToday++; g_initRiskDist = dist; g_hadPos = true;
      Dbg(StringFormat("%s %.2f @ %s SL %s TP %s (%s risk %s = %.2f ATR, target %.2fR: %s)", buy ? "BUY" : "SELL", lots, P(entry), P(sl), P(tp), stopHow, P(dist), dist / atr, tpDist / dist, how));
      return true;
     }
   Dbg(StringFormat("order failed (%u %s)", rc, trade.ResultRetcodeDescription()));
   return false;
  }

//====================================================================
// MANAGEMENT
//====================================================================
void ManageTick()
  {
   if(BreakevenTriggerR <= 0 || g_initRiskDist <= 0) return;
   ulong t; bool isBuy;
   if(!GetOurPosition(t, isBuy)) return;
   double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double px = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gain = isBuy ? px - open : open - px;
   if(gain < BreakevenTriggerR * g_initRiskDist) return;
   double be = NormPrice(isBuy ? open + BreakevenPlusPoints * _Point : open - BreakevenPlusPoints * _Point);
   if(isBuy ? sl >= be : (sl > 0 && sl <= be)) return;
   if(trade.PositionModify(t, be, tp)) Dbg("breakeven -> " + P(be));
  }

void ManageBar(const MqlRates &r[], const double &f[], const double &m[], const double &sar[])
  {
   ulong t; bool isBuy;
   if(!GetOurPosition(t, isBuy)) return;
   if(CloseOnOppositeCross && (isBuy ? (f[1] < m[1] && f[2] >= m[2]) : (f[1] > m[1] && f[2] <= m[2])))
     { CloseOurPosition("opposite EMA cross"); return; }
   if(!UseSARTrail) return;
   double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double gap = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double nsl = NormPrice(sar[1]);
   if(isBuy  && sar[1] < r[1].low  && nsl > sl && nsl < bid - gap && trade.PositionModify(t, nsl, tp)) Dbg("SAR trail -> " + P(nsl));
   if(!isBuy && sar[1] > r[1].high && (sl == 0 || nsl < sl) && nsl > ask + gap && trade.PositionModify(t, nsl, tp)) Dbg("SAR trail -> " + P(nsl));
  }

//====================================================================
// SIGNAL - +1 buy, -1 sell, 0 none (closed bar 1)
//====================================================================
int Signal(const MqlRates &r[], const double &f[], const double &m[], const double &tr[], const double &sar[])
  {
   for(int dir = 1; dir >= -1; dir -= 2)
     {
      bool buy = dir == 1;
      if(buy ? r[1].close <= tr[1] : r[1].close >= tr[1]) continue;           // EMA200 bias
      if(buy ? f[1] <= m[1] : f[1] >= m[1]) continue;                           // 21 on the bias side of 50
      bool crossed = false;
      for(int k = 1; k <= CrossLookbackBars && !crossed; k++)
        {
         crossed = buy ? (f[k] > m[k] && f[k + 1] <= m[k + 1]) : (f[k] < m[k] && f[k + 1] >= m[k + 1]);
         if(crossed) g_crossTime = r[k].time;
        }
      if(!crossed) continue;
      if(buy ? sar[1] >= r[1].low : sar[1] <= r[1].high) continue;              // PSAR dots on the trade side
      if(SARFlipBars > 0)
        {
         bool flipped = false;
         for(int k = 1; k <= SARFlipBars && !flipped; k++)
            flipped = buy ? (sar[k] < r[k].low && sar[k + 1] > r[k + 1].high) : (sar[k] > r[k].high && sar[k + 1] < r[k + 1].low);
         if(!flipped) continue;
        }
      return dir;
     }
   return 0;
  }

//====================================================================
void OnNewBar()
  {
   int need = MathMax(MathMax(CrossLookbackBars, SARFlipBars), LocationLookbackBars) + 3;
   double f[], m[], tr[], sar[], atrB[];
   if(!Buf(hFast, 0, need, f) || !Buf(hMid, 0, need, m) || !Buf(hTrend, 0, need, tr) || !Buf(hSAR, 0, need, sar) || !Buf(hATR, 0, 3, atrB)) return;
   int n = SwingLookbackBars + SwingStrength + 2;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, SignalTF, 0, n, r);
   if(got < need + SwingStrength * 2 + 2) return;

   ulong t; bool isBuy;
   if(GetOurPosition(t, isBuy)) { ManageBar(r, f, m, sar); return; }   // one position at a time

   if(g_dayStopped) return;
   if(MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay) return;
   int nyMin = NYMinutes(TimeCurrent());
   if(!InWindow(nyMin, g_sessStart, g_sessEnd) || InDailyBreak(nyMin)) return;
   if(g_exitBarTime > 0 && iBarShift(_Symbol, SignalTF, g_exitBarTime) < CooldownBars) return;

   int dir = Signal(r, f, m, tr, sar);
   if(dir == 0) return;
   if(g_crossTime == g_usedCross) return;                       // one entry per cross
   if(g_crossTime != g_countedCross) { TallySkip(); g_countedCross = g_crossTime; g_signals++; }
   bool buy = dir == 1;
   double atr = atrB[1];
   if(atr <= 0) return;

   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints > 0 && spreadPts > MaxSpreadPoints) { g_lastSkip = 4; Dbg(StringFormat("skip %s: spread %d > %d", buy ? "buy" : "sell", spreadPts, MaxSpreadPoints)); return; }

   g_nh = FindSwings(r, got, true,  g_hi, g_hp);
   g_nl = FindSwings(r, got, false, g_lo, g_lp);
   string why; LocInfo li;
   if(!LocationOK(buy, r, got, atr, li, why)) { g_lastSkip = 1; Dbg(StringFormat("%s signal, skipped: %s", buy ? "buy" : "sell", why)); return; }
   Dbg(StringFormat("%s signal: %s", buy ? "buy" : "sell", why));
   if(TryEnter(buy, r, got, atr, sar[1], li)) { g_usedCross = g_crossTime; g_lastSkip = 0; }
  }

// a cross that never entered counts once, under the last reason it was skipped
void TallySkip()
  {
   if(g_lastSkip == 1) g_skipLoc++;
   else if(g_lastSkip == 2) g_skipRoom++;
   else if(g_lastSkip == 3) g_skipStop++;
   else if(g_lastSkip == 4) g_skipSpread++;
   g_lastSkip = 0;
  }

//====================================================================
int OnInit()
  {
   g_sessStart = ParseHHMM(SessionStartNY); g_sessEnd = ParseHHMM(SessionEndNY); g_flatMin = ParseHHMM(DailyFlatNY);
   if(g_sessStart < 0 || g_sessEnd < 0 || g_flatMin < 0) { Print("bad session time input"); return INIT_PARAMETERS_INCORRECT; }
   if(!(FastEMA < MidEMA && MidEMA < TrendEMA) || CrossLookbackBars < 1 || SwingStrength < 1 || RewardRisk <= 0 || MaxStopATR <= MinStopATR)
     { Print("bad strategy inputs (need FastEMA < MidEMA < TrendEMA, lookbacks >= 1, RewardRisk > 0, MaxStopATR > MinStopATR)"); return INIT_PARAMETERS_INCORRECT; }
   if(LotMode == LOTS_FIXED ? FixedLots <= 0 : RiskPercent <= 0) { Print("bad lot input"); return INIT_PARAMETERS_INCORRECT; }

   hFast  = iMA(_Symbol, SignalTF, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hMid   = iMA(_Symbol, SignalTF, MidEMA,   0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, SignalTF, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSAR   = iSAR(_Symbol, SignalTF, SARStep, SARMax);
   hATR   = iATR(_Symbol, SignalTF, ATRPeriod);
   if(hFast == INVALID_HANDLE || hMid == INVALID_HANDLE || hTrend == INVALID_HANDLE || hSAR == INVALID_HANDLE || hATR == INVALID_HANDLE)
     { Print("indicator handle failed"); return INIT_FAILED; }

   string broker = AccountInfoString(ACCOUNT_COMPANY) + " " + AccountInfoString(ACCOUNT_SERVER);
   StringToUpper(broker);
   g_useUTC0 = ApplyUTC0History && StringFind(broker, "AAAFX") >= 0;

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(MaxDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   ulong t; bool b;
   g_hadPos = GetOurPosition(t, b);
   PrintFormat("[Trend Scalper] v1.02 %s %s | EMA %d/%d/%d cross<=%d | SAR %.2f/%.2f flip %d | loc %s | TP %s RR %.1f stop %s %.1f-%.1f ATR | session %s-%s NY | lots %s | UTC0 fix %s",
               _Symbol, EnumToString(SignalTF), FastEMA, MidEMA, TrendEMA, CrossLookbackBars, SARStep, SARMax, SARFlipBars,
               EnumToString(LocationMode), EnumToString(TPMode), RewardRisk, EnumToString(StopMode), MinStopATR, MaxStopATR, SessionStartNY, SessionEndNY,
               LotMode == LOTS_FIXED ? DoubleToString(FixedLots, 2) : DoubleToString(RiskPercent, 2) + "%", g_useUTC0 ? "on" : "off");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   TallySkip();
   PrintFormat("[Trend Scalper] crosses %d | entries %d | crosses skipped: location %d, target/room %d, stop too wide %d, spread %d",
               g_signals, g_entries, g_skipLoc, g_skipRoom, g_skipStop, g_skipSpread);
   IndicatorRelease(hFast); IndicatorRelease(hMid); IndicatorRelease(hTrend); IndicatorRelease(hSAR); IndicatorRelease(hATR);
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   long key = NYDayKey(now);
   if(key != g_dayKey)
     { g_dayKey = key; g_tradesToday = 0; g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE); g_dayStopped = false; }

   ulong t; bool isBuy;
   bool has = GetOurPosition(t, isBuy);
   if(g_hadPos && !has) { g_exitBarTime = iTime(_Symbol, SignalTF, 0); g_initRiskDist = 0; }
   g_hadPos = has;

   if(!g_dayStopped && DailyLossLimitPct > 0 && AccountInfoDouble(ACCOUNT_EQUITY) <= g_dayStartBal * (1.0 - DailyLossLimitPct / 100.0))
     { g_dayStopped = true; Dbg(StringFormat("daily loss limit %.1f%% hit - done for the NY day", DailyLossLimitPct)); CloseOurPosition("daily loss limit"); }

   if(has && InDailyBreak(NYMinutes(now))) CloseOurPosition("flat before the daily break");

   ManageTick();

   datetime bt = iTime(_Symbol, SignalTF, 0);
   if(bt != g_lastBar && bt != 0) { g_lastBar = bt; OnNewBar(); }
  }
//+------------------------------------------------------------------+
