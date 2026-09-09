---
status: active
project: personal
type: reference
---
# Elijah Learning Academy

A Base44 app already built on Adam's account (app ID `69f27001c5c4951a3f7d5c0f`).

## What Think Wave is
[thinkwave.com](https://www.thinkwave.com/) — cloud-based school management platform with a gradebook: student records, grades, assignments, attendance, and teacher/student/parent communication. Teachers get an access code; students/parents get personal logins. Paid subscription (monthly/annual) after a 30-day trial.

## Think Wave login
Username: `Elijah.Landrum`. Password not stored here — keep it in Adam's password manager, not in vault notes.

## No live sync path exists
Checked Base44's connector catalog (78 integrations) — no Think Wave connector. Checked Think Wave's own docs — no public developer API, no OAuth, no automated sync. Only manual CSV export (grades, attendance, custom fields) from their Setup → Import & Export screen. So a real-time or automatic sync from Think Wave into this app isn't possible today with what either platform exposes.

## First real data entered 2026-09-08
Adam photographed a stack of Elijah's schoolwork and asked for it to go into the app. Before this, **`WorkSample` and `Assignment` were both completely empty** — these are the first records in either.

Five `WorkSample` records (all Fall, school_year `2026-2027`, dated 2026-09-08):
- Math Notes Ch 1 — Sec 1.1 Numerical Expressions
- Math Notes Ch 1 — Sec 1.4 Distributing Algebraic Expressions
- Math Notes Ch 1 — Sec 1.5 Expressions with Absolute Value
- Science Lab — Solar Heating and Cooling of Soil, Sand, and Water (Part 2 data collection)
- Plot Diagram — "Partly Cloudy" (Pixar), English/Language Arts

One `Assignment` record: **Practice Quiz — Exponents & Order of Operations**, dated 9/4/26, marked graded, A, 100. Every item was checked and is genuinely correct (3^3=27, 2^4=16, order of operations, 25-12+7^2-6*3=44, 60-[10+(10-5)^2]+17=42). The quiz's question #4 asked whether he'd signed up for DeltaMath and he answered "not yet" — **that's still an open action item.**

Each work sample also got a matching `Assignment` at **full credit (graded, A, score 100)** per Adam's instruction, filed against the real course names: three under Algebra 1A, the lab under Biology A, the plot diagram under English 9A.

### School year rolled over to 2026-2027 (2026-09-08)
The whole app was still defaulting to `2025-2026` even though it's September 2026. Fixed both the stored data and the defaults:

**Records migrated:** 9 Courses, 4 JoobiloClass entries (the "Period / CYP" ones added in Aug 2026 — the four "High School" duplicates were already 2026-2027), and the 2 Attendance days dated 2026-08-27/28.

**Schema defaults changed 2025-2026 → 2026-2027** on Attendance, DailyLog, Course, Assignment, JoobiloClass, WorkSample, WeeklyPlan, ComplianceItem, and LearningSchedule, so anything created from here lands in the right year without being told.

**Deliberately NOT migrated:**
- Attendance dated May 2026 and earlier — that genuinely *is* the 2025-2026 year.
- The `LearningSchedule` for week of 2026-05-11 — same reason.
- **The 6 `ComplianceItem` records.** Five are marked completed (PSA filed with California, records folder, attendance log, courses created, work sample folder) and one is not (transcript started). Rolling those forward would have falsely claimed the **2026-2027 PSA is already filed** — California's private school affidavit is an annual filing due Oct 1-15. They were left as the 2025-2026 historical record instead. **Open action: a fresh set of 2026-2027 compliance items still needs creating, and this year's PSA filing is genuinely outstanding.**

### Attendance logged for the start of 2026-2027 (as of 2026-09-08)
Nine school days on record, no absences:
- **Aug 27, 28** (Thu/Fri) — already existed, Joobilo in session
- **Aug 31 – Sep 4** (Mon–Fri) — added, Joobilo in session, perfect attendance
- **Sep 7** (Mon) — `holiday`, Labor Day
- **Sep 8** (Tue) — `present`. Joobilo doesn't hold classes at all during Labor Day week, **but Elijah keeps doing independent work at home every day, and those days still count toward the attendance record.** This is the key distinction for the PSA 180-day requirement — no-Joobilo does not mean no-school.

**Sep 9, 10, 11 were deliberately left unlogged.** They hadn't happened yet at the time of entry, and attendance is a compliance document — future days get logged as they actually occur, never pre-filled.

### Other things to know
1. **No `file_url` on any record — the photos themselves are not uploaded.** The Base44 MCP tools can write entity data but have no path to push a local image into the app's file storage, so the photos have to be attached by hand through the app if the portfolio needs the originals.
2. Several handwritten answers (the two distribution problems, the lab's temperature values, and parts of the plot diagram) were **not legible enough in the photos to transcribe reliably** — each of those records carries a `NEEDS REVIEW` line rather than an invented value.
3. Subject/course naming was normalised from "Math" to the real course name **Algebra 1A** so the records actually link to the Course entity.

## Open — connect to Think Wave
Realistic path is a manual/periodic one: export CSV from Think Wave, then either import it by hand into Base44's entity data, or Jarvis builds an import feature in the app that ingests that CSV format. Adam has login (`Elijah.Landrum`) but Jarvis has no browser/login tool to act on Think Wave directly — Adam would need to pull the export himself, or grant a way to automate it. Alternative: contact Think Wave directly to ask if they have an API for partners/schools that isn't publicly documented. Get direction from Adam before building anything.
