"""TWI Gold Zone Ladder: offline research + random-zone control. READ-ONLY (bars only, no orders).

Setup (pre-declared, not tuned): the TWI EQ Liquidity OB v10 trigger on gold M5.
  A swing high/low (3/3 pivots) is either EQUAL to a prior swing (<= 0.15 ATR) or SWEEPS it (0.05..2 ATR and closes back),
  -> a close breaks the swing between them (BOS / CHoCH) within 40 bars
  -> the ADVANCE block (last opposite candle before the break) is the entry zone, the top block / sweep candle is the stop area
  -> price returns into the advance block and an M5 candle closes back out of it in the trade direction (rejection)
  -> market order at the next M5 open (long at ask, short at bid). SL beyond the top block + 0.1 ATR.
Management ("ladder", GenWealth-style TP1/TP2/TP3), resolved on M1 with the bar spread (+6 pts live markup):
  LADDER: 50% at 1R -> stop to entry, 25% at 2R, 25% at 3R.   FIXED2R: all at 2R (baseline).
  Max hold 24 h (closed at market). One trade at a time. Mon-Fri. Daily cap: no new trade after -3R realised that day.
  Same-bar ties count the stop first; after TP1 the breakeven check starts on the TP1 bar itself (pessimistic).
Fixes vs last night's research: a trade that comes back to entry after TP1 is CLOSED there (the old script still
credited it with TP2 if price later got there); costs use the real bar spread, not a flat 0.35.

Controls:
  TWIN  = identical setups, but at the BOS the whole zone (advance block, top block, equal level) is shifted so the
          advance block sits at a random distance from price drawn from the real zones' own distance pool (ATR units).
  RANDOM TIME = entries at random M5 bars, same direction mix, same stop distance in ATR, same management.
Data: C:/Users/aland/stg/obh/XAUUSD_M1.csv (TWIBarsExportTester, AAAFx, 2020-01-02 -> 2026-10-09).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe zone_ladder_research.py [SEEDS]
"""
import sys, os
import numpy as np, pandas as pd

DATA = r"C:\Users\aland\stg\obh"
SYM, PT, MARKUP = "XAUUSD", 0.01, 6
SEEDS = int(sys.argv[1]) if len(sys.argv) > 1 else 30
P = dict(piv=3, eqTol=0.15, minGap=3, maxGap=60, minDip=0.5, beyond=0.05, bosMax=40, obMax=1.5, retestMax=120,
         invAccept=2, invBuf=0.10, stopBuf=0.10, minRisk=0.15, maxRisk=4.0, sweepMax=2.0)
MAXHOLD_M1, DAYCAP = 1440, -3.0
LADDERS = {"LADDER": [(0.5, 1.0), (0.25, 2.0), (0.25, 3.0)], "FIXED2R": [(1.0, 2.0)]}


def load():
    df = pd.read_csv(os.path.join(DATA, f"{SYM}_M1.csv"))
    df["time"] = pd.to_datetime(df.time_server, format="%Y.%m.%d %H:%M")
    return df.drop(columns="time_server").sort_values("time").drop_duplicates("time").reset_index(drop=True)


def resample(m1, rule):
    g = m1.set_index("time").resample(rule, label="left", closed="left")
    return pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()


def atr_rma(df, n=14):
    h, l, c = df.high.values, df.low.values, df.close.values
    pc = np.roll(c, 1); pc[0] = c[0]
    tr = np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
    a = np.full(len(tr), np.nan); a[n - 1] = tr[:n].mean()
    for i in range(n, len(tr)):
        a[i] = (a[i - 1] * (n - 1) + tr[i]) / n
    return a


def setups(m5, A):
    """Pass 1: pivots -> equal/sweep pairs. Returns setup dicts (creation bar i, d, eq, mid, zt, zb, b2, kind)."""
    H, L, O, C = m5.high.values, m5.low.values, m5.open.values, m5.close.values
    pv = P["piv"]; out = []
    piv = {-1: ([], []), 1: ([], [])}
    recent = []  # (d, lvl, b2) of live-ish setups for dedupe
    for i in range(30, len(m5)):
        a = A[i]
        if not a > 0:
            continue
        tol = P["eqTol"] * a; pb = i - pv
        isPH = H[pb] > H[pb - pv:pb].max() and H[pb] >= H[pb + 1:i + 1].max()
        isPL = L[pb] < L[pb - pv:pb].min() and L[pb] <= L[pb + 1:i + 1].min()
        for d, isP in ((-1, isPH), (1, isPL)):
            if not isP:
                continue
            PP, PB = piv[d]; p = H[pb] if d == -1 else L[pb]
            for j in range(len(PP) - 1, -1, -1):
                q, qb = PP[j], PB[j]; gap = pb - qb
                if gap < P["minGap"]:
                    continue
                if gap > P["maxGap"]:
                    break
                ext = d * (q - p)
                back = (C[pb:i + 1].min() < q) if d == -1 else (C[pb:i + 1].max() > q)
                kind = None
                if abs(p - q) <= tol:
                    kind = "equal"; lvl = max(p, q) if d == -1 else min(p, q); lim = lvl + d * -tol
                elif 0.05 * a < ext <= P["sweepMax"] * a and back:
                    kind = "sweep"; lvl = p; lim = q
                if kind is None:
                    continue
                seg = slice(qb + 1, pb)
                if pb - qb <= 1:
                    break
                if d == -1:
                    clean = not (H[seg] > (lvl + tol if kind == "equal" else lim)).any(); midv = L[seg].min()
                else:
                    clean = not (L[seg] < (lvl - tol if kind == "equal" else lim)).any(); midv = H[seg].max()
                recent[:] = [r for r in recent if i - r[2] < 200]
                dup = any(r[0] == d and (abs(r[1] - lvl) <= tol or r[2] == qb) for r in recent)
                if clean and not dup and d * (midv - lvl) >= P["minDip"] * a:
                    k = pb
                    for kk in range(pb, max(pb - 5, 0) - 1, -1):
                        if d * (C[kk] - O[kk]) < 0:
                            k = kk; break
                    zh, zl = H[k], L[k]
                    if zh - zl > P["obMax"] * a:
                        zh, zl = max(O[k], C[k]), min(O[k], C[k])
                    out.append(dict(i=i, d=d, eq=lvl, mid=midv, zt=max(zh, H[pb]) if d == -1 else zh,
                                    zb=zl if d == -1 else min(zl, L[pb]), b2=pb, kind=kind))
                    recent.append((d, lvl, pb))
                break
            PP.append(p); PB.append(pb)
            if len(PP) > 200:
                PP.pop(0); PB.pop(0)
    return out


def signals(m5, A, S, shift_fn=None):
    """Pass 2: BOS -> advance block -> retest -> rejection close. shift_fn(setup, bos_bar) -> price offset (twin control).
    Returns list of (bar j of the rejection close, d, stop price, kind)."""
    H, L, O, C = m5.high.values, m5.low.values, m5.open.values, m5.close.values
    by_i = {}
    for s in S:
        by_i.setdefault(s["i"], []).append(dict(s, st=0, wrong=0))
    live, sig = [], []
    for i in range(len(m5)):
        live.extend(by_i.get(i, ()))
        if not live:
            continue
        a = A[i]
        if not a > 0:
            continue
        tol = P["eqTol"] * a; keep = []
        for s in live:
            d = s["d"]
            if s["st"] == 0:
                if i - s["b2"] > P["bosMax"] or d * (s["eq"] - C[i]) > tol:
                    continue
                if d * (C[i] - s["mid"]) > P["beyond"] * a:
                    kk0 = None
                    for kk in range(i - 1, s["b2"], -1):
                        if d * (C[kk] - O[kk]) < 0:
                            kk0 = kk; break
                    if kk0 is None:
                        at, ab = max(O[i], C[i]), min(O[i], C[i])
                    else:
                        at, ab = H[kk0], L[kk0]
                        if at - ab > P["obMax"] * a:
                            at, ab = max(O[kk0], C[kk0]), min(O[kk0], C[kk0])
                    s.update(bos=i, st=1, at=at, ab=ab)
                    if shift_fn is not None:
                        off = shift_fn(s, i)
                        for f in ("at", "ab", "zt", "zb", "eq"):
                            s[f] += off
                keep.append(s); continue
            near = s["at"] if d == 1 else s["ab"]
            far = s["zb"] if d == 1 else s["zt"]
            s["wrong"] = s["wrong"] + 1 if d * (far - C[i]) > P["invBuf"] * a else 0
            if s["wrong"] >= P["invAccept"] or d * (s["eq"] - C[i]) > tol or i - s["bos"] > P["retestMax"]:
                continue
            touched = L[i] <= near if d == 1 else H[i] >= near
            if s["st"] == 1 and touched and i > s["bos"]:
                s["st"] = 2
            if s["st"] == 2 and d * (C[i] - near) > 0 and d * (C[i] - O[i]) > 0:
                stop = far - d * P["stopBuf"] * a; risk = d * (C[i] - stop)
                if P["minRisk"] * a <= risk <= P["maxRisk"] * a:
                    sig.append((i, d, stop, s["kind"]))
                continue
            keep.append(s)
        live = keep
    return sig


def first_hit(H, L, O, S, k, end, d, sl, tp, sp):
    """First M1 bar in [k, end) touching sl or tp (shorts trade at ask = bid + spread). (bar, price, 'sl'|'tp'|None)."""
    if d == 1:
        slh = L[k:end] <= sl; tph = H[k:end] >= tp
    else:
        sh = (S[k:end] + sp) * PT
        slh = H[k:end] + sh >= sl; tph = L[k:end] + sh <= tp
    hit = np.flatnonzero(slh | tph)
    if not len(hit):
        return None
    m = k + hit[0]; o = O[m] + (0 if d == 1 else (S[m] + sp) * PT)
    if slh[hit[0]]:
        return m, (o if m > k and d * (o - sl) < 0 else sl), "sl"
    return m, (o if m > k and d * (o - tp) > 0 else tp), "tp"


def trade(m1, k, d, stop, ladder, sp):
    """Ladder from M1 bar k. Returns (R, exit bar)."""
    O, H, L, C, S = m1.open.values, m1.high.values, m1.low.values, m1.close.values, m1.spread.values
    entry = O[k] + (S[k] + sp) * PT if d == 1 else O[k]
    risk = d * (entry - stop)
    if risk <= 0:
        return None
    end = min(len(O), k + MAXHOLD_M1); sl = stop; R = 0.0; left = 1.0; cur = k
    for frac, rr in ladder:
        tp = entry + d * rr * risk
        h = first_hit(H, L, O, S, cur, end, d, sl, tp, sp)
        if h is None:
            last = C[end - 1] + (0 if d == 1 else (S[end - 1] + sp) * PT)
            return R + left * d * (last - entry) / risk, end - 1
        m, px, what = h
        if what == "sl":
            return R + left * d * (px - entry) / risk, m
        R += frac * d * (px - entry) / risk; left -= frac; cur = m
        sl = entry  # breakeven after the first target
    return R, cur


def run_book(m1, m5, sig, ladder, sp):
    t1 = m1.time.values; t5 = m5.time.values
    dow = pd.DatetimeIndex(t5).dayofweek.values
    busy = -1; rows = []; day = None; dayR = 0.0
    for j, d, stop, kind in sig:
        if j + 1 >= len(t5) or dow[j + 1] >= 5:
            continue
        k = int(np.searchsorted(t1, t5[j + 1]))
        if k >= len(t1) or k <= busy:
            continue
        dd = t5[j + 1].astype("datetime64[D]")
        if dd != day:
            day, dayR = dd, 0.0
        if dayR <= DAYCAP:
            continue
        r = trade(m1, k, d, stop, ladder, sp)
        if r is None:
            continue
        R, m = r; busy = m; dayR += R
        rows.append((t5[j + 1], d, kind, R))
    return pd.DataFrame(rows, columns=["time", "d", "kind", "R"])


def summ(R):
    if len(R) == 0:
        return dict(n=0, tot=0.0, avg=0.0, win=0.0, pf=0.0)
    r = R.R
    return dict(n=len(R), tot=r.sum(), avg=r.mean(), win=(r > 0).mean(), pf=r[r > 0].sum() / max(-r[r < 0].sum(), 1e-12))


if __name__ == "__main__":
    m1 = load(); m5 = resample(m1, "5min"); A = atr_rma(m5)
    C5 = m5.close.values
    S = setups(m5, A)
    real_sig = signals(m5, A, S)
    print(f"{SYM} M5 {m5.time.iloc[0]:%Y-%m-%d} -> {m5.time.iloc[-1]:%Y-%m-%d}: {len(S)} setups, {len(real_sig)} signals", flush=True)
    # distance pool: advance-block near edge vs close at the BOS bar (ATR units), recorded from a real pass
    pool = {1: [], -1: []}
    def rec(s, i):
        near = s["at"] if s["d"] == 1 else s["ab"]
        pool[s["d"]].append(s["d"] * (C5[i] - near) / A[i]); return 0.0
    signals(m5, A, S, rec)
    pool = {k: np.array(v) for k, v in pool.items()}
    stopATR = np.array([abs(m5.close.values[j] - st) / A[j] for j, d, st, _ in real_sig])
    dirs = np.array([d for _, d, _, _ in real_sig])
    rows = []
    for name, lad in LADDERS.items():
        real = run_book(m1, m5, real_sig, lad, MARKUP); real["year"] = pd.to_datetime(real.time).dt.year
        if name == "LADDER":
            real.to_csv(os.path.join(DATA, "zone_ladder_real_trades.csv"), index=False)
        s = summ(real); years = sorted(real.year.unique())
        print(f"\n=== {name}: REAL {s['n']} trades, {s['tot']:+.1f}R, avg {s['avg']:+.3f}R, win {s['win']:.0%}, PF {s['pf']:.2f}", flush=True)
        for kd in ("equal", "sweep"):
            x = summ(real[real.kind == kd]); print(f"   {kd:5s}: {x['n']} tr, avg {x['avg']:+.3f}R, PF {x['pf']:.2f}")
        for dd, lab in ((1, "buys"), (-1, "sells")):
            x = summ(real[real.d == dd]); print(f"   {lab:5s}: {x['n']} tr, avg {x['avg']:+.3f}R, PF {x['pf']:.2f}")
        rng = np.random.default_rng(20261011)
        tw_tot, tw_year, rt_tot = [], {y: [] for y in years}, []
        for sd in range(SEEDS):
            def shift(s, i, rng=rng):
                near = s["at"] if s["d"] == 1 else s["ab"]
                want = rng.choice(pool[s["d"]]) * A[i]
                return (C5[i] - s["d"] * want) - near
            tw = run_book(m1, m5, signals(m5, A, S, shift), lad, MARKUP); tw["year"] = pd.to_datetime(tw.time).dt.year
            tw_tot.append(summ(tw))
            for y in years:
                tw_year[y].append(tw[tw.year == y].R.sum())
            js = np.sort(rng.choice(np.arange(200, len(m5) - 2), size=len(real_sig), replace=False))
            dsr = rng.choice(dirs, size=len(js)); sa = rng.choice(stopATR, size=len(js))
            rsig = [(j, int(d), C5[j] - d * x * A[j], "rand") for j, d, x in zip(js, dsr, sa)]
            rt_tot.append(summ(run_book(m1, m5, rsig, lad, MARKUP)))
            print(f"   seed {sd + 1}/{SEEDS}: twin {tw_tot[-1]['tot']:+.1f}R ({tw_tot[-1]['n']} tr) | random-time {rt_tot[-1]['tot']:+.1f}R", flush=True)
        tt = np.array([x["tot"] for x in tw_tot]); rt = np.array([x["tot"] for x in rt_tot])
        ta = np.array([x["avg"] for x in tw_tot]); ra = np.array([x["avg"] for x in rt_tot])
        print(f"  TWINS: total median {np.median(tt):+.1f}R [5-95%: {np.percentile(tt,5):+.1f} .. {np.percentile(tt,95):+.1f}], avg/trade {np.median(ta):+.3f}R"
              f" | REAL beats {(tt < s['tot']).mean():.0%}")
        print(f"  RANDOM TIME: total median {np.median(rt):+.1f}R, avg/trade {np.median(ra):+.3f}R | REAL beats {(rt < s['tot']).mean():.0%}")
        for y in years:
            yr = summ(real[real.year == y]); arr = np.array(tw_year[y])
            print(f"   {y}: {yr['n']:4d} tr {yr['tot']:+7.1f}R avg {yr['avg']:+.3f} win {yr['win']:.0%} PF {yr['pf']:.2f} | twins median {np.median(arr):+7.1f}R | beats {(arr < yr['tot']).mean():.0%}")
            rows.append(dict(mgmt=name, year=y, n=yr["n"], R=yr["tot"], avg=yr["avg"], pf=yr["pf"], twin_med=np.median(arr), beats=(arr < yr["tot"]).mean()))
        rows.append(dict(mgmt=name, year="ALL", n=s["n"], R=s["tot"], avg=s["avg"], pf=s["pf"], twin_med=np.median(tt), beats=(tt < s["tot"]).mean(),
                         rand_med=np.median(rt), beats_rand=(rt < s["tot"]).mean()))
    pd.DataFrame(rows).to_csv(os.path.join(DATA, "zone_ladder_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "zone_ladder_summary.csv"))
