---
agent: 053
scope: corpus section `whatsapp` (6 articles x EN/AR) - classification, accuracy against code, register of Meta assertions the repository cannot verify
confidence: high
---

# 053 - Corpus: the `whatsapp` section

Read-only. Repository at HEAD `b21f0aaf` (branch `claude/documentation-v2`). "EN L38" means line 38 of
`custom/db/documentation/en/whatsapp/<key>.md`; "AR L39" the same for `ar/`. Code citations are `path:line`.
`confidence: high` covers **repository findings only**. Nothing here was checked against Meta's own pages: §3.2 is the
list of Meta assertions for agents 001-028, deliberately not resolved.

Measurement warning for other corpus agents: `wc -w` under-counts Arabic here by roughly 3.5x (268 vs 950 words for AR
`connect-whatsapp`). Counts below are `body.split()` in Python, front matter excluded.

**What matters most, in order.**

1. The lifecycle article (EN L54, L81; AR L54, L79) and its worked example promise that Lynomia Chat "warns you before
   you save" an edit to an approved template. The warning copy exists (`whatsappTemplateMgmt.json:82-86`,
   `CONFIRM.EDIT_APPROVED`) but **no Vue or JS file references it** - the builder's `save()` calls the API directly
   (`TemplateBuilderDialog.vue:288-300`; `Index.vue:397-408` registers only `submit` and `delete` confirmations). Either
   the product or the article is wrong; the article is wrong as shipped.
2. The 24-hour article says a window-closed message appears "with WhatsApp's own explanation underneath". It is
   Lynomia's own pre-flight refusal, written before Meta is called, in different words from the quoted line, in English
   even for Arabic users, and a flow cannot produce it at all.
3. The coexistence article says deleting the inbox "releases the number from the Meta app". The repository's own Meta
   verification record says the opposite for these numbers (`docs/whatsapp-business/META-VERIFICATION.md` item 12).
4. Every one of the 53 internal links in each Arabic article is a bare English key, so an Arabic reader following any
   link lands on the **English** article (`routes.rb:519` carries no locale; `articles_controller.rb:81-83` finds by slug
   alone; Arabic slugs end `-ar`, `content_seeder.rb:85-87`). Corpus-wide, not only in this section.
5. Template-manager behaviour was never exercised against real Meta (`docs/whatsapp-template-manager/11-real-meta-uat.md`
   "REAL META UAT BLOCKED"; same for coexistence: `docs/whatsapp-business/README.md:3`). Every lifecycle outcome the
   articles state as fact ("approved in minutes", "one change every 24 hours") is a reading of Meta's documentation,
   not an observation.

## 1. Inventory

| Key | EN file | AR file | EN title | AR title | Position | EN words | AR words |
|---|---|---|---|---|---|---|---|
| `connect-whatsapp` | `en/whatsapp/connect-whatsapp.md` | `ar/whatsapp/connect-whatsapp.md` | Connect a WhatsApp number | ربط رقم واتساب | 10 | 1193 | 950 |
| `whatsapp-business-coexistence` | `en/whatsapp/whatsapp-business-coexistence.md` | `ar/whatsapp/whatsapp-business-coexistence.md` | The WhatsApp Business app and Lynomia Chat on one number | تطبيق WhatsApp Business ولينوميا تشات على رقم واحد | 20 | 988 | 780 |
| `the-whatsapp-24-hour-window` | `en/whatsapp/the-whatsapp-24-hour-window.md` | `ar/whatsapp/the-whatsapp-24-hour-window.md` | The WhatsApp 24-hour window | نافذة الـ24 ساعة في واتساب | 30 | 867 | 686 |
| `whatsapp-templates` | `en/whatsapp/whatsapp-templates.md` | `ar/whatsapp/whatsapp-templates.md` | WhatsApp templates | قوالب واتساب | 40 | 1327 | 1108 |
| `whatsapp-template-lifecycle` | `en/whatsapp/whatsapp-template-lifecycle.md` | `ar/whatsapp/whatsapp-template-lifecycle.md` | The template lifecycle | دورة حياة القالب | 50 | 1178 | 956 |
| `whatsapp-troubleshooting` | `en/whatsapp/whatsapp-troubleshooting.md` | `ar/whatsapp/whatsapp-troubleshooting.md` | When WhatsApp does not work | حين لا يعمل واتساب | 60 | 1223 | 997 |

Section totals: 6 + 6 files, 6,776 EN and 5,477 AR body words. Manifest entry: `manifest.yml:47-55` (slug `whatsapp`,
position 50). All six keys are in the product registry (`documentationLinks.js:35-40`). Zero images, zero external links in
the whole section (`grep '!\['` and `grep http` return nothing): no claim links to the Meta page it rests on.

## 2. Per-article verdict

The verdict names the **structural** action. Claim-level corrections (§3.1) are required regardless of the verdict; an
article marked KEEP is KEEP only after them.

| Key | Verdict | Reason | Evidence |
|---|---|---|---|
| `connect-whatsapp` | **SPLIT** (after correcting C-04, C-05, C-10) | One article carries three jobs - the WABA/prerequisite concept, a route chooser, and the steps for two routes - and a fourth route (Twilio) has no steps at all. The manual route is a 5-step wizard with its own error vocabulary that the article compresses into one sentence. | C-03, C-05; `WhatsappManualSetup.vue:24`; 039 section 9 items 6-7; `docs/global-documentation/04-karzoun-doc-map.md:42` ("all four top articles are about WhatsApp prerequisites") |
| `whatsapp-business-coexistence` | **REWRITE** | Wrong on deletion/offboarding, carries an unverifiable claim about the phone ("including to the phone"), embeds internal release status that will rot, and uses the word "Coexistence" the product rule forbids in user-facing copy. | C-14, C-15, M-10, M-14, section 3.3 |
| `the-whatsapp-24-hour-window` | **KEEP** (after C-20, C-21, C-22, C-24, C-24b) | The rule, the clock and the structure are right and the best-organised article in the section; the defects are two table cells, two quoted strings and one overstated comparison. | C-17..C-24b |
| `whatsapp-templates` | **EXPAND** (after C-26, C-28..C-34) | Authoring is well covered; sending a template (the agent job) is covered by one sentence, and five claims need correcting (AUTHENTICATION, carousel/LTO "sent", media handle, header edge rule, preview renderer). | C-26, C-28..C-34, section 4 item 1 |
| `whatsapp-template-lifecycle` | **KEEP** (after C-35..C-40) | The state table matches `Actions` exactly and is the strongest content here; one promised UI behaviour does not exist, one claim is contradicted by the audit log article, and the 30-day block is stated more broadly than the repo's own contract states it. | C-35..C-40, C-43 |
| `whatsapp-troubleshooting` | **REWRITE as a symptom router; RELOCATE its rejection section** | "A number is not connected" and the Sunday worked example duplicate `whatsapp-errors/whatsapp-nothing-arrives`, `-reconnect-a-number`, `-number-status`; "A message did not send" duplicates `-find-a-failed-message`. The key is wired into the product as the fallback "learn more" (`MessageError.vue:73-76`), so it cannot be retired. | C-43..C-49, DC-08 |

## 3. Accuracy against the product

### 3.1 Claims checked against code

Verdicts: **confirmed**, **wrong**, **partly wrong**, **unverifiable** (needs Meta, a live install, or a decision).

**Connect (`connect-whatsapp.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-01 | L20-24 | Templates belong to the WABA; inboxes on one WABA share them, separate WABAs do not | confirmed | Identity is (account, WABA, name, lower(language)) `message_template.rb:24,108-113`; `channels` by WABA `:98-102`; sending reads each inbox's own synced snapshot `flows/template.rb:16-20` |
| C-02 | L35-37, L106-107 | Business App card shown only when the installation has a Meta app | confirmed | `Whatsapp.vue:48-52,78-80,114-124` (`hasWhatsappAppId`, `canUseEmbeddedSignup`) |
| C-03 | L26 | "Three ways to connect" over a four-row table | partly wrong | The picker has three cards (Cloud, Twilio, Business App) `Whatsapp.vue:98-124`; the Cloud card holds quick and manual. 360dialog still exists in code and has no card (`channel/whatsapp.rb:36`, XA-11) |
| C-04 | L41, L78 | "Every step below is administrator-only ... viewing Account Health" | partly wrong | create/update/sync_templates/register_webhook are admin `inbox_policy.rb:51-57,71-73`, `inbox_health_management.rb:6`. `GET health` drops the class gate `inbox_health_management.rb:5` and keeps only `fetch_inbox`'s membership check `inboxes_controller.rb:87-90`; `InboxPolicy#health?` `:79-81` is never called. Same as DC-17 / 039 |
| C-05 | L55-58 | "Verify details" checks number access, template access, webhook callback and subscription before the inbox is created; four stages | **wrong** | Verify details = `preview` = `manual_setup_validation_service.rb:12-25` (WABA owns the phone id, status, uniqueness, template access, messaging access). Callback and subscription are set up and polled **after** `connect` creates the inbox `manual_setup_controller.rb:11-14,64-73`, `WhatsappManualSetup.vue:262-283`, retry button `inboxMgmt.json:400`. Wizard is 5 steps `WhatsappManualSetup.vue:24` |
| C-06 | L52-54 | Quick setup exchanges server-side; token never in the browser | confirmed | `facebook_api_client.rb:19-30` (per 039) |
| C-07 | L61-62 | Last screen offers a scan code that opens a chat to the new number | confirmed | `FinishSetup.vue:71-73,122-127` (`https://wa.me/<number>`) |
| C-08 | L64-66, L116-117 | Inbox -> Account Health reports display number/name/status, quality, limit, throughput, WABA name and id | confirmed for **Cloud only** | Fields `inboxMgmt.json:932-1015`. The tab exists for `whatsapp_cloud` (`Settings.vue:169-171,249-257`) and, separately, for Twilio **SMS** (`:172-174`); a Twilio **WhatsApp** or 360dialog inbox has no Account Health tab |
| C-09 | L83-84 | A number can be connected once in the whole installation | confirmed | `channel/whatsapp.rb:40` (`uniqueness: true`), `manual_setup_validation_service.rb:57-62` |
| C-10 | L88-89 | Quick setup can be unavailable; the page says so and offers manual setup | partly wrong | Copy exists `inboxMgmt.json:467`, but its gate `isMetaInboxCreationDisabled` is cloud-only (XA-10), so on a self-hosted install the described behaviour cannot occur |
| C-11 | L90-91 | Twilio templates are managed in Twilio; campaigns need a Cloud number | confirmed | `TemplatePreviewDrawer.vue:46-61` ("Manage in Twilio"); `oneoff_campaign_service.rb:27-29` raises `WhatsApp Cloud provider required` |
| C-12 | L92-95 | Quick-setup number released on delete; manual number deliberately left registered | confirmed as an *attempt* | `webhook_teardown_service.rb:43-54` (deregister only for `embedded_signup`), failures logged and swallowed `:14-18,:51-53`. Whether Meta accepts the release is M-06 |
| C-13 | L106-107, L113-114, L116-117 | The three FAQ strings and the "Register Webhook" / "Webhook not configured" labels | confirmed | `inboxMgmt.json:406,434,1087-1088` (EN). In the Arabic UI these are still English (`ar/inboxMgmt.json:407,435,990-991`) |

**Coexistence (`whatsapp-business-coexistence.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-14 | L78-79 | "Deleting the inbox releases the number from the Meta app" | **wrong / contradicted by the repo's own record** | Teardown *calls* deregister for every `embedded_signup` channel, including coexistence (`webhook_teardown_service.rb:43-54`), but `META-VERIFICATION.md` item 12 records Meta's rule that the deregister endpoint cannot be used for a number in use with both Cloud API and the Business app, the error is swallowed, and "offboarding is done from the phone app" |
| C-15 | L16-19 | Built, tested end to end against a simulated Meta in a staging rehearsal; not released to production; two real-Meta steps outstanding | confirmed as of the docs, **time-sensitive** | `docs/whatsapp-business/README.md:3`; `META-VERIFICATION.md` items 14-15 OPEN; `UAT-RUNBOOK` says the real run is BLOCKED. Whether production has changed since is not knowable from the repo |
| C-16a | L35-36 | Phone-typed replies arrive as echoes, matched by message id, never re-sent | confirmed | `incoming_message_base_service.rb:175-190` (type outgoing, status delivered "to prevent SendReplyJob from trying to send them", `external_echo`); dedup per README |
| C-16b | L75-77 | No manual fallback for this route | confirmed | 039 section 10 (`Whatsapp.vue:271-301`) |
| C-16c | L80-81 | Account Health shows a *Coexistence* line when Meta says the number is also on the Business app | confirmed | `AccountHealth.vue:224-230` (`isOnBizApp === true && platformType === 'CLOUD_API'`) |
| C-16d | L54, L63-64 | Needs app >= 2.24.17; linked devices signed out | confirmed *as product copy* | `inboxMgmt.json:461`. The Meta fact is M-11/M-12 |
| C-16e | L9 vs product rule | Article uses "Coexistence" in prose, tags-adjacent SEO text and slug | **conflicts with a stated rule** | `docs/whatsapp-business/README.md:25` and `docs/global-documentation/05-lynomia-capability-doc-map.md:49` say "QR", "Evolution", "Coexistence" must not appear in user-facing copy. The shipped UI itself breaks the rule (`inboxMgmt.json:983` "Coexistence" row, `AccountHealth.vue:225`) - decision for Agent 000 |

**24-hour window (`the-whatsapp-24-hour-window.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-17 | L24-26, L77-78 | Clock = customer's latest message, **per conversation**; resolving changes nothing | confirmed (product); the Meta rule is M-18 | `message_window_service.rb:34-38,67-69` reads `@conversation.messages...incoming`; status is not consulted. `lock_to_single_conversation` defaults false (`db/schema.rb:1423`), so one contact can hold several conversations, each with its own clock |
| C-18 | L27-29 | Nothing the business sends restarts it, including campaigns | confirmed (product) | Only `incoming` messages are read; campaign sends carry no message (`oneoff_campaign_service.rb:83-100`); echoes are stored outgoing (C-16a) |
| C-18b | L35-36, L41 | Composer switched off; attachments and voice notes off; notes still allowed | confirmed | `ReplyBox.vue:517-522,289-292`; `ReplyBottomPanel.vue:176-200`; server refuses any non-template `send_on_whatsapp_service.rb:15-17` |
| C-19 | L38-39 | Campaign sends a template; automation message "is created and then fails" | confirmed | `oneoff_campaign_service.rb:42-59`; `automation_rules/action_service.rb:43-48` has no `can_reply?`, refusal at `send_on_whatsapp_service.rb:15-17` |
| C-20 | L40 | Window closed -> satisfaction survey "not sent" | **partly wrong** | `csat_survey_service.rb:7-15`: a WhatsApp inbox with an approved CSAT template is sent **as a template regardless of the window**; only without one does it fall to `can_reply?` (`:11`), then to a "not sent" activity (`:14`, `:171`) |
| C-21 | L46-48, TS L37-38, L42 | A plain message sent anyway (automation, flow, integration) appears "Failed to send" with **WhatsApp's own explanation**: "the 24-hour customer service window is closed and no template was used" | **wrong in four ways** | (a) Text is Lynomia's, set before Meta is called `send_on_whatsapp_service.rb:17`, `inbound_evidence.rb:124`, `delivery_failure.rb:33-34` ("A localized refusal such as the 24-hour window message carries no code"); (b) real wording is `en.yml:185` "Message not sent because the WhatsApp 24-hour customer service window is closed and no template parameters were provided. Send an approved template message instead."; (c) **a flow never produces it**: `flows/nodes/send_message.rb:5` returns `handed_off / window_closed`, no message is created; (d) Meta's own refusal is a different thing and arrives as `"131047: Re-engagement message"` (`docs/real-whatsapp-uat/06-delivery-status.md:83-85`). On **Twilio** there is no local guard (`twilio/send_on_twilio_service.rb:28-37`): the text is Twilio's error. Arabic users see the English `ar.yml:152` |
| C-22 | L43-44 | Reply box says "you can only reply using a template message due to 24-hour message window restriction" | confirmed (EN) | `conversation.json:287`; banner `conversation.json:45,56`. The **Arabic** placeholder is English (`ar/conversation.json:274`) |
| C-23 | L74 | No countdown or reminder | confirmed by absence | search of `components/widgets/conversation` and `components-next/Conversation` finds none; banner only when `!can_reply` `MessagesView.vue:476` |
| C-24 | L75-76 | Twilio WhatsApp has the same 24 h; Facebook, Instagram, TikTok "differ" | partly wrong | Twilio 24 h `message_window_service.rb:47-49`; TikTok 48 h `:59-61`; Facebook/Instagram are **24 h by default**, 7 days only with `ENABLE_*_CHANNEL_HUMAN_AGENT` `:63-65` |
| C-24b | L93-94 | "The template button shows nothing. No approved templates synced yet" | partly wrong | The button is hidden only when the inbox has **no** synced template of any status (`ReplyBox.vue:214-220` uses the unfiltered getter `inboxes.js:36-52`); with templates but none sendable the picker opens empty ("No WhatsApp templates available. Click refresh ...", `whatsappTemplates.json:18`) |

**Templates (`whatsapp-templates.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-25 | L34-37, L39 | Header 60 (one variable), message 1024, footer 60 no variables, <=10 buttons (10 quick replies, 2 website, 1 call, 1 copy code), quick replies contiguous, URL variable at the end | confirmed (as the product enforces them) | `validator.rb:10-21,100-114,122-130,132-158,172-187`. Whether they are Meta's limits: M-28..M-31 |
| C-26 | L46-49 | Variable rules (not first/last, not adjacent, numbered 1..n in order, named lowercase unique) | confirmed, with two precisions | `validator.rb:203-222`. The edge and adjacency rules are applied to the **header** text too (`:111`, `:208`); named variables are `[a-z][a-z0-9_]*` (`:27`), i.e. digits and underscores allowed, must start with a letter |
| C-27 | L51-53 | Sample values required for every variable and never sent to a customer | confirmed | `validator.rb:225-243`; send builds parameters from `processed_params`, not examples (`template_processor_service.rb:37-46`) |
| C-28 | L26-29 | AUTHENTICATION "cannot be written here at all ... a template authored here would be one the product could never send" | **partly wrong** | UI offers only Utility/Marketing `TemplateBuilderDialog.vue:407-424`. But the **server accepts** AUTHENTICATION: `message_template.rb:36`, `validator.rb:68`, `message_templates_controller.rb:91-92`. "Never send": composer/campaign/flow exclude it (`flows/template.rb:31-36`, `isSendableTemplate` in `@chatwoot/utils`), yet `query.rb:17-19` states an API client sending an authentication template to an ordinary number "keeps working" |
| C-29 | L114-116 | Catalogue, carousel, product-list and limited-time-offer "cannot be written or sent here" | **partly wrong** | *Written*: confirmed, only HEADER/BODY/FOOTER/BUTTONS authored `validator.rb:23-24,84`. *Sent*: the send filter blocks LIST, PRODUCT, CATALOG, CALL_PERMISSION_REQUEST and a LOCATION header only (`flows/template.rb:11,31-36`; `UNSUPPORTED_COMPONENT_TYPES` in `@chatwoot/utils` `utils.cjs.development.js:2370,2426-2440`). **CAROUSEL and LIMITED_TIME_OFFER are not handled anywhere** in app/custom (grep): an approved one would be offered and sent. Unverified what Meta does |
| C-30 | L55-57 | Sample media: "Upload it in WhatsApp Manager once and paste the handle it gives you" | unverifiable | Product requires `example.header_handle` `validator.rb:116-120`; UI copy `whatsappTemplateMgmt.json:146`; no upload helper was built (`docs/whatsapp-template-manager/FINAL-CHECKPOINT.md` row 72(e)). M-33 |
| C-31 | L69-82 | Eight starters, with the stated categories and buttons | confirmed | `templateStarters.js` (ids, categories, buttons). Not disclosed: URL-button starters carry `https://example.com/...` placeholders the admin must replace; the footer "Reply STOP to unsubscribe" is a starter text, not an unsubscribe mechanism |
| C-32 | L86-96 | Steps; name never changes; language free text; inbox decides the WABA | confirmed | `templates.routes.js:10-17`; `message_templates_controller.rb:46,78-87`; name `^[a-z0-9_]{1,512}$` `message_template.rb:39` (ASCII only - AR L87 says "English"; EN says "lowercase letters" only). Language: only non-blank is checked `validator.rb:67` |
| C-33 | L92-93 | Preview "uses the same renderer that draws real messages" | partly wrong | `TemplatePreview` is shared with the composer/campaign parser (`WhatsAppTemplateParser.vue`), not with message bubbles |
| C-34 | L107-108, L120-121, L122-124 | Admin only; CSAT templates read-only; Twilio links out; quality rating only when reported; refresh every few hours | confirmed | `message_template_policy.rb:6-34`; `actions.rb:34,75-77`; `TemplatePreviewDrawer.vue:75-85`; schedule `config/schedule.yml:12-15`, `templates_sync_scheduler_job.rb:5-12` (per-channel, older than 3 h, capped per run - 040). "Sync templates ... refreshes them now" is an async job: UI says "may take a couple of minutes" `whatsappTemplateMgmt.json:8` |

**Lifecycle (`whatsapp-template-lifecycle.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-35 | L22-32 state table | Content/category/delete/submit allowed per state | confirmed | `actions.rb:16-19,48-69`; status strings `whatsappTemplateMgmt.json:21-36`. Gaps: IN_APPEAL/ARCHIVED/PENDING_DELETION/DELETED/LIMIT_EXCEEDED are **deletable** in code (`:65-69` excludes only DISABLED) but the article lists no Delete rule for them |
| C-36 | L16-18, L34-37, L112-120 | State read "immediately when WhatsApp sends an update", else every few hours | confirmed, **conditional** | Wired: `custom/.../whatsapp_events_job.rb:13-22`, `webhook_setup_service.rb:90`. Template webhooks reach only the Meta App Dashboard **default callback URL**, which is Meta-side configuration outside the repo (`docs/whatsapp-template-manager/01-meta-api-contract.md:312-330`, `03-sync-and-lifecycle.md:230-242`). Not provable that production is configured |
| C-37 | L52-55, L81-82 | "Lynomia Chat warns you before you save" an edit to an approved template | **wrong** | Copy `whatsappTemplateMgmt.json:82-86` is never referenced; `TemplateBuilderDialog.vue:288-300` saves immediately; `Index.vue:397-408` has no edit confirmation. `git log -S EDIT_APPROVED` shows the key only in the introducing commit `f3093cca` |
| C-38 | L57-61 | Only content and, where allowed, category go to Meta; category locked once approved | confirmed (product) | `revision.rb:53-58`, `actions.rb:16-19`; Meta rule M-47 |
| C-39 | L65-76 | Deleting a held template: campaigns/flows stop; name blocked 30 days "in any language"; sent-not-delivered -> "being deleted"; disabled cannot be deleted | confirmed as product behaviour; scope of the block unverified | `removal.rb` comment `:4-11`; dialog warns the *deleter* `whatsappTemplateMgmt.json:90`. The repo's own contract says the block follows deletion of an **approved** template and states nothing about languages (`01-meta-api-contract.md:297-304`). M-48 |
| C-40 | L99 | "There is no revision history. Lynomia Chat does not keep previous versions of a template's text" | partly wrong / contradicted | `Whatsapp::MessageTemplate` is `audited` (`message_template.rb:46`), so each update stores before/after attributes including `components`; `administration/audit-logs.md:23,30-31` says template changes are recorded and points *back at this article* for submission-as-update - which this article never mentions |
| C-41 | L95-97 | A submit already in flight is refused, not duplicated | confirmed | `submission.rb:31-42` (row-lock claim before the HTTP call) |
| C-42 | L90-91 | Each action is also checked on the server | confirmed | `message_templates_controller.rb:17-19`; `operation.rb:21-25` |

**Troubleshooting (`whatsapp-troubleshooting.md`)**

| ID | EN line | Claim | Verdict | Evidence |
|---|---|---|---|---|
| C-43 | L27-29 | A rejected template stays editable: "fix the text, save, and submit again" | **contradicts the lifecycle article** | Lifecycle table (L29) says **Submit: no** for Rejected, and `actions.rb:48-50` allows submit only for local drafts. Saving an edit to a rejected template *is* the resubmission: `revision.rb:26-27` sends it to Meta and sets PENDING (repo contract: "Editing a REJECTED template is the API's resubmission path", `01-meta-api-contract.md:277`) |
| C-44 | L17-25 | Detail panel "Why WhatsApp rejected it" shows the reason, plus Meta's words when sent; four listed "reasons" | partly wrong | Panel shows `rejection_info.reason + recommendation`, else the Meta `rejected_reason` enum title-cased (`TemplatePreviewDrawer.vue:75-83`), `formatTemplateLabel` `templateUtils.js:90-97`. The four row headings are paraphrase, not strings a user sees; "A duplicate exists" is not a rejection at all - it is a create-time error `NAME_TAKEN` (`operation.rb:10,53`) |
| C-45 | L40-44 | "Failed to send" with WhatsApp's explanation; "Template not found or invalid template name" | partly wrong | The template string is Lynomia's, hard-coded English `send_on_whatsapp_service.rb:39-42`; trigger is "no approved template of that name+language in this channel's synced list" `template_processor_service.rb:17-34`. Marker label in Arabic is "تعذّر الإرسال" (`ar/chatlist.json:28`) not the article's "فشل الإرسال" (AR L35) |
| C-46 | L48 | "A failed message can be retried" | partly wrong | Retry vanishes **24 hours after the message was created** and is withdrawn for recipient-scoped refusals (`MessageError.vue:56-66`); 040 section 10 item 3 |
| C-47 | L59-73 | Account Health states and the disconnect behaviour (banner, email) | confirmed | strings `inboxMgmt.json:936-944,1087-1088`; threshold 2 `reauthorizable.rb:16,34`; admin email `reauthorizable.rb:58,93`, `whatsapp_disconnect.liquid`; banner `inboxMgmt.json:9`. The Arabic UI shows these English strings, the AR article shows Arabic ones (section 6) |
| C-48 | L96 vs corpus | "Deleting and recreating an inbox is rarely the fix and can release the number" | confirmed | `webhook_teardown_service.rb:43-54` |
| C-49 | L103-105 | "a code with no page here is one nobody here has met" | wrong | DC-08 (131047, 131026 recorded in `docs/real-whatsapp-uat/`) |
