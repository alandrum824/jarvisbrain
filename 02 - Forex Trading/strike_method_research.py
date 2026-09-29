# STRIKE method (Abdo Karim): 4H S/R -> touch at NY session -> M5 wick rejection -> higher low / lower high -> BOS entry
import os, sys, bisect, datetime as dt, collections
_src = open(os.path.join(os.environ["TEMP"], "claude_flip_research.py")).read().split("def daily(")[0]
exec(_src)   # load(), srv_to_ny incl. the London-time era, SPEC
SPEC.update({"NAS100": 1.5})
BUF = {"EURUSD": 0.00005, "XAUUSD": 0.30, "NAS100": 2.0}


def agg(bars, minutes, anchor_min=0):
    out = collections.OrderedDict()
    for b in bars:
        t = b[0]
        tod = t.hour * 60 + t.minute
        k = dt.datetime.combine(t.date(), dt.time(0)) + dt.timedelta(minutes=((tod - anchor_min) // minutes) * minutes + anchor_min)
        if k not in out:
            out[k] = [k, b[1], b[2], b[3], b[4]]
        else:
            o = out[k]; o[2] = max(o[2], b[2]); o[3] = min(o[3], b[3]); o[4] = b[4]
    return list(out.values())


def levels_at(H4, t, K=2, lookback_days=30):
    lv = []
    for i in range(K, len(H4) - K):
        if H4[i + K][0] + dt.timedelta(hours=4) > t:
            break
        if H4[i][0] < t - dt.timedelta(days=lookback_days):
            continue
        if all(H4[i][2] > H4[i + z][2] and H4[i][2] > H4[i - z][2] for z in range(1, K + 1)):
            lv.append(H4[i][2])
        if all(H4[i][3] < H4[i + z][3] and H4[i][3] < H4[i - z][3] for z in range(1, K + 1)):
            lv.append(H4[i][3])
    return sorted(set(lv))


def run(sym, bars, minRR=3.0, tol_frac=0.15, start=dt.time(9, 0), end_entry=dt.time(12, 0), flat=dt.time(16, 0),
        hold_overnight=False, reqRR=True, tpR=None):
    T = [b[0] for b in bars]; cost = SPEC[sym]; buf = BUF[sym]
    H4 = agg(bars, 240, anchor_min=120)          # 4H blocks 18:00, 22:00, 02:00 ... NY time
    H4T = [h[0] for h in H4]
    res = collections.defaultdict(list); funnel = collections.Counter()
    days = sorted(set(b[0].date() for b in bars if b[0].weekday() < 5))
    for day in days:
        st = dt.datetime.combine(day, start); en = dt.datetime.combine(day, end_entry); fl = dt.datetime.combine(day, flat)
        j = bisect.bisect_left(H4T, st)
        if j < 60:
            continue
        rngs = [h[2] - h[3] for h in H4[j - 30:j]]; tol = tol_frac * sum(rngs) / len(rngs)
        lv = levels_at(H4[max(0, j - 200):j], st)
        if not lv:
            continue
        i0 = bisect.bisect_left(T, st); i1 = bisect.bisect_left(T, fl)
        if i1 - i0 < 100:
            continue
        m5 = agg(bars[i0:i1], 5)
        funnel["days"] += 1
        state = None; trade = None
        for q in range(2, len(m5)):
            b = m5[q]
            if state is None:
                if b[0] >= en:
                    break
                for L in lv:
                    body_lo, body_hi = min(b[1], b[4]), max(b[1], b[4]); rngb = b[2] - b[3]
                    if rngb <= 0:
                        continue
                    if b[3] <= L + tol and b[3] >= L - 3 * tol and b[4] > L and body_lo - b[3] > 0.5 * rngb:
                        state = dict(d=1, L=L, ext=b[3], q=q); funnel["touch+reject"] += 1; break
                    if b[2] >= L - tol and b[2] <= L + 3 * tol and b[4] < L and b[2] - body_hi > 0.5 * rngb:
                        state = dict(d=-1, L=L, ext=b[2], q=q); funnel["touch+reject"] += 1; break
                continue
            d = state["d"]
            if q - state["q"] > 24 or b[0] >= en:
                state = None; continue
            if (d > 0 and b[4] < state["L"] - tol) or (d < 0 and b[4] > state["L"] + tol):
                state = None; continue
            p, pp = m5[q - 1], m5[q - 2]
            if "sw" not in state and q - 1 > state["q"]:
                if d > 0 and p[3] < pp[3] and p[3] < b[3] and p[3] > state["ext"]:
                    state["sw"] = p[3]; state["bos"] = max(x[2] for x in m5[state["q"]:q]); funnel["HL/LH"] += 1
                if d < 0 and p[2] > pp[2] and p[2] > b[2] and p[2] < state["ext"]:
                    state["sw"] = p[2]; state["bos"] = min(x[3] for x in m5[state["q"]:q]); funnel["HL/LH"] += 1
            if "sw" in state and ((d > 0 and b[4] > state["bos"]) or (d < 0 and b[4] < state["bos"])):
                k = bisect.bisect_left(T, b[0] + dt.timedelta(minutes=5))
                if k >= len(T):
                    break
                e = bars[k][1]; sl = state["sw"] - d * buf; risk = d * (e - sl)
                nxt = [x for x in lv if x > e + tol] if d > 0 else [x for x in lv if x < e - tol]
                tp = e + d * tpR * risk if tpR else (nxt[0] if d > 0 and nxt else (nxt[-1] if nxt else None))
                if risk <= 0 or tp is None:
                    state = None; continue
                rr = d * (tp - e) / risk
                if reqRR and rr < minRR:
                    funnel["rr<3 skip"] += 1; state = None; continue
                trade = (k, d, e, sl, tp, risk); break
        if trade is None:
            continue
        k, d, e, sl, tp, risk = trade
        funnel["trades"] += 1
        stop_at = min(len(bars), k + 60 * 24 * 10) if hold_overnight else i1
        out = None
        for kk in range(k, stop_at):
            x = bars[kk]
            if (d > 0 and x[3] <= sl) or (d < 0 and x[2] >= sl):
                out = sl; break
            if (d > 0 and x[2] >= tp) or (d < 0 and x[3] <= tp):
                out = tp; break
        if out is None:
            out = bars[stop_at - 1][4]
        res[day.year].append((d * (out - e) - cost) / risk)
    return res, funnel


def report(name, r):
    yrs = sorted(r); allv = [x for y in yrs for x in r[y]]
    eq = pk = dd = 0
    for x in allv:
        eq += x; pk = max(pk, eq); dd = max(dd, pk - eq)
    wins = [x for x in allv if x > 0]
    print(name.ljust(40), "  ".join("%d:%+5.1fR/n%d" % (y, sum(r[y]), len(r[y])) for y in yrs),
          "| tot %+6.1fR n%d win%2.0f%% avgWin %.1fR DD %.1fR | %d/%d yrs +" % (
              sum(allv), len(allv), 100 * len(wins) / max(1, len(allv)), sum(wins) / max(1, len(wins)), dd,
              sum(1 for y in yrs if sum(r[y]) > 0), len(yrs)), flush=True)


if __name__ == "__main__":
    for s in (sys.argv[1:] or ["NAS100", "XAUUSD", "EURUSD"]):
        bars = load(s)
        r, f = run(s, bars)
        print(s, "funnel", dict(f))
        report(s + " STRIKE as written", r)
        report(s + " hold to TP/SL (no 16:00 flat)", run(s, bars, hold_overnight=True)[0])
        report(s + " no RR filter, TP next 4H", run(s, bars, reqRR=False)[0])
        report(s + " fixed TP 2R", run(s, bars, reqRR=False, tpR=2.0)[0])
        report(s + " fixed TP 3R", run(s, bars, reqRR=False, tpR=3.0)[0])
