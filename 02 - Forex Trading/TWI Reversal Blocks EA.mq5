//+------------------------------------------------------------------+
//| TWI Reversal Blocks EA - TESTER ONLY                             |
//| Trades the blocks of TWI Reversal Blocks.pine to confirm the     |
//| replay (reversal_blocks_research.py) in the MT5 tester.          |
//| Block rules (sell side; buys mirror on swept lows):              |
//|  - liquidity = confirmed swing highs (SwingLen each side) not    |
//|    yet traded through                                            |
//|  - sweep pivot = a new swing high whose up-leg (from the last    |
//|    swing low) traded through an old high formed before the leg   |
//|  - rejection = close below the leg-start low, no high above the  |
//|    sweep high first, within MaxWait bars                         |
//|  - block = sweep high down to min(old high, sweep body top);     |
//|    newest KeepPerSide per side stay live; a close through the    |
//|    far side ends it                                              |
//| Trade: limit at the near edge on the first touch (while flat),   |
//| SL at the far edge, TP 1R / 2R / leg-start level, max hold.      |
//| A touch while a position is open uses the block up (as replay).  |
//| Refuses to run outside the strategy tester: the replay failed.   |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property description "TWI Reversal Blocks EA - tester only. Limit on the first tap of a swept-and-rejected block."

#include <Trade/Trade.mqh>

enum ENUM_RB_EXIT { EXIT_1R = 0, EXIT_2R = 1, EXIT_LEG = 2 };

input ENUM_TIMEFRAMES SignalTF     = PERIOD_M5;  // Block timeframe
input int             SwingLen     = 5;          // Swing length (candles each side)
input int             MaxWait      = 100;        // Bars allowed for the rejection
input int             KeepPerSide  = 3;          // Live blocks per side
input ENUM_RB_EXIT    ExitMode     = EXIT_2R;    // Exit: 1R, 2R or leg-start level
input double          MinHeight    = 0.0;        // Min block height to trade (price units, 0 = all)
input double          FixedLots    = 0.1;        // Lots
input int             MaxHoldHours = 48;         // Max hold (hours)
input long            MagicNumber  = 20261023;   // Magic number

struct Liq  { double price; int bar; int swept; };
struct Piv  { double price; int bar; };
struct Pend { double farP; double nearP; double trig; int piv; int born; };
struct Blk  { int d; double top; double bot; double trig; int conf; bool used; ulong order; };

CTrade   trade;
double   O[], H[], L[], C[];
int      nb = 0;
datetime lastBar = 0;
Liq      liqH[], liqL[];
Piv      pivH[], pivL[];
Pend     pendS[], pendB[];
Blk      liveS[], liveB[];
int      blocksMade = 0, ordersPlaced = 0;

// R bookkeeping
long     posIds[];
double   posRisk[];
int      nTr = 0, nWin = 0;
double   sumR = 0, grossW = 0, grossL = 0;
int      yrs[];
double   yrR[];

//+------------------------------------------------------------------+
int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      Print("TWI Reversal Blocks EA is tester-only (the gold replay failed). Not running.");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void PushBar(const MqlRates &r)
{
   if(nb >= ArraySize(O))
   {
      int sz = nb + 50000;
      ArrayResize(O, sz); ArrayResize(H, sz); ArrayResize(L, sz); ArrayResize(C, sz);
   }
   O[nb] = r.open; H[nb] = r.high; L[nb] = r.low; C[nb] = r.close;
   nb++;
}

void TrimLiq(Liq &a[])  { int n = ArraySize(a); if(n > 40) ArrayRemove(a, 0, n - 40); }
void TrimPiv(Piv &a[])  { int n = ArraySize(a); if(n > 20) ArrayRemove(a, 0, n - 20); }

void DropOrder(Blk &b)
{
   if(b.order != 0 && OrderSelect(b.order)) trade.OrderDelete(b.order);
   b.order = 0;
}

// Pivot at c (confirmed at i) on side s: +1 = high, -1 = low.
void PivotSide(int s, int c, int i)
{
   double p = (s > 0) ? H[c] : L[c];
   double mx = -DBL_MAX, mxLeft = -DBL_MAX;
   for(int k = c - SwingLen; k <= c + SwingLen; k++)
   {
      double v = s * ((s > 0) ? H[k] : L[k]);
      if(v > mx) mx = v;
      if(k < c && v > mxLeft) mxLeft = v;
   }
   if(s * p != mx || !(s * p > mxLeft)) return;

   // leg start = latest opposite pivot before c
   int legBar = -1; double legPrice = 0;
   int no = (s > 0) ? ArraySize(pivL) : ArraySize(pivH);
   for(int k = no - 1; k >= 0; k--)
   {
      Piv q; if(s > 0) q = pivL[k]; else q = pivH[k];
      if(q.bar < c) { legBar = q.bar; legPrice = q.price; break; }
   }
   if(legBar >= 0)
   {
      bool found = false; double old = 0;
      int nl = (s > 0) ? ArraySize(liqH) : ArraySize(liqL);
      for(int k = 0; k < nl; k++)
      {
         Liq l; if(s > 0) l = liqH[k]; else l = liqL[k];
         if(l.swept < 0 || !(l.bar < legBar && legBar < l.swept && l.swept <= c)) continue;
         if(!(s * l.price < s * p)) continue;
         if(!found || s * l.price > s * old) { old = l.price; found = true; }
      }
      if(found)
      {
         double body  = (s > 0) ? MathMax(O[c], C[c]) : MathMin(O[c], C[c]);
         Pend q;
         q.farP = p; q.nearP = (s > 0) ? MathMin(old, body) : MathMax(old, body);
         q.trig = legPrice; q.piv = c; q.born = i;
         if(s > 0) { int n = ArraySize(pendS); ArrayResize(pendS, n + 1); pendS[n] = q; }
         else      { int n = ArraySize(pendB); ArrayResize(pendB, n + 1); pendB[n] = q; }
      }
   }
   Liq nl2; nl2.price = p; nl2.bar = c; nl2.swept = -1;
   Piv np;  np.price = p;  np.bar = c;
   if(s > 0) { int n = ArraySize(liqH); ArrayResize(liqH, n + 1); liqH[n] = nl2;
               n = ArraySize(pivH); ArrayResize(pivH, n + 1); pivH[n] = np; TrimPiv(pivH); }
   else      { int n = ArraySize(liqL); ArrayResize(liqL, n + 1); liqL[n] = nl2;
               n = ArraySize(pivL); ArrayResize(pivL, n + 1); pivL[n] = np; TrimPiv(pivL); }
}

void AddBlock(int s, const Pend &q, int i)
{
   Blk b;
   b.d = -s; b.top = MathMax(q.farP, q.nearP); b.bot = MathMin(q.farP, q.nearP);
   b.trig = q.trig; b.conf = i; b.used = false; b.order = 0;
   blocksMade++;
   if(s > 0)
   {
      int n = ArraySize(liveS); ArrayResize(liveS, n + 1); liveS[n] = b;
      while(ArraySize(liveS) > KeepPerSide) { DropOrder(liveS[0]); ArrayRemove(liveS, 0, 1); }
   }
   else
   {
      int n = ArraySize(liveB); ArrayResize(liveB, n + 1); liveB[n] = b;
      while(ArraySize(liveB) > KeepPerSide) { DropOrder(liveB[0]); ArrayRemove(liveB, 0, 1); }
   }
}

void PendSide(int s, int i)
{
   int n = (s > 0) ? ArraySize(pendS) : ArraySize(pendB);
   for(int k = n - 1; k >= 0; k--)
   {
      Pend q; if(s > 0) q = pendS[k]; else q = pendB[k];
      bool rej, beyond = false;
      if(i == q.born)
      {
         double ext = C[i];
         for(int j = i - SwingLen + 1; j <= i; j++) ext = (s > 0) ? MathMin(ext, C[j]) : MathMax(ext, C[j]);
         rej = (s > 0) ? ext < q.trig : ext > q.trig;
      }
      else
      {
         rej    = (s > 0) ? C[i] < q.trig : C[i] > q.trig;
         beyond = (s > 0) ? H[i] > q.farP : L[i] < q.farP;
      }
      if(beyond || i - q.born > MaxWait || rej)
      {
         if(!beyond && i - q.born <= MaxWait && rej) AddBlock(s, q, i);
         if(s > 0) ArrayRemove(pendS, k, 1); else ArrayRemove(pendB, k, 1);
      }
   }
}

// Close-through ends a block; any touch of the near edge uses it up.
void BlocksSide(Blk &a[], int i)
{
   for(int k = ArraySize(a) - 1; k >= 0; k--)
   {
      if(i <= a[k].conf) continue;
      bool broken = (a[k].d < 0) ? C[i] > a[k].top : C[i] < a[k].bot;
      if(broken) { DropOrder(a[k]); ArrayRemove(a, k, 1); continue; }
      bool touched = (a[k].d < 0) ? H[i] >= a[k].bot : L[i] <= a[k].top;
      if(touched) { a[k].used = true; DropOrder(a[k]); }
   }
}

void Engine()
{
   int i = nb - 1;
   for(int k = 0; k < ArraySize(liqH); k++) if(liqH[k].swept < 0 && H[i] > liqH[k].price) liqH[k].swept = i;
   for(int k = 0; k < ArraySize(liqL); k++) if(liqL[k].swept < 0 && L[i] < liqL[k].price) liqL[k].swept = i;
   TrimLiq(liqH); TrimLiq(liqL);
   int c = i - SwingLen;
   if(c >= SwingLen) { PivotSide(1, c, i); PivotSide(-1, c, i); }
   PendSide(1, i);  BlocksSide(liveS, i);
   PendSide(-1, i); BlocksSide(liveB, i);
}

//+------------------------------------------------------------------+
bool OurPosition(ulong &ticket, datetime &opened)
{
   for(int k = PositionsTotal() - 1; k >= 0; k--)
   {
      ulong t = PositionGetTicket(k);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
      { ticket = t; opened = (datetime)PositionGetInteger(POSITION_TIME); return true; }
   }
   return false;
}

// An order that is no longer pending has filled (or was cancelled by us, which resets order to 0 first).
void SyncFills(Blk &a[])
{
   for(int k = 0; k < ArraySize(a); k++)
      if(a[k].order != 0 && !OrderSelect(a[k].order)) { a[k].used = true; a[k].order = 0; }
}

void PlaceOrders(Blk &a[])
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   for(int k = 0; k < ArraySize(a); k++)
   {
      if(a[k].used || a[k].order != 0) continue;
      double h = a[k].top - a[k].bot;
      if(h <= 0 || h < MinHeight) continue;
      double tp;
      if(a[k].d < 0)
      {
         if(bid >= a[k].bot - stopsLvl) { a[k].used = true; continue; }   // already at/through the edge
         tp = (ExitMode == EXIT_1R) ? a[k].bot - h : (ExitMode == EXIT_2R) ? a[k].bot - 2 * h : a[k].trig;
         if(tp >= a[k].bot) continue;
         if(trade.SellLimit(FixedLots, NormalizeDouble(a[k].bot, _Digits), _Symbol, NormalizeDouble(a[k].top, _Digits),
                            NormalizeDouble(tp, _Digits), ORDER_TIME_GTC, 0, "TWI RB"))
         { a[k].order = trade.ResultOrder(); ordersPlaced++; }
      }
      else
      {
         if(ask <= a[k].top + stopsLvl) { a[k].used = true; continue; }
         tp = (ExitMode == EXIT_1R) ? a[k].top + h : (ExitMode == EXIT_2R) ? a[k].top + 2 * h : a[k].trig;
         if(tp <= a[k].top) continue;
         if(trade.BuyLimit(FixedLots, NormalizeDouble(a[k].top, _Digits), _Symbol, NormalizeDouble(a[k].bot, _Digits),
                           NormalizeDouble(tp, _Digits), ORDER_TIME_GTC, 0, "TWI RB"))
         { a[k].order = trade.ResultOrder(); ordersPlaced++; }
      }
   }
}

void DropAll(Blk &a[]) { for(int k = 0; k < ArraySize(a); k++) DropOrder(a[k]); }

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bt = iTime(_Symbol, SignalTF, 0);
   if(bt != lastBar && bt != 0)
   {
      MqlRates r[];
      if(lastBar == 0)
      {
         int got = CopyRates(_Symbol, SignalTF, 1, 300, r);        // warm-up, oldest first
         for(int k = 0; k < got; k++) { PushBar(r[k]); Engine(); }
      }
      else if(CopyRates(_Symbol, SignalTF, 1, 1, r) == 1) { PushBar(r[0]); Engine(); }
      lastBar = bt;
   }

   SyncFills(liveS); SyncFills(liveB);
   ulong tk; datetime opened;
   // keep only the first position if two limits filled on the same tick
   int ours = 0;
   for(int k = PositionsTotal() - 1; k >= 0; k--)
   {
      ulong t = PositionGetTicket(k);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
      { ours++; if(ours > 1) trade.PositionClose(t); }
   }
   if(OurPosition(tk, opened))
   {
      DropAll(liveS); DropAll(liveB);
      if(TimeCurrent() - opened >= MaxHoldHours * 3600) trade.PositionClose(tk);
      return;
   }
   PlaceOrders(liveS); PlaceOrders(liveB);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &tr, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(tr.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetInteger(tr.deal, DEAL_MAGIC) != MagicNumber) return;
   long pid = HistoryDealGetInteger(tr.deal, DEAL_POSITION_ID);
   long entry = HistoryDealGetInteger(tr.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      double price = HistoryDealGetDouble(tr.deal, DEAL_PRICE), vol = HistoryDealGetDouble(tr.deal, DEAL_VOLUME);
      bool isBuy = HistoryDealGetInteger(tr.deal, DEAL_TYPE) == DEAL_TYPE_BUY;
      double sl = 0;
      if(PositionSelectByTicket(pid)) sl = PositionGetDouble(POSITION_SL);
      double loss = 0;
      if(sl > 0 && OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol, price, sl, loss))
      {
         int n = ArraySize(posIds); ArrayResize(posIds, n + 1); ArrayResize(posRisk, n + 1);
         posIds[n] = pid; posRisk[n] = MathAbs(loss);
      }
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      double pnl = HistoryDealGetDouble(tr.deal, DEAL_PROFIT) + HistoryDealGetDouble(tr.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(tr.deal, DEAL_COMMISSION);
      for(int k = 0; k < ArraySize(posIds); k++)
      {
         if(posIds[k] != pid || posRisk[k] <= 0) continue;
         double R = pnl / posRisk[k];
         nTr++; sumR += R;
         if(R > 0) { nWin++; grossW += R; } else grossL -= R;
         MqlDateTime t; TimeToStruct((datetime)HistoryDealGetInteger(tr.deal, DEAL_TIME), t);
         int y = -1;
         for(int j = 0; j < ArraySize(yrs); j++) if(yrs[j] == t.year) y = j;
         if(y < 0) { y = ArraySize(yrs); ArrayResize(yrs, y + 1); ArrayResize(yrR, y + 1); yrs[y] = t.year; yrR[y] = 0; }
         yrR[y] += R;
         ArrayRemove(posIds, k, 1); ArrayRemove(posRisk, k, 1);
         break;
      }
   }
}

void OnDeinit(const int reason)
{
   string ys = "";
   for(int j = 0; j < ArraySize(yrs); j++) ys += StringFormat(" %d:%+.1f", yrs[j], yrR[j]);
   PrintFormat("LIVE/TEST: trades %d R %+.1f avg %+.3f PF %.2f win %.0f%% blocks %d orders %d |%s",
               nTr, sumR, nTr ? sumR / nTr : 0, grossL > 0 ? grossW / grossL : 0, nTr ? 100.0 * nWin / nTr : 0,
               blocksMade, ordersPlaced, ys);
}
