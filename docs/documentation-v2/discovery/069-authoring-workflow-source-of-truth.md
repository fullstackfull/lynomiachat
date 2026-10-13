---
agent: 069
scope: Authoring workflow — draft, publish, preview, validation, dirty state — and the file-vs-database collision at the centre of it
confidence: high
---

Read first-hand against `claude/documentation-v2`. Every claim below carries a `file:line`. Where I could not verify
something without running code, it is marked **unverified** and I say what would be needed.

The brief asked me to verify `content_seeder.rb:94-104` line by line. I did, and the lines say slightly less than
§3 of `01-current-system.md` claims and slightly more than the seeder's own header admits. Both corrections are in
§3.1 and §3.3.

---

## 1. What exists today

### 1.1 The three workflow actions

`custom/app/controllers/super_admin/articles_controller.rb` is 54 lines and carries three non-Administrate actions:

| Action | Code | Route |
|---|---|---|
| `publish` | `requested_resource.update!(status: :published)` then redirect with `I18n.t('documentation.super_admin.published')` (`articles_controller.rb:10-13`) | `post :publish` (`config/routes/documentation.rb:13-17`) |
| `unpublish` | `requested_resource.update!(status: :draft)` then redirect with `…unpublished` (`articles_controller.rb:15-18`) | `post :unpublish` |
| `preview` | `redirect_to "/hc/#{article.portal.slug}/articles/#{article.slug}?show_plain_layout=true"` (`articles_controller.rb:22-25`) | `get :preview` |

The notices exist: `config/locales/en.yml:77-80` carries `documentation.not_set_up`,
`documentation.super_admin.published` and `documentation.super_admin.unpublished`.

Preview works because the public article lookup is deliberately widened for a signed-in super admin —
`scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published`
(`app/controllers/public/api/v1/portals/articles_controller.rb:80-88`) — and the page then renders a banner so a
draft cannot be mistaken for the live page (`app/views/public/api/v1/portals/articles/_draft_banner.html.erb:3-7`,
rendered by all three show variants including `show.html+documentation.erb:6`). That part of the workflow is sound
and is the one piece of it that was designed rather than inherited.

**No view in the repository links to any of the three actions.** `grep -rn 'publish\|preview'` over
`app/views/super_admin` and `custom/app/views/super_admin` returns nothing, and
`grep -rn 'publish_super_admin\|unpublish_super_admin\|preview_super_admin'` over every `.erb` and `.rb` in the
repository (excluding `node_modules` and `vendor/bundle`) returns nothing. There is no
`app/views/super_admin/articles/` directory and no `custom/app/views/super_admin/articles/` directory. The one show
template every Administrate resource in this install renders, `app/views/super_admin/application/show.html.erb:26-40`,
emits exactly two buttons: **Edit** and **Destroy**. The actions are exercised only by raw path in
`spec/requests/documentation/global_ownership_spec.rb:97-99`.

So the publish/unpublish/preview workflow that `docs/global-documentation/07-super-admin-management.md:67-77`
describes as a table of four steps is, in the browser, one GET an operator can type by hand (`preview`) and two
POSTs with no form and therefore no CSRF token — effectively unreachable. The working publish control is the
`status` dropdown on the edit form (`custom/app/dashboards/article_dashboard.rb:21,36`), which is a different thing:
it is a field inside an all-or-nothing save, not an action.

### 1.2 Administrate's form save

`ArticleDashboard::FORM_ATTRIBUTES` is `portal category title slug description content locale status position meta`
(`article_dashboard.rb:36`). `content` is `Field::Text.with_options(rows: 28)` (`article_dashboard.rb:19`) — a
textarea. `status` is `Field::Select` over `Article.statuses.keys` (`article_dashboard.rb:21`), which is
`draft published archived` (`app/models/article.rb:75`), so **archived is already reachable from the form**.

The save path is the gem's, unmodified: `update` calls `requested_resource.update(resource_params)`
(`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:60-70`),
and `resource_params` is
`params.require(param_key).permit(dashboard.permitted_attributes(action_name)).transform_values { read_param_value(v) }`
(`…/application_controller.rb:203-224`). `read_param_value` recurses into nested `Parameters` and turns a blank
string into `nil`.

`SuperAdmin::ArticlesController#resource_params` then post-processes only `meta`
(`articles_controller.rb:39-53`): `meta.to_h.compact_blank`, with `tags` split on commas. `meta` is a jsonb column,
so this is a **whole-value replacement**, not a merge.

What the form actually posts into `meta` is fixed by `ArticleMetaField`: `STRING_KEYS` =
`title description version release_date feature_image`, plus `tags`
(`custom/app/fields/article_meta_field.rb:11-13,33-35`), and the form view emits exactly those inputs
(`custom/app/views/fields/article_meta_field/_form.html.erb:5-21`). **`doc_key` is not among them, is not rendered
on the show page either** (`ArticleMetaField#to_s` iterates `LABELS.keys`, `article_meta_field.rb:49-54`), and is
therefore invisible to the operator who is about to destroy it. See §3.3.

Validation feedback on save is the gem's top-of-form list of `resource.errors.full_messages`
(`…/app/views/administrate/application/_form.html.erb:18-34`), rendered with `status: :unprocessable_entity`.
Administrate 0.20.1 renders **no per-field errors** — `grep -rln errors` over the gem's `app/views/fields/`
returns nothing. Required-ness is a CSS class only (`_form.html.erb:43`,
`…/app/helpers/administrate/application_helper.rb:15-17`).

### 1.3 `Documentation::ContentSeeder`, lines 94-104, read line by line

```ruby
94  def attributes_for(front_matter, body, category, key)
95    {
96      title: front_matter.fetch('title'),
97      description: front_matter['description'],
98      content: body,
99      category: category,
100     position: front_matter.fetch('position'),
101     status: @publish ? :published : :draft,
102     meta: meta_for(front_matter, key)
103   }
104 end
```

Seven keys. Six are read from the file or derived from it; `status` (line 101) is read from the **constructor flag**,
not from the file. `@publish` defaults to `true` (`content_seeder.rb:20,23`) and `rails documentation:content`
passes nothing (`lib/tasks/documentation.rake:18`), so in every operator-run invocation line 101 resolves to
`:published` for every article in the corpus, unconditionally, on every run. The front matter has no `status` key
and no article can opt out: the only override is `ContentSeeder.new(publish: false)`, which flips **all** of them to
draft (asserted at `spec/custom/services/documentation/content_seeder_spec.rb:133-137`).

`meta_for` (`content_seeder.rb:106-113`) builds `{'doc_key', 'title', 'description', 'tags', 'version',
'release_date'}.compact`. It does **not** emit `feature_image`, which the form does offer
(`article_meta_field.rb:13`), so a feature image an operator sets is destroyed by the next run along with
everything else in `meta`.

These seven keys are applied by `article.assign_attributes(attributes_for(...))` at `content_seeder.rb:76`, onto a
row found by `portal.articles.find_or_initialize_by(slug: slug_for(key, locale), locale: locale)`
(`content_seeder.rb:73`). **`slug` and `locale` are the lookup key, so they are the two form fields the seeder never
writes** — which is the opposite of harmless (§3.2). `associated_article_id` is written for every non-default locale
(`content_seeder.rb:77`). `author` is written **only when nil** (`content_seeder.rb:79`: `article.author ||= author`),
so an author survives. `views`, `draft_title`, `draft_content`, `folder_id` and `created_at` are never touched.

Two structural properties, both confirmed by reading the whole file:

- **Nothing is ever deleted.** `perform!` iterates `manifest['sections']` and `Dir.glob`s files
  (`content_seeder.rb:28-29,47-56`). There is no `destroy`, no `where.not(...)`, no reconciliation against the set of
  files. A removed or renamed `.md` leaves its article live and published.
- **No transaction.** The only writes are `category.save!` (`:62`) and `article.save!` (`:80`), per record. The string
  `transaction` does not appear in the file. A raise at article 57 of 126 — and the seeder raises readily, on missing
  front matter (`:128`) and on missing `title` (`:96`, a `KeyError`, asserted at `content_seeder_spec.rb:147-151`) —
  leaves a half-updated corpus with nothing to undo it.

---

## 2. Constraints the existing system imposes

An authoring upgrade must not break any of these. Each is load-bearing somewhere else.

| Constraint | Evidence | Why it binds |
|---|---|---|
| The file name is the stable key; the slug is derived from it (`key`, `key-ar`) | `content_seeder.rb:66-73,85-87`; `content_seeder_spec.rb:92-94` | the slug is the public address and the fallback resolver |
| `meta['doc_key']` is the product↔corpus contract | `library.rb:54-57`; `content_seeder.rb:107` | 87 `DOC_ARTICLES` keys resolve through it |
| `articles.slug` is globally unique | `app/models/article.rb:32` | EN and AR cannot share a slug; hence the `-ar` suffix |
| English must seed before any other locale | `content_seeder.rb:42-45,77,90-92` | otherwise `associated_article_id` is nil |
| Platform portals carry `account_id = NULL` | `library.rb:5-6`; `app/models/article.rb:51-53,230-232` | tenant isolation depends on it |
| `locale` is derived from the category, not chosen | `app/models/article.rb:200-206` | an operator's `locale` edit is overridden by the model before validation |
| Only a published article is public and only a published article resolves by key | `library.rb:42-44`; `public/.../articles_controller.rb:13,81` | unpublishing an article 404s every in-product link to it (`documentation_controller.rb:22-23`) |
| Preview depends on the super-admin session widening the public scope | `public/.../articles_controller.rb:80-88` | any new preview surface should reuse this, not a second renderer |
| `content` is required when published | `app/models/article.rb:68` | publish can fail validation; the form must say so |
| `author_id` and `title` are required | `app/models/article.rb:66-67` | a new article needs an author; `new_resource` supplies it (`articles_controller.rb:35-37`) |
| **`Article` has no revision history** | absent from `custom/app/models/custom/audit/` (14 capture points, no `article.rb`); stated at `docs/global-documentation/05-lynomia-capability-doc-map.md:79` (*"THERE IS NO REVISION HISTORY"*) | an overwritten article cannot be recovered. This is the single fact that makes every "silently overwrite" finding below unrecoverable rather than merely annoying |
| The SEO audit exits 1 on an error | `lib/tasks/documentation_seo_audit.rake:9-10` | anything that creates a duplicate canonical is a release blocker by construction |
| A single-slot draft buffer already exists on the model | `app/models/article.rb:8-9`; migration `db/migrate/20260623000000_add_draft_columns_to_articles.rb` | the thing to extend for dirty state and live preview (§3.7) |

---

## 3. Findings

Severity is `blocker` (reachable today, loses or corrupts content or breaks a public address), `major`, `minor`.

### 3.1 What happens to an operator's edit when the next sync runs

Field by field, for an article that came from a file:

| Field | Form writes it | Seeder writes it | Outcome of the next `rails documentation:content` |
|---|---|---|---|
| `title` | yes (`article_dashboard.rb:36`) | yes (`content_seeder.rb:96`) | reverted to the file |
| `description` | yes | yes (`:97`) | reverted |
| `content` | yes | yes (`:98`) | reverted |
| `category` | yes | yes (`:99`) | reverted |
| `position` | yes | yes (`:100`) | reverted — but see 3.6 |
| `status` | yes | **forced** (`:101`) | forced to `published`, whatever the operator chose, including `archived` |
| `meta` (all keys) | yes, replacing the jsonb | yes, replacing the jsonb (`:102,106-113`) | reverted; `feature_image` is destroyed, not reverted |
| `slug` | yes | **no** — it is the lookup key (`:73,85-87`) | **not reverted. A second article is created.** See 3.2 |
| `locale` | yes, but the model overrides it | **no** — it is the lookup key (`:73`) | the operator's choice never took effect (`app/models/article.rb:200-206`) |
| `author` | not on the form (`article_dashboard.rb:36`) | only when nil (`:79`) | preserved |
| `views` | no | no | preserved |
| `draft_title` / `draft_content` | no | no | preserved |
| `associated_article_id` | no | yes, non-default locales (`:77`) | reset to the English article's id |

So the plain answer to the brief's first question: **every edit an operator can usefully make through the form is
silently discarded on the next sync, except the one edit that is actively destructive.** The seeder's header is
honest about the intent — *"An operator's own edits in Super Admin are not protected from a re-run… The seeder says
what it changed so that is visible rather than silent"* (`content_seeder.rb:7-8`) — but the second half of that
sentence is not true in practice. `count` increments `updated` for any row whose attributes differ
(`content_seeder.rb:78,115-123`), and the task prints one aggregate line
(`lib/tasks/documentation.rake:19`). A reverted operator edit and a genuine corpus change are the same `+1`. The
operator sees `19 updated` and cannot tell whether that included their own work being undone, nor which rows.

**Severity: blocker**, because there is no revision history to recover from (§2).

### 3.2 Editing `slug` in Super Admin creates a duplicate article, not a renamed one

The sharpest collision in the system, and it is not in `01-current-system.md`.

`slug` is on the form (`article_dashboard.rb:36`). The seeder's upsert key is `(slug_for(key, locale), locale)`
(`content_seeder.rb:73`). An operator who renames `whatsapp-setup` to `whatsapp-setup-v2` therefore produces, on the
next run:

- a **new** article at slug `whatsapp-setup`, with the file's title, content, category, position, `status: published`
  and `meta['doc_key'] = 'whatsapp-setup'`;
- the operator's row still live at `whatsapp-setup-v2`, still `published`, still carrying `meta['doc_key'] =
  'whatsapp-setup'` if it survived the save (it does not — §3.3), and now unreachable from the corpus forever,
  because no file will ever match it again.

Two published articles then claim the same `doc_key`. `Library.article_for` resolves with
`by_key.find_by(locale:) || by_key.find_by(locale: DEFAULT_LOCALE) || by_key.first || article(key)`
(`library.rb:54-57`) — `find_by` with no order is arbitrary, so which article a product help link opens is
undefined. Changing `category` to a category in the other locale has the same shape of effect via
`app/models/article.rb:200-206`, since `locale` is part of the key too.

The SEO audit will **not** catch this: it groups by `portal_canonical_url` and the two rows have different slugs, so
the canonical check at `documentation_seo_audit.rake:52-59` passes. Nothing in the repository compares the set of
articles against the set of files — `spec/custom/services/documentation/content_seeder_corpus_spec.rb` checks
file-side invariants only (parity, cross-references, front matter, placement).

**Severity: blocker.**

### 3.3 Any Super Admin save of a seeded article destroys `meta['doc_key']`

`resource_params` replaces the whole jsonb with `normalized_meta(permitted[:meta])`
(`articles_controller.rb:39-52`), and the submitted hash can only ever contain
`title description version release_date feature_image tags` (`article_meta_field.rb:13,33-35`;
`_form.html.erb:5-21`). `doc_key` is not posted, so it is not in the hash, so it is gone. There is no merge in the
controller and none in the model.

Consequence, until the next seeder run restores it:

- An English article still resolves, by accident, through the final fallback `|| article(key)` (`library.rb:56`),
  because for the default locale `slug == key` (`content_seeder.rb:85-87`).
- An **Arabic** reader does not. `by_key` is empty, so the chain falls through to `article(key)` and returns the
  **English** article. Every Arabic contextual-help link to that article silently serves English.
- If the operator also changed the slug (§3.2), `article_for` returns nil and `/docs/:slug` responds `404`
  (`documentation_controller.rb:22-23`), breaking the in-product link outright.

The operator gets no warning, because `doc_key` appears on neither the form nor the show page
(`article_meta_field.rb:15-22,49-54`). Fixing a typo in a title is enough to trigger it.

**Severity: blocker.** It is also the reason `meta` is the wrong home for a provenance or detachment marker (§4.3).

### 3.4 An operator-authored article can never carry a `doc_key`, and is otherwise safe

A never-seeded article behaves well with respect to the seeder: no file produces its `(slug, locale)` pair, so
`find_or_initialize_by` never finds it and no run touches it. Its `author` is the acting super admin
(`articles_controller.rb:35-37`), not `SuperAdmin.first`.

But it cannot be wired into the product. `meta['doc_key']` has no form field, so a hand-authored article is reachable
only by the literal-slug fallback (`library.rb:56`) — which means its slug must *be* the registry key, and a key
whose slug is not suffixed cannot have an Arabic sibling under the `-ar` convention. In practice an
operator-authored article can be linked from `DOC_ARTICLES` in English only, and only if whoever chose the slug knew
that the slug is doing double duty as the key. Its category must be one of the seeded categories
(`article_dashboard.rb:15`), whose name, description, position and icon the seeder overwrites on every run
(`content_seeder.rb:58-64`).

**Severity: major** (a capability gap, not a data loss).

### 3.5 Retirement: there is no working path

The seeder deletes nothing (§1.3), so the brief's question is the right one. The four candidate paths:

| Path | What happens | Verdict |
|---|---|---|
| Delete the `.md` file | nothing. The article stays `published`, stays in the portal index (`public/.../articles_controller.rb:13`), stays in the sitemap, stays resolvable by key. It is now unreachable from source control and will never be updated again | **does not retire anything** |
| Set `status: archived` on the form | works *immediately and correctly*: `Library.articles` is `published`-scoped (`library.rb:42-44`), the public lookup is `published`-scoped (`public/.../articles_controller.rb:81`), the SEO audit scopes `status: :published` (`documentation_seo_audit.rake:45`). Then `content_seeder.rb:101` forces it back to `published` on the next run | **undone by the next sync** |
| `unpublish` action | identical, via `status: :draft` (`articles_controller.rb:15-18`) — and unreachable from any view (§1.1) | **undone by the next sync** |
| Administrate **Destroy** (`show.html.erb:33-39`, route `resources :articles`) | hard-deletes the row. The next run recreates it from the file with a **new id**, `views` reset, `author` reset to `SuperAdmin.first` and a new `created_at`; `associated_article_id` on the Arabic sibling was nullified by `dependent: :nullify` (`app/models/article.rb:40-44`) and is repaired only if the sibling is also re-seeded in the same run | **destructive and futile** |

So today an article is retired by being retired twice: once in Super Admin and once again after every deploy. The
good news is that the mechanism already exists and needs no migration — `archived` is in the enum
(`app/models/article.rb:75`) and all three read paths already exclude it. What is missing is a way for the **file**
to say so, and a seeder that respects it.

**Severity: blocker** for a corpus that is about to grow several times over (charter §9), because the first thing a
growing corpus does is make mistakes that need withdrawing.

### 3.6 The seeder is not convergent in a single run when an article changes section

New finding, and it bears directly on whether the sync can ever gate a deploy.

`Article` has `after_save :category_id_changed_action, if: :saved_change_to_category_id?`
(`app/models/article.rb:73`). For an **existing** row whose `category_id` the seeder changed — i.e. an article whose
`.md` moved between sections — the early return at `app/models/article.rb:195` does not fire
(`created_at_before_last_save` is not nil), so `update_article_position_in_category` runs and does
`update_column(:position, max_position + 10)` (`app/models/article.rb:215-228`). That silently discards the
`position` the seeder just read from the front matter at `content_seeder.rb:100`.

On **creation** the early return does fire (`created_at_before_last_save` is nil, `position` is present,
`category_id_before_last_save` is nil), so a first seed preserves the file's positions. The defect is specific to a
section move, and it self-heals on the *second* consecutive run, because by then `category_id` is unchanged and no
callback fires.

Two consequences: a corpus reorganisation ships with wrong ordering until someone runs the task twice; and
`rails documentation:content` cannot be described as idempotent-in-one-run, which is the property
`content_seeder_spec.rb:55-64` asserts and calls *"the property that makes it safe to run on every deploy."* The
spec does not cover a section move, so it passes.

**Severity: major.** Unverified detail: I did not run it, so the exact resulting position value is inferred from the
callback chain, not measured. Reproducing it needs a seed, a file move between sections, and a second seed.

### 3.7 Provenance: what a reader of the database can actually learn

The brief asks what tells a reader whether a row came from a file or a human. The honest answer is **nothing
reliable**. The full inventory of signals on `articles`:

| Signal | What it would tell you | Why it does not |
|---|---|---|
| `meta->>'doc_key'` | present ⇒ a file wrote this row at some point (`content_seeder.rb:107`) | destroyed by any Super Admin save (§3.3), so absence proves nothing. Cannot distinguish "seeded, untouched" from "seeded, edited, re-seeded" |
| `author_id` | `SuperAdmin.first` for seeded (`content_seeder.rb:22`) vs `current_super_admin` for hand-created (`articles_controller.rb:36`) | on a single-super-admin install these are the same row. And `author ||=` (`:79`) means the value is whatever it was first, not who wrote last |
| `updated_at` | when it last changed | bumped by both writers indistinguishably. An unchanged seeder pass does not bump it, which is the only (weak) inference available |
| `created_at` | — | both writers create rows |
| `status` | — | forced by one writer (`:101`) |
| audit trail | who changed what, when | **`Article` is not audited.** `custom/app/models/custom/audit/` has 14 capture points and no `article.rb`; `audited` is in the Gemfile at `Gemfile:184` and used widely elsewhere |

There is no `source`, `provenance`, `managed_by`, `origin` or `file_path` column or `meta` key anywhere in the
repository. A reader looking at a row in production cannot tell whether its `content` is the Markdown in
`custom/db/documentation/` or something a human typed. Nor can the seeder, which is exactly why it overwrites
everything.

**Severity: blocker for the Phase 4 decision.** Whatever source-of-truth option is chosen, it needs a marker, and
the marker has to be visible to the seeder, to the form, to Super Admin's UI and to SQL.

### 3.8 The ordinary authoring needs

| Need | State | Evidence |
|---|---|---|
| Title | **exists** | `article_dashboard.rb:16,36` |
| Slug | **exists — and editing it is destructive** | `article_dashboard.rb:17,36`; §3.2 |
| Section (category) | **exists**, scoped to platform portals | `article_dashboard.rb:15,36` |
| Locale | **field exists, has no effect** — the model derives it from the category | `article_dashboard.rb:20,36`; `app/models/article.rb:200-206` |
| Summary (`description`) | **exists** | `article_dashboard.rb:18,36` |
| SEO title / description / tags | **exists**, as named fields with hints | `article_meta_field.rb:11-31`; `_form.html.erb:5-21`. Validation of them is agent 070's |
| Draft vs published | **exists** as a form field, 3 states including `archived` | `article_dashboard.rb:21`; `app/models/article.rb:75` |
| Publish / unpublish as actions | **backend exists, no UI entry point** | `articles_controller.rb:10-18`; §1.1 |
| Preview | **backend exists, no UI entry point**; GET, so URL-reachable by hand | `articles_controller.rb:22-25`; §1.1 |
| Draft preview is not public | **exists, and is good** | `public/.../articles_controller.rb:80-88`; `_draft_banner.html.erb:3-7` |
| Live / side-by-side preview | **absent** | the form is the gem's `_form.html.erb`; no JS beyond Administrate's own (`app/views/super_admin/application/_javascript.html.erb:10-14`) |
| RTL preview | **absent, and worse than absent** — the portal layouts set `lang` but never `dir`: `<html lang="<%= html_lang_attribute(I18n.locale) %>">` (`app/views/layouts/portal.html+documentation.erb:2`, same at `portal.html+plain.erb:2`), and `html_lang_attribute` only transliterates underscores (`app/helpers/portal_helper.rb:40-42`). The sidebar uses `rtl:` Tailwind variants (`documentation_layout/_sidebar.html.erb:15`) which never activate without `dir` | so an Arabic article previews — and publishes — LTR. Shared with agent 072 |
| Dirty-state protection | **absent in Super Admin.** No `beforeunload` handler exists outside `useCallSession.js:63` and `FlowBuilder.vue:300` | `app/javascript/` grep |
| Autosave / draft buffer | **columns exist, unwired here.** `draft_title`/`draft_content` are not in `FORM_ATTRIBUTES` and the seeder never touches them, so they already survive a sync | `app/models/article.rb:8-9`; `article_dashboard.rb:36` |
| Save validation feedback | **exists, minimally**: a top-of-form list of `full_messages`, 422, no per-field errors | `…/administrate/application/_form.html.erb:18-34` |
| Required-field marking | **exists** as a CSS class only | `_form.html.erb:43`; `application_helper.rb:15-17` |
| Revision history / restore | **absent** | §3.7 |
| Media insertion, alt text | **absent** (agent 068's scope) | `01-current-system.md:§6` |

The one thing worth saying loudly: **a full editor-grade dirty-state and live-preview story already exists in this
codebase**, in the tenant Help Center — `PortalsArticlesEditPage.vue:55-110` stages edits into
`draft_title`/`draft_content`, clears the buffer when the staged version renders identically to the live one, and
drives a "pending changes" badge; the API writes drafts with `update_columns` precisely so a draft autosave does not
bump the public `updated_at` (`app/controllers/api/v1/accounts/articles_controller.rb:92-105`). Extending that to
Super Admin is strictly cheaper than inventing dirty-state handling, and it is the charter's EXTEND rule applied
literally.

---

## 4. Options

### 4.1 Should a seeded article be editable at all?

| Option | What it means | Cost | Verdict |
|---|---|---|---|
| **Read-only** | the form is unavailable for any row a file owns; Super Admin shows it, Preview works, Publish does not | no data can ever be lost; every change goes through review; but an urgent factual correction needs a deploy, and §3.6 means a deploy does not even reliably sync | **too rigid.** The production fact in charter §4 is that the deploy does *not* sync content; read-only plus a non-syncing deploy means the corpus cannot be corrected at all |
| **Editable (today)** | what exists | zero | **unacceptable.** §3.1-3.3: two writers, no provenance, no history, no warning, no recovery. The charter forbids it in §8.1: *"Two writers that overwrite each other are forbidden"* |
| **Editable-with-detachment** | editing is allowed; the first operator edit marks the row as no longer file-owned; the seeder then reports that row instead of overwriting it | one column, one merge fix in `resource_params`, one branch in the seeder, one Super Admin banner | **recommended** |

### 4.2 Source of truth: A, B, C

**Option A — repository Markdown canonical.**
*Who writes what*: files only. Super Admin becomes read-only for file-owned rows: `FORM_ATTRIBUTES` drops to
nothing for them, `publish`/`unpublish` are removed for them, `preview` stays, `destroy` is removed.
*Deploy*: must run `documentation:content`, gated and transactional, or the corpus is frozen at whatever the last
hand-run left. §3.6 must be fixed first.
*Operator loses*: the ability to fix anything without a PR and a deploy — including taking down a wrong article.
*Provenance*: trivially complete; the file path is the record. Still needs a marker to distinguish file-owned rows
from the operator-authored ones that would have to be grandfathered or forbidden.
*Conflict*: impossible by construction.
*Rollback*: `git revert` the corpus commit and re-run. Clean, and the best rollback story of the three.
*Silent overwrite risk*: the seeder over the database, which is intended — but §3.2 still applies if `slug` stays on
any form, and §3.5 still applies: deleting a file retires nothing. A needs a retirement mechanism in the file
format regardless.

**Option B — database canonical.**
*Who writes what*: Super Admin only. The corpus becomes a one-time import; `rails documentation:content` is
retired, or reduced to a `--seed-only-if-absent` mode like `PortalSeeder`'s treatment of
`DOCUMENTATION_URL` (`portal_seeder.rb:39-47`).
*Deploy*: does nothing to content. The charter §4 production problem disappears by making the pipeline irrelevant.
*Operator loses*: nothing. Reviewers and the authors of the 126 Markdown files lose everything: no diff, no PR, no
review, no `grep`, no cross-reference spec (`content_seeder_corpus_spec.rb` becomes dead), no EN/AR parity check.
*Provenance*: must be built from scratch — `Article` is not audited (§3.7), so B's first requirement is auditing
`Article`, which the prior design record explicitly deferred
(`docs/global-documentation/10-global-docs-implementation.md:120`, *"A revision history with restore… Deferred"*).
*Conflict*: none between writers; between two super admins, last-write-wins with no history. There is one
undifferentiated super-admin role (`docs/global-documentation/07-super-admin-management.md:18-19`).
*Rollback*: a full database restore (deploy stage 2), which loses everything else written since.
*Silent overwrite risk*: one super admin over another, undetectably.
*Verdict*: it throws away the review discipline that is the corpus's main quality control, at exactly the moment the
corpus is about to multiply. It is also the one option that makes the textarea the permanent authoring surface for
all 126+ articles.

**Option C — controlled hybrid with explicit ownership.**
*Who writes what*: every article row has exactly one declared owner. `file`-owned rows are written by the seeder and
are read-only in Super Admin except for `status`-as-an-action and a deliberate **detach**. `operator`-owned rows
(hand-authored, or detached) are written only by Super Admin and are never touched by the seeder, which reports
them.
*Deploy*: runs the sync, which now has three outcomes per row — written, unchanged, or **skipped because detached**
— and a non-zero exit or a loud report when the skipped set is non-empty, so a detachment is a thing someone must
resolve rather than a thing that rots.
*Operator loses*: the ability to edit a file-owned article casually. They gain the ability to edit one
*deliberately*, with the consequence stated on screen.
*Provenance*: a column (§4.3), readable in SQL, on the show page, and by the seeder.
*Conflict*: made impossible per row, and made **visible** at the corpus level: the sync's report is the conflict
list.
*Rollback*: for a file-owned row, `git revert` + re-run, same as A. For a detached row, rollback requires an audit
trail — so detachment must come with `audited` on `Article`, or detachment is permitted only with a matching
corpus change. That is C's real cost, and it is a cost A also pays for operator-authored rows.
*Silent overwrite risk*: reduced to one case — an operator detaches, someone later resolves the detachment by
re-pointing the row at the file, and that resolution overwrites. Which is fine, because resolving is an explicit act.

### 4.3 If an article detaches, what marks it and where

The marker must survive **both** existing writers. `meta` cannot do that: the seeder replaces the whole jsonb
(`content_seeder.rb:102`) and so does the form (`articles_controller.rb:41`). A `meta` key would be destroyed by
whichever writer ran last — which is precisely the §3.3 bug, and reusing the mechanism that has the bug is not a
design. The charter's §8.1 "explicit ownership, version and provenance" cannot live in `meta` as `meta` is written
today.

So: **a column on `articles`.** This is an extension of the existing content model, not a new table — the charter's
EXTEND rule (§2) prohibits a `documents` table, not a column, and the precedent is three commits old
(`db/migrate/20260623000000_add_draft_columns_to_articles.rb` added `draft_title`/`draft_content` for exactly this
kind of reason).

Concretely:

- `articles.doc_source` — string, nullable. `'file'` for anything the seeder owns; `'operator'` for a hand-authored
  article; `'detached'` for a row that was file-owned and has been deliberately edited. NULL for every tenant Help
  Center article in the installation, which is correct: this is a platform-documentation concern and tenant rows must
  keep behaving exactly as they do now.
- `articles.doc_detached_at` — datetime, nullable. Set when the transition to `'detached'` happens. Gives the sync
  report something to sort by and an operator something to answer for.
- The seeder sets `doc_source: 'file'` in `attributes_for` for every row it writes, and **skips** any row already
  `'detached'` or `'operator'`, counting it into a fourth `Result` member. `rails documentation:content` prints the
  skipped keys, not just a number.
- `SuperAdmin::ArticlesController#new_resource` sets `doc_source: 'operator'` (`articles_controller.rb:35-37` is
  already the right place).
- `doc_source` and `doc_detached_at` stay out of `FORM_ATTRIBUTES` so no form post can forge them, and go into
  `SHOW_PAGE_ATTRIBUTES` and `COLLECTION_ATTRIBUTES` so an operator can see and filter them
  (`article_dashboard.rb:30,32-34,36`). A `COLLECTION_FILTERS` entry for `detached` (`article_dashboard.rb:38-42`)
  is one line.

**What the seeder then does with the file**: nothing to the row, and it must not pretend the file does not exist.
It reports `detached: <key> (<locale>) — file not applied, detached <timestamp>` per row, and exits non-zero when
the set is non-empty if the sync runs as a deploy gate. The file remains the reviewed record of what the article
*should* say; the divergence is a work item, not a silent state. Resolving it is either "update the file to match
the row and re-attach" or "discard the row's edit and re-attach" — both of which are a deliberate operator action,
and the second one is the one that needs the audit trail.

Three small, cited fixes are prerequisites and are worth separating from the column, because each closes a blocker on
its own:

1. **Merge `meta` instead of replacing it** in `articles_controller.rb:39-52`, so `doc_key` and any future key
   survive a save. `update` has `requested_resource` to merge onto; `create` does not, which is fine because a new
   row has no `doc_key` to preserve. This closes §3.3.
2. **Remove `slug` and `locale` from `FORM_ATTRIBUTES`** (`article_dashboard.rb:36`) for a file-owned row. `locale`
   has no effect anyway (`app/models/article.rb:200-206`) and `slug` is the one edit that forks the corpus. This
   closes §3.2.
3. **Stop forcing `status` unconditionally** (`content_seeder.rb:101`): honour a front-matter key for intended state
   and leave a detached row's status alone. This closes §3.1's worst case and is the precondition for retirement.

### 4.4 Retirement

Retirement belongs in the file, because the file is the reviewed record and because deleting a file must not be the
mechanism (§3.5). The smallest thing that works:

- A `retired: true` front-matter key. `attributes_for` maps it to `status: :archived` instead of `:published`
  (`content_seeder.rb:101`). No migration, no new state: `archived` is already in the enum
  (`app/models/article.rb:75`) and all three read paths — `Library.articles` (`library.rb:42-44`), the public lookup
  (`public/.../articles_controller.rb:81`) and the SEO audit (`documentation_seo_audit.rake:45`) — already exclude
  it. The article drops out of `/docs`, the portal index, the sitemap and the audit the moment the sync runs.
- The file **stays**, which keeps `content_seeder_corpus_spec.rb`'s cross-reference and parity checks meaningful and
  gives agent 079's redirect work a row to redirect *from*.
- `DOC_ARTICLES` must then not point at a retired key. That is a check worth adding, and it does not exist today:
  nothing in the repository asserts that every one of the 87 registry keys resolves to a published article.
- Deleting a file should become a **failure**, not a silent orphan: a reconciliation step that lists published
  `doc_source: 'file'` rows with no corresponding file, and reports them. That is the missing half of "the seeder
  deletes nothing" — not deletion, but *detection*.

### 4.5 Recommendation

**Option C, with files canonical by default.** In one sentence: *the corpus is the source of truth; the database is
a rendering of it; and any row that stops being a rendering has to say so, in a column, and be listed every time the
sync runs.*

Why not A: the charter's own §4 production fact is that the deploy does not sync content, and §3.6 shows the sync is
not even single-run convergent. Making the database read-only while the only write path is unreliable means the
documentation cannot be corrected at all — including taking down something wrong. A is the right destination once the
deploy lifecycle is fixed, and C is A plus a safety valve; a detachment count of zero *is* A.

Why not B: it discards the review discipline, the diffability, the EN/AR parity spec and the cross-reference spec —
the only quality controls the corpus has — right before the corpus multiplies, and its first prerequisite
(auditing `Article`) is a prerequisite of C's detachment path anyway.

**What makes it safe:**

1. **One writer per row, declared in a column**, not inferred. The question "who owns this row" has a SQL answer
   (§4.3). Today it has none (§3.7).
2. **No silent revert.** The seeder either writes a row it owns or reports a row it does not. The failure mode
   becomes a report line, which is reviewable, instead of a diff nobody saw.
3. **The destructive edits are removed rather than guarded.** `slug` off the form closes §3.2 at the entry point;
   merging `meta` closes §3.3 at the entry point. Both are at the controller/dashboard boundary — the earliest
   shared entry point — not scattered as downstream guards.
4. **Retirement uses a state that already works** (`archived`) and a record that already exists (the file), so there
   is no new mechanism to get wrong, and no `DELETE` anywhere near the corpus.
5. **Rollback is `git revert` + re-run** for every row the seeder owns, which is every row until someone deliberately
   detaches one — and `audited` on `Article` is the stated price of allowing that, rather than something discovered
   after the first unrecoverable overwrite.
6. **Convergence in one run** (§3.6 fixed) is what lets the sync become a deploy gate at all. Without it, Phase 4's
   deployment-lifecycle decision has no safe shape, whichever source of truth is chosen.

The authoring-experience work then stands on top of this rather than fighting it: Preview and the draft banner are
already right and should be *linked* (§1.1); dirty state and live preview extend the tenant editor's existing
`draft_title`/`draft_content` staging, which the seeder already leaves alone (§3.8); and `dir="rtl"` on the portal
layout is the one-line precondition for RTL preview being honest.

---

## 5. Risks

| Risk | Why it is real | What reduces it |
|---|---|---|
| A detachment column becomes a place where divergence accumulates quietly | the whole point of the column is to permit divergence. If the sync's report is a line of stdout nobody reads, C degrades into B with extra steps | the sync must exit non-zero on a non-empty detached set when it runs as a gate, and `detached` must be a `COLLECTION_FILTER` an operator sees on the index |
| Detachment without an audit trail is unrecoverable | `Article` is not audited (§3.7) and has no revision history | `audited` on `Article` is a prerequisite of the detach path, not a later nicety. It is also the cheapest fix in this report: 14 precedents exist in `custom/app/models/custom/audit/` |
| Making the form read-only for file-owned rows removes the only working publish control | the `status` dropdown is how publishing actually happens today, because the actions have no UI (§1.1) | link `publish`/`unpublish`/`preview` from the article show page *before* removing anything from the form; they are already implemented and specced |
| Fixing §3.2 by removing `slug` from the form breaks operator-authored articles | an operator-authored article's slug *is* its key (§3.4), so it must stay editable there | gate the field on `doc_source`, or give operator-authored rows a real `doc_key` field — the latter is better and closes §3.4 too |
| §3.6 is inferred from a callback chain, not measured | I did not run the seeder (§6.1 forbids it) | one spec: seed, move a file between sections, seed once, assert `position` matches the front matter |
| Two published rows with the same `doc_key` already exist in production | §3.2 is reachable today and nothing detects it; `01-current-system.md:§4` records a hand-run that reported `38 created` against a 126-file corpus, which is consistent with rows having been created at unexpected slugs | a read-only reconciliation report (file set vs. row set vs. `doc_key` uniqueness) is worth running against production **before** any Phase 5 change, and it is a different check from the SEO audit, which cannot see it |
| `dir` is missing from the portal layout | Arabic publishes LTR today, not just previews LTR | agent 072 owns it; flagged here because an RTL *preview* cannot be built on a layout that has no RTL |
| The registry is unverified against the corpus | nothing asserts that the 87 `DOC_ARTICLES` keys resolve to published articles | a spec over `Library.article_for` for every key; it is the check that would have caught §3.3 and §3.5 |
