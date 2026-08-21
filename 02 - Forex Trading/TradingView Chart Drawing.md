---
status: active
project: forex-trading
type: reference
---
# TradingView Chart Drawing

How to read and draw on Adam's live TradingView chart, reliably and fast. Discovered the hard way starting 2026-08-17 — read this before improvising, so the discovery tax never gets paid twice.

## Transport 0: tradingview-mcp (installed 2026-08-18 — use this first, once verified)
A real, purpose-built MCP server that talks to TradingView Desktop over CDP (port 9222) — replaces the hand-rolled pain of Transports 1/2 below. 84 tools: `chart_set_symbol`/`chart_set_timeframe`/`chart_scroll_to_date` for navigation, `draw_shape` (horizontal_line, trend_line, rectangle, text) for markup, `data_get_pine_lines`/`data_get_pine_labels`/`data_get_pine_boxes` for reading custom-indicator output (Adam's Pafx Secret template draws with Pine graphics, invisible to normal data tools — these are the only way to read it programmatically), `capture_screenshot`, `alert_create`, `replay_*` for backtesting, `pine_*` for editing/compiling Pine Script, `tv_health_check` to verify the connection.

**Repo:** `github.com/tradesdontlie/tradingview-mcp`, cloned to `C:\Users\aland\tradingview-mcp`. Full tool list and decision tree in the repo's own `CLAUDE.md` — read that first for which tool to reach for.

**Setup done:** `npm install`'d with the portable Node at `C:\Users\aland\Downloads\node-v24.19.0-win-x64\...\node.exe` (no system-wide Node/npm on PATH — this machine only has the portable extract). Wired into `C:\Users\aland\.mcp.json` as the `tradingview` server, using that same absolute node.exe path (not bare `"node"`, to avoid PATH-resolution surprises inside Claude Code's own process). `server.js` passed a syntax check.

**Verified end-to-end 2026-08-18.** After a Claude Code restart, `tv_health_check` returned `cdp_connected: true` / `api_available: true` on the first try — TradingView Desktop wasn't even running yet, so `tv_launch` was used first (auto-detected the MSIX install, relaunched with the debug port, ~1 min for the local package copy) and the health check passed immediately after. This is now the default transport for everything — reading, navigating, and drawing.

**Transports 1 and 2 below are now legacy/historical fallback only** — kept for understanding what the MCP server abstracts away, and as a manual backup if `tradingview-mcp` itself is ever down. Default to Transport 0 first every time.

## Transport 1 (legacy, hand-rolled): TradingView Desktop app via raw CDP

## Standing workflow (legacy — superseded 2026-08-18)
**Superseded by Transport 0.** This Desktop/Chrome split was the workaround for not having a real drawing tool over CDP. Now that `tradingview-mcp`'s `draw_shape` is verified live, the whole division is moot — use Transport 0 for reading and drawing both. Left below for reference only.

Don't pick a transport ad hoc — this is the default division of labor every time, not just when drawing is hard:

- **TradingView Desktop (Transport 1) is the primary chart, for everything except drawing.** Reading price action, indicators, existing drawings, order blocks, FVGs, structure, liquidity, support/resistance, Adam's chart setup — all read from Desktop. Changing symbols and timeframes happens through Desktop. Multi-timeframe analysis (1h → 15m → 5m) is done on Desktop.
- **Chrome (Transport 2) is for drawing/markup only.** Entry lines, stop loss, take profit, zones, order blocks, FVG boxes, trendlines, labels, or any other visual markup — Chrome only, because it's the only transport with a proven precise-drawing procedure (see below). Once the drawing is placed, return to Desktop for continued analysis/navigation. **Don't switch the whole workflow to Chrome just because drawing is easier there** — go there, draw, come back.
- If multiple Chrome browsers are connected and it's unclear which one has the live TradingView tab: use the live-selection method (`switch_browser`, prompts every connected extension so Adam picks in whichever one is right) **once**, then remember that browser for future TradingView drawing tasks this session.

**Every discretionary setup review follows this sequence:**
1. Check 1h for direction/context.
2. Check 15m for the setup.
3. Check 5m for entry confirmation.
4. Give a clear **BUY / SELL / WAIT** call.
5. Give entry zone, stop loss, take profit, R:R, what confirmation is still needed, and what invalidates the idea.
6. Draw the final setup on Chrome when appropriate.

**Never place or execute a live trade without Adam explicitly saying so.** Default is analysis and chart drawings only.

## Transport 1: TradingView Desktop app via CDP (primary — reading, symbols, timeframes, navigation)
TradingView Desktop is Electron under the hood (confirmed: `chrome_100_percent.pak`, `v8_context_snapshot.bin`, etc. in `C:\Program Files\WindowsApps\TradingView.Desktop_...\`). It supports the standard Chromium remote-debugging port, which gives clean CDP screenshots — **no black-canvas problem at all**, unlike the browser-tool method below.

**Setup (needed once per app launch — the debug port is NOT on by default):**
1. Kill any running instance: `Get-Process -Name TradingView | Stop-Process -Force`.
2. Relaunch with the flag directly (don't use the Start Menu tile / `shell:AppsFolder`, which won't pass it): `Start-Process "C:\Program Files\WindowsApps\TradingView.Desktop_<version>_x64__n534cwy3pjxzj\TradingView.exe" -ArgumentList "--remote-debugging-port=9222"`. The exact `_<version>_` folder segment can drift on app updates — glob `Get-ChildItem "C:\Program Files\WindowsApps" -Filter "TradingView.Desktop_*"` if the hardcoded path 404s.
3. Confirm it's up: `Invoke-RestMethod http://127.0.0.1:9222/json/version` — should return a Chrome/Electron version block.
4. Find the real chart page target: `Invoke-RestMethod http://127.0.0.1:9222/json/list` — look for `"type":"page"` with a `tradingview.com/chart/...` URL (the app also opens several blank/internal Electron pages — ignore those). Adam's saved layout lives at a stable URL, e.g. `https://www.tradingview.com/chart/uJnBMo6l/`.

**Driving it — no MCP tool exists for arbitrary CDP targets (claude-in-chrome only drives the Chrome extension), so it's raw WebSocket JSON-RPC.** Built a reusable helper: `cdp-tv.ps1` (written to session scratchpad, `Read` its source if it needs restoring in a fresh session) wraps `System.Net.WebSockets.ClientWebSocket` with commands:
- `-Cmd eval -Expr "<js>"` — `Runtime.evaluate`, returns the JSON result.
- `-Cmd navigate -Url "<url>"` — `Page.navigate`.
- `-Cmd screenshot -OutFile "<path>"` — `Page.captureScreenshot`, writes a real PNG straight to disk.
- `-Cmd bringtofront` — `Page.bringToFront`.

**Switching symbol without disturbing Adam's saved layout/drawings:** navigate the existing chart tab to the same saved-chart URL with a `?symbol=EXCHANGE:TICKER` query param appended, e.g. `https://www.tradingview.com/chart/uJnBMo6l/?symbol=OANDA:XAUUSD`. This is TradingView's own deep-link mechanism (how "share chart with this symbol" links work) — it swaps the instrument in place, keeps the layout, indicators, and all of Adam's drawn objects (Pafx Secret template, order blocks, etc.) intact. Wait ~5s after navigating before screenshotting.

**Reading:** `-Cmd screenshot` renders the live canvas correctly on the first try — Fib levels, MSS labels, order-block boxes, price ticker, all legible. No snapshot-image workaround needed (contrast with Transport 2 below).

**Clicking UI elements (interval, symbol search, etc.) — proven 2026-08-18:** `cdp-tv.ps1` now also supports `-Cmd click -X.. -Y..` (`Input.dispatchMouseEvent`), `-Cmd key -Key Enter|Escape` (`Input.dispatchKeyEvent`), and `-Cmd type -Text2 "..."` (`Input.insertText`).

**CRITICAL gotcha — coordinate scaling:** `Page.captureScreenshot` returns pixels at the OS's device pixel ratio (this machine: 1.5x), but `Input.dispatchMouseEvent` expects CSS/viewport pixels. Reading a click target's position off a screenshot and feeding those pixel coordinates straight to `click` will click the wrong element (found the hard way — clicked what looked like the interval box and hit the Indicators menu instead). **Always divide screenshot pixel coordinates by `window.devicePixelRatio` before clicking** — check it once per session via `-Cmd eval -Expr "window.devicePixelRatio"` (don't assume 1.5, it's a per-machine/per-display setting). Confirmed workflow: screenshot → identify target in screenshot pixels → divide x,y by DPR → click → screenshot again to verify.

**Changing timeframe (proven procedure):** click the interval label top-left (e.g. "15m") to open its dropdown, screenshot to read the option list (Ticks/Seconds/Minutes/Hours sections), click the target option by its (DPR-corrected) coordinates. Re-opening the dropdown after a change re-renders it at the same position, so the same open-click coordinate works repeatedly; only the option's row position needs recalculating from a fresh screenshot if the menu contents shifted.

**Hovering to read an exact price (proven 2026-08-18):** `-Cmd click -X.. -Y..` also works as a hover/crosshair-read — clicking with the default cursor tool (no drawing tool active) just moves the crosshair, it doesn't place anything. The exact price at the cursor's y-position appears in a small label at the left edge of the chart (not at the cursor's x-position — it always renders on the price axis). This is far more reliable than computing price from screenshot pixel math by hand (gridline label positions aren't evenly spaced enough to trust) — always confirm swing high/low prices this way before handing Adam real entry/stop/TP numbers, not by eyeballing.

**Drawing — tried and failed 2026-08-18, don't retry the same way:** attempted the Rectangle tool via its documented shortcut (`Alt+Shift+R`) using `Input.dispatchKeyEvent` with a `modifiers` bitmask (Alt=1, Shift=8) — it did not select the tool (left toolbar stayed on the default cursor). Also tried clicking left-toolbar icons blind to find Rectangle/Fibonacci by trial and error — the toolbar's icon set and order shift dynamically (flyout submenus change what's docked after use), so guessing coordinates from one screenshot doesn't hold. Injecting a synthetic `KeyboardEvent` via `Runtime.evaluate` (e.g. for a `/` quick-search shortcut) also did nothing — untrusted JS-dispatched events are ignored by the app the same way browsers ignore them. **Conclusion: use Transport 2 for all drawing, per the standing workflow above, until someone deliberately reverse-engineers the real modifier/hotkey wiring or finds the actual Quick Search element on the desktop app.**

## Transport 2: Claude in Chrome browser tool (drawing/markup only, per the standing workflow above)
Use for placing entry lines, stop loss, take profit, zones, OB/FVG boxes, trendlines, or labels — the only transport with a proven precise-drawing procedure. Return to Transport 1 (Desktop) afterward for continued reading/navigation.

### Reading the chart (the canvas is invisible to screenshots)
TradingView's chart plot is WebGL canvas — plain `computer` screenshots of it often come back solid black even though the page is live (price ticker text overlays render fine, since those are DOM, not canvas). Don't trust a blank canvas as "broken."

**Fix:** use TradingView's own snapshot feature — it's reliable and gives a real static image:
1. Click the camera icon (top toolbar, "Take a snapshot").
2. Click "Open in new tab" in the flyout menu.
3. That page's `<img>` often LOOKS broken (broken-image icon) even though it loaded fine — don't trust the visual. Confirm via `javascript_tool`: `document.querySelector('main img')?.src` and check `naturalWidth`/`complete`.
4. Navigate directly to that image src (`https://s3.tradingview.com/snapshots/...png`) and screenshot — renders perfectly every time.

Sometimes the live canvas DOES render in a plain screenshot too (seemed to start working after a modal open/close cycle) — worth a quick screenshot check first since it's faster when it works, but never assume; fall back to the snapshot method the moment it comes back black.

### Drawing on the chart — the reliable path
Pixel-perfect click/drag on the live canvas is unreliable: `left_click_drag` and rapid click-click sequences often fail to register as a real draw gesture, or silently create a degenerate (zero-size, invisible) object. **Don't fight the pixel math — draw rough, then fix with exact numbers:**

1. **Select the tool by name, not by icon guessing.** Click "Quick search" (magnifying-glass icon near top-right of the toolbar) and type the tool name (e.g. "Rectangle") — the result shows the keyboard shortcut (Rectangle = `Alt+Shift+R`). Use the shortcut going forward.
2. **Confirm the tool is actually selected** before drawing — zoom into the left toolbar; the active tool's icon is highlighted. Do this as its own step; don't chain tool-select and draw in a way that risks the click landing before the keyboard shortcut registers.
3. **CRITICAL: keep the right-side Object tree/Data window panel CLOSED while computing click coordinates.** Opening it shrinks the chart viewport (e.g. 1568px → 1280px wide), silently invalidating any pixel coordinates computed from an earlier screenshot. Always take a fresh screenshot immediately before clicking to know the current true viewport size.
4. **Draw anywhere roughly close** (a rough click-drag or click-then-click on the canvas). Don't waste time trying to nail the pixel position — it doesn't matter yet.
5. **Open Object tree** (right-side icon, "Object tree and data window") to confirm the object was created — it'll be at the top of the list, generically named ("Rectangle", "Trendline", etc.).
6. **Double-click the object's entry in the tree** to open its settings dialog, go to the **Coordinates** tab, and type the *exact* price values for each point (e.g. `4325.000` / `4311.847`). This is the fast, reliable, pixel-free way to place something precisely — use it every time instead of trying to drag precisely.
7. **Style tab** in the same dialog sets border color/thickness/fill — default styling can be nearly invisible against Adam's existing colored Fibonacci/indicator zones, so bump border color to something bold (e.g. orange) and thickness to max if it needs to stand out.
8. Click OK, close the panel, and verify with a fresh snapshot (per the reading section above).

### Known gotchas
- Deleting stray/duplicate objects: select in Object tree, click the trash icon on that row. Adam's own indicator drawings ("Fib retracement", "Short position", "Long position", "Trendline", "Text" labels from his Pafx Secret indicator template) live in the same tree — never delete those, only entries created this session.
- The floating mini-toolbar that appears near the top of the chart after a draw action is not reliable confirmation that a *visible* object was placed — always verify via Object tree + Coordinates, not by eye.
- **Object tree panel reopens itself after a page reload** on this account/layout — don't assume a closed panel stayed closed across a navigate.

### Saving — unresolved as of 2026-08-18, two real blockers found
Drawing itself works (Rectangle tool, rough drag, Coordinates dialog with exact prices — all proven reliable). **Persisting it does not**, and two separate root causes were confirmed the hard way, each costing real time:

1. **One tab only.** TradingView killed the whole session mid-drawing with an explicit in-app message: *"We've closed this connection... you've exceeded your plan's limits."* This happened after 3-4 simultaneous tabs were open against the same TradingView account (drawing tab + snapshot-viewer tabs + a verification tab). **Never have more than one TradingView tab open at once on this account** — close snapshot/verification tabs immediately after reading them, before opening another.
2. **A stray floating widget sits on top of the real Save button.** A small floating control (drag-handle `⋮⋮` + a `⊞+` grid icon, hovering roughly at the top-center of the chart, around screenshot x=798-837/y=68-108 at 1568px width) intercepts clicks meant for the "Save all charts..." toolbar button underneath it — clicking there opens a multi-chart layout-picker panel instead of saving, even when using `find` + element-ref clicks (not raw coordinates). This happened consistently across multiple attempts. **Not yet solved:** never found what spawns this widget or how to dismiss/drag it away permanently. Whether it's a fixed piece of chrome on this particular saved layout or a leftover from an earlier stray action is unconfirmed.

**Net effect: as of 2026-08-18, no session has confirmed a drawn object survives a page reload.** Don't claim a drawing is saved without verifying via a fresh single tab's Object tree (per the reading section above) — the "Save" text label disappearing is not sufficient proof (it went blank in a way that turned out to just mean the layout-picker panel had opened over it, not that a save succeeded).

**Resolved 2026-08-19 via Transport 0.** Checked the real Save button's state through `tradingview-mcp`'s `ui_find_element` (`strategy: "aria-label"`) rather than guessing from a screenshot — it reported `aria-label: "All changes saved"` directly, real DOM state, not a visual guess. TradingView auto-saves as drawings are added; the whole "unresolved save" problem above was specific to the old Chrome-browser-tool path (the floating widget blocking the Save button, single-tab session limits) — it was never actually broken via CDP/the MCP server. Use `ui_find_element(query: "Save", strategy: "aria-label")` to verify save state going forward instead of re-fighting the old browser-tool problems.

**Before trying again:** (a) confirm only one TradingView tab is open, (b) try to identify and dismiss the floating grid widget first — screenshot the top-center chart area before touching Save, (c) as a fallback, try the Ctrl+S keyboard shortcut with focus explicitly on the chart canvas (tried once without success, but wasn't isolated from the widget-overlap problem, so it hasn't been fairly tested).
