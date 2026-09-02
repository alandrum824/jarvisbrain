---
status: active
project: forex-trading
type: reference
---
# TWI Telegram Copy

Copy-trader system built 2026-09-02: reads Telegram signal channels Adam is subscribed to and executes them automatically, replicating each signal's own TP ladder (not one fixed target) instead of a discretionary strategy. Two parts.

## Why not a bot
Adam is a **subscriber**, not an admin, of the target channels (e.g. "XAUUSD MASTER," 5,484 subscribers). A Telegram bot can only read messages from chats it's explicitly added to — a public signal-seller channel will never add a random bot. The only real way to read channels you're merely a member of is to log in as your own account (MTProto user-session), not the Bot API. Confirmed this is the same real architecture TWP's own free "Telegram Connector" tool uses (Adam found and shared that video — same phone+code login flow, same EA-reads-a-file-folder pattern) — just built here as fully readable source instead of an unsigned pre-built `.exe`.

## Part 1 — `telegram_signal_listener.py`
Python + Telethon, logs into **Adam's own Telegram account** (phone number + login code, one-time interactive setup — creates a local session file so it doesn't ask again). On first run (or `--select`), lists every channel/group his account is a member of and lets him pick which one(s) to watch — saved to `telegram_signal_channels.json`, not hardcoded to one channel.

Parses real signal messages, e.g.:
```
GOLD SELL 4309/4312
TP1 4306  TP2 4303  TP3 4300  TP4 OPEN
SL / 4315
```
Loose alert-only messages ("XAUUSD SELL NOW" with no levels) are skipped — not actionable. Each real parsed signal is appended as one row to `%APPDATA%\MetaQuotes\Terminal\Common\Files\telegram_signals.csv` — the terminal's **shared** Files folder, readable by any MT5 install on the machine regardless of which one.

**Not yet run.** Needs from Adam: a Telegram API ID/hash from my.telegram.org (his own account, free, ~2 min), then `pip install telethon` and one interactive run to log in and pick the channel(s).

## Part 2 — `TWI Telegram Copy.mq5`
MQL5 EA, polls that shared CSV on a timer (`PollSeconds`, default 3s). For each new row (tracked by `msg_id` so nothing double-fires, and the whole existing file is seeded as "already seen" on `OnInit` so it never trades a backlog from before attach):
1. Maps signal symbol (GOLD/XAUUSD) to a real chart symbol (`SymbolSuffix` input for brokers needing e.g. `.sim`).
2. Skips the signal if current price is outside its stated entry range (`EntryBufferPoints` tolerance) — doesn't chase a missed entry. Also skips if the signal is older than `MaxSignalAgeSec` (default 300s) by the time it's seen.
3. Opens up to `MaxLegs` (default 4) separate positions, `LegLotSize` (default 0.01) each, same entry/SL, but each leg gets its own TP — leg 1→TP1, leg 2→TP2, leg 3→TP3, leg 4→TP4 or no TP at all if the channel marked it "OPEN" (a runner). Replicates the channel's own partial-TP ladder instead of picking one target.

Compiled clean (0 errors/0 warnings) on RisenAdam. **Not attached to any chart** — Adam's call when the Telegram side is live and tested.

## Real open items
- **Blocked 2026-09-02: my.telegram.org rate-limited Adam's account** after repeated app-creation attempts (blank "ERROR" popups on every try, confirmed by Telegram's own "too many tries" message on a later attempt). This machine is a VPS — datacenter IPs get flagged/rate-limited by Telegram's anti-abuse system far more readily than a residential connection, likely a real factor here, not just attempt count. Waiting a few hours may or may not clear it. **Real workaround if it doesn't:** do the one-time my.telegram.org signup + first Telethon login from a residential connection (phone or home PC) instead of this VPS, which creates a local `telegram_signal.session` file — Telegram sessions aren't device-locked, so that file can be copied onto this machine afterward and the listener runs headlessly here with no further login needed.
- Adam needs to provide `API_ID`/`API_HASH` (my.telegram.org) and run the listener once interactively to log in + pick channels.
- No backtest possible for this EA (external live signal feed, no historical data to replay) — first real validation will be watching it live on a small size before trusting it.
- Symbol mapping only handles GOLD/XAUUSD/XAU today; add more pairs to `SYMBOL_MAP` in the Python script if other channels/symbols get added later.
