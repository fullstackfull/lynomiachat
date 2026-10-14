# 09 — Test results

Everything in this document was measured. Where a number improved, both the before and the after were measured
the same way.

---

## 1. The automated suite

```
bundle exec rspec spec/requests/marketing spec/requests/super_admin spec/custom \
                  spec/models/site_page_spec.rb spec/mailers/marketing spec/jobs/marketing
→ 778 examples, 0 failures
```

Of those, 250 are this project's own:

| File | Examples | What it pins |
|---|---|---|
| `spec/requests/marketing/pages_spec.rb` | 59 | all 96 URLs in both locales, the discovery tags, no dead links, the tenant-domain 404, and that no page renders a missing translation |
| `spec/requests/marketing/pricing_spec.rb` | — | no price is published while no plan is listed, no trial is promised, the form stores and answers, the notification is queued for the saved row |
| `spec/requests/marketing/seo_spec.rb` | 18 | the sitemap's contents and exclusions, the robots lines with and without a host, the four structured-data nodes, and that a JSON-LD block cannot be broken out of |
| `spec/requests/marketing/redirects_spec.rb` | 16 | 301 vs 302, chains three deep, loops refused, open redirects refused, protected routes unshadowable |
| `spec/requests/marketing/security/marketing_security_spec.rb` | 23 | the seven surfaces in §4 below |
| `spec/requests/super_admin/site_pages_spec.rb` | 30 | the editor, and that an edit reaches the public page |
| `spec/requests/super_admin/site_cms_spec.rb` | 17 | the nav, FAQ and redirect screens |
| `spec/requests/super_admin/marketing_settings_spec.rb` | 23 | the three states, saving, clearing, testing, the audit, and that a new address applies with no restart |
| `spec/requests/super_admin/site_quote_requests_spec.rb` | 5 | the lead list and its one editable field |
| `spec/models/site_page_spec.rb` | 8 | the standing-key/route agreement in both directions, and the catalogue boundary |
| `spec/custom/services/marketing/*_spec.rb` | 24 | the section schema, the sections input, the quote settings |
| `spec/jobs/marketing/quote_notification_job_spec.rb` | 8 | the recorded outcome, and that a delivery failure never costs a lead |
| `spec/mailers/marketing/quote_mailer_spec.rb` | 7 | the recipient, the reply-to, and that an unconfigured installation sends nothing |

RuboCop: clean on every file this project touches.

---

## 2. The browser pass

A real Chromium, a real Rails server in the test environment with the 96 pages and the documentation corpus
seeded, axe-core 4.10.2 injected per page.

```
192 page loads = 96 URLs × 2 viewports
desktop 1440×900   mobile 390×844
48 Arabic URLs (lang=ar dir=rtl) + 48 English (lang=en dir=ltr)
```

Raw results: `evidence/w6-browser/crawl-results.json`. Screenshots: `evidence/w6-browser/*.png`.

| Check | Result |
|---|---|
| HTTP status | **200 on 192/192** |
| JavaScript console errors | **0** |
| Failed subresources | **0** |
| `lang` / `dir` | 96 × `ar`/`rtl`, 96 × `en`/`ltr` — no page wrong |
| `<h1>` count | exactly 1 on 192/192 |
| title, description, canonical | present on 192/192 |
| hreflang | `ar` + `en` + `x-default` on 192/192 |
| `translation missing` anywhere in the body | **0** |
| horizontal overflow at 390 px | **0** |
| `<img>` without `alt` | **0** |
| `href` empty or `#` | **0** (the skip link's `#main` is a real target) |
| `target="_blank"` without `rel="noopener"` | **0** |
| structured data | 4 home loads with `Organization`+`WebSite`, 4 `/faq` loads with `FAQPage`, 152 detail loads with `BreadcrumbList`, 32 other standing loads with none — as designed |

### The link sweep

111 distinct internal `href`s rendered across the site, every one requested:

* 98 → 200
* 13 → 302 into the Help Center (`/docs`, `/changelog` and 11 article paths), each following to **200**
* **0 dead links**
* 4 external, all `https://lynomia.com/...` legal pages, verified live in `evidence/legal-links.md`
* 2 other schemes: the `#main` skip link and `mailto:info@lynomia.com`

A note on how that was established: on the first pass all 13 documentation links returned 404, then 401. Both
were artefacts of the crawl host rather than defects — the test database had no documentation portal, and the
Help Center's `ensure_custom_domain_request` refuses a host that is neither a registered custom domain nor the
installation's configured one. With the corpus seeded and the crawl pointed at the configured host, all 13
resolve. Recorded because the first number was wrong and the reason matters: **the marketing site's
documentation links only work on the installation's configured host**, which is what production is.

### The forms

* The quote form, filled and submitted in the browser → `/en/pricing?sent=1` with the confirmation visible.
* The same form with an invalid address → the form again, errors beside the fields, nothing stored.

### Super Admin, driven end to end

| Step | Result |
|---|---|
| all six CMS screens, anonymous | every one lands on the sign-in page |
| all seven screens, signed in | 200, with the shared navigation intact — so no exclusion-array breakage |
| open the About page, edit its heading, add a `note` section, save | saved |
| fetch `/en/about` immediately afterwards | **the edit is on the public page** (and was not before) |
| Website Sales Settings, before | "Not configured" |
| save `sales-desk@example.com` | "Configured", with the address |
| Send test email | "A test email was accepted by the mail server for sales-desk@example.com" |
| Clear email | "Not configured" |
| JavaScript errors across the whole pass | **0** |

### Custom-domain compatibility, on a live server

A portal registered at `docs.w6-tenant.example`, requested with that Host:

| URL | Status | Meaning |
|---|---|---|
| `/` | 200 | the tenant's Help Center still answers — existing behaviour preserved |
| `/hc/w6-tenant-portal` | 302 | the Help Center's own redirect |
| `/en/home`, `/features`, `/pricing`, `/sitemap.xml` | **404** | no marketing content inside a customer's domain |

and the platform host unaffected: `/en/home`, `/features`, `/sitemap.xml` all 200.

---

## 3. Accessibility

axe-core, WCAG 2.0 A/AA + 2.1 A/AA, all 192 page loads.

| | Before | After |
|---|---|---|
| `color-contrast` violations | **1,006 nodes** (serious) | **0** |
| Heading-order anomalies | **12 pages** | **0** |
| Any other violation | 0 | 0 |

### F1 — colour contrast (serious, 1,006 nodes)

Five distinct failures, each recomputed from the palette's own hex values rather than eyeballed:

| Used for | Colour | Measured | Needed | Now |
|---|---|---|---|---|
| link text, the wordmark | `woot-600` `#0090ff` on white | 3.26:1 | 4.5:1 | `woot-700` `#2870bd` — **5.07:1** |
| primary buttons | white on `woot-600` | 3.26:1 | 4.5:1 | white on `woot-700` — **5.07:1** |
| hover states | `woot-700` | — | — | `woot-800` `#104d87` — **8.63:1** |
| small grey text | `slate-500` `#777b84` on white | 4.24:1 | 4.5:1 | `slate-600` `#60646c` — **5.94:1** |
| the call-to-action standfirst | `woot-75` on `woot-700` | 4.25:1 | 4.5:1 | `woot-50` — **4.52:1** |

### F2 — a skipped heading level (moderate, 12 page loads)

A `cards` section with no heading of its own put an `<h3>` directly after the page's `<h1>` on `/contact`,
`/support` and `/integrations` in both locales. The item heading level now follows the section's: `<h3>` under
a section heading, `<h2>` without one.

### F3 — Super Admin, in this project's own views (3 findings)

An unlabelled select on the add-a-section control (`select-name`), and `woot-600`/`slate-500` text on the
settings and quote-request screens. All three fixed and re-verified.

### Pre-existing, in the Administrate shell — NOT fixed here

These appear on **every** Super Admin page in the installation, not only the new ones, and belong to a
design-system task rather than to this website project:

| Violation | Element | Scope |
|---|---|---|
| `color-contrast` | the navigation item labels, `.button`, the `Back` link | every Super Admin page |
| `nested-interactive` | the Settings menu's `<summary>` wrapping a link | every Super Admin page |
| `select-name` | Administrate's own `#filter-select` | every index page |

Also recorded: four entries in the Super Admin `sidebar_icons` map name symbol ids that do not exist in
`_icons.html.erb` (`portals`, `categories`, `articles` and one more), so those items render a blank square.
Pre-existing, cosmetic, and left alone — the right icon for each is the owner's choice. The four icons this
project added were checked against `_icons.html.erb` before being used.

---

## 4. Security review

23 executable examples, one per surface the brief named.

| Surface | What was tested | Result |
|---|---|---|
| **XSS** | markup in a section body, a page title, an FAQ question, and a link target | escaped at every sink; a script URL never becomes an `href` |
| **CSRF** | a token-less POST to the public form, and to a Super Admin write | **a real defect, found and fixed — see below** |
| **Unauthorized publishing** | anonymous publish, anonymous edit, the preview parameter, a signed-in product user | refused on all four; the draft stays off the site |
| **Cross-account access** | every marketing URL on a tenant custom domain; what a quote request creates | 404 on the tenant domain; no `Contact`, no `Conversation`, no account record |
| **Unsafe redirects** | absolute, protocol-relative and script destinations; a `redirect_to=` query parameter | refused on save; the parameter is ignored |
| **Uploads** | a renamed CSV, an SVG, a missing file, a draft page's image, another subsystem's attachment | five refusals, including that a draft's image is not served and a documentation attachment is not reachable through the marketing route |
| **Rate limiting** | the quote form past its limit, the Arabic path after the English one, and reading the page | 429 past 5/hour per IP with no row stored; the two locale paths share one counter; GETs are not throttled |

### F4 — CSRF on the one public write (fixed)

`PublicController` does `skip_before_action :verify_authenticity_token` for everything beneath it. That is
correct for what used to live there — the Help Center is a read-only surface — and wrong for the quote form
W2 added under it, which inherited the skip. **Measured: a POST with forgery protection enabled and no
authenticity token stored a quote request.**

Restored for `create` alone, with `:exception` rather than `:null_session` (there is no session for this form
to fall back on, so nullifying one would let the write through — the behaviour being fixed). Verified in both
directions: a token-less POST now answers 422 and stores nothing, and the token the real form emits is
accepted.

### Not a defect, recorded for completeness

* `Rack::Attack.enabled` is false outside production by design, so the throttle is exercised by enabling it
  around the examples against an in-memory store — the arrangement the Platform Support abuse specs
  established.
* `Net::SMTPSyntaxError` is swallowed by `ApplicationMailer`'s `rescue_from`, so an address the relay
  considers syntactically invalid is recorded as delivered rather than as a delivery problem. Named in the job
  rather than guarded against, because the other failure classes — refused connection, authentication,
  timeout, DNS, a busy server — all arrive and are recorded.

---

## 5. Performance

Measured over the same 192 page loads.

| | Value |
|---|---|
| Load event, median | **95 ms** |
| Load event, p95 | 369 ms |
| Load event, worst | 550 ms |
| HTTP requests per page | **3** on every page (document, stylesheet, script) |
| JavaScript shipped | **1 byte** — the entrypoint imports only its stylesheet |
| Transfer per page, uncompressed | 1,511 KB median |
| Of which the stylesheet | 1,497 KB |
| **The stylesheet, gzipped** | **138 KB** |

### F5 — the stylesheet is 1.46 MB uncompressed

Not a purge failure: `./custom/app/views/**/*.erb` is in Tailwind's `content` globs, so marketing classes are
scanned. The cause is that the globs are **application-wide**, and Tailwind emits one stylesheet per CSS
entry from all of them — so the marketing page downloads every class the dashboard uses.

Measured remedies, in order of value for effort:

1. **gzip** — 1.46 MB → 138 KB over the wire. Pure configuration, and now in
   `deployment/nginx/chat.lynomia.com.conf`. **Done.**
2. A marketing-only Tailwind config and PostCSS entry, which would cut the parse cost on a low-end phone as
   well as the transfer. A build-system change with its own risk; **not done**, and recorded here with the
   entry point (`tailwind.config.js` `content`, `app/javascript/marketing/application.scss`).

Three requests, 1 byte of JavaScript and a 95 ms median are otherwise about as good as a server-rendered page
gets.

### F6 — the vite build did not watch the files Tailwind scans (fixed)

`watchAdditionalPaths` was empty, so a class added in an ERB template under `custom/` never invalidated the
dev or test build. The class silently did not apply — which is how the contrast fixes above first appeared to
do nothing, and would mislead anyone developing the site locally. `app/views` and `custom/app/views` are now
watched.

---

## 6. Findings summary

| # | Severity | Finding | Status |
|---|---|---|---|
| F4 | **High** | CSRF verification skipped on the public quote form | **Fixed**, both directions tested |
| F1 | Serious | 1,006 colour-contrast failures across the site | **Fixed**, 0 remaining |
| F2 | Moderate | heading level skipped on 6 URLs | **Fixed**, 0 remaining |
| F3 | Moderate | three accessibility defects in this project's Super Admin views | **Fixed** |
| F6 | Moderate | the asset build ignored the ERB sources Tailwind scans | **Fixed** |
| F5 | Low | the stylesheet is 1.46 MB uncompressed | gzip configured (138 KB); a per-entry build recorded, not done |
| — | Low | the Administrate shell fails AA on its own nav labels, buttons and filter select | pre-existing, installation-wide, left to a design-system task |
| — | Cosmetic | four `sidebar_icons` entries name nonexistent symbol ids | pre-existing, left alone |

---

## 7. How to reproduce the browser pass

```bash
service postgresql start

# Seed the test database and the documentation corpus (a super admin must exist first).
RAILS_ENV=test bundle exec rails runner 'Marketing::ContentSeeder.apply!'
RAILS_ENV=test bundle exec rails documentation:setup documentation:content

RAILS_ENV=test FRONTEND_URL=http://localhost:3001 bundle exec rails server -p 3001 -b 127.0.0.1

# Crawl it. Chromium is pre-installed; axe-core is fetched once.
node crawl.mjs        # the script used for this pass is in the session record, not the repository

# Afterwards, remove what the crawl wrote: it ran OUTSIDE a transaction, so anything left behind
# leaks into later examples. This was measured during this work -- three stray quote requests made
# two security examples fail for the wrong reason.
RAILS_ENV=test bundle exec rails runner '[SiteQuoteRequest, SiteNavLink, SiteFaqEntry, SiteRedirect, SitePage].each(&:delete_all)'
```
