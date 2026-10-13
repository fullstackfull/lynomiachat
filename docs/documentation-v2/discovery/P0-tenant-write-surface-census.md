# P0 — Complete census of tenant-reachable documentation WRITE and PRIVATE-READ surfaces

Branch: `claude/documentation-v2`. Ruling enforced against: **a tenant is a documentation READER ONLY; only the
Lynomia Super Admin authors documentation.** Scope excludes the cross-tenant *publication* leak
(`category_id` → platform portal), which a separate agent owns.

Verdict up front: **the authoring API is already closed, and closed correctly.** Exactly two surfaces are
genuinely open today, and only one of them is a documentation surface:

1. `GET /api/v1/accounts/:id/search/articles` (and `/search`) returns the **full body and status of a tenant's
   own draft and archived articles** to any authenticated member, including agents. No policy runs at all.
2. `GET /hc/:slug/articles/:slug.png` (tracking pixel) resolves an **unpublished** slug with `200`, making it an
   existence oracle for draft slugs on any portal, including the platform docs portal. No content leaks.

Everything else in the census is denied, and the denial is a single prepended policy overlay.

---

## 1. Census table

Legend for *reachable today*: evaluated for a **tenant administrator** (the most privileged tenant principal),
and where it differs, for an agent or a custom role holding every permission including `knowledge_base_manage`.

### Article write

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `POST .../portals/:portal_id/articles` | `app/controllers/api/v1/accounts/articles_controller.rb:26-32`; route `config/routes.rb:343` | write | **NO** | `articles_controller.rb:3` → `app/controllers/api/base_controller.rb:14-18` `authorize(Article)` → `Custom::ArticlePolicy#create? = false` (`custom/app/policies/custom/article_policy.rb:9`), prepended at `app/policies/article_policy.rb:31` | Nothing. Add an ancestor-order assertion (§4) |
| `PATCH/PUT .../articles/:id` | `articles_controller.rb:34-37` | write | **NO** | same chain → `update?` false (`custom/.../article_policy.rb:10`) | Nothing |
| `DELETE .../articles/:id` | `articles_controller.rb:39-42` | write | **NO** | `destroy?` false (`custom/.../article_policy.rb:11`) | Nothing |
| `POST .../articles/reorder` | `articles_controller.rb:44-47`; route `config/routes.rb:344` | write | **NO** | `reorder?` false (`custom/.../article_policy.rb:12`) | Nothing |
| `GET .../articles` (index, with draft/published/archived counts) | `articles_controller.rb:9-21,51-62` | private-read | **NO** | `index?` false (`custom/.../article_policy.rb:7`) | Nothing |
| `GET .../articles/:id`, `GET .../articles/:id/edit`, `GET .../articles/new` | `articles_controller.rb:23-24`; `resources :articles` at `config/routes.rb:343` | private-read | **NO** | `show?`/`edit?` false; `new?` falls through `ApplicationPolicy#new?` (`app/policies/application_policy.rb:24-26`) to `create?` false | Nothing |
| Wide strong-params permit list (`:status`, `:draft_title`, `:draft_content`, `:category_id`, `:author_id`, `meta`) | `articles_controller.rb:108-115` | write (latent) | **NO** — not a gate, but has none of its own | Only ever called from `create`/`update`/`persist_article_changes`, all behind `:3` | Leave upstream code alone. This is the exact line Agent 081 read; see §3 |
| Autosave / draft-only write via `update_columns` (skips validations + `updated_at`) | `articles_controller.rb:94-106` | write | **NO** | same `:3` gate | Nothing |

### Article bulk actions (publish / unpublish / recategorise / mass delete)

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `PATCH .../articles/bulk_actions/update_status` (**this is publish/unpublish**) | `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:10-20`; route `config/routes.rb:338` | write | **NO** | `bulk_actions_controller.rb:3,47-49` `authorize(Article, :create?)` → `Custom::ArticlePolicy#create?` false | Nothing |
| `PATCH .../bulk_actions/update_category` | `bulk_actions_controller.rb:22-32`; route `config/routes.rb:339` | write | **NO** | same | Nothing |
| `DELETE .../bulk_actions/delete_articles` | `bulk_actions_controller.rb:34-39`; route `config/routes.rb:340` | write | **NO** | same | Nothing |
| `POST .../bulk_actions/translate` | `bulk_actions_controller.rb:6-8` (`head :not_implemented`); route `config/routes.rb:337` | write | **NO** | same, and the body is a stub | Nothing |

### Category write

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `POST .../portals/:portal_id/categories` | `app/controllers/api/v1/accounts/categories_controller.rb:14-20`; route `config/routes.rb:332` | write | **NO** | `categories_controller.rb:3` → `authorize(Category)` → `Custom::CategoryPolicy#create? = false` (`custom/app/policies/custom/category_policy.rb:6`), prepended at `app/policies/category_policy.rb:31` | Nothing |
| `PATCH .../categories/:id` | `categories_controller.rb:22-28` | write | **NO** | `update?` false (`custom/.../category_policy.rb:7`) | Nothing |
| `DELETE .../categories/:id` | `categories_controller.rb:30-33` | write | **NO** | `destroy?` false | Nothing |
| `POST .../categories/reorder` | `categories_controller.rb:35-38`; route `config/routes.rb:333` | write | **NO** | `reorder?` false (`custom/.../category_policy.rb:10`) | Nothing |
| `GET .../categories`, `GET .../categories/:id` (locale management surface) | `categories_controller.rb:7-12` | private-read | **NO** | `index?`/`show?` false | Nothing |

### Portal write, archive, logo

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `POST .../portals` | `app/controllers/api/v1/accounts/portals_controller.rb:18-23`; route `config/routes.rb:326` | write | **NO** | `portals_controller.rb:5` → `authorize(Portal)` → `Custom::PortalPolicy#create? = false` (`custom/app/policies/custom/portal_policy.rb:27`), prepended at `app/policies/portal_policy.rb:39` | Nothing |
| `PATCH .../portals/:id` (incl. `config.analytics` script injection, `popular_content`, locales) | `portals_controller.rb:25-36,94-119` | write | **NO** | `update?` false (`custom/.../portal_policy.rb:28`) | Nothing |
| `DELETE .../portals/:id` | `portals_controller.rb:38-41` | write | **NO** | `destroy?` false | Nothing |
| `PATCH .../portals/:id/archive` | `portals_controller.rb:43-46`; route `config/routes.rb:328` | write | **NO** | `archive?` false (`custom/.../portal_policy.rb:34`). **Note: this is the ONLY definition of `archive?` anywhere** — `app/policies/portal_policy.rb` has none, so deleting the overlay turns a clean 401 into a `NoMethodError` 500 | Nothing. Do not delete the overlay |
| `DELETE .../portals/:id/logo` (purge) | `portals_controller.rb:48-51`; route `config/routes.rb:329` | write | **NO** | `logo?` false (`custom/.../portal_policy.rb:31`) | Nothing |
| `POST .../portals/:id/send_instructions` (mails CNAME instructions to an arbitrary address) | `portals_controller.rb:53-65`; route `config/routes.rb:330` | write | **NO** | `send_instructions?` false (`custom/.../portal_policy.rb:32`) | Nothing |
| **Portal logo attach-by-signed-id** | `portals_controller.rb:67-70` (`ActiveStorage::Blob.find_signed(params[:blob_id])` → `@portal.logo.attach`) | write | **NO** | Declared *above* `private` (`:72`) so it is technically a public method, but it is **not routed** (`config/routes.rb:326-331` declares only `archive`, `logo`, `send_instructions`), and is invoked only from `create`/`update`, both denied | Nothing. Worth a note in review: an unrouted public action method is one `routes.rb` line from reachable |
| `GET .../portals`, `GET .../portals/:id` | `portals_controller.rb:9-16` | private-read | **NO** | `index?`/`show?` false (`custom/.../portal_policy.rb:25-26`) | Nothing |
| `portals/:id/ssl_status` | route **deleted**; policy still refuses at `custom/.../portal_policy.rb:33` | private-read | **NO** (no route) | Both halves asserted at `spec/requests/custom/tenant_help_center_removal_spec.rb:31-34` | Nothing |

### Publish / unpublish / status transitions

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| Bare `status` param on article update | `articles_controller.rb:110` (`:status` in the permit list) consumed at `:104` `@article.update!(article_params)` | write | **NO** | `update?` false. `Article` has `enum status: { draft: 0, published: 1, archived: 2 }` (`app/models/article.rb:75`), so a single `PATCH {article:{status:"published"}}` would publish — the policy is the only thing stopping it | Nothing, but this is the highest-value line to keep a regression spec on |
| `status` default on create | `articles_controller.rb:27-28` (`params_with_defaults[:status] ||= :draft`) | write | **NO** | `create?` false | Nothing |
| Bulk `update_status` | `bulk_actions_controller.rb:10-20` | write | **NO** | `authorize(Article, :create?)` | Nothing |
| `Article#draft!` | `app/models/article.rb:140-142` | write (model) | **NO** from a tenant request — no tenant-reachable caller | — | Nothing |
| Super Admin publish / unpublish | `custom/app/controllers/super_admin/articles_controller.rb:10-18` | write | n/a (super admin) | Administrate + super-admin session; `scoped_resource` pinned to `Article.where(portal: Documentation::Library.portals)` (`:29-31`) — never consults `ArticlePolicy` | **Must keep working** |

### Draft and unpublished private read

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `draft_title` / `draft_content` serialised on the tenant API | `app/views/api/v1/accounts/articles/_article.json.jbuilder:7-8` | private-read | **NO** | Rendered only by `ArticlesController`, every action denied | Nothing |
| Public portal HTML draft resolution | `app/controllers/public/api/v1/portals/articles_controller.rb:80-88` — `scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published` | private-read | **NO** | `previewing_as_super_admin?` is `current_super_admin.present?` (`:85-87`). A tenant never holds a super-admin session | Nothing. This is a deliberate, correctly-narrowed exception |
| Public markdown endpoint | `public/.../articles_controller.rb:29-33` (`return head :not_found unless @article&.published?`) | private-read | **NO** | explicit `published?` guard | Nothing |
| **Tracking pixel** `GET /hc/:slug/articles/:slug.png` | `public/.../articles_controller.rb:35-48`; route `config/routes.rb:516` | private-read | **YES** (unauthenticated, in fact) | `@portal.articles.find_by(slug:)` is **unscoped by status** (`:36`); only the view-count increment is guarded (`:39`). Portal lookup at `app/controllers/public/api/v1/portals/base_controller.rb:35` is not account-scoped — it is a public route by design | **Narrow the lookup to `.published`.** Returns `200`+pixel for a draft slug, `404` otherwise → an existence oracle for unpublished slugs on *any* portal, platform included. No body leaks |
| Public portal search | `app/controllers/public/api/v1/portals/search_controller.rb:11` (`.published`) | private-read | **NO** | explicit `.published` | Nothing |
| Public categories JSON | `app/controllers/public/api/v1/portals/categories_controller.rb:14` (`@portal.categories.order(position: :asc)`) | private-read | **YES** (public) | Unfiltered; `draft_locales` config not applied. `Category` has no `status`, so no unpublished *article* leaks — only the existence of a category in a draft locale | Low. Decide whether `draft_locales` should hide categories; not a P0 |
| **Dashboard global search — articles** | `app/controllers/api/v1/accounts/search_controller.rb:2-4,18-20` → `app/services/search_service.rb:177-182` → `app/views/api/v1/accounts/search/_article.json.jbuilder:4,9` | **private-read** | **YES — administrator, agent, and any custom role** | **None.** `SearchController` has no `check_authorization` and no policy of any kind. `filter_articles` is `current_account.articles.text_search(q)` with **no `status` filter**. The view emits `article.content` (`:4`) and `article.status` (`:9`) | **FIX. See §4(b).** Returns the full body of the tenant's own `draft` and `archived` articles |
| Diff / preview endpoints on the tenant API | **none exist** | — | **NO** | The diff is purely client-side: `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue`, imported only by `ArticleEditor.vue:14,212` — inside the dead Vue tree (§ Vue below) | Nothing |
| Super Admin preview of an unpublished article | `custom/app/controllers/super_admin/articles_controller.rb:22-25` → `/hc/:slug/articles/:slug?show_plain_layout=true` | private-read | n/a (super admin) | Works *because* `previewing_as_super_admin?` is true | **Must keep working** |

### Article media authoring

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `POST /api/v1/accounts/:id/upload` | `app/controllers/api/v1/accounts/upload_controller.rb:1-54`; route `config/routes.rb:348` | write (blob mint) | **YES — every account member** | **None.** No `check_authorization`, no policy, no admin check. Returns `file_url` + `blob_id` (`signed_id`) at `:47-49`. Accepts a file (`:16-19`) or an external URL via `SafeFetch` (`:21-37`) | **Do NOT gate this.** It is shared infrastructure: the conversation composer uses the same endpoint (`app/javascript/dashboard/components/widgets/WootWriter/Editor.vue:640` → `app/javascript/dashboard/helper/uploadHelper.js:37`). A minted blob cannot enter documentation while the policy holds — `Article` declares no `has_many_attached` (`app/models/article.rb`), so media only ever appears as a markdown URL inside `content`, and writing `content` is denied |
| Direct uploads | `app/controllers/api/v1/accounts/conversations/direct_uploads_controller.rb` (route `config/routes.rb:129`); `app/controllers/api/v1/widget/direct_uploads_controller.rb` (route `config/routes.rb:381`) | write (blob mint) | YES (conversation/widget scoped) | Conversation-scoped; no documentation path | Nothing — no article direct-upload route exists |
| Blob attach-by-signed-id into documentation | only `portals_controller.rb:67-70` | write | **NO** | denied with `create`/`update` | Nothing |
| External-image proxy used by the article editor | `app/javascript/dashboard/store/modules/helpCenterArticles/actions.js:2` → `uploadHelper.js:65` (`uploadExternalImage`), dispatched from `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:360` | write (blob mint) | NO reachable caller | `FullEditor.vue` is imported **only** by `ArticleEditor.vue:11` (dead tree). The store module is still registered (`app/javascript/dashboard/store/index.js:8`), so the action is dispatchable, but it only mints a blob — it writes no article | Nothing |

### Search

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `SearchService#filter_articles` | `app/services/search_service.rb:177-182` | private-read | **YES** | No `status` filter. `Custom::SearchService` (`custom/app/services/custom/search_service.rb:16-39`) overrides `filter_conversations` and `message_base_query` **only** — it never touches `filter_articles` | **Override `filter_articles` in `Custom::SearchService` to `super.published`** (§4b) |
| Cross-tenant / platform leak via search | `search_service.rb:178` | private-read | **NO** | `current_account.articles` compiles to `WHERE account_id = $1`. A platform article has `account_id` NULL by construction (`app/models/article.rb:51-53,65,230-232`; `app/models/portal.rb:42-58`; `custom/app/services/documentation/library.rb:4-6`), and NULL can never satisfy that predicate. `Account has_many :articles` at `app/models/account.rb:68` | Nothing. A tenant cannot see platform articles here — which also means this endpoint is **not** the "search of published platform content" that must keep working |
| `/search` combined payload | `app/views/api/v1/accounts/search/index.json.jbuilder:17-21`; `app/views/api/v1/accounts/search/articles.json.jbuilder:1-7` | private-read | **YES** | same | Narrow the relation; see §4's "placed wrongly" note on deleting the `:articles` key |
| `_article.json.jbuilder` exposes body + status | `app/views/api/v1/accounts/search/_article.json.jbuilder:4,9` | private-read | **YES** | — | Follows from the relation fix. No view change needed once drafts are excluded |

### Vue surfaces

The **entire tenant authoring UI is dead code**: `helpcenter.routes.js` is not imported anywhere.
`app/javascript/dashboard/routes/dashboard/dashboard.routes.js:1-32` mounts `inbox`, `conversation`, `settings`,
`contacts`, `search`, `campaigns`, `analytics`, `tickets` and `help` — never `helpcenter`. A repo-wide grep for
`helpcenter.routes` returns nothing. There is also no sidebar or nav entry (grep over
`components-next/sidebar` and `components/layout` for `portals_index` / `help_center` / `helpCenter` is empty).

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| Whole authoring route tree (`portals_articles_new`, `portals_articles_edit`, `portals_categories_articles_new/edit`, `portals_categories_index`, `portals_locales_index`, `portals_settings_index`, `portals_new`, `portals_index`) | `app/javascript/dashboard/routes/dashboard/helpcenter/helpcenter.routes.js:29-130` | UI | **NO** (route tree unmounted) | Feature-flagged `FEATURE_FLAGS.HELP_CENTER` + `permissions: ['administrator','agent','knowledge_base_manage']` (`:25-28`), and `['administrator','knowledge_base_manage']` for `portals_new`/`portals_index` (`:96-99,105-108`). `help_center` is `enabled: false` in `config/features.yml:44-46`. But the decisive fact is that **nothing imports the file** | Defence in depth: either delete the tree or add a structural assertion that `dashboard.routes.js` does not import it. One re-import line restores the whole authoring UI |
| Pages | `helpcenter/pages/PortalsArticlesNewPage.vue`, `PortalsArticlesEditPage.vue` (client-side autosave + draft staging at `:60-88`), `PortalsArticlesIndexPage.vue`, `PortalsCategoriesIndexPage.vue`, `PortalsLocalesIndexPage.vue`, `PortalsSettingsIndexPage.vue`, `PortalsIndexPage.vue`, `PortalsNewPage.vue`, `HelpCenterPageRouteView.vue` | UI | **NO** | reachable only through the unmounted tree | as above |
| Components | `components-next/HelpCenter/Pages/ArticleEditorPage/{ArticleEditor,ArticleEditorControls,ArticleEditorHeader,ArticleEditorProperties,ArticleDiffPanel,ArticlePendingChangesPopover}.vue`; `.../ArticlePage/{ArticlesPage,ArticleList}.vue`; `.../CategoryPage/{CategoryForm,CategoryDialog,EditCategoryDialog,CategoryHeaderControls,CategoryList,CategoriesPage}.vue`; `.../PortalSettingsPage/{PortalSettings,PortalBaseSettings,PortalConfigurationSettings,DNSConfigurationDialog}.vue`; `.../LocalePage/{LocalesPage,LocaleList,PopularContentDialog}.vue`; `HelpCenterLayout.vue`; `PortalSwitcher/`; `EmptyState/**`; `ArticleCard/`, `CategoryCard/`, `LocaleCard/` | UI | **NO** | imported only from the dead pages; `HelpCenterLayout.vue` and `PortalSwitcher` have no importer at all outside the tree | as above |
| `FullEditor.vue` (the article WYSIWYG, incl. image upload) | `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue` | UI | **NO** | imported only by `ArticleEditor.vue:11,233`. Note it lives under `components/widgets/`, so it *reads* like shared code — it is not | Nothing; flag in review |
| Store modules still registered | `app/javascript/dashboard/store/index.js:8,16,43` register `articles`, `categories`, `portals` | UI | Dispatchable, but no reachable dispatcher of a write action | Write actions incl. `publishDraft` / `discardDraft` at `store/modules/helpCenterArticles/actions.js:101-123` | Harmless while the server denies. Clean up with the tree |
| API clients | `app/javascript/dashboard/api/helpCenter/articles.js:50-105` (update/create/delete/reorder/bulkTranslate/bulkUpdateStatus/bulkUpdateCategory/bulkDelete); `api/helpCenter/categories.js`; `api/helpCenter/portals.js` | UI | modules load, nothing reachable calls the writers | — | Clean up with the tree |
| **Reachable** documentation UI: global-search Articles tab | `app/javascript/dashboard/modules/search/search.routes.js:11-24`; `components/SearchView.vue:99,116,156,480`; `SearchResultArticlesList.vue`; `SearchResultArticleItem.vue` | UI (private-read) | **YES** | Gated client-side on `[...ROLES, PORTAL_PERMISSIONS]` where `PORTAL_PERMISSIONS = 'knowledge_base_manage'` (`app/javascript/dashboard/constants/permissions.js:36`) — i.e. every administrator and agent. Renders the status chip (`SearchResultArticleItem.vue:55`) and truncated `content` (`:43-53`) | Follows the server fix. Also: `navigateTo` (`:32-36`) points at `accounts/:id/portals/:slug/:locale/articles/edit/:id`, **a route that no longer exists** — the card is a dead link today. Repoint at `/hc/:portalSlug/articles/:slug` or drop the link |

### Swagger / OpenAPI

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| Public API contract | `swagger/index.yml:8-11` and `swagger/tag_groups/application_swagger.json:5` both state: *"this API has no Help Center endpoints. The inherited `/api/v1/accounts/{account_id}/portals` routes and their category and article routes still exist, but they are refused for every caller and are not part of this contract."* `swagger/swagger.json` contains **no** `/portals`, `/articles`, `/categories` or `/upload` path | doc | n/a | already closed | **Nothing.** Already closed and already explained |

### Anything else that writes `articles`, `categories` or `portals`

| Surface | file:line | Kind | Reachable today | Current gate | What must change |
|---|---|---|---|---|---|
| `Documentation::PortalSeeder` / `Documentation::ContentSeeder` | `custom/app/services/documentation/portal_seeder.rb`; `custom/app/services/documentation/content_seeder.rb` | write | **NO** from a tenant request | Operate only on `Documentation::Library` platform portals (`library.rb:37-44`); invoked from rake / Super Admin, never from an account-scoped request | **Must keep working.** Do not place a choke point on the models (§4) |
| `SuperAdmin::{Portals,Categories,Articles}Controller` | `custom/app/controllers/super_admin/portals_controller.rb:8-10`; `.../categories_controller.rb:8`; `.../articles_controller.rb:29-31` | write | n/a (super admin) | Administrate + super-admin session; `scoped_resource` pinned to `Documentation::Library.portals`, so a tenant's article is not reachable *there* either | **Must keep working** |
| Inbox → portal link (upstream accepted *any* portal id) | closed at `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb:18-22` (`refuse_help_center_link`, unscoped by action), `422` | write | **NO** | boundary refusal | Nothing |
| Onboarding help-center creation | `app/controllers/api/v1/accounts/onboardings_controller.rb:21-23,79-86` — `help_center_generation` returns a static `{generation_id: nil, state: nil, articles_count: 0, categories_count: 0}` stub. No `create_help_center`; `Onboarding::HelpCenterCreationService` does not exist | write | **NO** | the code path is gone, not neutralised | Nothing |
| Account sample-data seeder | `lib/seeders/account_seeder.rb` — grep for `portal`/`article`/`categor` is clean | write | **NO** | no documentation writes | Nothing |
| Data import | `app/services/data_imports/importer.rb:11` — `DEFAULT_IMPORT_TYPES = %w[contacts conversations]` | write | **NO** | no article/category/portal import type exists | Nothing |
| Account deletion cascade | `app/models/account.rb:68,75,96` — `has_many :articles / :categories / :portals, dependent: :destroy_async` | write | indirect | account deletion, not an authoring path | Nothing |
| `Article.update_positions` / `rebalance_positions` / `Category.update_positions` | `app/models/article.rb:150-184`; `app/models/category.rb` | write (model) | **NO** | only callers are the denied `reorder` actions | Nothing |
| Jobs | no job writes `articles`/`categories`/`portals` from a tenant-authenticated request (repo-wide grep for `articles.create` / `Article.create` / `articles.build` / `Article.new` outside specs returns only the two denied controllers, the Super Admin controller, and the platform seeder) | write | **NO** | — | Nothing |

---

## 2. Already closed — by the prior removal programme

Each line is proven by `spec/requests/custom/tenant_help_center_removal_spec.rb`, which runs **three principals**
(administrator, agent, and a custom role created with `CustomRole::PERMISSIONS` in full, including
`knowledge_base_manage` — `:21-24`) and asserts `401` for each (`:37-40`).

| Already closed | Proof |
|---|---|
| Portal index, show, create, update, destroy | `tenant_help_center_removal_spec.rb:46-53` |
| Portal logo purge, send_instructions, archive | `:55-60` |
| Article index, show, create, update, destroy, reorder | `:62-70` |
| Article publish and all four bulk actions (`update_status`, `update_category`, `delete_articles`, `translate`) | `:72-78` |
| Category index, create, update, destroy, reorder (the locale-management surface) | `:80-87` |
| `portals/:id/ssl_status` — route gone **and** policy still refuses | `:31-34` |
| Inbox → Help Center link refused at the boundary, incl. another account's portal and the platform docs portal | `:95-125` |
| Refusals delete nothing (a denied `DELETE` does not change `Portal.count`) | `:137-142` |
| Platform documentation portal stays resolvable and stays out of every tenant query (`Portal.tenant` / `Portal.platform`) | `:150-155` |
| `/docs` still redirects into `/hc/lynomia-docs` | `:157-161` |
| The public renderer `/docs` lands on is still routed to `public/api/v1/portals#show` | `:168-171` |
| Onboarding creates no tenant Help Center, and the service is structurally gone | `:184-193` |
| The policies themselves grant nothing to any tenant role | `spec/policies/article_policy_spec.rb:18-26`; `spec/policies/portal_policy_spec.rb:20-28`; `spec/policies/category_policy_spec.rb` |
| The public API contract no longer advertises any Help Center endpoint | `swagger/index.yml:8-11`; `swagger/tag_groups/application_swagger.json:5` |

**Deliberately left alive** (do not "fix" these):

- The whole Help Center **engine** — models, public renderer, layouts, locale handling, SEO, sitemap. The Lynomia
  documentation and changelog *are* Help Center portals (`custom/app/services/documentation/library.rb:1-10`).
- The tenant `portals` / `categories` / `articles` **routes** (`config/routes.rb:326-346`). The removal was done in
  the policy on purpose, so the engine keeps merging cleanly from upstream
  (`custom/app/policies/custom/portal_policy.rb:8-14`).
- `knowledge_base_manage` in `CustomRole::PERMISSIONS` (`custom/app/models/custom_role.rb:27`), listed as
  `RETIRED_PERMISSIONS` (`:34`) — roles created before the change still carry it and must stay saveable. The client
  no longer offers it (`app/javascript/dashboard/constants/permissions.js:4-12`).
- The global-search **Articles tab**, explicitly described at `app/javascript/dashboard/constants/permissions.js:34-36`
  as *"read-only and … the one way a workspace that published a help centre before this change can find its own, now
  frozen, pages."* **This is the surface the new ruling collides with** — see §4(b).
- Super Admin authoring, including unpublished preview.

**Not covered by the existing spec, so new specs are needed only here** (no duplication):
`/api/v1/accounts/:id/search/articles` and `/search` returning drafts; the tracking-pixel draft oracle; and a
structural assertion that the Custom policy overlay is actually prepended.

---

## 3. The 064-vs-081 contradiction, settled

**Agents 064 and 096 are correct. Agent 081 is wrong about reachability.** No action on the tenant article
controller is reachable by a tenant administrator — or by an agent, or by a custom role holding every permission —
today. `Custom::ArticlePolicy` genuinely **replaces** the OSS grants at runtime; it does not merely supplement them.

Evidence chain, each link read directly:

1. **The overlay is enabled.** `ChatwootApp.custom?` is `root.join('custom').exist?`
   (`lib/chatwoot_app.rb:31-33`) — the directory exists. So `ChatwootApp.extensions == ['custom']`
   (`lib/chatwoot_app.rb:42-44`). `ChatwootApp.enterprise?` is hard `false` (`:19-21`) and there is **no
   `enterprise/` directory** in the repo, so `custom` is the sole extension and no second module can prepend after it.
2. **The constant resolves.** `config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]`
   (`config/application.rb:46`). That glob expands to the direct subdirectories of `custom/app` — verified:
   `custom/app/policies` is in the list. Rails' `set_autoload_paths` initializer puts every eager-load path on the
   autoload paths, so `custom/app/policies` is a Zeitwerk root and
   `custom/app/policies/custom/article_policy.rb` defines `Custom::ArticlePolicy`.
3. **`prepend_mod_with` finds it and prepends.** `Module#prepend_mod_with`
   (`config/initializers/01_inject_enterprise_edition_module.rb:24-28`) iterates `ChatwootApp.extensions`
   (`:70-80`), resolves `Object::Custom` then `Custom::ArticlePolicy` via `const_defined?`/`const_get`
   (`:82-88` — both trigger Zeitwerk), and calls `prepend` (`:64-68`).
4. **Prepend wins.** `app/policies/article_policy.rb:31` is `ArticlePolicy.prepend_mod_with('ArticlePolicy')`.
   `prepend` inserts the module **ahead of** the class in the ancestor chain, so `Custom::ArticlePolicy#create?`
   (`false`, `custom/app/policies/custom/article_policy.rb:9`) is found before
   `ArticlePolicy#create?` (`@account_user.administrator?`, `app/policies/article_policy.rb:18-20`). Identically for
   `CategoryPolicy` (`app/policies/category_policy.rb:31`) and `PortalPolicy` (`app/policies/portal_policy.rb:39`).
   The Custom modules define **no `super` call** — every method is an unconditional `false`, so no OSS grant can leak
   through.
5. **The controller reaches the policy on every action.** `articles_controller.rb:3` is
   `before_action :check_authorization` with **no `only:` / `except:`**. `check_authorization`
   (`app/controllers/api/base_controller.rb:14-18`) does `authorize(controller_name.classify.constantize)` =
   `authorize(Article)`; Pundit resolves `ArticlePolicy` and calls `#{action_name}?`. `pundit_user` is the
   `{user:, account:, account_user:}` hash (`app/controllers/application_controller.rb:21-27`), which
   `ApplicationPolicy#initialize` destructures (`app/policies/application_policy.rb:4-10`).
   `Articles::BulkActionsController` has its own `check_authorization` → `authorize(Article, :create?)`
   (`app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:47-49`), so one denial covers all four
   bulk actions.
6. **A denial is a 401.** `rescue Pundit::NotAuthorizedError` → `render_unauthorized`
   (`app/controllers/concerns/request_exception_handler.rb:24-26`).
7. **Executable proof already in the repo.** `spec/requests/custom/tenant_help_center_removal_spec.rb:62-78`
   exercises exactly the create/update/destroy/reorder/bulk matrix for all three principals and expects `401`.
   `spec/policies/article_policy_spec.rb:18-26` asserts the policy grants nothing.

**Where 081 went wrong.** `app/controllers/api/v1/accounts/articles_controller.rb:108-115` *is* a wide permit list —
`:content`, `:title`, `:status`, `:draft_title`, `:draft_content`, `:category_id`, `:author_id`, `meta` — and
`article_params` carries **no authorization of its own**. 081 read that list (its §4 row and `:499`, `:525`, `:545`)
and inferred "any account user with Help Center access can write `content`/`title`/`meta`", concluding the
"trusted super admin" premise for the shared render path was "already false". The inference skips the chain above:
`article_params` is only ever called from `create` (`:27`), `update` → `persist_article_changes` (`:35,99-105`), and
`validate_author`/`discard_invalid_author`, all of which sit behind line `:3`.

So 081's finding is real but **mis-classified: it is a latent hazard, not a live hole.** It matters because the
permit list is what turns any restored `ArticlePolicy` grant into immediate full authoring, including a one-line
`PATCH {article:{status:"published"}}` publish. That is the argument for §4(a)'s structural assertion rather than
for touching upstream params.

---

## 4. Recommended enforcement design

### (a) Writes and private reads through the three tenant controllers — keep the existing choke point, make it unfalsifiable

The narrowest correct choke point **already exists and is already correct**: the three prepended policy modules
`Custom::{Portal,Article,Category}Policy`. It is the earliest shared point, exactly as its own comment argues
(`custom/app/policies/custom/portal_policy.rb:8-14`): all three controllers run an unconditional
`before_action :check_authorization` (`portals_controller.rb:5`, `articles_controller.rb:3`,
`categories_controller.rb:3`) and the bulk controller funnels through `authorize(Article, :create?)`
(`bulk_actions_controller.rb:47-49`). One denial per model covers index, show, new, edit, create, update, destroy,
reorder, archive, logo, send_instructions, ssl_status and all four bulk actions — 25 routes, 3 files, no upstream
edits.

Do **not** add a second gate. What is missing is a *structural* assertion that the prepend is in effect, so that a
future upstream merge, a change to `ChatwootApp.extensions`, or a reintroduced `Enterprise::ArticlePolicy` fails
loudly instead of silently restoring authoring. One spec, three assertions, in the existing
`spec/requests/custom/tenant_help_center_removal_spec.rb`:

```ruby
# The overlay must sit AHEAD of the OSS class, or every refusal below is decoration.
[[PortalPolicy, Custom::PortalPolicy], [ArticlePolicy, Custom::ArticlePolicy],
 [CategoryPolicy, Custom::CategoryPolicy]].each do |oss, overlay|
  expect(oss.ancestors.index(overlay)).to be < oss.ancestors.index(oss)
end
```

Leave `articles_controller.rb:108-115` alone. Narrowing an upstream permit list buys nothing while the policy holds,
costs a merge conflict every release, and would be the wrong place: the hazard is the *policy* being restored, not
the params being wide.

### (b) The one open documentation surface — article search

Fix in the overlay that already exists for exactly this purpose,
`custom/app/services/custom/search_service.rb`:

```ruby
def filter_articles
  @articles = super.published
end
```

Why this is the narrowest point:

- `SearchController#articles` and `#index` are the only two callers, and both route through
  `SearchService#perform` → `filter_articles` (`app/services/search_service.rb:17,19,177-182`).
- Kaminari's `total_count` re-runs the narrowed relation without its limit, so counts agree with the page — the same
  argument the existing overlay makes for conversations (`custom/app/services/custom/search_service.rb:14-15`).
- It is a Lynomia-level overlay, so upstream `search_service.rb` is untouched.
- It preserves what `app/javascript/dashboard/constants/permissions.js:34-36` says must be preserved: a workspace
  that published a help centre before the removal can still find its own **published** frozen pages.

**One product decision to escalate, not to guess.** The ruling says a tenant "must not reach drafts or unpublished
content." `.published` satisfies that exactly. A stricter reading — that a tenant should reach *no* documentation
through this endpoint at all — would be `super.none` plus removing the Articles tab from `SearchView.vue` and
`search.routes.js`, and retiring `PORTAL_PERMISSIONS`. `permissions.js:34-36` currently documents the opposite
intention, so flag the choice. `.published` is the minimum that satisfies the ruling and the maximum that is safe
without a product call.

### (c) Two small follow-ons

1. **Tracking pixel.** `app/controllers/public/api/v1/portals/articles_controller.rb:36` —
   `@portal.articles.find_by(slug:)` → `@portal.articles.published.find_by(slug:)`. The view-count guard at `:39`
   already assumes published, so the guard becomes redundant and the draft existence oracle closes. Upstream file, so
   do it in `Custom::Public::Api::V1::Portals::ArticlesController` — the `prepend_mod_with` hook is already declared
   at `:114`.
2. **Dead search link.** `app/javascript/dashboard/modules/search/components/SearchResultArticleItem.vue:32-36`
   points at the deleted `portals_articles_edit` route. Repoint at `/hc/:portalSlug/articles/:slug` (the reader) or
   drop the link. This is a live user-visible bug today, independent of the ruling.
3. **Dead Vue tree.** Either delete `app/javascript/dashboard/routes/dashboard/helpcenter/**` and
   `components-next/HelpCenter/**`, or add a structural assertion that `dashboard.routes.js` does not import
   `helpcenter.routes`. Defence in depth only — the server already fails closed — but a single re-import line
   restores the whole authoring UI, and `FullEditor.vue` sitting under `components/widgets/` makes the tree look
   shared when it is not.

### What breaks if the choke point is placed wrongly

- **On the models** (a `before_save` / validation that refuses tenant writes): breaks
  `Documentation::PortalSeeder` and `Documentation::ContentSeeder`, and breaks Super Admin publish/unpublish
  (`custom/app/controllers/super_admin/articles_controller.rb:10-18`) — platform rows go through the same
  `Portal`/`Category`/`Article` classes. A "tenant = has `account_id`" test happens to discriminate correctly
  (platform rows are NULL, `app/models/portal.rb:57-58`), but a "raise unless super admin" test does not: the
  seeders run with no session at all.
- **On `Api::V1::Accounts::BaseController`** (a blanket before_action): wider than needed, and a blanket
  `params.key?(:portal_id)` refusal there would collide with the targeted inbox refusal that already exists
  (`custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb:18-22`) and would start refusing unrelated
  endpoints.
- **In `SearchService#perform`** (dropping the `:articles` key instead of narrowing the relation):
  `app/views/api/v1/accounts/search/index.json.jbuilder:17-21` and `articles.json.jbuilder:3` iterate
  `@result[:articles]`; a missing key becomes `nil.each` → 500 on the main search page. Narrow the relation, never
  delete the key.
- **On `Api::V1::Accounts::UploadController`** (adding an admin check or a policy): breaks the conversation composer's
  image upload for agents — `Editor.vue:640` → `uploadHelper.js:37` hits the same `/upload` route
  (`config/routes.rb:348`). It is shared infrastructure, and no documentation write can consume its blob while the
  policy holds (`Article` declares no attachment association). Leave it.
- **On the public `Public::Api::V1::Portals::*` controllers** (adding authentication or a policy): breaks `/docs` and
  `/changelog` for everyone, which is the product. The public side is already correctly narrowed with `.published`
  (`public/.../articles_controller.rb:81`, `search_controller.rb:11`, `categories_controller.rb:32`) and its single
  super-admin preview exception (`public/.../articles_controller.rb:80-88`) must stay.
- **By deleting routes instead of keeping the policy overlay**: removes the thing that keeps the next upstream merge
  safe, and `Custom::PortalPolicy#archive?` (`custom/app/policies/custom/portal_policy.rb:34`) is the **only**
  definition of `archive?` in the codebase — `app/policies/portal_policy.rb` has none and `ApplicationPolicy` has
  none, so dropping the overlay converts a clean `401` on `PATCH .../portals/:id/archive` into a `NoMethodError` 500.
