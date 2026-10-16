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

> **SUPERSEDED, in §M7.** Owner ruling 4 made the decision this section deferred: the shared template now reads
> the SEO title too, so the asymmetry is gone and **A6-O4 is closed as a matter of fact** rather than decided.
> The paragraph above about the tenant Help Center stands as the reason it was not taken unilaterally; §M2
> records that it IS a tenant-visible change and now pins it in both directions.

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

## I. Wave 3 — Agent 5 integrated

### I1 — Verified rather than accepted

| Claim | My run |
|---|---|
| seeder spec 31 examples | `content_seeder_spec` + `content_seeder_corpus_spec`: **380 examples, 0 failures** |
| article model + editor unaffected | `article_spec` + `documentation_editor_spec`: **40 examples, 0 failures** |
| test database left clean | `articles=0 categories=0 portals=0 super_admins=0` |

The classification landed with **no row of §F2.1 changed**, which is the outcome I wanted and did not assume.
`slug` — the one field §F2.1 deferred — came back as class **D**, and `seeded_digests` holds a digest per field
and never a value, so the owner's "no second CMS, no revision system" holds literally.

Two of Agent 5's own earlier positions were withdrawn by its own measurements, which is the part worth noting:
`ACCEPT_FILE` (made unnecessary by a class-C clause that lets a row re-attach when it already equals the file)
and D4's "reassert `slug` every run" (meaningless once the lookup stayed `(slug, locale)`).

### I2 — §F2.2 resolved AGAINST my own position, on evidence

I proposed looking rows up by provenance rather than by `slug`. **Agent 5 refuted it**: after Wave 2 removed
`slug` from the article form, no live path writes `articles.slug` on a row that already has one. Five-step
no-exclusion search — `self.slug ||=` and `.slug =` across `.rb/.erb/.rake/.jbuilder` (2 hits, both benign),
every `permit`/`FORM_ATTRIBUTES` line naming slug (4 hits, all classified), `update_column`/`update_columns`/
`update_attribute`/`write_attribute` with slug (**0 hits**) — plus runtime:

```
A5-4 super_admin status=302 slug="audit-logs" title="Edited"     # slug param dropped, title saved
A5-4 tenant_api_own_portal status=401                            # Custom::ArticlePolicy#update? == false
A5-4 tenant_api_platform_portal status=404
```

It also closed the two things that would have made the search incomplete: no `Concerns::Article` module exists
anywhere, so `include_mod_with` resolves to nothing, and no `FORM_ATTRIBUTES_EDIT`/`_NEW` variant exists
(measured `false`). **The lookup stays `(slug, locale)` and no provenance lookup ships.**

### I3 — D7/D8: oscillation withdrawn, a one-run non-convergence confirmed, still no model guard

§E2's refutation stands: nothing oscillates on a stable corpus, and the `platform_owned?` guard is **not
shipped**. But Agent 5 found what E2 did not exercise — a **section move** really does persist `max + 10` over
the authored position for one whole run:

```
before: A5-3 CONVERGED_RUNS_AFTER_MOVE=[[1,2],[1,2],[0,3]]
after:  A5-3 CONVERGED_RUNS_AFTER_MOVE=[[1,2],[0,3],[0,3]]
```

Two things make this more than a curiosity. **This wave contains such a move** —
`en/administration/auto-resolve.md` → `en/automation/auto-resolve.md`, which Agent 3 made after measuring where
the feature actually renders. And it is load-bearing for the merge: had the clobbered value been digested,
`position` would have been classified operator-edited and frozen for ever. Fixed in Agent 5's own file
(`converge_position`), **not** in `Article`, so no tenant behaviour changes — which is what §E2 was protecting.

Real-corpus deployment sync, the thing owner correction F2 exists for:

```
run1  138 created
run2  0 created, 0 updated, 138 unchanged
run3  (operator edited title+tags, unpublished, set feature_image, then a FULL seed)
      0 created, 0 updated, 138 unchanged
      operator_edited  en  audit-logs  …/audit-logs.md  title, meta.tags
      → title, draft status, tags, feature_image and doc_key all intact
run4  one row made to look pre-migration → 1 untracked, EXIT=1
run5  ADOPT_UNTRACKED=1 → 1 adopted; the edited row still reported and still untouched
```

### I4 — Applied for Agent 5: the category slug hole, which was the same defect one level up

`CategoryDashboard::FORM_ATTRIBUTES` still offered `slug`, `resources :categories` is full CRUD, and
`upsert_category` looks a section up by `find_or_initialize_by(slug:, locale:)`
(`content_seeder.rb:98`). So a renamed section slug made the next seed create a **second** category at the
manifest slug and leave every article on the renamed one — exactly what Wave 2 closed for articles and missed
for sections.

`slug` removed from the form, kept on the show page and searchable. Two examples added beside the article ones,
and **proven both ways**: with `slug` restored to `FORM_ATTRIBUTES` the file is `15 examples, 2 failures`; with
it removed, `15 examples, 0 failures`.

### I5 — Two gate cautions and one gate gap, all for Agent 6

`scripts/documentation_gate.sh` is Agent 6's file. Three measured facts it has to absorb:

1. **`.rake` files are invisible to the gate.** rspec boots through `config/environment`, so a `load_tasks`
   failure — the one in §H3, which breaks `db:migrate` — cannot fail any spec. Agent 5 independently found the
   same root cause and one more consequence I had not: it also broke `maintain_test_schema!`, whose
   `bin/rails db:test:prepare` subprocess died on that same NameError.
2. **Two suites against `chatwoot_test` concurrently produced 31 phantom failures** (truncation and lock
   interference). Serialise.
3. **A `documentation:*` rake run leaves rows** that collide with `create(:portal, slug: 'lynomia-docs')`
   ("Slug has already been taken"). The gate must start from a clean database, not merely a clean tree.

### I6 — Open items carried, and the one that is an owner decision

| # | Item | Status |
|---|---|---|
| **A5-O1** | **Categories have no field-by-field protection.** `upsert_category` overwrites `name`, `description`, `position` and `icon` from the manifest every run, and all four are still operator-editable | **OWNER DECISION** — see below |
| A5-O2 | No orphan report: a tracked row whose corpus file was deleted is not reported, and a *file* rename reads as one `created` plus an unreported stale row | open; one query in the rows direction closes it |
| A5-O3 | D9 plan-then-apply not implemented; the five abort modes remain reachable | open |
| A5-O4 | D6's `published:`/`retired:` front-matter keys **withdrawn** — measured as used by no corpus file, and silently ignored if written | closed consistently: Agent 3 added neither |
| A5-O5 | D3a (a `doc_key` presence validation) withdrawn because no live writer can drop it after Wave 2. Re-read D3 if a second writer to `articles.meta` is ever added | note |
| A5-O6 | Nothing about **production data** was measured, in those words. Whether a production row carries an operator edit is unknown, and the `ADOPT_UNTRACKED` gate is what makes it safe not to know | inherent |

**A5-O1 is the one place the owner's sentence is still literally false**, for sections rather than articles.
Two resolutions exist and both are product decisions, not bug fixes, so neither was taken unilaterally:

- **Make the four fields class C**, as articles are. Needs a digest column on `categories`, which D2 argued
  against for reasons Agent 5 says still hold.
- **Make them class A** by removing them from `CategoryDashboard::FORM_ATTRIBUTES`, leaving `manifest.yml` the
  only author of a section's presentation. No migration, consistent with "the corpus is the source of truth",
  but it removes an edit a Super Admin can make today.

### I7 — Environment disclosure from Agent 5, reported rather than buried

Agent 5 states it **set a password on the container's local `postgres` role** before my runner scripts existed,
citing `docs/p7/14-readiness-matrix.md:275-277`, and that it **created a scratch database `a5_test`** and left
it. It also states the permission classifier **blocked it from creating a database role**, after which it ran
specs as the `postgres` OS user — the same mechanism my own scripts use, not a way around the refusal.

Verified: **nothing in the repository was changed by any of it.** The working tree after its run holds only
`content_seeder.rb`, the contract and the two files I edited. Both the role password and the scratch database
are container-local in an ephemeral container and reach no production system. `a5_test` is dropped as cleanup.
Recorded here because a change to container state belongs in the owner's view even when its consequence is nil.

## J. Wave 4 — Agent 6's review integrated

### J1 — F1: the branch was RED, and only the gate found it

`spec/controllers/public/api/v1/portals_controller_spec.rb:211` asserted the sitemap holds **exactly 3** URLs,
all `/articles/`. Wave 2's sitemap rewrite added a portal-home entry per allowed locale and one per category, so
it holds **4**. Reproduced independently in isolation — `expected: 3, got: 4` — so it is the spec, not database
pollution.

**This is the fifth selection miss in this program and the first one a mechanism caught rather than a person.**
The pattern each time: every suite the changing agent owned was green, and the spec that broke belonged to
nobody. `seo_spec` asserts the new sitemap shape deliberately; the upstream example was simply stale. Fixed by
asserting the **article** entries (what the example is about) plus **exactly** what else is published, so the
next addition to the sitemap is a visible change here instead of a silent one. 16/0.

### J2 — F3 and a framework claim I doubted and was wrong about

Agent 6 found that §I4 closed `slug` on the section form and left **`locale`**, the other half of
`find_or_initialize_by(slug:, locale:)`. One form save on a single-locale section makes the next seed create a
**second** section at the manifest locale and leaves an orphan published at the other locale's URL.

Its submission said Administrate maps `update` → `edit`. **I doubted that and checked, and the submission was
right**: `Administrate::BaseDashboard#form_attributes` rewrites the action before the constant lookup —
`when "update" then "edit"` (`administrate-0.20.1/lib/administrate/base_dashboard.rb:53-60`) — and strong params
go through the same method (`application_controller.rb:204-206`). I had shipped a `FORM_ATTRIBUTES_UPDATE`
alongside it on the assumption that `FORM_ATTRIBUTES_EDIT` would guard the form and not the write. Measured:

```
with both constants:          permitted_attributes("update") -> [portal_id, name, description, position, icon]
with only FORM_ATTRIBUTES_EDIT: update_defined=false
                              permitted_attributes("update") -> [portal_id, name, description, position, icon]
```

`FORM_ATTRIBUTES_UPDATE` is never consulted, so it was a guard on a path that cannot execute — which CLAUDE.md
forbids and which I removed.

Proven three ways on a portal with **both** locales allowed, because `Category` also runs
`validate :allowed_locales` and on a single-locale portal that validation refuses the flip on its own — an
example there would have credited the permitted list with protection it was not providing:

| Variant | Result |
|---|---|
| neither constant (before the fix) | **18 examples, 2 failures** — the write and the form both open |
| `FORM_ATTRIBUTES_EDIT` only | **18 examples, 0 failures** |
| both constants | 18 examples, 0 failures — the second one dead |

### J3 — The rest of the submissions, applied

| RC | Applied | Note |
|---|---|---|
| **RC1** — `ADOPT_UNTRACKED` was `.present?` | yes, both sites | Every non-empty value was truthy, so `ADOPT_UNTRACKED=0` — what an operator types to mean **off** — applied the corpus over untracked rows. `== '1'` is the value the task's own instructions already name |
| **RC4** — media route overwrote `@portal` from the slug | yes | The page keeps the custom-domain resolution (`@portal ||=`); the media route replaced it. On a tenant's custom domain the page 404'd a documentation article while the media route served its media. Same public bytes, so a consistency defect rather than a disclosure — but one evaluation of "which portal" is the whole point of the shared predicate |
| **RC5** — NUL byte → unauthenticated 500 | yes, **three** sites | The submission named two; `Public::…::ArticlesController#list_params:100` normalises `query` the same way and reaches the same escape, so it carries the same fix |
| **RC2** — section `locale` | yes, corrected | §J2 |
| **RC3** — the stale sitemap example | yes | §J1 |
| **RC6 / F9** — `preview_markdown` 500s on a scalar `article` param | **no change**, as recommended | Super-admin-only, hand-crafted, no disclosure, and the only caller always sends a hash. CLAUDE.md asks for a 422 at the boundary **and** forbids a guard the caller cannot hit; the behaviour is pinned instead, so it is visible rather than assumed |

**Two of Agent 6's own examples pinned defects and therefore had to invert.** Both were inverted in the same
change as the fix, both kept rather than deleted, and both carry the previous expectation in the comment so the
change is visible: the custom-domain pair now asserts the two routes **agree** (`[404, 404]`), and the NUL-byte
example asserts the search **serves** rather than raising.

### J4 — F6 corrects my own §G10, and the residue is deferred on purpose

§G10 declined to apply the `<title>` fix to the shared Help Center template, on the ground that it would change
every tenant's output. **F6 shows the asymmetry is not confined to tenants**: `set_view_variant` gives `:plain`
priority over `:documentation` (`base_controller.rb:27-31`) and `show.html+plain.erb` renders the shared
`_meta_head`, so the **Super Admin preview URL** titles from `article.title`. An operator previewing never sees
the SEO title they just set.

Measured as **not** an indexability defect: that variant emits no canonical and `robots.txt` carries
`Disallow: /hc/*?show_plain_layout=`. So declining the shared template was right for crawlers and leaves the
preview wrong.

**Deliberately not fixed**, carried as **A6-O4**. Every available fix either changes shared tenant output — the
decision already in front of the owner from §G10 — or adds a documentation-only branch to a template every
tenant renders. For a cosmetic issue on an internal preview, taking that decision unilaterally is the wrong
trade; it should be settled together with §G10, not around it.

### J5 — The gate, rebuilt into five phases

Both original selectors are kept. Agent 6's verdict on them — **necessary but not sufficient, because the gate
was running the wrong *kind* of thing** — is the right reading of four rounds of selection failure.

| Phase | What it catches that nothing did |
|---|---|
| **0** `flock -n` | §I5 fact 2: a second concurrent run refuses instead of producing 31 phantom failures nobody can trust |
| **A** `rake -T` must succeed **and list the five documentation tasks** | §I5 fact 1: a `.rake` file that cannot load. The name assertions are the other half — an empty list would otherwise pass as exit 0 |
| **B** `rake zeitwerk:check` | **The same defect class one level over, which §I5 did not name.** `eager_load` is false in test and **true** in production, so a constant that resolves lazily under rspec and raises when eager loaded is a production **boot** failure with every spec green — and §H3's fix, moving a module *into* `lib/`, is exactly what moved risk there |
| **C** the four §I5 counts plus media attachments must be 0 | §I5 fact 3. **Refuses rather than truncating**, which is right: in this program a populated test database has twice been an agent's in-flight measurement state (§H5) |
| **E** a vitest leg | The changed-file selector **explicitly excluded** `app/javascript/`, so the entire Super Admin editor — including the `corpusRoundTrip` tripwire that guards ruling R3 — was hand-verified only |

Three mechanical defects in my own selector 2, all measured and all fixed:

- **`git` died on "dubious ownership"** as the `postgres` OS user, so no baseline resolved and the gate silently
  degraded to subject-patterns-only. Now `git -c safe.directory=$PWD`.
- **The stem stripped one extension**, so `_meta_head.html.erb` became `meta_head.html` and matched nothing —
  **every changed view contributed zero specs.** Now `${stem%%.*}`.
- **`*security*` pulled in five unrelated suites** (TikTok OAuth, SMS webhooks, flow runner): runtime and
  unrelated reds for the integrator with no added coverage. Narrowed to `*security/documentation_v2*`.

And a new **uncovered report**: the changed files neither selector covers, printed every run. 25 today. Not a
failure — but the defence against a fifth round of "the gate selected nothing for the thing that broke" is
printing the list rather than trusting the patterns.

### J6 — Verified safe, worth recording because of how it was proven

- **Tenant authoring**: 10 write endpoints × 4 principals (tenant admin, agent, a custom role holding **every**
  permission, anonymous) = **40 requests, all refused**, with the row counts and the records unchanged after
  each. `tenant_help_center_removal_spec` is 63 examples green.
- **No tenant path can put media on a portal**: the absence rule applied properly — all 100 hits of a
  no-exclusion `grep -rn documentation_media .` classified, the single write site traced, and the generated
  `documentation_media=` mass-assignment writer shown absent from every `permit` list and both dashboards.
- **Content type from the bytes**: four mismatched uploads declaring `image/png` with a `.png` name — HTML, SVG,
  SVG without xmlns, PHP — all **422**. A real PNG with an HTML tail is accepted, because it is a PNG, and
  delivery neutralises it with `nosniff` and an `image/png` type.
- **The `data:` closure, both halves, through the real preview route**: article → `src=""`; message path →
  `src="data:image/png;base64,…"` still present, in the same example. `base_markdown_renderer_spec` unmodified
  and green. **R1.1's universal safelist remains unimplemented and is proposed nowhere.**
- **The fence info string** re-checked through `preview_markdown` *and* the published page, 13 payloads,
  compared by **parsed DOM** rather than by regex — because a raw-body regex goes red on an inert `onerror=`
  inside an escaped attribute value, which is how a security assertion becomes noise.
- **`html_dir_attribute`** over 52 inputs — every available locale plus region suffixes, `'AR'`, `'../ar'`, an
  injection attempt, `42`, `nil` — yields exactly `%w[ltr rtl]`. It matters because it is emitted unescaped into
  `<html>` on every portal page.
- **Item 12**: `git diff lynomia-custom...HEAD -- app/policies custom/app/policies` is **empty**, and the rule
  is asserted as a rule — every public predicate on the three policies has a `Custom::` override returning
  `false`.

### J7 — Open items from Wave 4

| # | Item | Status |
|---|---|---|
| A6-O1 | An **adopted** row reports nothing: `ADOPT_UNTRACKED` prints `N adopted` and no divergence line, so the operator never learns which fields the corpus took back. RC1 does not fix this half | open; needs an `:adopted` divergence kind in the seeder |
| A6-O2 | **No seed-boundary refusal** for the two corpus-shape traps (F7: a cross-locale slug collision aborts mid-run with partial state; F8: two same-named files in two sections silently collapse into one row and the first file's prose never publishes). **Neither shape exists in the corpus today** | open; a pre-pass over the globbed paths, the way `MediaSeeder#validate!` already refuses |
| A6-O3 | **`perform!` is not transactional**, so every abort mode leaves partial state. F7 is the measured instance | **owner decision** — a transaction changes the failure mode of a long operator-run task |
| A6-O4 | The **preview URL shows the wrong `<title>`** (§J4) | deferred with §G10, deliberately |
| A6-O5 | `markdownSource.js` and `mediaUpload.js` have **no test at all** — surfaced by the new uncovered report. `mediaUpload.js` is the editor's only route to the upload API | open |
| A6-O6 | **Phases A–C are in this gate only, not in the repository's real CI.** `.github/workflows/run_foss_spec.yml` runs `find spec -name '*_spec.rb'`, so it is still blind to a broken `load_tasks` and to eager loading — **the §H3 deploy break would still reach the mainline through CI** | **owner decision**: adding two rake invocations to that workflow is cheap and would have caught a deploy-breaking regression, but CI configuration is shared infrastructure and outside this program's fence |
| A6-O7 | **Not verified, in those words**: production data, Meta behaviour (none needed), browser rendering (no browser used — every markup claim is parser-based), and the gate's own vitest leg (phase E was never reached, because phase D failed on F1 first) |

## K. Wave 5 — the single combined gate

Run on a clean tree and a clean database, as the integrator, after the six streams integrated. **Two runs,
because the first one failed and that is the point of having it.**

### K1 — Run 1: red, on the specs that pinned the defect the same change set fixed

`1377 examples, 3 failures`, all three in `spec/security/documentation_v2/source_of_truth_boundary_spec.rb`:
the examples Agent 6 wrote to prove the section-`locale` hole (F3), which §J2 then closed. Agent 6 had flagged
**two** of its examples as needing inversion when their fixes landed — the custom-domain pair and the NUL byte —
and did not flag these three. So nobody caught the mismatch; the gate did.

All three inverted, each kept rather than deleted, each carrying its previous expectation in the comment:

| Was asserting | Now asserts |
|---|---|
| a posted locale **is** applied | both halves of the lookup key are dropped |
| the model's uniqueness validation answers 422 | the locale never reaches the model, so that validation is not consulted — it was the last line, the permitted list is now the first |
| the seed creates a second section and leaves an orphan at the Arabic URL | one row, same id, **no orphan**, article still attached |

A fourth example was green and had to change anyway: it asserted that `0`, `false`, `no` and `off` are all
truthy — true of Ruby, and exactly the `ADOPT_UNTRACKED` defect — while the task now accepts `1` alone. **A
passing test that describes behaviour which no longer exists is worse than no test.**

### K2 — Run 2: GREEN, all five phases

```
A: rake load_tasks        126 tasks load, the documentation ones among them
B: eager load (production boot shape)
C: clean test database    articles=0 categories=0 portals=0 super_admins=0 documentation_media=0
D: rspec -- 51 files      1377 examples, 0 failures        (1m 44s, baseline origin/lynomia-custom)
E: vitest -- 19 files     19 files, 230 tests, 0 failures   (8.9s)
all phases passed         GATE_EXIT=0
```

Phases A and B are the first time anything in this program has executed a `.rake` file or an eager load. Both
pass. Phase E is the first time the gate has run the editor's own tests rather than trusting a hand check.

### K3 — What the gate still cannot see, printed every run

**25 changed files are covered by neither selector** — the report that now prints them is the only defence
against a fifth round of "the gate selected nothing for the thing that broke". Not all 25 are uncovered in
substance: `media_controller.rb` is exercised by `media_delivery_spec` and `media_boundary_spec`, and
`markdown_renderer_url_sanitizer.rb` by two renderer specs — the selector matches **basenames**, so a file whose
tests live under another name reads as uncovered. Two are genuinely untested and are **A6-O5**:
`markdownSource.js` and `mediaUpload.js`, the editor's only route to the upload API.

### K4 — The program's own count: five selection misses, and where each was caught

| # | What broke | Caught by |
|---|---|---|
| 1 | the public documentation home page 500'd; the gate's hand-written list named a directory, not the sibling file | production-shaped manual check |
| 2 | `markdown_embeds_spec` went red on the mainline; no subject pattern matched `markdown_embeds` | the mainline |
| 3 | a `.rake` class body broke **every** rake task including `db:migrate` | trying to apply a migration |
| 4 | the sitemap rewrite left an upstream spec asserting 3 URLs | **the gate, phase D** |
| 5 | the fixes for F3 invalidated the specs that proved F3 | **the gate, phase D** |

Misses 1–3 were caught by accident. 4 and 5 were caught by a mechanism. That is the difference phases A–E were
built for, and it is the one claim in this record that two runs of evidence actually support.

## L. Pre-merge owner rulings

The gate was accepted as green and **MERGE-GO was withheld** pending five rulings. This section records each as
closed, with the evidence. Rulings 1, 2 and 4 are the Orchestrator's; 3 and 5 went to agents.

### L1 — Ruling 1: sections are repository-authored, and the UI no longer says otherwise

> Repository is the sole author of: name, description, position, icon. Do not build field-by-field
> merge/digest protection for these fields now. Do not leave these fields appearing editable in Super Admin if
> the seeder will overwrite them. … The UI must not promise editability that the source-of-truth contract
> rejects.

No digest protection built, as instructed. The question was therefore only *what remains editable on a
section*, and the answer is **nothing**:

| Field | Author |
|---|---|
| `name`, `description`, `position`, `icon` | the manifest, by this ruling |
| `slug`, `locale` | identity — the two halves of `find_or_initialize_by(slug:, locale:)` (`content_seeder.rb:98`) |
| `portal` | the same lookup is `portal.categories.…`, so moving a section between portals re-creates it in the original and orphans the moved row — the defect class §I4 and §J2 already closed twice |

So **the edit surface is withheld at the route**: `resources :categories, except: [:edit, :update]`. Not by
emptying a form, for two reasons. It is the earliest shared entry point, so there is no PUT whose params need
permitting — CLAUDE.md's rule rather than a preference. And Administrate decides whether to render an Edit
button from the **real route table** (`existing_action?` is `routes.include?([resource, action])`,
`administrate-0.20.1/app/controllers/administrate/application_controller.rb:117-120`), so the button disappears
on its own. An empty form behind a live route would still be a promise.

`FORM_ATTRIBUTES_EDIT`, added one wave earlier, is now dead and removed. `FORM_ATTRIBUTES` stays and serves
`new`/`create` only: a hand-made section has no manifest row, so the operator is its only author. `destroy`
stays — `has_many :articles, dependent: :nullify` (`app/models/category.rb:49`), so a deleted section is
re-created by the next seed and its articles reattach.

**Article → category assignment is untouched**, as the ruling allows: that is a field on the *article*, governed
by the article source-of-truth rules.

Measured, not assumed — and one measurement changed the specs:

```
PUT  /super_admin/categories/:id        -> 404, name unchanged
GET  /super_admin/categories/:id/edit   -> 404
GET  /super_admin/categories/:id        -> 200, no /edit link in the body
GET  /super_admin/categories            -> 200, no /edit link anywhere
GET  /super_admin/categories/new        -> 200, all five fields offered
```

A first attempt asserted `raise_error(ActionController::RoutingError)` and failed: `show_exceptions` is `true`
in this app's test environment, so the request is **rendered as 404** rather than raised. A second measurement
found that a 404 earlier in an example **drops the Devise session**, so a page assertion placed after one reads
302 and would have passed for the wrong reason — each request now lives in its own example.

Three spec files were updated because the endpoint they exercised no longer exists. In each case the replacement
is a stronger claim, and the previous expectation is recorded in the comment:

| File | Was | Now |
|---|---|---|
| `documentation_editor_spec.rb` | four examples asserting which **fields** the section form dropped | five asserting there is no form, no PUT, and no Edit link on either page — 21/0 |
| `tenant_help_center_removal_spec.rb` | a section-update row in the 10-endpoint refusal table | the row removed (the table lists endpoints that exist) plus one example asserting the route is absent **for a super admin as well as a tenant** — 64/0 |
| `source_of_truth_boundary_spec.rb` | two examples on which fields the PUT dropped | one asserting there is no endpoint; the single-locale orphan example now asserts the 404 explicitly rather than only the absence of damage — 14/0 |

**Not done, deliberately:** no explanatory note on the section page. Administrate's show template is a 65-line
global override, so a per-resource copy for one sentence is more churn than the ruling asks for. An operator
sees a read-only page, which is the honest UI; a note would be an improvement, not a correction.

### L2 — Ruling 2: the CI gap, closed and proven both ways

> Update the real CI so it executes the same rake/eager-load checks that caught the deploy-breaking .rake
> defect. Add the minimum required invocations to run_foss_spec.yml. Do not broaden or redesign CI beyond what
> is required to close this measured gap. Prove the CI commands locally before final integration.

One step added to the existing `backend-tests` job in `.github/workflows/run_foss_spec.yml`, after the schema
load and before the specs. No new job, no new service, nothing else changed.

```yaml
      - name: Check rake tasks load and the app eager loads
        if: matrix.ci_node_index == 0
        env:
          RAILS_ENV: test
        run: |
          TASKS="$(bundle exec rake -T)"
          echo "$TASKS"
          echo "$TASKS" | grep -q 'documentation:content'
          bundle exec rake zeitwerk:check
```

Three choices worth stating. **`if: matrix.ci_node_index == 0`** because these are properties of the revision,
not of a shard — the job is a 16-node matrix and running them 16 times is 16 copies of one answer.
**`grep -q`** because an empty task list would otherwise pass as exit 0, which is the same green-for-the-wrong-
reason this step exists to stop. **`RAILS_ENV: test`** because `rake -T` in development also loads
`lib/tasks/annotate_rb.rake`, whose gem is in the development group.

**Proven both ways, locally, with the step's commands verbatim.** Passing on this revision:

```
rake -T lines: 126
grep documentation:content -> FOUND
Hold on, I am eager loading the application.
All is good!
STEP_EXIT=0
```

And failing on the defect it exists to catch — a throwaway `.rake` file whose class body dereferences an
application constant at load time, the exact shape of §H3, created and deleted in one command:

```
=== exit code with the defect present: 1 ===
rake aborted!
NameError: uninitialized constant ZzCiGapProbe::Probe::DocumentationHelper (NameError)
```

That closes **A6-O6**: the §H3 regression would no longer reach the mainline through CI.

### L4 — Ruling 4: the Help Center title

> Fix the shared Help Center title / Super Admin preview title if it remains a small isolated patch. Do not
> describe it as an SEO/indexability issue. It is a presentation/preview correctness issue.

It remained a small isolated patch: **one line changed and one added** in
`app/views/public/api/v1/portals/articles/_meta_head.html.erb`. `<title>` now reads
`article.meta["title"].presence || article.title` — the same value the `meta`, `og:` and `twitter:` titles
beside it already used. The conditional block that emits those tags is untouched.

Framed as the owner directs: **presentation and preview correctness.** The operator-visible consequence is that
`SuperAdmin::ArticlesController#preview` redirects to `?show_plain_layout=true`, `set_view_variant` gives
`:plain` priority over `:documentation` (`base_controller.rb:27-31`), and this shared template renders there —
so an operator previewing an article never saw the SEO title they had just set. No crawler was reading either
value: that variant publishes no canonical and `robots.txt` disallows `/hc/*?show_plain_layout=`.

Three examples added to `documentation_editor_spec.rb`: Preview lands on the plain variant of the real public
page; the SEO title appears there; and the article heading is used when no SEO title is set. The first carries
a **discriminator** — `expect(response.body).not_to include('<title>Audit logs | ')` — so it fails if `<title>`
ignores the override, which is what it used to do.

**Proven both ways**: with the one-line change reverted the file is `21 examples, 1 failure`; with it, 21/0.
One measurement shaped the spec: without a `custom_domain` on the portal the public page answers **401** from
`ensure_custom_domain_request` (`public_controller.rb:9-20`), and an example written without it would have been
measuring the domain guard rather than the title.

> **CORRECTION, issued in §M2.** The paragraph that stood here read: "`articles_controller_spec` + `seo_spec` =
> 59 examples, 0 failures, so the shared template's other consumers — every tenant Help Center — are
> unaffected." That conclusion does not follow from that run, and the claim is false twice over.
>
> The partial has **two** consumers, not one: `articles/show.html.erb`, the classic tenant Help Center article
> page, and `articles/show.html+plain.erb`, the preview variant. The change is therefore **tenant-visible and
> crawler-visible** — only the preview variant is disallowed by `robots.txt`, and the sentence above about no
> crawler reading either value is true of the preview variant alone. And at the time of that run no example
> anywhere set `meta['title']` on a tenant article and asserted `<title>`: the 59/0 showed **no regression**,
> which is not the same as showing tenants unaffected. A green suite that never exercises a property is silent
> about it, not confirmatory. §M2 records the two examples that close the gap.

### L5 — Ruling 5: the two untested editor-path files, and the integration chain

> These are not acceptable as untested because they are on the editor/media critical path. Add focused tests for
> both. Also add one integration path proving: Super Admin authorized upload -> Portal-owned documentation media
> -> stable media: key/reference -> article renderer resolution -> authorized application-owned delivery.
> Include negative assertions for: tenant cannot upload / wrong portal cannot resolve/deliver / draft media is
> not exposed to an unauthorized public request / missing/invalid media key fails safely.

Verified by me on my own database and toolchain, not accepted on report:

| Run | Result |
|---|---|
| `markdownSource.spec.js` + `mediaUpload.spec.js` | **2 files, 44 tests, 0 failures** |
| `media_end_to_end_spec.rb` | **6 examples, 0 failures** |
| `corpusRoundTrip.spec.js` after my comment correction | 22 tests, 0 failures |
| eslint, the quoted `**/*.{js,vue}` glob | clean |

**The integration chain is one example that performs every step for real** — a real multipart POST as a
signed-in super admin, the attachment that lands, the `markdown` the server returns (not rebuilt), that string
saved into an article, a real GET of the public page through `ChatwootMarkdownRenderer#render_article`, and a
real GET of the `src` the page itself minted. Its **sensitivity is proven rather than assumed**: mutating one
character of the key saved into the article turns it red at the renderer step.

The step worth naming is the alt. `MediaUpload#markdown_for` escapes `[`/`]` with backslashes, and the chain
asserts the operator's literal `Step 2 [see note]` survives CommonMark and reaches the page as text — a
cross-boundary property no per-boundary spec held.

The four negatives each carry a **control in the same example**, which is what makes them mean something: the
wrong-portal 404 sits beside the right portal serving the same key at 200, so the refusal is about the portal
and not a broken key; the draft negative runs anonymous → tenant administrator → super admin on one key and one
URL, so "signed in" is visibly not the predicate, "signed in as a super admin" is; and the invalid-key negative
asserts all six hostile shapes produce **identical** `[404, empty body, no Location, nosniff]`.

#### L5.1 — `df247fb8` carried a RED snapshot, and the label is why that is not a problem

The agent's report flagged that my in-flight commit `df247fb8` captured `media_end_to_end_spec.rb` between its
first run and its fixes — **6 examples, 3 failures** at that commit. That is exactly what the commit message
said it was: *"NOT a verified state … no suite was executed against these files."* The green version is the one
integrated here, and I re-ran it myself before integrating. The prettier reformatting the agent noticed on its
two JS files was the husky pre-commit hook running lint-staged on that snapshot, not an edit by anyone.

#### L5.2 — Finding 1 was a real defect in shipped work, and it is fixed

**The editor's preview pane never showed an uploaded image.** `preview_markdown` called `render_article` with no
resolver, so every `media:` reference rendered as an inert comment. An operator uploaded an image, the editor
inserted the server's own Markdown, and the preview showed nothing — while the published page and the `preview`
member action were both correct. Ruling R3 point 6's defect class **inverted**: a preview showing less than the
published page.

Fixed, with the resolver the public page already builds, per request and per portal:

- `preview_markdown` permits `:id` and passes `media: preview_resolver(permitted[:id])`.
- The portal comes from the **found article**, not from the posted form, so a posted id cannot point the
  resolver at a portal the operator is not editing. `scoped_resource` keeps it to platform portals and the
  action is Super Admin only. Pinned: an article on a tenant portal resolves to nothing, and the response
  contains no trace of that portal.
- `_content_editor.html.erb` passes `articleId`; `ArticleEditor.vue` posts it beside the content.

**A limitation stays, and is asserted rather than left to be discovered:** an unsaved article has no slug, so
`MediaResolver#image_for` has no address to mint, and a new article's preview shows the inert comment until its
first save. Widening the resolver to an article-less form is Agent 1's interface call
(`R2-MEDIA-INTERFACE.md` §2.1), not something to improvise at integration. Three examples added; **proven both
ways** — with the resolver removed the file is `24 examples, 1 failure`, with it 24/0.

#### L5.3 — Findings 2 and 3: two new defect classes in the WYSIWYG pair, inert today

Both are in the ProseMirror pair that ruling R3 keeps **closed**, and both are pinned in
`markdownSource.spec.js` rather than left as prose:

- **An alt is truncated at the first backslash escape.** `![Step 2 \[see note\]](media:…)` round-trips to
  `![Step 2 ](media:…)` — prosemirror-markdown reads the alt from the first inline token only. This is the
  **sixth** measured defect class, and the one that matters most, because the escaped form is exactly what
  `MediaUpload#markdown_for` composes: the day WYSIWYG reopens, operator alt text with brackets is lost
  silently.
- **An image inline with prose is not a fixpoint.** `'before ![Alt](…) after'` needs **two** passes to settle,
  where every class `corpusRoundTrip.spec.js` measures settles after one. Two consecutive WYSIWYG saves of one
  unedited article would produce two different files.

I corrected the comment on `corpusRoundTrip.spec.js`'s image example, which read as though the media grammar
survives the pair unconditionally. It survives for an alt needing no escaping; that is now what it says, and it
points at the spec holding the other half. **No assertion changed** — this was accuracy, not coverage.

#### L5.4 — Findings 4 and 5: recorded, no change

**Two refusal shapes on one resource**: `POST …/documentation_media` answers 302 to the sign-in page while
`PATCH …/documentation_media/<key>` answers **401**, because the replace path ends in `.png` and Rails takes the
format from the extension, so Devise's failure app picks `http_auth` over a navigational redirect. Already
measured in §J6 from the other direction; consistent. The operator-visible consequence is that an expired
session shows the raw status text in the editor. Pinned, no change requested.

**A 404's declared Content-Type follows the requested path**, so `…/media/a/b.svg` refuses as
`Content-Type: image/svg+xml`. Inert — zero-byte body and `nosniff`, both asserted — but it is
attacker-influenced metadata on a refusal, so it is written down rather than left to be re-found.

#### L5.5 — `markdownSource.js` has no production consumer, and is not dead code

`parseMarkdown` and `serializeDoc` are exported and called only by `roundTrip`, which is called only by
`corpusRoundTrip.spec.js`. CLAUDE.md says remove dead code, and this is deliberately kept: that module **is**
the mechanism that keeps ruling R3's gate honest. It is the tripwire that goes red the day the ProseMirror pair
becomes safe enough to adopt, and deleting it would delete the evidence the ruling rests on. Recorded as a
judgement rather than left implicit, since a future reader will otherwise read it as an oversight.

#### L5.6 — Open items from ruling 5

| # | Item | What closes it |
|---|---|---|
| A2'-O1 | ~~Editor preview shows no uploaded image~~ | **closed** in §L5.2 for a saved article; the unsaved case is the recorded limitation |
| A2'-O2 | `mediaUpload.js` resolves a **2xx whose body is not JSON** with `{}`, so the editor would insert `undefined`. Deliberately not covered: the server always renders JSON on 201, and asserting either behaviour would bless a choice nobody has made | a decision on whether an unparseable 2xx is an error |
| A2'-O3 | `mediaUpload.js` has no request cancellation, where the preview path has an `AbortController`. The concurrency guard lives in the component | one example in `ArticleEditor.spec.js` |
| A2'-O4 | ~~`markdownSource.js` is unused~~ | **answered** in §L5.5: kept, as the R3 tripwire |
| A2'-O5 | Not covered in `markdownSource.spec.js`: Arabic/RTL round-tripping (`corpusRoundTrip.spec.js` samples it; duplicating it would re-measure another spec's subject) and non-string input (raises from the tokenizer; no caller can pass it) | nothing, unless the module gains such a caller |
| A2'-O6 | The two halves meet at the **documented wire shape**, not in one process: the JS spec mocks `fetch`, the Ruby spec drives the real route with the same params. The one real cross-language assertion is the `ACCEPTED_TYPES` ↔ `CONTENT_TYPES` mirror, which goes red on drift from either side | a browser-driven test, which this program has none of |
| A2'-O7 | **Not verified, in those words**: production data, and browser rendering — every markup claim is parser-based, Nokogiri server-side and jsdom client-side | a real browser |

### L3 — Ruling 3: the seeder failure model

> Do NOT wrap the entire seeder in one large transaction. ActiveStorage/filesystem/object-storage work makes
> that a misleading atomicity boundary. Instead implement: A. full no-write preflight … B. deterministic
> idempotent apply … C. if apply fails: report exactly what completed and what failed, leave the task safely
> rerunnable, do not silently continue. No speculative global transaction.

**No transaction anywhere**, as ruled. `perform!` is now `preflight!` then `apply!`, with a nested `Corpus`
holding the files-and-manifest side that touches no database. 274 → 536 lines.

Nine checks, all collected into **one** `PreflightError` naming every offending file rather than the first:
manifest shape; manifest sections **==** directories, both directions, per seeded locale; every file parses;
required fields including a non-empty body; reserved slugs; slug uniqueness within the corpus; no row outside
this run already holding an intended slug; every `media:` reference's key grammar **and** its file; and the
provenance class of every row decided before any write.

#### L3.1 — The no-write requirement, proven rather than asserted

Every `sql.active_record` payload matching `INSERT|UPDATE|DELETE` recorded across a `perform!` on a corpus that
cannot apply:

```
statements == []
[Article.count, Category.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count] == [0, 0, 0, 0]
```

The measurement that makes this worth having is the **baseline on the shipped seeder, taken before the file
changed**, on the same corpora:

```
F7     RAISED ActiveRecord::RecordNotUnique   left rows=3 cats=2
F8     OK created=1 updated=1 rows=1          # two files, ONE row, the later section won, nothing reported
MODE1  RAISED RecordInvalid (Content blank)   left rows=1 cats=1
MODE2  RAISED RecordInvalid (Slug reserved)   left rows=1 cats=1
MODE4  RAISED Psych::DisallowedClass          left rows=1 cats=1
MODE5  OK rows=1 for 2 files                  # no error, no count
MODE3b RAISED RecordNotUnique                 left rows=1 cats=2
MEDIA  OK rows=1, published_with_broken_ref=1 # nothing checked
```

Every one of those now refuses with zero rows and zero categories.

#### L3.2 — Phase C: what an operator actually sees

```
========== APPLY FAILURE ==========
articles: 1 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
articles: APPLY FAILED at …/en/getting-started/zebra.md: ActiveModel::RangeError: 2147483648 is out of range
The counts above are everything that completed, and they are committed: nothing was rolled back and no file
after this one was applied. Fix the cause and run the task again -- every write is an upsert on
(slug, locale), so a re-run reapplies the completed rows as `unchanged` and carries on from the file that
failed.
```

The failure used is one the preflight **genuinely cannot see**: `position: 2147483648` is an Integer, so the
check passes, and it overflows `int4`, so the write fails. That is the case phase C exists for, rather than a
contrived one. Rerunnability measured: `2 created, 0 updated, 1 unchanged` on the next run.

Real-corpus idempotency unchanged: `138 created` → `0/0/138 unchanged` → `0/0/138 unchanged`; 5.6s then 4.9s.

#### L3.3 — Three deliberate deviations from D9 as written, each recorded

The body check is **unconditional** rather than "when published", so there is no branch on a condition no
corpus file expresses. The cross-corpus half of item 4 is checked against the **rows** rather than the other
corpus on disk, since either way whichever task runs second refuses before its first write. And
`content_source_path` is **not** pre-checked: two files cannot claim one path, because the path *is* the file,
and the only colliding shape is two files swapping basenames inside one run — which is the rows-direction query
A5-O2 is open for and which the brief ruled out widening into.

#### L3.4 — F7, F8, A6-O1 closed; A6-O3 answered as the owner ruled

| Item | Was | Now |
|---|---|---|
| **F7** cross-locale slug collision | `RecordNotUnique` mid-run, **3 rows and 2 categories committed** | refused, naming both files, zero rows |
| **F8** one basename in two sections | `1 created, 1 updated`, one row, later section wins, **silent** | refused, naming both files, zero rows |
| **A6-O1** adoption reported nothing | `N adopted` and no divergence line | an `:adopted` divergence carrying the class-C fields the corpus took back |
| **A6-O3** `perform!` not transactional | the five abort modes all left partial state | **no transaction**, as ruled: four are preflight refusals and a post-preflight failure is reported and rerunnable |

Class A is deliberately excluded from the `:adopted` divergence: the corpus owns prose on every run for every
row, so listing it would report the design rather than the adoption.

#### L3.5 — The three requested changes, applied — and one bug I introduced applying them

**8.1 — `MediaSeeder` gets the same treatment** (`media_seeder.rb`, Agent 1's file). Its grammar checks already
ran before any write, but the **missing-file** check sat inside the write loop, so a corpus whose tenth key had
no file uploaded nine blobs and then raised — F7's shape, one file over. Now `preflight!` + `require_file!`.
The ruling applies to that seeder for the same reason it applies to the other one.

**I broke it while applying it.** The submitted diff kept `references.each { |key, reference| seed(key, reference) }`;
I "tidied" it to `references.each { |key| seed(key) }`, and `Hash#each` with one block parameter passes the
`[key, value]` **array**, so `seed` would have received an array and `media_dir.join` would have failed.
**RuboCop passed on the broken version** — 1 file, no offenses — which is the whole point: a linter cannot see
this and only a test can. Corrected to `each_key`. `media_seeder_spec` + `media_delivery_spec`: **31 examples,
0 failures**.

**8.2 — three examples in `source_of_truth_boundary_spec.rb` pinned the defects this ruling closes**: measured
`14 examples, 3 failures` at HEAD. Applied the submitted patch, which inverts rather than deletes and keeps each
previous expectation in the comment. **14/0.** This is the **fourth** time in this program that fixing a defect
invalidated the specs proving it, and the third time a mechanism rather than a person caught it.

**8.3 — seven stale `content_seeder.rb:<line>` citations** across five files, all comments. This program grades
`file:line`, so a wrong replacement is worse than a stale one: **I read each proposed target line before
replacing it** — `256` `def read_file`, `261` the slug derivation, `298` the author guard, `384`
`def upsert_category`, `423` `article.author ||=`, `437` `meta['doc_key'] =`. All seven confirmed, all replaced,
and a sweep for the old numbers across `config app custom spec lib` returns nothing. Historical records under
`discovery/**` are left as they were.

#### L3.6 — One RuboCop suppression, and why it stays

A targeted `# rubocop:disable Style/OneClassPerFile` on the nested `Corpus`, with the reason above it. The
repo's own cop allowlists name **suffixes** (`Builder`, `Validator`, `Result`, …) rather than nesting, so the
alternatives were a class named to satisfy a linter or a new file. Without the extraction the class is
`279/175` on `Metrics/ClassLength`.

**Kept as submitted.** Extracting to `content_seeder/corpus.rb` is the other clean answer and is cheap to do
later; taking a late file move for a one-line suppression, immediately after a measured change and immediately
before a merge gate, buys nothing. Recorded so the choice is visible rather than inherited.

#### L3.7 — A5'-O1: NOTHING SEEDS CORPUS MEDIA. Verified independently, and it needs an owner decision

> **SUPERSEDED by §N1–§N13. A5'-O1 is CLOSED.** The owner ruled, and the wiring landed:
> `ContentSeeder#preflight!` calls `media_seeder.preflight!` (`content_seeder.rb:377`) and `ContentSeeder#apply!`
> calls `media_seeder.perform!` first (`content_seeder.rb:436`). Everything below is left exactly as it was
> written, including the sentences that say nothing calls the seeder and that the decision is outstanding: they
> were true when measured and are not true now. The table's line numbers are that pass's positions. In the
> current tree the comments naming `MediaSeeder` are at `content_seeder.rb:65` and `:86` — the second is new in
> this delta — and the `MEDIA_DIR` read is at `:254`.

`Documentation::MediaSeeder` is implemented, specced and documented — and **no production path calls it.**
I ran the no-exclusion search myself rather than taking the claim, and classified all 26 hits:

| Where | Hits | Kind |
|---|---|---|
| `R2-MEDIA-INTERFACE.md` | 13 | documentation |
| `P2-SOURCE-OF-TRUTH-CONTRACT.md`, `P2-WORKSTREAM-OWNERSHIP.md` | 6 | documentation |
| `content_seeder.rb:57`, `media_upload.rb:14`, `custom_markdown_renderer.rb:113` | 3 | **comments** |
| `content_seeder.rb:239` | 1 | reads `MEDIA_DIR`, the constant — **not** a call |
| `media_seeder_spec.rb`, `media_delivery_spec.rb:200` | 2 | **specs** |
| `media_seeder.rb` | 1 | its own definition |

**No rake task, no job, no controller, no seeder call.** `R2-MEDIA-INTERFACE.md` §3.2 assigns that one line to
`content_seeder.rb` and it was never written.

Latent today, for one reason only: the corpus has **zero images**. The live failure mode is precise — the moment
a corpus image and a reference to it are both added, the preflight passes (the file is there), nothing attaches
it, and the article publishes the unresolved-key comment.

**Deliberately not wired here.** It needs a `Result` member, a report line and §3.2's ordering, so it is a
mechanism rather than a line, and landing an unmeasured one in the same pass as a measured failure-model change
is the thing this program's discipline exists to prevent. **This is the single most consequential item
outstanding and it is an owner decision**, not an open item to carry quietly.

#### L3.8 — Open items from ruling 3

| # | Item | What closes it |
|---|---|---|
| **A5'-O1** | **Nothing seeds corpus media** (§L3.7) | an **owner decision**, then a change of its own — since **CLOSED** both ways: the owner ruled and the change landed (§N, and the table at §N's head) |
| A5'-O2 | A **basename swap inside one run** still fails mid-apply on the `content_source_path` index, now as a reported `ApplyFailure`, and fails identically on every re-run | the rows-direction query A5-O2 is already open for |
| A5'-O3 | The preflight cannot see a value the **database** rejects; `int4` overflow is the measured instance | nothing — phase C is the ruling's answer |
| A5'-O4 | A manifest section with no directory is now **refused** where it used to create an empty category, so adding a section before its articles is a red task | nothing, unless the owner wants it demoted to a warning; D9 asks for set equality |
| A5'-O5 | The `:adopted` divergence lists `meta.tags` when the row's key is absent and the file's value is `[]`, because `digest(nil) != digest([])`. Accurate but noisy | a decision that `nil` and `[]` are one value, which changes the digest payload and so `DIGEST_VERSION` |
| A5'-O6 | **Not verified, in those words**: production data, the `media:` grammar against a real image (the fixture is a non-PNG byte string; content type is `MediaUpload`'s job and specced there), and browser rendering |

## M. Agent 6's delta-only review, and the two blocking items it found

Agent 6 reviewed only `4778d737..727a4cfd` — the rulings 1/2/4/5/3 delta — and returned: *"The code is merge-ready.
The record is not, and one spec asserts something false."* No security defect, no tenant-reachable authoring path,
no regression against §J. Ruling 1's enforcement holds against the full 16-route category table. Ruling 3's
preflight is write-free on 15 crafted corpora plus the adoption path. The preview resolver leaks no row's
existence — 12 `id` shapes, all byte-identical. The gate still selects correctly: 52 rspec + 20 vitest with
`GATE_BASE_REF=4778d737`.

Two of its six requests were marked **must**. Both are closed below, and the four **should** items with them.

### M1 — RC-6: a spec named "is still creatable" over an endpoint that 422s on every input

Agent 6's charge was that this is *"the same class of defect ruling 1 was issued to fix"* — a surface the record
and the suite described as working, which was not. I verified it myself before acting, with a throwaway probe
spec:

```
PROBE full_form status=422 created=0
PROBE body_error="Slug can&#39;t be blank"
PROBE tenant_portal status=422 created=0
PROBE permitted_create=["portal_id", :name, :description, :locale, :position, :icon]
PROBE category_has_slug_derivation=[]
```

Confirmed, and the cause is two facts that meet: `slug` was deliberately held off `CategoryDashboard::FORM_ATTRIBUTES`
(§L1, for the same reason it is off `ArticleDashboard`'s), and `Category` validates `slug` presence
(`app/models/category.rb:86`) with **no** derivation from `name`. So `POST /super_admin/categories` could never
succeed, for any input, and `documentation_editor_spec.rb` asserted only that the *form rendered*, never that a
row was created.

**Resolved by RC-6(a): withhold the route.** `config/routes/documentation.rb` is now
`resources :categories, only: [:index, :show, :destroy]`.

Why that over "just permit `slug`": the fourth probe line. The permitted list carried an unscoped `portal_id`,
and Administrate's `create` is **not** scoped — `create` → `new_resource(resource_params)` → `resource_class.new`
(`administrate-0.20.1/app/controllers/administrate/application_controller.rb:43` and `:271-273`), where `show`
and `destroy` both go through `scoped_resource`. `Field::BelongsTo`'s `scope:` filters the select options and
nothing else. Making the create work would therefore have opened a write into **any** portal, tenant portals
included, rather than restoring a feature. Withholding the route closes a dead surface and that latent hole in
one line.

`CategoryDashboard::FORM_ATTRIBUTES` is **deleted**, not emptied. Traced before deleting: `form_attributes` is
reached only from `Administrate::Page::Form` (`lib/administrate/page/form.rb:14`) and from `permitted_attributes`,
which the controller calls only for `create`/`update` (`application_controller.rb:204-206`); `Field::HasOne` also
calls `permitted_attributes` on another dashboard, and no dashboard in either tree declares a `HasOne` or
`HasMany` pointing at `Category`. With all four form actions gone the constant has no reader. `index`, `show`
and `destroy` read `COLLECTION_ATTRIBUTES` and `SHOW_PAGE_ATTRIBUTES`, so every field stays visible and
searchable while none is writable.

**Measured both ways.** The example formerly named *"is still creatable, with every field offered on the new
form"* is replaced by three: no `new` route, no `create` route (`.not_to change(Category, :count)` **and** 404),
and no New link on the list page. Against `HEAD` restored for both files — old routes **and** old dashboard —
`4 examples, 3 failures`: all three new examples fail, and the fourth (no Edit link in the list) passes in both
states, correctly, because `edit` was already withheld at `727a4cfd`. With the change: `26 examples, 0 failures`.

**A defect of my own, caught by that measurement.** My first "offers no New link" example asserted
`include('Administration')` as a string, and failed: `category` is a lazy `let`, so referencing it only inside
the assertion creates the row **after** the page has been rendered. Changing the assertion to `category.name`
did not fix it — same lazy evaluation, one step later. The row has to be forced before the request. That makes
the sibling example written for ruling 1 — *"offers no Edit link in the section list either"* — **green for the
wrong reason**: it asserted `not_to include(".../edit")` over an **empty** list, which would pass with the
button still on the page. Both list examples now bind `section = category` before the `get` and assert
`include(section.name)` first, so an empty list fails them.

`docs/global-documentation/07-super-admin-management.md` said `super_admin/categories` was **"full CRUD"**. It is
now `(index, show, destroy)`, with a paragraph stating the contract beside the one that already explained why
portals are not creatable.

### M2 — RC-5 and the §L4 correction: the tenant Help Center title was unpinned

Agent 6's finding, verbatim: *"A tenant-visible, crawler-visible change is currently recorded as 'every tenant
Help Center — unaffected', and nothing pins it."* Correct on both halves, and §L4 now carries the correction
inline.

The partial has **two** consumers, traced rather than assumed:
`app/views/public/api/v1/portals/articles/show.html.erb` (the classic tenant article page) and
`show.html+plain.erb` (what Preview lands on). `show.html+documentation.erb` renders
`documentation_layout/articles/_meta_head` instead and is untouched. So the change reaches a **crawlable** tenant
page — `RobotsController::DISALLOWED_PATTERNS` disallows `/hc/*?show_plain_layout=` and not the classic article
URL — and the 59/0 run §L4 cited proved only that nothing regressed, because no example anywhere set
`meta['title']` on a tenant article and read `<title>`.

**Two examples added** to `spec/controllers/public/api/v1/portals/articles_controller_spec.rb`, both directions:
the SEO title appears in `<title>` when a tenant sets one, with the discriminator
`not_to include("<title>#{article.title} | ")`; and the article title is used when none is set. Measured against
the pre-fix template: `2 examples, 1 failure` — the override example fails, the fallback example passes in both
states, which is what makes it a regression pin rather than a restatement. With the fix, 2/0.

The comment at the head of the partial has been rewritten to name both consumers and to confine the
"no crawler was reading either value" statement to the preview variant, where it is true. **For the PR body:
this is a tenant-visible product change**, not an internal one.

### M3 — The four `should` items

| # | Agent 6's request | Applied |
|---|---|---|
| RC-1 | Anchor the CI grep | `grep -q '^rake documentation:content'`, matching `scripts/documentation_gate.sh:273`. Measured: `rake something:else  # ... see documentation:content ...` passes the old pattern and is **rejected** by the anchored one. The real `rake -T` still matches, and `rake zeitwerk:check` is `All is good!` |
| RC-2 | `article_dashboard.rb:42` cites `#slug_for`, which does not exist | now `Documentation::ContentSeeder::Corpus#read_file`, with what it actually does — basename for the default locale, `basename-<locale>` otherwise (`:256-261`) |
| RC-3 | `article_meta_field.rb:34` cites `#meta_for`, which does not exist | now `#merged_meta`; the `library.rb` line number corrected from `:55` to `:63`, where the `doc_key` query really is |
| RC-4 | The checksum rationale ended up heading `preflight!` after my `each_key` fix | moved back above `seed`, where the checksum comparison is. `preflight!` keeps the ruling-3 rationale |

One citation Agent 6 did not flag, found while checking its three: `documentation_helper.rb:82-84` quoted
`find_or_initialize_by(slug: section['slug'], locale: locale)`, which was the hash-based shape before Agent 5's
rewrite made sections a `Struct`. Now `portal.categories.find_or_initialize_by(slug: section.slug, locale: section.locale)`.

### M4 — One addition beyond the review: ruling 3's requirement C had no spec

Ruling 3 asks that a failed apply *"report exactly what completed and what failed, leave the task safely
rerunnable, do not silently continue."* `Documentation::ContentSeeder` was specced for that; `DocumentationSeedReport`,
which is the half an operator actually reads, was not — and it is where the requirement is observable, because
it owns the text **and the exit code**.

`spec/lib/tasks/rake/documentation_seed_report_spec.rb`, 7 examples, covers all four outcomes, which differ in
exit code as well as in text: a clean run is zero; a clean run holding untracked rows is **non-zero** and names
`ADOPT_UNTRACKED=1`; a refused preflight is non-zero, says `NOTHING was written`, lists every offending file and
prints **no** counts; a failed apply prints the counts of everything that completed, then names the file, the
underlying cause, that the completed rows are committed and that a re-run is safe. `abort` writes to stderr and
raises `SystemExit`, so each aborting example asserts both streams — which also keeps the suite's own output
clean.

### M5 — Sharpened: what A5'-O1's silence now means

§L3.7 recorded that **nothing seeds corpus media** and that the live failure is an article publishing an
unresolved-key comment. This delta changes what the *absence of a report* means, and the distinction matters for
the owner decision. `Corpus#media_problems` (`content_seeder.rb:248`) now **certifies** every `media:` reference
in the corpus during the preflight. Before, a clean run was silent about media because nothing looked. Now a
clean run is an affirmative all-clear on the references — and a corpus image that exists, is referenced, and is
never attached still publishes unresolved, because certifying a reference is not attaching a file. The gap is
narrower and better reported, and it is unchanged in substance. **Still an owner decision.**

> **SUPERSEDED by §N1–§N13.** The owner decided, and the gap this section describes is closed: a corpus image
> that exists and is referenced is now attached by `media_seeder.perform!` before any row is written, so a clean
> run is an all-clear on the attachments as well as on the references. The paragraph above is kept as the record
> of what the absence of a report meant while it still meant something.

### M7 — The gate found a seventh thing, and it is the same class as §K1

The ONE combined gate on the delta came back **red**, at
`spec/security/documentation_v2/search_and_meta_escaping_spec.rb:128` — `1420 examples, 1 failure`:

```
expected "SEOPwn\" onload=\"alert(1)\" x=\"</title><script>alert(1)</script></script>]]>&  | Lynomia Chat
Documentation" to start with "Audit logs"
```

That example is named *"titles from `article.title` while the documentation variant titles from the SEO
title"*, and it asserted the **§G10 asymmetry on purpose**, as a deliberate pin of the behaviour §G10 declined
to change. Owner ruling 4 changed it. So this is the §K1 pattern again: a spec pinning the defect that the same
change set fixes.

Worth recording for three reasons.

**It was not selected by the delta review.** Agent 6 ran 52 rspec files with `GATE_BASE_REF=4778d737`, and §L4's
own proof ran `documentation_editor_spec` (21/0), then `articles_controller_spec` + `seo_spec` (59/0). None of
those is this file. The combined gate reaches it because selector 1 picks the documentation subsystem **by
subject**, not by what the branch touched — which is exactly the property §K4 counts, and the sixth time it has
earned its place.

**The expectation is inverted, not deleted.** Both variants now title from the SEO title, and the assertion the
example is really worth keeping is that the payload reaches `<title>` as TEXT on **both** — Nokogiri reads it
back whole and no `on*` attribute is created in either head. Neither variant had a pin for that. The old
expectation is recorded in the comment above the example so the inversion is visible to the next reader rather
than silent.

**It closes A6-O4 by fact.** §G10 left the shared-template branch as an owner decision; ruling 4 took it. There
is no asymmetry left to decide about, and §G10 now says so.

After the fix: `search_and_meta_escaping_spec` is `17 examples, 0 failures`.

### M8 — The last genuinely uncovered changed file, and the seam it hid

The gate's uncovered-file report (§K3) prints the files no spec basename matches. `markdownSource.js` and
`mediaUpload.js` have left it — ruling 5 gave them specs with matching names, which closes **A6-O5**. One entry
is new and one remained, so the count read 25 again before this section's own fix, and that coincidence is worth
spelling out rather than reporting an unchanged number as an unchanged situation. After the fix below the gate
reports **24**, and `app/javascript/entrypoints/superadmin_pages.js` has left the list — which is the report
confirming its own closure rather than my word for it.

Of the 25, **24 are uncovered by BASENAME only** and are exercised in substance; I checked each rather than
asserting it. The two `.rake` files are executed by phase A and `lib/documentation_seo_audit.rb` by phase B;
`lib/tasks/documentation.rake` is now additionally covered by `documentation_seed_report_spec.rb` (§M4), which
no basename match can see. `config/routes/documentation.rb`, both dashboards and `article_meta_field.rb` are
exercised by `documentation_editor_spec` and `source_of_truth_boundary_spec`; both `_meta_head` partials by
`seo_spec`, `articles_controller_spec` and `search_and_meta_escaping_spec`; `sitemap.xml.erb` by
`portals_controller_spec`; `robots_controller.rb` by `search_and_meta_escaping_spec`;
`portal_article_visibility.rb`, `media_controller.rb` and `documentation_media_controller.rb` by the three media
specs; the three `super_admin/articles/` partials by `documentation_editor_spec`; both `manifest.yml` files by
`content_seeder_spec`; `markdown_renderer_url_sanitizer.rb` by two renderer specs. `db/schema.rb`,
`config/locales/en.yml` and `.github/workflows/run_foss_spec.yml` are not code with a behaviour to pin — the CI
file's own commands were proven by hand (§L2, §M3).

The twenty-fifth was real: **`app/javascript/entrypoints/superadmin_pages.js`**, whose change is one
`ComponentMapping` key. Looking at it found a seam rather than a missing unit test. The Rails partial emits
`data-component-name="DocumentationArticleEditor"` (`_content_editor.html.erb:15`) and
`documentation_editor_spec.rb:221` pins **that** string; the registry key is the matching half and nothing
pinned it. A one-character divergence makes `ComponentMapping[componentName]` `undefined`, Vue logs
`Invalid vnode type when creating vnode: undefined` and mounts nothing — **the operator sees a blank editor and
both sides' own suites stay green.** `ArticleEditor.spec.js` mounts the component directly, so it cannot see the
registry at all.

`app/javascript/entrypoints/superadmin_pages.spec.js`, 2 examples, asserts the real path instead of comparing
two strings: build the `#app` element exactly as `render_vue_component`
(`super_admin/application_controller.rb:33-42`) does, dispatch `DOMContentLoaded`, and read back the textarea
the Administrate form posts, carrying the content the props supplied. **Measured both ways**: with the key
changed to `DocumentationArticleEditorX` the first example fails and the second — the negative case — still
passes, so the pin is on the two names matching rather than on the editor merely existing.

While checking that partial, its citation of `render_vue_component` read `:222-231`. The method is at `:33-42`.
Corrected, and the partial now names both halves of the contract and where each is pinned.

### M6 — Open items after the delta

| # | Item | What closes it |
|---|---|---|
| A5'-O1 | Nothing seeds corpus media | **closed** by the owner's final ruling and §N — the pass is wired, with the owner's A-I tests and a real run of both rake tasks |
| A6-O4 | §G10's `<title>` branch | **closed** by ruling 4 and §M7 — the asymmetry no longer exists |
| A5-O1 | Section ownership | **closed** by ruling 1 and §M1 |
| A6-O5 | `markdownSource.js` and `mediaUpload.js` untested | **closed** by ruling 5; both have left the gate's uncovered report |
| **A5'-O7** | A corpus key referenced only by an **operator-authored** article is purged by the next sweep that finds the corpus no longer referencing it (§N12) | widen `referenced_keys` to this portal's article content, or state the limit in R2-MEDIA-INTERFACE.md §6.2 — **owner decision** |
| A5'-O8 | The orphan sweep runs BEFORE the article loop, so an apply that purges an orphan and then fails in the rows leaves published articles referencing a purged key until the next successful run (§N9) | move the sweep after the loop, which needs a public `sweep!` and re-opens the public-surface finding §N11 closed |
| A5'-O9 | `MediaUpload#attachment_for` takes the FIRST attachment for a key while both indexes take the LAST, over an association with no `ORDER BY` (§N11) | matters only if the transient two-attachments-one-key window became permanent, which needs a failure inside `purge_later`'s own transaction |
| A5'-O10 | `seed` treats checksum identity as proof the storage object still exists, so a database restored without its storage reports `unchanged` forever (§N11) | one condition in `seed` — **owner decision**, since requirement 4 defines idempotency without it |
| A5'-O2 … O6 | Carried unchanged from §L3.8 | as recorded there |

## N. A5'-O1 closed: the corpus media pass is wired, and wiring it found two defects

> Owner ruling: *"preflight can certify a repository `media:` reference while apply never attaches that corpus
> file to the Portal. Today the corpus contains zero images, so the defect is latent. The first future corpus
> image could pass validation and publish unresolved. Complete the existing design; do not redesign it."*

### N1 — What was actually missing, and what already held

`Documentation::MediaSeeder` was implemented, specced and documented, and **seven of the owner's nine
requirements were already satisfied by its code**: the per-portal namespace and stable key (2), ActiveStorage
only (3), checksum idempotency with no global scan (4), scoped lookup (5), provenance by `content_source_path`
(6), an orphan sweep restricted to corpus-owned attachments (7), and no cross-portal reuse (8). Each of those
held only because nothing ran, which is why §N11 and §N12 then found defects in two of them.

The other two were not satisfied, and saying so matters more than the tally:

- **Requirement 1 had no caller at all.** R2-MEDIA-INTERFACE.md §3.2 assigns one line to `ContentSeeder` and it
  was never written, so the preflight certified `media:` references the apply never attached.
- **Requirement 9 was half there.** The service failed loudly and a re-run converged, but two decidable defects
  — bytes that are not a permitted raster type, and bytes over the cap — were still inside the write loop, so a
  failure could leave a partial write (§N11); and nothing REPORTED media at all: no `Result` member, no report
  line, so "reported clearly" had nothing to report with.

An earlier draft of this paragraph claimed nine of nine. That was the tally of what the service's own code
looked like rather than what the owner asked for, and it is corrected here rather than left standing.

So this delta is mostly a wiring change. The frozen contract already said where the line goes, and owner ruling
3 had since given **both** services a write-free preflight and an idempotent apply — which is what made the
completion obvious: **interleave the phases rather than call `perform!` from one place.**

| Phase | What runs | Why there |
|---|---|---|
| `ContentSeeder#preflight!` | `media_seeder.preflight!`, last | Write-free. It decides the four defects `Corpus#media_problems` cannot see — empty alt, a key in a **link** position, a destination CommonMark does not read as an image at all, a corpus file in the reserved `uploads/` namespace. All four are decidable without a write, so ruling 3 puts them before the apply |
| `ContentSeeder#apply!` | `media_seeder.perform!`, **first** | §3.2's ordering: every validated reference becomes an attachment before any row is written, so a media failure leaves the corpus untouched |

`MediaSeeder#preflight!` is **memoized**, so the preflight call and the apply call scan the 138 corpus files
once between them. Its `Error` is re-raised as `PreflightError`, which is how the operator gets the message
every other refusal prints — that NOTHING was written — instead of a Ruby backtrace. The cost is recorded in
the code rather than hidden: `MediaSeeder` raises on the **first** media defect where `refuse` lists all of
them, so a corpus with two of those four defects takes two runs to clear. Closing that is the non-raising
`MediaSeeder#problems` the frozen contract leaves open as Agent 1's decision.

### N2 — The Result and the report: one member, one line, the contract's own wording

`ContentSeeder::Result` gains the `media` member §3.2 names. It holds the **live** `MediaSeeder::Result`, not a
copy, published the moment the seeder is memoized — because an upload is outside any transaction, so an attach
that fails on the tenth key must still report the nine that landed. That is owner ruling 3's "report exactly
what completed" one level down, and it needed one new line of API: `attr_reader :result` on `MediaSeeder`.

`DocumentationSeedReport` gains one constant and one `puts`, worded as R2-MEDIA-INTERFACE.md §3.7 suggests
with two departures, both deliberate: `uploaded` prints as **attached**, because an attachment is the thing that
exists afterwards, and `unreferenced` is qualified **in the repository**, because what it counts are files in the
tree and not blobs in storage. **Measured, four real runs through the real report** (a temporary corpus, one image, one spare file):

```
--- RUN 1: first seed, one image attached, one unreferenced file in the tree ---
articles: 1 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
  media: 1 attached, 0 replaced, 0 unchanged (0 without dimensions); sweep: 0 purged, 1 unreferenced in the repository
--- RUN 2: identical re-seed, nothing written ---
  media: 0 attached, 0 replaced, 1 unchanged (0 without dimensions); sweep: 0 purged, 1 unreferenced in the repository
--- RUN 3: the image bytes changed in the repository ---
  media: 0 attached, 1 replaced, 0 unchanged (0 without dimensions); sweep: 0 purged, 1 unreferenced in the repository
--- RUN 4: the reference left the corpus, so the corpus-owned attachment is purged ---
  media: 0 attached, 0 replaced, 0 unchanged (0 without dimensions); sweep: 1 purged, 2 unreferenced in the repository
```

The sweep is a clause of its own, and that is §N11's finding rather than cosmetics: the sweep is the LAST thing
the media pass does, so on any earlier failure `purged` and `unreferenced` are not zero but UNKNOWN. They
initialise to `nil` and the clause reads `sweep: did not run`, because `0 purged, 0 unreferenced` would claim the
sweep ran and found nothing.

Four of the owner's five categories are counters. The fifth, **failed, is deliberately not one**: the pass
fails loudly on the first defect rather than tallying defects, so a failure is reported by `PREFLIGHT_FAILED`
(a corpus defect, nothing written) or by `APPLY_FAILED` naming `the corpus media pass` with these counts above
it. `APPLY_FAILED`'s own sentence was widened by one clause, because "every write is an upsert on
(slug, locale)" is an article's vocabulary and an attachment's key is the `media:` key.

### N3 — The first defect wiring it found: the pass reported `uploaded: 1` against zero attachment rows

> Five defects were found in the course of this delta, and they are numbered by where they are recorded rather
> than counted here: §N3 (an attachment never written), §N4 (that failure reported as success), §N10 (a false
> refusal from an unserved locale tree), §N11 (two decidable checks still in the write loop, and a fenced
> example of the grammar refusing the whole seed), §N12 (the report crashing on a sweep that died partway).
> §N5 is a sixth thing, a spec that passed for the wrong reason.


The first integration run was green on counts and **empty in the database**. Isolated with a throwaway probe
rather than reasoned about:

```
PROBE built_new=true target_size=1
PROBE portal_changed=false valid=false
PROBE save_result=false errors=["Articles is invalid"]
PROBE attach_returned_nil=true
PROBE row_exists=false
PROBE control_row_exists=true        # the same attach with portal.articles.reset
```

`plan_file` built its planned rows through `portal.articles.find_or_initialize_by`, which leaves an unsaved,
invalid `Article` in the portal's **association target**. `has_many` autosave then makes `portal.valid?` false
while `portal.changed?` — which is about attributes — stays false. `Attached::Many#attach` saves only
`if record.persisted? && !record.changed?` and abandons the attachment on `return if !record.save`
(`activestorage-7.2.3.2/lib/active_storage/attached/many.rb:51-57`). So the attachment stayed pending in memory
and was never written.

Fixed where it was created: `Article.find_or_initialize_by(portal: portal, …)`. Same query, same assignment, and
the **article** plan stops mutating the portal's in-memory graph — which it never should have, since a plan is an
inspection.

Two things the first draft of this paragraph got wrong, corrected rather than left standing. `media_seeder_spec`
never saw this defect because it **builds no Article at all** — the association target is never polluted, so
there is nothing for `attach` to trip over; its `portal.reload` is incidental and would clear the target if there
were one. And "a plan is an inspection" is true of the article plan only: `upsert_category` still builds through
`portal.categories.find_or_initialize_by` (`content_seeder.rb:450`), so the same unsaved-child shape exists on
the apply side. It is harmless for exactly one reason — `media_seeder.perform!` runs **first**, before any
category is built — which is §3.2's ordering doing a second job it was not chosen for, and is recorded here so
nobody reorders the two calls believing the order is only about failure atomicity.

### N4 — Defect 2: that abandonment was silent, which is the shape this program keeps refusing

`MediaUpload#upload` returned the blob whatever `attach` did, so an upload that attached nothing reported
success. The attach boundary now reads the attachment back **from the database** — `blob.attachments.exists?`
— and raises `Error` naming the portal and its validation errors. Not a speculative guard: the failure was
measured above, and the cop against "report success when it failed" is the same one P5c-1 was issued for.

### N5 — A third thing, found the way every other defect in this delta was: by attacking a claim

`content_seeder_spec.rb`'s *"accepts it once the file is there"* wrote the five bytes `'bytes'` to the media
path and asserted `created == 2`. That satisfied the preflight, which checks that a file **exists**. Nothing
read it, because nothing attached it — so a placeholder passed for as long as the defect existed. With the pass
wired in, the attach boundary identifies the content type from the bytes and refuses `application/octet-stream`.
It is a real 4x3 PNG now, and the example asserts the attachment, its key and its provenance rather than only
a row count. **The same class as §K1 and §M7: a spec that pinned the world as it was, so the gate stayed green
over a missing feature.** An earlier draft called this the seventh instance; the ordinal is dropped rather than
re-numbered, because §M7 four commits earlier had already claimed a seventh and the ledger is spread across
sections where a running count cannot be checked.

### N6 — Tests: the owner's A–I, at the integration level

The distinction that shaped every one of them: *"the service can do it"* was already proven by
`media_seeder_spec`, and is not what was broken. Each example below runs the real **`ContentSeeder`**.

| # | Requirement | Where | What makes it a proof rather than a count |
|---|---|---|---|
| A | first seed attaches a corpus image | `content_seeder_spec.rb` | the key, the owning portal, `content_source_path`, and the 4x3 dimensions |
| B | second identical seed performs no media write | same | the **blob id** is unchanged, which a re-upload-then-purge would also have counted as `unchanged` |
| C | changed bytes update the same logical key | same | same key, different blob id, new width, new bytes downloaded back |
| D | EN and AR resolve the same per-portal media | `corpus_media_end_to_end_spec.rb` | both pages render an `<img>`; one attachment; each locale's own alt |
| E | operator media survives a seed | `content_seeder_spec.rb` | the bytes are downloaded back, and `content_source_path` is absent |
| F | orphan cleanup cannot purge operator media | same | the corpus orphan **is** purged in the same run, so the sweep provably ran |
| G | cross-portal media cannot resolve | `corpus_media_end_to_end_spec.rb` | the changelog seed **refuses** the key rather than adopting it, then the renderer emits the inert comment and the route 404s, with a control proving the owning portal serves it |
| H | a validated reference renders after seed | same | `GET` the src each page minted returns the committed bytes |
| I | missing media fails in preflight | `content_seeder_spec.rb` | zero articles **and** zero attachments afterwards, plus one example per each of the four preflight-only defects |

Plus the failure model: an attach that fails on a later key raises `ApplyFailure` whose `where` is
`the corpus media pass`, whose `result.media.uploaded` is 1, with **no** article or category row written and the
completed attachment committed — so the re-run is an upsert, not a repair.

**PROVEN BOTH WAYS, and the split is recorded rather than rounded up.** With the two wiring lines removed and
nothing else changed, the two spec files are **`64 examples, 15 failures`**; with them, 64/0. The fifteen, each
one a real discriminator and each one a distinct example:

| # | Example |
|---|---|
| 1–4 | the four preflight-only defects — empty alt, a key in a link position, a destination CommonMark does not read as an image, a corpus file in the reserved namespace |
| 5 | A — attaches the corpus image under its stable key, marked corpus-owned |
| 6 | B — writes no media on a second identical seed |
| 7 | C — replaces the bytes of an existing key, keeping the key |
| 8 | E — leaves an operator upload attached, with its bytes, across a seed |
| 9 | F — purges the corpus orphan and never the operator upload, in one sweep |
| 10 | refuses bytes that are not a permitted raster type, before writing anything |
| 11 | refuses a file over the byte cap in the preflight too |
| 12 | reports the media work that completed when a later key fails at the attach boundary |
| 13 | reports the key that survived a failed run as `unchanged` on the next one |
| 14 | D and H — one image resolves on the English and the Arabic page, and the src each mints delivers the bytes |
| 15 | G — the other platform portal seeds its OWN blob for identical bytes and cannot resolve this one's key |

An earlier draft of this table said "twelve … A, B, C, D, E, F, G, H, the partial-failure example, and the four
preflight-only defects", which names thirteen things against a count of twelve: **D and H are one example**, and
two more examples have been added since. A reviewer caught the arithmetic; the list above is the re-measured one.

What passes either way is stated as what it is:

- **I** (`refuses a key with no file in the corpus, before writing a row or an attachment`) passes without the
  wiring, because `Corpus#media_problems` already refused a missing file before this delta (D9 item 8). It is a
  **regression pin** on the half that was already there, not a pin on the new behaviour; its two added
  assertions — zero articles and zero attachments afterwards — are what make it a preflight proof. The four
  preflight-only examples (1–4 above) are the media seeder's own guards.
- The `documentation_seed_report_spec.rb` examples build a `Result` by hand, so they pin the REPORT and not the
  wiring. Deliberate: §N2's four measured rake runs are what exercise the report from a live seed.


`purge_later` deletes the attachment row **synchronously** and only enqueues the blob's own purge
(`activestorage-7.2.3.2/app/models/active_storage/attachment.rb:60-66`), so attachment presence is assertable
under the `:test` queue adapter (`config/environments/test.rb:46`). Checked before relying on it.

### N7 — The shipped corpus and the changelog, run for real

Both rake tasks, against the real trees, then the test database reset:

```
articles: 138 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
  media: 0 attached, 0 replaced, 0 unchanged (0 without dimensions); sweep: 0 purged, 0 unreferenced in the repository
releases: 2 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
  media: 0 attached, 0 replaced, 0 unchanged (0 without dimensions); sweep: 0 purged, 0 unreferenced in the repository
```

and the second run: `138 unchanged` / `2 unchanged`, all media zeros. Two things proven that only a real run
proves. The shipped corpus still holds zero images, so the pass is a no-op on it today — the latency the owner
described, now closed rather than waiting. And **`documentation:changelog` is safe**: `custom/db/changelog` has
no `media/` directory at all, and the pass neither crashes nor purges, because `unreferenced_files` returns
`[]` for a missing directory and the sweep only ever considers attachments carrying a `content_source_path`.

### N8 — One deliberate four-line overrun, measured before it was accepted

`Metrics/ClassLength` on `ContentSeeder` reads 179 against a limit of 175. Measured rather than assumed before
disabling it: ten throwaway methods inside the nested `Corpus` left the count at **179**, and ten in the outer
class took it to **189** — so the cop excludes the nested class and the 179 is the seeder's own code. Nothing in
it is dead (every method and constant has a live caller, checked), so the only way under the limit is a second
object for the apply phase, which is the redesign the ruling forbids. Disabled inline with that reasoning rather
than added to `.rubocop.yml`'s `Exclude`, which would switch the cop off for the file permanently.

### N10 — Defect 3, found by attacking the one thing §N9 had waved through

§N9 first recorded the glob difference as "a bounded difference" — the kind of sentence this program treats as a
place to look rather than a conclusion. Attacked with a probe, it was real:

```
PROBE outcome=Documentation::ContentSeeder::PreflightError
      message=.../ar/getting-started/welcome.md:9: media:getting-started/inbox.png has no file at ...
PROBE articles=0 attachments=0
```

A portal whose `allowed_locales` is `['en']`, with an `ar` tree in the corpus referencing an image that is not
in the media tree: **the whole seed is refused** and no article is written, for an image no published article
needs. `Corpus` never reads that tree — `locales` is `LOCALES & portal.allowed_locale_codes` — but the media
walk read every one. And `Corpus#parity_problems` states the intent in terms: *"Scoped to the locales the portal
allows, so narrowing `allowed_locales` keeps working: the corpus legitimately carries a locale tree the portal
does not serve."*

Before this delta the difference was harmless, because the media seeder never ran. **The wiring is what made it
a defect**, so it is this delta's to close. `MediaSeeder#initialize` takes `locales:`, `nil` means every tree —
which is what a standalone run and every pre-wiring caller get, so no existing behaviour changes — and
`ContentSeeder` passes the locales it is actually seeding. Re-probed: `outcome=OK created=1 locales=["en"]`,
one article, zero attachments, no refusal. Pinned by an example that names the measurement.

### N11 — What a six-reader adversarial pass found, and what I took from it

Before offering the delta I ran six independent readers over the media subsystem — the frozen contract, an
adversarial audit of the owner's nine requirements, a test inventory, the report surface, a "what breaks when
this starts running" pass, and the fixture mechanics. Two of them independently found the same two defects I had
not. Everything below is a change in this delta; the two I declined are named with the reason.

**Taken — the content type and the byte cap were still inside the write loop.** My own `preflight!` comment said
"every corpus defect, with no write of any kind", and R2-MEDIA-INTERFACE.md §3.6 freezes BOTH of these as
seed-boundary checks — but they lived in `MediaUpload#attach!`, reached only from the apply. So the shape the
missing-file check was moved out of the write loop to fix was still there for two conditions that are equally
decidable from the file. The live consequence is likely rather than theoretical: **the cap is 2 MB and a
full-page screenshot is often larger**, so the first corpus image batch could attach image one and raise on
image two. `MediaUpload#validate_bytes!` is now public, `attach!` and the seed preflight both call it — one
implementation, so the preflight cannot drift from what the write accepts — and `attach!` no longer takes a
`content_type:` on trust, because a caller-supplied type is a claim and the bytes are the fact. The refusal
message now also names the corpus FILE and LINE, which is what an operator opens; it named only the image path
before.

**Taken — a fenced example of the grammar refused the whole seed.** `reject_spaced_reference` is a raw-line
regex, and it has to be: CommonMark builds no image node for a spaced destination, so no parse can see one.
But the corpus **documents this product**, and `![alt](media:step 2.png)` is exactly the example a
troubleshooting article shows as the thing not to write — `Corpus#media_problems` is parsed precisely so a key
in a fence is not a reference. The parse now tells the regex where the prose ends: lines inside a fenced or
indented code block are skipped. An example inside INLINE backticks still refuses, which is recorded in the
code rather than hidden. The same scan also reads the BODY now, not the raw file, so a `media:` image written
inside a front-matter value is no longer a reference to one scanner and invisible to the other — with the front
matter replaced by as many blank lines as it occupied, so error line numbers still point where an operator
looks. All three are pinned, and all three fail with the fix reverted: `19 examples, 3 failures`.

**Taken — `purged` and `unreferenced` printed as zeros for a sweep that never ran.** The orphan sweep is the
last thing the apply does, so on an earlier failure those two counters were not zero but unknown, and the report
said `0 purged (… 0 unreferenced)` as though the sweep had run and found nothing. They start `nil` and the
report prints `sweep: did not run`. §N2 carries the new output.

**Taken — three claims of mine were false.** `MediaSeeder`'s header said "ContentSeeder does not rescue it and
the rake task does not either, so rake prints the message and exits 1" — it does rescue it now, which is this
delta's own change, and the comment now describes both surfaces plus the fact that R2-MEDIA-INTERFACE.md §3.6
still documents the old path. `Result#media`'s comment said "assigned in `apply!`" when the assignment is in the
memo whose first caller is the preflight, so a media-preflight refusal carries a ZEROED struct, not nil.
`ATTACHMENT_NAME`'s justification said the association's name was not available: `ActiveStorage::Attached`
declares `attr_reader :name` (`activestorage-7.2.3.2/lib/active_storage/attached.rb:11`), so the constant is
gone and the query reads `portal.documentation_media.name`.

**Taken — `apply!` was public with no external caller.** I made both phases public when only the preflight
needed to be, and the comment described an integration that does not exist (`ContentSeeder` calls `preflight!`
and `perform!`, never `apply!`). A public `apply!` taking a caller-supplied reference hash would also reach the
attach boundary without `validate!`'s namespace guard, which is the only place the `uploads/` invariant is
enforced. Private again.

**Declined, with the reason — the storage-existence probe.** A reader proposed
`&& existing.blob.service.exist?(existing.blob.key)` in `seed`, because checksum identity proves what the
repository holds and not that the service still holds the object: after a database restore without its storage,
the seed reports `unchanged` forever and the page serves a broken image. The finding is correct. I did not take
it, because owner requirement 4 defines idempotency as "same key + same checksum => no write" with no further
condition, requirement 9's "safely rerunnable" is about recovering the run rather than repairing externally lost
storage, and the ruling says complete the existing design rather than extend it. **It is one condition in
`seed` if the owner wants it**, at the cost of one `File.exist?` per key per run on Disk or one HEAD on S3.

**Declined, with the reason — the `index_by` / `detect` disagreement.** `MediaUpload#attachment_for` takes the
FIRST attachment for a key and both indexes take the LAST, over an association with no `ORDER BY`. It matters
only if the transient two-attachments-one-key window `attach!` documents ever became permanent, which needs a
failure inside `purge_later`'s own transaction. Pre-existing, unchanged by this delta, and the reader rates it
low; recorded rather than fixed.

### N12 — The third review lens found a defect in §N11's own fix, and four more things

The failure-model lens returned `blocking_defect_found` with one **must**, and it was right: §N11's nil-sweep
change introduced a crash.

**MUST, closed.** `purged` is set to 0 just BEFORE the sweep (so the sweep has something to count into) and
`unreferenced` just AFTER it, while the report chose the sweep sentence from `purged`. So a sweep that died
partway — `purge_later` unable to reach the queue, `unreferenced_files` unable to read the tree — left `purged`
at 0 and `unreferenced` at nil, and `%<unreferenced>d` on nil **raises TypeError**: the report itself crashed
with a bare backtrace instead of printing `APPLY FAILED`. The sentence is now gated on `unreferenced`, the
counter written last and the real "the sweep completed" marker, and reads `sweep: did not complete`, which is
true of both "never started" and "died partway". **Measured both ways**: with the gate back on `purged` the new
example fails with `TypeError`; with it on `unreferenced`, 12/0.

**Requirement 8's SEED half had no discriminating coverage.** My cross-portal example asserted that the changelog
seed REFUSES the documentation portal's key — but its corpus had no media file at all, so the example would have
passed byte for byte even if `seed` resolved keys with the `ActiveStorage::Blob.find_by(checksum:)` global scan
that requirements 4 and 8 forbid outright. The changelog corpus now carries **its own copy of the same bytes**,
and the example asserts the changelog portal gets its own blob: same checksum, different `blob_id`. Only the
per-portal lookup can produce that, so the example now fails if the prohibition is broken.

**`PREFLIGHT_FAILED` promised more than the media half delivers.** Its heading is "Every file to fix:", which is
true of the collected corpus list and not of the media seeder, which raises on the first defect it sees. The
conversion now appends one line saying so, rather than leaving an operator to fix one file, re-run, and meet a
second under a heading that said otherwise.

**Two more stale citations**, both mine: a second `refuse_media!` in `media_seeder.rb`'s own header, and the
report spec's comment still calling the nil case a PreflightError.

**Recorded, not changed.** An operator-authored article may legally reference a CORPUS key — the key exists and
resolves, and `MediaUpload#replace!` only tells an operator the corpus owns those bytes, not that they may not
point at them. `purge_orphans` reads what the CORPUS references, never what an Article row references, so the
first seed after the corpus stops referencing that key purges it and the operator's article loses its image.
R2-MEDIA-INTERFACE.md §6.2 scopes this out by wording rather than by considering it. **A5'-O7**, below: either
widen `referenced_keys` to include this portal's article content, or say in §6.2 that such a key is unprotected.

### N13 — The owner's two confirmations, taken from a live run rather than from a test name

The ruling asks for confirmation that operator uploads survive a reseed and that a real fixture `media:`
reference resolves after seed. Both are pinned by examples (§N6 E, F, D, H), and both were also run live against
the test database — a temporary corpus, a real 4x3 PNG, an operator upload made through
`Documentation::MediaUpload`, two seeds, then the REAL renderer and the REAL per-portal resolver:

```
--- SEED 1 ---
articles: 2 created, 0 updated, 0 unchanged, 0 adopted, 0 untracked (en, ar)
  media: 1 attached, 0 replaced, 0 unchanged (0 without dimensions); sweep: 0 purged, 0 unreferenced ...
OPERATOR UPLOAD key=uploads/64365fb26ba8034f-operator-note.png
--- SEED 2 (re-seed, with the operator upload in place) ---
articles: 0 created, 0 updated, 2 unchanged, 0 adopted, 0 untracked (en, ar)
  media: 0 attached, 0 replaced, 1 unchanged (0 without dimensions); sweep: 0 purged, 0 unreferenced ...

CONFIRM operator_survives=true bytes_intact=true corpus_owned=false
CONFIRM corpus_attached=true corpus_owned=.../media/getting-started/inbox.png
CONFIRM render locale=en slug=welcome     src=/hc/lynomia-docs/articles/welcome/media/getting-started/inbox.png     alt=The inbox       dims=4x3
CONFIRM render locale=ar slug=welcome-ar  src=/hc/lynomia-docs/articles/welcome-ar/media/getting-started/inbox.png  alt=صندوق الوارد  dims=4x3
```

`bytes_intact=true` is the operator's own bytes downloaded back, not merely a row still present.
`corpus_owned=false` on the operator attachment and a path on the corpus one are the provenance the sweep reads.
The two `src` values are the article-scoped, application-owned addresses the renderer minted for ONE attachment
from two locales, with the dimensions the analyzer measured. Test database only, Disk storage under
`tmp/storage`, reset to zero rows afterwards; no production, no Meta, no real credentials.

### N9 — What this does NOT change, recorded so nobody re-derives it

- **`Corpus#media_problems` stays.** It collects every offending file where `MediaSeeder` raises on the first,
  and that collecting behaviour is the better report for the two checks they share. The frozen contract's
  deduplication (`MediaSeeder#problems`) remains open.
- **`MediaSeeder` still does its own walk** rather than being handed keys, because §3.3 justifies that and the
  cost is one extra read of the corpus. What it walks is no longer "every locale tree": see §N10, which is the
  defect this item originally recorded as merely bounded and then measured as real. A difference that remains:
  `Corpus` reads only what `manifest.yml` CLAIMS, while the media walk reads every section directory inside the
  locales being seeded. `parity_problems` already refuses an unclaimed section directory for a served locale, so
  the two sets cannot diverge without the run failing first.
- **No `documentation:media` rake task.** §3.3 permits one; nothing requires it. `documentation:content` is
  idempotent, so an operator who changed only an image re-runs that, and a second task would be a second
  entry point to the same pass.

### N14 — The fifth review lens read the record itself, and what it cost

The owner asked Agent 6 to review this delta. Five lenses ran: correctness, idempotency and provenance, the
tests, the operator's view, and one whose only job was to check every claim written above against the code. The
first four are recorded at §N11 and §N12. The fifth returned **no must-level finding** and twelve items, which
split in two.

**Six were already fixed by commits that landed while it ran**, which is the honest reading rather than a
coincidence worth hiding: the "nine of nine requirements" claim §N1 now corrects, §N11's "cannot see" wording
about the content-type and byte-cap checks, the missing note that requirement 8 has an example of its own, a
`Result` comment that had gone stale, a rake example that was subsumed by the exact-string one (now independent,
with pairwise-distinct counters), and a second stale `refuse_media!` citation.

**Six were record-only, and are applied here.** They change no code, and `docs/` is outside the gate's
changed-file selector, so they cannot move a gate result:

| # | What was wrong | Fix |
|---|---|---|
| R-2 | §L3.7, §M5 and the frozen contract still asserted that nothing calls the seeder and that A5'-O1 is an open owner decision | **SUPERSEDED/AMENDED** markers at all three, with the historical text left as written |
| R-3 | Three line citations had shifted under this delta | `content_seeder.rb:65`/`:86`/`:254` stated once at §L3.7 as current positions; §M5's `media_problems` citation updated to `:248` |
| R-4 | §N5's "seventh instance" double-counted — §M7, four commits earlier, had already claimed a seventh | the ordinal is dropped rather than re-numbered, and the class (§K1, §M7) named instead |
| R-8 | §N3 gave the wrong reason `media_seeder_spec` never saw defect 1 | it builds **no Article at all**, so the association target is never polluted; the `portal.reload` is incidental |
| R-9 | §N2 claimed the report line is worded "as §3.7 itself suggests" | two departures named: `uploaded` prints as `attached`, and `unreferenced` is qualified "in the repository" |
| R-12 | §N3's "a plan is an inspection" covers the **article** plan only | `upsert_category` still builds through `portal.categories`, and is safe solely because the media pass runs first — recorded so the ordering is not read as being about failure atomicity alone |

R-12 is the one with teeth: the ordering `R2-MEDIA-INTERFACE.md` §3.2 chose so that a media failure leaves the
corpus untouched is also what keeps the apply's own unsaved-category child out of `attach`'s way. Two reasons,
one line, and now both written down.
