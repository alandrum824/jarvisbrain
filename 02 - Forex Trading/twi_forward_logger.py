"""
TWI BOS Trap Entry - forward signal logger.

Records every signal the strategy fires FROM NOW ON, with its levels frozen at
fire time, then resolves the outcome from real subsequent bars.

Why this exists: six backtest variants were tested on 2026-09-08 and none beat the
plain baseline. After that many attempts on one dataset, a winner is as likely to be
luck as edge. Forward data has not been fitted to anything, so it is the only sample
that can settle whether this strategy has an edge.

Discipline rules baked in:
  * The entry / stop / target are written once, at fire time, and never rewritten.
  * Only the outcome column gets filled in later.
  * Nothing before the logger's start time is recorded -- no backfilling wins.
  * It reuses the SAME engine as the backtest (twi_bos_trap_backtest.run), so the
    logged strategy and the tested strategy can never quietly drift apart.

Usage:
    python twi_forward_logger.py          # one poll, then exit
    python twi_forward_logger.py --loop   # poll every 5 minutes
"""

import csv
import json
import os
import sys
import time
from datetime import datetime, timezone

from twi_bos_trap_backtest import load_bars, run

HERE     = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(HERE, "twi_forward_log.csv")
STATE    = os.path.join(HERE, "twi_forward_state.json")

# Same settings the backtest measured at +0.267R. Do not tune these while logging;
# changing the strategy mid-sample makes the sample worthless.
SETTINGS = dict(use_mom_gate=True, confirm_close=False, sl_buf=0.25)

WATCH = [
    ("XAUUSD", "M15"), ("XAUUSD", "M30"),
    ("EURUSD", "M15"), ("EURUSD", "M30"),
    ("GBPUSD", "M30"), ("NZDUSD", "M15"),
]

BARS = 3000
POLL_SECONDS = 300

FIELDS = ["logged_at", "symbol", "tf", "signal_time", "dir", "entry", "sl", "tp",
          "rr", "zone_bot", "zone_top", "result", "r", "exit_price", "exit_time",
          "resolved_at"]


def load_state():
    """
    The cutoff must be expressed in BROKER SERVER TIME, not real UTC.

    MT5 bar timestamps come back in the broker's server timezone (UTC+2/+3 for
    Risen), so comparing them against datetime.utcnow() lets several hours of
    already-completed signals slip past the filter. The first run of this logger
    did exactly that -- it recorded a signal from an hour earlier and scored it a
    loss. Backfilled outcomes are precisely what makes a forward sample worthless,
    so the cutoff is anchored to the newest bar the broker has instead.
    """
    if os.path.exists(STATE):
        with open(STATE) as f:
            return json.load(f)
    latest = None
    for symbol, tf in WATCH:
        try:
            bars = load_bars(symbol, tf, 5)
        except SystemExit:
            continue
        if bars and (latest is None or bars[-1]["time"] > latest):
            latest = bars[-1]["time"]
    if latest is None:
        raise SystemExit("cannot establish a server-time cutoff: no bars available")
    st = {"started": latest.isoformat(), "started_wall_utc": datetime.now(timezone.utc).isoformat()}
    with open(STATE, "w") as f:
        json.dump(st, f)
    return st


def load_log():
    if not os.path.exists(LOG_PATH):
        return {}, []
    with open(LOG_PATH, newline="") as f:
        rows = list(csv.DictReader(f))
    index = {(r["symbol"], r["tf"], r["signal_time"], r["dir"]): i
             for i, r in enumerate(rows)}
    return index, rows


def write_log(rows):
    with open(LOG_PATH, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


def poll_once(verbose=True):
    state = load_state()
    started = datetime.fromisoformat(state["started"]).replace(tzinfo=None)
    index, rows = load_log()

    new_count = 0
    resolved_count = 0
    now = datetime.now(timezone.utc).isoformat()

    for symbol, tf in WATCH:
        try:
            bars = load_bars(symbol, tf, BARS)
        except SystemExit as e:
            if verbose:
                print("SKIP %s %s: %s" % (symbol, tf, e), flush=True)
            continue

        trades, _ = run(bars, **SETTINGS)

        for t in trades:
            # Nothing that fired before logging began.
            if t["time"] < started:
                continue

            key = (symbol, tf, t["time"].isoformat(), t["dir"])
            risk = abs(t["entry"] - t["sl"])
            rr = abs(t["tp"] - t["entry"]) / risk if risk else 0.0

            if key not in index:
                rows.append({
                    "logged_at":   now,
                    "symbol":      symbol,
                    "tf":          tf,
                    "signal_time": t["time"].isoformat(),
                    "dir":         t["dir"],
                    "entry":       "%.5f" % t["entry"],
                    "sl":          "%.5f" % t["sl"],
                    "tp":          "%.5f" % t["tp"],
                    "rr":          "%.2f" % rr,
                    "zone_bot":    "",
                    "zone_top":    "",
                    "result":      t["result"],
                    "r":           "%.2f" % t["R"],
                    "exit_price":  "%.5f" % t["exit"] if t["result"] != "open" else "",
                    "exit_time":   t["exit_time"].isoformat() if t["result"] != "open" else "",
                    "resolved_at": now if t["result"] != "open" else "",
                })
                index[key] = len(rows) - 1
                new_count += 1
                if verbose:
                    print("NEW SIGNAL %s %s %s entry %.5f SL %.5f TP %.5f (%.2f:1)"
                          % (symbol, tf, t["dir"].upper(), t["entry"], t["sl"], t["tp"], rr),
                          flush=True)
            else:
                # Only ever fill in an outcome. Levels are never rewritten.
                row = rows[index[key]]
                if row["result"] == "open" and t["result"] != "open":
                    row["result"]      = t["result"]
                    row["r"]           = "%.2f" % t["R"]
                    row["exit_price"]  = "%.5f" % t["exit"]
                    row["exit_time"]   = t["exit_time"].isoformat()
                    row["resolved_at"] = now
                    resolved_count += 1
                    if verbose:
                        print("RESOLVED %s %s %s -> %s (%.2fR)"
                              % (symbol, tf, t["dir"].upper(), t["result"], t["R"]),
                              flush=True)

    write_log(rows)

    closed = [r for r in rows if r["result"] in ("win", "loss")]
    if verbose:
        if closed:
            total = sum(float(r["r"]) for r in closed)
            wins = sum(1 for r in closed if r["result"] == "win")
            print("running: %d closed | %.1f%% win | %+.2fR | expectancy %+.3fR"
                  % (len(closed), 100.0 * wins / len(closed), total, total / len(closed)),
                  flush=True)
        else:
            print("running: %d logged, none closed yet" % len(rows), flush=True)

    return new_count, resolved_count


if __name__ == "__main__":
    loop = "--loop" in sys.argv
    while True:
        try:
            poll_once()
        except Exception as e:
            print("POLL ERROR: %s" % e, flush=True)
        if not loop:
            break
        time.sleep(POLL_SECONDS)
