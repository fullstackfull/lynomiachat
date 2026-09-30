# Security backlog after the Chatwoot 4.18.0 upgrade (Phase 14)

Each item was checked on the upgraded code, not assumed.

- **Code:** `file:line` at the merged tree.
- **Tests:** the new specs and the staging harness.
- **Policy:** none of the open items was changed in this upgrade, following "don't change production behaviour without tests". Every open item has a proposed fix below. Each fix needs its own decision and regression test.

## A. The four findings from the 4.14.1 review

| # | Finding (4.14.1) | Status on 4.18 | Evidence |
|---|---|---|---|
| 1 | Agent can create or re-authorize a WhatsApp inbox through the API | **PARTIALLY FIXED BY 4.18** | See below |
| 2 | WhatsApp token reaches the browser | **STILL PRESENT** (admins only) | See below |
| 3 | `WHATSAPP_APP_SECRET` not defined as a secret | **STILL PRESENT** | See below |
| 4 | Deleting an inbox can unsubscribe the whole WABA's webhooks | **FIXED BY 4.18** | See below |

### 1. Agent can create or re-authorize a WhatsApp inbox

- **Re-authorize / reconfigure is now admin-only.** `before_action :check_admin_authorization?, if: -> { params[:inbox_id].present? }` (`app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb:4`).
  - Verified: an agent gets 401 (`coexistence_onboarding_spec.rb` "does not let an agent reauthorize it", and the staging harness).
- **Creating a new inbox is still allowed for any account member, including agents.**
  - Upstream's own spec asserts it: `spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb` posts with `agent.create_new_auth_token` and expects success.
  - The dashboard route to add inboxes is admin-only, so this is an API-level gap inside the agent's own account. It is not cross-tenant.
- **Proposed fix:** in `AuthorizationsController`, `authorize ::Inbox, :create?` for creation, as upstream's manual setup v2 already does (`manual_setup_controller.rb:39-41`). Add a request spec where an agent gets 401. This changes an upstream spec expectation, so it belongs in its own reviewed change.

### 2. WhatsApp token reaches the browser

- **Administrators** still receive the full `provider_config`: `api_key`, `webhook_verify_token`, `verification_pin` (`app/views/api/v1/models/_inbox.json.jbuilder:147`).
- **Agents do not** (verified: `coexistence_onboarding_spec.rb` "never returns the token to agents").
- **At rest,** `provider_config.api_key` is still plain jsonb. 4.18 only adds `encrypts :business_management_token` (`app/models/channel/whatsapp.rb:31`, Chatwoot Cloud only).
- **Proposed fix:**
  1. Serialize `provider_config` without secrets (mask `api_key`, `verification_pin`) and adapt `ConfigurationPage.vue`, which shows the key for manual inboxes.
  2. Separately, move the token to an encrypted attribute with a data migration and a rollback path. That touches every existing number, so it needs its own staging rehearsal.

### 3. `WHATSAPP_APP_SECRET` not defined as a secret

- `config/installation_config.yml:162-165` has no `type: secret`. Compare `FB_APP_SECRET` at `:131-134`.
- As a result, Super Admin → App configs → WhatsApp Embedded shows the App Secret in clear text (`app/views/super_admin/app_configs/show.html.erb:38` masks only `type == 'secret'`).
- **Proposed fix:** add `type: secret` (one line) and check the Super Admin form still saves the value.

### 4. Deleting an inbox can unsubscribe the whole WABA

- `Whatsapp::WebhookTeardownService#unsubscribe_app_if_last_inbox` unsubscribes the app from the WABA **only when no other channel uses that WABA**, checked installation-wide (`app/services/whatsapp/webhook_teardown_service.rb:55-74`).
- Deletion also clears the number's own callback override and, for embedded-signup numbers, calls `/deregister`.
- Meta refuses `/deregister` for Business-App (Coexistence) numbers. The error is logged and swallowed, so deletion still succeeds.
- Verified on staging: deleting a WhatsApp Business inbox did not unsubscribe other tenants' WABAs.

## B. New findings during the upgrade review

| # | Finding | Severity | Status | Evidence / proposed fix |
|---|---|---|---|---|
| 5 | **Unsigned webhooks are accepted for manual Cloud API numbers.** Anyone who knows the number and its `phone_number_id` can inject inbound messages into that inbox. | High | STILL PRESENT (pre-existing: identical in 4.14.1 and 4.18.0) | `meta_signature_verification_required?` returns false for `whatsapp_cloud` channels that are not `embedded_signup` and have no app-secret key in `provider_config` (`app/controllers/webhooks/whatsapp_controller.rb:45-51`). **Staging:** unsigned POST to the manual number → **200, message created**; to the Embedded Signup number → 401. Embedded Signup and WhatsApp Business numbers **are** protected. **Fix:** manual numbers use the customer's own Meta app, whose secret Lynomia does not know. Let admins store `app_secret` in the manual inbox settings; `MetaTokenVerifyConcern#provider_config_meta_app_secrets` already enforces it when present. Then make it mandatory for new manual inboxes. |
| 6 | No rate limit on the Lynomia endpoints `/api/v1/mobile/auth/{google,apple}` and `/billing/webhooks/stripe` | Medium | pre-existing | `config/initializers/rack_attack.rb` has no rule for them. **Fix:** add throttles like upstream's `/auth/sign_in` rule. The Stripe webhook is already signature-verified. |
| 7 | Mobile sign-in sessions were invisible to 4.18's session management | Medium | **FIXED in this upgrade** (commit 4) | `custom/app/controllers/api/v1/mobile/auth_controller.rb` now calls `UserSessionTrackingService`, so sessions appear in Profile → Active sessions and can be revoked. Spec: `spec/controllers/api/v1/mobile/auth_controller_spec.rb`. |
| 8 | Long WhatsApp health errors could block later channel saves (upstream 4.18 bug) | Low (availability) | **FIXED in this upgrade** (commit 4) | `phone_number_health_error` is a 500-char column, but the generic 255-char `ApplicationRecord` check rejected it. A 300-char error made the channel invalid (re-auth and settings saves failed). Added the matching length validation; spec in `spec/models/channel/whatsapp_spec.rb`. |

## C. Improvements brought by 4.18 (for the record)

- Two private advisories:
  - `7d581dc8c`: MFA, SAML and session-limit bypass via credentials sent in headers;
  - `aad2791b4`: macro execution IDOR.
- About 35 hardening fixes: XSS, SSRF via SafeFetch, tenant scoping, admin-only mutations, integration secrets redacted, widget HMAC, CSV injection, `httponly` session cookie. See `../chatwoot-upgrade/01-upstream-diff.md` §2.
- Rails 7.2.3.1 and patched gems close the CVEs 4.14.1 had to ignore.
- WhatsApp re-auth is admin-only, and whole-WABA teardown is fixed (items 1 and 4).

## D. Stop-condition check

- **Tenant isolation is not weaker.** Cross-tenant create, re-authorize, read and modify are all refused. Mismatched-number webhooks are not routed to any tenant.
- **No new token exposure.** Agents never receive tokens. The App Secret stays server-side: the token exchange happens in the backend.
