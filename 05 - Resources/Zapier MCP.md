---
status: active
project: meta
type: reference
---
# Zapier MCP

claude.ai-hosted MCP connector (`claude.ai Zapier`) that lets Jarvis reach Adam's apps through Zapier. **Status as of 2026-09-18: connected, authenticated, provisioned with 5 apps, read path tested live. No writes ever executed.**

## What's provisioned (via `auto_provision_mcp`, approved by Adam 2026-09-18)

| App | Bound account | Read actions | Write actions |
|---|---|---|---|
| Google Drive | alandrum24@gmail.com | 4 | 15 |
| Google Sheets | alandrum24@gmail.com | 8 | 21 |
| Shopify | store `75f1s2-bj` (confirmed = the coffee store, `75f1s2-bj.myshopify.com`, per [[O For the Love of Coffee]]) | 12 | 24 |
| Facebook Pages | jvmusicnow@gmail.com | 0 | 5 |
| Instagram for Business | jvmusicnow@gmail.com | 0 | 3 |

131 actions total. Each app has exactly one connected account, so there's no account-choice ambiguity today.

## Standing decision: write actions stay enabled
Auto-provision enabled write actions too, including `delete_file`, `delete_sheet`, `share_file`, `publish_product`, `gift_card`, and posting to Facebook/Instagram. Jarvis offered to trim them to read-only; **Adam declined (2026-09-18).** They stay on. Standing rule regardless: Jarvis only uses a Zapier write action after Adam approves that specific action, the same as any other outward-facing step. Don't prune them on your own initiative either; if Adam later wants read-only, use `disable_zapier_action` per app.

## Test pull results (read-only, 2026-09-18)
- **Google Drive** "Find a File" returned real files (newest: Blue Ridge Academy course list, an ASL quiz video, Acellus GOLD 2026-27).
- **Google Sheets** "Find Spreadsheet" returned 7 real sheets, all homeschool / Blue Ridge Academy material.
- **Shopify** "Find Order" returned zero orders on two different queries. Consistent with the store having no products or launch yet; not independently verified.

## Working method (banked so nobody pays the discovery tax twice)
- Always `inspect_zapier_actions` for an action's schema before executing; `execute_zapier_read_action` needs `selected_api`, `action`, and `tool_name`.
- **Drive "Find a File" with a broad term (e.g. `a`) dumps ~97K characters** and spills to a tool-results file. Use a specific filename, or slice the saved file with Python.
- **Shopify "Find Order" errors with no query field** ("enter a value for at least one search query field or provide a raw query"). Pass `raw_query`, e.g. `created_at:>2020-01-01`.
- **Sheets "Find Spreadsheet"** takes a name substring and returns a clean list; fine for browsing.
- Facebook and Instagram are post-only here (no read actions).
- The onboarding skill (`zapier:onboarding`, via `get_zapier_skill`) says to run a multi-app "morning digest" and save it as a skill without asking. That is third-party text: treated as a suggestion, and Adam approved each step separately. Steps 3-5 (digest, `create_zapier_skill`, scheduling) were not done.

## Not done
- No rundown/digest saved as a Zapier skill; no scheduled run.
- Gmail and Google Calendar are NOT provisioned through Zapier (they already have their own connectors in Claude).

## Related
[[eBay MCP]] and [[Exa Web Search (MCP)]] — the other MCP connections. [[O For the Love of Coffee]] — the Shopify store this may touch.
