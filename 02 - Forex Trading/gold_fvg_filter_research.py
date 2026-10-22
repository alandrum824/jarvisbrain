"""FVG filtering on gold (Adam's "FVG Filtering" image, Expertsbazaar, 2026-10-13). READ-ONLY replay, PRE-REGISTERED.
Picture: a leg up leaves several FVGs; on the pullback the upper gaps are closed through (X) and the trade is taken at the
deeper gap that holds. Bull FVG at middle bar i: low[i+1] > high[i-1], size >= 0.1 x ATR14; zone bottom = high[i-1],
top = low[i+1]. Bear = mirror. A gap is DEAD once a bar closes through its far edge. Watched from bar i+2 for 96 bars.
  NAIVE        : every gap, limit at the near edge (top) on the first touch, SL = bottom - 0.1 ATR (realistic ask fills).
  RESPECT      : first touch bar must NOT close through the bottom -> market at the next open, SL = min(touch low,
                 bottom) - 0.1 ATR. A touch that closes through = dead, no trade.
  RESPECT_STACK: RESPECT, and at least one NEWER same-direction gap (formed after this one) died before the touch
                 (the picture: upper gaps X'd, deeper gap holds).
TP 2R, max hold 48 bars, one trade at a time per variant. M15 and H1, gold 2020-26, real spread +6 pt, exits M1.
Control: coin flip (30-50 seeds). Pass bar = EA Scorecard.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report
import gold_three_areas_research as ta
import gold_three_methods_research as tm


def setups(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    n = len(b); gaps = []
    for i in range(15, n - 100):
        a = A[i]
        if not a > 0: continue
        for d in (1, -1):
            bot, top = (H[i - 1], L[i + 1]) if d == 1 else (L[i - 1], H[i + 1])
            if d * (top - bot) < 0.1 * a: continue
            inv = touch = None
            for j in range(i + 2, i + 98):
                if touch is None and (L[j] <= top if d == 1 else H[j] >= top): touch = j
                if d * (C[j] - bot) < 0: inv = j; break
            gaps.append(dict(i=i, d=d, bot=bot, top=top, a=a, inv=inv, touch=touch))
    naive, resp, stack = [], [], []
    by_d = {1: [g for g in gaps if g["d"] == 1], -1: [g for g in gaps if g["d"] == -1]}
    for g in gaps:
        i, d, j = g["i"], g["d"], g["touch"]
        if j is None: continue
        yr = pd.Timestamp(T[i]).year
        naive.append(dict(t0=T[i + 2], t1=T[min(i + 98, n - 1)], d=d, entry=g["top"], stop=g["bot"] - d * 0.1 * g["a"], yr=yr))
        if d * (C[j] - g["bot"]) < 0 or j + 1 >= n - 49: continue
        ext = min(L[j], g["bot"]) if d == 1 else max(H[j], g["bot"])
        sig = (T[j + 1], d, ext - d * 0.1 * g["a"], T[j + 49], yr)
        resp.append(sig)
        if any(i < h["i"] < j and h["inv"] is not None and h["inv"] < j for h in by_d[d]):
            stack.append(sig)
    key = lambda s: s[0]
    return sorted(naive, key=lambda s: s["t0"]), sorted(resp, key=key), sorted(stack, key=key)


if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf, mins in (("15min", 15), ("1h", 60)):
        naive, resp, stack = setups(bars(m1, tf))
        print(f"##### {tf}: gaps touched {len(naive)} | respect {len(resp)} | stack {len(stack)}", flush=True)
        real = ta.run(m1, naive, mins); rng = np.random.default_rng(20261013)
        report(f"NAIVE {tf}", real, [summ(ta.run(m1, naive, mins, rng))["tot"] for _ in range(30)])
        for name, sig in (("RESPECT", resp), ("RESPECT_STACK", stack)):
            real = tm.run(m1, sig); rng = np.random.default_rng(20261013)
            report(f"{name} {tf}", real, [summ(tm.run(m1, sig, rng))["tot"] for _ in range(50)])
