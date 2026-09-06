---
status: active
project: forex-trading
type: reference
---
# Polymarket Pipeline

Third-party repo (`github.com/brodyautomates/polymarket-pipeline`), cloned 2026-09-06 to `C:\Users\Administrator\polymarket-pipeline`. Real automated news-to-trade system: monitors breaking news (Twitter/Telegram/RSS), classifies bullish/bearish with Claude, detects edge against niche Polymarket markets (<$500K volume), and can execute trades.

## Not from Anthropic — a third-party, unverified repo
Same caveat as [[MBT (MT5 Backtest Toolkit)]]. Installed for its analysis tooling (news monitoring, edge detection, backtesting), not trusted blindly for execution.

## Deliberately NOT wired for live trading
This repo can place real orders (`executor.py`, `--live` flag). Jarvis does not execute financial trades — same boundary as declining to run the raw Polymarket order-placement Python snippet Adam pasted earlier the same night. Structural safeguards in place, not just a config flag:
- `DRY_RUN=true` in `.env` (the repo's own default)
- Polymarket trading credentials (`POLYMARKET_API_KEY`/`SECRET`/`PASSPHRASE`/`PRIVATE_KEY`) left blank in `.env` — never filled in
- `py-clob-client` (the library that actually places live orders) was **not installed** — commented out in `requirements.txt`, skipped on purpose. Even a stray `--live` flag can't execute without it.

## Setup status (2026-09-06)
- Cloned, venv created at `.venv` using the real Python interpreter (`C:\Users\Administrator\AppData\Local\Python\bin\python.exe`, 3.14.7) — NOT the Microsoft Store stub at `AppData\Local\Microsoft\WindowsApps\python.exe`, which throws `Permission denied` (same class of gotcha as [[MBT (MT5 Backtest Toolkit)]]'s Windows-Python trap).
- All dependencies installed except the live-trading client (deliberately).
- `python cli.py verify` output: everything PASSES except **Anthropic API key not set** (required — the pipeline calls the real Claude API directly, independent of Claude Code's OAuth session, so it needs its own key from console.anthropic.com). RSS scraper, public Polymarket market data, niche-market filter, and the SQLite DB all confirmed working live with zero keys.
- Twitter/Telegram/NewsAPI keys are optional (RSS fallback works without them) — not set, not needed yet.

## What already works right now, no key needed
- `python cli.py niche` — real live niche-market browser (volume-filtered, $1K-$500K), verified working.
- `python cli.py markets` — browse all active Polymarket markets.
- `python cli.py scrape` — RSS news scraper test.

## What's blocked until Adam supplies a real Anthropic API key
Classification (`classifier.py`), the full `watch`/`run` pipeline, `backtest`, and `calibrate` — anything that asks Claude to classify news. Adam needs to generate this himself at console.anthropic.com and hand it over to drop into `.env` — not something Jarvis creates on his behalf (an account/billing action).

## Related
[[Polymarket (Prediction Markets)]] — the read-only odds-lookup pairing already built tonight for sports decisions; this pipeline is a separate, heavier system aimed at general news-driven edge detection across all Polymarket categories, not just sports.
