# Pivot Review: WhatsApp Business App Coexistence via Meta Embedded Signup

> **Superseded (2026-09-29).** Lynomia was upgraded to Chatwoot 4.18.0, which ships Coexistence support. The "WhatsApp Business / واتساب بزنس" option was built on that upstream implementation, not on the plan below. For example, the marker is `provider_config.is_coexistence`, not `onboarding_method`, and no Lynomia backport was needed. See `docs/whatsapp-business/README.md` and `docs/chatwoot-upgrade/`. This page is kept as architectural history.

| | |
|---|---|
| Status | Review only. Nothing was implemented, nothing was deleted, and neither production nor the official WhatsApp code changed. Evolution work is **PAUSED / FALLBACK**. |
| Repo | `claude/laughing-albattani-8yi0kh` @ `348360bb`. Lynomia fork of Chatwoot **4.14.1** (`VERSION_CW`); upstream `chatwoot/chatwoot` master and develop are **4.18.0** (`https://raw.githubusercontent.com/chatwoot/chatwoot/master/VERSION_CW`) |
| Date | 2026-09-29 |
| Evidence | Local code with `path:line`. Upstream master fetched file by file from `raw.githubusercontent.com` (169 of 172 WhatsApp-related files diffed; copies kept in the session scratchpad). `U:` means `https://github.com/chatwoot/chatwoot/blob/master/` (read through the raw URL; line anchors as of 2026-09-29, no commit SHA because github.com is blocked). |
| **Evidence gap** | **Meta's official documentation could not be read in this session.** `developers.facebook.com`, `graph.facebook.com` and `business.whatsapp.com` are denied by the environment's network policy (proxy 403). Every Meta-behaviour statement below is therefore either (a) what the code sends to or expects from Meta, (b) what upstream Chatwoot's code comments state, or (c) explicitly marked **VERIFY-META**. Nothing was taken from tutorials. |

---

## Key findings

1. **Coexistence is not a new system. It is the existing official WhatsApp Cloud channel.** The current Embedded Signup button already launches Meta with the Coexistence feature type:
   - `featureType: 'whatsapp_business_app_onboarding'`, `sessionInfoVersion: '3'` (`app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:71-80`).
   - It accepts the Coexistence completion event `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` (`channels/WhatsappEmbeddedSignup.vue:154-157`).
   - Its "learn more" link points to Meta's `…/embedded-signup/custom-flows/onboarding-business-app-users#limitations` (`app/javascript/dashboard/constants/globals.js:45-46`).
   - A Coexistence number ends up as a normal `Channel::Whatsapp` with `provider: 'whatsapp_cloud'` (`app/services/whatsapp/channel_creation_service.rb:41-57`).
2. **In our 4.14.1 fork, a Coexistence completion most likely fails, and if it didn't, the number would be mishandled.**
   - Upstream states that the Coexistence finish event carries **only `waba_id`**: "Meta's coexistence FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING event documents data: { waba_id } alone — no business_id or phone_number_id" (`U:app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js#L32-L36`).
   - Our code rejects a finish event without `business_id` in three places:
     - frontend: `whatsapp/utils.js:32-34` → "invalid business data";
     - controller: `api/v1/accounts/whatsapp/authorizations_controller.rb:67-73`;
     - service: `app/services/whatsapp/embedded_signup_service.rb:81-90`.
   - Even if that passed, our code would call `/register` with a random PIN (`app/services/whatsapp/webhook_setup_service.rb` `register_phone_number if !phone_number_verified? || phone_number_needs_registration?`). Upstream explicitly skips this: "Coexistence numbers come pre-registered, so /register is redundant" (`U:app/services/whatsapp/webhook_setup_service.rb#L27-L38`).
   - Our code would also run the post-signup health check (`embedded_signup_service.rb:27, 63-79`), which can flag the number, prompt re-authorization, and then **drop all webhooks** for the channel (`app/jobs/webhooks/whatsapp_events_job.rb:127-133`).
   - (The "only `waba_id`" statement is upstream's reading of Meta's docs. **VERIFY-META.**)
3. **Message synchronisation for Coexistence is already implemented in our code.** Messages sent from the WhatsApp Business App arrive as `smb_message_echoes`. Our code subscribes to them (`app/services/whatsapp/facebook_api_client.rb:63`), processes them as outgoing messages with `external_echo`, and dedupes them by WhatsApp message id (section E.4). History import and contact sync are **not** implemented, neither here nor upstream.
4. **Therefore no new provider, channel, table or messaging runtime is needed.** What is needed:
   - an additive onboarding entry;
   - a small, backward-compatible **Coexistence-aware branch** in the existing signup path (accept the waba-only finish, skip `/register` and the post-signup health check, record `onboarding_method`);
   - tests.

   This is the same approach upstream 4.18.0 took (section E.5).
5. **Evolution is no longer needed for connecting WhatsApp Business App numbers.** It stays a paused fallback. None of its code was ever written (section A).

---

## A. Current state (what was actually produced for "WhatsApp QR")

| Artifact | Exists? | Evidence |
|---|---|---|
| `docs/whatsapp-qr/00-discovery.md` (Phase A, 714 lines) | Yes. It is the **only** artifact | commit `348360bb` (`git show --stat 348360bb`: 1 file, +714) |
| Code, config, routes, migrations, schema, UI or Docker for QR/Evolution | **No** | `grep -rniI "evolution\|whatsapp_qr\|WhatsappQr\|baileys"` over app, custom, config, lib, db and enterprise found only non-English i18n strings for the unrelated wa.me test QR and `config/llm_models.json`. No `custom/db/migrate/*whatsapp_qr*`. No `config/routes/whatsapp_qr.rb`. |
| Evolution installed or deployed | **No** | Nothing in the repo; nothing was ever installed |

### A.1 Classification of `00-discovery.md` (line ranges refer to that file)

| Section (lines) | Content | Decision | Why |
|---|---|---|---|
| §0 Summary (14-25) | Mixed | ADAPT | Items 1-4 still hold. Items 5-7 are Evolution-specific (fallback) |
| Q1-Q2 channels and inbox lifecycle (28-53) | Provider-neutral repo facts | **REUSE** | Still accurate and relevant (inbox create and delete; `DeleteObjectJob` deletes history) |
| Q3 provider abstraction (54-63) | "No general abstraction; only inside `Channel::Whatsapp`" | ADAPT | Fact unchanged. The **conclusion flips**: Coexistence *is* `Channel::Whatsapp` + `whatsapp_cloud`, so no new abstraction is needed |
| Q4-Q5 secrets and encryption (64-99) | Neutral | **REUSE** | Directly relevant: `provider_config.api_key` is plaintext (section H) |
| Q6-Q10 tenancy, permissions, audit (100-163) | Neutral | **REUSE** | Same model applies to the Meta path |
| Q11 channels UI (164-178) | Neutral | **REUSE** | `Whatsapp.vue` picker is now the entry point |
| Q12-Q13 official WhatsApp (179-236) | Official path, plus what to avoid touching | REUSE + ADAPT | Becomes the *primary* path. "Must not touch" becomes "protected; additive extension only" |
| Q14 deployment (237-249) | Unknown topology | REUSE | Less critical now, because no new service is needed |
| Q15-Q17 Docker, PG/Redis, Evolution placement (250-277) | Evolution infra | **REMOVE/LATER (fallback)** | Not needed for Meta |
| §2 Evolution facts (278-369) | Versions, API, bridge, license | **REMOVE/LATER (fallback)** | Keep as reference |
| §3.1 architecture (372-390) | Neutral | REUSE | |
| §3.2 reusable components (391-414) | Mixed | ADAPT | Tenant scoping, Pundit, audit, logging, SafeFetch and admin-only realtime are kept. The `Channel::Api` / MessageBuilder bridge rows are Evolution-only |
| §3.3 files to change (415-485) | Evolution Option B files | **REPLACE** | Replaced by section J |
| §3.4-3.6 official path, inbox lifecycle, security (486-509) | Neutral | REUSE | |
| §3.7 secret model (510-520) | Evolution keys | ADAPT | The principle (ENV / encrypted, fail closed) stays; applied to Meta tokens in section H |
| §3.8 Evolution topology (521-548) | Evolution | REMOVE/LATER (fallback) | |
| §3.9 `whatsapp_qr_connections` table (549-577) | Evolution | **NOT REQUIRED for Meta** | `Channel::Whatsapp.provider_config` already models the Meta connection |
| §3.10 risks (578-599) | Mixed | ADAPT | R5, R7, R11-R13 and R15 remain; R1-R4 are Evolution-only |
| §3.11 "won't build" (600-614) | Neutral | REUSE | |
| §3.12 contracts (615-691) | Evolution provider, states, API | REMOVE/LATER (fallback) | The Meta path uses the existing reauthorization and health model |
| §4 decisions D1-D9 (692-709) | Mixed | ADAPT | D1-D3 paused (Evolution). D4, D5 and D9 still open. D6 resolved (additive picker card, allowed now). D7 less critical. D8 answered by Meta path (global unique number, `app/models/channel/whatsapp.rb:32`) |

### A.2 Evolution-specific items

All are **not required for the Meta path**. None was built. The research below is kept in `00-discovery.md` for a possible fallback.

| Item | Built? | Decision |
|---|---|---|
| Evolution API client, API key, URL settings | No (design only, 00 §3.3/§3.7) | KEEP FOR FALLBACK (design only) |
| Instance creation, instance IDs (`lyn_<account>_<uuid>`) | No | KEEP FOR FALLBACK |
| QR generation endpoints, QR UI | No | NO LONGER REQUIRED FOR META PATH |
| Baileys (v7.0.0-rc.9 via Evolution 2.3.7) | No | KEEP FOR FALLBACK (research) |
| Session lifecycle: reconnect, restart, logout, delete; the 8-state model | No | KEEP FOR FALLBACK. The Meta path uses the existing `Reauthorizable` and health model |
| Evolution PostgreSQL / Redis / Docker service | No | NO LONGER REQUIRED FOR META PATH |
| Evolution → Chatwoot bridge (native or Lynomia-owned) | No | NO LONGER REQUIRED FOR META PATH |
| Evolution webhooks and events (`QRCODE_UPDATED`, `CONNECTION_UPDATE`…) | No | KEEP FOR FALLBACK (research) |
| `whatsapp_qr_connections` table | No | NO LONGER REQUIRED FOR META PATH |

---

## B. Reuse matrix

| Existing component (evidence) | Evolution role (planned) | Meta Coexistence role | Decision |
|---|---|---|---|
| `Channel::Whatsapp` + `provider: 'whatsapp_cloud'` (`app/models/channel/whatsapp.rb:25-37`) | Not used (Evolution rode on `Channel::Api`) | **The channel for Coexistence numbers**, the same as Embedded Signup numbers | **REUSE** |
| Embedded Signup UI `WhatsappEmbeddedSignup.vue` + `whatsapp/utils.js` | None | The Meta popup launcher. Already sends the Coexistence feature type | **ADAPT** (accept the waba-only Coexistence finish; mode prop for copy) |
| Provider picker `channels/Whatsapp.vue:15-50, 99-141` | Avoided (official file) | Hosts the new "Connect existing WhatsApp Business App" card | **ADAPT** (additive card) |
| `Api::V1::Accounts::Whatsapp::AuthorizationsController` (`:1-75`) | None | Endpoint for signup and reauthorization | **ADAPT** (optional `is_coexistence`; `business_id` optional only then) |
| `Whatsapp::EmbeddedSignupService` (`:1-91`) | None | Code exchange → phone info → channel → webhooks | **ADAPT** (Coexistence branch: no `/register`, no post-signup health check) |
| `Whatsapp::TokenExchangeService` / `FacebookApiClient#exchange_code_for_token` (`facebook_api_client.rb:9-20`) | None | Server-side code → business token with App Secret | **REUSE** |
| `Whatsapp::PhoneInfoService` (`:22-37`) | None | Resolve the number on the WABA (Coexistence may omit `phone_number_id`) | **ADAPT** for the Coexistence branch only (no `phone_numbers.first` guess; `:34-37`) |
| `Whatsapp::ChannelCreationService` (`:1-72`, fork-modified naming) | Evolution variant existed upstream-only | Creates the inbox and channel. Global duplicate guard (`:27-31`) | **REUSE** + one optional key (`onboarding_method`) |
| `Whatsapp::WebhookSetupService` / `subscribed_apps` + callback override (`facebook_api_client.rb:63-96`) | None | Subscribes `messages` + `smb_message_echoes` | **ADAPT** (`is_coexistence:` keyword, default nil = today's behaviour) |
| `Whatsapp::WebhookTeardownService` (`:16-46`) | None | Offboarding | **REUSE** (known upstream bug: unsubscribes the whole WABA; section E.3) |
| `Whatsapp::ReauthorizationService` + `Reauthorizable` + `whatsapp/Reauthorize.vue` | Evolution "reconnect" was to be custom | Reconnect / re-auth | **REUSE** (Coexistence-aware reauth is a later item; section E.3) |
| Webhook route `webhooks/whatsapp/:phone_number` + `Webhooks::WhatsappController` + `WhatsappEventsJob` (`config/routes.rb:616-617`) | New `/webhooks/whatsapp_qr/:uuid` planned | Receives `messages`, `statuses` and `smb_message_echoes` for Coexistence numbers | **REUSE** unchanged |
| `IncomingMessageBaseService` + echo handling + `MessageDedupLock` | Evolution needed its own dedupe | Business App echoes → outgoing messages, deduped by wamid | **REUSE** unchanged |
| Send path `SendReplyJob` → `SendOnWhatsappService` → `WhatsappCloudService` | Evolution needed its own send job | Replies from Lynomia go out through the Cloud API | **REUSE** unchanged |
| Templates, statuses, attachments, contacts, conversations, agents, teams, automations | Reused via `Channel::Api` | Reused as-is | **REUSE** |
| Tenant scoping (`Api::V1::Accounts::BaseController`, `Current.account`) | Reuse | Reuse | **REUSE** |
| Pundit `InboxPolicy` (admin-only create/update) | Reuse | Reuse. Note that `AuthorizationsController` itself has **no** authorize call (section H) | **REUSE** (+ recommended admin guard) |
| Billing `Billing::InboxLimit` (all create paths) | Reuse | Applies automatically (Inbox validation) | **REUSE** |
| Secrets: `InstallationConfig` `WHATSAPP_APP_ID/SECRET/CONFIGURATION_ID/API_VERSION` (`config/installation_config.yml:154-170`; super admin `app_configs_controller.rb:50`) | Evolution keys to be added | **Already the Meta app configuration** | **REUSE** (`WHATSAPP_APP_SECRET` lacks `type: secret`; section H) |
| Encryption (`encrypts … if Chatwoot.encryption_configured?`) | For Evolution tokens | `provider_config.api_key` is **not** encrypted | ADAPT later (hardening, section H) |
| Audit (`Enterprise::AuditLog`, `Enterprise::Channelable` audits channel updates) | Custom `whatsapp_qr.*` events | Inbox create/update/delete are already audited. Custom `whatsapp.coexistence_*` events are optional | **REUSE** |
| Health: `Whatsapp::HealthService`, `whatsapp_health_management.rb`, `AccountHealth.vue` | Evolution health poll | Existing health endpoint and UI | **REUSE** (upstream adds an `is_on_biz_app` display) |
| Evolution Docker/PG/Redis, QR UI, `whatsapp_qr_connections` | Core | None | **NOT REQUIRED** (fallback) |

---

## C. Existing official WhatsApp architecture (as it is today)

### C.1 Onboarding paths
- **Entry.** `ChannelList.vue` has a single `whatsapp` card (`:38-43`). `channels/Whatsapp.vue` shows a provider picker with **WhatsApp Cloud** and **Twilio** cards (`:37-50`). 360dialog is reachable only via `?provider=360dialog` (`:21, :138-140`).
- **Embedded Signup** shows only when `whatsappAppId` is configured (`Whatsapp.vue:24-29, 99-104`). A "manual setup" link switches to the `whatsapp_manual` form (`:67-69, 107-127`).
  - `whatsappConfigurationId` is read only on click (`WhatsappEmbeddedSignup.vue:204-206`).
- **Manual Cloud API setup (protected).** `CloudWhatsapp.vue:50-57` posts `type: 'whatsapp', provider: 'whatsapp_cloud', provider_config: { api_key, phone_number_id, business_account_id }` to `POST /api/v1/accounts/:id/inboxes` (`inboxes_controller.rb:33-46, 93-97`). `EDITABLE_ATTRS` accepts any `provider_config` key (`whatsapp.rb:25`).
- **Embedded Signup (protected).**
  1. `FB.login` with `config_id`, `response_type: 'code'`, `override_default_response_type: true` and `extras { setup: {}, featureType: 'whatsapp_business_app_onboarding', sessionInfoVersion: '3' }` (`whatsapp/utils.js:59-83`).
  2. The page listens for `postMessage` events of type `WA_EMBEDDED_SIGNUP` from `*facebook.com` (`:36-57`).
  3. On a finish event it sends `{code, business_id, waba_id, phone_number_id}` (`WhatsappEmbeddedSignup.vue:130-140`) to `POST /api/v1/accounts/:id/whatsapp/authorization` (`config/routes.rb:336-338`).
  4. `AuthorizationsController#create` (`:7-13, 20`) calls `Whatsapp::EmbeddedSignupService#perform` (`:11-33`), which runs:
     - token exchange;
     - phone info;
     - token validation (`debug_token` WABA scope check);
     - `ChannelCreationService` (`provider: 'whatsapp_cloud'`, `provider_config { api_key, phone_number_id, business_account_id, source: 'embedded_signup' }`, `:41-57`), or `ReauthorizationService` when `inbox_id` is present;
     - `channel.setup_webhooks`;
     - a health check (new channels only).
- **Twilio WhatsApp** is `Channel::TwilioSms` with `medium: whatsapp`, a separate path (`Twilio.vue:84-92`).

### C.2 Answers to the review questions

1. **How is a WhatsApp inbox created today?** Through one of three creation paths:
   - manual Cloud API form → `inboxes#create`;
   - Embedded Signup → `whatsapp/authorization`;
   - 360dialog → `inboxes#create`.

   Twilio WhatsApp is a separate channel type. All three paths produce `Channel::Whatsapp` + `Inbox`.
2. **Manual or Embedded Signup?** Both exist. The UI shows Embedded Signup when `WHATSAPP_APP_ID` is set, and manual otherwise or on request. The fork edited the Embedded Signup service (`channel_creation_service.rb:69-71` names the inbox by phone number), which indicates Lynomia uses Embedded Signup.
3. **Is Embedded Signup present?** Yes (C.1).
4. **Is Coexistence-specific logic present?** Partly:
   - **Present:** the Coexistence feature type (`utils.js:77`), finish-event acceptance (`WhatsappEmbeddedSignup.vue:154-157`), `smb_message_echoes` subscription and processing (section E.4), and a placeholder for messages WhatsApp cannot render, such as companion-device syncs (`incoming_message_base_service.rb:79-89`).
   - **Missing or broken:** waba-only finish data (rejected), `/register` skip, health-check skip, phone resolution without `phone_number_id` (`phone_info_service.rb:34-37` falls back to the first number), `Reauthorize.vue` Coexistence event, history and contact sync.
5. **Chatwoot version.** 4.14.1 (`VERSION_CW`); upstream is 4.18.0.
6. **Difference from upstream.** The fork's WhatsApp delta is only `build_inbox_name` (git diff vs `d58b6a6c`). Upstream 4.14.1 → 4.18.0 changed about 40 WhatsApp files (section E.5). The Coexistence-relevant ones are listed there.
7. **New provider needed?** **No.** A Coexistence number is a `whatsapp_cloud` number. It needs an additional onboarding branch on the same provider.

### C.3 Branches keyed on `provider_config['source']`

These must **not** be broken. Setting `source` to a new value would silently change behaviour, so **the Coexistence marker must be a new key**.

| # | Location | Behaviour when `source == 'embedded_signup'` |
|---|---|---|
| 1 | `app/models/channel/whatsapp.rb:137-141` | Skip `after_commit :setup_webhooks` auto-setup |
| 2 | `app/services/whatsapp/webhook_teardown_service.rb:16-26` | Teardown only for embedded signup |
| 3 | `app/controllers/webhooks/whatsapp_controller.rb:36-42` | Meta `X-Hub-Signature-256` verification **required** |
| 4 | `settingsPage/ConfigurationPage.vue:53-55, 363, 439` | "Reconfigure" button instead of raw `api_key` and verify-token display |
| 5 | `inbox/Settings.vue:370-392` | Reauth and registration banners |
| 6 | `inbox/FinishSetup.vue:51-63, 84, 94, 194` | Hides manual webhook details |

---

## D. Meta Coexistence requirements

**This section cannot be completed from official sources in this session**, because Meta's documentation hosts are blocked. Below, **(code)** marks what our code already requires and uses, **(upstream)** marks what upstream Chatwoot's comments state, and **VERIFY-META** marks what must be read on developers.facebook.com before implementation.

| Item | Current evidence | Status |
|---|---|---|
| Meta App (Business type) with the WhatsApp product | Chatwoot self-hosted guide (`https://raw.githubusercontent.com/chatwoot/docs/main/self-hosted/configuration/features/integrations/whatsapp-embedded-signup.mdx`, lines 31-45) | (code/docs) |
| App ID | `WHATSAPP_APP_ID` → browser as `whatsappAppId` (`app/controllers/dashboard_controller.rb:78-79`, `app/views/layouts/vueapp.html.erb:42`) | (code) |
| App Secret | `WHATSAPP_APP_SECRET`, used **server-side only**: code exchange (`facebook_api_client.rb:14`), `debug_token` app token (`:118`), webhook signature (`webhooks/whatsapp_controller.rb:28`). Not sent to the browser | (code) |
| Configuration ID (Facebook Login for Business, "WhatsApp Embedded Signup" variation) | `WHATSAPP_CONFIGURATION_ID` → `whatsappConfigurationId` (`vueapp.html.erb:43`); docs lines 53-62 | (code/docs). **VERIFY-META:** whether the configuration must enable the business-app onboarding option |
| Permissions | `whatsapp_business_management`, `whatsapp_business_messaging`, `business_management` (docs lines 69-75). The token check requires `whatsapp_business_management` scoped to the WABA (`token_validation_service.rb:26-40`) | (code/docs). **VERIFY-META:** Advanced Access / App Review status needed for Tech Provider onboarding of other businesses |
| Tech Provider status | Not represented in code | **VERIFY-META** (program requirements, business verification) |
| Code → token exchange | `GET /oauth/access_token?client_id&client_secret&code` (server-side) | (code). **VERIFY-META:** token type (business integration system user token?) and its lifetime |
| WABA ID | From the `WA_EMBEDDED_SIGNUP` finish event (`waba_id`) → `provider_config.business_account_id` | (code) |
| Phone Number ID | From the finish event, or looked up with `GET /{waba}/phone_numbers` (`facebook_api_client.rb:22-29`) | (code). (upstream): **absent** from the Coexistence finish event |
| `subscribed_apps` | `POST /{waba}/subscribed_apps` + override `{override_callback_uri, verify_token, subscribed_fields}` (`facebook_api_client.rb:75-96`) | (code). **VERIFY-META:** the per-number override that upstream moved to (`U:app/services/whatsapp/facebook_api_client.rb#L144-L176`) |
| Webhook fields | `messages`, `smb_message_echoes`, `calls` (`facebook_api_client.rb:63`) | (code). **VERIFY-META:** `history` and `smb_app_state_sync` (not subscribed) |
| Phone registration | `POST /{phone_id}/register {pin}` when not verified | (upstream): **must be skipped for Coexistence**. **VERIFY-META** |
| History / contact sync request | Not implemented (no `smb_app_data`) | **VERIFY-META** (endpoint, 24-hour window, opt-in). Not implemented upstream either |
| Token lifecycle and revocation | Reauth when media download returns 401 (`incoming_message_whatsapp_cloud_service.rb:17`) or webhook setup fails. No handling of `account_update` / `PARTNER_REMOVED` | **VERIFY-META** (which webhooks signal offboarding) |
| Graph API version | Config default `v22.0` (`installation_config.yml:166-170`). Messages hard-coded **v13.0**, templates **v14.0** (`providers/whatsapp_cloud_service.rb:78-99`). `whatsappApiVersion` never reaches the browser (not in `GLOBAL_CONFIG_KEYS`, `dashboard_controller.rb:4-26`) | (code). **VERIFY-META:** current supported versions |
| Coexistence limitations (eligible numbers, countries, features unavailable on Coexistence numbers, companion-device limits) | Only the doc link at `globals.js:45-46` (`#limitations`) | **VERIFY-META** |

**What a human must read** (URLs were not fetchable here):
- `developers.facebook.com/docs/whatsapp/embedded-signup/` (overview, implementation, version 3 session info)
- `…/embedded-signup/custom-flows/onboarding-business-app-users/` (flow, finish event payload, limitations, sync)
- WhatsApp Cloud API webhooks reference for `smb_message_echoes`, `history`, `smb_app_state_sync`, `account_update`
- Tech Provider onboarding requirements

---

## E. Chatwoot compatibility: self-hosted and multi-tenant

### E.1 Multi-tenant model today

| Topic | Behaviour | Evidence |
|---|---|---|
| One Meta app for all tenants | Installation-wide `WHATSAPP_APP_ID/SECRET/CONFIGURATION_ID`, super admin managed | `config/installation_config.yml:154-170`; `app/controllers/super_admin/app_configs_controller.rb:50` |
| Tenant → WABA / number | Each inbox stores its own `business_account_id`, `phone_number_id` and `api_key` in `provider_config` | `channel_creation_service.rb:50-57` |
| Several numbers or WABAs per tenant | Allowed (one inbox per number) | model has no per-account limit |
| Same number in two tenants | **Blocked globally.** Model uniqueness plus a unique index. The error message reveals that the number "already exists" | `whatsapp.rb:32`; `db/schema.rb:659`; `channel_creation_service.rb:12-13, 27-31`; `config/locales/en.yml:118` |
| Duplicate inbox on retry | Blocked by the same global guard | same |
| Webhook routing | `…/webhooks/whatsapp/:phone_number`. Channel resolved from the payload's `display_phone_number` plus a `phone_number_id` match, with the URL as fallback | `config/routes.rb:616-617`; `webhooks/whatsapp_controller.rb:44-55`; `whatsapp_events_job.rb:135-156` |
| Callback registration | Override **per WABA** to this number's URL (the last registered number of a WABA wins; routing still works through payload resolution) | `webhook_setup_service.rb:58-78`; `facebook_api_client.rb:84-96` |
| Webhook authenticity | `X-Hub-Signature-256` HMAC with the global App Secret, **required** for `embedded_signup` channels | `concerns/meta_token_verify_concern.rb:21-38`; `whatsapp_controller.rb:25-42` |
| Verify token | Per channel, random (`provider_config.webhook_verify_token`) | `whatsapp.rb:117-119` |
| Re-auth | `whatsapp/Reauthorize.vue` + `ReauthorizationService`; the `Reauthorizable` Redis flag makes the job drop **all** events | `whatsapp_events_job.rb:127-133`; `reauthorizable.rb:16, 39-48` |
| Offboarding | Inbox delete → `before_destroy :teardown_webhooks` → `DELETE /{waba}/subscribed_apps` | `whatsapp.rb:36`; `webhook_teardown_service.rb:16-46` |
| Plan limits | `Billing::InboxLimit` applies to every path. The core `validate_limit` is skipped by `whatsapp/authorization` | `config/initializers/billing.rb:5-12`; `app/helpers/api/v1/inboxes_helper.rb:118-122` |

### E.2 Security-relevant gaps in the current implementation

These are protected as-is. They are listed for decision, not changed.

1. **`AuthorizationsController` has no role check.** Any account member, including an agent, can create or re-authorize a WhatsApp inbox through the API. The spec asserts that an agent succeeds (`spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb:59-81`). The UI routes are admin-only (`inbox.routes.js:74-79`), so this is an API-level gap. Upstream 4.18 requires an admin only for re-auth (`U:app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb#L4`).
2. **The business token is stored in plain text** in `provider_config.api_key` (no `encrypts` in `app/models/channel/whatsapp.rb`). It is also returned to admins' browsers inside `provider_config` (`app/views/api/v1/models/_inbox.json.jbuilder:132`) together with `webhook_verify_token` and `verification_pin`. This conflicts with the requirement "no permanent or business tokens in the browser".
3. **`WHATSAPP_APP_SECRET` has no `type: secret`** (`config/installation_config.yml:162-165`, compare `FB_APP_SECRET` at `:130-134`), so the super admin form renders it as plain text.

### E.3 Known bugs in 4.14.1 that upstream has fixed (checked against local code)

| Bug | Local evidence | Upstream fix |
|---|---|---|
| Coexistence finish rejected (requires `business_id`) | `utils.js:32-34`; `authorizations_controller.rb:67-73`; `embedded_signup_service.rb:81-90` | `U:…/whatsapp/utils.js#L32-L36`; controller `#L33, #L81` |
| `/register` called on Coexistence numbers | `webhook_setup_service.rb` (`register_phone_number if !phone_number_verified? …`) | `U:app/services/whatsapp/webhook_setup_service.rb#L27-L38` |
| Post-signup health check can lock a Coexistence number | `embedded_signup_service.rb:27, 63-79` | skipped for Coexistence (`U:app/services/whatsapp/embedded_signup_service.rb#L25`) |
| `phone_numbers.first` fallback can bind the wrong number | `phone_info_service.rb:34-37` | strict match or error (`U:app/services/whatsapp/phone_info_service.rb#L34-L58`) |
| Re-auth writes the Business-portfolio id into `business_account_id` | `whatsapp/Reauthorize.vue:76-83` → `reauthorization_service.rb:33` | uses `waba_id` (`U:app/services/whatsapp/reauthorization_service.rb#L31-L37`) |
| `Reauthorize.vue` ignores the Coexistence event | `whatsapp/Reauthorize.vue:76` | upstream composable `U:app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js#L50-L75` |
| Teardown unsubscribes the **whole WABA** (breaks other inboxes on it) | `webhook_teardown_service.rb:38` | only when no other inbox uses the WABA (`U:app/services/whatsapp/webhook_teardown_service.rb#L11-L74`) |
| Re-auth flag drops webhooks for manual channels too | `whatsapp_events_job.rb:129` | embedded-signup only (`U:app/jobs/webhooks/whatsapp_events_job.rb#L148-L159`) |
| Throughput "pending" check never matches (symbol key on a string-keyed hash) | `webhook_setup_service.rb:116` | `U:app/services/whatsapp/health_service.rb#L159` |
| BSUID-only contacts are sent with `to:` (upstream comment: silently dropped by Meta) | `providers/whatsapp_cloud_service.rb:20, 108, 131, 199` | `recipient` (`U:app/services/whatsapp/providers/base_service.rb#L57-L69`) |

### E.4 Message synchronisation today

| Flow | Handling | Evidence |
|---|---|---|
| Sent from Lynomia (Cloud API) | The send stores the returned `wamid` as `source_id`. Status webhooks update by `source_id` | `send_on_whatsapp_service.rb:37, 42`; `incoming_message_base_service.rb:49-66` |
| Sent from the WhatsApp Business App (phone) | `smb_message_echoes` webhook → `IncomingMessageWhatsappCloudService(outgoing_echo: true)` → message created with `message_type: :outgoing`, `status: :delivered`, `sender: nil`, `source_id: wamid`, `content_attributes.external_echo: true` | `whatsapp_events_job.rb:71-77`; `incoming_message_base_service.rb:21-23, 161-176` |
| Contact for an echo | Taken from the echo's recipient (`to_parent_user_id` / `to_user_id` / `to`) | `whatsapp_events_job.rb:102-107`; `incoming_message_identifier_helper.rb:2-14, 49-55` |
| Echo not re-sent | `SendOnChannelService#invalid_message?` skips messages with a `source_id` | `base/send_on_channel_service.rb:35-50` |
| Inbound customer messages | Normal `messages` webhook, the same as today | — |
| Dedupe | `Message.find_by(source_id:)` (global) plus a Redis `SET NX` lock for 1 day on the wamid | `incoming_message_service_helpers.rb:74-78`; `message_dedup_lock.rb` |
| Unrenderable companion-device syncs (error 131060) | Stored as a placeholder "This message is unavailable." (`is_unsupported`) | `incoming_message_base_service.rb:79-89`; `config/locales/en.yml:261` |
| History import | **Not implemented** (no `history` subscription or handler, no `smb_app_data` request). Payloads are ignored | grep (local and upstream) |
| Contact sync | **Not implemented** (`smb_app_state_sync`) | same |
| Only the first change / first message per webhook | Batched payloads lose items after the first | `incoming_message_whatsapp_cloud_service.rb:8`; `whatsapp_events_job.rb:72, 93` |

**Needs VERIFY-META:** whether Meta also emits `smb_message_echoes` for messages sent *through the Cloud API*. If it does, an echo that arrives before `message.update!(source_id:)` could create a duplicate. That race is not covered by the lock, which only serialises echoes.

### E.5 Upstream 4.14.1 → 4.18.0 (WhatsApp)

- About 40 local WhatsApp files changed upstream, and about 20 new files exist upstream (for example `webhook_channel_finder_service.rb`, `user_id_rotation_service.rb`, `media_upload_service.rb`, `manual_setup_service.rb`, `health_sync_job.rb`, `composables/useWhatsappEmbeddedSignup.js`).
- `token_validation_service.rb` was removed.
- Upstream did **not** add history sync, contact sync or `smb_app_data`: every conventional path probed returned 404, and there is no occurrence in any fetched file.
- Its UI still has **one** Embedded Signup button. Only the copy changed, to "connect a new number or an existing number from the WhatsApp Business app" (`U:app/javascript/dashboard/i18n/locale/en/inboxMgmt.json#L399, #L428`).
- Fork conflicts: `channel_creation_service.rb` is byte-identical upstream (so our naming change applies cleanly); `facebook/Reauthorize.vue` really conflicts; branding config and `db/schema.rb` conflict (expected).

---

## F. Proposed target architecture (no implementation yet)

```text
Add Channel → WhatsApp (channels/Whatsapp.vue picker)
│
├── [WhatsApp Cloud]  ── EXISTING, UNCHANGED ──────────────────────────────────────────────
│     ├── Embedded Signup button (same component, same featureType, same behaviour)
│     └── "manual setup" link → CloudWhatsapp.vue (manual API setup)
│
├── [Connect existing WhatsApp Business App]  ── NEW card (additive) ─────────────────────
│     └── same WhatsappEmbeddedSignup.vue, mode="business_app" (Coexistence copy/instructions)
│         └── FB.login with the SAME featureType 'whatsapp_business_app_onboarding'
│
├── [Twilio] ── EXISTING, UNCHANGED
│
▼ both Embedded Signup entries
POST /api/v1/accounts/:id/whatsapp/authorization  { code, waba_id, [business_id], [phone_number_id], [is_coexistence] }
▼
Whatsapp::EmbeddedSignupService
  • is_coexistence absent/false → exactly today's behaviour
  • is_coexistence true         → business_id optional; strict phone resolution; skip /register; skip post-signup health
▼
Channel::Whatsapp(provider: whatsapp_cloud, provider_config: {…, source: 'embedded_signup', onboarding_method: 'coexistence'})
▼
EXISTING runtime (unchanged): webhooks/whatsapp/:phone_number → WhatsappEventsJob → messages / statuses / smb_message_echoes
                              SendReplyJob → SendOnWhatsappService → Cloud API ; templates, health, reauth, teardown
```

Design rules:
1. **Tag by event, not by button.** The existing button can also produce a Coexistence onboarding (Meta shows the choice), so `is_coexistence = (event == 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING')`. This is the same rule upstream uses (`U:…/whatsapp/utils.js` `classifySignupEvent`).
2. **Keep `source: 'embedded_signup'`.** It drives six protected branches (C.3). Add a new key `onboarding_method: 'coexistence'`.
3. **All new parameters default to today's behaviour** (nil or absent means "not Coexistence").
4. **Evolution stays separate and paused.** No Evolution or Baileys code enters this path.

---

## G. Migration impact

| | Items |
|---|---|
| **Stays unchanged** | Manual API setup (`CloudWhatsapp.vue`, `inboxes#create`); 360dialog; Twilio; the webhook route, controller, signature logic and events job; incoming and echo processing; dedupe; the send path; templates; health; teardown; `Channel::Whatsapp` model and schema; all existing channels' `provider_config`; `source` semantics; existing inbox JSON |
| **Extended (additive, backward compatible)** | `whatsapp/utils.js` (accept the waba-only *Coexistence* finish; expose the event type); `WhatsappEmbeddedSignup.vue` (mode prop, pass `is_coexistence`); `Whatsapp.vue` (new card); `AuthorizationsController` (permit `is_coexistence`; `business_id` optional only when true); `EmbeddedSignupService` / `WebhookSetupService` / `PhoneInfoService` / `ChannelCreationService` (optional keyword arguments, default = current behaviour); `en.json` (plus `ar`) strings |
| **Replaced** | Nothing |
| **No longer required (Meta path)** | Evolution service, Evolution PG/Redis, QR UI, `whatsapp_qr_connections`, the Evolution bridge (all were design only) |
| **Data migration for existing numbers** | **None.** No schema change. Existing rows have no `onboarding_method` and are treated exactly as today |

---

## H. Compliance and risk comparison (factual)

| Aspect | Evolution (Baileys / linked device) | Meta Coexistence (Cloud API) |
|---|---|---|
| Official support | Unofficial WhatsApp Web protocol (Baileys `7.0.0-rc.9`, 00 §2.1). WhatsApp terms of service and ban exposure (00 §3.10 R17) | Official Meta Cloud API plus Embedded Signup (code: `whatsapp/utils.js:59-83`) |
| New infrastructure | Evolution service + own PG + Redis (00 §3.8) | **None.** Uses the existing Rails app and Meta webhooks |
| Credentials | Global Evolution API key, per-instance token, and (native bridge) an admin user token stored in plain text in Evolution's DB (00 §2.4) | Meta App Secret (server-side only; E.2.3 UI masking issue); per-number business token in `provider_config.api_key` (**plain text, returned to admins**, E.2.2) |
| Webhooks | Evolution → Lynomia with a shared secret (design); the native bridge webhook is unauthenticated (00 §2.4) | Meta → Lynomia with an `X-Hub-Signature-256` HMAC, **required** for embedded-signup channels (`webhooks/whatsapp_controller.rb:36-42`) |
| Browser exposure | QR is a credential and needs admin-only delivery (00 §3.6) | `FB.login` gets App ID + Configuration ID only. The code is exchanged server-side. The App Secret never reaches the browser (`dashboard_controller.rb:78-79`). The **business token does reach admins** (E.2.2) |
| Tenant isolation | Our mapping (design) | Per-inbox `provider_config`; payload-based channel resolution plus a `phone_number_id` match; global number uniqueness |
| Revocation and offboarding | Logout or delete the instance (Evolution) | Teardown `DELETE subscribed_apps` (whole-WABA bug, E.3). The customer disconnecting on Meta's side is **not detected** (no `account_update` handling). VERIFY-META |
| Audit | Custom events (design) | Inbox create, update and delete audited (`Enterprise::Channelable`, `Audit::Inbox`); optional custom events |
| Permissions | Admin-only by design | UI admin-only. **API allows agents** (E.2.1) |
| Licensing | Evolution license notice for admins (00 §2.5); 2.4.0 activation and phone-home (00 §2.1) | Meta platform terms / Tech Provider (VERIFY-META) |
| History sync | Evolution could import (defaulted off) | Not implemented locally or upstream (optional later) |
| Maintenance | Must track an unofficial protocol plus Evolution releases | Tracks upstream Chatwoot (4.18 already hardens this path) |

---

## I. Recommendation

**Adopt Meta Coexistence as the primary path for "connect an existing WhatsApp Business App number". Keep Evolution PAUSED as a fallback. Implement Coexistence as a small additive branch of the existing Embedded Signup / `whatsapp_cloud` implementation.**

Engineering basis:
- **Official support.** It is the Cloud API plus Embedded Signup, which our code already uses (C.1).
- **Reuse.** The channel, webhooks, echo sync, dedupe, send path, templates, health, re-auth and teardown are all reused unchanged (B). Evolution would have needed a new service, bridge, table and UI (00 §3.3).
- **Complexity.** About 7 existing files get backward-compatible optional parameters, plus 1 new UI card, strings and specs (J). There is no new infrastructure.
- **Tenant isolation.** The existing per-inbox model plus signed Meta webhooks. Evolution's native bridge failed our isolation requirements (00 §2.4).
- **Maintenance.** This follows upstream's own approach (4.18 `is_coexistence`), so a later upstream upgrade converges instead of conflicting.
- **Chatwoot compatibility.** A Coexistence number is an ordinary `Channel::Whatsapp`.
- **Operations.** No new servers, databases or Redis.

Conditions and caveats:
1. **Before coding, read the blocked Meta pages** (D). In particular, confirm the Coexistence finish payload, the "skip `/register`" rule, the history and contact sync rules, and Coexistence limitations.
2. **Confirm the Meta App and Configuration ID** support business-app onboarding, and that Lynomia's Tech Provider app has the required access.
3. **Separately (not required for the Coexistence MVP, but recommended):**
   - admin guard on `whatsapp/authorization` (E.2.1);
   - stop returning `api_key` to browsers, and encrypt it (E.2.2);
   - `type: secret` for `WHATSAPP_APP_SECRET` (E.2.3);
   - the whole-WABA teardown fix;
   - the re-auth `business_account_id` fix (E.3).

   Each of these changes existing behaviour slightly, so each needs its own decision and regression tests. A full upgrade to 4.18.0 would bring all of them, but it is a larger, separate project.

---

## J. Exact next implementation phase (if approved)

### J.1 Contracts
- **Endpoint (existing):** `POST /api/v1/accounts/:account_id/whatsapp/authorization`
  - Request: `{ code, waba_id, business_id?, phone_number_id?, is_coexistence? }`.
    - `is_coexistence` is a boolean, default `false`.
    - `business_id` is required unless `is_coexistence` is true (today it is always required).
    - `inbox_id` is used for re-auth (unchanged).
  - Response: unchanged (`{ success, id, name, channel_type: 'whatsapp' }`).
- **Stored:** `provider_config.onboarding_method = 'coexistence'`, set only when `is_coexistence`. `source` stays `'embedded_signup'`.
- **Service keyword arguments** (default = current behaviour):
  - `EmbeddedSignupService.new(account:, params:, inbox_id: nil)`, where params may include `is_coexistence`.
  - `WebhookSetupService.new(channel, waba_id, access_token, is_coexistence: nil)`: skip `/register` when true.
  - `PhoneInfoService`: strict match when `strict: true`, used only for Coexistence.
  - `ChannelCreationService.new(…, onboarding_method: nil)`.
- **Frontend:**
  - `whatsapp/utils.js` exports `isCoexistenceFinish(event)`.
  - `isValidBusinessData(data, event)` requires `business_id` for `FINISH` (unchanged) and only `waba_id` for `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`.

### J.2 Files

**Changed (shared, additive):**
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappEmbeddedSignup.vue`: `mode` prop; pass `is_coexistence`; mode-specific copy.
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue`: new `PROVIDER_TYPES` key and card, shown only when `hasWhatsappAppId`; a new `v-else-if` placed **before** the `CloudWhatsapp` catch-all at `:141`.
- `app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb` (permit plus conditional validation)
- `app/services/whatsapp/embedded_signup_service.rb`
- `app/services/whatsapp/webhook_setup_service.rb`
- `app/services/whatsapp/phone_info_service.rb`
- `app/services/whatsapp/channel_creation_service.rb`
- `app/models/channel/whatsapp.rb`: only if `setup_webhooks` must forward `is_coexistence` (keyword argument with default).
- `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` (plus `ar`, following the fork's earlier convention for fork-specific keys)

**New:**
- Specs (J.4)
- Optional `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.spec.js`

**Explicitly untouched:**
- `CloudWhatsapp.vue`, `360DialogWhatsapp.vue`, `Twilio.vue`, `whatsapp/Reauthorize.vue` (Coexistence-aware re-auth is a later item)
- `webhooks/whatsapp_controller.rb`, `whatsapp_events_job.rb`, `incoming_message_*`, `send_on_whatsapp_service.rb`, `providers/*`, `webhook_teardown_service.rb`
- `_inbox.json.jbuilder`, schema, `config/features.yml`

### J.3 Additive Integration Impact

1. **Current files that will not change:** the list above ("explicitly untouched"), plus all models, schema, routes and the messaging runtime.
2. **Shared files needing a small extension:** the 10 files in J.2, all through optional parameters or new branches whose defaults equal today's behaviour.
3. **New Coexistence-specific files:** specs only. Coexistence reuses the existing component and services; there is no new service or model.
4. **Can Coexistence be added without modifying the messaging runtime?** **Yes.** Webhook receipt, echo processing, dedupe, sending, templates and statuses are unchanged (E.4). History and contact sync would be the first runtime extension, and they are out of scope for the MVP (defaults OFF).
5. **Same Chatwoot WhatsApp inbox infrastructure?** **Yes.** `Channel::Whatsapp` + `whatsapp_cloud` + `Inbox` (`channel_creation_service.rb:41-65`).
6. **Backward compatibility for existing numbers:**
   - no migration and no schema change;
   - existing `provider_config` untouched;
   - `onboarding_method` absent means current behaviour;
   - `source` unchanged;
   - new params default to nil or false, so the code paths for existing channels (webhook signature, teardown, auto-setup, UI branches in C.3) are unchanged;
   - webhook subscriptions are unchanged (`WEBHOOK_DEFAULT_FIELDS` untouched).

   **The non-negotiable criterion is satisfiable.** No Meta or Chatwoot constraint forces a reconnect, because nothing about existing numbers' Meta configuration changes.
7. **Regression tests required:**
   - **Existing suites must pass unchanged:**
     - `spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb`
     - `spec/services/whatsapp/{embedded_signup,channel_creation,webhook_setup,webhook_teardown,phone_info,token_exchange,token_validation,facebook_api_client}_service_spec.rb`
     - `spec/jobs/webhooks/whatsapp_events_job_spec.rb`
     - `spec/controllers/webhooks/whatsapp_controller_spec.rb`
     - `spec/models/channel/whatsapp_spec.rb`
     - `spec/services/whatsapp/incoming_message_*_spec.rb`, `message_dedup_lock_spec.rb`
     - `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`
   - **New "unchanged behaviour" tests:**
     - `FINISH` without `business_id` is still rejected (frontend and backend);
     - `is_coexistence` absent → `/register` still called under the same conditions, and the health check still runs;
     - the stored `provider_config` for the standard flow is byte-identical (no `onboarding_method`);
     - `source` stays `'embedded_signup'` for both flows;
     - the manual `inboxes#create` WhatsApp path is unaffected;
     - an existing channel without `onboarding_method` receives messages and echoes and sends as before.
   - **New Coexistence tests:**
     - a waba-only finish is accepted;
     - `/register` is skipped;
     - the health check is skipped;
     - strict phone resolution (multi-number WABA → clear error, not `.first`);
     - `onboarding_method` is stored;
     - duplicate-number retry yields the existing error, not a second inbox;
     - service-level echo test (outgoing, delivered, `external_echo`, deduped against an API-sent wamid).
   - **Frontend:** `utils.js` event classification and validation; the picker shows the new card only with an App ID and leaves the existing cards and flow untouched.

### J.4 Open decisions before Phase J
1. Allow Meta docs access (add `developers.facebook.com`, `graph.facebook.com`) or provide the pages, so the **VERIFY-META** items can be closed.
2. Confirm that Lynomia's Meta app and Configuration ID are enabled for business-app onboarding (Tech Provider).
3. Scope: Coexistence MVP only (J), or also the security fixes in E.2 and E.3 (each changes existing behaviour slightly), or a full upstream upgrade to 4.18.0?
4. History and contact sync: out of the MVP (recommended; defaults OFF, as in the QR plan)?
