import os, sys, bisect, datetime as dt, collections
SYM = sys.argv[1] if len(sys.argv) > 1 else "EURUSD"
FILES = {"EURUSD": "eurusd_m1_2024_2026.csv", "XAUUSD": "xauusd_m1_2024_2026.csv", "NAS100": "nas100_m1_2024_2026.csv"}
COST = {"EURUSD": 0.00002, "XAUUSD": 0.55, "NAS100": 1.5}[SYM]
VAL = {"EURUSD": 1000.0, "XAUUSD": 1.0, "NAS100": 0.1}[SYM]   # $ per 1.0 price move at 0.01 lot
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
def run(sess_start, range_min=55, window_min=10, slx=2.2, tpx=0.75, days_ok=(0, 1, 2, 3, 4), label=""):
    res = collections.defaultdict(list)
    day = bars[0][0].date(); last = bars[-1][0].date(); busy_until = None
    while day <= last:
        if day.weekday() in days_ok:
            st = dt.datetime.combine(day, sess_start)
            yr = "2026" if st >= CUT else ("2025-26" if st >= dt.datetime(2025, 3, 10) else ("2024-25" if st >= dt.datetime(2024, 3, 11) else None))
            if yr and (busy_until is None or busy_until <= st):
                i0 = bisect.bisect_left(T, st); i1 = bisect.bisect_left(T, st + dt.timedelta(minutes=range_min))
                i2 = bisect.bisect_left(T, st + dt.timedelta(minutes=range_min + window_min))
                rng = bars[i0:i1]
                if len(rng) >= range_min * 0.6:
                    hi = max(b[2] for b in rng); lo = min(b[3] for b in rng); size = hi - lo
                    for k in range(i1, i2):
                        b = bars[k]; up = b[2] >= hi; dn = b[3] <= lo
                        if not (up or dn): continue
                        if up and dn: break                      # ambiguous bar: skip the day
                        d = 1 if up else -1
                        e = max(hi, b[1]) if d > 0 else min(lo, b[1])
                        sl = e - d * slx * size; tp = e + d * tpx * slx * size
                        out = None
                        for q in range(k, min(k + 60 * 24 * 20, len(bars))):
                            x = bars[q]
                            if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl): out = sl; break
                            if q > k and ((d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp)): out = tp; break
                        if out is None: break
                        busy_until = bars[q][0]
                        pnl = (d * (out - e) - COST) * VAL
                        res[yr].append((pnl, (d * (out - e) - COST) / (slx * size)))
                        break
        day += dt.timedelta(days=1)
    for yr in ("2024-25", "2025-26", "2026"):
        v = res[yr]
        if v:
            gp = sum(p for p, _ in v if p > 0); gl = -sum(p for p, _ in v if p < 0)
            print(SYM, label.ljust(26), yr, "n=%3d" % len(v), "net $%7.2f" % sum(p for p, _ in v), "PF %.2f" % (gp / gl if gl else 0), "R %+6.1f" % sum(r for _, r in v), "win %2.0f%%" % (100 * sum(1 for p, _ in v if p > 0) / len(v)))
run(dt.time(9, 30), label="NYSE 55m/10m (TWP set)")
if SYM == "EURUSD":
    run(dt.time(3, 0), label="London 55m/10m")
    run(dt.time(20, 0), days_ok=(6, 0, 1, 2, 3), label="Asia 55m/10m")
    run(dt.time(8, 0), label="NY 08:00 55m/10m")
