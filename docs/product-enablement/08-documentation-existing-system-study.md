# Help Center existing system study

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Provenance: the `help_center` area inventory, corrected by the `help-center-global-docs` adversarial verifier. Where
they disagreed the verifier wins and the line is marked **(V)**. Claims marked **(R)** I reproduced myself against this
HEAD; **(R≠)** means I reproduced it and got a *different* answer from the corrections file, and the number shown is
mine. Claims I could not cite are marked **UNVERIFIED**. No migration is proposed anywhere in this document — where one
would be needed the requirement is stated and left for approval.

Covers brief parts **0.11, 7.1**.

---

## 1. The decision in one page

**The existing Help Center can carry Lynomia product documentation. It is an EXTEND, not a NEW PRIMITIVE, and the
recommended path needs no migration. The three things that make it work are already true; the one thing that can break
it is a global slug namespace with no reservation.**

What is already true:

1. **The public reader is globally scoped.** `Portal.find_by!(slug: params[:slug], archived: false)`
   (`app/controllers/public/api/v1/portals_controller.rb:26`, same lookup at
   `app/controllers/public/api/v1/portals/base_controller.rb:35`) — no account id appears in any `/hc` route
   (`config/routes.rb:649-660`) **(R)**. One portal owned by one internal Lynomia account already serves at
   `/hc/<slug>` to the whole world.
2. **The host guard does not block a branded install.** `DomainHelper.chatwoot_domain?` does not test for a Chatwoot
   domain; it compares `request.host` against the hosts of `ENV['FRONTEND_URL']` and `ENV['HELPCENTER_URL']`
   (`app/controllers/concerns/domain_helper.rb:2-4`) **(V)(R)**. A Lynomia install serving from its own configured host
   passes. The flip side: if neither env var is set, `URI.parse('').host` is `nil`, the list is `[nil, nil]`, and every
   guarded portal page returns 401 with a hardcoded `support@chatwoot.com` message
   (`app/controllers/public_controller.rb:9-20`) **(V)(R)**.
3. **The account feature gate is cloud-only.** `ensure_portal_feature_enabled` returns early unless
   `ChatwootApp.chatwoot_cloud?` (`app/controllers/public_controller.rb:22-27`) **(R)**, so a self-hosted Lynomia
   install serves every non-archived portal regardless of the `help_center` account feature
   (`config/features.yml:42-45`).

What can break it:

**Portal slugs are a single global, first-come-first-served namespace with no reservation.**
`app/models/portal.rb:44` is a bare `validates :slug, presence: true, uniqueness: true`; there is no Portal
`RESERVED_SLUGS` — the only `RESERVED_SLUGS` in the repo is Article's (`app/models/article.rb:61`) **(V)(R)**. Worse,
tenant onboarding actively claims slugs globally: `Onboarding::HelpCenterCreationService#slug_candidates` tries
`<account-name>`, `<first-token>`, `<first-token>-docs`, `<first-token>-help` against a global `Portal.exists?(slug:)`
(`enterprise/app/services/onboarding/help_center_creation_service.rb:114-124`) **(V)(R)**. Tenant onboarding will
automatically grab the obvious docs slugs. A slug reservation is the one genuinely new guard required.

Headline verdict: **EXTEND**. Detail in §11.

---

## 2. Object model

Three live tables, three dead ones.

### 2.1 Article — `db/schema.rb:202-229`

| Column | Line | Type / default | Notes |
|---|---|---|---|
| `account_id` | :203 | integer **NOT NULL** | never client-supplied; copied from portal by `ensure_account_id` (`app/models/article.rb:221-223`) |
| `portal_id` | :204 | integer **NOT NULL** | |
| `category_id` | :205 | integer | optional (`app/models/article.rb:52`) |
| `folder_id` | :206 | integer | **dead**, see §2.4 |
| `title` | :207 | string | `validates :title, presence: true` (`article.rb:65`) |
| `description` | :208 | text | summary/excerpt; weighted `B` in search (`article.rb:93`); **no dashboard writer**, see §6 |
| `content` | :209 | text | required only when published (`article.rb:66`) |
| `status` | :210 | integer | `enum status: { draft: 0, published: 1, archived: 2 }` (`article.rb:73`); indexed :227 |
| `views` | :211 | integer | bumped by `increment_view_count` via `update_column` (`article.rb:135-139`); indexed :228 |
| `created_at` / `updated_at` | :212-213 | datetime NOT NULL | `updated_at` is the sitemap `lastmod` and is deliberately *not* bumped by draft autosave (§4.2) |
| `author_id` | :214 | bigint | `validates :author_id, presence: true` (`article.rb:64`); must belong to the account |
| `associated_article_id` | :215 | bigint | translation root link; self-join at `article.rb:40-50` |
| `meta` | :216 | jsonb default `{}` | the only SEO store: `title`, `description`, `tags[]` (`articles_controller.rb:111-113`) |
| `slug` | :217 | string **NOT NULL** | **GLOBAL unique index** :226 |
| `position` | :218 | integer | 10-step spacing, server-rebalanced (§2.2) |
| `locale` | :219 | string default `"en"` **NOT NULL** | inherited from the category by `ensure_locale_in_article` (`article.rb:191-197`) |
| `draft_title` | :220 | string | single-slot unpublished buffer (§4.2) |
| `draft_content` | :221 | text | single-slot unpublished buffer (§4.2) |

Slug is auto-generated once and never regenerated:
`self.slug ||= "#{Time.now.utc.to_i}-#{title.underscore.parameterize(separator: '-')}"`
(`app/models/article.rb:225-227`) **(R)**. Public article URLs therefore carry an epoch prefix. `RESERVED_SLUGS` is
`%w[search articles categories]` (`article.rb:61`), enforced by `validates :slug, exclusion:` (`:67`) — these three
collide with the `/hc/:slug/:locale/...` route segments.

Search is Postgres full text: `pg_search_scope :text_search` weighting `title: 'A'`, `description: 'B'`,
`content: 'C'`, with `prefix: true` and `normalization: 2` (`app/models/article.rb:89-103`), wrapped by
`Article.search` (`:105-114`).

### 2.2 Position and the 10-step rebalance

`before_create :add_position_to_article` (`app/models/article.rb:70`) seeds a position. Reordering is server-authoritative:
`Article.update_positions(portal:, positions_hash:)` writes the client's requested positions inside a transaction, then
`rebalance_positions` re-spaces every touched category through `resequence_category`, which assigns
`new_position = (index + 1) * 10` and returns the final map to the caller
(`app/models/article.rb:141-174`, both helpers `private_class_method` at `:175`) **(R)**. The controller echoes the
rebalanced map back (`app/controllers/api/v1/accounts/articles_controller.rb:44-47`). Categories have the same pattern
(`app/models/category.rb:76`). This is a solid, reusable ordering primitive — **REUSE**.

### 2.3 Portal — `db/schema.rb:1539-1557`

`account_id` integer **NOT NULL** (:1540), `name` NOT NULL (:1541), `slug` NOT NULL with UNIQUE index (:1542, :1556),
`custom_domain` with UNIQUE index (:1543, :1555), `color` (:1544), `homepage_link` (:1545), `page_title` (:1546),
`header_text` (:1547), `config` jsonb default `{"allowed_locales" => ["en"]}` (:1550), `archived` boolean default false
(:1551), `channel_web_widget_id` (:1552), `ssl_settings` jsonb NOT NULL (:1553) **(R)**.

Portal is hard-scoped to an account: `belongs_to :account` (`app/models/portal.rb:33`),
`validates :account_id, presence: true` (`:42`). **There is no accountless/global portal and no global or system
account concept anywhere in the repo** — a grep for `global_portal|system_account|internal_account|docs_portal|is_global|
system_owned` across `app`, `enterprise`, `custom`, `config`, `lib` returns nothing **(V)**.

`config` is schema-validated (`JsonSchemaValidator` against `PortalConfigSchema`, `app/models/portal.rb:50-52`) and
carries: `default_locale`, `allowed_locales`, `draft_locales`, `layout`, `social_profiles`, `locale_translations`,
`popular_content`, `analytics`. Derived readers: `default_locale` (`:98`), `allowed_locale_codes` (`:102`),
`draft_locale_codes` (`:109`), `public_locale_codes` (`:115`), `draft_locale?` (`:119`), `display_title` (`:128`),
`layout` defaulting to `'classic'` (`:142`), `popular_category_ids` / `popular_article_ids` capped at 3 / 6
(`:146-152`). `scope :active` is `where(archived: false)` (`:54`). `has_one_attached :logo` (`:37`) is the only real
attachment in the subsystem.

### 2.4 Category, and the three dead tables

Category — `db/schema.rb:608-627`: `account_id` / `portal_id` NOT NULL, `position` (:613), `locale` default `"en"`
(:616), `slug` NOT NULL, `parent_category_id` (:618), `associated_category_id` (:619), `icon` (:620), `icon_color`
(:621), UNIQUE on `(slug, locale, portal_id)` (:626). Hierarchy and cross-locale linking exist in the model
(`app/models/category.rb:33-51`) and in permitted params but have **no UI** — see §6.

Dead or near-dead:

- **`folders`** (`db/schema.rb:1271-1277`) + `Folder` model (`app/models/folder.rb:12`) + `articles.folder_id` (:206).
  No controller, no route (`config/routes.rb:439-460` nests only categories and articles), no policy, no frontend
  reference. **DO NOT CREATE** on top of it; it is a half-landed upstream idea.
- **`portals_members`** (`db/schema.rb:1559-1565`, UNIQUE `(portal_id, user_id)`). No model, no association, no
  `has_many :members` on Portal. Per-portal ownership does not exist; access is account-wide via policy.
- **`related_categories`** (`db/schema.rb:1567-1574`) + `RelatedCategory` (`app/models/related_category.rb:16`).
  API-reachable, UI-invisible.

---

## 3. The public read path

Eleven routes, all server-rendered ERB, no account id in any of them (`config/routes.rb:649-660`) **(R)**:

| Route | Line | Action |
|---|---|---|
| `GET hc/:slug` | :649 | `portals#show` — redirects to the default locale (`portals_controller.rb:30-35`) |
| `GET hc/:slug/sitemap.xml` | :650 | `portals#sitemap` |
| `GET hc/:slug/:locale` | :651 | `portals#show` (portal home) |
| `GET hc/:slug/:locale/search` | :652 | `portals/search#index` |
| `GET hc/:slug/:locale/articles` | :653 | `portals/articles#index` |
| `GET hc/:slug/:locale/categories` | :654 | `portals/categories#index` |
| `GET hc/:slug/:locale/categories/:category_slug` | :655 | `portals/categories#show` |
| `GET hc/:slug/:locale/categories/:category_slug/articles` | :656 | `portals/articles#index` |
| `GET hc/:slug/articles/:article_slug.png` | :657 | `portals/articles#tracking_pixel` |
| `GET hc/:slug/articles/:article_slug.md` | :658-659 | `portals/articles#show_markdown` |
| `GET hc/:slug/articles/:article_slug` | :660 | `portals/articles#show` |

### 3.1 Layouts — two selectable, three rendered

`PORTAL_LAYOUTS = %w[classic documentation]` (`app/controllers/public/api/v1/portals/base_controller.rb:10`).
`set_portal_layout` falls back to `'classic'` for anything unrecognised (`:22-24`). `set_view_variant` then picks a
Rails template variant: `:plain` when `?show_plain_layout=true`, `:documentation` for the documentation layout, nothing
(classic) otherwise (`:26-32`) **(R)**. The three templates are `app/views/layouts/portal.html.erb`,
`portal.html+documentation.erb` and `portal.html+plain.erb` **(R)**.

`plain` is not a product layout — it is the chrome-less variant used by the in-dashboard preview iframe, which is why
`allow_iframe_requests` deletes `X-Frame-Options` when it is active (`base_controller.rb:66-68`). The layout picker in
the dashboard exposes only classic vs documentation
(`app/javascript/dashboard/components-next/HelpCenter/Pages/PortalSettingsPage/PortalLayoutContentSettings.vue`).

Each layout has its own partial set: `app/views/public/api/v1/portals/documentation_layout/` (sidebar, topbar,
breadcrumb, hero, footer, section header, article card, category card, avatar group, empty state, plus
`articles/_meta_head` and `categories/_meta_head`) and the classic partials directly under
`app/views/public/api/v1/portals/` (header, hero, footer, home categories, featured articles, authors, thumbnail,
mobile menu, category block).

### 3.2 Markdown endpoint

`show_markdown` returns `head :not_found unless @article&.published?`, otherwise renders the raw body as
`text/markdown; charset=utf-8` (`app/controllers/public/api/v1/portals/articles_controller.rb:29-33`) **(R)**. This is
an existing, published-only, LLM/agent-friendly plain-text surface for every article. **REUSE** — it is the cheapest
way to make Lynomia docs consumable by Captain, by an external agent, or by a doc-ingest pipeline, with zero new code.

The HTML path renders markdown server-side through `ChatwootMarkdownRenderer#render_article`
(`articles_controller.rb:95-97`).

### 3.3 Tracking pixel

`GET hc/:slug/articles/:article_slug.png` → `tracking_pixel` (`articles_controller.rb:35-48`): resolves the article
within `@portal.articles`, increments `views` only when published, sets `expires_in 24.hours, public: false` (private
cache deliberately bypasses the CDN while still suppressing duplicate counts from one browser) and sends
`public/assets/images/tracking-pixel.png` **(R)**. This is the entire read-analytics mechanism: a single integer per
article. There is no per-day series, no referrer, no unique-reader count, no search-term log.

### 3.4 Sitemap

`portals#sitemap` sets `@help_center_url = @portal.custom_domain || ChatwootApp.help_center_root`, prefixing `https://`
when no protocol is present (`app/controllers/public/api/v1/portals_controller.rb:17-21`;
`lib/chatwoot_app.rb:36`). The view iterates **every** published article of the portal with
`lastmod = updated_at.to_date.iso8601` (`app/views/public/api/v1/portals/sitemap.xml.erb:1-9`) **(R)**. No categories,
no locale alternates, no pagination, and no batching — it loads the whole published set into memory per request. Fine at
documentation scale; a known cliff if a tenant portal ever grows large. **PATCH** (batching) if Lynomia docs are
expected past a few thousand articles, otherwise **REUSE**.

### 3.5 Locale handling and overrides

Locale is a URL segment, not a header. `switch_locale_with_portal` keeps `@locale` as the portal's own code (e.g.
`th_TH`) for content queries while falling the UI translations back to an available I18n locale
(`base_controller.rb:45-51`). Portal-level per-locale overrides live in `config.locale_translations`, keyed
`locale -> {name, page_title, header_text}` (permitted at
`app/controllers/api/v1/accounts/portals_controller.rb:102-111`), resolved by `Portal#localized_value` with a
locale → default-locale → base-column fallback chain (`app/models/portal.rb:135-140`).

Draft-ness of a *locale* is a portal setting (`draft_locales` → `draft_locale_codes` / `public_locale_codes` /
`draft_locale?`, `app/models/portal.rb:109-122`), with a validation that the default locale cannot be drafted. Per
*article* there is only the single `status` integer. Translations are separate Article rows linked by
`associated_article_id` (`app/models/article.rb:40-50`).

`PortalHelper` carries the supporting view logic: `set_og_image_url` against `OG_IMAGE_CDN_URL` /
`OG_IMAGE_CLIENT_REF`, colour mixing, `language_name` from `config/languages/language_map.yml`, `html_lang_attribute`
converting `th_TH` → `th-TH`, link builders that preserve `theme` and `show_plain_layout`, and
`generate_portal_brand_url` which appends UTM params (`app/helpers/portal_helper.rb`).

### 3.6 Search — three independent implementations

| Surface | Where | Mechanism |
|---|---|---|
| Public portal search | `app/controllers/public/api/v1/portals/search_controller.rb:9-16` | `@portal.articles.published` for the requested locale, `Article.search` (pg_search), 10 per page; empty query returns `.none` (`:21`) |
| Dashboard global search | `app/services/search_service.rb:177-182`, exposed `GET /api/v1/accounts/:id/search/articles` | `current_account.articles.text_search(q)`, 15 per page |
| EE vector search | `enterprise/app/controllers/enterprise/public/api/v1/portals/articles_controller.rb` → `Article.vector_search` (`enterprise/app/models/enterprise/concerns/article.rb:13-38`) | pgvector cosine over `article_embeddings` (`db/schema.rb:193-200`), **gated on a flag that ships `enabled: false, premium: true, chatwoot_internal: true`** (`config/features.yml:135-139`) |

The public article index caps `per_page` at 100 and defaults to 25 (`articles_controller.rb:52-58`), and sorts by views
only when `?sort=views`, otherwise by position (`:64-70`).

### 3.7 SEO head — what is emitted

`app/views/public/api/v1/portals/articles/_meta_head.html.erb:1-21` emits `<title>` as
`"<article.title> | <portal.display_title(locale)>"`, then, only when the corresponding `meta` jsonb key is present:
`name`/`og`/`twitter` title, `name`/`og`/`twitter` description, and `name="tags"` as a comma join. `og:image` /
`twitter:image` are emitted only when an OG image URL resolves (`:16-21`). The documentation-layout variant is the same
shape (`documentation_layout/articles/_meta_head.html.erb:1-17`) **(R)**.

### 3.8 Two public endpoints have no host guard (V)

`ensure_custom_domain_request` is applied selectively, not as a blanket property of the public path:

| Controller | Guard scope | Line |
|---|---|---|
| `Public::Api::V1::PortalsController` | `only: [:show]` | `app/controllers/public/api/v1/portals_controller.rb:4` |
| `Public::Api::V1::Portals::ArticlesController` | `only: [:show, :index, :show_markdown]` | `.../articles_controller.rb:2` |
| `Public::Api::V1::Portals::SearchController` | `only: [:index]` | `.../search_controller.rb:2` |

So **`portals#sitemap` and `articles#tracking_pixel` serve on any host that reaches the app** **(V)(R)**. Low severity
for a docs portal (both are already public data), but it means the sitemap is reachable on hosts you have not
registered, and a view count can be inflated from anywhere. Worth knowing before fronting docs with a CDN.

### 3.9 One cross-tenant lookup by construction

`switch_locale_with_article` does a bare, unscoped `Article.find_by(slug: params[:article_slug])`
(`base_controller.rb:53-64`) purely to derive the locale. It is safe only because `articles.slug` is globally unique
(`db/schema.rb:226`). It does not leak content — the article actually rendered is re-resolved within `@portal`
(`articles_controller.rb:72-74`) — but it is a cross-tenant read, and it is the reason the global slug index cannot be
relaxed to per-portal uniqueness without touching this method.

---

## 4. The authoring surface

### 4.1 Routes and controllers

`config/routes.rb:439-460`: `resources :portals` with member `patch :archive`, `delete :logo`,
`post :send_instructions`, `get :ssl_status`; nested `resources :categories` (+ collection `post :reorder`); a
`namespace :articles` holding `bulk_actions` (`post :translate`, `patch :update_status`, `patch :update_category`,
`delete :delete_articles`); and `resources :articles` (+ collection `post :reorder`) **(R)**.

`Api::V1::Accounts::ArticlesController` (`app/controllers/api/v1/accounts/articles_controller.rb`):

- Portal resolved account-scoped: `Current.account.portals.find_by!(slug: params[:portal_id])` (`:90-92`).
- `create` defaults `status` to `:draft` (`:28`).
- `article_params` permits `title, slug, position, content, description, category_id, author_id,
  associated_article_id, status, locale, draft_title, draft_content, meta[title, description, tags[]]` (`:108-115`).
- Author integrity: `validate_author` 422s an out-of-account author on create (`:68-74`); `discard_invalid_author`
  silently *drops* it on update (`:76-84`). Asymmetric, deliberate, worth knowing.
- `set_article_count` computes all / mine / published / draft / archived counts off the status-stripped filter
  (`:51-62`) — this is what powers the status tabs.

Bulk actions (`app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb`): `update_status` validates against
`Article.statuses.key?` and applies in a transaction (`:10-20`); `update_category` validates the category belongs to the
portal (`:22-32`, `:55-57`); `delete_articles` destroys (`:34-39`). `translate` is `head :not_implemented` in OSS
(`:6-8`) and is supplied by the EE module (§7). Authorization for all of them is `authorize(Article, :create?)`
(`:47-49`) — i.e. bulk delete requires only create rights.

### 4.2 The single-slot draft buffer

This is the only "unpublished changes" mechanism in the product, and it is exactly one slot deep.

`draft_title` / `draft_content` hold the pending edit; the live `title` / `content` stay untouched. The server writes
draft-only payloads with `update_columns` *specifically so the public `updated_at` is not bumped*, assigning and
validating first because `update_columns` skips validations
(`app/controllers/api/v1/accounts/articles_controller.rb:94-106`) **(R)**. That is a careful piece of work and the
reason the sitemap `lastmod` stays honest while someone drafts.

Frontend: `ArticleEditor.vue:47-52` reads `draftTitle ?? title` and `draftContent ?? content` and derives
"has pending changes" from either draft field being non-null; `articleDiffHelper.js:172` is the same predicate
(`hasPendingChanges`). `ArticleDiffPanel.vue:31-42` renders a word-level title diff and a block-level body diff, and
`rendersIdentically` compares the two bodies through the *same* CommonMark renderer the public page uses so that
whitespace-only edits do not register as changes (`articleDiffHelper.js:9-11`) **(R)**.

Because there is one slot, there is no history: publishing overwrites live and clears the buffer; the previous published
text is gone. See §6.

### 4.3 Editor and dashboard pages

Routes: `app/javascript/dashboard/routes/dashboard/helpcenter/helpcenter.routes.js` — nine pages (portals index/new,
articles index/new/edit, categories index, locales index, settings index), all behind
`meta = { featureFlag: FEATURE_FLAGS.HELP_CENTER, permissions: ['administrator', 'agent', 'knowledge_base_manage'] }`
(`:25-28`), with portals index/new narrowed to `['administrator', 'knowledge_base_manage']` (`:98`, `:107`) **(R)**.

Editor components, all in `components-next` (the non-deprecated tree):
`app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/` — `ArticleEditor.vue`,
`ArticleEditorHeader.vue`, `ArticleEditorControls.vue`, `ArticleEditorProperties.vue`, `ArticleDiffPanel.vue`,
`ArticlePendingChangesPopover.vue` **(R)**. Status changes run through `ARTICLE_STATUS_TYPES`
(PUBLISH / ARCHIVE / DRAFT) in the header (`ArticleEditorHeader.vue:61`, `:129-140`).

The properties panel is the SEO panel and nothing more: its reactive state is exactly
`{ title, description, tags }` mapped to `article.meta.*` (`ArticleEditorProperties.vue:25-33`) **(R)**.

Media: editor uploads go to `Api::V1::Accounts::UploadController#create`
(`app/controllers/api/v1/accounts/upload_controller.rb:1-20`), which creates a bare `ActiveStorage::Blob` and returns
its URL; the markdown body stores that URL. **Article has no `has_many_attached`** (`app/models/article.rb:36-74`), so
nothing links the blob to the article and deleting an article orphans its images. Only the Portal logo is a real
attachment (`app/models/portal.rb:37`). **PATCH** if Lynomia docs will carry many screenshots.

Portal settings are four tabs — general, domain, appearance, integrations
(`app/javascript/dashboard/components-next/HelpCenter/Pages/PortalSettingsPage/PortalSettings.vue:39-60`) **(R)**.
Portal `update` takes a row lock before merging `config` so concurrent saves do not drop each other's keys
(`app/controllers/api/v1/accounts/portals_controller.rb:26-36`) — good, reusable.

Other surfaces that already read articles: the chat widget
(`app/javascript/widget/api/article.js`, `app/javascript/widget/views/ArticleViewer.vue`) and the public portal bundle
(`app/javascript/entrypoints/portal.js`, `app/javascript/portal/` with `PublicArticleSearch.vue`,
`TableOfContents.vue`, `SidebarThemeToggle.vue`).

---

## 5. Permissions and tenancy

**Tenancy.** Every row is account-scoped in the database: `portals.account_id` (`db/schema.rb:1540`),
`articles.account_id` (`:203`), `categories.account_id` (`:609`), `folders.account_id` (`:1272`) — all `NOT NULL`.
`account_id` is never client-supplied; `ensure_account_id` copies it from the portal
(`app/models/article.rb:221-223`, `app/models/category.rb:88-90`). Every dashboard read goes through
`Current.account.portals.find_by!(slug:)` (`articles_controller.rb:90-92`,
`categories_controller.rb:46-48`, `articles/bulk_actions_controller.rb:43-45`,
`portals_controller.rb` `fetch_portal`). Global search is scoped the same way (`search_service.rb:178`). Captain tools
scope to `@assistant.account_id`.

**Roles.** OSS: read is any account user, every write is administrator-only.

```
ArticlePolicy#index?   = @account.users.include?(@user)        app/policies/article_policy.rb:2-4
ArticlePolicy#update? #show? #edit? #create? #destroy? #reorder?
                       = @account_user.administrator?          app/policies/article_policy.rb:6-28
```

Same shape in `app/policies/category_policy.rb` and `app/policies/portal_policy.rb`. EE widens writes to the custom-role
permission `knowledge_base_manage` for **all** Article and Category actions
(`enterprise/app/policies/enterprise/article_policy.rb:1-29`, `enterprise/app/policies/enterprise/category_policy.rb`)
but for Portal only `update?` / `edit?` / `logo?`
(`enterprise/app/policies/enterprise/portal_policy.rb:1-13`) — **creating or deleting a portal stays
administrator-only** **(R)**.

One in-controller rule worth preserving: portal analytics ids are permitted only for administrators, explicitly so that
`knowledge_base_manage` roles cannot inject tracking scripts into every public page
(`app/controllers/api/v1/accounts/portals_controller.rb:107-110`) **(R)**.

Note the client/server asymmetry: the frontend route permissions include `'agent'` for the article editor pages
(`helpcenter.routes.js:27`), so an agent can reach the editor UI, but `ArticlePolicy#update?` rejects the write. Visible
friction, not a security hole.

**Super Admin.** A separate Devise scope on the `SuperAdmin` model at path `/super_admin`
(`config/routes.rb:726-727`) **(R≠ — the corrections file says `devise_for :super_admins` is at :725; at this HEAD it
is :726, with `:727` `devise_scope` and `:729` `namespace :super_admin`)**. Every administrate controller inherits
`SuperAdmin::ApplicationController` with `before_action :authenticate_super_admin!`
(`app/controllers/super_admin/application_controller.rb:14`). There is **no finer-grained super-admin role, no
per-resource authorization and no Pundit in the namespace** — any super admin can do everything, including Sidekiq Web
at `/monitoring/sidekiq` (`config/routes.rb:764`).

---

## 6. What is ABSENT

| Missing capability | Evidence of absence | Classification |
|---|---|---|
| **Revision / version history** | No `versions` or `article_versions` table in `db/schema.rb`; no `paper_trail` in the Gemfile (`audited ~> 5.4` at `Gemfile:184` is the only such gem). The single-slot draft buffer is the only "unpublished" state. | **EXTEND, no migration** — see §6.1 |
| **Article is not audited** | `grep '^\s*audited'` across `app/models`, `enterprise/app/models`, `custom/app/models` returns Webhook, Inbox, InboxMember, User, Team, TeamMember, AccountUser, AutomationRule, AgentBot, Conversation, Account, Macro (all `enterprise/app/models/enterprise/audit/*`) and `Custom::Audit::CustomFilter`. Article, Portal and Category are absent **(R)**. | **EXTEND, no migration** |
| **No `published_at` / `scheduled_at` / `expires_at`** | `db/schema.rb:202-229` has none. `status` is flipped synchronously by the controller or a bulk action; no scheduled job transitions article status. "Published on" is therefore unknowable, and publish-at-a-date is impossible. | **NEW PRIMITIVE REQUIRED** (migration — §12) |
| **No canonical / hreflang / noindex** | `grep -iE 'canonical|hreflang|noindex|robots'` across `app/views/public` and `app/views/layouts` matches only `app/views/layouts/super_admin/application.html.erb:19` and `app/views/layouts/vueapp.html.erb:7` **(R)**. `RobotsController` (`app/controllers/robots_controller.rb:3-6`) disallows only `/widget` and says nothing about `/hc`. The sitemap has no `xhtml:link` alternates. | **PATCH** (view-only) |
| **No editable slug in the dashboard** | `slug` is permitted server-side (`articles_controller.rb:110`) but nothing binds it: `createArticle` sends only `content, title, author_id, category_id, locale` (`app/javascript/dashboard/api/helpCenter/articles.js:57-66`) and the properties panel exposes only `meta` (`ArticleEditorProperties.vue:25-33`) **(R)**. Public URLs carry an epoch prefix. | **PATCH** (UI-only; API already accepts it) |
| **No editable `description`** | `articles.description` exists (`db/schema.rb:208`), is weighted `B` in search (`article.rb:93`) and is permitted (`articles_controller.rb:110`), but its only writers are the EE translate job (`enterprise/app/jobs/captain/articles/translate_job.rb`) and the onboarding builder (`enterprise/app/services/onboarding/help_center_article_builder.rb`). | **PATCH** (UI-only) |
| **No review/approval workflow** | `enum status: { draft: 0, published: 1, archived: 2 }` (`article.rb:73`) is the complete state set; no reviewer column, no pending-review state, no notify-on-submit. | **NEW PRIMITIVE REQUIRED** |
| **No per-portal ownership** | `portals_members` exists but has no model or association (§2.4). | **DO NOT CREATE** unless multi-team docs ownership becomes a real requirement |
| **No folder organisation** | §2.4. | **DO NOT CREATE** |
| **Category hierarchy and cross-locale links have no UI** | Columns, associations and permitted params all exist; `grep related_category|parentCategory|associated_category` across `app/javascript` returns nothing, and `CategoryForm.vue` carries only `{id, name, icon, iconColor, slug, description, locale}`. | **PATCH** (UI-only) |
| **No asset lifecycle** | §4.3. | **PATCH** |
| **No Help Center reach from Super Admin** | §9. | **EXTEND** |
| **No in-product changelog** | §10. | **NEW PRIMITIVE REQUIRED** (migration) |
| **No Portal slug reservation** | §1. | **NEW PRIMITIVE REQUIRED** (model/const only, no migration) |

### 6.1 Revision history needs no migration (V)

The corrections file is right and this changes the build decision. The generic polymorphic `audits` table already exists
with `auditable_type` / `auditable_id` / `version` / `audited_changes` / `user_id` / `action` / `created_at`
(`db/schema.rb:264-288`) **(R)**, and the `audited` gem is already a dependency (`Gemfile:184`). Adding revision
history to Article is a **model change only** — an `audited` declaration — not a schema change.

Follow the repo's own convention and gate it the way `custom/` already does:
`audited associated_with: :account, if: :contact? if defined?(Enterprise::AuditLog)`
(`custom/app/models/custom/audit/custom_filter.rb:8`) **(R)**. Note the gem stores whole-column diffs, so auditing an
Article's `content` will write a full before/after body into `audits.audited_changes` on every save — worth a column
allowlist (`audited only: [...]`) rather than auditing everything. **EXTEND.**

---

## 7. The Enterprise overlay — full enumeration

`custom/` contributes nothing here (§8), so `enterprise/` is the entire overlay. Twenty-one files, grouped.

### 7.1 Model and policy concerns

| File | Role | State |
|---|---|---|
| `enterprise/app/models/enterprise/concerns/article.rb` | `after_save :add_article_embedding` on title/description/content change (`:5`); `has_many :article_embeddings` (`:7-11`); `self.vector_search` via `ArticleEmbedding.nearest_neighbors` cosine (`:13-38`) | Gated on `help_center_embedding_search` (`:42`), which ships disabled |
| `enterprise/app/models/enterprise/concerns/portal.rb` | `after_save :enqueue_cloudflare_verification` on `custom_domain` change | Returns early unless `ChatwootApp.chatwoot_cloud?` (`:10`) — **inert on Lynomia** |
| `enterprise/app/models/article_embedding.rb` | `has_neighbors :embedding, normalize: true` (`:18`); after_commit enqueues `Captain::Llm::UpdateEmbeddingJob` (`:20`) | Behind the disabled flag |
| `enterprise/app/policies/enterprise/article_policy.rb` | `knowledge_base_manage` on all 7 actions | Live |
| `enterprise/app/policies/enterprise/category_policy.rb` | same | Live |
| `enterprise/app/policies/enterprise/portal_policy.rb` | `knowledge_base_manage` on `update?`/`edit?`/`logo?` only (`:1-13`) | Live |

The EE Article concern also contains a hand-rolled HTTParty `gpt-4o` call reading `InstallationConfig`
`CAPTAIN_OPEN_AI_API_KEY` / `CAPTAIN_OPEN_AI_ENDPOINT` (`enterprise/app/models/enterprise/concerns/article.rb:65-88`)
— protocol code in a model, bypassing the repo's own LLM client layer. Flagging it only because the house rule prefers
existing client libraries; it is unreachable while the flag is off.

### 7.2 Controllers

- `enterprise/app/controllers/enterprise/api/v1/accounts/articles/bulk_actions_controller.rb` — supplies `translate`,
  which OSS stubs as `head :not_implemented`. Requires `captain_tasks` (`:40-45`), validates the locale is in
  `portal.config['allowed_locales']` (`:47-52`), detects existing translations by root id and returns `409` with a
  `duplicate_articles` list unless `force` (`:5-10`, `:35-38`), then fans out `Captain::Articles::TranslateJob` (`:12-16`).
- `enterprise/app/controllers/enterprise/public/api/v1/portals/articles_controller.rb` — swaps pg_search for
  `Article.vector_search`. Behind the disabled flag.
- `enterprise/app/controllers/enterprise/api/v1/accounts/portals_controller.rb` — `ssl_status`. Cloud-oriented.

### 7.3 Captain / LLM

- `enterprise/app/jobs/captain/articles/translate_job.rb` — translates title and content, then either updates the
  existing translation found by `(associated_article_id = root, locale)` (`:17-20`) or creates a new Article with
  `status: :draft` and `associated_article_id = root` (`:42-53`).
- `enterprise/app/services/captain/llm/article_translation_service.rb` — `TYPES = [:title, :content]`; uses feature
  `help_center_article_generation`; the content prompt explicitly preserves markdown, HTML, URLs and images (`:48-60`).
- `enterprise/app/services/captain/llm/article_writer_service.rb` + `article_writer_schema.rb` — rewrites a scraped page
  into `{title, description, content}`.
- `enterprise/app/services/captain/tools/copilot/search_articles_service.rb` — ILIKE title/content search scoped to
  `@assistant.account_id`, capped at 100; requires `knowledge_base_manage` (`:22-24`).
- `enterprise/app/services/captain/tools/copilot/get_article_service.rb` — `Article.find_by(id:, account_id:)` →
  `to_llm_text`; same gate.
- `app/services/llm_formatter/article_llm_formatter.rb` (OSS) — the `to_llm_text` those two tools consume.
- `enterprise/app/jobs/portal/article_indexing_job.rb` — embedding terms; behind the disabled flag.

### 7.4 The six files the first pass omitted (V)

All six are real, all are on a wired path, and four of them are the actual Portal creator — the inventory filed this as
an untraced risky claim.

| File | Lines | Role |
|---|---|---|
| `enterprise/app/services/onboarding/help_center_creation_service.rb` | 130 | **The Portal creator.** `perform` reuses `@account.portals.first` if present, else `@account.portals.create!(portal_attributes)` then attaches the brand logo and enqueues generation (`:10-18`, `:31`, `:75`, `:85`). `generate_slug` (`:114`) picks the first free candidate from `slug_candidates` (`:117-124`), falling back to `<name>-<hex8>` (`:126-129`). |
| `enterprise/app/services/onboarding/help_center_curator.rb` | 71 | Firecrawl `map` discovery. `MAP_LIMIT = 500`, `MIN_ARTICLES = 3`, and a broadened `MAP_SEARCH` term list whose comment records that the original 4-term list caused ~60% of onboarding skips (`:1-10`). Raises `CurationSkipped` when Firecrawl is unconfigured, the website URL is blank, or map returns nothing (`:19-24`). |
| `enterprise/app/services/onboarding/help_center_errors.rb` | 4 | `CurationSkipped` and `ArticleBuildFailed`. |
| `enterprise/app/services/onboarding/help_center_generation_state.rb` | 45 | Redis hash progress tracker (`status`/`total`/`finished`), `TTL = 7.days`, `record_article_finished` using `hincrby` and flipping to `completed`; raises `Missing` when state is gone (`:8-26`). **Not a DB table** — generation progress is ephemeral. |
| `enterprise/app/services/captain/llm/help_center_curation_service.rb` | 157 | The LLM curator. `MAX_LINKS_IN_PROMPT = 50`, an image-extension ignore pattern, and a pinned `CURATION_MODEL = 'gpt-4.1'` with a comment that it beats 5.2 for this task (`:1-7`). Drops categories no article referenced (`:21-28`). |
| `enterprise/app/services/captain/llm/help_center_curation_schema.rb` | 30 | `RubyLLM::Schema`: 1-10 categories, 1-25 articles, 1-3 source URLs each, with explicit instructions to skip blog/marketing/pricing/legal/careers pages (`:4-14`). |

Entry point: `Enterprise::Api::V1::Accounts::OnboardingsController#create_onboarding_inboxes` → `#create_help_center`
→ `Onboarding::HelpCenterCreationService.new(@account, Current.user).perform`, guarded by `website.blank?`
(`enterprise/app/controllers/enterprise/api/v1/accounts/onboardings_controller.rb:9-24`) **(V)(R)**. Downstream:
`Onboarding::HelpCenterArticleGenerationJob` → `Onboarding::HelpCenterArticleWriterJob` (one article per job, with a
catch-all `discard_on StandardError` so generation state cannot wedge) → `Onboarding::HelpCenterArticleBuilder`, which
calls `portal.articles.create!(status: :draft, meta: { source_urls: [...] })` — the only writer of a `meta` key other
than title/description/tags.

**This pipeline is why the slug risk is live, not theoretical.** Every onboarding account with a website URL runs
`generate_slug` against the global `Portal.exists?(slug:)`.

---

## 8. `custom/` has zero Help Center files

`find custom -type f | wc -l` = **242** **(V)(R)** — the corrections file is right that the earlier count of 211 was
wrong; the substantive claim stands. Filtering that listing case-insensitively for
`portal|article|categor|help_center|helpcenter` returns **0** files **(R)**. The `custom/` tree is billing, mobile auth,
commerce, flows, audience and automation only.

Consequence: the overlay hooks resolve to the enterprise module alone.

```
Article.include_mod_with('Concerns::Article')   app/models/article.rb:229  -> Enterprise::Concerns::Article only
Portal.include_mod_with('Concerns::Portal')     app/models/portal.rb:207   -> Enterprise::Concerns::Portal only
```

Same for `ArticlePolicy.prepend_mod_with` (`app/policies/article_policy.rb:31`) and the public articles/search
controllers (`.../articles_controller.rb:100`, `.../search_controller.rb:31`). Mechanism:
`config/initializers/01_inject_enterprise_edition_module.rb`, `config/application.rb:42-57`, `lib/chatwoot_app.rb:40-48`.

**This is the single best piece of news in this study.** Lynomia Help Center work has a clean, empty overlay slot. Per
the house rule, Lynomia-specific Help Center behaviour belongs in `custom/` via these existing hooks, not in edits to
`app/`. No hard fork, no drift, nothing to mirror.

---

## 9. Super Admin

### 9.1 Stack

thoughtbot **administrate**. `Gemfile:97-99` declares `administrate >= 0.20.1`,
`administrate-field-active_storage >= 1.0.3`, `administrate-field-belongs_to_search >= 0.10.0`; `Gemfile.lock:85,93,96`
resolves exactly **0.20.1 / 1.0.3 / 0.10.0** **(R)**. (The Gemfile constraint is `>=`, not a pin — worth knowing before
treating 0.20.1 as fixed.)

### 9.2 Dashboards — 8 + 2

`app/dashboards/` (8) **(R)**: `access_token_dashboard.rb`, `account_dashboard.rb`, `account_user_dashboard.rb`,
`agent_bot_dashboard.rb`, `installation_config_dashboard.rb`, `platform_app_dashboard.rb`,
`platform_banner_dashboard.rb`, `user_dashboard.rb`.

`custom/app/dashboards/` (2) **(R)**: `billing_plan_dashboard.rb`, `billing_subscription_dashboard.rb`.

`enterprise/app/` has **no** `dashboards` directory at all **(R)** — EE extends Super Admin through controllers
(`enterprise/app/controllers/enterprise/super_admin/accounts_controller.rb`, `app_configs_controller.rb`) and fields,
not dashboards.

### 9.3 Custom field types — 7 + 4 + 2

| Tree | Count | Files |
|---|---|---|
| `app/fields/` | 7 | `account_status_field.rb`, `avatar_field.rb`, `confirmed_at_field.rb`, `count_field.rb`, `secret_field.rb`, `serialized_field.rb`, `suspension_history_field.rb` |
| `enterprise/app/fields/` | 4 | `account_features_field.rb`, `account_limits_field.rb`, `captain_model_overrides_field.rb`, `manually_managed_features_field.rb` |
| `custom/app/fields/` | 2 | `billing_plan_features_field.rb`, `billing_plan_limits_field.rb` |

All 13 verified by directory listing **(R)**. Field classes are resolved by bare constant from any of the three trees,
which is how `BillingPlanDashboard` references `BillingPlanLimitsField` and `CountField` side by side
(`custom/app/dashboards/billing_plan_dashboard.rb:15-18`).

### 9.4 How a resource is added

Three pieces, one optional, and a fourth that is easy to forget:

1. **Routes** — declare it inside `namespace :super_admin`, either in `config/routes.rb:729-762` or in a drawn file.
   `config/routes/billing.rb:4-19` is the working `custom/` precedent, drawn by `draw :billing` at
   `config/routes.rb:782` **(V)(R)** (alongside `draw :commerce` :783).
2. **An `Administrate::BaseDashboard` subclass** in `app/dashboards/` or `custom/app/dashboards/`, defining
   `ATTRIBUTE_TYPES`, `COLLECTION_ATTRIBUTES`, `SHOW_PAGE_ATTRIBUTES`, `FORM_ATTRIBUTES` and usually
   `display_resource`. `custom/app/dashboards/billing_plan_dashboard.rb:5` is the template; `app/dashboards/account_dashboard.rb:11-26`
   shows the deployment-shape pattern (build an attribute hash conditionally on `ChatwootApp.enterprise?` /
   `chatwoot_cloud?`, then merge).
3. **Optionally a controller** subclassing `SuperAdmin::ApplicationController`
   (`custom/app/controllers/super_admin/billing_plans_controller.rb:6`), only needed for custom actions or scoping.
   Authentication comes free from `before_action :authenticate_super_admin!`
   (`app/controllers/super_admin/application_controller.rb:14`).
4. **An entry in the hardcoded `sidebar_icons` hash** (`app/views/super_admin/application/_navigation.html.erb:14-21`)
   — or the nav item renders with a blank icon. `billing_subscriptions` is in the routes but *not* in the icon map, so
   it already renders iconless **(R)**: a live demonstration of the trap.

There is **no generator** for this in the repo; administrate's own `administrate:dashboard` generator from the gem is
all there is, and the working pattern is only discoverable by reading the billing precedent. **PATCH** (documentation)
if more resources are coming.

### 9.5 Sidebar auto-derivation and the skip list

`app/views/super_admin/application/_navigation.html.erb`:

- `:36` iterates `Administrate::Namespace.new(namespace).resources` — the nav is derived from the routes, not declared.
- `:37` skips a **hardcoded list**: `account_users`, `access_tokens`, `installation_configs`, `dashboard`,
  `devise/sessions`, `app_configs`, `instance_statuses`, `settings`, `push_diagnostics` **(R)**.
- `:38` additionally skips `platform_banners` unless `ChatwootApp.chatwoot_cloud?` — **so the only accountless
  broadcast primitive is invisible in the sidebar on a self-hosted Lynomia install** (the route still works).
- `:40` looks the icon up in `sidebar_icons`.
- `:47` is a manually added "Billing Settings" link outside the loop.
- `:53-57` are the fixed footer links: Sidekiq, Instance Health, Push Diagnostics, Agent Dashboard, Logout.

Net effect: adding a route makes a sidebar entry appear automatically. That is convenient and it is also why the skip
list exists — it is the only way to hide something.

### 9.6 What Super Admin can manage today

From `config/routes.rb:729-762` plus `config/routes/billing.rb:4-19` **(R)**:

| Resource | Where | In auto-sidebar? |
|---|---|---|
| Accounts (+ `seed`, `reset_cache`, suspension workflow) | `config/routes.rb:737-740` | yes |
| Users (+ avatar delete, resend confirmation) | `:742-745` | yes |
| Access tokens (index/show) | `:747` | no (skipped) |
| Installation configs | `:748` | no (skipped) |
| Agent bots (+ avatar delete) | `:749-751` | yes |
| Platform apps | `:752` | yes |
| **Platform banners** | `:753` | cloud only (`_navigation:38`) |
| Instance status | `:754` | no (skipped; footer link instead) |
| Settings | `:756-758` | no (skipped) |
| Account users (new/create/show/destroy) | `:761` | no (skipped) |
| App config | `:732` | no (skipped) |
| Push diagnostics | `:733-735` | no (skipped; footer link) |
| **Billing plans** (+ settings) | `config/routes/billing.rb:5-10` | yes |
| **Billing subscriptions** (+ extend trial, grant plan, cancel) | `config/routes/billing.rb:12-18` | yes, iconless |

**Portals, Categories and Articles are not among them.** No `PortalDashboard`, `CategoryDashboard` or
`ArticleDashboard` exists; the `namespace :super_admin` block declares no such resource; a case-insensitive grep for
`portal|article|categor` across the whole Super Admin tree (`app/controllers/super_admin`, `app/dashboards`,
`app/views/super_admin`, `custom/app/controllers/super_admin`, `custom/app/dashboards`, the EE super_admin controllers)
matches only `suspension_category` and one prose string, "access billing portal", at
`app/views/super_admin/settings/show.html.erb:12` **(V)(R)**.

Also note what a super admin *is*: one undifferentiated role with no per-resource authorization, cross-tenant by nature,
with Sidekiq Web attached. Putting Help Center authoring there is a reasonable fit for an internal docs team of
trusted staff; it is not a fit if docs authoring should be delegable to someone who must not also be able to delete
accounts.

Three EE files under `enterprise/app/controllers/super_admin/` — `enterprise_base_controller.rb`,
`responses_controller.rb`, `response_documents_controller.rb` — have no routes and are **defined but unused**. Do not
model new work on them.

---

## 10. The existing changelog situation

There is no in-product changelog. Two separate things exist, neither of which is one.

**1. The sidebar changelog is a read-only consumer of a hardcoded external feed.**
`app/javascript/dashboard/api/changelog.js:12` does `axios.get(CHANGELOG_API_URL)` where
`CHANGELOG_API_URL = 'https://hub.2.chatwoot.com/changelogs'`
(`app/javascript/shared/constants/links.js:11`) **(R)**. It is rendered by `SidebarChangelogCard.vue` /
`SidebarChangelogButton.vue` with `GroupedStackedChangelogCard.vue` / `StackedChangelogCard.vue`, and "Read more" opens
`https://www.chatwoot.com/blog/<slug>`. There is **no** changelog table in `db/schema.rb`, no Rails route or controller
serving it, no model and no authoring UI **(R)**.

Critically, it is gated on `isOnChatwootCloud && !isACustomBrandedInstance`
(`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:1084-1096`) **(R)**, so **it does not render on a branded
Lynomia install at all**. The slot in the UI is empty, not wrong — which means it is available.

**2. The only accountless in-product broadcast primitive is `PlatformBanner`.**
`db/schema.rb:1531-1537`: `banner_message` text NOT NULL, `banner_type` integer default 0 NOT NULL, `active` boolean
default true NOT NULL, timestamps — **and no `account_id`** **(R)**. The model is three lines of behaviour:
`enum :banner_type, { info: 0, warning: 1, error: 2 }`, `validates :banner_message, presence: true`,
`scope :active` (`app/models/platform_banner.rb:12-18`). Super Admin can author exactly
`banner_message`, `banner_type`, `active` (`app/dashboards/platform_banner_dashboard.rb:15`). It reaches the SPA through
`app/controllers/dashboard_controller.rb` → `window.globalConfig` → `StatusBanner.vue`, with dismissal held in
localStorage (`app/javascript/dashboard/constants/localStorage.js:3`).

So the primitive is: one plain-text line, one of three severities, instance-wide. **No title, no link, no rich body, no
scheduling, no per-account or per-plan targeting, no read/unread state, no history** — and, per §9.5, its sidebar entry
is hidden off cloud.

| Need | Verdict |
|---|---|
| Publish Lynomia release notes as *documentation* | **REUSE** — a "Release notes" Category in the docs portal, with articles. Available today, zero code. The `.md` endpoint (§3.2) even gives it a machine-readable feed. |
| A dismissible one-line "we shipped X" strip | **REUSE `PlatformBanner`** as-is, plus a **PATCH** to `_navigation.html.erb:38` so the Super Admin link is reachable off cloud. |
| A real changelog feed with titles, links, dates, per-release grouping and read state | **NEW PRIMITIVE REQUIRED** — needs storage. §12. |
| Re-pointing the existing sidebar card at a Lynomia feed | **DO NOT CREATE.** It is dead code on a branded install and the card's "Read more" hardcodes `chatwoot.com/blog`. Rebuilding it against a new primitive is cheaper than retrofitting it, and leaving it is harmless. |

---

## 11. Classification summary

| Capability | Verdict | Why |
|---|---|---|
| Portal → Category → Article as the docs container | **REUSE** | Complete, tested, already serves globally by slug (§1) |
| Public `/hc/:slug` server-rendered reader, both layouts | **REUSE** | `documentation` layout is purpose-built for docs (§3.1) |
| `.md` per-article endpoint | **REUSE** | Published-only machine-readable surface, free (§3.2) |
| Public search (pg_search) | **REUSE** | Adequate at docs scale (§3.6) |
| 10-step position rebalancing | **REUSE** | Server-authoritative, already correct (§2.2) |
| Draft buffer + live/draft diff | **REUSE** | Genuinely good: diffs through the public renderer (§4.2) |
| Markdown editor + SEO properties panel | **REUSE** | `components-next`, the non-deprecated tree (§4.3) |
| Tracking-pixel view counts | **REUSE** | Enough to rank popular docs; nothing more (§3.3) |
| Sitemap | **REUSE** (**PATCH** if article count grows) | Unbatched full scan (§3.4) |
| EE translation pipeline (`captain_tasks`) | **REUSE** | Wired end-to-end, 409-on-duplicate is well built (§7.3) |
| Lynomia-specific Help Center behaviour | **EXTEND** via `include_mod_with` / `prepend_mod_with` | Overlay slot is empty (§8) |
| Article revision history | **EXTEND** — `audited` on Article, **no migration** | `audits` table already exists (§6.1) |
| Portal/Category/Article in Super Admin | **EXTEND** — routes + dashboards + icons, **no migration** | Additive; billing is the proof (§9.4) |
| Editable slug in the dashboard | **PATCH** (UI only) | API already permits it (§6) |
| Editable `description` in the dashboard | **PATCH** (UI only) | Column, search weight and param all exist (§6) |
| Canonical / hreflang / `noindex` | **PATCH** (views only) | Two `_meta_head` partials + sitemap alternates (§6) |
| Category hierarchy + cross-locale links in UI | **PATCH** (UI only) | Model and params already there (§2.4) |
| `#archive` writing a non-existent attribute | **PATCH** — live defect | §13 |
| `custom_domain` unsettable on update | **PATCH** — live defect | §13 |
| Sitemap / tracking-pixel host guard | **PATCH** | §3.8 |
| `platform_banners` sidebar link off cloud | **PATCH** | §9.5 |
| Article asset lifecycle | **PATCH** | §4.3 |
| Portal slug reservation | **NEW PRIMITIVE REQUIRED** (model/const only, **no migration**) | The one guard the whole recommendation rests on (§1) |
| `published_at` / scheduled publishing | **NEW PRIMITIVE REQUIRED** (migration) | §12 |
| Review/approval workflow | **NEW PRIMITIVE REQUIRED** | §6 |
| Accountless/global Portal | **DO NOT CREATE** | Would need to drop `NOT NULL` on three columns, relax three validations, rework two `ensure_account_id` callbacks and six `Current.account.portals` lookups — and buys nothing the global slug lookup does not already give (§1, §2.3) **(V)** |
| `folders` | **DO NOT CREATE** | Dead upstream table (§2.4) |
| `portals_members` | **DO NOT CREATE** | No model, no need yet (§2.4) |
| Re-pointing the Chatwoot changelog card | **DO NOT CREATE** | Dead on branded installs (§10) |
| `help_center_embedding_search` / vector search | **DO NOT CREATE** | Ships `enabled: false, premium, chatwoot_internal`; pg_search is sufficient at docs scale (§3.6) |

---

## 12. Migration requirements — stated, not proposed

Left for approval. Nothing in §11's REUSE / EXTEND / PATCH rows needs any of these.

1. **An in-product changelog / release-notes feed.** There is no `changelog` or `release_note` table in
   `db/schema.rb` **(R)**, and the only accountless content record is `platform_banners` (§10). A real feed needs new
   storage: accountless rows with title, body, published date, optional link, and release grouping; plus per-user
   read-state if "unread" is wanted. **Only if §10's REUSE options are rejected.**
2. **`articles.published_at`** (and `scheduled_at` / `expires_at` if scheduling is wanted). Without `published_at` the
   docs portal cannot show or sort by publication date, and "published" has no timestamp distinct from `updated_at`.
3. **A per-portal slug reservation table**, *only* if reservations must be editable at runtime. If a static
   `Portal::RESERVED_SLUGS` constant mirroring `Article::RESERVED_SLUGS` (`app/models/article.rb:61`) is acceptable,
   **no migration is needed** — and that is the recommendation.

---

## 13. Live defects found in this area

1. **`PortalsController#archive` writes a non-existent attribute.**
   `app/controllers/api/v1/accounts/portals_controller.rb:44` is `@portal.update(archive: true)`; the column is
   `archived` (`db/schema.rb:1551`) **(R)**. Archiving via `PATCH portals/:id/archive` cannot work. `archived` *is*
   permitted in `portal_params` (`:98`), so the normal update path still archives — which is probably why this has gone
   unnoticed. Note `archived: false` is the public lookup predicate (`public/api/v1/portals_controller.rb:26`), so
   archiving is the only way to take a portal offline. Must be fixed before Super Admin exposes an archive action.
   **UNVERIFIED:** whether Rails raises `UnknownAttributeError` or silently no-ops here; I did not execute it, and I
   found no spec covering `PATCH portals/:id/archive`.
2. **`custom_domain` cannot be changed after create.** The assignment in `#update` is commented out with no explanation
   (`app/controllers/api/v1/accounts/portals_controller.rb:31`) while `create` sets it (`:20`) **(R)**. If Lynomia docs
   are to live on a custom domain, the domain must be right at portal-creation time or be fixed in a console.
3. **Two unguarded public endpoints** — §3.8.
4. **`platform_banners` is invisible in the Super Admin sidebar off cloud** — §9.5. The route works; only the link is
   hidden.

---

## 14. Limits of this study

- I did not boot the app or run any spec. Every "wired end to end" claim is from reading route → controller → model →
  view, not from observed behaviour.
- `Limits::CATEGORIES_PER_PAGE` (referenced at `app/models/category.rb:28`) — value **UNVERIFIED**.
- I traced the onboarding generation chain and its entry point (§7.4) but did not execute it; Firecrawl is required and
  its configuration state here is **UNVERIFIED**.
- `config/llm.yml` declares `help_center_article_generation`, `help_center_query_translation` and `help_center_search`;
  only the first is referenced by code I traced
  (`enterprise/app/services/captain/llm/article_translation_service.rb`). The other two are **UNVERIFIED** as live.
- Whether `FRONTEND_URL` / `HELPCENTER_URL` are set to the serving host in the Lynomia deployment is **UNVERIFIED** and
  is a prerequisite for §1 item 2. It is an env check, not a code change.
- There was no prior Help Center discovery doc to reconcile against: `ls docs/` returns audience, automation,
  campaigns, chatwoot-upgrade, commerce, contacts, flow-builder, product-enablement, rails_upgrade_assessment.md,
  rails_upgrades, ui-modernization, usability, whatsapp-business, whatsapp-qr **(R)**. Help Center appears only
  incidentally in the `ui-modernization` audits, whose `helpcenter.routes.js` line references have drifted by a few
  lines — substance correct, anchors stale.
