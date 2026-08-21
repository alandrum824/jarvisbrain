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

## Open — connect to Think Wave
Realistic path is a manual/periodic one: export CSV from Think Wave, then either import it by hand into Base44's entity data, or Jarvis builds an import feature in the app that ingests that CSV format. Adam has login (`Elijah.Landrum`) but Jarvis has no browser/login tool to act on Think Wave directly — Adam would need to pull the export himself, or grant a way to automate it. Alternative: contact Think Wave directly to ask if they have an API for partners/schools that isn't publicly documented. Get direction from Adam before building anything.
