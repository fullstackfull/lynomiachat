# Lynomia Commerce: final status after Phase 9–10

Where Lynomia Commerce stands after its last phase (order actions, abandoned carts and sales recovery). **Nothing was
deployed to production.** Earlier verdicts: doc 23 (Phase 6, production gate) and doc 27 (Phase 7–8). This phase ends
Lynomia Commerce: CRM, SLA, Audiences, Automation and AI were not started. How a merchant adds a store (platform picker,
WooCommerce access choice) and the plan's store limit set in Super Admin: doc 35.

## 1. Readiness per provider

| Provider | READ | REALTIME | ACTIONS | RECOVERY |
|---|---|---|---|---|
| **WooCommerce** | **GO** (pilot, doc 23): real UAT, regressions unchanged | **GO** with a Read/Write key (real deliveries, doc 27); a Read key keeps working without live updates | **GO per store**: off until the store's administrator opts in with a Read/Write key; refunds and cancellations for administrators only; real E2E on a disposable store (doc 33) | **UNSUPPORTED**: WooCommerce core has no merchant-wide abandoned-cart API; no plugin required |
| **Salla** | **NO-GO** (real UAT blocked: no Partner app, hosts unreachable) | NO-GO (payload shape VERIFY) | **UNSUPPORTED**: no verified write contract | **NO-GO**, held until real UAT; list path and `carts.read` scope VERIFY; simulated E2E passes |
| **Zid** | **NO-GO** (real UAT blocked) | NO-GO | **NO-GO**, held until real UAT: two status steps only; simulated E2E passes | **NO-GO**, held until real UAT; simulated E2E passes |
| **Shopify** | **NO-GO** (real UAT blocked; Protected Customer Data not approved) | NO-GO | **NO-GO**, held until real UAT and Protected Customer Data approval; `write_orders` only through an explicit reconnect; `@idempotent` VERIFY; simulated E2E passes | **NO-GO**, held until real UAT and approval; simulated E2E passes |

"Held" is enforced in code (`Commerce::Switches::PRE_UAT`): Super Admin switches cannot turn these providers' actions or
carts on in production. Only the ENV `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` lifts the hold, for staging and simulations.

## 2. Production defaults

| Switch | Default | Result in production |
|---|---|---|
| `COMMERCE_ACTIONS_ENABLED` | on | kill switch available |
| `WOOCOMMERCE_ACTIONS_ENABLED` | on | WooCommerce actions possible, **each store off until its administrator opts in** with a Read/Write key |
| `SALLA_ACTIONS_ENABLED`, `ZID_ACTIONS_ENABLED`, `SHOPIFY_COMMERCE_ACTIONS_ENABLED` | off | off (and held regardless) |
| `COMMERCE_RECOVERY_ENABLED` | on | kill switch available; no store offers carts in production |
| `SALLA_RECOVERY_ENABLED`, `ZID_RECOVERY_ENABLED`, `SHOPIFY_COMMERCE_RECOVERY_ENABLED` | off | off (and held regardless) |
| `COMMERCE_RECOVERY_COOLDOWN_HOURS` | 24 | |
| `SALLA_ENABLED`, `ZID_ENABLED`, `SHOPIFY_COMMERCE_ENABLED` (read) | off (doc 23) | unchanged |
| `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` (ENV) | unset | must stay unset in production |

## 3. What Phase 9–10 added

- **Order actions** (doc 28): change status, cancel, partial/full refund, resend invoice/payment link; capability per
  provider and per order state; two-step confirmation dialog; `commerce_action_runs` with idempotency keys; re-read and
  version check before every write; amount checks against the store's refundable amount; unknown outcomes reconciled by
  reading only; sweep job; rate limits; audit and metrics; per-store opt-in; kill and provider switches.
- **Provider adapters** (doc 29): WooCommerce (REST, real), Zid (status steps), Shopify (GraphQL 2026-07, scope
  upgrade by reconnect, `orderCancel`, `refundCreate`).
- **Abandoned carts** (doc 30): provider-neutral cart, Salla/Zid/Shopify adapters, trusted-identity matching only,
  Customer 360 section, cache without contact details, drop on order and cart events (Salla cart events through the
  Phase 7 realtime core).
- **Sales recovery** (doc 31): prepared message in the reply box, never sent by Lynomia; reply-window check; safe links;
  prepared vs sent (from the outgoing message); cooldown with administrator override; administrators' queue.
- **Security** (doc 32): threat review with tests for every control.

## 4. Evidence

| | Result |
|---|---|
| Phase 9–10 E2E, production configuration (real WooCommerce, disposable orders) | **51/51** (doc 33 §2) |
| Phase 9–10 E2E, pre-UAT override (simulated Salla/Zid/Shopify) | **43/43** |
| Earlier E2Es on the same build | WooCommerce 41/41, Salla 47/47, Zid 49/49, Shopify 64/64, Phase 7–8 realtime 41/41: unchanged |
| WhatsApp harnesses | existing numbers 41/41, WhatsApp Business coexistence 54/54, Lynomia 17/17: unchanged |
| Full suites | Enterprise RSpec 10,293 (1 known OpenSearch failure), Community RSpec 7,589 (0), Vitest 4,745, ESLint 0 errors, RuboCop unchanged (doc 33 §3) |
| Migration down/up (throwaway database) | drops and restores only `commerce_action_runs` (doc 33 §3) |

## 5. Rollback

Code rollback only, no downgrade migration (doc 28 §11):

1. `COMMERCE_ACTIONS_ENABLED=false`, `COMMERCE_RECOVERY_ENABLED=false` in Super Admin; sent actions keep being
   reconciled (at most ~13 minutes).
2. Before rolling back to code that does not understand suppressed links (Phase 7–8):
   `Commerce::CustomerLink.where(match_source: 4).delete_all`.
3. Deploy the previous release. Older code ignores `commerce_action_runs`, the `order_actions` store setting and the
   `write_access` metadata key; the table stays with its history.
4. Shopify stores reconnected for order actions keep `write_orders` in their token until an administrator reconnects
   them read-only; with actions off nothing uses it.

The down migration is not part of the rollback (it would drop the action history); its mechanics were rehearsed on a
throwaway database (doc 33 §3).

## 6. Before any provider leaves NO-GO

Each needs, on its real service, at least:

- **Salla**: Partner app with `carts.read`; confirm `/admin/v2/carts/abandoned`, the Cart shape, `abandoned.cart*`
  events on the app webhook; then real UAT of reads and realtime (doc 23 §4.2). No actions are planned for Salla.
- **Zid**: real UAT of reads (doc 23); then confirm `change-order-status` (`indelivery`, `delivered`), the 403 for a
  missing permission, and `abandoned-carts` with `customer_id` on a test store.
- **Shopify**: Protected Customer Data approval; real UAT of reads; then on a development store confirm `write_orders`
  through the reconnect, `refundCreate` with `@idempotent` (and that a repeated key refunds nothing), `orderCancel`'s Job,
  and `abandonedCheckouts`.

Leaving NO-GO is a reviewed code change to `Commerce::Switches::PRE_UAT`, not a setting.

## 7. Not started

CRM, SLA, Audiences, Automation and AI are out of scope and were not started. Lynomia Commerce stops here.
