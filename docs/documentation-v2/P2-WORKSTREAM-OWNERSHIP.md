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

### G8 — My G1 icon claim was half right, and the half I got wrong is the half that matters

**Withdrawn from G1:** *"no rule was ever generated"* is true, but I gave the wrong cause and therefore shipped
a safelist that fixes nothing on its own.

`PortalHelper#render_emoji_or_icon` (`app/helpers/portal_helper.rb:107`) is
`value.start_with?('i-') ? value : "i-ri-#{value}"`. The manifest stores **bare** names (`rocket`,
`messages-square`, …), so every documentation category icon resolves to `i-ri-rocket` — the **Remix** set, not
Lucide. Measured against the installed collections:

```
rocket             lucide=true  ri=false
messages-square    lucide=true  ri=false
users              lucide=true  ri=false
megaphone          lucide=true  ri=false
message-circle     lucide=true  ri=false
alert-triangle     lucide=true  ri=false
workflow           lucide=true  ri=false
shopping-bag       lucide=true  ri=false
building           lucide=true  ri=false
plug               lucide=true  ri=false
shield             lucide=true  ri=false
life-buoy          lucide=true  ri=false
sparkles           lucide=true  ri=false
```

(`@iconify-json/lucide@1.2.82`, `@iconify-json/ri@1.2.6`, checked for both `icons` and `aliases`.)

**All thirteen exist in Lucide and none in Remix.** So the icon does not render because the generated class
names a set that does not contain it — and `@egoist/tailwindcss-icons` emits a rule only for an icon the
collection actually has, so safelisting `i-ri-rocket` would not have helped either.

The fix is **one line per section in the manifest**: store the full class `i-lucide-rocket`, which the helper
passes through untouched. That is Agent 3's file, handed to it for Wave 3 with this evidence — it is also the
change Agent 4 requested in Wave 2 and which I deferred without understanding it.

**The safelist I shipped is correct only once the manifest changes**, because `manifest.yml` is not in the
Tailwind content globs (`.vue`, `.erb`, `.js` only) and the class still arrives from `categories.icon` at
runtime. The two halves complete each other; neither works alone. I did not change
`render_emoji_or_icon`: its `i-ri-` default is product-wide and serves tenant help-center categories too, so
changing it is not a documentation-local change.

### G9 — Agent 1's remaining REQUESTED CHANGES, resolved

| # | Verdict | What happened |
|---|---|---|
| #4 — one definition of the §0.1 visibility predicate | **APPLIED** | New `app/controllers/concerns/public/portal_article_visibility.rb`; both `ArticlesController` and `MediaController` include it and their local copies are gone |
| #5 — a queue-name note in `deployment/ROLLBACK.md` | **DECLINED, premise does not hold** | The request was "wherever queue names are mentioned". `ROLLBACK.md` mentions **no** ActiveStorage queue: its only queue check is `Sidekiq::Stats.new.queues.inspect` (`deployment/ROLLBACK.md:104-106`), which enumerates whatever queues exist rather than naming one to watch. There is nothing to correct, so nothing in `deployment/**` is touched. The fact itself stays recorded in `R2-MEDIA-CONTRACT.md` §3A.3 |
| #6 — who owns `spec/lib/markdown_renderer_security_spec.rb` | **Orchestrator** | Answered by doing it: the inversion is §G5 above, applied by the integrator, not by Agent 1 |

#### Why #4 was worth applying rather than keeping the agreement spec alone

Agent 1 had written the predicate twice and guarded it with an end-to-end spec, which was the right thing to do
while the extraction was unapproved. Two copies of one rule is the defect `R2-O1` already records for `show` vs
`show_markdown`, and the media route evaluates the predicate in a **separate HTTP request**, so there is no way
to have one evaluation — only one rule.

The agreement example in `spec/requests/documentation/media_delivery_spec.rb` **stays**, with its comment
rewritten. Sharing a method does not prove the two routes behave identically: a `before_action` ordering, a
scope applied elsewhere, or a different 404 path could still diverge them, and that example hits both real
routes for both roles.

Verified: `media_delivery_spec` **15 examples, 0 failures**; `articles_controller_spec` +
`tenant_help_center_removal_spec` **85 examples, 0 failures**; RuboCop on all four files, no offenses.

#### An environment note, because it cost a false red

The first run of `media_delivery_spec` against the working tree failed all 15 examples on
`Errno::EACCES @ dir_s_mkdir - tmp/storage/...` — the spec runner runs as the `postgres` OS user (peer auth over
the unix socket) and `tmp/` and `log/` were root-owned. Made writable; `log/test.log` had also grown to **6.4 GB**
and was truncated, which returned 6 GB of the session's disk allowance. **Neither was a defect in the change**,
and the failure is recorded here because a 15/15 red that is really a permission bit is exactly the kind of
result that gets misread as a regression.

### G10 — Agent 4's `<title>` request, applied to the documentation layout and declined for the shared one

`documentation_layout/articles/_meta_head.html.erb` computed `meta_title` from `article.meta["title"]` and used
it for `meta name="title"`, `og:title` and `twitter:title` — and then wrote **`article.title`** into `<title>`.
So an operator's SEO title reached every tag except the one a search engine shows as the result heading.
Categories never had the defect: `documentation_layout/categories/_meta_head.html.erb:9-10` builds one
`meta_title` and uses it for both.

**Applied** to the documentation layout. The brand suffix stays, because it is what every other documentation
page's title carries.

**Not applied** to `app/views/public/api/v1/portals/articles/_meta_head.html.erb`, which has the same shape.
That template is rendered by `articles/show.html.erb` and `articles/show.html+plain.erb` — the **tenant** Help
Center's default variant and the chrome-less preview — while documentation portals render
`show.html+documentation.erb`. Changing it would change every tenant's Help Center `<title>`, which is a
product-wide behaviour change outside a documentation program. Recorded as an owner decision rather than taken:
**the same fix is almost certainly right there too**, since the field is labelled an SEO title in the tenant UI
as well, but it is not mine to widen into.

Nothing pinned `<title>` anywhere, which is how the divergence survived. Three examples added to
`spec/requests/documentation/seo_spec.rb`, and **proven both ways**: with the fix reverted the suite is
`31 examples, 1 failure` at `:110`; with it, `31 examples, 0 failures`. Only one of the three fails without the
fix — the other two assert the `og`/`twitter`/`meta` titles agree with it and that the on-page heading is
deliberately left alone, which were already true. That is the honest split, not three regression pins.

### G11 — Agent 2's "strikethrough is silently dead in articles": measured, and correctly NOT a defect

`render_article` passes `[:table]` only, while `render_message` passes `[:strikethrough, :autolink]`
(`lib/chatwoot_markdown_renderer.rb:8,17`). Measured through commonmarker directly:

```
[:table]                              -> <p>Strike ~~this~~ out.</p>
                                         <p>Bare https://example.com/docs link.</p>
[:table, :strikethrough]              -> <p>Strike <del>this</del> out.</p>
[:table, :strikethrough, :autolink]   -> <p>Bare <a href="https://example.com/docs">...</a> link.</p>
```

So in an article `~~x~~` renders literally and a bare URL stays plain text. **No change made**, because
`markdownCommands.js:15-16` shows Agent 2 already read this and declined to offer a strikethrough button for
exactly this reason: *"Offering a strikethrough button would store syntax the published page …"*. The editor and
the renderer agree, so there is no mismatch to fix — and enabling either extension would change rendering for
every tenant Help Center article too, which nobody asked for. Recorded as a capability fact, not a bug.

### G12 — Agent 2's "Arabic articles render LTR" is real, and the markup was already written for the fix

Agent 2 reported no `dir` attribute anywhere and no server-side direction source. Both confirmed, and the
important half is what a no-exclusion search for RTL handling turned up: the portal views **already carry
`rtl:` Tailwind utilities** — the sidebar's side and border (`_sidebar.html.erb:17`), the header's logo gap and
dropdown edge (`_header.html.erb:6,15,47,107`), the author stack's order (`_authors.html.erb:7`), eight in all.
That variant compiles to an `[dir="rtl"]` ancestor selector (`tailwind.config.js:204`). **The markup was built
for both directions and the attribute that selects one was missing**, so half the corpus rendered
left-to-right with every one of those rules inert.

Fixed: new `TextDirectionHelper#html_dir_attribute`, wired into all three portal layouts beside the `lang` they
already set, so the two come from one source and cannot disagree. Its own module rather than a method on
`PortalHelper` because direction is not portal-specific — and because `PortalHelper` is at RuboCop's
`Metrics/ModuleLength` limit (adding it there measured `104/100`).

`RTL_LOCALES = %w[ar fa he]` — the right-to-left locales among the **44** the product offers
(`config/initializers/languages.rb`, `iso_639_1_code`). Deliberately not a copy of the frontend's
`getLanguageDirection` list (`languages.js:746-749`), which includes `as` (Assamese, **left-to-right**) and
`ku`/`ur`, none of which are available locales here. A region suffix is ignored, so `ar_EG` is still RTL.

This is a **product-wide** change: it also fixes any tenant's Arabic, Persian or Hebrew Help Center, where the
same `rtl:` utilities are equally inert today. Flagged rather than buried, because the `<title>` fix in §G10 was
declined on exactly that ground. The difference is that the title change would alter output every tenant
currently relies on, while this one activates markup that was written for it and is doing nothing.

Verified: `text_direction_helper_spec` + `portal_helper_spec` + `seo_spec` = **69 examples, 0 failures**;
RuboCop on all five files, no offenses. The SEO spec asserts the real page:
`<html lang="ar" dir="rtl">` for the Arabic article and `<html lang="en" dir="ltr">` for the English one.

#### A false lead I chased, recorded so nobody re-chases it

The first version of that example read the memoized `let(:body)` twice across two requests, so the second
assertion compared against the **first** response. I read the Arabic body on an English request as evidence that
`BaseController#set_locale` runs the action twice — it calls `switch_locale_with_article(&)`, which yields
inside `I18n.with_locale`, and then calls a bare `yield` again (`base_controller.rb:38-43`). Probed it rather
than asserting it:

```
PROBE status=200
PROBE with_locale_calls=["en"]
PROBE show_renders=1  all=["show.html+documentation.erb"]
```

**One render, one locale window.** ActiveSupport's callback chain does not re-run the action on a second yield.
The trailing `yield` is the necessary path when neither `locale` nor `article_slug` is present, and it is inert
otherwise. **Not a defect, and the spec was mine.**

### G8.1 — Measured the safelist instead of asserting it, and my §G1 claim was wrong a second time

§G1 said the database-driven icon classes meant *"no rule was ever generated and eight render sites emitted an
empty span."* The second clause holds; **"no rule was ever generated" does not.** Measured by building the
config twice, once with the safelist and once with it removed, and diffing the generated icon selectors:

```
only present WITH the safelist:
  i-lucide-rocket
  i-lucide-shield
```

**Eleven of the thirteen were already generated** — `messages-square`, `users`, `megaphone`,
`message-circle`, `alert-triangle`, `workflow`, `shopping-bag`, `building`, `plug`, `life-buoy` and `sparkles`
all appear in `.vue` or `.erb` files elsewhere in the product, so the content scan already emitted them.

Three things this measurement settles:

1. **The safelist mechanism works**, which I had not verified. It is Tailwind 3.4.19 and `safelist` is honoured.
2. **All thirteen entries stay.** Needing only two today is incidental — it depends on an unrelated component
   continuing to use the same icon. The manifest is the source of these class names, so they must not depend on
   a coincidence in another file.
3. **`i-lucide-*` icons land in the COMPONENTS layer**, not utilities (a build of `@tailwind utilities` alone
   produced **zero** icon rules; adding `@tailwind components` produced **629**). The portal's own stylesheet
   imports all three layers (`app/javascript/portal/application.scss:2-4`), so they do reach the public page.

**§G8's conclusion is unchanged and is still the whole cause**: the rules exist, and the markup asks for
`i-ri-rocket` — a set that contains none of these names. The manifest fix is what makes the existing rules
reachable.

## H. Wave 3 — Agent 3 integrated, and a deploy-breaking regression found on the way

### H1 — Agent 3's corpus, verified independently rather than accepted

| Claim | My check |
|---|---|
| 126 → 138 files, 69 EN / 69 AR | `find` counts: **en=69 ar=69 total=138** |
| parity exact per section | twelve sections compared: **no mismatch** |
| no orphan sibling either direction | set difference both ways: **en-only none, ar-only none** |
| every manifest icon now a full class | `icon:` lines not matching `i-lucide-`: **none**, across both manifests |
| the registry points every key at an article that exists | `content_seeder_corpus_spec` + `library_spec`: **357 examples, 0 failures** |

That last run **closes Agent 3's A3-O6**: it reported it could not execute a single spec
(`PG::ConnectionBad: fe_sendauth: no password supplied`) and reimplemented the corpus spec's assertions in pure
Ruby instead. The real spec now runs, with its own additions and my registry entries in the tree, and is green.

Agent 3 also refined §G8 with something I had not checked: **`alert-triangle` is a lucide *alias*, not a primary
icon.** It generates a rule because `@egoist/tailwindcss-icons` resolves through `@iconify/utils`' `getIconData`,
which follows aliases. Had the plugin read the `icons` map directly, one of the thirteen would have stayed
invisible after the fix. Verified at the plugin's own resolution path, with a `definitely-not-an-icon` control
returning NULL.

### H2 — Applied for Agent 3: the two Agent 4 registry changes

Six entries in `documentationLinks.js` so the new articles are reachable from the product, and
`featureHelper.js`'s `slack_integration` repointed from the ten-app catalogue to the new Slack article.
`documentationLinks.spec.js` + `featureHelper.spec.js`: **28 tests, 0 failures**; the Ruby-side registry
cross-check is in the 357 above. Agent 3's §5.3 media requests are **not** applied — the corpus still has no
images, and a `media:` key with no file fails the seed.

### H3 — A deploy-breaking regression, found because a migration would not run

`bin/rails db:migrate` aborted with:

```
NameError: uninitialized constant DocumentationSeoAudit::Auditor::DocumentationHelper
  lib/tasks/documentation_seo_audit.rake:66:in '<class:Auditor>'
  ...
  Rakefile:6:in '<main>'
```

`Rakefile` is `require_relative 'config/application'` then `load_tasks` — it **never initializes the
application**, so Zeitwerk's autoloaders do not exist while a `.rake` file is being read. Wave 2 hoisted
`include DocumentationHelper` from inside the task body to a **class body**, where it is dereferenced at load
time. The result is a `NameError` out of `load_tasks`, which breaks **every rake task in the project** —
`db:migrate` and `assets:precompile` among them. On the deploy script's path, that is a failed deploy.

Confirmed it was not pre-existing: the diff against `9e6e4d58` shows the two `include` lines moving from
six-space indentation inside the task to class-body level.

**Fixed** by moving the module to `lib/documentation_seo_audit.rb`. `lib` is an eager load path
(`config/application.rb:42`), so it autoloads when the task body — which depends on `:environment` — first names
it, exactly as `ChatwootMarkdownRenderer` and the rest of `lib/` already do. The `.rake` file is now 48 lines of
task and nothing else.

Proven both ways: before, `rails -T` raised; after, it lists both `lynomia:` tasks and
`rake lynomia:docs:seo_audit` runs to completion. `task_documentation_seo_audit_spec` + `seo_spec` +
`documentation_helper_spec`: **66 examples, 0 failures**. RuboCop clean — the one new offence was
`Rails/Output`, which does not apply to `.rake` files and came into scope purely because of the move; scoped to
that one `puts` with the reason recorded, since live per-portal progress for an operator at a terminal is what
it is for.

**Nothing caught this**, which is the part worth keeping: the gate runs rspec, and rspec boots through
`config/environment`, so it never loads `.rake` files. A gate that cannot see a broken `load_tasks` cannot see a
broken deploy. Handed to Agent 6 as a gate-mechanism gap, since `scripts/documentation_gate.sh` is its file.

### H4 — Two owner-stated facts Agent 3 flagged, resolved here

**`WHATSAPP_API_VERSION = v22.0` is not a contradiction of the repository's `v24.0`.** `FacebookApiClient`
reads `GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT_API_VERSION)` (`:13`), so the stored
installation config **wins over** the code default. Both measurements are true at once.

The consequence neither of us had drawn, and it belongs in the owner's version inventory: `Whatsapp::HealthService`
clamps **upward** to its own floor —
`[configured, MINIMUM_HEALTH_API_VERSION].max_by { … }` with `MINIMUM_HEALTH_API_VERSION = 'v24.0'`
(`health_service.rb:18,48`). So on a v22.0 installation, health calls go out on **v24.0** and every other
WhatsApp call on **v22.0**: two Graph versions in play at once, which is precisely what
`facebook_api_client.rb:4-6` says a lower default would cause. **Nothing changed** — the owner ruled this is
handled separately under the Graph API inventory — and no article states a Graph version.

**"Embedded Signup v4" has no literal in the repository**, which Agent 3 is right to call UNVERIFIED on its
side. Only `sessionInfoVersion: '3'` is in code (`whatsapp/utils.js:136-140`); the flow version is Meta-side
configuration, so the owner's production read is the only source for it and the repository cannot corroborate
it. Carried as **A3-O3**, with Agent 3's time-sensitive note that Meta's own page warns Embedded Signup **v2**
deprecates **2026-10-15**. Production is reported to be on v4, so this is a thing to know, not a thing to do.

### H5 — The test database is seeded mid-wave, and that is Agent 5 working, not pollution to clean

After the corpus specs ran green, `rake lynomia:docs:seo_audit` went from `no portal to audit` to
`NOT_INDEXABLE`, and `task_documentation_seo_audit_spec` began failing on `Slug has already been taken`. The
cause is **not** my refactor — the same file was `66 examples, 0 failures` after the refactor and before this —
and not a leaky spec: `use_transactional_fixtures = true` and no spec runs the seeder.

Measured instead of guessed:

```
with_source_path=137  with_digests=137  total=138
["custom/db/documentation/en/getting-started/connect-your-first-channel.md", …]
```

`content_source_path` and `seeded_digests` are columns **only Agent 5's new seeder writes**. Agent 5 is running
its D7/D8 convergence measurements against the test database, which its brief requires. **Deliberately not
truncated**: that would destroy an agent's in-flight measurement state. The combined gate runs in its own
worktree with its own database, so it is unaffected.
