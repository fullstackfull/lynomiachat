# The documentation system as it actually is

Agent 000, first-hand, against `claude/documentation-v2` at baseline `021ea6e3`. Every claim carries a citation.
Specialist agents 049–087 deepen individual areas; this is the shared map they start from.

---

## 1. One content model, no second CMS

There is no documentation table. The corpus lives on the Help Center's own three models — `Portal`, `Category`,
`Article` — and two of the portals are *platform-owned*, meaning they belong to no account.

`custom/app/services/documentation/library.rb` is the single door onto them:

- `DOCS_SLUG = 'lynomia-docs'`, `CHANGELOG_SLUG = 'lynomia-changelog'` (`library.rb:8-10`)
- `LOCALES = %w[en ar]`, `DEFAULT_LOCALE = 'en'` (`library.rb:14-15`)
- `portals` = `Portal.platform.active.where(slug: SLUGS)` (`library.rb:37-39`)
- `articles` = `Article.published.where(portal: portals)` (`library.rb:42-44`)
- `article_for(key, locale:)` resolves a contextual-help *key* to the article in the reader's language, falling
  back to English, then to any locale, then to a literal slug (`library.rb:54-57`)

The key→article lookup is `articles.meta->>'doc_key' = ?` (`library.rb:55`). That matters: `articles.slug` is
globally unique, so the English and Arabic versions of one article cannot share a slug, and the *key* is what the
product links to. **There is no index on `meta->>'doc_key'`** — see §9.

Tenancy holds because every tenant surface reads through `Current.account.portals` and a NULL `account_id`
cannot satisfy that (`library.rb:5-6`).

## 2. The corpus is Markdown in source control

```
custom/db/documentation/
├── manifest.yml          12 sections: slug, position, icon, en/ar name + description
├── en/<section>/<key>.md
└── ar/<section>/<key>.md
```

Measured: **126 `.md` files, 63 EN + 63 AR, exact per-section parity.**

| Section | EN | AR |
|---|---|---|
| getting-started | 5 | 5 |
| conversations | 6 | 6 |
| contacts | 4 | 4 |
| audiences-and-campaigns | 3 | 3 |
| whatsapp | 6 | 6 |
| whatsapp-errors | 14 | 14 |
| automation | 4 | 4 |
| commerce | 7 | 7 |
| workspace | 4 | 4 |
| integrations | 2 | 2 |
| administration | 1 | 1 |
| troubleshooting | 7 | 7 |

Each file is YAML front matter plus CommonMark. The front matter carries `title`, `description`, `position`, and
optionally `seo_title`, `seo_description`, `tags`, `version`, `release_date`
(`content_seeder.rb:94-113`). Front matter is mandatory — a file without it raises
(`content_seeder.rb:126-131`).

The changelog is the same machinery over `custom/db/changelog` (`content_seeder.rb:11,16-18`).

## 3. Seeding: `Documentation::ContentSeeder`

`rails documentation:content` → `Documentation::ContentSeeder.new.perform!` (`lib/tasks/documentation.rake:19-23`).

Its own header states the intent: *"One-time, operator-run, idempotent… An operator's own edits in Super Admin
are not protected from a re-run: the files are the source, and a change that should survive belongs in a file."*
(`content_seeder.rb:1-8`)

The actual semantics, read line by line:

| Behaviour | Evidence | Consequence |
|---|---|---|
| Upsert by `(slug, locale)` | `content_seeder.rb:73` | re-running updates rather than duplicates |
| **`status` is forced on every run** — `@publish ? :published : :draft` | `content_seeder.rb:101` | an operator who unpublished an article gets it republished by the next sync |
| `title`, `description`, `content`, `category`, `position`, `meta` all overwritten from file | `content_seeder.rb:94-104` | any Super Admin edit to a seeded article is silently discarded |
| **Nothing is ever deleted** | `perform!` only iterates manifest sections and globs files (`content_seeder.rb:28-29,47-56`) | removing a Markdown file leaves its article published forever; renaming a key leaves an orphan |
| **No wrapping transaction** | per-article `article.save!` (`content_seeder.rb:80`); no `transaction` block anywhere in the file | a failure mid-run leaves a *partially updated corpus* with no rollback |
| Author defaults to `SuperAdmin.first` | `content_seeder.rb:22` | raises `ArgumentError` on an install with no super admin; attributes every article to whoever was created first |
| `author ||= author` only when absent | `content_seeder.rb:79` | an operator-set author survives |
| Translations link to the English article by slug | `content_seeder.rb:77,90-92` | English must be seeded first, which `locales` enforces by sorting (`content_seeder.rb:42-45`) |
| Category upsert enforces name/description/position/icon | `content_seeder.rb:58-64` | operator category edits are also overwritten |
| `changed?` is read *before* `author ||=` | `content_seeder.rb:78-79` | the created/updated/unchanged counters are about file-driven fields only |

`rails documentation:setup` → `Documentation::PortalSeeder` is gentler on purpose: it enforces only identity and
language set, preserves `config['layout']`, and fills `DOCUMENTATION_URL`/`CHANGELOG_URL` **only when blank**
(`portal_seeder.rb:38-46,52-60`).

So the two seeders already disagree about operator edits: the portal seeder protects them, the content seeder
does not. That asymmetry is a decision to make explicit, not an accident to copy.

## 4. The production fact: nothing calls the content sync

`deployment/deploy.sh` stages, in order:

| Stage | What |
|---|---|
| 0 | Pre-deploy checks |
| 1 | Fetch the release |
| 2 | Database backup |
| 3 | Check out the release |
| 4 | `bundle install --frozen`, `pnpm install --frozen-lockfile` |
| 4b | libvips precondition (Rails 7.2.3.2 Active Storage refuses to load otherwise) |
| 5 | `db:migrate`, then `check_all_pending!` + invalid-index probe |
| 6 | `pnpm vite build`, `pnpm build:sdk`, manifest assertions |
| 6b | Quiet Sidekiq and drain in-flight jobs |
| 7 | Restart |
| 8 | Verify |
| 9 | Done |

**`documentation:content` appears nowhere** (`grep -n 'rake\|rails \|documentation\|seed' deployment/deploy.sh`
returns only the migration, probe and verification `rails runner` calls). Neither does `documentation:setup`.

That is exactly the reported production behaviour: the Markdown shipped at stage 3, the restart happened at
stage 7, and the corpus did not change until an operator ran the task by hand and got
`38 created / 19 updated / 67 unchanged / 124 published / 0 SEO errors`.

The gap is real and the fix is **not** "append a rake call to stage 5". The open questions, to be answered in
Phase 4:

1. Content sync must run **after** migrate (it writes through the models) and **before or after** restart? Before
   the restart, the running old code serves content written by new-code expectations; after the restart, there is
   a window where new code serves an old corpus. One of those is wrong for a schema-changing release.
2. A partial run is possible today (§3). What does a failure at article 57 of 126 leave, and what undoes it?
3. The database backup is at stage 2, *before* content sync — so a bad sync is recoverable only by restoring the
   whole database, which also loses everything written since. Is that acceptable, or does content sync need its
   own reversal?
4. `status` is forced (§3). If an operator has deliberately unpublished something, an automatic sync overrides a
   human decision on every deploy. That is a product decision, not a deployment detail.
5. SEO validation (`lynomia:docs:seo_audit`, exits 1 on error) — deploy gate or CI gate? It audits *data*, which
   only exists on the server, but failing a deploy at stage 5½ leaves a migrated database and an old corpus.
6. Should sync be automatic at all, or explicitly gated (a flag, a separate command, an operator confirmation)?

## 5. Public rendering

The public entry points are deliberately thin redirects, so the Help Center's own renderer, layouts, locale
handling, search and SEO are reused rather than reimplemented:

- `GET /docs` → `DocumentationController#show` → `redirect_to "/hc/#{portal.slug}"`
  (`custom/app/controllers/documentation_controller.rb:8-10,30-34`)
- `GET /docs/:article_slug` → `#article` → resolves the key via `Library.article_for`, then redirects to
  `/hc/#{portal.slug}/articles/#{article.slug}`; an unresolvable slug is a `404`, deliberately, rather than a
  drop onto the documentation home page (`documentation_controller.rb:18-26`)
- `GET /changelog` → `#changelog` (`documentation_controller.rb:12-14`)
- A missing portal renders `I18n.t('documentation.not_set_up')` with `404` (`documentation_controller.rb:36-38`)
- Route constraint on the slug: `/[a-z0-9][a-z0-9\-_]*/` (`config/routes/documentation.rb:28`)

The documentation layout is a *variant* of the Help Center's public views, not a fork:

```
app/views/public/api/v1/portals/show.html+documentation.erb
app/views/public/api/v1/portals/articles/show.html+documentation.erb
app/views/public/api/v1/portals/categories/show.html+documentation.erb
app/views/public/api/v1/portals/search/index.html+documentation.erb
app/views/public/api/v1/portals/documentation_layout/
```

Markdown → HTML goes through `ChatwootMarkdownRenderer#render_article`, which renders CommonMark with the
`:table` extension through `CustomMarkdownRenderer` and then calls `html_safe` with a RuboCop
`Rails/OutputSafety` disable (`lib/chatwoot_markdown_renderer.rb:14-21,27-31`).

**CORRECTED 2026-10-13, after agents 065, 071 and 085 read the path in full.** My original text here said no
`sanitize` call appears and that CommonMark's `:DEFAULT` set "does not escape raw HTML blocks unless
`:SAFE`/`UNSAFE` handling says so", leaving the question open. That framing was wrong in a way that matters, so
the corrected finding:

- **Raw HTML is DELETED, not escaped.** `CustomMarkdownRenderer.new` is built with `options: :DEFAULT`
  (`lib/custom_markdown_renderer.rb` via `renderer.rb:10`); `:UNSAFE` (`1<<17`) is never set, and `:UNSAFE`
  appears nowhere in the repository. CommonMarker's HTML renderer therefore emits `<!-- raw HTML omitted -->`
  for both block and inline HTML (`commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-126`),
  which `spec/lib/custom_markdown_renderer_spec.rb:31-38` already asserts. There is no `sanitize` call because
  no author HTML is ever emitted. The mechanism is **omission**, and saying "escaping" is how someone later
  reasons their way to turning `:UNSAFE` on.
- **`javascript:`, `vbscript:` and `file:` URLs are blanked** by
  `lib/markdown_renderer_url_sanitizer.rb:14-18`. The `\A` anchor holds, because cmark's own `cmark_clean_url`
  trims whitespace and decodes entities before Ruby sees the URL. `blob:`, `intent:` and protocol-relative
  `//host` pass.
- **`data:` is NOT blanked for images.** Corrected 2026-10-13 — I wrote that it was. `SAFE_DATA_IMAGE_PATTERN`
  (`markdown_renderer_url_sanitizer.rb:4`) explicitly re-permits `data:image/png`, `gif`, `jpeg` and `webp`, and
  `sanitized_href` blanks a dangerous URL only when it does *not* match that pattern (`:16`). Agents 083 and 087
  both found this, and I verified it. It is load-bearing: **`![](data:image/png;base64,…)` is a working media
  channel that bypasses ActiveStorage, every size and type check, EXIF stripping and any review step — and it is
  permanent in git.** It must be closed before Phase 5 writes a single image, or the media contract is
  unenforceable by construction.
- **`onerror`/`onload` are unreachable**: the hand-built `<img>`/`<a>` interpolate only through `escape_href`,
  `escape_html` and a `\A(\d+)px\z`-bounded width.
- **A latent trap**: enabling `:UNSAFE` would NOT enable `tagfilter`, because the renderer is built with
  `extensions: []`. A "one-flag" change to let authors write HTML is a full stored-XSS hole, not a relaxation.

**But the real finding is one nobody was looking for.** `config/markdown_embeds.yml` already turns a bare
Markdown link into raw embed HTML for **11 providers** — 8 iframes, one `<video>`, and **two that emit
third-party `<script>` tags (Wistia and GitHub Gist)** — interpolated verbatim by
`lib/custom_markdown_renderer.rb:198-209` with no sanitizer pass afterwards. Gist content is attacker-authored.
So an author can publish third-party script on the product's own origin with one Markdown link, today, and the
portal's Content-Security-Policy is `object-src 'none'; base-uri 'self'` and nothing else
(`config/initializers/content_security_policy.rb:14-17`) — no `script-src`, no `default-src`, no `frame-src`.
`object-src 'none'` blocks `<object>`/`<embed>`; it does not block an iframe or a script tag.

Worse, `?show_plain_layout=true` — **the Super Admin preview URL** — deletes `X-Frame-Options`
(`base_controller.rb:66-68`) with no `frame-ancestors` to replace it, so any site can frame any article.

The corpus uses **zero** embeds and **zero** images today, so the cost of removing `github_gist` and `wistia`
from that YAML is nil. That file is imported by the dashboard editor too
(`app/javascript/dashboard/helper/markdownEmbeds.js:1`), so it needs one owner across both trees.

## 6. Authoring: Administrate, and a textarea

Super Admin authors on the same `Article` — there is no second content model and no second editor
(`custom/app/dashboards/article_dashboard.rb:5-10`).

- `custom/app/controllers/super_admin/articles_controller.rb` (54 lines): `publish` / `unpublish` set `status`;
  `preview` redirects to `/hc/#{portal.slug}/articles/#{slug}?show_plain_layout=true`; `scoped_resource` is
  `Article.where(portal: Documentation::Library.portals)`; `new_resource` sets `author: current_super_admin`;
  `resource_params` normalises comma-separated tags into `meta`.
- `ArticleDashboard` form fields: `portal category title slug description content locale status position meta`
  (`article_dashboard.rb:36`).
- The editor is **`content: Field::Text.with_options(rows: 28)`** (`article_dashboard.rb:19`). A 28-row textarea.
- `meta` is a custom field (`custom/app/fields/article_meta_field.rb`, view in
  `custom/app/views/fields/article_meta_field/`), `author` likewise.
- Collection filters: published, draft, changelog (`article_dashboard.rb:38-42`).
- Routes: `resources :articles` with member `post :publish`, `post :unpublish`, `get :preview`
  (`config/routes/documentation.rb:13-19`). Plus `resources :categories` and read/edit-only `:portals`.

What the authoring surface does **not** have: media insertion of any kind, alt-text enforcement, side-by-side or
live preview, RTL preview, structured documentation components, SEO field validation, dirty-state protection,
content quality checks, or any relationship to the Markdown files that the seeder will overwrite it with.

## 7. Contextual help

`app/javascript/dashboard/helper/documentationLinks.js` is the single registry — *"a documentation link lives in
exactly one place and a Vue file never carries a URL"*. It exports:

- `DOC_ARTICLES` — **62 keys** (corrected 2026-10-13; I first wrote 87, agent 076 challenged it and is right — 62
  `DOC_ARTICLES` keys plus 19 `COMMERCE_ERROR_ARTICLES` mappings is 81 `key: 'value'` lines in the file),
  grouped by product area, each mapping a product moment to a stable article slug
- `documentationArticleUrl(base, key)` — builds the URL from the installation's own `DOCUMENTATION_URL`; returns
  `''` when the installation has no documentation URL, so the caller renders no link
- `commerceErrorArticle(code)` — maps 19 `Commerce::Error` codes onto **5** articles, grouped by *remedy*
- `whatsappErrorArticle(code)` — resolves `whatsappError<code>` only when a key exists; an unknown code resolves
  to `undefined` and the caller falls back to general troubleshooting

Two design rules are already established here and should be preserved rather than relitigated:
**one article per class of failure, not one per code**, and **no article invented for a code nobody has seen**.
Five WhatsApp codes have articles — `131049`, `131042`, `131053`, `131060`, `190`.

**CORRECTED 2026-10-13.** I wrote that those are the five codes
`custom/app/services/whatsapp/delivery_failure.rb` classifies. Agent 054 challenged it and is right: `CODES`
holds exactly **two** entries, `131049` and `131042` (`delivery_failure.rb:28-31`), which I verified myself. The
other three articles exist for codes the product only *names* elsewhere.

That matters more than a miscount, because classification is what gates the in-product link: `MessageError.vue`
needs a `deliveryFailure`, which the server sends only for a classified code. So **12 of the 14
`whatsapp-errors` articles have no entry point from the product at all**, and any new Meta error article will be
equally unreachable unless that gate changes. Agents 040 and 054 reached this independently.

That rule is about to meet a much larger Meta error surface, and §8 of the charter asks whether article+metadata
or structured metadata is the right carrier. The registry is the thing to extend.

## 8. SEO

`lib/tasks/documentation_seo_audit.rake` → `rake lynomia:docs:seo_audit`. It is read-only, exits 1 on an ERROR
and 0 on warnings only, and it audits **data rather than templates** — deliberately
(`documentation_seo_audit.rake:1-11`). What it enforces:

| Check | Level |
|---|---|
| two articles sharing a canonical URL | error |
| canonical URL without a host | error |
| missing title | error |
| missing meta description *and* description | error |
| hreflang set not containing the article itself | error — **but unreachable, see below** |
| hreflang set without `x-default` | error — **but unreachable, see below** |
| duplicate hreflang locales | error |
| structured data that fails to build | error |
| title over 60 chars | warning |
| description outside 50–160 chars | warning |

It renders through the real helpers (`DocumentationHelper`, `PortalHelper`) rather than reimplementing them
(`documentation_seo_audit.rake:36-38`). The reported production run was `0 SEO errors / INDEXABLE`.

**CORRECTED 2026-10-13.** I listed those checks as if they were live gates. Agents 070 and 073 established that
several of them cannot fail, which makes "0 SEO errors" a much weaker statement than it reads as:

- The **duplicate-canonical** error is structurally unreachable: `index_articles_on_slug` is UNIQUE, so the
  database refuses the collision before the audit can see it. Its own spec has to stub `Article#slug` to reach
  the branch (`spec/.../task_documentation_seo_audit_spec.rb:50-56`).
- **x-default** and **hreflang self-inclusion** cannot fail for a published article, because the alternates are
  derived from `associated_article_id` rather than from the slug suffix.
- The **title-length warning measures the wrong field** — `article.title`, while the page renders `meta['title']`
  when present. It flags four files that already carry a compliant `seo_title`, and misses the real problem:
  the rendered `<title>` appends `" | Lynomia Chat Documentation"`, a 29-character suffix the audit never
  counts, so **27 of 126 articles render a `<title>` over 60 characters while the audit reports 4**.
- A **hostless canonical passes**: with `HELPCENTER_URL` and `FRONTEND_URL` unset — or `HELPCENTER_URL` set to
  the empty string, which is truthy in Ruby and therefore shadows the fallback — every URL becomes
  `https://hc/...`, and `start_with?('http')` is satisfied.
- The audit cannot see the failure modes this program will actually create: a renamed slug leaving a live
  duplicate article at the old slug that the seeder recreates and nothing deletes; an article orphaned from
  every index; a `DOC_ARTICLES` key resolving to nothing; thin or duplicated content.

So the audit is a useful per-article front-matter check and **not** a corpus integrity check. The program needs
the second thing, and it does not exist yet.

Agents 073–080 own canonical/hreflang, sitemap/robots, JSON-LD, internal linking, search relevance, synonyms,
retirement/redirects and image/CWV.

## 9. Known weak points, from this read alone

1. **`meta->>'doc_key'` has no index.** `Library.article_for` runs that predicate on every contextual-help
   resolution (`library.rb:55`). At 124 articles it is a trivial scan; the corpus is about to multiply.
2. **The content seeder forces `status`** and overwrites every file-backed field, while the portal seeder
   deliberately protects operator edits. Two writers, two philosophies, one `Article` row.
3. **The content seeder deletes nothing.** Retiring an article is currently impossible through the corpus; a
   removed file leaves a live, published, unreachable-from-source article.
4. **No transaction.** A partial sync is a reachable state with no defined recovery.
5. **`SuperAdmin.first` as author** couples content provenance to row order.
6. **No sanitization proven in the article render path** (§5) — and the editor upgrade widens it.
7. **Nothing in the deploy pipeline syncs content** (§4).
8. **No media story at all.** Not a weak implementation — an absent one. Articles are text.

## 10. What this program must not break

- `/docs`, `/docs/:slug`, `/changelog` are stable public addresses; a product link must keep resolving.
- `DOC_ARTICLES` slugs are the contract between the product and the corpus. Renaming a key breaks a UI link;
  renaming a slug breaks `meta['doc_key']` resolution.
- Platform portals have `account_id = NULL` and that is load-bearing for tenant isolation.
- `articles.slug` is globally unique across locales; the `-ar` suffix convention is how the Arabic sibling exists
  at all (`content_seeder.rb:85-87`).
- English must seed before any other locale, or `associated_article_id` comes back nil
  (`content_seeder.rb:42-45,90-92`).
- The SEO audit exits non-zero on an error. Anything that makes it exit 1 is a release blocker by construction.
