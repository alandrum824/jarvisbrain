---
status: active
project: personal
type: reference
---
# Juvenile Virtue

Adam's artist name for his music — Christian rap and alternative rock. Released on Spotify and Apple Music. Uses Suno (AI music generation) as part of the production process, per Adam (2026-08-18) — noted as stated; worth confirming exact workflow if it ever matters for a task.

Artist website: **jvsession.com** — this is the "JV Room" app project (seen in the claude.ai chat history) confirmed by Adam 2026-08-18: the app *is* the website, not a separate thing. It's a real Base44 app, ID `6a7aaf7b0fa2e04cc27a0ad7` ("Juvenile Virtue: The JV Room") — Jarvis has direct code access via the Base44 MCP tools. One of Adam's 92 total Base44 apps — see [[Base44 Apps]] for the full inventory. Far more than a landing page: full auth, a community system (posts, comments, reactions), a Premium tier with checkout/webhooks, and custom song ordering.

**SEO/social metadata — fixed and live (2026-08-18):** `index.html` had zero meta description, Open Graph tags, or Twitter card. Added all three (description, OG title/description/image/url, Twitter card) via the Base44 MCP tools. Adam then sent the real JV Session key art (crown/JV logo, "Listen · Hang Out · Talk Music · Connect") — turned out this exact image is already hosted on Base44's CDN (used on the homepage hero), so swapped the OG/Twitter share image and the browser favicon to that real branded asset instead of the generic Base44 icon/plain screenshot. Checkpointed before and after each round. Adam published from the Base44 dashboard — confirmed live on the real jvsession.com by reading the actual meta tags off the page.

## Site audit (2026-08-18, ongoing while Adam sleeps — "permission to build")
Full-site audit requested. Findings so far:
- **`payments-webhook` function: solid, no changes made.** Proper RS256 JWT verification on Wix's webhook, correct idempotency, grant-before-mark-paid ordering so a crash never grants access without payment recorded. Explicitly marked "do not rewrite the plumbing" in its own header — respected that.
- **`Home.jsx`: solid, no changes made.** Well-structured React Query data fetching, sensible trending/most-discussed logic, handled empty states.
- **`manifest.json` — Base44 auto-generates its own** at `/api/apps/manifests/{appId}/manifest.json`, which silently shadows any manifest.json written into the repo. It already references a real branded icon (`11605e178_logo.png`) Adam didn't mention and Jarvis didn't know about, but its theme/background colors are default black/white, not matching the site's dark theme — minor, not fixed (no tool access to Base44's dashboard-level app settings that actually drive it). Deleted the now-dead manual `manifest.json` file — well, *attempted to*, see gotcha below.
- **`robots.txt`/`sitemap.xml` needed to move into a `public/` folder** — Vite's static-asset convention, not the repo root. Done via `write_file`; the stale root-level copies could not be cleaned up (see gotcha). Confirmed the *preview* domain auto-serves a `Disallow: /` robots.txt (correct — staging shouldn't be indexed); the real fix only takes effect on jvsession.com once Adam publishes.
- **Platform gotcha:** `run_command`'s shell sandbox was stuck on a stale snapshot the whole session — `ls` kept showing a near-empty directory while `list_directory`/`read_file`/`write_file` (a separate code path) saw the real, current file tree. Don't trust `run_command` for anything file-state-dependent in this app without independently verifying against `list_directory` first.

**Still pending Adam's Publish click** (asleep as of this checkpoint): the favicon/OG-image swap to the real key art, and the `public/robots.txt` + `public/sitemap.xml` move.

**Content findings — flagged, not touched (creative/brand calls, not Jarvis's to make):**
- `About.jsx`, `Music.jsx`, and 10 real songs in the `Song` entity all checked out solid — real audio/cover art, no empty-content problem.
- One song, **"Ridin Drawdown"** ("Ridin drawdown, living the grid"), uses forex terminology (drawdown, grid — literally the TWP ORB EA language) with no faith framing, unlike every other song's clearly spiritual description. Worth Adam's call on whether that's an intentional trading-life crossover or doesn't fit the "faith-based music" brand.
- Only 2 of 10 songs have the story fields (story_title/story_body/story_verses) filled in — the two that do are genuinely strong personal writing. The other 8 are blank; filling them in is a real engagement lever given the site's own tagline ("the music doesn't end when the song does").

TikTok: [@juvenilevirtue](https://www.tiktok.com/@juvenilevirtue).

Publishes/distributes songs (to Spotify, Apple Music, etc.) via **DistroKid**.

## Release workflow
See [[Release a Juvenile Virtue Song]] for the actual Suno → DistroKid → platforms → TikTok flow, and what Jarvis does at each stage.

## TikTok MCP (read-only, third-party)
`tiktok-mcp` (github.com/Seym0n/tiktok-mcp) is cloned and built at `C:\Users\aland\tiktok-mcp`, wired into this project's `.mcp.json` (key stored there, not repeated here). Adam asked for it despite Jarvis's pushback that it doesn't add capability beyond what browsing TikTok directly already gives — worth knowing going in: it's **read-only** (subtitles, post details, search — no posting, no private analytics), and it routes through a third-party service, **TikNeuron**, not TikTok's own API directly.

**Real bug found and fixed 2026-08-18:** even after a Claude Code restart, the server never actually connected — `.mcp.json` had it configured with a bare `"command": "node"`, but this machine has no system-wide Node on PATH (only the portable extract), so Claude Code's own process couldn't resolve it. Same class of issue `tradingview-mcp` deliberately avoided by using node's full absolute path instead. Fixed `.mcp.json` to point at the portable node.exe directly, matching the tradingview-mcp pattern. Confirmed the built `index.js` exists. Still needs a fresh Claude Code restart to actually prove the connection — not yet verified live.

## Growth goal
Adam wants to actively grow the TikTok following, not just post at release time — see [[Grow Juvenile Virtue on TikTok]] for the strategy and the real-numbers evidence behind it.
