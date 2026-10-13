# Report templates — Phase 1

Your brief names one template. Use its sections, in order, as `##` headings. Read
`docs/documentation-v2/00-program.md` §6 first: it is the contract, this file is only the shape.

Useful paths:
- Corpus: `custom/db/documentation/manifest.yml`, `custom/db/documentation/{en,ar}/<section>/*.md`
- Seeder / portal access: `custom/app/services/documentation/{content_seeder,library,portal_seeder}.rb`
- Tasks: `lib/tasks/documentation.rake`, `lib/tasks/documentation_seo_audit.rake`
- Public portal: `app/views/public/api/v1/portals/**/*+documentation.erb`, `app/controllers/public/api/v1/portals/`
- Authoring: `custom/app/controllers/super_admin/articles_controller.rb`, `custom/app/dashboards/*_dashboard.rb`,
  `custom/app/fields/`, `custom/app/views/fields/`
- Contextual help: `app/javascript/dashboard/helper/documentationLinks.js`
- Render: `lib/chatwoot_markdown_renderer.rb`, `lib/custom_markdown_renderer.rb`, `lib/base_markdown_renderer.rb`,
  `lib/markdown_renderer_url_sanitizer.rb`
- Lynomia overlay: `custom/app/**`, `custom/db/**`, `config/routes/*.rb`. There is no `enterprise/` tree.
- Prior design records: `docs/global-documentation/*.md`, `docs/product-refinement/03-documentation-seo.md`

---

## Template PRODUCT (agents 029–048)

1. **What the feature is** — in product terms, from the code, not from the docs.
2. **Surfaces and routes** — Vue route / component path, API endpoints, controller + action, `file:line` each.
3. **User-visible states** — every state a user can see (empty, loading, partial, degraded, blocked, error,
   success), and what produces it.
4. **Errors and validation messages** — the exact strings, with the i18n key and `file:line`. Include server
   validations, client validations and provider-relayed errors.
5. **Failure paths** — what can actually go wrong in production, how it surfaces, and whether the user can tell
   what to do next.
6. **Permissions** — which role, capability, plan entitlement or feature flag gates each surface, with
   `file:line`.
7. **Contextual-help opportunities** — a table: UI location (`file:line`) | the question a user has there |
   the registry key that should link there | whether a key already exists in `DOC_ARTICLES`.
8. **Current documentation coverage** — which existing corpus files cover this, and how well. Name the files.
9. **Missing or stale documentation** — what a stuck user cannot find, and what the docs say that is now wrong.
10. **Doc claims not proven by code** — anything an existing article asserts that you could not verify in the
    code. Cite both sides.

## Template CORPUS (agents 049–062)

1. **Inventory** — a table of every article in scope: key | EN file | AR file | title | position | EN words |
   AR words.
2. **Per-article verdict** — `KEEP | REWRITE | EXPAND | SPLIT | MERGE | RETIRE | RELOCATE`, with a one-sentence
   reason and the evidence. Nothing is deleted in Phase 1; you are classifying.
3. **Accuracy against the product** — claims you checked against code, with `file:line`. Mark each
   `confirmed | wrong | unverifiable`.
4. **Missing articles** — what this section must contain and does not, with the user question each answers.
5. **Quality** — structure, task-orientation, screenshots, length, front matter, SEO fields, tags.
6. **EN/AR parity** — mismatch in meaning, not just in presence.

## Template EDITOR (agents 063–072)

1. **What exists today** — with `file:line`.
2. **Constraints the existing system imposes** — what an editor upgrade must not break.
3. **Findings** — specific, cited.
4. **Options** — where a decision is needed, the real options with trade-offs, and your recommendation with the
   reason. For technology choices: evaluate against this product's needs (CommonMark round-trip, RTL, ActiveStorage,
   sanitization, Administrate/Rails asset pipeline, bundle size, licence, maintenance), not against popularity.
5. **Risks**.

## Template SEO (agents 073–080)

1. **What exists today** — with `file:line`.
2. **Measured behaviour** — what the code actually emits, quoting the template or helper.
3. **Defects** — each with severity (`blocker | major | minor`) and the user or crawler impact.
4. **What a larger corpus breaks** — the corpus is about to grow several times over; say what fails at that size.
5. **Recommendations**, each tied to an existing system to extend.

## Template SECURITY (agents 081–087)

1. **Attack surface** — with `file:line`.
2. **What the existing defence actually does** — quote it; do not assume a sanitizer sanitizes.
3. **Findings** — each as: claim, evidence (`file:line` or a concrete payload), impact, severity
   (`blocker | major | minor`), and whether it is reachable today or only after the editor upgrade.
4. **What the editor upgrade would newly expose** — rich content, uploads, embeds, SVG, pasted HTML.
5. **Required controls** — minimum set, each mapped to an existing mechanism.

## Template META (agents 001–028)

1. **Source register** — a table: source URL | page title | product | API/version context | date checked |
   normative or observational. Every later claim references a row here.
2. **The rules** — what Meta actually states, paraphrased. **Do not copy large sections of Meta documentation.**
3. **Error codes and failures** — a table: code | subcode | title as Meta words it | what it means | what the
   business can do | what the end user sees | source row. **Never invent a code.** Leave a cell `not stated`
   rather than guessing.
4. **Limits and numbers** — only numbers a source states, each with its source row.
5. **Version and deprecation notes** — anything version-dependent, with the version.
6. **Ambiguities and gaps** — where Meta's documentation does not answer the question. Say so plainly.
7. **What Lynomia users would ask** — the questions this area produces for a support desk.

## Template REFUTE (agents 088–099)

You are a skeptic. Your job is to find what is wrong, not to confirm what is right.

1. **What you attacked** — the specific claims, files or designs, named.
2. **Refutations** — each as: the claim, who made it (agent/report/file), why it is wrong, the evidence, and the
   severity (`blocker | major | minor`).
3. **Survived** — claims you tried to break and could not, with what you tried. This matters as much as the
   refutations.
4. **Not checkable** — what you could not test, and what would be needed.

Do not propose implementations. Do not soften a finding to be agreeable. An "accepted risk" is not yours to
grant.
