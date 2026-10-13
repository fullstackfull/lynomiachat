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
