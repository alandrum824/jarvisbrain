---
status: active
project: personal
type: plan
---
# April Mobility App

A Base44 mobility app for [[April]] (Adam's wife), built from four Elastaboy videos she sent. Requested 2026-10-09 ~12:50 AM PT. Adam's full brief: extract every exercise (12 fields each), build 5/15/25–30-min routines and a 4-week beginner progression, a visual guide (real demos only, no fake "from the video" art), and a phone checklist. Safety rule: don't treat normal asymmetry as a medical problem. Ask about medical restrictions before tailoring, and don't give April Adam's conditions.

**Status: LIVE since 2026-10-09 1:51 AM PT** (Adam: "Yes"). **URL: https://aprils-mobility.base44.app** (slug changed 2026-10-09 via `PATCH /api/apps/{id}/metadata/slug`; the old auto slug `hairy-fit-partner-pulse` is now a 404 with no redirect). Deployed checkpoint **v2 look `6ac8afd6a0d66155bc57ebca`** (2:11 AM PT). A full headless iPhone test on the live URL passed (session logged, plan day ticked, 0 errors). Pending: confirmation from Adam/April that it works on her phone. April has no medical restrictions; Adam wants it to "build up to it." Base44 app `6ac8a3d1f1142f2110bac6ce` ("FitPartner" internal name, page title "April's Mobility"), [editor](https://app.base44.com/apps/6ac8a3d1f1142f2110bac6ce/editor/preview). Latest checkpoint "Mobility app v1.1" `6ac8a8ac736c19e7dd74f1d0` (v1 = `6ac8a6e3442c4d50f2b8de6d`). Already `public_without_login`.

## How it was verified
All 4 videos were downloaded and read three ways: description + chapters, the spoken audio (YouTube captions for videos 1 and 3; local whisper for 2 and 4), and timestamped frames plus the on-screen title cards. Method is in [[Video Editing (ffmpeg)]]. **Two video descriptions name exercises the videos never teach**, so the inventory follows what is spoken and shown.

## Verified inventory

### Video 1: "Your pelvis is stuck in one position for 8+ hours a day" (`WRBn5RctDWU`, 87 s)
1. **Kneeling hip flexor stretch** (0:31–0:41): deep half-kneeling lunge, tuck the pelvis under, drive the hips forward. **30 s each side.** Feel it across the front of the hip.
2. **Supine "boat pose" hold** (0:42–0:57): on your back, knees up, posterior pelvic tilt, low back flat on the floor, core braced; extend the legs to make it harder. **3 × 30–45 s.** It looks like a hollow/dead-bug hold, not a seated boat. The description says "Seated Forward Fold" instead, which is not shown.
3. **Single-leg glute bridge** (0:58–1:12): one foot flat, the other leg extended; drive the hips up and squeeze at the top. **3 × 10 per side.**

Shown but not taught: the standing forward hinge with hands on the low back/glutes (0:22–0:27, 1:20–1:25). It's b-roll illustrating a tilted pelvis and back strain, not a drill (Adam's screenshot movement #1).

### Video 2: "Your arches don't collapse on their own" (`43nL0FOBTWw`, 50 s)
1. **Single-leg balance, barefoot** (0:22–0:29): grip the ground with your toes, feel the arch lift, hips stacked over the ankle. No time given.
2. **Hip airplanes** (0:30–0:36): standing on one leg, hinge and slowly open and close the pelvis (rotation at the hip socket). No reps given.
3. **Curtsy lunges** (0:37–0:46): step back diagonally, control the descent, knee tracking straight, grip the floor. No reps given.

The description instead names banded clamshells, lateral band walks and single-leg glute bridges; those are NOT taught. The 15 cm Drop Block forward fold (0:20, Adam's screenshot #3) is a 1-second b-roll clip under "fix the foundation first". It is never named or explained here. It's the same movement taught as the Jefferson curl in video 3. No stick is visible in the frames checked. Other b-roll: deep squat, banded bridge, half-kneeling lunge.

### Video 3: "Your body isn't symmetrical" (`4Ucob3CDam4`, 62 s)
1. **Jefferson curl, bodyweight, used as a drift test** (0:35–0:48): stand tall, tuck the chin, roll down one vertebra at a time with zero weight. If the torso drifts to one side, that's the tight side. Demonstrated on the floor and on a box.
2. **Kneeling thoracic side bend** (0:48–0:58): kneel, reach overhead, side-bend and breathe into the gap between ribs and pelvis. **3 × 20 s, tight/high side only.**

The wide-stance standing side bend with arms overhead (0:17, Adam's screenshot #2) is b-roll, not taught. A taught version of it appears in video 4's cool-down.

### Video 4: "Hip Mobility for Stiff Hips | Follow Along" (`ZRvHuHCcBKQ`, 25:25, live group workshop, NYC)
1. **90/90 position hold** (0:09; title card 0:45 "45 secs"; again at 7:00 "60 secs"): sit in 90/90 "as much as you can".
2. **90/90 front-leg external rotation lifts** (0:46–2:10, card "5 reps"): hands planted either side, keep the front knee down and lift the front foot (even 1 mm). Leaning forward makes it easier; sit more upright as you warm up. Felt in the adductors, deep hip rotators and glute. Cramping is common.
3. **90/90 good mornings, levels 1–7** (2:14–6:55 left side, 7:00–10:15 right side; cards "2 minutes", then "60 secs"). Hinge forward over the front shin and back up, to stretch the external rotators (glute med/max):
   - L1: hands on the front leg or floor.
   - L2: no hands.
   - L3: hands on head.
   - L4–5: push back into deeper external rotation, back leg extended straight back (full pigeon).
   - L6: pigeon, no hands.
   - L7: pigeon, hands on head.

   "Push the floor away" (stay active), breathe, the foot further forward = more intense. Progress over weeks, not in one session; 2–3×/week. Do an extra set on the tighter side.
4. **90/90 back-leg internal rotation lifts** (10:20–13:40, card "60 secs", "drive the foot up towards the ceiling"): the easiest version is leaning on the elbows; lift the back foot to rotate the thigh inward at the socket. More upright = harder. Glute med activation, cramps likely.
5. **Rear-leg IR PAILs/RAILs** (13:44–18:43, card "10 secs push · 10 secs lift · 2 rounds each side · push hard then lift with the knee down"): in 90/90, press the back knee and ankle into the floor for 10 s (PAIL), then lift the foot with the knee down for 10 s (RAIL), then relax. Advanced: a block under the back foot. The coach usually does 3 rounds.
6. **Cool-down** (19:26–25:10), on-screen times:
   - Child's pose 45 s, including walking the hands left/right for a side-body stretch.
   - Upward dog 45 s with slow neck circles both ways.
   - Downward dog 30 s, walking out the calves.
   - Standing forward bend 30 s: folded arms, sway, chin tucked, roll up one vertebra at a time.
   - Standing side bend 30 s: hands on head, wide base, alternating sides.
   - Spine elongation 30 s: hands interlaced palms up, push tall, gentle arch.

Chapter markers: 0:00 intro · 0:14 external rotation · 2:25 good mornings · 6:55 ER drill · 10:21 internal rotation · 13:41 PAILs/RAILs · 19:20 cool down.

## App build (2026-10-09)
**Builder skipped.** The first builder turn only asked a clarifying question (it can't see the videos); stopped it, 0 credits charged. Jarvis wrote all the code directly on the bare scaffold (auth removed; progress lives in device localStorage, no login).
- `src/data/exercises.js`: the single source of truth. 22 exercises (19 verified with a video and timestamp, 3 suggested extras labelled "Suggested extra": knee-to-wall ankle rocks, toe yoga, open book), each with all 12 fields. Routines: Quick 5 min / Daily 15 / Extended 29 (computed incl. 5 s transitions). PLAN = the 4-week build-up plus rules.
- Pages:
  - Today: plan position, streak, start button.
  - Routines: overview, follow-along, checklist.
  - Exercises: library with area filters and a detail page that has every field plus a "Watch the demo at m:ss" deep link into the original YouTube video. No fake illustrations.
  - Plan: 4 weeks × 7 days, auto-ticks when the planned routine is finished.
  - Player: 5 s get-ready, countdown ring, beeps, vibration, screen wake lock, pause/skip, how-to drawer.
  - Checklist (no timer).
  - Guide: printable, Save as PDF.
- **v2 look (Adam: "female powered, purple and black"):** a dark-only theme (near-black background with violet/fuchsia radial glows); Syne (display) + Outfit (body) from Google Fonts; gradient text, glowing gradient buttons, glass cards; hero "Strong. Mobile. Unstoppable." with a time-of-day greeting to April; gradient countdown ring; purple confetti. Print flips to light. The hero uses `clamp(28px,8.2vw,44px)` because Syne is wide and 40px overflowed at 390px. Verified with no horizontal scroll at 360/390/430.

**Tested:** eslint clean, build OK, and an iPhone 390 px headless run through every screen. No horizontal scroll; tap targets fixed to 44 px. A full Quick session logged a session, auto-ticked W1D1, and the streak showed 1. 0 console errors.

**Preview gotcha (bank it):** the sandbox dev preview takes ~30–60 s to render on a cold profile (Vite serves unbundled modules through a proxy), so blank screenshots in the first minute are not a bug. Poll for text instead. `run_command` defaults to `/workspace` (empty); the app root is `/app`.

## Not verifiable / caveats
- The "stick near the lower leg" in Adam's drop-block screenshot can't be confirmed in the frames checked. A 1-second b-roll clip carries no instruction.
- No source gives reps for the arches drills or a hold time for the pelvis video's b-roll hinge.
- The coach's lines about pelvis "locked," QL "locked short," and "weak glutes cause flat feet" are his framing, not diagnoses. Per Adam's brief, the app treats asymmetry as normal.

## Related
[[Base44 Apps]] · [[Video Editing (ffmpeg)]]
