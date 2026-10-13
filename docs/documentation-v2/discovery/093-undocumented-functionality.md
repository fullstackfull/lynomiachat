---
agent: 093
scope: Hunt undocumented functionality — enumerate the product's real surface independently of the corpus, subtract what the corpus covers, rank the remainder by user harm
confidence: high
---

## 1. What you attacked

I did not attack an agent's claim. I attacked the **corpus's implicit claim to be the product's documentation** —
the claim that `custom/db/documentation/{en,ar}/**` plus the 56 contextual-help keys in
`app/javascript/dashboard/helper/documentationLinks.js` describe what Lynomia Chat does.

Method, in this order, deliberately corpus-blind until the last step:

1. **Enumerated the surface from the code.** Every `*.routes.js` and `routes.js` under
   `app/javascript/dashboard/routes/**` (144 distinct named routes), `config/routes.rb` plus all ten
   `config/routes/*.rb`, all 74 entries of `config/features.yml`, all 131 rows of
   `config/installation_config.yml`, all 53 EN dashboard i18n files (8,671 strings), `config/schedule.yml`,
   every rake task in `lib/tasks/` (27 files, 8 of them operator tools), and all 13 Super Admin dashboards /
   16 Super Admin controllers.
2. **Subtracted the corpus.** 63 EN + 63 AR Markdown files across 12 sections; keyword-matched every surface
   name, every i18n block title and every limit constant against the EN tree.
3. **Ranked what was left** by how a real user meets it: visible failure state with no help, irreversible
   action with no warning, silent limit they will hit, operator-only tooling, or a whole feature.

I also looked for the inverse trap — surfaces that have i18n and look documentable but **cannot be reached on
this installation**, so a Phase-5 writer must not spend words on them. Three of those are in §3.

### 1.1 The headline numbers

| Measure | Count | Evidence |
|---|---|---|
| Distinct named dashboard routes | **144** | `app/javascript/dashboard/routes/dashboard/**` |
| Features declared | **74** | `config/features.yml` |
| Features any Lynomia plan can sell | **42** | `custom/app/models/billing_plan.rb:41-47` (74 − 15 premium − 11 internal − 4 deprecated − 3 system, with overlap) |
| EN dashboard i18n strings | **8,671** | 53 files under `app/javascript/dashboard/i18n/locale/en/` |
| EN i18n strings behind a surface with **no article at all** | **≈2,000 (23%)** | §1.2 |
| EN articles | **63** | `custom/db/documentation/en/**/*.md` |
| Contextual-help keys | **56** (+`TIMEOUT`) | `documentationLinks.js` |
| Settings pages with no article | **6 of 23 reachable** | billing, subscription, data, conversation-workflow, assignment-policy, support/sla-policies |
| Top-level nav destinations with no article | **3 of 9** | Reports, Analytics, Support cases |
| Campaign types documented | **1 of 4** | only WhatsApp; live-chat, one-off and SMS have none |
| Channel tiles with a setup article | **1 of 10** | only WhatsApp (`ChannelList.vue:27-84`) |

### 1.2 How the ≈2,000 figure is built

Whole i18n files whose feature has **zero** corpus mentions: `report` 386, `analytics` 206,
`supportTickets` 192, `mfa` 98, `companies` 85, `onboarding` 74, `sla` 68, `search` 54, `yearInReview` 40,
`signup` 37, `contentTemplates` 37, `login` 34, `calls` 34, `setNewPassword` 11, `resetPassword` 9,
`sessionLimit` 8, `csatMgmt` 7 = **1,380**.

Zero-coverage blocks inside shared files: `settings.json` → `ASSIGNMENT_POLICY` 137, `DATA_IMPORTS` 90,
`BILLING_SETTINGS` 76, `SECURITY_SETTINGS` 45, `CAPTAIN_SETTINGS` 30, `CONVERSATION_WORKFLOW` 28,
`KEYBOARD_SHORTCUTS` 15 = **421**. `inboxMgmt.json` → `WIDGET_BUILDER` 43, `CSAT` 42, `SMTP` 23, `IMAP` 19,
`PRE_CHAT_FORM` 14, `WHATSAPP_CALLING` 10, `VOICE_CONFIGURATION` 9, `EMAIL_PROVIDERS` 6, `MICROSOFT` 2 =
**168**. `conversation.json` → `CONVERSATION_PARTICIPANTS` 13, `EMAIL_TRANSCRIPT` 12, `TRANSLATE_MODAL` 5 =
**30**.

Total **1,999**. This is conservative: I excluded every block with even a passing mention (e.g.
`PROFILE_SETTINGS`, 171 strings, is *partial* not *none*), and excluded `INBOX_MGMT.ACCOUNT_HEALTH` (103),
which the WhatsApp section touches.

**The feature agents found four holes (notifications, Facebook, Instagram, abandoned carts, billing). The real
figure is 31 ranked items below, and the three largest — Reports, Analytics and the Intercom/Freshdesk
importer — are not among the ones anybody reported.**

---

## 2. Refutations

The claim under attack, in each row: *"a stuck user would find an article."* They would not.

### 2.1 The ranked table

Priority: **P0** = visible failure state or irreversible loss with no help anywhere; **P1** = whole feature,
user-reachable, no article; **P2** = silent limit or operator tooling with a user-visible consequence;
**P3** = real but narrow.

| # | Feature | Where it lives (`file:line`) | User-visible consequence of not knowing | Corpus coverage | Priority |
|---|---|---|---|---|---|
| 1 | **Reports** — 8 families (account overview, conversations, CSAT, bot, agent, inbox, team, label) | `settings/reports/reports.routes.js:34-144`; `config/routes.rb:417-445`; `report.json` (386 strings) | A whole top-level nav destination. Every metric definition, every date-range behaviour, the CSV download and the CSAT panel are undefined. A manager cannot tell what "first response time" counts or why a number differs from Analytics' version of it. | **none** (26 files say the word "report"; not one explains the page) | **P1** |
| 2 | **Analytics** — 7 tabs (overview, WhatsApp, campaigns, automations, flows, commerce, tickets) | `analytics/analytics.routes.js:24-65`; `config/routes/analytics.rb:11-22`; `custom/app/controllers/api/v1/accounts/analytics_controller.rb:15-70`; `analytics.json` (206 strings) | Second whole nav destination. Three tabs ship **built-in degradation warnings** the user cannot interpret: Automations counts only *delayed* rules ("they run inline and record nothing"), Flows has no node metrics, Commerce has no revenue. A user reads "Nothing was recorded in this period" and concludes the product is broken. | **none** (2 passing mentions, both about *campaign* analytics) | **P1** |
| 3 | **Billing lock: trial ends → the entire dashboard 402s** | `custom/app/controllers/billing/access_guard.rb:20-35`; `app/javascript/dashboard/helper/billingGuard.js:9-10`; `custom/app/services/billing/settings.rb:12,15` | `ensure_billing_access` is a `before_action` on **every** account-scoped API request. When the subscription is not `accessible?`, every call returns 402 `subscription_required` with the hard-coded, untranslated English `"This account has no active subscription."` and the client redirects to the subscription page. Trial is **14 days**, past-due grace is **3 days** — both silent. Nothing tells a customer the clock exists, what it is, or that the whole product stops. | **none** (XA-05 flags billing has no article; the 402 lock and the two windows are additionally unreported) | **P0** |
| 4 | **Two-factor authentication (TOTP) incl. backup codes** | `settings/profile/profile.routes.js:26-42`; `config/routes.rb:368-374`; `app/services/mfa/management_service.rb:26,32`; `app/javascript/dashboard/components/app/LowBackupCodesBanner.vue:11,41`; `mfa.json` (98 strings) | Irreversible lock-out risk with **zero** help. **10** backup codes, single-use, shown once ("You won't be able to see them again"), warning banner at **≤3** remaining. Regenerating invalidates all existing codes. Lose authenticator + codes and the in-product advice is "contact your administrator" — and the only recovery that exists anywhere is a rake task (row 5). Two further undocumented traps: the authenticator app shows the issuer **"Chatwoot"**, not Lynomia (`management_service.rb:26`), and enabling 2FA **blocks Google/Apple sign-in in the mobile app outright** with a hard-coded English 403 (`custom/app/controllers/api/v1/mobile/auth_controller.rb:13,28`). | **none** (0 hits for MFA / two-factor / authenticator in EN *and* AR) | **P0** |
| 5 | **MFA recovery is a rake task only** — `mfa:reset`, `mfa:reset_all`, `mfa:generate_backup_codes` | `lib/tasks/mfa.rake:50-66`; no Super Admin route (`config/routes.rb:593-625` has none) | The only path back for a locked-out user. `mfa:reset_all` is irreversible, affects every user on the installation and its only guard is a typed `yes` at a prompt. No operator runbook, no Super Admin UI, nothing in the corpus tells a support agent this exists, so the realistic outcome is an unrecoverable account. | **none** | **P0** |
| 6 | **Intercom / Freshdesk data migration** (contacts + conversations + messages) | `settings/data/data.routes.js:8-30`; `config/routes.rb:183-192`; `app/models/data_import.rb:36-66`; 23 services + 9 jobs under `app/{services,jobs}/data_imports/`; `settings.json` → `DATA_IMPORTS` (90 strings) | A complete background-migration product: access-key validation, live progress, per-record skip logs and error CSVs, retry, **Abandon**. Silent rules nobody can discover: **one active import at a time** ("Wait for the active import to finish"), stalled after **15 minutes** (`data_import.rb:36`), a **placeholder inbox** is invented for imported conversations (`data_imports/intercom/placeholder_inbox_builder.rb`), and the Export tab says "Coming soon". A customer pastes a production Intercom key with no article on what gets created or how to undo it. | **none** (one incidental line, `import-contacts.md:142`) | **P1** |
| 7 | **Support cases** — the tenant's own case desk + its SLA policies | `tickets/tickets.routes.js:22-38`; `settings/supportSla/supportSla.routes.js:13-27`; `config/routes/support.rb:13-16`; `supportTickets.json` (192) + `sla.json` (68) | 260 strings, two routes, an events timeline, a 5-minute SLA sweep (`config/schedule.yml` → `Support::SlaSweepJob`) and an Analytics tab (row 2). Every account member reaches it. The corpus gives it **one table row** — inside the article about raising a ticket with *Lynomia*, which is a different desk (XA-04). A user who opens Support in the sidebar finds nothing that explains statuses, SLA targets or who sees what. | **passing mention** (`contact-lynomia-support.md:14`) | **P1** |
| 8 | **Global search** (contacts / conversations / messages / articles) | `search.json` (54 strings); `SEARCH.INPUT_PLACEHOLDER`, `SEARCH.PLACEHOLDER_KEYBINDING` | Four result tabs, sender/inbox filters, four preset date ranges plus a custom range, recent searches, and a hard **3-character minimum** surfaced as "Type 3 or more characters to search". The one piece of advice that exists is itself an i18n string ("Search by conversation id, email, phone number…"). An agent who cannot find a conversation has nowhere to read how matching works. | **none** (the 14 "search" hits are the contacts filter, the audit filter and the canned-response `/` picker) | **P1** |
| 9 | **CSAT surveys** — configuration, WhatsApp template creation, utility-fit analyzer, label survey rules | `inboxMgmt.json` → `INBOX_MGMT.CSAT` (42 strings); `report.json` → `CSAT_REPORTS`; `config/routes.rb:193-194` (`csat_survey_responses`) | Destructive and irreversible without a warning in any article: editing survey copy on WhatsApp "will **delete the previous template** and make a new one which will be sent again for WhatsApp approval" — i.e. a working, Meta-approved survey is destroyed and replaced by a pending one. Plus a Meta-category prediction tool, a "once per conversation" rule and five template states (incl. `NOT_FOUND`: "The template does not exist in the Meta platform"). | **passing mention** (`set-up-an-inbox.md:36,83`; `whatsapp-templates.md:120`) | **P0** |
| 10 | **Delete a conversation** | `app/controllers/api/v1/accounts/conversations_controller.rb:133-137`; `app/policies/conversation_policy.rb:6-8`; `app/services/conversations/delete_service.rb`; `conversation.json` → `CONVERSATION.DELETE_CONVERSATION`, `CARD_CONTEXT_MENU.DELETE` | Irreversible, administrator-only, and the confirm dialog says only *"Are you sure you want to delete this conversation?"* — it does **not** say the deletion is permanent, while the *message* delete dialog right next to it does say "You cannot undo this action". Undocumented side effect: on an email inbox, deleting records the source message ids in Redis for **2 days** (`Imap::DeletedMessageTracker::TTL`), so IMAP will not re-import them — a silently different outcome from deleting anywhere else. | **none** (0 hits for "delete conversation") | **P0** |
| 11 | **Live-chat campaigns and SMS campaigns** | `campaigns/campaigns.routes.js:29-57`; `campaign.json` → `CAMPAIGN.LIVE_CHAT`, `CAMPAIGN.SMS` | Three of four campaign surfaces. Live-chat campaigns are proactive widget messages fired by URL and time-on-page, sent as a chosen agent or bot; SMS campaigns are scheduled bulk sends with their own four card states including `"Not sent — channel unavailable"`. The corpus's only campaign article is WhatsApp-only, so a user reading it builds the wrong mental model for the other three. | **none** | **P1** |
| 12 | **Email channel setup** (IMAP, SMTP, Google OAuth, Microsoft OAuth, forwarding address, email continuity) | `inboxMgmt.json` → `IMAP` 19, `SMTP` 23, `EMAIL_PROVIDERS` 6, `MICROSOFT` 2, `SETTINGS_POPUP.FORWARD_EMAIL_*`, `ENABLE_CONTINUITY_VIA_EMAIL*`; `config/installation_config.yml:112-116` (`MAILER_INBOUND_EMAIL_DOMAIN`) | The second-most-likely channel after WhatsApp, and there is not one article. 0 corpus hits for IMAP, SMTP, Microsoft, Gmail, Outlook, OAuth, "forwarding address" or `reply+`. The failure states (`FORWARD_EMAIL_NOT_CONFIGURED`, continuity disabled without an inbound domain) are reachable on a fresh install. | **none** (named in a table row only) | **P1** |
| 13 | **Website widget builder + pre-chat form + HMAC identity validation** | `inboxMgmt.json` → `WIDGET_BUILDER` 43, `PRE_CHAT_FORM` 14, `SETTINGS_POPUP.{HMAC_VERIFICATION,HMAC_MANDATORY_VERIFICATION,ALLOWED_DOMAINS,LOCK_TO_SINGLE_CONVERSATION,ALLOW_MESSAGES_AFTER_RESOLVED,ALLOW_MOBILE_WEBVIEW}`; `config/installation_config.yml:696-700` (`WIDGET_TOKEN_EXPIRY` = **180 days**) | The widget is the only channel a customer installs themselves, and nothing documents the install snippet, the pre-chat form, the allowed-domain list, `HMAC_MANDATORY_VERIFICATION` (which **rejects unsigned visitors**) or the 180-day widget token expiry. The agent-side consequence is already shipping as a string: `CONVERSATION.UNVERIFIED_SESSION` = *"The identity of this user is not verified"*, with no article behind it. | **none** (0 hits for "widget code", "install the widget", "pre-chat") | **P1** |
| 14 | **Conversation Workflows / attributes required on resolve** | `settings/conversationWorkflow/conversationWorkflow.routes.js:8-19`; `settings.json` → `CONVERSATION_WORKFLOW` (28); feature `conversation_required_attributes` (`config/features.yml:267-270`, `premium: true`) | The route carries **no feature flag**, so every administrator reaches the page; the capability behind it is `premium: true`, which `BillingPlan.assignable_features` excludes (`billing_plan.rb:41-47`) **and** `Billing::OverrideGrant#sellable_feature?` refuses (`override_grant.rb:124-129`). So the page is reachable, shows "Upgrade now", and **no plan and no operator override can ever unlock it**. Compounded by PD-39: even when on, the gate is browser-only. | **none** (0 hits) | **P0** |
| 15 | **Agent availability is taken away automatically after 20 seconds** | `lib/online_status_tracker.rb:3` (`PRESENCE_DURATION` = **20s**); `app/models/concerns/availability_statusable.rb:25-28`; `settings.json` → `SIDEBAR.SET_AUTO_OFFLINE`; `app/models/account_user.rb:7` (`auto_offline` default **TRUE**) | `assign-and-prioritise.md:35` correctly says offline agents get nothing — and then never says that the product sets you offline by itself, on by default, 20 seconds after you stop using the tab. This is the single most common "why did I stop getting conversations?" with no answer in the corpus. | **partial** — the consequence is documented, the **mechanism and the threshold are not** | **P0** |
| 16 | **Reporting rollups need `account.reporting_timezone`, which has no UI** | `lib/tasks/reporting_events_rollup_timezone_setup.rake:4-5`; `lib/tasks/reporting_events_rollup.rake:4-5`; `custom/app/services/analytics/rollup_coverage.rb:16,43`; `custom/app/services/analytics/date_range.rb:85-93`; feature `report_rollup` (`features.yml`, `enabled: false`, SYSTEM) | `reporting_timezone` appears in **no** Vue file and **no** controller — it is settable only by an interactive rake task. Without it, `RollupService` writes nothing, every Analytics request falls back to source records, and the account's day boundaries silently fall back to **UTC** — which for a Kuwait customer shifts every daily total by three hours. The tenant sees `META.REASON.NO_ACCOUNT_REPORTING_TIMEZONE` = *"no reporting timezone is set, so no rollups were written"* and can do nothing about it. | **none** | **P2** |
| 17 | **Notifications are silently capped and purged** | `app/jobs/notification/remove_old_notification_job.rb:4-5` (`NOTIFICATION_LIMIT` = **300**, `OLD_NOTIFICATION_THRESHOLD` = **1 month**); `config/schedule.yml` → `remove_old_notification_job` daily 22:30 UTC | Notifications already have no article (034). On top of that: anything older than a month is deleted, and each user is trimmed to the newest 300. A user who relies on the bell as a work queue loses items with no notice. Agent 034 reported the article gap and PD-40's 3-day snooze window; **the 300/1-month retention is unreported**. | **none** | **P2** |
| 18 | **Analytics date range silently refuses wide windows** | `custom/app/services/analytics/date_range.rb:21` (`MAX_BUCKETS` = day **366**, week **104**, month **60**); `config/locales/en.yml:238` (`range_too_large`) | Picking a range over a year grouped by day returns an error, not a report. The message exists and is decent ("Narrow the range or group by a longer period") but the ceiling is nowhere a user can read it in advance, and Analytics has no article to put it in. | **none** | **P2** |
| 19 | **Delayed-automation history is purged after 30 days** | `app/models/automation_rule_pending_execution.rb:32` (`RETENTION_WINDOW` = **30 days**), `:162`; `custom/app/services/analytics/automations/overview.rb:38` | The Analytics screen degrades itself and says so: `"finished episodes are kept for 30 days, so earlier days are incomplete"`. A user comparing month-on-month automation performance reads partly-empty history as a drop in activity. The 10-minute-to-30-day *delay* range **is** documented (`automation-rules.md:99-101`); the 30-day *retention* is not. | **none** | **P2** |
| 20 | **Active sessions + the active-session limit** | `config/routes.rb:373` (`resources :sessions`); `settings/profile/ActiveSessions.vue`; `app/controllers/devise_overrides/sessions_controller.rb:146` (`MAX_USER_SESSIONS` default **25**), `:157-173`; `sessionLimit.json` | At 25 live tokens, a **browser** login is stopped on a device picker ("Active session limit reached … Please end a session before logging in"); a non-browser client (detected by `"Mozilla"` in the user agent, `:177-179`) is **silently evicted** of its oldest session instead. Both outcomes are user-visible, neither is documented, and the Profile → Active Sessions revoke list is undocumented too. | **none** | **P2** |
| 21 | **Personal access token reset** | `config/routes.rb:365`, `:75`; `settings.json` → `PROFILE_SETTINGS.FORM.ACCESS_TOKEN` | Irreversible: regenerating breaks every integration using the old token. The only warning is a two-step button — `"Are you sure?"` / `"Click again to confirm"`. `integrations.md` and `webhooks.md` describe the API but not that this control exists or what it breaks. The sibling string `PAID_PLAN_NOTE` ("API access tokens are available on paid plans") is also an undocumented entitlement. | **none** (6 files mention "access token"; all of them mean Meta's) | **P1** |
| 22 | **Platform banners — operator HTML injected into every tenant's dashboard** | `config/routes.rb:615` (`resources :platform_banners`); `app/models/platform_banner.rb`; `app/dashboards/platform_banner_dashboard.rb`; `app/javascript/dashboard/components/app/StatusBanner.vue:25-62` | A Super Admin publishes an `info`/`warning`/`error` banner that appears at the top of every account's dashboard, rendered through `v-dompurify-html` and dismissed **per browser** via `localStorage`. A tenant who sees one has no article telling them what it is, who sent it or why it reappears on another machine. Operator-side: nothing documents the blast radius. | **none** (3 "banner" hits, all about WhatsApp/Instagram restriction banners) | **P1** |
| 23 | **Operations Control Center** (signal queue, acknowledge / suppress / resume, open case) | `config/routes/operations.rb:9-28`; `custom/app/controllers/super_admin/operations_controller.rb`; `custom/app/services/operations/signal_lifecycle.rb:33` (`MAX_SUPPRESSION` = **30 days**) | Eight Super Admin reads and four writes, with a 30-day suppression ceiling. 048 covered the Platform Support desk; the Control Center's **operator decisions** and their effect on what a tenant is told are not in any corpus article or runbook. | **none** (1 "Operations" hit) | **P2** |
| 24 | **Account suspension** | `dashboard.routes.js:51-57` (`account_suspended`); `app/models/account.rb:40` (`SUSPENSION_CATEGORIES` = `spam non_payment other`); `app/controllers/super_admin/accounts_controller.rb:90-122`; `settings.json` → `APP_GLOBAL.ACCOUNT_SUSPENDED` | A tenant can be locked out behind *"Your account has been suspended due to activity that may violate our policies"* plus a **Manage billing** button. Three categories and an operator-typed reason (≤256 chars) are captured and **never shown to the customer**. The corpus gives this one sentence. | **passing mention** (`contact-lynomia-support.md:94`) | **P1** |
| 25 | **Attachment size limit (40 MB) and the type/size enforcement gap** | `config/installation_config.yml:104-108` (`MAXIMUM_FILE_UPLOAD_SIZE` = **40**); `conversation.json` → `CONVERSATION.FILE_SIZE_LIMIT`, `FILE_TYPE_NOT_SUPPORTED`, `UNKNOWN_FILE_TYPE` | The shipped error names a number the user cannot look up anywhere. Compounds PD-42/PD-43 (type and size are client-only off the web widget): an agent drags a 60 MB file onto a WhatsApp conversation, the client refuses with a number, and no article says what the ceiling is or that WhatsApp's own per-type ceilings are lower. | **none** (0 hits for a size figure) | **P2** |
| 26 | **Keyboard shortcuts** (14, incl. destructive "Resolve and move to next") | `settings.json` → `KEYBOARD_SHORTCUTS` (15 strings); `SETTINGS.KEYBOARD_SHORTCUTS.TOGGLE_MODAL` = "View all shortcuts" | The in-product modal is the entire documentation. For a desk working hundreds of conversations a day this is the highest-leverage article in the Conversations section and it does not exist. | **none** (0 hits for "keyboard") | **P2** |
| 27 | **Email a conversation transcript** | `conversation.json` → `EMAIL_TRANSCRIPT` (12); `app/javascript/dashboard/components/widgets/conversation/EmailTranscriptModal.vue:89` | Sends the full conversation, including private notes if chosen, to an arbitrary address — a data-egress action with a privacy consequence and no article. The component also handles a **402** specially, i.e. it is one of the surfaces the billing lock (row 3) hits first. Four corpus files say "transcript"; all mean the message list. | **none** | **P2** |
| 28 | **Conversation participants** | `conversation.json` → `CONVERSATION_PARTICIPANTS` (13); `app/policies/conversation_policy.rb:40-42`; routes `conversation_participating`, `conversation_through_participating` | `work-in-the-inbox.md` documents the *Participating* view; adding and removing participants, and what a participant can then see and be notified about, is not documented — and the `conversation_participating_manage` "All tab equals Mine" defect (XA-13) lands exactly here. | **partial** | **P3** |
| 29 | **Translate a message** | `conversation.json` → `TRANSLATE_MODAL`, `CONVERSATION.{VIEW_ORIGINAL,VIEW_TRANSLATED}`, `CONTEXT_MENU.TRANSLATE` | An EN/AR desk's most-used assist. `integrations.md:21-39` lists "Google Translate" as an integration; nothing explains the per-message control, when it appears, or that it depends on that integration. | **passing mention** | **P3** |
| 30 | **Twilio content templates** — a second, separate template surface | `contentTemplates.json` (37); `components/widgets/conversation/ContentTemplates/ContentTemplatesPicker.vue`; `components-next/NewConversation/components/ContentTemplateForm.vue` | A Twilio-WhatsApp/SMS inbox sends **Twilio** content templates, synced with a Refresh button ("It may take a couple of minutes to update"), not the Meta templates the corpus describes. An agent on a Twilio inbox following `whatsapp-templates.md` is reading about a different system. Ties to XA-11 (360dialog). | **none** | **P2** |
| 31 | **Account onboarding wizard** | `dashboard.routes.js:35-49` (`onboarding_account_details`, `onboarding_inbox_setup`); `onboarding.json` (74) | The first two screens a new customer ever sees. `welcome-to-lynomia-chat.md` and `set-up-your-account.md` describe the account, not the wizard; "onboarding" appears twice in the EN tree and both times it means WhatsApp onboarding. | **none** | **P2** |

### 2.2 Three findings that are structural, not per-feature

**R-A. Fifteen declared features can never be turned on by any commercial path — and one of them already has
a published article.** `BillingPlan.assignable_features` rejects `premium: true`
(`custom/app/models/billing_plan.rb:41-47`), and `Billing::OverrideGrant#sellable_feature?` uses the same list
(`custom/app/services/billing/override_grant.rb:124-129`), so a `premium` capability cannot be sold by a plan
**and** cannot be granted as an operator exception. The fifteen, all `enabled: false`:
`disable_branding`, `audit_logs`, `custom_tools`, `sla`, `captain_integration`, `channel_voice`,
`captain_integration_v2`, `captain_document_auto_sync`, `advanced_search`, `saml`, `companies`,
`csat_review_notes`, `conversation_required_attributes`, `advanced_assignment`, `audit_log_ip_address`.

The only remaining routes are `rails console` or `feature_defaults:toggle`
(`lib/tasks/feature_defaults.rake:5-6`), which edits `ACCOUNT_LEVEL_FEATURE_DEFAULTS` and **affects new
signups only**.

Consequences the corpus has not absorbed:
- `administration/audit-logs.md` is a full published article for a page gated on `audit_logs`
  (`settings/auditlogs/audit.routes.js:27`). **No existing tenant can reach it.** Capture is never gated
  (`config/installation_config.yml:729-737`), so the data exists and the page does not.
- `conversation-workflow` (row 14) and `agent_capacity_policy_*`
  (`assignmentPolicy.routes.js:62-84`, gated on `advanced_assignment`) are reachable pages whose capability is
  permanently unsellable — which makes **PD-07 moot in practice** and makes XA-13's "UI offers what the server
  refuses" an eighth instance.
- `sla` being unsellable sits directly under XA-05 and PD-02.

This belongs in the arbitration ledger as a product/commercial question, not a documentation one.

**R-B. The subscription page's entire copy is a component-local dictionary, invisible to the i18n audit and to
Crowdin.** `app/javascript/dashboard/routes/dashboard/settings/subscription/Index.vue:14-120` holds a hand-written
`TEXT = { en: {...}, ar: {...} }` table — plan statuses (`"Payment failed — locked"`), date labels
(`"Pay before"`), and the usage meters for **Agents / Inboxes / Commerce stores**. None of it is in
`app/javascript/dashboard/i18n/locale/**`. Any audit built on the i18n tree — including mine, and including
whatever Phase 2 builds — misses this page entirely unless it is added by hand. It is also the page the
billing lock (row 3) redirects every locked user to.

**R-C. Nine of ten channel tiles have no setup article, and the one article that names them is the reason
nobody noticed.** `connect-your-first-channel.md:17-34` lists every channel in a tidy table and then gives
steps for WhatsApp only. A title and a table row read as coverage; they are not. Website, Email, SMS
(Twilio **and** Bandwidth), Telegram, Line, API, TikTok and Voice/WhatsApp-calling have no article, no
contextual-help key, and in TikTok's case a feature flag that is **`enabled: true` by default**
(`config/features.yml:187-189`) with a tile at `ChannelList.vue:84`. Facebook and Instagram (041, 042) are two
of the nine, not the whole problem.

---

## 3. Survived

Claims and candidates I tried to break and could not. This matters as much as the refutations: four of these
would have wasted a Phase-5 writer's time.

| Candidate | What I tried | Why it survived |
|---|---|---|
| **Audit-log retention** | Expected an undocumented sweep | `administration/audit-logs.md:63` states it: *"One year by default. Entries older than the retention window are removed by a scheduled sweep."* Matches `AUDIT_LOG_RETENTION_DAYS` = 365 (`config/installation_config.yml:729-737`) and `AuditTrail::RetentionJob`. (The page being unreachable is R-A, a different problem.) |
| **Delayed-automation delay range** | Expected the 10-minute / 30-day bounds to be silent | `automation-rules.md:99-101` states *"10 minutes to 30 days"*, matching `AutomationRule::EXECUTION_DELAY_RANGE = (10..43_200)` (`app/models/automation_rule.rb:25`). Only the 30-day *retention* (row 19) is missing. |
| **Conversation folders / saved filters** | Expected a gap, since `advancedFilters.json` has 94 strings | `work-in-the-inbox.md:48-55,102-103` covers folders properly, including that they are private and what conditions they accept. |
| **Audience and contact-filter limits** | Expected silent ceilings | `shared-audiences.md:140-142` states 10 conversation/Commerce conditions, 50 values per condition, 1,000 saved filters per person. |
| **SAML SSO** | Looked like a 45-string undocumented security feature | **There is no SAML surface in this tree.** `settings.json` → `SECURITY_SETTINGS` is the only trace: no route, no component (`grep SECURITY_SETTINGS` over `app/javascript/**/*.vue` is empty), no `saml` route in `config/routes.rb`, and `saml` is `premium: true` (R-A). It is dead i18n from upstream Enterprise, and there is no `enterprise/` tree. **Do not write an article.** |
| **Captain (AI assistant)** | Looked like a whole undocumented product (settings page + copilot + credits + 30 strings) | `settings/captain/captain.routes.js:28-30` gates the page on `installationTypes: [CLOUD]` **and** `FEATURE_FLAGS.CAPTAIN`, which is `premium: true`. `config/features.yml:252-266` records the decision in plain words: *"Lynomia does not sell or operate an AI assistant."* **Do not write an article.** |
| **Year in Review** | Looked like a live, undocumented 40-string surface with a sidebar banner | `YearInReviewBanner.vue:32-33` hides it when `isACustomBrandedInstance`, and that getter is `installationName !== 'Chatwoot'` (`app/javascript/shared/store/globalConfig.js:71`). `INSTALLATION_NAME` is `'Lynomia Chat'` (`config/installation_config.yml:17-18`), so **the banner can never render here**. `currentYear` is also hard-coded to 2025 (`:17`). **Do not write an article** — but the `ShareModal` strings still say "Made with Chatwoot" / "Check out my {year} Year in Review with Chatwoot!", which belongs on the branding-debt list. |
| **Companies / Inbox View** | Candidate undocumented features (85 and 69 strings) | `companies` is `premium: true` (R-A, unsellable); `inbox_view` is `chatwoot_internal: true, enabled: false`. Both are below the documentation line unless a product decision changes. |
| **Account-deletion grace period** | Expected an undocumented 30-day window | There is none to document. `Internal::DeleteAccountsJob` reads `custom_attributes['marked_for_deletion_at']`, and **nothing in this tree ever writes that key** (`grep marked_for_deletion` finds only the job). Super Admin delete is immediate (`super_admin/accounts_controller.rb:80-87`, straight to `DeleteObjectJob`). The grace path is dead code, not a silent window. |
| **Webhooks** | Expected undocumented delivery semantics | `integrations/webhooks.md` covers events, payloads, secrets and the account-wide scope (`:125`, `:134`). `WEBHOOK_TIMEOUT` = 5s (`config/installation_config.yml:94-98`) is not stated, but it is an installation setting with no tenant-visible string — minor, and 058's. |

---

## 4. Not checkable

- **AR coverage of the undocumented surfaces.** I measured the EN i18n tree. Whether `ar/*.json` has parity
  for `mfa`, `report`, `analytics`, `supportTickets` and the component-local subscription dictionary (R-B)
  needs 094's method, not mine. The subscription page's AR strings being inside the component means they are
  outside Crowdin entirely.
- **Whether `report_rollup` and any `premium` flag are actually off in production.** Both are read from the
  database (`ACCOUNT_LEVEL_FEATURE_DEFAULTS` + per-account bitmask), and Phase 1 forbids touching production.
  R-A's conclusion — "no commercial path" — is proven from code and holds regardless; whether some account was
  flipped by console is unverified. Same shape as 044's open question about the retired `SHOPIFY_*` rows.
- **Whether `MAX_USER_SESSIONS`, `PRESENCE_DURATION`, `MAXIMUM_FILE_UPLOAD_SIZE`, `BILLING_TRIAL_DAYS` and
  `BILLING_GRACE_PERIOD_DAYS` carry their defaults in production.** All five are env- or
  installation-config-overridable. The defaults are 25, 20s, 40 MB, 14 days and 3 days; the article must state
  the default and say it is an installation setting, not assert the number as fact.
- **The real behaviour of the Intercom/Freshdesk importer against live tenant data** — duplicate handling, what
  the placeholder inbox looks like afterwards, and whether Abandon leaves partial data. Needs a live import,
  which Phase 1 forbids. An article cannot be written from the code alone on that point.
- **Whether the TikTok channel is actually connectable** on this installation. The flag is on by default and
  the tile exists, but `connect-your-first-channel.md:31` claims it "appears only where it has been
  configured" — which I did not verify against the installation config rows. Not checked.
- **Reports vs Analytics numeric agreement.** The two surfaces compute overlapping metrics on different
  contracts — `/api/v2` reports use epoch seconds and viewer-offset bucketing, Analytics uses calendar dates in
  the account timezone, and `custom/app/services/analytics/date_range.rb:9-10` records the inconsistency as
  known. Whether a user comparing the two sees different numbers for the same week needs a running server.
  **If they do, that is a product defect and the corpus must not paper over it.**
