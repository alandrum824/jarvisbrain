import os, sys, datetime as dt, collections
SYM = sys.argv[1]
p = os.path.expandvars(r"%TEMP%\eurusd_m1_2024_2026.csv" if SYM == "EURUSD" else r"%TEMP%\xauusd_m1_2024_2026.csv")
CUT = dt.datetime(2026, 3, 7)
COST, BUF = (0.00002, 0.00002) if SYM == "EURUSD" else (0.55, 0.30)
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
h1b = collections.OrderedDict()
for bb_ in bars:
    k = bb_[0].replace(minute=0)
    if k not in h1b: h1b[k] = [k, bb_[2], bb_[3]]
    else: h1b[k][1] = max(h1b[k][1], bb_[2]); h1b[k][2] = min(h1b[k][2], bb_[3])
H = list(h1b.values()); SW = []   # (confirm_time, price)
for q in range(3, len(H) - 3):
    if all(H[q][1] > H[q + z][1] and H[q][1] > H[q - z][1] for z in (1, 2, 3)): SW.append((H[q + 3][0] + dt.timedelta(hours=1), H[q][1]))
    if all(H[q][2] < H[q + z][2] and H[q][2] < H[q - z][2] for z in (1, 2, 3)): SW.append((H[q + 3][0] + dt.timedelta(hours=1), H[q][2]))
DAYHL = collections.OrderedDict()
for bb_ in bars:
    dd = bb_[0].date()
    if dd not in DAYHL: DAYHL[dd] = [bb_[2], bb_[3]]
    else: DAYHL[dd][0] = max(DAYHL[dd][0], bb_[2]); DAYHL[dd][1] = min(DAYHL[dd][1], bb_[3])
DKEYS = list(DAYHL.keys())
def htf_ok(day, d, px):
    if day not in DAYHL: return False
    i = DKEYS.index(day); prev = [DAYHL[k] for k in DKEYS[max(0, i - 20):i]]
    if len(prev) < 15: return False
    H_, L_ = max(x[0] for x in prev), min(x[1] for x in prev)
    pos = (px - L_) / (H_ - L_) if H_ > L_ else 0.5
    return pos <= 0.25 if d > 0 else pos >= 0.75
def near_level(day, price, tol):
    t0 = dt.datetime.combine(day, dt.time(9, 30)); lo_t = t0 - dt.timedelta(days=7)
    return any(lo_t <= ct <= t0 and abs(pr - price) <= tol for ct, pr in SW)
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
def outcome(m1, k0, d, entry, sl, tp, fill_sl_only):
    risk = abs(entry - sl)
    for k in range(k0, len(m1)):
        x = m1[k]
        if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl): return -1.0 - COST / risk
        if (k > k0 or not fill_sl_only) and ((d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp)): return abs(tp - entry) / risk - COST / risk
    return d * (m1[-1][4] - entry) / risk - COST / risk
TPS = (1.0, 1.5, 2.0, 3.0, "ext")
CURD = [0]
def SRX(day, lvl, size, name, yr, R, val):
    S[name][(yr, R)].append(val)
    if htf_ok(day, CURD[0], lvl): S[name + " +HTFloc"][(yr, R)].append(val)
    if near_level(day, lvl, 0.2 * size): S[name + " +S/R"][(yr, R)].append(val)

S = collections.defaultdict(lambda: collections.defaultdict(list)); funnel = collections.Counter()
for day, m1 in sorted(days.items()):
    if len(m1) < 300: continue
    yr = "2026" if day >= CUT.date() else ("2025-26" if day >= dt.date(2025, 3, 10) else ("2024-25" if day >= dt.date(2024, 3, 11) else None))
    if not yr: continue
    rng = [b for b in m1 if b[0].time() < dt.time(9, 45)]
    if len(rng) < 10: continue
    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); size = hi - lo
    if size <= 0: continue
    all5 = m5(m1); b5 = [b for b in all5 if dt.time(9, 45) <= b[0].time() < dt.time(12, 0)]
    brk = next(((i, 1 if b[4] > hi else -1) for i, b in enumerate(b5) if b[4] > hi or b[4] < lo), None)
    if not brk: continue
    funnel[yr + " break"] += 1
    i, d = brk; CURD[0] = d; edge = hi if d > 0 else lo; target_ext = edge + d * 0.7 * size
    # extension must be reached before any close back through the far side
    ext_j = None; extreme = None
    for j in range(i, len(b5)):
        b = b5[j]
        if (d > 0 and b[4] < lo) or (d < 0 and b[4] > hi): break
        if (d > 0 and b[2] >= target_ext) or (d < 0 and b[3] <= target_ext): ext_j = j; break
    if ext_j is None: continue
    funnel[yr + " ext70"] += 1
    # FVG inside the impulse (range start .. extension bar): first gap beyond/near the edge
    leg = [x for x in all5 if x[0] <= b5[ext_j][0]]
    fvg = None
    for k in range(1, len(leg) - 1):
        if d > 0 and leg[k + 1][3] > leg[k - 1][2] and leg[k + 1][3] >= edge - 0.25 * size: fvg = (leg[k - 1][2], leg[k + 1][3]); break
        if d < 0 and leg[k + 1][2] < leg[k - 1][3] and leg[k + 1][2] <= edge + 0.25 * size: fvg = (leg[k + 1][2], leg[k - 1][3]); break
    ext_high = max(x[2] for x in leg if x[0] >= b5[i][0]) if d > 0 else min(x[3] for x in leg if x[0] >= b5[i][0])
    t_arm = b5[ext_j][0] + dt.timedelta(minutes=5)
    after5 = [x for x in all5 if t_arm <= x[0] < dt.datetime.combine(day, dt.time(12, 0))]
    if fvg:
        funnel[yr + " fvg"] += 1
        fb, ft = fvg
        top = ft if d > 0 else fb; bot = fb if d > 0 else ft      # 'top' = first touch side
        sl = (bot - BUF) if d > 0 else (bot + BUF)
        # V1 blind limit at the FVG edge
        for k, x in enumerate(m1):
            if x[0] < t_arm or x[0].time() >= dt.time(12, 0): continue
            if (d > 0 and x[3] <= top) or (d < 0 and x[2] >= top):
                r = abs(top - sl)
                for R in TPS:
                    tp = ext_high if R == "ext" else top + d * R * r
                    if (tp - top) * d > 0: SRX(day, top, size, "F1 FVG limit", yr, R, outcome(m1, k, d, top, sl, tp, True))
                break
        # V2 hold confirmation: touches the FVG, M5 closes back beyond its outer edge -> market
        touched = False
        for x in after5:
            if (d > 0 and x[4] < bot) or (d < 0 and x[4] > bot): break
            if (d > 0 and x[3] <= top) or (d < 0 and x[2] >= top): touched = True
            if touched and ((d > 0 and x[4] > top and x[4] > x[1]) or (d < 0 and x[4] < top and x[4] < x[1])):
                t_in = x[0] + dt.timedelta(minutes=5); k = next((q for q, y in enumerate(m1) if y[0] >= t_in), None)
                if k is None: break
                e = m1[k][1]; s2 = (min(bot, x[3]) - BUF) if d > 0 else (max(bot, x[2]) + BUF)
                if (e - s2) * d > 0:
                    for R in TPS:
                        tp = ext_high if R == "ext" else e + d * R * abs(e - s2)
                        if (tp - e) * d > 0: SRX(day, top, size, "F2 FVG hold-confirm", yr, R, outcome(m1, k, d, e, s2, tp, False))
                break
    # DEMAND leg (base of the impulse), Pat's frames: holds in demand + confirmation -> long, tight SL under demand, TP = extension high
    ext_i = min(range(len(leg)), key=lambda q: leg[q][3]) if d > 0 else max(range(len(leg)), key=lambda q: leg[q][2])
    base_i = ext_i
    for q in range(ext_i, max(ext_i - 6, -1), -1):
        x = leg[q]
        if (d > 0 and x[4] < x[1]) or (d < 0 and x[4] > x[1]): base_i = q; break
    bx, ex = leg[base_i], leg[ext_i]
    if d > 0: ztop, zbot = max(bx[1], bx[4]), min(bx[3], ex[3])
    else:     zbot, ztop = min(bx[1], bx[4]), max(bx[2], ex[2])
    dtop = ztop if d > 0 else zbot; dbot = zbot if d > 0 else ztop
    dsl = (dbot - BUF) if d > 0 else (dbot + BUF)
    funnel[yr + " demand-defined"] += 1
    for k, x in enumerate(m1):   # D1 blind limit at the demand edge
        if x[0] < t_arm or x[0].time() >= dt.time(12, 0): continue
        if (d > 0 and x[3] <= dtop) or (d < 0 and x[2] >= dtop):
            for R in TPS:
                tp = ext_high if R == "ext" else dtop + d * R * abs(dtop - dsl)
                if (tp - dtop) * d > 0: SRX(day, dtop, size, "D1 demand limit", yr, R, outcome(m1, k, d, dtop, dsl, tp, True))
            break
    touched = False
    for x in after5:              # D2 holds in demand + M5 close back out of it
        if (d > 0 and x[4] < dbot) or (d < 0 and x[4] > dbot): break
        if (d > 0 and x[3] <= dtop) or (d < 0 and x[2] >= dtop): touched = True
        if touched and ((d > 0 and x[4] > dtop and x[4] > x[1]) or (d < 0 and x[4] < dtop and x[4] < x[1])):
            t_in = x[0] + dt.timedelta(minutes=5); k = next((q for q, y in enumerate(m1) if y[0] >= t_in), None)
            if k is None: break
            e = m1[k][1]
            if (e - dsl) * d > 0:
                for R in TPS:
                    tp = ext_high if R == "ext" else e + d * R * abs(e - dsl)
                    if (tp - e) * d > 0: SRX(day, dtop, size, "D2 demand hold-confirm", yr, R, outcome(m1, k, d, e, dsl, tp, False))
            break
for key in sorted(S):
    for yr in ("2024-25", "2025-26", "2026"):
        row = []
        for R in TPS:
            v = S[key][(yr, R)]
            if v: row.append(("TP%s" % R).ljust(6) + ":%+6.1fR/%2.0f%%" % (sum(v), 100 * sum(1 for z in v if z > 0) / len(v)))
        print(SYM, key.ljust(20), yr, "n=%3d" % len(S[key][(yr, 1.0)]), "  ".join(row))
print(SYM, "funnel:", dict(sorted(funnel.items())))
