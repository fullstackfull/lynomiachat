# Lynomia Audience: reuse map

Decision, from [00](00-existing-system-discovery.md): **an Audience is a Chatwoot contact segment** (a saved, dynamic
contact filter). Lynomia extends the segment engine, its condition format, its operators, its API and its UI. It adds
condition fields, and one small Commerce projection because order figures are not in Postgres today.

## Existing system to extend

| Layer | Extended | How |
|---|---|---|
| Filter engine | `Contacts::FilterService` | `prepend_mod_with('Contacts::FilterService')` → `Custom::Contacts::FilterService`: conditions whose key is an Audience field are built there; every other key goes to the unchanged engine |
| Condition format | `{ attribute_key, filter_operator, values, query_operator }` | unchanged; new keys only |
| Operators | `equal_to`, `not_equal_to`, `is_present`, `is_not_present`, `is_greater_than`, `is_less_than`, `days_before` | reused as they are; no new operator |
| Saved audiences | `CustomFilter` (`filter_type: contact`) via `CustomFiltersController` | unchanged storage and API; labelled "Audiences" in the product |
| Filter API | `POST /contacts/filter` | unchanged; accepts the new keys |
| UI | `ContactsFilter.vue`, `ConditionRow.vue`, `contactProvider.js`, `groupFilterTypes` | new attribute groups (Conversation, Commerce) in the same picker |
| Permissions | `ContactPolicy#filter?`, `CustomFilterPolicy`, `Conversations::PermissionFilterService` | reused; conversation conditions only see conversations the user may see |
| Commerce data | `Commerce::Cache.fetch(store, :orders, …)` read paths | each read also refreshes one projection row (below) |

## Reuse matrix

| Capability | Existing? | Location | Classification | What Lynomia does |
|---|---|---|---|---|
| Contact filter engine | yes | `Contacts::FilterService`, `FilterService`, `Filters::FilterHelper` | **EXTEND EXISTING** | adds Conversation and Commerce condition builders through a prepended module |
| Saved segments | yes | `CustomFilter` / `custom_filters`, `CustomFiltersController` | **READY TO REUSE** | an Audience is a contact `CustomFilter`; no new table, no new API |
| Filter UI | yes | `components-next/filter/*`, `ContactListHeaderWrapper.vue` | **EXTEND EXISTING** | two attribute groups; product label "Audiences" |
| Operators | yes | `FilterService#filter_operation`, `operators.js` | **READY TO REUSE** | the same operator names and UI operator sets |
| Contact attributes | yes | `filter_keys.yml` `contacts:` + custom attributes | **READY TO REUSE** | untouched |
| Labels | yes | `taggings` via `tag_filter_query` | **READY TO REUSE** | contact labels as is; conversation labels as a conversation condition |
| AND / OR | flat chain | `query_operator` per condition | **READY TO REUSE** | kept flat; OR within a field through multiple values; no groups (documented in 02) |
| Campaign recipients | labels only | `Campaign.audience`, one-off services, `campaign_recipients` | **NOT PRESENT** (segment source) | not changed; minimum integration documented in 06 |
| Automation conditions | yes, one conversation | `AutomationRules::ConditionsFilterService` | **DO NOT USE** (this phase) | untouched; Audience keys deliberately kept out of `filter_keys.yml` so automation cannot accept them yet (06) |
| Captain audience | yes, in memory | `Captain::AudienceMatcher` | **DO NOT USE** | a per-conversation matcher for an AI assistant, not a segmentation engine |
| Pagination | yes | `ContactsController#fetch_contacts` (15 per page) | **READY TO REUSE** | preview is the first page; never all contacts |
| Count | yes | `meta.count` → "Showing … of N contacts" | **READY TO REUSE** | the matching-contacts preview |
| Account scoping | yes | `Current.account.contacts`, `Current.account.custom_filters.where(user:)` | **READY TO REUSE** | Commerce subqueries also pin `account_id` |
| Permissions | yes | `ContactPolicy`, `CustomFilterPolicy` | **READY TO REUSE** | no new permission flag |
| Search | yes | `contacts/search` | **READY TO REUSE** | untouched |
| Audit | partial (not for saved filters) | `Enterprise::Audit::*`, audit log page | **NEEDS PATCH** | audit contact segments (audiences): created / updated / deleted, named and filterable on the existing audit log page |
| Commerce link conditions | yes, in SQL | `commerce_customer_links`, `commerce_stores` | **READY TO REUSE** | has a linked store, provider, store |
| Commerce order figures | no (Redis, in memory) | `Commerce::Cache`, `Commerce::Customer360` | **NOT PRESENT** | `commerce_contact_metrics`: one summary row per customer link, written by the existing read paths (03) |
| Abandoned carts | no (Redis, per conversation identity) | `Commerce::AbandonedCarts` | **NOT PRESENT** | not exposed in this phase (03 §7) |

## Deliberately not created

- no Audience model, table or API (`/audiences`, `lynomia_audiences`); no member table; no copied contact lists
- no second condition format, no expression parser, no `commerce_*` operators
- no Commerce orders, products, addresses, payments or shipments in Postgres
- no new Commerce sync pipeline, job or schedule; no provider call while evaluating an audience
- no new permission flag
- no Automation or Campaign change
