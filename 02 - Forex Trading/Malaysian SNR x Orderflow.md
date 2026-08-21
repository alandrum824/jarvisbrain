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
- **Not trade-tested.** Compiles clean and draws, but no setup has been taken off it.
- Multi-timeframe projection (Daily/4H) and the DBR/RBD helper are both **off by default** and unverified — turn on and eyeball before trusting.
- The DBR/RBD detector is deliberately simplified (fixed-lookback impulse + tight base). If Adam wants real Type 2 continuation detection it needs proper swing-anchored legs, not a bar-count window.
- Worth checking whether body-based A/V levels agree with the Order Block zones from Adam's existing framework, or systematically diverge — that comparison would say a lot about which method is actually mapping the same institutional footprints.
