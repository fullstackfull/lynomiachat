---
agent: 038
scope: Campaigns and audiences — WhatsApp campaigns end to end, shared audiences, the Label→Campaign bridge, presets, campaign and audience analytics
confidence: high
---

## 1. What the feature is

Lynomia has **two** things people call "audience", and the product uses the same word for both.

A **campaign's audience** is a jsonb array on the campaign row: `[{ "type": "Label" | "Audience", "id": n }]`
(`app/models/campaign.rb:103-107`, `custom/app/models/custom/campaign_audience.rb:21`). It stores *references*,
never conditions and never contacts. Membership is resolved at send time by
`Custom::CampaignAudience#audience_contacts` (`custom/app/models/custom/campaign_audience.rb:12-19`), which unions
each shared audience's `members` relation with the labels branch and dedupes through `account.contacts.where(id: …).reduce(:or)`.

A **shared audience** is not a model. It is a `CustomFilter` with `filter_type: :contact` and `shared: true`
(`custom/app/models/custom/custom_filter.rb:1-23`). `shared` turns a personal saved filter into an account-owned
one: `validates :user, presence: true, unless: :shared?`, `scope :visible_to` returns the user's own plus every
shared one, and `shared_only_for_contacts` refuses sharing a conversation folder
(`custom/app/models/custom/custom_filter.rb:6-8,20-22`). `#members` evaluates the saved query through
`Contacts::FilterService.new(account, nil, …)` — **user `nil`, so account-wide, with no inbox scoping**
(`custom/app/models/custom/custom_filter.rb:13-16`). There is no membership table and nothing is cached.

A **WhatsApp campaign** is one approved template, sent once, at a scheduled time, to the union of the chosen labels
and shared audiences. `ensure_correct_campaign_attributes` forces `campaign_type = one_off` and defaults
`scheduled_at` for Twilio SMS / Sms / Whatsapp inboxes (`app/models/campaign.rb:198-208`); Website inboxes become
`ongoing` with `scheduled_at` nilled. `validate_campaign_inbox` restricts campaigns to
`['Website', 'Twilio SMS', 'Sms', 'Whatsapp']` (`app/models/campaign.rb:191-195`).

Dispatch: `TriggerScheduledItemsJob` runs on `*/5 * * * *` (`config/schedule.yml:12-15`) and selects
`campaign_type: :one_off, campaign_status: :active, scheduled_at: 3.days.ago..Time.current`
(`app/jobs/trigger_scheduled_items_job.rb:8,15-18`). Each selected campaign is enqueued as
`Campaigns::TriggerOneoffCampaignJob`, which calls `campaign.trigger!`
(`app/jobs/campaigns/trigger_oneoff_campaign_job.rb:3-5`). `trigger!` gates on `one_off?`, then on
`feature_enabled?`, then takes a lock in `mark_processing!` and dispatches by inbox type
(`app/models/campaign.rb:74-81,146-157,167-175`). For WhatsApp that is `Whatsapp::OneoffCampaignService`, which
re-validates type, status, **WhatsApp Cloud provider** and the feature flag, then loops the audience and
`completed!`s (`app/services/whatsapp/oneoff_campaign_service.rb:4-8,15-40`).

Per-recipient outcomes are Lynomia's. `Custom::Whatsapp::OneoffCampaignService` prepends the upstream service and
records an outcome at every decision point upstream already makes, delegating rather than re-expressing the loop
(`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb:22-147`). Rows are seeded `queued` **before** the
first provider call in batches of 1,000 (`custom/app/services/campaigns/recipient_snapshot.rb:44,89-96`) so the
`audience` denominator does not grow during a run. `CampaignRecipient` is forward-only: `LADDER` is
`queued → sent → delivered → read`, `skipped` is off the ladder entirely, and a failure may only override `queued`
or `sent` (`custom/app/models/campaign_recipient.rb:34,40,45,58-80,92-121`). Meta's status webhooks reach it
through `Whatsapp::DeliveryReport`, which looks the row up by `(inbox_id, source_id)` and hands the state to
`record_outcome!` (`custom/app/services/whatsapp/delivery_report.rb:35-46,58-62`).

Audiences are reachable from a dedicated page (`AudiencesIndex.vue`), from the sidebar's "All Audiences" entry
which is always present even with zero audiences (`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:575-583`),
and from nine presets (`app/javascript/dashboard/recipes/audiencePresets.js:49-157`).

## 2. Surfaces and routes

| Surface | Path | `file:line` |
|---|---|---|
| Campaigns shell | `/accounts/:id/campaigns` | `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js:18-20` |
| WhatsApp campaigns list | `campaigns/whatsapp` → `campaigns_whatsapp_index` | `campaigns.routes.js:56-63`, page `pages/WhatsAppCampaignsPage.vue` |
| WhatsApp campaign analytics | `campaigns/whatsapp/:campaignId/analytics` | `campaigns.routes.js:64-72`, page `pages/WhatsAppCampaignAnalyticsPage.vue` |
| SMS campaigns | `campaigns/sms` → `campaigns_sms_index` | `campaigns.routes.js:49-54` |
| Create/edit form | `WhatsAppCampaignForm.vue` | `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue:1-308` |
| Recipient picker (shared by SMS + WhatsApp) | `CampaignRecipients.vue` | `.../CampaignPage/CampaignRecipients.vue:1-179`; SMS at `SMSCampaign/SMSCampaignForm.vue:181-186` |
| Campaign card (status badge) | `CampaignCard.vue` | `app/javascript/dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue:56-99` |
| Audiences page | `/accounts/:id/contacts/audiences` → `contacts_dashboard_audiences_index` | `app/javascript/dashboard/routes/dashboard/contacts/routes.js:44-52` |
| One audience (conditions editor) | `contacts/segments/:segmentId` (`?edit=1`) | `app/javascript/dashboard/helper/audienceHelper.js:88-92` |
| Audience explainer | `AudienceExplainer.vue` | `app/javascript/dashboard/components-next/audience/AudienceExplainer.vue:1-95` |
| Account-wide campaign analytics | `/analytics/campaigns` | `app/javascript/dashboard/routes/dashboard/analytics/analytics.routes.js:40-41`, `AnalyticsCampaigns.vue` |

| API | Controller + action | `file:line` |
|---|---|---|
| `GET/POST/PATCH/DELETE /api/v1/accounts/:id/campaigns` | `Api::V1::Accounts::CampaignsController` | `app/controllers/api/v1/accounts/campaigns_controller.rb:5-22`; routes `config/routes.rb:101` |
| `POST /campaigns/audience_preview` | `Campaigns::AudiencePreviewsController#create` | `custom/app/controllers/api/v1/accounts/campaigns/audience_previews_controller.rb:7-13`; route `config/routes/campaign_audiences.rb:8` |
| `GET /campaigns/:id/analytics/metrics` | `Campaigns::AnalyticsController#metrics` → `Campaigns::RecipientMetrics` | `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb:30-32`; route `config/routes.rb:104` |
| `GET /campaigns/:id/analytics/contacts` | `Campaigns::AnalyticsController#contacts` | same file `:34-36`; route `config/routes.rb:105`; view `custom/app/views/api/v1/accounts/campaigns/analytics/contacts.json.jbuilder` |
| `GET /analytics/campaigns` | `Analytics::Campaigns::Overview` | `config/routes/analytics.rb:16`, `custom/app/services/analytics/campaigns/overview.rb:16-27` |
| Audiences CRUD | `custom_filters` API, overridden | `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:6-24` |
| Audience count | `POST /contacts/filter` | called from `AudiencesIndex.vue:96` |

There is **no campaign-level `audience` serializer for labels/audience names**: `_campaign.json.jbuilder:20` emits
the raw jsonb array of `{type, id}`, so the browser resolves names from the label and custom-view stores.

## 3. User-visible states

**Campaign list / card** (`CampaignCard.vue:66-99`): four one-off states, each with a tone.

| State | Badge string | Tone | Produced by |
|---|---|---|---|
| Scheduled (fallthrough from `active`) | `CAMPAIGN.SMS.CARD.STATUS.SCHEDULED` | `warning` | default branch, `CampaignCard.vue:98` |
| Processing | `…STATUS.PROCESSING` | `info` | `mark_processing!`, `app/models/campaign.rb:146-157` |
| Completed | `…STATUS.COMPLETED` | `success` | `campaign.completed!`, `app/services/whatsapp/oneoff_campaign_service.rb:7` |
| **Blocked** | `…STATUS.BLOCKED` = "Not sent — channel unavailable" | `danger` | `block_for_disabled_feature!`, `app/models/campaign.rb:120-134` |

Loading and empty: spinner with `role="status"` while `uiFlags.isFetching`
(`WhatsAppCampaignsPage.vue:135-143`); `WhatsAppCampaignEmptyState` otherwise (`:150-154`).

**Recipient picker** (`CampaignRecipients.vue`): audiences dropdown shows "Loading your shared audiences…" while
`customViews/getUIFlags.isFetching` (`:40,140-144`), "No shared audiences yet…" when the fetch returned none
(`:142-143`), and when the account genuinely has none the inline `AudienceExplainer` plus a "Create a shared
audience" button replaces silence (`:152-167`). Count has four states: empty (no note), "Counting matching
contacts…", "N contacts match now. Each contact receives the campaign once…", and
"The number of matching contacts could not be loaded." — **a failed count is unknown, deliberately never zero**
(`:100-111`).

**Analytics page** (`WhatsAppCampaignAnalyticsPage.vue`): loading spinner (`:420-433`); three distinct empty
states — error, pending (campaign is `processing` but no rows yet), and "Analytics aren't available for this
campaign" for a campaign sent before recipient recording existed (`:144-174`); an amber processing banner whose
wording branches on `queued` and `sent` counts, with four plural forms (`:94-143,388-398`); six metric cards with
rates over `audience` (`:180-200`); six status tabs with counts (`:29-36,202-215`); a 25-per-page delivery table
with its own `noDataMessage` for an empty filtered tab (`:221-233`). Polls every 5s while processing, only when
the page is active (`:27,299-311,369-377`).

**Audiences page** (`AudiencesIndex.vue`): loading (`:232-242`), empty state with preset + build-from-filters
actions (`:244-268`), and per-card `Shared` / `Only you`, "No conditions saved, so this matches every contact.",
a count-on-demand button, and a usage line "Used by 2 automation rules · 1 campaign"
(`AudienceCard.vue:86-113`; strings in `contactFilters.json`/contacts locale).

## 4. Errors and validation messages

Client-side (`WhatsAppCampaignForm.vue:69-77,130-143`): `title` required+minLength, `inboxId`, `templateId`,
`scheduledAt` required, and `selectedAudience` `requiredIf(() => !state.selectedSharedAudiences.length)` — so
labels *or* audiences satisfies it. Strings: `CAMPAIGN.WHATSAPP.CREATE.FORM.{TITLE,INBOX,TEMPLATE,SCHEDULED_AT}.ERROR`
("Title is required", "Inbox is required", "Template is required", "Scheduled time is required") and
`CAMPAIGN.RECIPIENTS.ERROR` = "Select at least one label or shared audience"
(`app/javascript/dashboard/i18n/locale/en/campaign.json`). Submit is additionally disabled until the template
parser reports its required variables filled (`:145-151`).

Server-side:

| String | i18n key | `file:line` |
|---|---|---|
| "A campaign's audience can only include the shared audiences of this account, on SMS and WhatsApp campaigns." | `errors.campaigns.audience_not_shared` | `config/locales/en.yml:231`; raised at `custom/app/models/custom/campaign_audience.rb:33-35` and returned 422 by `audience_previews_controller.rb:10` |
| "'%{status}' is not a recipient status. Allowed: %{allowed}." | `errors.campaigns.unknown_recipient_status` | `config/locales/en.yml:232`; `analytics_controller.rb:62-69` |
| "This audience is used by %{count} automation rules. Remove it from those rules first." | `errors.custom_filters.used_by_automation` | `config/locales/en.yml:269`; `custom_filters_controller.rb:53` |
| "This audience is used by %{count} campaigns that have not been sent yet. Delete those campaigns or wait until they are sent first." | `errors.custom_filters.used_by_campaigns` | `config/locales/en.yml:270`; `custom_filters_controller.rb:54` |
| "Unsupported Inbox type" (not i18n'd — a bare English string) | — | `app/models/campaign.rb:194` |
| "The campaign is already completed" (bare string) | — | `app/models/campaign.rb:234` |
| "must belong to the same account as the campaign" (bare strings, ×2) | — | `app/models/campaign.rb:221,229` |

Provider-relayed errors reach the user only on the analytics table, from the recipient row: `error_code`,
`error_title`, `error_message`, read in the order message → title → code
(`contacts.json.jbuilder:16-19`), with `CAMPAIGN.WHATSAPP.ANALYTICS.TABLE.ERROR_CODE` = "Code {code}".

Skip reasons are a closed set of **fixed English strings on the model, not i18n keys**
(`custom/app/services/campaigns/recipient_snapshot.rb:24-34`): "No WhatsApp destination", "Multiple WhatsApp
identities", "Campaign has no template parameters", "Template variables resolved to blank", "Authentication
template not allowed for this recipient", "No approved template for this name and language". They are rendered
verbatim in the Reason column and grouped on directly by the account-wide skip breakdown
(`custom/app/services/analytics/campaigns/metrics.rb:151-155`), which is why they must stay low-cardinality and
data-free — but it also means **an Arabic-locale operator reads them in English**.

Audience condition validation: >50 values in one condition or >10 conversation/Commerce conditions raises
`CustomExceptions::CustomFilter::InvalidValue` (`custom/app/services/custom/contacts/filter_service.rb:11-12,38,51`).

## 5. Failure paths

1. **Capability unavailable at send time → `blocked`.** `feature_enabled?` is
   `inbox.inbox_type != 'Whatsapp' || account.feature_enabled?(:whatsapp_campaign)`
   (`app/models/campaign.rb:110-112`), so only a WhatsApp campaign can reach this. `block_for_disabled_feature!`
   flips status under a lock, sets `blocked_reason = 'FEATURE_DISABLED'`, and records one
   `Operations::Signal` (`app/models/campaign.rb:120-144`). The campaign is then excluded from the scheduler
   forever, because the selection is on `campaign_status: :active` (`trigger_scheduled_items_job.rb:15-16`).
   **The user-visible consequence is a red "Not sent — channel unavailable" badge and nothing else.**
   `blocked_reason` is serialized (`app/views/api/v1/models/_campaign.json.jbuilder:21-22`) but no Vue file reads
   it; the signal is visible only in Super Admin Operations
   (`custom/app/controllers/super_admin/operations_controller.rb:26,39-45`), i.e. to the platform operator, not
   the account administrator who scheduled the campaign. And `Campaign#unblock!`
   (`app/models/campaign.rb:87-100`) **has no caller anywhere in the product** — no route, no controller action,
   no UI; `campaign_params` does not permit `campaign_status` (`campaigns_controller.rb:31-32`). A blocked
   campaign is, from the dashboard, unrecoverable except by deleting it.
2. **Wrong WhatsApp provider.** `validate_provider!` raises `'WhatsApp Cloud provider required'`
   (`app/services/whatsapp/oneoff_campaign_service.rb:27-29`) inside the job. Nothing is written to the campaign:
   it stays `processing` for ever and `started_at` is set. No badge, no toast, no signal. **This is the silent
   stuck state the `blocked` design removed for one cause and left for the other.**
3. **Per-contact skips.** No destination, ambiguous destination (two BSUIDs on one inbox — refused rather than
   guessed, `oneoff_campaign_service.rb:117-137`), blank Liquid variables, authentication-template guard, and
   "no approved template for this name and language". Each writes a `skipped` row with its reason
   (`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb:47-108`). The campaign still reads
   *Completed*, so **"Completed" does not mean "delivered"** and the only way to learn otherwise is the analytics
   page.
4. **Meta refuses a send.** `channel.last_send_failure` is read and stored as code/title/message
   (`custom/.../oneoff_campaign_service.rb:83-84,118-123`), surfaced per row.
5. **Recording failure never aborts a run.** `contained` rescues, logs, and reports to Sentry
   (`custom/.../oneoff_campaign_service.rb:127-135`); the seed is similarly contained (`:137-142`). Correct — a
   send handed to Meta cannot be unsent — but it means the snapshot can be incomplete with no user-facing signal.
6. **Scheduled more than 3 days ago.** Never selected (`trigger_scheduled_items_job.rb:16`). The campaign sits at
   *Scheduled* indefinitely with no indication it will never run.
7. **Audience still referenced.** Deleting or unsharing is refused 422 with a counted reason
   (`custom_filters_controller.rb:14,21,51-56`). `Audience::Usage.campaigns` counts `active`, `processing` **and
   `blocked`** (`custom/app/services/audience/usage.rb:22-25`) — so a blocked campaign that can never be
   unblocked from the UI permanently pins its audience.
8. **Count request fails.** `countFailed` renders "could not be loaded" rather than 0
   (`CampaignRecipients.vue:85-87,102`); the Audiences page alerts "Couldn't count this audience. Open it to see
   why." (`AudiencesIndex.vue:98-103`).
9. **Draft loss.** The campaign→Contacts→campaign round trip keeps the half-filled form in `sessionStorage` for
   60 minutes, read-once (`app/javascript/dashboard/helper/campaignDraft.js:20,62-77`). Outside that, or in a new
   tab, the form is empty on return with no explanation.

## 6. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| All campaign routes | `featureFlag: campaigns`, `permissions: ['administrator']` | `campaigns.routes.js:10-13` |
| WhatsApp campaign routes | `featureFlag: whatsapp_campaign` (overrides) | `campaigns.routes.js:58-61,66-69`; flag `app/javascript/dashboard/featureFlags.js:9`; `config/features.yml:204-206`, default **off** |
| Campaign API (every action) | `CampaignPolicy` — `@account_user.administrator?` on index/show/create/update/destroy | `app/policies/campaign_policy.rb:1-21` |
| Audience preview | `authorize Campaign, :create?` | `audience_previews_controller.rb:8` |
| Campaign analytics | `CampaignPolicy#show?`, campaign looked up inside `Current.account.campaigns`, **deliberately not feature-gated** | `analytics_controller.rb:40-43`; `config/routes.rb:102-105` |
| Audiences page | `featureFlag: crm`, `permissions: ['administrator', 'agent', 'contact_manage']` | `app/javascript/dashboard/routes/dashboard/contacts/routes.js:7-10,51` |
| Sharing an audience | administrator only, on create and update | `custom_filters_controller.rb:7,13` |
| Changing/deleting a shared audience | administrator only | `custom_filters_controller.rb:13,20` |
| Visibility of a personal audience | `visible_to(user)` = own ∪ shared | `custom/app/models/custom/custom_filter.rb:8` |
| Whether a campaign actually sends | `account.feature_enabled?(:whatsapp_campaign)` at send time, again in the service | `app/models/campaign.rb:110-112`; `app/services/whatsapp/oneoff_campaign_service.rb:31-33` |

So: **agents can build and save audiences but cannot see the campaigns section at all.** The UI mirrors this —
`AudienceCard` resolves the target route's own `meta` before offering "Use in a new WhatsApp campaign"
(`AudienceCard.vue:63-73`), so a shortcut is never offered to a page that would refuse.

## 7. Contextual-help opportunities

`DOC_ARTICLES` already holds all three keys for this area — `sharedAudiences`, `labelsOrAudiences`, `campaigns`
(`app/javascript/dashboard/helper/documentationLinks.js:30-33`). **None of them is rendered anywhere.**
`DocsLink.vue` is consumed only by Commerce and Platform Support surfaces (grep of `DocsLink` across
`app/javascript/dashboard`: 9 files, all Commerce settings / CommercePanel / PlatformSupport pages). Campaigns
and audiences have rich in-product explainers (`AudienceExplainer.vue`) but zero links to the corpus.

| UI location (`file:line`) | The question a user has there | Registry key | Key exists? |
|---|---|---|---|
| `CampaignRecipients.vue:132-149` (Shared audiences dropdown) | "What is a shared audience and why can't I pick my own filter?" | `sharedAudiences` | yes, unused |
| `CampaignRecipients.vue:152-167` (`AudienceExplainer` action row) | "Label or audience — which do I want?" | `labelsOrAudiences` | yes, unused |
| `CampaignRecipients.vue:100-111` (count note) | "Is this the number that will actually receive it?" | `campaigns` | yes, unused |
| `WhatsAppCampaignForm.vue:248-264` (template picker + INFO line) | "Why isn't my template in this list?" | `whatsappTemplates` | yes (`documentationLinks.js:37`), unused here |
| `WhatsAppCampaignForm.vue:280-288` (Scheduled time, `min` = now) | "Why is there no Send now?" | `campaigns` | yes, unused |
| `CampaignCard.vue:94-96` (blocked badge) | "Not sent — channel unavailable. What do I do?" | **none — no article exists** | **no** |
| `WhatsAppCampaignAnalyticsPage.vue:144-174` (UNAVAILABLE empty state) | "Why are there no analytics for this campaign?" | **none** | **no** |
| `CampaignDeliveryTable` Reason column (`contacts.json.jbuilder:16-19`) | "What does 'Multiple WhatsApp identities' mean?" | **none per reason**; nearest is `whatsappFindAFailedMessage` | partial |
| `AudiencesIndex.vue:230` (`AudienceExplainer`) | "What is an audience?" | `sharedAudiences` | yes, unused |
| `AudiencesIndex.vue:291-298` (preset gallery) | "What does this preset actually ask?" | `sharedAudiences` | yes, unused |
| `AudienceCard.vue:86-113` ("Used by 2 rules · 1 campaign") | "Why can't I delete this?" | `sharedAudiences` | yes, unused |
| `AnalyticsCampaigns.vue:20` (breakdown: `audience`, `failure`, `skip_reason`) | "Is 'Audience used' a count of people?" (it is a count of *campaigns* — `metrics.rb:157-176`) | **none** | **no** |

## 8. Current documentation coverage

Section `audiences-and-campaigns`, position 40, icon `megaphone`
(`custom/db/documentation/manifest.yml`). Three articles, EN and AR both present:

| File | Words (EN) | Verdict |
|---|---|---|
| `custom/db/documentation/en/audiences-and-campaigns/shared-audiences.md` | 1,575 | strong; see §9/§10 for two defects |
| `.../labels-or-shared-audiences.md` | 1,313 | strong and unusually accurate |
| `.../whatsapp-campaigns.md` | 1,706 | strong on the happy path, blind on the blocked state |

Accuracy spot-checks, all **confirmed**: the 5-minute scheduler cadence (`config/schedule.yml:12-13`); the
3-day cut-off (`trigger_scheduled_items_job.rb:8`); "campaigns refuse to run on any other WhatsApp provider"
(`oneoff_campaign_service.rb:27-29,143-145`); the four template-eligibility rules — APPROVED, not AUTHENTICATION,
not a CSAT survey, no LIST/PRODUCT/CATALOG/CALL_PERMISSION_REQUEST component and no LOCATION header
(`node_modules/@chatwoot/utils/dist/utils.cjs.development.js:2426-2436`, via
`getFilteredWhatsAppTemplates`, `app/javascript/dashboard/store/modules/inboxes.js:53-73`); "each contact
receives it once" (`campaign_audience.rb:18`); "administrators only" (`campaign_policy.rb`); the filter limits of
10 conversation/Commerce conditions and 50 values (`custom/app/services/custom/contacts/filter_service.rb:11-12`);
"no condition anywhere asks whether a contact carries a label" for automation; the nine presets and their inputs
match `audiencePresets.js:49-157` exactly, including that "High-value buyers" asks for the threshold rather than
shipping a number.

`labels-or-shared-audiences.md`'s claim that a campaign reads **contact** labels is confirmed —
`audience_contacts` goes through `account.contacts.tagged_with(...)` (`app/models/campaign.rb:103-107`).

Related design records (not corpus, but the de-facto internal reference): `docs/campaigns/00-07`,
`docs/audience/00-06`, `docs/contacts/07-label-vs-audience.md`, `docs/usability/13-audience-presets.md`,
`docs/product-enablement/13-audience-ux-implementation.md`.

## 9. Missing or stale documentation

1. **The blocked state is entirely undocumented.** No article mentions "Not sent — channel unavailable",
   `blocked`, `FEATURE_DISABLED`, or what an administrator should do. The one thing a stuck user can see
   (`CampaignCard.vue:94-96`) has no help at all. It is also the one state with **no product escape hatch**
   (§5.1), so the article has to say "ask your platform operator" — which means it needs a true answer first.
2. **No article covers campaign analytics as a surface.** `whatsapp-campaigns.md` mentions "View analytics" only
   inside a Limits bullet, hedged. There is no explanation of the six metrics, the difference between "Submitted
   to WhatsApp" and "Delivered", why `delivered` counts a `read_at`-only row
   (`custom/app/services/campaigns/recipient_metrics.rb:9-12,56-66`), what the six status tabs mean, or what the
   six skip reasons mean and which is fixable. Six fixed English strings reach the user with no article behind
   any of them.
3. **The `processing`-forever path is undocumented** (wrong provider, §5.2). The nearest statement is "campaigns
   refuse to run on any other WhatsApp provider", which reads as a pre-flight refusal; it is actually a job that
   raises after the status has already flipped.
4. **No article for the account-wide campaign report** (`/analytics/campaigns`). In particular the "Audience used"
   breakdown is a count of *campaigns*, not recipients, and the rows deliberately do not sum
   (`custom/app/services/analytics/campaigns/metrics.rb:157-176`) — a number guaranteed to be misread without a
   sentence about it. There is no "audience analytics" article of any kind.
5. **The Label→Campaign bridge is not described.** "Use in a new WhatsApp campaign" exists from a label page as
   well as an audience page (`ContactListHeaderWrapper.vue:261-266`, `audienceHelper.js:62-65`), carries the id in
   the URL so the link is shareable, and silently opens an empty form if the id is not one of the account's
   (`WhatsAppCampaignsPage.vue:77-89`). Nor is the reverse trip — campaign → Contacts → back, with a 60-minute
   read-once draft (`campaignDraft.js:20`) — documented anywhere a user would find it.
6. **Audience presets have no article.** Nine presets with a dedicated gallery, a requirements model and a
   "start from scratch instead" escape (`AudiencesIndex.vue:163-179,291-298`), covered only as a table inside
   `shared-audiences.md`. The Audiences page itself — count-on-demand, duplicate, copy link, the usage line — is
   likewise only implied.

Stale/incorrect in the corpus:

- `whatsapp-campaigns.md`: *"Per-recipient delivery results are not available on every installation."* The
  analytics routes are **explicitly not feature-gated**, with a comment saying so
  (`config/routes.rb:102-105`, `analytics_controller.rb:17-19`). The hedge was true before recipient recording
  landed; it is now wrong, and it tells a stuck user to stop looking for the one screen that would help them.
- `whatsapp-campaigns.md`: *"The campaign appears in the list as Scheduled"* … *"While it is sending the card
  reads Processing; afterwards, Completed."* Four states exist, not three.
- `docs/campaigns/03-audience-dependency.md:12,18-24` (design record) states the dependency guard counts
  `active` and `processing`. The code counts `blocked` too (`custom/app/services/audience/usage.rb:23`). Stale.

## 10. Doc claims not proven by code

| Claim | Where | What the code says |
|---|---|---|
| "A campaign cannot be edited after it is created. Delete it and create another." | `whatsapp-campaigns.md` Limits | **True of the UI only.** `CampaignCard.vue:163-171` renders the edit button only for live-chat campaigns, but `PATCH /campaigns/:id` exists and permits `audience`, `template_params`, `scheduled_at`, `message`, `inbox_id` (`campaigns_controller.rb:15-17,30-33`), gated only by `CampaignPolicy#update?` = administrator. The only block is `prevent_completed_campaign_from_update` (`app/models/campaign.rb:233-235`), which stops updating a **completed** campaign. A scheduled WhatsApp campaign is editable by API. The sentence is right as advice and wrong as a statement about the product. |
| "Customers with a shipped order" preset asks for an order "the store has marked shipped" | `shared-audiences.md` preset table; `RECIPES.AUDIENCE.CUSTOMERS_WITH_SHIPPED_ORDER.DESCRIPTION` | The preset emits `commerce_order_status = 'shipped'` (`audiencePresets.js:138-140`), and `shipped` **is** a permitted order status (`custom/app/services/audience/commerce_condition.rb:28`). But the preset's own source comment (`audiencePresets.js:136-137`) says the normalized *shipment* statuses contain no "shipped" — i.e. the condition reads the order status, not the shipment status. Whether `order_status = shipped` is populated by every provider is **unverified**; I did not trace provider normalization. If some providers never set it, this preset silently matches nobody. Needs Agent 043–047 to confirm. |
| "A scheduled time more than three days in the past is never sent. If your account was down over that window, recreate the campaign." | `whatsapp-campaigns.md` Limits | Confirmed for `active` campaigns (`trigger_scheduled_items_job.rb:16`). But `unblock!` deliberately moves `scheduled_at` forward when it has fallen outside the window (`app/models/campaign.rb:87-95`) — so the product has an answer better than "recreate it" that no user can reach (§5.1). The advice is accurate only because the better path is unreachable. |
| "When *you* open an audience, conversation conditions only see conversations you are allowed to see. When a campaign or an automation rule reads the same audience it is evaluated for the whole account, so the two counts can differ." | `shared-audiences.md` Limits | Confirmed: `#members` passes `nil` as the user (`custom/app/models/custom/custom_filter.rb:15`), while the Audiences page counts through `ContactAPI.filter` as the signed-in user (`AudiencesIndex.vue:96`). This is an important and correctly documented discrepancy; worth promoting out of Limits, because the number a user reads before sending can legitimately differ from the number sent to. |
| "Changes to audiences are recorded in the audit log." | `shared-audiences.md` | Confirmed by the audit-log strings `AUDIT_LOGS.AUDIENCE.{ADD,EDIT,DELETE}` and `spec/controllers/api/v1/accounts/contacts/audiences_spec.rb:73-81`, which asserts create/update/destroy rows for `CustomFilter`. |
| "Up to 1,000 saved filters per person." | `shared-audiences.md` Limits | Confirmed: `Limits::MAX_CUSTOM_FILTERS_PER_USER = 1000` (`lib/limits.rb:11`), enforced per `(account, user_id)` by `validate_number_of_filters` (`app/models/custom_filter.rb:25,30-34`) with the message "Limit reached. The maximum number of allowed custom filters for a user per account is 1000." (`config/locales/en.yml:268`). Note the scope: per user **per account**, and a shared audience has a `user_id` too, so it counts against its creator's thousand. |
