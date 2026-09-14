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
| ai-memory-vault | `~/ai-memory-vault` | the mind — this Obsidian vault's engine | up to date (`176d800`) |
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

## Update — 2026-08-30

Adam asked to pull "the Jarvis brain file" (`ai-memory-vault`, the mind repo) from GitHub. Was 5 commits behind (`2fc72ae` → `176d800`); pulled clean via `git pull --ff-only`. All five commits were setup-wizard/installer bug fixes (config-registration corruption risk, half-finished-install recovery, memory-redirect folder ambiguity) — none affect an already-running install like this one, with one exception:

**Daily-note foldering convention fixed:** upstream now says month subfolders (`NN - Month YYYY`) start from the very first daily note, never "once the folder fills up" — the old wording let two sessions disagree about where today's note goes. Adopted immediately: moved all 7 existing notes from `01 - Daily Notes/` flat into `01 - Daily Notes/08 - August 2026/`, updated the rule text in [[VAULT-INDEX]]'s Daily Notes section to match. Template stays at the folder root.

Did not check `fullstack-agent`, `backtalk`, `ai-visualizer`, or `barehands` in this pass — scoped to just the brain repo per what was asked.

## Update — 2026-09-14

This session runs on a different machine (`C:\Users\Administrator`) than where the 2026-08-20/08-30 clones lived (`C:\Users\aland`) — none of the 5 repos existed here. Adam asked to check jaredrhod's GitHub for anything new; checked via the GitHub API (no `gh` CLI on this box) since there was nothing local to `git pull`.

**Found:** upstream has been quiet since 2026-08-31 (nothing shipped in 2 weeks), but `fullstack-agent`, `backtalk`, `ai-visualizer`, and `barehands` were still sitting on this vault's records at their 2026-08-20 SHAs — only `ai-memory-vault` had been checked since (2026-08-30 note). Real backlog that had never been pulled anywhere: a same-day (08-30) architecture change across all four — **"Windows update path: ask your agent instead of update.bat"** — plus barehands' `add_card` now taking a position (cards stop stacking), mic-pinning-by-name in backtalk, plan-usage now drawn on every ai-visualizer face, and a real zip-skip bug fix in fullstack-agent's updater.

**Action taken:** cloned all 5 repos fresh to this machine (`~/fullstack-agent`, `~/ai-memory-vault`, `~/backtalk`, `~/ai-visualizer`, `~/barehands`) — clone only, Adam's explicit call, no installer run. All landed at the current tip (`5bb159f` / `659bba9` / `84b3a6c` / `6921e1d` / `eb23bed`, all 2026-08-30). This machine still only runs the brain/vault side — backtalk (voice) and ai-visualizer (face) are cloned but not wired up or running here, same "cloned but dormant" status the 2026-08-20 table recorded on the old machine.

## How to update, now that repos are cloned here

Confirmed via `ai-memory-vault`/`fullstack-agent`'s own READMEs (2026-09-14): on Windows there's no `update.bat` step for the agent to run — the documented flow is Adam just says **"update everything and tell me what changed"** and the agent does real `git -C <repo> pull --ff-only` on each clone and reports the changelog. Now that all 5 are actually cloned on this machine (see the 2026-09-14 update above), that's a straight local `git pull` per repo — no need to fall back on the GitHub API workaround used today (that workaround was only needed because the clones didn't exist here yet).

## Related

[[barehands]], [[voice-line]] — the two pieces from this stack actually in daily use.
