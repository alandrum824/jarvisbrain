//+------------------------------------------------------------------+
//|                                                  TWI Gold ORB.mq5 |
//|          Open Range Breakout Expert Advisor for XAU/USD (MT5)     |
//+------------------------------------------------------------------+
//
//  ORIGIN
//  ------
//  Faithful single-file reimplementation of the GOLD_ORB strategy by
//  Ulysses O. Andulte (https://github.com/yulz008/GOLD_ORB, 2022).
//  The original is spread over ten custom includes plus a vendored copy
//  of the MQL5 Math library, and does not compile on current MT5 builds.
//  This build reproduces the strategy exactly, in one file, with only
//  the stock Trade library as a dependency.
//
//  STRATEGY (H1, XAU/USD)
//  ----------------------
//  1. The trading day begins at InpStartHour server time (default 01:00).
//     At that bar all state resets.
//  2. The FIRST candle of the day defines the opening range:
//        resistance = that candle's high   (or its body high if the upper
//                     wick exceeds InpLongWickPoints - a long wick is
//                     treated as noise and excluded from the range)
//        support    = that candle's low    (same rule on the lower wick)
//  3. On each following candle the range may EXTEND. A new high only
//     counts if BOTH the wick high AND the body high improve by more than
//     InpMinRangeUpdate. Any extension RESETS the consolidation counter.
//  4. The range becomes FINAL once it has survived InpCandleComposition
//     candles without extension (default 3). Only then can it be traded.
//  5. Entry: a candle CLOSES beyond the final range.
//        BUY  - bullish candle whose body high closes above range high
//        SELL - bearish candle whose body low closes below range low
//  6. Fixed stop and target in points (default SL 400 / TP 1200), with an
//     optional wide trailing stop.
//  7. At most one long and one short per day (InpMaxTradePerDay = 2), or
//     a single trade per day (= 1).
//
//  NON-REPAINTING
//  --------------
//  Every decision reads bar index 1 - the fully closed previous candle -
//  and is evaluated once per bar open. Nothing is read from the forming
//  candle, so no signal can change after it is generated.
//
//  DEVIATIONS FROM THE ORIGINAL  (all deliberate, all listed)
//  ----------------------------------------------------------
//  D1  Equity-drawdown halt. The original reads:
//          if(dd < -MaxEquityDrawdownPercent)
//             printf(...);
//             execute_trade = false;
//      Missing braces mean execute_trade is cleared UNCONDITIONALLY on
//      every tick whenever MaxEquityDrawdownPercent != 0. With the code
//      default of 10 the EA never places a real trade - only virtual ones.
//      (The shipped default_input.set sets it to 0.0, which sidesteps the
//      bug rather than fixing it.) Here the halt is properly scoped.
//  D2  Position sizing. The original's VerifyVolume() raises any volume
//      below the broker minimum UP to the minimum, silently over-risking,
//      and uses MathRound, which can round risk above budget. This build
//      sizes from OrderCalcProfit(), rounds DOWN only, and SKIPS the trade
//      when the risk budget cannot buy one minimum lot (unless
//      InpAllowMinLotWhenTooSmall is enabled).
//  D3  Trade-per-day cap. The original sets its direction flags only when
//      trades_per_day is exactly 1 or 2; at 3 or more no flag is ever set
//      and entries become unlimited. Here the cap is always enforced.
//  D4  Trailing parameters (700 / 100 / 10) were hardcoded; now inputs.
//  D5  The long-wick threshold (500 points) and the minimum range-update
//      distance (0.1) were hardcoded; now inputs.
//  D6  Chart object names were fixed strings that collided across days;
//      objects here are uniquely named and optional.
//  D7  Distances are expressed in QUOTE CURRENCY, not raw broker points.
//      The original's 400 / 1200 assume a 2-digit gold feed (point = 0.01)
//      and mean $4.00 / $12.00. On a 3-digit feed (point = 0.001) the same
//      numbers silently mean $0.40 / $1.20 - a stop narrower than the
//      spread, which then inflates risk-based position size by 10x.
//      Measured: a 19-month run on a 3-digit feed produced 742 signals and
//      738 margin rejections, zero live trades. Init now prints the
//      resolved geometry in both units, refuses to start if the stop is
//      below the broker minimum, and refuses individual entries whose stop
//      is inside InpMinStopSpreadMult x spread.
//      InpDistanceUnit = UNIT_POINTS restores raw-point behaviour.
//
//  VIRTUAL BOOK
//  ------------
//  As in the original, every signal is also recorded in a virtual book
//  that keeps running even when real trading is halted. The loss-streak
//  and equity-slope modules read that book, so the EA can recognise a
//  recovery and resume live trading.
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property description "GOLD_ORB (Andulte) reimplemented: H1 opening range breakout for XAU/USD"

#include <Trade\Trade.mqh>

//==================================================================
//  DISTANCE UNITS
//==================================================================
//  The original EA expressed every distance in raw broker points and
//  was written against a 2-digit gold feed (point = 0.01), so its
//  "400" meant $4.00. On a 3-digit feed (point = 0.001) that same 400
//  silently means $0.40 - a stop narrower than the spread, which then
//  inflates risk-based position size by 10x. See deviation D7.
//
//  Distances are therefore expressed in QUOTE CURRENCY by default,
//  which means the same thing on every broker. UNIT_POINTS restores
//  the original raw-point behaviour for fidelity testing.
//------------------------------------------------------------------
enum ENUM_DIST_UNIT
  {
   UNIT_PRICE  = 0,   // Quote currency (dollars for gold) - broker independent
   UNIT_POINTS = 1    // Raw broker points - meaning depends on this feed's digits
  };

//==================================================================
//  INPUTS
//==================================================================
input group "=== Session ==="
input int    InpStartHour              = 1;      // Start of trading day (server hour)
input bool   InpWarnIfNotH1            = true;   // Warn when not attached to H1

input group "=== Distance units ==="
input ENUM_DIST_UNIT InpDistanceUnit   = UNIT_PRICE; // How every distance below is interpreted
input double InpMinStopSpreadMult      = 2.0;    // Refuse entry if stop is under this multiple of spread (0 = off)

input group "=== Trade management ==="
input double InpTakeProfit             = 12.00;  // Take profit distance
input double InpStopLoss               = 4.00;   // Stop loss distance
input int    InpMaxTradePerDay         = 2;      // Max trades per day (1 = one; 2 = one long + one short)
input bool   InpLongPosition           = true;   // Allow long positions
input bool   InpShortPosition          = true;   // Allow short positions

input group "=== Range construction ==="
input int    InpCandleComposition      = 3;      // Candles the range must survive before it is tradable
input double InpLongWickDist           = 5.00;   // Wick longer than this is excluded from the range
input double InpMinRangeUpdate         = 0.1;    // Minimum price improvement to count as a range extension (always price)

input group "=== Trailing stop ==="
input bool   InpEnableTrail            = true;   // Enable trailing stop
input double InpTrailDist              = 7.00;   // Trail distance behind price
input double InpTrailMinProfit         = 1.00;   // Profit needed before the trail arms
input double InpTrailStep              = 0.10;   // Minimum improvement before modifying

input group "=== Risk management ==="
input double InpMaxEquityDrawdownPct   = 10.0;   // Halt live trading at this drawdown from peak balance (0 = off)
input double InpMaxRiskPerTradePct     = 1.0;    // Risk per trade (% of balance; 0 = use fixed volume)
input double InpFixedVolume            = 0.10;   // Fixed volume when risk sizing is off
input double InpMaxVolume              = 10.0;   // Hard cap on any single position
input bool   InpAllowMinLotWhenTooSmall= false;  // Trade the broker minimum when risk budget is too small
input double InpMaxMarginPct           = 30.0;   // Max % of free margin one order may consume

input group "=== Advanced equity monitoring (virtual book) ==="
input bool   InpSlopeDetection         = false;  // Resume trading when the virtual equity slope turns up
input int    InpLossStreakCount        = 0;      // Halt after this many consecutive virtual losses (0 = off)
input int    InpSlopeLookback          = 12;     // Virtual deals used for the slope check

input group "=== Execution ==="
input long   InpMagic                  = 20260904;// Magic number
input int    InpSlippagePoints         = 50;     // Max deviation (points)
input double InpMaxSpreadDist          = 5.00;   // Max spread allowed to enter

input group "=== Diagnostics ==="
input bool   InpDrawRange              = true;   // Draw the opening range on the chart
input bool   InpVerboseLog             = true;   // Log range construction and signals
input bool   InpPrintSummary           = true;   // Print summary at deinit

//==================================================================
//  TYPES
//==================================================================
struct CandleInfo
  {
   double bodyHigh;
   double bodyLow;
   double wickHigh;
   double wickLow;
   bool   bullish;
  };

struct VirtualPosition
  {
   int      dir;          // +1 long, -1 short
   double   openPrice;
   double   sl;
   double   tp;
   double   volume;
   datetime openTime;
  };

struct VirtualDeal
  {
   double   balance;      // running virtual balance after this deal
   bool     win;
   datetime time;
  };

//==================================================================
//  GLOBALS
//==================================================================
CTrade g_trade;

// range state ------------------------------------------------------
CandleInfo g_range;
CandleInfo g_prev;
int        g_counterResistance = 0;
int        g_counterSupport    = 0;
bool       g_resetResistance   = false;
bool       g_resetSupport      = false;

// day state --------------------------------------------------------
bool     g_firstCandle       = true;
bool     g_newTradingDay     = false;
bool     g_tradeToday        = false;
bool     g_longFlag          = false;
bool     g_shortFlag         = false;
int      g_tradesToday       = 0;
datetime g_lastBarTime       = 0;
int      g_dayIndex          = 0;

// risk state -------------------------------------------------------
bool   g_executeTrade  = true;
double g_peakBalance   = 0.0;
double g_startBalance  = 0.0;

// virtual book -----------------------------------------------------
VirtualPosition g_vpos[];
VirtualDeal     g_vdeals[];
double          g_vBalance = 0.0;

// broker specs -----------------------------------------------------
double g_point   = 0.0;
int    g_digits  = 0;
double g_volMin  = 0.0;
double g_volMax  = 0.0;
double g_volStep = 0.0;
int    g_stopLvl = 0;

// resolved geometry, all in PRICE, computed once at init -----------
double g_slDist        = 0.0;
double g_tpDist        = 0.0;
double g_trailDist     = 0.0;
double g_trailArm      = 0.0;
double g_trailStep     = 0.0;
double g_longWickDist  = 0.0;
double g_maxSpreadDist = 0.0;

// counters ---------------------------------------------------------
long k_bars = 0, k_rangeSet = 0, k_rangeExtended = 0;
long k_signalsLong = 0, k_signalsShort = 0;
long k_entries = 0, k_rejHalt = 0, k_rejSpread = 0, k_rejLot = 0, k_rejMargin = 0;
long k_rejStopTooTight = 0;
long k_vTrades = 0, k_vWins = 0, k_vLosses = 0;

//==================================================================
//  HELPERS
//==================================================================
void Log(string s) { if(InpVerboseLog) Print(s); }

double SpreadPrice()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }

double SpreadPoints()
  {
   if(g_point <= 0.0) return 0.0;
   return SpreadPrice() / g_point;
  }

//--- resolve an input distance into PRICE, whatever unit was chosen
double ToPrice(double v)
  {
   if(InpDistanceUnit == UNIT_PRICE) return v;
   return v * g_point;
  }

//--- round DOWN to the broker volume step; 0 means "not tradable" --
double NormalizeLotDown(double lots)
  {
   if(g_volStep <= 0.0) return 0.0;
   double v = MathFloor(lots / g_volStep + 1e-8) * g_volStep;
   v = NormalizeDouble(v, 8);
   if(v > g_volMax) v = g_volMax;
   if(v < g_volMin) return 0.0;
   return v;
  }

double MinStopDistance()
  {
   int lvl = g_stopLvl;
   if(lvl <= 0) lvl = 10;
   return lvl * g_point;
  }

//==================================================================
//  CANDLE READ  (bar 1 only - fully closed, cannot repaint)
//==================================================================
bool ReadPreviousCandle(CandleInfo &c)
  {
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, r) != 1)
      return false;

   if(r[0].close > r[0].open)          // bullish
     {
      c.bodyHigh = r[0].close;
      c.bodyLow  = r[0].open;
      c.bullish  = true;
     }
   else                                 // bearish
     {
      c.bodyHigh = r[0].open;
      c.bodyLow  = r[0].close;
      c.bullish  = false;
     }
   c.wickHigh = r[0].high;
   c.wickLow  = r[0].low;
   return true;
  }

//==================================================================
//  RANGE CONSTRUCTION
//==================================================================
void ResetDay()
  {
   g_range.wickHigh = 0.0;
   g_range.wickLow  = 0.0;
   g_range.bodyHigh = 0.0;
   g_range.bodyLow  = 0.0;

   g_counterResistance = 0;
   g_counterSupport    = 0;
   g_resetResistance   = false;
   g_resetSupport      = false;

   g_longFlag    = false;
   g_shortFlag   = false;
   g_tradesToday = 0;
   g_tradeToday  = true;
   g_dayIndex++;
  }

//--- a wick longer than the threshold is treated as noise ----------
bool WickIsLong(double bodyEdge, double wickEdge)
  {
   if(g_longWickDist <= 0.0) return false;
   return (MathAbs(bodyEdge - wickEdge) > g_longWickDist);
  }

//--- the first candle of the day defines the range -----------------
void SetFirstCandleRange()
  {
   if(WickIsLong(g_prev.bodyHigh, g_prev.wickHigh))
     {
      g_range.wickHigh = g_prev.bodyHigh;      // exclude the long upper wick
      g_range.bodyHigh = g_prev.bodyHigh;
     }
   else
     {
      g_range.wickHigh = g_prev.wickHigh;
      g_range.bodyHigh = g_prev.bodyHigh;
     }

   if(WickIsLong(g_prev.bodyLow, g_prev.wickLow))
     {
      g_range.wickLow = g_prev.bodyLow;        // exclude the long lower wick
      g_range.bodyLow = g_prev.bodyLow;
     }
   else
     {
      g_range.wickLow = g_prev.wickLow;
      g_range.bodyLow = g_prev.bodyLow;
     }

   k_rangeSet++;
   Log(StringFormat("ORB_RANGE_SET | day=%d high=%.*f low=%.*f width=%.0f pts",
                    g_dayIndex, g_digits, g_range.wickHigh, g_digits, g_range.wickLow,
                    (g_range.wickHigh - g_range.wickLow) / g_point));
   DrawRange();
  }

//--- later candles may extend the range, which restarts the count --
void UpdateRange()
  {
   bool haveRange = (g_range.wickHigh > 0.0 && g_range.wickLow > 0.0);
   if(!haveRange) return;

   //--- resistance side -------------------------------------------
   if(g_counterResistance > 0 && g_counterResistance <= InpCandleComposition)
     {
      if(g_prev.wickHigh > g_range.wickHigh &&
         MathAbs(g_prev.wickHigh - g_range.wickHigh) > InpMinRangeUpdate &&
         g_prev.bodyHigh > g_range.bodyHigh &&
         MathAbs(g_prev.bodyHigh - g_range.bodyHigh) > InpMinRangeUpdate)
        {
         if(WickIsLong(g_prev.bodyHigh, g_prev.wickHigh))
           {
            g_range.wickHigh = g_prev.bodyHigh;
            g_range.bodyHigh = g_prev.bodyHigh;
           }
         else
           {
            g_range.wickHigh = g_prev.wickHigh;
            g_range.bodyHigh = g_prev.bodyHigh;
           }
         g_counterResistance = 1;
         g_resetResistance   = true;
         k_rangeExtended++;
         Log(StringFormat("ORB_RANGE_EXTEND | side=HIGH new=%.*f", g_digits, g_range.wickHigh));
         DrawRange();
        }
     }

   //--- support side ----------------------------------------------
   if(g_counterSupport > 0 && g_counterSupport <= InpCandleComposition)
     {
      if(g_prev.wickLow < g_range.wickLow &&
         MathAbs(g_prev.wickLow - g_range.wickLow) > InpMinRangeUpdate &&
         g_prev.bodyLow < g_range.bodyLow &&
         MathAbs(g_prev.bodyLow - g_range.bodyLow) > InpMinRangeUpdate)
        {
         if(WickIsLong(g_prev.bodyLow, g_prev.wickLow))
           {
            g_range.wickLow = g_prev.bodyLow;
            g_range.bodyLow = g_prev.bodyLow;
           }
         else
           {
            g_range.wickLow = g_prev.wickLow;
            g_range.bodyLow = g_prev.bodyLow;
           }
         g_counterSupport = 1;
         g_resetSupport   = true;
         k_rangeExtended++;
         Log(StringFormat("ORB_RANGE_EXTEND | side=LOW new=%.*f", g_digits, g_range.wickLow));
         DrawRange();
        }
     }
  }

//--- counters advance once per candle unless the range just moved --
void UpdateCounters()
  {
   if(g_longFlag && g_shortFlag)
      g_tradeToday = false;

   if(g_resetResistance) { g_counterResistance = 1; g_resetResistance = false; }
   else                    g_counterResistance++;

   if(g_resetSupport)    { g_counterSupport = 1;    g_resetSupport = false; }
   else                    g_counterSupport++;
  }

//==================================================================
//  SIGNAL
//==================================================================
//  Returns +1 buy, -1 sell, 0 none. A signal requires the range to
//  have been final for more than InpCandleComposition candles and the
//  previous candle to have CLOSED beyond it.
//------------------------------------------------------------------
int GetSignal()
  {
   if(!g_tradeToday) return 0;
   if(g_range.wickHigh <= 0.0 || g_range.wickLow <= 0.0) return 0;

   //--- long -------------------------------------------------------
   if(g_counterResistance > InpCandleComposition && g_prev.bullish)
     {
      if(g_prev.bodyHigh > g_range.wickHigh)
        {
         if(!g_longFlag)
           {
            g_longFlag = true;
            if(InpMaxTradePerDay == 1) g_tradeToday = false;
            k_signalsLong++;
            return 1;
           }
        }
     }

   //--- short ------------------------------------------------------
   if(g_counterSupport > InpCandleComposition && !g_prev.bullish)
     {
      if(g_prev.bodyLow < g_range.wickLow)
        {
         if(!g_shortFlag)
           {
            g_shortFlag = true;
            if(InpMaxTradePerDay == 1) g_tradeToday = false;
            k_signalsShort++;
            return -1;
           }
        }
     }

   return 0;
  }

//==================================================================
//  SIZING  (D2 - corrected)
//==================================================================
double ComputeVolume(double entry, double sl, int dir)
  {
   if(InpMaxRiskPerTradePct <= 0.0 || g_slDist <= 0.0)
     {
      double fixed = NormalizeLotDown(MathMin(InpFixedVolume, InpMaxVolume));
      if(fixed <= 0.0) Log("SIZING | fixed volume below broker minimum");
      return fixed;
     }

   double budget = AccountInfoDouble(ACCOUNT_BALANCE) * (InpMaxRiskPerTradePct / 100.0);
   if(budget <= 0.0) return 0.0;

   double lossPerMin = 0.0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(t, _Symbol, g_volMin, entry, sl, lossPerMin))
     {
      Log("SIZING | OrderCalcProfit failed - refusing trade");
      return 0.0;
     }
   lossPerMin = MathAbs(lossPerMin);
   if(lossPerMin <= 0.0) return 0.0;

   double raw  = g_volMin * (budget / lossPerMin);
   raw = MathMin(raw, InpMaxVolume);
   double lots = NormalizeLotDown(raw);

   if(lots <= 0.0)
     {
      if(InpAllowMinLotWhenTooSmall)
        {
         Log(StringFormat("SIZING | budget %.2f below min-lot risk %.2f - using minimum lot (OVER-RISK)",
                          budget, lossPerMin));
         return g_volMin;
        }
      k_rejLot++;
      Log(StringFormat("SIZING | budget %.2f below min-lot risk %.2f - skipping trade",
                       budget, lossPerMin));
      return 0.0;
     }

   // never let step rounding push actual risk above budget
   double actual = 0.0;
   if(!OrderCalcProfit(t, _Symbol, lots, entry, sl, actual))
      return 0.0;
   actual = MathAbs(actual);
   while(lots > g_volMin && actual > budget)
     {
      lots = NormalizeLotDown(lots - g_volStep);
      if(lots <= 0.0) return 0.0;
      if(!OrderCalcProfit(t, _Symbol, lots, entry, sl, actual))
         return 0.0;
      actual = MathAbs(actual);
     }

   Log(StringFormat("SIZING | budget=%.2f lots=%.2f actualRisk=%.2f", budget, lots, actual));
   return lots;
  }

bool MarginOK(int dir, double lots, double price)
  {
   double need = 0.0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(t, _Symbol, lots, price, need))
      return false;
   double allowed = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (InpMaxMarginPct / 100.0);
   if(need > allowed)
     {
      k_rejMargin++;
      Log(StringFormat("MARGIN_REJECT | need=%.2f allowed=%.2f", need, allowed));
      return false;
     }
   return true;
  }

//==================================================================
//  VIRTUAL BOOK
//==================================================================
void VirtualOpen(int dir, double volume, double price, double sl, double tp)
  {
   int n = ArraySize(g_vpos);
   ArrayResize(g_vpos, n + 1);
   g_vpos[n].dir       = dir;
   g_vpos[n].openPrice = price;
   g_vpos[n].sl        = sl;
   g_vpos[n].tp        = tp;
   g_vpos[n].volume    = volume;
   g_vpos[n].openTime  = TimeCurrent();
   k_vTrades++;
  }

void VirtualClose(int idx, bool win)
  {
   double profit = 0.0;
   double closePrice = win ? g_vpos[idx].tp : g_vpos[idx].sl;
   ENUM_ORDER_TYPE t = (g_vpos[idx].dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(t, _Symbol, g_vpos[idx].volume, g_vpos[idx].openPrice, closePrice, profit))
      profit = 0.0;   // virtual book only - never blocks live logic

   g_vBalance += profit;

   int n = ArraySize(g_vdeals);
   ArrayResize(g_vdeals, n + 1);
   g_vdeals[n].balance = g_vBalance;
   g_vdeals[n].win     = win;
   g_vdeals[n].time    = TimeCurrent();

   if(win) k_vWins++; else k_vLosses++;

   ArrayRemove(g_vpos, idx, 1);
  }

void MonitorVirtual()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = ArraySize(g_vpos) - 1; i >= 0; i--)
     {
      if(g_vpos[i].dir > 0)
        {
         if(g_vpos[i].tp > 0.0 && bid >= g_vpos[i].tp) { VirtualClose(i, true);  continue; }
         if(g_vpos[i].sl > 0.0 && bid <= g_vpos[i].sl) { VirtualClose(i, false); continue; }
        }
      else
        {
         if(g_vpos[i].tp > 0.0 && ask <= g_vpos[i].tp) { VirtualClose(i, true);  continue; }
         if(g_vpos[i].sl > 0.0 && ask >= g_vpos[i].sl) { VirtualClose(i, false); continue; }
        }
     }
  }

//--- last N virtual trades all losers? ----------------------------
bool VirtualLossStreak(int streak)
  {
   if(streak <= 0) return false;
   int n = ArraySize(g_vdeals);
   if(n < streak) return false;
   for(int i = n - 1; i >= n - streak; i--)
      if(g_vdeals[i].win) return false;
   return true;
  }

//--- virtual balance higher than it was N deals ago? --------------
bool VirtualSlopeUp(int lookback)
  {
   int n = ArraySize(g_vdeals);
   if(n <= lookback) return false;
   return (g_vdeals[n - 1].balance - g_vdeals[n - 1 - lookback].balance) > 0.0;
  }

//==================================================================
//  RISK MODULE  (D1 - corrected scoping)
//==================================================================
void RiskModule()
  {
   MonitorVirtual();

   //--- balance drawdown from peak --------------------------------
   if(InpMaxEquityDrawdownPct != 0.0)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal > g_peakBalance) g_peakBalance = bal;

      if(g_peakBalance > 0.0)
        {
         double dd = 100.0 * (bal - g_peakBalance) / g_peakBalance;
         if(dd < -InpMaxEquityDrawdownPct)          // braces are the fix
           {
            if(g_executeTrade)
               PrintFormat("HALT | balance drawdown %.2f%% exceeds %.2f%% (peak %.2f, now %.2f)",
                           dd, InpMaxEquityDrawdownPct, g_peakBalance, bal);
            g_executeTrade = false;
           }
        }
     }

   //--- loss streak / recovery slope ------------------------------
   if(InpSlopeDetection || InpLossStreakCount != 0)
     {
      bool streak = VirtualLossStreak(InpLossStreakCount);
      bool slopeUp = VirtualSlopeUp(InpSlopeLookback);

      if(streak)
        {
         if(g_executeTrade) Log("HALT | virtual loss streak detected");
         g_executeTrade = false;
        }
      if(slopeUp && !streak)
        {
         if(!g_executeTrade) Log("RESUME | virtual equity slope recovering");
         g_executeTrade = true;
        }
     }
  }

//==================================================================
//  TRAILING STOP
//==================================================================
void TrailModule()
  {
   if(!InpEnableTrail || g_trailDist <= 0.0) return;

   double stepPrice = MathMax(g_trailStep, 10 * g_point);   // original floored the step at 10 points
   double trailDist = g_trailDist;
   double minProfit = g_trailArm;
   double minDist   = MinStopDistance();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = NormalizeDouble(PositionGetDouble(POSITION_SL), g_digits);
      double curTP  = PositionGetDouble(POSITION_TP);

      double newSL, profit;
      if(isBuy)
        {
         newSL  = NormalizeDouble(bid - trailDist, g_digits);
         profit = bid - open;
         if(!(newSL > curSL + stepPrice && profit >= minProfit)) continue;
         if(bid - newSL < minDist) continue;
        }
      else
        {
         newSL  = NormalizeDouble(ask + trailDist, g_digits);
         profit = open - ask;
         if(!(curSL > 0.0 && newSL < curSL - stepPrice) || !(profit >= minProfit)) continue;
         if(newSL - ask < minDist) continue;
        }

      if(g_trade.PositionModify(ticket, newSL, curTP))
         Log(StringFormat("TRAIL | ticket=%I64u %s old=%.*f new=%.*f profit=%.0f pts",
                          ticket, (isBuy ? "BUY" : "SELL"),
                          g_digits, curSL, g_digits, newSL, profit / g_point));
     }
  }

//==================================================================
//  EXECUTION
//==================================================================
void ExecuteSignal(int dir)
  {
   if(dir > 0 && !InpLongPosition)  return;
   if(dir < 0 && !InpShortPosition) return;

   if(InpMaxTradePerDay > 0 && g_tradesToday >= InpMaxTradePerDay)   // D3
     {
      Log("SKIP | daily trade cap reached");
      return;
     }

   // a stop inside the spread is not a stop - refuse rather than size into it
   if(InpMinStopSpreadMult > 0.0)
     {
      double spread = SpreadPrice();
      if(spread > 0.0 && g_slDist < spread * InpMinStopSpreadMult)
        {
         k_rejStopTooTight++;
         Log(StringFormat("STOP_TOO_TIGHT | sl=%.*f spread=%.*f required=%.*f - refusing entry",
                          g_digits, g_slDist, g_digits, spread,
                          g_digits, spread * InpMinStopSpreadMult));
         return;
        }
     }

   double price = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (dir > 0) ? price - g_slDist : price + g_slDist;
   double tp = (dir > 0) ? price + g_tpDist : price - g_tpDist;
   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);

   double volume = ComputeVolume(price, sl, dir);
   if(volume <= 0.0) return;

   // the virtual book records every signal, halted or not
   VirtualOpen(dir, volume, price, sl, tp);

   if(!g_executeTrade)
     {
      k_rejHalt++;
      Log("SKIP | live trading halted by risk module - virtual only");
      return;
     }

   if(SpreadPrice() > g_maxSpreadDist)
     {
      k_rejSpread++;
      Log(StringFormat("SPREAD_REJECT | spread=%.*f limit=%.*f (%.0f pts)",
                       g_digits, SpreadPrice(), g_digits, g_maxSpreadDist, SpreadPoints()));
      return;
     }

   if(!MarginOK(dir, volume, price)) return;

   // respect the broker's minimum stop distance
   double minDist = MinStopDistance();
   if(dir > 0)
     {
      if(price - sl < minDist) sl = NormalizeDouble(price - minDist, g_digits);
      if(tp - price < minDist) tp = NormalizeDouble(price + minDist, g_digits);
     }
   else
     {
      if(sl - price < minDist) sl = NormalizeDouble(price + minDist, g_digits);
      if(price - tp < minDist) tp = NormalizeDouble(price - minDist, g_digits);
     }

   bool ok = (dir > 0) ? g_trade.Buy(volume, _Symbol, 0.0, sl, tp, "ORB")
                       : g_trade.Sell(volume, _Symbol, 0.0, sl, tp, "ORB");
   if(!ok)
     {
      PrintFormat("SEND_FAIL | %s vol=%.2f ret=%d %s",
                  (dir > 0 ? "BUY" : "SELL"), volume,
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return;
     }

   g_tradesToday++;
   k_entries++;
   PrintFormat("ORB_ENTRY | %s vol=%.2f fill=%.*f sl=%.*f tp=%.*f rangeHigh=%.*f rangeLow=%.*f",
               (dir > 0 ? "BUY" : "SELL"), volume, g_digits, g_trade.ResultPrice(),
               g_digits, sl, g_digits, tp,
               g_digits, g_range.wickHigh, g_digits, g_range.wickLow);
  }

//==================================================================
//  CHART OBJECTS  (D6)
//==================================================================
void DrawRange()
  {
   if(!InpDrawRange) return;
   string hi = StringFormat("ORB_HI_%d", g_dayIndex);
   string lo = StringFormat("ORB_LO_%d", g_dayIndex);

   if(ObjectFind(0, hi) < 0) ObjectCreate(0, hi, OBJ_HLINE, 0, 0, g_range.wickHigh);
   else                      ObjectMove(0, hi, 0, 0, g_range.wickHigh);
   ObjectSetInteger(0, hi, OBJPROP_COLOR, clrTomato);

   if(ObjectFind(0, lo) < 0) ObjectCreate(0, lo, OBJ_HLINE, 0, 0, g_range.wickLow);
   else                      ObjectMove(0, lo, 0, 0, g_range.wickLow);
   ObjectSetInteger(0, lo, OBJPROP_COLOR, clrDodgerBlue);
  }

//==================================================================
//  LIFECYCLE
//==================================================================
int OnInit()
  {
   g_point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_stopLvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   if(g_point <= 0.0 || g_volStep <= 0.0 || g_volMin <= 0.0)
     {
      Print("FATAL: unusable symbol specs for ", _Symbol);
      return INIT_FAILED;
     }
   if(InpCandleComposition < 1)
     {
      Print("FATAL: InpCandleComposition must be at least 1");
      return INIT_FAILED;
     }
   if(InpStartHour < 0 || InpStartHour > 23)
     {
      Print("FATAL: InpStartHour must be 0-23");
      return INIT_FAILED;
     }

   //--- resolve every distance to PRICE once, here, and never again
   g_slDist        = ToPrice(InpStopLoss);
   g_tpDist        = ToPrice(InpTakeProfit);
   g_trailDist     = ToPrice(InpTrailDist);
   g_trailArm      = ToPrice(InpTrailMinProfit);
   g_trailStep     = ToPrice(InpTrailStep);
   g_longWickDist  = ToPrice(InpLongWickDist);
   g_maxSpreadDist = ToPrice(InpMaxSpreadDist);

   if(g_slDist <= 0.0 || g_tpDist <= 0.0)
     {
      Print("FATAL: stop loss and take profit distances must both be positive");
      return INIT_FAILED;
     }

   double brokerMin = MinStopDistance();
   if(g_slDist < brokerMin)
     {
      PrintFormat("FATAL: stop distance %.*f is below the broker minimum %.*f. "
                  "Check InpDistanceUnit - on this feed 1 point = %.*f",
                  g_digits, g_slDist, g_digits, brokerMin, g_digits, g_point);
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakBalance  = g_startBalance;
   g_vBalance     = 0.0;
   g_executeTrade = true;
   g_firstCandle  = true;

   if(InpWarnIfNotH1 && Period() != PERIOD_H1)
      Print("WARNING: GOLD_ORB is designed for H1. Current timeframe is ",
            EnumToString((ENUM_TIMEFRAMES)Period()),
            " - the opening range will be built from that timeframe instead.");

   PrintFormat("TWI Gold ORB init | %s %s | startHour=%d composition=%d maxTrades/day=%d",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()),
               InpStartHour, InpCandleComposition, InpMaxTradePerDay);
   PrintFormat("Broker | digits=%d point=%.*f volMin=%.2f volStep=%.2f stopLevel=%d leverage=1:%d",
               g_digits, g_digits, g_point, g_volMin, g_volStep, g_stopLvl,
               (int)AccountInfoInteger(ACCOUNT_LEVERAGE));

   // resolved geometry printed in BOTH units - this is what makes a
   // unit mismatch impossible to miss again
   PrintFormat("GEOMETRY | unit=%s | SL=%.*f (%.0f pts) TP=%.*f (%.0f pts) RR=%.2f",
               (InpDistanceUnit == UNIT_PRICE ? "PRICE" : "POINTS"),
               g_digits, g_slDist, g_slDist / g_point,
               g_digits, g_tpDist, g_tpDist / g_point,
               g_tpDist / g_slDist);
   PrintFormat("GEOMETRY | trail=%.*f (%.0f pts) arm=%.*f step=%.*f longWick=%.*f maxSpread=%.*f",
               g_digits, g_trailDist, g_trailDist / g_point,
               g_digits, g_trailArm, g_digits, g_trailStep,
               g_digits, g_longWickDist, g_digits, g_maxSpreadDist);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(InpDrawRange)
      ObjectsDeleteAll(0, "ORB_");

   if(!InpPrintSummary) return;
   Print("=== TWI GOLD ORB SUMMARY ===");
   PrintFormat("Bars evaluated: %I64d | ranges set: %I64d | range extensions: %I64d",
               k_bars, k_rangeSet, k_rangeExtended);
   PrintFormat("Signals: long %I64d | short %I64d", k_signalsLong, k_signalsShort);
   PrintFormat("Live entries: %I64d | halted (virtual only): %I64d", k_entries, k_rejHalt);
   PrintFormat("Rejected: spread %I64d | margin %I64d | lot too small %I64d | stop tighter than spread %I64d",
               k_rejSpread, k_rejMargin, k_rejLot, k_rejStopTooTight);
   PrintFormat("Virtual book: trades %I64d | wins %I64d | losses %I64d | virtual P/L %.2f",
               k_vTrades, k_vWins, k_vLosses, g_vBalance);
   PrintFormat("Balance: start %.2f | peak %.2f | now %.2f | live trading %s",
               g_startBalance, g_peakBalance, AccountInfoDouble(ACCOUNT_BALANCE),
               (g_executeTrade ? "ENABLED" : "HALTED"));
  }

void OnTick()
  {
   RiskModule();
   TrailModule();

   //--- one pass per new bar --------------------------------------
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == 0 || barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;
   k_bars++;

   if(!ReadPreviousCandle(g_prev)) return;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   //--- day sequencing (faithful to the original) ------------------
   if(t.hour == InpStartHour + 1)
      g_firstCandle = true;

   if(t.hour == InpStartHour && g_firstCandle)
     {
      ResetDay();
      g_firstCandle   = false;
      g_newTradingDay = true;
     }
   else if(g_newTradingDay)
     {
      SetFirstCandleRange();          // previous candle IS the first of the day
      g_newTradingDay = false;
      UpdateCounters();
     }
   else
     {
      UpdateRange();
      UpdateCounters();
     }

   int sig = GetSignal();
   if(sig != 0)
      ExecuteSignal(sig);
  }
//+------------------------------------------------------------------+
