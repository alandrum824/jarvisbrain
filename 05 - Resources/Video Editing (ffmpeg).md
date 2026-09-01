---
status: active
project: meta
type: guide
---
# Video Editing (ffmpeg)

How Jarvis can actually help edit video (e.g. Adam's PS5 gaming clips) on a machine that has ffmpeg installed, and where the real limits are.

## What Jarvis can't do
- **No PS5 hardware access.** Can't capture or pull video directly from a PS5 — Adam has to get the clips onto the PC himself first (PS5 Media Gallery → export to USB is the easiest path, or Share-upload then download).
- **No GUI automation for CapCut** (or any other desktop editing app). No mouse/keyboard control tool exists for arbitrary apps in this setup — Jarvis can't click around inside CapCut.

## What Jarvis can actually do
Once raw video files exist on a machine with **ffmpeg installed**, Jarvis can edit them for real via command line — trimming, cutting, concatenating clips, adding text/overlays, cropping (e.g. to vertical for TikTok), adjusting audio, adding music, exporting to whatever format/resolution — all without touching a GUI editor at all. This can do the heavy raw-cutting work before Adam does any CapCut-specific finishing (templates, auto-captions, transitions) himself.

## Confirmed availability
**Confirmed 2026-08-24 on this session's machine** (Windows Server 2025, the mt5-bridge/trading machine — not necessarily Adam's laptop or desktop): `ffmpeg version 9.0.1-essentials_build`, full build with hardware encoding (NVENC/CUDA/AMF), libx264/libx265, subtitles (libass), and audio codecs. Run `ffmpeg -version` to re-confirm on any other machine before assuming it's there — **not yet checked on the desktop or laptop.**

## Related
[[Jarvis Remote Control]] — the laptop-specific machine, distinct from this one.
