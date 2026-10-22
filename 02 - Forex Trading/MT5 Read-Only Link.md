---
status: active
project: forex-trading
type: guide
---
# MT5 Read-Only Link

Jarvis's window into Adam's live MT5 account on the desktop (built 2026-09-29 ~4:15 AM PT, on Adam's "Load it up"). Replaces screenshots for balance, positions, history and broker prices.

**Where:** `C:\Users\aland\mt5-readonly\` — venv `.venv` (Python 3.13, `MetaTrader5` 5.0.6231, pandas), script `mt5ro.py`.
**Terminal:** `C:\Program Files\AAAFx Global MT5 Terminal\terminal64.exe` (the only MT5 terminal on the desktop; the backtest toolkit and the RisenAdam terminal live on the VPS). Account **8996721, AAAFxGlobal-5 Real**, leverage 1:500.

**Commands** (run from that folder with `.venv\Scripts\python.exe mt5ro.py …`): `status` (balance/equity and **which login is active**), `positions`, `price SYMBOL` (the broker's own bid/ask/spread), `journal [days]` (closed trades → `journal.csv`: entry, exit, pips, R, net), `risk SYMBOL entry stop [risk%]` (lot size for a 2–3% risk).

**Safety:** the script has no order functions (no `order_send`/`order_check`/close/modify; checked with grep). **Status 2026-09-29: the terminal auto-logs in with the saved MASTER (trading) password**; `status` reports "TRADING-CAPABLE" and warns. **Pending (Adam):** create an investor password (Tools → Options → Server → Change, typed by Adam), then log the desktop terminal in with it so the broker's server blocks trading. Never put either password in the vault or in chat. Gold pips = 0.1 (fixed after the first run showed 10× values).

**First read (2026-09-29):** balance $168.98, no open positions. See [[Review Trades and Risk Management]] for the 45-day journal findings.

**Overnight watcher:** `watch.py` (read-only, no order functions) polls one symbol every 30s and logs pending → filled → closed with the best/worst run to `watch.log`; 12h cap. Run it in the background with the venv python. First used 2026-09-29 for the AUDUSD sell limit.

**Rejected 2026-09-29 (~4:50 AM): ariadng/metatrader-mcp-server + its `claude-skill/trading/SKILL.md`.** It gives Claude live order placement, modification and closing. Its skill says "When the user asks to trade, execute immediately — no additional confirmation needed", there are no size/loss/leverage limits, and market orders go in first with the SL/TP added in a second call (briefly unprotected). Its last push was ~6 months ago, and Grok's upgrade report rejected it too. It conflicts with the confirm-first rules and with Jarvis never executing trades. Adam places trades; Jarvis reads, sizes, and watches.
**Rejected 2026-09-29 (~4:55 AM): Qoyyuum/mcp-metatrader5-server** (226★; the GitHub page now shows MIT, where Grok's report said no license). It exposes `order_send`/`order_check` and position/order management, with no read-only mode or limits. Same verdict: no MCP that can trade goes on Adam's real account.
**Skipped 2026-09-29 (~5:00 AM): masdevid/mt5-quant** (38★, MIT). Research/backtest only (compile, backtest, optimize, 89 tools), no live trading, so it's safe in kind. But it's built for macOS/Linux running MT5 under Wine; Adam's machines are Windows, and it duplicates [[MBT (MT5 Backtest Toolkit)]].

## Known bug: `risk` under-states gold risk 100× (found 2026-09-29, fix pending Adam's OK)
AAAFx reports XAUUSD `trade_tick_value` = 0.01 per 0.01 tick, but real P/L is **$1 per $1 move per 0.01 lot**. That was checked with `order_calc_profit` and matches Adam's real 9/29 gold fills. `risk XAUUSD 4205 4232` said 0.17 lots for $4.59; the truth is $459. Forex symbols are unaffected (EURUSD checked: 0.01 lot × 10 pips = $1.00). Planned fix: compute the per-lot risk with `order_calc_profit` instead of the tick value. **Until then, don't trust `risk` on gold.**
Also noted: the terminal's local history was missing the 9/28–9/29 bars when pulled via `copy_rates` (it jumped from 9/25 to 9/30). Use the TradingView feed for structure until it backfills.
