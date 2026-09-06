---
status: active
project: personal
type: reference
---
# eBay MCP

Third-party MCP server (`github.com/YosefHayim/ebay-mcp`), cloned 2026-09-06 to `C:\Users\Administrator\ebay-mcp`. Exposes 299 tools covering essentially all of eBay's Sell API — inventory, listings, orders, fulfillment, shipping, refunds, promoted listings, messaging, analytics — controllable through plain conversation with Jarvis. For **Adam's own eBay store**, not [[Mom's eBay Store (EMarketingTX)]].

## Not from Anthropic or eBay — a third-party, unverified repo
Same caveat as [[MBT (MT5 Backtest Toolkit)]] and [[Polymarket Pipeline]]. Runs entirely locally over stdio; credentials never leave this machine (per the project's own README).

## Setup status (2026-09-06)
- Cloned, `npm install` + build completed clean (394 packages, 0 vulnerabilities, all 4 UI view templates built).
- Registered as an MCP server in `~/.claude.json` (`ebay`, stdio, `node build/index.js`).
- `.env` created from template — all credential fields still empty placeholders.
- Verified the built server actually starts clean, registers all 299 tools, and correctly reports "auth failed" (expected — no real credentials yet) without crashing.
- The server loads its own `.env` from its package root regardless of caller's working directory (verified in `src/config/environment.ts`) — no need to duplicate credentials into `.claude.json` itself.

## Status update (2026-09-06)
Adam signed up for an eBay Developer account. eBay's key approval is taking ~24 hours (their timeline, not something either of us controls) — waiting on the App ID / Cert ID before the next step.

## What Adam still needs to do (real account/credential steps, not something Jarvis can do)
1. Create a free eBay Developer account at developer.ebay.com if he doesn't have one. **Done 2026-09-06** — keys pending eBay's ~24hr approval.
2. Generate application keys (Client ID / App ID, Client Secret / Cert ID) in the Developer Portal.
3. Decide sandbox vs. production in `EBAY_ENVIRONMENT`.
4. Run `npm run setup` from `C:\Users\Administrator\ebay-mcp` — the project's own interactive wizard: writes credentials into `.env`, and can walk through the OAuth flow to get a real `EBAY_USER_REFRESH_TOKEN` (needed for anything beyond read-only catalog lookups). The wizard's auto-capture OAuth flow needs an HTTPS callback URL (eBay rejects plain http/localhost) — the README suggests fronting the local callback port with an ngrok-style tunnel; **the JARVIS Bridge's existing Tailscale Funnel** (see [[Jarvis Remote Control]]) could plausibly serve this same role if Adam wants to reuse it instead of installing ngrok, worth considering when he gets to this step.
5. Restart Claude Code (or just start a fresh session) so the `ebay` MCP server picks up the new `.env`.

## Related
[[Automated POD Stores (Adam and Mom)]] — the still-undecided print-on-demand store idea; unclear yet whether this is the same store or a separate one. Not resolved tonight.
