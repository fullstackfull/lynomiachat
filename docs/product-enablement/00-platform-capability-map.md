# Platform capability map

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`. Schema version
`2026_10_04_110000` (db/schema.rb:13), 108 tables.

Provenance: 15 area inventories, re-checked by six adversarial verifiers. Where they disagreed the verifier's number is
used and marked **(V)**. Every aggregate count that cannot carry a `path:line` names the command that produced it.
Claims I could neither cite nor reproduce are marked **UNVERIFIED**.

---

## 1. The decision in one page

Lynomia is a fork of Chatwoot carrying a large, genuinely finished Lynomia layer. Flow Builder, Commerce (4 providers),
Audience, Campaign-audience references and the billing plan layer are all wired end to end, under flags, with policies
and validation. There is almost nothing structurally missing from the *engines*.

What is missing is the **entry path**. The product has 21 flow node types, 12 automation triggers, 20 automation
actions, 16 macro actions and 22 starter recipes, and a first-run administrator meets: a settings sidebar, three empty
list pages, and a save-filter icon button. The recipe catalogues that were supposed to be that entry path are
**client-side JavaScript constants with no server, no catalogue table, no provenance link and zero telemetry** — so
nobody can answer "did anyone use a starter".

Three facts constrain every build decision that follows:

| Fact | Consequence |
|---|---|
| Commerce automation is **read-driven**, not webhook-driven **(V)** | A commerce rule fires only when something re-reads the order — in practice when an agent opens the conversation panel. Any "automatic" commerce recipe is a false promise. |
| `Commerce::Switches::PRE_UAT` holds salla/zid/shopify for both `actions` and `recovery`, and WooCommerce has no `RECOVERY_KEYS` entry (custom/app/services/commerce/switches.rb:15-16) | Order actions and **all** cart/recovery features are hard-off in a default production install for every provider. |
| The recipe contract is one scalar `type` + one `build()` returning one payload (app/javascript/dashboard/recipes/index.js:9-23) | No multi-object kit, no macro starter, no WhatsApp-template starter is expressible without changing the contract. |

Headline classification: **EXTEND the recipe layer, REUSE every engine underneath it, PATCH four defects, and DO NOT
CREATE an abandoned-cart recipe or a "Conversation Workflow" engine.**

---

## 2. The three-tree overlay

Three source trees are joined at boot, not merged:

| Tree | Files | Role |
|---|---|---|
| `app/` | — | Upstream Chatwoot OSS. The base of every ancestor chain. |
| `enterprise/` | 557 (`find enterprise -type f`) | Chatwoot EE: SLA, custom roles, audit, Captain AI, premium features. |
| `custom/` | 242 (`find custom -type f`) **(V)** | Lynomia: Flow Builder, Commerce, billing, shared audiences, mobile auth. |

- `ChatwootApp.extensions` returns `%w[enterprise custom]` (lib/chatwoot_app.rb:40-48), so the resolution order is
  **Custom → Enterprise → base**.
- `config/application.rb:46` and `:52-55` put `enterprise/app/**` then `custom/app/**` on the eager-load path, unshift
  both view paths, and append `custom/db/migrate`.
- `prepend_mod_with` / `include_mod_with` are defined by `InjectEnterpriseEditionModule`
  (config/initializers/01_inject_enterprise_edition_module.rb:70-80 `each_extension_for`, `Module.prepend` at the file
  tail). A missing extension namespace resolves to `false` and is skipped (`const_get_maybe_false`), so an
  `enterprise/`-only build still boots.
- Practical rule for this programme: `prepend_mod_with('XxxPolicy')` can **only ever** resolve to an `Enterprise::`
  module, because `custom/app/policies` contains two concrete policies and zero override modules
  (custom/app/policies/commerce/store_policy.rb, custom/app/policies/commerce/action_policy.rb).

Classification: **REUSE.** The overlay works, is load-bearing, and is the correct place for anything Lynomia-only.
Do not edit OSS files for Lynomia-only behaviour.

---

## 3. Counted inventory

| Primitive | Count | Citation |
|---|---|---|
| Flow node types | **21** | custom/app/services/flows/node_types.rb:9-34 |
| Flow node executors | 21 (+3 shared bases = 24 files) | `ls custom/app/services/flows/nodes/` |
| Flow graph validators | 3 | `flows/{graph_validator,node_validator,template_validator}.rb` |
| Flow templates (frontend only) | **6** | app/javascript/dashboard/recipes/flowTemplates.js:74,155,220,279,329,373 |
| Automation triggers | **12** = 5 + 7 | app/listeners/automation_rule_listener.rb (5 methods); custom/app/listeners/custom/automation_rule_listener.rb:5-7 over `Commerce::OrderTransitions::EVENTS` (custom/app/services/commerce/order_transitions.rb:29) |
| Automation conditions | 18 OSS + `sla_policy_id` (EE, dead) | app/models/automation_rule.rb:49-52 |
| Automation actions | **20** = 19 OSS + `add_sla` **(V)** | app/models/automation_rule.rb:54-59; enterprise/app/models/enterprise/automation_rule.rb:6-8 |
| Automation recipes | **7** | app/javascript/dashboard/recipes/automationRecipes.js:74,90,106,123,140,165,198 |
| Macro actions (model) | **16** | app/models/macro.rb:33-35 |
| Macro actions (builder UI) | 15 — `change_status` is API-only | app/javascript/dashboard/routes/dashboard/settings/macros/constants.js (15 `key:` entries) |
| Agent bot types | 2 (`webhook: 0`, `flow: 1`) | app/models/agent_bot.rb:42 |
| Audience presets | **9** | app/javascript/dashboard/recipes/audiencePresets.js:52,58,64,86,105,125,133,143,152 |
| **Recipes, total** | **22** (9 + 7 + 6) | three files above |
| Commerce providers | **4** | custom/app/services/commerce/providers.rb:3-4 |
| Commerce tables | 4 | db/schema.rb:809, 837, 855, 870 |
| Commerce order events | 7 | custom/app/services/commerce/order_transitions.rb:22-29 |
| WhatsApp providers | 2 (`default`, `whatsapp_cloud`) | app/models/channel/whatsapp.rb:36 |
| Account feature flags | **72** | `grep -c '^- name:' config/features.yml` |
| Premium (EE) features | 9 | enterprise/config/premium_features.yml |
| Custom-role permissions | 7 | enterprise/app/models/custom_role.rb:37-45 |
| Policies | 26 OSS / 17 EE files (8 of them `Enterprise::` override modules) / 2 custom | `find app/policies -name '*.rb'`; `find enterprise/app/policies -name '*.rb'` |
| Super Admin dashboards | 8 OSS + 2 custom (billing) | `ls app/dashboards/`, `ls custom/app/dashboards/` |
| Audited models | 12 | `ls enterprise/app/models/enterprise/audit/` |
| DB tables | 108 | `grep -c '^  create_table' db/schema.rb` |
| `replaceInstallationName` reach | 32 non-spec files, 83 textual occurrences, 42 real invocations **(V)** | app/javascript/shared/composables/useBranding.js (32-file count reproduced independently) |
| `'woot'`-derived identifiers | 3,802 **(V)** | verifier count; my own grep over a wider dir set returned 7,957, so the figure is scope-sensitive — use the verifier's |
| Non-spec `useTrack(` call sites | 72 | `grep -rn "useTrack(" app/javascript --include=*.vue --include=*.js \| grep -v spec` |
| Telemetry calls on any recipe path | **0** | `grep -rn "useTrack\|analytics" app/javascript/dashboard/recipes/` → 0 |

---

## 4. Subsystem map

### 4.1 Flow Builder — **REUSE**

A flow is an `AgentBot` with `bot_type: :flow` (app/models/agent_bot.rb:42, prepended by
custom/app/models/custom/agent_bot.rb). Graphs are `flow_versions` rows (db/schema.rb:1254, draft/published/archived,
one each per bot by partial unique index); runs are `flow_sessions` (db/schema.rb:1232, one live session per
conversation). Runtime: `Flows::RunJob` (Redis-locked per conversation) → `Flows::Runner`, driven by six events from
`Custom::AgentBotListener`. Publishing, draft semantics, 3 validators, a variables allow-list, a transaction-rollback
Test Mode and a 50-row session inspector are all reachable from Settings → Flow Builder
(app/javascript/dashboard/components-next/sidebar/Sidebar.vue:851-854, gated by route-meta feature flag +
administrator).

Tree: `custom/` almost entirely. Channel support is **WhatsApp Cloud only** — `Flows::ChannelCapabilities.for` returns
nil for anything that is not a `Channel::Whatsapp` with `provider == 'whatsapp_cloud'`
(custom/app/services/flows/channel_capabilities.rb:21-23), and `unsupported` then rejects every capability-bearing node.

Defined but unused: `Flows::NodeTypes.terminal?` (custom/app/services/flows/node_types.rb:49) has no caller anywhere.
The flow template catalogue is **frontend-only** — there is no server-side catalogue, table, seeder or route
(config/routes/flows.rb exposes index/create/show/update/destroy/draft/publish/disable/sessions/simulate and nothing
else).

### 4.2 Automation — **EXTEND**

`AutomationRule` + two overlays. 12 triggers, 20 actions, 18+1 condition keys (§3). Conditions are gated twice: at
save by `conditions_attributes` (app/models/automation_rule.rb:49-52) and at run time by `lib/filters/filter_keys.yml`
via `AutomationRules::ConditionValidationService`. Frontend trigger parity is exact: 5 in
`AUTOMATION_RULE_EVENTS` (app/javascript/dashboard/routes/dashboard/settings/automation/constants.js:689) + 7 in
`COMMERCE_EVENTS` (.../lynomiaAutomation.js:13-21, behind `lynomia_commerce`).

Four defects/mismatches, all verifier-confirmed:

1. **`event_name` is not validated (V).** `app/models/automation_rule.rb` has no inclusion validation; only DB NOT NULL
   (db/schema.rb:313). An arbitrary `event_name` saves via the API and the rule simply never fires. Silent failure.
2. **`sla_policy_id` is a dead condition key (V).** Accepted by enterprise/app/models/enterprise/automation_rule.rb:2-4,
   but with no `filter_keys.yml` entry, no SQL branch and no UI it falls through to `custom_attribute_present?`
   (app/services/automation_rules/condition_validation_service.rb:35-47), returns false, calls
   `rule.authorization_error!`, and `Reauthorizable` auto-deactivates the rule after two evaluations and emails admins.
3. **`attribute_changed` is satisfiable on `conversation_updated` only (V).** `conversation.rb:328` passes nil for
   `conversation_created`; `:385` passes `status_change` for opened/resolved; `message_created` dispatches no
   `changed_attributes` (app/models/message.rb:380) yet the listener reads them
   (app/listeners/automation_rule_listener.rb:24) — always nil. Flow Builder rejects it outright
   (custom/app/services/flows/node_validator.rb:230).
4. **`AUTOMATIONS[event].actions` is dead data** — see §5.

The 7 automation recipes are all created with `active: false`.

### 4.3 Agent Bots — **REUSE**

Two `bot_type` values only. Four creation paths: account API (the only one accepting `bot_type`/`bot_config`),
Platform API (webhook only, can create account-less system bots), Super Admin administrate (webhook only), and the
Lynomia flows API (the only path that creates a flow bot). The Settings → Agent Bots UI deliberately hides flow bots
and always posts `bot_type: 'webhook'` with a required outgoing URL.

A bot attaches to an inbox through one `AgentBotInbox` row created by `POST /inboxes/:id/set_agent_bot`. The minimum
viable "ready-made bot" object set is proven by
app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:125-144: `AgentBot(bot_type: :flow)` + a draft
`FlowVersion` (POST /flows, then PUT /flows/:id/draft) — plus a **published** FlowVersion and an `AgentBotInbox`
before it answers anyone. There is no bot-template table, no seeder and no `bot_config`-driven configuration.

### 4.4 Macros — **REUSE**

16 action names (app/models/macro.rb:33-35), 12 implemented in the shared `ActionService` base and 5
overridden/added in `Macros::ExecutionService`; the builder offers 15. Execution is asynchronous
(`MacrosExecutionJob`, queue `:medium`) and per-action errors are swallowed into Sentry. There is exactly one macro
runtime, with an Enterprise mixin for required-attribute gating. No macro action touches custom attributes or Commerce,
and `add_sla` is automation-only because only `AutomationRule`'s attribute list is extended by Enterprise.

### 4.5 Conversation-level orchestration — **DO NOT CREATE**

There is **no** "Conversation Workflow" engine, model, table, service or state machine. `db/schema.rb` has zero
`/workflow/` tables and there is no `Workflow` class in `app/`, `enterprise/`, `custom/` or `lib/`. The phrase exists in
four cosmetic places: a frontend route `conversation_workflow_index`, a `components-next/ConversationWorkflow/` folder,
a sidebar label (Sidebar.vue:869-872), and a Swagger tag description. The settings page is a thin container rendering
two unrelated, independently-flagged features (`AutoResolve`, `ConversationRequiredAttributes`).

Real orchestration is distributed across eight systems: Automation Rules (+ delayed executions), Macros, Flow Builder,
the shared `ActionService` vocabulary, auto-assignment (V1 legacy + V2 policy-driven, with EE balanced/capacity),
Teams, EE SLA, and the conversation status/priority enums plus `bot_handoff!`. Automation, Macro and Flow genuinely
differ in **trigger model** (event / agent-invoked / per-conversation session graph), **state** (stateless / stateless /
persisted `flow_sessions`) and **scope** — but their action vocabularies overlap almost completely because all three end
up calling the same `ActionService`.

Two use cases map poorly and should not be promised: **out-of-hours handling** (no time-of-day or business-hours
condition anywhere in the rule engine) and **priority escalation** (no escalation-level concept; an explicit TODO in the
Captain handoff tool).

### 4.6 Commerce — **REUSE (engine) / DO NOT CREATE (recovery recipes)**

All commerce code is `custom/`-only. No `enterprise/` commerce overlay, no OSS commerce backend; the only `enterprise/`
touchpoint is the `commerce_order_manage` custom-role permission (enterprise/app/models/custom_role.rb:26,44) and the
only `app/` touchpoint is Vue UI. No commerce class uses `prepend_mod_with`, so there is no three-tree join here.

**Reads are never pushed.** Every provider webhook only says "this customer changed" and its payload is discarded;
all state and every normalized `commerce_order_*` event is produced by re-reading the store and diffing two normalized
reads through a 120-second Redis cache. There is no polling job (the only scheduled commerce job is
`Commerce::ActionSweepJob`). **(V)** `Automation::CommerceEvents.dispatch` has exactly one call site —
custom/app/models/commerce/contact_metric.rb:27 — and `ContactMetric.record` has exactly two callers,
custom/app/services/commerce/realtime.rb:93 and custom/app/services/commerce/conversation_panel.rb:62. **A commerce
automation rule therefore fires only if an agent opens the conversation panel, or a read is otherwise triggered.**

Webhook verification: WooCommerce (per-store HMAC-SHA256), Salla (app-secret HMAC-SHA256), Shopify (client-secret
HMAC-SHA256). **Zid is not signed at all** — HTTP Basic with a per-store random pair, and the request field that hands
those credentials to Zid is marked unverified in the code.

Capability truth table (NOT_AVAILABLE cells are verified negatives, not gaps in the inventory):

| | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| Write actions | 5 of 7 | **none** (custom/app/services/commerce/providers/salla.rb; inherits `supports_actions?` false from base.rb:66) | 1 status change + 2 transitions | cancel + refund only |
| `paid` reachable | yes | **no** — payment_status can only be `unpaid`/`unknown` (providers/salla/normalizer.rb:5-8,137-139) | yes | yes |
| `shipped` / `delivered` | **no** — no STATUSES entry, `shipments: []` hardcoded (providers/woocommerce/normalizer.rb:17-20,35) | yes | yes | yes |
| Tracking number | **no** — `tracking: nil` hardcoded (same file :14-15,93-98) | yes | yes | yes |
| Carts | **no** `supports_carts?` override → false (providers/base.rb:87) | list only (unfiltered 30-cart page, path/scope still VERIFY) | customer-filtered list + detail | `abandonedCheckouts` GraphQL, linked customers only |
| Recovery | **no** `RECOVERY_KEYS` entry (switches.rb:15) | PRE_UAT off | PRE_UAT off | PRE_UAT off |

Downstream consequences worth stating to a product owner: `commerce_order_shipped` can never fire for WooCommerce;
`commerce_order_paid` can never fire for Salla, and `Commerce::Customer360.spend` (which selects
`payment_status == 'paid'`) is therefore always empty for a Salla-only contact.

`supports_realtime?` is overridden by all four providers and **read nowhere** — see §5.

### 4.7 Abandoned cart — **NEW PRIMITIVE REQUIRED** (and therefore **DO NOT CREATE** a recipe today)

Confirmed by an independent verifier without correction. There is **no cart table** (zero `cart` lines in
db/schema.rb; the four commerce tables are listed in §3) and no cart migration. A cart is a transient
`Commerce::AbandonedCart` `Data.define`, cached in Redis only (FRESH_FOR 120s / KEEP_FOR 24h), and the cache is
**deleted, not staled,** on any order or cart webhook — so no durable prior cart state exists to diff.

Consequently there is no provider-neutral "cart became abandoned" transition: each cart's status is read straight off
the provider's own per-cart response (Shopify `completedAt`, Zid `phase`/`order_id`, Salla hardcoded `'abandoned'` for
anything still listed). Orders *do* have exactly such an engine (`Commerce::OrderTransitions`, diffing persisted
`commerce_contact_metrics.order_states`); the cart equivalent was simply not built.

There is **no trigger** (the complete commerce event set is the 7 `commerce_order_*` names,
custom/app/services/commerce/order_transitions.rb:29), **no condition**, **no flow node and no flow entry from a store
event** (flows are entered from a conversation message only — custom/app/services/flows/nodes/start.rb:1-16), and **no
campaign type** (app/models/campaign.rb:50 is `{ ongoing: 0, one_off: 1 }`).

Recovery exists and is **entirely human-driven**: an agent presses "Prepare recovery message", the browser writes the
text into the reply box, the agent sends it. Provider-native recovery APIs are explicitly not used.
`Commerce::RecoveryMessages#prepare` raises `RECOVERY_DISABLED` unless `AbandonedCarts.offered?(store)`, which is false
for WooCommerce always and for the other three while PRE_UAT holds.

A cart table + a cart transition engine + an event + a condition would each be needed. **That is a migration, so it is
stated as a requirement and left for approval — not proposed here.**

### 4.8 WhatsApp — **PATCH**

Mostly `app/` (OSS), with a thin `enterprise/` overlay (calling, campaign recipients, provider error capture) and a
thin `custom/` overlay (interactive list payloads, interactive-reply attributes, and the Flow Builder's own
`Flows::Template` / `Flows::TemplateValidator` / `Flows::Nodes::SendTemplate`).

Templates are **one jsonb column**, `channel_whatsapp.message_templates` (+ `message_templates_last_updated`). No
templates table, no per-template row, no template model. `sync_templates` does
`GET {WHATSAPP_CLOUD_BASE_URL}/v14.0/{business_account_id}/message_templates`, follows `paging.cursors.after`, and
writes Meta's `data` array **verbatim** via `update_columns` — nothing mapped, nothing discarded. Graph API **v14.0 is
hardcoded (V)**, long past Meta's support window.

Against Meta's actual template surface (list / create / edit / delete / single-template GET, all requiring
`whatsapp_business_management`), the repo is effectively read-only:

| Meta operation | Repo |
|---|---|
| `GET /{WABA}/message_templates` | Yes — polled every 3h into jsonb |
| `POST /{WABA}/message_templates` (create) | **CSAT only** — `Whatsapp::CsatTemplateService#create_template`, hardcoded UTILITY, one BODY, one URL button |
| `POST /{TEMPLATE_ID}` (edit) | **Absent in every tree.** The UI defers: "To create or edit a template, manage it with your provider" + a "Manage in Meta" deep link |
| `DELETE …?name=` | CSAT only |
| `GET /{TEMPLATE_ID}` | Absent |
| Create from Template Library | Absent — zero occurrences of `library_template_name` |
| Versioning / duplication | **NOT_SUPPORTED by Meta.** No duplicate/copy/clone/version endpoint exists. Do not mistake `custom/app/services/flows/template.rb` for one — it is a flow-side reader of synced templates |
| 4 template webhook fields (`message_template_status_update`, `_quality_update`, `_components_update`, `template_category_update`) | **Not subscribed, not handled, not routable.** `WEBHOOK_DEFAULT_FIELDS` is `%w[messages smb_message_echoes]` + `calls`; the only Meta webhook route is per-phone-number, and all four fields ignore phone-level callback overrides and go to the app's default callback URL |

Editable parameters **(V)**: Meta's normative template-management page permits editing only **category, components and
`message_send_ttl_seconds`**. (The wider list — `parameter_format`, `product_set_id`, `creative_sourcing_spec` — comes
from the node reference, not the normative page.) `sub_category` is a **CREATE** parameter, not merely readable, and
occurs 8× in app/javascript/dashboard/components-next/template-preview/templates/whatsapp-templates.js.

Two live WhatsApp defects: see §6 items 1 and 2.

### 4.9 Audience — **EXTEND**

An "Audience" is nothing but a saved contact filter: `CustomFilter` with `filter_type: contact` (db/schema.rb:1105).
There is **no audience table and no static membership table (V)** — 108 tables, none named
audiences/audience_members/audience_contacts/segments. Membership is always re-evaluated by running the saved
`query.payload` through `Contacts::FilterService` + the prepended `Custom::Contacts::FilterService`.

"Shared" is one boolean column, `custom_filters.shared` (added by
custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb), which flips a record from personal to
account-owned. `Custom::CustomFilter` adds `scope :visible_to`, makes `user` optional when shared, forbids sharing
conversation folders, and adds `#members`.

Only shared audiences are referenceable elsewhere: campaigns via `{type: 'Audience', id:}` entries in
`campaigns.audience` (custom/app/models/custom/campaign_audience.rb:6-28), automation rules and flow condition nodes
via the `contact_audience` condition key. `Audience::Usage` is the single dependency guard and it knows only about
automation rules and one-off campaigns in `active`/`processing` — **it does not look at flow graphs.**

Counts and previews are pure Postgres; no provider call is ever made for a count or preview.

The UX is the weak part and the reason this is EXTEND rather than REUSE: **there is no Audience list page at all** —
only a sidebar group that renders shared audiences as saved views (Sidebar.vue:556). The only way to create one is to
apply a contact filter and press an icon-only save button; the "shared" checkbox exists only at creation time and only
for administrators; and navigating to Contacts to create one destroys the campaign draft you were building.

### 4.10 Contacts — **PATCH**

Bulk actions over all filtered results **are** implemented end to end, so prior docs calling this a gap are stale.
`Contacts::ViewScope` (app/services/contacts/view_scope.rb:16-68) resolves a view from `{q, active, payload,
label|labels}`; `BulkActionsController` opts in on `all_matching`, plucks ids with a hard 10,000 bound, and hands them
to the untouched `Contacts::BulkActionJob`
(app/controllers/api/v1/accounts/bulk_actions_controller.rb:10,51-75,107-114). The client builds the same view
description branch-for-branch (ContactsIndex.vue:352-370).

The bulk vocabulary is exactly three operations — add labels, remove labels, delete
(app/services/contacts/bulk_action_service.rb:42-48). No bulk block, merge, company, campaign or audience.

**"Add selected contacts to a shared audience" is architecturally impossible as a direct write.** A shared audience's
only stored state is a `query` jsonb and membership is recomputed every time
(custom/app/models/custom/custom_filter.rb:12-16); there is no membership table and no `id` filter key for contacts
(lib/filters/filter_keys.yml:130-211), so an unknown key raises `InvalidAttribute`
(app/helpers/filters/filter_helper.rb:22-25). **(V)** `"id in (a set)"` is not expressible as a contact filter and is
not a safe option. The only persistent grouping of an arbitrary contact set is a **label**
(acts-as-taggable-on `taggings`, db/schema.rb:1644-1668), plus `contacts.company_id` (one company per contact,
feature-flagged).

Two live defects in the just-shipped Phase D work: see §6 items 3 and 4.

### 4.11 Campaigns — **REUSE**

`campaigns.audience` is a jsonb **list of `{type, id}` references**, not a membership list. `campaign_recipients` is a
**send log created during the send**, not a membership list **(V)**. Resolution happens at send time:
`Custom::CampaignAudience#audience_contacts` finds the shared audiences, maps `&:members`, unions them with the label
branch, and de-duplicates (custom/app/models/custom/campaign_audience.rb:12-20). Audience entries are validated to
one-off campaigns owned by the same account (`:23-28`). `campaign_type` is `{ ongoing: 0, one_off: 1 }`
(app/models/campaign.rb:50) — there is no third type.

### 4.12 Help Center — **EXTEND**

Upstream Portal → Category → Article, account-scoped at the DB level, with an EE overlay for AI (translation,
embeddings/vector search, onboarding article generation, Captain copilot tools) and **zero `custom/` Help Center
files**. Six EE files the first pass missed **(V)**:
`enterprise/app/services/onboarding/{help_center_creation_service,help_center_curator,help_center_errors,help_center_generation_state}.rb`
and `enterprise/app/services/captain/llm/{help_center_curation_service,help_center_curation_schema}.rb`.

Articles have a 3-state status enum, a `meta` jsonb for SEO, 10-step `position` ordering, `locale`, `author_id`, a
globally-unique `slug`, and a **single-slot** draft buffer (`draft_title`/`draft_content`) that powers autosave and a
live-vs-draft diff. There is **no revision history**: Article is not among the 12 audited models
(`ls enterprise/app/models/enterprise/audit/`).

Two corrections that change the recommendation:

- **The enabling guard was mischaracterised (V).** `DomainHelper.chatwoot_domain?` does **not** test for a Chatwoot
  domain — it compares the request host against the hosts of `ENV['FRONTEND_URL']` and `ENV['HELPCENTER_URL']`
  (app/controllers/concerns/domain_helper.rb:2-4). A branded Lynomia install is therefore **not** blocked from
  `/hc/<slug>`.
- **Unflagged risk (V):** portal slugs are a single **global, first-come-first-served namespace with no reservation**.
  app/models/portal.rb:44 is a bare `validates :slug, presence: true, uniqueness: true`. There is no Portal
  `RESERVED_SLUGS` — the only one is Article's (app/models/article.rb:61, `%w[search articles categories]`). **Tenant
  onboarding can squat the docs slug.**

Portal *is* hard-scoped to an account (`portals.account_id` NOT NULL, db/schema.rb:1539-), so there is no global
portal — but the entire public read path resolves a portal by globally-unique slug or unique custom domain with **no
account in the URL**, so one portal owned by an internal Lynomia account can already serve global product docs.

**Revision history needs no migration (V):** the generic polymorphic `audits` table already exists with
`auditable_type`/`auditable_id`/`version`/`audited_changes` (db/schema.rb:264-288). Adding `audited` to Article is a
model change only.

Two public endpoints have no custom-domain guard **(V)**: `portals#sitemap` and `articles#tracking_pixel`.

No in-product changelog: the sidebar changelog pulls a hardcoded external feed (`hub.2.chatwoot.com/changelogs`), and
the only in-product global broadcast primitive is the account-less `PlatformBanner`.

### 4.13 Super Admin — **EXTEND**

thoughtbot `administrate` 0.20.1. 8 dashboards in `app/dashboards/` + 2 billing dashboards in
`custom/app/dashboards/`; custom field types in `app/fields/` (7), `enterprise/app/fields/` (4), `custom/app/fields/`
(2). Adding a resource = declare it under `namespace :super_admin` in routes + an `Administrate::BaseDashboard`
subclass + an optional controller; the sidebar auto-derives from `Administrate::Namespace` with a hardcoded skip list
and icon map. `devise_for :super_admins` is config/routes.rb:726; `draw :billing` is config/routes.rb:782.

Manages Accounts, Users, AccountUsers, AccessTokens, InstallationConfigs, AgentBots, PlatformApps, PlatformBanners,
BillingPlans, BillingSubscriptions. **Cannot see or manage Portals, Categories or Articles at all.**

### 4.14 Permissions and tenancy — **REUSE**

Pundit with a **hash** user_context (`{user, account, account_user}`) assembled in
`ApplicationController#pundit_user` from the thread-local `Current` (lib/current.rb). Tenancy is enforced **once**, at
`Api::V1::Accounts::BaseController` via `EnsureCurrentAccountHelper`: load account, reject suspended, find the caller's
`AccountUser` or 401, set `Current.account` / `Current.account_user`. Everything downstream scopes through
`Current.account.<association>`.

The base role is a two-value enum (agent/administrator) on `account_users`. Custom roles are EE-only, add 7 named
permissions, and **replace rather than extend** the base role in `AccountUser#permissions` — so a custom-role user is
neither `'agent'` nor `'administrator'` for route gating. This is the single most common authorization surprise in the
codebase and any new settings page must be tested with a custom-role user.

Four independent gating layers: 72 account bitset flags (`Featurable`), the 9-entry EE premium list, installation-wide
GlobalConfig/ENV switches (`Commerce::Providers`, `Commerce::Switches`, `Shopify::FeatureGate`), and a Lynomia
billing-plan layer (`BillingPlan.assignable_features` + `Billing::FeatureSync`) that can never grant premium or system
flags. The frontend gate is one composable — `usePolicy().shouldShow(featureFlag, permissions, installationTypes)` —
consumed by route `meta`, `<Policy>`, the sidebar provider and the command bar. **A new settings page is authorized by
adding route meta plus a server policy, and nothing else.**

### 4.15 Telemetry — **PATCH**

Amplitude only. `useTrack` is a 9-line try/catch wrapper (app/javascript/dashboard/composables/index.js:7) around a
singleton built from `window.analyticsConfig`, which the layout emits **only** when the `CLOUD_ANALYTICS_TOKEN`
InstallationConfig is present (app/views/layouts/vueapp.html.erb:68-74). That row ships blank
(config/installation_config.yml:299-303), is typed `secret` — so it is excluded from Super Admin's InstallationConfig
list — and the App Config section that holds it is unreachable while `ChatwootHub.pricing_plan == 'community'`
(enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:16). `.env.example` has no analytics entry
at all.

Net: **there is no Super Admin UI path to turn telemetry on in a community install, and with no token all 72 non-spec
`useTrack` call sites are no-ops.** And there are **zero** telemetry calls on any recipe/starter/template path, so
"starter selected / completed / abandoned" cannot be answered today. That is an opportunity, not a capability.

### 4.16 Recipe catalogues — **EXTEND** (the contract itself: **NEW PRIMITIVE REQUIRED**)

Entirely client-side source code in one of the three trees: three static JS catalogues (22 recipes), a shared contract
module (app/javascript/dashboard/recipes/index.js), one availability composable
(app/javascript/dashboard/recipes/useRecipeContext.js), and one two-step dialog. `grep -i recipe` over `custom/app`,
`enterprise/app`, `app/models`, `app/services`, `app/controllers`, `app/jobs` and `lib` returns nothing: **no recipes
table, endpoint, model, service, job or seeder.**

A recipe is a manifest plus a pure `build(values)` returning **one payload for one object type**, which **one owning
page** then posts through the ordinary create API. The three owning pages each hardcode a different API call; there is
no dispatcher. Instantiated objects are fully independent and editable — flows are created as unpublished drafts
connected to no inbox, automation rules with `active: false`, audiences only after the user confirms a name.

Provenance is **informational text only**: the recipe name and version are interpolated into the `description` of
created flows and rules; audiences get no provenance at all. i18n is `RECIPES.<TYPE>.<ID_UPPER>.NAME/.DESCRIPTION` and
of the 57 locale directories only `en` and `ar` ship a `recipes.json`.

The architecture **cannot** express a multi-object kit, a macro starter, a non-flow bot starter or a WhatsApp-template
starter: `type` is a single scalar, `build` returns a single payload, the dialog emits a single create event, and the
input vocabulary (`INPUT_TYPES`, index.js:50-62) has no inbox, agent, free-text, boolean or template picker. Expanding
to kits is a contract change — a new primitive — not a new catalogue entry.

### 4.17 Branding and external links — **PATCH**

The white-label mechanism already exists and is already pointed at Lynomia: ten attributes in
`config/installation_config.yml:17-58` **(V, not :15-58)** flow InstallationConfig → GlobalConfig (Redis) →
`DashboardController::GLOBAL_CONFIG_KEYS` → `window.globalConfig` → `globalConfig.js` →
`useBranding().replaceInstallationName`, which regex-replaces `/chatwoot/gi`
(app/javascript/shared/composables/useBranding.js). Reach: 32 non-spec files, 83 occurrences, 42 real invocations
**(V)**. Logos, favicons, meta description, widget/survey/portal "Powered by" footers and email footers are
config-driven and need no code change.

Five findings dominate:

1. **The EE overlay reverts branding.** `enterprise/config/premium_installation_config.yml:1-22` still holds upstream
   Chatwoot values and `Internal::ReconcilePlanConfigService#reconcile_premium_config`
   (enterprise/app/services/internal/reconcile_plan_config_service.rb:38-46) **force-writes them back into the
   database** whenever `ChatwootHub.pricing_plan == 'community'` — the seeded default — driven daily via
   `Internal::TriggerDailyScheduledItemsJob` → `Enterprise::Internal::CheckNewVersionsJob`.
2. **And there is no UI to fix it:** `custom_branding` is gated behind `pricing_plan != 'community'` in both
   app/helpers/super_admin/features.yml:15 and
   enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:16.
3. **Coverage is per call site, not per i18n key (V).** `generalSettings.json:126`
   (`GENERAL_SETTINGS.UPDATE_CHATWOOT`) is wrapped at BuildInfo.vue:42 but **not** at UpdateBanner.vue:32.
4. **The inverse problem, missed entirely (V):** 34 hard-coded `'Lynomia'` literals in EN source strings
   (commerce.json 28, automation.json 2, contactFilters.json 1, config/locales/en.yml 3), plus config/features.yml:283,287
   and app/helpers/super_admin/features.yml:155,161,167,172, plus 17 `'Lynomia'` description lines in
   config/installation_config.yml:487-612. **None read from `INSTALLATION_NAME`.**
5. **Brand leaks to the model provider (V):** `lib/integrations/openai/openai_prompts/tone_rewrite.liquid:1` and
   `fix_spelling_grammar.liquid:1` both begin "You are an AI writing assistant integrated into Chatwoot, an omnichannel
   customer support platform" — sent on every AI-assist rewrite. `MAILER_SENDER_EMAIL` also defaults to Chatwoot at
   config/initializers/devise.rb:15 (governing every Devise email) and
   app/models/concerns/email_address_parseable.rb:13. And `BRAND_URL` reaches `window.globalConfig`
   (app/controllers/dashboard_controller.rb:12) but is **never destructured** in
   app/javascript/shared/store/globalConfig.js:4-30, so no SPA code can read it.

`chwt.app` is the single biggest blind spot a "grep for chatwoot" misses — it contains no "chatwoot" substring and
carries the in-product help links (28 in one hardcoded table at app/javascript/dashboard/helper/featureHelper.js:2-28,
14 more in config/features.yml). `hub.2.chatwoot.com` is a live outbound dependency for telemetry, instance
registration, push relay, the changelog feed and the billing link, overridable only in `Rails.env.development?`.
The `custom/` tree contains **zero** Chatwoot-owned URLs.

---

## 5. DEFINED_BUT_UNUSED register

Cheap wins and dead code. The reader needs to know which is which, so each row carries a verdict.

| # | Primitive | Tree | Citation | Verdict |
|---|---|---|---|---|
| 1 | `sla_policy_id` automation condition key | enterprise | enterprise/app/models/enterprise/automation_rule.rb:2-4 | **PATCH — broken if used.** No `filter_keys.yml` entry, no SQL branch, no UI; a rule using it auto-disables after 2 evaluations and emails admins. Remove from the attribute list or finish it. |
| 2 | `AUTOMATIONS[event].actions` per-event action lists | frontend | automation/constants.js:90-155, 232-289, 378-435, 518-571, 648-685 | **Dead data, and wrong.** Nothing reads it (`lynomiaAutomation.js:152` replaces whole entries with `{conditions: [...]}`); `assign_agent` is duplicated at :250/:396/:536 and `add_label`/`remove_label` are missing from every conversation event. Delete. |
| 3 | `automationHelper` `getInputType` / `getOperators` / `getCustomAttributeType` / `getAutomationType` | frontend | automationHelper.js:324-328, 338-350, 361-376, 385-389 | Dead exports — the live path is `useConditionFilterTypes.js`. Delete. |
| 4 | `AgentBot#bot_config` jsonb | app | app/models/agent_bot.rb:6; db/schema.rb:134; agent_bots_controller.rb:48; _agent_bot.json.jbuilder:7 | **Tempting trap.** Permitted free-form and echoed in JSON, but no schema, no validation, no production reader. Only non-spec readers are docs/flow-builder/uat/uat.rb. Do **not** build starter config on it. |
| 5 | `AgentBotInbox#inactive` enum value | app | app/models/agent_bot_inbox.rb | Never written anywhere in `app/`, `enterprise/` or `custom/`. Either a free "pause this bot" affordance or dead code. |
| 6 | `Flows::NodeTypes.terminal?` | custom | custom/app/services/flows/node_types.rb:49 | No caller anywhere, specs included. Harmless; use it or drop it. |
| 7 | `Commerce::Providers::Base#supports_realtime?` | custom | overridden by all four providers, read nowhere | Dead predicate. Resolve before anyone reasons about it as a capability. |
| 8 | `Whatsapp::Providers::WhatsappCloudService#create_csat_template` / `#delete_csat_template` | app | app/services/whatsapp/providers/whatsapp_cloud_service.rb:82-89 | No caller — `CsatTemplateManagementService` instantiates `Whatsapp::CsatTemplateService` directly. (`#get_template_status` **is** used, from app/services/csat_survey_service.rb:83.) Dead code. |
| 9 | `folders` table + `Folder` model | app | db/schema.rb:1271-1277; app/models/folder.rb:12 | Referenced only by the model and `articles.folder_id`. No controller, route, policy, serializer or UI. **Cheap win:** an existing article-grouping column nobody exposed. |
| 10 | `portals_members` join table | app | db/schema.rb:1559-1565 | `portal_id` + `user_id` with a unique index, **no model and no association**. Orphaned. |
| 11 | `SuperAdmin::ResponsesController` / `SuperAdmin::ResponseDocumentsController` / `SuperAdmin::EnterpriseBaseController` | enterprise | enterprise/app/controllers/super_admin/{responses_controller,response_documents_controller,enterprise_base_controller}.rb:1 | Administrate boilerplate with no route and no dashboard class. Dead code. |
| 12 | `DOCS_URL` | app | app/javascript/dashboard/constants/globals.js:41 | `rg '\bDOCS_URL\b' app enterprise custom` returns only the definition. Dead, and points at chatwoot.com. Delete. |
| 13 | `config/features.yml` `help_url` (14 `chwt.app` URLs) | app | config/features.yml:23,27,45,49,59,66,70,77,81,94,98,134,278 → application_helper.rb:6-9 → vueapp.html.erb:58 as `window.chatwootConfig.helpUrls` | **Nothing in the frontend reads `helpUrls`** (zero hits). They are still emitted into every dashboard page's HTML source. A duplication defect too — the live links come from the parallel hardcoded `featureHelper.js` table. |
| 14 | Dead i18n key carrying Chatwoot branding | frontend | app/javascript/dashboard/i18n/locale/en/integrations.json:20 (`INTEGRATION_SETTINGS.SHOPIFY.HELP_TEXT.BODY`) | No renderer. Delete. |
| 15 | `CLOUD_ANALYTICS_TOKEN` plumbing | app | vueapp.html.erb:68-74; dashboard_controller.rb:20; config/installation_config.yml:299-303 | Fully built, structurally unreachable on a community install (§4.15). **The cheapest high-value win in this register.** |
| 16 | `rejected_reason` | spec-only | spec/factories/channel/channel_whatsapp.rb:15,24,33,84 **(V)** | Appears in factories with **no production reader**. Do not cite it as a capability. |
| 17 | Flow discovery/E2E harnesses | mixed | docs/flow-builder/{e2e,uat,rollback}, docs/usability/e2e | Not wired into CI. `rollback/detach_new.rb` is the documented kill switch (sets `LYNOMIA_FLOW_BUILDER_ENABLED=false`). Keep, but do not mistake for test coverage. |

---

## 6. Live defects

Three verified defects. A fourth — the CSAT 30-day block — was asserted in the corrections file and is **withdrawn**:
see §6.1. Items 2 and 3 were verified personally against commits that claim they were fixed.

1. **WITHDRAWN — the CSAT path does *not* collide with Meta's 30-day same-name block.** The corrections file
   asserted it did, and this document repeated it. Re-checked directly:
   `app/services/whatsapp/csat_template_service.rb:52-55` calls
   `CsatTemplateNameService.generate_next_template_name`, which mints
   `customer_satisfaction_survey_<inbox_id>_<n+1>` (`app/services/csat_template_name_service.rb:19-25`) rather than
   reusing the old name. Meta's block is therefore avoided **by design**. `04` §5.2, `05` §3.3 and `12` D4 had this
   right. The only residual note is a constraint on future work: **do not "simplify" that service by reusing the
   template name** — the versioned suffix is load-bearing. **NOT A DEFECT.**
2. **Header variable examples are mis-read (V).** `TemplateNormalizer.extractWhatsAppVariables` reads
   `example.body_text_named_params` (app/javascript/dashboard/services/TemplateNormalizer.js:75) and
   `example.body_text[0][pos]` (:81) for **both** branches, but Meta's TEXT header uses
   `header_text_named_params` / `header_text`. **PATCH.**
3. **Contact export still ignores the current view.** `app/javascript/dashboard/store/modules/contacts/actions.js:202`
   destructures only `{ payload, label }` and forwards only those to `ContactAPI.exportContacts`. The D4 fix made the
   dialog emit `q`/`active` and the controller and job honour them, but the Vuex action in between **drops them**.
   Exporting from a search or the online list still exports the whole account. **The commit claiming this was fixed is
   wrong. PATCH.**
4. **"Select all N in this view" is unreachable on a search view.**
   `app/controllers/api/v1/accounts/contacts_controller.rb:183` sets `@contacts_count = results.size` (page size, max
   15) on the search path, so `totalItems <= 15` and `ContactsBulkActionBar`'s `canSelectAllMatching`
   (`totalCount > visible`) can never be true. **PATCH.**

Plus the **daily EE branding revert** (§4.17 item 1), which `07` §3 and `12` P0 both rank as the single
highest-value fix in the program — it is a live defect, not merely a risk, and this document previously demoted it
in error. And one standing risk that is not a bug but will become an incident: the global unreserved portal slug
namespace (§4.12).

---

## 7. Do not repeat

`quality_score` **does not appear anywhere in this repository.** An earlier inventory cited it as a readable Meta
template field present in the code; `grep -rni quality_score app enterprise custom lib spec config db` returns zero
hits. Meta's `message_template_quality_update` webhook does carry quality scores, but nothing here subscribes to it,
handles it or could route it. Any document, ticket or roadmap line that cites `quality_score` as an existing Lynomia
capability is citing a fabrication.

---

## 8. The primary product problem, restated in terms of this map

The map shows a platform with **21 flow node types, 12 automation triggers, 20 automation actions, 16 macro actions,
4 commerce providers and 108 tables of working machinery — and no guided entry into any of it.**

Concretely, the gap is not capability, it is the first ten minutes:

- The **only** path to a shared audience is: apply a contact filter, then press an icon-only save button, then tick a
  checkbox that only administrators see and that only exists at creation time. There is no Audience page (§4.9).
- The **only** path to a flow bot is through Flow Builder; the Agent Bots settings page deliberately hides flow bots
  and will not create one (§4.3).
- A flow is useful only after four objects exist — bot, draft, **published version**, inbox attachment — and nothing in
  the product says so (§4.3).
- The 22 starters that were meant to close this are frontend constants with no server, no provenance beyond a sentence
  interpolated into a `description`, and **zero telemetry** (§4.16, §4.15). We cannot measure whether guided entry
  works because we never instrumented it, and on a community install we **could not** instrument it even if we wanted
  to (§4.15).
- Where the product does offer a guided promise, the substrate sometimes cannot keep it: a commerce automation
  "fires automatically" only when an agent happens to open the conversation panel (§4.6); an abandoned-cart starter
  cannot exist at all (§4.7); and in a default production install every order action and every recovery feature is
  switched hard off (§1).

So the build decision this map supports is narrow and high-leverage: **REUSE the engines as they are, EXTEND the recipe
layer into a real guided-entry surface (which needs a contract change — a new primitive — not more catalogue entries),
PATCH the three live defects plus the branding revert, and turn telemetry on, and DO NOT CREATE either an abandoned-cart recipe or a
"Conversation Workflow" engine.** The two migrations this would eventually require — a cart table with a cart
transition engine, and a portal slug reservation — are stated here as requirements and left for approval.
