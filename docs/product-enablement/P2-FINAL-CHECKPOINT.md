# Phase P2 — final checkpoint

**Audience UX + starter library expansion.** Branch `claude/practical-thompson-9xfqed`.
Commits `75d06597`, `31126b9c`, `3f63f630`, `a308ec1e`, `d12adff2`, `c904e2ee`, `c0025f2a`, `4470ac1c`,
`ae665ea9` and the closeout commit carrying this file.

Every item is a claim about what is in the branch. Where a claim is empirical the evidence is in
`20-p2-regression-results.md`.

---

## Branding closeout

| # | Item | Verdict |
|---|---|---|
| 1 | The official product name is `Lynomia Chat` | `INSTALLATION_NAME` and `BRAND_NAME` are `'Lynomia Chat'` |
| 2 | Fixed at the canonical source only | `config/installation_config.yml` plus the enterprise overlay, so the plan reconcile stays a non-writer; no page title or component hardcodes it |
| 3 | No second writer introduced | the overlay repeats the same value, which is what makes `reconcile_premium_config` a no-op by construction |
| 4 | Reach of the change stated, not assumed | a fresh install seeds `Lynomia Chat` (verified on a freshly seeded database); an existing row is kept, because `ConfigLoader` defaults to `reconcile_only_new: true`. Operator remedy recorded; no data migration written |
| 5 | No other branding work done in this phase | one exception, declared: an Arabic string on an audience surface that hardcoded the brand where English takes `{installationName}`. The other 27 of that class are counted, located and left |

## Part A — Audience UX

| # | Item | Verdict |
|---|---|---|
| 6 | A1 — it is explicit that an audience is a saved dynamic filter | `AudienceExplainer.vue`, on the Audiences page and in the campaign recipients section |
| 7 | A2 — the label-versus-audience rule is stated where people decide | the same component, on by default: "If you can point at the customers, use a label. If you can describe them, use an audience." |
| 8 | A3 — there is an Audiences destination | route `contacts_dashboard_audiences_index`, page, card, sidebar leaf; one request, no new model, no new endpoint |
| 9 | A3 — the destination shows name, shared state, conditions and usage | all four read from the record the sidebar already fetched |
| 10 | A3 — a count is available on demand | one button per row, `ContactAPI.filter` → `meta.count`; nothing counted on load |
| 11 | A3 — edit, duplicate, use-in-campaign, use-in-automation, create-from-preset, create-from-filters | all present; edit routes to the filter panel that already owns it rather than adding a second editor |
| 12 | A4 — the campaign → audience round trip keeps the campaign | verified end to end in the browser, including the restored title and the prefilled audience |
| 13 | A5 — empty states offer the thing that fills them | shared `EmptyState.vue` on the Audiences page, the explainer in the campaign picker |
| 14 | A6 — the audience selector says what each audience asks for | `summariseAudience` from the stored query, costing no request |
| 15 | A7 — save-as-audience is no longer an unexplained icon | a labelled button; the visible text is its accessible name |
| 16 | A8 — who may do what is honoured, not re-implemented | no policy or controller changed; the UI offers only what the server allows |
| 17 | No static audience membership was introduced | there is nowhere to put members, and nothing was added to create one |
| 18 | "Add selected contacts to a shared audience" was not built | it is architecturally wrong; the label path is the answer, and one new recipe bridges the two directions honestly |

## Part B — starter library and coherence

| # | Item | Verdict |
|---|---|---|
| 19 | Macro starters exist | six, in `recipes/macroStarters.js` |
| 20 | They respect `action_params` being a flat scalar array | asserted per starter; a hash would be silently dropped by strong params |
| 21 | They use only action types the builder can render | fifteen; `change_status` deliberately excluded so what a starter makes stays editable |
| 22 | They never embed an account id | asserted; every resource is an input |
| 23 | One starter works with nothing set up | `take_conversation`, via the macro-only `'self'` sentinel |
| 24 | Macro visibility matches what the server will actually do | `global` for an administrator, `personal` otherwise, because `set_visibility` overwrites rather than rejects |
| 25 | B1/B2 — all four catalogues are reached the same two ways | header button and empty state, on audiences, automation, flows and macros |
| 26 | B2 — all four empty states are the same component | shared `EmptyState.vue`; the two hand-rolled ones were replaced and macros gained one |
| 27 | B2 — every entry point reads the same way | "Start from a &lt;noun&gt;", each keeping its domain noun; the three labels that said it differently are retired |

## Parts C, D, E, F — catalogue expansion

| # | Item | Verdict |
|---|---|---|
| 28 | C — flow templates expanded | six to eight: `faq_menu`, `complaint_intake` |
| 29 | C — every template still satisfies the graph contract | asserted in all three languages: one Start, every edge on a real output, every required output connected, nothing unreachable, no loop without a wait, WhatsApp limits respected |
| 30 | C1/C2 — resources are mapped from the account, never invented | teams and audiences by id, labels by title, store implicit in the account's configuration |
| 31 | D — automation recipes expanded | seven to eleven |
| 32 | D — one recipe now works on a brand-new account | `greet_new_conversation` requires nothing |
| 33 | D1 — every recipe-built rule arrives switched off | `active: false` in `build`, unchanged |
| 34 | E1 — provider capability gates respected | no starter performs a provider action; the gate stack and PRE_UAT are documented rather than worked around |
| 35 | E2 — nothing unsupported is advertised as ready | four starters carry a platform note naming which platforms report what, in the gallery and on the wizard step |
| 36 | E2 — the capability claims are sourced | each normalizer's own status map, quoted by file and line |
| 37 | E3 — provider-aware recommendation | the note at the decision point, plus relevance ordering driven by whether a store is actually connected |
| 38 | Abandoned cart NOT implemented | and shown nowhere as ready |
| 39 | Abandoned cart recorded as COMING LATER, with its blocker | no persisted cart (schema proven empty of carts; the Redis entry is deleted, not staled) and recovery held pre-UAT for every platform |
| 40 | F — macro starters are part of one library, not a side door | same contract, same dialog, same gating, same copy shape |

## Parts G, I, J, K — setup recipes, relevance, search, permissions

| # | Item | Verdict |
|---|---|---|
| 41 | G — the single-payload contract was EXTENDED, not replaced | an optional `steps` array; `RecipeDialog` unchanged |
| 42 | G — a later step can use what an earlier one created | `spend_audience_routing` points its rule at the audience id the server returned |
| 43 | G1 — partial failure is reported, not hidden | the page names what already exists; nothing further is created after a refusal |
| 44 | I — "recommended for your setup" is stated and deterministic | one rule, read from data the dashboard holds; no model, no score, nothing sent anywhere |
| 45 | I — relevance never hides anything | it changes order and adds a label |
| 46 | J — no marketplace | no server-side catalogue, no install lifecycle, no back-reference from a created object; no search box over eleven rows |
| 47 | K — tenancy preserved | every option list is the current account's own; every write goes through an account-scoped endpoint |
| 48 | K — permissions preserved | setup recipes live where both their steps are allowed; cross-module shortcuts ask the target route |

## Parts L, M, N, O — UI, parity, performance, migrations

| # | Item | Verdict |
|---|---|---|
| 49 | L — 390 / 768 / 1024 / 1280 all fit | no horizontal scroll measured at any of the four in English, nor at any of the four in Arabic |
| 50 | L — RTL correct | the page computes `rtl`, the copy is Arabic, and the card's menu follows the reading direction |
| 51 | L — keyboard and accessible names | focus reaches every audience action; every visible control on the page and in the gallery has an accessible name; each card's menu names its own audience |
| 52 | M — nothing was removed to make room | every from-scratch path is untouched and still offered, including the gallery's own "start from scratch" |
| 53 | N — no provider call in ordinary browsing | the only on-demand request is the contact count, and only when asked |
| 54 | N — opening a gallery adds no request | beyond the one cached Commerce options call the contact filter already makes |
| 55 | **O — ZERO MIGRATIONS** | none written, none needed; no item required one |

## Parts P, Q — record and verification

| # | Item | Verdict |
|---|---|---|
| 56 | P — docs 13 to 20 written, plus this checkpoint | and indexed from the directory README |
| 57 | Q — every gate run, with numbers | ESLint 0 errors; Vitest 5160 tests green; RSpec 10601 examples with the 2 pre-existing baseline failures and nothing else; RuboCop no offenses; the production build clean; 52 browser journey checks and 5 accessibility checks green. See `20-p2-regression-results.md` |
| 58 | Q — findings reported honestly, including the ones against my own work | four defects this phase found and fixed in its own additions; three pre-existing gaps counted and left with their reasons; one 421-failure test run diagnosed to a polluted database rather than called a flake, and proven so by a clean re-run matching the known baseline exactly |

---

## Stop conditions — none triggered

Nothing in this phase required static audience membership, a Conversation Workflow engine, a new Bot,
Automation, Macro, Campaign or Commerce engine, abandoned-cart persistence, a WhatsApp Template Manager, a
Documentation CMS, or AI. `components-next/ConversationWorkflow/` is upstream Chatwoot's
conversation-required-attributes UI and was not touched.

---

AUDIENCE UX: MADE SHARED AUDIENCES UNDERSTANDABLE
STARTER LIBRARY: EXPANDED
NOT: CREATED A NEW WORKFLOW, AUDIENCE, AUTOMATION, BOT, MACRO OR COMMERCE ENGINE
