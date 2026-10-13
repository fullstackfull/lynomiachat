---
agent: 064
scope: Backend content model (Article/Category/Portal) and the APIs an editor could actually use
confidence: high
---

# The editor's backend: what the content model is, and what it will let an editor write

Read first-hand against `claude/documentation-v2`. Every claim carries a `file:line`. Nothing was executed — no
`rails`, no `rspec`, no database. Where a conclusion rests on gem behaviour I cite the gem source in
`vendor/bundle/`.

The short version: **the content model is adequate and the authoring API is not.** There is exactly one authoring
surface (Super Admin / Administrate), it posts HTML forms, there is no JSON authoring API at all — the tenant one
exists in code but is unconditionally denied by a policy overlay — and the one surface that does exist silently
destroys `meta['doc_key']` on every save.

---

## 1. What exists today

### 1.1 `articles` — every column, as the schema really is

`db/schema.rb:202-229`. The model's annotation block (`app/models/article.rb:1-35`) is **stale on one point**: it
says `account_id :integer not null`, which stopped being true at
`custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:17`.

| Column | Type | Null | Default | Index |
|---|---|---|---|---|
| `id` | bigint PK | no | sequence | PK |
| `account_id` | integer | **yes** | — | `index_articles_on_account_id` |
| `portal_id` | integer | **no** | — | `index_articles_on_portal_id` |
| `category_id` | integer | yes | — | none |
| `folder_id` | integer | yes | — | none |
| `title` | string | yes | — | none |
| `description` | text | yes | — | none |
| `content` | text | yes | — | none |
| `status` | integer | yes | **none** | `index_articles_on_status` |
| `views` | integer | yes | **none** | `index_articles_on_views` |
| `created_at` | datetime | no | — | — |
| `updated_at` | datetime | no | — | — |
| `author_id` | bigint | yes | — | `index_articles_on_author_id` |
| `associated_article_id` | bigint | yes | — | `index_articles_on_associated_article_id` |
| `meta` | jsonb | yes | `{}` | **none** |
| `slug` | string | **no** | — | `index_articles_on_slug` **UNIQUE** |
| `position` | integer | yes | — | none |
| `locale` | string | **no** | `'en'` | none |
| `draft_title` | string | yes | — | none |
| `draft_content` | text | yes | — | none |

**There is not a single foreign key on `articles`.** `grep -n add_foreign_key db/schema.rb` returns one row in
this whole subsystem — `add_foreign_key "inboxes", "portals"` (`db/schema.rb:2130`). `portal_id`, `category_id`,
`author_id` and `associated_article_id` are all unconstrained integers. Referential integrity is entirely an
application-layer promise (`dependent: :nullify` / `:destroy_async`, `app/models/article.rb:40-44`,
`app/models/portal.rb:47-49`).

**There is no composite index for the query the portal actually runs.** Every public read is
`portal.articles.published.where(locale: …)` (`app/controllers/concerns/portal_home_data.rb:28`,
`app/controllers/public/api/v1/portals/articles_controller.rb:13-15`). The available indexes are single-column
`portal_id`, `status` and no `locale` index at all. At 124 articles this is noise; §4 Option E says what to do at
10×.

### 1.2 `categories` (`db/schema.rb:647-666`)

`account_id` integer **nullable**; `portal_id` integer NOT NULL; `name` string; `description` text; `position`
integer; `locale` string default `'en'` (**nullable**, unlike `articles.locale`); `slug` string NOT NULL;
`parent_category_id` bigint; `associated_category_id` bigint; `icon` string default `''`; `icon_color` string
default `''`.

Indexes: `associated_category_id`; `(locale, account_id)`; `locale`; `parent_category_id`; and
`(slug, locale, portal_id)` **UNIQUE**.

**This is the single most load-bearing asymmetry in the whole model.** A category's slug is unique *per locale per
portal*, so `getting-started` exists twice — once `en`, once `ar`. An article's slug is unique *globally, across
every portal and every account*. That one difference is why the corpus needs the `-ar` suffix convention
(`custom/app/services/documentation/content_seeder.rb:85-87`) and why the stable identity a product link points at
had to move into `meta['doc_key']` rather than being the slug (`library.rb:52-56`).

### 1.3 `portals` (`db/schema.rb:1773-1793`)

`account_id` integer nullable; `name` NOT NULL; `slug` NOT NULL; `custom_domain`; `color`; `homepage_link`;
`page_title`; `header_text` text; `config` jsonb default `{"allowed_locales" => ["en"]}`; `archived` boolean
default false; `channel_web_widget_id` bigint; `ssl_settings` jsonb default `{}` NOT NULL; `platform_owned`
boolean default false NOT NULL.

Indexes: `channel_web_widget_id`; `custom_domain` UNIQUE; `slug` UNIQUE; and a **partial** index
`index_portals_on_platform_owned … WHERE platform_owned` (`db/schema.rb:1791`) — cheap because only two rows
match.

`config` is JSON-schema validated (`app/models/concerns/portal_config_schema.rb:29-68`) with
`additionalProperties: true`, and then separately key-allowlisted in Ruby against `CONFIG_JSON_KEYS`
(`app/models/portal.rb:88-89`, enforced at `:208-212`). Two gates, one of which (`CONFIG_JSON_KEYS`) is the real
one.

### 1.4 Model validations, callbacks, scopes, enums

**`Article`** (`app/models/article.rb`):

| Kind | What | Line |
|---|---|---|
| callback | `before_validation :ensure_account_id` → `self.account_id = portal&.account_id` | `:58`, `:230-232` |
| callback | `before_validation :ensure_article_slug` | `:59`, `:234-236` |
| callback | `before_validation :ensure_locale_in_article` | `:60`, `:200-206` |
| callback | `before_create :add_position_to_article` | `:72`, `:208-213` |
| callback | `after_save :category_id_changed_action, if: :saved_change_to_category_id?` | `:73`, `:188-198` |
| validation | `account_id` presence **unless** `platform_owned?` | `:65` |
| validation | `author_id` presence — **always** | `:66` |
| validation | `title` presence | `:67` |
| validation | `content` presence **only if** `published?` | `:68` |
| validation | `slug` **exclusion** from `%w[search articles categories]` | `:63`, `:69` |
| enum | `status: { draft: 0, published: 1, archived: 2 }` | `:75` |
| scopes | `search_by_{category_slug,category_locale,locale,author,status}`, `order_by_{updated_at,position,release_date,views}` | `:77-87` |
| search | `pg_search_scope :text_search` over `title:A, description:B, content:C`, prefix, normalization 2 | `:94-108` |

**What is NOT validated on `Article`, and matters:** no `slug` presence, no `slug` uniqueness, no `slug` format, no
`locale` inclusion, no `status` presence, no `description` presence, no `meta` shape, no length limit on anything.
Compare `Category`, which *does* validate `slug` presence (`app/models/category.rb:60`) and locale uniqueness
within `(slug, portal_id)` (`:63-64`) and locale membership in the portal's allowed set (`:62`, `:97-105`).

**`Portal`** validates `account_id` presence-unless-platform-owned *and* absence-if-platform-owned
(`app/models/portal.rb:57-58`) — both halves, deliberately, so neither state is reachable by accident; `name`
presence; `slug` presence + uniqueness + a reserved-slug list that exempts platform portals (`:39-40`, `:61`,
`:194-199`); `custom_domain` uniqueness; `color` hex format; and the config/analytics validations above.

### 1.5 `meta` jsonb: every key, and who writes it

Seven keys exist in this installation. Nothing enforces the set — `meta` is free-form jsonb with `default: {}`.

| Key | Written by | Read by | Status |
|---|---|---|---|
| `doc_key` | **seeder only** — `content_seeder.rb:107` | `Documentation::Library.article_for` → `where("articles.meta->>'doc_key' = ?", key)` (`library.rb:55`) | **the product↔corpus contract**; no editor surface writes it |
| `title` (SEO) | seeder `content_seeder.rb:108` (from `seo_title`, falling back to `title`); Super Admin `ArticleMetaField`; tenant API | `_meta_head.html.erb:8` → `<title>`, `og:title`, `twitter:title` | editor-writable |
| `description` (SEO) | seeder `:109` (from `seo_description`, falling back to `description`); Super Admin; tenant API | `_meta_head.html.erb:9,28,40,52`; `DocumentationHelper#documentation_article_schema` (`documentation_helper.rb:87`); SEO audit (`documentation_seo_audit.rake:85`) | editor-writable |
| `tags` | seeder `:110` as `Array(...)`; Super Admin (comma string → array, `super_admin/articles_controller.rb:47-52`); tenant API as `tags: []` | `_meta_head.html.erb:30-31` → `<meta name="tags">`; `_release_meta.html.erb:7` | editor-writable |
| `version` | seeder `:111` | `_release_meta.html.erb:5` | **populated in 0 of 2 changelog files** — `grep -l '^version:' custom/db/changelog` returns nothing |
| `release_date` | seeder `:112` | `_release_meta.html.erb:6`; `_header.html.erb:3` (suppresses "last updated"); `Article.order_by_release_date` (`article.rb:86`) | present in 2 of 2 changelog files, 0 of 126 doc files |
| `feature_image` | **Super Admin only** — `ArticleMetaField::STRING_KEYS` (`article_meta_field.rb:13`), labelled and hinted at `:21,:30` | **nothing.** `grep -rn feature_image app custom --include=*.rb --include=*.erb` finds only the field itself. The Vue `StackedChangelogCard.vue:59-75` that consumes `card.feature_image` is fed by `changelogAPI.fetchFromHub()` (`SidebarChangelogCard.vue:34`) — Chatwoot's hosted hub, not this `Article` | **dead authoring field** |

Corpus-measured front-matter coverage (126 doc files): `title` 126, `description` 126, `position` 126, `tags` 126,
`seo_description` 126, `seo_title` **28**, `version` 0, `release_date` 0.

### 1.6 Slug generation and uniqueness

Three different writers produce a slug, and they disagree.

1. **The seeder** sets it explicitly and deterministically: `slug_for(key, locale)` →
   `locale == 'en' ? key : "#{key}-#{locale}"` (`content_seeder.rb:85-87`). The file basename is the key
   (`:72`). This is the only writer that produces a stable, meaningful, reproducible slug.
2. **The model fallback**: `self.slug ||= "#{Time.now.utc.to_i}-#{title.underscore.parameterize(separator: '-')}" if title.present?` (`app/models/article.rb:234-236`).
3. **An editor**, by typing into `Field::String` (`article_dashboard.rb:17`, in `FORM_ATTRIBUTES` at `:36`).

Writer 2 has two defects an editor will hit.

- **`||=` does not fire on an empty string.** Administrate's `Field::String` form always posts
  `article[slug]`, and a blank input posts `""`. `"" ||= x` is `""`. So an article created in Super Admin with the
  slug box left empty is saved with `slug = ""` — the column is `null: false`, and `""` is not NULL, and `Article`
  has no `slug` presence validation. The resulting row 404s on `/docs/:article_slug`, whose route constraint is
  `/[a-z0-9][a-z0-9\-_]*/` (`config/routes/documentation.rb:26`), and the *second* such article raises
  `ActiveRecord::RecordNotUnique` against `index_articles_on_slug`.
- **The fallback is ASCII-only, so it cannot name an Arabic article.** `parameterize` calls `transliterate`,
  which substitutes `?` for anything with no ASCII approximation, then
  `gsub!(/[^a-z0-9\-_]+/i, separator)` and strips leading/trailing separators
  (`vendor/bundle/ruby/3.4.0/gems/activesupport-7.2.3.2/lib/active_support/inflector/transliterate.rb:123-147`).
  An all-Arabic title parameterizes to the empty string, so the generated slug is a bare epoch plus a trailing
  hyphen. Half the corpus is Arabic.

**Uniqueness is enforced only by the UNIQUE index, never by a validation.** `SuperAdmin::ArticlesController` has
no `rescue_from ActiveRecord::RecordNotUnique` — in this whole tree only
`app/controllers/super_admin/installation_configs_controller.rb:2` has one. So a slug collision in the authoring
form is an unrescued 500 and a Sentry event, not a form error. And because the index is **global**, the namespace
is shared with every tenant's help-center article: a tenant who creates `whatsapp-errors` first takes it from the
platform corpus permanently.

### 1.7 `associated_article_id` and the translation graph

A deliberately flat two-level graph, enforced in three places and constrained in none.

- Self-join: `has_many :associated_articles` (inverse `root_article`) + `belongs_to :root_article, optional: true`,
  both over `associated_article_id`, `dependent: :nullify` (`app/models/article.rb:40-50`).
- Flattening: `Article.find_root_article_id(article)` returns `article.associated_article_id || article.id`, and
  `associate_root_article` writes that, "to avoid the deeper associations" (`article.rb:125-138`). So a translation
  always points at the root, never at another translation.
- The seeder writes it directly, skipping `associate_root_article` entirely:
  `article.associated_article_id = root_article_id(key) unless locale == 'en'`, where `root_article_id` is
  `portal.articles.find_by(slug: key, locale: 'en')&.id` (`content_seeder.rb:77,90-92`).
- **Order is load-bearing**: `locales` sorts the default locale first precisely so the English row exists before any
  translation looks for it (`content_seeder.rb:41-45`). Seed Arabic alone and `associated_article_id` comes back
  `nil`, silently — `&.id` swallows it, and nothing validates the result.
- The graph is what hreflang is built from: `DocumentationHelper#article_translation_family` is
  `([root] + root.associated_articles) .select { published } .uniq(&:id) .sort_by(&:locale)`
  (`documentation_helper.rb:106-110`), consumed by `portal_locale_alternates` (`:44-49`) and
  `portal_default_alternate_url` (`:54-60`), and audited for reciprocity, `x-default` and duplicate locales by
  `lynomia:docs:seo_audit` (`documentation_seo_audit.rake:97-114`).
- **No FK, and no guard against a cycle or a self-reference.** `associate_root_article` at least scopes the lookup
  to the same portal (`article.rb:126`); the seeder's direct write does not need to. A hand-written
  `associated_article_id` pointing at the article's own id would make `article_translation_family` emit the article
  twice, which `uniq(&:id)` then collapses — so the audit's duplicate-locale check would not catch it.

### 1.8 `views`

Write path: exactly one. `increment_view_count` → `update_column(:views, views? ? views + 1 : 1)`
(`article.rb:144-148`), called only from the 1×1 tracking pixel
(`public/api/v1/portals/articles_controller.rb:35-48`), only when published, with a 24-hour private cache.
`update_column` skips validations and `updated_at` — correct, since `updated_at` is published as
`article:modified_time` (`_meta_head.html.erb:43`) and `dateModified` (`documentation_helper.rb:91`).

Read path: `order_by_views` (`article.rb:87`), used by `?sort=views`
(`articles_controller.rb:65-66`), by `@featured` (`portal_home_data.rb:18`) and by
`_featured_articles.html.erb:2`.

**The column has no default and the seeder never sets it**, so every seeded article is `views IS NULL`.
`order_by_views` is a bare `reorder(views: :desc)`, and in Postgres `DESC` sorts NULLs **first**. The sibling scope
one line above knows this — `order_by_release_date` spells out `DESC NULLS LAST` (`article.rb:86`) — and
`order_by_views` does not. Consequence: the documentation home page's "Recommended" block, which falls back to
`@featured` when nothing is curated (`show.html+documentation.erb:22`), currently shows six arbitrary never-viewed
articles rather than the six most-read ones.

Worse, the curated alternative is unreachable from the UI. `@recommended_articles` comes from
`portal.popular_article_ids` → `config['popular_content'][locale]['article_ids']` (`portal.rb:173-175`), and
`PortalDashboard::FORM_ATTRIBUTES` is `%i[name page_title header_text color custom_domain homepage_link archived]`
— **`config` is in `SHOW_PAGE_ATTRIBUTES` but not in `FORM_ATTRIBUTES`** (`portal_dashboard.rb:27-31`). So
`popular_content`, `locale_translations`, `article_order`, `layout` and `analytics` are all visible and none are
editable. Curating the documentation home page today requires a Rails console.

### 1.9 `author`

`belongs_to :author, class_name: 'User'` (`article.rb:56`), `validates :author_id, presence: true` (`:66`), no FK.

- Super Admin: `new_resource` forces `author: current_super_admin` (`super_admin/articles_controller.rb:35-37`).
  `author` is in `SHOW_PAGE_ATTRIBUTES` and **not** in `FORM_ATTRIBUTES` (`article_dashboard.rb:33,36`) — so it is
  set once at creation and never editable.
- Seeder: `@author = author || SuperAdmin.first || raise(ArgumentError, …)` (`content_seeder.rb:22`), applied as
  `article.author ||= author` (`:79`) — so an operator-set author **survives** a re-run, unlike every other
  field. Note `changed?` is captured at `:78`, *before* that line, so filling in a missing author counts as
  "unchanged" in the task's own report.
- `ArticleAuthorField` renders the author as text rather than a link, because `SuperAdmin` is an STI subclass of
  `User` and Administrate's `BelongsTo` would `link_to` a nonexistent `super_admin_super_admin_path` and 500 the
  show page (`custom/app/fields/article_author_field.rb:6-9`).
- Author is **never** published: `documentation_article_schema` sets `author` to the Organization, explicitly so a
  staff member's identity is not put into public structured data (`documentation_helper.rb:80-92`). But
  `_avatar_group.html.erb` / `build_category_contributors` (`portal_home_data.rb:54-64`) do surface authors on the
  portal home page, which is worth 087's attention, not mine.

### 1.10 `status`

Enum `draft: 0, published: 1, archived: 2` (`article.rb:75`). The column is `integer`, **nullable, with no
default** — so `status IS NULL` is representable, and a NULL-status row satisfies none of `Article.published`,
`.draft` or `.archived`, making it invisible to `Documentation::Library.articles` (`library.rb:43`), to all three
Super Admin collection filters (`article_dashboard.rb:38-42`) and to the public portal. No authoring path produces
it — Administrate's `Field::Select` defaults to `include_blank: false`
(`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/lib/administrate/field/select.rb:27-29`) and the tenant API
defaults to `:draft` (`articles_controller.rb:28`) — so it is reachable only by a direct write. Worth a NOT NULL
+ default in any migration that touches this table.

`archived` is a third state the corpus pipeline does not know about: the seeder forces
`@publish ? :published : :draft` on every run (`content_seeder.rb:101`), so archiving a seeded article in Super
Admin is undone by the next `rails documentation:content`.

### 1.11 The APIs, all three of them

**(a) Tenant-facing JSON — present in code, dead in this product.**

`/api/v1/accounts/:account_id/portals/:portal_id/articles` (`config/routes.rb:343-345`) plus
`articles/bulk_actions` (`:335-342`). The controller is a full CRUD + reorder + draft-autosave implementation
(`app/controllers/api/v1/accounts/articles_controller.rb`), with the most interesting authoring primitive in the
whole codebase at `:94-106`: a draft-only autosave detects that the submitted keys are exactly
`draft_title`/`draft_content`, assigns, validates, and then persists with `update_columns` so the public-facing
`updated_at` is not bumped.

**All of it is unreachable.** Every action runs `before_action :check_authorization` (`:3`), which resolves to
`authorize(Article)` (`app/controllers/api/base_controller.rb:14-18`), and `Custom::ArticlePolicy` — prepended via
`ArticlePolicy.prepend_mod_with` (`app/policies/article_policy.rb:31`) resolved against `ChatwootApp.extensions ==
['custom']` (`lib/chatwoot_app.rb:42-44`) — returns `false` from `index?`, `show?`, `create?`, `update?`, `edit?`,
`destroy?` and `reorder?` unconditionally (`custom/app/policies/custom/article_policy.rb:7-13`). The bulk-actions
controller authorizes through `authorize(Article, :create?)`, so one `false` closes its four actions too
(`bulk_actions_controller.rb:47-49`, and the policy comment says so at `:3-5`). `Custom::PortalPolicy` does the
same for portals (`custom/app/policies/custom/portal_policy.rb:24-35`).

So: **there is no JSON authoring API for documentation.** The serializers (`_article.json.jbuilder`, which exposes
`meta` wholesale at `:12`), the Vue editor pages (`PortalsArticlesEditPage.vue`), the Vuex module and the
`draft_title`/`draft_content` columns are all orphaned machinery. They are also *free material* — see §4 Option B.

One article-shaped endpoint is **not** policy-gated: `GET /api/v1/accounts/:id/search/articles`
(`config/routes.rb:152`) → `SearchService#filter_articles` → `current_account.articles.text_search(…)`
(`app/services/search_service.rb:177-182`). It is account-scoped, and a platform article has `account_id = NULL`,
so it returns nothing of ours. Harmless, but it is an unauthorized `Article` read path and 086/096 should know.

**(b) Public-facing — read-only, and the real renderer.**

`config/routes.rb:508-519`. For articles: `#index` (list/search, `?query` `?locale` `?sort` `?page` `?per_page`
capped at 100, `articles_controller.rb:52-58`), `#show` (HTML), `#show_markdown`
(`/hc/:slug/articles/:article_slug.md`, serves raw CommonMark as `text/markdown`, published-only at `:29-33`), and
`#tracking_pixel`. `set_article` scopes to `.published` **except** for a signed-in super admin, which is the
preview path (`:80-88`). Plus the Lynomia entry points `/docs`, `/docs/:article_slug`, `/changelog`
(`config/routes/documentation.rb:22-27`) and the documentation layout variants.

**(c) Super Admin — the only authoring surface, and it is HTML forms.**

`config/routes/documentation.rb:6-18`: `resources :articles` + member `publish` / `unpublish` / `preview`;
`resources :categories` (full CRUD); `resources :portals, only: [:index, :show, :edit, :update]`.
`SuperAdmin::ArticlesController` (54 lines) scopes everything through
`scoped_resource = Article.where(portal: Documentation::Library.portals)`
(`super_admin/articles_controller.rb:29-31`) — one place, covering index/show/edit/update/destroy alike. Auth is
`before_action :authenticate_super_admin!` (`app/controllers/super_admin/application_controller.rb:16`); CSRF is
Administrate's `protect_from_forgery with: :exception`
(`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:3`).
Mass assignment is `params.require(…).permit(dashboard.permitted_attributes(action_name))`
(ibid. `:203-207`), where `permitted_attributes` maps each `FORM_ATTRIBUTES` entry through its field's
`permitted_attribute` (`lib/administrate/base_dashboard.rb:71-85`).

The editor itself is `content: Field::Text.with_options(rows: 28)` (`article_dashboard.rb:19`). A 28-row textarea.

---

## 2. Constraints the existing system imposes

An editor upgrade must not break any of these. They are facts about the data, not preferences.

1. **`articles.slug` is globally unique, forever** (`db/schema.rb:226`). Per-locale slugs cannot be made equal
   without a migration that drops that index, and that index is upstream Chatwoot's. The `-ar` convention
   (`content_seeder.rb:85-87`) is therefore permanent unless the program chooses to change the index.
2. **`meta['doc_key']` is the product↔corpus contract.** 87 keys in
   `app/javascript/dashboard/helper/documentationLinks.js` resolve through `library.rb:55`. Any save path that
   replaces `meta` wholesale breaks contextual help. See Finding 3.1.
3. **The seeder owns `title`, `description`, `content`, `category`, `position`, `status` and `meta` outright** —
   `assign_attributes(attributes_for(…))` (`content_seeder.rb:76,94-104`). Whatever an editor writes to those is
   discarded by the next `rails documentation:content`. Only `author` survives (`:79`), and only when absent.
4. **A platform portal has `account_id = NULL`, and that is the tenant-isolation mechanism**
   (`app/models/portal.rb:42-46,57-58`; migration rationale at
   `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:6-9`). An editor feature must never
   backfill an account onto a platform article.
5. **`locale` is derived from `category`, not chosen.** `ensure_locale_in_article` sets
   `self.locale = category.locale` whenever a category is present (`article.rb:200-206`). The Super Admin form
   offers both (`article_dashboard.rb:20,36`), and the category silently wins.
6. **`account_id` is derived from `portal`.** `ensure_account_id` overwrites it on every validation
   (`article.rb:230-232`). It is not writable, by anyone, ever.
7. **`position` is auto-assigned on create and re-spaced on category change**
   (`article.rb:72,208-228`, `:188-198`), and the corpus's front matter makes it mandatory
   (`content_seeder.rb:100` uses `fetch`).
8. **English must be seeded before any other locale** or `associated_article_id` is nil
   (`content_seeder.rb:41-45,90-92`), which costs hreflang (`documentation_helper.rb:106-110`) and fails the SEO
   audit's reciprocity check (`documentation_seo_audit.rake:97-107`).
9. **`lynomia:docs:seo_audit` exits 1 on an error** (`documentation_seo_audit.rake:149`). A new authoring field
   that lets an editor blank a description, duplicate a canonical or orphan an hreflang turns a release into a
   blocker by construction.
10. **The Markdown must round-trip.** `#show_markdown` serves `article.content` verbatim as `text/markdown`
    (`public/api/v1/portals/articles_controller.rb:32`), and `ChatwootMarkdownRenderer` is the only HTML producer
    (`:110`). Any editor that cannot emit the same CommonMark it consumed breaks both the `.md` endpoint and the
    file-vs-database diff the seeder depends on.
11. **Articles have no ActiveStorage attachment of any kind.** `grep has_one_attached app/models/article.rb` is
    empty; the only attachment in the subsystem is `Portal#logo` (`app/models/portal.rb:50`). The sole historical
    trace of article media is a 2023 migration that rewrote `rails/active_storage` URLs embedded *in the Markdown
    body* (`db/migrate/20230515051424_update_article_image_keys.rb:40-46`) — i.e. upstream's media model is
    "a signed blob URL pasted into the content", not an association. 066 and 068 own this; it is the single
    biggest absence in the model.

---

## 3. Findings

### 3.1 BLOCKER — every Super Admin save of a seeded article destroys `meta['doc_key']`

The chain:

- `ArticleMetaField.permitted_attribute` returns `{ meta => STRING_KEYS + [{ tags: [] }, :tags] }`, i.e.
  `title description version release_date feature_image tags` (`custom/app/fields/article_meta_field.rb:13,33-35`).
  **`doc_key` is not in that list, and the form has no hidden field for it**
  (`custom/app/views/fields/article_meta_field/_form.html.erb:5-21`).
- `resource_params` passes the permitted hash through `normalized_meta`, which does `meta.to_h.compact_blank` and
  splits tags (`custom/app/controllers/super_admin/articles_controller.rb:39-52`).
- Administrate's `update` is `requested_resource.update(resource_params)`
  (`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:57`).
- Assigning a jsonb attribute **replaces** it. There is no merge anywhere in that path.

So editing an article's SEO title in Super Admin writes `meta = {"title" => "...", "description" => "...",
"tags" => [...]}` and drops `doc_key`. `Documentation::Library.article_for(key, locale:)` then falls through
`by_key.find_by(locale:)` → `find_by(locale: 'en')` → `by_key.first` → `article(key)`
(`library.rb:54-57`), and that last literal-slug fallback is the only reason this is not instantly visible: it
still resolves the **English** article, because the English slug *is* the key (`content_seeder.rb:86`). For an
Arabic article, whose slug is `key-ar`, every fallback misses and the contextual-help link 404s via
`documentation_controller.rb:18-26`.

Impact: an editor doing exactly what the UI invites — fixing an SEO description — silently breaks locale-aware
contextual help for that article until the next `rails documentation:content` run restores `doc_key`. Nothing
reports it. No spec covers it (`grep -rn doc_key spec/` is empty).

Minimum fix, in the existing surface: merge rather than replace in `normalized_meta`, i.e. build from
`requested_resource.meta` and overlay the permitted keys. One line, no migration.

### 3.2 MAJOR — there is no authoring API, only forms

Every authoring mutation in this product is an HTML form POST to Administrate, authenticated by a Devise
`:super_admin` session cookie. Consequences for the editor programme:

- A rich editor cannot autosave, validate-as-you-type, upload a figure, or preview without a JSON endpoint. It
  would have to post the whole form.
- `draft_title` / `draft_content` — the exact columns a dirty-state-safe editor needs — exist in the schema
  (`db/schema.rb:220-221`), are serialized (`_article.json.jbuilder:7-8`), have a correct non-timestamp-bumping
  write path (`articles_controller.rb:94-106`), and are **not in `ArticleDashboard::FORM_ATTRIBUTES` or
  `SHOW_PAGE_ATTRIBUTES`** (`article_dashboard.rb:32-36`). The capability is paid for and unused.
- `preview` is a full-page redirect to `/hc/:portal/articles/:slug?show_plain_layout=true`
  (`super_admin/articles_controller.rb:22-25`), which means previewing navigates away from the form. There is no
  unsaved-content preview at all, and no side-by-side.

### 3.3 MAJOR — blank or non-Latin slugs are accepted, and collisions are 500s

Per §1.6: `self.slug ||=` cannot fire on the `""` that the form posts; `Article` validates neither presence nor
uniqueness nor format on `slug`; the only enforcement is the UNIQUE index; and no `rescue_from
ActiveRecord::RecordNotUnique` exists on the controller. Three distinct outcomes, all bad: an unroutable empty
slug, an epoch-only slug for any Arabic title, and an unrescued 500 on collision. The reserved-slug list is
validated (`article.rb:63,69`) — which proves slug validation was considered and only this one rule was written.

### 3.4 MAJOR — `order_by_views` has no `NULLS LAST`, so "featured" is inverted

Per §1.8. `reorder(views: :desc)` (`article.rb:87`) over a column with no default that the seeder never populates,
in Postgres, puts every never-viewed article ahead of every read one. Three call sites
(`portal_home_data.rb:18`, `articles_controller.rb:66`, `_featured_articles.html.erb:2`). The fix is the pattern
already used one line above it for `release_date`.

### 3.5 MAJOR — portal `config` is show-only, so nothing curated can be curated

`PortalDashboard` lists `config: SerializedField` in `ATTRIBUTE_TYPES` and `SHOW_PAGE_ATTRIBUTES` and omits it from
`FORM_ATTRIBUTES` (`portal_dashboard.rb:19,28,31`). That locks `popular_content` (the home page's Recommended
topics and articles, `portal.rb:169-175`), `locale_translations` (per-locale portal name/title/header,
`portal.rb:151-159`), `article_order` (`portal.rb:165-167`), `layout` and `analytics` out of the UI. The portal
seeder preserves `layout` across re-runs specifically so an operator's choice survives
(`custom/app/services/documentation/portal_seeder.rb:55-56`) — but there is no way for an operator to make that
choice.

### 3.6 MINOR — `meta['feature_image']` is an authoring field nothing reads

Per §1.5. Labelled, hinted, permitted, persisted, and consumed by nobody. An editor filling it in gets no effect
and no warning. Either wire it to `_release_meta.html.erb` or remove it; leaving it is a promise the product does
not keep.

### 3.7 MINOR — the `locale` select is a lie whenever a category is chosen

`ensure_locale_in_article` (`article.rb:200-206`) overwrites the submitted `locale` with `category.locale`. Both
fields are in the same form (`article_dashboard.rb:36`). An editor who picks category "Getting started (en)" and
locale "ar" gets `en`, with no message. `Category` validates its own locale against the portal's allowed set
(`category.rb:62,97-105`); `Article` validates `locale` not at all.

### 3.8 MINOR — `meta['tags']` as a string would 500 the public page

`_meta_head.html.erb:30-31` does `article.meta["tags"].present?` then `.join(',')`. Both current writers normalize
to an array (`content_seeder.rb:110` via `Array()`; `super_admin/articles_controller.rb:51`), and the tenant API
permits `tags: []` — so this is not reachable today. It becomes reachable the moment a new authoring path writes
`meta` without the normalizer, which is exactly what an editor upgrade is.

### 3.9 Structural notes for the record

- **No FK anywhere on `articles`** (§1.1). A `category_id` pointing at a deleted category survives
  `dependent: :nullify` only if the delete went through the model; a raw SQL delete leaves a dangling pointer that
  `documentation_breadcrumb_schema` (`documentation_helper.rb:64-75`) would then build a nameless crumb from — which
  the SEO audit does catch (`documentation_seo_audit.rake:122-123`).
- **No index on `meta->>'doc_key'`**, confirming `01-current-system.md` §9.1. Every contextual-help resolution is a
  sequential scan (`library.rb:55`).
- **No composite `(portal_id, status, locale)` index** for the query every public page runs (§1.1).
- **`status` is nullable with no default** (§1.10).
- **The model annotation in `app/models/article.rb:19` is wrong** about `account_id not null` (§1.1).
- `Category` has no `paginates_per` problem but `Limits::CATEGORIES_PER_PAGE = 1000` (`lib/limits.rb:7`,
  `category.rb:28`) means category pagination is effectively off; `Article` declares no `paginates_per` at all, so
  Kaminari's default applies to `#index`.

---

## 4. Options

### Decision 1 — where a new authoring field goes: migration, or a `meta` key?

This is the question the brief asks, so here is the cost of each, measured against this code.

**A `meta` key costs:** one entry in `ArticleMetaField::STRING_KEYS` + `LABELS` + `HINTS`
(`article_meta_field.rb:13-31`) — the `_form.html.erb` iterates `STRING_KEYS`, so the form updates itself; one key
in `ContentSeeder#meta_for` (`content_seeder.rb:106-113`) if it is file-backed; one front-matter key per corpus
file. No migration, no deploy ordering, no downtime. What it gives up: **no type, no NOT NULL, no default, no
index, no uniqueness, no FK, no validation that the key is even spelled right.** `meta` is free-form jsonb with
`default: {}` and nothing validates its shape. A typo'd key is silently stored and silently never read — exactly
how `feature_image` became dead weight (§3.6). Querying it means `meta->>'key'`, which is a sequential scan
without an expression index, which `doc_key` already demonstrates (§3.9).

**A column costs:** one migration in `custom/db/migrate/`, which the deploy already runs at stage 5
(`01-current-system.md` §4), plus the schema.rb diff. What it gives: a type, a default, NOT NULL if wanted, an
index if wanted, a model validation that fails loudly, and a cheap `WHERE`. On a 124-row table an
`add_column` + backfill is instant; this is not a scale consideration.

**Recommendation — a three-way rule, not a single answer:**

| The field is… | Put it… | Because |
|---|---|---|
| queried, filtered, sorted, or joined on | **a column** | `meta->>` has no index, and the one key already queried that way (`doc_key`) is the program's known performance weak point. Add an index in the same migration. |
| required, or has an invariant the product must enforce | **a column** | `meta` cannot be validated. `validates` on a column fails loudly at the model, which is what CLAUDE.md asks for. A required field in `meta` is a field that is sometimes absent. |
| per-article presentation metadata, read only when rendering that one article | **a `meta` key** | This is what `meta` is already for and is already good at — the five live keys (§1.5) are exactly this shape, and `ArticleMetaField` makes adding one nearly free. |

Applied to the fields this programme is likely to want:

- **SEO title / description / tags** — already `meta`, already rendered, already audited. Leave them.
- **A Meta error code, or an error family** (charter §8.4) — **column + index**, or a column + a GIN index on a
  jsonb array if an article can carry several. These will be looked up by code (`whatsappErrorArticle(code)` in
  `documentationLinks.js` is the existing shape), and a lookup is a query. Putting an error code in `meta` repeats
  the `doc_key` mistake knowingly.
- **`doc_key` itself** — **promote it to a column**, `null: true` for tenant articles, with an index, and
  ideally `UNIQUE (portal_id, locale, doc_key)`. It is the contract (§2.2), it is queried on every contextual-help
  resolution, it is the thing §3.1 silently destroys, and a column cannot be dropped by a jsonb reassignment. This
  single migration fixes 3.1 structurally rather than by remembering to merge, closes
  `01-current-system.md` §9.1, and makes the English/Arabic pair expressible as a constraint instead of a naming
  convention.
- **Alt text, figure captions, structured components** — neither. Those belong in the Markdown body, which is the
  source of truth and already round-trips (§2.10). 071 owns the component syntax.
- **A review/approval state beyond draft/published/archived** — **a column**, and expect it to collide with
  `content_seeder.rb:101`, which force-writes `status` on every run (§2.3). Resolve the seeder's ownership first
  (charter §8.1); do not add a state the sync will overwrite.

### Decision 2 — the authoring transport: extend Administrate, or revive the JSON API?

**Option A — stay on Administrate forms.** Cheapest. Fixes 3.1/3.3/3.5/3.7 with small, cited, low-risk changes:
merge `meta` instead of replacing; add `slug` presence/format/uniqueness validations and a `rescue_from`; add
`draft_title`/`draft_content` and `author` to the right dashboard constants; add `config` to
`PortalDashboard::FORM_ATTRIBUTES` behind a proper field. Ceiling: no autosave, no live preview, no upload, no
dirty-state guard — because there is no endpoint to talk to.

**Option B — revive the tenant JSON controller for platform content.** The whole surface already exists and is
good: CRUD, reorder, bulk status/category/delete, and the draft-autosave primitive at
`articles_controller.rb:94-106` that writes `draft_*` with `update_columns` so the public `updated_at` does not
move. It is dead only because `Custom::ArticlePolicy` denies it (§1.11a). Reviving it for *platform* content
means a **new** super-admin-authenticated namespace that reuses the controller's logic — **not** relaxing
`Custom::ArticlePolicy`, which is the tenant-isolation guarantee (`custom/app/policies/custom/portal_policy.rb:1-23`
explains why it is a policy and not a route deletion) and must not be touched.

**Option C — a second CMS.** Forbidden by charter §2.

**Recommendation: A now, B as the Phase 5 target, and never C.** Do A's fixes regardless — 3.1 is a live
correctness bug and its fix is one line, independent of any editor decision. Then build the editor against a
super-admin-scoped JSON endpoint that reuses the existing controller's logic, because the three things the
charter's §1.4 complaint actually needs — autosave, side-by-side preview, media insertion — each require a JSON
round-trip, and the draft columns, the serializer and the non-timestamp-bumping write path are already written and
already correct. That is extension in the charter's sense: the model is unchanged, the policy is unchanged, the
public renderer is unchanged, and the only new thing is a route and a controller that calls code that exists.

### Decision 3 — three small fixes that are not editor decisions

- `order_by_views` → `reorder(Arel.sql('articles.views DESC NULLS LAST, articles.position ASC'))`, matching
  `order_by_release_date` one line above (`article.rb:86-87`). Fixes §3.4 for all three call sites.
- `articles.status` → `null: false, default: 0` in whatever migration next touches the table (§1.10).
- Correct the `account_id :integer not null` line in the model annotation (`article.rb:19`), which has been wrong
  since the platform-ownership migration.

---

## 5. Risks

1. **`doc_key` loss is already happening and is invisible.** Production has 124 published articles and an
   authoring UI that drops `doc_key` on save (§3.1). Nobody knows how many rows have lost it, because the English
   literal-slug fallback masks it (`library.rb:57`). Before anything else: a read-only count of
   `Documentation::Library.articles.where("meta->>'doc_key' IS NULL")`. If that is non-zero, Arabic contextual help
   is already broken for those articles. I could not run it — **unverified, needs a production-safe read.**
2. **Promoting `doc_key` to a column is a two-writer migration.** The seeder writes `meta['doc_key']`
   (`content_seeder.rb:107`) and the Library reads it (`library.rb:55`). Both change in one commit, or the
   contextual-help registry breaks for every article. Backfill from `meta`, keep the `meta` key written for one
   release, then drop it — and note that `UNIQUE (portal_id, locale, doc_key)` will **fail to create** if risk 1
   turns out to be real, because NULLs are fine but duplicates from a partial restore are not.
3. **Any editor that cannot round-trip CommonMark breaks two things at once**: `#show_markdown`
   (`public/api/v1/portals/articles_controller.rb:29-33`) serves the body verbatim, and the file-vs-database diff
   the seeder's created/updated/unchanged counters depend on (`content_seeder.rb:78,115-123`) becomes noise. 067
   owns the evaluation; this is the constraint it must be evaluated against.
4. **A richer editor meets an unproven sanitizer.** `01-current-system.md` §5 records that no `sanitize` call
   appears in the article render path and that `ChatwootMarkdownRenderer#render_article` ends in `html_safe`.
   Anything that lets an author paste HTML, embed a figure or add a component multiplies that exposure. 065, 081,
   082, 084 own it. **Not checked by me** — out of scope and I did not read the renderer.
5. **Media has no model at all** (§2.11). The only historical article-media mechanism is a signed ActiveStorage URL
   pasted into the Markdown body (`db/migrate/20230515051424_update_article_image_keys.rb`), which is why that
   migration had to exist: those URLs rot. Charter §8.3 must settle ownership before an upload button is drawn.
   066, 068, 083 own it.
6. **Adding authoring fields widens the SEO audit's blast radius.** It exits 1 on an error
   (`documentation_seo_audit.rake:149`) and audits data, not templates. A field that lets an editor blank a
   description or create a duplicate canonical converts an editor mistake into a failed release. Validate at the
   authoring boundary — which, per CLAUDE.md, is the controller — rather than discovering it at deploy.
7. **`archived` and any new state collide with the seeder's forced `status`** (§2.3, `content_seeder.rb:101`).
   Charter §8.1's source-of-truth decision gates this; an editor-facing workflow state added before that decision
   will be overwritten on the next sync.
