# WhatsApp upgrade analysis: Chatwoot v4.14.1 → v4.18.0 vs the Lynomia fork

## Scope and method

- Refs: `v4.14.1` = `d58b6a6c` (the fork's merge base), `v4.18.0` = `9f920b54`, fork `HEAD` = `d09dcb7a9`. The tags are annotated. `git rev-parse v4.14.1` returns the tag object `8bcf08c2`, so resolve them with `^{commit}`.
- Read-only. I used only `git show/diff/log/grep` with explicit refs. I ran three-way merges only on scratch copies (`git merge-file -p` into `scratchpad/upgrade/wa/`). The working tree, index and refs were not touched.
- All `file:line` citations refer to **v4.18.0** unless marked otherwise.
- Upstream count: 611 commits between the tags, about 90 of them touching WhatsApp paths.

### Lynomia's WhatsApp footprint (`git diff --name-status v4.14.1 HEAD`)

Only these fork files touch WhatsApp:

| File | Lynomia change |
|---|---|
| `app/services/whatsapp/channel_creation_service.rb` | `build_inbox_name` returns `@phone_info[:phone_number]` instead of `"#{business_name} WhatsApp"` |
| `spec/services/whatsapp/channel_creation_service_spec.rb` | 3 expectations changed to `'+1234567890'` |
| `docs/whatsapp-qr/00-discovery.md`, `docs/whatsapp-qr/07-meta-coexistence-pivot.md` | Docs only: a plan, not implemented |

Indirect touch points:
- `custom/app/models/billing/inbox_limit.rb`, included into `Inbox` by `config/initializers/billing.rb`, adds a create-time validation to every inbox, including embedded-signup inboxes.
- `Billing::AccessGuard`, included into `Api::V1::Accounts::BaseController`, covers the WhatsApp authorization and manual-setup controllers.
- `config/installation_config.yml`: branding keys only.
- `app/views/layouts/vueapp.html.erb`: title and colours only. The `whatsappAppId`/`whatsappConfigurationId`/`whatsappApiVersion` lines are untouched.
- `channels/Facebook.vue` and `facebook/Reauthorize.vue`: Meta, not WhatsApp. Upstream also changed both (commits `66067a1df`, `950d87183`, `fe6f900db`, `c6a38e2fc`, `78a6b2457`). Out of scope here, but expect a real conflict there.

**No other WhatsApp file (frontend or backend) is modified by the fork.** Every other upstream WhatsApp change is therefore textually an upstream-only change.

---

## TL;DR

1. **Coexistence in v4.18.0 is a transient request flag and is never stored.**
   - The frontend sets `is_coexistence = (event === 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING')`.
   - The backend uses it only to skip `/register` and the post-signup health check.
   - Nothing is written to `provider_config` and there is no new column.
   - The only persisted signal is Meta's `is_on_biz_app`, which the new health poller writes into the `phone_number_health` jsonb.
   - There is **no separate Coexistence card**. The picker still shows only "WhatsApp Cloud" and "Twilio".
2. **History sync (`history`) and contact sync (`smb_app_state_sync`) are not implemented in v4.18.0.**
   - There is no subscription, no handler, no `smb_app_data` call and no flag.
   - Subscribed fields are `messages`, `smb_message_echoes`, plus `calls` only when calling is enabled.
   - Echo handling and dedupe are unchanged in mechanism. Echoes gained BSUID-aware contact resolution.
3. **Migrations are additive, nullable or defaulted, and need no backfill.**
   - `phone_number_health` (jsonb, NOT NULL, default `{}`), `phone_number_health_checked_at`, `phone_number_health_error`.
   - `business_management_token` (text, nil).
   - Only `business_management_token` is `encrypts` (conditional). It is set only on Chatwoot Cloud. `provider_config.api_key` stays **plaintext**.
4. **Security.**
   - Admin-only is enforced **only for reauthorize/reconfigure** (`inbox_id` present). Creating a new inbox through embedded signup still works for agents, and upstream's spec asserts that.
   - `provider_config`, including `api_key`, is still returned to administrators.
   - `WHATSAPP_APP_SECRET` still has **no** `type: secret`.
   - Teardown now only unsubscribes the app from the WABA when no sibling channel uses the same WABA. It also clears the phone-level override and deregisters the number for embedded-signup channels.
5. **`channel_creation_service.rb` is byte-identical between v4.14.1 and v4.18.0**, so Lynomia's naming change survives unchanged.
   - Upstream only added one spec example, which does not assert the name.
   - `git merge-file` produced 0 conflicts for both the service and the spec. The merged service equals Lynomia HEAD.
   - The phone number format from `PhoneInfoService#build_phone_info` is still `"+#{digits}"`.
6. **Lynomia naming gap (pre-existing, not new).** `ReauthorizationService` renames the inbox to the WhatsApp business name on every reauth or reconfigure (`reauthorization_service.rb:42-44`). This contradicts Lynomia's phone-number naming. It was already in v4.14.1, but v4.18.0 makes reconfigure ungated and admin-available.

---

## 1. WhatsApp Embedded Signup

### Commits
- `78a6b2457` (#14619): extracted `useWhatsappEmbeddedSignup` composable.
- `f93f2067b` (#14697): **deleted `Whatsapp::TokenValidationService`** (the `debug_token` WABA-scope check).
- `397ac2e18` (#14943), `d3c588ff1` (#14955), `8d554f2b7` (#14964), `5e811eab9` (#15042): temporary disable and re-enable.
- `98154bbea` (#14974), `fe6f900db` (#15210), `950d87183` (#15318): Meta incident controls.
- `b560720e0` (#14975), `0a25a0ef6` (#15032): embedded → manual transfer.
- `2891a72cb` (#15038), `08b9992c4` (#15650): reconfigure enabled, then ungated.
- `90861f880` (#15046), `7d2f01e40` (#15106): Cloud-only creation gate.
- `c086fe875` (#15079): guided manual setup v2.
- `343bb15d0` (#15336), `4114ff1f9` (#15749): Cloud access request.
- `79e145bc2` (#15462): coexistence.
- `0e07a27c7` (#14949): model-level inbox limit.
- `59eac9a7c` (#15218): business management token.

### Backend (v4.18.0)

**`app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb`**
- `:2` `before_action :ensure_embedded_signup_enabled`. It returns early unless `ChatwootApp.chatwoot_cloud?` (`:22-28`), so it is a **no-op on self-hosted**.
- `:4` `before_action :check_admin_authorization?, if: -> { params[:inbox_id].present? }`. Admin is required only for reauth.
- `:33` permits `:code, :business_id, :waba_id, :phone_number_id, :is_coexistence`.
- `:14-17` rescues `CustomExceptions::Inbox::LimitExceeded`, which renders 402 via `render_error_response`. Everything else becomes 422 `{success:false,error:...}`.
- `:78-86`: `business_id` is **no longer required**; only `code` and `waba_id`.

**`app/services/whatsapp/embedded_signup_service.rb`**
- `:8` `@is_coexistence = ActiveModel::Type::Boolean.new.cast(params[:is_coexistence])`. This yields `nil` when absent, `false` for "false", `true` for "true".
- `:14-17`: token exchange → phone info → create or reauth. The `validate_token_access` step was removed.
- `:22` `channel.setup_webhooks(is_coexistence: @is_coexistence)`.
- `:25` `check_channel_health_and_prompt_reauth(channel) if @inbox_id.blank? && !@is_coexistence`.
- `:39-54`: for reauth, it passes `expected_phone_number: reauthorizing_channel&.phone_number` to `PhoneInfoService`.
- `:58-63`: `ReauthorizationService` now takes `waba_id:`, where v4.14.1 took `business_id:`.

**`app/services/whatsapp/phone_info_service.rb`**
- `:25`: paginated `fetch_all_phone_numbers`, with a Bearer header.
- `:36-44`: **strict matching**.
  - If `phone_number_id` is given, it must match or the call raises `"No matching phone number found"` (`:29`).
  - Otherwise, for reauth, it matches the expected number.
  - Otherwise it raises if the WABA has more than one number (`:41`).
  - v4.14.1 silently fell back to `phone_numbers.first`.
- `:60-69`: the returned hash is unchanged: `phone_number: "+#{display_phone_number}"`, `business_name: verified_name || display_phone_number`.

**`app/services/whatsapp/reauthorization_service.rb`**
- `:31` `resolved_phone_number_id = @phone_number_id.presence || phone_info[:phone_number_id]`.
- `:32` clears `business_management_token` when the WABA changes.
- `:37` `'business_account_id' => @waba_id`.
  - This fixes a v4.14.1 bug where `Reauthorize.vue`'s non-stored-config path sent the **portfolio** `business_id` and it was written into `business_account_id`.
  - v4.18.0 has no backfill for channels already corrupted by that path.
- `:42-44`, unchanged from v4.14.1: `channel.inbox.update!(name: business_name) if business_name.present?`. **Reauth renames the inbox.** See §9.

**`app/services/whatsapp/token_validation_service.rb`: deleted.** There is no longer an explicit check that the exchanged token is scoped to the browser-supplied `waba_id`. Indirectly, `PhoneInfoService` lists `/{waba_id}/phone_numbers` with that token, which fails without access.

**`Whatsapp::TokenExchangeService` and `FacebookApiClient#exchange_code_for_token`: unchanged** (`facebook_api_client.rb:11-22`).

**`app/services/whatsapp/channel_creation_service.rb`: identical to v4.14.1.** It still writes `provider_config = { api_key, phone_number_id, business_account_id, source: 'embedded_signup' }` (`:50-57`) inside a transaction (`:33-39`).

**New: guided manual setup v2.**
- Files: `manual_setup_controller.rb`, `manual_setup_service.rb`, `manual_setup_validation_service.rb`, `manual_webhook_status_service.rb`.
- Routes: `config/routes.rb:386-393` (`/whatsapp/manual/{preview,connect,:inbox_id/webhook_status,:inbox_id/setup_webhook}`).
- Creates channels with `source: 'manual_setup_v2'` (`manual_setup_service.rb:42`).
- Default inbox name is `"#{verified_name || phone_number} WhatsApp"` (`manual_setup_validation_service.rb:96`). That is **not** Lynomia's phone-number naming.
- Authorization: `authorize ::Inbox, :create?` (admin) and `authorize @inbox, :update?`.

### Frontend (v4.18.0)

- **`channels/Whatsapp.vue`**
  - Providers: `:78-93` lists only `WHATSAPP` ("WhatsApp Cloud") and `TWILIO`.
  - Embedded signup is shown when `whatsappAppId` is set and `(!isOnChatwootCloud || cloud flag)` (`:54-66`).
  - The manual path now renders `WhatsappManualSetup.vue` (v2) (`:123-126`, `:204`). `CloudWhatsapp.vue` is only reached for other `?provider=` values (`:270`).
- **`composables/useWhatsappEmbeddedSignup.js`** (new): resolves `{code, business_id||'', waba_id, phone_number_id||'', is_coexistence}` (`:50-56`). It is used by `WhatsappEmbeddedSignup.vue:38,101`, `ConfigurationPage.vue:40,181` (reconfigure) and onboarding `useChannelConnect.js:27,60`.
- **`channels/whatsapp/utils.js`**
  - `isValidBusinessData` now needs only `waba_id` (`:34-36`).
  - `classifySignupEvent` (`:64-92`); unsupported events are `FINISH_ONLY_WABA`, `FINISH_OBO_MIGRATION` and `FINISH_GRANT_ONLY_API_ACCESS` (`:46-50`).
  - `FB.login` extras are unchanged from v4.14.1: `featureType: 'whatsapp_business_app_onboarding'`, `sessionInfoVersion: '3'` (`:130-137`).
- **`channels/whatsapp/Reauthorize.vue`**: handles the coexistence FINISH and passes `is_coexistence` (`:79-91`, `:229-237`).
- **`DISABLE_META_INBOX_CREATION`** (installation config default `true`, `installation_config.yml:240-245`) is only effective when `deploymentEnv === 'cloud'` (`shared/store/globalConfig.js:63-64`). **No effect on self-hosted** (`DEPLOYMENT_ENV` default `self-hosted`).

**Classification.** All of these are **SAFE AUTO-MERGE**: upstream-only files. Behaviour to verify, which is **REQUIRES MANUAL MERGE (behavioural)**:
- inbox naming for the manual v2 flow and on reauth (§9);
- strict phone matching, which can now raise where v4.14.1 silently picked the first number.

---

## 2. Coexistence: exact v4.18.0 behaviour

**Detection is frontend-only, from Meta's postMessage event name.**

`app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:38-40,70-75`:
```js
const COEXISTENCE_FINISH_EVENT = 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING';
const FINISH_EVENTS = ['FINISH', COEXISTENCE_FINISH_EVENT];
...
  if (FINISH_EVENTS.includes(event)) {
    return {
      type: SIGNUP_RESULT.FINISH,
      isCoexistence: event === COEXISTENCE_FINISH_EVENT,
    };
  }
```

`app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js:62-75`: the first terminal FINISH wins, then `is_coexistence: isCoexistence` is sent (`:55`).

**Where it is passed**
- `authorizations_controller.rb:33`: `params.permit(:code, :business_id, :waba_id, :phone_number_id, :is_coexistence)`
- `embedded_signup_service.rb:8`: `@is_coexistence = ActiveModel::Type::Boolean.new.cast(params[:is_coexistence])`
- `embedded_signup_service.rb:22`: `channel.setup_webhooks(is_coexistence: @is_coexistence)`
- `app/models/channel/whatsapp.rb:145-150, 172-178`:
  - `setup_webhooks(is_coexistence: nil)` → `perform_webhook_setup(is_coexistence:)` → `Whatsapp::WebhookSetupService.new(self, provider_config['business_account_id'], provider_config['api_key'], is_coexistence: is_coexistence)`
- `webhook_setup_service.rb:4,9`

**What it skips**

`app/services/whatsapp/webhook_setup_service.rb:33-38`:
```ruby
  def should_register_phone_number?
    return false if @is_coexistence
    return false if @is_coexistence.nil? && health_data[:is_on_biz_app]

    !phone_number_verified? || phone_number_needs_registration?
  end
```
- When `is_coexistence` is true, `POST /{phone_number_id}/register` is skipped.
- When it is `nil` (manual setup, voice toggle, `register_webhook` endpoint, old clients), the Graph `is_on_biz_app` health field is used as a fallback.
- Webhook subscription still runs.

`app/services/whatsapp/embedded_signup_service.rb:23-25`:
```ruby
    # Skip health check on reauth (avoids false disconnect emails) and on coexistence signups
    # (Meta's health data can lag several minutes behind a fresh FINISH event).
    check_channel_health_and_prompt_reauth(channel) if @inbox_id.blank? && !@is_coexistence
```

`phone_info_service.rb:40-41`: with no `phone_number_id`, which coexistence can omit, the signup fails on a multi-number WABA.

**What is stored.** **Nothing coexistence-specific.**
- `ChannelCreationService#build_provider_config` (`:50-57`) is unchanged. There is no `onboarding_method`, `coexistence` or `is_coexistence` key in `provider_config`, and no column.
- `git grep -i coexist` over `app enterprise lib db` finds no persistence.
- The only persisted related datum is Meta-sourced: `Whatsapp::HealthService::PERSISTED_FIELDS` includes `is_on_biz_app` (`health_service.rb:20-38`, specifically `:32`). It is written into `channel_whatsapp.phone_number_health` by `sync_health_status!` (`:184-195`).
- `sync_health_status!` runs from `Channels::Whatsapp::HealthSyncSchedulerJob` (hourly trigger; each whatsapp_cloud channel of an active account every ≥6h, `health_sync_scheduler_job.rb:5-13`) and from the inbox health endpoint (`inbox_health_management.rb:71`).

**UI for coexistence**
- **No separate card or option in the channel picker** (`Whatsapp.vue:78-93`: only `WHATSAPP` and `TWILIO`). One embedded signup button covers both new and existing-app numbers; Meta shows the choice.
- The copy mentions it: `en/inboxMgmt.json:399` ("connect a new number or an existing number from the WhatsApp Business app") and `:428`.
- Read-only indicator: `settings/inbox/components/AccountHealth.vue:223-230` shows "Coexistence: ACTIVE" when `isOnBizApp === true && platformType === 'CLOUD_API'` (i18n `en/inboxMgmt.json:958-960`).
- `inbox/Settings.vue:429-440` hides the embedded→manual migration banner unless `is_on_biz_app === false`.

**Coexistence-related gaps upstream did not address**
- Teardown on inbox delete **deregisters** embedded-signup numbers without any coexistence check (`webhook_teardown_service.rb:41-53`). The effect of `/deregister` on a coexistence number is not handled in code (**VERIFY-META**).
- No coexistence marker exists for later logic to key on.

**Lynomia impact.** **CONFLICTS WITH LYNOMIA plan (docs only).**
- `docs/whatsapp-qr/07-meta-coexistence-pivot.md` §F/§J proposed:
  - a new additive picker card;
  - a stored `provider_config.onboarding_method = 'coexistence'`;
  - `ChannelCreationService.new(…, onboarding_method:)`;
  - a `PhoneInfoService` "strict only for coexistence" mode;
  - keeping `business_id` required for normal FINISH.
- Upstream instead:
  - uses a transient flag, with nothing stored;
  - makes `business_id` optional for all flows;
  - makes `PhoneInfoService` strict for **all** flows;
  - adds no card.
- No Lynomia code exists for this yet, so there is no code conflict. The plan should be re-based onto 4.18 (for example, add `onboarding_method` inside `ChannelCreationService#build_provider_config` if a marker is still wanted).

---

## 3. BSUID / LID / contact mapping

### Commits
- `a3a961919` (#15150): send to BSUID via `recipient`.
- `2144de92f` (#15098), `11ecd7a30` (#15175), `65952920c` (#15630): conversation and identity anchoring.
- `07fa9ce88` (#15357): `UserIdRotationService`.
- `54c731b86` (#15670): BSUID contacts become `lead`.
- `c44a98d87` (#15552): contact-info request to recover phone numbers.
- `9253468b3` (#15614): campaigns to BSUID.
- `0e376f4fe` (#14743), `b227f8042` (#15546): BSUID calls.
- `d04a71770` (#15107): in-reply-to across scoped message ids.
- `9550de83e` (#14657), `545b82f01` (#14264), `d1a6ea579` (#14174): BR/MX/AR phone normalization.

Basic BSUID support (`from_user_id`, `parent_user_id`, `WHATSAPP_BSUID_REGEX`) already existed at v4.14.1.

### Changes in v4.18.0
- **recipient vs to.** `app/services/whatsapp/providers/base_service.rb:57-69`: `recipient_params(identifier)` returns `{ recipient_type: 'individual', recipient: identifier }` when the identifier matches `RegexHelper::WHATSAPP_BSUID_REGEX`, else `{ to: identifier }`. It is used in template, text, attachment and interactive sends (`providers/whatsapp_cloud_service.rb`).
- **Source-id ordering.** `incoming_message_identifier_helper.rb:51-61, 67-77` together with the new `app/services/whatsapp/identity_source_id_orderer.rb:1-25`:
  - phone first, then parent BSUID, then BSUID;
  - but a BSUID row is preferred when that identity already has conversations and the phone row has none.
  - The order changed from v4.14.1's `[phone, user_id, parent_user_id]`.
- **Contact-inbox resolution.** `app/services/contact_inbox_source_id_resolver.rb:2-11, 25-31`: new `prefer_first_source_id:` option (used by WhatsApp, `incoming_message_identifier_helper.rb:42-49`). It creates a new `contact_inbox` row for the preferred identifier on the same contact, inside a savepoint that rescues `RecordNotUnique`.
- **Conversation reuse.** `incoming_message_base_service.rb:108-129`:
  - `whatsapp_cloud` reuses conversations of the resolving `contact_inbox`, which is effectively the same as v4.14.1;
  - 360dialog reuses contact-wide.
- **Identity lifecycle.** New `app/services/whatsapp/user_id_rotation_service.rb`:
  - handles `messages[].type == 'system'` with `system.type` in `user_changed_number` or `user_changed_user_id`;
  - records aliases and never merges;
  - hook point: `incoming_message_identifier_helper.rb:2-7`, and `whatsapp_events_job.rb:142-146` for the lock key.
  - At v4.14.1 these system messages had no handling.
- **Contacts.**
  - `contact_inbox_with_contact_builder.rb`: contact name is truncated to 255, and lookup uses `phone_number_candidates`.
  - `identifier_sync_service.rb`: `visitor` → `lead` when a BSUID source id is seen.
- **Echo contact.** `incoming_message_identifier_helper.rb:9-23`: the name falls back to `message[:to]` rather than the BSUID.
- **Contact-info request** (new, `send_on_whatsapp_service.rb:13, 22-28`, `contact_info_request_*`): agent-triggered interactive or template "share your number" requests to BSUID contacts. There is no feature flag in `config/features.yml`; availability is decided by `ContactInfoRequestEligibilityService`.
- **Schema.** No `contact_inboxes` schema change. Everything uses the existing `source_id`.

**Classification: SAFE AUTO-MERGE.** Lynomia does not touch these files. This is behaviour change for existing whatsapp_cloud contacts, and it is additive.

---

## 4. Webhook processing

### Commits
- `e65e18e9c` (#13709): `WebhookChannelFinderService`.
- `27c87bf0e` (#15706): tracking-only skip.
- `8a3b12929` (#13599): reauth-drop only for embedded signup.
- `11ecd7a30`, `07fa9ce88`: lock keys and system messages.
- `56e533cd0` (#14149): status regressions.

### `app/controllers/webhooks/whatsapp_controller.rb`
- `:13`, `:21-26`: webhooks whose changes are all `field == 'tracking_events'` return 200 and are not enqueued.
- `:53-63`: channel resolution by payload `metadata.display_phone_number` plus `phone_number_id`, via `Whatsapp::WebhookChannelFinderService`.
  - The finder tries `"+digits"`, then the BR/AR/MX-normalized number, and accepts a candidate only if `provider_config['phone_number_id']` matches (`webhook_channel_finder_service.rb:12-20`).
  - Fallback is the URL `:phone_number` (`:42`).
- **Signature verification is unchanged.** `app/controllers/concerns/meta_token_verify_concern.rb` has no diff between the tags. `meta_signature_verification_required?` (`whatsapp_controller.rb:45-51`, identical to v4.14.1 `:36-42`) is:
  - true when the channel is not found;
  - false for non-cloud providers;
  - true when `provider_config` has `app_secret`/`app_secret_key`/`client_secret`/`api_secret`;
  - otherwise true only for `source == 'embedded_signup'`.
  - Consequence: new `manual_setup_v2` channels do **not** require a signature unless an app-secret key is in `provider_config`.
- `INACTIVE_WHATSAPP_NUMBERS` rejection is unchanged (`:65-74`).

### `app/jobs/webhooks/whatsapp_events_job.rb`
- `:6`: `retry_on LockAcquisitionError, attempts: 20`.
- `:23-26`: 30s per-(inbox, sender) mutex.
- `:103-146`: sender id prefers parent BSUID > contact parent > BSUID > phone. System messages lock on the new identity.
- `:148-159` **reauth-required handling**:
  ```ruby
  return true if channel.reauthorization_required? && embedded_signup_channel?(channel)
  ```
  At v4.14.1 **all** channels with the reauth flag dropped webhooks; now only `source == 'embedded_signup'`.
- `:176-182`: payload channel lookup via the finder service.
- Still processes only `entry[0].changes[0]` and the first message (`incoming_message_whatsapp_cloud_service.rb:7-9`, `incoming_message_base_service.rb:38, 71`).

### Reauth triggers (v4.18.0)
- `authorization_error!` when media download returns 401 (`incoming_message_whatsapp_cloud_service.rb:18`).
- `prompt_reauthorization!` when webhook setup raises (`channel/whatsapp.rb:145-150`) or when the post-signup health check reports `NOT_APPLICABLE` (`embedded_signup_service.rb:70-81`).
- The new `HealthSyncJob` does **not** trigger reauth; it swallows `ApiError` and `ArgumentError`.
- `app/views/api/v1/models/_inbox.json.jbuilder:153-157`: `reauthorization_required` is now reported **only for embedded_signup** channels.

**Classification: SAFE AUTO-MERGE.** Behaviour change: manual whatsapp_cloud channels flagged for reauth now keep receiving webhooks.

---

## 5. Message echoes, dedupe, history and contact sync

- **Echoes (`smb_message_echoes`)**: the mechanism is unchanged.
  - Detected by `params.dig(:entry,0,:changes,0,:field) == 'smb_message_echoes'` (`whatsapp_events_job.rb:80-86`).
  - Processed by `IncomingMessageWhatsappCloudService.new(..., outgoing_echo: true)` into `message_type: :outgoing`, `status: :delivered`, `sender: nil`, `content_attributes.external_echo: true` (`incoming_message_base_service.rb:164-179`).
  - Blocked contacts are still processed for echoes (`:43`).
  - New: echo contact resolution uses `to_parent_user_id`/`to_user_id` with the same orderer as inbound (`incoming_message_identifier_helper.rb:67-77`).
- **Dedupe** is unchanged (`incoming_message_base_service.rb:34-39`, `incoming_message_service_helpers.rb:99-109`):
  - global `Message.find_by(source_id:)`;
  - plus `Whatsapp::MessageDedupLock` (Redis `SET NX EX 1.day`, `message_dedup_lock.rb`, no diff).
  - Statuses: `Messages::StatusUpdateService` now prevents out-of-order status regressions (`incoming_message_base_service.rb:61-68`, commit `56e533cd0`).
- **Unsupported or companion-device messages** (for example error 131060): stored as a placeholder with `is_unsupported` (`incoming_message_base_service.rb:81-91`). Present since before v4.14.1.
- **History sync (`history` webhook): NOT implemented.**
  - No subscription: `facebook_api_client.rb:4` `WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes]`, and `webhook_setup_service.rb:85-89` adds `calls` only when calling is enabled.
  - No handler: `git grep -i "smb_app_state_sync\|'history'\|history_sync\|smb_app_data"` over app, enterprise, lib and config returns nothing WhatsApp-related at either tag.
  - A stray `history` payload would fall through to `IncomingMessageWhatsappCloudService` and no-op, because there are no `messages`/`message_echoes`/`statuses` keys.
  - **No flag, no default. It does not exist.**
- **Contact sync (`smb_app_state_sync`): NOT implemented.** Same evidence as history sync.

**Classification: SAFE AUTO-MERGE / NOT RELEVANT** to the Lynomia code. If Lynomia wants history or contact import, it must build it. There is no upstream base.

---

## 6. Media, templates, statuses, calls, campaigns: behaviour changes for existing whatsapp_cloud channels

| Change | Evidence (v4.18.0) | Commit | Effect on existing channels | Class |
|---|---|---|---|---|
| **Media sent by upload + `media_id`** instead of `link` | `providers/whatsapp_cloud_service.rb:188-195`; `media_upload_service.rb:18-28, 32-35` (`WHATSAPP_MEDIA_UPLOAD_STRATEGY`, default `direct`; `link` restores the old behaviour); falls back to `link` on failure; attachment send uses Graph `v24.0` (`:150`) | `eb0d524de` (#15702) | Every outgoing attachment now does a multipart POST to `/{phone_number_id}/media` first. `faraday-multipart` is already in Gemfile.lock at v4.14.1 | SAFE AUTO-MERGE |
| Voice notes (`voice: true`, opus→ogg) | `whatsapp_cloud_service.rb` `voice_message?`, `normalize_opus_content_type` | `37eed5de1` (#14606) | Additive | SAFE |
| Template sync with Bearer header and cursor paging; `update_columns` plus cache-key bump; skips suspended accounts | `whatsapp_cloud_service.rb:35-62`; `templates_sync_scheduler_job.rb` (`joins(:account).merge(Account.active)`) | `3e03f8da1`, `081e08c7c`, `59eac9a7c` | Uses `template_access_token`, which is `api_key` unless Chatwoot Cloud with a business management token (`channel/whatsapp.rb:79-83`). Self-hosted: unchanged token | SAFE |
| `validate_provider_config?` also checks that `phone_number_id` belongs to the WABA whenever `provider_config` changes | `whatsapp_cloud_service.rb:64-76` (`phone_numbers?fields=id&limit=100`, no paging) | `b560720e0` | Any validated save that changes `provider_config` (reauth, `store_pin`, inbox settings update) makes one extra Graph call. It fails if the number is not in the first 100 of the WABA | SAFE (note) |
| Sending outside the 24h window without template params now fails immediately with `errors.whatsapp.message_outside_messaging_window` | `send_on_whatsapp_service.rb:8-20` | `166a41c31` (#15113) | v4.14.1 tried a template and failed with "Template not found…". Only the error text changes | SAFE |
| Template header TEXT params; numeric body params sorted | `template_processor_service.rb` | `9d769dfcd` (#15199), `e1270a4ef` (#15255) | Bug fixes | SAFE |
| Template rendering in transcript; template API endpoints `message_templates` (any agent: `inbox_policy.rb` `message_templates? → true`) | `inbox_health_management.rb:19-31` | `7142bc43a` (#15277), `1c28df49e` (#15311) | Additive | SAFE |
| Flow responses (`nfm_reply`), CTWA referral, interactive list row descriptions | `incoming_message_base_service.rb:178-195`; `providers/base_service.rb:80-119` | `781943867`, `de137e829`, `5dc47d2de` | Additive | SAFE |
| **Calls webhook field**: subscribe `calls` only when calling is enabled on this channel or any WABA sibling | `webhook_setup_service.rb:84-103` | `e055cead3` (#14718) | At v4.14.1 `calls` was always subscribed. On the next re-setup, WABAs without calling lose the `calls` field | SAFE |
| Per-inbox `inbound_calls_enabled` and `recording_enabled`/`transcription_enabled` in `provider_config`, default on | `channel/whatsapp.rb:59-62`; `enterprise/app/models/concerns/call_recording_settings.rb` | `8d5d02ea9`, `7bd4ecacf` | No migration. Absent keys mean on. Calling still needs the `channel_voice` feature (premium, default off) | SAFE |
| Call data migration `20260618000000_backfill_rejected_call_status.rb` | `UPDATE calls SET status='rejected' WHERE status='failed' AND end_reason='agent_rejected'` | `647cfc2d8` | Data backfill on `calls` (enterprise voice) | SAFE |
| **Campaigns**: `completed!` moved to after processing; BSUID recipients; auth-template guard; enterprise `CampaignRecipient` tracking plus status updates from WhatsApp status webhooks | `oneoff_campaign_service.rb`; `enterprise/.../oneoff_campaign_service.rb`; `enterprise/.../incoming_message_base_service.rb:4-16`; migration `20260807133000_create_campaign_recipients.rb` | `8ee2c7f43` (#15276), `9253468b3` (#15614), `f27bbef73` (#14592) | New table; `campaigns.started_at`/`completed_at` added. No backfill | SAFE |
| Health polling (new) | `health_sync_scheduler_job.rb`, `trigger_hourly_scheduled_items_job.rb:5`; `health_service.rb` forces Graph ≥ v24.0 (`:18, :46-47`) | `d644c207f` (#15100), `4a63be975`, `3479b1026` | **New outbound Graph traffic for every whatsapp_cloud channel of active accounts, every ≥6h**, using `api_key` | SAFE (ops note) |
| Webhook routing: **phone-number-level override** instead of WABA-level override | `facebook_api_client.rb:144-176` (`POST /{waba}/subscribed_apps {subscribed_fields}`, then `POST /{phone_number_id} {webhook_configuration:{override_callback_uri, verify_token}}`) | `7c7459b73` (#13817) | Existing channels keep whatever v4.14.1 set (a WABA-level `override_callback_uri` on `subscribed_apps`) until webhook setup is re-run (reauth, reconfigure, `register_webhook`, voice toggle). No automatic migration code exists | SAFE (ops note) |

---

## 7. Migrations touching `channel_whatsapp`

`db/migrate/20260718000000_add_phone_number_health_to_channel_whatsapp.rb` (`d644c207f`, #15100):
```ruby
add_column :channel_whatsapp, :phone_number_health, :jsonb, default: {}, null: false
add_column :channel_whatsapp, :phone_number_health_checked_at, :datetime
add_column :channel_whatsapp, :phone_number_health_error, :string, limit: 500
add_index :channel_whatsapp, :phone_number_health_checked_at
```

`db/migrate/20260728000001_add_business_management_token_to_channel_whatsapp.rb` (`59eac9a7c`, #15218):
```ruby
add_column :channel_whatsapp, :business_management_token, :text
```

**Backfill.** None needed or provided.
- Existing rows get `{}` / nil / nil / nil.
- The health scheduler orders `phone_number_health_checked_at IS NULL DESC`, so existing channels are polled first after deploy (in batches of `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`).
- The UI treats an empty `{}` as unknown.

**Existing channels with nil values keep working.**
- `template_access_token` falls back to `api_key` (`channel/whatsapp.rb:79-83`).
- The jbuilder only emits `business_management_token_configured` on cloud (`_inbox.json.jbuilder:148-152`).
- `serializable_hash` strips the token (`channel/whatsapp.rb:85-87`).

**Encryption**
- `app/models/channel/whatsapp.rb:31`: `encrypts :business_management_token if Chatwoot.encryption_configured?` is the **only** new `encrypts` for WhatsApp.
  - `Chatwoot.encryption_configured?` requires all three `ACTIVE_RECORD_ENCRYPTION_*` env vars (`config/application.rb:101-109`).
  - `support_unencrypted_data = true` and `extend_queries = true` are set when the primary key is present (`config/application.rb:75-85`), so plaintext values would remain readable.
  - The column is brand new and is only writable on Chatwoot Cloud (`business_management_token_service.rb:21-26`), so on self-hosted Lynomia it stays nil.
- **`provider_config.api_key` (the real per-number business token) is NOT encrypted**. `provider_config` is plain jsonb (`channel/whatsapp.rb:14`). Nothing changes for existing plaintext tokens; they are read as before.

**Edge risk (from code, not runtime-verified).**
- `phone_number_health_error` is `string, limit: 500`, and `HealthService` writes `truncate(500)` via `update_all` (`health_service.rb:190, 204`).
- `ApplicationRecord#validates_column_content_length` (`app/models/application_record.rb:8, 24-47`) caps every string column at 255 when no explicit length validator exists, and `Channel::Whatsapp` has none.
- A stored health error longer than 255 chars would therefore make the next **validated** save of that channel fail with "is too long". Such saves include reauth (`reauthorization_service.rb:40`), `store_pin` (`webhook_setup_service.rb:70`) and inbox settings updates.

**Other migrations** in range touching WhatsApp-adjacent data:
- `20260807133000_create_campaign_recipients.rb` (new table plus `campaigns.started_at`/`completed_at`);
- `20260618000000_backfill_rejected_call_status.rb` (data update on `calls`);
- `20260831000000_add_provider_name_to_social_channels.rb` (instagram, tiktok and facebook only; not WhatsApp).

**Schema version.** Upstream is `2026_08_31_000000`. Lynomia's custom migrations are `2026092610xxxx`–`20260928100000`, so the Lynomia `db/schema.rb` version stays higher. `db/schema.rb` itself will conflict and must be regenerated. That is expected and outside this scope.

**Classification: SAFE AUTO-MERGE** (upstream-only migrations; the schema.rb conflict is generic).

---

## 8. Security-relevant WhatsApp changes

**Role checks.** `app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb:2-5`:
```ruby
  before_action :ensure_embedded_signup_enabled
  # Reconfiguring/reauthorizing a live inbox swaps its credentials, so restrict it to admins.
  before_action :check_admin_authorization?, if: -> { params[:inbox_id].present? }
  before_action :fetch_and_validate_inbox, if: -> { params[:inbox_id].present? }
```
- Admin is required **only when `inbox_id` is present** (reauth or reconfigure).
- **New-inbox creation has no role check.** `spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb:50-69` and `:85-110` post with `agent.create_new_auth_token` and expect `:success`.
- `ensure_embedded_signup_enabled` (`:22-28`) is a no-op off Chatwoot Cloud.
- By contrast, manual setup v2 uses `authorize ::Inbox, :create?` (`manual_setup_controller.rb:39-41`).
- `can_reconfigure_channel?` (`:53-56`) allows any `whatsapp_cloud` inbox, including manual ones, for admins.

**`provider_config` in the browser.** `app/views/api/v1/models/_inbox.json.jbuilder:143-158`:
```ruby
### WhatsApp Channel
if resource.whatsapp?
  message_templates = resource.channel.try(:message_templates)
  json.message_templates message_templates.is_a?(Array) ? message_templates : []
  json.provider_config resource.channel.try(:provider_config) if Current.account_user&.administrator?
  if Current.account_user&.administrator? &&
     ChatwootApp.chatwoot_cloud? &&
     (resource.channel.try(:provider_config) || {}).to_h['source'] == 'embedded_signup'
    json.business_management_token_configured resource.channel.try(:business_management_token).present?
  end
  # Only show reauthorization for embedded signup; manual flow uses API keys, not OAuth
  json.reauthorization_required(
    (resource.channel.try(:provider_config) || {}).to_h['source'] == 'embedded_signup' &&
    resource.channel.try(:reauthorization_required?)
  )
end
```
- The full `provider_config` is still sent to administrators: `api_key`, `webhook_verify_token`, `verification_pin`, `phone_number_id`, `business_account_id`. The admin gate existed at v4.14.1 as well.
- `ConfigurationPage.vue:433` displays `api_key` for non-embedded inboxes. `Reauthorize.vue:215` reads `provider_config`.
- The new `business_management_token` is never serialized.

**`WHATSAPP_APP_SECRET`: still no `type: secret`.** `config/installation_config.yml:162-165` at v4.18.0:
```yaml
- name: WHATSAPP_APP_SECRET
  display_title: 'WhatsApp App Secret'
  description: 'The App Secret for WhatsApp Embedded Signup flow (required for embedded signup)'
  locked: false
```
Compare `FB_APP_SECRET` at `:131-134`, which has `type: secret`. It is grouped in super-admin `app_configs_controller.rb:67` (`'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION]`).

**Webhook teardown on inbox delete with a shared WABA.** `app/services/whatsapp/webhook_teardown_service.rb:6-17, 55-74`:
```ruby
  def perform
    return unless should_teardown_webhook?

    api_client = Whatsapp::FacebookApiClient.new(provider_config['api_key'])

    clear_phone_number_override(api_client)
    deregister_phone_number(api_client)
    unsubscribe_app_if_last_inbox(api_client)
  rescue StandardError => e
    # before_destroy must never block a channel delete — log and move on.
    Rails.logger.error "[WHATSAPP] Webhook teardown failed for channel #{@channel&.id}: #{e.message}"
  end
...
  # Embedded signup only — a manual token's subscribed app is the customer's, not ours to unsubscribe.
  # The subscription is shared across the WABA, so only unsubscribe when this is the last inbox.
  def unsubscribe_app_if_last_inbox(api_client)
    return unless provider_config['source'] == 'embedded_signup'

    waba_id = provider_config['business_account_id']
    return if waba_id.blank?
    return if waba_sibling_exists?(waba_id)

    api_client.unsubscribe_app_from_waba(waba_id)
    ...
  def waba_sibling_exists?(waba_id)
    Channel::Whatsapp
      .where.not(id: @channel.id)
      .exists?(["provider_config ->> 'business_account_id' = ?", waba_id])
  end
```
- The sibling check is installation-wide: any account, any provider or source.
- `should_teardown_webhook?` (`:25-29`) now applies to **all** whatsapp_cloud channels with an `api_key`, not only embedded signup. Manual channels get their phone-level override cleared.
- `deregister_phone_number` (`:41-53`) is embedded_signup only, but **runs regardless of siblings and regardless of coexistence**.
- v4.14.1 always did `DELETE /{waba}/subscribed_apps` for embedded-signup channels. The whole-WABA bug is fixed.
- Commits: `7c7459b73` (#13817), `b2716e15e` (#14940), `9328f8739` (#15010).

**Other security-relevant changes**
- The `debug_token` WABA-scope validation was removed (`f93f2067b`).
- Signature verification is unchanged (see §4).
- New admin-only endpoints: `whatsapp_business_management_token` (`inbox_policy.rb:69-71`, Cloud-only service) and `access_request` (enterprise, Cloud-only, `check_admin_authorization?`).
- Inbox `health` is admin-only (`inbox_policy.rb:73-75`); `register_webhook` requires admin (`inbox_health_management.rb:6`).

**Classification: SAFE AUTO-MERGE** (upstream-only). The open gaps are unchanged and remain a Lynomia decision:
- agents can create inboxes;
- `api_key` is plaintext and sent to admins;
- `WHATSAPP_APP_SECRET` is not masked.

---

## 9. `channel_creation_service.rb` and its spec

**Lynomia change** (`git diff v4.14.1 HEAD`): `build_inbox_name` returns `@phone_info[:phone_number]`. The spec expects `'+1234567890'` in 3 places.

**Upstream service.** `git diff v4.14.1 v4.18.0 -- app/services/whatsapp/channel_creation_service.rb` is empty, so the service is byte-identical. The v4.18.0 service still has `"#{business_name} WhatsApp"` at `:69-72`.

**Upstream spec.** One commit, `0e07a27c7` (#14949), adds `it 'does not leave an orphan channel when inbox creation fails'` after the "creates an inbox" example. It stubs `Inbox.create!` to raise `RecordInvalid` and expects no `Channel::Whatsapp` count change. It does not assert the name.

**Trial 3-way merge** (`git merge-file`, scratch copies)
- Service: 0 conflicts. The result is identical to Lynomia HEAD.
- Spec: 0 conflicts. The merged spec keeps Lynomia's `'+1234567890'` expectations (`:60`) and adds the new example (`:64-73`).
- `config/installation_config.yml`: 0 conflicts. Lynomia branding keys and upstream Meta/Shopify keys are in different regions.

**Semantics still hold.** Callers are unchanged: `EmbeddedSignupService#create_or_reauthorize_channel` still calls `Whatsapp::ChannelCreationService.new(@account, waba_info, phone_info, access_token).perform` (`embedded_signup_service.rb:64-66`). `phone_info[:phone_number]` is still `"+#{sanitized display_phone_number}"` (`phone_info_service.rb:60-69`). The transaction wrapper that the new spec relies on already exists (`:33-39`), and Lynomia's `Billing::InboxLimit` raises `RecordInvalid` from inside the same `Inbox.create!`, so a limit failure also rolls back the channel.

**Classification: REQUIRES MANUAL MERGE (review only).** Both sides touched the spec, but git merges it cleanly and it is semantically compatible. No edits expected; run the spec.

**Naming gaps around it**
- **CONFLICTS WITH LYNOMIA naming (pre-existing, unchanged).** `app/services/whatsapp/reauthorization_service.rb:42-44`:
  ```ruby
      # Update inbox name if business name changed
      business_name = phone_info[:business_name] || phone_info[:verified_name]
      channel.inbox.update!(name: business_name) if business_name.present?
  ```
  - This renames a Lynomia inbox from `+E164` to the verified business name on every reauth or reconfigure.
  - It was identical at v4.14.1, but v4.18.0 makes reconfigure ungated (`08b9992c4`) and coexistence reauth functional, so it will fire more often.
  - If Lynomia wants phone-number names everywhere, patch this too, or better, extract the naming into one place.
- **New upstream path with different naming.** Manual setup v2 suggests `"#{verified_name || phone_number} WhatsApp"` (`manual_setup_validation_service.rb:96`), and the user can override it (`manual_setup_service.rb:46`). Classification: REQUIRES MANUAL MERGE (behavioural) if Lynomia wants consistent naming.

---

## Classification summary

| Area / file(s) | Class |
|---|---|
| `app/services/whatsapp/channel_creation_service.rb` | SAFE AUTO-MERGE: upstream unchanged; Lynomia version kept (verified) |
| `spec/services/whatsapp/channel_creation_service_spec.rb` | REQUIRES MANUAL MERGE (review only): clean 3-way merge; new upstream example is name-agnostic |
| `app/services/whatsapp/reauthorization_service.rb` (inbox rename on reauth) | CONFLICTS WITH LYNOMIA naming: pre-existing, not introduced by 4.18 |
| `manual_setup_*` (new v2 flow; `source: 'manual_setup_v2'`; `"… WhatsApp"` name) | REQUIRES MANUAL MERGE (behavioural): decide the naming policy |
| `docs/whatsapp-qr/07-meta-coexistence-pivot.md` plan (card, `onboarding_method`, conditional `business_id`) | CONFLICTS WITH LYNOMIA plan: upstream took a different design; re-base the plan |
| `authorizations_controller.rb`, `embedded_signup_service.rb`, `phone_info_service.rb`, `webhook_setup_service.rb`, `facebook_api_client.rb`, `channel/whatsapp.rb`, `token_validation_service.rb` (deleted), frontend signup files (`Whatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `useWhatsappEmbeddedSignup.js`, `whatsapp/utils.js`, `whatsapp/Reauthorize.vue`, `ConfigurationPage.vue`) | SAFE AUTO-MERGE: behaviour Lynomia depends on (embedded signup), so run the specs and do a manual signup smoke test |
| Webhook controller, events job, finder, incoming services, BSUID services, identity orderer, rotation service, resolver, builder | SAFE AUTO-MERGE |
| Providers (media upload, `recipient`), templates, campaigns, calls, health jobs | SAFE AUTO-MERGE (ops notes: Graph traffic, media upload strategy env) |
| Migrations `20260718000000`, `20260728000001` (and campaign/calls ones) | SAFE AUTO-MERGE; `db/schema.rb` needs regeneration (generic conflict) |
| `_inbox.json.jbuilder`, `installation_config.yml` WhatsApp keys | SAFE AUTO-MERGE (installation_config merge verified clean) |
| Billing interplay (`Billing::InboxLimit` + upstream enterprise `ensure_create_permitted`; `InboxesController#validate_limit` removed) | SAFE: Lynomia's validation still applies to embedded signup; error surfaces as 422 via `render_embedded_signup_error` |
| `DISABLE_META_INBOX_CREATION` (default true), `whatsapp_embedded_signup_inbox_creation` flag, access request | NOT RELEVANT on self-hosted (effective only when `DEPLOYMENT_ENV == 'cloud'`) |
| Business management token (column, UI, endpoints) | NOT RELEVANT on self-hosted (Cloud-only); column stays nil |
| History / contact sync | NOT RELEVANT (not implemented upstream) |

---

## Upstream WhatsApp specs at v4.18.0 (to run later)

### Ruby, core
- spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb
- spec/controllers/api/v1/accounts/whatsapp_business_management_token_spec.rb
- spec/controllers/webhooks/whatsapp_controller_spec.rb
- spec/controllers/api/v1/accounts/inboxes_controller_spec.rb (WhatsApp health, templates, register_webhook, update paths)
- spec/jobs/webhooks/whatsapp_events_job_spec.rb
- spec/jobs/channels/whatsapp/health_sync_job_spec.rb
- spec/jobs/channels/whatsapp/health_sync_scheduler_job_spec.rb
- spec/jobs/channels/whatsapp/templates_sync_job_spec.rb
- spec/jobs/channels/whatsapp/templates_sync_scheduler_job_spec.rb
- spec/models/channel/whatsapp_spec.rb
- spec/models/contact_inbox_spec.rb
- spec/models/application_record_external_credentials_encryption_spec.rb (`business_management_token` encryption; skips without keys)
- spec/builders/contact_inbox_with_contact_builder_spec.rb
- spec/services/whatsapp/*_spec.rb, i.e.:
  - `authentication_template_guard`, `business_management_token_service`, `business_management_token_validation_service`, `business_profile_service`
  - `channel_creation_service`
  - `contact_info_request_eligibility_service`, `contact_info_response_service`, `csat_template_service`
  - `embedded_signup_service`, `facebook_api_client`, `health_service`, `identifier_sync_service`, `in_reply_to_message_finder`
  - `incoming_message_service`, `incoming_message_whatsapp_cloud_service`
  - `liquid_template_processor_service`, `media_upload_service`, `message_dedup_lock`, `oneoff_campaign_service`, `phone_info_service`
  - `phone_normalizers/brazil_phone_normalizer`, `phone_normalizers/mexico_phone_normalizer`, `phone_number_normalization_service`
  - `populate_template_parameters_service`
  - `providers/whatsapp360_dialog_service`, `providers/whatsapp_cloud_service`
  - `reauthorization_service`, `send_on_whatsapp_service`, `template_parameter_converter_service`, `template_processor_service`, `token_exchange_service`
  - `user_id_rotation_service`, `webhook_setup_service`, `webhook_teardown_service`
- spec/services/twilio/incoming_message_service_spec.rb, spec/services/twilio/send_on_twilio_service_spec.rb (Twilio WhatsApp BSUID paths)

### Ruby, enterprise
- spec/enterprise/controllers/api/v1/accounts/whatsapp_calls_controller_spec.rb
- spec/enterprise/services/enterprise/whatsapp/incoming_message_base_service_spec.rb
- spec/enterprise/services/enterprise/whatsapp/oneoff_campaign_service_spec.rb
- spec/enterprise/services/enterprise/whatsapp/providers/base_service_spec.rb
- spec/enterprise/services/enterprise/whatsapp/providers/whatsapp_cloud_service_spec.rb
- spec/enterprise/services/whatsapp/{call_permission_reply_service,call_permission_request_service,call_service,inbound_call_identity_builder,incoming_call_service}_spec.rb
- spec/enterprise/services/voice/inbound_call_builder_spec.rb
- spec/enterprise/models/inbox_spec.rb (inbox limit)

### JavaScript (Vitest)
- app/javascript/dashboard/composables/spec/useWhatsappEmbeddedSignup.spec.js
- app/javascript/dashboard/routes/dashboard/settings/inbox/components/specs/AccountHealth.spec.js
- app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/specs/ConfigurationPage.spec.js
- app/javascript/dashboard/routes/dashboard/settings/inbox/specs/Settings.spec.js
- app/javascript/dashboard/routes/dashboard/settings/inbox/specs/FinishSetup.spec.js
- app/javascript/dashboard/routes/dashboard/onboarding/specs/inbox-setup/{useDetectedChannels,InboxChannelsDialog,channelMatchers}.spec.js
- app/javascript/dashboard/components-next/whatsapp/specs/WhatsAppTemplateParser.spec.js
- app/javascript/dashboard/components-next/message/bubbles/specs/WhatsappFlowResponse.spec.js
- app/javascript/dashboard/components-next/message/helpers/specs/whatsappFlowResponse.spec.js
- app/javascript/dashboard/api/specs/inboxes.spec.js
- app/javascript/dashboard/store/modules/specs/inboxes/{actions,getters}.spec.js

---

## Recommended follow-ups (Lynomia decisions, not upstream bugs)

1. **Naming consistency.** Patch `ReauthorizationService#update_channel_config` (`:42-44`) and decide on the manual-v2 default name if all WhatsApp inboxes must be named by phone number.
2. **Coexistence plan re-base.**
   - If a persisted marker is required, add it in `ChannelCreationService#build_provider_config` from `EmbeddedSignupService` (which already has `@is_coexistence`), or rely on `phone_number_health['is_on_biz_app']`.
   - Consider guarding `WebhookTeardownService#deregister_phone_number` for coexistence numbers (**VERIFY-META** what `/deregister` does to a coexistence number).
3. **Security gaps still open in 4.18.** Upstream did not fix these; they remain Lynomia's decision:
   - admin check for new-inbox creation in `AuthorizationsController`;
   - `type: secret` for `WHATSAPP_APP_SECRET`;
   - `api_key` plaintext and returned to admins.
4. **Post-deploy ops.**
   - Expect a burst of health-sync Graph calls. The scheduler prioritises NULL `phone_number_health_checked_at` and is capped per run by `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`.
   - Media now uploads via `/media` (set `WHATSAPP_MEDIA_UPLOAD_STRATEGY=link` to revert).
   - Webhook overrides move to phone level only when setup re-runs.
   - Optionally audit `provider_config.business_account_id` on channels reauthorized under 4.14.1 via the non-stored-config path. The portfolio-id bug has no backfill.
5. **Edge risk.** Watch for `phone_number_health_error` values longer than 255 chars blocking validated channel saves (§7).
