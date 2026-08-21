---
status: active
project: forex-trading
type: reference
---
# TWP24 EURUSD Sets

Five session-specific `.set` files for the TWP ORB EA on EURUSD, built with the grid system disabled — Adam's call after deciding the grid was too risky, even though in practice it rarely hit the $300 daily drawdown cap.

## Where they live
`C:\Users\aland\HQ\TWP24 EURUSD Sets\` — `twp24 EURUSD NY.set`, `AMERICA.set`, `LONDON.set`, `EUROPE.set`, `ASIA.set`.

**Not yet staged into a terminal.** No MT4/MT5 install tied to TWP was found on this machine, so these are sitting in the HQ folder, not a terminal's Presets/Sets folder. They need to be moved into the right terminal manually, or Jarvis needs the exact terminal path to do it.

## How they were built
Base: TWP Robot's own shipped **EURUSD AMERICA** preset (v1.13.1, downloaded 2026-07-08) — the only EURUSD set file found on the machine. Per session file, only the session-window selector and its matching DST region were changed (mapped from TWP's own other session set files, not guessed). Each file got its own magic number so they don't collide if more than one runs at the same time. Everything else — lot size, TP, entry logic (instant retrace off the opening-range edge), filters, risk caps — was left exactly as TWP shipped it: **still the stock 0.10 fixed lot size**, not resized for Adam's account.

## Open — lot sizing was never finished
Adam asked to resize these for an **$800 account**. Context he gave: 0.60 lots, up to 3 concurrent trades, up to 3 trades per session, with the grid on, worked fine and was profitable at that size — it rarely hit his $300 daily drawdown cap. What actually blew it up wasn't the grid or the trade-count caps, it was that he eventually pushed the **lot size itself too high**. So the grid/3-concurrent/3-per-session structure is the validated part; lot size is the variable to size conservatively for $800.

That resizing question was never answered — the session hit a technical bug (voice-line's brain desynced after an interrupted turn and started returning empty replies) before Jarvis could respond, and the fix required a restart that wiped the conversation. See [[Review Trades and Risk Management]] for the general risk-review job; this note is the state to pick the lot-sizing work back up from.

**Do not size these from theory.** Work it from the account balance, the $300/day and 4%/8% drawdown caps already in the base file, and Adam's stated risk tolerance — and confirm with him before calling it final, per the no-live-changes-without-confirmation rule.

## Also open: live account login
Last login attempt (2026-08-16) to the live account (ending 8996721, AAAFxGlobal-5 Real) failed with "invalid account" four times in a row and the terminal shut down. Account number or credentials may be stale, or the EA may be running on a different machine/VPS entirely. Unresolved as of this note.

## Job
[[Build TWP Set Files]] — the actual `.set` file format (verified by reading these files directly) and a parameter glossary, for any future lot-sizing/config work on these files.

## Related reference
[[TWP ORB EA Reference]] — config/trade-history screenshots from two *other* TWP accounts (108.181.193.243 and D3101:81322), neither of which is the broken 8996721 login above. Different lot sizing (0.35 static) and a possibly-contradictory grid setup — don't confuse it with this note's validated 0.60-lot/grid-on config when sizing the $800 account.
