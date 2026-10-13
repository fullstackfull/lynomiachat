# Checkpoint 1 — Phase 1 discovery

Agent 000, 2026-10-13. Branch `claude/documentation-v2`, baseline `lynomia-custom` @ `021ea6e3`.
Every claim below traces to a cited report in `docs/documentation-v2/discovery/`.

---

## A. Branch and baseline

Working branch **`claude/documentation-v2`**, cut from `lynomia-custom` at
`021ea6e39f0d73689638d68673f84bd567cdb160` — the HEAD that carries the merged Platform Support Desk. Tree clean,
nothing merged, nothing deployed. I chose the descriptive per-program branch name this repository has used for
every prior programme; say the word if you want the generic task branch instead.

## B. Baseline measurements, first-hand

126 Markdown files: **63 EN + 63 AR**, exact per-section parity, 12 sections. 124 published articles in
production. 53,975 EN words. **988 internal links, 0 broken.** 62 `DOC_ARTICLES` contextual-help keys (I first
wrote 87; agent 076 challenged it, and 076 was right — corrected). **Zero images and zero embeds** in the whole
corpus. 31 `Commerce::Error` codes, 19 mapped to 5 articles. ~100 published WhatsApp error codes, 4 with
articles.

## C. The 100-agent allocation

As specified in `00-program.md` §5, unchanged: Agent 000 orchestrating; 001–028 Meta official knowledge;
029–048 Lynomia product and code; 049–062 corpus and gap analysis; 063–072 editor; 073–080 SEO and search;
081–087 security; 088–099 adversarial refuters.

## D. Status

**All 99 launched. 81 complete**, producing 34,423 lines of cited reports. **18 still running**: 028 (the
cross-Meta error master auditor), 049, 050, 078, 080, 083, and all twelve refuters 088–099. That is the correct
remainder — the completeness backstop and the skeptics should be last, because they audit the others.

## E. Current architecture

One content model, no second CMS. The corpus is Markdown with YAML front matter in source control, seeded by
`Documentation::ContentSeeder` into the Help Center's own `Portal`/`Category`/`Article`, where two portals are
platform-owned with `account_id = NULL`. `Documentation::Library` is the single door. Public access is thin
redirects (`/docs`, `/docs/:slug`, `/changelog`) onto the Help Center's own renderer through `+documentation`
view variants. Authoring is Administrate. Contextual help is one registry. SEO is a read-only rake audit.
Full detail with citations: `01-current-system.md`.

**Three things I asserted there were wrong, and three agents proved it.** Raw HTML is *deleted*, not escaped.
Several SEO audit checks *cannot fail*. `DOC_ARTICLES` has 62 keys, not 87. All three are corrected in place
with the evidence, not quietly overwritten.

## F. Product coverage

Measured, not estimated. **WhatsApp holds 20 of 63 articles. Facebook/Messenger has zero. Instagram has zero.
Notifications has zero. Billing, plans and usage limits have zero.** Of 32 core integration targets, 7 have a
dedicated article, 17 are one table row, 5 are unmentioned. `administration` is one article against an 18-area
surface — 61% of it has no coverage at all. Abandoned carts are fully built and completely undocumented. The
Platform Support Desk, just shipped, has one article.

## G. Meta findings

27 facts the corpus currently gets wrong or omits are tabulated in the ledger. The highest-value ones: **a voice
call now opens the 24-hour window**; **code 470 does not exist** (it was On-Premises, sunset 2025-10-23) — the
real code is 131047; **free entry points are a separate 72-hour window** and the only documented way to send
non-template outside the service window; **inbound media expires in 7 days, not 30** (cut 2025-10-09), and a
retrieved URL lives 5 minutes; **template pauses are 3h/6h/disabled**, not the widely-repeated 3h/6h/24h;
**Meta re-categorises approved templates**, and marketing→authentication sets them REJECTED on the 1st of the
month; **image media is 5 MB**, not 100; and **messaging limits, quality rating and throughput are three
different things** that the existing article conflates into two.

## H. Source register

~190 normative Meta pages read across 19 completed Meta agents, with URL, page title, product, version context
and date checked per claim. Notably, **no agent invented a code or a limit** — the recurring entry is "not
stated". Meta publishes no phone-number `status` enum, no `quality_rating` definition, no verification timeline,
no rejection taxonomy, no media-link HTTPS rule, no per-user marketing cap number, and no retry count for
webhooks. Those are now documented as unknowable rather than guessed.

**Meta's documentation tree has moved** (`/docs/whatsapp/**` → `/documentation/business-messaging/whatsapp/**`),
with pages split across both, several 404s and several JS-only shells. Agent 010 found the technique that works:
append `.md` to any path in that tree's `llms.txt`.

## I. Corpus quality

Better than I expected in craft, worse in currency. **Duplication is genuinely low** — max 6-gram containment
0.169 across 1,953 pairs, so no MERGE is warranted anywhere. A 7-slot house template is already observable.
988 internal links with zero broken ones, enforced by an existing spec.

But **~45 specific corpus claims are now contradicted by code**, and the corpus's *most-linked* article
(in-degree 24) is factually wrong about the permission list. Several are negative absolutes — "there is no X",
"only administrators can Y" — which is exactly where a corpus goes stale as the product gains capability.

And one correction to my own earlier record: three agents found that **POSIX `wc -w` undercounts Arabic by 3–5×**
in this shell. Measured properly the AR/EN ratio is ~0.84. **The Arabic corpus is not truncated**; earlier
alarming ratios were a measurement artefact. Agent 094 is confirming per-pair.

## J. Editor findings

The decisive one: **a full CommonMark article editor already ships in this repository**
(`@chatwoot/prosemirror-schema`, MIT, exact pin), and the Ruby renderer already implements five features whose
only producer is that editor's serializer. The render path and the editor are already a matched pair, so no new
editor dependency is justified. Super Admin can already mount Vue through a harness that is loaded on every page
with zero mount points.

**But it does not round-trip this corpus**: 126 of 126 files change on a no-edit parse-and-serialize, adding
2,315 spurious `<br>`. Adoption is therefore gated on a round-trip test. Two of the three fixes live upstream.

`rows: 28` is inert — the Administrate partial passes no options. Sprockets is dead in production, so the editor
can only ship through Vite.

## K. The source-of-truth problem, and my proposed resolution

Six independent agents converged on the same five defects. The seeder forces `status: :published` and overwrites
every file-backed field on every run, `Article` is **not audited**, so an operator's edit is reverted silently
and unrecoverably; **editing `slug` creates a duplicate rather than a rename**, which the SEO audit cannot see
and nothing ever deletes; **every Super Admin save destroys `meta['doc_key']`**, so Arabic contextual help
silently serves English; there is **no working retirement path**; and the seeder is **not single-run
convergent** — a file moved between sections heals only on a second run.

**Proposed resolution: Option C, controlled hybrid, files canonical by default.** The detachment marker must be
a **column** (`doc_source`, `doc_detached_at`), not a `meta` key, because both writers replace `meta` wholesale —
and this repository already has the precedent migration. The seeder skips and *reports* detached rows with a
non-zero exit. Retirement becomes front-matter `retired: true` → `archived`, file stays. Three prerequisites are
near-one-liners: merge `meta` instead of replacing, drop `slug`/`locale` from the form, stop forcing `status`.
`doc_key` gets promoted to an indexed column with a uniqueness constraint, which fixes the destruction
*structurally* rather than by remembering to merge.

**This cannot be frozen until convergence is settled** — under a files-canonical model with a non-syncing
deploy, the corpus cannot be corrected at all, including taking down something wrong. Agent 097 is on it.

## L. Deployment sync finding

Confirmed first-hand: `documentation:content` appears **nowhere** in `deployment/deploy.sh`, and neither does
`documentation:setup`. The nine deploy stages are mapped in `01-current-system.md` §4. The six open questions —
placement relative to migrate and restart, partial-run semantics with no wrapping transaction, rollback when the
only backup predates the sync, whether the SEO audit belongs in deploy or CI, whether `status` should be
force-written at all, and whether sync should be automatic — are posed there and are agent 097's target. **I have
not added a rake call to the deploy script, and will not until convergence is proven.**

## M. Security findings

One blocker, several majors, and — worth saying — a number of defences that held under attack.

**Blocker: a tenant account administrator can publish their own article into Lynomia's public `/docs` portal.**
The tenant API permits `category_id` unchecked, no validation ties category to portal, and the public category
page lists articles unscoped by portal. It renders on the vendor's own documentation domain, with the tenant's
agent names and avatars, unaudited. **Pre-existing, live, and not created by anything this program proposes.**

Majors: `portal_id` is mass-assignable in Super Admin and transfers the article to a tenant's account, after
which the content sync dies permanently on a slug collision; `create` never consults the platform scope at all;
one `archived` checkbox removes the entire documentation surface with no UI path back; an author can publish
third-party `<script>` with one Markdown link via two embed providers, with a CSP that constrains nothing;
`?show_plain_layout=true` — the preview URL — deletes `X-Frame-Options`; `![](data:image/…)` publishes a live
inline image that bypasses every media control; `/docs` publishes a named staff byline and avatar in
contradiction of the product's own written policy; and documentation authoring is entirely unaudited, with the
usual `audited` macro unable to fix it because there is no `current_user` in a Super Admin session.

Held under attack: CSRF, JSON-LD `</script>` injection, Administrate's escaping, the `meta` allowlist, the
`preview` redirect, and the URL scheme denylist. **The corpus itself is clean** — agent 087 swept all 128 files
for tokens, keys, real customer data, internal hosts and admin paths and found zero.

## N. Proposed implementation architecture

Nine orchestrator rulings are written up in `08-orchestrator-rulings.md`, each forced by named agents: one
sanitizer pass at the single existing choke point (and remove the two script-emitting embed providers);
ActiveStorage as the storage mechanism with a `media:` key in the corpus and **never** a blob URL; reuse the
installed editor gated on a round-trip test, with the textarea upgrade as increment one; a changelog is normative
for the fact and date of a change only; the error taxonomy keys on `(product, code)` and never on subcode; one
Meta URL convention with per-claim date and version; the corpus documents what the **server** enforces, not what
the UI offers; Arabic link, route and `dir` resolution is **one** decision, not three; and file-level integrity
checks belong in CI, data-level checks in the audit.

## O. Proposed writer ownership map

Deferred to Checkpoint 2, deliberately. Three contended files have surfaced — `content_seeder.rb` (four agents
have recommendations on it), `config/markdown_embeds.yml` (imported by both trees), and
`roles-and-permissions.md` (three agents) — and I will not freeze ownership until the refuters have attacked the
proposals that would touch them.

---

## Decisions I need from you

Everything above I am proceeding on. These five I am not, because they are live production risks or product
decisions, not documentation ones.

1. **Embedded Signup v2 is deprecated on 2026-10-15 — in two days.** Meta carries this on five pages, and v4
   changes the post-flow contract materially. I could not determine the version from the repository: there is no
   version or `config_id` literal in the code, it is supplied at runtime, and this installation sends
   `sessionInfoVersion '3'`, for which Meta gives no sunset date. **Someone needs to check the Meta app's
   Embedded Signup configuration.** If it is v2, new-customer WhatsApp onboarding stops working on Thursday.
2. **Expired Graph API pins.** `FACEBOOK_API_VERSION` defaults to **v18.0** (availability ended 2026-01-26);
   Messenger send and page subscribe are pinned at **v3.2** inside a vendored gem; a legacy Instagram send path
   is on **v11.0**. Current is v26.0; the oldest in window is v21.0. Meta retires versions **silently** — a call
   to a retired version is served by the next oldest, so there is no error to detect.
3. **The cross-tenant publication blocker** (section M). Live, pre-existing, unaudited.
4. **Is a service reply billable from 2026-10-01?** Two Meta pages disagree and the date has passed. Blocks any
   cost article, and may affect invoices.
5. **Two product defects that block honest documentation**: a blocked campaign has no resume path reachable from
   the product (`unblock!` has no caller), and no way exists to create an SLA policy row for the Platform
   Support Desk, so the SLA engine cannot be activated as shipped. Documentation cannot describe either without
   documenting a defect.

Unless you redirect me, I continue automatically: finish the remaining 18 agents, write deliverables 02–07,
build the Phase-2 coverage matrix, and bring you Checkpoint 2 with the frozen contracts.
