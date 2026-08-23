---
status: active
project: forex-trading
type: reference
---
# Malaysian SNR x Orderflow

TradingView Pine v6 indicator built 2026-08-20 from a full written spec Adam supplied. Implements **Malaysian Support & Resistance** — a body-based (not wick-based) S/R method — plus Fresh/Unfresh level tracking, gap levels, engulfing detection, and a simplified continuation helper. Runs alongside [[TWI True North]] as a **separate script**, not a replacement.

**Status: live on Adam's chart, compiles clean (zero errors), verified drawing 37 levels on GBPUSD 5m. Not yet trade-tested.**

## What it detects

**A-Level (Resistance)** — a peak defined by candle *bodies*, never wicks. Two detection paths run in parallel:
- Pivot-based: highest body-high in a `pivLen`-bar swing (default 3).
- Colour-flip: a bullish candle immediately followed by a bearish one → the bullish candle's close becomes the level.

**V-Level (Support)** — the mirror: lowest body-low pivot, or a bearish candle followed by a bullish one.

**OCL (Open-Close / Gap Level)** — where one candle's close meets the next same-colour candle's open (within a tick tolerance, default 2), plus true gaps between consecutive same-colour candles.

**Fresh vs. Unfresh** — every level starts Fresh (solid, thicker). Any candle touching it flips it Unfresh (dashed, faded, touch count shown). After `maxTouches` (default 2) the level is deleted entirely. `onlyFresh` hides everything but virgin levels.

**Extras** — bullish/bearish engulfing markers ("E" labels, on by default); Daily and 4H A/V level projection onto the current chart (off by default); a simplified Drop-Base-Rally / Rally-Base-Drop detector (off by default — impulse leg ≥1.5×ATR, then a tight base ≤0.6×ATR, then a break out of the base).

**Alerts** — `alertcondition` fires on the first tap of a Fresh A-Level or Fresh V-Level, so it can push to Adam's phone without a manual price alert.

## Design decisions worth remembering
- **Levels are deduplicated by ATR distance** (`minSepATR`, default 0.25×ATR) — without this, the two parallel detection paths stack near-identical lines on top of each other and the chart turns into noise. Same lean-chart principle already locked in for [[TWI True North]].
- **Old levels are hard-deleted, not hidden** — `line.delete`/`label.delete`/`box.delete` on expiry, plus a `maxLevels` cap (default 15 per type) that shifts the oldest off. Pine has hard object limits; leaking drawings is what makes an indicator lag or silently stop drawing.
- **Shaded zone boxes default OFF.** The spec listed them as optional; given the standing "chart stays lean" rule they're a toggle, not a default.

## Where it sits vs. Adam's other tools
Related but genuinely distinct from [[TWI True North]] (structure + POC accept/reject + 10-confluence scoring) and [[TWI Sniper ORB]] (opening range breakout EA). This one is purely a **level-mapping** tool — it draws where price should react, it does not score or fire directional signals. The body-based rule is also a real contrast to the wick-inclusive Order Block definition already in [[Chart Analysis Notes]], and to the close-based BOS/CHoCH rule — worth watching whether body-based levels line up with or diverge from the OB zones in practice.

## Gotcha banked 2026-08-20 — the Pine Editor is ONE SLOT (this cost a near-miss)
**`pine_new` does not create a second script.** It opens a blank editor still bound to whatever script slot was last active — so `pine_save` afterward **overwrites that script**. This is the same trap recorded in [[TWI True North]] when Momentum Signal Suite got overwritten, and it happened again building this indicator: TWI True North's slot was silently replaced with SNR code and saved as version 21.

**Recovery that worked (use this if it ever happens again):** Pine Editor → click the script-name dropdown → **Version history…** → pick the last version predating the overwrite (identify it by timestamp against the script's `modified` field from `pine_list_scripts`) → **Restore this version** → **Save**. Full recovery, nothing lost. TradingView keeps every save, so an overwrite is recoverable as long as it's caught.

**The method that actually creates a separate script:** script-name dropdown → **"Make a copy…"** → type the new name → **Make copy**. This genuinely allocates a new script id (verified: `pine_list_scripts` count went 26 → 27). Then inject the new source into that copy and save. **"Create new → Indicator" from the same menu did nothing** — the click registered, the menu closed, and the editor stayed on the original slot. Don't rely on it.

**Standing rule going forward: before writing any new indicator, make a copy first, confirm the script count increased, and only then inject source.** Never inject-then-save into whatever slot happens to be open.

## Full source
Kept in TradingView (script name `Malaysian SNR x Orderflow`, id `USER;b273d92d701d4d01b0155f01428c0861`). Read it back with `pine_open` + `pine_get_source` if it ever needs editing — not duplicated here, since a stale copy in the vault would be worse than no copy (see the no-bloat rule).

## Open / next
- **Still not trade-tested against real outcomes** (i.e., "did the BUY/SELL signal actually lead somewhere good") — the fix below is verified by *signal count and logic*, not by live P&L.
- Multi-timeframe projection (Daily/4H) is **off by default** and unverified — turn on and eyeball before trusting.
- Worth checking whether body-based A/V levels agree with the Order Block zones from Adam's existing framework, or systematically diverge.
- Consider whether BUY/SELL should also require HTF alignment or a Discount/Premium check if the signal count still feels too generous after live use — deliberately not added yet, per the standing "complexity is capped" rule; add only if the current cut proves insufficient.

## Buy/Sell signal system added, 2026-08-21 (Adam: "too many signals, want good setups, easy to understand")
Replaced the raw "E" engulfing-candle tag (fired on **every** engulfing candle regardless of context — 302 labels on a single GBPUSD 5m session, almost all noise) with a filtered **BUY/SELL** signal: an engulfing candle only counts as a signal when it's *also* the same bar that taps a level which was still Fresh — i.e., a real reaction off a real support/resistance level, not a bare candle pattern. Reuses `tapA`/`tapV` (already computed for the level Fresh/Unfresh system) ANDed with `bullEngulf`/`bearEngulf` — no new indicators, no new confluence machinery, just combining two things the script already tracked separately. Added matching `alertcondition`s (`MSNR Buy Signal` / `MSNR Sell Signal`).

**Real bug caught during verification, same session:** the first version of this fix barely moved the count (292 vs. 302 labels) because a level was being marked "tapped" on the **same bar it was created** — a level's price is built from that bar's own action (a pivot a few bars back, or the previous bar's close), so it almost always sits inside the current bar's high/low range by construction, self-triggering a false "Fresh tap" the instant it's born. Fixed by requiring `lv.createdBar < bar_index` before a touch counts. **Verified by data, not eyeballing**: labels went from 292 → 71 total after the fix, with only ~34 of those being actual BUY/SELL signals (the rest are the informational level-status tags, not noise) — a real, checked improvement, not just a plausible-sounding change.

## Gotcha banked 2026-08-21 — this machine's Pine Editor: popped-out window state is unreliable, work around it, don't fight it
On this machine (not necessarily Adam's main desk box), the Pine Editor always opens as a **separate popped-out Electron window**, never docked. Full picture after extensive troubleshooting this session:
- `pine_open` (internal_api) and `pine_get_source`/`pine_set_source`/`pine_save` **are** the same underlying mechanism and **do** work correctly together, verified repeatedly — `pine_list_scripts`' `modified` timestamp is the ground truth, and it moved on the correct script (`USER;bc23c2e674ef4c7193b2b4c716330d0d`, "Malaysian SNR x Orderflow 1") on the first successful landing this session.
- BUT `pine_open` **intermittently fails** ("Could not open Pine Editor") for no visible reason, even moments after `ui_open_panel` reports the panel opened, even on a freshly relaunched app. **The fix that worked every time: just retry `pine_open` once or twice in a row.** It reliably succeeds on retry — no relaunch, no window-juggling needed. This was the single biggest time-sink this session, entirely avoidable by retrying instead of escalating.
- Chasing the visible popped-out window (screenshots, chart-legend "Source code" context menu, dropdown menus) to "confirm" what's open is **not reliable and not necessary** — the window can visibly show stale/wrong content (a genuinely separate, harder-to-diagnose display bug) while `pine_get_source` right after a successful `pine_open` returns the **correct** content regardless. Trust `pine_get_source`'s returned content and `pine_list_scripts`' timestamps, not what the popped-out window looks like.
- `chart_manage_indicator` with `action:"add"` **does not work for custom "My scripts"** (only built-in indicators like RSI/MACD) — it silently returns `new_study_count: 0`. To attach a custom script to the chart: call `indicator_search` with the exact script name (pre-fills the search box), then open the Indicators dialog (`ui_click` on `data-name:"open-indicators-dialog"`), then click the result — but **use coordinates from a fresh `ui_find_element` call**, not coordinates read off a screenshot image. Screenshot pixel coordinates and the coordinate space `ui_find_element`/`ui_mouse_click` actually use are **on different scales** in this environment — every raw "click what I see in the screenshot" attempt missed; every `ui_find_element`-sourced coordinate click landed correctly.
- **Standing rule, still correct:** after any `pine_set_source` + `pine_save`, always run `pine_list_scripts` immediately after and confirm the target script's `id` and `modified` timestamp actually changed before trusting the edit landed.
- The chart currently runs off the duplicate script (`USER;bc23c2e674ef4c7193b2b4c716330d0d`, "Malaysian SNR x Orderflow 1" in the script list — but its internal `indicator()` title is still "Malaysian SNR x Orderflow", so the chart legend and shorttitle "MSNR" look completely normal, no visible difference to Adam). The original (`USER;b273d92d701d4d01b0155f01428c0861`) is now unused/stale, still sitting in Adam's script list. **Cosmetic cleanup still open:** rename the original out of the way (or delete it once confirmed nothing references it) and rename the duplicate to drop the "1" suffix, so the script list isn't confusing later. Low priority — purely cosmetic, chart works correctly as-is.
