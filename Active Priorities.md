---
status: active
project: meta
type: plan
---
# Active Priorities

The single queue of open work across everything. Tag each item with its project where it isn't obvious. Add an item when work is parked; delete it when it's actually done (don't let it rot). This is the system of record for "what's still open" — a daily note's "In Progress" is a frozen snapshot that goes stale the moment something closes, so never treat an old daily note's open items as current truth.

### Open Tasks
- [ ] Ongoing: review and analyze TWP ORB EA trades and manage risk (forex-trading) — see [[Review Trades and Risk Management]].
- [ ] Resize the TWP24 EURUSD set files' lot sizing for an $800 account, per Adam's stated risk tolerance; confirm with him before final (forex-trading) — see [[TWP24 EURUSD Sets]].
- [ ] **Resolved (2026-08-21):** account ending 8996721 = server "AAAFxGlobal-5 Real", confirmed live via the RisenAdam MT5 terminal (`MetaTrader5` Python package, `account_info()`) — balance $391.39, algo/EA trading enabled. Not login-failing; the earlier note was wrong. The separate AAAFx Global MT4 Terminal install still has a stale login for presumably the same account — low priority now that the MT5 side works (forex-trading) — see [[TWP ORB EA Reference]].
- [ ] **Balance mismatch (2026-08-21):** the lot-sizing resize task below assumed an $800 account; account 8996721's real balance is **$391.39** — confirm with Adam which number (or account) the resize should actually target before touching anything (forex-trading) — see [[TWP ORB EA Reference]].
- [x] **Fixed by Adam (2026-08-21):** switched the EA to static lot size 0.01 on account 8996721. Confirmed in the terminal log and via the MT5 bridge: a same-SL signal (4536.17, "TWI Sniper") that had failed at 1.58 lots fired clean at 0.01 lots — open position using $9.10 margin against $385.62 free, no more "No money" rejections (forex-trading) — see [[TWP ORB EA Reference]].
- [ ] Sort out which TWP account is which — account 8996721 now resolved (see above); still need to place config account 108.181.193.243 and trade-history account D3101:81322 relative to it before trusting any config/lot-sizing reference (forex-trading) — see [[TWP ORB EA Reference]].
- [ ] Confirm with TradeWithPat docs/support whether SL=0.0 in ATR mode means "no stop loss" or "use default ATR multiplier," and whether the grid + "trade only if no other open trade" settings are actually contradictory — both open on the 108.181.193.243 config (forex-trading) — see [[TWP ORB EA Reference]].
- [ ] Connect the "Elijah Learning Academy" Base44 app to Think Wave, once the Think Wave login is available (education/base44) — see [[Elijah Learning Academy]].
- [ ] Ongoing: grow @juvenilevirtue's TikTok following, story-first per the evidence gathered (personal) — see [[Grow Juvenile Virtue on TikTok]].
- [ ] Go deeper than name/ID on Adam's 92 Base44 apps (corrected from an initial ~50 estimate) — full list now in [[Base44 Apps]], categorized by theme but unexplored beyond that; only [[Elijah Learning Academy]] and [[Juvenile Virtue]] have real depth (meta).
- [ ] Publish the pending jvsession.com batch from the Base44 dashboard — real favicon/OG image swap, `public/robots.txt` + `public/sitemap.xml` — code done, needs Adam's Publish click (personal) — see [[Juvenile Virtue]].
- [ ] Decide on the "Ridin Drawdown" song (forex terminology, no faith framing — fits the brand or not?) and whether to fill in the missing story fields on 8 of 10 songs (personal) — see [[Juvenile Virtue]].
- [ ] Brainstorm a revamp for mom's eBay store (EMarketingTX) before she shuts it down — sales dried up, no account access yet, real goal is clearing house space not growth, still at the idea stage (personal) — see [[Mom's eBay Store (EMarketingTX)]].
- [ ] Decide the niche/products for two separate no-overhead print-on-demand stores (one for Adam, one for mom) before building — see [[Automated POD Stores (Adam and Mom)]].
- [ ] **Partially done (2026-08-22):** [[TWI Scalp Pro]] is now placed and compiled clean (0 errors/warnings) on both RisenAdam and RisenMOM terminals on this machine, not attached to any chart. Still not compiled on the main desktop machine's AAAFx terminal, and no backtest run anywhere yet (forex-trading).
- [ ] Design and build the license-check backend for selling [[TWI Range Breakout]] and [[TWI Scalp Pro]] — idea stage, leaning toward a Base44-hosted phone-home license (TWP-style TOS/username/activate flow) over simple account-locking or MQL5 Market; nothing built yet (forex-trading) — see [[EA Licensing and Anti-Piracy]].
- [ ] Cosmetic cleanup: rename/delete the now-unused original "Malaysian SNR x Orderflow" script (the chart now correctly runs off the duplicate, "...1" — functionally fine, just messy in the script list) (forex-trading) — see [[Malaysian SNR x Orderflow]].

- [ ] Add Grok/xAI into the working system — specifically **SuperGrok's "Build with Grok"**, a coding agent inside the Grok app (like Claude Code, but built-in) that generates full apps/EAs/indicators from a prompt. Adam's using it right now to build an MQL5 Expert Advisor matching his "sniper ORB" strategy. Wants it as a "second brain" alongside Jarvis — Grok handling MQL5/EA generation, Jarvis handling TradingView/Pine + vault knowledge + orchestration. **Explicit instruction (2026-08-20): "I want everything in Obsidian, that way you have access to everything"** — whatever Grok builds (the MQL5 EA source, its logic/decisions) needs to actually land in the vault, not stay siloed in the Grok app, so Jarvis can see and reason about it. Confirm tomorrow exactly how the handoff works (e.g., does the finished EA get pasted/saved into [[Build TWP Set Files]] or its own note?) (meta).

### Completed Tasks
