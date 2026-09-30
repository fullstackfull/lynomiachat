# 10 — Salla: tying an installation to a Lynomia account

Phase 3 connects Salla stores through the published Lynomia Salla app. This page records how the app decides which
Lynomia account a Salla installation belongs to. That decision is the security boundary between tenants.

## The problem

The Lynomia app uses Salla's **Easy Mode**, the authorization mode Salla expects for published apps. Salla's own
agent kit (SallaApp/salla-partners-agent-kit, `salla-app-auth/SKILL.md`) says:

> Publishing the app? → default to Easy Mode. Tokens arrive in the `app.store.authorize` webhook … you don't need an
> OAuth /callback or state handling.

> "I know OAuth — I'll just build the `/callback` flow." That's Custom Mode. Shipping it in a published app without a
> justified use case can be **rejected at review**.

So the merchant installs the app from Salla, and Salla sends the tokens to our webhook as
`{ "event": "app.store.authorize", "merchant": <id>, "data": { access_token, refresh_token, expires, scope, token_type } }`.
Nothing in that event, and no redirect, carries anything that Lynomia issued. **An authorization alone cannot say which
Lynomia account it is for.**

These are never used, because none of them proves anything:

- the account that most recently started a connection;
- IP addresses, or browser timestamps alone;
- the store name or domain;
- the authorizing user's email (it can be any staff member, and the address can match unrelated accounts);
- any other heuristic.

## The solution: a one-time code the merchant enters in the app's settings

Salla apps can define a **settings form** that the merchant fills in the Salla dashboard. When the merchant saves it,
Salla sends `app.settings.updated` for that merchant to the app's webhook, signed like every other event (kit:
`salla-app-settings`, `salla-app-lifecycle/references/lifecycle-payloads.md`). Receiving it needs no API scope.

1. **Lynomia side.** An account administrator opens *Settings → Commerce → Add store → Salla* and clicks
   *Connect with Salla*. Lynomia creates a one-time **connection code** (`Commerce::Salla::ConnectionCode`):
   - 16 symbols from a 32-symbol alphabet (80 random bits), shown as `ABCD-EFGH-JKLM-NPQR`;
   - bound to that account and that administrator;
   - valid for one hour and for one use;
   - shown once. Only its HMAC is stored, in Redis.
   A new code replaces the account's previous one.
2. **Salla side.** The administrator installs the app with the official link `https://s.salla.sa/apps/install/<App ID>`
   and pastes the code into the app's settings field `lynomia_connection_code` in the Salla dashboard.
3. Salla delivers two signed events, in either order:
   - `app.store.authorize` carries the tokens;
   - `app.settings.updated` carries the code.
4. `Commerce::Salla::Installation` matches them for that merchant, then connects the store to the account the code
   was issued for. The merchant is the event's `merchant`, and it is confirmed against `merchant.id` from
   `GET https://accounts.salla.sa/oauth2/user/info` called with the new token.

This proves both sides:

| Claim | Proof |
| --- | --- |
| The Lynomia account wants this store | Only an administrator of the account can create the code. The code is random, single-use and expires in one hour, and it is shown only to that administrator. |
| The Salla store agrees to be this account's | Only someone signed in to the merchant's Salla dashboard, with permission to manage its apps, can save the settings of that store's installation. Salla sends the saved code signed with our app's webhook secret, and the event names the merchant. |
| The tokens are this store's | They arrive in a signed `app.store.authorize` for the same merchant, and `user/info` with those tokens returns the same `merchant.id`. |

### Event order and waiting state

Both halves wait for each other under the merchant's lock (`Commerce::StoreLock`, the same lock token
refreshes use):

| Arrives first | Kept until the other arrives | Where | TTL |
| --- | --- | --- | --- |
| `app.store.authorize` | tokens, merchant identity | `Redis::SecureStorage` (AES-256-GCM): `COMMERCE::SALLA::MERCHANT::<id>::TOKENS` | 7 days |
| `app.settings.updated` | `{ account_id, user_id }` of the redeemed code | `COMMERCE::SALLA::MERCHANT::<id>::CLAIM` | 7 days |

When both are present:

1. The store is saved through `Commerce::StoreConnection#attach`, the same ownership rules WooCommerce uses.
   `external_store_id` is Salla's merchant id, and the credentials are encrypted in `commerce_stores.credentials`.
2. The waiting state is deleted.
3. The account's progress becomes `connected`.

The settings page polls `GET /api/v1/accounts/:id/commerce/salla_connection`. It reports
`none | waiting | expired | claimed | connected | conflict` and never returns the code or any token.

### Ownership rules

| Situation | Result |
| --- | --- |
| Merchant has no store in Lynomia | Connected only when both halves are present. An authorization alone never creates a store. |
| Store connected (active, disabled, needs re-authorization) in the same account, and a new authorization arrives | Credentials replaced atomically under the lock. A `needs_reauth` store becomes active; a store an administrator disabled stays disabled. Audit `commerce.salla.reauthorized`. No new row. |
| Store connected to **another** account, and a code arrives | **Conflict.** The store is not moved, the claiming account's progress becomes `conflict`, and the store keeps working for its owner. A later authorization still updates the owner's store. |
| Store disconnected in the same account | A new code and a new authorization reconnect it, reusing its row. |
| Store disconnected by another account | Released: the claiming account gets it, which is the same rule WooCommerce stores follow. |
| Duplicate deliveries | Byte-identical redeliveries are queued once (SHA-256 of the raw body, 3 days). A repeated authorization for a connected store only rewrites the same credentials. A used code is gone, so a repeated settings event does nothing. |

### App uninstalled

`app.uninstalled` disconnects the store: credentials are deleted, customer links are removed (the existing Commerce
policy), and cached store data is purged. Audit `commerce.salla.disconnected`. Contacts and conversations are never
touched. Waiting tokens and claims for the merchant are deleted too.

### Salla switched off (Super Admin)

- New installations and codes are ignored, and Salla is not called.
- Stores that are already connected still take new tokens, so they don't end up on dead tokens.
- Uninstalls are still processed.

## Threats considered

| Threat | Why it fails |
| --- | --- |
| Forged event (someone posts to `/webhooks/salla`) | Every delivery must carry `X-Salla-Security-Strategy: Signature` and `X-Salla-Signature`, the hex HMAC-SHA256 of the raw body under the app's webhook secret, compared in constant time before anything is parsed. No secret configured means everything is refused. See doc 12. |
| Guessing a code from another Salla store | An attempt means saving settings in a Salla store that has the app installed. The space is 2^80 and each code lives one hour. |
| Replaying a used code | Codes are deleted as they are read (Redis `MULTI GET DEL`). |
| A leaked code | It works once, for one hour, and connects the store to the account that issued it. It gives no access to that account. |
| Taking over a connected store | A store connected to an account is never moved (conflict). It can change hands only after it is disconnected. |
| Tokens with more power than read-only | Tokens are refused, and not stored, if their scope has anything other than `offline_access` and `*.read`, or lacks a required scope. See doc 11. |
| Tokens of another store in the event | `user/info` must return the event's merchant id, or nothing is stored. |
| Tokens at rest in Redis/Sidekiq | Waiting tokens use `Redis::SecureStorage`. Queued events are encrypted (`ActiveSupport::MessageEncryptor`, AES-256-GCM); Sidekiq arguments are never plaintext. |

## Salla Partners setup this relies on

- App type: public app, Easy Mode.
- Webhook URL: `https://<lynomia host>/webhooks/salla`, security strategy **Signature**. Copy the secret into Super
  Admin → Settings → Salla → Webhook Secret.
- Scopes: see doc 11.
- App settings form, one field:

```json
{
  "id": "lynomia_connection_code",
  "type": "string",
  "format": "password",
  "label": "رمز الربط من Lynomia",
  "description": "أنشئ الرمز من Lynomia: الإعدادات ← المتاجر ← إضافة متجر ← سلة، ثم الصقه هنا.",
  "required": false,
  "public": false,
  "value": "",
  "maxLength": 32
}
```

## Limitations

- Disconnecting a Salla store in Lynomia deletes its tokens. To connect it again, the merchant must authorize the app
  again, by updating it or reinstalling it in Salla, and enter a new code. The settings page says so.
- A code must be entered within one hour, and an authorization waits 7 days for a code. After that, the merchant
  reinstalls the app.
- If two accounts' codes are entered one after the other before any authorization, the later one wins. The earlier
  account's progress stays `claimed` until it expires.
- **Not yet verified against a live Salla store** (`REAL_SALLA_UAT = BLOCKED`, doc 13): that saving the settings form
  on an installed app sends `app.settings.updated` with the field's `id` as its key, and the exact shape of `domain` in
  `user/info` for stores without a custom domain.
