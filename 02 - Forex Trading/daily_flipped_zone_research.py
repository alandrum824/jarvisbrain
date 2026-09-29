# Pat "Once You Understand Price Action": daily structure -> BOS -> flipped zone pullback -> buy/sell
import os, sys, datetime as dt, collections, bisect
CUT = dt.datetime(2026, 3, 7)
SPEC = {"EURUSD": 0.00003, "GBPUSD": 0.00005, "USDCAD": 0.00005, "AUDUSD": 0.00004, "USDJPY": 0.005, "XAUUSD": 0.55}
def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))
def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5
def last_sunday(y, m):
    d = dt.datetime(y, m + 1, 1) if m < 12 else dt.datetime(y + 1, 1, 1)
    d -= dt.timedelta(days=1)
    return d - dt.timedelta(days=(d.weekday() + 1) % 7)
LONDON_END = dt.datetime(2022, 3, 27)
def srv_to_ny(t):
    if t < LONDON_END:   # broker ran on London time (UTC+0 / +1 EU DST) before 2022-03-27
        eu = last_sunday(t.year, 3) + dt.timedelta(hours=1) <= t < last_sunday(t.year, 10) + dt.timedelta(hours=1)
        utc = t - dt.timedelta(hours=1 if eu else 0)
        return utc + dt.timedelta(hours=ny_off(utc))
    return t + dt.timedelta(hours=ny_off(t)) if t < CUT else t - dt.timedelta(hours=7)
def load(sym):
    bars = []
    for l in open(os.path.join(os.environ["TEMP"], sym.lower() + "_m1_full.csv")).read().splitlines()[1:]:
        f = l.split(","); t = dt.datetime.strptime(f[0], "%Y.%m.%d %H:%M")
        bars.append((srv_to_ny(t), float(f[1]), float(f[2]), float(f[3]), float(f[4])))
    bars.sort(); return bars
def daily(bars):  # NY 17:00 close
    D = collections.OrderedDict()
    for b in bars:
        k = (b[0] + dt.timedelta(hours=7)).date()
        if k.weekday() >= 5: continue
        if k not in D: D[k] = [k, b[1], b[2], b[3], b[4], None]
        else: o = D[k]; o[2] = max(o[2], b[2]); o[3] = min(o[3], b[3]); o[4] = b[4]
    return list(D.values())
def atr(d, i, n=14):
    tr = [max(d[j][2], d[j - 1][4]) - min(d[j][3], d[j - 1][4]) for j in range(max(1, i - n + 1), i + 1)]
    return sum(tr) / len(tr)
def run(sym, bars, d, K=2, zone_mode="body", entry="limit", sl_mode="zone", tp_mode="2.5R", fib=None, tag=""):
    cost = SPEC[sym]; T = [b[0] for b in bars]; res = collections.defaultdict(list)
    busy_until = None; setups = []
    last_sh = last_sl = None
    for i in range(30, len(d)):
        # confirm swings (pivot at i-K using bars up to i)
        p = i - K
        if all(d[p][2] > d[p + z][2] and d[p][2] > d[p - z][2] for z in range(1, K + 1)): last_sh = p
        if all(d[p][3] < d[p + z][3] and d[p][3] < d[p - z][3] for z in range(1, K + 1)): last_sl = p
        c = d[i][4]; a = atr(d, i)
        for dirn, sw in ((1, last_sh), (-1, last_sl)):
            if sw is None: continue
            lvl = d[sw][2] if dirn > 0 else d[sw][3]
            if (dirn > 0 and c > lvl and d[i - 1][4] <= lvl) or (dirn < 0 and c < lvl and d[i - 1][4] >= lvl):
                # BOS: flipped zone around the broken swing candle
                sc = d[sw]
                if zone_mode == "body": zt, zb = (sc[2], max(sc[1], sc[4])) if dirn > 0 else (min(sc[1], sc[4]), sc[3])
                else: zt, zb = (lvl, lvl - 0.3 * a) if dirn > 0 else (lvl + 0.3 * a, lvl)
                if dirn > 0: near, far = zt, min(zb, zt - 0.1 * a)
                else: near, far = zb, max(zt, zb + 0.1 * a)
                legstart = min(d[j][3] for j in range(sw, i + 1)) if dirn > 0 else max(d[j][2] for j in range(sw, i + 1))
                setups = [s for s in setups if s["dir"] != dirn]      # newest BOS replaces older same-dir setup
                setups = [s for s in setups if s["dir"] == dirn] + [dict(dir=dirn, near=near, far=far, legstart=legstart, ext=d[i][2] if dirn > 0 else d[i][3], born=i, a=a)]
                if dirn > 0: last_sh = None
                else: last_sl = None
        # manage setups on the NEXT day's intraday M1 path
        if i + 1 >= len(d): break
        nxt = d[i + 1][0]
        for s in list(setups):
            s["ext"] = max(s["ext"], d[i][2]) if s["dir"] > 0 else min(s["ext"], d[i][3])
            if i - s["born"] > 20 or (s["dir"] > 0 and c < s["far"]) or (s["dir"] < 0 and c > s["far"]):
                setups.remove(s); continue
            if busy_until and dt.datetime.combine(nxt, dt.time(0)) < busy_until: continue
            if fib:
                leg = abs(s["ext"] - s["legstart"]); depth = abs(s["ext"] - s["near"]) / leg if leg else 0
                if not (fib[0] <= depth <= fib[1]): continue
            dn = s["dir"]
            day_start = dt.datetime.combine(nxt, dt.time(0)) - dt.timedelta(hours=7)
            k0 = bisect.bisect_left(T, day_start); k1 = bisect.bisect_left(T, day_start + dt.timedelta(days=1))
            if entry == "limit":
                kf = next((k for k in range(k0, k1) if (dn > 0 and bars[k][3] <= s["near"]) or (dn < 0 and bars[k][2] >= s["near"])), None)
                if kf is None: continue
                e = s["near"]
            elif entry == "engulf":  # day i is an engulfing candle in trade direction that traded into the zone
                pv = d[i - 1]; cu = d[i]
                touched = (dn > 0 and cu[3] <= s["near"]) or (dn < 0 and cu[2] >= s["near"])
                eng = (dn > 0 and pv[4] < pv[1] and cu[4] > cu[1] and cu[4] >= pv[1] and cu[1] <= pv[4]) or                       (dn < 0 and pv[4] > pv[1] and cu[4] < cu[1] and cu[4] <= pv[1] and cu[1] >= pv[4])
                if not (touched and eng): continue
                kf = k0; e = bars[kf][1]
            else:  # confirm: day i closed back beyond the near edge after trading into the zone -> enter next open
                touched = (dn > 0 and d[i][3] <= s["near"]) or (dn < 0 and d[i][2] >= s["near"])
                held = (dn > 0 and c > s["near"]) or (dn < 0 and c < s["near"])
                if not (touched and held): continue
                kf = k0; e = bars[kf][1]
            sl = s["far"] - dn * 0.1 * s["a"]
            risk = abs(e - sl)
            if risk <= 0 or (e - sl) * dn <= 0: setups.remove(s); continue
            tp = (s["ext"] if tp_mode == "ext" else e + dn * float(tp_mode[:-1]) * risk)
            if (tp - e) * dn <= 0: setups.remove(s); continue
            out = None; q = kf
            while q < len(bars):
                x = bars[q]
                if sl_mode == "close":   # Pat: invalid only on a daily close beyond the zone; hard stop 1 ATR further
                    hard = sl - dn * s["a"]
                    if (dn > 0 and x[3] <= hard) or (dn < 0 and x[2] >= hard): out = hard; break
                    if x[0].hour == 16 and x[0].minute == 59 and ((dn > 0 and x[4] < s["far"]) or (dn < 0 and x[4] > s["far"])): out = x[4]; break
                else:
                    if (dn > 0 and x[3] <= sl) or (dn < 0 and x[2] >= sl): out = sl; break
                if q > kf and ((dn > 0 and x[2] >= tp) or (dn < 0 and x[3] <= tp)): out = tp; break
                q += 1
            if out is None: setups.remove(s); continue
            R = (dn * (out - e) - cost) / risk
            res[bars[kf][0].year].append((R, bars[kf][0], bars[q][0]))
            busy_until = bars[q][0]; setups.remove(s)
    return res
if __name__ == "__main__":
    syms = sys.argv[1:] or list(SPEC)
    data = {s: load(s) for s in syms}
    D = {s: daily(data[s]) for s in syms}
    for s in syms: print(s, "M1", data[s][0][0].date(), "->", data[s][-1][0].date(), "daily bars", len(D[s]))
    variants = [("limit body SLzone 2.5R", {}), ("limit body SLzone TPext", dict(tp_mode="ext")),
                ("limit body SLclose 2.5R", dict(sl_mode="close")), ("confirm body SLzone 2.5R", dict(entry="confirm")),
                ("limit fib50-83 2.5R", dict(fib=(0.5, 0.83))), ("engulf body SLzone 2.5R", dict(entry="engulf")), ("engulf body TPext", dict(entry="engulf", tp_mode="ext")), ("limit atr-zone 2.5R", dict(zone_mode="atr")),
                ("limit K3 2.5R", dict(K=3))]
    for name, kw in variants:
        tot = collections.defaultdict(list)
        for s in syms:
            r = run(s, data[s], D[s], **kw)
            for y, v in r.items(): tot[y] += v
        yrs = sorted(tot)
        row = "  ".join("%d:%+5.1fR/n%d" % (y, sum(x[0] for x in tot[y]), len(tot[y])) for y in yrs)
        allv = [x for y in yrs for x in tot[y]]
        eq = pk = dd = 0
        for R_, _, _ in sorted(allv, key=lambda z: z[2]): eq += R_; pk = max(pk, eq); dd = max(dd, pk - eq)
        pos = sum(1 for y in yrs if sum(x[0] for x in tot[y]) > 0)
        print(name.ljust(26), row, "| total %+6.1fR n%d win%2.0f%% maxDD %.1fR | %d/%d yrs +" % (sum(x[0] for x in allv), len(allv), 100 * sum(1 for x in allv if x[0] > 0) / max(1, len(allv)), dd, pos, len(yrs)))
