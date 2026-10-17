# Partner commerce installation

The server-to-server endpoint a commerce partner uses to connect its own store to one of its
merchants' Lynomia workspaces, without the merchant pasting a credential into a form.

Added for Store Syria. Written as a provider-agnostic contract, but the allow-list is one entry
long on purpose — see *Which providers* below.

## Request

```
PUT /platform/api/v1/accounts/:account_id/commerce_installation
api_access_token: <Platform App token>
Content-Type: application/json

{
  "provider":          "storesyria",
  "external_store_id": "storesyria.com:26",
  "base_url":          "https://storesyria.com",
  "commerce_token":    "lsc_26_3_<64 hex>",
  "name":              "al atalssian"          // optional
}
```

`external_store_id` is the partner's own installation-qualified identifier. It is **declared and
then proved**: Lynomia presents `commerce_token` back to the partner's commerce API and keeps the
result only if the identity that comes back is this same store.

`name` is optional. An existing row keeps its own name when none is sent.

## Response

```json
{ "provider": "storesyria", "external_store_id": "storesyria.com:26",
  "commerce_store_id": 41, "name": "al atalssian", "status": "active", "applied": true }
```

`applied` says whether **this** call changed anything, which is what lets a partner tell "nothing
needed doing" from "something changed" without having to guess whether an earlier attempt landed.
`status` is `commerce_stores.status`: `active`, `disabled`, `needs_reauth` or `disconnected`.

### Refusals

| HTTP | `error_code` | Meaning |
|---|---|---|
| 401 | `Invalid access_token` | not a Platform App token |
| 401 | `non_permissible_resource` | the app holds no permissible on that account — **also the answer for an account id that does not exist** |
| 422 | `invalid_request` | a required parameter is missing |
| 422 | `provider_not_installable` | that provider is not installed by a partner |
| 422 | `provider_disabled` | the provider is switched off installation-wide (Super Admin) |
| 422 | `platform_owned_account` | that account is the installation's own workspace |
| 422 | `commerce_disabled` | the account's plan does not include `lynomia_commerce` |
| 422 | `invalid_store_url` | `base_url` is not an acceptable store URL (`Commerce::StoreUrl`) |
| 422 | `auth_invalid` | the credential does not resolve, at the partner, to the declared store |
| 422 | `store_limit_reached` | the account is at its plan's `stores` limit |
| 409 | `installation_claimed_elsewhere` | another account holds that store |

`commerce_disabled` is a refusal rather than a quiet success because every commerce read path
checks the feature: a store connected into an account without it is a row that works and a product
that does not. The feature is **not** granted here — a capability a plan sells is written only
through `Billing::OverrideGrant` (see `Platform::Api::V1::AccountsController#update_resource_features`).

## Idempotency

The operation is keyed on `(provider, external_store_id)` and runs under
`Commerce::StoreLock`, which is a Redis lock held across accounts and processes. Two simultaneous
calls produce one installation.

| Existing row | Action | `applied` |
|---|---|---|
| none | health-check, then `StoreConnection#attach` | `true` |
| this account, `active`, same credential | nothing | `false` |
| this account, `active`, different credential | `rotate_credentials` | `true` |
| this account, `needs_reauth` | `rotate_credentials` — the repair | `true` |
| this account, `disconnected` | `attach` reuses the row | `true` |
| this account, `disabled` | nothing; `status: "disabled"` is reported | `false` |
| another account, `disconnected` | `attach` releases it to this one | `true` |
| another account, otherwise | `409 installation_claimed_elsewhere` | — |

A `disabled` store is left alone deliberately: that state is a Lynomia operator's decision, and a
partner call that re-enabled it would be a partner undoing a decision made on this side of the
boundary. The partner is told the state instead.

## What the endpoint does not do

* It does not create, admit or role an account user. Commerce installation and seat admission are
  separate operations.
* It does not enable a plan feature, change a limit, or touch billing.
* It does not grant order-write access. `Commerce::Providers::Storesyria.supports_actions?` is
  `false` and Store Syria's commerce API is read-only.
* It does not bring an installation into existence for a provider whose credential a merchant
  holds themselves.

## Which providers

`Commerce::PartnerInstallation::CREDENTIAL_FORMATS` is the allow-list, and its keys are the whole
of it. Salla, Zid and Shopify are connected through their own app installations, which carry an
OAuth grant the merchant gave in the store's own dashboard; WooCommerce keys belong to whoever
generated them. Store Syria is the one provider whose credential is minted by a partner that has
already authenticated the merchant itself — which is what makes installing on their behalf
meaningful rather than presumptuous.

## Relationship to the lifecycle endpoint

`installation_lifecycle` moves an installation that exists (`suspend` / `resume` / `disconnect`)
and documents in its own header that it deliberately does not offer `activate` from nothing. This
endpoint is that missing half, with the checks that absence was protecting. Together they are the
whole of a partner's control over its own installations; neither can reach another account's.
