//+------------------------------------------------------------------+
//| TWIBarsExportTester.mq5  (EA, run in the Strategy Tester only)    |
//| READ-ONLY. Never trades. Writes every completed M1 bar of the     |
//| tester window to Common\Files\bars_export_tester.csv. Used where  |
//| the live terminal can't serve old M1 history (max-bars limit).    |
//+------------------------------------------------------------------+
#property strict

int      g_fh = INVALID_HANDLE;
datetime g_last = 0;

int OnInit()
  {
   g_fh = FileOpen("bars_export_tester.csv", FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) return INIT_FAILED;
   FileWriteString(g_fh, "time_server,open,high,low,close,tick_volume,spread\n");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime t = iTime(_Symbol, PERIOD_M1, 1);
   if(t == 0 || t == g_last) return;
   g_last = t;
   FileWriteString(g_fh, StringFormat("%s,%s,%s,%s,%s,%I64d,%d\n",
                   TimeToString(t, TIME_DATE | TIME_MINUTES),
                   DoubleToString(iOpen(_Symbol, PERIOD_M1, 1), _Digits),
                   DoubleToString(iHigh(_Symbol, PERIOD_M1, 1), _Digits),
                   DoubleToString(iLow(_Symbol, PERIOD_M1, 1), _Digits),
                   DoubleToString(iClose(_Symbol, PERIOD_M1, 1), _Digits),
                   iVolume(_Symbol, PERIOD_M1, 1), iSpread(_Symbol, PERIOD_M1, 1)));
  }

void OnDeinit(const int reason) { if(g_fh != INVALID_HANDLE) FileClose(g_fh); }
