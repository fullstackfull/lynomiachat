# WhatsApp template current state, and the Meta API proof

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Provenance: the `whatsapp_current` and `meta_api_proof` area inventories, corrected by the `meta-template-api` adversarial
verifier. Where they disagreed the verifier wins and the line is marked **(V)**. Meta-side constraints are the verifier's,
read from Meta's normative template-management page, not the inventory's wider node-reference list. Claims I could not
cite are marked **UNVERIFIED**. The inventory's `quality_score` file citation was fabricated and is not repeated — see
§3.6.

---

## 1. The decision in one page

**Lynomia is a template *reader*. It is not a template manager, and it should not become one in this program.**

The entire WhatsApp template surface is one 3-hourly poll of Meta's list endpoint into a single `jsonb` column, plus a
read-only inventory page, plus a well-built send path. There is exactly one write path to Meta's template API in the whole
repo and it exists to maintain a single auto-generated CSAT survey template. There is no edit call, no single-template
GET, no status webhook, no rejection reason, no versioning, and no local per-template record to hang any of that on.

The important finding is that **this is mostly the right architecture and the gaps that matter are not the obvious ones.**

| What a product owner might assume is the gap | Actual verdict |
|---|---|
| "We should build template authoring in Lynomia" | **DO NOT CREATE.** Meta allows it, but authoring means owning example-value validation, category review, 30-day name blocks and pacing. The UI already says "manage it with your provider" (`app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json:4`) and deep-links to WhatsApp Manager. That is a defensible product position, not a hole. |
| "Template status is stale, we need the webhook" | **NEW PRIMITIVE REQUIRED, and it is the highest-value template work available.** Up to 3 hours of staleness on a value that gates sending. But it needs an app-default callback route that does not exist — Meta refuses to deliver the four template fields to a per-phone override. See §4.1. |
| "Rejection reasons are missing data" | **PATCH, cheap.** The data is already in the column; nothing reads it. Pure UI. See §4.2. |
| "Template versioning is a feature we lack" | **DO NOT CREATE.** Meta exposes no version, duplicate or clone operation at all **(V)**. There is nothing to mirror. |

Three live defects are flagged in §5. One of them (the Graph v14.0 pin) will take template sync offline when Meta enforces
it, if it has not already.

---

# HALF ONE — what the repo does today

## 2. The whole WhatsApp surface

### 2.1 Two providers, and only two

`Channel::Whatsapp::PROVIDERS = %w[default whatsapp_cloud]` (`app/models/channel/whatsapp.rb:36`).

| Provider | Service | Template sync | Classification |
|---|---|---|---|
| `whatsapp_cloud` (Meta Graph) | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:1-261` | `GET {base}/v14.0/{business_account_id}/message_templates`, cursor-paged (`:47-62`) | **REUSE** |
| `default` (360dialog) | `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb:1-127` | `GET {base}/configs/templates`, stores `response['waba_templates']` (`:27-32`). No pagination, no error logging, uses `update` not `update_columns` | **DO NOT CREATE** — unreachable from the add-inbox UI except by hand-crafting `?provider=360dialog` (`.../channels/Whatsapp.vue:301-303` renders the form; `availableProviders` at `:92-119` never offers it) |

Everything below is `whatsapp_cloud` unless stated. 360dialog has no health service, no webhook setup/teardown, no media
upload and no template write path.

### 2.2 Template storage — one jsonb column, no table, no model, no row

```
app/models/channel/whatsapp.rb   →  channel_whatsapp
db/schema.rb:800                 →  t.jsonb   "message_templates", default: {}
db/schema.rb:801                 →  t.datetime "message_templates_last_updated", precision: nil
```

That is the entire persistence layer. Confirmed by reading `db/schema.rb:792-808`: there is no templates table, no
per-template primary key, no join to inboxes, no history table and no status column.

Consequences that are load-bearing for any build decision:

- **No stable local identity.** The frontend has to synthesize a key from `(platform, provider account, Meta template id,
  language)` in `app/javascript/dashboard/routes/dashboard/settings/templates/templateUtils.js:31-47` precisely because no
  local record exists.
- **The column default is `{}` (a Hash) while every writer stores an Array** (`db/schema.rb:800` vs
  `whatsapp_cloud_service.rb:43`). Harmless today — the serializer coerces non-Arrays to `[]`
  (`app/views/api/v1/models/_inbox.json.jbuilder:146`) and `Flows::Template.find` wraps in `Array()`
  (`custom/app/services/flows/template.rb:17`) — but `Whatsapp::TemplateProcessorService#find_template` calls `.find`
  directly on the column value (`app/services/whatsapp/template_processor_service.rb:22`). Flagged, not a defect I can
  demonstrate.
- Twilio WhatsApp uses a *separate* column, `channel_twilio_sms.content_templates` (`db/schema.rb:749-750`). The settings
  page unifies the two client-side.

Any per-template state — a local status, a rejection reason you want to keep after Meta drops it, an approval timestamp, a
revision — **requires a migration**. Stated here as a requirement; left for approval, not proposed.

### 2.3 The 3-hourly sync writes Meta's `data` array verbatim

```ruby
# app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45
def sync_templates
  whatsapp_channel.mark_message_templates_updated          # :37 — stamp FIRST so a bad config can't loop
  return if (templates = fetch_whatsapp_templates).blank?
  whatsapp_channel.account.update_cache_key('inbox') if templates != whatsapp_channel.message_templates
  whatsapp_channel.update_columns(message_templates: templates, ...)   # :43 — verbatim, validation-skipping
end
```

- `fetch_whatsapp_templates` (`:47-62`) sends **no `fields=` parameter and no documented filter**; it recurses on
  `paging.cursors.after` (`:57-61`) and returns `response['data']` unmapped. Nothing is normalized, filtered or discarded
  at write time.
- Triggered three ways: `after_create :sync_templates` on the channel (`app/models/channel/whatsapp.rb:46`); the scheduler
  (below); and an admin-only `POST /inboxes/:id/sync_templates` (`config/routes.rb:303`).
- Scheduler: `app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-13` picks active-account channels whose
  `message_templates_last_updated` is NULL or `<= 3.hours.ago`, capped at `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`, and
  enqueues `Channels::Whatsapp::TemplatesSyncJob` (`app/jobs/channels/whatsapp/templates_sync_job.rb:1-7`, queue `:low`).
- Auth: `channel.template_access_token` (`app/models/channel/whatsapp.rb:84-88`) — the encrypted
  `business_management_token` only on Chatwoot Cloud with `provider_config['source'] == 'embedded_signup'`, otherwise
  `provider_config['api_key']`.

**The practical statement**: nothing is discarded, but any field outside `name`, `language`, `status`, `category`,
`namespace`, `components`, `parameter_format` and `id` is **never read by any code path**. `rejected_reason`,
`previous_category`, `sub_category` and the rest transit to the browser as dead data. `quality_score`,
`message_send_ttl_seconds`, `cta_url_link_tracking_opted_out` and `product_set_id` are not named anywhere in the repo at
all (`grep -rni` over `app enterprise custom lib spec config db` → zero hits, verified).

### 2.4 The READ endpoints

| Surface | Path | Auth |
|---|---|---|
| `GET /api/v1/accounts/:id/inboxes/:inbox_id/message_templates` | `config/routes.rb:300`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:19-31` | **Any account user** — `InboxPolicy#message_templates?` returns `true` unconditionally (`app/policies/inbox_policy.rb:37-39`) |
| `message_templates` inlined in the inbox JSON | `app/views/api/v1/models/_inbox.json.jbuilder:144-146` | Same as inbox read |
| `POST /inboxes/:id/sync_templates` | `config/routes.rb:303` | Administrator (`inbox_policy.rb:64-66`) |

The controller returns the stored jsonb **untouched** (`inbox_health_management.rb:27-30`), with an optional local
`?name=` filter at `:25` and `meta.last_sync_attempt_at`. There is no POST/PATCH/DELETE sibling. The frontend client has
no `createTemplate`/`updateTemplate`/`deleteTemplate` method (`app/javascript/dashboard/api/inboxes.js:32-50`, verified
— only `syncTemplates`, `getMessageTemplates`, `updateWhatsappBusinessManagementToken`, `createCSATTemplate`,
`getCSATTemplateStatus`, `analyzeCSATTemplateUtility`).

**Settings → Templates** (`app/javascript/dashboard/routes/dashboard/settings/templates/`, route
`templates.routes.js:14-18`, administrator-only) fans the read endpoint across every WhatsApp and Twilio-WhatsApp inbox,
dedupes, filters client-side by inbox/language/type, fuzzy-searches and previews. Its only two actions are **Sync** and an
external **"Manage in Meta"** link to `business.facebook.com/latest/whatsapp_manager/message_templates`
(`TemplatePreviewDrawer.vue:28-29`). Despite the `WHATSAPP_TEMPLATE_MGMT` i18n namespace it is an inventory viewer.
Classification: **REUSE** as the host for any new read-side surface.

### 2.5 The SEND chain

```
Whatsapp::SendOnWhatsappService#send_template_message        app/services/whatsapp/send_on_whatsapp_service.rb:30-50
  └─ Whatsapp::TemplateProcessorService#call                 app/services/whatsapp/template_processor_service.rb:1-134
       ├─ find_template  (name == , language casecmp, status casecmp 'approved')      :21-27
       ├─ Whatsapp::TemplateParameterConverterService         .../template_parameter_converter_service.rb:11-119  (V)
       └─ Whatsapp::PopulateTemplateParametersService         .../populate_template_parameters_service.rb:1-163
  └─ channel.send_template → provider.send_template           app/models/channel/whatsapp.rb:147
       └─ template_body_parameters                            whatsapp_cloud_service.rb:196-231
```

- Driven by `message.additional_attributes['template_params']` (`send_on_whatsapp_service.rb:58-60`), shaped
  `{name, namespace, language, category, content_mode, processed_params: {body, header, footer, buttons}}` — the documented
  public contract is `swagger/definitions/request/campaign/whatsapp_template_params.yml:1-46`, which covers **sending
  only**; no create/update/delete schema exists in `swagger/`.
- `PopulateTemplateParametersService` builds Meta parameter objects for text, named (`parameter_name`), currency,
  date_time, image/video/document media (**always by public `link`**, never a media handle — `:33-40,:93-119`) and
  `coupon_code` (≤15 chars, raises `ArgumentError`). It sanitizes by stripping `<>"'` and truncating to 1000 chars.
- `TemplateProcessorService` honours `parameter_format == 'NAMED'` (`:83,:95`) — named templates build named parameters and
  skip numeric sorting; POSITIONAL sorts body keys by integer index.
- `Whatsapp::AuthenticationTemplateGuard` (`app/services/whatsapp/authentication_template_guard.rb:1-29`) blocks
  AUTHENTICATION-category templates to BSUID recipients — but it is called **only from the campaign paths**
  (`oneoff_campaign_service.rb:109-115` and the EE overlay `:95-101`). `SendOnWhatsappService` does not call it.
- `Whatsapp::TemplateContentRendererService` and `Whatsapp::LiquidTemplateProcessorService` render the human-readable body
  and per-contact Liquid respectively; `Liquidable` (`app/models/concerns/liquidable.rb:51-96`) flips `content_mode` from
  `raw_template` to `rendered` before create.

**Send path does not fail closed on an unknown template.** `processed_templates_params` returns `nil` when `find_template`
misses (`template_processor_service.rb:30-32`), but `name` comes straight from the caller (`:14`), so
`SendOnWhatsappService`'s only guard — `if name.blank?` (`send_on_whatsapp_service.rb:39`) — passes, and
`template_body[:components] = template_info[:parameters] || []` (`whatsapp_cloud_service.rb:228`) ships a live Graph call
with empty components. A template deleted at Meta, un-approved, or missing in the requested language produces a Meta
rejection surfaced only as `message.external_error`. Read from code; not executed. Classification: **PATCH** — one
`return` in `send_template_message`, zero schema change.

### 2.6 The Flow `send_template` node

`custom/app/services/flows/nodes/send_template.rb:11-62`. Emits one bot message whose content is the template body text and
whose `additional_attributes.template_params` is the composer shape, then lets Chatwoot's normal
`SendReplyJob`/`SendOnWhatsappService` path send it. It never substitutes free text; a template the inbox cannot send
follows the `failed` handle or fails the session with a code (`:33-35`).

Supporting Lynomia services, all **REUSE**:

- `Flows::Template` (`custom/app/services/flows/template.rb:10-97`) — reads `inbox.channel.message_templates`.
  `UNSUPPORTED_COMPONENTS = %w[LIST PRODUCT CATALOG CALL_PERMISSION_REQUEST]` (`:11`); `sendable?` (`:31-36`) excludes
  AUTHENTICATION, any name starting with the CSAT base name, and a `LOCATION`-format header. `problem` (`:23-29`) returns
  `template_not_found` / `template_language_unavailable` / `template_not_approved` / `template_not_allowed`.
- `Flows::TemplateValidator` (`custom/app/services/flows/template_validator.rb:6-79`) — publish-time validation; resolves
  templates only inside the account's own inboxes (`:33-35`).
- `Flows::ChannelCapabilities` (`custom/app/services/flows/channel_capabilities.rb:8-31`) — `template: true` only for
  `Channel::Whatsapp` with provider `whatsapp_cloud` (`:20`); `NODE_NEEDS` maps `send_template → :template`, so publishing
  the node to any other inbox is refused.
- UI: `.../settings/flows/components/TemplateEditor.vue`, wired at `NodeConfigPanel.vue:222-228`. Picker only.

### 2.7 Campaign template selection

`WhatsAppCampaignForm.vue:84-170` — inbox combobox → `templateOptions` from the `inboxes/getFilteredWhatsAppTemplates`
getter (`:32-33,:86`) → `WhatsAppTemplateParser.vue` → submits `template_params` (`:148,:160`). Submit is blocked until
every parameter is filled.

Execution: `Campaign#execute_campaign` dispatches on `inbox.inbox_type == 'Whatsapp'` (`app/models/campaign.rb:98-107`) to
`Whatsapp::OneoffCampaignService` (`app/services/whatsapp/oneoff_campaign_service.rb:1-148`), which requires provider
`whatsapp_cloud`, feature `whatsapp_campaign` and a `one_off` campaign (`:15-40`). The EE overlay replaces `perform` with
`CampaignRecipient` bookkeeping (`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:1-110`).

**The one sendability rule, in two places that must stay in sync**: `isSendableTemplate` from `@chatwoot/utils` via
`app/javascript/dashboard/store/modules/inboxes.js:53-72` (shared with the mobile app), mirrored server-side by
`Flows::Template.sendable?` (`custom/app/services/flows/template.rb:31-36`). Both exclude non-approved, AUTHENTICATION,
`customer_satisfaction_survey*`, LIST/PRODUCT/CATALOG/CALL_PERMISSION_REQUEST components and LOCATION headers.

### 2.8 Where Meta secrets live

| Secret | Location | Reaches the browser? |
|---|---|---|
| `WHATSAPP_APP_ID` | `config/installation_config.yml:154-157` | **Yes** — `app/views/layouts/vueapp.html.erb:45` |
| `WHATSAPP_CONFIGURATION_ID` | `config/installation_config.yml:158-161` | **Yes** — `vueapp.html.erb:46` |
| `WHATSAPP_APP_SECRET` (`type: secret`) | `config/installation_config.yml:162-166` | **No** — server-side only (`facebook_api_client.rb:15-16`, `webhooks/whatsapp_controller.rb:37`) |
| `WHATSAPP_API_VERSION` (default `v22.0`) | `config/installation_config.yml:167-171` | **Yes** — `vueapp.html.erb:47` |
| Per-inbox `api_key`, `phone_number_id`, `business_account_id` (= the WABA id), `verification_pin`, `app_secret` | `provider_config` jsonb | **No** — `SECRET_PROVIDER_CONFIG_KEYS` stripped at `_inbox.json.jbuilder:148`; the rest admin-only (`:147-149`) |
| `business_management_token` | encrypted column (`app/models/channel/whatsapp.rb:33`) | **No** — `serializable_hash` strips it (`:90-92`); only a boolean `business_management_token_configured` is exposed |

All four app-level values are edited in Super Admin under the `whatsapp_embedded` group
(`app/controllers/super_admin/app_configs_controller.rb:82`).

## 3. The write-call ledger — this is the load-bearing claim

**Every HTTP call the repo makes against `message_templates`, exhaustively** (`grep -rn 'message_templates' app enterprise
custom lib --include=*.rb | grep HTTParty`, plus a sweep of every `HTTParty.post/delete/patch/put` under
`app/services/whatsapp`, `enterprise/app/services`, `custom/app/services`):

| # | Call | Path:line | Purpose |
|---|---|---|---|
| 1 | `GET {waba}/message_templates` | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:50` | the 3-hourly sync |
| 2 | `GET {waba}/message_templates?access_token=` | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:66` | `validate_provider_config?` liveness probe |
| 3 | `GET {waba}/message_templates?limit=1` | `app/services/whatsapp/facebook_api_client.rb:52-57` | onboarding permission probe |
| 4 | `GET {waba}/message_templates?limit=1` | `app/services/whatsapp/business_management_token_validation_service.rb:28-32` | token validation |
| 5 | `GET {waba}/message_templates?name=` | `app/services/whatsapp/csat_template_service.rb:31` | **CSAT only** — reads `id, name, status, language` |
| 6 | **`DELETE {waba}/message_templates?name=`** | `app/services/whatsapp/csat_template_service.rb:23-26` | **CSAT only** |
| 7 | **`POST {waba}/message_templates`** | `app/services/whatsapp/csat_template_service.rb:99-103` | **CSAT only** |

Rows 6 and 7 are the only template **writes in the entire repository**. Both are reachable only through
`POST /inboxes/:id/csat_template` (`config/routes.rb:319-321`,
`app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb`), which accepts only
`{template: {message, button_text, language}}`. The create body is fixed: `category: 'UTILITY'`
(`csat_template_service.rb:5,:65`), one `BODY` component and one `BUTTONS[URL]` pointing at
`{base_url}/survey/responses/{{1}}` with `example: ['12345']` (`:70-96`).

Therefore, established:

1. **No edit call exists.** There is no `POST`/`PATCH` to a template id in `app/`, `enterprise/` or `custom/`. The four
   enterprise `HTTParty.post` calls in `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:24,
   37,46,76` are all WhatsApp Calling endpoints **(V)**.
2. **No single-template GET.** `GET /{TEMPLATE_ID}` is never called. Meta's template ids *are* persisted and reach the
   dashboard; nothing fetches by id. The only targeted lookup is the `?name=` list filter (row 5).
3. **No status webhook handling.** `message_template_status_update`, `message_template_quality_update`,
   `message_template_components_update` and `template_category_update` return **zero hits** across `app enterprise custom
   lib spec config` (verified). `WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes]`
   (`app/services/whatsapp/facebook_api_client.rb:4`); `subscribed_fields` adds only `calls`
   (`app/services/whatsapp/webhook_setup_service.rb:85-89`). `Webhooks::WhatsappEventsJob` branches on
   `smb_message_echoes` vs `messages` (`app/jobs/webhooks/whatsapp_events_job.rb:80-97`) and the EE overlay adds only
   `calls` — a template payload would be handed to `IncomingMessageWhatsappCloudService` as if it were a message.
4. **No rejection reason.** No production code reads `rejected_reason`. It occurs only in fixtures:
   `spec/factories/channel/channel_whatsapp.rb:15,24,33,84` **(V)** and
   `app/javascript/dashboard/store/modules/specs/inboxes/templateFixtures.js`.
5. **No versioning.** `message_templates` is overwritten wholesale by `update_columns`
   (`whatsapp_cloud_service.rb:43`); the only timestamp is the single `message_templates_last_updated` column; there is no
   versions table. The EE audit log deliberately skips template changes
   (`enterprise/app/models/enterprise/channelable.rb:24-25,:41-42` — early return when the only changed key is
   `message_templates_last_updated`).
6. **No quality surface at the template level.** `quality_score` appears **nowhere in the repository** —
   `grep -rni 'quality_score' app enterprise custom lib spec config db` returns zero hits, verified. The inventory's
   file citation for it was **fabricated**; it names no real location and must not be carried forward **(V)**. The repo's
   only quality surface is at the *phone-number* level: `Whatsapp::HealthService` reads Meta's phone-number
   `quality_rating` and logs on YELLOW/RED (`app/services/whatsapp/health_service.rb:25,39,106,151,226`) **(V)**.
7. **`Whatsapp::Providers::WhatsappCloudService#create_csat_template` / `#delete_csat_template`
   (`:82-89`) are dead code** — no caller in `app/`, `enterprise/` or `custom/`; `CsatTemplateManagementService`
   instantiates `Whatsapp::CsatTemplateService` directly. (`#get_template_status` at `:91-93` *is* used, from
   `app/services/csat_survey_service.rb:83`.) Classification: **PATCH** — delete them.

---

# HALF TWO — the Part 21 Meta API proof table

Meta column: the verifier's reading of Meta's normative pages, this session. Where Meta's template-management page and the
`whats-app-business-hsm` node reference disagree, **the normative page is used** — this is the correction that matters most
for anyone planning an edit feature. Permission is `whatsapp_business_management` for every management operation unless
noted.

| # | Operation | META | Endpoint | Constraints (normative) | REPO | path:line |
|---|---|---|---|---|---|---|
| 1 | **List** | SUPPORTED | `GET /{WABA_ID}/message_templates` | Filters `category, content, language, name, name_or_content, quality_score, status, since, until`; summary `total_count, message_template_count, message_template_limit, are_translations_complete` | **implemented**, but with **no filter and no `fields=`** — all filtering is client-side | `whatsapp_cloud_service.rb:47-62`; client filter `templates/Index.vue:181-214` |
| 2 | **Get one** | SUPPORTED | `GET /{TEMPLATE_ID}` | Returns `status, rejected_reason, quality_score, previous_category, sub_category, parameter_format, message_send_ttl_seconds, …` | **not implemented** | nowhere; nearest is the `?name=` list filter, CSAT-only, at `csat_template_service.rb:30-48` |
| 3 | **Create** | SUPPORTED | `POST /{WABA_ID}/message_templates` | Required `name` (`^[a-z0-9_]+$`, ≤512), `language`, `category` (UTILITY\|MARKETING\|AUTHENTICATION), `components`. Optional `allow_category_change` (default behaviour since 2025-04-09), `parameter_format`, `message_send_ttl_seconds`, `product_set_id`, **`sub_category`** **(V — a create param, not merely readable)**. 100 creates/WABA/hour; 250 templates per account unverified, 6,000 verified | **implemented for CSAT only** — `category` hardcoded UTILITY, one BODY + one URL button, `language` default `en`; `allow_category_change` and `parameter_format` never sent | `csat_template_service.rb:12-19,61-104`; route `config/routes.rb:319` |
| 4 | **Edit** | **CONDITIONAL** | `POST /{TEMPLATE_ID}` | Only `APPROVED`, `REJECTED` or `PAUSED` may be edited. **Editable fields are only `category`, `components` and `message_send_ttl_seconds` (V — the six-item node-reference list is NOT normative).** Components are replaced **wholesale**: "You cannot edit individual template components." The category of an **approved** template cannot be edited. Approved: **10 edits/30 days, 1 edit/24 h**; rejected/paused: unlimited. Re-approval is automatic unless review fails. The WABA *edge*'s own Updating section reads "You can't perform this operation on this endpoint" | **not implemented** — no POST to a template id anywhere | absent; UI defers by design: `whatsappTemplateMgmt.json:4` + `TemplatePreviewDrawer.vue:28-29` |
| 5 | **Delete** | SUPPORTED | `DELETE /{WABA_ID}/message_templates` | `name` (deletes **all languages**), `hsm_id`, `hsm_ids` (≤100). **"If you delete an approved template, you cannot create a new template with the same name for 30 days." (V — missed by the inventory; see §5.2)** | **implemented for CSAT only, by `name`** — `hsm_id`/`hsm_ids` never used | `csat_template_service.rb:21-28`; sole caller `csat_template_management_service.rb:189` |
| 6 | **Status** | SUPPORTED | `GET /{TEMPLATE_ID}?fields=status`, or `status` on the list edge | Enum `APPROVED, IN_APPEAL, PENDING, REJECTED, PENDING_DELETION, DELETED, DISABLED, PAUSED, LIMIT_EXCEEDED` | **implemented only via the 3-hourly bulk poll** (+ `?name=` for CSAT). Status is genuinely load-bearing: sends gate on `'approved'`. Badge map covers **five** states — approved, pending, rejected, paused, disabled **(V — no `unsubmitted` entry)**; IN_APPEAL, PENDING_DELETION, DELETED, LIMIT_EXCEEDED fall through to a neutral default | gates: `template_processor_service.rb:21-27`, `custom/.../flows/template.rb:26`, `contact_info_request_eligibility_service.rb:116`; badge `templateUtils.js:121-131`; `unsubmitted` handled separately at `TemplateCard.vue:29-30`, `TemplatePreviewDrawer.vue:59-60` |
| 7 | **Rejection reason** | SUPPORTED | `rejected_reason` on `GET /{TEMPLATE_ID}`; `reason` in the status webhook | Node enum `ABUSIVE_CONTENT, INVALID_FORMAT, NONE, PROMOTIONAL, TAG_CONTENT_MISMATCH, SCAM`. Webhook enum adds `CATEGORY_NOT_AVAILABLE, INCORRECT_CATEGORY, null` | **not implemented.** Value transits to the browser (stored verbatim, returned untouched) but no production reader exists | storage `whatsapp_cloud_service.rb:43`, passthrough `inbox_health_management.rb:27-30`; fixtures only at `spec/factories/channel/channel_whatsapp.rb:15,24,33,84` **(V)** |
| 8 | **Category change** | **CONDITIONAL** | `category` in `POST /{TEMPLATE_ID}` | A successful category edit re-triggers category validation **and** template review. Cannot change the category of an approved template. Requesting a category **review/appeal is NOT_SUPPORTED by API** — "A review can only be requested via WhatsApp Manager" | **not implemented (write).** Category is read for two hard send gates | read: `authentication_template_guard.rb:16-18`, `custom/.../flows/template.rb:32`; write: nowhere. `previous_category`/`correct_category` never read |
| 9 | **Quality rating** | SUPPORTED | `quality_score` on `GET /{TEMPLATE_ID}`; array filter on the list edge; `message_template_quality_update` webhook | Values `GREEN, YELLOW, RED, UNKNOWN`. Webhook value keys `previous_quality_score, new_quality_score, message_template_id, message_template_name, message_template_language` | **not implemented at template level** — zero occurrences of `quality_score` in the repo **(V)**. The only quality surface is per phone number | `app/services/whatsapp/health_service.rb:25,39,106,151,226` (phone-number `quality_rating`) **(V)** |
| 10 | **Duplicate / versioning** | **NOT_SUPPORTED** | — | Meta exposes no duplicate, copy, clone or version operation. The only sanctioned ways to a second copy are a new `(name, language)` create, or a Template Library create. Editing is destructive in place and Meta exposes no version history | **not implemented** — and there is nothing to mirror | storage overwritten wholesale `whatsapp_cloud_service.rb:43`; EE audit log skips it `enterprise/app/models/enterprise/channelable.rb:24-25,41-42` |
| 11 | **Template Library** | SUPPORTED | `POST /{WABA_ID}/message_templates` with `library_template_name` | `library_template_name` required; `library_template_button_inputs` required for library templates with buttons; `library_template_body_inputs` optional; `category` must be UTILITY for utility library templates. Not documented as auto-approved — customising sends it to review | **not implemented** — zero occurrences of `library_template_name`, `library_template_button_inputs`, `library_template_body_inputs` (verified) | absent |
| 12 | **Webhooks** (all four template fields) | SUPPORTED | Object `whatsapp_business_account`, fields `message_template_status_update`, `message_template_quality_update`, `message_template_components_update`, `template_category_update` | **"Template webhooks … do not support callback overrides"** — they always go to the Meta **app's default callback URL**, never a phone-level override | **not subscribed, not handled, not routable.** `WEBHOOK_DEFAULT_FIELDS` is `messages smb_message_echoes` + conditional `calls`; the **only** Meta webhook route is per-phone-number | `facebook_api_client.rb:4`; `webhook_setup_service.rb:85-89`; dispatcher `whatsapp_events_job.rb:80-97`; route `config/routes.rb:678-679` |

### 3.1 Two Meta behaviours with no repo representation at all

- **Pacing / pausing.** Meta holds messages from newly created, recently unpaused, or non-GREEN marketing and utility
  templates and returns `held_for_quality_assessment` on the messages endpoint. `held_for_quality_assessment` has **zero
  hits** in the repo. `PAUSED` renders as a generic warning badge (`templateUtils.js:126`) with no explanation.
- **Archival.** Meta auto-archives and deletes templates inactive for ≥12 months. `ARCHIVED`/`UNARCHIVED` are not in the
  badge map at all. A silently archived template becomes an un-sendable template with no operator-visible reason.

### 3.2 One field that looks like a Meta operation and is not

`namespace` is threaded from `template_params` through the send path but is only ever placed in the **360dialog** payload
(`whatsapp_360_dialog_service.rb:104`). `WhatsappCloudService#template_body_parameters` (`:196-231`) deliberately omits it
— correct, because Meta's Cloud template send takes `name` + `language` + `components` and no namespace. Listed so it is
not mistaken for a Meta template-management concept.

---

## 4. Classification of every capability discussed

| Capability | Classification | Why |
|---|---|---|
| Template list sync + storage | **REUSE** | Works. Add `fields=` and a `status` filter only if payload size becomes a problem; nothing today needs it. |
| Settings → Templates inventory page | **REUSE** | Correct host for any new read-side surface. |
| Send chain (`SendOnWhatsappService` → … → `send_template`) | **REUSE** | The most complete part of the subsystem: NAMED/POSITIONAL, media, coupon codes, sanitization, Liquid, campaigns, flows. |
| Flow `send_template` node + `Flows::Template`/`TemplateValidator`/`ChannelCapabilities` | **REUSE** | Fully wired, publish-time validated, capability-gated. |
| Rejection reason in the UI | **PATCH** | §4.2 — data already present, pure UI. |
| Status badge coverage for IN_APPEAL / ARCHIVED / PENDING_DELETION / DELETED / LIMIT_EXCEEDED | **PATCH** | Five map entries + i18n keys at `templateUtils.js:121-131`. |
| Send-path fail-closed on unknown template | **PATCH** | §2.5 — one `return` in `send_template_message`. |
| Dead `create_csat_template` / `delete_csat_template` wrappers | **PATCH** | Delete `whatsapp_cloud_service.rb:82-89`. |
| Graph API version unification | **PATCH** | §5.1 — the v14.0 pin is the urgent one. |
| `TemplateNormalizer` header examples | **PATCH** | §5.3. |
| Real-time template status (the four webhooks) | **NEW PRIMITIVE REQUIRED** | §4.1 — needs an app-default callback route that does not exist. |
| Per-template local record (status history, approval timestamps, retained rejection reason) | **NEW PRIMITIVE REQUIRED** | **Requires a migration.** Stated as a requirement; left for approval. |
| Generic template create / edit / delete UI | **DO NOT CREATE** | §4.3. |
| Template Library create | **DO NOT CREATE** | Only valuable alongside a generic authoring surface, which is **DO NOT CREATE**. |
| Template versioning / duplicate | **DO NOT CREATE** | Meta supports no such operation **(V)**. Nothing to mirror. |
| Category review / appeal from Lynomia | **DO NOT CREATE** | Meta: WhatsApp Manager only, not API **(V)**. |
| Template analytics (per-template delivery/read) | **DO NOT CREATE** *in this program* | No code requests Meta's analytics edges; campaign analytics are per `CampaignRecipient` (`WhatsAppCampaignAnalyticsPage.vue`). A separate decision, not a template-management gap. |
| 360dialog template parity | **DO NOT CREATE** | No UI entry point exists; the provider is effectively unreachable. |
| Coexistence offboarding (`account_offboarded` / `account_reconnected`) | out of scope here | Already recorded as not implemented in `docs/whatsapp-business/META-VERIFICATION.md` items 10, 11, 13; code agrees (zero hits for `account_offboarded`, `smb_app_data`, `smb_app_state_sync`). |

### 4.1 Real-time status — the one piece worth building, and its hard prerequisite

Today a status change takes **up to 3 hours** to appear (`templates_sync_scheduler_job.rb:8`) and is never pushed. Three
concrete consequences, each citable:

1. A template rejected or disabled at Meta keeps passing `status == 'approved'` in `find_template`
   (`template_processor_service.rb:21-27`) for up to 3 hours, and the send fails at Meta with only `external_error`.
2. A Meta-initiated **recategorisation to AUTHENTICATION** silently changes send behaviour, because category drives two
   hard gates (`authentication_template_guard.rb:16-18`, `custom/.../flows/template.rb:32`) — and
   `template_category_update` is not subscribed.
3. An edit made **in WhatsApp Manager — which the product's own UI instructs admins to use**
   (`whatsappTemplateMgmt.json:4`) — is invisible to Lynomia for up to 3 hours, because
   `message_template_components_update` is not subscribed.

**The prerequisite that makes this a NEW PRIMITIVE and not an EXTEND**: Meta states the four template fields *do not
support callback overrides* and are always delivered to the Meta **app's default callback URL** **(V)**. Lynomia's only
Meta webhook route is `webhooks/whatsapp/:phone_number` (`config/routes.rb:678-679`), and the phone-level override is
exactly what `WebhookSetupService` configures (`:105-110`). So there is **no endpoint these four fields could be delivered
to**. A WABA-level / app-default callback route, its signature verification and a `whatsapp_business_account` dispatcher
branch are all new. Subscription is a one-line change to `WEBHOOK_DEFAULT_FIELDS` (`facebook_api_client.rb:4`) and
`subscribed_fields` (`webhook_setup_service.rb:85-89`) — but it is the *last* step, not the first.

Whether a single app-default callback can be multiplexed to the right tenant from
`value.message_template_id` / `message_template_name` alone, given that `message_templates` has no local record to look
them up in (§2.2), is **UNVERIFIED** and is the first question any design must answer.

### 4.2 Rejection reason — the cheapest real win in the subsystem

The data already arrives and already reaches the browser (§3, row 7). An admin who sees a REJECTED badge today has no way
to learn why inside Lynomia. The change is: read `rejected_reason` off the template object in `TemplatePreviewDrawer.vue`
(which currently shows only Status, Content type, Category, Language, Inboxes — `whatsappTemplateMgmt.json` PREVIEW block)
and add the six enum values to `en.json`. **No API call, no migration, no backend change.** Classification: **PATCH**.

Caveat worth stating to the product owner: because nothing persists the reason independently, it is only visible while
Meta still returns it on the list edge.

### 4.3 Why generic template authoring is DO NOT CREATE

Meta permits create, edit and delete. The recommendation is still not to build them, for reasons that are all repo- or
Meta-evidenced rather than preference:

- **Examples are effectively mandatory and the repo cannot produce them.** Meta requires `example` values wherever a
  component's text or URL carries a parameter — `header_text` / `header_text_named_params`, `body_text` /
  `body_text_named_params`, button `example`, and `header_handle` (always, for media headers). The repo's only authoring
  code emits exactly one hardcoded `example: ['12345']` (`csat_template_service.rb:92`), and it has never uploaded a media
  handle — `Whatsapp::MediaUploadService` is wired only into `send_attachment_message`
  (`whatsapp_cloud_service.rb:188-195`), and template media is always sent as a `link`
  (`populate_template_parameters_service.rb:33-40`). Authoring means building the resumable-upload handle flow first.
- **Editing is destructive and rate-limited.** Components replace wholesale; approved templates allow 1 edit/24 h and
  10/30 days **(V)**. An edit UI must therefore own an optimistic-concurrency story against a column that has no version
  (§2.2) and no push notification of Meta-side edits (§4.1).
- **The 30-day name block makes a naive "save" unrecoverable.** See §5.2.
- **Appeals cannot be done from here.** Category review is WhatsApp Manager only **(V)**, so a rejected template always
  sends the admin to Meta anyway. The existing deep link (`TemplatePreviewDrawer.vue:28-29`) already does the right thing.
- **The product has already said so, in shipped copy.** `whatsappTemplateMgmt.json:4`.

If authoring is ever revisited, the correct sequencing is: real-time status (§4.1) → a per-template local record
(migration, for approval) → media handle upload → create → edit. Not the reverse.

---

## 5. Live defects

### 5.1 Graph API **v14.0** hardcoded for template sync — expired

```
app/services/whatsapp/providers/whatsapp_cloud_service.rb:124-126
  def business_account_path
    "#{api_base_path}/v14.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

app/services/whatsapp/csat_template_service.rb:4
  WHATSAPP_API_VERSION = 'v14.0'.freeze
```

Meta's version table lists **v14.0 as expired 2024-09-17** and v13.0 as expired 2024-05-28; current versions are v20.0 –
v26.0 **(V)**. This single constant is on the path of **every** template operation the repo performs: the 3-hourly sync
(`:50`), `validate_provider_config?` (`:66`), and all three CSAT calls (`csat_template_service.rb:23,31,99` via
`business_account_path` at `:125-127`). The repo *already has* a configurable version —
`GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')` (`facebook_api_client.rb:8`), surfaced in Super Admin
(`config/installation_config.yml:167-171`) — and `csat_template_service.rb:4` deliberately ignores it.

**Impact**: when Meta enforces the sunset, template sync and CSAT template creation stop for every inbox simultaneously,
and the failure is a logged warning that returns `[]` (`whatsapp_cloud_service.rb:51-55`) — i.e. templates silently
disappear from the dashboard rather than erroring. It is also the one defect here whose timer is controlled by a third
party.

Aggravating context: **five** Graph versions coexist — v13.0 for `/messages` (`:120`), v24.0 for attachments (`:150`),
v14.0 for business-account/template paths (`:124-126` and `csat_template_service.rb:4`), GlobalConfig v22.0 in
`facebook_api_client.rb:8` / `media_upload_service.rb:63` / `business_management_token_validation_service.rb:24,30` /
`enterprise/.../whatsapp_cloud_service.rb:63`, and `max(configured, v24.0)` in `health_service.rb:18,46-47`. The TODO at
`whatsapp_cloud_service.rb:119` acknowledges it. Classification: **PATCH**; the v14.0 pins are the urgent subset.

### 5.2 The CSAT delete-then-recreate path versus Meta's 30-day name block

Meta: **"If you delete an approved template, you cannot create a new template with the same name for 30 days." (V — this
constraint was missed by the inventory and is the one that matters most here.)**

The repo's "edit a CSAT template" is implemented as delete-then-create, in that order, non-transactionally:

```ruby
# app/services/csat_template_management_service.rb:23-35
def create_template(template_params)
  validate_template_params!(template_params)
  delete_existing_template_if_needed            # :25  → delete_existing_whatsapp_template :181-197
  result = create_template_via_provider(template_params)   # :27
  update_inbox_csat_config(result) if result[:success]     # :28  ← only on success
  result
end
```

The design is **better-founded than it looks**, and this should be said plainly: `CsatTemplateNameService.generate_next_
template_name` (`app/services/csat_template_name_service.rb:19-25`) mints
`customer_satisfaction_survey_<inbox>_<n+1>` rather than reusing the name (`csat_template_service.rb:52-55`), which is
precisely how the 30-day block is normally avoided **(V)**. Do not "simplify" that code by reusing the name.

**The defect is the ordering combined with the irreversibility.** The delete fires first and unconditionally; the previous
template was `APPROVED`; and `update_inbox_csat_config` only runs on success (`:28`). So:

- If the create fails — Meta's **100 creates/WABA/hour** cap, a malformed body, a transport error — the approved template
  is already gone, `csat_config['template']` still names it, and **the original name cannot be recreated for 30 days.**
- Even on success, CSAT is offline until Meta approves the new template, because `csat_survey_available?` requires a live
  `status == 'APPROVED'` (`app/services/csat_survey_service.rb:83-85`, reading
  `provider_service.get_template_status`). There is no rollback: the approved version was deleted, not superseded.
- The post-create status is **hardcoded** `'PENDING'` (`csat_template_service.rb:6,:113`) rather than read from Meta's
  response, which does return `status` — so the persisted record cannot even distinguish "submitted" from "not
  submitted".

Meta supports an edit (`POST /{TEMPLATE_ID}`) that would avoid all of this, within the editable set `category`,
`components`, `message_send_ttl_seconds` **(V)** — a CSAT body/button change is exactly a `components` edit. Using it
costs 1 of 10 edits per 30 days and 1 per 24 h, and re-approval is automatic unless review fails. Classification:
**EXTEND** — the narrowest justified use of the edit endpoint in the product, scoped to the CSAT template only, with
delete-then-create retained as the fallback when status is not APPROVED/REJECTED/PAUSED.

### 5.3 `TemplateNormalizer` reads body example fields for TEXT headers — **both** branches

```js
// app/javascript/dashboard/services/TemplateNormalizer.js:67-85
components.forEach(component => {
  if (component.text) {                       // :68 — true for a TEXT **header** too
    ...
    if (template.parameter_format === WA_PARAM_FORMATS.NAMED) {
      component.example?.body_text_named_params?.find(...)   // :75
    } else {
      component.example?.body_text?.[0]?.[position]          // :81
    }
```

The body-example lookup is applied to **every** component carrying `.text`, including a `HEADER` with `format: TEXT`. Meta's
shapes are different for a TEXT header: `example.header_text_named_params` (named) and the **flat**
`example.header_text: ["<VALUE>"]` (positional) **(V)**. So a TEXT-header variable's documented example is never found and
the preview variable is prefilled as `''` under **either** `parameter_format` — the named branch reads the wrong key, and
the positional branch reads both the wrong key and one nesting level too deep.

Broader than first reported **(V)**: the inventory confined this to the positional case.

The companion doubt is **closed in the code's favour**: Meta's positional BODY example genuinely is nested,
`"body_text": [["<VALUE>"]]`, so `example?.body_text?.[0]?.[position]` at `:81` is **correct for BODY** and there is no
defect there **(V)**.

Second-order observation from the same lines, which I verified directly rather than inheriting: `variables` is a single
flat map keyed by the raw variable token (`:64,:78,:83`), built across all components. For a POSITIONAL template with both
a header `{{1}}` and a body `{{1}}` — a legal and common Meta shape, since positions are numbered per component — the two
collapse into one entry. Classification: **PATCH**; scoping the example lookup by component type fixes both the key
mismatch and the collision.

---

## 6. Stale docs touching this area

| Doc | Status |
|---|---|
| `docs/whatsapp-business/META-VERIFICATION.md` | Substantive claims still hold; **anchors have drifted** — it cites `authorizations_controller.rb:76-83` (now `:94-102`) and `embedded_signup_service.rb:92-99` (now `:88-96`). It makes **no claim at all** about template operations. Two environmental premises are stale: both `developers.facebook.com` and `graph.facebook.com` are reachable from this container. |
| `docs/whatsapp-business/README.md` | "Chatwoot 4.18 carries `is_coexistence` on the signup request but stores nothing on the channel" is true of upstream but **not of this tree** — `channel_creation_service.rb:58-60` stores it. Misleading read out of context. |
| `docs/whatsapp-qr/07-meta-coexistence-pivot.md` | Self-marked Superseded (2026-09-29); describes the pre-upgrade 4.14.1 fork. Line references do not resolve at this HEAD. Historical only — **not usable as an index.** |
| `docs/whatsapp-qr/00-discovery.md` | Describes a "WhatsApp QR" / Evolution channel that **does not exist** at this HEAD: no Evolution provider, no `whatsapp_qr` channel, route, migration or column. `PROVIDERS` is still exactly `['default', 'whatsapp_cloud']` (`app/models/channel/whatsapp.rb:36`). |

## 7. Permissions and tenancy, for the record

Reading templates is open to **any account user** (`InboxPolicy#message_templates?` → `true`,
`app/policies/inbox_policy.rb:37-39`). Everything that mutates is administrator-only: `sync_templates?`,
`whatsapp_business_management_token?`, `health?`, `register_webhook?`, `create?`, `update?`, `destroy?`
(`inbox_policy.rb:49-85`); the Settings → Templates route carries `meta: { permissions: ['administrator'] }`
(`templates.routes.js:16-18`). Tenancy: every WhatsApp object hangs off `account_id`, with a **global** unique index on
`channel_whatsapp.phone_number` (`db/schema.rb:807`) so one number cannot be connected twice anywhere on the installation;
`Flows::TemplateValidator` deliberately resolves templates only inside the account's own inboxes
(`custom/app/services/flows/template_validator.rb:33-35`).

Relevant flags, all default false (`config/features.yml:188-194,251-254,263-271`): `whatsapp_campaign` (gates WhatsApp
campaigns at `app/models/campaign.rb:78` and `oneoff_campaign_service.rb:31-33`),
`whatsapp_embedded_signup_inbox_creation`, `whatsapp_manual_transfer`, plus deprecated `whatsapp_embedded_signup` and
`whatsapp_reconfigure`. `captain_integration` gates CSAT template analysis
(`inbox_csat_templates_controller.rb:67-71`).

## 8. What is UNVERIFIED

- Whether a single Meta app-default callback can be multiplexed to the correct tenant from the template webhook payload
  alone, given there is no local per-template record to resolve `message_template_id` against (§4.1).
- The exact default field projection Meta returns for `GET /{WABA}/message_templates` on **v14.0** specifically. §2.3's
  statement is derived from the shapes the code is written against (`spec/factories/channel/channel_whatsapp.rb:7-85`),
  not from a live v14.0 response.
- No test suite was run and the app was not launched for this document; every repo claim is a static read of the cited
  path:line at HEAD `6c381e96`.
