# 00 — The Help Center that already exists

What is in the repository before P4 touches anything, and which parts of it platform documentation can stand on.
Implementation preflight: this is an inventory, not a product study. The broad study was done in
`docs/product-enablement/08-documentation-existing-system-study.md`; everything below was re-verified against
HEAD `53dd50b8` because that study is older than the code.

**EXISTING SYSTEM TO EXTEND: the Help Center — `Portal → Category → Article`, its account-scoped authoring API, its
server-rendered public portal, its pg_search, its locale model, and the Administrate Super Admin console.** No second
content model, editor, renderer or search engine is introduced by this phase.

---

## 1. Models

| | File | What it is |
|---|---|---|
| `Portal` | `app/models/portal.rb` | the site. `slug` UNIQUE **globally**, `custom_domain` UNIQUE, `config` jsonb (locales, layout, analytics, per-locale overrides), `archived` |
| `Category` | `app/models/category.rb` | a section, **per locale**. `(slug, locale, portal_id)` UNIQUE; `position`; `parent_category_id`; `associated_category_id` links translations |
| `Article` | `app/models/article.rb` | the page. `slug` UNIQUE **globally**; `status` enum `draft:0 / published:1 / archived:2`; `locale` NOT NULL; `position`; `meta` jsonb; `draft_title` / `draft_content`; `views`; `author` → `User` |
| `RelatedCategory` | `app/models/related_category.rb` | the join behind `related_categories` |

Two facts shape everything P4 does:

```ruby
# both derive the account from the portal, not from the request
def ensure_account_id
  self.account_id = portal&.account_id       # article.rb, category.rb
end
```

so **the portal is the only ownership anchor**, and

```ruby
enum status: { draft: 0, published: 1, archived: 2 }   # article.rb
```

so **a two-state publish lifecycle already exists** and did not need building.

`Article` also carries a *second* draft buffer — `draft_title` / `draft_content` — written with `update_columns` so a
live article can be revised without bumping the public `updated_at`. P4 does not use it (Super Admin edits the live
row and previews before publishing), but it is there for a later "edit a published page safely" flow.

## 2. The authoring API (tenant)

`config/routes.rb:439-460`: `resources :portals` with `categories` and `articles` nested beneath. Every controller
resolves the portal the same way:

```ruby
@portal ||= Current.account.portals.find_by!(slug: params[:portal_id])
```

`portals_controller.rb:10,19,75` · `articles_controller.rb:91` · `categories_controller.rb:47` ·
`articles/bulk_actions_controller.rb:44`

That single pattern is why platform content needs no extra tenant guard: a row with no account cannot satisfy
`WHERE account_id = $1` (`01-global-ownership-design.md §1`).

Article `meta` is **not** free-form on the write path — the tenant API permits three keys:

```ruby
meta: [:title, :description, { tags: [] }]      # articles_controller.rb
```

Super Admin does not go through that controller, so P4 permits the fuller set in its own dashboard instead of
widening the tenant API.

## 3. The public read path

Eleven routes, all server-rendered ERB, **no account id in any of them** (`config/routes.rb:649-660`):

```
GET hc/:slug                                        portals#show        → redirects to the default locale
GET hc/:slug/sitemap.xml                            portals#sitemap
GET hc/:slug/:locale                                portals#show
GET hc/:slug/:locale/search                         portals/search#index
GET hc/:slug/:locale/articles                       portals/articles#index
GET hc/:slug/:locale/categories[/:category_slug]    portals/categories#index|show
GET hc/:slug/articles/:article_slug(.png|.md)       portals/articles#tracking_pixel|show_markdown
GET hc/:slug/articles/:article_slug                 portals/articles#show
```

Resolution is a bare global lookup — `Portal.find_by!(slug:, archived: false)` — which is exactly why a platform
portal serves with no changes to this layer.

**Layouts.** `PORTAL_LAYOUTS = %w[classic documentation]`, plus a `plain` template variant used by the preview
iframe. Lynomia's two portals use `documentation`.

**Markdown is the content format.** `ChatwootMarkdownRenderer#render_article` runs `CommonMarker.render_doc(content,
:DEFAULT, [:table])` through `CustomMarkdownRenderer`. So `articles.content` is CommonMark, the same source the
dashboard's ProseMirror editor serialises — which is why a Markdown textarea in Super Admin is the *same* content
model and not a lesser one.

**Host guard.** `ensure_custom_domain_request` passes when `request.host` matches this install's own `FRONTEND_URL` or
`HELPCENTER_URL` (`app/controllers/concerns/domain_helper.rb`). If neither is set, every portal page returns 401. That
is a **deployment prerequisite**, recorded in `10-global-docs-implementation.md`, not a code gap.

### Two defects this phase found here

| Defect | Where | Fixed in P4 |
|---|---|---|
| **An unpublished draft was served to anyone with its URL** — `set_article` resolved the slug unscoped, while the markdown endpoint and the view counter both guarded correctly | `public/api/v1/portals/articles_controller.rb` | published-only, with a signed-in super admin excepted for preview and a banner saying so |
| An unknown article slug raised `NoMethodError` → **500** | same | `find_by!` → 404 |

## 4. Search — three independent implementations

| Surface | Mechanism | Scope |
|---|---|---|
| Public portal search | `Article.search` → `pg_search_scope :text_search` over `title` (A) / `description` (B) / `content` (C), 10 per page | `@portal.articles.published` for the requested locale |
| Dashboard global search | `current_account.articles.text_search(q)`, 15 per page | the account's own |
| EE vector search | `Article.vector_search` over `article_embeddings` | gated on `help_center_embedding_search`, which ships `enabled: false, premium: true` |

Public search is **portal-scoped**, which is what keeps global documentation and tenant help content apart with no
new filter (`14-security-and-tenancy.md`).

## 5. Locales

- `portals.config['allowed_locales']`, `default_locale`, and `draft_locales` (a locale can be held back as a whole).
- `categories.locale` and `articles.locale`; a translation is a **separate row** linked by `associated_*_id`.
- Locale is a **URL segment**, not a header: `/hc/:slug/:locale/...`.
- `Portal#localized_value` resolves per-locale overrides for `name`, `page_title` and `header_text` with a
  locale → default-locale → column fallback.
- `PortalHelper#html_lang_attribute` converts `th_TH` → `th-TH`; RTL comes from the layout's `dir`.

## 6. Super Admin

thoughtbot **administrate 0.20.1**. A resource needs four things, and the fourth is easy to miss:

1. routes inside `namespace :super_admin` (drawn files work — `config/routes/billing.rb` is the `custom/` precedent);
2. an `Administrate::BaseDashboard` subclass in `app/dashboards/` or `custom/app/dashboards/`;
3. optionally a controller subclassing `SuperAdmin::ApplicationController` (authentication comes free from
   `before_action :authenticate_super_admin!`);
4. an entry in the hardcoded `sidebar_icons` hash in `app/views/super_admin/application/_navigation.html.erb`, or the
   nav item renders iconless.

The sidebar is **derived from the routes**, with a hardcoded skip list as the only way to hide something.

Before P4 there was **no `PortalDashboard`, `CategoryDashboard` or `ArticleDashboard`** and no help-center route in the
`super_admin` namespace. Super Admin had zero reach into content.

`SuperAdmin` is an **STI subclass of `User`** (`users.type`), which is why it can satisfy `articles.author_id`.

## 7. What was absent, and what P4 did about each

| Absent | P4 |
|---|---|
| Any notion of platform-owned (accountless) content | **one additive migration** — `01-global-ownership-design.md` |
| Super Admin reach into Portal / Category / Article | three dashboards + three scoped controllers — `07-super-admin-management.md` |
| A reserved-slug list for portals (tenant onboarding squats `docs`, `help`) | `Portal::RESERVED_SLUGS`, code only |
| Date-ordered article listing (everything is `position`) | one portal config key, `article_order` — `08-changelog-design.md` |
| An in-product changelog | a platform portal whose articles are release notes — no new table |
| A revision history | **deferred**; the `audited` table could carry it, and it is recorded rather than built — `15-content-quality-audit.md` |
| Any Lynomia documentation content at all | `09-content-master-map.md` and the seeded corpus |
