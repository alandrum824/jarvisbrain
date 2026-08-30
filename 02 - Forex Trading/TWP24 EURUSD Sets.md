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
Last login attempt (2026-08-16) to the live account (ending 8996721, AAAFxGlobal-5 Real) failed with "invalid account" four times in a row and the terminal shut down. Account number or credentials may be stale, or the EA may be running on a different machine/VPS entirely. **Superseded 2026-08-30: login works fine now** — confirmed live and authenticating cleanly throughout the entire overnight session (see below). Whatever caused the 2026-08-16 failure had resolved itself by the time of this session.

## 2026-08-29/30 — real backtest data replaces the theory (lot-sizing question substantially answered)

A long overnight session ran real Strategy Tester backtests (not theory) against account 8996721's actual balance (~$391–$420 across the night) instead of the assumed $800. Key findings, all at $400 deposit / 0.01 lots (the real broker minimum) unless noted:

**Stock `EURUSD America.set` (vendor default, grid ON, 8-level ladder):** 0.01 lots → 416 trades, +$83.70 net, PF 1.78, Sharpe 2.11. At 0.30 lots the same config **got margin-called** on 2025.11.05 (stop-out 18% of the test period, account fell from $400 to $179.34) — direct proof that 0.30 lots + this grid ladder is too large for a $400 account, full stop. Grid OFF at the same 0.30 lots survived clean (+$18.05) — the grid, not the raw position size alone, was the primary driver of the blowup, though even grid-off still showed 32.63% equity drawdown at that size.

**Community-sourced files** (from a TradeWithPat Discord thread, "custom-setfiles" channel — author dananiq22, gold leg credited to joewiller92, EU leg to birdseedlw66; explicitly built and shared as **prop-firm-friendly configs, calibrated for a $25,000 account** — author's own words: "adjust accordingly" for other sizes): `EURUSD_M5_NYSE_NO_GRID.set` (real no-grid build, `iSLMode=2/iSL=2.2` — a real, non-ambiguous stop) tested at native 0.01 lots: **100 trades, -$0.10 net, PF 1.00, Sharpe -0.01, but only 6.73% equity drawdown — the tightest risk control of anything tested all night.** Flat, but genuinely safe. The gold companion file (`XAUUSD Breakout Asia.set`, substituted for the author's exact "S/D Asia" file which isn't in this machine's library) at scaled-down 0.01 lots: 10 trades only (too small a sample), -$0.92 net. At the file's native 0.6 lots (correctly proportioned for $25k, NOT $400) it would be wildly oversized — confirmed by testing a different community file's native 0.5-lot size on $400, which also got margin-called.

**A "3 trades at once / 3 per session" regular-tier EURUSD config** (Adam's own real historical usage, confirmed via real MT5 mobile screenshots) was rebuilt from the stock `EURUSD America.set` base with `iMaxTradesAtOnce=3`/`iMaxTradesDaily=3` (up from the stock default of 1/1) at 0.01 lots: **764 trades, +$167.51 net, PF 2.16, Sharpe 3.45, win 76.31%** — the best EURUSD dollar result of the night. Saved as `EURUSD America 3x3.set` in this same folder, with `iLots=0.01` and `User=Alandrum24` baked in (the saved file initially still had the vendor's 0.1-lot default — caught and fixed before it went live).

**4-symbol portfolio replication** (Adam's real "~$300 to ~$970" trading history, clarified as EURUSD+GBPJPY+CHFJPY+gold run simultaneously, not a single file): ran all four legs independently at $400/0.01 lots — EURUSD (above, +$167.51), GBPJPY NYSE (+$82.72, PF 2.24, Sharpe 5.20, DD 4.17%/14.09%), CHFJPY NYSE (+$47.33, PF 2.44, Sharpe 8.20, DD only 1.30%/5.34% — tightest of the four), XAUUSD Breakout Asia (+$681.04, PF 1.41, Sharpe 3.05, but the riskiest — 37.82% equity DD, largest single loss -$72.06). **Naive sum ≈ $978.60 — explicitly NOT a real combined-account number**, since MT5's Strategy Tester gave each leg its own separate $400 rather than one shared pool; a real account running all four would face shared margin and shared drawdown caps. A true merged-timeline equity curve was offered as a follow-up but not yet built.

**Real bug found and worked around:** the compiled `TWP ORB EA.ex5` **hung indefinitely** (confirmed via flat CPU over repeated checks, not just slow) on two different grid-ladder configs during testing tonight, for reasons never definitively isolated (not simply ladder depth — a 10-level CHFJPY ladder ran clean while a smaller 3-level one hung). Safe to force-kill mid-hang since it's Strategy Tester/demo only, no capital at risk from doing so. Worth knowing if a future backtest run on this EA appears to sit doing nothing — check CPU progress before assuming it's just slow.

## Live deployment (2026-08-30) — three legs attached on RisenAdam, real money

Adam confirmed via direct terminal action (not Jarvis/Claude, who has no GUI control over MT5 — checked and confirmed no automation tool reaches MT5, only file/CLI access): **EURUSD, GBPJPY, and XAUUSD charts attached with TWP ORB EA on RisenAdam**, using the three ready-to-load `.set` files built and verified above, all at `iLots=0.01`:
- `regular (most popular)\g_EURUSD America\EURUSD America 3x3.set`
- `regular (most popular)\g_GBPJPY NYSE\GBPJPY NYSE 0.01.set` (new file, built tonight, same GBPJPY NYSE config confirmed clean in the portfolio test above)
- `regular (most popular)\_XAUUSD Asia\XAUUSD Breakout Asia 0.01.set` (new file, built tonight)

AutoTrading confirmed ON by Adam directly. CHFJPY was intentionally left off this initial deployment (only 3 of the 4 tested legs went live). Gold dashboard screenshot confirmed correct load: magic number 900790009, TP 8x/SL 1x, EMA(250) filter all matching the built file. **ZeroPoint was explicitly discussed and NOT added** — see [[ZeroPoint]] for that decision. Next real step, not yet done: verify EURUSD and GBPJPY dashboards the same way, and check the Experts log tab (not just the visual dashboard) for a clean init on all three.

## Job
[[Build TWP Set Files]] — the actual `.set` file format (verified by reading these files directly) and a parameter glossary, for any future lot-sizing/config work on these files.

## Related reference
[[TWP ORB EA Reference]] — config/trade-history screenshots from two *other* TWP accounts (108.181.193.243 and D3101:81322), neither of which is the broken 8996721 login above. Different lot sizing (0.35 static) and a possibly-contradictory grid setup — don't confuse it with this note's validated 0.60-lot/grid-on config when sizing the $800 account.
