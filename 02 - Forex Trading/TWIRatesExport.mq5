//+------------------------------------------------------------------+
//| TWIRatesExport.mq5  (SCRIPT)                                      |
//| READ-ONLY. Never trades. Exports the broker's M1 bars for one     |
//| symbol and server-time range to Common\Files\rates_export.csv     |
//| (used to cross-check external tick data: price scale + timezone), |
//| then closes the terminal.                                         |
//+------------------------------------------------------------------+
#property script_show_inputs false

input string RSymbol = "XAUUSD";
input string RFrom   = "2026.03.10 00:00";
input string RTo     = "2026.03.13 00:00";

void OnStart()
  {
   MqlRates r[];
   SymbolSelect(RSymbol, true);
   int n = -1;
   for(int a = 0; a < 20 && n <= 0; a++)   // history may still be loading on a fresh start (err 4401)
     {
      ResetLastError();
      n = CopyRates(RSymbol, PERIOD_M1, StringToTime(RFrom), StringToTime(RTo), r);
      if(n <= 0) Sleep(3000);
     }
   int fh = FileOpen("rates_export.csv", FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   int dg = (int)SymbolInfoInteger(RSymbol, SYMBOL_DIGITS);
   FileWriteString(fh, StringFormat("# symbol=%s server=%s bars=%d err=%d\n", RSymbol, AccountInfoString(ACCOUNT_SERVER), n, GetLastError()));
   FileWriteString(fh, "time_server,open,high,low,close,tick_volume,spread\n");
   for(int i = 0; i < n; i++)
      FileWriteString(fh, StringFormat("%s,%s,%s,%s,%s,%I64d,%d\n",
                      TimeToString(r[i].time, TIME_DATE | TIME_MINUTES),
                      DoubleToString(r[i].open, dg), DoubleToString(r[i].high, dg),
                      DoubleToString(r[i].low, dg), DoubleToString(r[i].close, dg),
                      r[i].tick_volume, r[i].spread));
   FileClose(fh);
   TerminalClose(0);
  }
