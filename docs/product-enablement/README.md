# Product Enablement & Self-Service Expansion — Discovery

**Branch** `claude/practical-thompson-9xfqed`

| | |
|---|---|
| Discovery (`00`–`12`) | complete at HEAD `6c381e96`; no product code was changed by it |
| P0 defects, P1 branding | implemented |
| P2 audience UX + starter library (`13`–`20`) | implemented, zero migrations |

> The program brief cites `95d9994e` as the last known HEAD. That is stale: Contacts phases D and E landed
> after it. Two consequences matter here — Part 5.6 ("all filtered results" bulk actions) is **already shipped**
> via `Contacts::ViewScope`, and the prior doc the brief quotes as saying otherwise is the one that had to be
> corrected. See `06` §7.

## Read in this order

| | |
|---|---|
| [`12-proposed-phases.md`](12-proposed-phases.md) | **start here** — the P0 defect list, the phases, the summary tables, and the recommended first phase |
| [`00-platform-capability-map.md`](00-platform-capability-map.md) | what Lynomia is today: 17 subsystems, the counted inventory, the defined-but-unused register, the live defects |
| [`01-starter-library-opportunity-study.md`](01-starter-library-opportunity-study.md) | 22 starter candidates with all 13 brief fields, graded HIGH/MEDIUM/LOW, plus 23 rejections each with its blocking fact |
| [`02-flow-automation-bots-macros-reuse-map.md`](02-flow-automation-bots-macros-reuse-map.md) | the Part 19 reuse matrix, every orchestration primitive enumerated, and the Part 20 starter study |
| [`03-commerce-recipe-capability-matrix.md`](03-commerce-recipe-capability-matrix.md) | the 14×4 provider matrix, all 56 cells classified, and the abandoned-cart verdict |
| [`04-whatsapp-template-current-state.md`](04-whatsapp-template-current-state.md) | the repo's template surface, and the Part 21 META-vs-REPO proof table |
| [`05-whatsapp-template-target-architecture.md`](05-whatsapp-template-target-architecture.md) | the Template Manager design, bounded by what Meta actually permits |
| [`06-audience-and-contact-ux-study.md`](06-audience-and-contact-ux-study.md) | Shared Audience architecture proven, Parts 22 and 23 answered, the five-scope action map |
| [`07-branding-audit.md`](07-branding-audit.md) | the Part 24 counts by class, the central mechanism that already exists, and the daily revert that defeats it |
| [`08-documentation-existing-system-study.md`](08-documentation-existing-system-study.md) | the Help Center and Super Admin as they are |
| [`09-documentation-target-architecture.md`](09-documentation-target-architecture.md) | the Part 25 answer: yes with extension, no migration — and the slug risk it depends on |
| [`10-changelog-architecture.md`](10-changelog-architecture.md) | reuse the documentation content model; the field-by-field mapping and its two mismatches |
| [`11-permissions-and-tenant-map.md`](11-permissions-and-tenant-map.md) | the four gating layers, the authorization recipe per new surface, and the honest telemetry answer |

## Phase P2, as implemented

| | |
|---|---|
| [`13-audience-ux-implementation.md`](13-audience-ux-implementation.md) | the Audiences destination, the explainer, the campaign round trip, and the two things deliberately not built |
| [`14-flow-template-additions.md`](14-flow-template-additions.md) | two templates, and the handoff priority the builder was dropping |
| [`15-automation-recipe-additions.md`](15-automation-recipe-additions.md) | four recipes, including the first one a brand-new account can use |
| [`16-commerce-aware-starters.md`](16-commerce-aware-starters.md) | what each store platform really reports, and abandoned cart recorded as COMING LATER |
| [`17-macro-starters.md`](17-macro-starters.md) | six starters, the three server constraints, and the first gallery an agent can reach |
| [`18-setup-recipes.md`](18-setup-recipes.md) | the multi-object extension to the recipe contract |
| [`19-starter-experience-coherence.md`](19-starter-experience-coherence.md) | one way in to four catalogues; why relevance is stated; why there is no marketplace |
| [`20-p2-regression-results.md`](20-p2-regression-results.md) | every gate run, with numbers, plus the findings P2 proved and left for a later phase |
| [`P2-FINAL-CHECKPOINT.md`](P2-FINAL-CHECKPOINT.md) | the 58-item checkpoint |

## The eight findings that decide the program

1. **Commerce automation is read-driven, not webhook-driven.** `Automation::CommerceEvents.dispatch` has exactly
   one call site (`custom/app/models/commerce/contact_metric.rb:27`), reached only when something re-reads the
   order. A provider webhook merely invalidates cache. Every "notify the customer the moment X happens" recipe
   therefore fires when an agent opens the conversation panel. This reshapes the whole commerce catalogue — `03` §1.
2. **Branding already says Lynomia, and reverts to Chatwoot daily.** Ten config keys carry the brand, and
   `Internal::ReconcilePlanConfigService#reconcile_premium_config` overwrites them from
   `enterprise/config/premium_installation_config.yml` whenever the plan is `community` — the seeded default.
   Highest value, smallest fix in the program — `07` §3.
3. **Abandoned-cart automation is impossible today.** No cart table, cart is a `Data.define` in Redis, and the
   cache is *deleted* not staled on webhooks, so there is nothing to diff — `03` §8.
4. **There is no Conversation Workflow engine**, and inventing one is not warranted. Thirteen use cases map onto
   Automation, Macro, Flow and conversation actions — `02` §5.
5. **A Shared Audience cannot accept an arbitrary set of contacts.** It is a saved filter re-resolved at every
   send; no membership table exists across 108 tables; an id-in-a-set filter is not expressible. A label is the
   correct persistent grouping — `06` §2.
6. **Help Center can carry global product docs with no migration**, because the public path resolves a portal by
   globally unique slug with no account in the URL. The risk it depends on: that namespace is
   first-come-first-served with no reservation — `09` §2.
7. **The recipe architecture cannot express a multi-object kit, a macro starter or a template starter.** `type`
   is a scalar, `build` returns one payload, the dialog emits one create event — `02` §6.
8. **Telemetry cannot answer "starter selected / completed / abandoned".** Amplitude only, no token shipped, so
   all 96 call sites are no-ops, and zero of them are on a recipe path — `11` §9.

## Method, and what it cost

15 read-only inventory agents, then 6 adversarial verifiers on the claims a wrong answer would have ruined.
**Four of six came back `PARTLY_WRONG`.** One inventory agent **fabricated a citation** — it twice reported a
`quality_score` grep hit in a named file; the string appears nowhere in the repository. Without the verify pass
the WhatsApp architecture would have rested on a field the code has never seen.

A completeness critic then re-checked the 13 deliverables and caught two errors that had been **propagated from
the corrections file into the documents** — a withdrawn CSAT claim and a wrong listener line number repeated
three times. Both are corrected; the withdrawal is recorded in place at `00` §6.1 rather than deleted, because
the reasoning is worth keeping.

Prior discovery under `docs/` was treated as an index of where to look, never as evidence. That rule earned its
keep: `docs/contacts/05-bulk-labels.md` still describes a capability that shipped.
