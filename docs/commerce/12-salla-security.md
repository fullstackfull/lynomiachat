# 12 — Salla: security

This page describes what protects each boundary of the Salla connector, and which spec proves it. It sits alongside
docs 10 (install correlation), 11 (tokens) and 08 (the Commerce core's HTTP and tenancy rules, which Salla reuses
unchanged).

## Trust boundaries

```
Salla ──signed app events──▶ POST /webhooks/salla ──encrypted job──▶ Sidekiq ──▶ Commerce::Salla::Installation
                                                                                  │  user/info, token refresh
Lynomia admin ──connection code──▶ Salla dashboard (app settings) ──signed event──┘  (accounts.salla.sa)
Agent ──conversation API──▶ Commerce::ConversationPanel ──▶ Providers::Salla ──Bearer──▶ api.salla.dev/admin/v2
```

Nothing that comes from the browser reaches Salla except an exact email or E.164 phone typed in the panel's search. No
Salla token, refresh token, client secret or webhook secret ever reaches the browser.

## 1. Webhook authenticity: `Webhooks::SallaController`, `Commerce::Salla::Webhook`

- The request must carry `X-Salla-Security-Strategy: Signature` and `X-Salla-Signature`. The signature is the hex
  HMAC-SHA256 of the **raw** request body under the app's webhook secret (Salla agent kit, `salla-webhooks`). It is
  compared with `ActiveSupport::SecurityUtils.secure_compare`, in constant time.
- The body is only parsed, and the job only queued, after the signature checks out. A missing header, another
  strategy (`Token`), a bad signature, a changed body or another secret all get **401**.
- With no webhook secret configured, every delivery gets 401: nothing is ever verified against an empty key.
- Rails' own parameter log parses JSON bodies for display. Access and refresh tokens are filtered there by the
  existing `/token/` rule, and the connection code by the new `:connection_code` rule.

Specs: `spec/controllers/webhooks/salla_controller_spec.rb` covers valid, missing, invalid, changed body, wrong secret,
other strategy, no secret and log filtering. A mutation run that replaced the HMAC comparison with "signature present"
failed 4 of its examples.

## 2. Replay and idempotency

- Salla has no event id and resends a failed delivery three times. The SHA-256 of the raw body is claimed with Redis
  `SET NX EX 3d`, so identical bytes are queued once. If queuing fails, the claim is released and Salla's retry gets
  through.
- The handlers are idempotent on their own:
  - a repeated authorization rewrites the same credentials;
  - a used connection code is gone (`MULTI GET DEL`);
  - a repeated uninstall finds a disconnected store and does nothing.
- A replayed old `app.store.authorize`, even if validly signed, can at most:
  - put tokens back on a store already connected to that same merchant;
  - leave waiting tokens that need a fresh code from the store's own dashboard.

  It cannot connect a store to any account.

## 3. Tenant isolation

- **Connecting (doc 10).** A store is attached to an account only when two things match for the same merchant: a
  signed authorization, and a signed settings event carrying a one-time code that an administrator of that account
  created. The merchant id is confirmed against `user/info` with the new token.
  - A store connected to one account is never moved to another (conflict).
  - Spec: `spec/services/commerce/salla/installation_spec.rb`.
- **Reading.** Unchanged Commerce core: every conversation API call is scoped to the conversation's account and to that
  account's active stores. Customer links carry the account and are validated against both store and contact. Cache
  keys contain the account and store ids.
  - Specs: `stores_controller_spec.rb` (multi-store, multi-tenant) and `salla_panel_spec.rb`.
- **Merchant-level state.** Waiting tokens, claims, the refresh lock and the rate-limit backoff are keyed by Salla
  merchant id, which is unique per store. Nothing about a merchant is shared across accounts.

## 4. Secrets and tokens at rest

| Secret | Where | Protection |
| --- | --- | --- |
| Client secret, webhook secret | `installation_configs` (Super Admin) | Typed `secret`: write-only, masked, never rendered, filtered from logs, not on the generic configs page. Spec: `spec/controllers/super_admin/salla_app_config_spec.rb`. |
| Access and refresh tokens of a connected store | `commerce_stores.credentials` | Active Record encryption. A store cannot be saved without encryption keys (`ENCRYPTION_NOT_CONFIGURED`), and the connection API refuses to start without them. `serializable_hash` drops the column; the JSON views list fields explicitly. |
| Tokens waiting for a code | Redis `COMMERCE::SALLA::MERCHANT::<id>::TOKENS` | `Redis::SecureStorage` (AES-256-GCM), 7 days. |
| Queued webhook bodies | Sidekiq job arguments | `ActiveSupport::MessageEncryptor` (AES-256-GCM, key derived from `secret_key_base`). The job arguments hold no plaintext token or merchant id (webhook spec). |
| Connection code | Redis | Only an HMAC of the code, 1 hour, single use. The code itself is shown once, to the administrator who created it. |

**Never logged:**

- `Commerce::HttpClient` logs only the method, path, status and duration: no query string (it can hold an email or
  phone), no headers and no body.
- Audit entries record reason codes and expiry times only. Specs assert that no token appears in logs, errors or audit
  rows (`token_manager_spec.rb`, `installation_spec.rb`, `http_client_spec.rb`).

## 5. Network

- The hosts are fixed in code: `https://api.salla.dev/admin/v2` and `https://accounts.salla.sa`. No tenant or store
  setting can change them.
- Requests use the same `Commerce::HttpClient` as WooCommerce:
  - SsrfFilter checks resolved addresses and pins the connection;
  - redirects are never followed;
  - connect 3 s, read 8 s, body 10 s and 5 MB;
  - `GET` is retried once, for a dropped connection or a 502/503/504 only.
- The token request (`post_form`) is **never** retried (doc 11).
- The admin link on an order is Salla's own `urls.admin`, kept only when it is https on `s.salla.sa`. A tracking link is
  kept only for a trackable shipment and only over https. The panel re-checks both before rendering
  (`safeHttpsUrl` / `safeAdminUrl`).

## 6. Least privilege

- **Salla scopes.** `customers.read orders.read shipping.read offline_access`. A token that carries any write scope is
  refused and never stored, and so is one that lacks a required scope (`Commerce::Salla::Tokens`).
- **Lynomia roles.**
  - Only account administrators can create connection codes, see connection progress, disable, enable or disconnect
    stores (`Commerce::StorePolicy`). The connection API specs cover agents, `lynomia_commerce` being off, and Salla
    being switched off.
  - Agents see Commerce data only through conversations they can already access.
- **Provider switch.** `SALLA_ENABLED` (Super Admin) is separate from the `lynomia_commerce` plan feature. With it off:
  - no new Salla connection can be made;
  - Salla stores are not read;
  - a disabled Salla store cannot be re-enabled.
- **API keys.** The stores API refuses WooCommerce-style API keys for a Salla store, so a Salla store's credentials can
  only come from Salla.

## 7. Abuse and availability

- **Rate limits.** When Salla answers 429, or reports no requests left, the connector stops calling that merchant until
  Salla's `Retry-After` or reset time (at most 60 s). The panel serves its cache as stale meanwhile. Only the Salla
  connector does this; the Commerce core is unchanged.
- **Customers API.** It has its own tighter cap (500 per 10 minutes). Discovery results are cached (fresh for 120 s,
  kept for 24 h), and searches are for exact identifiers only.
- **Auth errors.** A revoked token, or a token Salla rejects, is never hidden behind stale data. The store is marked
  `needs_reauth`, its cache is purged, and the error is shown (`salla_panel_spec.rb`).
- **Webhook endpoint.** It does constant-time work before verification (one HMAC over the body) and queues only
  verified, first-seen bodies.

## 8. Residual risks

- The connection code is visible in the merchant's Salla app settings after use. By then it is spent (single-use), so
  it grants nothing.
- An `app.store.authorize` that arrives after an uninstall of the same merchant (order is not guaranteed) can leave
  waiting tokens, and those tokens are probably already revoked. They expire in 7 days. Connecting still needs a new
  code, and a dead token turns the store `needs_reauth` on its first read.
- The Salla webhook secret must match the Partner Portal. If it is rotated in the Portal without updating Super Admin,
  every event gets 401. This fails loudly (Salla shows the failures), never silently.
- The webhook secret is installation-wide, as Salla issues it per app. Anyone holding it could forge events, so it is
  stored and handled like the client secret.
