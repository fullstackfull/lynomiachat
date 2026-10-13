---
agent: 045
scope: WooCommerce commerce integration — merchant setup, keys, connection form, webhooks, capability matrix, order actions, limits, error mapping
confidence: high
---

## 1. What the feature is

WooCommerce is the only Lynomia Commerce provider connected with merchant-pasted credentials rather than an app
authorization. The merchant creates a **WooCommerce REST API v3 key** in their own WordPress admin and pastes the
consumer key/secret into Lynomia; Lynomia talks to `https://<store>/wp-json/wc/v3` over HTTP Basic
(`custom/app/services/commerce/providers/woocommerce.rb:9`, `:192-194`). There is no OAuth, no app to install, no
token refresh and no uninstall event.

It is also the most capable provider in the registry. `Commerce::Providers::Woocommerce` declares
`supports_realtime?`, `registers_webhooks?`, `supports_actions?` and `searches_orders?` all true
(`woocommerce.rb:16-20`, `:80`) — the only provider with that full set — and it is the only one whose
installation switch is on by default (`custom/app/services/commerce/switches.rb:23`:
`flag(ACTION_KEYS.fetch(provider), default: provider == 'woocommerce')`) and the only one not held behind
`PRE_UAT` (`switches.rb:16` lists `salla zid shopify` only). It is also the only provider with **no**
installation-level enable switch at all: `Commerce::Providers::Base.enabled?` returns true
(`providers/base.rb:6`) and WooCommerce never overrides it, unlike Salla (`providers/salla.rb:18`), Zid
(`providers/zid.rb:18`) and Shopify (`providers/shopify.rb:60`). WooCommerce therefore always appears in
`Commerce::Providers.enabled` (`providers.rb:15-17`), so the only gate on it is the account's `lynomia_commerce`
feature flag.

Identity model: a registered buyer is its WooCommerce customer id; a guest checkout has none, so the identity is
`guest:<email>` or `guest:<E.164 phone>` — the verified identifier it was found by (`woocommerce.rb:5-7`,
`:64-68`, `:122-129`). Candidates come from WooCommerce's broad substring search and are then kept only when a
billing/shipping email or phone matches **exactly** (`woocommerce.rb:145-151`,
`providers/woocommerce/normalizer.rb:68-70`).

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| Settings → Commerce (store list) | `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue` |
| Platform picker (step 1 of Add store) | `.../settings/commerce/ProviderPicker.vue:26-58` |
| WooCommerce connect / replace-keys dialog | `.../settings/commerce/StoreDialog.vue` |
| Conversation panel (orders) | `app/javascript/dashboard/components/widgets/conversation/commerce/CommercePanel.vue` |
| `GET/POST /api/v1/accounts/:id/commerce/stores` | `config/routes/commerce.rb:9` → `Api::V1::Accounts::Commerce::StoresController#index/#create` |
| `PATCH/DELETE .../commerce/stores/:id` | same controller `#update`/`#destroy` (`stores_controller.rb:35`, `:43`) |
| `POST /webhooks/woocommerce/:store_id` | `config/routes/commerce.rb:50` → `Webhooks::WoocommerceController#create` (`store_id` constrained to `/\d+/`) |
| `GET/POST .../conversations/:id/commerce/stores/:sid/orders/:oid/actions` | `config/routes/commerce.rb:32` → `Conversations::Commerce::OrderActionsController` |

WooCommerce has **no dedicated connection controller**. Salla, Zid and Shopify each have one
(`custom/app/controllers/api/v1/accounts/commerce/{salla,zid,shopify}_connections_controller.rb`); WooCommerce is
connected through the generic `StoresController#create`, which hard-codes the provider:
`raise ActionController::ParameterMissing, :provider unless params[:provider] == 'woocommerce'`
(`stores_controller.rb:28`). So `POST .../commerce/stores` is, in practice, the WooCommerce connect endpoint.

### Connection form

The dialog asks for the **permission choice first**, before any field (`StoreDialog.vue:22-25`, `:39-58`,
`:133-158`), defaulting to Read/Write (`:37`). The choice is purely advisory — it is never sent to the server; it
only switches the wording of step 2 of the WordPress instructions (`:53-58`, `:168`). What the key can really do
is whatever WooCommerce answers after it is saved (`:11-14`). Fields: store URL (`dir="ltr"`, placeholder
`https://shop.example.com`), display name (optional), consumer key and consumer secret (both
`type="password"`, `autocomplete="off"`, placeholders `ck_…` / `cs_…`) (`:172-202`). Keys are write-only: never
rendered back (`_store.json.jbuilder:1-17` is an explicit allow-list) and cleared whenever the dialog closes
(`:92-107`). On rotation the URL and name fields are hidden and only the key pair is sent (`:76-83`).

**Validation.** Client-side: only non-emptiness (`StoreDialog.vue:61-66`). Server-side the key pair must match
WooCommerce's exact format — `/\Ack_[0-9a-f]{40}\z/` and `/\Acs_[0-9a-f]{40}\z/`
(`stores_controller.rb:12`, `:72-81`) — and `base_url` must be present (`:27`). The URL itself is parsed by
`Commerce::StoreUrl` (`store_url.rb:30-38`): https only, default port only, no IP literal, no userinfo, query,
fragment or `..` (`:53-56`), host lowercased and trailing slashes stripped (`:46-47`). `COMMERCE_TRUSTED_STORE_HOSTS`
is an exact-host allow-list that waives the scheme/port/private-address rules for dev and staging stores only
(`store_url.rb:14-15`, `:32-35`).

**Connect sequence** (`store_connection.rb:14-20`): encryption configured → parse URL → build adapter →
`adapter.health` → `attach` (claim ownership, plan limit, save credentials, status `active`) →
enqueue `Commerce::WebhookRegistrationJob`. Credentials are saved **only after** the health check passes, so a
store never exists with keys that do not work (`store_connection.rb:1-3`). The health check is three calls:
`GET /` asserting `namespace == 'wc/v3'`, then `GET /orders?per_page=1` and
`GET /customers?per_page=1&role=all` (`woocommerce.rb:36-47`) — i.e. it proves the key can read both collections,
not just that the site is up.

### Webhook setup and authentication

Registration (`woocommerce.rb:94-108`, under `Commerce::StoreLock`): list the store's webhooks, delete any whose
`delivery_url` is already Lynomia's, generate a fresh `SecureRandom.hex(32)` secret, **save it encrypted before
WooCommerce can use it** (`:154-155`), then create one webhook per topic. Topics are
`order.created order.updated order.deleted` (`woocommerce.rb:12`), each named `Lynomia Commerce` (`:13`),
`status: 'active'`, delivery URL `#{ENV.fetch('FRONTEND_URL')}/webhooks/woocommerce/#{@store.id}` (`:170`).
Registration runs after connect, after key rotation and after re-enable (`store_connection.rb:19`, `:52`, `:64`,
`:120-122`), retries only on `STORE_UNAVAILABLE TIMEOUT RATE_LIMITED` and otherwise reports once to Sentry
(`webhook_registration_job.rb:6`, `:13-17`).

A Read key cannot create webhooks. The registration rescues `AUTH_INVALID` only, drops the stored
`webhook_secret` and records `realtime.status = 'read_only_key'` (`woocommerce.rb:101-106`, `:164-168`). That same
write is the **only proof of write access** Lynomia has: `write_access` is `granted` when registration succeeded,
`read_only_key` when it was refused, and `write_access_unverified` for stores recorded before this was tracked
(`woocommerce.rb:14`, `:25-28`).

Inbound authentication (`webhooks/woocommerce_controller.rb:8-22`, `commerce/woocommerce/webhook.rb:9-14`):
`X-WC-Webhook-Signature` must equal `base64(HMAC-SHA256(raw body, store's secret))`, compared with
`ActiveSupport::SecurityUtils.secure_compare`, **before the body is parsed**. 401 for an unsigned delivery
(WooCommerce's own unsigned creation ping included), a disconnected store, or a store with no secret. Because each
store has its own random secret, a delivery signed for one store is refused at every other store's URL. An
authentic delivery stamps store health (`:19`), and is queued only when the topic is one of `WEBHOOK_TOPICS`
(`:20`); other topics get 200 and are dropped. Deduplication is on `store.id + SHA256(delivery id, or the body
when there is no delivery id)` for 1 day (`webhook.rb:16-19`, `webhook_queue.rb:8`, `:11-16`), and the body is
encrypted before it reaches Sidekiq because Redis keeps job arguments in plaintext (`webhook_queue.rb:5-6`,
`:19`). The job only invalidates and re-reads the named customer's cached orders — **event payloads are never
stored** (`commerce/woocommerce/webhook_job.rb:1-2`, `:11`).

Disconnect deletes the webhooks first, while the credentials still exist (`woocommerce.rb:112-118`), best-effort
(`store_connection.rb:112-118`). A Read key cannot delete them, and the code states WooCommerce then disables them
itself after five refused deliveries (`woocommerce.rb:110-111`) — an external WooCommerce behaviour claim, not
verifiable in this repository.

## 3. Capability matrix — what is and is not supported

| Capability | WooCommerce | Evidence |
|---|---|---|
| Read customers (registered) | yes | `woocommerce.rb:53-60` |
| Read guest checkouts | yes, by email **or** phone | `woocommerce.rb:58`, `:64-66` — the only provider matching guests by phone |
| Latest orders beside a conversation | yes, 5 | `conversation_panel.rb:9`, `:60` |
| Order lookup by id | yes | `woocommerce.rb:72-77` |
| Order search by number | yes, **because the id is the number** | `woocommerce.rb:79-80`, `providers/base.rb:33-39` |
| Admin "view order" link | yes, built from stored URL + numeric id | `woocommerce.rb:83-88` |
| Payment status | derived, not read | `normalizer.rb:4-12`, `:74-81` |
| **Shipments / tracking** | **NOT SUPPORTED** — `shipments: []`, `tracking: nil` always | `normalizer.rb:14-15`, `:35` |
| **Status `shipped` / `delivered`** | **NOT SUPPORTED** — not in the status map | `normalizer.rb:17-20` |
| Live updates (webhooks) | yes, **Read/Write key only** | `woocommerce.rb:94-108` |
| Order actions | yes, 6 of 7 (see §4) | `providers/woocommerce/actions.rb` |
| **Update shipping / address** | **NOT SUPPORTED** — no capability key, so reported `unsupported` | `actions.rb:14`, `order_actions.rb:129` |
| **Abandoned carts / recovery** | **NOT SUPPORTED at the source** — `supports_carts?` never overridden, and `RECOVERY_KEYS` has no WooCommerce entry at all | `providers/base.rb:87`, `switches.rb:15`, `abandoned_carts.rb:18-21` |
| Token refresh / background refresh | **NOT APPLICABLE** — key auth, no token | `woocommerce.rb:1` |
| Uninstall detection | **NOT SUPPORTED** — no app, no event | — |
| Customer-facing order URL | **NOT SUPPORTED** — `customer_order_url: nil` | `normalizer.rb:35` |

Two further honest limits. WooCommerce numbers orders by their internal id, so a plugin that renumbers orders
breaks order search (`woocommerce.rb:79`). And payment status is *inferred*: `on-hold`, cash-on-delivery before
completion, cancelled and any custom status all resolve to `unknown` (`normalizer.rb:11-12`, `:80`).

## 4. Order actions

Allow-listed, judged from the order as the store returns it **now** (`actions.rb:1-17`, `:79-89`).

| Action | When available | Store call |
|---|---|---|
| `update_order_status` | `processing → completed\|on_hold`, `on-hold → processing` only | `PUT /orders/{id} {status}` (`actions.rb:20`, `:129-133`) |
| `cancel_order` | `pending` or `on-hold` only; restocks, refunds nothing | `PUT /orders/{id} {status: cancelled}` (`actions.rb:22`, `:91-96`) |
| `refund_full` / `refund_partial` | `processing\|completed` **and** `date_paid_gmt` present, remaining > 0 | `POST /orders/{id}/refunds` (`actions.rb:98-107`, `:135-141`) |
| `resend_invoice` | `processing\|completed\|on-hold`, billing email present | `POST /orders/{id}/actions/send_order_details` (`actions.rb:24`, `:58`) |
| `resend_payment_link` | `pending\|failed` and `needs_payment != false`, billing email present | same endpoint (`actions.rb:25`, `:87`) |
| `update_shipping` | never | no key in `capabilities` (`actions.rb:14`) |

Refund mode is decided by reading `GET /payment_gateways/{payment_method}`: `gateway` when the gateway is enabled
and lists `refunds` in `method_supports`, else `manual` — recorded only, no money moves (`actions.rb:118-127`).
Unknown or unreadable gateway means `manual`, except that `AUTH_INVALID TIMEOUT STORE_UNAVAILABLE` are re-raised
(`:123-126`). Maximum = total − every refund the store reports (`:101`, `:198-200`). Refunds are amount-only:
`api_restock: false`, no line items (`:137`).

**Idempotency.** WooCommerce has none, so Lynomia sends once and never retries (`actions.rb:16-17`,
`http_client.rb:67-71`). Each refund carries `meta_data: [{key: 'lynomia_action_key', value: <idempotency key>}]`
(`actions.rb:30`, `:137`), which is how a lost answer is reconciled: refunds are re-read and matched on that key
(`:160-167`). Status changes reconcile on the order's status (`:66-74`). "Nothing changed" only proves
non-application after `SETTLED_AFTER = 5.minutes`, because PHP may still have been executing (`actions.rb:35-37`,
`:176`). Resending an email is **not reconcilable** — a lost answer stays `unknown` forever (`actions.rb:1-17`
header; `base.rb:83`).

Seven gates run before any write, in order (`order_actions.rb:7-15`, `:103-115`): provider supports actions →
`COMMERCE_ACTIONS_ENABLED` → `WOOCOMMERCE_ACTIONS_ENABLED` → the store's per-store opt-in
(`settings['order_actions']`) → write access → `Commerce::ActionPolicy` → the order's current state. The
executor re-checks all of them, re-reads the order and compares the version the agent confirmed before sending
(`action_executor.rb:5-10`, `:57-88`).

## 5. User-visible states

| State | What produces it |
|---|---|
| Platform shown "Not available yet" | `providers` from the index response; WooCommerce is never in this state (no `enabled?` override) — `ProviderPicker.vue:54-57`, `index.json.jbuilder:3` |
| Store limit banner / blocked Add store | `Billing::ResourceLimit`; disconnected stores do not count — `Index.vue:50-57`, `index.json.jbuilder:7-10` |
| `Active` / `Disabled` / `Needs re-authorization` / `Disconnected` | `Commerce::Store` status enum — `custom/app/models/commerce/store.rb:42`, `Index.vue:38-43` |
| "Live order updates on" | `realtime.status == 'active'` — `Index.vue:393-405` |
| "Live order updates off: this key is read-only." | `realtime.status == 'read_only_key'` — same |
| No live-updates line at all | `realtime_status` nil (registration never completed) — `Index.vue:393` |
| "Order actions: on / off" | opt-in with `order_actions_status == 'available'` — `Index.vue:211-233` |
| "Order actions require a Read/Write WooCommerce API key." | `read_only_key` **or** `write_access_unverified` — `Index.vue:218-222` |
| "Order actions are switched off on this installation." | `actions_disabled` / `provider_actions_disabled` — `Index.vue:227-229` |
| Panel `linked` with stale data | cache fallback up to 24 h with the fetch time and error code — `cache.rb:8-10`, `conversation_panel.rb:63-64` |
| Panel `not_found` / `suggested` / `multiple` | candidate count — `conversation_panel.rb:72-78` |
| Panel `unavailable` | a `Commerce::Error` with no usable cache — `conversation_panel.rb:27` |
| "Just refreshed. Try again in {seconds} s." | 30 s per store+contact, shared by all viewers — `refreshes_controller.rb:8` |
| Action result `UNKNOWN` / `UNRESOLVED` | lost answer; reconciliation at 30 s, 2 min, 10 min then exhausted — `action_executor.rb:15`, `:141-151` |

## 6. Errors and validation messages

Every backend error is a `Commerce::Error` code from the fixed list in `custom/app/services/commerce/error.rb:4-10`,
rendered as `{ error: { code, reason } }` with 422 (`stores_controller.rb:18-20`,
`order_actions_controller.rb:11-18`) and mapped to a string by `useCommerceLabels.js:54-107`. Strings are in
`app/javascript/dashboard/i18n/locale/en/commerce.json`.

| Trigger (WooCommerce path) | Code | String | `file:line` |
|---|---|---|---|
| HTTP 401 from the store | `AUTH_INVALID` | "The store rejected {installationName}'s credentials…" | `http_client.rb:225`, `commerce.json:134` |
| HTTP 403 | `PERMISSION_DENIED` | "The store refused access to its orders or customers…" | `http_client.rb:226`, `commerce.json:135` |
| HTTP 404 | `NOT_FOUND` | "This link request expired. Search again." | `http_client.rb:227`, `commerce.json:139` |
| HTTP 429 | `RATE_LIMITED` | "The store is limiting requests. Try again in a moment." | `http_client.rb:228`, `commerce.json:136` |
| HTTP 5xx | `STORE_UNAVAILABLE` / `http_<code>` | "The store is not reachable right now." | `http_client.rb:229`, `commerce.json:133` |
| `wp-json` not WooCommerce v3, or 404 on health | `STORE_UNAVAILABLE` / `woocommerce_api_not_found` | same string | `woocommerce.rb:38`, `:44` |
| DNS failure | `STORE_UNAVAILABLE` / `dns` | same string | `http_client.rb:157` |
| TLS failure | `STORE_UNAVAILABLE` / `tls` | same string | `http_client.rb:237` |
| Dropped connection after retry | `STORE_UNAVAILABLE` / `connection` | same string | `http_client.rb:237` |
| Request provably never sent (write path) | `STORE_UNAVAILABLE` / `not_sent` | same string | `http_client.rb:122-123` |
| Connect/read/body timeout | `TIMEOUT` | "The store took too long to answer." | `http_client.rb:161`, `:205` |
| Lost answer on a write | `TIMEOUT` / `unknown_outcome` → run `UNKNOWN_OUTCOME` | "The store didn't answer in time. {installationName} is checking…" | `http_client.rb:124-125`, `action_executor.rb:62`, `commerce.json:158` |
| Non-JSON body | `INVALID_RESPONSE` / `not_json` | "The store sent a response {installationName} could not read." | `http_client.rb:219` |
| Body over 5 MB | `INVALID_RESPONSE` / `too_large` | same | `http_client.rb:204` |
| Array expected, object returned | `INVALID_RESPONSE` / `unexpected_shape` | same | `woocommerce.rb:181`, `:74`, `:158`, `actions.rb:171`, `:186` |
| Malformed order / customer JSON | `INVALID_RESPONSE` / `malformed_order` \| `malformed_customer` | same | `normalizer.rb:39`, `:53`, `:64` |
| Order id belongs to another order | `INVALID_RESPONSE` / `other_order` | same | `order_actions.rb:95` |
| 3xx from the store | `INVALID_STORE_URL` / `redirect` | "The store redirected to another address…" | `http_client.rb:224`, `commerce.json:173` |
| URL unparseable / userinfo / query / fragment / `..` | `INVALID_STORE_URL` / `invalid` | "Enter the store address, for example https://shop.example.com." | `store_url.rb:44`, `:49`, `commerce.json:168` |
| `http://` on an untrusted host | `INVALID_STORE_URL` / `https_required` | "The store must use https." | `store_url.rb:33`, `commerce.json:169` |
| non-default port | `INVALID_STORE_URL` / `port_not_allowed` | "Custom ports are not supported." | `store_url.rb:34`, `commerce.json:170` |
| IP literal | `INVALID_STORE_URL` / `ip_address_not_allowed` | "Use the store's domain name, not an IP address." | `store_url.rb:35`, `commerce.json:171` |
| Host resolves private/metadata | `INVALID_STORE_URL` / `private_address` | "This address points to a private network…" | `http_client.rb:154-155`, `commerce.json:172` |
| `SsrfFilter::Error` (other) | `INVALID_STORE_URL` / `invalid` | as above | `http_client.rb:158-159` |
| Encryption not configured | `ENCRYPTION_NOT_CONFIGURED` | "Store credentials can't be saved: encryption is not configured…" | `store_connection.rb:125`, `commerce.json:142` |
| Store owned by another account | `STORE_ALREADY_CONNECTED` | "This store is already connected." | `store_connection.rb:38`, `:141`, `commerce.json:143` |
| Plan store limit reached | `STORE_LIMIT_REACHED` | "You've connected all the stores your plan allows…" | `store_connection.rb:132`, `commerce.json:165` |
| Re-enable with no credentials | `AUTH_INVALID` | as above | `store_connection.rb:58` |
| Search term not an email or E.164 phone | `INVALID_QUERY` | "Enter an exact email, or a phone number starting with +…" | `conversation_panel.rb:32`, `orders_controller.rb:19`, `commerce.json:141` |
| Order actions off for the store | `ACTIONS_DISABLED` | "Order actions are off for this store." | `order_actions.rb:27-28`, `commerce.json:147` |
| Read key / unverified write access | `WRITE_ACCESS_DENIED` | "The store's credentials can't change orders. An administrator can replace them." | `order_actions.rb:28-29`, `woocommerce.rb:27`, `commerce.json:153` |
| Store answers 401 to a write | `WRITE_ACCESS_DENIED`, and the store is re-flagged `read_only_key` | same | `actions.rb:147`, `:155-158` |
| Order state no longer allows the action | `ACTION_UNAVAILABLE` (+ reason `order_state`, `not_paid`, `nothing_refundable`, `paid_refund_first`, `already_cancelled`, `no_email`, `target_status`, `unsupported`) | per-reason strings | `actions.rb:83-114`, `:202`, `action_executor.rb:83`, `:97`, `commerce.json:349-361` |
| Earlier unresolved action on the order | `ACTION_IN_PROGRESS` | "Another action on this order is still being processed." | `order_actions.rb:83`, `commerce.json:149` |
| Order version changed after review | `ORDER_CHANGED` | "The order changed in the store after you opened it. Nothing was sent." | `action_executor.rb:80`, `commerce.json:150` |
| Amount wrong currency / precision / above refundable / not full | `INVALID_AMOUNT` (+ reason) | "The amount isn't valid for this order. Nothing was sent." | `order_actions.rb:195`, `action_executor.rb:102-111`, `commerce.json:151` |
| Idempotency key reused for a different request | `IDEMPOTENCY_CONFLICT` | "This confirmation was already used. Start again." | `order_actions.rb:206`, `commerce.json:152` |
| Store answers 400/403/404/409/422 to a write | `PROVIDER_REJECTED` (404 → `NOT_FOUND`) | "The store refused this change." | `actions.rb:31-32`, `:148`, `commerce.json:155` |
| 500 `woocommerce_rest_cannot_create_order_refund` | `REFUND_DECLINED` | "The payment gateway refused the refund. No money was sent." | `actions.rb:33`, `:149`, `commerce.json:156` |
| Reconciliation proves non-application | `NOT_APPLIED` | "The store shows the change wasn't made. You can try again." | `actions.rb:70`, `:164`, `commerce.json:154` |
| Action rate limit hit | `RATE_LIMITED` + `Retry-After`, HTTP **429** | "Too many actions were requested on this order. Try again in {seconds} s." | `order_actions.rb:218`, `order_actions_controller.rb:12-14`, `commerce.json:335` |
| Unknown action type / bad version or key format | `INVALID_REQUEST` | "This request isn't valid." | `order_actions.rb:71`, `:73`, `commerce.json:157` |

**Not covered by a code.** Malformed key format, a missing `base_url`, `provider != 'woocommerce'`, an invalid
`status` and a non-boolean `order_actions` all raise `ActionController::ParameterMissing`
(`stores_controller.rb:28`, `:62`, `:67`, `:77`), which the shared handler renders as 422 with a **string** body:
`render json: { error: sanitized_error_message(error) }`
(`app/controllers/concerns/request_exception_handler.rb:27-29`, `:46-48`). `apiErrorMessage` reads
`data.error.code`, finds nothing, and falls back to `COMMERCE.ERRORS.GENERIC` — "Something went wrong. Try again."
(`useCommerceLabels.js:103-107`, `commerce.json:146`). A merchant who pastes a truncated, upper-case-hex or
whitespace-broken key therefore gets no indication that the *format* is the problem, and the dialog does no
client-side format check either (`StoreDialog.vue:61-66`).

## 7. Failure paths

1. **Read key pasted while Read/Write was selected.** Connect succeeds (health is read-only), then
   `WebhookRegistrationJob` gets a 401 on the webhook POST, drops the secret and records `read_only_key`
   (`woocommerce.rb:101-106`). The store shows "Live order updates off: this key is read-only." and order actions
   cannot be turned on. Recoverable, and the UI says how. **But** the rescue matches `AUTH_INVALID` only
   (`:102`): if WooCommerce or a WAF answers 403 instead, `PERMISSION_DENIED` escapes to Sentry
   (`webhook_registration_job.rb:13-16`), `realtime_status` stays nil, the store silently has no live updates and
   the UI shows **no line at all** (`Index.vue:393`). Not verified against a live store.
2. **A WooCommerce store flagged `needs_reauth`** (set whenever any read or action gets `AUTH_INVALID` —
   `conversation_panel.rb:121`, `order_actions.rb:98`, `order_search.rb:37`, `realtime.rb:96`,
   `abandoned_carts.rb:36`, `store_connection.rb:80-86`) has **no Reconnect button and no hint**: `canReconnect`
   requires `disconnected` or a provider in `REAUTHORIZED_HERE = ['zid','shopify']` (`Index.vue:34`, `:93-97`),
   and the reauth hint renders only for non-key providers (`Index.vue:437-443`). The only cue is the amber
   "Needs re-authorization" badge plus a "Replace keys" button whose label does not say it is the fix.
3. **`write_access_unverified`** (a store connected before write access was tracked) is shown as
   "Order actions require a Read/Write WooCommerce API key." (`Index.vue:218-222`) even though the key may be
   Read/Write and merely unproven. The real fix is to re-save the keys so registration runs again
   (`store_connection.rb:52`); nothing in the UI says so.
4. **Store URL that redirects.** Redirects are never followed (`http_client.rb:180`), so `www.` → apex,
   trailing-slash and HTTP→HTTPS redirects all surface as "The store redirected to another address. Enter the
   final store URL." The merchant must supply the final URL.
5. **Security plugin or `wp-json` blocked.** `STORE_UNAVAILABLE / woocommerce_api_not_found`
   (`woocommerce.rb:38`, `:44`) renders the same generic "not reachable" string as a dead host — the distinguishing
   `reason` is in the payload but never shown.
6. **Lost answer on a refund.** The run goes `unknown`, is never re-sent, and is reconciled by reading refunds and
   matching `lynomia_action_key` at 30 s / 2 min / 10 min; after that it stays `unknown` with
   `reconcile: 'exhausted'`, stops blocking the order, and the agent is told to check the store
   (`action_executor.rb:15`, `:141-151`, `commerce.json:409`).
7. **Resend invoice / payment link lost.** Unreconcilable by construction — an email leaves no state
   (`base.rb:83`, `actions.rb:73`). The agent can only check the order notes in WordPress. The UI's "check the
   order in the store" wording does not say to look at order notes.
8. **Plugin-renumbered orders.** Order search silently finds nothing (`woocommerce.rb:79`, `base.rb:33-39`).

## 8. Rate limits and timeouts

All in `Commerce::HttpClient` and shared with every provider (`http_client.rb:15-29`): connect/TLS 3 s, read and
write 8 s, **25 s for an order action** because a payment gateway may be slow (`:16-17`), whole-body deadline 10 s
(`:201-206`), body cap 5 MB. One retry, **GET only**, only for `ECONNRESET`/`EOF` or 502/503/504; timeouts are
never retried, so a slow store costs at most one timeout (`:20-23`, `:135-150`). POST, PUT and DELETE are never
retried (`:67-76`, `:117-126`).

WooCommerce imposes no documented rate limit of its own; `RATE_LIMITED` for this provider comes from a 429 emitted
by the store's host or WAF (`http_client.rb:228`). `X-RateLimit-*` and `Retry-After` are captured if present
(`:27-28`, `:174`) but WooCommerce does not send them. Lynomia's own limits: order actions throttled at 10 per
user/min, 30 per store/min, 5 per order/10 min (`order_actions.rb:25`, `:212-220`); panel refresh 30 s per
store+contact (`refreshes_controller.rb:8`); cache fresh 120 s, stale fallback up to 24 h
(`cache.rb:8-10`); `SEARCH_LIMIT = 20` for order search, `per_page: 100` for webhook and refund listings
(`woocommerce.rb:11`, `:96`, `actions.rb:170`); webhook dedup window 1 day (`webhook_queue.rb:8`).

## 9. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| Any Commerce API | account feature `lynomia_commerce` | `stores_controller.rb:50-52`, `order_actions_controller.rb:32-34` |
| List / connect / rotate / enable / disable / disconnect / opt in to actions | account **administrator** | `custom/app/policies/commerce/store_policy.rb:3-18`, `stores_controller.rb:15` |
| View the Commerce panel, search, link, unlink | anyone who can view the conversation | `Conversations::BaseController`, `docs/commerce/08-woocommerce-security.md:91` |
| Ask what actions are possible | anyone who can view the conversation | `order_actions_controller.rb:1-3`, `:20-22` |
| `update_order_status`, `resend_invoice`, `resend_payment_link` | administrator **or** custom-role permission `commerce_order_manage` | `custom/app/policies/commerce/action_policy.rb:8-21` |
| `cancel_order`, `refund_full`, `refund_partial` | **administrators only** — no custom role grants these | `action_policy.rb:23-29` |
| Order actions at all | `COMMERCE_ACTIONS_ENABLED` + `WOOCOMMERCE_ACTIONS_ENABLED` (both default on) + per-store opt-in | `switches.rb:19-24`, `order_actions.rb:104-109` |
| Provider availability | none — WooCommerce has no installation switch | `providers/base.rb:6` (never overridden) |
| Agent bots | never | `docs/commerce/08-woocommerce-security.md:94` |

## 10. Contextual-help opportunities

| UI location | The question there | Registry key | Exists? |
|---|---|---|---|
| `StoreDialog.vue:212-215` | "how do I create the key?" | `commerceWoocommerce` → `connect-woocommerce` | yes, linked |
| `ProviderPicker.vue:118` | "what will each platform give me?" | `commerceProviders` → `commerce-provider-support` | yes, linked |
| `CommercePanel.vue:415` | per-error help in the panel | `COMMERCE_ERROR_ARTICLES` (`documentationLinks.js:109-133`) | yes, linked |
| `StoreDialog.vue:203-209` (error paragraph) | "why was my URL/key refused?" | `commerceStoreAddress`, `commerceStorePermissions` | keys exist; **the dialog links only the static connect article** |
| `Index.vue` page header | "what is Commerce and what can it do?" | `commerce` → `commerce-overview` | key exists; **no `DocsLink` anywhere in `Index.vue`** |
| `Index.vue:393-405` live-updates line | "why are live updates off?" | `commerceStorePermissions` (keys article) | key exists; **not linked** |
| `Index.vue:437-443` / `needs_reauth` badge | "what does Needs re-authorization mean for a key store?" | `commerceStoreReconnect` | key exists; **not linked, and no hint text for WooCommerce** |
| `Index.vue:315-320` store-limit banner | "why can't I add a store?" | none | **no key**: `STORE_LIMIT_REACHED` is absent from `COMMERCE_ERROR_ARTICLES` |
| Connect failure `STORE_ALREADY_CONNECTED` / `ENCRYPTION_NOT_CONFIGURED` | "who has this store?" / "why can't keys be saved?" | none | **no key** in `COMMERCE_ERROR_ARTICLES` |
| `Index.vue:447-463` order-actions toggle | "what will agents be able to do?" | `commerceOrderAction` | key exists; **not linked** |

## 11. Current documentation coverage

- `custom/db/documentation/en/commerce/connect-woocommerce.md` (103 lines, AR counterpart present) is strong and
  largely accurate: the Read vs Read/Write table, the WordPress steps, the health check, the limits section (no
  shipments, id-based order search, the action allow-list, gateway vs recorded refund, the three
  `Lynomia Commerce` webhooks, no abandoned carts) and a five-item troubleshooting section all match the code.
- `custom/db/documentation/en/commerce/commerce-provider-support.md` carries the cross-provider matrix; its
  WooCommerce column matches `providers/base.rb` and `actions.rb`, including "latest 5 orders"
  (`conversation_panel.rb:9`) and "Find an order by its number: yes".
- Five troubleshooting articles are wired to error codes:
  `commerce-store-needs-reconnecting`, `commerce-store-unreachable`, `commerce-store-address-refused`,
  `commerce-keys-cannot-do-that`, `commerce-order-action-did-not-apply`
  (`documentationLinks.js:74-78`, `custom/db/documentation/en/troubleshooting/`).
- `commerce-order-action-did-not-apply.md` mentions WooCommerce **zero** times despite WooCommerce being the only
  provider whose actions are live.

## 12. Missing or stale documentation

1. **`needs_reauth` on a WooCommerce store** is undocumented for the no-Reconnect-button case (§7.2). The
   connect article's troubleshooting covers "the store rejected the credentials" but not the status badge, and
   `commerce-store-needs-reconnecting` is not linked from the store row.
2. **`write_access_unverified`** is documented nowhere, in either the corpus or `docs/commerce/`, although it is a
   reachable state for any store connected before write-access tracking (`woocommerce.rb:25-28`).
3. **The permission choice is advisory.** The dialog's own comment says so (`StoreDialog.vue:11-14`) and the
   article hints at it, but neither states plainly that selecting "Read/Write" and then pasting a Read key
   produces a working but read-only store.
4. **Malformed-key feedback.** Nothing documents that a badly formatted key yields only "Something went wrong.
   Try again." (§6), nor that keys are exactly `ck_`/`cs_` + 40 lower-case hex characters.
5. **Timeouts and the 24 h stale window.** No article states the 3 s / 8 s / 25 s / 10 s budgets, the single
   GET-only retry, the 120 s cache or that an unreachable store can show orders up to 24 hours old with a
   "last updated" time (`cache.rb:8-10`).
6. **Order-action rate limits** (10/user/min, 30/store/min, 5/order/10 min) appear in no article, though the
   panel string "Too many actions were requested on this order" is user-facing (`commerce.json:335`).
7. **Resend-email actions are unreconcilable.** No article tells an agent that the fix for an `unknown` resend is
   to read the WordPress order notes (`actions.rb:46-49` in `docs/commerce/29`).
8. **`COMMERCE_TRUSTED_STORE_HOSTS`** — the only way to connect an `http`/custom-port/private store — is in
   `docs/commerce/08-woocommerce-security.md` but in no operator-facing article.

## 13. Doc claims not proven by code

These are internal design records, not the published corpus, and they are a merge hazard for anyone writing from
them:

| Claim | Where | What HEAD shows |
|---|---|---|
| "Read keys only … only GET requests exist in code … a write … is never attempted" | `docs/commerce/08-woocommerce-security.md:21` | False at HEAD: `register_webhooks` POSTs and DELETEs (`woocommerce.rb:98`, `:157`) and `Actions` PUTs and POSTs (`actions.rb:130`, `:138`, `:58`) |
| "Webhooks — None in Phase 2: no endpoint, no fake endpoint" | `docs/commerce/08-woocommerce-security.md:117-119` | A live endpoint and signature check exist (`config/routes/commerce.rb:50`, `webhooks/woocommerce_controller.rb`) |
| "Lynomia still only sends GETs. Rotate to a Read key." | `docs/commerce/08-woocommerce-security.md:146` | Contradicts the shipped Read/Write recommendation (`commerce.json:217`) and the write paths above |
| "Each read / write 8 s" | `docs/commerce/08-woocommerce-security.md:72` | 25 s for an order action (`http_client.rb:16-17`) |
| "`per_page` ≤ 20" | `docs/commerce/08-woocommerce-security.md:75` | `per_page: 100` for webhook and refund listings (`woocommerce.rb:96`, `actions.rb:170`) |
| `woocommerce_spec` "exposes no write operation" | `docs/commerce/08-woocommerce-security.md:21` | No such example exists in `spec/services/commerce/providers/woocommerce_spec.rb` |

Unverified external claims (correct to state as WooCommerce behaviour, but not provable here): WooCommerce
disables a webhook after five refused deliveries (`woocommerce.rb:110-111`, repeated in
`connect-woocommerce.md:78-79`); `send_order_details` requires WooCommerce 9.8+
(`docs/commerce/29-provider-action-capabilities.md:46`); WooCommerce answers 401 rather than 403 for an
insufficient-permission write (§7.1). None was tested against a live store — no WooCommerce credentials exist in
this environment (`docs/commerce-production/01-provider-capability-matrix.md:102`).
