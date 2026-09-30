# Lynomia Commerce: WooCommerce security

This document covers:
- the controls implemented in Phase 2;
- the tests that prove each control;
- the risks that remain.

The design baseline is `04-security-and-tenancy.md`.

## 1. Credentials

| Requirement | Implementation | Evidence |
|---|---|---|
| Encrypted at rest | `Commerce::Store` `encrypts :credentials` (Active Record encryption, non-deterministic). Link ids use `encrypts :external_customer_id, deterministic: true`, because guest ids carry an email or phone. | `store_connection_spec` reads the raw column: no `ck_`/`cs_`. E2E: the raw `credentials` is `{"p":…,"h":{"iv":…}}`, and **0** occurrences of any of the 3 stores' keys or secrets in a full `pg_dump` (`09` §5). |
| Refused without encryption | `StoreConnection` raises `ENCRYPTION_NOT_CONFIGURED` **before any network call** when `Chatwoot.encryption_configured?` is false. The model also refuses to save credentials. | `store_connection_spec`, `store_spec` |
| Never sent back to the browser | Explicit jbuilder allow-list. `Store#serializable_hash` drops `credentials`. The edit form has write-only password fields, cleared on close. | Request specs. E2E: 697 API responses captured in the browser, **0** contain a key, secret or a `credentials` field. |
| Never logged | Rails `filter_parameters` (`_key`, `secret`) masks request params as `[FILTERED]`. `HttpClient` logs path + status + ms only. Encrypted attributes are filtered from `inspect`. | `http_client_spec` (log contains no key or query). E2E server log: **0** occurrences. |
| Not in audit payloads | Audit changes carry provider, external id, status, match source and counts only. | E2E audit dump (`09` §5) |
| Not in Redis | The cache stores provider-neutral orders and candidates only. | `cache_spec`. E2E: 0 keys/secrets across all `COMMERCE` values. |
| Not in errors | `Commerce::Error` carries a code and an optional safe reason. Provider bodies are never raised or rendered. | `http_client_spec` (a 401 with "Consumer secret is invalid." renders only `AUTH_INVALID`) |
| Read keys only | The UI asks for Read keys; only GET requests exist in code. A Read key cannot be verified without a write, which is never attempted (`07` §14). | `woocommerce_spec` ("exposes no write operation") |
| Strict key format | `ck_` + 40 hex and `cs_` + 40 hex (WooCommerce's format); anything else is 422 before any call. CRLF and garbage are impossible. | Request spec (short key, CRLF secret) |
| Rotation | `PATCH` with both keys; the health check uses the **new** keys before saving; the cache is purged; audited. | `store_connection_spec`, E2E lifecycle |
| Disconnect | Credentials set to `NULL`, links deleted, cache purged, audited. | `store_connection_spec`, E2E |

## 2. Store URL and SSRF

**Layer 1: `Commerce::StoreUrl`, at connect.** Parsing uses `URI`, not a regex.
- scheme `https` (no scheme means https);
- default port only;
- no userinfo, query, fragment or `..`;
- IP literals refused;
- normalized lowercase host, no trailing slash.

**Layer 2: `Commerce::HttpClient`, on every request.**
- `SsrfFilter` resolves the host and refuses the request unless at least one address is public. The refused ranges are:
  - 0/8, 10/8, 100.64/10 (incl. Alibaba metadata), 127/8, 169.254/16 (AWS/GCP/Azure metadata), 172.16/12, 192.168/16;
  - the TEST-NETs and multicast;
  - `::1`, `fc00::/7` (incl. AWS IPv6 metadata `fd00:ec2::254`), `fe80::/10`;
  - IPv4-mapped, compatible and NAT64 forms of all of the above.
- The connection is **pinned to the checked IP** (`ipaddr:`), so DNS rebinding between the check and the connect is not possible.
- **Redirects are never followed** (`max_redirects: 0`). Any 3xx becomes `INVALID_STORE_URL/redirect`, so a store cannot bounce Lynomia to an internal address, even through a public intermediary.

**Explicit internal policy:**
- `COMMERCE_TRUSTED_STORE_HOSTS` is an exact host list and is empty by default.
- Only those hosts may use `http`, a custom port or a private address (development and staging stores).
- They get the same limits and no redirects either.
- Other hosts stay fully checked even when the list is set.

**Why not `SafeFetch`:** it follows up to 10 redirects, does not expose status codes, and its private-network switch is global. Commerce needs no redirects, status mapping and a per-host exception.

**SSRF test matrix:**

| Case | Where | Result |
|---|---|---|
| `http://…` (untrusted) | `store_url_spec`, E2E | `https_required` |
| `https://host:8443` | `store_url_spec` | `port_not_allowed` |
| `https://10.0.0.5`, `https://169.254.169.254`, `https://[::1]` | `store_url_spec`, E2E UI + API | `ip_address_not_allowed`, no request |
| `user:pass@`, `?redirect=http://10.0.0.1`, `#x`, `/a/../../admin`, `ftp://` | `store_url_spec` | `invalid` |
| Host resolving to 127.0.0.1, 10.0.0.5, 172.16.4.2, 192.168.1.10, 169.254.169.254, 100.100.100.200, 0.0.0.0, ::1, fd00:ec2::254, fe80::1, ::ffff:127.0.0.1 | `http_client_spec` (11 examples) | `private_address`, **no connection made** |
| Real public name resolving to loopback (`localtest.me`) | E2E (real DNS) | "points to a private network" |
| Unresolvable host | `http_client_spec` | `STORE_UNAVAILABLE/dns` |
| 302 to `http://169.254.169.254/latest/meta-data/` | `http_client_spec` | `redirect`, metadata **never requested** |
| 301 to the same host | `http_client_spec` | `redirect`, not followed |
| Trusted internal host allowed; other private hosts still blocked | `http_client_spec` | as described |

## 3. Bounded requests

| Limit | Value |
|---|---|
| Connect / TLS | 3 s |
| Each read / write | 8 s |
| Whole body | 10 s deadline and 5 MB (`INVALID_RESPONSE/too_large`) |
| Retries | GET only, **at most one**, only for a dropped connection (`ECONNRESET`/`EOF`) or 502/503/504. Timeouts and 500 are not retried, so a slow store costs at most one timeout. |
| Page sizes | `per_page` ≤ 20 (WooCommerce caps at 100) |

**Error mapping:**
- 401 → `AUTH_INVALID`
- 403 → `PERMISSION_DENIED`
- 404 → `NOT_FOUND`
- 429 → `RATE_LIMITED`
- 5xx → `STORE_UNAVAILABLE/http_<code>`
- non-JSON → `INVALID_RESPONSE/not_json`
- TLS error → `STORE_UNAVAILABLE/tls`
- timeouts → `TIMEOUT`

## 4. Authorization and tenancy

| Action | Who | Mechanism |
|---|---|---|
| List, connect, rotate, enable, disable, disconnect | Administrators | `Commerce::StorePolicy`, only on `Current.account.commerce_stores` |
| Panel, search, link, unlink | Anyone who can view the conversation (admins, agents of the inbox or team, EE custom roles through `ConversationPolicy`) | `Conversations::BaseController#conversation` (`authorize … :show?`) + `Current.account.commerce_stores.active.find` |
| Anything when `lynomia_commerce` is off | nobody | 401 |
| Bots (agent-bot tokens) | nobody | Not in `BOT_ACCESSIBLE_ENDPOINTS` |

**Tenancy rules:**
- A store belongs to one account: unique `(provider, external_store_id)`. Another account gets `STORE_ALREADY_CONNECTED` until the owner disconnects it. The ownership check runs **after** the health check, so only someone holding working keys learns that the store is connected elsewhere.
- A link requires `link.account == store.account == contact.account` (model validation).
- The link endpoint only accepts an **encrypted token** issued for this conversation's contact and store (15 min, `ActiveSupport::MessageEncryptor` keyed from `secret_key_base`).
  - A forged token, a token for another contact, an expired token or garbage → 422.
  - Tokens do not reveal the masked email or phone.
- Cache keys include account and store; purge is per store.
- **Tested:**
  - request specs: other account's store 404, disabled store 404, agent 401, outsider agent 401;
  - E2E API checks (17/17): A1/A2 vs B1, agent vs admin endpoints, outsider, forged token, name search;
  - E2E UI: account B cannot claim A1; A2 orders never shown for A1.

## 5. Data minimization

| Where | What |
|---|---|
| Postgres | store rows and link rows only (`07` §3). No orders, addresses or customer profiles. |
| Redis (≤ 24 h) | normalized orders (names, items, totals) and candidates. |
| Browser | candidates **masked** until linked. Orders are shown only for the conversation's linked customer. `order_key`, `payment_url`, `customer_ip_address`, `_links` and meta data never leave the backend. |
| Logs | `[Commerce]` lines carry ids, paths and status codes. Search terms (emails, phones) are never logged: 0 matches in the E2E server log. |

## 6. Webhooks

- None in Phase 2: no endpoint, no fake endpoint.
- The design for WooCommerce webhooks (per-store secret, `X-WC-Webhook-Signature`, dedup on delivery id, cache invalidation only) stays in `04` §4.

## 7. Shopify OAuth callback (Part 0)

This is a separate commit: `security: harden Shopify OAuth callback`.

**Before:**
- `shop` was used unvalidated as the token-exchange host, so the client secret was sent to any host;
- the state JWT had no `exp` and no shop binding;
- any agent could mint it;
- the callback HMAC was not verified.

**After:**
- `Shopify::ShopDomain` validation, before anything else;
- a signed state with `exp` (10 min) and a shop claim, which must match;
- Shopify's HMAC is verified (`secure_compare`);
- only admins can start auth.

Regression specs: forged shops (`attacker.example.com`, suffix, `@`, `/`, `#`, IP), wrong-shop state, expired state, legacy state without `exp`, wrong signing secret, missing or wrong HMAC, tampered parameters. There is no other Shopify change: no gem upgrade, no migration to Commerce Core.

## 8. Residual risks

1. **Merchant-controlled data:** item names and shipping titles are shown as text. Vue escapes them, and nothing is rendered as HTML.
2. **Admin links:** "View order" points to the merchant's own admin.
   - The URL is built from the stored store URL plus a numeric id, never from a response.
   - For development stores on the trusted-host list the link may be `http`.
3. **Key strength:** a store whose Read/Write key is pasted instead of a Read key gives Lynomia more power than needed. Lynomia still only sends GETs. Rotate to a Read key.
4. **Customer names in the cache:** Redis holds customer names and items for up to 24 h. Purge happens on disable, disconnect and key failure. A retention statement is still needed before production (`04` §8).
