//+------------------------------------------------------------------+
//|                                       TWI_PatORB_Smart_v1.mq5    |
//|                                                                    |
//| BARE-BONES REBUILD - 2026-09-01                                    |
//| ----------------------------------                                 |
//| Simplified after real backtests (XAUUSD, EURUSD, full year, every  |
//| tick) showed the old 100-point quality/momentum score had ~zero    |
//| correlation with trade outcomes (winners and losers scored almost  |
//| identically on both symbols). This is now a textbook Opening Range |
//| Breakout, nothing more:                                            |
//|   - Opening Range = first 15-minute candle of the session.         |
//|   - BUY on a candle CLOSE above Range High (+ a small ATR buffer   |
//|     to filter pure noise breaks); SELL on a close below Range Low. |
//|   - Enter immediately on the confirmed breakout bar - no retest    |
//|     wait, no FVG, no scoring, no trend/chop/ADX filters.           |
//|   - ATR stop, move to breakeven at 1R, fixed R-multiple target.    |
//| The prior full-featured version (scoring, retest modes, chop       |
//| engine, fake-breakout cooldowns) is backed up outside the vault -  |
//| ask before assuming it's gone for good.                            |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//====================== ENUMS ======================
enum ENUM_DIRECTION    { DIR_NONE, DIR_BUY, DIR_SELL };
enum ENUM_SESSION_ID   { SESS_LONDON=0, SESS_NEWYORK=1, SESS_CUSTOM=2 };
enum ENUM_LOT_MODE     { LOT_RISK_PERCENT, LOT_FIXED, LOT_BALANCE_SCALED };

//====================== INPUTS ======================
input group "=== 01 Session ==="
input bool             UseLondon              = true;
input bool             UseNewYork             = true;
input bool             UseCustom              = false;
input int              LondonStartHourGMT     = 7;
input int              LondonStartMinGMT      = 0;
input int              NewYorkStartHourGMT    = 12;
input int              NewYorkStartMinGMT     = 0;
input int              CustomStart            = 800;   // HHMM, broker/server time
input int              CustomEnd              = 1600;  // HHMM, broker/server time - informational only

input group "=== 01b Days of Week ==="
input bool             TradeMonday            = true;
input bool             TradeTuesday           = true;
input bool             TradeWednesday         = true;
input bool             TradeThursday          = true;
input bool             TradeFriday            = true;
input bool             TradeSaturday          = false;
input bool             TradeSunday            = false;

input group "=== 02 Range / Breakout ==="
input int              InpORMinutes           = 15;
input ENUM_TIMEFRAMES  InpConfirmTF           = PERIOD_M5;
input double           InpMinBreakATR         = 0.12;   // min close-beyond-range distance, in ATR, to filter noise breaks
input int              InpATRperiod           = 14;
input double           InpMinRangeATR         = 0.30;   // basic sanity guard, not a scoring gate - reject a degenerate (near-zero) range
input double           InpMaxRangeATR         = 3.00;   // reject an absurd (news-spike) range
input double           InpMinVolumeMult       = 1.5;    // breakout bar tick_volume must be >= this x the recent average; 0 = disabled
input int              InpVolumeAvgBars       = 20;     // lookback for the tick_volume average (bars 2..N+1, excludes the breakout bar itself)

input group "=== 03 Risk ==="
input ENUM_LOT_MODE    InpLotMode             = LOT_RISK_PERCENT;
input double           InpRiskPercent         = 0.50;   // used when InpLotMode = LOT_RISK_PERCENT
input double           InpFixedLot            = 0.10;   // used when InpLotMode = LOT_FIXED
input double           InpBalancePerLot       = 2000.0; // used when InpLotMode = LOT_BALANCE_SCALED
input double           InpMaxLot              = 5.0;
input double           InpMinLot              = 0.01;
input int              InpMaxTradesPerSession = 2;
input int              InpMaxTradesPerDay     = 3;
input double           InpMaxDailyLossPercent = 2.0;
input double           InpMaxSpreadPoints     = 350;    // widen for XAUUSD
input int              InpTradeWindowMinutes  = 180;

input group "=== 03b Account / Safety ==="
input bool             InpLiveAccountConfirm  = false;  // MUST be explicitly true for the EA to place real trades on a live account
input bool             InpTradingEnabled      = true;   // master switch - pause all new entries without removing the EA
input bool             InpAlertOnTrade        = true;

input group "=== 04 Exits ==="
input double           InpSL_ATR              = 0.50;
input double           InpMinSL_ATR           = 0.35;
input double           InpMaxSL_ATR           = 1.60;
input double           InpBEAfterR            = 1.0;    // move stop to breakeven once price is this many R in favor
input double           InpBEBufferATR         = 0.10;
input double           InpTargetR             = 2.0;    // fixed take-profit in R multiples - single target, no partials, no trailing

input group "=== 05 Grid / Recovery (capped, off by default) ==="
input bool             InpUseGrid             = false;  // master switch - default OFF
input int              InpGridMaxAdds         = 2;      // hard cap on additional entries per trade
input double           InpGridSpacingATR      = 0.5;    // price must move this many ATR further adverse than the last fill
input double           InpGridMaxTotalLot     = 0.05;   // absolute ceiling on combined volume - independent circuit breaker

input group "=== 06 Dashboard ==="
input bool             InpShowDashboard       = true;
input bool             InpDrawZones           = true;

input group "=== 07 Debug ==="
input long             InpMagicNumber         = 260901;

//====================== GLOBALS ======================
CTrade trade;
string OBJ_PREFIX = "TWI_PORB_";

int h_atrConfirm;

int      g_lastDay = -1, g_lastMon = -1, g_lastYear = -1;
double   g_dayStartEquity = 0;
int      g_tradesToday = 0;
bool     g_dailyLossHit = false;
int      g_brokerGMTOffsetSec = 0;
bool     g_tradingEnabledRuntime = true;
string   BTN_PANIC = "TWI_PORB_PANIC";

const int   PANEL_X          = 10;
const int   PANEL_Y           = 46;
const int   PANEL_W           = 360;
const int   PANEL_LINE_H      = 17;
const color PANEL_BG_COLOR    = C'16,10,38';
const color PANEL_BORDER      = clrMediumPurple;
const color PANEL_TITLE       = clrDeepSkyBlue;
const color PANEL_SECTION     = clrMediumPurple;
const color PANEL_LABEL       = clrSilver;
const color PANEL_VALUE       = clrWhite;
const color PANEL_GOOD        = clrLimeGreen;
const color PANEL_BAD         = clrTomato;
const color PANEL_WARN        = clrGold;
int         g_panelLineCount  = 0;

struct SessionState
  {
   bool           enabled;
   string         name;
   bool           customMode;
   int            startHour, startMin;

   datetime       rangeStart;
   bool           rangeFormed;
   bool           rangeRejected;
   double         rangeHigh, rangeLow;
   double         rangeSize;
   datetime       tradeWindowEnd;

   ENUM_DIRECTION lockedDirection;   // once a trade fires this session, the opposite direction is blocked for the rest of the session
   int            tradesThisSession;

   datetime       lastBarTime;
   string         lastDecision;
  };
SessionState S[3];

struct ActiveTrade
  {
   ulong          ticket;
   ENUM_DIRECTION dir;
   double         entryPrice;
   double         initialSL;
   double         rDistance;
   bool           beDone;
  };
ActiveTrade g_active;

int    g_gridAddsUsed          = 0;
double g_gridBaseLot           = 0;
double g_gridOriginalRiskMoney = 0;
double g_lastGridEntryPrice    = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(20);

   h_atrConfirm = iATR(_Symbol, InpConfirmTF, InpATRperiod);
   if(h_atrConfirm==INVALID_HANDLE)
     {
      Print("TWI PAT ORB SMART: indicator handle creation failed");
      return(INIT_FAILED);
     }

   S[SESS_LONDON].name  = "LONDON ORB";
   S[SESS_LONDON].customMode = false;
   S[SESS_LONDON].startHour = LondonStartHourGMT;
   S[SESS_LONDON].startMin  = LondonStartMinGMT;

   S[SESS_NEWYORK].name = "NEW YORK ORB";
   S[SESS_NEWYORK].customMode = false;
   S[SESS_NEWYORK].startHour = NewYorkStartHourGMT;
   S[SESS_NEWYORK].startMin  = NewYorkStartMinGMT;

   S[SESS_CUSTOM].name  = "CUSTOM ORB";
   S[SESS_CUSTOM].customMode = true;
   S[SESS_CUSTOM].startHour = CustomStart/100;
   S[SESS_CUSTOM].startMin  = CustomStart%100;

   S[SESS_LONDON].enabled  = UseLondon;
   S[SESS_NEWYORK].enabled = UseNewYork;
   S[SESS_CUSTOM].enabled  = UseCustom;

   RefreshBrokerGMTOffset();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingEnabledRuntime = InpTradingEnabled;

   for(int i=0;i<3;i++)
      ResetSession(i);

   FindOurPosition();
   CreatePanicButton();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(h_atrConfirm);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
void RefreshBrokerGMTOffset()
  {
   g_brokerGMTOffsetSec = (int)(TimeTradeServer() - TimeGMT());
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CheckDailyReset();

   ManageOpenPositions();
   CheckGridAdd();

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayLossPct = (g_dayStartEquity>0) ? (g_dayStartEquity-eq)/g_dayStartEquity*100.0 : 0;
   if(dayLossPct >= InpMaxDailyLossPercent)
      g_dailyLossHit = true;

   bool tradingHalted = g_dailyLossHit || !g_tradingEnabledRuntime;

   for(int i=0;i<3;i++)
     {
      if(!S[i].enabled)
         continue;

      CheckSessionDailyReset(i);

      if(!DayAllowed(TimeCurrent()))
        {
         S[i].lastDecision = "No new trades - day of week disabled";
         continue;
        }

      if(!S[i].rangeFormed && !S[i].rangeRejected)
         TryBuildOpeningRange(i);

      if(!S[i].rangeFormed)
         continue;

      if(IsNewBar(InpConfirmTF, S[i].lastBarTime))
        {
         if(!tradingHalted && g_tradesToday<InpMaxTradesPerDay)
            EvaluateBreakoutAndEnter(i);
        }
     }

   if(InpShowDashboard)
      UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Days of week                                                      |
//+------------------------------------------------------------------+
bool DayAllowed(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   switch(dt.day_of_week)
     {
      case 0: return(TradeSunday);
      case 1: return(TradeMonday);
      case 2: return(TradeTuesday);
      case 3: return(TradeWednesday);
      case 4: return(TradeThursday);
      case 5: return(TradeFriday);
      case 6: return(TradeSaturday);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Daily / session resets                                            |
//+------------------------------------------------------------------+
void CheckDailyReset()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day==g_lastDay && dt.mon==g_lastMon && dt.year==g_lastYear)
      return;
   g_lastDay=dt.day; g_lastMon=dt.mon; g_lastYear=dt.year;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday = 0;
   g_dailyLossHit = false;
   RefreshBrokerGMTOffset();
  }

void ResetSession(int i)
  {
   S[i].rangeFormed=false; S[i].rangeRejected=false;
   S[i].rangeHigh=0; S[i].rangeLow=0; S[i].rangeSize=0;
   S[i].tradeWindowEnd=0;
   S[i].lockedDirection=DIR_NONE;
   S[i].tradesThisSession=0;
   S[i].lastDecision="Waiting for opening range";
   ObjectsDeleteAll(0, OBJ_PREFIX+S[i].name);
  }

void CheckSessionDailyReset(int i)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayMidnight = TimeCurrent() - (dt.hour*3600 + dt.min*60 + dt.sec);
   if(S[i].rangeFormed || S[i].rangeRejected)
     {
      if(S[i].rangeStart < todayMidnight)
         ResetSession(i);
     }
  }

//+------------------------------------------------------------------+
//| Session start time (broker/server time), GMT presets converted    |
//+------------------------------------------------------------------+
datetime GetSessionStart(int i)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = S[i].startHour;
   int min  = S[i].startMin;
   if(!S[i].customMode)
     {
      int totalMin = hour*60 + min + g_brokerGMTOffsetSec/60;
      totalMin = ((totalMin % 1440) + 1440) % 1440;
      hour = totalMin/60;
      min  = totalMin%60;
     }
   dt.hour=hour; dt.min=min; dt.sec=0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| 1. Opening Range - built from M1 bars, session-time based         |
//+------------------------------------------------------------------+
void TryBuildOpeningRange(int i)
  {
   datetime rangeStart = GetSessionStart(i);
   datetime rangeEnd   = rangeStart + InpORMinutes*60;

   if(TimeCurrent() < rangeStart)
     {
      S[i].lastDecision = S[i].name+" - waiting for session start";
      if(InpDrawZones) DrawFormingBox(i, rangeStart);
      return;
     }
   if(TimeCurrent() < rangeEnd)
     {
      S[i].lastDecision = S[i].name+" - opening range forming, no trades";
      if(InpDrawZones) DrawFormingBox(i, rangeStart);
      return;
     }

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, rangeStart, rangeEnd-60, rates);
   if(copied <= 0)
      return;

   double hi=-DBL_MAX, lo=DBL_MAX;
   for(int k=0;k<copied;k++)
     {
      if(rates[k].high>hi) hi=rates[k].high;
      if(rates[k].low<lo)  lo=rates[k].low;
     }

   S[i].rangeStart = rangeStart;
   S[i].rangeHigh = hi; S[i].rangeLow = lo;
   S[i].rangeSize = hi-lo;
   S[i].tradeWindowEnd = rangeEnd + InpTradeWindowMinutes*60;

   double atrRange = GetBuf(1);
   double ratio = (atrRange>0) ? S[i].rangeSize/atrRange : 0;
   if(ratio < InpMinRangeATR || ratio > InpMaxRangeATR)
     {
      S[i].rangeRejected = true;
      S[i].lastDecision = StringFormat("%s RANGE REJECTED - size %.2f ATR", S[i].name, ratio);
      if(InpDrawZones) DrawRangeBox(i, clrOrange);
      return;
     }

   S[i].rangeFormed = true;
   S[i].lastDecision = S[i].name+" range set - waiting for breakout";
   if(InpDrawZones) DrawRangeBox(i, clrTeal);
  }

//+------------------------------------------------------------------+
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

double GetBuf(int shift)
  {
   double b[];
   if(CopyBuffer(h_atrConfirm, 0, shift, 1, b) <= 0)
      return(0);
   return(b[0]);
  }

//+------------------------------------------------------------------+
//| 2. Breakout confirmation + immediate entry - no retest wait        |
//+------------------------------------------------------------------+
double AvgVolumeExcludingBar1()
  {
   long   sum = 0;
   int    n = InpVolumeAvgBars;
   for(int b=2; b<=n+1; b++)
      sum += iVolume(_Symbol, InpConfirmTF, b);
   return( n>0 ? (double)sum/n : 0.0 );
  }

void EvaluateBreakoutAndEnter(int i)
  {
   if(TimeCurrent() > S[i].tradeWindowEnd)
     {
      S[i].lastDecision = S[i].name+" trade window closed, managing only";
      return;
     }
   if(S[i].tradesThisSession >= InpMaxTradesPerSession)
      return;

   double atr = GetBuf(1);
   if(atr<=0) return;
   double breakDist = atr*InpMinBreakATR;
   double c1 = iClose(_Symbol, InpConfirmTF, 1);

   ENUM_DIRECTION dir = DIR_NONE;
   if(c1 > S[i].rangeHigh + breakDist) dir = DIR_BUY;
   else if(c1 < S[i].rangeLow - breakDist) dir = DIR_SELL;
   if(dir==DIR_NONE) return;

   if(InpMinVolumeMult > 0)
     {
      long   barVol  = iVolume(_Symbol, InpConfirmTF, 1);
      double avgVol  = AvgVolumeExcludingBar1();
      if(avgVol > 0 && barVol < InpMinVolumeMult*avgVol)
        {
         S[i].lastDecision = StringFormat("%s BLOCKED | Volume %.0f below %.1fx average (%.0f)",
                               dir==DIR_BUY?"BUY":"SELL", (double)barVol, InpMinVolumeMult, avgVol);
         return;
        }
     }

   if(S[i].lockedDirection!=DIR_NONE && dir!=S[i].lockedDirection)
     {
      S[i].lastDecision = StringFormat("%s BLOCKED | session already locked %s", dir==DIR_BUY?"BUY":"SELL",
                            S[i].lockedDirection==DIR_BUY?"BUY":"SELL");
      return;
     }

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
     {
      S[i].lastDecision = StringFormat("%s BLOCKED | Spread %.0f too wide", dir==DIR_BUY?"BUY":"SELL", spread);
      return;
     }

   OpenTrade(i, dir, atr);
  }

//+------------------------------------------------------------------+
//| 13. Risk, lot sizing, stop loss                                   |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step<=0) return(vol);
   return(MathMax(0.0, MathFloor(vol/step)*step));
  }

double CalcRiskMoney(double lots, double slDistPrice)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0) return(0);
   return( lots * (slDistPrice/tickSize) * tickValue );
  }

double CalcLotSize(double slDistPrice)
  {
   double brokerMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lo = MathMax(brokerMin, InpMinLot);
   double hi = MathMin(brokerMax, InpMaxLot);

   if(InpLotMode==LOT_FIXED)
      return( MathMax(lo, MathMin(hi, NormalizeVolume(InpFixedLot))) );

   if(InpLotMode==LOT_BALANCE_SCALED)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double scaled = (InpBalancePerLot>0) ? bal/InpBalancePerLot : lo;
      return( MathMax(lo, MathMin(hi, NormalizeVolume(scaled))) );
     }

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slDistPrice<=0 || tickValue<=0 || tickSize<=0) return(MathMax(brokerMin, InpMinLot));

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity*InpRiskPercent/100.0;
   double valuePerLot = (slDistPrice/tickSize)*tickValue;
   if(valuePerLot<=0) return(MathMax(brokerMin, InpMinLot));

   double lots = NormalizeVolume(riskMoney/valuePerLot);
   return(MathMax(lo, MathMin(hi, lots)));
  }

double ComputeStopLoss(ENUM_DIRECTION dir, double atr)
  {
   double dist = InpSL_ATR*atr;
   dist = MathMax(InpMinSL_ATR*atr, MathMin(InpMaxSL_ATR*atr, dist));
   double price = SymbolInfoDouble(_Symbol, dir==DIR_BUY?SYMBOL_ASK:SYMBOL_BID);
   return( dir==DIR_BUY ? price-dist : price+dist );
  }

//+------------------------------------------------------------------+
void OpenTrade(int i, ENUM_DIRECTION dir, double atr)
  {
   bool isLive = (AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL);
   if(isLive && !InpLiveAccountConfirm && !MQLInfoInteger(MQL_TESTER))
     {
      S[i].lastDecision = "BLOCKED | Live account - set InpLiveAccountConfirm=true to allow real trades";
      Print("LIVE ACCOUNT TRADE BLOCKED - this is a real account and InpLiveAccountConfirm is false.");
      return;
     }

   double sl = ComputeStopLoss(dir, atr);
   double price = SymbolInfoDouble(_Symbol, dir==DIR_BUY?SYMBOL_ASK:SYMBOL_BID);
   double slDist = MathAbs(price-sl);
   if(slDist<=0) return;

   double lots = CalcLotSize(slDist);
   double tp = (dir==DIR_BUY) ? price+slDist*InpTargetR : price-slDist*InpTargetR;
   string cmt = StringFormat("TWI-PORB-Simple %s", S[i].name);

   bool ok;
   for(int attempt=0; attempt<2; attempt++)
     {
      price = SymbolInfoDouble(_Symbol, dir==DIR_BUY?SYMBOL_ASK:SYMBOL_BID);
      if(dir==DIR_BUY) ok = trade.Buy(lots,_Symbol,price,sl,tp,cmt);
      else             ok = trade.Sell(lots,_Symbol,price,sl,tp,cmt);
      if(ok) break;
      uint code = trade.ResultRetcode();
      if(code!=TRADE_RETCODE_REQUOTE && code!=TRADE_RETCODE_PRICE_CHANGED) break;
     }

   if(ok)
     {
      S[i].tradesThisSession++;
      g_tradesToday++;
      S[i].lockedDirection = dir;
      S[i].lastDecision = StringFormat("%s FILLED @ %.5f", dir==DIR_BUY?"BUY":"SELL", price);
      PrintFormat("%s | %s | %s | %s FILLED | %.2f lots @ %.5f | SL %.5f | TP %.5f",
         TimeToString(TimeCurrent()), _Symbol, S[i].name, dir==DIR_BUY?"BUY":"SELL", lots, price, sl, tp);

      bool wasFlat = (g_active.ticket==0);
      FindOurPosition();
      if(wasFlat)
        {
         g_gridAddsUsed = 0;
         g_gridBaseLot = lots;
         g_gridOriginalRiskMoney = slDist>0 ? CalcRiskMoney(lots, slDist) : 0;
         g_lastGridEntryPrice = price;
        }
      if(InpDrawZones) DrawTradeMarker(i, dir, price);
      if(InpAlertOnTrade)
         Alert(StringFormat("%s %s FILLED | %s | %.2f lots @ %.5f", _Symbol, dir==DIR_BUY?"BUY":"SELL", S[i].name, lots, price));
     }
   else
     {
      S[i].lastDecision = "ORDER FAILED: " + trade.ResultRetcodeDescription();
     }
  }

//+------------------------------------------------------------------+
//| Position management - just breakeven-at-1R. TP is a fixed broker- |
//| side order set at open; SL only moves once, to breakeven.         |
//+------------------------------------------------------------------+
bool FindOurPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      if(g_active.ticket!=ticket)
        {
         g_active.ticket=ticket;
         g_active.dir = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?DIR_BUY:DIR_SELL;
         g_active.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         g_active.initialSL  = PositionGetDouble(POSITION_SL);
         g_active.rDistance  = MathAbs(g_active.entryPrice-g_active.initialSL);
         g_active.beDone=false;
        }
      return(true);
     }
   if(g_active.ticket!=0)
     {
      g_gridAddsUsed=0; g_gridBaseLot=0; g_gridOriginalRiskMoney=0; g_lastGridEntryPrice=0;
     }
   g_active.ticket=0;
   return(false);
  }

void ManageOpenPositions()
  {
   if(!FindOurPosition()) return;
   if(g_active.beDone) return;
   if(g_active.rDistance<=0) return;

   double curPrice = SymbolInfoDouble(_Symbol, (g_active.dir==DIR_BUY)?SYMBOL_BID:SYMBOL_ASK);
   double progress = (g_active.dir==DIR_BUY) ? (curPrice-g_active.entryPrice) : (g_active.entryPrice-curPrice);
   double rMultiple = progress/g_active.rDistance;
   if(rMultiple < InpBEAfterR) return;

   double atr = GetBuf(1);
   double newSL = (g_active.dir==DIR_BUY) ? g_active.entryPrice+atr*InpBEBufferATR
                                            : g_active.entryPrice-atr*InpBEBufferATR;
   double curSL = PositionGetDouble(POSITION_SL);
   bool improve = (g_active.dir==DIR_BUY) ? (newSL>curSL) : (newSL<curSL || curSL==0);
   if(improve)
     {
      if(trade.PositionModify(g_active.ticket, newSL, PositionGetDouble(POSITION_TP)))
         g_active.beDone=true;
     }
  }

//+------------------------------------------------------------------+
//| Grid / recovery - capped, flat-lot adds with a hard total-risk    |
//| ceiling. Off by default (InpUseGrid=false). Total $ risk across   |
//| the whole group is pinned to the ORIGINAL entry's risk - the      |
//| stop tightens (in price terms) as volume grows, never widens.     |
//+------------------------------------------------------------------+
void CheckGridAdd()
  {
   if(!InpUseGrid) return;
   if(g_active.ticket==0) return;
   if(g_gridAddsUsed >= InpGridMaxAdds) return;
   if(g_gridBaseLot<=0 || g_gridOriginalRiskMoney<=0) return;

   double atr = GetBuf(1);
   if(atr<=0) return;

   double curPrice = SymbolInfoDouble(_Symbol, (g_active.dir==DIR_BUY)?SYMBOL_BID:SYMBOL_ASK);
   double adverse = (g_active.dir==DIR_BUY) ? (g_lastGridEntryPrice-curPrice) : (curPrice-g_lastGridEntryPrice);
   if(adverse < atr*InpGridSpacingATR) return;

   double posVol = PositionGetDouble(POSITION_VOLUME);
   if(posVol + g_gridBaseLot > InpGridMaxTotalLot) return;

   double price = SymbolInfoDouble(_Symbol, (g_active.dir==DIR_BUY)?SYMBOL_ASK:SYMBOL_BID);
   bool ok = (g_active.dir==DIR_BUY) ? trade.Buy(g_gridBaseLot,_Symbol,price)
                                       : trade.Sell(g_gridBaseLot,_Symbol,price);
   if(!ok)
     {
      PrintFormat("GRID ADD FAILED: %s", trade.ResultRetcodeDescription());
      return;
     }

   g_gridAddsUsed++;
   g_lastGridEntryPrice = price;
   FindOurPosition();
   RecalcGridStopLoss();

   PrintFormat("GRID ADD #%d | %s | %.2f lots @ %.5f | total vol now %.2f",
      g_gridAddsUsed, g_active.dir==DIR_BUY?"BUY":"SELL", g_gridBaseLot, price, PositionGetDouble(POSITION_VOLUME));
   if(InpAlertOnTrade)
      Alert(StringFormat("%s GRID ADD #%d | %.2f lots @ %.5f", _Symbol, g_gridAddsUsed, g_gridBaseLot, price));
  }

void RecalcGridStopLoss()
  {
   double totalVol = PositionGetDouble(POSITION_VOLUME);
   double avgPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0 || totalVol<=0) return;

   double valuePerPriceUnitTotal = (totalVol/tickSize)*tickValue;
   if(valuePerPriceUnitTotal<=0) return;
   double slDistPrice = g_gridOriginalRiskMoney / valuePerPriceUnitTotal;

   double newSL = (g_active.dir==DIR_BUY) ? avgPrice - slDistPrice : avgPrice + slDistPrice;
   double curTP = PositionGetDouble(POSITION_TP);
   if(trade.PositionModify(g_active.ticket, newSL, curTP))
     {
      g_active.initialSL = newSL;
      g_active.rDistance  = slDistPrice;
     }
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      FindOurPosition();
  }

//+------------------------------------------------------------------+
//| Panic button                                                      |
//+------------------------------------------------------------------+
void CreatePanicButton()
  {
   if(!InpShowDashboard)
      return;
   if(ObjectFind(0,BTN_PANIC)<0)
      ObjectCreate(0,BTN_PANIC,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_YDISTANCE,10);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_XSIZE,140);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_YSIZE,26);
   ObjectSetString(0,BTN_PANIC,OBJPROP_TEXT,"PANIC: CLOSE + STOP");
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_BGCOLOR,clrFireBrick);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,BTN_PANIC,OBJPROP_HIDDEN,true);
  }

void CloseAllEAPositions(string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      trade.PositionClose(ticket);
     }
   PrintFormat("%s | %s | ALL POSITIONS CLOSED | %s", TimeToString(TimeCurrent()), _Symbol, reason);
   if(InpAlertOnTrade)
      Alert(_Symbol+" TWI PAT ORB SMART: "+reason);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==BTN_PANIC)
     {
      CloseAllEAPositions("PANIC button pressed");
      g_tradingEnabledRuntime = false;
      ObjectSetInteger(0,BTN_PANIC,OBJPROP_STATE,false);
     }
  }

//+------------------------------------------------------------------+
//| Dashboard + chart drawing                                         |
//+------------------------------------------------------------------+
void DrawFormingBox(int i, datetime start)
  {
   string name = OBJ_PREFIX+S[i].name+"_forming";
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,start,SymbolInfoDouble(_Symbol,SYMBOL_ASK),TimeCurrent(),SymbolInfoDouble(_Symbol,SYMBOL_BID));
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrGray);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectMove(0,name,1,TimeCurrent(),ObjectGetDouble(0,name,OBJPROP_PRICE,1));
  }

void DrawRangeBox(int i, color c)
  {
   string prefix = OBJ_PREFIX+S[i].name;
   ObjectDelete(0, prefix+"_forming");

   string box = prefix+"_box";
   if(ObjectFind(0,box)<0)
      ObjectCreate(0,box,OBJ_RECTANGLE,0,S[i].rangeStart,S[i].rangeHigh,S[i].rangeStart+InpTradeWindowMinutes*60,S[i].rangeLow);
   ObjectSetInteger(0,box,OBJPROP_TIME,0,S[i].rangeStart);
   ObjectSetDouble(0,box,OBJPROP_PRICE,0,S[i].rangeHigh);
   ObjectSetInteger(0,box,OBJPROP_TIME,1,S[i].rangeStart+InpTradeWindowMinutes*60);
   ObjectSetDouble(0,box,OBJPROP_PRICE,1,S[i].rangeLow);
   ObjectSetInteger(0,box,OBJPROP_COLOR,c);
   ObjectSetInteger(0,box,OBJPROP_FILL,true);
   ObjectSetInteger(0,box,OBJPROP_BACK,true);

   DrawHLine(prefix+"_ORH", S[i].rangeHigh, c, "ORH "+S[i].name);
   DrawHLine(prefix+"_ORL", S[i].rangeLow,  c, "ORL "+S[i].name);
  }

void DrawHLine(string name, double price, color c, string text)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void DrawTradeMarker(int i, ENUM_DIRECTION dir, double price)
  {
   string name = OBJ_PREFIX+S[i].name+"_trade_"+TimeToString(TimeCurrent(),TIME_SECONDS);
   int arrowCode = (dir==DIR_BUY) ? 233 : 234;
   ObjectCreate(0,name,OBJ_ARROW,0,TimeCurrent(),price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,arrowCode);
   ObjectSetInteger(0,name,OBJPROP_COLOR, dir==DIR_BUY?clrLime:clrRed);
  }

void PanelReset() { g_panelLineCount = 0; }

void PanelLine(string text, color clr, int fontSize=9, bool bold=false)
  {
   string name = OBJ_PREFIX+"PANEL_L"+IntegerToString(g_panelLineCount);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PANEL_X+12);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PANEL_Y+10+g_panelLineCount*PANEL_LINE_H);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetString(0,name,OBJPROP_FONT, bold?"Consolas Bold":"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   g_panelLineCount++;
  }

void PanelBlank() { PanelLine("", PANEL_VALUE, 4); }

color StatusColor(string s)
  {
   if(StringFind(s,"FILLED")>=0) return(PANEL_GOOD);
   if(StringFind(s,"BLOCKED")>=0 || StringFind(s,"FAILED")>=0 || StringFind(s,"REJECTED")>=0) return(PANEL_BAD);
   if(StringFind(s,"waiting")>=0 || StringFind(s,"forming")>=0) return(PANEL_WARN);
   return(PANEL_LABEL);
  }

void PanelFinish()
  {
   int totalH = 16 + g_panelLineCount*PANEL_LINE_H;
   string bg = OBJ_PREFIX+"PANEL_BG";
   if(ObjectFind(0,bg)<0)
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,PANEL_X);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,PANEL_Y);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,PANEL_W);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,totalH);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,PANEL_BG_COLOR);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,PANEL_BORDER);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   for(int k=g_panelLineCount; k<60; k++)
     {
      string nm = OBJ_PREFIX+"PANEL_L"+IntegerToString(k);
      if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm);
      else break;
     }
  }

void UpdateDashboard()
  {
   PanelReset();
   PanelLine("TWI PAT ORB SMART (bare-bones)", PANEL_TITLE, 11, true);

   bool isLive = (AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL);
   string acctTxt = isLive ? (InpLiveAccountConfirm ? "LIVE (confirmed)" : "LIVE - BLOCKED, confirm required") : "DEMO / TESTER";
   color acctColor = isLive ? (InpLiveAccountConfirm ? PANEL_WARN : PANEL_BAD) : PANEL_LABEL;
   PanelLine("Account: "+acctTxt, acctColor);

   string haltTxt = "";
   if(!g_tradingEnabledRuntime) haltTxt += "PAUSED (switch/panic) ";
   if(g_dailyLossHit)   haltTxt += "DAILY LOSS LIMIT ";
   bool halted = (haltTxt!="");
   PanelLine(halted ? "STATUS: "+haltTxt : "STATUS: Active", halted?PANEL_BAD:PANEL_GOOD, 9, true);
   PanelBlank();

   for(int i=0;i<3;i++)
     {
      if(!S[i].enabled) continue;
      double atrR = GetBuf(1);
      double ratio = (atrR>0) ? S[i].rangeSize/atrR : 0;
      string dirTxt = (S[i].lockedDirection==DIR_BUY)?"BUY-LOCKED":(S[i].lockedDirection==DIR_SELL)?"SELL-LOCKED":"OPEN";

      PanelLine(S[i].name, PANEL_SECTION, 10, true);
      PanelLine(StringFormat("  Range High %s  |  Low %s  (%.2f ATR)",
                  DoubleToString(S[i].rangeHigh,_Digits), DoubleToString(S[i].rangeLow,_Digits), ratio), PANEL_VALUE);
      PanelLine(StringFormat("  Direction: %s  |  Trades: %d/%d this session, %d/%d today",
                  dirTxt, S[i].tradesThisSession, InpMaxTradesPerSession, g_tradesToday, InpMaxTradesPerDay), PANEL_LABEL);
      PanelLine("  "+S[i].lastDecision, StatusColor(S[i].lastDecision), 9, true);
      PanelBlank();
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPL = eq - g_dayStartEquity;
   double dayPLpct = (g_dayStartEquity>0) ? dayPL/g_dayStartEquity*100.0 : 0;
   PanelLine(StringFormat("Daily P/L: %.2f  (%.2f%%)", dayPL, dayPLpct), (dayPL>=0)?PANEL_GOOD:PANEL_BAD, 10, true);
   PanelLine(StringFormat("Spread: %.0f  |  Lot Mode: %s",
               (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD),
               InpLotMode==LOT_FIXED?"Fixed":InpLotMode==LOT_BALANCE_SCALED?"Balance-Scaled":"Risk %"),
               PANEL_LABEL);

   PanelFinish();
  }
