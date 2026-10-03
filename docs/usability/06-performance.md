# Performance

The rule for this phase: **convenience must not cost a request.** What follows is what each added surface actually
fetches, counted from the code.

## 1. Requests added per surface

| Surface | Requests it makes | Notes |
|---|---|---|
| Command bar entries | **0** | two more objects in an array that is already computed; the route is resolved client-side |
| "Unpublished changes" | **0** | `flows_controller#flow_json` already returned `published` **and** `draft`. No field was added, no call was added |
| Audience actions menu | **0** | teams, labels, contact filters and the usage counts are already in the store or already in the custom-filter payload (`active_automation_rules_count`, `campaigns_count` come from the same jbuilder the list already renders) |
| "Use in a new rule" | **1**, the one the Automation panel always makes (`customViews/get`, `loadAudienceFields`) when it opens | the panel made them before; the audience is resolved from what they return |
| "Use in a new campaign" | **1** `customViews/get`, and only when the route actually carries an audience id | the campaigns route view fetches campaigns and labels but not contact filters, so this fills a real gap rather than duplicating one |
| Recipe gallery (all three) | **0 new** | `useRecipeContext` reads the store, and calls `loadAudienceFields()` — the **same module-level cached call** the contact filter makes, keyed by account. Opening the gallery after using the filter fetches nothing |
| Recipe wizard | **0** | every picker is fed from what the gallery already had |
| Create from an audience preset | **1** `POST /custom_filters` | the same call "save these filters as an audience" makes |
| Create from an automation recipe | **1** `POST /automation_rules` | the same call the form makes |
| Create from a flow template | **2** — `POST /flows`, `PUT /flows/:id/draft` | exactly what the builder itself does on a new flow's first save |
| Duplicate a flow | **3** — `GET /flows/:id`, `POST /flows`, `PUT /flows/:id/draft` | the read comes first, so a failure creates nothing |
| Order number copy | **0** | a clipboard write |

**No N+1, no polling, no preload of a dataset, and no provider call anywhere.** Nothing here asks WooCommerce, Salla,
Zid or Shopify for anything: the only Commerce data any of it reads is `GET /commerce/audience_fields`, which
`Api::V1::Accounts::Commerce::AudienceFieldsController` serves from Postgres alone — the counted stores, the
currencies already seen, and how many linked contacts have not been read yet.

## 2. The one shared fetch

`useAudienceFilterTypes` holds `commerceFields` in a module-level ref keyed by account id and returns early when it
already has them. This phase added two computed accessors (`commerceStores`, `commerceCurrencies`) over that same
cache rather than a second call. Three surfaces now share it: the contact filter builder, the automation rule
builder, and the recipe gallery.

## 3. Double submission

Every create path disables its own control while it runs: `RecipeDialog` passes `isCreating` to the Dialog's
`is-loading`/`disabled`, the flow list holds `isCreatingFromTemplate`, the automation list holds
`isCreatingFromRecipe`, and the existing segment dialog already held `uiFlags.isCreating`. The control is disabled
**only** while a request is in flight.

## 4. Work added to a page that already renders

| | |
|---|---|
| Catalogues | 20 plain objects, built once at module load. No reactivity, no watchers |
| `describeAll` | runs over 6–7 entries when the gallery is open: a `filter`, a `map` and a `sort`. Not on any list page |
| Flow list | one extra boolean per row (`flow.published && flow.draft`) |
| Audience menu | the two counts are read from the segment object the page already holds |
| Bundle | the three catalogues and the copy are ~30 KB of source, imported only by the pages that offer them |

## 5. Audience evaluation is unchanged

An audience created from a preset is an ordinary `CustomFilter`, so it is evaluated by
`Contacts::FilterService` + `Custom::Contacts::FilterService` as one SQL query over
`commerce_customer_links` and `commerce_contact_metrics`. The guarantee the Audience phase established holds
unchanged, because nothing about evaluation was touched:

```
0 WooCommerce calls   0 Salla calls   0 Zid calls   0 Shopify calls
```

The presets deliberately build **one** condition each, well inside `Custom::Contacts::FilterService::MAX_CONDITIONS`
(10) — asserted in `audiencePresets.spec.js`.

## 6. Flow runtime is unchanged

A flow created from a template runs on `Flows::Runner` like any other. The templates stay far inside the graph
limits — the largest is 12 nodes and 19 edges against `MAX_NODES` 300 and `MAX_EDGES` 900 — and the measured canvas
performance work from the Flow Builder phase (up to 200 nodes) is untouched.

The order-tracking template uses at most two `commerce_lookup` nodes per session, against
`Flows::Nodes::CommerceLookup::LOOKUP_LIMIT` of 10 per conversation per hour.
