---
status: active
project: forex-trading
type: reference
---
# TWI Tap & Close

TradingView Pine v6 indicator built 2026-09-05 from a TradewithPat YouTube Shorts clip Adam sent ("The EASIEST Trade Entry Model (Tap & Close)"). Saved as its own script, id `USER;1b553689d07e43cd9d8abd944242ba6c`.

## The model
1. **Zone** = the full wick-to-wick range of a confirmed swing pivot candle (`ta.pivothigh`/`ta.pivotlow`, default 5 left/5 right bars). Green box = demand (from a pivot low), red box = supply (from a pivot high).
2. **Tap** = price wicks into the zone (low touches a demand zone, high touches a supply zone) — marked with a "Tap in" label.
3. **Close** = the confirming signal only fires once a candle **closes** back outside the zone after tapping it (rejection confirmed) — that's the "Tap & Close" entry, plotted as a buy/sell triangle.
4. Only **one active zone per side** is kept on the chart at a time — a fresh pivot or an invalidation (price closing clean through the zone without reclaiming) clears the previous box/labels immediately. Matters: an early version left every historical zone/label on the chart forever and the whole chart turned into a solid green/red wash within a few dozen bars — rewritten to always clear before drawing a new one.
5. Optional TP/SL projection box on signal, R-multiple configurable (default 2R).

## Status
Compiled clean, visually verified on FX:GBPUSD and EURUSD 15m (real tap-in/close-above signals fired correctly, zones cleared properly, no clutter, correctly overlaid on the main price chart). Not backtested — this is Adam's own idea from a video, not validated for win rate yet.

## Two real bugs found and fixed 2026-09-06 (Adam reported a red error icon on his phone)
1. **Cosmetic: rendered in its own separate pane instead of overlaying the candles.** A script with only `box.new`/`label.new`/`plotshape` and no actual `plot()` call has nothing to bind its price scale to, so TradingView can fall back to a detached pane even with `overlay=true` declared. **Fix:** added one hidden anchor plot — `plot(close, title="(anchor)", display=display.none)` — right after the `indicator()` line. Purely cosmetic, no logic change.
2. **Real: applying it via the indicator search ("My scripts") pulled a STALE cached compiled version** — specifically an old broken one from mid-build that still had the "cannot modify global variable in function" bug, even though the actual saved source was already the fixed, working version (confirmed via `pine_get_source` and `pine_get_errors` both showing clean). This is a caching bug in how TradingView's search-add path resolves a script, not a real problem with the code. **Reliable fix:** open the script in the Pine Editor itself (via the script name dropdown) and use its own **"Add to chart"** button, not the general indicator search/"My scripts" list. A save-then-add-from-editor cycle picked up the correct current version every time in testing; search-add did not, twice in a row.

**If this shows the red error icon again on any device:** remove it from the chart, open **TWI Tap & Close** in the Pine Editor, click **Add to chart** from there (not via search), and it should render clean. If it still errors after that, the actual saved source has a real problem and needs a fresh look — check `pine_get_errors` on the editor itself first.

## Real incident while building this (2026-09-05) — read before touching Pine Editor again
`pine_new` does NOT reliably detach the editor from whatever script was last open, even when `pine_get_source` right after confirms the buffer looks blank. On the very next **save**, it silently overwrote **`TWI Sweep MSS IDM BOS OB`'s real script slot** (id `USER;a4a888ded0eb4c9e94602ea09e357a6e`) with this indicator's code — twice in a row, including once immediately after the first recovery. This is a materially worse version of the bug already logged on 2026-09-01 (which only cost an old, no-longer-wanted script): this slot's real current content was **"TWI VWAP POC OB Suite"** (a combined VWAP+POC+Order-Block script, not what the vault previously assumed — that older note describing this slot as "Sweep MSS IDM BOS OB" is stale; a later Sept 1 session evidently rebuilt/renamed it and nobody updated the note).

**Recovered both times via TradingView's own Version History** (chevron next to the script name in the Pine Editor → *Version history…* → pick the last real version → *Restore this version* → save). No vault-side backup of this script's source existed before tonight, which is why recovery depended entirely on TradingView's own version retention — see the fix below for why that gap is now closed for new scripts.

**The actual safe method going forward:** don't use `pine_new` when any script is already open in the editor. Instead: open the dropdown next to the current script's name → **"Make a copy…"** → give it the new script's name in that dialog → THEN edit/save. This creates a genuinely separate script id from the moment of creation, confirmed by checking `pine_list_scripts` shows a new id before writing real content. `pine_get_source` immediately after `pine_new` looking blank is **not sufficient proof** of a real detach — verify via `pine_list_scripts` id count/uniqueness instead, or just use "Make a copy" and skip the risk entirely.

## Future idea (2026-09-06, parked — Adam's call)
Adam thinks this could become a high-winning EA with a few modifications. Deliberately parked for now — indicator stays as-is on TradingView, no MQL5 port started. Revisit when he's ready.

## Related
- [[TWI Sweep MSS IDM BOS OB]] — the note that turned out to be stale (describes what this slot used to be, not what it currently is; needs a real re-check of its actual current source next time someone touches it)
