# 08 — Implementation report

**Branch:** `claude/practical-thompson-9xfqed`
**Commits:** 14, from `4ae356b1` (W1 documents) to `2b44daf1` (W6 fixes)
**Diff:** 115 files, +11,410 / −6

---

## 1. What exists now that did not before

| | Before | Now |
|---|---|---|
| The website | one unversioned static HTML file shadowing Rails at `/` | 96 rows rendered by Rails, in version control |
| Pages | 1 | 48 per locale: 10 standing + 38 catalogue detail |
| Languages | one file, language chosen by a click handler | Arabic unprefixed and English under `/en`, decided server-side from the URL |
| Editing | SSH and a text editor | Super Admin, with draft/preview/publish and an audit trail |
| Discovery tags | 2 `<meta>` + 3 `<link>`, no canonical | title, description, canonical, hreflang ×3, Open Graph, Twitter card, structured data |
| Sitemap | none | `/sitemap.xml`, advertised in `robots.txt` |
| The contact path | a text email address in a `<span>` and a live-chat button that opened nothing | a validated quote form, stored, throttled, and emailed to an operator-editable address |
| False claims | six (doc 01 §5) | none; a `requires` line on every conditional capability instead |
| Tests | none | 250 examples across the website surface |

---

## 2. The architecture, in one page

```
config/routes/marketing.rb          the public tree, the media route, /sitemap.xml, the Super Admin resources
  │
  ├── Marketing::PagesController    10 standing pages  ─┐
  ├── Marketing::EntriesController  38 detail pages     │  read site_pages, nothing else
  ├── Marketing::PricingController  /pricing + the form │
  ├── Marketing::SitemapController  /sitemap.xml        │
  └── Marketing::MediaController    /site-media/:id    ─┘
        (all inherit Marketing::BaseController: locale, tenant-domain rejection, the preview scope)

site_pages ── sections (jsonb, allowlisted by Marketing::SectionSchema)
    │             └── link targets validated by Marketing::LinkTarget
    ├── marketing_images (ActiveStorage, its own attachment name)
    └── meta (jsonb, the SEO overrides)

Marketing::Catalog     the verified product facts — availability, prerequisite, docs, relations
Marketing::ContentBlueprint + ContentSeeder   the locale files → the 96 rows, once
```

The rule that holds all of it together: **the row owns the words, the catalogue owns the facts**, and the
controllers read the row with no fallback — so the editor and the visitor cannot see different things.

---

## 3. By workstream

### W1 — Information architecture and content spec
`docs/official-website/04-information-architecture.md`, `05-design-and-content-spec.md`. Eleven numbered
decisions, including the locale strategy (D5), the tenant-domain boundary (D3), the four CMS record types
(D10) and the reuse map (D11).

### W2 — The Rails foundation
The route table, `Marketing::BaseController` and the page controllers, the layout, the head partial, the
header and footer, the eight section partials, and `config/locales/marketing.{en,ar}.yml` — 483 leaf keys
each, with the Arabic **written in Arabic** rather than translated.

### W3 — The verified pages
20 features, 9 channels, 11 integrations, 4 solutions, each with a detail page carrying its availability
badge and its prerequisite from the catalogue; `/pricing` publishing whatever plans an operator has ticked for
the website and asking for a quote when there are none; `/about`, `/contact`, `/faq`, `/support`.

### W4 — The CMS
Four models, four Administrate resources, the ordered-sections editor, the SEO panel, image management,
draft preview, publish/unpublish, the audit writer, and the editable sales email. `06-super-admin-cms-design.md`
is the design; the source-of-truth boundary and the seeder's never-overwrite rule are proved by six examples.

### W5 — SEO
`/sitemap.xml`, the `robots.txt` additions, the four structured-data nodes, the breadcrumb pair, and redirect
management with loop protection. `07-seo-strategy.md`.

### W6 — Validation
192 browser page loads over all 96 URLs at two viewports in both locales with axe-core; a link sweep; the
quote form submitted for real; the Super Admin CMS driven end to end; custom-domain compatibility checked on a
live server; 23 security examples. Four defects found and fixed. `09-test-results.md`.

---

## 4. Every file this project added

### Routing and configuration
```
config/routes/marketing.rb                               the whole marketing route table, incl. `/` and the `/home` 301
config/routes.rb                                         the root, host-constrained so `/` is the homepage on the platform host
config/locales/marketing.en.yml, marketing.ar.yml        483 leaf keys each
config/vite.json                                         watchAdditionalPaths, so Tailwind's ERB sources invalidate the build
app/controllers/robots_controller.rb                     + the marketing Sitemap line and the preview disallow
app/views/super_admin/application/_navigation.html.erb   + 4 icons and 1 exclusion entry
deployment/nginx/chat.lynomia.com.conf                   a reference model of the vhost -- NOT the live file, not a drop-in
deployment/nginx/cutover-root-to-rails.md                the three-line patch to the live vhost: prepared, not applied
app/controllers/super_admin/application_controller.rb    the invalid-action fallback, `/` -> Super Admin's own root
```

### Models and migrations
```
custom/app/models/site_page.rb                           kinds, statuses, sections, meta, public_path
custom/app/models/site_nav_link.rb                       placements, exactly-one-target, resolves
custom/app/models/site_faq_entry.rb                      question, answer, optional validated link
custom/app/models/site_redirect.rb                       paths, status, loop and chain protection
custom/app/models/site_quote_request.rb                  the one table an anonymous visitor writes
custom/db/migrate/20261014140000_create_site_cms_tables.rb
custom/db/migrate/20261014150000_add_notification_outcome_to_site_quote_requests.rb
```

### Services
```
marketing/catalog.rb            the verified catalogue: 20 features, 9 channels, 11 integrations, 4 solutions
marketing/section_schema.rb     THE CMS SECURITY BOUNDARY: 8 types, their fields, limits, link validation
marketing/link_target.rb        the positive allowlist for anything that becomes an href
marketing/content_blueprint.rb  the locale files → row shapes
marketing/content_seeder.rb     writes them once, never overwrites
marketing/sections_input.rb     the editor's submission → the ordered array
marketing/image_upload.rb       bytes → a marketing image, type read from content
marketing/page_audit.rb         who changed what on the website
marketing/quote_settings.rb     the one editable sales setting
marketing/official_host.rb      is this request on the platform's own host -- the one answer `/` is decided by
```

### Controllers
```
marketing/base_controller.rb      locale, tenant-domain rejection, the draft preview scope
marketing/pages_controller.rb     the 10 standing pages
marketing/entries_controller.rb   the 38 detail pages, and the redirect lookup
marketing/pricing_controller.rb   the page and the quote form, now CSRF-protected
marketing/sitemap_controller.rb   /sitemap.xml
marketing/media_controller.rb     /site-media/:id, published pages only
super_admin/site_pages_controller.rb          publish, unpublish, preview, upload, delete
super_admin/site_nav_links_controller.rb
super_admin/site_faq_entries_controller.rb
super_admin/site_redirects_controller.rb
super_admin/site_quote_requests_controller.rb
super_admin/marketing_settings_controller.rb  show, update, clear, test_email
```

### Super Admin presentation
```
custom/app/dashboards/site_{page,nav_link,faq_entry,redirect,quote_request}_dashboard.rb
custom/app/fields/site_page_sections_field.rb + 4 partials    the ordered-sections editor
custom/app/fields/site_page_meta_field.rb + 3 partials        the SEO panel
custom/app/views/super_admin/site_pages/show.html.erb         status, preview, publish, images
custom/app/views/super_admin/marketing_settings/show.html.erb the three states and three actions
custom/app/views/super_admin/site_quote_requests/index.html.erb
```

### Public views
```
custom/app/views/layouts/marketing.html.erb
custom/app/views/marketing/shared/{_head,_header,_footer,_footer_column,_sections,_page,
                                   _breadcrumb,_entry_card,_state_badge,_cta}.html.erb
custom/app/views/marketing/sections/{_hero,_prose,_cards,_note,_image,_catalogue,_stats,_faq}.html.erb
custom/app/views/marketing/{pages,entries,pricing}/show.html.erb
custom/app/views/marketing/sitemap/show.xml.erb
custom/app/helpers/marketing_helper.rb        URLs and metadata, one host-resolution point
custom/app/helpers/marketing_seo_helper.rb    structured data
```

### Mail
```
custom/app/mailers/marketing/quote_notification.rb   where a notification goes; no fallback
custom/app/mailers/marketing/quote_mailer.rb         the notification and the test message
custom/app/jobs/marketing/quote_notification_job.rb  one attempt, outcome recorded
custom/app/views/marketing_quote_mailer/{new_request,test_notification}.html.erb
config/initializers/mailer.rb                        the test-environment delivery-method fix
```

### Operations
```
lib/tasks/marketing.rake    marketing:content, marketing:content:restore, marketing:verify
```

---

## 5. Decisions worth knowing about

**The CMS has no fallback.** A page with no published row is a 404. The alternative — falling back to the
locale file — would mean the editor and the visitor could disagree, which is the one failure mode a CMS must
not have. `rake marketing:verify` in the deploy is the mitigation.

**Section bodies are plain text.** This repository has already shipped a stored XSS through a Markdown path;
the 96 pages contain no markup; and links are first-class validated fields.

**The sections editor has no JavaScript.** Super Admin renders one Vue island per page and the rest of the
form has to share the screen. Position numbers and remove boxes, server-rendered.

**The quote form is throttled rather than captcha'd.** Five per hour per IP, both locale paths sharing one
counter. A captcha is a third-party script on a zero-JavaScript site and a decision for the owner.

**Notification delivery is recorded, not inferred.** A job writes the outcome to the row, so "delivery
problem" is something that happened rather than something guessed from the presence of an address.

---

## 6. What is deliberately not done

| | Why |
|---|---|
| applying the `/` cutover to nginx | the Rails half is done — `/` is the homepage on the platform's own host, `/home` is a 301. The nginx half is a three-line patch to the live vhost, prepared with its backup, pre-flight checks and rollback in `deployment/nginx/cutover-root-to-rails.md`, and **not applied** |
| merging into `lynomia-custom` | the owner's instruction |
| a sales email address | the owner enters it; the default is empty and nothing is invented |
| prices on `/pricing` | no plan row, price or tier exists anywhere in this repository (doc 02 §4) |
| analytics or a tag manager | nobody asked, and it is a privacy decision |
| a marketing-only Tailwind build | a build-system change; gzip takes the real cost to 138 KB |
| legal page text | linked, never restated; this application does not author policy |
