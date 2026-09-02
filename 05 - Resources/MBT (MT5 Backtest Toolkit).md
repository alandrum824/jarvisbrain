---
status: active
project: forex-trading
type: reference
---
# MBT (MT5 Backtest Toolkit)

Third-party MCP server installed 2026-09-01 after every headless MT5 Strategy Tester attempt through the existing [[mt5]] bridge failed repeatedly (RisenAdam, RisenMOM, terminal restarts, closing the Tester GUI panel — nothing got a `metatester64` process to spawn). Adam found it: `https://github.com/FXDavid-OffbeatForex/MBT`. Purpose-built for exactly this — drives MT5's real headless Strategy Tester (real spread/swap/execution) and hands results back programmatically, plus signal-replay backtesting for indicators and EA compilation.

**Not from Anthropic or MetaQuotes — a third-party, unverified repo.** Installing it as an MCP server grants it real code-execution and file/terminal access. Adam explicitly approved the install.

## Where it lives
- Repo: `C:\Users\Administrator\mbt`
- Python: dedicated venv at `mbt\.venv` (Python 3.12.14, reusing the same interpreter that already works for [[mt5]] — the MetaTrader5 pip package doesn't have wheels for the system's default Python 3.14 yet)
- Registered as MCP server `mbt`: `claude mcp add mbt "C:/Users/Administrator/mbt/.venv/Scripts/python.exe" "C:/Users/Administrator/mbt/mcp_server.py"`

## Real bug hit and fixed during install
`requirements.txt` pins `mcp>=1.0.0`, which pip resolved to the latest `mcp` 2.1.1 — but the server's own code (`from mcp.server.fastmcp import FastMCP`) is written against the 1.x API, which was renamed/restructured in 2.x. Server crashed on every connection attempt (`ModuleNotFoundError: No module named 'mcp.server.fastmcp'`) until pinned back with `pip install "mcp<2" --upgrade` inside the venv (landed on mcp 1.29.1). If this repo is ever reinstalled from scratch, expect to hit this again — the installer's `requirements.txt` itself needs that pin, not just a one-time fix.

## Config (`mbt\config.yaml`)
- `mt5_path`: RisenAdam's terminal (`C:/Program Files/RisenAdam/terminal64.exe`)
- `default_symbol`: XAUUSD, `default_timeframe`: M5 — matches tonight's main testing focus
- `tester.default_model`: set to **`every_tick`**, not the template's default `open_prices` — a low-fidelity tick model already produced one real false-positive backtest result tonight ([[TWI OB Hunter]]) on a wick/sweep-sensitive EA. Don't loosen this without a real reason.
- `tester.default_leverage`: 500 (matches the account setups used tonight)
- Installer auto-copied `SignalLogger.mqh` and `MBT_IndicatorHost.mq5` into **both** RisenAdam's and RisenMOM's MQL5 folders. `MBT_IndicatorHost.mq5` compiled clean (0 errors/0 warnings) in RisenAdam only so far — compile it in RisenMOM too before using `run_indicator` there.

## Status
Installed, tools load correctly after a Claude Code restart. **`run_strategy_tester` confirmed working end-to-end (2026-09-01) — but only after finding and fixing the critical bug below.** Trust a result only after verifying the Tester Journal actually loaded the intended `.ex5` (see the mandatory verification step below) — MBT's own JSON response cannot be trusted alone to confirm this.

## CRITICAL bug found (2026-09-01): wrong path separator silently substitutes a completely different EA
Passing `expert="Advisors/TWI_PatORB_Smart_v1"` (forward slash) to `run_strategy_tester` does **not** fail — MBT returns a normal-looking successful response with a real metrics-bearing HTML report. But MT5's own tester `.ini` format requires a **backslash** for subfolder paths (`Expert=Advisors\TWI_PatORB_Smart_v1.ex5`); a forward slash fails to resolve and MT5 silently falls back to whatever Expert was last loaded in that terminal — in this case, its own **stock `Experts\Examples\Moving Average\Moving Average.ex5`** — and tests *that* instead, with zero error or warning anywhere in MBT's response.

This produced a real, plausible-looking, completely wrong backtest for [[TWI PAT ORB SMART]] tonight: net -$340.74, 2,036 trades/year, which was written up as a "confirmed session-gating bug" in the EA before this was caught. It wasn't a bug in the EA at all — Moving Average has no session logic, so of course it traded constantly. The mistake was only caught by adding temporary debug `Print()` instrumentation to the real EA and noticing the debug lines never appeared in the Tester Journal — then finding the Journal's own `"expert file added: Experts\Examples\Moving Average\..."` line, which had been sitting there the whole time and was never checked.

**Fix:** always pass `expert=` with backslashes for subfolder paths, e.g. `"Advisors\TWI_PatORB_Smart_v1"` (in a JSON/MCP call this needs escaping per the client, e.g. `Advisors\\TWI_PatORB_Smart_v1`).

**Mandatory verification, every run, no exceptions:** after any `run_strategy_tester` call, grep `<data_path>/Tester/logs/<YYYYMMDD>.log` (the *Terminal's* Tester log, not the Agent log below) for `"expert file added"` / `"testing of"` and confirm the path matches the EA you actually intended. A "successful" MBT response with real metrics is not sufficient proof the right EA ran.

**Where EA `Print()`/Journal output actually lives** (not in the Terminal's own `Tester/logs/`, which only has engine-level messages): `C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\<terminal-data-dir-id>\Agent-127.0.0.1-<port>\logs\<YYYYMMDD>.log`. This is the only place to see an EA's own `Print()`/`PrintFormat()` output from a headless tester run — the exported `.htm` report never includes it.

## Performance trap: on-chart drawing can make a real EA time out entirely (2026-09-01)
A visually-rich EA (dashboard `Comment()`/chart-object panel, zone boxes, per-trade markers — see [[TWI PAT ORB SMART]]) redrawing on every tick can be **catastrophically slower** in the tester than a trivial EA, especially under `every_tick` over a long date range: MT5's stock Moving Average example finished a full year in ~20s; the real ORB EA with dashboard+zone drawing enabled couldn't finish the same range inside a 1800s (30 min) timeout, twice, even after chasing several dead-end theories (bumping `config.yaml`'s `timeout_sec` — doesn't work, see below; guessing at MT5's tester-profile auto-load filename convention for a dotted broker symbol like `XAUUSD.sim` — never confirmed working). The real fix: **disable on-chart drawing for headless runs** (flip the EA's own `InpShowDashboard`/`InpDrawZones`-style inputs to false via a `.set` file — see the reliable override method below). Doesn't touch trading logic, only visualization; a 30+-minute timeout became a 95-second real run once applied. If a headless run of ANY visually-active EA is slow or timing out, suspect chart-object drawing first, especially `DrawTradeMarker()`-style calls that create a new uniquely-named object per trade (never cleaned up) — that compounds across a long backtest.

## `config.yaml` is cached at MBT server startup — edits mid-session do nothing
Editing `mbt/config.yaml` (e.g. bumping `tester.timeout_sec`) has **no effect on a currently-running MBT server** — `core/connection.py`'s `load_config()` caches the parsed config in a module-level variable for the life of the process, exactly like the "new server, needs a Claude Code restart" issue that applied when MBT was first installed. A config edit only takes effect after the next full session restart. Within a session, don't bother editing `config.yaml` to fix a live problem — use the reliable override method below instead.

## The reliable way to override EA inputs or the timeout: bypass the MCP tool, call MBT's Python directly
The exposed `run_strategy_tester` MCP tool only forwards `expert/symbol/timeframe/from_date/to_date/model/deposit` — but the real underlying function, `core.tester.run_strategy_tester()` (imported into `mcp_server.py` as `_run_tester`), also accepts **`set_file`** (a `.set` file path, written into the launch `.ini` as MT5's standard `ExpertParameters=<path>` directive — the real, documented mechanism MT5 uses for input overrides) and **`timeout_sec`** (a per-call override, sidestepping the config-caching problem above). Neither is wired into the MCP tool's exposed parameters.

To use them anyway: write a small script that imports `core.tester.run_strategy_tester` directly and run it with MBT's own venv interpreter, e.g.:
```
"C:/Users/Administrator/mbt/.venv/Scripts/python.exe" a_script_that_imports_core.tester.py
```
The `.set` file itself is the standard MT5 format — one `Key=current||default||min||max||flag` line per input (same format MT5 itself writes when you save inputs from the Tester GUI; grab a real example from any `MQL5/Profiles/Tester/*.set` file already on disk rather than guessing the syntax). This is the path that actually got [[TWI PAT ORB SMART]]'s dashboard disabled — the disk-based tester-profile auto-load filename convention (`<Expert>.<Symbol>.<Period>.<FromDate>_<ToDate>.<idx>.ini` in `MQL5/Profiles/Tester/`) was tried first and never worked, possibly because MT5 also appears to cache "last-used inputs per Expert" internally regardless of the compiled binary's declared defaults or that filename convention — renaming the terminal's `bases/strategy.dat` didn't reset it either. The explicit `ExpertParameters=` / `set_file` route is the only one confirmed to actually work.

Reusable artifacts left in place for next time: `mbt/dashboard_off.set` (this EA's full input set with drawing disabled) and `mbt/run_real_test.py` (the direct-call script pattern — copy and adjust `expert=`/`symbol=`/dates/`set_file=` for a different EA or run).

## Other real gotchas found running it (2026-09-01)
- **`tester.terminal_path` vs. top-level `mt5_path` disagree in `config.yaml`** — top-level `mt5_path` is RisenAdam, but `tester.terminal_path` (what `run_strategy_tester` actually launches) is **RisenMOM**. Not yet reconciled/fixed in the config; just worked around by confirming the EA is deployed to both terminals and checking RisenMOM's own symbol names before each test.
- **RisenMOM is logged into OANDA-Demo-1, not AAAFxGlobal** — its gold symbol is `XAUUSD.sim`, not `XAUUSD` (confirmed via the [[mt5]] bridge's `mt5_get_symbols`). A bare `XAUUSD` fails with `symbol XAUUSD not exist` in the Tester log. Check the real symbol name per-broker before every run rather than assuming the plain ticker.
- **MT5 is single-instance per data dir — a live terminal window blocks the headless tester.** Calling the `mt5` bridge's `mt5_connect` against RisenMOM (e.g. just to check symbols) launches/attaches a live terminal instance; the next `run_strategy_tester` call then just forwards to that live instance instead of running headless, and returns in ~2s with nothing. Fix: force-close that `terminal64.exe` process before calling `run_strategy_tester` again.
- **When `run_strategy_tester` "fails," the JSON error alone is not enough to diagnose it** — check the real MT5 Tester log at `<data_path>/Tester/logs/<YYYYMMDD>.log` (one-line-per-event, tab-separated) for the actual reason. But per the critical bug above, checking it only when MBT reports failure isn't enough either — check it (or the Agent log) every run to confirm which EA actually loaded.

## Related
- [[TWP ORB EA Reference]] / [[TWI OB Hunter]] / [[TWI PAT ORB SMART]] — the EAs this exists to actually test.
