# 08 — Provider support, security decisions, and user-facing wording

---

## 1. Per-provider abandoned-cart support

| Provider | Capability state | Why |
|---|---|---|
| **Zid** | **LIMITED — software complete, real UAT blocked** | The only provider with provider-native abandonment *and* completion, a stable id, real timestamps and provider-side cart→order correlation. Ingestion is built and gated PRE_UAT |
| Salla | **NOT SUPPORTED** | Recovery is undetectable by construction: `status: 'abandoned'` is hardcoded and a bought cart and a deleted cart both simply vanish. A recovery figure for Salla could only ever be fabricated |
| Shopify | **NOT SUPPORTED** | A lifecycle would be inferred from polling a `status:open` list that structurally cannot show recoveries; also PRE_UAT and behind Shopify's protected-customer-data review |
| WooCommerce | **NOT SUPPORTED** | No cart data reaches the connector at all — `supports_carts?` is false and there is no recovery switch key. An absence at the source, not a gap in Lynomia |

**Nothing is labelled SUPPORTED.** Zid is `LIMITED` until a real store clears the UAT in `09`. "COMING LATER" is
not used for the other three: Salla's and WooCommerce's are structural, not scheduled.

## 2. The cart URL: the security decision

Zid supplies `url`, a direct checkout link, and it is **not persisted**.

The reasoning is specific rather than general caution. A checkout URL for an abandoned cart is effectively a
**bearer credential for someone else's basket**: anyone holding it can open that cart, and in many storefronts
act on it. Persisting one for every cart, indefinitely, is a standing disclosure risk that buys nothing the
lifecycle needs — the row's job is state, not content.

The repository already contains the safer pattern, and it is reused rather than reinvented:
`Commerce::RecoveryMessages` stores only an **HMAC digest** of the recovery URL and validates the real one through
`Commerce::RecoveryUrl` at the moment an agent asks for it. So the link is derived on demand from the provider,
and what is stored cannot be replayed.

Two regressions pin it: the lifecycle spec asserts no stored attribute contains the URL and that no
`checkout_url` / `url` / `products` / `payload` column exists; the job spec posts a delivery carrying
`checkout/secret-token` and asserts the row contains no trace of it.

**Consequence, stated honestly:** a template variable for the checkout link cannot be served from the cart row. If
a future recipe needs one it must fetch it through the existing provider read at send time. No fake
`checkout_url` variable is exposed.

## 3. What is deliberately not persisted

| Not stored | Why |
|---|---|
| `url` / `checkout_url` | §2 |
| `products[]` — names, SKUs, prices, images | `products_count` is all the lifecycle and a message need; the rest would duplicate the product catalogue |
| addresses, `city_id`, `country_id` | no proposed transition, message or metric uses them |
| payment data | never |
| the full provider payload | a payload column is a permanent, un-minimised copy of customer data |
| `session_id`, `cart_id` | identity is resolved by choosing one field in the normalizer, not by storing all three |
| `whatsapp_message` | Zid's own message text. Worth *reading* at UAT to understand the reminder confound; not worth keeping |

`external_customer_id` **is** stored, encrypted deterministically — the same treatment
`Commerce::CustomerLink` already gives it, and for the same reason: guest references are derived from an email or
an E.164 phone and have to be queryable.

## 4. Security properties of the cart path

| Property | How |
|---|---|
| No new endpoint | the existing `POST /webhooks/zid/:store_id`, authenticated before the body is parsed |
| No credential in the row | the cart row holds no token, no secret and no URL |
| No credential in the Automation payload | the cart context is seven scalar fields (`07` §1) |
| Tenant isolation | `account_id` and `commerce_store_id` on every row; the unique index is scoped to the store, so two accounts holding the same provider cart id get two rows. Two regressions cover account-level and store-level separation |
| Body encryption in transit to Sidekiq | the existing `Commerce::WebhookQueue`, because Sidekiq keeps job arguments in Redis in plaintext |
| Observability without leakage | `[COMMERCE CART] event=unusable_zid_cart_delivery store_id=… zid_event=… keys=…` logs the payload's **key names**, never its values |

## 5. User-facing wording

Permitted, because the data supports them:

- Abandoned carts detected
- Abandoned carts targeted
- Carts completed
- Completion rate
- Post-target completion rate
- Order value associated with completed carts — *only* where `provider_order_id` exists and the value comes from a
  live order read

Not used anywhere in code, copy or metric names:

- ~~Recovered revenue~~
- ~~Revenue recovered by automation~~
- ~~Lynomia recovery rate~~
- ~~Recovered by Lynomia~~

The model enforces the distinction in its own vocabulary: there is no `recovered` state and no `recovered?`
method, only `post_target_completion?`, `untargeted_completion?` and `order_attributed?`. A regression asserts the
absences, so the word cannot quietly return through a later convenience method.

## 6. Analytics readiness (P8 will build the UI, not this phase)

| Metric | Provable from | Honest? |
|---|---|---|
| detected | rows ever in `abandoned` | yes |
| targeted | `targeted_at IS NOT NULL` | yes |
| completed | `state = completed` | yes |
| post-target completed | `targeted_at < completed_at` | yes, as a **time ordering** |
| completion rate | completed ÷ detected | yes |
| post-target completion rate | post-target completed ÷ targeted | yes, with the Zid-reminder confound named |
| order value associated with completed carts | `provider_order_id` + a live order read | yes, and never called recovered revenue |
| recovered revenue | — | **no, and not offered** |

## 7. Contact Timeline readiness (also P8)

A future timeline can show *Cart abandoned → Template X sent → Cart completed* from durable sources that already
exist, without inventing history and without a new event warehouse:

| Timeline entry | Durable source |
|---|---|
| Cart abandoned | `commerce_carts.abandoned_at` + `state` |
| Outreach sent | the existing `Commerce::ActionRun` of type `recovery_message`, plus the `Message` it was matched to — and `commerce_carts.targeted_at` for the moment |
| Automation ran | the existing `Automation::ExecutionLog` |
| Cart completed | `commerce_carts.completed_at`, and `provider_order_id` when attributed |

One caveat worth recording now rather than discovering later: `Commerce::ActionRun` rows are swept after 90 days,
so a timeline older than that can show the cart's lifecycle but not which message was sent. The cart row itself is
not swept by that job.
