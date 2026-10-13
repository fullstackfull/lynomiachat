---
agent: 043
scope: Commerce core (provider-agnostic): domain models, capability matrix, store lifecycle and health, lookup, order actions, cart normalizer and state, Customer 360, commerce analytics, and the Commerce::Error code list
confidence: high
---

## 1. What the feature is

Lynomia Commerce connects an online store to the account and shows the store's view of the person in the
conversation. It is deliberately **not** a commerce database. There is no order table, no scheduled import and
no revenue ledger: a store is read when something asks it a question, the answer is normalised into Lynomia's
own shapes and kept in Redis for 120 seconds (`Commerce::Cache::FRESH_FOR`,
`custom/app/services/commerce/cache.rb:8`), and a stale answer up to 24 hours old is served, labelled with its
fetch time, when the store cannot be reached (`cache.rb:9-10`, `:24-26`).

Four provider adapters sit behind one contract. The whole product above them is provider-agnostic.

**The domain models.** Two groups. The *value objects* are provider-neutral `Data` types that the API, the cache
and the UI use, so raw provider JSON never leaves an adapter:

| Shape | File | What it is |
|---|---|---|
| `Commerce::Order` | `custom/app/services/commerce/order.rb:13` | the only order shape; 11 statuses (`pending processing on_hold shipped delivered completed cancelled refunded failed draft other`), 7 payment statuses, decimal-string totals, items, shipping, shipments, tracking, admin/customer URLs |
| `Commerce::Customer` | `custom/app/services/commerce/customer.rb:3` | a candidate store customer; emails downcased, phones E.164, so matching is exact comparison |
| `Commerce::AbandonedCart` | `custom/app/services/commerce/abandoned_cart.rb:12` | cart as read now; cached in Redis only, never in Postgres |
| `Commerce::CartEvent` | `custom/app/services/commerce/cart_event.rb:17` | the canonical cart lifecycle event (see §1 cart state below) |
| `Commerce::ActionSnapshot` | `custom/app/services/commerce/action_snapshot.rb:11` | order read now + opaque `version` digest + per-action capabilities + in-memory `facts` |
| `Commerce::ActionResult` | `custom/app/services/commerce/action_result.rb:7` | `succeeded / running / failed / unknown` with a Lynomia `message_code`, never the store's error text |
| `Commerce::Error` | `custom/app/services/commerce/error.rb:3` | the one error class; see §4 |

The *persisted* models are five tables, none of which holds an order:

| Model | Table | Purpose |
|---|---|---|
| `Commerce::Store` | `commerce_stores` | one connected store; `credentials` serialised JSON then `encrypts`, excluded from `serializable_hash` (`custom/app/models/commerce/store.rb:47-48`, `:63-65`); unique on `(provider, external_store_id)` so one store belongs to one account |
| `Commerce::StoreHealth` | `commerce_store_health` | a one-row-per-store operational **snapshot**, not a history (`custom/app/models/commerce/store_health.rb:1-17`) |
| `Commerce::CustomerLink` | `commerce_customer_links` | the store customer a contact was matched to; `external_customer_id` deterministically encrypted, `"guest:<email or E.164>"` for guest checkouts (`custom/app/models/commerce/customer_link.rb:22-26`, `:39`) |
| `Commerce::ContactMetric` | `commerce_contact_metrics` | what the last read of a link's orders adds up to, so audience SQL never calls a store; "visible", never lifetime (`custom/app/models/commerce/contact_metric.rb:1-8`) |
| `Commerce::ActionRun` | `commerce_action_runs` | one requested order action or prepared recovery message; the idempotency record and audit anchor (`custom/app/models/commerce/action_run.rb:35-47`) |
| `Commerce::Cart` | `commerce_carts` | the durable cart lifecycle; two states only (`custom/app/models/commerce/cart.rb:17-21`) |

**The provider capability matrix is declared in code, on the adapter class.** `Commerce::Providers::Base`
(`custom/app/services/commerce/providers/base.rb`) is the whole contract: reads, the order actions, realtime and
carts. Capability is expressed as class predicates that default to the conservative answer and are overridden
per provider. There is no capability table, no YAML, no database column — the adapter class *is* the matrix, and
everything downstream (`Commerce::StoreHealth.webhooks?` at `store_health.rb:81-83`, `Commerce::OrderActions`,
`Commerce::AbandonedCarts.offered?`, the stores jbuilder) reads it rather than keeping a second list.

| Declaration | Base | Woo | Salla | Zid | Shopify |
|---|---|---|---|---|---|
| `self.enabled?` | `true` (`base.rb:6`) | true | `Salla::Config.enabled?` (`salla.rb:18`) | `Zid::Config.enabled?` (`zid.rb:18`) | `Shopify::Config.enabled?` (`shopify.rb:60`) |
| `self.searches_orders?` | `false` (`base.rb:30`) | true (`woocommerce.rb:80`) | false | true (`zid.rb:57`) | true (`shopify.rb:102`) |
| `self.supports_realtime?` | `false` (`base.rb:50`) | true (`woocommerce.rb:16`) | true (`salla.rb:47`) | true (`zid.rb:59`) | true (`shopify.rb:110`) |
| `self.registers_webhooks?` | `false` (`base.rb:54`) | true (`woocommerce.rb:18`) | false | false | false |
| `self.supports_actions?` | `false` (`base.rb:66`) | true (`woocommerce.rb:20`) | false | true (`zid.rb:99`) | true (`shopify.rb:112`) |
| `write_access_problem` | `'unsupported'` (`base.rb:70`) | from the key (`woocommerce.rb:25`) | unsupported | `metadata['write_access']` (`zid.rb:101`) | from scopes (`shopify.rb:126`) |
| `self.supports_carts?` | `false` (`base.rb:87`) | false | true (`salla.rb:49`) | true (`zid.rb:61`) | true (`shopify.rb:114`) |
| `cart_access_problem` | `'unsupported'` (`base.rb:90`) | unsupported | scope check (`salla.rb:54`) | `nil` (`zid.rb:63`) | `nil` (`shopify.rb:116`) |
| `recovery_hosts` | store host (`base.rb:100`) | store host | `+ salla.sa` (`salla.rb:68`) | `+ zid.store` (`zid.rb:85`) | shop + primary domain (`shopify.rb:122`) |

Two caveats a reader must not miss. `registers_webhooks?` is narrower than "has webhooks": only WooCommerce has
subscriptions Lynomia creates with the store's own credentials via `Commerce::WebhookRegistrationJob`
(`custom/app/services/commerce/store_connection.rb:120-122`). Zid registers from its authorization flow instead
(`custom/app/services/commerce/zid/authorization.rb:19`), and Salla and Shopify from their app setup
(`base.rb:53`). And the class predicates are only the **provider's** half: a second, installation-level gate
decides what is actually on.

**The installation gate** is `Commerce::Switches` (`custom/app/services/commerce/switches.rb`), read from Super
Admin → Settings → Lynomia Commerce, else ENV, else a default (`:43-47`). `COMMERCE_ACTIONS_ENABLED` defaults on
and per-provider action switches default **on for WooCommerce only** (`:23`); recovery switches default **off**
for all (`:30`), and WooCommerce has no recovery key at all (`:15`). On top of both sits
`PRE_UAT = { actions: %w[salla zid shopify], recovery: %w[salla zid shopify] }` (`:16`), which blocks those
providers regardless of any switch unless the ENV-only `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is set — "staging and
simulated E2E runs only, never production" (`:10-11`). **Net production state today: order actions exist only
for WooCommerce, and abandoned carts / recovery messages exist for nobody.**

**Store connection lifecycle** is `Commerce::StoreConnection` (`custom/app/services/commerce/store_connection.rb`).
Credentials are saved only once verified — by `adapter.health` in `#connect` (`:18`) or, for Salla, by a signed
installation confirmed with Salla — so a store is never persisted `active` with credentials that do not work.
`Commerce::Store` has four statuses (`store.rb:42`): `active`, `disabled`, `needs_reauth`, `disconnected`.
Transitions: `#connect`/`#attach` (new or reclaimed), `#rotate_credentials` (`:41`), `#enable` (`:56`),
`#disable` (`:88`), `#credentials_rejected` (`:80`, sets `needs_reauth` and purges the cache),
`#disconnect` (`:98`, releases provider-side webhooks, deletes customer links and credentials, keeps the row so
the store can be reconnected or claimed by another account). Ownership is enforced in `#claim` (`:137-146`) and
the plan's `stores` limit in `#ensure_within_plan!` (`:130-133`), inside the account lock. Every status change
raises or resolves an operations incident from one place, a model callback
(`store.rb:61`, `:74-79`) — chosen because six services flip the status and this is the single path they all pass
through.

**Store health** is separate from status, and that separation is the point. `commerce_stores.status` records
what a human or a token rejection last decided; `Commerce::StoreHealth` records whether the provider has
actually answered (`store_health.rb:8-12`). `api_state` is `failing / healthy / stale / unknown` (`:56-61`),
`webhook_state` is `unsupported / none / received / processed` (`:70-75`), and `health_status` maps into the
operations console's four-state vocabulary with `stale → UNKNOWN` deliberately (`:88-94`); two or fewer
consecutive failures is `WARNING`, three or more is `CRITICAL`. `Commerce::StoreHealthRecorder` is the only
writer, throttles successes to 5 minutes, writes failures immediately, counts webhooks only past the provider's
signature check, and accepts nothing but a `Commerce::Error` as failure input — which is where the no-secrets
rule is enforced (`custom/app/services/commerce/store_health_recorder.rb:1-62`). An operator reads it all through
`Operations::CommerceOperations` with four views (`needs_action` default, `failing`, `unobserved`, `all`) and
five bounded queries that never call a provider
(`custom/app/services/operations/commerce_operations.rb:9-27`).

**Order / customer / cart lookup.** Three distinct paths.
*Customer lookup* — `Commerce::CustomerMatcher` proposes, `Commerce::ConversationPanel` decides; agent search
accepts an exact email or an international phone only, never a name
(`custom/app/services/commerce/conversation_panel.rb:94-99`), and candidates reach the browser masked with a
15-minute encrypted token scoped to this conversation's contact (`:101-107`, `:40-45`).
*Order lookup by number* — `Commerce::OrderSearch` asks each store for that exact number directly, never scans,
reports a provider without such a lookup as `unsupported`, searches up to 4 stores concurrently with a 10s
timeout and reports a slow store in its own entry (`custom/app/services/commerce/order_search.rb:9-24`). `owners`
keeps only the asking customer's orders, so a Flow lookup cannot return a stranger's order (`:7-8`, `:44-47`).
*Cart lookup* — `Commerce::AbandonedCarts` matches a cart to the contact only by linked customer, verified phone
or verified email, never by name, never by a masked value, and never when the identity is ambiguous
(`custom/app/services/commerce/abandoned_carts.rb:1-11`).

**The order actions a user can take** are seven, fixed in `Commerce::ActionRun::ORDER_ACTIONS`
(`action_run.rb:51`): `update_order_status`, `cancel_order`, `refund_full`, `refund_partial`, `resend_invoice`,
`resend_payment_link`, `update_shipping`. Three are destructive (`:52`). `recovery_message` shares the table but
is not an order action (`:53`, scope `order_actions` at `:70`). Actions are the **only writes** Lynomia makes to
a store. `Commerce::OrderActions` checks seven things in a declared order — provider implements it, installation
switches, the store's administrator opt-in, the credentials can write, the agent's permission, no unresolved run
on the order, the order's state now (`custom/app/services/commerce/order_actions.rb:7-15`) — and the order must
belong to the conversation's linked customer among that customer's latest 25 orders, or it is `NOT_FOUND`
(`:136-145`). Requests are rate-limited per user (10/min), store (30/min) and order (5/10min) (`:25`, `:212-220`),
normalised to documented values only (`:170-198`), digested, and recorded under a UUID idempotency key whose
format is validated (`action_run.rb:54`); the same key replays its own run, a different request under the same
key is `IDEMPOTENCY_CONFLICT` (`:204-210`). Execution is `Commerce::ActionExecutor`: claim the run under a row
lock, re-check everything, re-read the order, refuse on `ORDER_CHANGED` when the version moved, check the
amount, **send once** — never retried — and settle a lost answer only by reading the store back, at 30s / 2min /
10min, after which the run stays `unknown` and stops blocking the order
(`custom/app/services/commerce/action_executor.rb:1-12`, `:15`, `:35-44`, `:117-126`, `:147-151`).

**The canonical cart event normalizer and cart state.** `Commerce::CartEvent` (`cart_event.rb:17`) is the only
cart shape `Commerce::CartLifecycle` ever sees; a provider normalizer builds it (today only
`Commerce::Providers::Zid::CartEvents`), so the lifecycle knows no provider field names. `Commerce::Cart` has
exactly two states, `abandoned` and `completed` (`cart.rb:21`) — "two, because two is what the provider's events
can establish" (`cart.rb:3`). There is no `active` state (the provider never announces a live cart) and no
`recovered` state, because completion does not prove Lynomia caused it; recovery is read from two recorded facts
via `#post_target_completion?` (`cart.rb:43-45`), named for what it measures. `Commerce::CartLifecycle` applies
one event under three rules: forward only, provider time only, and no clock creates state — so a provider outage
produces no transitions at all, because silence is not a signal
(`custom/app/services/commerce/cart_lifecycle.rb:8-20`). Writes are serialised by `Commerce::StoreLock` keyed on
store+cart with the unique index as backstop (`:18-20`, `:34`). Descriptive fields are written only when a
delivery carries them, so a sparser later event cannot blank what an earlier one established (`:82-91`). A
transition into `abandoned` hands `Automation::CommerceEvents` one dispatch and nothing more (`:102-104`). The
Zid normalizer carries two self-declared unverified decisions, both confined to that one file:
`UNVERIFIED(zid-cart-identity)` (`id` vs `cart_id` vs `session_id`; a payload without the chosen key is refused
rather than falling back) and `UNVERIFIED(zid-cart-envelope)`
(`custom/app/services/commerce/providers/zid/cart_events.rb:8-18`).

**Customer 360's commerce panel.** `Commerce::Customer360` aggregates each connected store's
`ConversationPanel#show` across stores read concurrently, at most 4 at a time, answered after 15 seconds whatever
is still running, so one slow store is reported in its own entry and never fails the overview
(`custom/app/services/commerce/customer360.rb:6-8`, `:15-18`, `:81-84`). Nothing is stored. Its four definitions
are stated in the class and reused by `Commerce::ContactMetric.figures` so audiences and the panel cannot
disagree: active = `pending processing on_hold shipped`; shipped = `shipped`; last purchase = newest order not
`draft failed cancelled`; spend = totals of orders the store reports `paid`, **per currency, never converted**
(`:14-33`, `contact_metric.rb:41-51`). Figures cover only the orders the stores returned — the latest 5 per store
(`ConversationPanel::ORDER_LIMIT`, `conversation_panel.rb:9`) — so they are "visible", never lifetime. Stores of a
switched-off provider and stores in `needs_reauth` are listed without being read and without cached data
(`:88-90`).

**Commerce analytics.** `Analytics::Commerce::Metrics` is provider-neutral by construction: every number comes
from `commerce_carts` and `commerce_action_runs`, nothing calls a provider
(`custom/app/services/analytics/commerce/metrics.rb:1-5`). Nine count metrics (`carts_seen carts_abandoned
carts_targeted carts_completed post_target_completions untargeted_completions order_actions_requested
order_actions_failed recovery_messages_prepared`), one rate (`targeting_rate`, `nil` not 0 when nothing was
abandoned), two current-state metrics (`open_abandoned_now`, `actions_unresolved_now`) (`:24-31`, `:80-84`). Three
series (abandoned / targeted / completed) and five breakdown dimensions (`provider store currency action_type
action_error`) (`custom/app/services/analytics/commerce/overview.rb:3-5`). Three rules are enforced rather than
documented: **no revenue, GMV or profit** — `commerce_carts.visible_total` exists and is deliberately never
summed, because carts carry a per-cart currency and nothing converts, so the currency breakdown reports cart
*counts* (`metrics.rb:9-13`, `:180-186`); **no recovery attribution** (`:15-19`); **no invented cart states**
(`:21-22`).

## 2. Surfaces and routes

| Surface | Vue / view | API | Controller |
|---|---|---|---|
| Settings → Commerce (store list, limit, cart queue) | `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue`, route `settings_commerce_index` at `commerce.routes.js:13-20` | `GET/POST/PATCH/DELETE /api/v1/accounts/:id/commerce/stores` | `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:11` |
| Provider picker | `settings/commerce/ProviderPicker.vue` | index payload `providers` | `custom/app/views/api/v1/accounts/commerce/stores/index.json.jbuilder:3` |
| WooCommerce key dialog | `settings/commerce/StoreDialog.vue` | `POST .../commerce/stores` | `stores_controller.rb:26-33` |
| Salla / Zid / Shopify connect dialogs | `SallaConnectDialog.vue`, `ZidConnectDialog.vue`, `ShopifyConnectDialog.vue` | `commerce/salla_connection`, `zid_connection`, `shopify_connection` | `custom/app/controllers/api/v1/accounts/commerce/{salla,zid,shopify}_connections_controller.rb` |
| OAuth returns | `Index.vue:158-172` reads `?<provider>=connected` / `?<provider>_error=<code>` | `GET /commerce/zid/callback`, `GET /commerce/shopify/callback` | `custom/app/controllers/commerce/{zid,shopify}/callbacks_controller.rb`; routes `config/routes/commerce.rb:53`, `:60` |
| Recovery queue (admins) | `settings/commerce/CartQueue.vue` | `GET .../commerce/carts` | `custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb` |
| Conversation Commerce section | `components/widgets/conversation/commerce/CommercePanel.vue`, mounted at `routes/dashboard/conversation/ContactPanel.vue:289` behind `FEATURE_FLAGS.LYNOMIA_COMMERCE` (`:54`) | `GET .../conversations/:id/commerce/stores`, `.../stores/:store_id` | `custom/app/controllers/api/v1/accounts/conversations/commerce/stores_controller.rb:20-45` |
| Customer 360 tab | `commerce/CommerceOverview.vue` | `GET .../conversations/:id/commerce/overview` | `.../conversations/commerce/overviews_controller.rb` |
| Refresh | `CommercePanel.vue` refresh button | `POST .../conversations/:id/commerce/refresh` | `.../conversations/commerce/refreshes_controller.rb` |
| Find an order | `commerce/CommerceOrderSearch.vue` | `GET .../conversations/:id/commerce/orders?number=` | `.../conversations/commerce/orders_controller.rb:19` |
| Link / unlink customer | `CommercePanel.vue` | `GET .../stores/:id/customers`, `POST/DELETE .../stores/:id/link` | `conversations/commerce/stores_controller.rb:34-45` |
| Order actions menu + confirm | `commerce/CommerceOrderItem.vue` → `commerce/CommerceOrderActions.vue` | `GET/POST .../stores/:sid/orders/:oid/actions` | `.../conversations/commerce/order_actions_controller.rb`; route `config/routes/commerce.rb:32` |
| Action run polling | `CommerceOrderActions.vue` | `GET .../commerce/action_runs/:id` | `.../conversations/commerce/action_runs_controller.rb` |
| Abandoned carts in a conversation | `commerce/CommerceCarts.vue` | `GET .../conversations/:id/commerce/carts`, `POST .../stores/:sid/carts/:cart_id/recovery` | `.../conversations/commerce/{carts,recoveries}_controller.rb` |
| Analytics → Commerce | `routes/dashboard/analytics/AnalyticsCommerce.vue`, route `analytics_commerce` at `analytics.routes.js:57-62` | `GET /api/v1/accounts/:id/analytics/commerce` (`config/routes/analytics.rb:19`) | `custom/app/controllers/api/v1/accounts/analytics_controller.rb:65-72` |
| Super Admin operations | `app/views/super_admin/operations/commerce.html.erb` | `config/routes/operations.rb:24` | `Operations::CommerceOperations` |
| Audience field options | contact filter | `GET .../commerce/audience_fields` | `.../commerce/audience_fields_controller.rb` |
| Provider webhooks | — | `POST /webhooks/salla`, `/webhooks/woocommerce/:store_id`, `/webhooks/zid/:store_id`, `/webhooks/shopify_commerce` | `config/routes/commerce.rb:47-61` |

Sidebar entries: Settings → Commerce at `components-next/sidebar/Sidebar.vue:898-901`, Analytics → Commerce at
`Sidebar.vue:670-674`.

## 3. User-visible states

**Store (Settings → Commerce).** `active` / `disabled` / `needs_reauth` / `disconnected`, labelled "Active",
"Disabled", "Needs re-authorization", "Disconnected" (`en/commerce.json` `COMMERCE.SETTINGS.STATUS`,
`useCommerceLabels.js:117-124`), with tones at `Index.vue:38-43`. Each row also shows: verified-at, live-update
state (`active` / `read_only_key` / absent — `_store.json.jbuilder:10`), order-actions opt-in plus
`order_actions_status` (`available`, `unsupported`, `actions_disabled`, `provider_actions_disabled`,
`store_actions_off`, `read_only_key`, `missing_scope`, `write_access_unverified` —
`_store.json.jbuilder:13-14`, `order_actions.rb:32-36`, rendered at `Index.vue:209-233`), whether abandoned carts
are offered, and `provider_enabled` (an installation switch turned off under a connected store).
The page also shows the plan's store usage and refuses "Add store" at the limit (`index.json.jbuilder:7-10`,
`Index.vue:50-57`).

**Conversation panel, per store** (`Commerce::ConversationPanel#show`): `linked`, `not_found`, `suggested`,
`multiple`, `unavailable` (`conversation_panel.rb:21-28`, `:70-79`). A `linked` panel can additionally be stale —
orders from cache with the time they were fetched and the error code that prevented a fresh read — or carry
`orders: nil` with an error when even the fallback is gone (`:58-68`). Empty state: "No orders yet."

**Customer 360 entry states**: `linked`, `not_found`/`suggested`/`multiple` (all shown as "Not linked"),
`needs_reauth`, `provider_unavailable`, `unavailable` (`useCommerceLabels.js:140-149`, `customer360.rb:88-99`).
The overview is `partial: true` when any store entry carries an error (`customer360.rb:60`).

**Order search, per store**: `searched`, `unsupported` (the platform has no number lookup), `unavailable` with a
code; a store that exceeds the 10s budget is reported `unavailable` / `TIMEOUT`
(`order_search.rb:21`, `:30`, `:38-41`).

**Order actions.** Per action: `{ available: true, … }` or `{ available: false, reason: }` where the reason is
`unsupported`, `permission_denied`, `action_in_progress`, or the provider's own order-state reason
(`order_actions.rb:127-134`). Reasons shown to the agent: `PERMISSION_DENIED`, `ACTION_IN_PROGRESS`,
`PAID_REFUND_FIRST`, `ALREADY_CANCELLED`, `NOT_PAID`, `NOTHING_REFUNDABLE`, `ORDER_STATE`, `NO_EMAIL`,
`UNSUPPORTED`, `MULTIPLE_PAYMENTS`, `OTHER` (`en/commerce.json` `COMMERCE.ACTIONS.UNAVAILABLE`).
Run states: `pending`, `running`, `succeeded`, `failed`, `unknown` (`action_run.rb:38-43`, `:63`), plus the
terminal-but-unresolved `unknown` + `metadata.reconcile == 'exhausted'`, which stops blocking the order
(`action_executor.rb:148-151`, `order_actions.rb:161-163`).

**Carts** (per store): `ok`, `unavailable` with a code, and per cart `abandoned` / `recovered` / `expired` /
`unknown` (`abandoned_cart.rb:4`, `abandoned_carts.rb:29-38`). In production every store is `unavailable` /
`RECOVERY_DISABLED` because of the PRE_UAT gate.

**Absent surfaces.** Without the `lynomia_commerce` feature the Commerce section and the settings page do not
render at all (`ContactPanel.vue:54`, `commerce.routes.js:18`, and server-side
`stores_controller.rb:50-52`). Analytics → Commerce is **not** gated on `lynomia_commerce`: its route carries only
`FEATURE_FLAGS.REPORTS` and `['administrator','report_manage']` (`analytics.routes.js:16-19`), and the sidebar
entry is unconditional (`Sidebar.vue:670-674`), so an account without Commerce still sees an all-zero Commerce
analytics screen.

## 4. Errors and validation messages — the complete `Commerce::Error` code list

`Commerce::Error` is the one commerce error. Construction validates the code against `CODES` and raises
`ArgumentError` for anything else, so an unknown code cannot reach a user
(`custom/app/services/commerce/error.rb:15`). The UI only ever sees `code` and a pre-classified `reason`;
provider responses, host error pages and credentials never reach a message (`error.rb:1-2`, `:22-24`).
Controllers render it as `{ error: { code, reason } }` with **422** (`stores_controller.rb:18-20`,
`conversations/commerce/stores_controller.rb:16-18`). The browser renders it through
`useCommerceLabels.errorMessage` (`useCommerceLabels.js:54-89`), falling back to `COMMERCE.ERRORS.GENERIC`.

`CODES` holds **31** codes (`error.rb:4-10`). All of them, with meaning, where raised, and how they surface:

| Code | What it means | Raised at (representative) | How it surfaces | Article group |
|---|---|---|---|---|
| `STORE_UNAVAILABLE` | connection failed, 5xx, DNS, TLS, or a busy store lock | `http_client.rb:229`, `:237`, `:157`, `store_lock.rb:16` | panel stale banner; store entry `unavailable`; served as stale fallback | `commerceStoreUnreachable` |
| `AUTH_INVALID` | the store refused the credentials; also flips the store to `needs_reauth` and purges its cache | `http_client.rb:225`, `token_manager.rb:64`, `:115`, `providers/*.rb` identity mismatch | "An administrator needs to reconnect the store"; store row `Needs re-authorization` | `commerceStoreReconnect` |
| `PERMISSION_DENIED` | 403 from the store, a missing OAuth scope, or an executor-time permission loss | `http_client.rb:226`, `salla/tokens.rb:24`, `:27`, `shopify/authorization.rb:33`, `action_executor.rb:67`, `:71` | panel/action error | `commerceStorePermissions` |
| `RATE_LIMITED` | 429, Shopify `THROTTLED`, or Lynomia's own action/recovery throttle; `reason` is seconds to wait | `http_client.rb:228`, `shopify/graphql.rb:55`, `order_actions.rb:218`, `recovery_messages.rb:107`, `backoff.rb:8` | "Try again in a moment"; served as stale fallback | `commerceStoreUnreachable` |
| `TIMEOUT` | the request went out and no answer arrived in the budget; also the Customer 360 per-store deadline | `http_client.rb:125`, `:161`, `:205`, `customer360.rb:83`, `order_search.rb:21` | panel stale banner; store entry `unavailable` | `commerceStoreUnreachable` |
| `INVALID_RESPONSE` | a body Lynomia could not read: not JSON, too large, unexpected shape, malformed order/customer/cart/shipment, an unexpected HTTP status | `http_client.rb:204`, `:219`, `:230`, every `providers/*/normalizer.rb`, `shopify/graphql.rb:23` | panel error; served as stale fallback | `commerceStoreUnreachable` |
| `NOT_FOUND` | 404 from the store; an expired or forged link token; an order that is not the linked customer's; a cart the store no longer lists | `http_client.rb:227`, `conversation_panel.rb:42`, `order_actions.rb:138`, `:141`, `:144`, `abandoned_carts.rb:44` | "This link request expired. Search again." | **none** |
| `INVALID_STORE_URL` | refused before anything is sent (not https, port, IP, private/loopback/metadata address) or on a 3xx; `reason` picks the exact URL message | `store_url.rb:66`, `http_client.rb:155`, `:159`, `:224`, `shopify_connections_controller.rb:26` | one of seven `COMMERCE.URL_ERRORS` strings (`useCommerceLabels.js:91-100`) | `commerceStoreAddress` |
| `INVALID_QUERY` | the agent's customer search or order number is neither an exact email nor an international phone / digits | `conversation_panel.rb:32`, `orders_controller.rb:19` | "Enter an exact email, or a phone number starting with +…" | **none** |
| `ENCRYPTION_NOT_CONFIGURED` | the installation has no Active Record encryption keys, so credentials cannot be stored | `store_connection.rb:125`, the three connection controllers | "Store credentials can't be saved: encryption is not configured" | **none** |
| `STORE_ALREADY_CONNECTED` | that store belongs to another account, or a non-disconnected row already exists | `store_connection.rb:38`, `:141` | "This store is already connected." | **none** |
| `PROVIDER_DISABLED` | the installation's provider switch is off | `store_connection.rb:57`, callbacks and connection controllers | "This store platform is turned off on this installation." | **none** |
| `PROTECTED_DATA_NOT_APPROVED` | Shopify has not approved the app for Protected Customer Data, so customers cannot be matched | `shopify/graphql.rb:64` | a store entry stating customers cannot be matched | `commerceStorePermissions` |
| `INVALID_REQUEST` | an action type, order id, version, idempotency key or parameter value outside the documented set | `order_actions.rb:71`, `:73`, `:185`, `:191` | "This request isn't valid." | **none** |
| `ACTIONS_DISABLED` | a kill switch, the provider switch, or the store's opt-in is off | `order_actions.rb:114` via `STORE_ERRORS` (`:26-30`), `shopify_connections_controller.rb:55` | "Order actions are off for this store." | `commerceOrderAction` |
| `ACTION_UNAVAILABLE` | the provider does not implement it, or the order's state now does not allow it (`reason` carries which) | `order_actions.rb:114`, `action_executor.rb:83`, `:97` | greyed menu item with its reason, or a failed run | `commerceOrderAction` |
| `ACTION_IN_PROGRESS` | another unresolved run on the same order | `order_actions.rb:83` | "Another action on this order is still being processed." | `commerceOrderAction` |
| `ORDER_CHANGED` | the order's version moved between the agent confirming and the send; **nothing was sent** | `action_executor.rb:80` | "The order changed… Nothing was sent. Review it again." | `commerceOrderAction` |
| `INVALID_AMOUNT` | not a positive decimal, wrong currency, too many decimals, above refundable, or a `refund_full` that is not the full amount | `order_actions.rb:195`, `action_executor.rb:110` | "The amount isn't valid for this order. Nothing was sent." | `commerceOrderAction` |
| `IDEMPOTENCY_CONFLICT` | the same idempotency key reused for a different request, or another account's | `order_actions.rb:206` | "This confirmation was already used. Start again." | `commerceOrderAction` |
| `WRITE_ACCESS_DENIED` | the credentials cannot change orders: `read_only_key`, `missing_scope`, `write_access_unverified` | `order_actions.rb:114` via `STORE_ERRORS` | "The store's credentials can't change orders." | `commerceStorePermissions` |
| `NOT_APPLIED` | the store accepted the request and reading it back proves the order is unchanged — safe to retry | `action_executor.rb:120`, `providers/{woocommerce,zid,shopify}/actions.rb` | failed run, "You can try again." | `commerceOrderAction` |
| `PROVIDER_REJECTED` | the store refused the action itself (4xx / `userErrors`) | `providers/woocommerce/actions.rb:31`, `zid/actions.rb:16`, `shopify/actions.rb:69`, `:146` | "The store refused this change." | `commerceOrderAction` |
| `REFUND_DECLINED` | the payment gateway refused the refund; no money moved | `providers/woocommerce/actions.rb:149` | "The payment gateway refused the refund. No money was sent." | `commerceOrderAction` |
| `RECOVERY_DISABLED` | abandoned carts are off for this store (switch, PRE_UAT, or the provider has none) | `recovery_messages.rb:45`, `abandoned_carts.rb:59` | cart section `unavailable` | **none** |
| `RECOVERY_COOLDOWN` | a recovery message for this cart was prepared inside the cooldown; `reason` is when it lifts | `recovery_messages.rb:73` | "…was sent recently."; administrators may override once | **none** |
| `CANNOT_REPLY` | the conversation cannot take a free-form message now (the 24-hour window) | `recovery_messages.rb:46` | "…reach the customer with an approved template instead." | **none** |
| `INVALID_RECOVERY_URL` | the store's recovery link failed `Commerce::RecoveryUrl` validation | `recovery_messages.rb:63` | "The store's recovery link isn't safe to send. Nothing was prepared." | **none** |
| `CART_NOT_ABANDONED` | the cart was completed or is older than `MAX_AGE` (30 days) | `recovery_messages.rb:60` | "This cart was completed or has expired." | **none** |
| `NOT_SENT` | the sweep found a run that was accepted and never sent; nothing changed in the store | `custom/app/jobs/commerce/action_sweep_job.rb:24` | "…didn't send this action to the store. Nothing changed." | `commerceOrderAction` |
| `STORE_LIMIT_REACHED` | the account is at its plan's `stores` limit | `store_connection.rb:132` | **see defect below** | **none** |

Two outcome codes reach the UI as `ActionRun#error_code` but are **not** `Commerce::Error` codes:
`UNKNOWN_OUTCOME` (the answer was lost; `action_executor.rb:31`, `:62`, `action_result.rb:14`) and
`NOT_RECONCILABLE` (`providers/base.rb:83`). `UNKNOWN_OUTCOME` has an EN/AR string
(`useCommerceLabels.js:82`); `NOT_RECONCILABLE` has **no string at all** and renders as
`COMMERCE.ERRORS.GENERIC`.

**Mapping to the contextual-help registry.** `app/javascript/dashboard/helper/documentationLinks.js` holds seven
commerce keys (`:63-78`): `commerce`, `commerceProviders`, `commerceWoocommerce`, `commerceSalla`, `commerceZid`,
`commerceShopify`, `customer360`, plus five troubleshooting keys `commerceStoreReconnect`,
`commerceStoreUnreachable`, `commerceStoreAddress`, `commerceStorePermissions`, `commerceOrderAction`.
`COMMERCE_ERROR_ARTICLES` (`:109-133`) maps **19 of the 31 codes** into those five groups — 1 reconnect, 4
unreachable, 1 address, 3 permissions, 10 order action — and `commerceErrorArticle` returns `undefined` for the
rest by design (`:144-152`).

**The 12 codes with no article**, grouped by the answer a stuck reader actually needs:

| Codes | The question they raise | Nothing answers it |
|---|---|---|
| `RECOVERY_DISABLED`, `RECOVERY_COOLDOWN`, `CANNOT_REPLY`, `INVALID_RECOVERY_URL`, `CART_NOT_ABANDONED` | "why can't I send this cart a recovery message?" | there is **no abandoned-cart or recovery article in the corpus at all** |
| `STORE_LIMIT_REACHED` | "why can't I add another store?" | no plan/limit article is linked from Commerce |
| `NOT_FOUND`, `INVALID_QUERY` | "why can't I find or link this customer?" | no customer-matching troubleshooting article; the matching rules live only in prose inside `customer-360` |
| `STORE_ALREADY_CONNECTED` | "my store is connected somewhere else" | mentioned in a Limits bullet of `commerce-overview`, no article |
| `PROVIDER_DISABLED` | "my platform says Not available yet" | answered in prose in `commerce-overview` / `commerce-provider-support`, not reachable from the code |
| `ENCRYPTION_NOT_CONFIGURED`, `INVALID_REQUEST` | installation / client bugs | correctly unarticled: neither is a user action |

## 5. Failure paths

1. **Store silently failing while reading `active`.** The exact case `Commerce::StoreHealth` was built for
   (`store_health.rb:8-12`). An agent sees a stale banner with a fetch time; an administrator sees `Active` in
   Settings → Commerce, because that page renders `status` and `verified_at`, **not** health. Health is visible
   only in Super Admin. A tenant administrator cannot tell a store failing since Tuesday from a healthy one.
2. **Credentials revoked.** Any provider read returning `AUTH_INVALID` flips the store to `needs_reauth` and
   purges its cache from three places (`conversation_panel.rb:120-122`, `order_search.rb:37`,
   `order_actions.rb:98`, `abandoned_carts.rb:36`). The agent gets a clear message and a `What to do about this`
   link; the administrator gets a `Reconnect` or `Replace keys` button. Well handled.
3. **Lost answer on a write.** The one genuinely unresolvable production case. The run is `unknown`, never
   re-sent, reconciled by reading the store at 30s/2min/10min, and after that stays `unknown` with
   `reconcile: exhausted` and stops blocking the order (`action_executor.rb:15`, `:35-44`, `:148-151`). The agent
   is told the store did not answer and that Lynomia is checking. `actions_unresolved_now` in analytics is the
   operator's counter (`metrics.rb:103-108`). The user cannot tell what to do next beyond "look in your store
   admin" — which is what the article says, and is honest.
4. **Accepted but never sent.** `Commerce::ActionSweepJob` fails a stranded `pending` run with `NOT_SENT`
   (`action_sweep_job.rb:24`). Correct, and articled.
5. **A refund above what is refundable, or in the wrong currency.** Caught twice: at request normalisation and
   again against the fresh snapshot at execution (`order_actions.rb:195`, `action_executor.rb:102-111`), with
   `reason` naming `currency`, `precision`, `above_refundable` or `not_full`. The reason is **not** surfaced: the
   UI shows one `INVALID_AMOUNT` string for all four.
6. **A Zid cart delivery whose identity key is absent.** Refused loudly rather than falling back to another key,
   because a fallback would create two rows for one cart (`cart_events.rb:10-14`). The merchant sees no cart; the
   refusal is reported through `Commerce::Metrics`. Unverifiable until a real Zid UAT.
7. **An order that is not the linked customer's.** `NOT_FOUND`, deliberately indistinguishable from a missing
   order so an order id cannot be probed (`order_actions.rb:136-145`). Good security, poor diagnosability: the
   user sees "This link request expired. Search again.", which is the wrong sentence for this case — the same
   string serves both the expired link token and an unowned order.
8. **Plan limit reached.** `STORE_LIMIT_REACHED` renders as "Something went wrong. Try again." — see §9 D1.
9. **Encryption keys missing.** Fails loudly before any credential is stored
   (`store_connection.rb:124-126`, `store.rb:82-84`). Correct.

## 6. Permissions

| Surface | Gate | Citation |
|---|---|---|
| Settings → Commerce (route) | `lynomia_commerce` feature flag + `administrator` | `commerce.routes.js:17-20` |
| Store CRUD (server) | `lynomia_commerce` feature + `Commerce::StorePolicy` (administrator for index/create/update/destroy) | `stores_controller.rb:14-15`, `:50-52`; `custom/app/policies/commerce/store_policy.rb:2-18` |
| OAuth callbacks | administrator **and** `lynomia_commerce` **and** the provider switch | `commerce/zid/callbacks_controller.rb:23-24`, `commerce/shopify/callbacks_controller.rb:31-32` |
| Conversation Commerce section, order search, link/unlink | whoever can view the conversation (like editing the contact) + `lynomia_commerce` | `conversations/commerce/stores_controller.rb:1-3`, `:49-51` |
| Store reachable in a conversation | `active` **and** its provider enabled on the installation | `conversations/commerce/stores_controller.rb:54-56` |
| `update_order_status`, `resend_invoice`, `resend_payment_link`, `update_shipping` | administrator **or** custom-role `commerce_order_manage` | `custom/app/policies/commerce/action_policy.rb:27-39` |
| `cancel_order`, `refund_full`, `refund_partial` | **administrator only** — never grantable to an agent by a custom role (pilot) | `action_policy.rb:22-24`, `:41-47` |
| The store's order actions at all | administrator opt-in on the store (`settings['order_actions']`) | `order_actions.rb:107`, `store_connection.rb:70-76` |
| Order actions on the installation | `COMMERCE_ACTIONS_ENABLED`, `<PROVIDER>_ACTIONS_ENABLED`, and the PRE_UAT gate | `switches.rb:19-24`, `:39-41` |
| Abandoned carts / recovery | `COMMERCE_RECOVERY_ENABLED`, `<PROVIDER>_RECOVERY_ENABLED` (default **off**), PRE_UAT, and `supports_carts?` | `switches.rb:26-31`, `abandoned_carts.rb:18-21` |
| Recovery cooldown override | administrator | `commerce.js:127-138` (`override_cooldown`), `switches.rb:34-37` |
| Permission re-checked at execution | the requester's `account_user` and policy are re-read when the job runs | `action_executor.rb:65-75` |
| Analytics → Commerce | `FEATURE_FLAGS.REPORTS` + `['administrator','report_manage']` — **not** `lynomia_commerce` | `analytics.routes.js:16-19`, `:57-62` |
| Super Admin operations → Commerce | Devise `:super_admin` | `config/routes/operations.rb:24` |

## 7. Contextual-help opportunities

`commerceErrorArticle` is wired into **exactly one** place in the product: the stale/error banner of the
per-store conversation panel (`CommercePanel.vue:415`). No other commerce surface links to documentation from a
code. `DocsLink` appears statically in four connect dialogs and the provider picker
(`StoreDialog.vue:213`, `SallaConnectDialog.vue:221`, `ZidConnectDialog.vue:86`, `ShopifyConnectDialog.vue:116`,
`ProviderPicker.vue:118`) and nowhere else.

| UI location | The question a user has there | Registry key that should link | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `CommercePanel.vue:415` | "why is this out of date / unreachable?" | resolved from the code, `commerce` fallback | yes — **already wired** |
| `CommerceOrderActions.vue` result banner (`COMMERCE.ACTIONS.RESULT`) | "it failed / we don't know — now what?" | `commerceOrderAction` via `commerceErrorArticle(run.error_code)` | yes, key exists; **not wired** |
| `CommerceOrderActions.vue` greyed menu item with `UNAVAILABLE.*` reason | "why can't I refund this?" | `commerceProviders` (capability) or `commerceStorePermissions` (`read_only_key`/`missing_scope`) | yes; **not wired** |
| `Index.vue:209-233` order-actions status line (`read_only_key`, `missing_scope`, `write_access_unverified`) | "how do I let it change orders?" | `commerceStorePermissions` | yes; **not wired** |
| `Index.vue` store row, status `needs_reauth` | "what does re-authorization mean?" | `commerceStoreReconnect` | yes; **not wired** |
| `Index.vue:158-172` OAuth return alert (`?<provider>_error=<code>`) | "the authorization came back with an error" | resolved from the code | yes; **not wired** (a bare alert) |
| `Index.vue` "Add store" disabled at the plan limit | "why can't I add another store?" | — | **no key, no article** |
| `ProviderPicker.vue` "Not available yet" | "who turns my platform on?" | `commerceProviders` | yes — wired statically at `:118` |
| `CommerceOrderSearch.vue` `UNSUPPORTED` / `UNAVAILABLE` | "why can't this store be searched?" | `commerceProviders` | yes; **not wired** |
| `CommercePanel.vue` search hint / `INVALID_QUERY` / `NO_RESULTS` | "why won't it find my customer?" | — | **no key**; matching rules buried in `customer-360` prose |
| `CommerceCarts.vue` `UNAVAILABLE` / `COOLDOWN` / `CANNOT_REPLY` | "why can't I send a recovery message?" | — | **no key, no article** |
| `CartQueue.vue` (admin recovery queue) | "what is this queue and what do I do with it?" | — | **no key, no article** |
| `CommerceOverview.vue` `SPEND_HINT` / `ORDERS_HINT` / `PARTIAL` | "why is spend empty / why only 5 orders?" | `customer360` | yes; **not wired** |
| `AnalyticsCommerce.vue` | "why is there no revenue line?" | — | **no key**; no commerce-analytics article |

## 8. Current documentation coverage

Seven commerce articles plus five troubleshooting articles, EN and AR, all present in both locales:

| Slug | EN file | Lines | Covers |
|---|---|---|---|
| `commerce-overview` | `custom/db/documentation/en/commerce/commerce-overview.md` | 105 | what connecting a store gives you, read-on-demand model, who can do what, limits |
| `commerce-provider-support` | `.../commerce-provider-support.md` | 104 | the capability matrix in user terms, per-platform limits |
| `connect-woocommerce` / `connect-salla` / `connect-zid` / `connect-shopify` | `.../connect-*.md` | 103 / 97 / 95 / 98 | per-provider setup (agents 044–047) |
| `customer-360` | `.../customer-360.md` | 115 | the cross-store overview and why figures are visible, not lifetime |
| `commerce-store-needs-reconnecting` | `en/troubleshooting/` | 54 | `AUTH_INVALID`, `needs_reauth` |
| `commerce-store-unreachable` | `en/troubleshooting/` | 45 | `STORE_UNAVAILABLE`, `TIMEOUT`; timeouts and retry policy |
| `commerce-store-address-refused` | `en/troubleshooting/` | 51 | `INVALID_STORE_URL`, the SSRF rules |
| `commerce-keys-cannot-do-that` | `en/troubleshooting/` | 51 | `PERMISSION_DENIED`, `WRITE_ACCESS_DENIED`, `PROTECTED_DATA_NOT_APPROVED` |
| `commerce-order-action-did-not-apply` | `en/troubleshooting/` | 52 | the order-action outcomes |

Quality is high where coverage exists. The articles are task-oriented, state limits plainly, and several claims
check out exactly against code: the 120s / 24h cache window (`cache.rb:8-9`), the 3s/8s/10s/5MB budgets and the
"retry once, GET only, never a write" rule (`http_client.rb:8-10`, `:15-20`), "names are never matched or
searched" (`conversation_panel.rb:94-99`), the five-orders-per-store figure (`conversation_panel.rb:9`), one
store per account (`store.rb:23`, `store_connection.rb:137-146`), Zid has no admin order link
(`providers/zid/normalizer.rb:35`), Salla cannot be searched by order number (no `searches_orders?` override),
Zid's two status steps (`providers/zid/actions.rb:14`) and WooCommerce's (`providers/woocommerce/actions.rb:20`).

The internal design records under `docs/commerce/` (36 files) and `docs/commerce-production/` (12 files) are far
richer than the corpus and are the right source for several missing articles — in particular
`24-realtime-architecture.md`, `28-commerce-actions-architecture.md`, `30-abandoned-carts.md`,
`31-sales-recovery.md`, `35-stores-on-plans.md`, `05-cart-state-design.md`, `06-cart-transition-design.md`.

## 9. Missing or stale documentation

**Gaps a stuck user cannot resolve.**

- **No abandoned-cart / recovery article anywhere.** Five error codes, a conversation section
  (`CommerceCarts.vue`), an administrator queue (`CartQueue.vue`), a durable cart lifecycle, a cooldown with an
  admin override and three analytics series all exist with zero documentation. `commerce-provider-support.md`
  asserts "In practice: there is no abandoned-cart feature", which is true of the production switches and false
  of the product a reader can see.
- **No commerce-analytics article.** Analytics → Commerce ships twelve metrics, three series and five breakdowns
  and is reachable by any report manager, documented nowhere.
- **No store-limit / plans article linked from Commerce.** `STORE_LIMIT_REACHED` exists, the settings page shows
  usage, and `docs/commerce/35-stores-on-plans.md` exists internally.
- **No customer-matching troubleshooting article.** `NOT_FOUND` and `INVALID_QUERY` are the two codes an agent
  hits most in day-to-day linking; the rules are prose inside `customer-360` and nothing links to them from the
  search box.
- **No store-health article.** `api_state` and `webhook_state` have four states each and a stated meaning for
  `unknown` vs `healthy`, but the vocabulary appears only in Super Admin and in
  `docs/product-refinement/09-commerce-operations.md`.
- **No article explains the unresolved-run state to an administrator.** `actions_unresolved_now` is an operator
  metric; nothing says what to do when it is above zero.

**Defects worth fixing alongside the documentation.**

- **D1 — `STORE_LIMIT_REACHED` is unreachable in the UI.** The string exists in both locales
  (`app/javascript/dashboard/i18n/locale/en/commerce.json:165`, `ar/commerce.json:165`) and the server raises the
  code (`store_connection.rb:132`), but `useCommerceLabels.errorMessage` has no entry for it
  (`useCommerceLabels.js:54-89`, which ends at `NOT_SENT`), so an administrator at the plan limit is told
  "Something went wrong. Try again." The written answer — "Upgrade your plan or disconnect a store" — is in the
  bundle and never shown.
- **D2 — `NOT_RECONCILABLE` has no string.** It is a real `ActionRun#error_code`
  (`providers/base.rb:83`, `woocommerce/actions.rb:73`, `shopify/actions.rb:94`) and renders as the generic
  message.
- **D3 — the registry's own comment is stale.** `documentationLinks.js:71-73` says "the thirty entries in
  `Commerce::Error::CODES`"; there are 31 (`error.rb:4-10`). `:139-141` repeats "Thirty codes have five distinct
  answers". Minor, but it is the comment a future author will trust.
- **D4 — Analytics → Commerce is not gated on `lynomia_commerce`** (`analytics.routes.js:16-19`,
  `Sidebar.vue:670-674`), so accounts without Commerce get an all-zero screen with no explanation.
- **D5 — in the stale case the error message is never shown.** The panel banner renders the code's message only
  when `!panel.stale` (`CommercePanel.vue:408-411`); when a cached answer is served — the common path, since
  `Commerce::Cache::STALE_FALLBACK_CODES` covers `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED` and
  `INVALID_RESPONSE` (`cache.rb:10`) — the agent sees only "Couldn't refresh store data right now." plus the
  fetch time. The code still drives the `What to do about this` link, so the article is the *only* place that
  names what went wrong, which raises the bar on those four codes being well covered.

## 10. Doc claims not proven by code

| Claim | Source | Code | Verdict |
|---|---|---|---|
| "**For reporting.** There is no commerce report. Nothing here totals revenue, orders per day or per agent." | `en/commerce/commerce-overview.md` (When not to use it) | `Analytics::Commerce::Overview`, `AnalyticsCommerce.vue`, `analytics.routes.js:57-62` | **wrong on the first sentence, right on the second.** A Commerce analytics family exists with 12 metrics; it deliberately publishes no revenue (`metrics.rb:9-13`). The article must be rewritten to say "no revenue", not "no report". |
| "**For abandoned-cart recovery.** It is not available on any platform." / "In practice: there is no abandoned-cart feature." | `commerce-overview.md`, `commerce-provider-support.md` | `supports_carts?` true for Salla/Zid/Shopify; `switches.rb:15-16`, `:26-31` | **true only of the default switches.** PRE_UAT plus a default-off recovery switch make it unreachable in production, so the user-facing statement holds today — but it is a configuration fact presented as a product fact, and it will be wrong the moment a UAT clears. |
| "Two things exist in the product and are switched off everywhere. They are held in code, so no setting turns them on." | `commerce-provider-support.md` | `switches.rb:40` | **imprecise.** `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is exactly such a setting; it is ENV-only and documented as staging-only, which is not the same as "no setting". |
| "Live updates when an order changes — Salla: yes" | `commerce-provider-support.md` | `salla.rb:47` `supports_realtime? = true`, but `registers_webhooks?` false | **correct, by a different mechanism.** Salla's webhooks come from the Salla app's own configuration, not from Lynomia registering them (`base.rb:53`). The article does not distinguish the two, which matters when a merchant asks why nothing arrives. |
| "Zid CART CREATED — UNSUPPORTED (Lynomia: provider offers the event, Lynomia does not subscribe)"; "Salla WEBHOOKS — UNSUPPORTED (Lynomia: registers none)" | `docs/commerce-production/01-provider-capability-matrix.md` §3 | `Commerce::Zid::Webhooks::EVENTS` includes `Commerce::Providers::Zid::CartEvents::EVENTS` (`custom/app/services/commerce/zid/webhooks.rb:12-13`); `salla.rb:47` | **stale internal record.** Zid now subscribes both abandoned-cart events; the Salla cell conflates "Lynomia registers none" with "no webhooks are consumed". Agent 000 should treat `01-provider-capability-matrix.md` as superseded by the adapter predicates. |
| "'Your store did not answer' | `STORE_UNAVAILABLE`"; "'We could not reach your store' | `AUTH_INVALID'"; "'These keys cannot change orders'"; "'The order changed while you were looking at it'" | the five `commerce-*` troubleshooting articles' *What you see* columns | `en/commerce.json` `COMMERCE.ERRORS.*`; the panel actually prefixes `COMMERCE.PANEL.UPDATE_FAILED` ("Couldn't refresh store data right now.") at `CommercePanel.vue:401-418` | **wrong strings.** Not one quoted sentence matches the shipped copy. Shipped: "The store is not reachable right now.", "The store rejected {installationName}'s credentials…", "The store's credentials can't change orders.", "The order changed in the store after you opened it. Nothing was sent. Review it again." A reader searching the article for the sentence on their screen will not find it. This affects all five articles and both locales. |
| "Settings → Commerce → the store → **Reconnect**" | `commerce-store-needs-reconnecting.md` | `COMMERCE.SETTINGS.ACTIONS.RECONNECT` exists; `Index.vue:34` limits it to `['zid','shopify']` | **partly wrong.** A WooCommerce store is fixed with **Replace keys**, and a Salla store is re-authorized from the Salla dashboard — the article's own description claims it covers all four platforms. |
| "A webhook carries no data… The webhook body itself is discarded." | `commerce-overview.md` | `base.rb:65-67`: order events name only the customer ids whose cached orders changed | **confirmed for order events.** Not true of cart events, which do carry cart fields into `Commerce::Cart` (`cart_lifecycle.rb:84-91`) — undocumented because carts are undocumented. |
| "Each store returns its latest 5 orders… Spend is the total of the paid orders among those" | `commerce-overview.md`, `customer-360.md` | `conversation_panel.rb:9`, `customer360.rb:22-27` | **confirmed.** Note `Customer360::LATEST_ORDERS = 10` is the *display* cap across stores (`customer360.rb:15`), a distinction neither article makes. |
| "Zid allows 60 requests a minute per store"; "Shopify returns only the last 60 days of orders" | `commerce-provider-support.md` | not expressed anywhere in `custom/app` | **unverified in this repository.** Both are provider facts, not Lynomia behaviour; they need a provider-documentation citation (agents 046/047) or should be dropped. |
