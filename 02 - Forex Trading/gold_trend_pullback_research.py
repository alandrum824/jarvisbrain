"""Replay of GoldTrendPullback_v1.00.mq5 (Adam's upload 2026-10-12; header credits andamagodwin/forex XauScalper). READ-ONLY.

Rules exactly as the EA codes them (M5, closed bar 1, next-bar-open entry):
  LONG : close > EMA200, EMA21 > EMA200, close > EMA9, bullish bar, EMA9 > EMA21, a low touched EMA21 within the last 5
         bars (incl. bar 1), RSI(14) in (45, 70) and rising, ADX(14) >= 25, bar range < 3 x ATR(14).
  SHORT: mirror EXCEPT the RSI gate, which the EA leaves un-mirrored (RSI 45-70 and RISING for shorts too) -> AS_CODED.
         FIXED_RSI = the intended mirror (RSI in (30, 55) and falling).
  SL = max(1.5 x ATR, $1.50), TP = 1R, time stop 60 bars, new entries 07-17 UTC (Fri until 15), flat 21:00 UTC,
  one position, 5-bar cooldown after a loss, max 8 trades/day, daily lock at -4R (= 2% at 0.5%/trade).
  Spread cap $0.45: AAAFx gold runs ~52 pts, so the cap is reported separately (CAP45 = as coded on AAAFx).
Costs: real bar spread + 6 pt markup; exits on M1. Control: 50-seed coin flip. Gold 2020-26.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import bars, ema, atr_rma, first_hit
from gold_breakout_research import summ, report

MK = 6; SEEDS = 50


def wilder(x, n):
    out = np.full(len(x), np.nan); out[n] = np.nanmean(x[1:n + 1])
    for i in range(n + 1, len(x)):
        out[i] = (out[i - 1] * (n - 1) + x[i]) / n
    return out


def rsi(c, n=14):
    d = np.diff(c, prepend=c[0])
    up, dn = wilder(np.maximum(d, 0), n), wilder(np.maximum(-d, 0), n)
    return 100 - 100 / (1 + up / np.where(dn == 0, 1e-12, dn))


def adx(h, l, c, n=14):
    up = np.diff(h, prepend=h[0]); dn = -np.diff(l, prepend=l[0])
    pdm = np.where((up > dn) & (up > 0), up, 0.0); mdm = np.where((dn > up) & (dn > 0), dn, 0.0)
    pc = np.roll(c, 1); pc[0] = c[0]
    tr = np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
    atr_, p, m = wilder(tr, n), wilder(pdm, n), wilder(mdm, n)
    pdi, mdi = 100 * p / atr_, 100 * m / atr_
    dx = 100 * abs(pdi - mdi) / np.where(pdi + mdi == 0, 1e-12, pdi + mdi)
    return wilder(np.nan_to_num(dx), n)


def signals(b, short_rsi):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    e9, e21, e200 = ema(C, 9), ema(C, 21), ema(C, 200)
    R, X, A = rsi(C), adx(H, L, C), atr_rma(H, L, C)
    utc = pd.DatetimeIndex(b.ny.values).tz_localize("America/New_York", ambiguous="NaT", nonexistent="NaT").tz_convert("UTC")
    sig = []
    for j in range(210, len(b) - 1):
        if pd.isna(utc[j]):
            continue
        hr, dw = utc[j].hour, utc[j].dayofweek
        if dw >= 5 or hr < 7 or hr >= 17 or (dw == 4 and hr >= 15):
            continue
        if not (A[j] > 0) or (H[j] - L[j]) >= 3 * A[j] or X[j] < 25:
            continue
        lmom = 45 < R[j] < 70 and R[j] > R[j - 1]
        smom = lmom if short_rsi == "AS_CODED" else (30 < R[j] < 55 and R[j] < R[j - 1])
        touchL = (L[j - 5:j + 1] <= e21[j - 5:j + 1]).any(); touchS = (H[j - 5:j + 1] >= e21[j - 5:j + 1]).any()
        if lmom and C[j] > e200[j] and e21[j] > e200[j] and C[j] > e9[j] and C[j] > O[j] and e9[j] > e21[j] and touchL:
            sig.append((j, 1))
        elif smom and C[j] < e200[j] and e21[j] < e200[j] and C[j] < e9[j] and C[j] < O[j] and e9[j] < e21[j] and touchS:
            sig.append((j, -1))
    return sig, A, utc


def run(m1, b, sig, A, utc, cap, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    T = m1.ny.values; pt = PT["XAUUSD"]
    rows = []; busy = -1; cool_until = -1; day = None; nday = 0; dayR = 0.0
    for j, d in sig:
        if j <= cool_until:
            continue
        k = int(np.searchsorted(T, b.ny.values[j + 1]))
        if k >= len(T) or k <= busy:
            continue
        if cap and S[k] * pt > 0.45:
            continue
        ud = utc[j].date()
        if ud != day:
            day, nday, dayR = ud, 0, 0.0
        if nday >= 8 or dayR <= -4:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
        sp = (S[k] + MK) * pt
        entry = O[k] + (sp if d == 1 else 0)
        risk = max(1.5 * A[j], 1.50)
        sl, tp = entry - d * risk, entry + d * risk
        flat = utc[j].normalize() + pd.Timedelta(hours=21)
        flat_ny = flat.tz_convert("America/New_York").tz_localize(None).to_datetime64()
        end = min(int(np.searchsorted(T, flat_ny)), int(np.searchsorted(T, b.ny.values[j + 1] + np.timedelta64(300, "m"))))
        if end <= k:
            continue
        h = first_hit(H, L, O, S, k, end, d, sl, tp, pt, MK)
        if h is None:
            m = end - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * pt)
        else:
            m, px = h
        r = d * (px - entry) / risk
        busy = m; nday += 1; dayR += r
        if r < 0:   # 5-bar cooldown after a loss, counted from the exit bar
            cool_until = int(np.searchsorted(b.ny.values, T[m])) + 5
        rows.append((pd.Timestamp(T[k]).year, d, r))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = load("XAUUSD"); b = bars(m1, "5min")
    print("AAAFx gold bar spread median (pts):", float(np.median(m1.spread.values)),
          "| share of M1 bars with spread <= 45 pts:", round(float((m1.spread.values <= 45).mean()), 3), flush=True)
    for mode in ("AS_CODED", "FIXED_RSI"):
        sig, A, utc = signals(b, mode)
        for cap in (True, False):
            real = run(m1, b, sig, A, utc, cap)
            rng = np.random.default_rng(20261012)
            coin = [summ(run(m1, b, sig, A, utc, cap, rng))["tot"] for _ in range(SEEDS)]
            report(f"{mode} {'CAP45' if cap else 'NOCAP'}", real, coin)
            for dd, n in ((1, "LONG"), (-1, "SHORT")):
                x = real[real.d == dd]; s = summ(x)
                print(f"    {n}: {s['n']} tr {s['tot']:+.1f}R PF {s['pf']:.2f} win {s['win']:.0%}", flush=True)
