# Security backlog after the Chatwoot 4.18.0 upgrade (Phase 14)

Each item was checked on the upgraded code, not assumed.

- **Code:** `file:line` at the merged tree.
- **Tests:** the new specs and the staging harness.
- **Policy:** none of the open items was changed in this upgrade, following "don't change production behaviour without tests". Every open item has a proposed fix below. Each fix needs its own decision and regression test.

## A. The four findings from the 4.14.1 review

| # | Finding (4.14.1) | Status on 4.18 | Evidence |
|---|---|---|---|
| 1 | Agent can create or re-authorize a WhatsApp inbox through the API | **FIXED** (re-authorize by 4.18, create in Phase 4 commit C) | See below |
| 2 | WhatsApp token reaches the browser | **FIXED in Phase 4 (commit B)** for the browser. **Encryption at rest: OPEN, production blocker** | See below |
| 3 | `WHATSAPP_APP_SECRET` not defined as a secret | **FIXED in Phase 4 (commit B)** | See below |
| 4 | Deleting an inbox can unsubscribe the whole WABA's webhooks | **FIXED BY 4.18** | See below |

### 1. Agent can create or re-authorize a WhatsApp inbox

- **Re-authorize / reconfigure is now admin-only.** `before_action :check_admin_authorization?, if: -> { params[:inbox_id].present? }` (`app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb`).
  - Verified: an agent gets 401 (`coexistence_onboarding_spec.rb` "does not let an agent reauthorize it", and the staging harness).
- **Creating a new inbox now requires an administrator (Phase 4, commit C).**
  - Before, any account member, including agents, could create one through `POST /whatsapp/authorization`. Upstream's own spec asserted that.
  - Now `AuthorizationsController` runs `authorize ::Inbox, :create?` (the existing `InboxPolicy`, as `InboxesController#create` and manual setup v2 already do) when there is no `inbox_id`.
  - This covers both Embedded Signup and WhatsApp Business (Coexistence), because they share the endpoint.
  - Conversation permissions are untouched.
- **Tests** (`spec/controllers/api/v1/accounts/whatsapp/`, 36 examples, 0 failures):

  | Caller | Create (Embedded Signup) | Create (WhatsApp Business) | Re-authorize |
  |---|---|---|---|
  | administrator of the account | allowed | allowed | allowed |
  | agent of the account | **401** (new) | **401** (new) | 401 |
  | administrator of another account | 401 | 401 | 404 |
  | unauthenticated | 401 | 401 | 401 |

  - The two new agent examples fail on the previous code.
  - Upstream's creation examples now run as an administrator.

### 2. WhatsApp token reaches the browser

**Before:** administrators received the full `provider_config`, including `api_key` (the Meta access token), `verification_pin` and any app secret. The manual-inbox settings page displayed the token.

**After (commit B):**
- `_inbox.json.jbuilder` sends administrators `provider_config` without `Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS` (`api_key verification_pin app_secret app_secret_key client_secret api_secret`).
  - `webhook_verify_token`, `phone_number_id`, `business_account_id`, `source` and the calling flags stay, because the settings screens use them.
  - `webhook_verify_token` only authorizes Meta's GET handshake, and admins must paste it into their Meta app.
- Agents still get no `provider_config` at all.
- `PATCH /inboxes/:id` (the only write path the dashboard uses):
  - a `provider_config` without a credential key keeps the stored value (`Channel::Whatsapp#with_stored_credentials`);
  - sending the key replaces it.
  - So these keep working: calling settings, "Update API Key", the embedded signup → manual transfer, and API clients that send the full config.
- `ConfigurationPage.vue` no longer shows the key. The "Update API Key" field is unchanged.
- **Tests:**
  - `spec/controllers/api/v1/accounts/inboxes_whatsapp_credentials_spec.rb`: 6 examples. 3 of them fail on the previous code.
  - `ConfigurationPage.spec.js`: 2 new tests.
  - Upstream inbox specs, CE + EE: 143 examples, 0 failures.

**Still open: encryption at rest (production blocker, needs a decision).**
- `provider_config.api_key` is plain text inside a `jsonb` column.
- Rails' existing `encrypts` (already used for `business_management_token`, Facebook/Line/Twitter tokens) cannot encrypt one key of a `jsonb` column.
- Encrypting the whole column would break the SQL lookups on `provider_config->>'business_account_id'` and `phone_number_id` (WABA teardown, webhook routing).
- The fix therefore needs all of the following, each rehearsed against the 41/41 regression:
  1. a new `encrypts :access_token` text column;
  2. a backfill job that reads the plain value and writes the encrypted one, without logging values;
  3. switching the 19 `provider_config['api_key']` reads in `app/` and `enterprise/` to it;
  4. removing the plain key only after verification (reversible until then).
- That is wider than a hardening commit and changes the existing WhatsApp API code paths, so it is left for a dedicated change.

### 3. `WHATSAPP_APP_SECRET` not defined as a secret

**Before:**
- `config/installation_config.yml` had no `type: secret` for it.
- Super Admin → App configs → WhatsApp Embedded showed it in clear text.
- The generic Super Admin → Installation configs page (not in the menu, reachable by URL) listed its value.

**After (commit B):**
- It is `type: secret`, the existing mechanism (like `FB_APP_SECRET`).
- **Every** `type: secret` config is now write-only in Super Admin:
  - the App configs page renders an empty password field (placeholder `••••••••` when set) and never sends the stored value to the browser;
  - a blank submission keeps the stored value, and a new value replaces it;
  - the generic Installation configs list excludes secret configs. With the Enterprise overlay on a paid pricing plan, every one of them has an App configs page. On the community plan, the internal/Captain/Langfuse/Cloudflare secrets have none and are set through ENV or the console. They are not used by Lynomia today.
- **Logs:** the existing `filter_parameters` (`:secret`, `_key`, `token`) already redact it in request logs.
- **Frontend state:** it was never in `window.globalConfig`. `DashboardController` exposes `WHATSAPP_APP_ID` and `WHATSAPP_CONFIGURATION_ID` only.
- **Runtime use unchanged:** token exchange and webhook signature still read `GlobalConfigService.load('WHATSAPP_APP_SECRET')`.
- **Behaviour change for operators:** a stored secret or verify token can no longer be read back in Super Admin. To change one, enter a new value. To clear one, use the Rails console.
- **Tests:** `spec/controllers/super_admin/whatsapp_app_secret_spec.rb` has 6 examples: masked, not rendered, blank keeps, new value replaces, not listed, filtered from logs. The existing Super Admin specs pass.

### 4. Deleting an inbox can unsubscribe the whole WABA

- `Whatsapp::WebhookTeardownService#unsubscribe_app_if_last_inbox` unsubscribes the app from the WABA **only when no other channel uses that WABA**, checked installation-wide (`app/services/whatsapp/webhook_teardown_service.rb:55-74`).
- Deletion also clears the number's own callback override and, for embedded-signup numbers, calls `/deregister`.
- Meta refuses `/deregister` for Business-App (Coexistence) numbers. The error is logged and swallowed, so deletion still succeeds.
- Verified on staging: deleting a WhatsApp Business inbox did not unsubscribe other tenants' WABAs.

## B. New findings during the upgrade review

| # | Finding | Severity | Status | Evidence / proposed fix |
|---|---|---|---|---|
| 5 | **Unsigned webhooks were accepted for manual Cloud API numbers.** Anyone who knew the number and its `phone_number_id` could inject inbound messages into that inbox. | High | **FIXED in Phase 4 (commit A)** | Every `whatsapp_cloud` number now needs a valid `X-Hub-Signature-256`, checked against the channel's app secret or `WHATSAPP_APP_SECRET`. Before production, manual numbers subscribed through a customer's own Meta app need that app's secret on the channel. Audit, evidence and rollout: `WEBHOOK-SIGNATURE.md`. 360dialog numbers are not Meta-signed and stay URL-protected only. |
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
