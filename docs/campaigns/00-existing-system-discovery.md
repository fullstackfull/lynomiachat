# Lynomia Campaigns: the existing system

What Chatwoot's campaign system is in this tree, before any change, and the Lynomia audience pieces it can reuse. Every
statement points at the code it was read from.

## 1. Model and storage

`Campaign` (`app/models/campaign.rb`), table `campaigns`, one row per campaign:

| Column | Meaning |
|---|---|
| `account_id`, `inbox_id`, `sender_id` | the account; the inbox the campaign is sent from (validated: same account, type Website / Twilio SMS / Sms / Whatsapp); the optional sender agent |
| `title`, `description`, `message` | `message` is the text (SMS) or the rendered template body (WhatsApp) |
| `campaign_type` | `ongoing` (Website: live chat triggers) or `one_off` (SMS, Twilio, WhatsApp), forced by inbox type in `ensure_correct_campaign_attributes` |
| `campaign_status` | `active`, `processing`, `completed`; no draft, cancelled or failed status |
| `enabled` | used by Website campaigns only; nothing in the one-off path reads it |
| `audience` | jsonb, default `[]`: `[{ "type": "Label", "id": <label id> }]` |
| `scheduled_at`, `started_at`, `completed_at` | one-off schedule and run timestamps |
| `template_params` | WhatsApp: `{ name, namespace, category, language, processed_params }` |
| `trigger_rules`, `trigger_only_during_business_hours` | Website campaigns |

Enterprise adds `campaign_recipients` (`enterprise/app/models/campaign_recipient.rb`): one row per contact per WhatsApp
campaign (unique `campaign_id, contact_id`), with `status` (`queued`, `skipped`, `sent`, `delivered`, `read`, `failed`),
the provider `source_id` (WhatsApp message id), the rendered content and error fields. It is created while the campaign is
sent and updated from WhatsApp status webhooks (`Campaigns::UpdateRecipientStatusJob`).

There is no campaign contact list, no audience member table and no copy of a segment's conditions anywhere.

## 2. API and permissions

- `Api::V1::Accounts::CampaignsController`: `index`, `show`, `create`, `update`, `destroy`, by `display_id`.
  Strong params: `audience: [:type, :id]`. No other validation of the audience entries: label ids are resolved inside
  the account at send time (`account.labels.where(id:)`), so a foreign or deleted label id matches nobody.
- `CampaignPolicy` (`app/policies/campaign_policy.rb`): administrators only, for every action. No Enterprise override.
- Enterprise `Campaigns::AnalyticsController`: `analytics/metrics` and `analytics/contacts` for one-off WhatsApp campaigns,
  from `campaign_recipients`; authorized through `CampaignPolicy#show?`.
- Features: `campaigns` (the section), `whatsapp_campaign` (WhatsApp one-off campaigns; `Campaign#trigger!` and the
  WhatsApp sender check it).
- Views: `api/v1/models/_campaign.json.jbuilder` returns `audience` as stored, for one-off campaigns.

## 3. Scheduling and dispatch

1. `TriggerScheduledItemsJob` (cron `*/5 * * * *`, `config/schedule.yml`) enqueues `Campaigns::TriggerOneoffCampaignJob`
   for every `one_off` + `active` campaign whose `scheduled_at` is within the last 3 days.
2. The job calls `Campaign#trigger!`: returns unless `one_off?` and the feature is enabled; `mark_processing!` flips the
   status to `processing` under a row lock (so two scheduler runs cannot both send); then `execute_campaign` picks the
   sender by inbox type.
3. The sender resolves the audience **at that moment**, sends, then `campaign.completed!`.

| Sender | File | Audience resolution | Per-contact eligibility |
|---|---|---|---|
| WhatsApp (OSS) | `app/services/whatsapp/oneoff_campaign_service.rb` | `extract_audience_labels` → `account.contacts.tagged_with(titles, any: true)`, then `.each` | destination = phone number, else exactly one BSUID contact inbox on this inbox; `template_params` present; Liquid params resolve; authentication-template guard; `channel.send_template` |
| WhatsApp (Enterprise, prepended) | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | the same relation, `find_each`, one `campaign_recipients` row per contact (`find_or_create_by!`) before sending | the same checks, recorded as `skipped` / `failed` / `sent` |
| SMS | `app/services/sms/oneoff_sms_campaign_service.rb` | the same label lookup (its own copy), `.each` | phone number present; Liquid content; `channel.send_text_message` |
| Twilio SMS | `app/services/twilio/oneoff_sms_campaign_service.rb` | the same label lookup (its own copy), `.each` | phone number present; Liquid content; `channel.send_message` |

The label resolution is written four times. `tagged_with(..., any: true)` is an `EXISTS` on taggings per contact, so a
contact carrying two of the campaign's labels is one row: **one contact receives the campaign once**. With no label
resolved, `tagged_with([])` is `none`.

Blocked contacts and opt-outs: **no sender excludes them.** `contacts.blocked` exists and is a contact filter key
(`lib/filters/filter_keys.yml`), but no campaign path reads it, and there is no opt-out model. Exclusions are whatever
the label (or, below, the audience) selects.

The message path: the WhatsApp senders call `channel.send_template` directly (no `Message` row, no conversation), the SMS
senders call the channel's send method directly. Template compliance comes from the template chosen in the form and
`Whatsapp::TemplateProcessorService`.

## 4. Frontend

- `components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue` and
  `SMSCampaign/SMSCampaignForm.vue`: title, inbox, (WhatsApp) template + `WhatsAppTemplateParser`, **Audience = a
  `TagMultiSelectComboBox` of the account's labels**, scheduled at. Submit sends
  `audience: selected.map(id => ({ id, type: 'Label' }))`. The audience field is required.
- One-off campaigns cannot be edited in the UI (only Website campaigns have an edit dialog); they can be deleted.
- `dashboard/api/campaigns.js`, store `campaigns`; i18n `campaign.json`.
- The WhatsApp analytics page reads `analytics/metrics` (`audience` = number of recipient rows).

## 5. Lynomia audiences (built before this phase)

- An audience is a contact `CustomFilter` (`filter_type: contact`) with `query.payload` = Chatwoot conditions.
  `shared: true` makes it the account's (`custom/app/models/custom/custom_filter.rb`): every member may open it,
  administrators manage it, it survives its creator. Personal filters keep their user.
- Evaluation: `Contacts::FilterService` (+ `Custom::Contacts::FilterService`: conversation and Commerce conditions,
  limits) returns an `ActiveRecord::Relation` of the account's contacts. `relation` builds it without counting.
  Commerce conditions are three-valued: unknown is never a member (docs/audience/03 §6).
- Account-wide evaluation: Automation evaluates a shared audience with no user
  (`Automation::LynomiaCondition#member?`: `Contacts::FilterService.new(account, nil, { payload: }).relation`), so
  conversation conditions see every conversation of the account.
- Dependency: `Audience::Usage.rules(filter)` lists the automation rules whose `contact_audience` condition references
  the audience. `Custom::Api::V1::Accounts::CustomFiltersController` refuses to delete or unshare a shared audience in use
  (`errors.custom_filters.used_by_automation`: "This audience is used by %{count} automation rules…", 422).
  `_custom_filter.json.jbuilder` exposes `automation_rules_count` and `active_automation_rules_count`; the contacts
  filter shows "used by {count} active automation rules" to administrators.
- Audit: shared and personal contact filters are audited (`Custom::Audit::CustomFilter`). Campaigns are not audited in
  Chatwoot (no `Audit::Campaign`).
- The planned contract (docs/audience/06 §5): campaigns accept `{ type: 'Audience', id }` entries for shared audiences,
  resolved at send time with the audience's relation, unioned with labels, keeping each channel's eligibility and the
  `campaign_recipients` path.

## 6. Answer

**EXISTING CAMPAIGN SYSTEM TO EXTEND:** Chatwoot's one-off `Campaign` (`campaigns.audience` jsonb), dispatched by
`TriggerScheduledItemsJob` → `Campaigns::TriggerOneoffCampaignJob` → `Campaign#trigger!` → `Whatsapp::OneoffCampaignService`
(+ Enterprise `campaign_recipients`), `Sms::OneoffSmsCampaignService`, `Twilio::OneoffSmsCampaignService`, created by
`Api::V1::Accounts::CampaignsController` under `CampaignPolicy`, built in `WhatsAppCampaignForm.vue` / `SMSCampaignForm.vue`.
Shared audiences enter as one more entry type in `campaigns.audience`.
