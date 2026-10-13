# Documentation V2 — six workstreams, file ownership frozen

**This file is the write gate.** No agent writes a file until it appears below against that agent's name.
Orchestrator rule 1. The Orchestrator is the only integrator; no agent merges.

Branch `claude/documentation-v2`, currently `df147c75`. Nothing merges to `lynomia-custom`, nothing deploys,
no production or Meta change.

## The rule for a file that is not listed

If an agent needs a file it does not own, it **submits the requested change to the Orchestrator** — the exact
diff and why — and keeps working. It does not write the file and does not work around it by adding a parallel
file that does the same job. "I needed it and nobody owned it" is not a licence; unlisted means ask.

---

## A. Ownership

### Agent 1 — R2 media / ActiveStorage

| Owns | Note |
|---|---|
| `custom/db/documentation/media/**` | new; the corpus media tree |
| `custom/app/services/documentation/media_seeder.rb` | new; upload-by-checksum against the portal's own attachments |
| `custom/app/services/documentation/media_resolver.rb` | new; `media:` key → blob, per portal, render-time |
| `app/controllers/public/api/v1/portals/media_controller.rb` | new; the app-owned delivery route |
| `app/models/portal.rb` | `has_many_attached :documentation_media` |
| `lib/custom_markdown_renderer.rb` | the `image` override resolves `media:` |
| `lib/markdown_renderer_url_sanitizer.rb` | the `data:image/*` closure, arbitrated to R2 |
| `spec/` files for the above | each agent owns the specs for the files it owns |

**Interface Agent 1 must publish before Agent 2 can use it** — key grammar, resolver signature, route shape,
alt/caption field names. Published as `R2-MEDIA-INTERFACE.md`. The R2 *contract* is already frozen in
`R2-MEDIA-CONTRACT.md`; the interface is the code-level half.

### Agent 2 — R3 professional editor (Super Admin only)

| Owns | Note |
|---|---|
| `custom/app/dashboards/article_dashboard.rb` | the current authoring surface |
| `custom/app/controllers/super_admin/articles_controller.rb` | |
| `custom/app/views/super_admin/articles/**` | new editor views |
| `app/javascript/dashboard/components/widgets/WootWriter/**` | ⚠️ **product-wide**: this editor is the tenant reply/article editor too. Any change here needs Orchestrator review before it lands, because it is not documentation-local |
| new Super Admin editor JS under `app/javascript/super_admin/**` | preferred home for documentation-only editor code |

Tenant authoring stays disabled. Agent 2 adds no tenant-reachable authoring route, action or policy grant.
Uses Agent 1's media interface; **mocks only the agreed contract boundary** if the interface is not yet
published, never an alternative media implementation.

### Agent 3 — content + Meta knowledge

| Owns | Note |
|---|---|
| `custom/db/documentation/en/**`, `custom/db/documentation/ar/**` | the corpus prose |
| `custom/db/documentation/manifest.yml` | ⚠️ shared surface: Agent 1 needs media front-matter keys and Agent 5 needs provenance keys. **Agent 3 owns the file**; both submit their key additions to the Orchestrator |
| `custom/db/changelog/**` | |

Touches no editor or media implementation file. No unsupported Meta error code; official Meta sources
authoritative; every Meta claim carries source URL, product, version and date-checked per the program's
evidence rules.

### Agent 4 — search + SEO + contextual help

| Owns | Note |
|---|---|
| `custom/app/services/custom/search_service.rb`, `app/services/search_service.rb` | |
| `custom/app/services/documentation/library.rb` | ⚠️ shared: Agent 1 resolves media per portal through it, Agent 5 reads provenance. **Agent 4 owns it**; others submit |
| `custom/app/helpers/documentation_helper.rb` | canonical, hreflang, JSON-LD, breadcrumb |
| `app/views/public/api/v1/portals/sitemap.xml.erb` | |
| `app/controllers/robots_controller.rb` | |
| `lib/tasks/documentation_seo_audit.rake` | |
| contextual-help registry and the related-article / category-icon / navigation views under `app/views/public/api/v1/portals/` **except** those Agent 1 owns | |

Extends the existing documentation search; builds no second search engine.

### Agent 5 — source of truth + deployment sync

| Owns | Note |
|---|---|
| `custom/app/services/documentation/content_seeder.rb` | including the **one line** that calls Agent 1's `MediaSeeder` |
| `custom/app/services/documentation/portal_seeder.rb` | |
| `lib/tasks/documentation.rake` | |
| `db/migrate/**` | ⚠️ **Agent 5 is the only agent that may add a migration**, and it must be additive. `db/schema.rb` is generated — Orchestrator applies it |
| `app/models/article.rb`, `app/models/category.rb` | provenance fields and their validations |

**Must publish the source-of-truth contract first**, as `P2-SOURCE-OF-TRUTH-CONTRACT.md`, because Agents 2 and
3 cannot know how authored content persists until it exists. Deployment must never silently overwrite
operator-authored content. No second CMS.

### Agent 6 — security / QA / integration review

| Owns | Note |
|---|---|
| `spec/security/documentation_v2/**` | new; reserved prefix for adversarial suites |
| `spec/requests/custom/tenant_help_center_removal_spec.rb` | the tenant-isolation suite |
| `scripts/documentation_gate.sh` | the gate's selection mechanism |

Builds no product feature. Reviews Agents 1–5 adversarially. R1.1's universal sanitizer stays
**unimplemented** unless a policy iteration solves the three measured defects
(`P2-RULINGS-IMPLEMENTATION.md` R1.1).

### Orchestrator-only — nobody else writes these

| File | Why |
|---|---|
| `config/routes.rb`, `config/routes/documentation.rb` | central conflict point; Agents 1 and 4 both need lines here |
| `config/locales/en.yml`, `app/javascript/dashboard/i18n/locale/en/*.json` | Agents 2, 3 and 4 all add strings. English only; other locales go through Crowdin |
| `deployment/**` | the §3A.2 backup addition is designed and **not approved**; no agent touches deploy or infra |
| `CLAUDE.md`, `docs/documentation-v2/00-program.md`, `08-orchestrator-rulings.md` | program contracts |
| `docs/documentation-v2/P2-WORKSTREAM-OWNERSHIP.md` | this file |
| `db/schema.rb` | generated from Agent 5's migration |

---

## B. Dependencies, frozen

```
Agent 5 ──publishes P2-SOURCE-OF-TRUTH-CONTRACT.md──┬──> Agent 2  (how authored content persists)
                                                    └──> Agent 3  (what front matter means)

Agent 1 ──publishes R2-MEDIA-INTERFACE.md───────────┬──> Agent 2  (image insertion, alt/caption)
                                                    └──> Agent 3  (media: references in prose)

Agent 4  depends on nothing; reads the corpus as it is
Agent 6  depends on all; reviews what exists at each wave
```

Nothing else blocks. Agent 2 does not wait for R2 to finish — only for the interface. Agent 3 does not wait
for the editor. Agent 4 starts immediately.

---

## C. The 4-CPU rule, and what it actually forbids

`nproc` = **4**. Orchestrator rule 5: heavy full-suite runs must not be concurrent. Concretely, binding on
every agent:

- **No agent runs `scripts/documentation_gate.sh`.** The Orchestrator runs it once, after integration.
- **No agent runs a spec directory** (`bundle exec rspec spec/models`), the whole `spec/`, or
  `pnpm test` / `vitest` without a path. Named files only.
- Targeted means **one to three spec files**, or a single `vitest` file.
- The orchestration layer caps concurrency at `min(16, nproc - 2)` = **2** agents at a time regardless, so
  waves are enforced by the runtime as well as by instruction.

---

## D. Waves

| Wave | Agents | Output |
|---|---|---|
| 1 | 5, 1 | the two contracts the others depend on. Design and reading only, no heavy tests |
| 2 | 1, 2, 4 | media implementation, editor, search/SEO/contextual help |
| 3 | 3, 5 | corpus expansion on the frozen front matter; sync implementation |
| 4 | 6 | adversarial review of everything |
| 5 | Orchestrator | the single combined gate, then the report |

A wave does not start until the previous wave's contracts are published and read.

---

## E. Wave 1 integrator verification — one claim confirmed, one refuted by measurement

Both wave-1 agents reported PostgreSQL down in their container, so neither could run a database probe. As
integrator I restarted it and measured the two claims that Agents 2, 3 and 5 would otherwise code against.
Results are binding on Wave 2.

### E1 — CONFIRMED: a Super Admin save destroys `meta['doc_key']`

```
A5-1 meta_before={"tags"=>["x"], "title"=>"SEO", "doc_key"=>"probe-key"}
A5-1 meta_after ={"tags"=>["x"], "title"=>"SEO edited"}
A5-1 DOC_KEY_DROPPED=true
A5-1 PERMITTED_INCLUDES_DOC_KEY=false
```

`ArticleMetaField.permitted_attribute` (`custom/app/fields/article_meta_field.rb:33-35`) permits
`STRING_KEYS + [{tags: []}, :tags]` — `title`, `description`, `version`, `release_date`, `feature_image`,
`tags`. **`doc_key` is not among them**, and `Super Admin::ArticlesController#resource_params`
(`custom/app/controllers/super_admin/articles_controller.rb:39-43`) assigns `permitted[:meta]` as a **whole
value**, so the jsonb column is replaced rather than merged.

One operator save silently breaks every in-product contextual-help link for that article, because
`Documentation::Library#article_for` resolves on `meta->>'doc_key'`
(`custom/app/services/documentation/library.rb:55`).

**Agent 5's second-order point is the important one and it is correct**: today a re-seed accidentally repairs
this by overwriting `meta` wholesale. A three-way merge that refuses to write an operator-edited row **stops
the accidental repair**, so the merge cannot ship before the `doc_key` fix. Frozen as a **hard prerequisite**:
the `meta` merge and the model-level guarantee land in the same change as the merge, or neither lands.

### E2 — REFUTED: a no-op re-seed does not oscillate `position`

Agent 5 re-derived discovery 069/097's non-convergence finding from the callback chain and proposed a one-line
fix (`return if platform_owned?` in `Article#category_id_changed_action`). Measured through the seeder's exact
write shape, four consecutive runs:

```
A5-2 changed_before_save=[]   (x3)
A5-2 positions=[20, 20, 20, 20]
A5-2 OSCILLATES=false
A5-2 callback fired: no
```

The callback is `after_save :category_id_changed_action, if: :saved_change_to_category_id?`
(`app/models/article.rb:74`). On a stable corpus the category does not change, the predicate is false, and
`update_column(:position, …)` is never reached. **The proposed fix guards a path that does not execute**, which
CLAUDE.md forbids as a speculative guard.

Two things this does **not** refute, and Agent 5 must address both rather than treating E2 as closing D8:

1. **A section move.** When a file moves between manifest sections the category really does change, the
   callback really does fire, and `position` jumps by `max + 10` once. That is a one-time move, not an
   oscillation — but it is untested and it interacts with ordering, so it needs its own probe.
2. **`changed == []` on every run** also means the seeder's `unchanged` count is reliable for this shape,
   which narrows D7's concern rather than confirming it.

**Instruction to Agent 5 for Wave 3:** re-derive D7 and D8 against this measurement. Do not ship the
`platform_owned?` guard. If non-convergence is real it is in a path this probe did not exercise — find it and
measure it, or withdraw the finding and say discovery 069/097 overstated it.

### E3 — Three Agent 1 constraints confirmed, binding on Agent 2

| Claim | Verified |
|---|---|
| `?cw_image_width=400px` cannot ride on a `media:` key | `URI.parse("media:a/b.png?cw_image_width=400px")` → `scheme="media"`, `opaque` holds the whole rest, **`query=nil`**. `custom_markdown_renderer.rb`'s width convention reads `.query`, so **the editor's existing drag-resize does not work on a `media:` key.** Agent 2 must not assume it does |
| The bare direct-upload route 403s | `config/initializers/active_storage.rb:62` — `head :forbidden if instance_of?(ActiveStorage::DirectUploadsController)`. **Agent 2's editor cannot upload through it**; it inserts references to seeded keys |
| `render_markdown_to_plain_text` cannot be affected by the sanitizer closure | `lib/chatwoot_markdown_renderer.rb:21-23` is `CommonMarker.render_doc(@content, :DEFAULT).to_plaintext` — **no Ruby renderer class at all**. Refines my contract §0.3: it is a third renderer, but not a sanitizer-bearing one |

---

## F. Two owner corrections — binding on Wave 2, incorporated before implementation

### F1 — Documentation gets its OWN authorized Super Admin upload path

The wave-1 conclusion "the bare direct-upload route 403s, therefore the editor inserts only references to
seeded keys" is **not sufficient for the product**. Corrected:

- The **generic/bare** `ActiveStorage::DirectUploadsController` route stays unavailable. That guard
  (`config/initializers/active_storage.rb:62`) is not relaxed, not subclassed around, not exempted.
- Documentation gets its **own** Super Admin-only upload path, attaching to the **same**
  `portal.documentation_media` namespace, addressed by the **same `media:` key grammar**, resolved by the
  **same** `Documentation::MediaResolver`. Seeded media and operator-uploaded media are one abstraction.
- Must support: upload button, drag/drop, paste image, replacement, alt text, caption.
- Backend-independent through ActiveStorage abstractions only — no raw blob path, no DiskService path, no
  second media system.
- **Super Admin only. No tenant authoring path**, and item 12's standing rule applies: any new
  Portal/Article/Category policy action lands a `false` override in the same commit.

**The editor must not depend on repository-seeded images only.**

#### F1.1 This breaks frozen contract item 9, and item 9 is the thing that changes

`R2-MEDIA-CONTRACT.md` item 9 froze orphan cleanup as: *after a run, any `documentation_media` attachment whose
key no longer appears in that portal's corpus is purged.* An operator-uploaded file **has no corpus file by
construction**, so that sweep would delete every operator upload on the next seed — silently, and with the
article still referencing it.

**Item 9 is amended:** the sweep is scoped to attachments whose provenance says *the seeder created this one*.
Operator-uploaded attachments are never touched by the seeder's cleanup. That requires each attachment to
record its origin, which Agent 1 specifies and which is the same provenance question Agent 5 is answering for
rows — the two must use **one** vocabulary, not two.

Agent 1 owns the backend service and the origin marker. Agent 2 consumes the interface and must not implement
an alternative upload path, even temporarily.

### F2 — Source of truth is field-by-field, not content-only

A `content_digest` protects `content` and nothing else. I enumerated every field the seeder writes and every
field Super Admin can edit; **the overlap is nine fields**, so a content-only digest silently overwrites an
operator's title, slug, description, position, status and SEO metadata while the digest still matches.

**Written by `Documentation::ContentSeeder`** (`content_seeder.rb:70-113`), complete:

| Field | How | Source |
|---|---|---|
| `slug` | `find_or_initialize_by(slug: slug_for(key, locale))` — the identity lookup | file name |
| `locale` | `find_or_initialize_by(locale:)`, and forced again by `ensure_locale_in_article` from the category | directory |
| `title` | `attributes_for` | `front_matter.fetch('title')` |
| `description` | `attributes_for` | `front_matter['description']` |
| `content` | `attributes_for` | the body |
| `category` | `attributes_for` | manifest section |
| `position` | `attributes_for` | `front_matter.fetch('position')` |
| `status` | `attributes_for` | **the `@publish` flag — the file does not express it** |
| `meta` | `attributes_for` → `meta_for`, **whole-value replacement** | `doc_key`, SEO `title`, SEO `description`, `tags`, `version`, `release_date` |
| `associated_article_id` | explicit, non-default locales only | root-article lookup |
| `author` | `\|\|=` — **never overwritten**, the one field already protected | `SuperAdmin.first` |

**Editable in Super Admin** — `ArticleDashboard::FORM_ATTRIBUTES` (`custom/app/dashboards/article_dashboard.rb:36`):
`portal, category, title, slug, description, content, locale, status, position, meta`.

**Every one of those except `portal` is also written by the seeder.**

#### F2.1 The classification the contract must carry, field by field

Proposed by the Orchestrator from the evidence above; Agent 5 owns the final text and may argue a row, with
evidence, but may not leave a field unclassified.

| Class | Fields | Rule |
|---|---|---|
| **D — immutable identity / provenance** | `portal`, `locale`, `meta['doc_key']`, and the new provenance column | Neither side changes these after creation. `doc_key` is the one being destroyed today (§E1) |
| **A — repository-owned** | `content`, `category`/section, `associated_article_id` | The corpus is the source of truth for prose and placement. The seeder wins |
| **B — operator-owned** | `status` | **The file does not express it** — the seeder forces it from its own `publish:` flag. An operator who unpublishes an article must stay unpublished across a deploy |
| **C — mergeable, per field** | `title`, `description`, `position`, `meta['title']`, `meta['description']`, `meta['tags']`, `meta['version']`, `meta['release_date']` | The seeder writes a field **only if the current value still equals what the seeder last wrote there**. Otherwise it is operator-edited: leave it, and report it |

#### F2.2 `slug` is the dangerous one and needs its own decision

`slug` is both the identity lookup (`find_or_initialize_by(slug:)`) and an operator-editable form field, and
`articles.slug` is globally unique. So **an operator who renames a slug makes the next seed create a duplicate
article** rather than update the existing one — the lookup no longer finds it.

The Orchestrator's position, for Agent 5 to confirm or refute with evidence: **look the row up by provenance,
not by a field an operator can edit.** `meta['doc_key']` or the new `content_source_path` is the stable
identity; `slug` then becomes class C or B and a rename stops being a corpus-duplication event. Whether a
renamed slug needs a redirect for the previously indexed public URL is an SEO question for Agent 4, submitted
rather than decided here.

#### F2.3 Constraints on the solution

- **No second CMS and no revision system** unless evidence proves one necessary. A per-field record of *what
  the seeder last wrote* is a generalization of the accepted digest direction, not a new store, and it earns
  D1, D5, D7 and D10 the same way.
- **The `doc_key` fix and the merge model still land atomically** (§E1).
- Agent 5 remains the only agent permitted a migration, and it must be additive.
- `author` already demonstrates the pattern in one line (`\|\|=`); the merge generalizes it rather than
  inventing a mechanism.

### F3 — Unchanged by these corrections

R2-O4 stays an operational backup gap only. No production change, no storage migration, no Meta change, no
discovery restart. Targeted tests during implementation; one combined gate after integration.

---

## G. Wave 2 integration — the Orchestrator's decisions and applied changes

Agents 1, 2 and 4 delivered; none committed, as instructed. Integration applied by the Orchestrator.

### G1 — Applied from REQUESTED CHANGES (Orchestrator-owned or unlisted files)

| File | Change | Why it was not the agent's to make |
|---|---|---|
| `config/routes.rb` | the public media delivery route, with `format: false` | Orchestrator-only. Without `format: false` the non-greedy glob hands `.png` to `params[:format]` and the key stops matching |
| `config/routes/documentation.rb` | `preview_markdown` on the articles collection; `post documentation_media` + `patch documentation_media/*key` | Orchestrator-only, and the collision below |
| `lib/chatwoot_markdown_renderer.rb` | `render_article(media: nil)` | unlisted. The default keeps every existing caller and spec working |
| `app/controllers/public/api/v1/portals/articles_controller.rb` | passes a per-request, per-portal `MediaResolver` | unlisted. Per-portal is what stops one portal's key reaching another's attachment |
| `config/locales/en.yml` | 30 editor keys under `documentation.super_admin.editor` | Orchestrator-only. English only; the rest go through Crowdin |
| `app/views/super_admin/application/_navigation.html.erb` | hide `documentation_media` from the resource nav | unlisted. Without it Agent 1's upload resource 500s **every** Super Admin page |
| `app/javascript/entrypoints/superadmin_pages.js` | register `DocumentationArticleEditor` | unlisted. The editor does not mount without it |
| `tailwind.config.js` | scan `app/javascript/super_admin` and `custom/app/views`; safelist the 13 database-driven icon classes | unlisted. Neither path was scanned, which is why CLAUDE.md's "Tailwind only, no inline styles" was *unachievable* in `custom/app/views/`. The icons come from `categories.icon` — a database value in no scanned file, so no rule was ever generated and eight render sites emitted an empty span |
| `app/models/article.rb` | `dictionary: 'arabic'` on the `text_search` scope | Agent 5's file. Decision below |

### G2 — The route collision, resolved

Agents 1 and 2 both specified a `documentation_media` create route, and Agent 1 flagged it: **a second
`as: :documentation_media` raises on boot.** Agent 1's explicit pair landed, because `resources` cannot express
the glob that `replace` needs (a `media:` key contains slashes). Agent 2's variant was not applied.

### G3 — R2-O12 resolved: captions stay out of R2, and the conflict was mine

Agent 1 correctly refused to decide this and flagged it. The conflict is between two things **I** wrote: owner
correction **F1** lists "caption" among what the upload path must support, while frozen contract **item 7** puts
captions out of R2 and **R2-O2** defers them to R3.

**Item 7 wins, and F1 was over-broad.** Captions have no representation in the Markdown source model, and item
7's deferral exists precisely so nobody invents a convention for one — which is what F1 would have forced. F1's
list was me enumerating editor affordances, not amending the data model. `MediaUpload` accepts no caption;
Agent 2's alt panel is laid out so one can be added when R3 settles a representation. **F1 is corrected here
rather than reinterpreted.**

### G4 — Agent 4's `dictionary: 'arabic'` accepted, after checking the one thing that could have made it unsafe

It is a **product-wide** change: `Article.text_search` serves every tenant's Help Center, not only the
documentation portals. Accepted on Agent 4's measurement (65 A/B cases, 9 Arabic fixed, 0 broken, `to_tsvector`
byte-identical on 23 Latin probes) **plus two checks of my own**, because a dictionary change is the kind of
thing that silently invalidates a stored artefact:

- **No stored tsvector and no full-text index exist on `articles`** (`db/schema.rb:202-228` — only the seven
  btree indexes). The upstream TODO at `article.rb:104` even points at update triggers as future work,
  confirming there are none. So `to_tsvector` is computed per query: **no reindex, nothing to drift.**
- **The configuration is present**: `select cfgname from pg_ts_config` returns `arabic` on the PostgreSQL 16.15
  this product runs. A missing configuration would have raised on every search.

Left open as **A4-O1**: alef variants (`أ إ آ` → `ا`) still do not fold, so `الخطا` finds nothing. Closing it
needs character folding before tokenization, which `unaccent` cannot do and which pg_search cannot inject into
`against:`.

### G5 — The superseded `data:` spec, inverted by the Orchestrator

Agent 1's closure turned `spec/lib/markdown_renderer_security_spec.rb:211` red — the example I wrote in P0 to
pin that `render_article` **permits** `data:image/png`. Its own comment said why it was only pinned: *"recorded
for the media contract rather than changed inside a security hotfix."* The media contract has now changed it
(§2.1), so I inverted the assertion and **kept the old expectation quoted in place** rather than deleting it.

A second example was added asserting the message path **still permits** it — that is the containment boundary in
a test rather than a comment. `spec/lib/base_markdown_renderer_spec.rb` stays **unmodified and green**, which is
what proves the closure did not leak into the conversation and email path.

### G6 — Verification run (targeted; the gate is not run until integration completes)

| Suite | Result |
|---|---|
| media resolver + upload + seeder | 58 examples, 0 failures |
| media delivery + upload requests + custom renderer | 84 examples, 0 failures |
| media delivery + resolver + public articles controller (after my route and resolver wiring) | **67 examples, 0 failures** |
| `markdown_renderer_security_spec` + `base_markdown_renderer_spec` (after the inversion) | **73 examples, 0 failures** |
| `article_spec` + `search_service_spec` + documentation `search_spec` (after the dictionary change) | **73 examples, 0 failures** |
| editor unit + component + round-trip specs | **74 tests, 0 failures** across 4 files |
| RuboCop, 31 changed Ruby files | no offenses |
| eslint on `tailwind.config.js`, the entrypoint and `'app/javascript/super_admin/**/*.{js,vue}'` | 0 errors, 0 warnings |

**The first eslint run of this set was vacuous, and the pre-commit hook caught it.** I passed eslint a
*directory*; without `--ext` it lints only `.js` in a directory, so every `.vue` file — including the editor
itself — was never checked and the run exited 0. The husky hook, which resolves staged paths individually,
then failed the commit on `ArticleEditor.vue` (`'selectedPortalId' was used before it was defined` — a real
TDZ error at module evaluation, not a style nit). Re-running with the explicit glob above surfaced six errors
and one warning in that same file; all are now fixed and the 74 editor tests re-pass. The row above records
the glob, not the directory, because the directory form is what made the earlier claim false.


### G7 — Agent 2's gate verdict: ruling R3 point 2 does NOT open

**The corpus does not round-trip through the installed ProseMirror pair.** Measured over all 126 files:
`byteIdentical=0, changed=126, addedHardBreaks=2315, tablesReformatted=108`, independently reproducing agent
067's figure exactly. Five defect classes, four cosmetic and one semantic: **a fenced code block's info string
is DROPPED** (` ```json ` → ` ``` `) — which is the field P0-1 security-reviewed and renders as
`class="language-…"`. A WYSIWYG save would silently delete it.

Agent 2 therefore did **not** convert the corpus and built ruling R3's "increment one" instead: a Markdown
**source** editor, which cannot have a round-trip problem by construction. `![alt](media:key)` round-trips
byte-identical, so Agent 1's grammar is safe for a future adoption. `corpusRoundTrip.spec.js` goes red the
moment the serializer changes, which is the signal to re-decide. **This is the ruling working as designed, not
a blocker.**
