# Lynomia Commerce: Shopify Commerce next to the legacy Shopify integration (Phase 5)

Chatwoot 4.18 ships a Shopify integration, referred to here as **legacy**. It is **protected**: Phase 5 changes nothing in it, moves no installation and migrates nothing. Shopify Commerce is a separate path inside Commerce Core. This document records how the two coexist, the evidence that the legacy integration is unchanged, and a feasibility assessment of a later migration (§5). No migration was started.

## 1. The legacy integration, as audited

| Part | Legacy |
|---|---|
| App | Embedded app (`Shopify::ApiContext` `is_embedded: true`); `SHOPIFY_CLIENT_ID` / `SHOPIFY_CLIENT_SECRET`; Partner API billing (`Shopify::PartnerClient`, enterprise billing jobs) |
| Scopes | `read_customers read_orders read_fulfillments` (`Shopify::IntegrationHelper::REQUIRED_SCOPES`) |
| Token | Non-expiring offline token in `Integrations::Hook` (`app_id: 'shopify'`, `reference_id`: shop domain); one shop per account |
| Endpoints | `/shopify/callback` (JWT state, raw-join HMAC), `/webhooks/shopify` (HMAC with `SHOPIFY_CLIENT_SECRET`; app/uninstalled, shop/redact, compliance), `api/v1/accounts/:id/integrations/shopify` (auth, orders, destroy) |
| API | REST Admin (`customers/search.json`, `orders.json`) with `api_version '2025-01'` in the orders controller; GraphQL `shop` for identity (`Shopify::ShopIdentity`) |
| UI | Settings → Integrations → Shopify; the conversation sidebar's Shopify orders section |
| Super Admin | Settings → Shopify (`SHOPIFY_CONFIGS`, Partner validation) |

## 2. Coexistence rules (implemented)

| Risk | How it is avoided |
|---|---|
| Shared app credentials | Separate settings `SHOPIFY_COMMERCE_*`, separate Super Admin page. Saving one never changes the other. The legacy Partner validation runs only for the legacy page. |
| Token overwrite | A separate Shopify app has its own installation and its own token per shop. Commerce never reads or writes `Integrations::Hook`, and legacy never reads `commerce_stores`. |
| Callback collision | `/commerce/shopify/callback` vs `/shopify/callback`; each has its own state format and secret. |
| Webhook collision / duplication | `/webhooks/shopify_commerce` vs `/webhooks/shopify`. Neither accepts the other app's signature (spec and E2E). Commerce subscriptions are app-specific to its own app, so nothing is subscribed twice. |
| Duplicate order display in one account | Connecting a shop through Commerce is refused while the same account has a legacy hook for that shop: `STORE_ALREADY_CONNECTED (legacy_shopify_integration)`, with a message saying to disconnect it there first. The legacy hook is not touched. |
| Sidebar / panel duplication | The Commerce panel lists only `commerce_stores`. The legacy sidebar section is unchanged and separate. Shopify Commerce adds no sidebar section. |
| Feature switches | `SHOPIFY_COMMERCE_ENABLED` + `lynomia_commerce` for Commerce; `ENABLE_SHOPIFY_INTEGRATION` (+ the `shopify_integration` account feature) for legacy. Turning one on or off never affects the other (specs, E2E). |

**The other direction (closed in Phase 6).** The legacy connect start (`POST /api/v1/accounts/:id/integrations/shopify/auth`) refuses a shop this account already has as a Lynomia Commerce store (any status but disconnected):
- It answers 422 `This Shopify store is already connected through Commerce` and issues no state.
- It is the only way into the legacy callback, which requires that state, so it is the earliest shared entry point.
- The guard is the only legacy change: legacy tokens, hooks, webhooks, billing and the callback are untouched.

Both directions are specs:
- legacy → existing Commerce shop refused: `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`;
- Commerce → existing legacy shop refused: `spec/controllers/api/v1/accounts/commerce/shopify_connections_controller_spec.rb`.

So no account can hold the same shop through both paths. Two narrow cases remain, both accepted:
- The legacy settings page shows its generic request-failed message rather than this text. The legacy UI is not changed.
- A legacy authorization already started before the Commerce store was connected can still complete within its 10-minute state. Both flows are administrator-initiated.

## 3. Evidence that legacy is unchanged

- **No legacy file changed in Phase 5.** Phase 6 adds only the conflict guard above to the legacy connect start. `git diff --stat 59fd18357..6903fde21` (Phase 5 start to end) over `app/services/shopify`, `app/controllers/shopify`, `app/controllers/webhooks/shopify_controller.rb`, `app/controllers/api/v1/accounts/integrations/shopify_controller.rb`, `app/helpers/shopify`, `app/models/integrations`, `config/routes.rb` and `enterprise/` is empty.
  - Phase 5 touched the shared Super Admin files (`installation_config.yml`, `features.yml`, `app_configs_controller.rb`) only by **adding** entries; the legacy `SHOPIFY_CONFIGS` entry is untouched.
- **Legacy specs pass unchanged:**
  - `spec/controllers/shopify`, `spec/controllers/webhooks/shopify_controller_spec.rb`, `spec/services/shopify`, `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`
  - the enterprise Shopify billing specs (full suites, doc 22 §4).
- **E2E checks:**
  - the legacy Super Admin page shows no Commerce field;
  - the legacy settings fingerprint (values hashed) and hook count are identical before and after the whole run;
  - the legacy webhook endpoint refuses a Commerce-signed delivery.

**Observations about legacy, not changed.** These are recorded for a future legacy task:
- The legacy customer search writes the contact's email and phone into the REST `customers/search.json` query unescaped (`"email:#{contact.email}"`). Commerce builds search strings only through the escaping helper.
- The legacy integration uses a non-expiring offline token. Shopify requires expiring offline tokens for all public apps from 2027-01-01, so the legacy integration will need that migration regardless of Commerce.

## 4. What Commerce does not do

- It does not read legacy tokens, and does not move legacy installations or hooks into `commerce_stores`.
- It does not change the legacy integration's billing, webhooks, callback or Super Admin settings.
- It does not delete legacy models or services.

## 5. Legacy Shopify migration feasibility

This is an assessment only; no migration was started.

| Question | Finding |
|---|---|
| **Token compatibility** | Not transferable. The legacy token belongs to the legacy app (a different client), and a token cannot be used by another app. Shopify's token exchange can turn a non-expiring offline token into an expiring one (`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`, `subject_token=<offline token>`, `expiring=1`; `@shopify/shopify-api` `migrateToExpiringToken`), but only **within the same app**. |
| **Store identity** | Mappable. Legacy keys a shop by its domain (`reference_id`); Commerce keys it by the numeric shop id. The legacy token can read `shop { id }` (legacy `Shopify::ShopIdentity` already queries the shop) to build the mapping. |
| **Reauthorization** | **Required** with the current design: each merchant authorizes the Commerce app once (Settings → Commerce → Connect with Shopify). |
| **Scope differences** | Commerce needs `read_customers,read_orders`, a subset of legacy's (`+ read_fulfillments`). Protected customer data approval is **per app**, so the Commerce app needs its own Level 1 + Email/Phone approval. |
| **GraphQL migration** | Commerce is GraphQL 2026-07 already. Legacy orders use REST `2025-01`; legacy would need its own GraphQL rewrite only if it were kept. |
| **Expiring-token requirement** | Commerce is compliant (expiring offline tokens only). Legacy is not, and must move to expiring tokens before 2027-01-01 if it remains a public app. |

**Options:**
1. **Guided move, per account (recommended).**
   1. Detect a legacy hook in the account.
   2. Offer "Move to Shopify Commerce".
   3. The administrator authorizes the Commerce app for the shop. This needs a relaxed conflict rule for exactly this flow, since today the connect is refused while the legacy hook exists.
   4. On success, the administrator disconnects the legacy integration.

   No token copying, no background migration, merchant consent per shop.
2. **Make the legacy app the Commerce app.** Exchange each legacy token for an expiring one with the legacy client, then re-home the shop in `commerce_stores`. Not recommended: it couples Commerce to the legacy app's embedded configuration, billing and webhooks, which the dedicated-app decision (doc 18 §1) avoids.
3. **Do nothing.** Keep both; each account uses one path per shop. Legacy still needs its own expiring-token migration before 2027-01-01.

**Recommendation.** Option 1, as a separate, explicitly approved phase, after:
- the Commerce app's protected customer data approval;
- the real Shopify UAT (doc 22 §6).
