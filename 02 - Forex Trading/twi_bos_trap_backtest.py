"""
TWI BOS Trap Entry - signal logger / backtest.

Replicates the Pine v2 logic in Python against real MT5 bars so signal quality can be
judged on a real sample instead of on one live trade. Runs the same data twice --
momentum gate ON and OFF -- so the gate itself can be measured rather than assumed.

Logic mirrored from '02 - Forex Trading/TWI BOS Trap Entry.pine':
  BOS -> Order Block -> Trap/Inducement -> sweep -> OB tap -> entry.

Usage:
    python twi_bos_trap_backtest.py [SYMBOL] [TIMEFRAME] [BARS]
    e.g. python twi_bos_trap_backtest.py XAUUSD M30 5000
"""

import csv
import os
import sys
from datetime import datetime

import MetaTrader5 as mt5

# ---- settings (match the Pine defaults) ----
SWING_LEN    = 5
OB_LOOKBACK  = 20
OB_MAX_AGE   = 60
REQUIRE_IDM  = True
CONFIRM_CLOSE = True
R_MULTIPLE   = 2.0
MOM_LEN      = 10

TF_MAP = {
    "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15, "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4, "D1": mt5.TIMEFRAME_D1,
}

OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def load_bars(symbol, timeframe, count):
    if not mt5.initialize():
        raise SystemExit("MT5 initialize failed: %s" % (mt5.last_error(),))
    rates = mt5.copy_rates_from_pos(symbol, TF_MAP[timeframe], 0, count)
    mt5.shutdown()
    if rates is None or len(rates) == 0:
        raise SystemExit("No bars returned for %s %s" % (symbol, timeframe))
    return [
        {
            "time": datetime.utcfromtimestamp(int(r["time"])),
            "open": float(r["open"]), "high": float(r["high"]),
            "low": float(r["low"]),   "close": float(r["close"]),
            "volume": int(r["tick_volume"]),
        }
        for r in rates
    ]


def pivot_high(bars, i, left, right):
    """Pine ta.pivothigh: bar i is a pivot if it is the strict high of its window."""
    if i - left < 0 or i + right >= len(bars):
        return None
    h = bars[i]["high"]
    for j in range(i - left, i + right + 1):
        if j == i:
            continue
        if bars[j]["high"] >= h:
            return None
    return h


def pivot_low(bars, i, left, right):
    if i - left < 0 or i + right >= len(bars):
        return None
    l = bars[i]["low"]
    for j in range(i - left, i + right + 1):
        if j == i:
            continue
        if bars[j]["low"] <= l:
            return None
    return l


def momentum(bars, i, n):
    """Higher highs AND higher lows over n bars vs the n bars before = momentum up."""
    if i - (2 * n) < 0:
        return False, False
    cur_hh = max(b["high"] for b in bars[i - n + 1:i + 1])
    cur_ll = min(b["low"] for b in bars[i - n + 1:i + 1])
    prv_hh = max(b["high"] for b in bars[i - (2 * n) + 1:i - n + 1])
    prv_ll = min(b["low"] for b in bars[i - (2 * n) + 1:i - n + 1])
    return (cur_hh > prv_hh and cur_ll > prv_ll), (cur_hh < prv_hh and cur_ll < prv_ll)


def simulate(bars, entry_i, direction, entry, sl, tp):
    """Walk forward until SL or TP hits. SL wins ties (same bar) -- conservative."""
    for j in range(entry_i + 1, len(bars)):
        b = bars[j]
        if direction == "long":
            if b["low"] <= sl:
                return "loss", -1.0, sl, bars[j]["time"]
            if b["high"] >= tp:
                return "win", R_MULTIPLE, tp, bars[j]["time"]
        else:
            if b["high"] >= sl:
                return "loss", -1.0, sl, bars[j]["time"]
            if b["low"] <= tp:
                return "win", R_MULTIPLE, tp, bars[j]["time"]
    return "open", 0.0, bars[-1]["close"], bars[-1]["time"]


def expand_cluster(bars, j, span=6):
    """
    Build the zone from the CONSOLIDATION CLUSTER around bar j, not from j alone.

    Adam draws his order blocks as ~10-point bands covering the whole basing area;
    this script was drawing 3-point single-candle zones. His own earlier finding on
    TWI SR Sweep Reclaim was that cluster-based zones beat single-candle zones, and
    that lesson was never carried over here.

    Walk out from j in both directions, absorbing any bar whose range still overlaps
    the zone being built. Stop at the first bar that does not touch it.
    """
    top = bars[j]["high"]
    bot = bars[j]["low"]
    for k in range(j - 1, max(-1, j - span - 1), -1):
        if bars[k]["low"] <= top and bars[k]["high"] >= bot:
            top = max(top, bars[k]["high"])
            bot = min(bot, bars[k]["low"])
        else:
            break
    for k in range(j + 1, min(len(bars), j + span + 1)):
        if bars[k]["low"] <= top and bars[k]["high"] >= bot:
            top = max(top, bars[k]["high"])
            bot = min(bot, bars[k]["low"])
        else:
            break
    return top, bot


def add_to_profile(profile, bar, bucket):
    """Spread one bar's volume evenly across the price buckets it spans."""
    lo_b = int(bar["low"] / bucket)
    hi_b = int(bar["high"] / bucket)
    n = hi_b - lo_b + 1
    share = bar["volume"] / n
    for b in range(lo_b, hi_b + 1):
        profile[b] = profile.get(b, 0.0) + share


def zone_vol_ratio(profile, bot, top, bucket):
    """
    Volume density inside the zone vs average density across the profile so far.
    >1 means the zone sits on a high-volume node. Built only from bars already
    seen, so there is no lookahead.
    """
    if not profile:
        return None
    lo_b = int(bot / bucket)
    hi_b = int(top / bucket)
    zone_v = sum(profile.get(b, 0.0) for b in range(lo_b, hi_b + 1))
    zone_n = hi_b - lo_b + 1
    total_v = sum(profile.values())
    total_n = len(profile)
    if zone_n == 0 or total_n == 0 or total_v == 0:
        return None
    return (zone_v / zone_n) / (total_v / total_n)


def pick_origin_ob(bars, i, bullish, max_leg=200, back=10):
    """
    Anchor the order block to the ORIGIN of the impulse leg, not to a pullback
    partway up it.

    Adam's read of the 2026-09-08 gold chart: the real demand was the base of the
    whole rally (4380.90), not the shallow 4405-4408 zone the 20-bar lookback found.
    The origin sat ~108 bars back -- outside anything the windowed search can see.

    Method: find the extreme (lowest low for a bullish BOS) in the leg behind the
    break, then take the last opposing candle at or before that extreme.
    """
    lo = max(0, i - max_leg)
    if lo >= i:
        return None
    window = range(lo, i)
    if bullish:
        origin = min(window, key=lambda k: bars[k]["low"])
    else:
        origin = max(window, key=lambda k: bars[k]["high"])

    for k in range(origin, max(-1, origin - back), -1):
        if bullish and bars[k]["close"] < bars[k]["open"]:
            return i - k
        if not bullish and bars[k]["close"] > bars[k]["open"]:
            return i - k
    # No opposing candle right at the extreme -- use the extreme bar itself.
    return i - origin


def pick_ob(bars, i, bullish, skip_trap):
    """
    Choose the order block candle offset behind bar i.

    The nearest opposing candle is usually the TRAP order block -- the shallow one
    retail buys, which price runs through on its way to the real zone underneath.
    With skip_trap on, take the deepest opposing candle in the leg instead.
    """
    if bullish:
        cands = [k for k in range(1, min(OB_LOOKBACK, i) + 1)
                 if bars[i - k]["close"] < bars[i - k]["open"]]
    else:
        cands = [k for k in range(1, min(OB_LOOKBACK, i) + 1)
                 if bars[i - k]["close"] > bars[i - k]["open"]]
    if not cands:
        return None, None
    nearest = cands[0]
    if not skip_trap:
        return nearest, None
    if bullish:
        deepest = min(cands, key=lambda k: bars[i - k]["low"])
    else:
        deepest = max(cands, key=lambda k: bars[i - k]["high"])
    trap = nearest if deepest != nearest else None
    return deepest, trap


def run(bars, use_mom_gate, skip_trap=False, seq_trap=False, confirm_close=CONFIRM_CLOSE,
        strict_bos=False, bos_depth=2, sl_buf=0.0, origin_ob=False, max_age=None,
        cluster=False, vol_min=None):
    """
    strict_bos: a real BOS/CHoCH has to break the highest of the last `bos_depth`
    swing highs (or lowest of the swing lows), not merely the most recent pivot.
    Adam's rule: the break must clear PREVIOUS price, not an internal minor high.

    seq_trap: the shallow zone is treated as the TRAP. It must be violated
    (price closing through it) before the deeper zone is armed for entry --
    which is what the chart actually does: price cuts through the fake OB
    and only the one underneath holds.

    Returns (taken, blocked).
    """
    trades, blocked = [], []
    ob_age = OB_MAX_AGE if max_age is None else max_age
    profile = {}
    bucket = max(b['high'] for b in bars[:200]) / 4000.0   # ~0.025% of price

    swing_high = swing_low = None
    last_broken_high = last_broken_low = None
    hi_pivots, lo_pivots = [], []   # recent confirmed pivots, for strict BOS

    bull = {"armed": False, "top": None, "bot": None, "bar": None,
            "idm": None, "swept": False, "taken": False}
    bear = {"armed": False, "top": None, "bot": None, "bar": None,
            "idm": None, "swept": False, "taken": False}

    for i in range(len(bars)):
        b = bars[i]

        # Pivots confirm SWING_LEN bars late, exactly like Pine.
        pv = i - SWING_LEN
        if pv >= 0:
            ph = pivot_high(bars, pv, SWING_LEN, SWING_LEN)
            plw = pivot_low(bars, pv, SWING_LEN, SWING_LEN)
            if ph is not None:
                swing_high = ph
                hi_pivots.append(ph)
                hi_pivots[:] = hi_pivots[-bos_depth:]
            if plw is not None:
                swing_low = plw
                lo_pivots.append(plw)
                lo_pivots[:] = lo_pivots[-bos_depth:]
        else:
            ph = plw = None

        # The level a real BOS has to clear.
        if strict_bos and len(hi_pivots) >= bos_depth:
            bos_hi_level = max(hi_pivots)
        else:
            bos_hi_level = swing_high
        if strict_bos and len(lo_pivots) >= bos_depth:
            bos_lo_level = min(lo_pivots)
        else:
            bos_lo_level = swing_low

        bos_up = bos_hi_level is not None and b["close"] > bos_hi_level and bos_hi_level != last_broken_high
        bos_dn = bos_lo_level is not None and b["close"] < bos_lo_level and bos_lo_level != last_broken_low

        if bos_up:
            last_broken_high = bos_hi_level
            if origin_ob:
                off, trap_off = pick_origin_ob(bars, i, True), None
            else:
                off, trap_off = pick_ob(bars, i, True, skip_trap or seq_trap)
            if off is not None:
                j = i - off
                if cluster:
                    z_top, z_bot = expand_cluster(bars, j)
                else:
                    z_top, z_bot = bars[j]["high"], bars[j]["low"]
                if vol_min is not None:
                    r = zone_vol_ratio(profile, z_bot, z_top, bucket)
                    if r is not None and r < vol_min:
                        z_top = None
                tz = bars[i - trap_off]["low"] if (seq_trap and trap_off is not None) else None
                if z_top is not None:
                    bull.update({"armed": True, "top": z_top, "bot": z_bot,
                                 "bar": j, "idm": None,
                                 "swept": not REQUIRE_IDM, "taken": False,
                                 "trap_bot": tz, "trap_done": tz is None})

        if bos_dn:
            last_broken_low = bos_lo_level
            if origin_ob:
                off, trap_off = pick_origin_ob(bars, i, False), None
            else:
                off, trap_off = pick_ob(bars, i, False, skip_trap or seq_trap)
            if off is not None:
                j = i - off
                if cluster:
                    z_top, z_bot = expand_cluster(bars, j)
                else:
                    z_top, z_bot = bars[j]["high"], bars[j]["low"]
                if vol_min is not None:
                    r = zone_vol_ratio(profile, z_bot, z_top, bucket)
                    if r is not None and r < vol_min:
                        z_top = None
                tz = bars[i - trap_off]["high"] if (seq_trap and trap_off is not None) else None
                if z_top is not None:
                    bear.update({"armed": True, "top": z_top, "bot": z_bot,
                                 "bar": j, "idm": None,
                                 "swept": not REQUIRE_IDM, "taken": False,
                                 "trap_top": tz, "trap_done": tz is None})

        # The trap zone has to actually fail before the real zone is live.
        if seq_trap:
            if bull["armed"] and not bull.get("trap_done") and bull.get("trap_bot") is not None:
                if b["close"] < bull["trap_bot"]:
                    bull["trap_done"] = True
            if bear["armed"] and not bear.get("trap_done") and bear.get("trap_top") is not None:
                if b["close"] > bear["trap_top"]:
                    bear["trap_done"] = True

        # Trap / inducement
        if bull["armed"] and bull["idm"] is None and plw is not None:
            if pv > bull["bar"] and plw > bull["top"]:
                bull["idm"] = plw
        if bear["armed"] and bear["idm"] is None and ph is not None:
            if pv > bear["bar"] and ph < bear["bot"]:
                bear["idm"] = ph

        # Sweep of the trap
        if bull["armed"] and REQUIRE_IDM and not bull["swept"] and bull["idm"] is not None:
            if b["low"] < bull["idm"]:
                bull["swept"] = True
        if bear["armed"] and REQUIRE_IDM and not bear["swept"] and bear["idm"] is not None:
            if b["high"] > bear["idm"]:
                bear["swept"] = True

        # Invalidation + ageing
        if bull["armed"] and b["close"] < bull["bot"]:
            bull["armed"] = False
        if bear["armed"] and b["close"] > bear["top"]:
            bear["armed"] = False
        if bull["armed"] and i - bull["bar"] > ob_age:
            bull["armed"] = False
        if bear["armed"] and i - bear["bar"] > ob_age:
            bear["armed"] = False

        mom_up, mom_dn = momentum(bars, i, MOM_LEN)

        # Entries
        tapped_bull = bull["armed"] and bull["swept"] and b["low"] <= bull["top"] and b["high"] >= bull["bot"]
        tapped_bear = bear["armed"] and bear["swept"] and b["high"] >= bear["bot"] and b["low"] <= bear["top"]

        if seq_trap:
            tapped_bull = tapped_bull and bull.get("trap_done", True)
            tapped_bear = tapped_bear and bear.get("trap_done", True)

        raw_long  = tapped_bull and (b["close"] > bull["top"] if confirm_close else True) and not bull["taken"]
        raw_short = tapped_bear and (b["close"] < bear["bot"] if confirm_close else True) and not bear["taken"]

        if raw_long:
            if use_mom_gate and mom_dn:
                blocked.append({"time": b["time"], "dir": "long"})
            else:
                bull["taken"] = True
                entry = b["close"]
                # Stop sits beyond the far side of the zone. sl_buf widens it by a
                # fraction of the zone height -- the 2026-09-07 gold short died 1.3 points
                # inside the zone edge, so the question is whether headroom pays for itself.
                zh = bull["top"] - bull["bot"]
                sl = bull["bot"] - (zh * sl_buf)
                if entry > sl:
                    tp = entry + (entry - sl) * R_MULTIPLE
                    res, r, xp, xt = simulate(bars, i, "long", entry, sl, tp)
                    trades.append({"time": b["time"], "dir": "long", "entry": entry,
                                   "sl": sl, "tp": tp, "result": res, "R": r,
                                   "exit": xp, "exit_time": xt})

        add_to_profile(profile, b, bucket)

        if raw_short:
            if use_mom_gate and mom_up:
                blocked.append({"time": b["time"], "dir": "short"})
            else:
                bear["taken"] = True
                entry = b["close"]
                zh = bear["top"] - bear["bot"]
                sl = bear["top"] + (zh * sl_buf)
                if sl > entry:
                    tp = entry - (sl - entry) * R_MULTIPLE
                    res, r, xp, xt = simulate(bars, i, "short", entry, sl, tp)
                    trades.append({"time": b["time"], "dir": "short", "entry": entry,
                                   "sl": sl, "tp": tp, "result": res, "R": r,
                                   "exit": xp, "exit_time": xt})

    return trades, blocked


def stats(trades, label):
    closed = [t for t in trades if t["result"] != "open"]
    if not closed:
        return "%-16s no closed trades" % label
    wins = [t for t in closed if t["result"] == "win"]
    total_r = sum(t["R"] for t in closed)
    gross_w = sum(t["R"] for t in wins)
    gross_l = abs(sum(t["R"] for t in closed if t["R"] < 0))
    pf = (gross_w / gross_l) if gross_l else float("inf")
    return ("%-16s trades %3d | win rate %5.1f%% | total %+7.2fR | expectancy %+5.3fR | PF %.2f"
            % (label, len(closed), 100.0 * len(wins) / len(closed), total_r,
               total_r / len(closed), pf))


def main():
    symbol = sys.argv[1] if len(sys.argv) > 1 else "XAUUSD"
    tf     = sys.argv[2] if len(sys.argv) > 2 else "M30"
    count  = int(sys.argv[3]) if len(sys.argv) > 3 else 5000

    bars = load_bars(symbol, tf, count)
    print("%s %s | %d bars | %s -> %s"
          % (symbol, tf, len(bars), bars[0]["time"], bars[-1]["time"]))
    print()

    base,    _ = run(bars, use_mom_gate=True, confirm_close=False, sl_buf=0.25)
    clus,    _ = run(bars, use_mom_gate=True, confirm_close=False, sl_buf=0.25, cluster=True)
    vol,     _ = run(bars, use_mom_gate=True, confirm_close=False, sl_buf=0.25, vol_min=1.0)
    on_trades, _ = run(bars, use_mom_gate=True, confirm_close=False, sl_buf=0.25,
                       cluster=True, vol_min=1.0)

    print(stats(base,      "single-candle"))
    print(stats(clus,      "cluster zone"))
    print(stats(vol,       "volume >= avg"))
    print(stats(on_trades, "cluster + volume"))

    path = os.path.join(OUT_DIR, "twi_bos_trap_signals_%s_%s.csv" % (symbol, tf))
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["time", "dir", "entry", "sl", "tp",
                                          "result", "R", "exit", "exit_time"])
        w.writeheader()
        for t in on_trades:
            w.writerow(t)
    print()
    print("signal log written: %s" % path)


if __name__ == "__main__":
    main()
