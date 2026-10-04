# Commerce recipe capability matrix

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Covers brief parts **0.6** (provider capability matrix) and **1.4** (the abandoned-cart decision). Provenance: the
`commerce_capability` and `abandoned_cart` inventories, re-checked by the `abandoned-cart` verifier (verdict
**CONFIRMED**), and re-spot-checked against the repo for every load-bearing claim below. Line numbers here are the ones
I read at this HEAD; where an inventory citation disagreed with the file, I used the file.

Every cell carries exactly one class from the mandated vocabulary: **SUPPORTED_RELIABLY / SUPPORTED_WITH_LIMITATIONS /
NOT_AVAILABLE / NOT_SAFE_FOR_AUTOMATION**.

**The class answers one question: can a recipe depend on this, for this provider, in production today.** Because that
verdict is often worse than the underlying data quality, each provider table also carries a separate, clearly-labelled
**Read fidelity** column (RELIABLE / LIMITED / NONE) for the agent-facing panel, Customer 360 and the Flow Builder
`commerce_lookup` node. The two columns diverge on purpose, and section 4.6 lists where.

---

## 1. The decision

| # | Recommendation | Class | Blocking or enabling fact |
|---|---|---|---|
| 1 | **Build** the commerce → webhook recipe (`commerce_event_webhook`) as the flagship commerce starter | REUSE | It is the only commerce action that is not a false promise. `send_webhook_event` is overridden to carry `commerce:{event,store_id,provider,order}` (custom/app/services/custom/automation_rules/action_service.rb:7-14). n8n/Make does the messaging, outside the read-driven trigger's reach. |
| 2 | **Build** `commerce_order_paid` → label/assign recipes for **WooCommerce, Shopify** only | EXTEND | Both derive `paid` from an explicit, reliable field. Salla can **never** be `paid` (custom/app/services/commerce/providers/salla/normalizer.rb:74-75); Zid's transport is unsigned and unverified (§2.4). |
| 3 | **Build** `commerce_order_refunded` → escalation for **WooCommerce, Shopify** only | EXTEND | Two independent refund signals each (WooCommerce status + refunds total; Shopify `REFUNDED`/`PARTIALLY_REFUNDED`). Salla's only refund signal is the `restored` slug, semantics unverified (§7). |
| 4 | **Reject** every "notify the customer when X" commerce recipe | DO NOT CREATE | Two independent blocks: commerce triggers forbid `send_message`/`send_attachment` (custom/app/models/custom/automation_rule.rb:9,38-39), and the trigger is read-driven so the notification would arrive when an agent opens the panel (§2.2). |
| 5 | **Reject** any `commerce_order_shipped` / `_delivered` recipe presented as cross-provider | DO NOT CREATE | WooCommerce can never reach either status (custom/app/services/commerce/providers/woocommerce/normalizer.rb:17-20,35) and Shopify's `delivered` is derived, bounded and webhook-less (§4.5). A cross-provider shipped recipe is true for Salla and Zid only. |
| 6 | **Reject** the abandoned-cart recipe. Verified twice, independently | DO NOT CREATE | No cart table, no cart transition, no trigger, no condition — and carts are production-unreachable for all four providers anyway (§3, §5). |
| 7 | **Reject** any recipe that performs a store write | DO NOT CREATE | No automation action writes to a store. The action set is conversation actions plus `send_webhook_event`; writes exist only on the agent UI, behind an administrator-or-`commerce_order_manage` policy (custom/app/policies/commerce/action_policy.rb:9-29), sent once and never retried (custom/app/jobs/commerce/action_job.rb:1-5). |
| 8 | **Patch** the silent-failure trap before shipping any commerce starter | PATCH | `event_name` has no inclusion validation (app/models/automation_rule.rb, DB `NOT NULL` only at db/schema.rb:313). A rule named `commerce_cart_abandoned` saves fine via the API and never fires. Nothing tells the author. |
| 9 | **New primitive required** before abandoned cart is even a conversation | NEW PRIMITIVE REQUIRED | Persisted prior cart state + a `Commerce::CartTransitions`. One migration (not designed here, not proposed), one scheduled read, one constant. §5.3. |
| 10 | Do **not** present Zid or Shopify order actions, or any provider's carts, as available | DO NOT CREATE | `Commerce::Switches::PRE_UAT` (custom/app/services/commerce/switches.rb:16) hard-offs them; WooCommerce has no `RECOVERY_KEYS` entry at all (:15). §2.3. |

**Net: one commerce recipe is honest today (webhook fan-out), four are honest per-provider (paid / refunded / created /
updated on WooCommerce and Shopify), and everything cart-, shipping- or message-shaped is a DO NOT CREATE.**

---

## 2. Four facts that govern every cell below

These are not caveats. They decide the classes.

### 2.1 Reads are never pushed — the provider payload is discarded

A provider webhook never carries the change. `Commerce::Realtime.order_event` asks the provider only for
`event_customer_ids`, drops the store's cached carts, invalidates those customers' cached orders, and then schedules
one coalesced `Commerce::RefreshJob` per **linked, non-suppressed** customer link
(custom/app/services/commerce/realtime.rb:32-43). No field of the event body is ever stored.

Every normalized `commerce_order_*` event is therefore produced by **re-reading the store and diffing two normalized
reads**: `Commerce::OrderTransitions.between` compares the previous read's persisted state against the current one
(custom/app/services/commerce/order_transitions.rb:38-46), through a Redis cache that is fresh for 120 s and serves up
to 24 h stale on store failure (custom/app/services/commerce/cache.rb:8-9). The prior state lives in exactly one place,
`commerce_contact_metrics.order_states` (db/schema.rb:850, written at
custom/app/models/commerce/contact_metric.rb:35-37).

Two consequences that a product owner must price in:

- **An event that names no customer produces no refresh at all** — it returns after a store-wide cache invalidation
  (custom/app/services/commerce/realtime.rb:37). WooCommerce `order.deleted` and any Salla event whose payload shape
  differs from the code's assumption land here.
- **A link's first read is a silent baseline.** `between` returns `[]` when there is no previous state
  (order_transitions.rb:39), and a newly-appearing order key emits `commerce_order_created` only if its `created_at`
  beats the newest order previously seen (:49-52). The first order observed for a newly linked contact emits nothing.

One upside worth stating, because it changes the risk shape of §2.4: since the payload is discarded, a forged webhook
**cannot inject false order data**. It can only force a read.

### 2.2 Commerce automation is READ-DRIVEN — one dispatch call site

`Automation::CommerceEvents.dispatch` has exactly **one** call site:
`custom/app/models/commerce/contact_metric.rb:27`. `ContactMetric.record` has exactly **two** callers:

| Caller | What triggers it |
|---|---|
| custom/app/services/commerce/realtime.rb:93 (`read_orders`, via `RefreshJob`) | A webhook arrived **and** named a customer **and** that customer has a non-suppressed `customer_link` **and** the store is active and its provider enabled |
| custom/app/services/commerce/conversation_panel.rb:62 | **An agent opened or refreshed the conversation's Commerce panel** |

There is no polling. The only scheduled commerce job is `Commerce::ActionSweepJob`
(config/schedule.yml:80-83), which reconciles action runs and prunes recovery rows and reads no orders.

So **a rule fires when someone reads the order, not when the store changes.** The webhook's only power is to schedule
that read, and only for already-linked customers. Where any precondition fails, the agent panel is the *only* remaining
path — which means the "automatic" rule fires minutes or days late, whenever a human happens to open the conversation.

Two further gates sit after the dispatch and bite every recipe:

- **No conversation, no rule.** The listener resolves the contact's latest conversation and, when there is none, logs
  `no_conversation` and stops (custom/app/listeners/custom/automation_rule_listener.rb:16-17). A commerce event for a
  contact who has never messaged you does nothing.
- **No active rule, no dispatch.** `dispatch` returns early unless an active rule already exists for that event name
  (custom/app/services/automation/commerce_events.rb:19-20).

What this means per recipe shape — this is the table to show a product owner:

| Recipe shape | What actually happens |
|---|---|
| "When an order is paid, label the contact VIP" | Fires on the next read of that order. If the store webhook works and the contact is linked, that is seconds. If not, it is whenever an agent next opens the panel. |
| "When an order ships, message the customer the tracking link" | **Impossible.** `send_message` is rejected at validation on every commerce trigger (custom/app/models/custom/automation_rule.rb:38-39). |
| "When an order is refunded, assign to the escalation team" | Works, with the §2.2 timing. Safe because assignment has no customer-visible urgency. |
| "When a high-value order is created, notify the team" | Works via `send_webhook_event` or `send_email_to_team`. The `commerce_order_created` event is suppressed on a link's first read (§2.1). |
| "When an order is delivered, ask for a review" | Customer-facing → impossible. Internal → fires when read; on Shopify the `delivered` promotion itself may never happen (§4.5). |
| "When a cart is abandoned, anything" | No such event exists. §5. |

### 2.3 PRE_UAT: carts, recovery, and three providers' writes are unreachable in production

```ruby
RECOVERY_KEYS = { 'salla' => …, 'zid' => …, 'shopify' => … }          # switches.rb:15 — no 'woocommerce'
PRE_UAT = { actions: %w[salla zid shopify], recovery: %w[salla zid shopify] }   # switches.rb:16
```

`provider_recovery_enabled?` requires a `RECOVERY_KEYS` entry, so it is **unconditionally false for WooCommerce**
(custom/app/services/commerce/switches.rb:28-31). For the other three, `uat_cleared?` passes only when the ENV-only
`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is truthy (:39-41) — which the file's own header says is for "staging and simulated
E2E runs only, never production", and which a provider leaves "through a reviewed code change".

| Feature | woocommerce | salla | zid | shopify |
|---|---|---|---|---|
| Abandoned carts + recovery | **off**, no `RECOVERY_KEYS` entry | **off**, PRE_UAT | **off**, PRE_UAT | **off**, PRE_UAT |
| Order write actions | **on** (`WOOCOMMERCE_ACTIONS_ENABLED` defaults true) | n/a, no write code | **off**, PRE_UAT | **off**, PRE_UAT |

`Commerce::AbandonedCarts.offered?` (custom/app/services/commerce/abandoned_carts.rb:18-21) and
`Commerce::RecoveryMessages#prepare` (custom/app/services/commerce/recovery_messages.rb:45) both hang off that
predicate, as does the admin recovery queue's store filter
(custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb:33). Independently, `SALLA_ENABLED`,
`ZID_ENABLED` and `SHOPIFY_COMMERCE_ENABLED` all default false (config/installation_config.yml:488, 515, 535), and the
three `*_RECOVERY_ENABLED` flags default false (:589, 595, 601).

**Net: in a default production install, zero stores of any provider show an abandoned cart.** The cart and recovery
feature is code-complete and reaches nobody.

### 2.4 Zid webhooks are NOT signed

Zid is the only provider of the four without a signed body. `Commerce::Zid::Webhook.authorized?` constant-time compares
an **HTTP Basic** username and password against a per-store random pair stored encrypted
(custom/app/services/commerce/zid/webhook.rb:8-14). The file says so itself at :1-3: *"This is HTTP Basic
Authentication, not a signature."* Compare the other three, all base64/hex HMAC-SHA256 over the raw body, constant-time,
before any parsing:

| Provider | Transport auth | Key | Citation |
|---|---|---|---|
| WooCommerce | HMAC-SHA256, base64, `X-WC-Webhook-Signature` | per-store random secret Lynomia generates | custom/app/services/commerce/woocommerce/webhook.rb:9-14 |
| Salla | HMAC-SHA256, hex, `Signature` strategy only | app webhook secret | custom/app/services/commerce/salla/webhook.rb:12-14 |
| Shopify | HMAC-SHA256, base64, + shop-domain + `X-Shopify-Webhook-Id` required | app client secret | custom/app/services/commerce/shopify/webhook.rb:18-19 |
| **Zid** | **HTTP Basic, no body integrity** | per-store random username/password | custom/app/services/commerce/zid/webhook.rb:8-14 |

And the delivery is **unverified end to end**. The `authentication` field that hands Zid those credentials at
subscription time could not be confirmed against Zid's documentation
(custom/app/services/commerce/zid/webhooks.rb:42-48, `VERIFY(zid-webhook-auth)`). If Zid ignores that field, Lynomia
refuses every delivery with 401 and Zid realtime silently does not work at all.

**Classification consequence.** Because of §2.1 the risk is availability and timing, not content forgery: a forged
delivery can force a read and name arbitrary customer ids, but cannot fabricate an order. Even so, a recipe cannot be
built on a transport that is both unsigned and unproven. **Every cell whose mechanism is a Zid webhook is classified
NOT_SAFE_FOR_AUTOMATION until a live Zid UAT proves deliveries authenticate.** Zid's *data* is the best of the four
providers and its read-fidelity column says so.

---

## 3. Transport and trust, per provider

| | woocommerce | salla | zid | shopify |
|---|---|---|---|---|
| Endpoint | `POST /webhooks/woocommerce/:store_id` | `POST /webhooks/salla` (app-wide) | `POST /webhooks/zid/:store_id` (external id) | `POST /webhooks/shopify_commerce` (app-wide) |
| Signed body | **yes** | **yes** | **no** (§2.4) | **yes** |
| Order topics | `order.created/updated/deleted` (providers/woocommerce.rb:12) | prefix `order.` / `shipment.` (jobs/commerce/salla/webhook_job.rb:13,18) | `order.create`, `order.status.update`, `order.payment_status.update` (zid/webhooks.rb:9) | `orders/create`, `orders/updated` (shopify/webhook.rb:9) |
| Cart topics | none | `abandoned.cart`, `abandoned.cart.update` (salla/webhook_job.rb:14) — drops caches only | none | none |
| Who creates the subscription | **Lynomia** (`registers_webhooks?` true, providers/woocommerce.rb:18) | **nobody in this repo** — Salla Partner Portal (`registers_webhooks?` false, providers/base.rb:54) | **Lynomia** (`Commerce::Zid::WebhookRegistrationJob`, zid/webhooks.rb:23) | **nobody in this repo** — `shopify.app.toml` + Shopify CLI (base.rb:54) |
| Realtime declared | `supports_realtime?` true on all four (woocommerce.rb:16, salla.rb:47, zid.rb:57, shopify.rb:110) — **and never read anywhere**: setting it false would change nothing | | | |
| Cache | `Commerce::Cache`, fresh 120 s, stale-serve to 24 h (cache.rb:8-9) — identical for all four | | | |
| Polling | **none, for any provider** (config/schedule.yml:80-83 is the only commerce cron and reads no orders) | | | |

The `supports_realtime?` row is a dead predicate (`PATCH`, cosmetic): four overrides, zero readers. Do not build a
provider-enablement story on it.

---

## 4. The capability matrix

### 4.1 At a glance

`RELY` = SUPPORTED_RELIABLY · `LIMIT` = SUPPORTED_WITH_LIMITATIONS · `NONE` = NOT_AVAILABLE · `UNSAFE` =
NOT_SAFE_FOR_AUTOMATION.

| Capability | woocommerce | salla | zid | shopify |
|---|---|---|---|---|
| Order created | LIMIT | LIMIT | **UNSAFE** | LIMIT |
| Order status change | LIMIT | LIMIT | **UNSAFE** | LIMIT |
| Paid | LIMIT | **NONE** | **UNSAFE** | LIMIT |
| Unpaid | LIMIT | LIMIT | LIMIT | LIMIT |
| Shipped | **NONE** | LIMIT | **UNSAFE** | LIMIT |
| Delivered | **NONE** | LIMIT | **UNSAFE** | **UNSAFE** |
| Cancelled | LIMIT | LIMIT | **UNSAFE** | LIMIT |
| Refunded | LIMIT | **UNSAFE** | **UNSAFE** | LIMIT |
| Cart | **NONE** | **NONE** | **NONE** | **NONE** |
| Abandoned cart | **NONE** | **NONE** | **NONE** | **NONE** |
| Recovery | **NONE** | **NONE** | **NONE** | **NONE** |
| Customer lookup | LIMIT | LIMIT | LIMIT | LIMIT |
| Tracking | **NONE** | LIMIT | LIMIT | LIMIT |
| Write actions | **UNSAFE** | **NONE** | **NONE** | **NONE** |

Not one cell in 56 is SUPPORTED_RELIABLY. That is the honest headline: §2.1 and §2.2 put a limitation on every event
in the system, and §2.3 removes three whole rows.

Two global facts that remove rows for **all** providers at once:

- **There is no `commerce_order_unpaid` event, for anybody.** `FACTS` has exactly five entries — paid, shipped,
  delivered, cancelled, refunded — and `EVENTS` is those plus created/updated
  (custom/app/services/commerce/order_transitions.rb:22-29); `Automation::CommerceEvents::EVENTS` aliases that constant
  verbatim (custom/app/services/automation/commerce_events.rb:11); the listener defines methods only over it
  (custom/app/listeners/custom/automation_rule_listener.rb:5-7); the frontend hardcodes the same seven
  (app/javascript/dashboard/routes/dashboard/settings/automation/lynomiaAutomation.js:13-21). The whole `Unpaid` row is
  therefore a **condition**, never a trigger — `commerce_payment_status equal_to unpaid`
  (custom/app/services/audience/commerce_condition.rb:20).
- **`update_shipping` is a declared action no provider implements.** It is in `ORDER_ACTIONS`
  (custom/app/models/commerce/action_run.rb:51) and in the policy (action_policy.rb:11), but no capabilities hash ever
  contains the key, so `capability` always answers `{available: false, reason: 'unsupported'}`
  (custom/app/services/commerce/order_actions.rb:127-129), and the Vue `ACTION_ORDER` omits it entirely. Dead
  surface — `PATCH` (remove) or implement, do not advertise.

### 4.2 WooCommerce

The only provider whose writes reach production. The only one with no shipping data at all.

| Capability | Class | Read fidelity | Mechanism | Signed | Justification |
|---|---|---|---|---|---|
| Order created | SUPPORTED_WITH_LIMITATIONS | RELIABLE | signed webhook `order.created` → re-read → diff | **yes** | providers/woocommerce.rb:12; woocommerce/webhook.rb:9-14; order_transitions.rb:49-52. **Limit:** a Read-only API key gets no webhooks — `register_webhooks` catches `AUTH_INVALID`, deletes the secret and records realtime `read_only_key` (providers/woocommerce.rb:105), so such a store gets **no events at all**, only 120 s-cache freshness. Plus the first-read baseline (§2.1). |
| Order status change | SUPPORTED_WITH_LIMITATIONS | RELIABLE | signed webhook `order.updated` → re-read → diff on `s`/`p`/`h` | **yes** | order_transitions.rb:55-56. Core vocabulary is complete (pending/processing/on-hold/completed/cancelled/refunded/failed/checkout-draft, woocommerce/normalizer.rb:17-20); any plugin status collapses to `other`. `order.deleted` names no customer → store-wide invalidation, no refresh (§2.1). Same Read-key limit. |
| Paid | SUPPORTED_WITH_LIMITATIONS | LIMITED | **derived at normalize** from an on-demand read — WooCommerce has no payment field | n/a | woocommerce/normalizer.rb:21,74-81. Requires status ∈ {processing, completed} **and** `date_paid_gmt` present. On-hold (awaiting bank transfer) and not-yet-completed COD both yield `unknown`, so `Customer360.spend` silently omits them (custom/app/services/commerce/customer360.rb:22-23). |
| Unpaid | SUPPORTED_WITH_LIMITATIONS | LIMITED | derived at normalize; **condition only, no trigger** | n/a | woocommerce/normalizer.rb:22. Only `pending` → `unpaid`; `failed` has its own value; on-hold → `unknown`. |
| Shipped | **NOT_AVAILABLE** | NONE | none | n/a | No `STATUSES` entry produces `shipped` and `shipments: []` is hardcoded (woocommerce/normalizer.rb:17-20,35). `commerce_order_shipped` can **never** fire for WooCommerce. |
| Delivered | **NOT_AVAILABLE** | NONE | none | n/a | Same two lines. With no status and no shipments, the derivation Shopify uses cannot apply. |
| Cancelled | SUPPORTED_WITH_LIMITATIONS | RELIABLE | on-demand read (webhook only schedules it) | yes | Explicit `cancelled` status maps 1:1 (woocommerce/normalizer.rb:19). Detection is exact; only event *delivery* is limited (Read-key). |
| Refunded | SUPPORTED_WITH_LIMITATIONS | RELIABLE | on-demand read | yes | Two independent signals: status `refunded`, or `refunds[]` summing to ≥ total (woocommerce/normalizer.rb:19,74-81); partial refunds representable as `partially_refunded`. Both satisfy `commerce_order_refunded` (order_transitions.rb:27). |
| Cart | **NOT_AVAILABLE** | NONE | none | n/a | Doubly absent: no `supports_carts?` override → inherits false (providers/base.rb:87), **and** no `RECOVERY_KEYS` entry (switches.rb:15) so `provider_recovery_enabled?` short-circuits false (:29-31). |
| Abandoned cart | **NOT_AVAILABLE** | NONE | none | n/a | Same. WooCommerce core exposes no merchant-wide abandoned-cart API and no provider method exists. |
| Recovery | **NOT_AVAILABLE** | NONE | none | n/a | `prepare` raises `RECOVERY_DISABLED` unless `AbandonedCarts.offered?` (recovery_messages.rb:45), false for every WooCommerce store. |
| Customer lookup | SUPPORTED_WITH_LIMITATIONS | LIMITED | on-demand API reads | n/a | providers/woocommerce.rb:53-70. Email: `GET /customers?email=` + a broad `GET /orders?search=` re-checked for an exact billing/shipping email. **Phone: order search only** — the Customers API has no phone filter — narrowed then exactly re-checked against E.164. Guests get synthetic `guest:<email>` / `guest:<E.164>` ids. `SEARCH_LIMIT` 20: a customer outside the 20 most recent matching orders is not found. Order-number search works (`searches_orders?` true, :80) but fails on stores with an order-renumbering plugin. |
| Tracking | **NOT_AVAILABLE** | NONE | none | n/a | `tracking: nil` and `shipments: []` hardcoded (woocommerce/normalizer.rb:35); the header at :14-15 says plugin metadata is deliberately not read. `Flows::Nodes::CommerceLookup` therefore always yields empty tracking variables for WooCommerce. |
| Write actions | **NOT_SAFE_FOR_AUTOMATION** | n/a (agent surface: **LIMITED, and the only one live**) | on-demand REST v3 writes over HTTP Basic, sent once, never retried | n/a | **No automation action performs a store write** — the action set is conversation actions plus `send_webhook_event`. Agent-side it is the one production-reachable write surface (PRE_UAT excludes woocommerce; `WOOCOMMERCE_ACTIONS_ENABLED` defaults true, installation_config.yml:559). Supported: `update_order_status` (allow-list only: processing→completed\|on_hold, on-hold→processing), `cancel_order` (pending\|on-hold, restocks, refunds nothing), `refund_full`/`refund_partial` (capped; `gateway` mode only when the gateway reports refund support, else `manual` = **recorded only, no money moves**), `resend_invoice`, `resend_payment_link` (providers/woocommerce/actions.rb:4-14,79-87). Not supported: `update_shipping`. Idempotency is Lynomia's own (`lynomia_action_key` refund meta); WooCommerce has none. Requires `metadata['write_access'] == 'granted'`, proven by a successful webhook creation (providers/woocommerce.rb:25-27). |

### 4.3 Salla

Richest shipment data; no writes; and **`paid` is structurally impossible**, which breaks spend-based targeting.

| Capability | Class | Read fidelity | Mechanism | Signed | Justification |
|---|---|---|---|---|---|
| Order created | SUPPORTED_WITH_LIMITATIONS | RELIABLE | signed app webhook → prefix dispatch → re-read → diff | **yes** | salla/webhook.rb:12-14; salla/webhook_job.rb:13,18. **Limits:** nothing in this repo subscribes Salla store events (`registers_webhooks?` false, base.rb:54; `Commerce::Salla::Installation` handles only `app.*`) — subscription is a Salla Partner Portal action, outside the repo; a missing `SALLA_WEBHOOK_SECRET` makes every delivery 401; `event_customer_ids` reads `data.customer.id` only and the payload shape is marked `VERIFY` (providers/salla.rb:70-73), so any other shape names nobody and drops the whole store's cached orders with no refresh (§2.1). |
| Order status change | SUPPORTED_WITH_LIMITATIONS | RELIABLE | same transport; `status.slug` | **yes** | salla/normalizer.rb:14. Nine slugs map explicitly, a merchant's custom status keeps the slug it is based on, anything else is `other`. Same subscription/payload limits. |
| Paid | **NOT_AVAILABLE** | NONE | n/a | n/a | `payment_status` can return only `unpaid` or `unknown` (salla/normalizer.rb:74-75); the literal `paid` is unreachable. Therefore: `commerce_order_paid` can **never** fire for a Salla store; `Customer360.spend` selects only `payment_status == 'paid'` (customer360.rb:22-23) so Salla spend totals are **always empty**; and the `commerce_spend_<ccy>` audience conditions built from it can never match a Salla-only contact. This single line invalidates every spend-based recipe for Salla. |
| Unpaid | SUPPORTED_WITH_LIMITATIONS | RELIABLE | derived at normalize; **condition only** | n/a | Two explicit signals: `is_pending_payment == true` or slug `payment_pending` (salla/normalizer.rb:74-75). The read is exact; there is no unpaid trigger for anyone. |
| Shipped | SUPPORTED_WITH_LIMITATIONS | RELIABLE | on-demand read + diff | yes | Both `shipped` and `delivering` slugs → `shipped` (salla/normalizer.rb:14). Limited only by the unverified subscription above. |
| Delivered | SUPPORTED_WITH_LIMITATIONS | RELIABLE | on-demand read + diff | yes | Explicit `delivered` slug → `delivered` (salla/normalizer.rb:14). Not derived from shipments, unlike Shopify — which makes Salla the **most trustworthy `delivered` of the four**. |
| Cancelled | SUPPORTED_WITH_LIMITATIONS | RELIABLE | on-demand read | yes | `canceled` → `cancelled` (salla/normalizer.rb:14). |
| Refunded | **NOT_SAFE_FOR_AUTOMATION** | LIMITED | on-demand read | yes | The only path is the order slug `restored` → `refunded` (salla/normalizer.rb:14). `payment_status` can never be `refunded`/`partially_refunded` for Salla, so the second limb of the refund fact (order_transitions.rb:27) never applies, and a partial refund is not representable at all. **Decisive reason for UNSAFE:** whether Salla's `restored` means "refunded" rather than "restored from trash" is unverified against Salla's documentation (§7). A refund-escalation recipe firing on that slug would mis-escalate. |
| Cart | **NOT_AVAILABLE** | (code: LIMITED) | on-demand `GET /carts/abandoned`, cached | n/a | Production-unreachable: PRE_UAT recovery holds `salla` (switches.rb:16) and `SALLA_RECOVERY_ENABLED` defaults false (installation_config.yml:589). See §4.7 for what the code would give if lifted. |
| Abandoned cart | **NOT_AVAILABLE** | (code: LIMITED) | same | n/a | Same gate. |
| Recovery | **NOT_AVAILABLE** | (code: agent-only) | n/a | n/a | Same gate; and by design Lynomia never sends — §5.1. |
| Customer lookup | SUPPORTED_WITH_LIMITATIONS | LIMITED | on-demand `GET /customers?keyword=` | n/a | providers/salla.rb:31-40. Salla's keyword matches mobile, email and name; `SEARCH_LIMIT` 20; kept only on an exact email or exact E.164 (rebuilt from `mobile_code` + `mobile`); **names never match**. **Order-number search: NOT_AVAILABLE** — Salla does not override `searches_orders?` (base.rb:30), so `Commerce::OrderSearch` reports the store `unsupported` without calling it (order_search.rb:30). Salla is the only provider of the four that cannot look up an order by number. |
| Tracking | SUPPORTED_WITH_LIMITATIONS | RELIABLE | **separate on-demand `GET /shipments?order_id=` per shown order** | n/a | providers/salla.rb:101-104. The richest shipment data of the four: 16 statuses map explicitly, every shipment kept, return shipments excluded from the primary, courier names joined. **Cost:** one extra API call per order rendered in the panel. `tracking_url` kept only when Salla says `trackable == true` and the link is https with no userinfo; the order's shipping total is always nil. |
| Write actions | **NOT_AVAILABLE** | NONE | none | n/a | `providers/salla.rb` overrides neither `supports_actions?` nor `write_access_problem` nor `action_snapshot`/`perform_action`, so it inherits false / `'unsupported'` / `NotImplementedError` (base.rb:66,70). `store_blocker` returns `'unsupported'` → `ACTION_UNAVAILABLE` (order_actions.rb:104); the stores JSON reports `order_actions_status: 'unsupported'`. The class contains GET requests only. |

### 4.4 Zid

**The best data of the four and the worst transport.** Finest-grained event set (a dedicated payment-status topic),
explicit `payment_status`, both `cancelled` spellings, a real customer filter on carts — all behind an unsigned,
unverified webhook (§2.4).

| Capability | Class | Read fidelity | Mechanism | Signed | Justification |
|---|---|---|---|---|---|
| Order created | **NOT_SAFE_FOR_AUTOMATION** | RELIABLE | **unsigned** webhook `order.create` → re-read → diff | **NO** | zid/webhooks.rb:9; zid/webhook.rb:8-14. Registration is done by Lynomia with the store's own tokens (zid/webhooks.rb:23), and re-authorizing never duplicates subscriptions. But the transport is HTTP Basic, not a signature, and the field handing Zid the credentials is `VERIFY(zid-webhook-auth)` (zid/webhooks.rb:42-48) — so we cannot assert deliveries arrive at all. |
| Order status change | **NOT_SAFE_FOR_AUTOMATION** | RELIABLE | **unsigned** webhooks `order.status.update` **and** `order.payment_status.update` | **NO** | zid/webhooks.rb:9 — the only provider with a dedicated payment-status topic. Status from `order_status.code` compared lowercased (the orders API writes `indelivery`, webhook conditions `inDelivery`); new/preparing/ready collapse to `processing`; `reversed` and merchant statuses → `other` (zid/normalizer.rb:16-19). Data excellent, transport unproven. |
| Paid | **NOT_SAFE_FOR_AUTOMATION** | **RELIABLE** | explicit `payment_status` field on an on-demand read | **NO** (trigger) | zid/normalizer.rb:20,34 — `paid` → `paid`, never inferred from order status; `voided` and unknown → `unknown`. **This is the single most reliable `paid` of the four providers** and it feeds `Customer360.spend` correctly. Classed UNSAFE only because the *trigger* transport is §2.4. As an audience condition or panel fact it is RELIABLE. |
| Unpaid | SUPPORTED_WITH_LIMITATIONS | **RELIABLE** | explicit `payment_status` `pending` → `unpaid`; **condition only** | n/a | zid/normalizer.rb:20. Not webhook-dependent as a condition, so not downgraded. No unpaid trigger exists for anyone. |
| Shipped | **NOT_SAFE_FOR_AUTOMATION** | RELIABLE | read `order_status.code` `indelivery` → `shipped` | **NO** (trigger) | zid/normalizer.rb:17,22. Same code drives the synthetic shipment status `in_transit`. |
| Delivered | **NOT_SAFE_FOR_AUTOMATION** | RELIABLE | read explicit `delivered` code | **NO** (trigger) | zid/normalizer.rb:17,22. Explicit, not derived — better than Shopify's. |
| Cancelled | **NOT_SAFE_FOR_AUTOMATION** | RELIABLE | on-demand read | **NO** (trigger) | Both spellings handled, `cancelled` and `canceled` (zid/normalizer.rb:17-18) — which the actions file flags as an unresolved doc discrepancy on the **write** side. |
| Refunded | **NOT_SAFE_FOR_AUTOMATION** | LIMITED | on-demand read | **NO** (trigger) | Only `payment_status` `refunded` is read (zid/normalizer.rb:20); the order status `reversed` deliberately maps to `other` and no credit-note/reverse-order list is read anywhere. Partial refunds are not representable for Zid. |
| Cart | **NOT_AVAILABLE** | (code: **RELIABLE** — best of the four) | on-demand `GET /managers/store/abandoned-carts` with a real `customer_id` filter | n/a | Production-unreachable: PRE_UAT recovery holds `zid` (switches.rb:16); `ZID_RECOVERY_ENABLED` defaults false (installation_config.yml:595). §4.7. |
| Abandoned cart | **NOT_AVAILABLE** | (code: **RELIABLE**) | same, plus a per-cart detail endpoint | n/a | Same gate. |
| Recovery | **NOT_AVAILABLE** | (code: agent-only) | n/a | n/a | Same gate. Zid's own notification/reminder API is explicitly never used (providers/zid/carts.rb:4). |
| Customer lookup | SUPPORTED_WITH_LIMITATIONS | LIMITED | on-demand `GET /managers/store/orders?search_term=` | n/a | providers/zid.rb:31-39. **There is no customers endpoint in use at all** — candidates are taken from orders' customers and kept only on an exact email or E.164 match; `SEARCH_LIMIT` 20. Marketplace orders (`is_marketplace_order`) yield no candidate, and any masked value containing `*` is never read as an email or phone, so **those customers can never be matched or linked** (zid/normalizer.rb:10-12). Order-number search works (`searches_orders?` true, zid.rb:55). |
| Tracking | SUPPORTED_WITH_LIMITATIONS | LIMITED | read inline from the order payload, **no extra call** | n/a | zid/normalizer.rb:22,67-99 — number from `tracking.number`/`tracking_number`, url from `url`/`tracking_url`, https only. **Limit stated in the code (zid/normalizer.rb:21):** Zid documents no shipment status of its own, so the shipment's status is derived from the **order** code — only `indelivery`→`in_transit` and `delivered`→`delivered`, everything else `other`. At most one shipment per order; shipping total always nil; no admin order URL exists for Zid at all (:35). |
| Write actions | **NOT_AVAILABLE** | n/a | on-demand `POST …/change-order-status`, sent once, never retried | n/a | Production-unreachable: PRE_UAT actions holds `zid` (switches.rb:16); `ZID_ACTIONS_ENABLED` defaults false. In code: the **only** action is `update_order_status`, and only two transitions — ready→shipped (`indelivery`) and indelivery→delivered (providers/zid/actions.rb:4). Moving into `ready` is deliberately not offered (it needs a pickup location Lynomia does not choose); `cancel_order` unsupported (the cancelled/canceled doc discrepancy, :6); refunds unsupported (Zid refunds via reverse orders, :7). No readable scope list, so write capability is **optimistic**: `write_access_problem` returns nil until a 403 flips `metadata['write_access']` to `missing_scope` (providers/zid.rb:99). No provider idempotency — a lost answer is settled by reading the status back after 5 minutes. |

### 4.5 Shopify

Signed transport, strongest refund data, and the one provider where **`delivered` can silently never arrive**.

| Capability | Class | Read fidelity | Mechanism | Signed | Justification |
|---|---|---|---|---|---|
| Order created | SUPPORTED_WITH_LIMITATIONS | RELIABLE | signed webhook `orders/create` → re-read → diff | **yes** | shopify/webhook.rb:9,18-19 — HMAC over the raw body, shop domain validated, `X-Shopify-Webhook-Id` required (400 otherwise) and used for dedup. **Limit:** nothing in the repo creates the subscriptions — topics are app-specific, declared in `shopify.app.toml` and deployed with the Shopify CLI (base.rb:54; docs/commerce/shopify.app.toml.example). Guests keyed `guest:<email>` from the order email when no customer is present. |
| Order status change | SUPPORTED_WITH_LIMITATIONS | RELIABLE | signed webhook `orders/updated` → re-read → diff | **yes** | Only `orders/updated` exists — there is no status-specific topic (shopify/webhook.rb:9). **The limitation the code itself states:** a tracking-only change that does not update the order **arrives with no event at all**, so a carrier moving from in-transit to delivered may not trigger a refresh until the 120 s cache expires and someone reads. Eight fulfillment statuses map to processing/on_hold/shipped; `RESTOCKED` and `REQUEST_DECLINED` → `other`; `closed` (archived) deliberately not read (shopify/normalizer.rb:5-7,15-18). |
| Paid | SUPPORTED_WITH_LIMITATIONS | **RELIABLE** | `displayFinancialStatus` `PAID` from the GraphQL order read | yes | shopify/normalizer.rb:19-22. Never inferred from fulfillment status. Together with WooCommerce this is the safe basis for a paid recipe. |
| Unpaid | SUPPORTED_WITH_LIMITATIONS | LIMITED | read `displayFinancialStatus`; **condition only** | n/a | Only `PENDING` → `unpaid`. `AUTHORIZED`, `VOIDED` and `EXPIRED` map to `unknown` because they have no neutral equivalent (shopify/normalizer.rb:8-9,19-22) — so an authorised-but-uncaptured order reads as payment-**unknown**, not unpaid, even though the cancel action treats `AUTHORIZED` and `EXPIRED` as cancellable-unpaid. A recipe filtering on `unpaid` will miss authorised orders. |
| Shipped | SUPPORTED_WITH_LIMITATIONS | RELIABLE | read `displayFulfillmentStatus` `FULFILLED` | yes | shopify/normalizer.rb:17,65-71 — unless all shipments are delivered, which promotes it to `delivered`. |
| Delivered | **NOT_SAFE_FOR_AUTOMATION** | LIMITED | **derived** from read: status `shipped` **and** ≥1 non-cancelled shipment **and** every non-cancelled shipment `DELIVERED`/`PICKED_UP` | yes | shopify/normalizer.rb:23-28,65-71; providers/shopify.rb:21-23,44-46. Shopify has no `delivered` order status, so it is derived — and the derivation has two hard bounds: the query reads at most `FULFILLMENT_LIMIT` 10 fulfillments × `TRACKING_LIMIT` 5 tracking numbers, so **a larger order can read as `shipped` forever**; and because a tracking-only change emits no `orders/updated`, the promotion lags until someone reads. A "when delivered" recipe on Shopify may fire very late or never. Do not ship it. |
| Cancelled | SUPPORTED_WITH_LIMITATIONS | RELIABLE | read `cancelledAt` | yes | shopify/normalizer.rb:66 — `cancelledAt` present wins over every other status. |
| Refunded | SUPPORTED_WITH_LIMITATIONS | **RELIABLE** | read `displayFinancialStatus` | yes | `REFUNDED` and `PARTIALLY_REFUNDED` both map explicitly and both satisfy the refund fact (shopify/normalizer.rb:19-22; order_transitions.rb:27). The action path additionally reads `totalRefundedSet`, suggested-refund maxima and the last 20 refunds with notes — **the richest refund state of the four** — but only on the action path, not the panel read. |
| Cart | **NOT_AVAILABLE** | (code: LIMITED) | on-demand GraphQL `abandonedCheckouts` | n/a | Production-unreachable: PRE_UAT recovery holds `shopify` (switches.rb:16); `SHOPIFY_COMMERCE_RECOVERY_ENABLED` defaults false (installation_config.yml:601). §4.7. |
| Abandoned cart | **NOT_AVAILABLE** | (code: LIMITED) | same | n/a | Same gate. |
| Recovery | **NOT_AVAILABLE** | (code: agent-only) | n/a | n/a | Same gate. Note a Shopify-specific cost if ever lifted: `recovery_hosts` triggers an extra GraphQL call on **every** URL check, because the allowed hosts are the myshopify host plus the shop's primary domain read live (providers/shopify.rb:122). |
| Customer lookup | SUPPORTED_WITH_LIMITATIONS | LIMITED | on-demand GraphQL `customers(query:)` | n/a | providers/shopify.rb:8-13,24-30. `SEARCH_LIMIT` 20; kept only on exact `defaultEmailAddress` or exact E.164 `defaultPhoneNumber`. Limits stated in the code: **names are never requested or matched** (protected customer data), so `Customer#name` is always nil for Shopify; the orders API has no phone filter so **guests are discoverable by email only**; and without `read_all_orders` Shopify returns only the **last 60 days** of orders — while the requested scopes are `read_customers` + `read_orders` only. Order-number search works (`searches_orders?` true, :102). |
| Tracking | SUPPORTED_WITH_LIMITATIONS | LIMITED | read inline from the same GraphQL order query, **no extra call** | n/a | shopify/normalizer.rb:23-28,73-97. One shipment per tracking number, or one per fulfillment without tracking; 15 carrier statuses map explicitly; `tracking_url` kept only when https with no userinfo. Same 10 × 5 bound and the same no-webhook-on-tracking-change freshness gap as `delivered`. |
| Write actions | **NOT_AVAILABLE** | n/a | on-demand Admin GraphQL mutations pinned to `2026-07`, sent once | n/a | Production-unreachable: PRE_UAT actions holds `shopify` (switches.rb:16); `SHOPIFY_COMMERCE_ACTIONS_ENABLED` defaults false. In code, two families only: `cancel_order` (`orderCancel`, restock true, refund false, customer not notified; available **only** when not already cancelled, financial status ∈ {PENDING, AUTHORIZED, EXPIRED} and fulfillment status `UNFULFILLED`; completes as a Shopify Job so the run stays `running` until a read shows `cancelledAt`) and `refund_full`/`refund_partial` (`refundCreate` through the single suggested transaction — explicitly **unavailable with reason `multiple_payments` when more than one suggested transaction exists**, so split payments are refused, providers/shopify/actions.rb:112). `update_order_status`, `resend_*` and `update_shipping` are unsupported: Shopify has no settable order status. Requires the literal `write_orders` in the stored scope, granted only by an explicit administrator reconnect (providers/shopify.rb:126). |

### 4.6 Where the agent surface is better than the recipe class

Do not let the matrix talk you out of the panel. These capabilities are genuinely good **today**, for an agent looking
at a conversation, or for the `commerce_lookup` Flow Builder node (which is entered from a customer message, not from a
store event — a path with none of §2.2's problems):

| Capability | Recipe class | Agent/flow reality |
|---|---|---|
| Zid `paid` / `unpaid` / `shipped` / `delivered` / `cancelled` | NOT_SAFE_FOR_AUTOMATION | Explicit provider fields, exact mapping. The best order-state data of the four providers. |
| Salla `delivered`, Salla tracking | SUPPORTED_WITH_LIMITATIONS | Explicit `delivered` slug; 16 shipment statuses; every shipment kept; couriers named. |
| Shopify `refunded` | SUPPORTED_WITH_LIMITATIONS | Refund list, notes and suggested maxima on the action path. |
| WooCommerce write actions | NOT_SAFE_FOR_AUTOMATION | The one live write surface in production, under a real policy. |
| All four, `unpaid` | SUPPORTED_WITH_LIMITATIONS (condition only) | Works as an audience/flow condition: `commerce_payment_status equal_to unpaid` (audience/commerce_condition.rb:20). |

### 4.7 What the cart code would give if PRE_UAT were lifted

Conditional, not current. Useful only for sequencing the UAT. Classes here are **hypothetical** and assume
`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` plus the per-provider flags are on.

| Provider | Hypothetical class | Why |
|---|---|---|
| Zid | SUPPORTED_RELIABLY | The only provider that can ask for **one customer's** carts (`customer_id` filter, providers/zid.rb:66), plus a per-cart detail endpoint giving product names (:73-81), plus an explicit recovered signal — `phase == 'completed'` or an `order_id` (providers/zid/carts.rb:43-46). Caveat: `cart_access_problem` is hardcoded nil (zid.rb:61) so a store missing `abandoned_carts.read` fails at the API instead of reporting `PERMISSION_DENIED`. |
| Shopify | SUPPORTED_WITH_LIMITATIONS | `abandonedCheckouts` works but has **no customer filter**, so the recent page is read and matched locally; identity is the customer GID **only** — email and phone are hardcoded nil for protected-customer-data reasons (providers/shopify/carts.rb:51), so **a guest abandoned checkout can never match a contact**. |
| Salla | NOT_SAFE_FOR_AUTOMATION | Unfiltered most-recent 30-cart page (providers/salla.rb:60-62); `abandoned_cart(id)` is a linear scan of that same page, returning NOT_FOUND past position 30 (:64-66); `status` hardcoded `'abandoned'` for everything listed (salla/carts.rb:21) so recovered is inferable only from disappearance; items carry quantities but no names; the list path and `carts.read` scope are both marked `VERIFY` in the code. |
| WooCommerce | NOT_AVAILABLE | No cart code exists at all, and no `RECOVERY_KEYS` entry to lift. |

---

## 5. The abandoned-cart decision

### 5.1 Verdict: no recipe is possible today

**NO.** Verified by the inventory and re-verified independently by the `abandoned-cart` verifier — verdict
**CONFIRMED**, every load-bearing claim upheld on all four axes. This is not a "needs design work" answer; there is no
object to build a recipe out of.

| Missing piece | Evidence of absence |
|---|---|
| **No cart table** | `db/schema.rb` has exactly four commerce tables — `commerce_action_runs`:809, `commerce_contact_metrics`:837, `commerce_customer_links`:855, `commerce_stores`:870. A grep for `cart` in the schema returns **zero** lines. `custom/db/migrate/` holds 13 migrations, none cart-related. A cart is a `Data.define` value object (custom/app/services/commerce/abandoned_cart.rb:12-15) held in **Redis only**, fresh 120 s and kept 24 h (cache.rb:8-9) — and the cart cache is **deleted, not marked stale**, on every order and cart webhook (realtime.rb:33,47,54-57), so even the Redis copy cannot serve as a prior state to diff. |
| **No abandonment transition** | The only transition engine is orders-only (`Commerce::OrderTransitions`, FACTS :22-28, EVENTS :29) and its diff needs a persisted prior state that exists only as `commerce_contact_metrics.order_states`. A cart's `status` is assigned once per read straight off the provider payload: shopify/carts.rb:53, zid/carts.rb:43-46, salla/carts.rb:21 (hardcoded). No dwell-time or age threshold is applied at normalization — the only age logic is display-side (`MAX_AGE` 30 days, abandoned_carts.rb:15; the `AGES` filter at accounts/commerce/carts_controller.rb:10). |
| **No trigger** | `Automation::CommerceEvents::EVENTS` is a verbatim alias of the order constant (commerce_events.rb:11); `event?` (:14) is the sole membership test; the listener `define_method`s only over that list (custom/app/listeners/custom/automation_rule_listener.rb:5-7); the rule model delegates to it (custom/app/models/custom/automation_rule.rb:22-24); the frontend hardcodes the same seven (lynomiaAutomation.js:13-21). A repo-wide grep for `commerce_cart`/`cart_abandoned`/`cart\.abandon` across .rb/.js/.vue/.json/.yml returns **zero** hits. And `dispatch` has one call site, reached only from order reads (§2.2). |
| **No condition** | `Audience::CommerceCondition::FIELDS` is exhaustively store, provider, orders_count, last_purchase_at, active_order, order_status, payment_status, shipment_status plus `commerce_spend_<ccy>` (custom/app/services/audience/commerce_condition.rb:14-24). All its SQL joins `commerce_customer_links` to `commerce_contact_metrics`, neither of which holds cart data, so **a cart condition is not even expressible**. No cart node or store-event entry exists in Flow Builder either. |
| **Nothing to fire it on anyway** | §2.3: carts reach zero stores in production for all four providers. |
| **Recovery is human-driven by design** | `prepare` returns message *ingredients* only — url, first name, total, currency, store, items count (recovery_messages.rb:92-95) — and creates a PENDING ActionRun; it never creates a Message. The text is composed **in the browser** from two i18n templates and inserted into the reply box; the agent sends it. `Commerce::RecoveryListener` only observes the agent's outgoing message to flip the run to succeeded. There is no scheduled or bulk send anywhere. |

A trap to close first: because `event_name` has no inclusion validation, **an AutomationRule with
`event_name: 'commerce_cart_abandoned'` can be persisted today via the API.** It would simply never fire — no dispatcher
emits the name and no listener method exists. The gap is purely emission-side, and the failure is silent.

### 5.2 The single smallest new primitive that would be required

**NEW PRIMITIVE REQUIRED — one emission-side primitive, three parts:**

> A **persisted prior cart state** per store customer link, plus a `Commerce::CartTransitions` that diffs two
> normalized cart reads into a provider-neutral `commerce_cart_abandoned`, handed to the **existing**
> `Automation::CommerceEvents.dispatch`, with the event name added to the one constant the rule model, the listener and
> the frontend all derive from.

What makes it genuinely small — and this is the part that is easy to get wrong in a plan:

- **No new provider call is needed.** A conversation-free, account-wide, cached server-side cart poll already exists:
  `Commerce::Providers.for(store).abandoned_carts(limit: QUEUE_PER_STORE)` behind the `:cart_queue` cache
  (custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb:37-43). The read is already written, bounded and
  cached.
- **No new dispatch, listener, condition engine, execution log or dedup is needed.** `dispatch` already handles the
  feature flag, the "is there an active rule" check and the per-event-id claim (commerce_events.rb:16-24), and the
  listener already resolves the conversation and runs conditions and actions.
- **The event vocabulary is one constant.** Adding a member to it propagates to `event?`, the listener's
  `define_method` loop and the rule model automatically — the only non-derived copy is the hardcoded frontend list
  (lynomiaAutomation.js:13-21).

**Reliability by provider, if built:**

| Provider | Verdict for the primitive |
|---|---|
| **Zid** | Reliable. Customer-filtered list + per-cart detail + an explicit recovered signal. Build it here first, or not at all. |
| **Shopify** | Partially reliable — linked customers only. Email and phone are hardcoded nil, so **guest checkouts can never match a contact**. |
| **Salla** | Not reliably. Unfiltered 30-row page, linear-scan lookup, hardcoded status, path and scope marked `VERIFY`. |
| **WooCommerce** | Impossible. No cart API, no cart code, no `RECOVERY_KEYS` entry. |

### 5.3 What it would cost

Not a design — the requirement list, for approval. **I am not proposing a migration.**

| Cost item | Requirement |
|---|---|
| Durable prior state | A persisted cart-state store analogous to `commerce_contact_metrics.order_states` (db/schema.rb:850). **This requires a migration. Stated as a requirement and left for approval.** Redis cannot serve: the cart cache is *deleted* on every webhook (realtime.rb:54-57). |
| Something to run the read | There is **no commerce polling job of any kind**. `Commerce::ActionSweepJob` (config/schedule.yml:80-83) is the only commerce cron and reads no store data. A new scheduled read — per account, per store, bounded like the queue read — is required, with its own rate and cost profile against three provider APIs. |
| Abandonment definition | A dwell threshold must be invented and owned as a product rule. None exists: normalization applies no age logic and the only existing age filters are display-side. |
| Frontend + i18n | The hardcoded `COMMERCE_EVENTS` list, the rule-builder label and the recipe catalogue entry. |
| **A provider UAT and a PRE_UAT code change** | `switches.rb:16` must lose the provider, which the file states is "a reviewed code change", and the per-provider `*_RECOVERY_ENABLED` flag must be turned on. Without this the primitive fires for nobody. |
| **A second, separate product decision** | §5.4. |

### 5.4 What the primitive would NOT buy — read this before approving it

**A `commerce_cart_abandoned` trigger alone cannot message the customer.** `Custom::AutomationRule` bans
`send_message` and `send_attachment` on **every** commerce trigger (custom/app/models/custom/automation_rule.rb:9,
enforced :38-39), for a stated reason: a store event is not a customer message, and a WhatsApp conversation may be
outside its 24-hour window. The trigger buys label / assign / priority / private note / `send_webhook_event` — internal
actions only.

So an abandoned-cart **recovery** feature — the thing anyone actually wants — needs the primitive **and** a separate
decision to allow customer-facing messaging on a store-driven trigger, with the WhatsApp 24-hour window and template
rules resolved. Scope the cart primitive as *internal routing* or not at all; an "automatic cart recovery message" is
two approvals away, not one.

---

## 6. Recipe-by-recipe verdict

Current catalogue: seven recipes at app/javascript/dashboard/recipes/automationRecipes.js:74, 90, 106, 123, 140, 165,
198 — `commerce_new_order_routing`, `commerce_order_shipped_label`, `commerce_refund_escalation`,
`commerce_event_webhook`, `vip_audience_priority`, `high_value_spend_routing`, `active_order_routing`. **None is
cart-related**, and the file's own header records that the seven `commerce_order_*` transitions are the whole set.

| Recipe | Class | Decision and the blocking or enabling fact |
|---|---|---|
| `commerce_event_webhook` | **REUSE** | **Ship it as the flagship.** The only commerce action carrying commerce data out of the platform (custom/app/services/custom/automation_rules/action_service.rb:7-14). Honest on every provider; the read-driven delay is acceptable because the consumer is a workflow tool, not a customer. |
| `commerce_new_order_routing` | **EXTEND** | Keep, but fix the copy: it is suppressed on a link's first read (order_transitions.rb:39,49-52), so the very first order of a new contact routes nothing. Say so in the recipe description. |
| `commerce_refund_escalation` | **EXTEND** | Keep for WooCommerce and Shopify (two signals each, partial refunds representable). Exclude Salla (`restored` semantics unverified) and Zid (unsigned transport, partial refunds not representable). The recipe must name the providers it is true for. |
| `commerce_order_shipped_label` | **PATCH** | Ships a false promise today: WooCommerce can **never** reach `shipped` (woocommerce/normalizer.rb:17-20,35), and WooCommerce is the only provider on by default. Either scope the recipe to Salla/Zid or remove it. |
| A `commerce_order_paid` → VIP recipe | **EXTEND** | Build for WooCommerce and Shopify. Must not be offered for Salla: `paid` is structurally unreachable there (salla/normalizer.rb:74-75), which also empties `commerce_spend_<ccy>` — so `high_value_spend_routing` is silently dead on Salla-only accounts too. |
| A `commerce_order_delivered` recipe | **DO NOT CREATE** | WooCommerce NOT_AVAILABLE, Shopify NOT_SAFE_FOR_AUTOMATION (derived, bounded at 10 × 5, no webhook on tracking-only change). True only for Salla and Zid, and Zid's transport is unproven. Not a cross-provider recipe. |
| Any customer-messaging commerce recipe | **DO NOT CREATE** | Rejected at validation (custom/app/models/custom/automation_rule.rb:38-39). |
| Any recipe performing a store write | **DO NOT CREATE** | No automation action writes to a store; writes are agent-UI only, administrator-gated for cancel/refund (action_policy.rb:22-29), sent once, never retried. |
| **Abandoned cart / cart recovery** | **DO NOT CREATE** → **NEW PRIMITIVE REQUIRED** | §5. No table, no transition, no trigger, no condition, and production-unreachable for all four providers. |
| `update_shipping` anywhere | **DO NOT CREATE** | Declared in three places, implemented by nobody; always answers `unsupported` (order_actions.rb:127-129). PATCH: remove the dead declaration. |

---

## 7. Defects and unverified claims in this area

| Item | Class | Detail |
|---|---|---|
| `event_name` is unvalidated | **PATCH** | No inclusion validation on `app/models/automation_rule.rb` (DB `NOT NULL` only, db/schema.rb:313). Any string saves; the rule silently never fires. Blocks safe authoring of any new commerce trigger. |
| `supports_realtime?` is a dead predicate | **PATCH** (cosmetic) | Four overrides (woocommerce.rb:16, salla.rb:47, zid.rb:57, shopify.rb:110), zero readers. Setting it false changes nothing. |
| `update_shipping` declared, never implemented | **PATCH** | action_run.rb:51, action_policy.rb:11, i18n — no provider capabilities hash contains the key. |
| `customer_order_url` declared, never populated | **PATCH** (cosmetic) | A member of `Commerce::Order` passed literally nil by all four normalizers (woocommerce/normalizer.rb:35, salla, zid/normalizer.rb:35, shopify). |
| Zid / Shopify cart scope not pre-checked | **PATCH** | `cart_access_problem` hardcoded nil (zid.rb:61, shopify.rb:116), so `PERMISSION_DENIED` can never be reported and a store missing the scope fails at the API with a generic error. Salla does check (salla.rb:54-57). Only matters once PRE_UAT lifts. |
| Cart-status doc comment overstates | **PATCH** (doc) | custom/app/services/commerce/abandoned_cart.rb:4 lists four statuses (abandoned / recovered / expired / unknown); only `abandoned` and `recovered` are ever assigned. `docs/commerce/30-abandoned-carts.md` §1 is correct — the code comment is the stale one. |
| **UNVERIFIED** — Zid webhook auth field | — | `VERIFY(zid-webhook-auth)`, zid/webhooks.rb:42-48. If Zid ignores the `authentication` field, every Zid delivery is 401 and Zid realtime does not work at all, downgrading every Zid webhook cell to effectively NOT_AVAILABLE. **Resolve this in a live Zid UAT before any Zid recipe is promised.** |
| **UNVERIFIED** — Salla store-event payload shape | — | `VERIFY(salla-store-events)`, providers/salla.rb:70-73. If `data.customer.id` is absent or nested differently, every Salla event names nobody: correctness is preserved (store-wide invalidation) but there are **no automation events and no live panel updates**. |
| **UNVERIFIED** — Salla `restored` = refunded | — | salla/normalizer.rb:14 maps it so; whether Salla means "refunded" rather than "restored from trash" is not confirmed against Salla's documentation. Sole reason Salla `refunded` is classed NOT_SAFE_FOR_AUTOMATION. |
| **UNVERIFIED** — Salla `/carts/abandoned` path and `carts.read` scope | — | Marked `VERIFY` in both the provider (salla.rb:53) and the carts class. |
| **UNVERIFIED** — Shopify `@idempotent` on `refundCreate` | — | The code flags the directive as present in Shopify's docs but absent from the introspected schema it was built against. If rejected, the mutation errors rather than deduplicating; the note-based reconciliation is the real safety net. |
| **UNVERIFIED** — WooCommerce `POST /orders/{id}/actions/send_order_details` | — | Called unconditionally for `resend_invoice`/`resend_payment_link` with no version check; documented as WooCommerce 9.8+. An older store presumably 404s into a NOT_FOUND failure — graceful but untested. |
| No specs executed | — | This document is static analysis of the repo at `6c381e96`. Specs exist for this area (`spec/services/commerce/abandoned_carts_spec.rb`, `abandoned_cart_adapters_spec.rb`, `realtime_carts_spec.rb`, `recovery_messages_spec.rb`, `recovery_url_spec.rb`, and controller specs) and were not run. |

**One fabrication to never repeat:** `quality_score` does not appear anywhere in this repository. It was invented by an
inventory pass and must not be cited in any commerce or WhatsApp document.
