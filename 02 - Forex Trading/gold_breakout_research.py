"""Gold breakout research: the logic the publicly successful gold EAs use, replayed on our AAAFx data. READ-ONLY (bars only).

Adam 2026-10-12: "Study goal learn gold charts look at gold EA's all over the Internet see which ones are successful and
start work from there. Build me a EA" -> "Gold". Web survey (vendor pages, see Gold EA Market Survey.md): the gold EAs
with long public records (Profalgo Gold Reaper / Gold Trade Pro, the free MQL5 code-base H4 Donchian, Aurum Range
Breakout) all trade BREAKOUTS on H1/H4 or the Asian range, with a hard stop, no grid. Rules below are copied from
their published descriptions and PRE-REGISTERED (nothing tuned on this data).

  DON_H4 (MQL5 code base 77691, as published): H4 close > highest high of the previous 20 H4 bars (and the bar before
      did not), close > H4 EMA200. Buy next bar open. SL 2 x ATR(20), TP 2R. Short = mirror (author: weaker).
  DON_H1T (Profalgo style: level break + trailing, no fixed TP): H1 close > highest high of the previous 48 H1 bars
      (2 days) and the bar before did not; close > H1 EMA200. SL 2 x ATR(14), then a chandelier trail
      (highest high since entry - 3 x ATR(14)) updated each closed H1 bar. No TP.
  ASIA (Aurum Range Breakout, as published): range 00:00-05:00 GMT; at 05:00 a buy stop at high + 5% of the width and a
      sell stop at low - 5%, OCO; SL = the other side of the range, TP 1R; unfilled orders cancelled 15:00 GMT, trade
      closed 16:00 GMT; day skipped if the range < 0.10 or > 0.80 x daily ATR(14).
Costs: real bar spread (+6 pt markup on gold); long pays the ask on entry, short pays it on exit. Swap ignored (caveat).
Swing families resolve on H1 bars (SL first if a bar hits both); ASIA resolves on M1. One position at a time per cell.
Controls (50 seeds):
  COIN  = same entry times, stop distance and exit rule, coin-flip direction.
  DRIFT = long-only cells: the same number of entries at random H1 bars, long, same stop and exit rule.
          Gold went ~1,500 -> ~4,000 in 2020-26, so "buy and hold a while" makes money; a breakout has to beat that.
Pass bar (EA Scorecard): positive in >= 5 of 7 years, PF > 1, beats >= 95% of COIN and (long-only) >= 95% of DRIFT.
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe gold_breakout_research.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT

DATA = r"C:\Users\aland\stg\obh"
SYM = "XAUUSD"; MK = 6; SEEDS = 50


def ema(x, n):
    return pd.Series(x).ewm(span=n, adjust=False).mean().values


def atr_rma(h, l, c, n):
    pc = np.roll(c, 1); pc[0] = c[0]
    tr = np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
    a = np.full(len(tr), np.nan); a[n - 1] = tr[:n].mean()
    for i in range(n, len(tr)):
        a[i] = (a[i - 1] * (n - 1) + tr[i]) / n
    return a


def bars(m1, rule, offset=None):
    g = m1.set_index("ny").resample(rule, label="left", closed="left", offset=offset)
    return pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last(),
                         "spread": g.spread.median()}).dropna().reset_index()


# ---------------- swing families (H1 / H4 signals, resolved on H1) ----------------
def don_signals(b, look, atr_n, emaN, short):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    e, A = ema(C, emaN), atr_rma(H, L, C, atr_n)
    hh = pd.Series(H).shift(1).rolling(look).max().values
    ll = pd.Series(L).shift(1).rolling(look).min().values
    sig = []
    for j in range(max(look, emaN) + 1, len(b) - 1):
        if not A[j] > 0:
            continue
        if C[j] > hh[j] and not C[j - 1] > hh[j - 1] and C[j] > e[j]:
            sig.append((b.ny.values[j + 1], 1, A[j]))
        elif short and C[j] < ll[j] and not C[j - 1] < ll[j - 1] and C[j] < e[j]:
            sig.append((b.ny.values[j + 1], -1, A[j]))
    return sig


def sim_swing(h1, a14, sig, mode, rng=None, flip=False):
    T = h1.ny.values; O, H, L, C = (h1[k].values for k in ("open", "high", "low", "close"))
    SP = (h1.spread.values + MK) * PT[SYM]
    rows = []; busy = -1
    for t, d, a in sig:
        k = int(np.searchsorted(T, t))
        if k >= len(T) - 1 or k <= busy:
            continue
        if flip:
            d = 1 if rng.random() < 0.5 else -1
        sp = SP[k]
        entry = O[k] + (sp if d == 1 else 0)
        risk = 2 * a
        sl = entry - d * risk; tp = entry + d * 2 * risk if mode == "TP2R" else None
        ext = entry; exitpx = None; m = k
        for m in range(k, len(T)):
            sh = 0 if d == 1 else SP[m]           # short exits pay the ask
            lo, hi, op = L[m] + sh, H[m] + sh, O[m] + sh
            if d * (sl - (lo if d == 1 else hi)) >= 0:    # stop touched
                exitpx = op if (m > k and d * (op - sl) < 0) else sl; break
            if tp is not None and d * ((hi if d == 1 else lo) - tp) >= 0:
                exitpx = op if (m > k and d * (op - tp) > 0) else tp; break
            if mode == "TRAIL":
                ext = max(ext, H[m]) if d == 1 else min(ext, L[m])
                if a14[m] > 0:
                    nsl = ext - d * 3 * a14[m]
                    if d * (nsl - sl) > 0:
                        sl = nsl
        if exitpx is None:
            exitpx = C[m] + (0 if d == 1 else SP[m])
        busy = m
        rows.append((pd.Timestamp(T[k]).year, d, d * (exitpx - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


def drift_signals(h1, a, n, rng, lo_idx):
    dow = pd.DatetimeIndex(h1.ny.values).dayofweek
    ok = np.flatnonzero((dow < 5) & (a > 0) & (np.arange(len(h1)) > lo_idx))[:-1]
    pick = np.sort(rng.choice(ok, size=n, replace=False))
    return [(h1.ny.values[i + 1], 1, a[i]) for i in pick]


# ---------------- ASIA range breakout (M1) ----------------
def asia(m1, rng=None, tpR=1.0, hold=None):
    """tpR = target in R; hold = max minutes in the trade (exit at market), None = until 16:00 GMT."""
    utc = pd.DatetimeIndex(m1.ny).tz_localize("America/New_York", ambiguous="NaT", nonexistent="NaT").tz_convert("UTC")
    m1 = m1.assign(utc=utc.tz_localize(None)).dropna(subset=["utc"]).reset_index(drop=True)
    O, H, L, C = (m1[k].values for k in ("open", "high", "low", "close"))
    SP = (m1.spread.values + MK) * PT[SYM]
    U = m1.utc.values; day = m1.utc.dt.normalize().values; mins = (m1.utc.dt.hour * 60 + m1.utc.dt.minute).values
    d1 = m1.groupby(day).agg(high=("high", "max"), low=("low", "min"), close=("close", "last"))
    da = atr_rma(d1.high.values, d1.low.values, d1.close.values, 14)
    datr = dict(zip(d1.index.values, np.roll(da, 1)))          # yesterday's ATR (no look-ahead)
    starts = np.flatnonzero(np.r_[True, day[1:] != day[:-1]]); ends = np.r_[starts[1:], len(m1)]
    rows = []
    for s, e in zip(starts, ends):
        dd = day[s]; at = datr.get(dd, np.nan)
        if pd.Timestamp(dd).dayofweek >= 5 or not at > 0:
            continue
        mm = mins[s:e]
        r = np.flatnonzero(mm < 300)
        if len(r) < 200:
            continue
        hi, lo = H[s + r].max(), L[s + r].min(); w = hi - lo
        if w < 0.10 * at or w > 0.80 * at:
            continue
        bs, ss = hi + 0.05 * w, lo - 0.05 * w
        act = np.flatnonzero((mm >= 300) & (mm < 900))
        if not len(act):
            continue
        fill = None
        for i in s + act:
            up = H[i] + SP[i] >= bs; dn = L[i] <= ss
            if up and dn:
                break
            if up or dn:
                fill = (i, 1 if up else -1); break
        if fill is None:
            continue
        i, d = fill
        entry = max(bs, O[i] + SP[i]) if d == 1 else min(ss, O[i])
        stop = ss if d == 1 else bs
        if rng is not None:                      # coin: same minute, same risk, random side
            d = 1 if rng.random() < 0.5 else -1
            entry = C[i] + (SP[i] if d == 1 else 0)
            risk = bs - ss
            stop = entry - d * risk
        risk = d * (entry - stop)
        if risk <= 0:
            continue
        tp = entry + d * tpR * risk
        close_i = s + np.flatnonzero(mm < 960)[-1]
        if hold is not None:
            close_i = min(close_i, i + hold)
        px = None
        for m in range(i + 1, close_i + 1):
            sh = 0 if d == 1 else SP[m]
            if d * (stop - ((L[m] + sh) if d == 1 else (H[m] + sh))) >= 0:
                px = stop; break
            if d * (((H[m] + sh) if d == 1 else (L[m] + sh)) - tp) >= 0:
                px = tp; break
        if px is None:
            px = C[close_i] + (0 if d == 1 else SP[close_i])
        rows.append((pd.Timestamp(dd).year, d, d * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


def summ(R):
    if len(R) == 0:
        return dict(n=0, tot=0.0, avg=0.0, win=0.0, pf=0.0)
    r = R.R
    return dict(n=len(R), tot=r.sum(), avg=r.mean(), win=(r > 0).mean(), pf=r[r > 0].sum() / max(-r[r < 0].sum(), 1e-12))


def report(name, real, coin, drift=None):
    s = summ(real)
    yr = {y: real[real.year == y].R.sum() for y in sorted(real.year.unique())}
    pos = sum(v > 0 for v in yr.values())
    bc = (np.array(coin) < s["tot"]).mean()
    bd = (np.array(drift) < s["tot"]).mean() if drift is not None else None
    ok = pos >= 5 and s["pf"] > 1 and bc >= 0.95 and (bd is None or bd >= 0.95)
    print(f"  {name:12s}: {s['n']:5d} tr {s['tot']:+8.1f}R avg {s['avg']:+.3f} win {s['win']:.0%} PF {s['pf']:.2f} | years+ {pos}/{len(yr)} | "
          f"coin med {np.median(coin):+7.1f}R beats {bc:.0%}" + (f" | drift med {np.median(drift):+7.1f}R beats {bd:.0%}" if bd is not None else "")
          + f" | {'PASS' if ok else 'fail'}", flush=True)
    print("        " + "  ".join(f"{y}:{v:+.1f}" for y, v in yr.items()), flush=True)
    return dict(cell=name, n=s["n"], R=s["tot"], avg=s["avg"], win=s["win"], pf=s["pf"], years_pos=pos, years=len(yr),
                coin_med=np.median(coin), beats_coin=bc, drift_med=np.median(drift) if drift is not None else np.nan,
                beats_drift=bd if bd is not None else np.nan, passed=ok, **{f"y{y}": v for y, v in yr.items()})


if __name__ == "__main__":
    m1 = load(SYM)
    h1 = bars(m1, "1h"); h4 = bars(m1, "4h", offset="2h")
    H1a14 = atr_rma(h1.high.values, h1.low.values, h1.close.values, 14)
    # H4 ATR(20) of the last CLOSED H4 bar, on the H1 grid (for the DRIFT control's stops)
    H4a20 = atr_rma(h4.high.values, h4.low.values, h4.close.values, 20)
    k4 = np.searchsorted(h4.ny.values, h1.ny.values + np.timedelta64(1, "h") - np.timedelta64(4, "h"), side="right") - 1
    H4on1 = np.where(k4 >= 0, H4a20[np.clip(k4, 0, None)], np.nan)
    print(f"##### {SYM}: {h1.ny.iloc[0]:%Y-%m-%d} -> {h1.ny.iloc[-1]:%Y-%m-%d}", flush=True)
    out = []
    cells = [("DON_H4 LONG", don_signals(h4, 20, 20, 200, False), "TP2R"),
             ("DON_H4 BOTH", don_signals(h4, 20, 20, 200, True), "TP2R"),
             ("DON_H1T LONG", don_signals(h1, 48, 14, 200, False), "TRAIL"),
             ("DON_H1T BOTH", don_signals(h1, 48, 14, 200, True), "TRAIL")]
    for name, sig, mode in cells:
        real = sim_swing(h1, H1a14, sig, mode)
        rng = np.random.default_rng(20261012)
        coin = [summ(sim_swing(h1, H1a14, sig, mode, rng, flip=True))["tot"] for _ in range(SEEDS)]
        drift = None
        if "LONG" in name:
            aref = H4on1 if "H4" in name else H1a14
            drift = [summ(sim_swing(h1, H1a14, drift_signals(h1, aref, len(sig), rng, 800), mode))["tot"] for _ in range(SEEDS)]
        out.append(report(name, real, coin, drift))
    real = asia(m1)
    rng = np.random.default_rng(20261012)
    coin = [summ(asia(m1, rng))["tot"] for _ in range(SEEDS)]
    out.append(report("ASIA BOTH", real, coin))
    pd.DataFrame(out).to_csv(os.path.join(DATA, "gold_breakout_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "gold_breakout_summary.csv"))
