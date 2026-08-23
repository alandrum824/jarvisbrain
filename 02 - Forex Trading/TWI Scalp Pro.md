---
status: active
project: forex-trading
type: reference
---
# TWI Scalp Pro

A new MQL5 Expert Advisor, built by Jarvis (not Grok this time — see [[TWI Sniper ORB]] for that one) on 2026-08-22, from a spec Adam supplied via screenshots of Pat's (TradeWithPat) "Trade the Trend" ORB playbook plus his own additional requirements. Full source lives at `02 - Forex Trading/TWI Scalp Pro.mq5` in this vault, and is also placed in the one MT5 terminal found on this machine (see Access note below) — **not attached to any chart**, per Adam's explicit instruction.

## What it does
Session-based aggressive Opening Range Breakout:
1. For each enabled session (Asian/London/New York, or "all sessions"), a configurable Opening Range window (default 15 min) sets that session's OR High/Low.
2. H1 EMA-vs-price filter sets trend bias (uptrend = price above EMA, downtrend = below) — same method as [[TWI Sniper ORB]]'s trend filter, for consistency.
3. Aggressive entry: the first EntryTF (default M5) candle to **close** beyond the OR extreme in the direction of bias triggers immediately — no retrace wait, matching the "aggressive break-and-close" style from Pat's playbook screenshots.
4. Stop: opposite side of the opening range (+ optional pip buffer). Target: entry ± (risk × RR_Multiplier, default 2.8 — matched to the R:R seen in Pat's traded examples, roughly 2.7–2.93R).
5. Entries are only considered within `EntryWindowMinutes` (default 240) after a session's OR closes, so a stale breakout hours later doesn't fire — Jarvis's own addition to make the OR window mechanically sound, not something Adam explicitly asked for; flagged here rather than silently baked in.

## Controls Adam asked for specifically
- Per-session enable + independent time windows, or one "all sessions" switch.
- Day-of-week filter (Mon–Sun toggles).
- Lot sizing: **Fixed** (flat lot) or **Dynamic** (auto-calculated from current account balance × a risk % input, so position size scales with the account).
- Max concurrent open trades (cap).
- Max trades per session (cap, resets each new session/day).

## Access — two machines, two Jarvis sessions
Adam runs Jarvis in two separate chats: one on this desktop machine, one over Remote Desktop into a different machine where his other trading setup lives — that second machine has the other MT5 terminal this EA still needs to reach. This session has no filesystem access to that machine.

**Handoff instructions for the Remote Desktop session:** the vault syncs via its GitHub remote (`alandrum824/jarvisbrain`), not OneDrive — pull latest there once Adam has this session's changes pushed. Once pulled, take `02 - Forex Trading\TWI Scalp Pro.mq5` from the vault, find that machine's MT5 terminal data folder (data folder differs from the install folder — check the install directory's `origin.txt` if unsure which AppData\MetaQuotes\Terminal\<hash> folder it maps to), and copy the file into `MQL5\Experts\` there. **Do not attach it to any chart** — Adam was explicit about that. Confirm back to Adam once placed.

On this machine: only **one** MT5 terminal is installed — **AAAFx Global MT5 Terminal** (installed at `C:\Program Files\AAAFx Global MT5 Terminal`, actual data/MQL5 folder at `C:\Users\aland\AppData\Roaming\MetaQuotes\Terminal\C460888076DC2C8BC8FAA784199EBB14` per that install's `origin.txt`). The file is already placed there, in `MQL5\Experts\`, not attached to any chart.

## Not yet done
- Not compiled/tested — MetaEditor needs to compile it into a runnable .ex5; Jarvis has no way to run that compiler here.
- Not attached to any chart, per Adam's explicit instruction — this is source-only so far.
- No backtest run yet.
