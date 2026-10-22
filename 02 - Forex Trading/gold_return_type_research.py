"""Return type into a zone (Adam's "Supply zone - different returns" image, 2026-10-13). PRE-REGISTERED filter on the
DEMAND1 and GAP_DEEP setups of gold_three_areas_research (impulse >= 1.5 ATR + FVG, limit entries, 2R, realistic fills).
On the setup timeframe, the return leg = bars from impulse+2 up to (NOT including) the bar that trades through the entry
price - only information known at fill time. (A first run including the fill bar had lookahead and is void.)
  REVERSAL return (skip): the leg has any bar with body >= 1.0 x ATR moving toward the zone, OR the leg is < 4 bars.
  BALANCED/CORRECTIVE (take): everything else (a slow, overlapping walk back).
Cells: ALL, BALANCED, REVERSAL per area per timeframe. Coin control as in the base script."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report
import gold_three_areas_research as ta

def tag(b, ss):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    for s in ss:
        i0 = int(np.searchsorted(T, s["t0"])); i1 = int(np.searchsorted(T, s["t1"])); d, e = s["d"], s["entry"]
        f = next((k for k in range(i0, i1) if (L[k] <= e if d == 1 else H[k] >= e)), None)
        if f is None: s["bal"] = None; continue
        leg = range(i0, f)   # only bars CLOSED before the fill bar (no lookahead)
        fast = any(-d * (C[k] - O[k]) >= A[k] for k in leg) or len(leg) < 3
        s["bal"] = not fast
    return ss

if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf, mins in (("15min", 15), ("1h", 60)):
        b = bars(m1, tf); out = ta.setups(b)
        for area in ("DEMAND1", "GAP_DEEP"):
            ss = tag(b, out[area])
            for cell, keep in (("BALANCED", True), ("REVERSAL", False)):
                sub = [s for s in ss if s["bal"] is keep]
                real = ta.run(m1, sub, mins); rng = np.random.default_rng(20261013)
                coin = [summ(ta.run(m1, sub, mins, rng))["tot"] for _ in range(30)]
                report(f"{area} {cell:8s} {tf}", real, coin)
