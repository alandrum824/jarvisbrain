---
status: active
project: meta
type: reference
---
# StrumMaster

Adam's guitar-learning Base44 app (app id `6aa65e34d09ee6acd5a73ad5`) — song lookup with real chords/tabs/strumming, an interactive Play Mode, and a guitar tuner. Black/gold/green styling, don't redesign.

## What's real vs. what's not

- **Tuner — REAL, confirmed working by Adam on a real device (2026-09-14).** Genuine Web Audio autocorrelation pitch detection off the live mic, real cents math, needle moves off real frequency, turns green in tune.
- **Song Finder / chord dictionary / tabs / strumming display — REAL.** LLM-backed (`getSongChords` function), returns real chord shapes, sections, timed chord events, tab text.
- **Play Mode — REAL, built out 2026-09-13/14:**
  - Song Tempo auto-advance on real BPM/beats/speed, 4-beat count-in, beat-dot indicator phase-locked to BPM.
  - Real microphone chord-matching (`src/hooks/use-chord-listener.js`) — derives each chord's actual pitch classes from its own fret data (`src/utils/chord-notes.js`, no name lookup table), matches live mic chroma against them with smoothing + a 5-consecutive-frame confidence gate. No red-flash on misses (beginner-friendly per Adam's spec).
  - Follow Me now genuinely waits for a real mic HIT + 300-400ms confirm before advancing — replaced the old fake "I played it" button.
  - Upcoming chord rail (3 ahead, sliding/shrinking), strumming pattern shown + highlighted under the chord, section X/Y + progress bar + big transition label on section change, chord/diagram sized up for 2-4ft readability.
  - Practice This Chord: tapping a chord in the dictionary opens a full-screen practice card, same real mic listener, streak counter to 3, "Ready to use it in the song →".

## Known gaps (flagged, not yet fixed as of 2026-09-14)

- **No fallback if mic permission is denied in Follow Me** — user gets stuck with no way to advance. Real bug, needs a manual skip fallback for that one case.
- **Chord-matching thresholds are reasoned, not tuned** — 0.72 confidence match, 40dB noise floor, 5-frame smoothing were set from first principles, not from real guitar audio. Tuner's own algorithm (autocorrelation, single-pitch) was proven correct on-device; the chord-chroma matcher hasn't been guitar-tested yet.
- **False-positive risk between similar chords** (e.g. C/Am share most notes) — nothing currently checks the current chord's match score against runner-up chords, just an absolute threshold.
- **Detection loop runs a full FFT every animation frame (~60fps)** — real battery/CPU cost on a phone; not yet throttled.
- Base44 MCP connection expired mid-build 2026-09-14 — needs Adam to reauthorize before any further live status checks or edits.

## Related
[[Base44 Apps]] — full app inventory this one belongs to.
