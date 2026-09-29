import os, datetime as dt, collections, json
p = os.path.expandvars(r"%APPDATA%\MetaQuotes\Terminal\Common\Files\bars_export_tester.csv")
CUT = dt.datetime(2026, 3, 7)
def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))
def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5
def srv_to_ny(t):
    if t < CUT: return t + dt.timedelta(hours=ny_off(t))
    return t - dt.timedelta(hours=7)
bars = []
for l in open(p).read().splitlines()[1:]:
    f = l.split(","); t = dt.datetime.strptime(f[0], "%Y.%m.%d %H:%M")
    bars.append((srv_to_ny(t), float(f[1]), float(f[2]), float(f[3]), float(f[4])))
# H1 EMA200 on NY-hour buckets (close of each hour), known only after the hour closes
h1 = collections.OrderedDict()
for b in bars:
    k = b[0].replace(minute=0); h1[k] = b[4]
ema = {}; e = None; a = 2 / 201
for k, c in h1.items():
    e = c if e is None else e + a * (c - e); ema[k] = e
def ema_before(t):  # last completed hour strictly before t's hour
    k = t.replace(minute=0) - dt.timedelta(hours=1)
    for _ in range(80):
        if k in ema: return ema[k]
        k -= dt.timedelta(hours=1)
    return None
days = collections.defaultdict(list)
for b in bars:
    if b[0].weekday() < 5 and dt.time(9, 30) <= b[0].time() < dt.time(16, 0): days[b[0].date()].append(b)
COST = 0.00002   # 0.2 pip round trip
def m5(bs):
    out = collections.OrderedDict()
    for b in bs:
        k = b[0].replace(minute=b[0].minute - b[0].minute % 5)
        if k not in out: out[k] = [k, b[1], b[2], b[3], b[4]]
        else: o = out[k]; o[2] = max(o[2], b[2]); o[3] = min(o[3], b[3]); o[4] = b[4]
    return list(out.values())
def walk(m1, start_t, d, entry, sl, tp_list):
    # returns dict tpR -> R outcome (SL first if same bar), flat at 16:00
    risk = abs(entry - sl); res = {}
    for R in tp_list:
        tp = entry + d * R * risk; out = None
        for b in m1:
            if b[0] < start_t: continue
            hitsl = b[3] <= sl if d > 0 else b[2] >= sl
            hittp = b[2] >= tp if d > 0 else b[3] <= tp
            if hitsl: out = -1.0; break
            if hittp: out = R; break
        if out is None: out = d * (m1[-1][4] - entry) / risk
        res[R] = out - COST / risk
    return res
TPS = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
stats = collections.defaultdict(lambda: collections.defaultdict(list))
for day, m1 in sorted(days.items()):
    if len(m1) < 300: continue
    yr = "2026" if day >= CUT.date() else ("2025-26" if day >= dt.date(2025, 3, 10) else ("2024-25" if day >= dt.date(2024, 3, 11) else None))
    if not yr: continue
    rng = [b for b in m1 if b[0].time() < dt.time(9, 45)]
    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); mid = (hi + lo) / 2
    bars5 = [b for b in m5(m1) if b[0].time() >= dt.time(9, 45)]
    for trend in (True, False):
        brk = None
        for i, b in enumerate(bars5):
            if b[0].time() >= dt.time(12, 0): break
            d = 1 if b[4] > hi else (-1 if b[4] < lo else 0)
            if not d: continue
            if trend:
                em = ema_before(b[0] + dt.timedelta(minutes=5))
                if em is None or (d > 0 and b[4] <= em) or (d < 0 and b[4] >= em): continue
            brk = (i, d); break
        if not brk: continue
        i, d = brk; bb = bars5[i]; edge = hi if d > 0 else lo; opp = lo if d > 0 else hi
        after = bars5[i + 1:]
        tag = ("trend" if trend else "all") + "|" + yr
        # E1: market at breakout close, SL mid / opposite edge
        t_in = bb[0] + dt.timedelta(minutes=5)
        for sln, sl in (("mid", mid), ("opp", opp)):
            if (bb[4] - sl) * d > 0: stats["E1 break-close SL=" + sln][tag].append(walk(m1, t_in, d, bb[4], sl, TPS))
        # E2: limit at the broken edge (retest touch) before 12:00
        for b in after:
            if b[0].time() >= dt.time(12, 0): break
            if (d > 0 and b[3] <= edge) or (d < 0 and b[2] >= edge):
                for sln, sl in (("mid", mid), ("opp", opp)):
                    stats["E2 retest-limit SL=" + sln][tag].append(walk(m1, b[0], d, edge, sl, TPS))
                break
        # E3: retest bar that touches the edge and CLOSES back beyond it -> market at its close; SL beyond that bar / mid
        for j, b in enumerate(after):
            if b[0].time() >= dt.time(12, 0): break
            touched = (d > 0 and b[3] <= edge) or (d < 0 and b[2] >= edge)
            if touched and ((d > 0 and b[4] > edge) or (d < 0 and b[4] < edge)):
                t2 = b[0] + dt.timedelta(minutes=5)
                for sln, sl in (("bar", b[3] - 0.00002 if d > 0 else b[2] + 0.00002), ("mid", mid)):
                    if (b[4] - sl) * d > 0: stats["E3 retest-confirm SL=" + sln][tag].append(walk(m1, t2, d, b[4], sl, TPS))
                break
            if (d > 0 and b[4] < lo) or (d < 0 and b[4] > hi): break
res = {}
for strat in sorted(stats):
    for tag in sorted(stats[strat]):
        L = stats[strat][tag]; row = {}
        for R in TPS:
            v = [x[R] for x in L]; row[R] = (sum(v), sum(1 for x in v if x > 0) / len(v))
        res[strat + " | " + tag] = (len(L), row)
for k, (n, row) in res.items():
    print(k.ljust(44), "n=%3d" % n, "  ".join("TP%.2g:%+6.1fR/%2.0f%%" % (R, row[R][0], 100 * row[R][1]) for R in TPS))

print("\n==== E2 strict: M1-precise fill, fill bar can only hit SL, buffer on SL ====")
strict = collections.defaultdict(lambda: collections.defaultdict(list))
for day, m1 in sorted(days.items()):
    if len(m1) < 300: continue
    yr = "2026" if day >= CUT.date() else ("2025-26" if day >= dt.date(2025, 3, 10) else ("2024-25" if day >= dt.date(2024, 3, 11) else None))
    if not yr: continue
    rng = [b for b in m1 if b[0].time() < dt.time(9, 45)]
    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); mid = (hi + lo) / 2
    bars5 = [b for b in m5(m1) if b[0].time() >= dt.time(9, 45)]
    for trend in (False, True):
        brk = None
        for b in bars5:
            if b[0].time() >= dt.time(12, 0): break
            d = 1 if b[4] > hi else (-1 if b[4] < lo else 0)
            if not d: continue
            if trend:
                em = ema_before(b[0] + dt.timedelta(minutes=5))
                if em is None or (d > 0 and b[4] <= em) or (d < 0 and b[4] >= em): continue
            brk = (b, d); break
        if not brk: continue
        b, d = brk; edge = hi if d > 0 else lo
        t_arm = b[0] + dt.timedelta(minutes=5)
        fill_i = None
        for k, x in enumerate(m1):
            if x[0] < t_arm: continue
            if x[0].time() >= dt.time(12, 0): break
            if (d > 0 and x[3] <= edge) or (d < 0 and x[2] >= edge): fill_i = k; break
        if fill_i is None: continue
        for buf in (0.0, 0.00005):
            sl = mid - buf if d > 0 else mid + buf
            risk = abs(edge - sl)
            for R in (0.5, 0.75, 1.0, 1.5, 2.0):
                tp = edge + d * R * risk; out = None
                for k in range(fill_i, len(m1)):
                    x = m1[k]
                    if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl): out = -1.0; break
                    if k > fill_i and ((d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp)): out = R; break
                if out is None: out = d * (m1[-1][4] - edge) / risk
                strict[("trend" if trend else "all") + " buf%.1fpip" % (buf * 10000)][(yr, R)].append(out - COST / risk)
for key in sorted(strict):
    for yr in ("2024-25", "2025-26", "2026"):
        row = []
        for R in (0.5, 0.75, 1.0, 1.5, 2.0):
            v = strict[key][(yr, R)]
            if v: row.append("TP%.2g:%+6.1fR/%2.0f%%" % (R, sum(v), 100 * sum(1 for z in v if z > 0) / len(v)))
        n = len(strict[key][(yr, 1.0)])
        print(key.ljust(18), yr, "n=%3d" % n, "  ".join(row))

print("\n==== Demand zone: blind limit (current EA) vs confirmation close (Pat-style), strict M1 ====")
dz = collections.defaultdict(lambda: collections.defaultdict(list))
PIP = 0.0001
def outcome(m1, start_k, d, entry, sl, R, fill_bar_sl_only):
    risk = abs(entry - sl); tp = entry + d * R * risk
    for k in range(start_k, len(m1)):
        x = m1[k]
        if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl): return -1.0 - COST / risk
        if (k > start_k or not fill_bar_sl_only) and ((d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp)): return R - COST / risk
    return d * (m1[-1][4] - entry) / risk - COST / risk
for day, m1 in sorted(days.items()):
    if len(m1) < 300: continue
    yr = "2026" if day >= CUT.date() else ("2025-26" if day >= dt.date(2025, 3, 10) else ("2024-25" if day >= dt.date(2024, 3, 11) else None))
    if not yr: continue
    rng = [b for b in m1 if b[0].time() < dt.time(9, 45)]
    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); mid = (hi + lo) / 2
    all5 = m5(m1)
    bars5 = [b for b in all5 if b[0].time() >= dt.time(9, 45)]
    for trend in (False, True):
        brk = None
        for b in bars5:
            if b[0].time() >= dt.time(12, 0): break
            d = 1 if b[4] > hi else (-1 if b[4] < lo else 0)
            if not d: continue
            if trend:
                em = ema_before(b[0] + dt.timedelta(minutes=5))
                if em is None or (d > 0 and b[4] <= em) or (d < 0 and b[4] >= em): continue
            brk = (b, d); break
        if not brk: continue
        bb, d = brk
        leg = [x for x in all5 if x[0] <= bb[0]]
        ext_i = min(range(len(leg)), key=lambda i: leg[i][3]) if d > 0 else max(range(len(leg)), key=lambda i: leg[i][2])
        base_i = ext_i
        for i in range(ext_i, max(ext_i - 6, -1), -1):
            x = leg[i]
            if (d > 0 and x[4] < x[1]) or (d < 0 and x[4] > x[1]): base_i = i; break
        bx = leg[base_i]; ex = leg[ext_i]
        if d > 0: ztop = max(bx[1], bx[4]); zbot = min(bx[3], ex[3])
        else:     zbot = min(bx[1], bx[4]); ztop = max(bx[2], ex[2])
        if d > 0 and ztop > mid: continue
        if d < 0 and zbot < mid: continue
        entry_edge = ztop if d > 0 else zbot
        sl = (zbot - 2 * PIP) if d > 0 else (ztop + 2 * PIP)          # SL beyond the zone
        sl_rng = (min(lo, zbot) - 2 * PIP) if d > 0 else (max(hi, ztop) + 2 * PIP)
        t_arm = bb[0] + dt.timedelta(minutes=5)
        tag = ("trend" if trend else "all")
        # A) blind limit at zone edge (current EA idea), SL beyond range
        for k, x in enumerate(m1):
            if x[0] < t_arm: continue
            if x[0].time() >= dt.time(12, 0): break
            if (d > 0 and x[3] <= entry_edge) or (d < 0 and x[2] >= entry_edge):
                for R in (1.0, 1.5, 2.0, 3.0): dz["A blind-limit SL=range " + tag][(yr, R)].append(outcome(m1, k, d, entry_edge, sl_rng, R, True))
                break
        # B) confirmation: price trades into the zone, then an M5 bar CLOSES back beyond the zone edge -> enter at that close
        touched = False
        for x in bars5:
            if x[0] < t_arm: continue
            if x[0].time() >= dt.time(12, 0): break
            if (d > 0 and x[4] < zbot) or (d < 0 and x[4] > ztop): break   # zone broken on a close -> no trade
            if (d > 0 and x[3] <= ztop) or (d < 0 and x[2] >= zbot): touched = True
            if touched and ((d > 0 and x[4] > ztop and x[4] > x[1]) or (d < 0 and x[4] < zbot and x[4] < x[1])):
                t_in = x[0] + dt.timedelta(minutes=5)
                k = next((i for i, y in enumerate(m1) if y[0] >= t_in), None)
                if k is None: break
                e = m1[k][1]
                for nm, s in (("zone", sl), ("range", sl_rng)):
                    if (e - s) * d <= 0: continue
                    for R in (1.0, 1.5, 2.0, 3.0): dz["B confirm SL=" + nm + " " + tag][(yr, R)].append(outcome(m1, k, d, e, s, R, False))
                break
for key in sorted(dz):
    for yr in ("2024-25", "2025-26", "2026"):
        row = []
        for R in (1.0, 1.5, 2.0, 3.0):
            v = dz[key][(yr, R)]
            if v: row.append("TP%.2g:%+6.1fR/%2.0f%%" % (R, sum(v), 100 * sum(1 for z in v if z > 0) / len(v)))
        print(key.ljust(26), yr, "n=%3d" % len(dz[key][(yr, 1.0)]), "  ".join(row))
