"""TWI ORB Momentum vs the FTMO 2-Step Challenge ($10k). READ-ONLY research on the replay trade lists.

FTMO 2-Step rules modelled: Phase 1 target +10%, Phase 2 (Verification) target +5%; Max Daily Loss 5% of the initial
balance (FTMO counts floating P/L; here every trade has a hard stop, so a day's worst case is its stopped trades);
Max Loss 10% of the initial balance (static floor at $9,000); min 4 trading days; no time limit (FTMO removed it), but
attempts still unresolved after 12 months are reported separately. Each phase restarts from a fresh $10,000.
Trades: AAAFx replay lists from orb_momentum_longrun_research.py (EURUSD NY, USDJPY London, 2020-01 -> 2026-10).
Costs: the replay already has spread; FTMO-style commission $7/lot round trip is subtracted in R on top.
Sizing: fixed $ risk = risk% x $10,000 per trade (no compounding). Starts: every Monday 2020-01-06 -> 2025-10-06.
"""
import os
import numpy as np, pandas as pd

D = r"C:\Users\aland\stg\obh"
ACC, TARGETS, DAILY, MAXLOSS = 10000.0, (0.10, 0.05), 0.05, 0.10
COMM = 7.0


def legs():
    e = pd.read_csv(os.path.join(D, "orbmom_EURUSD_NY_trades.csv"), parse_dates=["time"])
    j = pd.read_csv(os.path.join(D, "orbmom_USDJPY_London_trades.csv"), parse_dates=["time"])
    # stop distance in price = px / R (both include the same cost sign) -> $ loss per 1.0 lot at the stop
    for df, per_lot in ((e, lambda s: s * 100000), (j, lambda s: s * 100000 / 140.0)):
        sld = (df.px / df.R).abs()
        df["commR"] = COMM / per_lot(sld)
        df["Rn"] = df.R - df.commR
    e["leg"] = "EURUSD NY"; j["leg"] = "USDJPY London"
    return e, j


def phase(tr, start, risk, target):
    """Walk trades from start. Returns (result, days, end_time). result: pass / fail_daily / fail_max / open."""
    x = tr[tr.time >= start]
    if x.empty:
        return "open", None, None
    bal = ACC; day = None; dayR = 0.0; days = set()
    for t, r in zip(x.time, x.Rn):
        d = t.date()
        if d != day:
            day, dayR = d, 0.0
        pl = r * risk * ACC; bal += pl; dayR += pl; days.add(d)
        if dayR <= -DAILY * ACC:
            return "fail_daily", (t - start).days, t
        if bal <= ACC * (1 - MAXLOSS):
            return "fail_max", (t - start).days, t
        if bal >= ACC * (1 + target) and len(days) >= 4:
            return "pass", (t - start).days, t
    return "open", None, None


def challenge(tr, risk):
    out = []
    for s in pd.date_range("2020-01-06", "2025-10-06", freq="W-MON"):
        r1, d1, t1 = phase(tr, s, risk, TARGETS[0])
        if r1 != "pass":
            out.append(dict(start=s, p1=r1, d1=d1, p2=None, d2=None)); continue
        r2, d2, _ = phase(tr, t1 + pd.Timedelta(days=1), risk, TARGETS[1])
        out.append(dict(start=s, p1=r1, d1=d1, p2=r2, d2=d2))
    return pd.DataFrame(out)


if __name__ == "__main__":
    e, j = legs()
    print(f"commission cost per trade: EURUSD median {e.commR.median():.3f}R, USDJPY median {j.commR.median():.3f}R")
    print(f"net expectancy after FTMO commission: EURUSD {e.Rn.mean():+.3f}R ({len(e)} tr), USDJPY {j.Rn.mean():+.3f}R ({len(j)} tr)")
    both = pd.concat([e, j]).sort_values("time").reset_index(drop=True)
    rows = []
    for name, tr in (("EURUSD NY only", e), ("Both legs", both)):
        print(f"\n=== {name}: {len(tr)} trades, {tr.Rn.sum():+.1f}R net over 2020-26")
        for risk in (0.005, 0.01, 0.015, 0.02, 0.025, 0.03):
            c = challenge(tr, risk); n = len(c)
            p1 = (c.p1 == "pass").mean(); full = (c.p2 == "pass").mean()
            fd = ((c.p1 == "fail_daily") | (c.p2 == "fail_daily")).mean(); fm = ((c.p1 == "fail_max") | (c.p2 == "fail_max")).mean()
            slow1 = ((c.p1 == "pass") & (c.d1 > 365)).mean()
            op = ((c.p1 == "open") | (c.p2 == "open")).mean()
            m1 = c[c.p1 == "pass"].d1.median(); m2 = c[c.p2 == "pass"].d2.median()
            print(f"  risk {risk:.1%}: Phase 1 pass {p1:.0%} (median {m1:.0f} days, {slow1:.0%} took >1 yr) | "
                  f"BOTH phases {full:.0%} (Phase 2 median {m2:.0f} days) | failed: max-loss {fm:.0%}, daily {fd:.0%} | unresolved {op:.0%}  [n={n} starts]", flush=True)
            rows.append(dict(set=name, risk=risk, p1=p1, both=full, fail_max=fm, fail_daily=fd, open=op, med_d1=m1, med_d2=m2, slow1=slow1))
    pd.DataFrame(rows).to_csv(os.path.join(D, "orbmom_ftmo_summary.csv"), index=False)
    print("\nsaved", os.path.join(D, "orbmom_ftmo_summary.csv"))
