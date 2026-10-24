//+------------------------------------------------------------------+
//| TWI_LiquidityReversal_EA.mq5                                      |
//| Research EA for TWI_LiquidityReversal custom indicator.          |
//| No grid, martingale, averaging, or unprotected entries.          |
//+------------------------------------------------------------------+
#property copyright "TWI - Research Prototype"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// These MUST match the indicator inputs, in exactly the same order.
input int    PivotDepth       = 3;
input int    ATRPeriod        = 14;
input double DisplacementATR  = 1.20;
input double ZoneATR          = 0.55;
input int    ConfirmationBars = 4;
input int    MaxReferenceBars = 100;
input double StopBufferATR    = 0.12;
input double ArrowOffsetATR   = 0.20;

input double RiskPercent       = 0.50;   // Percentage of equity at SL
input double RewardToRisk      = 2.0;    // Fixed initial TP in R
input int    MaxSpreadPoints   = 65;     // Broker points, NOT dollars
input int    MaxTradesPerDay   = 2;
input int    SlippagePoints    = 25;
input bool   AllowBuy          = true;
input bool   AllowSell         = true;
input bool   UseServerTime     = false;
input int    StartHourServer   = 0;      // Inclusive
input int    EndHourServer     = 23;     // Inclusive
input ulong  MagicNumber       = 20261022;

int SignalHandle=INVALID_HANDLE;
datetime PreviousBar=0;

bool HasOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return true;
   }
   return false;
}

int EntriesToday()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   now.hour=0; now.min=0; now.sec=0;
   datetime dayStart=StructToTime(now);
   if(!HistorySelect(dayStart,TimeCurrent())) return MaxTradesPerDay; // fail closed
   int n=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)==_Symbol &&
         (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==MagicNumber &&
         HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         n++;
   }
   return n;
}

int VolumePrecision(double step)
{
   for(int digits=0;digits<=8;digits++)
      if(MathAbs(NormalizeDouble(step,digits)-step)<0.00000001)
         return digits;
   return 8;
}

double CalculateRiskLot(ENUM_ORDER_TYPE side,double entry,double stop)
{
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*RiskPercent/100.0;
   double fullLotPL=0.0;
   if(riskMoney<=0 || !OrderCalcProfit(side,_Symbol,1.0,entry,stop,fullLotPL) || fullLotPL>=0)
      return 0.0;
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || minLot<=0 || maxLot<minLot) return 0.0;

   // Round DOWN, never up to the minimum lot: preserve the risk ceiling.
   double raw=riskMoney/MathAbs(fullLotPL);
   double lots=MathFloor((MathMin(raw,maxLot)+1e-10)/step)*step;
   lots=NormalizeDouble(lots,VolumePrecision(step));
   if(lots+1e-10<minLot) return 0.0;

   double margin=0.0;
   if(!OrderCalcMargin(side,_Symbol,lots,entry,margin) ||
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return 0.0;
   return lots;
}

double RoundToTradeTick(double price,bool roundUp)
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;
   double scaled=price/tickSize;
   double rounded=(roundUp ? MathCeil(scaled-1e-9) : MathFloor(scaled+1e-9))*tickSize;
   return NormalizeDouble(rounded,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

void ProcessSignal(ENUM_ORDER_TYPE side,double stop,MqlTick &tick)
{
   double entry=(side==ORDER_TYPE_BUY ? tick.ask : tick.bid);
   double minStop=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(stop==EMPTY_VALUE || stop<=0.0 || entry<=0.0) return;

   // Round to executable tick sizes, away from entry for both exits.
   stop=RoundToTradeTick(stop,side==ORDER_TYPE_SELL);
   if(side==ORDER_TYPE_BUY && stop>=tick.bid-minStop) return;
   if(side==ORDER_TYPE_SELL && stop<=tick.ask+minStop) return;

   double riskDistance=MathAbs(entry-stop);
   double tp=(side==ORDER_TYPE_BUY ? entry+RewardToRisk*riskDistance
                                    : entry-RewardToRisk*riskDistance);
   tp=RoundToTradeTick(tp,side==ORDER_TYPE_BUY);
   if(side==ORDER_TYPE_BUY && tp<=tick.bid+minStop) return;
   if(side==ORDER_TYPE_SELL && tp>=tick.ask-minStop) return;

   double lot=CalculateRiskLot(side,entry,stop);
   if(lot<=0)
   {
      Print("Skipped: minimum lot or margin would exceed the risk budget.");
      return;
   }

   bool sent=false;
   if(side==ORDER_TYPE_BUY)
      sent=trade.Buy(lot,_Symbol,0.0,stop,tp,"TWI protected low");
   else
      sent=trade.Sell(lot,_Symbol,0.0,stop,tp,"TWI protected high");

   uint ret=trade.ResultRetcode();
   if(!sent || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
      Print("Order failed: ",ret," ",trade.ResultRetcodeDescription());
   else
      Print("Trade opened: ",EnumToString(side)," lots=",lot,
            " stop=",stop," tp=",tp," ",trade.ResultRetcodeDescription());
}

int OnInit()
{
   if(RiskPercent<=0 || RiskPercent>2 || RewardToRisk<=0 ||
      MaxTradesPerDay<1 || MaxSpreadPoints<0 || StartHourServer<0 ||
      EndHourServer>23 || StartHourServer>EndHourServer)
      return INIT_PARAMETERS_INCORRECT;
   SignalHandle=iCustom(_Symbol,PERIOD_CURRENT,"TWI_LiquidityReversal",
                        PivotDepth,ATRPeriod,DisplacementATR,ZoneATR,
                        ConfirmationBars,MaxReferenceBars,StopBufferATR,ArrowOffsetATR);
   if(SignalHandle==INVALID_HANDLE)
   {
      Print("Missing indicator TWI_LiquidityReversal or iCustom creation failed: ",GetLastError());
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   PreviousBar=iTime(_Symbol,PERIOD_CURRENT,0); // Never trade an old signal on attaching.
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(SignalHandle!=INVALID_HANDLE) IndicatorRelease(SignalHandle);
}

void OnTick()
{
   datetime currentBar=iTime(_Symbol,PERIOD_CURRENT,0);
   if(currentBar==0 || currentBar==PreviousBar) return;

   // Some terminals calculate a custom indicator *after* the first new-bar tick.
   // Retry on a later tick if its buffers are not ready; do not lose the signal.
   double buy[],sell[],buyStop[],sellStop[];
   if(CopyBuffer(SignalHandle,0,1,1,buy)!=1 ||
      CopyBuffer(SignalHandle,1,1,1,sell)!=1 ||
      CopyBuffer(SignalHandle,2,1,1,buyStop)!=1 ||
      CopyBuffer(SignalHandle,3,1,1,sellStop)!=1) return;
   PreviousBar=currentBar;  // At most one decision per newly opened chart bar.

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   if(HasOurPosition() || EntriesToday()>=MaxTradesPerDay) return;

   if(UseServerTime)
   {
      MqlDateTime now; TimeToStruct(TimeCurrent(),now);
      if(now.hour<StartHourServer || now.hour>EndHourServer) return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask<=0 || tick.bid<=0) return;
   if((tick.ask-tick.bid)/_Point>MaxSpreadPoints) return;

   if(AllowBuy && buy[0]!=EMPTY_VALUE && buyStop[0]!=EMPTY_VALUE)
      ProcessSignal(ORDER_TYPE_BUY,buyStop[0],tick);
   else if(AllowSell && sell[0]!=EMPTY_VALUE && sellStop[0]!=EMPTY_VALUE)
      ProcessSignal(ORDER_TYPE_SELL,sellStop[0],tick);
}
//+------------------------------------------------------------------+
