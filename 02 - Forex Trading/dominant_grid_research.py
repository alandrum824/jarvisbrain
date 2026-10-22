"""DOMINANT EA PRO V6.3 (jeebsoft) money-management replica vs a capped "fixed" version. READ-ONLY research.

The real EA is a locked commercial .ex5 (USER_KEY), so its ENTRY logic is unknown. The settings screenshot only shows it
uses MA 20, ATR 5, MACD 5/20/5 and Bollinger 20/2. Entries here are therefore two stand-ins:
  BB  = M5 candle wicks outside Bollinger(20,2) and closes back inside, with MACD(5,20,5) main crossing its signal in the
        trade direction (a typical grid-EA mean-reversion entry), and
  RAND = random M5 bars, random direction (shows what the money management does on its own).
Money management from the screenshot (points are broker points: gold 0.01, GBPUSD 0.00001; $1 per point per 1.0 lot on both):
  ORIGINAL: SL 0; aggressive mode -> 4 x 0.01 at entry; add every 50 points against the last fill, lot x1.5 per add
            (rounded up to 0.01, single add capped at 8.0 lots), up to 25 adds; unified basket TP +150 points from the
            average price; breakeven: at +70 points lock +30; close all if the floating loss reaches 50% of balance.
  FIXED:    same entries, same TP/BE, but lot x1.0 (flat adds), max 3 adds, and a hard basket stop at -3% of balance.
Simulated on M1 bars (bid OHLC + bar spread, +6 pts gold markup). Adverse side of a bar is processed before the
favourable side (pessimistic). $400 start, fixed lots (as the settings). The close-all % is of the balance when the
basket opened. BLOWUP = balance below $50 (can't keep trading): counted, and a fresh $400 is deposited so the run continues.
NET = final balance - every $400 deposited. Margin is NOT modelled (a $400 account would be stopped out by margin long
before the original's max lots), so the original's real outcome is worse than shown.
Data: C:/Users/aland/stg/obh/<SYM>_M1.csv (AAAFx, 2020-01-02 -> 2026-10-09).
"""
import os, math
import numpy as np, pandas as pd

DATA = r"C:\Users\aland\stg\obh"
SYMS = {"XAUUSD": (0.01, 6), "GBPUSD": (0.00001, 0)}
CONTRACT = {"XAUUSD": 100, "GBPUSD": 100000}
LEV, STOPOUT = 500.0, 0.50
START = 400.0
CFG = {
    "ORIGINAL": dict(base=[0.01] * 4, mult=1.5, maxadd=25, addcap=8.0, step=50, tp=150, be_start=70, be_lock=30, kill_pct=50.0),
    "FIXED":    dict(base=[0.01] * 4, mult=1.0, maxadd=3,  addcap=8.0, step=50, tp=150, be_start=70, be_lock=30, kill_pct=3.0),
}


def load(sym):
    df = pd.read_csv(os.path.join(DATA, f"{sym}_M1.csv"))
    df["time"] = pd.to_datetime(df.time_server, format="%Y.%m.%d %H:%M")
    return df.drop(columns="time_server").sort_values("time").drop_duplicates("time").reset_index(drop=True)


def bb_signals(m1):
    m5 = m1.set_index("time").resample("5min", label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last"}).dropna().reset_index()
    c = m5.close
    mid = c.rolling(20).mean(); sd = c.rolling(20).std(ddof=0)
    up, lo = mid + 2 * sd, mid - 2 * sd
    macd = c.ewm(span=5, adjust=False).mean() - c.ewm(span=20, adjust=False).mean()
    sig = macd.ewm(span=5, adjust=False).mean()
    xu = (macd > sig) & (macd.shift() <= sig.shift()); xd = (macd < sig) & (macd.shift() >= sig.shift())
    buy = (m5.low < lo) & (c > lo) & xu
    sell = (m5.high > up) & (c < up) & xd
    t = m5.time + pd.Timedelta(minutes=5)  # act at the next bar open
    out = [(tt, 1) for tt in t[buy]] + [(tt, -1) for tt in t[sell]]
    return sorted(out)


def rand_signals(m1, n, rng):
    t = m1.time.values
    idx = np.sort(rng.choice(np.arange(1000, len(t) - 10), size=n, replace=False))
    return [(pd.Timestamp(t[i]), int(rng.choice([-1, 1]))) for i in idx]


def run(m1, sigs, pt, mk, c, contract):
    T = m1.time.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    n = len(T); bal = START; peak = START; maxdd = 0.0
    baskets = wins = blowups = kills = stopouts = 0; worst = 0.0; maxlots = 0.0; first_blow = None; busy = 0
    for st, d in sigs:
        k = int(np.searchsorted(T, np.datetime64(st)))
        if k <= busy or k >= n or pd.Timestamp(T[k]).dayofweek >= 5:
            continue
        sp0 = (S[k] + mk) * pt
        px = O[k] + sp0 if d == 1 else O[k]           # fill price (ask for buys, bid for sells)
        fills = [(px, l) for l in c["base"]]; last = px; adds = 0; addlot = sum(c["base"])
        be_lock = None; start_bal = bal; closed = None
        for m in range(k, n):
            sp = (S[m] + mk) * pt
            adv = L[m] if d == 1 else H[m] + sp           # price we could close at, worst point of the bar
            fav = H[m] if d == 1 else L[m] + sp
            # adds on the adverse side
            while adds < c["maxadd"] and d * (last - adv) >= c["step"] * pt - 1e-12:
                nl = min(c["addcap"], math.ceil(addlot * c["mult"] * 100 - 1e-9) / 100) if c["mult"] != 1.0 else c["base"][0]
                lv = last - d * c["step"] * pt
                lt = sum(l for _, l in fills) + nl; av = (sum(p * l for p, l in fills) + lv * nl) / lt
                if bal + d * (lv - av) / pt * lt - lt * lv * contract / LEV < 0:
                    break                                   # broker refuses: not enough free margin
                last, addlot = lv, nl; fills.append((last, addlot)); adds += 1; be_lock = None
            lots = sum(l for _, l in fills); avg = sum(p * l for p, l in fills) / lots
            maxlots = max(maxlots, lots)
            pl_adv = d * (adv - avg) / pt * lots           # $ (1$/point/lot)
            if pl_adv <= -c["kill_pct"] / 100 * start_bal:
                closed = (-c["kill_pct"] / 100 * start_bal, "kill"); break
            if (bal + pl_adv) / (lots * adv * contract / LEV) < STOPOUT:
                closed = (pl_adv, "stopout"); break
            if be_lock is not None and d * (adv - (avg + d * be_lock * pt)) <= 0:
                closed = (be_lock * lots, "be"); break
            if d * (fav - avg) >= c["tp"] * pt:
                closed = (c["tp"] * lots, "tp"); break
            if be_lock is None and d * (fav - avg) >= c["be_start"] * pt:
                be_lock = c["be_lock"]
        if closed is None:
            break
        pl, why = closed; busy = m; baskets += 1
        bal += pl; worst = min(worst, pl)
        if pl > 0:
            wins += 1
        if why == "kill":
            kills += 1
        if why == "stopout":
            stopouts += 1
        peak = max(peak, bal); maxdd = max(maxdd, (peak - bal) / peak)
        if bal < 50:
            blowups += 1; first_blow = first_blow or pd.Timestamp(T[m]); bal = START; peak = START
    return dict(baskets=baskets, win=wins / max(baskets, 1), blowups=blowups, kills=kills, end_bal=bal,
                worst=worst, maxlots=maxlots, maxdd=maxdd, first_blow=first_blow, stopouts=stopouts, net=bal - START * (1 + blowups))


if __name__ == "__main__":
    rng = np.random.default_rng(20261011)
    for sym, (pt, mk) in SYMS.items():
        m1 = load(sym)
        bb = bb_signals(m1); rs = rand_signals(m1, len(bb), rng)
        print(f"\n=== {sym} {m1.time.iloc[0]:%Y-%m-%d} -> {m1.time.iloc[-1]:%Y-%m-%d}  ({len(bb)} BB/MACD signals)", flush=True)
        for sname, sigs in (("BB/MACD", bb), ("RANDOM", rs)):
            for cname, c in CFG.items():
                r = run(m1, sigs, pt, mk, c, CONTRACT[sym])
                fb = f"{r['first_blow']:%Y-%m-%d}" if r["first_blow"] is not None else "-"
                print(f"  {sname:8s} {cname:8s}: baskets {r['baskets']:5d}  win {r['win']:.1%}  BLOWUPS {r['blowups']:3d} "
                      f"(first {fb})  margin stop-outs {r['stopouts']:3d}  basket stops {r['kills']:4d}  worst basket ${r['worst']:8.2f}  max lots held {r['maxlots']:.2f}  "
                      f"max DD {r['maxdd']:.0%}  NET ${r['net']:,.2f}", flush=True)
