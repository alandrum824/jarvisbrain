---
status: active
project: meta
type: reference
---
# voice-line

Local voice interface for talking to Jarvis: hold-to-talk (or always-on VAD) speech in, transcribed locally, answered by a warm Claude session, spoken back out via local TTS. Lives at `~/voice-line`. Also the backend [[barehands]]'s `stage.html` posts typed/voice turns to — barehands has no voice of its own, it just relays to voice-line's endpoint.

## Identity and vault access
voice-line's Jarvis runs with `cwd=C:\Users\aland\HQ`, which has **its own separate copy of `CLAUDE.md`** — not the real one at `C:\Users\aland\CLAUDE.md`. These two files do NOT auto-sync; editing the real one (as terminal-session Jarvis routinely does) leaves voice-line's copy stale until someone copies it over by hand. **Whenever `CLAUDE.md` gets a new section, copy it into `HQ\CLAUDE.md` too, in the same checkpoint** — otherwise voice-line's Jarvis silently runs on out-of-date rules.

As of 2026-08-17, `brain.py`/`main.py` were also patched to pass `add_dirs=[VAULT_DIR]` (`C:\Users\aland\OneDrive\Desktop\jarvis\Adam`) into `ClaudeAgentOptions`, so voice-line's Jarvis can actually read vault notes now — previously it had zero path to the vault and would ask for links to things (like KTFAlways.com) that were already documented. Mirrors the pattern `backtalk` ships with natively (`extra_dirs` in `backtalk.json`).

## The stack (three services, none auto-start)
- `whisper-server.exe` — port 2022, local transcription (CPU, base.en model — swapped from small.en on 2026-08-17 for faster transcription; small.en's `.bin` is still on disk in `tools/whisper/models/` to revert if base.en's accuracy is an issue)
- Kokoro — port 8880, local TTS (CPU, `bm_lewis` voice)
- voice-line (`main.py`) — port 8779, the typed/voice turn queue + one warm Claude session (`claude-sonnet-5`, fast tier, rooted at `C:\Users\aland\HQ` — same Jarvis identity as terminal sessions)

None of these survive a reboot on their own (an NSSM Windows-service upgrade would fix that — not set up, not yet asked for).

## Starting it (in order)
```
start-whisper-server.bat     # opens its own detached window, ~instant
start-kokoro-server.bat      # opens its own detached window, ~1-2 min CPU model load
run-voice-line.bat           # kills any old copy of itself first, safe to re-run
```
All three `.bat` files live at `~/voice-line` root. Each `start-*` one launches its server detached (`start "name" ...`), so the window can be closed after — the server keeps running. `run-voice-line.bat` itself needs to stay running (it's the live session), so leave that window open or launch it detached too.

Confirm each is up by checking its port is LISTENING (2022, 8880, then 8779 last — 8779 only comes up once the Claude session finishes warming).

## Flags
`run-voice-line.bat [flags]`:
- `--open-mic` — legacy always-on mic with VAD endpointing instead of hold-to-talk
- `--deep` — deep-thinking model for the session instead of fast tier
- `--key <name>` — hold-to-talk key (`right_ctrl` default, or `left_ctrl`, `caps_lock`, `right_alt`, `right_shift`, `f13`)
- `--voice {kokoro,elevenlabs}` — TTS engine (kokoro default)
- `--elevenlabs-voice-id <id>` — required with `--voice elevenlabs`, plus an `ELEVENLABS_API_KEY` env var

## Controls
- Hold Right Ctrl anywhere in Windows to talk; release to send. Sub-250ms taps are ignored.
- Press the key again mid-playback to interrupt instantly (speaker-safe, no headphones needed).
- Type in the voice-line console window any time — Enter sends, same handler as speech, typing while it's talking interrupts it.
- Or type in `voice-visualizer`'s chat box (bottom-left) — POSTs to `127.0.0.1:8779`, same queue. This is also what barehands' `stage.html` hits.
- Say "goodbye" / "end voice mode" / "hang up", or Ctrl-C, to end the session.

## Hardware note
No NVIDIA GPU on this machine (Intel integrated only) — both whisper and Kokoro run CPU-only. Kokoro synthesizes at roughly real time (~1s synthesis per 1s of speech), so first audio on a longer reply can take a few seconds rather than 1-2s.

## Troubleshooting
`logs/<today's date>.log` in `~/voice-line` records every turn, interrupt, and TTS fallback in plain text.

**Restarting from Claude Code's own Bash/PowerShell tool — must disable the sandbox, or the restart silently fails.** Confirmed 2026-08-18: running the three `start-*.bat`/`run-voice-line.bat` launchers through the normal sandboxed tool call spawns the detached windows successfully, but they get torn down the instant that tool call returns — `Get-Process` immediately after shows nothing running, no error surfaced. Re-running the exact same launches with `dangerouslyDisableSandbox: true` fixed it immediately (whisper came up instantly, Kokoro/voice-line ~60-90s later). **Always pass `dangerouslyDisableSandbox: true` when starting/restarting this stack from a terminal-session Jarvis** — it's a legitimate persistent local server, not a risky command.

**"Stuck thinking" that doesn't clear:** check if the process is actually still alive — `Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -like '*main.py*' }`. Seen on 2026-08-17 (twice, different causes): once a stale HTTP client after a whisper-server restart (self-cleared, see below); once the process had silently died entirely (port 8779 not listening, no python.exe process found, no traceback in `logs/`). Either way, the fix is the same: restart via `run-voice-line.bat`. No confirmed root cause yet for the silent-death case — **recurred again 2026-08-18** (all three services down, barehands up), still no root cause found in logs. Worth setting up as an NSSM Windows service (auto-restart on crash) if this keeps happening.

**"Jarvis not talking" but text turns work fine:** check the log for `ERROR: kokoro synth failed:` after each `ASSISTANT:` line. Seen on 2026-08-17 — text replies generated normally but every synth call failed with an empty error. Hitting Kokoro's `/v1/audio/speech` directly with curl (both plain and with `response_format":"pcm"`, the exact call `mouth.py` makes) worked fine both times, so Kokoro itself wasn't the problem — looked like a stale connection in voice-line's long-lived `httpx.AsyncClient` (20s timeout, one client held for the whole session in `mouth.py`). Cleared on its own; if it recurs and doesn't self-clear, restart `run-voice-line.bat` (it kills its own old process first, safe to re-run) to force a fresh HTTP client.

## Desktop shortcuts (added 2026-08-18)
Two Desktop `.bat` launchers, the ones owed since the fullstack-agent install on 2026-08-17:
- **`Talk with Jarvis.bat`** — starts all three voice-line services (no browser needed; hold Right Ctrl anywhere once it's ready).
- **`Chat with Jarvis.bat`** — opens a typed terminal Claude Code session in `~` (not voice-line specific, but the third leg of the same three-shortcut set).
- (Barehands' own combined voice+camera shortcut, `Jarvis's Hands.bat`, is documented in [[barehands]].)
Written and component-verified (whisper/Kokoro/voice-line were all independently confirmed live the same session these were written), but not yet double-clicked and confirmed by Adam himself.

## Related
Full detail: `~/voice-line/CHEATSHEET.md`. Consumer/relay side: [[barehands]].
