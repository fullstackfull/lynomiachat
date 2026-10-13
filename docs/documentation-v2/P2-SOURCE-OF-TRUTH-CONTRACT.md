# P2 — the source-of-truth and deployment-sync contract, frozen

**Agent 5.** Implements ruling **R12** (`08-orchestrator-rulings.md:406-481`) and is bound by `00-program.md` §2.1
(the documentation security model), §2.3 (the absence rule) and §3 (production rules), and by `R2-MEDIA-CONTRACT.md`,
which is already frozen and which nothing here contradicts.

**This document is the contract Agents 2 (editor) and 3 (content) code against.** It answers one question:
*what authority does an operator's edit have against the file that produced the row?* It does not replace the content
model. The repository stays the source of truth for seeded content; `Article`/`Category`/`Portal` stay the content
model; `Documentation::ContentSeeder` stays the importer. There is no second CMS here and none is proposed.

**Owner constraint, treated as binding and not re-argued:** *deployment must never silently overwrite
operator-authored content.* "Last writer wins silently" is rejected. Every decision below is tested against that
sentence.

**Scope of my write gate.** I write this file, and in implementation waves only
`custom/app/services/documentation/content_seeder.rb`, `custom/app/services/documentation/portal_seeder.rb`,
`lib/tasks/documentation.rake`, `db/migrate/**`, `app/models/article.rb`, `app/models/category.rb`
(`P2-WORKSTREAM-OWNERSHIP.md:76-88`). Everything else I need is in §5 as a requested change with an exact diff.
I have written no file but this one.

---

## 0. How this was verified, and the one thing I could not measure

| Method | What it covered |
|---|---|
| Direct read | `content_seeder.rb` (all 132 lines), `article.rb` (all 301), `article_meta_field.rb`, `article_dashboard.rb`, `category_dashboard.rb`, `super_admin/articles_controller.rb`, `library.rb`, `portal_seeder.rb`, `documentation.rake`, `documentation_controller.rb`, `_form.html.erb`, Administrate 0.20.1's `application_controller.rb`, `documentation_seo_audit.rake`, `deploy.sh` stage inventory, `ROLLBACK.md` |
| Absence-rule searches (§7) | `doc_key`, `feature_image`, `tracking_pixel`, `ContentSeeder`/`PortalSeeder`, `documentation:content`, provenance-column candidates, `Concerns::Article` |
| Filesystem measurement | 126 corpus files (63 EN + 63 AR), 2 changelog files, 12 manifest sections, 12 section directories per locale; manifest slug set `diff`s clean against both locale directory listings |
| Independent re-derivation | the non-convergence callback chain, the `doc_key` destruction path, and the four abort modes — each re-walked in the code rather than taken from 069/097 |

**What I could not measure.** `nproc` is 4 and I ran no spec, per the 4-CPU rule. More importantly **PostgreSQL is
down in this environment** — `pg_isready` returns `/var/run/postgresql:5432 - no response` and `psql` returns
`connection refused` — so the measured two-run probe that R12 §2 asks for (seed, record, seed again, diff) **could
not be executed**. Where a conclusion rests on reading a callback chain rather than on a measurement, it says
**UNVERIFIED** and names the probe that settles it. I did not guess a number anywhere.

---

## 1. The two writers, measured

Both writers target the same rows. Neither knows the other exists.

**Writer A — the seeder.** `Documentation::ContentSeeder#upsert_article` (`content_seeder.rb:70-83`) finds a row by
`portal.articles.find_or_initialize_by(slug: slug_for(key, locale), locale: locale)` (`:73`) and applies
`attributes_for` (`:94-104`) — seven keys: `title` (`:96`), `description` (`:97`), `content` (`:98`), `category`
(`:99`), `position` (`:100`), `status` (`:101`), `meta` (`:102`). `meta` is built by `meta_for` (`:106-113`) as
`{doc_key, title, description, tags, version, release_date}.compact`. Then `associated_article_id` for every
non-default locale (`:77`), then `author ||=` (`:79`), then `save!` (`:80`).

**Writer B — Super Admin.** `ArticleDashboard::FORM_ATTRIBUTES` is
`portal category title slug description content locale status position meta` (`article_dashboard.rb:36`). Administrate
0.20.1 applies it unmodified: `requested_resource.update(resource_params)`
(`administrate-0.20.1/app/controllers/administrate/application_controller.rb:59`), with `resource_params` =
`params.require(...).permit(dashboard.permitted_attributes(action_name))` (`:203-206`).
`SuperAdmin::ArticlesController#resource_params` (`articles_controller.rb:39-43`) then post-processes `meta` only, via
`normalized_meta` (`:47-53`), which is `meta.to_h.compact_blank` — a **whole-value replacement of the jsonb column**,
not a merge.

### 1.1 Field by field, as the code behaves today

| Column | Form writes | Seeder writes | Result of the next `documentation:content` |
|---|---|---|---|
| `title` | yes (`:36`) | yes (`:96`) | operator edit reverted |
| `description` | yes | yes (`:97`) | reverted |
| `content` | yes | yes (`:98`) | reverted |
| `category` | yes | yes (`:99`) | reverted, **and triggers the position defect** (§2.8) |
| `position` | yes | yes (`:100`) | reverted |
| `status` | yes, 3 states incl. `archived` (`article_dashboard.rb:21`, `article.rb:76`) | **forced** from `@publish` (`:101`) | forced to `published`, whatever the operator chose |
| `meta` | yes, replacing the jsonb | yes, replacing the jsonb (`:102`) | reverted — **and the two writers author different key sets** (§1.2) |
| `slug` | yes | **no** — it is the lookup key (`:73,85-87`) | **not reverted; a second row is created** (§2.4) |
| `locale` | yes, but `ensure_locale_in_article` overrides it from the category (`article.rb:263-269`) | **no** — lookup key | the operator's choice never took effect |
| `author` | not on the form | only when nil (`:79`) | preserved |
| `views`, `draft_title`, `draft_content`, `folder_id`, `created_at` | no | no | preserved |
| `associated_article_id` | no | yes, non-default locales (`:77`) | reset from the corpus |

Two structural properties, both re-confirmed by reading the whole file: **nothing is ever deleted** — `perform!`
(`:28-31`) iterates `manifest['sections']` and `Dir.glob`s files (`:47-56`) with no `destroy` and no reconciliation
against the file set — and **there is no transaction**; the only writes are `category.save!` (`:62`) and
`article.save!` (`:80`), per record, and the string `transaction` does not appear in the file.

### 1.2 The `meta` key sets diverge in both directions

| Key | Seeder writes (`:107-112`) | Form writes (`article_meta_field.rb:11-13`) |
|---|---|---|
| `doc_key` | **yes** | no |
| `title`, `description`, `tags`, `version`, `release_date` | yes | yes |
| `feature_image` | no | **yes** |

Because both writers replace the whole jsonb, each destroys the other's exclusive key. This is the two-writer problem
in miniature on one column, and it is the mechanism behind §2.3.

---

## 2. The eleven frozen decisions

Each gives the current behaviour with `file:line`, the decision, why, and what an agent coding against it must do.

---

### D1 — A Super Admin edit survives a deploy. The seeder never overwrites an edited row.

**Today.** Every column in §1.1 marked "reverted" is reverted, silently. The seeder's own header admits the intent —
*"An operator's own edits in Super Admin are not protected from a re-run… The seeder says what it changed so that is
visible rather than silent"* (`content_seeder.rb:7-8`) — but the second clause is false in practice: `count`
(`:115-123`) increments one aggregate `updated` for any differing row and the task prints one line
(`documentation.rake:19`). A reverted operator edit and a genuine corpus change are the same `+1`.

**Decision.** The seeder becomes a **three-way merge** against a stored base, and it **writes nothing to a row whose
content has changed since the seeder last wrote it**. Three digests per row:

- `sd` — the stored base, `articles.content_digest`, written by the seeder at its last write to that row;
- `fd` — the digest of the attributes **the file would produce now**;
- `rd` — the digest of the attributes **currently in the row**.

| `fd` vs `sd` | `rd` vs `sd` | Class | Seeder action |
|---|---|---|---|
| `=` | `=` | `unchanged` | nothing |
| `≠` | `=` | `updated` | apply the file; rewrite `sd` |
| `=` | `≠` | `operator_edited` | **nothing** |
| `≠` | `≠` | `conflict` | **nothing** |

**Why.** It is the smallest construction that satisfies the owner's sentence without a second content store, without a
revision table, and without asking the operator to declare anything. `sd` is a merge base; the file in git is "theirs";
the row is "ours". It also replaces the unreliable `changed?` heuristic (§2.7) and makes content rollback a forward
operation (§2.10) — one column earns three decisions.

**What an agent must do.** Agent 2: an editor save is authoritative and permanent for the row's content; you do not
need to warn the operator that a deploy will erase their work, because it will not. You **must** surface the row's
state — see D5 for the exact fields. Agent 3: a corpus change reaches a row only when that row is `unchanged` or
`updated`; a row an operator has touched is yours to fix only through the operator, so prose corrections should ship
promptly rather than accumulate.

---

### D2 — Provenance is two additive columns on `articles`. There is no provenance today.

**Today.** Verified: none. The schema annotation at `article.rb:1-34` and `db/schema.rb`'s `create_table "articles"`
list every column — `account_id portal_id category_id folder_id title description content status views created_at
updated_at author_id associated_article_id meta slug position locale draft_title draft_content`. A no-exclusion grep
for `content_source|source_path|provenance|managed_by|origin|file_path|content_digest|content_checksum` across
`db/migrate`, `custom/db/migrate`, `db/schema.rb`, both models and all of `custom/app/` returns five hits, every one
classified and unrelated: `support_tickets`' operational `origin`
(`custom/db/migrate/20261009100000_create_support_tickets.rb:48`, `custom/app/models/support/ticket.rb:6,41`) and two
comments in `custom/app/services/whatsapp/diagnosis/local_checks.rb:46,106`. The signals a reader *might* reach for
are all unreliable: `meta->>'doc_key'` is destroyed by any form save (§2.3); `author_id` is `SuperAdmin.first`
(`:22`) for seeded and `current_super_admin` (`articles_controller.rb:36`) for hand-made, which on a
single-super-admin install is the same row, and `author ||=` (`:79`) records who wrote *first*, not last;
`updated_at` is bumped indistinguishably by both writers. And **`Article` is not audited** — `custom/app/models/custom/audit/`
holds 14 capture points and none is `article.rb`; no `audited` declaration exists on `Article`; and
`Article.include_mod_with('Concerns::Article')` (`article.rb:300`) resolves to nothing, because no
`Concerns::Article` module exists anywhere in the tree (§7).

**Decision.** One additive migration, mine, `db/migrate/`:

```ruby
class AddContentProvenanceToArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :content_source_path, :string
    add_column :articles, :content_digest, :string, limit: 64
    add_index :articles, :content_source_path, unique: true
  end
end
```

- **`content_source_path`** — the corpus file that owns this row, relative to `Rails.root`, e.g.
  `custom/db/documentation/en/getting-started/welcome-to-lynomia-chat.md`. NULL means no file owns it: every tenant
  article, and every row an operator authored by hand.
- **`content_digest`** — SHA-256 hex (64 chars) of the canonical seeded-attribute tuple, as the seeder last wrote it.
  NULL means the seeder has never tracked this row.
- **The unique index is a guarantee, not an optimisation**: one file, exactly one row. Postgres permits unlimited
  NULLs in a unique index, so every untracked row is unaffected. It also carries the lookup — `find_by(content_source_path:)`
  runs once per corpus file per run, 126 times today, against a table that also holds every tenant's articles, so the
  index is on the production path and is not speculative.

**Explicitly rejected, with reasons, because an implementer will reach for each:**

- **A `content_synced_at` timestamp.** The digest already answers *is it different*, which is the only question the
  policy asks. A timestamp would only answer *which changed first*, and that does not change any outcome, because the
  seeder never wins a conflict. CLAUDE.md: do not add fields the code does not use.
- **A `detached` / `operator_edited` boolean.** Detachment is **derived** — `content_digest.present? && rd != sd` — and
  a stored flag would be a second source of truth for the same fact, free to drift from it. Derive it.
- **Moving `doc_key` out of `meta` into a column.** It is a contextual-help key, not provenance, and
  `Documentation::Library#article_for` queries it as `articles.meta->>'doc_key'` (`library.rb:55`) — Agent 4's file.
  D3 protects it where it lives; moving it would change another agent's file and three serializers to no end.
- **An expression index on `meta->>'doc_key'`.** The predicate only ever runs after the portal filter
  (`library.rb:43,55`), which uses `index_articles_on_portal_id`, over a platform corpus of 126 rows. An index here
  would be a guess. What would change the answer: the platform corpus passing a few thousand rows, or `article_for`
  being called from a hot loop rather than one in-product help click.
- **Provenance on `categories`.** Sections come from `manifest.yml`, not from per-file front matter, and
  `index_categories_on_slug_and_locale_and_portal_id` is already unique per portal, so the cross-portal collision class
  cannot arise. Phase 1's manifest ⇔ disk assertion (D9) covers section drift. No column. See §5.4 for the one category
  change I do need and do not own.

**What an agent must do.** Agent 2: both columns are **read-only in the editor** — they are never form fields, and the
editor must not let an operator set or clear them. Display them (D5). Agent 3: nothing in `manifest.yml` changes; the
ownership map anticipated that I would need provenance keys there, and I do not.

---

### D3 — `doc_key` destruction is REAL, and it is closed by a model validation plus a controller merge.

**Verified, not taken on report.** The chain, end to end:

1. `ArticleMetaField::STRING_KEYS` is `%w[title description version release_date feature_image]`
   (`article_meta_field.rb:11-13`). `doc_key` is not in it.
2. `self.permitted_attribute` returns `{ attr => STRING_KEYS + [{ tags: [] }, :tags] }` (`:33-35`). `doc_key` is not
   permitted.
3. The form view emits exactly `STRING_KEYS` plus `tags` (`custom/app/views/fields/article_meta_field/_form.html.erb:5-21`).
   `doc_key` is never posted.
4. Administrate's `resource_params` `permit`s only that set (`application_controller.rb:203-206`), and
   `read_param_value` (`:209-224`) turns blank strings into `nil`.
5. `SuperAdmin::ArticlesController#resource_params` replaces the column wholesale:
   `permitted[:meta] = normalized_meta(permitted[:meta]) if permitted.key?(:meta)` (`articles_controller.rb:41`), and
   `normalized_meta` is `meta.to_h.compact_blank` (`:50`). The posted hash always has keys, so it is never `blank?`
   and the early return at `:48` does not fire.
6. `update(resource_params)` (`application_controller.rb:59`) assigns the jsonb. **`doc_key` is gone.**
7. **No merge exists anywhere else.** A no-exclusion grep for `doc_key` returns exactly two code sites in the whole
   repository: `content_seeder.rb:107` writes it, `library.rb:55` reads it (§7). There is no `Concerns::Article`
   override and no custom `Article` model — `./app/models/article.rb` is the only `article.rb` model in the tree.

So: **any Super Admin save of a seeded article destroys `meta['doc_key']`, including a save that only fixes a typo in
the title.** The operator gets no warning, because `doc_key` appears on neither the form nor the show page —
`ArticleMetaField#to_s` iterates `LABELS.keys` (`:15-22,49-54`), which does not include it.

**Blast radius.** `Documentation::Library.article_for` (`library.rb:54-57`) resolves
`by_key.find_by(locale:) || by_key.find_by(locale: DEFAULT_LOCALE) || by_key.first || article(key)`. With `doc_key`
gone, `by_key` is empty and only the literal-slug fallback remains. For **English** that accidentally still works,
because `slug == key` for the default locale (`content_seeder.rb:85-87`). For **Arabic** it does not: the slug is
`key-ar`, so the chain falls through to `article(key)` and returns the **English** row — every Arabic in-product help
link silently serves English. The single caller is `DocumentationController#article` (`documentation_controller.rb:22`),
which 404s on nil (`:23`); 87 keys in `DOC_ARTICLES` (`app/javascript/dashboard/helper/documentationLinks.js:11`)
resolve through it.

**And D1 makes this permanent.** Today the next seed accidentally repairs `doc_key`, because the seeder overwrites
`meta` unconditionally. Under D1 the seeder stops overwriting an edited row, so **the repair stops happening**. The
defect changes from transient to permanent the moment D1 lands. This is the one hard sequencing constraint in this
contract.

**Decision — two parts, in this order:**

**D3a, mine, the guarantee.** A validation on `Article`, in `app/models/article.rb`:

```ruby
# `meta['doc_key']` is the product-to-corpus contract: Documentation::Library#article_for resolves 87 contextual-help
# keys through it, and for a non-default locale the slug cannot stand in for it. The Super Admin form posts `meta` as
# a whole-value replacement and has no field for this key, so a save that does not merge destroys it silently. Fail
# the save instead.
validate :seeded_article_keeps_doc_key

def seeded_article_keeps_doc_key
  return if content_source_path.blank?
  return if meta.to_h['doc_key'].present?

  errors.add(:meta, I18n.t('errors.articles.doc_key_required'))
end
```

**D3b, Agent 2's, the ergonomics.** `normalized_meta` must merge rather than replace. Exact diff in §5.1.

**Why this split, and why this order.** CLAUDE.md: enforce at the earliest shared entry point, and let an impossible
state fail loudly. The model is the one point every write passes through; the controller is one of several possible
callers and Agent 2 is about to add more. Until §5.1 lands, D3a makes a Super Admin save of a seeded article return
`422` with a visible message — which is loud, reversible and strictly better than silent destruction of every Arabic
help link. **The Orchestrator can land D3a and §5.1 in the same integration and the gap never exists**; that is the
preferred path and the reason §5.1 is first in the requested-change list.

**What an agent must do.** Agent 2: land §5.1 with your first editor change, never after it; and treat `doc_key` as a
**displayed, non-editable** field (D5). Agent 3: `doc_key` is the file's basename and you never write it in front
matter.

---

### D4 — The slug is a corpus-owned public address. A file rename never 404s. Redirects are out of scope.

**Today.** `slug_for` derives the slug from the file basename — `key` for `en`, `key-ar` otherwise
(`content_seeder.rb:85-87`) — and `(slug, locale)` is the upsert key (`:73`), so the seeder **never writes `slug`**.
`articles.slug` is globally unique (`article.rb:32`, `index_articles_on_slug`) with **no model-level uniqueness
validation** — `validates :slug, exclusion: { in: RESERVED_SLUGS }` (`:69`) is the only slug validation — so a
collision surfaces as a raw `ActiveRecord::RecordNotUnique`, not a validation error. `slug` is on the form
(`article_dashboard.rb:36`) and on the category form too (`category_dashboard.rb:25`).

Three behaviours follow, and they are different from each other:

- **A file is renamed.** `find_or_initialize_by(slug: new_key)` finds nothing, so a **new row** is created; the old row
  stays `published` at the old slug with the old `doc_key`, now matched by no file forever. Two published rows claim
  one `doc_key`, and `by_key.find_by` has no `ORDER BY`, so which article a help link opens is **undefined**. The old
  public URL still returns 200 with stale content — this is duplicate content, **not** a 404.
- **An operator renames the slug in Super Admin.** The previously indexed public URL
  `/hc/lynomia-docs/articles/<old>` **404s immediately**, because no row holds that slug any more; the next seed then
  recreates a row there, leaving a duplicate. This is the real SEO regression, and it is the one the owner's brief
  names.
- **An operator renames a category slug.** Same shape, portal-scoped: the next
  `upsert_category` (`:58-64`) `find_or_initialize_by(slug:, locale:)` creates a **second section**, and the renamed
  one keeps its articles.

**Decision.**

1. **The seeder owns `slug`.** With `content_source_path` as the primary lookup key (D7), the seeder can and does
   reassert `slug` from `slug_for(key, locale)` on **every** run, for every row it tracks, **regardless of
   classification** — exactly as it already reasserts `associated_article_id` (`:77`). A slug is an *address*, not
   authored content; the corpus defines it; so reasserting it is not overwriting operator content and does not violate
   the owner's sentence. Consequence: an operator slug rename is corrected on the next seed and the old URL comes back.
2. **`slug` leaves both Super Admin forms** (§5.2, §5.4). Editing it has no legitimate use and the only effects are a
   transient 404 and a duplicate row.
3. **A file rename is one `created` plus one `orphan`, both reported** (D9's classification). The old row keeps
   serving its old URL untouched, so **no previously indexed URL ever 404s from a rename**. The operator resolves the
   duplicate by retiring the old file (D6) or renaming it back. The SEO audit cannot see this — it groups by
   `portal_canonical_url` (`documentation_seo_audit.rake:50-57`) and two different slugs produce two different
   canonicals — so **the orphan report is the only detector, which is why it is mandatory output and not a debug
   flag**.
4. **Redirects are OUT of scope for P2.** No previously indexed URL 404s under (1)–(3), so a redirect table would be a
   new mechanism solving a problem this design does not create — against the charter's §2 rule and CLAUDE.md's
   smallest-change rule. Recorded in §6 as a question for the owner with the place it would live if the answer changes,
   because the corpus is about to grow several times over and a deliberate URL change is a legitimate future want.

**What an agent must do.** Agent 2: do not render a slug field; the file name is the address. Agent 3: **a corpus file
basename is a public URL.** Renaming one is an editorial act with consequences, not a tidy-up; retire and replace
instead. Never name a file `search.md`, `articles.md` or `categories.md` (D9, abort mode 2).

---

### D5 — Conflict policy: the seeder refuses, reports, and exits non-zero. The operator sees the row, the file and the class.

**Today.** The operator sees `articles: 38 created, 19 updated, 67 unchanged` (`documentation.rake:19`) and nothing
else. There is no indication of which rows, which files, whether their own work was among the 19, or that the counters
describe only *the files the seeder happened to read* — never compared against the manifest, the corpus on disk, or the
rows already present. 097 §2.1 showed that is not theoretical: `38 + 19 + 67 = 124` against a 126-file corpus (I
confirmed the corpus is 126 files today), and nothing reported the shortfall for a whole release.

**Decision.** On `conflict` the seeder writes nothing to that row and reports it. Per-run output, mandatory:

```
portal lynomia-docs, revision <git sha>, 126 files in 12 sections, 126 tracked rows
  created 0   updated 3   unchanged 121   operator_edited 1   conflict 1   retired 0   adopted 0
  orphans 0

conflict         en  whatsapp-templates      custom/db/documentation/en/whatsapp/whatsapp-templates.md
operator_edited  ar  connect-whatsapp-ar     custom/db/documentation/ar/whatsapp/connect-whatsapp.md
```

- The **reconciliation line** — files, sections, tracked rows — is the drift detector R12 orders before any scheduler.
  It is what makes "I missed two files" visible.
- **Exit status**: non-zero on any `conflict` or `untracked` (D7); zero with a warning block on `operator_edited` and
  `orphan`. Rationale: a conflict and an untracked row are states the operator must act on before the corpus is
  correct; `operator_edited` and `orphan` are states an operator may legitimately be living in, and a red exit on every
  routine run trains people to ignore the exit code.
- **Resolution is the operator's, in one of two directions, and both are explicit**: edit the file to match the row and
  re-run (the file wins), or pass `ACCEPT_FILE=<slug>,<slug>` to overwrite those named rows (the file wins loudly, once,
  by name). There is no global "take the file" flag, because that is "last writer wins silently" with extra words.
- **Agent 2's surface** shows, on the article's show page and above the edit form, read-only: `content_source_path`
  (or "authored in Super Admin" when NULL), the row's class as the seeder would compute it, and `doc_key`. A
  conflicted row says so where the operator is editing it.

**Why.** It is the minimum that makes the owner's sentence checkable by a human rather than asserted by a comment. A
sync that cannot tell you it missed two files cannot be trusted to tell you it overwrote nothing.

**What an agent must do.** Agent 2: render those three facts; they are the only reason an operator can reason about
their own edit's fate. Agent 3: a `conflict` line names your file and blocks the corpus from converging — treat it as a
build break.

---

### D6 — Publication state belongs to the operator. The file decides it once, at creation, and may retire.

**Today.** `status: @publish ? :published : :draft` (`content_seeder.rb:101`) is unconditional. `@publish` defaults to
`true` (`:20,23`) and `documentation.rake:18` passes nothing, so **every run forces every article to `published`**. The
front matter has no `status` key and no article can opt out; the only override, `ContentSeeder.new(publish: false)`,
flips all of them to draft. Meanwhile `archived` and `draft` are the only working retirement mechanisms — all three
read paths are `published`-scoped (`library.rb:42-44`;
`app/controllers/public/api/v1/portals/articles_controller.rb:13` index, `:30` markdown, `:39` tracking pixel, `:84`
the page — the last widened only for a previewing super admin; `documentation_seo_audit.rake:45`) — so an
operator who unpublishes an article has it republished by the next seed, **including by a deploy that withdraws the
feature the article documents**.

**Decision.**

| Situation | Does the seeder write `status`? |
|---|---|
| Row created | **Yes**, from front matter `published:` (optional, default `true`) |
| Row updated, normally | **No. Never.** |
| Front matter `retired: true` | **Yes** → `archived`, applied whatever the class, content left alone |
| The file was removed from the corpus | **No** — reported as `orphan`, never auto-archived |

`status` is **excluded from the digest**. This matters and is not an oversight: if `status` were in the digest, an
operator unpublishing an article would make `rd ≠ sd` forever, freezing that article's **prose** against all future
corpus corrections. Unpublishing must not freeze the text. Publication state is therefore governed by its own rule
above, not by the merge.

`retired: true` is allowed to override the operator because it only ever *reduces* visibility — the safe direction —
and because it is a reviewed change in source control, which is what a retirement decision should be. Deleting a file
is **not** a decision: it is indistinguishable from a mistake, a bad rebase or a sparse checkout, so it archives
nothing.

**Why.** 097 §2.9 is right that automation changes what the behaviour *means*: with the sync manual, forcing `status`
is an operator's deliberate act they are present for; wired into a pipeline it becomes an unconditional property of
every release, including the rollback one. And the charter's two seeders already disagree about this —
`PortalSeeder` protects operator state by design and says so (`portal_seeder.rb:4-6`), preserving `config['layout']`
(`:55-56`) and filling `DOCUMENTATION_URL`/`CHANGELOG_URL` only when blank (`:39-47`). This decision makes the content
seeder agree with the portal seeder.

**What an agent must do.** Agent 3: two new **optional** front-matter keys, `published:` (boolean, default `true`,
honoured on create only) and `retired:` (boolean, default `false`). All 126 existing files keep working unchanged, and
`retired: true` is how you withdraw an article — not `git rm`. Agent 2: `status` stays an editable form field and the
operator's choice is now durable; stop treating the `publish`/`unpublish` actions
(`articles_controller.rb:10-18`) as cosmetic — they were previously undone by every seed and now are not.

---

### D7 — "unchanged" is not reliable today. The digest replaces it, and the digest is defined exactly.

**Today.** `changed = article.changed?` is read at `content_seeder.rb:78`, which is **after** `assign_attributes`
(`:76`) and the `associated_article_id` write (`:77`) but **before** two further writes:

1. `article.author ||= author` (`:79`). An existing row with a nil `author` is written and reported **`unchanged`**.
2. `save!` (`:80`) fires `after_save :category_id_changed_action, if: :saved_change_to_category_id?`
   (`article.rb:74`), which can `update_column(:position, …)` (`:286`) **after** the flag was read. The row is then
   reported `updated` while the persisted state does **not** match the file (§2.8).

So `changed?` is a statement about an in-memory dirty flag read two writes early, not about the resulting row.

**What it does cover, checked rather than assumed** — I looked for other oscillation sources and found none:
`meta` jsonb comparison goes through `ActiveRecord::Type::Value#changed?` (`old != new`) and Ruby `Hash#!=` is
key-order independent, so key order causes no false `updated`; `release_date` is normalised to a String by
`meta_for` (`:112`, `.presence&.to_s`) so the `Date`→text round trip is stable; `tags` is `Array(...)` (`:110`);
`content` is `strip`ped once (`:130`), deterministically; `locale` is re-derived from the category
(`article.rb:263-269`) to the same value the lookup used; `ensure_account_id` (`:293-295`) writes the `nil` it already
holds; `position` on **create** is preserved because `before_create :add_position_to_article` returns early when
`position.present?` (`:271-276`) and the `after_save` guard's three conjuncts are all true on a create (`:258`).
**The section move is the only content-level non-convergence source.** That bounds the fix in D8.

**Decision.** `unchanged` ⇔ `fd == sd && rd == sd`. The digest is canonical and frozen:

```ruby
DIGEST_VERSION = 1
SEEDED_META_KEYS = %w[doc_key title description tags version release_date].freeze

def digest_for(title:, description:, content:, position:, category_slug:, meta:)
  payload = [DIGEST_VERSION, title.to_s, description.to_s, content.to_s, position,
             category_slug.to_s, meta.to_h.slice(*SEEDED_META_KEYS).compact.sort.to_h]
  Digest::SHA256.hexdigest(JSON.generate(payload))
end
```

Frozen properties, each load-bearing:

- **In the digest**: `title`, `description`, `content`, `position`, the category **slug** (not its id — ids differ
  between environments and a reseeded category gets a new one), and the `SEEDED_META_KEYS` subset of `meta`.
- **Not in the digest**: `status` (D6), `slug` and `locale` (identity, reasserted by the seeder — D4), `author`,
  `views`, `draft_title`, `draft_content`, `folder_id`, `associated_article_id`, and `meta['feature_image']`.
- **`meta` is sliced to `SEEDED_META_KEYS` on both sides.** Without the slice, an operator setting `feature_image`
  (the one form-only key, `article_meta_field.rb:13`) would detach the row and freeze its prose forever. With it,
  `feature_image` is the operator's and does not affect the merge. Symmetrically `doc_key` is the seeder's; under D3 it
  can never go missing, so it can never cause a false detach.
- **`.to_s` on the three text fields** normalises `nil` against `""`, which matters because Administrate's
  `read_param_value` (`application_controller.rb:209-224`) turns a blank input into `nil` while the file yields `""`.
- **`.sort.to_h`** makes the hash serialisation order-independent; `JSON.generate` on a Hash otherwise preserves
  insertion order.
- **`DIGEST_VERSION` is the first element.** Changing the tuple bumps it, which invalidates every stored digest and
  turns the whole corpus `untracked` on the next run — a deliberate, loud, operator-gated event (D7's adopt path), not
  a silent reclassification. **Never change the tuple without bumping it.**
- Two rows written by the seeder and two written by a form always produce comparable digests, because both sides are
  computed by this one method from the same six inputs.

**The untracked / adopt path.** `content_digest` is NULL for every existing row the moment the migration lands — the
whole production corpus. The seeder cannot tell a pristine previous seed from operator work, and I cannot read
production to find out (§3). So: **`documentation:content` refuses to write an untracked row**, prints the count and
the instruction, and exits non-zero. The operator runs it once as
`ADOPT_UNTRACKED=1 rails documentation:content`, which applies the file, writes the path and the digest, and reports
them as `adopted`. That reproduces today's behaviour exactly once, under an explicit flag, with a count the operator
reads — rather than silently overwriting, on the first run after a deploy, whatever an operator may have typed before
the migration existed.

**What an agent must do.** Agent 2: never compute a digest in the editor and never write `content_digest`; the seeder
owns both columns. Agent 3: whitespace matters to the digest only through `content.strip`, so trailing-newline churn in
a file does not reclassify a row; a one-space prose change does, and correctly.

---

### D8 — Non-convergence is real, I re-derived the cause, and the fix is one guard in the model.

**The finding, re-derived rather than cited.** The chain, read at `file:line`:

1. The seeder assigns `category` on every upsert (`content_seeder.rb:76,99`), so an article whose `.md` moved between
   sections changes `category_id` — the lookup is by `(slug, locale)` (`:73`) and ignores the category entirely.
2. `after_save :category_id_changed_action, if: :saved_change_to_category_id?` (`article.rb:74`) therefore fires.
3. The guard is `return if created_at_before_last_save.nil? && position.present? && category_id_before_last_save.nil?`
   (`:258`). For an **existing** row, `created_at_before_last_save` is the row's `created_at` — not nil — and
   `category_id_before_last_save` is the old category — not nil. **Two of three conjuncts are false, so the guard does
   not fire.**
4. `update_article_position_in_category` (`:278-291`) runs, `persisted?` is true, and
   `update_column(:position, max_position + 10)` (`:286`) **discards the front-matter position the seeder assigned one
   line earlier** (`content_seeder.rb:100`).
5. On the **next** run `category_id` is unchanged, the callback does not fire, and the file's position is restored. The
   defect heals on run two.

So `rails documentation:content` needs **two runs** to reach a fixed point after any corpus reorganisation, and run one
reports `updated` for a row whose persisted state does not match the file. It cannot be described as idempotent in one
run, which is what `content_seeder.rb:3` claims and what `content_seeder_spec.rb:55-64` asserts under the name *"the
property that makes it safe to run on every deploy."*

**Why the spec cannot see it, verified by reading the fixture.** `content_seeder_spec.rb:19-30` writes a temporary
manifest with **exactly one section**, and the `write` helper hard-codes `'getting-started'` as the directory (`:42`).
There is no second section for a file to move to, so `saved_change_to_category_id?` can never be true for an existing
row in any example. A section move is **structurally unrepresentable** in this fixture; the suite is green and
measures nothing here. The gate runs recorded at `P0-PRODUCTION-HARDENING.md:669-670,1045` do not help either:
`126 created, 0 updated, 0 unchanged` is a first seed into an empty database, which exercises the create path where the
guard *does* fire.

**UNVERIFIED — the measurement.** PostgreSQL is down in this environment (`pg_isready`: *no response*; `psql`:
*connection refused*), so I could not run the two-run probe. The claim above is a callback-chain derivation, not a
measurement. **The probe that settles it**, for whoever has a database: seed the fixture corpus with **two** sections;
record `articles.position` for one article; move its `.md` to the other section; seed; assert the position is
`max_position + 10` rather than the front-matter value; seed again; assert the front-matter value is restored. That
spec belongs beside `content_seeder_spec.rb` and is mine to write in the implementation wave.

**Decision — one line, in the model, gated on the platform portal:**

```ruby
def category_id_changed_action
  return unless persisted?
  # For a platform portal the corpus sets `position` from front matter on every run
  # (Documentation::ContentSeeder#attributes_for), so re-deriving it here discards the authored order and makes the
  # seed non-convergent in a single run. A tenant Help Center still gets the end-of-category default.
  return if platform_owned?
  return if created_at_before_last_save.nil? && position.present? && category_id_before_last_save.nil?

  update_article_position_in_category
end
```

**Why here and not in the seeder.** CLAUDE.md: enforce at the earliest shared entry point; do not add backup guards
downstream. The clobber happens inside `save!`, so a seeder-side correction would be a second write repairing the
first — and it would have to run after every `save!` whether or not the callback fired. `platform_owned?` already
exists (`article.rb:125-127`) and is `portal&.platform_owned? || false`, so a tenant portal is never affected and
tenant behaviour is bit-for-bit unchanged. This also makes `position` safe to include in the digest (D7), which it
otherwise would not be: the callback would make every moved article look operator-edited and freeze it.

**Honest note on ownership.** `app/models/article.rb` is granted to me for "provenance fields and their validations"
(`P2-WORKSTREAM-OWNERSHIP.md:84`). This guard is neither, strictly — it is a position callback on a product-wide
model. I am taking it because it is the root cause of the defect my own contract depends on and because it is inert
outside a platform portal, and I am flagging it here for Agent 6's adversarial review and the Orchestrator's
integration rather than landing it quietly.

---

### D9 — The seed becomes plan-then-apply. That is what makes the four abort modes unreachable.

**Today.** `perform!` (`:28-31`) writes as it walks. There is no transaction — the codebase knows the idiom, since
`Article.update_positions` wraps its writes in `transaction do` (`article.rb:218`) — and there is no `rescue`
anywhere in the file. The write order is fully determined: `manifest['sections']` in file order (`:29`), locales
outer with the default locale first (`:42-45,48`), `Dir.glob` inner and sorted (`:52`), and `upsert_category` before
the glob (`:51`). A raise at file *k* therefore leaves earlier sections complete and **published and publicly
crawlable**, the failing section's categories created in both locales, the failing section complete up to the failing
filename alphabetically, and every later section untouched with its categories absent. Nothing undoes it, and
re-running fails at the same file forever when the cause is a file.

**The four abort modes, named and verified.** 097 reported four; I re-derived each and add the fifth it reported
separately:

| # | Mode | Mechanism | Why CI misses it |
|---|---|---|---|
| 1 | **A front-matter-only stub** | `body` is `match.post_match.strip` → `''` (`:130`); `status` is forced `:published` (`:101`); `validates :content, presence: true, if: :published?` (`article.rb:68`) → `save!` raises `RecordInvalid` | `content_seeder_corpus_spec.rb:44-45` asserts only that `title` is present and `position` is an Integer |
| 2 | **`search.md`, `articles.md`, `categories.md`** | `RESERVED_SLUGS = %w[search articles categories]` with `validates :slug, exclusion:` (`article.rb:63,69`); the EN slug **is** the key (`:85-87`) → `RecordInvalid`. **Locale-asymmetric**: the AR sibling becomes `search-ar` and passes, so the EN file aborts the run and the AR file would have seeded fine | nothing checks file names against `RESERVED_SLUGS` |
| 3 | **A docs key equal to a changelog key** | `index_articles_on_slug` is global and UNIQUE (`article.rb:32`) with **no model uniqueness validation**; `find_or_initialize_by` is portal-scoped (`:73`) so it cannot see the other portal's row → `ActiveRecord::RecordNotUnique`, a raw PG error. Which task dies depends on run order (`documentation.rake:11,17`) | the two corpora are never compared; `custom/db/changelog/releases/` already holds `first-release-note` |
| 4 | **Two YAML shapes** | `YAML.safe_load(match[1], permitted_classes: [Date])` (`:130`). `release_date: 2026-01-01 10:00:00` parses as `Time`, not permitted → `Psych::DisallowedClass`; malformed YAML → `Psych::SyntaxError`. `release_date` is a real field (`:112`) the changelog orders by (`article.rb:87`) | neither is caught anywhere |
| 5 | **A section directory absent from `manifest.yml`** | `perform!` iterates the **manifest** (`:29`); the corpus spec globs **all** directories (`content_seeder_corpus_spec.rb:21,23`). The section is silently never seeded — no error, no warning, no count | CI and the seeder disagree about what the corpus *is*. **This is the original production bug one layer down, with a green suite.** I measured the current state: 12 manifest slugs `diff` clean against 12 directories in **both** locales, so this is latent today, not live |

**Decision — two phases in one task, no wrapping transaction.**

- **Phase 1, PLAN. Read-only. Writes nothing.** Parse every file in both corpora; build every intended row; then
  assert, and on any failure print every offending file and exit non-zero with nothing applied:
  1. manifest section set **==** directory set, per locale (mode 5);
  2. front matter parses, `title` and `position` present, body non-empty when the row would be published (modes 1, 4);
  3. every intended slug passes `Article::RESERVED_SLUGS` (mode 2);
  4. the intended slug set is unique **globally** — within the corpus, across the documentation and changelog corpora,
     and against `Article.where.not(id: <the rows this run owns>)` — because the index is global and portal scoping
     cannot see the collision (mode 3). This also catches the transient collision D4's slug reassertion could
     otherwise produce when an operator-renamed slug occupies another row's address;
  5. the three-way class of every tracked row (D1), so `conflict` and `untracked` are known **before** anything is
     written.
- **Phase 2, APPLY.** Write only the rows classed `created`, `updated` or `retired`, plus the always-reasserted
  identity fields (`slug`, `associated_article_id`, `author ||=`). Per-row `save!`, as today.

**No single wrapping transaction**, and this is deliberate. R12 names `increment_view_count` as the cost of that
"obvious fix". I checked the claim rather than inheriting it, because 098 asserts the opposite —
that `increment_view_count` *"is never called"*. **Both are partly right and both conclusions are wrong.** A
no-exclusion grep for `tracking_pixel|tracking-pixel` returns exactly four hits, every one classified:
`config/routes.rb:516`, `app/controllers/public/api/v1/portals/articles_controller.rb:7`, `:38` (the action) and `:49`
(the asset path). So **no view and no JavaScript in this repository emits that URL** — 098's observation is correct.
But `get 'hc/:slug/articles/:article_slug.png'` is a live, unauthenticated public route, and
`@article.increment_view_count` (`:42`) runs on any request to it from a crawler, a prefetcher or a typed URL. *No
caller in our code* is not *never called* — which is the absence rule's whole point. The real-world rate is
**UNVERIFIED** and would be settled by one `SELECT count(*) FROM articles WHERE views IS NOT NULL` on production, or
an access-log grep for `.png` under `/hc/`. Phase 1 removes the need to decide: because everything that raises raises
before any write, a wrapping transaction buys nothing and its lock window against an unmeasured public writer is a
cost with no benefit.

**Deploy placement: the seed does NOT run automatically.** `documentation:content` appears nowhere in
`deployment/deploy.sh` — I verified this with a no-exclusion grep across the whole repository, which returns three
call sites for `ContentSeeder` (the two rake tasks and two specs) and no deploy, job, controller or CI reference
(§7). It stays that way, for four reasons: 097 §2.6 shows every placement in the current pipeline breaks something,
two of them structurally (before stage 3 the tree is still `$PREVIOUS_SHA`, so the sync is a no-op); a wired sync runs
on releases that touch no Markdown, including the rollback deploy (D6); R12 orders a drift detector *before* a
scheduler; and a failure at stage 5½ trips an ERR trap whose message — *"Nothing was restarted; the previous version
is still serving"* (`deploy.sh:48-52`) — is **false** after a content write, because the trap models process state and
cannot express a second axis. Instead: `deploy.sh` gains a **read-only, non-failing** drift print at stage 8, and the
seed stays an operator step in the post-deploy checklist. Both are files I do not own — §5.3 and §5.5.

**What an agent must do.** Agent 3: all five modes are now caught in phase 1 with your filename and a reason, before
anything is written, so a bad file costs you a red task and not a half-published corpus. Agent 2: the editor is never
the thing that runs a seed.

---

### D10 — Rollback: content rolls back by a forward seed, not a database restore.

**Today.** `ROLLBACK.md:42-69` is checkout, `bundle install`, `pnpm install`, two Vite builds, `systemctl restart`.
**It touches no database.** So rolling the code back after a bad sync leaves the new corpus in `articles` and the old
code serving it — permanently, as the steady state. The only content reversal available is the stage-2 whole-database
dump, which `ROLLBACK.md:83-85` itself says *"loses every message, conversation and order written since the dump was
taken"* and *"needs an explicit decision from the service owner, not an operator's judgment call mid-incident."* That
is the current price of reversing a wrong paragraph in a help article. And `ROLLBACK.md:33` routes "one feature broken,
rest of the product serving" to *"Usually no — fix forward"*, which is the right row for a bad sync — except that
there is no forward fix today for overwritten operator content, because `Article` is unaudited (D2), the seeder writes
neither `draft_title` nor `draft_content`, and there is no revision history.

**Decision.** `git revert` the corpus commit, then re-run `documentation:content`. That is the whole procedure, and
under D1 it is sound rather than hopeful: reverting the file makes `fd ≠ sd` while `rd == sd` for every row no operator
touched, so each is classed `updated` and fast-forwards **back** to the reverted content. Rows an operator has edited
stay as the operator left them and are reported `operator_edited` — which is the owner's rule, applied to rollback.

This answers 097 §2.7's four stated requirements for a content-only reversal without building any of them:

| Requirement | How D1/D2 satisfies it |
|---|---|
| A pre-image per row, captured before the first write | Not needed. The file in git **is** the pre-image, and `content_digest` proves the row still matches it. |
| A representation independent of the file | Not needed, for the same reason: reverting the code restores the old file, and re-seeding is then the reversal rather than a re-application. |
| A reconciliation that can delete | `retired: true` (D6) plus the mandatory orphan report (D4, D5). Still never an implicit delete. |
| Convergent in one run | D8. |

**The hard limit, stated plainly.** A revert cannot reverse a row an operator edited after the bad seed, and nothing
short of the whole-database dump can. That is a consequence of the owner's own rule and the correct trade: operator
content is safe from deployment, therefore deployment cannot undo operator content.

**Note the migration interaction.** `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:23-30`
restores `NOT NULL` on `articles.account_id` in `down`, which fails while any platform-owned row exists; the migration
says so itself (`:20-22`) and prescribes *"Delete the platform portals first — the content is reproducible from source
control and the seeder is idempotent."* D8 is what makes the second half of that sentence true; it was not. My own
migration (D2) is additive and `change`-based, so it inverts mechanically and old code ignores two extra nullable
columns.

`deployment/ROLLBACK.md` is Orchestrator-only (`P2-WORKSTREAM-OWNERSHIP.md:108`). Exact diff in §5.3.

---

### D11 — SEO validation: front matter in CI, data in the audit, **nothing** in the seed.

**Today.** `lib/tasks/documentation_seo_audit.rake` is Agent 4's file. It declares itself *"READ-ONLY… Exit status is
1 when there is an ERROR, so it can gate a deploy"* (`:9-10`) and audits
`portals = Portal.where(archived: false)` with the `PORTAL_SLUG` narrowing **optional** (`:34-35`).

**Decision, consistent with R9** (*"file-level checks are properties of files, so they belong in CI… Data-level checks
stay in the audit"*):

| Check | Home | Why |
|---|---|---|
| SEO title/description presence and length; tags shape | **CI**, in the corpus spec | Properties of front matter. A human fixes them before merge. |
| Duplicate canonical; hreflang reciprocity | **CI**, by seeding a fixture corpus into a throwaway database — which `content_seeder_spec.rb` already does — **and** retained in the audit for production data | Properties of the article *set*, reproducible from files; the audit keeps the production view. |
| Slug legality, global slug uniqueness, body presence, YAML validity, manifest ⇔ disk | **the seed's phase 1** (D9) | These abort a write or corrupt a public address. They are write-safety, not quality. |
| Files-versus-rows drift and orphans | **a new `documentation:drift` task**, mine | The one genuinely production-only fact, and the detector R12 orders first. The audit cannot see it. |
| Everything above as a **deploy gate** | **No** | See below. |

**Why nothing SEO-shaped goes in the seed.** Conflating quality with write-safety means a 48-character description
blocks a factual correction. Phase 1 fails only on what would raise or produce a broken address.

**Why the audit cannot gate a deploy**, three of which I verified in its source: it audits **every** non-archived
portal including tenants', because `PORTAL_SLUG` is optional (`:34-35`), so a customer's own help-center article with a
short description would fail a production deploy; it is read-only and runs last (`:9`, `report` at `:139-149`), so it
announces a corpus that is already committed and already public; and `exit 1 unless errors.empty?` (`:149`) at stage 8
would trip the deploy's `RESTARTED=1` trap branch, telling the operator the revision *"is not healthy"* and to roll
back — catastrophically disproportionate for a meta description. 097 adds, and I did not re-verify, that it returns
`INDEXABLE` for a corpus missing every Arabic sibling, which is the one failure mode an after-the-sync gate would
exist to catch.

**The one change the audit needs is one line**: default to the platform portals instead of all portals. §5.6. I am not
making it; Agent 4 owns the file.

**What an agent must do.** Agent 4: §5.6, and `documentation:drift` is mine, not a new audit mode — call it, do not
reimplement it. Agent 3: your front matter is checked on the pull request, not after deployment.

---

## 3. The task surface, frozen

`lib/tasks/documentation.rake` is mine. After this contract:

| Task | Behaviour |
|---|---|
| `documentation:setup` | unchanged (`PortalSeeder`), still operator-run, still ordered **before** `documentation:content` — a locale added to `manifest.yml` is inert until it runs, because `locales` is `LOCALES & portal.allowed_locale_codes` (`content_seeder.rb:43`) and `allowed_locales` is written only by `PortalSeeder` (`portal_seeder.rb:63`) |
| `documentation:content` | phase 1 then phase 2 (D9); the report of D5; non-zero on `conflict` or `untracked`; honours `ADOPT_UNTRACKED=1` and `ACCEPT_FILE=<slug>,…` |
| `documentation:changelog` | identical semantics against `CHANGELOG_ROOT`; phase 1's uniqueness check spans **both** corpora (D9 mode 3) |
| `documentation:drift` | **new.** Read-only. Prints files-versus-rows both directions — tracked rows with no file (orphans), files with no row, and each row's class — plus the reconciliation line. Writes nothing. This is the detector R12 orders before any scheduler, and it is what `deploy.sh` calls (§5.5). |

`Result` gains `operator_edited`, `conflict`, `adopted`, `retired` counts and an `orphans` array; `created`,
`updated`, `unchanged` and `locales` keep their names and meanings (`content_seeder.rb:14`).

---

## 4. What Agents 2 and 3 can now rely on, in one place

**Agent 2 (editor).**
1. An operator's save is **durable**. No deploy reverts it. Design for that.
2. `content_source_path` and `content_digest` are **never** form fields; the seeder owns them.
3. `slug` **leaves** the form (§5.2). `doc_key` is **displayed, not editable**.
4. `meta` must be **merged**, not replaced (§5.1) — and land it with your first change, because D3a 422s a seeded
   article's save until you do.
5. `status` stays editable and the operator's choice is now permanent (D6).
6. Show the row's provenance and class where the operator edits it (D5).

**Agent 3 (content).**
1. The file basename is the `doc_key` **and** the public URL. Renaming it is a URL change (D4).
2. Two new optional front-matter keys: `published:` (default `true`, create-only) and `retired:` (default `false`).
   No existing file changes. No `manifest.yml` key is added by me.
3. Retire with `retired: true`, never `git rm` — a removed file archives nothing and reports as an orphan (D6).
4. Never name a file `search.md`, `articles.md` or `categories.md` (D9 mode 2).
5. A new section directory needs a `manifest.yml` entry in the same commit, or phase 1 fails the run (D9 mode 5).
6. A documentation key must not equal a changelog key — `first-release-note` is taken (D9 mode 3).
7. `release_date:` must be a bare ISO-8601 date; a date **with a time** raises `Psych::DisallowedClass` (D9 mode 4).
8. Every file needs a non-empty body (D9 mode 1).

---

## 5. REQUESTED CHANGES — files I do not own

Ordered by urgency. §5.1 is the only one that gates another agent.

### 5.1 — `custom/app/controllers/super_admin/articles_controller.rb` (Agent 2). Merge `meta`, do not replace it.

**Why**: D3. Without it, every Super Admin save destroys `meta['doc_key']`, breaking all 87 Arabic contextual-help
links; and once D1 lands, the accidental repair by the next seed stops happening. With D3a in place, without this
change a seeded article cannot be saved at all.

```diff
   def resource_params
     super.tap do |permitted|
       permitted[:meta] = normalized_meta(permitted[:meta]) if permitted.key?(:meta)
     end
   end
 
-  # The form posts tags as one comma separated string because that is what a text input gives; the model, the
-  # serializer and the public <meta> tag all expect an array.
+  # The form posts tags as one comma separated string because that is what a text input gives; the model, the
+  # serializer and the public <meta> tag all expect an array.
+  #
+  # MERGED onto the stored value, never replacing it. `meta` is one jsonb column holding two writers' keys: the form
+  # offers `feature_image` and the six SEO/release fields (ArticleMetaField::STRING_KEYS), while the content seeder
+  # owns `doc_key` -- the key Documentation::Library#article_for resolves every contextual-help link through, which
+  # the form has no field for. A whole-value replacement destroys it silently
+  # (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D3).
   def normalized_meta(meta)
-    return meta if meta.blank?
+    stored = requested_resource.meta.to_h
+    return stored if meta.blank?
 
     meta = meta.to_h.compact_blank
     meta['tags'] = meta['tags'].split(',').map(&:strip).compact_blank if meta['tags'].is_a?(String)
-    meta
+    stored.merge(meta)
   end
```

**Note for the implementer**: `requested_resource` is Administrate's memoised finder and is available on `update`; on
`create` there is no stored value, so `normalized_meta` must be reached only from the update path or guard on
`requested_resource` being persisted. Agent 2 picks the shape; the contract is only that the stored keys the form does
not offer survive. Do **not** solve this by adding `doc_key` to `ArticleMetaField` — an editable `doc_key` is a second
way to break every help link.

### 5.2 — `custom/app/dashboards/article_dashboard.rb` (Agent 2). Drop `slug` from the form.

**Why**: D4. Editing a slug has no legitimate use; it 404s a previously indexed public URL until the next seed and
then leaves a duplicate row. `slug` stays on `SHOW_PAGE_ATTRIBUTES` and stays searchable.

```diff
-  FORM_ATTRIBUTES = %i[portal category title slug description content locale status position meta].freeze
+  # `slug` is deliberately absent: it is the article's public address, derived from the corpus file name by
+  # Documentation::ContentSeeder#slug_for and reasserted on every run. Editing it here 404s an indexed URL and
+  # creates a duplicate row (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
+  FORM_ATTRIBUTES = %i[portal category title description content locale status position meta].freeze
```

### 5.3 — `deployment/ROLLBACK.md` (Orchestrator-only). Content rollback is a forward seed.

**Why**: D10. Today the document is code-only and reverses no content, so the only available content reversal is the
whole-database restore it itself calls disproportionate.

Add one row to the decision table at `:29-35`:

```diff
 | Slow but correct | No. Investigate; an invalid index from a killed `CREATE INDEX CONCURRENTLY` is the usual cause (deploy.sh step 5 now checks for this). |
+| Documentation content wrong after a seed | **No.** A code rollback reverses no content — this file touches no database. `git revert` the corpus commit and re-run `rails documentation:content`; rows no operator has edited fast-forward back, and rows an operator has edited are reported and left alone. See *Documentation content* below. |
```

And a subsection after *What a rollback cannot undo*:

```markdown
### Documentation content

A code rollback does not roll content back. `rails documentation:content` is an operator step and is not in
`deploy.sh`, so content changes only when someone runs it.

To reverse a documentation change: `git revert` the commit that changed `custom/db/documentation/` (or
`custom/db/changelog/`), deploy or check out that revision, and run `rails documentation:content`. Every row no
operator has edited since the seeder last wrote it fast-forwards back to the reverted text. Rows an operator **has**
edited are reported as `operator_edited` or `conflict` and are **not** touched — deployment never overwrites
operator-authored content, which means it cannot undo it either. Those rows are fixed in Super Admin.

Restoring the pre-deploy dump is **not** the route for wrong documentation content. It loses every message,
conversation and order written since the dump, as described above, and the forward path exists.
```

### 5.4 — `custom/app/dashboards/category_dashboard.rb` (unlisted — Orchestrator to assign). Drop `slug`.

**Why**: D4, third bullet. A renamed category slug makes the next `upsert_category` (`content_seeder.rb:58-64`) create
a **second** section while the renamed one keeps its articles. The section slug comes from `manifest.yml`.

```diff
-  FORM_ATTRIBUTES = %i[portal name slug description locale position icon].freeze
+  # `slug` is deliberately absent: a section's slug comes from custom/db/documentation/manifest.yml and is the
+  # seeder's lookup key, so renaming it here creates a duplicate section
+  # (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
+  FORM_ATTRIBUTES = %i[portal name description locale position icon].freeze
```

I also note, without proposing a change, that `config/routes/documentation.rb:9` is a bare `resources :categories` —
full CRUD including `create` and `destroy` — so an operator can destroy a documentation section; the seeder recreates
it from the manifest on the next run with a new id, and the articles that pointed at it keep a dangling `category_id`
(there is no foreign key on it, per `article.rb:131-133`). Whether to narrow that route is the Orchestrator's, since
routes are Orchestrator-only.

### 5.5 — `deployment/deploy.sh` (Orchestrator-only). A read-only drift print at stage 8.

**Why**: D9 and R12's first ordered item. Production sat two articles behind HEAD for a whole release and nothing
reported it. This is the detector, and it must **not** fail the deploy: a non-zero exit at stage 8 trips the
`RESTARTED=1` trap branch, which tells the operator to roll back (`deploy.sh:48-49`) — disproportionate for
documentation drift, and exactly the mistake D11 refuses for the SEO audit.

In stage 8, beside the existing verification `rails runner` calls, after the health and unit checks:

```bash
# Documentation drift is reported, never enforced: the content seed is an operator step (documentation:content is
# not in this script), so drift here is information for the post-deploy checklist, not a reason to roll back a
# healthy revision. `|| true` is deliberate.
as_app 'RAILS_ENV=production bundle exec rake documentation:drift' || true
```

### 5.6 — `lib/tasks/documentation_seo_audit.rake` (Agent 4). Default to the platform portals.

**Why**: D11. Unqualified, the task iterates every non-archived portal including tenants', so a customer's own
help-center article can produce an error in a report about Lynomia's documentation. One line, no behaviour change for
anyone who sets `PORTAL_SLUG`.

```diff
-      portals = Portal.where(archived: false)
-      portals = portals.where(slug: ENV.fetch('PORTAL_SLUG')) if ENV['PORTAL_SLUG'].present?
+      # The platform's own documentation by default. A tenant's help center is their content, and a short description
+      # there is not a finding about Lynomia's documentation -- nor a reason to fail anything.
+      portals = Documentation::Library.portals
+      portals = Portal.where(archived: false).where(slug: ENV.fetch('PORTAL_SLUG')) if ENV['PORTAL_SLUG'].present?
```

### 5.7 — `config/locales/en.yml` (Orchestrator-only). One backend string for D3a.

```yaml
en:
  errors:
    articles:
      doc_key_required: "must keep its doc_key: this article comes from a documentation file and the product's help links resolve through that key"
```

English only; other locales go through Crowdin. It sits beside the existing
`errors.articles.category_portal_mismatch` already referenced at `article.rb:149`.

### 5.8 — `docs/documentation-v2/P0-POST-DEPLOY-OWNER-CHECKS.md` (unlisted — Orchestrator to assign).

**Why**: D9 keeps the seed an operator step, so the checklist is where it lives or it is nowhere — which is the
condition that produced the original defect. Add, after the existing checks:

```markdown
- [ ] `rake documentation:drift` — reconciliation line matches the release (file count, section count, tracked rows);
      no orphans you did not expect.
- [ ] If the release changed `custom/db/documentation/` or `custom/db/changelog/`:
      `rake documentation:content`. Phase 1 writes nothing and exits non-zero on a bad file; read the per-class
      report. `conflict` rows are not written — resolve each in Super Admin or by editing the file, never by
      re-running with a wider flag.
- [ ] First run after the provenance migration only: `ADOPT_UNTRACKED=1 rake documentation:content`, and check the
      `adopted` count equals the corpus file count.
```

---

## 6. OPEN — needs the owner

1. **Should a deliberate URL change be possible at all, and therefore do we need redirects?** D4 makes a file rename
   safe — no 404, one `created` plus one reported `orphan` — and that is why I ruled redirects out of P2 rather than
   building a mechanism. But it means a URL, once published, is effectively permanent: to change it you publish a new
   file and retire the old one, and the old URL then serves an archived article, which the public read paths treat as
   absent (`library.rb:42-44`; `public/api/v1/portals/articles_controller.rb:13,30,39,84`) — **so a retirement 404s the old
   URL even though a rename does not**. For a corpus about to grow several times over that may be too rigid.
   *The question, plainly:* is "a published documentation URL never changes, and withdrawing an article 404s it"
   acceptable, or should P2 carry a slug-alias redirect? My recommendation is to accept it for P2 and, if the answer
   is redirects, to put them in Agent 4's SEO stream as a `meta['previous_slugs']` array consulted by a 301 in the
   public articles controller — not in the seeder, and not as a new table.

2. **Does any production row carry an operator edit today?** D7's adopt path exists because I cannot answer this: it
   is a fact about production data I am forbidden to read (§3), and an absence claim about data cannot be established
   from the repository. If the owner can confirm that no documentation article has ever been edited in Super Admin,
   the adopt run is provably lossless and the gate is a formality. If any have been, the adopt run **will** overwrite
   them, and the operator should record those rows first.
   *The settling query, read-only:*
   `SELECT id, slug, locale, status, updated_at FROM articles WHERE portal_id IN (SELECT id FROM portals WHERE platform_owned) ORDER BY updated_at DESC LIMIT 20;`
   — an `updated_at` noticeably later than the rest, or a row whose `meta` lacks `doc_key`, is an edited row.

3. **Is production's corpus actually 124 rows?** R12 verified from git that the cited `38/19/67` run processed a
   124-file tree while baseline HEAD holds 126, and concluded the Platform Support Desk's two articles are very likely
   absent in production. I confirmed the tree is 126 files today. The remaining step is production, and it is one
   query:
   `SELECT p.slug, a.locale, count(*) FROM articles a JOIN portals p ON p.id = a.portal_id WHERE p.platform_owned GROUP BY 1,2;`
   Expected after a correct seed: `lynomia-docs/en 63`, `lynomia-docs/ar 63`, `lynomia-changelog/en 1`,
   `lynomia-changelog/ar 1`. This is already on the owner list; I repeat it because D7's adopt count is checked
   against it.

4. **Should `documentation:content` ever become automatic, once the drift detector exists?** D9 says no for P2 and I
   am confident in that for this wave. But R12's ordering implies the question reopens once a detector and a
   convergence spec exist, which is exactly what this contract delivers. I am not pre-deciding a later wave. The
   constraint that would have to hold first: a drift print that has been correct across several real deploys.

---

## 7. The absence claims, with their five steps

`00-program.md` §2.3 requires each of these to be established, not asserted. Each ran with **no exclusion filter**;
`.git` and `log/` are excluded from the *display* only, and their hits are classified below.

**A. "Nothing preserves `meta` keys the Super Admin form does not post."** (D3)
Search: `grep -rn "doc_key" .` — 27 files. Classified: `custom/app/services/documentation/content_seeder.rb:107`
(the only writer); `custom/app/services/documentation/library.rb:55` (the only reader);
`spec/requests/documentation/entry_points_spec.rb`, `spec/custom/services/documentation/content_seeder_spec.rb` (2
assertions); 22 files under `docs/` (prose); `log/test.log` (30 hits, all captured `INSERT` statements from past
spec runs — generated output, not code). **Aliases, helpers, concerns and config republication followed**:
`Article.include_mod_with('Concerns::Article')` (`article.rb:300`) resolves through
`each_extension_for` (`config/initializers/01_inject_enterprise_edition_module.rb:69-79`) and no `Concerns::Article`
module exists — `./app/models/article.rb` is the only `article.rb` model in the tree and there is no `enterprise/`
tree. The camelCase alias `docKey` was searched separately and appears in no Ruby file. **Chain inspected**: form view
→ `permitted_attribute` → Administrate `permit` → `normalized_meta` → `update` → jsonb column, and the consumer side
`library.rb:55` → `documentation_controller.rb:22-23` → 404 → `documentationLinks.js:11`. **Negative stated**: no
merge exists on any path.

**B. "`documentation:content` is in no deploy path, job, controller or CI workflow."** (D9)
Search: `grep -rn "ContentSeeder\|PortalSeeder" .` → 9 hits: `content_seeder.rb:9` and `portal_seeder.rb:7` (the class
definitions), `documentation.rake:5,12,18` (three call sites), two spec files, `article.rb:162` (a comment),
`spec/controllers/.../articles_controller_spec.rb:224` (a comment). `grep -rn "documentation:content\|documentation:setup\|documentation:changelog" .`
adds only prose and comments. `grep -rn "documentation\|seo_audit\|corpus" .github/workflows/` over all 16 workflow
files returns two hits, both `--format documentation` (RSpec's output formatter) in `run_mfa_spec.yml:75,89`.
`deployment/deploy.sh` contains no occurrence of `documentation`. **Negative stated**: three call sites, two of them
specs, and the third is the operator's rake task.

**C. "No provenance column or `meta` key exists."** (D2)
Search: `grep -rni "content_source|source_path|provenance|managed_by|origin|file_path|content_digest|content_checksum"`
over `db/migrate`, `custom/db/migrate`, `db/schema.rb`, `app/models/article.rb`, `app/models/category.rb` and all of
`custom/app/` → 5 hits, each classified and unrelated (§D2). Cross-checked against the full column list in
`db/schema.rb`'s `create_table "articles"` and the annotation at `article.rb:1-34`. **Negative stated.**

**D. "`Article` is not audited."** (D2)
Search: every `audited` declaration under `custom/app/models/` and in `app/models/article.rb` → 17 hits across 16
models, none of them `Article`. `custom/app/models/custom/audit/` holds 14 files and there is no `article.rb` among
them. The `include_mod_with` chain is followed in (A). **Negative stated**: no audit trail records who changed a
documentation article, which is why D2's provenance is a column and not an inference.

**E. "Nothing in this repository emits the tracking-pixel URL."** (D9)
Search: `grep -rn "tracking_pixel\|tracking-pixel" .` → 4 hits, every one classified: `config/routes.rb:516` (the
route), `app/controllers/public/api/v1/portals/articles_controller.rb:7` (a `before_action` exception), `:38` (the
action), `:49` (the asset path). No `.erb`, `.vue` or `.js` hit. **Negative stated — and deliberately narrowed**: no
*view or script in this repository* emits it. That is **not** "`increment_view_count` is never called", which is how
098 stated it; the route is a live unauthenticated public GET and any external client reaches it. The step-4
chain inspection (server → view → runtime) is precisely what distinguishes the two, and the conclusion I draw from it
(D9: no wrapping transaction, because phase 1 removes the need rather than because the writer does not exist) does not
depend on which is true.

---

## 8. Status

**Frozen.** Agents 2 and 3 are unblocked. Nothing here is implemented: this wave is design, and the only code in this
document is the diffs in §5 — none of which I have applied — and the sketches in D2, D3a and D8, which land in my own
files in the implementation wave.

One thing in this contract is **UNVERIFIED by measurement** and is flagged at the point of use: the two-run
convergence probe for D8, because PostgreSQL is down in this environment. The derivation is in D8 and the exact probe
is named there. Every other claim carries a `file:line` that can be read without a database.
