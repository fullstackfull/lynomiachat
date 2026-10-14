# 01 — Current state audit: chat.lynomia.com

**Date:** 2026-10-14 · **Branch:** `claude/practical-thompson-9xfqed` · **Repo base:** `lynomia-custom @ aa27e6f7`
**Live host audited:** `https://chat.lynomia.com` (read-only `GET` only; nothing on the server was changed)

## Method, and how to re-verify

Every statement below was measured, not inferred. Live facts come from HTTP `GET`/`HEAD` against the public host
and from a byte-identical copy of the served homepage (100,208 bytes, fetched 2026-10-14 13:40 UTC). Repository
facts come from `git`-tracked files at `aa27e6f7`, cited as `path:line`. Where a fact can only be settled by
reading the production server, it says **NOT ESTABLISHED** and names the probe a human must run.

Two rules were applied throughout, because this audit contradicts assumptions in both directions:

1. **The repository is not evidence about production, and production is not evidence about the repository.**
   Section 10 lists four places where they actually diverge.
2. **A reachable URL is not a working feature.** A Vue single-page app returns `200` for routes whose
   underlying capability is disabled, so route probing was always paired with a configuration check.

---

## 1. Where the official website actually lives — the finding that reframes everything

**The website is a hand-maintained static HTML file on the production server. It is in no repository, it is not
rendered by Rails, and it shadows the application at `/`.**

### 1.1 Proof that `/` is a static file

```
HTTP/2 200
server: nginx/1.24.0 (Ubuntu)
content-type: text/html
content-length: 100208
last-modified: Sat, 12 Sep 2026 13:57:29 GMT
etag: "6aa55a49-18770"
accept-ranges: bytes
```

nginx derives a static-file ETag as `hex(mtime)-hex(size)`. Here `0x18770 = 100208`, which is exactly
`content-length`, and `last-modified` plus `accept-ranges: bytes` complete the signature. A Rails response on
this stack carries none of that; it carries `x-request-id` and `x-runtime`, and the contrast is measurable on
the same host in the same second:

| Request | `x-request-id` / `x-runtime` present | Conclusion |
|---|---|---|
| `GET /` | **0 of 2** | served from disk by nginx |
| `GET /features` | **2 of 2** (`x-runtime: 0.006251`) | served by Rails |

`GET /index.html` returns a **different** file: the stock "Welcome to nginx!" page, 615 bytes,
`last-modified: Tue, 11 Apr 2023`, `etag: "6434bbbe-267"`. So nginx's `index` directive resolves `/` to a
differently-named file in the same docroot, and the default welcome page remains publicly reachable.

### 1.2 Proof it is in no repository

- `grep -rl` for the live hero headline `كل محادثات عملائك` across the working tree, including
  `--include=*.html --include=*.erb --include=*.vue --include=*.yml --include=*.json`: **no tracked file matches.**
- `git ls-files public/index.html` → **0**. `.gitignore` ignores `public/uploads`, `public/packs*`,
  `public/vite*` and some asset globs (`.gitignore:33-43,79-80,87`) — but not a root `index.html`, so the file's
  absence is real absence, not an ignore rule.
- The other repository in scope, `fullstackfull/lynomia-chat-app98`, is a **Flutter mobile app** (`pubspec.yaml`,
  `android/`, `ios/`, `lib/`) — not the website.
- `deployment/nginx_chatwoot.conf` is the stock Chatwoot template: `server_name chatwoot.domain.com`
  (`:14`, `:26`), a single `location /` proxying to `127.0.0.1:3000` (`:33-50`), **no `root`, `index` or
  `try_files`**. The configuration that makes `/` static therefore exists only on the server.

### 1.3 What this costs today

| Consequence | Why |
|---|---|
| No review, no history, no rollback | the file is outside version control |
| No tests, no CI | nothing can assert anything about it |
| No translation workflow | copy is hard-coded twice inside one file (§8) |
| **A deploy that rewrites the nginx vhost deletes the website** | the shadowing `location`/`index` directive is not reproducible from the repo |
| Nobody but a server operator can change a word | there is no CMS, by construction |

### 1.4 What Rails already owns on the same host

| Path | Live result |
|---|---|
| `/app`, `/app/login`, `/app/register` | 200 (SPA shell: 10,193 / 9,008 / 10,193 bytes) |
| `/docs` | 302 → `/hc/lynomia-docs` → `/hc/lynomia-docs/en` |
| `/changelog` | 302 → `/hc/lynomia-changelog` |
| `/super_admin` | 302 → `/super_admin/sign_in` |
| `/health` | 200 |
| `/robots.txt` | 200, Rails-rendered (`app/controllers/robots_controller.rb`) |
| `/sitemap.xml` | **404** — no site-wide sitemap exists |
| 34 of 36 other probed marketing paths | **404**, Rails error page, 3,378 bytes, **English only** |

So the host is already a hybrid, and every marketing URL the rebuild needs is **free** (`/features`, `/pricing`,
`/about`, `/contact`, `/demo`, `/support`, `/solutions`, `/integrations`, `/channels`, `/faq`, `/blog`,
`/privacy`, `/terms`, `/security`, `/status`, `/sitemap.xml`, `/en`, `/ar` — all 404 today).

---

## 2. The page as a visitor sees it

`lang="ar" dir="rtl"`, `<title>Lynomia Chat — كل محادثات عملائك بصندوق واحد</title>`. Six `<section>`s,
1 `<h1>`, 8 `<h2>`, 9 `<h3>`. All CSS inline in two `<style>` blocks; two `<script>` blocks; **two `<img>`**,
both hot-linked from a different domain (`https://lynomia.com/img/navbar/chatlogo.png`,
`https://lynomia.com/img/new/lynomia-icon.png`). Every other visual is inline CSS/SVG.

**Navigation is anchor-only.** Nav: `#channels`, `#whatsapp`, `#ai`, `#features`, `#reports`, `#security`,
`#cta`. The entire site is therefore **one indexable URL**. The only real outbound hyperlink in the whole
document is `/app/login` (`home.html:428`).

**Footer promises four pages that do not exist as pages:** `#about`, `#privacy`, `#deletion`, `#terms`
(`home.html:856-860`). None has a matching element id; their bodies live as **JavaScript string literals**
(`home.html:872-911` Arabic, `:953-989` English, `:993-1032` an Arabic duplicate) rendered into a modal. With
JavaScript disabled, nothing renders at all.

---

## 3. Three defects that break the funnel — all live right now

### 3.1 BLOCKER — the page promises a free trial and offers no way to start one

The CTA hint reads `تجربة مجانية · بدون بطاقة ائتمانية · دعم بالعربي` (`home.html:784`) and the hero button
`جرّبها مجانًا` points at `href="#cta"` (`home.html:440`) — an in-page anchor. Meanwhile:

- `GET /app/register` → **200**, and production has **`"ENABLE_ACCOUNT_SIGNUP":true`** (measured in the
  `window.globalConfig` blob the live app shell serves at `/app/login`).
- Occurrences of `app/register` anywhere in the marketing page: **0**.

**A working self-service signup exists in production and the marketing page never links it.** Every visitor who
wants to act on the page's own call to action is sent to a sign-in form for an account they do not have.

### 3.2 BLOCKER — the "live chat" sends nothing, while claiming a human is waiting

The primary CTA and the footer's `شات مباشر` both call `toggleWidget(true)` (`home.html:781`, `:1044`). The
widget's `sendW()` appends a canned reply from a client-side table (`home.html:1253-1265`, strings at `:1189`,
`:1193`). A no-exclusion grep of the served file for `fetch(`, `XMLHttpRequest`, `WebSocket`, `mailto:`, `tel:`
and `wa.me` returns **zero hits** — so the file contains no mechanism of any kind for reaching Lynomia.

While sending nothing, the widget states `فريق لنوميا متصل — متوسط الرد: دقيقتين` ("Lynomia's team is online —
average reply: two minutes", `home.html:1059`), shows a hard-coded unread badge of `1` (`:1073`), and claims
`هذا نفس الويدجت اللي بينركّب على موقعك` ("this is the same widget that gets installed on your site", `:1062`)
— which it is not. The page's only contact detail, `info@lynomia.com` (`:1043`), is a plain `<span>` with no
`mailto:`.

### 3.3 BLOCKER — the Arabic page force-flips itself to English on every load

```js
const langBtn = document.getElementById('langBtn');   // home.html:936
if (langBtn) { langBtn.click(); }                      // home.html:937-938
```

The button's handler is `setLang(cur==='ar'?'en':'ar')` with `cur` initialised to `'ar'`
(`home.html:426`, `:869`), and `setLang` rewrites `lang`, `dir`, the `<title>` and every `data-i` string
(`:1223-1226`). So on an Arabic-first product aimed at an Arabic-speaking market, every visitor sees Arabic
paint and then flip to English, with the text direction changing under them. `localStorage` is written but never
read to choose the initial language (`:1233`). Crawlers index the Arabic server response; humans read English.

---

## 4. Claims audit — what the page asserts, and what survives verification

Claims were extracted exhaustively from the page and then checked against the codebase; the full verification
table with per-claim citations is **`02-verified-feature-inventory.md` §6**. The summary of what must change:

| Claim on the page | Line | Verdict |
|---|---|---|
| `uptime · last 90 days` → `99.98%` | `home.html:768` | **Fabricated.** No uptime measurement, no SLA, no status page exists; `/status` and `/uptime` are 404. The single most dangerous line on the site. |
| `backups · daily 03:00` → `done` | `:767` | **Unsubstantiated as "daily".** What exists is a verified `pg_dump` taken *before each deployment*, last 14 retained (`deployment/deploy.sh:36`, `:126-130`, `:214-224`, `:449-450`). No backup cron exists — 0 hits for backup/`pg_dump` in `config/schedule.yml`. |
| `encryption · TLS 1.3 + AES-256` → `active` | `:766` | **Overstated.** TLS and HSTS are real; the shipped template permits TLS 1.2 as well (`deployment/nginx_chatwoot.conf:54`). "AES-256 at rest" covers **credential columns only** (22 `encrypts` attributes), not messages, conversations, contacts or attachments. |
| `monitoring · security & health` → `24/7` | `:769` | **Not established.** The internal console states it is *not* infrastructure monitoring (`custom/app/controllers/super_admin/operations_controller.rb:4-6`). No evidence of a staffed rota. |
| "an audit log for **every action**… for governance and compliance" | `:754`, `:758` | **Refuted by Lynomia's own documentation**: `custom/db/documentation/en/administration/audit-logs.md` tells customers that replying, resolving, labelling and running macros leave no entry. |
| `تجربة مجانية · بدون بطاقة ائتمانية` (free trial, no card) | `:784` | **Not deliverable as written.** No `BillingPlan` row exists anywhere in the repo, `BILLING_TRIAL_PLAN_ID` defaults to nil (`custom/app/models/billing/settings.rb:13`). See §4 of doc 02. |
| The whole status panel presented as a **live readout** | `:763-770` | Static HTML styled with pulsing green dots (`home.html:305`). Even with corrected values, the live-status framing is a misrepresentation and must go. |
| AI section: `ردود آلية بالذكاء الاصطناعي 24/7` ("AI auto-replies 24/7") | `:448`, `:546`, `:590` | **Materially false today.** There is no AI assistant or bot product; what exists is five agent-assist LLM actions, gated by an account flag that is **off by default** and an LLM credential that must be configured. Full trace in doc 02 §3. |

No certification badge of any kind appears on the page (no SOC 2, ISO, GDPR, PCI, HIPAA) — correctly, since none
is held. **None may be added.**

---

## 5. SEO state of the served page

| Element | Present? | Evidence |
|---|---|---|
| `<title>` | yes | `home.html:6` |
| `meta name="description"` | **no** | the document contains exactly two `<meta>` tags, `:4-5` |
| `rel="canonical"` | **no** | 0 hits |
| `hreflang` | **no** | 0 hits |
| Open Graph / Twitter cards | **no** | 0 hits — no share card on any platform |
| JSON-LD structured data | **no** | 0 hits |
| `rel="icon"` / manifest / `theme-color` | **no** | 0 hits; `GET /favicon.ico` → 404 |
| Indexable URLs | **1** | anchor-only navigation |
| In a sitemap | **no** | `/sitemap.xml` → 404; `robots.txt` advertises only the three `/hc/` sitemaps |
| 404 page | unbranded | 3,378-byte Rails default, **English only**, on an Arabic-market site |

### 5.1 The documentation SEO precedent — strong on articles, absent on the landing page

Measured live. A documentation **article** (`/hc/lynomia-docs/articles/welcome-to-lynomia-chat`, 200) carries
`rel="canonical"`, `hreflang` for `ar`/`en`/`x-default`, `og:type|url|title|description`, and JSON-LD
`BreadcrumbList` + `TechArticle` + `Organization`. The portal **landing** page (`/hc/lynomia-docs/en`, 200,
95,480 bytes) carries **none** of them — a case-insensitive scan of the whole document for
`canonical|hreflang|og:title|ld+json` returns **0 matches**.

This is a known, recorded gap: `app/views/public/api/v1/portals/sitemap.xml.erb:13-17` states that
`rel="canonical"` appears in exactly two templates and `portals/show.html+documentation.erb` is neither. The
marketing site must follow the **article** pattern and must not inherit the landing-page gap.

### 5.2 A tenant Help Center is advertised to crawlers from the platform host

`robots.txt` as served ends with three `Sitemap:` lines, one of which is a **tenant** portal:

```
Sitemap: https://chat.lynomia.com/hc/ddf1/sitemap.xml
Sitemap: https://chat.lynomia.com/hc/lynomia-docs/sitemap.xml
Sitemap: https://chat.lynomia.com/hc/lynomia-changelog/sitemap.xml
```

`/hc/ddf1/en` → 200, `<title>ddf1</title>`, **0 article links**; its sitemap contains **1 URL**. So an empty,
test-named tenant Help Center is publicly indexable under the Lynomia brand and is being advertised in the
platform's own `robots.txt`. The mechanism is `RobotsController#sitemap_lines`, which enumerates
`Portal.where(archived: false)` with no platform filter (`app/controllers/robots_controller.rb:77-83`), while
`PublicController#ensure_portal_feature_enabled` is inert on this fork because it early-returns unless
`ChatwootApp.chatwoot_cloud?`, and `ChatwootApp.enterprise?` is hard-coded `false`
(`app/controllers/public_controller.rb:22-27`, `lib/chatwoot_app.rb:19-21`). Severity: **HIGH** — brand quality
and crawl budget, with a tenant's existence disclosed on the platform's marketing host.

---

## 6. Performance signals

Measured without a browser; no Core Web Vitals field data is available, so nothing below is a CWV claim.

| Signal | Value |
|---|---|
| HTML transferred | **100,208 bytes**, uncompressed on the wire for this request |
| CSS | 100% inline, two `<style>` blocks — no cacheable stylesheet |
| JS | two inline `<script>` blocks, including all four legal documents as string literals |
| External origins | 3 — `fonts.googleapis.com`, `fonts.gstatic.com` (`preconnect`, `home.html:7-9`), `lynomia.com` (images) |
| Render-blocking | the Google Fonts stylesheet (`:9`); fonts are `preconnect`ed but not `preload`ed |
| Images | 2, both cross-origin PNGs with no `width`/`height`/`loading` attributes |
| Caching | `last-modified`/`etag` only; no `cache-control` header on the HTML |

The repository's own build also carries a measured warning worth noting for the rebuild: the Vite production
build emits `DashboardIcon-*.js` at **15,954 kB** (gzip 4,385 kB) and `dashboard-*.js` at 3,444 kB. Marketing
pages must not load the dashboard bundle; they need their own entrypoint.

---

## 7. Accessibility and RTL

Good: `prefers-reduced-motion` is honoured (`home.html:51-54`), `:focus-visible` has a visible 3px outline
(`:49`), a `.flip` utility neutralises icon mirroring in LTR (`:50`), and colour tokens are defined centrally
(`:12-40`).

Problems: **no landmark elements** and no skip link; the heading outline is driven by visual order rather than a
single document hierarchy; the two images' alt text and the inline SVG decorations carry no `aria-hidden`
discipline; the simulated chat widget is a `div`-based control opened by `onclick` with no ARIA dialog semantics,
no focus trap and no keyboard dismissal; and the four legal "pages" are injected into a modal, so a keyboard or
screen-reader user cannot reach a stable document. `lang`/`dir` are correct **until** the forced flip in §3.3
changes both without the user asking.

---

## 8. Internationalisation — there is no English site

| Probe | Result |
|---|---|
| `/en`, `/en/`, `/en.html`, `/index-en.html` | **404** |
| `/?lang=en` | 200, **byte-identical** 100,208-byte Arabic file |
| `/ar` | **404** |

Both languages exist only as `data-i` string tables inside the one file, swapped client-side. There is no
per-language URL, so neither language can be linked, shared, canonicalised, `hreflang`-paired or indexed
separately — and the Arabic version is the one a crawler sees while the user is flipped to English.

The product itself is already bilingual at the data layer: the documentation corpus ships `LOCALES = %w[en ar]`
(`custom/app/services/documentation/library.rb:14`) with per-locale resolution, and the app has working
`lang`/`dir` helpers (`app/helpers/portal_helper.rb:40-42`,
`app/helpers/text_direction_helper.rb:12,20-22`). The website is the only part of the system that is not
properly bilingual.

---

## 9. Legal and platform-review exposure

The four legal documents — `من نحن`, `سياسة الخصوصية`, `حذف البيانات`, `شروط الاستخدام` — have **no URL of
their own**. They are JS string literals behind dead anchors (§2). Yet their text contains an explicit **Google
API Limited-Use disclosure** (`home.html:884`, `:964`) and **Meta/Gmail integration terms** (`:893`, `:973`).

Platform app review (Meta, Google) requires stable, publicly loadable privacy-policy and data-deletion URLs. A
`#hash` on a JS-rendered page does not satisfy that, and with JavaScript off there is no text at all.

**The same four documents already exist as real pages on the corporate domain**: `lynomia.com/privacy` (200,
16,886 B), `/terms` (200, 18,266 B), `/about_us` (200, 7,570 B), `/user-data-deletion` (200, 10,703 B). So the
content exists; only `chat.lynomia.com` lacks addressable copies.

---

## 10. Repository ↔ production divergences (four, all measured)

These matter because each one invalidates a conclusion drawn from one side alone.

| # | Divergence | Evidence | Consequence |
|---|---|---|---|
| D1 | **Self-service signup is ON in production, OFF in the repo** | live `window.globalConfig` → `"ENABLE_ACCOUNT_SIGNUP":true`; repo ships `value: false` (`config/installation_config.yml:73-77`) | signup works today; the marketing page's trial promise is reachable **as a signup**, though no plan row exists to bill it (doc 02 §4) |
| D2 | **`BRAND_URL` and `WIDGET_BRAND_URL` point at a hostname that does not exist** | production config → `https://www.chat.lynomia.com`; `getent hosts www.chat.lynomia.com` → **no A record**; HTTPS connect fails | every "Powered by Lynomia Chat" link — in emails, the chat widget and the documentation portal footer (`app/views/public/api/v1/portals/documentation_layout/_footer.html.erb:24` via `app/helpers/portal_helper.rb:89-98`) — is **broken in production**. BLOCKER-class, trivially fixable by dropping `www.` |
| D3 | **Terms and Privacy links on the login/signup screens point at dead anchors** | production config → `TERMS_URL: https://chat.lynomia.com/#terms`, `PRIVACY_URL: .../#privacy`; those ids do not exist in the page (§2); consumed at `app/javascript/v3/views/login/Index.vue:338,345,481,489` and `.../signup/components/Signup/Form.vue:54,57` | users cannot read the terms they are asked to accept. Compliance-relevant |
| D4 | **`SUPPORT_URL` is empty in production** | production config → `"SUPPORT_URL":""` | support links are hidden in the dashboard by design when blank (`app/javascript/shared/composables/useBranding.js:9-14`), so in-product "contact support" entry points are currently absent |

Also recorded: the merge authorized earlier today (`aa27e6f7`) is **not deployed**, so live behaviour reflects an
earlier release. Deployed documentation is real and substantial — `/hc/lynomia-docs/en` lists 75 articles and its
sitemap has 164 URLs; the changelog has 6 — so the marketing site **can** link to `/docs` and `/changelog` today.

---

## 11. Findings, ranked

| # | Severity | Finding |
|---|---|---|
| F1 | **BLOCKER** | The website is an unversioned static file shadowing Rails at `/`; an nginx rewrite deletes it (§1) |
| F2 | **BLOCKER** | Trial promised, signup never linked, although signup is enabled in production (§3.1) |
| F3 | **BLOCKER** | The "live chat" sends nothing while claiming a human is online; no `mailto:`, `tel:` or `wa.me` anywhere (§3.2) |
| F4 | **BLOCKER** | Arabic page force-flips to English on every load (§3.3) |
| F5 | **BLOCKER** | Fabricated live-status panel: 99.98% uptime, daily backups, AES-256 at rest, 24/7 monitoring (§4) |
| F6 | **BLOCKER** | AI section claims a product that does not exist in a sellable state (§4, doc 02 §3) |
| F7 | **HIGH** | `BRAND_URL`/`WIDGET_BRAND_URL` point at a non-resolving host — every "Powered by" link is broken (§10 D2) |
| F8 | **HIGH** | No meta description, canonical, hreflang, OG, Twitter card, JSON-LD or favicon (§5) |
| F9 | **HIGH** | One indexable URL; 34 of 36 marketing paths 404 with an unbranded English error page (§1.4, §5) |
| F10 | **HIGH** | Legal and data-deletion documents have no URLs, breaking platform-review requirements (§9) |
| F11 | **HIGH** | A tenant Help Center (`ddf1`) is publicly indexable and advertised in the platform `robots.txt` (§5.2) |
| F12 | **HIGH** | No English site at all; language is a client-side swap with no URL (§8) |
| F13 | **MEDIUM** | Terms/Privacy links on login and signup point at dead anchors (§10 D3) |
| F14 | **MEDIUM** | The documentation portal landing page emits no canonical/hreflang/OG/JSON-LD (§5.1) |
| F15 | **MEDIUM** | 100 KB of uncacheable inline HTML/CSS/JS; cross-origin hot-linked images; no `cache-control` (§6) |
| F16 | **MEDIUM** | No landmarks, no skip link, modal legal content with no dialog semantics (§7) |
| F17 | **MEDIUM** | Stock nginx welcome page publicly reachable at `/index.html` (§1.1) |
| F18 | **LOW** | `SUPPORT_URL` empty, hiding in-product support links (§10 D4) |

## 12. What is NOT established

1. The **production nginx configuration** and the **filesystem path** of the static homepage. Probe: read the
   live vhost and docroot on the server. Everything in §1 is derived from response headers, which prove the
   *behaviour* but not the file's location.
2. Whether `www.chat.lynomia.com` is *intended* to exist (DNS could be added instead of changing the config).
3. **Core Web Vitals field data** — no RUM source was available; §6 is a static analysis.
4. Whether host-level disk or database encryption and host-level scheduled backups exist outside this
   repository. If they do, they are hosting facts and must be worded as such.
5. Hosting region / data residency — nothing in the repository states it, so no claim may be made.
6. Whether a plan row, Stripe configuration or trial plan exists in the **production database** (doc 02 §4
   establishes only that none exists in the repository).

## 13. What this means for the rebuild

1. **The cutover is the gate, and it is an nginx change.** Until the static shadow at `/` is removed, no Rails
   marketing page can answer `/`. Everything else can be built and tested behind named paths first.
2. **Build it in Rails.** The multi-page, CMS-managed, per-page-SEO, bilingual requirements each independently
   rule out a hand-edited file, and the application already serves public pages well (doc 04 §2).
3. **Six claims must come off the page before anything else ships**, independent of the rebuild: the four status
   readouts, the "every action" audit claim, and the AI section. Doc 02 §6 carries the removal list and the
   honest replacement wording.
4. **Fix `BRAND_URL` first.** It is a one-token configuration change that repairs every "Powered by" link in
   the product, and it is unrelated to the website build.
5. **The four legal documents need real URLs** on this host before the next platform review.
