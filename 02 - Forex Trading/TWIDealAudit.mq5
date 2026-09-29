//+------------------------------------------------------------------+
//| TWIDealAudit.mq5  (SCRIPT)                                        |
//| READ-ONLY. Never sends, modifies or closes an order or position.  |
//| Dumps the account's full deal history (all symbols) to a CSV in   |
//| the Common Files folder so live commission/swap/fee can be        |
//| inspected per deal, then closes the terminal.                     |
//+------------------------------------------------------------------+
#property script_show_inputs false

void OnStart()
  {
   string fn = "twi_deal_audit.csv";
   int fh = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) { Print("TWIDealAudit: cannot open ", fn); TerminalClose(1); return; }

   FileWrite(fh, "account", "server", "deal", "position_id", "order", "time", "symbol", "type", "entry",
             "volume", "price", "commission", "swap", "fee", "profit", "magic", "reason", "comment");

   if(!HistorySelect(0, TimeCurrent() + 86400))
     { Print("TWIDealAudit: HistorySelect failed ", GetLastError()); FileClose(fh); TerminalClose(1); return; }

   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      string sym = HistoryDealGetString(d, DEAL_SYMBOL);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits <= 0) digits = 5;
      FileWrite(fh,
                (string)AccountInfoInteger(ACCOUNT_LOGIN),
                AccountInfoString(ACCOUNT_SERVER),
                (string)d,
                (string)HistoryDealGetInteger(d, DEAL_POSITION_ID),
                (string)HistoryDealGetInteger(d, DEAL_ORDER),
                TimeToString((datetime)HistoryDealGetInteger(d, DEAL_TIME), TIME_DATE | TIME_SECONDS),
                sym,
                EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE)),
                EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY)),
                DoubleToString(HistoryDealGetDouble(d, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(d, DEAL_PRICE), digits),
                DoubleToString(HistoryDealGetDouble(d, DEAL_COMMISSION), 2),
                DoubleToString(HistoryDealGetDouble(d, DEAL_SWAP), 2),
                DoubleToString(HistoryDealGetDouble(d, DEAL_FEE), 2),
                DoubleToString(HistoryDealGetDouble(d, DEAL_PROFIT), 2),
                (string)HistoryDealGetInteger(d, DEAL_MAGIC),
                EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(d, DEAL_REASON)),
                HistoryDealGetString(d, DEAL_COMMENT));
     }
   FileClose(fh);
   PrintFormat("TWIDealAudit: wrote %d deals to %s", n, fn);
   TerminalClose(0);
  }
