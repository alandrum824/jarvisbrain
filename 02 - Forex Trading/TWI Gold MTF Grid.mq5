//+------------------------------------------------------------------+
//|                                            TWI Gold MTF Grid.mq5 |
//|                     Multi-timeframe XAU/USD Expert Advisor (MT5) |
//+------------------------------------------------------------------+
//
//  PURPOSE
//  -------
//  Trend-aligned, mean-reversion-timed entry engine for gold (XAU/USD),
//  with optional grid management of floating losses.
//
//  DECISION STACK (top-down; every stage must agree)
//  -------------------------------------------------
//    H4   Overall trend direction        EMA(fast/slow) + optional ADX strength
//    H1   Trend confirmation             EMA(fast/slow); must match H4 or NO TRADE
//    M30  Overbought / oversold state    RSI (+ optional Stochastic)
//    M15  Overbought / oversold state    RSI (+ optional Stochastic)
//         -> If M30 and M15 disagree, the EA PAUSES new entries.
//    M5   Execution trigger              Non-repainting candlestick patterns
//
//  NON-REPAINTING GUARANTEE
//  ------------------------
//  Every indicator value and every candle used for a decision is read from
//  CLOSED bars only (buffer shift >= 1). No indicator in this EA looks
//  forward, and no value used for a decision can change after it is read.
//  Decisions are evaluated once per closed M5 bar, never intrabar.
//
//  BROKER / ACCOUNT ADAPTATION
//  ---------------------------
//  Leverage, margin mode, contract size, tick value, volume min/max/step,
//  stop level, freeze level, digits and filling mode are all read from the
//  live symbol and account at init and applied at every order. Position size
//  is derived from real money risk via OrderCalcProfit(), and every send is
//  pre-checked with OrderCalcMargin() against free margin.
//
//  MONEY MANAGEMENT
//  ----------------
//    - Fixed lot, or percent-of-equity risk sizing (round DOWN only).
//    - Configurable SL / TP in points or ATR multiples.
//    - Trailing stop (fixed distance or ATR based), with activation threshold.
//    - Grid: fixed or flexible (ATR / progressive) spacing, capped position
//      count, optional lot multiplier, basket take-profit and basket stop.
//
//  RISK NOTICE
//  -----------
//  The grid module averages into losing positions. With InpGridLotMultiplier
//  above 1.0 it becomes a martingale and risk grows geometrically. The default
//  is 1.0 (flat adds) and InpBasketMaxLossPercent is an unconditional kill
//  switch on the whole basket. Raise the multiplier only deliberately.
//
//  Designed and tested against MetaTrader 5 build 5xxx+ / MQL5.
//+------------------------------------------------------------------+
#property copyright "TWI"
#property link      ""
#property version   "1.00"
#property description "Gold MTF (H4/H1/M30/M15/M5) trend + OB/OS + candlestick EA with optional grid"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,          // Fixed lot size
   LOT_RISK_PERCENT = 1    // Percent of equity risked per trade
  };

enum ENUM_DIST_MODE
  {
   DIST_POINTS = 0,        // Distance in points
   DIST_ATR = 1            // Distance as ATR multiple
  };

enum ENUM_GRID_SPACING
  {
   GRID_FIXED = 0,         // Fixed spacing (points)
   GRID_ATR = 1,           // Flexible spacing (ATR multiple)
   GRID_PROGRESSIVE = 2    // Progressive spacing (step * level)
  };

enum ENUM_TREND
  {
   TREND_NONE = 0,
   TREND_BULL = 1,
   TREND_BEAR = -1
  };

enum ENUM_OBOS
  {
   OBOS_NEUTRAL = 0,
   OBOS_OVERBOUGHT = 1,
   OBOS_OVERSOLD = -1
  };

//==================================================================
//  INPUTS
//==================================================================
input group "=== Timeframes (fixed by design, exposed for study) ==="
input ENUM_TIMEFRAMES  InpTrendTF          = PERIOD_H4;   // Overall trend timeframe
input ENUM_TIMEFRAMES  InpConfirmTF        = PERIOD_H1;   // Trend confirmation timeframe
input ENUM_TIMEFRAMES  InpOBOS1TF          = PERIOD_M30;  // Overbought/oversold TF #1
input ENUM_TIMEFRAMES  InpOBOS2TF          = PERIOD_M15;  // Overbought/oversold TF #2
input ENUM_TIMEFRAMES  InpEntryTF          = PERIOD_M5;   // Entry / execution timeframe

input group "=== Trend engine (H4 + H1) ==="
input int              InpEmaFast          = 21;          // EMA fast period
input int              InpEmaSlow          = 55;          // EMA slow period
input bool             InpUseADXFilter     = true;        // Require trend strength (ADX)
input int              InpADXPeriod        = 14;          // ADX period
input double           InpADXMinimum       = 18.0;        // Minimum ADX for a valid trend
input bool             InpRequireH4Slope   = true;        // Require H4 fast EMA to be sloping

input group "=== Gate switches (turn off to measure a gate's cost) ==="
input bool             InpGateTrendH4      = true;        // Enforce H4 trend gate
input bool             InpGateTrendH1      = true;        // Enforce H1 confirmation gate
input bool             InpGateOBOSAgree    = true;        // Enforce M30/M15 agreement gate
input bool             InpGatePattern      = true;        // Enforce M5 candlestick gate

input group "=== Overbought / oversold (M30 + M15) ==="
input int              InpRSIPeriod        = 14;          // RSI period
input double           InpRSIOverbought    = 65.0;        // RSI overbought level
input double           InpRSIOversold      = 35.0;        // RSI oversold level
input bool             InpUseStochastic    = true;        // Also require Stochastic agreement
input int              InpStochK           = 14;          // Stochastic %K
input int              InpStochD           = 3;           // Stochastic %D
input int              InpStochSlow        = 3;           // Stochastic slowing
input double           InpStochOverbought  = 75.0;        // Stochastic overbought level
input double           InpStochOversold    = 25.0;        // Stochastic oversold level
input bool             InpRequireCounterOBOS = true;      // true: buy only when oversold (pullback entry)
                                                          // false: buy only when overbought (momentum entry)

input group "=== M5 candlestick patterns (non-repainting, closed bars) ==="
input bool             InpPatEngulfing     = true;        // Engulfing
input bool             InpPatPinBar        = true;        // Pin bar (hammer / shooting star)
input bool             InpPatStar          = true;        // Morning star / evening star
input bool             InpPatPiercing      = true;        // Piercing line / dark cloud cover
input bool             InpPatInsideBreak   = true;        // Inside-bar breakout
input double           InpPatMinBodyATR    = 0.25;        // Minimum signal-bar range as ATR multiple
input double           InpPatWickRatio     = 0.60;        // Pin bar: wick share of total range
input double           InpPatBodyRatio     = 0.30;        // Pin bar: max body share of total range

input group "=== Stop loss / take profit ==="
input ENUM_DIST_MODE   InpSLMode           = DIST_ATR;    // Stop loss mode
input double           InpSLPoints         = 3000;        // Stop loss (points) if mode = points
input double           InpSLATR            = 1.5;         // Stop loss (ATR multiple) if mode = ATR
input ENUM_DIST_MODE   InpTPMode           = DIST_ATR;    // Take profit mode
input double           InpTPPoints         = 6000;        // Take profit (points) if mode = points
input double           InpTPATR            = 3.0;         // Take profit (ATR multiple) if mode = ATR
input int              InpATRPeriod        = 14;          // ATR period (entry timeframe)

input group "=== Trailing stop ==="
input bool             InpUseTrailing      = true;        // Enable trailing stop
input ENUM_DIST_MODE   InpTrailMode        = DIST_ATR;    // Trailing distance mode
input double           InpTrailStartPoints = 2000;        // Profit needed to arm trail (points)
input double           InpTrailStartATR    = 1.0;         // Profit needed to arm trail (ATR)
input double           InpTrailPoints      = 1500;        // Trailing distance (points)
input double           InpTrailATR         = 1.0;         // Trailing distance (ATR)
input double           InpTrailStepPoints  = 200;         // Minimum improvement before modifying
input bool             InpMoveToBreakeven  = true;        // Move to breakeven before trailing
input double           InpBEStartATR       = 0.8;         // Profit (ATR) that triggers breakeven
input double           InpBEOffsetPoints   = 100;         // Breakeven offset in points (locked profit)

input group "=== Position sizing ==="
input ENUM_LOT_MODE    InpLotMode          = LOT_RISK_PERCENT; // Sizing mode
input double           InpFixedLot         = 0.10;        // Fixed lot size
input double           InpRiskPercent      = 0.50;        // Risk per trade (% of equity)
input double           InpMaxLot           = 10.0;        // Hard cap on a single position
input double           InpMaxMarginPercent = 30.0;        // Max % of free margin any one order may consume

input group "=== Grid (management of floating losses) ==="
input bool             InpUseGrid          = true;        // Enable grid
input ENUM_GRID_SPACING InpGridSpacingMode = GRID_ATR;    // Grid spacing mode
input double           InpGridStepPoints   = 2500;        // Grid step (points) - fixed / progressive
input double           InpGridStepATR      = 1.0;         // Grid step (ATR multiple) - flexible
input int              InpMaxGridPositions = 5;           // Max simultaneous positions per direction
input double           InpGridLotMultiplier= 1.0;         // Lot multiplier per grid level (1.0 = flat)
input bool             InpGridNoIndividualSL = true;      // Grid on: no per-position SL, basket stop governs
input bool             InpUseBasketTP      = true;        // Close whole basket at a profit target
input double           InpBasketTPPercent  = 0.75;        // Basket TP as % of equity
input double           InpBasketMaxLossPercent = 5.0;     // HARD basket kill switch (% of equity)
input bool             InpGridRequireSignal= false;       // Require a fresh M5 signal for each grid add

input group "=== Execution / safety ==="
input long             InpMagic            = 20260904;    // Magic number
input int              InpSlippagePoints   = 50;          // Max deviation (points)
input double           InpMaxSpreadPoints  = 500;         // Max spread allowed to enter (points)
input double           InpDailyLossPercent = 5.0;         // Daily loss halt (% of start-of-day equity)
input double           InpMinEquityPercent = 50.0;        // Stop all trading below this % of start equity
input bool             InpOnePositionPerBar= true;        // At most one entry per closed M5 bar

input group "=== Diagnostics ==="
input bool             InpVerboseLog       = true;        // Log gate rejections and trade events
input bool             InpPrintSummary     = true;        // Print funnel summary at deinit

//==================================================================
//  GLOBALS
//==================================================================
CTrade         g_trade;
CPositionInfo  g_pos;

// indicator handles ------------------------------------------------
int  h_emaFastTrend = INVALID_HANDLE, h_emaSlowTrend = INVALID_HANDLE;
int  h_emaFastConf  = INVALID_HANDLE, h_emaSlowConf  = INVALID_HANDLE;
int  h_adxTrend     = INVALID_HANDLE;
int  h_rsiOBOS1     = INVALID_HANDLE, h_rsiOBOS2     = INVALID_HANDLE;
int  h_stoOBOS1     = INVALID_HANDLE, h_stoOBOS2     = INVALID_HANDLE;
int  h_atrEntry     = INVALID_HANDLE;

// cached broker / symbol specs -------------------------------------
double g_point       = 0.0;
int    g_digits      = 0;
double g_volMin      = 0.0;
double g_volMax      = 0.0;
double g_volStep     = 0.0;
int    g_stopLevel   = 0;
int    g_freezeLevel = 0;
double g_tickSize    = 0.0;
long   g_leverage    = 0;

// session / state --------------------------------------------------
datetime g_lastBarTime   = 0;
datetime g_lastEntryBar  = 0;
datetime g_dayStamp      = 0;
double   g_dayStartEquity= 0.0;
double   g_runStartEquity= 0.0;
bool     g_halted        = false;

// funnel counters --------------------------------------------------
long k_bars = 0, k_rejTrendH4 = 0, k_rejTrendH1 = 0, k_rejAlign = 0;
long k_rejOBOSDisagree = 0, k_rejOBOSWrong = 0, k_rejPattern = 0;
long k_rejSpread = 0, k_rejHalt = 0, k_rejMargin = 0, k_rejLot = 0;
long k_entries = 0, k_gridAdds = 0, k_basketTP = 0, k_basketStop = 0;
long k_buys = 0, k_sells = 0, k_pauseOBOS = 0;

//==================================================================
//  UTILITY
//==================================================================

//--- round a volume DOWN to the broker's step, then clamp ---------
double NormalizeLotDown(double lots)
  {
   if(g_volStep <= 0.0)
      return 0.0;
   double steps = MathFloor(lots / g_volStep + 1e-8);
   double v     = steps * g_volStep;
   // guard against binary dust
   v = NormalizeDouble(v, 8);
   if(v > g_volMax) v = g_volMax;
   if(v < g_volMin) return 0.0;          // below minimum is NOT tradable
   return v;
  }

//--- current spread in points -------------------------------------
double SpreadPoints()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_point <= 0.0) return 0.0;
   return (ask - bid) / g_point;
  }

//--- ATR on the entry timeframe, from a CLOSED bar ----------------
double EntryATR()
  {
   double buf[];
   if(CopyBuffer(h_atrEntry, 0, 1, 1, buf) != 1)
      return 0.0;
   return buf[0];
  }

//--- convert an ATR/points distance spec into a price distance ----
double ResolveDistance(ENUM_DIST_MODE mode, double pts, double atrMult, double atr)
  {
   if(mode == DIST_POINTS)
      return pts * g_point;
   return atrMult * atr;
  }

//--- broker minimum stop distance, in price ------------------------
double MinStopDistance()
  {
   int lvl = (int)MathMax(g_stopLevel, g_freezeLevel);
   // a few brokers report 0 and police it server-side; keep a small floor
   if(lvl <= 0) lvl = 10;
   return lvl * g_point;
  }

void Log(string msg)
  {
   if(InpVerboseLog)
      Print(msg);
  }

//==================================================================
//  BROKER / ACCOUNT ADAPTATION
//==================================================================
bool CacheSymbolSpecs()
  {
   if(!SymbolInfoInteger(_Symbol, SYMBOL_SELECT))
     {
      if(!SymbolSelect(_Symbol, true))
        {
         Print("FATAL: cannot select symbol ", _Symbol);
         return false;
        }
     }

   g_point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_volMin      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_volMax      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_leverage    = AccountInfoInteger(ACCOUNT_LEVERAGE);

   if(g_point <= 0.0 || g_volStep <= 0.0 || g_volMin <= 0.0)
     {
      Print("FATAL: broker returned unusable symbol specs for ", _Symbol);
      return false;
     }

   string marginMode = "UNKNOWN";
   switch((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE))
     {
      case ACCOUNT_MARGIN_MODE_RETAIL_NETTING: marginMode = "RETAIL_NETTING"; break;
      case ACCOUNT_MARGIN_MODE_RETAIL_HEDGING: marginMode = "RETAIL_HEDGING"; break;
      case ACCOUNT_MARGIN_MODE_EXCHANGE:       marginMode = "EXCHANGE";       break;
     }

   PrintFormat("BROKER PROFILE | %s | digits=%d point=%.*f tickSize=%.*f",
               _Symbol, g_digits, g_digits, g_point, g_digits, g_tickSize);
   PrintFormat("BROKER PROFILE | volume min=%.4f max=%.2f step=%.4f | stopLevel=%d freezeLevel=%d",
               g_volMin, g_volMax, g_volStep, g_stopLevel, g_freezeLevel);
   PrintFormat("BROKER PROFILE | leverage=1:%d marginMode=%s contractSize=%.2f currency=%s",
               (int)g_leverage, marginMode,
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               AccountInfoString(ACCOUNT_CURRENCY));
   PrintFormat("BROKER PROFILE | equity=%.2f balance=%.2f freeMargin=%.2f",
               AccountInfoDouble(ACCOUNT_EQUITY),
               AccountInfoDouble(ACCOUNT_BALANCE),
               AccountInfoDouble(ACCOUNT_MARGIN_FREE));

   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      Print("WARNING: symbol trade mode is not FULL - orders may be restricted.");

   // Hedging is required for a true grid; netting will merge adds into one position.
   if(InpUseGrid &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: grid enabled on a NETTING account - grid adds will average into a ",
            "single position rather than opening separate ones. Basket logic still applies.");

   return true;
  }

//--- can this order be afforded? ----------------------------------
bool MarginOK(ENUM_ORDER_TYPE type, double lots, double price)
  {
   double need = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, need))
     {
      Log("MARGIN_CHECK | OrderCalcMargin failed, refusing order");
      return false;
     }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double allowed    = freeMargin * (InpMaxMarginPercent / 100.0);
   if(need > allowed)
     {
      k_rejMargin++;
      Log(StringFormat("MARGIN_REJECT | need=%.2f allowed=%.2f free=%.2f lots=%.2f",
                       need, allowed, freeMargin, lots));
      return false;
     }
   return true;
  }

//==================================================================
//  SIZING
//==================================================================

//--- money lost if a 'lots' position runs from entry to sl ---------
double RiskMoneyFor(double lots, double entry, double sl, int dir)
  {
   double profit = 0.0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(t, _Symbol, lots, entry, sl, profit))
      return 0.0;
   return MathAbs(profit);
  }

//--- lots for the configured sizing mode --------------------------
double ComputeLots(double entry, double sl, int dir)
  {
   if(InpLotMode == LOT_FIXED)
     {
      double v = NormalizeLotDown(MathMin(InpFixedLot, InpMaxLot));
      if(v <= 0.0)
         Log("SIZING | fixed lot below broker minimum");
      return v;
     }

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney  = equity * (InpRiskPercent / 100.0);
   if(riskMoney <= 0.0)
      return 0.0;

   // money risked by one minimum lot, then scale linearly
   double riskPerMin = RiskMoneyFor(g_volMin, entry, sl, dir);
   if(riskPerMin <= 0.0)
     {
      Log("SIZING | OrderCalcProfit returned no risk - refusing trade");
      return 0.0;
     }

   double raw = g_volMin * (riskMoney / riskPerMin);
   raw = MathMin(raw, InpMaxLot);
   double lots = NormalizeLotDown(raw);

   if(lots <= 0.0)
     {
      k_rejLot++;
      Log(StringFormat("SIZING | risk %.2f too small for min lot %.2f (min-lot risk %.2f) - skipping",
                       riskMoney, g_volMin, riskPerMin));
      return 0.0;
     }

   // never let rounding push actual risk above the requested budget
   double actual = RiskMoneyFor(lots, entry, sl, dir);
   while(lots > g_volMin && actual > riskMoney)
     {
      lots = NormalizeLotDown(lots - g_volStep);
      if(lots <= 0.0) return 0.0;
      actual = RiskMoneyFor(lots, entry, sl, dir);
     }

   Log(StringFormat("SIZING | equity=%.2f budget=%.2f lots=%.2f actualRisk=%.2f (%.3f%%)",
                    equity, riskMoney, lots, actual, actual / equity * 100.0));
   return lots;
  }

//==================================================================
//  STAGE 1 + 2 : TREND (H4) AND CONFIRMATION (H1)
//==================================================================

//--- EMA-based trend on a given timeframe, read from closed bars ---
ENUM_TREND EmaTrend(int hFast, int hSlow, bool requireSlope)
  {
   double f[], s[];
   if(CopyBuffer(hFast, 0, 1, 2, f) != 2) return TREND_NONE;
   if(CopyBuffer(hSlow, 0, 1, 1, s) != 1) return TREND_NONE;

   // f[0] = bar 2 (older), f[1] = bar 1 (most recent CLOSED bar)
   double fastNow  = f[1];
   double fastPrev = f[0];
   double slowNow  = s[0];

   if(fastNow > slowNow)
     {
      if(requireSlope && fastNow <= fastPrev) return TREND_NONE;
      return TREND_BULL;
     }
   if(fastNow < slowNow)
     {
      if(requireSlope && fastNow >= fastPrev) return TREND_NONE;
      return TREND_BEAR;
     }
   return TREND_NONE;
  }

//--- ADX strength filter, closed bar ------------------------------
bool TrendStrongEnough()
  {
   if(!InpUseADXFilter) return true;
   double adx[];
   if(CopyBuffer(h_adxTrend, 0, 1, 1, adx) != 1) return false;
   return (adx[0] >= InpADXMinimum);
  }

//==================================================================
//  STAGE 3 : OVERBOUGHT / OVERSOLD (M30 AND M15)
//==================================================================
ENUM_OBOS ReadOBOS(int hRSI, int hSto)
  {
   double r[];
   if(CopyBuffer(hRSI, 0, 1, 1, r) != 1) return OBOS_NEUTRAL;
   double rsi = r[0];

   bool rsiOB = (rsi >= InpRSIOverbought);
   bool rsiOS = (rsi <= InpRSIOversold);

   if(!InpUseStochastic)
     {
      if(rsiOB) return OBOS_OVERBOUGHT;
      if(rsiOS) return OBOS_OVERSOLD;
      return OBOS_NEUTRAL;
     }

   double k[];
   if(CopyBuffer(hSto, 0, 1, 1, k) != 1) return OBOS_NEUTRAL;   // buffer 0 = main (%K)
   double sto = k[0];

   bool stoOB = (sto >= InpStochOverbought);
   bool stoOS = (sto <= InpStochOversold);

   if(rsiOB && stoOB) return OBOS_OVERBOUGHT;
   if(rsiOS && stoOS) return OBOS_OVERSOLD;
   return OBOS_NEUTRAL;
  }

//==================================================================
//  STAGE 4 : M5 CANDLESTICK PATTERNS (CLOSED BARS ONLY)
//==================================================================
//  All patterns are evaluated on bar index 1 and older, i.e. bars
//  that are fully closed and can never change. Nothing repaints.
//------------------------------------------------------------------
struct Candle
  {
   double open, high, low, close;
   double body, range, upperWick, lowerWick;
   bool   bull;
  };

bool LoadCandle(int shift, Candle &c)
  {
   MqlRates r[];
   if(CopyRates(_Symbol, InpEntryTF, shift, 1, r) != 1)
      return false;
   c.open  = r[0].open;
   c.high  = r[0].high;
   c.low   = r[0].low;
   c.close = r[0].close;
   c.body  = MathAbs(c.close - c.open);
   c.range = c.high - c.low;
   c.bull  = (c.close > c.open);
   c.upperWick = c.high - MathMax(c.open, c.close);
   c.lowerWick = MathMin(c.open, c.close) - c.low;
   return true;
  }

//--- returns +1 bullish pattern, -1 bearish, 0 none ---------------
int PatternSignal(double atr, string &patName)
  {
   patName = "";
   if(atr <= 0.0) return 0;

   Candle c1, c2, c3;
   if(!LoadCandle(1, c1)) return 0;
   if(!LoadCandle(2, c2)) return 0;
   bool have3 = LoadCandle(3, c3);

   // the signal bar must be meaningful relative to current volatility
   if(c1.range < InpPatMinBodyATR * atr)
      return 0;

   //--- Engulfing --------------------------------------------------
   if(InpPatEngulfing && c1.body > 0.0 && c2.body > 0.0)
     {
      bool bullEngulf = c1.bull && !c2.bull &&
                        c1.close >= c2.open && c1.open <= c2.close &&
                        c1.body > c2.body;
      bool bearEngulf = !c1.bull && c2.bull &&
                        c1.close <= c2.open && c1.open >= c2.close &&
                        c1.body > c2.body;
      if(bullEngulf) { patName = "BULL_ENGULFING"; return  1; }
      if(bearEngulf) { patName = "BEAR_ENGULFING"; return -1; }
     }

   //--- Pin bar (hammer / shooting star) ---------------------------
   if(InpPatPinBar && c1.range > 0.0)
     {
      double bodyShare  = c1.body / c1.range;
      double lowerShare = c1.lowerWick / c1.range;
      double upperShare = c1.upperWick / c1.range;

      if(bodyShare <= InpPatBodyRatio && lowerShare >= InpPatWickRatio)
        { patName = "HAMMER"; return  1; }
      if(bodyShare <= InpPatBodyRatio && upperShare >= InpPatWickRatio)
        { patName = "SHOOTING_STAR"; return -1; }
     }

   //--- Morning / evening star (3 bars) ----------------------------
   if(InpPatStar && have3 && c3.body > 0.0 && c1.body > 0.0)
     {
      double c3mid = (c3.open + c3.close) / 2.0;
      bool smallMiddle = (c2.body <= c3.body * 0.5);

      bool morning = !c3.bull && smallMiddle && c1.bull &&
                     c1.close > c3mid && c2.high < c3.close;
      bool evening =  c3.bull && smallMiddle && !c1.bull &&
                     c1.close < c3mid && c2.low  > c3.close;

      if(morning) { patName = "MORNING_STAR"; return  1; }
      if(evening) { patName = "EVENING_STAR"; return -1; }
     }

   //--- Piercing line / dark cloud cover ---------------------------
   if(InpPatPiercing && c2.body > 0.0)
     {
      double c2mid = (c2.open + c2.close) / 2.0;
      bool piercing = !c2.bull && c1.bull &&
                      c1.open < c2.low && c1.close > c2mid && c1.close < c2.open;
      bool darkCloud = c2.bull && !c1.bull &&
                       c1.open > c2.high && c1.close < c2mid && c1.close > c2.open;
      if(piercing)  { patName = "PIERCING";   return  1; }
      if(darkCloud) { patName = "DARK_CLOUD"; return -1; }
     }

   //--- Inside-bar breakout ----------------------------------------
   //  bar3 = mother bar, bar2 = inside bar, bar1 = breakout close
   if(InpPatInsideBreak && have3)
     {
      bool inside = (c2.high <= c3.high && c2.low >= c3.low);
      if(inside)
        {
         if(c1.close > c3.high) { patName = "INSIDE_BREAK_UP";   return  1; }
         if(c1.close < c3.low)  { patName = "INSIDE_BREAK_DOWN"; return -1; }
        }
     }

   return 0;
  }

//==================================================================
//  POSITION / BASKET INSPECTION
//==================================================================
int CountPositions(int dir, double &totalVolume, double &weightedEntry,
                   double &floatingPL, double &worstPrice)
  {
   int    n     = 0;
   double volSum = 0.0, volPriceSum = 0.0, pl = 0.0;
   worstPrice = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(dir != 0 && pdir != dir) continue;

      double v  = PositionGetDouble(POSITION_VOLUME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);

      n++;
      volSum      += v;
      volPriceSum += v * op;
      pl          += PositionGetDouble(POSITION_PROFIT)
                   + PositionGetDouble(POSITION_SWAP);

      // "worst" = the entry furthest into loss, i.e. the last grid level
      if(worstPrice == 0.0)
         worstPrice = op;
      else if(pdir > 0 && op < worstPrice)
         worstPrice = op;
      else if(pdir < 0 && op > worstPrice)
         worstPrice = op;
     }

   totalVolume   = volSum;
   weightedEntry = (volSum > 0.0) ? volPriceSum / volSum : 0.0;
   floatingPL    = pl;
   return n;
  }

int BasketDirection()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

void CloseAllOurs(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      if(!g_trade.PositionClose(ticket, InpSlippagePoints))
         PrintFormat("CLOSE_FAIL | ticket=%I64u ret=%d %s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
     }
   Log("BASKET_CLOSED | reason=" + reason);
  }

//==================================================================
//  ORDER SEND
//==================================================================
bool SendOrder(int dir, double lots, double sl, double tp, string tag)
  {
   double price = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(!MarginOK(type, lots, price))
      return false;

   // clamp stops to the broker's minimum distance
   double minDist = MinStopDistance();
   if(sl > 0.0)
     {
      if(dir > 0 && price - sl < minDist) sl = price - minDist;
      if(dir < 0 && sl - price < minDist) sl = price + minDist;
      sl = NormalizeDouble(sl, g_digits);
     }
   if(tp > 0.0)
     {
      if(dir > 0 && tp - price < minDist) tp = price + minDist;
      if(dir < 0 && price - tp < minDist) tp = price - minDist;
      tp = NormalizeDouble(tp, g_digits);
     }

   bool ok = (dir > 0)
             ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, tag)
             : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, tag);

   if(!ok)
     {
      PrintFormat("SEND_FAIL | %s dir=%s lots=%.2f sl=%.*f tp=%.*f ret=%d %s",
                  tag, (dir > 0 ? "BUY" : "SELL"), lots, g_digits, sl, g_digits, tp,
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }

   PrintFormat("ENTRY | %s | %s lots=%.2f fill=%.*f sl=%.*f tp=%.*f spread=%.0fpts",
               tag, (dir > 0 ? "BUY" : "SELL"), lots,
               g_digits, g_trade.ResultPrice(), g_digits, sl, g_digits, tp,
               SpreadPoints());
   return true;
  }

//==================================================================
//  GRID
//==================================================================
double GridStepPrice(int level, double atr)
  {
   switch(InpGridSpacingMode)
     {
      case GRID_FIXED:       return InpGridStepPoints * g_point;
      case GRID_ATR:         return InpGridStepATR * atr;
      case GRID_PROGRESSIVE: return InpGridStepPoints * g_point * MathMax(1, level);
     }
   return InpGridStepPoints * g_point;
  }

//--- returns true if a grid add was placed ------------------------
bool ManageGrid(double atr, int freshSignal)
  {
   if(!InpUseGrid) return false;

   int dir = BasketDirection();
   if(dir == 0) return false;

   double vol, avgEntry, pl, worst;
   int n = CountPositions(dir, vol, avgEntry, pl, worst);
   if(n <= 0) return false;
   if(n >= InpMaxGridPositions) return false;
   if(pl >= 0.0) return false;                 // only manage FLOATING LOSSES

   if(InpGridRequireSignal && freshSignal != dir)
      return false;

   double price = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double step  = GridStepPrice(n, atr);
   if(step <= 0.0) return false;

   // price must have travelled 'step' against us from the deepest entry
   bool trigger = (dir > 0) ? (price <= worst - step)
                            : (price >= worst + step);
   if(!trigger) return false;

   if(SpreadPoints() > InpMaxSpreadPoints)
     {
      k_rejSpread++;
      return false;
     }

   // grid lot: base lot scaled by the multiplier for this level
   double baseLot;
   if(InpLotMode == LOT_FIXED)
      baseLot = InpFixedLot;
   else
     {
      // reuse the first position's size as the base for consistency
      baseLot = (n > 0) ? vol / n : g_volMin;
     }
   double raw  = baseLot * MathPow(InpGridLotMultiplier, n);
   double lots = NormalizeLotDown(MathMin(raw, InpMaxLot));
   if(lots <= 0.0) return false;

   double sl = 0.0, tp = 0.0;
   if(!InpGridNoIndividualSL)
     {
      double slDist = ResolveDistance(InpSLMode, InpSLPoints, InpSLATR, atr);
      sl = (dir > 0) ? price - slDist : price + slDist;
     }

   if(SendOrder(dir, lots, sl, tp, StringFormat("GRID_L%d", n + 1)))
     {
      k_gridAdds++;
      PrintFormat("GRID_ADD | level=%d dir=%s worstEntry=%.*f price=%.*f step=%.*f floatPL=%.2f",
                  n + 1, (dir > 0 ? "BUY" : "SELL"),
                  g_digits, worst, g_digits, price, g_digits, step, pl);
      return true;
     }
   return false;
  }

//--- basket take profit and hard basket stop ----------------------
void ManageBasket()
  {
   int dir = BasketDirection();
   if(dir == 0) return;

   double vol, avgEntry, pl, worst;
   int n = CountPositions(dir, vol, avgEntry, pl, worst);
   if(n <= 0) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // hard kill switch first - this must never be gated behind anything
   double maxLoss = equity * (InpBasketMaxLossPercent / 100.0);
   if(InpBasketMaxLossPercent > 0.0 && pl <= -maxLoss)
     {
      k_basketStop++;
      PrintFormat("BASKET_STOP | positions=%d floatPL=%.2f limit=-%.2f equity=%.2f",
                  n, pl, maxLoss, equity);
      CloseAllOurs("BASKET_MAX_LOSS");
      return;
     }

   // basket take profit
   if(InpUseBasketTP && n > 1)
     {
      double target = equity * (InpBasketTPPercent / 100.0);
      if(pl >= target)
        {
         k_basketTP++;
         PrintFormat("BASKET_TP | positions=%d floatPL=%.2f target=%.2f avgEntry=%.*f",
                     n, pl, target, g_digits, avgEntry);
         CloseAllOurs("BASKET_TP");
        }
     }
  }

//==================================================================
//  BREAKEVEN + TRAILING
//==================================================================
void ManageStops(double atr)
  {
   if(!InpUseTrailing && !InpMoveToBreakeven) return;
   if(atr <= 0.0) return;

   double minDist = MinStopDistance();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      int    dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double price  = (dir > 0) ? bid : ask;
      double profit = (dir > 0) ? (price - entry) : (entry - price);

      double desiredSL = 0.0;
      string chosen    = "";

      //--- breakeven candidate -------------------------------------
      if(InpMoveToBreakeven && profit >= InpBEStartATR * atr)
        {
         double be = (dir > 0) ? entry + InpBEOffsetPoints * g_point
                               : entry - InpBEOffsetPoints * g_point;
         desiredSL = be;
         chosen    = "BE";
        }

      //--- trailing candidate --------------------------------------
      if(InpUseTrailing)
        {
         double armAt = ResolveDistance(InpTrailMode, InpTrailStartPoints, InpTrailStartATR, atr);
         if(profit >= armAt)
           {
            double dist  = ResolveDistance(InpTrailMode, InpTrailPoints, InpTrailATR, atr);
            double trail = (dir > 0) ? price - dist : price + dist;

            // keep the MOST protective of the candidates
            if(desiredSL == 0.0 ||
               (dir > 0 && trail > desiredSL) ||
               (dir < 0 && trail < desiredSL))
              {
               desiredSL = trail;
               chosen    = "TRAIL";
              }
           }
        }

      if(desiredSL == 0.0) continue;

      //--- a stop may only ever tighten ----------------------------
      double tol = g_point * 0.5;
      if(curSL > 0.0)
        {
         if(dir > 0 && desiredSL < curSL + InpTrailStepPoints * g_point) continue;
         if(dir < 0 && desiredSL > curSL - InpTrailStepPoints * g_point) continue;
        }

      //--- respect the broker's minimum distance -------------------
      if(dir > 0 && price - desiredSL < minDist) continue;
      if(dir < 0 && desiredSL - price < minDist) continue;

      desiredSL = NormalizeDouble(desiredSL, g_digits);
      if(curSL > 0.0 && MathAbs(desiredSL - curSL) < tol) continue;

      if(g_trade.PositionModify(ticket, desiredSL, curTP))
         PrintFormat("STOP_MOVED | %s ticket=%I64u dir=%s old=%.*f new=%.*f profit=%.*f",
                     chosen, ticket, (dir > 0 ? "BUY" : "SELL"),
                     g_digits, curSL, g_digits, desiredSL, g_digits, profit);
      else
         PrintFormat("STOP_MOVE_FAIL | ticket=%I64u ret=%d %s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
     }
  }

//==================================================================
//  SAFETY
//==================================================================
void RollDayIfNeeded()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0; t.min = 0; t.sec = 0;
   datetime today = StructToTime(t);
   if(today != g_dayStamp)
     {
      g_dayStamp       = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_halted         = false;
     }
  }

bool TradingHalted()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpMinEquityPercent > 0.0 && g_runStartEquity > 0.0 &&
      equity < g_runStartEquity * (InpMinEquityPercent / 100.0))
     {
      if(!g_halted)
         PrintFormat("HALT | equity %.2f below %.1f%% of start equity %.2f",
                     equity, InpMinEquityPercent, g_runStartEquity);
      g_halted = true;
      return true;
     }

   if(InpDailyLossPercent > 0.0 && g_dayStartEquity > 0.0)
     {
      double dd = (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
      if(dd >= InpDailyLossPercent)
        {
         if(!g_halted)
            PrintFormat("HALT | daily loss %.2f%% >= %.2f%% limit", dd, InpDailyLossPercent);
         g_halted = true;
         return true;
        }
     }
   return g_halted;
  }

//==================================================================
//  MAIN DECISION PASS (once per closed entry bar)
//==================================================================
void EvaluateEntry(double atr)
  {
   //--- Stage 1: H4 overall trend ---------------------------------
   ENUM_TREND h4 = EmaTrend(h_emaFastTrend, h_emaSlowTrend, InpRequireH4Slope);
   if(InpGateTrendH4)
     {
      if(h4 == TREND_NONE || !TrendStrongEnough())
        {
         k_rejTrendH4++;
         return;
        }
     }

   //--- Stage 2: H1 confirmation ----------------------------------
   ENUM_TREND h1 = EmaTrend(h_emaFastConf, h_emaSlowConf, false);
   if(InpGateTrendH1)
     {
      if(h1 == TREND_NONE)
        {
         k_rejTrendH1++;
         return;
        }
      if(InpGateTrendH4 && h1 != h4)
        {
         k_rejAlign++;
         Log(StringFormat("GATE | H4/H1 disagree (H4=%d H1=%d) - no trade", h4, h1));
         return;
        }
     }

   int dir = 0;
   if(InpGateTrendH4)      dir = (int)h4;
   else if(InpGateTrendH1) dir = (int)h1;
   if(dir == 0) { k_rejTrendH4++; return; }

   //--- Stage 3: M30 / M15 overbought-oversold agreement ----------
   ENUM_OBOS o30 = ReadOBOS(h_rsiOBOS1, h_stoOBOS1);
   ENUM_OBOS o15 = ReadOBOS(h_rsiOBOS2, h_stoOBOS2);

   if(InpGateOBOSAgree)
     {
      if(o30 != o15)
        {
         k_rejOBOSDisagree++;
         k_pauseOBOS++;
         Log(StringFormat("PAUSE | M30 and M15 disagree (M30=%d M15=%d) - new entries paused",
                          o30, o15));
         return;
        }
      if(o30 == OBOS_NEUTRAL)
        {
         k_rejOBOSWrong++;
         return;
        }

      // pullback mode: buy into oversold within an uptrend, sell into overbought
      ENUM_OBOS wanted;
      if(InpRequireCounterOBOS)
         wanted = (dir > 0) ? OBOS_OVERSOLD : OBOS_OVERBOUGHT;
      else
         wanted = (dir > 0) ? OBOS_OVERBOUGHT : OBOS_OVERSOLD;

      if(o30 != wanted)
        {
         k_rejOBOSWrong++;
         return;
        }
     }

   //--- Stage 4: M5 candlestick trigger ---------------------------
   string patName = "";
   int pat = PatternSignal(atr, patName);
   if(InpGatePattern)
     {
      if(pat == 0 || pat != dir)
        {
         k_rejPattern++;
         return;
        }
     }

   //--- execution guards ------------------------------------------
   if(SpreadPoints() > InpMaxSpreadPoints)
     {
      k_rejSpread++;
      Log(StringFormat("SPREAD_REJECT | %.0f pts > %.0f limit",
                       SpreadPoints(), InpMaxSpreadPoints));
      return;
     }

   // an existing basket in the opposite direction is not reversed here;
   // grid management owns that basket until it closes.
   int existingDir = BasketDirection();
   if(existingDir != 0 && existingDir != dir)
     {
      Log("SKIP | opposite basket open, leaving it to basket management");
      return;
     }
   if(existingDir == dir)
     {
      // adding to a winning direction is the grid's job, not the entry's
      return;
     }

   //--- geometry ---------------------------------------------------
   double price  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = ResolveDistance(InpSLMode, InpSLPoints, InpSLATR, atr);
   double tpDist = ResolveDistance(InpTPMode, InpTPPoints, InpTPATR, atr);
   if(slDist <= 0.0) return;

   double sl = (dir > 0) ? price - slDist : price + slDist;
   double tp = (dir > 0) ? price + tpDist : price - tpDist;

   double lots = ComputeLots(price, sl, dir);
   if(lots <= 0.0) return;

   // with the grid enabled the basket stop governs, so individual stops
   // are optional - but the SL distance is still what sizes the position.
   double sendSL = (InpUseGrid && InpGridNoIndividualSL) ? 0.0 : sl;
   double sendTP = (InpUseGrid && InpUseBasketTP) ? tp : tp;

   PrintFormat("SIGNAL | dir=%s H4=%d H1=%d M30=%d M15=%d pattern=%s atr=%.*f",
               (dir > 0 ? "BUY" : "SELL"), h4, h1, o30, o15,
               (patName == "" ? "NONE" : patName), g_digits, atr);

   if(SendOrder(dir, lots, sendSL, sendTP, "ENTRY_" + patName))
     {
      k_entries++;
      if(dir > 0) k_buys++; else k_sells++;
      g_lastEntryBar = iTime(_Symbol, InpEntryTF, 0);
     }
  }

//==================================================================
//  LIFECYCLE
//==================================================================
int OnInit()
  {
   if(!CacheSymbolSpecs())
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- indicator handles (all non-repainting, read from closed bars)
   h_emaFastTrend = iMA(_Symbol, InpTrendTF,   InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   h_emaSlowTrend = iMA(_Symbol, InpTrendTF,   InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   h_emaFastConf  = iMA(_Symbol, InpConfirmTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   h_emaSlowConf  = iMA(_Symbol, InpConfirmTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   h_adxTrend     = iADX(_Symbol, InpTrendTF,  InpADXPeriod);
   h_rsiOBOS1     = iRSI(_Symbol, InpOBOS1TF,  InpRSIPeriod, PRICE_CLOSE);
   h_rsiOBOS2     = iRSI(_Symbol, InpOBOS2TF,  InpRSIPeriod, PRICE_CLOSE);
   h_stoOBOS1     = iStochastic(_Symbol, InpOBOS1TF, InpStochK, InpStochD, InpStochSlow,
                                MODE_SMA, STO_LOWHIGH);
   h_stoOBOS2     = iStochastic(_Symbol, InpOBOS2TF, InpStochK, InpStochD, InpStochSlow,
                                MODE_SMA, STO_LOWHIGH);
   h_atrEntry     = iATR(_Symbol, InpEntryTF,  InpATRPeriod);

   if(h_emaFastTrend == INVALID_HANDLE || h_emaSlowTrend == INVALID_HANDLE ||
      h_emaFastConf  == INVALID_HANDLE || h_emaSlowConf  == INVALID_HANDLE ||
      h_adxTrend     == INVALID_HANDLE || h_rsiOBOS1     == INVALID_HANDLE ||
      h_rsiOBOS2     == INVALID_HANDLE || h_stoOBOS1     == INVALID_HANDLE ||
      h_stoOBOS2     == INVALID_HANDLE || h_atrEntry     == INVALID_HANDLE)
     {
      Print("FATAL: indicator handle creation failed");
      return INIT_FAILED;
     }

   if(InpEmaFast >= InpEmaSlow)
     {
      Print("FATAL: InpEmaFast must be smaller than InpEmaSlow");
      return INIT_FAILED;
     }
   if(InpMaxGridPositions < 1)
     {
      Print("FATAL: InpMaxGridPositions must be at least 1");
      return INIT_FAILED;
     }

   g_runStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity = g_runStartEquity;
   RollDayIfNeeded();

   PrintFormat("TWI Gold MTF Grid init | trend=%s confirm=%s obos=%s/%s entry=%s",
               EnumToString(InpTrendTF), EnumToString(InpConfirmTF),
               EnumToString(InpOBOS1TF), EnumToString(InpOBOS2TF),
               EnumToString(InpEntryTF));
   PrintFormat("Grid=%s spacing=%s maxPositions=%d lotMultiplier=%.2f basketStop=%.2f%%",
               (InpUseGrid ? "ON" : "OFF"), EnumToString(InpGridSpacingMode),
               InpMaxGridPositions, InpGridLotMultiplier, InpBasketMaxLossPercent);

   if(InpGridLotMultiplier > 1.0)
      Print("WARNING: InpGridLotMultiplier > 1.0 - this is a MARTINGALE. ",
            "Risk grows geometrically with each grid level.");

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(h_emaFastTrend);
   IndicatorRelease(h_emaSlowTrend);
   IndicatorRelease(h_emaFastConf);
   IndicatorRelease(h_emaSlowConf);
   IndicatorRelease(h_adxTrend);
   IndicatorRelease(h_rsiOBOS1);
   IndicatorRelease(h_rsiOBOS2);
   IndicatorRelease(h_stoOBOS1);
   IndicatorRelease(h_stoOBOS2);
   IndicatorRelease(h_atrEntry);

   if(!InpPrintSummary) return;

   Print("=== TWI GOLD MTF GRID FUNNEL ===");
   PrintFormat("Entry bars evaluated: %I64d", k_bars);
   PrintFormat("Rejected: H4 trend %I64d | H1 trend %I64d | H4/H1 disagree %I64d",
               k_rejTrendH4, k_rejTrendH1, k_rejAlign);
   PrintFormat("Rejected: M30/M15 disagree %I64d | wrong OB/OS state %I64d",
               k_rejOBOSDisagree, k_rejOBOSWrong);
   PrintFormat("Rejected: no M5 pattern %I64d | spread %I64d | margin %I64d | lot too small %I64d",
               k_rejPattern, k_rejSpread, k_rejMargin, k_rejLot);
   PrintFormat("ENTRIES: %I64d (buy %I64d | sell %I64d)", k_entries, k_buys, k_sells);
   PrintFormat("Grid adds: %I64d | basket TP: %I64d | basket stop: %I64d",
               k_gridAdds, k_basketTP, k_basketStop);
   PrintFormat("OB/OS pauses (M30 vs M15 conflict): %I64d", k_pauseOBOS);
   PrintFormat("Final equity: %.2f (start %.2f)",
               AccountInfoDouble(ACCOUNT_EQUITY), g_runStartEquity);
  }

void OnTick()
  {
   RollDayIfNeeded();

   double atr = EntryATR();

   //--- management runs every tick: stops, basket, grid ------------
   ManageStops(atr);
   ManageBasket();

   //--- entry logic runs once per CLOSED entry-timeframe bar -------
   datetime barTime = iTime(_Symbol, InpEntryTF, 0);
   if(barTime == 0) return;
   bool newBar = (barTime != g_lastBarTime);
   if(newBar) { g_lastBarTime = barTime; k_bars++; }

   if(TradingHalted())
     {
      if(newBar) k_rejHalt++;
      return;
     }

   if(!newBar) return;
   if(InpOnePositionPerBar && barTime == g_lastEntryBar) return;
   if(atr <= 0.0) return;

   //--- grid add is evaluated on the same closed bar ---------------
   string dummy = "";
   int freshSignal = (InpUseGrid && InpGridRequireSignal) ? PatternSignal(atr, dummy) : 0;
   if(ManageGrid(atr, freshSignal))
      return;

   EvaluateEntry(atr);
  }
//+------------------------------------------------------------------+
