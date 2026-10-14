# 04 — Information architecture and serving decisions

**Date:** 2026-10-14 · Decisions here are binding on W2–W6. Evidence: `01-current-state-audit.md`,
`02-verified-feature-inventory.md`, `03-competitive-analysis.md`.

## D1 — The site is built inside the Rails application

Four requirements each independently rule out a static file, and all four are owner requirements: operator-
managed content without a deploy, per-page SEO fields, true Arabic/English parity at the URL level, and
integration with Documentation V2 and the Platform Support Desk. The application already renders public,
unauthenticated, crawlable HTML for the Help Center, so this is reuse, not new ground.

**No parallel application, no separate CMS product.** The marketing site is a namespace inside this app.

## D2 — Named routes first; `/` is a separate, approved cutover

The marketing site ships under its own paths and **does not take `/` in the same change**. Reason: in
production nginx answers `/` from disk (`01-current-state-audit.md` §1), so a Rails root change has no effect
there until the vhost changes — and it *does* change behaviour in development, CI and any other deployment.
Shipping them together would mix a reversible application change with an irreversible-looking infrastructure one.

**Order of operations:**

1. W2–W5: everything under named paths. `/` keeps `root to: 'dashboard#index'` (`config/routes.rb:17`).
2. W6: the cutover commit — Rails root becomes the marketing home, with the custom-domain delegation of D3
   and the four spec changes of D4 — plus a version-controlled nginx vhost, applied only on explicit approval.

## D3 — Custom-domain Help Centers must keep working, and the marketing root is host-scoped

This is the one genuine breakage a root change causes. `DashboardController` renders a portal's home at `/`
when the request host matches a `Portal#custom_domain`:

```ruby
# app/controllers/dashboard_controller.rb:64-75 (before_action at :40)
def render_hc_if_custom_domain
  domain = request.host
  return if domain == URI.parse(ENV.fetch('FRONTEND_URL', '')).host
  @portal = Portal.find_by(custom_domain: domain)
  return unless @portal
  ...
  render 'public/api/v1/portals/show', layout: 'portal', portal: @portal and return
end
```

**Rule:** the marketing root action runs that same host check **first** and delegates when it matches. A
tenant's custom domain never sees a Lynomia marketing page, and the marketing pages answer **only** on the
official host.

**Rule (host scoping), which also closes a finding the audit raised:** every marketing route refuses a request
whose host is a registered portal custom domain. Without it, `/pricing` would also answer on
`docs.customer.example`, because custom domains resolve through the same route table.

## D4 — What the root change touches, and nothing else

The full dependency trace is in the working notes; the result:

| Thing | Effect | Handling |
|---|---|---|
| Custom-domain Help Center home | **breaks without D3** | D3 delegation |
| `spec/controllers/dashboard_custom_domain_spec.rb:28,44` | 2 examples | pass once D3 is in place |
| `spec/requests/search_indexing_spec.rb:74` | installation-onboarding redirect at `/` | marketing root keeps `ensure_installation_onboarding` (`dashboard_controller.rb:39,60-62`) |
| `spec/requests/search_indexing_spec.rb:94` | custom-domain `/` indexable | passes with D3 |
| Super Admin "Agent Dashboard" nav item, hardcoded `url: '/'` (`app/views/super_admin/application/_navigation.html.erb:72`) | would land an operator on marketing | change to `/app` |
| `TERMS_URL` / `PRIVACY_URL` anchors on the old page | login/signup links | re-point to the new `/terms` and `/privacy` in the same release |
| Mailer links, `FRONTEND_URL`'s 56 call sites, the Vue router, OAuth callbacks, webhooks, widget, survey, logout | **no effect** | `root_url` still returns `/`; every one of them appends a path, and the SPA declares no route at `/` |

`/` today is a bounce page: the SPA boots the whole dashboard bundle only to redirect to `/app/login` or the
account dashboard (`app/javascript/dashboard/routes/index.js:18-64`). Replacing it removes that bounce.

## D5 — Language: Arabic unprefixed, English under `/en`

```
/                         Arabic home          ← x-default and ar
/en                       English home         ← en
/features/unified-inbox   Arabic feature page
/en/features/unified-inbox  its English sibling
```

Arabic is the primary market and gets the clean URLs; English is explicit. Each page declares reciprocal
`hreflang` for `ar` and `en` plus `x-default` → the Arabic URL, and `<html lang dir>` is set per locale using
the helpers the Help Center already uses (`app/helpers/portal_helper.rb:40-42`,
`app/helpers/text_direction_helper.rb:12,20-22`).

**Language is a server-side URL decision, never a client-side swap** — the defect that made the current page
flip every Arabic visitor to English (`01-current-state-audit.md` §3.3). A language switcher is a link to the
sibling URL, nothing more.

Documentation V2 keeps its own `/hc/:slug/:locale` convention. The two systems are addressed differently on
purpose; changing the documentation URLs would break 164 indexed URLs for cosmetic consistency.

## D6 — URL map

Routes marked **CMS** are database-backed pages an operator edits; **code** pages are templates.

### Pillars and index pages
| Path | Type | Notes |
|---|---|---|
| `/` · `/en` | CMS sections | home |
| `/features` | code + CMS intro | grouped index of feature pages |
| `/channels` | code + CMS intro | nine channels, with per-channel state |
| `/solutions` | code + CMS intro | industry and team pages |
| `/integrations` | code + CMS intro | four commerce providers |
| `/pricing` | CMS | **quote request**, no figures (doc 02 §4) |

### Feature pages (all verified AVAILABLE unless noted)
`/features/unified-inbox` · `/team-collaboration` · `/auto-assignment` · `/contact-management` ·
`/custom-attributes` · `/canned-responses` · `/macros` · `/business-hours` · `/customer-satisfaction` ·
`/automation` · `/campaigns` · `/audiences` · `/whatsapp-templates` · `/analytics` · `/api-webhooks` ·
`/support-desk` · `/security`
**Conditional, and labelled on the page:** `/features/ai-assist` · `/features/flow-builder` ·
`/features/translation`

### Channel pages
`/channels/whatsapp` · `/live-chat` · `/email` · `/sms` · `/telegram` · `/line` · `/facebook-messenger` ·
`/instagram` — plus the API channel folded into `/features/api-webhooks`, and TikTok named as **beta** on
`/channels` only.
**Never created:** Twitter/X, voice, 360dialog.

### Company, legal and support
`/about` · `/contact` · `/demo` · `/faq` · `/support` · `/terms` · `/privacy` · `/data-deletion` ·
`/security` — plus `/docs` and `/changelog`, which **already exist** and are not re-implemented.

### Reserved, not built in this programme
`/blog`, `/use-cases/*`, `/industries/*`, `/compare/*`, free tools. The IA leaves room for them; the content
does not exist yet.

**Every path above was proven free** against `config/routes.rb` and all ten files in `config/routes/`
(`01-current-state-audit.md` §1.4 measured 34 of 36 as live 404s). One caveat carried forward:
`public/integrations/` holds real static files, so `/integrations/:slug` must not use a slug that collides
with an existing file path there.

## D7 — Navigation and footer

Grouped by buyer journey rather than by module name.

**Header:** المنتج (mega menu: Features, Channels, Integrations) · الحلول · الأسعار · الموارد (Documentation,
Changelog, FAQ, Support) · تسجيل الدخول · **أنشئ حسابك**.

**Footer, five columns:** Product · Solutions · Resources (Documentation, Help centre, Changelog, FAQ) ·
Support (Contact, Open a ticket, Email) · Company (About, Privacy, Terms, Data deletion).

Both are **CMS-managed** (`SiteNavLink`), because the current site's inability to change a nav item without a
server edit is one of the problems being fixed. Rules enforced in code: no link may point at an unpublished
page, and no link may be empty — the audit found four dead footer links and the rebuild must make that state
unrepresentable.

## D8 — Documentation and support integration

**Documentation:** link through the existing named helpers — `lynomia_docs_path`,
`lynomia_docs_article_path(slug)`, `lynomia_changelog_path` (`config/routes/documentation.rb:56,59-61`). No
second documentation centre, no copying of article content, and nothing writes into the corpus. Every feature
page carries a "read the documentation" deep link to its specific article where one exists (doc 02 records the
slugs per area).

**Support — the honest design.** There is no account-less ticket URL and no post-login return destination
(doc 02 §5). So:

- `/support` is a public page explaining both desks and what to do.
- "Open a ticket" is shown as a **sign-in-first** action linking to `/app/login`, labelled as such.
- A signed-in customer reaches `/app/accounts/:id/help/tickets/new` from inside the product.
- The public page also links `/docs/contact-lynomia-support`, which is indexable and account-less.
- `/contact` carries a form for people who are **not** customers.

**Never:** a public link containing a guessed account id, an internal ticket API exposed publicly, or a second
ticket system. If a one-URL entry point is wanted later, it is new work: either an account-less redirect that
resolves the signed-in user's account, or a path-allowlisted `return_to` on `/app/login`
(`raise_on_open_redirects` is on — `config/application.rb:39`).

## D9 — SEO architecture

- **One host-resolution point** for marketing absolute URLs, mirroring `DocumentationHelper#portal_public_host`
  (`custom/app/helpers/documentation_helper.rb:56-62`), which exists because the same arithmetic in three
  copies produced `https://hc/hc/...` in canonicals and sitemaps. Canonical, `hreflang`, `og:url`, JSON-LD and
  the sitemap all read from it, so they cannot disagree.
- **`/sitemap.xml`** — marketing URLs only; the address is free (404 today). The three per-portal documentation
  sitemaps stay as they are, and a fourth `Sitemap:` line is added to `robots.txt`
  (`app/controllers/robots_controller.rb:77-83`) without disturbing the generated ones. The regression suite at
  `spec/requests/search_indexing_spec.rb:112-151` must stay green; in particular no broad `Disallow:` may be
  added.
- **Per page:** unique title and meta description, canonical, reciprocal hreflang, Open Graph and Twitter,
  breadcrumbs, and structured data where the type genuinely applies — `Organization` and `BreadcrumbList`
  always, `FAQPage` **only** where FAQ entries exist as structured rows, `SoftwareApplication` on the home.
  No `AggregateRating`, no `Review`: there is nothing to base them on.
- **Published pages only** in the sitemap, and alternates only to published siblings — the rule the
  documentation sitemap already follows (`app/views/public/api/v1/portals/sitemap.xml.erb:22`).
- **The marketing home gets a full head.** The documentation portal's landing page emits none, which is a
  recorded defect (`01-current-state-audit.md` §5.1); the marketing root must not inherit it.
- **Noindex** for drafts, previews and any `?` parameterised duplicate.

## D10 — Content model: a new `SitePage`, and why not `Article`

Marketing pages **cannot** be `Article` rows. The seeding contract makes `content` repository-owned and the
seeder wins on every run; a Super Admin-authored page with no corpus file is `untracked`, and
`documentation:content` **exits non-zero** on it — so marketing content stored as articles would fail the
documentation seed on every deploy. `Article#slug` is also not operator-editable by design, while a marketing
URL is exactly what an operator must choose. (`docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md:17-22,
31-41`; `custom/app/dashboards/article_dashboard.rb:42-48`.)

The smallest sound model, reusing existing patterns rather than inventing new ones:

- **`SitePage`** — `locale`, operator-chosen `slug`, `kind`, `status` (draft/published/archived),
  `published_at`, `title`, `description`, `meta` jsonb (SEO fields, edited through a field class modelled on
  `ArticleMetaField`'s merge-not-replace discipline, `custom/app/fields/article_meta_field.rb:43-55`),
  `sections` jsonb (ordered, typed sections), `position`, and a self-join to its translation sibling — the same
  mechanism hreflang already reads for articles (`custom/app/helpers/documentation_helper.rb:192-196`).
- **`SiteNavLink`** — `locale`, `placement`, `label`, `href`, `position`, `visible`.
- **`SiteFaqEntry`** — `locale`, `question`, `answer`, `position`, optional page link; structured rows are what
  make `FAQPage` JSON-LD honest.
- **`SiteRedirect`** — `from`, `to`, `permanent`, for retired URLs.
- **Media** — `has_many_attached` on `SitePage`, in a namespace **separate** from `portal.documentation_media`
  so the documentation corpus's orphan sweep can never reach marketing media, and vice versa.

**Deliberately not proposed:** a revision table, a second media system, a corpus-seeded marketing tree, or any
tenant-reachable authoring path — each is forbidden by the Documentation V2 contracts for reasons that still
apply.

## D11 — Reuse map for W2

| Need | Reuse | Source |
|---|---|---|
| Base controller | `PublicController` (`ActionController::Base`, no session, no Pundit) | `app/controllers/public_controller.rb:3-5` |
| Locale selection | `SwitchLocale#validate_and_get_locale` | `app/controllers/concerns/switch_locale.rb:59-72` |
| `lang`/`dir` | `PortalHelper#html_lang_attribute`, `TextDirectionHelper#html_dir_attribute` | as cited in D5 |
| Asset pipeline | a new Vite entrypoint beside `portal.js`; `vite-plugin-ruby` picks it up with no build config | `vite.config.ts:8` |
| Tailwind | already scans `app/views/**/*.erb` and `custom/app/views/**/*.erb` | `tailwind.config.js:38-39` |
| Head pattern | `content_for?(:head)` with a title fallback | `app/views/layouts/_portal_head.html.erb:16-20` |
| Super Admin CMS | Administrate dashboard + controller + route + **the navigation exclusion array** | `app/views/super_admin/application/_navigation.html.erb:40-47` |
| Editor | the existing Markdown editor component and its mount registry | `app/javascript/entrypoints/superadmin_pages.js:9-13` |
| Server-side preview | the same renderer the public page uses, never a browser-side Markdown implementation | `custom/app/controllers/super_admin/articles_controller.rb:27-39` |
| Media upload | server-side through an authenticated action; the direct-upload route stays 403 | `config/initializers/active_storage.rb:48-64` |
| Audit | `Custom::AuditLog` + the `Billing::PlanAudit` writer pattern | `custom/app/services/billing/plan_audit.rb:24-33` |

**Not reusable, and why:** `_portal_head`, `_portal_scripts` and the portal analytics partials all require an
`@portal`; `Documentation::MediaUpload` is constructed per portal and refuses non-corpus callers; the portal
404 renders inside the portal layout.

## D12 — Content rules binding on W3

1. Every claim traces to `02-verified-feature-inventory.md`. Availability is re-checked during implementation,
   not assumed from the inventory alone.
2. CONDITIONAL and BETA features are labelled **on the page**, with the prerequisite named.
3. No invented statistics, no performance percentages, no uptime or SLA numbers, no certifications, no
   customer logos or testimonials that do not exist, no prices.
4. AI is presented as the five agent-assist actions with their prerequisite, never as an autonomous agent.
5. Screenshots are real product UI with customer data removed; anything illustrative is visibly illustrative.
6. Arabic is written, not translated — and both locales are reviewed as originals.
