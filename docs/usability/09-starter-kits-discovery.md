# Starter kits: discovery of existing template and preset mechanisms

Question asked before writing any code: **does Chatwoot or Lynomia already have a way to start an object from a
prepared configuration?** Everything below was read in the repository.

## 1. What already exists

| Mechanism | Where | What it does | Reusable as a recipe host? |
|---|---|---|---|
| **Automation clone** | `automations/clone` → `AutomationAPI.clone(id)` → `POST /automation_rules/:id/clone` | copies an existing rule | **No** — it needs an existing rule. It is the right model *after* a first rule exists, which is exactly the gap: there is no first rule |
| **Flow node duplicate** | `flowGraph.js` `duplicateNode`, `FlowBuilder.vue` `duplicateSelected` | copies one node on the canvas | **No** — node scope, not flow scope |
| **`Flows::Versions::STARTER`** | `custom/app/services/flows/versions.rb` | the two-node graph (Start → End) a new flow's first draft is created from | **Yes, conceptually.** It proves a flow's first draft is just "a graph handed to `save!`". A template is a different graph handed to the same method. **This is the extension point** |
| **Campaign empty-state fixtures** | `components-next/Campaigns/EmptyState/CampaignEmptyStateContent.js` | fake campaign rows rendered behind the empty state, purely decorative | **No** — they are never created as records |
| **Macros** | `settings/macros`, `useMacroHotKeys` | an admin-authored, saved, re-runnable sequence of actions on a conversation | **No, and must not be confused with this.** A macro acts on a conversation at runtime. A recipe creates a configuration object once. Different lifecycle, different engine |
| **Canned responses** | `settings/canned` | reusable message text | **No** — message content, not configuration |
| **Captain / Help Center seeding** | `enterprise/`, `Seeders::AccountSeeder`, `Internal::SeedAccountJob` | bulk sample data for dev and Super Admin | **No** — a dev/admin utility that creates sample *data*, not a user-facing starting point. Reusing it would mean enqueueing a seeding job from a product button |
| **`AddAutomationRule.START_VALUE`** | `settings/automation/AddAutomationRule.vue` | the blank rule a new rule form opens on | **Yes, conceptually** — `open()` already replaces the whole `automation` object, so a recipe is a different start value |
| **`CreateSegmentDialog`** | `components-next/Contacts/ContactsForm/CreateSegmentDialog.vue` | saves the *currently applied* contact filter as a segment | **Yes, conceptually** — a preset is a prepared `query` posted to the same `customViews/create` |
| **Prefilled forms via route query** | used across the dashboard (`contacts_dashboard_index` takes `page`, `search`; `ContactsList` forwards `route.query`) | routes carry state | **Yes** — this is how "Use in Campaign" passes an audience without a new mechanism |

## 2. Conclusion

**No template framework exists, and none needs to be built.** All three object types already have a public,
policy-checked creation path that accepts a complete prepared payload:

```text
Flow      POST /api/v1/accounts/:id/flows            { name, description }
          PUT  /api/v1/accounts/:id/flows/:id/draft  { graph }        ← Flows::Versions#save! → GraphValidator
Automation POST /api/v1/accounts/:id/automation_rules { name, event_name, conditions, actions, active: false }
Audience  POST /api/v1/accounts/:id/custom_filters   { name, filter_type: contact, shared, query: { payload } }
```

A recipe is therefore **data plus a pure build function**, held in version control, that produces one of those three
payloads from the resources the user picks. It is not a runtime, not a table, and not a new API.

## 3. What was deliberately not created

| Not created | Why |
|---|---|
| a recipes database table | recipes are source code; nothing about them is per-account. Stop condition 7 |
| a migration of any kind | **zero migrations.** Confirmed: no file added under `db/migrate` or `custom/db/migrate` |
| a recipes REST endpoint | the catalogue is static and already shipped to the browser in the bundle; an endpoint would add a round trip and a second source of truth |
| a template marketplace / "save my template" | out of scope by instruction, and it would need exactly the table above |
| a new bot model (`OrderTrackingBot`, `VipBot`, …) | a flow bot is `AgentBot(bot_type: :flow)`. Friendly product names are UI strings only |
| a second automation / flow / audience engine | the recipe hands a payload to the existing one |
| a recipe-aware runtime | a created object keeps no live link to its recipe. See [10](10-recipe-architecture.md) §6 |
| `created_from_recipe` provenance as a stored field | §19 of the brief allows it **only** if existing metadata can hold it. `agent_bots` does have a spare `bot_config` jsonb, and `automation_rules` / `agent_bots` both have a `description`; `custom_filters` has neither (`name`, `filter_type`, `query`, `shared` only). So a *partial* stored provenance was possible and was still rejected: nothing in the product would read it, it would be exposed inconsistently across the three object types, and writing a field no code consumes is dead data. Instead the recipe's name and version are written into the **description** of the objects that have one (flow, rule) as ordinary editable text a human can read, and nowhere else. **No migration, no new column, no runtime dependency.** |

## 4. Where the recipe entry points live

No new navigation. Each entry point is on the page that already creates that object:

| Object | Entry point | Existing component extended |
|---|---|---|
| Flow | Settings → Flow Builder → **New flow** dialog gains a "Start from a template" choice; the empty state offers the same | `settings/flows/Index.vue` |
| Automation | Settings → Automation → **Add** gains "Start from a recipe"; the empty state offers the same | `settings/automation/Index.vue` + `AddAutomationRule.open(startValue)` |
| Audience | Contacts → overflow menu → **New audience from a preset**; also offered from the audience actions menu | `Contacts/ContactsHeader/components/ContactMoreActions.vue` |

Commerce → "Create an order-tracking bot" was considered as a fourth entry point and **rejected**: it would put a
Flow Builder action on the Commerce settings page, which is a navigation surprise, and the flow template list already
sorts Commerce templates first when a store is connected.
