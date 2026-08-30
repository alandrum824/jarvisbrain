---
status: active
project: forex-trading
type: reference
---
# TWI Scalp Pro

A new MQL5 Expert Advisor, built by Jarvis (not Grok this time — see [[TWI Sniper ORB]] for that one) on 2026-08-22, from a spec Adam supplied via screenshots of Pat's (TradeWithPat) "Trade the Trend" ORB playbook plus his own additional requirements. Full source lives at `02 - Forex Trading/TWI Scalp Pro.mq5` in this vault, and is now **compiled and running live on both Risen MT5 terminals** (see Access note below and the 2026-08-24/25 update further down — originally placed without chart attachment, now confirmed actively live-trading on both).

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
Adam runs Jarvis in two separate chats: one on his main desktop machine (where this EA was originally built and placed on the one MT5 terminal found there — **AAAFx Global MT5 Terminal**, `C:\Program Files\AAAFx Global MT5 Terminal`, data folder `C460888076DC2C8BC8FAA784199EBB14`), and one on this machine (a VPS-like box, reached via Remote Desktop from the other session's point of view — this **is** the "second machine" that session's note originally flagged as unconfirmed).

**Resolved 2026-08-22, this machine:** pulled the vault via `git pull` (see [[Mom's eBay Store (EMarketingTX)]]'s note-history for the same day's merge story), found the source at `02 - Forex Trading/TWI Scalp Pro.mq5`, and placed + compiled it on **both** MT5 terminals installed here:
- **RisenAdam** — data folder `C3F62A8326295558A052069AC3E69E3E`, file at `MQL5\Experts\Advisors\TWIScalpPro.mq5`/`.ex5` (matches this terminal's existing convention — [[TWI Range Breakout]] lives in the same `Advisors` subfolder there).
- **RisenMOM** — data folder `1E8D644434576A3AECBEDD6601AB83BA` (Adam's mom's terminal), file at `MQL5\Experts\TWIScalpPro.mq5`/`.ex5` directly (matches this terminal's own convention — its existing EAs sit straight in `Experts\`, no subfolder). **Account confirmed 2026-08-23 via the `mt5-bridge` Python check: this terminal is logged into a DEMO account** (`OANDA-Demo-1`, login `1600175163`, balance $10,385.23 demo funds), not a live account — worth knowing before assuming any activity here is real money.

Both compiled via direct `MetaEditor64.exe /compile` CLI access, each terminal's own MetaEditor: **0 errors, 0 warnings** on both, first pass. Neither is attached to any chart — only the filesystem and compiler were touched, the terminal UIs were never opened.

## Manual trading companion
[[TWI Scalp Pro Signals]] — a TradingView Pine v6 indicator built 2026-08-23 that mirrors this EA's exact entry logic (sessions, OR, H1 EMA trend filter, entry/SL/TP math) so Adam can manually trade the same setups without the EA placing orders. Live on the chart, compiled clean, verified against real signal data.

## Update 2026-08-24/25 — confirmed live-trading, both terminals (superseded "not attached to chart" note below)
Contrary to the original placement plan below, this EA **is now attached and actively live-trading on both RisenAdam and RisenMOM** — confirmed via real closed-deal history (comments "TWI Scalp Pro London" and "TWI Scalp Pro NewYork", magic `20260822`). Real results, last 14 days combined across both accounts: **3 trades, 2W/1L, net +$207.67** — two real wins (+$26.51 RisenAdam NewYork, +$224.32 RisenMOM NewYork) and one real loss (-$53.84 RisenMOM London). A second London loss (-$17.04, RisenAdam, ticket #8034471, stopped out in under 14 minutes) hit on 2026-08-25.

**Session toggle found in source:** `input bool TradeLondon = true;` and `input bool TradeNewYork = true;` (lines ~34-39 of `TWIScalpPro.mq5`) — independent per-session switches, no Asian-session toggle exists for this EA.

**Decision 2026-08-25:** after both London-session losses, Adam restricted this EA to **NY session only**. He made the change himself directly in the live Inputs dialog on **RisenAdam** — confirmed `TradeLondon` is now off there. **RisenMOM is still running with `TradeLondon = true` live** — Adam's explicit choice, declined to change it further ("Not interested"). The `.mq5` source file's own default (`true`) was also left untouched at Adam's direction — same standing caveat as [[TWI Sniper ORB]]'s live-Inputs-vs-source-default gap applies here: the source default no longer matches RisenAdam's live behavior, and won't automatically fix itself if the EA is ever re-attached from scratch there.

## Not yet done
- **Compiled and verified on this machine's two terminals (RisenAdam, RisenMOM) — not yet compiled on the main desktop machine's AAAFx terminal**, per that session's own note (no MetaEditor access there at the time it was written).
- **No backtest run yet, on any terminal.** Tried a headless CLI Strategy Tester run on RisenAdam (2026-08-22, `terminal64.exe /config:tester.ini`) — didn't work, and the reason is a real constraint worth knowing: **both RisenAdam and RisenMOM are already running live** (actively trading), and MT5 only honors `/config` on a fresh launch. It silently no-ops against an already-running instance rather than erroring. Jarvis also has no UI automation tool for MT5 (only TradingView has one), so driving the already-open terminal's Strategy Tester tab isn't currently possible either. A real backtest needs either Adam running it manually in the GUI (no disruption, terminal's already open) or explicit permission to close the live terminal first for a headless run — parked per Adam's call ("nothing for now").
