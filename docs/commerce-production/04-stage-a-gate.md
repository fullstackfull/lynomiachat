# 04 — Stage A gate

---

## 1. Provider verdicts

| Provider | Verdict | Why |
|---|---|---|
| **WooCommerce** | **SOFTWARE COMPLETE / REAL UAT BLOCKED** | The broadest capability set, the only real captured payload behind its tests, and the only provider not gated off in production. Blocked solely on credentials |
| **Zid** | **SOFTWARE COMPLETE / REAL UAT BLOCKED** — orders. **PRE_UAT** — carts | Order reads and the two status writes are complete. Order *webhooks* could never have delivered before `02`'s fix, so push has effectively never run. Carts are gated |
| **Shopify** | **PRE_UAT** | Cancel and refund are gated, and protected customer data approval is a Shopify-side review. Reads are software-complete |
| **Salla** | **SOFTWARE COMPLETE / REAL UAT BLOCKED**, read-only by construction | No write is possible — the token scope forbids it. No webhook is registered. One order page only |

**No provider is PRODUCTION PROVEN, and none is NO-GO.** Nothing has run against a real store in this environment.

## 2. Findings carried out of Stage A

| # | Finding | State |
|---|---|---|
| 1 | Zid webhook credentials sent in an undefined `authentication` field → every order event lost while registration reported success | **fixed** (`02` §1) |
| 2 | Zid registration dropped failed subscriptions with `filter_map` and reported success | **fixed** (`02` §1.8) |
| 3 | `CustomerMatcher` auto-links on a single verified-phone match **without checking whether the candidate list was served stale** (up to 24 h). A customer deleted or re-keyed at the provider inside that window could auto-link a contact to a stale identity | **open — reported, not fixed.** It needs a product decision: refuse to auto-link on stale data, or auto-link and re-verify. Blast radius is bounded by requiring an *exact* channel-identity phone match, so it cannot link an arbitrary stranger; it can bind to an identity the store no longer has |
| 4 | `Commerce::AbandonedCart` advertises four statuses in its own comment; only two are ever produced | **open — cosmetic**, but it is exactly the drift that makes a reader trust a lifecycle that does not exist |
| 5 | Stale reads may reach a **write** decision path: `Cache.fetch` serves stale on provider failure and `ActionExecutor`'s pre-flight order read can be one of them | **open — needs verification under Stage B**, because this is the "writes must use current provider truth" rule and a stale pre-flight could offer an action the order no longer permits |

Findings 3 and 5 are deliberately left open rather than fixed in passing: both change product semantics, and
neither is on the path this phase was asked to clear.

## 3. The ten cart-gate questions, per provider

Provenance key: **CONTRACT** = the provider's current published documentation, cited and read 2026-10-06 ·
**CODE** = this repository at HEAD · **SIM** = hand-authored fixture only · **UNKNOWN** = not established.

### WooCommerce

| # | Question | Answer | Provenance |
|---|---|---|---|
| 1 | Stable cart identity? | **No** | CODE — `providers/base.rb` defaults `supports_carts?` false; WooCommerce never overrides it |
| 2 | Cart created/updated data? | **No** | CODE |
| 3 | Customer correlation? | n/a — no cart exists to correlate | CODE |
| 4 | Later order correlation? | n/a | CODE |
| 5 | Stable provider cart id? | **No** | CODE |
| 6 | Reliable timestamps? | n/a | CODE |
| 7 | Recovery detectable? | **No** | CODE |
| 8 | Webhook delivery available? | Yes for orders; **no cart topic** | CODE (real-capture verified for orders) |
| 9 | Lynomia persists state today? | **No** | CODE |
| 10 | Honest lifecycle implementable? | **No** | — |

WooCommerce core has no abandoned-cart concept; cart recovery is a plugin concern. Classified **UNSUPPORTED BY
PROVIDER as Lynomia reads it**, and that is a statement about the connector's surface, not a claim that no
WooCommerce plugin anywhere exposes carts.

### Salla

| # | Question | Answer | Provenance |
|---|---|---|---|
| 1 | Stable cart identity? | **UNKNOWN** | CODE — an id is read, but `providers/salla/carts.rb:4-5` says in the repository itself: "The list path and scope come from Salla's API map … **VERIFY on a live store**" |
| 2 | Cart created/updated data? | **No** — a polled list, no event | CODE |
| 3 | Customer correlation? | Partially — a customer reference is read | SIM |
| 4 | Later order correlation? | **No** | CODE |
| 5 | Stable provider cart id? | UNKNOWN | CODE |
| 6 | Reliable timestamps? | UNKNOWN | SIM |
| 7 | Recovery detectable? | **No — impossible by construction.** `salla/carts.rb:21` hardcodes `status: 'abandoned'`; the design note says "a cart Salla no longer lists has been bought or removed". A recovered cart silently vanishes and is indistinguishable from a deleted one | CODE |
| 8 | Webhook delivery available? | **No — Lynomia registers no Salla webhooks at all** | CODE |
| 9 | Lynomia persists state today? | **No** | CODE |
| 10 | Honest lifecycle implementable? | **No** | — |

### Zid

| # | Question | Answer | Provenance |
|---|---|---|---|
| 1 | Stable cart identity? | **Yes, with one ambiguity to resolve.** The schema carries `id`, **and also** `cart_id` and `session_id`. Which is stable across a cart's life is **not stated** | CONTRACT + **UNKNOWN** |
| 2 | Cart created/updated data? | **Created: yes** — `abandoned_cart.created`. **Updated: no such event exists.** Updates are observable only by re-reading | CONTRACT |
| 3 | Customer correlation? | **Yes** — `customer_id`, `customer_name`, `customer_email`, `customer_mobile` | CONTRACT |
| 4 | Later order correlation? | **Yes — the provider does it.** `order_id` is a field on the cart. Lynomia currently reads it and **throws it away** | CONTRACT + CODE |
| 5 | Stable provider cart id? | Yes, subject to #1 | CONTRACT |
| 6 | Reliable timestamps? | **Yes** — `created_at`, `updated_at` | CONTRACT |
| 7 | Recovery detectable? | **Completion is detectable** — `abandoned_cart.completed`, plus `phase: completed` and a non-null `order_id`. Whether that equals *recovery* is a separate question, answered in `05` §4 | CONTRACT |
| 8 | Webhook delivery reliable? | **Yes, with documented limits**: 3 attempts (1/5/15 min), circuit breaker degraded ≥10/h and **broken ≥30/h with dispatch stopped**, 429 not counted. **No delivery id is documented**, so idempotency must come from payload content | CONTRACT |
| 9 | Lynomia persists state today? | **No.** Redis only, plus a 90-day `recovery_message` ActionRun | CODE |
| 10 | Honest lifecycle implementable? | **Yes — and this is the only yes.** Provider-native abandonment and provider-native completion, a stable id, real timestamps and provider-side cart→order correlation | CONTRACT |

### Shopify

| # | Question | Answer | Provenance |
|---|---|---|---|
| 1 | Stable cart identity? | Yes — the `abandonedCheckouts` node id | SIM |
| 2 | Cart created/updated data? | **No event subscribed**; polled via GraphQL | CODE |
| 3 | Customer correlation? | Yes | SIM |
| 4 | Later order correlation? | **No.** `completedAt` is read; no order id is captured | CODE |
| 5 | Stable provider cart id? | Yes | SIM |
| 6 | Reliable timestamps? | `completedAt` yes; others SIM | SIM |
| 7 | Recovery detectable? | **Only by fetching one cart by id.** The list query is `status:open`, so a completed checkout can never appear in it | CODE |
| 8 | Webhook delivery available? | Yes for orders (HMAC); **no cart topic subscribed** | SIM |
| 9 | Lynomia persists state today? | **No** | CODE |
| 10 | Honest lifecycle implementable? | **Not yet** — and it would be a polling design, not an event one. Also `PRE_UAT` and behind protected-data approval | CODE |

## 4. Accept / reject for a cart lifecycle

| Provider | Decision | Reason |
|---|---|---|
| **WooCommerce** | **REJECT** | No cart data of any kind reaches the connector. There is nothing to build a lifecycle from — not a gap in Lynomia, an absence at the source |
| **Salla** | **REJECT** | Recovery is undetectable by construction: a bought cart and a deleted cart both simply disappear. A recovery rate for Salla could only ever be a fabrication, and the endpoint itself is self-declared unverified |
| **Zid** | **ACCEPT, as the only candidate** | The provider defines abandonment, announces it, announces completion, and correlates the cart to the order itself. Lynomia uses none of this today |
| **Shopify** | **REJECT for now** | A lifecycle is conceivable but would be inferred from polling a list that structurally cannot show recoveries, and the capability is gated behind a Shopify-side approval. Revisit only with a cart/checkout webhook topic |

Supporting **Zid only** is the honest outcome, and B1 explicitly permits it.

## 5. Gate decision

**Stage B is NOT blocked by provider data — for Zid.** The brief's stop condition ("if NONE") is not met.

It **is** blocked on three things that are not provider data, and all three are why this document stops here:

1. the one durable-state migration is **designed, not written**, and awaits approval (`05`);
2. the Zid **webhook payload shape for cart events is UNKNOWN** — the published schema is the REST object, and
   nothing retrievable states that the webhook delivers the same fields. That is a real-UAT question;
3. every Zid cart path is `PRE_UAT`, so even a correct implementation stays dark until a real store clears it.

So the gate opens onto a design review, not onto code.
