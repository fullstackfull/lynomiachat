# Lynomia Audience: architecture

An **audience is a Chatwoot contact segment**: a saved contact filter (`CustomFilter`, `filter_type: contact`) that is
evaluated again every time it is opened. Lynomia adds condition fields to the contact filter (conversation and
Commerce fields) and calls segments "Audiences" in the product. The storage, API, URLs, permissions and evaluation
engine are Chatwoot's. Discovery is in [00](00-existing-system-discovery.md), the reuse decision in
[01](01-reuse-map.md), the Commerce model in [03](03-commerce-query-model.md).

```text
Contacts → Filter → build conditions (existing builder, two new field groups)
         → Apply   POST /api/v1/accounts/:id/contacts/filter?page=1   { payload: [conditions] }
                   → Contacts::FilterService (+ Custom::Contacts::FilterService) → one SQL query
                   ← first page of 15 contacts + meta.count                 ("Showing 1 – 15 of N contacts")
         → Save audience   POST /api/v1/accounts/:id/custom_filters { name, type: contact, query: { payload } }
Sidebar  → Audiences → /contacts/segments/:segmentId
                   → the saved query is posted to /contacts/filter again: membership is always current
```

## 1. Storage and semantics

| | |
|---|---|
| Model | `CustomFilter` (`custom_filters`): `account_id`, `user_id`, `name`, `filter_type` = contact, `query` = `{ payload: [conditions] }`. No new table, column or migration. |
| Membership | **Dynamic.** Never stored. Opening, previewing or counting an audience runs its conditions against current data. |
| Static lists | Chatwoot has none, and none were added. Labels remain the way to pin contacts by hand (`labels` condition). |
| Entity | The Chatwoot **Contact**. Conditions about conversations or Commerce are `EXISTS` / aggregate subqueries about that contact; there is no audience customer, lead or member model. |
| Ownership | One account and one user, as for every saved filter: `Current.account.custom_filters.where(user: Current.user)`. |
| Names | Product label "Audiences" (`SIDEBAR.CUSTOM_VIEWS_SEGMENTS`, the segment dialogs and buttons in `contact.json`). Internally it stays a segment: routes `/contacts/segments/:segmentId`, store module `customViews`, API `custom_filters`. |

So yesterday's SAR 900 customer who places an order today and now has SAR 1,200 of visible spend belongs to "visible
spend (SAR) > 1000" as soon as Lynomia reads that order (03 §4). Nobody presses a sync button.

## 2. Condition format and operators

Unchanged: `{ attribute_key, filter_operator, values, query_operator }`, the operators Chatwoot already has
(`equal_to`, `not_equal_to`, `is_present`, `is_not_present`, `is_greater_than`, `is_less_than`, `days_before`). Only
new `attribute_key`s were added. Values are always bind parameters.

### Contact fields (existing, untouched)

Name, email, phone number, identifier, country, city, company, created at, last activity, blocked, labels, and every
contact custom attribute. Built by the unchanged engine.

### Conversation fields (new, group "Conversations")

| Key | UI | Values | Operators |
|---|---|---|---|
| `conversation_status` | Conversation status | open, resolved, pending, snoozed | equal_to, not_equal_to |
| `conversation_priority` | Conversation priority | low, medium, high, urgent | equal_to, not_equal_to |
| `conversation_inbox` | Conversation inbox | inbox ids (an inbox is one channel, so this is also the channel condition) | equal_to, not_equal_to |
| `conversation_assignee` | Assigned agent | user ids | equal_to, not_equal_to |
| `conversation_team` | Assigned team | team ids | equal_to, not_equal_to |
| `conversation_labels` | Conversation labels | label names | equal_to, not_equal_to |

`equal_to X` = the contact has **at least one** conversation matching X; `not_equal_to X` = the contact has **none**.
Several values are OR ("open or pending"). Only conversations the current user may see count
(`Conversations::PermissionFilterService`, including Enterprise custom roles), so an agent's audience never reveals a
conversation in an inbox the agent cannot open. `has_open_conversation` is `conversation_status = open`. The
contact's own `last_activity_at` stays the "last activity" condition; a separate "last conversation at" was not added.
Conditions run as `EXISTS` on `conversations` (indexed by contact); messages are never joined.

### Commerce fields (new, group "Commerce", only in accounts with Lynomia Commerce)

| Key | UI | Operators | Source |
|---|---|---|---|
| `commerce_store` | Linked store | equal_to, not_equal_to, is_present, is_not_present | links |
| `commerce_provider` | Store platform | equal_to, not_equal_to | links |
| `commerce_orders_count` | Visible orders | equal_to, is_greater_than, is_less_than | summaries |
| `commerce_spend_<currency>` | Visible spend (SAR), (USD), … one field per currency seen | is_greater_than, is_less_than | summaries |
| `commerce_last_purchase_at` | Last visible purchase | is_greater_than (after), is_less_than (before), days_before (more than N days ago) | summaries |
| `commerce_active_order` | Has an active order | equal_to Yes / No | summaries |
| `commerce_order_status` | Order status | equal_to (has an order with), not_equal_to (has none with) | summaries |
| `commerce_payment_status` | Payment status | same | summaries |
| `commerce_shipment_status` | Shipment status | same | summaries |

"Has a shipped order" is `Order status = shipped`. Store and platform options come from
`GET /api/v1/accounts/:id/commerce/audience_fields` (counted stores: id, name, provider; currencies seen; linked
contacts not read yet). Abandoned carts are not offered (03 §7). Semantics of every Commerce field are in 03.

## 3. AND / OR

Chatwoot's chain is flat: each condition carries the `query_operator` that joins it to the next one, and the chain is
one SQL expression, so AND binds before OR (`A AND B OR C` = `(A AND B) OR C`). Lynomia keeps it:

- OR inside one field is a multi-value condition: `Store platform = Salla, Shopify`.
- So the brief's example `(provider = Salla OR provider = Shopify) AND visible spend SAR > 1000 AND last purchase after …`
  is `Store platform = [Salla, Shopify] AND Visible spend (SAR) > 1000 AND Last visible purchase > <date>`.
- Parenthesised groups across different fields are **not** supported (no new expression parser, no nesting). That is a
  known limitation; the Captain audience tree (`Captain::AudienceMatcher`, root → group → leaf) is the shape to reuse if
  groups are ever needed.

## 4. Code

| Piece | File |
|---|---|
| Extension point | `app/services/contacts/filter_service.rb`: `Contacts::FilterService.prepend_mod_with('Contacts::FilterService')` |
| Condition dispatch, limits | `custom/app/services/custom/contacts/filter_service.rb` (`Custom::Contacts::FilterService#perform`, `#build_condition_query`) |
| Conversation conditions | `custom/app/services/audience/conversation_condition.rb` |
| Commerce conditions | `custom/app/services/audience/commerce_condition.rb` |
| Commerce summaries | `custom/app/models/commerce/contact_metric.rb`, migration `custom/db/migrate/20261002100000_create_commerce_contact_metrics.rb` |
| Builder options | `custom/app/controllers/api/v1/accounts/commerce/audience_fields_controller.rb`, route in `config/routes/commerce.rb` |
| Audit | `custom/app/models/custom/audit/custom_filter.rb`, included from `app/models/custom_filter.rb` |
| Builder fields | `app/javascript/dashboard/components-next/filter/audienceProvider.js`, appended in `contactProvider.js` |
| Builder groups, notes | `helper/filterAttributeIcons.js` (groups, icons), `ContactsFilter.vue` (notes, unread count, phone layout) |
| Saved audience edit | `Contacts/ContactsHeader/ContactListHeaderWrapper.vue` (rebuilds Audience rows), `ContactsActiveFiltersPreview.vue` and `ActiveFilterPreview.vue` (field and value names in the pills) |
| Strings | `i18n/locale/{en,ar}/contactFilters.json` (`CONTACTS_FILTER.GROUPS`, `CONTACTS_FILTER.AUDIENCE`), `contact.json`, `settings.json` |

`build_condition_query` hands a condition to Audience only when its key is an Audience field; every other key goes to
Chatwoot's code untouched, and the produced SQL is appended to the same chain with the same `query_operator`.

## 5. Compatibility with existing filters and segments

- The new keys are **not** in `lib/filters/filter_keys.yml`. That file is shared with automation rules, whose
  `ConditionValidationService` accepts any key under `contacts:`; listing the keys there would let automation save
  conditions it cannot evaluate (06).
- An account whose contact custom attribute happens to be named like an Audience key (`conversation_status`,
  `commerce_store`, …) keeps the custom-attribute meaning: `build_audience_condition` returns nil and the engine builds
  it as before. No saved segment changes meaning.
- No data migration of `custom_filters`; no existing condition becomes invalid. Existing keys, operators and the
  existing contact/conversation filter specs pass unchanged (05 §4).
- Without the `lynomia_commerce` feature, Commerce keys are rejected like any unknown key (422) and the builder does
  not show them; conversation fields are available to every account.

## 6. Validation

At the filter boundary (`Custom::Contacts::FilterService`), before any SQL runs; every failure is one of Chatwoot's
existing `CustomExceptions::CustomFilter::*` errors, so the API answers **422** as for any bad filter:

- operator not allowed for the field → `InvalidOperator`;
- missing, malformed or out-of-range values (non-integer ids, unknown statuses, negative amounts, non-ISO dates,
  `days_before` outside 1–998, a label name over 255 characters, more than one value where one is expected) → `InvalidValue`;
- more than **10** conversation/Commerce conditions in one filter, or more than **50** values in one condition → `InvalidValue`;
- a Commerce key in an account without Lynomia Commerce, or any unknown key → `InvalidAttribute` (the engine's own check).

Field names never reach SQL from the request: each key maps to fixed SQL in code.

## 7. Builder UX

- The same attribute picker, with two more groups: **Conversations** and **Commerce** (icons, `GROUPS.CONVERSATIONS`,
  `GROUPS.COMMERCE`).
- Notes under the conditions, only when such a field is used: conversation conditions ("at least one such
  conversation / none, among the conversations you can see"); Commerce ("latest orders Lynomia has read … visible
  orders and spend, not lifetime totals. Spend is per currency."); and, when some linked contacts have not been read
  yet, how many ("order conditions can't match them … read when an agent opens the contact's conversation or the store
  sends an update").
- Preview: Apply shows the first page and "Showing 1 – 15 of N contacts" (existing footer, `meta.count`). Never all
  contacts in the browser.
- Save: "Save audience" → name → listed under **Audiences** in the sidebar. Edit: the saved Audience rows are rebuilt
  with their options (store by name, Yes/No, statuses). Delete: removes the audience only; contacts stay.
- Phone (390 px) and Arabic RTL: the panel spans the screen under the header, buttons wrap; all strings in `en` and `ar`.

## 8. Not built (by design)

No Audience model, table, member list or `/audiences` API; no static list; no new operators or expression parser; no
nested groups; no provider call while evaluating; no orders in Postgres; no Campaign or Automation change (06).
