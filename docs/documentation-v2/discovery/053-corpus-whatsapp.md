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
4. All 53 internal links across the six Arabic articles are bare English keys, so an Arabic reader following any
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
| C-15 | L16-19 | Built, tested end to end against a simulated Meta in a staging rehearsal; not released to production; two real-Meta steps outstanding | confirmed as of the docs, **time-sensitive** | `docs/whatsapp-business/README.md:3`; `META-VERIFICATION.md` items 14-15 OPEN and its closing paragraph records the real-number UAT as BLOCKED. Whether production has changed since is not knowable from the repo |
| C-16a | L35-36 | Phone-typed replies arrive as echoes, matched by message id, never re-sent | confirmed | `incoming_message_base_service.rb:175-190` (type outgoing, status delivered "to prevent SendReplyJob from trying to send them", `external_echo`); dedup per README |
| C-16b | L75-77 | No manual fallback for this route | confirmed | 039 section 10 (`Whatsapp.vue:271-301`, not re-read here) |
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
| C-39 | L65-76 | Deleting a held template: campaigns/flows stop; name blocked 30 days "in any language"; sent-not-delivered -> "being deleted"; disabled cannot be deleted | confirmed as product behaviour; scope of the block unverified | `removal.rb` comment `:4-11`; dialog warns the *deleter* `whatsappTemplateMgmt.json:90`. The repo's own contract says the block follows deletion of an **approved** template and states nothing about languages (`01-meta-api-contract.md:299-304`). M-48 |
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

### 3.2 Meta assertions the repository cannot verify (routing list for agents 001-028)

Each row is something an article states as Meta's rule or Meta's behaviour. "Repo" is what the repository does with it or
records about it; **no row is verified**, and the repository's own record of Meta's contract
(`docs/whatsapp-template-manager/01-meta-api-contract.md`, `docs/whatsapp-business/META-VERIFICATION.md`) is internal and
non-normative - the latter was built from search-tool summaries, not from reading Meta's pages (its own preamble). Priority
**H** = I have a specific reason to doubt the claim, or being wrong misleads an operator into a harmful action.

| ID | Article, EN line | Assertion | Repo evidence / reason for doubt | Route | Pri |
|---|---|---|---|---|---|
| M-01 | connect L14-16 | A WABA "owns your numbers, your message templates and your messaging limits" | The window article L72-73 and the product tooltip say the limit is shared across the **business portfolio** (`inboxMgmt.json:1015`); repo contract cites "portfolio pacing" 2025-12-08 (`01-meta-api-contract.md:460`). The two articles disagree on who owns the limit | 014, 018 | H |
| M-02 | connect L42-43 | Number must not be signed in to personal WhatsApp nor connected to another WhatsApp Business Platform account | None | 013, 014 | M |
| M-03 | connect L44-46 | Manual route needs a Meta app with the WhatsApp use case, a number added and verified in it, and a permanent system-user token with both `whatsapp_business_management` and `whatsapp_business_messaging`, shown once | Product asks for both permissions `manual_setup_validation_service.rb:69,83` (per 039); "shown once" is copy `inboxMgmt.json` TOKEN.WARNING | 002, 003, 013 | M |
| M-04 | connect L52-53, L70-72 | Quick setup runs in a Meta-hosted window where the number is added and verified (by SMS in the example) | Embedded Signup flow `useWhatsappEmbeddedSignup.js`; the SMS detail is the article's | 013, 014 | M |
| M-05 | connect L85-87 | Number registration, display-name review, quality, limit and template approval are all Meta's decisions | Generic; the Lynomia side is in Account Health | 010, 014, 018 | L |
| M-06 | connect L92-95 | Deleting a quick-setup inbox deregisters the number "so it can be connected elsewhere"; deregistering a manual number "would disable the number on your own Meta app" | Product attempts the former (`webhook_teardown_service.rb:43-54`) and swallows failures; the latter is a code comment (`:41-42`) | 014, 015 | H |
| M-07 | coexistence L8-10, L33 | Meta's term is "coexistence"; the number joins the WhatsApp Business Platform officially | `META-VERIFICATION.md` items 1-2 (summary-derived) | 015 | L |
| M-08 | coexistence L40-42 | History sync is possible only in the first 24 hours after onboarding | `META-VERIFICATION.md` item 10 quotes "24 hours ... otherwise they must be offboarded and complete the flow again"; not implemented in product | 015 | M |
| M-09 | coexistence L43-44 | Contacts are not carried over | Same record, item 11 (`smb_app_state_sync`, same 24 h) | 015 | L |
| M-10 | coexistence L45-47 | The 24-hour window and approved templates "apply exactly as on any other WhatsApp channel - **including to the phone**" | No code basis: Lynomia enforces the window only on Lynomia sends; phone-typed replies arrive as echoes already sent (`incoming_message_base_service.rb:175-190`). Whether the Business app is bound by the Cloud API window is unstated in the repo | 015, 016 | H |
| M-11 | coexistence L54 | WhatsApp Business app version 2.24.17 or later | `META-VERIFICATION.md` item 9; product copy `inboxMgmt.json:461` | 015 | M |
| M-12 | coexistence L63-64 | Linked devices (e.g. WhatsApp Web) are signed out at onboarding and can be linked again | Item 9 also records "WhatsApp for Windows / WearOS unsupported" and "Groups API not available" and "fixed 20 msg/s" - none of which the article mentions | 015 | M |
| M-13 | coexistence L35-36 | Meta sends an echo of every phone-typed reply | Webhook field `smb_message_echoes` subscribed `facebook_api_client.rb:9` | 007, 015 | L |
| M-14 | coexistence L78-79 | Deleting the inbox "releases the number from the Meta app" | **Contradicted** by `META-VERIFICATION.md` item 12 (Meta: "You cannot use the deregister endpoint" for a number in use with both; offboarding is done from the phone app) | 015 | H |
| M-15 | coexistence L16-19 | Real onboarding needs Lynomia's own Meta app / Configuration ID enabled for Business-App onboarding (Tech Provider) | Item 14 OPEN | 027, 015 | M |
| M-16 | window L11-12, L24-26 | Window = 24 h from the customer's most recent message; outside it only a template sends | Flat 24 h in product `message_window_service.rb:27-28` | 016 | M |
| M-17 | window L68-70 | The window "cannot be extended, shortened or switched off" - i.e. no entry point (e.g. an ad click) changes it | Product has one constant for every WhatsApp message | 016 | H |
| M-18 | window L25-26, L77-78 | The window is "per conversation"; one customer inside it tells you nothing about another | Product scope is the **Lynomia conversation** (`message_window_service.rb:67-69`); `lock_to_single_conversation` defaults false (`db/schema.rb:1423`), so the same customer can have a closed-window conversation while Meta's window for that customer is open. Is Meta's scope per user and business number? | 016 | H |
| M-19 | window L27-29 | Nothing the business sends restarts the window, template and campaign included | Product reads incoming only | 016 | M |
| M-20 | window L35-37 | Outside the window only a template sends (not images, files, voice notes) | Product refuses all non-template sends `send_on_whatsapp_service.rb:15-17` | 016 | M |
| M-21 | window L19-20 | "Breaking it is not possible - the message simply does not go out" | What Meta actually returns when attempted: `131047 "Re-engagement message"` was observed (`docs/real-whatsapp-uat/06-delivery-status.md:83-85`) | 005, 016 | M |
| M-22 | window L71-73 | Messaging limit = unique customers messageable outside the window in a rolling 24 h, set by Meta, shared across the portfolio | UI copy `inboxMgmt.json:1014-1015`; tiers `:1048+` | 018 | M |
| M-24 | templates L22-23 | UTILITY approved most readily; MARKETING reviewed more strictly and the usual rejection reason | None | 010 | M |
| M-25 | templates L25 | WhatsApp decides the final category and may change it | Product takes the category from the create response `submission.rb:55`; repo contract cites removal of `allow_category_change` 2025-04-09 | 009, 010 | M |
| M-26 | templates L26-29 | AUTHENTICATION bodies are written by WhatsApp and need an Android package name and signature hash | Starters file repeats it `templateStarters.js:7-9` | 009 | M |
| M-27 | templates L34-36 | Limits: header text 60 (one variable), body 1024, footer 60 (no variables); header formats text/image/video/document | `validator.rb:10-12`; repo contract claims "verified verbatim" | 009 | M |
| M-28 | templates L37 | At most 10 buttons: 10 quick reply, 2 website, 1 call, 1 copy-code | `validator.rb:20-21` | 009, 012 | M |
| M-29 | templates L37-38 | Quick replies must sit together; scattered ones are refused | `validator.rb:151-158` ("[QR, URL, QR] is refused") | 012 | M |
| M-30 | templates L39 | A website button may hold one variable, at the end of the URL | `validator.rb:179-187` | 012 | M |
| M-31 | templates L46-49 | Variable rules: not first or last, never adjacent, numbered 1..n in order, named = unique lowercase. **Do the edge/adjacency rules apply to a text header?** | Product applies them to the header too (`validator.rb:111,208`); if Meta's rule is body-only, Lynomia blocks valid headers such as "Order {{1}}" | 009 | H |
| M-32 | templates L51-53 | A sample is required for every variable and reviewers read it | `validator.rb:225-243` | 009, 010 | M |
| M-33 | templates L55-57 | The media-header sample is a handle you get by "uploading the file in WhatsApp Manager once" | Product needs `header_handle` `validator.rb:116-120`. The repo contract describes it as "an uploaded media handle, not a URL" and records that no upload-and-resume helper was built (`FINAL-CHECKPOINT.md` row 72(e)). Can WhatsApp Manager show a copyable handle at all? | 009, 012 | H |
| M-34 | templates L60-66 | Review judges tone, accuracy and category fit; real-order utility messages approve quickly; vague promotion and over-promising are rejected | None | 010 | M |
| M-35 | templates L88-90, L112-113 | Name (lowercase letters, digits, underscores) and language can never change at WhatsApp; a template in `en_US` and one in `ar` are separate | `message_template.rb:39`; repo contract section 2 | 009 | M |
| M-36 | templates L117-118 | Copy-code sample cap in the product is "stricter than WhatsApp's own limit" | Repo contract: Meta raised 15 to 20 on 2025-12-03; product held at 15 (`validator.rb:16-19`) | 009, 012 | M |
| M-37 | templates L141-142 | A name must be unique per language per WABA "including a name WhatsApp is still holding from a template you deleted in the last 30 days"; Lynomia shows "name already exists" | Only subcode `2388024` is mapped to NAME_TAKEN (`operation.rb:10,53`). What Meta returns in the 30-day case is not in the repo; otherwise it falls to `META_REJECTED_REQUEST` "WhatsApp refused the request." | 009, 010, 025 | H |
| M-38 | templates L114-116 | Catalogue, carousel, product-list, limited-time-offer, location header and call-permission components exist and are managed in WhatsApp Manager | Repo contract lists them (`01-meta-api-contract.md:74-86`); carousel/LTO are **not** blocked on send (C-29) | 012 | M |
| M-39 | templates L122-123; lifecycle L16-18; TS L17-33 | The template list endpoint returns `rejected_reason`, `quality_score` and `parameter_format` - **without a `fields` parameter** | The sync calls `GET /{waba}/message_templates` with no `fields` (`whatsapp_cloud_service.rb:47-52`), yet the UI reads `rejected_reason`/`quality_score` from that payload (`_message_template.json.jbuilder`, `TemplatePreviewDrawer.vue:75-85`) and defaults a missing `parameter_format` to POSITIONAL (`mirror.rb:97`). If the defaults omit them, "Why WhatsApp rejected it" is empty after a sync and named-variable templates are mislabelled | 009, 010, 025 | H |
| M-40 | lifecycle L22-37 | Meaning of pending, approved, rejected, paused ("usually over quality"), disabled, in appeal, archived, being deleted, deleted, template limit reached | `status_update.rb:19-20` enum "WhatsAppBusinessHSMStatus" | 010 | M |
| M-41 | lifecycle L16-18 | Status arrives "immediately when WhatsApp sends an update" | Template webhooks do not support callback overrides and always go to the app's default callback URL (`01-meta-api-contract.md:312-330`); depends on Meta-side configuration | 010, 026 | M |
| M-42 | lifecycle L44-48 | Name and language are the template's identity | `01-meta-api-contract.md:60-72` | 009 | L |
| M-43 | lifecycle L52-55, L81-83 | Editing an approved template sends it back to review and it may be unsendable meanwhile | `revision.rb:26-27`; repo contract: "re-enters review and is auto-re-approved unless it fails review" | 010, 011 | M |
| M-44 | lifecycle L54-55 | Quotas: one change per 24 h and ten per 30 days for an approved template | Repo contract: rejected and paused are unlimited; no API field reports the remaining count | 009, 010 | M |
| M-45 | lifecycle L57-58 | An edit replaces all components; there is no partial edit | `revision.rb:7-9` | 009 | L |
| M-47 | lifecycle L60-61 | The category of an approved template cannot change; only while rejected or paused | `actions.rb:6-8`; UI `ERRORS.CATEGORY_NOT_EDITABLE` | 009, 010 | M |
| M-48 | lifecycle L65-76 | After deleting a held template its **name is blocked for 30 days "in any language"**; a sent-not-delivered one becomes "being deleted" for 30 days; a disabled one cannot be deleted; a template in review can be deleted | Repo contract states the block after deleting an **approved** template and says nothing about languages (`01-meta-api-contract.md:299-304`); the article generalises to any held template | 009, 010 | H |
| M-49 | lifecycle L100-101 | Appeals exist only in WhatsApp Manager | Repo contract `:277-278` | 010 | L |
| M-50 | templates L103, lifecycle L119-120, UI `CONFIRM.SUBMIT` | Review takes "minutes" and can take hours | UI copy `whatsappTemplateMgmt.json:79`; no real submission was ever made (`11-real-meta-uat.md`) | 010 | M |
| M-51 | troubleshooting L22-25 | The four "reasons you are likely to see" | Not Meta enum values and not strings the product shows (C-44); Meta's real rejection enumeration is not in the repo | 010 | H |
| M-52 | troubleshooting L31-32 | The words explaining a rejection arrive only with the live status update | `status_update.rb:91` ("`rejection_info` is webhook-only") | 010, 026 | M |
| M-53 | troubleshooting L68 | Display name "Not approved": messages still send, the number may show instead of the name | Product copy for REJECTED says only "update the name or appeal in Meta" (`inboxMgmt.json:994`); only AVAILABLE_WITHOUT_REVIEW mentions the number showing | 014 | H |
| M-54 | troubleshooting L55, L67 | Status Flagged, Restricted, Banned means Meta has acted on the number; resolved with Meta | Labels `inboxMgmt.json:1058-1073`; risky set `health_service.rb:40` | 014, 017, 018 | M |
| M-55 | troubleshooting L91, L77-81 | Messages sent while the webhook was missing "are gone ... no backfill and no replay" because WhatsApp "had nowhere to deliver them" | Meta's webhook retry and redelivery behaviour is not in the repo; the product has no replay (`whatsapp-nothing-arrives.md` says the same) | 026 | H |

(M-23 and M-46 were reserved and merged into M-22 and M-45; numbering is left gapped so other reports can cite stable IDs.)

### 3.3 Claims about the product's internal state and decisions that are not code facts

| ID | Where | Statement | Why it cannot be settled here |
|---|---|---|---|
| S-01 | coexistence L16-21 | "Built, tested ... against a simulated Meta ... **not released to production**" | Deployment state. `docs/whatsapp-business/README.md:3` and `05-lynomia-capability-doc-map.md:49` ("Do not publish as GA without confirming the production gate"). A public help article that narrates engineering release status rots the day it ships. Related: XA-02 (PRE_UAT editorial rule) |
| S-02 | coexistence title, L9, SEO text, slug, registry key `whatsappCoexistence` | Uses "Coexistence" | Product rule says the word must not appear in user-facing copy (`README.md:25`), while the shipped Account Health row says "Coexistence" (`inboxMgmt.json:983`). Agent 000 to decide which is the rule |
| S-03 | window, templates, lifecycle (many) | Outcomes of template submission/approval/edit/delete as lived experience ("approved in minutes", "approved an hour later") | `11-real-meta-uat.md`: no template was ever created, edited or deleted at a real Meta WABA from this product. Worked examples are plausible, not observed |
| S-04 | connect L35-37, C-10 | Quick-setup-unavailable behaviour | XA-10: the gate is cloud-only |
| S-05 | `docs/whatsapp-template-manager/01-meta-api-contract.md:434` (internal record, candidate IR) | Says `Flows::Template::UNSUPPORTED_COMPONENTS` and `isSendableTemplate` "already exclude" CAROUSEL, LIMITED_TIME_OFFER, ALBUM, MPM, SPM, FLOW and VOICE_CALL from every send path | The exclusion list is four names - LIST, PRODUCT, CATALOG, CALL_PERMISSION_REQUEST - plus a LOCATION header (`flows/template.rb:11,31-36`; `utils.cjs.development.js:2370`). The record overstates; writers must not inherit it. Same root as C-29 |

## 4. Missing articles

What a stuck user in this section cannot find today. "Evidence" is why the gap is real rather than imagined. Items 6-8 need
Meta content from agents 009-015 before they can be written honestly.

| # | Missing article | The user question it answers | Evidence |
|---|---|---|---|
| 1 | **Send a template** (agent side: composer picker, filling variables, starting a conversation with a template, where else a template is sent) | "The window closed - how do I actually send one, what do I fill in, and what does the customer see?" | One sentence in the window article (L43-44). The surfaces exist: composer button `ReplyBottomPanel.vue:349-358`, `TemplatesPicker.vue` (reads the filtered, sendable list `inboxes.js:53-73`), `WhatsAppOptions.vue` (new conversation), automation action `send_whatsapp_template` (`constants.js:789-792`), flow node `flows/nodes/send_template.rb`. The window and troubleshooting articles both tell the reader to "send a template" and none says how |
| 2 | **Connect WhatsApp through Twilio** | "My number is on Twilio - what do I enter, and what is different afterwards?" | A Twilio card exists (`Whatsapp.vue:108-113`) and the connect article lists it with no steps. Differences nobody states: no Account Health or Configuration tab for a Twilio WhatsApp inbox (`Settings.vue:169-174`), no local window guard so the failure text is Twilio's (C-21), templates managed in Twilio |
| 3 | **Connect manually, step by step - and what each refusal means** | "Which three values do I paste? It says 'This Phone Number ID does not belong to the WABA ID you entered' - what now?" | 5-step wizard (`WhatsappManualSetup.vue:24`); validation refusals are bare English strings (`manual_setup_validation_service.rb:46,54,59,62,69`); 039 section 9 item 7 counts fourteen of twenty reaching a tenant verbatim. Natural half of the SPLIT of `connect-whatsapp` |
| 4 | **Before you connect: what Meta needs from you** (business portfolio, verification, number rules, display name) | "What must I have in place with Meta before I start?" | Karzoun's four most-read articles are exactly this (`docs/global-documentation/04-karzoun-doc-map.md:42`); the connect article carries only three bullets (L41-46). Content must come from 013, 014, 027 |
| 5 | **Template builder messages** | "It will not let me save - what does 'A variable cannot be the first or last thing in the text' mean here?" and "What does 'WhatsApp refused the request.' mean?" | 35 field messages `whatsappTemplateMgmt.json:187-212` and 14 error toasts `:214-229`; 040 section 9 item 4 |
| 6 | **Why WhatsApp rejected my template** | "It says rejected - why, and what exactly do I change?" | Today a four-row guess table inside troubleshooting (C-44). The product shows Meta's enum or `rejection_info` (`TemplatePreviewDrawer.vue:75-83`). Needs 010's catalogue |
| 7 | **Moving a number out / taking it back to the phone** | "How do I stop using Lynomia Chat for this number without breaking it?" | The repo's own finding is that offboarding a coexistence number is done **from the phone app** (`META-VERIFICATION.md` item 12) and that deleting a manual inbox deliberately leaves the number registered (`webhook_teardown_service.rb:43-54`). The corpus says the opposite for coexistence (C-14) and nothing about manual. Needs 014/015 |
| 8 | **Switch an inbox from quick setup to manual setup** | "A banner says 'Manual setup recommended' - what is it and should I do it?" | `Settings.vue:431-442`, `inboxMgmt.json:1186-1190`, account flag `whatsapp_manual_transfer`; 039 section 9 item 2 ("given a guide to read and nothing to click"). Flag default not checked |
| 9 | **Delivery states on a WhatsApp message** (sent, delivered, read, failed) | "It says delivered - did they read it?" | 040 section 9 item 1; not a gap I introduced, but it belongs in this section |

Deliberately **not** needed, so no writer adds them: the Business Management Token (`ConfigurationPage.vue:481-486` renders
it only `isOnChatwootCloud`; `channel/whatsapp.rb:84-87` ignores it unless `chatwoot_cloud?` - inert on this product, so
`docs/global-documentation/03-chatwoot-doc-map.md:64` mapping it to `whatsapp-templates` is moot), and 360dialog (XA-11 is a
product decision).

## 5. Quality

**Structure.** The six articles share one skeleton - orienting paragraph, reference table, Steps, A worked example, Who can
do this, Limits, Related, If it does not work - and it works: a reader can jump to Limits or "If it does not work" in any of
them. Two deviations: troubleshooting has no "If it does not work" (it is that), and it duplicates material that has a
better home (section 2). Every article states its audience (administrators) explicitly, which is the right habit for a
product where agents and administrators see different screens.

**Task orientation.** Front-matter descriptions follow "You will ..." and name an outcome. `connect-whatsapp`, `whatsapp-templates`
and `the-whatsapp-24-hour-window` answer the question their title names. `whatsapp-business-coexistence` answers "what is
it" but its title promises a how-to the status block then withdraws ("treat this as a description, not an instruction").
`whatsapp-troubleshooting` is a router in practice but is written as a reference.

**Screenshots and media.** None in any of the 12 files (`grep '!\['` = 0). The two screen-heavy tasks - the 5-step manual
wizard and the template builder dialog - are exactly where a reader checks "am I on the right screen".

**Length.** 867-1,327 body words in English; the three longest (templates 1,327, connect 1,193, troubleshooting 1,223) are
the ones with a real structural case for splitting. Nothing is padded; the long tables carry the content.

**Front matter and SEO.** All fields present. No article sets `seo_title`, so the rendered `<title>` is title + a 29-character
suffix (SA-02): the coexistence article is 56 + 29 = **85 characters** in English and 79 in Arabic, the rest 47-56. EN
`description` lengths 132-158 (coexistence at 158 is 2 from the 160 ceiling); `seo_description` 130-151; AR `description` 89-113, `seo_description` 97-120.
Titles "The template lifecycle" and "WhatsApp templates" carry little search language on their own.

**Tags.** `[whatsapp, ...]` plus one of getting-started, inboxes, conversations, templates, troubleshooting. Two articles share
`templates`; none is tagged `window`, `webhook` or `account-health`, so tag search cannot find the window rule or the health tab.

**Links.** 53 internal links per locale, all resolve to a real key. No link leaves the corpus: no claim cites the Meta page it
rests on, which is why §3.2 exists. The window article links to `whatsapp-campaigns` and `work-in-the-inbox`; the
audit-log article links back to the lifecycle article for something it does not say (C-40).

**Cross-article consistency.** The connect article says the WABA owns "your messaging limits"; the window article says the
limit is shared across the portfolio (M-01). The troubleshooting article says a rejected template is fixed by "save, and
submit again"; the lifecycle table says Submit is unavailable for rejected (C-43). Four articles repeat "Meta owns these
outcomes" in near-identical words.

**Contextual help.** The window banner in the product links to Meta's policy page, not to `whatsappWindow`
(`links.js:6-7`; CH ledger entry from 040), so the best article in the section is not reachable from the screen that needs it.

## 6. EN/AR parity

Parity of **structure** is complete: 6 + 6 files, identical front-matter keys and positions, the same H2 count in
four of six articles, 53 links each, Arabic body 0.79-0.83x the English length (normal for the language, no omitted section).
Parity of **meaning** has these defects.

| ID | Where | Mismatch | Severity |
|---|---|---|---|
| P-01 | All six AR files, all 53 links | Every internal link is a bare English key (e.g. AR `connect-whatsapp.md:35` -> `whatsapp-business-coexistence`). Public article URL is `hc/<portal>/articles/<slug>` with no locale (`routes.rb:519`), the controller finds by slug alone (`articles_controller.rb:81-83`) and Arabic slugs end `-ar` (`content_seeder.rb:85-87`). An Arabic reader who follows any link lands on the **English** article. Corpus-wide; I verified only this section | major |
| P-02 | AR 24h L39, L43; AR troubleshooting L35, L39 | The Arabic articles quote Arabic UI text that the Arabic UI does not show: the composer placeholder is English in Arabic (`ar/conversation.json:274`), the stored window-refusal sentence is English (`ar.yml:152`), and the marker is "تعذّر الإرسال" (`ar/chatlist.json:28`), not the article's "فشل الإرسال" | major |
| P-03 | AR troubleshooting L62-66; AR connect L101-105; AR coexistence L9-10, L56, L89 | Same mechanism for Account Health and setup: AR articles translate "WhatsApp connection needs to be refreshed", "WhatsApp access token needs attention", "Not approved", "This access token is invalid or expired" into Arabic, while the Arabic UI shows the English originals (`ar/inboxMgmt.json:407,435,842-844,975-976`). The reverse also occurs: the Business-app card is titled "واتساب بزنس" in the Arabic UI (`ar/inboxMgmt.json:270`) but the AR articles call it "WhatsApp Business" (AR connect L30, L33; AR coexistence L10, L56). A reader cannot match article to screen | major |
| P-04 | AR connect L73; AR troubleshooting L62-63, L80, L89 | The AR articles send the reader to the **"Configuration"** tab in English. In the Arabic UI that tab is labelled "الإعدادات" (`ar/inboxMgmt.json:781`), the same word as the Settings tab (`:779`); "Account Health" is English in the UI (`:787`) and the AR articles keep it English - correct | major |
| P-05 | AR templates L39 vs EN L39 | EN: the variable "has to come at the end of the **address**". AR: "في نهاية **العنوان**" - the same word the AR article uses for the **Header** row (AR L34). The product's own AR validation string uses the same word (`ar/whatsappTemplateMgmt.json:204`), so the ambiguity is inherited, but the article puts the sentence directly under the table where "العنوان" means Header | minor |
| P-06 | AR templates L87 vs EN L88 | AR says the name uses "lowercase **English** letters"; EN says "lowercase letters". The product is ASCII-only (`message_template.rb:39`), so AR is the accurate one and EN would let an Arabic-speaking admin try Arabic letters | minor |
| P-07 | AR templates L14 (heading), L52, L71-72 | Content or structure present only in AR: a `## متى تستخدم قالباً` heading over text that is an unheaded paragraph in EN; an extra sentence that the sample values "دانة / LY-2041" exist so the reviewer sees a realistic message; an extra tail "so the flow that confirms bookings can use it". Heading counts differ (11 vs 12) | minor |
| P-08 | AR lifecycle L13 (heading), L93, L97 | AR-only: a `## نصفا حياة القالب` heading, "the list tells the two apart on purpose", and a whole extra limit - "a template that disappears from WhatsApp is reported, not restored; duplicate it". The last is a real product fact (`templateUtils.js:161-169`, `DETAIL.MISSING_NOTICE`) missing from EN. Heading counts differ (9 vs 10) | minor |
| P-09 | AR coexistence L31 vs EN L33 | EN "nothing is scanned, scraped or proxied"; AR "ولا شيء يُقرأ برمز أو يُمرَّر عبر وسيط" ("nothing is read by a code or passed through an intermediary") - "scraped" is lost and "scanned" becomes "read by a code" | minor |
| P-10 | Both locales | The wrong claims are mirrored faithfully: C-05, C-14, C-21, C-37, C-43 appear identically in Arabic. Parity is complete; accuracy is not, so fixing EN alone leaves AR wrong | note |

## Not checked

Stated so nothing here reads as cleared by silence: the 14 `whatsapp-errors` pages (other agents); the mobile apps; 360dialog
sends; Twilio sends beyond reading `send_on_twilio_service.rb`; the default value of the `whatsapp_manual_transfer` and
`whatsapp_campaign` account flags; production schedules, the Meta App Dashboard callback URL and whether the coexistence
route has since shipped; every Arabic UI string beyond the ones cited in §6; the rendered HTML of any article (I read the
Markdown and the renderer path only); `TemplatesPicker.vue` and `WhatsAppTemplateParser.vue` internals beyond the lines cited.
