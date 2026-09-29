//+------------------------------------------------------------------+
//| TWITickExport.mq5  (SCRIPT)                                       |
//| READ-ONLY. Never trades. Exports raw real ticks for one symbol,   |
//| one CSV per broker-server calendar day, exactly as MT5 returns    |
//| them from CopyTicksRange(COPY_TICKS_ALL). Prices are written with |
//| the symbol's own digits - no rounding beyond the feed's precision,|
//| no spread or price adjustment of any kind.                        |
//| Output: Common\Files\tick_export\<SYMBOL>_<YYYY-MM-DD>.csv plus   |
//| export_log.txt. Closes the terminal when done.                    |
//+------------------------------------------------------------------+
#property script_show_inputs false

input string ExportSymbol = "XAUUSD";
input string FromDay      = "2026.09.11";   // first server day, inclusive
input string ToDay        = "2026.09.22";   // last server day, inclusive
input int    MaxRetries   = 5;              // CopyTicksRange retries per day while history syncs
input int    RetrySleepMs = 3000;

void OnStart()
  {
   string dir = "tick_export\\";
   int lg = FileOpen(dir + "export_log.txt", FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   SymbolSelect(ExportSymbol, true);
   int digits = (int)SymbolInfoInteger(ExportSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(ExportSymbol, SYMBOL_POINT);
   FileWrite(lg, StringFormat("symbol=%s digits=%d point=%.8f build=%d server=%s account=%I64d",
             ExportSymbol, digits, point, (int)TerminalInfoInteger(TERMINAL_BUILD),
             AccountInfoString(ACCOUNT_SERVER), AccountInfoInteger(ACCOUNT_LOGIN)));

   datetime from = StringToTime(FromDay);
   datetime to   = StringToTime(ToDay);
   for(datetime day = from; day <= to; day += 86400)
     {
      MqlTick ticks[];
      int n = -1;
      for(int a = 0; a < MaxRetries; a++)
        {
         ResetLastError();
         n = CopyTicksRange(ExportSymbol, ticks, COPY_TICKS_ALL, (ulong)day * 1000, (ulong)(day + 86400) * 1000 - 1);
         if(n >= 0 && GetLastError() == 0) break;
         Sleep(RetrySleepMs);
        }
      int err = GetLastError();
      string ds = TimeToString(day, TIME_DATE);
      StringReplace(ds, ".", "-");
      if(n <= 0)
        {
         FileWrite(lg, StringFormat("%s ticks=%d err=%d (no file written)", ds, n, err));
         continue;
        }
      string fn = dir + ExportSymbol + "_" + ds + ".csv";
      int fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(fh == INVALID_HANDLE) { FileWrite(lg, ds + " cannot open output"); continue; }
      FileWriteString(fh, "time_msc,bid,ask,last,volume,volume_real,flags\n");
      for(int i = 0; i < n; i++)
        {
         FileWriteString(fh, StringFormat("%I64d,%s,%s,%s,%I64u,%.8f,%u\n",
                         ticks[i].time_msc,
                         DoubleToString(ticks[i].bid, digits),
                         DoubleToString(ticks[i].ask, digits),
                         DoubleToString(ticks[i].last, digits),
                         ticks[i].volume, ticks[i].volume_real, ticks[i].flags));
        }
      FileClose(fh);
      FileWrite(lg, StringFormat("%s ticks=%d err=%d first_msc=%I64d last_msc=%I64d file=%s",
                ds, n, err, ticks[0].time_msc, ticks[n - 1].time_msc, fn));
     }
   FileWrite(lg, "DONE");
   FileClose(lg);
   TerminalClose(0);
  }
