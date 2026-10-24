//+------------------------------------------------------------------+
//| TWI_LiquidityReversal.mq5                                         |
//| Research prototype: protected swing retest -> confirmation       |
//| A mechanical interpretation of the screenshots, NOT a copy of    |
//| an undisclosed proprietary strategy or a validated edge.         |
//+------------------------------------------------------------------+
#property copyright "TWI - Research Prototype"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   6

#property indicator_label1 "Bullish confirmation"
#property indicator_type1  DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 2

#property indicator_label2 "Bearish confirmation"
#property indicator_type2  DRAW_ARROW
#property indicator_color2 clrTomato
#property indicator_width2 2

#property indicator_label3 "Buy SL reference"
#property indicator_type3  DRAW_NONE
#property indicator_label4 "Sell SL reference"
#property indicator_type4  DRAW_NONE

#property indicator_label5 "Protected high zone"
#property indicator_type5  DRAW_FILLING
#property indicator_color5 clrLightSkyBlue,clrLightSkyBlue

#property indicator_label6 "Protected low zone"
#property indicator_type6  DRAW_FILLING
#property indicator_color6 clrPaleGreen,clrPaleGreen

input int    PivotDepth       = 3;     // Confirm swing after N closed candles
input int    ATRPeriod        = 14;
input double DisplacementATR  = 1.20;  // Move away to arm the reference high/low
input double ZoneATR          = 0.55;  // Zone width on each side of protected level
input int    ConfirmationBars = 4;     // Max bars to close beyond retest candle
input int    MaxReferenceBars = 100;   // Expiry of a swing reference
input double StopBufferATR    = 0.12;  // Beyond protected extreme
input double ArrowOffsetATR   = 0.20;

double BuyArrow[], SellArrow[], BuySL[], SellSL[];
double HighZoneTop[], HighZoneBottom[], LowZoneTop[], LowZoneBottom[];
int ATRHandle=INVALID_HANDLE;

bool PivotHigh(const int p,const int depth,const int total,const double &high[])
{
   if(p-depth<1 || p+depth>=total) return false;
   for(int d=1;d<=depth;d++)
      if(high[p]<=high[p-d] || high[p]<=high[p+d]) return false;
   return true;
}

bool PivotLow(const int p,const int depth,const int total,const double &low[])
{
   if(p-depth<1 || p+depth>=total) return false;
   for(int d=1;d<=depth;d++)
      if(low[p]>=low[p-d] || low[p]>=low[p+d]) return false;
   return true;
}

int OnInit()
{
   if(PivotDepth<1 || ATRPeriod<2 || DisplacementATR<=0 || ZoneATR<=0 ||
      ConfirmationBars<1 || MaxReferenceBars<=PivotDepth || StopBufferATR<0)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0,BuyArrow,INDICATOR_DATA);
   SetIndexBuffer(1,SellArrow,INDICATOR_DATA);
   SetIndexBuffer(2,BuySL,INDICATOR_DATA);
   SetIndexBuffer(3,SellSL,INDICATOR_DATA);
   SetIndexBuffer(4,HighZoneTop,INDICATOR_DATA);
   SetIndexBuffer(5,HighZoneBottom,INDICATOR_DATA);
   SetIndexBuffer(6,LowZoneTop,INDICATOR_DATA);
   SetIndexBuffer(7,LowZoneBottom,INDICATOR_DATA);
   ArraySetAsSeries(BuyArrow,true);
   ArraySetAsSeries(SellArrow,true);
   ArraySetAsSeries(BuySL,true);
   ArraySetAsSeries(SellSL,true);
   ArraySetAsSeries(HighZoneTop,true);
   ArraySetAsSeries(HighZoneBottom,true);
   ArraySetAsSeries(LowZoneTop,true);
   ArraySetAsSeries(LowZoneBottom,true);

   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   // DRAW_FILLING: use 0.0 as the absence of a zone.
   PlotIndexSetDouble(4,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(5,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"TWI Protected Liquidity Reversal (research)");
   ATRHandle=iATR(_Symbol,PERIOD_CURRENT,ATRPeriod);
   return (ATRHandle==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(ATRHandle!=INVALID_HANDLE) IndicatorRelease(ATRHandle);
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   int minBars=ATRPeriod+2*PivotDepth+15;
   if(rates_total<minBars) return 0;
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   static datetime cachedClosed=0;
   if(prev_calculated==rates_total && cachedClosed==time[1]) return rates_total;

   double atr[];
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(ATRHandle,0,0,rates_total,atr)!=rates_total)
      return prev_calculated;

   ArrayInitialize(BuyArrow,EMPTY_VALUE);
   ArrayInitialize(SellArrow,EMPTY_VALUE);
   ArrayInitialize(BuySL,EMPTY_VALUE);
   ArrayInitialize(SellSL,EMPTY_VALUE);
   ArrayInitialize(HighZoneTop,0.0);
   ArrayInitialize(HighZoneBottom,0.0);
   ArrayInitialize(LowZoneTop,0.0);
   ArrayInitialize(LowZoneBottom,0.0);

   // Only closed bars are processed (bar 0 is never a signal).
   // Chronological processing means no future candles can validate past signals.
   int hPhase=0, lPhase=0;   // 0=none, 1=pivot, 2=armed, 3=touched
   int hBorn=0,lBorn=0,hTouch=0,lTouch=0;
   double hRef=0,lRef=0,hTouchLow=0,lTouchHigh=0;
   int oldest=rates_total-2*PivotDepth-2;

   for(int i=oldest;i>=1;i--)
   {
      double a=atr[i];
      if(a<=0.0 || a==EMPTY_VALUE) continue;

      // Expire very old levels; pivot is 'born' where its high/low occurred.
      if(hPhase!=0 && hBorn-i>MaxReferenceBars) hPhase=0;
      if(lPhase!=0 && lBorn-i>MaxReferenceBars) lPhase=0;

      int p=i+PivotDepth;
      if(hPhase<=1 && PivotHigh(p,PivotDepth,rates_total,high))
      {
         hRef=high[p]; hBorn=p; hPhase=1;
      }
      if(lPhase<=1 && PivotLow(p,PivotDepth,rates_total,low))
      {
         lRef=low[p]; lBorn=p; lPhase=1;
      }

      // A protected high is invalid once any later wick reaches it.
      // This implementation intentionally does NOT trade a liquidity sweep.
      if(hPhase!=0 && high[i]>=hRef) hPhase=0;
      if(lPhase!=0 && low[i]<=lRef) lPhase=0;

      if(hPhase==1 && close[i]<=hRef-DisplacementATR*a) hPhase=2;
      if(lPhase==1 && close[i]>=lRef+DisplacementATR*a) lPhase=2;

      if(hPhase==2 || hPhase==3)
      {
         HighZoneTop[i]=hRef;
         HighZoneBottom[i]=hRef-ZoneATR*a;
      }
      if(lPhase==2 || lPhase==3)
      {
         LowZoneTop[i]=lRef+ZoneATR*a;
         LowZoneBottom[i]=lRef;
      }

      if(hPhase==2 && high[i]>=hRef-ZoneATR*a && high[i]<hRef)
      {
         hTouch=i; hTouchLow=low[i]; hPhase=3;
      }
      else if(hPhase==3)
      {
         if(hTouch-i>ConfirmationBars) hPhase=0;
         else if(i<hTouch && close[i]<hTouchLow && close[i]<open[i])
         {
            SellArrow[i]=high[i]+ArrowOffsetATR*a;
            SellSL[i]=hRef+StopBufferATR*a;
            hPhase=0;
         }
      }

      if(lPhase==2 && low[i]<=lRef+ZoneATR*a && low[i]>lRef)
      {
         lTouch=i; lTouchHigh=high[i]; lPhase=3;
      }
      else if(lPhase==3)
      {
         if(lTouch-i>ConfirmationBars) lPhase=0;
         else if(i<lTouch && close[i]>lTouchHigh && close[i]>open[i])
         {
            BuyArrow[i]=low[i]-ArrowOffsetATR*a;
            BuySL[i]=lRef-StopBufferATR*a;
            lPhase=0;
         }
      }
   }
   cachedClosed=time[1];
   return rates_total;
}
//+------------------------------------------------------------------+
