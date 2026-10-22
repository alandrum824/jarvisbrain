"""ORB family survey (Adam 2026-10-22: "study and learn all different ORB strategy and make a good working one"). READ-ONLY.

Families (NY open 09:30, flat 16:00, one trade/day, entries until 12:00 unless noted):
  ORB{N}      stop entry at the edge of the first N-min box (N = 5/15/30/60), SL = other side.
  MID{N}      after the first edge touch, limit at the box midpoint (N = 15/30), SL = other side.
  ZA{N}       Zarattini-Aziz: direction of the first N-min candle (N = 5/15), enter at the next bar open, SL = other
              side of that candle; doji (body < 10% of range) skipped.
  CRABEL      Crabel stretch: stretch = 10-day mean of min(open-high, open-low) of the 09:30-16:00 session;
              buy stop at open+stretch, sell stop at open-stretch, SL = the other stop.
Filters on ORB15 and ORB30: NARROW (box < median of the previous 20 boxes), NR7 (yesterday's session range the
  narrowest of 7), TREND (trade only the side of yesterday's close vs the 20-session SMA of closes), GAP (trade only
  the gap's direction: 09:30 open vs yesterday's 16:00 close).
Exits: 1R, 2R, EOD (no target, flat 16:00).
PRE-REGISTERED SELECTION (fixed before any result): pick on DISCOVERY (to 2024-12-31) among NAS100 cells with >= 150
discovery trades, by avg R. A cell is a WINNER only if it also has HOLDOUT (2025-01 on) avg R > 0, full-period PF > 1.1,
beats >= 95% of 50 coin-flip runs, and >= 4 of 5 years positive. US30 / XAUUSD / EURUSD run the same cells as a
robustness check (not used for selection). Costs: bar spread (+6 pt gold), shorts exit on the ask, SL first on ties,
a limit's fill bar can stop it out.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, DATA

PT = {"NAS100": 0.1, "US30": 0.1, "XAUUSD": 0.01, "EURUSD": 0.00001}
MK = {"XAUUSD": 6}
SEEDS = 50; SPLIT = pd.Timestamp("2025-01-01")
M = np.timedelta64(1, "m")


def sessions(df):
    T = df.ny.values; O, H, L, C = (df[k].values for k in ("open", "high", "low", "close"))
    rows = []
    for d in pd.DatetimeIndex(T).normalize().unique():
        if d.dayofweek >= 5:
            continue
        o = (d + pd.Timedelta(hours=9, minutes=30)).to_datetime64()
        i0 = np.searchsorted(T, o); iF = np.searchsorted(T, o + 390 * M); iN = np.searchsorted(T, o + 150 * M)
        if iF - i0 < 300 or T[i0] > o + 2 * M:
            continue
        rows.append(dict(day=d, i0=i0, iN=iN, iF=iF, open=O[i0], close=C[iF - 1], hi=H[i0:iF].max(), lo=L[i0:iF].min()))
    s = pd.DataFrame(rows)
    s["rng"] = s.hi - s.lo
    s["noise"] = np.minimum(s.hi - s.open, s.open - s.lo)
    s["stretch"] = s.noise.shift(1).rolling(10).mean()
    s["nr7"] = s.rng.shift(1) <= s.rng.shift(1).rolling(7).min()
    s["trend"] = np.sign(s.close.shift(1) - s.close.shift(1).rolling(20).mean())
    s["gap"] = np.sign(s.open - s.close.shift(1))
    return s


def first_touch(H, L, a, b, hi, lo):
    up = np.flatnonzero(H[a:b] >= hi); dn = np.flatnonzero(L[a:b] <= lo)
    u = up[0] if len(up) else 10 ** 9; w = dn[0] if len(dn) else 10 ** 9
    if u == w:
        return None
    if min(u, w) == 10 ** 9:
        return None
    return (a + u, 1) if u < w else (a + w, -1)


def signals(df, s, fam, flt=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    out = []; boxes = []
    for r in s.itertuples():
        sig = None
        if fam.startswith(("ORB", "MID")):
            n = int(fam[3:]); i1 = r.i0 + n
            hi = H[r.i0:i1].max(); lo = L[r.i0:i1].min(); box = hi - lo
            narrow_ok = len(boxes) >= 20 and box < np.median(boxes[-20:]); boxes.append(box)
            if box <= 0:
                continue
            t = first_touch(H, L, i1, r.iN, hi, lo)
            if t is None:
                continue
            k, d = t
            if fam.startswith("ORB"):
                sig = dict(k=k, d=d, e=max(hi, O[k]) if d == 1 else min(lo, O[k]), sl=lo if d == 1 else hi, lim=False)
            else:
                mid = (hi + lo) / 2; sp = (S + MK.get(SYM, 0)) * PT[SYM]
                for j in range(k + 1, r.iN):
                    if d == 1 and L[j] + sp[j] <= mid:
                        sig = dict(k=j, d=1, e=min(mid, O[j] + sp[j]) - sp[j], sl=lo, lim=True); break
                    if d == -1 and H[j] >= mid:
                        sig = dict(k=j, d=-1, e=max(mid, O[j]), sl=hi, lim=True); break
            if sig and flt:
                if flt == "NARROW" and not narrow_ok: sig = None
                elif flt == "NR7" and not r.nr7: sig = None
                elif flt == "TREND" and r.trend != d: sig = None
                elif flt == "GAP" and r.gap != d: sig = None
        elif fam.startswith("ZA"):
            n = int(fam[2:]); i1 = r.i0 + n
            o, c = O[r.i0], C[i1 - 1]; hi = H[r.i0:i1].max(); lo = L[r.i0:i1].min()
            if hi - lo <= 0 or abs(c - o) < 0.1 * (hi - lo):
                continue
            d = 1 if c > o else -1
            sig = dict(k=i1, d=d, e=O[i1], sl=lo if d == 1 else hi, lim=False)
        elif fam == "CRABEL":
            if np.isnan(r.stretch) or r.stretch <= 0:
                continue
            bh, bl = r.open + r.stretch, r.open - r.stretch
            t = first_touch(H, L, r.i0 + 1, r.iN, bh, bl)
            if t is None:
                continue
            k, d = t
            sig = dict(k=k, d=d, e=max(bh, O[k]) if d == 1 else min(bl, O[k]), sl=bl if d == 1 else bh, lim=False)
        if sig:
            sig.update(day=r.day, fl=r.iF); out.append(sig)
    return out


def run(df, sets, ex, rng=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    pt = PT[SYM]; mk = MK.get(SYM, 0); rows = []
    for s in sets:
        k, d, e = s["k"], s["d"], s["e"]; sld = abs(e - s["sl"])
        if sld <= 0 or s["fl"] <= k + 1:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
        sp = (S[k] + mk) * pt
        if d == 1:
            e = e + sp
        sl = e - d * sld; tp = e + d * ex * sld if ex else None
        a = k if s["lim"] else k + 1          # stop/market entries: exits from the next bar; limits: the fill bar too
        b = s["fl"]; shs = (S[a:b] + mk) * pt
        if d == 1:
            slh = L[a:b] <= sl; tph = H[a:b] >= tp if tp else np.zeros(b - a, bool)
        else:
            slh = H[a:b] + shs >= sl; tph = L[a:b] + shs <= tp if tp else np.zeros(b - a, bool)
        if s["lim"]:
            tph[0] = False
        hit = np.flatnonzero(slh | tph)
        if len(hit):
            m = a + hit[0]; px = sl if slh[hit[0]] else tp
            o = O[m] + (0 if d == 1 else (S[m] + mk) * pt)
            if m > k and ((slh[hit[0]] and d * (o - sl) < 0) or (not slh[hit[0]] and d * (o - tp) > 0)):
                px = o                          # gapped through the level
        else:
            m = b - 1; px = C[m] + (0 if d == 1 else (S[m] + mk) * pt)
        rows.append((s["day"], d, d * (px - e) / sld))
    return pd.DataFrame(rows, columns=["day", "d", "R"])


def stats(r):
    if r.empty:
        return dict(n=0, R=0.0, avg=0.0, win=0.0, pf=0.0)
    x = r.R
    return dict(n=len(r), R=x.sum(), avg=x.mean(), win=(x > 0).mean(), pf=x[x > 0].sum() / max(-x[x < 0].sum(), 1e-12))


CELLS = ([(f"ORB{n}", None) for n in (5, 15, 30, 60)] + [(f"MID{n}", None) for n in (15, 30)] +
         [("ZA5", None), ("ZA15", None), ("CRABEL", None)] +
         [(f"ORB{n}", f) for n in (15, 30) for f in ("NARROW", "NR7", "TREND", "GAP")] +
         [(f"MID{n}", f) for n in (15, 30) for f in ("NARROW", "NR7", "TREND", "GAP")])
EXITS = [(1, "1R"), (2, "2R"), (0, "EOD")]

if __name__ == "__main__":
    syms = sys.argv[1:] or ["NAS100"]
    res = []
    for SYM in syms:
        df = load(SYM); s = sessions(df)
        print(f"\n== {SYM}: {len(s)} sessions {s.day.min():%Y-%m} to {s.day.max():%Y-%m}", flush=True)
        for fam, flt in CELLS:
            sets = signals(df, s, fam, flt)
            for ex, exn in EXITS:
                real = run(df, sets, ex)
                if real.empty:
                    continue
                dis, hol = real[real.day < SPLIT], real[real.day >= SPLIT]
                rng = np.random.default_rng(20261022)
                coin = np.array([run(df, sets, ex, rng).R.sum() for _ in range(SEEDS)])
                yr = real.groupby(real.day.dt.year).R.sum()
                a, b, c = stats(real), stats(dis), stats(hol)
                row = dict(sym=SYM, cell=f"{fam}{'+' + flt if flt else ''} {exn}", n=a["n"], R=a["R"], avg=a["avg"], win=a["win"],
                           pf=a["pf"], dis_n=b["n"], dis_avg=b["avg"], hol_n=c["n"], hol_avg=c["avg"], hol_R=c["R"],
                           years_pos=int((yr > 0).sum()), years=len(yr), beats=(coin < a["R"]).mean(),
                           long_R=real[real.d == 1].R.sum(), short_R=real[real.d == -1].R.sum(),
                           yrs=" ".join(f"{y}:{v:+.1f}" for y, v in yr.items()))
                res.append(row)
                print(f"  {row['cell']:20s} {a['n']:5d} tr {a['R']:+7.1f}R avg {a['avg']:+.3f} win {a['win']:.0%} PF {a['pf']:.2f} | "
                      f"dis {b['avg']:+.3f} ({b['n']}) hold {c['avg']:+.3f} ({c['n']}) | yrs+ {row['years_pos']}/{row['years']} | "
                      f"coin {row['beats']:.0%} | L {row['long_R']:+.1f} S {row['short_R']:+.1f}", flush=True)
    out = pd.DataFrame(res)
    out.to_csv(os.path.join(DATA, f"orb_family_{'_'.join(syms)}.csv"), index=False)
    for SYM in syms:
        x = out[(out.sym == SYM) & (out.dis_n >= 150)].sort_values("dis_avg", ascending=False)
        x = x.assign(winner=(x.hol_avg > 0) & (x.pf > 1.1) & (x.beats >= 0.95) & (x.years_pos >= x.years - 1))
        print(f"\n{SYM} ranked on DISCOVERY avg R (top 12):")
        print(x.head(12)[["cell", "n", "dis_avg", "hol_avg", "pf", "win", "years_pos", "beats", "winner", "yrs"]].to_string(index=False))
