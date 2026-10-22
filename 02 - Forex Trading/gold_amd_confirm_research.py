"""AMD fake-out reversal + confirmation-candle retest on the gold Asia range (Adam's chart-lesson images, 2026-10-13).
READ-ONLY replay, PRE-REGISTERED:
  Range 00-05 GMT + ATR filter + first M5 close beyond the range before 15:00 (as gold_sniper_research.build_days).
  AMD_REVERSAL ("manipulation" failed): after the breakout close, if an M5 bar CLOSES back inside the range within 12 bars
     (1 hour), enter OPPOSITE at the next M5 open. SL = the manipulation extreme (highest high / lowest low since the
     breakout) +/- 0.25 x ATR(M5). TP = the far side of the range (sell-side / buy-side liquidity); skipped if < 1R.
  CONFIRM_RETEST: after the breakout close, wait (until 15:00) for an M5 bar that touches the broken edge AND is a
     rejection candle in the breakout direction (bull: lower wick >= 50% of the bar's range and close in the upper half;
     bear mirrored) = pin bar / wick rejection. Enter at the next M5 open; SL = range midpoint; TP = measured move
     (edge +/- width), skipped if < 1R.
Exits on M1 with real spread (+6 pt), flat 16:00 GMT. Control: 50-seed coin flip. Pass bar = EA Scorecard.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pullback_scalper_research import first_hit
from gold_breakout_research import summ, report
import gold_sniper_research as sn

MK = 6; PTG = 0.01; SEEDS = 50


def make(m1, days):
    U = m1.utc.values; O1 = m1.open.values; S = m1.spread.values
    g = m1.set_index("utc").resample("5min", label="left", closed="left")
    m5 = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()
    T5 = m5.utc.values; O5, H5, L5, C5 = (m5[k].values for k in ("open", "high", "low", "close"))
    amd, conf = [], []
    for s in days:
        d, hi, lo, w = s["d"], s["hi"], s["lo"], s["w"]
        b = int(np.searchsorted(T5, s["t_place"])) - 1
        e15 = int(np.searchsorted(T5, s["t_cancel"]))
        ke = int(np.searchsorted(U, s["t_close"]))
        # AMD reversal
        for j in range(b + 1, min(b + 13, e15)):
            if lo < C5[j] < hi:
                ext = H5[b:j + 1].max() if d == 1 else L5[b:j + 1].min()
                rd = -d
                k = int(np.searchsorted(U, T5[j] + np.timedelta64(5, "m")))
                if k < ke - 1:
                    sp = (S[k] + MK) * PTG
                    entry = O1[k] + (sp if rd == 1 else 0)
                    sl = ext + d * 0.25 * s["a5"]           # beyond the manipulation extreme
                    risk = rd * (entry - sl)
                    tp = lo if rd == -1 else hi
                    tpR = rd * (tp - entry) / risk if risk > 0 else 0
                    if risk > 0 and tpR >= 1:
                        amd.append(dict(year=s["day"].year, d=rd, k=k, ke=ke, entry=entry, risk=risk, tpR=tpR))
                break
        # confirmation-candle retest
        edge = hi if d == 1 else lo
        for j in range(b + 1, e15):
            rng_ = H5[j] - L5[j]
            if rng_ <= 0:
                continue
            if d == 1:
                ok = L5[j] <= edge and (min(O5[j], C5[j]) - L5[j]) >= 0.5 * rng_ and C5[j] >= L5[j] + 0.5 * rng_
            else:
                ok = H5[j] >= edge and (H5[j] - max(O5[j], C5[j])) >= 0.5 * rng_ and C5[j] <= H5[j] - 0.5 * rng_
            if ok:
                k = int(np.searchsorted(U, T5[j] + np.timedelta64(5, "m")))
                if k < ke - 1:
                    sp = (S[k] + MK) * PTG
                    entry = O1[k] + (sp if d == 1 else 0)
                    risk = d * (entry - (hi + lo) / 2)
                    tpR = d * ((edge + d * w) - entry) / risk if risk > 0 else 0
                    if risk > 0 and tpR >= 1:
                        conf.append(dict(year=s["day"].year, d=d, k=k, ke=ke, entry=entry, risk=risk, tpR=tpR))
                break
    return pd.DataFrame(amd), pd.DataFrame(conf)


def resolve(m1, tr, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    out = []
    for r in tr.itertuples():
        d, entry = r.d, r.entry
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            entry = O[r.k] + ((S[r.k] + MK) * PTG if d == 1 else 0)
        sl = entry - d * r.risk; tp = entry + d * r.tpR * r.risk
        h = first_hit(H, L, O, S, r.k, r.ke, d, sl, tp, PTG, MK)
        if h is None:
            m = r.ke - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * PTG)
        else:
            m, px = h
        out.append((r.year, d, d * (px - entry) / r.risk))
    return pd.DataFrame(out, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = sn.prep(); days = sn.build_days(m1)
    amd, conf = make(m1, days)
    for name, tr in (("AMD_REVERSAL", amd), ("CONFIRM_RETEST", conf)):
        real = resolve(m1, tr)
        rng = np.random.default_rng(20261013)
        coin = [summ(resolve(m1, tr, rng))["tot"] for _ in range(SEEDS)]
        report(name, real, coin)
        print(f"    median risk ${tr.risk.median():.2f}, median target {tr.tpR.median():.2f}R, long {real[real.d==1].R.sum():+.1f}R / short {real[real.d==-1].R.sum():+.1f}R", flush=True)
