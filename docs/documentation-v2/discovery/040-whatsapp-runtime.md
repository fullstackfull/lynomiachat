---
agent: 040
scope: WhatsApp runtime — inbound ingest, outbound send, 24-hour window, status updates, template manager, delivery-failure classifier
confidence: high
---

## 1. What the feature is

WhatsApp runtime in this installation is five separate machines that share a channel row.

**Inbound ingest.** Meta posts to an unauthenticated public endpoint; the controller verifies the payload's
HMAC, drops operator-disabled numbers and template-only deliveries, and enqueues a job
(`app/controllers/webhooks/whatsapp_controller.rb:6-17`). The job resolves the channel from the payload's own
`phone_number_id`, serializes per (inbox, contact) on a Redis mutex, and hands the payload to a per-provider
ingest service (`app/jobs/webhooks/whatsapp_events_job.rb:8-24`). The ingest service deduplicates, resolves
contact and conversation, downloads media, and writes one `Message`
(`app/services/whatsapp/incoming_message_base_service.rb:29-60`).

**Outbound send.** `Whatsapp::SendOnWhatsappService` chooses between a template send, a contact-info request and
a free-form session message, and refuses the last one outright when the 24-hour window is closed
(`app/services/whatsapp/send_on_whatsapp_service.rb:8-20`). The Cloud provider builds the Graph request,
uploads media first so Meta never fetches from this host, and funnels every response through one
`process_response` / `handle_error` pair (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:2-33`,
`130-197`; `app/services/whatsapp/providers/base_service.rb:34-58`).

**Status propagation.** A `statuses` webhook advances the `Message` through a forward-only ladder under a row
lock (`app/services/messages/status_update_service.rb:10-18`, `36-45`), and a Lynomia overlay additionally
routes every entry of the same payload to `CampaignRecipient` for campaign sends, which have no message
(`custom/app/services/custom/whatsapp/incoming_message_base_service.rb:17-21`,
`custom/app/services/whatsapp/delivery_report.rb:35-46`).

**Template manager.** A local `whatsapp_message_templates` table mirrors Meta's snapshot and also holds local
drafts; four lifecycle operations (submit, edit, delete, duplicate) talk to Graph through one client, under one
action-permission rule and one validator (`custom/app/services/whatsapp/templates/*`,
`custom/app/models/whatsapp/message_template.rb`). A `message_template_status_update` webhook accelerates
status, and the periodic sync remains the authority
(`custom/app/jobs/custom/webhooks/whatsapp_events_job.rb:15-22`,
`custom/app/services/whatsapp/templates/status_update.rb`).

**Delivery-failure classification.** `Whatsapp::DeliveryFailure` parses the numeric code out of the stored
refusal string and classifies exactly two codes, deliberately
(`custom/app/services/whatsapp/delivery_failure.rb:9-31`).

## 2. Surfaces and routes

| Surface | Route / component | Controller or service |
|---|---|---|
| Webhook handshake (per number) | `GET webhooks/whatsapp/:phone_number` — `config/routes.rb:548` | `Webhooks::WhatsappController#verify` via `MetaTokenVerifyConcern:9-17` |
| Webhook delivery (per number) | `POST webhooks/whatsapp/:phone_number` — `config/routes.rb:549` | `whatsapp_controller.rb:6-17` |
| Webhook handshake (app-level) | `GET webhooks/whatsapp` — `config/routes.rb:554` | `whatsapp_controller.rb:28-41` (installation-wide token) |
| Webhook delivery (app-level) | `POST webhooks/whatsapp` — `config/routes.rb:555` | same controller; the only URL Meta delivers template webhooks to (`config/routes.rb:552`) |
| Template manager page | `/accounts/:accountId/settings/templates`, `settings_templates` — `app/javascript/dashboard/routes/dashboard/settings/templates/templates.routes.js:9-19`; `Index.vue`, `TemplateBuilderDialog.vue`, `TemplateCard.vue`, `TemplatePreviewDrawer.vue` | — |
| Template CRUD + lifecycle | `/api/v1/accounts/:id/whatsapp/message_templates` (+ `:id/submit`, `:id/duplicate`) — `config/routes/whatsapp_templates.rb:10-15` | `custom/app/controllers/api/v1/accounts/whatsapp/message_templates_controller.rb:29-63` |
| Template sync (per inbox) | `POST .../inboxes/:id/sync_templates` | `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:10`, `:117` → `Channels::Whatsapp::TemplatesSyncJob` |
| Failed-message block | `app/javascript/dashboard/components-next/message/MessageError.vue` | fed by `app/views/api/v1/models/_message.json.jbuilder:20-21` |
| Retry a failed message | `POST .../messages/:id/retry` — `config/routes.rb:122` | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:33-46` |
| Composer blocked outside the window | `ReplyBox.vue:517-523` (`isEditorDisabled`), banner in `MessagesView.vue:225`, `247-256` | `Conversation#can_reply?` → `Conversations::MessageWindowService:9-13` |
| Sidebar entry | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:891-896` | — |

## 3. User-visible states

**Inbound.** A message arrives, arrives without its attachment (media download failed; the message is still
saved — `incoming_message_base_service.rb:142-150` returns early on a blank download), arrives as an empty
placeholder with an "unsupported message" sentence (`:95-102`, `I18n.t('conversations.messages.whatsapp.unsupported_message')`),
or does not arrive at all. Reactions, ephemeral messages and `request_welcome` are silently discarded
(`incoming_message_service_helpers.rb:55-57`). Nothing in the product shows a user that a payload was dropped:
`unroutable_payload` and `inactive_account` go to the Rails log only
(`app/jobs/webhooks/whatsapp_events_job.rb:171-201`).

**Outbound.** `sent` → `delivered` → `read`, forward-only, or `failed`. An echo from the WhatsApp Business app
is written straight to `delivered` so `SendReplyJob` never picks it up
(`incoming_message_base_service.rb:180-183`).

**Failed message.** Three different renderings, decided by whether the server classified the code
(`MessageError.vue:31-48`, `99-111`): (a) classified — a plain-language title and body, the label "WhatsApp
said:", the verbatim refusal, and a "What to do about this" link; (b) classified and recipient-scoped — the same,
with Retry replaced by "Sending this again would be refused the same way." (`:56-58`, `:137-139`); (c)
unclassified — "Failed to send", the verbatim refusal, a Retry button, **and no link at all**, because
`learnMoreUrl` returns `''` when `deliveryFailure` is absent (`:70-77`).

**Template manager.** Fourteen states, nine of Meta's and five derived locally
(`app/javascript/dashboard/routes/dashboard/settings/templates/templateUtils.js:161-187`): `UNSUBMITTED`,
`SUBMITTING`, `SUBMISSION_FAILED`, `MISSING` (Lynomia's own observation —
`Whatsapp::MessageTemplate#missing_at_meta?`, `custom/app/models/whatsapp/message_template.rb:90-92`), plus
`APPROVED PENDING REJECTED PAUSED DISABLED IN_APPEAL PENDING_DELETION DELETED ARCHIVED LIMIT_EXCEEDED`. An
unknown status from Meta renders its own formatted name rather than a missing key (`:190-196`). Also: empty, no
WhatsApp inbox, loading, partial fetch failure, partial sync failure, and a "last sync attempt" timestamp
(i18n keys `WHATSAPP_TEMPLATE_MGMT.EMPTY`, `EMPTY_NO_INBOX`, `PARTIAL_FETCH_ERROR`, `PARTIAL_SYNC_ERROR`,
`LAST_SYNC_ATTEMPT` in `app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json`).

## 4. Errors and validation messages

### 4.1 Server-side send refusals (`config/locales/en.yml`)

| Key | String | Raised at |
|---|---|---|
| `errors.whatsapp.message_outside_messaging_window` (`en.yml:185`) | "Message not sent because the WhatsApp 24-hour customer service window is closed and no template parameters were provided. Send an approved template message instead." | `send_on_whatsapp_service.rb:17` |
| `errors.whatsapp.recipient_delivery_restricted` (`en.yml:186`) | "WhatsApp refused this message for this recipient (%{reason}). Retrying would repeat the same refusal, so it is not offered. The restriction is Meta's and lifts on its own." | `messages_controller.rb:38-40` |
| `errors.whatsapp.authentication_template_requires_phone` (`en.yml:187`) | "Authentication templates require a WhatsApp phone number and cannot be sent to a BSUID-only contact." | `app/services/whatsapp/authentication_template_guard.rb:7` |
| `errors.whatsapp.template_category_required_for_bsuid` (`en.yml:188`) | "Template category could not be verified for this BSUID-only contact." | `authentication_template_guard.rb:6` |
| `errors.whatsapp.contact_info_request.outside_messaging_window` (`en.yml:193`) | "Contact information can only be requested within the WhatsApp 24-hour customer service window." | `Whatsapp::ContactInfoRequestEligibilityService` |
| (hard-coded, no i18n key) | `'Template not found or invalid template name'` | `send_on_whatsapp_service.rb:40` |

The last one is a bare string in Ruby, not an i18n key, and it is the message the troubleshooting article
documents (`custom/db/documentation/en/whatsapp/whatsapp-troubleshooting.md:44`).

### 4.2 Template-manager error codes (14, none numeric)

`Whatsapp::Templates::Error::CODES` (`custom/app/services/whatsapp/templates/error.rb:6-10`) with copy at
`whatsappTemplateMgmt.json` → `WHATSAPP_TEMPLATE_MGMT.ERRORS.*`:
`ALREADY_AT_META`, `SUBMIT_IN_FLIGHT`, `NOT_SUBMITTABLE`, `NOT_EDITABLE`, `CATEGORY_NOT_EDITABLE`,
`NOT_DELETABLE`, `CSAT_MANAGED_ELSEWHERE`, `NO_WHATSAPP_INBOX`, `INVALID_TEMPLATE`, `NAME_TAKEN`,
`AUTH_INVALID`, `RATE_LIMITED`, `META_UNAVAILABLE`, `META_REJECTED_REQUEST`. All fifteen strings (plus
`GENERIC`) are present in EN. `META_REJECTED_REQUEST` carries Meta's own `error_user_msg`/`error_user_title`
as `reason` and nothing else (`custom/app/services/whatsapp/templates/meta_client.rb:21`,
`operation.rb:48-58`).

### 4.3 Template validation codes (33)

`Whatsapp::Templates::Validator` returns `{field:, code:, limit:}`; every code has a sentence under
`WHATSAPP_TEMPLATE_MGMT.PROBLEM.*`. The full set, with `custom/app/services/whatsapp/templates/validator.rb`
lines: `name_format` (:66), `language_blank` (:67), `category_unsupported` (:68), `parameter_format_unsupported`
(:71), `component_unsupported` / `component_duplicated` (:84-85), `body_missing` / `body_blank` /
`body_too_long` (:90-95), `header_format_unsupported` / `header_too_long` / `header_too_many_variables` /
`header_example_missing` (:105-119), `footer_too_long` / `footer_has_variables` (:127-129), `buttons_too_many`
(:136), `button_type_unsupported` / `button_type_too_many` (:144-147), `buttons_quick_reply_not_grouped` (:157),
`button_text_too_long` (:163), `button_phone_too_long` (:167), `button_url_blank` / `button_url_too_long`
(:174-175), `button_url_too_many_variables` / `button_url_variable_not_at_end` / `button_example_missing`
(:184-186), `button_copy_code_too_long` (:193), `variable_at_edge` / `variables_adjacent` (:208-209),
`variable_name_invalid` / `variable_duplicated` (:214-215), `variables_not_sequential` (:221),
`variable_example_missing` (:230).

Numeric limits enforced server-side (`validator.rb:10-21`): header text 60, body 1024, footer 60, button text
25, button URL 2000, button phone 20, copy code 15, buttons 10, and per type `QUICK_REPLY` 10, `URL` 2,
`PHONE_NUMBER` 1, `COPY_CODE` 1. Name 512 (`message_template.rb:39`). The client mirrors the same numbers for
input maxlengths (`templateUtils.js:146-156`) and names the server as the authority (`:142-145`).

The copy-code limit is a deliberate divergence from Meta: the comment at `validator.rb:16-19` records that Meta
raised it to 20 on 2025-12-03 but `Whatsapp::PopulateTemplateParametersService:20` still refuses over 15 at send
time, so the manager holds 15. `Flows::Template::COPY_CODE_MAX` repeats 15
(`custom/app/services/flows/template.rb:14`).

### 4.4 Meta error codes this installation classifies or names — complete enumeration

| Code | Where, `file:line` | What the code does here | Article? |
|---|---|---|---|
| **131049** | `custom/app/services/whatsapp/delivery_failure.rb:13`, `:29`; `custom/app/models/custom/message.rb:6`; `custom/app/services/lynomia/operator_log.rb:31`; `MessageError.vue:28`, `:69`; `documentationLinks.js:44` | **Classified** `META_RECIPIENT_DELIVERY_RESTRICTION`, scope `:recipient`; `DO_NOT_AUTO_RETRY`; Retry withdrawn in UI and refused by the API | **Yes** — `whatsapp-error-131049` (EN + AR) |
| **131042** | `delivery_failure.rb:16`, `:30`, `:59`; `MessageError.vue:54`; `documentationLinks.js:45` | **Classified** `META_BILLING_ELIGIBILITY`, scope `:account`; `DO_NOT_AUTO_RETRY` but Retry deliberately kept | **Yes** — `whatsapp-error-131042` (EN + AR) |
| **131053** | `app/services/whatsapp/media_upload_service.rb:5`; `app/services/whatsapp/providers/whatsapp_cloud_service.rb:191`; `documentationLinks.js:46` | **Named only**, in comments explaining why media is uploaded by id rather than linked. No branch tests for it. | **Yes** — `whatsapp-error-131053` (EN + AR) |
| **131060** | `app/services/whatsapp/incoming_message_base_service.rb:93`; `documentationLinks.js:47` | **Named only**, in the comment explaining the `type: unsupported` placeholder. The code is never read; the branch keys on `message_type == 'unsupported'` (`:83`). | **Yes** — `whatsapp-error-131060` (EN + AR) |
| **190** | `app/services/whatsapp/health_service.rb:13` (`ApiError#authorization_error?`); `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:54`; `custom/app/services/whatsapp/templates/operation.rb:11`, `:54`; `app/services/social_channels/provider_name_backfill_service.rb:157`; also Instagram/Facebook at `app/services/instagram/base_send_service.rb:76`, `app/services/instagram/message_text.rb:44`, `app/builders/messages/instagram/message_builder.rb:27`; `documentationLinks.js:48` | **Classified in three places, each independently**: latches `authorization_error!` on media 401, marks the health read an authorization failure, and maps a template write to `AUTH_INVALID`. Not in `DeliveryFailure::CODES`. | **Yes** — `whatsapp-error-190` (EN + AR) |
| **2388024** (subcode) | `custom/app/services/whatsapp/templates/operation.rb:10`, `:53` | **Classified** → `NAME_TAKEN`. Meta's "Content in This Language Already Exists", carried on code 100. | **No** |
| **100** | `app/services/whatsapp/provider_error_log.rb:47` (comment, as a code-length example); `operation.rb:9` (comment, as the parent of subcode 2388024); `app/builders/messages/facebook/message_builder.rb:156` (comment, Facebook) | **Named only**, never branched on for WhatsApp | **No** |
| **131030** | `app/services/whatsapp/provider_error_log.rb:47` (comment, code-length example) | **Named only** | **No** |
| **2655007** (subcode) | `app/services/whatsapp/provider_error_log.rb:47` (comment, subcode-length example; the reason `MIN_CONTACT_DIGITS` is 9 and not 7) | **Named only** | **No** |
| **131047** | `docs/real-whatsapp-uat/05-outbound-new-contact.md:137`, `:171`; `06-delivery-status.md:18`, `:85`; `FINAL-CHECKPOINT.md:301`; specs `spec/services/whatsapp/delivery_report_spec.rb:22`, `spec/requests/whatsapp/inbound_reliability_spec.rb:229` | **Named in a design record and in fixtures only** — no production code reads it. It is the re-engagement/24-hour refusal, i.e. the single most likely code an operator will actually see. | **No** |
| **131026** | `docs/real-whatsapp-uat/05-outbound-new-contact.md:172`; `06-delivery-status.md:85`; specs `spec/services/whatsapp/send_failure_spec.rb:51-53`, `spec/models/campaign_recipient_spec.rb:74` etc. | **Named in a design record and in fixtures only.** The UAT record glosses it "Receiver is incapable of receiving this message — the number is not on WhatsApp". | **No** |
| **131059** | `docs/whatsapp-template-manager/01-meta-api-contract.md:198`, `:410` | **Named in a design record only** (v24.0 invalid pagination cursor). No code path acts on it; `fetch_whatsapp_templates` does not retry without cursors (`whatsapp_cloud_service.rb:47-62`). | **No** |
| **131051** | `spec/services/whatsapp/incoming_message_service_spec.rb:356` (fixture for the `unsupported` placeholder) | **Fixture only** | **No** |
| **133010** | `app/javascript/dashboard/components-next/message/specs/MessageError.spec.js:192`; `app/javascript/dashboard/helper/specs/documentationLinks.spec.js:50` | **The canonical "no article" code in the test suite.** Asserted to resolve to `undefined`. | **No, by design** |
| **132000** | `spec/services/flows/nodes/send_template_spec.rb:184`, `:197` | **Fixture only** (template parameter mismatch) | **No** |
| **139069** | `app/javascript/dashboard/components-next/message/fixtures/instagramConversation.js:894` | **Fixture only, Instagram** | n/a |

**Summary of the enumeration.** Codes with an article: **5** (131049, 131042, 131053, 131060, 190), each EN + AR
(`custom/db/documentation/{en,ar}/whatsapp-errors/whatsapp-error-*.md`). Codes the product classifies (changes
behaviour on): **4** numeric — 131049 and 131042 in `DeliveryFailure`, 190 in three separate places, plus
subcode 2388024 in `Templates::Operation` — of which 2388024 has no article. Codes named anywhere in the
repository without an article: **131030, 100, 2655007, 131047, 131026, 131059, 131051, 133010, 132000**. The
`whatsapp-errors` hub says this plainly (`whatsapp-troubleshooting.md:101-105`), so the gap is declared rather
than hidden — but 131047 and 131026 are the two the UAT record says were actually observed in production, and
neither has a page.

Non-numeric classifications also exist: `Whatsapp::ProviderErrorLog#classification` invents four of its own
words for the log line — `unparseable_body`, `provider_refused` (4xx), `provider_error` (5xx),
`provider_rejected` (`provider_error_log.rb:130-136`) — and `Templates::Operation#mapped` classifies by HTTP
status rather than code for `RATE_LIMITED` (429) and `META_UNAVAILABLE` (≥500) (`operation.rb:55-56`).

## 5. Failure paths

**The classifier can only ever see codes from the status webhook.** `Whatsapp::DeliveryFailure` requires a
leading `<3-6 digits>:` (`delivery_failure.rb:35`), and the only writer producing that shape is
`Whatsapp::IncomingMessageBaseService#update_message_with_status:73-76`, which formats
`"#{error[:code]}: #{error[:title]}"` from a `failed` status report. A **synchronous send refusal** writes
`error.message` — Meta's prose, with no code prefix — straight onto the message
(`app/services/whatsapp/providers/base_service.rb:52-57`, `whatsapp_cloud_service.rb:166-169`). So a send-time
refusal is always `UNCLASSIFIED`, always keeps its Retry button, and always renders with no documentation link,
whatever code Meta returned. This is reachable today and is the single largest hole in the failure UX.

**Three of the five coded articles are unreachable from the failed-message block.**
`whatsappErrorArticle(code)` is called from exactly one place — `MessageError.vue:74` — with
`props.deliveryFailure.code`, and `deliveryFailure` is only serialized when the code is *classified*
(`custom/app/models/custom/message.rb:13-17` → `delivery_failure.rb:64-68` returns `nil` otherwise;
`_message.json.jbuilder:20-21`). So `whatsappError131053`, `whatsappError131060` and `whatsappError190` can
never be resolved from this surface, and the `'whatsappTroubleshooting'` fallback at `MessageError.vue:75` is
unreachable in production — the only test that exercises it hand-builds a payload the server never emits
(`MessageError.spec.js:190-196`). Those three articles are reachable only through the manual list in
`whatsapp-troubleshooting.md:106-110`.

**A dropped inbound payload is invisible in the product.** The controller answers Meta `200 OK` before the job
runs, so an `unroutable_payload` (no channel owns the `phone_number_id`) or an inactive account produces one
`Rails.logger.error` line and nothing else — no Sentry event, no operations row, no retry from Meta
(`whatsapp_events_job.rb:161-201`). The comment at `:145-160` records that an earlier version additionally
dropped every inbound message for a channel awaiting reauthorization, permanently and silently.

**Media download failure is silent and lossy.** A failed download returns early and the message saves without
its attachment (`incoming_message_base_service.rb:142-150`). On Cloud, a 401 counts against
`AUTHORIZATION_ERROR_THRESHOLD` only when Meta attributes it to OAuth; any other 401 logs
`event=media_unauthorized` and is deliberately not counted
(`incoming_message_whatsapp_cloud_service.rb:41-57`). Nothing tells the agent the attachment is missing rather
than absent.

**Dedup is a mutex, not a tombstone.** The durable guard is the `Message` row
(`incoming_message_service_helpers.rb:99-103`); the Redis `SET NX EX` lock only serializes racing workers and
is released in an `ensure` precisely so Meta's redelivery can succeed after a failed attempt
(`incoming_message_base_service.rb:41-48`, `message_dedup_lock.rb:6-11`, `:23-31`). The per-(inbox, contact)
mutex has a 30s TTL against a 19×2s retry budget, documented as deliberately ordered
(`whatsapp_events_job.rb:3-6`, `:16-23`).

**Signature verification is decided by the envelope, not by the resolved channel.**
`meta_signature_verification_required?` returns true for any `object == 'whatsapp_business_account'` payload
(`whatsapp_controller.rb:64-68`); the comment records that deciding from a channel resolved out of the same body
let a caller waive its own authentication by omitting `phone_number_id`. The finder now refuses a payload with
no `phone_number_id` outright (`webhook_channel_finder_service.rb:29-33`) and logs
`event=ambiguous_phone_number_id` if two channels claim one id (`:42-54`).

**Submit is claimed before the HTTP call.** `Templates::Submission` takes `submitted_at` under a row lock and
commits it before calling Meta, releasing it with the reason on refusal
(`custom/app/services/whatsapp/templates/submission.rb:31-42`, `:60-62`), so a double-clicked Submit cannot
create two templates at Meta. An edit to a remote template forces `meta_status: 'PENDING'` because Meta's reply
is only `{success: true}` (`revision.rb:26-27`).

**A template going `DISABLED`, `REJECTED` or `PAUSED` is now reported.** `StatusUpdate#report_status_change`
emits `WHATSAPP_TEMPLATE_STATUS_CHANGED` at `:error` for `DISABLED`/`DELETED`, `:warn` for
`REJECTED PAUSED LIMIT_EXCEEDED IN_APPEAL PENDING_DELETION`, `:info` otherwise
(`status_update.rb:51-70`). The comment at `:43-46` records that before this the first anyone knew was a
campaign quietly refusing to send.

**Outgoing delivery failure is logged once per transition.** `Custom::Messages::StatusUpdateService#report_failure`
emits `OUTGOING_DELIVERY_FAILED` with account, inbox, conversation, message, channel, code, classification,
retry policy and the provider's string, at `:warn` when recipient-scoped and `:error` otherwise
(`custom/app/services/custom/messages/status_update_service.rb:21-51`). An unclassified code therefore pages;
131049 does not.

## 6. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| Both webhook endpoints | None — unauthenticated `ActionController::API`, gated only by Meta's HMAC and the verify token | `app/controllers/webhooks/whatsapp_controller.rb:1-4`, `app/controllers/concerns/meta_token_verify_concern.rb:21-40` |
| App-level handshake | `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN` global config, `secure_compare` | `whatsapp_controller.rb:38-41` |
| Per-number handshake | the channel's `provider_config['webhook_verify_token']` | `whatsapp_controller.rb:33-35` |
| Operator kill switch | `INACTIVE_WHATSAPP_NUMBERS` global config; now also applies on the app-level route via the resolved channel | `whatsapp_controller.rb:90-99` |
| Template manager API (all 7 actions) | `administrator?` only; authorized before any record is fetched so a non-admin cannot probe existence | `custom/app/policies/whatsapp/message_template_policy.rb:7-33`, controller `:22` |
| Template manager page | route meta `permissions: ['administrator']` | `templates.routes.js:16-18` |
| Per-inbox template sync | `InboxPolicy#sync_templates?` → `administrator?` | `app/policies/inbox_policy.rb:71-73` |
| Retry a failed message | conversation scope only (`Api::V1::Accounts::Conversations::BaseController`); any agent on the inbox | `messages_controller.rb:33` |
| Composer outside the window | not a permission — `can_reply` disables the editor for every role | `ReplyBox.vue:517-523` |

There is **no account feature flag** for the template manager: `config/features.yml` has
`whatsapp_embedded_signup`, `whatsapp_campaign`, `whatsapp_manual_transfer`, `whatsapp_reconfigure`,
`whatsapp_embedded_signup_inbox_creation` (`:200`, `:204`, `:276`, `:288`, `:293`) and nothing for templates.
CSAT templates are read-only in the manager and the user is pointed at the inbox's CSAT settings
(`custom/app/services/whatsapp/templates/actions.rb:34`, `:75-77`; error `CSAT_MANAGED_ELSEWHERE`).

## 7. Contextual-help opportunities

| UI location (`file:line`) | The user's question | Registry key that should link there | Key exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `MessageError.vue:70-77` (unclassified failure — no link renders at all) | "What does this code mean?" | `whatsappErrorArticle(code)` ?? `whatsappTroubleshooting` — needs the server to emit `code` for unclassified failures too | Yes; both unreachable today |
| `MessagesView.vue:247-256` + `shared/constants/links.js:6-7` — the "cannot reply" banner links to `business.whatsapp.com/policy` | "Why can't I type?" | `whatsappWindow` | **Yes, and never used** (`documentationLinks.js:37`) |
| `ReplyBox.vue:517-523` (editor disabled, no explanation beside it) | "How do I message this person now?" | `whatsappWindow` | Yes, unused |
| `TemplateBuilderDialog.vue` field errors (`PROBLEM.*`, 33 codes) | "What does WhatsApp allow here?" | `whatsappTemplates` | Yes; wired only on the page header via `feature-name="whatsapp_templates"` (`Index.vue:536`, `featureHelper.js:31`) |
| `WHATSAPP_TEMPLATE_MGMT.ERRORS.NOT_EDITABLE` / `CATEGORY_NOT_EDITABLE` / `NOT_DELETABLE` toasts | "Why is this blocked in this state?" | `whatsappTemplateLifecycle` | **Yes, and never used** (`documentationLinks.js:39`) |
| `ERRORS.AUTH_INVALID` ("Reconnect it and try again") | "How do I reconnect?" | `whatsappReconnect` | Yes, unused |
| `ERRORS.RATE_LIMITED` / `META_UNAVAILABLE` | "Is this me or WhatsApp?" | none | **No key, no article** |
| `TemplatePreviewDrawer.vue` status badge, esp. `MISSING` / `SUBMISSION_FAILED` | "What is this state and what do I do?" | `whatsappTemplateLifecycle` | Yes, unused |
| `STATUSES.PAUSED` / `DISABLED` / `LIMIT_EXCEEDED` | "Why did WhatsApp do this to my template?" | `whatsappQualityAndLimits` | Yes, unused |
| `ERRORS.CSAT_MANAGED_ELSEWHERE` | "Where are CSAT templates managed?" | none | No key |

Measured: of the 17 WhatsApp keys in `DOC_ARTICLES` (`documentationLinks.js:35-57`), only four are reachable
from the UI — `whatsapp` and `whatsappTemplates` through `featureHelper.js:14`, `:31`, and
`whatsappError131049`/`whatsappError131042` through `whatsappErrorArticle`. Thirteen are registry-only.

## 8. Current documentation coverage

| Corpus file (EN + AR both present) | Covers | Quality against the code |
|---|---|---|
| `whatsapp/the-whatsapp-24-hour-window.md` | the window, both sides of it, what reopens it | Matches `MessageWindowService:27-28` (a flat 24h for `Channel::Whatsapp`, no `ENABLE_*_HUMAN_AGENT` 7-day escape as Messenger/Instagram have). Good. |
| `whatsapp/whatsapp-templates.md` | categories, components, variables vs sample values, starters, limits | Matches `Validator` and the three-way variable distinction in `docs/whatsapp-template-manager/08-variables.md:9-19`. Good. |
| `whatsapp/whatsapp-template-lifecycle.md` | all 14 states in a table, what each allows, the 30-day name block, Duplicate always works | Matches `Actions::EDITABLE_STATUSES`/`CATEGORY_EDITABLE_STATUSES`/`UNDELETABLE_STATUSES` (`actions.rb:16-19`), `Duplication` (`:7-8`), and `templateUtils.js:173-187`. The best article in scope. |
| `whatsapp/whatsapp-troubleshooting.md` | rejection reasons, send failures, disconnection, and the code index | The "A message did not send" table at `:40-45` is accurate for the strings in `en.yml:185` and `send_on_whatsapp_service.rb:40`. |
| `whatsapp-errors/whatsapp-error-{131049,131042,131053,131060,190}.md` | one code each, including why Retry differs between 131049 and 131042 | Each traceable to the line cited in §4.4. |
| `whatsapp-errors/whatsapp-find-a-failed-message.md` | where a failure shows, the `message_status` filter | — |
| `whatsapp-errors/{whatsapp-number-status, whatsapp-quality-and-limits, whatsapp-display-name, whatsapp-nothing-arrives, whatsapp-reconnect-a-number, whatsapp-number-already-connected, whatsapp-contact-info-requests, whatsapp-business-scoped-contacts}.md` | the eight symptom pages | Anchored per `docs/p7/09-whatsapp-error-knowledge-base.md:46-56` |

EN/AR parity is complete by filename: 6 + 14 files in each locale.

## 9. Missing or stale documentation

1. **No article explains what `sent`, `delivered`, `read` and `failed` mean on a WhatsApp message.** The four
   states are the product's whole delivery vocabulary (`DeliveryReport::REPORTED_STATES`,
   `delivery_report.rb:21`) and a forward-only ladder (`status_update_service.rb:36-45`) with no mention
   anywhere in the corpus — `custom/db/documentation/en/conversations/work-in-the-inbox.md` covers conversation
   status, not message status. A stuck user asking "it says delivered, did they read it?" finds nothing.
2. **131047 has no page**, and it is the code the UAT record shows arriving in production for the window
   refusal (`docs/real-whatsapp-uat/06-delivery-status.md:83-85`). The troubleshooting article documents the
   *symptom* (`whatsapp-troubleshooting.md:41`) but not the code an agent can see on the bubble.
3. **131026 has no page** — "the number is not on WhatsApp", also observed
   (`docs/real-whatsapp-uat/05-outbound-new-contact.md:172`). This is the most common campaign-level failure
   and has no explanation page.
4. **The 14 template-manager error codes are documented nowhere.** `RATE_LIMITED`, `META_UNAVAILABLE`,
   `META_REJECTED_REQUEST`, `NO_WHATSAPP_INBOX`, `SUBMIT_IN_FLIGHT` and `CSAT_MANAGED_ELSEWHERE` each have a
   one-sentence toast and no article behind it. An administrator who hits `META_REJECTED_REQUEST` with a blank
   `reason` (Meta sent no `error_user_msg`) has nothing at all.
5. **Duplicate's renaming behaviour is under-documented.** `Duplication` appends `_copy`, `_copy_2`… up to 50,
   then a random hex suffix, and resets a Meta-recategorised template to `UTILITY`
   (`duplication.rb:34-56`). The lifecycle article says Duplicate "makes a brand-new draft with a new name"
   (`whatsapp-template-lifecycle.md:40-41`) without saying what that name will be or that the category may
   change.
6. **Nothing documents the media-attachment-missing state.** An inbound message that saved without its
   attachment looks identical to a message that had none. `whatsapp-error-131053` is about outbound media.

## 10. Doc claims not proven by code

1. **"Templates refresh from WhatsApp automatically every few hours"** (`whatsapp-templates.md:124`) —
   **confirmed**. `config/schedule.yml:12-15` runs `TriggerScheduledItemsJob` every five minutes;
   `app/jobs/trigger_scheduled_items_job.rb:30` enqueues `TemplatesSyncSchedulerJob`, which selects channels
   whose `message_templates_last_updated` is three hours old or null, capped at
   `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`
   (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-12`). So the real cadence is per channel,
   every three hours, and a large installation can be throttled below that by the per-run cap — which the
   article does not say.
2. **"a code with no page here is one nobody here has met"** (`whatsapp-troubleshooting.md:102-104`). Not true
   as written: 131047 and 131026 were met and recorded in
   `docs/real-whatsapp-uat/{05-outbound-new-contact,06-delivery-status}.md`, and neither has a page. The
   sentence should say the installation classifies them rather than that nobody met them.
3. **"A failed message can be retried from the conversation once you have fixed the cause"**
   (`whatsapp-troubleshooting.md:47`). True in general, but it does not state the two conditions the UI applies:
   Retry disappears entirely more than 24 hours after the message was created
   (`MessageError.vue:60-66`, `hasOneDayPassed`), and it is withdrawn for a recipient-scoped refusal (`:56-58`).
   The 131049 article covers the second; nothing covers the first.
4. **`whatsapp-error-131053` implies the code is handled.** The product only *avoids* the situation by
   uploading media (`media_upload_service.rb:5`); no code path reads 131053, and if it arrives on a send it
   lands as prose with no code prefix and is never classified (§5). Article and code do not contradict, but the
   article is the only place the code is explained to anyone.
5. **`whatsapp-error-190`'s "what Lynomia Chat does after two refusals"** — **confirmed**.
   `Reauthorizable::AUTHORIZATION_ERROR_THRESHOLD = 2` (`app/models/concerns/reauthorizable.rb:16`), applied at
   `:34`, and `Channel::Whatsapp` does not override it. The 190 gates are `health_service.rb:13` and
   `incoming_message_whatsapp_cloud_service.rb:54`. What the article cannot claim is symmetry: a 401 on a media
   read that Meta does *not* attribute to OAuth is explicitly not counted
   (`incoming_message_whatsapp_cloud_service.rb:41-48`), so two media failures no longer latch the channel.
6. **Error 131059 retry remedy.** `docs/whatsapp-template-manager/01-meta-api-contract.md:198`, `:410` state
   the documented remedy is to retry without cursors, and flag "a pre-v24 cursor loop" as a risk.
   `fetch_whatsapp_templates` (`whatsapp_cloud_service.rb:47-62`) recurses on `paging.cursors.after` with no
   131059 handling, so the design record names a gap the code still has.
