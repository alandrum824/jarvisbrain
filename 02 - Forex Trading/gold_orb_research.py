import os, datetime as dt, collections
p = os.path.expandvars(r"%TEMP%\xauusd_m1_2024_2026.csv")
CUT = dt.datetime(2026, 3, 7); COST = 0.55; BUF = 0.30
def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))
def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5
def srv_to_ny(t): return t + dt.timedelta(hours=ny_off(t)) if t < CUT else t - dt.timedelta(hours=7)
bars = []
for l in open(p).read().splitlines()[1:]:
    f = l.split(","); t = dt.datetime.strptime(f[0], "%Y.%m.%d %H:%M")
    bars.append((srv_to_ny(t), float(f[1]), float(f[2]), float(f[3]), float(f[4])))
# clock check: last bar on Fridays (NY) should be ~16:58-16:59
fri = collections.OrderedDict()
for b in bars:
    if b[0].weekday() == 4 and b[0].hour < 18: fri[b[0].date()] = b[0].time()
print("Friday last-bar NY times:", collections.Counter(t.strftime("%H:%M") for t in fri.values()).most_common(4))
h1 = collections.OrderedDict()
for b in bars: h1[b[0].replace(minute=0)] = b[4]
ema = {}; e = None; a = 2 / 201
for k, c in h1.items(): e = c if e is None else e + a * (c - e); ema[k] = e
def ema_before(t):
    k = t.replace(minute=0) - dt.timedelta(hours=1)
    for _ in range(80):
        if k in ema: return ema[k]
        k -= dt.timedelta(hours=1)
days = collections.defaultdict(list)
for b in bars:
    if b[0].weekday() < 5 and dt.time(9, 30) <= b[0].time() < dt.time(16, 0): days[b[0].date()].append(b)
def m5(bs):
    out = collections.OrderedDict()
    for b in bs:
        k = b[0].replace(minute=b[0].minute - b[0].minute % 5)
        if k not in out: out[k] = [k, b[1], b[2], b[3], b[4]]
        else: o = out[k]; o[2] = max(o[2], b[2]); o[3] = min(o[3], b[3]); o[4] = b[4]
    return list(out.values())
def outcome(m1, k0, d, entry, sl, R):
    risk = abs(entry - sl); tp = entry + d * R * risk
    for k in range(k0, len(m1)):
        x = m1[k]
        if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl): return -1.0 - COST / risk
        if (d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp): return R - COST / risk
    return d * (m1[-1][4] - entry) / risk - COST / risk
TPS = (1.0, 1.5, 2.0, 3.0)
S = collections.defaultdict(lambda: collections.defaultdict(list))
for day, m1 in sorted(days.items()):
    if len(m1) < 300: continue
    yr = "2026" if day >= CUT.date() else ("2025-26" if day >= dt.date(2025, 3, 10) else ("2024-25" if day >= dt.date(2024, 3, 11) else None))
    if not yr: continue
    rng = [b for b in m1 if b[0].time() < dt.time(9, 45)]
    if len(rng) < 10: continue
    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); mid = (hi + lo) / 2
    b5 = [b for b in m5(m1) if dt.time(9, 45) <= b[0].time() < dt.time(12, 0)]
    for trend in (False, True):
        tg = ("trend" if trend else "all")
        # G1: first M5 close beyond the range -> enter at next M1 open
        for b in b5:
            d = 1 if b[4] > hi else (-1 if b[4] < lo else 0)
            if not d: continue
            if trend:
                em = ema_before(b[0] + dt.timedelta(minutes=5))
                if em is None or (d > 0 and b[4] <= em) or (d < 0 and b[4] >= em): break
            t_in = b[0] + dt.timedelta(minutes=5)
            k = next((i for i, y in enumerate(m1) if y[0] >= t_in), None)
            if k is None: break
            e = m1[k][1]
            for nm, sl in (("mid", mid), ("opp", lo - BUF if d > 0 else hi + BUF), ("bar", b[3] - BUF if d > 0 else b[2] + BUF)):
                if (e - sl) * d <= 0: continue
                for R in TPS: S["G1 ORB break-close SL=" + nm + " " + tg][(yr, R)].append(outcome(m1, k, d, e, sl, R))
            break
        # G2: sweep & reclaim - M5 wick beyond an edge, close back inside -> fade; SL beyond the sweep extreme
        for b in b5:
            up = b[2] > hi and b[4] < hi
            dn = b[3] < lo and b[4] > lo
            if not (up or dn): 
                if b[4] > hi or b[4] < lo: break   # a real close outside first = breakout day, no fade
                continue
            d = -1 if up else 1
            if trend:
                em = ema_before(b[0] + dt.timedelta(minutes=5))
                if em is None or (d > 0 and b[4] <= em) or (d < 0 and b[4] >= em): break
            t_in = b[0] + dt.timedelta(minutes=5)
            k = next((i for i, y in enumerate(m1) if y[0] >= t_in), None)
            if k is None: break
            e = m1[k][1]; sl = b[2] + BUF if d < 0 else b[3] - BUF
            if (e - sl) * d > 0:
                for R in TPS: S["G2 sweep-reclaim fade " + tg][(yr, R)].append(outcome(m1, k, d, e, sl, R))
            break
for key in sorted(S):
    for yr in ("2024-25", "2025-26", "2026"):
        v1 = S[key][(yr, 1.0)]
        row = []
        for R in TPS:
            v = S[key][(yr, R)]
            if v: row.append("TP%.2g:%+6.1fR/%2.0f%%" % (R, sum(v), 100 * sum(1 for z in v if z > 0) / len(v)))
        print(key.ljust(32), yr, "n=%3d" % len(v1), "  ".join(row))
