# Lynomia Commerce: adding a store, and stores on plans

How a merchant picks their store's platform and connection, and how a plan sets how many stores an account may connect.
This completes the "plan limits later" note in [07 §12](07-phase2-implementation.md). Production readiness per provider
is unchanged ([34](34-commerce-final-status.md)): WooCommerce GO; Salla, Zid and Shopify NO-GO.

## 1. Adding a store (Settings → Commerce → Add store)

**Step 1, the platform.** "Add store" always opens the platform picker first, with all four platforms and how each one
connects:

| Platform | How it connects | What the merchant does |
|---|---|---|
| WooCommerce | a WooCommerce REST API key | creates a key in WordPress and pastes it (step 2) |
| Salla | the Lynomia app from the Salla App Store | installs the app and enters a one-time code from Lynomia in the app's settings (doc 10) |
| Zid | the Lynomia app's authorization (OAuth) | clicks "Connect with Zid" and approves on Zid (doc 14) |
| Shopify | the Lynomia Commerce app's authorization (OAuth) | enters the myshopify.com domain and approves on Shopify (doc 18) |

A platform the installation does not offer (its Super Admin switch is off, or it is held before its real UAT) is still
listed, marked **Not available yet**, and cannot be chosen. A note under the list says so. This way a Salla, Zid or
Shopify merchant sees that their platform is coming instead of being dropped straight into WooCommerce's key form, which
is what happened before when WooCommerce was the only platform on.

**Step 2, the connection (WooCommerce).** The WooCommerce dialog first asks what Lynomia should be able to do:

| Choice | What it gives | Key permission |
|---|---|---|
| **Read/Write** (recommended, preselected) | orders in conversations, live order updates (Lynomia adds only its own webhooks), and order actions once an administrator turns them on; refunds and cancellations stay with administrators (doc 28) | Read/Write |
| **Read** | orders in conversations | Read |

Below the choice, three steps say where to create the key in WordPress (WooCommerce → Settings → Advanced → REST API →
Add key) and which permission to set. The choice is guidance only: the request sends the key, and what the key can do is
what WooCommerce says it can do (`write_access`, doc 28 §7). A Read key is never upgraded; the administrator replaces it
from the store's row.

The dialog scrolls when it is taller than the window, so "Test and connect" is reachable on a laptop or a phone.

## 2. The plan's store limit

**Super Admin → Billing plans → edit.** The plan's limits are Agents, Inboxes and **Commerce stores**, side by side
(`BillingPlan#limits`, `LIMIT_KEYS = %w[agents inboxes stores]`). The form explains the store limit: stores an account
keeps connected, on any platform; disconnected stores do not count; empty is unlimited and 0 is none. It applies when the
plan includes the Lynomia Commerce feature (the plan's feature list, synced to the account by `Billing::FeatureSync`).

**What counts.** Every store of the account that is not disconnected: active, disabled and needing re-authorization alike,
whatever the platform. A disconnected store keeps only its history (no credentials, no customer links) and does not count.

**Where it is enforced.** At the one place every connection of every platform passes through,
`Commerce::StoreConnection`:

- `#attach`: a new WooCommerce store, a Salla installation completed by its code, a Zid or Shopify authorization, and a
  disconnected store reconnected (same row reused) or taken over from another account;
- `#rotate_credentials`: new keys for a disconnected WooCommerce store.

Each runs in a transaction that locks the account row first, so two connections at the same moment cannot both take the
last place. At the limit the answer is `STORE_LIMIT_REACHED` (422) and nothing is saved, deleted or moved. Replacing the
keys of a store that already counts, re-authorizing it, or enabling a disabled store is never blocked.

**Salla.** A Salla store connects asynchronously, when both the merchant's code and Salla's authorization have arrived
(doc 10). If the account is at its limit by then, nothing is connected and the settings page shows
`limit_reached`: "Your plan's store limit is reached, so this Salla store wasn't connected. Upgrade your plan or disconnect
a store, then create a new code." The authorization keeps waiting (encrypted, 7 days), so after the upgrade a new code
connects the store without reinstalling the app.

**Zid and Shopify.** Their authorization returns to Settings → Commerce with `zid_error=STORE_LIMIT_REACHED` or
`shopify_error=STORE_LIMIT_REACHED`, shown as "You've connected all the stores your plan allows. Upgrade your plan or
disconnect a store to connect another." A re-authorization of a store that already counts is never blocked.

**Downgrades.** A plan with fewer stores than the account has connected disconnects nothing: the stores keep working and
"Add store" stays off until the account is below its new limit. Disconnecting is the merchant's decision.

## 3. What each side sees

| Who | Where | What |
|---|---|---|
| Merchant administrator | Settings → Commerce | "Stores on your plan: 1 of 2" above the stores (only when the plan sets a store limit) |
| | | at the limit: "Add store" is off, and a note "You've reached your plan's store limit (2). To add another store, upgrade your plan or disconnect one." with **View plans** (the subscription page) |
| | Settings → Subscription | usage "Commerce stores 1 / 2" next to agents and inboxes (when the plan includes Commerce or stores are connected); each plan with Commerce lists its store count |
| Mobile app | `GET …/billing/entitlements` | `limits.stores: { used, limit }` next to agents and inboxes |
| Super admin | Billing plans | the "Commerce stores" limit in the form and in the plan's limits ("Agents: 5 · Inboxes: 3 · Commerce stores: 2") |
| | Billing subscriptions → one subscription | "Usage / plan limit: Agents: 1 / 5 · Inboxes: 0 / 3 · Commerce stores: 1 / 2" |
| Platform API | subscription `with_usage` | `usage.stores: { used, limit }` |

The subscription page now reads the subscribed plan's limits from the subscription itself (`plan_limits`,
`plan_commerce`). Before, it looked the plan up among the plans offered for checkout, which only lists plans with a
Stripe price, so a plan the super admin granted manually showed every limit as "Unlimited".

## 4. API

| Endpoint | Change |
|---|---|
| `GET /api/v1/accounts/:id/commerce/stores` | `store_limit: { used, limit }` (`limit` null: unlimited) |
| `POST /api/v1/accounts/:id/commerce/stores`, `PATCH …/:store` | `422 { error: { code: "STORE_LIMIT_REACHED" } }` at the limit |
| `GET /api/v1/accounts/:id/commerce/salla_connection` | `status: "limit_reached"` |
| Zid and Shopify OAuth callbacks | redirect with `zid_error` / `shopify_error` `STORE_LIMIT_REACHED` |
| `GET /api/v1/accounts/:id/billing` | `usage.stores`; `subscription.plan_limits`, `subscription.plan_commerce`; each plan's `commerce` |
| `GET /api/v1/accounts/:id/billing/entitlements` | `limits.stores: { used, limit }` |

No migration: `limits` is the existing jsonb column. `Commerce::Store.connected` is the scope the limit counts.

## 5. Tests

- RSpec: the limit in `Commerce::StoreConnection` (new store, any provider counted, disconnected not counted, reconnect
  and takeover refused at the limit with nothing changed, key replacement of a counted store allowed, no limit, a limit
  of 0), Salla `limit_reached` then a new code after the upgrade without a new authorization, the stores API
  (`store_limit`, 422), the billing API (usage, entitlements, `plan_limits` for a plan without a Stripe price), and
  `BillingPlan` keeping the `stores` limit.
- Vitest: the picker (all platforms, not available ones disabled), the WooCommerce access choice (steps change, the
  request does not).
- E2E (`e2e/plans/`, production configuration, real WooCommerce test stores with Read keys, results in
  `e2e/results/plans/`, screenshots in `screenshots/plans/`): the merchant's picker and access choice, the limit reached
  in the UI and through the API, the subscription page, the super admin raising the plan's limit and seeing the
  account's usage, a second store, a disconnected store not counted, a granted plan without a Stripe price, Arabic at 390 px:
  **22/22**.
- Regressions through the new picker and dialog (`e2e/results/plans/provider_regressions.txt`): Phase 7–8 realtime
  41/41, Shopify 64/64, Zid 49/49, WooCommerce 41/41, Salla 47/47, Phase 9–10 order actions 51/51 + 43/43, all unchanged.
  The realtime run first caught the WooCommerce dialog's "Test and connect" below the fold on a 900 px screen; the
  dialog now scrolls.

## 6. Rollback

Code only. Older code ignores `stores` in a plan's `limits` and drops it the next time the plan is saved there; the
store-limit check and the usage fields go with the code. Nothing to clean up.
