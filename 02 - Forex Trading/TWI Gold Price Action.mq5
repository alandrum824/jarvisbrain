//+------------------------------------------------------------------+
//|                                        TWI Gold Price Action.mq5 |
//|  2026-10-13. Adam: "With this information build a second ea with |
//|  these strategies incorporated" / "I want a brand new one".       |
//|                                                                  |
//|  Built from the chart lessons Adam sent (see Chart Lessons Study) |
//|  - only the setups that held up on gold 2020-26 replays (real     |
//|  spread +6 pt, coin-flip control):                                |
//|                                                                  |
//|  1. THREE SOLDIERS / THREE CROWS, H1 (UseSoldiers, default ON)    |
//|     3 bars in a row in one direction, each body >= 0.5 x ATR(14), |
//|     each closing beyond the previous close and in the top/bottom  |
//|     30% of its range. Market entry at the next bar open; SL       |
//|     beyond the first bar -/+ 0.1 ATR; TP 1R; time exit 48 bars.   |
//|     Replay (gold_soldiers_research.py): 194 tr, +17.4R, PF 1.23,  |
//|     5/7 years, coin 100% = PASS.                                  |
//|                                                                  |
//|  2. HEAD & SHOULDERS, M15 (UseHeadShoulders, default OFF - lead)  |
//|     Last 5 confirmed 3/3 swings = shoulder/trough/head/trough/    |
//|     shoulder; head beyond both shoulders by >= 0.5 ATR, shoulders |
//|     within 1 ATR. Entry at the next open after the first close    |
//|     through the neckline (within 20 bars); SL beyond the right    |
//|     shoulder + 0.1 ATR; TP measured move clipped to 1-4R; time    |
//|     exit 96 bars. Replay (gold_hs_double_research.py): 959 tr,    |
//|     +84.4R, PF 1.15, 4/7 years, coin 98% = near miss.             |
//|                                                                  |
//|  3. FVG GAP ENTRY, M15 (UseGapEntry, default OFF - lead)          |
//|     Impulse bar body >= 1.5 ATR that leaves a fair value gap.     |
//|     Limit at the near edge of the gap, valid 48 bars; SL beyond   |
//|     the impulse bar -/+ 0.1 ATR; TP 2R; time exit 48 bars.        |
//|     Replay (gold_three_areas_research.py GAP_DEEP): 2,794 tr,     |
//|     +123.7R, PF 1.07, 5/7 years, coin 100% = thin lead.           |
//|                                                                  |
//|  Each module: own magic (Magic + 0/1/2), one position at a time,  |
//|  hard SL on every order, no grid, no martingale.                 |
//|  RunMode = RUN_SHADOW (default) sends NO orders on a live chart;  |
//|  virtual trades from live bid/ask -> MQL5\Files\                  |
//|  TWIGoldPA_shadow.csv. The strategy tester always runs LIVE.     |
//|  Account Guard as in TWI Gold Asia Breakout v1.02 (LIVE/tester). |
//|  ATR = Wilder RMA(14), the same as the replays.                  |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE { LOTS_FIXED = 0, LOTS_RISK_PERCENT = 1 };
enum ENUM_RUN_MODE { RUN_SHADOW = 0, RUN_LIVE = 1 };

input group "=== General ==="
input ENUM_RUN_MODE   RunMode                       = RUN_SHADOW; // SHADOW: no orders ever sent; virtual trades logged to Files\TWIGoldPA_shadow.csv (the tester always runs LIVE)
input long            Magic                         = 20261020;  // Soldiers = Magic, H&S = Magic+1, Gap = Magic+2
input string          TradeComment                  = "TWI Gold PA";
input ENUM_LOT_MODE   LotMode                       = LOTS_FIXED;
input double          FixedLots                     = 0.01;
input double          RiskPercent                   = 0.5;       // LOTS_RISK_PERCENT only
input double          RiskOvershootTolerancePercent = 10.0;      // allow the min lot if it overshoots risk by at most this %
input double          MaxRiskPerTradePct            = 0.0;       // fixed lots: skip a trade whose SL risk exceeds this % of equity (0 = off)
input double          MaxSpreadToRisk               = 0.10;      // skip if the spread is more than this fraction of the stop
input int             ATRPeriod                     = 14;        // Wilder ATR, as in the replays
input bool            DebugMode                     = true;

input group "=== 1. Three Soldiers / Crows (PASS) ==="
input bool            UseSoldiers                   = true;
input ENUM_TIMEFRAMES SoldiersTF                    = PERIOD_H1;
input double          SoldiersBodyATR               = 0.5;       // each body >= this x ATR
input double          SoldiersCloseZone             = 0.30;      // each close within this fraction of its range from the extreme
input double          SoldiersStopATR               = 0.1;       // SL beyond the first bar by this x ATR
input double          SoldiersTargetR               = 1.0;
input int             SoldiersMaxHoldBars           = 48;

input group "=== 2. Head & Shoulders (lead, OFF) ==="
input bool            UseHeadShoulders              = false;
input ENUM_TIMEFRAMES HsTF                          = PERIOD_M15;
input int             HsSwingStrength               = 3;         // fractal bars each side
input double          HsShoulderTolATR              = 1.0;       // |left shoulder - right shoulder| <= this x ATR
input double          HsHeadMinATR                  = 0.5;       // head beyond the higher shoulder by >= this x ATR
input int             HsBreakWindowBars             = 20;        // neckline close must come within this many bars of the right shoulder's confirmation
input double          HsStopATR                     = 0.1;
input double          HsMinR                        = 1.0;       // measured-move target clipped to [MinR, MaxR]
input double          HsMaxR                        = 4.0;
input int             HsMaxHoldBars                 = 96;
input int             HsLookbackBars                = 800;

input group "=== 3. FVG Gap Entry (lead, OFF) ==="
input bool            UseGapEntry                   = false;
input ENUM_TIMEFRAMES GapTF                         = PERIOD_M15;
input double          GapImpulseATR                 = 1.5;       // impulse body >= this x ATR
input double          GapStopATR                    = 0.1;       // SL beyond the impulse bar by this x ATR
input double          GapTargetR                    = 2.0;
input int             GapValidBars                  = 48;        // limit order lifetime
input int             GapMaxHoldBars                = 48;

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

#define MOD_SOLDIERS 0
#define MOD_HS       1
#define MOD_GAP      2
#define NMOD         3
#define NVT          16

string   MODNAME[NMOD] = { "Soldiers", "H&S", "Gap" };
CTrade   g_tr[NMOD];
datetime g_lastBar[NMOD];
datetime g_lastSig[NMOD];
int      g_sig[NMOD], g_taken[NMOD], g_skip[NMOD];
bool     g_shadow = true;

// shadow (virtual) trades: state 1 = pending limit, 2 = open
struct VT
  {
   int      state, mod, dir;
   double   entry, sl, tp, lots;
   datetime expiry, deadline, fillTime;
  };
VT g_vt[NVT];

void   Dbg(string s) { if(DebugMode) Print("[TWI PA] ", s); }
string P(double v)   { return DoubleToString(v, _Digits); }
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }
long   MagicOf(int mod) { return Magic + mod; }
bool   IsMyMagic(long m) { return m >= Magic && m < Magic + NMOD; }
ENUM_TIMEFRAMES ModTF(int mod) { return mod == MOD_SOLDIERS ? SoldiersTF : (mod == MOD_HS ? HsTF : GapTF); }
int    ModHold(int mod) { return mod == MOD_SOLDIERS ? SoldiersMaxHoldBars : (mod == MOD_HS ? HsMaxHoldBars : GapMaxHoldBars); }

//====================================================================
// Wilder ATR over a chronological rates array (same as atr_rma in the replays)
//====================================================================
void WilderATR(const MqlRates &r[], int n, double &a[])
  {
   ArrayResize(a, n); ArrayInitialize(a, 0.0);
   if(n < ATRPeriod + 1) return;
   double s = 0;
   for(int i = 0; i < n; i++)
     {
      double pc = i > 0 ? r[i - 1].close : r[0].close;
      double tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      if(i < ATRPeriod) { s += tr; if(i == ATRPeriod - 1) a[i] = s / ATRPeriod; }
      else a[i] = (a[i - 1] * (ATRPeriod - 1) + tr) / ATRPeriod;
     }
  }

// closed bars, oldest first (r[n-1] = last closed bar)
int ClosedRates(ENUM_TIMEFRAMES tf, int n, MqlRates &r[])
  {
   ArraySetAsSeries(r, false);
   int got = CopyRates(_Symbol, tf, 1, n, r);
   return got;
  }

//====================================================================
// ACCOUNT GUARD (state survives restarts in terminal global variables)
//====================================================================
string g_gv = "";
bool   GuardOn() { return UseGuard && !g_shadow; }
double GGet(string k, double def) { return GlobalVariableCheck(g_gv + k) ? GlobalVariableGet(g_gv + k) : def; }
void   GSet(string k, double v)   { GlobalVariableSet(g_gv + k, v); }

void GuardInit()
  {
   g_gv = "TPA_G_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(Magic) + "_";
   if(GuardRearm || !GlobalVariableCheck(g_gv + "PEAK"))
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      GSet("PEAK", bal); GSet("PEAKT", (double)TimeCurrent()); GSet("TRIP", 0);
      Print("[TWI PA] GUARD armed: peak balance ", DoubleToString(bal, 2));
     }
  }
double GuardFloor() { return PeakDDKillPct > 0 ? GGet("PEAK", 0) * (1.0 - PeakDDKillPct / 100.0) : -DBL_MAX; }

int DeletePendings(int mod, string why)    // mod < 0 = all modules
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      long om = OrderGetInteger(ORDER_MAGIC);
      if(!IsMyMagic(om) || (mod >= 0 && om != MagicOf(mod))) continue;
      if(g_tr[(int)(om - Magic)].OrderDelete(t)) n++;
     }
   if(n > 0) Dbg(StringFormat("deleted %d pending (%s)", n, why));
   return n;
  }

void GuardTrip(string why)
  {
   if(GGet("TRIP", 0) > 0) return;
   GSet("TRIP", 1);
   string msg = "TWI Gold PA GUARD TRIPPED: " + why + ". No new orders until GuardRearm.";
   Print("[TWI PA] ", msg); Alert(msg);
   DeletePendings(-1, "guard trip");             // unfilled orders are new trades; open positions are left alone
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

double RealizedSince(datetime from)
  {
   double sum = 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(!IsMyMagic(HistoryDealGetInteger(d, DEAL_MAGIC))) continue;
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
      if(!IsMyMagic(HistoryDealGetInteger(d, DEAL_MAGIC))) continue;
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
            if(GuardOn()) Alert("TWI Gold PA: " + why + " - trade skipped.");
            return false;
           }
        }
     }
   lots = MathMax(minLot, MathMin(maxLot, NormalizeDouble(MathRound(lots / step) * step, 8)));
   if(LotMode == LOTS_FIXED && MaxRiskPerTradePct > 0 && lots * perLot > eq * MaxRiskPerTradePct / 100.0)
     {
      why = StringFormat("risk %.2f > %.1f%% of equity", lots * perLot, MaxRiskPerTradePct);
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

//====================================================================
// positions / orders per module
//====================================================================
ulong ModPosition(int mod)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicOf(mod)) return t;
     }
   return 0;
  }

int ModPendings(int mod)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicOf(mod)) n++;
     }
   return n;
  }

bool ShadowBusy(int mod, bool countPending)
  {
   for(int i = 0; i < NVT; i++)
      if(g_vt[i].mod == mod && (g_vt[i].state == 2 || (countPending && g_vt[i].state == 1))) return true;
   return false;
  }

bool ModBusy(int mod) { return g_shadow ? ShadowBusy(mod, false) : ModPosition(mod) > 0; }

// time exits + pending expiry (LIVE)
void ManageLive()
  {
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long pm = PositionGetInteger(POSITION_MAGIC);
      if(!IsMyMagic(pm)) continue;
      int mod = (int)(pm - Magic);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(now - opened >= (long)ModHold(mod) * PeriodSeconds(ModTF(mod)) && g_tr[mod].PositionClose(t))
         Dbg(StringFormat("%s time exit after %d bars", MODNAME[mod], ModHold(mod)));
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != MagicOf(MOD_GAP)) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(now - setup >= (long)GapValidBars * PeriodSeconds(GapTF) && g_tr[MOD_GAP].OrderDelete(t)) Dbg("Gap limit expired");
     }
  }

//====================================================================
// SHADOW: virtual orders from live bid/ask, nothing is ever sent
//====================================================================
void ShadowLog(int k, double px, string why)
  {
   VT v = g_vt[k];
   double risk = MathAbs(v.entry - v.sl), R = risk > 0 ? v.dir * (px - v.entry) / risk : 0, money = 0;
   if(!OrderCalcProfit(v.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, v.lots, v.entry, px, money)) money = 0;
   Dbg(StringFormat("SHADOW %s %s closed @ %s (%s): %+.2fR, %+.2f at %.2f lots", MODNAME[v.mod], v.dir > 0 ? "BUY" : "SELL", P(px), why, R, money, v.lots));
   string fn = "TWIGoldPA_shadow.csv";
   bool fresh = !FileIsExist(fn);
   int h = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      if(fresh) FileWrite(h, "symbol", "module", "fill_server", "close_server", "side", "entry", "sl", "tp", "exit", "reason", "R", "money", "lots");
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, _Symbol, MODNAME[v.mod], TimeToString(v.fillTime), TimeToString(TimeCurrent()), v.dir > 0 ? "BUY" : "SELL", P(v.entry), P(v.sl), P(v.tp), P(px), why,
                DoubleToString(R, 3), DoubleToString(money, 2), DoubleToString(v.lots, 2));
      FileClose(h);
     }
   g_vt[k].state = 0;
  }

void ShadowTick()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime now = TimeCurrent();
   for(int k = 0; k < NVT; k++)
     {
      if(g_vt[k].state == 1)
        {
         if(now >= g_vt[k].expiry) { g_vt[k].state = 0; Dbg(StringFormat("SHADOW %s limit expired", MODNAME[g_vt[k].mod])); continue; }
         if(ShadowBusy(g_vt[k].mod, false)) continue;
         bool fill = g_vt[k].dir > 0 ? ask <= g_vt[k].entry : bid >= g_vt[k].entry;
         if(!fill) continue;
         g_vt[k].state = 2; g_vt[k].fillTime = now;
         g_vt[k].deadline = now + (datetime)((long)ModHold(g_vt[k].mod) * PeriodSeconds(ModTF(g_vt[k].mod)));
         g_taken[g_vt[k].mod]++;
         Dbg(StringFormat("SHADOW %s %s limit filled @ %s", MODNAME[g_vt[k].mod], g_vt[k].dir > 0 ? "BUY" : "SELL", P(g_vt[k].entry)));
         for(int j = 0; j < NVT; j++)                        // one at a time: the fill cancels this module's other limits
            if(j != k && g_vt[j].state == 1 && g_vt[j].mod == g_vt[k].mod) g_vt[j].state = 0;
         continue;
        }
      if(g_vt[k].state != 2) continue;
      double px = g_vt[k].dir > 0 ? bid : ask;
      if(g_vt[k].dir * (g_vt[k].sl - px) >= 0)      ShadowLog(k, px, "SL");
      else if(g_vt[k].dir * (px - g_vt[k].tp) >= 0) ShadowLog(k, px, "TP");
      else if(now >= g_vt[k].deadline)              ShadowLog(k, px, "time");
     }
  }

int ShadowSlot()
  {
   for(int i = 0; i < NVT; i++) if(g_vt[i].state == 0) return i;
   return -1;
  }

//====================================================================
// EXECUTION (shared by all modules)
//  limit = false: market now, SL fixed, TP = entry +/- targetR x risk at the actual fill
//  limit = true : limit at 'price' (market if price is already through it), SL/TP fixed from 'price'
//====================================================================
void Execute(int mod, int dir, bool limit, double price, double sl, double targetR)
  {
   string gwhy;
   if(!GuardAllowsNewTrade(gwhy)) { g_skip[mod]++; Dbg(MODNAME[mod] + " skip: " + gwhy); return; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool marketNow = !limit || (dir > 0 ? ask <= price : bid >= price);
   double entry = limit ? price : (dir > 0 ? ask : bid);
   sl = NormPrice(sl);
   double risk = dir * (entry - sl);
   if(risk <= 0) { g_skip[mod]++; Dbg(MODNAME[mod] + " skip: stop on the wrong side"); return; }
   if(MaxSpreadToRisk > 0 && (ask - bid) > MaxSpreadToRisk * risk) { g_skip[mod]++; Dbg(MODNAME[mod] + " skip: spread vs stop"); return; }
   double tp = NormPrice(entry + dir * targetR * risk);
   double lots; string why;
   if(!CalcLots(dir > 0, entry, sl, lots, why)) { g_skip[mod]++; Dbg(MODNAME[mod] + " skip: " + why); return; }
   string side = dir > 0 ? "BUY" : "SELL";
   if(g_shadow)
     {
      int k = ShadowSlot();
      if(k < 0) { g_skip[mod]++; return; }
      g_vt[k].mod = mod; g_vt[k].dir = dir; g_vt[k].sl = sl; g_vt[k].tp = tp; g_vt[k].lots = lots;
      if(marketNow)
        {
         g_vt[k].entry = limit ? (dir > 0 ? ask : bid) : entry;
         g_vt[k].state = 2; g_vt[k].fillTime = TimeCurrent();
         g_vt[k].deadline = TimeCurrent() + (datetime)((long)ModHold(mod) * PeriodSeconds(ModTF(mod)));
         g_taken[mod]++;
         Dbg(StringFormat("SHADOW %s %s %.2f @ %s  SL %s  TP %s", MODNAME[mod], side, lots, P(g_vt[k].entry), P(sl), P(tp)));
        }
      else
        {
         g_vt[k].entry = NormPrice(price); g_vt[k].state = 1;
         g_vt[k].expiry = TimeCurrent() + (datetime)((long)GapValidBars * PeriodSeconds(ModTF(mod)));
         Dbg(StringFormat("SHADOW %s %s LIMIT %.2f @ %s  SL %s  TP %s", MODNAME[mod], side, lots, P(price), P(sl), P(tp)));
        }
      return;
     }
   string cmt = TradeComment + " " + MODNAME[mod];
   bool ok;
   if(marketNow) ok = dir > 0 ? g_tr[mod].Buy(lots, _Symbol, 0, sl, tp, cmt) : g_tr[mod].Sell(lots, _Symbol, 0, sl, tp, cmt);
   else          ok = dir > 0 ? g_tr[mod].BuyLimit(lots, NormPrice(price), _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
                              : g_tr[mod].SellLimit(lots, NormPrice(price), _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(ok && marketNow) g_taken[mod]++;
   Dbg(StringFormat("%s %s %s %.2f @ %s  SL %s  TP %s%s", MODNAME[mod], side, marketNow ? "MARKET" : "LIMIT", lots, P(marketNow ? entry : price), P(sl), P(tp),
                    ok ? "" : StringFormat("  FAILED %u", g_tr[mod].ResultRetcode())));
  }

bool NewBar(int mod)
  {
   datetime b = iTime(_Symbol, ModTF(mod), 0);
   if(b == 0 || b == g_lastBar[mod]) return false;
   bool first = g_lastBar[mod] == 0;
   g_lastBar[mod] = b;
   return !first;                                  // don't act on the bar the EA was attached in
  }

//====================================================================
// 1. THREE SOLDIERS / THREE CROWS
//====================================================================
void SoldiersTick()
  {
   MqlRates r[]; double a[];
   int n = ClosedRates(SoldiersTF, 300, r);
   if(n < 60) return;
   WilderATR(r, n, a);
   int j = n - 1; double atr = a[j];
   if(atr <= 0) return;
   datetime barT = r[j].time;
   if(g_lastSig[MOD_SOLDIERS] > 0 && barT - g_lastSig[MOD_SOLDIERS] < 3 * PeriodSeconds(SoldiersTF)) return;
   for(int d = 1; d >= -1; d -= 2)
     {
      bool ok = true;
      for(int m = j - 2; m <= j && ok; m++)
        {
         double rng = r[m].high - r[m].low;
         if(rng <= 0 || d * (r[m].close - r[m].open) < SoldiersBodyATR * atr || d * (r[m].close - r[m - 1].close) <= 0) ok = false;
         else if(d == 1 && r[m].close < r[m].high - SoldiersCloseZone * rng) ok = false;
         else if(d == -1 && r[m].close > r[m].low + SoldiersCloseZone * rng) ok = false;
        }
      if(!ok) continue;
      g_lastSig[MOD_SOLDIERS] = barT; g_sig[MOD_SOLDIERS]++;
      if(ModBusy(MOD_SOLDIERS)) { g_skip[MOD_SOLDIERS]++; Dbg("Soldiers signal while a trade is open -> skip"); return; }
      double sl = d > 0 ? r[j - 2].low - SoldiersStopATR * atr : r[j - 2].high + SoldiersStopATR * atr;
      Dbg(StringFormat("Three %s on %s", d > 0 ? "white soldiers" : "black crows", TimeToString(r[j - 2].time)));
      Execute(MOD_SOLDIERS, d, false, 0, sl, SoldiersTargetR);
      return;
     }
  }

//====================================================================
// 2. HEAD & SHOULDERS (and inverse)
//====================================================================
struct Pv { int conf, i, t; double p; };

void HsTick()
  {
   if(ModBusy(MOD_HS)) return;
   MqlRates r[]; double a[];
   int n = ClosedRates(HsTF, HsLookbackBars, r);
   int K = HsSwingStrength;
   if(n < 100) return;
   WilderATR(r, n, a);
   // confirmed fractal swings, alternated (a run of same-type swings keeps the most extreme)
   Pv sw[]; int ns = 0;
   ArrayResize(sw, 0, n);
   for(int i = K; i < n - K; i++)
     {
      bool isH = true, isL = true;
      for(int q = 1; q <= K; q++)
        {
         if(!(r[i].high > r[i - q].high) || !(r[i].high >= r[i + q].high)) isH = false;
         if(!(r[i].low < r[i - q].low) || !(r[i].low <= r[i + q].low)) isL = false;
        }
      for(int pass = 0; pass < 2; pass++)          // low first, then high (same order as the replay's sort)
        {
         int t = pass == 0 ? -1 : 1;
         if((t == -1 && !isL) || (t == 1 && !isH)) continue;
         double p = t == 1 ? r[i].high : r[i].low;
         if(ns > 0 && sw[ns - 1].t == t)
           {
            if((t == 1 && p > sw[ns - 1].p) || (t == -1 && p < sw[ns - 1].p)) { sw[ns - 1].conf = i + K; sw[ns - 1].i = i; sw[ns - 1].p = p; }
           }
         else
           {
            ArrayResize(sw, ns + 1, n);
            sw[ns].conf = i + K; sw[ns].i = i; sw[ns].t = t; sw[ns].p = p; ns++;
           }
        }
     }
   int j = n - 1;
   for(int w = 4; w < ns; w++)
     {
      int conf = sw[w].conf;
      if(conf > j || j - conf >= HsBreakWindowBars) continue;
      double atr = a[conf];
      if(atr <= 0) continue;
      int typ = sw[w - 4].t;
      double ls = sw[w - 4].p, t1 = sw[w - 3].p, hd = sw[w - 2].p, t2 = sw[w - 1].p, rs = sw[w].p;
      double hiShoulder = typ == 1 ? MathMax(ls, rs) : MathMin(ls, rs);
      if(!(typ * (hd - ls) > 0 && typ * (hd - rs) > 0 && MathAbs(ls - rs) <= HsShoulderTolATR * atr && typ * (hd - hiShoulder) >= HsHeadMinATR * atr)) continue;
      int i1 = sw[w - 3].i, i2 = sw[w - 1].i;
      double slope = i2 != i1 ? (t2 - t1) / (i2 - i1) : 0.0;
      int d = -typ;
      // the break must be the FIRST neckline close since the right shoulder's confirmation, and it must be the last closed bar
      bool earlier = false;
      for(int q = conf; q < j && !earlier; q++) if(d * (r[q].close - (t1 + slope * (q - i1))) > 0) earlier = true;
      if(earlier) continue;
      double neckJ = t1 + slope * (j - i1);
      if(d * (r[j].close - neckJ) <= 0) continue;
      double height = MathAbs(hd - (t1 + slope * (sw[w - 2].i - i1)));
      double target = neckJ + d * height;
      double sl = rs - d * HsStopATR * atr;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double entry = d > 0 ? ask : bid, risk = d * (entry - sl);
      if(risk <= 0) continue;
      double tR = MathMin(MathMax(d * (target - entry) / risk, HsMinR), HsMaxR);
      g_sig[MOD_HS]++;
      Dbg(StringFormat("%s head & shoulders: neckline close %s, head %s, target %.2fR", d < 0 ? "Bearish" : "Inverse (bullish)", P(r[j].close), P(hd), tR));
      Execute(MOD_HS, d, false, 0, sl, tR);
      return;
     }
  }

//====================================================================
// 3. FVG GAP ENTRY
//====================================================================
void GapTick()
  {
   MqlRates r[]; double a[];
   int n = ClosedRates(GapTF, 300, r);
   if(n < 60) return;
   WilderATR(r, n, a);
   int f = n - 1, i = n - 2;                       // f = the bar that confirms the gap, i = the impulse
   double atr = a[i];
   if(atr <= 0) return;
   double body = r[i].close - r[i].open;
   if(MathAbs(body) < GapImpulseATR * atr) return;
   int d = body > 0 ? 1 : -1;
   bool fvg = d > 0 ? r[f].low > r[i - 1].high : r[f].high < r[i - 1].low;
   if(!fvg) return;
   g_sig[MOD_GAP]++;
   if(ModBusy(MOD_GAP)) { g_skip[MOD_GAP]++; Dbg("Gap setup while a trade is open -> skip"); return; }
   double price = d > 0 ? r[f].low : r[f].high;
   double sl = d > 0 ? r[i].low - GapStopATR * atr : r[i].high + GapStopATR * atr;
   Dbg(StringFormat("%s impulse + FVG (%s-%s)", d > 0 ? "Bullish" : "Bearish", P(d > 0 ? r[i - 1].high : r[f].high), P(d > 0 ? r[f].low : r[i - 1].low)));
   Execute(MOD_GAP, d, true, price, sl, GapTargetR);
  }

//====================================================================
int OnInit()
  {
   if(SoldiersTargetR <= 0 || GapTargetR <= 0 || HsMinR <= 0 || HsMaxR < HsMinR || ATRPeriod < 2 || HsSwingStrength < 1) { Print("[TWI PA] bad inputs"); return INIT_PARAMETERS_INCORRECT; }
   g_shadow = RunMode == RUN_SHADOW && !MQLInfoInteger(MQL_TESTER);
   if(g_shadow) Print("[TWI PA] SHADOW MODE: no orders will be sent. Virtual trades -> MQL5\\Files\\TWIGoldPA_shadow.csv");
   if(GuardOn())
     {
      GuardInit();
      PrintFormat("[TWI PA] guard: daily %.1f%%, weekly %.1f%%, kill %.1f%% under peak (floor %.2f), %s", DailyLossPct, WeeklyLossPct, PeakDDKillPct,
                  GuardFloor(), GGet("TRIP", 0) > 0 ? "TRIPPED (set GuardRearm to re-arm)" : "armed");
     }
   for(int m = 0; m < NMOD; m++)
     {
      g_tr[m].SetExpertMagicNumber(MagicOf(m));
      g_tr[m].SetTypeFillingBySymbol(_Symbol);
      g_lastBar[m] = 0; g_lastSig[m] = 0; g_sig[m] = 0; g_taken[m] = 0; g_skip[m] = 0;
     }
   for(int k = 0; k < NVT; k++) g_vt[k].state = 0;
   Dbg(StringFormat("init %s | Soldiers %s (%s) | H&S %s (%s) | Gap %s (%s)", _Symbol,
                    UseSoldiers ? "ON" : "off", EnumToString(SoldiersTF), UseHeadShoulders ? "ON" : "off", EnumToString(HsTF),
                    UseGapEntry ? "ON" : "off", EnumToString(GapTF)));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   for(int m = 0; m < NMOD; m++)
      PrintFormat("[TWI PA] %s: signals %d | taken %d | skipped %d", MODNAME[m], g_sig[m], g_taken[m], g_skip[m]);
   PrintFormat("[TWI PA] guard %s", GuardOn() ? (GGet("TRIP", 0) > 0 ? "TRIPPED" : "armed") : "off");
  }

void OnTradeTransaction(const MqlTradeTransaction &tx, const MqlTradeRequest &rq, const MqlTradeResult &rs)
  {
   if(tx.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   long dm = HistoryDealGetInteger(tx.deal, DEAL_MAGIC);
   if(!IsMyMagic(dm) || HistoryDealGetInteger(tx.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   int mod = (int)(dm - Magic);
   if(mod == MOD_GAP)
     {
      g_taken[mod]++;
      DeletePendings(MOD_GAP, "gap limit filled - one trade at a time");
     }
  }

void OnTick()
  {
   if(g_shadow) ShadowTick();
   else
     {
      if(GuardOn()) GuardUpdate();
      ManageLive();
     }
   if(UseSoldiers && NewBar(MOD_SOLDIERS)) SoldiersTick();
   if(UseHeadShoulders && NewBar(MOD_HS)) HsTick();
   if(UseGapEntry && NewBar(MOD_GAP)) GapTick();
  }
//+------------------------------------------------------------------+
