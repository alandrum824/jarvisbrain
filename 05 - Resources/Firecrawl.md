---
status: active
project: meta
type: reference
---
# Firecrawl

Real web scraping/search CLI, already available as a Claude Code skill set (`firecrawl`, `firecrawl-scrape`, `firecrawl-search`, `firecrawl-map`, `firecrawl-crawl`, `firecrawl-monitor`, `firecrawl-interact`, `firecrawl-download`, `firecrawl-parse`, `firecrawl-agent`, `firecrawl-developer-index`, `firecrawl-research-index`) — no separate MCP server needed, and no separate hookup needed for the JARVIS Bridge either: Agent SDK sessions load the same skill config as this terminal (`settingSources: user/project/local`), confirmed live 2026-09-05.

## Real bugs found and fixed 2026-09-05

1. **Bare `firecrawl` command wasn't on PATH.** The plugin's PATH entry pointed at a version folder with no `bin/` in it — the CLI was never actually npm-installed globally, only cached as a plugin definition. `npx firecrawl-cli@latest` worked (confirms it functions keyless, no login needed for scrape/search), but the skill's own instructions call the bare `firecrawl` command. **Fix:** `npm install -g firecrawl-cli@latest`. Verified: `firecrawl scrape <url>` now works directly.
2. **The JARVIS Bridge's permission policy didn't know the `Skill` tool existed** — it fell through to "unrecognised tool" and escalated to a phone confirmation for *every* firecrawl call, which then expired unanswered (looked like a hang, wasn't one). Fixed in `jarvis-bridge/src/permissions.js`: `Skill` now auto-allows only a narrow read-only set (`firecrawl-scrape`, `firecrawl-search`, `firecrawl-map`, `firecrawl-developer-index`, `firecrawl-research-index`, `firecrawl-parse`) — the bare `firecrawl` router and anything that can write files, submit forms, or set up a recurring job (`firecrawl-crawl`, `firecrawl-interact`, `firecrawl-download`, `firecrawl-monitor`, `skill-gen`) still escalates. Same idea applied one level deeper for the actual `Bash: firecrawl <subcommand>` call the skill issues (git-style subcommand allowlist — scrape/search/map/parse/developer/research/status are free, everything else still confirms).

## Verified live end-to-end (2026-09-05)
Through the actual bridge, zero phone confirmation needed: `Skill(firecrawl-scrape)` → `Bash(firecrawl scrape ...)` → `Grep`/`Read` the output → real answer, correctly pulled the Brewers' real record (88-54) off a live ESPN page.

## Related
[[Exa Web Search (MCP)]] — the other web-search path (still needs a real API key); firecrawl works right now with zero setup and no key.
[[Public ESPN API]], [[Polymarket (Prediction Markets)]] — the other two info sources this pairs with for sports lookups.
