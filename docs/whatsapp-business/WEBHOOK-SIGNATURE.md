# Meta webhook signature: audit and enforcement (Phase 4, commit A)

## 1. Meta's contract

- Meta signs every webhook **POST** with `X-Hub-Signature-256: sha256=<hex>`.
  - The value is the HMAC-SHA256 of the **raw request body**.
  - The key is the **App Secret of the Meta app that owns the webhook subscription**.
- The **GET** subscription handshake (`hub.mode`, `hub.verify_token`, `hub.challenge`) is not signed. It is checked with the verify token only.
- For WhatsApp Cloud API the same rule applies to every number, whatever the onboarding path:
  - Embedded Signup;
  - WhatsApp Business (Coexistence);
  - manual token setup.

  Only the app whose secret signs the webhook changes.

## 2. Endpoint audit

| Endpoint | Sender | Before (4.18 upstream) | After (commit A) |
|---|---|---|---|
| `POST /webhooks/whatsapp/:phone_number`, Embedded Signup number | Meta (Lynomia app) | verified | verified (unchanged) |
| same, WhatsApp Business / Coexistence number | Meta (Lynomia app) | verified | verified (unchanged) |
| same, manual Cloud API number with `provider_config.app_secret` | Meta (customer app) | verified | verified (unchanged) |
| same, **manual Cloud API number without an app secret** (legacy, or `manual_setup_v2`) | Meta | **not verified**: unsigned and forged POSTs were accepted | **verified**, against `WHATSAPP_APP_SECRET` or the channel's app secret |
| same, number not connected to any inbox | n/a | verified | verified (unchanged) |
| same, 360dialog (`provider: default`) | 360dialog, not Meta | not verified | not verified (not Meta-originated; see §5) |
| `GET /webhooks/whatsapp/:phone_number` | Meta handshake | per-channel `webhook_verify_token` | unchanged |
| `POST /webhooks/instagram` | Meta | always verified (channel, `INSTAGRAM_APP_SECRET`, `FB_APP_SECRET`) | unchanged |
| `POST /bot` (Messenger) | Meta | verified by the `facebook-messenger` gem: `X-Hub-Signature` HMAC-SHA1 with the page's or `FB_APP_SECRET` | unchanged |

- Embedded Signup and Coexistence completion do not go through a webhook. The browser posts the `code` to the authenticated `POST /api/v1/accounts/:id/whatsapp/authorization`, and the token exchange happens server-side.

### Why upstream exempted manual numbers

- A manual number can be subscribed through the customer's **own** Meta app.
- Chatwoot does not ask for that app's secret, so it cannot verify those webhooks with `WHATSAPP_APP_SECRET`.
- Upstream therefore enforced the signature only where it knew the secret: Embedded Signup numbers, or a channel with an app-secret key in `provider_config`.
- As a result, anyone who knows a manual number and its `phone_number_id` could inject inbound messages. The staging probe proved it: an unsigned POST returned 200 and created a message.

## 3. What changed

- `Webhooks::WhatsappController#meta_signature_verification_required?` now requires a valid signature for every `whatsapp_cloud` channel, and for unknown numbers. 360dialog is the only exception.
- Accepted secrets are unchanged:
  - the channel's `provider_config` `app_secret` / `app_secret_key` / `client_secret` / `api_secret`;
  - then the global `WHATSAPP_APP_SECRET`.
- The check fails closed:
  - missing header → 401;
  - wrong prefix or wrong HMAC → 401;
  - no secret configured → 401.
- The comparison is constant-time (`ActiveSupport::SecurityUtils.secure_compare`) over `request.raw_post`. This is unchanged.
- A rejection is logged once, with neither the secret nor the signature:

  ```text
  Rejected Meta webhook with invalid X-Hub-Signature-256: /webhooks/whatsapp/+15550001001
  Rejected Meta webhook with missing X-Hub-Signature-256: /webhooks/whatsapp/+15550001001
  ```

- The GET verification challenge is untouched.

## 4. Evidence

- **`spec/controllers/webhooks/whatsapp_signature_enforcement_spec.rb`:** 32 examples, run on Ruby 3.4.4.
  - Five kinds of number: legacy manual (no `source`), `manual_setup_v2`, manual on its own Meta app, Embedded Signup, WhatsApp Business (Coexistence).
  - For each:
    - valid → 200 and job enqueued;
    - missing → 401;
    - invalid → 401;
    - body modified after signing → 401;
    - signed with another secret → 401;
    - GET challenge → 200.
  - Also: no secret configured on the server → 401; the rejection log contains neither the secret nor the signature.
  - Against the previous controller, the 10 manual-number rejection examples fail. So the spec detects the gap.
- **`spec/controllers/webhooks/`:** 89 examples, 0 failures. Upstream's "skips signature validation for manual…" example now expects 401.
- **Staging** (`lynomia_staging_p4`, the pre-upgrade dump migrated to this tree):
  - existing WhatsApp API regression **41/41**;
  - the unsigned-manual probe now returns **401, no message created** (before: 200, message created).

## 5. Rollout requirements (before production)

1. **Inventory the manual Cloud API numbers.** This query does not select any secret:

   ```sql
   SELECT id, account_id, phone_number, provider_config->>'source' AS source,
          (provider_config ?| array['app_secret','app_secret_key','client_secret','api_secret']) AS has_channel_app_secret
   FROM channel_whatsapp
   WHERE provider = 'whatsapp_cloud' AND coalesce(provider_config->>'source', '') <> 'embedded_signup';
   ```

2. For each row, confirm which Meta app delivers its webhooks:
   - **Lynomia's app** (the one whose secret is `WHATSAPP_APP_SECRET`): nothing to do.
   - **The customer's own app:** store that app's secret on the channel before deploying.

     ```bash
     # Pass the secret through the environment so it is not in shell history or logs.
     read -rs APP_SECRET && export APP_SECRET
     CHANNEL_ID=<id> bundle exec rails runner '
       c = Channel::Whatsapp.find(ENV.fetch("CHANNEL_ID"))
       c.update!(provider_config: c.provider_config.merge("app_secret" => ENV.fetch("APP_SECRET")))'
     unset APP_SECRET
     ```

3. **360dialog:** run `SELECT count(*) FROM channel_whatsapp WHERE provider = 'default';`.
   - If the result is not 0, those numbers stay protected only by the webhook URL (residual risk; `SECURITY-BACKLOG.md`).
4. **After the deploy:** watch the logs for `Rejected Meta webhook with invalid X-Hub-Signature-256: /webhooks/whatsapp/...`.
   - It names the number whose app secret is missing or wrong. Fix it with step 2.
   - Meta retries webhooks that did not get a 200 (Meta documents retries for up to 7 days), so messages delivered during that window are redelivered once the secret is fixed. To be confirmed during the real UAT (`META-VERIFICATION.md`).
5. **Rollback:** `git revert <commit A>` restores the upstream behaviour. No data change is involved.
