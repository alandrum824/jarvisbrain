"""Gold scalping-pattern mining with a held-out test. READ-ONLY (bars only).

Adam 2026-10-12: "I want you to study gold patterned find a scalping pattern that works and make it an ea".
Method (PRE-REGISTERED before any run):
  DISCOVERY = 2020-01 .. 2023-12, HOLDOUT = 2024-01 .. 2026-10 (never looked at during discovery).
  Unit: price move / ATRd (14-day ATR of daily ranges, yesterday's). Cost per trade = (bar spread + 6 pt markup) in price / ATRd.
  Drift removed: every trade's return is EXCESS over the same-year average of a long position held the same minutes
  (taken at all session minutes), times the trade direction. A pattern can't pass by being long gold in a bull year.
  Families (all holds <= 60 min = scalps):
    A  OPEN MOVE: at event time E (NY: 19:00 Asia, 03:00 London, 08:20 COMEX, 09:30 NY cash, 10:00 fix/data), take the
       direction of the first W minutes (W 5/15), then CONTINUE or FADE it, held H minutes (15/30/60).   5x2x2x3 = 60 cells
    B  HOUR DRIFT: long at the top of each NY hour (0..23, weekdays), held 60 min. Shorts = the negative.  24 cells
    C  SHOCK BAR: an M5 bar 03:00-12:00 NY whose range > 2.5 x the M5 ATR(14) and closes in its outer third; CONTINUE or
       FADE from the next bar open, held H (15/30/60).                                                    6 cells
  Selection: discovery t-stat (net of cost, drift-excess) |t| >= 3.2 (~Bonferroni for 90 cells). For B the sign of t picks
  long or short. Survivors must, on HOLDOUT, keep the same sign with t >= 2.0 AND be positive in each of 2024, 2025, 2026.
  Only those go on to the EA build + coin control + MT5.
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe gold_pattern_mining.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT

MK = 6; DISC_END = 2023
EVENTS = {"ASIA19": 19 * 60, "LDN03": 3 * 60, "COMEX0820": 8 * 60 + 20, "NY0930": 9 * 60 + 30, "FIX10": 10 * 60}


def prep():
    m = load("XAUUSD")
    t = pd.DatetimeIndex(m.ny)
    m["min"] = t.hour * 60 + t.minute; m["day"] = t.normalize(); m["dow"] = t.dayofweek; m["year"] = t.year
    d = m.groupby("day").agg(h=("high", "max"), l=("low", "min"), c=("close", "last"))
    pc = d.c.shift(1)
    tr = np.maximum(d.h - d.l, np.maximum(abs(d.h - pc), abs(d.l - pc)))
    atr = tr.rolling(14).mean().shift(1)            # yesterday's 14-day ATR, no look-ahead
    m["atrd"] = m.day.map(atr)
    return m.dropna(subset=["atrd"]).reset_index(drop=True)


def px_at(T, O, ts):
    """open price of the M1 bar starting exactly at ts (NaN if missing)."""
    i = np.searchsorted(T, ts)
    ok = (i < len(T)) & (T[np.minimum(i, len(T) - 1)] == ts)
    return np.where(ok, O[np.minimum(i, len(T) - 1)], np.nan), np.minimum(i, len(T) - 1), ok


def baseline(m, T, O, holds):
    """same-year mean long move (in ATRd) for each hold, sampled every 5 min across weekday 00-24 NY."""
    s = m[(m.dow < 5) & (m["min"] % 5 == 0)]
    out = {}
    for H in holds:
        p1, _, ok = px_at(T, O, s.ny.values + np.timedelta64(H, "m"))
        r = (p1 - s.open.values) / s.atrd.values
        df = pd.DataFrame({"y": s.year.values, "r": r})[ok]
        out[H] = df.groupby("y").r.mean().to_dict()
    return out


def stats(df):
    r = df.x.values
    if len(r) < 30:
        return dict(n=len(r), mean=np.nan, t=np.nan)
    return dict(n=len(r), mean=r.mean(), t=r.mean() / (r.std(ddof=1) / np.sqrt(len(r))))


def trades_open_move(m, T, O, S, base, E, W, H, mode):
    days = m[(m["min"] == E) & (m.dow < 5)]
    t0 = days.ny.values
    p0 = days.open.values
    pw, iw, ok1 = px_at(T, O, t0 + np.timedelta64(W, "m"))
    ph, _, ok2 = px_at(T, O, t0 + np.timedelta64(W + H, "m"))
    d = np.sign(pw - p0) * (1 if mode == "CONT" else -1)
    cost = (S[iw] + MK) * PT["XAUUSD"]
    y = days.year.values; a = days.atrd.values
    b = np.array([base[H].get(v, 0.0) for v in y])
    x = (d * (ph - pw) - cost) / a - d * b
    keep = ok1 & ok2 & (d != 0)
    return pd.DataFrame({"year": y[keep], "x": x[keep], "d": d[keep]})


def trades_hour(m, T, O, S, base, h):
    s = m[(m["min"] == h * 60) & (m.dow < 5)]
    p1, _, ok = px_at(T, O, s.ny.values + np.timedelta64(60, "m"))
    cost = (s.spread.values + MK) * PT["XAUUSD"]
    y = s.year.values
    b = np.array([base[60].get(v, 0.0) for v in y])
    raw = (p1 - s.open.values) / s.atrd.values - b          # long excess, before cost
    return pd.DataFrame({"year": y[ok], "raw": raw[ok], "c": (cost / s.atrd.values)[ok]})


def trades_shock(m, T, O, S, base, H, mode):
    g = m.set_index("ny").resample("5min", label="left", closed="left")
    b5 = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna()
    hh, ll, cc = b5.high.values, b5.low.values, b5.close.values
    pc = np.roll(cc, 1); pc[0] = cc[0]
    tr = np.maximum(hh - ll, np.maximum(abs(hh - pc), abs(ll - pc)))
    atr = pd.Series(tr).rolling(14).mean().shift(1).values
    t5 = pd.DatetimeIndex(b5.index); mins = t5.hour * 60 + t5.minute
    rng_ = hh - ll
    up = (cc - ll) >= 2 / 3 * rng_; dn = (cc - ll) <= 1 / 3 * rng_
    sel = (rng_ > 2.5 * atr) & (mins >= 180) & (mins < 720) & (t5.dayofweek < 5) & (up | dn)
    t0 = b5.index.values[sel] + np.timedelta64(5, "m")
    d = np.where(up[sel], 1, -1) * (1 if mode == "CONT" else -1)
    p0, i0, ok1 = px_at(T, O, t0)
    p1, _, ok2 = px_at(T, O, t0 + np.timedelta64(H, "m"))
    a = m.atrd.values[i0]; y = pd.DatetimeIndex(t0).year.values
    cost = (S[i0] + MK) * PT["XAUUSD"]
    b = np.array([base[H].get(v, 0.0) for v in y])
    x = (d * (p1 - p0) - cost) / a - d * b
    keep = ok1 & ok2
    return pd.DataFrame({"year": y[keep], "x": x[keep], "d": d[keep]})


if __name__ == "__main__":
    m = prep()
    T, O, S = m.ny.values, m.open.values, m.spread.values
    base = baseline(m, T, O, (15, 30, 60))
    print("baseline long drift per 60 min (ATRd):", {k: round(v, 4) for k, v in base[60].items()}, flush=True)
    rows = []

    def add(fam, name, df):
        dsc, hold = df[df.year <= DISC_END], df[df.year > DISC_END]
        sd, sh = stats(dsc), stats(hold)
        yrs = {y: round(df[df.year == y].x.sum(), 2) for y in sorted(df.year.unique())}
        rows.append(dict(fam=fam, cell=name, n_disc=sd["n"], mean_disc=sd["mean"], t_disc=sd["t"],
                         n_hold=sh["n"], mean_hold=sh["mean"], t_hold=sh["t"],
                         hold_years_pos=sum(yrs.get(y, 0) > 0 for y in (2024, 2025, 2026)), **{f"y{y}": v for y, v in yrs.items()}))

    for en, E in EVENTS.items():
        for W in (5, 15):
            for H in (15, 30, 60):
                for mode in ("CONT", "FADE"):
                    add("A", f"{en} W{W} H{H} {mode}", trades_open_move(m, T, O, S, base, E, W, H, mode))
    for h in range(24):
        hr = trades_hour(m, T, O, S, base, h)
        dsc = hr[hr.year <= DISC_END]
        side = 1 if dsc.raw.mean() >= 0 else -1           # the direction is chosen on DISCOVERY only
        hr["x"] = side * hr.raw - hr.c
        add("B", f"HOUR{h:02d} {'LONG' if side > 0 else 'SHORT'}", hr)
    for H in (15, 30, 60):
        for mode in ("CONT", "FADE"):
            add("C", f"SHOCK H{H} {mode}", trades_shock(m, T, O, S, base, H, mode))

    R = pd.DataFrame(rows)
    R["disc_pass"] = R.t_disc >= 3.2
    R["hold_pass"] = R.disc_pass & (R.t_hold >= 2.0) & (R.hold_years_pos == 3)
    R.sort_values("t_disc", ascending=False).to_csv(r"C:\Users\aland\stg\obh\gold_pattern_mining.csv", index=False)
    pd.set_option("display.width", 220); pd.set_option("display.max_columns", 30)
    cols = ["fam", "cell", "n_disc", "mean_disc", "t_disc", "n_hold", "mean_hold", "t_hold", "hold_years_pos", "disc_pass", "hold_pass"]
    print(R.sort_values("t_disc", ascending=False)[cols].head(15).round(4).to_string(index=False))
    print(f"\ncells {len(R)} | discovery passes {int(R.disc_pass.sum())} | holdout passes {int(R.hold_pass.sum())}")
