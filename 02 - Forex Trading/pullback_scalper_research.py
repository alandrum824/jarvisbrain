"""TWI Pullback Scalper: offline research + coin-flip control. READ-ONLY (bars only, no orders).

Adam 2026-10-12: "Let's do pull backs scalper in trend" -> "Yes" to the spec below, test before any EA is built.
Rules are PRE-REGISTERED (fixed before any result was seen); nothing here was tuned on this data.
  Trend (H1, last CLOSED H1 bar): up = close > EMA50 and EMA21 > EMA50; down = the mirror.
  M5 agrees: EMA21 > EMA50 (up) / < (down).
  Pullback signal (closed M5 bar j): low <= EMA21 and close > EMA21 and close > open (rejection) for a buy; mirror for a sell.
    Edge-triggered: no signal in the same direction in the previous 6 M5 bars.
  Session: 03:00-12:00 New York, Mon-Fri. One trade at a time. No new trade after -3R realised that NY day.
  Entry: next M5 open (buy at ask = bid + bar spread + markup, sell at bid).
  Stop: lowest low of bars j-2..j minus 0.25 ATR(14, M5) for a buy (mirror for a sell); widened to at least
    max(0.5 ATR, 5 x spread); trade skipped if wider than 3 ATR.
  Targets (two variants):
    SWING = the most recent confirmed M5 swing high (3/3 pivot, last 60 bars) above entry for a buy (swing low for a sell),
            at least 1R and at most 4R; 1.5R when no swing exists.   ("end of the move")
    R15   = fixed 1.5R.
  Exit: SL/TP resolved on M1 with the bar spread (SL first when a bar hits both); flat at 16:50 NY (gold daily break).
Markets: XAUUSD, EURUSD, USDJPY. Longs and shorts reported separately.
Control: COIN = same entry bars, same stop distance and same target in R, but a coin-flip direction (SEEDS runs).
Pass bar (EA Scorecard): positive in >= 5 of 7 years, PF > 1, and beats >= 95% of coin runs.
Clock: AAAFx server = London time before 2022-03-27, UTC+0 to 2026-03-06, NY+7 after (as orb_momentum_longrun_research.py).
Data: C:/Users/aland/stg/obh/<SYM>_M1.csv (TWIBarsExportTester, 2020-01-02 -> 2026-10-09).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe pullback_scalper_research.py [SEEDS]
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT

DATA = r"C:\Users\aland\stg\obh"
MARKUP = {"XAUUSD": 6}
SEEDS = int(sys.argv[1]) if len(sys.argv) > 1 else 50
SYMS = ["XAUUSD", "EURUSD", "USDJPY"]
SESS = (3 * 60, 12 * 60); FLAT = 16 * 60 + 50
EDGE, SLBARS, SLBUF, MINR, MAXR, SPREADX = 6, 3, 0.25, 0.5, 3.0, 5
PIV, SWLOOK, TPMIN, TPMAX, TPDEF = 3, 60, 1.0, 4.0, 1.5
DAYCAP = -3.0


def ema(x, n):
    return pd.Series(x).ewm(span=n, adjust=False).mean().values


def atr_rma(h, l, c, n=14):
    pc = np.roll(c, 1); pc[0] = c[0]
    tr = np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
    a = np.full(len(tr), np.nan); a[n - 1] = tr[:n].mean()
    for i in range(n, len(tr)):
        a[i] = (a[i - 1] * (n - 1) + tr[i]) / n
    return a


def bars(m1, rule):
    g = m1.set_index("ny").resample(rule, label="left", closed="left")
    return pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()


def build_signals(m1):
    m5 = bars(m1, "5min"); h1 = bars(m1, "1h")
    O, H, L, C = (m5[k].values for k in ("open", "high", "low", "close"))
    e21, e50, A = ema(C, 21), ema(C, 50), atr_rma(H, L, C)
    hc = h1.close.values; h21, h50 = ema(hc, 21), ema(hc, 50)
    t5 = m5.ny.values; th = h1.ny.values
    # last H1 bar whose close (start + 1h) <= the M5 bar's close (start + 5m)
    hi = np.searchsorted(th, t5 + np.timedelta64(5, "m") - np.timedelta64(60, "m"), side="right") - 1
    mins = pd.DatetimeIndex(t5).hour * 60 + pd.DatetimeIndex(t5).minute
    dow = pd.DatetimeIndex(t5).dayofweek
    sig = []; last = {1: -99, -1: -99}
    for j in range(60, len(m5) - 1):
        if not A[j] > 0 or hi[j] < 50 or dow[j] >= 5 or not (SESS[0] <= mins[j] < SESS[1]):
            continue
        k = hi[j]
        up = hc[k] > h50[k] and h21[k] > h50[k] and e21[j] > e50[j]
        dn = hc[k] < h50[k] and h21[k] < h50[k] and e21[j] < e50[j]
        d = 1 if up else (-1 if dn else 0)
        if d == 0:
            continue
        hit = (L[j] <= e21[j] and C[j] > e21[j] and C[j] > O[j]) if d == 1 else (H[j] >= e21[j] and C[j] < e21[j] and C[j] < O[j])
        if not hit:
            continue
        if j - last[d] <= EDGE:
            last[d] = j; continue
        last[d] = j
        ext = L[j - SLBARS + 1:j + 1].min() if d == 1 else H[j - SLBARS + 1:j + 1].max()
        # most recent confirmed swing (3/3 pivot) in the trade direction, within SWLOOK bars
        sw = []
        for p in range(j - PIV, max(j - SWLOOK, PIV), -1):
            if d == 1 and H[p] > H[p - PIV:p].max() and H[p] >= H[p + 1:p + PIV + 1].max():
                sw.append(H[p])
            if d == -1 and L[p] < L[p - PIV:p].min() and L[p] <= L[p + 1:p + PIV + 1].min():
                sw.append(L[p])
        sig.append(dict(j=j, d=d, ext=ext, atr=A[j], swings=sw, t_entry=t5[j + 1], year=pd.Timestamp(t5[j + 1]).year))
    return m5, sig


def first_hit(H, L, O, S, k, end, d, sl, tp, pt, mk):
    if d == 1:
        slh = L[k:end] <= sl; tph = H[k:end] >= tp
    else:
        sh = (S[k:end] + mk) * pt
        slh = H[k:end] + sh >= sl; tph = L[k:end] + sh <= tp
    hit = np.flatnonzero(slh | tph)
    if not len(hit):
        return None
    m = k + hit[0]; o = O[m] + (0 if d == 1 else (S[m] + mk) * pt)
    if slh[hit[0]]:
        return m, (o if m > k and d * (o - sl) < 0 else sl)
    return m, (o if m > k and d * (o - tp) > 0 else tp)


def run(m1, sig, tpmode, sym, coin_rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    t1 = m1.ny.values; pt = PT[sym]; mk = MARKUP.get(sym, 0)
    rows = []; busy = -1; day = None; dayR = 0.0
    for s in sig:
        k = int(np.searchsorted(t1, s["t_entry"]))
        if k >= len(t1) or k <= busy:
            continue
        nyday = pd.Timestamp(t1[k]).normalize()
        if nyday != day:
            day, dayR = nyday, 0.0
        if dayR <= DAYCAP:
            continue
        d = s["d"]; a = s["atr"]; sp = (S[k] + mk) * pt
        entry_real = O[k] + sp if d == 1 else O[k]
        risk = d * (entry_real - (s["ext"] - d * SLBUF * a))
        risk = max(risk, MINR * a, SPREADX * sp)
        if risk > MAXR * a:
            continue
        if tpmode == "R15":
            tpR = TPDEF
        else:
            cand = [d * (x - entry_real) / risk for x in s["swings"] if d * (x - entry_real) > 0]
            tpR = min(max(cand[0], TPMIN), TPMAX) if cand else TPDEF
        if coin_rng is not None:
            d = 1 if coin_rng.random() < 0.5 else -1
        entry = O[k] + sp if d == 1 else O[k]
        sl = entry - d * risk; tp = entry + d * tpR * risk
        end = int(np.searchsorted(t1, (nyday + pd.Timedelta(minutes=FLAT)).to_datetime64()))
        if end <= k:
            continue
        h = first_hit(H, L, O, S, k, end, d, sl, tp, pt, mk)
        if h is None:
            m = end - 1; px = C[m] + (0 if d == 1 else (S[m] + mk) * pt)
        else:
            m, px = h
        R = d * (px - entry) / risk
        busy = m; dayR += R
        rows.append((s["year"], d, R))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


def summ(R):
    if len(R) == 0:
        return dict(n=0, tot=0.0, avg=0.0, win=0.0, pf=0.0)
    r = R.R
    return dict(n=len(R), tot=r.sum(), avg=r.mean(), win=(r > 0).mean(), pf=r[r > 0].sum() / max(-r[r < 0].sum(), 1e-12))


if __name__ == "__main__":
    out = []
    for sym in SYMS:
        m1 = load(sym)
        m5, sig = build_signals(m1)
        print(f"\n##### {sym}: {m5.ny.iloc[0]:%Y-%m-%d} -> {m5.ny.iloc[-1]:%Y-%m-%d}, {len(sig)} signals "
              f"({sum(s['d'] == 1 for s in sig)} buy / {sum(s['d'] == -1 for s in sig)} sell)", flush=True)
        for tpmode in ("SWING", "R15"):
            for side, sel in (("BOTH", None), ("LONG", 1), ("SHORT", -1)):
                ss = [s for s in sig if sel is None or s["d"] == sel]
                real = run(m1, ss, tpmode, sym); s = summ(real)
                years = sorted(real.year.unique()) if len(real) else []
                yr = {y: real[real.year == y].R.sum() for y in years}
                pos = sum(v > 0 for v in yr.values())
                rng = np.random.default_rng(20261012)
                coin = np.array([summ(run(m1, ss, tpmode, sym, rng))["tot"] for _ in range(SEEDS)])
                beats = (coin < s["tot"]).mean()
                ok = pos >= 5 and s["pf"] > 1 and beats >= 0.95
                print(f"  {tpmode:5s} {side:5s}: {s['n']:5d} tr {s['tot']:+8.1f}R avg {s['avg']:+.3f} win {s['win']:.0%} PF {s['pf']:.2f} | "
                      f"years+ {pos}/{len(years)} | coin median {np.median(coin):+7.1f}R, beats {beats:.0%} | {'PASS' if ok else 'fail'}", flush=True)
                print("        " + "  ".join(f"{y}:{v:+.1f}" for y, v in yr.items()), flush=True)
                out.append(dict(sym=sym, tp=tpmode, side=side, n=s["n"], R=s["tot"], avg=s["avg"], win=s["win"], pf=s["pf"],
                                years_pos=pos, years=len(years), coin_med=np.median(coin), beats=beats, passed=ok,
                                **{f"y{y}": v for y, v in yr.items()}))
    pd.DataFrame(out).to_csv(os.path.join(DATA, "pullback_scalper_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "pullback_scalper_summary.csv"))
