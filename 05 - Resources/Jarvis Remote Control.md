---
status: active
project: meta
type: guide
---
# Jarvis Remote Control

How Adam reaches the real, full-tool-access Jarvis (this exact Claude Code session — files, terminal, browser, everything) from his phone. Distinct from [[Jarvis on Claude Mobile App]], which is a separate advice-only Project with no live session and no tools.

## How it works
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
