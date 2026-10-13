---
agent: 079
scope: 404s, redirects and article retirement on the public documentation portal, and the lifecycle the program needs to rename, split, merge and retire articles
confidence: high
---

Read-only, repository evidence. Nothing was executed (no rails, rspec or rake, per §6.1). Status codes below are
taken from the controllers and confirmed against the existing request specs where one exists; where a claim rests
on code reading alone it says so.

## 1. What exists today

### 1.1 What the portal answers for each kind of miss

The public portal is the Help Center's own: `GET /hc/:slug/...` (`config/routes.rb:508-519`). Two things decide
every row below. `Public::Api::V1::Portals::BaseController` declares `around_action :set_locale` first
(`base_controller.rb:7`), so it runs before any `before_action` of the child controllers. And `PublicController`
includes `RequestExceptionHandler` but never wraps its actions in `handle_with_exception`
(`public_controller.rb:3-5`; that wrapper is only an `around_action` on `ApplicationController`,
`application_controller.rb:12`). A bare `find_by!` in a public portal controller therefore raises
`ActiveRecord::RecordNotFound` straight into Rails' exceptions app: `config.exceptions_app` is not set anywhere
under `config/` and production has `consider_all_requests_local = false` (`production.rb:14`), so the response is
the **static `public/404.html`** with status 404, not the portal-branded page. Sentry ignores that exception by
default (`vendor/bundle/ruby/3.4.0/gems/sentry-rails-5.19.0/lib/sentry/rails/configuration.rb:47`; `config/initializers/sentry.rb:10` only adds two exclusions).

| Request | Path through the code | Status | Body | Evidence |
|---|---|---|---|---|
| **Unknown article slug**, known portal | `switch_locale_with_article` finds no row by `Article.find_by(slug:)` (any portal, any status) and calls `render_404 && return` | **404** | portal-branded `error/404.html.erb` in the portal layout | `base_controller.rb:40,53-57,70-75`; `articles_controller_spec.rb:140-143` |
| **Unknown portal** (any article/category/home URL) | `Portal.find_by!(slug:, archived: false)` raises | **404** | static `public/404.html` | `base_controller.rb:35`, `portals_controller.rb:25-28` |
| **Unknown portal on a foreign host** (home/index/show only) | `ensure_custom_domain_request` finds no portal for the host | **401** JSON "Domain ... is not registered" | JSON | `public_controller.rb:9-20` |
| **Draft article**, anonymous | the base lookup finds the row (it is not status-scoped), then `set_article` scopes `.published` and `find_by!` raises | **404** | static `public/404.html` | `articles_controller.rb:80-83`; `global_ownership_spec.rb:68-71`; `articles_controller_spec.rb:133-138` |
| **Draft article**, signed-in super admin | `set_article` uses `@portal.articles` (all statuses) | **200** with a draft banner | the page | `articles_controller.rb:81,85-88`; `_draft_banner.html.erb:3`; `global_ownership_spec.rb:90-95` |
| **Archived article**, anonymous | identical to draft: `published` scope excludes it | **404** | static `public/404.html` | `article.rb:75`; `articles_controller.rb:81` (no spec asserts the HTML page for `archived`; the `published` scope is the same one the draft spec exercises) |
| **Draft / archived / unknown `.md`** | `set_article` raises first; `show_markdown` also guards `published?` | **404** | static page or empty | `articles_controller.rb:8,29-33`; `articles_controller_spec.rb:169-181` |
| **Article slug that belongs to another portal** | base lookup is global so it passes; `@portal.articles` scope misses | **404** | static `public/404.html` | `base_controller.rb:54`, `articles_controller.rb:82` (code reading) |
| **Unknown category** on its page | `find_by(locale:, slug:)` is nil, then `render_404` | **404** | portal-branded | `categories_controller.rb:24-29` |
| **Unknown category** on `/hc/:slug/:locale/categories/:cat/articles` | `index` is excluded from `set_category` and `list_params` omits `category_slug`, so the slug is ignored | **200**, the whole locale's article list | list | `articles_controller.rb:7,99-103` (code reading, not executed) |
| **Emptied category** (all its articles unpublished or gone) | the category row still exists, the documentation view renders its empty state | **200** | empty state | `categories_controller.rb:25`; `categories/show.html+documentation.erb:13-14` |
| **Unknown locale** on the portal home, e.g. `/hc/lynomia-docs/xx` | `@locale = params[:locale]` is used verbatim; nothing checks `allowed_locales` | **200**, empty home | empty lists | `portals_controller.rb:25-28`, `base_controller.rb:45-50` (code reading) |
| **Categories index** `/hc/:slug/:locale/categories` | the portal's only 301 | **301** to the locale home | none | `categories_controller.rb:13` |

So there are two different "not found" pages inside `/hc/`: the branded one (only when no row carries that slug,
or the category is unknown) and the static one (every `find_by!` miss, which includes every draft and archived
article). Both are 404.

### 1.2 `DocumentationController#article` for an unresolvable key

`GET /docs/:article_slug` (`config/routes/documentation.rb:25-26`, slug constrained to `[a-z0-9][a-z0-9\-_]*`):

- No docs portal: `render plain: I18n.t('documentation.not_set_up'), status: :not_found` (`documentation_controller.rb:20,36-38`) -- **404**, plain text body. Specced at `entry_points_spec.rb:90-95`.
- Portal present, key unresolved: `return head :not_found if article.blank?` (`documentation_controller.rb:22-23`) -- **404 with an empty body**. Specced at `entry_points_spec.rb:65-69` and `global_ownership_spec.rb:78-86` (unknown key, and a key whose only article is a draft).
- Resolved: `redirect_to "/hc/#{portal.slug}/articles/#{article.slug}"` (`documentation_controller.rb:25`). `redirect_to` with no `status:` is Rails' default **302**, which is right for a stable product address: the `/docs/<key>` URL stays the address, `/hc/...` stays the indexed one.
- Resolution is `Library.article_for(key, locale: params[:locale])`: published, `meta->>'doc_key' = key`, preferring the requested locale, then `en`, then any, then the key as a literal published slug (`library.rb:54-57`). `Library.articles` is `Article.published` (`library.rb:42-44`), so a draft **and an archived** article are invisible to it. An unresolved key costs four queries (`library.rb:55-56`: locale, default locale, `.first`, slug), three of them on the un-indexed `meta->>'doc_key'`.
- Route-level misses (a slug with an uppercase letter or a dot) never reach the controller; they are a Rails routing 404.

### 1.3 Is there any redirect mechanism for a renamed slug?

**No.** Searched, with these results:

| Place | Result |
|---|---|
| Models / tables | no `Redirect` model, no redirects or slug-history table: `db/schema.rb` has nothing matching `redirect`, `slug_hist` or `friendly`; `articles.slug` is a single column with a unique index (`schema.rb:226`) |
| Gems | no `rack-rewrite`, `friendly_id` or similar in `Gemfile` / `Gemfile.lock` |
| Rack / config | no rewrite middleware in `config/application.rb`, `config/initializers/*.rb` or `config/environments/production.rb` |
| Routes | no `redirect(...)` route in `config/routes.rb` or `config/routes/*.rb` |
| nginx | `deployment/nginx_chatwoot.conf` is a sample (`server_name chatwoot.domain.com`, lines 15 and 26) with one `location /` that proxies everything to the app (33-50) and one `return 301` for http to https (20). No rewrite or map. `deployment/deploy.sh` never mentions nginx (grep), so nothing in the release pipeline could ship an nginx rule |
| Article model | no slug history; the seeder keys on `(slug, locale)` (`content_seeder.rb:73`), so a renamed key is a **new row** |

The only redirects that exist are `/docs` and `/changelog` to the portal home (`documentation_controller.rb:30-34`), `/docs/:key` to the article (302), the portal's locale redirect `hc/:slug` to `hc/:slug/:default_locale` (`portals_controller.rb:30-35`, 302) and the categories index 301.

### 1.4 What the seeder does about a file that no longer exists: nothing

`perform!` iterates `manifest['sections']` and, per locale, globs the files that **exist** (`content_seeder.rb:28-31,47-56`). There is no comparison of the database to the file set anywhere in the class. No spec covers deletion, orphans or `archived` (`content_seeder_spec.rb` grep for delet/remov/orphan/archiv returns only the temp-dir cleanup and two `status` assertions). `git log --name-status -- custom/db/documentation` shows 127 adds, 39 modifications, **0 deletions, 0 renames**: no article has ever been retired, so the gap has never been hit and nothing was built for it.

Consequences, each read from the code:

- Delete a file: the row stays published, indexable, in the sitemap and in search, forever.
- Rename a key (file `a.md` to `b.md`): `b` is created, `a` stays published. Two live articles, same text, two different canonicals -- the SEO audit's duplicate-canonical check (`lib/tasks/documentation_seo_audit.rake:50-58`) cannot see it because the URLs differ.
- Archive or unpublish in Super Admin while the file still exists: reverted at the next sync, because `status` is forced on every run (`content_seeder.rb:101`). Super Admin has `publish` and `unpublish` (to **draft**) and no retire action (`custom/app/controllers/super_admin/articles_controller.rb:10-18`), though the status select offers `archived` (`article_dashboard.rb:23`).
- Move a file between sections (same key): the row is found by slug, so the URL does not change, but `category` is reassigned and `after_save :category_id_changed_action` then recomputes `position` as max+10 in the new category (`article.rb:73,188-198,215-228`), discarding the file's `position` until the next run. By code reading; this is the same lifecycle (RELOCATE) and converges only on the second sync.
- Remove a section from `manifest.yml`: categories are only ever upserted (`content_seeder.rb:58-64`), so the category row and its public page survive (200, empty state, see 1.1).

### 1.5 A `DOC_ARTICLES` key whose article is retired: what the product link resolves to

The chain, link by link:

1. `docsLink(key)` calls `documentationArticleUrl(brandLink('documentation'), key)` (`useBranding.js:64-65`; `documentationLinks.js:102-107`). The base is the installation's `DOCUMENTATION_URL`, which `PortalSeeder` fills with `/docs` only when blank (`portal_seeder.rb:26,38-46`). The URL is `/docs/<slug>` with **no locale** (`documentationLinks.js:106`).
2. `DocsLink.vue` renders `<a href target="_blank">` only when the URL is non-empty (`DocsLink.vue:31-33`). A key **absent from the registry** gives `''` (`documentationLinks.js:104`) and the link is simply not rendered. A key **present** whose article is retired still renders.
3. `/docs/<slug>` hits `DocumentationController#article`, `article_for` misses (published scope), and the answer is `head :not_found`: a new tab showing a **blank 404 page** (`documentation_controller.rb:23`).

What already prevents that in source control: `content_seeder_corpus_spec.rb:77-79` fails the build if any registry slug lacks an English file; `:31-37` fails if any article links by bare key to a file that does not exist; `:25-27` requires EN/AR parity. Those catch a **file** deleted while the registry or another article still names it. They look at files, never at the database, and never at links from outside the repository.

The registry has **62** keys (`documentationLinks.js:11-94`, counted twice), not the 87 stated in `01-current-system.md` §7. 62 of the 63 corpus keys are product-linked; the exception is `your-own-help-centre`, whose title is now "Documentation and support" (see 1.7).

### 1.6 `archived` already exists and is already excluded everywhere it needs to be

`enum status: { draft: 0, published: 1, archived: 2 }` (`article.rb:75`). Every public and SEO surface filters on `published`, so an archived article disappears from all of them without any new code:

| Surface | Filter |
|---|---|
| Article page / `.md` | `articles_controller.rb:81,30` |
| Listing, search | `articles_controller.rb:13`; `search_controller.rb:11`; `search_spec.rb:85-91` asserts an archived article is never returned |
| Home, categories | `portal_home_data.rb:14,28,59`; `categories_controller.rb:32` |
| Product-link resolution | `library.rb:42-44` |
| Sitemap | `sitemap.xml.erb:14` |
| hreflang family | `documentation_helper.rb:106-109` |
| SEO audit | `documentation_seo_audit.rake:45` |

### 1.7 The one live example of a key that no longer describes its content

`your-own-help-centre` (section `workspace`) is titled "Documentation and support" and says the workspace does **not** publish a help centre. It is the only corpus key without a registry key, and is bare-linked from `roles-and-permissions` (2 links per locale). A rename is the cheapest first use of the mechanism below, but the verdict belongs to agent 057/062.

## 2. Measured behaviour

What each retirement action does **today** to the three kinds of inbound link. "Product" is a `DOC_ARTICLES` key, "Corpus" a bare-key Markdown link (988 occurrences: 494 EN + 494 AR, 63 keys, 19 keys with 10 or more inbound EN links, most-linked `automation-rules` 33 and `the-whatsapp-24-hour-window` 33), "External" a search-engine result, bookmark, third-party page or an old dashboard bundle still emitting a retired key.

| Action | Corpus | Product | External |
|---|---|---|---|
| Delete the `.md` | CI fails if any article still links to it | CI fails if the registry still names it | **nothing changes**: the article stays published (1.4) |
| Rename key `a` to `b` | CI fails until links are edited | CI fails until the registry is edited | `a` stays live as a duplicate; if later archived by hand: **404, no redirect** |
| Archive in Super Admin, file kept | unchanged | unchanged | 404 now; **republished at next sync** |
| Hard-delete in Super Admin (`resources :articles` has `destroy`, `config/routes/documentation.rb:11-17`; `custom/app/policies/custom/article_policy.rb:12` only governs the tenant API) | unchanged | blank 404 | 404; the seeder recreates it at next sync if the file exists. The EN root's translations are un-linked by `dependent: :nullify` (`article.rb:40-44`) until the sync re-links them (`content_seeder.rb:77`) |
| Unpublish (`draft`) | unchanged | blank 404 | 404, and the seeder republishes it (`content_seeder.rb:101`) |

A subtlety that matters for where a redirect can live: `Super Admin` saves `meta` by **replacing it wholesale**. `ArticleMetaField.permitted_attribute` allows only `title description version release_date feature_image tags` (`article_meta_field.rb:36-38`), the form renders only those (`_form.html.erb`), `normalized_meta` shapes only what was posted (`super_admin/articles_controller.rb:39-53`), and Administrate runs `requested_resource.update(resource_params)` (`administrate-0.20.1/app/controllers/administrate/application_controller.rb:59-60,203-207`). Nothing merges into the existing hash, so saving any seeded article from Super Admin drops `meta['doc_key']`. By code reading; not executed; `grep` finds no spec that saves an article through Super Admin and inspects `meta`.

## 3. Defects

| # | Defect | Severity | Impact |
|---|---|---|---|
| D1 | The seeder never removes or archives anything; a deleted or renamed file leaves a published, indexable, sitemap-listed article forever (`content_seeder.rb:28-31,47-56`) | **major** (blocker the first time the program renames anything) | stale and duplicate content in search and the sitemap; invisible to the SEO audit because canonicals differ |
| D2 | No redirect mechanism of any kind (1.3); a retired slug is a 404 for every external link, bookmark and search result | **major** | link equity and users lost on every rename, merge and retirement the program plans |
| D3 | Retirement through Super Admin is not durable: sync forces `published` (`content_seeder.rb:101`), and there is no retire action (`super_admin/articles_controller.rb:10-18`) | **major** | a retirement done in the UI silently reverts on the next deploy sync |
| D4 | Saving a seeded article in Super Admin replaces `meta` and drops `doc_key` (section 2); only the literal-slug fallback keeps the English key resolving (`library.rb:56`) until the next sync restores it | **major** (adjacent to scope; it also rules out storing a redirect in `meta`) | key lookups for edited articles silently degrade; any retirement key stored in `meta` would be erased the same way |
| D5 | A product link to a retired key opens a blank 404 tab (`documentation_controller.rb:23`); old dashboard bundles keep emitting retired keys until the user reloads | **minor today, major once retirements start** | stuck user gets nothing; CI cannot see bundles already in browsers |
| D6 | Two different 404 pages inside `/hc/` (1.1): branded for "no such slug", static for draft, archived and cross-portal | minor | inconsistent recovery path; no behavioural difference for crawlers |
| D7 | Emptied or retired section stays a 200 page with an empty state (`categories_controller.rb:25`; seeder never deletes categories) | minor | soft-404 on a URL the sitemap does not list but old links and the breadcrumb schema can reach |
| D8 | `/hc/:slug/:locale/categories/:bogus/articles` returns the whole locale's list and `/hc/lynomia-docs/xx` returns an empty 200 (1.1) | minor, code reading only | soft-404 pattern a crawler can find by guessing |
| D9 | The product link carries no locale (`documentationLinks.js:106`) and `article_for` receives `params[:locale]` = nil, so it falls to English (`library.rb:56`); `12-contextual-help.md` says the locale is handled | minor, outside this scope, flagged for the contextual-help owner | an Arabic reader following a product link lands on the English article; a retirement redirect must not make this worse |
| D10 | **Possible live instance of D5.** `contactLynomiaSupport` (`documentationLinks.js:93`) names `contact-lynomia-support`, added in `48574e65` (2026-10-12 22:40, in baseline). The reported production run processed 38+19+67 = **124** articles; the baseline tree has **126** files, all inside manifest sections | unverified, would be **major** | if the run predates `48574e65`, three dashboard surfaces link to an article production does not have. Needs a production read, which §3 forbids |

## 4. What a larger corpus breaks

- **Orphans scale with edits, not with size.** Every rename or merge strands two published rows (EN and AR) with old text under a second canonical. The SEO audit passes, the sitemap lists them, search returns them.
- **Inbound-link repair is already expensive.** A rename of a top key touches up to 33 EN and 33 AR files. CI forces that edit for in-repo links (`content_seeder_corpus_spec.rb:31-37`) and for the registry (`:77-79`), which is good; nothing covers the world outside the repository.
- **Every retirement is a frontend release.** 62 of 63 keys are in the JS registry, so retiring one means changing `documentationLinks.js`, rebuilding the bundle, and living with old bundles in open tabs. The redirect has to outlive bundle churn: entries are permanent.
- **Unresolved keys get more expensive.** Four queries per miss, three on an un-indexed JSONB predicate (`library.rb:55-56`; 01-current-system §9.1). Crawlers re-probing retired URLs for months turns a trivial scan into constant load once the table is several times larger. A redirect map held in memory adds none.
- **Splits break fragments.** A redirect preserves the `#anchor` but cannot know the section moved. Keep the old key as the hub of a split (no retirement) and keep its headings.
- **Section changes leave empty 200 pages** (D7); the charter keeps the 12 sections (§8.5), so this is a latent rather than a planned case.

## 5. Recommendations

Extend what exists; build no table, no status value, no SEO engine.

### 5.1 The answers asked for

| Question | Answer | Why |
|---|---|---|
| Does `status` gain a value? | **No.** Retired is `archived`, which already exists (`article.rb:75`), is excluded from every public and SEO surface (1.6), and is already selectable in Super Admin (`article_dashboard.rb:23`) | a new enum value changes the shared core `Article` for nothing |
| Does `meta` gain a key? | **No, not in the minimum.** The redirect is not stored on the article row | Super Admin replaces `meta` wholesale (D4); the row can be hard-deleted (section 2), which would lose the redirect with it, and a fresh database never had the row; `meta->>` lookups are un-indexed |
| Where does the redirect live? | **In `custom/db/documentation/manifest.yml`, as a `retired:` list**, read by `Documentation::Library` | the manifest is already the reviewed, versioned description of the corpus (it ships in the release and the seeder reads it at runtime, `content_seeder.rb:37-39`); the retirement decision lands in the same diff as the file removal; it survives row deletion, DB restore and a fresh install; an extra top-level key is ignored by today's seeder (`manifest['sections']` is all it reads, `content_seeder.rb:29`) so the manifest can ship ahead of the code |
| What does the seeder do about a missing file? | Archive the rows named in `retired:`, report any other published row with no source file, never act on it (5.4) | an automatic archive on "file absent" would let a typo in a rename unpublish production content at deploy |
| How does SEO handle it? | 301 when there is a successor, 410 when there is none, 404 unchanged for unknown and draft, **no noindex** (5.5) | |

### 5.2 Manifest shape

```yaml
retired:
  - key: your-own-help-centre        # the file key; EN slug = key, AR slug = key-ar (content_seeder.rb:85-87)
    to: documentation-and-support    # a live key. Omit when nothing replaces it (answered 410)
```

Rules, checked by a corpus spec at CI and re-checked by the seeder before it writes anything (fail loud, in the seeder's existing `ArgumentError` style, `content_seeder.rb:22,128`):

1. **Append-only; a retired key is never reused.** No file for it in any locale. This is what makes a permanent 301 safe and keeps the slug reserved by the unique index (`schema.rb:226`).
2. `to` names a **live** key with both an EN and an AR file, is not itself retired, and is not `key`. A chain therefore cannot exist and the resolver is exactly one hop, with no loop guard needed.
3. `to` is a topical equivalent. Never the docs home: a redirect to a page that does not answer the question is a soft-404, the same principle as `documentation_controller.rb:16-17`.
4. No `DOC_ARTICLES` slug is a retired key (extend `content_seeder_corpus_spec.rb:77-79`). Retiring a key means removing its registry entry in the same PR; the link then vanishes from the UI (`documentationLinks.js:104`, `DocsLink.vue:31`).
5. EN and AR retire together; the entry is per key and the seeder iterates `Library::LOCALES`.

### 5.3 The resolver: one map, two call sites

`Documentation::Library` gains one in-memory lookup built from `retired:` at first use (the manifest changes only with a release, which restarts the process, `deploy.sh` stage 7), plus a hoisted public `slug_for(key, locale)` so the `-ar` convention lives in one place instead of private to the seeder (`content_seeder.rb:85-87`). It answers, for a key or a slug: not retired, retired with a successor, or retired and gone. The successor is returned only when it is **published**; if it is not yet in the database (the window between a restart and the content sync, 01-current-system §4) the request falls through to exactly today's behaviour instead of redirecting to a 404.

1. **`DocumentationController#article`** (`documentation_controller.rb:22-23`): when `article_for` finds nothing, consult the map. Successor: `redirect_to ..., status: :moved_permanently`. Gone: `head :gone`. Otherwise the existing `head :not_found`. This serves the product link, stale bundles and anything that learned `/docs/<key>`.
2. **`/hc/lynomia-docs/articles/<old-slug>` and `.md`**, the URL a search engine actually holds. Add a `Custom::Public::Api::V1::Portals::ArticlesController` overlay module (the hook already exists at `articles_controller.rb:114`; `ChatwootApp.extensions` is `['custom']`, `chatwoot_app.rb:42-44`; pattern: `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb`) with a **`prepend_before_action`** for `show` and `show_markdown`, for the docs portal only. It must be a prepended before-action and not a change to `set_article`: the base `around_action :set_locale` runs first (`base_controller.rb:7`) and, for a slug with no row, renders the 404 at `base_controller.rb:56` before `set_article` (`articles_controller.rb:80-83`) is ever reached. A hook in `set_article` would never fire for a retired slug whose row is absent (fresh install, hard delete). The map hit is an in-memory hash lookup, so ordinary article views pay nothing. Successor locale follows the requested slug (`key` is `en`, `key-ar` is `ar`).

A signed-in super admin previewing a retired article would be redirected too; the overlay can skip that case if preview of archived rows matters (`previewing_as_super_admin?`, `articles_controller.rb:85-88`).

### 5.4 What the seeder must do

In `ContentSeeder#perform!`, after the file upserts:

1. For each `retired` entry and each portal locale: `portal.articles.find_by(slug: slug_for(key, locale), locale:)`; if present and not archived, set `status: :archived` and count it in a new `Result#retired`. Absent row: nothing to do. It never publishes, never deletes, and re-archives on every run, so it is idempotent and wins over a hand edit (the opposite of a file-backed article, deliberately: the manifest is the source).
2. Validate rules 1 and 2 of 5.2 **before the first write**, so a bad manifest aborts the run rather than leaving a partial corpus (01-current-system §9.4).
3. Report orphans: portal articles that are not archived and whose slug is neither produced by a file this run nor named in `retired:`. Detect by slug set, **not** by `meta['doc_key']`, which D4 shows is unreliable on edited rows. Return them in `Result#orphans` and print them from `rake documentation:content` (`lib/tasks/documentation.rake:19-23`). Do not act on them. Whether a non-empty list should fail the sync is the Phase 4 failure-semantics decision (charter §8.2); the recommendation is non-zero in deploy and CI, because an orphan is exactly "a file was removed without a retirement decision". The definition also catches Super Admin-authored articles with no file, so it depends on the source-of-truth decision (charter §8.1).
4. Leave categories alone; section retirement is outside the minimum (5.7).

### 5.5 SEO: which status, when

| Condition | Response | Reason |
|---|---|---|
| Retired, has successor | **301** to the successor's `/hc/.../articles/<slug>`, same locale | permanent move; consolidates signals onto the live page; the sitemap and hreflang already stop listing the old URL (1.6) |
| Retired, no successor | **410**, rendering the existing branded not-found view with `status: :gone` (`error/404.html.erb`) | deliberate removal; distinguishable from a typo in access logs; crawlers drop it. `404` is an acceptable fallback if the program wants one fewer code path |
| Unknown slug or key | **404**, unchanged | |
| Draft | **404**, unchanged | may come back; 404 is accurate |
| noindex | **not used for retirement** | a `noindex` only works on a 200 page the crawler can fetch and parse; a 301, 410 or 404 has no head to carry it, and the portal head has no robots tag at all today (`app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:1-65`; `RobotsController` is path-based, `robots_controller.rb:17-28`). It would only be needed for a "deprecated but still served" article, which no current article requires; if one appears it is a conditional on a `meta` flag in `_meta_head.html.erb`, not a new system |

Crawler handling of 301, 404 and 410 is stated from general convention and was not checked against a search-engine source in this report; agent 098 should confirm before the SEO position is frozen.

`/docs/<key>` keeps its 302 for live articles (it is the stable address) and uses 301 only for retired keys, which never come back (rule 1).

### 5.6 Retirement procedure (what an author does)

1. Move or merge the content into the successor article, EN and AR.
2. In one PR: delete both `.md` files, add the `retired:` entry, edit every bare-key link that pointed at the key (CI names them), remove the `DOC_ARTICLES` entry, and drop any Vue call site that would now render nothing.
3. CI passes only if the rules in 5.2 hold. Deploy, then run the content sync; the old rows become `archived`, the sitemap loses them, `/docs/<key>` and `/hc/.../articles/<old-slug>` answer 301 or 410.
4. Never retire through Super Admin: it is reverted at the next sync (D3).

Rename is a retire-with-`to`. Merge is a retire-with-`to` per source. Split keeps the original key as the hub and adds new keys; nothing retires, no redirect. Relocate between sections changes no URL and needs no entry, but the `position` quirk in 1.4 means the first sync after a move should be re-run once; the seeder owner should fix that when touching `upsert_article`.

### 5.7 Out of the minimum, said plainly

- Retiring a **section** (category): not covered; the category row and its 200 empty page survive (D7). If it happens, the same release must remove the category and 301 its URL. Charter §8.5 keeps the 12 sections.
- The **changelog** portal is historical and does not retire; the changelog seeder reads its own manifest (`content_seeder.rb:16-18`) and would simply find no `retired:` list.
- A table-backed `Redirect` model: rejected (charter §2); tens of rows do not justify one.
- An nginx map: rejected; the file is a sample, `deploy.sh` does not manage nginx, and a rule there would sit outside the diff that retires the article and would have to duplicate the `-ar` slug convention.
- Rails `redirect` routes: workable but split the decision across a routes file and the content change; rejected in favour of the manifest.
- If Phase 4 freezes the database as canonical, keep the same `{key, to}` shape but store it where Super Admin cannot clobber it. The cheapest correct home is `meta['replaced_by']` **after** `ArticleMetaField` is changed to merge into the existing hash instead of replacing it (needed anyway for `doc_key`, D4). Do not store it in `meta` before that fix.

### 5.8 Changed files, for the writer-ownership map (charter §8.6)

| File | Change | Contention |
|---|---|---|
| `custom/db/documentation/manifest.yml` | `retired:` list | content streams |
| `custom/app/services/documentation/library.rb` | retired map, public `slug_for` | the `doc_key` index/lookup work |
| `custom/app/services/documentation/content_seeder.rb` | archive step, validation, orphan report | **high**: the deployment-sync and transaction work edits the same class |
| `custom/app/controllers/documentation_controller.rb` | consult the map before `head :not_found` | low |
| `custom/app/controllers/custom/public/api/v1/portals/articles_controller.rb` | new overlay with the prepended before-action | low |
| `lib/tasks/documentation.rake` | print `retired` and `orphans` | deployment-sync work |
| `spec/custom/services/documentation/content_seeder_corpus_spec.rb` plus one request spec | rules in 5.2; 301, 410 and the fall-through when the successor is missing | |

No change to `Article`, `articles.status`, the sitemap, the hreflang helper, the SEO audit, `robots.txt`, nginx or the dashboard bundle (beyond removing a registry key when one is retired).

## 6. Risks and what was not checked

- **Deploy ordering.** The map ships with the code; the archive happens at content sync. The "published successor only" rule makes the gap safe; the gap itself is the 01-current-system §4 problem and is not solved here.
- **Permanent 301s are cached by browsers.** Hence append-only keys (rule 1). A mistaken entry cannot be taken back for users who already followed it.
- **Orphan report false positives** if authors create articles in Super Admin before a file exists. Depends on charter §8.1.
- **Not checked:** the production database (D10); the body, language and home link of `public/404.html`; whether the branded 404 renders cleanly when `@locale` is nil for an unknown slug (the status is specced, the markup was not read); the `/hc/lynomia-docs/xx` and bogus-category-listing 200s by execution (D8); the Super Admin `meta` overwrite by execution (D4); custom-domain handling of platform portals; any CDN or proxy in front of the app (nothing in the repository); search-engine documentation for 301/404/410.
