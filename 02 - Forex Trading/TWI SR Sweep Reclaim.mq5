//+------------------------------------------------------------------+
//| TWI SR Sweep Reclaim                                             |
//| H1 bias -> M15 resistance/support -> break+flip -> M5 pullback   |
//| -> zone interaction -> engulfing candle -> entry on its close.    |
//| Targets come from a registry of remembered structure zones.       |
//| Debug mode draws every zone/breakout/retest/entry/invalidation   |
//| event on the chart, and every taken trade prints a full          |
//| diagnostic block, so a loss can be explained instead of guessed. |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "3.20"
#property strict

//----------------------------------------------------------------------
// Inputs
//----------------------------------------------------------------------
input group "Structure"
input int    SwingLeftBars      = 3;
input int    SwingRightBars     = 3;
input int    ATRPeriod          = 14;
input int    SwingLookbackBars  = 300;
input double ZoneClusterATR     = 0.25;  // a bar "touches" the level if its extreme is within this of the reference
input int    MaxClusterBars     = 8;     // window searched either side of the swing
input int    MinClusterTouches  = 2;     // fewer qualifying touches than this = not a real level
input double MinZoneThickATR    = 0.10;
input double MaxZoneThickATR    = 0.60;

input group "Breakout / Pullback"
input double BreakoutBufferATR    = 0.10;
input double MinBreakoutBodyATR   = 0.50;
input int    MaxBreakoutWaitBars  = 60;   // StructureTF (M15) bars, waiting for the level to break
input int    MaxPullbackWaitBars  = 20;   // EntryTF (M5) bars, waiting for price back into the zone

input group "Zone interaction / Engulf confirmation"
// Penetration depth is measured and logged for research, but it is NOT a
// gate: the source material shows entries on an engulfing candle at the
// level, with no required ATR-sized wick through it.
input int    MaxEngulfWaitBars = 40;      // EntryTF bars, overall window once pullback is tagged

input group "Entry"
enum ENUM_ENTRY_MODE { ENTRY_MARKET_ON_CONFIRM, ENTRY_STOP_ABOVE_CONFIRM };
input ENUM_ENTRY_MODE EntryMode  = ENTRY_MARKET_ON_CONFIRM; // "buy at close" by default
input double EntryBufferATR      = 0.02;   // only used by ENTRY_STOP_ABOVE_CONFIRM
input int    PendingExpiryBars   = 6;      // EntryTF bars before a stop order is cancelled

input group "Structure targets"
input double TargetBufferATR   = 0.10;  // TP sits this far inside the opposing zone's near edge
input double DuplicateZoneATR  = 0.25;  // zones this close are treated as the same historical level
input int    MaxZoneRegistry   = 200;   // rolling cap on remembered zones

input group "Risk / Exit"
input double SLBufferATR    = 0.10;
input double MinRR          = 1.5;   // skip if nearest structure target is closer than this many R
enum ENUM_TP_MODE { TP_STRUCTURE, TP_FIXED_RR, TP_HYBRID };
input ENUM_TP_MODE TPMode   = TP_HYBRID;  // hybrid = TP at the selected structure target, gated by MinRR
input double FixedRR        = 2.0;
input double RiskPercent    = 1.0;
input int    MaxPositions   = 1;
input double BreakevenR     = 1.0;
input double TrailStartR    = 1.5;
input double TrailATRMult   = 1.5;

input group "Multi-timeframe"
input ENUM_TIMEFRAMES TrendTF     = PERIOD_H1;
input ENUM_TIMEFRAMES StructureTF = PERIOD_M15;
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M5;

input group "Debug"
input bool DebugStats    = true;   // print the funnel counter breakdown on deinit
input bool DebugDraw     = true;   // draw zones/breakout/retest/sweep/entry/invalidation on chart
input bool DebugTradeLog = true;   // print a full diagnostic block for every trade sent

input group "Misc"
input long MagicNumber = 990100;

//----------------------------------------------------------------------
// State
//----------------------------------------------------------------------
enum EA_STATE
  {
   STATE_SEARCH_TREND,
   STATE_WAIT_FOR_BREAKOUT,
   STATE_WAIT_FOR_PULLBACK,
   STATE_WAIT_FOR_ENGULF,
   STATE_PENDING_ORDER
  };

struct SwingPoint
  {
   datetime time;
   double   price;
  };

// Persistent structural map. A zone's life is independent of any single
// trading setup: a breakout/retest setup may time out, but the level it
// was built on stays available as future structure until price decisively
// invalidates it.
enum ZONE_STATE { ZS_ACTIVE, ZS_FLIPPED, ZS_BROKEN, ZS_INVALIDATED, ZS_MERGED };

struct ZoneRec
  {
   int        id;
   int        type;            // +1 resistance, -1 support
   double     hi;
   double     lo;
   datetime   created;         // oldest bar of the originating cluster
   datetime   registered;      // when the EA actually learned of it (closed bars only)
   datetime   originSwing;     // the confirmed swing this was built from
   datetime   lastInteraction;
   datetime   breakTime;
   int        touches;
   ZONE_STATE state;
  };

ZoneRec g_zones[];
int     g_nextZoneId = 1;
int     g_entryZoneId = -1;   // the zone broken and flipped for the current setup

EA_STATE g_state = STATE_SEARCH_TREND;
int      g_direction = 0;              // +1 bull, -1 bear

double   g_zoneHigh, g_zoneLow;        // level identified as resistance (bull) / support (bear), then flips
double   g_breakoutBodyATR = 0;
int      g_breakoutWaitBars = 0;
int      g_pullbackWaitBars = 0;
int      g_engulfWaitBars = 0;

double   g_rejectHigh, g_rejectLow;    // the rejection/interaction extremes the stop sits beyond
double   g_penetrationATR;             // measured for research only -- never gates a trade

ulong    g_pendingTicket = 0;

datetime g_lastStructBarTime = 0;
datetime g_lastEntryBarTime  = 0;

int g_atrStructHandle = INVALID_HANDLE;
int g_atrEntryHandle  = INVALID_HANDLE;

long g_tradeCounter = 0;
long g_objCounter = 0;

// Diagnostic funnel counters -- printed on OnDeinit so a backtest run
// shows exactly where setups die, instead of guessing.
long g_cTrendDetected=0, g_cReachedBreakoutWait=0, g_cZoneRejectedTouches=0;
long g_cH1BiasFlip=0, g_cBreakoutWaitTimeout=0, g_cBreakoutHit=0;
long g_cPullbackTimeout=0, g_cPullbackTag=0;
long g_cEngulfTimeout=0;
long g_cZoneInteractions=0, g_cBullishEngulfs=0, g_cBearishEngulfs=0;
long g_cEngulfRejNoZoneInteraction=0, g_cEngulfRejCloseWrongSide=0, g_cEngulfConfirmed=0;
long g_cTargetFound=0, g_cNoValidTarget=0, g_cRRPass=0, g_cRRFail=0;
long g_cTargetCandidates=0, g_cValidTargets=0, g_cZonesMerged=0;
long g_cTradeSkippedRR=0, g_cTradeSkippedLots=0, g_cTradeSkippedMaxPos=0, g_cTradeSent=0;

// Closed-trade results, tracked in R so wins/losses are comparable across
// different stop distances (the tester report can't express this itself).
ulong  g_riskTicket[];
double g_riskMoney[];
long   g_rWins=0, g_rLosses=0, g_rLongs=0, g_rShorts=0;
double g_sumWinR=0, g_sumLossR=0;

//----------------------------------------------------------------------
int OnInit()
  {
   g_atrStructHandle = iATR(_Symbol, StructureTF, ATRPeriod);
   g_atrEntryHandle  = iATR(_Symbol, EntryTF, ATRPeriod);
   if(g_atrStructHandle == INVALID_HANDLE || g_atrEntryHandle == INVALID_HANDLE)
      return(INIT_FAILED);
   ResetSequence();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_atrStructHandle != INVALID_HANDLE) IndicatorRelease(g_atrStructHandle);
   if(g_atrEntryHandle  != INVALID_HANDLE) IndicatorRelease(g_atrEntryHandle);
   if(!DebugStats) return;

   long closed = g_rWins + g_rLosses;
   double winRate = (closed > 0) ? 100.0 * g_rWins / closed : 0;
   double avgWinR = (g_rWins   > 0) ? g_sumWinR  / g_rWins   : 0;
   double avgLossR= (g_rLosses > 0) ? g_sumLossR / g_rLosses : 0;

   PrintFormat("=== SETUP FUNNEL ===\nH1 bias windows found: %d\nZones rejected (too few cluster touches): %d\nZones armed (level identified): %d\nLevel never broke (breakout timeout): %d\nDetected M15 breakouts: %d\nRejected H1 bias flip: %d\nNo retest (pullback timeout): %d\nRetest tagged: %d\nZone interactions: %d\nBullish engulfs seen: %d\nBearish engulfs seen: %d\nEngulf rejected (no zone interaction): %d\nEngulf rejected (close wrong side): %d\nEngulf confirmed: %d\nNo engulf in window (timeout): %d\nTarget candidates considered: %d\nValid targets found: %d\nSetups with a target: %d\nNo valid structure target: %d\nRR pass: %d\nRR fail: %d\nInsufficient RR (total skipped): %d\nRejected lot sizing: %d\nRejected max positions: %d\nVALID ENTRIES: %d",
               g_cTrendDetected, g_cZoneRejectedTouches, g_cReachedBreakoutWait, g_cBreakoutWaitTimeout,
               g_cBreakoutHit, g_cH1BiasFlip,
               g_cPullbackTimeout, g_cPullbackTag,
               g_cZoneInteractions, g_cBullishEngulfs, g_cBearishEngulfs,
               g_cEngulfRejNoZoneInteraction, g_cEngulfRejCloseWrongSide, g_cEngulfConfirmed,
               g_cEngulfTimeout,
               g_cTargetCandidates, g_cValidTargets, g_cTargetFound, g_cNoValidTarget, g_cRRPass, g_cRRFail,
               g_cTradeSkippedRR, g_cTradeSkippedLots, g_cTradeSkippedMaxPos,
               g_cTradeSent);

   double expectancyR = (closed > 0) ? (g_sumWinR + g_sumLossR) / closed : 0;
   double pfR = (g_sumLossR != 0) ? g_sumWinR / MathAbs(g_sumLossR) : 0;

   PrintFormat("=== TRADE RESULTS ===\nClosed trades: %d\nBUY trades: %d\nSELL trades: %d\nWins: %d\nLosses: %d\nWin rate: %.1f%%\nAvg win: %.2fR\nAvg loss: %.2fR\nExpectancy: %.3fR per trade\nProfit factor (R-based): %.2f\nFinal balance: %.2f\n(net profit and max equity DD%%: see tester report)",
               closed, g_rLongs, g_rShorts, g_rWins, g_rLosses, winRate,
               avgWinR, avgLossR, expectancyR, pfR, AccountInfoDouble(ACCOUNT_BALANCE));
  }

// Record each entry's money risk, then score each exit in R.
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong posId    = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   if(entryType == DEAL_ENTRY_IN)
     {
      double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double sl     = HistoryDealGetDouble(trans.deal, DEAL_SL);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double riskMoney = 0;
      if(sl > 0 && tickSize > 0)
         riskMoney = MathAbs(price - sl) / tickSize * tickValue * volume;
      if(riskMoney <= 0) return;

      int n = ArraySize(g_riskTicket);
      ArrayResize(g_riskTicket, n + 1);
      ArrayResize(g_riskMoney,  n + 1);
      g_riskTicket[n] = posId;
      g_riskMoney[n]  = riskMoney;

      if(HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) g_rLongs++;
      else                                                             g_rShorts++;
      return;
     }

   if(entryType == DEAL_ENTRY_OUT)
     {
      double risk = 0;
      for(int i = 0; i < ArraySize(g_riskTicket); i++)
         if(g_riskTicket[i] == posId) { risk = g_riskMoney[i]; break; }
      if(risk <= 0) return;

      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      double r = profit / risk;
      if(profit >= 0) { g_rWins++;   g_sumWinR  += r; }
      else            { g_rLosses++; g_sumLossR += r; }
     }
  }

void ResetSequence()
  {
   g_state = STATE_SEARCH_TREND;
   g_direction = 0;
   g_breakoutWaitBars = 0;
   g_pullbackWaitBars = 0;
   g_engulfWaitBars = 0;
   if(g_pendingTicket != 0)
      CancelPending();
  }

//----------------------------------------------------------------------
double ATRValue(int handle)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, 1, 1, buf) != 1) return(0.0);
   return(buf[0]);
  }

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastTime)
  {
   datetime t = iTime(_Symbol, tf, 0);
   if(t != lastTime)
     {
      lastTime = t;
      return(true);
     }
   return(false);
  }

string BiasLabel(int d) { return(d > 0 ? "Bullish" : (d < 0 ? "Bearish" : "Neutral")); }

//----------------------------------------------------------------------
// Swing detection, closed bars only, on whichever timeframe is asked for.
// Index 0 = most recently closed bar (series copy starts at shift 1 to
// skip the still-forming bar) -- no repaint.
//----------------------------------------------------------------------
bool FindLastTwoSwingHighs(ENUM_TIMEFRAMES tf, SwingPoint &s1, SwingPoint &s2)
  {
   int total = SwingLookbackBars;
   double high[];
   datetime tm[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(tm, true);
   if(CopyHigh(_Symbol, tf, 1, total, high) < total) return(false);
   if(CopyTime(_Symbol, tf, 1, total, tm) < total) return(false);

   int found = 0;
   for(int i = SwingRightBars; i < total - SwingLeftBars && found < 2; i++)
     {
      bool isHigh = true;
      for(int L = 1; L <= SwingLeftBars && isHigh; L++)
         if(high[i+L] > high[i]) isHigh = false;
      for(int R = 1; R <= SwingRightBars && isHigh; R++)
         if(high[i-R] > high[i]) isHigh = false;
      if(isHigh)
        {
         if(found == 0) { s1.time = tm[i]; s1.price = high[i]; }
         else           { s2.time = tm[i]; s2.price = high[i]; }
         found++;
        }
     }
   return(found == 2);
  }

bool FindLastTwoSwingLows(ENUM_TIMEFRAMES tf, SwingPoint &s1, SwingPoint &s2)
  {
   int total = SwingLookbackBars;
   double low[];
   datetime tm[];
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(tm, true);
   if(CopyLow(_Symbol, tf, 1, total, low) < total) return(false);
   if(CopyTime(_Symbol, tf, 1, total, tm) < total) return(false);

   int found = 0;
   for(int i = SwingRightBars; i < total - SwingLeftBars && found < 2; i++)
     {
      bool isLow = true;
      for(int L = 1; L <= SwingLeftBars && isLow; L++)
         if(low[i+L] < low[i]) isLow = false;
      for(int R = 1; R <= SwingRightBars && isLow; R++)
         if(low[i-R] < low[i]) isLow = false;
      if(isLow)
        {
         if(found == 0) { s1.time = tm[i]; s1.price = low[i]; }
         else           { s2.time = tm[i]; s2.price = low[i]; }
         found++;
        }
     }
   return(found == 2);
  }

int DetectTrend(ENUM_TIMEFRAMES tf)
  {
   SwingPoint h1, h2, l1, l2;
   if(!FindLastTwoSwingHighs(tf, h1, h2)) return(0);
   if(!FindLastTwoSwingLows(tf, l1, l2))  return(0);
   bool higherHigh = h1.price > h2.price;
   bool higherLow  = l1.price > l2.price;
   bool lowerHigh  = h1.price < h2.price;
   bool lowerLow   = l1.price < l2.price;
   if(higherHigh && higherLow) return(+1);
   if(lowerHigh  && lowerLow)  return(-1);
   return(0);
  }

//----------------------------------------------------------------------
// Zone registry
//----------------------------------------------------------------------
// Merge rather than duplicate: two levels whose midpoints sit within
// DuplicateZoneATR are the same historical structure. The existing zone's
// geometry is preserved (the width algorithm is not touched here) -- the
// new sighting only adds a touch and refreshes last interaction.
int FindMergeTarget(int type, double hi, double lo, double atrStruct)
  {
   double tol = DuplicateZoneATR * atrStruct;
   double mid = (hi + lo) / 2.0;
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].type != type) continue;
      if(g_zones[i].state == ZS_BROKEN || g_zones[i].state == ZS_INVALIDATED || g_zones[i].state == ZS_MERGED)
         continue;
      double emid = (g_zones[i].hi + g_zones[i].lo) / 2.0;
      if(MathAbs(emid - mid) <= tol) return(i);
     }
   return(-1);
  }

int RegisterZone(int type, double hi, double lo, datetime created, datetime originSwing,
                 int touches, double atrStruct, datetime registeredAt)
  {
   int m = FindMergeTarget(type, hi, lo, atrStruct);
   if(m >= 0)
     {
      g_zones[m].touches        += MathMax(1, touches);
      g_zones[m].lastInteraction = registeredAt;
      if(created < g_zones[m].created) g_zones[m].created = created;  // preserve earliest
      g_cZonesMerged++;
      return(g_zones[m].id);
     }

   int n = ArraySize(g_zones);
   if(n >= MaxZoneRegistry)
     {
      for(int i = 0; i < n - 1; i++) g_zones[i] = g_zones[i + 1];
      ArrayResize(g_zones, n - 1);
      n = n - 1;
     }
   ArrayResize(g_zones, n + 1);
   g_zones[n].id              = g_nextZoneId++;
   g_zones[n].type            = type;
   g_zones[n].hi              = hi;
   g_zones[n].lo              = lo;
   g_zones[n].created         = created;
   g_zones[n].registered      = registeredAt;
   g_zones[n].originSwing     = originSwing;
   g_zones[n].lastInteraction = registeredAt;
   g_zones[n].breakTime       = 0;
   g_zones[n].touches         = MathMax(1, touches);
   g_zones[n].state           = ZS_ACTIVE;
   return(g_zones[n].id);
  }

// Invalidation needs a decisive close -- same buffer AND body requirement
// as the breakout rule. A wick through a level does not kill it.
void UpdateBrokenZones(double close1, double body1, double atrStruct, datetime time1)
  {
   double buf = BreakoutBufferATR * atrStruct;
   bool decisive = (body1 >= MinBreakoutBodyATR * atrStruct);
   if(!decisive) return;

   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].state != ZS_ACTIVE && g_zones[i].state != ZS_FLIPPED) continue;
      if(g_zones[i].type > 0 && close1 > g_zones[i].hi + buf)
        { g_zones[i].state = ZS_BROKEN; g_zones[i].breakTime = time1; }
      if(g_zones[i].type < 0 && close1 < g_zones[i].lo - buf)
        { g_zones[i].state = ZS_BROKEN; g_zones[i].breakTime = time1; }
     }
  }

//----------------------------------------------------------------------
// Continuous structural cataloguing -- the target-supply fix.
// Each M15 bar, the bar that has just become swing-confirmable (it has
// SwingRightBars closed bars after it) is checked and, if it is a swing,
// its cluster zone is added to the map. Closed bars only, so a zone can
// never be known before the candles that formed it -- no lookahead.
//----------------------------------------------------------------------
bool IsSwingHighAt(int shift)
  {
   double h = iHigh(_Symbol, StructureTF, shift);
   for(int k = 1; k <= SwingLeftBars; k++)
      if(iHigh(_Symbol, StructureTF, shift + k) > h) return(false);
   for(int k = 1; k <= SwingRightBars; k++)
      if(iHigh(_Symbol, StructureTF, shift - k) > h) return(false);
   return(true);
  }

bool IsSwingLowAt(int shift)
  {
   double l = iLow(_Symbol, StructureTF, shift);
   for(int k = 1; k <= SwingLeftBars; k++)
      if(iLow(_Symbol, StructureTF, shift + k) < l) return(false);
   for(int k = 1; k <= SwingRightBars; k++)
      if(iLow(_Symbol, StructureTF, shift - k) < l) return(false);
   return(true);
  }

void ScanNewStructureZones(double atrStruct, datetime barTime)
  {
   int shift = SwingRightBars + 1;
   if(shift + SwingLeftBars + 1 >= Bars(_Symbol, StructureTF)) return;

   double hi, lo;
   int touches = 0, clusterBars = 0;
   datetime clusterStart = 0;
   datetime swingTime;

   if(IsSwingHighAt(shift))
     {
      swingTime = iTime(_Symbol, StructureTF, shift);
      if(BuildZoneFromSwingHigh(swingTime, atrStruct, hi, lo, touches, clusterBars, clusterStart))
         RegisterZone(+1, hi, lo, clusterStart, swingTime, touches, atrStruct, barTime);
     }
   if(IsSwingLowAt(shift))
     {
      swingTime = iTime(_Symbol, StructureTF, shift);
      if(BuildZoneFromSwingLow(swingTime, atrStruct, hi, lo, touches, clusterBars, clusterStart))
         RegisterZone(-1, hi, lo, clusterStart, swingTime, touches, atrStruct, barTime);
     }
  }

void StructureMapCounts(int &activeRes, int &activeSup, int &brokenN, int &flippedN)
  {
   activeRes = 0; activeSup = 0; brokenN = 0; flippedN = 0;
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].state == ZS_ACTIVE && g_zones[i].type > 0) activeRes++;
      if(g_zones[i].state == ZS_ACTIVE && g_zones[i].type < 0) activeSup++;
      if(g_zones[i].state == ZS_BROKEN)  brokenN++;
      if(g_zones[i].state == ZS_FLIPPED) flippedN++;
     }
  }

// Nearest valid unbroken opposing zone. No fallback to "last two swings":
// if nothing valid exists the setup is rejected, not given an invented target.
string ZoneStateName(ZONE_STATE s)
  {
   switch(s)
     {
      case ZS_ACTIVE:      return("ACTIVE");
      case ZS_FLIPPED:     return("FLIPPED");
      case ZS_BROKEN:      return("BROKEN");
      case ZS_INVALIDATED: return("INVALIDATED");
      default:             return("MERGED");
     }
  }

bool SelectStructureTarget(int direction, double entryPrice, double slDistance, double atrEntry,
                           datetime entryTime, double &targetPrice, int &targetId, double &nearEdgeOut,
                           string &noTargetReason)
  {
   int wantType = (direction > 0) ? +1 : -1;

   int    candIdx[];
   double candDist[];
   int    nCand = 0;
   int    nWrongSide = 0, nBroken = 0, nInvalid = 0, nDuplicate = 0, nRightTypeSeen = 0;

   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      double nearEdge = (direction > 0) ? g_zones[i].lo : g_zones[i].hi;
      double distATR  = MathAbs(nearEdge - entryPrice) / atrEntry;
      double rrIfUsed = (slDistance > 0) ? MathAbs(nearEdge - entryPrice) / slDistance : 0;
      string reason = "";

      // No lookahead: a level may only be targeted if the EA already knew
      // of it from candles that closed before this entry.
      if(g_zones[i].registered > entryTime)                    reason = "FUTURE_ZONE";
      else if(g_zones[i].id == g_entryZoneId)                  reason = "ENTRY_ZONE";
      else if(g_zones[i].type != wantType)                     reason = "WRONG_TYPE";
      else if(g_zones[i].hi <= g_zones[i].lo)                  reason = "INVALIDATED";
      else if(g_zones[i].state == ZS_BROKEN)                   reason = "ALREADY_BROKEN";
      else if(g_zones[i].state == ZS_INVALIDATED)              reason = "INVALIDATED";
      else if(g_zones[i].state == ZS_MERGED)                   reason = "DUPLICATE";
      else if(g_zones[i].state == ZS_FLIPPED)                  reason = "ENTRY_ZONE";
      else if(direction > 0 && g_zones[i].hi <= entryPrice)    reason = "WRONG_SIDE";
      else if(direction < 0 && g_zones[i].lo >= entryPrice)    reason = "WRONG_SIDE";

      if(g_zones[i].type == wantType) nRightTypeSeen++;
      if(reason == "WRONG_SIDE")      nWrongSide++;
      if(reason == "ALREADY_BROKEN")  nBroken++;
      if(reason == "INVALIDATED")     nInvalid++;
      if(reason == "DUPLICATE")       nDuplicate++;

      g_cTargetCandidates++;
      if(DebugStats)
         PrintFormat("TARGET_CANDIDATE | zoneID=%d | createdTime=%s | type=%s | zoneLow=%.2f | zoneHigh=%.2f | touches=%d | state=%s | distanceATR=%.2f | plannedRR=%.2f | status=%s | reason=%s",
                     g_zones[i].id, TimeToString(g_zones[i].created, TIME_DATE|TIME_MINUTES),
                     g_zones[i].type > 0 ? "RESISTANCE" : "SUPPORT",
                     g_zones[i].lo, g_zones[i].hi, g_zones[i].touches,
                     ZoneStateName(g_zones[i].state), distATR, rrIfUsed,
                     reason == "" ? "VALID" : "EXCLUDED", reason == "" ? "-" : reason);

      if(reason != "") continue;
      g_cValidTargets++;

      ArrayResize(candIdx,  nCand + 1);
      ArrayResize(candDist, nCand + 1);
      candIdx[nCand]  = i;
      candDist[nCand] = MathAbs(nearEdge - entryPrice);
      nCand++;
     }

   if(nCand == 0)
     {
      if(nRightTypeSeen == 0)          noTargetReason = (direction > 0) ? "NO_TARGET_NONE_ABOVE" : "NO_TARGET_NONE_BELOW";
      else if(nBroken >= nWrongSide && nBroken >= nInvalid && nBroken >= nDuplicate) noTargetReason = "NO_TARGET_ALL_BROKEN";
      else if(nInvalid >= nWrongSide && nInvalid >= nDuplicate)                      noTargetReason = "NO_TARGET_ALL_INVALID";
      else if(nDuplicate > nWrongSide)                                               noTargetReason = "NO_TARGET_ALL_DUPLICATES";
      else                              noTargetReason = (direction > 0) ? "NO_TARGET_NONE_ABOVE" : "NO_TARGET_NONE_BELOW";
      return(false);
     }

   // nearest valid zone wins
   int best = 0;
   for(int k = 1; k < nCand; k++)
      if(candDist[k] < candDist[best]) best = k;

   int bi = candIdx[best];
   double tol = DuplicateZoneATR * atrEntry;
   if(DebugStats)
      for(int k = 0; k < nCand; k++)
        {
         if(k == best) continue;
         int oi = candIdx[k];
         if(MathAbs(g_zones[oi].hi - g_zones[bi].hi) <= tol && MathAbs(g_zones[oi].lo - g_zones[bi].lo) <= tol)
            PrintFormat("TARGET_CANDIDATE | zoneID=%d | status=EXCLUDED | reason=DUPLICATE", g_zones[oi].id);
        }

   double nearEdge = (direction > 0) ? g_zones[bi].lo : g_zones[bi].hi;
   targetPrice = (direction > 0) ? nearEdge - TargetBufferATR * atrEntry
                                 : nearEdge + TargetBufferATR * atrEntry;
   targetId    = g_zones[bi].id;
   nearEdgeOut = nearEdge;
   return(true);
  }

//----------------------------------------------------------------------
// Zone from a confirmed StructureTF swing, padded by ZonePaddingATR.
//----------------------------------------------------------------------
double Median(double &values[], int n)
  {
   if(n <= 0) return(0);
   double copy[];
   ArrayResize(copy, n);
   ArrayCopy(copy, values, 0, 0, n);
   ArraySort(copy);
   if(n % 2 == 1) return(copy[n / 2]);
   return((copy[n / 2 - 1] + copy[n / 2]) / 2.0);
  }

void ClampZoneThickness(double zoneHigh, double &zoneLow, double atrStruct, bool resistance)
  {
   double thick = zoneHigh - zoneLow;
   double minT = MinZoneThickATR * atrStruct;
   double maxT = MaxZoneThickATR * atrStruct;
   if(thick < minT) thick = minT;
   if(thick > maxT) thick = maxT;
   zoneLow = zoneHigh - thick;
  }

// A level is a price area several candles agree on -- not one wick, and
// not "every bar that happens to sit nearby in time". A bar only joins
// the cluster if its own extreme comes within ZoneClusterATR of the
// swing's extreme, i.e. it actually interacted with the same level.
bool BuildZoneFromSwingHigh(datetime swingTime, double atrStruct, double &zoneHigh, double &zoneLow,
                            int &touches, int &clusterBars, datetime &clusterStart)
  {
   int shift = iBarShift(_Symbol, StructureTF, swingTime, false);
   double refHigh = iHigh(_Symbol, StructureTF, shift);
   double tol = ZoneClusterATR * atrStruct;

   double bodyTops[];
   int n = 0;
   double hi = 0;
   int minShift = shift, maxShift = shift;
   int total = Bars(_Symbol, StructureTF);

   for(int s = shift - MaxClusterBars; s <= shift + MaxClusterBars; s++)
     {
      if(s < 1 || s >= total) continue;
      double h = iHigh(_Symbol, StructureTF, s);
      if(MathAbs(refHigh - h) > tol) continue;   // must interact with the same price area

      ArrayResize(bodyTops, n + 1);
      bodyTops[n++] = MathMax(iOpen(_Symbol, StructureTF, s), iClose(_Symbol, StructureTF, s));
      hi = MathMax(hi, h);
      if(s < minShift) minShift = s;
      if(s > maxShift) maxShift = s;
     }

   touches = n;
   if(n < MinClusterTouches) return(false);

   clusterBars = maxShift - minShift + 1;
   clusterStart = iTime(_Symbol, StructureTF, maxShift);   // oldest bar in the cluster
   zoneHigh = hi;
   zoneLow  = Median(bodyTops, n);
   ClampZoneThickness(zoneHigh, zoneLow, atrStruct, true);
   return(true);
  }

bool BuildZoneFromSwingLow(datetime swingTime, double atrStruct, double &zoneHigh, double &zoneLow,
                           int &touches, int &clusterBars, datetime &clusterStart)
  {
   int shift = iBarShift(_Symbol, StructureTF, swingTime, false);
   double refLow = iLow(_Symbol, StructureTF, shift);
   double tol = ZoneClusterATR * atrStruct;

   double bodyBottoms[];
   int n = 0;
   double lo = 0;
   bool first = true;
   int minShift = shift, maxShift = shift;
   int total = Bars(_Symbol, StructureTF);

   for(int s = shift - MaxClusterBars; s <= shift + MaxClusterBars; s++)
     {
      if(s < 1 || s >= total) continue;
      double l = iLow(_Symbol, StructureTF, s);
      if(MathAbs(l - refLow) > tol) continue;

      ArrayResize(bodyBottoms, n + 1);
      bodyBottoms[n++] = MathMin(iOpen(_Symbol, StructureTF, s), iClose(_Symbol, StructureTF, s));
      if(first) { lo = l; first = false; }
      else      lo = MathMin(lo, l);
      if(s < minShift) minShift = s;
      if(s > maxShift) maxShift = s;
     }

   touches = n;
   if(n < MinClusterTouches) return(false);

   clusterBars = maxShift - minShift + 1;
   clusterStart = iTime(_Symbol, StructureTF, maxShift);
   zoneLow  = lo;
   zoneHigh = Median(bodyBottoms, n);
   // mirror clamp: hold the low fixed, move the high
   double thick = zoneHigh - zoneLow;
   double minT = MinZoneThickATR * atrStruct;
   double maxT = MaxZoneThickATR * atrStruct;
   if(thick < minT) thick = minT;
   if(thick > maxT) thick = maxT;
   zoneHigh = zoneLow + thick;
   return(true);
  }

//----------------------------------------------------------------------
// Debug drawing -- every zone/breakout/retest/sweep/entry/invalidation,
// so a run can be inspected visually instead of only through counters.
//----------------------------------------------------------------------
void DrawZoneRect(datetime t, double hi, double lo, color clr)
  {
   if(!DebugDraw) return;
   string name = StringFormat("SRQ_zone_%d", g_objCounter++);
   datetime t2 = t + PeriodSeconds(StructureTF) * (MaxBreakoutWaitBars + MaxPullbackWaitBars + MaxEngulfWaitBars);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void DrawMark(datetime t, double price, color clr, int arrowCode, string tag)
  {
   if(!DebugDraw) return;
   string name = StringFormat("SRQ_%s_%d", tag, g_objCounter++);
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  }

void DrawText(datetime t, double price, string text, color clr)
  {
   if(!DebugDraw) return;
   string name = StringFormat("SRQ_txt_%d", g_objCounter++);
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//----------------------------------------------------------------------
// StructureTF (M15) stage: H1 bias -> zone -> break
//----------------------------------------------------------------------
void ProcessStructureBar()
  {
   double atrStruct = ATRValue(g_atrStructHandle);
   if(atrStruct <= 0) return;

   double close1 = iClose(_Symbol, StructureTF, 1);
   double open1  = iOpen(_Symbol, StructureTF, 1);
   double body1  = MathAbs(close1 - open1);
   datetime time1 = iTime(_Symbol, StructureTF, 1);

   ScanNewStructureZones(atrStruct, time1);
   UpdateBrokenZones(close1, body1, atrStruct, time1);

   switch(g_state)
     {
      case STATE_SEARCH_TREND:
        {
         int bias = DetectTrend(TrendTF);
         if(bias == 0) return;
         g_cTrendDetected++;

         SwingPoint h1, h2, l1, l2;
         int touches = 0, clusterBars = 0;
         datetime clusterStart = 0;
         bool built = false;
         if(bias > 0 && FindLastTwoSwingHighs(StructureTF, h1, h2))
            built = BuildZoneFromSwingHigh(h1.time, atrStruct, g_zoneHigh, g_zoneLow, touches, clusterBars, clusterStart);
         else if(bias < 0 && FindLastTwoSwingLows(StructureTF, l1, l2))
            built = BuildZoneFromSwingLow(l1.time, atrStruct, g_zoneHigh, g_zoneLow, touches, clusterBars, clusterStart);
         else
            return;

         if(!built) { g_cZoneRejectedTouches++; return; }

         g_direction = bias;
         g_entryZoneId = RegisterZone(bias > 0 ? +1 : -1, g_zoneHigh, g_zoneLow, clusterStart,
                                      clusterStart, touches, atrStruct, time1);
         if(DebugStats)
            PrintFormat("%s ZONE | id=%d | touches=%d | bars=%d | high=%.2f | low=%.2f | width=%.2f ATR",
                        bias > 0 ? "RESISTANCE" : "SUPPORT", g_entryZoneId, touches, clusterBars,
                        g_zoneHigh, g_zoneLow, (g_zoneHigh - g_zoneLow) / atrStruct);
         DrawZoneRect(clusterStart, g_zoneHigh, g_zoneLow, bias > 0 ? clrDodgerBlue : clrOrange);

         g_cReachedBreakoutWait++;
         g_breakoutWaitBars = 0;
         g_state = STATE_WAIT_FOR_BREAKOUT;
         break;
        }

      case STATE_WAIT_FOR_BREAKOUT:
        {
         int bias = DetectTrend(TrendTF);
         if(bias != g_direction) { g_cH1BiasFlip++; DrawText(time1, close1, "H1 flip", clrGray); ResetSequence(); return; }

         g_breakoutWaitBars++;
         if(g_breakoutWaitBars > MaxBreakoutWaitBars) { g_cBreakoutWaitTimeout++; DrawText(time1, close1, "brkout timeout", clrGray); ResetSequence(); return; }

         bool broke = (g_direction > 0)
                      ? (close1 > g_zoneHigh + BreakoutBufferATR * atrStruct && body1 >= MinBreakoutBodyATR * atrStruct)
                      : (close1 < g_zoneLow  - BreakoutBufferATR * atrStruct && body1 >= MinBreakoutBodyATR * atrStruct);
         if(broke)
           {
            g_breakoutBodyATR = body1 / atrStruct;
            g_cBreakoutHit++;
            // this level has flipped and is now the setup's own zone --
            // it must never be offered back as a target
            for(int zi = 0; zi < ArraySize(g_zones); zi++)
               if(g_zones[zi].id == g_entryZoneId) { g_zones[zi].state = ZS_FLIPPED; break; }
            DrawMark(time1, close1, g_direction > 0 ? clrLime : clrRed, 217, "brk");
            g_pullbackWaitBars = 0;
            g_state = STATE_WAIT_FOR_PULLBACK;
           }
         break;
        }

      default:
         break; // pullback/sweep/pending stages run on EntryTF
     }
  }

//----------------------------------------------------------------------
// EntryTF (M5) stage: pullback -> sweep -> same/next-candle reclaim
//----------------------------------------------------------------------
void ProcessEntryBar()
  {
   double atrEntry = ATRValue(g_atrEntryHandle);
   if(atrEntry <= 0) return;

   double close1 = iClose(_Symbol, EntryTF, 1);
   double high1  = iHigh(_Symbol, EntryTF, 1);
   double low1   = iLow(_Symbol, EntryTF, 1);
   datetime time1 = iTime(_Symbol, EntryTF, 1);

   if(g_state == STATE_PENDING_ORDER) { ManagePending(); return; }
   if(g_state != STATE_WAIT_FOR_PULLBACK && g_state != STATE_WAIT_FOR_ENGULF) return;

   int bias = DetectTrend(TrendTF);
   if(bias != g_direction) { g_cH1BiasFlip++; DrawText(time1, close1, "H1 flip", clrGray); ResetSequence(); return; }

   if(g_state == STATE_WAIT_FOR_PULLBACK)
     {
      g_pullbackWaitBars++;
      if(g_pullbackWaitBars > MaxPullbackWaitBars) { g_cPullbackTimeout++; DrawText(time1, close1, "pullback timeout", clrGray); ResetSequence(); return; }

      bool tagged = (g_direction > 0) ? (low1 <= g_zoneHigh) : (high1 >= g_zoneLow);
      if(tagged)
        {
         g_cPullbackTag++;
         DrawMark(time1, g_direction > 0 ? low1 : high1, clrYellow, 159, "pullback");
         g_engulfWaitBars = 0;
         g_state = STATE_WAIT_FOR_ENGULF;
        }
      return;
     }

   // STATE_WAIT_FOR_ENGULF -- level interaction plus an engulfing candle,
   // entry on that candle's close. Penetration depth is measured for
   // research only and never rejects a setup.
   g_engulfWaitBars++;
   if(g_engulfWaitBars > MaxEngulfWaitBars) { g_cEngulfTimeout++; DrawText(time1, close1, "engulf timeout", clrGray); ResetSequence(); return; }

   double open1  = iOpen(_Symbol,  EntryTF, 1);
   double open2  = iOpen(_Symbol,  EntryTF, 2);
   double close2 = iClose(_Symbol, EntryTF, 2);
   double high2  = iHigh(_Symbol,  EntryTF, 2);
   double low2   = iLow(_Symbol,   EntryTF, 2);

   bool interacted;
   bool engulf;
   bool closeRightSide;
   double penetration;

   if(g_direction > 0)
     {
      interacted = (low1 <= g_zoneHigh) || (low2 <= g_zoneHigh);
      engulf = (close2 < open2) && (close1 > open1) && (open1 <= close2) && (close1 >= open2);
      closeRightSide = (close1 > g_zoneHigh);
      penetration = MathMax(0.0, g_zoneLow - MathMin(low1, low2)) / atrEntry;
     }
   else
     {
      interacted = (high1 >= g_zoneLow) || (high2 >= g_zoneLow);
      engulf = (close2 > open2) && (close1 < open1) && (open1 >= close2) && (close1 <= open2);
      closeRightSide = (close1 < g_zoneLow);
      penetration = MathMax(0.0, MathMax(high1, high2) - g_zoneHigh) / atrEntry;
     }

   if(interacted) g_cZoneInteractions++;
   if(!engulf) return;

   if(g_direction > 0) g_cBullishEngulfs++; else g_cBearishEngulfs++;

   if(!interacted)     { g_cEngulfRejNoZoneInteraction++; return; }
   if(!closeRightSide) { g_cEngulfRejCloseWrongSide++;    return; }

   g_cEngulfConfirmed++;
   g_penetrationATR = penetration;
   g_rejectLow  = MathMin(low1,  low2);
   g_rejectHigh = MathMax(high1, high2);

   if(DebugStats)
      PrintFormat("%s ENGULF | zone=%.2f-%.2f | penetration=%.2fATR | bodyEngulf=yes | close%sZone=yes | ENTRY",
                  g_direction > 0 ? "BULL" : "BEAR", g_zoneLow, g_zoneHigh, penetration,
                  g_direction > 0 ? "Above" : "Below");

   DrawMark(time1, close1, g_direction > 0 ? clrLime : clrRed, 233, "engulf");
   TryEnter(close1, atrEntry);
  }

//----------------------------------------------------------------------
// Trade construction
//----------------------------------------------------------------------
int CountOwnPositions()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
     }
   return(count);
  }

double CalcLots(double slDistance)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0) return(0.0);

   double lots = riskMoney / (slDistance / tickSize * tickValue);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return(lots);
  }

// reclaimClose: the bar close that satisfied the reclaim -- "BUY AT CLOSE".
void TryEnter(double reclaimClose, double atrEntry)
  {
   if(CountOwnPositions() >= MaxPositions) { g_cTradeSkippedMaxPos++; ResetSequence(); return; }

   double sl = (g_direction > 0) ? g_rejectLow  - SLBufferATR * atrEntry
                                  : g_rejectHigh + SLBufferATR * atrEntry;
   double entry = reclaimClose;
   double slDistance = MathAbs(entry - sl);
   if(slDistance <= 0) { ResetSequence(); return; }

   if(DebugStats)
      PrintFormat("ENTRY_CANDIDATE | %s | entryPrice=%.2f | entryZoneID=%d",
                  g_direction > 0 ? "BUY" : "SELL", entry, g_entryZoneId);

   int actRes = 0, actSup = 0, brokenN = 0, flippedN = 0;
   StructureMapCounts(actRes, actSup, brokenN, flippedN);
   if(DebugStats)
     {
      PrintFormat("STRUCTURE_MAP | activeResistance=%d | activeSupport=%d | broken=%d | flipped=%d | merged=%d | total=%d",
                  actRes, actSup, brokenN, flippedN, g_cZonesMerged, ArraySize(g_zones));
      PrintFormat("TARGET_SEARCH | %s | entryPrice=%.2f | eligibleOpposingZones=%d",
                  g_direction > 0 ? "BUY" : "SELL", entry, g_direction > 0 ? actRes : actSup);
     }

   double target = 0, nearEdge = 0;
   int targetId = -1;
   string noTargetReason = "";
   datetime entryTime = iTime(_Symbol, EntryTF, 0);
   bool haveStructTarget = SelectStructureTarget(g_direction, entry, slDistance, atrEntry, entryTime,
                                                 target, targetId, nearEdge, noTargetReason);
   double rr = haveStructTarget ? MathAbs(target - entry) / slDistance : 0;

   if(haveStructTarget)
     {
      g_cTargetFound++;
      if(DebugStats)
         PrintFormat("TARGET_SELECTED | zoneID=%d | targetPrice=%.2f | stopPrice=%.2f | riskDistance=%.2f | rewardDistance=%.2f | plannedRR=%.2f",
                     targetId, target, sl, slDistance, MathAbs(target - entry), rr);
     }
   else
     {
      g_cNoValidTarget++;
      if(DebugStats) PrintFormat("NO_VALID_STRUCTURE_TARGET | %s", noTargetReason);
     }

   double tp = 0;
   switch(TPMode)
     {
      case TP_STRUCTURE:
         if(!haveStructTarget) { ResetSequence(); return; }
         tp = target;
         break;
      case TP_FIXED_RR:
         tp = (g_direction > 0) ? entry + FixedRR * slDistance : entry - FixedRR * slDistance;
         break;
      case TP_HYBRID:
      default:
         // TP is the selected structure target itself; MinRR stays active
         // so this run isolates whether target *selection* was the choke.
         if(!haveStructTarget) { ResetSequence(); return; }
         if(rr < MinRR) { g_cRRFail++; g_cTradeSkippedRR++; ResetSequence(); return; }
         g_cRRPass++;
         tp = target;
         break;
     }

   double lots = CalcLots(slDistance);
   if(lots <= 0) { g_cTradeSkippedLots++; ResetSequence(); return; }

   g_tradeCounter++;
   if(DebugTradeLog)
      PrintFormat("TRADE #%d %s\nH1 Bias: %s\nM15 Zone: %.2f-%.2f\nBreakout Strength: %.2f ATR\nPullback Bars: %d\nPenetration (research only): %.2f ATR\nEngulf Close: %.2f\nEntry: %.2f\nSL: %.2f\nRisk: %.2f\nTP: %.2f\nRR: %.2f",
                  g_tradeCounter, g_direction > 0 ? "BUY" : "SELL",
                  BiasLabel(g_direction), g_zoneLow, g_zoneHigh,
                  g_breakoutBodyATR, g_pullbackWaitBars, g_penetrationATR,
                  reclaimClose, entry, sl, slDistance, tp, (tp - entry != 0 ? MathAbs(tp - entry) / slDistance : 0));

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.symbol   = _Symbol;
   req.volume   = lots;
   req.magic    = MagicNumber;
   req.sl       = NormalizeDouble(sl, _Digits);
   req.tp       = NormalizeDouble(tp, _Digits);
   req.deviation= 20;

   if(EntryMode == ENTRY_MARKET_ON_CONFIRM)
     {
      req.action = TRADE_ACTION_DEAL;
      req.type   = (g_direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price  = (g_direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
        {
         g_cTradeSent++;
         DrawMark(iTime(_Symbol, EntryTF, 0), entry, g_direction > 0 ? clrLime : clrRed, g_direction > 0 ? 233 : 234, "entry");
        }
      ResetSequence();
     }
   else
     {
      // Broker requires a stop order to sit at least SYMBOL_TRADE_STOPS_LEVEL
      // points from the current price.
      long stopsLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stopsLevelPoints * _Point;
      double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double stopEntry = entry + EntryBufferATR * atrEntry;
      if(g_direction > 0 && stopEntry < curAsk + minDist) stopEntry = curAsk + minDist;
      if(g_direction < 0 && stopEntry > curBid - minDist) stopEntry = curBid - minDist;

      req.action = TRADE_ACTION_PENDING;
      req.type   = (g_direction > 0) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      req.price  = NormalizeDouble(stopEntry, _Digits);
      req.type_time = ORDER_TIME_SPECIFIED;
      req.expiration = iTime(_Symbol, EntryTF, 0) + PendingExpiryBars * PeriodSeconds(EntryTF);
      if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
        {
         g_cTradeSent++;
         g_pendingTicket = res.order;
         g_state = STATE_PENDING_ORDER;
        }
      else
         ResetSequence();
     }
  }

void CancelPending()
  {
   if(g_pendingTicket == 0) return;
   if(OrderSelect(g_pendingTicket))
     {
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = g_pendingTicket;
      bool sent = OrderSend(req, res);
     }
   g_pendingTicket = 0;
  }

void ManagePending()
  {
   if(g_pendingTicket == 0) { ResetSequence(); return; }
   if(!OrderSelect(g_pendingTicket))
     {
      g_pendingTicket = 0;
      ResetSequence();
     }
  }

//----------------------------------------------------------------------
// Open-position management: breakeven + ATR trail
//----------------------------------------------------------------------
void ManageOpenPositions()
  {
   double atrEntry = ATRValue(g_atrEntryHandle);
   if(atrEntry <= 0) return;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double curSL = sl;
      double price = (type == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double riskDist = MathAbs(openPrice - sl);
      if(riskDist <= 0) continue;
      double rMultiple = (type == POSITION_TYPE_BUY)
                          ? (price - openPrice) / riskDist
                          : (openPrice - price) / riskDist;

      double newSL = curSL;

      if(rMultiple >= BreakevenR)
        {
         if(type == POSITION_TYPE_BUY && (curSL < openPrice))
            newSL = openPrice;
         else if(type == POSITION_TYPE_SELL && (curSL > openPrice || curSL == 0))
            newSL = openPrice;
        }

      if(rMultiple >= TrailStartR)
        {
         double trail = TrailATRMult * atrEntry;
         if(type == POSITION_TYPE_BUY)
           {
            double candidate = price - trail;
            if(candidate > newSL) newSL = candidate;
           }
         else
           {
            double candidate = price + trail;
            if(newSL == 0 || candidate < newSL) newSL = candidate;
           }
        }

      if(newSL != curSL && newSL != 0)
        {
         MqlTradeRequest req;
         MqlTradeResult  res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action   = TRADE_ACTION_SLTP;
         req.symbol   = _Symbol;
         req.position = ticket;
         req.sl       = NormalizeDouble(newSL, _Digits);
         req.tp       = tp;
         bool sent = OrderSend(req, res);
        }
     }
  }

//----------------------------------------------------------------------
void OnTick()
  {
   ManageOpenPositions();

   if(IsNewBar(StructureTF, g_lastStructBarTime))
      ProcessStructureBar();

   if(IsNewBar(EntryTF, g_lastEntryBarTime))
      ProcessEntryBar();
  }
//+------------------------------------------------------------------+
