---
status: active
project: meta
type: reference
---
# Playwright MCP

Microsoft's official browser-automation MCP server. It gives Jarvis a headless browser of its own, separate from Adam's logged-in Chrome and from [[barehands]]. Added 2026-09-29 ~3:20 AM PT with Adam's OK ("Yes"), after it showed up in a Claude Code tools video he sent.

**Why:** the Claude in Chrome extension was disconnected that night, so testing [[PolyEdge]] at iPhone size and reading a JS-only Grok page needed a hand-built CDP harness (`~/pe_cdp/drive.mjs`, `read.mjs`). Playwright does the same job properly.

**Install (verified):**
- Pinned install, no npx auto-update: `C:\Users\aland\playwright-mcp` (`npm install @playwright/mcp`, v0.0.83).
- Registered in `C:\Users\aland\.mcp.json` as `playwright`, with the same portable node.exe as `tradingview`/`tiktok-mcp`, and args `cli.js --headless --isolated`. `--isolated` means a fresh browser profile every session, so no cookies or logins are kept. Backup of the previous file: `.mcp.json.bak-2026-09-29`.
- It uses the installed Google Chrome. Smoke test: it starts and exits cleanly.
- **Status:** configured, loads on the next Claude Code restart (a session started from `C:\Users\aland`); not yet exercised through the MCP tools.

**Use it for:** testing Adam's own apps (PolyEdge at 390px, Base44 previews) and reading JS-rendered pages. Not for logged-in sites or anything outward-facing without Adam's go.

## Considered the same night, NOT installed
- **ECC (affaan-m/ECC, ~260k stars):** 292 skills, 68 subagents, 94 commands, always-loaded rules, and session-start hooks that inject "learned patterns" and keep their own memory on disk. Rejected: it competes with the vault as the only memory and loads thousands of lines of foreign rules into every session.
- **jaredrhod/ai-marketing-skills:** already installed as the `jaredrhod-marketing` skill; all 12 files are byte-identical to the repo (checked by git blob hash). Nothing to add.
- **Brahma Echo (titechprabhasolutions/Brahma-Echo, checked 2026-09-29 ~4 AM):** a separate Windows voice assistant built on Gemini/OpenRouter (111 stars, "custom source-available" license). Rejected: it stores API keys *and account passwords* (e.g. Instagram) in plain `config/api_keys.json`; its "auto-heal" engine rewrites its own Python code on disk without approval; it has broad system control (kill processes, shutdown, webcam) plus optional Discord remote control. It duplicates Jarvis24/voice-line/barehands on a weaker, less safe base.
