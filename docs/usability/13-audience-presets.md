# Audience presets

Seven presets. Each builds the `query` of a **normal contact filter** — the same shape the filter builder saves —
which is then saved through the dialog and the call the product already uses. Architecture in
[10](10-recipe-architecture.md); why these seven in [09a](09a-recipe-opportunity-study.md) §4.3.

## 1. What an audience still is

Unchanged by this phase, and worth restating because a "preset" could be mistaken for a list:

- an audience is a `CustomFilter` (`filter_type: contact`), **shared** when the account shares it;
- membership is **never stored**. It is worked out again every time the audience is opened, counted or sent to;
- a preset therefore produces **conditions**, not members, and the audience it saves is as dynamic as a hand-built
  one.

## 2. The seven

| id | Name | Condition | Asks for |
|---|---|---|---|
| `high_value_buyers` | High-value buyers | `commerce_spend_<ccy>` is greater than N | **currency**, amount (starts at 1000) |
| `repeat_buyers` | Repeat buyers | `commerce_orders_count` is greater than N | count (starts at 1) |
| `recent_buyers` | Recent buyers | `commerce_last_purchase_at` days before N | days (starts at 30) |
| `customers_with_active_order` | Customers with an open order | `commerce_active_order` equal to true | — |
| `customers_with_shipped_order` | Customers with a shipped order | `commerce_order_status` equal to `shipped` | — |
| `store_customers` | Customers of one store | `commerce_store` equal to the store | store |
| `linked_commerce_customers` | All linked customers | `commerce_store` is present | — |

### 2.1 Two deliberate corrections to the brief

**"VIP customers = spend > 1000" is refused as written.** §10 of the brief is right: VIP is not a number this
catalogue may choose. The preset is called **High-value buyers**, it asks which currency it means and what the
threshold is, and it names itself after what it measures rather than after a business judgement.

**The four provider presets became one store picker.** "WooCommerce customers", "Salla customers", "Zid customers"
and "Shopify customers" would list providers the installation has switched off or the account has never connected.
`store_customers` is fed from `GET /commerce/audience_fields`, which already filters to
`Commerce::Providers.enabled` and to this account's active stores, so it is correct by construction and stays
correct when a provider is ungated later.

**"Customers with a shipped order" uses the order status, not the shipment status.** The normalized shipment
statuses are `pending`, `in_transit`, `out_for_delivery`, `delivered`, `failed`, `cancelled`, `returned`, `other` —
there is no `shipped` among them. The order statuses do have one.

## 3. Semantics a preset must respect

`Audience::CommerceCondition` divides its operators in two, and the presets are built with that in mind:

| Kind | Operators | Behaviour | Presets using it |
|---|---|---|---|
| **Grows with data** | `is_greater_than`, `days_before`, "has an order with …" | true as soon as the summaries Lynomia has read prove it | high-value, repeat, recent, shipped |
| **Could change with data** | `is_less_than`, `equal_to`, "has no order with …" | matches only when **every** counted link of the contact has been read | customers with an open order |

`commerce_store` conditions are facts about links, not about orders, so they are exact.

**Money is per currency and never converted.** A spend preset always asks which currency it means; there is no
preset that adds currencies together, because the engine does not.

## 4. Saving one

```text
⋮ → New audience from a preset → Use this → values → Create
  → the preset's conditions go into the page's pending filter query
  → the existing "save these filters as an audience" dialog opens, the name prefilled with the preset's own
  → the user confirms the name and, if they are an administrator, whether the account shares it
  → POST /custom_filters
```

So the two decisions that matter — what it is called, and whether the whole account can use it — stay the user's
explicit act, in the dialog the product already uses.

The gallery's "Start from scratch instead" opens the ordinary filter builder.

## 5. Availability

Every preset needs Commerce, which is honest: without a connected store there is nothing in a contact filter that a
preset knows better than the person building it. An account without Commerce sees the presets listed with "Needs
Commerce first" and no Create button, and builds its filter in the builder as before.

## 6. How they are checked

`recipes/specs/audiencePresets.spec.js` (10 assertions): the manifest, unique ids, the exact condition shape the
filter builder saves (including `attribute_model: 'commerce'` and the null operator on the last condition), every
field and operator inside `Audience::CommerceCondition::FIELDS` and the spend-operator list, the ten-condition limit,
and that the currency is always asked for and never assumed.
