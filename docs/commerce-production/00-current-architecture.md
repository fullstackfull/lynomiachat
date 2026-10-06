# 00 — The Commerce architecture as it stands

Read at HEAD. Commerce lives entirely in the `custom/` overlay — not `app/`, not `enterprise/` — across 115 Ruby
files. Four providers: `woocommerce`, `salla`, `zid`, `shopify`.

This document records what exists so that `01`–`05` can argue from it. Nothing here is a proposal.

---

## 1. The data model — four tables, and no fifth

| Table | Holds |
|---|---|
| `commerce_stores` | the connection: `account_id`, `provider`, `external_store_id`, `name`, `base_url`, `status`, `credentials` (encrypted), `settings`, `metadata` |
| `commerce_customer_links` | provider customer ↔ Lynomia contact: `account_id`, `commerce_store_id`, `contact_id`, `external_customer_id` (deterministically encrypted), `match_source`, `confirmed_by_id` |
| `commerce_action_runs` | one attempted write action, its idempotency key and its outcome |
| `commerce_contact_metrics` | a contact's order rollup: `orders_count`, `active_orders_count`, `last_purchase_at`, `spend`, and the status maps |

**There is no cart table.** `commerce_contact_metrics` has order columns only. This matters for Stage B and is the
subject of `05`.

`Commerce::Store` keeps `PROVIDERS` as a plain string column with an inclusion validation rather than a Rails
enum; only `status` is an enum (`active`, `disabled`, `needs_reauth`, `disconnected`). Credentials are a single
encrypted JSON blob, stripped from `serializable_hash` and absent from the jbuilder view, and the model refuses to
save at all if encryption keys are not configured.

Store ownership is enforced by a **global** unique index on `(provider, external_store_id)`, so two accounts
cannot hold the same store. `Commerce::StoreConnection#claim` defines the only transfer rule: the same account may
reconnect its own disconnected store; another account's *disconnected* row is destroyed and taken; anything else
raises `STORE_ALREADY_CONNECTED`.

## 2. Identity and matching

`Commerce::CustomerMatcher` tries three things in order, and the order is the product rule:

1. an existing non-suppressed link for this contact **in this store** — returned without calling the store;
2. a **trusted phone** taken from the *channel identity*, not the contact record: WhatsApp `source_id` when it is
   1–15 digits, SMS/Twilio `source_id`. A web or email conversation yields nothing, and a WhatsApp BSUID username
   yields nothing;
3. the agent-editable contact email and phone — as **suggestions only**, never auto-linked.

A link is created automatically only when exactly one exact verified-phone match comes back, and never when a
`suppressed` tombstone exists for that pair. Phone normalization is the installation's single rule
(`Contacts::Phone.e164`): `00…` becomes `+…`, a `+`-prefixed number parses alone, and a local number parses only
with an explicit region — otherwise nil, never a guessed country.

Two facts worth stating plainly because they bound what Stage B may assume:

- **`commerce_customer_links` is unique on `(commerce_store_id, contact_id)` only.** There is no uniqueness on
  `(commerce_store_id, external_customer_id)`, so one store customer may legitimately be linked from several
  contacts in the same store.
- **The auto-link does not check cache freshness.** `CustomerMatcher` fetches candidate customers through
  `Commerce::Cache.fetch` and auto-links on a single verified-phone match without inspecting whether that entry
  was served stale (up to 24 hours old). Reported in `04` as a finding, with its blast radius.

## 3. The cache

`Commerce::Cache`: `FRESH_FOR = 120.seconds`, `KEEP_FOR = 24.hours`, over `Redis::Alfred`. A stale entry is served
when the provider answers `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED` or `INVALID_RESPONSE`, and the entry
carries a `stale` flag so a caller can tell. Keys are HMAC'd under an account-and-store prefix, which is what
makes cross-account key collision impossible.

The product rule this is meant to serve — reads may degrade to stale, writes must use current provider truth — is
examined in `04`, because one caller does not honour it.

## 4. Write actions

`Commerce::ActionRun` records every attempted write with an idempotency key; `Commerce::ActionExecutor` dispatches
it; `Commerce::OrderActions` reports per-action availability to the API and refuses anything the adapter does not
claim. `Commerce::Providers::Base` is the interface, and the defaults are deliberately negative
(`supports_actions?` false, `supports_carts?` false, `registers_webhooks?` false), so a provider has what it
overrides and nothing more.

What each provider can actually write:

| Provider | Writes |
|---|---|
| WooCommerce | `update_order_status` (allow-listed transitions only), `cancel_order`, `refund_full`, `refund_partial`, `resend_invoice`, `resend_payment_link`, plus its own webhook registration |
| Zid | `update_order_status`, and only `ready → shipped` and `indelivery → delivered`; plus webhook subscription management. Everything else raises `ArgumentError` |
| Shopify | `cancel_order`, `refund_full`, `refund_partial` — all three gated `PRE_UAT` |
| Salla | **nothing**, and structurally so: `salla/tokens.rb` refuses to store a token carrying any scope that is not `offline_access` or `*.read` |

## 5. Webhooks

| Provider | Endpoint | Auth | Job |
|---|---|---|---|
| WooCommerce | `POST /webhooks/woocommerce/:store_id` | shared secret in encrypted credentials | `Commerce::Woocommerce::WebhookJob` |
| Zid | `POST /webhooks/zid/:store_id` | HTTP Basic, per store | `Commerce::Zid::WebhookJob` |
| Shopify | `POST /webhooks/shopify_commerce` | HMAC, 90 s tolerance | `Commerce::Shopify::WebhookJob` |
| Salla | — | — | **none registered** |

All three that exist funnel through `Commerce::WebhookQueue`, which deduplicates on
`store.id` + SHA-256 of the raw body for 24 hours and encrypts the body before handing it to Sidekiq — because
Sidekiq keeps job arguments in Redis in plaintext and these payloads carry names, emails and phone numbers.

`Commerce::Realtime` is what a delivered webhook ultimately does: invalidate the affected caches so the next read
re-fetches. **Lynomia keeps no order database**, which is why webhooks carry no persistence burden today.

## 6. Automation and audience surfaces

`Automation::CommerceEvents` exposes Commerce events to the existing `AutomationRule` engine through the
authoritative trigger registry. `Commerce::ContactMetric` backs the Audience Commerce conditions.
`Commerce::OrderTransitions` is the precedent worth noting for Stage B: it diffs previous against current order
state and **persists** the result in `commerce_contact_metrics.order_states`. Orders have a transition engine.
Carts have no equivalent.

## 7. The existing cart code, and what it actually is

A **read-through viewer over three provider cart APIs** — not a cart system.

| | |
|---|---|
| The cart object | `Commerce::AbandonedCart` is a `Data.define` value object. Its own header says "kept in the Redis cache only, never in Postgres" |
| Persistence | none. Two cache kinds: `:carts` per contact, `:cart_queue` per store |
| Lifecycle | none. No state machine, no stored previous state, no job advancing a cart |
| Status | recomputed from the provider's current payload on every read |
| `expired` | not a status — a display filter dropping carts older than `MAX_AGE = 30.days`. The class comment advertises four statuses (`abandoned`, `recovered`, `expired`, `unknown`); **no adapter ever produces `expired` or `unknown`** |
| "never offered twice" | implemented by cache eviction — `Commerce::Realtime#drop_carts` on any order or cart event |
| The one durable trace | a `Commerce::ActionRun` of type `recovery_message`, keyed by the provider cart id, holding only an HMAC digest of the recovery URL, the total, the currency and the match kind. Swept after 90 days |
| Send attribution | `Commerce::RecoveryListener` matches an outgoing message's HTTPS link digest to a pending run within 24 hours. That is *message-sent* attribution — there is no link from a sent run to any later order anywhere in the codebase |

**And all of it is off in production.** `Commerce::Switches` puts `salla`, `zid` and `shopify` in
`PRE_UAT[:recovery]`, released only by the ENV-only `COMMERCE_ALLOW_PRE_UAT_PROVIDERS`, documented in the file
itself as "staging and simulated E2E runs only, never production". WooCommerce has no recovery key at all, so it
is false by a different route. `spec/services/commerce/switches_spec.rb` pins all four providers false by default.

How each adapter decides "abandoned" — the whole of it:

```ruby
# Zid — providers/zid/carts.rb
recovered = raw['phase'].to_s == 'completed' || raw['order_id'].present?
{ status: recovered ? 'recovered' : 'abandoned', ... }

# Shopify — providers/shopify/carts.rb
status: raw['completedAt'].present? ? 'recovered' : 'abandoned', recovered_at: raw['completedAt']

# Salla — providers/salla/carts.rb
status: 'abandoned', recovered_at: nil      # hardcoded; membership in the list *is* the status
```

In all three, **abandonment is the `else` branch** — the absence of a recovery signal is read as abandonment. That
is the hazard Stage B must not inherit, and `05` §5 addresses it.
