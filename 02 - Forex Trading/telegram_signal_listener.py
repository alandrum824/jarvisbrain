"""
TWI Telegram Signal Listener

Logs into Adam's own Telegram account (Telethon, MTProto -- NOT a bot, since
target signal channels are subscriptions he doesn't administer and won't add
a bot to) and watches whichever channel(s) he picks from his own joined-chat
list for XAUUSD-style signal messages. Each parsed signal is appended as one
row to a CSV file in MT5's shared Common\Files folder, where the TWI
Telegram Copy EA picks it up and executes it.

First-run setup (one time, needs Adam present):
    1. Go to https://my.telegram.org, log in with his own phone number,
       create an "API development tool" app -> get api_id / api_hash.
    2. pip install telethon
    3. Fill in API_ID / API_HASH below.
    4. Run this script directly: `python telegram_signal_listener.py`
       Telethon will prompt for phone number + the login code sent to his
       Telegram app (and a 2FA password if he has one set). This creates a
       local session file (telegram_signal.session) so it won't ask again.
    5. On first run (or with --select), it lists every channel/group his
       account is in and asks which one(s) to watch. The choice is saved to
       telegram_signal_channels.json so it's remembered next time.
    6. Leave it running (or run it as a background/scheduled task) -- it
       streams new messages in real time, it does not poll.

To pick different channels later: `python telegram_signal_listener.py --select`
"""

import csv
import json
import os
import re
import sys
import time
from telethon import TelegramClient, events
from telethon.tl.types import Channel, Chat

# ---------------- Fill these in ----------------
API_ID = 0            # from my.telegram.org
API_HASH = ""          # from my.telegram.org
# -------------------------------------------------

HERE = os.path.dirname(os.path.abspath(__file__))
CHANNELS_CONFIG = os.path.join(HERE, "telegram_signal_channels.json")

SIGNAL_FILE = os.path.expandvars(
    r"%APPDATA%\MetaQuotes\Terminal\Common\Files\telegram_signals.csv"
)
CSV_FIELDS = [
    "msg_id", "received_ts", "symbol", "direction",
    "entry_low", "entry_high", "sl", "tp1", "tp2", "tp3", "tp4",
]

SYMBOL_MAP = {"GOLD": "XAUUSD", "XAUUSD": "XAUUSD", "XAU": "XAUUSD"}


def parse_signal(text: str):
    """Return a dict of signal fields, or None if this message isn't a real
    actionable signal (e.g. "XAUUSD SELL NOW" alerts with no levels)."""
    t = text.upper()

    m = re.search(r"(GOLD|XAUUSD|XAU)\s+(BUY|SELL)\s+([\d.]+)\s*/\s*([\d.]+)", t)
    if not m:
        return None
    symbol = SYMBOL_MAP.get(m.group(1), m.group(1))
    direction = m.group(2)
    e1, e2 = float(m.group(3)), float(m.group(4))
    entry_low, entry_high = min(e1, e2), max(e1, e2)

    sl_m = re.search(r"SL\s*/?\s*([\d.]+)", t)
    if not sl_m:
        return None
    sl = float(sl_m.group(1))

    tps = {}
    for i in range(1, 5):
        tm = re.search(rf"TP\s*{i}\s+([\d.]+|OPEN)", t)
        if tm:
            tps[f"tp{i}"] = "" if tm.group(1) == "OPEN" else float(tm.group(1))

    return {
        "symbol": symbol,
        "direction": direction,
        "entry_low": entry_low,
        "entry_high": entry_high,
        "sl": sl,
        "tp1": tps.get("tp1", ""),
        "tp2": tps.get("tp2", ""),
        "tp3": tps.get("tp3", ""),
        "tp4": tps.get("tp4", ""),
    }


def ensure_signal_file():
    os.makedirs(os.path.dirname(SIGNAL_FILE), exist_ok=True)
    if not os.path.exists(SIGNAL_FILE):
        with open(SIGNAL_FILE, "w", newline="") as f:
            csv.DictWriter(f, fieldnames=CSV_FIELDS).writeheader()


def append_signal(msg_id: int, parsed: dict):
    with open(SIGNAL_FILE, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writerow({"msg_id": msg_id, "received_ts": int(time.time()), **parsed})


def pick_channels(client) -> list:
    """List every channel/group Adam's account is a member of and let him
    pick which one(s) to watch. Returns a list of {id, title}."""
    print("\nFetching your joined channels/groups...")
    entries = []
    for dialog in client.iter_dialogs():
        ent = dialog.entity
        if isinstance(ent, (Channel, Chat)):
            subs = getattr(ent, "participants_count", None)
            entries.append({"id": dialog.id, "title": dialog.name, "subs": subs})

    print(f"\nFound {len(entries)} channels/groups:\n")
    for i, e in enumerate(entries):
        subs = f" ({e['subs']} members)" if e["subs"] else ""
        print(f"  [{i}] {e['title']}{subs}")

    raw = input("\nEnter number(s) to watch, comma-separated (e.g. 0,3): ").strip()
    picks = [entries[int(x)] for x in raw.split(",") if x.strip().isdigit()]
    if not picks:
        print("No valid selection, exiting.")
        sys.exit(1)

    with open(CHANNELS_CONFIG, "w") as f:
        json.dump(picks, f, indent=2)
    print(f"\nSaved selection to {CHANNELS_CONFIG}: {[p['title'] for p in picks]}")
    return picks


def load_or_pick_channels(client, force_select: bool) -> list:
    if not force_select and os.path.exists(CHANNELS_CONFIG):
        with open(CHANNELS_CONFIG) as f:
            picks = json.load(f)
        print(f"Watching saved channels: {[p['title'] for p in picks]} "
              f"(run with --select to change)")
        return picks
    return pick_channels(client)


def main():
    force_select = "--select" in sys.argv
    ensure_signal_file()
    client = TelegramClient("telegram_signal", API_ID, API_HASH)
    client.start()

    picks = load_or_pick_channels(client, force_select)
    chat_ids = [p["id"] for p in picks]

    @client.on(events.NewMessage(chats=chat_ids))
    async def handler(event):
        parsed = parse_signal(event.raw_text or "")
        if parsed is None:
            return  # not an actionable signal (alert-only message, etc.)
        append_signal(event.id, parsed)
        print(f"[signal] #{event.id} {parsed['direction']} {parsed['symbol']} "
              f"{parsed['entry_low']}/{parsed['entry_high']} SL {parsed['sl']}")

    print(f"\nWatching {[p['title'] for p in picks]} -> writing signals to {SIGNAL_FILE}")
    client.run_until_disconnected()


if __name__ == "__main__":
    main()
