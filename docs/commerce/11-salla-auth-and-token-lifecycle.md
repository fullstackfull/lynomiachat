# 11 — Salla: authorization, scopes and the token lifecycle

## Authorization mode: Easy Mode

Lynomia is a published Salla app, so it uses **Easy Mode**. Salla sends the tokens to the app's webhook in
`app.store.authorize`, on install and again after every app update. Lynomia has no OAuth redirect or callback of its
own. Salla's agent kit (`salla-app-auth/SKILL.md`) is explicit: Custom Mode (our own `/callback`) is for development
and "can be rejected at review" for a published app. Which Lynomia account the tokens belong to is settled separately,
by the connection code (doc 10). The browser never sees a token: the only Salla data it receives is the store's
name, status and URL.

## Scopes

Set in the Salla Partners portal (Easy Mode takes the scopes from the app's configuration). Lynomia only reads.

| Scope | Why |
| --- | --- |
| `customers.read` | Find the store customer for a conversation's verified phone or email (`GET /customers?keyword=`). |
| `orders.read` | The linked customer's latest orders (`GET /orders?customer_id=`). |
| `shipping.read` | Shipment carrier, status and tracking for those orders (`GET /shipments?order_id=`). |
| `offline_access` | Required for Salla to issue a refresh token. Without it the merchant would have to reinstall every time the access token expires. |

No `*.read_write` scope is requested; Lynomia never writes to a store. `Commerce::Salla::Tokens` enforces this at run
time. An authorization or refresh whose scope contains anything other than `offline_access` and `*.read`, or lacks one
of the four above, is refused and its tokens are not stored (`PERMISSION_DENIED`: `salla_write_scope` /
`salla_missing_scope`). Extra read scopes, if Salla ever adds defaults, are tolerated.

## Installation settings (Super Admin → Settings → Salla)

| Field | Kind | Used for |
| --- | --- | --- |
| Enable Salla (`SALLA_ENABLED`) | switch | The installation's provider switch (below). |
| App ID (`SALLA_APP_ID`) | plain | The install link `https://s.salla.sa/apps/install/<App ID>`. |
| Client ID (`SALLA_CLIENT_ID`) | plain | Token refresh. |
| Client Secret (`SALLA_CLIENT_SECRET`) | secret | Token refresh. |
| Webhook Secret (`SALLA_WEBHOOK_SECRET`) | secret | Verifying every Salla event (doc 12). |

Both secrets are typed `secret` in `config/installation_config.yml`:

- they are rendered as empty password fields and never sent back to the browser;
- a blank field keeps the stored value;
- they are left off the generic installation-configs page;
- they are filtered from request logs.

No merchant token is ever stored here. The API hosts (`https://api.salla.dev/admin/v2`, `https://accounts.salla.sa`)
are constants in code, and no tenant or store setting can change them.

**Provider switch vs plan feature.** `lynomia_commerce` is the account's plan feature: whether the account has Commerce
at all. `SALLA_ENABLED` decides whether this installation offers Salla. With the switch off:

- *Connect with Salla* is hidden, and the connection API answers `PROVIDER_DISABLED`;
- Salla stores stay connected but are not listed in conversations and are not read, so no API calls or refreshes happen;
- a disabled Salla store cannot be re-enabled;
- token updates for connected stores and uninstalls are still applied (doc 10).

## Stored credentials

In the existing `commerce_stores.credentials` column, which is encrypted with Active Record encryption. There is no
new table.

```json
{
  "access_token": "…",
  "refresh_token": "…",
  "token_type": "bearer",
  "scope": "offline_access customers.read orders.read shipping.read",
  "access_token_expires_at": "2026-10-14T12:31:25Z",
  "refresh_token_expires_at": null
}
```

- `access_token_expires_at` comes from `expires`, which Salla defines as an absolute Unix timestamp, not a duration.
- `refresh_token_expires_at` is `null` because Salla refresh tokens do not expire. The token chain lives until it is
  used twice or the app is uninstalled.

The credentials never appear in the browser, logs, the Redis order cache, audit entries or error messages. Tokens that
are waiting for a connection code live in `Redis::SecureStorage` (AES-256-GCM, 7 days), and queued webhook bodies are
encrypted (doc 10).

## Refreshing: `Commerce::Salla::TokenManager`

Salla refresh tokens are **single-use**. Sending one twice makes Salla treat the chain as compromised: it revokes the
chain, the current access token included, and the merchant must reinstall. The Salla provider asks the token manager
for a token before every read. A refresh:

1. happens when the access token expires within a day. It is triggered by a read, so an unused store costs nothing;
   the refresh token does not expire.
2. takes the merchant's lock, `COMMERCE::SALLA::MERCHANT::<merchant id>::LOCK`. The lock is `SET NX EX 60` with a random
   owner and is released only by its owner (`Redis::Alfred.delete_if_equals`). Other processes poll for up to 10 s and
   then **re-read the store**; normally it has just been refreshed, so they use the new token.
   Installation events for the same merchant take the same lock.
3. re-reads the store under the lock. If it is still expiring, it saves `metadata.refresh_started_at` (committed)
   *before* sending.
4. sends one `POST https://accounts.salla.sa/oauth2/token` with `grant_type=refresh_token`, `refresh_token`,
   `client_id` and `client_secret`. It is never retried (`Commerce::HttpClient#post_form`).
5. on 200 saves **both** new tokens and the new expiry in one `UPDATE` and clears the marker. Audit
   `commerce.salla.token_refreshed` records only the old and new expiry times.

A concurrency spec runs ten threads against an expiring token: one refresh request is made and all ten get the new
token. With the lock removed, the same spec sees ten requests.

### When a refresh fails

| Outcome | Could Salla have used the refresh token? | Result |
| --- | --- | --- |
| Connection never opened, DNS failure, connect timeout (`not_sent`) | No | Temporary `STORE_UNAVAILABLE`. The token is kept and a later read tries again. |
| 429 | No, the request was not processed | Temporary `RATE_LIMITED`. The token is kept. |
| 401 `invalid_client` | No: client authentication comes before the grant | Temporary `STORE_UNAVAILABLE: salla_client_rejected`. The Super Admin client credentials are wrong. |
| 400/401 `invalid_grant` | It is already dead (revoked, reused, app removed) | **needs re-authorization** |
| Any other 4xx, or a 5xx | Unknown | **needs re-authorization** |
| Read/write timeout, reset connection after sending (`unknown_outcome`) | Unknown | **needs re-authorization** |
| 200 but the tokens cannot be used (missing fields, a write scope) | Yes: it is spent | **needs re-authorization** |
| `refresh_started_at` already set when a refresh starts (a process died mid-refresh) | Unknown | **needs re-authorization**, without sending anything |

"Needs re-authorization" does four things:

- sets the store's status to `needs_reauth`;
- **deletes the refresh token** from the credentials, so it can never be sent again;
- purges the store's cached data;
- audits `commerce.salla.needs_reauth` with the reason code.

The panel stops reading the store. The settings page asks an administrator to re-authorize the app in Salla
(update or reinstall). The next `app.store.authorize` then replaces the credentials and makes the store active again
(`commerce.salla.reauthorized`).

The rule behind the table: **a refresh token that may have reached Salla is never sent again**. If the answer is lost,
there is no safe way to find out whether the token was spent (retrying *is* the reuse Salla punishes), so the store
goes back to the merchant for re-authorization.

A 401 from the Merchant API on a normal read (a revoked token, or an uninstall that has not arrived yet) is handled by
the existing Commerce rule: the store becomes `needs_reauth`, its cache is purged, and the error is shown rather than
hidden behind stale data.

## Audit events (never with tokens or secrets)

| Event | When |
| --- | --- |
| `commerce.salla.connect_started` | An administrator created a connection code (auditable: the account). |
| `commerce.salla.connected` | A store was connected from a code and an authorization. |
| `commerce.salla.reauthorized` | A connected store received new tokens from Salla (app update or reinstall). |
| `commerce.salla.token_refreshed` | A refresh succeeded; only expiry times are recorded. |
| `commerce.salla.needs_reauth` | The token manager could not keep a usable token; only a reason code is recorded. |
| `commerce.salla.disconnected` | Salla reported the app as uninstalled. An administrator's own disconnect stays `commerce.store_disconnected`. |

## Not yet verified against a live Salla store

`REAL_SALLA_UAT = BLOCKED` (doc 13). These points follow Salla's documentation and official kit, but no live store has
confirmed them:

- The refresh response carries `expires` as a Unix timestamp; the kit's own refresh code reads `data.expires`.
  `Commerce::Salla::Tokens` also accepts `expires_in` (seconds), which standard OAuth servers return.
- The refresh response may leave out `scope` when it is unchanged (RFC 6749 §5.1). The previous scope is then kept.
- `invalid_client` is returned with HTTP 401, as RFC 6749 §5.2 describes.
