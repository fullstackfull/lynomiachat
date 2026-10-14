# P2 — the source-of-truth and deployment-sync contract, frozen

> **REVISED AND IMPLEMENTED IN WAVE 3.** Owner correction `P2-WORKSTREAM-OWNERSHIP.md` §F2 replaced this
> contract's single `content_digest` with a **field-by-field** model, and §2A below is the authoritative
> statement of it — it is what the code does. Where a decision in §2 disagrees with §2A, §2A wins, and each
> affected decision now carries its own correction at the point of use (D1, D3, D4, D5, D6, D7, D8, D9, D11).
> Four of this document's wave-1 conclusions are **withdrawn on measurement** and say so where they stand:
> the `platform_owned?` position guard (D8), the `slug` reassertion (D4), the `doc_key` validation (D3a) and
> the two new front-matter keys (D6).

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

## 0A. How wave 3 was verified — PostgreSQL was up this time

| Method | What it covered |
|---|---|
| Measurement, real corpus | both seed tasks run twice over against the shipped 69/69 corpus in the test database; an operator edit (title, status, tags, feature image) surviving a full seed; the untracked refusal and its non-zero exit; the adopt run after it |
| Measurement, fixture probes | the section move, before and after the fix, with the callback instrumented (D8); every runtime write path to `articles.slug`, including a `PUT` that carries one (D4) |
| Specs | `spec/custom/services/documentation/content_seeder_spec.rb`, 31 examples, extended from 17 |
| Absence-rule searches | four no-exclusion searches for writers of `articles.slug` (§7F), one for writers of `articles.meta` (D3), and the front-matter key inventory behind D6 |
| Not measured | anything about production data (§6.2 stays open), and the five D9 abort modes, which wave 3 does not change |

**Everything below this line is the wave-1 document, with wave-3 corrections inline.** §0's statement that
PostgreSQL was down applies to wave 1 only. Two reading notes: §1 and every paragraph headed **Today** describe
`content_seeder.rb` **as it was before wave 3**, and that file was rewritten, so its line citations in those
paragraphs locate the old behaviour rather than a current line — the wave-3 blocks cite the current file. Line
citations to every other file were re-checked against the tree while writing this revision.

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

## 2A. The field-by-field model, as implemented

Owner correction §F2: a `content_digest` protects `content` and nothing else, and **nine fields have two
writers**, so a content-only digest reverts an operator's title, description, position, status and SEO metadata
while the digest still matches. The classification below is what `Documentation::ContentSeeder` now obeys. **No
row of §F2.1's proposal changed**; one field §F2.1 left to §F2.2 is now classified (`slug`, class D, see D4) and
the class-C *rule* gained one clause, so no field is unclassified.

| Class | Field | Where the other writer is | Rule the seeder follows |
|---|---|---|---|
| **D** identity / provenance | `portal` | not on the form as a documentation portal change (`article_dashboard.rb:17` scopes it to `Documentation::Library.portals`) | the lookup scope; never written |
| **D** | `locale` | on the form, but `ensure_locale_in_article` (`article.rb:289-295`) overrides it from the category | the lookup key; never written |
| **D** | `slug` | **off the form since wave 2** (`article_dashboard.rb:42-47`); the only in-model writer is `ensure_article_slug`'s `\|\|=` (`article.rb:323-325`) | the lookup key, derived from the file's basename; never written. §F2.1 left this one to §F2.2; D4 answers it |
| **D** | `meta['doc_key']` | not on the form; `ArticleMetaField::MANAGED_KEYS` (`article_meta_field.rb:37`) excludes it and `merge_submitted` (`:50-55`) carries it through | **reasserted on every run** from the file's basename |
| **D** | `content_source_path` | never a form field | written on create and on adoption, and re-pointed when the file moves section |
| **A** repository-owned | `content` | form (`article_dashboard.rb:47`) | the corpus wins on every run |
| **A** | `category` | form | the corpus wins on every run |
| **A** | `associated_article_id` | not on the form | reasserted for every non-default locale, as before |
| **B** operator-owned | `status` | form, three states (`article_dashboard.rb:27`) | **written on create only.** The file does not express it |
| **C** mergeable | `title`, `description`, `position` | form | written while the row still holds what the seeder last wrote there |
| **C** | `meta['title']`, `meta['description']`, `meta['tags']`, `meta['version']`, `meta['release_date']` | form (`article_meta_field.rb:11-13`) | the same rule, per key |
| — | `meta['feature_image']` | form only (`article_meta_field.rb:13`) | the seeder never writes or removes it |
| — | `author` | not on the form | `\|\|=`, as before |
| — | `views`, `draft_title`, `draft_content`, `folder_id` | not on the form | never touched |

**`seeded_digests`, the one new mechanism.** A jsonb column holding one SHA-256 per class-C field of the value
the seeder last wrote there:
`Digest::SHA256.hexdigest(JSON.generate([DIGEST_VERSION, field, canonical_value]))`, with `DIGEST_VERSION` first
so that changing what a digest covers invalidates every stored digest loudly instead of reclassifying rows
silently, and `canonical_value` normalising `nil` against `""` — which matters because Administrate's
`read_param_value` (`administrate-0.20.1/app/controllers/administrate/application_controller.rb:209-224`) turns a
blank input into `nil` while a file yields `""`. It is a **digest, never the value**: no second copy of the
content, no revision table, no second CMS. §F2.3's requirement that this be a generalisation of the accepted
digest direction rather than a new store is met by that sentence.

**The rule, exactly.** For each class-C field, with `current` = the digest of the row's value now:

| Condition | Meaning | Action |
|---|---|---|
| `current == seeded_digests[field]` | the row still holds what the seeder wrote | write the file's value, record its digest |
| `current == digest(file value)` | the operator and the corpus now agree | nothing to write; **re-attach** by recording the digest |
| otherwise | an operator edited it | **leave it**, keep the old digest, and **report the field** |

The middle row is new and is not in §F2.1. Without it a field stays reported as divergent for ever once edited,
even after the corpus catches up with the same text — and that, not a flag, is what lets a row converge again.
It also removes the need for the `ACCEPT_FILE=<slug>` override D5 proposed (withdrawn, see D5).

**A row with no digests is `untracked`, and is not written.** Every production row is in that state the moment
the migration lands, and nothing in the repository can tell a previous seed's own writing from an operator's
edit. The run reports those rows and exits non-zero; `ADOPT_UNTRACKED=1 rails documentation:content` is the
operator saying once, by hand, that the corpus wins. Adoption is **not** creation: it does not write `status`,
so an article an operator withdrew before the migration stays withdrawn.

**The report** (`lib/tasks/documentation.rake`), per run, in the shape the seeder already had:

```
articles: 0 created, 3 updated, 130 unchanged, 0 adopted, 0 untracked (en, ar)
  operator_edited  ar  connect-whatsapp-ar  custom/db/documentation/ar/whatsapp/connect-whatsapp.md  title, meta.tags
```

`created + updated + unchanged + adopted + untracked` is one outcome per file processed, so it reconciles against
the corpus on disk. A row can be `updated` **and** carry a divergence in the same run: class A is written while a
class-C field the operator owns is left alone. That is the owner's constraint — *deployment must never silently
overwrite operator-authored content* — made checkable by a human rather than asserted in a comment.

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

> **CORRECTED BY §F2 AND IMPLEMENTED AS §2A.** The row-level three-way table above is **not** what shipped, and the
> owner's correction is why: a whole-row class makes the merge all-or-nothing, so one edited title would have frozen
> that row's prose against every future corpus correction, and an unedited title would still have been reverted by a
> content change. The shipped model is the same construction applied **per field** — the merge base is
> `seeded_digests[field]` instead of one `content_digest`, and the four classes above become per-field outcomes.
> Everything D1 promised Agents 2 and 3 still holds, field by field: an operator's save is durable, and a corpus
> change reaches a field only when the operator has not taken that field over.

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
class AddContentProvenanceToArticles < ActiveRecord::Migration[7.2]
  def change
    add_column :articles, :content_source_path, :string
    add_column :articles, :seeded_digests, :jsonb, default: {}, null: false
    add_index :articles, :content_source_path, unique: true
  end
end
```

- **`content_source_path`** — the corpus file that owns this row, relative to `Rails.root`, e.g.
  `custom/db/documentation/en/getting-started/welcome-to-lynomia-chat.md`. NULL means no file owns it: every tenant
  article, and every row an operator authored by hand.
- **`content_digest`** — SHA-256 hex (64 chars) of the canonical seeded-attribute tuple, as the seeder last wrote it.
  NULL means the seeder has never tracked this row.
  **SHIPPED INSTEAD, per §F2:** `seeded_digests`, `jsonb, default: {}, null: false` — one SHA-256 **per class-C
  field** (§2A). An empty hash on a persisted row means the seeder has never tracked it. The name changed with the
  shape deliberately: a column called `content_digest` holding eight entries invites exactly the misreading — "the
  digest covers the content" — that owner correction §F2 exists to kill.
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
  `Documentation::Library#article_for` queries it as `articles.meta->>'doc_key'` (`library.rb:63`) — Agent 4's file.
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
   repository: `content_seeder.rb:107` writes it, `library.rb:63` reads it (§7). There is no `Concerns::Article`
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

> **D3a IS WITHDRAWN. D3b SHIPPED IN WAVE 2 AND IS WHAT CLOSED THIS.**
>
> Wave 2 landed the fix one layer better than §5.1 asked: the merge lives on the **field**, not in the controller.
> `ArticleMetaField::MANAGED_KEYS` (`article_meta_field.rb:37`) is every key the form posts, and
> `merge_submitted` (`:50-55`) returns `stored.except(*MANAGED_KEYS).merge(normalize(submitted))` — so the only
> keys a submission can set are the ones the form owns, and `doc_key` is carried through from storage by
> construction. `SuperAdmin::ArticlesController#resource_params` (`articles_controller.rb:52-56`) calls it;
> `#stored_meta` (`:67-69`) handles create, where there is no stored row. Measured: a `PUT` that edits only the
> title keeps `doc_key` (`spec/controllers/super_admin/documentation_editor_spec.rb:27-35`).
>
> So the model validation D3a proposed would now guard a path **no live writer can reach**, and CLAUDE.md forbids
> exactly that. The full no-exclusion search for writers of `articles.meta` on a documentation row: the seeder
> (`content_seeder.rb`), the Super Admin form (merged, above), and
> `Api::V1::Accounts::ArticlesController#article_params` (`articles_controller.rb:110`), which permits
> `meta: [:title, :description, {tags: []}]` and **replaces** the column — but `Custom::ArticlePolicy#update?` is
> `false` (`custom/app/policies/custom/article_policy.rb`, in `ArticlePolicy.ancestors`, measured) so every tenant
> article verb is refused with `401`
> (`spec/controllers/api/v1/accounts/articles_controller_spec.rb:68-115`), **and** `portal` there is
> `Current.account.portals.find_by!` (`:90-92`) which cannot return an account-less platform portal — measured
> `404`, and `account.portals.exists?(platform portal) == false`.
>
> The seeder instead **reasserts** `meta['doc_key']` from the file's basename on every run (§2A, class D). That is
> not a backup guard: it is the corpus owning an identity field, in the one line that already builds the hash, and
> it repairs any row whose key was destroyed before wave 2 closed that path
> (`spec/custom/services/documentation/content_seeder_spec.rb`, "reasserts doc_key on a row whose key was
> destroyed").
>
> **One thing this does NOT do, stated plainly**: it does not stop a *future* writer from replacing `meta`. If
> Agent 2 or anyone else adds a second write path to that column, the model validation becomes the right answer
> again and the evidence for it is this paragraph.

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

> **DECISION 1 IS WITHDRAWN, AND §F2.2's PROVENANCE LOOKUP IS NOT NEEDED. The lookup stays `(slug, locale)`.**
>
> §F2.2's premise was that `slug` is both the identity lookup and an operator-editable form field, so a rename
> makes the next seed create a duplicate. **Wave 2 removed the second half**: `slug` left
> `ArticleDashboard::FORM_ATTRIBUTES` (`article_dashboard.rb:42-47`, citing this decision). The question is
> therefore whether any live path can still change `articles.slug` on a documentation row, and that is an absence
> claim, so it is established in the five steps `00-program.md` §2.3 requires.
>
> **(1) No-exclusion search.** Four patterns over the whole tree with no path exclusions:
> `(self\.slug|\.slug)\s*(\|\|)?=[^=]` across `*.rb *.erb *.rake *.jbuilder` → **2 hits**;
> `permit(|permitted_attributes|FORM_ATTRIBUTES` lines containing `slug` → **4 hits**;
> `update_column|update_columns|update_attribute|write_attribute|['slug']=` containing `slug` → **0 hits**;
> every `Article`/`articles` create-or-initialise site → **4 hits**.
>
> **(2) Every hit classified.**
>
> | Hit | What it is |
> |---|---|
> | `app/models/article.rb:324` | `ensure_article_slug`, `self.slug \|\|=` — writes only when the slug is **nil** |
> | `vendor/.../ruby_llm-2.0.0/lib/ruby_llm/provider.rb:557` | a gem's own class attribute; not this table |
> | `app/controllers/api/v1/accounts/articles_controller.rb:110` | the tenant API permits `:slug` — **the only live permit that does**; reachability below |
> | `app/controllers/api/v1/accounts/portals_controller.rb:97` | `Portal#slug`, a different table |
> | `app/controllers/api/v1/accounts/categories_controller.rb:56`, `custom/app/dashboards/category_dashboard.rb:25` | `Category#slug`, a different table (§5.4 still stands) |
> | `app/controllers/public/api/v1/portals/articles_controller.rb:109` | `params.permit` for a **read** filter, not a model write |
> | `custom/app/services/documentation/content_seeder.rb:115` | the seeder's own lookup; it writes no slug |
> | `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:44` | `slug` used to find the portal; the bulk verbs write status, category and translations |
>
> **(3) Aliases, helpers and config publication followed.** `Article.include_mod_with('Concerns::Article')`
> (`article.rb:327`) resolves through `each_extension_for`
> (`config/initializers/01_inject_enterprise_edition_module.rb:69-79`) and **no `Concerns::Article` module exists
> anywhere in the tree** (re-checked: no `module Concerns` under `app`, `custom` or `lib`, and there is no
> `enterprise/` tree). Administrate's `permitted_attributes` is built **only** from `form_attributes`
> (`administrate-0.20.1/app/dashboards/../base_dashboard.rb:53-84`), which is `FORM_ATTRIBUTES` unless a
> `FORM_ATTRIBUTES_EDIT`/`_NEW` constant exists — measured: both `const_defined?` are **false**. There is no
> platform-API articles controller (`app/controllers/platform/api/v1/` holds five controllers, none for articles).
>
> **(4) The runtime path inspected, not inferred** — measured in this container:
>
> ```
> A5-4 super_admin status=302 slug="audit-logs" title="Edited"
> A5-4 administrate_permitted=["portal_id", "category_id", :title, :description, :content, :locale, :status,
>                             :position, {meta: [...]}]
> A5-4 form_attributes_edit_const=false form_attributes_new_const=false
> A5-4 tenant_api_own_portal status=401 slug="tenant-article"
> A5-4 tenant_api_platform_portal status=404 slug="audit-logs"
> A5-4 platform_portal_in_account_scope=false
> A5-4 article_policy_update=false ancestors_include_custom=true
> A5-4 ensure_article_slug on_new="1791933346-nameless" on_existing_after_title_change="audit-logs"
> ```
>
> A `PUT /super_admin/articles/:id` carrying `slug` **and** `title` succeeds, changes the title and leaves the slug
> alone — the slug param is dropped, not honoured.
>
> **(5) The claim.** *No live path writes `articles.slug` on a row that already has one.* The seeder's
> `find_or_initialize_by(slug:, locale:)` is therefore as stable an identity as `content_source_path` would be, and
> a provenance-based lookup would buy nothing while costing a second lookup path — because every production row has
> a NULL `content_source_path` until it is adopted, so the provenance lookup would have to fall back to the slug
> anyway. **Decision 1 of D4 is withdrawn with it**: reasserting `slug` on every run was only meaningful under a
> provenance lookup, and under the slug lookup it is a write of the value the row was just found by.
>
> Decisions 2, 3 and 4 of D4 stand unchanged: `slug` stays off both forms, a **file** rename is still one `created`
> plus one stale row, and redirects stay out of P2. One thing D4 claimed is now **narrower than the code**: the
> stale row after a file rename is *not* reported, because wave 3 does not implement the orphan report (D11, D9).
> That is an open item, not a silent omission.

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

> **AS IMPLEMENTED, with two changes and one deferral.**
>
> The per-row `conflict` class is **gone**, because §F2 made the classes per field: a row is not conflicted, a
> *field* is. The shipped report is in §2A and measured on the real 138-file corpus:
>
> ```
> articles: 0 created, 0 updated, 137 unchanged, 0 adopted, 1 untracked (en, ar)
>   untracked        en  welcome-to-lynomia-chat  custom/db/documentation/en/getting-started/welcome-to-lynomia-chat.md
>   operator_edited  en  audit-logs               custom/db/documentation/en/administration/audit-logs.md  title, meta.tags
> ```
>
> **`ACCEPT_FILE=<slug>,<slug>` is withdrawn.** §2A's middle rule — a field re-attaches when the row already holds
> what the file says — gives the operator two resolutions that need no new mechanism and no new flag: edit the file
> to match the row, or edit the row to match the file. A named-override flag would be a third way to do what those
> two already do, and CLAUDE.md's smallest-change rule rules it out. `ADOPT_UNTRACKED=1` stays, because nothing
> else can answer *who wrote this row before provenance existed*.
>
> **Exit status, as implemented:** non-zero on `untracked` only — measured `EXIT=1` with the instruction block
> printed. `operator_edited` prints and exits zero, for the reason given above.
>
> **Deferred, and not implemented in wave 3: the reconciliation line and the orphan list.** The counts
> `created + updated + unchanged + adopted + untracked` already reconcile one-to-one against the files processed
> (measured: 138 against a 69/69 corpus), which is the half that catches "I missed two files". The other half —
> tracked rows whose file is **gone** — needs a pass over rows rather than over files, and it is the
> `documentation:drift` task of D11. It is an open item, named in §6, not a silent omission.

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

> **NARROWED AS IMPLEMENTED: the `status` rule shipped; the two front-matter keys are WITHDRAWN.**
>
> What shipped is class B exactly as §F2.1 states it: `status` is written **on create only**, from the seeder's
> existing `publish:` constructor flag, and never on an update or an adoption. Measured on the real corpus: an
> article set to `draft` in the database stays `draft` through a full seed, where before this change every run
> forced every article to `published`.
>
> `published:` and `retired:` are withdrawn because **no corpus file uses either key**. Measured over the whole
> shipped corpus, every front-matter key in use is: `title` (134), `tags` (134), `seo_description` (134),
> `position` (134), `description` (134), `seo_title` (28) — and nothing else, in either locale. Implementing a key
> no file carries is dead code by CLAUDE.md's rule, and the `retired:` half would also have been the one place
> where the corpus is allowed to override an operator's publication choice, which is a real behaviour to add on
> evidence rather than on anticipation.
>
> **Consequence, stated plainly rather than left implied:** there is now **no corpus-side way to withdraw an
> article.** Deleting a file still archives nothing (that part of D6 stands and is deliberate), and `retired:` does
> not exist, so withdrawal is an operator action in Super Admin — which is durable now, and which is the one
> direction class B makes safe. Open item in §6; the thing that closes it is a corpus that actually needs to
> retire an article.
>
> **Agent 3: do not write `published:` or `retired:` in front matter.** They are silently ignored. If a file needs
> to ship unpublished, say so and the key lands with the file that needs it.

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

> **AS IMPLEMENTED: the digest is per field (§2A), and D7's own defect is fixed in one line.**
>
> The single six-input tuple above is replaced by one digest per class-C field, and the properties it was carrying
> move with it: `content` is **not** digested at all (it is class A — the corpus always wins, so there is nothing
> to decide), the category is **not** digested (class A), `status`, `slug`, `locale`, `author`, `views`, the draft
> columns and `meta['feature_image']` are still outside, and the `.to_s` normalisation and `DIGEST_VERSION`-first
> rule are kept verbatim because both reasons still hold. `meta` is no longer sliced-then-digested as a hash: each
> key is its own field, which is what makes "an edited SEO title does not freeze the tags beside it" true.
>
> **D7's measured defect, fixed:** `changed = article.changed?` was read at the old `:78`, **before**
> `article.author ||= author` and before `save!`. It is now read after every assignment, so a row whose only write
> was its author is no longer reported `unchanged`. The second half of that defect — the `after_save` position
> callback writing after the flag was read — is addressed by D8 instead, and the `unchanged` count is now reliable:
> measured on the real corpus, a second consecutive run reports **`0 created, 0 updated, 138 unchanged`**.
>
> **The untracked/adopt path shipped as described**, with `seeded_digests == {}` standing in for the NULL digest.
> Measured end to end on the real corpus: `1 untracked` with `EXIT=1`, then `1 adopted` under `ADOPT_UNTRACKED=1`,
> and the operator-edited row beside it still reported and still untouched.

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

> **VERDICT, MEASURED. The `platform_owned?` guard is WITHDRAWN. "Oscillation" is withdrawn. The one-run
> non-convergence is REAL, and it is repaired in the seeder.**
>
> §E2 refuted the finding by measuring a **stable** corpus, where the predicate `saved_change_to_category_id?` is
> false and the callback body never runs — so a guard inside it would guard a path that does not execute, which
> CLAUDE.md forbids. That refutation stands, and the guard is not shipped. What §E2 could not exercise is a
> **section move**, so I built that probe: two manifest sections, three articles, the destination section already
> occupied so `max + 10` is not the same number as the front matter's.
>
> **Before any change** (the code as §E2 left it):
>
> ```
> A5-3 run0 counts=[3,0,0] positions={"connect"=>[10, 31], "second"=>[20, 30], "welcome"=>[10, 30]}
> A5-3 run0 callback_fired=[["second", 20], ["welcome", 10], ["connect", 10]]
> A5-3 run1 counts=[0,1,2] positions={"connect"=>[10, 31], "second"=>[20, 30], "welcome"=>[20, 31]}
> A5-3 run1 callback_fired=[["welcome", 10]]
> A5-3 run1 welcome_position=20 front_matter_position=10
> A5-3 run2 counts=[0,1,2] positions={"connect"=>[10, 31], "second"=>[20, 30], "welcome"=>[10, 31]}
> A5-3 run2 callback_fired=[]
> A5-3 run3 counts=[0,0,3] positions={"connect"=>[10, 31], "second"=>[20, 30], "welcome"=>[10, 31]}
> A5-3 CONVERGED_RUNS_AFTER_MOVE=[[1, 2], [1, 2], [0, 3]]
> ```
>
> Read it exactly: on `run1` the moved article persists `position = 20` while its file says `10`, the run reports
> it `updated`, and the authored value only returns on `run2` — which reports `updated` again. **Two runs to reach
> the file's state, and a public page ordered wrongly in between.** That is the mechanism D8 derived, measured, and
> it is **not** an oscillation: `run3` is `[0 updated, 3 unchanged]` and nothing alternates. Discovery 069/097
> **overstated it** by calling it non-convergence; the accurate name is *one-time, one-run lag after a corpus
> reorganisation*, and §E2 was right that a stable corpus never reaches it.
>
> It is also not hypothetical: wave 3's own corpus change contains one
> (`custom/db/documentation/en/administration/auto-resolve.md` → `.../automation/auto-resolve.md`, a rename across
> sections in `git status`), so the first seed after this wave would have been the run that exercises it.
>
> **And under §F2's merge model it stops being merely cosmetic.** The digest records what the seeder last wrote. If
> the callback's `max + 10` were recorded, the next run would compare the row against the file, see a difference it
> did not write, and classify `position` as **operator-edited** — freezing the authored order for ever and printing
> a divergence nobody caused. The measurement above is therefore load-bearing for the merge, not a side quest.
>
> **The fix: `Documentation::ContentSeeder#converge_position`**, four lines, in my own file. The seeder captures the
> position it decided on immediately before `save!` and restores it after, *only* when the save moved it. Why
> there and not in the model: the callback is product-wide and a tenant Help Center legitimately wants the
> end-of-category default, so the documentation-only writer is the narrower place — the tenant path is untouched by
> construction rather than by a `platform_owned?` predicate. It is one write repairing one write, which D8
> originally rejected on CLAUDE.md grounds; the grounds have changed, because the alternative is now measured to be
> a guard on a path a stable corpus never runs. It also covers the case the model guard could not: when the
> **operator** owns `position`, the restored value is theirs, not the file's.
>
> **After the change**, same probe, same fixture:
>
> ```
> A5-3 run1 counts=[0,1,2] positions={"connect"=>[10, 66], "second"=>[20, 65], "welcome"=>[10, 66]}
> A5-3 run1 callback_fired=[["welcome", 10]]
> A5-3 run1 welcome_position=10 front_matter_position=10
> A5-3 run2 counts=[0,0,3] positions={"connect"=>[10, 66], "second"=>[20, 65], "welcome"=>[10, 66]}
> A5-3 CONVERGED_RUNS_AFTER_MOVE=[[1, 2], [0, 3], [0, 3]]
> ```
>
> One run. The callback still fires — nothing in the shared model changed — and the authored order survives it.
> Pinned by `spec/custom/services/documentation/content_seeder_spec.rb`, "a file that moves between manifest
> sections".

---

### D9 — The seed becomes plan-then-apply. That is what makes the four abort modes unreachable.

**Before this ruling** — every line number in this paragraph and in the table below is the **pre-wave-5** file,
kept because it is the record of what the modes were. `perform!` (`:28-31`) wrote as it walked. There is no transaction — the codebase knows the idiom, since
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

**IMPLEMENTED IN WAVE 5, on owner ruling 3.** The two phases are in the tree
(`content_seeder.rb` — `preflight!`, then `apply!`), there is **no transaction around either**, and the five abort
modes above are no longer reachable: each one is a refusal with the database exactly as the run found it. What the
owner's ruling added to the wave-1 plan is phase C — what an operator sees when a write fails *anyway*.

**The checks, as implemented.** Every one collects its message rather than raising on sight, so one run reports
every offending file; the manifest is the single exception, because nothing derived from an unsound manifest
(a glob, a category) means anything.

| # | Check | Refusal | Mode it closes |
|---|---|---|---|
| 1 | `manifest.yml` section shape: `slug` present, `position` an Integer, a `name` for every locale the section claims | `PreflightError` | the category write failing on a malformed manifest |
| 2 | manifest section set **==** directory set, per seeded locale, both directions | `PreflightError` | **mode 5** (a directory the manifest omits was silently never seeded) and its inverse (an empty category) |
| 3 | every file parses: front matter present, `YAML.safe_load` accepts it | `PreflightError`, with the file and the exception class | **mode 4** (`Psych::DisallowedClass` on a `Time`, `Psych::SyntaxError`) |
| 4 | required fields: `title` present, `position` an Integer, body non-empty | `PreflightError` | **mode 1** (a front-matter-only stub, which `validates :content, if: :published?` refuses) |
| 5 | every intended slug passes `Article::RESERVED_SLUGS` | `PreflightError` | **mode 2**, including its locale asymmetry — `search.md` is refused for `en` and legal as `search-ar` |
| 6 | the intended slug set is unique **within the corpus** | `PreflightError` naming both files | **F7** (two locales deriving one slug) and **F8** (one basename in two sections) |
| 7 | no row outside this run holds an intended slug | `PreflightError` naming the row, its portal and its locale | **mode 3** (a docs key equal to a changelog key) and D4's transient collision |
| 8 | every `media:` image reference is a valid key with a file under `media/` | `PreflightError` | R2-MEDIA-INTERFACE.md §1.4: the resolver answers `nil` and the page publishes the fallback, silently |
| 9 | the class of every tracked row (D1/D7): `kept` per field, and `untracked` or `adopting` | reported, not refused — an untracked row is a state an operator lives in | D1 |

**Three deliberate differences from the wave-1 plan above**, each because the measurement said so:

- Item 2's body check is "non-empty", not "non-empty when the row would be published". An article with no prose is
  a corpus defect at any status, and the state-dependent version would be a branch on a condition no corpus file
  expresses.
- Item 4's cross-corpus half is checked **against the rows**, not against the other corpus on disk. Either way
  nothing partial is written: whichever task runs second refuses before its first write. Reading the other corpus
  would mean reading the other portal's `allowed_locales` to derive its slugs, which is a second seeder's worth of
  logic for a message that names the same collision.
- `content_source_path` is **not** pre-checked. Two corpus files cannot claim one path — the path *is* the file —
  and the only shape that collides is two files swapping basenames inside one run, where both rows are this run's
  own. That is the rows-direction query A5-O2 is open for, and widening into it here was not wanted.

**The no-write property is measured, not asserted.** On a corpus carrying F7, with every `INSERT`/`UPDATE`/`DELETE`
on the connection recorded through `sql.active_record`:

```
statements == []
[Article.count, Category.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count] == [0, 0, 0, 0]
```

The same corpus on the shipped seeder left **3 articles and 2 categories** committed behind an
`ActiveRecord::RecordNotUnique`.

**Phase C — what an operator sees when the apply fails anyway.** The preflight is not omniscient: `position:
2147483648` is an Integer and out of range for an `int4` column, so it passes the preflight and fails the write.
There is no rollback, by the ruling, so the report is the thing that has to be complete:

```
articles: 1 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
articles: APPLY FAILED at custom/db/documentation/en/getting-started/zebra.md: ActiveModel::RangeError: 2147483648 is out of range …
The counts above are everything that completed, and they are committed: nothing was rolled back and no file
after this one was applied. Fix the cause and run the task again -- every write is an upsert on
(slug, locale), so a re-run reapplies the completed rows as `unchanged` and carries on from the file that
failed.
```

`ApplyFailure` carries `where` (the corpus file) and `result` (the counts so far); the task prints both and exits
non-zero, so nothing continues silently. **Rerunnability is measured**: after the failed apply above, fixing the
file and re-running gives `2 created, 0 updated, 1 unchanged` and the three rows the corpus describes.

**Unchanged by this ruling.** The merge model is exactly as §2A shipped — classes A/B/C/D, the digests, the
position convergence — because the ruling is about *when* writes happen and *what is reported*, not about which
side wins a field. `documentation:content` still does **not** run in `deployment/deploy.sh`; the §5.5 drift print
is still a requested change and still depends on the deferred `documentation:drift` task.

**One reporting gap closed with it.** An `ADOPT_UNTRACKED` run printed `N adopted` and no divergence line
(P2-WORKSTREAM-OWNERSHIP.md A6-O1), so an operator never learned which fields the corpus took back. There is now
an `:adopted` divergence carrying the class-C fields whose stored value the corpus replaced:

```
articles: 0 created, 0 updated, 2 unchanged, 1 adopted, 0 untracked (en, ar)
  adopted  en  welcome  custom/db/documentation/en/getting-started/welcome.md  title
```

Class A is deliberately absent from that list: the corpus owns prose and placement on every run for every row, so
reporting it under `adopted` would report the design rather than the consequence of adopting.

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
| `documentation:content` | the field-by-field merge of §2A; the report below; **non-zero on `untracked`**; honours `ADOPT_UNTRACKED=1` |
| `documentation:changelog` | identical semantics against `CHANGELOG_ROOT`, including `ADOPT_UNTRACKED=1`. Measured: `2 created`, then `2 unchanged` |
| `documentation:drift` | **NOT IMPLEMENTED in wave 3.** See D5 and §6: the half it was for that the summary line cannot do is the orphan direction, rows whose file is gone |

**As implemented** (the row above is the shipped surface, not a plan): no phase 1, no `ACCEPT_FILE`, no
`conflict` class, no `retired` count, no `orphans` array — each withdrawn or deferred at its own decision, with the
reason there. `Result` is
`created, updated, unchanged, adopted, untracked, locales, divergences`; `created`, `updated` and `unchanged` keep
their names, `locales` is now actually populated (it was declared and never written), and `divergences` is an array
of `Divergence(kind, locale, slug, path, fields)` with `kind` one of `:operator_edited` or `:untracked`.

**One operational note that is not mine to fix and is already fixed.** Until the Orchestrator moved
`DocumentationSeoAudit` into `lib/documentation_seo_audit.rb`, a `.rake` file in this repository referenced an
autoloadable constant in a class body, and `Rails.application.load_tasks` runs **before** the application is
initialized — measured here as `Rails.application.initialized? == false` with the constant undefined at that
point. That raised `NameError` out of task loading and broke **every** rake task, `db:migrate` and
`assets:precompile` among them. The report module in `lib/tasks/documentation.rake` therefore names no application
constant, and says so in a comment, so this task cannot reintroduce it.

---

## 4. What Agents 2 and 3 can now rely on, in one place

**Rewritten for what wave 3 actually shipped.** Every line here is true of the code in the tree.

**Agent 2 (editor).**
1. An operator's save is **durable, field by field**. No deploy reverts `title`, `description`, `position`,
   `status` or the SEO keys once the operator has touched them (§2A). `content` and `category` are **not**
   durable: the corpus owns them and a deploy will revert an edit to either. Design for exactly that split — and
   if the editor is going to let an operator change the body, it should say that the corpus wins there.
2. `content_source_path` and `seeded_digests` are **never** form fields; the seeder owns both. Neither is in
   `ArticleDashboard::ATTRIBUTE_TYPES`, so Administrate cannot permit them.
3. `slug` is off the form and stays off (D4). `doc_key` is **displayed, not editable** — and it is now reasserted
   by the seeder on every run, so a row whose key was lost before wave 2 repairs itself on the next seed.
4. `meta` merging is **done** (wave 2, `ArticleMetaField.merge_submitted`), and the model validation this contract
   proposed for it is withdrawn — see D3. If you add a second write path to `articles.meta`, that validation
   becomes necessary again.
5. `status` stays editable and the operator's choice is now permanent — including through an adoption (D6).
6. Showing provenance is still worth doing (D5), and it is now one column plus one derived fact:
   `content_source_path` (or "authored in Super Admin" when NULL) and, if you want the per-field state,
   `seeded_digests.keys` is the list of fields the seeder is still tracking.

**Agent 3 (content).**
1. The file basename is the `doc_key` **and** the public URL. Renaming it is a URL change (D4).
2. **Do not write `published:` or `retired:` in front matter** — withdrawn, and silently ignored (D6). There is no
   corpus-side way to withdraw an article; ask and the key lands with the file that needs it.
3. Deleting a file archives nothing and, in wave 3, is **not reported either** — the orphan report is deferred
   (D5). A removed file leaves a published row behind until an operator archives it by hand.
4. Moving a file between manifest sections is now safe in one run: the authored `position` survives the move
   (D8). It was not safe before wave 3, and `auto-resolve.md` is one such move in this very wave.
5. Never name a file `search.md`, `articles.md` or `categories.md` — still an abort, and still not pre-checked
   (D9 mode 2).
6. A new section directory still needs a `manifest.yml` entry, or the section is **silently never seeded** — that
   is D9 mode 5 and phase 1 is not implemented, so nothing catches it for you.
7. A documentation key must not equal a changelog key — `first-release-note` is taken (D9 mode 3). It now fails on
   a unique index as well as on the slug index.
8. `release_date:` must be a bare ISO-8601 date (D9 mode 4), and every file needs a non-empty body (D9 mode 1).
9. Editing prose is always safe: `content` is class A, so a corpus correction always reaches the row.

---

## 5. REQUESTED CHANGES — files I do not own

Ordered by urgency. §5.1 is the only one that gates another agent.

> **WAVE 3 STATUS OF EACH REQUEST.**
>
> | Request | State |
> |---|---|
> | §5.1 `super_admin/articles_controller.rb` — merge `meta` | **LANDED in wave 2**, better than asked: the merge is on `ArticleMetaField`, so a controller that forgets cannot replace the column (see D3) |
> | §5.2 `article_dashboard.rb` — drop `slug` | **LANDED in wave 2** (`:42-47`). It is what makes §F2.2's provenance lookup unnecessary (D4) |
> | §5.3 `deployment/ROLLBACK.md` | **NOT APPLIED**, and I touched no deployment file. D10's procedure now reads per field rather than per row: a revert fast-forwards every field the operator has not taken over, and reports the rest |
> | §5.4 `category_dashboard.rb` — drop `slug` | **NOT APPLIED and still live.** Re-stated with evidence below |
> | §5.5 `deployment/deploy.sh` — drift print | **NOT APPLIED**, and now blocked on the deferred `documentation:drift` task (D5, D11) |
> | §5.6 `documentation_seo_audit.rake` — default to platform portals | **UNKNOWN to me**; Agent 4's file, not re-checked in wave 3 |
> | §5.7 `en.yml` — one string for D3a | **WITHDRAWN**: D3a is withdrawn, so the string is not needed. No backend i18n key is requested by wave 3 |
> | §5.8 `P0-POST-DEPLOY-OWNER-CHECKS.md` | **UNKNOWN to me**; not re-checked in wave 3 |
>
> **§5.4 is still live, and the measurement is one line of code.** `CategoryDashboard::FORM_ATTRIBUTES`
> (`custom/app/dashboards/category_dashboard.rb:25`) is
> `%i[portal name slug description locale position icon]`, the route exists
> (`config/routes/documentation.rb:9`, `resources :categories`, full CRUD) and
> `SuperAdmin::CategoriesController` scopes it to the platform portals — so a super admin can rename a
> documentation section's slug. `Documentation::ContentSeeder#upsert_category` looks a section up by
> `find_or_initialize_by(slug:, locale:)`, so the next seed **creates a second category** at the manifest slug
> while the renamed one keeps every article. This is the duplication §F2.2 feared for articles, still open for
> categories, and the fix is the same one line wave 2 applied to the article dashboard:
>
> ```diff
> -  FORM_ATTRIBUTES = %i[portal name slug description locale position icon].freeze
> +  # `slug` is deliberately absent: it is the section's public address, taken from `manifest.yml` by
> +  # Documentation::ContentSeeder#upsert_category, which looks a section up by (slug, locale). Renaming it here
> +  # makes the next seed create a SECOND category at the manifest slug and leaves every article on the renamed
> +  # one (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4, §5.4). It stays on SHOW_PAGE_ATTRIBUTES.
> +  FORM_ATTRIBUTES = %i[portal name description locale position icon].freeze
> ```
>
> I did not apply it: `custom/app/dashboards/category_dashboard.rb` is not in my write gate.

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

### 5.9 — `custom/app/services/documentation/media_seeder.rb` (Agent 1). Make its own run plan-then-apply.

**Why**: the owner's ruling applies to that file for the same reason it applies to this one. `perform!` raises
every *grammar* defect from `scan_corpus` before it writes anything, which is right — but the **missing-file**
check sits inside the write loop (`:131-135`), so a corpus whose tenth key has no file uploads nine blobs first
and then raises. It is the same partial-apply shape F7 had, one file over, and it is six lines to close.

```diff
   def perform!
-    references = scan_corpus
+    references = preflight!
     references.each { |key, reference| seed(key, reference) }
     purge_orphans(references.keys)
     @result.unreferenced = unreferenced_files(references.keys).count
     @result
   end
+
+  # Every corpus defect, with no write of any kind: the grammar checks `scan_corpus` already makes, plus the file
+  # each referenced key names. Owner ruling 3 -- an upload is outside any database transaction, so the only
+  # honest atomicity is to decide everything that can be decided before the first one.
+  def preflight!
+    references = (@references ||= scan_corpus)
+    references.each { |key, reference| require_file!(key, reference) }
+    references
+  end
 
   def seed(key, reference)
     file = media_dir.join(key)
-    unless file.file?
-      raise Error, "#{where(reference[:path], reference[:line])}: media:#{key} has no file at " \
-                   "#{file.relative_path_from(Rails.root)}."
-    end
-
     existing = index[key]
     candidate = checksum_of(file)
     return @result.unchanged += 1 if existing && existing.blob.checksum == candidate
 
     attach(key, file, existing)
   end
+
+  def require_file!(key, reference)
+    file = media_dir.join(key)
+    return if file.file?
+
+    raise Error, "#{where(reference[:path], reference[:line])}: media:#{key} has no file at " \
+                 "#{file.relative_path_from(Rails.root)}."
+  end
```

`seed`'s `reference` argument becomes unused and can go with it (two call sites, both in this file).

**What this does NOT change, deliberately.** `ContentSeeder`'s preflight keeps its own media check (D9 item 8)
rather than calling `preflight!`, because `MediaSeeder` raises on the first defect while the preflight's contract
is to name *every* offending file. The deduplication exists and is Agent 1's to decide: a non-raising
`MediaSeeder#problems` returning one message per defect, which `perform!` then raises the first of. If that lands,
`ContentSeeder::Corpus#media_problems` deletes itself and delegates. The overlap until then is two checks — the
grammar predicate (read from `MediaResolver`, not copied) and file existence.

**AMENDED — A5'-O1 closed, and the paragraph above is now half true.** `ContentSeeder#preflight!` DOES call
`media_seeder.preflight!`, as its last step (`content_seeder.rb:377`), and `ContentSeeder#apply!` calls
`media_seeder.perform!` first (`content_seeder.rb:436`). What survives is the *reason*: `Corpus#media_problems`
is kept, not replaced, because it collects every offending file where `MediaSeeder` raises on the first — so the
collected list is still what reports a missing media file, and the media preflight runs after it to decide the
four defects a collector cannot see (empty alt text, a `media:` key in a link position, a destination CommonMark
reads as no image at all, a corpus file in the reserved `uploads/` namespace). The overlap is unchanged and still
deliberate; the non-raising `MediaSeeder#problems` is still open. See P2-WORKSTREAM-OWNERSHIP.md §N1.

---

### 5.10 — `spec/security/documentation_v2/source_of_truth_boundary_spec.rb` (Agent 6). Three examples that pin
the defects this ruling closes.

**Why**: measured on this change — `14 examples, 3 failures`, and all three are examples asserting the *old*
behaviour, which is the §J3 pattern. They are inverted rather than deleted, each keeping its previous expectation
in the comment. With the diff below applied the file is **14 examples, 0 failures** (measured on a copy, since
this file belongs to Agent 6). The three are:

| Line | Pinned | Now |
|---|---|---|
| `:224` | `expect(adopted.divergences).to be_empty` — A6-O1's silent adoption | the `:adopted` divergence, with the six fields the corpus took back |
| `:311` | F8 collapsing two files into one row (`1 created, 1 updated`) | `PreflightError` naming both files, and zero rows |
| `:342` | F7 aborting with `RecordNotUnique` and two rows committed | `PreflightError` naming both files, and zero rows. Its `before` block also leaves an `en/automation` directory the rewritten manifest no longer claims, so without that line removed the example measures the parity refusal instead of the slug one |

```diff
--- a/spec/security/documentation_v2/source_of_truth_boundary_spec.rb
+++ b/spec/security/documentation_v2/source_of_truth_boundary_spec.rb
@@ -219,9 +219,13 @@
     end
 
     # The worst thing one accidental run does, measured end to end on a real untracked row: every class-A and
-    # class-C field is taken from the corpus and NOTHING reports what was overwritten -- `record_untracked` is
-    # skipped and `kept` is empty, so the run prints `1 adopted` and no divergence line.
-    it 'overwrites an untracked row\'s title, description, position and body with no divergence reported' do
+    # class-C field is taken from the corpus.
+    #
+    # INVERTED: this asserted `adopted.divergences` was EMPTY, which was A6-O1 -- the run printed `1 adopted` and
+    # no divergence line, so an operator never learned which fields the corpus took back. Owner ruling 3's "do not
+    # silently continue" closed it: there is now an `:adopted` divergence carrying the class-C fields whose stored
+    # value was replaced. Class A stays out of it by design -- the corpus owns prose on every run for every row.
+    it 'overwrites an untracked row\'s title, description, position and body, and reports every field it took' do
       root = Pathname.new(Dir.mktmpdir)
       begin
         root.join('manifest.yml').write(<<~YAML)
@@ -251,7 +255,9 @@
         article.reload
         aggregate_failures do
           expect(adopted.adopted).to eq(1)
-          expect(adopted.divergences).to be_empty
+          expect(adopted.divergences.sole.kind).to eq(:adopted)
+          expect(adopted.divergences.sole.fields)
+            .to eq(%w[title description position meta.title meta.description meta.tags])
           expect(article.title).to eq('Corpus title')
           expect(article.description).to eq('Corpus description')
           expect(article.position).to eq(70)
@@ -306,20 +312,19 @@
     end
 
     # The shape that DOES lose content, and it is not an index violation: two files with the SAME basename in
-    # two sections both derive the same `(slug, locale)`, so the second silently updates the row the first
-    # created. One row for two files, the later section wins, and the run reports `1 created, 1 updated`.
-    it 'silently collapses two sections\' same-named files into one row, rather than aborting' do
+    # two sections both derive the same `(slug, locale)`, so there is only ever one row for them.
+    #
+    # INVERTED: this asserted the collapse -- `1 created, 1 updated` for two files, one row, the later section
+    # winning and the first file's prose never published, with nothing raised. Owner ruling 3's preflight refuses
+    # the pair as a corpus defect before the first write (P2-SOURCE-OF-TRUTH-CONTRACT.md D9 item 6, F8).
+    it 'refuses two sections\' same-named files, rather than collapsing them into one row' do
       write('administration', 'overview', 'Administration overview')
       write('automation', 'overview', 'Automation overview')
 
-      result = seed
-
-      expect(portal.reload.articles.count).to eq(1)
-      expect([result.created, result.updated]).to eq([1, 1])
-      row = portal.articles.first
-      expect(row.title).to eq('Automation overview')
-      expect(row.content_source_path).to eq('custom/db/documentation/en/automation/overview.md'.sub('custom/db/documentation',
-                                                                                                    root.relative_path_from(Rails.root).to_s))
+      expect { seed }.to raise_error(Documentation::ContentSeeder::PreflightError) do |error|
+        expect(error.message).to include('en/administration/overview.md', 'en/automation/overview.md')
+      end
+      expect(portal.reload.articles).to be_empty
     end
 
     # A moved file keeps its basename, so the row is found and its path is reassigned. No second row, no
@@ -335,11 +340,15 @@
       expect(portal.articles.first.content_source_path).to end_with('en/automation/auto-resolve.md')
     end
 
-    # THE ONE REACHABLE ABORT, and it is on `slug` rather than on `content_source_path`: `articles.slug` is
+    # THE ABORT THAT WAS REACHABLE, and it is on `slug` rather than on `content_source_path`: `articles.slug` is
     # GLOBALLY unique while the seeder's lookup is `(slug, locale)`, so a non-default-locale article whose slug
-    # collides with another locale's row is not found and is INSERTED. The run raises mid-way and leaves
-    # everything already written in place -- there is no transaction around `perform!`.
-    it 'aborts mid-run, with the earlier rows committed, when a locale suffix collides with another row\'s slug' do
+    # collides with another locale's row is not found and would be INSERTED.
+    #
+    # INVERTED: this asserted `ActiveRecord::RecordNotUnique` mid-run with `audit-logs` and `audit-logs-ar`
+    # already committed -- F7, and the measured instance of A6-O3's "every abort mode leaves partial state".
+    # Owner ruling 3 answered A6-O3 with a preflight rather than a transaction, so the pair is refused with
+    # nothing written (P2-SOURCE-OF-TRUTH-CONTRACT.md D9 item 6).
+    it 'refuses a locale suffix that collides with another row\'s slug, with nothing written' do
       root.join('manifest.yml').write(<<~YAML)
         sections:
           - slug: administration
@@ -353,17 +362,23 @@
               description: إدارة مساحة العمل.
       YAML
       FileUtils.mkdir_p(root.join('ar', 'administration'))
+      # This manifest claims only `administration`, and the preflight refuses a corpus directory no section
+      # claims, so the `automation` directory the outer before block made has to go or it is what gets reported.
+      FileUtils.rm_rf(root.join('en', 'automation'))
       write('administration', 'audit-logs', 'Audit logs')
       # `slug_for('audit-logs-ar', 'en')` is `audit-logs-ar`; `slug_for('audit-logs', 'ar')` is the same string.
       write('administration', 'audit-logs-ar', 'A page whose name ends in the locale suffix')
       root.join('ar', 'administration', 'audit-logs.md')
           .write("---\ntitle: سجلات\ndescription: وصف\nposition: 10\n---\n\nمحتوى\n")
 
-      expect { seed }.to raise_error(ActiveRecord::RecordNotUnique, /slug/)
+      expect { seed }.to raise_error(Documentation::ContentSeeder::PreflightError) do |error|
+        expect(error.message).to include('en/administration/audit-logs-ar.md', 'ar/administration/audit-logs.md')
+      end
 
-      # Everything the run got to before the raise is committed. That is the state an operator is left in.
-      expect(portal.reload.articles.pluck(:slug)).to contain_exactly('audit-logs', 'audit-logs-ar')
-      expect(portal.articles.find_by(slug: 'audit-logs-ar').locale).to eq('en')
+      # The state an operator is left in: the one the run started from. The category is the group's own
+      # fixture, not the run's -- `upsert_category` never executed.
+      expect(portal.reload.articles).to be_empty
+      expect(portal.categories.pluck(:slug)).to eq([category.slug])
     end
   end
 end
```

---

## 6. OPEN — needs the owner

> **Added by wave 3**, in the order I would ask them:
>
> 5. **Do categories get the same field-by-field treatment?** The one place the owner's sentence is still false.
>    `upsert_category` overwrites a section's `name`, `description`, `position` and `icon` from `manifest.yml` on
>    every run, and all four are operator-editable (`category_dashboard.rb:25`). D2 ruled out provenance on
>    `categories` — sections come from the manifest rather than from per-file front matter, and the slug index is
>    already unique per portal — and those reasons still hold, so this is a decision about whether a section's
>    *presentation* is operator-owned, not a defect to patch. §5.4 (drop `slug` from that form) is the urgent half
>    and does not need this answer.
>
>    **CLOSED while wave 5 was running, by another agent and the owner, the other way than D2 feared**: a
>    section's edit surface is withheld at the ROUTE — `resources :categories, except: [:edit, :update]`
>    (`config/routes/documentation.rb:22`, commit `3c1324be`) — so `manifest.yml` is the only author of a
>    section's `name`, `description`, `position` and `icon` and `upsert_category` has no second writer to
>    overwrite. No digest column on `categories`, which is what D2 argued against. Nothing in this contract
>    changes: §2A was always about rows.
> 6. **Is there a corpus-side way to withdraw an article, and should there be?** D6's `retired:` key is withdrawn
>    because no file uses it. Withdrawal is now an operator action only. What would close it: a corpus that needs
>    to retire an article.
> 7. **When does the orphan half of the drift detector land?** R12 ordered a drift detector before any scheduler;
>    wave 3 ships the files-versus-counts half and not the rows-with-no-file half (D5). The deferral is safe only
>    while nobody deletes a corpus file, which is exactly the thing nobody announces.

> **Added by wave 5**, while implementing owner ruling 3:
>
> 8. **Nothing seeds media.** `Documentation::MediaSeeder` has no production caller: a no-exclusion search for
>    `MediaSeeder` returns 20 hits — its own definition, three code comments, the two interface documents, and
>    **two specs** — and no rake task, job, controller or `ContentSeeder` line among them. R2-MEDIA-INTERFACE.md
>    §3.2 assigns that one line to this file, and it was never written. It is latent today because the corpus
>    holds zero images (interface §0.1), and it becomes a defect the moment Agent 3 adds one: the article seeds,
>    the reference resolves to nothing, and the page publishes the fallback. The preflight now refuses a reference
>    with no file (D9 item 8), which is the half that belongs here; the wiring is a behaviour change to
>    `documentation:content` — a second `Result` member, a second report line, and an upload pass whose ordering
>    §3.2 specifies — and adding it alongside the failure-model change would land two unmeasured mechanisms in one
>    pass, which is the mistake wave 3 avoided by deferring D9. *What would close it:* the Orchestrator's decision
>    to wire it, or a `documentation:media` task, in a change of its own.
>
>    **CLOSED** by the owner's final pre-merge ruling, in a change of its own, as this item asked for.
>    `ContentSeeder#preflight!` now runs the media seeder's write-free phase and `ContentSeeder#apply!` runs its
>    write phase first, `Result` carries the `media` member §3.2 names, and the report prints one media line.
>    Wiring it found two defects — a plan that polluted the portal's association target so
>    `Attached::Many#attach` abandoned the attachment, and an attach boundary that reported success anyway. Full
>    record, with the measured probes and the owner's A–I tests: P2-WORKSTREAM-OWNERSHIP.md §N. No
>    `documentation:media` task was added: §3.3 permits one and nothing requires it, and
>    `documentation:content` is idempotent.

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
(the only writer); `custom/app/services/documentation/library.rb:63` (the only reader);
`spec/requests/documentation/entry_points_spec.rb`, `spec/custom/services/documentation/content_seeder_spec.rb` (2
assertions); 22 files under `docs/` (prose); `log/test.log` (30 hits, all captured `INSERT` statements from past
spec runs — generated output, not code). **Aliases, helpers, concerns and config republication followed**:
`Article.include_mod_with('Concerns::Article')` (`article.rb:300`) resolves through
`each_extension_for` (`config/initializers/01_inject_enterprise_edition_module.rb:69-79`) and no `Concerns::Article`
module exists — `./app/models/article.rb` is the only `article.rb` model in the tree and there is no `enterprise/`
tree. The camelCase alias `docKey` was searched separately and appears in no Ruby file. **Chain inspected**: form view
→ `permitted_attribute` → Administrate `permit` → `normalized_meta` → `update` → jsonb column, and the consumer side
`library.rb:63` → `documentation_controller.rb:22-23` → 404 → `documentationLinks.js:11`. **Negative stated**: no
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

**F. "No live path writes `articles.slug` on a row that already has one."** (D4, added in wave 3 for §F2.2)
The full five steps — four no-exclusion searches, every hit classified, the alias/helper/config chain followed
through `include_mod_with` and Administrate's `permitted_attributes`, and the runtime path measured rather than
inferred — are **in D4** rather than repeated here, because the claim is the whole of that decision. The negative:
one writer exists (`Article#ensure_article_slug`) and it is `self.slug ||=`, so it cannot change a slug that is
already set; one permit list names `:slug` on `Article` (the tenant API) and both of its reachability conditions
fail for a documentation row, measured as `401` and `404`.

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

**Wave 1: frozen. Wave 3: revised per owner correction §F2, implemented, and measured.** §2A is the authoritative
model and the code in the tree does what it says.

**Wave 5 adds owner ruling 3**: `preflight!` then `apply!` in `content_seeder.rb`, with no transaction around
either, the `ApplyFailure` report, the `:adopted` divergence, and the three report shapes in
`lib/tasks/documentation.rake`. D9 carries the check list, the no-write measurement and the operator output.

**Implemented** — `db/migrate/20261013230000_add_content_provenance_to_articles.rb` (additive),
`custom/app/services/documentation/content_seeder.rb` (the field-by-field merge, the `doc_key` reassertion, the
position convergence, the per-field divergence report), `lib/tasks/documentation.rake` (the report, the
`ADOPT_UNTRACKED` boundary, the non-zero exit), `app/models/article.rb` (**the schema annotation only** — no
behaviour change; the `platform_owned?` guard this contract proposed is withdrawn, see D8) and
`spec/custom/services/documentation/content_seeder_spec.rb`. `custom/app/services/documentation/portal_seeder.rb`
needed **no change**: it already protects operator state and already says so (`:4-6`), and class B makes the
content seeder agree with it rather than the other way round. `app/models/category.rb` needed no change either —
see the open item below.

**Withdrawn on measurement, each at its own decision:** the `platform_owned?` position guard (D8), the `slug`
reassertion and §F2.2's provenance lookup (D4), the `doc_key` model validation D3a and its `en.yml` string (D3,
§5.7), the `published:`/`retired:` front-matter keys (D6), `ACCEPT_FILE` and the per-row `conflict` class (D5).

**Deferred, not silently dropped:** the orphan report and
`documentation:drift` (D5, D11) and the `deploy.sh` drift print (§5.5). The source-of-truth question for
**categories** is no longer among them: the section edit route was withdrawn while wave 5 was running
(`config/routes/documentation.rb:22`, commit `3c1324be`), so the manifest is the only writer and
`upsert_category` overwrites nobody. §6 item 5 records it.

**What is measured, and what is not.** Measured in this container, against PostgreSQL 16, on the real 138-file
corpus and on fixtures: both seed tasks twice over (138 created → 138 unchanged; 2 → 2), an operator edit surviving
a full seed per field, the untracked refusal with its non-zero exit and the adopt run after it, the section move
before and after the fix, and every runtime write path to `articles.slug`. **Not measured:** anything about
production data — whether any production row carries an operator edit is still §6's open question, and the adopt
run is the mechanism that makes the answer safe to not know. No production system was touched.
