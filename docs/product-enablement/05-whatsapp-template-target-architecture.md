# WhatsApp Template Manager — target architecture

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Part 3 of the enablement brief. The Meta-side and repo-side proof is in
`docs/product-enablement/04-whatsapp-template-current-state.md`; this document does not re-derive it and cites it as **04
§n**. Every Meta constraint used here is the `meta-template-api` verifier's reading of Meta's **normative**
template-management page, not the wider node-reference list — marked **(V)** where the verifier corrected the inventory.
Claims I could not cite are marked **UNVERIFIED**. Nothing here proposes a migration; where one is required the
requirement is stated and left for approval.

---

## 1. The decision in one page

**Build a draft-and-submit surface on top of the sync that already exists. Do not build a template authoring IDE, and do
not add a provider layer.**

The shape: Meta's synced array stays exactly where it is and keeps being the single source of truth for *what Meta thinks*
and for *what may be sent*. A new, sparse, per-template local record carries only what Lynomia owns — "this is a starter
draft", "we submitted it at T", "Meta rejected it for this reason". The two are joined on `(name, language)` and read
together only by the new management surface. The send path, the Flow node, Campaigns and the composer are not touched.

| Layer | Target state | Classification |
|---|---|---|
| WhatsApp inbox / `Channel::Whatsapp`, `provider_config`, `template_access_token` | unchanged | **REUSE** |
| 3-hourly sync + `channel_whatsapp.message_templates` jsonb | unchanged; remains the Meta mirror **and** the only source the send path reads | **REUSE** |
| Send chain (`SendOnWhatsappService` → `TemplateProcessorService` → `PopulateTemplateParametersService` → `send_template`) | unchanged | **REUSE** |
| Campaigns, Flow `send_template` node, composer, New Conversation | consumers only; no change | **REUSE** |
| Settings → Templates page | host for the new surface | **REUSE** |
| Starter gallery mechanics (`dashboard/recipes/*`, `RecipeDialog.vue`) | one new recipe type | **REUSE** |
| **Per-template Lynomia record** (draft state, provenance, submitted_at, retained rejection reason) | **the one new primitive.** Requires a migration — stated, not designed | **NEW PRIMITIVE REQUIRED** |
| Generic `POST /{WABA}/message_templates` submit | new service beside `Whatsapp::CsatTemplateService`, same credential and error-parsing path | **EXTEND** |
| Single-template status read `GET /{TEMPLATE_ID}` | the manual-refresh primitive; Meta supports it, repo never calls it (04 table row 2) | **EXTEND** |
| `POST /{TEMPLATE_ID}` edit | narrow and conditional; CSAT first (04 §5.2) | **EXTEND** |
| `DELETE /{WABA}/message_templates` generically | permitted, but only behind an explicit 30-day warning | **EXTEND** |
| App-default (`whatsapp_business_account`) webhook route | real, valuable, and **not phase 1** (04 §4.1) | **NEW PRIMITIVE REQUIRED** |
| A second WhatsApp provider abstraction / template gateway | **DO NOT CREATE** — `PROVIDERS = %w[default whatsapp_cloud]` (`app/models/channel/whatsapp.rb:36`) and the one extension point that exists (`provider_service` delegation, `app/models/channel/whatsapp.rb:146-150`) already does this job |
| Category review / appeal from Lynomia | **DO NOT CREATE** — WhatsApp Manager only **(V)** |
| Template versioning / duplicate against Meta | **DO NOT CREATE** — Meta exposes no such operation **(V)** |
| `currency` / `date_time` template variables | **DO NOT CREATE** — §6.3 |
| Cart / abandoned-cart template variables | **DO NOT CREATE** — §6.4 |

The single most important architectural property to hold onto, stated once here and justified in §5.3: **a Lynomia draft
must never enter `channel_whatsapp.message_templates`.** Every send-side consumer reads that column, so keeping drafts out
of it makes "a draft can never be sent" a structural fact rather than a UI rule.

---

## 2. Storage — does a jsonb column suffice?

**No. A managed library needs a per-template row. This is the one place a new primitive is justified, and the argument
comes entirely from what the sync does.**

### 2.1 The sync behaviour that decides it

```ruby
# app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45
def sync_templates
  whatsapp_channel.mark_message_templates_updated                     # :37
  return if (templates = fetch_whatsapp_templates).blank?             # :38
  whatsapp_channel.account.update_cache_key('inbox') if templates != whatsapp_channel.message_templates
  whatsapp_channel.update_columns(message_templates: templates, message_templates_last_updated: Time.current)  # :43
end
```

Four properties of those nine lines, each decisive:

1. **The write is wholesale and verbatim.** `templates` is `response['data']` with no mapping, no merge and no field
   selection (`:47-62`). Any key Lynomia added to an element of that array is gone on the next successful pass.
2. **It is `update_columns`.** Validations, callbacks and `after_commit` hooks are all skipped (`:42-44`, with the RuboCop
   disable around it). There is no model hook that could re-merge local state, so "preserve it in a callback" is not an
   available design.
3. **A draft is not in Meta's list at all.** An unsubmitted Lynomia draft has no Meta object, so it cannot appear in
   `response['data']`. It is therefore not merely overwritten — it is **guaranteed destroyed on the first successful
   sync**, which the scheduler triggers within three hours for every channel whose stamp is older than that
   (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-13`), and immediately on channel create
   (`app/models/channel/whatsapp.rb:46`) or on an admin pressing Sync (`config/routes.rb:303`).
4. **A failed sync does *not* wipe the column** — the `blank?` guard at `:38` returns early and
   `fetch_whatsapp_templates` returns `[]` on a non-success response (`:51-55`). This is worth stating because it means
   the risk is not "we lose data when Meta is down"; the risk is the ordinary, successful, every-three-hours path.

There is no version of "store the draft in the jsonb" that survives (3). Storing drafts in a *second* jsonb column on the
same row would survive the sync, but see §2.3.

### 2.2 The requirement, stated precisely

| # | Requirement | Why the jsonb cannot meet it |
|---|---|---|
| R1 | A Lynomia draft survives an arbitrary number of successful syncs until it is submitted or deleted | §2.1 (3) — a draft is absent from Meta's payload and is erased wholesale |
| R2 | Lynomia-owned attributes on a template Meta *does* return (`starter_key`, `submitted_by`, `submitted_at`, local notes) survive a sync | §2.1 (1) — verbatim overwrite drops added keys |
| R3 | A stable local identity exists before Meta assigns one, and persists across a Meta-side delete | The jsonb has no primary key; the frontend already synthesizes one from `(platform, provider account, Meta id, language)` at `templates/templateUtils.js:31-47` precisely because none exists |
| R4 | A rejection reason remains readable after Meta stops returning it | 04 §4.2's caveat: `rejected_reason` is only visible while it is in Meta's list payload, because nothing persists it independently |
| R5 | Nothing on the send path has to read the new record for a send to work | Keeps the blast radius of the primitive away from `template_processor_service.rb:21-27` and the four pickers in §5.3 |
| R6 | Lynomia's own edit activity is countable, so the 1-per-24h / 10-per-30d budget can be warned about | No timestamp exists per template; the column has one shared `message_templates_last_updated` (`db/schema.rb:801`) |

**Classification: NEW PRIMITIVE REQUIRED.** This is the only item in this document that earns it.

### 2.3 Why a row and not a second jsonb column

Both need a migration, so the migration itself does not decide it. Three things do:

- **Uniqueness.** `(channel_id, name, language)` is the real key of a WhatsApp template, and a name collision at submit
  time is a 400 from Meta plus — if the clashing name was ever an approved template that got deleted — a 30-day block
  (§3.3). A unique index enforces that before the Graph call; a jsonb blob cannot.
- **Revision history comes free, with no new table.** The polymorphic `audits` table already exists with
  `auditable_type/auditable_id/version/audited_changes` (`db/schema.rb:264-288`), and the repo already applies the
  `audited` pattern through Enterprise overlay models (`enterprise/app/models/enterprise/audit/inbox.rb`,
  `.../webhook.rb`, `.../team.rb`). Making the new record audited is a model-level change in the enterprise tree. A jsonb
  blob cannot be audited per template. Note the boundary: this gives **local draft** history. Meta-side version history
  remains **DO NOT CREATE** — Meta exposes none **(V)**.
- **It is sparse.** One row per *Lynomia-managed* template, not per Meta template. An account that never opens the
  starter gallery has zero rows and is bit-for-bit unchanged. A blob column lands on every WhatsApp channel.

### 2.4 What must stay in the jsonb

The Meta mirror stays where it is, unchanged, because five independent readers depend on it and none of them should be
rewritten for this program:

| Reader | path:line |
|---|---|
| `Whatsapp::TemplateProcessorService#find_template` — the send gate | `app/services/whatsapp/template_processor_service.rb:21-27` |
| `Flows::Template` — flow node resolution and `sendable?` | `custom/app/services/flows/template.rb:16-36` |
| `Whatsapp::ContactInfoRequestEligibilityService` | `app/services/whatsapp/contact_info_request_eligibility_service.rb:105-107` |
| `getFilteredWhatsAppTemplates` — composer, New Conversation, campaign form | `app/javascript/dashboard/store/modules/inboxes.js:53-73` |
| Inbox serializer | `app/views/api/v1/models/_inbox.json.jbuilder:144-146` |

### 2.5 The migration requirement — for approval, not designed here

A new table is required, keyed on the WhatsApp channel, holding at minimum: the Lynomia state (draft / submitted /
mirrored), `name`, `language`, the Meta template id once assigned, the authored component tree for a draft, the starter
provenance key, `submitted_at`, the last observed Meta status and rejection reason, and an edit timestamp for R6. Unique
on `(channel_id, name, language)`. **Not proposed, not sketched further.** Two existing conventions it must match:
`account_id`-scoped tenancy like every other WhatsApp object, and the `channel_whatsapp` global uniqueness posture
(`db/schema.rb:806`) does **not** apply here — template names are unique per WABA, not per installation.

One pre-existing wart the migration should not inherit: `message_templates` has a jsonb default of `{}` (a Hash) while
every writer stores an Array (`db/schema.rb:800` vs `whatsapp_cloud_service.rb:43`) — 04 §2.2.

---

## 3. Which UI controls are permitted to exist at all

| Control | Meta | Permitted in Lynomia | What the UI must do |
|---|---|---|---|
| **Create / submit for approval** | SUPPORTED — `POST /{WABA_ID}/message_templates`, 100 creates/WABA/hour, 250 templates (6,000 if the portfolio is verified) | **YES** | Submit the full component tree with examples. Show "submitted for Meta review", never "created". Never show an approval ETA. |
| **Edit** | **CONDITIONAL** — only `APPROVED`, `REJECTED`, `PAUSED`; editable fields only `category`, `components`, `message_send_ttl_seconds` **(V)**; components replaced **wholesale**; category of an approved template **not** editable; 1/24h and 10/30d on approved, unlimited on rejected/paused | **YES, gated** | §3.2 |
| **Delete** | SUPPORTED — by `name` (all languages), `hsm_id`, `hsm_ids` | **YES, with a blocking confirmation** | §3.3 |
| **Request category review / appeal** | **NOT available via API** — "A review can only be requested via WhatsApp Manager" **(V)** | **NO** | §3.4 — the UI must *say so* and deep-link, not offer a button that fakes it |
| **Duplicate / new version** | NOT_SUPPORTED by Meta **(V)** | **NO as a Meta operation.** A "start a new draft from this one" action is fine, provided it is unmistakably a new `(name, language)` create | Never use the words "version" or "duplicate" for something that becomes a separate Meta template |
| **Change category of an approved template** | Explicitly prohibited **(V)** | **NO** | Category control read-only when status is APPROVED; editable when REJECTED or PAUSED |
| **Pause / unpause / archive** | Meta-initiated only; no API verb in the proof | **NO** | Render the state, explain it, offer nothing |
| **Edit a template Lynomia did not create** | Meta permits it | **YES** — same rules | No special case; the gate is Meta status, not provenance |

### 3.1 Create

The only create call in the repo today is CSAT-shaped: `category` hardcoded `UTILITY`, one BODY, one URL button, one
fixed `example: ['12345']` (`app/services/whatsapp/csat_template_service.rb:5,70-96,99-103`). A generic submit is a new
service beside it — **EXTEND**, not a rewrite — reusing three things verbatim:

- `channel.template_access_token` (`app/models/channel/whatsapp.rb:84-88`) for auth,
- `business_account_path` for the URL — **after** the v14.0 pin is fixed (04 §5.1); submitting a template through an
  expired Graph version is not acceptable,
- `parse_whatsapp_error` (`app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb:115-128`), which already
  surfaces Meta's `error_user_msg` / `code` / `subcode` to the dashboard. Every new control in this section should
  surface Meta's own message rather than a Lynomia paraphrase.

Two things the create form must own, because Meta requires them and the repo has never produced them (04 §4.3):

- **Examples wherever a component carries a parameter** — `body_text` / `body_text_named_params`, `header_text` /
  `header_text_named_params`, button `example`. Validate client-side *and* server-side; a submit missing an example is a
  Meta rejection, not a Lynomia error.
- **Media headers require `header_handle`, which the repo cannot produce.** `Whatsapp::MediaUploadService` is wired only
  into `send_attachment_message` (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:188-195`), and template
  media is always sent as a public `link` (`app/services/whatsapp/populate_template_parameters_service.rb:33-40`).
  **Decision: phase 2 creates TEXT-header, body, footer, and URL/COPY_CODE/QUICK_REPLY button templates only.** Media
  headers are out until the upload-handle flow exists. The form must not offer a media header it cannot submit.

### 3.2 Edit — the conditionality, made concrete

Four independent rules, all enforced before the Graph call, none of them optional:

1. **Status gate.** The Edit control is enabled only when the mirrored status is `APPROVED`, `REJECTED` or `PAUSED`. For
   `PENDING`, `IN_APPEAL`, `PENDING_DELETION`, `DELETED`, `DISABLED` or `LIMIT_EXCEEDED` it is disabled *with the reason
   shown*. Note the mirrored status can be up to three hours stale (§4), so the gate is advisory client-side and must be
   re-checked server-side against a fresh single-template read.
2. **Wholesale replacement.** "You cannot edit individual template components; the API replaces all components with those
   in the edit request payload" **(V)**. The editor is therefore a **full-template form pre-filled from the mirror** —
   never an inline per-field edit, never a partial PATCH. If the mirror is stale, a save silently reverts whatever
   changed at Meta in the meantime. That risk is why §4 recommends a forced single-template refresh immediately before
   opening the editor.
3. **Category lock.** Read-only when APPROVED **(V)**. Editable for REJECTED/PAUSED, with the warning that a successful
   category edit re-triggers both category validation and template review.
4. **Budget honesty.** 1 edit/24h and 10/30d on approved **(V)**. Lynomia can count only the edits *it* made (R6) — an
   edit made in WhatsApp Manager, which the product's own copy instructs admins to use
   (`app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json:4`), consumes budget invisibly because
   `message_template_components_update` is not subscribed (04 §4.1). **Do not build a counter that claims to know the
   remaining budget.** State the limit as copy, warn when Lynomia's own count is at the edge, and let Meta's error be the
   authority. Whether Meta exposes a remaining-edit count on any read is **UNVERIFIED**.

The narrowest justified first use of this endpoint is the one 04 §5.2 already identified: replacing the CSAT
delete-then-recreate path with a `components` edit. That is a bug fix with a known blast radius, not a feature.

### 3.3 Delete — permitted, with a consequence that must be in the dialog

> "If you delete an approved template, you cannot create a new template with the same name for 30 days." **(V)**

The confirmation dialog must state that consequence in those terms, and must state that deleting by `name` removes
**every language variant** — which is how the repo's one delete call already behaves
(`app/services/whatsapp/csat_template_service.rb:21-28`). Prefer `hsm_id` for a single-language delete; the repo uses
neither `hsm_id` nor `hsm_ids` today (04 table row 5).

This is also the constraint that makes `CsatTemplateNameService.generate_next_template_name`
(`app/services/csat_template_name_service.rb:19-25`) correct rather than odd: it mints
`customer_satisfaction_survey_<inbox>_<n+1>` precisely to avoid the block **(V)**. Any new delete-and-resubmit path must
follow the same discipline, and the new record's unique `(channel_id, name, language)` index (§2.3) should retain a
tombstone so the UI can refuse to reuse a recently deleted name rather than discovering the block from a Meta error.

### 3.4 Category review — the UI must say it, not offer it

Meta: a category review can only be requested in WhatsApp Manager **(V)**. So the preview drawer for a REJECTED or
recategorised template must carry a short line of copy saying category review is not available from Lynomia, plus the
existing deep link (`.../templates/TemplatePreviewDrawer.vue:28-29` →
`business.facebook.com/latest/whatsapp_manager/message_templates`). A disabled "Request review" button is worse than no
button: it implies the capability exists and is merely unavailable right now.

---

## 4. Status sync — what the missing route implies, and the honest interim

**Finding (04 §4.1, unchanged here): Meta delivers template lifecycle on the `whatsapp_business_account` object through
`message_template_status_update` and three siblings, these four fields do not honour callback overrides **(V)**, and the
repo's only Meta webhook route is `post 'webhooks/whatsapp/:phone_number'` (`config/routes.rb:678-679`) — which is
exactly the phone-level override `WebhookSetupService` configures (`:105-110`).**

What that implies, precisely:

1. **Subscribing is not the work.** Adding the field to `WEBHOOK_DEFAULT_FIELDS`
   (`app/services/whatsapp/facebook_api_client.rb:4`) and `subscribed_fields`
   (`app/services/whatsapp/webhook_setup_service.rb:85-89`) is two lines, and would deliver the payload to **an endpoint
   that does not exist**. Doing it first produces silent loss, not partial value.
2. **The new endpoint is app-scoped, not inbox-scoped.** One callback for the whole Meta app, carrying no phone number.
   Its signature verification can reuse `MetaTokenVerifyConcern` (`app/controllers/concerns/meta_token_verify_concern.rb:1-73`)
   against `GlobalConfigService.load('WHATSAPP_APP_SECRET')` — the same source
   `Webhooks::WhatsappController` already uses (`app/controllers/webhooks/whatsapp_controller.rb:37`).
3. **Tenant resolution is the open problem.** The payload identifies the template by `message_template_id` /
   `message_template_name` / `message_template_language` and the entry by WABA id. Today there is no local per-template
   record to resolve an id against; the nearest resolvable key is `provider_config['business_account_id']`, which is
   stored per channel and materialized by the health service
   (`app/services/whatsapp/health_service.rb` persists `business_account_id` into `phone_number_health`). Whether WABA id
   alone is sufficient and unambiguous across channels is **UNVERIFIED** and must be answered before the route is built.
   **This is a second reason the per-template record (§2) should land before the webhook, not after.**

**The honest interim is manual refresh plus the existing 3-hourly job — and yes, it is honest, provided the UI stops
implying freshness.** Three parts:

- **Keep the 3-hourly scheduler as the background floor.** `templates_sync_scheduler_job.rb:5-13`, unchanged.
- **Add a single-template refresh.** `GET /{TEMPLATE_ID}` is supported by Meta and never called by the repo (04 table
  row 2); the repo already has the narrower `?name=` precedent at `csat_template_service.rb:30-48`. A per-template
  "Check status now" is **EXTEND**, is the natural control on a just-submitted draft, and is what §3.2 rule 2 requires
  before opening the editor. It must be rate-limited per template; a submitted draft does not need polling every few
  seconds while an admin stares at it.
- **Say the age out loud.** The read endpoint already returns `meta.last_sync_attempt_at`
  (`app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:19-31`) and the page already renders
  `LAST_SYNC_ATTEMPT` (`whatsappTemplateMgmt.json:19`). On a submitted-but-not-approved draft the surface must show the
  observation time next to the status, not a bare badge.

What the interim does **not** cover, and must not be claimed to: a Meta-initiated recategorisation to AUTHENTICATION
flips two hard send gates with up to three hours of silence (`app/services/whatsapp/authentication_template_guard.rb:16-18`,
`custom/app/services/flows/template.rb:32`), and an edit made in WhatsApp Manager is invisible for the same window. Those
are the arguments for eventually building the route — not for pretending polling solves them.

---

## 5. Starter template gallery (brief §3.6)

**Classification: REUSE for the mechanics, NEW PRIMITIVE REQUIRED for the state it produces.** The gallery itself is not
new work; what it produces is.

### 5.1 Reuse the recipe architecture exactly as written

`app/javascript/dashboard/recipes/index.js:1-23` already defines the contract, and its first paragraph is the governing
principle: *"A recipe is a ready-made configuration for an object the product already has… It is source code, not a
record… created through the same APIs, the same policies and the same server-side validation as a hand-built object."*
The pieces to reuse:

| Piece | path:line | Use |
|---|---|---|
| Manifest contract (`id`, `type`, `version`, `name`, `description`, `category`, `requires`, `inputs`, `build`) | `app/javascript/dashboard/recipes/index.js:9-23` | add `type: 'whatsapp_template'`; `build` returns the create payload |
| `CATEGORIES` / `REQUIREMENTS` / `INPUT_TYPES` | `.../recipes/index.js:25-31,34-45,48-60` | a template starter needs a new `REQUIREMENTS` key for "a WhatsApp Cloud inbox exists" |
| `RecipeDialog.vue`, `RecipeInputs.vue` | `app/javascript/dashboard/components-next/recipes/` | the wizard, unchanged |
| Bilingual curated copy | `app/javascript/dashboard/recipes/starterCopy.js:1-6` | hand-written AR/EN, never machine-translated — the same rule applies to template bodies |
| Host pattern | `.../settings/flows/Index.vue:18-19,130` | Settings → Templates gets the same treatment |

**Where the analogy breaks, and it matters.** For a flow or an automation, `build`'s output goes straight to an existing
create API and the result is an ordinary local object. For a template there is **no generic create API and no local
record** — which is exactly why §2's primitive is a prerequisite for this gallery and not an optional nicety. A starter
that cannot be saved as a draft can only be "submit to Meta immediately, unedited", which contradicts the brief's own
requirement that starters be editable drafts.

### 5.2 The vocabulary, fixed

Three states, three distinct words, never interchangeable:

| State | Meaning | Where it lives | Can it be sent? |
|---|---|---|---|
| **Lynomia starter** | catalogue entry in source code; not an object at all | `dashboard/recipes/*` | No — it is not a template yet |
| **Draft** | a starter the admin has instantiated and may edit; never seen by Meta | the new record (§2) | **No** |
| **Submitted** | sent to Meta; status is whatever Meta last said | new record + Meta mirror once Meta returns it | Only at `APPROVED`, via the existing gate |

Rules the UI must hold, each of which is testable:

- A draft card carries an explicit **"Lynomia starter — not submitted to WhatsApp"** label and must not render the Meta
  status badge at all. The badge palette is approved/pending/rejected/paused/disabled
  (`templates/templateUtils.js:121-131`) and an unknown value falls through to a neutral grey (`:131`) — a draft rendered
  through that path reads as a real-but-unremarkable Meta state. That is precisely the misleading outcome to avoid.
- The words "approved", "pending" and "live" are reserved for values that came from Meta. A draft is "draft"; a
  submission is "submitted for review".
- Starter and Meta templates are never merged into one undifferentiated list. Either separate sections, or a provenance
  column that is always visible — never a filter the user has to discover.
- There is already a precedent for a non-Meta state in this UI: Twilio's `unsubmitted`, handled as its own label outside
  the tone map (`TemplateCard.vue:29-30`, `TemplatePreviewDrawer.vue:59-60`, copy at `whatsappTemplateMgmt.json:21-23`).
  Follow that pattern rather than inventing a second one.

### 5.3 The structural guarantee, not just a UI rule

A draft is unsendable because of where it is stored, not because a component hides it. All four send-side readers take
their list from `channel_whatsapp.message_templates` (§2.4) and filter on `status == 'approved'`
(`template_processor_service.rb:25`, `inboxes.js:72` via `isSendableTemplate`, `flows/template.rb:26`,
`contact_info_request_eligibility_service.rb:110`). A draft that never enters that column cannot be selected in the
composer, cannot be chosen in a campaign, cannot be referenced by a published flow, and cannot be sent by the API.

**Therefore: the new management endpoint must be a separate, administrator-gated endpoint, and drafts must never be
returned by `GET /inboxes/:id/message_templates`.** That existing endpoint is readable by **any account user** —
`InboxPolicy#message_templates?` returns `true` unconditionally (`app/policies/inbox_policy.rb:37`) — so returning drafts
there would both break the guarantee and expose unapproved drafts to agents. The new surface follows
`sync_templates?` (`app/policies/inbox_policy.rb:65`) and the existing route meta
(`templates/templates.routes.js:16-18`, `permissions: ['administrator']`).

---

## 6. Commerce-aware variables (brief §3.7)

**Rule: a variable may be offered only if some producer in the repo can fill it for the context the template will be sent
in. `PopulateTemplateParametersService` and `TemplateProcessorService` decide the *shape* a value may take; the
*source* of the value is decided by the composer, the campaign Liquid drops, or the flow run.** Both halves must hold.

### 6.1 Shapes the send pipeline can emit

| Shape | Builder | path:line |
|---|---|---|
| Positional text | `build_parameter` → `build_string_parameter` | `populate_template_parameters_service.rb:2-11,49-56` |
| Named text (`parameter_name`) — only when `parameter_format == 'NAMED'` | `build_named_parameter`, selected at `template_processor_service.rb:94-98` | `populate_template_parameters_service.rb:42-45` |
| Media header by **public http(s) link**, ≤2000 chars, image/video/document | `build_media_parameter` | `.../populate_template_parameters_service.rb:33-40,93-119` |
| URL button parameter (text) | `build_button_parameter` else-branch | `.../populate_template_parameters_service.rb:26-30` |
| `copy_code` button, ≤15 chars, raises on empty or over-length | `build_button_parameter` | `.../populate_template_parameters_service.rb:16-25` |

All text is sanitized — `<>"'` stripped and truncated to 1000 chars — before it reaches Meta.

### 6.2 Sources that can actually fill them

| Send context | Resolver | Variables that resolve |
|---|---|---|
| Composer / New Conversation | agent types the value in `WhatsAppTemplateParser.vue` | anything typed; **no automatic commerce data** |
| Campaign | `Whatsapp::LiquidTemplateProcessorService#drops` (`app/services/whatsapp/liquid_template_processor_service.rb:37-44`) — exactly four drops | `contact.{name, first_name, last_name, email, phone_number, custom_attribute.<key>}` (`app/drops/contact_drop.rb:1-26`); `agent.{name, available_name, email, first_name, last_name}` (`app/drops/user_drop.rb`); `inbox.{name, business_name, avatar_url, email}` (`app/drops/inbox_drop.rb`); `account.name` (`app/drops/account_drop.rb`) |
| Any message-level Liquid | `Liquidable#drops` (`app/models/concerns/liquidable.rb:14-18`) | the above **plus** `conversation.{id, display_id, contact_name, custom_attribute.<key>}` (`app/drops/conversation_drop.rb:1-29`) |
| Flow `send_template` node | `Flows::Variables` (`custom/app/services/flows/variables.rb:14-40`) | the Chatwoot set at `:16-17`, plus `flow.reply`, `flow.<key>` stored by a Question, plus **`flow.order.{number, status, payment_status, tracking_number, tracking_url}`** (`:18`) |

**The commerce answer, stated plainly: the only commerce-aware template variables that resolve anywhere in this product
are those five `flow.order.*` fields, and only inside a flow run in which a Commerce Lookup node has already found an
order.** They are populated by `custom/app/services/flows/nodes/commerce_lookup.rb:64-70`, which writes
`order → {number, status, payment_status, tracking_number, tracking_url}` into the run context, and they are the set the
builder's picker already advertises (`custom/app/services/flows/variables.rb:23-24`).

So the template manager's variable picker must be **context-aware**: offer `flow.order.*` when the template is being
authored for flow use, and not offer it in the campaign or composer path, where nothing can fill it.

### 6.3 What must not be offered, with the reason

| Not offered | Reason |
|---|---|
| `currency` and `date_time` parameters | `PopulateTemplateParametersService` can build them (`:69-91`), but **no producer anywhere emits the required hash** — `grep` for `amount_1000` / `fallback_value` across `app`, `custom` and `app/javascript` returns only the builder itself and the renderer that reads `fallback_value` (`app/services/whatsapp/template_content_renderer_service.rb:44`). The documented public contract types body params as plain strings (`swagger/definitions/request/campaign/whatsapp_template_params.yml:27-30`). Offering them would ship a control nothing can populate. **DO NOT CREATE** |
| `order.*` in a **campaign** template | There is no `OrderDrop`. `app/drops/` holds exactly seven drops — account, base, contact, conversation, inbox, message, user — and the campaign renderer injects only four of them (`liquid_template_processor_service.rb:37-44`). A campaign template with `{{ order.number }}` renders blank, and a blank Liquid render causes `LiquidTemplateProcessorService` to return `nil`, which **skips the recipient silently** (`:21`). This is an actively harmful variable to offer. **DO NOT CREATE** |
| Cart / abandoned-cart variables | There is no cart table anywhere in `db/schema.rb`; a cart is a `Data.define` cached in Redis only, and the cache is deleted rather than staled on provider webhooks (verified independently by the `abandoned-cart` verifier). Nothing can resolve a cart variable at send time, in any context. **DO NOT CREATE** |
| Media header variables in phase 2 | §3.1 — no `header_handle` upload exists, so the template cannot be *created* with a media header even though it can be *sent* with one |
| `LIST`, `PRODUCT`, `CATALOG`, `CALL_PERMISSION_REQUEST` components; `LOCATION` headers | Already refused on the send side (`custom/app/services/flows/template.rb:11,34`). Authoring something the product then refuses to send is a trap. **DO NOT CREATE** |

### 6.4 One correctness note the authoring form inherits

`TemplateNormalizer.extractWhatsAppVariables` keys variables in a single flat map by raw token across all components
(`app/javascript/dashboard/services/TemplateNormalizer.js:63-85`), so a POSITIONAL template with both a header `{{1}}`
and a body `{{1}}` collapses into one entry, and TEXT-header examples are read from body-shaped keys (04 §5.3). An
authoring form built on this normalizer inherits both bugs. **Fix 04 §5.3 before building the form**, not after.

---

## 7. Security (brief §12)

**No secret changes hands. The new surface uses the paths that already exist, server-side only.**

| Secret | Where it lives | Reaches the browser? |
|---|---|---|
| Per-inbox `api_key`, `verification_pin`, `app_secret`, `app_secret_key`, `client_secret`, `api_secret` | `provider_config` jsonb, listed in `Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS` (`app/models/channel/whatsapp.rb:32`) | **No** — stripped at `app/views/api/v1/models/_inbox.json.jbuilder:148`, and the rest of `provider_config` is admin-only (`:147-149`) |
| `business_management_token` | encrypted column (`app/models/channel/whatsapp.rb:33`) | **No** — `serializable_hash` strips it (`:90-92`); only the boolean `business_management_token_configured` is exposed (`_inbox.json.jbuilder:150-154`) |
| `WHATSAPP_APP_SECRET` | `InstallationConfig`, `type: secret`, read via `GlobalConfigService` (`app/services/whatsapp/facebook_api_client.rb:16,213`, `app/controllers/webhooks/whatsapp_controller.rb:37`) | **No** |
| `WHATSAPP_APP_ID`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_API_VERSION` | same store, edited under the `whatsapp_embedded` group (`app/controllers/super_admin/app_configs_controller.rb:82`) | Yes, by design (`app/views/layouts/vueapp.html.erb:45-47`) |

Rules for every new control in this document:

1. **The token for a template write is resolved server-side, per channel, by the method that already does it** —
   `Channel::Whatsapp#template_access_token` (`:84-88`), which prefers the encrypted `business_management_token` on
   Chatwoot Cloud embedded-signup channels and otherwise uses `provider_config['api_key']`. No new credential, no new
   storage location, nothing in the new record.
2. **No Graph call is ever issued from the browser.** The dashboard calls Lynomia; Lynomia calls Meta. This is already
   how every template call works (04 §3's seven-row ledger) and the new surface must not be the exception.
3. **Meta errors are surfaced through the existing parser** (`inbox_csat_templates_controller.rb:115-128`), which reads
   `error_user_msg` / `message` / `code` / `subcode`. Do not render a raw response body — `csat_template_service.rb:116`
   already logs `response.body` server-side, which is the right place for it.
4. **Administrator-only, server-enforced.** New endpoints follow `InboxPolicy#sync_templates?`
   (`app/policies/inbox_policy.rb:65`) and the route carries `meta: { permissions: ['administrator'] }` like
   `templates.routes.js:16-18`. The frontend gate is `usePolicy().shouldShow(...)`; it is a convenience, never the
   enforcement.
5. **Starter content is source code, not user input** (`dashboard/recipes/index.js:4`), so the gallery adds no injection
   surface. Values that *are* user- or store-derived are already sanitized twice: `Flows::Variables.safe` strips `{{`,
   `}}`, `{%`, `%}` and truncates to 1024 (`custom/app/services/flows/variables.rb:56`), and
   `PopulateTemplateParametersService` strips `<>"'` and truncates to 1000 before the Graph call.
6. **Tenancy is unchanged**: every WhatsApp object hangs off `account_id`, and `Flows::TemplateValidator` already refuses
   to resolve a template outside the account's own inboxes (`custom/app/services/flows/template_validator.rb:33-35`). The
   new record must be reachable only through `Current.account`.

---

## 8. Phasing

| Phase | Contents | Classification | Gate to start |
|---|---|---|---|
| **0 — Prerequisites** | The v14.0 Graph pin (`whatsapp_cloud_service.rb:124-126`, `csat_template_service.rb:4`); `TemplateNormalizer` header examples + the flat-map collision (04 §5.3); send-path fail-closed (04 §2.5); delete the dead `create_csat_template` / `delete_csat_template` wrappers (`whatsapp_cloud_service.rb:82-89`) | **PATCH** | none — the v14.0 pin's timer is held by Meta, not by us |
| **1 — Read-side truth** | Surface `rejected_reason` in the preview drawer (04 §4.2); badge coverage for IN_APPEAL / ARCHIVED / PENDING_DELETION / DELETED / LIMIT_EXCEEDED (`templateUtils.js:121-131`); show observation age beside status; single-template "Check status now" via `GET /{TEMPLATE_ID}` | **PATCH** + one **EXTEND** | phase 0 |
| **2 — The primitive and the gallery** | The per-template record (**migration — for approval**); starter catalogue as a new recipe type; draft create/edit/delete locally; submit via generic `POST /{WABA}/message_templates`; TEXT-header / body / footer / button templates only | **NEW PRIMITIVE REQUIRED** + **EXTEND** | migration approved; phase 1 shipped, because a submitted draft is unusable without status truth |
| **3 — Narrow Meta edit** | CSAT delete-then-recreate replaced by a `components` edit (04 §5.2); then the general edit form under §3.2's four rules | **EXTEND** | phase 2 shipped; a forced single-template refresh exists (§4) |
| **4 — Push status** | App-default `whatsapp_business_account` callback route, signature verification, dispatcher branch, then the field subscription | **NEW PRIMITIVE REQUIRED** | phase 2 shipped (tenant resolution needs the record), and §4 item 3 answered |

Phases 0 and 1 are worth doing whether or not the manager is ever built. Phase 2 is the decision point: it is the first
phase that needs a migration and the first that creates state the product must then maintain.

---

## 9. Not worth building

| Item | Why not |
|---|---|
| Another WhatsApp provider / template-gateway abstraction | Two providers exist and one of them (360dialog) has no UI entry point at all (04 §2.1). `provider_service` delegation (`app/models/channel/whatsapp.rb:146-150`) is already the extension point. Adding a layer above it adds indirection and no capability |
| Template Library create (`library_template_name`) | Only valuable alongside general authoring, and the starter gallery (§5) delivers the same product outcome — curated, pre-written templates — in Lynomia's own copy and languages, under our own version control |
| Per-template analytics | No code requests Meta's analytics edges; campaign analytics are per `CampaignRecipient`. A separate product decision, not a template-management gap |
| A remaining-edit-budget counter | §3.2 rule 4 — Lynomia cannot see edits made in WhatsApp Manager, so any counter is wrong in exactly the situation where it matters |
| Template quality surfacing | `quality_score` appears nowhere in the repo **(V)**, and the only quality data the product reads is per phone number (`app/services/whatsapp/health_service.rb:25,39,151,226`). Adding it means subscribing `message_template_quality_update` — i.e. phase 4 first |
| Mirroring Meta's pacing / archival states as actionable UI | Meta offers no verb for either; the honest change is explanatory copy on the existing badges, which is phase 1 |
| Rebuilding the Settings → Templates list | It already fans the read across inboxes, dedupes, filters and previews. Extend it; do not replace it |

---

## 10. Telemetry, for the record

There are **zero** tracking calls on any recipe, starter or template path today, so "how many admins used a starter" is
unanswerable now and will stay unanswerable unless the gallery is instrumented when it ships. The mechanism exists but is
inert by default: `useTrack` is a nine-line try/catch wrapper (`app/javascript/dashboard/composables/index.js:7-15`) over
a singleton built from `window.analyticsConfig`, which the layout emits only when the `CLOUD_ANALYTICS_TOKEN`
`InstallationConfig` is present (`app/views/layouts/vueapp.html.erb:68-71`, `config/installation_config.yml:299`). With
no token every call site is a no-op. **Do not promise adoption reporting as part of phase 2**; the instrumentation is
cheap, the data pipeline is an installation-level decision that is not ours to make here.

---

## 11. Open questions and UNVERIFIED items

1. Whether a single Meta app-default callback can be resolved to the right tenant from the template webhook payload plus
   `provider_config['business_account_id']`, and whether one WABA can map to more than one channel in a way that makes
   that ambiguous (§4 item 3). **Blocks phase 4.**
2. Whether Meta exposes a remaining-edit count on any read, which would turn §3.2 rule 4's warning into a fact.
3. The exact default field projection of `GET /{WABA}/message_templates` once the Graph version moves off v14.0 — the
   stored shape is whatever that version returns (04 §2.3), so the pin fix in phase 0 can change what the mirror holds.
4. Whether any existing account has a non-empty Hash in `channel_whatsapp.message_templates` (the column's default is
   `{}` while every writer stores an Array, `db/schema.rb:800`). Cheap to answer with a query; worth answering before
   anything new reads that column alongside a new record.
5. No test suite was run and the app was not launched for this document. Every repo claim is a static read of the cited
   path:line at HEAD `6c381e96`.
