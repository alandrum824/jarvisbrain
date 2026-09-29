//+------------------------------------------------------------------+
//| TWISpreadAudit.mq5                                                |
//| Read-only measurement tool. Never trades.                         |
//| Records the broker spread on EVERY tick of a real-tick tester run |
//| and writes the unconditional distribution, split by the same      |
//| session windows TWI Liquidity Sweep OB EA V1 uses (broker server  |
//| time, weekdays): S1 08:00-11:00, S2 13:00-17:00.                  |
//| Spread = SymbolInfoInteger(SYMBOL_SPREAD), exactly what the V1    |
//| MaxSpreadPoints gate reads. (ask-bid)/point is recorded alongside |
//| as a cross-check.                                                 |
//| Two weightings: per tick, and per minute (last tick of each M1    |
//| minute) so dense-tick periods don't dominate.                     |
//+------------------------------------------------------------------+
#property strict

input string OutFile = "twi_spread_audit.txt";

#define MAXPTS 5000
#define NGROUPS 4   // 0 = all, 1 = session 1, 2 = session 2, 3 = outside sessions

long     g_tick[NGROUPS][MAXPTS + 1];   // per-tick histogram, SYMBOL_SPREAD
long     g_min[NGROUPS][MAXPTS + 1];    // per-minute histogram, SYMBOL_SPREAD
long     g_mismatch = 0;                // ticks where SYMBOL_SPREAD != round((ask-bid)/point)
long     g_ticks = 0;
datetime g_first = 0, g_last = 0;
datetime g_curMinute = 0;
int      g_curMinuteSpread = -1;
int      g_curMinuteGroup = 0;

int SessionGroup(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.day_of_week < 1 || dt.day_of_week > 5) return 3;
   int m = dt.hour * 60 + dt.min;
   if(m >= 8 * 60 && m < 11 * 60) return 1;
   if(m >= 13 * 60 && m < 17 * 60) return 2;
   return 3;
  }

void FlushMinute()
  {
   if(g_curMinuteSpread < 0) return;
   g_min[0][g_curMinuteSpread]++;
   g_min[g_curMinuteGroup][g_curMinuteSpread]++;
  }

int OnInit() { return INIT_SUCCEEDED; }

void OnTick()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp < 0) sp = 0;
   if(sp > MAXPTS) sp = MAXPTS;

   int calc = (int)MathRound((t.ask - t.bid) / _Point);
   if(calc != (int)sp) g_mismatch++;

   int g = SessionGroup(t.time);
   g_tick[0][sp]++;
   g_tick[g][sp]++;
   g_ticks++;
   if(g_first == 0) g_first = t.time;
   g_last = t.time;

   datetime minute = t.time - (t.time % 60);
   if(minute != g_curMinute)
     {
      FlushMinute();
      g_curMinute = minute;
     }
   g_curMinuteSpread = (int)sp;
   g_curMinuteGroup = g;
  }

long Total(long &h[][MAXPTS + 1], int g)
  {
   long n = 0;
   for(int i = 0; i <= MAXPTS; i++) n += h[g][i];
   return n;
  }

int Pct(long &h[][MAXPTS + 1], int g, double p)
  {
   long n = Total(h, g);
   if(n == 0) return -1;
   long target = (long)MathCeil(p * n);
   if(target < 1) target = 1;
   long c = 0;
   for(int i = 0; i <= MAXPTS; i++) { c += h[g][i]; if(c >= target) return i; }
   return MAXPTS;
  }

string Row(long &h[][MAXPTS + 1], int g, string name)
  {
   long n = Total(h, g);
   if(n == 0) return StringFormat("%-10s n=0", name);
   int mn = -1, mx = 0;
   double sum = 0;
   for(int i = 0; i <= MAXPTS; i++)
     {
      if(h[g][i] == 0) continue;
      if(mn < 0) mn = i;
      mx = i;
      sum += (double)i * h[g][i];
     }
   return StringFormat("%-10s n=%-9I64d min=%-4d median=%-4d mean=%-7.2f p75=%-4d p90=%-4d p95=%-4d p99=%-4d max=%d",
                       name, n, mn, Pct(h, g, 0.50), sum / n, Pct(h, g, 0.75), Pct(h, g, 0.90),
                       Pct(h, g, 0.95), Pct(h, g, 0.99), mx);
  }

void WriteHist(int fh, long &h[][MAXPTS + 1], int g, string name)
  {
   long n = Total(h, g);
   FileWrite(fh, "  histogram " + name + " (points: count, cumulative %)");
   long c = 0;
   for(int i = 0; i <= MAXPTS; i++)
     {
      if(h[g][i] == 0) continue;
      c += h[g][i];
      FileWrite(fh, StringFormat("    %4d: %10I64d  %7.3f%%", i, h[g][i], 100.0 * c / n));
     }
  }

void OnDeinit(const int reason)
  {
   FlushMinute();
   int fh = FileOpen(OutFile, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE) { Print("TWISpreadAudit: cannot open output file"); return; }
   string names[NGROUPS] = {"ALL", "SESSION1", "SESSION2", "OUTSIDE"};
   FileWrite(fh, "TWI SPREAD AUDIT - " + _Symbol + "  (spread = SYMBOL_SPREAD, EA points; point=" + DoubleToString(_Point, 5) + ")");
   FileWrite(fh, "First tick: " + TimeToString(g_first, TIME_DATE | TIME_SECONDS) +
                 "   Last tick: " + TimeToString(g_last, TIME_DATE | TIME_SECONDS) +
                 "   Ticks: " + (string)g_ticks);
   FileWrite(fh, "SYMBOL_SPREAD vs round((ask-bid)/point) mismatches: " + (string)g_mismatch);
   FileWrite(fh, "Sessions (server time, Mon-Fri): S1 08:00-11:00, S2 13:00-17:00. They do not overlap.");
   FileWrite(fh, "---- PER TICK ----");
   for(int g = 0; g < NGROUPS; g++) FileWrite(fh, Row(g_tick, g, names[g]));
   FileWrite(fh, "---- PER MINUTE (last tick of each minute) ----");
   for(int g = 0; g < NGROUPS; g++) FileWrite(fh, Row(g_min, g, names[g]));
   FileWrite(fh, "---- HISTOGRAMS (per tick) ----");
   for(int g = 0; g < NGROUPS; g++) WriteHist(fh, g_tick, g, names[g]);
   FileWrite(fh, "DONE");
   FileClose(fh);
   Print("TWISpreadAudit: wrote ", OutFile, "  ticks=", g_ticks);
  }
