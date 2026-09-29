//+------------------------------------------------------------------+
//|                                            TWI Range Breaker.mq5 |
//|  Opening-range breakout, built 2026-09-27 from 5 frames of an    |
//|  "Alphoryn Systems - Range Breaker (ORB)" ad Adam supplied        |
//|  (TradingView strategy on MNQ 3m, sold on Whop).                  |
//|                                                                  |
//|  Rules as read from the frames (all times New York):              |
//|   1. Range  - high/low of 11:00-11:05 (vendor's winning setting;  |
//|               their own 9:30 run lost: PF 0.99, 15.8% DD).        |
//|   2. Filter - range size must be RangeQualityMin..Max % of price. |
//|   3. Entry  - buy stop at the range high / sell stop at the low,  |
//|               per-weekday long/short switches. One trade per day. |
//|               Both sides enabled = OCO (first fill kills other).  |
//|   4. TP = entry + TP% of range size, SL = entry - SL% of range    |
//|      size (vendor defaults 40 / 60 -> risk 1.5 to make 1).        |
//|   5. Session end (16:00) - pendings deleted, position flattened.  |
//|   6. Daily loss limit (% of the day's starting equity) - pendings |
//|      deleted and position closed when hit.                        |
//|  Frames only show Monday + Tuesday settings. Wed-Fri defaults are |
//|  copies of Monday, NOT the vendor's values.                       |
//|                                                                  |
//|  Range is read from closed M1 bars whatever the chart timeframe,  |
//|  so the EA can sit on any chart.                                  |
//|                                                                  |
//|  Time: every decision runs on New York wall-clock time.           |
//|   TIME_NY_PLUS_7 (default): server = NY + 7h all year (the usual  |
//|   GMT+2/+3 broker; AAAFx is UTC+3 = NY+7 in summer).              |
//|   TIME_FIXED_UTC: server = UTC + ServerUTCOffsetHours, NY from a  |
//|   real US DST calendar.                                           |
//|   AAAFx history quirk: its broker history before the weekend of   |
//|   2026-03-06 is stored at UTC+0 (proven from broker bars, see the |
//|   XAUUSD Tick Data Infrastructure note). With ApplyUTC0History on,|
//|   server times before UTC0HistoryEnd are treated as UTC+0.        |
//|                                                                  |
//|  Sizing + R accounting carried over from TWI SMC POI v1.01:       |
//|  lots from OrderCalcProfit() only, R base frozen at the ACTUAL    |
//|  fill, NetPnL sums every deal (profit+commission+swap+fee).       |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TIME_MODE  { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_ENTRY_MODE { ENTRY_STOP_ORDER, ENTRY_CLOSE_BEYOND };

//--- inputs ---------------------------------------------------------
input group "=== General ==="
input long            MagicNumber                   = 20260927;
input string          TradeComment                  = "TWI Range Breaker";
input double          RiskPercent                   = 0.5;   // % of equity risked per trade (replaces the vendor's fixed contracts)
input double          RiskOvershootTolerancePercent = 10.0;  // broker min lot may push risk over by at most this relative %; beyond that the trade is skipped
input double          DailyLossLimitPercent         = 2.0;   // vendor: $1,000 on a $50K account = 2%
input int             MaxSpreadPoints               = 0;     // 0 = off (symbol not settled yet; spread is logged at every entry)
input ENUM_ENTRY_MODE EntryMode                     = ENTRY_STOP_ORDER; // stop order at the range edge, or market on a closed M1 bar beyond it
input bool            DrawRange                     = true;
input bool            DebugMode                     = true;

input group "=== Times (New York) ==="
input string          RangeStart                    = "11:00";
input string          RangeEnd                      = "11:05";
input string          SessionStart                  = "09:30";
input string          SessionEnd                    = "16:00";   // pendings deleted + position flattened here
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;          // TIME_FIXED_UTC only
input bool            ApplyUTC0History              = true;       // AAAFx: history before the cutoff is stored at UTC+0
input datetime        UTC0HistoryEnd                = D'2026.03.07 00:00'; // server time; the switch happened over the 2026-03-06 weekend

input group "=== Monday ==="
input bool   MonTrade = true;  input bool MonLongs = true;  input bool MonShorts = false;
input double MonTP    = 40;    input double MonSL  = 60;    input double MonQMin = 0.1; input double MonQMax = 0.5;
input group "=== Tuesday ==="
input bool   TueTrade = true;  input bool TueLongs = true;  input bool TueShorts = false;
input double TueTP    = 40;    input double TueSL  = 60;    input double TueQMin = 0.1; input double TueQMax = 0.5;
input group "=== Wednesday (not shown in the frames - Monday copy) ==="
input bool   WedTrade = true;  input bool WedLongs = true;  input bool WedShorts = false;
input double WedTP    = 40;    input double WedSL  = 60;    input double WedQMin = 0.1; input double WedQMax = 0.5;
input group "=== Thursday (not shown in the frames - Monday copy) ==="
input bool   ThuTrade = true;  input bool ThuLongs = true;  input bool ThuShorts = false;
input double ThuTP    = 40;    input double ThuSL  = 60;    input double ThuQMin = 0.1; input double ThuQMax = 0.5;
input group "=== Friday (not shown in the frames - Monday copy) ==="
input bool   FriTrade = true;  input bool FriLongs = true;  input bool FriShorts = false;
input double FriTP    = 40;    input double FriSL  = 60;    input double FriQMin = 0.1; input double FriQMax = 0.5;

//--- state ----------------------------------------------------------
enum ENUM_DAY_STATE { D_WAIT_RANGE, D_ARMED, D_ACTIVE, D_DONE };

struct DayParams { bool trade, longs, shorts; double tp, sl, qMin, qMax; };

struct Day
  {
   ENUM_DAY_STATE state;
   datetime nyDate;                 // NY midnight (NY-repr)
   int      dow;
   DayParams p;
   datetime rsSrv, reSrv, ssSrv, seSrv; // range start/end, session start/end in server time
   double   hi, lo, size;
   ulong    buyTicket, sellTicket;
   bool     longDone, shortDone;    // side already used (ENTRY_CLOSE_BEYOND)
   bool     isShort;
   ulong    posTicket;
   double   slPrice, tpPrice, plannedRiskMoney, initialRiskMoney;
   bool     riskValid, filledBeyondSL;
   double   startEquity;
  };

Day      D;
double   g_point;
int      g_rsMin, g_reMin, g_ssMin, g_seMin;

//--- funnel + results -----------------------------------------------
int st_days = 0, st_dayOff = 0, st_noBars = 0, st_qLow = 0, st_qHigh = 0, st_armed = 0;
int st_spread = 0, st_stopsLevel = 0, st_riskReject = 0, st_orderFail = 0, st_alreadyRan = 0;
int st_noFill = 0, st_filled = 0, st_filledBeyondSL = 0, st_dailyLimit = 0;
int st_exitTP = 0, st_exitSL = 0, st_exitSession = 0, st_exitOther = 0;
int st_wins = 0, st_losses = 0, st_be = 0, st_buy = 0, st_sell = 0, st_buyWins = 0, st_sellWins = 0;
int st_consec = 0, st_maxConsec = 0, st_rInvalid = 0;
double st_grossProfit = 0, st_grossLoss = 0, st_sumR = 0, st_buyR = 0, st_sellR = 0;
double st_commission = 0, st_swap = 0, st_fee = 0;
int    st_dowTrades[7], st_dowWins[7];
double st_dowR[7];

//====================================================================
void Dbg(string m) { if(DebugMode) Print("[Range Breaker] ", m); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }
string P(double p) { return DoubleToString(p, _Digits); }
string DowName(int d) { string n[7] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}; return n[d]; }

int ParseHHMM(string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return -1;
   int h = (int)StringToInteger(parts[0]), m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
  }

//====================================================================
// TIME - server <-> New York
//====================================================================
datetime NthSunday(int year, int month, int n)
  {
   datetime first = StringToTime(StringFormat("%04d.%02d.01", year, month));
   MqlDateTime f; TimeToStruct(first, f);
   int add = (7 - f.day_of_week) % 7;
   return first + (add + 7 * (n - 1)) * 86400;
  }

// US DST: 2nd Sunday of March 07:00 UTC -> 1st Sunday of November 06:00 UTC
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

// inverse by search: the server time whose NY wall-clock equals ny (0 if none)
datetime NYToServer(datetime ny)
  {
   if(ServerToNY(ny + 7 * 3600) == ny) return ny + 7 * 3600;
   for(int k = -14; k <= 14; k++)
     {
      datetime s = ny + k * 3600;
      if(ServerToNY(s) == ny) return s;
     }
   return 0;
  }

//====================================================================
// RISK SIZING - identical method to TWI SMC POI v1.01
//====================================================================
bool ComputeLots(bool isShort, double entry, double sl, double &outLots, double &outRiskMoney, string &why)
  {
   outLots = 0; outRiskMoney = 0; why = "";
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * RiskPercent / 100.0;
   ENUM_ORDER_TYPE ot = isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

   double pl1 = 0;
   ResetLastError();
   if(!OrderCalcProfit(ot, _Symbol, 1.0, entry, sl, pl1)) { why = StringFormat("OrderCalcProfit 1-lot failed, err=%d", GetLastError()); return false; }
   double perLot = MathAbs(pl1);
   if(perLot <= 0) { why = "1-lot risk resolved to zero"; return false; }

   double lots = MathFloor((riskMoney / perLot) / step) * step;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   if(lots <= 0) { why = "lots resolved to zero"; return false; }

   double plF = 0;
   ResetLastError();
   if(!OrderCalcProfit(ot, _Symbol, lots, entry, sl, plF)) { why = StringFormat("OrderCalcProfit final failed, err=%d", GetLastError()); return false; }
   double pct = equity > 0 ? MathAbs(plF) / equity * 100.0 : 0;
   double ceiling = RiskPercent * (1.0 + RiskOvershootTolerancePercent / 100.0);

   Print("RISK CHECK:");
   PrintFormat("  Equity=$%.2f  TargetRisk=%.2f%% ($%.2f)", equity, RiskPercent, riskMoney);
   PrintFormat("  Entry=%s  SL=%s  1-lot SL loss=$%.2f  Lots=%.2f", P(entry), P(sl), perLot, lots);
   PrintFormat("  ProjectedLoss=$%.2f  ActualRisk=%.4f%%  (ceiling %.4f%%)", MathAbs(plF), pct, ceiling);

   if(pct > ceiling) { why = StringFormat("projected risk %.4f%% > ceiling %.4f%%", pct, ceiling); return false; }
   outLots = lots;
   outRiskMoney = MathAbs(plF);
   return true;
  }

//====================================================================
// DAY SETUP
//====================================================================
DayParams ParamsFor(int dow)
  {
   DayParams p; ZeroMemory(p);
   switch(dow)
     {
      case 1: p.trade = MonTrade; p.longs = MonLongs; p.shorts = MonShorts; p.tp = MonTP; p.sl = MonSL; p.qMin = MonQMin; p.qMax = MonQMax; break;
      case 2: p.trade = TueTrade; p.longs = TueLongs; p.shorts = TueShorts; p.tp = TueTP; p.sl = TueSL; p.qMin = TueQMin; p.qMax = TueQMax; break;
      case 3: p.trade = WedTrade; p.longs = WedLongs; p.shorts = WedShorts; p.tp = WedTP; p.sl = WedSL; p.qMin = WedQMin; p.qMax = WedQMax; break;
      case 4: p.trade = ThuTrade; p.longs = ThuLongs; p.shorts = ThuShorts; p.tp = ThuTP; p.sl = ThuSL; p.qMin = ThuQMin; p.qMax = ThuQMax; break;
      case 5: p.trade = FriTrade; p.longs = FriLongs; p.shorts = FriShorts; p.tp = FriTP; p.sl = FriSL; p.qMin = FriQMin; p.qMax = FriQMax; break;
     }
   return p;
  }

void NewDay(datetime nyNow)
  {
   ZeroMemory(D);
   D.nyDate = (datetime)((long)nyNow - (long)nyNow % 86400);
   MqlDateTime dt; TimeToStruct(D.nyDate, dt);
   D.dow = dt.day_of_week;
   D.p = ParamsFor(D.dow);
   D.startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   D.state = D_WAIT_RANGE;

   if(D.dow == 0 || D.dow == 6) { D.state = D_DONE; return; }
   st_days++;
   if(!D.p.trade || (!D.p.longs && !D.p.shorts)) { st_dayOff++; D.state = D_DONE; Dbg(DowName(D.dow) + " switched off"); return; }

   D.rsSrv = NYToServer(D.nyDate + g_rsMin * 60);
   D.reSrv = NYToServer(D.nyDate + g_reMin * 60);
   D.ssSrv = NYToServer(D.nyDate + g_ssMin * 60);
   D.seSrv = NYToServer(D.nyDate + g_seMin * 60);
   if(D.rsSrv == 0 || D.reSrv == 0 || D.seSrv == 0) { D.state = D_DONE; Dbg("NY->server conversion failed (DST gap?)"); return; }
   Dbg(StringFormat("%s %s NY | range %s-%s server | session end %s server", DowName(D.dow),
                    TimeToString(D.nyDate, TIME_DATE), TimeToString(D.rsSrv, TIME_MINUTES), TimeToString(D.reSrv, TIME_MINUTES),
                    TimeToString(D.seSrv, TIME_MINUTES)));
  }

// Range from closed M1 bars in [range start, range end)
bool BuildRange()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, D.rsSrv, D.reSrv - 1, r);
   if(n <= 0) { st_noBars++; Dbg("no M1 bars inside the range window - day skipped"); return false; }
   D.hi = r[0].high; D.lo = r[0].low;
   for(int i = 1; i < n; i++) { D.hi = MathMax(D.hi, r[i].high); D.lo = MathMin(D.lo, r[i].low); }
   D.size = D.hi - D.lo;
   int expected = (g_reMin - g_rsMin);
   double mid = (D.hi + D.lo) / 2.0;
   double q = mid > 0 ? D.size / mid * 100.0 : 0;
   Dbg(StringFormat("RANGE %s-%s  size %s (%.3f%% of price)  bars %d/%d", P(D.lo), P(D.hi), P(D.size), q, n, expected));

   if(DrawRange)
     {
      string nm = "TWIRB_" + TimeToString(D.nyDate, TIME_DATE);
      ObjectDelete(0, nm);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, D.rsSrv, D.hi, D.seSrv, D.lo);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrSeaGreen);
      ObjectSetInteger(0, nm, OBJPROP_FILL, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
     }

   if(D.size <= 0 || q < D.p.qMin) { st_qLow++;  Dbg(StringFormat("range quality %.3f%% < min %.3f%% - day skipped", q, D.p.qMin)); return false; }
   if(q > D.p.qMax)                { st_qHigh++; Dbg(StringFormat("range quality %.3f%% > max %.3f%% - day skipped", q, D.p.qMax)); return false; }
   return true;
  }

void LevelsFor(bool sh, double &entry, double &sl, double &tp)
  {
   entry = sh ? D.lo : D.hi;
   sl    = sh ? entry + D.size * D.p.sl / 100.0 : entry - D.size * D.p.sl / 100.0;
   tp    = sh ? entry - D.size * D.p.tp / 100.0 : entry + D.size * D.p.tp / 100.0;
   entry = NormPrice(entry); sl = NormPrice(sl); tp = NormPrice(tp);
  }

// Place one side. market=true sends at market with the range-derived SL/TP.
bool PlaceSide(bool sh, bool market)
  {
   double entry, sl, tp;
   LevelsFor(sh, entry, sl, tp);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ref = sh ? bid : ask;

   if(!market && (sh ? bid <= entry : ask >= entry))
     {
      // already through the edge when the range closed -> take it at market unless it already ran to TP
      if(sh ? bid <= tp : ask >= tp) { st_alreadyRan++; Dbg((sh ? "SHORT" : "LONG") + string(" side: price already at TP when armed - skipped")); return false; }
      market = true;
     }
   if(market)
     {
      entry = ref;
      if(sh ? entry >= sl : entry <= sl) { st_alreadyRan++; Dbg("price already beyond the stop - skipped"); return false; }
      if(sh ? entry <= tp : entry >= tp) { st_alreadyRan++; Dbg("price already beyond the target - skipped"); return false; }
     }

   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints) { st_spread++; Dbg(StringFormat("spread %d > %d - skipped", spread, MaxSpreadPoints)); return false; }

   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   if(minDist > 0 && (MathAbs(entry - sl) <= minDist || MathAbs(tp - entry) <= minDist || (!market && MathAbs(ref - entry) <= minDist)))
     { st_stopsLevel++; Dbg("inside broker stops level - skipped, never widened"); return false; }

   double lots, plannedRisk; string why;
   if(!ComputeLots(sh, entry, sl, lots, plannedRisk, why)) { st_riskReject++; Dbg("risk sizing rejected: " + why); return false; }

   bool ok;
   if(market) ok = sh ? trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment) : trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment);
   else       ok = sh ? trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment)
                      : trade.BuyStop (lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment);
   if(!ok) { st_orderFail++; Dbg(StringFormat("order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription())); return false; }

   if(!market) { if(sh) D.sellTicket = trade.ResultOrder(); else D.buyTicket = trade.ResultOrder(); }
   D.slPrice = sl; D.tpPrice = tp; D.plannedRiskMoney = plannedRisk;   // overwritten per side; re-read from the position on fill
   Dbg(StringFormat("%s %s %.2f lots @ %s  SL %s  TP %s  spread %d", sh ? "SELL" : "BUY", market ? "MARKET" : "STOP",
                    lots, P(entry), P(sl), P(tp), spread));
   return true;
  }

void ArmDay()
  {
   bool ok = BuildRange();
   if(OurPosition() != 0)   // re-init mid-trade (chart/timeframe change): adopt it, never stack a second trade
     { D.state = D_ARMED; CheckFill(); Dbg("existing position adopted"); return; }
   if(!ok) { D.state = D_DONE; return; }
   st_armed++;
   D.state = D_ARMED;
   if(EntryMode == ENTRY_STOP_ORDER)
     {
      bool any = false;
      if(D.p.longs  && PlaceSide(false, false)) any = true;
      if(D.p.shorts && PlaceSide(true,  false)) any = true;
      CheckFill();
      if(!any && D.state == D_ARMED) D.state = D_DONE;
     }
  }

// ENTRY_CLOSE_BEYOND: a closed M1 bar outside the range -> market entry
void CheckCloseBeyond()
  {
   double c = iClose(_Symbol, PERIOD_M1, 1);
   datetime t = iTime(_Symbol, PERIOD_M1, 1);
   if(t < D.reSrv) return;
   if(D.p.longs && !D.longDone && c > D.hi)       { D.longDone = true;  PlaceSide(false, true); CheckFill(); }
   else if(D.p.shorts && !D.shortDone && c < D.lo) { D.shortDone = true; PlaceSide(true,  true); CheckFill(); }
  }

void DeletePendings()
  {
   if(D.buyTicket  != 0 && OrderSelect(D.buyTicket))  trade.OrderDelete(D.buyTicket);
   if(D.sellTicket != 0 && OrderSelect(D.sellTicket)) trade.OrderDelete(D.sellTicket);
   D.buyTicket = 0; D.sellTicket = 0;
  }

//====================================================================
// POSITION TRACKING
//====================================================================
ulong OurPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return tk;
     }
   return 0;
  }

void CheckFill()
  {
   if(D.state != D_ARMED) return;
   ulong pos = OurPosition();
   if(pos == 0) return;
   D.posTicket = pos;
   D.state = D_ACTIVE;
   DeletePendings();   // OCO + one trade per day
   st_filled++;

   D.isShort = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;
   if(D.isShort) st_sell++; else st_buy++;
   double fill = PositionGetDouble(POSITION_PRICE_OPEN);
   double lots = PositionGetDouble(POSITION_VOLUME);
   D.slPrice = PositionGetDouble(POSITION_SL);
   D.tpPrice = PositionGetDouble(POSITION_TP);
   double e0, s0, t0; LevelsFor(D.isShort, e0, s0, t0);
   double plannedPl = 0;
   D.plannedRiskMoney = OrderCalcProfit(D.isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, lots, e0, s0, plannedPl) ? MathAbs(plannedPl) : 0;

   // R denominator frozen at the ACTUAL fill; a fill at/beyond the SL falls back to planned risk
   D.filledBeyondSL = D.isShort ? (fill >= D.slPrice) : (fill <= D.slPrice);
   if(D.filledBeyondSL)
     {
      st_filledBeyondSL++;
      D.initialRiskMoney = D.plannedRiskMoney;
      D.riskValid = D.plannedRiskMoney > 0;
     }
   else
     {
      double pl = 0;
      ResetLastError();
      D.riskValid = OrderCalcProfit(D.isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, lots, fill, D.slPrice, pl) && MathAbs(pl) > 0;
      D.initialRiskMoney = D.riskValid ? MathAbs(pl) : 0;
     }

   Print("R BASE:");
   PrintFormat("  PositionID=%I64u  Direction=%s  Day=%s", pos, D.isShort ? "SELL" : "BUY", DowName(D.dow));
   PrintFormat("  Fill=%s  OriginalSL=%s  TP=%s  Lots=%.2f", P(fill), P(D.slPrice), P(D.tpPrice), lots);
   PrintFormat("  InitialRiskMoney=$%.2f  (riskValid=%s)%s", D.initialRiskMoney, D.riskValid ? "true" : "false",
               D.filledBeyondSL ? "  FILLED BEYOND SL - R base = planned risk" : "");
  }

void RecordClosedTrade()
  {
   double gross = 0, comm = 0, swp = 0, fee = 0;
   bool closed = false;
   long reason = -1;
   if(HistorySelectByPosition(D.posTicket))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         gross += HistoryDealGetDouble(d, DEAL_PROFIT);
         comm  += HistoryDealGetDouble(d, DEAL_COMMISSION);
         swp   += HistoryDealGetDouble(d, DEAL_SWAP);
         fee   += HistoryDealGetDouble(d, DEAL_FEE);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT) { closed = true; reason = HistoryDealGetInteger(d, DEAL_REASON); }
        }
   double net = gross + comm + swp + fee;
   st_commission += comm; st_swap += swp; st_fee += fee;

   if(reason == DEAL_REASON_TP)          st_exitTP++;
   else if(reason == DEAL_REASON_SL)     st_exitSL++;
   else if(reason == DEAL_REASON_EXPERT) st_exitSession++;
   else                                  st_exitOther++;

   bool rInvalid = !closed || !D.riskValid || D.initialRiskMoney <= 0;
   double r = rInvalid ? 0 : net / D.initialRiskMoney;

   if(net > 0)      { st_wins++; st_consec = 0; st_grossProfit += net; st_dowWins[D.dow]++; if(D.isShort) st_sellWins++; else st_buyWins++; }
   else if(net < 0) { st_losses++; st_consec++; st_grossLoss += -net; if(st_consec > st_maxConsec) st_maxConsec = st_consec; }
   else               st_be++;
   st_dowTrades[D.dow]++;

   if(rInvalid) st_rInvalid++;
   else { st_sumR += r; st_dowR[D.dow] += r; if(D.isShort) st_sellR += r; else st_buyR += r; }

   Print("R RESULT:");
   PrintFormat("  PositionID=%I64u  InitialRiskMoney=$%.2f  Exit=%s", D.posTicket, D.initialRiskMoney,
               reason == DEAL_REASON_TP ? "TP" : reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_EXPERT ? "SESSION/EA" : "OTHER");
   PrintFormat("  Gross=$%.2f  Commission=$%.2f  Swap=$%.2f  Fee=$%.2f  NetPnL=$%.2f", gross, comm, swp, fee, net);
   if(rInvalid) Print("  FinalR=R_INVALID (excluded from R aggregates)");
   else         PrintFormat("  FinalR=%.2f", r);
  }

void EndDay(string why)
  {
   if(D.state == D_ARMED) { st_noFill++; Dbg("no fill - " + why); }
   DeletePendings();
   if(D.state == D_ACTIVE)
     {
      ulong pos = OurPosition();
      if(pos != 0) { Dbg("flattening - " + why); trade.PositionClose(pos); }
      if(OurPosition() == 0) RecordClosedTrade();
      else return;   // close failed; retry next tick
     }
   D.state = D_DONE;
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_rsMin = ParseHHMM(RangeStart); g_reMin = ParseHHMM(RangeEnd);
   g_ssMin = ParseHHMM(SessionStart); g_seMin = ParseHHMM(SessionEnd);
   if(g_rsMin < 0 || g_reMin < 0 || g_ssMin < 0 || g_seMin < 0) { Print("Bad time input - use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(g_reMin <= g_rsMin || g_seMin <= g_reMin || g_rsMin < g_ssMin) { Print("Times must satisfy SessionStart <= RangeStart < RangeEnd < SessionEnd"); return INIT_PARAMETERS_INCORRECT; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   ZeroMemory(D); D.state = D_DONE;
   ArrayInitialize(st_dowTrades, 0); ArrayInitialize(st_dowWins, 0); ArrayInitialize(st_dowR, 0);
   PrintFormat("TWI Range Breaker v1.00 on %s | range %s-%s NY | session %s-%s NY | %s | Risk %.2f%% | DailyLimit %.2f%% | TimeMode %s%s",
               _Symbol, RangeStart, RangeEnd, SessionStart, SessionEnd, EnumToString(EntryMode), RiskPercent, DailyLossLimitPercent,
               EnumToString(TimeMode), ApplyUTC0History ? " (+UTC0 history before " + TimeToString(UTC0HistoryEnd) + ")" : "");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime ny  = ServerToNY(now);
   if(D.nyDate == 0 || (datetime)((long)ny - (long)ny % 86400) != D.nyDate)
     {
      if(D.state == D_ARMED || D.state == D_ACTIVE) EndDay("NY day rolled over");
      NewDay(ny);
     }
   if(D.state == D_DONE) return;

   if(D.state == D_ARMED)  CheckFill();
   if(D.state == D_ACTIVE && OurPosition() == 0) { RecordClosedTrade(); D.state = D_DONE; return; }

   // daily loss limit on equity vs the day's start
   if(DailyLossLimitPercent > 0 && (D.state == D_ARMED || D.state == D_ACTIVE)
      && AccountInfoDouble(ACCOUNT_EQUITY) <= D.startEquity * (1.0 - DailyLossLimitPercent / 100.0))
     { st_dailyLimit++; EndDay("daily loss limit hit"); return; }

   if(now >= D.seSrv) { EndDay("session end"); return; }

   if(D.state == D_WAIT_RANGE && now >= D.reSrv) { ArmDay(); return; }
   if(D.state == D_ARMED && EntryMode == ENTRY_CLOSE_BEYOND) CheckCloseBeyond();
  }

void OnDeinit(const int reason)
  {
   DeletePendings();

   int trades = st_wins + st_losses + st_be;
   int validR = trades - st_rInvalid;
   Print("==================== TWI RANGE BREAKER SUMMARY ====================");
   PrintFormat("Days %d -> switched off %d | no range bars %d | quality too small %d | too big %d -> armed %d",
               st_days, st_dayOff, st_noBars, st_qLow, st_qHigh, st_armed);
   PrintFormat("        armed -> spread %d | stops level %d | risk reject %d | order fail %d | already ran %d | no fill %d -> FILLED %d (beyond SL %d)",
               st_spread, st_stopsLevel, st_riskReject, st_orderFail, st_alreadyRan, st_noFill, st_filled, st_filledBeyondSL);
   PrintFormat("Exits: TP %d  SL %d  session/EA %d  other %d | daily-limit stops %d", st_exitTP, st_exitSL, st_exitSession, st_exitOther, st_dailyLimit);
   PrintFormat("Trades %d  W %d  L %d  BE %d  WinRate %.1f%%", trades, st_wins, st_losses, st_be, trades > 0 ? 100.0 * st_wins / trades : 0);
   PrintFormat("Net $%.2f  PF %.2f  Max consecutive losses %d", st_grossProfit - st_grossLoss,
               st_grossLoss > 0 ? st_grossProfit / st_grossLoss : 0, st_maxConsec);
   PrintFormat("Total R %.2f  Avg R %.3f  (R_INVALID %d)", st_sumR, validR > 0 ? st_sumR / validR : 0, st_rInvalid);
   PrintFormat("BUY %d (W %d, R %.2f)  SELL %d (W %d, R %.2f)", st_buy, st_buyWins, st_buyR, st_sell, st_sellWins, st_sellR);
   for(int d = 1; d <= 5; d++)
      PrintFormat("  %s: trades %d  W %d  R %.2f", DowName(d), st_dowTrades[d], st_dowWins[d], st_dowR[d]);
   PrintFormat("Costs: commission $%.2f  swap $%.2f  fee $%.2f (all deals, entry + exit)", st_commission, st_swap, st_fee);
   Print("===================================================================");
  }
//+------------------------------------------------------------------+
