---
agent: 059
scope: corpus section `administration` (one EN + one AR article) classified against the code, plus the undocumented administration surface and the article set it needs
confidence: high
---

# 059 — Corpus section `administration`

Method: both files read in full; every claim in them traced to code by direct read except where marked unverified (no `rails`, `rspec`, DB or network).
Word counts are `\S+` tokens over the body, counted with `python3 -I` because `wc -w` mis-splits Arabic in this shell.
Headline: the section is **one article, and ten of its claims are wrong, unsupported or materially incomplete** (six flatly
wrong, one unsupported, three misleading), with two more needing a correction. Behind it sit **eleven
tenant-administrator topics and seven operator areas**; sixteen of those eighteen have no adequate documentation
anywhere, eleven of them none at all. Beyond single fragments, the corpus does not explain billing, plan limits, locking
vs suspension, sign-in security, data import/export/closure, or any operator console.

## 1. Inventory

| key | EN file | AR file | title (EN / AR) | position | EN words | AR words |
|---|---|---|---|---|---|---|
| `audit-logs` | `custom/db/documentation/en/administration/audit-logs.md` (123 lines) | `custom/db/documentation/ar/administration/audit-logs.md` (111 lines) | Audit logs / سجلات التدقيق | 10 | 1017 | 816 |

Section record: `custom/db/documentation/manifest.yml:107-115` — slug `administration`, position 100, icon `shield`,
description *"What happened in your account, and who did it."* That one-line description is itself the problem: the
section was defined as "audit" and nothing else. The EN file is above the corpus median (910 words; rank 44 of 63 by
length), so it is not thin; it is the only occupant of a section that the product would fill with a dozen articles.
Baseline check: 126 files, 63+63, `administration` 1/1 — confirmed (`find custom/db/documentation -name '*.md' | wc -l` = 126).

## 2. Per-article verdict

| key | verdict | reason and evidence |
|---|---|---|
| `audit-logs` | **REWRITE**, then **SPLIT** the event reference out | Ten claims are wrong, unsupported or materially incomplete (§3), and the worked example describes something the page cannot show: the audit list renders only an activity sentence, a time and an IP address (`app/javascript/dashboard/routes/dashboard/settings/auditlogs/Index.vue:216-241`), never the changed attributes. The structure, scope honesty and "what is not recorded" idea are good and should survive; the facts under them must be replaced. The 14-row event table plus the list of unlabelled event kinds is reference material and should become its own article so the how-to stays short. |

Nothing is KEEP. Nothing is RETIRE: `auditLogs` is a live contextual-help key (`app/javascript/dashboard/helper/documentationLinks.js:86`,
used by `featureHelper.js:9` and the page's `feature-name="audit_logs"` at `Index.vue:165`), so the slug `audit-logs` must be preserved.

## 3. Accuracy against the product

Claims are cited by EN line. "Wrong" means the code contradicts the sentence as written.

| # | claim (EN line) | verdict | evidence |
|---|---|---|---|
| 1 | Read-only record under **Settings → Audit Logs** (8-9) | confirmed | `Sidebar.vue:1010-1013`; `audit.routes.js:10`; route is `resource :audit_logs, only: [:show]` (`config/routes.rb:84`), no write route exists |
| 2 | Replying, resolving, labelling, macros leave no entry (11-12) | confirmed | the `audited` declarations are in `custom/app/models/custom/audit/*.rb`, `whatsapp/message_template.rb:46` and `support/ticket.rb:23`; none covers message creation or conversation updates |
| 3 | Filter offers exactly fourteen event types in four groups (17) | confirmed | `app/javascript/dashboard/helper/auditlogHelper.js:235-265` (1+4+7+2 = 14) |
| 4 | "Each entry carries the acting user's name **and email**" (26) | **wrong** | The API emits `user_id`, `user_type`, `username` only (`custom/app/views/api/v1/accounts/audit_logs/_audit_log.json.jbuilder:5-8`). `username` is the display name captured at write time (`custom/app/models/custom/audit_log.rb:45-51`), not an email. The UI renders the live agent-list name (`auditlogHelper.js:79-88,174`). |
| 5 | Entries show "the attributes that changed" (27) and the worked example relies on it (79-80) | **wrong (in the UI)** | `audited_changes` is in the JSON (`_audit_log.json.jbuilder:12`) but `Index.vue:216-241` renders three cells: activity sentence, time, `remote_address`. Only membership entries put role/availability into the sentence (`auditlogHelper.js:58-77,102-118`). An inbox entry reads "X updated an inbox (#12)" and nothing more (`app/javascript/dashboard/i18n/locale/en/auditLogs.json:72-76`). The "enough to know what to put back" outcome is not reachable. |
| 6 | Availability changes are recorded; template submission recorded as an update (29-31) | confirmed / unverified | availability: `custom/app/models/custom/audit/account_user.rb:15` + `auditlogHelper.js:6-10`. Template: `Whatsapp::MessageTemplate` is `audited` on create/update/destroy (`message_template.rb:46`); I did not trace `Whatsapp::Templates::Submission` to confirm it saves the row, so "submission is an update" is **unverified** |
| 7 | Contacts "created, edited, **merged** or deleted" are not recorded (39) | **wrong for merge** | `custom/app/actions/custom/contact_merge_action.rb:74-86` writes `contact.merged` with `associated: @account`. It has no label or filter, so it appears undescribed. Create/edit/delete: confirmed not audited (no `audited` on `Contact`). |
| 8 | "Canned responses, custom attributes, custom roles" not recorded (42) | partly misleading | Role *definitions* are not audited, but attaching or detaching a custom role changes `account_users.custom_role_id`, which **is** audited (`audit/account_user.rb:15`; `custom_role.rb:46-48` says so). Read from the code, such an entry would render with empty attribute and value slots, because the sentence builder reads only role and availability (`auditlogHelper.js:58-77`); not observed. |
| 9 | Commerce and flow events are the only undescribed entries (43-44, 119-120) | **incomplete** | Also unlabelled and tenant-visible: contact merge (7), agent-bot create/update/destroy (`audit/agent_bot.rb:14`), support-ticket changes (`support/ticket.rb:23`), and Lynomia-operator billing rows — override grant/revoke (`billing/override_grant.rb:132`, `associated: @account`) and plan-sync revocations (`billing/feature_sync.rb:54`). Rows on `Account` with action `create`/`destroy` have no label (`auditlogHelper.js:46` labels only `account:update`). Operator rows written by `PlatformSupport::AuditWriter`, `Operations::SignalLifecycle` and `Billing::PlanAudit` deliberately omit `associated` and are invisible to tenants (`platform_support/audit_writer.rb:12-16`, `operations/signal_lifecycle.rb:130-132`, `custom/app/models/custom/audit_log.rb:24-25`). |
| 10 | A **Location** column shows city and country "where your installation looks those up" (48-49) | **wrong** | There is no Location column: `Index.vue:106-116` builds three headers (Activity, Time, IP address). Lynomia resolves no locations, ever (`disclosure.rb:16-17`; `audit_log.rb:15-16`). `LOCATION` survives only as a dead i18n key (`en/auditLogs.json:50`). |
| 11 | IP last part is masked by default; full address on installations with "the extra IP-address feature" (48-50) | confirmed with a correction | Masking is a network, e.g. `203.0.113.0/24` or a `/64` for IPv6 (`disclosure.rb:22-23,54-57`). The switch is **per account**, not per installation: `account.feature_enabled?('audit_log_ip_address')` (`disclosure.rb:19,27`; `config/features.yml:301-306`). |
| 12 | Administrators only; cannot be delegated to a custom role (54-56) | confirmed | `audit_logs_controller.rb:13` → `api/base_controller.rb:20-22`; `CustomRole::PERMISSIONS` has eight entries, none for audit (`custom_role.rb:19-28`); route `permissions: ['administrator']` (`audit.routes.js:28`) |
| 13 | Audit logs are "a paid capability" (54) | **unsupported** | `audit_logs` is `premium: true` (`config/features.yml:112-115`), and `BillingPlan.assignable_features` rejects `premium` (`custom/app/models/billing_plan.rb:41-47`), so no plan can sell it; an override cannot either (`billing/override_grant.rb:127`). The only enabling paths found are the Platform API feature write (`override_grant.rb:65-74`, called from `platform/api/v1/accounts_controller.rb:45-49`), the new-account defaults task (`lib/tasks/feature_defaults.rake:5`) and the console. The honest sentence is "Lynomia enables it per account". |
| 14 | Entries are written while the feature is off; enabling later reveals history (58-59) | confirmed | gate is on read only (`audit_trail/query.rb:52`); `retention_job.rb:3-8` |
| 15 | One year by default; installation-wide; only the server operator can change it; minimum 30 days (63-66) | confirmed, with nuance | `retention_job.rb:29-36`; `config/installation_config.yml:729-735`; editable at Super Admin general settings (`super_admin/app_configs_controller.rb:7-8`); daily 03:15 UTC (`config/schedule.yml:113-117`). Nuance: a value below 30 is **not** clamped — the sweep logs `AUDIT_RETENTION_MISCONFIGURED` and skips entirely (`retention_job.rb:61-74`), so retention silently stops being enforced. |
| 16 | Sweep errs toward keeping slightly longer (69-70) | confirmed | cutoff is a strict `<` on a UTC day boundary (`retention_job.rb:22-25,77-79`) |
| 17 | No export (72, 92-93) | confirmed | no export route for audits (`config/routes.rb:163` is contacts); `app/javascript/dashboard/api/auditLogs.js:5-13` has `get` only |
| 18 | Search needs ≥3 characters; 25 per page; one event type at a time (86-94) | confirmed | `Index.vue:27,118-124`; `audit_trail/filters.rb:17`; `auditlogHelper.js:276` builds `[query.type]` |
| 19 | Search matches the actor's "name, username **or email**" (95) | **wrong** | `by_actor_name` is `audits.username ILIKE` and nothing else (`audit_log.rb:34-36`); `username` is the display name. The product's own placeholder says "Search by name or email" (`en/auditLogs.json:12`) — the **UI string is wrong too**. |
| 20 | Deleted messages show no content; conversation deletion records only that it happened (97-99) | confirmed | `messages_controller.rb:30-39` records ids and sender only; `audit/conversation.rb:15` records ids and status |
| 21 | "A deleted user's entries remain, shown by the email recorded at the time" (100-101) | **wrong** | The stored value is a display name (`audit_log.rb:45-51`) and the UI never shows it; for a user missing from the agent list it prints the **numeric user id** (`auditlogHelper.js:79-88`) |
| 22 | Sign-in and sign-out are recorded (21) | confirmed, incomplete | `custom/app/controllers/custom/devise_overrides/sessions_controller.rb:7-9,37-52`. Not stated in the article: **failed sign-ins are not recorded**, and a person in several accounts gets the sign-in on **one** account's trail only (their most recently active, `:54-56`). |

Adjacent claims checked because they touch administration (outside this section; for the owning agents):

| file:line | claim | verdict | evidence |
|---|---|---|---|
| `getting-started/invite-your-team.md:86` | plan limit refusal is "a message about licences" | **wrong** | No licence wording exists. The message is "Your plan allows up to N team members. Upgrade your plan to invite more." (`config/locales/en.yml:300`). The count is **every** member including administrators (`billing/resource_limit.rb:29`). |
| `troubleshooting/contact-lynomia-support.md:90-94` | a billing-locked account can still open a Lynomia ticket; a suspended one cannot | confirmed | `platform_support/base_controller.rb:16-22,29-31`; suspension answers 401 earlier (`ensure_current_account_helper.rb:11`) |
| same file `:30` | five files, 10 MB each, images/PDF/text/CSV | confirmed | `platform_support/message.rb:32-34` |
| `getting-started/set-up-your-account.md:79-80` | domain and support-email fields appear only when inbound email is enabled | confirmed | `settings/account/Index.vue:77-88,200-236` |

## 4. Missing articles

Each row is the question a stuck administrator has. Evidence IDs point to §7. Audience: **T** = tenant administrator, public
portal; **O** = Lynomia operator, not for the public portal (§10 D1).

| proposed key | aud. | the question it answers | evidence | priority |
|---|---|---|---|---|
| `billing-and-subscription` | T | What do Free trial / Active / Payment failed / Canceled mean, when does my trial end, how do I pay, change plan, see invoices, cancel — and who can? | A3 | 1 |
| `locked-or-suspended-account` | T | The dashboard says subscription required, or I was signed out: is it billing or a suspension, what still works, what do I do? | A5 | 1 |
| `plan-limits-and-usage` | T | "Your plan allows up to N team members/inboxes/stores" — what counts, where do I see my usage, who raises it? | A4 | 1 |
| `audit-logs` (rewrite) | T | Who changed this setting, and what can this page not tell me? | A6 | 1 |
| `audit-log-events` (split) | T | Which of the 14 filters exist, which events show with no description, which actions never appear? | A6 | 2 |
| `sign-in-security` | T | Change my password, turn on two-factor (and why I cannot see it), use backup codes, sign out other devices, rotate my API token. | A10 | 2 |
| `settings-map` | T | Where does each admin setting live and who can open it? (Seven Settings groups, `Sidebar.vue:777-1015`) | all A | 2 |
| `export-your-data` | T | What can I download today, why is Settings → Data → Export a placeholder, how do I get everything out? | A8 | 2 |
| `import-data-from-another-tool` | T | Bring conversations, contacts and messages from a file, Intercom or Freshdesk; what was skipped; retry or abandon. | A7 | 3 (may belong to `contacts`; §10 D8) |
| `close-your-account` | T | How do I delete my account and what happens to my data and my agents' logins? | A9 | 3 — blocked on an owner decision (§10 D3) |
| `conversation-workflow-settings` | T | Auto-resolve and required attributes (account-level, admin-only). | A2 | hand to 050/057 |
| operator runbooks ×6 | O | See §9.2. | O1-O7 | separate track |

## 5. Quality

Structure is the strongest part: a plain-language opener, a "what is not recorded" list that is genuinely the useful half,
a worked example, Steps, Limits, Related, and "If it does not work", all with correct sibling-style H2s (10 H2, 0 H3).
Weaknesses:

- **Reference first, task last.** The three-line Steps block sits at line 83 of 123; a reader who wants to find one
  change reads 80 lines of explanation first. The how-to and the event reference are two documents (§2 SPLIT).
- **No images.** Zero of the 126 corpus files contain an image (`grep -rl '!\[' en ar` = 0), so there is no screenshot of
  the three-column list that the Location/attributes claims got wrong.
- **Front matter** is complete: `title` (10 chars), `description` (114, in the corpus "You will…" form), `position`,
  `tags: [administration, audit]`, `seo_description` (136; inside the 50-160 window the audit checks). No `seo_title`
  (optional). Tags omit `settings`/`security`, which an administrator would search.
- **Links:** 11 internal links, 0 unresolved, in both languages (checked against the slug set of each locale).
- **Numbers and claims that rot:** "fourteen" event types, "25 per page" and "three characters" are stated as facts with no
  pointer to where they come from; the three are correct today but will drift silently.
- **Hedged phrasing hides wrong claims.** "where your installation looks those up" (49) and "installations with the extra
  IP-address feature" (49-50) read as caution but describe things that do not exist per §3 rows 10-11.

## 6. EN/AR parity

Structure is identical: same 10 headings in the same order, one table, 11 links each. Meaning diverges only here:

| where | EN | AR | issue |
|---|---|---|---|
| AR line 42 | "Commerce store connections and order actions" | "ربط متاجر المتجر وإجراءات الطلبات" | "متاجر المتجر" ("the store's stores") is a translation slip; the product term is "متاجر Commerce" (`app/javascript/dashboard/routes/dashboard/settings/subscription/Index.vue:99`) |
| AR lines 18-23 vs the screen | filter groups "Access", "Agents & teams"; items "Sign in / sign out", "Team members", "Inbox collaborators", "Automation rules", "Conversation deletions", "Message deletions" | Arabic names in the article | The Arabic **UI** still shows these in English (`app/javascript/dashboard/i18n/locale/ar/auditLogs.json`, `FILTERS.EVENT_TYPE_GROUPS`/`EVENT_TYPES`; also `SEARCH_PLACEHOLDER`, `ALL_EVENTS`, `DATE_RANGE`, `SORT`), so an Arabic reader cannot match the article's words to the screen. Either translate the strings or quote the English labels. |
| AR line 21 | "Agents and teams" group | "وكلاء الدعم والفرق" | the UI's own AR label for the item is "الوكلاء" (`ar/auditLogs.json`); "وكلاء الدعم" (support agents) reads like Lynomia's support staff |
| AR 47 vs 61 | — | افتراضاً / افتراضيًا | inconsistent orthography within one article |
| both | rows 4, 5, 7, 9, 10, 11, 13, 19, 21 of §3 | same errors | the AR is a faithful translation of the wrong EN, so every fix lands twice |

AR is 80% of EN length (816/1017), normal for this corpus. No section is missing from either side.

## 7. What "administration" means in this product

Administration is not the audit log. The code has two audiences and eighteen areas.

### 7.1 Tenant administrator (what a customer's admin does)

| ID | area | surfaces (file:line) | gate | corpus coverage |
|---|---|---|---|---|
| A1 | Account settings | route `account/account.routes.js:8-21`; form `account/Index.vue:156-250` (name, language, domain, support email, audio transcription `:247`, Account ID `:248`, build info `:249`); API `app/controllers/api/v1/accounts_controller.rb:57-63`, permitted keys `:110-124` | administrator | **adequate**: `getting-started/set-up-your-account.md` (accurate; omits Account ID, build info, audio transcription) |
| A2 | Conversation workflow (account auto-resolve, required attributes) | `conversationWorkflow/conversationWorkflow.routes.js:8-20`; `index.vue:37,43`; settings keys `accounts_controller.rb:123`. Its `feature-name="conversation-workflow"` has no entry in `featureHelper.js:6-32`, so no help link renders | administrator | none (0 hits for auto-resolve in the EN corpus) |
| A3 | Billing and subscription | `billing/billing.routes.js:8-21` and `subscription/subscription.routes.js:9-22` render one page (`billing/ProviderIndex.vue:21-33`); statuses `billing_subscription.rb:4`, sources `:10`; defaults trial 14 d, grace 3 d, once per user `billing/settings.rb:11-15`; API `api/v1/accounts/billing_controller.rb:33-100`; routes `config/routes/billing.rb:23-38`; page states `subscription/Index.vue:219-264`, plan change with proration preview `:173-178,281-327`, portal `:329` | administrator only for `show/plans/checkout/portal/change_plan*` (`billing_controller.rb:33`); page route also lists `agent` so a locked agent lands on "Only account administrators can manage the subscription" (`subscription.routes.js:11,20`; `Index.vue:55`) | **none**; `roles-and-permissions.md:16` says "Settings and billing: all / none" |
| A4 | Plan limits and usage | counted resources `billing/resource_limit.rb:28-32` (agents = all members; inboxes; connected stores); gates `billing/agent_limit.rb:13,18`, `billing/inbox_limit.rb:15-16,21-46`, pre-flight `controllers/billing/access_guard.rb:40-48`; messages `config/locales/en.yml:298-303`; usage on the subscription page `Index.vue:156-160`; plan fields `billing_plan.rb:4-9` (month/year; flat/per_agent; usd eur gbp sar aed try egp; limits agents/inboxes/stores) | enforced for everyone | **wrong** single line (`invite-your-team.md:86`). The daily email cap (`ACCOUNT_EMAILS_LIMIT`, `installation_config.yml:122-126`) is inert here: `chatwoot_cloud?` is hard-wired false (`lib/chatwoot_app.rb:14-25`; `account_email_rate_limitable.rb:19-21,34`) |
| A5 | Locked vs suspended | **lock**: 402 `subscription_required` on every account API call except billing and Platform Support (`access_guard.rb:21-35`, `billing_controller.rb:14`, `platform_support/base_controller.rb:29-31`); UI bounces to the subscription page (`helper/billingGuard.js:7-18`); enforced only once Stripe or a trial plan is configured (`billing/settings.rb:76-78`, `billing_subscription.rb:58-60`); grace period `:36-38`. **suspension**: 401 (`ensure_current_account_helper.rb:11`), consequences listed for operators at `en.yml:797-812`, tenant screen `routes/dashboard/suspended/Index.vue:39-61`, only the suspended and billing routes stay reachable (`helper/routeHelpers.js:62-80`) | — | **partial**: one paragraph, `contact-lynomia-support.md:90-94` |
| A6 | Audit logs | §3 | administrator + `audit_logs` flag | **defective** (this report) |
| A7 | Data import | route `data/data.routes.js:10-30` (flag `data_import`, `features.yml:280-283`, off by default); API `data_imports_controller.rb`, routes `config/routes.rb:183-196` (validate, start, retry, abandon, error and skip logs); sources file, Intercom, Freshdesk (`data/importSources.js`); types contacts, conversations, messages (`en/settings.json:463-467`); one import at a time (controller `create`) | administrator (`data_import_policy.rb:2-12`) | **partial**: `import-contacts.md:141-142` only |
| A8 | Data export | Settings → Data → **Export** is a placeholder: "Exports are on the way… coming soon" (`data/Index.vue:244-267`, `en/settings.json:489-493`). What exists: contacts CSV, emailed (`contacts_controller.rb:48-56`, `account/contacts_export_job.rb:7-15`); CSAT responses download (`config/routes.rb:198`). Everything else: a Lynomia ticket in category `data_export` (`platform_support/ticket.rb:38-39`) | contacts: administrator or contact-manage role per the corpus (`contacts.md:96`); policy not read | **partial**: contact export is covered in `contacts.md:96,127`, `bulk-actions.md:107,113`; nothing on the placeholder, CSAT download or full export |
| A9 | Account closure and deletion | **No self-serve path.** The strings `GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION` (`en/generalSettings.json:17-36`: "Delete Your Account", scheduled-deletion banner, "Cancel Scheduled Deletion") have no Vue consumer (`grep` over `app/javascript` outside `/locale/` = 0). The back end half exists: `Internal::DeleteAccountsJob` daily 01:00 UTC (`app/jobs/internal/delete_accounts_job.rb:16-19`, `config/schedule.yml:53-56`), `AccountDeletionService` rewrites orphaned users' emails to `<id>@chatwoot-deleted.invalid` and sends a compliance mail (`app/services/account_deletion_service.rb:2,11-47`) — but **nothing in the tree writes `marked_for_deletion_at`** (grep over `app lib custom config` = readers only). Operators delete through Super Admin (`accounts_controller.rb:79-86`). | operator | none |
| A10 | Sign-in security and tokens | Profile → change password, two-factor, active sessions, personal access token (`profile/Index.vue:323-338,365`); MFA exists only when ActiveRecord encryption keys are set (`config/application.rb:105-113`, `api/v1/profile/mfa_controller.rb:36-42`, message `en.yml:288`); enrol/verify/disable need password and code (`mfa_controller.rb:5-6,60-64`); Super Admin sign-in enforces the code when enrolled (`super_admin/devise/sessions_controller.rb:41-49`) | any member (`profile.routes.js:14`) | **none** (0 hits for MFA/2FA/backup code/session in the EN corpus; `password` appears once, `invite-your-team.md:88`) |
| A11 | Raising a ticket with Lynomia (tenant side) | routes `config/routes/platform_support.rb:30-50`; sidebar "Help & Support" `Sidebar.vue:738-746` | any member; admin sees all, others own (policy not read) | **adequate**: `troubleshooting/contact-lynomia-support.md` |

### 7.2 Operator (Lynomia staff; Super Admin console)

| ID | area | surfaces (file:line) | corpus coverage |
|---|---|---|---|
| O1 | Super Admin console | routes `config/routes.rb:590-629`; every action behind `authenticate_super_admin!` (`super_admin/application_controller.rb:16`); sidebar `views/super_admin/application/_navigation.html.erb:38-73` (Dashboard, Accounts, Users, Platform Apps, Agent Bots, Billing Plans, Portals, Categories, Articles, Billing Settings, Settings, Operations, Customer Support, Sidekiq, Instance Health, Push Diagnostics); Platform Banners hidden unless cloud (`:48`, always hidden here); dashboard stats cached 30 min (`dashboard_controller.rb:15-26`); settings groups and the allow-list `app_configs_controller.rb:7-9,60-83` (restart-required keys `:85-98`) | none |
| O2 | Operations Control Center | routes `config/routes/operations.rb:8-29` (8 reads: overview, accounts, issues, queue, signal, account, channels, commerce; 4 writes: acknowledge, suppress, resume, open case); controller `super_admin/operations_controller.rb:14-146`; states healthy/warning/critical/unknown with *unknown is not healthy* (`operations/health.rb:1-22`); signal sources, kinds, subjects (`operations/signal.rb:22-41`); handling state derived, never stored (`:88-94`); eight queue views (`attention_queue.rb:29-38`); suppress needs a deadline ≤30 days and a reason (`signal_lifecycle.rb:33,62-70,148-155`); alert thresholds are env vars (`computed_signals.rb:13-25`); five of twelve channel types report nothing (`channel_matrix.rb:2-8`) | none (design records only: `docs/product-refinement/07`, `10`, `docs/p9/04`) |
| O3 | Account lifecycle and **seeding** | edit, suspend with required category (`spam/non_payment/other`, `account.rb:40`) and reason ≤256 (`accounts_controller.rb:90-125`); delete is asynchronous (`:79-86`); reset cache (`:72-77`); **seed**: button `views/super_admin/accounts/_seed_data.html.erb:1-15` → `Internal::SeedAccountJob` (`accounts_controller.rb:65-70`) → `Seeders::AccountSeeder#set_up_account` **destroys all teams, conversations, labels, inboxes, contacts and custom roles** (`lib/seeders/account_seeder.rb:30-37`), creates users with a fixed password and downloads avatars from a third-party host (`:74,77`) | none (CLAUDE.md documents the developer commands) |
| O4 | Billing operations | plan CRUD with Stripe sync (`super_admin/billing_plans_controller.rb:22-40`); a plan with billed subscribers may be widened, never narrowed (`billing_plan.rb:126-159`); settings (`billing/settings.rb:7-19`); per-account trial extension, manual plan grant, cancel (`billing_subscriptions_controller.rb:10-85`); entitlement overrides: feature/limit/channel, reason required, optional expiry, written to the **customer's own** audit trail (`billing_entitlement_override.rb:13,24`; `override_grant.rb:28-53,132`); Platform API (`config/routes/billing.rb:40-68`); Stripe webhook (`:71`) | none |
| O5 | Platform Support Desk, operator side | routes `config/routes/platform_support.rb:52-80`; guard requires an active `PlatformSupport::Agent` row (`platform_support_controller.rb:38,77-84`); **agents are created only by rake** (`lib/tasks/platform_support.rake:27-56`; no page, by design `platform_support.rb:62-65`) — with none granted the desk refuses everyone; roles `agent`/`lead` (`agent.rb:25`), only a lead may reassign another agent's ticket (`staff_authorizer.rb:44-50`); queue filters (`platform_support_controller.rb:104-136`); five write actions: reply, note, status, triage, assign/unassign (`platform_support_actions_controller.rb:20,40,50,61,74`); SLA policies have **no UI** and no rows (`platform_support.rb:62-65`; `sla_policy.rb`), sweep every 5 min (`config/schedule.yml:105-108`); operator mail alias has no default and silences operator mail when unset (`installation_config.yml:740-748`); statuses/categories (`ticket.rb:26,38-40`) | none |
| O6 | Installation knobs | `AUDIT_LOG_RETENTION_DAYS` (`installation_config.yml:729-735`), `OPERATIONS_*` env (`computed_signals.rb:13-25`), `BILLING_*` (`billing/settings.rb:7-19`), `PLATFORM_SUPPORT_OPERATOR_ALIAS`, `ACCOUNT_EMAILS_LIMIT` (inert, A4) | none |
| O7 | Operator command line | `platform_support:grant_agent/revoke_agent/agents` (`lib/tasks/platform_support.rake`), MFA reset for one user or all (`lib/tasks/mfa.rake:51-61`), `feature_defaults:toggle` (`feature_defaults.rake:5`), `documentation:*` (`documentation.rake:19-23`), orphan-conversation cleanup (`lib/tasks/ops/`) | none |

One hazard found while reading O3, for the security agents: the seed gate is
`ENV.fetch('ENABLE_ACCOUNT_SEEDING', !Rails.env.production?)` (`account_seeder.rb:13`, `inbox_seeder.rb:13`,
`_seed_data.html.erb:1`). In Ruby any set value, including the string `"false"` or `"0"`, is truthy, so setting the variable
to anything — even to disable seeding — enables a wipe-and-reseed from the Super Admin button. The variable is set nowhere in
`deployment/`, `docker-compose*` or `.env.example`, so the hazard is latent, not live. Separately, the button queues a job and
flashes "Account seeding triggered" (`accounts_controller.rb:66-68`) before the gate is evaluated inside the job, so a refused
seed in production reports success to the operator.

## 8. The gap, quantified

| | areas | adequate elsewhere | defective or partial | no coverage |
|---|---|---|---|---|
| Tenant administrator (A1-A11) | 11 | 2 (A1, A11) | 5 (A4, A5, A6, A7, A8) | 4 (A2, A3, A9, A10) |
| Operator (O1-O7) | 7 | 0 | 0 | 7 |
| **Total** | **18** | **2 (11%)** | **5 (28%)** | **11 (61%)** |

- The section holds **1 article for 11 tenant topics**: in-section coverage 1/11 = 9%, and that one article is defective.
- Of the 62 contextual-help keys (`documentationLinks.js:11-94`) exactly **one** points into the `administration` section (`auditLogs`). The registry has no key for
  billing, limits, lock/suspension, security, import or export. `accountSetup` (line 14) is defined but referenced by no
  component (`grep -rn accountSetup app/javascript custom` returns only the definition), so A1 is not linked from its own page either.
- Surface scale behind the gap: 8 tenant settings routes touch administration; Super Admin has 12 resource routes + 2 billing
  resources; Operations 12 routes; Platform Support staff 8 routes; Billing Platform API 4 resource families (20 routes).
- Proposed work: **10 tenant articles** (1 rewrite, 9 new = 18 new files, EN+AR) plus **6 operator runbooks** (covering the 7 operator areas) outside the portal.

## 9. Proposed article set

### 9.1 Tenant set — section `administration` (positions leave room to insert)

| pos | key | action | source of truth in code | registry key to add / wire |
|---|---|---|---|---|
| 5 | `settings-map` | new | `Sidebar.vue:777-1015`; each route's `meta.permissions` | `settingsMap` |
| 10 | `audit-logs` | **rewrite** (keep slug) | §3 | `auditLogs` exists; keep |
| 11 | `audit-log-events` | new (split) | `auditlogHelper.js:12-49,235-265`; the unlabelled kinds in §3 row 9 | `auditLogEvents` |
| 20 | `billing-and-subscription` | new | A3; Arabic status words are in the page's own dictionary (`subscription/Index.vue:80-111`) and the article must use them | `billing`; add `billing` and `subscription` to `FEATURE_DOC_KEYS` (`featureHelper.js:6-32`) so the page gets a link — it has none today |
| 30 | `plan-limits-and-usage` | new | A4 | `planLimits` |
| 40 | `locked-or-suspended-account` | new | A5 | `accountLocked` (also wire the suspended screen) |
| 50 | `sign-in-security` | new | A10 | `signInSecurity` |
| 60 | `export-your-data` | new | A8 | `dataExport` |
| 70 | `import-data-from-another-tool` | new, or relocate to `contacts` | A7 | `dataImport`; add `data_import` to `FEATURE_DOC_KEYS` |
| 80 | `close-your-account` | new, **blocked** | A9 | `closeAccount` |

Section description in `manifest.yml:111-115` must be rewritten ("Billing, limits, security, data and the record of who
changed what"), and the icon `shield` kept. Hand A2 (`conversation-workflow-settings`) to 050/057 and wire `conversation_workflow`
in `FEATURE_DOC_KEYS`.

### 9.2 Operator set — **not** in the public portal

Six runbooks for seven areas: Super Admin console and installation knobs, including audit retention (O1+O6), Operations Control
Center (O2), Account lifecycle including seeding and deletion (O3), Billing operations (O4), Platform Support Desk operator guide
(O5), and Operator command line (O7). Source material already exists as build records: `docs/p9/04-operations-center.md`,
`docs/product-refinement/07-operations-control-center-v2.md` and `10`, `docs/platform-support/05-super-admin-operations.md`,
`docs/p11/03-plans-entitlements.md` and `05-usage-limits.md` — they describe why it was built, not how to run it.

### 9.3 Sequencing

1. `audit-logs` rewrite is independent and can ship first; it does not need the product questions answered if it describes
   the page as it is (no Location, no email search, no changed attributes, numeric id for deleted users).
2. `billing-and-subscription`, `plan-limits-and-usage`, `locked-or-suspended-account` should be written together (shared terms,
   cross-links) and only after the Arabic status words are frozen.
3. `close-your-account` waits on D3. `import-data-from-another-tool` waits on the discovery agent for A7 (I read the controller head,
   not the import pipeline).

## 10. Decisions and contradictions for the orchestrator

- **D1 — where operator docs live.** The documentation portal has no access control: the public portal controller authenticates nothing
  (`app/controllers/public/api/v1/portals_controller.rb:4-10`), and `Documentation::Library.portals` is just the two platform portals, both public (`library.rb:37-39`).
  Anything seeded into `lynomia-docs` is on the open web. Seeding operator runbooks there would publish how to silence
  an incident (O2) and how to wipe an account (O3). Recommendation: keep O1-O7 in the repository (`docs/`, the existing pattern)
  and link them from the Super Admin console; do not add a private portal (that would be new auth, against §2 of the charter).
- **D2 — three audit defects are product bugs, not just doc bugs.** The page hides what changed (`Index.vue:216-241`), the search
  placeholder promises email (`en/auditLogs.json:12`) that the query cannot match (`audit_log.rb:34-36`), and a deleted actor prints a number
  (`auditlogHelper.js:79-88`). The article must follow the product as it is; if the product is fixed, the article changes again.
- **D3 — account closure policy.** There is no customer-facing way to close an account and the deletion banner strings are orphaned.
  What the corpus may promise ("ask support", retention, what happens to staff logins) is an owner decision. Do not write
  `close-your-account` from the orphaned strings.
- **D4 — contradiction with the baseline.** `01-current-system.md:196` says `DOC_ARTICLES` has **87 keys**; it has **62**
  (62 keys, 62 unique slugs, checked by evaluating the object with Node and by `grep -cE` over lines 11-94). Every slug resolves
  to a file; the only EN file with no key is `your-own-help-centre`.
- **D5 — cross-section error.** `invite-your-team.md:86` ("licences") is wrong (§3, adjacent table); owner is 049.
- **D6 — seed gate truthiness** (§7.2 after the O table): hand to 086/096 and 093.
- **D7 — `audit_logs` has no sales path.** It is `premium: true`, so neither plans nor overrides can grant it (§3 row 13). If the
  commercial intent is to sell it, the flag or the exclusion must change; if not, the article must stop calling it paid.
- **D8 — ownership of A7 and A2.** Import-from-another-tool and conversation workflow arguably belong to `contacts`/`conversations`; the
  charter says splits need evidence, and the evidence here is only that the pages live under Settings. 031/050/057 should arbitrate.
- **D9 — `chatwoot_cloud?` vs the browser.** The server's `chatwoot_cloud?` is always false (`lib/chatwoot_app.rb:14-25`) while the
  front end's `isOnChatwootCloud` reads `DEPLOYMENT_ENV` (`shared/store/globalConfig.js:66`). Cloud-only behaviours (the payment-pending
  banner `components/app/PaymentPendingBanner.vue:35-43`, the suspended page's billing link `suspended/Index.vue:11-13`, platform banners)
  therefore depend on a value I could not see. Billing articles must not describe either as available. Production `DEPLOYMENT_ENV`: **unverified**.
- **D10 — "Open case" writes to the customer's own helpdesk.** `Operations::CaseBridge#create_case` builds a tenant `Support::Ticket`
  (`case_bridge.rb:53-60`), not a Platform Support ticket (`platform_support/ticket.rb` header says the two are different desks). The
  operator runbook must say so; whether the customer account has that module enabled was not checked.
- **D11 — minor.** Comments say the staff desk has "six decisions" (`platform_support_actions_controller.rb:1`, `platform_support.rb:54`);
  there are five write actions, the sixth being unassign through `assign` (`:129`).
- **D12 — Arabic UI strings.** `ar/auditLogs.json` leaves thirteen user-visible strings in English (§6); 061/094 should decide whether to translate
  the product or quote English in the Arabic article.

## 11. Not checked

- No code was executed; every behaviour above is read, not observed. Nothing was run against a database, a browser or Stripe.
- Rendered ERB of the Super Admin and Operations pages was not read beyond the navigation, seed and account partials; the Operations
  overview's exact wording and the general-settings form fields were not viewed.
- `Whatsapp::Templates::Submission` (row 6), `Support::Tickets::Create` feature gating (D10), the tenant ticket visibility policy (A11),
  the import pipeline behind A7, rack-attack throttle values for sign-in, and `Billing::WebhookHandler` / Stripe flows were not traced.
- Whether `ChatwootExceptionTracker`/Sentry or any operator receives `AUDIT_RETENTION_MISCONFIGURED` was not checked.
- Production values: `DEPLOYMENT_ENV`, whether `audit_logs` is enabled on any real account, whether billing enforcement is on, whether any
  Platform Support agent exists. None may be inspected under the program's production rules.
