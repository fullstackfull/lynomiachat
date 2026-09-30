# Chatwoot 4.14.1 → 4.18.0: Phase 2 upstream change map

**Range:** `v4.14.1` (`d58b6a6c`) → `v4.18.0` (`9f920b54`)

- **Commits:** 611 (593 non-merge).
- **Files:** 3,954. Of these, 1,618 are locale files.
- **Lines:** +259,534 / −30,982.
- **WhatsApp-related:** 82 non-merge commits touch WhatsApp, Embedded Signup, Coexistence or BSUID.

Detailed evidence, with every `file:line` and commit/PR number:
- `appendix/A-upstream-whatsapp-analysis.md`: all WhatsApp areas.
- `appendix/B-upstream-core-analysis.md`: everything else.

This page is the classified summary.

**Classes**

- **SAFE AUTO-MERGE:** an upstream-only file, or a change with no interaction with Lynomia code.
- **REQUIRES MANUAL MERGE:** merges textually, but needs a decision, config, ops step or QA.
- **CONFLICTS WITH LYNOMIA:** a textual or semantic collision with a Lynomia customization (resolved in `03-conflict-resolution.md`).
- **NOT RELEVANT:** Chatwoot Cloud only, or a feature that is off / unused by Lynomia.

---

## 1. WhatsApp, Embedded Signup, Coexistence

| Change | Evidence (v4.18.0) | Class |
|---|---|---|
| **Coexistence support.** The frontend classifies `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` and sends `is_coexistence`. The backend accepts a completion with **only `waba_id`**, skips `/register` and skips the post-signup health check. | `whatsapp/utils.js:38-40,70-75`; `useWhatsappEmbeddedSignup.js:55,62-75`; `authorizations_controller.rb:33,81`; `embedded_signup_service.rb:8,22,25`; `webhook_setup_service.rb:33-38` | SAFE AUTO-MERGE (Lynomia builds its "WhatsApp Business" option on it; see `05-whatsapp-business.md`) |
| `business_id` no longer required anywhere (controller, service, frontend) | `authorizations_controller.rb:76-83`; `embedded_signup_service.rb:92-99`; `utils.js:32-36` | SAFE AUTO-MERGE |
| **Coexistence is not stored on the channel.** `ChannelCreationService#build_provider_config` is unchanged; there is no new key or column. Meta's `is_on_biz_app` appears in the new `phone_number_health` jsonb. | `channel_creation_service.rb:50-57`; `health_service.rb:32,184-195` | SAFE (Lynomia adds a marker: `05-whatsapp-business.md`) |
| `PhoneInfoService` is strict: no `phone_numbers.first` fallback. A multi-number WABA without `phone_number_id` raises. | `phone_info_service.rb:36-58` | SAFE AUTO-MERGE |
| Re-auth writes `waba_id` into `business_account_id` (4.14 wrote the business portfolio id) | `reauthorization_service.rb:31-37` | SAFE AUTO-MERGE |
| Re-auth / reconfigure is **admin-only** (`inbox_id` present). New-inbox creation still has **no role check**. | `authorizations_controller.rb:2-5` | SAFE (security follow-up: `SECURITY-BACKLOG.md`) |
| `TokenValidationService` (`debug_token` WABA-scope check) deleted | `f93f2067b` (#14697) | SAFE AUTO-MERGE |
| Webhook channel lookup via `WebhookChannelFinderService` (`+digits`, then BR/AR/MX normalization, and `phone_number_id` must match) | `webhook_channel_finder_service.rb:12-20` | SAFE AUTO-MERGE |
| Webhook signature verification unchanged. Embedded-signup channels always require `X-Hub-Signature-256`. | `meta_token_verify_concern.rb` (no diff); `whatsapp_controller.rb:45-51` | SAFE AUTO-MERGE |
| Tracking-only webhooks return 200 without a job | `whatsapp_controller.rb:13,21-26` | SAFE AUTO-MERGE |
| Re-auth flag drops webhooks **only for embedded-signup** channels (4.14 dropped them for every channel) | `whatsapp_events_job.rb:148-159` | SAFE AUTO-MERGE (improves manual API numbers) |
| **Message echoes** (`smb_message_echoes`): same mechanism. Contact is now resolved through the BSUID too. Dedupe is unchanged (global `source_id` plus a Redis `MessageDedupLock`). | `whatsapp_events_job.rb:80-86`; `incoming_message_base_service.rb:164-179` | SAFE AUTO-MERGE |
| **History sync (`history`) and contact sync (`smb_app_state_sync`): not implemented upstream.** No subscription, no handler, no flag. | `facebook_api_client.rb:4` (`WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes]`) | NOT RELEVANT (stays OFF, per Phase 16) |
| BSUID / LID: `recipient` instead of `to` for business-scoped ids; identity ordering; `UserIdRotationService` (number / user-id changes); BSUID contacts become `lead`; contact-info request | `providers/base_service.rb:57-69`; `identity_source_id_orderer.rb`; `user_id_rotation_service.rb` | SAFE AUTO-MERGE |
| **Media is sent by upload + `media_id`** (falls back to `link`). `WHATSAPP_MEDIA_UPLOAD_STRATEGY=link` restores the old behaviour. | `providers/whatsapp_cloud_service.rb:188-195`; `media_upload_service.rb` (#15702) | REQUIRES MANUAL MERGE (ops note; tested in regression) |
| Sending outside the 24h window without a template fails immediately (only the error changes) | `send_on_whatsapp_service.rb:8-20` (#15113) | SAFE AUTO-MERGE |
| Template sync uses a Bearer header and paging, and skips suspended accounts. `validate_provider_config?` also checks that `phone_number_id` belongs to the WABA. | `whatsapp_cloud_service.rb:35-76` | SAFE AUTO-MERGE |
| **Health polling** (new hourly scheduler; every channel checked at least every 6h, Graph ≥ v24.0) | `health_sync_scheduler_job.rb`; `health_service.rb:18,46-47` | REQUIRES MANUAL MERGE (ops: new Graph traffic) |
| Webhook override moves to the **phone-number level** (`POST /{phone_number_id} webhook_configuration`). Old WABA-level overrides stay until setup re-runs. | `facebook_api_client.rb:144-176` (#13817) | SAFE (ops note) |
| `calls` webhook field subscribed only when calling is enabled | `webhook_setup_service.rb:84-103` | SAFE AUTO-MERGE |
| **Teardown on inbox delete:** clears the phone override; deregisters embedded-signup numbers; unsubscribes the app from the WABA **only if no other channel uses that WABA** (4.14 always unsubscribed the whole WABA) | `webhook_teardown_service.rb:6-17,55-74` | SAFE AUTO-MERGE (fixes a 4.14 bug; `/deregister` on Coexistence numbers is **VERIFY-META**) |
| New manual setup v2 (`source: 'manual_setup_v2'`, names inboxes "`<name> WhatsApp`") | `manual_setup_*`; `manual_setup_validation_service.rb:96` | REQUIRES MANUAL MERGE (naming differs from Lynomia's phone-number naming; kept as upstream) |
| Business management token (column `business_management_token`, `encrypts` when AR encryption keys exist) | `channel/whatsapp.rb:31,79-87` | NOT RELEVANT (Chatwoot Cloud only; stays nil) |
| `DISABLE_META_INBOX_CREATION` (default true), `whatsapp_embedded_signup_inbox_creation` flag, access request | `authorizations_controller.rb:22-28`; `globalConfig.js` | NOT RELEVANT (only when `DEPLOYMENT_ENV=cloud`) |
| `app/services/whatsapp/channel_creation_service.rb` | upstream byte-identical 4.14.1 ↔ 4.18.0 | SAFE (Lynomia inbox naming kept) |
| `spec/services/whatsapp/channel_creation_service_spec.rb` | upstream adds a "no orphan channel" example | REQUIRES MANUAL MERGE (review only; clean merge) |
| `ReauthorizationService` renames the inbox to the business name on re-auth | `reauthorization_service.rb:42-44` (unchanged since 4.14.1) | CONFLICTS WITH LYNOMIA naming (pre-existing; not changed, listed in known limitations) |

## 2. Security

| Change | Class |
|---|---|
| **GHSA** `7d581dc8c`: MFA, SAML guard and session limit could be bypassed by sending credentials in headers | SAFE AUTO-MERGE |
| **GHSA** `aad2791b4`: macro execution IDOR (per-conversation authorization) | SAFE AUTO-MERGE |
| ~35 hardening fixes. XSS: #14050 (including Lynomia's `Signup/Form.vue` terms link), #15525. SSRF: #15466, #15463, #14693, #14620. Slack signature: #15480. Tenant scoping: #15521, #15207, #15180, #15191/#15229, #15249, #15386. Admin-only mutations: #14831, #15126. Bot tokens hidden: #14830. Integration secrets redacted: #14147. Widget HMAC: #14884, #14945. CSV injection: #15334, #15335. Cookie `httponly`/`secure`: #14248 | SAFE AUTO-MERGE |
| Bare `/rails/active_storage/direct_uploads` → 403 (#15329) | REQUIRES MANUAL MERGE (the mobile app must not use it; see `04-regression-report.md`) |
| Rails 7.2.3.1 closes the Rails CVEs that 4.14.1 had to ignore; puma, nokogiri, crass, msgpack, oauth2, net-imap, mail, websocket-driver and dompurify CVEs fixed | SAFE AUTO-MERGE |
| New rate limits (widget, conversation delete, agent create/delete) | SAFE AUTO-MERGE |

## 3. Authentication, sessions, API tokens

| Change | Class |
|---|---|
| New `user_sessions` table and **Profile → Active sessions** (#14556) | CONFLICTS WITH LYNOMIA (semantic). Lynomia's `Api::V1::Mobile::AuthController` issues tokens without session tracking. Fixed in commit 4. |
| **Concurrent session limit** `MAX_USER_SESSIONS` (default 25; 409 + `SessionLimitOverlay`) (#14621) | CONFLICTS WITH LYNOMIA (login template); resolved in commit 3 |
| `api_and_webhooks` feature and token-auth check (`validate_token_api_access`) | SAFE (always allowed off Chatwoot Cloud) |
| `Current.account` no longer nil under token auth (#15088) | SAFE (Lynomia's `Billing::AccessGuard` depends on `Current.account`; verified in regression) |
| Platform API (`app/controllers/platform/**`) | SAFE (no upstream change; Lynomia's `/platform/api/v1/billing/*` unaffected) |
| Google OAuth error toast and signup feedback (#15716, #15655) | CONFLICTS WITH LYNOMIA (login template); resolved in commit 3 |

## 4. Inboxes and other channels

| Change | Class |
|---|---|
| Facebook login refactored into `useFacebookPageConnect` + `helper/facebookScopes.js`; Instagram scopes kept out of Messenger (#14619, #14695) | CONFLICTS WITH LYNOMIA (scope list); resolved in commit 3, Lynomia scopes kept |
| Messenger postbacks: the `messaging_postbacks` page webhook field is now subscribed (#14115) | REQUIRES MANUAL MERGE (ops: enable the field in the Meta app) |
| Model-level inbox limit (`CustomExceptions::Inbox::LimitExceeded`, 402) next to Lynomia's `Billing::InboxLimit` (422) | REQUIRES MANUAL MERGE (compatible; FB/IG/TikTok callbacks surface only the 402 class; backlog item) |
| Email: branded layouts, SMTP without IMAP, IMAP fixes (net-imap 0.4 → 0.6) | SAFE AUTO-MERGE (QA IMAP inboxes) |
| Instagram, TikTok, Telegram, LINE, Twilio, SMS, widget fixes | SAFE AUTO-MERGE |
| Voice / Calls dashboard (enterprise) and its sidebar entry | CONFLICTS WITH LYNOMIA (sidebar hunk); resolved in commit 3 |

## 5. Frontend routing and UI

| Change | Class |
|---|---|
| `settings.routes.js`: `templates` and `data` routes | CONFLICTS WITH LYNOMIA (import line); merged both |
| `billing.routes.js` → `ProviderIndex.vue` (Shopify / Stripe switch) | REQUIRES MANUAL MERGE: still renders Lynomia's `billing/Index.vue` redirect |
| `billing/Index.vue`: multi-currency and cancel-at-period-end | CONFLICTS WITH LYNOMIA; Lynomia redirect kept |
| Sidebar: sortable and collapsible sections, team icons, unread badges, Calls, Templates, Data | CONFLICTS WITH LYNOMIA (one hunk); merged. Visual QA done with screenshots. |
| `vueapp.html.erb`: robots `noindex`, new brand colours | CONFLICTS WITH LYNOMIA (colours); Lynomia branding kept, `noindex` taken |
| Upstream brand refresh of 28 icons + `manifest.json` (#15054) | CONFLICTS WITH LYNOMIA; Lynomia assets kept |
| Captain in the conversation assignment dropdown (#15437) | REQUIRES MANUAL MERGE (product decision; Lynomia hides Captain only in the sidebar) |

## 6. Automations, jobs, Redis, storage, websocket, integrations

| Change | Class |
|---|---|
| `config/schedule.yml`, `config/sidekiq.yml` unchanged; new jobs use existing queues | SAFE AUTO-MERGE |
| Delayed automations (`automation_rule_pending_executions`, feature off by default) | SAFE AUTO-MERGE |
| Assignment v2: skips conversations inactive for more than 7 days by default | REQUIRES MANUAL MERGE (behaviour change; tell admins) |
| Redis: new key namespaces only | SAFE AUTO-MERGE |
| ActionCable: `reconnect_attempts`, list refresh on reconnect | SAFE AUTO-MERGE |
| Storage: `azure-storage-blob` → `azure-blob` (`AzureBlob` service) | REQUIRES MANUAL MERGE only if `ACTIVE_STORAGE_SERVICE=microsoft` |
| Slack signature verification (`SLACK_SIGNING_SECRET`); Dyte → Cloudflare RealtimeKit; Shopify gated by `ENABLE_SHOPIFY_INTEGRATION` | REQUIRES MANUAL MERGE (ops, only if used) |
| Captain / AI (86 commits), data imports | SAFE AUTO-MERGE / NOT RELEVANT (Lynomia hides Captain) |
| Enterprise billing (Stripe/Shopify for Chatwoot Cloud) vs Lynomia `custom/` billing | SAFE: no collision in methods, tables, InstallationConfig keys, routes or constants (`appendix/B` §5.4). **REQUIRES MANUAL MERGE:** 6 more flags become assignable in Lynomia plans (`api_and_webhooks`, `branded_email_templates`, `data_import`, `delayed_automations`, `whatsapp_manual_transfer`, `whatsapp_embedded_signup_inbox_creation`), so plans must be reviewed. |

## 7. Migrations

- There are 45 new upstream migrations plus 1 modified historical one. Details and reversibility are in `02-rollback-plan.md` §2.1 and `appendix/B` §6.
- **SAFE AUTO-MERGE:** all of them (upstream-only files).
- **REQUIRES MANUAL MERGE (ops):**
  - Run the migrations with `POSTGRES_STATEMENT_TIMEOUT=0`: there are 4 concurrent indexes on `messages`, `conversations` and `audits`, and 2 `conversations` backfills.
  - Pre-check duplicate installation `email_templates`.
  - Back up pending `captain_assistant_responses` (purged).
  - Keep Sidekiq processing `async_database_migration`.
  - Afterwards check `pg_index.indisvalid`.
- **CONFLICTS WITH LYNOMIA:** `db/schema.rb` (version line and foreign-key block); merged in commit 3.

## 8. Dependencies

| Item | Change | Class |
|---|---|---|
| Rails | 7.1.5.2 → **7.2.3.1** (`load_defaults 7.0` kept) | REQUIRES MANUAL MERGE: Lynomia `custom/` scanned with no 7.2 incompatibilities; full test suite run |
| puma / sidekiq | 6.4.3 → 7.2.1 / 7.3.1 → 7.3.10 | SAFE AUTO-MERGE |
| Gems | `azure-blob`, `devise-secure_password` 2.2.1 (gem instead of git), `speedshop-cloudwatch`, `useragent`, `auth-sanitizer`; net-imap 0.6 | SAFE AUTO-MERGE |
| JS | Vite 5 → 6.4.2, `@chatwoot/viz` replaces chart.js, turbo replaces turbolinks, dompurify 3.4.13 | SAFE AUTO-MERGE (Lynomia imports none of the removed packages) |
| Runtime | Ruby 3.4.4, Node 24.13.0, pnpm 10.2.0, Postgres 16 + pgvector, Redis: **unchanged** | SAFE |
| ENV | no new required variables | SAFE |

## 9. Summary by class

| Class | Scope |
|---|---|
| SAFE AUTO-MERGE | 3,904 upstream-only files, including every WhatsApp service, job and migration |
| REQUIRES MANUAL MERGE | 12 items, all config, ops or product decisions: media upload strategy, health polling, `messaging_postbacks`, plan feature review, 7-day assignment exclusion, Captain in assignment, migration runbook flags, direct-upload route, Slack/Dyte/Shopify if used, inbox-limit exception class, manual-setup-v2 naming, `ProviderIndex` |
| CONFLICTS WITH LYNOMIA | 38 textual (resolved in commit 3) + 2 semantic: mobile-auth session tracking (fixed in commit 4); re-auth inbox rename (pre-existing, documented) |
| NOT RELEVANT | Chatwoot Cloud-only billing, Meta incident switches, business management token, Shopify billing, history/contact sync (does not exist) |

**No stop condition is triggered by the upstream diff.**
- No Lynomia customization has to be deleted.
- No destructive migration touches Lynomia or WhatsApp data.
- Tenant isolation is strengthened: several scoping fixes, and admin-only WhatsApp re-auth.
- No new token exposure.
- Coexistence in 4.18 uses the same `whatsapp_cloud` + Embedded Signup architecture Lynomia already has.
