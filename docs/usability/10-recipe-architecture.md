# Recipe architecture

What a recipe is, and everything it deliberately is not. Discovery of the existing mechanisms is in
[09](09-starter-kits-discovery.md); the study that chose the catalogue is [09a](09a-recipe-opportunity-study.md).

## 1. The shape of it

```text
app/javascript/dashboard/recipes/
  index.js              the manifest contract: CATEGORIES, REQUIREMENTS, INPUT_TYPES, RECIPE_STATUS, joinConditions
  audiencePresets.js    7 presets  → the `query` of a contact filter
  automationRecipes.js  7 recipes  → the payload of an automation rule
  flowTemplates.js      6 templates → the graph of a flow bot
  starterCopy.js        the curated Arabic and English copy the flow templates send
  useRecipeContext.js   what the account has, and therefore which recipes it can use
  specs/                the catalogues checked against the backend's own contracts

app/javascript/dashboard/components-next/recipes/
  RecipeDialog.vue      choose a recipe, then give it the values it needs
  RecipeInputs.vue      one control per input type, every option list from this account
```

**A recipe is source code and a pure function.** No table, no migration, no endpoint, no runtime.

## 2. The manifest contract

| Field | Meaning |
|---|---|
| `id` | stable, snake_case, unique within its type |
| `type` | `audience`, `automation` or `flow` |
| `version` | bumped when `build` changes. Objects already created are never touched |
| `name`, `description` | i18n keys, so the gallery is translatable |
| `category` | one of `support`, `ecommerce`, `retention`, `operations`, `integrations` |
| `requires` | `REQUIREMENTS` keys the account must satisfy |
| `inputs` | the account-specific values to ask for, in order, each with a type from `INPUT_TYPES` |
| `build(values)` | returns the payload for that type's own create call. **Pure**: no requests, and no id it was not given |

Flow templates also carry `nodeCount` and `edgeCount` — what the docs and the gallery quote as the work saved. The
specs assert them against what `build` really produces, so the claim cannot drift.

## 3. Instantiation

```text
Audience    preset.build(values)  → { payload: [conditions] }
            → the existing "save these filters as an audience" dialog (name, and share for administrators)
            → POST /custom_filters                       → Custom::Contacts::FilterService validates on first use

Automation  recipe.build(values)  → { event_name, conditions, actions, active: false }
            → the page adds name + description
            → POST /automation_rules                     → AutomationRule + Custom::AutomationRule validation
            → the created, disabled rule opens in the edit panel for review

Flow        POST /flows { name, description }             → AgentBot(bot_type: :flow), Flows::Audit records it
            → template.build(values)  → { nodes, edges }
            → PUT /flows/:id/draft                       → Flows::Versions#save! → GraphValidator shape check
            → the builder opens on the draft              → publish runs the full GraphValidator
```

**Every created object goes through the ordinary path.** No validator is bypassed, no policy is skipped, and the
audit trail is the usual one.

## 4. Availability, deterministically

`useRecipeContext` answers each requirement from data the dashboard already holds, plus the single cached Commerce
options call the contact filter already makes (`GET /commerce/audience_fields`). Opening the gallery adds **no
request of its own** and asks **no provider anything**.

| Requirement | Answered from |
|---|---|
| `contact_filter` | the `crm` feature flag |
| `commerce` | the `lynomia_commerce` feature flag |
| `commerce_store` | the connected stores the audience-fields call returns — already filtered to `Commerce::Providers.enabled`, so a provider the installation has switched off can never appear |
| `commerce_currency` | the currencies Lynomia has actually seen in this account's orders |
| `flow_builder`, `automations`, `webhooks` | the `lynomia_flow_builder`, `automations`, `api_and_webhooks` flags |
| `shared_audience` | the contact filters the store holds, `shared: true` only |
| `team`, `label` | the account's teams and labels |

A recipe with an unmet requirement is shown with what is missing and **no Create button**: better than letting
someone build a configuration that cannot work. Usable recipes sort first; among them, Commerce ones first for an
account with a connected store, then audience-based ones for an account that has shared audiences. **Order only —
relevance never hides anything.**

## 5. Smart resource mapping

Filled in without asking: a sole team, a sole store, a sole currency, a sole shared audience, and any `default` the
recipe declares (a priority of High, 30 days, a threshold of 1000). **Never** filled in: a webhook address, and
anything where the account leaves a real choice. Nothing destructive or financial is preselected, and the user
confirms before anything is created.

The inbox is deliberately **not** asked for. [09a](09a-recipe-opportunity-study.md) §8 has the reason: connecting a
flow replaces whatever bot the inbox already has, so it stays an explicit act in the builder, where the consequence
is visible.

## 6. Versioning and provenance

A recipe's `version` describes the **catalogue entry**, not the object. Editing a recipe later cannot touch anything
already created: `build` runs once, at creation, and the result is an ordinary record from then on.

Provenance is informational only, and is **not stored as a field**. `custom_filters` has nowhere to put it without a
migration, and writing it into `agent_bots.bot_config` for flows alone would be data nothing reads. Instead the
recipe's name and version go into the **description** of the objects that have one:

```text
Created from the Order tracking bot template (v1).
Created from the Audience gets priority recipe (v1).
```

Ordinary editable text a human can read. **No runtime depends on it.**

## 7. Safe default state

| Created | State |
|---|---|
| Flow | a **draft**, unpublished, connected to no inbox |
| Automation rule | **disabled**, then opened for review; enabling it is the existing toggle, with its existing confirmation |
| Audience | saved only when the user confirms the name, and shared only if they tick the box (administrators only) |
| Campaign | nothing is created — see [09a](09a-recipe-opportunity-study.md) §6 |

**Nothing a recipe creates can message a customer until a person publishes or enables it.**

## 8. Editability

A created object carries no mark that limits it. Nodes, text, teams, audiences, conditions, actions, labels, stores
and thresholds are all editable, the object can be duplicated, disabled and deleted, and the recipe has no further
say in it.

## 9. Extensibility

An AI, CRM or SLA recipe later needs a new `REQUIREMENTS` key and, for a flow, nodes that exist by then. The contract
itself does not change, and nothing in this phase anticipates those features beyond leaving the key list open.
