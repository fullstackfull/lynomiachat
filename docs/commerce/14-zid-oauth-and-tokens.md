# Lynomia Commerce: Zid OAuth and token lifecycle (Phase 4)

Zid is the third provider on the Commerce core, after WooCommerce (docs 07–09) and Salla (docs 10–13). It reuses:
- the store model, `StoreConnection` ownership rules and customer links;
- the matcher, the cache, the panel and the permissions.

This document covers how a Zid store is connected and how its tokens are kept usable. Webhooks are covered in doc 15, the provider in doc 16 and the E2E in doc 17.

## 0. Sources

Zid's documentation hosts (`docs.zid.sa`, `help-partner.zid.sa`, `changelog.partner.zid.sa`, `partner.zid.sa`) and its API hosts are blocked by this environment's egress proxy. The contract below comes from:

| Source | What it gives | Version |
|---|---|---|
| **Zid AI Agent Skill**, Zid's official reference for building Zid apps (`github.com/zidsa/zid-agent-skill`, linked from docs.zid.sa/zid-agent-skill) | OAuth flow, token response, headers, refresh, uninstall, errors, rate limits, endpoint index | commit `5d49695` (2026-07-20) |
| **Zid Python SDK**, official (`github.com/zidsa/sdk-python`, PyPI `zid-client`) | Token model, manager profile model (`user.store`), orders/customers/webhooks resources, recorded API fixtures | 0.1.2, commit `9f81472` (2026-05-11) |
| docs.zid.sa pages, through web search | Authorization, create/list/delete webhooks, list orders (marketplace masking), list customers (scope names) | read 2026-09-30 |
| Zid Partner changelog 57336, through web search | "Action Required: Webhook Security Changes by September 30, 2026": Basic Authentication mandatory for all webhooks | read 2026-09-30 |

Anything these do not settle is marked **VERIFY** and listed in §8. It is resolved in the real UAT (doc 17 §6).

## 1. Super Admin: Settings → Zid

| Field | Type | Why it is here |
|---|---|---|
| Enable Zid (`ZID_ENABLED`) | boolean | The installation's provider switch. It is separate from the `lynomia_commerce` plan feature, and both are required to connect or read a Zid store. |
| Zid Client ID (`ZID_CLIENT_ID`) | plain | The Lynomia app's OAuth client id (Zid Partner Dashboard). |
| Zid Client Secret (`ZID_CLIENT_SECRET`) | `secret` | Used only server-side for the token requests. Write-only: masked, never rendered, a blank field keeps the stored value, and it is filtered from logs. |

- There is no redirect-URL setting. The callback URL is always `<FRONTEND_URL>/commerce/zid/callback`, since Zid requires the exact registered value on every OAuth request (`Commerce::Zid::Config.redirect_uri`).
- It is registered once as the app's callback URL in the Zid Partner Dashboard.
- No merchant token is ever stored in Super Admin.

## 2. Connect flow (OAuth 2.0 Authorization Code, server-side)

```
Admin: Settings → Commerce → Add store → Zid → [Connect with Zid]
  POST /api/v1/accounts/:id/commerce/zid_connection      (administrator, lynomia_commerce, Zid enabled, encryption configured)
    → { authorize_url } + Set-Cookie lynomia_zid_oauth (encrypted, HttpOnly, SameSite=Lax, Path=/commerce/zid/callback, 10 min)
Browser → https://oauth.zid.sa/oauth/authorize?client_id=…&redirect_uri=<FRONTEND_URL>/commerce/zid/callback&response_type=code&state=…
Merchant approves on Zid → Zid redirects to the callback with ?code=…&state=…
GET /commerce/zid/callback
  1. state: signature, expiry, one use, same browser (cookie)        → else: redirect <FRONTEND_URL>/app, nothing named, nothing saved
  2. user from the state is still an administrator of the account from the state; account has lynomia_commerce; Zid enabled
  3. code present (a declined authorization has none)
  4. POST https://oauth.zid.sa/oauth/token  grant_type=authorization_code, client_id, client_secret, redirect_uri, code   (server-side, once)
  5. GET https://api.zid.sa/v1/managers/account/profile with both tokens → user.store.{id, title, url, timezone}
  6. under the store lock: save through StoreConnection (new store) or re-authorize the account's own store in place
  7. queue the webhook registration (doc 15)
  → redirect <FRONTEND_URL>/app/accounts/:id/settings/commerce?zid=connected   (or ?zid_error=<code>)
```

- **Nothing is saved before step 5 succeeds.** A code Zid rejects, or a profile without a store id, saves nothing (`AUTH_INVALID` / `INVALID_RESPONSE`).
- **Ownership (unchanged core rules).**
  - A store connected to another account is never moved (`STORE_ALREADY_CONNECTED`).
  - A disconnected store row is reused, or released to the new account.
  - The account's own store (active, disabled or needs_reauth) takes the new tokens in place. A disabled store stays disabled.
- **App Market installs.** A merchant who installs the app from the Zid App Market without starting from Lynomia reaches the callback without a Lynomia state. That callback is refused and connects nothing. Stores are connected from Lynomia (Settings → Commerce), where the account is known. The Partner Dashboard's app URL should point merchants to the Lynomia dashboard.
- The Salla one-time-code correlation (doc 10) is not used: Zid's callback carries our `state`.

## 3. State

`Commerce::OauthState` (provider `zid`; shared with Shopify since Phase 5) answers "never trust query parameters alone for tenant ownership":

| Property | How |
|---|---|
| Signed | `Rails.application.message_verifier('commerce_zid_oauth')`: a key derived from `secret_key_base`, purpose-bound. It is not signed with the Zid client secret, which Zid also knows. |
| Account-bound, user-bound | The payload carries `account_id` and `user_id`. The callback takes the account only from the state, then re-checks that the user is still an administrator there (`Commerce::StorePolicy#create?`). |
| Nonce-protected, single-use | 256-bit nonce. `COMMERCE::ZID::OAUTH_STATE::<sha256(nonce)>` is set in Redis for 10 min and deleted on first use (`DEL` returns 1 once). |
| Short-lived | `expires_in: 10.minutes` in the signed message, and the same TTL on the nonce and the cookie. |
| Browser-bound | The nonce is also in the encrypted HttpOnly cookie set by the start request, and compared in constant time. A state leaked to or replayed from another browser is refused, and it is not consumed by that attempt. |

Reuse: the same Rails message-verifier infrastructure the upstream Google/Microsoft OAuth callbacks use (`to_sgid` in `OauthCallbackController`). The `code` and `state` parameters are filtered from request logs (`config/initializers/filter_parameter_logging.rb`, exact-key match).

Evidence (specs):
- `spec/services/commerce/oauth_state_spec.rb`: valid, replayed, other browser, missing cookie, expired, forged with another key, tampered, garbage.
- `spec/controllers/commerce/zid/callbacks_controller_spec.rb`:
  - state checked before the code;
  - replay, expired state, query `account_id` ignored;
  - another browser (agent), demoted administrator, Commerce or Zid switched off meanwhile;
  - declined authorization, rejected code, unverifiable profile;
  - store of another account, re-authorization in place;
  - tokens encrypted and absent from browser/logs.
- `spec/controllers/api/v1/accounts/commerce/zid_connections_controller_spec.rb`: agents refused, feature off, Zid off, no encryption.
- E2E doc 17 §3.

**VERIFY (state round-trip).** Zid's docs show the authorize request without `state`.
- OAuth 2.0 requires the server to return `state` unchanged when the client sends it (RFC 6749 §4.1.2). `oauth.zid.sa` exposes the standard `/oauth/authorize` and `/oauth/token` endpoints of an RFC 6749 server.
- This fails closed. If Zid dropped `state`, every callback would be refused and nothing would ever be attached to the wrong account.
- The real UAT confirms it first (doc 17 §6).

## 4. Token payload and stored credentials

Zid answers both grants with (official skill, `references/oauth-flow.md`; SDK `TokenResponse`):

```json
{ "access_token": "…", "authorization": "…", "refresh_token": "…", "expires_in": 31536000 }
```

`Commerce::Zid::Tokens` stores exactly this, in `commerce_stores.credentials` (Active Record encryption):

| Stored key | From | Used as |
|---|---|---|
| `authorization` | `authorization` (the SDK also accepts `Authorization`) | `Authorization: Bearer <authorization>` |
| `access_token` | `access_token` | `X-Manager-Token: <access_token>` |
| `refresh_token` | `refresh_token` | refresh grant only |
| `expires_at` | now + `expires_in` (integer or numeric string); `nil` when Zid sends none | proactive refresh |
| `token_type`, `scope` | only when Zid sends them | informational |
| `webhook_username`, `webhook_password` | generated by Lynomia (doc 15) | webhook Basic Auth |

- No `refresh_token_expires_at`: Zid sends no refresh-token expiry, so none is invented.
- The two tokens are kept under distinct names, as Zid's skill asks: they are not interchangeable.
- Tokens never reach the browser, logs, audit entries, the Redis order cache or error messages. The stores API renders an allow-list without credentials, and errors carry codes only.

## 5. Token lifecycle

`Commerce::Zid::TokenManager`:

| Situation | Behaviour |
|---|---|
| Expires in more than 60 days | Used as is; no Zid call. |
| Expires within 60 days (or expired) | Refreshed under `Commerce::StoreLock('zid', <store id>)`: re-read the store; if another process already refreshed, use its tokens; else send **one** refresh request (`post_form`, never retried) and save all new tokens in one write (other credential keys kept). |
| Zid rejects the tokens early (401, or a redirect to Zid's login page) | Zid's documented recovery: refresh once (or take tokens another process saved meanwhile) and retry the request once. A second rejection means the authorization is gone, so the store moves to `needs_reauth`. |
| Refresh answered `400`/`401` (invalid_grant, revoked, expired) | `needs_reauth`: tokens removed (webhook pair kept for the re-registration's cleanup), cache purged, audited `commerce.zid.needs_reauth`. Only an administrator's Reconnect fixes it. |
| Refresh answered 200 with an unusable body | `needs_reauth` (`refresh_response_invalid`); nothing from the body is stored. This is a safe failure, not a retry loop. |
| Refresh rate limited, Zid 5xx, not sent, or answer lost in transit | Tokens kept (single-use is **not** assumed; §8), `refresh_failed_at` recorded, and no new refresh for one hour. A token that has not expired keeps working meanwhile. An expired one reports the error, and after a 401 the error stays `AUTH_INVALID`, so cached data is never served over rejected tokens. |
| `invalid_client` | `STORE_UNAVAILABLE / zid_client_rejected`: the installation's client credentials are wrong, not the store's. |
| No `expires_in` from Zid | Refreshed only after Zid rejects the tokens. |

- **No infinite retry.** A refresh request is sent at most once per lock, never retried by the HTTP client, and at most once an hour after a passing failure.
- **Concurrency.** The lock plus re-read gives one refresh for N concurrent readers (spec: 10 threads → 1 request; E2E: same).
- **Single-use.** Phase 1 (doc 02 §4) cited a help-partner article saying Zid refresh tokens are single-use. Zid's official skill and SDK do not say so. The SDK keeps the old refresh token on failure and retries, so the behaviour is not assumed either way.
  - The design is safe both ways: a refresh is never sent twice concurrently.
  - A refresh whose answer is lost keeps the old token, since Zid does not document it as spent. If Zid had spent it, the next refresh gets `invalid_grant` and the store asks for re-authorization; nothing loops.
- **Uninstall.** Zid invalidates every token at once. The next read gets 401, then the refresh gets `invalid_grant`, then `needs_reauth`. The app lifecycle webhook (`app.market.application.uninstall`, Partner Dashboard) is not subscribed in this phase; §8.
- The official guidance is to refresh around month 10. The 60-day window applies on use. A store unused for more than ~10 months may lapse and then asks for Reconnect; there is no background sweep in this phase (doc 17 §7).

Evidence: `spec/services/commerce/zid/token_manager_spec.rb` (16 examples) and `spec/services/commerce/providers/zid_spec.rb` (tokens and errors).

## 6. Scopes

Scopes are chosen per app in the Zid Partner Dashboard. The authorize request carries none (official skill), so Lynomia cannot widen them at runtime. The app needs:

| Scope (Partner Dashboard) | Why |
|---|---|
| Orders: **read** | `GET /managers/store/orders` (customer discovery through `search_term`, a customer's orders, order detail). |
| Webhooks: **read & write** (`webhooks.read_write`) | `POST` / `DELETE /managers/webhooks`: Lynomia's own order-event subscriptions (doc 15). This manages subscriptions only and never writes store data. Zid gives it no read-only variant that can subscribe. |
| (manager profile) | `GET /managers/account/profile` identifies the store; no separate scope is documented. **VERIFY**. |

- **Not requested:**
  - Customers read (`third_customers_read`): customers come from orders, and the customers endpoints are not called.
  - Any products, orders, customers or inventory **write** scope. Abandoned carts are out of MVP.
- Exact scope identifiers as shown in the dashboard: **VERIFY**.
- STOP condition 3 does not apply: no commerce data write scope is required. The webhook subscription scope is the one the task's webhook design requires.

## 7. Files

- Services:
  - `custom/app/services/commerce/zid/config.rb`, `oauth.rb`, `oauth_state.rb`, `tokens.rb`, `authorization.rb`, `token_manager.rb`;
  - `custom/app/services/commerce/store_lock.rb` (shared with Salla, formerly `Commerce::Salla::MerchantLock`, same Redis keys).
- Controllers:
  - `custom/app/controllers/api/v1/accounts/commerce/zid_connections_controller.rb`;
  - `custom/app/controllers/commerce/zid/callbacks_controller.rb`.
- `config/routes/commerce.rb`, `config/installation_config.yml`, `app/helpers/super_admin/features.yml`, `app/controllers/super_admin/app_configs_controller.rb`, `config/initializers/filter_parameter_logging.rb`.

## 8. VERIFY (to close in the real UAT)

1. `oauth.zid.sa/oauth/authorize` returns `state` unchanged. This fails closed if not.
2. The token response carries `expires_in` as an integer (the official example shows a placeholder string).
3. Refresh-token rotation and single-use behaviour; the answer to reusing a spent refresh token.
4. The manager profile path `user.store.id` / `title` / `url` / `timezone` (SDK model and fixtures: confirmed shape; live value unverified).
5. Scope identifiers in the Partner Dashboard, and whether the manager profile needs one.
6. Whether a merchant-initiated App Market install can deep-link into Lynomia (Partner Dashboard app URL).
