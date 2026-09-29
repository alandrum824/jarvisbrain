import os, bisect, datetime as dt, collections, statistics
CUT = dt.datetime(2026, 3, 7); COST = 0.00002; VAL = 1000.0   # $ per 1.0 at 0.01 lot
def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))
def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5
def srv_to_ny(t): return t + dt.timedelta(hours=ny_off(t)) if t < CUT else t - dt.timedelta(hours=7)
seen = set(); bars = []
for fn in ("eurusd_m1_2023.csv", "eurusd_m1_2024_2026.csv"):
    for l in open(os.path.join(os.environ["TEMP"], fn)).read().splitlines()[1:]:
        f = l.split(",")
        if f[0] in seen: continue
        seen.add(f[0]); t = dt.datetime.strptime(f[0], "%Y.%m.%d %H:%M")
        bars.append((srv_to_ny(t), float(f[1]), float(f[2]), float(f[3]), float(f[4])))
bars.sort(); T = [b[0] for b in bars]
h1 = collections.OrderedDict()
for b in bars: h1[b[0].replace(minute=0)] = b[4]
HK = list(h1.keys())
def ema_series(n):
    out = {}; e = None; a = 2 / (n + 1)
    for k in HK: c = h1[k]; e = c if e is None else e + a * (c - e); out[k] = e
    return out
E50, E200 = ema_series(50), ema_series(200)
def last_h(t, ser):
    k = t.replace(minute=0) - dt.timedelta(hours=1)
    for _ in range(100):
        if k in ser: return ser[k]
        k -= dt.timedelta(hours=1)
def yr_of(t):
    if t >= CUT: return "2026"
    if t >= dt.datetime(2025, 3, 10): return "2025-26"
    if t >= dt.datetime(2024, 3, 11): return "2024-25"
    if t >= dt.datetime(2023, 5, 8): return "2023-24"
# daily ranges for the oversized-range filter
sizes = []
def run(label, trend=None, be=None, hold=None, maxsize=None, grid=None):
    res = collections.defaultdict(list); busy = None; hist = []
    day = dt.date(2023, 5, 8); last = bars[-1][0].date()
    while day <= last:
        if day.weekday() < 5:
            st = dt.datetime.combine(day, dt.time(9, 30)); yr = yr_of(st)
            if yr and (busy is None or busy <= st):
                i0 = bisect.bisect_left(T, st); i1 = bisect.bisect_left(T, st + dt.timedelta(minutes=55)); i2 = bisect.bisect_left(T, st + dt.timedelta(minutes=65))
                rng = bars[i0:i1]
                if len(rng) >= 33:
                    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); size = hi - lo
                    med = statistics.median(hist[-20:]) if len(hist) >= 10 else None
                    hist.append(size)
                    skip = maxsize is not None and med is not None and size > maxsize * med
                    for k in range(i1, i2):
                        b = bars[k]; up = b[2] >= hi; dn = b[3] <= lo
                        if not (up or dn): continue
                        if up and dn: break
                        d = 1 if up else -1
                        if skip: break
                        if trend:
                            p = hi if d > 0 else lo; e50 = last_h(b[0], E50); e200 = last_h(b[0], E200)
                            if e50 is None or e200 is None: break
                            ok = {"ema50": (p > e50) if d > 0 else (p < e50), "ema200": (p > e200) if d > 0 else (p < e200),
                                  "aligned": (p > e50 > e200) if d > 0 else (p < e50 < e200)}[trend]
                            if not ok: break
                        e = max(hi, b[1]) if d > 0 else min(lo, b[1])
                        sld = 2.2 * size; sl = e - d * sld; tp = e + d * 0.75 * sld
                        pos = [e]; gridlvl = e - d * grid * sld if grid else None
                        cur_sl = sl; out = None; q = k; t_end = b[0] + dt.timedelta(hours=hold) if hold else None
                        while q < min(k + 60 * 24 * 20, len(bars)):
                            x = bars[q]
                            if grid and len(pos) == 1 and ((d > 0 and x[3] <= gridlvl) or (d < 0 and x[2] >= gridlvl)): pos.append(gridlvl)
                            if (d > 0 and x[3] <= cur_sl) or (d < 0 and x[2] >= cur_sl): out = cur_sl; break
                            tp_now = tp
                            if grid and len(pos) == 2 and grid_tp == "avg": tp_now = sum(pos) / 2 + d * 0.375 * sld
                            if q > k and ((d > 0 and x[2] >= tp_now) or (d < 0 and x[3] <= tp_now)): out = tp_now; break
                            if be and ((d > 0 and x[2] >= e + be * sld) or (d < 0 and x[3] <= e - be * sld)): cur_sl = e + d * 0.00005
                            if t_end and x[0] >= t_end: out = x[4]; break
                            q += 1
                        if out is None: break
                        busy = bars[q][0]
                        pnl = sum((d * (out - p_) - COST) * VAL for p_ in pos)
                        res[yr].append((bars[q][0], pnl))
                        break
        day += dt.timedelta(days=1)
    line = []; tot = 0; worst = 0
    for yr in ("2023-24", "2024-25", "2025-26", "2026"):
        v = res[yr]; net = sum(p for _, p in v); tot += net
        eq = pk = dd = 0
        for _, p in v: eq += p; pk = max(pk, eq); dd = max(dd, pk - eq)
        worst = max(worst, dd)
        line.append("%s %+7.2f(n%3d,DD$%5.1f)" % (yr, net, len(v), dd))
    allpos = all(sum(p for _, p in res[y]) > 0 for y in ("2023-24", "2024-25", "2025-26", "2026"))
    print(label.ljust(24), " | ".join(line), "| total %+7.2f | worstDD $%5.1f (=%2.0f%% of $200) %s" % (tot, worst, worst / 2, "ALL+" if allpos else ""))
grid_tp = "orig"
run("ema50 + BE0.4", trend="ema50", be=0.4)
run("ema50 + BE0.6", trend="ema50", be=0.6)
run("ema50 + grid@0.5", trend="ema50", grid=0.5)
run("ema50 + BE0.4 + grid@0.5", trend="ema50", be=0.4, grid=0.5)
run("ema50 + hold24h", trend="ema50", hold=24)
