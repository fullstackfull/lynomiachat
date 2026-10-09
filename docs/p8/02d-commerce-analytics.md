# P8.5 — Commerce analytics

Companion to `docs/p8/02-analytics.md`, and to the Commerce design it reads from
(`docs/commerce-production/05-cart-state-design.md`).

`GET /api/v1/accounts/:account_id/analytics/commerce`

| Parameter | Values |
| --- | --- |
| `since`, `until`, `group_by` | the shared contract |
| `provider` | validated against `Commerce::Store::PROVIDERS` |
| `breakdown_by` | `provider` (default) \| `store` \| `currency` \| `action_type` \| `action_error` |

Provider-neutral throughout. Every number comes from `commerce_carts` and `commerce_action_runs`, which already
normalise WooCommerce, Salla, Zid and Shopify into one shape. Nothing here calls a provider, and nothing here
keeps a second copy of an order.

---

## 1. Three rules, each a restatement of what the data supports

### No revenue, GMV or profit

`commerce_carts.visible_total` exists, and it is **never summed** — not per screen, not per currency, not
anywhere in the payload. Two reasons, and the first alone is sufficient:

1. A cart carries its own `currency` and nothing in this product converts between currencies. One total would
   silently add riyals to dollars.
2. A per-currency money total is a revenue figure, and `visible_total` is the amount the provider displayed on a
   cart — not a settled, taxed, discounted, refund-adjusted amount. Publishing it as revenue would be wrong even
   within one currency.

The **currency breakdown therefore reports cart counts**, which is the number an operator actually needs from
it: which currencies the traffic is in, and therefore that the values cannot be added up. A request spec asserts
that no KPI key is a money name and that every KPI unit is `count` or `percent`.

### No recovery attribution

Completion does not prove Lynomia's outreach caused it. Zid's own cart schema carries `reminders_count` and a
`whatsapp_message`, so the store may be sending reminders of its own
(`custom/app/models/commerce/cart.rb`). There is deliberately no `recovered` state in the schema and there is no
recovery metric here.

What is reported is `post_target_completions`: a completion whose `completed_at` is **after** `targeted_at`.
That is the ordering of two recorded times, named for exactly what it measures, and it is the same condition the
model's own `Commerce::Cart#post_target_completion?` expresses — a spec asserts the two agree.
`untargeted_completions` sits beside it so the contrast is visible rather than implied, and the UI hint says in
plain words that this is not proof of cause.

### No invented cart states

The enum is `abandoned` and `completed`, because those are the only two things a provider announces. There is no
`active` state and Lynomia runs no inactivity timer, so **silence from a store is never counted as
abandonment**. `carts_seen` and `carts_abandoned` are reported separately even though they are usually equal,
because nothing in the schema guarantees that they are.

---

## 2. Metrics

| Metric | Definition | Kind |
| --- | --- | --- |
| `carts_seen` | `first_seen_at` in range | event |
| `carts_abandoned` | `abandoned_at` in range | event |
| `carts_targeted` | `targeted_at` in range — outreach accepted for sending | event |
| `carts_completed` | `completed_at` in range | event |
| `post_target_completions` | completed in range with `completed_at > targeted_at` | event |
| `untargeted_completions` | completed in range with `targeted_at` null | event |
| `targeting_rate` | `carts_targeted / carts_abandoned`, `nil` when nothing was abandoned | event |
| `order_actions_requested` | `commerce_action_runs` of an order type, by `created_at` | event |
| `order_actions_failed` | of those, `status = failed` | event |
| `recovery_messages_prepared` | `action_type = recovery_message`, by `created_at` | event |
| `open_abandoned_now` | `state = abandoned` | **current state** |
| `actions_unresolved_now` | the model's `unresolved` scope: `pending`, `running` or `unknown` | **current state** |

### `carts_targeted` is not "a message arrived"

`targeted_at` means a Lynomia outreach was **accepted for sending**. Whether it reached the customer is a
WhatsApp delivery question and belongs on the WhatsApp screen
(`docs/p8/02b-whatsapp-campaign-analytics.md`). The KPI hints say so on both screens so the two are not read as
the same number.

### `actions_unresolved_now` matters more than its size suggests

`unknown` means the request reached the store but the answer was lost. Such a run is **never re-sent**, only
reconciled by reading the store (`custom/app/models/commerce/action_run.rb`). Before this screen, a lost answer
sat in the table with nothing surfacing it. Any value above zero is work for an operator, and the hint says so.

---

## 3. Tenant isolation

`Commerce::Cart.where(account_id:)` and `Commerce::ActionRun.where(account_id:)`; the store breakdown's labels
come from `@account.commerce_stores`. The `provider` filter is validated against the supported provider list
rather than against free text, and the request spec asserts a 422 for an unsupported provider.

Nothing in the payload carries a customer identifier. `commerce_carts.external_customer_id` is encrypted and is
never read here; `contact_id` is never grouped on.

---

## 4. Frontend

The shared `AnalyticsScreen` shell with scope `COMMERCE`, three series cards (abandoned, messaged, completed)
and the five breakdown dimensions. Route `analytics_commerce`, sidebar Analytics → Commerce, copy under
`ANALYTICS.COMMERCE.*` in EN and AR.

There is no money series card, which is the visible consequence of §1 rather than an omission.

---

## 5. Tests

| Spec | Count |
| --- | --- |
| `spec/services/analytics/commerce/metrics_spec.rb` | 19 |
| `spec/requests/analytics/analytics_commerce_spec.rb` | 12 |

Among them: a spec that the service agrees with `Commerce::Cart#post_target_completion?`, a spec that a
completion *preceding* its outreach is counted as neither post-target nor untargeted, and a spec that the
payload publishes no money figure and no money unit.

---

## 6. Known limitations carried forward

1. **No revenue, GMV or profit**, and no per-currency money total either (§1).
2. **No historical cart-state transitions.** A cart row holds its current state with `abandoned_at` and
   `completed_at`; there is no per-transition log, so "how many carts were abandoned as of last Tuesday" is not
   answerable.
3. **No recovery attribution.** `post_target_completions` is a time ordering.
4. **No cart abandonment Lynomia detected itself.** Abandonment is whatever the provider announced.
5. **A completion that preceded its outreach is counted as neither** post-target nor untargeted: it is a
   completed cart that was also messaged, which the funnel reports under `carts_completed` and `carts_targeted`
   without claiming a relationship between them.
6. **Order actions have no per-action latency metric.** `started_at` and `completed_at` exist on the run, but
   they are not populated on every path, so an average would be computed over an unstated subset.
