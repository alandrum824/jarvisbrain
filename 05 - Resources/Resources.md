---
status: active
project: meta
type: index
---
# Resources

Cross-project reference material, templates, and Jobs that don't belong to a single project.

## Notes in this folder

- [[Jarvis on Claude Mobile App]] — how to set up a claude.ai Project to talk to Jarvis when away from this machine (advice-only, no hands).
- [[barehands]] — hand-tracked webcam gesture UI (jaredrhod/barehands), cloned to `~/barehands`, how to run it and wire it in.
- [[Fullstack Agent Stack]] — the jaredrhod/fullstack-agent installer and its five component repos, version/update tracking, and which pieces are actually active vs. dormant clones.
- [[Public ESPN API]] — ESPN's public API (no key needed) for live sports data. In active use as of 2026-09-05, paired with [[Polymarket (Prediction Markets)]].
- [[Polymarket (Prediction Markets)]] — public prediction-market odds API, used alongside ESPN stats to help Adam think through sports-game decisions. Informational only, no trading.
- [[voice-line]] — local voice interface (whisper + Kokoro TTS + warm Claude session) that barehands relays to for voice; how to start the three-service stack and drive it.
- [[Jarvis Remote Control]] — how Adam reaches the real, full-tool Jarvis session from his phone: the JARVIS Bridge + Tailscale Funnel + Jarvis24 custom app (primary path, live 2026-09-05), plus Claude Code's native Remote Control pairing and the lid-close power fix so it survives closing the laptop.
- [[Exa Web Search (MCP)]] — the exa MCP server's wrong-hostname bug (fixed) and the still-pending real API key Adam needs to generate before it's fully live.
- [[Jarvis Personality]] — current tone/personality spec (lives for real in each machine's `CLAUDE.md`; this note tracks decisions and flags cross-machine drift).
- [[RetroVault (CeeloEdge)]] — Adam's real sports-pick/signal engine (Base44 app). Fixed the actual "not working" root cause (home screen never generated signals itself), added College Football, and wired in real Polymarket market pricing.
- [[eBay MCP]] — third-party MCP server (299 tools, full eBay Sell API) for Adam's own eBay store. Installed and registered; blocked on Adam creating a real eBay Developer account and running the setup wizard.
- [[Firecrawl]] — real web scraping/search CLI, already wired into both this terminal and the JARVIS Bridge via the existing skill config. Fixed a missing global install and a bridge permission gap that made every call hang waiting on a phone confirmation.
- [[Base44 Apps]] — full inventory of Adam's 92 Base44 apps, categorized by theme; only [[Elijah Learning Academy]] and [[Juvenile Virtue]] explored in depth so far.
- [[Marketing]] — Jared Rhodenizer's marketing playbook (principles, funnel strategy, copywriting/email/ads/lead-magnet/content/analytics playbooks); read before any marketing work. Also live as a Claude Code skill at `~/.claude/skills/jaredrhod-marketing/`.
- [[Video Editing (ffmpeg)]] — what Jarvis can/can't do with video (e.g. PS5 gaming clips): no PS5 hardware access, no CapCut GUI automation, but real command-line editing via ffmpeg once files are on a machine that has it — confirmed on this session's machine 2026-08-24, not yet checked elsewhere.
- [[Vault GitHub Sync]] — this vault's own git remote (`alandrum824/jarvisbrain`), the end-of-day commit/push habit, and how to resolve multi-session merge conflicts.
