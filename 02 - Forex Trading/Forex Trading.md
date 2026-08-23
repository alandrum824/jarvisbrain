---
status: active
project: forex-trading
type: index
---
# Forex Trading

Adam's forex trading: platforms, the EA that runs it, and the recurring work of reviewing and managing risk.

## Notes in this folder
- [[Review Trades and Risk Management]] — Job: reviews and analyzes TWP ORB EA trades and manages risk.
- [[Build TWP Set Files]] — Job: helps Adam build/edit TWP ORB EA `.set` files — the real file format, and a parameter glossary (confirmed vs. unconfirmed).
- [[TWP24 EURUSD Sets]] — the five grid-off session set files built for TWP ORB, and the open lot-sizing/login items against them.
- [[TWP ORB EA Reference]] — captured config/trade-history from two other TWP accounts (108.181.193.243, D3101:81322); raises open questions on SL=0.0, contradictory grid settings, and account identity.
- [[Forex Economic Calendar]] — free no-key feed for high-impact USD/EUR news events, used to flag news-risk on trades.
- [[TradingView Chart Drawing]] — reliable procedure for reading/drawing on Adam's live TradingView chart via the browser tool.
- [[Chart Analysis Notes]] — running log of discretionary chart analysis, levels, and terminology, so sessions don't start cold.
- [[TWI True North]] — custom TradingView Pine indicator built with Jarvis: Break of Structure / Change of Character sets direction, Previous Day POC decides accept-vs-reject entry timing, 10 scored confluences (none of them gates), HTF bias as context not score, live trade-state tracking. Replaced [[Momentum Signal Suite]] (archived) same night after the older EMA-cross trigger was caught selling a pullback in an uptrend.
- [[TWI Sniper ORB]] — Adam's own MQL5 EA (opening range breakout + FVG/demand sniper retrace), generated via SuperGrok's "Build with Grok" and maintained by Jarvis. Asset-profile system runs gold and forex off the same logic with separately scaled inputs; not yet compiler-verified or live-tested.
- [[Malaysian SNR x Orderflow]] — Pine v6 indicator: body-based A/V support-resistance levels, Open-Close/gap levels, Fresh-vs-Unfresh tracking, engulfing markers, MTF projection. Live on the chart alongside TWI True North; also holds the hard-won gotcha about the Pine Editor being a single slot.
- [[Forex Trading Fundamentals]] — Jarvis's general forex knowledge base (risk management, sessions, ORB, ICT/SMC concepts), researched to ground the applied lessons in this folder against real trading practice.
- [[TWI Scalp Pro]] — new MQL5 EA built by Jarvis (not Grok) from Pat's "Trade the Trend" aggressive ORB playbook: per-session opening ranges, H1 trend filter, day-of-week filter, fixed or dynamic-balance lot sizing, concurrent/per-session trade caps. Compiled clean (0 errors/warnings) on both RisenAdam and RisenMOM terminals; not yet compiled on the main desktop machine's AAAFx terminal; not attached to any chart; no backtest run yet.
- [[TWI Range Breakout]] — MQL5 EA, time-based opening range + pending Buy/Sell Stop breakout. v1.20: Asia/London/New York/Custom run as independent concurrent sessions (own magic numbers each), per-session static lots, day-of-week filter, max-open/per-session/daily-loss/daily-profit/spread guardrails. Built 2026-08-21 from Adam's spec, compiler-verified clean at every revision, deployed to the RisenAdam terminal's Experts folder but deliberately not attached to any chart.
- [[EA Licensing and Anti-Piracy]] — brainstorming how to protect [[TWI Range Breakout]] and [[TWI Scalp Pro]] if Adam sells them: account-locking vs. MQL5 Market vs. a TWP-style phone-home license backend on Base44 (the option Adam's leaning toward). Idea stage, nothing built.
