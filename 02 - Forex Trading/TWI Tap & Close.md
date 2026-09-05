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
Compiled clean, visually verified on FX:GBPUSD 15m (real tap-in/close-above signals fired correctly, zones cleared properly, no clutter). Not backtested — this is Adam's own idea from a video, not validated for win rate yet.

## Real incident while building this (2026-09-05) — read before touching Pine Editor again
`pine_new` does NOT reliably detach the editor from whatever script was last open, even when `pine_get_source` right after confirms the buffer looks blank. On the very next **save**, it silently overwrote **`TWI Sweep MSS IDM BOS OB`'s real script slot** (id `USER;a4a888ded0eb4c9e94602ea09e357a6e`) with this indicator's code — twice in a row, including once immediately after the first recovery. This is a materially worse version of the bug already logged on 2026-09-01 (which only cost an old, no-longer-wanted script): this slot's real current content was **"TWI VWAP POC OB Suite"** (a combined VWAP+POC+Order-Block script, not what the vault previously assumed — that older note describing this slot as "Sweep MSS IDM BOS OB" is stale; a later Sept 1 session evidently rebuilt/renamed it and nobody updated the note).

**Recovered both times via TradingView's own Version History** (chevron next to the script name in the Pine Editor → *Version history…* → pick the last real version → *Restore this version* → save). No vault-side backup of this script's source existed before tonight, which is why recovery depended entirely on TradingView's own version retention — see the fix below for why that gap is now closed for new scripts.

**The actual safe method going forward:** don't use `pine_new` when any script is already open in the editor. Instead: open the dropdown next to the current script's name → **"Make a copy…"** → give it the new script's name in that dialog → THEN edit/save. This creates a genuinely separate script id from the moment of creation, confirmed by checking `pine_list_scripts` shows a new id before writing real content. `pine_get_source` immediately after `pine_new` looking blank is **not sufficient proof** of a real detach — verify via `pine_list_scripts` id count/uniqueness instead, or just use "Make a copy" and skip the risk entirely.

## Related
- [[TWI Sweep MSS IDM BOS OB]] — the note that turned out to be stale (describes what this slot used to be, not what it currently is; needs a real re-check of its actual current source next time someone touches it)
