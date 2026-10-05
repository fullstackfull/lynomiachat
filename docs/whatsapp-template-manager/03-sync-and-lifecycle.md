# 03 — Sync and lifecycle

How a template moves between Lynomia Chat and Meta, which side owns which fact, and what must never happen.
Read with `00-current-system.md` (what exists) and `02-local-record-design.md` (the record).

---

## 1. Who owns what

| Fact | Owner | Lynomia's role |
|---|---|---|
| A template's content before it is submitted | **Lynomia** | the only place it exists; Meta has never seen it |
| Approval status, rejection reason, quality score, category corrections, pausing | **Meta** | mirror it verbatim, never infer it, never write it |
| Whether a template still exists at Meta | **Meta** | observe its absence; never assume |
| When a draft was created, submitted, last edited, and why a submit failed | **Lynomia** | the local record |
| Which templates can be sent | **derived** from Meta's status + the existing sendability rule | one shared authority |

**Meta remains authoritative for remote approval and status. Lynomia becomes the management experience.** Nothing in
this phase lets a user, an API caller or a UI state set an approval.

---

## 2. The three paths that move remote truth into Lynomia

All three write through **one** service, so there is one writer and no split-brain
(`02-local-record-design.md §5`).

### 2.1 The existing sync — extended, not replaced

`Whatsapp::Providers::WhatsappCloudService#sync_templates`
(`app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45`) keeps doing exactly what it does today:
it marks the timestamp first, fetches with cursor paging, bumps the inbox cache key when the list changed, and
writes the whole jsonb with `update_columns`. **Not one of those lines changes.** One call is appended: mirror the
snapshot it just wrote into rows.

Consequences of keeping it intact, all verified in `00-current-system.md §2`:

- the jsonb stays byte-for-byte what every existing consumer reads, so nothing regresses;
- `update_columns` still skips callbacks, so no `Enterprise::AuditLog` row is written per sync — the suppression at
  `enterprise/app/models/enterprise/channelable.rb:37-43` is keyed on the exact column name and would start firing if
  the sync were switched to a validated `save` or touched a second column. It is not;
- the 360dialog branch (`whatsapp_360_dialog_service.rb:27-32`) is untouched and keeps working; mirroring is driven
  from the stored snapshot, so 360dialog channels get rows without a second provider change.

The scheduler and the job are the same two: `Channels::Whatsapp::TemplatesSyncSchedulerJob` (≤ 25 channels per
5-minute tick, per-channel staleness 3 hours) and `Channels::Whatsapp::TemplatesSyncJob` (`queue_as :low`).
**No new polling framework, no new schedule entry, no new queue** (PART 3, PART 20).

### 2.2 Mirroring, with no network at all

The mirror reads the channel's **already-stored** `message_templates` snapshot and upserts rows. It never calls Meta.
That is what makes it safe to run from a migration-free deploy, from a read, and from the sync.

```
for each template in channel.message_templates (Array; a never-synced channel holds the Hash default {} → treated as empty)
  key = (account_id, channel.provider_config['business_account_id'], template['name'], lower(template['language']))
  row = find by Meta id within the account, else by key
  write: category, parameter_format, components, meta_template_id, meta_status, meta_payload, meta_synced_at = now
  never write: submitted_at, submission_error
```

- **A draft is structurally outside the write set.** The mirror only ever writes a row it matched against a template
  *present in the snapshot*. A draft Meta has never seen matches nothing, so it is never updated and never deleted.
  This is PART 3's "a sync must never delete a local draft", enforced by the shape of the loop rather than by a
  conditional someone can delete.
- **A draft that Meta now knows about stops being a draft.** When a submitted draft appears in the snapshot, the match
  on `(waba, name, lower(language))` finds the existing row and fills in `meta_template_id` and `meta_status`. The
  draft becomes the mirror of the real template — the same row, no duplicate, and the history stays on it.
- **Lookup order is id first, key second.** Within an account, a row already carrying `meta_template_id` is matched by
  it, so a rename at Meta updates that row instead of creating a second one. Only a row with no id falls back to the
  key.
- **Identity is per WABA.** Two WABAs with a same-named template produce two rows (unique index includes
  `business_account_id`), so one WABA can never overwrite another's template (PART 1.3, PART 16).
- **Two inboxes on one WABA produce one row.** They share the WABA, so they share the template — which is how
  `templateUtils.js:38-47` already groups them in the current UI.
- **Idempotent.** Running it twice changes nothing but `meta_synced_at`.

**When it runs:** (a) at the end of `sync_templates`, for the channel just synced; (b) lazily, when the query service
is asked for an account's templates and a channel's `message_templates_last_updated` is newer than the newest
`meta_synced_at` among that WABA's rows. (b) is what populates the table after deploy without a backfill migration
and without a network call (PART 1.4), and what covers the 360dialog provider.

### 2.3 Manual sync — the button that already exists

`POST /api/v1/accounts/:id/inboxes/:id/sync_templates` (`config/routes.rb:303` →
`inbox_health_management.rb:10-17`, admin-only via `InboxPolicy#sync_templates?`) keeps its contract and keeps
enqueuing the same job. The manager's "Sync from WhatsApp" control calls it — the same endpoint the settings page
calls today (`app/javascript/dashboard/store/modules/inboxes.js:313-319`,
`routes/dashboard/settings/templates/Index.vue:302-325`). **No new sync endpoint.**

The response already carries `meta.last_sync_attempt_at`, which is what the UI shows as "last checked".

---

## 3. Remote deletion, modelled truthfully

A template can disappear from Meta while Lynomia is not looking — someone deletes it in Business Manager, or Meta
deletes it. PART 3 forbids both wrong answers: silently deleting the local row, and going on claiming it is approved.

**The observation is derived, not stored as a status we invented** (`02-local-record-design.md §6`):

```
missing_at_meta? = meta_template_id.present?
                && meta_synced_at < the channel's message_templates_last_updated
```

A row the last sync did not touch was not in the snapshot. The UI then says **"No longer at WhatsApp — last seen on
<date>"**, the template is not sendable, and the row stays, with its content, so the user can duplicate it into a new
draft and resubmit. Nothing is destroyed on the strength of one sync, and a failed or empty fetch cannot cause it:
`sync_templates:38` returns before writing when the fetch is blank, so `message_templates_last_updated` moves only on
a fetch that actually produced templates.

A template Meta reports as `PENDING_DELETION` or `DELETED` is simply mirrored with that status — Meta said it, so
Lynomia repeats it.

---

## 4. The status webhook

### 4.1 What Meta actually does — verified at the source, 2026-10

Meta's current webhooks-override documentation
(<https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/>) states, verbatim:

> "Template webhooks (message_template_status_update, message_template_quality_update,
> message_template_components_update, template_category_update) and account-level webhooks (account_update,
> account_review_update, account_alerts) do not support callback overrides."

and

> "Meta always delivers these webhooks to your app's default callback URL."

The fields that *do* support an override are listed as
`messages, message_echoes, calls, consumer_profile, messaging_handovers, group_lifecycle_update,
group_participants_update, group_settings_update, group_status_update, smb_message_echoes, smb_app_state_sync,
history, account_settings_update`. Delivery priority for those is phone-number override → WABA override → the app's
default callback URL.

**So the callback-override claim from the earlier discovery notes is correct, and it is Meta's own current rule.**

### 4.2 Why nothing arrives today — both halves, verified at this HEAD

1. **The field is not subscribed.** `Whatsapp::WebhookSetupService#subscribed_fields` returns
   `%w[messages smb_message_echoes]` plus `calls` when voice is on (`webhook_setup_service.rb:84-89`), and
   `FacebookApiClient::WEBHOOK_DEFAULT_FIELDS` is the same pair (`facebook_api_client.rb:9`). A sweep of `app/`,
   `enterprise/` and `custom/` finds **zero** occurrences of `message_template_status_update`,
   `message_template_quality_update`, `message_template_components_update` or `template_category_update`.
2. **Lynomia has no URL that can receive it.** Every WhatsApp webhook route carries a phone number —
   `post 'webhooks/whatsapp/:phone_number'` (`config/routes.rb:679`) — and the only callback Lynomia registers with
   Meta is the **phone-level** override `"#{FRONTEND_URL}/webhooks/whatsapp/#{phone_number}"`
   (`webhook_setup_service.rb:105-110`, set through
   `FacebookApiClient#override_phone_number_callback:168-181`). A template event is never delivered to a phone-level
   override, and a WABA-scoped event has no phone number to put in the path anyway.
3. **And if one did arrive, it would be dropped.** `Webhooks::WhatsappEventsJob#perform:9` resolves the channel with
   `find_channel_from_whatsapp_business_payload`, which for `object == 'whatsapp_business_account'` reads only
   `entry[0].changes[0].value.metadata` (`:167-182`) — a template-status `value` carries `event`,
   `message_template_id`, `message_template_name`, `message_template_language` and `reason`, and **no `metadata`**.
   `Whatsapp::WebhookChannelFinderService#perform` returns nil the moment the display number's digits are blank
   (`webhook_channel_finder_service.rb:13`), so `channel_is_inactive?` is true (`whatsapp_events_job.rb:149`) and the
   payload is logged as an inactive channel and discarded.

### 4.3 The design — one receiver, one more route, no parallel pipeline

PART 4 forbids a parallel webhook receiver, and Meta's delivery rule forbids reusing the phone-scoped URL. Both are
satisfied by adding a **second route into the same controller action**, with the same signature verification and the
same job:

```ruby
# config/routes.rb, beside the existing pair
post 'webhooks/whatsapp', to: 'webhooks/whatsapp#process_payload'   # the Meta app's default callback URL
get  'webhooks/whatsapp', to: 'webhooks/whatsapp#verify'           # Meta's subscription handshake
```

- **Same controller, same `before_action :verify_meta_signature!`.** With no `:phone_number` segment,
  `whatsapp_channel` is blank, so `meta_signature_verification_required?` returns true
  (`whatsapp_controller.rb:48-50`) and the HMAC is checked against `GlobalConfigService.load('WHATSAPP_APP_SECRET')`
  (`:34-39`) — which is precisely the right secret for an app-level callback, because the app that owns the
  subscription is what signs it. This path is **more** strictly verified than the per-phone one, which can fall back
  to a channel-level secret.
- **Same job.** `Webhooks::WhatsappEventsJob` gains one branch, taken **before** `channel_is_inactive?`, because that
  guard treats "no channel" as "inactive" and returns (`whatsapp_events_job.rb:11-14`).
- **Tenant resolution is by WABA, not by phone number.** For `object == 'whatsapp_business_account'`, `entry[].id` is
  the WABA id. Channels are found with the pattern already in this repo:
  `Channel::Whatsapp.where("provider_config->>'business_account_id' = ?", waba_id)`
  (`app/services/whatsapp/webhook_setup_service.rb:100`). That is exactly the scope the local record uses
  (`02-local-record-design.md §3`), so the event lands on the right rows for every account connected to that WABA —
  and on no others.
- **Every change in the batch is processed.** `entry[].changes[]` is iterated. Today's handlers read `changes[0]`
  only (`whatsapp_events_job.rb:81`, EE `:19`), and Meta can batch several template status updates in one delivery,
  so a template branch that copied that shape would silently drop all but the first.
- **Matching a row, with Meta's own inconsistencies handled.** `message_template_id` is an **Integer** in the webhook
  and a numeric **String** in API reads, so it is compared as a string. `message_template_language` is `en-US`
  (hyphen) in this webhook and `en_US` (underscore) in the API, so `-` is normalised to `_` before any name+language
  fallback. Both are verified in `01-meta-api-contract.md §8`.
- **`event` is not `status`.** Meta's webhook `event` enum is a superset of the status enum: `FLAGGED`, `LOCKED`,
  `REINSTATED` and `UNARCHIVED` are events about a template whose status may not have changed. So the handler writes
  `meta_status` **only** when the event is a member of the status enum, and otherwise records the event in
  `meta_payload` and leaves the status for the next sync to settle. Writing an event straight into the status would
  store values the API never returns — which is exactly the kind of invented remote fact this phase forbids.
  `rejection_info.reason` / `.recommendation` are kept in `meta_payload`: they are the only place Meta explains a
  rejection in words.
- **Idempotency.** The update is an upsert keyed on `(account, meta_template_id)`, so a redelivered or out-of-order
  event converges. A stale event cannot resurrect an old status: the write is ignored when the payload's event is
  already the row's `meta_status` and `meta_synced_at` is newer. No new Redis lock, no reuse of
  `Whatsapp::MessageDedupLock` — its key prefix is hardcoded to `MESSAGE_SOURCE_KEY`
  (`app/services/whatsapp/message_dedup_lock.rb:6`) and template ids must not share a namespace with message ids.
- **`contact_sender_id` stays nil for these payloads**, so the per-(inbox, contact) mutex is bypassed, as it already
  is for status payloads (`whatsapp_events_job.rb:102`).
- **Subscription.** `message_template_status_update` is added to `subscribed_fields` /
  `WEBHOOK_DEFAULT_FIELDS`. The three sibling fields are not subscribed in P3: `message_template_quality_update` and
  `message_template_components_update` are covered by the sync, and `template_category_update` (note the missing
  `message_` prefix) carries two different payload shapes on one field — neither is needed for the lifecycle this
  phase manages. That list is WABA-wide and resent in full on every re-subscribe
  (`facebook_api_client.rb:152, 158-166`), so the addition propagates on the next channel save, voice toggle or
  reauthorization; no migration and no backfill.

### 4.4 The webhook is an accelerator, never the source of truth

The Meta App Dashboard's default callback URL is **Meta-side configuration outside this repository.** If it is not
pointed at `{FRONTEND_URL}/webhooks/whatsapp`, no template event arrives and nothing breaks: status still moves on the
existing 3-hourly sync and on the manual sync button, exactly as today. The webhook turns "within three hours" into
"within seconds"; it is never the only way a status changes, and no code path waits for it.

This also answers PART 20: there is **no new polling job and no status-watching loop.** A submitted template's status
arrives by webhook if the app callback is configured, and otherwise on the sync that already runs. Nothing retries in
a loop, and nothing polls per template.

---

## 5. Submitting, editing, deleting: the local half of the lifecycle

Only the local-record mechanics are specified here. The Meta contract for each call — what is allowed, what is not,
and what Meta no longer supports — is in `01-meta-api-contract.md`.

### 5.1 Submit

```
with_lock on the row:
  refuse if meta_template_id.present?     → it is already at Meta; nothing to submit
  refuse if submitted_at.present?          → a submit is already in flight (this is the double-click guard)
  validate locally; set submitted_at = now, clear submission_error
commit, then POST {waba}/message_templates
  success → store meta_template_id, meta_status from the response, meta_synced_at = now
  failure → clear submitted_at, store the safe message in submission_error. THE DRAFT IS NOT TOUCHED.
```

- **A double-clicked Submit cannot create two Meta templates** (PART 7): the claim is taken inside the lock and
  committed *before* the HTTP call, so the second request sees `submitted_at` present and refuses. Without the
  pre-commit claim there is a window where both requests see a clean draft.
- **Meta refusing the call never destroys the draft** (PART 7). The content stays; the reason is shown; the user
  edits and submits again.
- **No token ever reaches the browser** (PART 7). The browser calls Lynomia; Lynomia calls Meta with
  `Channel::Whatsapp#template_access_token` — the same selector the sync uses, not the raw `api_key` the CSAT service
  uses (`00-current-system.md §4.3`).

### 5.2 Edit

Allowed actions are derived from Meta's current rules, per template, server-side — never from a hidden button
(PART 8). The record supplies `meta_status` and `meta_template_id`; `01-meta-api-contract.md §6` supplies the rule.
Three consequences shape the implementation:

- **Editable only in `APPROVED`, `REJECTED` or `PAUSED`**, and the category only while `REJECTED` or `PAUSED`. The
  server computes the allowed action set; the UI renders it.
- **Meta replaces every component.** There are no partial component edits, so an edit always submits the complete
  component set from the row — header, footer, buttons and every `example` value — not a diff. This is why the row
  stores the whole `components` payload rather than fragments.
- **The response is only `{"success": true}`.** Nothing is marked approved optimistically: `meta_status` is left to
  the webhook or the next sync, which is the same rule as everywhere else in this phase.

An edit of an approved template re-enters review at Meta and is limited to one edit per 24 hours and ten per 30 days,
with no API field reporting the remaining count. The UI states both facts before the confirmation, because they are
real consequences for a template a campaign may be using, and Meta's refusal is mapped to a clear message if the
quota is already spent. No private edit counter is kept (`01-meta-api-contract.md §6`).

### 5.3 Delete

- **By id, never by name alone.** `DELETE {waba}/message_templates?name=` removes the template in **every
  language**, which is why the CSAT service's name-scoped delete is correct for CSAT and wrong as a manager default.
  The documented single-template shape is `?hsm_id=<id>&name=<name>` — the id **with** the name
  (`01-meta-api-contract.md §7`). `hsm_ids` bulk delete is not used: if any id is invalid the whole request fails and
  nothing is deleted, which makes partial failure invisible.
- **The 30-day name lockout is stated before the confirmation.** After an approved template is deleted its name
  cannot be reused for 30 days — the same rule `CsatTemplateNameService`'s versioning exists to dodge.
- **A `DISABLED` template cannot be deleted at all**, so the action is not offered for one.
- A local draft is deleted locally, with no Meta call at all — Meta has nothing to delete.
- Deleting a remote template is confirmed with its consequences stated, and the local row is kept with Meta's
  resulting status rather than vanishing, so a production template does not disappear unexpectedly (PART 8).

### 5.4 Duplicate

Copies `name` (suffixed), `language`, `category`, `parameter_format` and `components` into a **new local draft**, and
copies **no** `meta_template_id`, `meta_status`, `meta_payload`, `submitted_at`, `submission_error` or
`meta_synced_at`. Meta ids are never cloned (PART 10) — the unique partial index on
`(account_id, meta_template_id)` makes a clone impossible to persist even if the code tried.

### 5.5 CSAT keeps its own lifecycle

The CSAT template lifecycle is not merged into this one (PART 9). It keeps `CsatTemplateNameService`'s versioned
names, keeps `CsatTemplateManagementService`'s create-without-delete safeguard, and keeps
`CsatSurveyService`'s live status check (`00-current-system.md §9`). The manager does not offer Delete or Edit for a
template whose name starts with `CsatTemplateNameService::CSAT_BASE_NAME`; CSAT is managed from its own settings
screen, and the manager says so.

Note the nuance that must not be flattened: `Flows::Template.sendable?` excludes CSAT-named templates because a
**flow** must not send one. That is a flow-level rule, not a global send rule — CSAT itself sends those templates
through `CsatSurveyService`, bypassing `SendOnWhatsappService` entirely (`csat_survey_service.rb:107-135`). A shared
sendability authority must keep the two scopes apart or CSAT stops working.

---

## 6. The state machine, end to end

```
                    ┌──────── user edits ────────┐
                    ▼                            │
  (new)  ──▶  DRAFT ──submit──▶ SUBMITTING ──Meta accepted──▶ IN REVIEW (meta_status=PENDING)
                 ▲                   │                                 │
                 │           Meta refused the call                      │  Meta decides
                 └── submission_error, draft intact                     ▼
                                                        APPROVED / REJECTED / PAUSED / DISABLED / …
                                                                        │
                                                   edit ──▶ back to IN REVIEW (Meta re-reviews)
                                                   delete ──▶ PENDING_DELETION / DELETED (Meta's word)
                                                   absent from a sync ──▶ "No longer at WhatsApp"
```

Every box left of "Meta accepted" is a Lynomia fact; every box right of it is Meta's, mirrored verbatim. There is no
transition that invents an approval, and `sendable?` is true in exactly one box: `meta_status == APPROVED`.

---

## 7. What this phase does not add

- No second sync, scheduler, queue or job for templates.
- No per-template polling, no status-watching loop, no retry loop (PART 20). Transport retries stay with the
  existing `ApplicationJob` / Sidekiq behaviour.
- No parallel webhook receiver: one more route into the existing controller and one branch in the existing job.
- No change to the jsonb snapshot's write, so no change to any existing consumer, and no new audit-log traffic.
- No backfill, in a migration or out of one. Rows appear from snapshots already on disk.
