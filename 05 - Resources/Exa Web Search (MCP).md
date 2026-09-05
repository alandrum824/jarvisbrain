---
status: active
project: meta
type: reference
---
# Exa Web Search (MCP)

An MCP server (`exa`, configured user-wide in `~/.claude.json` under `mcpServers`) meant to give Jarvis a dedicated web-search tool — relevant for live lookups like weather, sports scores, and news that a static model can't answer from memory.

## Bug found and fixed 2026-09-05
Config pointed at the wrong host: `https://exa.ai/mcp` (405 error, server never connected). The correct hosted endpoint is `https://mcp.exa.ai/mcp` (confirmed via Exa's own docs and the official repo, [exa-labs/exa-mcp-server](https://github.com/exa-labs/exa-mcp-server)). Fixed the host in `~/.claude.json`.

## Still open: needs a real API key
The corrected URL still needs `?exaApiKey=<key>` appended — currently set to a placeholder (`REPLACE_WITH_YOUR_EXA_API_KEY`). Adam needs to generate a free key himself at **dashboard.exa.ai/api-keys** (account signup required, not something Jarvis can do on his behalf) and hand it over so it can be dropped into the config and the MCP connection restarted/verified.

## In the meantime
Jarvis already has general-purpose web search/fetch tools (not exa-dependent) and can answer weather/sports/news questions right now without waiting on this fix — exa would just be a dedicated, higher-quality search backend once wired up.

## Related
[[Public ESPN API]] — a saved reference for pulling real sports data directly, independent of exa.
