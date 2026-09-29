//+------------------------------------------------------------------+
//|                                     TWI ORB Demand Pullback.mq5 |
//|  Built 2026-09-27 from Pat's (TradeWithPat stream) "Discretion   |
//|  Entry" slides, as our own EA instead of the TWP grid presets.   |
//|                                                                  |
//|  LONG (short is the mirror), all on closed EntryTF bars:         |
//|   1. Range     - NY RangeStart for RangeMinutes (M1 high/low).   |
//|   2. Breakout  - a bar CLOSES above the range high (touch is not |
//|                  enough). Trend filter: close above EMA(TrendTF).|
//|   3. Retest    - a later bar trades back down to the range high. |
//|   4. FVG       - the impulse leg left a bullish fair value gap   |
//|                  (low[k+1] > high[k-1]), switchable.             |
//|   5. Demand    - base of the impulse: last bearish candle at or  |
//|                  before the lowest low between range start and   |
//|                  the breakout. Zone = its low .. body top; must  |
//|                  sit at/below the range midline (switchable).    |
//|   Entry  - buy limit at the demand top (market if already in).   |
//|   SL     - below the range low (or the demand low) + buffer.     |
//|   Exits  - partial at PartialR (SL to break-even), runner at     |
//|            RunnerR. Flat at SessionEnd. One trade per day.       |
//|   Cancel - close back through the range low, or EntryCutoff.     |
//|                                                                  |
//|  Deliberately NOT here: grid, martingale, averaging down.        |
//|  Every trade has a hard stop from the first tick.                |
//|                                                                  |
//|  Time, sizing and R accounting carried over from TWI Range       |
//|  Breaker v1.00 (NY+7 server clock, AAAFx UTC+0 history before    |
//|  2026-03-07, lots from OrderCalcProfit only, R base frozen at    |
//|  the actual fill, NetPnL sums every deal of the position).       |
//|  Pending orders are only forgotten once the broker confirms they |
//|  are gone; any stray order/position of ours is cleaned up.       |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TIME_MODE { TIME_NY_PLUS_7, TIME_FIXED_UTC };
enum ENUM_SL_MODE   { SL_RANGE_OPPOSITE, SL_DEMAND_EDGE };

//--- inputs ---------------------------------------------------------
input group "=== General ==="
input long            MagicNumber                   = 20260928;
input string          TradeComment                  = "TWI ORB Demand";
input double          RiskPercent                   = 0.5;   // % of equity risked per trade
input double          RiskOvershootTolerancePercent = 10.0;  // broker min lot may push risk over by at most this relative %
input double          DailyLossLimitPercent         = 2.0;   // equity vs the day's start; 0 = off
input int             MaxSpreadPoints               = 0;     // 0 = off (spread is logged at every entry)
input bool            DebugMode                     = true;

input group "=== Times (New York) ==="
input string          RangeStart                    = "09:30";
input int             RangeMinutes                  = 15;
input string          EntryCutoff                   = "12:00";  // no new setups/pendings after this
input string          SessionEnd                    = "16:00";  // flat here
input ENUM_TIME_MODE  TimeMode                      = TIME_NY_PLUS_7;
input int             ServerUTCOffsetHours          = 3;          // TIME_FIXED_UTC only
input bool            ApplyUTC0History              = true;       // AAAFx: history before the cutoff is stored at UTC+0
input datetime        UTC0HistoryEnd                = D'2026.03.07 00:00';

input group "=== Model ==="
input ENUM_TIMEFRAMES EntryTF                       = PERIOD_M5;
input bool            TradeLongs                    = true;
input bool            TradeShorts                   = true;
input bool            UseTrendFilter                = true;       // longs only above EMA, shorts only below
input ENUM_TIMEFRAMES TrendTF                       = PERIOD_H1;
input int             TrendEMAPeriod                = 200;
input bool            RequireRetest                 = true;
input bool            RequireFVG                    = true;
input bool            DemandBelowMidline            = true;       // demand top must be at/below the range midline (above for shorts)
input int             BaseSearchBars                = 5;          // how far back from the leg extreme to look for the opposing base candle

input group "=== Exits ==="
input ENUM_SL_MODE    SLMode                        = SL_RANGE_OPPOSITE;
input int             SLBufferPoints                = 20;
input double          PartialR                      = 1.0;        // 0 = no partial
input double          PartialPercent                = 50.0;
input bool            MoveToBEAfterPartial          = true;
input int             BEOffsetPoints                = 5;
input double          RunnerR                       = 3.0;

//--- state ----------------------------------------------------------
enum ENUM_DAY_STATE { D_WAIT_RANGE, D_WAIT_BREAK, D_WAIT_RETEST, D_ARMED, D_ACTIVE, D_DONE };

struct Day
  {
   ENUM_DAY_STATE state;
   datetime nyDate;
   int      dow;
   datetime rsSrv, reSrv, cutSrv, seSrv;
   double   hi, lo, mid;
   bool     isShort;
   datetime boTime;
   double   zoneTop, zoneBot;
   datetime zoneTime;
   double   entry, sl, tp;
   ulong    posTicket;
   bool     partialDone;
   double   fillPrice, riskDist;
   double   plannedRiskMoney, initialRiskMoney;
   bool     riskValid;
   double   startEquity;
  };

Day      D;
double   g_point;
int      g_rsMin, g_cutMin, g_seMin;
int      g_ema = INVALID_HANDLE;
datetime g_lastBar = 0;

//--- funnel + results -----------------------------------------------
int st_days = 0, st_noBars = 0, st_trendBlocked = 0, st_breaks = 0, st_breakLong = 0, st_breakShort = 0;
int st_failedBeforeRetest = 0, st_noRetest = 0, st_noFVG = 0, st_demandAboveMid = 0, st_badGeometry = 0;
int st_spread = 0, st_stopsLevel = 0, st_riskReject = 0, st_orderFail = 0;
int st_armed = 0, st_cancelThrough = 0, st_cancelCutoff = 0, st_filled = 0, st_marketEntry = 0;
int st_partials = 0, st_partialSkipped = 0, st_dailyLimit = 0, st_stray = 0;
int st_exitTP = 0, st_exitSL = 0, st_exitSession = 0, st_exitOther = 0;
int st_wins = 0, st_losses = 0, st_be = 0, st_buy = 0, st_sell = 0, st_buyWins = 0, st_sellWins = 0;
int st_consec = 0, st_maxConsec = 0, st_rInvalid = 0;
double st_grossProfit = 0, st_grossLoss = 0, st_sumR = 0, st_buyR = 0, st_sellR = 0;
double st_commission = 0, st_swap = 0, st_fee = 0;

//====================================================================
void Dbg(string m) { if(DebugMode) Print("[ORB Demand] ", m); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }
string P(double p) { return DoubleToString(p, _Digits); }
double O(int i) { return iOpen(_Symbol, EntryTF, i); }
double H(int i) { return iHigh(_Symbol, EntryTF, i); }
double L(int i) { return iLow(_Symbol, EntryTF, i); }
double C(int i) { return iClose(_Symbol, EntryTF, i); }
datetime T(int i) { return iTime(_Symbol, EntryTF, i); }

int ParseHHMM(string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return -1;
   int h = (int)StringToInteger(parts[0]), m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
  }

//====================================================================
// TIME - server <-> New York (same as TWI Range Breaker)
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
   for(int k = -14; k <= 14; k++)
     {
      datetime s = ny + k * 3600;
      if(ServerToNY(s) == ny) return s;
     }
   return 0;
  }

//====================================================================
// RISK SIZING - identical method to TWI Range Breaker / SMC POI
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
// ORDERS / POSITIONS OF OURS
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

int OurOrderCount()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber) n++;
     }
   return n;
  }

// true only when the broker shows no pending order of ours left
bool DeleteOurOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         trade.OrderDelete(tk);
     }
   return OurOrderCount() == 0;
  }

//====================================================================
// DAY SETUP
//====================================================================
void NewDay(datetime nyNow)
  {
   ZeroMemory(D);
   D.nyDate = (datetime)((long)nyNow - (long)nyNow % 86400);
   MqlDateTime dt; TimeToStruct(D.nyDate, dt);
   D.dow = dt.day_of_week;
   D.startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   D.state = D_WAIT_RANGE;
   if(D.dow == 0 || D.dow == 6) { D.state = D_DONE; return; }
   st_days++;

   D.rsSrv  = NYToServer(D.nyDate + g_rsMin * 60);
   D.reSrv  = NYToServer(D.nyDate + (g_rsMin + RangeMinutes) * 60);
   D.cutSrv = NYToServer(D.nyDate + g_cutMin * 60);
   D.seSrv  = NYToServer(D.nyDate + g_seMin * 60);
   if(D.rsSrv == 0 || D.reSrv == 0 || D.cutSrv == 0 || D.seSrv == 0) { D.state = D_DONE; Dbg("NY->server conversion failed"); return; }
   Dbg(StringFormat("%s NY | range %s-%s | cutoff %s | flat %s (server)", TimeToString(D.nyDate, TIME_DATE),
                    TimeToString(D.rsSrv, TIME_MINUTES), TimeToString(D.reSrv, TIME_MINUTES),
                    TimeToString(D.cutSrv, TIME_MINUTES), TimeToString(D.seSrv, TIME_MINUTES)));
  }

bool BuildRange()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, D.rsSrv, D.reSrv - 1, r);
   if(n <= 0) { st_noBars++; Dbg("no M1 bars in the range window - day skipped"); return false; }
   D.hi = r[0].high; D.lo = r[0].low;
   for(int i = 1; i < n; i++) { D.hi = MathMax(D.hi, r[i].high); D.lo = MathMin(D.lo, r[i].low); }
   D.mid = (D.hi + D.lo) / 2.0;
   Dbg(StringFormat("RANGE %s-%s  mid %s  bars %d/%d", P(D.lo), P(D.hi), P(D.mid), n, RangeMinutes));
   return D.hi > D.lo;
  }

bool TrendAllows(bool isShort)
  {
   if(!UseTrendFilter) return true;
   double v[];
   if(CopyBuffer(g_ema, 0, 1, 1, v) != 1) return false;
   return isShort ? C(1) < v[0] : C(1) > v[0];
  }

// Demand (long) / supply (short): base candle of the impulse leg
bool FindZone()
  {
   int rsShift = iBarShift(_Symbol, EntryTF, D.rsSrv);
   int boShift = iBarShift(_Symbol, EntryTF, D.boTime);
   if(rsShift < boShift || boShift < 1) return false;
   int cnt = rsShift - boShift + 1;
   int ext = D.isShort ? iHighest(_Symbol, EntryTF, MODE_HIGH, cnt, boShift)
                       : iLowest (_Symbol, EntryTF, MODE_LOW,  cnt, boShift);
   if(ext < 0) return false;
   int base = ext;
   for(int i = ext; i <= ext + BaseSearchBars && i <= rsShift + BaseSearchBars; i++)
     {
      bool opposing = D.isShort ? (C(i) > O(i)) : (C(i) < O(i));
      if(opposing) { base = i; break; }
     }
   if(D.isShort) { D.zoneBot = MathMin(O(base), C(base)); D.zoneTop = MathMax(H(base), H(ext)); }
   else          { D.zoneTop = MathMax(O(base), C(base)); D.zoneBot = MathMin(L(base), L(ext)); }
   D.zoneTime = T(base);
   return D.zoneTop > D.zoneBot;
  }

// Fair value gap anywhere from the zone candle to the bar after the breakout
bool HasFVG()
  {
   int from = iBarShift(_Symbol, EntryTF, D.zoneTime);
   int boShift = iBarShift(_Symbol, EntryTF, D.boTime);
   int to = MathMax(boShift - 1, 1);            // bar after the breakout (already closed)
   for(int k = from - 1; k >= to + 0 && k >= 1; k--)
     {
      // candle k is the middle one: gap between k+1 (older) and k-1 (newer)
      if(k - 1 < 1) break;
      if(!D.isShort && L(k - 1) > H(k + 1)) return true;
      if( D.isShort && H(k - 1) < L(k + 1)) return true;
     }
   return false;
  }

//====================================================================
// ENTRY
//====================================================================
void PlaceEntry()
  {
   bool sh = D.isShort;
   if(!FindZone()) { st_badGeometry++; Dbg("no zone found"); D.state = D_DONE; return; }
   if(RequireFVG && !HasFVG()) { st_noFVG++; Dbg("no fair value gap in the leg - skipped"); D.state = D_DONE; return; }
   if(DemandBelowMidline && (sh ? D.zoneBot < D.mid : D.zoneTop > D.mid))
     { st_demandAboveMid++; Dbg(StringFormat("zone %s-%s not beyond the midline %s - skipped", P(D.zoneBot), P(D.zoneTop), P(D.mid))); D.state = D_DONE; return; }

   double entry = sh ? D.zoneBot : D.zoneTop;
   double ref   = SLMode == SL_RANGE_OPPOSITE ? (sh ? MathMax(D.hi, D.zoneTop) : MathMin(D.lo, D.zoneBot))   // beyond whichever is further
                                        : (sh ? D.zoneTop : D.zoneBot);
   double sl    = sh ? ref + SLBufferPoints * g_point : ref - SLBufferPoints * g_point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool market = sh ? (bid >= entry) : (ask <= entry);
   if(market) entry = sh ? bid : ask;
   entry = NormPrice(entry); sl = NormPrice(sl);
   double risk = sh ? sl - entry : entry - sl;
   if(risk <= 0) { st_badGeometry++; Dbg("price already beyond the stop - skipped"); D.state = D_DONE; return; }
   double tp = NormPrice(sh ? entry - RunnerR * risk : entry + RunnerR * risk);

   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints) { st_spread++; Dbg(StringFormat("spread %d > %d", spread, MaxSpreadPoints)); D.state = D_DONE; return; }
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double refPx = sh ? bid : ask;
   if(minDist > 0 && (risk <= minDist || (!market && MathAbs(refPx - entry) <= minDist)))
     { st_stopsLevel++; Dbg("inside broker stops level - skipped"); D.state = D_DONE; return; }

   double lots, planned; string why;
   if(!ComputeLots(sh, entry, sl, lots, planned, why)) { st_riskReject++; Dbg("risk sizing rejected: " + why); D.state = D_DONE; return; }

   bool ok;
   if(market) ok = sh ? trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment) : trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment);
   else       ok = sh ? trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment)
                      : trade.BuyLimit (lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment);
   if(!ok) { st_orderFail++; Dbg(StringFormat("order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription())); D.state = D_DONE; return; }

   st_armed++; if(market) st_marketEntry++;
   D.entry = entry; D.sl = sl; D.tp = tp; D.plannedRiskMoney = planned;
   D.state = D_ARMED;
   Dbg(StringFormat("%s %s %.2f @ %s  SL %s  TP %s (%.1fR)  zone %s-%s  spread %d", sh ? "SELL" : "BUY", market ? "MARKET" : "LIMIT",
                    lots, P(entry), P(sl), P(tp), RunnerR, P(D.zoneBot), P(D.zoneTop), spread));
   CheckFill();
  }

void CheckFill()
  {
   ulong pos = OurPosition();
   if(pos == 0) return;
   D.posTicket = pos;
   D.state = D_ACTIVE;
   DeleteOurOrders();
   st_filled++;
   D.isShort = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;
   if(D.isShort) st_sell++; else st_buy++;
   double fill = PositionGetDouble(POSITION_PRICE_OPEN);
   double lots = PositionGetDouble(POSITION_VOLUME);
   D.fillPrice = fill;
   D.riskDist = D.isShort ? D.sl - fill : fill - D.sl;
   if(D.riskDist <= 0)
     {
      D.initialRiskMoney = D.plannedRiskMoney;
      D.riskValid = D.plannedRiskMoney > 0;
      D.riskDist = MathAbs(D.entry - D.sl);
     }
   else
     {
      double pl = 0;
      D.riskValid = OrderCalcProfit(D.isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, lots, fill, D.sl, pl) && MathAbs(pl) > 0;
      D.initialRiskMoney = D.riskValid ? MathAbs(pl) : 0;
     }
   Print("R BASE:");
   PrintFormat("  PositionID=%I64u  %s  Fill=%s  SL=%s  TP=%s  Lots=%.2f  InitialRiskMoney=$%.2f",
               pos, D.isShort ? "SELL" : "BUY", P(fill), P(D.sl), P(D.tp), lots, D.initialRiskMoney);
  }

// Partial at PartialR, then stop to break-even
void ManagePosition()
  {
   if(D.partialDone || PartialR <= 0) return;
   ulong pos = OurPosition();
   if(pos == 0) return;
   double px = D.isShort ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double gained = D.isShort ? D.fillPrice - px : px - D.fillPrice;
   if(gained < PartialR * D.riskDist) return;

   D.partialDone = true;
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double part = MathFloor(vol * PartialPercent / 100.0 / step) * step;
   if(part >= minL && vol - part >= minL)
     {
      if(trade.PositionClosePartial(pos, part)) { st_partials++; Dbg(StringFormat("partial %.2f of %.2f closed at %.1fR", part, vol, PartialR)); }
     }
   else { st_partialSkipped++; Dbg(StringFormat("volume %.2f too small to split - partial skipped", vol)); }

   if(MoveToBEAfterPartial && OurPosition() != 0)
     {
      double be = NormPrice(D.isShort ? D.fillPrice - BEOffsetPoints * g_point : D.fillPrice + BEOffsetPoints * g_point);
      if(trade.PositionModify(OurPosition(), be, D.tp)) { D.sl = be; Dbg("stop to break-even " + P(be)); }
     }
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
   if(reason == DEAL_REASON_TP) st_exitTP++; else if(reason == DEAL_REASON_SL) st_exitSL++;
   else if(reason == DEAL_REASON_EXPERT) st_exitSession++; else st_exitOther++;

   bool rInvalid = !closed || !D.riskValid || D.initialRiskMoney <= 0;
   double r = rInvalid ? 0 : net / D.initialRiskMoney;
   if(net > 0)      { st_wins++; st_consec = 0; st_grossProfit += net; if(D.isShort) st_sellWins++; else st_buyWins++; }
   else if(net < 0) { st_losses++; st_consec++; st_grossLoss += -net; if(st_consec > st_maxConsec) st_maxConsec = st_consec; }
   else               st_be++;
   if(rInvalid) st_rInvalid++;
   else { st_sumR += r; if(D.isShort) st_sellR += r; else st_buyR += r; }

   Print("R RESULT:");
   PrintFormat("  PositionID=%I64u  Exit=%s  Partial=%s  Gross=$%.2f  Costs=$%.2f  NetPnL=$%.2f  FinalR=%s",
               D.posTicket, reason == DEAL_REASON_TP ? "TP" : reason == DEAL_REASON_SL ? "SL" : reason == DEAL_REASON_EXPERT ? "EA" : "OTHER",
               D.partialDone ? "yes" : "no", gross, comm + swp + fee, net, rInvalid ? "R_INVALID" : DoubleToString(r, 2));
  }

// Close out the day; stays open (retries next tick) until the broker confirms everything is gone
void EndDay(string why)
  {
   if(D.state == D_ARMED || D.state == D_WAIT_RETEST || D.state == D_WAIT_BREAK)
     {
      if(D.state == D_ARMED) { if(why == "entry cutoff") st_cancelCutoff++; Dbg("no fill - " + why); }
     }
   if(!DeleteOurOrders()) { Dbg("pending delete not confirmed (" + why + ") - retrying"); return; }
   ulong pos = OurPosition();
   if(pos != 0)
     {
      if(D.state != D_ACTIVE) { st_stray++; D.posTicket = pos; }
      trade.PositionClose(pos);
      if(OurPosition() != 0) { Dbg("close not confirmed - retrying"); return; }
      RecordClosedTrade();
     }
   D.state = D_DONE;
  }

//====================================================================
// BAR LOGIC
//====================================================================
void OnNewBar()
  {
   datetime t1 = T(1);
   if(t1 < D.reSrv) return;

   // entry window over: drop anything not yet filled
   if(t1 >= D.cutSrv && D.state != D_ACTIVE) { EndDay("entry cutoff"); return; }

   if(D.state == D_WAIT_BREAK)
     {
      bool upBreak = TradeLongs  && C(1) > D.hi;
      bool dnBreak = TradeShorts && C(1) < D.lo;
      if(!upBreak && !dnBreak) return;
      bool sh = dnBreak;
      if(!TrendAllows(sh)) { st_trendBlocked++; Dbg((sh ? "SHORT" : "LONG") + string(" break blocked by trend filter")); return; }
      st_breaks++; if(sh) st_breakShort++; else st_breakLong++;
      D.isShort = sh; D.boTime = t1;
      Dbg(StringFormat("%s BREAK close %s @ %s", sh ? "SHORT" : "LONG", P(C(1)), TimeToString(t1)));
      D.state = D_WAIT_RETEST;   // with RequireRetest off, the next closed bar places the entry without needing a touch
      return;
     }

   if(D.state == D_WAIT_RETEST && t1 > D.boTime)
     {
      bool sh = D.isShort;
      if(sh ? C(1) > D.hi : C(1) < D.lo) { st_failedBeforeRetest++; Dbg("closed back through the far side before the retest"); EndDay("failed break"); return; }
      bool touched = sh ? H(1) >= D.lo : L(1) <= D.hi;
      if(RequireRetest && !touched) return;
      Dbg(RequireRetest ? "RETEST of the range edge" : "retest not required");
      PlaceEntry();
      return;
     }

   if(D.state == D_ARMED)
     {
      if(D.isShort ? C(1) > D.hi : C(1) < D.lo)
        { st_cancelThrough++; Dbg("closed through the range before fill - cancelled"); EndDay("closed through"); return; }
     }
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_rsMin = ParseHHMM(RangeStart); g_cutMin = ParseHHMM(EntryCutoff); g_seMin = ParseHHMM(SessionEnd);
   if(g_rsMin < 0 || g_cutMin < 0 || g_seMin < 0) { Print("Bad time input - use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(RangeMinutes < 1 || g_rsMin + RangeMinutes >= g_cutMin || g_cutMin > g_seMin) { Print("Times must satisfy RangeStart+RangeMinutes < EntryCutoff <= SessionEnd"); return INIT_PARAMETERS_INCORRECT; }
   if(RunnerR <= 0) { Print("RunnerR must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(UseTrendFilter)
     {
      g_ema = iMA(_Symbol, TrendTF, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_ema == INVALID_HANDLE) { Print("EMA handle failed"); return INIT_FAILED; }
     }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   ZeroMemory(D); D.state = D_DONE;
   PrintFormat("TWI ORB Demand Pullback v1.00 on %s | range %s +%d min NY | cutoff %s | flat %s | %s | trend %s | retest %s | FVG %s | below-mid %s | SL %s +%d pts | partial %.1fR %.0f%% BE %s | runner %.1fR | risk %.2f%%",
               _Symbol, RangeStart, RangeMinutes, EntryCutoff, SessionEnd, EnumToString(EntryTF),
               UseTrendFilter ? StringFormat("EMA%d %s", TrendEMAPeriod, EnumToString(TrendTF)) : "off",
               RequireRetest ? "on" : "off", RequireFVG ? "on" : "off", DemandBelowMidline ? "on" : "off",
               EnumToString(SLMode), SLBufferPoints, PartialR, PartialPercent, MoveToBEAfterPartial ? "on" : "off", RunnerR, RiskPercent);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime ny  = ServerToNY(now);
   datetime nyDay = (datetime)((long)ny - (long)ny % 86400);
   if(D.nyDate == 0 || nyDay != D.nyDate)
     {
      if(D.nyDate != 0 && D.state != D_DONE) EndDay("NY day rolled over");
      NewDay(ny);
     }

   // anything of ours the state machine does not own gets cleaned up
   if(D.state != D_ARMED && D.state != D_ACTIVE && OurOrderCount() > 0) DeleteOurOrders();
   if(D.state != D_ACTIVE && D.state != D_ARMED && OurPosition() != 0) { Dbg("stray position found - closing"); D.state = D_ACTIVE; st_stray++; D.posTicket = OurPosition(); EndDay("stray"); }
   if(D.state == D_DONE) return;

   if(D.state == D_ARMED) CheckFill();
   if(D.state == D_ACTIVE)
     {
      if(OurPosition() == 0) { RecordClosedTrade(); D.state = D_DONE; return; }
      ManagePosition();
     }

   if(DailyLossLimitPercent > 0 && (D.state == D_ARMED || D.state == D_ACTIVE)
      && AccountInfoDouble(ACCOUNT_EQUITY) <= D.startEquity * (1.0 - DailyLossLimitPercent / 100.0))
     { st_dailyLimit++; EndDay("daily loss limit"); return; }

   if(now >= D.seSrv) { EndDay("session end"); return; }

   if(D.state == D_WAIT_RANGE && now >= D.reSrv)
     {
      if(!BuildRange()) { D.state = D_DONE; return; }
      D.state = D_WAIT_BREAK;
     }

   datetime bar = T(0);
   if(bar != g_lastBar)
     {
      g_lastBar = bar;
      if(D.state == D_WAIT_BREAK || D.state == D_WAIT_RETEST || D.state == D_ARMED) OnNewBar();
     }
  }

void OnDeinit(const int reason)
  {
   DeleteOurOrders();
   if(g_ema != INVALID_HANDLE) IndicatorRelease(g_ema);
   int trades = st_wins + st_losses + st_be;
   int validR = trades - st_rInvalid;
   Print("==================== TWI ORB DEMAND PULLBACK SUMMARY ====================");
   PrintFormat("Days %d (no range bars %d) | breaks %d (long %d, short %d) | trend-blocked break bars %d",
               st_days, st_noBars, st_breaks, st_breakLong, st_breakShort, st_trendBlocked);
   PrintFormat("  break -> failed before retest %d | no FVG %d | zone not beyond midline %d | bad geometry %d | spread %d | stops %d | risk reject %d | order fail %d",
               st_failedBeforeRetest, st_noFVG, st_demandAboveMid, st_badGeometry, st_spread, st_stopsLevel, st_riskReject, st_orderFail);
   PrintFormat("  armed %d (market %d) -> cancelled: closed through %d, cutoff %d -> FILLED %d",
               st_armed, st_marketEntry, st_cancelThrough, st_cancelCutoff, st_filled);
   PrintFormat("  partials %d (skipped, too small %d) | daily-limit stops %d | stray cleanups %d", st_partials, st_partialSkipped, st_dailyLimit, st_stray);
   PrintFormat("Exits: TP %d  SL %d  EA %d  other %d", st_exitTP, st_exitSL, st_exitSession, st_exitOther);
   PrintFormat("Trades %d  W %d  L %d  BE %d  WinRate %.1f%%", trades, st_wins, st_losses, st_be, trades > 0 ? 100.0 * st_wins / trades : 0);
   PrintFormat("Net $%.2f  PF %.2f  Max consecutive losses %d", st_grossProfit - st_grossLoss, st_grossLoss > 0 ? st_grossProfit / st_grossLoss : 0, st_maxConsec);
   PrintFormat("Total R %.2f  Avg R %.3f  (R_INVALID %d)", st_sumR, validR > 0 ? st_sumR / validR : 0, st_rInvalid);
   PrintFormat("BUY %d (W %d, R %.2f)  SELL %d (W %d, R %.2f)", st_buy, st_buyWins, st_buyR, st_sell, st_sellWins, st_sellR);
   PrintFormat("Costs: commission $%.2f  swap $%.2f  fee $%.2f", st_commission, st_swap, st_fee);
   Print("==========================================================================");
  }
//+------------------------------------------------------------------+
