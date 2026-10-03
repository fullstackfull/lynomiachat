# Recipe end-to-end

What was run, what passed, and where the boundary is. The browser harness and its honest limits are described in
[07](07-e2e.md) §1.

## 1. Browser scenarios

Run by `docs/usability/e2e/run.sh`, four times each (English and Arabic, 1280×900 and 390×844).

### A · New flow → Templates → Order tracking bot

```text
open the gallery                       the six templates, Commerce ones first because the account has a store
Use this                               the wizard: team (one in the fixture account, so filled in), language ("both")
choose the team                        one select
Create                                 → 12 nodes, 19 edges, the chosen team on the handoff
```

**4 clicks, measured.** The emitted graph is asserted node-for-node in the journey; that it is a graph the server
would accept is asserted for **every template in every language** by `flowTemplates.spec.js` (37 assertions against
the transcribed node contracts, graph rules, node validation and channel limits).

What the browser run does **not** cover: that `POST /flows` and `PUT /flows/:id/draft` actually store it, and that
the builder then renders it. The page half is covered by `settings/flows/specs/Index.spec.js` — the two calls, their
order, the graph passed, the navigation to the builder, and the failure path.

### B · New automation → Recipes → Customer with an open order

```text
open the gallery                       the seven recipes
Use this                               the wizard: team
choose the team                        one select
Create                                 → { event_name: conversation_created,
                                            conditions: [commerce_active_order equal_to true],
                                            actions: [assign_team [1]],
                                            active: false }
```

**4 clicks, measured.** `active: false` is asserted in the journey. The page half — the exact payload, the
provenance description, the "Created. Review it before you turn it on." alert, opening the edit panel, and the
failure path — is in `settings/automation/specs/Index.spec.js`.

### C · New audience → Presets → High-value buyers

```text
open the gallery                       the seven presets
Use this                               the wizard: currency (two in the fixture account, so asked), amount (1000)
choose SAR                             one select
Create                                 → { payload: [ commerce_spend_sar is_greater_than "1000" ] }
```

**4 clicks, measured**, plus the two of the existing name-and-share dialog. The built condition is asserted in the
journey; that it is a condition the engine accepts is asserted in `audiencePresets.spec.js`.

### D · Requirements, honestly

With the fixture account's store removed, a preset that needs one renders **"Needs a connected store first"** and no
Create button. Asserted in `RecipeDialog.spec.js`, which drives the same gate with the context swapped.

### E · Validation and recovery

In `RecipeDialog.spec.js`: a missing required value refuses to create and says which field; a number outside the
recipe's declared range refuses with the range; an address that is not http(s) refuses — `javascript:` among them —
and the same field accepts a valid one immediately after. After a failed create the dialog keeps the recipe **and**
the values, so one field can be fixed and tried again.

## 2. Counts

| Suite | Assertions | Result |
|---|---|---|
| `recipes/specs/flowTemplates.spec.js` | 37 | pass |
| `recipes/specs/automationRecipes.spec.js` | 18 | pass |
| `recipes/specs/audiencePresets.spec.js` | 10 | pass |
| `recipes/specs/useRecipeContext.spec.js` | 10 | pass |
| `recipes/specs/catalogue.spec.js` | 10 | pass |
| `components-next/recipes/specs/RecipeDialog.spec.js` | 10 | pass |
| `settings/flows/specs/Index.spec.js` | 6 | pass |
| `settings/automation/specs/Index.spec.js` | 6 | pass |
| `Contacts/.../specs/ContactMoreActions.spec.js` | 8 | pass |
| `campaigns/pages/specs/WhatsAppCampaignsPage.spec.js` | 6 | pass |
| `helper/specs/audienceHelper.spec.js` | 6 | pass |
| browser journeys | 38 checks over 16 journeys | pass |

The whole frontend suite — **476 files, 4893 tests** — passes with these in it.

## 3. Setup effort, before and after

| | Before | After |
|---|---|---|
| Order tracking bot | ≈59 interactions (12 palette clicks, ≈25 fields, 19 edge drags), then Save and Publish | **4 clicks** to a complete draft, then edit and publish |
| "Customer with an open order" rule | ≈15 clicks, saved **active** | **4 clicks**, saved **switched off** |
| High-value buyers audience | ≈11 clicks, after knowing the Commerce field model | **6 clicks**, with the currency and the threshold asked outright |

## 4. Not covered here

- A real Rails request cycle, for the reason in [07](07-e2e.md) §1 — this container has no Docker daemon, the wrong
  Ruby, and no running Postgres.
- A real WhatsApp send from a flow created by a template. That is the Flow Builder phase's standing operator-side
  UAT (`docs/flow-builder/uat/`), still pending, and unchanged by this phase: a template produces the same kind of
  draft a person would build by hand, so it adds nothing new to verify there.
