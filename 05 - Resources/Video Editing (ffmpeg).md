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

## Analyzing a YouTube video Adam sends (winning method, 2026-10-09, desktop)
1. `python -m pip install --user yt-dlp` (installed 2026-10-09). ffmpeg/ffprobe on the desktop are at `~/voice-line/tools/` (pass `--ffmpeg-location`).
2. `python -m yt_dlp -f "bv*[height<=720][ext=mp4]+ba[ext=m4a]/b" --merge-output-format mp4 --write-info-json --write-auto-subs --sub-langs en --sub-format vtt <url>`. Read the **description and chapters** from `info.json` first.
3. **Dead end:** YouTube returns HTTP 429 on captions after ~2 videos. Don't retry. Transcribe locally instead: `ffmpeg -i x.mp4 -ar 16000 -ac 1 x.wav`, then `~/voice-line/tools/whisper/bin/Release/whisper-cli.exe -m .../models/ggml-small.en.bin -t 12 -f x.wav -otxt`. That takes ~35 s for a 1-min short and ~15 min for a 25-min video; run it in the background.
4. For visuals, build timestamped contact sheets: `-vf "fps=1/2.5,scale=270:-1,drawtext=fontfile='C\:/Windows/Fonts/arial.ttf':text='%{pts\:hms}':...,tile=6x4"`. For on-screen title cards, crop that region at chosen timestamps and `vstack` the crops.
5. **Trust what's spoken and shown over the description.** Elastaboy's descriptions listed different exercises from the ones the videos actually teach.

## Related
[[Jarvis Remote Control]] — the laptop-specific machine, distinct from this one.
