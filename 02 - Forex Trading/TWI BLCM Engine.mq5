//+------------------------------------------------------------------+
//| TWI BLCM Engine                                                  |
//| Bias -> Location -> Confirmation -> Execution -> Management      |
//|                                                                  |
//| A SEQUENTIAL state machine, deliberately not an indicator stack. |
//| Each stage asks only its own question and is only reached once    |
//| the previous stage is satisfied. This is the structural fix for   |
//| the AND-stack failure that produced near-zero trade frequency in  |
//| TWI SR Sweep Reclaim and TWI TakeProfit SMC EA.                   |
//|                                                                  |
//| Volume profile is deliberately ABSENT in v1: on MT5 spot CFDs     |
//| "volume" is broker tick volume, so it earns its place later as a  |
//| scored input that is tested, never as a gate that is assumed.     |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict
#property description "Bias/Location/Confirmation/Management sequential engine."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;
CAccountInfo  account;

//====================================================================
// INPUTS
//====================================================================
input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpBiasTF        = PERIOD_H1;   // stage 1
input ENUM_TIMEFRAMES InpLocationTF    = PERIOD_M15;  // stage 2
input ENUM_TIMEFRAMES InpEntryTF       = PERIOD_M5;   // stage 3

input group "=== Stage 1: Bias ==="
input int    InpBiasSwingLeft   = 3;
input int    InpBiasSwingRight  = 3;
input int    InpBiasLookback    = 250;
input int    InpBiasMaxAgeBars  = 48;   // bias re-evaluated every bias bar anyway

input group "=== Stage 2: Location ==="
input int    InpLocSwingLeft    = 3;
input int    InpLocSwingRight   = 3;
input int    InpLocLookback     = 250;
input double InpZoneClusterATR  = 0.25; // a bar joins a level if within this of it
input int    InpMaxClusterBars  = 8;
input int    InpMinClusterTouch = 2;
input double InpMinZoneThickATR = 0.10;
input double InpMaxZoneThickATR = 0.60;
input double InpZoneTouchBuffer = 0.15; // ATR fraction of tolerance when tagging
input int    InpRangeBars       = 60;   // range used for discount/premium context
input int    InpMaxLocationWait = 60;   // location bars to wait before abandoning bias

input group "=== Stage 3: Confirmation ==="
input int    InpMaxConfirmWait     = 24;   // entry bars at location before giving up
input double InpDisplacementATR    = 0.80; // body size that counts as displacement
input double InpRejectionWickRatio = 0.45;

input group "=== Stage 4: Execution / risk ==="
input double InpRiskPercent          = 0.50;
input double InpMaxActualRiskPercent = 0.60;  // absolute pre-send ceiling
input double InpSLBufferATR          = 0.10;  // beyond structural invalidation only
input int    InpMaxPositions         = 1;
input long   InpMagic                = 20260904;
input int    InpMaxSpreadPoints      = 400;   // gold is ~250-265 pts on this broker
input int    InpSlippagePoints       = 30;

input group "=== Stage 5: Management ==="
input double InpPartial1AtR   = 1.0;
input double InpPartial1Pct   = 40.0;
input double InpPartial2Pct   = 30.0;
input double InpTrailStartR   = 1.25;
input bool   InpStructureTrail = true;  // trail under newly formed higher lows
input bool   InpExitOnStructureBreak = true;

input group "=== Diagnostics ==="
input bool   InpDebugStats   = true;
input bool   InpLogEveryStage = true;

//====================================================================
// TYPES
//====================================================================
enum BLCM_STATE
  {
   ST_BIAS,          // stage 1
   ST_LOCATION,      // stage 2
   ST_CONFIRM,       // stage 3
   ST_MANAGE         // stages 4/5 (position live)
  };

struct SwingPt { datetime t; double price; };

struct Zone
  {
   int      type;    // +1 supply/resistance, -1 demand/support
   double   hi, lo;
   datetime created;
   int      touches;
   bool     broken;
  };

struct LiveTrade
  {
   ulong    posId;
   int      dir;
   double   entry, rawSL, finalSL, riskPrice, riskMoney;
   double   tp1, tp2;
   double   mfeR, maeR;
   double   initialVolume;
   bool     partial1Done, partial2Done;
  };

//====================================================================
// STATE
//====================================================================
BLCM_STATE g_state = ST_BIAS;
int        g_bias  = 0;          // +1 buy, -1 sell, 0 neutral
int        g_locationWait = 0;
int        g_confirmWait  = 0;
double     g_locHi, g_locLo;     // the location area price must reach
string     g_locKind = "";
Zone       g_zones[];
LiveTrade  g_live[];

datetime g_lastBiasBar = 0, g_lastLocBar = 0, g_lastEntryBar = 0;
int g_atrLocHandle = INVALID_HANDLE, g_atrEntryHandle = INVALID_HANDLE;

//--- funnel counters
long c_biasBars=0, c_biasBull=0, c_biasBear=0, c_biasNeutral=0;
long c_locationArmed=0, c_locationReached=0, c_locationTimeout=0, c_locationBiasFlip=0;
long c_confirmTried=0, c_confirmHit=0, c_confirmTimeout=0, c_confirmBiasFlip=0;
long c_confEngulf=0, c_confRejection=0, c_confDisplacement=0, c_confReclaim=0;
long c_riskRejectMinLot=0, c_riskRejectGuard=0, c_spreadBlocked=0, c_maxPosBlocked=0;
long c_entries=0, c_entriesBuy=0, c_entriesSell=0;
long c_closed=0, c_wins=0, c_losses=0, c_riskMismatch=0;
double c_sumWinR=0, c_sumLossR=0, c_sumMFE=0, c_sumMAE=0;
double c_riskPctSum=0, c_riskPctMin=99999, c_riskPctMax=0; long c_riskPctN=0;
long c_lossesWithMFE1R=0;

//====================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_atrLocHandle   = iATR(_Symbol, InpLocationTF, 14);
   g_atrEntryHandle = iATR(_Symbol, InpEntryTF, 14);
   if(g_atrLocHandle == INVALID_HANDLE || g_atrEntryHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   Print("TWI BLCM Engine init on ", _Symbol,
         " bias=", EnumToString(InpBiasTF),
         " location=", EnumToString(InpLocationTF),
         " entry=", EnumToString(InpEntryTF));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_atrLocHandle   != INVALID_HANDLE) IndicatorRelease(g_atrLocHandle);
   if(g_atrEntryHandle != INVALID_HANDLE) IndicatorRelease(g_atrEntryHandle);
   if(!InpDebugStats) return;

   double avgWinR  = (c_wins   > 0) ? c_sumWinR  / c_wins   : 0;
   double avgLossR = (c_losses > 0) ? c_sumLossR / c_losses : 0;
   double expR     = (c_closed > 0) ? (c_sumWinR + c_sumLossR) / c_closed : 0;
   double pfR      = (c_sumLossR != 0) ? c_sumWinR / MathAbs(c_sumLossR) : 0;
   double avgRisk  = (c_riskPctN > 0) ? c_riskPctSum / c_riskPctN : 0;

   PrintFormat("=== BLCM FUNNEL ===\nBias bars evaluated: %d (bull %d | bear %d | neutral %d)\nLocations armed: %d\n  reached: %d | timed out: %d | bias flipped: %d\nConfirmation attempts: %d\n  confirmed: %d | timed out: %d | bias flipped: %d\n  engulf %d | rejection %d | displacement %d | reclaim %d\nBlocked: spread %d | max positions %d\nRisk refusals: min-lot %d | guard %d\nENTRIES: %d (buy %d | sell %d)",
               c_biasBars, c_biasBull, c_biasBear, c_biasNeutral,
               c_locationArmed, c_locationReached, c_locationTimeout, c_locationBiasFlip,
               c_confirmTried, c_confirmHit, c_confirmTimeout, c_confirmBiasFlip,
               c_confEngulf, c_confRejection, c_confDisplacement, c_confReclaim,
               c_spreadBlocked, c_maxPosBlocked,
               c_riskRejectMinLot, c_riskRejectGuard,
               c_entries, c_entriesBuy, c_entriesSell);

   PrintFormat("=== BLCM RESULTS ===\nClosed deals: %d | wins %d | losses %d | win rate %.1f%%\nAvg win %.2fR | avg loss %.2fR\nExpectancy %.3fR | R-based PF %.2f\nAvg MFE %.2fR | avg MAE %.2fR\nLosers that reached +1R: %d of %d\nActual risk %%: min %.3f | avg %.3f | max %.3f\nRisk-model mismatches: %d",
               c_closed, c_wins, c_losses,
               c_closed > 0 ? 100.0 * c_wins / c_closed : 0,
               avgWinR, avgLossR, expR, pfR,
               c_closed > 0 ? c_sumMFE / c_closed : 0,
               c_closed > 0 ? c_sumMAE / c_closed : 0,
               c_lossesWithMFE1R, c_losses,
               c_riskPctN > 0 ? c_riskPctMin : 0, avgRisk, c_riskPctMax,
               c_riskMismatch);
  }

//====================================================================
// UTILITIES
//====================================================================
double ATR(int handle)
  {
   double b[];
   if(CopyBuffer(handle, 0, 1, 1, b) != 1) return(0);
   return(b[0]);
  }

bool NewBar(ENUM_TIMEFRAMES tf, datetime &last)
  {
   datetime t = iTime(_Symbol, tf, 0);
   if(t == last) return(false);
   last = t;
   return(true);
  }

bool SpreadOK()
  {
   return(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints);
  }

int CountOwn()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) n++;
     }
   return(n);
  }

//--- swing detection, closed bars only (no repaint)
bool LastTwoHighs(ENUM_TIMEFRAMES tf, int left, int right, int lookback, SwingPt &a, SwingPt &b)
  {
   double h[]; datetime tm[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(tm, true);
   if(CopyHigh(_Symbol, tf, 1, lookback, h) < lookback) return(false);
   if(CopyTime(_Symbol, tf, 1, lookback, tm) < lookback) return(false);
   int found = 0;
   for(int i = right; i < lookback - left && found < 2; i++)
     {
      bool ok = true;
      for(int k = 1; k <= left  && ok; k++) if(h[i+k] > h[i]) ok = false;
      for(int k = 1; k <= right && ok; k++) if(h[i-k] > h[i]) ok = false;
      if(ok) { if(found == 0) { a.t = tm[i]; a.price = h[i]; } else { b.t = tm[i]; b.price = h[i]; } found++; }
     }
   return(found == 2);
  }

bool LastTwoLows(ENUM_TIMEFRAMES tf, int left, int right, int lookback, SwingPt &a, SwingPt &b)
  {
   double l[]; datetime tm[];
   ArraySetAsSeries(l, true); ArraySetAsSeries(tm, true);
   if(CopyLow(_Symbol, tf, 1, lookback, l) < lookback) return(false);
   if(CopyTime(_Symbol, tf, 1, lookback, tm) < lookback) return(false);
   int found = 0;
   for(int i = right; i < lookback - left && found < 2; i++)
     {
      bool ok = true;
      for(int k = 1; k <= left  && ok; k++) if(l[i+k] < l[i]) ok = false;
      for(int k = 1; k <= right && ok; k++) if(l[i-k] < l[i]) ok = false;
      if(ok) { if(found == 0) { a.t = tm[i]; a.price = l[i]; } else { b.t = tm[i]; b.price = l[i]; } found++; }
     }
   return(found == 2);
  }

//====================================================================
// STAGE 1 — BIAS   (structure only; no indicator, no volume)
//====================================================================
int DetermineBias()
  {
   SwingPt h1, h2, l1, l2;
   if(!LastTwoHighs(InpBiasTF, InpBiasSwingLeft, InpBiasSwingRight, InpBiasLookback, h1, h2)) return(0);
   if(!LastTwoLows (InpBiasTF, InpBiasSwingLeft, InpBiasSwingRight, InpBiasLookback, l1, l2)) return(0);
   if(h1.price > h2.price && l1.price > l2.price) return(+1);
   if(h1.price < h2.price && l1.price < l2.price) return(-1);
   return(0);
  }

//====================================================================
// STAGE 2 — LOCATION
// A bullish bias does not mean buy anywhere. Price must reach an area
// where executing the bias makes sense. ANY ONE of these qualifies:
//   (a) a demand/supply zone built from a real touch cluster
//   (b) a retest of a level that was broken and flipped
//   (c) the discount half of the recent range (buys) / premium (sells)
// (c) stands in for "interaction levels / AMT" WITHOUT volume profile.
//====================================================================
double Median(double &v[], int n)
  {
   if(n <= 0) return(0);
   double c[]; ArrayResize(c, n); ArrayCopy(c, v, 0, 0, n); ArraySort(c);
   if(n % 2 == 1) return(c[n/2]);
   return((c[n/2 - 1] + c[n/2]) / 2.0);
  }

bool BuildZone(int type, datetime swingT, double atr, double &hi, double &lo, int &touches)
  {
   int shift = iBarShift(_Symbol, InpLocationTF, swingT, false);
   double refv = (type > 0) ? iHigh(_Symbol, InpLocationTF, shift) : iLow(_Symbol, InpLocationTF, shift);
   double tol  = InpZoneClusterATR * atr;
   int total = Bars(_Symbol, InpLocationTF);

   double bodies[]; int n = 0;
   double ext = refv;
   for(int s = shift - InpMaxClusterBars; s <= shift + InpMaxClusterBars; s++)
     {
      if(s < 1 || s >= total) continue;
      double v = (type > 0) ? iHigh(_Symbol, InpLocationTF, s) : iLow(_Symbol, InpLocationTF, s);
      if(MathAbs(v - refv) > tol) continue;      // must interact with the same area
      ArrayResize(bodies, n + 1);
      bodies[n++] = (type > 0)
                    ? MathMax(iOpen(_Symbol, InpLocationTF, s), iClose(_Symbol, InpLocationTF, s))
                    : MathMin(iOpen(_Symbol, InpLocationTF, s), iClose(_Symbol, InpLocationTF, s));
      ext = (type > 0) ? MathMax(ext, v) : MathMin(ext, v);
     }
   touches = n;
   if(n < InpMinClusterTouch) return(false);

   double body = Median(bodies, n);
   if(type > 0) { hi = ext; lo = body; } else { lo = ext; hi = body; }

   double thick = hi - lo;
   double minT = InpMinZoneThickATR * atr, maxT = InpMaxZoneThickATR * atr;
   if(thick < minT) thick = minT;
   if(thick > maxT) thick = maxT;
   if(type > 0) lo = hi - thick; else hi = lo + thick;
   return(true);
  }

void RangeHiLo(double &hi, double &lo)
  {
   hi = iHigh(_Symbol, InpLocationTF, iHighest(_Symbol, InpLocationTF, MODE_HIGH, InpRangeBars, 1));
   lo = iLow (_Symbol, InpLocationTF, iLowest (_Symbol, InpLocationTF, MODE_LOW,  InpRangeBars, 1));
  }

// Arm the execution area for the current bias. Returns false if no
// sensible location exists yet.
bool ArmLocation(int bias, double atr)
  {
   SwingPt h1, h2, l1, l2;
   int touches = 0;
   double hi = 0, lo = 0;

   // (a) zone in the direction we intend to trade FROM
   if(bias > 0 && LastTwoLows(InpLocationTF, InpLocSwingLeft, InpLocSwingRight, InpLocLookback, l1, l2))
     {
      if(BuildZone(-1, l1.t, atr, hi, lo, touches))
        { g_locHi = hi; g_locLo = lo; g_locKind = StringFormat("DEMAND_ZONE(touches=%d)", touches); return(true); }
     }
   if(bias < 0 && LastTwoHighs(InpLocationTF, InpLocSwingLeft, InpLocSwingRight, InpLocLookback, h1, h2))
     {
      if(BuildZone(+1, h1.t, atr, hi, lo, touches))
        { g_locHi = hi; g_locLo = lo; g_locKind = StringFormat("SUPPLY_ZONE(touches=%d)", touches); return(true); }
     }

   // (c) fall back to value context: discount for buys, premium for sells
   double rhi, rlo;
   RangeHiLo(rhi, rlo);
   if(rhi <= rlo) return(false);
   double mid = (rhi + rlo) / 2.0;
   if(bias > 0) { g_locHi = mid; g_locLo = rlo; g_locKind = "DISCOUNT_HALF"; return(true); }
   else         { g_locHi = rhi; g_locLo = mid; g_locKind = "PREMIUM_HALF";  return(true); }
  }

bool PriceAtLocation(double atr)
  {
   double pad = InpZoneTouchBuffer * atr;
   double lo = iLow (_Symbol, InpEntryTF, 1);
   double hi = iHigh(_Symbol, InpEntryTF, 1);
   return(hi >= g_locLo - pad && lo <= g_locHi + pad);
  }

//====================================================================
// STAGE 3 — CONFIRMATION (any ONE reaction, in the bias direction)
//====================================================================
string Confirmation(int bias, double atrEntry)
  {
   double o1 = iOpen (_Symbol, InpEntryTF, 1), c1 = iClose(_Symbol, InpEntryTF, 1);
   double h1 = iHigh (_Symbol, InpEntryTF, 1), l1 = iLow  (_Symbol, InpEntryTF, 1);
   double o2 = iOpen (_Symbol, InpEntryTF, 2), c2 = iClose(_Symbol, InpEntryTF, 2);
   double rng = h1 - l1;
   double body = MathAbs(c1 - o1);

   if(bias > 0)
     {
      if(c2 < o2 && c1 > o1 && o1 <= c2 && c1 >= o2) { c_confEngulf++;       return("BULL_ENGULF"); }
      if(rng > 0 && (MathMin(o1,c1) - l1) / rng >= InpRejectionWickRatio && c1 > o1)
                                                     { c_confRejection++;    return("BULL_REJECTION"); }
      if(body >= InpDisplacementATR * atrEntry && c1 > o1)
                                                     { c_confDisplacement++; return("BULL_DISPLACEMENT"); }
      if(l1 <= g_locHi && c1 > g_locHi)              { c_confReclaim++;      return("BULL_RECLAIM"); }
     }
   else
     {
      if(c2 > o2 && c1 < o1 && o1 >= c2 && c1 <= o2) { c_confEngulf++;       return("BEAR_ENGULF"); }
      if(rng > 0 && (h1 - MathMax(o1,c1)) / rng >= InpRejectionWickRatio && c1 < o1)
                                                     { c_confRejection++;    return("BEAR_REJECTION"); }
      if(body >= InpDisplacementATR * atrEntry && c1 < o1)
                                                     { c_confDisplacement++; return("BEAR_DISPLACEMENT"); }
      if(h1 >= g_locLo && c1 < g_locLo)              { c_confReclaim++;      return("BEAR_RECLAIM"); }
     }
   return("");
  }

//====================================================================
// STAGE 4 — EXECUTION (risk model carried over from TWI TakeProfit
// SMC EA v2.30: real contract spec, round down, never floor a
// sub-minimum lot up, absolute pre-send ceiling.)
//====================================================================
double RiskMoney(double entry, double stop, double volume, int dir)
  {
   double p = 0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, _Symbol, volume, entry, stop, p)) return(MathAbs(p));
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return(0);
   return(MathAbs(entry - stop) / ts * tv * volume);
  }

double NormLot(double lot)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st) * st;      // round DOWN only
   if(lot < mn) lot = 0;                // caller decides whether min lot is affordable
   if(lot > mx) lot = mx;
   return(NormalizeDouble(lot, 2));
  }

bool SafeLots(double entry, double stop, int dir, double &lots, double &riskM, double &riskPct)
  {
   lots = 0; riskM = 0; riskPct = 0;
   double eq = account.Equity();
   double allowed = eq * InpRiskPercent / 100.0;
   if(eq <= 0 || allowed <= 0) return(false);

   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double minRisk = RiskMoney(entry, stop, mn, dir);
   if(minRisk <= 0) return(false);

   double raw = mn * (allowed / minRisk);
   double v = NormLot(raw);
   if(v <= 0)
     {
      double pct = 100.0 * minRisk / eq;
      if(pct > InpMaxActualRiskPercent)
        {
         c_riskRejectMinLot++;
         if(InpDebugStats)
            PrintFormat("RISK_REJECT_MIN_LOT | requested$=%.2f | minLotRisk$=%.2f | pct=%.2f", allowed, minRisk, pct);
         return(false);
        }
      v = mn;
     }

   riskM   = RiskMoney(entry, stop, v, dir);
   riskPct = 100.0 * riskM / eq;
   if(riskPct > InpMaxActualRiskPercent)
     {
      c_riskRejectGuard++;
      if(InpDebugStats)
         PrintFormat("RISK_REJECT_GUARD | lots=%.2f | risk$=%.2f | pct=%.2f", v, riskM, riskPct);
      return(false);
     }
   lots = v;
   return(true);
  }

// Liquidity targets: nearest opposing swing, then the next one out.
bool NextTargets(int dir, double entry, double &t1, double &t2)
  {
   double best1 = 0, best2 = 0;
   bool f1 = false, f2 = false;
   double arr[]; datetime tm[];
   ArraySetAsSeries(arr, true);
   if(dir > 0)
     {
      if(CopyHigh(_Symbol, InpLocationTF, 1, InpLocLookback, arr) < InpLocLookback) return(false);
      for(int i = 0; i < InpLocLookback; i++)
        {
         if(arr[i] <= entry) continue;
         if(!f1 || arr[i] < best1) { best2 = f1 ? best1 : 0; f2 = f1; best1 = arr[i]; f1 = true; }
         else if(!f2 || arr[i] < best2) { best2 = arr[i]; f2 = true; }
        }
     }
   else
     {
      if(CopyLow(_Symbol, InpLocationTF, 1, InpLocLookback, arr) < InpLocLookback) return(false);
      for(int i = 0; i < InpLocLookback; i++)
        {
         if(arr[i] >= entry || arr[i] <= 0) continue;
         if(!f1 || arr[i] > best1) { best2 = f1 ? best1 : 0; f2 = f1; best1 = arr[i]; f1 = true; }
         else if(!f2 || arr[i] > best2) { best2 = arr[i]; f2 = true; }
        }
     }
   t1 = best1; t2 = f2 ? best2 : best1;
   return(f1);
  }

void Execute(int dir, string confirmName, double atrEntry)
  {
   if(!SpreadOK())              { c_spreadBlocked++; return; }
   if(CountOwn() >= InpMaxPositions) { c_maxPosBlocked++; return; }

   double entry = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double l1 = iLow (_Symbol, InpEntryTF, 1), l2 = iLow (_Symbol, InpEntryTF, 2);
   double h1 = iHigh(_Symbol, InpEntryTF, 1), h2 = iHigh(_Symbol, InpEntryTF, 2);
   double rawSL = (dir > 0) ? MathMin(l1, l2) : MathMax(h1, h2);
   double sl    = (dir > 0) ? rawSL - InpSLBufferATR * atrEntry
                            : rawSL + InpSLBufferATR * atrEntry;
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;

   double t1 = 0, t2 = 0;
   if(!NextTargets(dir, entry, t1, t2)) { t1 = entry + dir * risk * 2.0; t2 = entry + dir * risk * 3.0; }

   double lots = 0, riskM = 0, riskPct = 0;
   if(!SafeLots(entry, sl, dir, lots, riskM, riskPct)) return;

   if(InpDebugStats)
      PrintFormat("RISK_CHECK | equity=%.2f | reqPct=%.2f | lots=%.2f | entry=%.2f | SL=%.2f | risk=%.2f | risk$=%.2f | pct=%.3f | TP1=%.2f | TP2=%.2f | RR1=%.2f",
                  account.Equity(), InpRiskPercent, lots, entry, sl, risk, riskM, riskPct,
                  t1, t2, MathAbs(t1 - entry) / risk);

   bool ok = (dir > 0) ? trade.Buy (lots, _Symbol, entry, NormalizeDouble(sl, _Digits), 0, "BLCM|" + confirmName)
                       : trade.Sell(lots, _Symbol, entry, NormalizeDouble(sl, _Digits), 0, "BLCM|" + confirmName);
   if(!ok)
     {
      if(InpDebugStats) Print("Order failed: ", trade.ResultRetcodeDescription());
      return;
     }

   c_entries++;
   if(dir > 0) c_entriesBuy++; else c_entriesSell++;
   c_riskPctSum += riskPct; c_riskPctN++;
   if(riskPct < c_riskPctMin) c_riskPctMin = riskPct;
   if(riskPct > c_riskPctMax) c_riskPctMax = riskPct;

   int n = ArraySize(g_live);
   ArrayResize(g_live, n + 1);
   g_live[n].posId = trade.ResultOrder();
   g_live[n].dir = dir; g_live[n].entry = entry;
   g_live[n].rawSL = rawSL; g_live[n].finalSL = sl;
   g_live[n].riskPrice = risk; g_live[n].riskMoney = riskM;
   g_live[n].tp1 = t1; g_live[n].tp2 = t2;
   g_live[n].mfeR = 0; g_live[n].maeR = 0;
   g_live[n].initialVolume = lots;
   g_live[n].partial1Done = false; g_live[n].partial2Done = false;

   if(InpLogEveryStage)
      PrintFormat("ENTRY | %s | confirm=%s | location=%s | entry=%.2f | SL=%.2f | lots=%.2f | riskPct=%.3f",
                  dir > 0 ? "BUY" : "SELL", confirmName, g_locKind, entry, sl, lots, riskPct);
  }

//====================================================================
// STAGE 5 — MANAGEMENT
//====================================================================
int FindLive(ulong posId)
  {
   for(int i = 0; i < ArraySize(g_live); i++) if(g_live[i].posId == posId) return(i);
   return(-1);
  }

void Manage()
  {
   double atrEntry = ATR(g_atrEntryHandle);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic) continue;

      ulong ticket = posInfo.Ticket();
      ulong posId  = (ulong)posInfo.Identifier();
      int li = FindLive(posId);
      if(li < 0) continue;

      long typ   = posInfo.PositionType();
      double sl  = posInfo.StopLoss();
      double vol = posInfo.Volume();
      double px  = (typ == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double rNow = (typ == POSITION_TYPE_BUY)
                    ? (px - g_live[li].entry) / g_live[li].riskPrice
                    : (g_live[li].entry - px) / g_live[li].riskPrice;
      if(rNow > g_live[li].mfeR) g_live[li].mfeR = rNow;
      if(rNow < g_live[li].maeR) g_live[li].maeR = rNow;

      // partial 1 at +1R, then breakeven -- never before
      if(!g_live[li].partial1Done && rNow >= InpPartial1AtR)
        {
         double part = NormLot(g_live[li].initialVolume * InpPartial1Pct / 100.0);
         if(part > 0 && part < vol && trade.PositionClosePartial(ticket, part))
            g_live[li].partial1Done = true;
         double be = NormalizeDouble(g_live[li].entry, _Digits);
         if((typ == POSITION_TYPE_BUY && (sl < be || sl == 0)) ||
            (typ == POSITION_TYPE_SELL && (sl > be || sl == 0)))
            trade.PositionModify(ticket, be, posInfo.TakeProfit());
         continue;
        }

      // partial 2 at the first liquidity target
      if(g_live[li].partial1Done && !g_live[li].partial2Done)
        {
         bool hit = (typ == POSITION_TYPE_BUY) ? (px >= g_live[li].tp1) : (px <= g_live[li].tp1);
         if(hit)
           {
            double part2 = NormLot(g_live[li].initialVolume * InpPartial2Pct / 100.0);
            if(part2 > 0 && part2 < vol && trade.PositionClosePartial(ticket, part2))
               g_live[li].partial2Done = true;
            continue;
           }
        }

      // runner: trail under newly formed structure, not every candle
      if(InpStructureTrail && rNow >= InpTrailStartR)
        {
         SwingPt a, b;
         double newSL = sl;
         if(typ == POSITION_TYPE_BUY &&
            LastTwoLows(InpEntryTF, 2, 2, 60, a, b) && a.price - InpSLBufferATR * atrEntry > sl)
            newSL = a.price - InpSLBufferATR * atrEntry;
         if(typ == POSITION_TYPE_SELL &&
            LastTwoHighs(InpEntryTF, 2, 2, 60, a, b) &&
            (sl == 0 || a.price + InpSLBufferATR * atrEntry < sl))
            newSL = a.price + InpSLBufferATR * atrEntry;
         if(newSL != sl && newSL != 0)
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posInfo.TakeProfit());
        }

      // structural failure against the position
      if(InpExitOnStructureBreak)
        {
         int biasNow = DetermineBias();
         if((typ == POSITION_TYPE_BUY && biasNow == -1) ||
            (typ == POSITION_TYPE_SELL && biasNow == +1))
            trade.PositionClose(ticket);
        }
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   int li = FindLive(posId);
   if(li < 0) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double rr = (g_live[li].riskMoney > 0) ? profit / g_live[li].riskMoney : 0;

   c_closed++;
   if(profit >= 0) { c_wins++; c_sumWinR += rr; }
   else
     {
      c_losses++; c_sumLossR += rr;
      if(g_live[li].mfeR >= 1.0) c_lossesWithMFE1R++;
      if(g_live[li].maeR <= -0.98 && (rr < -1.25 || rr > -0.75)) c_riskMismatch++;
     }
   c_sumMFE += g_live[li].mfeR;
   c_sumMAE += g_live[li].maeR;

   if(InpDebugStats)
      PrintFormat("TRADE_RESULT | %s | entry=%.2f | rawSL=%.2f | finalSL=%.2f | risk$=%.2f | MFE=%.2fR | MAE=%.2fR | realizedR=%.2f | realized$=%.2f",
                  g_live[li].dir > 0 ? "BUY" : "SELL",
                  g_live[li].entry, g_live[li].rawSL, g_live[li].finalSL, g_live[li].riskMoney,
                  g_live[li].mfeR, g_live[li].maeR, rr, profit);
  }

//====================================================================
// THE SEQUENCE
//====================================================================
void OnTick()
  {
   Manage();

   double atrLoc   = ATR(g_atrLocHandle);
   double atrEntry = ATR(g_atrEntryHandle);
   if(atrLoc <= 0 || atrEntry <= 0) return;

   // ---------- STAGE 1: bias, re-evaluated each bias bar ----------
   if(NewBar(InpBiasTF, g_lastBiasBar))
     {
      int b = DetermineBias();
      c_biasBars++;
      if(b > 0) c_biasBull++; else if(b < 0) c_biasBear++; else c_biasNeutral++;

      if(b != g_bias)
        {
         if(g_state == ST_LOCATION) c_locationBiasFlip++;
         if(g_state == ST_CONFIRM)  c_confirmBiasFlip++;
         g_bias = b;
         g_state = (b == 0) ? ST_BIAS : ST_LOCATION;
         g_locationWait = 0;
         g_locKind = "";
         if(b != 0 && ArmLocation(b, atrLoc))
           {
            c_locationArmed++;
            if(InpLogEveryStage)
               PrintFormat("STAGE1 BIAS=%s -> STAGE2 location armed: %s [%.2f-%.2f]",
                           b > 0 ? "BUY" : "SELL", g_locKind, g_locLo, g_locHi);
           }
         else if(b != 0)
            g_state = ST_BIAS;
        }
     }

   if(g_bias == 0 || g_state == ST_MANAGE) return;

   // ---------- STAGE 2: wait for price to reach the location ----------
   if(g_state == ST_LOCATION && NewBar(InpLocationTF, g_lastLocBar))
     {
      g_locationWait++;
      if(g_locationWait > InpMaxLocationWait)
        {
         c_locationTimeout++;
         g_state = ST_BIAS;
         return;
        }
     }

   if(g_state == ST_LOCATION && NewBar(InpEntryTF, g_lastEntryBar))
     {
      if(PriceAtLocation(atrEntry))
        {
         c_locationReached++;
         g_confirmWait = 0;
         g_state = ST_CONFIRM;
         if(InpLogEveryStage)
            PrintFormat("STAGE2 reached %s -> STAGE3 awaiting confirmation", g_locKind);
        }
      return;
     }

   // ---------- STAGE 3: confirmation, then execute ----------
   if(g_state == ST_CONFIRM && NewBar(InpEntryTF, g_lastEntryBar))
     {
      g_confirmWait++;
      c_confirmTried++;
      if(g_confirmWait > InpMaxConfirmWait)
        {
         c_confirmTimeout++;
         g_state = ST_BIAS;
         return;
        }

      string cname = Confirmation(g_bias, atrEntry);
      if(cname != "")
        {
         c_confirmHit++;
         if(InpLogEveryStage) PrintFormat("STAGE3 confirmed: %s -> STAGE4 execute", cname);
         Execute(g_bias, cname, atrEntry);
         g_state = ST_BIAS;      // sequence complete; management takes over
        }
     }
  }
//+------------------------------------------------------------------+
