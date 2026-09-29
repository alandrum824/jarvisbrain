---
status: active
project: meta
type: reference
---
# Jarvis upgrades, v2: re-ranked for Adam's real setup (2026-09-29)

This was read-only research. Nothing was installed on any of Adam's computers, no accounts were created, and nothing was sent or posted. The only thing cloned was Anthropic's plugin marketplace, and it went to the research box so I could read it.

**How to read the facts below**
- **Repo numbers** (stars, license, last push) come from the GitHub API around 3:30 AM PT on 2026-09-29. "Last push" is shown as a UTC date, so it can be one day off from Pacific time.
- **Claude Code docs** (code.claude.com) show no "last updated" date on their pages, so each doc link below says "no date shown". For scale: Claude Code's current versions on npm are **latest 2.1.284** and **stable 2.1.277**, published 2026-09-28 at 11:03 AM PT. The matching Agent SDK is **0.3.284**.
- **Scope:** everything is judged against Adam's actual setup. That's Windows 11 plus a Windows Server VPS, the Obsidian vault as the only memory, the Jarvis24 → Node Bridge (Agent SDK) → Tailscale Funnel path, tradingview-mcp/TikTok/Playwright, claude.ai connectors, and the MT5 toolkit. It's also held to his hard constraints.

**What changed from the earlier report** (`github-upgrades-2026-09-29.md`, which assumed a stock Mac install): several earlier picks were things he already has, so they're now listed under Overlap. Those are Remote Control, the docs/pdf/xlsx/pptx skills, the marketing skill, Google connectors, Playwright, and scheduling. Two earlier picks break his constraints: the Shopify AI Toolkit *plugin* adds automatic hooks, and knowledge-work-plugins is a large skill pack. The biggest new finding: **Claude Code's own "auto memory" is switched on by default. It is a second memory system, and the Agent SDK Bridge loads it too.**

---

## If you only do five things
1. Turn off Claude Code's built-in auto memory on both machines and in the Bridge (#1).
2. Pin Claude Code versions on both machines, and pin the Agent SDK version in the Bridge (#2).
3. Put your hard rules in a `managed-settings.json` that both the CLI and the Bridge must obey (#3).
4. Harden the Bridge: permission mode, turn and budget caps, a fallback model, and less public exposure (#4).
5. Keep the Bridge alive and watched: run it as a service and add an outside uptime check (#5).

## Ranked top list (15)

| # | Pick | Group | One line |
|---|---|---|---|
| 1 | Switch off Claude Code auto memory (built-in) | Reliable | It's on by default and writes its own notes outside the vault. Turn it off everywhere, Bridge included. |
| 2 | Version pinning on both machines + pinned Agent SDK | Reliable | Both copies stop auto-updating into different versions. The Bridge's Claude Code version is set by the SDK version you pin. |
| 3 | `managed-settings.json` to lock the rules | Reliable | One admin-owned file that the CLI *and* the Bridge must obey: memory off, deny rules, allowed version range. |
| 4 | Harden the Bridge with Agent SDK options (+ Tailscale Serve vs Funnel) | Reliable | Permission mode, deny lists, `maxTurns`, `maxBudgetUsd`, `fallbackModel`, resume by session ID, prewarm, and less public exposure. |
| 5 | WinSW + Tailscale "Run Unattended" + healthchecks.io / Uptime Kuma | Reliable | The Bridge restarts itself, survives reboots, and you get an alert when it's down. |
| 6 | MCP Inspector CLI + `claude doctor` / `claude mcp list` | Reliable | A quick smoke test for tradingview-mcp, TikTok, and Playwright after any update. |
| 7 | MT5 investor (read-only) login for automation | Capable | The broker's server blocks trading, so research and backtest tools can't place orders. |
| 8 | Official read-only data endpoints for PolyEdge | Capable | Polymarket US public gateway (no key), Odds API quota headers, and a warning that ESPN endpoints are unofficial. |
| 9 | Alpha Vantage official MCP | Capable | Read-only FX, macro (CPI, payrolls, Fed funds), and news-sentiment data for risk checks around big releases. |
| 10 | eBay official read-only MCP | Capable | eBay's own server. It only makes read (GET) requests: price comps, item lookups, your own orders. |
| 11 | Shopify **Dev MCP** (standalone, pinned, telemetry off), *not* the plugin | Capable | Shopify's docs and schemas for theme and app work, without the plugin's automatic hooks. |
| 12 | backtesting.py (or vectorbt) | Capable | Fast Python pre-screen of an idea on MT5 history before the slow Strategy Tester run. |
| 13 | Built-in context controls, incl. subagent-only MCP servers | Faster/cheaper | Confirm tool search is on, use `/context` and `/skill-doctor`, turn off unused connectors per folder, and keep heavy MCPs inside subagents. |
| 14 | Lean headless jobs (`claude -p` flags) + the right scheduler | Faster/cheaper | Scheduled jobs load only the one MCP server they need, with turn caps and fixed tool lists. |
| 15 | Anthropic `session-report` skill + ccusage | Faster/cheaper | Shows where tokens actually go: cache breaks, most expensive prompts, and daily totals on both machines. |

---

## RELIABLE

### 1. Switch off Claude Code's built-in auto memory (everywhere, including the Bridge)
- **Link / date:** https://code.claude.com/docs/en/memory#auto-memory and https://code.claude.com/docs/en/agent-sdk/claude-code-features#what-settingsources-does-not-control (no date shown).
- **Problem it solves:** The docs say plainly: *"Auto memory is on by default."* Claude saves its own notes to `~/.claude/projects/<project>/memory/` on each machine. When you say "remember X", the docs say Claude saves it there, not to your vault. That's exactly the second memory layer your rules forbid. The Agent SDK also loads auto memory *regardless of `settingSources`*. So the Bridge on the VPS can quietly build its own memory unless you turn it off there too.
- **What it changes:** One setting. Use `"autoMemoryEnabled": false` in settings (or the toggle in `/memory`), or the environment variable `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. For the Bridge, set that variable in the Bridge process's `env`. The SDK docs name exactly this fix. No installs, no background processes.
- **Risks / reasons not to:** Essentially none. Before switching it off, open `/memory` → auto memory folder on both machines and look for notes Claude already wrote. Move anything useful into the vault by hand, then delete the folder. Also make sure CLAUDE.md tells Jarvis that "remember this" means "write it to the vault".
- **Overlap:** If your CLAUDE.md or a `MEMORY.md` redirect already points auto memory at the vault, you're partly covered. Turning it off is the stricter fix. Also avoid the subagent `memory:` frontmatter field, which gives each subagent its own memory folder (https://code.claude.com/docs/en/sub-agents).

### 2. Pin versions on both machines, and pin the Agent SDK in the Bridge
- **Link / date:** https://code.claude.com/docs/en/setup#configure-release-channel (plus `#pin-a-minimum-version` and `#disable-auto-updates`) and https://code.claude.com/docs/en/agent-sdk/typescript (no date shown).
- **Problem it solves:** Native installs auto-update in the background, so the Windows 11 PC and the VPS can drift to different versions, and a bad release can break both overnight. The fix:
  - **Desktop:** `"autoUpdatesChannel": "stable"`. The docs describe stable as "typically about one week old, skipping releases with major regressions". Add a `minimumVersion` floor so switching channels never downgrades you.
  - **VPS:** `DISABLE_AUTOUPDATER=1` in settings `env`. Update it by hand only after the desktop has run that version for a few days. `claude doctor` confirms the setting: its "Auto-updates" line should read disabled.
  - **Bridge:** The TypeScript Agent SDK *bundles its own Claude Code binary*, and the SDK version tracks it (0.3.284 ↔ 2.1.284). So the Bridge's real version is whatever SDK version is in `package.json`. Pin it exactly (no `^`), commit `package-lock.json`, and upgrade on purpose.
- **What it changes:** Two or three settings keys and one line in `package.json`. No new software.
- **Risks / reasons not to:** You'll get fixes about a week later on stable, and later still on the VPS if you forget to update it. The docs also note that on WinGet installs, an upgrade can fail while Claude Code is running because Windows locks the file. Close sessions before updating.
- **Overlap:** None. This is config for what you already run.

### 3. Lock your hard rules in `managed-settings.json` (applies to the CLI and the Bridge)
- **Link / date:** https://code.claude.com/docs/en/managed-settings , https://code.claude.com/docs/en/permissions , https://code.claude.com/docs/en/sandboxing (no date shown).
- **Problem it solves:** CLAUDE.md rules are requests, and the model can still ignore them. Managed settings are enforced by the program, and Claude can't loosen them from inside a session. On Windows the file lives at `C:\Program Files\ClaudeCode\managed-settings.json`, a system folder that normally needs admin rights to change. The SDK docs say managed policy settings are read *regardless of `settingSources`*, so the Bridge obeys them too. Good contents for you:
  - `autoMemoryEnabled: false` (#1).
  - `permissions.deny` rules for tools that send, post, publish, or spend. Deny rules also accept globs like `mcp__*`, and a bare-name deny removes the tool from Claude's view entirely. Tools from claude.ai connectors show up as `mcp__claude_ai_<server>__<tool>`. List the real names with `/mcp` before writing rules.
  - `requiredMinimumVersion` / `requiredMaximumVersion` to fence the versions both machines will start on.
- **Why this matters extra on Windows:** Claude Code's built-in command sandbox **does not run on native Windows**, only on macOS, Linux, and WSL2. So permission rules are your main hard guard.
- **What it changes:** One JSON file per machine, written as admin. No background process.
- **Risks / reasons not to:** A rule that's too broad can block a job you wanted, and you need admin rights to fix it. Start with a short deny list and grow it. Per-parameter rules for MCP tools (anything with parentheses) are *skipped* in settings files. The docs say to use `--disallowedTools` on the command line for those.
- **Overlap:** Strengthens your CLAUDE.md "confirm before changes" rule; it doesn't replace it.

### 4. Harden the Bridge with Agent SDK options, and reduce public exposure
- **Link / date:** https://code.claude.com/docs/en/agent-sdk/permissions , `/agent-sdk/sessions`, `/agent-sdk/typescript`, `/agent-sdk/hooks`, `/agent-sdk/hosting` (no date shown). Tailscale: https://tailscale.com/kb/1223/funnel and https://tailscale.com/kb/1312/serve (both "Last validated: Jan 20, 2026").
- **Problem it solves:** The Bridge is the part that runs unattended from your phone, so it needs the tightest settings.
  - **Permissions.** For a locked-down agent, pair `allowedTools` with `permissionMode: "dontAsk"`: anything not listed is denied instead of silently allowed. Alternatively, send approvals to your phone with a `canUseTool` callback. The docs warn that tools auto-approved earlier *never reach* `canUseTool`. Deny rules and `PreToolUse` hooks apply even in `bypassPermissions` mode. Never run the Bridge in bypass mode. SDK hooks are code *you* write inside the Bridge, so they stay reviewed and fit your no-auto-hooks rule.
  - **Caps.** Use `maxTurns`, and `maxBudgetUsd`, which stops when the SDK's own cost estimate hits your limit. `fallbackModel` keeps replies coming when the main model is overloaded.
  - **Continuity.** Store the SDK session ID for each phone conversation and pass it to `resume`, so a Bridge restart doesn't lose the thread. `continue` picks up the most recent session.
  - **Speed.** `startup()` spawns the Claude Code process before a prompt arrives, taking spawn and init time off the first reply. (`prewarm()` exists too, but it's alpha.)
  - **Exposure.** Tailscale Funnel puts the Bridge on the **public internet**. It's in beta, limited to ports 443/8443/10000, and has non-configurable bandwidth limits. If the phone running Jarvis24 can run the Tailscale app, **Tailscale Serve** shares the Bridge only inside your tailnet. If Funnel has to stay, the Bridge must check its own secret token on every request.
  - **Login.** The SDK overview says: "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods…" Your personal Bridge isn't a product, but the documented, supported path is an API key. Check which login the Bridge uses so a policy change can't break it.
- **What it changes:** Code and config inside the Bridge, and possibly Tailscale settings. Nothing new installed.
- **Risks / reasons not to:** `dontAsk` will refuse anything you forgot to allow. That's safe, but expect a few "denied" replies at first. The budget cap is a client-side estimate. Moving from Funnel to Serve means the phone must be on Tailscale.
- **Overlap:** Remote Control stays your backup. This makes the main path sturdier.

### 5. Keep the Bridge running and watched: WinSW + Tailscale "Run Unattended" + an outside check
- **WinSW:** https://github.com/winsw/winsw (14,331★, MIT, last push 2026-07-30).
  - Latest **stable** release is v2.12.0 (2023-01-28). v3 is still pre-release (v3.0.0-alpha.11).
  - It wraps any program (here, `node bridge.js`) as a real Windows service with restart-on-failure, using one .exe and an XML file.
  - It solves the Bridge dying on a crash or reboot until someone logs in.
  - **Changes:** installs a Windows service (needs admin once) and writes logs to a folder you pick.
  - **Restart setting:** `<onfailure action="restart" delay="10 sec"/>` in the XML (from the v2.12.0 config docs).
  - **Risks:** the stable release is old, though the repo is still being pushed. WinSW installs services as **LocalSystem by default**. Run the Bridge **as your own Windows user** instead, or it won't find your `~/.claude` settings and login. WinSW's documented way to do that puts the account **password in plain text in the XML file**, which clashes with your no-passwords rule. Instead, leave it out of the XML and set the account once in Windows' Services console (Log On tab), or use a dedicated low-privilege local account just for the Bridge. (The Services-console method is standard Windows, not something from WinSW's docs.)
- **Tailscale "Run Unattended":** https://tailscale.com/kb/1088/run-unattended (last validated Jan 5, 2026). On Windows, Tailscale runs as the logged-in user, so after a VPS reboot "Tailscale won't automatically connect". This mode makes it run as the system. It's a tray setting, not an install.
- **Outside check, pick one:**
  - **healthchecks.io** (hosted; the open-source code is at https://github.com/healthchecks/healthchecks, 10,369★, BSD-3-Clause, last push 2026-09-28). Pricing: Hobbyist $0/month (https://healthchecks.io/pricing/). A tiny scheduled script on the VPS checks the Bridge's local health URL and, if it's OK, pings your healthchecks URL. You get an email or other alert when the pings stop. You'd need to create the account yourself.
  - **Uptime Kuma** (https://github.com/louislam/uptime-kuma, 91,930★, MIT, last push 2026-09-29). Self-hosted. The README lists non-Docker support for Windows 10 x64 / Windows Server 2012 R2+ with Node ≥ 20.4. Run it on the *other* machine (for example, the Windows 11 PC watching the VPS's public URL). The catch: no alerts while that PC is off.
- **Risks / reasons not to:** The health-ping script is code running on a schedule. Keep it a few reviewed lines. Uptime Kuma is a web app with its own login, so keep it local-only.
- **Overlap:** None today.

### 6. MCP Inspector (CLI mode) + built-in health commands
- **Link / date:** https://github.com/modelcontextprotocol/inspector (10,977★, last push 2026-09-28; license moving from MIT to Apache-2.0 per the repo; npm `@modelcontextprotocol/inspector` 2.8.0, published 2026-09-23; needs Node ≥ 22.19.0). Built-ins: https://code.claude.com/docs/en/debug-your-config and https://code.claude.com/docs/en/troubleshooting (no date shown).
- **Problem it solves:** When tradingview-mcp, TikTok, or Playwright breaks after a TradingView or Node update, you find out mid-task. `npx @modelcontextprotocol/inspector@2.8.0 --cli` connects to a server, lists its tools, and can call one, with JSON output and exit codes. The repo has a "Smoke-testing an MCP server" guide. Pair it with:
  - `claude mcp list` (shows server status),
  - `claude doctor` (read-only install and settings check from the shell),
  - `/doctor` inside a session (it proposes fixes and asks before applying them),
  - tradingview-mcp's own `tv_health_check`.
- **What it changes:** Nothing permanent. It runs through npx when you call it. Use `--cli`, not the web UI.
- **Risks / reasons not to:** Only call read-only tools in tests. On machines with no OS keychain it stores secrets in a plaintext file (Windows has one, but check). The v2 line changed its CLI flags from v1.
- **Overlap:** `/mcp` already shows connection status. The Inspector adds scriptable, repeatable tests.

---

## CAPABLE

### 7. Use the MT5 **investor (read-only) password** for any automated MT5 session that only reads
- **Link / date:** https://www.metatrader5.com/en/terminal/help/startworking/authorization (no date shown). Return codes: https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes (no date shown). Python package `MetaTrader5` 5.0.6231 on PyPI (uploaded 2026-09-27).
- **Problem it solves:** MetaQuotes' own help says: *"Investor authorization allows you to see the account status, analyze prices, and work with your own Expert Advisors, but not trade."* That's a server-enforced read-only mode. It makes your backtest toolkit, and any MT5 MCP you ever try, unable to place trades even if an agent misfires. Turning off the terminal's Algo Trading button adds a second, client-side block: orders then fail with code 10027 "Autotrading disabled by client terminal".
- **What it changes:** Which password your toolkit's `initialize/login` uses. Keep it in Windows Credential Manager or an environment variable, never in the vault.
- **Risks / reasons not to:** I didn't verify that the headless Strategy Tester runs normally under an investor login. Test it once. Real trading still needs the master password, so keep that out of anything Jarvis can reach.
- **Overlap:** Extends your existing toolkit. Nothing new to install.

### 8. Official, read-only data endpoints for PolyEdge (hardening what you already use)
- **Polymarket US:** https://docs.polymarket.us/api-reference/introduction and `/api-reference/rate-limits` (no date shown).
  - The US API is split in two. `https://gateway.polymarket.us` is **public, no API key**: markets, events, order books, sports. `https://api.polymarket.us` is the authenticated one that places orders.
  - The public limit is 20 requests/second per IP.
  - I sent one test GET to `gateway.polymarket.us/v1/markets` and it returned market JSON with no key.
  - **Don't create a Polymarket US API key at all.** PolyEdge doesn't need one.
  - This is different from international Polymarket (docs.polymarket.com): its `py-clob-client` repo is now archived, and `Polymarket/agents` is archived too.
- **The Odds API v4:** https://the-odds-api.com/liveapi/guides/v4/ (no date shown).
  - Every response carries `x-requests-remaining`, `x-requests-used`, and `x-requests-last`. `/sports` and `/events` don't count against quota.
  - Odds calls cost markets × regions, and historical calls cost 10× that.
  - Have PolyEdge log `x-requests-remaining` and warn before the quota runs out, so the app doesn't silently go blank.
- **ESPN:** there's no official public ESPN API. The widely used endpoints are undocumented; the best-known list is https://github.com/pseudo-r/Public-ESPN-API (741★, no license, last push 2026-07-04). They can change without notice, so build a fallback and show a "stale data" flag in the app.
- **What it changes:** PolyEdge code in Base44 only.
- **Risks / reasons not to:** None beyond build time.
- **Overlap:** Same data sources you already use. This is about making them sturdier.

### 9. Alpha Vantage official MCP server (read-only market data)
- **Link / date:** https://github.com/alphavantage/alpha_vantage_mcp (213★, MIT, last push 2026-09-28).
- **Problem it solves:** Gives Jarvis read-only macro and news context for small-account risk management:
  - `FX_INTRADAY/DAILY/WEEKLY/MONTHLY`
  - US economic indicators: `CPI`, `NONFARM_PAYROLL`, `FEDERAL_FUNDS_RATE`, `TREASURY_YIELD`
  - `NEWS_SENTIMENT`
  For example: "is there a CPI release this week, and what did the last one do?" It's a data API with no trading functions.
- **What it changes:** One MCP entry. Either the hosted server `https://mcp.alphavantage.co/mcp` (the README shows an OAuth option) or local `uvx marketdata-mcp-server <key>`. Needs a free Alpha Vantage key.
- **Risks / reasons not to:**
  - The README also shows putting the key in the URL. That key would sit in plain text in `~/.claude.json`, so prefer OAuth or an environment variable.
  - It has about 100 tools, but tool search only loads their names (#13). Scope it to your trading folder or a subagent.
  - I couldn't verify the free-tier limits.
  - The data isn't your broker's feed, so spreads and prices will differ.
- **Overlap:** Its technical indicators duplicate TradingView. Use it for macro, news, and cross-checks.

### 10. eBay's official read-only MCP server
- **Link / date:** https://github.com/eBay/npm-public-api-mcp (21★, Apache-2.0, last push 2026-08-14; npm `@ebay/npm-public-api-mcp` 1.1.0).
- **Problem it solves:** Price comps and item lookups for the eBay store (Browse API), plus read access to your own seller data in "User token" mode. The README says **production is GET-only (read operations only); writes are not available**. It's published under eBay's own GitHub organization.
- **What it changes:** One MCP entry through npx (pin the version). Needs Node 22+ and an eBay developer Client ID and Secret. You'd create those yourself. User-token mode also needs a refresh token.
- **Risks / reasons not to:** It's a young repo with few stars. User-token mode gives Jarvis read access to private order and inventory data. Keep it in a project scope, not user-wide.
- **Overlap:** None. (Zapier may already reach eBay for simple automations.)

### 11. Shopify **Dev MCP** as a standalone server, not the Shopify AI Toolkit plugin
- **Link / date:** https://shopify.dev/docs/apps/build/ai-toolkit (no date shown). Repo: https://github.com/Shopify/Shopify-AI-Toolkit (578★, MIT, last push 2026-09-25). npm `@shopify/dev-mcp` 1.16.0 (published 2026-09-25).
- **Problem it solves:** Current Shopify docs and schemas (Liquid themes, Admin GraphQL, Functions) when Jarvis edits a theme or builds an app for the coffee store. Shopify's docs say the Dev MCP server "runs locally and doesn't require authentication". It can't touch your store.
- **What it changes:** One stdio MCP entry. Shopify's docs give `claude mcp add --transport stdio shopify-dev-mcp -- npx -y @shopify/dev-mcp@latest`; use `@1.16.0` instead of `@latest` to pin it. Turn telemetry off by creating an empty file at `%APPDATA%\shopify-ai-toolkit\opt-out`, or setting `OPT_OUT_INSTRUMENTATION=true`. The README says opting out covers the MCP server too.
- **Why not the plugin:** The README says the plugin registers a `PostToolUse` hook and a `UserPromptSubmit` hook. Telemetry is **on by default**, and on Claude Code it can send **your most recent prompt verbatim** when a Shopify skill activates. That breaks your no-automatic-hooks rule.
- **Risks / reasons not to:** Low value if you never touch theme or app code. npx fetches code when it runs, which is why pinning matters.
- **Overlap:** Your claude.ai **Shopify connector** already covers store data. This is only for building. Anthropic's marketplace also lists Shopify's `liquid-skills` plugin, which is optional and was not reviewed in depth.

### 12. backtesting.py (or vectorbt) for fast pre-screening
- **Links / dates:**
  - https://github.com/kernc/backtesting.py (9,006★, AGPL-3.0, last push 2026-08-05; PyPI `backtesting` 0.6.6, 2026-07-22).
  - Alternative: https://github.com/polakowo/vectorbt (9,210★, Apache-2.0 **with Commons Clause**, last push 2026-09-26; PyPI 1.1.1, Python 3.11–3.14).
- **Problem it solves:** The MT5 Strategy Tester is thorough but slow. Pull history with the `MetaTrader5` package, screen parameter ideas in seconds in Python, then send only the survivors to your headless Strategy Tester.
- **What it changes:** A pinned `pip install` into your toolkit's virtual environment. No services, no network.
- **Risks / reasons not to:** Results won't match MT5 exactly, because fill and spread modelling differ. Treat them as a filter, never as proof. Heavy parameter sweeps invite overfitting. AGPL and Commons Clause are fine for personal use.
- **Overlap:** Complements your custom MT5 toolkit; doesn't replace it.

---

## FASTER / CHEAPER

### 13. Use the built-in context controls, including subagent-only MCP servers
- **Link / date:** https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search , `/docs/en/context-window`, `/docs/en/sub-agents`, `/docs/en/skills`, `/docs/en/commands` (no date shown).
- **Problem it solves:** Wasted context from MCP tool lists, connectors, and skills that load but aren't needed.
  - **Tool search is already on by default.** Only tool names and server instructions load at start. It switches off if `ANTHROPIC_BASE_URL` points at a non-Anthropic host or `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` is set, so check neither is set on either machine or in the Bridge. Use `alwaysLoad` only for a tiny server you need every turn.
  - **Measure:**
    - `/context` shows what's filling the window.
    - `/skill-doctor` (v2.1.252+) shows each skill's context cost and how often it's used.
    - `/doctor` flags unused skills, MCP servers, and plugins against their context cost. It will also *offer* to make auto mode your default. Decline that, because it conflicts with your confirm-first rule.
  - **Connectors:** Claude Code fetches your claude.ai connectors (Gmail, Calendar, Drive, Shopify, Zapier, Base44, Claude Docs) into sessions. Toggle them off *per folder* in `/mcp`, which writes `disabledMcpServers`. For example, no Shopify, Base44, or Gmail in the trading folder.
  - **Subagent-only servers:** The docs say: "To keep an MCP server out of the main conversation entirely… define it inline [in a subagent's `mcpServers`]… The subagent gets the tools; the parent conversation doesn't." Put tradingview-mcp, Playwright, and TikTok inside chart-reader, browser, and TikTok subagents. Screenshots and OHLCV dumps then stay out of Jarvis's main thread.
  - **Skills:** set `disable-model-invocation: true` on rarely used skills (pptx, for example). Their description leaves context, and you can still run them with `/name`.
- **What it changes:** Settings and small agent files in `~/.claude/agents/`. No installs.
- **Risks / reasons not to:** Subagents return summaries, so you lose raw detail in the main thread and add a little latency. Plugin subagents ignore `mcpServers`, so write your own agent files. Project-folder agents only load their inline servers after you trust the folder.
- **Overlap:** All built in.

### 14. Lean headless jobs (`claude -p`) and the right scheduler
- **Link / date:** https://code.claude.com/docs/en/headless , `/cli-reference`, `/scheduled-tasks`, `/desktop-scheduled-tasks`, `/routines` (no date shown).
- **Problem it solves:** Scheduled jobs that start a full Jarvis session load every server and connector. Leaner flags:
  - `--mcp-config job.json --strict-mcp-config` loads only the server that job needs.
  - `--allowedTools` plus `--permission-mode dontAsk` fixes the job's tool list.
  - `--max-turns`, `--fallback-model`, and `--output-format json` for logs.
  - `--bare` is fastest, but it skips CLAUDE.md and "doesn't use your subscription login" (it needs an API key), so it doesn't suit persona jobs.
- **Picking a scheduler:**
  - `/loop` and in-session tasks die with the session, and recurring ones expire after 7 days.
  - **Desktop scheduled tasks** (Windows desktop app) only run while the app is open and the computer is awake.
  - **Cloud Routines** (Pro and up) run on Anthropic's servers and can't see your OneDrive vault. They could clone the vault's GitHub repo, but writes there could collide with OneDrive sync, so keep any routine read-only.
- **What it changes:** Command lines and small per-job JSON files.
- **Risks / reasons not to:** The docs warn that a `-p` session runs a project's `.claude/settings.json` hooks and `.mcp.json` servers **even in a folder you never trusted**. Only run jobs in folders you control.
- **Overlap:** The earlier report's scheduling pick, now tuned for your setup.

### 15. Anthropic's `session-report` skill + ccusage (find where tokens go)
- **session-report:** in https://github.com/anthropics/claude-plugins-official (37,180★, Apache-2.0, last push 2026-09-29), at `plugins/session-report` (last commit 2026-09-28; author Anthropic).
  - **What it does:** runs a bundled Node script over your local `~/.claude/projects` transcripts. It reports tokens by project, subagent, and skill, **cache breaks**, and the most expensive prompts, as an HTML file.
  - **Changes:** installs a single skill, with no hooks. It writes the report into the current folder, so run it from a scratch folder, not the vault root.
- **ccusage:** https://github.com/ccusage/ccusage (18,794★, MIT, last push 2026-09-29; npm 20.0.26).
  - **What it does:** daily, monthly, and per-session totals from local logs. On the VPS that includes the Bridge's SDK sessions, which are also saved to disk.
  - **Changes:** nothing permanent. Run it through npx with a pinned version (`npx ccusage@20.0.26`).
- **Risks / reasons not to:** Both read your full local transcripts, but locally only. ccusage costs are estimates.
- **Overlap:** The built-in `/usage` (aliases `/cost` and `/stats`) already shows session cost and plan limits. These two add history and the "why".

---

## Already covered: overlap, not re-recommended
| Earlier pick | Status for Adam |
|---|---|
| Remote Control / Telegram Channels | You already have Remote Control as backup, and Jarvis24 is the main path. The Telegram plugin would be a third route and needs Bun. Skip. |
| anthropics/skills (docs/pdf/xlsx/pptx) | Already installed. |
| Marketing skills (Jared's pack, coreyhaines31/marketingskills, knowledge-work `marketing`) | You already have a marketing playbook. Adding more duplicates it and bloats context. |
| taylorwilsdon/google_workspace_mcp | You already have the Gmail, Calendar, and Drive connectors. |
| Playwright MCP | Already installed. Anthropic's marketplace also lists an official `playwright` plugin, so you don't need both. Claude in Chrome overlaps too. |
| Scheduling (earlier #2) | Re-framed in #14. |
| ccusage (earlier #6) | Kept in #15 with a pinned version. |
| kepano/obsidian-skills (48,997★, MIT, last push 2026-09-15) | Fits the vault and passes your constraints, but it's optional. Not ranked, because your vault already works. |

## Considered, not ranked
- **PHUICMT/mcp-mt5**: https://github.com/PHUICMT/mcp-mt5 (18★, MIT, last push 2026-09-04; PyPI 0.5.0). A Windows MT5 *build pipeline*: compile, deploy, headless Strategy Tester, and report parsing. The README says "No broker login… no risk of real-money execution." It fits your EA workflow closely, but it's a small single-maintainer project and overlaps your own toolkit. Read its code before trying it, and run it under the investor login (#7).
- **OpenTelemetry export**: https://code.claude.com/docs/en/monitoring-usage. It's built in and prompts are redacted by default, but it needs a collector to send to. That's overkill for one person today; #5 and #15 cover the need.
- **Status line**: https://code.claude.com/docs/en/statusline. A small script you review can show context %. It runs on every refresh, so keep it trivial. sirmalloc/ccstatusline (13,106★, MIT) works but is more code running automatically.
- **Claude Code `/voice` dictation**: https://code.claude.com/docs/en/voice-dictation. Only in the desktop CLI; needs a claude.ai login and a local mic. It won't help Jarvis24 on the phone. No voice pick this round: I found nothing official that clearly beats your current voice line without creating a second voice stack.

---

## Rejected under your constraints
| Item | Link / stars / last push | Why rejected |
|---|---|---|
| claude-mem | https://github.com/thedotmack/claude-mem, 94,887★, Apache-2.0, 2026-09-28 | Second memory system: it auto-captures sessions into its own store. |
| basic-memory | https://github.com/basicmachines-co/basic-memory, 4,062★, AGPL-3.0, 2026-09-29 | A second knowledge store beside the vault. |
| Claude Code auto memory and the subagent `memory:` field (built in) | https://code.claude.com/docs/en/memory | Second memory. Switch it off (#1). |
| Shopify AI Toolkit *plugin* | https://github.com/Shopify/Shopify-AI-Toolkit, 578★, MIT, 2026-09-25 | Auto-runs `PostToolUse` and `UserPromptSubmit` hooks. Telemetry is on by default and can include your prompt word for word. Use the Dev MCP instead (#11). |
| Langfuse / Dash0 observability plugins | https://github.com/langfuse/claude-observability-plugin (24★); https://github.com/dash0hq/dash0-agent-plugin (5★) | Hook-based automatic telemetry sent to third parties. |
| anthropics/knowledge-work-plugins | https://github.com/anthropics/knowledge-work-plugins, 25,819★ | Large skill packs; overlaps your marketing skill. |
| ariadng/metatrader-mcp-server | https://github.com/ariadng/metatrader-mcp-server, 814★, MIT, 2026-03-28 | Built to place trades ("place market order then set SL/TP"). Last push was 6 months ago. |
| Qoyyuum/mcp-metatrader5-server | https://github.com/Qoyyuum/mcp-metatrader5-server, 226★, no license | Exposes `order_send`, and has no license. |
| emerzon/mtdata-mcp | https://github.com/emerzon/mtdata-mcp, 22★, MIT | `trade_*` tools "can place, modify, and close real orders". Small project. |
| claude-tradingview-mcp-trading | https://github.com/jackson-video-resources/claude-tradingview-mcp-trading, 609★, no license | "Execute trades automatically via BitGet". Needs exchange trading keys. |
| Polymarket MCPs (IQAIcom/mcp-polymarket, @carbon-copy/polymarket-mcp, demwick/polymarket-agent-mcp) | e.g. https://github.com/IQAIcom/mcp-polymarket | Trading turns on with a wallet private key. Not official. Polymarket has no official MCP; its `agents` repo is archived. |
| Printful / Printify MCPs | https://github.com/Purple-Horizons/printful-mcp (28★, last push 2026-01-28); hosted Apify/Composio Printify servers | No official server exists. They can create or confirm orders, which charges money. Hosted versions hold your account token. |
| YosefHayim/ebay-mcp | https://github.com/YosefHayim/ebay-mcp, 167★, MIT | Unofficial, with about 298 tools including write access to listings and orders. Use eBay's official read-only server (#10). |
| Postiz | https://github.com/gitroomhq/postiz-app, 36,466★, AGPL-3.0 | Auto-posts to social accounts. |
| Meta Ads MCP | https://github.com/pipeboard-co/meta-ads-mcp, 1,281★ | Can create and spend on ad campaigns. |
| TikTok scrapers | https://github.com/Evil0ctal/Douyin_TikTok_Download_API, 20,392★ | Scraping and downloading: terms-of-service and copyright risk. |
| PM2 as the Windows service manager | https://github.com/Unitech/pm2 (43,301★, AGPL-3.0); https://github.com/jessety/pm2-installer (575★, last push 2024-01-23) | PM2's docs send Windows users to pm2-installer, which has been stale since January 2024. Use WinSW instead. |
| Orchestrators / wrappers (Ruflo, slopus/happy) | https://github.com/ruvnet/ruflo (73,469★); https://github.com/slopus/happy (23,944★) | Extra harness layers and token burn. Happy duplicates Jarvis24 and Remote Control through a relay. |
| `bypassPermissions` / `--dangerously-skip-permissions` in the Bridge | https://code.claude.com/docs/en/permission-modes | Removes the confirm-first safety net. |

**Flag on something you may already run:** if your TikTok MCP is https://github.com/Seym0n/tiktok-mcp (200★, MIT, last push 2026-08-19), be aware it goes through a third-party service (TikNeuron) with its own API key, not TikTok's official API. It's fine for reading subtitles and metadata, but it's a dependency that can break or change terms. I found **no official TikTok, YouTube, or Instagram MCP servers**. The YouTube ones are community-built, for example kimtaeyoon83/mcp-server-youtube-transcript (598★) and ZubeidHendricks/youtube-mcp-server (577★), so none are recommended.

---

## Couldn't verify
- **NSSM** (nssm.cc) timed out twice from my side, so I couldn't confirm its current release status. It's left out in favour of WinSW.
- **Alpha Vantage free-tier limits.** Their pricing page timed out.
- **healthchecks.io Hobbyist limits.** The $0 plan is confirmed, but the page text I got didn't list the check count.
- **Headless Strategy Tester under an investor login.** MT5 help says investors can "work with your own Expert Advisors". Test it once.
- **Your specifics:** which TikTok MCP you use; the exact claude.ai connector tool names (list them with `/mcp` before writing deny rules); whether the claude.ai Shopify connector can write; and whether the Bridge logs in with an API key or your subscription.
- **pineforge-4pass/pineforge-engine** (188★, Apache-2.0, last push 2026-09-29) claims trade-for-trade reproduction of TradingView Pine v6 backtests. Not verified, so not recommended yet.
- **Claude Desktop app scheduled tasks on Windows Server**, and details of Windows Task Scheduler for `claude -p`. Not researched.

## Method and limits
- **Claude Code facts:** read from the current Markdown versions of the docs pages (code.claude.com/docs/llms.txt index). Quotes above are from those pages. Versions are from the npm registry.
- **Repo facts:** from the GitHub search API; releases from the GitHub releases API. READMEs were fetched raw from GitHub. Anthropic's plugin marketplace was cloned to the research box (not Adam's computer) to read plugin contents.
- **Vendor docs:** Polymarket US docs (plus one unauthenticated GET to the public gateway), The Odds API v4 guide, Tailscale KB, healthchecks.io pricing, the MetaTrader 5 help and MQL5 reference, and Shopify's AI Toolkit page.
- **Limits:** I didn't install or run any of these tools. Stars and dates change daily. "Last push" isn't a quality guarantee; small repos were checked for what they can *do* (trade, post, write), not audited line by line.


## Jarvis review (2026-09-29 ~4:30 AM)
Saved as reference; research by Adam's Grok bot from the brief Jarvis wrote. Nothing in it has been executed. Every item is a config change or install that needs Adam's explicit go. See the daily note for the triage.

**Decision (Adam, 2026-09-29 ~4:35 AM):** "No nothing sounds good" — declined #1 (auto memory off) and #2 (version pinning) on the desktop for now. Nothing from this report is applied. Don't re-pitch unprompted.
