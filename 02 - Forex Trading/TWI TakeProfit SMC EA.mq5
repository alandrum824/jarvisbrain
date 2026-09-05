//+------------------------------------------------------------------+
//|                                     TWI_TakeProfit_SMC_EA.mq5    |
//|  TakeProfit Exclusive style SMC engine                           |
//|  BOS / CHoCH / Order Block / FVG / Weak-Strong Liquidity / T-P2  |
//|                                                                  |
//|  Built from TakeProfit / Forex Blog chart language:              |
//|   - CHoCH + BOS structure labels                                 |
//|   - Demand (teal/purple) and Supply (pink/red) boxes             |
//|   - Weak High / Strong Low liquidity tags                        |
//|   - Equilibrium (50%) dotted line                                |
//|   - Channel break + RSI "Bear/Bull" confluence                   |
//|   - Partial TP1 then runner T-P2 at opposing liquidity           |
//+------------------------------------------------------------------+
#property copyright "TWI / Juvenile Virtue"
#property version   "2.30"
#property strict
#property description "SMC EA: BOS/CHoCH + OB + FVG + multi-TP (T-P2). Visuals match TakeProfit Exclusive charts."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   account;

//====================================================================
// INPUTS
//====================================================================
enum ENUM_LOT_MODE { LOT_FIXED = 0, LOT_RISK_PERCENT = 1 };

input group "=== Core ==="
input ulong             InpMagic              = 20260903;
input string            InpTradeComment       = "TWI_TP_SMC";
input ENUM_LOT_MODE     InpLotMode            = LOT_RISK_PERCENT;
input double            InpFixedLot           = 0.10;
input double            InpRiskPercent        = 0.50;      // % of equity per full position
input double            InpMaxActualRiskPercent = 0.60;    // hard ceiling; order is refused above this
input int               InpMaxTrades          = 2;
input int               InpSlippagePoints     = 30;

input group "=== Structure (BOS / CHoCH) ==="
input int               InpSwingLeft          = 5;
input int               InpSwingRight         = 5;
input int               InpStructureLookback  = 300;
input bool              InpTradeCHoCH         = true;      // reversal after Change of Character
input bool              InpTradeBOS           = true;      // continuation after Break of Structure
input int               InpBarsAfterShift     = 40;        // how fresh a shift must be to trade

input group "=== Zones (OB / FVG / S&D) ==="
input bool              InpUseOrderBlocks     = true;
input bool              InpUseFVG             = true;
input int               InpOBLookback         = 80;
input int               InpFVGLookback        = 50;
input int               InpMinFVGPoints       = 20;        // ignore tiny gaps
input double            InpZoneBufferATR      = 0.15;      // extra touch buffer as ATR fraction
input bool              InpRequireZoneTouch   = true;      // must tap OB or FVG
input bool              InpUseEquilibrium     = true;      // premium/discount 50% filter

input group "=== Confluence ==="
input bool              InpUseRSI             = true;      // matches "Bear" label on 2nd screenshot
input int               InpRSIPeriod          = 14;
input double            InpRSIOverbought      = 62.0;
input double            InpRSIOversold        = 38.0;
input bool              InpUseChannelBreak    = true;      // rising/falling channel break
input int               InpChannelPivots      = 4;
input bool              InpUseRejectionCandle = true;

input group "=== Sessions (server time) ==="
input bool              InpUseSessionFilter   = true;
input int               InpLondonStart        = 8;
input int               InpLondonEnd          = 12;
input int               InpNYStart            = 13;
input int               InpNYEnd              = 17;
input bool              InpTradeLondon        = true;
input bool              InpTradeNY            = true;
input bool              InpCloseFriday        = true;
input int               InpFridayCloseHour    = 20;

input group "=== Risk / Prop ==="
// Gold on this broker is 2-digit: normal spread runs ~250-265 points
// (~$2.50) and news spikes hit ~1480. The original 25 blocked 100% of
// 2024 bars in the Aug 2026 test -- the strategy never ran once.
input int               InpMaxSpreadPoints    = 400;
input double            InpDailyLossPercent   = 3.0;       // halt if daily floating+closed <= -X%
input double            InpDailyProfitPercent = 4.0;       // optional halt after +X%
input bool              InpUseDailyProfitHalt = false;
input int               InpMaxHoldHours       = 36;
input int               InpSLBufferPoints     = 80;        // beyond OB / swing
input double            InpTP1_RR             = 1.50;
input double            InpTP2_RR             = 3.00;      // T-P2 runner
input double            InpTP1_ClosePercent   = 50.0;      // close half at TP1
input bool              InpMoveBE_AtTP1       = true;
input int               InpBE_OffsetPoints    = 20;
input bool              InpUseTrailAfterTP1   = true;
input int               InpTrailStartPoints   = 400;
input int               InpTrailStepPoints    = 150;

input group "=== Exit geometry experiment ==="
enum ENUM_EXIT_VARIANT { EXIT_A_CONTROL, EXIT_B_BUFFER, EXIT_C_FULL };
input ENUM_EXIT_VARIANT InpExitVariant     = EXIT_A_CONTROL;
input double            InpSLBufferATRMult = 0.05;   // execution breathing room, not extra risk
input double            InpSLBufferATRCap  = 0.15;   // upper safety cap on that buffer
input double            InpMinGeometryRR   = 1.0;    // reject setups whose primary target is nearer than the stop
input double            InpPartial1AtR     = 1.0;    // first partial trigger
input double            InpPartial1Pct     = 40.0;
input double            InpPartial2Pct     = 30.0;
input double            InpTrailStartR     = 1.25;   // no trailing before this

input group "=== Confluence scoring ==="
// Core requirements are STRUCTURE + LOCATION + PRICE ACTION. Everything
// else grades the candidate rather than vetoing it.
input int               InpMinConfluenceScore = 6;
input bool              InpUseScoreGate       = true;      // false = core-only, for diagnosis

input group "=== Diagnostics ==="
input bool              InpDebugStats         = true;      // funnel counters printed on deinit
input bool              InpLogEverySetup      = true;      // per-candidate shadow evaluation lines

input group "=== Visuals ==="
input bool              InpDrawObjects        = true;
input bool              InpDrawDashboard      = true;
input color             InpBullColor          = clrMediumSeaGreen;
input color             InpBearColor          = clrLightCoral;
input color             InpDemandBox          = C'40,90,90';
input color             InpSupplyBox          = C'140,60,80';
input color             InpEqColor            = clrSilver;

//====================================================================
// TYPES
//====================================================================
enum ENUM_TREND { TREND_NONE = 0, TREND_BULL = 1, TREND_BEAR = -1 };

struct Swing
  {
   datetime t;
   double   price;
   int      bar;
   bool     isHigh;
   bool     isWeak;     // swept / taken = weak, held = strong
  };

struct StructureEvent
  {
   datetime t;
   double   level;
   int      bar;
   int      dir;        // +1 bull, -1 bear
   bool     isCHoCH;
   bool     used;
  };

struct Zone
  {
   datetime t1;
   datetime t2;
   double   top;
   double   bot;
   int      dir;        // +1 demand (buy), -1 supply (sell)
   bool     isOB;
   bool     isFVG;
   bool     mitigated;
   int      bar;
  };

//====================================================================
// STATE
//====================================================================
Swing            g_highs[];
Swing            g_lows[];
StructureEvent   g_events[];
Zone             g_zones[];

ENUM_TREND       g_trend       = TREND_NONE;
datetime         g_lastBar     = 0;
datetime         g_dayStart    = 0;
double           g_dayStartEq  = 0;
bool             g_haltDay     = false;
string           g_pfx         = "TWI_TP_";
int              g_rsiHandle   = INVALID_HANDLE;
int              g_atrHandle   = INVALID_HANDLE;   // cached; see AtrValue()
int              g_atrM5Handle = INVALID_HANDLE;   // M5 ATR for the stop buffer

// Per-position forensics: MFE/MAE in R, so a loss that was once deeply in
// profit is distinguishable from one that never worked at all.
struct TradeRec
  {
   ulong    posId;
   int      dir;
   double   entry;
   double   rawSL;
   double   finalSL;
   double   riskPrice;     // entry -> finalSL distance
   double   riskMoney;
   double   tp1, tp2, tp3;
   double   rr1, rr2, rr3;
   double   mfeR, maeR;
   double   initialVolume;
   bool     partial1Done, partial2Done;
   bool     beMoved;
   datetime opened;
  };
TradeRec g_trades[];

//--- diagnostic funnel counters (logging only, no effect on trading)
long g_dBars=0, g_dSpreadBlocked=0, g_dSessionBlocked=0, g_dHaltBlocked=0;
long g_dFridayBlocked=0, g_dMaxTradesBlocked=0, g_dReachedEntries=0;
long g_dBuyShift=0, g_dSellShift=0;
long g_dBuyRejEq=0, g_dBuyRejRSI=0, g_dBuyRejChan=0, g_dBuyRejRej=0, g_dBuyRejZone=0;
long g_dSellRejEq=0, g_dSellRejRSI=0, g_dSellRejChan=0, g_dSellRejRej=0, g_dSellRejZone=0;
long g_dOpenBuy=0, g_dOpenSell=0, g_dOrderFail=0;
long g_dEventsSeen=0, g_dZonesSeen=0, g_dAtrZero=0;
long g_dSpreadMin=1000000, g_dSpreadMax=0, g_dSpreadSum=0, g_dSpreadN=0;

//--- new architecture funnel: structure -> location -> price action -> score
long g_fRawEvents=0, g_fBOSBull=0, g_fBOSBear=0, g_fCHoCHBull=0, g_fCHoCHBear=0;
long g_fLocValid=0, g_fZoneTouch=0, g_fBrokenRetest=0, g_fKeyLevelRetest=0;
long g_fPAConfirm=0, g_fBullEngulf=0, g_fBearEngulf=0, g_fRejCandle=0;
long g_fChannelConf=0, g_fEqFavorable=0, g_fRSIBullAligned=0, g_fRSIBearAligned=0;
long g_fCoreSetupsBuy=0, g_fCoreSetupsSell=0, g_fScorePass=0, g_fScoreFail=0;
long g_fEntriesBuy=0, g_fEntriesSell=0;
long g_fOldLogicWouldAccept=0, g_fNewLogicAccepts=0, g_fOnlyNewAccepts=0;
long g_fCandidateId=0;
long g_fScoreHist[15];   // score distribution 0..14

//--- exit geometry experiment counters
long   g_gGeometryReject=0;
double g_gRejectRRSum=0;
long   g_gClosed=0, g_gWins=0, g_gLosses=0;
double g_gSumWinR=0, g_gSumLossR=0, g_gSumMFE=0, g_gSumMAE=0;
long   g_gLossesWithMFE1R=0;   // losers that were once >= +1R

//--- risk integrity counters
long   g_riskRejectMinLot=0, g_riskRejectGuard=0, g_riskModelMismatch=0;
double g_riskPctSum=0, g_riskPctMin=99999, g_riskPctMax=0;
long   g_riskPctN=0;

//====================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber((long)InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   ArrayResize(g_highs, 0);
   ArrayResize(g_lows, 0);
   ArrayResize(g_events, 0);
   ArrayResize(g_zones, 0);

   if(InpUseRSI)
     {
      g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
      if(g_rsiHandle == INVALID_HANDLE)
        {
         Print("RSI handle failed");
         return INIT_FAILED;
        }
     }

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("ATR handle failed");
      return INIT_FAILED;
     }
   g_atrM5Handle = iATR(_Symbol, PERIOD_M5, 14);
   if(g_atrM5Handle == INVALID_HANDLE)
     {
      Print("M5 ATR handle failed");
      return INIT_FAILED;
     }

   g_dayStart   = iTime(_Symbol, PERIOD_D1, 0);
   g_dayStartEq = account.Equity();
   EventSetTimer(2);
   Print("TWI TakeProfit SMC EA initialized on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_rsiHandle != INVALID_HANDLE)
      IndicatorRelease(g_rsiHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DeleteAllObjects();

   if(!InpDebugStats) return;
   double avgSpread = (g_dSpreadN > 0) ? (double)g_dSpreadSum / g_dSpreadN : 0;
   double avgEvents = (g_dBars > 0) ? (double)g_dEventsSeen / g_dBars : 0;
   double avgZones  = (g_dBars > 0) ? (double)g_dZonesSeen  / g_dBars : 0;

   PrintFormat("=== SMC FUNNEL ===\nATR zero-reads (should be 0): %d\nBars processed: %d\nSpread points seen: min=%d avg=%.1f max=%d (limit=%d)\nBlocked by spread: %d\nBlocked by session: %d\nBlocked by daily halt: %d\nBlocked by Friday close: %d\nBlocked by max trades: %d\nReached TryEntries: %d\nAvg structure events per bar: %.2f\nAvg zones per bar: %.2f",
               g_dAtrZero, g_dBars, g_dSpreadMin, avgSpread, g_dSpreadMax, InpMaxSpreadPoints,
               g_dSpreadBlocked, g_dSessionBlocked, g_dHaltBlocked, g_dFridayBlocked,
               g_dMaxTradesBlocked, g_dReachedEntries, avgEvents, avgZones);

   string hist = "";
   for(int s = 0; s <= 14; s++)
      if(g_fScoreHist[s] > 0) hist += StringFormat("%d:%d ", s, g_fScoreHist[s]);

   PrintFormat("=== ARCHITECTURE FUNNEL (core + score) ===\nRaw structure events: %d\n  BOS bull: %d | BOS bear: %d | CHoCH bull: %d | CHoCH bear: %d\nValid location: %d (zoneTouch=%d brokenRetest=%d keyLevel=%d)\nPrice-action confirmations: %d (bullEngulf=%d bearEngulf=%d rejectionBar=%d)\nChannel confirmations: %d\nEquilibrium favorable: %d\nRSI aligned: bull=%d bear=%d\nCore setups: BUY=%d SELL=%d\nScore pass: %d | score fail: %d\nScore distribution: %s\nEntries: BUY=%d SELL=%d",
               g_fRawEvents, g_fBOSBull, g_fBOSBear, g_fCHoCHBull, g_fCHoCHBear,
               g_fLocValid, g_fZoneTouch, g_fBrokenRetest, g_fKeyLevelRetest,
               g_fPAConfirm, g_fBullEngulf, g_fBearEngulf, g_fRejCandle,
               g_fChannelConf, g_fEqFavorable, g_fRSIBullAligned, g_fRSIBearAligned,
               g_fCoreSetupsBuy, g_fCoreSetupsSell, g_fScorePass, g_fScoreFail,
               hist == "" ? "(none)" : hist,
               g_fEntriesBuy, g_fEntriesSell);

   PrintFormat("=== ARCHITECTURE COMPARISON ===\nCandidates evaluated: %d\nOLD all-AND logic would accept: %d\nNEW core+score logic accepts: %d\nAccepted by NEW only: %d",
               g_fCandidateId, g_fOldLogicWouldAccept, g_fNewLogicAccepts, g_fOnlyNewAccepts);

   double avgWinR  = (g_gWins   > 0) ? g_gSumWinR  / g_gWins   : 0;
   double avgLossR = (g_gLosses > 0) ? g_gSumLossR / g_gLosses : 0;
   double expR     = (g_gClosed > 0) ? (g_gSumWinR + g_gSumLossR) / g_gClosed : 0;
   double pfR      = (g_gSumLossR != 0) ? g_gSumWinR / MathAbs(g_gSumLossR) : 0;
   double avgMFE   = (g_gClosed > 0) ? g_gSumMFE / g_gClosed : 0;
   double avgMAE   = (g_gClosed > 0) ? g_gSumMAE / g_gClosed : 0;
   double avgRejRR = (g_gGeometryReject > 0) ? g_gRejectRRSum / g_gGeometryReject : 0;

   double avgRiskPct = (g_riskPctN > 0) ? g_riskPctSum / g_riskPctN : 0;
   PrintFormat("=== RISK INTEGRITY ===\nEquity at end: %.2f | requested risk %.2f%% | ceiling %.2f%%\nOrders sized: %d\nActual risk %%: min %.3f | avg %.3f | max %.3f\nRejected (min lot would exceed risk): %d\nRejected (risk guard): %d\nRisk-model mismatches (stop-outs not near -1R): %d",
               account.Equity(), InpRiskPercent, InpMaxActualRiskPercent,
               g_riskPctN,
               g_riskPctN > 0 ? g_riskPctMin : 0, avgRiskPct, g_riskPctMax,
               g_riskRejectMinLot, g_riskRejectGuard, g_riskModelMismatch);

   PrintFormat("=== EXIT GEOMETRY (variant %s) ===\nClosed deals: %d | wins %d | losses %d | win rate %.1f%%\nAvg win %.2fR | avg loss %.2fR\nExpectancy %.3fR per deal | R-based PF %.2f\nAvg MFE %.2fR | avg MAE %.2fR\nLosers that reached +1R before failing: %d of %d\nGeometry rejects: %d (avg RR of rejected %.2f)",
               InpExitVariant == EXIT_A_CONTROL ? "A_CONTROL" : (InpExitVariant == EXIT_B_BUFFER ? "B_BUFFER" : "C_FULL"),
               g_gClosed, g_gWins, g_gLosses,
               g_gClosed > 0 ? 100.0 * g_gWins / g_gClosed : 0,
               avgWinR, avgLossR, expR, pfR, avgMFE, avgMAE,
               g_gLossesWithMFE1R, g_gLosses,
               g_gGeometryReject, avgRejRR);

   if(g_fEntriesBuy + g_fEntriesSell == 0)
      Print("ZERO_TRADE_DIAGNOSTIC | no entries taken -- see the funnel above for which condition blocked candidates. No rule was auto-loosened to manufacture a trade.");

   PrintFormat("=== SMC SIGNALS (legacy gates, diagnostic only) ===\nBUY shift found: %d\n  rejected equilibrium: %d\n  rejected RSI: %d\n  rejected channel: %d\n  rejected candle: %d\n  rejected zone touch: %d\n  OpenBuy called: %d\nSELL shift found: %d\n  rejected equilibrium: %d\n  rejected RSI: %d\n  rejected channel: %d\n  rejected candle: %d\n  rejected zone touch: %d\n  OpenSell called: %d\nOrder send failures: %d",
               g_dBuyShift, g_dBuyRejEq, g_dBuyRejRSI, g_dBuyRejChan, g_dBuyRejRej, g_dBuyRejZone, g_dOpenBuy,
               g_dSellShift, g_dSellRejEq, g_dSellRejRSI, g_dSellRejChan, g_dSellRejRej, g_dSellRejZone, g_dOpenSell,
               g_dOrderFail);
  }

// Register fills and score exits. MFE/MAE come from the running tracker so
// a loser that was once deeply in profit is distinguishable from one that
// never worked -- that difference decides whether to fix stops or management.
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong posId    = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   if(entryType == DEAL_ENTRY_IN)
     {
      if(FindTradeRec(posId) >= 0) return;      // already tracked (TP1/TP2 split)
      double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double sl    = HistoryDealGetDouble(trans.deal, DEAL_SL);
      double vol   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double tp    = HistoryDealGetDouble(trans.deal, DEAL_TP);
      int dir = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? +1 : -1;

      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double riskMoney = 0;
      if(sl > 0 && tickSize > 0)
         riskMoney = MathAbs(price - sl) / tickSize * tickValue * vol;
      RegisterTrade(posId, dir, price, sl, sl, riskMoney, vol, tp, tp, 0);
      return;
     }

   if(entryType == DEAL_ENTRY_OUT)
     {
      int ti = FindTradeRec(posId);
      if(ti < 0) return;
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      double realizedR = (g_trades[ti].riskMoney > 0) ? profit / g_trades[ti].riskMoney : 0;
      string reason = (profit >= 0) ? "TARGET_OR_PARTIAL" : "STOP_OR_ADVERSE";

      g_gClosed++;
      if(profit >= 0) { g_gWins++;   g_gSumWinR  += realizedR; }
      else            { g_gLosses++; g_gSumLossR += realizedR;
                        if(g_trades[ti].mfeR >= 1.0) g_gLossesWithMFE1R++;
                        // Validation: a genuine stop-out should land near -1R.
                        // Anything far outside that means the risk model and
                        // the actual fills disagree -- do not trust the report.
                        if(g_trades[ti].maeR <= -0.98 && (realizedR < -1.25 || realizedR > -0.75))
                           g_riskModelMismatch++; }
      g_gSumMFE += g_trades[ti].mfeR;
      g_gSumMAE += g_trades[ti].maeR;

      if(InpDebugStats)
         PrintFormat("TRADE_RESULT | %s | entry=%.2f | rawSL=%.2f | finalSL=%.2f | riskPts=%.2f | risk$=%.2f | TP1=%.2f | plannedRR1=%.2f | MFE=%.2fR | MAE=%.2fR | exit=%s | realizedR=%.2f | realized$=%.2f",
                     g_trades[ti].dir > 0 ? "BUY" : "SELL",
                     g_trades[ti].entry, g_trades[ti].rawSL, g_trades[ti].finalSL,
                     g_trades[ti].riskPrice, g_trades[ti].riskMoney,
                     g_trades[ti].tp1, g_trades[ti].rr1,
                     g_trades[ti].mfeR, g_trades[ti].maeR,
                     reason, realizedR, profit);
     }
  }

void OnTimer()
  {
   if(InpDrawDashboard)
      DrawDashboard();
  }

void OnTick()
  {
   if(!IsNewBar())
     {
      ManageOpenPositions();
      return;
     }

   g_dBars++;
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spr < g_dSpreadMin) g_dSpreadMin = spr;
   if(spr > g_dSpreadMax) g_dSpreadMax = spr;
   g_dSpreadSum += spr;
   g_dSpreadN++;

   ResetDailyIfNeeded();
   if(g_haltDay)
     {
      g_dHaltBlocked++;
      ManageOpenPositions();
      return;
     }

   ScanStructure();
   ScanZones();
   g_dEventsSeen += ArraySize(g_events);
   g_dZonesSeen  += ArraySize(g_zones);
   if(InpDrawObjects)
      RedrawChart();

   if(!SpreadOK())
     {
      g_dSpreadBlocked++;
      ManageOpenPositions();
      return;
     }
   if(InpUseSessionFilter && !InSession())
     {
      g_dSessionBlocked++;
      ManageOpenPositions();
      return;
     }
   if(InpCloseFriday && IsFridayClose())
     {
      g_dFridayBlocked++;
      CloseAll("Friday close");
      ManageOpenPositions();
      return;
     }
   if(CountOurPositions() >= InpMaxTrades)
     {
      g_dMaxTradesBlocked++;
      ManageOpenPositions();
      return;
     }

   g_dReachedEntries++;
   TryEntriesNew();
   ManageOpenPositions();
  }

//====================================================================
// BAR / FILTERS
//====================================================================
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_lastBar)
      return false;
   g_lastBar = t;
   return true;
  }

void ResetDailyIfNeeded()
  {
   datetime d = iTime(_Symbol, PERIOD_D1, 0);
   if(d != g_dayStart)
     {
      g_dayStart   = d;
      g_dayStartEq = account.Equity();
      g_haltDay    = false;
     }

   if(g_dayStartEq <= 0)
      return;

   double pnlPct = 100.0 * (account.Equity() - g_dayStartEq) / g_dayStartEq;
   if(pnlPct <= -MathAbs(InpDailyLossPercent))
     {
      if(!g_haltDay)
         Print("Daily loss halt at ", DoubleToString(pnlPct, 2), "%");
      g_haltDay = true;
     }
   if(InpUseDailyProfitHalt && pnlPct >= MathAbs(InpDailyProfitPercent))
     {
      if(!g_haltDay)
         Print("Daily profit halt at ", DoubleToString(pnlPct, 2), "%");
      g_haltDay = true;
     }
  }

bool SpreadOK()
  {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpreadPoints);
  }

bool InSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool lon = InpTradeLondon && (h >= InpLondonStart && h < InpLondonEnd);
   bool ny  = InpTradeNY     && (h >= InpNYStart    && h < InpNYEnd);
   return (lon || ny);
  }

bool IsFridayClose()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour);
  }

int CountOurPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == (long)InpMagic)
         n++;
     }
   return n;
  }

//====================================================================
// STRUCTURE
//====================================================================
void ScanStructure()
  {
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   int need = MathMin(bars - InpSwingRight - 2, InpStructureLookback);
   if(need < InpSwingLeft + InpSwingRight + 10)
      return;

   ArrayResize(g_highs, 0);
   ArrayResize(g_lows, 0);
   ArrayResize(g_events, 0);

   for(int i = need; i >= InpSwingRight; i--)
     {
      if(IsSwingHigh(i))
        {
         Swing s;
         s.t      = iTime(_Symbol, PERIOD_CURRENT, i);
         s.price  = iHigh(_Symbol, PERIOD_CURRENT, i);
         s.bar    = i;
         s.isHigh = true;
         s.isWeak = false;
         int n = ArraySize(g_highs);
         ArrayResize(g_highs, n + 1);
         g_highs[n] = s;
        }
      if(IsSwingLow(i))
        {
         Swing s;
         s.t      = iTime(_Symbol, PERIOD_CURRENT, i);
         s.price  = iLow(_Symbol, PERIOD_CURRENT, i);
         s.bar    = i;
         s.isHigh = false;
         s.isWeak = false;
         int n = ArraySize(g_lows);
         ArrayResize(g_lows, n + 1);
         g_lows[n] = s;
        }
     }

   // Chronological (oldest first). Arrays were filled from older bars to newer.
   // Classify weak vs strong: a high that has been traded through is weak.
   double lastHighTaken = 0, lastLowTaken = 0;
   for(int i = 0; i < ArraySize(g_highs); i++)
     {
      int bar = g_highs[i].bar;
      double px = g_highs[i].price;
      bool taken = false;
      for(int k = bar - 1; k >= 1; k--)
        {
         if(iHigh(_Symbol, PERIOD_CURRENT, k) > px)
           {
            taken = true;
            break;
           }
        }
      g_highs[i].isWeak = taken;
     }
   for(int i = 0; i < ArraySize(g_lows); i++)
     {
      int bar = g_lows[i].bar;
      double px = g_lows[i].price;
      bool taken = false;
      for(int k = bar - 1; k >= 1; k--)
        {
         if(iLow(_Symbol, PERIOD_CURRENT, k) < px)
           {
            taken = true;
            break;
           }
        }
      g_lows[i].isWeak = taken;
     }

   BuildBOS_CHoCH();
  }

bool IsSwingHigh(const int i)
  {
   double h = iHigh(_Symbol, PERIOD_CURRENT, i);
   for(int k = 1; k <= InpSwingLeft; k++)
      if(iHigh(_Symbol, PERIOD_CURRENT, i + k) >= h)
         return false;
   for(int k = 1; k <= InpSwingRight; k++)
      if(iHigh(_Symbol, PERIOD_CURRENT, i - k) > h)
         return false;
   return true;
  }

bool IsSwingLow(const int i)
  {
   double l = iLow(_Symbol, PERIOD_CURRENT, i);
   for(int k = 1; k <= InpSwingLeft; k++)
      if(iLow(_Symbol, PERIOD_CURRENT, i + k) <= l)
         return false;
   for(int k = 1; k <= InpSwingRight; k++)
      if(iLow(_Symbol, PERIOD_CURRENT, i - k) < l)
         return false;
   return true;
  }

void BuildBOS_CHoCH()
  {
   // Walk bars forward using last confirmed swing high/low as the structure level.
   int nh = ArraySize(g_highs);
   int nl = ArraySize(g_lows);
   if(nh < 2 || nl < 2)
      return;

   ENUM_TREND trend = TREND_NONE;
   double lastSH = 0, lastSL = 0;
   int    lastSHbar = 100000, lastSLbar = 100000;

   // Seed with first two swings (oldest)
   lastSH    = g_highs[0].price;
   lastSHbar = g_highs[0].bar;
   lastSL    = g_lows[0].price;
   lastSLbar = g_lows[0].bar;
   // BUGFIX: this used to guess BULL/BEAR from whichever of the first two
   // swings came first, and that guess decided whether the first structure
   // events were labelled CHoCH or BOS. Start with no character established;
   // a break can only be a *change* of character once a trend actually exists.
   trend = TREND_NONE;

   int startBar = MathMax(g_highs[0].bar, g_lows[0].bar) - 1;
   if(startBar < 2)
      startBar = 2;

   int hiIdx = 0, loIdx = 0;

   for(int bar = startBar; bar >= 1; bar--)
     {
      // advance swing pointers as we pass them
      while(hiIdx + 1 < nh && g_highs[hiIdx + 1].bar >= bar)
        {
         hiIdx++;
         lastSH    = g_highs[hiIdx].price;
         lastSHbar = g_highs[hiIdx].bar;
        }
      while(loIdx + 1 < nl && g_lows[loIdx + 1].bar >= bar)
        {
         loIdx++;
         lastSL    = g_lows[loIdx].price;
         lastSLbar = g_lows[loIdx].bar;
        }

      double c = iClose(_Symbol, PERIOD_CURRENT, bar);
      datetime tt = iTime(_Symbol, PERIOD_CURRENT, bar);

      // Bullish break of last swing high
      if(lastSH > 0 && c > lastSH && bar < lastSHbar)
        {
         StructureEvent e;
         e.t      = tt;
         e.level  = lastSH;
         e.bar    = bar;
         e.dir    = 1;
         e.isCHoCH = (trend == TREND_BEAR);   // only a change if bearish character existed
         e.used   = false;
         PushEvent(e);
         trend = TREND_BULL;
         // lock this high so we don't re-fire until a newer high is registered
         lastSH = 0;
        }

      // Bearish break of last swing low
      if(lastSL > 0 && c < lastSL && bar < lastSLbar)
        {
         StructureEvent e;
         e.t      = tt;
         e.level  = lastSL;
         e.bar    = bar;
         e.dir    = -1;
         e.isCHoCH = (trend == TREND_BULL);   // only a change if bullish character existed
         e.used   = false;
         PushEvent(e);
         trend = TREND_BEAR;
         lastSL = 0;
        }
     }

   g_trend = trend;
  }

void PushEvent(const StructureEvent &e)
  {
   int n = ArraySize(g_events);
   ArrayResize(g_events, n + 1);
   g_events[n] = e;
  }

StructureEvent LatestEvent(const int dirWanted, const bool chochOnly)
  {
   StructureEvent blank;
   blank.t = 0;
   blank.level = 0;
   blank.bar = -1;
   blank.dir = 0;
   blank.isCHoCH = false;
   blank.used = true;

   for(int i = ArraySize(g_events) - 1; i >= 0; i--)
     {
      if(g_events[i].dir != dirWanted)
         continue;
      if(chochOnly && !g_events[i].isCHoCH)
         continue;
      if(g_events[i].bar > InpBarsAfterShift)
         continue;
      return g_events[i];
     }
   return blank;
  }

//====================================================================
// ZONES — Order Blocks + FVGs
//====================================================================
void ScanZones()
  {
   ArrayResize(g_zones, 0);
   if(InpUseOrderBlocks)
      FindOrderBlocks();
   if(InpUseFVG)
      FindFVGs();
  }

void FindOrderBlocks()
  {
   int look = MathMin(InpOBLookback, Bars(_Symbol, PERIOD_CURRENT) - 6);
   // Displacement candle: body >= 1.4 * ATR and breaks structure-ish
   double atr = AtrValue(14, 1);
   if(atr <= 0)
      atr = _Point * 100;

   for(int i = look; i >= 3; i--)
     {
      double o = iOpen(_Symbol, PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      double body = MathAbs(c - o);
      if(body < atr * 0.8)
         continue;

      // Bullish displacement → demand OB = last down-close candle before it
      if(c > o)
        {
         int obBar = -1;
         for(int k = i + 1; k <= i + 6 && k < Bars(_Symbol, PERIOD_CURRENT) - 1; k++)
           {
            if(iClose(_Symbol, PERIOD_CURRENT, k) < iOpen(_Symbol, PERIOD_CURRENT, k))
              {
               obBar = k;
               break;
              }
           }
         if(obBar < 0)
            continue;
         Zone z;
         z.t1        = iTime(_Symbol, PERIOD_CURRENT, obBar);
         z.t2        = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 40;
         z.top       = iHigh(_Symbol, PERIOD_CURRENT, obBar);
         z.bot       = iLow(_Symbol, PERIOD_CURRENT, obBar);
         z.dir       = 1;
         z.isOB      = true;
         z.isFVG     = false;
         // mitigated if any later bar closed through the block
         z.mitigated = ZoneTradedThrough(z, obBar - 1);
         z.bar       = obBar;
         if(!z.mitigated)
            PushZone(z);
        }

      // Bearish displacement → supply OB = last up-close candle before it
      if(c < o)
        {
         int obBar = -1;
         for(int k = i + 1; k <= i + 6 && k < Bars(_Symbol, PERIOD_CURRENT) - 1; k++)
           {
            if(iClose(_Symbol, PERIOD_CURRENT, k) > iOpen(_Symbol, PERIOD_CURRENT, k))
              {
               obBar = k;
               break;
              }
           }
         if(obBar < 0)
            continue;
         Zone z;
         z.t1        = iTime(_Symbol, PERIOD_CURRENT, obBar);
         z.t2        = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 40;
         z.top       = iHigh(_Symbol, PERIOD_CURRENT, obBar);
         z.bot       = iLow(_Symbol, PERIOD_CURRENT, obBar);
         z.dir       = -1;
         z.isOB      = true;
         z.isFVG     = false;
         z.mitigated = ZoneTradedThrough(z, obBar - 1);
         z.bar       = obBar;
         if(!z.mitigated)
            PushZone(z);
        }
     }

   // Keep only the most recent few unmitigated of each side
   TrimZones(6);
  }

void FindFVGs()
  {
   int look = MathMin(InpFVGLookback, Bars(_Symbol, PERIOD_CURRENT) - 5);
   double minGap = InpMinFVGPoints * _Point;

   for(int i = look; i >= 2; i--)
     {
      // Bullish FVG: low[i-1] wait — using series: index i is older than i-1
      // Candle 3 (newest of the trio) = i-2? Let's use:
      //   candle A = i+1 (oldest), B = i, C = i-1 (newest)
      // Bullish FVG if Low(C) > High(A)
      double highA = iHigh(_Symbol, PERIOD_CURRENT, i + 1);
      double lowC  = iLow(_Symbol, PERIOD_CURRENT, i - 1);
      double lowA  = iLow(_Symbol, PERIOD_CURRENT, i + 1);
      double highC = iHigh(_Symbol, PERIOD_CURRENT, i - 1);

      if(lowC - highA >= minGap)
        {
         Zone z;
         z.t1        = iTime(_Symbol, PERIOD_CURRENT, i + 1);
         z.t2        = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 30;
         z.top       = lowC;
         z.bot       = highA;
         z.dir       = 1;
         z.isOB      = false;
         z.isFVG     = true;
         z.bar       = i;
         z.mitigated = FVGFilled(z, i - 2);
         if(!z.mitigated)
            PushZone(z);
        }
      if(lowA - highC >= minGap)
        {
         Zone z;
         z.t1        = iTime(_Symbol, PERIOD_CURRENT, i + 1);
         z.t2        = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 30;
         z.top       = lowA;
         z.bot       = highC;
         z.dir       = -1;
         z.isOB      = false;
         z.isFVG     = true;
         z.bar       = i;
         z.mitigated = FVGFilled(z, i - 2);
         if(!z.mitigated)
            PushZone(z);
        }
     }
  }

bool ZoneTradedThrough(const Zone &z, const int fromBar)
  {
   if(fromBar < 1)
      return false;
   int count = fromBar;
   if(z.dir > 0)
     {
      // demand invalidated if close below the block
      for(int i = fromBar; i >= 1; i--)
         if(iClose(_Symbol, PERIOD_CURRENT, i) < z.bot)
            return true;
     }
   else
     {
      for(int i = fromBar; i >= 1; i--)
         if(iClose(_Symbol, PERIOD_CURRENT, i) > z.top)
            return true;
     }
   return false;
  }

bool FVGFilled(const Zone &z, const int fromBar)
  {
   if(fromBar < 1)
      return false;
   for(int i = fromBar; i >= 1; i--)
     {
      if(z.dir > 0 && iLow(_Symbol, PERIOD_CURRENT, i) <= z.bot)
         return true;
      if(z.dir < 0 && iHigh(_Symbol, PERIOD_CURRENT, i) >= z.top)
         return true;
     }
   return false;
  }

void PushZone(const Zone &z)
  {
   // skip microscopic zones
   if(z.top - z.bot < 5 * _Point)
      return;
   int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1);
   g_zones[n] = z;
  }

void TrimZones(const int keepEach)
  {
   // keep newest unmitigated OBs / FVGs per direction
   Zone tmp[];
   ArrayResize(tmp, 0);
   int bullKept = 0, bearKept = 0;
   for(int i = ArraySize(g_zones) - 1; i >= 0; i--)
     {
      if(g_zones[i].dir > 0)
        {
         if(bullKept >= keepEach)
            continue;
         bullKept++;
        }
      else
        {
         if(bearKept >= keepEach)
            continue;
         bearKept++;
        }
      int n = ArraySize(tmp);
      ArrayResize(tmp, n + 1);
      tmp[n] = g_zones[i];
     }
   ArrayResize(g_zones, ArraySize(tmp));
   for(int i = 0; i < ArraySize(tmp); i++)
      g_zones[i] = tmp[i];
  }

Zone BestZone(const int dir)
  {
   Zone blank;
   blank.t1 = 0;
   blank.top = 0;
   blank.bot = 0;
   blank.dir = 0;
   blank.isOB = false;
   blank.isFVG = false;
   blank.mitigated = true;
   blank.bar = -1;

   // Prefer unmitigated OB that price is currently interacting with; else FVG
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (dir > 0 ? ask : bid);
   double atr = AtrValue(14, 1);
   double pad = atr * InpZoneBufferATR;

   Zone bestOB;
   bestOB = blank;
   Zone bestFVG;
   bestFVG = blank;

   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].dir != dir || g_zones[i].mitigated)
         continue;
      bool touch = (px <= g_zones[i].top + pad && px >= g_zones[i].bot - pad);
      if(!touch && InpRequireZoneTouch)
         continue;
      if(g_zones[i].isOB && bestOB.bar < 0)
         bestOB = g_zones[i];
      if(g_zones[i].isFVG && bestFVG.bar < 0)
         bestFVG = g_zones[i];
     }
   if(bestOB.bar >= 0)
      return bestOB;
   return bestFVG;
  }

bool PriceInZone(const Zone &z)
  {
   if(z.bar < 0)
      return false;
   double atr = AtrValue(14, 1);
   double pad = atr * InpZoneBufferATR;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (z.dir > 0 ? ask : bid);
   return (px <= z.top + pad && px >= z.bot - pad);
  }

//====================================================================
// EQUILIBRIUM / PREMIUM-DISCOUNT  (dotted 50% line on screenshots)
//====================================================================
bool InDiscountForBuy()
  {
   if(!InpUseEquilibrium)
      return true;
   double hi, lo;
   RangeHighLow(60, hi, lo);
   if(hi <= lo)
      return true;
   double eq = (hi + lo) * 0.5;
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= eq);
  }

bool InPremiumForSell()
  {
   if(!InpUseEquilibrium)
      return true;
   double hi, lo;
   RangeHighLow(60, hi, lo);
   if(hi <= lo)
      return true;
   double eq = (hi + lo) * 0.5;
   return (SymbolInfoDouble(_Symbol, SYMBOL_BID) >= eq);
  }

void RangeHighLow(const int bars, double &hi, double &lo)
  {
   hi = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, bars, 1));
   lo = iLow(_Symbol, PERIOD_CURRENT,  iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, bars, 1));
  }

//====================================================================
// RSI + CHANNEL
//====================================================================
double CurrentRSI()
  {
   if(g_rsiHandle == INVALID_HANDLE)
      return 50.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, buf) < 1)
      return 50.0;
   return buf[0];
  }

bool RSI_AllowsBuy()
  {
   if(!InpUseRSI)
      return true;
   return (CurrentRSI() <= InpRSIOversold + 8.0);   // coming out of discount / not stretched up
  }

bool RSI_AllowsSell()
  {
   if(!InpUseRSI)
      return true;
   return (CurrentRSI() >= InpRSIOverbought - 8.0);
  }

bool ChannelBreakSell()
  {
   if(!InpUseChannelBreak)
      return true;
   // Simple rising-channel break: last 4 swing lows slope up, close under the projected lower line
   int n = ArraySize(g_lows);
   if(n < InpChannelPivots)
      return true;
   int a = n - InpChannelPivots;
   int b = n - 1;
   if(g_lows[b].price <= g_lows[a].price)
      return true; // not a rising channel
   double dt = (double)(g_lows[b].bar - g_lows[a].bar);
   if(dt == 0)
      return true;
   // bars decrease toward present, so slope vs bar index is inverted
   double slopePerBar = (g_lows[a].price - g_lows[b].price) / (double)(g_lows[a].bar - g_lows[b].bar);
   double lineNow = g_lows[b].price + slopePerBar * (1 - g_lows[b].bar);
   // Use last confirmed low projected to bar 1
   double projected = g_lows[b].price - slopePerBar * (g_lows[b].bar - 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (c < projected);
  }

bool ChannelBreakBuy()
  {
   if(!InpUseChannelBreak)
      return true;
   int n = ArraySize(g_highs);
   if(n < InpChannelPivots)
      return true;
   int a = n - InpChannelPivots;
   int b = n - 1;
   if(g_highs[b].price >= g_highs[a].price)
      return true; // not a falling channel
   double slopePerBar = (g_highs[a].price - g_highs[b].price) / (double)(g_highs[a].bar - g_highs[b].bar);
   double projected = g_highs[b].price - slopePerBar * (g_highs[b].bar - 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (c > projected);
  }

bool RejectionBuy()
  {
   if(!InpUseRejectionCandle)
      return true;
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   double rng = h - l;
   if(rng <= 0)
      return false;
   bool bull = (c > o);
   bool wick = ((MathMin(o, c) - l) / rng >= 0.35);
   return (bull || wick);
  }

bool RejectionSell()
  {
   if(!InpUseRejectionCandle)
      return true;
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   double rng = h - l;
   if(rng <= 0)
      return false;
   bool bear = (c < o);
   bool wick = ((h - MathMax(o, c)) / rng >= 0.35);
   return (bear || wick);
  }

//====================================================================
// PRICE ACTION  — any ONE of these confirms; never all required
//====================================================================
bool BullEngulf()
  {
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1), c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, 2), c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   return(c2 < o2 && c1 > o1 && o1 <= c2 && c1 >= o2);
  }

bool BearEngulf()
  {
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1), c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, 2), c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   return(c2 > o2 && c1 < o1 && o1 >= c2 && c1 <= o2);
  }

bool BullRejectionBar()
  {
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1), c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1), l = iLow(_Symbol, PERIOD_CURRENT, 1);
   double rng = h - l;
   if(rng <= 0) return(false);
   double lowerWick = MathMin(o, c) - l;
   return(lowerWick / rng >= 0.45 && c >= (l + rng * 0.5));
  }

bool BearRejectionBar()
  {
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1), c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1), l = iLow(_Symbol, PERIOD_CURRENT, 1);
   double rng = h - l;
   if(rng <= 0) return(false);
   double upperWick = h - MathMax(o, c);
   return(upperWick / rng >= 0.45 && c <= (l + rng * 0.5));
  }

bool BullReclaim(const double level)
  {
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   return(level > 0 && l1 <= level && c1 > level);
  }

bool BearReclaim(const double level)
  {
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   return(level > 0 && h1 >= level && c1 < level);
  }

// Returns the confirmation name, or "" when none fired.
string PriceActionName(const int dir, const double retestLevel)
  {
   if(dir > 0)
     {
      if(BullEngulf())              return("BULL_ENGULF");
      if(BullRejectionBar())        return("BULL_REJECTION");
      if(BullReclaim(retestLevel))  return("BULL_RECLAIM");
     }
   else
     {
      if(BearEngulf())              return("BEAR_ENGULF");
      if(BearRejectionBar())        return("BEAR_REJECTION");
      if(BearReclaim(retestLevel))  return("BEAR_RECLAIM");
     }
   return("");
  }

//====================================================================
// LOCATION  — any ONE qualifies
//====================================================================
enum LOC_STATE { LOC_DISCOUNT, LOC_EQUILIBRIUM, LOC_PREMIUM };

LOC_STATE LocationState()
  {
   double hi, lo;
   RangeHighLow(60, hi, lo);
   if(hi <= lo) return(LOC_EQUILIBRIUM);
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pct = (px - lo) / (hi - lo);
   if(pct < 0.45) return(LOC_DISCOUNT);
   if(pct > 0.55) return(LOC_PREMIUM);
   return(LOC_EQUILIBRIUM);
  }

string LocStateName(LOC_STATE s)
  {
   if(s == LOC_DISCOUNT) return("DISCOUNT");
   if(s == LOC_PREMIUM)  return("PREMIUM");
   return("EQUILIBRIUM");
  }

bool BrokenStructureRetest(const int dir, const StructureEvent &ev, double &levelOut)
  {
   if(ev.bar < 0 || ev.level <= 0) return(false);
   double atr = AtrValue(14, 1);
   if(atr <= 0) return(false);
   double tol = atr * InpZoneBufferATR * 2.0;
   double px  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   levelOut = ev.level;
   return(MathAbs(px - ev.level) <= tol);
  }

bool KeyLevelRetest(const int dir, double &levelOut)
  {
   double atr = AtrValue(14, 1);
   if(atr <= 0) return(false);
   double tol = atr * InpZoneBufferATR * 2.0;
   double px  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lvl = (dir > 0) ? LastStrongLow() : LastStrongHigh();
   levelOut = lvl;
   return(lvl > 0 && MathAbs(px - lvl) <= tol);
  }

//====================================================================
// RSI as confluence only -- never permission
//====================================================================
double RSIPrev()
  {
   if(g_rsiHandle == INVALID_HANDLE) return(50.0);
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 2, buf) < 2) return(50.0);
   return(buf[1]);
  }

bool RSIAgrees(const int dir, double &rsiOut, string &noteOut)
  {
   double now = CurrentRSI();
   double prev = RSIPrev();
   rsiOut = now;
   bool rising = (now > prev);
   noteOut = DoubleToString(now, 1) + (rising ? " rising" : " falling");
   if(dir > 0) return(now > 50.0 || rising);
   return(now < 50.0 || !rising);
  }

//====================================================================
// STRUCTURE TARGETS
//====================================================================
bool NextSwingAbove(const double price, double &out)
  {
   double best = 0; bool ok = false;
   for(int i = 0; i < ArraySize(g_highs); i++)
      if(g_highs[i].price > price && (!ok || g_highs[i].price < best)) { best = g_highs[i].price; ok = true; }
   out = best;
   return(ok);
  }

bool NextSwingBelow(const double price, double &out)
  {
   double best = 0; bool ok = false;
   for(int i = 0; i < ArraySize(g_lows); i++)
      if(g_lows[i].price < price && (!ok || g_lows[i].price > best)) { best = g_lows[i].price; ok = true; }
   out = best;
   return(ok);
  }

bool NextZoneAbove(const double price, double &out)
  {
   double best = 0; bool ok = false;
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].dir >= 0 || g_zones[i].mitigated) continue;   // supply only
      if(g_zones[i].bot > price && (!ok || g_zones[i].bot < best)) { best = g_zones[i].bot; ok = true; }
     }
   out = best;
   return(ok);
  }

bool NextZoneBelow(const double price, double &out)
  {
   double best = 0; bool ok = false;
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].dir <= 0 || g_zones[i].mitigated) continue;   // demand only
      if(g_zones[i].top < price && (!ok || g_zones[i].top > best)) { best = g_zones[i].top; ok = true; }
     }
   out = best;
   return(ok);
  }

//====================================================================
// ENTRIES
//====================================================================
void EvaluateSide(const int dir);

void TryEntriesNew()
  {
   EvaluateSide(+1);
   EvaluateSide(-1);
  }

void EvaluateSide(const int dir)
  {
   // ---------- STRUCTURE (core 1) ----------
   StructureEvent evC = LatestEvent(dir, true);
   StructureEvent evB = LatestEvent(dir, false);

   bool haveCHoCH = (InpTradeCHoCH && evC.bar >= 0);
   bool haveBOS   = (InpTradeBOS && evB.bar >= 0 && !evB.isCHoCH &&
                     ((dir > 0 && g_trend == TREND_BULL) || (dir < 0 && g_trend == TREND_BEAR)));
   if(!haveCHoCH && !haveBOS) return;

   StructureEvent ev = haveCHoCH ? evC : evB;
   string family = haveCHoCH ? "CHOCH_REVERSAL" : "BOS_CONTINUATION";

   g_fRawEvents++;
   if(haveCHoCH) { if(dir > 0) g_fCHoCHBull++; else g_fCHoCHBear++; }
   else          { if(dir > 0) g_fBOSBull++;   else g_fBOSBear++;   }

   // ---------- LOCATION (core 2) : any one qualifies ----------
   Zone z = BestZone(dir);
   bool zoneTouch = (z.bar >= 0 && PriceInZone(z));
   double brokenLvl = 0, keyLvl = 0;
   bool brokenRetest = BrokenStructureRetest(dir, ev, brokenLvl);
   bool keyRetest    = KeyLevelRetest(dir, keyLvl);
   bool locationValid = (zoneTouch || brokenRetest || keyRetest);

   if(zoneTouch)    g_fZoneTouch++;
   if(brokenRetest) g_fBrokenRetest++;
   if(keyRetest)    g_fKeyLevelRetest++;
   if(locationValid) g_fLocValid++;

   string locName = zoneTouch ? (z.isOB ? "OB_ZONE" : "FVG_ZONE")
                              : (brokenRetest ? "BROKEN_STRUCTURE" : (keyRetest ? "KEY_LEVEL" : "NONE"));

   // ---------- PRICE ACTION (core 3) ----------
   double retestLevel = brokenRetest ? brokenLvl : (keyRetest ? keyLvl : 0);
   string paName = PriceActionName(dir, retestLevel);
   bool paValid = (paName != "");
   if(paValid)
     {
      g_fPAConfirm++;
      if(paName == "BULL_ENGULF") g_fBullEngulf++;
      if(paName == "BEAR_ENGULF") g_fBearEngulf++;
      if(paName == "BULL_REJECTION" || paName == "BEAR_REJECTION") g_fRejCandle++;
     }

   // ---------- OPTIONAL CONFLUENCE (grades, never vetoes) ----------
   LOC_STATE loc = LocationState();
   bool eqFavorable = (dir > 0) ? (loc == LOC_DISCOUNT) : (loc == LOC_PREMIUM);
   if(eqFavorable) g_fEqFavorable++;

   double rsiVal = 50; string rsiNote = "";
   bool rsiAgrees = RSIAgrees(dir, rsiVal, rsiNote);
   if(rsiAgrees) { if(dir > 0) g_fRSIBullAligned++; else g_fRSIBearAligned++; }

   bool channelOK = (dir > 0) ? ChannelBreakBuy() : ChannelBreakSell();
   if(channelOK) g_fChannelConf++;

   double atr = AtrValue(14, 1);
   double evBody = 0;
   if(ev.bar >= 1)
      evBody = MathAbs(iClose(_Symbol, PERIOD_CURRENT, ev.bar) - iOpen(_Symbol, PERIOD_CURRENT, ev.bar));
   bool strongDisplacement = (atr > 0 && evBody >= atr * 0.8);

   int overlaps = (zoneTouch ? 1 : 0) + (brokenRetest ? 1 : 0) + (keyRetest ? 1 : 0);
   bool htfAligned = ((dir > 0 && g_trend == TREND_BULL) || (dir < 0 && g_trend == TREND_BEAR));

   int score = 0;
   if(htfAligned)                       score += 2;
   if(strongDisplacement)               score += 2;
   if(zoneTouch && z.isOB)              score += 2;
   if(brokenRetest)                     score += 2;
   if(paName == "BULL_ENGULF" || paName == "BEAR_ENGULF" ||
      paName == "BULL_REJECTION" || paName == "BEAR_REJECTION") score += 2;
   if(eqFavorable)                      score += 1;
   if(rsiAgrees)                        score += 1;
   if(channelOK)                        score += 1;
   if(overlaps >= 2)                    score += 1;

   bool coreValid = (locationValid && paValid);
   bool scoreOK   = (!InpUseScoreGate || score >= InpMinConfluenceScore);
   bool newAccept = (coreValid && scoreOK);

   // Shadow: what the original all-AND architecture would have done.
   bool oldEq   = (dir > 0) ? InDiscountForBuy() : InPremiumForSell();
   bool oldRSI  = (dir > 0) ? (CurrentRSI() <= InpRSIOversold + 8.0)
                            : (CurrentRSI() >= InpRSIOverbought - 8.0);
   bool oldRej  = (dir > 0) ? RejectionBuy() : RejectionSell();
   bool oldAccept = (oldEq && oldRSI && channelOK && oldRej && (!InpRequireZoneTouch || zoneTouch));

   if(coreValid)
     {
      if(dir > 0) g_fCoreSetupsBuy++; else g_fCoreSetupsSell++;
      if(score >= 0 && score <= 14) g_fScoreHist[score]++;
      if(scoreOK) g_fScorePass++; else g_fScoreFail++;
     }
   if(oldAccept) g_fOldLogicWouldAccept++;
   if(newAccept) g_fNewLogicAccepts++;
   if(newAccept && !oldAccept) g_fOnlyNewAccepts++;

   g_fCandidateId++;
   if(InpLogEverySetup && (coreValid || oldAccept))
      PrintFormat("SETUP #%d | %s | family=%s\n  structure=%s (%s, bar=%d)\n  location=%s (zone=%s broken=%s key=%s)\n  priceAction=%s\n  RSI=%s\n  channel=%s\n  locationState=%s\n  displacement=%s\n  score=%d\n  OriginalANDLogic=%s | NewCoreLogic=%s | ENTRY=%s",
                  g_fCandidateId, dir > 0 ? "BUY" : "SELL", family,
                  "PASS", ev.isCHoCH ? "CHoCH" : "BOS", ev.bar,
                  locationValid ? locName : "FAIL",
                  zoneTouch ? "yes" : "no", brokenRetest ? "yes" : "no", keyRetest ? "yes" : "no",
                  paValid ? paName : "FAIL",
                  rsiNote, channelOK ? "OK" : "none",
                  LocStateName(loc), strongDisplacement ? "strong" : "weak",
                  score,
                  oldAccept ? "ACCEPT" : "REJECT",
                  newAccept ? "ACCEPT" : "REJECT",
                  newAccept ? "YES" : "NO");

   if(!newAccept) return;

   if(dir > 0) { g_fEntriesBuy++;  g_dOpenBuy++;  OpenBuy(z, ev);  }
   else        { g_fEntriesSell++; g_dOpenSell++; OpenSell(z, ev); }
  }

void TryEntries()
  {
   // --- BUY: bullish CHoCH or BOS, discount, demand zone tap ---
   StructureEvent evC = LatestEvent(1, true);
   StructureEvent evB = LatestEvent(1, false);
   bool buyShift = false;
   StructureEvent buyEv = evC;
   if(InpTradeCHoCH && evC.bar >= 0)
     {
      buyShift = true;
      buyEv = evC;
     }
   else
      if(InpTradeBOS && evB.bar >= 0 && !evB.isCHoCH && g_trend == TREND_BULL)
        {
         buyShift = true;
         buyEv = evB;
        }

   if(buyShift)
     {
      g_dBuyShift++;
      bool eq   = InDiscountForBuy();
      bool rsi  = RSI_AllowsBuy();
      bool chan = ChannelBreakBuy();
      bool rej  = RejectionBuy();
      if(!eq)   g_dBuyRejEq++;
      if(!rsi)  g_dBuyRejRSI++;
      if(!chan) g_dBuyRejChan++;
      if(!rej)  g_dBuyRejRej++;

      if(eq && rsi && chan && rej)
        {
         Zone z = BestZone(1);
         if(!InpRequireZoneTouch || PriceInZone(z))
           {
            g_dOpenBuy++;
            OpenBuy(z, buyEv);
           }
         else
            g_dBuyRejZone++;
        }
     }

   // --- SELL ---
   StructureEvent evCs = LatestEvent(-1, true);
   StructureEvent evBs = LatestEvent(-1, false);
   bool sellShift = false;
   StructureEvent sellEv = evCs;
   if(InpTradeCHoCH && evCs.bar >= 0)
     {
      sellShift = true;
      sellEv = evCs;
     }
   else
      if(InpTradeBOS && evBs.bar >= 0 && !evBs.isCHoCH && g_trend == TREND_BEAR)
        {
         sellShift = true;
         sellEv = evBs;
        }

   if(sellShift)
     {
      g_dSellShift++;
      bool eq   = InPremiumForSell();
      bool rsi  = RSI_AllowsSell();
      bool chan = ChannelBreakSell();
      bool rej  = RejectionSell();
      if(!eq)   g_dSellRejEq++;
      if(!rsi)  g_dSellRejRSI++;
      if(!chan) g_dSellRejChan++;
      if(!rej)  g_dSellRejRej++;

      if(eq && rsi && chan && rej)
        {
         Zone z = BestZone(-1);
         if(!InpRequireZoneTouch || PriceInZone(z))
           {
            g_dOpenSell++;
            OpenSell(z, sellEv);
           }
         else
            g_dSellRejZone++;
        }
     }
  }

double LastStrongLow()
  {
   for(int i = ArraySize(g_lows) - 1; i >= 0; i--)
      if(!g_lows[i].isWeak)
         return g_lows[i].price;
   return iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 30, 1));
  }

double LastStrongHigh()
  {
   for(int i = ArraySize(g_highs) - 1; i >= 0; i--)
      if(!g_highs[i].isWeak)
         return g_highs[i].price;
   return iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 30, 1));
  }

double LastWeakHigh()
  {
   for(int i = ArraySize(g_highs) - 1; i >= 0; i--)
      if(g_highs[i].isWeak)
         return g_highs[i].price;
   return LastStrongHigh();
  }

double LastWeakLow()
  {
   for(int i = ArraySize(g_lows) - 1; i >= 0; i--)
      if(g_lows[i].isWeak)
         return g_lows[i].price;
   return LastStrongLow();
  }

void OpenBuy(const Zone &z, const StructureEvent &ev)
  {
   if(HasDirection(POSITION_TYPE_BUY))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double buffer = StopBuffer();
   double rawSL = (z.bar >= 0) ? z.bot : LastStrongLow();   // structural invalidation, unmoved
   double slPrice = rawSL - buffer;

   if(slPrice >= ask)
      slPrice = ask - (buffer + 50 * _Point);

   double risk = ask - slPrice;
   if(risk <= 0)
      return;

   // Structure-based targets: nearest internal swing, then the next
   // meaningful supply zone, then external liquidity. RR to each is logged
   // so target quality can be judged rather than assumed. Falls back to the
   // R-multiple target only when no real structure exists above.
   double tp1 = ask + risk * InpTP1_RR;
   double tp2 = ask + risk * InpTP2_RR;
   double s1 = 0, s2 = 0;
   if(NextSwingAbove(ask, s1) && s1 > ask) tp1 = s1;
   if(NextZoneAbove(ask, s2) && s2 > tp1)  tp2 = s2;
   else if(NextSwingAbove(tp1, s2) && s2 > tp1) tp2 = s2;

   double tp3 = LastWeakHigh();
   double rr1 = (tp1 - ask) / risk;

   if(InpDebugStats)
      PrintFormat("GEOMETRY | BUY | rawStructuralSL=%.2f | bufferAdded=%.2f | finalSL=%.2f | riskDistance=%.2f | TP1=%.2f (RR %.2f) | TP2=%.2f (RR %.2f) | TP3=%.2f (RR %.2f)",
                  rawSL, buffer, slPrice, risk,
                  tp1, rr1, tp2, (tp2 - ask) / risk,
                  tp3, tp3 > ask ? (tp3 - ask) / risk : 0.0);

   // Geometry gate (variant C): refuse to risk more than the nearest
   // realistic target is worth. Rejects are counted and logged, never
   // silently dropped.
   if(InpExitVariant == EXIT_C_FULL && rr1 < InpMinGeometryRR)
     {
      g_gGeometryReject++;
      g_gRejectRRSum += rr1;
      if(InpDebugStats)
         PrintFormat("GEOMETRY_REJECT | BUY | risk=%.2f | nearestTarget=%.2f | RR=%.2f", risk, tp1, rr1);
      return;
     }

   slPrice = NormalizePrice(slPrice);
   tp1     = NormalizePrice(tp1);
   tp2     = NormalizePrice(tp2);

   double lots = 0, riskMoney = 0, riskPct = 0;
   string rejectMsg = "";
   if(!ComputeSafeLots(ask, slPrice, +1, lots, riskMoney, riskPct, rejectMsg))
     {
      if(InpDebugStats) Print(rejectMsg, " | BUY skipped");
      return;
     }
   if(lots <= 0)
      return;

   if(InpDebugStats)
      PrintFormat("RISK_CHECK | equity=%.2f | requestedPct=%.2f | requested$=%.2f | lotsFinal=%.2f | entry=%.2f | SL=%.2f | stopDistance=%.2f | actualRisk$=%.2f | actualRiskPct=%.2f",
                  account.Equity(), InpRiskPercent, account.Equity() * InpRiskPercent / 100.0,
                  lots, ask, slPrice, risk, riskMoney, riskPct);

   g_riskPctSum += riskPct; g_riskPctN++;
   if(riskPct < g_riskPctMin) g_riskPctMin = riskPct;
   if(riskPct > g_riskPctMax) g_riskPctMax = riskPct;

   // Split into two tickets so T-P2 is a real second target (matches "T-P2 Hit")
   double lot1 = NormalizeLot(lots * (InpTP1_ClosePercent / 100.0));
   double lot2 = NormalizeLot(lots - lot1);
   if(lot2 < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
     {
      lot1 = lots;
      lot2 = 0;
     }

   string tag = ev.isCHoCH ? "CHoCH" : "BOS";
   if(lot1 > 0)
     {
      if(!trade.Buy(lot1, _Symbol, ask, slPrice, tp1, InpTradeComment + "|TP1|" + tag))
         { g_dOrderFail++; Print("Buy TP1 failed: ", trade.ResultRetcodeDescription()); }
     }
   if(lot2 > 0)
     {
      if(!trade.Buy(lot2, _Symbol, ask, slPrice, tp2, InpTradeComment + "|TP2|" + tag))
         { g_dOrderFail++; Print("Buy TP2 failed: ", trade.ResultRetcodeDescription()); }
     }
  }

void OpenSell(const Zone &z, const StructureEvent &ev)
  {
   if(HasDirection(POSITION_TYPE_SELL))
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = StopBuffer();
   double rawSL = (z.bar >= 0) ? z.top : LastStrongHigh();   // structural invalidation, unmoved
   double slPrice = rawSL + buffer;

   if(slPrice <= bid)
      slPrice = bid + (buffer + 50 * _Point);

   double risk = slPrice - bid;
   if(risk <= 0)
      return;

   double tp1 = bid - risk * InpTP1_RR;
   double tp2 = bid - risk * InpTP2_RR;
   double s1 = 0, s2 = 0;
   if(NextSwingBelow(bid, s1) && s1 > 0 && s1 < bid) tp1 = s1;
   if(NextZoneBelow(bid, s2) && s2 > 0 && s2 < tp1)  tp2 = s2;
   else if(NextSwingBelow(tp1, s2) && s2 > 0 && s2 < tp1) tp2 = s2;

   double tp3 = LastWeakLow();
   double rr1 = (bid - tp1) / risk;

   if(InpDebugStats)
      PrintFormat("GEOMETRY | SELL | rawStructuralSL=%.2f | bufferAdded=%.2f | finalSL=%.2f | riskDistance=%.2f | TP1=%.2f (RR %.2f) | TP2=%.2f (RR %.2f) | TP3=%.2f (RR %.2f)",
                  rawSL, buffer, slPrice, risk,
                  tp1, rr1, tp2, (bid - tp2) / risk,
                  tp3, (tp3 > 0 && tp3 < bid) ? (bid - tp3) / risk : 0.0);

   if(InpExitVariant == EXIT_C_FULL && rr1 < InpMinGeometryRR)
     {
      g_gGeometryReject++;
      g_gRejectRRSum += rr1;
      if(InpDebugStats)
         PrintFormat("GEOMETRY_REJECT | SELL | risk=%.2f | nearestTarget=%.2f | RR=%.2f", risk, tp1, rr1);
      return;
     }

   slPrice = NormalizePrice(slPrice);
   tp1     = NormalizePrice(tp1);
   tp2     = NormalizePrice(tp2);

   double lots = 0, riskMoney = 0, riskPct = 0;
   string rejectMsg = "";
   if(!ComputeSafeLots(bid, slPrice, -1, lots, riskMoney, riskPct, rejectMsg))
     {
      if(InpDebugStats) Print(rejectMsg, " | SELL skipped");
      return;
     }
   if(lots <= 0)
      return;

   if(InpDebugStats)
      PrintFormat("RISK_CHECK | equity=%.2f | requestedPct=%.2f | requested$=%.2f | lotsFinal=%.2f | entry=%.2f | SL=%.2f | stopDistance=%.2f | actualRisk$=%.2f | actualRiskPct=%.2f",
                  account.Equity(), InpRiskPercent, account.Equity() * InpRiskPercent / 100.0,
                  lots, bid, slPrice, risk, riskMoney, riskPct);

   g_riskPctSum += riskPct; g_riskPctN++;
   if(riskPct < g_riskPctMin) g_riskPctMin = riskPct;
   if(riskPct > g_riskPctMax) g_riskPctMax = riskPct;

   double lot1 = NormalizeLot(lots * (InpTP1_ClosePercent / 100.0));
   double lot2 = NormalizeLot(lots - lot1);
   if(lot2 < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
     {
      lot1 = lots;
      lot2 = 0;
     }

   string tag = ev.isCHoCH ? "CHoCH" : "BOS";
   if(lot1 > 0)
     {
      if(!trade.Sell(lot1, _Symbol, bid, slPrice, tp1, InpTradeComment + "|TP1|" + tag))
         { g_dOrderFail++; Print("Sell TP1 failed: ", trade.ResultRetcodeDescription()); }
     }
   if(lot2 > 0)
     {
      if(!trade.Sell(lot2, _Symbol, bid, slPrice, tp2, InpTradeComment + "|TP2|" + tag))
         { g_dOrderFail++; Print("Sell TP2 failed: ", trade.ResultRetcodeDescription()); }
     }
  }

bool HasDirection(const ENUM_POSITION_TYPE typ)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == (long)InpMagic && posInfo.PositionType() == typ)
         return true;
     }
   return false;
  }

//====================================================================
// MANAGE
//====================================================================
void ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != (long)InpMagic)
         continue;

      ulong  ticket = posInfo.Ticket();
      double sl     = posInfo.StopLoss();
      double tp     = posInfo.TakeProfit();
      double open   = posInfo.PriceOpen();
      double vol    = posInfo.Volume();
      string cm     = posInfo.Comment();
      ENUM_POSITION_TYPE typ = posInfo.PositionType();

      // ---- MFE / MAE tracking, and variant-C management ----
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int ti = FindTradeRec(posId);
      if(ti >= 0 && g_trades[ti].riskPrice > 0)
        {
         double px = (typ == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double rNow = (typ == POSITION_TYPE_BUY)
                       ? (px - g_trades[ti].entry) / g_trades[ti].riskPrice
                       : (g_trades[ti].entry - px) / g_trades[ti].riskPrice;
         if(rNow > g_trades[ti].mfeR) g_trades[ti].mfeR = rNow;
         if(rNow < g_trades[ti].maeR) g_trades[ti].maeR = rNow;

         if(InpExitVariant == EXIT_C_FULL)
           {
            // partial at +1R, then breakeven -- never before 1R
            if(!g_trades[ti].partial1Done && rNow >= InpPartial1AtR)
              {
               double part = NormalizeLot(g_trades[ti].initialVolume * InpPartial1Pct / 100.0);
               if(part > 0 && part < vol)
                  if(trade.PositionClosePartial(ticket, part))
                     g_trades[ti].partial1Done = true;

               double be = NormalizePrice(open);
               if((typ == POSITION_TYPE_BUY && (sl < be || sl == 0)) ||
                  (typ == POSITION_TYPE_SELL && (sl > be || sl == 0)))
                  if(trade.PositionModify(ticket, be, tp))
                     g_trades[ti].beMoved = true;
              }
            // second partial once TP2 distance is reached
            else if(g_trades[ti].partial1Done && !g_trades[ti].partial2Done &&
                    g_trades[ti].rr2 > 0 && rNow >= g_trades[ti].rr2)
              {
               double part2 = NormalizeLot(g_trades[ti].initialVolume * InpPartial2Pct / 100.0);
               if(part2 > 0 && part2 < vol)
                  if(trade.PositionClosePartial(ticket, part2))
                     g_trades[ti].partial2Done = true;
              }
           }
        }

      // Max hold
      if(InpMaxHoldHours > 0)
        {
         int hrs = (int)((TimeCurrent() - posInfo.Time()) / 3600);
         if(hrs >= InpMaxHoldHours)
           {
            trade.PositionClose(ticket);
            continue;
           }
        }

      // After TP1 sibling is gone, move TP2 stop to BE
      if(InpMoveBE_AtTP1 && StringFind(cm, "|TP2|") >= 0)
        {
         if(!SiblingAlive("|TP1|", typ))
           {
            double be = open;
            if(typ == POSITION_TYPE_BUY)
               be = open + InpBE_OffsetPoints * _Point;
            else
               be = open - InpBE_OffsetPoints * _Point;
            be = NormalizePrice(be);
            bool need = false;
            if(typ == POSITION_TYPE_BUY && (sl < be || sl == 0))
               need = true;
            if(typ == POSITION_TYPE_SELL && (sl > be || sl == 0))
               need = true;
            if(need)
               trade.PositionModify(ticket, be, tp);
           }
        }

      if(InpUseTrailAfterTP1 && StringFind(cm, "|TP2|") >= 0)
        {
         // Variants B/C: never trail before InpTrailStartR. Early trailing is
         // a prime suspect for average winners being far smaller than risk.
         bool trailAllowed = true;
         if(InpExitVariant != EXIT_A_CONTROL)
           {
            trailAllowed = false;
            if(ti >= 0 && g_trades[ti].riskPrice > 0)
              {
               double pxT = (typ == POSITION_TYPE_BUY)
                            ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double rT = (typ == POSITION_TYPE_BUY)
                           ? (pxT - g_trades[ti].entry) / g_trades[ti].riskPrice
                           : (g_trades[ti].entry - pxT) / g_trades[ti].riskPrice;
               trailAllowed = (rT >= InpTrailStartR);
              }
           }
         if(trailAllowed && !SiblingAlive("|TP1|", typ))
            Trail(ticket, typ, open, sl, tp);
        }
     }
  }

bool SiblingAlive(const string tag, const ENUM_POSITION_TYPE typ)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == (long)InpMagic &&
         posInfo.PositionType() == typ && StringFind(posInfo.Comment(), tag) >= 0)
         return true;
     }
   return false;
  }

void Trail(const ulong ticket, const ENUM_POSITION_TYPE typ, const double open, const double sl, const double tp)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double start = InpTrailStartPoints * _Point;
   double step  = InpTrailStepPoints * _Point;

   if(typ == POSITION_TYPE_BUY)
     {
      if(bid - open < start)
         return;
      double nsl = NormalizePrice(bid - step);
      if(nsl > sl + _Point)
         trade.PositionModify(ticket, nsl, tp);
     }
   else
     {
      if(open - ask < start)
         return;
      double nsl = NormalizePrice(ask + step);
      if(sl == 0 || nsl < sl - _Point)
         trade.PositionModify(ticket, nsl, tp);
     }
  }

void CloseAll(const string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == (long)InpMagic)
         trade.PositionClose(posInfo.Ticket());
     }
   Print("CloseAll: ", reason);
  }

//====================================================================
// LOTS / PRICE
//====================================================================
// Real expected loss between entry and stop for a given volume, using the
// broker's own contract specification rather than assuming points x lots.
double GetRiskMoney(const double entry, const double stop, const double volume, const int dir)
  {
   double profit = 0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, _Symbol, volume, entry, stop, profit))
      return(MathAbs(profit));

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return(0);
   return(MathAbs(entry - stop) / tickSize * tickVal * volume);
  }

// Size from real dollar risk, rounding DOWN. A calculated lot below the
// broker minimum is NEVER floored up and traded anyway -- if one minimum
// lot would risk more than permitted, the trade is refused.
bool ComputeSafeLots(const double entry, const double stop, const int dir,
                     double &lotsOut, double &riskMoneyOut, double &riskPctOut, string &reject)
  {
   lotsOut = 0; riskMoneyOut = 0; riskPctOut = 0; reject = "";

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   double equity  = account.Equity();
   double allowed = equity * InpRiskPercent / 100.0;
   if(equity <= 0 || allowed <= 0) { reject = "NO_EQUITY"; return(false); }

   if(InpLotMode == LOT_FIXED)
     {
      lotsOut = NormalizeLot(InpFixedLot);
     }
   else
     {
      double minLotRisk = GetRiskMoney(entry, stop, minLot, dir);
      if(minLotRisk <= 0) { reject = "INVALID_RISK_CALC"; return(false); }

      double raw  = minLot * (allowed / minLotRisk);
      double lots = MathFloor(raw / step) * step;          // round DOWN, never up

      if(lots < minLot)
        {
         double pct = 100.0 * minLotRisk / equity;
         if(pct > InpMaxActualRiskPercent)
           {
            g_riskRejectMinLot++;
            reject = StringFormat("RISK_REJECT_MIN_LOT | requestedRisk$=%.2f | minLotRisk$=%.2f | actualRiskPct=%.2f",
                                  allowed, minLotRisk, pct);
            return(false);
           }
         lots = minLot;
        }
      if(lots > maxLot) lots = maxLot;
      lotsOut = NormalizeDouble(lots, 2);
     }

   riskMoneyOut = GetRiskMoney(entry, stop, lotsOut, dir);
   riskPctOut   = 100.0 * riskMoneyOut / equity;

   if(riskPctOut > InpMaxActualRiskPercent)
     {
      g_riskRejectGuard++;
      reject = StringFormat("RISK_REJECT_GUARD | lots=%.2f | actualRisk$=%.2f | actualRiskPct=%.2f | ceiling=%.2f",
                            lotsOut, riskMoneyOut, riskPctOut, InpMaxActualRiskPercent);
      return(false);
     }
   return(true);
  }

double NormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      step = 0.01;
   lot = MathFloor(lot / step) * step;
   if(lot < minLot)
      lot = minLot;
   if(lot > maxLot)
      lot = maxLot;
   return NormalizeDouble(lot, 2);
  }

double AtrM5()
  {
   if(g_atrM5Handle == INVALID_HANDLE) return(0);
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrM5Handle, 0, 1, 1, buf) != 1) return(0);
   return(buf[0]);
  }

// The buffer is execution breathing room beyond the structural invalidation
// point -- never a way to widen strategy risk. Variant A keeps the original
// fixed 80 points (~$0.80 on gold); B and C scale it to M5 volatility.
double StopBuffer()
  {
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(InpExitVariant == EXIT_A_CONTROL)
      return(MathMax(minDist, InpSLBufferPoints * _Point));

   double atr5 = AtrM5();
   if(atr5 <= 0)
      return(MathMax(minDist, InpSLBufferPoints * _Point));   // fail safe, never zero-stop
   double b   = atr5 * InpSLBufferATRMult;
   double cap = atr5 * InpSLBufferATRCap;
   if(b > cap) b = cap;
   return(MathMax(minDist, b));
  }

int FindTradeRec(const ulong posId)
  {
   for(int i = 0; i < ArraySize(g_trades); i++)
      if(g_trades[i].posId == posId) return(i);
   return(-1);
  }

void RegisterTrade(const ulong posId, const int dir, const double entry, const double rawSL,
                   const double finalSL, const double riskMoney, const double vol,
                   const double tp1, const double tp2, const double tp3)
  {
   int n = ArraySize(g_trades);
   ArrayResize(g_trades, n + 1);
   g_trades[n].posId        = posId;
   g_trades[n].dir          = dir;
   g_trades[n].entry        = entry;
   g_trades[n].rawSL        = rawSL;
   g_trades[n].finalSL      = finalSL;
   g_trades[n].riskPrice    = MathAbs(entry - finalSL);
   g_trades[n].riskMoney    = riskMoney;
   g_trades[n].tp1          = tp1;
   g_trades[n].tp2          = tp2;
   g_trades[n].tp3          = tp3;
   double rp = g_trades[n].riskPrice;
   g_trades[n].rr1          = (rp > 0) ? MathAbs(tp1 - entry) / rp : 0;
   g_trades[n].rr2          = (rp > 0) ? MathAbs(tp2 - entry) / rp : 0;
   g_trades[n].rr3          = (rp > 0 && tp3 > 0) ? MathAbs(tp3 - entry) / rp : 0;
   g_trades[n].mfeR         = 0;
   g_trades[n].maeR         = 0;
   g_trades[n].initialVolume= vol;
   g_trades[n].partial1Done = false;
   g_trades[n].partial2Done = false;
   g_trades[n].beMoved      = false;
   g_trades[n].opened       = TimeCurrent();
  }

double NormalizePrice(const double p)
  {
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

// BUGFIX: this used to create and release an indicator handle on every
// call -- and it is called several times per bar from BestZone(),
// PriceInZone() and FindOrderBlocks(). Besides the cost, a freshly created
// handle can have no data ready, so it silently returned 0 and zeroed every
// ATR-scaled buffer downstream. One cached handle, created in OnInit.
double AtrValue(const int period, const int shift)
  {
   if(g_atrHandle == INVALID_HANDLE)
     {
      g_dAtrZero++;
      return 0;
     }
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1)
     {
      g_dAtrZero++;
      return 0;
     }
   if(buf[0] <= 0) g_dAtrZero++;
   return buf[0];
  }

//====================================================================
// VISUALS  — match the Telegram chart language
//====================================================================
void DeleteAllObjects()
  {
   ObjectsDeleteAll(0, g_pfx);
  }

void RedrawChart()
  {
   DeleteAllObjects();

   // Equilibrium
   double hi, lo;
   RangeHighLow(60, hi, lo);
   double eq = (hi + lo) * 0.5;
   string ne = g_pfx + "EQ";
   ObjectCreate(0, ne, OBJ_TREND, 0, iTime(_Symbol, PERIOD_CURRENT, 60), eq, TimeCurrent() + PeriodSeconds() * 10, eq);
   ObjectSetInteger(0, ne, OBJPROP_COLOR, InpEqColor);
   ObjectSetInteger(0, ne, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, ne, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ne, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, ne, OBJPROP_BACK, true);

   // Premium / discount wash (the big teal / pink rectangles)
   string pd = g_pfx + "PREM";
   ObjectCreate(0, pd, OBJ_RECTANGLE, 0, iTime(_Symbol, PERIOD_CURRENT, 80), hi, TimeCurrent() + PeriodSeconds() * 20, eq);
   ObjectSetInteger(0, pd, OBJPROP_COLOR, InpSupplyBox);
   ObjectSetInteger(0, pd, OBJPROP_FILL, true);
   ObjectSetInteger(0, pd, OBJPROP_BACK, true);
   ObjectSetInteger(0, pd, OBJPROP_WIDTH, 1);

   string dd = g_pfx + "DISC";
   ObjectCreate(0, dd, OBJ_RECTANGLE, 0, iTime(_Symbol, PERIOD_CURRENT, 80), lo, TimeCurrent() + PeriodSeconds() * 20, eq);
   ObjectSetInteger(0, dd, OBJPROP_COLOR, InpDemandBox);
   ObjectSetInteger(0, dd, OBJPROP_FILL, true);
   ObjectSetInteger(0, dd, OBJPROP_BACK, true);

   // Zones
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      string nm = g_pfx + "Z" + IntegerToString(i);
      color  col = (g_zones[i].dir > 0 ? InpBullColor : InpBearColor);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_zones[i].t1, g_zones[i].top, g_zones[i].t2, g_zones[i].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);

      string lb = g_pfx + "ZL" + IntegerToString(i);
      string txt = g_zones[i].isOB ? "OB" : "FVG";
      ObjectCreate(0, lb, OBJ_TEXT, 0, g_zones[i].t1, g_zones[i].top);
      ObjectSetString(0, lb, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, lb, OBJPROP_COLOR, col);
      ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, 8);
     }

   // Structure events
   for(int i = 0; i < ArraySize(g_events); i++)
     {
      if(g_events[i].bar > InpStructureLookback)
         continue;
      string nm = g_pfx + "EV" + IntegerToString(i);
      color  col = (g_events[i].dir > 0 ? InpBullColor : InpBearColor);
      string txt = g_events[i].isCHoCH ? "CHoCH" : "BOS";
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_events[i].t, g_events[i].level);
      ObjectSetString(0, nm, OBJPROP_TEXT, "  " + txt);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);

      string ln = g_pfx + "EL" + IntegerToString(i);
      ObjectCreate(0, ln, OBJ_TREND, 0, g_events[i].t, g_events[i].level,
                   g_events[i].t + PeriodSeconds() * 15, g_events[i].level);
      ObjectSetInteger(0, ln, OBJPROP_COLOR, col);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
     }

   // Weak / Strong tags on last few swings
   int tagged = 0;
   for(int i = ArraySize(g_highs) - 1; i >= 0 && tagged < 3; i--)
     {
      string nm = g_pfx + "WH" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_highs[i].t, g_highs[i].price);
      ObjectSetString(0, nm, OBJPROP_TEXT, g_highs[i].isWeak ? "  weak high" : "  strong high");
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_highs[i].isWeak ? clrSilver : InpBearColor);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
      tagged++;
     }
   tagged = 0;
   for(int i = ArraySize(g_lows) - 1; i >= 0 && tagged < 3; i--)
     {
      string nm = g_pfx + "WL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_lows[i].t, g_lows[i].price);
      ObjectSetString(0, nm, OBJPROP_TEXT, g_lows[i].isWeak ? "  weak low" : "  strong low");
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_lows[i].isWeak ? clrSilver : InpBullColor);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
      tagged++;
     }

   ChartRedraw();
  }

void DrawDashboard()
  {
   string n = g_pfx + "DASH";
   string trend = (g_trend == TREND_BULL ? "BULL" : (g_trend == TREND_BEAR ? "BEAR" : "FLAT"));
   double rsi = CurrentRSI();
   int evN = ArraySize(g_events);
   string last = "-";
   if(evN > 0)
      last = (g_events[evN - 1].isCHoCH ? "CHoCH " : "BOS ") + (g_events[evN - 1].dir > 0 ? "UP" : "DN");

   string s = "TWI TakeProfit SMC\n";
   s += "Trend: " + trend + "   Last: " + last + "\n";
   s += "RSI(" + IntegerToString(InpRSIPeriod) + "): " + DoubleToString(rsi, 1) + "\n";
   s += "Zones: " + IntegerToString(ArraySize(g_zones)) + "   Pos: " + IntegerToString(CountOurPositions()) + "\n";
   s += g_haltDay ? "DAY HALT" : (InSession() || !InpUseSessionFilter ? "SESSION OK" : "OUT OF SESSION");

   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 28);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
     }
   ObjectSetString(0, n, OBJPROP_TEXT, s);
  }

//+------------------------------------------------------------------+
