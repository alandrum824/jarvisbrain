import os, sys, bisect, datetime as dt, collections
SYM = sys.argv[1]
FILES = {"EURUSD": "eurusd_m1_2024_2026.csv", "XAUUSD": "xauusd_m1_2024_2026.csv", "NAS100": "nas100_m1_2024_2026.csv"}
COST, BUF = {"EURUSD": (0.00002, 0.00002), "XAUUSD": (0.55, 0.30), "NAS100": (1.5, 1.0)}[SYM]
CUT = dt.datetime(2026, 3, 7)
def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))
def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5
def srv_to_ny(t): return t + dt.timedelta(hours=ny_off(t)) if t < CUT else t - dt.timedelta(hours=7)
bars = []
for l in open(os.path.join(os.environ["TEMP"], FILES[SYM])).read().splitlines()[1:]:
    f = l.split(","); t = dt.datetime.strptime(f[0], "%Y.%m.%d %H:%M")
    bars.append((srv_to_ny(t), float(f[1]), float(f[2]), float(f[3]), float(f[4])))
bars.sort(); T = [b[0] for b in bars]
fri = collections.Counter(b[0].strftime("%H:%M") for i, b in enumerate(bars[:-1]) if b[0].weekday() == 4 and bars[i + 1][0] - b[0] > dt.timedelta(hours=24))
print(SYM, "Friday last-bar NY:", fri.most_common(3))
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
SESS = {"Asia": dt.time(20, 0), "London": dt.time(3, 0), "NY": dt.time(9, 30)}
TPS = (1.0, 1.5, 2.0, 3.0)
S = collections.defaultdict(lambda: collections.defaultdict(list)); FUN = collections.Counter()
d0, d1 = bars[0][0].date(), bars[-1][0].date()
day = d0
while day <= d1:
    for sn, st in SESS.items():
        wd = day.weekday()
        if (sn == "Asia" and wd not in (6, 0, 1, 2, 3)) or (sn != "Asia" and wd > 4): continue
        start = dt.datetime.combine(day, st)
        yr = "2026" if start >= CUT else ("2025-26" if start >= dt.datetime(2025, 3, 10) else ("2024-25" if start >= dt.datetime(2024, 3, 11) else None))
        if not yr: continue
        i0 = bisect.bisect_left(T, start); i1 = bisect.bisect_left(T, start + dt.timedelta(hours=6, minutes=30))
        m1 = bars[i0:i1]
        rng = [b for b in m1 if b[0] < start + dt.timedelta(minutes=15)]
        if len(rng) < 10 or len(m1) < 200: continue
        hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); size = hi - lo
        if size <= 0: continue
        all5 = m5(m1); cut = start + dt.timedelta(hours=2, minutes=30)
        b5 = [b for b in all5 if start + dt.timedelta(minutes=15) <= b[0] < cut]
        brk = next(((i, 1 if b[4] > hi else -1) for i, b in enumerate(b5) if b[4] > hi or b[4] < lo), None)
        if not brk: continue
        i, d = brk; edge = hi if d > 0 else lo; ext = edge + d * 0.7 * size
        ext_j = None
        for j in range(i, len(b5)):
            b = b5[j]
            if (d > 0 and b[4] < lo) or (d < 0 and b[4] > hi): break
            if (d > 0 and b[2] >= ext) or (d < 0 and b[3] <= ext): ext_j = j; break
        FUN[sn + " " + yr + " break"] += 1
        if ext_j is None: continue
        FUN[sn + " " + yr + " displaced"] += 1
        leg = [x for x in all5 if x[0] <= b5[ext_j][0]]
        levels = []
        for k in range(1, len(leg) - 1):   # FVG near the edge
            if d > 0 and leg[k + 1][3] > leg[k - 1][2] and leg[k + 1][3] >= edge - 0.25 * size: levels.append(("FVG", leg[k + 1][3], leg[k - 1][2])); break
            if d < 0 and leg[k + 1][2] < leg[k - 1][3] and leg[k + 1][2] <= edge + 0.25 * size: levels.append(("FVG", leg[k + 1][2], leg[k - 1][3])); break
        ei = min(range(len(leg)), key=lambda q: leg[q][3]) if d > 0 else max(range(len(leg)), key=lambda q: leg[q][2])
        bi = ei
        for q in range(ei, max(ei - 6, -1), -1):
            x = leg[q]
            if (d > 0 and x[4] < x[1]) or (d < 0 and x[4] > x[1]): bi = q; break
        bx, ex = leg[bi], leg[ei]
        if d > 0: levels.append(("DEM", max(bx[1], bx[4]), min(bx[3], ex[3])))   # (name, touch edge, far edge)
        else:     levels.append(("DEM", min(bx[1], bx[4]), max(bx[2], ex[2])))
        after5 = [x for x in all5 if b5[ext_j][0] < x[0] < cut]
        for name, near, far in levels + [("ANY", None, None)]:
            lv = levels if name == "ANY" else [(name, near, far)]
            touched = set(); done = False
            for q in range(1, len(after5)):
                x, pv = after5[q], after5[q - 1]
                for (ln, n_, f_) in lv:
                    if (d > 0 and x[3] <= n_) or (d < 0 and x[2] >= n_): touched.add(ln)
                deepest_far = min(f_ for _, _, f_ in lv) if d > 0 else max(f_ for _, _, f_ in lv)
                if (d > 0 and x[4] < deepest_far) or (d < 0 and x[4] > deepest_far): break
                eng = (d > 0 and pv[4] < pv[1] and x[4] > x[1] and x[4] >= pv[1] and x[1] <= pv[4]) or \
                      (d < 0 and pv[4] > pv[1] and x[4] < x[1] and x[4] <= pv[1] and x[1] >= pv[4])
                if touched and eng:
                    t_in = x[0] + dt.timedelta(minutes=5); k = bisect.bisect_left([y[0] for y in m1], t_in)
                    if k >= len(m1): break
                    e = m1[k][1]
                    lvl_far = [f_ for (ln, _, f_) in lv if ln in touched]
                    sl = (min([x[3], pv[3]] + lvl_far) - BUF) if d > 0 else (max([x[2], pv[2]] + lvl_far) + BUF)
                    if (e - sl) * d > 0:
                        for R in TPS: S[sn + " " + name + "+engulf"][(yr, R)].append(outcome(m1, k, d, e, sl, R))
                    break
    day += dt.timedelta(days=1)
for key in sorted(S):
    for yr in ("2024-25", "2025-26", "2026"):
        row = []
        for R in TPS:
            v = S[key][(yr, R)]
            if v: row.append("TP%.2g:%+6.1fR/%2.0f%%" % (R, sum(v), 100 * sum(1 for z in v if z > 0) / len(v)))
        print(SYM, key.ljust(20), yr, "n=%3d" % len(S[key][(yr, 1.0)]), "  ".join(row))
print(SYM, "funnel", dict(sorted(FUN.items())))
