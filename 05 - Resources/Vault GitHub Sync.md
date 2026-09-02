---
status: active
project: meta
type: guide
---
# Vault GitHub Sync

This vault (`C:\Users\aland\OneDrive\Desktop\jarvis\Adam`) is a git repo with remote `origin` at [alandrum824/jarvisbrain](https://github.com/alandrum824/jarvisbrain) — separate from the [[Fullstack Agent Stack]] engine repos (`ai-memory-vault` etc.), which are the *tooling* this vault runs on, not the vault's own content.

Adam runs Jarvis in multiple sessions across multiple machines (this desktop, plus a Remote Desktop session on another machine — see [[TWI Scalp Pro]]'s Access section) and expects them to reconcile through this remote, not OneDrive.

## End-of-day habit (standing instruction, 2026-08-31)
At the end of each day's work, commit and push all vault changes to `origin/main`. Do this proactively as part of the normal wrap-up (alongside the daily-note log) — don't wait to be asked each time.

1. `git status` / `git diff` first — review what's actually changing before staging. Add the real files by name; avoid blind `git add -A` picking up stray artifacts.
2. Commit with a message summarizing the day's changes (session-summary style, not a full diff dump).
3. `git push origin main`.
4. If the push is rejected (remote has commits this session doesn't have — normal when another session pushed first, and can happen more than once in a row if both sessions are pushing near-simultaneously): `git fetch origin`, review `git log HEAD..origin/main --oneline` to see what's incoming (it's expected multi-session work, not a red flag), then `git pull origin main --no-rebase` to merge. Repeat fetch→merge→push if it's rejected again.

## Resolving merge conflicts
Conflicts happen most often in shared list-style notes both sessions touch the same day — chiefly **Active Priorities.md**. Resolve by keeping both sessions' unique items; only drop a line if it's a true duplicate of the same task, and in that case keep whichever version is more current/detailed (the other session's line usually carries the newer status). Never resolve a conflict by discarding a side wholesale — read both before deciding. After resolving, confirm no `<<<<<<<`/`=======`/`>>>>>>>` markers remain anywhere before committing the merge.

## Related
[[Fullstack Agent Stack]], [[TWI Scalp Pro]]
