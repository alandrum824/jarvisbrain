---
status: active
project: barehands
type: guide
---
# barehands

Hand-tracked webcam interface (jaredrhod/barehands): turns a webcam into a gesture-controlled board — notes, images, and 3D models float over the camera feed as glass cards, moved by pinch/drag/throw/clap gestures. No headset, stdlib Python server, MediaPipe + three.js loaded from CDN. Open-source (AGPLv3), free to use/build on commercially.

## Where it lives

- Repo: `~/barehands` (cloned from `https://github.com/jaredrhod/barehands`)
- Deployed: 2026-08-17, running locally. **Confirmed end-to-end 2026-08-18**: opened `stage.html` directly via the Chrome tool, camera/hand-tracker loaded clean (zero console errors), typed a message into the chat box, and watched the ring go THINKING → ACTIVE — full round trip through voice-line confirmed live.
- `stage.html` has local uncommitted edits (a "talk to Jarvis" chat box wired to voice-line's `127.0.0.1:8779` endpoint) and `barehands.json` has local config edits (name, Notes orb path) — not yet committed/pushed
- Pulled up to date with `origin/main` twice: 2026-08-17 (9 commits behind) and again 2026-08-18 (3 more commits) — both merged clean against the local edits above, verified no conflict markers. 2026-08-18's pull added real HTML-escaping on card titles/bodies (`escT()`), closing a script-injection hole.
- **Two Desktop shortcuts, `Jarvis's Hands.bat` and `barehands.bat`** — identical content, kept as two names since Adam refers to both. Each starts the full voice-line stack (so listening/talking works every time, not just when voice happens to already be running), starts this server, then opens `stage.html` **explicitly in Chrome** (`start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "..."`, not a bare `start ""` — that would launch whatever the OS default browser is, which may not be Chrome or may not have the hand-tracking/extension setup proven out). Revised 2026-08-18 after Adam asked specifically for both guarantees. Component-verified but not yet double-clicked and confirmed by Adam himself.

## Run it

```
cd ~/barehands
python3 server.py    # `python server.py` on Windows
```

Opens on `http://127.0.0.1:8794/stage.html` — open in Chrome, allow camera. Same URL + `?role=render` for the render/overlay role vs. the tracker/camera role.

## Config

`barehands.json` at repo root defines "orbs" — folders that appear on the board:

```json
{ "title": "Notes", "path": "~/Documents/MyVault", "kind": "notes" },
{ "title": "Props", "path": "media", "kind": "media" }
```

An Obsidian vault works as-is as a notes orb. Only files under `media/` can ever render on the board (the "media jail" — a deliberate safety boundary, not a bug).

## Wiring in an AI

Two protocols, both documented in `barehands.md` inside the repo:
- **Ring = face.** Write `thinking`/`idle`/`listening`/`speaking` to `state/state` in the repo.
- **Board = stage.** `bin/board.sh '{"a":"add_card","title":"HELLO"}'` to push cards; server enforces an action allowlist. `bin/board-state.sh` reads back what's on the board.

Not yet wired into this Jarvis instance — no hooks in `settings.json`, no state-file writes configured. If that's wanted, the repo's own `barehands.md` has the setup wizard prompt.

## Props and models

`media/` is the airlock — only files placed there can ever stage on the board. Four render laws by folder: `misc/` (images, framed cards), `fx/` (transparent PNGs/alpha WebM, renders naked), `models/` (`.glb`/`.gltf`, full texture/lighting), `holo/` (same model file types, but renders as a translucent blue-glass wireframe hologram instead). Same file, different folder, different reality.

As of 2026-08-17: `media/holo/Duck.glb` — the classic Khronos glTF sample duck, dropped in as the first holo demo. `media/models/` is still empty (bring your own `.glb`/`.gltf` — Sketchfab, Poly Haven, or AI-generated).

**Added 2026-08-19: void-throw spoken one-liners.** When a thrown item flies off-screen and vanishes (the existing `foley.void_()` sound event), it now also speaks a random line from a fixed 10-line set (`VOID_LINES` in `stage.html`, e.g. "Thanks for the payday, sir.") — hits Kokoro's TTS endpoint (`127.0.0.1:8880/v1/audio/speech`, `bm_lewis` voice, mp3) directly, not voice-line's own turn queue, so it's instant and doesn't need that session free. Tested the Kokoro call directly (real 21KB mp3 back) and confirmed the page loads with zero console errors after the edit.

**Note from the same session: throwing holo objects off-screen wasn't actually broken** — the fling-and-vanish physics already existed in the code for any item type. Live-diagnosed via the D debug overlay: the real blocker was the browser tab running at ~2 fps (background-tab throttling or CPU contention from everything else running), which starves the velocity-sampling the fling gate needs. Not a code bug — needs the tab focused/foregrounded and less CPU contention, not a threshold change.

**Added 2026-08-18: `Coin.glb` and `IronMan.glb`** (Adam wanted these to match what Jared shows on his own livestream). Real pipeline, not a direct download — Sketchfab and Meshy both gate downloads behind a required account (won't create accounts or log in on Adam's behalf, so those were dead ends). Found `free3d.com` allows anonymous downloads under a "Personal Use License" with no login wall. Both came packaged as `.rar` with `.obj` geometry — installed 7-Zip (direct from 7-zip.org, silent `/S` install) to extract, then `pip install trimesh pygltflib Pillow` to convert OBJ → GLB in Python. Iron Man is a copyrighted Marvel character — fine for personal home display under the source's Personal Use License, not for anything redistributed/commercial. Scratch download/extract folders cleaned up after; only the final `.glb` files were kept.

**Fixed 2026-08-19: IronMan.glb was absurdly oversized.** The raw free3d export had bounds ~258×256×147 units vs Duck.glb's known-working ~1.65×1.54×1.15 — a 150x+ scale mismatch, real bug, not a hitbox/gesture issue. Rescaled via `trimesh.apply_scale()` to match Duck's range (now ~1.6×1.59×0.91) and re-exported in place. Coin.glb's scale (2×0.3×2) was already in the right range, ruled out as the cause of the separate coin-flinging complaint below.

## Voice — no dollar amounts spoken (2026-08-19 rule)
Trading setups, price levels, and direction are fine to discuss out loud on barehands/voice — **never a dollar amount or account balance** (P/L, risk in dollars, balance). Voice can be overheard in a room; terminal sessions have no such restriction. Also in `CLAUDE.md`'s "Make it yours" so it applies everywhere, not just here.

## Voice

`stage.html` has no voice of its own — it posts typed/voice turns to `http://127.0.0.1:8779/type`, which is [[voice-line]]'s endpoint. Fails silently if voice-line isn't running. See [[voice-line]] for the three services that need to be up (whisper-server, Kokoro TTS, voice-line itself) and how to start them.

## Related

Repo docs: `README.md`, `barehands.md`, `TROUBLESHOOTING.md` (gesture-tuning clinic) — all inside `~/barehands`.

## Update — 2026-08-20

Pulled `27c4ef1` → `f1f8c9e` (clean fast-forward, no conflicts). Upstream moved `barehands.json` out of git tracking entirely (renamed to `barehands.json.example` as a template, real file now gitignored) so a future update can never again collide with local config edits. Restored Adam's real `barehands.json` (name, Notes orb path) from the merged content, reset `.example` back to a clean template. `stage.html`'s local customizations (the "talk to Jarvis" chat box) and the staged media (`Coin.glb`, `Duck.glb`, `GoldCoin.glb`, `IronMan.glb`) were untouched. See [[Fullstack Agent Stack]] for the full multi-repo update.
