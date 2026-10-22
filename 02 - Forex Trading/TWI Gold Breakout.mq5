//+------------------------------------------------------------------+
//|                                            TWI Gold Breakout.mq5 |
//|  2026-10-12. Adam: "look at gold EA's all over the Internet see   |
//|  which ones are successful and start work from there. Build me a  |
//|  EA" -> "Gold".                                                   |
//|                                                                  |
//|  The successful public gold EAs are H1/H4 breakouts with a hard   |
//|  stop (Gold Reaper, Gold Trade Pro, MQL5 code base 77691). These  |
//|  rules passed gold_breakout_research.py (2020-26, AAAFx data):     |
//|  195 trades, +74.7R, PF 1.71, 5/7 years, beat coin 98% and random |
//|  longs 96%.                                                       |
//|                                                                  |
//|  Rules (closed SignalTF bars, default H4):                        |
//|   BUY  : bar 1 closes above the highest high of the EntryBars     |
//|          bars before it, bar 2 did not, and bar 1 closed above    |
//|          the EMA(TrendEMA). Market buy.                           |
//|   SELL : mirror (off by default; it weakened the test).           |
//|   SL   : StopATR x ATR(ATRPeriod) from the fill.                  |
//|   TP   : TargetR x the stop (EXIT_TARGET), or a chandelier trail  |
//|          (EXIT_TRAIL: extreme since entry - TrailATR x ATR).      |
//|  One position per magic, a hard SL on every order, no grid.      |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE  { LOTS_FIXED = 0, LOTS_RISK_PERCENT = 1 };
enum ENUM_EXIT_MODE { EXIT_TARGET = 0, EXIT_TRAIL = 1 };

input group "=== General ==="
input long            Magic                         = 20261013;
input string          TradeComment                  = "TWI Gold Breakout";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED;
input double          FixedLots                     = 0.01;
input double          RiskPercent                   = 1.0;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;      // allow the min lot if it overshoots risk by at most this %
input double          MaxRiskPerTradePct            = 0.0;       // fixed lots: skip a trade whose SL risk exceeds this % of equity (0 = off)
input double          MaxSpreadToRisk               = 0.10;      // skip if the spread is more than this fraction of the stop
input int             MaxDeviationPoints            = 50;
input bool            DebugMode                     = true;

input group "=== Signal (closed bars on SignalTF) ==="
input ENUM_TIMEFRAMES SignalTF                      = PERIOD_H4;
input int             EntryBars                     = 20;        // breakout of the highest high / lowest low of this many bars
input int             TrendEMA                      = 200;       // 0 = no trend filter
input bool            AllowLong                     = true;
input bool            AllowShort                    = false;

input group "=== Exits ==="
input int             ATRPeriod                     = 20;
input double          StopATR                       = 2.0;
input ENUM_EXIT_MODE  ExitMode                      = EXIT_TARGET;
input double          TargetR                       = 2.0;       // EXIT_TARGET
input double          TrailATR                      = 3.0;       // EXIT_TRAIL

CTrade   trade;
int      hEMA = INVALID_HANDLE, hATR = INVALID_HANDLE;
datetime g_lastBar = 0;
int      g_signals = 0, g_entries = 0, g_skipSpread = 0, g_skipBusy = 0;

void   Dbg(string s) { if(DebugMode) Print("[TWI GB] ", s); }
string P(double v)   { return DoubleToString(v, _Digits); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }

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
ulong MyPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) return t;
     }
   return 0;
  }

// +1 buy breakout, -1 sell breakout, 0 none (bars 1 and 2 are closed)
int Signal(double &atr)
  {
   int need = EntryBars + 3;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, SignalTF, 0, need, r) < need) return 0;
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(hATR, 0, 1, 1, a) < 1 || a[0] <= 0) return 0;
   atr = a[0];
   double hh1 = r[2].high, ll1 = r[2].low, hh2 = r[3].high, ll2 = r[3].low;
   for(int i = 2; i <= EntryBars + 1; i++) { hh1 = MathMax(hh1, r[i].high);     ll1 = MathMin(ll1, r[i].low); }
   for(int i = 3; i <= EntryBars + 2; i++) { hh2 = MathMax(hh2, r[i].high);     ll2 = MathMin(ll2, r[i].low); }
   double e = 0;
   if(TrendEMA > 0)
     {
      double eb[];
      ArraySetAsSeries(eb, true);
      if(CopyBuffer(hEMA, 0, 1, 1, eb) < 1) return 0;
      e = eb[0];
     }
   if(AllowLong  && r[1].close > hh1 && !(r[2].close > hh2) && (TrendEMA <= 0 || r[1].close > e)) return 1;
   if(AllowShort && r[1].close < ll1 && !(r[2].close < ll2) && (TrendEMA <= 0 || r[1].close < e)) return -1;
   return 0;
  }

void TryEnter(int dir, double atr)
  {
   bool buy = dir > 0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = buy ? ask : bid;
   double risk = StopATR * atr;
   if(MaxSpreadToRisk > 0 && (ask - bid) > MaxSpreadToRisk * risk)
     { g_skipSpread++; Dbg(StringFormat("skip: spread %s > %.0f%% of stop %s", P(ask - bid), MaxSpreadToRisk * 100, P(risk))); return; }
   double sl = buy ? entry - risk : entry + risk;
   double tp = 0;
   if(ExitMode == EXIT_TARGET) tp = buy ? entry + TargetR * risk : entry - TargetR * risk;
   double lots; string why;
   if(!CalcLots(buy, entry, sl, lots, why)) { Dbg("skip: " + why); return; }
   bool ok = buy ? trade.Buy(lots, _Symbol, 0, NormPrice(sl), NormPrice(tp), TradeComment)
                 : trade.Sell(lots, _Symbol, 0, NormPrice(sl), NormPrice(tp), TradeComment);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     { Dbg(StringFormat("order failed (%u %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription())); return; }
   g_entries++;
   Dbg(StringFormat("%s %.2f @ %s  SL %s  TP %s  ATR %s", buy ? "BUY" : "SELL", lots, P(entry), P(sl), tp > 0 ? P(tp) : "trail", P(atr)));
   // a hard stop is mandatory: if the broker dropped it, get out
   ulong t = MyPosition();
   if(t > 0 && PositionSelectByTicket(t) && PositionGetDouble(POSITION_SL) <= 0)
     {
      Dbg("no SL attached -> closing");
      trade.PositionClose(t);
     }
  }

// chandelier trail on each new SignalTF bar: extreme since entry -/+ TrailATR x ATR
void Trail(ulong t, double atr)
  {
   if(!PositionSelectByTicket(t)) return;
   bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   int n = Bars(_Symbol, SignalTF, opened, TimeCurrent());
   if(n < 2) return;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, SignalTF, 1, n - 1, r) < 1) return;
   double ext = isBuy ? r[0].high : r[0].low;
   for(int i = 0; i < ArraySize(r); i++) ext = isBuy ? MathMax(ext, r[i].high) : MathMin(ext, r[i].low);
   double nsl = NormPrice(isBuy ? ext - TrailATR * atr : ext + TrailATR * atr);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   if(isBuy  && nsl > sl && nsl < bid - gap && trade.PositionModify(t, nsl, tp)) Dbg("trail -> " + P(nsl));
   if(!isBuy && (sl == 0 || nsl < sl) && nsl > ask + gap && trade.PositionModify(t, nsl, tp)) Dbg("trail -> " + P(nsl));
  }

//====================================================================
int OnInit()
  {
   if(EntryBars < 2 || ATRPeriod < 1 || StopATR <= 0 || (ExitMode == EXIT_TARGET && TargetR <= 0) || (ExitMode == EXIT_TRAIL && TrailATR <= 0))
     { Print("[TWI GB] bad inputs"); return INIT_PARAMETERS_INCORRECT; }
   hATR = iATR(_Symbol, SignalTF, ATRPeriod);
   if(TrendEMA > 0) hEMA = iMA(_Symbol, SignalTF, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hATR == INVALID_HANDLE || (TrendEMA > 0 && hEMA == INVALID_HANDLE)) { Print("[TWI GB] indicator handle failed"); return INIT_FAILED; }
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(MaxDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   Dbg(StringFormat("init %s %s, %d-bar breakout, EMA %d, SL %.1f ATR, %s", _Symbol, EnumToString(SignalTF), EntryBars, TrendEMA, StopATR,
                    ExitMode == EXIT_TARGET ? StringFormat("TP %.1fR", TargetR) : StringFormat("trail %.1f ATR", TrailATR)));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Print(StringFormat("[TWI GB] signals %d | entries %d | skipped: busy %d, spread %d", g_signals, g_entries, g_skipBusy, g_skipSpread));
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
  }

void OnTick()
  {
   datetime bt = iTime(_Symbol, SignalTF, 0);
   if(bt == 0 || bt == g_lastBar) return;
   g_lastBar = bt;
   double atr = 0;
   int dir = Signal(atr);
   ulong t = MyPosition();
   if(t > 0 && ExitMode == EXIT_TRAIL && atr > 0) Trail(t, atr);
   if(dir == 0) return;
   g_signals++;
   if(t > 0) { g_skipBusy++; Dbg("skip: position open"); return; }
   TryEnter(dir, atr);
  }
//+------------------------------------------------------------------+
