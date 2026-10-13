---
agent: 039
scope: WhatsApp SETUP and connection — embedded signup, manual setup, credentials in provider_config, phone selection/registration, webhook subscription, reconnection, coexistence, multi-WABA, setup errors
confidence: high
---

## 1. What the feature is

A WhatsApp number in this product is a `Channel::Whatsapp` row (`channel_whatsapp`) plus an `Inbox` pointing at it.
The channel row holds the phone number, a `provider` (`default` = 360dialog, `whatsapp_cloud` = Meta Cloud API —
`app/models/channel/whatsapp.rb:36`) and a `provider_config` jsonb blob holding every credential and identifier.
`phone_number` is **globally unique across the whole installation**, not per account
(`db/schema.rb:844`, unique index `index_channel_whatsapp_on_phone_number`; model validation at
`app/models/channel/whatsapp.rb:40`).

There are **five** distinct ways a WhatsApp Cloud channel comes into existence, distinguished by
`provider_config['source']`:

| Route | `source` value | Entry point |
|---|---|---|
| Embedded Signup, new/Cloud number | `embedded_signup` | `Whatsapp::ChannelCreationService` (`app/services/whatsapp/channel_creation_service.rb:56`) |
| Embedded Signup, "WhatsApp Business" coexistence | `embedded_signup` + `is_coexistence: true` | same service, `:59` |
| Manual setup v2 (5-step wizard) | `manual_setup_v2` | `app/services/whatsapp/manual_setup_service.rb:42` |
| Legacy manual form (`CloudWhatsapp.vue`) | **absent** | `Api::V1::Accounts::InboxesController#create` → `channels/CloudWhatsapp.vue:52-67` |
| 360dialog (`provider: default`) | absent | `channels/360DialogWhatsapp.vue:48-49` |

`source` is load-bearing: it decides whether webhook setup runs implicitly or explicitly
(`app/models/channel/whatsapp.rb:230-235`), whether delete deregisters the number at Meta
(`app/services/whatsapp/webhook_teardown_service.rb:44,59`), which reconnect UI is offered
(`.../inbox/Settings.vue:407-416`), and whether the Business Management Token field exists
(`app/services/whatsapp/business_management_token_service.rb:23`).

### What is stored in `provider_config`, and how it is protected

| Key | Written by | Secret? |
|---|---|---|
| `api_key` (the Meta access token, or the 360dialog D360 key) | `channel_creation_service.rb:53`, `manual_setup_service.rb:39`, `reauthorization_service.rb:35`, `ConfigurationPage.vue:177-180`, `Settings.vue:501-506` | yes — in `SECRET_PROVIDER_CONFIG_KEYS` |
| `phone_number_id` | `channel_creation_service.rb:54`, `manual_setup_service.rb:40`, `reauthorization_service.rb:36` | no |
| `business_account_id` (WABA id) | same three | no |
| `source` | same three | no |
| `is_coexistence` | `channel_creation_service.rb:59` (only when true) | no |
| `webhook_verify_token` | auto-generated `SecureRandom.hex(16)` in `before_validation` for every `whatsapp_cloud` channel (`app/models/channel/whatsapp.rb:188-190`) | no — shown in the UI (`ConfigurationPage.vue:420,449`) |
| `verification_pin` | 6-digit PIN generated/stored during `/register` (`app/services/whatsapp/webhook_setup_service.rb:58-71`) | yes |
| `app_secret` | not written by any setup path; read as an optional per-channel override for webhook signature verification (`custom/app/services/whatsapp/diagnosis/local_checks.rb:69`) | yes |
| `calling_enabled`, `inbound_calls_enabled` | voice toggles (`app/models/channel/whatsapp.rb:113,124`) | no |

Protection is **not encryption**. `provider_config` is a plain jsonb column (`db/schema.rb:836`); only
`business_management_token` is `encrypts`ed, and only when encryption is configured
(`app/models/channel/whatsapp.rb:33`). The protections that do exist:

1. **Browser never receives the secrets.** `SECRET_PROVIDER_CONFIG_KEYS = %w[api_key verification_pin app_secret
   app_secret_key client_secret api_secret]` (`app/models/channel/whatsapp.rb:32`) is stripped in the serializer,
   which also restricts the whole `provider_config` to administrators
   (`app/views/api/v1/models/_inbox.json.jbuilder:161-163`).
2. **A blank round-trip does not wipe them.** `#with_stored_credentials` re-merges the stored secret keys under
   any `provider_config` the dashboard sends back (`app/models/channel/whatsapp.rb:96-100`), called from
   `app/controllers/api/v1/accounts/inboxes_controller.rb:134`.
3. **`business_management_token` is excluded from `serializable_hash`** (`app/models/channel/whatsapp.rb:90-92`);
   only a `business_management_token_configured` boolean is sent, and only on Chatwoot Cloud
   (`_inbox.json.jbuilder:164-168`).
4. **The app secret never reaches the browser at all** — the OAuth code→token exchange is server-side
   (`app/services/whatsapp/facebook_api_client.rb:19-30`, reading `WHATSAPP_APP_ID`/`WHATSAPP_APP_SECRET` via
   `GlobalConfigService`).
5. **Diagnosis reports presence, never values** (`custom/app/services/whatsapp/diagnosis/local_checks.rb:106-115`).

Installation-level configuration: `WHATSAPP_APP_ID`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_APP_SECRET`
(type `secret`), `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN`, `WHATSAPP_API_VERSION` (default `v24.0`) —
`config/installation_config.yml:170-193`. The first three are injected into the page for the Facebook SDK at
`app/views/layouts/vueapp.html.erb:45-47`; the app secret is **not**.

## 2. Surfaces and routes

| Surface | Path / component | API |
|---|---|---|
| Provider picker | `settings_inboxes_page_channel`, `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:72-83`; `channels/Whatsapp.vue:98-125` | — |
| Embedded Signup card (both variants) | `channels/WhatsappEmbeddedSignup.vue`; driver `composables/useWhatsappEmbeddedSignup.js:27-114`; Meta SDK glue `channels/whatsapp/utils.js:121-151` | `POST /api/v1/accounts/:id/whatsapp/authorization` (`config/routes.rb:282`) → `Api::V1::Accounts::Whatsapp::AuthorizationsController#create` |
| Manual setup v2 wizard (5 steps) | `channels/WhatsappManualSetup.vue:24,348-771` | `POST whatsapp/manual/preview`, `POST whatsapp/manual/connect`, `GET whatsapp/manual/:inbox_id/webhook_status`, `POST whatsapp/manual/:inbox_id/setup_webhook` (`config/routes.rb:283-286`) → `Whatsapp::ManualSetupController` |
| Legacy manual credential form | `channels/CloudWhatsapp.vue` | `POST /api/v1/accounts/:id/inboxes` (`inboxes_controller.rb:216`) |
| 360dialog form | `channels/360DialogWhatsapp.vue` | same inboxes endpoint |
| Finish screen (webhook details + wa.me QR) | `inbox/FinishSetup.vue:55-73,111-141` | — |
| Reconnect banner / re-run signup | `channels/whatsapp/Reauthorize.vue`, gated by `Settings.vue:410-416` | same `whatsapp/authorization` with `inbox_id` |
| Reconfigure (embedded only) | `settingsPage/ConfigurationPage.vue:188-209,422-438` | same |
| Replace API key (manual only) | `settingsPage/ConfigurationPage.vue:169-187,451-479` | `PATCH inboxes/:id` |
| Embedded → manual migration | `components/WhatsappManualMigrationBanner.vue`, `components/WhatsappManualMigrationDialog.vue`, handler `Settings.vue:492-521` | `PATCH inboxes/:id` |
| Business Management Token (Cloud only) | `settingsPage/WhatsappBusinessManagementToken.vue`, gated `ConfigurationPage.vue:481-488` | `PUT inboxes/:id/whatsapp_business_management_token` (`config/routes.rb:212`) |
| Account Health + Register Webhook | `components/AccountHealth.vue:427-449`, tab at `Settings.vue:253` | `GET inboxes/:id/health`, `POST inboxes/:id/register_webhook` (`config/routes.rb:213-214`) |
| Operator diagnosis (CLI) | `lib/tasks/whatsapp_diagnose.rake:10-19` | `bundle exec rails whatsapp:diagnose [INBOX_ID=] [CONTACT=]` |
| Meta callbacks registered by setup | `config/routes.rb:548-549` (per-number), `:554-555` (app-level) | — |

### The embedded-signup sequence

`useWhatsappEmbeddedSignup.js` loads the Facebook SDK (`utils.js:7-13`), calls `FB.login` with
`config_id: WHATSAPP_CONFIGURATION_ID`, `response_type: 'code'`, `featureType:
'whatsapp_business_app_onboarding'`, `sessionInfoVersion: '3'` (`utils.js:121-145`), and separately listens for
`WA_EMBEDDED_SIGNUP` postMessages from `*.facebook.com` (`utils.js:98-119`). Auth code and business data arrive in
no fixed order and are joined before resolving (`useWhatsappEmbeddedSignup.js:48-57`). Server side:
`EmbeddedSignupService#perform` → `TokenExchangeService` → `PhoneInfoService` → create or reauthorize →
`channel.setup_webhooks!(is_coexistence:)` → post-signup health check (skipped on reauth and on coexistence)
(`app/services/whatsapp/embedded_signup_service.rb:11-35`).

### Phone number selection

`Whatsapp::PhoneInfoService` pages the whole WABA (`fetch_all_phone_numbers`,
`facebook_api_client.rb:43-60`) and then resolves one number, in strict priority
(`phone_info_service.rb:36-58`): a supplied `phone_number_id` wins; otherwise the channel being reauthorized's
existing `phone_number`; otherwise, only if the WABA holds exactly one number. A multi-number WABA with no
identifier raises *"Multiple phone numbers found for WABA … unable to determine the onboarded number"*
(`:41`). The stored `phone_number` is `"+" + display_phone_number` with separators stripped (`:60-74`).
**Multi-WABA and multi-number are supported** — nothing is unique per WABA, only per phone number.

### Webhook subscription setup

`Whatsapp::WebhookSetupService#perform` (`app/services/whatsapp/webhook_setup_service.rb:12-18`):

1. Conditionally `POST /{phone_number_id}/register` with a 6-digit PIN
   (`:33-38,47-71`; PIN reused from `provider_config['verification_pin']` if present).
2. `POST /{waba_id}/subscribed_apps` with `subscribed_fields: [messages, smb_message_echoes,
   message_template_status_update]`, plus `calls` when this channel or any sibling on the same WABA has voice on
   (`:85-107`, `facebook_api_client.rb:156-173`).
3. `POST /{phone_number_id}` with `webhook_configuration.override_callback_uri =
   FRONTEND_URL/webhooks/whatsapp/{phone_number}` and `verify_token = provider_config['webhook_verify_token']`
   (`:73-82,109-114`, `facebook_api_client.rb:175-188`).

The phone-level override is what lets several numbers on one WABA route to different URLs
(`facebook_api_client.rb:161`). The subscription itself is **WABA-wide and shared across siblings**, which is why
`calls_enabled_on_waba?` exists and why teardown only unsubscribes when no sibling remains
(`webhook_teardown_service.rb:57-74`).

`/register` is skipped for coexistence numbers. The guard is deliberately three-valued
(`webhook_setup_service.rb:27-38`): `true` → never register and make no health call; `false` → the front end
positively ruled coexistence out, trust it; `nil` (manual setup, the voice toggle, a direct re-registration) →
ask Meta `is_on_biz_app`. Registering a coexistence number takes the number *off* the phone
(`docs/real-whatsapp-uat/07-coexistence.md` §2).

### Teardown on delete

`before_destroy :teardown_webhooks` (`app/models/channel/whatsapp.rb:48,226-228`) clears the phone-level
override for every cloud channel, then — **only when `source == 'embedded_signup'`** — deregisters the number and,
if no sibling shares the WABA, removes the app subscription (`webhook_teardown_service.rb:31-74`). Deregistering a
manually connected number would disable it on the customer's own Meta app, hence the asymmetry (`:41-42`). Every
failure is logged and swallowed so a delete is never blocked (`:14-17`).

## 3. User-visible states

| State | What produces it |
|---|---|
| Provider picker with 2 cards (WhatsApp Cloud, Twilio) | `whatsappAppId` missing/`'none'` (`Whatsapp.vue:48-53,113-124`) |
| Provider picker with 3 cards (+ "WhatsApp Business") | `whatsappAppId` set and the embedded-signup feature resolves true — on a self-hosted install that is automatic (`Whatsapp.vue:64-68`) |
| Picker description switched to "connect WhatsApp Cloud manually…" | `isMetaInboxCreationDisabled` global config (`Whatsapp.vue:127-131`) |
| "WhatsApp Cloud" card jumps straight to manual | same flag (`Whatsapp.vue:133-145`) |
| Amber banner "Embedded Signup is temporarily unavailable…" | `isMetaInboxCreationDisabled` (`Whatsapp.vue:210-236`, `WhatsappEmbeddedSignup.vue:253-274`) |
| Embedded signup loading / "Setting up your WhatsApp Business Account" | `WhatsappEmbeddedSignup.vue:115,173-176` |
| Manual wizard 5-step progress bar | `WhatsappManualSetup.vue:24,330-338` |
| Manual wizard step 4 review (business name, number, phone id, WABA id) + green "Your Meta number and access token are valid." | successful `manual/preview` (`WhatsappManualSetup.vue:133-150,636-641`) |
| Manual wizard step 5 four-row checklist: Number access / Template access / Webhook callback / Webhook subscription, each Verified or Pending | `connect` response + `webhook_status` polled 5×/2 s (`WhatsappManualSetup.vue:110-131,245-260`) |
| Webhook URL shown with Copy, plus "Retry webhook setup" | `WhatsappManualSetup.vue:694-715,753-762` |
| Reconnection-required banner on the inbox | `reauthorization_required` **and** `source == 'embedded_signup'` (`Settings.vue:410-416`, serializer `_inbox.json.jbuilder:175`) |
| "Complete Registration" variant of that banner | health reports `platform_type`/`throughput.level == 'NOT_APPLICABLE'` (`Settings.vue:417-430`, `Reauthorize.vue:37-49`) |
| Blue "Manual setup recommended" migration banner | embedded-signup cloud channel + `is_on_biz_app === false` + health error is not `authorization` + account flag `whatsapp_manual_transfer` (`Settings.vue:431-442`) |
| Account Health: "Webhook not configured" / URL mismatch + Register Webhook button | `AccountHealth.vue:427-449,632-730` |
| Finish screen webhook details + verify token | cloud channel whose `source != 'embedded_signup'` (`FinishSetup.vue:55-58`) |
| wa.me QR on the finish screen | any WhatsApp channel with a phone number (`FinishSetup.vue:71-73,121`) |

**Not reachable on this installation**: the "Request access" banner for embedded signup requires
`isOnChatwootCloud` (`Whatsapp.vue:88-96`), and the Business Management Token section requires
`ChatwootApp.chatwoot_cloud?` both in the serializer (`_inbox.json.jbuilder:165`) and the template
(`ConfigurationPage.vue:483`). The 360dialog form is in the tree but has **no card in the picker** — it is only
reachable by hand-editing `?provider=360dialog` (`Whatsapp.vue:98-125` vs `:308-310`).

## 4. Errors and validation messages

### Server, backend i18n (`config/locales/en.yml`)

| String | Key | Raised at |
|---|---|---|
| `Channel already exists for this phone number: %{phone_number}, please contact support if the error persists` | `errors.whatsapp.phone_number_already_exists` (`en.yml:184`) | `channel_creation_service.rb:14` |
| `Reauthorization is not required for this inbox` | `inbox.reauthorization.not_required` (`en.yml:37`) | `authorizations_controller.rb:60-67` |
| `Channel reauthorized successfully` | `inbox.reauthorization.success` (`en.yml:36`) | `authorizations_controller.rb:81` |
| `Failed to exchange code for access token. Please try again.` | `errors.whatsapp.token_exchange_failed` (`en.yml:181`) | **defined but never referenced in code** — see §10 |
| `The access token does not have the required permissions for WhatsApp.` | `errors.whatsapp.invalid_token_permissions` (`en.yml:182`) | **never referenced** |
| `Failed to fetch phone number information. Please try again.` | `errors.whatsapp.phone_info_fetch_failed` (`en.yml:183`) | **never referenced** |
| `Invalid channel type for reauthorization` | `inbox.reauthorization.invalid_channel` (`en.yml:38`) | **never referenced** |
| `Failed to reauthorize WhatsApp. Please try again.` / `Reauthorization is not supported for this type of WhatsApp channel.` | `errors.whatsapp.reauthorization.generic` / `.not_supported` (`en.yml:196-198`) | **never referenced** |

### Server, bare English strings (no i18n key) — these reach the operator verbatim

`authorizations_controller.rb:101` and `embedded_signup_service.rb:99`:
`Required parameters are missing: code, waba_id`.
`token_exchange_service.rb:15` `Authorization code is required`; `:22` `No access token in response: {response}`.
`channel_creation_service.rb:22-25` `Account is required` / `WABA info is required` / `Phone info is required` /
`Access token is required`.
`phone_info_service.rb:18-19` `WABA ID is required` / `Access token is required`; `:26` `No phone numbers found for
WABA {id}`; `:29` `No matching phone number found for WABA {id}`; `:41` `Multiple phone numbers found for WABA
{id}; unable to determine the onboarded number`.
`reauthorization_service.rb:15` `Phone number mismatch. Expected {stored}, got {incoming}`.
`webhook_setup_service.rb:41-44` `Channel is required` / `WABA ID is required` / `Access token is required` /
`Phone number ID is required`; `:81` `Webhook setup failed: {message}`.
`manual_setup_validation_service.rb:34-36` `WABA ID is required` / `Phone Number ID is required` / `Access token is
required`; `:46` `This Phone Number ID does not belong to the WABA ID you entered.`; `:54` `Complete phone number
verification in Meta before continuing.`; `:59` `This WhatsApp number is already connected to another inbox.`;
`:62` `This Phone Number ID is already used by another WhatsApp inbox.`; `:69` `The token can access the number but
cannot access message templates. Generate a token with whatsapp_business_management permission.`; `:83` `The token
cannot access WhatsApp messaging. Generate a token with whatsapp_business_messaging permission.`
`business_management_token_service.rb:8,22,25` `Business management token is required` / `… only available on
Chatwoot Cloud` / `… only supported for WhatsApp Embedded Signup inboxes`.
`business_management_token_validation_service.rb:13,17` `Business management token must grant the
whatsapp_business_management permission` / `Could not validate business management token permissions. Please try
again.` (or Meta's own `error.message` passed through, `:51-54`).
`app/models/channel/whatsapp.rb:193` adds `provider_config: Invalid Credentials` — the one validation message the
whole credential check collapses into.
`inbox_health_management.rb:87` `Health data only available for WhatsApp Cloud API and Twilio SMS channels`.
`facebook_api_client.rb:230` `{context}: {raw Meta body}` for every Graph failure, e.g. `Token exchange failed:`,
`WABA phone numbers fetch failed:`, `Phone registration failed:`, `App subscription to WABA failed:`,
`Phone number webhook callback override failed:`.

### Client (`app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`, `.../inbox.json`)

`INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.*`: `INVALID_BUSINESS_DATA` "Invalid business data received from
Facebook. Please try again."; `UNSUPPORTED_COMPLETION` "The Meta setup finished without a WhatsApp phone number
that can be connected…"; `SIGNUP_ERROR` "Signup error occurred"; `CANCELLED` "WhatsApp Signup was cancelled";
`AUTH_NOT_COMPLETED`; `SDK_LOAD_ERROR`; `CALLING_ENABLE_FAILED`; `RESTRICTED_WARNING`; `SUCCESS_FALLBACK`.
`INBOX_MGMT.ADD.WHATSAPP.MANUAL_SETUP.ERRORS.{IDS_REQUIRED,REQUIRED,INVALID_TOKEN,GENERIC}` —
`INVALID_TOKEN` is produced by regex-matching Meta's text (`/invalid oauth access token|cannot parse access
token/i`) in `WhatsappManualSetup.vue:152-159`; anything else falls through to Meta's raw message.
`INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE` "We were not able to save the WhatsApp channel".
`INBOX_MGMT.ADD.WHATSAPP.{INBOX_NAME,PHONE_NUMBER,PHONE_NUMBER_ID,BUSINESS_ACCOUNT_ID,API_KEY}.ERROR` — the
legacy form's Vuelidate messages (`CloudWhatsapp.vue:37-43`).
`INBOX.REAUTHORIZE.*`: `ERROR`, `LOADING_FACEBOOK`, `CONFIGURATION_ERROR`, `FACEBOOK_LOAD_ERROR`,
`WHATSAPP_APP_ID_MISSING`, `WHATSAPP_CONFIG_ID_MISSING`, plus a `TROUBLESHOOTING` block (pop-ups, third-party
cookies, admin access) — **the troubleshooting strings exist in `inbox.json` but no component renders them**.
`INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_{RECONFIGURE,MANUAL_TRANSFER}_{SUCCESS,ERROR}` and the whole
`WHATSAPP_MANUAL_MIGRATION` tree.

The Meta SDK's own event taxonomy is mapped in `channels/whatsapp/utils.js:42-96`: `FINISH` and
`FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` are success; `FINISH_ONLY_WABA`, `FINISH_OBO_MIGRATION`,
`FINISH_GRANT_ONLY_API_ACCESS` become `UNSUPPORTED_COMPLETION`; `ERROR` and a `CANCEL` **carrying an
error_message** become errors; a bare `CANCEL` is a dismissal.

## 5. Failure paths

1. **Webhook setup fails after the channel is created (embedded signup).** `setup_webhooks!` reports to
   `ChatwootExceptionTracker`, logs `event=webhook_setup_failed`, latches `prompt_reauthorization!` and re-raises
   (`app/models/channel/whatsapp.rb:169-176,209-216`). The controller answers 422 with `Webhook setup failed: …`
   — **but the channel and inbox already exist** (`channel_creation_service.rb:35-40` committed before
   `setup_webhooks!` runs). The operator sees "failed" and an inbox they did not expect, in reconnection-required
   state. Recovery is the reconnect flow; nothing says so.
2. **Webhook setup fails in manual setup v2.** `ManualSetupService#setup_webhook` swallows the exception into
   `webhook_error` (`manual_setup_service.rb:52-58`), the API returns 201 with `webhook_setup: false`, and the
   wizard shows the message in a red banner plus a *Retry webhook setup* button
   (`WhatsappManualSetup.vue:275,285-297`). This path does **not** latch reauthorization, and
   `should_auto_setup_webhooks?` excludes `manual_setup_v2` (`app/models/channel/whatsapp.rb:230-235`), so an
   operator who clicks *Continue to add agents* instead of *Retry* gets a live inbox that silently receives
   nothing and shows no warning anywhere afterwards.
3. **Phone registration fails but setup continues.** `register_phone_number` rescues, stores the error and logs
   `Phone registration failed but continuing` (`webhook_setup_service.rb:53-56`). Embedded signup never inspects
   `registration_error`; only `ManualSetupService:55` and `ManualSetupController#setup_webhook:30` re-raise it.
   So an embedded-signup number that failed `/register` is reported as a successful signup.
4. **Reauthorization against the wrong number.** `ReauthorizationService` compares `phone_info[:phone_number]` to
   the stored one and raises `Phone number mismatch. Expected … got …` (`:14-16`). On a multi-number WABA with a
   coexistence FINISH that omits `phone_number_id`, `PhoneInfoService` matches the stored number instead
   (`embedded_signup_service.rb:52-58`, `phone_info_service.rb:52-58`) — this is the fix for the misidentification
   bug, and it is the only thing standing between a reauth and overwriting the wrong channel.
5. **Reauth silently changes the WABA.** If the incoming `waba_id` differs from the stored one,
   `business_management_token` is nulled and `business_account_id` overwritten with no warning
   (`reauthorization_service.rb:32-39`). The inbox is then also **renamed** to Meta's verified name
   (`:43-44`) — an operator's chosen inbox name is lost on reconnect.
6. **Reconnect offered on a healthy inbox.** `can_reconfigure_channel?` returns true for *any* `whatsapp_cloud`
   channel (`authorizations_controller.rb:69-72`), so the 422 "Reauthorization is not required" is effectively
   unreachable for cloud inboxes and a reconnect always proceeds, replacing the token.
7. **Every save of a WhatsApp channel calls Meta.** `validate_provider_config` → `validate_provider_config?`
   does a live `GET /{waba}/message_templates`, plus a `GET /{waba}/phone_numbers` whenever `provider_config`
   changed (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:67-81`). A Meta outage therefore fails
   unrelated inbox edits with `provider_config Invalid Credentials` and nothing more specific. The voice toggles
   deliberately bypass it with `save!(validate: false)` (`app/models/channel/whatsapp.rb:116,125`).
8. **The embedded→manual migration dialog has no server-side validation of its own.** It `PATCH`es
   `provider_config` with the three values and deletes `source` (`Settings.vue:495-508`); the only gate is
   `validate_provider_config?`, whose failure surfaces as the generic
   `WHATSAPP_MANUAL_TRANSFER_ERROR` "Could not switch to manual setup. Please verify the credentials and try
   again." The real reason is only in the log line `[WHATSAPP_EMBEDDED_TO_MANUAL] failure … check=…
   meta_error=…` (`whatsapp_cloud_service.rb:106-114`). Migration also does **not** re-register the webhook, so
   the inbox keeps the override pointing at the same URL under a now-different app.
9. **"Request access" is wired to a route that does not exist.** `whatsappChannel.js:13-17` posts to
   `/whatsapp/access_request`; `grep -rn access_request config/ app/ custom/` finds no route or controller. The
   button would always fail with the generic `ACCESS_REQUEST.ERROR`. Unreachable today because the banner is
   Chatwoot-Cloud-only (`Whatsapp.vue:90`), but it is a live defect for a cloud install.
10. **A popup-blocked or third-party-cookie-blocked browser** rejects `FB.login` with a non-`Login cancelled`
    error and shows the raw SDK message (`useWhatsappEmbeddedSignup.js:103-111`). The written-and-unused
    `INBOX.REAUTHORIZE.TROUBLESHOOTING` strings are exactly the advice a user needs here.
11. **`FRONTEND_URL` unset** makes the callback URL `/webhooks/whatsapp/{number}` with no host
    (`webhook_setup_service.rb:109-114`); Meta accepts or rejects it, and the only report is the diagnosis's
    `<FRONTEND_URL unset>` line (`custom/app/services/whatsapp/diagnosis/webhook_checks.rb:54`).
12. **Plan/limit refusals.** `CustomExceptions::Inbox::LimitExceeded` is handled separately in both controllers
    (`authorizations_controller.rb:17-19`, `manual_setup_controller.rb:14-15`); `Billing::InboxLimit` adds a count
    ceiling and a channel entitlement on every inbox create
    (`custom/app/models/billing/inbox_limit.rb:14-41`).

## 6. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| Every inbox settings Vue route | `permissions: ['administrator']` + `INBOX_MANAGEMENT` feature flag | `inbox.routes.js:58-61,76-79,99-102` |
| `whatsapp/authorization` — create | `authorize ::Inbox, :create?` → administrator | `authorizations_controller.rb:4`, `app/policies/inbox_policy.rb:51-53` |
| `whatsapp/authorization` — reauthorize | `check_admin_authorization?` | `authorizations_controller.rb:6` |
| Embedded signup availability | self-hosted: open; Chatwoot Cloud: account feature `whatsapp_embedded_signup_inbox_creation` | `authorizations_controller.rb:38-44`, `config/features.yml:293-296` |
| `whatsapp/manual/preview`, `/connect` | `authorize ::Inbox, :create?` | `manual_setup_controller.rb:2,39-41` |
| `whatsapp/manual/:inbox_id/*` | `authorize @inbox, :update?` **and** `source == 'manual_setup_v2'`, else 404 | `manual_setup_controller.rb:43-50` |
| `register_webhook` | `check_admin_authorization?` | `inbox_health_management.rb:6` |
| `health` | **inbox membership only, not administrator** — `skip_before_action :check_authorization` removes the class-level gate and no admin filter replaces it, so the only check left is `fetch_inbox`'s `authorize @inbox, :show?` (membership). `InboxPolicy#health?` exists but is never consulted | `inbox_health_management.rb:5`, `inboxes_controller.rb:3,6,87-90`, `inbox_policy.rb:22-27,79-81` |
| `whatsapp_business_management_token` | administrator, + `ChatwootApp.chatwoot_cloud?`, + `source == 'embedded_signup'` | `inbox_policy.rb:75-77`, `business_management_token_service.rb:21-26` |
| `provider_config` in the inbox payload | `Current.account_user&.administrator?` | `_inbox.json.jbuilder:161` |
| Migration banner | account feature flag `whatsapp_manual_transfer` (default off) | `Settings.vue:437-440`, `config/features.yml:276-279` |
| Embedded signup card (frontend) | `WHATSAPP_EMBEDDED_SIGNUP_FLOW` = `whatsapp_embedded_signup_inbox_creation`, only on Cloud | `featureFlags.js:10`, `Whatsapp.vue:64-68` |

Deprecated and unused: `whatsapp_embedded_signup` and `whatsapp_reconfigure` flags
(`config/features.yml:200-203,288-292`) — neither name appears in any non-spec source file.

## 7. Contextual-help opportunities

| UI location | The question a user has | Registry key that should link there | Key exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `channels/Whatsapp.vue:250-259` (provider cards) | "Which of these is mine?" | `whatsapp` → `connect-whatsapp` | yes (`documentationLinks.js:35`) |
| `channels/Whatsapp.vue:113-124` ("WhatsApp Business" card) | "Will my phone keep working?" | `whatsappCoexistence` | yes (`:36`) |
| `WhatsappEmbeddedSignup.vue:231-251` (Learn more) | same | currently links **Meta's** docs (`globals.js:46-47`), not the corpus | key exists, not used here |
| `WhatsappManualSetup.vue:101-108` (token step) | "Which permissions, and why two?" | new key, e.g. `whatsappManualToken` | **no** |
| `WhatsappManualSetup.vue:717-744` (4-row checklist) | "Webhook subscription is Pending — what now?" | new key, e.g. `whatsappWebhookSetup` | **no** |
| `WhatsappManualSetup.vue:152-159` (`INVALID_TOKEN`) | "My token is rejected" | `whatsappError190` | yes (`:48`) |
| `Whatsapp.vue:210-236` / `WhatsappEmbeddedSignup.vue:253-274` (restriction banner) | "Why is quick setup unavailable?" | links to `status.chatwoot.com` (`globals.js:81-82`); should be a corpus article | **no** |
| `WhatsappManualMigrationBanner.vue:14-18` ("View guide") | "What does migrating change?" | points at `chwt.app/migrate-whatsapp` via `brandLink`; needs a corpus article | **no** |
| `Reauthorize.vue:309-315` (reconnect banner) | "What do I do?" | `whatsappReconnect` | yes (`:53`) |
| `Settings.vue:417-430` ("Complete Registration") | "Registration isn't complete?" | `whatsappNumberStatus` / `whatsappDisplayName` | yes (`:49,51`) |
| `AccountHealth.vue:632-730` (webhook card) | "Not configured / mismatch" | `whatsappNothingArrives` | yes (`:52`) |
| `channel_creation_service.rb:14` → the 422 toast | "Already exists — where?" | `whatsappNumberTaken` | yes (`:54`) |
| `FinishSetup.vue:288-300` (wa.me QR) | "Is this a QR login?" (it is not) | `whatsapp` | yes |
| `ConfigurationPage.vue:451-479` (Update API Key) | "Which token goes here?" | `whatsappReconnect` | yes |

None of these keys is wired into the setup UI: `grep` finds no `documentationLinks` import under
`routes/dashboard/settings/inbox/channels/`.

## 8. Current documentation coverage

- `custom/db/documentation/en/whatsapp/connect-whatsapp.md` (1,237 words) — the main article. It names the
  three-or-four routes, what a WABA is, the required Meta permissions, the installation-wide uniqueness rule, the
  delete asymmetry, and five "if it does not work" cases. Strong and largely accurate.
- `custom/db/documentation/en/whatsapp/whatsapp-business-coexistence.md` (1,047) — the coexistence card, what is
  and is not carried over.
- `custom/db/documentation/en/whatsapp-errors/whatsapp-reconnect-a-number.md` (592) — reconnection order plus a
  table of five reconnection refusals.
- `custom/db/documentation/en/whatsapp-errors/whatsapp-number-already-connected.md` (457) — the installation-wide
  refusal, correctly scoped.
- `custom/db/documentation/en/whatsapp-errors/whatsapp-error-190.md` (511), `whatsapp-number-status.md` (602),
  `whatsapp-display-name.md` (393), `whatsapp-nothing-arrives.md` (590) — adjacent; each touches setup.
- `whatsapp-troubleshooting.md` (1,260) is the umbrella.
- Arabic mirrors exist for all of the above under `custom/db/documentation/ar/...`.

Internal engineering records (not corpus): `docs/whatsapp-business/README.md` (the coexistence card as built, with
the `source`/`is_coexistence` matrix), `docs/real-whatsapp-uat/01-channel-identity.md` (the definitive map of what
lives where), `.../02-waba-subscription.md`, `.../03-webhook-configuration.md`, `.../07-coexistence.md`,
`docs/whatsapp-qr/{00-discovery,07-meta-coexistence-pivot}.md` (both explicitly superseded; QR/Evolution was never
built).

## 9. Missing or stale documentation

1. **The manual setup v2 wizard has no article of its own.** `connect-whatsapp.md` summarises it in one numbered
   step. Nothing documents the four-row verification checklist, what *Pending* means on each row, the webhook-URL
   copy step, or the *Retry webhook setup* button — the single most likely place an operator gets stuck
   (`WhatsappManualSetup.vue:110-131,717-762`).
2. **"Switch to Manual Setup" / the migration banner is undocumented.** There is no corpus article; the UI's own
   "View guide" link points at upstream Chatwoot's `chwt.app/migrate-whatsapp` through `brandLink`, which on a
   branded install with no `DOCUMENTATION_URL` renders **no link at all**
   (`WhatsappManualMigrationBanner.vue:12-18`). A tenant is told to read a guide and given nothing to click.
3. **Multi-WABA and multi-number behaviour is not written down.** `connect-whatsapp.md` says templates belong to
   the business account, but nothing documents that the webhook subscription is WABA-wide and shared between
   sibling inboxes (`webhook_setup_service.rb:95-107`), that deleting one inbox can remove the subscription for
   none/all siblings (`webhook_teardown_service.rb:57-74`), or the "Multiple phone numbers found for WABA"
   refusal (`phone_info_service.rb:41`).
4. **Reconnect side effects are not documented.** `whatsapp-reconnect-a-number.md` does not say that a reconnect
   renames the inbox to Meta's verified name, or that reconnecting against a different WABA discards the stored
   business-management token (`reauthorization_service.rb:32-44`).
5. **No article covers the display-name/registration-incomplete *setup* state.** `whatsapp-display-name.md`
   covers the Account Health row, but the "Complete Registration" banner and the
   `platform_type == 'NOT_APPLICABLE'` condition that raises it (`Settings.vue:417-430`) are not named anywhere.
6. **The 360dialog provider is undocumented and unreachable.** `connect-whatsapp.md` lists only Cloud, Business
   App and Twilio. `360DialogWhatsapp.vue` still exists and `PROVIDERS` still accepts `default`
   (`app/models/channel/whatsapp.rb:36`). Either the docs or the code is stale; the orchestrator should decide
   which.
7. **No article explains the setup-time error vocabulary.** Fourteen of the twenty bare English strings in §4
   reach a tenant verbatim (e.g. *"This Phone Number ID does not belong to the WABA ID you entered."*). None is
   searchable in the corpus.
8. **Nothing documents the operator diagnosis.** `bundle exec rails whatsapp:diagnose`
   (`lib/tasks/whatsapp_diagnose.rake:4-6`) is the one tool that answers "where will Meta actually deliver"; it
   appears in no corpus file.

## 10. Doc claims not proven by code

| Doc claim | Code | Verdict |
|---|---|---|
| `connect-whatsapp.md`: "*Verify details* checks number access, template access, the webhook callback and the webhook subscription **before the inbox is created**" | `manual/preview` → `ManualSetupValidationService` checks number, template access and messaging permission only (`manual_setup_validation_service.rb:12-28`). Callback and subscription are checked **after** the inbox exists, by `ManualWebhookStatusService` on step 5 (`manual_setup_controller.rb:20-22`) | **wrong** (ordering) |
| `connect-whatsapp.md`: "**Administrators** only — … viewing Account Health" | `health` loses the class-level authorization (`inbox_health_management.rb:5`) and keeps only `fetch_inbox`'s membership check (`inboxes_controller.rb:87-89`), so any agent assigned to the inbox can read Meta's health payload | **wrong** — membership, not administrator (UI route is admin-only, the API is not) |
| `whatsapp-reconnect-a-number.md` refusal table lists "Failed to exchange code for access token", "The access token does not have the required permissions", "Failed to fetch phone number information", "Reauthorization is not supported for this type of WhatsApp channel" | all four are `en.yml:181-183,198` keys with **no reference anywhere in `app/`, `custom/` or `lib/`**. What a user actually sees is `Token exchange failed: {raw Meta body}` (`facebook_api_client.rb:29,230`), `No phone numbers found for WABA …` (`phone_info_service.rb:26`), etc. | **documented strings are unreachable**; the real strings are undocumented |
| `whatsapp-reconnect-a-number.md`: "**Lynomia Chat cannot tell you which permission was missing.** Meta reports a refusal, not a diff." | true for embedded signup, but manual setup *does* name the permission — `…Generate a token with whatsapp_business_management permission` / `…whatsapp_business_messaging permission` (`manual_setup_validation_service.rb:69,83`) | **partly wrong** |
| `connect-whatsapp.md`: "The access token is never handled in your browser" (quick setup) | confirmed: only the OAuth `code` crosses the browser; the exchange is server-side with `WHATSAPP_APP_SECRET` (`facebook_api_client.rb:19-30`) | **confirmed** |
| `connect-whatsapp.md`: "A phone number can be connected once in the whole installation" | confirmed: unique index (`db/schema.rb:844`), unscoped `find_by` (`channel_creation_service.rb:28-32`), unscoped `exists?` (`manual_setup_validation_service.rb:57-63`) | **confirmed** |
| `connect-whatsapp.md`: delete releases a quick-setup number but deliberately leaves a manual one registered | confirmed (`webhook_teardown_service.rb:41-53`) | **confirmed** |
| `whatsapp-business-coexistence.md` / `docs/whatsapp-business/README.md`: `/register` and the post-signup health check are skipped for coexistence | confirmed (`webhook_setup_service.rb:33-38`; `embedded_signup_service.rb:29`) | **confirmed** |
| `docs/whatsapp-business/README.md`: "There is no 'manual setup' fallback link under this card" | confirmed — the fallback link is inside the `shouldShowWhatsappEmbeddedSignup` branch only (`Whatsapp.vue:271-292` vs `:295-301`) | **confirmed** |
| `docs/whatsapp-business/README.md` matrix says manual Cloud API (legacy) has `source` absent | confirmed — `CloudWhatsapp.vue:60-64` sends no `source`, so `should_auto_setup_webhooks?` is true and webhook setup runs in `after_commit` with its failure swallowed (`app/models/channel/whatsapp.rb:49,179-184`) | **confirmed, and a documented gap**: this is the one route whose webhook failure is invisible to both the API response and the UI |

Unverified: nothing was checked against Meta's own documentation — no Meta API was called and no Meta page read,
per the brief. Every Meta-side claim above is "what this code sends or expects", not "what Meta states".
