---
agent: 086
scope: Super Admin authorization, CSRF and mass assignment on the documentation authoring surface
confidence: high
---

# Super Admin authorization, CSRF and mass assignment on the documentation authoring surface

Everything below is read from the branch as it stands. No server was started, nothing was modified, and no
payload was actually sent — the two boundary crossings in §3 are derived from the permitted-attribute lists, the
model callbacks and the public query scopes, each cited. Where a claim needs a running browser to settle, it is
marked **unverified** and says what would settle it.

## 1. Attack surface

`config/routes/documentation.rb` is drawn at `config/routes.rb:654`, outside the `devise_scope :super_admin`
block that closes at `config/routes.rb:630`. It produces exactly three resources and twenty-one routes:

| Route | Controller#action | Mass-assigns | CSRF-checked |
|---|---|---|---|
| `GET/POST/PATCH/DELETE /super_admin/articles[/:id]` | `SuperAdmin::ArticlesController` (Administrate CRUD) | yes, `resource_params` | yes (non-GET) |
| `POST /super_admin/articles/:id/publish` | `#publish` (`custom/.../articles_controller.rb:10`) | no | yes |
| `POST /super_admin/articles/:id/unpublish` | `#unpublish` (`:15`) | no | yes |
| `GET /super_admin/articles/:id/preview` | `#preview` (`:23`) | no | n/a (GET) |
| `GET/POST/PATCH/DELETE /super_admin/categories[/:id]` | `SuperAdmin::CategoriesController` | yes | yes (non-GET) |
| `GET/PATCH /super_admin/portals[/:id]` (index, show, edit, update only) | `SuperAdmin::PortalsController` | yes | yes (non-GET) |

The surface is not only these routes. The same three rows are writable from the tenant Help Center API
(`app/controllers/api/v1/accounts/articles_controller.rb`, `categories_controller.rb`, `portals_controller.rb`)
and readable from the public portal (`app/controllers/public/api/v1/portals/**`). The platform/tenant boundary is
a property of the **data**, not of any one controller, so the authoring surface has to be read together with the
two others. §3 F1 is a direct consequence of reading only one of them.

### The authorization chain, end to end

1. `config/routes.rb:590` — `devise_for :super_admins, path: 'super_admin'` creates the Warden scope
   `:super_admin`, mapped to `SuperAdmin`, which is an STI subclass of `User` on the `users` table with no
   behaviour of its own (`app/models/super_admin.rb:47`).
2. `app/controllers/super_admin/application_controller.rb:7` — `SuperAdmin::ApplicationController <
   Administrate::ApplicationController`, which is `< ActionController::Base`
   (`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:2`).
   It does **not** inherit the app's `ApplicationController`.
3. `app/controllers/super_admin/application_controller.rb:16` — `before_action :authenticate_super_admin!`.
4. All three documentation controllers inherit from it (`custom/app/controllers/super_admin/articles_controller.rb:9`,
   `categories_controller.rb:4`, `portals_controller.rb:5`) and none of them declares `skip_before_action`
   (grep over `app/controllers/super_admin` and `custom/app/controllers/super_admin` returns nothing).
5. There is no second decision. Administrate's authorization hook is a constant:

   ```ruby
   def authorized_action?(_resource, _action_name)
     true
   end
   ```
   (`vendor/.../administrate/application_controller.rb:258-260`)

   Nothing in the repository overrides it. **`authenticate_super_admin!` is the only authorization check on the
   entire documentation authoring surface** — there is no per-action, per-record or per-field authorization, and
   no policy object. A future "documentation editor" role has nothing to hang off.

**`:super_admin` vs `:user`.** They are not two tiers of the same session; they are two different
authentication systems that happen to share a table.

- The `:super_admin` scope is cookie-session-based. `config/initializers/session_store.rb:2` states the intent
  outright: *"Sessions are used only for the super_admin dashboard (flash/CSRF), not for API auth."*
- The agent dashboard and the whole `/api` tree authenticate by bearer header through devise_token_auth
  (`app/controllers/application_controller.rb:2`, `include DeviseTokenAuth::Concerns::SetUserByToken`) and
  **skip CSRF entirely** (`app/controllers/application_controller.rb:8`). There is no `:user` cookie session for
  an agent at all, so no agent credential can satisfy `authenticate_super_admin!`.
- Warden deserializes the `:super_admin` session key through `SuperAdmin.to_adapter`, which STI-scopes to
  `type = 'SuperAdmin'`; a plain user id in that key cannot resolve to a super admin.
- Consequence worth carrying into §3 F5: `Current.user` is never set on the Super Admin surface, because
  `set_current_user` lives in `ApplicationController` (`app/controllers/application_controller.rb:10,16-19`)
  which this tree does not inherit.

The routes being outside `devise_scope :super_admin` has **no authorization consequence** —
`authenticate_super_admin!` is a controller before_action, and Warden's throw carries `scope: :super_admin`
regardless of where the route was drawn. `config/routes/billing.rb:4` and `config/routes/operations.rb:8` use
the same pattern, so it is the repo convention, not an oversight specific to documentation.

## 2. What the existing defence actually does

### `scoped_resource` — what it restricts and what it does not

```ruby
def scoped_resource
  Article.where(portal: Documentation::Library.portals)
end
```
(`custom/app/controllers/super_admin/articles_controller.rb:29-31`; `Documentation::Library.portals` is
`Portal.platform.active.where(slug: SLUGS)` at `custom/app/services/documentation/library.rb:37-39`, with
`scope :platform` and `scope :active` at `app/models/portal.rb:71-72`.)

The controller's own comment claims this covers everything:

> *"Scoped to platform portals at `scoped_resource`, which is the single place Administrate resolves records from
> for index, show, edit, update and destroy alike."* (`articles_controller.rb:6-8`)

The first half is true. `requested_resource` → `find_resource(params[:id])` → `scoped_resource.find(param)`
(`vendor/.../administrate/application_controller.rb:183-195`), so `show`, `edit`, `update`, `destroy`, `publish`,
`unpublish` and `preview` all resolve through it. A tenant's article cannot be *reached* by id. **Verified.**

The claim is nonetheless incomplete in two ways, and both are exploitable:

- **It scopes record lookup, never attribute assignment.** `update` is
  `requested_resource.update(resource_params)` (`vendor/.../application_controller.rb:60`), and
  `resource_params` permits the raw foreign keys (below).
- **`create` does not consult it at all.** `create` is `new_resource(resource_params)` →
  `resource.save` (`vendor/.../application_controller.rb:42-46`). `scoped_resource` is never called on that
  path.

`SuperAdmin::CategoriesController#scoped_resource` is the same shape
(`custom/app/controllers/super_admin/categories_controller.rb:6-8`) and inherits both gaps.
`SuperAdmin::PortalsController#scoped_resource` returns `Documentation::Library.portals` directly
(`portals_controller.rb:7-9`); `create` and `destroy` are not routed, so the create gap does not apply there.

### `Field::BelongsTo.with_options(scope: ...)` is a UI affordance, not a constraint

`ArticleDashboard` declares:

```ruby
portal: Field::BelongsTo.with_options(scope: -> { Documentation::Library.portals }),
category: Field::BelongsTo.with_options(scope: -> { Category.where(portal: Documentation::Library.portals) }),
```
(`custom/app/dashboards/article_dashboard.rb:14-15`; the identical `portal` line is at
`custom/app/dashboards/category_dashboard.rb:11`.)

In Administrate 0.20.1 that `scope` lambda is consumed in exactly one place:

```ruby
def candidate_resources
  scope = options[:scope] ? options[:scope].call : associated_class.all
  ...
end
```
(`vendor/.../administrate-0.20.1/lib/administrate/field/belongs_to.rb:43-48`), which feeds
`associated_resource_options` — the `<option>` list of the `<select>` (`:24-31`). The permitted parameter is
unconditionally the bare foreign key:

```ruby
def self.permitted_attribute(attr, options = {})
  resource_class = options[:resource_class]
  if resource_class
    foreign_key_for(resource_class, attr)
  ...
end
```
(`belongs_to.rb:6-13`). **`scope:` never validates a submitted value.** It narrows what the browser offers and
nothing else.

### The permitted-attribute list, resolved

`resource_params` is `params.require(:article).permit(dashboard.permitted_attributes(action_name))`
(`vendor/.../administrate/application_controller.rb:203-207`), and `permitted_attributes` maps every entry of
`FORM_ATTRIBUTES` through its field's `permitted_attribute`
(`vendor/.../administrate/base_dashboard.rb:71-85`). For
`FORM_ATTRIBUTES = %i[portal category title slug description content locale status position meta]`
(`article_dashboard.rb:36`) that resolves to:

```
:portal_id, :category_id, :title, :slug, :description, :content, :locale, :status, :position,
{ meta: ['title', 'description', 'version', 'release_date', 'feature_image', { tags: [] }, :tags] }
```

**`meta` is NOT an unrestricted hash.** `ArticleMetaField.permitted_attribute` returns a six-key allow-list:

```ruby
def self.permitted_attribute(attr, _options = nil)
  { attr => STRING_KEYS + [{ tags: [] }, :tags] }
end
```
(`custom/app/fields/article_meta_field.rb:33-35`, with `STRING_KEYS` at `:13`). This is the right shape and is
the single best-designed part of the surface: `doc_key` — the contextual-help contract — is deliberately not
forgeable from a form post. §3 F4 is the cost of that choice, not an argument against it.

What is correctly **not** assignable: `author_id` (`author` is absent from `FORM_ATTRIBUTES`, and `new_resource`
forces `author: current_super_admin` at `articles_controller.rb:35-37`), `views`, `account_id`,
`associated_article_id`, `draft_title`, `draft_content`. For portals, `slug` and `config` are absent from
`PortalDashboard::FORM_ATTRIBUTES` (`custom/app/dashboards/portal_dashboard.rb:31`) — the two fields `/docs`,
`/changelog` and the whole link registry depend on. Those omissions are load-bearing and must survive the editor
upgrade.

### CSRF

```ruby
module Administrate
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
```
(`vendor/.../administrate/application_controller.rb:1-3`)

That is inherited by every Super Admin controller, including the three documentation ones, and nothing skips it.
The app-wide `skip_before_action :verify_authenticity_token` at `app/controllers/application_controller.rb:8`
does **not** reach this tree, because the inheritance chain is
`SuperAdmin::ApplicationController < Administrate::ApplicationController < ActionController::Base` — the app's
`ApplicationController` is not in it. The overridden layout emits the token
(`app/views/layouts/super_admin/application.html.erb:27`, `csrf_meta_tags`), and Administrate's forms are
`form_for`, so the token rides along. Relaxations are environment-scoped only:
`config.action_controller.allow_forgery_protection = false` in test (`config/environments/test.rb:35`) and
`forgery_protection_origin_check = false` in development (`config/environments/development.rb:72`).

`publish` and `unpublish` are `POST` and therefore covered. `preview` is `GET` and changes nothing, so CSRF does
not apply to it — see F9 for the open-redirect question.

### Administrate's search and sort

`Administrate::Search#query_template` builds `LOWER(CAST(#{table}.#{column} AS CHAR(256))) LIKE ?` with
`quote_table_name`/`quote_column_name` identifiers and a bound term
(`vendor/.../lib/administrate/search.rb:87-95,133-136,149-152`). `Administrate::Order#apply` builds the order
through `relation.arel_table[attribute]` and applies it only when `column_exist?` passes
(`lib/administrate/order.rb:9-19,113-115`), with the direction allow-listed to `asc`/`desc` (`:38-40`).
**No SQL injection from the authoring search box or the column headers.** Checked, not assumed.

## 3. Findings

### F1 — Tenant administrators can inject their own articles into Lynomia's public documentation portal — `blocker`, reachable today

**Claim.** An account administrator of any tenant can make their own article appear, published, on the public
`lynomia-docs` category pages, with their own agent names and avatars rendered as the section's authors. No
super admin is involved and no Super Admin route is touched.

**Evidence.** Three facts compose.

1. The tenant API permits `category_id` with no portal consistency check:
   ```ruby
   params.require(:article).permit(
     :title, :slug, :position, :content, :description, :category_id, :author_id, ...
   ```
   (`app/controllers/api/v1/accounts/articles_controller.rb:108-115`). The article itself is fetched through
   `@portal.articles.find(params[:id])` (`:65`) with `@portal` from `Current.account.portals` (`:91`), so the
   *article* is tenant-scoped — but the `category_id` it is pointed at is not scoped to anything.
2. Nothing on `Article` requires `category.portal_id == portal_id`. The model's only portal-adjacent callback is
   `before_validation :ensure_account_id` → `self.account_id = portal&.account_id`
   (`app/models/article.rb:58,230-232`); the validations are `account_id`, `author_id`, `title`, `content`,
   `slug`-exclusion (`:65-69`). `ensure_locale_in_article` (`:200-206`) then copies the *platform* category's
   locale onto the tenant's article, which makes it land in the right locale bucket.
3. The public documentation category page lists articles **by category, not by portal**:
   ```ruby
   articles = @category.articles.published.includes(:author)
   ```
   (`app/controllers/public/api/v1/portals/categories_controller.rb:32`). `@category` is correctly resolved from
   `@portal.categories` (`:25`), but `@category.articles` is `Article.where(category_id: …)` —
   `app/models/category.rb:33` — with no portal predicate.

   The injected row is then rendered: title and a `to_plaintext` excerpt of its content on a card
   (`app/views/public/api/v1/portals/documentation_layout/_article_card.html.erb:10-11`), the article count, and
   the author avatar group and "by …" label built from `@category_authors`
   (`categories_controller.rb:34`; `.../documentation_layout/categories/_header.html.erb:1,5-11`).

   The same unscoped `category.articles` appears in the classic portal layout too — `_category-block.html.erb:31,36,52`,
   `categories/_article_list.html.erb:4,9`, `categories/_category-hero.html.erb:28`, `_authors.html.erb:1,6,13`.
   The documentation layout's *sidebar* is the one place that already does it correctly:
   `portal.articles.published.where(category_id: sidebar_categories.map(&:id))`
   (`documentation_layout/_sidebar.html.erb:9`).

The required role is `administrator` on the attacker's own account —
`ArticlePolicy#update?` is `@account_user.administrator?` (`app/policies/article_policy.rb:6`). Platform category
ids are small sequential integers written by the seeder, so finding one is trial and error against a 422.

**Impact.** Content injection / defacement of Lynomia's own public documentation portal by a customer, plus
disclosure of that customer's agent names and avatars on the platform's public site. It is **not** stored XSS:
the card excerpt goes through `render_markdown_to_plain_text`, which returns a plain `String` and not an
`html_safe` one (`lib/chatwoot_markdown_renderer.rb:21-23` vs `:27-31`), so ERB escapes it. The injected
article's own detail page 404s, because `set_article` is portal-scoped
(`public/api/v1/portals/articles_controller.rb:80-83`) — so the card links nowhere. The reverse direction is the
same bug: an article left in the platform portal but pointed at a *tenant's* category surfaces in that tenant's
public help center.

**Severity.** `blocker`. It is the only finding here whose actor is not Lynomia staff. Agent 096 should attack it
independently; agent 081 should confirm the escaping claim against `to_plaintext` on a raw-HTML markdown block.

### F2 — The Super Admin `portal` field moves platform articles into tenant portals, irreversibly — `major`, reachable today

**Claim.** `PATCH /super_admin/articles/:id` with `article[portal_id]=<any tenant portal id>` moves a platform
documentation article into that tenant's Help Center, transfers ownership of the row to that account, removes it
from Super Admin's own reach, and poisons the content seeder.

**Evidence.**
- `:portal_id` is permitted (§2), and `scope:` does not validate it (§2).
- `update` is `requested_resource.update(resource_params)` (`vendor/.../application_controller.rb:60`).
- `before_validation :ensure_account_id` then rewrites ownership: `self.account_id = portal&.account_id`
  (`app/models/article.rb:58,230-232`).
- The one validation that could object is satisfied by that rewrite:
  `validates :account_id, presence: true, unless: :platform_owned?` (`:65`), where `platform_owned?` delegates to
  `portal&.platform_owned?` (`:110-112`). There is no `validates :portal, ... platform` anywhere.

**Impact, in order of severity.**
1. **Tenant gains full control of platform content.** `@portal.articles` in
   `app/controllers/api/v1/accounts/articles_controller.rb:65,91` now contains the article, so any administrator
   of that account can read, edit, unpublish or `destroy!` (`:39-42`) Lynomia's documentation. The article's
   `author` remains the super admin, so that staff member's name and email render in the tenant's authoring UI.
2. **Super Admin cannot undo it.** The row is no longer in `Article.where(portal: Documentation::Library.portals)`,
   so index, show, edit and update all 404. Recovery requires a Rails console or direct SQL.
3. **The content sync breaks permanently.** `Documentation::ContentSeeder#upsert_article` does
   `portal.articles.find_or_initialize_by(slug: slug_for(key, locale), locale: locale)`
   (`custom/app/services/documentation/content_seeder.rb:73`). With the row gone from `portal.articles` it
   *initializes a new* `Article` carrying the same slug, and `articles.slug` is a UNIQUE index
   (`app/models/article.rb:32`) with **no** matching model validation (`:69` only excludes `RESERVED_SLUGS`).
   `article.save!` (`content_seeder.rb:80`) therefore raises `ActiveRecord::RecordNotUnique`, and the seeder has
   no transaction and no rescue (`perform!` at `:28-31`) — so `rails documentation:content` aborts mid-run and
   stays broken until the row is fixed out of band. This compounds `01-current-system.md` §9.4.

**Severity.** `major`. The actor is a trusted super admin, which is why it is not a blocker, but there is no
confirmation, no audit entry (F5) and no way back, and the request needs no more than the browser's own form with
one id changed.

### F3 — `create` is not portal-scoped at all — `major`, reachable today

**Claim.** `POST /super_admin/articles` with `article[portal_id]=<tenant portal id>` creates an article inside a
tenant's Help Center.

**Evidence.** Administrate's `create` is `new_resource(resource_params)` then `resource.save`
(`vendor/.../administrate/application_controller.rb:42-46`). `scoped_resource` is never called on that path, and
the override `new_resource` only forces the author
(`custom/app/controllers/super_admin/articles_controller.rb:35-37`). Same for
`POST /super_admin/categories`.

**Impact.** Content authored in the platform console lands in a customer's help center and is invisible to the
console the moment it is saved. Same end state as F2 without needing an existing row. The controller comment's
claim that `scoped_resource` is *"the single place Administrate resolves records from"* (`:6-8`) is false for
`create`, and the comment is what a reviewer would trust.

### F4 — Saving an article in Super Admin silently destroys `meta['doc_key']` — `major`, reachable today

**Claim.** Opening any seeded article in Super Admin and pressing Save removes its contextual-help key, and the
degradation is silent and cross-lingual.

**Evidence.**
- `doc_key` is written only by the seeder: `{ 'doc_key' => key, 'title' => …, … }`
  (`custom/app/services/documentation/content_seeder.rb:106-113`).
- It is not in the field's allow-list (`custom/app/fields/article_meta_field.rb:13,33-35`) and the form renders
  no hidden input for it — the form partial iterates `STRING_KEYS` plus `tags` and nothing else
  (`custom/app/views/fields/article_meta_field/_form.html.erb:5-21`).
- `normalized_meta` rebuilds the hash from the submitted keys only and drops blanks:
  `meta = meta.to_h.compact_blank` (`custom/app/controllers/super_admin/articles_controller.rb:44-49`).
- Assigning a Hash to a jsonb column **replaces** it. `doc_key` is gone.

**Impact.** `Documentation::Library.article_for` resolves a key with
`by_key = articles.where("articles.meta->>'doc_key' = ?", key)` then
`by_key.find_by(locale: locale) || by_key.find_by(locale: DEFAULT_LOCALE) || by_key.first || article(key)`
(`custom/app/services/documentation/library.rb:54-57`). After an English article loses its key:

- `by_key` contains only the **Arabic** sibling, which still has its key;
- `find_by(locale: 'en')` is nil, `find_by(locale: 'en')` fallback is nil, so `by_key.first` returns the
  **Arabic** article — an English reader clicking contextual help gets Arabic.

If both siblings are edited, `by_key` is empty and the final `article(key)` fallback finds the English article by
slug, because the English slug *is* the key (`content_seeder.rb:85-87`) — Arabic then has no resolution path at
all, since its slug is `key-ar`. Either way the failure is asymmetric, invisible, and not caught by
`rake lynomia:docs:seo_audit`, which checks titles, descriptions, canonicals and hreflang but not `doc_key`
(`01-current-system.md` §8). A re-run of `rails documentation:content` heals it — which is precisely the sync
that nothing calls (`01-current-system.md` §4).

**Severity.** `major`. Triggered by the *intended* use of the authoring surface, by an author doing nothing
wrong, with no warning.

### F5 — Documentation authoring is not audited, and the `audited` macro cannot fix it — `major`, reachable today

**Claim.** No record is kept of who published, edited, moved or deleted a documentation article.

**Evidence.** The installation has a working audit trail — `Custom::AuditLog` is the `audited` gem's audit class
(`config/initializers/audited.rb:3-5`, `custom/app/models/custom/audit_log.rb:17`) with fourteen declared
capture points. `Article`, `Category` and `Portal` are not among them: `custom/app/models/custom/audit/` holds
`account, account_user, agent_bot, automation_rule, capture, conversation, custom_filter, inbox, inbox_member,
macro, team, team_member, user, webhook` and nothing else. The three documentation controllers write through
`update!`/`update`/`save`/`destroy` with no audit call
(`custom/app/controllers/super_admin/articles_controller.rb:10-26`).

Adding `audited` to `Article` would not be sufficient, and the repository already knows why. The gem's sweeper
resolves its actor through `Audited.current_user_method`, default `:current_user`:

```ruby
current_user: :current_user
...
def current_user
  lambda { controller.send(Audited.current_user_method) if controller.respond_to?(Audited.current_user_method, true) }
end
```
(`vendor/bundle/ruby/3.4.0/gems/audited-5.4.1/lib/audited/sweeper.rb:5-9,22-24`). On this surface the actor is
`current_super_admin`, and `Current.user` is never populated because `set_current_user` lives in the
`ApplicationController` this tree does not inherit (`app/controllers/application_controller.rb:10,16-19`). The
same conclusion is already written down twice for other features:
`custom/app/services/platform_support/audit_writer.rb:4-7` (*"a declared `audited` macro here would produce rows
attributed to nobody"*) and `custom/app/models/platform_support/ticket.rb:19` (*"DELIBERATELY NOT `audited`"*).

**Impact.** F2, F3, F6 and article deletion all happen with no trace of who did them. For a surface whose output
is public, brand-facing content on a shared platform, that is an accountability gap, and it is also the control
that would have made F2 detectable rather than archaeological.

### F6 — `archived` on a platform portal locks Super Admin out of its own documentation — `major`, reachable today

**Claim.** Ticking "Archived" on the `lynomia-docs` portal removes the entire documentation surface from Super
Admin, with no UI path back.

**Evidence.** `archived` is permitted (`custom/app/dashboards/portal_dashboard.rb:31`) and `Portal` validates it
not at all. `Documentation::Library.portals` is `Portal.platform.active.where(slug: SLUGS)`
(`custom/app/services/documentation/library.rb:37-39`), and `scope :active` is `where(archived: false)`
(`app/models/portal.rb:71`). All three documentation controllers scope through that method
(`articles_controller.rb:29-31`, `categories_controller.rb:6-8`, `portals_controller.rb:7-9`).

**Impact.** The Portals index becomes empty, so the archived portal cannot be opened to un-archive it;
Categories and Articles become empty; `/docs` renders the not-set-up 404
(`custom/app/controllers/documentation_controller.rb:9,30-38`); `Documentation::Library.docs_portal!` raises, so
`Documentation::ContentSeeder.new` raises at construction (`content_seeder.rb:21`). Recovery requires a console.
One checkbox, no confirmation, no audit entry.

### F7 — A duplicate article slug 500s instead of returning 422 — `minor`, reachable today

**Claim.** Typing an existing slug into the Super Admin article form raises `ActiveRecord::RecordNotUnique`.

**Evidence.** `slug` is permitted and free-text (`article_dashboard.rb:17`, `FORM_ATTRIBUTES` at `:36`).
`Article`'s only slug validation is `validates :slug, exclusion: { in: RESERVED_SLUGS }`
(`app/models/article.rb:69`); uniqueness is enforced solely by `index_articles_on_slug (slug) UNIQUE` (`:32`).
Administrate's `update`/`create` branch on `update`/`save` returning false
(`vendor/.../application_controller.rb:46,60`), which a database exception does not do.

**Impact.** A 500 and a Sentry event where the repository's own rule asks for a 422 at the boundary
(`CLAUDE.md`, *"Validate request parameters … so invalid input returns 422 Unprocessable Entity instead of
reaching models or Sentry"*). `Category` does not share this: it validates
`locale uniqueness scoped to [slug, portal_id]` (`app/models/category.rb:63-64`), matching its unique index
(`:25`).

### F8 — `publish`, `unpublish` and `preview` have no user interface — `minor`, reachable today

**Claim.** The three custom member routes are reachable only by hand-constructing the request.

**Evidence.** The shared Administrate show view renders Edit and Destroy and nothing else
(`app/views/super_admin/application/show.html.erb:26-40`); `_collection.html.erb` and `index.html.erb` contain
no documentation-specific links; there is no `custom/app/views/super_admin/articles/` directory at all (only
`billing_plans` and `billing_subscriptions` exist under `custom/app/views/super_admin/`); and a repo-wide grep
for `publish_super_admin|unpublish_super_admin|preview_super_admin` returns nothing outside the route file.

**Impact.** Publishing from the console happens only through the `status` select on the edit form, which means it
also carries F4. `preview` — the single most valuable action for the editor work this program is about — is
unreachable. And privileged routes with no UI get no review: F2 is a sibling of exactly this pattern. Either
render them or delete them.

Related and **unverified**: the Destroy link is `link_to … method: :delete`
(`app/views/super_admin/application/show.html.erb:33-39`), which needs rails-ujs or Turbo to become a DELETE.
Neither appears in `app/views/super_admin/application/_javascript.html.erb` (which iterates
`Administrate::Engine.javascripts`, populated only with `belongs_to_search.js` by
`vendor/bundle/ruby/3.4.0/gems/administrate-field-belongs_to_search-0.10.0/lib/administrate/field/belongs_to_search.rb:10`)
nor in either Vite entrypoint (`app/javascript/entrypoints/superadmin.js`,
`superadmin_pages.js`). If so the Destroy button is inert and degrades to a GET on the show path, which is
harmless but means deletion is also UI-unavailable. A browser would settle it.

### F9 — `preview` is not an open redirect, but it is unguarded by construction — `minor`

**Claim.** `GET /super_admin/articles/:id/preview` cannot be turned into a cross-origin redirect.

**Evidence.**
```ruby
redirect_to "/hc/#{article.portal.slug}/articles/#{article.slug}?show_plain_layout=true"
```
(`custom/app/controllers/super_admin/articles_controller.rb:22-26`). Three things make it safe, none of them a
check in this method:
1. The string is server-built and always begins with the literal `/hc/`, so it can never become
   protocol-relative (`//host`) or absolute (`https://host`). The author-controlled segments are interior.
2. `article.portal.slug` is constrained by `scoped_resource` to `lynomia-docs` or `lynomia-changelog`
   (`library.rb:12-14,37-39`).
3. `config.load_defaults 7.0` (`config/application.rb:39`) sets
   `action_controller.raise_on_open_redirects = true`
   (`vendor/bundle/ruby/3.4.0/gems/railties-7.2.3.2/lib/rails/application/configuration.rb:265`), so an
   off-host string would raise rather than redirect.

**Residual.** `article.slug` is unvalidated free text (F7), so the path segment is author-controlled: a slug of
`../..` yields a browser-normalised same-origin path. No cross-origin escape, no credential leak. The stylistic
defect is that the sibling public controller passes `allow_other_host: false` **explicitly** on both of its
redirects (`custom/app/controllers/documentation_controller.rb:25,33`) and `preview` does not, so the method
relies on an invariant that is nowhere stated. Add the flag and a slug format validation and the question stops
being interesting.

### F10 — Session handling: no idle timeout, MFA optional — `minor`

**Evidence.** `config/initializers/session_store.rb:8-12` — `cookie_store`, key `_chatwoot_session`,
`same_site: :lax`, `httponly: true`, `secure` gated on `FORCE_SSL` (defaulting to true in production, `:6`), no
`expire_after` so it is a browser-session cookie. `User`'s devise stack is
`:database_authenticatable, :registerable, :recoverable, :rememberable, :trackable, :validatable, :confirmable,
:password_has_required_content, :two_factor_authenticatable, :omniauthable`
(`app/models/user.rb:59-68`) — **no `:timeoutable` and no `:lockable`**, and `config.timeout_in` is commented out
(`config/initializers/devise.rb:167`). So a Super Admin session has no server-side idle expiry, and brute-force
defence is rack_attack alone: 5 per 5 min per IP and 5 per 15 min per email on `/super_admin/sign_in`
(`config/initializers/rack_attack.rb:78-83`). MFA is per-account opt-in —
`return true unless @super_admin.otp_required_for_login`
(`app/controllers/super_admin/devise/sessions_controller.rb:42`) — though when enabled it reuses the agent
`Mfa::AuthenticationService` (`:49-54`), which is the right call.

Two smaller items on the same surface:
- `get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'` (`config/routes.rb:592`) is a
  state-changing GET, contradicting `config.sign_out_via = :delete`
  (`config/initializers/devise.rb:245`). Logout CSRF only.
- `SuperAdmin::ApplicationController#order` reads `params.fetch(resource_name, {})`
  (`app/controllers/super_admin/application_controller.rb:24-31`) where Administrate reads
  `Hash.try_convert(request.query_parameters[resource_name]) || {}`
  (`vendor/.../administrate/application_controller.rb:175-177`). `GET /super_admin/articles?article=x` makes
  `params.fetch(:article, {})` return the String `"x"`, and `String#fetch` does not exist → `NoMethodError` →
  authenticated 500 on the article index. No SQL injection (§2).

### F11 — The shared Super Admin layout leaks staff identity and an HMAC into inline JS — `minor`, hand to 087

```erb
email: '<%= SuperAdmin.first.email %>',
name: '<%= SuperAdmin.first.name %>'
```
with `identifier_hash: '<%= ChatwootHub.support_config[:support_identifier_hash] %>'`
(`app/views/super_admin/application/_javascript.html.erb:43-47`). Rendered on **every** page of the
documentation authoring surface. `ERB::Util.html_escape` does not escape `'`, so a name containing an apostrophe
breaks the JS string literal; a name containing `';` is script injection into the console origin. `SuperAdmin.first`
is also the same row-order coupling flagged at `01-current-system.md` §9.5. Upstream Chatwoot code, not Lynomia's,
but it is on this surface and the editor upgrade will add more script to the same page. Agent 087 owns it.

### F12 — `custom_domain` on a platform portal bypasses the normalization the tenant API applies — `minor`

`custom_domain` is permitted (`custom/app/dashboards/portal_dashboard.rb:31`) and validated only for uniqueness
(`app/models/portal.rb:62`), with the `before_validation` normalizing an empty string to nil (`:54`). The tenant
API parses it to a bare host first — `URI.parse(@portal.custom_domain)` → `domain.host`
(`app/controllers/api/v1/accounts/portals_controller.rb:136-140`); Administrate does not, so Super Admin can
store a full URL or arbitrary string. That value is then compared against `request.host` in
`DashboardController#render_hc_if_custom_domain`, which renders the portal **in place of the agent dashboard**
at `/` (`app/controllers/dashboard_controller.rb:64-75`), and is interpolated into `robots.txt`
(`app/controllers/robots_controller.rb:37`) and `@help_center_url`
(`app/controllers/public/api/v1/portals_controller.rb:18`). Setting it to the installation's own host would
replace the dashboard with the docs portal. Trusted actor, unrecoverable from the UI by the same mechanism as F6.

### Severity summary

| # | Finding | Severity | Actor | Reachable |
|---|---|---|---|---|
| F1 | Tenant injects articles into the platform docs portal via `category_id` | blocker | tenant account administrator | today |
| F2 | `portal_id` moves platform articles into a tenant portal, irreversibly | major | super admin | today |
| F3 | `create` is not portal-scoped at all | major | super admin | today |
| F4 | Saving an article destroys `meta['doc_key']` | major | super admin (normal use) | today |
| F5 | Documentation authoring is unaudited, and `audited` cannot see this scope | major | — | today |
| F6 | `archived` on a platform portal locks the surface out | major | super admin | today |
| F7 | Duplicate slug → `RecordNotUnique` 500 instead of 422 | minor | super admin | today |
| F8 | `publish`/`unpublish`/`preview` have no UI | minor | — | today |
| F9 | `preview` safe only by construction; no `allow_other_host`, unvalidated slug | minor | super admin | today |
| F10 | No session timeout, no lockout, optional MFA, GET logout, `order` 500 | minor | — | today |
| F11 | Staff email/name and HMAC in inline JS on every authoring page | minor | — | today |
| F12 | `custom_domain` unnormalized on platform portals | minor | super admin | today |

Checked and clean, stated so deliberately: CSRF on the Administrate forms and on `publish`/`unpublish`
(§2); `meta` is an allow-list and not an open hash (§2); `author_id`, `views`, `account_id`,
`associated_article_id`, portal `slug` and portal `config` are not mass-assignable (§2); `find_resource` scoping
does hold for index/show/edit/update/destroy/publish/unpublish/preview (§2); no SQL injection via the search box
or column sort (§2); `authenticate_super_admin!` is applied to all three controllers with no skip (§1); the
`:user` scope cannot reach this surface (§1).

## 4. What the editor upgrade would newly expose

1. **Every new form attribute is a new mass-assignment.** `permitted_attributes` is derived mechanically from
   `FORM_ATTRIBUTES` (`vendor/.../base_dashboard.rb:71-85`), and there is no validation layer behind it —
   F2 and F3 exist precisely because two foreign keys were added to that list and the `scope:` lambda was
   mistaken for a constraint. Any field the new editor adds inherits that property by default.
2. **Media.** There is no media story today at all (`01-current-system.md` §9.8). An ActiveStorage field makes
   attachment and `signed_id` parameters assignable, and a `signed_id` is a bearer token for *any* blob in the
   installation — an attach-by-signed-id field is a cross-tenant blob read unless the surface validates
   ownership. Agents 066 and 083 own the detail; the mass-assignment shape is the part that belongs here.
3. **Live preview inside the console origin.** A side-by-side preview that renders through
   `ChatwootMarkdownRenderer#render_article` puts `html_safe` author HTML
   (`lib/chatwoot_markdown_renderer.rb:13-19,27-31`) into the Super Admin page, same-origin with every other
   Super Admin surface including Accounts and Users. Today the authoring surface renders content only through
   `Field::Text` (escaped) and `render_markdown_to_plain_text` (a plain String, escaped), so the console has no
   HTML-rendering path at all. Agents 081/082 own the sanitizer; the *origin* question is the one this report
   raises: a preview belongs in an iframe, and `preview`'s existing design — redirect to the real public
   `show_plain_layout` page — is already the safer answer.
4. **Autosave and draft endpoints.** The tenant API's draft path writes with `update_columns`, which skips
   validations by design (`app/controllers/api/v1/accounts/articles_controller.rb:98-106`). A Super Admin
   autosave copied from it would copy the validation bypass, and with it F7 and anything added for F1/F2.
5. **Any JSON endpoint added for the editor.** This is currently the only CSRF-protected tree in the
   application; `app/controllers/application_controller.rb:8` is the pattern an implementer will reach for, and
   it would be the first CSRF hole here.
6. **A documentation-author role.** `authorized_action?` is a hard-coded `true`
   (`vendor/.../application_controller.rb:258-260`). Introducing anyone less trusted than a full super admin
   requires building the first authorization decision this surface has ever had — and until F1–F3 are fixed, a
   lesser role would inherit the ability to cross the tenant boundary.

## 5. Required controls

Minimum set, each mapped to a mechanism that already exists. Ordered by the boundary each one defends.

1. **Reject out-of-scope foreign keys at the controller boundary.** In
   `SuperAdmin::ArticlesController#resource_params` and `SuperAdmin::CategoriesController`, reject a `portal_id`
   not in `Documentation::Library.portals` and a `category_id` whose portal is not in it, returning
   `422 Unprocessable Entity`. `Documentation::Library` is already *"the one door onto platform content"*
   (`library.rb:1-5`) — use it as the gate, not only as the select's option list. This covers F2 and F3 at the
   single shared entry point, as `CLAUDE.md` requires.
2. **One model invariant for the state that must never exist.** `validate :category_belongs_to_portal` on
   `Article`. This is the *only* control that also closes F1, because F1's write comes through the tenant API and
   no Super Admin change can reach it. It is not a redundant downstream guard — it is a different, proven path.
3. **Portal-scope the public category listing.** Change
   `app/controllers/public/api/v1/portals/categories_controller.rb:32` to read through
   `@portal.articles.published.where(category: @category)`, and do the same for the `category.articles` calls in
   `_category-block.html.erb:31,36,52`, `categories/_article_list.html.erb:4,9`,
   `categories/_category-hero.html.erb:28` and `_authors.html.erb:1,6,13`. The documentation sidebar already
   demonstrates the correct form (`documentation_layout/_sidebar.html.erb:9`). Defence in depth for F1 and the
   only fix for rows that are already mispointed.
4. **Preserve unknown `meta` keys.** `normalized_meta` must merge over the persisted hash rather than replace it,
   or `ArticleMetaField` must round-trip `doc_key` as a read-only displayed value. Keep the allow-list — it is
   correct that a form post cannot *forge* a `doc_key`. Fixes F4. Existing mechanism: `ArticleMetaField` plus the
   seeder's `meta_for` contract (`content_seeder.rb:106-113`).
5. **Audit documentation writes through the Lynomia writer, not the gem macro.** Use
   `AuditTrail::Event` (`custom/app/services/audit_trail/event.rb`) with the actor taken from
   `current_super_admin`, following the precedent and the stated reasoning in
   `custom/app/services/platform_support/audit_writer.rb:4-7`. Audit at minimum: create, portal/category change,
   status change, slug change and destroy. Fixes F5 and makes F2/F3/F6 detectable.
6. **`validates :slug, uniqueness: true` on `Article`**, matching the unique index at `app/models/article.rb:32`
   and the shape `Category` already has (`app/models/category.rb:63-64`). Fixes F7.
7. **Remove `archived` from `PortalDashboard::FORM_ATTRIBUTES`**, or drop `.active` from the Super Admin portal
   scope so an archived platform portal stays visible and recoverable in the console. Fixes F6. `slug` and
   `config` are already correctly excluded — keep them that way.
8. **Decide the three member routes.** Either render `publish`, `unpublish` and `preview` in the Administrate
   views, or delete them from `config/routes/documentation.rb`. A privileged route with no UI gets no review.
   Fixes F8; `preview` is the one the editor stream actually wants.
9. **`allow_other_host: false` on `preview`'s redirect** plus a slug format validation, matching
   `custom/app/controllers/documentation_controller.rb:25,33`. Fixes F9's residual and stops the invariant being
   implicit.
10. **Session hardening.** Add `:timeoutable` with an explicit `timeout_in` for the Super Admin scope, make the
    logout route `DELETE` to match `config.sign_out_via`, and fix `#order` to use `request.query_parameters` as
    Administrate does. Consider requiring MFA for super admins rather than leaving it opt-in — the sessions
    controller's own comment argues for it (*"A super admin reaches every account's data, so a password alone must
    not be enough"*, `app/controllers/super_admin/devise/sessions_controller.rb:38-40`) and then makes it
    conditional. Fixes F10.
11. **Hand F11 to agent 087 and F12 to the portal/SEO stream (073–080)** rather than fixing them here; both are
    pre-existing and neither is documentation-specific, but both sit on this surface.

### For Agent 000 to arbitrate

- **F1 crosses briefs.** Its write path is the tenant Help Center API and its read path is the public portal —
  neither is in 086's scope. It is reported here because the brief asked the `category_id` question, and the
  answer turned out not to be a Super Admin problem at all. Agents 096 (permissions) and 081 (render path) should
  attack it independently before Phase 4 freezes the content model.
- **F2 and F6 bear on charter §8 decision 1 (source of truth).** If repository Markdown is canonical, a re-seed
  heals F2's content but not its ownership — the moved row keeps the tenant's `account_id` and the seeder dies on
  the slug collision first. Any "database canonical" or hybrid answer has to say what happens to a row whose
  `portal_id` no longer satisfies the platform predicate.
- **F5 bears on §8 decision 6 (ownership map).** An unaudited authoring surface cannot support an ownership map
  that anyone can verify after the fact.
