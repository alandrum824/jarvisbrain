---
status: active
project: forex-trading
type: reference
---
# TWI Range Breakout

MQL5 Expert Advisor, built by Jarvis 2026-08-21 from a spec Adam supplied via screenshots of René Balke's "Professional MQL5 Programmer Tests Claude Code" video/prompt, then extended the same session with real guardrails. Not a rebuild of [[TWI Sniper ORB]] or the third-party [[TWP ORB EA Reference|TWP ORB EA]] — a separate, simpler time-based range breakout.

**Deployed, not attached — per Adam's explicit instruction ("build this and put in my risen live account but not a chart").** File sits in the RisenAdam MT5 terminal's Experts folder, compiled clean, but nothing is running until Adam attaches it to a chart himself.

## What it does (per session — see Sessions below)
1. During that session's Start → End time (broker server time), tracks the highest and lowest Bid tick-by-tick.
2. Once the range window closes, places a **Buy Stop at the range high** and a **Sell Stop at the range low**.
3. If a pending order can't be placed (already broken out at that exact tick, broker min-stop-distance violation, outright rejection, or the spread's too wide), it falls back to a **market order** the moment price actually breaks that level — watched every tick until it fires or the cycle closes.
4. At that session's own Close time: deletes any unfilled pending orders, closes that session's own open positions, and opens nothing further until its next cycle.

## Sessions (`InpSessionPreset`, v1.10 → rebuilt v1.20)
**v1.20 rewrite: Asia / London / New York / Custom now run as four fully independent, concurrent cycles**, not one shared window — each has its own Start/End/Close hours, its own range, its own orders, its own close time. `InpSessionPreset` (All / Asia / London / New York / Custom) picks whether to run every session that's individually enabled (`InpUseAsia`/`InpUseLondon`/`InpUseNewYork`/`InpUseCustom`) or restrict to just one — same two-layer pattern as [[TWI Sniper ORB]]'s session system, same default hours (Asia 00:00–04:00, London 08:00–12:00, New York 13:30–17:00 — verify against the actual broker before trusting them).

A shared clock for "when to give up and flatten" stopped making sense once sessions run at different times of day, so **each session also has its own Close hour/minute** (Asia/London/NY default to 4h after their own range ends; Custom keeps the original manual close time).

Each session uses its own **magic number** (`InpMagic + session index`, e.g. Asia = base+0, London = base+1) so sessions can never delete or close each other's orders/positions — verified structurally, not just by convention.

## Lot sizing (`InpLotMode`)
- **Risk Money** — fixed $ risk (`InpRiskAmount`, one shared value) against that day's actual SL distance.
- **Fixed Lots** — a **static lot size set per session** (`InpAsiaFixedLots` / `InpLondonFixedLots` / `InpNYFixedLots` / `InpCustomFixedLots`), since Asia/London/NY can have very different typical range sizes and Adam asked for this to be settable per session, not one shared number.

## Risk / targets
SL = range size × `InpSLFactor`. TP = range size × `InpTPFactor` (**0 disables TP** — the trade only closes at its session's close time or its stop).

## Trade mode (`InpTradeMode`) — applies within each session independently
- **Both** — both pendings can fill independently.
- **Buy Only** / **Sell Only** — only that side is ever placed.
- **OCO** — both are placed; the instant one fills (via `OnTradeTransaction`, matching the fill deal's `DEAL_ORDER` back to the ticket that was placed, magic-matched to the right session) the other pending is deleted. This is the literal "trade only one per session" behavior Adam asked for. Generalizes to `InpMaxTradesPerSession=1` too (see Limits) if he ever wants that without switching trade mode.

## Guardrails (added v1.20)
- **Day-of-week filter** — 7 independent toggles (`InpTradeMonday`…`InpTradeSunday`, weekend off by default). Checked against the date each session's *range* falls on; a disabled day still builds/draws the range (useful to look at) but never places an order.
- **Max open trades at a time** (`InpMaxOpenTrades`, default 4) — hard cap on concurrent open positions **across all four sessions combined**, checked before every single order (pending placement and market fallback alike).
- **Max trades per session** (`InpMaxTradesPerSession`, default 2) — once a session's own fill count reaches this, any remaining pending for that session is cancelled immediately, whatever the trade mode.
- **Max daily loss / profit** (`InpMaxDailyLoss` / `InpMaxDailyProfit`, account currency, 0 = off) — real daily P/L pulled from `HistoryDeals`, filtered to only this EA's own magic range (never counts a trade placed by [[TWI Sniper ORB]] or the TWP ORB EA on the same account). Once hit, **blocks new trades**; matches [[TWI Sniper ORB]]'s own precedent of not force-closing existing positions, just stopping new ones.
- **Max spread** (`InpMaxSpreadPoints`, 0 = off) — skips placing an order (pending or fallback market) while the live spread is over cap; wasn't in the original spec, added because a live-money EA with zero spread awareness is a real gap the other EAs already learned the hard way (see [[TWI Sniper ORB]]'s forex spread-cap fix).
- **Slippage / deviation** (`InpSlippagePoints`, default 30) — set on the `CTrade` object before every market order, so fallback fills don't get rejected on requote in fast conditions.

## Overnight range handling
Each session's cycle is **not tied to calendar midnight** — `ComputeSessionCycle()` walks from yesterday through day+2 looking for the first cycle whose close time hasn't happened yet, relative to whatever time the EA evaluates. An end time before the start time correctly spans midnight; the EA can be attached mid-range-build or mid-monitoring-window without skipping straight to tomorrow.

## Timeframe (`InpAutoSetChartTF` / `InpChartTF`)
The EA's own logic never reads chart bar data — it works off tick price (`SymbolInfoDouble` Bid/Ask) and `TimeCurrent()` only, so it's timeframe-independent by design (matches [[TWI Sniper ORB]]'s same property). `InpAutoSetChartTF` (on by default) calls `ChartSetSymbolPeriod()` in `OnInit` to snap the chart to `InpChartTF` (default M15) automatically, so Adam never has to switch it by hand.

## Visuals
Per session: a rectangle over its range window (`OBJ_RECTANGLE`, live-updating while building, object names prefixed per session so four can be on screen at once without collision), dotted lines (`OBJ_TREND`, `STYLE_DOT`) extending from that session's range high/low out to its own close time. Status `Comment()` lists every active session's state on its own line, plus running Day P/L and a loud flag if the daily limit's been hit.

## Build/verify record
- Written directly to `...\Terminal\C3F62A8326295558A052069AC3E69E3E\MQL5\Experts\Advisors\TWIRangeBreakout.mq5` (the RisenAdam terminal — confirmed via `origin.txt`, matching where [[TWI Sniper ORB]]'s compiled `TWIORB24.ex5` already lives).
- **Compiler-verified**, not just structurally checked — ran `MetaEditor64.exe /compile /log` directly each revision (first time Jarvis has had real compiler access on this machine).
- **v1.00** (2026-08-21): first pass 0 errors, 2 warnings (`uint`→`int` truncation). Fixed, recompiled clean.
- **v1.10** (same session): added session presets (single-window version) and auto-timeframe. Clean: 0 errors, 0 warnings.
- **v1.20** (same session): full rewrite to independent concurrent sessions, per-session fixed lots, day-of-week filter, max-open/max-per-session/daily-loss/daily-profit/max-spread/slippage guardrails, per-session magic numbers. Clean on first compile: **0 errors, 0 warnings.**
- `TWIRangeBreakout.ex5` confirmed present alongside the source, rebuilt after each change (verified by file timestamp, not just the compiler's own success message).
- Not attached to any chart, not backtested, not run live. Adam needs to attach it himself and enable AutoTrading before it does anything.

## Key inputs (quick reference)
- `InpSessionPreset` (All/Asia/London/NewYork/Custom) + `InpUseAsia/London/NewYork/Custom` — which sessions actually run.
- Per session: Start/End/Close hour+minute, and (Fixed Lots mode) that session's own static lot size.
- `InpLotMode` (Risk Money / Fixed Lots), `InpRiskAmount`, `InpSLFactor`, `InpTPFactor` (0 = no TP).
- `InpTradeMode` (Both / Buy Only / Sell Only / OCO).
- Day-of-week toggles, `InpMaxOpenTrades`, `InpMaxTradesPerSession`, `InpMaxDailyLoss`, `InpMaxDailyProfit`, `InpMaxSpreadPoints`, `InpSlippagePoints`.
- `InpMagic` (base — each session adds its own index), `InpComment`.

## Open / next
- **Not backtested** — worth a Strategy Tester pass before Adam trusts it with real size, same lesson as [[TWI Sniper ORB]]'s default-risk-mode near-miss. MT5's Strategy Tester runs one symbol/magic-range at a time, so a multi-session test will show all four sessions' combined activity in one pass — worth a look at per-session breakdown too if the numbers look mixed.
- Which pair/instrument this actually works best on is genuinely unknown — no empirical basis yet, only the structural guess that session-driven breakouts tend to do better on majors during London/NY overlap or on gold (per [[TWI Sniper ORB]]'s own backtest split). Needs real testing, not a guess.
- Range is built from **Bid** ticks only; entries execute at whatever the broker actually fills — the pending stop price itself is set exactly at the tracked Bid extreme, so real fills can be a few points beyond it. No entry buffer was requested and none was added.
- "One trade per day" in the original spec is now interpreted as **one trade per session** (OCO scoped to each session independently) since sessions are now independent cycles — if Adam actually wants one trade across *all* sessions combined for a day, that's a different, not-yet-built mechanism.

## Related
- [[TWI Sniper ORB]]
- [[TWP ORB EA Reference]]
- [[Active Priorities]]
