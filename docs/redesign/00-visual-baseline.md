# Phase A — the visual baseline

What the three surfaces look like today, measured rather than asserted. Every screenshot named here was taken
by `tools/visual/capture.mjs` from a dev server running this branch against a locally seeded database, and
every number was counted by a script in this repository. Nothing in this document is an impression.

- Rails baseline: `claude/practical-thompson-9xfqed`, deployed commit `236b3dd8`.
- Flutter baseline: `fullstackfull/lynomia-chat-app98` at `9795827`, 36 Dart files, 19,359 lines.
- Evidence: `docs/redesign/evidence/before/` — 48 marketing shots (12 pages × ar/en × mobile/desktop),
  7 dashboard shots.

---

## 1. The three identities the product currently has

There is no shared visual identity. There are three, and they disagree on the primary colour.

| Surface | Background | Primary | Accent | Where it is defined |
| --- | --- | --- | --- | --- |
| Marketing website | white | `woot-700` `#2870bd` | none | Tailwind utilities in `custom/app/views/marketing/**` |
| Dashboard sidebar | navy radial gradient `#0d2148 → #07101f` | `#db2777` (pink) | pink | 400 lines of scoped CSS in `Sidebar.vue` |
| Dashboard body | `n-background` (light) | `n-brand` `#2781F6` | — | `theme/colors.js` |
| Flutter app | `#F8FAFC` / `#0F172A` | `#6366F1` (indigo) | `#818CF8` | `lib/shared/styles/themes.dart` |

A customer who reads the website, signs in, and then opens the phone app sees three products. The brief's
"unified visual identity (electric blue, royal blue, indigo, restrained pink/magenta)" is not a new palette to
invent — it is the union of what already exists, made deliberate instead of accidental.

**One finding worth naming separately.** `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
carries roughly 400 lines of hand-written scoped CSS: radial and conic gradients, four bespoke pink custom
properties, and its own elevation scale. The repository's own rule is *"Do not write custom CSS. Do not use
scoped CSS. Do not use inline styles. Always use Tailwind utility classes."* The one place the product
reached for a premium look is the one place that left the design system, and the result is the only pink in
the product.

---

## 2. Why the old static page reads better than the current homepage

Both are real and both are in this repository. The old page is
`docs/official-website/hotfix/screenshot-ar-desktop.png`; the current one is
`docs/redesign/evidence/before/marketing/ar/desktop/home.png`. Five differences, in the order they matter.

**2.1 The old hero has a subject; the new one has none.** The old page opens with a tilted browser frame
showing a real conversation list — Arabic contact names, WhatsApp and Instagram channel badges, a message
preview. It shows you the product. The new hero is a headline, a paragraph and two buttons on white, with the
left 40% of a 1440px viewport empty. There is not one image on the entire 3,067px page.

**2.2 The old page has a second colour.** A magenta block sits behind *بصندوق واحد* in the headline — the
phrase the whole proposition turns on. It gives the eye somewhere to land and gives the brand something
besides "blue links". The new page uses exactly one hue, on buttons and links only.

**2.3 The old page has depth.** Three floating pill badges overlap the browser frame, each with a coloured
icon dot. The new page is uniformly flat: one border colour, no shadow, no overlap, no layering anywhere.

**2.4 Hierarchy comes from form, not only size.** The old page gives its three statistics a band of their
own. The new page prints `9 / 50+ / API` as three bare numbers in the same column as the body text, below
the buttons, where they read as a caption.

**2.5 Composition.** The old hero is a two-column asymmetric layout — headline on the right, product on the
left, which is the correct reading order for Arabic. The new hero is a single text column, so the page opens
with nothing to look at.

### What the current site does better, and must not be lost

The old page was a hand-edited static file that could not be reviewed, translated, tested or rolled back. The
current site is 96 CMS-backed pages across two locales with canonical URLs, hreflang, breadcrumbs, structured
data and a sitemap. It is also markedly **more honest**: every channel card states what you must supply
(*"تحتاج إلى: حساب واتساب للأعمال"*) and flags what is not ready (`يحتاج إعدادًا`, `تجريبي`). That honesty is
a product asset and the redesign keeps every word of it.

The brief's instruction stands: recover the old page's visual strengths, do **not** revert the architecture.

---

## 3. What is actually wrong with the current site, beyond the missing hero

Counted from the 48 screenshots, not guessed.

| # | Problem | Evidence |
| --- | --- | --- |
| 1 | The hero is not a hero. `_page.html.erb` renders `h1` + lede; the `hero` section renders only kicker + buttons, so the eyebrow prints *below* the standfirst. | `custom/app/views/marketing/shared/_page.html.erb`, `sections/_hero.html.erb` |
| 2 | Three consecutive sections use the same bordered white card in the same 3-column grid. No section is distinguishable from another at a glance. | `ar/desktop/home.png` |
| 3 | Zero images on any of the 96 pages. The `image` section type exists and is used nowhere. | `Marketing::SectionSchema::TYPES` |
| 4 | Arabic mobile home is 11,828px of undifferentiated cards with no anchor to orient against. | `ar/mobile/home.png` |
| 5 | The wordmark renders `Chat Lynomia` left-to-right inside an RTL header, so the Arabic page reads the brand backwards. | `shared/_header.html.erb` |
| 6 | The closing CTA is a flat blue rectangle — the only coloured surface on the page, spent on the least interesting block. | `shared/_cta.html.erb` |
| 7 | The type scale is `text-3xl/4xl` for h1 and `text-lg` for the lede, with no display size anywhere. Nothing on the page is set larger than a heading in the dashboard. | all 48 |
| 8 | No motion of any kind, including on focus and hover beyond a background tint. | `entrypoints/marketing.js` loads no JS at all |

Items 1, 5 and 6 are structural and are fixed in Phase C. Items 2, 3, 4, 7 and 8 are what the design
direction has to answer.

---

## 4. Feature-preservation baseline

The brief forbids removing, breaking or hiding any existing dashboard feature. That needs a number, not a
promise.

`bin/dashboard-route-inventory` enumerates every named Vue route and marks whether the sidebar or the go-to
command palette names it. Today:

- **136 named routes** across 37 route tables.
- **92 of them** are reachable from the sidebar or the command palette; the remaining 44 are detail and child
  routes reached from inside a page (a conversation, a contact, an inbox's channel step).

The baseline is committed at `docs/redesign/inventory/dashboard-routes.txt`. The same command re-run after
any dashboard change must produce a file whose diff contains no deleted line. A deleted route is a removed
feature; a route that loses its `menu` marker is a feature that still answers but can no longer be found.

Super Admin is explicitly out of scope and is not in this inventory.

---

## 5. Backend → mobile parity

Direction of integration is **backend → mobile only**. No Flutter feature, module, screen or business rule is
copied into the Rails project, and no endpoint is invented: every row below was read out of the Dart source
and matched against this repository's route table.

The Flutter app is an **end-customer** app — a person talking to a business — not an agent console. It has
11 screens: splash, login, inbox selection, conversations list, chat, plan selection, payment, payment
history, API documentation, privacy, about.

| What the app calls | Rails side | State |
| --- | --- | --- |
| `POST /public/api/v1/inboxes/{id}/contacts` | Chatwoot public API | exists |
| `GET/POST /public/api/v1/inboxes/{id}/contacts/{cid}/conversations` | Chatwoot public API | exists |
| `GET/POST …/conversations/{id}/messages` | Chatwoot public API | exists |
| `POST /api/v1/mobile/auth/google` | `custom/app/controllers/api/v1/mobile/auth_controller.rb` | exists, Lynomia-specific |
| `POST /api/v1/mobile/auth/apple` | same controller | exists, Lynomia-specific |
| `GET /api/v1/accounts/:id/billing/plans` | `custom/app/controllers/api/v1/accounts/billing_controller.rb` | exists |
| `GET /api/v1/accounts/:id/billing/entitlements` | same | exists |
| `POST /api/v1/accounts/:id/billing/checkout` | same | exists |
| `POST /api/v1/accounts/:id/billing/portal` | same | exists |
| `GET /mobile/billing/return` | `custom/app/controllers/mobile/billing_returns_controller.rb` | exists |
| `POST /api/v1/notification_subscriptions` | Chatwoot core | exists |
| `https://lynomia.com/api/...` (5 endpoints) | **not this repository** | external service |

Two things the parity matrix shows that matter for the redesign:

1. The app already consumes this backend's own billing and mobile-auth endpoints, so the plan, entitlement
   and payment screens can show real plan names and limits rather than hard-coded copy.
2. Five calls go to `lynomia.com`, which is a different service. Nothing in Phase E may assume those are ours
   to change.

---

## 6. How screenshots are taken

`node tools/visual/capture.mjs --set marketing --out <dir>` with `bin/rails s -p 3000` and `bin/vite dev`
running. Sets: `marketing` (12 pages × ar/en × mobile/desktop) and `dashboard` (7 pages, signed in through
the real login form).

The dashboard set runs against **locally seeded data only** — `rails db:seed` plus `Seeders::AccountSeeder`.
There is no customer conversation, contact, address or token in any committed image, and the set must never
be pointed at a production host.
