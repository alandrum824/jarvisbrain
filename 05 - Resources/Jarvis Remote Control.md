---
status: active
project: meta
type: guide
---
# Jarvis Remote Control

How Adam reaches the real, full-tool-access Jarvis from his phone. Two independent paths exist — pick based on what's needed. Distinct from [[Jarvis on Claude Mobile App]], which is a separate advice-only Project with no live session and no tools.

## Path 1: JARVIS Bridge + Tailscale Funnel + Jarvis24 (custom app, primary path)

Built 2026-09-04/05. A real custom voice/chat frontend (`https://jarvis24.grok.me`, built via Grok's "Remix" app builder on Grok's own hosting — not a personal Vercel project Adam has console access to) talks server-to-server to a local bridge on this PC, which runs the real Claude Agent SDK against this exact workspace and vault.

**Architecture:**
```
https://jarvis24.grok.me (Grok-hosted frontend, server-side env vars)
  → JARVIS_BRIDGE_URL (Tailscale Funnel HTTPS origin)
  → https://vps-cogk.tailbf00d6.ts.net  (Funnel, proxies to 127.0.0.1:3741)
  → JARVIS Bridge (C:\Users\Administrator\jarvis-bridge, Express + Claude Agent SDK)
  → Claude (cwd = C:\Users\Administrator, full CLAUDE.md/vault/MCP access)
```

**Local bridge project:** `C:\Users\Administrator\jarvis-bridge`. Binds loopback-only (`127.0.0.1:3741`) — never bound publicly. `.env` holds `JARVIS_BRIDGE_TOKEN` (bearer auth on every route), workspace path, and the vault path (used only for a health-check existence test; the bridge never reads vault contents itself — Claude's own tools do that). Routes: `/health`, `/session/new`, `/session/:id`, `/confirm`, `/chat` (SSE streaming).

**Exposure:** Tailscale Funnel (`tailscale funnel --bg 3741`), not Cloudflare — Adam doesn't control the `grok.me` DNS zone, so Cloudflare Tunnel was a dead end. Funnel needed one-time tailnet admin approval (`tailscale funnel status` / `tailscale funnel --help` for current syntax if it ever changes). Public origin is `https://vps-cogk.tailbf00d6.ts.net` — treat this as the real bridge URL; `jarvis24.grok.me` is the app, never the bridge.

**Token rotation:** `npm run token` generates a new one; update `.env`, restart the bridge (kill + `npm start`), verify old token 401s and new one 200s before handing it to Vercel/Grok's env vars. Never commit `.env`, never paste the token anywhere but the Jarvis24 hosting env.

**Autostart:** `scripts/install-autostart.ps1` registers a non-elevated Scheduled Task ("JARVIS Bridge") that starts `node src/index.js` **at logon**, not at raw boot. Deliberately NOT run as SYSTEM and NOT paired with Windows auto-logon:
- SYSTEM has no access to this Administrator profile's Claude OAuth session (`~/.claude`), so a SYSTEM-level task would start a bridge that can never reach Claude.
- Auto-logon stores the Windows password in the registry — a real security downgrade the boot rules forbid trading away for convenience.
- In practice this covers most real cases: this machine runs Windows Server (confirmed OS), which doesn't log off the session when an RDP client disconnects — the session (and the AtLogOn-triggered bridge) stays live in the background across a disconnect. The only real gap is a full reboot (or, per [[#Keeping it reachable: the lid|the lid]] below, the laptop actually sleeping) with nobody logging back in; if that ever needs closing, the correct fix is Adam supplying his account password to Task Scheduler for a "run whether logged on or not" trigger — not something to grab without him handing it over directly.
Tailscale's own Windows service is `Automatic`/`Running` — survives reboot on its own regardless of logon.

**Known bug, fixed 2026-09-05:** `/health` spawns a real Claude subprocess on every 30-second cache miss with no concurrency guard. A burst of simultaneous health polls (e.g. from Jarvis24 retrying after a slow response) could all race to spawn their own probe at once, starve each other, and abort — which surfaced client-side on Jarvis24 as `TypeError: fetch failed` / "HOME CORE OFFLINE" even though the bridge, Funnel, and Tailscale were all actually fine. Fixed in `src/health.js` by coalescing concurrent callers onto one in-flight probe promise instead of spawning one each. Verified with 10 concurrent forced (cache-bypassing) health requests: all returned clean before the fix would have produced abort bursts.

**Status as of 2026-09-05:** bridge online, Funnel live, full round trip (`/health`, `/chat` SSE with tool use, `/session/new`, `/session/:id`, `/confirm`) verified working end-to-end through the public URL multiple times. `jarvis24.grok.me`'s own env vars (`JARVIS_BRIDGE_URL`, `JARVIS_BRIDGE_TOKEN`) are set and confirmed reaching the real bridge.

## Path 2: Claude Code native Remote Control (pairs to the Claude mobile app)

Claude Code ships a native **Remote Control** feature that pairs a live local session to the Claude mobile app.

- From inside a running Claude Code terminal session: type `/remote-control` (or the short form `/rc`).
- Or launch a session already in remote-control mode: `claude --remote-control`.
- Confirmed present in this install via `claude --help` (2026-08-18) before using it — the flag and the slash command are real, not a guess from a blog post.

Once paired, the phone's Claude app connects to *that exact session* — same context, same files, same everything, because it's literally the same running process, not a copy.

## Keeping it reachable: the lid
This machine is a laptop. Closing the lid sleeps it by default, which kills the session (and voice-line, and barehands) until it's reopened. Fixed on 2026-08-18:
- `powercfg` lid-close action was hidden by default — unhid it: `powercfg -attributes SUB_BUTTONS LIDACTION -ATTRIB_HIDE`.
- Set to **"Do nothing" on AC power** (stays fully awake, closed, while plugged in) and **left as "Sleep" on battery** (so it doesn't overheat closed in a bag when unplugged).

So: for phone access to actually work with the lid closed, the laptop needs to be on AC power.

## The abandoned path: SSH + Tailscale
First approach tried was enabling OpenSSH Server + Tailscale for true remote terminal access. Ran into a real wall: Claude Code's auto-mode classifier blocks self-triggered UAC elevation (can't launch an elevated process to install OpenSSH Server), by design — a safety rail, not a bug to route around. The full setup script still exists at `C:\Users\aland\AppData\Local\Temp\claude\setup\setup-ssh.ps1` if ever needed for something Remote Control can't do (e.g. reaching this machine when Claude Code itself isn't already running) — would need Adam to run it himself from an elevated PowerShell.

## Related
[[Jarvis on Claude Mobile App]] — the separate, advice-only path for when this session isn't running or paired.
