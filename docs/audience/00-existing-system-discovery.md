# Lynomia Audience: what Chatwoot already has

Traced from the code (backend to SQL), in the Community, Enterprise and Lynomia (`custom/`) trees, before any Audience
change. Branch `claude/laughing-albattani-8yi0kh`, base `b09e1f40c`.

## 1. Contact filtering (the engine to extend)

| | |
|---|---|
| API | `POST /api/v1/accounts/:account_id/contacts/filter?page=N&sort=…` with `{ payload: [conditions] }` |
| Controller | `Api::V1::Accounts::ContactsController#filter` → renders `contacts/filter.json.jbuilder` (`meta.count`, `meta.current_page`, `payload`), 15 per page (`RESULTS_PER_PAGE`, Kaminari) |
| Service | `Contacts::FilterService < FilterService` (`app/services/contacts/filter_service.rb`) |
| Field config | `lib/filters/filter_keys.yml`, section `contacts:` (key → `attribute_type`, `data_type`, `filter_operators`) |
| SQL builders | `Filters::FilterHelper` (`app/helpers/filters/filter_helper.rb`), `Filters::CustomAttributeFilterHelper` |
| Base scope | `account.contacts.resolved_contacts(use_crm_v2:)`: contacts with an email, phone or identifier (or `contact_type = lead` with `crm_v2`) |
| Errors | `CustomExceptions::CustomFilter::{InvalidAttribute, InvalidOperator, InvalidQueryOperator, InvalidValue}` → 422 |
| Also used by | `Account::ContactsExportJob` (export of a filtered list, with the requesting user) |

**Condition format** (one shape for contacts, conversations, segments, folders and automation):

```json
{ "attribute_key": "email", "filter_operator": "contains", "values": ["@example.com"],
  "query_operator": "AND", "attribute_model": "standard", "custom_attribute_type": "" }
```

**Fields** (`contacts:`): `name`, `phone_number`, `email`, `identifier` (standard); `country_code`, `city`,
`company_name` (additional attributes); `labels` (taggings); `created_at`, `last_activity_at` (dates); `blocked`
(boolean); plus every contact custom attribute defined in the account (`custom_attribute_definitions`, typed by
display type: text, number, currency, percent, link, date, list, checkbox).

**Operators** (`FilterService#filter_operation`): `equal_to`, `not_equal_to`, `contains`, `does_not_contain`,
`is_present`, `is_not_present`, `is_greater_than`, `is_less_than`, `days_before` (1–998 days), `starts_with`
(automation). Values are bound parameters; numbers and dates are coerced (`coerce_lt_gt_value`: finite decimals,
ISO 8601 dates) and rejected with `InvalidValue` otherwise.

**Boolean logic: a flat chain.** Each condition carries the `query_operator` (`AND`/`OR`, validated) that joins it to
the next; the condition strings are concatenated and run as one `WHERE`, so SQL precedence applies (`AND` binds before
`OR`). There are no parentheses or groups. OR inside one field is expressed by several values
(`equal_to ["a","b"]` → `IN (…)`).

## 2. Conversation filtering

`POST /conversations/filter` → `Conversations::FilterService < FilterService`, section `conversations:` (status,
assignee, inbox, team, priority, labels, campaign, dates, …), scoped by `Conversations::PermissionFilterService`
(administrators: all; agents: their inboxes; Enterprise custom roles via `Enterprise::Conversations::PermissionFilterService`).
Saved conversation filters are "folders" (`CustomFilter` with `filter_type: conversation`).

## 3. Segments = saved contact filters

| | |
|---|---|
| Model / table | `CustomFilter` / `custom_filters` (`name`, `filter_type` enum conversation 0 / contact 1 / report 2, `query` jsonb, `account_id`, `user_id`) |
| API | `GET/POST /custom_filters?filter_type=contact`, `GET/PATCH/DELETE /custom_filters/:id` (`CustomFiltersController`) |
| Ownership | account **and** user: every query is `Current.account.custom_filters.where(user: Current.user)`; another user's or another account's id is a 404 |
| Limit | `Limits::MAX_CUSTOM_FILTERS_PER_USER` = 1000 |
| Permissions | `CustomFilterPolicy`: administrators and agents; `ContactPolicy#filter?`: everyone with contacts access |
| Storage | `query: { payload: [conditions] }`, the same conditions the filter API takes |
| Semantics | **dynamic**: opening a segment (`/contacts/segments/:segmentId`) posts its saved `query` to `/contacts/filter`; no membership is stored |
| Frontend | sidebar group "Segments" (`SIDEBAR.CUSTOM_VIEWS_SEGMENTS`), `ContactListHeaderWrapper.vue` (create/edit/delete), `CreateSegmentDialog`, `DeleteSegmentDialog`, store module `customViews` |
| Audit | none (`CustomFilter` is not audited; Macro, AutomationRule, Inbox, … are, via `Enterprise::Audit::*`) |
| Delete | deletes the row only; contacts untouched; nothing references a contact segment |

## 4. Frontend filter builder

- `components-next/filter/ContactsFilter.vue`: the builder (rows, add/remove, apply, update segment), `ConditionRow.vue`
  (attribute, operator, value input), inputs `FilterSelect`, `MultiSelect`, `MultiTextInput`, plain text, date.
- `contactProvider.js` → `useContactFilterContext()`: the attribute list (`filterTypes`, each with `attributeKey`,
  `inputType`, `options`, `filterOperators`, `attributeModel`), grouped for the picker by
  `helper/filterAttributeIcons.js#groupFilterTypes` (sections keyed by `attributeModel`: standard, additional, custom).
- `operators.js` → operator sets (`equalityOperators`, `containmentOperators`, `dateOperators`, …).
- `helper/filterQueryGenerator.js` → `{ payload }`; `customViewsHelper.js` rebuilds rows from a saved segment.
- Store `contacts/filter` → `ContactAPI.filter`; `meta.count` feeds the "Showing 1 – 15 of N contacts" footer, so a count
  preview already exists.

## 5. Campaigns

`Campaign.audience` jsonb = `[{ type: 'Label', id }]` only. One-off SMS / Twilio / WhatsApp campaigns resolve it at send
time to `account.contacts.tagged_with(labels, any: true)`; Enterprise WhatsApp writes `campaign_recipients` (per-send
delivery records: status, sent/delivered/read/failed) while sending. **Campaigns do not consume segments or saved
filters.** Nothing in the campaign path reads `custom_filters`.

## 6. Automation

`AutomationRules::ConditionsFilterService < FilterService` evaluates a rule's `conditions` (same condition shape) as SQL
against **one conversation** joined to its contact and message; `ConditionValidationService` accepts any key found in the
YAML's `conversations:`, `contacts:` or `messages:` sections, or a custom attribute. Contact keys are rendered as
`contacts.<key>` columns. There is no "contact is in segment" condition and no segment events.

## 7. Other audience-like code

- **Captain assistant audience** (Enterprise): `Captain::AudienceMatcher` evaluates `assistant.config['audience']`
  (a group tree, root → sub-group → leaves, `MAX_DEPTH` 3, AND/OR per group) **in memory** for one conversation's
  contact, to decide whether the AI assistant answers. Same keys and operator semantics as segments; UI
  `captain/.../audience/AudienceGroup.vue` reuses `ConditionRow`. It answers "does this one contact match", never "which
  contacts", so it is not a segmentation engine.
- **Search**: `GET /contacts/search?q=` (name, email, phone, identifier `ILIKE`); global search. Not a filter engine.
- **Labels**: `acts_as_taggable_on` on contacts and conversations (`taggings`, `tags`), filtered with `EXISTS`.
- **Contact lists / static lists / audience tables**: none.

## 8. Lynomia Commerce data: what is queryable in SQL

| Data | Where | SQL-queryable |
|---|---|---|
| Stores | `commerce_stores` (account, provider, status) | yes |
| Contact ↔ store customer | `commerce_customer_links` (account, store, contact, encrypted `external_customer_id`, `match_source` incl. `suppressed`) | yes |
| Orders (normalized `Commerce::Order`) | Redis only (`Commerce::Cache`, key = HMAC of the store customer id, 24 h), read through `Commerce::Cache.fetch(store, :orders, id)` by `ConversationPanel#linked` (agent view) and `Commerce::Realtime.read_orders` (webhook refresh), latest 5 per store (`ORDER_LIMIT`) | **no** |
| Customer 360 figures (visible orders, spend per currency, last purchase, active/shipped) | computed in memory per request (`Commerce::Customer360`) | **no** |
| Abandoned carts | Redis only, per conversation identity (link or the channel's verified phone/email), Salla/Zid/Shopify only | **no** |
| Order actions | `commerce_action_runs` (audit record of actions) | yes, not a customer metric |

So link-level conditions (has a linked store, provider, store) are already evaluable in SQL; order-derived conditions
are not, and evaluating them would mean a store API call per contact.
