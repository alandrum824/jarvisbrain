//+------------------------------------------------------------------+
//|                                       TWI Telegram Copy.mq5      |
//|  Copy-trader style signal executor.                              |
//|  A separate Python process (telegram_signal_listener.py) reads   |
//|  Adam's own Telegram account and appends parsed signals as rows  |
//|  to a shared CSV in the terminal's Common\Files folder. This EA  |
//|  polls that file on a timer and, for each NEW row:                |
//|   1. Maps the signal's symbol (GOLD/XAUUSD) to a real chart      |
//|      symbol (SymbolSuffix appended if this broker needs one).    |
//|   2. Skips it if current price is outside the signal's stated    |
//|      entry range (+ EntryBufferPoints) -- don't chase a missed   |
//|      entry.                                                       |
//|   3. Opens up to 4 separate legs (LegLotSize each), same entry   |
//|      and SL, but each leg's own TP (TP1..TP3 fixed, TP4 = no TP, |
//|      i.e. a runner) -- replicates the channel's own TP ladder    |
//|      instead of picking one fixed target.                        |
//+------------------------------------------------------------------+
#property copyright "TWI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input group "=== General ==="
input long   MagicNumber        = 20260902;
input string SignalFileName     = "telegram_signals.csv";  // in the terminal's Common\Files folder
input string SymbolSuffix       = "";                       // appended to mapped symbol (e.g. ".sim") if this broker needs it
input int    PollSeconds        = 3;

input group "=== Entry ==="
input double EntryBufferPoints  = 50;    // extra tolerance (points) around the signal's stated entry range
input int    MaxSignalAgeSec    = 300;   // ignore a signal if it's older than this by the time we see it

input group "=== Legs / Risk ==="
input double LegLotSize         = 0.01;  // lot size per TP leg
input int    MaxLegs            = 4;     // one per TP1..TP4 (a blank TP = runner, no fixed target)

//----------------- processed-row bookkeeping -----------------
long processedIds[];
int  lastRowCount = 0;
bool initializedFromExisting = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   ArrayResize(processedIds, 0);
   // Mark every row already in the file as "seen" so we never trade a
   // backlog of old signals from before this EA was attached.
   SeedProcessedFromExistingFile();
   EventSetTimer(PollSeconds);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
bool AlreadyProcessed(long id)
  {
   for(int i = 0; i < ArraySize(processedIds); i++)
      if(processedIds[i] == id)
         return true;
   return false;
  }

void MarkProcessed(long id)
  {
   int n = ArraySize(processedIds);
   ArrayResize(processedIds, n + 1);
   processedIds[n] = id;
  }

//+------------------------------------------------------------------+
void SeedProcessedFromExistingFile()
  {
   int h = FileOpen(SignalFileName, FILE_READ | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      return;
   bool firstLine = true;
   while(!FileIsEnding(h))
     {
      string idStr = FileReadString(h);
      if(idStr == "")
         break;
      // skip the rest of the row
      for(int c = 1; c < 11 && !FileIsLineEnding(h); c++)
         FileReadString(h);
      if(firstLine) { firstLine = false; continue; } // header row
      long id = StringToInteger(idStr);
      if(id != 0)
         MarkProcessed(id);
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
string MapSymbol(string sig)
  {
   string s = sig;
   if(s == "GOLD" || s == "XAU")
      s = "XAUUSD";
   return s + SymbolSuffix;
  }

//+------------------------------------------------------------------+
void ExecuteSignal(long id, long receivedTs, string symbol, string direction,
                    double entryLow, double entryHigh, double sl,
                    double tp1, bool hasTp1, double tp2, bool hasTp2,
                    double tp3, bool hasTp3, double tp4, bool hasTp4)
  {
   if((long)TimeCurrent() - receivedTs > MaxSignalAgeSec)
     {
      PrintFormat("TWI Telegram Copy: signal #%d too stale (%ds old), skipped", id, (long)TimeCurrent() - receivedTs);
      return;
     }

   if(!SymbolSelect(symbol, true))
     {
      PrintFormat("TWI Telegram Copy: symbol %s not found, skipped signal #%d", symbol, id);
      return;
     }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double buffer = EntryBufferPoints * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double refPrice = (direction == "BUY") ? ask : bid;

   if(refPrice < entryLow - buffer || refPrice > entryHigh + buffer)
     {
      PrintFormat("TWI Telegram Copy: price %.5f outside signal range %.5f-%.5f (+/-buffer), skipped #%d",
                  refPrice, entryLow, entryHigh, id);
      return;
     }

   double tps[4];       bool hasTp[4];
   tps[0] = tp1; hasTp[0] = hasTp1;
   tps[1] = tp2; hasTp[1] = hasTp2;
   tps[2] = tp3; hasTp[2] = hasTp3;
   tps[3] = tp4; hasTp[3] = hasTp4;

   int legsOpened = 0;
   for(int leg = 0; leg < MaxLegs && leg < 4; leg++)
     {
      double tp = hasTp[leg] ? tps[leg] : 0.0;   // 0.0 = no TP, runner leg
      string cmt = StringFormat("TG#%d L%d", id, leg + 1);
      bool ok;
      if(direction == "BUY")
         ok = trade.Buy(LegLotSize, symbol, 0, sl, tp, cmt);
      else
         ok = trade.Sell(LegLotSize, symbol, 0, sl, tp, cmt);
      if(ok)
         legsOpened++;
      else
         PrintFormat("TWI Telegram Copy: leg %d failed for signal #%d, retcode %d", leg + 1, id, trade.ResultRetcode());
     }
   PrintFormat("TWI Telegram Copy: signal #%d (%s %s) opened %d/%d legs", id, direction, symbol, legsOpened, MathMin(MaxLegs, 4));
  }

//+------------------------------------------------------------------+
void PollSignalFile()
  {
   int h = FileOpen(SignalFileName, FILE_READ | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      return;

   bool firstLine = true;
   while(!FileIsEnding(h))
     {
      string idStr = FileReadString(h);
      if(idStr == "")
         break;

      string tsStr     = FileReadString(h);
      string symStr    = FileReadString(h);
      string dirStr    = FileReadString(h);
      string elowStr   = FileReadString(h);
      string ehighStr  = FileReadString(h);
      string slStr     = FileReadString(h);
      string tp1Str    = FileReadString(h);
      string tp2Str    = FileReadString(h);
      string tp3Str    = FileReadString(h);
      string tp4Str    = FileReadString(h);

      if(firstLine)
        {
         firstLine = false;
         continue; // header row
        }

      long id = StringToInteger(idStr);
      if(id == 0 || AlreadyProcessed(id))
         continue;
      MarkProcessed(id);

      long   receivedTs = StringToInteger(tsStr);
      string symbol     = MapSymbol(symStr);
      string direction  = dirStr;
      double entryLow   = StringToDouble(elowStr);
      double entryHigh  = StringToDouble(ehighStr);
      double sl         = StringToDouble(slStr);

      double tp1 = StringToDouble(tp1Str); bool hasTp1 = (tp1Str != "");
      double tp2 = StringToDouble(tp2Str); bool hasTp2 = (tp2Str != "");
      double tp3 = StringToDouble(tp3Str); bool hasTp3 = (tp3Str != "");
      double tp4 = StringToDouble(tp4Str); bool hasTp4 = (tp4Str != "");

      ExecuteSignal(id, receivedTs, symbol, direction, entryLow, entryHigh, sl,
                    tp1, hasTp1, tp2, hasTp2, tp3, hasTp3, tp4, hasTp4);
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   PollSignalFile();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
  }
//+------------------------------------------------------------------+
