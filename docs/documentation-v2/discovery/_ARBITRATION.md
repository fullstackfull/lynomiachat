# Arbitration ledger — Agent 000

Every item a specialist agent escalated, classified by who can actually resolve it. Maintained by the
orchestrator as reports land. **A documentation program cannot fix a product defect, and must not document one as
if it were a feature.** That distinction is what this ledger exists to keep.

Classes:
- **PD** — product defect. Documentation cannot honestly describe it. Needs a Phase-5 owner or an owner decision.
- **DC** — doc-vs-code contradiction in the public corpus. A corpus writer fixes it.
- **IR** — internal design record is stale. The record's owner corrects it; writers must not inherit it.
- **XA** — cross-agent conflict. Agent 000 arbitrates.
- **CH** — contextual-help gap. Phase-2 coverage matrix absorbs it.
- **UV** — unverifiable here. Needs a live store / live Meta / a running server, which Phase 1 forbids.

---

## PD — product defects surfaced by documentation work

| # | Finding | Evidence | Reported by |
|---|---|---|---|
| PD-01 | `Campaign#unblock!` has no caller — no route, no controller, no UI, and `campaign_params` does not permit `campaign_status`. A blocked campaign is unrecoverable from the dashboard except by deletion. Compounded: `Audience::Usage.campaigns` counts `blocked`, so such a campaign permanently pins its audience against deletion. | `app/models/campaign.rb:87-100`, `app/controllers/api/v1/accounts/campaigns_controller.rb:31-32`, `custom/app/services/audience/usage.rb:23` | 038 |
| PD-02 | No way exists to create a `PlatformSupport::SlaPolicy` row — no route, page, dashboard, rake task or seed. `rails console` is the only path, so the SLA engine cannot be activated as shipped. | `custom/app/services/platform_support/sla/policy_resolver.rb:32,38` | 048 |
| PD-03 | `CallbacksController` has no `check_authorization`, `authorize` or admin check at all, so a plain agent can create a Facebook inbox that `InboxPolicy#create?` would refuse. Server also trusts browser-supplied `page_id` + `page_access_token` without re-verifying ownership. | `app/controllers/api/v1/accounts/callbacks_controller.rb` (whole file), `app/policies/inbox_policy.rb:51-53` | 041 |
| PD-04 | Facebook delivery/read receipts are matched without inbox scoping — `ContactInbox.find_by(source_id:)` then `Conversation.find_by(contact_id:)` across the whole installation; watermarks can land on the wrong conversation. | `lib/integrations/facebook/delivery_status.rb:26-36` | 041 |
| PD-05 | Canned responses have NO authorization layer — no policy, no `authorize` call. Any member who reaches the route can edit or delete any account canned response. | `app/controllers/api/v1/accounts/canned_responses_controller.rb` | 035 |
| PD-06 | Manual assignment accepts an agent with no inbox access (`account.users.find_by(id:)`, no membership check) while the automation path does check. | `app/services/conversations/assignment_service.rb:49-51` vs `app/services/automation/action_service.rb:47-50` | 032 |
| PD-07 | Agent Capacity Policy has a full frontend and no backend — no route, controller or model. Enabling the `advanced_assignment` flag that gates it breaks the page it unlocks. | `app/javascript/.../assignmentPolicy.routes.js:60-86` vs `config/routes.rb:253-259` | 032 |
| PD-08 | "Balanced" assignment does not exist server-side (`enum assignment_order: { round_robin: 0 }`); the form offers it and nothing rescues `ArgumentError`, so a balanced value is a 500. | `app/models/assignment_policy.rb:38`, `.../constants.js:3,18` | 032 |
| PD-09 | Per-agent capacity limits are inert: `Inbox#ensure_valid_max_assignment_limit` is an empty stub citing `enterprise/app/models/enterprise/inbox.rb`, a tree that does not exist in this repo. | `app/models/inbox.rb:256-258` | 032 |
| PD-10 | `report_manage` gates nothing server-side — `ReportPolicy#view?` is administrator-only with no `custom/` overlay, yet the reports and analytics routes accept the permission. Holder reaches the page; every panel 401s. | `app/policies/report_policy.rb:2-4`, `analytics.routes.js:18` | 033 |
| PD-11 | `knowledge_base_manage` also grants nothing — every portal/category/article policy method is unconditionally false, while helpcenter routes still accept the permission. | `custom/app/policies/custom/portal_policy.rb:25-34` | 033 |
| PD-12 | Permission/UI mismatch: Merge tab and the conversation-sidebar merge button have no gate, but the server requires administrator or `contact_manage`. A plain agent gets a generic failure toast. | `ContactManageView.vue:85`, `ContactInfo.vue:342-354`, `custom/app/policies/custom/contact_policy.rb:17-19` | 031 |
| PD-13 | Permission/UI mismatch: Import/Export are offered to `contact_manage` agents in the UI and the route, but `ContactPolicy#import?`/`#export?` are administrator-only. | `ContactMoreActions.vue:40-42`, `routes/dashboard/contacts/routes.js:7-10`, `app/policies/contact_policy.rb:10-21` | 031 |
| PD-14 | Bulk contact delete skips the "contact is online" refusal that single delete enforces. | `app/services/contacts/bulk_delete_service.rb:7-11` vs `contacts_controller.rb:113-118` | 031 |
| PD-15 | `macros.md` documents a required-attributes gate that does not exist: no server gate, resolve is unconditional, and the cited `Enterprise::Macros::ExecutionService` is absent (no `enterprise/` tree). The shipped toast asserts a falsehood. | `app/services/action_service.rb:17-19`, `config/initializers/01_inject_enterprise_edition_module.rb:78-86`, `en/macros.json:87` | 035 |
| PD-16 | Macro starter flow does not open the editor: `Index.vue` reads `created?.id` but the store action has no return statement. | `settings/macros/Index.vue:35,42-44`, `store/modules/macros.js:53-63` | 035 |
| PD-17 | `MACROS.DESCRIPTION` advertises "updating a custom attribute" — no such macro action exists. | `en/macros.json:4`, `app/models/macro.rb:33-35` | 035 |
| PD-18 | Server accepts 16 macro actions, the builder offers 15: a macro carrying `change_status` executes but throws when opened in the editor (unguarded `.find(...).inputType`). | `macro.rb:33-35` vs `settings/macros/constants.js`, `MacroEditor.vue:55-57` | 035 |
| PD-19 | Reachable automation-editor crash: `showActionInput` dereferences unguarded; the Abandoned-cart recipe requires no WhatsApp inbox but the template action is hidden without one, so creating that recipe then auto-opening it throws. | `automationHelper.js:397-402`, `automationRecipes.js:108-117`, `lynomiaAutomation.js:186`, `Index.vue:281` | 036 |
| PD-20 | `add_sla` is offered as an automation action when the `sla` feature is on but has no Ruby implementation; saving returns "Automation actions add_sla not supported." | `constants.js:808-812` | 036 |
| PD-21 | Three `sla_missed_*` notification types have no creation site anywhere, yet are offered as email/push toggles; the email path would raise — the mailer has no such method, though three Liquid templates exist. | `app/models/notification.rb:44-46`, `profile/constants.js:25-36`, `conversation_notifications_mailer.rb:2-56` | 034 |
| PD-22 | Notification preferences UI reports success on failure — the dispatch is not awaited, so `UPDATE_SUCCESS` always fires and `UPDATE_ERROR` is dead code. | `NotificationPreferences.vue:122-132`, `userNotificationSettings.js:53-58` | 034 |
| PD-23 | FCM failures are logged as successes and stale tokens are never pruned: the error check tests the legacy `['results']` key against an FCM HTTP v1 response, and `send_fcm_push` has no rescue. | `push_notification_service.rb:118-124` vs `fcm-1.0.8/lib/fcm.rb:244-263` | 034 |
| PD-24 | Several 500s where a 422 belongs: unknown notification email flag (`ArgumentError: Invalid flag`), snooze with a non-epoch value, missing Platform-Support installation config (`Config.required` raises `KeyError`, uncaught by `rescue_from ::Commerce::Error`). | `notification_settings_controller.rb:23,26-29`; `date_range_helper.rb:13-18`; `config.rb:28`, `salla_connections_controller.rb:13-24` | 034, 046 |
| PD-25 | `STORE_LIMIT_REACHED` is raised and has EN+AR strings but is absent from `useCommerceLabels.errorMessage`, so an admin at the plan limit sees "Something went wrong. Try again." Same shape for `NOT_RECONCILABLE`, which has no i18n string at all. | `store_connection.rb:132`, `en/commerce.json:165`, `useCommerceLabels.js:54-89`, `providers/base.rb:83` | 043, 045, 047 |
| PD-26 | Zid: re-authorizing a *disabled* store wipes the webhook credential pair, the registration job skips non-active stores, and Enable's `register_webhooks` is a no-op because Zid leaves `registers_webhooks?` false. Zid keeps delivering with the old pair → 401s → DEGRADED then BROKEN, with no user-visible trace. | `authorization.rb:37`, `webhook_registration_job.rb:11`, `store_connection.rb:63`, `base.rb:52-56` | 047 |
| PD-27 | A flow can be attached to a website/email/Facebook inbox from Inbox → Bot Configuration (no type or channel filter); every conversation is then skipped `unsupported_channel` with no UI explanation. The builder's own select filters channel_type but not provider, so a 360dialog WhatsApp inbox connects and then publish is refused. | `BotConfiguration.vue:95-99`, `runner.rb:182-189`, `FlowBuilder.vue:102-107`, `channel_capabilities.rb:21` | 037 |
| PD-28 | `Instagram::TestEventService` writes Meta's app-review test DM into `Channel::Instagram.last` — a real tenant's inbox, chosen by recency. | `app/services/instagram/test_event_service.rb:17,21-26` | 042 |
| PD-29 | Instagram OAuth state JWT has no `exp`, so authorize URLs never expire — unlike the 15-minute sgid every other OAuth channel uses. | `integration_helper.rb:18-22` | 042 |
| PD-30 | Webhook subscription failures are invisible on three channels: Facebook `subscribe`/`unsubscribe` rescue everything and return true; Instagram does the same; WhatsApp `manual_setup_v2` swallows the failure into `webhook_error`, returns 201 and is excluded from auto-retry. The inbox reports "connected" and receives nothing. | `channel/facebook_page.rb:49-67`, `channel/instagram.rb:57-72`, `manual_setup_service.rb:52-58`, `whatsapp.rb:230-235` | 039, 041, 042 |
| PD-31 | `register_facebook_page` turns any non-`LimitExceeded` error into a 500: the rescue does not render, so Rails renders a jbuilder whose first line dereferences nil. Reauthorize can likewise report success having changed nothing — an inner rescue inside the transaction swallows the failure and `render` still runs. | `callbacks_controller.rb:21-24,65-75`, `register_facebook_page.json.jbuilder:1` | 041 |
| PD-32 | WhatsApp `/register` failure is swallowed for embedded signup — `registration_error` is only re-raised by the two manual callers, so a number that failed registration reports as a successful signup. | `webhook_setup_service.rb:53-56` | 039 |
| PD-33 | `POST /api/v1/accounts/:id/whatsapp/access_request` is called by the client but no route or controller exists anywhere. | `whatsappChannel.js:13-17` | 039 |
| PD-34 | Billing-locked customers cannot attach files to a Platform Support ticket: the upload controller inherits the guarded base and never overrides `billing_exempt?`, while the desk itself does. | `upload_controller.rb:1`, `base_controller.rb:29-31` | 048 |
| PD-35 | Instagram has no proactive token refresh and nothing in `config/schedule.yml`; after 60 idle days `access_token` returns nil forever. | `channel/instagram.rb:76` | 042 |

## DC — public-corpus claims contradicted by code

| # | Corpus claim | Reality | File |
|---|---|---|---|
| DC-01 | `contacts.md:94` "Merge two contacts \| any agent" | administrator or `contact_manage` | 051 owns |
| DC-02 | `contacts.md:74-76` "labels do not move" on merge, and instructs unnecessary work | `MergeRelocation` moves labels | 051 |
| DC-03 | `contacts.md:102` + `bulk-actions.md:110` "changes to a contact are not recorded in the audit log" | merge now writes a `contact.merged` audit row | 051 |
| DC-04 | `contacts.md:96` import/export "administrator or contact_manage" vs `bulk-actions.md:112-114` "administrator-only" — the corpus contradicts itself | policy is administrator-only | 051 |
| DC-05 | `assign-and-prioritise.md` "balanced across current load" and "falls back to round robin" | unimplementable here (PD-08) | 050 |
| DC-06 | `whatsapp-campaigns.md` "per-recipient delivery results are not available on every installation" | the analytics routes are explicitly not feature-gated | 052 |
| DC-07 | `whatsapp-campaigns.md` describes three card states | four exist | 052 |
| DC-08 | `whatsapp-troubleshooting.md:102-104` "a code with no page here is one nobody here has met" | 131047 and 131026 were met and recorded in `docs/real-whatsapp-uat/` | 054 |
| DC-09 | `automation-rules.md:33` "twelve" triggers, `:65` "eleven" recipes, `:54-60` omits `send_whatsapp_template` | 13 triggers, 12 recipes, 19 actions | 055 |
| DC-10 | `automation-rules.md:91` "no time-based conditions of any kind" | date-typed custom attributes accept `is_greater_than`/`is_less_than`/`days_before` | 055 |
| DC-11 | `connect-salla.md` (EN+AR) abandoned carts "cannot be turned on" for Salla | fully built; off by default + PRE_UAT, overridable by `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` | 056 |
| DC-12 | `commerce-provider-support.md:59` "none are planned" vs `:75` "held until writes are verified" for Salla order actions — self-contradictory | code supports `:59` | 056 |
| DC-13 | `commerce-overview.md` "there is no commerce report" | Analytics → Commerce ships 12 metrics, 3 series, 5 breakdowns | 056 |
| DC-14 | all five `commerce-*` troubleshooting articles quote "What you see" strings matching no shipped copy (EN and AR) | e.g. doc "Your store did not answer" vs shipped "The store is not reachable right now." | 056 |
| DC-15 | `commerce-store-needs-reconnecting.md` gives one fix ("Reconnect") for all four platforms | only Zid/Shopify have that button; Woo replaces keys; Salla re-authorizes in Salla | 056 |
| DC-16 | `connect-zid.md` (EN+AR) "three events" | five (3 order + 2 cart) | 056 |
| DC-17 | `connect-whatsapp.md` claims the inbox health endpoint is administrators only | gated to inbox membership | 053 |
| DC-18 | `connect-your-first-channel.md:30-34` unavailable channels are greyed out | the Instagram tile has no gate and fails at the redirect | 049 |
| DC-19 | `roles-and-permissions.md:28` lists 6 permissions; client offers 7; `CustomRole::PERMISSIONS` holds 8 — `support_ticket_manage` missing from both locales | | 057 |
| DC-20 | AR `roles-and-permissions.md:92` claims an assigned custom role "cannot be reassigned" after a downgrade; EN makes no such claim | the agents endpoint checks ownership only | 057, 061 |
| DC-21 | `set-up-your-account.md:31` account-language claim | holds for mail bodies; every notification email SUBJECT is a hard-coded English Ruby string | 049 |

## IR — stale internal design records (writers must not inherit these)

| # | Record | Why stale | Reported by |
|---|---|---|---|
| IR-01 | `docs/commerce/08-woocommerce-security.md` | "only GET requests exist", "no webhook endpoint", old timeouts and page sizes, cites a spec example that does not exist. Mark as a Phase-2 snapshot, not a source. | 045 |
| IR-02 | `docs/commerce/15-zid-webhook-security.md` | still marks the Basic Auth field shape VERIFY and quotes the superseded nested payload; this is the first file an engineer reads on that contract. `05-provider-capability-matrix.md:28` and `23-real-uat-and-production-gate.md:92,278` repeat it. | 047 |
| IR-03 | `docs/commerce-production/01-provider-capability-matrix.md` §3 | "Zid CART CREATED — Lynomia does not subscribe" (it does) and conflates Salla webhook registration with consumption. Contradicts `FINAL-CHECKPOINT.md`. | 043, 047 |
| IR-04 | `docs/automation/05-runtime-security-and-tenancy.md:72-74` | "Automation has no template parameters, so it can never send a template or bypass the window" — now false. | 036 |
| IR-05 | `docs/campaigns/03-audience-dependency.md:12,18-24` | says the guard counts `active` + `processing`; code counts `blocked` too. | 038 |
| IR-06 | `docs/pre-deploy/04-decisions-implemented.md:148-155` | says `custom_roles` is `premium: true` and "no plan sells it"; the key was removed, so it IS in `BillingPlan.assignable_features`. | 033 |
| IR-07 | `docs/platform-support/12-refresh-against-product-refinement.md` §2:193 | promises staff `/agents` and `/sla_policies` routes that are deliberately absent. §9 item 5 is unwritable until PD-02 is resolved. | 048 |
| IR-08 | `docs/product-refinement/02-shopify-retirement.md:222` | claims the audit emits `reauthorize`; the task only emits `migrate`/`already_migrated`. | 044 |
| IR-09 | `docs/product-enablement/02-flow-automation-bots-macros-reuse-map.md:165,316` | cites an `enterprise/` file that is not in this repo; must not be used as evidence. | 035 |
| IR-10 | `docs/p7/00-discovery-findings.md:703-705` (SHO-48) | refuted: `locked: true` does not make `INSTAGRAM_API_VERSION` uneditable; the Instagram App Configs form writes it anyway. | 042 |
| IR-11 | Live code comments and OPERATOR-VISIBLE field descriptions at `config/installation_config.yml:510-511,515,520` still describe the retired Shopify callback/webhook/settings as current. | | 044 |
| IR-12 | `docs/commerce/14-zid-oauth-and-tokens.md:139` omits `abandoned_carts.read` from the scope list the code requires. | | 047 |

## XA — for Agent 000 to arbitrate

| # | Question | Why it is mine |
|---|---|---|
| XA-01 | **Meta error-code corpus rule.** The existing 5-article WhatsApp set already mixes codes the product *classifies* (131049, 131042) with codes it only *names* (131053, 131060, 190) — so `delivery_failure.rb`'s "only observed codes" rule is not the corpus's actual rule. 131047 and 131026 were observed in production with no article. Decide the admission rule before 028's master register lands. | Phase 4 decision 4; raised by 040, 054 |
| XA-02 | **PRE_UAT editorial rule.** Shopify/Zid order actions and abandoned carts are fully built but unreachable, and the shipped string implies an operator can switch them on. Decide how the corpus documents a built-but-gated capability without either lying or advertising vapourware. | 043, 044, 047 |
| XA-03 | **"Customer 360" now names two surfaces** — the commerce Overview tab (documented) and the Identities tab (undocumented). One name, one meaning, before either is written. | 031 |
| XA-04 | **Four names for one desk**: namespace `PlatformSupport`, nav "Customer Support", heading "Customer support", tenant "Help & Support → My tickets". The tenant never sees "Platform Support". | 048 |
| XA-05 | **Where does commercial documentation live?** Billing, plans, trials, the 402 lock redirect, usage limits and overrides are all tenant-reachable and have no article and no owning section. `administration` holds one article. | 048, 059 |
| XA-06 | **Fair-distribution defaults disagree**: code says 5 per 5 min with no policy; the policy form's help text says "defaults to 100 per hour". Pick the number the docs state and flag the UI string. | 032 |
| XA-07 | **Agent-limit refusal has two messages and two statuses** for the same wall: a hard-coded English 402 and a translated 422. | 032, 048 |
| XA-08 | **`automation-or-flow-builder.md` is a shared boundary article** verified from one side only (037 did flows, 036 did automation). Needs one Phase-5 owner. | 036, 037 |
| XA-09 | **Arabic provider name**: UI renders Zid as "زد" while the Arabic article says "Zid". Decide once and add to the Crowdin glossary. | 047, 061 |
| XA-10 | **`isMetaInboxCreationDisabled`** is `deploymentEnv === 'cloud' && …`, so the "temporarily unavailable" banner can never appear on a self-hosted install, and its copy attributes an operator switch to a detected Meta condition. Document as-is, or flag to product? | 041, 042 |
| XA-11 | **360dialog** is still a valid `PROVIDERS` value with a working form but has no card in the picker and no article. Code or docs is stale — a product decision. | 039 |
| XA-12 | **Administrator-only emails** (channel disconnects, import/export, automation disabled) have no opt-out and no bell row. Notifications article or administration section? | 034 |

## CH — contextual-help gaps (feed into the Phase-2 coverage matrix)

- `DOC_ARTICLES` has **no notification key at all**, and no notification UI calls `documentationArticleUrl` (034).
- Zero Facebook/Messenger keys and zero Instagram keys; zero articles for either channel (041, 042).
- `macrosOrAutomation`, `flows`, `automationOrFlows`, `sharedAudiences`, `labelsOrAudiences`, `campaigns` exist in the registry and **nothing in the product renders them** (035, 037, 038).
- `DocsLink.vue` is consumed only by Commerce and Platform Support surfaces (038).
- 13 of 17 WhatsApp keys are registry-only; the "cannot reply" banner links to `business.whatsapp.com/policy` rather than `whatsappWindow` (040).
- 12 of 31 `Commerce::Error` codes have no article; `commerceErrorArticle` is wired in exactly one place (043).
- Four contextual-help locations in Contacts have no key, and all four are Lynomia-built features: identities, activity, merge ×2 (031).
- Missing keys for: roles/permissions, agent availability, assignment policies, business hours (032); recipes, waits, commerce triggers, automation analytics, auto-deactivation (036); plan paywall, delete-confirm (033); template-manager `RATE_LIMITED`/`META_UNAVAILABLE`/`CSAT_MANAGED_ELSEWHERE` (040); `STORE_LIMIT_REACHED`, `STORE_ALREADY_CONNECTED`, `ENCRYPTION_NOT_CONFIGURED` (043, 045).
- No `DocsLink` anywhere in `settings/commerce/Index.vue`, the flow UI, or the macros empty state (035, 037, 045).
- Dead/orphaned i18n that would have been the help: `INBOX.REAUTHORIZE.TROUBLESHOOTING.*`, `INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED`, `HAS_ENABLED_PUSH`/`REQUEST_PUSH` (034, 039, 041).

## UV — cannot be settled in Phase 1

- WooCommerce: webhook auto-disable after five refused deliveries; `send_order_details` needing WooCommerce 9.8+; 401-vs-403 on an under-permissioned write (045).
- Salla: the `identity[:domain]` shape; live payload envelopes; Salla is NO-GO in production, so any article inherits the `REAL_SALLA_UAT=BLOCKED` caveat (046).
- Zid: cart identity key and webhook envelope (047).
- Instagram: whether Graph's `subscribed_apps` accepts the bracketed array form; what code Graph returns for an empty access token (042) — routed to 023/024/025.
- Facebook: the actual refusal code for a bad `appsecret_proof` (041) — routed to 021/025.
- Shopify: whether the non-secret retired `SHOPIFY_*` rows are actually present in production (044).
- Platform Support: whether the tenant desk's sweep shares the 5-minute cadence (048).

## Branding / white-label debt (one owner, not per-agent)

Strings that hardcode "Chatwoot" or "Woot" and are rendered without `replaceInstallationName`:
`INBOX_MGMT.ADD.FB.RESTRICTED_WARNING` (041); Instagram `RESTRICTED_WARNING`, `SETTINGS_RESTRICTED_WARNING`,
`CONVERSATION.INSTAGRAM_RESTRICTION_BANNER` (042); three agent-flow strings in `agentMgmt.json:48,55,91` (032);
`cannedMgmt.json:41,63,70` "Could not connect to Woot server" (035); `featureHelper.js:61` pointing at upstream
Chatwoot's retired-integration article (044).

---

# Addendum 1 — agents 029, 030, 070

## BLOCKER — the authoring surface silently breaks contextual help

**B-01. Every Super Admin article save destroys `meta['doc_key']`.** `ArticleMetaField` does not carry it in
`STRING_KEYS`, does not permit it, and does not render it in the form, and Administrate replaces the whole jsonb
on update (`custom/app/fields/article_meta_field.rb:13,33-35`; `administrate-0.20.1 application_controller.rb:59-60`).
English survives only by the slug fallback in `Documentation::Library#article_for`
(`library.rb:55-56`); **Arabic does not — it silently starts serving the English article.** Reported by 070.

This is the keystone finding for Phase 4. It means the existing authoring surface is not merely basic: it is
*lossy*, and it breaks the one contract (`doc_key`) that the product's contextual help depends on. Nothing may be
added to `meta` until this is fixed, and it must be fixed before, not after, the editor upgrade.

## PD — additional product defects

| # | Finding | Evidence | Reported by |
|---|---|---|---|
| PD-36 | Conversation bulk actions have **no `authorize` call** for the Conversation branch (the Contact branch is authorized), are fire-and-forget (`head :ok` on enqueue), use non-bang `update`, alert success on enqueue, and have no completion broadcast. | `bulk_actions_controller.rb:12-24,32-38`, `bulk_actions_job.rb:25-32`, `useBulkActions.js:212` | 029 |
| PD-37 | A failed conversation status change reports success — `toggleStatus` swallows every error, and both call sites alert unconditionally. `CONVERSATION.CHANGE_STATUS_FAILED` exists in `en.json` and is referenced nowhere. | `store/modules/conversations/actions.js:387-389`, `ResolveAction.vue:98-101`, `ChatList.vue:781-783` | 029 |
| PD-38 | Reopening a colleague's conversation silently takes it over: `handle_human_open` sets `assignee = Current.user` with no check for an existing assignee, and the response omits the assignee so the UI never shows it. | `conversations_controller.rb:92,180-186`, `toggle_status.json.jbuilder:4-9` | 029 |
| PD-39 | Required-conversation-attributes-before-resolve is browser-only; no server guard exists, so the API, automations, macros and `ResolutionJob` all bypass it. (Same shape as PD-15 for macros — one missing gate, two surfaces.) | `useConversationRequiredAttributes.js:13-91`, `app/models/concerns/account_settings_schema.rb:19` | 029, 035 |
| PD-40 | Snooze has a silent 3-day recovery window: the reopen job selects only `snoozed_until: 3.days.ago..Time.current`, so a scheduler outage longer than that leaves conversations snoozed permanently. Notifications have the identical defect. | `ReopenSnoozedConversationsJob:5`, `reopen_snoozed_notifications_job.rb:5` | 029, 034 |
| PD-41 | Deep-linking to a conversation you cannot see fails silently — `getConversation` swallows the 404/403 and the panel says "Please select a conversation from left pane". | `actions.js:82-84`, `EmptyState.vue:43-48` | 029 |
| PD-42 | Attachment **type** is validated almost nowhere: the check runs only in the paste handler, `accept` is an overridable hint, drag-and-drop bypasses it, and server-side validation returns early unless the inbox is a web widget. A `.exe` dropped on a WhatsApp conversation uploads and fails at Meta. | `ReplyBox.vue:783-800`, `app/models/attachment.rb:186-192` | 030 |
| PD-43 | Attachment **size** is client-only for every non-widget channel; the server re-checks only the web widget. The `:size="4096 * 4096"` hint on the picker is dead config. | `@chatwoot/utils fileUploadRules.ts:107-212`, `attachment.rb:208-213`, `ReplyBottomPanel.vue:287` | 030 |
| PD-44 | A send that fails before reaching the server **loses the agent's typed text**: the editor is cleared without awaiting, the autosave watcher then overwrites the draft with `''`, and `removeFromDraft` runs only on success. | `ReplyBox.vue:841-878,600-611,965` | 030 |
| PD-45 | Server validation errors reach agents as raw untranslated ActiveRecord strings ("Validation failed: Attachments exceeded maximum allowed", "Too many messages") via a 422 and a verbatim toast. | `request_exception_handler.rb:46-48,87-91`, `ReplyBox.vue:974-980`, `message.rb:289-299,445-447` | 030 |
| PD-46 | No message policy exists — anyone who can open a conversation can reply, note, delete and retry; it all hangs off `ConversationPolicy#show?`. | `base_controller.rb:6-9`, `custom/app/policies/custom/conversation_policy.rb:40-42` | 030 |
| PD-47 | The new-conversation composer passes the wrong shape to `useFileUpload` (`isATwilioSMSChannel` where `inbox` is expected), losing channel limits; with direct uploads on it posts to `/conversations/undefined/direct_uploads`. | `ActionButtons.vue:122-137`, `useFileUpload.js:76-84` | 030 |
| PD-48 | Drafts are per-browser `localStorage` only; the Redis draft endpoint has zero callers, and `draftMessages/delete` never removes keys, so the store grows forever. | `draft_messages_controller.rb`, `draftMessages.js:23-25,39-43` | 030 |
| PD-49 | `Article` has **no slug uniqueness validation**, so a collision is a 500 and a Sentry report rather than a 422 — against this repository's own stated rule. The duplicate-canonical ERROR in the SEO audit is therefore structurally unreachable (the DB index catches it first), and its spec has to stub `Article#slug` to reach the branch. | `app/models/article.rb:65-69`, `spec/.../task_documentation_seo_audit_spec.rb:50-56` | 070 |
| PD-50 | `slug` is freely author-editable and is the canonical URL. Renaming it breaks canonical, hreflang and sitemap with no redirect, **and makes the next seeder run create a duplicate article at the old slug** that nothing ever deletes — duplicate content the audit cannot see. | `article_dashboard.rb:36`, `content_seeder.rb:73` | 070 |
| PD-51 | `meta['feature_image']` is labelled, hinted, permitted and form-rendered, and is read by nothing. Dead field. | its three declarations only | 070 |
| PD-52 | `locale` is editable in the article form but is overwritten from the category on save. | `article.rb:200-206` | 070 |

## Defects in the SEO audit itself

| # | Finding | Evidence |
|---|---|---|
| SA-01 | The title-length warning measures the wrong field: it checks `article.title` while the page renders `meta['title']` when present. It flags 4 EN files that all already carry a compliant `seo_title`. | `documentation_seo_audit.rake:73-74` |
| SA-02 | The rendered `<title>` is `article.title + " \| Lynomia Chat Documentation"` — a 29-character suffix the audit never counts. **27 of 126 articles render a `<title>` over 60 characters**; the audit reports 4. | `_meta_head.html.erb:10`, `portal_seeder.rb:12` |
| SA-03 | A hostless canonical yields `https://hc/...` and **passes** the "canonical has a host" check. Unverified for the production environment. | `documentation_helper.rb:29-33`, `chatwoot_app.rb:35-37` |
| SA-04 | The `ArticleMetaField` hint "Overrides the `<title>` and og:title" is false — `meta['title']` overrides og/twitter/meta-name only, never `<title>`. The design record is correct; the operator-facing hint is not. | `article_meta_field.rb:25` vs `docs/global-documentation/07-super-admin-management.md:92` |

## DC — additional corpus contradictions

| # | Corpus claim | Reality | Owner |
|---|---|---|---|
| DC-22 | `work-in-the-inbox.md:105-106` muting means "nothing further from that person opens a conversation" | the conversation IS created, already resolved; and unmute never reopens it | 050 |
| DC-23 | same article names a "mute" control | the UI reads "Block Contact" / "Unblock Contact" | 050 |
| DC-24 | `canned-responses.md:99` "nothing checks that your variables are spelled correctly" | send is blocked behind an "Undefined variables" confirm dialog | 050 |
| DC-25 | `canned-responses.md` self-contradicts: `:112` a misspelled variable arrives "as literal text", `:99` "rendered as nothing" | Liquid renders every outgoing body on create, so "nothing" is the likely truth — needs one verified answer | 050 |
| DC-26 | `assign-and-prioritise.md` assigning a bot sets pending and clears the human assignee | verified at creation only; the assignments controller changes no status | 050, 032 |

## Corpus facts worth keeping (measured, not asserted)

From 070, measured across all 126 files: `seo_description` present on **126/126**, all within the 50–160 window.
`seo_title` present on **28**. Tags: 1–3 per article, **32 distinct values, zero singletons** — a controlled
vocabulary held by review rather than by code. Tags are reader-visible pill badges on every documentation page,
although the field hint calls them changelog-only. Two wire formats exist for tags: a comma string from Super
Admin, and `tags: []` from the account API.

## XA — added

| # | Question |
|---|---|
| XA-13 | **A "UI offers what the server refuses" pattern now appears seven times** (PD-10, PD-11, PD-12, PD-13, PD-07, PD-08, and the `conversation_participating_manage` "All" tab that equals "Mine"). This is a product-wide honesty defect, not seven documentation gaps. Decide whether the corpus describes the server's truth, the UI's offer, or refuses to document the surface until it is fixed. My position: the corpus documents the **server's** truth and the Phase-5 owner gets the list. |
| XA-14 | **Author-time SEO validation is worthless in Administrate alone**, because `ContentSeeder` overwrites `meta` wholesale on the next run. 070 recommends one shared rule object called from the form, a CI front-matter check, and `seo_audit`. This depends entirely on the §8.1 source-of-truth freeze, and is the strongest argument yet for a controlled hybrid rather than a pure database-canonical model. |
| XA-15 | Adding `validates :slug, uniqueness: true` touches a shared OSS model used by every tenant help center. 064 must confirm no tenant flow depends on the current exception before PD-49 is fixed. |

---

# Addendum 2 — the editor/SEO/security and Meta research waves

## URGENT — production risk, time-critical, owner decision required

These are not documentation items. They came out of the Meta research wave and they have dates attached.

| # | Risk | Evidence | Why it is urgent |
|---|---|---|---|
| U-01 | **Embedded Signup v2 is deprecated on 2026-10-15 — two days from today.** Meta carries this banner on five pages. v4 changes the post-flow contract materially: users can finish with a verified, unverified, or *no* phone number, where v2 required a verified one, and "the `extras` object is purposely empty for v4", so the entire pre-filled-data contract is v2-only. | agent 013, `developers.facebook.com/docs/whatsapp/embedded-signup/versions` | If this installation runs v2, WhatsApp onboarding for new customers stops working in two days. I could not determine the version from the repository — the code has no version or `config_id` literal; it is supplied at runtime. **The owner must check the Meta app's Embedded Signup configuration version now.** |
| U-02 | `FACEBOOK_API_VERSION` defaults to **v18.0**, whose availability ended **2026-01-26**. Only one server-side reader exists and it merely publishes the value to the browser, so the Super Admin control does not do what its description claims. | agent 003 (`app/controllers/dashboard_controller.rb:85`, `config/installation_config.yml:152-156`), agent 041 | Past end-of-life. |
| U-03 | Messenger **send** and page **subscribe/unsubscribe** are pinned at Graph **v3.2** inside a vendored gem, and all Page reads are unversioned Koala calls. | agent 041 (`vendor/.../facebook-messenger-2.0.1/lib/facebook/messenger/bot.rb:16`, `subscriptions.rb:12`) | v3.2 is many years past end-of-life. Agent 090 is verifying what Meta returns for it today. |
| U-04 | A legacy Instagram send path is pinned at **v11.0**. | agent 042 (`app/services/instagram/messenger/send_on_instagram_service.rb:9,34-36`) | Same class. |
| U-05 | WhatsApp billing: `/pricing/non-template-messages` says service messages and in-window utility messages become **charged** "Effective October 1, 2026", while the main `/pricing` page still says both are free, and the changelog has no entry confirming it took effect. Today is 2026-10-13 — past the date. | agent 008 | Affects what any cost article may claim, and possibly customer invoices. Must be re-checked immediately before publishing anything about cost. |

Graph API version status as of 2026-10-13, derived by agent 001 from Meta's own version table (arithmetic, not a
Meta label): **v26.0 current** (released 2026-07-29); v20.0 passed its end date 2026-09-24; **v21.0 is the lowest
still in window**. Agent 091 is producing the full repository version inventory.

## BLOCKERS — confirmed by multiple independent agents

| # | Blocker | Agreed by | Status |
|---|---|---|---|
| B-01 | **Every Super Admin article save destroys `meta['doc_key']`.** English is masked by a literal-slug fallback; **Arabic contextual help silently serves the English article**. | 064, 069, 070 — three independent readings | Confirmed. Nothing may be added to `meta` until fixed. 064 proposes promoting `doc_key` to an indexed column with `UNIQUE (portal_id, locale, doc_key)`, which fixes it structurally rather than by remembering to merge. |
| B-02 | **All 494 Arabic internal links resolve to the English article.** AR slugs are `<key>-ar`, the article route has no locale segment, the renderer emits the href verbatim, and there is no `<base>` or JS rewrite. The Arabic corpus is navigationally unusable. | 073, 076, 085 — three independent readings | Confirmed. Same bug class as B-03. |
| B-03 | **`/docs/:article_slug` has no locale in its route**, so `article_for(key, locale: nil)` always falls back to English: **every contextual-help click from the dashboard lands in English**, whatever the reader's language. | 073, 076 | Confirmed. B-02 and B-03 are one decision, not two. |
| B-04 | **Editing `slug` creates a duplicate, not a rename.** The seeder upserts on `(slug, locale)`, so the next run creates a second published row carrying the same `doc_key`; which one a help link opens is undefined, the SEO audit cannot see it (different canonicals), and nothing ever deletes it. | 069, 070, 074 | Confirmed. `slug` must leave the form. |
| B-05 | **Every other operator edit is silently reverted** and `status` is force-published on each run, and `Article` is **not audited**, so the revert is unrecoverable and invisible — the task prints one aggregate line. | 069, 070 | Confirmed. |
| B-06 | **No working retirement path.** Deleting the `.md` retires nothing; `archived`/`unpublish` work but are force-republished on the next run. | 069, 074, 079 | Confirmed. |
| B-07 | **The seeder is not single-run convergent.** A file moving between sections fires `after_save :category_id_changed_action`, which `update_column`s position to max+10 and discards the front-matter position; it heals only on a second run. | 069 (inferred from the callback chain, not measured) | **A sync that is not convergent cannot be a deploy gate.** Agent 097 is verifying. This is the single most important fact for the deployment decision. |
| B-08 | **An author can publish third-party `<script>` with one Markdown link.** `config/markdown_embeds.yml` turns a bare link into raw embed HTML for 11 providers; Wistia and GitHub Gist emit `<script>` tags, interpolated verbatim with no sanitizer pass. Gist content is attacker-authored. The portal CSP is `object-src 'none'; base-uri 'self'` and nothing else. | 065, 085 | Confirmed, reachable today. The corpus uses **zero** embeds, so removing those two providers costs nothing. |
| B-09 | **`?show_plain_layout=true` — the Super Admin preview URL — deletes `X-Frame-Options`** with no `frame-ancestors` to replace it. Any site can frame any article. | 065 | Confirmed. |
| B-10 | **`![](data:image/png;base64,…)` publishes a live inline image.** The URL sanitizer deliberately allows image data URIs. This bypasses every media control the program is about to build — no blob, no filename, no EXIF step, no review — and it is permanent in git. | 087 | Confirmed. **Must be closed before Phase 5 writes any image**, or the media contract is unenforceable by construction. |
| B-11 | **`/docs` publishes a named staff byline and avatar on every article and category page**, where the avatar may be a personal Gravatar fetched from the staff email. This contradicts the product's own written policy, which forbids publishing a staff name and is implemented in the JSON-LD only — the HTML body two files away publishes name *and* photo. | 087 | Confirmed, and it is a contradiction in shipped code rather than an ambiguity. The policy is right; the view is wrong. Fix scoped to the `documentation` variant only — the classic layout serves tenant portals, where a byline is the tenant's own choice. |
| B-12 | **Portal search has no index at all** — no GIN/GiST, no tsvector column; the vector is built per row per request and the matching subquery is `model.unscoped`, so every documentation search scans the whole installation's articles table. The model's own TODO names exactly this. | 077 | Confirmed. Breaks at the corpus size this program will produce. |
| B-13 | **The primary search UI throws the ranking away.** The hero/⌘K typeahead reorders by `position` *after* searching, wiping `ORDER BY rank DESC`, and it is **unlimited** — no `per_page` — while CommonMarker-rendering every matching body. Only `/search` is ranked and paginated. | 077 | Confirmed. |
| B-14 | **The search dictionary is `simple` by default and was never chosen**, so there is no stemming, no stopwords and no unaccent in either language, and all terms AND together. "why is my whatsapp message failing" returns zero. `meta` — `seo_title`, `seo_description`, `tags` — is **write-only and unsearchable**: the three fields authors fill in for findability do not affect findability. | 077 | Confirmed. Good news: `131049` *does* find its article today, through the A-weighted title, because digits survive `simple`. |

## Corrections to my own documents

| # | What I wrote | What is true | Who caught it |
|---|---|---|---|
| C-01 | §5: "no `sanitize` call appears… CommonMark's `:DEFAULT` does not escape raw HTML unless `:SAFE`/`UNSAFE` says so", question left open | Raw HTML is **deleted** (`<!-- raw HTML omitted -->`), not escaped. There is no sanitize call because no author HTML is ever emitted. Saying "escaping" is how someone later reasons their way to enabling `:UNSAFE` — which would also *not* enable `tagfilter`, because the renderer is built with `extensions: []`. | 065, 071 |
| C-02 | §8 listed x-default, hreflang self-inclusion and duplicate-canonical as live audit errors | None can fail for a published article. The duplicate-canonical branch is unreachable because the DB's unique index catches the collision first. | 070, 073 |
| C-03 | §7: "`DOC_ARTICLES` — 87 keys" | **62 keys** (plus 19 `COMMERCE_ERROR_ARTICLES` mappings = 81 `key: 'value'` lines). I verified this myself after the challenge. | 076 |

All three are now corrected in `01-current-system.md`, with the correction and its evidence left in place rather
than quietly overwritten.

## Decisive findings for the Phase 4 contracts

**Source of truth.** Agent 069 recommends **Option C, controlled hybrid with files canonical by default**, and the
mechanism matters: the detachment marker must be a **column** (`doc_source`, `doc_detached_at`), not a `meta`
key, because both writers replace `meta` wholesale. The precedent already exists in this repository
(`db/migrate/20260623000000_add_draft_columns_to_articles.rb`). The seeder skips and *reports* detached rows,
with a non-zero exit so it can gate. Retirement becomes front-matter `retired: true` → `archived`, and the file
stays. Three prerequisite fixes are nearly one-liners: merge `meta` instead of replacing it, drop `slug` and
`locale` from `FORM_ATTRIBUTES`, and stop forcing `status`. `audited` on `Article` is a prerequisite of any
edit-permitting option, and `docs/global-documentation/10-global-docs-implementation.md:120` explicitly deferred
it. **A/B/C cannot be frozen until B-07 is settled** — under Option A with a non-syncing deploy, the corpus
cannot be corrected at all, including taking down something wrong.

**Editor.** Agent 071 establishes that raw HTML is impossible on **both** sides — the server omits it and the
editor's own schema cannot represent it (`html: false`, no `html_block` node). The corpus has **no callout
convention to inherit** (zero uses of Note/Warning/Important/Tip/Caution as labels), and cautions were instead
routed into `## Limits` (52 files), `## If it does not work` (39) and `## Who can do this` (45). Recommendation:
one component — a callout with two variants, Note and Warning — expressed as `> **Note** — …` and recognised by a
renderer override, with labels declared in YAML on the existing `config/markdown_embeds.yml` pattern. It
round-trips byte-exact. `> [!NOTE]` is **provably broken** here, because prosemirror-markdown escapes `[` and
`]`. Steps, tables, UI paths and key names are **already** the component set — written down, measured, not to be
replaced.

**But 071 found a blocker under the editor itself**: the round trip is **already lossy for ordinary prose**.
`softbreak` becomes `hard_break` with `breaks: true`, and `hard_break` serialises as `'\\\n'` — so every
~110-column wrap in all 126 files becomes an explicit `<br />` on the first editor save. The component set cannot
be frozen until 067 and 069 arbitrate that.

**Arabic/RTL.** The public documentation layout emits `lang` but **never `dir`**
(`app/views/layouts/portal.html+documentation.erb:2`); `dir="rtl"` arrives only from JavaScript after first
paint, so an Arabic article paints LTR and stays LTR if the script fails. Three agents flag it (069, 071, 072).
An RTL preview cannot be built on a layout that has no RTL. Tailwind Typography itself is already fully
logical-property based, and the corpus already mirrors UI-path arrows per locale (EN 141 `→` / 0 `←`; AR 137 `←`
/ 2 `→`), so the convention is real — it is the layout that is missing.

**Meta documentation has moved.** `/docs/whatsapp/**` → `/documentation/business-messaging/whatsapp/**`. Several
old URLs are redirect stubs, 404s, or navigation-only shells, while a few pages serve *only* from the old path.
Agent 010 found the decisive technique: **appending `.md` to any path in
`developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt` returns the full plain-text
article.** Every Meta URL in the corpus and in the code needs re-checking, and the program must freeze one URL
convention before Phase 5. Reported independently by 001, 005, 009, 010, 011, 012, 013, 014.

**The error taxonomy question is now answerable.** Agent 005 reproduced ~100 published WhatsApp codes across
Meta's ten sections; the corpus has per-code articles for **4** of them. Three facts decide the model:
Meta publishes **no HTTP status** for send failures and says to build handling on `code` and `error_data.details`
rather than subcodes or status; **`error_subcode` is not returned by Cloud API v16.0+**, so any taxonomy keyed on
subcode is wrong; and **code 2388103 carries 11 distinct failures under one code**, discriminated only by the
string Meta tells you not to depend on. Agent 005 also found that **131060 is not a request-time failure at all**
and the existing corpus article is scoped to the wrong channel, and that **code 368 contradicts itself across
Meta's own pages**. Agent 011 adds that 132001 conflates "template does not exist in that language" with "not
approved" — two different user fixes behind one code — and that **no language fallback exists anywhere in Meta's
docs**, so `(name, language)` must be treated as the lookup key.

---

# Addendum 3 — media, retirement, Meta depth

## Media: the finding that reframes the whole media decision

Agent 068 established that **the media authoring UX already exists and ships**: `FullEditor.vue` does picker,
drag-and-drop at the drop position, paste, external-URL rehost, progress, failure/retry/remove, cancel,
drag-resize and a pending-upload navigation guard. Rebuilding any of it is duplication. It is unreachable from
documentation authoring for two reasons that have nothing to do with media: the dashboard editor resolves portals
as `Current.account.portals` while documentation portals are account-less, and **no upload endpoint answers a
`:super_admin` session**. Super Admin can already mount Vue (`render_vue_component`), so that is the extension
point. Only three genuinely new primitives are needed: an alt/decorative/caption panel, a drop-target highlight,
and a publish-time missing-alt blocker. **Required alt text is the only part of the scope with zero precedent
anywhere** in the editor, schema, insert path, renderer or SEO audit.

Agent 066 then found the fact that decides the media model, and it contradicts my own charter table:

> **An ActiveStorage signed id is a `message_verifier("ActiveStorage")` over the blob's primary key, keyed from
> `secret_key_base`. A blob URL committed into the git-canonical corpus is valid in exactly one database.**

So "Media → ActiveStorage" as written in `00-program.md` §2 cannot mean "commit `url_for(blob)` into a Markdown
file". Agent 066 recommends **Option D**: media files live beside the Markdown in the repository, referenced by a
stable `media:` key (never a URL), uploaded idempotently by checksum by the existing `ContentSeeder`, attached to
the platform **Portal** rather than the Article (because the seeder rewrites Articles wholesale), resolved at
render time per call, raster only, originals not variants, alt text required at the seed boundary. Agent 068
independently reached the same blocker from the UX side. **I am treating this as the leading candidate and will
freeze it in Phase 4 after 083 and 084 report.**

Supporting facts, all cited in the reports: production storage is **local Disk** unless overridden, and
**staging sets no service at all**; `urls_expire_in` is nil, so every `url_for(blob)` is a permanent
unauthenticated redirect URL; SVG is already forced to `octet-stream` + attachment, which is what closes upload
XSS, so the inline-SVG question is a sanitizer question and not a storage one; the existing article-image path
mints **orphan blobs with no validation and no reclamation**, and is account-scoped so a Super Admin author
cannot reach it; and the house pattern in `custom/` is deliberately an authorized streaming controller rather
than `rails_blob_path` — zero uses, with two code comments and a spec enforcing it.

## Retirement: a complete minimum design, from 079

No redirect mechanism exists anywhere — no model, table, gem, rack rewrite or route redirect, and `nginx` is a
sample config the deploy never touches. **No article has ever been deleted or renamed in git history (0 D, 0 R
across the corpus),** which is why nobody has hit this yet. `archived` already exists and is already excluded
from the sitemap, search, hreflang, `Library`, the home page and the SEO audit — so no new status value and no
new `meta` key is needed. Recommended minimum: `retired: [{key, to?}]` in `manifest.yml`, append-only, where `to`
must be a live key so there is one hop and no loops; an in-memory map in `Library`; **301** to a published
successor, **410** when there is no successor, 404 unchanged for unknown or draft. The redirect must **not** live
in article `meta`, for exactly the reason B-01 names.

A detail worth keeping: a retired `DOC_ARTICLES` key opens a **blank 404 tab**, because `DocsLink` uses
`target=_blank`. CI guards corpus files only — never the database, never external links.

## A possible live production defect, unverifiable from here

Agent 079 noticed that the baseline has **126** corpus files while the reported production run processed
**124** articles. The two-file gap matches one commit, `48574e65`, which added `contact-lynomia-support` in both
locales. **If production predates that commit, the `contactLynomiaSupport` product link — the Platform Support
Desk's only documentation link — 404s live today.** This needs one production read, which Phase 1 forbids;
recorded for the owner.

## Meta research: the facts that change existing articles

These are not gaps. They are things the shipped corpus currently states incorrectly, or omits where the omission
misleads.

| # | Finding | Source agent |
|---|---|---|
| M-01 | **A voice call now opens and resets the 24-hour window**, not just a message. No Lynomia article says this. | 016 |
| M-02 | The window error is **131047**; **code 470 does not appear on Meta's error page at all** — it was the On-Premises code, and On-Premises sunset 2025-10-23. | 016 |
| M-03 | **Free entry points are a separate 72-hour window** (click-to-WhatsApp ads, Page CTA), and are the only documented way to send a non-template message outside the service window. Absent from Lynomia entirely. | 016 |
| M-04 | Inside the window Meta permits a **closed list of 16 service message types** — "any service message type" is not "anything". **Read receipts are not window-gated** (30 days); typing indicators need an inbound wamid within 25 s. Reactions and media *are* gated. | 016 |
| M-05 | **Inbound customer media expires in 7 days, not 30** — cut from 30 on 2025-10-09. A retrieved media URL lives **5 minutes**. Media Lynomia uploads: 30 days. Three lifetimes, easily conflated. | 019, 020 |
| M-06 | The media download is **token-authenticated, not pre-signed** — the URL cannot be handed to a browser or a third party. Every failure is one bare `404`: expired URL, expired ID, deleted asset and bad token are indistinguishable. | 020 |
| M-07 | **Per-type media size limits**: audio 16 MB, document 100 MB, **image 5 MB**, video 16 MB, sticker 100 KB static / 500 KB animated. Image is 5 MB, not the 100 MB platform ceiling. WebP is sticker-only. | 019 |
| M-08 | **Template pause durations are 3h / 6h / disabled** — not the widely-repeated "3h/6h/24h". Template *Pacing* is a second, distinct pause that does **not** self-clear and needs a manual `POST /{id}/unpause`. | 010, 011 |
| M-09 | **Meta re-categorises approved templates**: utility→marketing with one day's notice, or none since 2025-04-16 after a warning, staying APPROVED; marketing/utility→authentication sets the template **REJECTED on the 1st of the following month**. | 008, 010 |
| M-10 | Messaging limits are **250 / 2,000 / 10,000 / 100,000 / Unlimited**, counted as unique recipients messaged **outside** a window per moving 24h — not a message count. The step off 250 is **gated**, and business verification is the highest-leverage operator action. Above 2,000, scaling needs quality **and** ≥half the current limit used in 7 days, so steady low-volume senders never advance. | 018 |
| M-11 | **Throughput is a third, separate thing**: 80 mps default, up to 1,000, coexistence fixed at 20, **inclusive of inbound**, exceeded → 130429. Lynomia's `whatsapp-quality-and-limits.md` omits throughput entirely, and its "Rate limited on the number's status" is not Meta vocabulary. | 018 |
| M-12 | **Per-message pricing has been live since 2025-07-01**; conversation-based pricing is deprecated, and on v24.0+ the `conversation` object is **omitted entirely** except inside an open free-entry-point window — so cost attribution by `conversation.id` is no longer reconstructable. | 008 |
| M-13 | A **fourth approval gate** exists that nobody documents: **Access Verification as a Tech Provider**, explicitly independent of App Review and permission access levels, failing with error 100. Onboarding is throttled to **10 new business customers per rolling 7 days** by default, 200 after all three verifications. | 027 |
| M-14 | **Instagram no longer requires a linked Facebook Page** on the Instagram-Login path — which is the path Lynomia uses, and its scope request matches Meta's current reference exactly. The Facebook-Login path still requires one. | 023 |
| M-15 | Instagram's **"Connected Tools → Allow Access to Messages"** toggle is the top onboarding failure, and Meta documents it **only** on the Facebook-Login page — whether it gates the Instagram-Login path is not stated anywhere. | 023 |
| M-16 | Meta documents, as designed behaviour, that messages handled through the API are **not marked read in the Instagram app inbox** until a reply is sent, and that "inbox folders are not supported". Both read as Lynomia bugs. | 023 |
| M-17 | **Handover Protocol is retired for Instagram** as of 2025-10-23. | 023 |
| M-18 | **Expired and revoked tokens are indistinguishable** from any error response — Meta maps 102/190/463/467 to one meaning with one handling. **`error_subcode` is not returned by Cloud API v16.0+**, so any Lynomia taxonomy keyed on a WhatsApp subcode is wrong. Tokens are **opaque** — Meta says do not parse, decode or assume a format or maximum length. | 001 |
| M-19 | **Error code 200 is overloaded**: "no access token provided" *and* "the token's user lacks access to the resource" — a permission problem and an asset-access problem, one code, two completely different fixes. This is the most common multi-tenant connect failure and no article explains it. | 001, 003, 004 |
| M-20 | **Embedded Signup does not register the number.** Registration is a separate API call with a 6-digit PIN, and is **capped at 10 register/deregister per number per 72 hours** → error **133016**, which blocks registration for 72 hours. A business guessing a forgotten PIN can lock its own number out for three days, and Meta documents no wrong-PIN error at all. | 013, 014 |
| M-21 | **Adding and verifying a number is not registering it**, and registration is API-only — not possible in WhatsApp Manager. `health_status` / `can_send_message` (AVAILABLE / LIMITED / BLOCKED) is the only field that answers "can this number send" and evaluates phone number, WABA, business and app in one call — it belongs at step 0 of any triage article. | 014 |
| M-22 | **Display-name approval does not apply the name** — re-registration does, within a 14-day window, or the name returns to review. | 014 |
| M-23 | Meta publishes **no `status` enum** for a phone number (only `CONNECTED`), no `code_verification_status` enum beyond `VERIFIED`, and **no definition of any `quality_rating` value**; the quality-rating pages are JS-gated and unreadable by fetch. No article may assert a value. | 014, 018 |
| M-24 | **`phone_number_quality_update` is now documented as a throughput webhook** — events `ONBOARDING` and `THROUGHPUT_UPGRADE` only, with no quality-rating field and no FLAGGED/UNFLAGGED. Any Lynomia code parsing it for quality drops is at risk. | 014 |
| M-25 | **No webhook reports a number going blocked or disconnected.** Health must be polled. | 014 |
| M-26 | **Meta's own pages contradict each other** in ways the corpus must not paper over: 131052 has two different titles on two normative pages; code 368 is a temporary block on one page and a policy restriction on another; webhook retry is 7 days on one page and 36 hours on another; MPM allows 30 products "across all sections" and "30 per section" in the same page; field casing is inconsistent (`CATALOG` vs lowercase, `format: location` vs `LOCATION`); and `index` appears as both integer and string. | 005, 006, 011, 012, 019, 020 |
| M-27 | Meta's **documentation tree has moved** from `/docs/whatsapp/**` to `/documentation/business-messaging/whatsapp/**`, with some pages serving only from the old path and some only from the new, several 404s, and several JS-only shells. **Appending `.md` to any path in `/documentation/business-messaging/whatsapp/llms.txt` returns the full plain-text article** — that is the technique that worked. Every Meta URL in the corpus and the code needs re-checking, and the program must freeze one URL convention. | 001, 005, 009–014, 016, 018, 027 |

## Unverified by design, and recorded as such

Meta's quality-rating pages, the accepted-document lists for business verification, Page access levels, and
several Business Help articles are **client-rendered and return only a title** to a plain fetch. Nothing from
them has been published as fact. Agents 002, 004, 014, 018, 023 and 027 all hit this and all recorded it rather
than filling the gap from memory, which is the behaviour the contract asked for.

## XA — added

| # | Question |
|---|---|
| XA-16 | **Charter §2 says "Media → ActiveStorage".** Agent 066 shows that cannot mean committing blob URLs, and proposes repository-canonical media files with a `media:` key. Agent 068 agrees from the UX side. I must either amend that charter row or state the `media:`-key reading explicitly — an agent should not have to guess. |
| XA-17 | **Is Access Verification a hard gate or a limit-raiser?** Four Meta pages disagree. This decides whether the onboarding critical path has three gates or four, which is the spine of the WhatsApp onboarding article. |
| XA-18 | **Portfolio vs phone number for messaging limits.** Meta's own page uses both scopes and never reconciles them. It decides whether "will a second number double our capacity?" is yes or no. No article may state a scope until this is settled. |
| XA-19 | **Is a service reply billable from 2026-10-01?** Two Meta pages disagree and the date has passed. Blocks any cost article. |
| XA-20 | **Charter §6.2 calls Meta changelogs normative in one sentence and observational in another** (agent 023 caught this). Six deprecation facts rest only on a changelog. I must rule: a changelog entry is **normative for the fact that a change was announced and dated**, and observational for any behaviour it does not spell out. |
| XA-21 | **The 005/006 boundary is a Lynomia invention.** Meta does not partition request-time from webhook errors and explicitly says to monitor both. No article may say "at send time you get X" until the taxonomy settles this. |
| XA-22 | **`recent_buyers` preset selects the opposite of its own copy** (agent 052): the date operator means "more than N days ago", so the preset targets lapsed customers while the copy promises recent ones. Three corpus articles repeat the inversion. Fix the preset, the operator, or the docs — a product answer is needed before those articles can be corrected. |

---

# Addendum 4 — the security wave, and the most serious finding of the program

## SEC-01 — BLOCKER: a tenant can publish into Lynomia's public documentation portal

**Agent 086, confirmed by reading three files that each look correct on their own.**

The write path: the tenant article API permits `category_id` **unchecked**
(`app/controllers/api/v1/accounts/articles_controller.rb:108-115`). No `Article` validation ties the chosen
category's portal to the article's portal. The read path: the public category page lists `@category.articles`
**unscoped by portal** (`app/controllers/public/api/v1/portals/categories_controller.rb:32`).

So a tenant account administrator can point their own published article at a **platform** documentation category,
and it renders on Lynomia's public `/docs` — title, excerpt, and the tenant's own agent names and avatars
(`documentation_layout/categories/_header.html.erb:1,5-11`).

It is not XSS: `to_plaintext` is not `html_safe`. It is worse in a different way — it is **unauthorized
publication on the vendor's own documentation domain**, by any customer, with no audit trail (SEC-03 below).

This is the one finding in the program I would class as release-blocking on its own, and it is **pre-existing**,
not created by anything this program proposes. The platform/tenant boundary that the whole documentation design
rests on is asserted nowhere and enforced only by `scoped_resource`, which scopes *lookup* and not *assignment*.

**Routed to agents 096 and 081 to attack independently before Phase 4 freezes the content model**, and to the
owner now, because it is live.

## SEC-02 — MAJOR: `portal_id` is mass-assignable in Super Admin, and the damage is permanent

Agent 086 answered the exact question I set: **`Field::BelongsTo.with_options(scope:)` only builds the `<select>`
options** (`belongs_to.rb:43-48`); `permitted_attribute` is the bare foreign key (`:6-13`). `scoped_resource`
scopes lookup only (`:183-195`). Same for `category`.

So a Super Admin save can set `article[portal_id]` to a tenant portal. Then `before_validation
:ensure_account_id` (`article.rb:58,230-232`) **transfers the row to that tenant's account**; the article
disappears from `scoped_resource` so Super Admin can no longer see or fix it; the tenant's admins get full CRUD
over it; and the next `rails documentation:content` **raises `RecordNotUnique` on the global slug index and
aborts permanently** (`content_seeder.rb:73,80`). One mis-click takes the content sync down until someone opens a
Rails console.

Worse, `create` **never consults `scoped_resource` at all** (Administrate `application_controller.rb:42-46`), so
a Super Admin can create an article directly in a tenant portal with no mistake required.

And one checkbox is worse still: **`archived` is a permitted Portal attribute** (`portal_dashboard.rb:31`) while
`Documentation::Library.portals` is `.active` — so archiving the portal removes the entire documentation surface
from both Super Admin and `/docs`, **with no UI path back**.

**This bears directly on §8.1.** A re-seed cannot heal a moved row, because it dies on the slug collision
first. Any hybrid source-of-truth answer must define the behaviour of a row whose `portal_id` no longer
satisfies the platform predicate.

## SEC-03 — MAJOR: documentation authoring is entirely unaudited, and the usual fix does not work

No capture point for `Article`, `Category` or `Portal` exists in `custom/app/models/custom/audit/`. And the
`audited` macro **cannot** fix it: its Sweeper resolves the actor via `current_user`
(`audited-5.4.1 sweeper.rb:5-9,22-24`), which is `nil` in a `:super_admin` session. The working precedent is this
repository's own `AuditTrail::Event` pattern (`platform_support/audit_writer.rb:4-7`).

Consequence for §8.6: **an unaudited authoring surface makes any writer-ownership map unverifiable after the
fact.** Agent 069 independently reached the same conclusion from the source-of-truth side — `audited` on
`Article` is a prerequisite of any option that permits operator edits, and
`docs/global-documentation/10-global-docs-implementation.md:120` explicitly deferred it.

## What the security wave confirmed as CLEAN

Worth recording, because an audit that only reports problems is not trustworthy. Agent 086 tried and failed to
break these: **CSRF holds** (`protect_from_forgery with: :exception`; the Super Admin tree does *not* inherit the
app's `skip_before_action :verify_authenticity_token`; `authenticate_super_admin!` is applied with no skip).
`preview` is **not** an open redirect (hard-coded `/hc/` prefix plus `raise_on_open_redirects`). **`meta` is not
an unrestricted hash** — it is a closed six-key allowlist, so arbitrary `meta` keys are impossible, which also
refutes a mass-assignment concern I had flagged in agent 082's brief.

Agent 081 likewise **tried and failed** to break four things it expected to break: JSON-LD `</script>`
injection (`json_escape(...).to_json` plus `escape_html_entities_in_json`), Administrate's show views (all
`<%= field.data %>`, escaped), `ArticleMetaField`'s three views (all escaped), and the URL denylist — whose `\A`
anchor holds because cmark's own `cmark_clean_url` trims whitespace and decodes entities *before* Ruby sees the
URL, and `houdini_href_e.c` percent-encodes controls. A `jav&#x09;ascript:` bypass dies there.

**Nobody's defence here is accidental except the one that matters most** — raw-HTML omission, which is a parser
flag rather than a chosen control. That is what Ruling R1 addresses.

## Corpus findings that change the IA decision

Agent 062 measured the two things I would otherwise have had to guess:

- **Duplication is genuinely low** — maximum 6-gram containment 0.169, and only 6 of 1,953 article pairs above
  0.05. So **no MERGE is warranted anywhere**, and any "fold these sections together" proposal is refuted by
  measurement rather than by taste.
- **Length is bimodal** (20 articles at 330–599 words, 38 at 800–1,399, only 2 in between) and a **7-slot house
  template is observable** — `## Related` in 57 files, `## Limits` 52, `## Who can do this` 45, `## Steps` 24.
  There are already two real article types here. They have simply never been named or enforced.

Its IA recommendation is the conservative one the charter asked for: **10 of 12 sections untouched**; relocate
the 5 commerce-error articles from `troubleshooting` to `commerce` and `whatsapp-troubleshooting` into
`whatsapp-errors` as its index — both free, because slug and `doc_key` derive from the filename; split
`integrations`; and create **one** new section, `channels`, **on trigger** (the fourth non-WhatsApp channel
article) rather than up front. It explicitly rejects per-provider error sections and both failure modes, citing
in-repo evidence for each.

Two more corpus facts worth keeping: **the corpus's most-linked article is factually wrong** —
`roles-and-permissions.md` has in-degree 24 and says the custom-role list is "fixed at six" when the product
offers seven. And the 5 commerce-error articles are a **disconnected island**: out-degree 0, four of five with
in-degree 0, their cross-references written in bold instead of as links.

## A methodology correction that affects three other agents

Agents 052, 055 and 058 independently found that **POSIX `wc -w` undercounts Arabic by three to five times** in
this shell's locale. Several earlier reports used it, which is why some EN/AR ratios looked alarming. Measured
properly, agent 055 gives EN 4,090 / AR 3,438 words for the automation section, and agent 052 puts the real
overall ratio near 0.84. **The Arabic corpus is not truncated.** Agent 094 is settling this with a per-pair
verdict; until then, no "the Arabic is half the length" claim stands, including ones in earlier addenda here.

---

# Addendum 5 — two live defects outside documentation scope

Agent 083 found these while establishing how a documentation image would be authorized. Neither is a
documentation problem and neither is created by this program. Both are **live on the current baseline** and go
to the owner.

| # | Finding | Evidence |
|---|---|---|
| OWN-01 | **The entire contact database leaves the product as a permanent, unauthenticated public URL in an email.** `rails_blob_url(@account.contacts_export)` is emailed on export, and the same shape is used for import failures. Because `active_storage.urls_expire_in` is **never set** anywhere — it is an unassigned `mattr_accessor` that `load_defaults 7.0` does not populate — that URL never expires, and the blob routes authorize nothing (`ActiveStorage::BaseController` has no authentication, `blob_scope` is the bare class, and no override exists in `app/`, `custom/`, `lib/` or `config/`). Anyone who ever receives or forwards that email, or finds it in a mailbox later, can download the whole contact export. | `app/jobs/account/contacts_export_job.rb:96-98`, `app/mailers/.../account_notification_mailer.rb:29-31`, `activestorage-7.2.3.2/lib/active_storage.rb:357`, `engine.rb:120` |
| OWN-02 | **`GET /slack_uploads?blob_key=…` is unauthenticated and resolves any blob key in the installation** into a signed, non-expiring URL. Its own existing spec signs in nobody, which is how it is proven unauthenticated rather than inferred. | `config/routes.rb:36`, `app/controllers/slack_uploads_controller.rb:1-26`, `spec/controllers/slack_uploads_controller_spec.rb:7-12` |

I verified both by reading the files. I have changed nothing: they are outside this program's scope, and a
security fix to the contacts export belongs to whoever owns that subsystem, not to a documentation programme
making a drive-by edit.

**They do, however, settle a design question for us.** Agent 083's analysis is that one storage service can serve
both documentation media and private attachments, but **one URL scheme cannot** — because an ActiveStorage
signature covers only the blob's integer primary key, with no record scope, no expiry, and no owner column on
`active_storage_blobs` at all. The predicate "holds a signature over this blob id" is identical for a
documentation screenshot and a contacts export. Publishing documentation media through that route would
foreclose ever tightening it. So: **one service, two routes** — a documentation-owned public route scoped
through `Documentation::Library.articles`, so that unpublishing an article actually revokes its images.

And a decisive argument against signed IDs in article content: because `urls_expire_in` is nil, **rotating
`SECRET_KEY_BASE` would break every embedded image URL at once**, and they would be unfindable inside free-text
`articles.content`.
