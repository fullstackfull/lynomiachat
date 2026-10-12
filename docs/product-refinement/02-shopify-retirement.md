# Shopify canonicalization: retiring the legacy duplicate

> Product decision (given, not re-litigated): **Lynomia has ONE Shopify integration, and it is
> Lynomia Commerce → Shopify.** Legacy Shopify is retired.
>
> Every claim below was verified by opening the cited file at the cited line.

## 1. Why the customer sees "two Shopify entries"

Not one duplicate — **three**, on three different surfaces.

### 1.1 Super Admin settings pages

`SuperAdmin::NavigationHelper#settings_pages` renders one page per entry in
`app/helpers/super_admin/features.yml` that has a `config_key` and is `enabled`
(`app/helpers/super_admin/navigation_helper.rb:6-15`). That file contains both:

```yaml
shopify:                                    # app/helpers/super_admin/features.yml:108-113
  name: 'Shopify'
  description: 'Configuration for setting up Shopify Integration'
  config_key: 'shopify'

shopify_commerce:                           # app/helpers/super_admin/features.yml:126-131
  name: 'Shopify Commerce'
  description: 'Configuration for the Lynomia Commerce Shopify app (separate from the Shopify integration)'
  config_key: 'shopify_commerce'
```

The second entry's own description admits the duplication. Each `config_key` maps to a set of
`InstallationConfig` keys in `SuperAdmin::AppConfigsController#allowed_configs`
(`app/controllers/super_admin/app_configs_controller.rb:71-94`):

| Page | `config_key` | Keys | Citation |
|---|---|---|---|
| **Shopify** (legacy) | `shopify` | 8 keys via `SHOPIFY_CONFIGS` | `app_configs_controller.rb:11-20,77` |
| **Shopify Commerce** (canonical) | `shopify_commerce` | `SHOPIFY_COMMERCE_ENABLED`, `_CLIENT_ID`, `_CLIENT_SECRET` | `app_configs_controller.rb:80` |

### 1.2 Tenant Settings → Integrations

`config/integration/apps.yml:257-263` registers a `shopify` integration app. It appears to a tenant when
`Shopify::FeatureGate.enabled?` and `SHOPIFY_CLIENT_ID` is present
(`app/models/integrations/app.rb:51,133-134`). Canonical Shopify lives instead under **Settings → Commerce**.

### 1.3 Conversation sidebar — two order panels at once

`ContactPanel.vue` mounts **both**:

| Accordion | Gate | Component | Citation |
|---|---|---|---|
| `shopify_orders` | `isShopifyFeatureEnabled` | `ShopifyOrdersList` (legacy) | `ContactPanel.vue:276-287` |
| `commerce` | `isCommerceEnabled` | `CommercePanel` (canonical) | `ContactPanel.vue:306-315` |

An account with both enabled sees two order panels side by side. The accordion is registered as a sidebar
element name at `app/javascript/dashboard/composables/useUISettings.js:17`.

## 2. The complete legacy surface

### 2.1 Ruby

| Path | What it is | Verdict |
|---|---|---|
| `app/controllers/api/v1/accounts/integrations/shopify_controller.rb` | Legacy tenant connect endpoint | **delete** |
| `app/controllers/shopify/callbacks_controller.rb` | Legacy OAuth callback | **delete** |
| `app/controllers/webhooks/shopify_controller.rb` | Legacy webhook endpoint | **delete** |
| `app/helpers/shopify/integration_helper.rb` | Legacy OAuth state JWT, reads `SHOPIFY_CLIENT_SECRET` | **delete** |
| `app/services/shopify/api_context.rb` | Legacy Shopify API session | **delete** |
| `app/services/shopify/feature_gate.rb` | `ENABLE_SHOPIFY_INTEGRATION` + feature flag gate | **delete**, 3 external callers to edit |
| `app/services/shopify/installation_generation.rb` | Legacy install generation counter | **delete** |
| `app/services/shopify/partner_client.rb` | Shopify **Partner API** client | **delete** — dead (§3) |
| `app/services/shopify/partner_configuration.rb` | Partner credential validation | **delete** — only caller is the config form it validates |
| `app/services/shopify/pending_installation.rb` | Pending-install cache | **delete** |
| `app/services/shopify/shop_identity.rb` | Legacy shop identity | **delete** |
| `app/services/shopify/subscription_fetcher.rb` | Shopify App Store subscription read | **delete** — dead (§3) |
| `app/services/shopify/subscription_snapshot.rb` | Subscription snapshot value object | **delete** — dead (§3) |
| `app/services/shopify/uninstallation_service.rb` | Legacy app-uninstalled handling | **delete** |
| **`app/services/shopify/shop_domain.rb`** | Shop-domain normalize/validate/`FORMAT` | **KEEP — see §4** |

### 2.2 Routes

| Route | Citation |
|---|---|
| `resource :shopify, controller: 'shopify', only: [:destroy]` | `config/routes.rb:308` |
| `post 'webhooks/shopify', to: 'webhooks/shopify#events'` | `config/routes.rb:565` |
| `namespace :shopify do … end` (OAuth callback) | `config/routes.rb:571` |

Canonical routes, which stay: `config/routes/commerce.rb:14,58,59`
(`shopify_connection#create`, `commerce/shopify/callback`, `webhooks/shopify_commerce`). Note
`config/routes/commerce.rb:57-58` carries a comment distinguishing itself from the legacy paths — that comment
becomes obsolete and gets updated.

### 2.3 Configuration

| Key | Where | Verdict |
|---|---|---|
| `ENABLE_SHOPIFY_INTEGRATION` | `config/installation_config.yml:470-475` | delete |
| `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET` | `:476-485` | delete |
| `SHOPIFY_APP_STORE_URL` | `:486-489` | delete (read at `integrations/app.rb:53`) |
| `SHOPIFY_PARTNER_ORGANIZATION_ID`, `_APP_ID`, `_ACCESS_TOKEN`, `_API_VERSION` | `:490-506` | delete |
| `CHATWOOT_SHOPIFY_PLANS` | `:292-297`, `locked: true` | delete — **zero readers** (§3) |
| `shopify_integration` feature flag | `config/features.yml:170-173` | **deprecate in place, do not remove** (§5) |
| `SHOPIFY_COMMERCE_*` (5 keys) | `:558-572, 600, 624` | **keep** — canonical |

### 2.4 Frontend

| Path | Verdict |
|---|---|
| `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue` | delete |
| `app/javascript/dashboard/api/integrations/shopify.js` | delete |
| `app/javascript/dashboard/components/widgets/conversation/ShopifyOrdersList.vue` | delete |
| `app/javascript/dashboard/components/widgets/conversation/ShopifyOrderItem.vue` | delete |
| `ContactPanel.vue` legacy accordion + getter | edit (`:23,48-54,276-287`) |
| `useUISettings.js:17` `{ name: 'shopify_orders' }` | edit |
| `conversation.json` `ACCORDION.SHOPIFY_ORDERS`, `SHOPIFY.*` (`:486,501-504`) | delete, both locales |
| **`settings/commerce/ShopifyConnectDialog.vue`** | **KEEP — canonical**, despite the filename matching a naive `*shopify*` search |

The last row is the trap: a path-based sweep for `shopify` picks up canonical Commerce files. Classification is
by **which architecture owns it**, not by filename.

## 3. Dead code inside the legacy surface

Proven by exhaustive grep over `app custom lib config spec` for `SubscriptionFetcher`, `subscription_snapshot`
and `PartnerClient`, excluding the cluster's own directory and specs. **One hit**, and it is a `rescue` of the
error class in the form that configures the credentials:

```
app/controllers/super_admin/app_configs_controller.rb:106:  rescue Shopify::PartnerClient::ConfigurationError => e
```

So the Shopify **Partner API** sub-cluster — `PartnerClient`, `PartnerConfiguration`, `SubscriptionFetcher`,
`SubscriptionSnapshot` — exists only to validate credentials that no runtime code ever uses.
`CHATWOOT_SHOPIFY_PLANS` likewise has **zero** readers. This was already dead before this phase.

### Billing is NOT coupled to legacy Shopify

The names suggested legacy Shopify might be a *billing channel* (Shopify App Store subscriptions), which would
have made retirement a billing-breaking change. It is not:

```
grep -rn -i shopify custom/app/services/billing/ custom/app/models/billing_plan.rb \
                    custom/app/models/billing_subscription.rb   →  no matches
```

**Retiring legacy Shopify cannot affect how any account is billed.** This was the single largest retirement
risk and it is cleared.

## 4. `Shopify::ShopDomain` must survive

`app/services/shopify/shop_domain.rb` lives in the legacy directory but is a **shared primitive the canonical
path depends on**:

| Canonical caller | Citation |
|---|---|
| `Commerce::ShopifyConnectionsController` normalize + validate | `custom/app/controllers/api/v1/accounts/commerce/shopify_connections_controller.rb:26-27` |
| `Webhooks::ShopifyCommerceController` validate + normalize | `custom/app/controllers/webhooks/shopify_commerce_controller.rb:17,19` |
| `Commerce::Shopify::Oauth` (documented contract) | `custom/app/services/commerce/shopify/oauth.rb:3` |

It is also used by `Integrations::Hook` validation (`app/models/integrations/hook.rb:31,122`), which is part of
the legacy data path but a *model* concern, handled in §5.

**Decision: keep the class, move it.** It is relocated to `custom/app/services/commerce/shopify/shop_domain.rb`
as `Commerce::Shopify::ShopDomain`, with the three canonical call sites updated, so that no canonical code
reaches into a legacy namespace. The legacy directory then deletes cleanly. Deleting it outright would break
the canonical connect flow — a deletion that a path-based sweep would have made.

## 5. Production data — confirmed empty, so the plan is simpler than it was

> **Production fact, confirmed by the product owner: there are NO Shopify stores connected in production.**
>
> Classification: **`SAFE_TO_RETIRE`**, subject to the audit below confirming it on the real server.
>
> This removes work rather than adding it. There is deliberately **no migration UI, no re-authorization
> workflow and no merchant transition process** anywhere in this retirement — building one for zero merchants
> would be inventing a product nobody needs. The read-only audit stays, as the verification that the premise
> holds.
>
> What the audit prints:
>
> | Result | Output | Meaning |
> |---|---|---|
> | 0 rows (expected) | `legacy Shopify installations = 0` then `SAFE_TO_RETIRE` | Retirement is complete; nothing further to do |
> | any rows (unexpected) | `legacy Shopify installations = N` then `LEGACY_RECORDS_FOUND` | The premise did not hold. Nothing is deleted on the strength of the report; a human confirms first |
>
> The per-row recommendations in this section exist **only** for that second case. Everything below describes
> the mechanism that makes a surprise safe, not a process anybody is expected to run.

### The original framing, kept because the safety property still holds

### What may exist in production

`Integrations::Hook` rows with `app_id = 'shopify'`. The canonical connect path reads them *today*:

```ruby
def legacy_integration?(shop)
  Current.account.hooks.exists?(app_id: 'shopify', reference_id: shop)
end
```
`custom/app/controllers/api/v1/accounts/commerce/shopify_connections_controller.rb:63-65`, raised at `:28` as
`STORE_ALREADY_CONNECTED / legacy_shopify_integration`, surfaced to the customer as
`COMMERCE.ERRORS.LEGACY_SHOPIFY_CONNECTED` (`en/commerce.json:145`, `ar/commerce.json:145`).

A legacy hook holds the Shopify Admin API token in `Integrations::Hook#access_token`, an **encrypted** column
(`app/models/integrations/hook.rb:26`). The shop domain is in `reference_id` (`:31,122`).

### This phase destroys no merchant data

| Step | This phase |
|---|---|
| Retire the source surface | **yes** |
| Report what exists in production | **yes** — read-only rake task |
| Delete `Integrations::Hook` rows | **no** |
| Drop columns or tables | **no** |

`Integrations::Hook` is a shared upstream table serving ~20 other integrations; nothing about it is
Shopify-specific except the seven validation/predicate sites (`app/models/integrations/hook.rb:22,31,33,34,84,110,121`). **Those are kept**, so an existing row stays
valid, loadable and deletable by an operator. Only the *product surface* goes.

### The read-only audit

`rails lynomia:shopify:legacy_audit` (`lib/tasks/shopify_legacy_audit.rake`). For each legacy hook it reports:
account id, account name, shop domain, whether a `Commerce::Store` already exists for that shop, and the
resulting recommendation (`migrate`, `already_migrated`, `reauthorize`). It reads exactly four columns and
**never** touches `access_token`:

```ruby
Integrations::Hook.where(app_id: 'shopify').pluck(:id, :account_id, :reference_id, :status)
```

A test asserts the task's output contains no token and that `access_token` is never selected.

### The coexistence guard

`legacy_integration?` is **removed** together with the legacy connect path, in the same change — otherwise a
merchant with a stale legacy row could never move to Commerce. Double-connection stays impossible by schema:
`index_commerce_stores_on_provider_and_external_store_id` is UNIQUE (`db/schema.rb:952`). The two i18n strings
for the now-unreachable error are removed in both locales.

### `shopify_integration` feature flag stays declared

`config/features.yml:170-173`. Flag bit positions are persisted per column and
`config/features.yml:12-16` states: *"never reorder or remove existing entries."* Removing the entry would
shift every later bit and silently change which features existing accounts have. It is marked `deprecated: true`
instead, which removes it from the UI and from `BillingPlan.assignable_features`
(`custom/app/models/billing_plan.rb:41-48`) while leaving the bitmask untouched.

## 6. Capability parity: does Commerce cover everything legacy did?

| Capability | Legacy | Commerce | Citation |
|---|---|---|---|
| OAuth connect | yes | yes | `custom/app/services/commerce/shopify/oauth.rb` |
| Token storage | `Hook#access_token` | `commerce_stores.credentials` | `db/schema.rb:944` |
| Orders in conversation | `ShopifyOrdersList` | `CommercePanel` | `ContactPanel.vue:276,306` |
| Customer matching | shop-scoped | `Commerce::CustomerMatcher` + unified identity | `commerce_customer_links` |
| Webhooks | `webhooks/shopify` | `webhooks/shopify_commerce` | `config/routes/commerce.rb:59` |
| Uninstall handling | `UninstallationService` | webhook + `needs_reauth`/`disconnected` | `Commerce::Store` status enum |
| Order **actions** (cancel/refund) | **no** | **yes** | `Commerce::OrderActions` |
| Abandoned carts | **no** | **yes** | `commerce_carts` |
| GraphQL provider | REST | GraphQL | `docs/commerce/19` |
| Shopify App Store subscriptions | dead code (§3) | n/a | — |

**Commerce is a strict superset of what legacy actually did.** No capability is lost. The only legacy-only
items are the dead Partner API cluster and the `SHOPIFY_APP_STORE_URL` marketing link.

## 7. Documentation

**Correction to my own first draft.** I initially recorded that the Shopify article documents only the Commerce
path. That is wrong, and it matters: `custom/db/documentation/en/commerce/connect-shopify.md` teaches the
legacy path in **four** places, and `ar/` mirrors all four.

| Line | Current text (EN) | Why it must change |
|---|---|---|
| `:11-12` | "This is a different app from the Shopify integration listed under Integrations. The two never share credentials, and a store already connected through that integration is refused here…" | Describes a second Shopify product and a refusal that will no longer exist |
| `:25` | Prerequisite: "The store not already connected through this account's Shopify integration." | A prerequisite about a surface being deleted |
| `:87-88` | *"This Shopify store is already connected through this account's Shopify integration."* → "Disconnect it under Integrations first, then connect it here." | Instructs the customer to visit a page that will 404 |

This is precisely the brief's requirement that "customers never see instructions for two competing Shopify
paths" — and the corpus currently fails it. All three passages are rewritten in both locales as part of
workstream A rather than deferred to B, because they document the surface this workstream deletes and would
otherwise ship stale for however long B takes.

`docs/commerce/21-shopify-legacy-coexistence.md` gains a header recording that its coexistence decision was
reversed by this phase, rather than being deleted — it is the record of why the code looked as it did.

## 8. Order of operations

1. Relocate `Shopify::ShopDomain` → `Commerce::Shopify::ShopDomain`; update the three canonical call sites and
   the two `Integrations::Hook` sites. Suite green. *(No behaviour change.)*
2. Add the read-only audit rake task + spec.
3. Remove the Super Admin page: `features.yml` entry, `SHOPIFY_CONFIGS`, the `'shopify'` mapping, and
   `shopify_partner_config_errors`.
4. Remove the tenant surface: `apps.yml` entry, the three `Shopify::FeatureGate` call sites, routes,
   controllers, services, frontend, i18n, and the conversation accordion.
5. Remove the coexistence guard and its two i18n strings.
6. Mark the feature flag `deprecated: true`.
7. Delete legacy-only specs; keep and extend canonical ones.
8. Installation config keys removed last, so an operator reading the diff sees the surface go before the keys.

Each step leaves the suite green on its own.

---

## §correction — a live breakage this retirement introduced, found and fixed

An adversarial verification pass over the branch found a defect this retirement **caused and shipped**. It is
recorded here rather than quietly fixed, because the way it escaped matters more than the fix.

### What broke

The retirement deleted `app/services/shopify/feature_gate.rb`. It did not delete the only reference to it:

```erb
features.delete(Shopify::FeatureGate::ACCOUNT_FEATURE) unless Shopify::FeatureGate.enabled?(account: @account)
```

in `app/views/api/v1/models/_account.json.jbuilder` — the account payload the dashboard reads **on every
load**. So `GET /api/v1/accounts/:id` raised `NameError` and answered **500**, reproduced directly:

```
status=500   (before)
status=200   (after)
```

That is the whole dashboard, for every user, on every account.

### Why the sweep missed it

The retirement's own verification ran 149 examples across the canonical Shopify Commerce path, the legacy
audit task, the integration app registry and the Vite build — and it found and fixed a dangling *relative*
Vite import by running the build. It did not run anything that **renders this view**, and nothing in the
repository asserted that the account payload renders at all. A grep for `Shopify::` would have found it; a
grep for the paths being deleted did not, which is the same mistake the `ShopDomain` finding in §4 warned
about and that this sweep then made in the other direction.

### The fix, which is a rule rather than a patch

The gate existed to hide the `shopify_integration` account feature unless the legacy integration was
configured. The flag is now `deprecated: true` in `config/features.yml` — declared so persisted bit positions
do not shift, never offered. So the payload now removes **every** deprecated feature, not this one:

```erb
json.features @account.enabled_features.except(*BillingPlan.deprecated_features)
```

`BillingPlan.deprecated_features` reads the same file as `assignable_features`, so one place knows what
deprecated means, and the next feature retired is covered without anybody editing a view.

### Two more defects the same pass exposed

- **`GET /integrations/apps/:id` answered 500 for an id that names no app.** `fetch_app` left `@app` nil and
  the view rendered it. Nothing noticed while every id anybody asked for existed; retiring the legacy Shopify
  app made `shopify` one of those ids. It now raises `RecordNotFound`, which is what a missing app is.
  Narrowed deliberately to **existence**: an app that exists but is not configured yet still answers, because
  fetching its details is how its settings page renders, which is how an administrator configures it.
- **Two stale specs asserted that a legacy Shopify hook could not be updated or deleted.** That is the
  opposite of this retirement's rule (§5): `create` is refused and nothing else, because an account holding a
  legacy row must be able to clear it. They now assert the documented behaviour, and the unreachable
  `@hook&.app_id` branch in `shopify_hook?` is gone.

### What now prevents a repeat

`spec/requests/accounts/deprecated_features_spec.rb` — 4 examples. The first one is simply **that the account
payload renders**, which is the assertion whose absence let a deleted constant reach a pushed commit. The rest
prove a deprecated feature is removed even when the account has it enabled, a live feature is still
advertised, and the deprecated list comes from the feature declarations rather than a second list.
