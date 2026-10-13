---
agent: 052
scope: Corpus section `audiences-and-campaigns` (3 articles, EN + AR) classified against the real campaign and audience code, with the WhatsApp-campaign gap specified
confidence: high
---

# 052 — Corpus: audiences-and-campaigns

Method: every article in `custom/db/documentation/{en,ar}/audiences-and-campaigns/` read in full; each factual claim traced to code, locale files, schema or specs. Nothing was rendered, run, or sent; word counts came from a read-only Python script. Meta-side rules (opt-in, template categories, marketing caps, messaging tiers) were not checked here: they belong to agents 001-028, and where an article states one I mark it unverifiable.

**Summary.** The three articles are well written and mostly accurate on the audience side. They carry one error that costs money: the worked examples (and one preset) use the date operator backwards. The WhatsApp campaign article is accurate about what it covers, but it covers only the happy path. The product has a visible blocked state, a stuck-Processing failure, six fixed skip reasons, a results page with error, pending, unavailable and processing states, and per-recipient Meta failure codes. The section documents none of them. It has no opt-in, marketing-cap or send-limit content at all. Three articles cannot carry that, and two of the three campaign types the sidebar offers (Live chat, SMS) have no article.

## 1. Inventory

Section registered at `custom/db/documentation/manifest.yml:37-45` (position 40, icon `megaphone`). Word counts are body words after the front matter. Zero images, zero H3, zero code blocks in all six files.

| key | EN file | AR file | EN title | AR title | position | EN words | AR words | H2 | tables |
|---|---|---|---|---|---|---|---|---|---|
| `shared-audiences` | `en/audiences-and-campaigns/shared-audiences.md` | `ar/audiences-and-campaigns/shared-audiences.md` | Shared audiences | الجماهير المشتركة | 10 | 1,535 | 1,331 | 14 | 3 |
| `labels-or-shared-audiences` | `en/.../labels-or-shared-audiences.md` | `ar/.../labels-or-shared-audiences.md` | Labels or shared audiences? | الوسوم أم الجماهير المشتركة؟ | 20 | 1,262 | 1,061 | 12 | 3 |
| `whatsapp-campaigns` | `en/.../whatsapp-campaigns.md` | `ar/.../whatsapp-campaigns.md` | WhatsApp campaigns | حملات واتساب | 30 | 1,676 | 1,394 | 12 | 2 |

Warning for other agents: `wc -w` under the POSIX locale this shell runs in counts Arabic at roughly one fifth of its real size (it reports 280 / 303 / 344 for the AR files against 1,111 / 1,380 / 1,443 real words including front matter). Anyone computing EN/AR length parity with `wc -w` gets a false 4:1 gap. The real ratio is about 0.84.

## 2. Per-article verdict

| key | verdict | reason and evidence |
|---|---|---|
| `shared-audiences` | **REWRITE** (accuracy), then **SPLIT** | The mechanics are confirmed (see §3), but the headline promise and the worked example depend on a date operator that does the opposite of what the article says (W2). One 1,535-word article also carries four jobs: the concept, a condition reference (`:44-73`), the presets (`:84-106`) and permissions and limits (`:132-154`). The condition reference and presets are the natural split. |
| `labels-or-shared-audiences` | **KEEP** with two table-row corrections | The best article in the section. Every checkable claim held except two rows that assume the broken date semantics (`:24`, `:90`). Dedupe with `conversations/labels.md:20-23,51,121`, which repeats the contact-label versus conversation-label trap and the same "which to use" table (hand to 062). |
| `whatsapp-campaigns` | **EXPAND**, then **SPLIT** | Accurate on recipients, template eligibility, scheduling, permissions and limits. Silent on the blocked state, the stuck-Processing failure, the exact skip reasons, the results page, opt-in, sending limits and template freshness. At 1,676 words with 11 limit bullets it is already at the size where adding the missing material would bury the steps. The task articles in §4 should carry that material and the existing article should shrink to the overview. |

## 3. Accuracy against the product

Verdicts are `confirmed`, `wrong` or `unverifiable`. "WC" is `whatsapp-campaigns`, "SA" is `shared-audiences`, "LS" is `labels-or-shared-audiences`; line numbers are the EN file unless stated.

### 3.1 Wrong, or wrong in a way that matters

| id | claim | verdict | evidence |
|---|---|---|---|
| W1 | The Commerce date condition is offered as "Last visible purchase — **more than N days ago** — 90" (WC `:93`, SA `:124`; AR WC `:94`, SA `:116`). | **wrong** | No locale string "more than N days ago" exists. The operator's visible label is "Is x days before" (`app/javascript/dashboard/i18n/locale/en/advancedFilters.json:34`; AR "قبل x أيام", `ar/contactFilters.json:31`). |
| W2 | That condition selects "customers who bought in the last 90 days" (WC `:91-98`) and "in the last 60 days" (SA `:122-130`); SA `:9,13-15` says a customer who orders this morning is in "recent buyers" this afternoon; LS `:24,90` says "bought in the last 30 days" is a shared-audience case. | **wrong** | `days_before` means **older than** N days. `app/services/filter_service.rb:101-113` rewrites it to `is_less_than` on `today - N`. For Commerce purchases the SQL is `last_purchase_at::date < today - N` (`custom/app/services/audience/commerce_condition.rb:115-121`). The spec pins it: the contact who last bought 90 days ago is the one `days_before 30` returns (`spec/services/contacts/filter_service_audience_spec.rb:33-35,98`). The WC example therefore sends the clearance offer to lapsed customers, not recent ones. |
| W2b | The `recent_buyers` preset is documented as "number of days" (SA `:96`). | **wrong** (product defect, not only a docs defect) | The preset builds `days_before` (`app/javascript/dashboard/recipes/audiencePresets.js:105-123`). Its own copy says "Bought within the last … days" (`en/recipes.json:45`) and "last visible purchase was within the last few days" (`en/recipes.json:76`). The frontend spec locks in the same operator (`recipes/specs/audiencePresets.spec.js:76-78`). The preset's name and the operator's behaviour disagree. |
| W2c | "Bought in the last N days" can be a self-refreshing audience. | **wrong as stated** | The only operators on `commerce_last_purchase_at` are `is_greater_than`, `is_less_than` (absolute date, so the threshold freezes) and `days_before` (older than N) (`commerce_condition.rb:18`). Contacts `created_at` and `last_activity_at` have only `days_before` as their relative operator too (`lib/filters/filter_keys.yml:200-213`). "Not active for N days" is expressible. "Active within N days" is not. |
| W3 | "Per-recipient delivery results are not available on every installation" (WC `:145-148`; `:170-171`; `troubleshooting/troubleshooting.md:54`). | **wrong for this codebase** | The two analytics routes exist and are deliberately ungated (`config/routes.rb:101-105`, header of `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb`). The button shows for `processing` and `completed` WhatsApp campaigns (`CampaignList.vue:17,37-40`). Only campaigns that ran before the feature lack data, and the page says so (`en/campaign.json:211`). |
| W4 | Campaigns "refuse to run on any other WhatsApp provider" (WC `:31`). | **wrong in its implication** | The refusal is at send time, not creation. The inbox picker lists every WhatsApp-type inbox (`store/modules/inboxes.js:116-120`). `Channel::Whatsapp` allows provider `default` (`app/models/channel/whatsapp.rb:36`), and `Campaign` validates only the inbox type (`app/models/campaign.rb:191-195`). At send, `validate_provider!` raises (`app/services/whatsapp/oneoff_campaign_service.rb:27-29`) after `mark_processing!` has already set `processing` (`campaign.rb:77-79,146-157`). A campaign whose trigger fails stays `processing` by design (`spec/models/campaign_spec.rb:145-153`). Only `active` campaigns are ever re-selected (`app/jobs/trigger_scheduled_items_job.rb:15-16`), and I found no job, task or signal that recovers or reports a stuck `processing` campaign (`computed_signals.rb:70-82` measures failed-recipient rate only). The user sees a card reading "Processing" forever, with no results. |
| W5 | Card states are "Scheduled", then "Processing", then "Completed" (WC `:86-87`). | **incomplete, misleading** | A fourth state exists: "Not sent — channel unavailable" (`en/campaign.json:94`; AR `ar/campaign.json:94`). It is rendered in `danger` tone (`CampaignCard.vue:58-71,94-96`). See §4.1. |
| W6 | Per-recipient states are "queued, skipped, sent, delivered, read or failed" (WC `:146-147`). | **confirmed as the enum, wrong as the UI vocabulary** | The enum is right (`custom/app/models/campaign_recipient.rb:24`). The user sees `sent` labelled **"Awaiting delivery update"** (`en/campaign.json:264`) and the metric card **"Submitted to WhatsApp"** (`en/campaign.json:242`). The word "sent" does not appear. |
| W7 | Commerce conditions need "a connected store" (SA `:40-42`). | **incomplete** | The condition class is built only when the `lynomia_commerce` capability is on (`custom/app/services/custom/contacts/filter_service.rb:67`). It is `enabled: false` by default (`config/features.yml:307-310`), and the presets read the same flag (`app/javascript/dashboard/recipes/useRecipeContext.js:26`). |
| W8 | Draft kept "while you do" (WC `:53-54`). | **partly wrong** | It is `sessionStorage`, one tab, expires after 60 minutes (`app/javascript/dashboard/helper/campaignDraft.js:20`). Template variable values are not kept (`WhatsAppCampaignForm.vue:24`). |
| W9 | AR cross-links, 30 across the three files, are bare English keys such as `(labels)`. | **wrong for AR readers** (code-read, not rendered) | AR slugs carry an `-ar` suffix (`custom/app/services/documentation/content_seeder.rb:85-87`). The renderer rewrites no links (searched `lib/*markdown*`, portal helpers). The portal finds an article by slug **regardless of locale** (`app/controllers/public/api/v1/portals/articles_controller.rb:82`). An AR reader following `(labels)` silently lands on the English article. EN links work. Hand to 061, 062 and 075. |

### 3.2 Confirmed

| claim | evidence |
|---|---|
| WhatsApp campaign is one template, one send, scheduled (WC `:8-10`). | `campaign.rb:198-208` forces `one_off`; `oneoff_campaign_service.rb:4-8,62-69` sends once per contact then `completed!`. |
| Needs the `whatsapp_campaign` capability, "off until enabled" (WC `:32,179-180`). | `config/features.yml:204-206` `enabled: false`; route gate `campaigns.routes.js:56-62,65-72`; menu entry hidden via `Sidebar.vue:120` plus route meta. |
| Administrator-only, including the count (WC `:35,126-127`). | `app/policies/campaign_policy.rb:1-21`; `campaigns.routes.js:9-12`; `audience_previews_controller.rb:8`. |
| Template picker: APPROVED, not AUTHENTICATION, not a CSAT survey, no LIST, PRODUCT, CATALOG or CALL_PERMISSION component, no LOCATION header (WC `:60-65`). | `store/modules/inboxes.js:72` calls `isSendableTemplate` in `node_modules/@chatwoot/utils/src/template.ts` (the filter body, including the `customer_satisfaction_survey` name prefix); mirrored server-side in `custom/app/services/flows/template.rb:31-35`. |
| Template re-checked at send by name and language, must be APPROVED, else nothing is sent to that contact (WC `:67-69`). | `app/services/whatsapp/template_processor_service.rb:29-35`; recorded as skipped "No approved template for this name and language" (`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb:86`; `recipient_snapshot.rb:29`). |
| Recipients resolved at send time; count is now, not then; each contact once; labels are **contact** labels (WC `:45-51`; LS `:77-79,114`). | `custom/app/models/custom/campaign_audience.rb:12-19`; `campaign.rb:103-106`; `audience_previews_controller.rb:12`. |
| Personal audiences cannot be used; only shared ones (WC `:42-43`; SA `:114`). | `campaign_audience.rb:24-27,31`; `CampaignRecipients.vue` filters `view.shared`. |
| Due campaigns checked every five minutes (WC `:86-87`). | `config/schedule.yml:12-15` (`*/5 * * * *`). |
| A scheduled time older than three days is never sent (WC `:134-135`). | `trigger_scheduled_items_job.rb:8,15-16`. |
| No edit, no send-now, no draft, no pause; delete is the only cancel (WC `:25,131-133`). | UI: the Edit button renders only for live-chat (`CampaignCard.vue:164-171`); Delete always (`:172-179`); the enum has no draft or paused (`campaign.rb:61`). Dashboard-only truth: the API accepts `PATCH` (`campaigns_controller.rb:15-17`; `config/routes.rb` resources include `:update`), and `scheduled_at` defaults to now (`campaign.rb:201-203`). |
| Blocked contacts are not excluded and there is no opt-out list (WC `:136-137`). | No `blocked` or consent filter anywhere on the send path (`campaign.rb:103-106`, `campaign_audience.rb:12-19`, `oneoff_campaign_service.rb:42-60`). A repo-wide search for opt-in, opt-out, consent, unsubscribe and do-not-contact found no data model or code (only an unrelated Commerce opt-in). `blocked` is a contact filter key (`lib/filters/filter_keys.yml:214`). |
| Destination: phone number, or exactly one WhatsApp identity on the inbox; two identities are skipped (WC `:138-140`). | `oneoff_campaign_service.rb:117-127`. Unstated in the article: a phone number wins over any identity (`:118`). |
| A variable that renders blank skips the contact (WC `:141-142`). | `app/services/whatsapp/liquid_template_processor_service.rb:21,46-53`; `oneoff_campaign_service.rb:71-81`. |
| Campaign creates no conversation or message (WC `:143-144`). | `channel.send_template(to, {...}, nil)` (`oneoff_campaign_service.rb:95-100`). The rendered text is kept per recipient (`recipient_snapshot.rb:57-59`) and shown in the results table. |
| A shared audience cannot be deleted or made personal while a campaign references it (WC `:149`; SA `:146-147`). | `custom/app/services/audience/usage.rb:22-25` covers `active`, `processing` **and `blocked`**; `custom_filters_controller.rb:12-24`. A campaign stuck in `processing` therefore pins its audience permanently. |
| SMS shares the Recipients section (WC `:150`). | Header comment of `CampaignRecipients.vue`. |
| Audience conditions: the 11 standard contact fields (SA `:50`). | `lib/filters/filter_keys.yml:139-214`. |
| Conversation conditions mean "has at least one such conversation"; not-equal means none (SA `:55-57`). | `custom/app/services/audience/conversation_condition.rb` (EXISTS and NOT EXISTS). |
| Limits of 10 conversation or Commerce conditions, 50 values, 1,000 saved filters per person (SA `:140-142`). | `custom/app/services/custom/contacts/filter_service.rb:11-12,38,49-52`; `lib/limits.rb:11`; `app/models/custom_filter.rb:31`. |
| Campaigns and rules evaluate an audience for the whole account, not the viewer (SA `:151-153`). | `custom/app/models/custom/custom_filter.rb:13-16` (nil user); `conversation_condition.rb:34-37`. |
| Personal versus shared permissions; a leaving creator's shared audience survives (SA `:110-118`). | `custom_filters_controller.rb:6-24`; `custom/app/models/custom/concerns/user.rb:13`. |
| Nine presets with the stated names; two work without Commerce (SA `:90-103`). | `audiencePresets.js` (`contacted_us`, `never_contacted_us` need no Commerce; the rest require `COMMERCE`); names match `en/recipes.json` and `ar/recipes.json`. |
| Audience changes are audited (SA `:135`). | `custom/app/models/custom/audit/custom_filter.rb:9`. |
| Commerce figures are local, "visible" and unknown-not-zero until read; refreshed on store webhook or when the conversation panel is read (SA `:59-66,172-174`). | `custom/app/services/audience/commerce_condition.rb` header and `complete()`; `custom/app/services/commerce/realtime.rb:1-12,93`; `conversation_panel.rb:62`. |
| Label names: lower case, 2+ characters, no spaces (LS `:123`). | `app/models/label.rb:34`; `lib/regex_helper.rb:9`. |
| Automation: no contact-label action, no contact trigger, a rule can test a shared audience (LS `:69-70,79-84`). | `app/services/action_service.rb:37-41` (labels the conversation); `app/models/automation_rule.rb:56` (five events, none on contacts); `usage.rb:6-14`. |
| UI labels "Save as audience", "Share with the whole account", "More actions", "Use in a new WhatsApp campaign", "New audience from a preset", "Shared", "Only you", "Tagged with" exist verbatim in EN, and in AR (`ar/contact.json`, `ar/settings.json:378`). | locale files. |

### 3.3 Unverifiable here

| claim | what would settle it |
|---|---|
| Meta fixes a template's category on approval; to change it, create a new template (WC `:71-73`). | Meta agents, plus `whatsapp/whatsapp-template-lifecycle.md:61`, which repeats it. |
| WhatsApp restricts free-form messages outside the 24-hour window, so a campaign sends a template (WC `:12-14,113`). | Meta agents. Consistent with the code path (template send, `nil` message), not proven by it. |
| A reply to a campaign "opens a conversation as usual" (WC `:143-144`). | Trace the incoming WhatsApp service; not done. |
| Who can switch `whatsapp_campaign` on (WC `:32,179-180` say only "switched on for your account"). | Super Admin account feature toggles; not traced. The article never says whom to ask. |
| The automation-versus-campaign table rows other than the audience-test row (WC `:106-113`). | Agent 055's scope; not checked. |

## 4. Missing articles

### 4.1 The WhatsApp campaign gap, concern by concern

| concern named in the brief | what the section says today | what the product does | gap |
|---|---|---|---|
| **Templates** | Eligibility rules and re-check at send (`WC:56-73`); one FAQ (`:163-168`). | The synced template list is refreshed only when older than 3 hours (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:8`). The send gate reads that snapshot (`template_processor_service.rb:29-35`). The Meta status webhook writes only the template manager's rows (`custom/app/jobs/custom/webhooks/whatsapp_events_job.rb:19`, `custom/app/services/whatsapp/templates/status_update.rb:36-44`), not the snapshot. From the code path (inferred, not exercised), a template paused at Meta can still pass Lynomia's check and fail at Meta until the next sync. Variables are Liquid over `contact`, `agent`, `inbox`, `account` (`liquid_template_processor_service.rb:37-44`). | The article names one variable, `{{ contact.name }}` (`:141`). No guidance on choosing a template, which variables exist, media-header templates, or the staleness window. |
| **Opt-in and opt-out** | One bullet: no opt-out list, blocked contacts included (`:136-137`); `contacts/contacts.md:84` repeats it. | The product holds no consent or opt-in state at all (§3.2). The only mechanism is a label plus a `Labels — not equal to` audience condition. | Nothing tells an owner that consent is entirely their process, how to model an exclusion list, or that Meta's rule applies (Meta side unverified here). |
| **24-hour window** | Link and one table row (`:12-14,113`). | Campaigns send templates and the window article already says a campaign does not restart the window (`whatsapp/the-whatsapp-24-hour-window.md`). | Adequate for the concept. Thin on what happens after a customer replies to a campaign. |
| **Marketing limits, quality, tiers** | No mention. Zero hits for quality, tier, 131049 or messaging limit in the section. | The send path never consults tier or quality rating (no reference in `campaign.rb`, `oneoff_campaign_service.rb`, `custom/.../oneoff_campaign_service.rb`). Meta's refusal arrives per recipient as `failed` with a code (`send_failure.rb:28-34`; `recipient_snapshot.rb:63-68`). Existing articles `whatsapp-errors/whatsapp-error-131049.md` and `whatsapp-errors/whatsapp-quality-and-limits.md` link **to** the campaign article, but the campaign article links to neither. | Reader of the campaign article never learns that part of a large campaign can fail for reasons Lynomia cannot fix. |
| **Per-recipient failure** | One hedged bullet (`:145-148`) and one FAQ (`:170-174`). | Six fixed skip reasons (`recipient_snapshot.rb:24-34`): "No WhatsApp destination", "Multiple WhatsApp identities", "Campaign has no template parameters", "Template variables resolved to blank", "Authentication template not allowed for this recipient", "No approved template for this name and language". Failures keep Meta's code, title and message (`recipient_snapshot.rb:63-68`) and show as "Code {code}". The results page has a processing banner with eight wordings (`en/campaign.json:216-225`), a "delivery data will appear once sending begins" state, an "unavailable for this campaign" state, an error state, filter tabs and a paginated table of 25 (`en/campaign.json:197-290`; `analytics_controller.rb:11`). Nothing on that page links an error code to `whatsapp-errors/*`; `whatsappErrorArticle` has one consumer, the conversation message error (`MessageError.vue:6,74`). | The exact strings a stuck user reads are documented nowhere. The article uses its own paraphrases ("a variable that rendered empty"). |
| **Blocked capability state** | Absent. `blocked` in the section always means a blocked contact. | `Campaign` has a fourth status `blocked` with `blocked_reason = 'FEATURE_DISABLED'` (`campaign.rb:53-65,74-80,120-144`). It is entered when a WhatsApp campaign reaches its send time while `whatsapp_campaign` is off (`:110-112`). It is shown as "Not sent — channel unavailable" in danger tone (`en/campaign.json:94`; `CampaignCard.vue:58-71`). One deduplicated operator signal is raised (`campaign.rb:136-144`). Nothing is sent and the campaign is not retried. **`Campaign#unblock!` is the only way back and nothing calls it**: no controller, route, job, rake task or UI (the sole callers are `spec/models/campaign_blocked_spec.rb`). The tenant's only action on the card is Delete (`CampaignCard.vue:172-179`). The label says "channel", but the cause is the account capability. | A tenant admin who sees this card has no documented explanation and no documented next step. The next step is also undefined in the product: a decision for the orchestrator, listed under blockers in the digest. |

### 4.2 Missing articles, with the question each answers

Keys are proposals for the Phase 3 IA decision. "Evidence" is where the answer lives in the product today.

| proposed key | user question | evidence | priority |
|---|---|---|---|
| `whatsapp-campaign-not-sent` | "My campaign says *Not sent — channel unavailable*. Why, and what do I do?" | `campaign.rb:53-65,110-144`; `en/campaign.json:94`; `features.yml:204-206`. Needs a product answer on resuming first. | P1 |
| `whatsapp-campaign-stuck-processing` | "My campaign has said *Processing* for hours and no results appear." | W4; `campaign_spec.rb:145-153`; analytics pending state `en/campaign.json:207-210`. | P1 |
| `whatsapp-campaign-results` | "How do I read the campaign results page, and what does each status, skip reason and banner mean?" | `en/campaign.json:197-290`; `recipient_snapshot.rb:24-34`; `CampaignRecipient` ladder (`campaign_recipient.rb:9-39`). | P1 |
| `whatsapp-campaign-failures` | "Some recipients failed with a Meta code. Is it me, them, or Meta, and can I retry?" | `send_failure.rb`; `delivery_failure.rb:29-30`; there is no retry for campaigns (nothing in the campaign UI re-sends). Links to existing `whatsapp-errors/*`. | P1 |
| `whatsapp-campaign-before-you-send` | "What must I have in place before I message a group (consent, exclusions, template, audience, time)?" | opt-in row in §4.1; exclusion recipe from WC `:100`, LS `:100-110`; browser-local scheduling converted to UTC (`WhatsAppCampaignForm.vue:153-154,283-286`). | P1 |
| `whatsapp-campaign-limits-and-quality` | "How many can I send, and why did only part of it go?" | `whatsapp-quality-and-limits.md` and `whatsapp-error-131049.md` exist; need the campaign-side framing and links. Merge candidate with `whatsapp-campaign-failures`. | P1 |
| `choose-a-campaign-template` | "Which template and category do I use, which variables can I put in, and why is mine missing or stale?" | `liquid_template_processor_service.rb:37-44`; `templates_sync_scheduler_job.rb:8`; `template_processor_service.rb:29-35`. | P2 |
| `audience-conditions-reference` | "What can I filter on, how do date conditions work, and why does 'last N days' not do what I expect?" | Split from `shared-audiences`; must state the real `days_before` semantics (W1-W2c). | P1 (blocked on the date-operator decision, W2b) |
| `audience-presets` | "What does each preset select and what does it ask me?" | Split from `shared-audiences`; blocked on the `recent_buyers` decision (W2b). | P2 |
| `live-chat-campaigns` | "What is a live-chat (website widget) campaign and how is it different from SMS and WhatsApp?" | Sidebar offers Live chat, SMS and WhatsApp (`Sidebar.vue:715-736`). `commerce/commerce-provider-support.md:78-79` points to the WhatsApp article for "the two types that exist", which the target article does not describe. | P2 |
| `sms-campaigns` | "How do I run an SMS campaign?" | One bullet in WC `:150`. | P3 |
| `delete-or-cancel-a-campaign` | "What happens to a campaign and its results when I delete it?" | Deleting a campaign **deletes its delivery records** (`db/schema.rb:2098`, `ON DELETE CASCADE`); deleting a contact does the same (`:2099`). Behaviour of deleting during Processing is **not checked**. | P2 |
| `send-your-first-campaign` | "Walk me through one end-to-end, in order." | A tutorial: the current article puts Steps at line 75 of 183. | P3 |

Also missing as links, not articles: the campaign article should link `whatsapp-business-scoped-contacts` (its "Multiple WhatsApp identities" skip reason), `whatsapp-quality-and-limits`, `whatsapp-error-131049`, and `whatsapp-template-lifecycle`.

### 4.3 Contextual help

The registry holds three keys for this section: `sharedAudiences`, `labelsOrAudiences`, `campaigns` (`app/javascript/dashboard/helper/documentationLinks.js:31-33`). I found **no consumer** in campaign or audience UI. `CampaignLayout.vue`, `WhatsAppCampaignDialog.vue`, `AudiencesIndex.vue`, `AudienceExplainer.vue`, `CampaignCard.vue` and the analytics page contain no docs link or registry call. The only path to the keys is `getHelpUrlForFeature` inside `BaseSettingsHeader.vue`, which the campaign pages do not use. Contextual help for this section is registered but not wired. The `campaigns` feature key also resolves to the WhatsApp article for all campaign types (`featureHelper.js:12`).

## 5. Quality

- **Structure.** All three follow one skeleton: when to use, when not, what you need, steps, who can do this, limits, related, if it does not work. 12-14 H2s, no H3. It is consistent and scannable.
- **Task orientation.** Strongest in the FAQ blocks. Weakest in `whatsapp-campaigns`, which spends 74 lines on concept and template rules before Steps (`:75`), and keeps the facts a stuck user needs inside an 11-bullet Limits list (`:129-150`). `labels-or-shared-audiences` is a decision article and has no Steps by design.
- **Screenshots and media.** None: zero images and zero code blocks in all six files. Section-level only; other sections not checked.
- **Length.** 1,262-1,676 words. The campaign article is the longest in the section and the one most likely to grow.
- **Front matter.** `title`, `description`, `position`, `tags` and `seo_description` present in all six. No `seo_title` (falls back to `title`, `content_seeder.rb:107-109`). Measured against the audit thresholds (`lib/tasks/documentation_seo_audit.rake:18-20`, title at most 60, description 50-160): titles 12-28, meta descriptions 115-144, descriptions 87-142. No SEO warning from these six.
- **Tags.** Three each, drawn from `audiences`, `campaigns`, `contacts`, `labels`, `whatsapp`. No error-code or symptom tags.
- **Search vocabulary.** Zero occurrences of "broadcast", "bulk message", "mass message", "newsletter" or "unsubscribe" in either language. A user looking for how to message many customers does not use "audience" or "campaign".
- **Link health.** All 30 EN cross-links resolve to an existing key (every key checked against `en/*/*.md`). AR links resolve to the English article (W9).
- **Voice.** Prose is direct and avoids filler. It repeats several facts in several places (the contact-versus-conversation label trap appears in `LS`, `WC` FAQ and `conversations/labels.md`), which raises the cost of every correction.

## 6. EN/AR parity

Meaning is preserved almost everywhere, and **that is the problem for W1-W3**: both languages carry the same errors, so each correction must be applied to all six files. Structure (headings, tables, links, bullet counts) matches.

| location | EN | AR | issue | severity |
|---|---|---|---|---|
| WC AR `:168` | "a reason when it was skipped or failed" | "وسبباً إن **تُجوِّز** أو فشل" | `جوّز` means *permit*, not *skip*. The same article uses `يُتجاوَز` for *skip* (`:138,139,140`). Reads as "a reason if it was permitted or failed". | medium |
| WC AR `:71-72`, `:140` | "that contact" | "تلك جهة الاتصال" | Ungrammatical demonstrative before an idafa. Meaning intact. Needs a native reviewer. | low |
| WC AR `:82` | "**WhatsApp Template**" | "**القالب**" | The AR UI shows the label in English: `WhatsApp Template` (`ar/campaign.json`, `CREATE.FORM.TEMPLATE.LABEL`). The article names a control that is labelled differently. | low |
| SA AR `:74,118` | "**Apply filters**" | "**تطبيق الفلاتر**" | AR UI is "تطبيق التصفيات" (`ar/contact.json`, `FILTER.BUTTONS.APPLY_FILTERS`). | low |
| WC AR `:79,97` | "Campaigns → WhatsApp campaigns → Create campaign" | "الحملات ← WhatsApp campaigns ← Create campaign" | Sidebar entry in AR is "واتساب" (`ar/settings.json:386`); "WhatsApp campaigns" and "Create campaign" are the page header and button, untranslated in `ar/campaign.json`. EN has the milder version of the same mix (menu item is "WhatsApp"). | low |
| WC AR `:85,88` | "*Scheduled*", "*Processing*", "*Completed*" | "*Scheduled*", "*Processing*", "*مكتمل*" | Mixed script. **Faithful to a half-translated UI** (`ar/campaign.json:91-93,147-149`): the defect is in the locale file, not the article. The article and the locale must change together or the article will describe a UI that no longer exists. | note |
| WC AR `:144-146`, results page | "View analytics", "queued, skipped, sent…" | same English tokens | The AR results page is almost entirely English (`ar/campaign.json:197-290` shows English in most keys). The AR article cannot describe an Arabic results page because there is none. | note |
| SA AR `:18` | (absent) | "هذه هي الفكرة كلها، وهي ما يفرّق الجمهور عن [الوسم](labels)" | AR-only sentence; the EN link to `labels` sits at `:24`. Harmless drift. | low |
| SA AR `:53` | "Commerce" | "المتجر (تظهر في المنتج باسم Commerce)" | AR adds a gloss because the UI says "Commerce" while the AR prose says "المتجر" (store). EN has no equivalent. | note |
| Terminology | audience / preset / template | الجمهور (pl. الجماهير) / **قالب جاهز** / **قالب** | One root, two senses in one section: "قالب" is the WhatsApp template in `WC` and "قالب جاهز" is an audience preset in `SA`. The product itself uses these terms (`ar/recipes.json`). Flag for 061. | low |
| Link targets | resolve | 30 bare-key links resolve to the **English** article | See W9. | high (cross-corpus) |
| Shared errors | | | W1, W2, W2b, W3, W5 appear identically in AR (WC AR `:94`, `:92-100`, `:144-148`; SA AR `:12-14`, `:114-122`; LS AR `:24`, `:87`). | high |

Not checked: Arabic fluency and idiom beyond the points above; that is 061's remit.
