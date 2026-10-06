# 10 — What was built

The implementation, file by file, and what each piece reuses rather than replaces.

---

## 1. The shape of it

```
a Markdown file in source control
   ↓  rails documentation:content        (Documentation::ContentSeeder)
an Article in a platform Portal          (no account — 01-global-ownership-design.md)
   ↓  the Help Center's own public renderer, unchanged
/hc/lynomia-docs/<locale>/...            (and /docs/<key> as the stable address)
   ↑  Super Admin edits the same row     (Administrate — 07-super-admin-management.md)
```

Nothing in that chain is new except the ownership primitive and the seeder. The editor's format, the publish
lifecycle, the locale model, the search and the renderer are the Help Center's.

## 2. The files

### The one migration

| File | What |
|---|---|
| `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb` | `portals.platform_owned`, and `account_id` relaxed to nullable on portals, categories and articles |

### Server

| File | What |
|---|---|
| `custom/app/services/documentation/library.rb` | the one door onto platform content: the two portal slugs, the locales, and `article_for(key, locale:)` |
| `custom/app/services/documentation/portal_seeder.rb` | creates the two platform portals, idempotently |
| `custom/app/services/documentation/content_seeder.rb` | Markdown + front matter → Articles, for both the documentation and the changelog trees |
| `custom/app/controllers/documentation_controller.rb` | `/docs`, `/docs/:key`, `/changelog` |
| `custom/app/controllers/super_admin/{portals,categories,articles}_controller.rb` | Super Admin, each scoped to platform content at `scoped_resource` |
| `custom/app/dashboards/{portal,category,article}_dashboard.rb` | the Administrate resources |
| `custom/app/fields/article_meta_field.rb` | `meta` edited as named fields rather than raw JSON |
| `custom/app/fields/article_author_field.rb` | the author as text, because Administrate's BelongsTo would build a route that does not exist |
| `config/routes/documentation.rb` | drawn from `config/routes.rb` |
| `lib/tasks/documentation.rake` | `documentation:setup`, `documentation:content`, `documentation:changelog` |

### Model changes, all small

| File | Change |
|---|---|
| `app/models/portal.rb` | `belongs_to :account, optional: true`; the two paired validations; `RESERVED_SLUGS`; `feature_enabled?`; `article_order`; `platform` / `tenant` scopes |
| `app/models/article.rb` | account optional; `platform_owned?`; `order_by_release_date` |
| `app/models/category.rb` | account optional; `platform_owned?` |
| `app/models/concerns/portal_config_schema.rb` | one key, `article_order` |

### Public rendering

| File | Change |
|---|---|
| `public/api/v1/portals/articles_controller.rb` | **published-only resolution**, with a super-admin preview exception |
| `.../articles/_draft_banner.html.erb` | new — says a previewed article is a draft |
| `.../documentation_layout/articles/_release_meta.html.erb` | new — a release's version, date and modules |
| `.../documentation_layout/_sidebar.html.erb` | honours `article_order` |
| `public/api/v1/portals/categories_controller.rb` | honours `article_order` |
| `app/controllers/public_controller.rb`, two layouts, two EE controllers, one EE model concern | ask the **portal** about a feature flag rather than its account |

### Content

| Path | What |
|---|---|
| `custom/db/documentation/manifest.yml` | the eleven sections, named in both languages |
| `custom/db/documentation/{en,ar}/<section>/<key>.md` | **86 files — 43 articles × 2 languages** |
| `custom/db/changelog/` | the changelog's own manifest and release notes |

### Dashboard

| File | Change |
|---|---|
| `dashboard/helper/documentationLinks.js` | new — the 43-key registry |
| `dashboard/helper/featureHelper.js` | resolves each feature to its own documentation article |
| `shared/composables/useBranding.js` | `docsLink(key)` |
| `config/installation_config.yml` | `DOCUMENTATION_URL` → `/docs`, `CHANGELOG_URL` → `/changelog` |

## 3. The public address — P4 §13, decided

| Option | Verdict |
|---|---|
| `/hc/<slug>/<locale>` only | works, but a product link then hard-codes the portal slug and the locale |
| An external documentation domain | needs DNS and a certificate per installation; the portal's custom-domain support is there if an operator wants it |
| **`/docs` and `/docs/<key>`** | **adopted** |

`/docs` resolves the platform portal and redirects into the Help Center's own renderer, so the documentation gets the
existing layouts, locale handling, search and SEO for nothing, and the address survives a slug change. `/docs/<key>`
resolves one article in the reader's language. Neither route collides with anything: a repository-wide check found no
existing `/docs` or `/changelog` route.

**A deployment prerequisite, recorded rather than hidden:** the public portal serves only on a host the installation
knows itself by — `FRONTEND_URL` or `HELPCENTER_URL` must match the serving host, or every portal page returns 401.
That is upstream behaviour (`DomainHelper.chatwoot_domain?`), it is not specific to platform documentation, and it is
the one thing an operator must set before the documentation is reachable.

## 4. Operating it

```bash
rails documentation:setup      # create or update the two platform portals
rails documentation:content    # publish the documentation corpus from source control
rails documentation:changelog  # publish the release notes
```

All three are idempotent and safe to re-run; re-running reports what it created, updated and left alone. There is no
background job, no scheduler and no scraper — P4 §29 asks for a one-time controlled task, and that is what these are.

**An operator's edits in Super Admin are not protected from a re-seed.** The files are the source; a change that
should survive a deploy belongs in a file. The seeder says what it changed, so this is visible rather than silent.

## 5. What was deliberately not built

| | Why |
|---|---|
| A second CMS, editor, renderer or search engine | the Help Center has all four, and P4 §43 forbids a second |
| A documentation-specific database table | Article carries everything a documentation article and a release note need |
| `articles.published_at` | P4 §17.1 forbids spending a migration on it without a requirement `meta` cannot meet |
| A revision history with restore | the audit table could carry the trail, but restore and a diff view are a feature. Deferred, in `15-content-quality-audit.md` |
| Per-resource Super Admin roles | needs storage, so a second migration |
| JSON-LD and hreflang | P4 §14 says not to overbuild SEO. hreflang is the one worth adding later |
| Scraping either external source | P4 §29 forbids a permanent scraper, and the licences forbid the content |
