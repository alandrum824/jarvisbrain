"""Gold SNIPER entries on the proven Asia-range breakout (momentum + OB/FVG + sniper). READ-ONLY replay.

Adam 2026-10-13: "Study forex study order blocks fvg then study momentum what works best then study sniper entries
understand them put it all together and make and ea and test ... be more determined".
Thesis: OB/FVG failed as stand-alone entries, but the Asia breakout (00-05 GMT range, London/NY break) has a real
directional edge. Use OB/FVG as the SNIPER location on that proven momentum: wait for the pullback into the zone the
breakout created, enter with a limit, tighter stop, bigger target.
PRE-REGISTERED (fixed before any run):
  Range 00:00-05:00 GMT, skip if width < 0.10 or > 0.80 x daily ATR(14) (same as TWI Gold Asia Breakout).
  Breakout = first M5 bar from 05:00 that CLOSES beyond the range (d = +1 above high, -1 below low), before 15:00.
  MOMENTUM filter (MOM): the breakout bar's body >= 0.8 x ATR(14) on M5. Every sniper is run with MOM and without (ALL).
  Entries (limit orders placed after the breakout bar closes, valid until 15:00 GMT; trade closed 16:00 GMT):
    RETEST : limit at the broken range edge; SL = range midpoint; TP = edge + d x range width (measured move).
    FVG    : most recent 3-bar fair value gap in the breakout leg (05:00 -> breakout bar) in direction d
             (bull: low[i] > high[i-2]); limit at the gap's near edge; SL = far edge -/+ 0.25 x ATR(M5); TP = 2R.
    OB     : last opposite-colour M5 candle among the 6 bars up to the breakout bar; limit at its near extreme
             (bull: the bearish candle's high); SL = its far extreme -/+ 0.25 x ATR(M5); TP = 2R.
  Minimum stop for FVG/OB: max(0.5 x ATR(M5), 5 x spread); widened if smaller. Skip if no zone found.
Fills on M1 with the real spread (+6 pt markup): buy limit fills when ask <= level, sell limit when bid >= level.
Control: 50-seed coin flip (same fill time/price, stop and R target, random direction).
Pass bar = EA Scorecard: >= 5/7 years, PF > 1, beats >= 95% of coin. 6 cells -> ~0.3 false passes expected.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import first_hit
from gold_breakout_research import summ, report, atr_rma

MK = 6; SEEDS = 50; PTG = PT["XAUUSD"]


def prep():
    m1 = load("XAUUSD")
    u = pd.DatetimeIndex(m1.ny).tz_localize("America/New_York", ambiguous="NaT", nonexistent="NaT").tz_convert("UTC").tz_localize(None)
    m1 = m1.assign(utc=u).dropna(subset=["utc"]).sort_values("utc").drop_duplicates("utc").reset_index(drop=True)
    return m1


def build_days(m1):
    U = m1.utc.values
    g = m1.set_index("utc").resample("5min", label="left", closed="left")
    m5 = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()
    a5 = atr_rma(m5.high.values, m5.low.values, m5.close.values, 14)
    day = m1.utc.dt.normalize()
    d1 = m1.groupby(day).agg(high=("high", "max"), low=("low", "min"), close=("close", "last"))
    da = atr_rma(d1.high.values, d1.low.values, d1.close.values, 14)
    datr = dict(zip(d1.index.values, np.roll(da, 1)))
    T5 = m5.utc.values
    O5, H5, L5, C5 = (m5[k].values for k in ("open", "high", "low", "close"))
    days = []
    for dd in pd.DatetimeIndex(np.unique(day.values)):
        if dd.dayofweek >= 5:
            continue
        at = datr.get(dd.to_datetime64(), np.nan)
        if not at > 0:
            continue
        r0 = int(np.searchsorted(T5, dd.to_datetime64())); r1 = int(np.searchsorted(T5, (dd + pd.Timedelta(hours=5)).to_datetime64()))
        if r1 - r0 < 40:
            continue
        hi, lo = H5[r0:r1].max(), L5[r0:r1].min(); w = hi - lo
        if w < 0.10 * at or w > 0.80 * at:
            continue
        e15 = int(np.searchsorted(T5, (dd + pd.Timedelta(hours=15)).to_datetime64()))
        b = None
        for j in range(r1, min(e15, len(T5))):
            if C5[j] > hi: b, d = j, 1; break
            if C5[j] < lo: b, d = j, -1; break
        if b is None or not a5[b] > 0:
            continue
        mom = abs(C5[b] - O5[b]) >= 0.8 * a5[b]
        # FVG in the leg r1..b in direction d (most recent)
        fvg = None
        for i in range(b, max(r1, 2) + 1, -1):
            if d == 1 and L5[i] > H5[i - 2]:
                fvg = (L5[i], H5[i - 2]); break          # (near edge, far edge)
            if d == -1 and H5[i] < L5[i - 2]:
                fvg = (H5[i], L5[i - 2]); break
        ob = None
        for i in range(b, max(b - 6, r1 - 1), -1):
            if d == 1 and C5[i] < O5[i]:
                ob = (H5[i], L5[i]); break
            if d == -1 and C5[i] > O5[i]:
                ob = (L5[i], H5[i]); break
        days.append(dict(day=dd, d=d, hi=hi, lo=lo, w=w, mom=mom, a5=a5[b], fvg=fvg, ob=ob,
                         t_place=T5[b] + np.timedelta64(5, "m"),
                         t_cancel=(dd + pd.Timedelta(hours=15)).to_datetime64(),
                         t_close=(dd + pd.Timedelta(hours=16)).to_datetime64()))
    return days


def plan(s, kind, spread_px):
    d = s["d"]
    if kind == "RETEST":
        edge = s["hi"] if d == 1 else s["lo"]
        mid = (s["hi"] + s["lo"]) / 2
        return edge, mid, edge + d * s["w"]
    z = s["fvg"] if kind == "FVG" else s["ob"]
    if z is None:
        return None
    near, far = z
    sl = far - d * 0.25 * s["a5"]
    risk = d * (near - sl)
    risk = max(risk, 0.5 * s["a5"], 5 * spread_px)
    return near, near - d * risk, near + d * 2 * risk


def run(m1, days, kind, mom_only, rng=None):
    U = m1.utc.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    rows = []
    for s in days:
        if mom_only and not s["mom"]:
            continue
        k0 = int(np.searchsorted(U, s["t_place"])); kc = int(np.searchsorted(U, s["t_cancel"])); ke = int(np.searchsorted(U, s["t_close"]))
        if k0 >= kc or kc > len(U):
            continue
        sp0 = (S[k0] + MK) * PTG
        p = plan(s, kind, sp0)
        if p is None:
            continue
        lvl, sl, tp = p; d = s["d"]
        # limit fill: buy when ask <= lvl, sell when bid >= lvl (from the bar after placement)
        if d == 1:
            hit = np.flatnonzero(L[k0:kc] + (S[k0:kc] + MK) * PTG <= lvl)
        else:
            hit = np.flatnonzero(H[k0:kc] >= lvl)
        if not len(hit):
            continue
        kf = k0 + hit[0]
        entry = min(lvl, O[kf] + (S[kf] + MK) * PTG) if d == 1 else max(lvl, O[kf])
        risk = d * (entry - sl)
        if risk <= 0:
            continue
        tpR = d * (tp - entry) / risk
        if tpR <= 0.2:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            sl = entry - d * risk; tp = entry + d * tpR * risk
        k = kf + 1
        if k >= ke:
            continue
        h = first_hit(H, L, O, S, k, ke, d, sl, tp, PTG, MK)
        if h is None:
            m = ke - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * PTG)
        else:
            m, px = h
        rows.append((s["day"].year, d, d * (px - entry) / risk, risk, tpR))
    return pd.DataFrame(rows, columns=["year", "d", "R", "risk", "tpR"])


if __name__ == "__main__":
    m1 = prep()
    days = build_days(m1)
    print(f"{len(days)} breakout days ({sum(s['mom'] for s in days)} with a momentum breakout bar)", flush=True)
    out = []
    for kind in ("RETEST", "FVG", "OB"):
        for mom_only in (True, False):
            name = f"{kind} {'MOM' if mom_only else 'ALL'}"
            real = run(m1, days, kind, mom_only)
            rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, days, kind, mom_only, rng))["tot"] for _ in range(SEEDS)]
            row = report(name, real, coin)
            print(f"    fills {len(real)}, median stop ${real.risk.median():.2f}, median target {real.tpR.median():.2f}R, "
                  f"long {real[real.d==1].R.sum():+.1f}R / short {real[real.d==-1].R.sum():+.1f}R", flush=True)
            out.append(row)
    pd.DataFrame(out).to_csv(r"C:\Users\aland\stg\obh\gold_sniper_summary.csv", index=False)
    print("saved")
