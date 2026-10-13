---
agent: 098
scope: Attack SEO and indexability, including the audit that reports "0 SEO errors / INDEXABLE"
confidence: high
---

# 098 — Attack SEO and indexability

**The sentence under attack.** The production run reported `38 created / 19 updated / 67 unchanged / 124 published /
0 SEO errors`, and `lynomia:docs:seo_audit` printed `INDEXABLE` (`lib/tasks/documentation_seo_audit.rake:148`).

**What that sentence proves.** The audit raises an ERROR at ten call sites
(`documentation_seo_audit.rake:54,71,72,86,102,104,113,122,124,128`). Eight of the ten cannot fail on this
installation's data model — they are guarded by a unique index, by a model presence validation, or by their own
preceding `return`. Of the two that can fail, one (`no meta description and no description`, `:86`) has nothing to
report: all 126 corpus files carry a description and all 126 fall inside the audit's own 50–160 window (measured).
The other (`duplicate hreflang locales`, `:113`) is reachable only through a Super Admin action nobody has taken.

So `0 SEO errors / INDEXABLE` proves that **124 published rows each had a non-blank description**. It does not
establish that the pages are indexable, that the canonical is on the right host, that the `<title>` fits, that the
sitemap is true, that the corpus has no duplicates, or that a product link resolves. The task's own header is honest
about this — *"it audits data rather than templates — deliberately"* (`:1-11`) — and the word `INDEXABLE` on line 148
is where the honesty stops. `01-current-system.md` §8 reprints the ten checks as a table of enforced errors without
saying that eight of them are unfalsifiable, and §10 then makes the task a release blocker by construction. A gate
that cannot fail is not a gate.

---

## 1. What you attacked

| Target | Source |
|---|---|
| The verdict `0 SEO errors / INDEXABLE` and the table that presents it as enforcement | `documentation_seo_audit.rake`, `01-current-system.md` §8, §10 |
| SA-01 — "the title-length check measures `article.title` while the page renders `meta['title']`, so it flags four files that are already compliant" | brief; `070-seo-authoring-fields.md` §3.2(a) |
| SA-02 — the rendered `<title>` appends a 29-character suffix the audit never counts; 27 of 126 exceed 60 | brief; 070 §3.2(b) |
| SA-03 — a hostless canonical yields `https://hc/...` and PASSES the host check | brief; 070 §3.7; 073 D1; 075 D8 |
| SA-04 — the duplicate-canonical ERROR is structurally unreachable; its spec stubs `Article#slug` | brief; 070 §3.3; 073 §3.1 |
| The five cases the brief says the audit cannot see (renamed slug, orphan, dead `DOC_ARTICLES` key, thin/duplicate content, retired URLs in the sitemap) | brief |
| `spec/requests/search_indexing_spec.rb:110` vs `RobotsController` and `seo_spec.rb` | brief; 074 D2 |
| Peer conclusions | 073 (canonical/hreflang), 074 (sitemap/robots), 075 (structured data), 077 (search), 079 (retirement) |
| **No report exists for 076 (internal linking), 078 (synonyms) or 080 (CWV and image SEO)** — those areas were read from code directly | `ls docs/documentation-v2/discovery/` |

Nothing was executed. Charter §6.1 forbids `rails`, `rake` and `rspec`; every "measured" figure below comes from
reading files or from a read-only script over `custom/db/documentation`, and every behavioural claim is traced through
source. Crawler-behaviour claims are marked **observational** — the brief authorised no network reads, so Google's and
sitemaps.org's documented thresholds are recalled, not fetched.

---

## 2. Refutations

### R1 — blocker — Eight of the audit's ten ERROR checks cannot fail. The verdict is near-vacuous.

**Claim refuted:** `01-current-system.md` §8 ("What it enforces", ten rows, seven of them `error`) and the
`INDEXABLE` verdict at `documentation_seo_audit.rake:148`.

| # | Check | Line | Can it fail? | Why not |
|---|---|---|---|---|
| 1 | two articles share a canonical | `:54` | **No** | `index_articles_on_slug (slug) UNIQUE` (`db/schema.rb:226`). Canonical is host + `portal.slug` + `article.slug` (`documentation_helper.rb:15-17`), and the grouping is *inside* `portals.each` (`:44-57`), so host and portal slug are constant per group. Distinct slugs ⇒ distinct canonicals. |
| 2 | canonical URL has no host | `:71` | **No, and it is inverted** | See R4. The only misconfiguration it exists to catch produces `https://hc/...`, and `start_with?('http')` is true. The sole way to fail is a `custom_domain` containing `://` with a non-HTTP scheme. |
| 3 | no title | `:72` | **No** | `validates :title, presence: true` (`app/models/article.rb:67`). A blank or whitespace title cannot be saved. |
| 4 | no meta description and no description | `:86` | **Yes** | Nothing validates `description`. This is the one live check — and 0 of 126 files violate it. |
| 5 | hreflang set lacks the article itself | `:102` | **No** | `article_translation_family` is `[root] + root.associated_articles` filtered to `published` (`documentation_helper.rb:106-110`). The audit iterates only published articles, and a published article is either the root or in `root.associated_articles`. It is always in its own family. |
| 6 | hreflang set has no x-default | `:104` | **No** | `audit_alternates` returns early when `alternates.empty?` (`:99`), i.e. when `family.length < 2`. `portal_default_alternate_url` returns `nil` only when `family.length < 2` (`documentation_helper.rb:56`). The guard already excluded the only failing input. |
| 7 | duplicate hreflang locales | `:113` | **Yes, but not the way 073 says** | See R14: not via `associated_article_id` (absent from `ArticleDashboard::FORM_ATTRIBUTES`, `article_dashboard.rb:36`) but via moving an article into a category of another locale, which `ensure_locale_in_article` (`article.rb:200-206`) then applies. |
| 8 | breadcrumb crumb with no name or URL | `:122` | **No** | Crumb 1 name is `portal.display_title` → `localized_value('page_title')‖self['name']`, and `name` is presence-validated (`portal.rb:59`). Crumb 2 exists only `if article.category` and `Category` presence-validates `name` (`category.rb:61`). Crumb 3 is `article.title`, presence-validated. All three `item` values are built strings, never blank. |
| 9 | article schema has no url | `:124` | **No** | `schema['url']` is `portal_canonical_url`, a concatenation that is never empty. |
| 10 | structured data could not be serialized | `:128` | **No** | Every value in both hashes is a `String`, `Integer` or `nil`-compacted (`documentation_helper.rb:69-95`). Postgres `text` columns in a UTF8 database cannot hold the invalid byte sequence that would raise `JSON::GeneratorError`. |

073 §3.1 reached part of this conclusion for five checks; it did not cover checks 3, 8, 9 or 10, and it rated check 7
reachable for the wrong reason. **Severity blocker**, because `01-current-system.md` §10 states "Anything that makes it
exit 1 is a release blocker by construction" — the converse, that a clean exit means anything, is what Phase 4 is
about to freeze a deploy gate on.

### R2 — major — SA-01 is wrong as stated, and it inverts the finding it reports.

**Claim refuted:** the brief's SA-01, and `070-seo-authoring-fields.md` §3.2(a): *"The audit measures `article.title`,
not the title a crawler reads… All four already carry a compliant `seo_title`. The author did the correct thing and
the audit still warns."*

`meta['title']` does **not** reach `<title>`. All three article variants emit `article.title`:

- `app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:10` —
  `<title><%= article.title %> | <%= portal.display_title(article.locale) %></title>`
- `app/views/public/api/v1/portals/articles/_meta_head.html.erb:2` — same shape, used by the classic and plain
  variants (`articles/show.html.erb:2`, `articles/show.html+plain.erb:2`).

`meta['title']` overrides only `<meta name="title">`, `og:title` and `twitter:title`
(`documentation_layout/articles/_meta_head.html.erb:8,26,38,50`). 070's own §3.2(c) says exactly this and calls the
field hint false — so §3.2(a) contradicts §3.2(c) three paragraphs later, and the brief inherited the wrong half.

The consequence is not academic. Measured over all 126 files, the four articles the audit flags are the four **worst**
rendered titles in the corpus:

| File | `title` | `seo_title` | rendered `<title>` |
|---|---|---|---|
| `en/whatsapp-errors/whatsapp-business-scoped-contacts.md` | 66 | 49 | **95** |
| `en/whatsapp-errors/whatsapp-error-131049.md` | 63 | 37 | **92** |
| `en/whatsapp-errors/whatsapp-error-131060.md` | 62 | 37 | **91** |
| `en/whatsapp-errors/whatsapp-error-131042.md` | 61 | 37 | **90** |

The audit does not false-positive on these four. It under-reports them, and it misses 23 others. Treating them as
"already compliant" licenses silencing the warning on precisely the pages that need it — and 070 §4 proposes an
author-time panel that counts `seo_title`, which would make the real defect permanently invisible. **Severity major.**

### R3 — confirmed, and extended — SA-02 is exactly right. The suffix is 29 characters and 27 of 126 exceed 60.

Verified independently. `portal_seeder.rb:12` sets `page_title: 'Lynomia Chat Documentation'` — 26 characters — and
the template adds `' | '`, 3 more: **29**, leaving a 31-character budget. Measured: **27 of 126 files render a
`<title>` over 60 characters (16 EN, 11 AR; longest 95)**. The audit reports 4. Three extensions nobody recorded:

1. **Arabic pages carry the English suffix.** `portal_seeder.rb:62-66` writes `allowed_locales`, `default_locale` and
   `layout` into `config` and no `locale_translations`, so `localized_value('page_title', 'ar')` falls through both
   `translations.dig('ar', …)` and `translations.dig('en', …)` to `self['page_title']` (`portal.rb:148,155-160`).
   Every Arabic documentation page ends `… | Lynomia Chat Documentation`.
2. **No spec asserts `<title>` on any portal page.** `grep -rn '<title>' spec/` returns only
   `dashboard_controller_spec.rb:32`, `super_admin/operations_control_center_spec.rb:319-320` and the
   `website_branding_service_spec.rb` fixtures. `spec/requests/documentation/seo_spec.rb` — 198 lines, the
   area's dedicated spec — asserts canonical, hreflang, Open Graph, Twitter, JSON-LD, sitemap and robots, and never
   the `<title>`. So the regression is unasserted at both the audit level and the spec level.
3. **`:73` and `:74` disagree with each other.** The condition is `article.title.to_s.length`, the message is
   `article.title.length`. Harmless only because check 3 can never leave a nil title in play (R1).

### R4 — confirmed, and worse — SA-03 is real, and the same arithmetic is re-implemented twice more, divergently.

The string arithmetic, evaluated in isolation: `host = ''` → `''.include?('://')` is false → `host = 'https://'` →
`'https://'.chomp('/')` → `'https:/'` → `'https:/' + '/hc/lynomia-docs/articles/welcome'` →
`"https://hc/lynomia-docs/articles/welcome"`, and `start_with?('http')` is `true`
(`documentation_helper.rb:29-33`; `ChatwootApp.help_center_root` is `ENV['HELPCENTER_URL'] || ENV['FRONTEND_URL']`,
`lib/chatwoot_app.rb:35-37`). Confirmed.

What 070 §3.7, 073 D1 and 075 D8 all missed is that `portal_absolute_url` is not the only copy:

| Copy | Behaviour with no host |
|---|---|
| `custom/app/helpers/documentation_helper.rb:29-33` | `https://hc/...` — canonical, hreflang, `og:url`, JSON-LD `url`, sitemap `<loc>` |
| `app/controllers/robots_controller.rb:37-39` | `Sitemap: https://hc/hc/lynomia-docs/sitemap.xml` — robots.txt does **not** call the helper |
| `app/controllers/public/api/v1/portals_controller.rb:18-20` | `nil.include?('://')` → `NoMethodError` → **500** on `/hc/:slug/sitemap.xml`; the only copy without `.to_s` |

Three copies, two divergent behaviours, one of them a 500 on the URL the other two advertise. And
`documentation_helper.rb:7-10` asserts the opposite in a comment that is the reason nobody re-checked:
*"EVERY ADDRESS HERE IS BUILT THE SAME WAY … so the canonical, the locale alternates, the Open Graph URL, the
structured data **and the sitemap** can never disagree with each other. That is the whole reason they are in one
helper rather than one expression per view."* `robots_controller.rb:37-39` is one expression per view. The claim is
false as written. **Severity major** (the comment, not the arithmetic). 074 D10 noticed the dead
`@help_center_url` and the `nil.include?` raise but did not connect it to the helper's claim or to the robots copy.

### R5 — confirmed, and extended — SA-04 is real, and the gate's own spec covers 2 of its 10 error checks.

`spec/lib/tasks/rake/task_documentation_seo_audit_spec.rb:50-56`:

```ruby
first = article(slug: 'duplicate')
allow_any_instance_of(Article).to receive(:slug).and_return(first.slug) # rubocop:disable RSpec/AnyInstance
article(slug: 'duplicate-two')
```

The stub replaces the *reader* only, so the second row still writes `duplicate-two` and the unique index is never
touched. The branch is reachable only by defeating the model. Confirmed.

The extension: that spec has **six examples**, and they exercise one happy path, one error (check 4), one warning
(description length), one error reachable only by stubbing (check 1), one reciprocal pair, and the empty-portal
message. Checks 2, 3, 5, 6, 7, 8, 9 and 10 have **no example**, and neither does the title-length warning — the only
check that fires on real corpus data (R2, R3). The release gate's own test suite cannot detect a regression in the
release gate. **Severity major.**

### R6 — major, new — The audit validates tags that the audited pages never emit.

`documentation_seo_audit.rake:34` is `Portal.where(archived: false)` — not `Documentation::Library.portals`
(`library.rb:37-39`, the documented "single door"). So by default the task audits **every non-archived portal of every
tenant account**, and then checks canonical, hreflang and structured data on all of them.

`grep -rn 'rel="canonical"' app/views/` returns exactly two files, both under `documentation_layout/`
(`articles/_meta_head.html.erb`, `categories/_meta_head.html.erb`). The classic variant's head
(`app/views/public/api/v1/portals/articles/_meta_head.html.erb:1-21`) emits `<title>`, `meta name="title"`,
`description`, `tags` and Open Graph image tags — and **no canonical, no hreflang, no JSON-LD**. Every tenant portal
defaults to `classic` (`base_controller.rb:23`).

Two consequences. For a tenant portal, eight of the ten error checks and the duplicate-canonical grouping are
assertions about markup that is never produced — a measurement of nothing. And because the task
`exit 1`s on any error (`:149`), **a customer's help-center content can set the exit code of a gate on Lynomia's own
release**. 074 D4 raised the scoping question for the `Sitemap:` list and for `:34`, and framed it as a product
decision about advertising tenant portals; it did not note that the checks are meaningless for those portals or that
the exit code is shared. **Severity major.**

### R7 — major, new — `?show_plain_layout=true` is a canonical-less mirror of the whole portal, and the page's own JavaScript propagates it.

`base_controller.rb:26-31`: `request.variant = :plain` whenever `params[:show_plain_layout] == 'true'`, for **any**
portal layout — the documentation branch is the `elsif`. `articles/show.html+plain.erb:1-4` then renders
`articles/_meta_head.html.erb`, which has no canonical, no hreflang and no structured data (R6). `robots.txt`
disallows `/hc/*?theme=` and nothing else (`robots_controller.rb:28`).

073 D5 and 074 D5 both recorded this and both rated it **minor**, on the reasoning that "public pages do not link to
it". That reasoning does not survive two further reads:

1. `app/javascript/portal/portalHelpers.js:141-151` — `appendPlainParamToURLs` iterates **every** `<a>` on the page
   whose href contains `/hc/` and sets `show_plain_layout=true` on it. It runs whenever
   `window.portalConfig.isPlainLayoutEnabled === 'true'` (`:168-170`). One crawlable plain URL therefore yields a page
   whose every internal link is another plain URL. The sidebar on that page lists every published article
   (`_sidebar.html.erb:8-11`), so the mirror is complete in one hop. That a crawler executes this JavaScript is
   **observational** — I did not fetch Google's rendering documentation — but the mechanism is in the repository.
2. `custom/app/controllers/super_admin/articles_controller.rb:24` — the Preview action redirects to exactly
   `/hc/#{portal.slug}/articles/#{slug}?show_plain_layout=true`. The authoring tool is the one in-product producer of
   the URL, so it will appear in operator bookmarks, tickets and chat logs.

And `base_controller.rb:66-68` deletes `X-Frame-Options` for that variant, so the canonical-less copy is also
framable by any origin. The audit cannot see any of this: it never renders a template. **Severity major.**

### R8 — major for the baseline — `DOC_ARTICLES` has 62 keys, not 87.

`01-current-system.md` §7: *"`DOC_ARTICLES` — **87 keys**, grouped by product area"*. Measured over
`app/javascript/dashboard/helper/documentationLinks.js:11-94`:

```
awk '/export const DOC_ARTICLES/,/^\}\);/' … | grep -cE "^\s{2}[A-Za-z0-9_]+:"   → 62
```

62. Adding `COMMERCE_ERROR_ARTICLES` (19 entries, `:108-132`) gives 81, still not 87; `whatsappErrorArticle`
(`:154-167`) adds no entries of its own, it reads `DOC_ARTICLES`. 079 D10 independently used 62 (*"62 of 63 keys are
in the JS registry"*) and is correct. The figure matters because Phase 2's coverage matrix is sized from it. Also
measured: all 62 registry values resolve to an existing EN corpus file, there are no duplicate values, and exactly one
corpus key — `your-own-help-centre` — has no registry key pointing at it.

### R9 — major, new — The "`DOC_ARTICLES` key resolving to nothing" case is already live for Arabic, and three layers each miss it.

A file-level check exists and is green: `spec/custom/services/documentation/content_seeder_corpus_spec.rb:68-79`
parses the registry as text and asserts `slugs - keys_by_locale['en']` is empty. So registry-vs-file is covered — by a
spec, not by the SEO audit, which never reads the registry and never reads `meta['doc_key']`.

What no layer covers is resolution *in the database*:

- `ArticleMetaField.permitted_attribute` (`custom/app/fields/article_meta_field.rb:33-35`) permits
  `title description version release_date feature_image tags` — **not `doc_key`**.
- `SuperAdmin::ArticlesController#resource_params` (`:39-43`) assigns `meta` as a whole hash, so one save replaces the
  jsonb and the key is gone. 070 §3.1 and 079 D4 both record the loss.
- `Documentation::Library.article_for` (`library.rb:54-57`) then falls through
  `by_key.find_by(locale:)` → `by_key.find_by(locale: 'en')` → `by_key.first` → `article(key)`, and
  `article(key)` is `find_by(slug: key)`. For `locale: 'ar'` that returns the **English** article, because the Arabic
  slug is `key-ar` (`content_seeder.rb:85-87`).

Neither 070 nor 079 states that consequence. The English link keeps working, so nothing is visibly broken; the Arabic
contextual-help link silently re-points at English, and the audit has no `doc_key` check to notice. The same spec is
also what makes 073's D2 invisible — see R10.

### R10 — major — The corpus spec's "links only to articles that exist" is true at key level and false at URL level.

`content_seeder_corpus_spec.rb:31-37` scans `](target)` for bare keys and asserts
`targets - keys_by_locale[locale]` is empty. For an Arabic file, `keys_by_locale['ar']` is the set of Arabic *file
basenames*, which are identical to the English keys — the `-ar` suffix exists only in the database slug. So
`](automation-rules)` inside an Arabic file passes.

Measured: **494 bare-key links in the Arabic corpus, 0 of them ending in `-ar`** (identical count in EN). The renderer
emits the target verbatim as a relative href (`lib/markdown_renderer_url_sanitizer.rb:6-10`,
`custom_markdown_renderer.rb:54-59`) and there is no `<base>` tag anywhere in `app/views` (grep). From
`/hc/lynomia-docs/articles/automation-rules-ar`, `href="automation-rules"` resolves against the directory to
`/hc/lynomia-docs/articles/automation-rules` — the English article. The three most-linked Arabic targets are
`the-whatsapp-24-hour-window` (33), `automation-rules` (33) and `roles-and-permissions` (30).

073 D2 found this and rated it major. I confirm the measurement and add the reason it is green in CI: the spec that
exists to catch broken cross-references validates key existence, not URL resolution, and its comment
(*"links only to articles that exist"*, `:31`) reads as though it validated the second. The SEO audit cannot see it at
all — internal link targets are not among its checks, and agent 076 filed no report.

### R11 — major — The production run's clean result cannot be attributed to any corpus.

`report` prints findings, two counts and a verdict (`:139-150`); the per-portal line prints the slug, the published
count and the locale list (`:46`). It prints **no commit, no corpus file count, no resolved origin host and no portal
set**. 073 R2 asks for the origin to be printed; nobody asked for the rest.

The reported run processed `38 + 19 + 67 = 124` articles and audited 124 published. The baseline tree has **126**
files, every one inside a manifest section (verified: all 12 manifest slugs exist as directories in both locales, 63
files each, so `seed_section`'s `next unless section[locale]` skips nothing and no directory is unlisted). 079 D10
proposes the `contact-lynomia-support` EN/AR pair (`48574e65`, 2026-10-12) as the delta, which I cannot confirm
without the run's timestamp. Either way: the sentence describes a corpus two files smaller than the one under review,
and nothing in the output would let anyone tell. **Severity major for process**, not for code.

### R12 — major, new — The `locale` field in the authoring form has no effect, and that is how check 7 becomes reachable.

`ArticleDashboard` exposes `locale: Field::Select.with_options(collection: Documentation::Library::LOCALES)`
(`article_dashboard.rb:20`) and includes it in `FORM_ATTRIBUTES` (`:36`). `Article#ensure_locale_in_article`
(`article.rb:200-206`) is a `before_validation` that sets `self.locale = category.locale` whenever a category is
present — and every seeded documentation article has one. The author's selection is discarded on every save.

The `category` field's scope is `Category.where(portal: Documentation::Library.portals)` (`article_dashboard.rb:15`)
with **no locale filter**, so the dropdown offers all 24 documentation categories in both languages. Moving the
Arabic `connect-woocommerce-ar` into the English `commerce` category silently flips its locale to `en`, which gives
its translation family two `en` members and makes `duplicate hreflang locales` (`:113`) fire — the mechanism 073
§3.1 asserts ("two published siblings with the same locale") without naming the only route to it. `associated_article_id`
is **not** in `FORM_ATTRIBUTES`, and the account API that does permit it
(`api/v1/accounts/articles_controller.rb:30,110`) is tenant-scoped and cannot reach an `account_id IS NULL` portal,
so 073's implied route does not exist. This is also a third field in the authoring surface that does nothing —
beside `meta['feature_image']` (070 §3.5) and the false `<title>` hint (070 §3.2c).

### R13 — confirmed — `search_indexing_spec.rb:110` does contradict the controller and `seo_spec.rb`. By reading, both specs cannot pass.

The brief asks this directly; 074 D2 asserts it. Confirmed, three ways:

```ruby
# spec/requests/search_indexing_spec.rb:104-111
describe 'robots.txt' do
  it 'blocks widget crawling while leaving other pages crawlable' do
    get '/robots.txt'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/plain')
    expect(response.body).to eq("User-agent: *\nDisallow: /widget\n")      # line 110
```

1. **Against the controller.** `RobotsController::DISALLOWED` is
   `['/widget', '/app/', '/super_admin/', '/api/', '/installation/']` (`robots_controller.rb:17`), and `body` emits
   `User-agent: *`, then one `Disallow:` per entry, then `Disallow: /hc/*?theme=`, then one `Sitemap:` line per
   non-archived portal (`:26-30`). The minimum possible body is **seven** lines, when no portal exists or
   `sitemap_lines` rescues (`:41-44`). The assertion expects two. It fails regardless of database state, so it is not
   order- or fixture-dependent.
2. **Against `seo_spec.rb`.** `spec/requests/documentation/seo_spec.rb:182-185,190,194-195` assert the presence of
   `Disallow: /app/`, `Disallow: /super_admin/`, `Disallow: /api/`, `Disallow: /hc/*?theme=`, `Sitemap: http` and
   `/hc/lynomia-docs/sitemap.xml` on the same endpoint. Every one of those strings is what makes line 110's equality
   false. The two files are mutually exclusive by construction, not by accident.
3. **Scope.** Both are `spec/requests/*`, neither carries an exclusion tag, and `search_indexing_spec.rb` is 113
   lines with no `pending`/`skip`.

074's reading is correct and its severity (major) is right. One addition it does not make: `seo_spec.rb:194`
(`Sitemap: http`) depends on `sitemap_lines` succeeding, which depends on the host arithmetic of R4 — so the spec
that proves robots.txt names a sitemap would also pass on the broken `https://hc/hc/…` output.

### R14 — the five cases the brief names: is each invisible, and what would catch it

| Case | Invisible to the audit? | Why | What would catch it |
|---|---|---|---|
| **A renamed slug leaving a live duplicate at the old slug** | **Yes, completely** | `content_seeder.rb:73` matches `find_or_initialize_by(slug: slug_for(key, locale), locale:)`, so a renamed slug no longer matches and a second article is created at the key's slug; nothing in `perform!` deletes (`:28-31,47-56`). Both rows then have a title, a description and a distinct canonical, so checks 1–10 all pass. `status` is forced to `published` on every run (`:101`), so unpublishing by hand does not survive. | A manifest-vs-database reconciliation: the set of `(slug, locale)` the manifest produces versus `Documentation::Library.articles.pluck(:slug, :locale)`. One query, corpus-level, and the audit is already the corpus-level place. 069, 070 §3.4, 074 D1 and 079 D1 all report the hazard; none proposes the diff as an audit check. |
| **An article orphaned from every index** | **Not reachable — the claim does not hold** | `_sidebar.html.erb:11,64-77` has an uncategorized block, filtered to the page locale, and `portal.html+documentation.erb:14-15` renders the sidebar on the home, every category page, every article page and the search results page. A published article with `category_id` nil is still internally linked from every page. What *is* invisible is 075 D9's two-crumb trail and missing "back to category" footer, and 079 D7's emptied category that stays a 200 soft-404. | The same manifest-vs-database diff, plus a `category_id IS NULL` warning. Not urgent: the state is currently unreachable through the seeder. |
| **A `DOC_ARTICLES` key resolving to nothing** | **Partly** — registry-vs-file is covered by a spec; registry-vs-database is not | See R9. `content_seeder_corpus_spec.rb:77-79` proves `slug ∈ EN file keys`. It does not prove `meta['doc_key']` survived a Super Admin save, that the row is `published`, or that the Arabic resolution lands on Arabic. | A runtime check in the audit: for every `DOC_ARTICLES` value, assert `Library.article_for(key, locale: 'en')` and `Library.article_for(key, locale: 'ar')` each return a published article in the requested locale. It reuses the existing door (`library.rb:54-57`) and needs the `meta->>'doc_key'` index that `01-current-system.md` §9.1 already asks for. |
| **Thin or duplicative content** | **Yes** — no word count, no similarity, no body check of any kind | The audit reads `title`, `description`, `meta`, `locale`, `category` and the association graph. `content` is never examined. | A word-count warning and a body-similarity report in the audit. Both are properties of the set, which is what the task is for. |
| **A sitemap advertising retired URLs** | **Yes, and the agreement the audit demonstrates is circular** | `sitemap.xml.erb:16` and `documentation_seo_audit.rake:50,69` both call `portal_canonical_url` over `portal.articles.where(status: :published)`. They are the same query through the same helper, so they agree *by construction*. The audit proving the canonicals are consistent proves nothing about whether those rows should exist. The audit also never issues an HTTP request for `/hc/:slug/sitemap.xml`, so the R4 500 and the `Content-Type` are unasserted anywhere. | Archiving in the seeder (074 R1, 079), plus the manifest-vs-database diff as its oracle. |

**The honest summary of the audit's reach**: it is a per-row validator of six attributes on one table. Every defect in
this report that matters is a property of a *template*, a *URL surface*, a *set*, or a *process* — and the task's own
header says it audits none of those, deliberately. The defect is not the task. It is `INDEXABLE` on line 148 and the
enforcement table in `01-current-system.md` §8.

### R15 — major — What breaks at scale, with the evidence

The brief asks for precision. These are the failures that are mechanical, not speculative.

**1. Every documentation page reads the whole corpus.** `_sidebar.html.erb:8-11`:

```ruby
sidebar_articles_by_category = order_articles.call(
  portal.articles.published.where(category_id: sidebar_categories.map(&:id))
).group_by(&:category_id)
uncategorized_articles = order_articles.call(portal.articles.published.where(category_id: nil, locale: locale))
```

No `select`, no limit, no cache. `SELECT *` includes `content` **and** `draft_content`. The layout renders it on every
page (`portal.html+documentation.erb:14-15`). Measured corpus body: **586,657 bytes** across 126 files (830,824
including front matter, per 077). So every documentation page view today reads ~0.6 MB of article bodies it renders
nothing from. At "several times over" — say 600 published articles — that is ~3 MB of row data per page view, on an
unauthenticated route whose only protection is the global 3000 req/min/IP throttle
(`config/initializers/rack_attack.rb:71`). The rendered nav also grows to 600 `<a>` elements on every page; DOM-size
and crawl-budget consequences are **observational**. 074 D3 and 073 §5.3 both costed the *sitemap* and neither costed
the sidebar, which is on 100% of page views rather than one XML endpoint.

**2. The sitemap is 2 queries per article, not 1.** `sitemap.xml.erb:18` calls `portal_locale_alternates` and `:21`
calls `portal_default_alternate_url`; both call `article_translation_family` (`documentation_helper.rb:44-60`), which
is **not memoized** (`:106-110`), and `includes(:root_article)` (`:14`) preloads the root but not
`root.associated_articles`. ~252 queries today, ~1,200 at 600 articles, uncached — no `expires_in`, `fresh_when` or
`Rails.cache` anywhere in `app/controllers/public/` except the tracking pixel (`articles_controller.rb:43`). 074 D3
says "about N+2"; it is about 2N.

**3. Search is linear in total corpus bytes, with no index and the wrong dictionary.** `pg_search_scope :text_search`
(`article.rb:94-109`) uses `against:` with no `tsvector_column`, so `to_tsvector` is computed per row per request;
`db/schema.rb:222-228` shows no GIN or tsvector index on `articles` (the TODO at `article.rb:89` says so). The
dictionary defaults to `:simple` — verified at
`vendor/bundle/ruby/3.4.0/gems/pg_search-2.3.6/lib/pg_search/features/tsearch.rb:179-181` — so there is no stemming in
either language and Postgres's `arabic` Snowball configuration is unused. 077 D4/D5 are correct. Agent 078
(synonyms, including Arabic and transliteration) filed no report, so nothing else covers the Arabic half.

**4. Uneven translation coverage turns the hreflang checks fully silent.** Parity is exactly 63/63 today, so every
article has a family of 2 and the alternates render. The moment coverage is uneven, `portal_locale_alternates` returns
`[]` for single-locale articles and `audit_alternates` returns `[]` at `:99` — **before** any check runs. The audit
produces no finding, no warning and no count. There is no coverage report, so nobody can see how many articles lost
their hreflang. The share of silent articles rises with the corpus.

**5. The first images will land on a path with nothing a crawler or a CWV budget needs.** Measured: **zero** corpus
files contain `![` or `<img` today, so the first image is also the first test of all of this.
`CustomMarkdownRenderer#image` (`lib/custom_markdown_renderer.rb:61-71`) emits:

```ruby
out(%(<img src="#{src}"))
out(' alt="', :children, '"')
out(%( title="#{escape_html(node.title)}")) if node.title.present?
out(%( style="width: #{width}; max-width: 100%; height: auto;")) if width
out(' />')
```

- `alt` is the Markdown link text, so `![](shot.png)` renders `alt=""`. Nothing requires alt text: not the renderer,
  not `Article` validations, not the authoring form, not the corpus spec, not the SEO audit.
- No `width`/`height` attributes and no `aspect-ratio` — only an inline `style` width, and only when the URL carries
  `?cw_image_width=Npx` (`:130-146`), which no corpus file does. A width with `height: auto` and no intrinsic
  dimensions still shifts. Layout shift on every image is mechanical.
- No `loading="lazy"`, no `decoding`, no `srcset`/`sizes`, no `fetchpriority`:
  `grep -rn 'loading="lazy"\|decoding=' app/views lib app/helpers` returns **nothing**.
- `MarkdownRendererUrlSanitizer::SAFE_DATA_IMAGE_PATTERN` (`lib/markdown_renderer_url_sanitizer.rb:4`) permits
  `data:image/(png|gif|jpeg|webp)`, so a base64 image lands inside `articles.content` — the column the sidebar loads
  on every page (point 1) and pg_search vectorises per request (point 3). One inlined screenshot multiplies both.
- The inline `style` also contradicts CLAUDE.md's Tailwind-only rule.

Agent 080 owned Core Web Vitals and image SEO and filed no report, so none of this is recorded elsewhere. 075 D5
notes correctly that there is nothing honest to put in a schema `image` yet.

**6. The server sends Arabic pages with no `dir`, so half the corpus has a guaranteed layout change.**
`portal.html+documentation.erb:2` emits `<html lang="<%= html_lang_attribute(I18n.locale) %>">` and nothing else.
`dir` is set by JavaScript at `app/javascript/portal/portalHelpers.js:153-162`, called from `initialize` (`:168`).
The sidebar and topbar carry direction-aware Tailwind variants that cannot apply until `dir="rtl"` exists
(`_sidebar.html.erb:15`: `ltr:left-0 rtl:right-0 … ltr:border-r rtl:border-l … max-md:ltr:-translate-x-full
max-md:rtl:translate-x-full`). That is 63 of 126 articles today and it grows with every Arabic file. No spec asserts
`dir`; the audit renders no page.

**7. `robots.txt` grows with tenants and the sitemap list is unscoped.** `robots_controller.rb:36` is
`Portal.where(archived: false)`, unordered, one `Sitemap:` line per portal, served by an
`ActionController::Base` subclass on every host including every portal's custom domain. So the documentation site's own
robots.txt is an enumerable directory of every customer's help-center slug. 074 D4 frames this as a product decision
about advertising tenant portals; the enumeration consequence and the cross-host service are not stated there. Google's
500 KiB robots.txt cap is **observational**.

**8. What does not break.** The sitemaps.org per-file caps (50,000 URLs / 50 MB uncompressed, **observational**) are
roughly 390× today's count and are not a threat at any plausible corpus size; one file per portal keeps them apart.
Description lengths have headroom: 0 of 126 files are outside 50–160 today. 070 is right that the 50–160 window is a
Latin-script heuristic and that no Arabic number has been stated — do not invent one.

### R16 — minor, new — Two more things in the SEO surface that nothing reads

- **`tracking_pixel` is referenced by no view and no JavaScript.** `grep -rn 'tracking-pixel\|tracking_pixel'`
  across `*.js`, `*.vue`, `*.erb`, `*.rb` (excluding `node_modules`) returns only `config/routes.rb:516` and
  `articles_controller.rb:7,35,46`. So `increment_view_count` (`article.rb:143-147`) is never called,
  `articles.views` stays NULL for every row, and `order_by_views` (`article.rb:87`) ties on every row — which makes the
  home's "Popular articles" block an arbitrary six (`portal_home_data.rb:18`) and
  `index_articles_on_views` (`schema.rb:228`) an index on a never-written column. The home page's only
  non-editorial internal-linking signal does not exist. Agent 076 owned internal linking and filed no report.
- **The documentation has no social image at all, and the spec asserts that state.**
  `set_og_image_url` returns `nil` when `OG_IMAGE_CDN_URL` is blank (`portal_helper.rb:3-5`), so
  `documentation_layout/articles/_meta_head.html.erb:49,58-61` emit `twitter:card = summary` and no `og:image`.
  `seo_spec.rb:57,65` assert exactly that — `not_to include('name="og:image"')` and
  `content="summary"` — so the one spec covering Open Graph proves correctness on a page with no image, and the
  `og_image_url.present?` branch has no coverage. Whether production configures `OG_IMAGE_CDN_URL` is **not checked**.
- **The audit `include`s its helpers into `Object`.** `include ActionView::Helpers::TagHelper`, `include
  DocumentationHelper`, `include PortalHelper` (`documentation_seo_audit.rake:30-32`) run inside the task block, where
  `self` is the Rake top-level object, so they land on `Object`; `audit_article` and friends (`:67-162`) are likewise
  defined as private `Object` methods. Harmless for a standalone invocation; a consideration if the task is ever
  chained into a deploy process that loads other tasks.

---

## 3. Survived

Claims and hypotheses I attacked and could not break. These matter as much as the refutations.

- **Thin and duplicative content.** I measured it, expecting to find the invisibility exploited. EN: 63 files, 330
  words minimum, p10 437, median 910, maximum 1,676, 53,975 total. AR: 264 / 339 / 769 / 1,394 / 44,924. Zero EN body
  pairs exceed 0.6 similarity (`difflib.SequenceMatcher.ratio` over front-matter-stripped bodies, with a 50% length
  prefilter). Nothing today is thin and nothing is a near-duplicate. The audit's blindness here is latent, not
  exploited. 077's figure of 830,824 total bytes is file bytes including front matter; body-only is 586,657.
- **The one reachable error check has nothing to report.** 0 of 126 files are missing a description, and 0 are outside
  the audit's 50–160 window. That, and not any enforcement, is why the run was clean.
- **Every `DOC_ARTICLES` value resolves to a corpus file.** All 62, no duplicates. 079 D10's hypothesis that
  `contact-lynomia-support` might be missing from production is about the *run*, not the tree — the file exists in
  both locales at baseline.
- **hreflang reciprocity holds for the whole current corpus.** `associated_article_id` is written only by the seeder
  (`content_seeder.rb:77`), only from the English root (`:90-92`), with English seeded first (`:42-45`). I could not
  construct a non-reciprocal pair, an orphan translation or a two-level chain through any path the seeder or the
  tenant API offers. 073's "latent" rating for the chain case is right.
- **An article orphaned from every index.** I tried; the sidebar's uncategorized block defeats it (R14).
- **The canonical never carries the reader's query string on documentation pages.** `portal_canonical_url` calls
  `generate_article_link(..., false, false)` (`documentation_helper.rb:16`), so `theme` and `show_plain_layout` can
  never leak into it. 073's §7 entry is correct.
- **Drafts are excluded three independent ways** — the sitemap filter (`sitemap.xml.erb:14`), the hreflang family
  filter (`documentation_helper.rb:108`) and the controller scope (`articles_controller.rb:80-83`) — and the
  super-admin preview exception carries a visible banner (`_draft_banner.html.erb:3-7`).
- **Corpus slugs are safe.** Every one of the 126 basenames matches `[a-z0-9-]`, there is no `-ar` collision, and no
  file name contains a dot — so 073's D10 routing hazard is latent, as it says.
- **No layout is applied to the sitemap.** `layouts/` contains `portal.html.erb`, `portal.html+documentation.erb` and
  `portal.html+plain.erb` and no `portal.xml.erb`, so the XML response carries no HTML chrome.
- **The audit is honest in its own header.** `documentation_seo_audit.rake:1-11` states that it audits data rather
  than templates and says why. Every refutation above is against the `INDEXABLE` verdict and against
  `01-current-system.md` §8's table, not against the task's design.

---

## 4. Not checkable

| What | What would be needed |
|---|---|
| Production `FRONTEND_URL` / `HELPCENTER_URL`, and whether the docs portal row has a `custom_domain`. R4's `https://hc/...` is therefore **unverified for production**. | A production environment read. Charter §3 forbids it. |
| Whether `OG_IMAGE_CDN_URL` is configured in production — i.e. whether any documentation page has a social image at all. | Same. |
| Which commit the reported run executed against, and therefore whether the 124-vs-126 delta is the `contact-lynomia-support` pair (079 D10). | The run's timestamp or a production read. R11 stands either way: the output records nothing. |
| Query counts, bytes per request and DOM sizes. Every figure in R15 is traced from source and from file measurement, not measured against a running server. | A server and a query log. Charter §6.1 forbids running anything. |
| Real HTTP behaviour: variant selection, the `/docs` → `/hc` → locale 302 chain, `nil.include?` raising on the sitemap, `.xml` format negotiation under an HTML-only `Accept` header, and whether `allow_any_instance_of` interacts with the unique index as I read it. | Execution. |
| Whether Googlebot executes `appendPlainParamToURLs` (R7), indexes `text/markdown` (R15 / 074 D6 / 073 D11), honours a cross-host `Sitemap:` directive, enforces a 500 KiB robots.txt cap, or penalises the DOM size R15 predicts. All **observational**. | Network reads of Google's documentation, which this brief did not authorise. |
| The right description window for Arabic. 070 is right that the 50–160 characters in `documentation_seo_audit.rake:18-19` is a Latin-script pixel heuristic. I did not find a stated Arabic number and did not invent one. | A normative source, or an explicit product decision. |
| Internal linking and related articles (076), synonyms including Arabic and transliteration (078), and Core Web Vitals and image SEO (080). **No report exists for any of the three.** R10, R15.5, R15.6 and R16 cover what I could read directly in each area; none of it is a substitute for those briefs. | Those agents, or a reassignment. |

---

## 5. What Agent 000 must arbitrate

1. **`0 SEO errors / INDEXABLE` must not be cited as evidence of indexability anywhere in Phase 2–4.** R1. Either the
   verdict line changes or `01-current-system.md` §8 and §10 must state which checks are falsifiable.
2. **`01-current-system.md` §7 says 87 `DOC_ARTICLES` keys; there are 62.** R8. Phase 2's coverage matrix is sized
   from that number.
3. **`070` §3.2(a) contradicts `070` §3.2(c).** R2. The four flagged files are the four worst, not four
   false positives, and 070 §4's proposed panel would measure the wrong string.
4. **073 §3.1 and 074 D5 / 073 D5 need re-rating.** R12 (check 7's only real route is category reassignment, not
   `associated_article_id`) and R7 (the plain-layout variant is a propagating mirror, not an unlinked page).
5. **Whose exit code is it?** R6. The audit and robots.txt both read `Portal.where(archived: false)` rather than
   `Documentation::Library.portals`, so tenant content gates a Lynomia release and tenant slugs are published in
   robots.txt. 074 D4 raises half of this; the shared exit code is the other half.
6. **076, 078 and 080 produced no report.** The gaps in R10, R15.5, R15.6 and R16 are unowned.
