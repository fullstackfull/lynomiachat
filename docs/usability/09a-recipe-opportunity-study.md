# Recipe opportunity study

Written **before** any recipe was implemented. The brief's example catalogue is treated as inspiration; what gets
built is derived from what this repository can actually do today.

## 1. Existing engines and capabilities (all verified in code)

### 1.1 Flow nodes — `custom/app/services/flows/node_types.rb`

`start`, `send_message`, `send_template`, `question`, `buttons`, `list`, `condition`, `audience_condition`,
`commerce_condition`, `set_contact_attribute`, `set_conversation_attribute`, `add_label`, `remove_label`,
`assign_agent`, `assign_team`, `commerce_lookup`, `webhook`, `delay`, `handoff`, `goto`, `end`. **21 types, no more.**

Channel limits actually enforced (`Flows::ChannelCapabilities::WHATSAPP`): buttons ≤ 3, button title ≤ 20 chars;
list ≤ 10 rows, row title ≤ 24, row description ≤ 72, list button ≤ 20; interactive body ≤ 1024; text ≤ 4096.
Flows run on **WhatsApp Cloud inboxes only** (`provider == 'whatsapp_cloud'`), which covers both WhatsApp API and
WhatsApp Business coexistence numbers.

Variables a template may use in message text (`Flows::Variables::SUGGESTED`): `contact.*`,
`conversation.display_id`, `inbox.name`, `account.name`, `flow.reply`, and after a lookup
`flow.order.number | status | payment_status | tracking_number | tracking_url`.

Per-node requirements that constrain templates (`Flows::NodeValidator`):

| Node | Hard requirement |
|---|---|
| `add_label` / `remove_label` | every label **must already exist** in the account (`unknown_label`) |
| `assign_team` | `team_id` required and must be the account's |
| `assign_agent` | `agent_id` required and must be the account's |
| `commerce_lookup`, `commerce_condition` | account feature `lynomia_commerce`; `mode` ∈ `latest_order`, `order_number` |
| `audience_condition` | conditions limited to `contact_audience`, i.e. **shared** audiences only |
| `set_contact_attribute` / `set_conversation_attribute` | the custom attribute definition must already exist |
| `question` with `store_as.scope: contact|conversation` | same — the definition must exist. `scope: context` needs nothing |
| `webhook` | `account.api_and_webhooks_enabled?` and an http(s) URL |
| `send_template` | an approved template on the connected inbox (`Flows::TemplateValidator`) |

### 1.2 Automation — `app/javascript/.../automation/constants.js`, `custom/app/services/automation/`

Triggers: Chatwoot's own (`conversation_created`, `conversation_updated`, `message_created`, …) **plus the seven
Lynomia Commerce triggers** `commerce_order_created | updated | paid | shipped | delivered | cancelled | refunded`
(`Commerce::OrderTransitions::EVENTS` — verified, not assumed).

Conditions: Chatwoot's, plus `contact_audience` (is in / is not in, **shared audiences only**), the Commerce contact
fields, and on Commerce triggers `commerce_event_store` / `commerce_event_provider`.

Actions: `assign_agent`, `assign_team`, `remove_assigned_agent`, `remove_assigned_team`, `add_label`,
`remove_label`, `send_email_to_team`, `send_email_transcript`, `mute_conversation`, `snooze_conversation`,
`resolve_conversation`, `open_conversation`, `pending_conversation`, `send_webhook_event`, `send_attachment`,
`send_message`, `add_private_note`, `change_priority`.

Constraint that kills one of the brief's examples: `CUSTOMER_MESSAGE_ACTIONS = ['send_message', 'send_attachment']`
are **not offered on Commerce triggers**. So "order shipped → message the customer" **cannot** be built as an
automation recipe. The brief anticipated this ("Do not auto-send a customer message unless current WhatsApp
compliance safely supports the exact configuration") — and the engine enforces it.

Param shapes (verified in `ActionService`): `add_label` takes label **titles**; `assign_team` takes `[team_id]`;
`change_priority` takes `[priority]`.

### 1.3 Audience — `custom/app/services/audience/commerce_condition.rb`

Commerce fields and their operators:

| Field | Operators |
|---|---|
| `commerce_store` | equal_to, not_equal_to, is_present, is_not_present |
| `commerce_provider` | equal_to, not_equal_to |
| `commerce_orders_count` | equal_to, is_greater_than, is_less_than |
| `commerce_spend_<ccy>` | is_greater_than, is_less_than |
| `commerce_last_purchase_at` | is_greater_than, is_less_than, days_before |
| `commerce_active_order` | equal_to |
| `commerce_order_status` | equal_to, not_equal_to |
| `commerce_payment_status` | equal_to, not_equal_to |
| `commerce_shipment_status` | equal_to, not_equal_to |

Plus the conversation fields (`conversation_status`, `_priority`, `_inbox`, `_assignee`, `_team`, `_labels`) and all
of Chatwoot's contact fields. Spend is **per currency, never converted** — a preset must therefore always ask for a
currency, never assume one.

Semantics that a preset must respect (documented in the service): "can only grow with more data" operators
(`is_greater_than`, `days_before`, has-an-order-with) are true as soon as known summaries prove it; "could change with
more data" operators (`is_less_than`, `equal_to`, before) match only when **every** counted link of the contact has
been read. A preset built on the second kind is correct but narrower — this is called out per preset below.

## 2. Account configuration signals available with no new API

| Signal | Source already loaded by the dashboard |
|---|---|
| Commerce enabled for the account | `FEATURE_FLAGS.LYNOMIA_COMMERCE` via `isCloudFeatureEnabled` |
| Flow Builder enabled | `FEATURE_FLAGS.LYNOMIA_FLOW_BUILDER` |
| Connected stores, their providers, and the currencies actually seen | `GET /commerce/audience_fields` (`stores`, `currencies`, `unread_contacts`) — already fetched by `audienceProvider.js`, and already filtered to `Commerce::Providers.enabled`, so a production-gated provider cannot appear |
| WhatsApp Cloud inboxes | `inboxes/getWhatsAppInboxes`, already in the store |
| Teams | `teams/getTeams` |
| Labels | `labels/getLabels` |
| Shared audiences | `customViews/getContactCustomViews` filtered by `.shared` |
| Webhooks allowed | `FEATURE_FLAGS.API_AND_WEBHOOKS` on the account (the same flag `Account#api_and_webhooks_enabled?` reads server-side) |

**Every availability decision is therefore deterministic, local, and free of extra requests. No LLM, nothing sent
anywhere.**

## 3. Most likely workflows for this product (hypotheses, from structure)

Ranked by how much of the platform already exists to serve them:

1. **"Where is my order?"** — the single question a WhatsApp + Commerce account receives most. Fully supported:
   `commerce_lookup` + `flow.order.*` + handoff.
2. **Route to the right department** — supported: `buttons`/`list` + `assign_team` + `handoff`.
3. **Treat good customers differently** — supported: shared audience + `audience_condition` (flow) or
   `contact_audience` (rule) + priority/team.
4. **After-sales intake** (wrong / damaged / late item) — supported: `question` + `commerce_lookup` + label + team.
5. **Operational tagging of order events** — supported: Commerce triggers + `add_label` / `change_priority`.
6. **Notify an external system** — supported: `send_webhook_event` with the existing safe client.
7. **First-contact greeting for accounts with no Commerce** — supported with messages + buttons + handoff only.
8. **Bilingual (ar/en) entry** — supported, as a deterministic language choice. **Not** language detection.

Not supported, therefore no recipe: proactive shipping notifications to customers (blocked by
`CUSTOMER_MESSAGE_ACTIONS` on Commerce triggers, and by the 24-hour window for free-form WhatsApp); anything needing
stock, prices, carts-as-trigger, or an AI step.

## 4. Candidate catalogue

Confidence is **High** only when every primitive exists *and* the recipe needs no setup the wizard cannot ask for.

### 4.1 Flow templates

| id | Name | Problem | Reuses | Requires | Inputs | Primitives exist? | Setup steps saved | Conf | Risk | Decision |
|---|---|---|---|---|---|---|---|---|---|---|
| `whatsapp_welcome_menu` | Welcome & menu bot | first reply out of hours / triage | buttons, send_message, assign_team, handoff, end | Flow Builder | team, language | yes | ~8 nodes, 9 edges | **High** | Low | **implement** |
| `commerce_order_tracking` | Order tracking bot | "where is my order?" without an agent | buttons, commerce_lookup ×2, question, send_message, assign_team, handoff, end | Flow Builder + **Commerce** | team, language | yes | ~14 nodes, 17 edges | **High** | Low | **implement** |
| `support_department_routing` | Department routing bot | route to the right team first time | buttons, assign_team ×3, handoff | Flow Builder + **≥2 teams** | 3 teams, language | yes | ~11 nodes, 11 edges | **High** | Low | **implement** |
| `vip_priority_routing` | VIP priority routing | known-good customers skip the queue | audience_condition, assign_team, handoff(priority) | Flow Builder + **≥1 shared audience** | audience, VIP team, standard team, language | yes | ~8 nodes, 8 edges | **High** | Low | **implement** |
| `bilingual_welcome` | Arabic / English entry | serve both languages without guessing | buttons, send_message, assign_team, handoff | Flow Builder + **≥1 team** | Arabic team, English team | yes | ~8 nodes, 8 edges | **High** | Low | **implement** |
| `commerce_after_sales` | Order issue intake | collect order + issue type before a human reads it | question, commerce_lookup, buttons, add_label, assign_team, handoff | Flow Builder + **Commerce** + **≥1 label** | team, 1–3 labels, language | yes | ~12 nodes, 13 edges | **High** | Low | **implement** |
| `contact_info_collection` | Collect name / email into attributes | enrich the contact | question + set_contact_attribute | Flow Builder + **existing contact custom attribute definitions** | which attributes | yes, **but** | ~7 nodes | **Medium** | Medium | **document only** — the wizard would have to let the user map an arbitrary number of attributes with their own types, and `AttributeValue.cast` must accept the answer. That is a form builder, not a starter kit. Rejected on complexity, not capability |
| `whatsapp_template_outreach` | Start with an approved template | reach customers outside the 24h window | send_template | approved template on the inbox | template, language | yes, **but** | small | **Low** | High | **document only** — a template's name, language and parameter list are entirely account-specific, so the recipe would prefill nothing while creating a path to sending approved templates from a starter button |

### 4.2 Automation recipes

All created **disabled**.

| id | Name | Trigger → actions | Requires | Inputs | Conf | Decision |
|---|---|---|---|---|---|---|
| `commerce_new_order_routing` | New order → customer care | `commerce_order_created` → add_label, assign_team | Commerce | team, label? | **High** | **implement** |
| `commerce_order_shipped_label` | Order shipped → label | `commerce_order_shipped` → add_label | Commerce + ≥1 label | label | **High** | **implement** |
| `commerce_refund_escalation` | Refund → escalate | `commerce_order_refunded` → change_priority(high), assign_team, add_label? | Commerce | team, label? | **High** | **implement** |
| `vip_audience_priority` | VIP conversation priority | `conversation_created` IF `contact_audience` is in X → change_priority, assign_team, add_label? | ≥1 shared audience | audience, team, priority, label? | **High** | **implement** |
| `high_value_spend_routing` | High-value customer routing | `conversation_created` IF `commerce_spend_<ccy>` > N → add_label, assign_team | Commerce + ≥1 currency seen | currency, threshold, team, label? | **High** | **implement** |
| `active_order_routing` | Customer with an open order | `conversation_created` IF `commerce_active_order` = true → assign_team, add_label? | Commerce | team, label? | **High** | **implement** |
| `commerce_event_webhook` | Order event → external system | chosen Commerce event → send_webhook_event | Commerce + `api_and_webhooks` | event, url | **High** | **implement** |
| ~~order shipped → message the customer~~ | — | — | — | — | — | **impossible** — `send_message` is withheld on Commerce triggers by design. Recorded, not built |
| ~~"order issue" trigger~~ | — | — | — | — | — | **no such trigger.** The seven events are the whole set; there is no normalized "issue" event. Recorded, not built |

### 4.3 Audience presets

Dynamic shared audiences. All of them need Commerce, which is honest: without a store there is nothing in a contact
filter that a preset knows better than the user.

| id | Name | Condition | Inputs | Semantics note | Conf | Decision |
|---|---|---|---|---|---|---|
| `high_value_buyers` | High-value buyers | `commerce_spend_<ccy>` is_greater_than N | **currency, amount** | grows with data — matches as soon as proven | **High** | **implement** |
| `repeat_buyers` | Repeat buyers | `commerce_orders_count` is_greater_than N (default 1) | count | grows with data | **High** | **implement** |
| `recent_buyers` | Recent buyers | `commerce_last_purchase_at` days_before N (default 30) | days | grows with data | **High** | **implement** |
| `customers_with_active_order` | Customers with an open order | `commerce_active_order` equal_to true | — | needs every counted link read; narrower by design | **High** | **implement** |
| `customers_with_shipped_order` | Customers with a shipped order | `commerce_order_status` equal_to `shipped` | — | grows with data. Uses the **order** status, not the shipment status: the normalized shipment statuses are `pending`, `in_transit`, `out_for_delivery`, `delivered`, `failed`, `cancelled`, `returned`, `other` — there is no `shipped` among them | **High** | **implement** |
| `store_customers` | Customers of one store | `commerce_store` equal_to \<store\> | **store** (from the account's connected stores) | fact about links | **High** | **implement** |
| `linked_commerce_customers` | All linked customers | `commerce_store` is_present | — | fact about links | **High** | **implement** |
| ~~"WooCommerce customers", "Salla customers", "Zid customers", "Shopify customers"~~ | — | `commerce_provider` equal_to … | — | — | — | **replaced by `store_customers`.** Four hardcoded provider presets would list providers the installation has switched off or the account has never connected. One store-picker preset is correct by construction, and the picker is fed by `audience_fields`, which already filters to `Commerce::Providers.enabled` |
| ~~"VIP customers" as spend > 1000~~ | — | — | — | — | — | **refused as written.** §10 of the brief is right: VIP is not a number we may choose. `high_value_buyers` asks for the currency and the threshold and names itself after what it measures, not after a business judgement |

## 5. What will actually be implemented

**6 flow templates, 7 automation recipes, 7 audience presets** — the rows marked *implement* above.

## 6. Campaign starters — deferred, with the reason

The Campaign + shared-audience integration **is** complete in this repository (verified: `Custom::CampaignAudience`,
`campaigns/audience_previews_controller.rb`, `CampaignRecipients.vue`), so §11 of the brief permits campaign
starters. They are still deferred, on value:

A WhatsApp campaign needs a title, an inbox, an **approved template with its parameters filled**, a schedule and
recipients. Every one of those is account-specific and four of the five are things a starter cannot guess. A
"VIP Announcement" starter would prefill the audience — which is exactly what **P0-6 "Use in Campaign"** already does,
in one click, from the audience you are looking at. Building a second path to the same prefill would add a catalogue
entry and remove no step.

Recorded as [03](03-prioritized-improvements.md) P2-5.

## 7. Changes from the brief's example catalogue

| Brief's example | Outcome |
|---|---|
| FLOW 1 E-commerce order tracking | **implemented** as `commerce_order_tracking`, with the brief's structure (buttons → lookup → ask number → lookup → handoff) |
| FLOW 2 Customer care routing | **implemented** as `support_department_routing` |
| FLOW 3 E-commerce customer service | **merged** into `commerce_after_sales` — overlapped FLOW 1 on "Track order"; kept the part FLOW 1 lacks (issue intake) |
| FLOW 4 VIP routing | **implemented** as `vip_priority_routing` |
| FLOW 5 Basic WhatsApp welcome | **implemented** as `whatsapp_welcome_menu` |
| FLOW 6 Arabic / English welcome | **implemented** as `bilingual_welcome` |
| FLOW 7 Contact information collection | **rejected** (complexity — see §4.1) |
| AUTOMATION 1 New order → customer care | **implemented** |
| AUTOMATION 2 Order shipped | **implemented** as label-only; the optional customer message is impossible by engine design, the optional webhook is its own recipe |
| AUTOMATION 3 VIP priority | **implemented** |
| AUTOMATION 4 High-value customer | **implemented**, asking for currency + threshold as §10 requires |
| AUTOMATION 5 Commerce order issue routing | **replaced** by `commerce_refund_escalation` + `active_order_routing` — there is no "issue" trigger, so the recipe uses the events that do exist |
| AUTOMATION 6 External webhook | **implemented** |
| AUDIENCE presets | **implemented**, with provider presets collapsed into one store picker and "VIP" renamed to what it measures |
| CAMPAIGN starters | **deferred** — §6 |

## 8. One deliberate deviation from the brief's example wizard: no inbox input

§4 of the brief sketches a wizard that asks for a **WhatsApp Inbox**. The recipe wizards implemented here do **not**,
and the reason is a safety finding rather than a shortcut:

- Connecting a flow to an inbox is `POST /inboxes/:id/set_agent_bot`, which **replaces** whatever bot that inbox
  already has. An inbox can hold exactly one `agent_bot_inbox`. A wizard that connected an inbox as a side effect of
  "create a draft from a template" could silently detach a live flow or a working webhook bot.
- It would also be pointless before publishing: `Flows::Runner#start` refuses with `no_published_version` when the bot
  has no published version, so a connected-but-unpublished flow starts no sessions — it only enqueues `Flows::RunJob`
  runs that immediately bail.
- The builder the user lands in already has the inbox selector in its header, shows which inboxes are connected, and
  lets them be disconnected. It is one click, in the place where the consequence is visible.

So the inbox stays an explicit act in the builder. Store, team, audience, label, currency and threshold — the inputs
a template cannot work without — are what the wizards ask for.
