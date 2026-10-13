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
