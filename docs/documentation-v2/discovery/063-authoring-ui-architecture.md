---
agent: 063
scope: The current Super Admin authoring UI architecture — Administrate wiring, dashboards, fields, overridden views, layout, asset delivery, auth scope, routes — and what it would take to put a rich editor on the article form inside it
confidence: high
---

Read-only, against `claude/documentation-v2` at `f986521c`. Gem sources are vendored in-tree at
`vendor/bundle/ruby/3.4.0/gems/`, so every gem claim below is cited from a file on disk rather than from memory.

This report answers one question the rest of the editor stream depends on: **the article form is an Administrate
form, and Administrate on this installation is a Sprockets/jQuery surface with two Vite entrypoints bolted on.**
Section 4 is the constraint set an editor must satisfy; sections 1–3 are the evidence.

---

## 1. What exists today

### 1.1 Administrate: the version and how it is wired

| Fact | Evidence |
|---|---|
| `administrate` **0.20.1** (declared `>= 0.20.1`) | `Gemfile:97`, `Gemfile.lock:85` |
| `administrate-field-active_storage` **1.0.3** | `Gemfile:98`, `Gemfile.lock:93` |
| `administrate-field-belongs_to_search` **0.10.0** | `Gemfile:99`, `Gemfile.lock:96` |
| The engine's asset lists start empty and are seeded with one entry each | `vendor/.../administrate-0.20.1/lib/administrate/engine.rb:22-23,48-49` |
| Nothing in this repository calls `Administrate::Engine.add_javascript` / `add_stylesheet` | `grep -rn 'Administrate::Engine' config app custom lib` returns only the two view partials that *read* the lists |
| The ActiveStorage field gem adds its own stylesheet from inside its engine | `vendor/.../administrate-field-active_storage-1.0.3/lib/administrate/field/active_storage.rb:7-9` |
| Administrate requires jQuery, jquery_ujs, selectize, kaminari, sassc-rails and `sprockets/railtie` | `vendor/.../administrate-0.20.1/lib/administrate/engine.rb:1-5` |

So the Administrate asset surface is **three Sprockets logical paths**: `administrate/application.js`,
`administrate/application.css`, `administrate-field-active_storage/application.css`.

The Lynomia overlay reaches Administrate through two `config/application.rb` lines, not through a plugin API:

- `config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]` (`config/application.rb:46`) — this is what makes
  `ArticleDashboard`, `ArticleMetaField` and `SuperAdmin::ArticlesController` resolvable constants.
- `config.paths['app/views'].unshift('custom/app/views')` (`config/application.rb:48`) — `custom/app/views` is
  searched **before** `app/views`, which is before the gems' view paths.

### 1.2 The dashboards

`app/dashboards/` holds 8 upstream dashboards (`access_token`, `account`, `account_user`, `agent_bot`,
`installation_config`, `platform_app`, `platform_banner`, `user`). `custom/app/dashboards/` holds 5 Lynomia ones:
`article`, `category`, `portal`, `billing_plan`, `billing_subscription`.

The documentation three:

| Dashboard | `FORM_ATTRIBUTES` | Scope |
|---|---|---|
| `ArticleDashboard` | `portal category title slug description content locale status position meta` (`custom/app/dashboards/article_dashboard.rb:36`) | `portal`/`category` selects are scoped to `Documentation::Library.portals` (`:14-15`) |
| `CategoryDashboard` | `portal name slug description locale position icon` (`custom/app/dashboards/category_dashboard.rb:25`) | same portal scope (`:11`) |
| `PortalDashboard` | `name page_title header_text color custom_domain homepage_link archived` (`custom/app/dashboards/portal_dashboard.rb:31`) | `slug` is deliberately **not** editable |

`ArticleDashboard::COLLECTION_FILTERS` declares `published`, `draft`, `changelog`
(`custom/app/dashboards/article_dashboard.rb:38-42`); Administrate reads that constant inside its search parser
(`vendor/.../administrate-0.20.1/lib/administrate/search.rb:121-122`).

**The editing surface itself is one line**: `content: Field::Text.with_options(rows: 28)`
(`custom/app/dashboards/article_dashboard.rb:19`). See finding F1 — `rows: 28` does nothing.

### 1.3 Custom field classes and their views

`custom/app/fields/` — 5 classes: `article_author_field.rb`, `article_meta_field.rb`,
`billing_plan_channels_field.rb`, `billing_plan_features_field.rb`, `billing_plan_limits_field.rb`.
`app/fields/` — 7 upstream: `account_status_field`, `avatar_field`, `confirmed_at_field`, `count_field`,
`secret_field`, `serialized_field`, `suspension_history_field`.

The resolution mechanism, which matters for section 4:

- `Administrate::Field::Base.field_type` is `to_s.split("::").last.underscore`
  (`vendor/.../administrate-0.20.1/lib/administrate/field/base.rb:27-29`). `ArticleMetaField` → `article_meta_field`;
  `Administrate::Field::Text` → `text`.
- `#to_partial_path` is `"/fields/#{field_type}/#{page}"` (`.../field/base.rb:51-53`). The **leading slash** makes
  it an absolute partial, so it bypasses controller prefixes and resolves straight against the view paths:
  `custom/app/views/fields/...`, then `app/views/fields/...`, then the gems'.
- The form partial renders each field with `render_field attribute, f: f`
  (`vendor/.../administrate-0.20.1/app/views/administrate/application/_form.html.erb:43-44`).

`custom/app/views/fields/` therefore holds `article_meta_field/_{form,show,index}.html.erb`,
`article_author_field/_{show,index}.html.erb` and the three billing-plan field view sets.

`ArticleMetaField` is the most instructive precedent: it edits the `meta` jsonb as six named inputs — SEO title,
SEO description, tags, release version, release date, feature image URL — with per-key labels and hints declared
in Ruby (`custom/app/fields/article_meta_field.rb:15-31`), a `permitted_attribute` override that whitelists the
nested keys (`:33-35`), and a `_form` partial that hand-writes the `name="article[meta][key]"` attributes
(`custom/app/views/fields/article_meta_field/_form.html.erb:5-21`). Tag normalisation happens in the controller
(`custom/app/controllers/super_admin/articles_controller.rb:39-53`). `ArticleAuthorField` exists for a narrow
reason, documented in its own header: Administrate's `BelongsTo` would `link_to` a `SuperAdmin`, for which no
`super_admin_super_admin_path` exists, and the show page 500s (`custom/app/fields/article_author_field.rb:6-9`).

**Every one of those custom partials styles with inline `style=` attributes**
(`article_meta_field/_form.html.erb:6,12,15,20`; `billing_plan_channels_field/_form.html.erb:5,11,13`). That is not
sloppiness — see C4.

### 1.4 Every overridden Administrate view

The gem ships 16 views under `administrate/application/` and 45 under `fields/`
(`vendor/.../administrate-0.20.1/app/views/`). This installation overrides them from `app/views/super_admin/` and
`app/views/fields/`; **`custom/app/views/administrate/` and `app/views/administrate/` do not exist.**

| Gem view | Overridden here? | Note |
|---|---|---|
| `_collection.html.erb` | **yes** — `app/views/super_admin/application/_collection.html.erb` (95 lines vs the gem's 92) | A fork of an **older** Administrate view: it calls `existing_action?` and `authorized_action?` where 0.20.1 calls `accessible_action?`, and it inlines the action-column header instead of rendering `_collection_header_actions`. It still works only because both predicates remain `helper_method`s in 0.20.1 (`vendor/.../app/controllers/administrate/application_controller.rb:117-120,258-261`) |
| `_flashes.html.erb` | yes | |
| `_icons.html.erb` | yes — 188 lines, ~40 `<symbol>` ids | |
| `_javascript.html.erb` | yes | |
| `_navigation.html.erb` | yes — rewritten entirely | |
| `_search.html.erb` | yes | |
| `_stylesheet.html.erb` | yes | |
| `index.html.erb` | yes | Diverges: inlines the header instead of `render "index_header"`, adds `render "filters"`, and calls `paginate resources, param_name: '_page'` directly instead of `render "pagination"` (`app/views/super_admin/application/index.html.erb:30-74`) |
| `show.html.erb` | yes | |
| **`_form.html.erb`** | **no** | the gem's is used verbatim — this is the article form |
| **`new.html.erb` / `edit.html.erb`** | **no** at the application level | overridden per-resource only for accounts (`app/views/super_admin/accounts/edit.html.erb`) |
| `_pagination`, `_index_header`, `_collection_header_actions`, `_collection_item_actions` | no | orphaned by the `index`/`_collection` forks |
| `fields/belongs_to/_{form,show,index}`, `fields/polymorphic/_{form,show,index}` | yes (`app/views/fields/`) | |
| `fields/text/_{form,show,index}` | **no** | the gem's `f.text_area field.attribute` is the article editor |

Three views have **no gem counterpart** — they are additions: `_filters.html.erb`, `_nav_item.html.erb`,
`_settings_menu.html.erb`.

Per-resource view overrides already in use: `super_admin/accounts/{edit,show,_reset_cache,_seed_data}`,
`super_admin/users/{show,_collection,_impersonate}`, and in the overlay
`custom/app/views/super_admin/billing_subscriptions/{show,_override_form}`,
`custom/app/views/super_admin/billing_plans/settings`. **There is no `super_admin/articles/` view directory in
either tree.**

### 1.5 The Super Admin layout

`app/views/layouts/super_admin/application.html.erb`, 40 lines. The head:

```erb
24  <%= render "stylesheet" %>
25  <%= vite_client_tag %>
26  <%= vite_javascript_tag 'superadmin' %>
27  <%= csrf_meta_tags %>
```

The body renders `_icons`, `_navigation`, `_flashes`, `yield`, then `_javascript` (`:30-38`). `_navigation.html.erb`
opens with a **second** `vite_client_tag` and a second entrypoint:

```erb
10  <%= vite_client_tag %>
11  <%= vite_javascript_tag 'superadmin_pages' %>
```

`_javascript.html.erb` iterates `Administrate::Engine.javascripts` (`:10-12`), yields `:javascript` (`:14`),
disables jQuery animation and forces synchronous AJAX in the test env (`:16-21`), then emits an inline `<script>`
that boots the Chatwoot support widget from `/packs/js/sdk.js` and identifies the operator with
`SuperAdmin.first.email` / `.name` (`:23-50`, names at `:46-47`).

The nav sidebar enumerates every routed Administrate resource and skips 12 by name, with a comment explaining that
a controller without an index route and a dashboard raises and breaks the partial on *every* page
(`app/views/super_admin/application/_navigation.html.erb:39-56`). Documentation's three resources get sidebar icons
from a literal hash (`:14-24`).

### 1.6 How JS and CSS reach a Super Admin page

**Established: Sprockets *and* Vite. There is no importmap** — no `config/importmap.rb`, and `importmap` appears
nowhere in `Gemfile`, `Gemfile.lock` or `package.json`.

**Sprockets** — `sprockets 4.2.1` / `sprockets-rails 3.4.2` (`Gemfile.lock:957,960`). `app/assets/config/manifest.js`
declares exactly five things:

```
1  //= link_tree ../images
2  //= link administrate/application.css
3  //= link administrate/application.js
4  //= link administrate-field-active_storage/application.css
5  //= link secretField.js
```

`administrate/application.css` resolves to the **app's** fork, not the gem's:
`app/assets/stylesheets/administrate/application.scss` (32 lines of `@import`, including `selectize` from
selectize-rails and a `custom_styles` tail), backed by 23 partials under
`app/assets/stylesheets/administrate/{reset,utilities,library,base,components}/`.
`administrate/application.js` is the gem's four-line Sprockets directive file: `jquery`, `jquery_ujs`, `selectize`,
`require_tree .` (`vendor/.../administrate-0.20.1/app/assets/javascripts/administrate/application.js:1-4`), pulling
in `components/{associative,select,table}.js`. So **jQuery is on every Super Admin page.**
`secretField.js` is included ad hoc by `javascript_include_tag "secretField"` at three call sites
(`app/views/super_admin/settings/show.html.erb:25`, `app/views/fields/secret_field/_{index,show}.html.erb:4`).

**Vite** — `vite_rails 3.10.0` / `vite_ruby 3.10.2` (`Gemfile:80`, `Gemfile.lock:1015-1016`), `vite.config.ts` with
`vite-plugin-ruby`, `@vitejs/plugin-vue` and `@rollup/plugin-yaml`, `sourceCodeDir: app/javascript`
(`config/vite.json:3`). Two of the nine entrypoints are Super Admin's:

- `app/javascript/entrypoints/superadmin.js` — line 1 imports
  `../dashboard/assets/scss/super_admin/index.scss`; the rest is the 36-line account-suspension form progressive
  enhancement (`:3-38`). The SCSS imports the Inter font and `tailwindcss/{base,components,utilities}`
  (`app/javascript/dashboard/assets/scss/super_admin/index.scss:1-4`) and then declares the full radix colour-token
  `:root` and `.dark` sets (`:10-213`). **This is how Tailwind reaches Super Admin** — through PostCSS inside the
  Vite SCSS pipeline (`postcss.config.js` loads `tailwindcss`), emitted as the entry's CSS by
  `vite_javascript_tag`'s stylesheet pass (`vendor/.../vite_rails-3.10.0/lib/vite_rails/tag_helpers.rb:52`).
- `app/javascript/entrypoints/superadmin_pages.js` — the Vue island runtime. `createApp` + `VueDOMPurifyHTML` only
  (`:16-24`), a two-entry `ComponentMapping` (`:8-11`), and a `DOMContentLoaded` hook that reads
  `#app`'s `data-component-name` / `data-props` and mounts (`:27-33`).

The island is produced server-side by `render_vue_component`, a private controller method exposed as a helper
(`app/controllers/super_admin/application_controller.rb:14,33-42`); it emits
`<div id="app" data-component-name=… data-props=…>`. Exactly one call site exists today:
`app/views/super_admin/dashboard/index.html.erb:5`.

Vue components under `app/javascript/superadmin_pages/` can use the shared aliases — `shared/`, `dashboard/`,
`next/`, `components/` (`vite.shared.ts:3-14`) — and already do
(`app/javascript/superadmin_pages/views/dashboard/Index.vue:5` imports `shared/components/charts/BarChart.vue`).

**CSS load order in `<head>`: Administrate's Sprockets CSS at layout line 24, Tailwind's Vite CSS at line 26.**
Tailwind preflight therefore loads last and wins every conflict with Administrate's `_normalize`/`_forms`.

### 1.7 Authentication scope, and the absence of authorization

- `devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }`
  (`config/routes.rb:590`). `SuperAdmin < User` — an STI subclass, no behaviour of its own
  (`app/models/super_admin.rb:47-48`).
- `SuperAdmin::ApplicationController < Administrate::ApplicationController` with exactly one guard:
  `before_action :authenticate_super_admin!` (`app/controllers/super_admin/application_controller.rb:7,16`). It also
  overrides `order` to default to `id desc` (`:24-29`).
- **No authorization layer.** Administrate's `authorized_action?` returns a bare `true`
  (`vendor/.../administrate-0.20.1/app/controllers/administrate/application_controller.rb:258-261`) and nothing in
  either controller tree overrides it. No Pundit include, no policy, in `app/controllers/super_admin/` or
  `custom/app/controllers/super_admin/`. Every signed-in super admin can reach everything routed.
- Record scoping is the only control, and it is per-controller `scoped_resource`:
  `Article.where(portal: Documentation::Library.portals)`
  (`custom/app/controllers/super_admin/articles_controller.rb:29-31`), `Documentation::Library.portals`
  (`custom/app/controllers/super_admin/portals_controller.rb:8-10`),
  `Category.where(portal: Documentation::Library.portals)`
  (`custom/app/controllers/super_admin/categories_controller.rb:7-9`). Administrate resolves index, show, edit,
  update and destroy from that one method, so a tenant's help-center article is not reachable here at all.
- `Sidekiq::Web` is mounted inside `authenticated :super_admin` (`config/routes.rb:627-629`).
- No `timeout_in` is configured (`config/initializers/devise.rb:167` is the commented default).

### 1.8 Routes

`config/routes/documentation.rb`, drawn at `config/routes.rb:654`:

```ruby
6   namespace :super_admin do
7     resources :portals, only: [:index, :show, :edit, :update]
9     resources :categories
11    resources :articles do
12      member do
13        post :publish
14        post :unpublish
15        get :preview
```

Note this `namespace :super_admin` block sits **outside** the `devise_scope :super_admin do … end` block that wraps
the upstream resources (`config/routes.rb:591-630`). That is harmless — `devise_scope` only affects Devise
controller mapping, and authentication comes from the controller's `before_action` — but it means the documentation
routes are declared in a different lexical place from every other Super Admin resource.

The three member actions are 15 lines of controller: `publish`/`unpublish` set `status` and redirect with
`documentation.super_admin.published` / `.unpublished` (`config/locales/en.yml:79-80`); `preview` redirects to the
real public article with `?show_plain_layout=true`
(`custom/app/controllers/super_admin/articles_controller.rb:10-25`). `new_resource` injects
`author: current_super_admin` (`:35-37`).

---

## 2. Constraints the existing system imposes

**C1 — The content field is rendered by a gem partial that ignores its options.** The article form is the gem's
`_form.html.erb`, which calls `render_field` per attribute; `content` resolves to
`vendor/.../administrate-0.20.1/app/views/fields/text/_form.html.erb:20-22`, whose body is
`<%= f.text_area field.attribute %>` — no options, no `rows`. Changing the editor means changing *which partial
path* `content` resolves to, which means a new field class or a per-resource form override. Overriding
`fields/text/_form` directly would change every `Field::Text` on every dashboard in the installation.

**C2 — Sprockets is effectively frozen in production.** `config.assets.compile = false`
(`config/environments/production.rb:32`); `public/assets/administrate*` is gitignored (`.gitignore:35`) and
untracked; and `deployment/deploy.sh` runs `pnpm install --frozen-lockfile` (`:244`),
`pnpm vite build` (`:284`) and `pnpm build:sdk` (`:288`) but **never `rake assets:precompile`** — that appears only
in the one-time server bootstrap (`deployment/setup_20.04.sh:395,1029`, `deployment/setup_18.04.sh:70`) and in
`docker/Dockerfile:85`, an image path a prior phase established production does not use
(`docs/p7/00-discovery-findings.md:409`). Deploy is in-place `git fetch` + fast-forward (`deployment/deploy.sh:89`),
so the Sprockets output already on the box survives — and a *new or changed* Sprockets asset would not be built.
**An editor delivered through Sprockets would 404 in production.**

**C3 — Vite is the only live asset path, and it is already tagged on every page.** `superadmin` (layout:26) and
`superadmin_pages` (navigation:11) are rendered on every Super Admin page, Administrate and bespoke alike, because
both tags live in the layout chain. Nothing new has to be added to the layout for an editor — which is also the
hazard in C8.

**C4 — Tailwind does not see `custom/app/views`.** `tailwind.config.js:24-38` globs
`./app/javascript/superadmin_pages/**/*.vue`, six other `app/javascript` trees and `./app/views/**/*.erb`. It does
**not** glob `custom/app/views`. Measured consequence: no Tailwind utility appears anywhere in `custom/app/views`
(`grep -rnE 'class="[^"]*(flex|text-sm|mt-[0-9]|px-[0-9]|bg-slate|grid|w-full|rounded)' custom/app/views/` returns
nothing); the overlay styles with Administrate's own BEM class names plus inline `style=` attributes. Meanwhile
`app/views` ERB uses Tailwind freely, including arbitrary variants
(`app/views/super_admin/accounts/edit.html.erb:17`, `app/views/super_admin/application/_filters.html.erb:31-48`).
So a field partial in `custom/app/views/fields/` **cannot** be styled with Tailwind unless the glob is extended.

**C5 — The field-unit box is ~498px wide and vertically centred.** `.field-unit__field { max-width: 31.15rem }`
and `.field-unit { display: flex; align-items: center }`
(`app/assets/stylesheets/administrate/components/_field-unit.scss:1-22`). Any editor rendered inside
`render_field` inherits both. A full-width or side-by-side editor has to escape the field unit, which means a
per-resource form override, not a field partial.

**C6 — The Vue island is single-slot and bare.** `superadmin_pages.js:27-33` does `getElementById('app')` and
`app.mount('#app')` — one island per page, keyed by a hard-coded id. The app is `createApp` plus
`VueDOMPurifyHTML` (`:23`): **no Vuex store, no `vue-i18n`, no `vue-router`, no `useAlert` host**. The article form
has no island today, so one editor island fits; a second component mounted separately does not.

**C7 — The product's existing rich article editor is bound to the tenant dashboard app.**
`app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue` (290 lines) already
does what this program wants — draft title/content with `??` preservation (`:44-56`), pending-upload guards
(`:61-69`), a diff panel, `ARTICLE_EDITOR_MENU_OPTIONS` (`:7`) — and it wraps
`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue` (676 lines), which is ProseMirror over
`@chatwoot/prosemirror-schema` (`FullEditor.vue:25,27`, styles at `:649`). But `FullEditor` requires
`this.$store.dispatch('articles/uploadExternalImage', …)` (`:360`), `useMapGetter`, `useUISettings`, `useAlert`
(`:34-36`) and `$t` (`:142`); `ArticleEditor.vue` adds `onBeforeRouteLeave` and `useI18n` (`:4-5`). None of those
exist in the Super Admin island (C6).

**C8 — Every Super Admin page render in a Ruby spec runs Vite.** `vite_client_tag` is inert outside the dev server
(`vendor/.../vite_ruby-3.10.2/lib/vite_ruby/manifest.rb:62-63` returns nil unless `dev_server_running?`), but
`vite_javascript_tag` calls `resolve_entries` → `lookup!` → `lookup`, which runs
`@build_mutex.synchronize { builder.build }` whenever `config.auto_build && !dev_server_running?`
(`manifest.rb:44,95,107,124`), raising `MissingEntrypointError` (`:234`) or, if the binary is absent,
`ViteRuby::MissingExecutableError` from `Errno::ENOENT` (`vite_ruby-3.10.2/lib/vite_ruby/runner.rb:18-19`).
`config/vite.json:11-15` sets `"test": { "autoBuild": true }`. **This has already cost a real spec failure**: the
Platform Support integration run recorded that "the staff ERB pages render a Vite tag, so the run needs a built
manifest and `VITE_RUBY_AUTO_BUILD=false`; without them every Super Admin page 500s on
`ViteRuby::MissingExecutableError` and **24 examples fail** for a reason that has nothing to do with the product"
(`docs/platform-support/13-integration-record.md:87-91`). Controller specs are immune (views are not rendered;
no `render_views` appears in `spec/controllers/super_admin/`), but request specs are not — e.g.
`spec/requests/documentation/global_ownership_spec.rb:91-103` signs in a super admin and hits Super Admin paths.

**C9 — Uploads from Super Admin have no endpoint.** The existing editor uploads via
`POST /api/v1/accounts/:accountId/upload`, with `accountId` scraped from
`window.location.pathname.split('/')[3]` (`app/javascript/dashboard/helper/uploadHelper.js:27-37`). That controller
inherits `Api::V1::Accounts::BaseController` → `Api::BaseController`, whose guard is `authenticate_user!` in the
devise_token_auth `:user` scope plus `current_account` membership (`app/controllers/api/base_controller.rb:6`,
`app/controllers/api/v1/accounts/base_controller.rb:4`). A Warden `:super_admin` session does not satisfy it, a
`SuperAdmin` has no `AccountUser` row, a platform article has `account_id = NULL`
(`app/models/article.rb:51-53,65`), and a Super Admin URL yields the wrong path segment anyway. **No reachable
upload path exists on this surface.**

**C10 — ActionText is loaded but has no table.** `rails/all` requires `action_text/engine`
(`vendor/.../railties-7.2.3.1/lib/rails/all.rb:14`), and `.gitignore:36-38` still ignores precompiled
`action*.js`, `activestorage*.js` and `trix*`. But `grep -n action_text db/schema.rb` returns nothing — there is no
`action_text_rich_texts` table. `has_rich_text` is a migration away, and it would introduce HTML as a second
content representation beside the CommonMark that `ChatwootMarkdownRenderer` and the Markdown corpus require.

**C11 — ActiveStorage *is* wired into Administrate and proven.** `Field::ActiveStorage` is in production use on
`User#avatar` and `AgentBot#avatar` with a `destroy_url` proc (`app/dashboards/user_dashboard.rb:14-18`,
`app/dashboards/agent_bot_dashboard.rb:13`), its form partial emits
`f.file_field …, multiple: field.many?, direct_upload: field.direct?`
(`vendor/.../administrate-field-active_storage-1.0.3/app/views/fields/active_storage/_form.html.erb:32`), and
`direct_upload:` is an available option (`.../lib/administrate/field/active_storage.rb:47-49`). ActiveStorage tables
exist (`db/schema.rb:89,99`).

**C12 — The CSP constrains nothing today, and that is load-bearing.** Only `object_src :none` and `base_uri :self`
are set, with a comment that `script-src`/`style-src` are deliberately absent until enumerated
(`config/initializers/content_security_policy.rb:10-17`). The existing surface *relies* on that: an inline
`<script>` plus an inline `onchange=` handler in `_filters.html.erb:39,54-62`, the inline support-widget bootstrap
in `_javascript.html.erb:23-50`, and inline `style=` throughout `custom/app/views`. An editor that needs
`blob:` workers or `unsafe-eval` works now and breaks at CSP stage two.

---

## 3. Findings

**F1 — `rows: 28` is inert; the real editing box is a browser-default textarea capped at ~498px.**
`custom/app/dashboards/article_dashboard.rb:19` passes `rows: 28`, but the partial that renders it is
`vendor/.../administrate-0.20.1/app/views/fields/text/_form.html.erb:21` = `f.text_area field.attribute` with no
options, and no override of `fields/text/_form` exists in `custom/app/views/fields/` or `app/views/fields/`. No
textarea height rule exists in the Administrate SCSS either — only `resize: vertical`
(`app/assets/stylesheets/administrate/base/_forms.scss:70-72`) and the ~498px cap from
`_field-unit.scss:17-22`. **`docs/documentation-v2/01-current-system.md:210` ("A 28-row textarea") overstates the
current surface** and should be corrected: it is a two-row-default, 498px-wide textarea. This matters because the
baseline is worse than recorded, and because it proves `with_options` is not a styling API here.

**F2 — The Super Admin layout emits `vite_client_tag` twice** (layout:25 and `_navigation.html.erb:10`). Inert in
production and test (C8), but it injects `@vite/client` twice in development. `_navigation.html.erb:11` also places
a `type="module"` script and the entry's stylesheet `<link>` inside `<body>`, not `<head>`.

**F3 — The three documentation sidebar items render blank squares.** `_navigation.html.erb:21-23` maps
`portals → icon-book-line`, `categories → icon-folder-line`, `articles → icon-article-line`. None of those three
symbol ids exists in `_icons.html.erb`; the sprite has `icon-book-2-line` and `icon-folder-3-line` and no article
icon at all. `_nav_item.html.erb:4` renders `<use xlink:href="#<%= icon %>" />`, so an unknown id is an empty 16×16
box — exactly the failure the partial's own comment warns about at `_navigation.html.erb:66-67`.

**F4 — `_collection.html.erb` and `index.html.erb` are forks of an older Administrate.** `_collection` calls
`existing_action?`/`authorized_action?` instead of 0.20.1's `accessible_action?`, drops the per-attribute
`cell-label--resource_attr` class, and inlines the action-column header; `index.html.erb` bypasses
`_index_header` and `_pagination`. Both still resolve, but four gem partials
(`_index_header`, `_pagination`, `_collection_header_actions`, `_collection_item_actions`) are now dead on this
surface, and an Administrate upgrade that removes either deprecated predicate breaks every index page.

**F5 — `Administrate::Engine.javascripts` / `.stylesheets` are the sanctioned extension point and are unused.**
`engine.rb:32-38` exposes `add_javascript` / `add_stylesheet`; nothing in this repository calls them. Combined with
C2 they are not a usable path anyway — they only work for Sprockets logical paths.

**F6 — Administrate's free per-field hint mechanism is unused.** The gem's form partial renders
`administrate.field_hints.<resource>.<attribute>` when the key exists
(`vendor/.../administrate-0.20.1/app/views/administrate/application/_form.html.erb:46-51`). `grep -rn field_hints
config/locales/*.yml` returns nothing, and `en.yml` has no `administrate:` namespace at all. `ArticleMetaField`
hand-rolls its own hints in Ruby instead (`custom/app/fields/article_meta_field.rb:24-31`).

**F7 — Every Super Admin page depends on `SuperAdmin.first` existing.** `_javascript.html.erb:46-47` interpolates
`SuperAdmin.first.email` and `.name` with no guard. The content seeder has the same coupling
(`01-current-system.md:79`). On an install with no super admin row, every Super Admin page 500s in the layout.

**F8 — A rich editor on the article form increases the Ruby suite's dependency on a successful Vite build.**
Because `superadmin`/`superadmin_pages` are tagged in the layout chain (C3), any module the editor imports joins
the graph that every request spec rendering a Super Admin page must have built. A broken import inside the editor
fails **Ruby** specs, not just Vitest. This is the C8 failure mode, widened.

**F9 — `custom/app/views` is first in the view path, so the overlay can override any Administrate view without
touching `app/`.** `config/application.rb:48` unshifts it; Rails resolves prefix-outer, path-inner, so the
precedence for the article form is:
`custom/app/views/super_admin/articles/_form` → `app/views/super_admin/articles/_form` →
`custom/app/views/super_admin/application/_form` → `app/views/super_admin/application/_form` → the gem's.
For a field partial the leading slash in `to_partial_path` short-circuits prefixes entirely:
`custom/app/views/fields/<field_type>/_form` → `app/views/fields/<field_type>/_form` → the gems'.

---

## 4. Options — what it would take to put a rich editor on the article form

### 4.1 Where the editor attaches (three insertion points)

| Option | Mechanism | Cost | Reach |
|---|---|---|---|
| **A. New Administrate field class** | `ArticleContentField < Administrate::Field::Base` in `custom/app/fields/`, view at `custom/app/views/fields/article_content_field/_form.html.erb`, and `content: ArticleContentField` at `article_dashboard.rb:19` | smallest; the repo already does this twice (`ArticleMetaField`, `ArticleAuthorField`); forks no gem view; absolute partial path so nothing else is touched (F9) | the editor lives inside the ~498px, vertically-centred field unit (C5) |
| **B. Per-resource form override** | `custom/app/views/super_admin/articles/_form.html.erb` (the directory does not exist yet), optionally `new`/`edit` too, following `app/views/super_admin/accounts/edit.html.erb` | medium; takes ownership of the gem's form, so error rendering, fieldsets, nesting and the submit button become ours to maintain across gem bumps | full page width; side-by-side preview, EN/AR tabs, and reordering the field set all become possible |
| **C. Bespoke non-Administrate controller** | a hand-written `super_admin` controller + views, the pattern of `settings`, `operations`, `platform_support`, `instance_statuses` | largest; loses the index, search, `COLLECTION_FILTERS`, show page and the nav item for free, and must be added to the nav exclusion list (`_navigation.html.erb:47`) | total control |

**Recommendation: A for the editor itself, B only if side-by-side preview is a requirement.** A is strictly
cheaper, is the established pattern in this overlay, and keeps Administrate's index/filters/search/preview flow
intact — which matters because `publish`, `unpublish` and `preview` already work
(`custom/app/controllers/super_admin/articles_controller.rb:10-25`). C duplicates a working CRUD surface and should
be refused under the program's governing rule.

### 4.2 How its code reaches the page (this is the binding constraint)

1. **Not Sprockets.** C2: production serves only what is already in `public/assets`, `config.assets.compile = false`,
   and `deploy.sh` never precompiles. A new `app/assets/javascripts/editor.js` + `//= link` in `manifest.js` would
   404 on the live box. Rule: **nothing new goes through Sprockets** without first fixing the deploy pipeline — and
   that is Agent 097's territory, not the editor's.
2. **Vite, through an existing entrypoint.** Both `superadmin` and `superadmin_pages` are already tagged on every
   page (C3). Adding the editor to `app/javascript/superadmin_pages/` and registering it in the `ComponentMapping`
   at `superadmin_pages.js:8-11` costs **zero layout changes and zero new tags**. A new third entrypoint plus a
   `content_for :javascript` block (`_javascript.html.erb:14`) is also possible and would keep the editor out of
   the bundle on pages that do not need it — at the cost of a per-page tag and one more manifest entry every spec
   must build.
3. **The island must be summoned from ERB.** `render_vue_component('ArticleEditor', { content: …, locale: … })` in
   the field partial (A) or the form override (B). It is a `helper_method`
   (`application_controller.rb:14`), so it is callable from a field partial.
4. **One island only.** C6: `getElementById('app')` / `mount('#app')`. The article form has none today so one fits,
   but a preview pane must be *inside* the same component, not a second island — or `superadmin_pages.js:27-33`
   must change to `querySelectorAll` with a per-element mount, which is a shared-runtime change affecting the
   dashboard home page.
5. **Plugins the editor needs must be added to the island app.** `FullEditor.vue` needs a Vuex store with an
   `articles` module, `vue-i18n`, `useUISettings` and `useAlert` (C7). Either `superadmin_pages.js` grows those
   plugins — which pulls the tenant dashboard's store into the Super Admin bundle — or the ProseMirror core is
   extracted into a store-free, i18n-free component that takes its upload function and its labels as props. **The
   second is the right shape**: the dependencies are not the editor, they are the dashboard app around it.
6. **Markdown round-trip is already solved in-repo.** `@chatwoot/prosemirror-schema@1.4.5` is a direct dependency
   (`package.json:41`), with `prosemirror-model`/`prosemirror-view` pinned (`:147,173,177`), plus
   `markdown-it@^14.3.2` and `markdown-it-link-attributes` (`:88-89`), `dompurify@3.4.16` (`:77`),
   `vue-dompurify-html@^5.3.0` (`:105`) — already loaded on this surface
   (`superadmin_pages.js:2-3,23`) — and `highlight.js` (`:80`). **No new editor dependency is needed.** Any
   proposal to add Tiptap, Lexical, Quill, EasyMDE or Toast UI must first explain why
   `@chatwoot/prosemirror-schema` — the schema the product's own composer and tenant article editor use, and the one
   that already round-trips to the CommonMark the corpus and `ChatwootMarkdownRenderer` require — is insufficient.
   This is Agent 067's decision; the asset architecture pre-selects the answer.
7. **Styling.** Keep markup inside the `.vue` file (globbed at `tailwind.config.js:25`) so Tailwind sees it. If any
   markup must live in the ERB field partial under `custom/app/views`, either add
   `'./custom/app/views/**/*.erb'` to the content globs or accept inline styles as the rest of the overlay does
   (C4). Remember Tailwind preflight loads **after** Administrate's CSS (§1.6) and `.field-unit__field` caps width
   at ~498px (C5).
8. **Media needs a new endpoint, in the `super_admin` namespace.** C9: the existing upload route is unreachable.
   Two shapes:
   - **ActiveStorage through Administrate** — add an attachment to `Article` and a `Field::ActiveStorage` entry to
     `ArticleDashboard`, reusing the proven `User#avatar` wiring (C11, `user_dashboard.rb:14-18`). Gives upload,
     preview, destroy and optional `direct_upload:` with no new controller. But it is an attachment list beside the
     text, not insertion *into* the text, and the editor would still need a URL to write into the Markdown.
   - **A `super_admin` upload action** — e.g. `post :upload` on the articles resource in
     `config/routes/documentation.rb`, creating an `ActiveStorage::Blob` the way
     `Api::V1::Accounts::UploadController#create_and_save_blob` does
     (`app/controllers/api/v1/accounts/upload_controller.rb:39-45`), guarded by the surface's own
     `authenticate_super_admin!`. This is what an in-editor image button requires. Ownership, naming, validation
     and read-authorization of the resulting blob are Agents 066/083's to settle before it is built.
   `ActionText`/Trix is not an option: no table (C10) and it would introduce HTML as a second content format.
9. **Specs.** Whatever is built, every Ruby request spec that renders a Super Admin page will build the editor's
   import graph (C8, F8). The project's runbooks must set `VITE_RUBY_AUTO_BUILD=false` against a prebuilt manifest
   — which `docs/platform-support/13-integration-record.md:87-91` already establishes as the house rule — and the
   editor's imports must stay clean, because a bad import there turns into Ruby failures in unrelated suites.

### 4.3 What stays the same either way

`scoped_resource`, `new_resource`, `resource_params`/`normalized_meta`, `publish`, `unpublish` and `preview` all
keep working untouched (`custom/app/controllers/super_admin/articles_controller.rb:9-53`). `preview` is already a
real-layout, pre-publish preview and should be preserved rather than replaced by an in-editor render — it is the
only thing on this surface that exercises the actual public pipeline. `Article` already carries `draft_content`
and `draft_title` columns (`app/models/article.rb:8-9`) that Super Admin does not use and the tenant editor does
(`ArticleEditor.vue:44-56`) — a single draft slot, no revision history.

---

## 5. Risks

| Risk | Why it is real | Severity |
|---|---|---|
| **An editor module breaks Ruby specs.** Adding it to `superadmin*` puts it in the graph every Super Admin page render builds (C8, F8), and 24 examples have already failed this way | `docs/platform-support/13-integration-record.md:87-91` is the precedent, not a hypothesis | **high** |
| **Pulling the tenant dashboard's store/i18n into the Super Admin bundle to reuse `FullEditor.vue`** would couple the operator console to the tenant app's state shape and multiply the bundle every Super Admin page downloads | C7; the island is deliberately bare (`superadmin_pages.js:16-24`) | high |
| **Reaching for Sprockets.** It is the obvious home for an Administrate asset, and it is dead in production | C2 — `assets.compile = false`, no `assets:precompile` in `deploy.sh`, `public/assets/administrate*` gitignored | high |
| **Tailwind purge silently drops the editor's chrome** if any markup lands in `custom/app/views` | C4; measured — zero Tailwind utilities survive in that tree today | medium |
| **Layout collision.** Tailwind preflight loads after Administrate's CSS and `.field-unit` imposes flex/centre/498px | §1.6, C5 | medium |
| **A second island.** Preview-beside-text as its own component requires changing the shared mount code, which also governs the Super Admin home page | C6 | medium |
| **No authorization anywhere in Super Admin.** Every signed-in super admin can edit, publish and (once uploads exist) upload. An editor adds an upload surface to a console with exactly one guard | §1.7; `authorized_action?` returns `true` | medium — hand to Agents 082/086 |
| **The CSP is permissive today by deliberate omission.** An editor built on inline scripts/styles, `blob:` or `unsafe-eval` passes now and breaks at stage two | C12 | medium |
| **Administrate upgrade.** Two forked views already use predicates 0.20.1 only keeps as compatibility helpers; a per-resource `_form` override (option B) adds a third fork of a gem view | F4 | low now, rises with B |
| **`SuperAdmin.first` in the layout** will 500 every Super Admin page on an install without one, including any new editor | F7 | low |
| **Blank sidebar icons** for all three documentation resources, shipped and unnoticed | F3 | low (cosmetic, trivially fixable, but it is on the authoring surface) |

### Not checked

- Whether the live production box's `public/assets` actually contains current Administrate output, or output from
  an older SCSS revision. Determining that needs server access, which this phase does not have. The *mechanism*
  in C2 is proven from the repository; the deployed state is not.
- Browser behaviour of the article form (actual rendered textarea height, Tailwind/Administrate conflicts). No
  browser was driven; F1 is from the partial, the SCSS and the absence of any override.
- `administrate-field-belongs_to_search` is declared and has one overridden view
  (`app/views/fields/belongs_to_search/_index.html.erb`) but I found no dashboard using the field type; not
  pursued, as it does not bear on the article form.
