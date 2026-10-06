# 00 — The WhatsApp template system Lynomia Chat has today

Read at HEAD `a970abb7`, branch `claude/practical-thompson-9xfqed`, working tree clean.
Every claim below is a file and line in this repository. Nothing here is designed yet — this is what exists.

---

## EXISTING SYSTEM TO EXTEND

P3 adds a management experience to the system named here. It does not add a provider, a sender, a send pipeline,
a campaign engine, a flow template sender or a credential store, because each of those already exists and is named
in this list.

| Concern | The thing that already does it | P3's relationship to it |
|---|---|---|
| Template **storage** | `channel_whatsapp.message_templates` jsonb (`db/schema.rb:800`) + `message_templates_last_updated` (`:801`) | ADD a per-template record beside it; keep the jsonb written exactly as today (PART 2) |
| Template **read for sending** | `Whatsapp::TemplateProcessorService#find_template` (`app/services/whatsapp/template_processor_service.rb:21-27`) | FIX the defect in §6.1, keep the service |
| Template **sendability rule (Ruby)** | `Flows::Template.sendable?` / `.problem` (`custom/app/services/flows/template.rb:11, 26, 31-36`) | EXTEND into the one shared authority; do not re-implement |
| Template **sendability rule (JS)** | `isSendableTemplate` from `@chatwoot/utils` (`node_modules/@chatwoot/utils/src/template.ts:86-102`), used at `app/javascript/dashboard/store/modules/inboxes.js:72` | keep in lock-step; do not fork |
| **Sync from Meta** | `Whatsapp::Providers::WhatsappCloudService#sync_templates` (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45`) + `Channels::Whatsapp::TemplatesSyncJob` + `…TemplatesSyncSchedulerJob` | EXTEND the same service and the same two jobs (PART 3) |
| **Graph client** | `Whatsapp::FacebookApiClient` (`app/services/whatsapp/facebook_api_client.rb`) and the provider service's own HTTParty calls | ADD create/edit/delete there; no new client |
| **Template write to Meta (the only one today)** | `Whatsapp::CsatTemplateService` (`app/services/whatsapp/csat_template_service.rb:11-47`) | the shape to copy, with the token corrected (§4.3); CSAT's own lifecycle stays untouched (PART 9) |
| **Credentials** | `provider_config['api_key']` / encrypted `business_management_token`, selected by `Channel::Whatsapp#template_access_token` (`app/models/channel/whatsapp.rb:85-89`) | USE it; store nothing new |
| **Webhook receiver** | `Webhooks::WhatsappController` → `Webhooks::WhatsappEventsJob` (`app/jobs/webhooks/whatsapp_events_job.rb`) | ADD a branch + subscribe the field (PART 4) |
| **Webhook subscription** | `Whatsapp::WebhookSetupService#subscribed_fields` (`app/services/whatsapp/webhook_setup_service.rb:86-89`), `FacebookApiClient::WEBHOOK_DEFAULT_FIELDS` (`:9`) | ADD `message_template_status_update` |
| **Management UI** | `app/javascript/dashboard/routes/dashboard/settings/templates/` — route `settings_templates` (`templates.routes.js:9-19`), `Index.vue`, `TemplateCard.vue`, `TemplatePreviewDrawer.vue`, `templateUtils.js` | EXTEND this page into the manager; no second page |
| **Preview renderer** | `app/javascript/dashboard/components-next/template-preview/` | REUSE for the builder's live preview (PART 6.3) |
| **Variable registry** | `Flows::Variables` (`custom/app/services/flows/variables.rb`) server-side; `MESSAGE_VARIABLES` (`app/javascript/shared/constants/messages.js:101-154`) client-side | PROMOTE to one authority (PART 12); six lists exist today (§7) |
| **Campaign template choice** | `WhatsAppCampaignForm.vue:36-37, 76-96` | re-point at the unified query; no campaign runtime |
| **Flow template choice** | `TemplateEditor.vue:27-61` + `Flows::TemplateValidator` | re-point at the unified query; no flow template store |
| **Authorization** | `InboxPolicy` (`app/policies/inbox_policy.rb:43-45, 71-73`) + route `meta.permissions` | REUSE; no second authorization model (PART 17) |
| **Audit** | `Enterprise::AuditLog` via `Enterprise::Channelable#create_audit_log_entry` (`enterprise/app/models/enterprise/channelable.rb:12-43`) | REUSE; no new audit system (PART 18) |
| **i18n namespace** | `app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json` (`WHATSAPP_TEMPLATE_MGMT`) | EXTEND; it already reserves `STATUSES.UNSUBMITTED` (`:22`) |

---

## 1. Where a template lives today

**Two columns on one table, and nothing else.** `db/schema.rb:792-807`:

```ruby
t.jsonb    "message_templates", default: {}
t.datetime "message_templates_last_updated", precision: nil
```

- Origin: `db/migrate/20230426130150_init_schema.rb:339-340`. No later migration touches either column.
- The only indexes on `channel_whatsapp` are `phone_number` (unique) and `phone_number_health_checked_at`. **No index on the jsonb.**
- **The default is `{}` — a Hash — while every consumer expects an Array.** A channel that has never synced holds `{}`.
  Consumers defend individually: `Array(...)` in `app/services/whatsapp/authentication_template_guard.rb:21`,
  `app/services/whatsapp/contact_info_request_eligibility_service.rb:106`, `custom/app/services/flows/template.rb:17`;
  `is_a?(Array) ? … : []` in `app/views/api/v1/models/_inbox.json.jbuilder:146`.
  `app/services/whatsapp/template_processor_service.rb:22` has **no guard** and calls `.find` on the raw column.
- **There is no per-template table.** `db/schema.rb` (version `2026_10_04_110000`) has 108 `create_table`
  statements; the only one matching `templ` is `create_table "email_templates"` (`:1217-1230`) — branded transactional
  email, unrelated. No `whatsapp_templates`, no `message_template*` table, no join table.
- Twilio's parallel column is `channel_twilio_sms.content_templates` / `content_templates_last_updated`.

**Shape in practice.** An Array of Meta's `GET /{waba}/message_templates` `data[]` elements, stored verbatim —
nothing normalizes, filters or keys them. The shared TypeScript contract is
`node_modules/@chatwoot/utils/dist/types/template.d.ts:25-34`: `id?`, `name`, `status`, `category`, `language`,
`namespace?`, `components[]`, `parameter_format?`. Real examples with and without `id`, and with
`example.body_text_named_params`, are in `spec/factories/channel/channel_whatsapp.rb:6-18, 20-33, 35-51, 67-86`.

**Overlays.** `enterprise/app/models/enterprise/channel/whatsapp.rb` does not touch templates (13 lines: call-recording
settings and a `send_template` wrapper that captures `provider.last_error`). `custom/` has no `Channel::Whatsapp`
overlay. So the storage has exactly one owner.

---

## 2. How it is written

**WhatsApp Cloud — a full-document replace that skips the whole ActiveRecord stack**
(`app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45`):

```ruby
def sync_templates
  whatsapp_channel.mark_message_templates_updated          # :37 — timestamp FIRST, so a broken config stops retrying
  return if (templates = fetch_whatsapp_templates).blank?  # :38 — a blank fetch writes nothing
  whatsapp_channel.account.update_cache_key('inbox') if templates != whatsapp_channel.message_templates   # :41
  whatsapp_channel.update_columns(message_templates: templates, message_templates_last_updated: Time.current) # :43
end
```

`update_columns` means: **no merge, no validations, no callbacks, no `updated_at`, no audit entry.** The manual
`update_cache_key('inbox')` at `:41` exists precisely because the touch is skipped.

> **This is the proof that a local draft cannot live in the jsonb.** The next sync replaces the entire document.
> Any local-only state kept inside it is destroyed within three hours.

`fetch_whatsapp_templates` (`:47-62`) recurses through Meta's `paging.cursors.after` with no page cap and no page size,
and returns `response['data']` as-is.

**360dialog — same full replace, different key, different mechanics**
(`app/services/whatsapp/providers/whatsapp_360_dialog_service.rb:27-32`):
reads `response['waba_templates']` and writes with `update`, which runs `validate_provider_config`
(`app/models/channel/whatsapp.rb:41`) — and for 360dialog that **POSTs a webhook registration on every sync**
(`whatsapp_360_dialog_service.rb:34-43`). A validation failure drops the write silently (`update` returns false).
Lynomia uses Cloud; the 360dialog branch must keep working unchanged.

**`mark_message_templates_updated`** (`app/models/channel/whatsapp.rb:139-144`) `update_column`s the timestamp only.

**Three triggers, all of them:**

1. **Cron, every 5 minutes.** `config/schedule.yml:12-15` → `TriggerScheduledItemsJob` →
   `Channels::Whatsapp::TemplatesSyncSchedulerJob.perform_later` (`app/jobs/trigger_scheduled_items_job.rb:21`).
   The scheduler (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-12`) selects active accounts' channels,
   orders `message_templates_last_updated IS NULL DESC, … ASC`, filters `<= 3.hours.ago OR IS NULL`, and caps at
   `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT` = **25** (`lib/limits.rb:3`).
   Effective cadence: **at most every 3 hours per channel, at most 25 channels per 5-minute tick.**
2. **On channel create, synchronously in the request.** `after_create :sync_templates`
   (`app/models/channel/whatsapp.rb:44`) — not through the job.
3. **Manual, per inbox, admin only.** `POST /api/v1/accounts/:account_id/inboxes/:id/sync_templates`
   (`config/routes.rb:303`) → `Api::V1::Accounts::Concerns::InboxHealthManagement#sync_templates` (`:10-17`) →
   `Channels::Whatsapp::TemplatesSyncJob.perform_later` (`:117`). `InboxPolicy#sync_templates?` is
   `administrator?` (`app/policies/inbox_policy.rb:71-73`).

`Channels::Whatsapp::TemplatesSyncJob` (`app/jobs/channels/whatsapp/templates_sync_job.rb`) is 7 lines, `queue_as :low`,
a pure delegator to `channel.sync_templates`, which is `delegate :sync_templates, to: :provider_service`
(`app/models/channel/whatsapp.rb:155`).

---

## 3. Every operation this repo performs against Meta's template API

| # | Operation | Verb + URL | Where | Token |
|---|---|---|---|---|
| 1 | LIST, paginated | `GET {base}/{v}/{waba}/message_templates` (+`after`) | `whatsapp_cloud_service.rb:47-62` | `channel.template_access_token` (`:48`) |
| 2 | LIST, probe `limit=1` | `GET {BASE}/{v}/{waba}/message_templates?limit=1` | `facebook_api_client.rb:57-65` | bearer argument |
| 3 | LIST, config check | `GET {base}/{v}/{waba}/message_templates?access_token=…` | `whatsapp_cloud_service.rb:64-76` | `provider_config['api_key']`, **in the query string** |
| 4 | LIST, token check | `GET {base}/{v}/{waba}/message_templates?limit=1` | `business_management_token_validation_service.rb:28-32, 40-49` | the business-management token |
| 5 | GET by name | `GET {base}/{v}/{waba}/message_templates?name=…` | `csat_template_service.rb:29-47` | `provider_config['api_key']` |
| 6 | **CREATE** | `POST {base}/{v}/{waba}/message_templates` | `csat_template_service.rb:11-18, 97-103` | `provider_config['api_key']` |
| 7 | **DELETE by name** | `DELETE {base}/{v}/{waba}/message_templates?name=…` | `csat_template_service.rb:20-27` | `provider_config['api_key']` |
| 8 | **EDIT** | — | **absent** | — |

So: the repo can already create and delete a template at Meta. It has never edited one, never deleted by id, and
never read a single template by id. P3 adds edit, delete-by-id and read-by-id — nothing else new at the protocol level.

**Graph version.** `Whatsapp::FacebookApiClient::DEFAULT_API_VERSION = 'v24.0'` (`facebook_api_client.rb:3`), overridable
by the `WHATSAPP_API_VERSION` installation config (seeded `v24.0` at `config/installation_config.yml:179-182`,
`locked: false`). The pair is re-read independently at eight call sites with no shared accessor, and
`Whatsapp::HealthService` clamps it upward to 24.0 (`health_service.rb:18, 45-46`). `FacebookApiClient` hardcodes
`BASE_URI` and ignores `WHATSAPP_CLOUD_BASE_URL`, which the provider services honour — so a mock host set for tests
covers the provider but not the Graph client.

**Base URL.** `ENV['WHATSAPP_CLOUD_BASE_URL']`, default `https://graph.facebook.com`
(`whatsapp_cloud_service.rb:115-117`, `csat_template_service.rb:124-141`).

---

## 4. Identity, tenancy and credentials

### 4.1 A template's identity

- **Meta's identity is `(WABA, name, language)`, or the Meta template `id`.** Names are not unique across languages.
- **`id` is present on some synced templates and absent on others** — proven by the factory:
  `spec/factories/channel/channel_whatsapp.rb:74` carries `'id' => '9876543210987654'`, while
  `:6-18` has no `id` at all.
- **Three dedupe schemes coexist and disagree:**
  1. `(name, language)`, case-insensitive on language and status, **exact on name** —
     `template_processor_service.rb:22-26`, `authentication_template_guard.rb:21-23`,
     `contact_info_request_eligibility_service.rb:111-112`, `custom/app/services/flows/template.rb:18`,
     `inbox_health_management.rb:25` (`?name=`), `TemplateEditor.vue:39` (`` `${name}|${language}` ``, exact case).
  2. Meta's `id` alone — `WhatsAppCampaignForm.vue:86` uses `template.id` as the dropdown option value, so a template
     with no `id` is **unselectable** and `selectedTemplate` (`:93-96`) never resolves.
  3. `[platform, business_account_id || account_sid || inbox.id, template.id || content_sid, language]`, falling back to
     stringifying the whole template object — `templateUtils.js:38-47`. Two inboxes on one WABA merge into one row;
     two inboxes on different WABAs do not.

  Any new storage must keep all three working or fix them together.

### 4.2 Tenancy

- `Channel::Whatsapp` includes `Channelable` → `belongs_to :account`, `has_one :inbox, as: :channel`
  (`app/models/concerns/channelable.rb:4-7`). **One channel ↔ exactly one inbox.**
- `phone_number` is a real column, `null: false`, **globally unique** (`db/schema.rb:795, 806`).
- `phone_number_id` and `business_account_id` (the WABA) are **not columns** — they are keys inside the
  `provider_config` jsonb, set at `channel_creation_service.rb:54-55`, `manual_setup_service.rb:40-41`,
  `reauthorization_service.rb:36-37`.
- **One account can have many WhatsApp inboxes** (`app/models/account.rb:105` `has_many :whatsapp_channels`;
  no uniqueness on `account_id`).
- **One account can span many WABAs, and many inboxes can share one WABA.** `business_account_id` has no uniqueness,
  no index and no validation anywhere; `Whatsapp::WebhookSetupService` already queries sibling channels by WABA.
  **Do not assume one WABA per account** (PART 16).

### 4.3 The token discrepancy — must be resolved before the first write

```ruby
# app/models/channel/whatsapp.rb:85-89
def template_access_token
  return provider_config['api_key'] unless ChatwootApp.chatwoot_cloud? && provider_config['source'] == 'embedded_signup'
  business_management_token.presence || provider_config['api_key']
end
```

The **sync reads** with `template_access_token` (`whatsapp_cloud_service.rb:48`). The **CSAT create/delete writes**
with `provider_config['api_key']` directly (`csat_template_service.rb`). On an embedded-signup cloud install those are
different tokens, and template management is a `whatsapp_business_management` operation. A manager that copies CSAT's
choice would read every template and fail every write. **P3's writes use `template_access_token`.**

---

## 5. Every consumer of `message_templates`

### Backend — direct column access

| File:line | R/W | What |
|---|---|---|
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb:41` | R | compares fetched vs stored to decide the cache-key bump |
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb:43` | **W** | `update_columns` full replace |
| `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb:31` | **W** | `update` full replace, validated |
| `app/models/channel/whatsapp.rb:139-144` | **W** | timestamp only, `update_column` |
| `app/services/whatsapp/template_processor_service.rb:22-27` | R | the lookup that every send depends on; **no `Array()` guard** |
| `app/services/whatsapp/authentication_template_guard.rb:20-24` | R | name+language, **no status filter**; blocks AUTHENTICATION to a BSUID recipient |
| `app/services/whatsapp/contact_info_request_eligibility_service.rb:106-118` | R | approved templates carrying a `REQUEST_CONTACT_INFO` button |
| `custom/app/services/flows/template.rb:17-20, 77` | R | the flow-builder lookup and its error classification |
| `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:110` | R | `message_template_data`; Twilio branch at `:112` uses `content_templates['templates']` with name key `friendly_name` |
| `app/views/api/v1/models/_inbox.json.jbuilder:144-146` | R | emits `message_templates` on every inbox payload, `if resource.whatsapp?`, coerced to `[]` when not an Array |

### Backend — indirect (through `TemplateProcessorService` or `Flows::Template`)

`app/services/whatsapp/send_on_whatsapp_service.rb:30-51` (composer + API send) ·
`app/services/whatsapp/oneoff_campaign_service.rb:83-107` (OSS campaign) ·
`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:60-84` (EE campaign) ·
`app/services/whatsapp/liquid_template_processor_service.rb` · `…/template_parameter_converter_service.rb` ·
`…/populate_template_parameters_service.rb` · `custom/app/services/flows/nodes/send_template.rb:19, 29-30, 42-54` ·
`custom/app/services/flows/template_validator.rb:23, 41, 50-51, 68, 71` · `custom/app/services/flows/node_validator.rb:46`.

CSAT is **not** in this list: CSAT templates live only at Meta and are read back by name
(`csat_template_service.rb:29-47`). They are never written into `message_templates`.

### HTTP surface and authorization

- `GET  /api/v1/accounts/:id/inboxes/:id/message_templates` — `config/routes.rb:300` →
  `inbox_health_management.rb:19-31`. 422 for a non-WhatsApp inbox (`:20-22`), optional `?name=` (`:25`), response
  `{ payload: [...], meta: { last_sync_attempt_at: … } }` (`:27-30`).
- `POST /api/v1/accounts/:id/inboxes/:id/sync_templates` — `config/routes.rb:303` → `:10-17`.
- `InboxPolicy#message_templates?` returns **true for any inbox member** (`app/policies/inbox_policy.rb:43-45`, with a
  comment at `:37-42` explaining why a membership test there would be wrong); `sync_templates?` is
  `administrator?` (`:71-73`). **A write action must not copy the read pattern.**
- Swagger: `swagger/paths/index.yml:427-428`, `swagger/swagger.json:6213`,
  `swagger/definitions/request/campaign/whatsapp_template_params.yml:7`.

### Frontend

- API: `app/javascript/dashboard/api/inboxes.js:32-34` (`syncTemplates`), `:36-41` (`getMessageTemplates`, passes a
  request `config` so an AbortSignal works).
- Store getters (`app/javascript/dashboard/store/modules/inboxes.js`): `getWhatsAppTemplates` (`:36-52`) returns
  `inbox.message_templates || inbox.additional_attributes.message_templates`, **unfiltered and possibly not an Array**;
  `getFilteredWhatsAppTemplates` (`:53-73`) adds `Array.isArray` and `filter(isSendableTemplate)`.
  Action `syncTemplates` at `:313-319`.
- **Deep camelCasing renames keys inside each template.** `inboxes.js:33-35` (`getAllInboxes`) and `:92-97`
  (`getInboxById`), plus `components-next/NewConversation/helpers/composeConversationHelper.js:103, 247`, apply
  `camelcaseKeys(…, { deep: true })` — so templates reached that way carry `parameterFormat` and `rejectedReason`,
  while the two getters above carry `parameter_format` and `rejected_reason`. Both shapes are live.
- Vue consumers: `ReplyBox.vue:217-224` (deliberately not channel-gated, see the comment at `:214-216`) ·
  `WhatsappTemplates/TemplatesPicker.vue:31-68` · `WhatsappTemplates/Modal.vue` · `WhatsAppTemplateReply.vue` ·
  `components-next/NewConversation/components/WhatsAppOptions.vue:21-45` ·
  `…/Campaigns/…/WhatsAppCampaignForm.vue:36-37, 76-96` ·
  `routes/dashboard/settings/flows/components/TemplateEditor.vue:27-61` ·
  `…/NewConversation/components/ComposeNewConversationForm.vue:93-97`.
- Specs pinning the contract: `app/javascript/dashboard/store/modules/specs/inboxes/getters.spec.js:110-404`
  (null, the string `'invalid'`, mixed status, interactive, location, authentication, and the
  `additional_attributes` fallback precedence at `:345` and `:380`).

---

## 6. The three defects this phase inherits

### 6.1 A non-approved template still reaches `channel.send_template` — PROVEN BY RUNNING IT

`Whatsapp::TemplateProcessorService#find_template` does filter on `status == 'approved'`
(`template_processor_service.rb:21-27`), but `process_template_with_params` returns the **caller's** name:

```ruby
# app/services/whatsapp/template_processor_service.rb:12-19
[template_params['name'], template_params['namespace'], template_params['language'], processed_templates_params]
```

and every caller guards on that name alone:

```ruby
# app/services/whatsapp/send_on_whatsapp_service.rb:39-42
if name.blank?
  message.update!(status: :failed, external_error: 'Template not found or invalid template name')
  return
end
```

A throwaway spec run against this HEAD printed:

```
PENDING  -> name="order_shipped"     namespace=nil lang="en_US" params=nil
UNKNOWN  -> name="no_such_template"  params=nil
APPROVED -> name="order_shipped"     params=[]
```

So for a pending, rejected, paused, disabled, deleted, wrong-language or entirely unknown template, `name` is
present, the guard does **not** fire, and `channel.send_template` is called with `parameters: nil`, which the provider
turns into `components: []` (`whatsapp_cloud_service.rb:226`). Meta refuses it; Lynomia never did.
For a parameterless template, `nil` parameters are indistinguishable from "none needed".

The same `name.blank?`-only guard is in `app/services/whatsapp/oneoff_campaign_service.rb:91-93` and
`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:68-72`.

**All three send paths share `Whatsapp::TemplateProcessorService`, so one fix closes all three** — derive the returned
name/namespace/language from the *found* template, which makes the existing guards correct instead of adding new ones.
PART 2.2 requires this to be structural; today it is accidental and incomplete.

The approval gates that *do* work are elsewhere and are all advisory to the send: `Flows::Template.problem` at flow
publish time (`custom/app/services/flows/template.rb:26`), `isSendableTemplate` in the pickers
(`store/modules/inboxes.js:72`), and the CSAT pre-send status check (`csat_survey_service.rb:77-89`).

### 6.2 Template status webhooks cannot arrive — two independent reasons

1. **Not subscribed.** `Whatsapp::WebhookSetupService#subscribed_fields` returns `%w[messages smb_message_echoes]`
   plus `calls` when voice is on (`webhook_setup_service.rb:86-89`);
   `FacebookApiClient::WEBHOOK_DEFAULT_FIELDS` is the same pair (`facebook_api_client.rb:9`).
   `message_template_status_update` appears nowhere in `app/`, `enterprise/`, `custom/` or `lib/`.
2. **Even if subscribed, the event would be dropped.**
   `Webhooks::WhatsappEventsJob#find_channel_from_whatsapp_business_payload` takes the payload branch whenever
   `object == 'whatsapp_business_account'` and resolves the channel only from
   `entry[0].changes[0].value.metadata.phone_number_id` — which a WABA-level template payload does not carry. The
   channel resolves to nil and the event is discarded, even though the URL's `phone_number` param (which
   `Webhooks::WhatsappController` already uses for signature verification) would have identified the channel.

So today a template's status moves **only** on the 3-hourly poll or a manual sync. PART 4 fixes both halves.

### 6.3 `WhatsAppOptions.vue:43-45` is an unguarded crash

`template.components.find(c => c.type === 'BODY').text` throws for any template without a BODY component, and
`components` is optional in the shared type. It is shielded today only because `isSendableTemplate` requires
`components` — widening what the composer lists breaks it.

---

## 7. Variables: six lists, no registry (input to PART 12)

**The real resolvers** are the Liquid drops in `app/drops/`: `ContactDrop` (`name`, `email`, `phone_number`,
`first_name`, `last_name`, `custom_attribute.<key>`, `id`), `UserDrop`, `ConversationDrop` (`id` **= `display_id`**,
`display_id`, `contact_name`, `recent_messages`, `custom_attribute.<key>`), `InboxDrop` (`name`, `business_name`,
`email`, `avatar_url`), `AccountDrop` (`name`), all inheriting `id`/`name` from `BaseDrop`.

**Drop sets differ per context:** `Liquidable#message_drops` (`app/models/concerns/liquidable.rb:12-20`) gives
`contact, agent, conversation, inbox, account`; `Whatsapp::LiquidTemplateProcessorService#drops` (`:37-44`) gives
`contact, agent, inbox, account` — **no `conversation`**; `app/helpers/email_helper.rb:48-53` has no `agent`.

**The six lists:**

1. `Flows::Variables` (`custom/app/services/flows/variables.rb:16-24`) — the only list **enforced** server-side
   (`node_validator.rb:143-149`, `template_validator.rb:65`).
2. `MESSAGE_VARIABLES` (`app/javascript/shared/constants/messages.js:101-154`), rendered by `VariableList.vue`.
3. `getMessageVariables` (`@chatwoot/utils/src/canned.ts:42-94`), used by `ReplyBox.vue:469-473`.
4. `getAgentVariables` / `getContactVariables` (`app/javascript/dashboard/helper/editorHelper.js:470-492`).
5. `Flows::Variables::SUGGESTED` as served to the builder (`custom/app/controllers/api/v1/accounts/flows_controller.rb:125`
   → `flowGraph.js:192-199` → `TemplateEditor.vue:84-86`).
6. **Nothing at all** for WhatsApp template parameter fields in the composer and campaigns —
   `WhatsAppTemplateParser.vue:239-337` is bare inputs, Liquid-rendered server-side with no allow-list.

**Where they disagree, and what it costs:**

- **`contact.phone` resolves nowhere.** Listed at `messages.js:128` and `canned.ts:63`; `ContactDrop` implements only
  `phone_number`. In the composer it is masked because the editor resolves it client-side into literal text; typed into
  a **campaign** parameter it renders blank, and a blank render **skips the entire recipient**
  (`liquid_template_processor_service.rb:21, 46-65`; OSS logs at `oneoff_campaign_service.rb:75`, EE records
  `'Template parameters could not be resolved'`). One typo drops the whole audience.
- `conversation.id` resolves (to `display_id`) and is offered, but `Flows::Variables` rejects it; flows must use
  `conversation.display_id`, which lists 2 and 3 omit.
- `account.name` resolves everywhere and is suggested for flows, but is absent from the composer's picker.
- `contact.custom_attribute.*` is allowed by `CHATWOOT` but not in `SUGGESTED`, so the flow builder never offers it.
- `flow.reply`, `flow.<key>` and `flow.order.*` have **no resolver outside a flow run**; in a campaign they render
  blank and skip the recipient.
- `inbox.business_name`, `inbox.email`, `agent.available_name`, `conversation.recent_messages` and friends resolve
  wherever there is no allow-list and are rejected in flows.

**Commerce variables today** are only `Flows::Variables::ORDER_FIELDS` → `flow.order.{number, status, payment_status,
tracking_number, tracking_url}` (`variables.rb:18`), populated solely by `Flows::Nodes::CommerceLookup#found`
(`custom/app/services/flows/nodes/commerce_lookup.rb:64-70`) — i.e. **only after a Commerce Lookup node matched in the
same flow session.** There is no `abandoned_cart_url` and no store-name variable anywhere in the codebase.
PART 12's rule — do not offer a variable no send context can resolve — has a concrete list to work from.

**Parameter limits already encoded in Ruby:** `sanitize_parameter` strips `< > " '` and truncates to **1000** chars
(`populate_template_parameters_service.rb:135-140`); `validate_url` requires http/https and ≤ **2000** chars
(`:151-162`); a `copy_code` coupon must be 1–**15** chars (`:19-20`, mirrored by `Flows::Template::COPY_CODE_MAX = 15`);
`Flows::Variables::MAX_VALUE = 1024` — **larger than the 1000-char truncation**, so a 1001–1024-char value passes flow
publish validation and is then silently truncated at send.

---

## 8. The management page that exists today

Read-only, live, not behind a flag. `WHATSAPP_TEMPLATE_MGMT` is an **i18n namespace, not a feature flag** — it appears
only in `i18n/locale/*/whatsappTemplateMgmt.json` and as `$t(...)` keys in the three Vue files below.

- Route: `routes/dashboard/settings/templates/templates.routes.js:9-19` — `accounts/:accountId/settings/templates`,
  name `settings_templates`, `meta: { permissions: ['administrator'] }`; registered at `settings.routes.js:17, 64`.
- No dedicated controller: the page fans out one `InboxesAPI.getMessageTemplates` per WhatsApp/Twilio inbox
  client-side (`Index.vue:228-250`, `Promise.allSettled`, `Array.isArray(data.payload)` required).
- Cross-inbox grouping and dedupe in `templateUtils.js:23-88`; label/language/date/status-tone helpers at `:90-139`.
- Filters by inbox / language / type (`Index.vue:88-124, 181-200`); exact substring search with a `picoSearch` fuzzy
  fallback (`:202-213`); refetch on `onActivated`, abort on `onDeactivated` (`:327-328`).
- `TemplateCard.vue:25-32` hides the status chip when approved and already special-cases `unsubmitted`.
- `TemplatePreviewDrawer.vue:28-57` renders through `TemplateNormalizer` + `components-next/template-preview/`, and
  links out: `META_TEMPLATE_MANAGER_URL = 'https://business.facebook.com/latest/whatsapp_manager/message_templates'`.
- Navigation: `components-next/sidebar/Sidebar.vue:829-834`, command palette
  `composables/commands/useGoToCommandHotKeys.js:167-172`.

**What it does not do:** create, edit, delete, submit, duplicate, draft, per-template URL or detail route, category or
variable editing, or persist anything (everything lives in `ref`s and a `Map`). Its own description string says
"View the message templates…".

**`STATUSES.UNSUBMITTED = "Not submitted for WhatsApp approval"`** already exists
(`i18n/locale/en/whatsappTemplateMgmt.json:22`, consumed at `TemplateCard.vue:30` and
`TemplatePreviewDrawer.vue:60`) with **no producer** — Meta never returns it. P3 reuses this vocabulary for a local
draft rather than inventing a parallel one, which also satisfies PART 5's "do not call a local draft Pending".

---

## 9. The CSAT lifecycle, and the P0 safeguard that must not regress

CSAT has its own template lifecycle and must keep it (PART 9).

- `CSAT_BASE_NAME = 'customer_satisfaction_survey'`; names are `customer_satisfaction_survey_<inbox_id>[_<version>]`
  (`app/services/csat_template_name_service.rb:2, 6-9, 36-46`). `generate_next_template_name` (`:19-25`) bumps the
  version — **this versioning is what dodges Meta's 30-day same-name block after a delete, and is load-bearing.**
- **The P0 safeguard is the absence of a delete before a create.** `app/services/csat_template_management_service.rb:23-32`
  goes straight to `create_template_via_provider`, with the comment at `:26-28` recording why the old call
  (`delete_existing_template_if_needed`) was removed: deleting took CSAT offline for the days Meta needs to approve the
  replacement. `rg -n delete app/services/csat_template_management_service.rb` returns nothing.
- `Whatsapp::CsatTemplateService#delete_template` (`:20-27`) and
  `Whatsapp::Providers::WhatsappCloudService#delete_csat_template` (`:86-89`) are live, tested code with **zero
  production callers** — one call site away from regressing the fix. Worse, `delete_template`'s default argument is the
  **unversioned** base name, and a name-scoped DELETE removes **every language**.
- `app/services/csat_survey_service.rb:77-89` keeps CSAT on the old approved template until Meta approves the new one,
  checking status live per survey; `:107-135` bypasses `SendOnWhatsappService` entirely and hardcodes its parameters.
- There is **no spec for `CsatTemplateManagementService`** anywhere in `spec/`, so the safeguard is currently
  unprotected by any test.

---

## 10. Conventions P3 must follow

- **Three trees.** `app/` (OSS), `enterprise/` (EE), `custom/` (Lynomia), joined by `prepend_mod_with` /
  `include_mod_with`; `ChatwootApp.extensions == %w[enterprise custom]`. **`custom/` contains no frontend files at
  all** — every Vue/JS change goes in `app/javascript`.
- **None of the send-path services has an overlay.** The `prepend_mod_with` hooks in this area are
  `Whatsapp::OneoffCampaignService:148`, `Whatsapp::Providers::WhatsappCloudService:258`,
  `Whatsapp::Providers::BaseService:136`, `Channel::Whatsapp:205` and `Messages::MessageBuilder:237`.
  `SendOnWhatsappService`, `TemplateProcessorService` and the parameter services have none — so a fix in `app/`
  is the whole fix.
- **Lynomia models and services live under `custom/`** with `self.table_name` set explicitly
  (`custom/app/models/commerce/store.rb`), and `serializable_hash` excluding secrets.
- **Lynomia migrations live in `custom/db/migrate/`** — the additive template to copy is
  `custom/db/migrate/20261004100000_create_flow_versions.rb` (`t.references … foreign_key: { on_delete: :cascade }`,
  partial unique indexes).
- **Lynomia routes live in their own file** drawn from `config/routes.rb` (`draw :flows`, `draw :commerce`).
- Test environment: `config/environments/test.rb:11` sets `cache_classes = false`, so editing app code during a running
  suite trips a Zeitwerk reload; two concurrent `rspec` processes corrupt `tmp/cache/bootsnap`; and
  `installation_configs` rows can commit outside the transactional fixture and poison later runs.

---

## 11. Open questions this doc does not answer

- Meta's default page size for the template list edge at v24.0, and therefore whether a very large WABA's catalogue is
  safe to hold as one jsonb document. The sync passes no `limit` and caps no pages
  (`whatsapp_cloud_service.rb:47-62`).
- Whether `message_templates` is ever populated for a non-WhatsApp channel in this installation.
  `ReplyBox.vue:214-216` comments that API inboxes are supported "if someone updates templates manually via API", and
  the store getter falls back to `inbox.additional_attributes.message_templates` (spec'd at
  `getters.spec.js:380-402`), but `_inbox.json.jbuilder:144` emits the field only `if resource.whatsapp?`.
- `GlobalConfigService.load` precedence between an `InstallationConfig` row, an ENV var of the same name and the passed
  default. Verified only that `WHATSAPP_API_VERSION` is seeded `v24.0`, `locked: false`.
