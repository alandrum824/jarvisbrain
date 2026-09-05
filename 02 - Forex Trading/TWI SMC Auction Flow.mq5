//+------------------------------------------------------------------+
//| TWI SMC Auction Flow                                             |
//|                                                                  |
//| Structure tells direction -> profile tells location ->           |
//| lower timeframe tells when -> liquidity tells where to exit.     |
//|                                                                  |
//| Built from first principles as an explicit state machine. No     |
//| proprietary indicator code. Nothing here requires six conditions |
//| to be true at the same instant: each state asks its own question |
//| and is only reached once the previous one is satisfied.          |
//|                                                                  |
//| NO LOOKAHEAD: every structural read uses closed bars only, a     |
//| pivot is unusable until objectively confirmable, and the volume  |
//| profile only ever sees data available at that historical moment. |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict
#property description "SMC Auction Flow: bias -> location -> confirmation -> execution -> management."

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
input ENUM_TIMEFRAMES InpBiasTF    = PERIOD_M15;
input ENUM_TIMEFRAMES InpContextTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M5;

input group "=== Structure ==="
input int    InpSwingLeft        = 3;
input int    InpSwingRight       = 3;
input int    InpStructLookback   = 300;
input double InpDisplacementATR  = 0.50;   // body size that qualifies a break as decisive
input bool   InpRequireDisplacement = true;

input group "=== Balance / consolidation ==="
input int    InpBalanceMinBars   = 4;
input int    InpBalanceMaxBars   = 12;
input double InpBalanceMaxATR    = 2.0;    // range width ceiling, in ATR
input double InpBalanceOverlap   = 0.60;   // fraction of bars that must overlap the range core

input group "=== Volume profile ==="
input bool   InpUseProfile       = true;
input int    InpProfileBars      = 96;     // rolling window on BiasTF
input int    InpProfileBins      = 50;
input double InpValueAreaPct     = 70.0;
input double InpHVNMult          = 1.30;   // bin volume vs average to count as HVN
input double InpLVNMult          = 0.50;

input group "=== Location ==="
input double InpLocTolATR        = 0.30;   // how close price must come to a level
input int    InpMaxLocationWait  = 80;     // BiasTF bars before abandoning the bias

input group "=== DXY context (optional, scored only) ==="
input bool   InpUseDXYContext    = false;
input string InpDXYSymbol        = "DXY";
input bool   InpDXYInverse       = true;   // instrument moves opposite to USD strength

input group "=== Confirmation ==="
input int    InpMaxConfirmWait   = 24;     // EntryTF bars at location
input double InpRejectionWick    = 0.45;
enum ENUM_ENTRY_MODE { ENTRY_CONFIRMATION_CLOSE, ENTRY_CONFIRMATION_RETEST };
input ENUM_ENTRY_MODE InpEntryMode = ENTRY_CONFIRMATION_CLOSE;
input int    InpRetestMaxBars    = 8;

input group "=== Confluence score ==="
input int    InpMinScore         = 5;
input bool   InpUseScoreGate     = true;

input group "=== Risk ==="
input double InpRiskPercent          = 0.50;
input double InpMaxActualRiskPercent = 0.60;
input double InpSLBufferATR          = 0.10;
input int    InpMaxPositions         = 1;
input int    InpMaxSpreadPoints      = 400;
input int    InpSlippagePoints       = 30;
input double InpDailyLossPercent     = 3.0;
input long   InpMagic                = 20260905;

input group "=== Trade geometry (defect fixes) ==="
// Evidence, Aug-2026 run: a 30% partial fired at +0.37R while the trade
// went on to +2.16R. Banking size at a fraction of the risk taken is
// indefensible regardless of threshold tuning.
// Held OFF for this run so the management-bypass fix is measured alone.
input double InpMinPartialR   = 0.00;   // never take a partial nearer than this
input double InpMinEntryRR    = 1.00;   // refuse entries whose nearest target is closer than the stop
input bool   InpRequireEntryRR = false;
input bool   InpFixDegenerateTargets = false;

input group "=== Management ==="
input double InpTP1ClosePct   = 30.0;
input double InpTP2ClosePct   = 30.0;
input double InpBEAfterR      = 1.0;      // never before this
input bool   InpStructureTrail = true;
input bool   InpExitOnOpposingCHoCH = true;

input group "=== Source modules: CRT / VP / AMT ==="
// Location objects taken from the source slides. These are additional
// ACCEPTED LOCATION SOURCES and confluence points -- never new AND-gates.
// With all three false, behaviour equals the current baseline.
input bool InpUseCRT          = false;  // frozen: uncompiled module, inert
input bool InpUseVP           = false;  // frozen: uncompiled module, inert
input bool InpUseAMTLevels    = false;  // frozen: uncompiled module, inert
input double InpVPValueAreaPct = 70.0;
input double InpVPBinPips      = 2.0;    // majors; on metals ATR*0.05 is used instead
input int    InpVPBinsMax      = 120;
// NOTE: this EA never had session clocks. These are carried over verbatim
// from TWI TakeProfit SMC EA rather than invented for this build.
input int    InpSessAsiaStart   = 0;
input int    InpSessAsiaEnd     = 7;
input int    InpSessLondonStart = 8;
input int    InpSessLondonEnd   = 12;
input int    InpSessNYStart     = 13;
input int    InpSessNYEnd       = 17;

input group "=== Diagnostics ==="
input bool   InpDebugStats  = true;
input bool   InpLogSetups   = true;
input bool   InpDrawVisuals = true;

//====================================================================
// TYPES
//====================================================================
enum EA_STATE
  {
   STATE_SCAN_BIAS,
   STATE_WAIT_LOCATION,
   STATE_WAIT_CONFIRMATION,
   STATE_READY_TO_ENTER,
   STATE_MANAGE_POSITION
  };

enum TREND { TR_NONE = 0, TR_BULL = 1, TR_BEAR = -1 };

enum PARTIAL_STATUS
  {
   PS_NOT_ATTEMPTED = 0,
   PS_EXECUTED,
   PS_SKIPPED_MIN_VOLUME,
   PS_SKIPPED_INVALID_REMAINDER,
   PS_FAILED_BROKER
  };
string PartialStatusName(int s)
  {
   switch(s)
     {
      case PS_EXECUTED:                 return("EXECUTED");
      case PS_SKIPPED_MIN_VOLUME:       return("SKIPPED_MIN_VOLUME");
      case PS_SKIPPED_INVALID_REMAINDER:return("SKIPPED_INVALID_REMAINDER");
      case PS_FAILED_BROKER:            return("FAILED_BROKER");
      default:                          return("NOT_ATTEMPTED");
     }
  }

struct Swing
  {
   datetime t;
   double   price;
   int      shift;
   bool     isHigh;
  };

// Structure read for one timeframe, including the protected swing that
// actually holds the auction together.
struct StructureView
  {
   TREND    trend;
   double   lastHigh, lastLow;
   double   protectedLow;    // bull: break this and character changes
   double   protectedHigh;   // bear
   datetime protectedTime;
   string   lastEvent;       // BOS_BULL / BOS_BEAR / CHOCH_BULL / CHOCH_BEAR
   datetime lastEventTime;
   double   lastEventLevel;
   bool     valid;
  };

// Candle Range Theory: the prior completed candle/session IS the dealing
// range. Sweep-then-reclaim of its edge is the bias tell.
struct CRT_Range
  {
   bool     valid;
   datetime tStart, tEnd;
   double   high, low, mid, open, close;
   int      direction;     // +1 closed up, -1 closed down
   bool     sweptHigh, sweptLow;
   bool     reclaimedHigh, reclaimedLow;
   string   label;
  };

// Session-fixed volume profile -- the beige box + histogram on the slides.
struct VP_Profile
  {
   bool     valid;
   datetime sessionStart, sessionEnd;
   double   priceLow, priceHigh, binSize;
   int      bins;
   double   vol[];
   double   poc, vah, val;
   double   hvn[];         // bins >= 70% of POC volume
   double   lvn[];
   string   source;        // TICK or REAL
  };

// AMT interaction levels: the session manipulation lines, not a new
// indicator. Built from the prior session box + prior POC + daily open.
struct AMT_Levels
  {
   bool   valid;
   double priorSessionHigh, priorSessionLow, priorSessionMid;
   double priorPOC;
   double dailyOpen;
  };

struct Balance
  {
   bool     valid;
   double   hi, lo, mid;
   datetime from, to;
   int      bars;
  };

struct Profile
  {
   bool   valid;
   double poc, vah, val;
   double binLo, binSize;
   int    bins;
   double vol[];
   string source;
  };

struct LiveTrade
  {
   // --- identity: never used interchangeably ---
   ulong  orderTicket;     // trade.ResultOrder()
   ulong  posIdentifier;   // DEAL_POSITION_ID -- the authoritative link
   ulong  posTicket;       // POSITION_TICKET as seen when selected
   ulong  dealTicketIn;    // opening DEAL_TICKET
   bool   idResolved;

   // --- structure snapshot taken AT ENTRY ---
   datetime entryTime;
   datetime entryM15Bar;
   int      entryStructState;
   double   entryProtLow, entryProtHigh;
   bool     entryContradiction;
   datetime lastProcM15;      // each closed M15 bar processed once
   bool     chochArmed;       // only after a new M15 bar closes post-entry
   bool     closed;
   string   exitReason;

   int    dir;
   // BUG #4: `entry` is authoritative and MUST be the executed DEAL_PRICE.
   // The pre-send quote is kept only for diagnostics and never owns R math.
   double entry, requestedEntry, rawSL, finalSL, riskPrice, riskMoney;
   double preSendRiskMoney;
   bool   fillSynced;
   double lastKnownSL;      // live POSITION_SL seen on the most recent manage pass
   datetime lastSLSeenAt;
   double tp1, tp2, tp3;
   double rr1, rr2, rr3;
   double mfeR, maeR;
   double initialVolume;
   double protectedLevel;    // opposing CHoCH level for early exit
   // A price milestone is market state. A partial close is an execution
   // side effect. They must never share a boolean.
   bool   tp1Reached, tp2Reached;
   int    tp1Status,  tp2Status;
   bool   beDone;
   int    idx;
   // Did the manager start interfering before the move developed?
   double mfeAtFirstAction;
   bool   firstActionTaken;
   string firstActionType;
   datetime mfePeakTime;      // when the peak excursion was recorded
   datetime lastUpdateTime;   // last time this record was touched while open
   bool   tp1Skipped;
  };

//====================================================================
// STATE
//====================================================================
EA_STATE      g_state = STATE_SCAN_BIAS;
int           g_bias  = 0;
string        g_biasReason = "";
StructureView g_biasStruct, g_ctxStruct;
Balance       g_balance;
Profile       g_profile;
LiveTrade     g_live[];

double  g_locPrice = 0, g_locHi = 0, g_locLo = 0;
string  g_locName = "";
int     g_locWait = 0, g_confWait = 0, g_retestWait = 0;
string  g_confName = "";
int     g_score = 0;
double  g_confHigh = 0, g_confLow = 0;
bool    g_awaitRetest = false;

datetime g_lastBiasBar = 0, g_lastEntryBar = 0, g_dayStamp = 0;
double   g_dayStartEquity = 0;
bool     g_dayHalt = false;
int      g_atrBiasH = INVALID_HANDLE, g_atrEntryH = INVALID_HANDLE;
long     g_tradeNo = 0, g_objNo = 0;

//--- funnel
long f_sessions=0, f_bull=0, f_bear=0, f_neutral=0;
long f_bosBull=0, f_bosBear=0, f_chochBull=0, f_chochBear=0;
long f_balances=0, f_locArmed=0, f_locReached=0, f_locTimeout=0;
long f_profileConf=0, f_structConf=0, f_dxyAgree=0, f_dxyDisagree=0;
long f_microConf=0, f_confTimeout=0, f_scorePass=0, f_scoreFail=0;
long f_entries=0, f_buys=0, f_sells=0, f_riskRejected=0, f_spreadBlocked=0, f_haltBlocked=0;
long f_scoreHist[16];
long r_closed=0, r_wins=0, r_losses=0, r_mismatch=0, r_lossMFE1R=0;
double r_sumWinR=0, r_sumLossR=0, r_sumMFE=0, r_sumMAE=0;
double r_riskSum=0, r_riskMin=99999, r_riskMax=0; long r_riskN=0;
double r_streakWorst=0; long r_lossStreak=0, r_worstLossStreak=0;

//--- rejection reasons
long x_noBias=0, x_noLocation=0, x_locTimeout=0, x_noConfirmation=0;
long x_confTimeout=0, x_scoreFail=0, x_riskReject=0, x_maxPosReject=0;

//--- confirmation types
long t_microCHoCH=0, t_microBOS=0, t_reclaim=0, t_engulf=0, t_rejection=0, t_displacement=0;

//--- location types (index matches LocTypeName)
long t_loc[10];
string LocTypeName(int i)
  {
   switch(i)
     {
      case 0: return("STRUCT_SUPPORT/RESISTANCE");
      case 1: return("PROTECTED_SWING");
      case 2: return("BROKEN_STRUCTURE");
      case 3: return("BALANCE_BOUNDARY");
      case 4: return("BALANCE_MID");
      case 5: return("VAH");
      case 6: return("VAL");
      case 7: return("POC");
      case 8: return("PREV_DAY_HIGH/LOW");
      default: return("OTHER");
     }
  }
int LocTypeIndex(string n)
  {
   if(n == "STRUCT_SUPPORT" || n == "STRUCT_RESISTANCE") return(0);
   if(n == "PROTECTED_LOW"  || n == "PROTECTED_HIGH")    return(1);
   if(n == "BROKEN_STRUCTURE")  return(2);
   if(n == "BALANCE_BOUNDARY")  return(3);
   if(n == "BALANCE_MID")       return(4);
   if(n == "VAH") return(5);
   if(n == "VAL") return(6);
   if(n == "POC") return(7);
   if(n == "PREV_DAY_LOW" || n == "PREV_DAY_HIGH") return(8);
   return(9);
  }

//--- shadow counters (diagnostic only -- these never trade)
long s_balOverlap50=0, s_balOverlap60=0, s_balOverlap70=0;
long s_locTol20=0, s_locTol30=0, s_locTol40=0;
bool s_tolHit20=false, s_tolHit30=false, s_tolHit40=false;
long s_barsToLocSum=0, s_barsToLocN=0, s_barsToLocMax=0;
long s_barsToConfSum=0, s_barsToConfN=0, s_barsToConfMax=0;

//--- structure / profile diagnostics
long d_swingHighs=0, d_swingLows=0, d_protectedSet=0;
long d_profilesBuilt=0, d_profReal=0, d_profTick=0;
long d_hitPOC=0, d_hitVAH=0, d_hitVAL=0, d_hitHVN=0, d_hitLVN=0;
double d_balBarsSum=0, d_balWidthATRSum=0; long d_balN=0;

//--- distributions
long m_mfeBucket[6];   // <0, 0-0.5, 0.5-1, 1-2, 2-3, >3 (R)
long m_maeBucket[5];   // 0, 0 to -0.5, -0.5 to -1, -1 to -1.5, < -1.5
double m_riskPcts[];
double m_eqR=0, m_eqPeakR=0, m_maxDDR=0;

//====================================================================
// SHADOW FORENSICS — observes what WOULD have happened to every
// confirmed setup, including ones the live EA refused. Creates no
// orders and changes no trading condition.
//====================================================================
input group "=== Shadow forensics ==="
input bool InpShadowTracking   = true;
input int  InpShadowHorizonBars = 288;   // EntryTF bars (~24h on M5)

struct Shadow
  {
   int      idx;
   datetime t;
   int      dir;
   int      score;
   string   locType, confType;
   double   entry, sl, risk;
   double   mfeR, maeR;
   bool     r05, r1, r15, r2, r3, stopped;
   bool     oneRFirst;        // +1R before -1R
   bool     beAfter1R;        // came back to entry after tagging +1R
   double   maxRAfter1R;
   bool     comps[9];
   bool     passedScore, wasEntered, maxPosBlocked;
   bool     blockedM15;      // refused by the M15 validity gate
   bool     active;
   int      bars;
  };
Shadow s_list[];
long s_finalized = 0;

//--- correctness counters
long k_chochExits=0, k_chochWithin1=0, k_chochWithin2=0, k_entryContradiction=0;
long k_beAttempts=0, k_beVerified=0, k_beFailed=0;
long k_posIdMismatch=0, k_mfeSanity=0, k_realizedSanity=0;
long k_chochSuppressedPreexisting=0;

//--- M15 owns trade validity
datetime g_setupCreatedTime = 0, g_protLevelCreatedTime = 0, g_protBrokenTime = 0;
double   g_setupProtLevel = 0;
bool     g_setupInvalidated = false;
long v_setupsCreated=0, v_invalidBeforeLocation=0, v_invalidBeforeConfirm=0;
long v_contradictionsDetected=0, v_contradictionsTraded=0, v_blockedAtEntry=0;
long v_shadowBlocked=0, v_shadowBlocked1R=0, v_shadowBlockedStopFirst=0;
long g_geometryRejects=0; double g_geometryRejectRRSum=0;

//--- partial-lot deadlock forensics
long k_tp1Reached=0, k_tp1Executed=0, k_tp1SkippedMinVol=0, k_tp1SkippedRemainder=0, k_tp1Failed=0;
long k_tp2Reached=0, k_tp2Executed=0, k_tp2SkippedMinVol=0, k_tp2SkippedRemainder=0, k_tp2Failed=0;
long k_beAfterSkipped=0, k_trailAfterSkipped=0, k_chochAfterSkipped=0;
long k_mfe1RthenLoss=0, k_mfe2RthenLoss=0, k_mfe3RthenLoss=0, k_firstActionNone=0;

//--- bug #4: fill-price integrity
double k_fillDeltas[];
long   k_fillExact=0, k_fillDiffer=0, k_requestedQuoteUsedAfterFill=0;
long   k_trailCandidates=0, k_trailAccepted=0, k_stopLoosenBlocked=0, k_invariantViolations=0;
double v_shadowBlockedMFE=0, v_shadowBlockedMAE=0;

//====================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_atrBiasH  = iATR(_Symbol, InpBiasTF, 14);
   g_atrEntryH = iATR(_Symbol, InpEntryTF, 14);
   if(g_atrBiasH == INVALID_HANDLE || g_atrEntryH == INVALID_HANDLE) return(INIT_FAILED);

   g_dayStamp = iTime(_Symbol, PERIOD_D1, 0);
   g_dayStartEquity = account.Equity();
   ArrayInitialize(f_scoreHist, 0);
   Print("TWI SMC Auction Flow init | bias=", EnumToString(InpBiasTF),
         " context=", EnumToString(InpContextTF), " entry=", EnumToString(InpEntryTF));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_atrBiasH  != INVALID_HANDLE) IndicatorRelease(g_atrBiasH);
   if(g_atrEntryH != INVALID_HANDLE) IndicatorRelease(g_atrEntryH);
   if(InpDrawVisuals) ObjectsDeleteAll(0, "AF_");
   if(!InpDebugStats) return;

   double avgWinR  = (r_wins   > 0) ? r_sumWinR  / r_wins   : 0;
   double avgLossR = (r_losses > 0) ? r_sumLossR / r_losses : 0;
   double expR     = (r_closed > 0) ? (r_sumWinR + r_sumLossR) / r_closed : 0;
   double pfR      = (r_sumLossR != 0) ? r_sumWinR / MathAbs(r_sumLossR) : 0;
   string hist = "";
   for(int i = 0; i <= 15; i++) if(f_scoreHist[i] > 0) hist += StringFormat("%d:%d ", i, f_scoreHist[i]);

   PrintFormat("=== AUCTION FLOW FUNNEL ===\nBias evaluations: %d (bull %d | bear %d | neutral %d)\nStructure events: BOS_BULL %d | BOS_BEAR %d | CHOCH_BULL %d | CHOCH_BEAR %d\nBalances detected: %d\nLocations armed: %d | reached: %d | timed out: %d\nConfluence seen: profile %d | structure %d | DXY agree %d / disagree %d\nMicro confirmations: %d | confirmation timeouts: %d\nScore pass %d | fail %d | distribution: %s\nBlocked: spread %d | daily halt %d | risk %d\nENTRIES: %d (buy %d | sell %d)",
               f_sessions, f_bull, f_bear, f_neutral,
               f_bosBull, f_bosBear, f_chochBull, f_chochBear,
               f_balances, f_locArmed, f_locReached, f_locTimeout,
               f_profileConf, f_structConf, f_dxyAgree, f_dxyDisagree,
               f_microConf, f_confTimeout, f_scorePass, f_scoreFail,
               hist == "" ? "(none)" : hist,
               f_spreadBlocked, f_haltBlocked, f_riskRejected,
               f_entries, f_buys, f_sells);

   PrintFormat("=== AUCTION FLOW RESULTS ===\nClosed deals: %d | wins %d | losses %d | win rate %.1f%%\nAvg win %.2fR | avg loss %.2fR | expectancy %.3fR | R-PF %.2f\nAvg MFE %.2fR | avg MAE %.2fR | losers reaching +1R: %d of %d\nLongest losing streak: %d\nActual risk %%: min %.3f | avg %.3f | max %.3f\nRisk-model mismatches: %d",
               r_closed, r_wins, r_losses, r_closed > 0 ? 100.0 * r_wins / r_closed : 0,
               avgWinR, avgLossR, expR, pfR,
               r_closed > 0 ? r_sumMFE / r_closed : 0,
               r_closed > 0 ? r_sumMAE / r_closed : 0,
               r_lossMFE1R, r_losses, r_worstLossStreak,
               r_riskN > 0 ? r_riskMin : 0, r_riskN > 0 ? r_riskSum / r_riskN : 0, r_riskMax,
               r_mismatch);

   PrintFormat("=== WHY SETUPS DIED ===\nNO_BIAS: %d\nNO_LOCATION: %d\nLOCATION_TIMEOUT: %d\nNO_CONFIRMATION: %d\nCONFIRMATION_TIMEOUT: %d\nSCORE_FAIL: %d\nRISK_REJECT: %d\nMAX_POSITION_REJECT: %d",
               x_noBias, x_noLocation, x_locTimeout, x_noConfirmation,
               x_confTimeout, f_scoreFail, f_riskRejected, x_maxPosReject);

   PrintFormat("=== CONFIRMATION TYPES ===\nMicro CHoCH: %d | Micro BOS: %d | Reclaim: %d | Engulf: %d | Rejection: %d | Displacement: %d",
               t_microCHoCH, t_microBOS, t_reclaim, t_engulf, t_rejection, t_displacement);

   string locLine = "";
   for(int i = 0; i <= 9; i++) if(t_loc[i] > 0) locLine += StringFormat("%s=%d  ", LocTypeName(i), t_loc[i]);
   PrintFormat("=== LOCATION TYPES ===\n%s", locLine == "" ? "(none)" : locLine);

   PrintFormat("=== SHADOW TESTS (diagnostic only, never traded) ===\nBalance overlap qualifying: 0.50 -> %d | 0.60 (live) -> %d | 0.70 -> %d\nLocation tolerance reached: 0.20ATR -> %d | 0.30ATR (live) -> %d | 0.40ATR -> %d\nBars to reach location: avg %.1f | max %d (timeout is %d)\nBars to confirm: avg %.1f | max %d (timeout is %d)",
               s_balOverlap50, s_balOverlap60, s_balOverlap70,
               s_locTol20, s_locTol30, s_locTol40,
               s_barsToLocN > 0 ? (double)s_barsToLocSum / s_barsToLocN : 0, s_barsToLocMax, InpMaxLocationWait,
               s_barsToConfN > 0 ? (double)s_barsToConfSum / s_barsToConfN : 0, s_barsToConfMax, InpMaxConfirmWait);

   PrintFormat("=== STRUCTURE DIAGNOSTICS ===\nBalances detected: %d | avg duration %.1f bars | avg width %.2f ATR\nProtected swings set: %d",
               f_balances,
               d_balN > 0 ? d_balBarsSum / d_balN : 0,
               d_balN > 0 ? d_balWidthATRSum / d_balN : 0,
               d_protectedSet);

   PrintFormat("=== VOLUME PROFILE DIAGNOSTICS ===\nProfiles built: %d | source REAL %d / TICK %d\nLocation chosen at: POC %d | VAH %d | VAL %d | HVN node %d | LVN node %d",
               d_profilesBuilt, d_profReal, d_profTick,
               d_hitPOC, d_hitVAH, d_hitVAL, d_hitHVN, d_hitLVN);

   double medRisk = 0;
   int rn = ArraySize(m_riskPcts);
   if(rn > 0) { ArraySort(m_riskPcts); medRisk = (rn % 2 == 1) ? m_riskPcts[rn/2] : (m_riskPcts[rn/2 - 1] + m_riskPcts[rn/2]) / 2.0; }

   PrintFormat("=== DISTRIBUTIONS ===\nMFE(R): <0 %d | 0-0.5 %d | 0.5-1 %d | 1-2 %d | 2-3 %d | >3 %d\nMAE(R): ~0 %d | 0..-0.5 %d | -0.5..-1 %d | -1..-1.5 %d | <-1.5 %d\nMax drawdown in R: %.2f\nActual risk %%: min %.3f | median %.3f | mean %.3f | max %.3f",
               m_mfeBucket[0], m_mfeBucket[1], m_mfeBucket[2], m_mfeBucket[3], m_mfeBucket[4], m_mfeBucket[5],
               m_maeBucket[0], m_maeBucket[1], m_maeBucket[2], m_maeBucket[3], m_maeBucket[4],
               m_maxDDR,
               rn > 0 ? m_riskPcts[0] : 0, medRisk,
               r_riskN > 0 ? r_riskSum / r_riskN : 0, r_riskMax);

   // flush any shadows still open at end of test so nothing is lost
   for(int i = 0; i < ArraySize(s_list); i++) if(s_list[i].active) ShadowFinalize(i);
   PrintFormat("=== SHADOW SUMMARY === tracked=%d finalized=%d (SHADOW lines above carry the per-setup forensics)",
               ArraySize(s_list), s_finalized);

   PrintFormat("=== M15 VALIDITY GATE ===\nM15 setups created: %d\nInvalidated before location reached: %d\nInvalidated before confirmation: %d\nM5 confirmations: %d\nENTRY_STRUCTURE_CONTRADICTIONS detected: %d\nENTRY_STRUCTURE_CONTRADICTIONS traded (must be 0): %d\nBlocked at final entry gate: %d",
               v_setupsCreated, v_invalidBeforeLocation, v_invalidBeforeConfirm,
               f_microConf, v_contradictionsDetected, v_contradictionsTraded, v_blockedAtEntry);

   PrintFormat("=== SHADOW: SETUPS BLOCKED BY M15 GATE (never traded) ===\nCount: %d\nAvg MFE %.2fR | avg MAE %.2fR\nReached +1R: %d (%.1f%%)\nStopped before +1R: %d (%.1f%%)",
               v_shadowBlocked,
               v_shadowBlocked > 0 ? v_shadowBlockedMFE / v_shadowBlocked : 0,
               v_shadowBlocked > 0 ? v_shadowBlockedMAE / v_shadowBlocked : 0,
               v_shadowBlocked1R, v_shadowBlocked > 0 ? 100.0 * v_shadowBlocked1R / v_shadowBlocked : 0,
               v_shadowBlockedStopFirst, v_shadowBlocked > 0 ? 100.0 * v_shadowBlockedStopFirst / v_shadowBlocked : 0);

   int fn = ArraySize(k_fillDeltas);
   double fMean = 0, fMed = 0, fMax = 0;
   if(fn > 0)
     {
      double cp[]; ArrayResize(cp, fn); ArrayCopy(cp, k_fillDeltas, 0, 0, fn); ArraySort(cp);
      for(int i = 0; i < fn; i++) { fMean += cp[i]; if(cp[i] > fMax) fMax = cp[i]; }
      fMean /= fn;
      fMed = (fn % 2 == 1) ? cp[fn/2] : (cp[fn/2 - 1] + cp[fn/2]) / 2.0;
     }
   PrintFormat("=== MANAGEMENT CORRECTNESS (refactor) ===\nSTATE_INVARIANT_VIOLATIONS: %d\nSTOP_LOOSEN_BLOCKED: %d\nTrail candidates: %d | trail accepted: %d\nBE verified: %d | BE failed: %d\n--- regression, all prior bug classes ---\nstanding-state CHoCH exits suppressed: %d (must be >0 only as suppression, never as exits)\nCHoCH exits within 2 bias bars: %d (expect 0)\npartial-lot deadlock (skipped then unmanaged): %d (expect 0)\nTP2 SKIPPED_INVALID_REMAINDER: %d (expect 0)\nrequestedQuoteUsedAfterFill: %d (expect 0)",
               k_invariantViolations, k_stopLoosenBlocked,
               k_trailCandidates, k_trailAccepted, k_beVerified, k_beFailed,
               k_chochSuppressedPreexisting, k_chochWithin2,
               (k_tp1SkippedMinVol + k_tp1SkippedRemainder) - (k_beAfterSkipped + k_trailAfterSkipped + k_chochAfterSkipped) > 0
                  ? (k_tp1SkippedMinVol + k_tp1SkippedRemainder) - (k_beAfterSkipped + k_trailAfterSkipped + k_chochAfterSkipped) : 0,
               k_tp2SkippedRemainder, k_requestedQuoteUsedAfterFill);

   PrintFormat("=== FILL-PRICE INTEGRITY (bug #4) ===\nR_ENTRY_SOURCE=DEAL_PRICE\nEntries with fill recorded: %d\nMean |fill delta|: %.2f pts | median: %.2f | max: %.2f\nFill == request (within 1 pt): %d | differ: %d\nrequestedQuoteUsedAfterFill: %d",
               fn, fMean, fMed, fMax, k_fillExact, k_fillDiffer, k_requestedQuoteUsedAfterFill);

   PrintFormat("=== PARTIAL-LOT DEADLOCK FIX ===\nTP1 reached: %d | executed %d | skipped(minVol) %d | skipped(remainder) %d | broker-failed %d\nTP2 reached: %d | executed %d | skipped(minVol) %d | skipped(remainder) %d | broker-failed %d\nManagement that ran DESPITE an impossible partial:\n  breakeven activations: %d | trail activations: %d | CHoCH exits: %d\nLosses after reaching +1R: %d | after +2R: %d | after +3R: %d\nLosses with firstAction=NONE: %d",
               k_tp1Reached, k_tp1Executed, k_tp1SkippedMinVol, k_tp1SkippedRemainder, k_tp1Failed,
               k_tp2Reached, k_tp2Executed, k_tp2SkippedMinVol, k_tp2SkippedRemainder, k_tp2Failed,
               k_beAfterSkipped, k_trailAfterSkipped, k_chochAfterSkipped,
               k_mfe1RthenLoss, k_mfe2RthenLoss, k_mfe3RthenLoss, k_firstActionNone);

   PrintFormat("=== TRADE GEOMETRY (defect fixes) ===\nEntries refused for insufficient reward-to-risk: %d (avg best RR of refused %.2f)\nMinimum partial distance: %.2fR | minimum entry RR: %.2f",
               g_geometryRejects,
               g_geometryRejects > 0 ? g_geometryRejectRRSum / g_geometryRejects : 0,
               InpMinPartialR, InpMinEntryRR);

   PrintFormat("=== CORRECTNESS CONTROL ===\nTotal entries: %d\nOpposing-CHoCH exits (new event only): %d\n  within 1 bias bar: %d | within 2: %d\nPre-existing breaks suppressed (would have fired under old logic): %d\nEntry structure contradictions: %d\nBreakeven attempts: %d | verified: %d | failed: %d\nPosition-ID mismatches: %d\nMFE sanity violations: %d\nRealized-R sanity violations: %d",
               f_entries, k_chochExits, k_chochWithin1, k_chochWithin2,
               k_chochSuppressedPreexisting, k_entryContradiction,
               k_beAttempts, k_beVerified, k_beFailed,
               k_posIdMismatch, k_mfeSanity, k_realizedSanity);

   if(f_entries == 0)
      Print("ZERO_TRADE_DIAGNOSTIC | no entries. Read the funnel above for where candidates died. No rule was auto-loosened.");
  }

//====================================================================
// HELPERS
//====================================================================
double ATRv(int h) { double b[]; if(CopyBuffer(h,0,1,1,b)!=1) return(0); return(b[0]); }

bool NewBar(ENUM_TIMEFRAMES tf, datetime &last)
  { datetime t = iTime(_Symbol, tf, 0); if(t == last) return(false); last = t; return(true); }

bool SpreadOK() { return(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints); }

int CountOwn()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     { if(!posInfo.SelectByIndex(i)) continue;
       if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) n++; }
   return(n);
  }

void DrawBox(string tag, datetime t1, double p1, datetime t2, double p2, color c)
  {
   if(!InpDrawVisuals) return;
   string n = StringFormat("AF_%s_%d", tag, g_objNo++);
   ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
  }

void DrawTag(string tag, datetime t, double p, string text, color c)
  {
   if(!InpDrawVisuals) return;
   string n = StringFormat("AF_%s_%d", tag, g_objNo++);
   ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
  }

void DrawLevel(string tag, double price, color c, ENUM_LINE_STYLE st)
  {
   if(!InpDrawVisuals || price <= 0) return;
   string n = StringFormat("AF_%s_%d", tag, g_objNo++);
   ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
  }

//====================================================================
// SWINGS — confirmed pivots only, closed bars only (no repaint)
//====================================================================
int CollectSwings(ENUM_TIMEFRAMES tf, bool wantHighs, Swing &out[], int maxCount)
  {
   ArrayResize(out, 0);
   int lookback = InpStructLookback;
   double v[]; datetime tm[];
   ArraySetAsSeries(v, true); ArraySetAsSeries(tm, true);
   int got = wantHighs ? CopyHigh(_Symbol, tf, 1, lookback, v) : CopyLow(_Symbol, tf, 1, lookback, v);
   if(got < lookback) return(0);
   if(CopyTime(_Symbol, tf, 1, lookback, tm) < lookback) return(0);

   int n = 0;
   for(int i = InpSwingRight; i < lookback - InpSwingLeft && n < maxCount; i++)
     {
      bool ok = true;
      for(int k = 1; k <= InpSwingLeft && ok; k++)
         if(wantHighs ? (v[i+k] > v[i]) : (v[i+k] < v[i])) ok = false;
      for(int k = 1; k <= InpSwingRight && ok; k++)
         if(wantHighs ? (v[i-k] > v[i]) : (v[i-k] < v[i])) ok = false;
      if(!ok) continue;
      ArrayResize(out, n + 1);
      out[n].t = tm[i]; out[n].price = v[i]; out[n].shift = i + 1; out[n].isHigh = wantHighs;
      n++;
     }
   return(n);   // index 0 = most recent
  }

//====================================================================
// STRUCTURE ENGINE — trend, protected swing, BOS vs CHoCH
//
// A protected low is the swing low that produced the displacement which
// broke the previous meaningful high. Bullish character survives until
// THAT low is decisively closed through -- not every countertrend wiggle.
//====================================================================
StructureView ReadStructure(ENUM_TIMEFRAMES tf, double atr)
  {
   StructureView s;
   s.trend = TR_NONE; s.valid = false; s.lastEvent = "";
   s.protectedLow = 0; s.protectedHigh = 0; s.lastEventLevel = 0;
   s.lastHigh = 0; s.lastLow = 0; s.protectedTime = 0; s.lastEventTime = 0;

   Swing hs[], ls[];
   int nh = CollectSwings(tf, true,  hs, 12);
   int nl = CollectSwings(tf, false, ls, 12);
   if(nh < 2 || nl < 2) return(s);

   s.lastHigh = hs[0].price;
   s.lastLow  = ls[0].price;

   bool hh = hs[0].price > hs[1].price;
   bool hl = ls[0].price > ls[1].price;
   bool lh = hs[0].price < hs[1].price;
   bool ll = ls[0].price < ls[1].price;
   if(hh && hl)      s.trend = TR_BULL;
   else if(lh && ll) s.trend = TR_BEAR;

   // Protected swing: for a bull, the most recent swing low that sits
   // BELOW the last confirmed high in time -- i.e. the origin of the leg
   // that made that high.
   if(s.trend == TR_BULL)
     {
      for(int i = 0; i < nl; i++)
         if(ls[i].t < hs[0].t) { s.protectedLow = ls[i].price; s.protectedTime = ls[i].t; break; }
      if(s.protectedLow <= 0) { s.protectedLow = ls[0].price; s.protectedTime = ls[0].t; }
     }
   if(s.trend == TR_BEAR)
     {
      for(int i = 0; i < nh; i++)
         if(hs[i].t < ls[0].t) { s.protectedHigh = hs[i].price; s.protectedTime = hs[i].t; break; }
      if(s.protectedHigh <= 0) { s.protectedHigh = hs[0].price; s.protectedTime = hs[0].t; }
     }

   // Event classification on the last closed bar of this timeframe.
   double c1 = iClose(_Symbol, tf, 1), o1 = iOpen(_Symbol, tf, 1);
   double body = MathAbs(c1 - o1);
   bool decisive = (!InpRequireDisplacement) || (atr > 0 && body >= InpDisplacementATR * atr);

   if(decisive)
     {
      if(c1 > hs[0].price && s.trend != TR_BEAR)
        { s.lastEvent = "BOS_BULL";  s.lastEventLevel = hs[0].price; }
      else if(c1 < ls[0].price && s.trend != TR_BULL)
        { s.lastEvent = "BOS_BEAR";  s.lastEventLevel = ls[0].price; }
      else if(s.protectedLow > 0 && c1 < s.protectedLow)
        { s.lastEvent = "CHOCH_BEAR"; s.lastEventLevel = s.protectedLow; }
      else if(s.protectedHigh > 0 && c1 > s.protectedHigh)
        { s.lastEvent = "CHOCH_BULL"; s.lastEventLevel = s.protectedHigh; }
      if(s.lastEvent != "") s.lastEventTime = iTime(_Symbol, tf, 1);
     }

   s.valid = true;
   return(s);
  }

//====================================================================
// BALANCE / CONSOLIDATION — expansion, balance, expansion
//====================================================================
Balance DetectBalance(ENUM_TIMEFRAMES tf, double atr)
  {
   Balance b; b.valid = false; b.hi = 0; b.lo = 0; b.mid = 0; b.bars = 0; b.from = 0; b.to = 0;
   if(atr <= 0) return(b);

   for(int len = InpBalanceMaxBars; len >= InpBalanceMinBars; len--)
     {
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = 1; i <= len; i++)
        { hi = MathMax(hi, iHigh(_Symbol, tf, i)); lo = MathMin(lo, iLow(_Symbol, tf, i)); }
      double width = hi - lo;
      if(width <= 0 || width > InpBalanceMaxATR * atr) continue;

      // overlap test: bodies should mostly sit inside the middle of the range
      double coreHi = hi - width * 0.25, coreLo = lo + width * 0.25;
      int inside = 0;
      for(int i = 1; i <= len; i++)
        {
         double c = iClose(_Symbol, tf, i);
         if(c <= coreHi && c >= coreLo) inside++;
        }
      double frac = (double)inside / len;
      // shadow: how many balances would qualify at other thresholds
      if(frac >= 0.50) s_balOverlap50++;
      if(frac >= 0.60) s_balOverlap60++;
      if(frac >= 0.70) s_balOverlap70++;
      if(frac < InpBalanceOverlap) continue;

      d_balBarsSum += len; d_balWidthATRSum += width / atr; d_balN++;

      b.valid = true; b.hi = hi; b.lo = lo; b.mid = (hi + lo) / 2.0; b.bars = len;
      b.from = iTime(_Symbol, tf, len); b.to = iTime(_Symbol, tf, 1);
      return(b);
     }
   return(b);
  }

//====================================================================
// VOLUME PROFILE — POC / VAH / VAL / HVN / LVN
// Uses real volume when the broker supplies it, otherwise tick volume,
// and says which in the log rather than pretending.
//====================================================================
bool BuildProfile(ENUM_TIMEFRAMES tf, int bars, Profile &p)
  {
   p.valid = false; p.bins = InpProfileBins;
   if(bars < 10 || p.bins < 5) return(false);

   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 1; i <= bars; i++)
     { hi = MathMax(hi, iHigh(_Symbol, tf, i)); lo = MathMin(lo, iLow(_Symbol, tf, i)); }
   if(hi <= lo) return(false);

   p.binLo = lo; p.binSize = (hi - lo) / p.bins;
   ArrayResize(p.vol, p.bins);
   ArrayInitialize(p.vol, 0.0);

   long realTotal = 0;
   for(int i = 1; i <= bars; i++) realTotal += (long)iRealVolume(_Symbol, tf, i);
   bool useReal = (realTotal > 0);
   p.source = useReal ? "REAL" : "TICK";

   for(int i = 1; i <= bars; i++)
     {
      double bh = iHigh(_Symbol, tf, i), bl = iLow(_Symbol, tf, i);
      double v  = useReal ? (double)iRealVolume(_Symbol, tf, i) : (double)iVolume(_Symbol, tf, i);
      if(v <= 0) continue;
      int b1 = (int)MathFloor((bl - p.binLo) / p.binSize);
      int b2 = (int)MathFloor((bh - p.binLo) / p.binSize);
      b1 = MathMax(0, MathMin(p.bins - 1, b1));
      b2 = MathMax(0, MathMin(p.bins - 1, b2));
      int span = b2 - b1 + 1;
      double share = v / span;
      for(int b = b1; b <= b2; b++) p.vol[b] += share;
     }

   int poc = 0;
   double total = 0;
   for(int b = 0; b < p.bins; b++) { total += p.vol[b]; if(p.vol[b] > p.vol[poc]) poc = b; }
   if(total <= 0) return(false);
   p.poc = p.binLo + (poc + 0.5) * p.binSize;

   // value area: expand from POC toward the heavier neighbour
   double target = total * InpValueAreaPct / 100.0;
   double acc = p.vol[poc];
   int up = poc, dn = poc;
   while(acc < target && (up < p.bins - 1 || dn > 0))
     {
      double vu = (up < p.bins - 1) ? p.vol[up + 1] : -1;
      double vd = (dn > 0)          ? p.vol[dn - 1] : -1;
      if(vu >= vd && vu >= 0) { up++; acc += vu; }
      else if(vd >= 0)        { dn--; acc += vd; }
      else break;
     }
   p.val = p.binLo + dn * p.binSize;
   p.vah = p.binLo + (up + 1) * p.binSize;
   p.valid = true;
   return(true);
  }

bool ProfileNode(Profile &p, double price, bool wantHVN)
  {
   if(!p.valid) return(false);
   double avg = 0;
   for(int b = 0; b < p.bins; b++) avg += p.vol[b];
   avg /= p.bins;
   int idx = (int)MathFloor((price - p.binLo) / p.binSize);
   if(idx < 0 || idx >= p.bins) return(false);
   return(wantHVN ? (p.vol[idx] >= avg * InpHVNMult) : (p.vol[idx] <= avg * InpLVNMult));
  }

//====================================================================
// PRIOR SESSION LEVELS
//====================================================================
void PrevDayHiLo(double &hi, double &lo)
  {
   hi = iHigh(_Symbol, PERIOD_D1, 1);
   lo = iLow (_Symbol, PERIOD_D1, 1);
  }

//====================================================================
// DXY CONTEXT — scored, never a gate
//====================================================================
int DXYBias()
  {
   if(!InpUseDXYContext) return(0);
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if(CopyHigh(InpDXYSymbol, InpContextTF, 1, 60, h) < 60) return(0);
   if(CopyLow (InpDXYSymbol, InpContextTF, 1, 60, l) < 60) return(0);
   double recentHi = h[ArrayMaximum(h, 0, 20)], olderHi = h[ArrayMaximum(h, 20, 40)];
   double recentLo = l[ArrayMinimum(l, 0, 20)], olderLo = l[ArrayMinimum(l, 20, 40)];
   if(recentHi > olderHi && recentLo > olderLo) return(+1);
   if(recentHi < olderHi && recentLo < olderLo) return(-1);
   return(0);
  }

//====================================================================
// STATE 2 — LOCATION (OR of legitimate execution areas)
//====================================================================
bool ArmLocation(int bias, double atr)
  {
   double tol = InpLocTolATR * atr;
   double px  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string best = ""; double bestPrice = 0, bestDist = DBL_MAX;

   double cands[]; string names[];
   int n = 0;
   ArrayResize(cands, 16); ArrayResize(names, 16);

   // 1/9: structural support/resistance + protected swing
   if(bias > 0)
     {
      if(g_biasStruct.lastLow > 0)      { cands[n] = g_biasStruct.lastLow;      names[n] = "STRUCT_SUPPORT";  n++; }
      if(g_biasStruct.protectedLow > 0) { cands[n] = g_biasStruct.protectedLow; names[n] = "PROTECTED_LOW";   n++; }
     }
   else
     {
      if(g_biasStruct.lastHigh > 0)      { cands[n] = g_biasStruct.lastHigh;      names[n] = "STRUCT_RESISTANCE"; n++; }
      if(g_biasStruct.protectedHigh > 0) { cands[n] = g_biasStruct.protectedHigh; names[n] = "PROTECTED_HIGH";    n++; }
     }

   // 2: broken structure retest
   if(g_biasStruct.lastEventLevel > 0)
     { cands[n] = g_biasStruct.lastEventLevel; names[n] = "BROKEN_STRUCTURE"; n++; }

   // 3: balance boundary
   if(g_balance.valid)
     {
      cands[n] = (bias > 0) ? g_balance.lo : g_balance.hi;
      names[n] = "BALANCE_BOUNDARY"; n++;
      cands[n] = g_balance.mid; names[n] = "BALANCE_MID"; n++;
     }

   // 4/5/6: value area and POC
   if(InpUseProfile && g_profile.valid)
     {
      cands[n] = (bias > 0) ? g_profile.val : g_profile.vah;
      names[n] = (bias > 0) ? "VAL" : "VAH"; n++;
      cands[n] = g_profile.poc; names[n] = "POC"; n++;
     }

   // 8: prior day high/low
   double pdh, pdl; PrevDayHiLo(pdh, pdl);
   if(bias > 0 && pdl > 0) { cands[n] = pdl; names[n] = "PREV_DAY_LOW";  n++; }
   if(bias < 0 && pdh > 0) { cands[n] = pdh; names[n] = "PREV_DAY_HIGH"; n++; }

   // choose the nearest sensible level that price has NOT already passed through
   for(int i = 0; i < n; i++)
     {
      if(cands[i] <= 0) continue;
      if(bias > 0 && cands[i] > px + tol) continue;   // buy locations sit below/at price
      if(bias < 0 && cands[i] < px - tol) continue;
      double d = MathAbs(px - cands[i]);
      if(d < bestDist) { bestDist = d; bestPrice = cands[i]; best = names[i]; }
     }
   if(best == "") return(false);

   g_locPrice = bestPrice;
   g_locHi = bestPrice + tol;
   g_locLo = bestPrice - tol;
   g_locName = best;
   t_loc[LocTypeIndex(best)]++;
   if(best == "POC") d_hitPOC++;
   if(best == "VAH") d_hitVAH++;
   if(best == "VAL") d_hitVAL++;
   if(InpUseProfile && g_profile.valid)
     {
      if(ProfileNode(g_profile, bestPrice, true))  d_hitHVN++;
      if(ProfileNode(g_profile, bestPrice, false)) d_hitLVN++;
     }
   s_tolHit20 = false; s_tolHit30 = false; s_tolHit40 = false;
   return(true);
  }

//====================================================================
// SOURCE MODULE A — CRT dealing ranges
//====================================================================
CRT_Range  g_crtD1, g_crtH1, g_crtSession;
VP_Profile g_vpCurrent, g_vpPrior;
AMT_Levels g_amt;
datetime   g_vpCacheStamp = 0;      // VP rebuilt per new EntryTF bar, not per tick
int        g_curSessionId = -1, g_prevSessionId = -1;

int SessionIdOf(datetime t)
  {
   MqlDateTime d; TimeToStruct(t, d);
   int h = d.hour;
   if(h >= InpSessAsiaStart   && h < InpSessAsiaEnd)   return(0);   // Asia
   if(h >= InpSessLondonStart && h < InpSessLondonEnd) return(1);   // London
   if(h >= InpSessNYStart     && h < InpSessNYEnd)     return(2);   // NY
   return(3);                                                       // off-session
  }

CRT_Range BuildCRTFromBar(ENUM_TIMEFRAMES tf, int shift, string label)
  {
   CRT_Range r; r.valid = false; r.label = label;
   if(shift < 1 || shift >= Bars(_Symbol, tf)) return(r);

   r.tStart = iTime(_Symbol, tf, shift);
   r.tEnd   = iTime(_Symbol, tf, shift - 1);
   r.high   = iHigh(_Symbol, tf, shift);
   r.low    = iLow (_Symbol, tf, shift);
   r.open   = iOpen(_Symbol, tf, shift);
   r.close  = iClose(_Symbol, tf, shift);
   r.mid    = (r.high + r.low) / 2.0;
   r.direction = (r.close > r.open) ? +1 : -1;

   // sweep + reclaim, evaluated only on bars that closed AFTER the range
   r.sweptHigh = false; r.sweptLow = false;
   r.reclaimedHigh = false; r.reclaimedLow = false;
   for(int i = shift - 1; i >= 1; i--)
     {
      double h = iHigh(_Symbol, tf, i), l = iLow(_Symbol, tf, i), c = iClose(_Symbol, tf, i);
      if(h > r.high) { r.sweptHigh = true; if(c < r.high) r.reclaimedHigh = true; }
      if(l < r.low)  { r.sweptLow  = true; if(c > r.low)  r.reclaimedLow  = true; }
     }
   r.valid = true;
   return(r);
  }

// Bias vote only -- never an entry on its own, never a veto.
int CRTBiasVote()
  {
   if(!InpUseCRT) return(0);
   int vote = 0;
   if(g_crtD1.valid)
     {
      if(g_crtD1.sweptLow  && g_crtD1.reclaimedLow)  vote++;
      if(g_crtD1.sweptHigh && g_crtD1.reclaimedHigh) vote--;
      vote += (g_crtD1.direction > 0) ? 1 : -1;
     }
   if(g_crtH1.valid)
     {
      if(g_crtH1.sweptLow  && g_crtH1.reclaimedLow)  vote++;
      if(g_crtH1.sweptHigh && g_crtH1.reclaimedHigh) vote--;
     }
   if(vote > 0) return(+1);
   if(vote < 0) return(-1);
   return(0);
  }

//====================================================================
// SOURCE MODULE B — session-fixed volume profile
// Built on new EntryTF bars only and cached; never rebuilt per tick.
//====================================================================
double VPBinSize()
  {
   // pips on majors; ATR-scaled on metals where a "pip" is meaningless
   double atr = ATRv(g_atrBiasH);
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      return(MathMax(atr * 0.05, _Point * 10));
   double pip = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   return(InpVPBinPips * pip);
  }

bool BuildSessionVP(datetime sStart, datetime sEnd, VP_Profile &p)
  {
   p.valid = false;
   if(!InpUseVP) return(false);
   int b1 = iBarShift(_Symbol, InpEntryTF, sStart, false);
   int b2 = iBarShift(_Symbol, InpEntryTF, sEnd, false);
   if(b1 <= b2 || b1 < 0) return(false);

   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = b2 + 1; i <= b1; i++)
     { hi = MathMax(hi, iHigh(_Symbol, InpEntryTF, i)); lo = MathMin(lo, iLow(_Symbol, InpEntryTF, i)); }
   if(hi <= lo) return(false);

   p.binSize = VPBinSize();
   if(p.binSize <= 0) return(false);
   p.bins = (int)MathMin(InpVPBinsMax, MathMax(10, (hi - lo) / p.binSize));
   p.binSize = (hi - lo) / p.bins;
   p.priceLow = lo; p.priceHigh = hi;
   ArrayResize(p.vol, p.bins);
   ArrayInitialize(p.vol, 0.0);

   long realTot = 0;
   for(int i = b2 + 1; i <= b1; i++) realTot += (long)iRealVolume(_Symbol, InpEntryTF, i);
   bool useReal = (realTot > 0);
   p.source = useReal ? "REAL" : "TICK";

   for(int i = b2 + 1; i <= b1; i++)
     {
      double bh = iHigh(_Symbol, InpEntryTF, i), bl = iLow(_Symbol, InpEntryTF, i);
      double v  = useReal ? (double)iRealVolume(_Symbol, InpEntryTF, i)
                          : (double)iVolume(_Symbol, InpEntryTF, i);
      if(v <= 0) continue;
      int lo1 = (int)MathFloor((bl - lo) / p.binSize);
      int hi1 = (int)MathFloor((bh - lo) / p.binSize);
      lo1 = MathMax(0, MathMin(p.bins - 1, lo1));
      hi1 = MathMax(0, MathMin(p.bins - 1, hi1));
      double share = v / (hi1 - lo1 + 1);
      for(int b = lo1; b <= hi1; b++) p.vol[b] += share;
     }

   int poc = 0; double total = 0;
   for(int b = 0; b < p.bins; b++) { total += p.vol[b]; if(p.vol[b] > p.vol[poc]) poc = b; }
   if(total <= 0) return(false);
   p.poc = lo + (poc + 0.5) * p.binSize;

   double target = total * InpVPValueAreaPct / 100.0, acc = p.vol[poc];
   int up = poc, dn = poc;
   while(acc < target && (up < p.bins - 1 || dn > 0))
     {
      double vu = (up < p.bins - 1) ? p.vol[up + 1] : -1;
      double vd = (dn > 0)          ? p.vol[dn - 1] : -1;
      if(vu >= vd && vu >= 0) { up++; acc += vu; } else if(vd >= 0) { dn--; acc += vd; } else break;
     }
   p.val = lo + dn * p.binSize;
   p.vah = lo + (up + 1) * p.binSize;

   ArrayResize(p.hvn, 0); ArrayResize(p.lvn, 0);
   double pocVol = p.vol[poc];
   for(int b = 0; b < p.bins; b++)
     {
      double price = lo + (b + 0.5) * p.binSize;
      if(p.vol[b] >= pocVol * 0.70) { int n = ArraySize(p.hvn); ArrayResize(p.hvn, n+1); p.hvn[n] = price; }
      if(p.vol[b] <= pocVol * 0.20) { int n = ArraySize(p.lvn); ArrayResize(p.lvn, n+1); p.lvn[n] = price; }
     }
   p.sessionStart = sStart; p.sessionEnd = sEnd;
   p.valid = true;
   return(true);
  }

//====================================================================
// SOURCE MODULE C — AMT interaction levels
//====================================================================
void BuildAMTLevels()
  {
   g_amt.valid = false;
   if(!InpUseAMTLevels) return;
   if(g_crtSession.valid)
     {
      g_amt.priorSessionHigh = g_crtSession.high;
      g_amt.priorSessionLow  = g_crtSession.low;
      g_amt.priorSessionMid  = g_crtSession.mid;
     }
   g_amt.priorPOC  = g_vpPrior.valid ? g_vpPrior.poc : 0;
   g_amt.dailyOpen = iOpen(_Symbol, PERIOD_D1, 0);
   g_amt.valid = true;
  }

// Rebuild the source objects. Called on a new EntryTF bar only.
void RefreshSourceModules()
  {
   datetime nowBar = iTime(_Symbol, InpEntryTF, 0);
   if(nowBar == g_vpCacheStamp) return;      // cache guard: never per tick
   g_vpCacheStamp = nowBar;

   if(InpUseCRT)
     {
      g_crtD1 = BuildCRTFromBar(PERIOD_D1, 1, "D1");
      g_crtH1 = BuildCRTFromBar(InpContextTF, 1, "H1");
     }

   int sid = SessionIdOf(TimeCurrent());
   if(sid != g_curSessionId)
     { g_prevSessionId = g_curSessionId; g_curSessionId = sid; g_vpPrior = g_vpCurrent; }

   if(InpUseVP)
     {
      // current developing session window, bounded to today
      MqlDateTime d; TimeToStruct(TimeCurrent(), d);
      datetime dayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", d.year, d.mon, d.day));
      int sh = 0, eh = 24;
      if(sid == 0) { sh = InpSessAsiaStart;   eh = InpSessAsiaEnd; }
      if(sid == 1) { sh = InpSessLondonStart; eh = InpSessLondonEnd; }
      if(sid == 2) { sh = InpSessNYStart;     eh = InpSessNYEnd; }
      datetime sStart = dayStart + sh * 3600;
      datetime sEnd   = (datetime)MathMin((double)TimeCurrent(), (double)(dayStart + eh * 3600));
      if(sEnd > sStart) BuildSessionVP(sStart, sEnd, g_vpCurrent);
      // prior session box for CRT + AMT
      g_crtSession = BuildCRTFromBar(PERIOD_H1, 1, "SESSION");
     }

   BuildAMTLevels();
  }

//====================================================================
// M15 OWNS TRADE VALIDITY
// M5 decides WHEN. It may never revive a setup whose M15 premise is
// already dead. Once the protected level is decisively broken after the
// setup was created, the setup stays dead -- it cannot be resurrected by
// price wandering back.
//====================================================================
bool M15SetupStillValid(int bias, string &why)
  {
   why = "";
   if(g_setupInvalidated) { why = "ALREADY_INVALIDATED"; return(false); }
   if(g_setupProtLevel <= 0) { why = "NO_PROTECTED_LEVEL"; return(false); }

   double c1 = iClose(_Symbol, InpBiasTF, 1);   // last CLOSED M15 bar only
   if(bias > 0 && c1 < g_setupProtLevel) { why = "M15_CLOSE_BELOW_PROTECTED_LOW";  return(false); }
   if(bias < 0 && c1 > g_setupProtLevel) { why = "M15_CLOSE_ABOVE_PROTECTED_HIGH"; return(false); }
   if(bias > 0 && g_biasStruct.trend == TR_BEAR) { why = "M15_TRANSITIONED_BEARISH"; return(false); }
   if(bias < 0 && g_biasStruct.trend == TR_BULL) { why = "M15_TRANSITIONED_BULLISH"; return(false); }
   return(true);
  }

// Called on every closed M15 bar while a setup is alive.
void UpdateM15Validity()
  {
   if(g_bias == 0 || g_setupProtLevel <= 0) return;
   if(g_setupInvalidated) return;
   double c1 = iClose(_Symbol, InpBiasTF, 1);
   bool broken = (g_bias > 0) ? (c1 < g_setupProtLevel) : (c1 > g_setupProtLevel);
   if(broken)
     {
      g_setupInvalidated = true;
      g_protBrokenTime = iTime(_Symbol, InpBiasTF, 1);
     }
  }

bool PriceAtLocation()
  {
   double hi = iHigh(_Symbol, InpEntryTF, 1), lo = iLow(_Symbol, InpEntryTF, 1);
   return(hi >= g_locLo && lo <= g_locHi);
  }

// Shadow only: would a different tolerance have reached this location?
// Counted once per armed location. Never trades.
void ShadowLocationTolerance(double atr)
  {
   double hi = iHigh(_Symbol, InpEntryTF, 1), lo = iLow(_Symbol, InpEntryTF, 1);
   double t20 = 0.20 * atr, t30 = 0.30 * atr, t40 = 0.40 * atr;
   if(!s_tolHit20 && hi >= g_locPrice - t20 && lo <= g_locPrice + t20) { s_tolHit20 = true; s_locTol20++; }
   if(!s_tolHit30 && hi >= g_locPrice - t30 && lo <= g_locPrice + t30) { s_tolHit30 = true; s_locTol30++; }
   if(!s_tolHit40 && hi >= g_locPrice - t40 && lo <= g_locPrice + t40) { s_tolHit40 = true; s_locTol40++; }
  }

//====================================================================
// STATE 3 — CONFIRMATION (any ONE; core is a structure shift)
//====================================================================
string Confirmation(int bias, double atrEntry)
  {
   double o1 = iOpen(_Symbol, InpEntryTF, 1), c1 = iClose(_Symbol, InpEntryTF, 1);
   double h1 = iHigh(_Symbol, InpEntryTF, 1), l1 = iLow(_Symbol, InpEntryTF, 1);
   double o2 = iOpen(_Symbol, InpEntryTF, 2), c2 = iClose(_Symbol, InpEntryTF, 2);
   double rng = h1 - l1, body = MathAbs(c1 - o1);

   StructureView micro = ReadStructure(InpEntryTF, atrEntry);

   if(bias > 0)
     {
      if(micro.lastEvent == "CHOCH_BULL" || micro.lastEvent == "BOS_BULL") return("MICRO_" + micro.lastEvent);
      if(c1 > g_locHi && l1 <= g_locHi)                                    return("RECLAIM");
      if(c2 < o2 && c1 > o1 && o1 <= c2 && c1 >= o2)                       return("BULL_ENGULF");
      if(rng > 0 && (MathMin(o1,c1) - l1)/rng >= InpRejectionWick && c1 > o1) return("BULL_REJECTION");
      if(body >= InpDisplacementATR * atrEntry && c1 > o1)                 return("BULL_DISPLACEMENT");
     }
   else
     {
      if(micro.lastEvent == "CHOCH_BEAR" || micro.lastEvent == "BOS_BEAR") return("MICRO_" + micro.lastEvent);
      if(c1 < g_locLo && h1 >= g_locLo)                                    return("RECLAIM");
      if(c2 > o2 && c1 < o1 && o1 >= c2 && c1 <= o2)                       return("BEAR_ENGULF");
      if(rng > 0 && (h1 - MathMax(o1,c1))/rng >= InpRejectionWick && c1 < o1) return("BEAR_REJECTION");
      if(body >= InpDisplacementATR * atrEntry && c1 < o1)                 return("BEAR_DISPLACEMENT");
     }
   return("");
  }

//====================================================================
// SCORE — grades a candidate that already passed the core sequence
//====================================================================
int ScoreCandidate(int bias, string confirmName, int dxy, bool &comps[])
  {
   ArrayResize(comps, 9);
   for(int i = 0; i < 9; i++) comps[i] = false;
   int s = 0;

   if((bias > 0 && g_ctxStruct.trend == TR_BULL) || (bias < 0 && g_ctxStruct.trend == TR_BEAR))
     { s += 2; comps[0] = true; }
   if(g_biasStruct.lastEvent != "") { s += 2; f_structConf++; comps[1] = true; }
   if(g_locName == "STRUCT_SUPPORT" || g_locName == "STRUCT_RESISTANCE" ||
      g_locName == "PROTECTED_LOW"  || g_locName == "PROTECTED_HIGH" ||
      g_locName == "BROKEN_STRUCTURE") { s += 2; comps[2] = true; }
   if(g_locName == "VAL" || g_locName == "VAH" || g_locName == "POC")
     { s += 1; f_profileConf++; comps[3] = true; }
   if(InpUseProfile && g_profile.valid &&
      (ProfileNode(g_profile, g_locPrice, true) || ProfileNode(g_profile, g_locPrice, false)))
     { s += 1; comps[4] = true; }
   if(StringFind(confirmName, "DISPLACEMENT") >= 0 || StringFind(confirmName, "MICRO_") >= 0)
     { s += 1; comps[5] = true; }
   if(StringFind(confirmName, "ENGULF") >= 0 || StringFind(confirmName, "REJECTION") >= 0)
     { s += 1; comps[6] = true; }
   if(InpUseDXYContext && dxy != 0)
     {
      bool agree = InpDXYInverse ? ((bias > 0 && dxy < 0) || (bias < 0 && dxy > 0))
                                 : ((bias > 0 && dxy > 0) || (bias < 0 && dxy < 0));
      if(agree) { s += 1; f_dxyAgree++; comps[7] = true; } else f_dxyDisagree++;
     }
   if(g_balance.valid && (g_locName == "BALANCE_BOUNDARY" || g_locName == "BALANCE_MID"))
     { s += 1; comps[8] = true; }
   return(s);
  }

//====================================================================
// RISK — real contract spec, round down, never floor a sub-min lot up
//====================================================================
double RiskMoney(double entry, double stop, double vol, int dir)
  {
   double p = 0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, _Symbol, vol, entry, stop, p)) return(MathAbs(p));
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return(0);
   return(MathAbs(entry - stop) / ts * tv * vol);
  }

double RoundDownLot(double lot)
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st) * st;
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

   double v = RoundDownLot(mn * (allowed / minRisk));
   if(v < mn)
     {
      double pct = 100.0 * minRisk / eq;
      if(pct > InpMaxActualRiskPercent)
        {
         f_riskRejected++;
         if(InpDebugStats)
            PrintFormat("RISK_REJECT_MIN_LOT | requested$=%.2f | minLotRisk$=%.2f | pct=%.2f", allowed, minRisk, pct);
         return(false);
        }
      v = mn;
     }
   riskM = RiskMoney(entry, stop, v, dir);
   riskPct = 100.0 * riskM / eq;
   if(riskPct > InpMaxActualRiskPercent)
     {
      f_riskRejected++;
      if(InpDebugStats)
         PrintFormat("RISK_REJECT_GUARD | lots=%.2f | risk$=%.2f | pct=%.2f", v, riskM, riskPct);
      return(false);
     }
   lots = v;
   return(true);
  }

//====================================================================
// TARGETS — internal liquidity, external structure, auction objective
//====================================================================
void BuildTargets(int dir, double entry, double &t1, double &t2, double &t3)
  {
   t1 = 0; t2 = 0; t3 = 0;
   Swing hs[], ls[];
   int nh = CollectSwings(InpBiasTF, true,  hs, 12);
   int nl = CollectSwings(InpBiasTF, false, ls, 12);

   if(dir > 0)
     {
      for(int i = 0; i < nh; i++)
         if(hs[i].price > entry) { if(t1 == 0) t1 = hs[i].price; else if(t2 == 0 && hs[i].price > t1) { t2 = hs[i].price; break; } }
      if(InpUseProfile && g_profile.valid && g_profile.vah > entry && (t2 == 0 || g_profile.vah > t2)) t3 = g_profile.vah;
      double pdh, pdl; PrevDayHiLo(pdh, pdl);
      if(pdh > entry && (t3 == 0 || pdh > t3)) t3 = pdh;
     }
   else
     {
      for(int i = 0; i < nl; i++)
         if(ls[i].price < entry && ls[i].price > 0) { if(t1 == 0) t1 = ls[i].price; else if(t2 == 0 && ls[i].price < t1) { t2 = ls[i].price; break; } }
      if(InpUseProfile && g_profile.valid && g_profile.val < entry && (t2 == 0 || g_profile.val < t2)) t3 = g_profile.val;
      double pdh, pdl; PrevDayHiLo(pdh, pdl);
      if(pdl > 0 && pdl < entry && (t3 == 0 || pdl < t3)) t3 = pdl;
     }
   // DEFECT FIX 3: do not collapse the ladder onto one price. If real
   // structure is missing further out, project measured extensions instead
   // of pretending three targets exist at the same level.
   if(!InpFixDegenerateTargets)
     { if(t2 == 0) t2 = t1; if(t3 == 0) t3 = t2; return; }   // original behaviour

   if(t1 <= 0) return;                       // no target at all -- caller refuses the trade
   double unit = MathAbs(t1 - entry);
   if(unit <= 0) return;
   if(t2 <= 0 || MathAbs(t2 - t1) < unit * 0.25) t2 = entry + dir * unit * 2.0;
   if(t3 <= 0 || MathAbs(t3 - t2) < unit * 0.25) t3 = entry + dir * unit * 3.0;
  }

//====================================================================
// SHADOW TRACKING
//====================================================================
void ShadowCreate(int dir, int score, string locType, string confType,
                  double entry, double sl, bool &comps[], bool passedScore)
  {
   if(!InpShadowTracking) return;
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;
   int n = ArraySize(s_list);
   ArrayResize(s_list, n + 1);
   s_list[n].idx = n + 1;
   s_list[n].t = iTime(_Symbol, InpEntryTF, 0);
   s_list[n].dir = dir; s_list[n].score = score;
   s_list[n].locType = locType; s_list[n].confType = confType;
   s_list[n].entry = entry; s_list[n].sl = sl; s_list[n].risk = risk;
   s_list[n].mfeR = 0; s_list[n].maeR = 0;
   s_list[n].r05 = false; s_list[n].r1 = false; s_list[n].r15 = false;
   s_list[n].r2 = false; s_list[n].r3 = false; s_list[n].stopped = false;
   s_list[n].oneRFirst = false; s_list[n].beAfter1R = false; s_list[n].maxRAfter1R = 0;
   for(int c = 0; c < 9; c++) s_list[n].comps[c] = comps[c];
   s_list[n].passedScore = passedScore;
   s_list[n].wasEntered = false; s_list[n].maxPosBlocked = false;
   s_list[n].blockedM15 = false;
   s_list[n].active = true; s_list[n].bars = 0;
  }

void ShadowFinalize(int i)
  {
   s_list[i].active = false;
   s_finalized++;
   if(s_list[i].blockedM15)
     {
      v_shadowBlocked++;
      v_shadowBlockedMFE += s_list[i].mfeR;
      v_shadowBlockedMAE += s_list[i].maeR;
      if(s_list[i].r1) v_shadowBlocked1R++;
      if(s_list[i].stopped && !s_list[i].oneRFirst) v_shadowBlockedStopFirst++;
     }
   if(!InpDebugStats) return;
   string comps = "";
   for(int c = 0; c < 9; c++) comps += (s_list[i].comps[c] ? "1" : "0");
   PrintFormat("SHADOW | id=%d | dir=%s | score=%d | loc=%s | conf=%s | comps=%s | entered=%s | maxposblk=%s | passedScore=%s | MFE=%.3f | MAE=%.3f | r05=%d r1=%d r15=%d r2=%d r3=%d stop=%d | oneRfirst=%d | beAfter1R=%d | maxRafter1R=%.3f",
               s_list[i].idx, s_list[i].dir > 0 ? "BUY" : "SELL", s_list[i].score,
               s_list[i].locType, s_list[i].confType, comps,
               s_list[i].wasEntered ? "Y" : "N",
               s_list[i].maxPosBlocked ? "Y" : "N",
               s_list[i].passedScore ? "Y" : "N",
               s_list[i].mfeR, s_list[i].maeR,
               s_list[i].r05, s_list[i].r1, s_list[i].r15, s_list[i].r2, s_list[i].r3,
               s_list[i].stopped, s_list[i].oneRFirst, s_list[i].beAfter1R, s_list[i].maxRAfter1R);
  }

// Walk every live shadow forward one EntryTF bar. Uses the closed bar's
// high/low only -- no intrabar assumptions beyond what a real stop would
// have seen, and no future data.
void ShadowUpdate()
  {
   if(!InpShadowTracking) return;
   double hi = iHigh(_Symbol, InpEntryTF, 1), lo = iLow(_Symbol, InpEntryTF, 1);

   for(int i = 0; i < ArraySize(s_list); i++)
     {
      if(!s_list[i].active) continue;
      s_list[i].bars++;

      double favR = (s_list[i].dir > 0) ? (hi - s_list[i].entry) / s_list[i].risk
                                        : (s_list[i].entry - lo) / s_list[i].risk;
      double advR = (s_list[i].dir > 0) ? (lo - s_list[i].entry) / s_list[i].risk
                                        : (s_list[i].entry - hi) / s_list[i].risk;

      if(favR > s_list[i].mfeR) s_list[i].mfeR = favR;
      if(advR < s_list[i].maeR) s_list[i].maeR = advR;

      bool hitStopNow = (advR <= -1.0);
      bool hit1RNow   = (favR >= 1.0);

      if(!s_list[i].r05 && favR >= 0.5) s_list[i].r05 = true;
      if(!s_list[i].r1  && hit1RNow)
        {
         s_list[i].r1 = true;
         if(!s_list[i].stopped) s_list[i].oneRFirst = true;   // +1R came first
        }
      if(!s_list[i].r15 && favR >= 1.5) s_list[i].r15 = true;
      if(!s_list[i].r2  && favR >= 2.0) s_list[i].r2  = true;
      if(!s_list[i].r3  && favR >= 3.0) s_list[i].r3  = true;

      if(s_list[i].r1)
        {
         if(favR > s_list[i].maxRAfter1R) s_list[i].maxRAfter1R = favR;
         // did price hand back the whole excursion to entry?
         bool backToEntry = (s_list[i].dir > 0) ? (lo <= s_list[i].entry) : (hi >= s_list[i].entry);
         if(backToEntry) s_list[i].beAfter1R = true;
        }

      if(hitStopNow)
        {
         s_list[i].stopped = true;
         ShadowFinalize(i);
         continue;
        }
      if(s_list[i].bars >= InpShadowHorizonBars)
         ShadowFinalize(i);
     }
  }

void ShadowMarkEntered(bool blockedByMaxPos)
  {
   if(!InpShadowTracking) return;
   int n = ArraySize(s_list);
   if(n <= 0) return;
   if(blockedByMaxPos) s_list[n-1].maxPosBlocked = true;
   else                s_list[n-1].wasEntered = true;
  }

void ShadowMarkBlockedM15()
  {
   if(!InpShadowTracking) return;
   int n = ArraySize(s_list);
   if(n > 0) s_list[n-1].blockedM15 = true;
  }

//====================================================================
// STATE 4 — EXECUTE
//====================================================================
void Execute(int bias, string confirmName, int score, double atrEntry)
  {
   // ---- FINAL M15 VALIDITY GATE: M5 may never overrule a dead M15 premise ----
   string invalidWhy = "";
   if(!M15SetupStillValid(bias, invalidWhy))
     {
      v_contradictionsDetected++;
      v_blockedAtEntry++;
      ShadowMarkBlockedM15();
      if(InpDebugStats)
         PrintFormat("ENTRY_BLOCKED_STRUCTURE_CONTRADICTION | %s | reason=%s | setupCreated=%s | protectedLevel=%.2f | protectedCreated=%s | brokenAt=%s | lastM15Close=%s",
                     bias > 0 ? "BUY" : "SELL", invalidWhy,
                     TimeToString(g_setupCreatedTime, TIME_DATE|TIME_MINUTES),
                     g_setupProtLevel,
                     TimeToString(g_protLevelCreatedTime, TIME_DATE|TIME_MINUTES),
                     TimeToString(g_protBrokenTime, TIME_DATE|TIME_MINUTES),
                     TimeToString(iTime(_Symbol, InpBiasTF, 1), TIME_DATE|TIME_MINUTES));
      return;
     }

   if(!SpreadOK())                    { f_spreadBlocked++; return; }
   if(CountOwn() >= InpMaxPositions)  { x_maxPosReject++; ShadowMarkEntered(true); return; }

   double entry = (bias > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double l1 = iLow (_Symbol, InpEntryTF, 1), l2 = iLow (_Symbol, InpEntryTF, 2);
   double h1 = iHigh(_Symbol, InpEntryTF, 1), h2 = iHigh(_Symbol, InpEntryTF, 2);

   // structural invalidation: the execution swing, or the location edge
   double rawSL = (bias > 0) ? MathMin(MathMin(l1, l2), g_locLo)
                             : MathMax(MathMax(h1, h2), g_locHi);
   double sl = (bias > 0) ? rawSL - InpSLBufferATR * atrEntry
                          : rawSL + InpSLBufferATR * atrEntry;
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;

   double t1, t2, t3;
   BuildTargets(bias, entry, t1, t2, t3);
   double rr1 = (t1 > 0) ? MathAbs(t1 - entry) / risk : 0;
   double rr2 = (t2 > 0) ? MathAbs(t2 - entry) / risk : 0;
   double rr3 = (t3 > 0) ? MathAbs(t3 - entry) / risk : 0;

   // DEFECT FIX 2: refuse to risk 1R for a target nearer than 1R. The
   // furthest available target is what matters -- a near TP1 is fine as a
   // partial only if something further out justifies the trade.
   double bestRR = MathMax(rr1, MathMax(rr2, rr3));
   if(InpRequireEntryRR && bestRR < InpMinEntryRR)
     {
      g_geometryRejects++;
      g_geometryRejectRRSum += bestRR;
      if(InpDebugStats)
         PrintFormat("GEOMETRY_REJECT | %s | risk=%.2f | bestTarget=%.2f | bestRR=%.2f | minRequired=%.2f",
                     bias > 0 ? "BUY" : "SELL", risk, MathMax(t1, MathMax(t2, t3)), bestRR, InpMinEntryRR);
      return;
     }

   double lots = 0, riskM = 0, riskPct = 0;
   if(!SafeLots(entry, sl, bias, lots, riskM, riskPct)) return;

   bool ok = (bias > 0)
             ? trade.Buy (lots, _Symbol, entry, NormalizeDouble(sl, _Digits), 0, "AF|" + confirmName)
             : trade.Sell(lots, _Symbol, entry, NormalizeDouble(sl, _Digits), 0, "AF|" + confirmName);
   if(!ok) { if(InpDebugStats) Print("Order failed: ", trade.ResultRetcodeDescription()); return; }

   g_tradeNo++;
   f_entries++;
   ShadowMarkEntered(false);
   if(bias > 0) f_buys++; else f_sells++;
   r_riskSum += riskPct; r_riskN++;
   if(riskPct < r_riskMin) r_riskMin = riskPct;
   if(riskPct > r_riskMax) r_riskMax = riskPct;
   int rn = ArraySize(m_riskPcts); ArrayResize(m_riskPcts, rn + 1); m_riskPcts[rn] = riskPct;

   int n = ArraySize(g_live);
   ArrayResize(g_live, n + 1);
   g_live[n].orderTicket   = trade.ResultOrder();
   g_live[n].posIdentifier = 0;      // filled from DEAL_POSITION_ID on the fill
   g_live[n].posTicket     = 0;
   g_live[n].dealTicketIn  = 0;
   g_live[n].idResolved    = false;
   g_live[n].closed        = false;
   g_live[n].exitReason    = "";

   // --- structure snapshot at entry ---
   double protLevel = (bias > 0) ? g_biasStruct.protectedLow : g_biasStruct.protectedHigh;
   double m15Close  = iClose(_Symbol, InpBiasTF, 1);
   bool contradiction = (protLevel > 0) &&
                        ((bias > 0 && m15Close < protLevel) || (bias < 0 && m15Close > protLevel));
   g_live[n].entryTime         = TimeCurrent();
   g_live[n].entryM15Bar       = iTime(_Symbol, InpBiasTF, 1);
   g_live[n].entryStructState  = (int)g_biasStruct.trend;
   g_live[n].entryProtLow      = g_biasStruct.protectedLow;
   g_live[n].entryProtHigh     = g_biasStruct.protectedHigh;
   g_live[n].entryContradiction= contradiction;
   g_live[n].lastProcM15       = g_live[n].entryM15Bar;
   g_live[n].chochArmed        = false;
   if(contradiction) { k_entryContradiction++; v_contradictionsTraded++; }   // must stay 0 under the gate

   if(InpDebugStats)
      PrintFormat("ENTRY_STRUCTURE_SNAPSHOT | trade=%d | %s | entryM15=%s | structure=%s | protectedLow=%.2f | protectedHigh=%.2f | alreadyThroughLevel=%s",
                  g_tradeNo + 1, bias > 0 ? "BUY" : "SELL",
                  TimeToString(g_live[n].entryM15Bar, TIME_DATE|TIME_MINUTES),
                  g_biasStruct.trend == TR_BULL ? "BULL" : (g_biasStruct.trend == TR_BEAR ? "BEAR" : "NONE"),
                  g_biasStruct.protectedLow, g_biasStruct.protectedHigh,
                  contradiction ? "true" : "false");
   if(contradiction && InpDebugStats)
      PrintFormat("ENTRY_STRUCTURE_CONTRADICTION | trade=%d | %s | m15Close=%.2f | protectedLevel=%.2f",
                  g_tradeNo + 1, bias > 0 ? "BUY" : "SELL", m15Close, protLevel);

   g_live[n].dir = bias;
   g_live[n].requestedEntry   = entry;    // pre-send quote, diagnostics only
   g_live[n].entry            = entry;    // provisional; overwritten by DEAL_PRICE on fill
   g_live[n].preSendRiskMoney = riskM; g_live[n].lastKnownSL = sl; g_live[n].lastSLSeenAt = 0;
   g_live[n].fillSynced       = false;
   g_live[n].rawSL = rawSL; g_live[n].finalSL = sl;
   g_live[n].riskPrice = risk; g_live[n].riskMoney = riskM;
   g_live[n].tp1 = t1; g_live[n].tp2 = t2; g_live[n].tp3 = t3;
   g_live[n].rr1 = rr1; g_live[n].rr2 = rr2; g_live[n].rr3 = rr3;
   g_live[n].mfeR = 0; g_live[n].maeR = 0;
   g_live[n].initialVolume = lots;
   g_live[n].protectedLevel = (bias > 0) ? g_biasStruct.protectedLow : g_biasStruct.protectedHigh;
   g_live[n].tp1Reached = false; g_live[n].tp2Reached = false;
   g_live[n].tp1Status = PS_NOT_ATTEMPTED; g_live[n].tp2Status = PS_NOT_ATTEMPTED;
   g_live[n].beDone = false;
   g_live[n].idx = (int)g_tradeNo;
   g_live[n].mfeAtFirstAction = 0; g_live[n].firstActionTaken = false; g_live[n].firstActionType = "NONE";
   g_live[n].tp1Skipped = false; g_live[n].mfePeakTime = 0; g_live[n].lastUpdateTime = 0;

   if(InpLogSetups)
      PrintFormat("TRADE #%d\nDirection=%s\nBiasTF=%s\nContextStructure=%s\nBiasStructure=%s\nBiasReason=%s\nLocation=%s @ %.2f\nPOC=%.2f VAH=%.2f VAL=%.2f (%s)\nDXY=%s\nConfirmation=%s\nScore=%d\nEntry=%.2f\nStructuralSL=%.2f (raw %.2f)\nActualRiskPct=%.3f\nTP1=%.2f TP2=%.2f TP3=%.2f\nRR1=%.2f RR2=%.2f RR3=%.2f",
                  g_tradeNo, bias > 0 ? "BUY" : "SELL", EnumToString(InpBiasTF),
                  g_ctxStruct.trend == TR_BULL ? "BULL" : (g_ctxStruct.trend == TR_BEAR ? "BEAR" : "NONE"),
                  g_biasStruct.trend == TR_BULL ? "BULL" : (g_biasStruct.trend == TR_BEAR ? "BEAR" : "NONE"),
                  g_biasReason, g_locName, g_locPrice,
                  g_profile.valid ? g_profile.poc : 0, g_profile.valid ? g_profile.vah : 0,
                  g_profile.valid ? g_profile.val : 0, g_profile.valid ? g_profile.source : "NONE",
                  InpUseDXYContext ? "USED" : "OFF",
                  confirmName, score, entry, sl, rawSL, riskPct, t1, t2, t3, rr1, rr2, rr3);

   if(InpDrawVisuals)
     {
      DrawTag("entry", iTime(_Symbol, InpEntryTF, 0), entry,
              StringFormat("  #%d %s %s", g_tradeNo, bias > 0 ? "BUY" : "SELL", confirmName),
              bias > 0 ? clrLime : clrRed);
      DrawLevel("sl", sl, clrRed, STYLE_DOT);
      DrawLevel("tp1", t1, clrAqua, STYLE_DOT);
      DrawLevel("tp2", t2, clrAqua, STYLE_DASH);
      DrawLevel("tp3", t3, clrAqua, STYLE_SOLID);
     }
  }

//====================================================================
// STATE 5 — MANAGEMENT
//====================================================================
// Match strictly on the authoritative position identifier. Order ticket is
// NOT interchangeable with it -- assuming so is what corrupted the earlier
// excursion records.
int FindLiveByPosId(ulong posIdentifier)
  {
   for(int i = 0; i < ArraySize(g_live); i++)
      if(g_live[i].idResolved && g_live[i].posIdentifier == posIdentifier && !g_live[i].closed)
         return(i);
   return(-1);
  }

int FindLiveByOrder(ulong orderTicket)
  {
   for(int i = 0; i < ArraySize(g_live); i++)
      if(g_live[i].orderTicket == orderTicket) return(i);
   return(-1);
  }

// Attempt a partial close. Returns the status; never throws away the
// management plan. Volume is never increased to make a partial possible --
// risk integrity outranks hitting an exact partial percentage.
// Milestones survive a terminal restart: a position that already reached
// TP1 must not "forget" and re-arm its partial or lose its BE eligibility.
void PersistMilestone(ulong posId, string level)
  {
   if(posId == 0) return;
   GlobalVariableSet(StringFormat("AF_%I64u_%s", posId, level), (double)TimeCurrent());
  }

bool MilestonePersisted(ulong posId, string level)
  {
   if(posId == 0) return(false);
   return(GlobalVariableCheck(StringFormat("AF_%I64u_%s", posId, level)));
  }

void ClearMilestones(ulong posId)
  {
   if(posId == 0) return;
   GlobalVariableDel(StringFormat("AF_%I64u_TP1", posId));
   GlobalVariableDel(StringFormat("AF_%I64u_TP2", posId));
  }

// BUGFIX 2: size the partial from the volume that actually exists on the
// ticket NOW, never from initialVolume. After TP1 takes its slice, a
// percent-of-initial request can exceed what remains and get misclassified
// as SKIPPED_INVALID_REMAINDER while legal size is still sitting there.
// When the percent-of-current rounds to something illegal, fall back to the
// largest legal close that still leaves minLot on the ticket.
int AttemptPartial(int li, ulong ticket, double curVolIn, double pct, string level)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // re-read the live volume immediately before sizing
   double curVol = curVolIn;
   if(PositionSelectByTicket(ticket)) curVol = PositionGetDouble(POSITION_VOLUME);

   double raw       = curVol * pct / 100.0;          // sizedFrom = CURRENT
   double part      = RoundDownLot(raw);
   double remainder = NormalizeDouble(curVol - part, 2);
   double maxLegal  = RoundDownLot(curVol - minLot);
   bool   usedSmaller = false;
   bool   initialWouldSkip = false;

   // what the old initial-volume rule would have done, for the clamp log
   double oldRaw  = g_live[li].initialVolume * pct / 100.0;
   double oldPart = RoundDownLot(oldRaw);
   double oldRem  = NormalizeDouble(curVol - oldPart, 2);
   if(oldPart < minLot || oldPart >= curVol || oldRem < minLot) initialWouldSkip = true;

   bool partIllegal = (part < minLot || part >= curVol || remainder < minLot);
   if(partIllegal && maxLegal >= minLot && maxLegal < curVol)
     {
      part        = maxLegal;
      remainder   = NormalizeDouble(curVol - part, 2);
      usedSmaller = true;
      partIllegal = false;
     }

   if(InpDebugStats)
      PrintFormat("PARTIAL_REQUEST | trade=%d | level=%s | posId=%I64u | initialVolume=%.2f | currentVolume=%.2f | sizedFrom=CURRENT | pct=%.0f | rawFromCurrent=%.4f | normalizedPart=%.2f | maxLegalPart=%.2f | usedSmallerPartial=%d | expectedRemainder=%.2f | minLot=%.2f | step=%.2f",
                  g_live[li].idx, level, g_live[li].posIdentifier,
                  g_live[li].initialVolume, curVol, pct, raw, part, maxLegal,
                  usedSmaller ? 1 : 0, remainder, minLot, step);

   if(partIllegal)
     {
      // no legal partial exists on this ticket at all
      if(part < minLot && maxLegal < minLot)
        {
         if(InpDebugStats)
            PrintFormat("%s_REACHED | trade=%d | partial=SKIPPED_MIN_VOLUME | volume=%.2f | requested=%.4f -- management continues",
                        level, g_live[li].idx, curVol, raw);
         return(PS_SKIPPED_MIN_VOLUME);
        }
      if(InpDebugStats)
         PrintFormat("%s_REACHED | trade=%d | partial=SKIPPED_INVALID_REMAINDER | curVol=%.2f | part=%.2f | remainder=%.2f -- management continues",
                     level, g_live[li].idx, curVol, part, remainder);
      return(PS_SKIPPED_INVALID_REMAINDER);
     }

   if(usedSmaller && initialWouldSkip && InpDebugStats)
      PrintFormat("%s_PARTIAL_CLAMPED | initialBasedWouldSkip=1 | took=%.2f | left=%.2f",
                  level, part, remainder);

   bool ok = trade.PositionClosePartial(ticket, part);
   uint rc = trade.ResultRetcode();

   // verify against the broker rather than trusting the return value
   double actualRemaining = -1;
   if(PositionSelectByTicket(ticket)) actualRemaining = PositionGetDouble(POSITION_VOLUME);
   bool verified = (actualRemaining >= 0 && MathAbs(actualRemaining - remainder) < step * 0.5);

   if(ok && verified)
     {
      if(InpDebugStats)
         PrintFormat("PARTIAL_VERIFIED | trade=%d | level=%s | closed=%.2f | remaining=%.2f | retcode=%u",
                     g_live[li].idx, level, part, actualRemaining, rc);
      return(PS_EXECUTED);
     }

   if(InpDebugStats)
      PrintFormat("PARTIAL_FAILED | trade=%d | level=%s | sent=%s | retcode=%u (%s) | expectedRemainder=%.2f | actualRemaining=%.2f -- management continues",
                  g_live[li].idx, level, ok ? "true" : "false", rc, trade.ResultRetcodeDescription(),
                  remainder, actualRemaining);
   return(PS_FAILED_BROKER);
  }

//====================================================================
// MANAGEMENT ENGINE - one authoritative read, one coherent decision,
// one action. Written this way because five separate defects shared a
// single cause: a snapshot taken, an execution changing reality, then
// further decisions made from the stale snapshot.
//
// HARD INVARIANT: protective stops may tighten or stay. They may NEVER
// loosen. Once breakeven is achieved it becomes the worst stop the
// manager is ever allowed to use again.
//
// Strategy rules (BE threshold, trail formula, targets, partial %) are
// unchanged. This is state correctness only.
//====================================================================
void Manage()
  {
   double atrEntry = ATRv(g_atrEntryH);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // ---------- 1. AUTHORITATIVE LIVE SNAPSHOT ----------
      // AUDIT: skips iteration only, nothing selectable. Valid.
      if(!posInfo.SelectByIndex(i)) continue;
      // AUDIT: skips other symbols/EAs. Valid.
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic) continue;

      ulong  ticket   = posInfo.Ticket();
      ulong  posIdent = (ulong)posInfo.Identifier();
      int li = FindLiveByPosId(posIdent);
      // AUDIT: untracked position, nothing of ours to manage. Valid.
      if(li < 0) { k_posIdMismatch++; continue; }

      long   typ      = posInfo.PositionType();
      double liveOpen = posInfo.PriceOpen();
      double liveVol  = posInfo.Volume();
      double liveSL   = posInfo.StopLoss();
      double liveTP   = posInfo.TakeProfit();
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double px       = (typ == POSITION_TYPE_BUY) ? bid : ask;
      int    dir      = (typ == POSITION_TYPE_BUY) ? +1 : -1;
      double tol      = _Point * 2;

      g_live[li].posTicket    = ticket;
      g_live[li].lastKnownSL  = liveSL;
      g_live[li].lastSLSeenAt = TimeCurrent();

      // ---------- STATE INVARIANT AUDIT ----------
      if(g_live[li].closed)
        { k_invariantViolations++;
          PrintFormat("STATE_INVARIANT_VIOLATION | closed position managed again | trade=%d", g_live[li].idx); }
      if(g_live[li].fillSynced && MathAbs(g_live[li].entry - liveOpen) > tol)
        { k_invariantViolations++;
          PrintFormat("STATE_INVARIANT_VIOLATION | entry != POSITION_PRICE_OPEN | trade=%d | stored=%.2f | live=%.2f",
                      g_live[li].idx, g_live[li].entry, liveOpen); }
      if(!g_live[li].fillSynced)
        { k_invariantViolations++;
          PrintFormat("STATE_INVARIANT_VIOLATION | post-fill calc using requestedEntry | trade=%d", g_live[li].idx); }
      if(g_live[li].beDone && liveSL > 0)
        {
         bool beBreached = (dir > 0) ? (liveSL < g_live[li].entry - tol)
                                     : (liveSL > g_live[li].entry + tol);
         if(beBreached)
           { k_invariantViolations++;
             PrintFormat("STATE_INVARIANT_VIOLATION | live SL worse than BE | trade=%d | liveSL=%.2f | BE=%.2f",
                         g_live[li].idx, liveSL, g_live[li].entry); }
        }

      // ---------- 2. MILESTONES (market state) ----------
      // AUDIT: no risk basis means no R math is computable. Valid.
      if(g_live[li].riskPrice <= 0) continue;
      double rNow = (dir > 0) ? (px - g_live[li].entry) / g_live[li].riskPrice
                              : (g_live[li].entry - px) / g_live[li].riskPrice;
      if(rNow > g_live[li].mfeR) { g_live[li].mfeR = rNow; g_live[li].mfePeakTime = TimeCurrent(); }
      if(rNow < g_live[li].maeR) g_live[li].maeR = rNow;

      #define STAMP_FIRST_ACTION(kind) \
         if(!g_live[li].firstActionTaken) \
           { g_live[li].firstActionTaken = true; \
             g_live[li].mfeAtFirstAction = g_live[li].mfeR; \
             g_live[li].firstActionType = kind; }

      // ---------- 3. EXIT EVENTS (before any stop selection) ----------
      bool exited = false;
      if(InpExitOnOpposingCHoCH && g_live[li].protectedLevel > 0)
        {
         datetime curM15 = iTime(_Symbol, InpBiasTF, 1);
         if(!g_live[li].chochArmed && curM15 > g_live[li].entryM15Bar) g_live[li].chochArmed = true;
         if(g_live[li].chochArmed && curM15 != g_live[li].lastProcM15)
           {
            g_live[li].lastProcM15 = curM15;
            double cNow  = iClose(_Symbol, InpBiasTF, 1);
            double cPrev = iClose(_Symbol, InpBiasTF, 2);
            double lvl   = g_live[li].protectedLevel;
            bool brokenNow  = (dir > 0) ? (cNow  < lvl) : (cNow  > lvl);
            bool brokenPrev = (dir > 0) ? (cPrev < lvl) : (cPrev > lvl);
            if(brokenNow && !brokenPrev)
              {
               k_chochExits++;
               if(g_live[li].tp1Status == PS_SKIPPED_MIN_VOLUME ||
                  g_live[li].tp1Status == PS_SKIPPED_INVALID_REMAINDER) k_chochAfterSkipped++;
               int barsSince = (int)((curM15 - g_live[li].entryM15Bar) / PeriodSeconds(InpBiasTF));
               if(barsSince <= 1) k_chochWithin1++;
               if(barsSince <= 2) k_chochWithin2++;
               g_live[li].exitReason = "OPPOSING_CHOCH";
               if(InpDebugStats)
                  PrintFormat("OPPOSING_CHOCH_EXIT | trade=%d | %s | barsSinceEntry=%d | protectedLevel=%.2f | prevClose=%.2f | curClose=%.2f",
                              g_live[li].idx, dir > 0 ? "BUY" : "SELL", barsSince, lvl, cPrev, cNow);
               trade.PositionClose(ticket);
               exited = true;
              }
            else if(brokenNow && brokenPrev) k_chochSuppressedPreexisting++;
           }
        }
      // AUDIT: position is gone; nothing further applies. Valid.
      if(exited) continue;

      // ---------- 4. BUILD EVERY STOP CANDIDATE ----------
      double beCand = 0, trailCand = 0;
      bool haveBE = false, haveTrail = false;

      if(rNow >= InpBEAfterR)
        { beCand = NormalizeDouble(g_live[li].entry, _Digits); haveBE = true; }

      if(InpStructureTrail && g_live[li].beDone)
        {
         Swing sw[];
         if(dir > 0 && CollectSwings(InpEntryTF, false, sw, 3) >= 1)
           { trailCand = sw[0].price - InpSLBufferATR * atrEntry;
             if(trailCand < px) { haveTrail = true; k_trailCandidates++; } }
         if(dir < 0 && CollectSwings(InpEntryTF, true, sw, 3) >= 1)
           { trailCand = sw[0].price + InpSLBufferATR * atrEntry;
             if(trailCand > px) { haveTrail = true; k_trailCandidates++; } }
        }

      // ---------- 5. SELECT THE MOST PROTECTIVE ----------
      double desiredSL = liveSL;
      string chosen = "NONE";
      if(dir > 0)
        {
         if(haveBE    && (desiredSL == 0 || beCand    > desiredSL)) { desiredSL = beCand;    chosen = "BE"; }
         if(haveTrail && (desiredSL == 0 || trailCand > desiredSL)) { desiredSL = trailCand; chosen = "TRAIL"; }
         if(g_live[li].beDone && desiredSL < g_live[li].entry - tol)
           { desiredSL = g_live[li].entry; chosen = "BE_FLOOR"; }
        }
      else
        {
         if(haveBE    && (desiredSL == 0 || beCand    < desiredSL)) { desiredSL = beCand;    chosen = "BE"; }
         if(haveTrail && (desiredSL == 0 || trailCand < desiredSL)) { desiredSL = trailCand; chosen = "TRAIL"; }
         if(g_live[li].beDone && desiredSL > g_live[li].entry + tol)
           { desiredSL = g_live[li].entry; chosen = "BE_CEILING"; }
        }

      if(InpDebugStats && (haveBE || haveTrail))
         PrintFormat("STOP_CANDIDATES | trade=%d | %s | currentSL=%.2f | BE=%s | trail=%s | selectedSL=%.2f | reason=%s",
                     g_live[li].idx, dir > 0 ? "BUY" : "SELL", liveSL,
                     haveBE ? DoubleToString(beCand, 2) : "NONE",
                     haveTrail ? DoubleToString(trailCand, 2) : "NONE",
                     desiredSL, chosen);

      // ---------- 6. MONOTONIC GUARD, ONE MODIFY PER PASS ----------
      if(desiredSL > 0 && MathAbs(desiredSL - liveSL) > tol)
        {
         bool loosens = (liveSL > 0) &&
                        ((dir > 0 && desiredSL < liveSL - tol) || (dir < 0 && desiredSL > liveSL + tol));
         if(loosens)
           {
            k_stopLoosenBlocked++;
            PrintFormat("STOP_LOOSEN_BLOCKED | trade=%d | %s | liveSL=%.2f | requested=%.2f | source=%s",
                        g_live[li].idx, dir > 0 ? "BUY" : "SELL", liveSL, desiredSL, chosen);
           }
         else
           {
            bool sent = trade.PositionModify(ticket, NormalizeDouble(desiredSL, _Digits), liveTP);
            uint rc = trade.ResultRetcode();
            double actualSL = 0;
            if(PositionSelectByTicket(ticket)) actualSL = PositionGetDouble(POSITION_SL);
            bool verified = (MathAbs(actualSL - desiredSL) <= tol);
            if(InpDebugStats)
               PrintFormat("SL_MOD | trade=%d | source=%s | old=%.2f | requested=%.2f | actual=%.2f | verified=%d | retcode=%u | sent=%d",
                           g_live[li].idx, chosen, liveSL, desiredSL, actualSL, verified ? 1 : 0, rc, sent ? 1 : 0);
            if(verified)
              {
               g_live[li].lastKnownSL = actualSL;
               if(chosen == "BE" || chosen == "BE_FLOOR" || chosen == "BE_CEILING")
                 {
                  if(!g_live[li].beDone)
                    {
                     k_beAttempts++; k_beVerified++;
                     if(g_live[li].tp1Status == PS_SKIPPED_MIN_VOLUME ||
                        g_live[li].tp1Status == PS_SKIPPED_INVALID_REMAINDER) k_beAfterSkipped++;
                    }
                  g_live[li].beDone = true;
                  STAMP_FIRST_ACTION("BREAKEVEN");
                 }
               else if(chosen == "TRAIL")
                 {
                  k_trailAccepted++;
                  if(g_live[li].tp1Status == PS_SKIPPED_MIN_VOLUME ||
                     g_live[li].tp1Status == PS_SKIPPED_INVALID_REMAINDER) k_trailAfterSkipped++;
                  STAMP_FIRST_ACTION("STRUCTURE_TRAIL");
                 }
              }
            else
              {
               k_beFailed++;
               PrintFormat("SL_MOD_FAILED | trade=%d | requested=%.2f | actual=%.2f | retcode=%u",
                           g_live[li].idx, desiredSL, actualSL, rc);
              }
           }
        }
      else if(haveBE && !g_live[li].beDone && liveSL > 0 && MathAbs(liveSL - g_live[li].entry) <= tol)
        { g_live[li].beDone = true; STAMP_FIRST_ACTION("BREAKEVEN"); }

      // ---------- 7. PARTIAL MILESTONES (execution, after protection) ----------
      if(PositionSelectByTicket(ticket)) liveVol = PositionGetDouble(POSITION_VOLUME);
      bool tp1Usable = (g_live[li].tp1 > 0 && g_live[li].rr1 >= InpMinPartialR);

      if(!g_live[li].tp1Reached && !tp1Usable && g_live[li].tp1 > 0)
        {
         g_live[li].tp1Reached = true;
         if(InpDebugStats && !g_live[li].tp1Skipped)
           {
            g_live[li].tp1Skipped = true;
            PrintFormat("TP1_SKIPPED_TOO_NEAR | trade=%d | rr1=%.2f < %.2f",
                        g_live[li].idx, g_live[li].rr1, InpMinPartialR);
           }
        }

      if(!g_live[li].tp1Reached && tp1Usable)
        {
         bool hit = (dir > 0) ? (px >= g_live[li].tp1) : (px <= g_live[li].tp1);
         if(hit)
           {
            g_live[li].tp1Reached = true; k_tp1Reached++;
            PersistMilestone(g_live[li].posIdentifier, "TP1");
            g_live[li].tp1Status = AttemptPartial(li, ticket, liveVol, InpTP1ClosePct, "TP1");
            if(g_live[li].tp1Status == PS_EXECUTED)
              { STAMP_FIRST_ACTION("TP1_PARTIAL"); k_tp1Executed++; }
            else
              {
               STAMP_FIRST_ACTION("TP1_REACHED_" + PartialStatusName(g_live[li].tp1Status));
               if(g_live[li].tp1Status == PS_SKIPPED_MIN_VOLUME)             k_tp1SkippedMinVol++;
               else if(g_live[li].tp1Status == PS_SKIPPED_INVALID_REMAINDER) k_tp1SkippedRemainder++;
               else if(g_live[li].tp1Status == PS_FAILED_BROKER)             k_tp1Failed++;
              }
            if(PositionSelectByTicket(ticket)) liveVol = PositionGetDouble(POSITION_VOLUME);
           }
        }

      if(g_live[li].tp1Reached && !g_live[li].tp2Reached && g_live[li].tp2 > 0)
        {
         bool hit = (dir > 0) ? (px >= g_live[li].tp2) : (px <= g_live[li].tp2);
         if(hit)
           {
            g_live[li].tp2Reached = true; k_tp2Reached++;
            PersistMilestone(g_live[li].posIdentifier, "TP2");
            g_live[li].tp2Status = AttemptPartial(li, ticket, liveVol, InpTP2ClosePct, "TP2");
            if(g_live[li].tp2Status == PS_EXECUTED)
              { STAMP_FIRST_ACTION("TP2_PARTIAL"); k_tp2Executed++; }
            else
              {
               STAMP_FIRST_ACTION("TP2_REACHED_" + PartialStatusName(g_live[li].tp2Status));
               if(g_live[li].tp2Status == PS_SKIPPED_MIN_VOLUME)             k_tp2SkippedMinVol++;
               else if(g_live[li].tp2Status == PS_SKIPPED_INVALID_REMAINDER) k_tp2SkippedRemainder++;
               else if(g_live[li].tp2Status == PS_FAILED_BROKER)             k_tp2Failed++;
              }
           }
        }
     }
  }
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   ulong dealPosId  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   ulong dealOrder  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   long  dealEntry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long  dealReason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

   // --- resolve identity on the fill: order ticket -> position identifier ---
   if(dealEntry == DEAL_ENTRY_IN)
     {
      int ei = FindLiveByOrder(dealOrder);
      if(ei >= 0)
        {
         g_live[ei].posIdentifier = dealPosId;
         g_live[ei].dealTicketIn  = trans.deal;
         g_live[ei].idResolved    = true;
         if(InpDebugStats)
            PrintFormat("ID_LINK | trade=%d | ORDER_TICKET=%I64u | DEAL_TICKET=%I64u | POSITION_IDENTIFIER=%I64u",
                        g_live[ei].idx, dealOrder, trans.deal, dealPosId);

         // ---- BUG #4 FIX: the fill owns entry, not the pre-send quote ----
         double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         double dealVol   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         if(dealPrice > 0)
           {
            g_live[ei].entry      = dealPrice;                       // authoritative
            g_live[ei].fillSynced = true;
            // R distance is now fill -> actual SL, never quote -> SL
            g_live[ei].riskPrice  = MathAbs(dealPrice - g_live[ei].finalSL);
            g_live[ei].riskMoney  = RiskMoney(dealPrice, g_live[ei].finalSL, dealVol, g_live[ei].dir);

            double deltaPts = MathAbs(dealPrice - g_live[ei].requestedEntry) / _Point;
            double atrE     = ATRv(g_atrEntryH);
            double deltaATR = (atrE > 0) ? MathAbs(dealPrice - g_live[ei].requestedEntry) / atrE : 0;
            double eq       = account.Equity();
            double actualPct= (eq > 0) ? 100.0 * g_live[ei].riskMoney / eq : 0;

            int fn = ArraySize(k_fillDeltas);
            ArrayResize(k_fillDeltas, fn + 1);
            k_fillDeltas[fn] = deltaPts;
            if(deltaPts <= 1.0) k_fillExact++; else k_fillDiffer++;

            if(InpDebugStats)
               PrintFormat("ENTRY_FILL_CHECK | tradeID=%d | dir=%s | requestedEntry=%.2f | actualDealPrice=%.2f | fillDeltaPoints=%.1f | fillDeltaATR=%.3f | SL=%.2f | requestedRiskPct=%.2f | preSendEstimatedRisk$=%.2f | actualFilledRisk$=%.2f | actualFilledRiskPct=%.3f | positionIdentifier=%I64u | dealTicket=%I64u",
                           g_live[ei].idx, g_live[ei].dir > 0 ? "BUY" : "SELL",
                           g_live[ei].requestedEntry, dealPrice, deltaPts, deltaATR,
                           g_live[ei].finalSL, InpRiskPercent,
                           g_live[ei].preSendRiskMoney, g_live[ei].riskMoney, actualPct,
                           dealPosId, trans.deal);
           }
        }
      else k_posIdMismatch++;
      return;
     }

   if(dealEntry != DEAL_ENTRY_OUT) return;

   int li = FindLiveByPosId(dealPosId);
   if(li < 0) { k_posIdMismatch++; return; }

   string exitReason = g_live[li].exitReason;
   if(exitReason == "")
     {
      if(dealReason == DEAL_REASON_SL)      exitReason = "STOP_LOSS";
      else if(dealReason == DEAL_REASON_TP) exitReason = "TAKE_PROFIT";
      else if(dealReason == DEAL_REASON_EXPERT) exitReason = "MANUAL_MANAGER_CLOSE";
      else exitReason = "OTHER";
     }

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double rr = (g_live[li].riskMoney > 0) ? profit / g_live[li].riskMoney : 0;
   string reason = exitReason;

   // ---- BUG #6 FORENSICS: rebuild the whole position from MT5 deal history ----
   // Reporting only. Nothing here changes behaviour.
   if(InpDebugStats)
     {
      double exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double exitVol   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      PrintFormat("EXIT_DEAL | trade=%d | dealTicket=%I64u | posId=%I64u | DEAL_PRICE=%.2f | DEAL_VOLUME=%.2f | DEAL_PROFIT=%.2f | DEAL_COMMISSION=%.2f | DEAL_SWAP=%.2f | DEAL_FEE=%.2f | DEAL_REASON=%d | verifiedSLBeforeExit=%.2f | stopFillDeltaPoints=%.1f",
                  g_live[li].idx, trans.deal, dealPosId, exitPrice, exitVol,
                  HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                  HistoryDealGetDouble(trans.deal, DEAL_COMMISSION),
                  HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                  HistoryDealGetDouble(trans.deal, DEAL_FEE),
                  (int)dealReason,
                  g_live[li].lastKnownSL,
                  (exitPrice - g_live[li].lastKnownSL) / _Point);

      // full lifecycle: every deal sharing this position id
      if(HistorySelect(0, TimeCurrent()))
        {
         double gross = 0, comm = 0, swap = 0, fee = 0, volIn = 0, volOut = 0;
         int total = HistoryDealsTotal();
         for(int d = 0; d < total; d++)
           {
            ulong dt = HistoryDealGetTicket(d);
            if(dt == 0) continue;
            if((ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID) != dealPosId) continue;
            long de = HistoryDealGetInteger(dt, DEAL_ENTRY);
            double dp = HistoryDealGetDouble(dt, DEAL_PRICE);
            double dv = HistoryDealGetDouble(dt, DEAL_VOLUME);
            gross += HistoryDealGetDouble(dt, DEAL_PROFIT);
            comm  += HistoryDealGetDouble(dt, DEAL_COMMISSION);
            swap  += HistoryDealGetDouble(dt, DEAL_SWAP);
            fee   += HistoryDealGetDouble(dt, DEAL_FEE);
            if(de == DEAL_ENTRY_IN) volIn += dv; else volOut += dv;
            PrintFormat("  LIFECYCLE | trade=%d | deal=%I64u | entry=%s | type=%d | time=%s | price=%.2f | vol=%.2f | profit=%.2f | comm=%.2f | swap=%.2f | reason=%d",
                        g_live[li].idx, dt, de == DEAL_ENTRY_IN ? "IN" : "OUT",
                        (int)HistoryDealGetInteger(dt, DEAL_TYPE),
                        TimeToString((datetime)HistoryDealGetInteger(dt, DEAL_TIME), TIME_DATE|TIME_SECONDS),
                        dp, dv, HistoryDealGetDouble(dt, DEAL_PROFIT),
                        HistoryDealGetDouble(dt, DEAL_COMMISSION),
                        HistoryDealGetDouble(dt, DEAL_SWAP),
                        (int)HistoryDealGetInteger(dt, DEAL_REASON));
           }
         double net = gross + comm + swap + fee;
         double lifecycleR = (g_live[li].riskMoney > 0) ? net / g_live[li].riskMoney : 0;
         PrintFormat("LIFECYCLE_TOTAL | trade=%d | volIn=%.2f volOut=%.2f | gross=%.2f | comm=%.2f | swap=%.2f | fee=%.2f | NET=%.2f | InitialRiskMoney=%.2f | LifecycleR=%.3f | EAReportedR=%.3f | RDifference=%.3f | PNL_ACCOUNTING_MISMATCH=%.2f",
                     g_live[li].idx, volIn, volOut, gross, comm, swap, fee, net,
                     g_live[li].riskMoney, lifecycleR, rr, lifecycleR - rr, net - profit);
        }
     }

   // sanity: a trade cannot legitimately run several R and still take a full loss
   if(g_live[li].mfeR >= 3.0 && rr <= -0.9)
     {
      k_mfeSanity++;
      PrintFormat("MFE_SANITY_VIOLATION | trade=%d | posIdent=%I64u | orderTicket=%I64u | MFE=%.2fR | realizedR=%.2f | entryTime=%s | mfePeakTime=%s | lastUpdate=%s | entry=%.2f | SL=%.2f | risk=%.2f",
                  g_live[li].idx, g_live[li].posIdentifier, g_live[li].orderTicket,
                  g_live[li].mfeR, rr,
                  TimeToString(g_live[li].entryTime, TIME_DATE|TIME_SECONDS),
                  TimeToString(g_live[li].mfePeakTime, TIME_DATE|TIME_SECONDS),
                  TimeToString(g_live[li].lastUpdateTime, TIME_DATE|TIME_SECONDS),
                  g_live[li].entry, g_live[li].finalSL, g_live[li].riskPrice);
     }
   if(rr < -1.35)
     {
      k_realizedSanity++;
      PrintFormat("REALIZED_SANITY_VIOLATION | trade=%d | realizedR=%.2f (worse than stop distance)", g_live[li].idx, rr);
     }

   r_closed++;
   if(profit >= 0) { r_wins++; r_sumWinR += rr; r_lossStreak = 0; }
   else
     {
      r_losses++; r_sumLossR += rr;
      r_lossStreak++;
      if(r_lossStreak > r_worstLossStreak) r_worstLossStreak = r_lossStreak;
      if(g_live[li].mfeR >= 1.0) { r_lossMFE1R++; k_mfe1RthenLoss++; }
      if(g_live[li].mfeR >= 2.0) k_mfe2RthenLoss++;
      if(g_live[li].mfeR >= 3.0) k_mfe3RthenLoss++;
      if(!g_live[li].firstActionTaken) k_firstActionNone++;
      if(g_live[li].maeR <= -0.98 && (rr < -1.25 || rr > -0.75)) r_mismatch++;
     }
   // R_ENTRY_SOURCE audit: after a known fill, entry must never still be the quote
   if(!g_live[li].fillSynced ||
      (g_live[li].requestedEntry != g_live[li].entry ? false
       : (MathAbs(g_live[li].requestedEntry - g_live[li].entry) < _Point * 0.5 && !g_live[li].fillSynced)))
     {
      if(!g_live[li].fillSynced)
        {
         k_requestedQuoteUsedAfterFill++;
         PrintFormat("R_ENTRY_SOURCE_VIOLATION | trade=%d | entry never synced to DEAL_PRICE", g_live[li].idx);
        }
     }

   ClearMilestones(g_live[li].posIdentifier);
   r_sumMFE += g_live[li].mfeR;
   r_sumMAE += g_live[li].maeR;

   double mfe = g_live[li].mfeR, mae = g_live[li].maeR;
   if(mfe < 0)        m_mfeBucket[0]++;
   else if(mfe < 0.5) m_mfeBucket[1]++;
   else if(mfe < 1.0) m_mfeBucket[2]++;
   else if(mfe < 2.0) m_mfeBucket[3]++;
   else if(mfe < 3.0) m_mfeBucket[4]++;
   else               m_mfeBucket[5]++;
   if(mae >= -0.01)      m_maeBucket[0]++;
   else if(mae > -0.5)   m_maeBucket[1]++;
   else if(mae > -1.0)   m_maeBucket[2]++;
   else if(mae > -1.5)   m_maeBucket[3]++;
   else                  m_maeBucket[4]++;

   m_eqR += rr;
   if(m_eqR > m_eqPeakR) m_eqPeakR = m_eqR;
   double ddR = m_eqPeakR - m_eqR;
   if(ddR > m_maxDDR) m_maxDDR = ddR;

   if(InpDebugStats)
      PrintFormat("TRADE #%d CLOSED | realizedR=%.2f | realized$=%.2f | MFEbeforeMgmt=%.2fR | finalMFE=%.2fR | firstAction=%s | MAE=%.2fR | exitReason=%s",
                  g_live[li].idx, rr, profit,
                  g_live[li].firstActionTaken ? g_live[li].mfeAtFirstAction : 0.0,
                  g_live[li].mfeR, g_live[li].firstActionType,
                  g_live[li].maeR, reason);
  }

//====================================================================
// DAILY GUARD
//====================================================================
void DailyGuard()
  {
   datetime d = iTime(_Symbol, PERIOD_D1, 0);
   if(d != g_dayStamp)
     { g_dayStamp = d; g_dayStartEquity = account.Equity(); g_dayHalt = false; }
   if(g_dayStartEquity <= 0) return;
   double pnl = 100.0 * (account.Equity() - g_dayStartEquity) / g_dayStartEquity;
   if(pnl <= -MathAbs(InpDailyLossPercent)) g_dayHalt = true;
  }

//====================================================================
// THE STATE MACHINE
//====================================================================
void OnTick()
  {
   Manage();
   DailyGuard();
   if(g_dayHalt) { f_haltBlocked++; return; }

   double atrBias  = ATRv(g_atrBiasH);
   double atrEntry = ATRv(g_atrEntryH);
   if(atrBias <= 0 || atrEntry <= 0) return;

   //---------------- STATE 1: bias, on each BiasTF bar ----------------
   if(NewBar(InpBiasTF, g_lastBiasBar))
     {
      g_biasStruct = ReadStructure(InpBiasTF, atrBias);
      g_ctxStruct  = ReadStructure(InpContextTF, atrBias);
      g_balance    = DetectBalance(InpBiasTF, atrBias);
      if(g_balance.valid) f_balances++;
      if(InpUseProfile && BuildProfile(InpBiasTF, InpProfileBars, g_profile))
        {
         d_profilesBuilt++;
         if(g_profile.source == "REAL") d_profReal++; else d_profTick++;
        }
      if(g_biasStruct.protectedLow > 0 || g_biasStruct.protectedHigh > 0) d_protectedSet++;

      if(g_biasStruct.lastEvent == "BOS_BULL")   f_bosBull++;
      if(g_biasStruct.lastEvent == "BOS_BEAR")   f_bosBear++;
      if(g_biasStruct.lastEvent == "CHOCH_BULL") f_chochBull++;
      if(g_biasStruct.lastEvent == "CHOCH_BEAR") f_chochBear++;

      int b = 0;
      if(g_biasStruct.trend == TR_BULL) b = +1;
      else if(g_biasStruct.trend == TR_BEAR) b = -1;
      g_biasReason = (g_biasStruct.lastEvent != "") ? g_biasStruct.lastEvent : "STRUCTURE_TREND";

      f_sessions++;
      if(b > 0) f_bull++; else if(b < 0) f_bear++; else f_neutral++;

      if(b != g_bias || g_state == STATE_SCAN_BIAS)
        {
         g_bias = b;
         g_locWait = 0; g_confWait = 0; g_awaitRetest = false;
         if(b == 0) { x_noBias++; g_state = STATE_SCAN_BIAS; }
         else if(ArmLocation(b, atrBias))
           {
            f_locArmed++;
            v_setupsCreated++;
            g_setupCreatedTime      = iTime(_Symbol, InpBiasTF, 1);
            g_setupProtLevel        = (b > 0) ? g_biasStruct.protectedLow : g_biasStruct.protectedHigh;
            g_protLevelCreatedTime  = g_biasStruct.protectedTime;
            g_protBrokenTime        = 0;
            g_setupInvalidated      = false;
            g_state = STATE_WAIT_LOCATION;
            if(InpLogSetups)
               PrintFormat("STATE1 bias=%s (%s) -> STATE2 location=%s @ %.2f [%.2f-%.2f]",
                           b > 0 ? "BUY" : "SELL", g_biasReason, g_locName, g_locPrice, g_locLo, g_locHi);
            if(InpDrawVisuals && g_balance.valid)
               DrawBox("balance", g_balance.from, g_balance.hi, g_balance.to, g_balance.lo, clrDimGray);
           }
         else { x_noLocation++; g_state = STATE_SCAN_BIAS; }
        }
      else if(g_state == STATE_WAIT_LOCATION)
        {
         g_locWait++;
         if(g_locWait > InpMaxLocationWait) { f_locTimeout++; x_locTimeout++; g_state = STATE_SCAN_BIAS; }
        }

      // M15 owns validity: kill dead setups upstream, not at OrderSend
      UpdateM15Validity();
      if(g_setupInvalidated &&
         (g_state == STATE_WAIT_LOCATION || g_state == STATE_WAIT_CONFIRMATION))
        {
         if(g_state == STATE_WAIT_LOCATION) v_invalidBeforeLocation++;
         else                               v_invalidBeforeConfirm++;
         if(InpLogSetups)
            PrintFormat("SETUP_CANCELLED_M15_INVALIDATION | %s | setupCreated=%s | protectedLevel=%.2f | brokenAt=%s | state=%s",
                        g_bias > 0 ? "BUY" : "SELL",
                        TimeToString(g_setupCreatedTime, TIME_DATE|TIME_MINUTES),
                        g_setupProtLevel,
                        TimeToString(g_protBrokenTime, TIME_DATE|TIME_MINUTES),
                        g_state == STATE_WAIT_LOCATION ? "WAIT_LOCATION" : "WAIT_CONFIRMATION");
         g_state = STATE_SCAN_BIAS;
         g_bias = 0;                     // a new setup needs new M15 evidence
        }
     }

   if(!NewBar(InpEntryTF, g_lastEntryBar)) return;
   ShadowUpdate();
   if(g_bias == 0 || g_state == STATE_SCAN_BIAS) return;

   //---------------- STATE 2: has price reached the location? ----------------
   if(g_state == STATE_WAIT_LOCATION)
     {
      ShadowLocationTolerance(atrBias);
      if(PriceAtLocation())
        {
         f_locReached++;
         s_barsToLocSum += g_locWait; s_barsToLocN++;
         if(g_locWait > s_barsToLocMax) s_barsToLocMax = g_locWait;
         g_confWait = 0;
         g_state = STATE_WAIT_CONFIRMATION;
         if(InpLogSetups) PrintFormat("STATE2 reached %s -> STATE3", g_locName);
        }
      return;
     }

   //---------------- STATE 3: confirmation ----------------
   if(g_state == STATE_WAIT_CONFIRMATION)
     {
      g_confWait++;
      if(g_confWait > InpMaxConfirmWait)
        { f_confTimeout++; x_confTimeout++; x_noConfirmation++; g_state = STATE_SCAN_BIAS; return; }

      string cname = Confirmation(g_bias, atrEntry);
      if(cname == "") return;

      f_microConf++;
      s_barsToConfSum += g_confWait; s_barsToConfN++;
      if(g_confWait > s_barsToConfMax) s_barsToConfMax = g_confWait;
      if(StringFind(cname, "MICRO_CHOCH") >= 0)      t_microCHoCH++;
      else if(StringFind(cname, "MICRO_BOS") >= 0)   t_microBOS++;
      else if(cname == "RECLAIM")                    t_reclaim++;
      else if(StringFind(cname, "ENGULF") >= 0)      t_engulf++;
      else if(StringFind(cname, "REJECTION") >= 0)   t_rejection++;
      else if(StringFind(cname, "DISPLACEMENT") >= 0) t_displacement++;
      int dxy = DXYBias();
      bool comps[];
      g_score = ScoreCandidate(g_bias, cname, dxy, comps);
      if(g_score >= 0 && g_score <= 15) f_scoreHist[g_score]++;

      // Shadow EVERY confirmation -- including ones the gate will refuse --
      // using the identical entry/SL formula the live path uses.
      if(InpShadowTracking)
        {
         double sEntry = (g_bias > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double zl1 = iLow (_Symbol, InpEntryTF, 1), zl2 = iLow (_Symbol, InpEntryTF, 2);
         double zh1 = iHigh(_Symbol, InpEntryTF, 1), zh2 = iHigh(_Symbol, InpEntryTF, 2);
         double zRaw = (g_bias > 0) ? MathMin(MathMin(zl1, zl2), g_locLo)
                                    : MathMax(MathMax(zh1, zh2), g_locHi);
         double zSL  = (g_bias > 0) ? zRaw - InpSLBufferATR * atrEntry
                                    : zRaw + InpSLBufferATR * atrEntry;
         ShadowCreate(g_bias, g_score, g_locName, cname, sEntry, zSL, comps,
                      (!InpUseScoreGate || g_score >= InpMinScore));
        }

      if(InpUseScoreGate && g_score < InpMinScore)
        {
         f_scoreFail++;
         if(InpLogSetups)
            PrintFormat("STATE3 confirmed %s but score %d < %d -> rejected", cname, g_score, InpMinScore);
         g_state = STATE_SCAN_BIAS;
         return;
        }
      f_scorePass++;
      g_confName = cname;
      g_confHigh = iHigh(_Symbol, InpEntryTF, 1);
      g_confLow  = iLow (_Symbol, InpEntryTF, 1);

      if(InpEntryMode == ENTRY_CONFIRMATION_RETEST)
        { g_awaitRetest = true; g_retestWait = 0; g_state = STATE_READY_TO_ENTER; return; }

      g_state = STATE_READY_TO_ENTER;
     }

   //---------------- STATE 4: execute ----------------
   if(g_state == STATE_READY_TO_ENTER)
     {
      if(InpEntryMode == ENTRY_CONFIRMATION_RETEST && g_awaitRetest)
        {
         g_retestWait++;
         if(g_retestWait > InpRetestMaxBars) { g_state = STATE_SCAN_BIAS; return; }
         double lo = iLow(_Symbol, InpEntryTF, 1), hi = iHigh(_Symbol, InpEntryTF, 1);
         bool back = (g_bias > 0) ? (lo <= g_confLow + (g_confHigh - g_confLow) * 0.5)
                                  : (hi >= g_confHigh - (g_confHigh - g_confLow) * 0.5);
         if(!back) return;
        }
      Execute(g_bias, g_confName, g_score, atrEntry);
      g_state = STATE_SCAN_BIAS;
     }
  }
//+------------------------------------------------------------------+
