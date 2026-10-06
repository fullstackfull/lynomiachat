# 09 — UAT results

**Status: SOFTWARE COMPLETE / REAL PROVIDER UAT BLOCKED.** No provider credentials exist in this environment, and
A3 forbids asking for secrets in chat. Nothing below is marked passed.

---

## 1. Why every provider is blocked

| Provider | Blocker |
|---|---|
| WooCommerce | credentials only. Its contract is the best-evidenced of the four (a real captured payload) and its production path is not gated — the cheapest first real UAT |
| **Zid** | credentials, **plus** two separate facts: order webhooks could never have delivered before `02`'s fix, and every cart path is PRE_UAT |
| Shopify | Shopify's protected-customer-data review, which no configuration change shortcuts |
| Salla | credentials + partner approval. Read-only by token scope; registers no webhooks |

The ordering and the per-provider steps are in `03`. What follows is the Zid cart UAT specifically, which is new
in this phase.

## 2. The ten things a real Zid store must prove

Nothing in the cart lifecycle may be enabled in production until these are answered. Items 4, 5 and 9 are the ones
that could change code.

| # | Question | How it is answered | What it decides |
|---|---|---|---|
| 1 | Webhook registration succeeds | re-authorize the Zid store; the five subscriptions are created | whether anything arrives at all |
| 2 | Basic Auth delivery succeeds | a `commerce.webhook.accepted` metric, not `commerce.webhook.rejected` | that `02`'s fix is real on a live store |
| 3 | `abandoned_cart.created` payload captured | abandon a test cart; capture the delivered body | everything below |
| 4 | **The canonical cart id** | does the body carry `id`, `cart_id`, `session_id` — and which is stable across the created *and* completed deliveries for one cart? | `CartEvents::IDENTITY_KEY`. If `id` is a per-delivery surrogate, the unique index is on the wrong value and completions would create rows instead of transitioning them |
| 5 | **The envelope** | is the cart object at the top level, or wrapped? Is there an `event` field? | whether `cart_delivery?` routes real traffic. If deliveries carry no event name, cart bodies would currently be routed to the order path |
| 6 | Timestamp semantics | are `created_at` / `updated_at` the cart's or the delivery's? Timezone? | the monotonic guard in `06` §5 rule 2 |
| 7 | `order_id` semantics | is it populated on completion, and is it the order Lynomia can then read? | order attribution, and `08` §5's permitted wording |
| 8 | Duplicate delivery behaviour | re-send; observe `commerce.webhook.duplicate` and that the row does not change | that §6's duplicate handling holds in reality |
| 9 | **Provider-native reminders** | does `reminders_count` rise without Lynomia doing anything? Does `whatsapp_message` carry text Zid sends? | whether post-target completion can ever be attributed to Lynomia at all — and therefore whether `commerce_cart_recovered` may ever exist |
| 10 | A safe test cart completes end to end | abandon, observe `abandoned`; complete, observe `completed` + `provider_order_id` | the whole lifecycle |

## 3. The operator runbook

Do not send credentials in chat. Everything below runs on the deployed server.

### Step 0 — see the state without changing it

```bash
bundle exec rails runner 'Commerce::Store.where(provider: "zid").find_each { |s| \
  puts "store=#{s.id} external=#{s.external_store_id} status=#{s.status} carts_offered=#{Commerce::AbandonedCarts.offered?(s)}" }'
```

`carts_offered=false` is expected: carts are PRE_UAT. Clearing that gate is step 2, and only for the UAT window.

### Step 1 — repair and verify the webhook subscription

Zid marks a webhook **broken** after 30 delivery failures in an hour and then stops dispatching (`02` §1.6), so a
store that has been live with the old registration may need Zid's own recovery endpoint, not just a
re-registration.

1. Re-authorize the Zid store in Settings → Commerce. This re-runs `Commerce::Zid::Webhooks#register`, which now
   sends `username`/`password` at the top level and **raises** if any of the five subscriptions fails.
2. In Zid's partner dashboard, confirm the store's webhooks exist and are not `broken`. If broken, use Zid's
   "Recover Broken Webhooks" endpoint with a fresh target URL.
3. Confirm the five events: the three order events plus `abandoned_cart.created` and `abandoned_cart.completed`.

### Step 2 — open the cart gate for the UAT window only

Carts are PRE_UAT for all four providers. For the test window set, on the server only:

```
COMMERCE_ALLOW_PRE_UAT_PROVIDERS=true
ZID_RECOVERY_ENABLED=true
```

`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is ENV-only and documented in `Commerce::Switches` as "staging and simulated
E2E runs only, never production". **Unset it when the window closes.** A provider leaves PRE_UAT properly through a
reviewed code change, not an environment variable.

### Step 3 — capture the two payloads

Abandon a test cart in the Zid store (add products, start checkout, stop), wait for Zid's own interval, then
complete it on a second cart.

Capture, for each delivery:

```bash
grep -F '[COMMERCE CART]' log/production.log | tail -20
bundle exec rails runner 'Commerce::Cart.order(:id).last(5).each { |c| \
  puts "#{c.provider_cart_id} #{c.state} phase=#{c.provider_phase} order=#{c.provider_order_id} \
abandoned=#{c.abandoned_at} completed=#{c.completed_at} event=#{c.last_provider_event_at}" }'
```

A `[COMMERCE CART] event=unusable_zid_cart_delivery` line is the single most valuable result of this UAT: it means
an `UNVERIFIED` assumption is wrong, and its `keys=` list says which.

### Step 4 — the duplicate and ordering checks

Re-send one delivery from Zid's dashboard, and confirm: `commerce.webhook.duplicate`, no second row, and no
change of state. Then confirm no cart changed state while Zid was sending nothing.

### Step 5 — what to send back

| | |
|---|---|
| The two captured bodies | with customer name, email and phone redacted. The field **names** are what matter |
| Whether one cart kept one id across both deliveries, and which field | answers #4 |
| Whether an `event` field was present | answers #5 |
| `reminders_count` before and after, with no Lynomia action | answers #9 |
| Any `[COMMERCE CART]` lines | answers #5 the hard way |
| The `commerce.webhook.*` metrics seen | answers #2 and #8 |

That is enough to close items 4, 5, 6, 7 and 9 without a second round of discovery.

## 4. What this phase can and cannot claim

**Can:** the software records a Zid cart lifecycle from provider events, forward-only, idempotent against
duplicates and out-of-order arrival, with one Automation event, with no clock that an outage could misfire, behind
a shut gate — all proven by 39 new examples.

**Cannot:** that any of it has met a real Zid delivery. The payload shape, the stable identity and the reminder
confound are open, and they are open in the only way that matters — on a real store.
