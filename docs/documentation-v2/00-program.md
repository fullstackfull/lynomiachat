# Lynomia Documentation Intelligence — Program Charter

**Program**: Documentation Intelligence + Meta Knowledge + Professional Editor
**Orchestrator**: Agent 000
**Baseline branch**: `lynomia-custom`
**Baseline HEAD**: `021ea6e39f0d73689638d68673f84bd567cdb160` (contains the merged Platform Support Desk)
**Working branch**: `claude/documentation-v2`
**Repository**: `fullstackfull/lynomiachat`
**Started**: 2026-10-13

---

## 1. Why this program exists

Lynomia ships a global documentation system today: a Markdown corpus in source control, seeded into the Help
Center's own `Portal`/`Category`/`Article` models, rendered by the Help Center's public portal, linked from the
product through a contextual-help registry, and authored in Super Admin through Administrate. It works, and it
is the thing to extend.

Four things are missing.

1. **The documentation does not know what the product does.** Nobody has walked the whole product and asked,
   feature by feature, "is there an article a stuck user would find?" The corpus was written from a capability
   map, not from the code.
2. **The product fails against Meta's APIs and the documentation cannot explain it.** Fourteen WhatsApp error
   articles exist. Meta's error surface across WhatsApp Cloud API, Graph API, Messenger and Instagram Messaging
   is far larger, and the five codes this installation classifies are the five somebody already hit in
   production — not the five that matter most.
3. **The corpus is small.** 126 Markdown files, 63 EN + 63 AR, 124 published articles. For a product with
   WhatsApp, Facebook, Instagram, four commerce providers, campaigns, automation, flows, a platform support
   desk and a super-admin operations centre, that is a skeleton.
4. **The authoring surface is a textarea.** Super Admin authors CommonMark in `Field::Text.with_options(rows: 28)`.
   There is no media insertion, no preview beside the text, no structured components, no required alt text, no
   SEO field validation, no RTL preview.

And one production fact has to be solved rather than patched: after the last deploy the Markdown shipped but no
article changed, because `rails documentation:content` is an operator-run task that nothing in the deploy calls.
An operator ran it by hand and got `38 created / 19 updated / 67 unchanged / 124 published / 0 SEO errors`.

## 2. The governing product rule

> **DO NOT create a parallel CMS, help center, documentation engine, SEO engine, media system or search engine
> if the existing Lynomia system can be extended.**

Everything below is an extension of something that already exists:

| Need | Existing system to extend | Not this |
|---|---|---|
| Content model | `Article`, `Category`, `Portal` (+ `meta` jsonb) | a new `documents` table |
| Corpus | `custom/db/documentation/<locale>/<section>/*.md` + `manifest.yml` | a new content directory |
| Seeding | `Documentation::ContentSeeder` | a new importer |
| Portal access | `Documentation::Library` | new finders |
| Public rendering | `app/views/public/api/v1/portals/**/*+documentation.erb` | a new public app |
| Authoring | `SuperAdmin::ArticlesController` + `ArticleDashboard` | a standalone CMS |
| Contextual help | `DOC_ARTICLES` in `documentationLinks.js` | hard-coded URLs in Vue |
| SEO | `DocumentationHelper`, `PortalHelper`, `lynomia:docs:seo_audit` | a new SEO engine |
| Search | the portal's existing search | a new index |
| Media | ActiveStorage as the *storage mechanism* — **see Ruling R2; this does not mean blob URLs in Markdown** | a DAM |
| Authorization | Devise `:super_admin` scope + existing policies | new auth |
| Sanitization | the existing article render path — **see Ruling R1, this row was wrong** | a second sanitizer |
| Deployment | the existing deploy system | a parallel pipeline |

**EXTEND, DO NOT DUPLICATE.**

## 3. Production rules — absolute, for every agent

- **DO NOT deploy.**
- **DO NOT touch production data.**
- **DO NOT modify real Platform Support agents or SLA settings.**
- **DO NOT use Account 21.**
- **DO NOT alter real Meta credentials.**
- **DO NOT call or send messages through real production providers.**
- **No real WhatsApp / Facebook / Instagram mutation during this program.**
- **External Meta research is read-only** — fetch and read documentation pages; never authenticate, never call a
  Graph endpoint, never submit a form.
- **No agent merges anything.** Only Agent 000 integrates, and the final merge into `lynomia-custom` waits for
  owner approval.

## 4. Phases

| Phase | What | Writers |
|---|---|---|
| 1 | Read-only discovery: product, Meta, corpus, editor, SEO, security | 0 (reports only) |
| 2 | Coverage matrix: feature → help, machine- and human-readable | Agent 000 |
| 3 | Information architecture reassessment; article taxonomy | Agent 000 |
| 4 | Contract freeze: source of truth, media, content model, Meta error taxonomy, deployment sync, ownership map | Agent 000 |
| 5 | Implementation, ≤20 simultaneous writers in isolated worktrees, streams A–J | ≤20 |
| 6 | Integration, combined gate, adversarial rerun by 088–099 | Agent 000 |
| 7 | Final report, push, STOP for owner approval | Agent 000 |

Checkpoint 1 closes Phase 1. Checkpoint 2 closes Phase 4. Checkpoint 3 closes Phase 5.

## 5. The 100 agents

Agent 000 is the Orchestrator. It owns contracts, deduplication, arbitration, worktree ownership, integration,
final verification and the merge decision. The other 99 are specialists.

### 001–028 — Meta official knowledge (read-only external research)

| # | Scope |
|---|---|
| 001 | WhatsApp Cloud API authentication model: access tokens, token types, lifetimes |
| 002 | System users, permanent tokens, token generation and rotation |
| 003 | Permissions and scopes: `whatsapp_business_messaging`, `whatsapp_business_management`, and the rest |
| 004 | App roles, asset ownership, business portfolio access, and what revocation breaks |
| 005 | Message send failures: request-time error families and their meaning |
| 006 | Message status lifecycle: sent, delivered, read, failed — and what each omits |
| 007 | Webhook payload shapes for messages and statuses, including `errors[]` |
| 008 | Pricing/conversation categories as they appear in payloads and failures |
| 009 | Template creation, categories, components, variables, limits |
| 010 | Template approval, rejection reasons, quality rating, pausing and disabling |
| 011 | Template sending: parameter mismatch failures, language resolution, named vs positional |
| 012 | Template media headers, documents, buttons, flows and their send-time constraints |
| 013 | Onboarding: Embedded Signup, the signup flow, what the business must already have |
| 014 | WABA structure, phone number registration, display name review, two-step PIN |
| 015 | Coexistence / migration between App and Cloud API; number porting and reconnection |
| 016 | The 24-hour customer service window and what may be sent inside and outside it |
| 017 | Marketing message limits, per-user caps, opt-in rules, quality-based throttling |
| 018 | Messaging limits and tiers; what raises and lowers them |
| 019 | Media upload, media IDs, supported types and size limits |
| 020 | Media download, URL expiry, and the failures a retrieval produces |
| 021 | Facebook Pages: page access tokens, page roles, subscribed apps, page-level failures |
| 022 | Messenger Platform: send API, messaging types, tags, the Messenger window, handover |
| 023 | Instagram Messaging: account requirements, linking, permissions |
| 024 | Instagram Messaging runtime: send failures, restrictions, story/mention semantics |
| 025 | Graph API `OAuthException` families, error subcodes, versioning and deprecation, rate-limit envelopes |
| 026 | Webhooks: verification handshake, `X-Hub-Signature-256`, retries, ordering, deduplication |
| 027 | Business verification, app review, advanced access, Tech Provider / Solution Partner requirements |
| 028 | **Cross-Meta error-code master auditor** — challenges 001–027; every code must be traceable to an official page |

### 029–048 — Lynomia product and code discovery (read-only, repository)

| # | Scope |
|---|---|
| 029 | Conversation and inbox lifecycle |
| 030 | Message composer, replies, attachments, signatures |
| 031 | Contacts, identity, merge, custom attributes, import |
| 032 | Teams, agents, assignment, availability |
| 033 | Custom roles and permissions |
| 034 | Notifications: in-app, email, push |
| 035 | Canned responses and macros |
| 036 | Automation rules |
| 037 | Flow builder / bots |
| 038 | Campaigns and audiences |
| 039 | WhatsApp setup and connection |
| 040 | WhatsApp runtime: send, receive, templates, failures |
| 041 | Facebook / Messenger integration |
| 042 | Instagram integration |
| 043 | Commerce core |
| 044 | Shopify integration (including its retired state) |
| 045 | WooCommerce integration |
| 046 | Salla integration |
| 047 | Zid integration |
| 048 | Platform Support Desk + Super Admin / Operations / billing |

### 049–062 — Corpus and gap analysis (read-only, repository)

| # | Scope |
|---|---|
| 049 | `getting-started` section |
| 050 | `conversations` section |
| 051 | `contacts` section |
| 052 | `audiences-and-campaigns` section |
| 053 | `whatsapp` section |
| 054 | `whatsapp-errors` section |
| 055 | `automation` section |
| 056 | `commerce` section |
| 057 | `workspace` section |
| 058 | `integrations` section |
| 059 | `administration` section |
| 060 | `troubleshooting` section |
| 061 | Arabic corpus quality, terminology consistency, RTL hazards |
| 062 | English corpus quality + cross-corpus information architecture |

### 063–072 — Editor and authoring experience (read-only, repository)

| # | Scope |
|---|---|
| 063 | Current Super Admin authoring UI architecture (Administrate, fields, views, assets) |
| 064 | Backend content model and APIs available to an editor |
| 065 | Markdown rendering and sanitization path, end to end |
| 066 | ActiveStorage configuration, services, variants, URL generation |
| 067 | Editor technology evaluation — on evidence, not popularity |
| 068 | Image and media authoring UX |
| 069 | Authoring workflow: draft, publish, preview, validation, dirty state |
| 070 | SEO authoring fields and their validation |
| 071 | Structured rich content components for documentation |
| 072 | Arabic / RTL authoring and accessibility |

### 073–080 — SEO, search and discovery (read-only, repository)

| # | Scope |
|---|---|
| 073 | Canonical URLs and hreflang |
| 074 | Sitemap and robots |
| 075 | JSON-LD / structured data |
| 076 | Internal linking and related articles |
| 077 | Search relevance in the existing portal search |
| 078 | Synonyms, including Arabic and transliteration |
| 079 | 404s, redirects, article retirement |
| 080 | Core Web Vitals and image SEO on the public portal |

### 081–087 — Security, media and authoring safety (read-only, repository)

| # | Scope |
|---|---|
| 081 | XSS and the article sanitizer |
| 082 | Editor attack surface |
| 083 | ActiveStorage authorization and blob exposure |
| 084 | SVG and dangerous media types |
| 085 | External links, iframes, embeds |
| 086 | Super Admin authorization, CSRF, mass assignment |
| 087 | Content provenance and secret leakage, including screenshots containing credentials |

### 088–099 — QA and adversarial refuters (skeptics, never implementers)

| # | Scope |
|---|---|
| 088 | Refute Meta error-code claims |
| 089 | Refute WhatsApp documentation claims |
| 090 | Refute Facebook / Messenger / Instagram claims |
| 091 | Hunt stale API guidance (deprecated versions, retired endpoints) |
| 092 | Hunt documentation claims unsupported by code |
| 093 | Hunt undocumented functionality |
| 094 | Hunt EN/AR semantic mismatch |
| 095 | Attack the editor: XSS and media |
| 096 | Attack permissions and authorization |
| 097 | Attack the deployment and content-sync design |
| 098 | Attack SEO and indexability |
| 099 | Attack usability, accessibility and navigation |

---

## 6. AGENT CONTRACT — every agent reads this section

### 6.1 You are read-only with respect to the product

You may **read** anything in the repository. You may **run read-only shell commands** (`cat`, `sed -n`, `rg`,
`grep`, `find`, `git log`, `git show`, `ls`). You may read external documentation over the network if your brief
says so.

You may **write exactly one file**: your own report, at the path your brief gives you, under
`docs/documentation-v2/discovery/`. Nothing else. No product code, no Markdown corpus file, no migration, no
config, no other agent's report. Do not `git add`, `git commit`, `git checkout`, `git merge`, `git stash` or
`git push`. Do not create branches or worktrees. Do not run `rails`, `rake`, `rspec`, `pnpm`, `bundle install`,
or anything that touches a database.

This is how 99 agents work at once without colliding: one agent, one file, no shared paths.

### 6.2 Evidence rules

**For repository findings**: cite `path/to/file.rb:LINE`. A claim with no citation is not a finding. If you
could not verify something, say "unverified" and say what you would need.

**For Meta findings**: every fact carries
- the **source URL**,
- the **page title**,
- the **product** (WhatsApp Cloud API / Graph API / Messenger Platform / Instagram Messaging / Business Help),
- the **API or version context** where the page states one,
- the **date checked**,
- whether it is **normative** (the documentation states the rule) or **observational** (a changelog, a community
  note, an inference).

**Never invent an error code.** **Never invent a numeric limit.** **Never treat a blog post, Stack Overflow
answer or Reddit thread as authoritative** — if the only source is one of those, record the claim as
*observational, unconfirmed* and say so. Only `developers.facebook.com`, `developers.facebook.com/docs/graph-api/changelog`,
`business.facebook.com` help content, `www.facebook.com/business/help` and Meta's own status/changelog pages are
normative.

If Meta's documentation is ambiguous, record the ambiguity rather than resolving it by guessing.

### 6.3 Your report

Write it at the exact path in your brief. Start with this front matter:

```
---
agent: NNN
scope: <one line>
confidence: high | medium | low
sources_normative: <count>      # Meta agents only
sources_observational: <count>  # Meta agents only
---
```

Then the sections your brief names. Write prose and tables, not bullet soup. Length follows evidence: a thin
area gets a short report, a rich one gets a long report. Do not pad.

### 6.4 What you return to the orchestrator

Return **only** a digest, at most 25 lines:

```
AGENT NNN — <scope>
REPORT: docs/documentation-v2/discovery/NNN-<slug>.md (<n> lines)
CONFIDENCE: high|medium|low
TOP FINDINGS (max 8, most important first, one line each, each with a citation or URL)
DOC GAPS (max 6, one line each)
BLOCKERS/CONTRADICTIONS (anything another agent or the orchestrator must arbitrate)
```

The digest is for routing. The report is the deliverable. Do not paste your report into the digest.

### 6.5 Forbidden

- Deploying, or suggesting a command that deploys.
- Touching production, production data, Account 21, real Platform Support agents or SLA rows, or real Meta
  credentials.
- Calling a Meta API, authenticating to Meta, or sending any message through any provider.
- Writing product code or corpus content in Phase 1.
- Merging, committing, pushing, or rebasing anything.
- Marking something "fine" because you did not check it. Say "not checked".

---

## 7. Phase 1 deliverables (Agent 000)

| File | Content |
|---|---|
| `00-program.md` | this charter |
| `01-current-system.md` | the documentation system as it actually is, with citations |
| `02-product-coverage-map.md` | every feature vs. the help that exists |
| `03-meta-source-register.md` | the Meta source register with provenance |
| `04-gap-register.md` | every gap, classified and owned |
| `05-editor-discovery.md` | the authoring surface and the editor decision inputs |
| `06-security-review.md` | sanitization, media, authorization, provenance |
| `07-seo-search-review.md` | canonical, hreflang, sitemap, structured data, search |

## 8. The decisions Agent 000 must freeze before any implementation

1. **Source of truth** — repository Markdown canonical, database canonical, or a controlled hybrid with explicit
   ownership, version and provenance. Two writers that overwrite each other are forbidden.
2. **Deployment content lifecycle** — what runs, when, gated how, with what failure semantics, transaction
   behaviour, rollback story, and whether SEO validation belongs in deploy or CI.
3. **Media ownership model** — what an article's image is attached to, who may read it, how it is named and
   validated.
4. **Meta error knowledge model** — articles plus metadata, or structured metadata on the existing model. Not a
   new application and not a new table merely because there are many codes.
5. **Article taxonomy and IA** — the 12 sections are preserved; additions and splits need evidence.
6. **Writer ownership map** — one owner per file or directory, frozen for Phase 5.

## 9. Content ambition

No arbitrary article target. The corpus must become substantially broader than the current 124 published
articles, and every important user flow must have help. A title is not coverage: an article that does not answer
the question it names is a gap, not a deliverable. **NO FAKE COMPLETENESS.**
