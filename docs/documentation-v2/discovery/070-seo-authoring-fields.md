---
agent: 070
scope: SEO fields in the authoring surface — what exists, how it reaches the page, and what the editor must validate before saving rather than `seo_audit` after
confidence: high
---

# SEO authoring fields and their validation

Template EDITOR. Read-only against `claude/documentation-v2`. Everything measured here was measured by parsing
the 126 corpus files and reading the render path; nothing was executed against a database.

---

## 1. What exists today

### 1.1 Three writers, one `meta` jsonb

SEO data for a documentation article lives in exactly two places: the `articles.title` / `articles.description`
columns, and five string keys plus one array inside `articles.meta` (jsonb, `app/models/article.rb:11`). Three
code paths write it.

| Writer | Path | Writes | SEO keys it can set |
|---|---|---|---|
| Markdown front matter → seeder | `custom/app/services/documentation/content_seeder.rb:106-113` | all 126 corpus files | `title`, `description`, `tags` (+ `doc_key`, `version`, `release_date`) |
| Super Admin (Administrate) | `custom/app/controllers/super_admin/articles_controller.rb:39-53` | the platform portals | `title`, `description`, `tags`, `version`, `release_date`, `feature_image` |
| Account Help Center API | `app/controllers/api/v1/accounts/articles_controller.rb:108-115` | tenant portals only | `title`, `description`, `tags` |

The third writer cannot reach documentation articles: `portal` resolves through `Current.account.portals`
(`articles_controller.rb:90-92`) and a platform portal has `account_id = NULL`. It matters only because it is a
second wire format for the same field — see §3.6.

### 1.2 Front matter → `meta`

`meta_for` is the whole mapping (`content_seeder.rb:106-113`):

```ruby
{ 'doc_key' => key,
  'title' => front_matter['seo_title'].presence || front_matter.fetch('title'),
  'description' => front_matter['seo_description'].presence || front_matter['description'],
  'tags' => Array(front_matter['tags']),
  'version' => front_matter['version'].presence,
  'release_date' => front_matter['release_date'].presence&.to_s }.compact
```

So `seo_title` and `seo_description` are *front-matter-only* names. They do not survive as themselves: they are
collapsed into `meta['title']` and `meta['description']` with the plain `title`/`description` as fallback. An
author editing the same article in Super Admin sees only the collapsed result, labelled "SEO title" and "SEO
description" (`custom/app/fields/article_meta_field.rb:16-17`), and has no way to tell whether the value was
authored as an override or inherited from the title.

Measured across `custom/db/documentation` (126 files, 63 EN + 63 AR):

| Front-matter key | Files carrying it | min–max chars |
|---|---|---|
| `title` | 126 | 6–66 |
| `description` | 126 | 56–198 |
| `seo_title` | 28 (14 EN + 14 AR) | 30–60 |
| `seo_description` | **126** | 76–157 |
| `tags` | 126 | 1–3 tags, 32 distinct values, 0 singletons |
| `version`, `release_date` | 0 (2 changelog files carry `release_date`) | — |

`seo_description` is on **every** file, so `meta['description']` is always the authored SEO sentence and
`articles.description` is never the one a crawler reads on a documentation page. Effective meta description is
within 50–160 on all 126 files; effective meta title (`seo_title || title`) is ≤60 on all 126.

### 1.3 How it reaches the public page

`app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb` is the only consumer for a
documentation article (rendered from `articles/show.html+documentation.erb:1-4`):

| Line | Tag | Source |
|---|---|---|
| `:10` | `<title>` | **`article.title` + `" | " + portal.display_title(locale)` — not `meta['title']`** |
| `:11` | `<link rel="canonical">` | `portal_canonical_url` (`custom/app/helpers/documentation_helper.rb:15-17`) |
| `:19-24` | `hreflang` + `x-default` | `portal_locale_alternates`, `portal_default_alternate_url` (`documentation_helper.rb:44-60`) |
| `:26` | `<meta name="title">` | `meta['title'] \|\| article.title` |
| `:28` | `<meta name="description">` | `meta['description'] \|\| article.description` |
| `:31` | `<meta name="tags">` | `meta['tags'].join(',')` |
| `:35-43` | `og:*`, `article:published_time`, `article:modified_time` | same two values + timestamps |
| `:49-53` | `twitter:card/title/description` | same two values |
| `:58-61` | `og:image`, `twitter:image` | `set_og_image_url` (`app/helpers/portal_helper.rb:3-18`) — **never `meta['feature_image']`** |
| `:64-65` | two JSON-LD blocks | `documentation_breadcrumb_schema`, `documentation_article_schema` (`documentation_helper.rb:64-95`) |

`meta['tags']` is rendered a second time, visibly, as pill badges on every documentation article:
`documentation_layout/articles/_release_meta.html.erb:7,22-26`, rendered unconditionally from
`_header.html.erb:14`. Every corpus file has tags, so every documentation page shows them.

`PortalHelper` contributes `html_lang_attribute` (`portal_helper.rb:40-42`), `generate_article_link`
(`:77-83`) — the path half of every canonical — and `set_og_image_url`, which returns `nil` when the
`OG_IMAGE_CDN_URL` global config is blank. Its shipped default **is** blank
(`config/installation_config.yml:634-638`), so unless an operator set it, no documentation page has a social
image and every card is `twitter:card: summary`.

The non-documentation variant `app/views/public/api/v1/portals/articles/_meta_head.html.erb` also puts
`article.title` in `<title>` (`:2`) and gates every `meta['title']`/`meta['description']` tag on presence. The
sitemap (`app/views/public/api/v1/portals/sitemap.xml.erb:14-25`) reuses the same two helpers, so page and
sitemap cannot disagree.

### 1.4 `ArticleMetaField` in Super Admin

`custom/app/fields/article_meta_field.rb` edits `meta` as named inputs rather than raw JSON.
`STRING_KEYS = %w[title description version release_date feature_image]` (`:13`), plus `tags` handled
separately. `permitted_attribute` returns `{ meta => STRING_KEYS + [{ tags: [] }, :tags] }` (`:33-35`).
`LABELS` and `HINTS` (`:15-31`) are the only guidance an author gets. The form
(`custom/app/views/fields/article_meta_field/_form.html.erb`) renders five text inputs (`release_date` as
`type="date"`), one text input for tags, and a hint paragraph each — with **no `maxlength`, no character
counter, no `pattern`, no `required`, and inline `style=` attributes**. `_index.html.erb` and `_show.html.erb`
are one line each, delegating to `to_s` (`article_meta_field.rb:49-54`).

`ArticleDashboard::FORM_ATTRIBUTES` is `portal category title slug description content locale status position
meta` (`custom/app/dashboards/article_dashboard.rb:36`).

### 1.5 Tag normalisation

`SuperAdmin::ArticlesController#resource_params` (`:39-53`):

```ruby
permitted[:meta] = normalized_meta(permitted[:meta]) if permitted.key?(:meta)
...
meta = meta.to_h.compact_blank
meta['tags'] = meta['tags'].split(',').map(&:strip).compact_blank if meta['tags'].is_a?(String)
```

The form posts tags as one comma-separated string; this splits on `,`, strips each, drops blanks. There is no
downcasing, no deduplication, no vocabulary check, no count limit, and no length limit. `compact_blank` on the
whole hash means clearing an input removes the key rather than storing `""` — which is correct, and is also how
§3.1 happens.

### 1.6 `rake lynomia:docs:seo_audit`

`lib/tasks/documentation_seo_audit.rake`. Read-only, `exit 1` on any ERROR (`:149`), renders through the real
helpers rather than reimplementing them (`:30-32`). Thresholds are constants at `:18-20`
(`MIN_DESCRIPTION = 50`, `MAX_DESCRIPTION = 160`, `MAX_TITLE = 60`).

| # | Check | Level | Line | Field it reads |
|---|---|---|---|---|
| 1 | two published articles share a canonical | error | `:50-57` | `portal_canonical_url` → `articles.slug` |
| 2 | canonical does not `start_with?('http')` | error | `:71` | env/custom domain |
| 3 | `article.title` blank | error | `:72` | `articles.title` |
| 4 | `article.title.length > 60` | **warn** | `:73-74` | `articles.title` — **not** `meta['title']` |
| 5 | no `meta['description']` **and** no `article.description` | error | `:85-86` | both |
| 6 | effective description outside 50–160 | **warn** | `:88-92` | `meta['description'] \|\| description` |
| 7 | hreflang set does not contain the article itself | error | `:102-103` | `associated_article_id` family |
| 8 | hreflang set has no `x-default` | error | `:104` | portal `default_locale` |
| 9 | duplicate hreflang locales | error | `:105,109-114` | family locales |
| 10 | breadcrumb crumb with blank `name` or `item` | error | `:122-123` | portal title, category name, article title |
| 11 | article schema has no `url` | error | `:124` | canonical |
| 12 | `[breadcrumb, schema].to_json` raises | error | `:125-128` | everything |

---

## 2. Constraints the existing system imposes

An author-time SEO panel must not break any of these.

1. **The files are the source; Super Admin is not.** `content_seeder` overwrites `title`, `description`,
   `content`, `category`, `position`, `status` **and `meta` wholesale** on every run
   (`content_seeder.rb:94-104`), by its own stated design (`content_seeder.rb:1-8`). Anything the panel makes an
   author fix in Super Admin is destroyed by the next `rails documentation:content`. A panel that validates
   only in Administrate validates the losing writer. **The same rules have to run on the front matter.**
2. **`seo_title`/`seo_description` do not exist after seeding.** The panel cannot show "override vs inherited"
   from the database alone; `meta_for` collapsed that distinction (`content_seeder.rb:108-109`).
3. **`articles.slug` is globally unique and is the canonical.** `index_articles_on_slug (slug) UNIQUE`
   (`article.rb:32`); the canonical is host + `/hc/<portal>/articles/<slug>`
   (`documentation_helper.rb:15-17`). Canonical identity is slug identity.
4. **`locale` is derived, not chosen.** `Article#ensure_locale_in_article` (`article.rb:200-206`) overwrites
   `locale` with the category's locale whenever the article has a category. The dashboard still offers it as an
   editable select (`article_dashboard.rb:20,36`).
5. **hreflang comes from `associated_article_id`, which only the seeder writes.**
   `article_translation_family` reads `root_article` + `associated_articles`
   (`documentation_helper.rb:106-110`); `content_seeder.rb:77,90-92` is the only writer, and it needs English
   seeded first (`content_seeder.rb:42-45`). The Administrate form does not expose it at all
   (`article_dashboard.rb:36`). An author cannot create, repair or break a translation link from the panel.
6. **`meta['doc_key']` is the product→corpus contract** and is read on every contextual-help resolution
   (`custom/app/services/documentation/library.rb:55`). It is in `meta`, next to the SEO keys, and is the one
   key in there that must never be author-editable.
7. **Only published articles are audited** (`documentation_seo_audit.rake:45`) and only published siblings are
   announced (`documentation_helper.rb:44-48`, `:108`). A draft is invisible to the audit but is the state an
   author is in while writing — which is precisely why the editor is the right place for these checks.
8. **Administrate's `update` is `requested_resource.update(resource_params)`**
   (`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:59-60`),
   so a `meta` hash in params *replaces* the jsonb. Any panel must post the complete `meta` or merge
   server-side.
9. **Super Admin already has two client-side extension points, both loaded on every page.** Vanilla
   data-attribute JS at `app/javascript/entrypoints/superadmin.js` (loaded by
   `app/views/layouts/super_admin/application.html.erb:26`) already does live `input`-driven validation of an
   Administrate form — the account-suspension form toggles `required`/`disabled` on every keystroke. A Vue
   mount exists too (`render_vue_component` in `app/controllers/super_admin/application_controller.rb:33-42`,
   `app/javascript/entrypoints/superadmin_pages.js`, loaded at
   `app/views/super_admin/application/_navigation.html.erb:11`). Neither needs creating.
10. **Backend strings belong in `config/locales/en.yml:76-80`** (`documentation.super_admin.*`), per CLAUDE.md.

---

## 3. Findings

### 3.1 BLOCKER — every Super Admin save of an article destroys `meta['doc_key']`

`doc_key` is written only by `content_seeder.rb:107` and read only by `library.rb:55`. It is **not** in
`ArticleMetaField::STRING_KEYS` (`:13`), **not** in `permitted_attribute` (`:33-35`), and **not** rendered by
`_form.html.erb`. Administrate replaces the whole `meta` jsonb with the permitted hash
(`administrate/application_controller.rb:59-60`), and `normalized_meta` returns a freshly built hash
(`articles_controller.rb:47-53`). So pressing Update on any documentation article drops `doc_key`.

Blast radius is asymmetric and that is what makes it dangerous:

- **English article**: `article_for(key)` falls through `by_key` (now empty) to `article(key)`
  (`library.rb:56`), and the English slug *is* the key (`content_seeder.rb:85-87`), so the link still resolves.
  Silent.
- **Arabic article**: the slug is `key-ar`, so the final fallback `article(key)` returns the **English**
  article. Every Arabic contextual-help link for that article silently serves English, with no error anywhere.

This is a `meta`-editing defect in the SEO panel's own field group, so it is this report's to raise, and it
must be fixed before any panel adds more keys to that hash.

### 3.2 MAJOR — the title-length warning measures the wrong string, and the hint is wrong

Three separate problems in one field.

**(a) The audit measures `article.title`, not the title a crawler reads.** Check 4
(`documentation_seo_audit.rake:73-74`) reads `article.title`. Four EN corpus files exceed 60:

| File | `title` | `seo_title` |
|---|---|---|
| `en/whatsapp-errors/whatsapp-business-scoped-contacts.md` | 66 | 49 |
| `en/whatsapp-errors/whatsapp-error-131049.md` | 63 | 37 |
| `en/whatsapp-errors/whatsapp-error-131060.md` | 62 | 37 |
| `en/whatsapp-errors/whatsapp-error-131042.md` | 61 | 37 |

**All four already carry a compliant `seo_title`.** The author did the correct thing and the audit still warns,
with no way to silence it. The effective meta title (`seo_title || title`) is ≤60 on all 126 files.

**(b) The rendered `<title>` is longer than anything the audit measures.** `_meta_head.html.erb:10` emits
`article.title | portal.display_title(locale)`, and `portal_seeder.rb:12` sets `page_title` to
`'Lynomia Chat Documentation'` — a 29-character suffix, leaving a 31-character budget. Measured: **27 of 126
articles render a `<title>` over 60 characters** (16 EN, 11 AR; longest 95). The audit reports 4.

**(c) The field hint is false.** `article_meta_field.rb:25` tells the author "Overrides the `<title>` and
og:title." `meta['title']` overrides `og:title`, `meta name="title"` and `twitter:title`
(`_meta_head.html.erb:26,38,50`) — it does **not** override `<title>` in either layout
(`documentation_layout/articles/_meta_head.html.erb:10`, `articles/_meta_head.html.erb:2`). The design record
is correct where the hint is not (`docs/global-documentation/07-super-admin-management.md:92`: "SEO title,
`og:title`, `twitter:title`"). An author trusting the hint will shorten `seo_title` and watch the SERP title
not change.

### 3.3 MAJOR — canonical uniqueness is structurally unreachable in the audit and unguarded in the model

Check 1 (`documentation_seo_audit.rake:50-57`) groups every published article by canonical URL. Given
`index_articles_on_slug (slug) UNIQUE` (`article.rb:32`) and a canonical that is host + portal slug + article
slug, two articles cannot produce the same canonical. The audit's own spec has to defeat the model to reach
the branch:

```ruby
allow_any_instance_of(Article).to receive(:slug).and_return(first.slug)
```
(`spec/lib/tasks/rake/task_documentation_seo_audit_spec.rb:50-56`)

Meanwhile the real failure mode is unguarded in the opposite direction: **`Article` has no slug uniqueness
validation.** `article.rb:65-69` validates `account_id`, `author_id`, `title`, `content` (if published) and
slug *exclusion* from `RESERVED_SLUGS`; `grep -rn "slug.*uniqueness" app custom` finds it on `Portal`
(`app/models/portal.rb:60`) and `Category` (`app/models/category.rb:63`) and not on `Article`. So a Super Admin
save with a colliding slug raises `ActiveRecord::RecordNotUnique` from Postgres — a 500 and a Sentry entry, not
a 422. That is a direct hit on this repo's own rule: *"Validate request parameters at the controller or request
boundary… so invalid input returns `422 Unprocessable Entity` instead of reaching models or Sentry."*

### 3.4 MAJOR — slug is freely author-editable and is the SEO primary key

`slug` is in `FORM_ATTRIBUTES` (`article_dashboard.rb:36`) as a plain `Field::String` (`:17`), and
`ensure_article_slug` only fills a nil slug (`article.rb:234-236`) — so an existing slug can be rewritten.
Renaming it changes:

- the canonical and every hreflang URL in its family (`documentation_helper.rb:15-17,44-48`);
- the sitemap entry (`sitemap.xml.erb:16`), with **no redirect anywhere** — there is no redirect table and
  `/docs/:article_slug` 404s an unresolvable slug by design
  (`custom/app/controllers/documentation_controller.rb:18-26`);
- the EN `doc_key` slug fallback (§3.1);
- what the next seeder run does: `find_or_initialize_by(slug: slug_for(key, locale), locale: locale)`
  (`content_seeder.rb:73`) no longer matches, so the seeder **creates a second article** at the original slug
  and nothing ever deletes the renamed one (`01-current-system.md` §3). Two published articles, two distinct
  canonicals, duplicate content — and the audit's duplicate-canonical check cannot see it, because the
  canonicals differ.

### 3.5 MINOR — `meta['feature_image']` is authorable, labelled, hinted, permitted, and read by nothing

`grep -rn "feature_image" app custom lib spec config` returns only its three declarations
(`article_meta_field.rb:13,21,30`). It is not written by `meta_for` (`content_seeder.rb:106-113`), not permitted
by the account API (`api/v1/accounts/articles_controller.rb:111-113`), not in the design record's table
(`docs/global-documentation/07-super-admin-management.md:92-96`), and not read by any view. The social image
comes from `set_og_image_url` (`portal_helper.rb:3-18`, `articles_controller.rb:25`), whose config default is
blank (`installation_config.yml:634-638`). So an author who fills in "Feature image URL" — the one field whose
label promises the social card — changes nothing at all, on a page that has no social image.

### 3.6 MINOR — tags are unconstrained, double-purposed, and have two wire formats

`normalized_meta` splits and strips and stops (`articles_controller.rb:51`). No case folding, no dedupe, no
count or length cap, no vocabulary. The corpus is in fact disciplined — 32 distinct values across 126 files,
1–3 per article, **zero singletons** — which is a convention held by review, not by code, and the panel is
where it can start being held by code.

Two further facts the hint gets wrong. `article_meta_field.rb:27` says tags are "Rendered as
`<meta name="tags">` and used to label a changelog entry by module." They are also rendered as **visible pill
badges on every documentation article** (`_release_meta.html.erb:7,22-26` via `_header.html.erb:14`) — so they
are reader-facing copy on all 126 pages, not an invisible SEO field. And `<meta name="tags">` is consumed by no
major search engine; the reader-visible badges are the only real effect.

Wire formats differ: Super Admin posts a comma string and normalises server-side
(`articles_controller.rb:47-53`), while the account API permits `tags: []` as a real array
(`api/v1/accounts/articles_controller.rb:113`). If a shared panel component is built, it has to pick one.

### 3.7 MINOR, latent — "canonical URL has no host" passes a hostless canonical

`portal_absolute_url` (`documentation_helper.rb:29-33`) with a blank host:
`ChatwootApp.help_center_root` is `ENV['HELPCENTER_URL'] || ENV['FRONTEND_URL']`
(`lib/chatwoot_app.rb:35-37`), `nil.to_s` → `''` → `host = "https://"` → `.chomp('/')` → `"https:/"` →
`"https://hc/lynomia-docs/articles/welcome"`. The host becomes `hc`, `start_with?('http')` is true, and check 2
(`documentation_seo_audit.rake:71`) reports INDEXABLE. `.env.example:17` sets `FRONTEND_URL`, so a normal
install is fine and the reported production run showed real hosts — **unverified for this installation's
production env**; I would need its environment to confirm. Recorded because it is the one check that exists to
catch exactly this and does not.

### 3.8 What cannot be validated at author time at all

This is the boundary the brief asks for. Four of the audit's twelve checks are **not** properties of one
article and cannot move into the editor.

| Audit check | Why one article cannot know | Where it must stay |
|---|---|---|
| **1. Duplicate canonical** | A property of the *set* of published articles. One form knows its own slug, not every other article's. (Today it is also unreachable — §3.3 — but the real duplicate-content case, §3.4, genuinely needs the whole corpus.) | corpus-wide check |
| **7. hreflang contains the article itself** | Depends on `associated_article_id` and on the **sibling's `status`** (`documentation_helper.rb:108`). An article can be valid when saved and become invalid when its Arabic sibling is unpublished by someone else, or when English is seeded before Arabic exists (`content_seeder.rb:42-45,90-92`). It is a property of the family over time. | corpus-wide check |
| **8. hreflang has `x-default`** | Depends on `portal.default_locale` and on at least two published siblings (`documentation_helper.rb:54-60`) — portal configuration plus family state, neither in the article form. | corpus-wide check |
| **9. Duplicate hreflang locales** | A property of the family. Reachable only via `ensure_locale_in_article` (`article.rb:200-206`) putting two siblings in categories of the same locale — a category-level fact. | corpus-wide check |

Partly author-time, partly not:

- **Check 2 (canonical host)** is environment configuration (`chatwoot_app.rb:35-37`) or
  `portal.custom_domain`. Nothing an article author types affects it. Deploy/CI concern.
- **Checks 10–12 (structured data builds)** have three inputs, and only one is in the article form.
  Crumb 1 is `portal.display_title(locale)` + `portal_home_url` (`documentation_helper.rb:65`) — portal
  configuration, editable on the Portal dashboard, and a blank portal title breaks **every** article at once.
  Crumb 2 is `article.category.name` (`:66`) — the Category dashboard, and a blank category name breaks every
  article in that category. Crumb 3 is `article.title` + canonical (`:67`), already required by
  `article.rb:67`. `schema['url']` is the canonical again. So "structured data buildability" reduces, at
  article level, to *title present* and *category present* — both cheap to enforce in the form — and otherwise
  to portal- and category-level invariants that belong in a corpus-wide check.
- **Tag vocabulary consistency** (§3.6) is corpus-level by definition: whether `whatsapp` or `whats-app` is the
  house spelling cannot be known from one article. The panel can offer the existing 32 values; only a
  corpus-wide check can report a new singleton.
- **EN/AR SEO parity** — whether the Arabic `seo_description` says what the English one says — is a two-article
  property and belongs to agents 061/094.
- **Whether 50–160 characters is even the right window for Arabic.** `MIN/MAX_DESCRIPTION`
  (`documentation_seo_audit.rake:18-19`) and the comment above them (`:16-17`) are a Latin-script
  pixel-width heuristic expressed in characters. Measured, the AR descriptions are shorter in characters and
  longer in bytes than the EN ones (AR 76–148 chars, max 274 bytes; EN 89–157 chars). Ruby's `String#length`
  counts characters, so the audit and any JS counter using `.length` agree — but the *threshold* is script-
  dependent and nobody has stated an Arabic number. **Do not invent one.** Agents 072 and 073 should state it
  or say it is unknown.

---

## 4. Options, and the author-time SEO panel specified

### 4.1 Decision: where do these rules live?

The seeder overwrites `meta` wholesale (constraint 2.1), so a rule enforced only in Administrate protects
nothing that a deploy will not undo.

| Option | What it is | Trade-off |
|---|---|---|
| **A. Administrate only** | panel validations in the form + controller | Fast. Protects the *losing* writer; the corpus's own 126 files stay unchecked until `seo_audit` runs on the server. |
| **B. Front-matter check only** | extend the audit to read the Markdown in CI | Checks the source of truth, before merge, with no database. Gives the author nothing while they are typing in Super Admin. |
| **C. One shared rule object, three call sites** — recommended | a `Documentation::SeoRules` value object holding the thresholds and the per-article verdicts, called by (i) the Administrate form's server-side validation, (ii) a front-matter check in CI, (iii) `seo_audit` for the corpus-level checks only | One definition of "too long", used before merge, before save, and after deploy. Costs one new object. The thresholds already exist as constants (`documentation_seo_audit.rake:18-20`) and would move into it. |

Option C also removes the duplication that already exists: the audit's effective-description expression
(`:85`) is the same expression as `_meta_head.html.erb:9` and `documentation_helper.rb:87`, written three
times.

### 4.2 The panel

A single "Search appearance" group inside the existing `ArticleMetaField` form partial
(`custom/app/views/fields/article_meta_field/_form.html.erb`) — not a new field type and not a new dashboard
section, because `meta` is already edited as named fields there and `FORM_ATTRIBUTES` already includes `meta`.

**Author-editable fields:**

| Field | Stored at | Control | Counter |
|---|---|---|---|
| SEO title | `meta['title']` | text input, `maxlength` **not** set (so the counter, not the browser, reports overflow) | `n / 60`, and separately **`n + 29 / 60` for the rendered `<title>`** — the suffix is `" | " + portal.display_title(locale)`, known server-side, passed as a data attribute. Fixes §3.2(b). |
| SEO description | `meta['description']` | textarea, 2 rows | `n / 160`, with the 50 floor marked. Counts characters, matching `String#length` in the audit (`:88`). |
| Tags | `meta['tags']` | text input, comma-separated, plus a datalist of the 32 values already in use | `n tags` |
| Release version | `meta['version']` | unchanged | — |
| Release date | `meta['release_date']` | unchanged (`type="date"`) | — |

**Live, non-blocking, beside each counter** (the state an author needs while typing):

- the effective value, computed the way the page computes it: SEO title falls back to `title`
  (`_meta_head.html.erb:8`), SEO description falls back to `description` (`:9`). The counter must count the
  **effective** value, or an author who left SEO title blank is shown `0 / 60` for a page that renders a
  66-character title. This is the §3.2(a) bug, reproduced in the UI if we are careless.
- a rendered-SERP preview: the `<title>` as it will actually be emitted, the canonical, the description.

**Blocking (reject the save, 422, re-render the form):**

| Rule | Why blocking | Existing mechanism |
|---|---|---|
| Effective SEO description blank | audit check 5 is an **error** and gates the deploy (`:149`) | `validates` on `Article`, or controller-level per CLAUDE.md |
| `title` blank | audit check 3 is an error; already blocking (`article.rb:67`) | existing |
| `slug` not unique | §3.3 — today a 500; must be a 422 | `validates :slug, uniqueness: true` on `Article` |
| `slug` changed on an article that has a `doc_key` | §3.4 — breaks the canonical, the sitemap, the link registry and the next seeder run, with no redirect | controller guard |
| `release_date` not ISO-8601 when present | it is sorted lexically as a string (`article.rb:86`) and interpolated into reader-facing copy (`_release_meta.html.erb:19`); a free-text date silently mis-sorts the changelog | format validation |
| `category` absent | breadcrumb crumb 2 (`documentation_helper.rb:66`); a documentation article with no category is a setup error | `validates` |

**Warning (save proceeds, the warning is shown on the article and after the save):**

| Rule | Threshold | Matches audit |
|---|---|---|
| Effective SEO title over 60 | `MAX_TITLE` | check 4, but on the *effective* field — §3.2(a) |
| Rendered `<title>` over 60 | 60 − suffix length | **new** — §3.2(b), 27 of 126 files today |
| Effective SEO description outside 50–160 | `MIN/MAX_DESCRIPTION` | check 6 |
| Tags empty, or more than 3 | corpus convention (1–3, 32 values, 0 singletons) | new, corpus-derived |
| A tag not already in the corpus vocabulary | — | new; a *warning*, never blocking — a new section legitimately needs a new tag |

**Must NOT be author-editable, because it is derived:**

| Field | Derived from | What the panel does instead |
|---|---|---|
| `meta['doc_key']` | the Markdown filename (`content_seeder.rb:70-72,107`) | render it read-only, so an author can see the key the product links to. Never permit it, and **merge it through on save** (§3.1) |
| Canonical URL | portal host + portal slug + article slug (`documentation_helper.rb:15-17`) | display it, read-only, as the author types the slug |
| hreflang set and `x-default` | `associated_article_id` + sibling `status` (`documentation_helper.rb:44-60,106-110`) | display the family and each sibling's status, read-only. An author must not be able to assert a translation that does not exist — "a guessed hreflang that 404s is worse than none" (`documentation_helper.rb:40`) |
| `locale` | the category's locale (`article.rb:200-206`) | **remove it from `FORM_ATTRIBUTES`** (`article_dashboard.rb:36`) or render it disabled. It is editable today and the edit is silently discarded |
| Both JSON-LD blocks | the record (`documentation_helper.rb:64-95`) | show the built JSON read-only, so "it builds" is visible rather than asserted |
| `og:image` / `twitter:image` | `set_og_image_url` + the `OG_IMAGE_CDN_URL` config (`portal_helper.rb:3-18`) | nothing per-article. Say where it comes from |
| `meta['feature_image']` | nothing reads it | **delete it** (`article_meta_field.rb:13,21,30`) — §3.5, and CLAUDE.md: remove dead code |
| `article:published_time` / `modified_time`, `dateModified` | `created_at` / `updated_at` (`_meta_head.html.erb:42-43`, `documentation_helper.rb:90-91`) | nothing |
| `<title>` suffix, `og:site_name`, breadcrumb crumb 1 | `portal.display_title(locale)` (`portal.rb:147-149`) | show it as the fixed suffix in the counter. Note that `portal_seeder.rb:11-13` sets no `locale_translations`, so the Arabic page's suffix and `og:site_name` are the Latin-script `'Lynomia Chat Documentation'` — a portal-level issue for agents 072/073, not an article field |

### 4.3 Where the counters run

Recommend **vanilla data-attribute JS in `app/javascript/entrypoints/superadmin.js`** over a Vue mount:
`superadmin.js` is already loaded on every Super Admin page
(`app/views/layouts/super_admin/application.html.erb:26`) and already does exactly this shape of work —
reading data attributes off an Administrate form, recomputing on every `input`, toggling `required`. A counter
is tens of lines there and zero bundle growth. The Vue path
(`render_vue_component`, `superadmin_pages.js`) should be held for whatever editor agent 067 selects; mounting
Vue for a character count would be the larger abstraction CLAUDE.md warns against. Either way, **the counters
are advisory**: every blocking rule in §4.2 must also be enforced server-side, because JS is not a validation.

### 4.4 The front-matter call site

Rules that are properties of one article — effective title length, effective description presence and length,
tag count — are checkable on the 126 Markdown files with no database, in CI, before merge, which is the only
place they catch the writer that wins (constraint 2.1). The measured corpus is already clean on the
description rules (0 of 126 outside 50–160) and dirty on the title rules (4 by the audit's measure, 27 by the
rendered-`<title>` measure), so this check lands with real findings on day one rather than as a formality.

Whether it gates CI or the deploy is Agent 000's §8.2 decision; this report's input is that the *article-level*
rules can run in CI with no server, and the *corpus-level* rules of §3.8 cannot — they need the database, so
they stay in `seo_audit`.

---

## 5. Risks

1. **Fixing §3.1 is a prerequisite, not a follow-up.** Adding fields to the `meta` group while a save still
   replaces the jsonb widens the blast radius. Merging `doc_key` through on save is a four-line change in
   `normalized_meta` (`articles_controller.rb:47-53`); it should land before any panel work.
2. **A panel invites authors to edit what the seeder overwrites.** The better the SEO panel, the more time an
   author spends in a surface whose work the next `rails documentation:content` discards
   (`content_seeder.rb:94-104`). Until Agent 000 freezes source-of-truth (§8.1), the panel should *say* which
   fields are file-backed. Building a good panel first and deciding ownership second is the sequence that
   produces lost work.
3. **Blocking on description presence changes the failure surface.** It is an audit *error* today and would
   become a save-time 422, which is right — but 126 articles were seeded without that gate. If any pre-existing
   article is missing the effective description, a validation on `Article` makes **every** later save of it
   fail, including `publish`/`unpublish` (`articles_controller.rb:10-18`, which call `update!`) and including
   the seeder's own `article.save!` (`content_seeder.rb:80`), turning a warning into a failed sync. Measured,
   all 126 have one — but the changelog portal and any hand-created article are not in that measurement.
   **Not checked: articles in the database that are not in the corpus.** A corpus-wide audit run would answer
   it; I did not run one.
4. **Adding `validates :slug, uniqueness: true`** (§3.3) is a model-level change on a Chatwoot OSS model shared
   with every tenant help center, not just documentation. It is the correct fix and it is also a behaviour
   change for tenants, whose article creation currently 500s on a collision. Agent 064 should confirm no
   tenant flow depends on the current exception.
5. **A tag vocabulary that blocks would ossify the taxonomy** at exactly the moment the corpus is meant to
   grow several times over (charter §9). Keep it a warning with a datalist.
6. **The 50–160 window is unvalidated for Arabic** (§3.8). Shipping a blocking Arabic rule on a Latin-script
   heuristic would be inventing a number. Keep it a warning in both locales until 072/073 state one.
7. **27 of 126 articles already fail a rule this report proposes** (rendered `<title>` over 60). If the
   rendered-title rule ever becomes blocking, those 27 must be fixed first — and they are fixed in the
   Markdown, not in Super Admin.
