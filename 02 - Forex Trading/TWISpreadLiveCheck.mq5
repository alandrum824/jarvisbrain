//+------------------------------------------------------------------+
//| TWISpreadLiveCheck.mq5  (SCRIPT)                                  |
//| READ-ONLY. Never trades. For ~30 seconds, samples the LIVE quote  |
//| the account actually sees (SymbolInfoTick / SYMBOL_SPREAD) next   |
//| to the newest tick stored in tick history (CopyTicks), to measure |
//| any fixed spread markup between the stored feed and the account's |
//| quotes. Writes Common\Files\twi_spread_live_check.txt, then closes|
//| the terminal.                                                     |
//+------------------------------------------------------------------+
#property script_show_inputs false

void OnStart()
  {
   string sym = "XAUUSD";
   SymbolSelect(sym, true);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int fh = FileOpen("twi_spread_live_check.txt", FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   FileWrite(fh, StringFormat("server=%s build=%d spread_float=%d",
             AccountInfoString(ACCOUNT_SERVER), (int)TerminalInfoInteger(TERMINAL_BUILD),
             (int)SymbolInfoInteger(sym, SYMBOL_SPREAD_FLOAT)));
   FileWrite(fh, "server_time,live_bid,live_ask,live_spread_pts,SYMBOL_SPREAD,hist_time_msc,hist_bid,hist_ask,hist_spread_pts");
   for(int i = 0; i < 30; i++)
     {
      MqlTick live;
      SymbolInfoTick(sym, live);
      long ss = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      MqlTick h[];
      int n = CopyTicks(sym, h, COPY_TICKS_ALL, 0, 1);
      FileWrite(fh, StringFormat("%s,%.2f,%.2f,%d,%d,%I64d,%.2f,%.2f,%d",
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                live.bid, live.ask, (int)MathRound((live.ask - live.bid) / pt), (int)ss,
                n > 0 ? h[0].time_msc : 0, n > 0 ? h[0].bid : 0.0, n > 0 ? h[0].ask : 0.0,
                n > 0 ? (int)MathRound((h[0].ask - h[0].bid) / pt) : -1));
      Sleep(1000);
     }
   FileClose(fh);
   TerminalClose(0);
  }
