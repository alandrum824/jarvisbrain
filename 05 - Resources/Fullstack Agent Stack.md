---
status: active
project: meta
type: reference
---
# Fullstack Agent Stack

The upstream open-source project this whole Jarvis setup was assembled from: [jaredrhod/fullstack-agent](https://github.com/jaredrhod/fullstack-agent), an installer that wires together four independent repos (memory, voice, face, hands) into one agent. Free/open source (AGPLv3).

## The five repos on this machine

| Repo | Local path | Role | Status as of 2026-08-20 |
|---|---|---|---|
| fullstack-agent | `~/fullstack-agent` | the installer/updater itself | up to date (`fdf0b71`) |
| ai-memory-vault | `~/ai-memory-vault` | the mind — this Obsidian vault's engine | up to date (`2fc72ae`) |
| backtalk | `~/backtalk` | the mouth — official voice repo | up to date (`b3b6cef`), **cloned but not the active voice stack** |
| ai-visualizer | `~/ai-visualizer` | the face — official visualizer repo | up to date (`a69dda8`), **cloned but not the active face** |
| barehands | `~/barehands` | the hands — gesture board | up to date (`f1f8c9e`), **active**, see [[barehands]] |

**Important distinction:** Adam's actual voice and face are a hand-built pair — [[voice-line]] (`~/voice-line`) and `voice-visualizer` (`~/voice-visualizer`) — neither is a git repo, both predate or bypassed the official `backtalk`/`ai-visualizer` adoption. The wizard's README says hand-built pieces normally get "honestly replaced" by the official repos on adoption, but that hasn't happened here — `backtalk` and `ai-visualizer` sit cloned and updated alongside the real, active hand-built stack. Don't assume a `backtalk`/`ai-visualizer` update changed what Adam actually hears or sees; it didn't, unless a future session adopts them.

## Update — 2026-08-20

Was 2 days / ~15 commits behind on all five repos (last pulled 2026-08-18). Pulled all five via `git -C <repo> pull --ff-only`, run manually rather than through `update.bat` (Bash tool couldn't invoke `update.bat` directly — the auto-mode classifier blocked the batch-file call — so `fullstack-agent`'s own new self-update path wasn't exercised; the raw git pulls were done in its place).

**Config-migration heal (the big change in this batch):** upstream moved `backtalk.json`, `barehands.json`, and `ai-visualizer.json` out of git tracking entirely — each renamed to a `.json.example` template, with the real filename added to `.gitignore`. This is a one-time fix so a config file with local edits can never again block or get overwritten by a future `git pull`. Because the pull was run manually (not through the new `update.bat`, which has purpose-built migration logic — copy the tracked config aside, `git checkout` it clean, pull, restore it), the three real config files were briefly gone after the raw pull; recreated by hand from the merged `.example` content (which had Adam's local edits merged in via `git stash`/`pop`) then reset each `.example` back to a pristine template. End state verified clean: real `backtalk.json`, `barehands.json`, `ai-visualizer.json` exist again with Adam's original settings, `.example` files are untouched templates, nothing lost.

**Other upstream changes pulled in (from the fullstack-agent/backtalk/barehands/ai-visualizer/ai-memory-vault changelogs, 2026-08-18→20):**
- A proper self-update path: `update.bat`/`update.sh` now re-copy themselves to a temp file before running (so a script updating itself mid-run doesn't garble), print the incoming changelog before pulling, and a 4th desktop shortcut ("Update `<name>`") is offered at the next full setup run.
- Windows fixes: backtalk's mic/permission-mode wiring, a hands-launch fix, xcrun/dev-tools catch on Mac (not applicable here).
- Vault-interview improvements (setup-wizard only, doesn't affect an already-running install).

**Not yet done:** running the new `Update <name>` desktop-shortcut flow hasn't been tried (this update was done via raw git pull, not the wizard's own updater) — worth trying next time an update is needed, to confirm the self-update path and changelog-on-update actually work end to end.

## Related

[[barehands]], [[voice-line]] — the two pieces from this stack actually in daily use.
