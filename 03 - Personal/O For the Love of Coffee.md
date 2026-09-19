---
status: active
project: personal
type: plan
---
# O For the Love of Coffee

Family coffee brand Adam is building with his wife. Not a laptop/productivity/hipster-café brand — it's about family, connection, sarcasm, memories, and traditions: early mornings before volleyball and football, Disneyland days, Airbnb mornings, road trips, Christmas lights and movies, cabin trips, and the ordinary mornings where everybody wakes up half-asleep and gets talkative once the coffee kicks in.

## Brand

**Tagline (locked):** "The first cup gets us talking. The second gets us in trouble."

**Voice:** warm, sarcastic, family-first, nostalgic, funny, real, slightly chaotic, still heartfelt. Summary line: **"Looks cozy. Talks back."** Avoid corporate/luxury/"rich people"/hustle-culture/tech-laptop language and generic inspirational coffee quotes. Supporting lines already approved (use sparingly so the main tagline stays special):
- "Who's grabbing the coffee?"
- "Coffee first. Personality loading."
- "Strong coffee. Loud family."
- "Same crew. Different adventure."
- "A few sips away from liking each other again."
- "Coffee isn't the memory. It's usually there when the memory happens."

**Visual identity:** warm cream/ivory base, coffee brown, deep navy blue, subtle purple (purple matters to Adam's wife, blue to Adam — both tasteful and subtle, not loud). Nostalgic, warm, family-centered — a little like an old favorite holiday movie or a cozy small-town/New York winter coffee moment, but works year-round.

**Logo (locked):** circular, story-rich, family life + coffee mugs + sports/travel/cozy imagery, subtle blue and purple, carries the tagline. Direction is chosen — do not redesign from scratch. Adam's wife also likes a simpler secondary mark concept: **O + heart/love + coffee bean**, reading visually as "O + Love + Coffee" — a candidate for a simplified/small-space version (e.g. favicon, packaging accent) alongside the main circular logo, not a replacement for it.

**Faith:** God is the foundation of the business, but the brand stays welcoming, not preachy. Reflected subtly — small scripture references, a quiet packaging detail, or a line like "Built with faith. Served with love. Everyone is welcome at the table."

## Website

Base44 site, live at https://our-coffee-hearth.base44.app — app name in Base44's dashboard is "O For the Love of Coffee" (search "coffee" to find it; last touched 2026-09-17). Published status confirmed live same day: hero tagline, nav (Shop / Our Story / FAQ / Contact), CTA currently reads "Coffee Coming Soon."

Site is built and should now be **polished, not rebuilt**. Already includes: real logo, hero tagline, Our Story, Coming Soon roast section, email capture, family memory cards, and the supporting phrases above.

**Website priorities:** mobile-first, real family photography, scrapbook/polaroid feel, less generic stock-coffee imagery, no fake reviews, no invented roast details, no fake pricing. Keep "Save Me a Cup" as the email signup button.

Real family photos have already been supplied and edited into branding concepts for Early Game Days, Family Trips, Movie Nights, Disney-style memories, and ordinary family moments. Long-term direction: replace the site's stock/generated lifestyle imagery with these real family photos over time — the real photos are what make the brand hard for a generic coffee company to copy.

**Premium polish pass (2026-09-17):** ran two rounds of build prompts through Base44's chat to fix real bugs and push visual polish. Fixed and confirmed live: three dead blank-whitespace section gaps (two of three), brand-statement text contrast (was unreadable pale gray, now legible), tighter section rhythm/spacing, deeper card shadows, richer footer (Explore/Help columns).

**Known open bugs, not launch-blocking, left as-is per Adam's call:**
- The Coming Soon coffee-bag mockup still has "Signature Dark Roast" baked into the image pixels — violates the no-invented-roast-details rule. Base44's chat claimed to regenerate this image twice; it did not actually change (same file both times). Fixing this requires either a true from-scratch image regen or replacing it with a clean mockup + real page-markup "COMING SOON" badge (not baked into the image).
- One dead blank whitespace gap (~230px) still sits between the memory/scrapbook cards section and "THE QUIET TRUTH" brand-statement section. Two separate fix attempts via Base44 chat did not resolve it despite the chat log claiming it was done — Base44's own progress reporting is not reliable evidence of a real fix; always verify on the live published URL (hard-refresh) before trusting its "done" message.

## Product

Ordered a sampler from **Temecula Coffee Roasters (TCR)**. Preference leans bold/dark roast, but the family will taste the samples together and choose before locking any product details. **No final roast name, tasting notes, origin, or price until tasting is done.**

**Dropship inquiry sent (2026-09-17):** submitted TCR's Dropship Inquiry form (temeculacoffeeroasters.com homepage) as Adam Landrum, business email oh4theloveofcoffee24@gmail.com, stating the brand name, website, that samples are already ordered, and that the brand is preparing for a soft launch, plus a request for pricing/label-bag options/Shopify fulfillment setup. Confirmation received twice — TCR's on-page message and a separate email from info@formsubmitapp.com — both saying they'll get back to us. **Status: SUBMITTED — do not resubmit.** Next trigger is TCR's reply or the samples arriving.

**TCR's program, per their own site:** automated SKU-based fulfillment app with order tracking fed to Shopify, fresh roasting, printed-on-demand custom labels, stock bags (Black/White/Kraft/Compostable), a separate wholesale/bulk program, 46+ coffee offerings across 2oz-5lb in whole bean/drip/coarse/fine grind, 9 specialty teas, weekly Zoom Q&A and monthly training, and optional paid design/marketing services. No monthly fees — pay only for coffee sold, no non-refundable shipping deposit. TCR's own stated figures (unverified, their marketing claim, not ours): roughly 15-35% gross margin selling online, 45-60% in-person; soft launch as fast as 48 hours after onboarding for some stores, 45+ days for others.

## Business Email

**oh4theloveofcoffee24@gmail.com** — Adam's dedicated business email for this brand, created 2026-09-17. Use this (not Adam's personal email) for anything sent to TCR, Shopify, or other vendors on the brand's behalf going forward.

## Shopify Store

**Store:** `75f1s2-bj.myshopify.com` — Basic plan, USD, PDT, store contact email is the business email below. Storefront is still password-protected (pre-launch "Opening soon" page), so nothing built here is publicly visible yet.

**Scope decision (2026-09-17, Adam's call, overrides the earlier split below):** Shopify also carries the full storytelling homepage (hero/brand story/Coming Soon/family memories/email capture), not just commerce. This deliberately duplicates what the Base44 site already does — Adam was shown the conflict and chose the full build anyway. Base44 is not retired; the two now overlap and will need a decision later about which is the real public front door.

**What's built (2026-09-17), all on an UNPUBLISHED draft theme:**
- Draft theme **"O For the Love of Coffee - Working Draft"** (`gid://shopify/OnlineStoreTheme/144158785634`), duplicated from the live Horizon theme. **The live theme was never touched** — Shopify's API blocks theme-file writes to the published theme anyway.
- Brand color palette set on the draft: cream `#FBF3E7` (background), coffee brown `#4A2E1F` (foreground/primary buttons), deep navy `#2C3E66` (color1, Adam), muted purple `#7B5E82` (color2, wife). Horizon references these four tokens everywhere, so buttons/inputs/badges/drawers all inherit them from that one change.
- Homepage (`templates/index.json`) rebuilt: hero with the locked tagline + "Our Story" button → brand story section → "COMING SOON / One roast. We're choosing it together." on a navy band → 3-up family-phrase columns → email capture headlined "Join the family before the first roast drops." with the **Save Me a Cup** button → faith line. Default empty product grid removed (no products exist; it rendered as a broken empty row).
- Main menu: Home / Shop / Our Story / FAQ / Contact. Footer menu: Shipping / Returns & Satisfaction Policy / Contact / Search / Your Privacy Choices.
- Four pages created **as drafts** (`isPublished: false`, invisible to visitors): Our Story, FAQ, Shipping (placeholder), Returns / Satisfaction Policy.

**Revision pass (2026-09-17, second round on Adam's exact change list):**
- **Real brand photography now in place.** Adam supplied two finished brand images ("Early Game Days" and "Family Trips") plus the logo. Uploaded all three to Shopify Files via `stagedUploadsCreate` → multipart POST → `fileCreate`: `ofltc-gameday.jpg`, `ofltc-trips.jpg`, `ofltc-logo.png`.
- **Hero fixed.** The "outdoor/camping illustration" was never an uploaded image — Horizon's `sections/hero.liquid` falls back to its built-in `'hero-apparel-1' | placeholder_svg_tag` whenever no `image_1`/`image_2` is set. Setting a real image is the only way to remove it. Hero now uses the Early Game Days photo, height `large`, with a `to top` gradient overlay at `#1A1208B3` so the headline stays readable over a bright, busy photo.
- **Family Trips image — resolved, now placed in its own section.** Initially held back because it has mountains, which Adam had ruled out. His clarification draws the real line: **the mountains are fine as a specific trip memory, but never as the hero or as the brand's main visual identity.** So a new **Family Trips** section sits between the memory columns and the signup — the photo alongside "Same crew. Different adventure." and copy covering road trips, Airbnb mornings, vacations, and coffee before heading out. The memory column's third line was reworded off "road trips / same crew, different adventures" so the travel beat lives in one place instead of two.
- **Standing rule from this:** outdoors imagery is allowed only where it depicts a real, named family memory. The site overall reads family + coffee + memories, never outdoors/hiking/camping coffee.
- **Header logo set** via theme setting `logo` = `shopify://shop_images/ofltc-logo.png`, with `logo_height` 36→56 and mobile 28→44 (a detailed circular badge is illegible at wordmark size). The PNG was given a supersampled circular alpha mask first, so the square white background doesn't sit as a white block on the cream page.
- **Duplicate signup removed.** Horizon's stock footer carried its own "Join our email list / Get exclusive deals" block plus a second email form. Dropped the whole `footer_m9NzUG` section, leaving only copyright + policy list, so the branded "Save Me a Cup" signup is the only one on the page.
- **Fake social links removed.** That footer also shipped `social-links` pointing at facebook.com / instagram.com / youtube.com / tiktok.com / x.com — platform homepages, not real accounts. Cleared rather than left as broken-looking placeholders; re-add when the real accounts exist.
- **Announcement bar** changed from Horizon's stock "Welcome to our store" to "Who's grabbing the coffee?"
- **Purple given real presence** beyond borders: memory-column headings in `#7B5E82` on cream, and the COMING SOON eyebrow in a lightened `#CDB4D4` so it reads against the navy band.
- **Verification method used:** local `md5sum` of each minified file compared against the `checksumMd5` the Theme API reports. `templates/index.json`, `sections/footer-group.json`, and `sections/header-group.json` all matched byte-for-byte; `config/settings_data.json` was hand-assembled so its key order differs, and was verified by reading the live value back instead. Worth reusing — it catches a silent bad-path typo that a `userErrors: []` response won't.

**LAYOUT LOCKED (2026-09-17, Adam's call after reviewing the draft).** The homepage order and content are settled: hero (Game Days photo + tagline) → "Coffee never really was about the coffee." → navy COMING SOON → three memory columns → Family Trips → "Join the family before the first roast drops." / Save Me a Cup / faith line. Adam specifically called out the hero telling the whole story at a glance, and confirmed the Family Trips copy ("Same crew. Different adventure." + the coffee-duty line) reads like family rather than marketing. **Don't restructure this or rewrite that copy without him reopening it** — polish only from here.

**Polish pass (2026-09-17, the four items Adam asked for):**
- Logo up ~18%: `logo_height` 56→66, `logo_height_mobile` 44→52. It was reading small on a phone.
- Hero headline reduced 48px→40px. Done by switching the block off `type_preset: "h2"` to `custom` at `2.5rem`&#8202;—&#8202;**and explicitly setting `font` to `var(--font-heading--family)` at the same time.** Leaving a custom-preset text block on the default `var(--font-body--family)` silently drops it to the body face; that's the trap with this theme's text block. Also switched `wrap` to `balance` so the two sentences split evenly instead of one long / one short.
- The other two items were "keep" instructions — story section and Family Trips copy untouched.

**Deliberately NOT done (and why):**
- **Settings → Brand logo** — separate from the theme header logo above, and Shopify's Admin API cannot write it. Confirmed in Shopify's own docs: the Shop resource is read-only, "only the merchant can update this information from inside the Shopify admin." The header logo is now handled in-theme; Settings → Brand (used by checkout, Shop app, etc.) still needs Adam. (The checkout-page logo *is* API-writable via `checkoutBrandingUpsert` + `fileCreate`, if that's ever wanted.)
- **Privacy Policy / Terms of Service** — `shopPolicyUpdate` has no draft state; writing a policy publishes it instantly at a live public URL. Not appropriate for AI-improvised binding legal text. Correct path is Shopify's own Settings → Policies → "Create from template" generator, then wire the results into the footer menu.
- **Products, prices, SKUs, roast details** — untouched, per the standing rule and the unfinished taste test.
- **Abandoned checkout / marketing email flows** — needs a real product and checkout to configure meaningfully, and is largely dashboard-only.

**Working method — previewing an unpublished theme (banked 2026-09-17):**
- **Dead end, don't repeat:** `https://<shop>.myshopify.com/?preview_theme_id=<id>` — returns a plain-text file reading *"Theme cannot be previewed because it's missing one of these required files: layout/theme.liquid, config/settings_schema.json."* The message is a red herring; both files were verified present and the draft's file list matched the live theme exactly. That URL form is simply not a supported preview route anymore.
- **What works:** the admin theme editor deep link, `https://admin.shopify.com/store/<store-handle>/themes/<numeric-theme-id>/editor`, or Shopify app → Sales channels → Online Store → Themes → the theme → ⋯ → Preview.
- Anonymous fetches of the storefront return the password page, not the theme — expected while the store is pre-launch, and not a sign anything is broken.

## Fulfillment

Shopify as the ecommerce engine. TCR has a Shopify fulfillment connection — customers order through Shopify, TCR roasts/labels/packs/ships. Base44 was originally the branded front-end/story experience with Shopify handling only product, checkout, payment, and order flow — but see the scope decision above, which moved the story content onto Shopify too. Fulfillment not yet connected — waiting on the final roast choice first.

**Pricing target:** ~$20-23 for a 12 oz bag, rough target gross profit ~$6-8/bag before ads and other expenses. Final price waits on the exact all-in cost of the chosen roast.

## Launch strategy

Quiet soft launch first — not launching to unsupportive family members. Start with honest coffee drinkers, local contacts, church/community events, game-day families, samples with QR codes, real customers.

**Marketing angle:** selling the feeling and story, not just beans. Content focus: family mornings, sports, trips, Disneyland days, Christmas traditions, movie nights, inside jokes, sarcastic coffee sayings, "who's grabbing the coffee?" moments.

**Channels under consideration:** Instagram, Facebook, TikTok, TikTok Shop, local events, church/community events, volleyball and football tournaments, QR-code samples, in-person sales. Adam isn't a strong fit for manual day-to-day posting and wants AI to carry as much of that load as possible — post creation, scheduling, captions, simple comment replies, email marketing, abandoned-cart flows, campaign ideas, local outreach lists.

## Trademark

"O For the Love of Coffee" has no obvious exact federal match in searches done so far, but older similar "For the Love of Coffee" marks exist (including abandoned filings and an older registered mark containing that phrase). **Do not assume legal clearance — the brand is NOT formally trademark-cleared.** Do proper clearance before major packaging/ad spend, and consider filing both a word mark ("O FOR THE LOVE OF COFFEE") and a logo mark once cleared.

## Automation

Grok/Chief is already managing the project skeleton — no extra bots needed right now. Chief coordinates marketing, social content, expenses, launch checklist, and deadlines. Owner also uses Jarvis and Claude, which have proven out browser/admin automation (e.g. the TCR inquiry submission). **Standing workflow: Adam makes the decisions, AI handles repetitive admin/execution, Adam steps in only for approvals, legal verification, passwords, payments, signatures, or other sensitive decisions.** Jarvis's role here: keep this note current, don't invent new branding directions/bots/products/prices/features unless asked, don't overbuild, help keep the project organized and moving one step at a time. While waiting on TCR's reply and the samples, don't manufacture busywork just to stay active.

## Launch Checklist

- [ ] TCR onboarding (dropship/wholesale relationship set up) — inquiry sent 2026-09-17, awaiting TCR reply
- [ ] Choose roast (family taste test)
- [ ] Business ownership decision (sole prop / LLC / partnership etc. — Adam's call, no filing without approval)
- [ ] EIN — online path exhausted (VPS IP block, then IRS Assistant kickout to paper); Form SS-4 by fax is the next step, TABLED 2026-09-17 (not to be filed without Adam's approval — see Business Setup section below)
- [ ] DBA / FBN (not to be filed without Adam's approval)
- [ ] Local business license (not to be filed without Adam's approval)
- [ ] California seller's permit, if required (not to be filed without Adam's approval)
- [ ] Business bank account
- [ ] Bookkeeping / expense tracking set up
- [ ] Insurance needs finalized
- [ ] Shopify store structure — draft theme, homepage, menus, and draft pages built 2026-09-17; still needs Adam's preview/approval, the Brand logo upload, and generated Privacy/Terms policies
- [ ] Shopify connection (product/checkout/payment, tied to TCR fulfillment)
- [ ] Test order (end-to-end order placed and received before real customers)
- [ ] Trademark clearance and filing (word mark + logo mark)
- [ ] Social accounts set up (Instagram, Facebook, TikTok, TikTok Shop)
- [ ] Soft launch

## Business Setup — EIN

Structure confirmed for the EIN application: **sole proprietorship** (Adam personally, no state filing needed first — fastest path; can convert to an LLC later if wanted for liability protection, which would need its own new EIN at that point).

**Free, direct from the IRS — apply at irs.gov's "Get an employer identification number" page.** Never pay a third-party site for this. Available Mon-Fri, 7am-10pm Eastern; must be completed in one sitting (no save-for-later), and you get the EIN immediately on approval.

**Jarvis/Claude cannot complete this application** — it requires entering the responsible party's Social Security number, and entering an SSN into any form is off-limits categorically, no exception even with Adam's go-ahead. This is Adam's step alone.

**Real gotcha hit 2026-09-17 (VPS attempt):** attempting to load the IRS EIN online tool through this VPS's browser hit the IRS's own "system is experiencing technical difficulties" page — not a real outage (mid-day Thursday, within service hours). Almost certainly the IRS blocking the VPS's datacenter/hosting IP as anti-fraud. **Fix: always apply from a normal home/mobile connection on Adam's own device, never through the VPS.**

**Second attempt 2026-09-17, from Adam's own device/network — different, final wall:** the IRS Online EIN Assistant returned "We apologize for the inconvenience but based on the information provided we are unable to provide you with an EIN through this online assistant. You must submit a Form SS-4 by fax or mail." This is a known IRS Assistant kickout (happens for various benign reasons, not necessarily anything wrong with the application) — the online path is closed for this attempt; **paper Form SS-4 is now the only route.**

**TABLED 2026-09-17 per Adam's call — resume when he's ready.**

**Paper filing path (Form SS-4):**
- Download: https://www.irs.gov/pub/irs-pdf/fss4.pdf
- **Fax (fastest, ~4 business days): 855-641-6935**
- Mail (~4 weeks): Internal Revenue Service, Attn: EIN Operation, Cincinnati, OH 45999
- Never pay a third-party site for this — direct to IRS only.

**Prep answers ready to transcribe onto the form (no SSN or address included — Adam fills those, plus signature, himself):**
- Line 1, Legal name: Adam Landrum
- Line 2, Trade name: O For the Love of Coffee
- Line 4a/4b, mailing address: Adam fills in
- Line 6, county/state: Adam's county, California
- Line 7a, responsible party: Adam Landrum
- Line 7b, SSN of responsible party: **Adam fills in by hand — Jarvis/Claude never touches this field, no exception**
- Line 8a, LLC?: No
- Line 9a, entity type: Sole Proprietor
- Line 10, reason for applying: Started new business
- Line 11, date business started: Adam's call
- Line 12, closing month of accounting year: December
- Line 13, expected employees: 0
- Line 16, principal activity: Retail
- Line 17, principal line/product: Coffee
- Line 18, applied for EIN before: No
- Signature section (name/title, phone, signature, date): Adam, by hand

## Status (as of 2026-09-17)

- Brand concept, tagline, logo direction: **locked**
- Base44 website: **built, being polished**
- Shopify store: **structure built on an unpublished draft theme 2026-09-17** — homepage, menus, and four draft pages done; nothing published, no products, logo and legal policies still on Adam
- TCR samples: **ordered, in transit**
- Shopify/TCR fulfillment plan: **chosen, not yet connected**
- Final roast: **not chosen** — waiting on family tasting
- Final price: **not chosen** — waiting on roast cost
- EIN: **tabled** — online application dead-ended twice (VPS IP block, then IRS Assistant kickout requiring paper Form SS-4); fax/mail path documented above, resume when Adam's ready.
- **Next step:** wait for samples, taste as a family, choose the winning coffee, connect that product to Shopify, prep soft launch. EIN via paper SS-4 fax whenever Adam picks it back up.
