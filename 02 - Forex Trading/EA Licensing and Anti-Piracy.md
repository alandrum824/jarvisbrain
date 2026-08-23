---
status: idea
project: forex-trading
type: plan
---
# EA Licensing and Anti-Piracy

Adam wants to sell his two MQL5 EAs — [[TWI Range Breakout]] and [[TWI Scalp Pro]] — and asked how to stop buyers from just copying/redistributing the compiled file. Brainstorming stage only, 2026-08-23 — nothing built yet, Adam said "not yet" when offered a build.

## The real constraint
Nothing makes a sold file un-copyable — the goal is "not worth the effort to steal," not perfect DRM. `.ex5` (compiled MQL5 bytecode) already has no public decompiler, so never distributing the `.mq5` source is the baseline, free protection either way.

## Three options discussed

**1. Account-number locking, baked in per sale.** Compile a fresh build for each buyer with their MT5 account number(s) hardcoded; EA checks `AccountInfoInteger(ACCOUNT_LOGIN)` on init and refuses to run on any other account. Zero infrastructure, works today. Downside: manual recompile per sale, no way to revoke access remotely once sold.

**2. Publish through the official MQL5 Market.** MetaQuotes handles licensing server-side automatically — no manual compiling, no way to copy the file to another account. Downside: they take a commission, and the EA goes through their code review (source stays private from buyers, but Adam loses some control over how it's sold/priced).

**3. Phone-home licensing via a self-hosted backend — the one Adam is actually leaning toward.** This is what TradeWithPat (TWP, the third-party EA Adam already uses — see [[TWP ORB EA Reference]]) does: TOS acceptance, username registration, "activate" on their website, and the EA calls out to their server on startup to verify the license before it'll trade (the "allow WebRequest for this URL" prompt in MT5 is that check). Recommended path for Adam specifically because he already builds on **Base44** (pay-as-you-go, no new platform to learn):
- Base44 app as the license backend: buyers table (license key or username, active/inactive flag), wired to Stripe/PayPal for payment.
- EA calls that Base44 endpoint via `WebRequest()` in `OnInit()`, refuses to trade if the check fails.
- Buyer experience matches TWP's exactly: accept TOS, enter username, hit activate, allow the WebRequest URL in MT5 settings.
- Real advantage over option 1: one universal compiled build (no per-sale recompiling), and access can be **revoked remotely** — chargebacks, piracy, subscription lapses, all killable without touching the file itself.
- Real cost: Adam is now running and maintaining a small backend instead of nothing, though Base44 keeps that cheap since he already knows the tool.

## Status
Brainstorming only. Not built. Whenever Adam's ready, next step is designing the actual Base44 data model + the `WebRequest` check to add into both EAs' `OnInit()`.

## Related
- [[TWI Range Breakout]]
- [[TWI Scalp Pro]]
- [[TWP ORB EA Reference]] — the real-world reference model (TWP's own activation flow) this is based on
- [[Active Priorities]]
