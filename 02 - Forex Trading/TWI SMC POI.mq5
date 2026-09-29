//+------------------------------------------------------------------+
//|                                                  TWI SMC POI.mq5 |
//|  Simple SMC continuation model, built 2026-09-23 straight from    |
//|  two "Forex School" graphics Adam supplied:                       |
//|    "BOS + Liquidity Sweep + OB = High Probability Long"           |
//|    "Liquidity Sweep to Point of Interest - The Classic SMC Short" |
//|                                                                  |
//|  LONG (short is the mirror):                                      |
//|   1. BOS    - a bar CLOSES above the last confirmed swing high.   |
//|   2. POI    - last bearish candle at/before the low of the leg    |
//|               that caused the break. Zone = its open .. leg low.  |
//|   3. Target - highest high after the break (BSL). Tracked until   |
//|               the sweep, then frozen.                             |
//|   4. Sweep  - the pullback takes out a swing low that formed      |
//|               AFTER the BOS and sits above the POI (inducement).  |
//|   5. Entry  - buy limit at the POI top edge ("LTF POI").          |
//|   6. SL below the POI, TP at the BSL. Skip if RR < MinRR.         |
//|   7. Cancel - POI touched before the sweep, close through the     |
//|               POI, new high above the frozen target, or timeout.  |
//|                                                                  |
//|  Deliberately NOT here: sessions, daily governor, HTF bias, BE,   |
//|  partials, concurrent long/short setups, rejection confirmation.  |
//|  All setup logic reads CLOSED bars only (shift >= 1).             |
//|                                                                  |
//|  Sizing + R accounting carried over from TWI Liquidity Sweep OB   |
//|  EA (validated on real ticks 2026-09-23): lots from               |
//|  OrderCalcProfit() only - this broker's SYMBOL_TRADE_TICK_VALUE   |
//|  for XAUUSD is 100x wrong. InitialRiskMoney is frozen at the      |
//|  ACTUAL fill price. NetPnL sums EVERY deal of the position        |
//|  (entry + exit: profit, commission, swap, fee), so entry-side     |
//|  commission is never dropped.                                     |
//|  v1.01 (2026-09-23): Friday cutoff - no pending/setup over the    |
//|  weekend gap; a fill beyond the SL uses planned risk as R base.   |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- inputs ---------------------------------------------------------
input long   MagicNumber                   = 20260923;
input string TradeComment                  = "TWI SMC POI";
input int    SwingBars                     = 3;    // bars each side of a pivot. Confirmed only after this many bars CLOSE after it
input int    MaxOBSearchBars               = 20;   // how far back from the leg extreme to look for the POI candle
input int    MaxSetupBars                  = 240;  // bars from BOS until an unfilled setup is dropped
input int    SLBufferPoints                = 30;   // stop beyond the POI
input int    TPBufferPoints                = 0;    // stop short of the target liquidity
input double MinRR                         = 1.0;  // skip if target is closer than this
input double RiskPercent                   = 0.5;  // % of equity risked per trade
input double RiskOvershootTolerancePercent = 10.0; // broker min lot may push risk over by at most this relative %; beyond that the trade is rejected
input int    MaxSpreadPoints               = 55;   // AAAFx XAUUSD broker-compatible; real-tick spread audit 2026-09-23
input int    FridayCutoffHour              = 23;   // server hour on Friday: pending orders and waiting setups are cancelled, no new ones placed (no limit rests over the weekend gap)
input bool   DebugMode                     = true;

//--- state ----------------------------------------------------------
enum ENUM_STATE { ST_IDLE, ST_WAIT_SWEEP, ST_PENDING, ST_ACTIVE };

struct Swing { double price; datetime barTime; bool broken; };

struct Setup
  {
   ENUM_STATE state;
   bool     isShort;
   datetime bosTime;
   int      barsAlive;
   double   obTop, obBottom;
   double   target;            // BSL (long) / SSL (short)
   double   inducement;        // the swept post-BOS swing
   ulong    orderTicket;
   ulong    posTicket;
   double   entryPrice, slPrice, tpPrice;
   double   plannedRiskMoney;  // projected loss at placement (limit price -> SL)
   double   initialRiskMoney;
   bool     riskValid;
   bool     filledBeyondSL;
  };

Swing  g_lastHigh, g_lastLow;          // most recent confirmed swings (BOS references)
Swing  g_postHigh, g_postLow;          // most recent confirmed swings formed after the current BOS
Setup  S;
datetime g_lastBar = 0;
double g_point;

//--- funnel + results -----------------------------------------------
int st_bos = 0, st_noOB = 0, st_armed = 0, st_touchBeforeSweep = 0, st_swept = 0;
int st_lowRR = 0, st_spread = 0, st_stopsLevel = 0, st_riskReject = 0, st_orderFail = 0;
int st_filledBeyondSL = 0, st_fridayCancel = 0;
int st_placed = 0, st_filled = 0, st_invalidated = 0, st_targetTaken = 0, st_timeout = 0;
int st_wins = 0, st_losses = 0, st_be = 0, st_buy = 0, st_sell = 0, st_buyWins = 0, st_sellWins = 0;
int st_consec = 0, st_maxConsec = 0, st_rInvalid = 0;
double st_grossProfit = 0, st_grossLoss = 0, st_sumR = 0, st_buyR = 0, st_sellR = 0;
double st_commission = 0, st_swap = 0, st_fee = 0;

//====================================================================
void Dbg(string m) { if(DebugMode) Print("[SMC POI] ", m); }
double Pts(double p) { return p * g_point; }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }
string P(double p) { return DoubleToString(p, _Digits); }

double O(int i) { return iOpen(_Symbol, _Period, i); }
double H(int i) { return iHigh(_Symbol, _Period, i); }
double L(int i) { return iLow(_Symbol, _Period, i); }
double C(int i) { return iClose(_Symbol, _Period, i); }
datetime T(int i) { return iTime(_Symbol, _Period, i); }

//====================================================================
// SWINGS - pivot at shift SwingBars+1, confirmed by the close of bar 1
//====================================================================
void ScanSwings()
  {
   int p = SwingBars + 1;
   if(Bars(_Symbol, _Period) < 2 * SwingBars + 3) return;
   bool isHigh = true, isLow = true;
   for(int k = 1; k <= SwingBars; k++)
     {
      if(H(p) <= H(p + k) || H(p) <= H(p - k)) isHigh = false;
      if(L(p) >= L(p + k) || L(p) >= L(p - k)) isLow  = false;
     }
   if(isHigh)
     {
      g_lastHigh.price = H(p); g_lastHigh.barTime = T(p); g_lastHigh.broken = false;
      if(S.state == ST_WAIT_SWEEP && T(p) >= S.bosTime) { g_postHigh = g_lastHigh; }
     }
   if(isLow)
     {
      g_lastLow.price = L(p); g_lastLow.barTime = T(p); g_lastLow.broken = false;
      if(S.state == ST_WAIT_SWEEP && T(p) >= S.bosTime) { g_postLow = g_lastLow; }
     }
  }

//====================================================================
// RISK SIZING - identical method to TWI Liquidity Sweep OB EA
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
// SETUP
//====================================================================
void Reset(string reason)
  {
   if(S.state != ST_IDLE && reason != "") Dbg((S.isShort ? "SHORT" : "LONG") + string(" setup dropped: ") + reason);
   ZeroMemory(S);
   S.state = ST_IDLE;
   g_postHigh.price = 0; g_postLow.price = 0;
  }

// Bar 1 closed through the last confirmed swing -> arm a setup
void CheckBOS()
  {
   bool bull = g_lastHigh.price > 0 && !g_lastHigh.broken && C(1) > g_lastHigh.price;
   bool bear = g_lastLow.price  > 0 && !g_lastLow.broken  && C(1) < g_lastLow.price;
   Swing ref;
   ZeroMemory(ref);
   if(bull) { ref = g_lastHigh; g_lastHigh.broken = true; }
   if(bear) { ref = g_lastLow;  g_lastLow.broken  = true; }
   if(S.state != ST_IDLE || bull == bear) return;   // busy, nothing, or ambiguous bar

   st_bos++;
   bool isShort = bear;
   int refShift = iBarShift(_Symbol, _Period, ref.barTime);
   if(refShift < 1) return;

   // leg extreme between the broken swing and the BOS bar
   int extShift = isShort ? iHighest(_Symbol, _Period, MODE_HIGH, refShift, 1)
                          : iLowest (_Symbol, _Period, MODE_LOW,  refShift, 1);
   if(extShift < 1) { st_noOB++; return; }
   double legExt = isShort ? H(extShift) : L(extShift);

   // POI = last opposing candle at/before the leg extreme
   int obShift = -1;
   for(int i = extShift; i <= extShift + MaxOBSearchBars && i < Bars(_Symbol, _Period) - 1; i++)
     {
      bool opposing = isShort ? (C(i) > O(i)) : (C(i) < O(i));
      if(opposing) { obShift = i; break; }
     }
   if(obShift < 0) { st_noOB++; Dbg("BOS but no POI candle found"); return; }

   double top, bottom;
   if(isShort) { bottom = O(obShift); top = MathMax(H(obShift), legExt); }
   else        { top = O(obShift);    bottom = MathMin(L(obShift), legExt); }
   if(top <= bottom) { st_noOB++; return; }

   ZeroMemory(S);
   S.state   = ST_WAIT_SWEEP;
   S.isShort = isShort;
   S.bosTime = T(1);
   S.obTop = top; S.obBottom = bottom;
   S.target  = isShort ? L(iLowest(_Symbol, _Period, MODE_LOW, extShift, 1))
                       : H(iHighest(_Symbol, _Period, MODE_HIGH, extShift, 1));
   g_postHigh.price = 0; g_postLow.price = 0;
   st_armed++;
   Dbg(StringFormat("%s BOS @ %s (broke swing %s from %s). POI %s-%s (candle %s). Target starts %s",
                    isShort ? "BEAR" : "BULL", TimeToString(T(1)), P(ref.price), TimeToString(ref.barTime),
                    P(bottom), P(top), TimeToString(T(obShift)), P(S.target)));
  }

// Waiting for the pullback to sweep post-BOS liquidity above/below the POI
void StepWaitSweep()
  {
   // target extends with the leg until the sweep freezes it
   if(S.isShort) S.target = MathMin(S.target, L(1)); else S.target = MathMax(S.target, H(1));

   if(S.isShort ? C(1) > S.obTop : C(1) < S.obBottom) { st_invalidated++; Reset("closed through the POI before the sweep"); return; }

   double ind = S.isShort ? g_postHigh.price : g_postLow.price;
   bool indValid = ind > 0 && (S.isShort ? ind < S.obBottom : ind > S.obTop);
   bool swept = indValid && (S.isShort ? H(1) > ind : L(1) < ind);
   bool touched = S.isShort ? H(1) >= S.obBottom : L(1) <= S.obTop;

   if(!swept)
     {
      if(touched) { st_touchBeforeSweep++; Reset("POI touched before any liquidity sweep"); }
      return;
     }

   st_swept++;
   S.inducement = ind;
   Dbg(StringFormat("SWEEP of post-BOS %s %s @ %s. Target frozen at %s",
                    S.isShort ? "high" : "low", P(ind), TimeToString(T(1)), P(S.target)));
   PlaceEntry();
  }

void PlaceEntry()
  {
   bool sh = S.isShort;
   double entry = sh ? S.obBottom : S.obTop;
   double sl    = sh ? S.obTop + Pts(SLBufferPoints) : S.obBottom - Pts(SLBufferPoints);
   double tp    = sh ? S.target + Pts(TPBufferPoints) : S.target - Pts(TPBufferPoints);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // price already inside the zone (sweep bar tapped it and closed inside) -> market
   bool market = sh ? (bid >= entry) : (ask <= entry);
   if(market) entry = sh ? bid : ask;

   entry = NormPrice(entry); sl = NormPrice(sl); tp = NormPrice(tp);
   if(sh ? entry >= sl : entry <= sl) { st_invalidated++; Reset("price already beyond the stop"); return; }
   double risk = MathAbs(entry - sl), reward = sh ? entry - tp : tp - entry;
   if(risk <= 0 || reward <= 0 || reward / risk < MinRR)
     { st_lowRR++; Reset(StringFormat("RR %.2f below MinRR %.2f", risk > 0 ? reward / risk : 0, MinRR)); return; }

   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) { st_spread++; Reset(StringFormat("spread %d > %d", spread, MaxSpreadPoints)); return; }

   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double refPx = sh ? bid : ask;
   if(minDist > 0 && (risk <= minDist || reward <= minDist || (!market && MathAbs(refPx - entry) <= minDist)))
     { st_stopsLevel++; Reset("inside broker stops level - skipped, never widened"); return; }

   double lots, plannedRisk; string why;
   if(!ComputeLots(sh, entry, sl, lots, plannedRisk, why)) { st_riskReject++; Reset("risk sizing rejected: " + why); return; }

   bool ok;
   if(market) ok = sh ? trade.Sell(lots, _Symbol, 0, sl, tp, TradeComment) : trade.Buy(lots, _Symbol, 0, sl, tp, TradeComment);
   else       ok = sh ? trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment)
                      : trade.BuyLimit (lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, TradeComment);
   if(!ok) { st_orderFail++; Reset(StringFormat("order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription())); return; }

   st_placed++;
   S.orderTicket = market ? 0 : trade.ResultOrder();
   S.slPrice = sl; S.tpPrice = tp; S.entryPrice = entry;
   S.plannedRiskMoney = plannedRisk;
   S.state = ST_PENDING;
   Dbg(StringFormat("%s %s %.2f lots @ %s  SL %s  TP %s  RR %.2f",
                    sh ? "SELL" : "BUY", market ? "MARKET" : "LIMIT", lots, P(entry), P(sl), P(tp), reward / risk));
   CheckFill();   // market orders fill immediately
  }

// Pending order: cancel on invalidation / target taken / timeout (closed-bar checks)
void StepPending()
  {
   string reason = "";
   if(S.isShort ? C(1) > S.obTop : C(1) < S.obBottom)      { st_invalidated++; reason = "closed through the POI"; }
   else if(S.isShort ? L(1) < S.target : H(1) > S.target)  { st_targetTaken++; reason = "target liquidity taken before fill"; }
   if(reason == "") return;
   if(S.orderTicket != 0 && OrderSelect(S.orderTicket)) trade.OrderDelete(S.orderTicket);
   Reset(reason);
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
   ulong pos = OurPosition();
   if(pos == 0) return;
   S.posTicket = pos;
   S.state = ST_ACTIVE;
   st_filled++;
   if(S.isShort) st_sell++; else st_buy++;

   // freeze the R denominator at the ACTUAL fill price, original SL, actual lots.
   // Exception: a fill AT/BEYOND the SL (gap through both levels) has no
   // meaningful fill-to-SL distance, so R falls back to the planned risk.
   double fill = PositionGetDouble(POSITION_PRICE_OPEN);
   double lots = PositionGetDouble(POSITION_VOLUME);
   S.entryPrice = fill;
   S.filledBeyondSL = S.isShort ? (fill >= S.slPrice) : (fill <= S.slPrice);
   if(S.filledBeyondSL)
     {
      st_filledBeyondSL++;
      S.initialRiskMoney = S.plannedRiskMoney;
      S.riskValid = S.plannedRiskMoney > 0;
     }
   else
     {
      double pl = 0;
      ResetLastError();
      S.riskValid = OrderCalcProfit(S.isShort ? ORDER_TYPE_SELL : ORDER_TYPE_BUY, _Symbol, lots, fill, S.slPrice, pl) && MathAbs(pl) > 0;
      S.initialRiskMoney = S.riskValid ? MathAbs(pl) : 0;
     }

   Print("R BASE:");
   PrintFormat("  PositionID=%I64u  Direction=%s", pos, S.isShort ? "SELL" : "BUY");
   PrintFormat("  Fill=%s  OriginalSL=%s  TP=%s  Lots=%.2f", P(fill), P(S.slPrice), P(S.tpPrice), lots);
   PrintFormat("  InitialRiskMoney=$%.2f  (riskValid=%s)%s", S.initialRiskMoney, S.riskValid ? "true" : "false",
               S.filledBeyondSL ? "  FILLED BEYOND SL - R base = planned risk" : "");
  }

// Friday close: no limit or waiting setup is carried over the weekend gap
bool FridayCutoff()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week == 5 && dt.hour >= FridayCutoffHour;
  }

void RecordClosedTrade()
  {
   double gross = 0, comm = 0, swp = 0, fee = 0;
   bool closed = false;
   if(HistorySelectByPosition(S.posTicket))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         gross += HistoryDealGetDouble(d, DEAL_PROFIT);
         comm  += HistoryDealGetDouble(d, DEAL_COMMISSION);
         swp   += HistoryDealGetDouble(d, DEAL_SWAP);
         fee   += HistoryDealGetDouble(d, DEAL_FEE);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT) closed = true;
        }
   double net = gross + comm + swp + fee;
   st_commission += comm; st_swap += swp; st_fee += fee;

   bool rInvalid = !closed || !S.riskValid || S.initialRiskMoney <= 0;
   double r = rInvalid ? 0 : net / S.initialRiskMoney;

   if(net > 0)      { st_wins++; st_consec = 0; st_grossProfit += net; if(S.isShort) st_sellWins++; else st_buyWins++; }
   else if(net < 0) { st_losses++; st_consec++; st_grossLoss += -net; if(st_consec > st_maxConsec) st_maxConsec = st_consec; }
   else               st_be++;

   if(rInvalid) st_rInvalid++;
   else { st_sumR += r; if(S.isShort) st_sellR += r; else st_buyR += r; }

   Print("R RESULT:");
   PrintFormat("  PositionID=%I64u  InitialRiskMoney=$%.2f", S.posTicket, S.initialRiskMoney);
   PrintFormat("  Gross=$%.2f  Commission=$%.2f  Swap=$%.2f  Fee=$%.2f  NetPnL=$%.2f", gross, comm, swp, fee, net);
   if(rInvalid) Print("  FinalR=R_INVALID (excluded from R aggregates)");
   else         PrintFormat("  FinalR=%.2f", r);
  }

//====================================================================
// MAIN
//====================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   trade.SetExpertMagicNumber(MagicNumber);
   ZeroMemory(g_lastHigh); ZeroMemory(g_lastLow);
   Reset("");
   PrintFormat("TWI SMC POI v1.01 on %s %s | Swing %d | Risk %.2f%% | MinRR %.2f | MaxSpread %d",
               _Symbol, EnumToString(_Period), SwingBars, RiskPercent, MinRR, MaxSpreadPoints);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   // tick-level: detect fills and closes
   if(S.state == ST_PENDING) CheckFill();
   if(S.state == ST_ACTIVE && OurPosition() == 0) { RecordClosedTrade(); Reset(""); }

   datetime bar = T(0);
   if(bar == g_lastBar) return;
   g_lastBar = bar;

   ScanSwings();

   if(FridayCutoff())
     {
      // keep swing BOS flags current, but hold no setup or order into the weekend
      CheckBOS();
      if(S.state == ST_WAIT_SWEEP || S.state == ST_PENDING)
        {
         st_fridayCancel++;
         if(S.state == ST_PENDING && S.orderTicket != 0 && OrderSelect(S.orderTicket)) trade.OrderDelete(S.orderTicket);
         Reset("Friday cutoff - nothing rests over the weekend");
        }
      return;
     }

   CheckBOS();

   // the BOS bar itself is the impulse - setup logic starts on the next closed bar
   if((S.state == ST_WAIT_SWEEP || S.state == ST_PENDING) && T(1) > S.bosTime)
     {
      if(++S.barsAlive > MaxSetupBars)
        {
         st_timeout++;
         if(S.state == ST_PENDING && S.orderTicket != 0 && OrderSelect(S.orderTicket)) trade.OrderDelete(S.orderTicket);
         Reset("timed out");
         return;
        }
      if(S.state == ST_WAIT_SWEEP) StepWaitSweep();
      else                         StepPending();
     }
  }

void OnDeinit(const int reason)
  {
   if(S.state == ST_PENDING && S.orderTicket != 0 && OrderSelect(S.orderTicket)) trade.OrderDelete(S.orderTicket);

   int trades = st_wins + st_losses + st_be;
   int validR = trades - st_rInvalid;
   Print("==================== TWI SMC POI SUMMARY ====================");
   PrintFormat("Funnel: BOS %d -> no POI %d -> armed %d -> POI touched before sweep %d -> closed through POI %d -> swept %d",
               st_bos, st_noOB, st_armed, st_touchBeforeSweep, st_invalidated, st_swept);
   PrintFormat("        swept -> RR too low %d | spread %d | stops level %d | risk reject %d | order fail %d -> placed %d",
               st_lowRR, st_spread, st_stopsLevel, st_riskReject, st_orderFail, st_placed);
   PrintFormat("        placed -> target taken first %d | timed out %d -> FILLED %d  (filled beyond SL %d)", st_targetTaken, st_timeout, st_filled, st_filledBeyondSL);
   PrintFormat("        Friday-cutoff cancellations (setup or pending) %d", st_fridayCancel);
   PrintFormat("Trades %d  W %d  L %d  BE %d  WinRate %.1f%%", trades, st_wins, st_losses, st_be,
               trades > 0 ? 100.0 * st_wins / trades : 0);
   PrintFormat("Net $%.2f  PF %.2f  Max consecutive losses %d", st_grossProfit - st_grossLoss,
               st_grossLoss > 0 ? st_grossProfit / st_grossLoss : 0, st_maxConsec);
   PrintFormat("Total R %.2f  Avg R %.3f  (R_INVALID %d)", st_sumR, validR > 0 ? st_sumR / validR : 0, st_rInvalid);
   PrintFormat("BUY %d (W %d, R %.2f)  SELL %d (W %d, R %.2f)", st_buy, st_buyWins, st_buyR, st_sell, st_sellWins, st_sellR);
   PrintFormat("Costs: commission $%.2f  swap $%.2f  fee $%.2f (all deals, entry + exit)", st_commission, st_swap, st_fee);
   Print("==============================================================");
  }
//+------------------------------------------------------------------+
