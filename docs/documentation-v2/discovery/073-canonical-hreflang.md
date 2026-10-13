---
agent: 073
scope: canonical URLs and hreflang for documentation articles (host resolution, /docs redirect, -ar slug convention, draft/missing translations, x-default, growth)
confidence: medium
---

# 073 — Canonical URLs and hreflang

Method. "Measured" means I ran `grep`/`find` over the repository, or a standalone Ruby script (scratchpad, repo code not loaded) that re-types the four lines of `portal_absolute_url`. "Traced" means I followed the code path by reading and did not execute it, because the contract forbids running Rails. Nothing here was observed on a live server, and production environment values are unknown.

## 1. What exists today

### 1.1 The helpers

| Piece | Where | What it does |
|---|---|---|
| `portal_canonical_url(portal, article)` | `custom/app/helpers/documentation_helper.rb:15-17` | `portal_absolute_url(portal, generate_article_link(portal.slug, article.slug, false, false))`. The two `false` arguments drop theme and plain-layout, so no query string can reach the canonical (`app/helpers/portal_helper.rb:77-83`). |
| `portal_absolute_url(portal, path)` | `documentation_helper.rb:29-33` | `host = portal.custom_domain.presence \|\| ChatwootApp.help_center_root.to_s`; prepend `https://` if the string has no `://`; `chomp('/')` once; append the path. |
| `ChatwootApp.help_center_root` | `lib/chatwoot_app.rb:35-37` | `ENV.fetch('HELPCENTER_URL', nil) \|\| ENV.fetch('FRONTEND_URL', nil)`. |
| `portal_category_canonical_url`, `portal_home_url` | `documentation_helper.rb:19-26` | Same host rule. Path is `/hc/<slug>/<locale>/categories/<cat>` or `/hc/<slug>/<locale>`. |
| `portal_locale_alternates` | `documentation_helper.rb:44-49` | `[locale, canonical]` for every member of the translation family. Returns `[]` when the family has fewer than 2 members. |
| `portal_default_alternate_url` | `documentation_helper.rb:54-60` | x-default URL: the family member whose locale equals `portal.default_locale`, else `family.first`. `nil` when the family has fewer than 2 members. |
| `article_translation_family` (private) | `documentation_helper.rb:106-110` | `root = article.root_article \|\| article`; `[root] + root.associated_articles`; keep `status == 'published'`; `uniq`; `sort_by(&:locale)`. |
| `html_lang_attribute(locale)` | `portal_helper.rb:40-42` | `locale.to_s.tr('_', '-')`. This produces the hreflang value. |

The helper module is wired into every view by `config/application.rb:51` (`config.paths['app/helpers'] << 'custom/app/helpers'`).

### 1.2 The surfaces that emit the tags

| Surface | Emits canonical | Emits hreflang + x-default | Evidence |
|---|---|---|---|
| Article, documentation layout | yes | yes | `documentation_layout/articles/_meta_head.html.erb:7,11,19-24`, rendered by `articles/show.html+documentation.erb:2` |
| Article, `?show_plain_layout=true` | **no** | **no** | `articles/show.html+plain.erb:2` renders the classic `articles/_meta_head.html.erb:1-21`, which has no canonical or alternate and no `noindex` |
| Article, classic layout | no | no | same classic partial |
| Category, documentation layout | yes | no | `documentation_layout/categories/_meta_head.html.erb:8,11` |
| Portal home `/hc/<slug>/<locale>` | **no** | no | `portals/show.html+documentation.erb` has 0 `content_for :head` blocks (measured), so `layouts/_portal_head.html.erb:16-20` falls back to a bare `<title>` |
| `sitemap.xml` | `<loc>` | `xhtml:link` + x-default | `portals/sitemap.xml.erb:14-25`, same three helpers |
| `robots.txt` | n/a | n/a | `Sitemap:` lines for every non-archived portal (`robots_controller.rb:35-40`) |

### 1.3 Routes

- **Canonical shape.** `GET /hc/:slug/articles/:article_slug` carries no locale segment (`config/routes.rb:519`). The slug carries the language through the `-ar` suffix.
- **Stable alias.** `GET /docs/:article_slug` (`config/routes/documentation.rb:25-26`) resolves in `DocumentationController#article` (`custom/app/controllers/documentation_controller.rb:18-26`) and then calls `redirect_to "/hc/<portal>/articles/<slug>"`. That is the default HTTP 302, with a relative target.
- **Markdown twin.** `GET /hc/:slug/articles/:article_slug.md` (`config/routes.rb:517`) is linked from every article page (`documentation_layout/articles/_actions.html.erb:3`).

### 1.4 How the family is built

The seeder gives English the slug `key` and every other locale `key-<locale>` (`content_seeder.rb:85-87`). It sets `associated_article_id` of non-default locales to the English article with `slug = key` (`content_seeder.rb:77,90-92`). Hreflang pairs are read from that column, never from the suffix (`documentation_helper.rb:35-40`).

## 2. Measured behaviour

### 2.1 Canonical host resolution (standalone re-implementation of `portal_absolute_url`)

Path used: `/hc/lynomia-docs/articles/connect-woocommerce`.

| `custom_domain` | `HELPCENTER_URL` | `FRONTEND_URL` | Canonical emitted | `start_with?('http')` (the audit's host check, `documentation_seo_audit.rake:71`) |
|---|---|---|---|---|
| nil | unset | `https://app.lynomia.com` | `https://app.lynomia.com/hc/...` | pass |
| nil | unset | `https://app.lynomia.com/` | `https://app.lynomia.com/hc/...` | pass |
| nil | unset | `https://app.lynomia.com//` | `https://app.lynomia.com//hc/...` | pass |
| nil | unset | `app.lynomia.com` | `https://app.lynomia.com/hc/...` | pass |
| nil | unset | `https://app.lynomia.com/app` | `https://app.lynomia.com/app/hc/...` | pass |
| nil | unset | `http://0.0.0.0:3000` (`.env.example:17`) | `http://0.0.0.0:3000/hc/...` | **pass** |
| nil | unset | unset | **`https://hc/lynomia-docs/articles/...`** | **pass** |
| nil | `""` (set, empty) | `https://app.lynomia.com` | **`https://hc/lynomia-docs/articles/...`** | **pass** |
| nil | `https://docs.lynomia.com` | `https://app.lynomia.com` | `https://docs.lynomia.com/hc/...` | pass |
| `docs.lynomia.com` | any | any | `https://docs.lynomia.com/hc/...` | pass |

Two rows are not what the source reads like:

- **Both unset gives host `hc`, not an empty host.** `"https://"` already contains `://`, `chomp('/')` removes its trailing slash, and the path's leading slash then supplies `//`, so the result is `https://hc/lynomia-docs/...`. It is a syntactically valid URL with a host called `hc`.
- **An empty `HELPCENTER_URL` shadows `FRONTEND_URL`.** The empty string is truthy in Ruby, so the `||` in `chatwoot_app.rb:36` never falls through to `FRONTEND_URL`. A `.env` line `HELPCENTER_URL=` therefore produces the `hc` host even when `FRONTEND_URL` is correct.

### 2.2 The host is never taken from the request

`portal_absolute_url` does not read `request.host`. A page served at `app.<host>` and at `docs.<host>` both canonicalise to the one configured origin. That is the correct property. It also means the wrong origin is wrong on every surface at once: `rel=canonical`, hreflang, `og:url`, JSON-LD `url`, sitemap `<loc>` and the robots `Sitemap:` line. `robots_controller.rb:37-39` carries its own copy of the same rule.

### 2.3 What a wrong or unset origin does to a request (traced)

- **Article, category and home pages.** `ensure_custom_domain_request` (`app/controllers/public_controller.rb:9-20`) returns a **401 JSON** unless the request host equals the host parsed from `FRONTEND_URL` or `HELPCENTER_URL` (`app/controllers/concerns/domain_helper.rb:2-4`), or equals a portal's `custom_domain`. So with both variables unset, pages fail loudly.
- **Sitemap and robots.** `before_action :ensure_custom_domain_request, only: [:show]` (`app/controllers/public/api/v1/portals_controller.rb:4`) excludes `sitemap`, and `RobotsController` has no such gate. They render with the `https://hc/...` origin.
- **The audit.** `lynomia:docs:seo_audit` runs in the operator's shell environment. If that shell lacks the web process's variables, it computes `https://hc/...`, passes `start_with?('http')`, and prints `INDEXABLE`.
- **A latent 500 on the sitemap.** The `sitemap` action runs `@help_center_url = @portal.custom_domain || ChatwootApp.help_center_root`, then calls `@help_center_url.include?('://')` (`portals_controller.rb:18-20`). With both variables unset and no `custom_domain` that is `nil.include?`, so `NoMethodError` and a 500. The variable is never read by `sitemap.xml.erb` (`grep help_center_url` finds only these three lines), so the code is dead except for the crash.

### 2.4 Translation shapes (traced from `documentation_helper.rb:44-60,106-110`; spec at `spec/requests/documentation/seo_spec.rb:93-129`)

| State | Output on the English page | Output on the Arabic page |
|---|---|---|
| EN published, AR published | `hreflang=en`, `hreflang=ar`, `x-default` (EN URL) | same set |
| EN published, AR draft | no hreflang, no x-default, canonical only | AR page 404s to the public (`articles_controller.rb:80-83`) |
| EN published, AR does not exist | same as above | n/a |
| EN draft or unpublished, AR published | EN page 404s | AR page has a family of 1, so no hreflang and no x-default |
| AR published, no EN row (seeder sets `associated_article_id` nil) | n/a | orphan, no hreflang, no signal anywhere |
| Super Admin previews a draft AR | n/a | AR is not in its own family (`status == 'published'` filter), so no self-reference; not public |

### 2.5 Corpus (measured)

- 63 EN and 63 AR files, every basename present in both, in the same section, no duplicate key across sections.
- No key ends in `-ar` or `-en`, so the global-unique-slug collision (`key` vs `other-key-ar`) cannot occur today.
- Every file basename matches `^[a-z0-9][a-z0-9-]*$`.
- Every article has `tags`, `seo_description`, `description`, `title`, `position`; 28 of 126 have `seo_title`.

## 3. Defects

| # | Severity | Defect | Impact | Evidence |
|---|---|---|---|---|
| D1 | major | The origin has no validation. Unset variables, an empty `HELPCENTER_URL`, or the shipped placeholder `http://0.0.0.0:3000` all produce well-formed absolute URLs on the wrong host and pass the audit. | If the web process carries a wrong value, every canonical, hreflang, sitemap `<loc>` and `Sitemap:` line points at the wrong host. A sitemap whose entries are on a different host than the sitemap file is ignored by crawlers (general crawler behaviour; I did not fetch Google's documentation, which this brief did not authorise). The audit reports `INDEXABLE`. Production values are unverified, so whether this is live is unknown. | §2.1, §2.3; `.env.example:17,19`; `app.json` placeholder `https://CHANGE.herokuapp.com`; `lib/chatwoot_app.rb:36` |
| D2 | major | **All 494 internal links in the Arabic corpus are bare English keys** (`](automation-rules)`). Zero end in `-ar`. EN also has 494. The renderer does not rewrite links by locale (`lib/custom_markdown_renderer.rb:54-59`, `lib/markdown_renderer_url_sanitizer.rb:6-10`) and no `<base>` tag exists in the portal views (measured). | From `/hc/lynomia-docs/articles/foo-ar`, `href="automation-rules"` resolves to `/hc/lynomia-docs/articles/automation-rules`, the English article. Every body link in an Arabic article leaves Arabic. The hreflang pairing is correct, but the `-ar` convention is honoured only by hreflang. For a key that exists only in Arabic (slug `key-ar`), the same bare link is a 404. | `grep -rhoE "\]\([^)]*\)" ar \| wc -l` = 494, `-ar` targets = 0; e.g. `ar/whatsapp/whatsapp-templates.md:9,94,123-125` |
| D3 | major (editor upgrade), not reachable today | There is **no way to link a translation by hand.** `ArticleDashboard::FORM_ATTRIBUTES` has no `associated_article_id` (`custom/app/dashboards/article_dashboard.rb:36`). The model forces `locale` from the category (`app/models/article.rb:200-206`). The only code that writes the association for platform content is the seeder (`content_seeder.rb:77`). | Every translation authored in Super Admin is an unlinked orphan with no hreflang. The editor work will create exactly those articles. | files cited |
| D4 | major | The audit gives false assurance. Four of its five canonical and hreflang checks cannot fail on a published article (see §3.1). The host check is `start_with?('http')`. There is no coverage, orphan, locale-draft or slug-format check, and the audit does not print the origin it resolved. | `0 SEO errors / INDEXABLE` says nothing about host, pairing or coverage. `01-current-system.md` §8 lists these as enforced errors; as written they are unfalsifiable. | `lib/tasks/documentation_seo_audit.rake:50-57,71,98-114` |
| D5 | minor | `?show_plain_layout=true` renders a head with **no canonical, no hreflang and no `noindex`**, and robots only disallows `?theme=` (`robots_controller.rb:28`). | A crawlable duplicate of every article if anything links to it. Public pages do not link to it; the Super Admin Preview redirect does (`custom/app/controllers/super_admin/articles_controller.rb:24`). The helper comment at `documentation_helper.rb:12-13` ("whatever query string or layout variant") overstates this. | §1.2 |
| D6 | minor | Portal home pages have no canonical, description, Open Graph or hreflang. Category pages have a canonical but no hreflang, and the seeder never sets `associated_category_id` (`content_seeder.rb:58-64`). The language switcher links to the other locale's home, not to the article's sibling (`documentation_layout/_topbar.html.erb:57`). | The two most-linked pages per language are not declared as alternates. A reader switching language leaves the article they were reading. | §1.2 |
| D7 | minor | x-default falls back to `family.first`, and the family is sorted by locale string (`documentation_helper.rb:58,109`). With the English root unpublished and 3 or more locales, x-default would be the alphabetically first locale. | Unreachable with 2 locales (a family of 1 returns `nil` first). Wrong with a third language. | `documentation_helper.rb:54-60` |
| D8 | minor | hreflang and sitemap ignore the portal's `draft_locales`. A locale hidden from the switcher (`app/models/portal.rb:128-141`, `_topbar.html.erb:44,55`) is still advertised when its articles are published. No controller blocks a draft locale (grep for `draft_locale` in `app/controllers`: none). | Staged launch of a new language would leak an unfinished locale into hreflang and the sitemap. Unused today. | cited |
| D9 | minor | `/docs/:slug` drops the reader's language. `Library.article_for(key, locale: params[:locale])` (`custom/app/controllers/documentation_controller.rb:22`) only sees `?locale=`, but the registry builds `${DOCUMENTATION_URL}/${slug}` with no locale (`app/javascript/dashboard/helper/documentationLinks.js:102-107`), and `DOCUMENTATION_URL` defaults to `/docs` (`config/installation_config.yml:53-56`). `find_by(locale: nil)` matches nothing, so every contextual link resolves to English. | An Arabic-UI dashboard user always lands on the English article. `docs/global-documentation/12-contextual-help.md:51` promises otherwise. | cited |
| D10 | minor | `Article.slug` has no format validation, only an exclusion list (`app/models/article.rb:69`). The canonical is not percent-encoded and goes verbatim into the sitemap (`sitemap.xml.erb:16`). | A slug with a dot (e.g. a changelog `release-1.2.0`) is parsed by `hc/:slug/articles/:article_slug` (`routes.rb:519`) as slug plus format by Rails' default segment rule (traced, not executed), so the canonical is an unroutable URL. A space or non-ASCII slug yields an unencoded `<loc>`. All 126 corpus keys are safe today (§2.5). | cited |
| D11 | minor | The Markdown twin `/articles/<slug>.md` is the same content as `text/markdown`, linked from every article page, with no canonical `Link` header and no robots rule. Its host comes from `public_portal_article_markdown_url` (a route helper), a different rule from `portal_absolute_url`. | Possible duplicate indexing. Whether a crawler indexes `text/markdown` is unverified. | `articles_controller.rb:29-33`; `_actions.html.erb:3` |
| D12 | minor | Test gap. `seo_spec.rb:14-17` sets `custom_domain`, so the `help_center_root` branch of `portal_absolute_url` is never exercised. `global_ownership_spec.rb:36` sets the variables only to pass host acceptance. There is no `DocumentationHelper` spec. | The behaviour in §2.1 is untested. | `grep -rn help_center_root spec`: none |

### 3.1 Which audit checks can fail

| Audit check | Can it fail? | Why |
|---|---|---|
| Two articles share a canonical (`rake:50-57`) | No in production | `articles.slug` has a global unique index (`article.rb` schema header, `index_articles_on_slug`); the spec has to stub `slug` to trigger it (`task_documentation_seo_audit_spec.rb:50-56`) |
| Canonical has no host (`rake:71`) | Almost never | Only a value that does not start with `http`, e.g. a leading space (§2.1) |
| hreflang set lacks the article itself (`rake:102-103`) | No | A published article is always in `root.associated_articles` or is the root |
| hreflang set has no x-default (`rake:104`) | No | `portal_default_alternate_url` is non-nil whenever the family has 2 or more members |
| Duplicate hreflang locales (`rake:109-114`) | Yes | Two published siblings with the same locale |
| Title and description length | Yes (warn) | n/a |

The header comment promises reciprocity ("points back", `rake:5,95-96`). It is true by construction only for a one-level family. A two-level chain (AR points to FR, FR points to EN) yields non-reciprocal sets that all pass. The seeder and the account API (`Article.find_root_article_id`, `article.rb:136-138`) never build one, so I rate it latent.

## 4. The questions asked

**Does `/docs/:slug` compete with the `/hc/...` canonical?** No, with caveats.

- It is a 302 to the canonical path (`documentation_controller.rb:25`).
- It is not in the sitemap.
- No corpus file links to `/docs/...` (0 of 988 links, measured).
- Every `rel=canonical` points at `/hc/<portal>/articles/<slug>`.
- **302 is the right status**, not a defect: the alias exists to survive slug and portal changes, and a 301 would be cached by browsers.
- The redirect target is host-relative, so it lands on whichever host served `/docs`, and the canonical then consolidates. That costs one extra hop.
- `/docs` itself is two hops (`/hc/<slug>` then the locale redirect, `portals_controller.rb:30-35`).
- The real problems are the lost language (D9) and the unredirected old slugs (§5, item 4).

**Does `-ar` produce correct hreflang pairs?** Yes, for hreflang, and by construction. Pairs come from `associated_article_id`, so a suffix typo cannot pair the wrong articles. The collision risks are in the slug column, not in hreflang: a key `X-ar` in English would take the slug `X-ar` that the Arabic `X` needs. This is currently impossible (§2.5) and nothing enforces it. In a sync with no transaction (`01-current-system.md` §3) that would be a unique-violation partway through. The convention is **not** honoured by body links (D2).

**Draft or missing translation?** Handled correctly and symmetrically (§2.4). The one gap is the portal-level draft locale (D8).

**Is x-default correct?** For two locales, yes: it names the English article, which is `portal.default_locale`, and it duplicates the `en` URL, which is permitted. The `family.first` fallback is the wrong rule for 3 or more locales (D7).

## 5. What a larger corpus breaks

Today every hreflang set is the same shape (`en`, `ar`, `x-default`), because parity is exactly 63/63. At several hundred articles with uneven coverage the following change.

1. **The uncommon shapes become the common ones.** English-only pages (no tags), Arabic-only orphans (no tags, no audit signal) and pairs will coexist. The code handles each shape. The spec covers only single, pair and draft-translation. The audit has no coverage report, so nobody can see how many articles have no sibling.
2. **Bare-key links turn into 404s.** The convention assumes every key exists in English with `slug = key`. An Arabic-only key has slug `key-ar`, so any bare link to it is a 404, and no English page can link to it at all (D2).
3. **The sitemap gets a query per article.** `sitemap.xml.erb:14` preloads `:root_article` only; `root.associated_articles.to_a` (`documentation_helper.rb:108`) then issues about one query per article. Roughly 125 queries now and several hundred later, per unauthenticated request, uncached (no cache code in `app/controllers/public` apart from the tracking pixel's `expires_in`). The audit's `includes(:category, :root_article, :associated_articles)` (`rake:45`) has the same gap on the translation side. Traced, not measured.
4. **Renames duplicate content.** The seeder deletes nothing (`01-current-system.md` §3) and there is no old-slug redirect. A key rename during information-architecture work leaves the old English and Arabic articles published beside the new ones. Different canonicals, same text, no audit error. The number of such events scales with restructuring.
5. **A third locale breaks three assumptions.** `Documentation::Library::LOCALES` is hard-coded to `%w[en ar]` (`library.rb:14`), so the seeder will not write it. Slugs become `key-fr`, or `key-pt_BR` with an uppercase letter and underscore that the `/docs` slug constraint rejects (`config/routes/documentation.rb:26`). The x-default fallback picks the wrong locale (D7).
6. **Staged language launches leak** because hreflang ignores `draft_locales` (D8).
7. **Hand-authored content has no translation link** (D3), so the share of articles with hreflang falls as authoring moves into Super Admin.
8. **The audit's blind spots scale with the corpus** and its unfalsifiable checks keep passing (D4).
9. **Categories and homes** stay un-alternated (D6), and category pairing would need `associated_category_id`, which nothing sets.

## 6. Recommendations

Each extends an existing system; none adds an engine.

| # | Recommendation | Extends |
|---|---|---|
| R1 | Make `portal_absolute_url` fail loudly: raise on a blank origin, an empty `HELPCENTER_URL` (use `.presence` in `ChatwootApp.help_center_root`), or a loopback / `0.0.0.0` / dotless host in production. Delete the dead `@help_center_url` (`portals_controller.rb:18-20`) and have `RobotsController` call the one helper. | `DocumentationHelper`, `ChatwootApp`, CLAUDE.md "fail loudly" rule |
| R2 | Make the audit print the resolved origin and error unless it is `https` with a dotted host. Add falsifiable checks: orphan (non-default locale with nil `associated_article_id`), family depth greater than 1, article in a portal `draft_locale`, slug not matching `/\A[a-z0-9][a-z0-9-]*\z/`, EN/AR coverage counts (warn), same title and body under two keys. Drop or label the unfalsifiable checks. | `lynomia:docs:seo_audit` |
| R3 | Resolve body links per locale: send bare keys through `Library.article_for(key, locale: article.locale)` (it already falls back locale, then English, then slug), either at seed time or in `CustomMarkdownRenderer#link`. Route the decision to 076. | `Documentation::Library`, `CustomMarkdownRenderer` |
| R4 | Phase 4 decision: how a translation is linked when authors work in Super Admin. Either add `associated_article_id` to `ArticleDashboard`, scoped to default-locale articles of the same portal and normalised by `Article#associate_root_article` (`article.rb:125-133`); or use `meta['doc_key']`, already on every seeded article (`library.rb:55`), as the explicit group key (then it needs the index from `01-current-system.md` §9). | `ArticleDashboard`, `Article` |
| R5 | Filter alternates by `portal.public_locale_codes` as well as `published`. Emit x-default only when the `portal.default_locale` sibling is published; otherwise omit it. Add a head to the portal home with canonical and hreflang between `/hc/<slug>/en` and `/ar`, using `portal_home_url`. | `DocumentationHelper`, `Portal#public_locale_codes` |
| R6 | Sitemap: load families in one pass (a hash by root id) and cache by the maximum `updated_at`. Route to 074. | `PortalsController#sitemap`, Rails cache |
| R7 | Keep `/docs/:slug` as a 302. Pass the dashboard locale (`?locale=`) from `documentationArticleUrl`. Route redirects for retired or renamed slugs to 079. | `documentationLinks.js`, `DocumentationController` |
| R8 | Stop indexing the plain variant: add `Disallow: /hc/*show_plain_layout=` beside the existing `?theme=` rule, or a `noindex` in the plain head. Decide `.md` twin handling (`Link: rel=canonical` or `X-Robots-Tag`) with 074 and 098. | `RobotsController::DISALLOWED` |
| R9 | Validate the slug format for platform portals in the seeder and the dashboard, and percent-encode the path in `portal_absolute_url`. | `Article` validations, `ContentSeeder` |
| R10 | Add a `DocumentationHelper` spec covering the §2.1 table, using `with_modified_env`. | `spec/helpers` |

## 7. Survived

I tried to break these and could not:

- **Canonical stays clean.** The canonical carries no `theme` or `show_plain_layout` for documentation-layout pages (`portal_helper.rb:77-83` with both flags `false`).
- **One function, six surfaces.** Canonical, hreflang, `og:url`, JSON-LD `url`, sitemap `<loc>` and the audit all call `portal_canonical_url`, so they cannot disagree on the article URL.
- **A draft translation is never announced.** The family filter and the controller scope agree (`documentation_helper.rb:108`, `articles_controller.rb:80-83`).
- **No cross-host duplicate.** Because the host never comes from the request, the app-host and docs-host copies of a page canonicalise to one origin (§2.2).
- **A wrong host is loud for pages.** `ensure_custom_domain_request` 401s an unknown request host (`public_controller.rb:9-20`).
- **`lastmod` is stable.** View counts use `update_column` (`article.rb:144-148`), so `updated_at`, and therefore `<lastmod>`, does not churn per page view.
- **English seeds first** (`content_seeder.rb:42-45`), so `associated_article_id` is non-nil for every file pair in the current corpus.
- **Corpus slugs are safe**, with no `-ar` collision and every basename matching `[a-z0-9-]` (§2.5).

## 8. Not checked

- The production values of `FRONTEND_URL` and `HELPCENTER_URL`, and whether the docs portal row has a `custom_domain`. I may not read production data.
- Real HTTP responses. Nothing here ran a server, and Rails behaviours (302 default, dotted-segment parsing, `nil.include?`) are from reading.
- A CDN in front of the app. Nothing in the repository caches the pages; an external cache would make hreflang changes lag.
- How Google treats `text/markdown`, a cross-host sitemap, or a 302 alias long term. The brief did not authorise external research.
- Query counts, which are inferred from the code.
- The tenant (classic layout) portals, which emit no canonical at all. They are out of this program's scope.
- `hreflang` language-region granularity (`ar` vs `ar-KW`). The prior record decided language-only, deliberately (`docs/product-refinement/03-documentation-seo.md` §3.5).

## 9. Hand-offs

| To | Item |
|---|---|
| 076 | D2 and R3: bare-key links resolve to English from Arabic pages, and 404 for Arabic-only keys. |
| 074 | Sitemap query-per-article, `robots.txt` listing every non-archived portal (tenant portals included, `robots_controller.rb:36`), `.md` twin, plain-variant disallow. |
| 079 | Renamed-key duplicates, old-slug 404s, the `/docs` alias. |
| 097 | Unique-slug violation mid-sync with no transaction; `status` forced to published re-announces a sibling an operator had unpublished. |
| 098 | D4: audit unfalsifiability and the `INDEXABLE` claim. |
| Orchestrator, Phase 4 | R4: translation-linking mechanism, tied to the source-of-truth decision. Also amend `01-current-system.md` §8: the x-default and self-inclusion checks listed there cannot fail. |
