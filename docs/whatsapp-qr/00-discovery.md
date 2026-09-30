# WhatsApp QR (Evolution API): Phase A Discovery

> **Status: PAUSED / FALLBACK ONLY (2026-09-29).** No Evolution API code was written or installed. Existing WhatsApp Business App numbers are now connected through Meta Embedded Signup (Coexistence); see `docs/whatsapp-business/README.md`. This discovery is kept as architectural history.

| | |
|---|---|
| Phase | A: discovery only. No production code, Evolution install, Chatwoot change or WhatsApp change was made. |
| Repo state | branch `claude/laughing-albattani-8yi0kh`, HEAD `85fddcd3`, upstream base Chatwoot 4.14.1 (`d58b6a6c`) |
| Date | 2026-09-29 |
| Method | Six independent code-reading passes, each followed by a fact-check pass that re-opened every cited file and line (164 claims: 121 verified, 43 corrected (mostly line numbers), 0 refuted). Corrected values are used below. Evolution facts come from its primary sources at git tag `2.3.7` / `2.4.0-rc2` (raw.githubusercontent.com) and Docker Hub metadata. github.com itself is blocked from this environment. |

Every claim below cites `path:line` in this repo or a pinned upstream URL. "Not found" claims state the search that was run.

---

## 0. Summary

1. **Lynomia Chat is not a separate backend.** It is this Rails app, a Chatwoot 4.14.1 fork. Lynomia-specific code lives in `custom/`, loaded as a third extension layer after `enterprise/` (`lib/chatwoot_app.rb:36-44`, `config/application.rb:51-57`). There is no separate "Chatwoot integration" to call. Chatwoot's models and services are in-process.
2. **The tenant is `Account`, 1:1 with a company.** There is no other tenant, organisation or workspace model (see Q6).
3. **There is no channel provider abstraction.** The only provider pattern is private to `Channel::Whatsapp` (`app/models/channel/whatsapp.rb:27-31, 59-65`). Adding a QR provider there would modify official WhatsApp code (Q3, Q13).
4. **No QR, Baileys or Evolution code exists** in the repo or its history (Q1 evidence).
5. **Evolution's built-in Chatwoot bridge conflicts with several of our hard requirements.** It finds the inbox by name, needs an admin *user* token stored in plain text in Evolution's DB, exposes an unauthenticated webhook, rewrites identifiers of shared contacts, and needs Chatwoot to call Evolution, which SafeFetch blocks on private networks (section 2.4). This triggers several **stop conditions** (section 4). An architecture decision is needed before Phase B.
6. **Version:** the latest *stable* Evolution release is `v2.3.7` (2025-12-05, Baileys `7.0.0-rc.9`). `2.4.0` is still RC and adds a **mandatory license activation plus phone-home heartbeat**. Docker `latest` matches no release digest.
7. **License:** Apache-2.0 plus extra conditions. One requires a notice that Evolution API is used, **visible to system administrators**. This is compatible with "no Evolution branding for end users" only if the notice lives in a super-admin or docs surface. It needs your confirmation.

---

## 1. Discovery questions

### Q1. Where are channels managed?

- **Models:** one ActiveRecord model per type under `app/models/channel/*.rb` (api, email, facebook_page, instagram, line, sms, telegram, tiktok, twilio_sms, twitter_profile, web_widget, whatsapp). All include `Channelable` (`app/models/concerns/channelable.rb:1-13`: `belongs_to :account`, `has_one :inbox, as: :channel, dependent: :destroy_async`, `after_update :create_audit_log_entry`, `Channelable.prepend_mod_with('Channelable')`).
- **Central create path:** `Api::V1::Accounts::InboxesController#create` builds the channel and the inbox in one transaction (`app/controllers/api/v1/accounts/inboxes_controller.rb:33-46`). The allowed types are hard-coded as `%w[web_widget api email line telegram whatsapp sms]` (`:93-101`); enterprise adds `voice` via `prepend_mod_with` (`enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb:38-58`, hook at `inboxes_controller.rb:191`).
- **Other create paths:**
  - Twilio: `channels/twilio_channels_controller.rb:50-63`.
  - WhatsApp embedded signup: `whatsapp/authorizations_controller.rb:17-24` → `Whatsapp::ChannelCreationService` (`app/services/whatsapp/channel_creation_service.rb:33-39`).
  - Facebook: `callbacks_controller.rb:14`.
  - Instagram, TikTok, Twitter callbacks.
  - Email OAuth: `oauth_callback_controller.rb:66-75`.
  - Platform email migrations: `platform/api/v1/email_channel_migrations_controller.rb:59-74`.
- **Absence of QR/Evolution code:** a case-insensitive search for `evolution|baileys|linked.device|whatsapp_web|whatsapp_qr` over app, custom, enterprise, config, lib and db matched only unrelated text: `config/llm_models.json:40020`, and the i18n key `WHATSAPP_QR_INSTRUCTION` used for the wa.me *test* QR in `FinishSetup.vue`. `git log -S baileys` found nothing.

### Q2. Where are Chatwoot inboxes managed?

- **Model:** `app/models/inbox.rb`. It has `belongs_to :channel, polymorphic: true, dependent: :destroy` (`:60-80`), and extension hooks `Inbox.prepend_mod_with('Inbox')`, `include_mod_with('Audit::Inbox')` and `include_mod_with('Concerns::Inbox')` (`:269-271`).
- **Update:** `inboxes_controller.rb:48-54` updates the inbox, then the channel through its `EDITABLE_ATTRS`.
- **Destroy is asynchronous:**
  - `inboxes_controller.rb:77-80` enqueues `DeleteObjectJob`.
  - The job first batch-deletes `conversations`, `contact_inboxes` and `reporting_events` (`app/jobs/delete_object_job.rb:18-23`), then runs `inbox.destroy!`, which takes the channel with it.
  - **Contacts are not deleted. Conversation history is deleted.** This matters for "Delete QR connection" (section 3.12).
- **Events:** create and update dispatch `INBOX_CREATED`/`INBOX_UPDATED` (`inbox.rb:82-83`).
- **Plan limits:**
  - `Billing::InboxLimit` (custom) validates *every* inbox create (`config/initializers/billing.rb:5-12`, `custom/app/models/billing/inbox_limit.rb:8-19`) and fails with 422.
  - Separately, the core `validate_limit` (`app/helpers/api/v1/inboxes_helper.rb:118-122`) returns **402** on `InboxesController#create` only.

### Q3. Is there a provider/adapter abstraction for channels?

**No general one.** The evidence:
- The only provider pattern is inside `Channel::Whatsapp`: `PROVIDERS = %w[default whatsapp_cloud]` (`app/models/channel/whatsapp.rb:27-31`, inclusion validation), and a two-way `provider_service` switch (`:59-65`) backed by `Whatsapp::Providers::BaseService` (`app/services/whatsapp/providers/base_service.rb:1-42`).
- `Channel::Sms` and `Channel::Email` have a `provider` column but no service layer. Twilio uses a `medium` enum (`app/models/channel/twilio_sms.rb:51`).
- Outbound sending uses a frozen class-to-service map in `SendReplyJob` (`app/jobs/send_reply_job.rb:4-16`). That map has no `prepend_mod_with`, and it returns early for unknown channel classes (`:24-25`).
- Inbound handling is per-channel webhook controllers and jobs.

**Consequence:** adding `EvolutionQrProvider` into `Channel::Whatsapp` would require editing official files. Those edits are listed in Q13. A new, small `WhatsappQr::Provider` interface under `custom/` (section 3.12) is the only way to meet "Evolution must be replaceable" without touching official code.

### Q4. Where are secrets stored?

| Store | Where | At rest | Evidence |
|---|---|---|---|
| Installation-wide settings | `installation_configs.serialized_value` (YAML in jsonb). `locked` defaults to true. | **Plain text** (no `encrypts`) | `app/models/installation_config.rb:35, 44-50`; `db/schema.rb:965-970` |
| Cached global config | Redis `$alfred`, expiry 1 day | Plain-text JSON | `lib/global_config.rb:4, 44-47` |
| `GlobalConfigService.load` ENV fallback | Copies the ENV value into a **`locked: false`** row, which is visible in super admin | Plain text | `lib/global_config_service.rb:8-12` |
| Lynomia `Billing::Settings` (Stripe keys) | `locked: true` InstallationConfig rows; direct DB read; masked display | **Plain text** | `custom/app/services/billing/settings.rb:3-9, 24, 37-43, 72-76` |
| Per-channel credentials | Channel columns. Some use `encrypts ... if Chatwoot.encryption_configured?` | Encrypted **only if** the AR encryption ENV keys are set | Q5 |
| Env-only secrets | `.env` | n/a | `.env.example` |

Also relevant:
- The super admin generic config page lists only `locked: false` rows and prints them raw (`app/controllers/super_admin/installation_configs_controller.rb:24-26`, `app/fields/serialized_field.rb:4-5`).
- `SuperAdmin::AppConfigsController` renders `secret`-type values back into the password field (`app/views/super_admin/app_configs/show.html.erb:38-43`).
- The dashboard receives only an allow-listed set of configs (`app/controllers/dashboard_controller.rb:4-5, 47`).

### Q5. How are credentials encrypted?

- **Setup:** ActiveRecord encryption is configured only when `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` is set (`config/application.rb:83-93`). The guard is `Chatwoot.encryption_configured?`, which needs all three keys (`config/application.rb:109-117`). The keys are commented out in `.env.example:9-14`, and there are no Rails credentials files.
- **Encrypted when keys are present:**
  - Telegram `bot_token`, deterministic because the webhook looks it up (`app/models/channel/telegram.rb:21`).
  - Instagram (`instagram.rb:23`).
  - TwilioSms (`twilio_sms.rb:35`).
  - Email passwords (`email.rb:45-47`).
  - Line, TikTok, FacebookPage, TwitterProfile.
  - `WebhookSecretable#secret` (`app/models/concerns/webhook_secretable.rb:4-6`).
  - Integrations hooks.
- **Always encrypted:** User MFA fields (`app/models/user.rb:84-85`).
- **Not encrypted:**
  - `Channel::Whatsapp.provider_config`, which holds `api_key` (`db/schema.rb:650-654`, no `encrypts` in the model).
  - `Channel::Api.hmac_token` (`app/models/channel/api.rb:29`).
  - All InstallationConfig values, including `Billing::Settings` secrets.
- **Unused capability:** `ActiveRecord::Encryption.encryptor.encrypt/decrypt` exists in Rails 7.1.5.2 but is used nowhere in the repo.
- **CI gap:** the encryption spec examples always skip in this fork. `.github/workflows/run_mfa_spec.yml` triggers only on `pull_request` and is guarded to `chatwoot/chatwoot` (`:5-6, :17`).
- **Unknown:** whether production sets the `ACTIVE_RECORD_ENCRYPTION_*` keys cannot be determined from the repo.

### Q6. How does tenant isolation work?

- **Tenant model:** `Account` is the only tenant (`app/models/account.rb:25`, `db/schema.rb:62`). A search for tenant, organisation or workspace tables found only enterprise `companies` (`db/schema.rb:662`). That table is a **contact CRM record** that `belongs_to :account` (`enterprise/app/models/company.rb:23, 38-39`), not a tenant.
- **Request scoping:**
  - `Api::V1::Accounts::BaseController` runs `current_account` (`app/controllers/api/v1/accounts/base_controller.rb:1-5`).
  - That loads `Account.find(params[:account_id])`, returns 401 if the account is suspended, and returns 401 unless the user has an `AccountUser` row (`app/controllers/concerns/ensure_current_account_helper.rb:10-11, 22-24`).
  - It then sets the thread-local `Current.account` and `Current.account_user` (`lib/current.rb:2-4`), which are reset after each request (`app/controllers/concerns/request_exception_handler.rb:21-23`).
- **Authentication** (`app/controllers/api/base_controller.rb:4-12`):
  - Either an `api_access_token` header (a User or AgentBot owner),
  - or devise_token_auth headers.
  - AgentBot tokens are limited to an allow-list (`app/controllers/concerns/access_token_auth_helper.rb:2-6, 29-34`).
- **Authorization:**
  - Pundit is **opt-in**. There is no `verify_authorized` anywhere (grep), so a controller without `authorize` is open to every account member.
  - The embedded-signup WhatsApp controller is an upstream example with no `authorize` call.
- **Channel-to-account consistency:** nothing validates that a channel and its inbox belong to the same account. Consistency comes from always creating through `Current.account.<assoc>` (`inboxes_controller.rb:36`, `app/helpers/api/v1/inboxes_helper.rb:106-116`). New code must do the same.
- **Webhook endpoints** are `ActionController::API` controllers identified by a channel key in the URL. They are outside account auth and outside the billing guard (`config/routes.rb:612-620`).

### Q7. How is company mapped to a Chatwoot account?

**1:1, and they are the same record.**
- Lynomia's custom code treats `Account` as the company. Mobile sign-up creates a "new company account" with `AccountBuilder`, which makes the user an administrator (`custom/app/services/mobile_auth/sign_in.rb:7, 59`; `app/builders/account_builder.rb:65-68`).
- A subscription belongs to exactly one account (unique index, `custom/db/migrate/20260926100100_create_billing_subscriptions.rb:7-9`).
- `accounts.id` is a serial **integer**. New foreign keys must use `type: :integer` (same migration, `:6-7`).
- **External system:** there is evidence of a Lynomia admin site outside this repo. The legacy billing page redirects to `https://lynomia.com/admin/subscriptions/:id` (`app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue:9`), and the custom billing Platform API serves Platform-App callers (`custom/app/controllers/platform/api/v1/billing/base_controller.rb:3-7`). Its nature cannot be determined from the repo.

### Q8. How is a channel linked to an inbox?

- **The link:** polymorphic `inboxes.channel_type` / `channel_id`, one-to-one **by convention only**. The DB index `index_inboxes_on_channel_id_and_channel_type` is **not unique** (`db/schema.rb:961`), and there is no uniqueness validation.
- **Type label:** `inbox_type` comes from `channel.name`; for `Channel::Api` that is `'API'` (`app/models/inbox.rb:178-180`, `app/models/channel/api.rb:34-36`).
- **Contacts:** a contact is linked to an inbox through `contact_inboxes`, which is unique on `(inbox_id, source_id)` (`db/schema.rb:687`).

### Q9. Where are channel permissions?

- **Policy:** `app/policies/inbox_policy.rb`.
  - `create?`, `update?`, `destroy?`, `campaigns?`, `sync_templates?` and the other management actions are **administrator-only** (`:37-67`).
  - `show?` and `Scope` use `user.assigned_inboxes`: all inboxes for admins, member inboxes for agents (`:13-14, 22-26`; `app/models/user.rb:136-137`).
  - No enterprise module overrides `InboxPolicy` (there is no `enterprise/app/policies/enterprise/inbox_policy.rb`).
- **Controller wiring:** `InboxesController` runs `check_authorization` on every action except `show` (`inboxes_controller.rb:7`). It authorizes the Inbox *class*, not the record (`app/controllers/api/base_controller.rb:14-17`).
- **Roles:** `AccountUser` has `agent: 0, administrator: 1` (`app/models/account_user.rb:34-35`).
- **Custom roles:** enterprise custom roles cover only conversations, contacts, reports and knowledge base (`enterprise/app/models/custom_role.rb:31-38`). None covers channels.
- **Frontend:** every inbox settings route requires `permissions: ['administrator']` (`app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:74-79`).
- **Admin-only pattern outside a policy method:** `app/controllers/api/v1/accounts/concerns/whatsapp_health_management.rb:5-6` combined with `api/base_controller.rb:20-22`.
- **Rate limiting:**
  - `config/initializers/rack_attack.rb`, enabled only in production (`:280`).
  - Global limit of 3000 requests per minute per IP (`:70`).
  - Per-account path throttles (template at `:207-210`).
  - No rules for `/webhooks/*`.
  - Safelist: `127.0.0.1`, `::1` and `RACK_ATTACK_ALLOWED_IPS` (`:28-31`).
- **CSRF** is skipped for `ApplicationController` (`app/controllers/application_controller.rb:7`). Webhook and platform controllers are `ActionController::API`.

### Q10. Where are audit events?

- **Mechanism:** the `audited` gem 5.4.1 with `config.audit_class = 'Enterprise::AuditLog'` (`Gemfile:181`, `config/initializers/audited.rb:3-5`, `enterprise/app/models/enterprise/audit_log.rb:29-42`). The `audits` table is core schema (`db/schema.rb:229-249`).
- **Audited models:** Account, AccountUser, AgentBot, AutomationRule, Conversation (destroy), Inbox (create and update, `enterprise/app/models/enterprise/audit/inbox.rb:5`), InboxMember, TeamMember, Macro, Team, User (sign_in and sign_out) and Webhook.
- **Channel updates:** every channel update is audited with `saved_changes.except('updated_at','secret')` (`enterprise/app/models/enterprise/channelable.rb:20-34`). **Secrets stored in any other channel column would be copied into `audits`.**
- **Inbox deletes** are audited through `enterprise/app/jobs/enterprise/delete_object_job.rb:15-24`.
- **Custom named actions are possible:** `action` is a free string, and upstream writes `sign_in` by hand (`enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb:27-37`; `enterprise/app/models/enterprise/audit/inbox_member.rb:22-29`). Inside requests the Sweeper fills user, IP and `request_uuid`. In jobs the user is nil, which the UI shows as "System".
- **Limits:**
  - The UI renders only hard-coded action keys (`app/javascript/dashboard/helper/auditlogHelper.js:12, 209-218`).
  - `audit_logs` is a **premium** feature that is off by default (`config/features.yml:103-106`). Reconcile turns it off on the `community` pricing plan (`enterprise/app/services/internal/reconcile_plan_config_service.rb:4, 52-57`), and Lynomia plans cannot grant premium features (`custom/app/models/billing_plan.rb:34-40`).
  - Rows are written but **probably not visible to account admins**.
  - There is no audit retention.
  - `Enterprise::AuditLog` does not exist in CE builds (`.github/workflows/publish_foss_docker.yml:48` runs `rm -rf enterprise`), so writers must guard with `defined?`.

### Q11. Where is the frontend for adding and managing channels?

- **Add flow:** `ChannelList.vue` (the tile grid, route `settings_inbox_new`) → `ChannelFactory.vue` (`channelViewList[key]`) → `channels/*.vue` → `settings_inboxes_add_agents` → `settings_inbox_finish`. Evidence: `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:52-84`, `ChannelList.vue:112-118`, `ChannelFactory.vue:17-31`.
- **WhatsApp tile:** `ChannelList.vue:38-43` → `channels/Whatsapp.vue`. That page has a fixed provider picker (`:15-22, 37-50`), and unknown provider values fall back to `CloudWhatsapp` (`:141`).
- **Sibling precedent:** `whatsapp_call` is a *second* WhatsApp tile with its own page (`ChannelList.vue:98-103`, `channels/WhatsappCall.vue:1-10`).
- **Enablement:** tiles are enabled by an allow-list in `app/javascript/dashboard/components/widgets/ChannelItem.vue:67-78`.
- **Inbox settings:** `Settings.vue`. API inboxes get a Configuration tab (`:198-213`), and admins can edit `webhook_url` and reset the secret (`:781-820`). Every save re-sends `webhook_url` (`:596-599`).
- **Store and API:**
  - `store/modules/inboxes.js:213-221` (`createChannel`).
  - `store/modules/inboxes/channelActions.js:35-42` (extension actions).
  - `helper/inbox.js:1-14, 50` (type and icon maps).
  - `settings/inbox/components/ChannelName.vue:46-49`: the API label, which is overridable installation-wide by `apiChannelName`.
- **QR rendering:** the `qrcode` npm package is already a dependency (`package.json:90`; used in `FinishSetup.vue:111-118` and `MfaSetupWizard.vue:4`).
- **Code style:** `WhatsappCall.vue` uses `<script setup>`, as CLAUDE.md requires. The existing `Api.vue` uses the Options API.

### Q12. How does official WhatsApp work today?

1. **Model**
   - `Channel::Whatsapp` has `PROVIDERS = %w[default whatsapp_cloud]` (`app/models/channel/whatsapp.rb:27-31`).
   - `phone_number` is **globally unique**, both in the model and in the DB (`:32`, `db/schema.rb:659`).
   - Callbacks: `after_create :sync_templates`, `before_destroy :teardown_webhooks`, and `setup_webhooks` for cloud without embedded signup (`:35-37, 137-141`).
   - **There is no `prepend_mod_with` hook** (grep).
2. **Create paths**
   - Generic: `InboxesController#create` maps `'whatsapp'` to `Channel::Whatsapp` (`inboxes_controller.rb:174-184`).
   - Embedded signup: `routes.rb:336-338` → `AuthorizationsController:17-24` → `EmbeddedSignupService` (`app/services/whatsapp/embedded_signup_service.rb:11-33`) → `ChannelCreationService` (provider `whatsapp_cloud`, source `embedded_signup`, `:41-57`).
   - The fork already changed `build_inbox_name` to return the phone number (`channel_creation_service.rb:69-71`). This is the fork's only WhatsApp code change compared with upstream.
3. **Inbound**
   - Route: `post 'webhooks/whatsapp/:phone_number'` (`config/routes.rb:616-617`).
   - `Webhooks::WhatsappController`: the Meta signature is checked **only for whatsapp_cloud** (`:36-42`). The controller enqueues `Webhooks::WhatsappEventsJob` (`:13`).
   - The job locks per inbox and sender (`:16-26`), then switches on provider (`:79-86`). It does have `prepend_mod_with` (`:159`).
   - `Whatsapp::IncomingMessageBaseService` does the dedupe: DB lookup of `source_id` plus a Redis SET NX lock (`:36-46`; `app/services/whatsapp/message_dedup_lock.rb:5-18`). It also handles contacts, conversations and attachments.
4. **Outbound:** `SendReplyJob` → `Whatsapp::SendOnWhatsappService`. It sends a template when there are template params or `!can_reply?`, otherwise `channel.send_message` (`app/services/whatsapp/send_on_whatsapp_service.rb:8-15, 40-43`). The 24-hour window is hard-coded for `Channel::Whatsapp` (`app/services/conversations/message_window_service.rb:27-28`).
5. **Templates:** synced on create, and re-synced every 3 hours for every `Channel::Whatsapp` (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-9`).
6. **Frontend:** `useInbox.js:112-130` derives the WhatsApp flags. `ReplyBox.vue:197-200` and `MessagesView.vue:135` gate templates and the 24-hour UX.

### Q13. What can be reused without touching the official provider?

**Callable as-is (they depend only on inbox, contact_inbox or source_id):**
- `Whatsapp::PhoneNumberNormalizationService` (`app/services/whatsapp/phone_number_normalization_service.rb:14-30`; already called from Twilio at `app/services/twilio/whatsapp_identifier_helper.rb:41`).
- The `Whatsapp::PhoneNormalizers::*` classes.
- `ContactInboxSourceIdResolver` (`app/services/contact_inbox_source_id_resolver.rb:1-6`).
- `ContactInboxWithContactBuilder`, which finds a contact by identifier, then email, then phone, and retries on `RecordNotUnique` (`app/builders/contact_inbox_with_contact_builder.rb:8-14, 62-69`).
- `Whatsapp::IdentifierSyncService`, which stores alternate ids such as LID next to the phone number (`app/services/whatsapp/identifier_sync_service.rb:1-5`).
- `Whatsapp::MessageDedupLock`.
- `MutexApplicationJob#with_lock` (`app/jobs/mutex_application_job.rb:17-32`).
- `Messages::MarkdownRendererService.new(content, 'Channel::Whatsapp')` for WhatsApp formatting.
- `Messages::MessageBuilder`, which allows `incoming` only on `Channel::Api` (`app/builders/messages/message_builder.rb:98-104`) and passes `source_id` through (`:132-146`).
- `Messages::StatusUpdateService`.

**Would require editing official code if QR lived inside `Channel::Whatsapp` (excluded):**
- `whatsapp.rb:27-31` (PROVIDERS and validation).
- `:59-65` (`provider_service`).
- `:35-37, :118, :137-141` (callbacks and template sync).
- `whatsapp_controller.rb:36-42, 64-73`.
- `whatsapp_events_job.rb:79-86, 135-156`.
- `message_window_service.rb:27-28`, where the 24-hour window would force template sends.
- `contact_inbox.rb:69-77`, whose digits-only `source_id` regex rejects `@lid` and group JIDs.
- `templates_sync_scheduler_job.rb:5`.
- `Whatsapp.vue:15-22, 37-50, 131-141`.
- `useInbox.js:112-130`.

**Extension hooks available without editing** (`prepend_mod_with` picks up `Custom::` modules, `lib/chatwoot_app.rb:36-44`):
- `InboxesController` (`:191`)
- `Inbox` (`inbox.rb:269-271`)
- `Conversation` (`conversation.rb:367`)
- `ContactInboxBuilder` (`contact_inbox_builder.rb:107`)
- `Contacts::ContactableInboxesService` (`:75`)
- `Webhooks::WhatsappEventsJob` (`:159`)
- `TriggerScheduledItemsJob` (`trigger_scheduled_items_job.rb:25`)
- `Channelable` (`channelable.rb:13`)

**Hooks that do not exist:** `Channel::Whatsapp`, `SendReplyJob`, `MessageWindowService`, `WhatsappController`, `SendOnWhatsappService`, `IncomingMessageBaseService`, `ContactInbox` (grep: 0 hooks).

### Q14. What is the current deployment topology?

**It cannot be determined from the repo.**
- Every deployment artifact is unchanged from upstream: `docker/`, compose files, `Procfile*`, `deployment/`, `Capfile`, `app.json`, `clevercloud/`, `.env.example`. Running `git diff d58b6a6c --stat` on them shows no changes.
- `docker-compose.production.yaml:4-8` pulls **`chatwoot/chatwoot:latest`**, which does not contain `custom/`, so it cannot be what runs Lynomia. It defines rails, sidekiq, `pgvector/pgvector:pg16` and `redis:alpine` bound to 127.0.0.1, with no `networks:` and no healthchecks (`:15-16, 37-58`).
- The `Capfile` is dead: there is no `config/deploy*` and no capistrano in `Gemfile.lock`.
- The upstream VM installer uses PG16, pgvector, Redis 7 or newer, nginx and systemd units (`deployment/setup_20.04.sh:245, 878`; `deployment/chatwoot-worker.1.service:10-20`; `deployment/nginx_chatwoot.conf:1-4`).
- **Signals:**
  - The fork commits are authored by `root <root@server2.lynomia.com>`, which suggests code committed directly on a single self-managed host.
  - Production is `chat.lynomia.com` (`config/installation_config.yml:34, 46, 50`).
  - A local `docker build` would include `custom/` (`docker/Dockerfile:77` `COPY . /app`).
  - **Needs your confirmation** (section 4, D7).

### Q15. Is Docker present and suitable for Evolution?

- **The repo has Docker tooling:** a multi-stage `docker/Dockerfile` (`ruby:3.4.4-alpine3.21`, `:3`) and compose files. None of it is used for Lynomia production as far as the repo shows.
- **Evolution ships as a Docker image.** The `v2.3.7` Dockerfile is `node:24-alpine`, `EXPOSE 8080`, and runs Prisma migrations on start (`https://raw.githubusercontent.com/EvolutionAPI/evolution-api/2.3.7/Dockerfile#L33-L60`).
- **Evolution needs a SQL DB:** `DATABASE_PROVIDER` must be postgresql or mysql, otherwise the entrypoint exits (`.../2.3.7/Docker/scripts/deploy_database.sh#L9-L31`).
- **Docker suits Evolution** whether or not Lynomia itself runs in Docker. It can run as a separate compose project on the same host (section 3.8).

### Q16. Are PostgreSQL and Redis present, and can they be isolated?

- **Current use:** Chatwoot uses **one** Postgres DB (`config/database.yml:27-29`, `statement_timeout 14s` at `:13`). All Redis traffic goes through a single `REDIS_URL`: Sidekiq with no namespace, plus the `alfred` and `velma` namespaces and ActionCable (`lib/redis/config.rb:12-19`, `config/initializers/01_redis.rb:9-20`).
- **Postgres recommendation: separate.** Prisma migrations would otherwise mix Evolution tables into Chatwoot's schema, dumps and backups. Give Evolution its **own Postgres database and role**, ideally its own container.
- **Redis recommendation: separate.** Sidekiq needs `noeviction`, while Evolution's cache tolerates eviction, and a separate DB index still shares memory limits and the eviction policy. Give Evolution its **own Redis instance**.
- **Evolution's own compose file** also uses separate `postgres:15` and `redis` containers (`.../2.3.7/docker-compose.yaml#L4-L52`).
- **Redis is required in practice:**
  - Without a cache engine, Evolution's Chatwoot locks and caches become no-ops (`cacheengine.ts:19-25`, `cache.service.ts:8-21`).
  - A session store is mandatory: `DATABASE_SAVE_DATA_INSTANCE=true` or Redis instance saving (`whatsapp.baileys.service.ts:556-574`).

### Q17. Where should Evolution live in the infrastructure?

As an **independent internal service** on the same private network and host as Lynomia (or a sibling host), with:
- **no public port**;
- **the Manager UI disabled** (`SERVER_DISABLE_MANAGER=true`, `.../2.3.7/src/api/routes/index.router.ts#L163-L165`);
- **its own Postgres and Redis**.

Lynomia calls Evolution over the private address. Evolution posts events to Lynomia. Details and the Chatwoot-to-Evolution direction are in sections 2.4 and 3.8.

---

## 2. Evolution API: verified facts

### 2.1 Versions and images
- **Git and Docker tags:** git tags have no `v` (`2.3.7`, `2.4.0-rc2`). Docker stable tags do (`v2.3.7`). Pre-release tags do not (`2.4.0-rc2`).
- **Baileys:** `2.3.7` and `2.4.0-rc2` both depend on **baileys `7.0.0-rc.9`** (`.../2.3.7/package.json#L80`).
- **Candidate digest:** `v2.3.7` is `sha256:1bd8afc4a6cf48822e6cf02469aeae7bd35a12a6b616eacd1291926307f4d339`, pushed 2025-12-05.
- **`latest`:** its digest `sha256:966625532d90…` matches no release. Layer sizes suggest a rebuild of 2.3.7-era `main` (medium confidence). There is also an undocumented `homolog` tag (2026-07-14).
- **2.4.0 is BREAKING:**
  - Every business route returns `503 LICENSE_REQUIRED` until the instance is activated against `license.evolutionfoundation.com.br`.
  - After that it sends a 30-minute heartbeat that includes message counts (`.../2.4.0-rc2/CHANGELOG.md#L31-L35`, `src/licensing/runtime.ts#L333-L346, L420-L434`).
- **2.3.7 telemetry is ON by default.** It posts every route path, including the instance name, to `https://log.evolution-api.com/telemetry` (`.../2.3.7/src/config/env.config.ts#L881`, `src/utils/sendTelemetry.ts#L30-L34`). It must be set to `TELEMETRY_ENABLED=false`.
- **Stability concern:** the only stable line is ~10 months old and pins a Baileys **release candidate**. Whether it still pairs reliably with current WhatsApp can only be proven in the Phase C staging deploy (section 4, D2).

### 2.2 Unsafe defaults baked into the image
- **`.env.example` becomes the image's `.env`** (`.../2.3.7/Dockerfile#L22`). Unless overridden, the container runs with:
  - the **public** `AUTHENTICATION_API_KEY=429683C4C977415CAAFCCE10F7D57E11` (`.env.example#L391-L395`);
  - `TELEMETRY_ENABLED=true`;
  - `SERVER_URL=http://localhost:8080`;
  - `AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true`, which puts the instance token into every webhook payload (`src/api/services/channel.service.ts#L447-L459`);
  - a placeholder `CHATWOOT_IMPORT_DATABASE_CONNECTION_URI` that the code treats as configured (`chatwoot.service.ts#L2548-L2551`).
- **Other exposures:**
  - `/store` is served without auth (`src/main.ts#L71`).
  - The ERRORS webhook includes the global key (`src/main.ts#L84-L98`).

### 2.3 Instance API, states and events (2.3.7)
- **Auth:** header `apikey`. The global key allows everything. A per-instance token (the `hash` returned at create) is accepted only on `/:instanceName` routes (`src/api/guards/auth.guard.ts#L10-L50`). `/instance/create` needs the global key.
- **Routes** (`src/api/routes/instance.router.ts#L17-L98`):
  - `POST /instance/create`
  - `GET /instance/connect/:n` (`?number=` returns a pairing code)
  - `GET /instance/connectionState/:n`
  - `POST /instance/restart/:n`
  - `DELETE /instance/logout/:n`
  - `DELETE /instance/delete/:n`
  - `GET /instance/fetchInstances`
- **Errors come back as HTTP 200/201 with `{error:true}`**, so callers must inspect the body.
- **Create body** (`src/api/dto/instance.dto.ts#L5-L55`):
  - `integration` must be `WHATSAPP-BAILEYS` for QR (`channel.controller.ts#L81-L93`).
  - `settings` includes `groupsIgnore`, `syncFullHistory`, `readMessages`, `alwaysOnline` and `rejectCall`.
  - A nested per-instance `webhook{enabled,url,headers,byEvents,base64,events}` accepts **custom headers**, which Lynomia can use for a shared secret (`src/api/integrations/event/webhook/webhook.controller.ts#L78, L129`).
  - Instance names must be unique; a duplicate returns 403 (`instance.guard.ts#L42-L51`).
  - Type traps: `chatwootAccountId` and `accountId` must be strings, and `number` must be digits with no `+` (`instance.schema.ts#L31, L204`).
- **`connect` response:** returns `{pairingCode, code, base64, count}` while connecting, and starts a connection when the state is `close` (`src/api/controllers/instance.controller.ts#L309-L343`).
- **`connectionState` values:** `open | connecting | close` (Baileys `WAConnectionState`, `.../Baileys/v7.0.0-rc.9/src/Types/State.ts#L15`). **`refused` appears only in the `CONNECTION_UPDATE` webhook**, never from the endpoint (`whatsapp.baileys.service.ts#L350-L357`, `monitor.service.ts#L435-L436`).
- **Events** (`whatsapp.baileys.service.ts#L336-L464`, `monitor.service.ts#L411-L446`):

  | Trigger | What Evolution emits |
  |---|---|
  | Each QR | `QRCODE_UPDATED` (base64 + pairingCode); `count++` |
  | QR count reaches `QRCODE_LIMIT` (default 30) | `QRCODE_UPDATED{statusCode:500}` → `CONNECTION_UPDATE{state:'refused', statusReason:428}` → logout; state `close` |
  | Connection opens | `CONNECTION_UPDATE{state:'open', wuid, profileName, profilePictureUrl}` |
  | Close with 401/403/402/406 | **No reconnect.** `STATUS_INSTANCE 'closed'` → `LOGOUT_INSTANCE` → session deleted → `CONNECTION_UPDATE{state:'close'}` |
  | Any other close code | Automatic reconnect, with **no** `close` event |

- **Per-instance only:** `LOGOUT_INSTANCE`, `REMOVE_INSTANCE` and `STATUS_INSTANCE` reach **per-instance webhooks only**, not the global webhook (`env.config.ts#L197-L228`).
- **Webhook retries:** up to 10 with exponential backoff (`env.config.ts#L788-L796`).
- **Restart, logout and delete** (`instance.controller.ts#L355-L379, L436-L476`):
  - Restart = `ws.close` + reconnect, and only when the state is `open` or `connecting`.
  - Logout errors when the state is `close` in 2.3.7.
  - Delete purges Evolution data but **never touches the Chatwoot inbox, contacts or conversations** (`monitor.service.ts#L191-L224`).
- **Messaging and media** (`src/api/routes/sendMessage.router.ts#L54, L64, L88`; `src/api/routes/chat.router.ts#L63, L113`):
  - `POST /message/sendText/:n`
  - `POST /message/sendMedia/:n`
  - `POST /message/sendWhatsAppAudio/:n`, which supports a `quoted` option (`src/api/dto/sendMessage.dto.ts#L8-L12`)
  - `POST /chat/markMessageAsRead/:n`
  - `POST /chat/getBase64FromMediaMessage/:n`
- **Health:** `GET /` (no auth) returns version info and makes an outbound request to `web.whatsapp.com` on every call. There is **no `/health` route** in 2.3.7 (`index.router.ts#L196-L205`).
- **Linked-device label:** `CONFIG_SESSION_PHONE_CLIENT` / `CONFIG_SESSION_PHONE_NAME` set the name shown in the phone's **Linked Devices** list. The default is "Evolution API" (`env.config.ts#L799-L806`). Set it to "Lynomia Chat" to avoid Evolution branding for end users.

### 2.4 Evolution's built-in Chatwoot bridge (`chatwoot.service.ts`, tag 2.3.7)

| Behaviour | Evidence | Conflicts with |
|---|---|---|
| Finds the inbox by **exact name**. Otherwise creates an API inbox with `webhook_url=${SERVER_URL}/chatwoot/webhook/{instance}`, only when `autoCreate`. Never updates or deletes it. Renaming the inbox breaks the link; a new `nameInbox` creates a second inbox. | `#L184-L222`, `#L887-L917`, `#L113-L129` | Req. 11 (Lynomia owns the inbox lifecycle; no duplicate inboxes) |
| Calls Chatwoot REST with `api_access_token` = a **User** token. AgentBot tokens cannot reach contacts or inboxes (`app/controllers/concerns/access_token_auth_helper.rb:2-6`). Inbox create needs an **administrator** (`app/policies/inbox_policy.rb:41-43`). The token is stored in Evolution's DB (`VarChar(100)`, plain text) and returned by `fetchInstances` and create responses. | `#L1101-L1108`; `monitor.service.ts#L109-L113`; `instance.controller.ts#L288` | Req. 7 and 18 (credential exposure, tenant isolation) |
| **`POST /chatwoot/webhook/:instanceName` has no guard and no signature check** in 2.3.7 or 2.4.0-rc2. A forged payload can send WhatsApp messages or run the bot `disconnect` command. | `chatwoot.router.ts#L13-L33`; `#L1336-L1337`, `#L1432-L1441`; grep for `hmac\|signature\|x-chatwoot` found nothing | Req. 7 and 18 |
| Needs **Chatwoot → Evolution** HTTP. Chatwoot sends API-inbox webhooks through `SafeFetch`, which **blocks private networks** unless the global flag `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` is set (`lib/safe_fetch.rb:38-40`, `lib/safe_fetch/fetcher.rb:42-46`, `app/listeners/webhook_listener.rb:120-126`). Setting that flag reopens SSRF for **tenant-controlled** webhook URLs, including the unauthenticated Evolution endpoint of *other tenants*. | as cited | Req. 2, 7, 18 (stop condition: unexpected exposure) |
| Rewrites the `identifier` of the contact found by phone to the JID (or merges contacts) on **every** non-group message. Contacts are account-wide, so a contact shared with the official WhatsApp inbox gets rewritten. | `#L645-L666`; `app/models/contact.rb:53-56` | Req. 14 (contact identity) |
| Dedupe: `source_id='WAID:<id>'`. Pre-insert duplicate checks need **direct SQL access to Chatwoot's DB** (`CHATWOOT_IMPORT_DATABASE_CONNECTION_URI`, with TLS verification off and string-built SQL). Without that access, no dedupe. Chatwoot `messages.source_id` is not unique (`db/schema.rb:1073`). | `#L2304-L2313`, `#L1061-L1069`; `chatwoot-import-helper.ts#L98-L111`; `postgres.client.ts#L16-L21` | Req. 13 (duplicates) |
| Checks echoes on the wrong field: it reads `conversation.messages[0].source_id`, while Chatwoot sends a top-level `source_id` (`app/models/message.rb:180-194`, `app/presenters/conversations/event_data_presenter.rb:24-37`). | `#L1444-L1447` | Req. 13 |
| Uses a bot contact `+123456` per account. QR images (up to 30 per attempt) and "Connection successfully established!" are posted *into the inbox* as messages, and commands are typed into that conversation. | `#L231-L281`, `#L2464-L2523` | Req. 6 (QR must be in Lynomia UI; no Evolution branding) |
| Evolution calls go through `Api::V1::Accounts::BaseController`, so a billing lock (402) makes them fail. Evolution only **logs** these failures, so **incoming messages are lost**. | `config/initializers/billing.rb:6-9`; `custom/app/controllers/billing/access_guard.rb:21-35` | Req. 21 (graceful failure) |
| 2.4.0-rc2 adds "content_type text for Chatwoot 4.x" and "avoid 406" fixes, which implies 2.3.7 may fail some replies against Chatwoot 4.14 (untested). | `.../2.4.0-rc2/.../chatwoot.service.ts#L976-L983` | Req. 12 |

### 2.5 License
- **Tag 2.3.7 LICENSE:** Apache-2.0 plus the following conditions (`.../2.3.7/LICENSE#L3-L20`):
  - **(1a)** Do not remove the logo or copyright in Evolution *frontend components*. This does not apply if the frontend is not used.
  - **(1b)** "display a clear notification within the system that Evolution API is being utilized … visible to system administrators and accessible from the system's documentation or settings page".
- **The LICENSE on `main` and 2.4.0 differs.** Those branches also add `NOTICE` and `TRADEMARKS.md`, under which a modified UI must drop Evolution brand assets.
- **Interpretation:** a super-admin-visible notice plus a docs mention appears to satisfy 1b while keeping end users brand-free. **This needs your / legal confirmation** (section 4, D3).

---

## 3. Checkpoint

### 3.1 Current architecture

```text
Browser (Vue dashboard, app/javascript)          Lynomia mobile app (separate repo)
        │  devise_token_auth / api_access_token          │
        ▼                                                ▼
Rails app = Chatwoot 4.14.1 fork ─────────────────────────────────────────────
  app/ (OSS)  +  enterprise/ (prepend_mod_with)  +  custom/ (Lynomia: billing, mobile auth)
  Api::V1::Accounts::BaseController ─ current_account ─ Pundit (opt-in) ─ Billing::AccessGuard (402)
  Channels: Channel::* models ── Inbox (polymorphic) ── Conversation ── Message
  Official WhatsApp: Channel::Whatsapp → Whatsapp::Providers::{Cloud,360Dialog}
  Inbound webhooks: /webhooks/<provider>/... (ActionController::API) → Sidekiq jobs
  Outbound: SendReplyJob (class map) | API inboxes: WebhookListener → WebhookJob → SafeFetch
        │                                   │
        ▼                                   ▼
   PostgreSQL 16 + pgvector (one DB)    Redis (Sidekiq + alfred + velma + ActionCable)
External: lynomia.com admin (billing Platform API), Stripe, Meta/360dialog
```

### 3.2 Exact reusable components

| Need | Reuse | Evidence |
|---|---|---|
| Tenant scoping, auth, 402 billing gate | Inherit `Api::V1::Accounts::BaseController` | `app/controllers/api/v1/accounts/base_controller.rb:1-5`; `config/initializers/billing.rb:5-12` |
| Admin-only authorization | `authorize ::Inbox, :create?` / `authorize @inbox, :update?/:destroy?/:show?` | `app/policies/inbox_policy.rb:13-67`; pattern `channels/twilio_channels_controller.rb:5-17` |
| Inbox + channel | `Inbox` + **`Channel::Api`**. Outbound runs through `WebhookListener` with no official edits; `MessageBuilder` accepts incoming messages only on API inboxes | `app/models/channel/api.rb:22-36`; `app/listeners/webhook_listener.rb:120-126`; `app/builders/messages/message_builder.rb:98-104` |
| Plan limits | `Billing::InboxLimit` (automatic); `Billing::PlanLimits.reached?` as a pre-check before remote calls | `custom/app/models/billing/inbox_limit.rb:8-19`; `custom/app/models/billing/plan_limits.rb:12-15` |
| Contacts and identity | `ContactInboxSourceIdResolver`, `ContactInboxWithContactBuilder`, `Whatsapp::PhoneNumberNormalizationService`, `Whatsapp::IdentifierSyncService` (LID ↔ phone) | Q13 |
| Messages and statuses | `Messages::MessageBuilder` (`source_id`), `Messages::StatusUpdateService` | `message_builder.rb:132-146`; `messages_controller.rb:75-79` |
| Dedupe | Redis SET NX pattern from `Whatsapp::MessageDedupLock` plus a `source_id` lookup scoped to the inbox | `app/services/whatsapp/message_dedup_lock.rb:5-18` |
| Serialised processing | `MutexApplicationJob#with_lock`, `retry_on LockAcquisitionError` | `app/jobs/mutex_application_job.rb:17-32`; `app/jobs/webhooks/whatsapp_events_job.rb:1-6` |
| Webhook authentication | `ActiveSupport::SecurityUtils.secure_compare` pattern | `app/controllers/concerns/meta_token_verify_concern.rb:35-36` |
| Per-record secrets | `encrypts :x if Chatwoot.encryption_configured?`, `WebhookSecretable` | `app/models/channel/telegram.rb:21`; `app/models/concerns/webhook_secretable.rb:4-6` |
| Installation settings | Pattern of `Billing::Settings` (locked rows, masked display, keep-on-blank). **Copy it, do not edit it** | `custom/app/services/billing/settings.rb` |
| Routes, super admin, initializers | `draw :<file>`; custom super admin pages; to_prepare initializer | `config/routes.rb:719`; `config/routes/billing.rb`; `config/initializers/billing.rb` |
| Extension without edits | `Custom::` modules via `prepend_mod_with` (Inbox, InboxesController, Conversation, TriggerScheduledItemsJob…) | Q13 |
| Scheduled polling | `Custom::TriggerScheduledItemsJob` (5 min), following the `TemplatesSyncSchedulerJob` bounded fan-out | `app/jobs/trigger_scheduled_items_job.rb:20-25`; `lib/limits.rb:3` |
| Audit | `Enterprise::AuditLog.create(action: '…')`, guarded by `defined?` | `enterprise/app/models/enterprise/audit/inbox_member.rb:22-29` |
| Errors and logging | `ChatwootExceptionTracker`, `Rails.logger` with a `[WhatsappQr]` prefix (as `[Billing]`), `request_id` tag | `lib/chatwoot_exception_tracker.rb:14-17`; `config/environments/production.rb:50-53` |
| SSRF-safe fetch of payload URLs | `SafeFetch`, `Avatar::AvatarFromUrlJob` | `lib/safe_fetch.rb`; `app/jobs/avatar/avatar_from_url_job.rb:37-41` |
| Admin-only realtime | `account.administrators.pluck(:pubsub_token)`, not the `account_<id>` stream (the QR is a credential) | `app/listeners/action_cable_listener.rb:202-205`; `app/channels/room_channel.rb:29` |
| Frontend | `ChannelList` tile, `ChannelFactory`, `ChannelItem` allow-list, `channelActions.js`, `qrcode` package, `<script setup>` like `WhatsappCall.vue` | Q11 |

### 3.3 Files likely to change (depends on decision D1; this assumes the recommended Option B)

**New (all under Lynomia-owned paths):**
- `custom/db/migrate/<ts>_create_whatsapp_qr_connections.rb`
- `custom/app/models/whatsapp_qr_connection.rb`
- `custom/app/services/whatsapp_qr/`:
  - `settings.rb`
  - `provider.rb` (interface)
  - `evolution/client.rb`
  - `evolution/provider.rb`
  - `state_mapper.rb`
  - `connection_manager.rb`
  - `inbound_message_service.rb`
  - `outbound_message_service.rb`
  - `audit.rb`
- `custom/app/controllers/api/v1/accounts/whatsapp_qr/connections_controller.rb`
- `custom/app/controllers/webhooks/whatsapp_qr_controller.rb`
- `custom/app/jobs/whatsapp_qr/`:
  - `event_job.rb`
  - `send_message_job.rb`
  - `health_check_job.rb`
  - `teardown_job.rb`
- `custom/app/jobs/custom/trigger_scheduled_items_job.rb`
- `custom/app/models/custom/inbox.rb` (teardown on inbox destroy)
- Super admin:
  - `custom/app/controllers/super_admin/whatsapp_qr_settings_controller.rb`
  - `custom/app/views/super_admin/whatsapp_qr_settings/*` (settings, diagnostics and the license notice)
- `config/routes/whatsapp_qr.rb`
- `config/initializers/whatsapp_qr.rb` (filter params, Rack::Attack throttles, outbound hook registration)
- Frontend:
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQr.vue`
  - a QR/status component
  - `app/javascript/dashboard/api/whatsappQr.js`
- `deployment/evolution/docker-compose.evolution.yaml` + `.env.evolution.example` (Phase C)
- `docs/whatsapp-qr/01…06`

**Modified (shared files, not WhatsApp-specific):**
- `config/routes.rb`: one `draw :whatsapp_qr` line next to `:719`.
- `ChannelList.vue`, `ChannelFactory.vue`, `components/widgets/ChannelItem.vue`: new tile (decision D6).
- `Settings.vue`: hide `webhook_url` and secret for QR inboxes; mount the status panel.
- `helper/inbox.js`, `components/ChannelName.vue`: WhatsApp icon and label for QR inboxes.
- `app/views/super_admin/application/_navigation.html.erb`: one nav item (the fork already edits this file).
- `en` (+`ar`, per the fork's earlier decision) `inboxMgmt.json`; `config/locales/en.yml`.
- `.env.example`: documentation only.
- Optional: `auditlogHelper.js` + `auditLogs.json`, if QR events must render in the Audit Logs UI (D5).

**Must not be modified (official WhatsApp):**
- `app/models/channel/whatsapp.rb`
- `app/services/whatsapp/**`
- `app/controllers/webhooks/whatsapp_controller.rb`
- `app/controllers/api/v1/accounts/whatsapp/**`
- `app/controllers/api/v1/accounts/concerns/whatsapp_health_management.rb`
- `app/jobs/webhooks/whatsapp_events_job.rb`
- `app/jobs/channels/whatsapp/**`
- `enterprise/**/whatsapp*`
- `channels/{Whatsapp,CloudWhatsapp,360DialogWhatsapp,WhatsappEmbeddedSignup,WhatsappCall}.vue`
- `channels/whatsapp/**`
- `api/channel/whatsappChannel.js`
- `WhatsappTemplates/*`
- `app/services/conversations/message_window_service.rb`
- `app/models/contact_inbox.rb`
- the routes `config/routes.rb:256-258, 336-338, 616-617`

Also must not change:
- `lib/safe_fetch*`
- `lib/webhooks/trigger.rb`
- `app/listeners/webhook_listener.rb`
- `lib/global_config*.rb`
- `config/features.yml`: 63 flags already exist in a signed bigint, so a 64th would overflow (`app/models/concerns/featurable.rb:11-17`, `db/schema.rb:69`).
- the billing guards.

### 3.4 Current official WhatsApp path

Covered in Q12 above. **The recommended design touches none of these files.**

### 3.5 Current Chatwoot inbox lifecycle

- **Create:** `InboxesController#create` (admin), or a dedicated service in one transaction: channel `create!` first, then `inbox.save!`. `Billing::InboxLimit` runs on save.
  - ⚠️ Remote side-effects in the channel's `after_create` run even if the inbox save later fails. Remote calls must therefore happen **after commit** (`inboxes_controller.rb:33-46`).
- **Members:** `InboxMembersController`, admin-only (`inbox_members_controller.rb:10-13`).
- **Update:** inbox and channel `EDITABLE_ATTRS`. `Channel::Api` replaces `additional_attributes` **wholesale** (`inboxes_controller.rb:129`, `channel/api.rb:26`).
- **Delete:** async `DeleteObjectJob`. It deletes conversations, contact_inboxes and reporting_events, then the inbox and the channel; contacts are kept. It does **nothing** outside the app, so a hook is needed to tear down the Evolution instance (`Custom::Inbox` via `inbox.rb:269`).
- **Exposure:** the inbox JSON returns `additional_attributes` to **all** members, while `hmac_token` and `secret` go only to admins (`app/views/api/v1/models/_inbox.json.jbuilder:117-121`). **No Evolution secret may be stored in `additional_attributes`.**

### 3.6 Tenant and security model

- **Tenant:** `Account`.
- **Isolation:** by `Current.account` scoping plus `AccountUser` membership plus explicit Pundit calls.
- **Every QR action** must:
  1. load the inbox through `Current.account.inboxes.find(id)`;
  2. call `authorize` (admin);
  3. resolve the Evolution instance **only** from our DB mapping, never from request or webhook input.
- **Webhooks** identify the connection by an unguessable UUID in the path plus a per-connection secret header, compared with `secure_compare`.
- **The QR** is a login credential. Deliver it only in the admin's HTTP response or to admin pubsub tokens, never to the shared `account_<id>` stream.

### 3.7 Secret-storage model (proposed)

- **Global Evolution URL and API key:** **ENV** (`EVOLUTION_API_URL`, `EVOLUTION_API_KEY`), read with `ENV.fetch`. This keeps them out of the DB (InstallationConfig is plain text) and out of `GlobalConfigService`, which would copy them into a visible row. The super admin page shows only `set / not set` and reachability.
  - Alternative (if UI editing is required): a locked InstallationConfig row, encrypted with `ActiveRecord::Encryption.encryptor` (D4).
- **Per-connection Evolution instance token and inbound webhook secret:** columns on `whatsapp_qr_connections` with `encrypts … if Chatwoot.encryption_configured?`.
- **Fail closed:** the feature refuses to enable unless `Chatwoot.encryption_configured?` is true, which guarantees "encrypted at rest" (req. 18). **Needs confirmation** that production has the `ACTIVE_RECORD_ENCRYPTION_*` keys (D4).
- **Redaction:**
  - Add `apikey`, `base64`, `qrcode`, `pairingCode` and `code` to `filter_parameters` from a new initializer (`config/initializers/filter_parameter_logging.rb:4-13` lacks them).
  - Strip `apikey` and QR payloads before `perform_later` (Sidekiq args are stored in Redis and visible at `/monitoring/sidekiq`, `config/routes.rb:700-702`).
  - Scrub them for Sentry (`config/initializers/sentry.rb:13` sends PII).

### 3.8 Recommended Evolution topology

```text
                       ┌──────────── private network (docker network or host loopback) ────────────┐
Browser ─HTTPS─ nginx ─┤ Lynomia Rails/Sidekiq ──(apikey, timeouts)──► evolution-api v2.3.7 (pinned) │
                       │        ▲                                       │        │                  │
                       │        └──── per-instance webhook + secret ────┘  evolution-postgres (own) │
                       │                                                  evolution-redis (own)      │
                       └────────────────────────────────────────────────────────────────────────────┘
No public Evolution port. Manager disabled. Telemetry off. Chatwoot never calls Evolution directly.
```

- **Image:** `evoapicloud/evolution-api:v2.3.7@sha256:1bd8afc4…4d339`.
- **Required env** (image defaults are unsafe; override every value):
  - `AUTHENTICATION_API_KEY=<random 48+>`
  - `AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false`
  - `TELEMETRY_ENABLED=false`
  - `SERVER_DISABLE_MANAGER=true`
  - `SERVER_URL=<internal url>`
  - `CHATWOOT_ENABLED=false` (Option B)
  - `CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=` (empty)
  - `DATABASE_PROVIDER=postgresql`, `DATABASE_CONNECTION_URI=<own DB>`, `DATABASE_SAVE_DATA_INSTANCE=true`
  - `CACHE_REDIS_ENABLED=true`, `CACHE_REDIS_URI=<own redis>`
  - `QRCODE_LIMIT`
  - `CONFIG_SESSION_PHONE_CLIENT="Lynomia Chat"`
- **Rack::Attack:** add the Evolution container IP to `RACK_ATTACK_ALLOWED_IPS`, because all tenants' webhooks come from one IP (`config/initializers/rack_attack.rb:28-31, 70`).
- **Exact wiring** (loopback vs docker network, public webhook URL vs internal) depends on the real production deploy (D7).

### 3.9 Required DB additions (Option B)

One new table, `whatsapp_qr_connections`, created through `custom/db/migrate`:

| Column | Notes |
|---|---|
| `account_id` | integer FK |
| `inbox_id` | integer FK, **unique** |
| `uuid` | unique, public webhook key |
| `instance_name` | unique, deterministic `lyn_<account_id>_<uuid-hex>`, never the phone |
| `instance_token` | encrypted |
| `webhook_secret` | encrypted |
| `status` | enum of the normalized states |
| `status_reason` | |
| `phone_number` | E.164, filled on connect |
| `wa_jid` | |
| `profile_name` | |
| `connected_at` / `disconnected_at` | |
| `last_event_at` | |
| `last_error_code` / `last_error_at` | safe code only |
| `settings` | jsonb: `ignore_groups: true`, `import_history: false` |
| timestamps | |

Notes:
- It is kept **off** the channel row, because `Enterprise::Channelable` would audit every change *and* any secret.
- The short-lived QR payload lives in **Redis with a TTL**, not in the DB.
- Optional unique index on `wa_jid` among active rows (D8).
- **Option A would need no table** but stores secrets inside Evolution.

### 3.10 Risks and conflicts

| # | Risk / conflict | Evidence | Mitigation |
|---|---|---|---|
| R1 | Evolution's native bridge breaks req. 7/11/13/14/18 (name-bound inbox, user token, unauthenticated webhook, contact rewrite, no dedupe) | §2.4 | Option B (Lynomia-owned thin bridge) |
| R2 | Chatwoot→Evolution via `SafeFetch` needs a global SSRF relaxation, which exposes other tenants' unauthenticated endpoints | `lib/safe_fetch.rb:38-40` | Never enable it. In Option B, Chatwoot never calls Evolution |
| R3 | Stable Evolution is old, and Baileys is an RC; 2.4.0 adds license activation and phone-home | §2.1 | Pin v2.3.7 by digest; staging soak (Phase C); decision D2 |
| R4 | License 1b notice | §2.5 | Super-admin notice plus docs; decision D3 |
| R5 | At-rest encryption depends on ENV keys of unknown state | `config/application.rb:83-117` | Fail closed; D4 |
| R6 | Deploy topology unknown; prod compose uses the upstream image without `custom/` | `docker-compose.production.yaml:4-8` | D7 before Phase C |
| R7 | Orphans: inbox delete does nothing remotely; an inbox-limit failure after the remote create | Q2, §3.5 | Pre-check limits; create remotely after commit; `Custom::Inbox` teardown job |
| R8 | Duplicate messages: `messages.source_id` is not unique | `db/schema.rb:1053, 1073` | Redis SET NX plus an inbox-scoped `source_id` lookup (official pattern) |
| R9 | Duplicate contacts: phone uniqueness is enforced in the model only | `app/models/contact.rb:54-56`; `db/schema.rb:722` | `ContactInboxWithContactBuilder` race retry plus a per-sender mutex |
| R10 | Admins can edit `webhook_url` or reset the secret of a QR (API) inbox | `Settings.vue:781-820, 596-599` | Hide those fields for QR inboxes; outbound must not depend on `webhook_url` (D1) |
| R11 | Billing lock: account API returns 402, and webhooks are not gated | Q9 | Decision D9 (drop vs accept inbound while locked) |
| R12 | No feature-flag bit left for gating | `config/features.yml` (63); `db/schema.rb:69` | Installation-level ENV switch plus an optional `BillingPlan` limit key |
| R13 | Audit rows written but hidden (premium `audit_logs`) | Q10 | Decision D5 |
| R14 | Same WhatsApp number linked in two tenants (up to 4 linked devices per phone) | n/a (product) | Decision D8 |
| R15 | Log and Sentry leakage of `apikey` or QR | §3.7 | Filter params, scrub, strip before enqueue |
| R16 | Upstream merges: shared UI files (`ChannelList`, `Settings.vue`) get conflicts | — | Keep edits to a few lines; all logic in new files |
| R17 | Unofficial WhatsApp (Baileys) carries ToS and ban risk | — | Product and legal awareness; out of the code's control |

### 3.11 What we will NOT build (already exists)

- **Inboxes:** `Inbox` + `Channel::Api`. The inbox system itself is not rebuilt.
- **Conversations, messages, attachments UI:** Chatwoot's `Conversation`, `Message`, ActiveStorage attachments and the existing conversation and reply UI.
- **Contacts:** `Contact`, `ContactInbox` and the builders and resolvers listed in §3.2.
- **Agents, teams, assignment, labels, notes, automations:** unchanged. They apply to QR inboxes automatically.
- **Permissions:** Pundit `InboxPolicy` and `AccountUser` roles.
- **Settings:** ENV / InstallationConfig patterns.
- **Audit:** `Enterprise::AuditLog`.
- **Billing:** `Billing::InboxLimit` / `AccessGuard`.
- **Jobs and scheduling:** Sidekiq, `MutexApplicationJob`, existing queues (no new queue, per `config/sidekiq.yml:17-33`), dispatcher prepend.
- **Logging and monitoring:** `Rails.logger` + `request_id`, `ChatwootExceptionTracker`, `/health`, `/monitoring/sidekiq`.
- **SSRF guard:** `SafeFetch`.
- **Official WhatsApp:** untouched.

### 3.12 Proposed Phase B contracts (drafts, pending decisions)

**Provider interface.** New `custom/app/services/whatsapp_qr/provider.rb`. Evolution is one implementation, and Lynomia logic depends only on this:

```ruby
# All methods take the WhatsappQrConnection, raise WhatsappQr::ProviderError (safe code), never leak raw errors.
create_instance(connection)      # idempotent: fetch-or-create by instance_name
request_qr(connection)           # => { qr_png_data_url:, pairing_code: nil, attempt:, expires_in: }
connection_state(connection)     # => normalized state
restart(connection); logout(connection); delete_instance(connection)
send_text(connection, to:, body:, quoted_id: nil)            # => provider_message_id
send_media(connection, to:, kind:, file_url_or_io:, caption: nil, quoted_id: nil)
fetch_media(connection, provider_message_ref)                # => IO + content_type
parse_event(raw_payload)         # => WhatsappQr::Event (type, state, message, ids) — pure, no side effects
```

**Normalized states.** Lynomia owns these. The mapping comes from the Evolution evidence in §2.3:

| Lynomia | Evolution signal |
|---|---|
| `CREATING` | row created; `/instance/create` not yet confirmed |
| `WAITING_QR` | `QRCODE_UPDATED` with base64, or `connect` returned `{base64,count}` |
| `CONNECTING` | `CONNECTION_UPDATE{state:'connecting'}` after a scan (no fresh QR) |
| `CONNECTED` | `CONNECTION_UPDATE{state:'open'}` / `connectionState=open` |
| `RECONNECTING` | `connecting` after a previous `CONNECTED` (Evolution auto-reconnect emits no `close`) |
| `DISCONNECTED` (UI: "QR Required") | `refused`/428 (QR limit), or `close` without logout |
| `LOGGED_OUT` | `LOGOUT_INSTANCE`, or `STATUS_INSTANCE closed` with 401/403/402/406 |
| `ERROR` | Evolution unreachable, timeout, 401 on the apikey, or an unknown instance (safe `status_reason`) |

**Account API.** Admin only; inherits `Api::V1::Accounts::BaseController`; rate-limited per account.
- `POST /api/v1/accounts/:account_id/whatsapp_qr/connections {name}` → `201 {connection}`. It:
  1. pre-checks the plan limit;
  2. creates the `Channel::Api` inbox and the connection row in one transaction;
  3. calls Evolution after commit.

  It is idempotent on retry, so there is no second inbox or instance.
- `GET  …/connections/:id` → `{id, inbox_id, status, phone_number, profile_name, last_event_at, error_code}` (no secrets, no instance internals).
- `POST …/connections/:id/qr` → `{qr_png_data_url, attempt, expires_in}` (QR taken from Redis or `connect`; never logged or audited).
- `POST …/connections/:id/restart`, `POST …/connections/:id/logout`.
- `DELETE …/connections/:id` → removes the Evolution instance and the mapping, and **keeps the inbox and history**. That inbox can still be deleted with the standard inbox delete, which deletes conversations per `delete_object_job.rb:18-23` and also triggers teardown.

**Evolution → Lynomia webhook.** `POST /webhooks/whatsapp_qr/:uuid` (`ActionController::API`):
- The header `X-Lynomia-Webhook-Token` is checked with `secure_compare`.
- The payload is stripped of `apikey` and enqueued, with the controller returning 200 quickly.
- `WhatsappQr::EventJob` runs on `:low`, with a mutex per connection and sender.

**Outbound.** A decision point, because agent replies on a `Channel::Api` inbox are delivered by `WebhookListener` to `webhook_url`:
- **(a)** Point `webhook_url` at Lynomia's own public `/webhooks/whatsapp_qr/:uuid/outbound`, verifying `X-Chatwoot-Signature` with the channel secret. This needs no core edit.
- **(b)** Register a small custom listener for `message_created` on QR inboxes and leave `webhook_url` blank.

Both enqueue `WhatsappQr::SendMessageJob`, which is bounded and idempotent on message id.

**Contact identity:**
- `contact_inbox.source_id` = phone digits taken from `remoteJidAlt`/`remoteJid`.
- The LID is stored as an extra source id through `IdentifierSyncService`.
- The contact is found by phone through `PhoneNumberNormalizationService`.
- Groups are ignored (`groupsIgnore: true` at create, and `@g.us` dropped).
- History import is off (`syncFullHistory: false`).

**Audit actions:**
- `whatsapp_qr.instance_created`, `qr_requested`, `connected`, `disconnected`, `restarted`, `logged_out`, `deleted`, `connection_failed`.
- Written through `Enterprise::AuditLog` with `auditable: inbox` and `associated: account`, guarded by `defined?`.
- Only state *transitions* are recorded, never QR data or secrets.

**Health:**
- Per-connection `last_event_at` / `last_error_*`, plus a 5-minute `connectionState` poll via `Custom::TriggerScheduledItemsJob`, bounded like `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`.
- A super admin page shows Evolution reachability (`GET /`), version, instance counts and the license notice.

**HTTP client:**
- Base URL comes only from ENV (not tenant input).
- http/https only, no redirects.
- `open_timeout 2s`, `read_timeout 10s`.
- No retries in the request path; bounded Sidekiq retries in jobs.
- Errors are mapped to safe codes.

---

## 4. Stop conditions hit and decisions needed

| ID | Stop condition | Decision needed |
|---|---|---|
| **D1** | Evolution's native Chatwoot bridge needs a different inbox lifecycle (name-bound, autoCreate), a user token, an unauthenticated inbound endpoint, and a private-network SSRF relaxation (§2.4) | **Option A**: use Evolution's native bridge with mitigations. Less code; residual risks R1, R2, R8 and R11 (messages lost on 402). **Option B (recommended)**: Evolution is transport only (`CHATWOOT_ENABLED=false`). Lynomia owns inbox, contacts, messages and dedupe through the existing Chatwoot builders. It is more code (message mapping), but it meets req. 7, 11, 13, 14, 18 and 21 |
| **D2** | The only stable version is old and pins an RC Baileys; 2.4.0 adds licence activation and phone-home | Pin `v2.3.7` for staging, and go/no-go after a Phase C soak test? Or wait for 2.4.x GA and accept activation? |
| **D3** | License 1b usage notice | Confirm a super-admin page plus docs notice is acceptable (end users see no Evolution branding) |
| **D4** | "Encrypted at rest" is guaranteed only with `ACTIVE_RECORD_ENCRYPTION_*` set | Confirm production has the keys (or will). Global key in ENV (recommended) vs an encrypted DB setting |
| **D5** | Audit rows are hidden unless the premium `audit_logs` feature is on | Where must QR audit events be visible: account Audit Logs UI (needs the feature on and UI keys), super admin, or DB only? |
| **D6** | UI placement: "Add Channel → WhatsApp → Connect via QR" inside the WhatsApp picker edits the official `channels/Whatsapp.vue` | Recommended: a separate **"WhatsApp (QR)"** tile next to WhatsApp, following the `whatsapp_call` precedent, with zero official edits. Or accept a small edit to the official picker |
| **D7** | Production topology unknown (`server2.lynomia.com`? systemd VM vs docker?) | Tell us how chat.lynomia.com is deployed and where Evolution may run |
| **D8** | Same number in multiple tenants | Allow, or enforce one active QR connection per WhatsApp number installation-wide? |
| **D9** | Billing-locked accounts | Keep ingesting inbound WhatsApp while the account API is locked (402), or drop or queue? |

No implementation will start until D1 to D4 and D7 are answered.

---

## Appendix: primary external sources
- Evolution API tag 2.3.7: `https://raw.githubusercontent.com/EvolutionAPI/evolution-api/2.3.7/` (package.json, LICENSE, Dockerfile, docker-compose.yaml, .env.example, src/…). Tag 2.4.0-rc2: same path with `2.4.0-rc2`.
- Baileys v7.0.0-rc.9: `https://raw.githubusercontent.com/WhiskeySockets/Baileys/v7.0.0-rc.9/src/Types/`.
- Docker Hub: `https://hub.docker.com/v2/repositories/evoapicloud/evolution-api/tags/{v2.3.7,latest,2.4.0-rc1,2.4.0-rc2,homolog}`.
- Not verifiable here (github.com blocked): the provenance of the `latest` build, and the contents of `homolog`.
