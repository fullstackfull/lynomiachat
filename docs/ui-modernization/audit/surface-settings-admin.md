# Surface audit — Settings admin pages

**Scope:** `app/javascript/dashboard/routes/dashboard/settings/{account,integrations,auditlogs,templates,sla,data,billing,subscription,security,profile}/**`
**Mode:** read-only inventory. Nothing proposed, nothing edited.
**Purpose:** this is the BASELINE manifest. A later redesign is checked against it. A control that still
exists but becomes materially harder to find counts as a regression.

All assertions below carry `file:line`. Paths are relative to
`app/javascript/dashboard/routes/dashboard/settings/` unless prefixed otherwise.

---

## 1. Routes and primary task

### Route table

| Route name | Path | Component | Shell | Gating (`meta`) |
|---|---|---|---|---|
| `settings_home` | `/accounts/:accountId/settings` | redirect | — | `ROLES` + `CONVERSATION_PERMISSIONS`; redirects admins (with `getCurrentCustomRoleId === null`) to `general_settings_index`, everyone else to `canned_list` (`settings.routes.js:37-53`) |
| `general_settings_index` | `/settings/general` | `account/Index.vue` | `SettingsWrapper` | `administrator` (`account/account.routes.js:8-21`) |
| `settings_applications` | `/settings/integrations` | `integrations/Index.vue` | `SettingsWrapper` | `administrator` + `FEATURE_FLAGS.INTEGRATIONS` (`integrations/integrations.routes.js:20-28`) |
| `settings_integrations_dashboard_apps` | `/settings/integrations/dashboard_apps` | `integrations/DashboardApps/Index.vue` | `SettingsWrapper` | `administrator` + `INTEGRATIONS` (`:29-37`) |
| `settings_integrations_webhook` | `/settings/integrations/webhook` | `integrations/Webhooks/Index.vue` | `SettingsWrapper` | `administrator` + `INTEGRATIONS` (`:38-46`) |
| `settings_integrations_slack` | `/settings/integrations/slack` | `integrations/Slack.vue` | `SettingsWrapper` | `administrator` + `INTEGRATIONS`; `code` from `route.query.code` (`:53-62`) |
| `settings_integrations_linear` | `/settings/integrations/linear` | `integrations/Linear.vue` | `SettingsWrapper` | `administrator` only — **no feature flag** (`:63-71`) |
| `settings_integrations_notion` | `/settings/integrations/notion` | `integrations/Notion.vue` | `SettingsWrapper` | `administrator` only — **no feature flag** (`:72-80`) |
| `settings_integrations_shopify` | `/settings/integrations/shopify` | `integrations/Shopify.vue` | `SettingsWrapper` | `administrator` + `INTEGRATIONS`; `error` from query (`:81-90`) |
| `settings_applications_integration` | `/settings/integrations/:integration_id` | `integrations/IntegrationHooks.vue` | `SettingsWrapper` | `administrator` + `INTEGRATIONS` (`:91-102`) |
| `auditlogs_list` | `/settings/audit-logs/list` | `auditlogs/Index.vue` | `SettingsWrapper` | `administrator` + `FEATURE_FLAGS.AUDIT_LOGS` + `installationTypes: [CLOUD, ENTERPRISE]` + `reuseOnQueryChange: true` (`auditlogs/audit.routes.js:20-33`) |
| `settings_templates` | `/settings/templates` | `templates/Index.vue` | `SettingsWrapper` | `administrator` only — **no feature flag** (`templates/templates.routes.js:11-20`) |
| `sla_wrapper` → `sla_list` | `/settings/sla/list` | `sla/Index.vue` | `SettingsWrapper` | `administrator` + `FEATURE_FLAGS.SLA` + `installationTypes: [CLOUD, ENTERPRISE]` (`sla/sla.routes.js:8-35`) |
| `settings_data_imports` | `/settings/data` | `data/Index.vue` | `SettingsWrapper` | `administrator` + `FEATURE_FLAGS.DATA_IMPORT` (`data/data.routes.js:13-21`) |
| `settings_data_import_show` | `/settings/data/:dataImportId` | `data/Show.vue` | `SettingsWrapper` | `administrator` + `DATA_IMPORT` (`:22-30`) |
| `billing_settings_index` | `/settings/billing` | `billing/ProviderIndex.vue` | `SettingsWrapper` | `administrator` (`billing/billing.routes.js:8-27`) |
| `subscription_settings_index` | `/settings/subscription` | `subscription/Index.vue` | `SettingsWrapper` | `administrator`, `agent` (`subscription/subscription.routes.js:9-28`) |
| `security_settings_index` | `/settings/security` | `security/Index.vue` | `SettingsWrapper` | `administrator` + `FEATURE_FLAGS.SAML` + `installationTypes: [CLOUD, ENTERPRISE]` (`security/security.routes.js:25-37`) |
| `profile_settings_index` | `/accounts/:accountId/profile/settings` | `profile/Index.vue` | `SettingsWrapper` | `administrator`, `agent`, `custom_role` (`profile/profile.routes.js:18-25`) |
| `profile_settings_mfa` | `/accounts/:accountId/profile/mfa` | `profile/MfaSettings.vue` | `SettingsWrapper` | same roles + `beforeEnter` guard redirecting to `profile_settings_index` when `window.chatwootConfig.isMfaEnabled` is falsy (`profile/profile.routes.js:26-42`) |

### Primary task

One administrator configures the whole workspace from a flat list of single-purpose pages: identity and
locale (general), outbound/inbound plumbing (integrations, webhooks, dashboard apps), compliance review
(audit logs), channel assets (WhatsApp templates), service targets (SLA), migration (data imports),
commercial state (billing, subscription), authentication (security/SAML), plus each individual's own
account (profile, MFA). Every page is read-then-edit: land, orient, change one setting, confirm via a
toast. Only audit logs and data imports are monitoring surfaces rather than forms.

### Navigation entry points

Sidebar group "Settings" (`components-next/sidebar/Sidebar.vue:714-868`), each item gated by the target
route's own `meta.permissions` and `meta.featureFlag`, resolved in
`components-next/sidebar/provider.js:105-127` and applied by `<Policy>` in
`components-next/sidebar/SidebarGroup.vue:245-249`.

| Nav label | Route | Notes |
|---|---|---|
| Account Settings | `general_settings_index` | `Sidebar.vue:719-724`, icon `i-lucide-briefcase` |
| WhatsApp Templates | `settings_templates` | `:780-785` |
| Integrations | `settings_applications` | `:822-827` |
| Data | `settings_data_imports` | `:840-849` — wrapped in `hasDataImport` (`:90-94`) |
| Audit Logs | `auditlogs_list` | `:850-855`, icon `i-lucide-briefcase` (**same icon as Account Settings**) |
| Billing | `billing_settings_index` | `:862-867` |
| Subscription | `subscription_settings_index` | `:868-873` |
| Profile Settings | `profile_settings_index` | `components-next/sidebar/SidebarProfileMenu.vue:76` |

Not reachable from any navigation: **`security_settings_index`**, **`sla_list`**,
`settings_integrations_webhook`, `settings_integrations_dashboard_apps`, `settings_data_import_show`,
`profile_settings_mfa`. Webhooks / dashboard apps / MFA / import detail are reached from inside their
parent page; **Security and SLA have no entry point at all** — only a typed URL
(`Sidebar.vue:714-868` contains neither route name).

---

## 2. Feature parity manifest

Every visible control, action, menu item, filter, tab, status, shortcut, bulk action, permission-gated
action, mobile affordance, cross-module link and empty/loading/error state on this surface.

### 2.1 Shared shell (applies to every page below)

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| S1 | Scrolling page container, `max-w-5xl` centered | state | `SettingsWrapper.vue:21-33` | none |
| S2 | `keep-alive` route caching | state | `SettingsWrapper.vue:26-31` | `keepAlive` prop (default true) |
| S3 | Remount on query change; opt-out via `reuseOnQueryChange` | state | `SettingsWrapper.vue:16-18` | `route.meta.reuseOnQueryChange` |
| S4 | Page title (h1) | state | `components/BaseSettingsHeader.vue:52-60` | `title` prop |
| S5 | Page description, clamped to 5 lines on mobile | state | `BaseSettingsHeader.vue:67-72` | `description` or `#description` slot |
| S6 | "Learn more" help link → external docs | navigation | `BaseSettingsHeader.vue:73-87` | `getHelpUrlForFeature(featureName)`; hidden on custom-branded instances via `CustomBrandPolicyWrapper`; **`hidden … sm:inline-flex` = desktop only** |
| S7 | Back button with label | navigation | `BaseSettingsHeader.vue:45-50` | `backButtonLabel` prop |
| S8 | Search input (type=search, magnifier prefix) | filter | `BaseSettingsHeader.vue:103-117` | `searchPlaceholder` prop; **`hidden sm:flex` = desktop only** |
| S9 | `#tabs` slot (filter bars / tab bars) | tab | `BaseSettingsHeader.vue:96-102` | slot presence |
| S10 | `#count` slot (record count) | status | `BaseSettingsHeader.vue:123` | slot presence |
| S11 | `#actions` slot (primary CTAs) | primary | `BaseSettingsHeader.vue:128` | slot presence |
| S12 | `#meta` slot (sub-description metadata) | status | `BaseSettingsHeader.vue:88` | slot presence |
| S13 | Count/actions divider pip | state | `BaseSettingsHeader.vue:124-127` | both slots present |
| S14 | Loading state (`woot-loading-state` + message) | loading | `SettingsLayout.vue:28-30` | `isLoading` prop |
| S15 | "No records" centered message | empty | `SettingsLayout.vue:31-36` | `noRecordsFound` prop |
| S16 | `#preBody` escape-hatch slot | state | `SettingsLayout.vue:27` | slot presence |
| S17 | Section block: title, description, `#headerActions`, collapsible body, BETA badge | state | `account/components/SectionLayout.vue:14-59` | `beta` / `withBorder` / `hideContent` props |
| S18 | Paywall card (lock icon, availability copy, Upgrade CTA, "cancel anytime") | state | `components/BasePaywallModal.vue:33-78` | cloud+admin → upgrade button; cloud+non-admin → `LIMIT_MESSAGES.NON_ADMIN`; self-hosted+superadmin → `/super_admin` link; else → `ASK_ADMIN` |
| S19 | `BaseSettingsListItem` card with hover-reveal action rail | contextual | `components/BaseSettingsListItem.vue:16-50` | `$slots.actions`; **unused on this surface** |

### 2.2 General settings (`general_settings_index`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| G1 | Account name text field | primary | `account/Index.vue:173-186` | required validator (`:50-56`) |
| G2 | Site language select (sorted by ISO code) | primary | `account/Index.vue:187-202`, sort at `:71-76` | required; options from `useConfig().enabledLanguages` |
| G3 | Custom reply domain field + help text | secondary | `account/Index.vue:203-225` | `featureCustomReplyDomainEnabled` (`:83-87`) |
| G4 | Support email field | secondary | `account/Index.vue:226-239` | `featureCustomReplyEmailEnabled` (`:88-92`) |
| G5 | "Update" submit, loading from `uiFlags.isUpdating` | primary | `account/Index.vue:240-244` | none |
| G6 | Validation-failure alert | error | `account/Index.vue:132-135` | invalid form |
| G7 | Update success / error toast | status | `account/Index.vue:150-153` | API result |
| G8 | Audio transcription toggle | secondary | `account/components/AudioTranscription.vue:45-49` | `FEATURE_FLAGS.CAPTAIN` on account (`account/Index.vue:65-70`) |
| G9 | Account ID code block with copy button | secondary | `account/components/AccountId.vue:20` (`woot-code`) | none |
| G10 | "Delete account" button | destructive | `account/components/AccountDelete.vue:125-131` | `isOnChatwootCloud` + not already marked (`account/Index.vue:252-254`) |
| G11 | Delete confirmation modal requiring typed account name | destructive | `AccountDelete.vue:133-146`, placeholder `:18-22` | `showDeletePopup` |
| G12 | Scheduled-deletion banner (manual vs inactivity copy) | status | `AccountDelete.vue:108-124`, copy choice `:45-59` | `custom_attributes.marked_for_deletion_at` |
| G13 | "Clear scheduled deletion" button | secondary | `AccountDelete.vue:113-122` | `isMarkedForDeletion` |
| G14 | Server-message passthrough on deletion failure | error | `AccountDelete.vue:61-68` | `error.response.data.message` |
| G15 | App version + short git SHA, click-to-copy full SHA | status | `account/components/BuildInfo.vue:45-54` | none |
| G16 | "Update available" notice | status | `BuildInfo.vue:38-44` | `semver.lt(appVersion, latest)` **and** `globalConfig.displayManifest` |
| G17 | Fetching-account loading state | loading | `account/Index.vue:248` | `uiFlags.isFetchingItem` |

### 2.3 Integrations index (`settings_applications`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| I1 | Responsive integration card grid (1/2/3 cols) | state | `integrations/Index.vue:57-70` | none |
| I2 | Enabled / Disabled status label (teal / slate) | status | `integrations/IntegrationItem.vue:66-70`, colors `:36-44` | `item.enabled` |
| I3 | "Configure" link per card → integration detail | navigation | `IntegrationItem.vue:77-84`, URL `:46-48` | none |
| I4 | Light/dark logo pair | state | `IntegrationItem.vue:56-65` | `dark:` class swap |
| I5 | Search across name + description (`picoSearch`) | filter | `integrations/Index.vue:21-25`, bound `:38-39` | desktop only (S8) |
| I6 | Search no-results message | empty | `integrations/Index.vue:51-56` | `!filtered.length && searchQuery` |
| I7 | Loading state | loading | `integrations/Index.vue:33-35` | `uiFlags.isFetching` |
| I8 | Description run through `replaceInstallationName` | state | `integrations/Index.vue:41-43`, `IntegrationItem.vue:87` | branding |

### 2.4 Integration detail — hooks (`settings_applications_integration`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| H1 | Single-hook card: logo, name, description | state | `integrations/SingleIntegrationHooks.vue:22-45` | `isIntegrationSingle` |
| H2 | Connect button (single) | primary | `SingleIntegrationHooks.vue:55-62` | `!hasConnectedHooks` |
| H3 | Disconnect button (single) | destructive | `SingleIntegrationHooks.vue:46-54` | `hasConnectedHooks` |
| H4 | Multi-hook table, columns from `visible_properties` | state | `integrations/MultipleIntegrationHooks.vue:103-145`, headers `:35-42` | `isIntegrationMultiple` |
| H5 | Inbox column | state | `MultipleIntegrationHooks.vue:121-125` | `isHookTypeInbox` |
| H6 | `--` placeholder for missing property values | state | `MultipleIntegrationHooks.vue:53-55` | none |
| H7 | Delete-hook row button (tooltip + aria-label) | destructive | `MultipleIntegrationHooks.vue:127-141` | none |
| H8 | "Add" hook button | primary | `MultipleIntegrationHooks.vue:93-100` | `showAddButton` = multiple + loaded (`IntegrationHooks.vue:57-59`) |
| H9 | Hook search over all visible properties | filter | `MultipleIntegrationHooks.vue:59-68` | desktop only |
| H10 | Hook count pluralized | status | `MultipleIntegrationHooks.vue:88-92` | `hooks.length` |
| H11 | Search no-results (table `noDataMessage`) | empty | `MultipleIntegrationHooks.vue:107` | `searchQuery` |
| H12 | "No hooks configured" empty state | empty | `MultipleIntegrationHooks.vue:146-152` | `!hasConnectedHooks` |
| H13 | Add-hook modal with FormKit schema-driven form | primary | `integrations/NewHook.vue:131-168`, schema `:60-62` | `showAddHookModal` |
| H14 | JSON-validated fields parsed before submit | state | `NewHook.vue:91-97` | `item.validation.includes('JSON')` |
| H15 | Inbox select on the add form | primary | `NewHook.vue:143-153` | `isHookTypeInbox` |
| H16 | Dialogflow: already-connected inboxes excluded | state | `NewHook.vue:43-59` | `integration.id === 'dialogflow'` |
| H17 | OpenAI "validating" submit label | status | `NewHook.vue:66-72` | `id === 'openai' && isCreatingHook` |
| H18 | Add success / server-error toast | status | `NewHook.vue:111-119` | API result |
| H19 | Delete confirmation, inbox-scoped vs account-scoped copy | destructive | `IntegrationHooks.vue:60-77`, modal `:152-160` | `isHookTypeInbox` |
| H20 | Back button → "Integrations" | navigation | `IntegrationHooks.vue:125`, `MultipleIntegrationHooks.vue:85` | none |
| H21 | Loading state | loading | `IntegrationHooks.vue:119` | `uiFlags.isFetching` |

### 2.5 Slack integration (`settings_integrations_slack`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| K1 | Connect (OAuth link) / Disconnect | primary / destructive | `integrations/Integration.vue:89-129` | `integration.enabled` + `integrationAction` |
| K2 | Disconnect confirmation dialog (Slack-specific copy) | destructive | `integrations/Slack.vue:104-110`, dialog `Integration.vue:130-146` | `integrationAction === 'disconnect'` |
| K3 | OAuth `code` consumed then stripped from URL | state | `Slack.vue:69-78` | `props.code` |
| K4 | "Attention required" card: no channel vs expired | error | `Slack/SelectChannelWarning.vue:62-80`, copy `:28-32` | `!isIntegrationHookEnabled` |
| K5 | "Select channel" fetch-channels button | primary | `SelectChannelWarning.vue:82-90` | `!hasConnectedAChannel && !availableChannels.length` |
| K6 | Channel `<select>` + Update button | primary | `SelectChannelWarning.vue:91-115` | channels fetched |
| K7 | Channel fetch failure → empty list | error | `SelectChannelWarning.vue:44-47` | catch |
| K8 | Message mode radio cards (two-way / alert) | primary | `Slack/SlackMessageMode.vue:44-63`, modes `:15-18` | `isIntegrationHookEnabled` |
| K9 | Mode update success/error toast | status | `SlackMessageMode.vue:26-30` | API result |
| K10 | Mode-aware help text, markdown-formatted | state | `Slack/SlackIntegrationHelpText.vue:22-33` | `messageMode` |
| K11 | Selected channel name, fallback `customer-conversations` | status | `Slack.vue:52-58` | `hook.status` |
| K12 | Loading state covering create-in-flight | loading | `Slack.vue:86` | `!integrationLoaded \|\| uiFlags.isCreatingSlack` |

### 2.6 Linear / Notion / Shopify integrations

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| L1 | Linear connect / disconnect + confirm copy | primary / destructive | `integrations/Linear.vue:49-60` | `integration.enabled` |
| L2 | Notion "Connect" → `generateAuthorization()` redirect | primary | `integrations/Notion.vue:75-82`, call `:33-40` | `#action` slot override |
| L3 | Notion disconnect + confirm copy | destructive | `Notion.vue:70-73` | `integrationAction` |
| L4 | Shopify "Connect" opens store-URL dialog | primary | `integrations/Shopify.vue:118-124` | none |
| L5 | Store URL dialog: labelled input + help/error message | primary | `Shopify.vue:134-154` | dialog open |
| L6 | `*.myshopify.com|io` regex validation | state | `Shopify.vue:48-52`, use `:63-67` | submit |
| L7 | Redirect to `data.redirect_url` | state | `Shopify.vue:74-76` | API result |
| L8 | Shopify OAuth error banner | error | `Shopify.vue:126-133` | `route.query.error` prop |
| L9 | Per-integration loading states | loading | `Linear.vue:39`, `Notion.vue:53`, `Shopify.vue:95` | `isCreatingLinear/Notion/Shopify` |
| L10 | Back button → "Integrations" on all three | navigation | `Linear.vue:45`, `Notion.vue:59`, `Shopify.vue:101` | none |

### 2.7 Webhooks (`settings_integrations_webhook`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| W1 | Webhook table (endpoint, actions) | state | `integrations/Webhooks/Index.vue:169-187`, headers `:66-73` | `apiAndWebhooksEnabled` |
| W2 | Optional name shown before URL | state | `Webhooks/WebhookRow.vue:42-50` | `webhook.name` |
| W3 | Subscribed events list, truncated with ShowMore(60) | state | `WebhookRow.vue:52-57`, mapping `:22-34` | none |
| W4 | "Add webhook" button | primary | `Webhooks/Index.vue:157-164` | `apiAndWebhooksEnabled` |
| W5 | Edit row button (tooltip + aria-label) | secondary | `WebhookRow.vue:62-69` | none |
| W6 | Delete row button (tooltip + aria-label, ruby hover) | destructive | `WebhookRow.vue:70-80` | none |
| W7 | Delete confirmation naming the webhook URL | destructive | `Webhooks/Index.vue:209-222` | `showDeleteConfirmationPopup` |
| W8 | URL field: required, minLength 7, url validator | state | `Webhooks/WebhookForm.vue:48-53`, field `:106-118` | — |
| W9 | Name field (optional) | secondary | `WebhookForm.vue:119-127` | — |
| W10 | 10 event checkboxes + `inbox_updated` | primary | `WebhookForm.vue:13-24`, conditional `:65-67`, render `:162-187` | `useConfig().inboxEventsEnabled` |
| W11 | Secret field, masked by default | state | `WebhookForm.vue:128-138` | `hasSecret` |
| W12 | Secret reveal/hide toggle | secondary | `WebhookForm.vue:139-147` | `hasSecret` |
| W13 | Secret copy-to-clipboard + toast | secondary | `WebhookForm.vue:148-156`, handler `:94-97` | `hasSecret` |
| W14 | One-time secret reveal screen after create, with Done | state | `Webhooks/NewWebHook.vue:46-83` | `createdWebhook` |
| W15 | Submit disabled while invalid or submitting | state | `WebhookForm.vue:198-203` | `v$.$invalid \|\| isSubmitting` |
| W16 | Edit modal reusing the same form | secondary | `Webhooks/EditWebHook.vue:47-59` | `showEditPopup` |
| W17 | Search over name + url | filter | `Webhooks/Index.vue:61-65` | `apiAndWebhooksEnabled`; desktop only |
| W18 | Webhook count | status | `Webhooks/Index.vue:150-156` | records present |
| W19 | Empty-list 404 message | empty | `Webhooks/Index.vue:132-133` | `apiAndWebhooksEnabled && !records.length` |
| W20 | Search no-results | empty | `Webhooks/Index.vue:173-175` | `searchQuery` |
| W21 | Loading state | loading | `Webhooks/Index.vue:130-131` | `fetchingList` |
| W22 | Paywall replacing the whole table | state | `Webhooks/Index.vue:168`, `Webhooks/WebhookPaywall.vue:17-26` | cloud **and** `FEATURE_FLAGS.API_AND_WEBHOOKS` off (`Index.vue:49-57`) |
| W23 | Paywall "Upgrade" → `billing_settings_index` | navigation | `WebhookPaywall.vue:9-14` | cross-module link |
| W24 | Server-error passthrough on create/update | error | `NewWebHook.vue:31-34`, `EditWebHook.vue:37-40` | `error.response.data.message` |
| W25 | Fetch deferred until entitlement known | state | `Webhooks/Index.vue:75-82` | `apiAndWebhooksEnabled` watcher |

### 2.8 Dashboard apps (`settings_integrations_dashboard_apps`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| D1 | Table (name, endpoint, actions) | state | `integrations/DashboardApps/Index.vue:144-155`, headers `:41-51` | none |
| D2 | Truncating cells with `title` tooltips | state | `DashboardApps/DashboardAppsRow.vue:18-34` | none |
| D3 | "New" button → create modal | primary | `DashboardApps/Index.vue:128-134`, handler `:65-69` | none |
| D4 | Edit row button | secondary | `DashboardAppsRow.vue:38-49` | none |
| D5 | Delete row button | destructive | `DashboardAppsRow.vue:50-62` | none |
| D6 | Delete confirmation naming the app | destructive | `DashboardApps/Index.vue:165-179` | popup open |
| D7 | Create/Update modal with mode-driven title & submit label | primary | `DashboardApps/DashboardAppModal.vue:52-59`, form `:117-169` | `mode` |
| D8 | Title field, required | state | `DashboardAppModal.vue:118-134`, validator `:31-32` | — |
| D9 | URL field, required + url validator | state | `DashboardAppModal.vue:135-151`, validator `:33-36` | — |
| D10 | Submit disabled while invalid, loading spinner | state | `DashboardAppModal.vue:162-167` | `v$.$invalid` |
| D11 | Prefill on edit | state | `DashboardAppModal.vue:61-66` | `mode === 'UPDATE'` |
| D12 | Search over title | filter | `DashboardApps/Index.vue:36-40` | desktop only |
| D13 | App count | status | `DashboardApps/Index.vue:119-127` | records present |
| D14 | Empty-list 404 message | empty | `DashboardApps/Index.vue:104-105` | `!records.length` |
| D15 | Search no-results | empty | `DashboardApps/Index.vue:138-143` | `searchQuery` |
| D16 | Loading state | loading | `DashboardApps/Index.vue:102-103` | `uiFlags.isFetching` |
| D17 | Back button → "Integrations" | navigation | `DashboardApps/Index.vue:117` | none |

### 2.9 Audit logs (`auditlogs_list`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| A1 | Table: Activity / Time / Location-or-IP | state | `auditlogs/Index.vue:198-235`, headers `:108-116` | none |
| A2 | IP-address column instead of Location | state | `auditlogs/Index.vue:101-106, 112-114` | `FEATURE_FLAGS.AUDIT_LOG_IP_ADDRESS` |
| A3 | Humanised activity sentence from log payload | state | `auditlogs/Index.vue:85-99`, helpers `helper/auditlogHelper.js` | none |
| A4 | Timestamp `MMM dd, yyyy hh:mm a` | state | `auditlogs/Index.vue:218-223` | none |
| A5 | Agent names resolved for the sentence | state | `auditlogs/Index.vue:146` (`agents/get`) | none |
| A6 | Debounced search, 500 ms, min 3 chars | filter | `auditlogs/Index.vue:118-126`, constants `:27-28` | desktop only |
| A7 | Event-type filter menu, grouped by Access/Agents/Configuration/Conversations | filter | `auditlogs/components/AuditLogFilters.vue:75-94`, groups `helper/auditlogHelper.js:230-259` | none |
| A8 | "All events" reset item | filter | `AuditLogFilters.vue:77-83` | none |
| A9 | Date-range picker (presets + custom range) | filter | `AuditLogFilters.vue:177-186`, apply `:158-164` | none |
| A10 | "Date range" button that reveals the picker | filter | `AuditLogFilters.vue:187-194` | `!isPickerVisible` |
| A11 | Sort menu: Newest / Oldest | filter | `AuditLogFilters.vue:96-112` | none |
| A12 | Active-menu highlight + chevron | state | `AuditLogFilters.vue:196-205` | `openFilterMenu` |
| A13 | Click-outside closes menus and resets picker | shortcut | `AuditLogFilters.vue:174`, handler `:143-146` | none |
| A14 | "Clear all" filters button | secondary | `auditlogs/Index.vue:184-193`, handler `:79-83` | `hasActiveFilters` (`:48-51`) |
| A15 | Filters mirrored in URL query (shareable/back-button) | state | `auditlogs/Index.vue:62-69`, parse `helper/auditlogHelper.js:266-281` | `reuseOnQueryChange` route meta |
| A16 | Pagination footer with range + page info | navigation | `auditlogs/Index.vue:236-242`, `components-next/pagination/PaginationFooter.vue` | `meta` from API |
| A17 | Total event count | status | `auditlogs/Index.vue:179-183` | `meta.totalEntries` |
| A18 | Unfiltered empty state (`LIST.404`) | empty | `auditlogs/Index.vue:156-158` | `!records.length && !hasActiveFilters` |
| A19 | Filtered empty state (`SEARCH_404`) | empty | `auditlogs/Index.vue:156-158` | `!records.length && hasActiveFilters` |
| A20 | Loading state | loading | `auditlogs/Index.vue:153-154` | `uiFlags.fetchingList` |
| A21 | Fetch-failure alert toast | error | `auditlogs/Index.vue:53-60` | catch |
| A22 | Typed-but-unsent search preserved across URL echoes | state | `auditlogs/Index.vue:41-44, 128-136` | none |
| A23 | Late debounce suppressed after navigating away | state | `auditlogs/Index.vue:63-64` | `route.name` check |

### 2.10 WhatsApp templates (`settings_templates`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| T1 | Template list rows, divided | state | `templates/Index.vue:417-424` | templates present |
| T2 | Channel icon per row | state | `templates/TemplateCard.vue:45-52` | `template.inboxes[0]` |
| T3 | Status label — shown only when **not** approved | status | `TemplateCard.vue:58-64`, condition `:25-27` | `status !== 'approved'` |
| T4 | `UNSUBMITTED` special-cased label | status | `TemplateCard.vue:28-32` | status value |
| T5 | Row meta: type · language · inbox names | state | `TemplateCard.vue:66-78` | none |
| T6 | Row click / Enter / Space opens preview | shortcut | `TemplateCard.vue:36-43` | `role="button" tabindex="0"` |
| T7 | Eye preview button with tooltip + aria-label | secondary | `TemplateCard.vue:81-91` | none |
| T8 | Inbox filter menu | filter | `templates/Index.vue:126-135`, options `:88-97` | `hasTemplates` |
| T9 | Language filter menu | filter | `templates/Index.vue:136-139`, options `:99-111` | `hasTemplates` |
| T10 | Type filter menu (9 template types) | filter | `templates/Index.vue:140-145`, labels `:67-77` | `hasTemplates` |
| T11 | Filter selections reset when the value disappears after refetch | state | `templates/Index.vue:277-288` | none |
| T12 | Search: exact substring first, fuzzy fallback | filter | `templates/Index.vue:202-213`, keys `:26-33` | shown only when results or query exist (`:216-218`); desktop only |
| T13 | Filtered count | status | `templates/Index.vue:384-392` | results present |
| T14 | "Sync templates" button, per-inbox fan-out | primary | `templates/Index.vue:393-403`, handler `:302-325` | disabled when no WhatsApp inbox or syncing |
| T15 | "Last sync attempt" timestamp in `#meta` | status | `templates/Index.vue:349-357`, computed `:58-65` | any inbox reported one |
| T16 | Side-panel preview drawer | secondary | `templates/TemplatePreviewDrawer.vue:70-141` | `openPreview` |
| T17 | Rendered template bubble preview | state | `TemplatePreviewDrawer.vue:77-85` | normalizer |
| T18 | Details list: status, type, category, language, inboxes | state | `TemplatePreviewDrawer.vue:87-127` | none |
| T19 | "Manage in Meta" / "Manage in Twilio" footer link | navigation | `TemplatePreviewDrawer.vue:131-140`, URL choice `:42-57` | Twilio platform, or an inbox with `provider === 'whatsapp_cloud'` |
| T20 | WhatsApp + Twilio-WhatsApp inbox discovery | state | `templates/Index.vue:79-86` | channel type / medium |
| T21 | Unfiltered empty state | empty | `templates/Index.vue:336` | `!templates.length` |
| T22 | Filtered no-results state | empty | `templates/Index.vue:408-415` | `!filteredTemplates.length` |
| T23 | Loading state | loading | `templates/Index.vue:333-334` | `useAbortableRequest().isPending` |
| T24 | Partial-fetch vs total-fetch error toasts | error | `templates/Index.vue:290-299` | `Promise.allSettled` outcome |
| T25 | Full / partial / total sync-error toasts | status | `templates/Index.vue:316-322` | failure count |
| T26 | In-flight request aborted on page deactivate | state | `templates/Index.vue:327-328` | `onDeactivated` |
| T27 | Per-inbox template cache pruned when an inbox disappears | state | `templates/Index.vue:262-267` | none |

### 2.11 SLA (`sla_list`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| Q1 | Table: SLA, Business hours, FRT, NRT, RT, Actions | state | `sla/Index.vue:176-301`, headers `:66-75` | `!isBehindAPaywall` |
| Q2 | Name + description stacked in first cell | state | `sla/Index.vue:227-236` | none |
| Q3 | FRT / NRT / RT header info tooltips | state | `sla/Index.vue:188-223` | `#header-2/3/4` slots |
| Q4 | Business-hours label with clock-on/off icon, teal/slate | status | `sla/Index.vue:238-264` | `only_during_business_hours` |
| Q5 | Thresholds rendered as `12m` / `3h` / `2d`, `-` when unset | state | `sla/Index.vue:120-128` | none |
| Q6 | "Add" SLA button | primary | `sla/Index.vue:160-166` | `!isBehindAPaywall`; `openAddPopup` no-ops behind paywall (`:86-91`) |
| Q7 | Create-SLA modal | primary | `sla/Index.vue:303-305`, `sla/AddSLA.vue:29-41` | `showAddPopup` |
| Q8 | Name field: required, minLength 2, distinct messages | state | `sla/SlaForm.vue:163-177`, messages `:71-81`, rules `sla/validations.js:4-7` | — |
| Q9 | Description field | secondary | `SlaForm.vue:178-188` | — |
| Q10 | Three threshold inputs with unit selects (minutes/hours/days) | primary | `SlaForm.vue:190-200`, `sla/SlaTimeInput.vue:86-119`, units `:32-37` | — |
| Q11 | Threshold → seconds conversion; 0/null means unset | state | `SlaForm.vue:136-141` | — |
| Q12 | Business-hours toggle switch | primary | `SlaForm.vue:202-209` | — |
| Q13 | Submit disabled while name invalid / thresholds invalid / updating | state | `SlaForm.vue:64-70, 219-224` | — |
| Q14 | Delete row button with per-row loading | destructive | `sla/Index.vue:284-297` | `loading[sla.id]` |
| Q15 | Delete confirmation naming the SLA | destructive | `sla/Index.vue:307-316`, value `:57-59` | popup open |
| Q16 | Create / delete success & error toasts | status | `AddSLA.vue:17-23`, `sla/Index.vue:107-119` | API result |
| Q17 | Search over name + description | filter | `sla/Index.vue:76-80` | `!isBehindAPaywall`; desktop only |
| Q18 | SLA count | status | `sla/Index.vue:155-159` | records present |
| Q19 | Empty-list state (`LIST.404`) | empty | `sla/Index.vue:180-186` | `!records.length` |
| Q20 | Search no-results state | empty | `sla/Index.vue:183-184` | `searchQuery && !filtered.length` |
| Q21 | Loading state | loading | `sla/Index.vue:141-142` | `uiFlags.isFetching` |
| Q22 | Paywall, cloud vs enterprise copy | state | `sla/Index.vue:170-175`, `sla/SLAPaywallEnterprise.vue:16-28` | `!isFeatureEnabledonAccount(accountId,'sla')` |
| Q23 | Paywall "Upgrade" → `billing_settings_index` | navigation | `sla/Index.vue:129-134` | cross-module link |
| Q24 | Super-admin branch inside the paywall | state | `sla/Index.vue:63-65`, `components/BasePaywallModal.vue:71-77` | `currentUser.type === 'SuperAdmin'` |
| Q25 | **No edit action** — SLAs can only be created and deleted | — | `sla/Index.vue:284-297` has delete only; `SlaForm.vue:16-20` accepts `selectedResponse` but nothing passes it | parity note |

### 2.12 Data imports (`settings_data_imports`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| X1 | Import / Export tab bar | tab | `data/Index.vue:193-199`, tabs `:46-49` | none |
| X2 | Import list rows, divided | state | `data/Index.vue:293-369` | imports present |
| X3 | Source icon (image or lucide) with tooltip | state | `data/Index.vue:305-321`, config `data/importSources.js:1-25` | `source_provider` |
| X4 | Status dot + humanised status, pulsing while active | status | `data/Index.vue:327-340`, colors `data/importStatus.js:81-91` | `isActiveImport` |
| X5 | Row meta: types · imported count · created date | state | `data/Index.vue:342-356`, count `importStatus.js:25-34` | none |
| X6 | Row click / Enter / Space opens detail | shortcut | `data/Index.vue:297-302` | `role="button" tabindex="0"` |
| X7 | Eye "View" button | secondary | `data/Index.vue:359-367` | none |
| X8 | "New import" button | primary | `data/Index.vue:227-237` | disabled + tooltip when `hasActiveIntegrationImport` |
| X9 | Manual refresh button (aria-label + title) | secondary | `data/Index.vue:217-226` | `activeTab === 'import'` |
| X10 | "Live, refreshing every Ns" indicator | status | `data/Index.vue:206-216` | `hasActiveImport`; **`hidden … sm:inline-flex` = desktop only** |
| X11 | 5 s polling while an import is active | state | `data/Index.vue:112-117`, `importStatus.js:1` | `hasActiveImport` |
| X12 | Polling paused on hidden tab / page deactivate | state | `data/Index.vue:93-101, 155-180` | `document.hidden` |
| X13 | Import count | status | `data/Index.vue:200-204` | imports present |
| X14 | Empty state: icon, title, description, CTA | empty | `data/Index.vue:268-291` | `!dataImports.length` |
| X15 | Export tab "coming soon" state | empty | `data/Index.vue:243-266` | `activeTab === 'export'` |
| X16 | Loading state | loading | `data/Index.vue:185-186` | `isLoading` |
| X17 | New-import dialog: source select (Intercom / Freshdesk) | primary | `data/NewImportDialog.vue:186-193` | — |
| X18 | Import name field, source-specific default | secondary | `NewImportDialog.vue:195-199`, default `:26-30` | — |
| X19 | Freshdesk domain field | primary | `NewImportDialog.vue:201-208` | `sourceConfig.requiresDomain` |
| X20 | Credential (password) field, source-specific label/placeholder | primary | `NewImportDialog.vue:210-219`, copy `:46-55` | — |
| X21 | Async credential validation on blur, with validating/valid/invalid message states | state | `NewImportDialog.vue:88-111`, message type `:57-61` | — |
| X22 | Stale validation responses discarded | state | `NewImportDialog.vue:94-105` | request id |
| X23 | Data-type checkboxes (contacts / conversations) | primary | `NewImportDialog.vue:221-243` | — |
| X24 | Confirm disabled until validated + a type chosen + no active import | state | `NewImportDialog.vue:63-69, 179` | `canCreate` |
| X25 | Active-import warning inside the dialog | error | `NewImportDialog.vue:245-250` | `hasActiveImport` |
| X26 | Create success/failure toast, then navigate to detail | status | `NewImportDialog.vue:128-133`, nav `data/Index.vue:143-149` | API result |
| X27 | Detail header: name (or "Unnamed"), stage label, status dot | status | `data/components/ImportDetailHeader.vue:80-142`, stages `:48-64` | — |
| X28 | Detail live/refreshing indicator | status | `ImportDetailHeader.vue:128-141` | `hasActiveImport` |
| X29 | Detail refresh button | secondary | `ImportDetailHeader.vue:86-96` | `hasActiveImport` |
| X30 | Retry button | secondary | `ImportDetailHeader.vue:97-107` | `dataImport.stalled` |
| X31 | Abandon button (ruby) | destructive | `ImportDetailHeader.vue:108-116` | `isAbandonableImport` (`importStatus.js:22-23`) |
| X32 | Retry / abandon mutual disabling | state | `ImportDetailHeader.vue:104, 113` | — |
| X33 | Back button → data list | navigation | `ImportDetailHeader.vue:78` | — |
| X34 | Summary tiles: source, types, created, duration, initiated by | state | `data/components/ImportSummaryTiles.vue:49-86` | — |
| X35 | Duration tile tooltip showing last-updated time | state | `ImportSummaryTiles.vue:73-75` | — |
| X36 | Per-type progress bars with percent and totals | state | `data/components/ImportProgress.vue:62-99`, math `:31-51` | `import_types.length` |
| X37 | Progress grid column count fitted to group count | state | `ImportProgress.vue:55-59` | — |
| X38 | Errors section: collapsible, count badge, table, CSV download | state | `data/components/ImportErrorsSection.vue:38-77`, shell `data/components/ImportLogSection.vue:44-104` | — |
| X39 | Skip-logs section: collapsible, count badge, table, CSV download | state | `data/components/ImportSkipLogsSection.vue:74-126` | — |
| X40 | Skip-log type filter chips with per-type counts | filter | `ImportSkipLogsSection.vue:86-99`, options `:46-70` | chip disabled when count 0 |
| X41 | Download disabled when count is 0 | state | `ImportLogSection.vue:66-75` | `!count` |
| X42 | Section empty messages ("No errors" / "No skip logs") | empty | `ImportErrorsSection.vue:47`, `ImportSkipLogsSection.vue:82` | `!items.length` |
| X43 | Sections auto-collapsed when they have no records | state | `data/Show.vue:192-194` | counts |
| X44 | Retry invalidates in-flight detail fetches | state | `data/Show.vue:55-66, 134` | `importRequestVersion` |
| X45 | Abandon / retry success & failure toasts | status | `data/Show.vue:126, 139-141` | API result |
| X46 | CSV blob download with per-import filename | secondary | `data/Show.vue:148-179` | — |

### 2.13 Billing (`billing_settings_index`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| B1 | Provider fork: Shopify billing vs Stripe | state | `billing/ProviderIndex.vue:24-46` | `currentAccount.billing_provider === 'shopify'` |
| B2 | Account-not-yet-loaded loading state | loading | `ProviderIndex.vue:25-29` | `!isAccountLoaded` |
| B3 | Stripe path: immediate redirect to `lynomia.com/admin/subscriptions/:accountId` with a spinner | navigation | `billing/Index.vue:8-16` | default (non-Shopify) |
| B4 | "Shopify billing unavailable" state | empty | `ProviderIndex.vue:31-44` | Shopify provider **without** `FEATURE_FLAGS.SHOPIFY` |
| B5 | Plan card: title, description, action | state | `billing/ShopifyBilling.vue:205-255`, `billing/components/BillingCard.vue:16-24` | `summary` present |
| B6 | "Manage plan" / "View plans" button | primary | `ShopifyBilling.vue:214-226`, label `:54-58` | `allowed_actions.manage_subscription` |
| B7 | Detail items: current plan, status, price, billing date, last verified | state | `ShopifyBilling.vue:231-253`, `billing/components/DetailItem.vue:14-22` | each conditional |
| B8 | Status label for 6 states (active/trialing/cancelled/expired/missing/pending) | status | `ShopifyBilling.vue:36-52` | `summary.state` |
| B9 | Currency-formatted price, per-month / per-year suffix | state | `ShopifyBilling.vue:60-84` | `billing_period` |
| B10 | Date row relabelled: trial ends / access until / renews on | status | `ShopifyBilling.vue:86-102` | state + dates |
| B11 | Stale-data warning banner | error | `ShopifyBilling.vue:178-188` | refresh leg failed after a good first read |
| B12 | Error state with Retry button | error | `ShopifyBilling.vue:190-203`, retry `:200-202` | `hasError && !summary` |
| B13 | Two-phase load: cached read, then forced refresh + store refresh | state | `ShopifyBilling.vue:123-154` | — |
| B14 | Shopify return params (`plan_handle`, `shop`) stripped from the URL | state | `ShopifyBilling.vue:118-121, 143-145` | `isShopifyReturn` |
| B15 | Loading state | loading | `ShopifyBilling.vue:164-167` | `isLoading` |

### 2.14 Subscription (`subscription_settings_index`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| P1 | Hand-rolled page header (title + description) | state | `subscription/Index.vue:353-358` | **does not use `BaseSettingsHeader`** |
| P2 | Current-subscription card: plan, status, date | state | `subscription/Index.vue:426-456` | — |
| P3 | Status for 9 states incl. manual, trial-ended, past-due-locked, cancels-at-period-end | status | `subscription/Index.vue:217-262` | `subscription.status` + `usable` + `source` |
| P4 | "Manage billing" → Stripe portal redirect | primary | `subscription/Index.vue:430-441`, handler `:327-337` | `isAdmin && subscription.has_billing_account` |
| P5 | Usage card: agents / inboxes / commerce stores vs plan limits | state | `subscription/Index.vue:459-478` | — |
| P6 | Stores row shown only when relevant | state | `subscription/Index.vue:160-162, 472-476` | `plan_commerce` or `usage.stores > 0` |
| P7 | "Unlimited" rendering for null limits | state | `subscription/Index.vue:203-204` | — |
| P8 | Plans grid with per-plan name, description, price, interval, per-agent note | state | `subscription/Index.vue:492-522` | — |
| P9 | Plan feature bullets (agents, inboxes, stores, custom features) | state | `subscription/Index.vue:524-545` | — |
| P10 | Current plan highlighted with brand outline | status | `subscription/Index.vue:496-501` | `plan.id === subscription.plan_id` |
| P11 | "Current plan" disabled button | state | `subscription/Index.vue:549-558` | paid sub + same plan |
| P12 | "Subscribe" → Stripe checkout redirect | primary | `subscription/Index.vue:575-586`, handler `:279-289` | no paid subscription |
| P13 | "Change plan" → proration preview | primary | `subscription/Index.vue:560-573`, handler `:292-304` | `hasPaidSubscription`; disabled unless `canChangePlan` (`:174-178`) |
| P14 | Plan-change confirmation panel with charge / credit / free wording | primary | `subscription/Index.vue:395-423`, copy `:206-215` | `pendingChange` |
| P15 | Confirm plan change (uses the previewed `proration_date`) | primary | `subscription/Index.vue:307-321` | — |
| P16 | Cancel plan change | secondary | `subscription/Index.vue:413-421` | — |
| P17 | Checkout success banner + delayed refetch | status | `subscription/Index.vue:363-368`, refetch `:342` | `?checkout=success` |
| P18 | Checkout canceled banner | status | `subscription/Index.vue:369-374` | `?checkout=canceled` |
| P19 | Plan-change success banner | status | `subscription/Index.vue:375-380` | `successMessage` |
| P20 | Action-error banner | error | `subscription/Index.vue:381-386` | `actionError` |
| P21 | "Admins only" notice | state | `subscription/Index.vue:387-392` | `!isAdmin` (route allows `agent`) |
| P22 | All plan CTAs hidden for non-admins | state | `subscription/Index.vue:547` | `isAdmin` |
| P23 | "No plans available" state | empty | `subscription/Index.vue:488-490` | `!plans.length` |
| P24 | Load-error state via `noRecordsFound` | error | `subscription/Index.vue:350-351`, set `:273` | `loadError` |
| P25 | Loading state | loading | `subscription/Index.vue:348-349` | `isLoading` |
| P26 | Mutual CTA locking while a plan action is in flight | state | `subscription/Index.vue:567-569, 582` | `busyPlanId`, `pendingChange` |

### 2.15 Security / SAML (`security_settings_index`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| E1 | SAML enable/disable switch | primary | `security/components/SamlSettings.vue:178-186` | `isLoading` disables it |
| E2 | Disabling the switch deletes the stored settings | destructive | `SamlSettings.vue:147-163` | toggle off |
| E3 | BETA badge with tooltip | status | `SamlSettings.vue:174` → `account/components/SectionLayout.vue:34-40` | `beta` prop |
| E4 | Form collapsed until enabled / feature present / loaded | state | `SamlSettings.vue:175` | `hideContent` |
| E5 | SSO URL field (type=url), required + help | primary | `SamlSettings.vue:196-210`, error `:45-49` | — |
| E6 | IdP entity ID field, required + help | primary | `SamlSettings.vue:212-225`, error `:57-61` | — |
| E7 | Certificate textarea (8 rows), required + help | primary | `SamlSettings.vue:227-241`, error `:51-55` | — |
| E8 | Update button with submitting state | primary | `SamlSettings.vue:243-250` | — |
| E9 | Create-vs-update chosen by stored id | state | `SamlSettings.vue:96-101` | `id.value` |
| E10 | Info panel: ACS URL, SP entity ID, fingerprint | state | `security/components/SamlInfoSection.vue:62-101`, items `:28-50` | each row's `show` flag |
| E11 | ACS URL computed from origin + account id | state | `SamlInfoSection.vue:23-26` | — |
| E12 | Per-row copy button + success toast | secondary | `SamlInfoSection.vue:91-98, 56-59` | — |
| E13 | Per-row info tooltips + section tooltip | state | `SamlInfoSection.vue:68-71, 84-87` | — |
| E14 | Attribute-mapping disclosure (email / first_name / last_name) | state | `security/components/SamlAttributeMap.vue:14-49` | collapsed by default |
| E15 | 404 on load treated as "not configured", not an error | state | `SamlSettings.vue:80-87` | `status !== 404` |
| E16 | Backend validation errors surfaced verbatim | error | `SamlSettings.vue:116-127` | `error.response.data.errors` |
| E17 | Save / disable / load-error toasts | status | `SamlSettings.vue:83, 110, 114, 125` | API result |
| E18 | Paywall, cloud vs enterprise copy | state | `security/Index.vue:44`, `security/components/SamlPaywall.vue:28-41` | `shouldShowPaywall('saml')` |
| E19 | Paywall "Upgrade" → `billing_settings_index` | navigation | `SamlPaywall.vue:20-25` | cross-module link |
| E20 | "SAML disabled" message | empty | `security/Index.vue:46-48` | `allowedLoginMethods` lacks `saml` (`:13-28`) |

### 2.16 Profile settings (`profile_settings_index`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| F1 | Avatar with upload | primary | `profile/UserProfilePicture.vue:30-37` | `allow-upload` |
| F2 | Avatar delete + toast | destructive | `UserProfilePicture.vue:20-22`, handler `profile/Index.vue:193-202` | — |
| F3 | Name field, required minLength 1 | primary | `profile/UserBasicDetails.vue:95-106` | — |
| F4 | Display-name field | secondary | `UserBasicDetails.vue:107-120` | — |
| F5 | Email field | primary | `UserBasicDetails.vue:121-133` | `!globalConfig.disableUserProfileUpdate` (`profile/Index.vue:245`) |
| F6 | Changing email logs the user out and shows the verify notice | state | `profile/Index.vue:168-177` | `hasEmailChanged` |
| F7 | Profile save button + validation alert | primary | `UserBasicDetails.vue:134-136, 77-88` | — |
| F8 | Font-size select | secondary | `profile/FontSize.vue:43-60` | `useFontSize().fontSizeOptions` |
| F9 | Interface language select, with "use account default" | secondary | `profile/UserLanguageSelect.vue:85-101`, option `:23-31` | — |
| F10 | Language applied immediately; clearing falls back to account locale | state | `UserLanguageSelect.vue:33-65` | — |
| F11 | Invalid language code rejected | error | `UserLanguageSelect.vue:45-50` | — |
| F12 | Message-signature rich editor | primary | `profile/MessageSignature.vue:43-51` | — |
| F13 | Inline base64 images stripped with a warning | state | `MessageSignature.vue:27-38` | `hasInlineImages` |
| F14 | Send-message hotkey radio cards (Enter / Cmd+Enter) with light+dark art | primary | `profile/Index.vue:294-314`, data `:70-94` | `isEditorHotKeyEnabled` |
| F15 | Change-password form: current, new, confirm | primary | `profile/ChangePassword.vue:85-131` | `!globalConfig.disableUserProfileUpdate` (`profile/Index.vue:318`) |
| F16 | Password match + minLength 6 validators; submit disabled until satisfied | state | `ChangePassword.vue:30-55` | — |
| F17 | Server error passthrough on password change | error | `ChangePassword.vue:70-76` | `parseAPIErrorResponse` |
| F18 | MFA card with "Configure" → MFA page | navigation | `profile/MfaSettingsCard.vue:20-46` | `window.chatwootConfig.isMfaEnabled` (`profile/Index.vue:122-124, 326`) |
| F19 | Active-sessions list: device icon, browser/platform, location, last active | state | `profile/ActiveSessions.vue:92-144`, labels `:28-64` | — |
| F20 | "Current" session badge | status | `ActiveSessions.vue:109-114` | `session.current` |
| F21 | Exact-timestamp tooltip on last-active | state | `ActiveSessions.vue:122-132` | `last_activity_at` |
| F22 | Revoke session button + analytics event | destructive | `ActiveSessions.vue:135-143`, handler `:78-87` | hidden for the current session |
| F23 | Session fetch / revoke error toasts | error | `ActiveSessions.vue:71-75, 84-86` | — |
| F24 | Audio tone select (5 tones) | secondary | `profile/AudioAlertTone.vue:67-84`, tones `:22-43` | — |
| F25 | Tone preview play button with tooltip | secondary | `AudioAlertTone.vue:85-93`, handler `:54-62` | — |
| F26 | Audio alert event checkboxes (assigned / unassigned / notme) | primary | `profile/AudioAlertEvent.vue:77-97`, events `profile/constants.js:45-58` | — |
| F27 | Legacy `none`/`mine`/`all` values migrated on read | state | `AudioAlertEvent.vue:22-34` | — |
| F28 | Combination summary sentence under the checkboxes | status | `AudioAlertEvent.vue:59-68, 98-100` | — |
| F29 | Audio conditions: play when tab inactive, alert if unread assigned exists | primary | `profile/AudioAlertCondition.vue:20-45`, data `profile/AudioNotifications.vue:35-48` | — |
| F30 | Audio settings section role-gated | state | `profile/Index.vue:340-350` | `ROLES + CONVERSATION_PERMISSIONS` via `<Policy>` |
| F31 | Notification matrix (desktop): type / email / push columns | primary | `profile/NotificationPreferences.vue:162-225` | `hidden sm:block` |
| F32 | Notification stacked lists (mobile): email list then push list | mobile | `NotificationPreferences.vue:226-272` | `sm:hidden` |
| F33 | 8 notification types incl. 3 SLA ones | primary | `profile/constants.js:1-37` | SLA rows filtered out without `FEATURE_FLAGS.SLA` (`NotificationPreferences.vue:43-53`) |
| F34 | Each checkbox saves immediately with a toast | state | `NotificationPreferences.vue:122-147` | — |
| F35 | Browser push-permission toggle (subscribe / unsubscribe) | primary | `NotificationPreferences.vue:274-291`, handlers `:78-106` | `Notification in window` (`:37-39`) |
| F36 | Notifications section role-gated | state | `profile/Index.vue:351-359` | `<Policy>` |
| F37 | Access token, masked, with reveal toggle | secondary | `profile/AccessToken.vue:35-58, 16-22` | — |
| F38 | Access token copy + toast | secondary | `AccessToken.vue:60-69`, handler `profile/Index.vue:210-215` | disabled when not entitled |
| F39 | Access token reset, two-step inline confirm | destructive | `AccessToken.vue:70-82`, handler `profile/Index.vue:216-225` | disabled when not entitled |
| F40 | Paid-plan note replacing the token description | state | `profile/Index.vue:113-121` | `apiAndWebhooksEnabled` (`:106-112`) |
| F41 | All token controls disabled without entitlement | state | `AccessToken.vue:45, 52, 67, 80` | `disabled` prop |

### 2.17 MFA settings (`profile_settings_mfa`)

| # | Feature | Kind | Where | Gated by |
|---|---|---|---|---|
| M1 | "Enhance security" prompt card + Enable button | primary | `profile/MfaStatusCard.vue:24-44` | `!mfaEnabled && !showSetup` |
| M2 | "MFA enabled" status card | status | `MfaStatusCard.vue:45-62` | `mfaEnabled && !showSetup` |
| M3 | Step 1: QR code rendered client-side from the provisioning URI | primary | `profile/MfaSetupWizard.vue:165-184`, generation `:50-64` | `setupStep === 'qr'` |
| M4 | QR loading placeholder | loading | `MfaSetupWizard.vue:175-182` | `!qrCodeUrl` |
| M5 | "Enter manually" disclosure with secret + copy | secondary | `MfaSetupWizard.vue:186-207` | — |
| M6 | 6-digit code input, Enter submits | shortcut | `MfaSetupWizard.vue:210-221` | `maxlength=6`, `@keyup.enter` |
| M7 | Verify button disabled until 6 digits | state | `MfaSetupWizard.vue:231-236` | — |
| M8 | Cancel setup | secondary | `MfaSetupWizard.vue:224-230` | — |
| M9 | Verification error message | error | `MfaSetupWizard.vue:217`, setter `:140-142`, caller `profile/MfaSettings.vue:88-91` | — |
| M10 | Step 2: backup-codes grid (2 / 4 / 5 cols) | state | `MfaSetupWizard.vue:268-279` | `setupStep === 'backup'` |
| M11 | Important-notice callout | status | `MfaSetupWizard.vue:253-265` | — |
| M12 | Download backup codes as `.txt` | secondary | `MfaSetupWizard.vue:282-289`, handler `:101-110` | — |
| M13 | Copy all backup codes + toast | secondary | `MfaSetupWizard.vue:290-297`, handler `:95-99` | — |
| M14 | "I saved them" checkbox gating Complete | state | `MfaSetupWizard.vue:303-318` | `backupCodesConfirmed` |
| M15 | Setup state reset whenever the wizard reopens | state | `MfaSetupWizard.vue:127-137` | — |
| M16 | Regenerate-backup-codes card + dialog (OTP required) | primary | `profile/MfaManagementActions.vue:106-127, 201-217` | `mfaEnabled` |
| M17 | New-codes dialog opened after regeneration | state | `MfaManagementActions.vue:220-276`, trigger `MfaSettings.vue:128-129` | — |
| M18 | Disable-MFA card + dialog (password required) | destructive | `MfaManagementActions.vue:130-151, 155-198` | `mfaEnabled` |
| M19 | Disable via OTP **or** backup code, with a method toggle | primary | `MfaManagementActions.vue:170-196`, toggle `:64-68` | — |
| M20 | Forms reset + dialogs closed after success | state | `MfaManagementActions.vue:77-88`, callers `MfaSettings.vue:115, 128` | — |
| M21 | Enable / verify / disable / regenerate toasts | status | `MfaSettings.vue:74, 101, 117, 119, 131, 133` | — |
| M22 | `MFA_STATE_CHANGED` broadcast on every state change | state | `MfaSettings.vue:100, 116, 130` | `emitter` |
| M23 | Redirect out when MFA is globally disabled (route guard + in-page) | state | `profile/profile.routes.js:33-41`, `MfaSettings.vue:34-44` | `window.chatwootConfig.isMfaEnabled` |
| M24 | Back button → "Profile settings" | navigation | `MfaSettings.vue:143` | — |

---

## 3. Visual and interaction audit

### 3.1 Hierarchy

**V1 — Two incompatible page shells coexist, and three header components.** `SettingsWrapper.vue:21-33`
(`max-w-5xl`, no header slot) is used by every page on this surface, while `Wrapper.vue:20-37`
(`max-w-7xl` + `SettingsHeader.vue`) is still used by teams and macros
(`teams/teams.routes.js:12`, `macros/macros.routes.js:8`). Content width therefore differs between
sibling settings pages. Separately, `SettingsSubPageHeader.vue:10-19` is a third header, used only by
teams (`teams/Edit/EditTeam.vue:7`). Severity: medium.

**V2 — Route-level header props are silently dropped.** `billing/billing.routes.js:13-17`,
`subscription/subscription.routes.js:14-18` and `security/security.routes.js:19-23` each pass
`headerTitle`, `icon` and `showNewButton` as route `props`. `SettingsWrapper.vue:5-10` declares only
`keepAlive`, so all three are discarded — the icon and route-level title never render. These are
leftovers from `Wrapper.vue:6-11`, which did accept them. `showNewButton` is accepted by nothing
anywhere (4 call sites, 0 consumers). Severity: medium.

**V3 — Two pages give up on the shared header entirely.** `subscription/Index.vue:353-358` hand-rolls
`<h1 class="text-xl font-medium">` + `<p class="text-sm">`, and `account/Index.vue:161` and
`profile/Index.vue:232` pass `BaseSettingsHeader` a title with no description, then immediately open a
`SectionLayout` with `title=""` (`profile/Index.vue:233`) purely for its padding. The subscription page's
`h1` is `text-xl`; every other page's is `text-heading-1` (`BaseSettingsHeader.vue:56`). Severity: high —
the subscription page reads as a different product.

**V4 — Heading levels are inconsistent for the same visual rank.** `h3` at
`integrations/Integration.vue:81` and `integrations/SingleIntegrationHooks.vue:38` both carry
`text-heading-1`; `h5` at `integrations/Slack/SlackMessageMode.vue:38` and
`Slack/SlackIntegrationHelpText.vue:41` also carry `text-heading-1`; `h4` at
`account/components/SectionLayout.vue:29-31` carries `text-heading-2`. Three different tags render the
same size inside one surface. Severity: medium (a11y + consistency).

### 3.2 Density and spacing

**V5 — The paywall cards cannot centre themselves.** `SettingsWrapper.vue:25` sets
`flex items-start` on the router-view parent, so the page is a non-stretching flex item of auto height.
`Webhooks/WebhookPaywall.vue:18` (`h-full max-h-[28rem] grid place-content-center`) and
`security/components/SamlPaywall.vue:30` (`w-full max-w-5xl mx-auto h-full max-h-[28rem] grid
place-content-center`) both depend on `h-full` resolving to a real height; against an auto-height parent
it resolves to content height, so `place-content-center` has no free space to distribute. Meanwhile
`sla/SLAPaywallEnterprise.vue:20` solves the same problem differently, with `pb-6 pt-10 flex
justify-center`. Three paywalls, three layout strategies, two of which depend on a height the shell does
not provide. Severity: medium.

**V6 — Four different page content widths.** `SettingsWrapper.vue:25` `max-w-5xl`;
`account/Index.vue:160` and `profile/Index.vue:231` `max-w-2xl`;
`security/components/SamlSettings.vue:176` `max-w-2xl`; `BaseSettingsHeader.vue:69` clamps the
description to `max-w-3xl`; `integrations/ShowIntegration.vue:47` `max-w-6xl`. Navigating
General → Integrations → Audit logs shifts the content column width twice. Severity: medium.

**V7 — Magic alignment offsets.** `profile/AudioAlertTone.vue:89` positions the play button with
`mt-[1.75rem]`, and `sla/SlaTimeInput.vue:104` uses `class="mt-7"` with the comment
`<!-- the mt-7 handles the label offset -->`. Both hand-compute a label height to line a control up with
the input beside it, rather than using the shared control ladder in `tailwind.config.js:78-88`
(`h-control-*`). Severity: low.

**V8 — One-off width hack in a flex row.** `integrations/SingleIntegrationHooks.vue:45` reserves the
action column with `w-[15%]`, so the Connect/Disconnect button's width tracks viewport width instead of
its label. Severity: low.

### 3.3 Inconsistent controls and duplicated patterns

**V9 — Three input systems on one surface.** Legacy `woot-input`:
`integrations/DashboardApps/DashboardAppModal.vue`, `profile/UserBasicDetails.vue`,
`profile/AccessToken.vue`, `profile/ChangePassword.vue`, `sla/SlaTimeInput.vue`, `sla/SlaForm.vue`.
Modern `components-next/input/Input.vue`: `account/Index.vue`, `data/NewImportDialog.vue`,
`integrations/Shopify.vue`, `profile/MfaManagementActions.vue`, `profile/MfaSetupWizard.vue`,
`security/components/SamlSettings.vue`. Severity: high — this is the single biggest source of visual drift
on the surface.

**V10 — The legacy inputs re-declare the same inline style object five times.** The identical literal
`{ borderRadius: '0.75rem', padding: '0.375rem 0.75rem', fontSize: '0.875rem' }` appears at
`profile/UserBasicDetails.vue:37-42`, `profile/ChangePassword.vue:22-27`, `sla/SlaForm.vue:167-171`,
`sla/SlaForm.vue:181-185` and `sla/SlaTimeInput.vue:93-97`; `profile/AccessToken.vue:38-42` uses the same
idea with px values (`'12px'`, `'14px'`) instead of rem. This is inline styling of exactly the thing
Tailwind tokens exist for, and it drifts (`0.75rem` vs `12px`). Severity: medium.

**V11 — Three select systems.** Raw `<select>`: `account/Index.vue:193-201`,
`integrations/Slack/SelectChannelWarning.vue:92-106`, `sla/SlaTimeInput.vue:105-117`. `v3`
`FormSelect`: `profile/UserLanguageSelect.vue:85`, `profile/FontSize.vue:43`,
`profile/AudioAlertTone.vue:67`. `components-next` `Select`: `data/NewImportDialog.vue:188`. Three
different focus rings and chevrons for the same affordance. Severity: medium.

**V12 — Four mechanisms for destructive confirmation.** `woot-delete-modal`: `sla/Index.vue:307`,
`integrations/Webhooks/Index.vue:209`, `integrations/DashboardApps/Index.vue:165`,
`integrations/IntegrationHooks.vue:152`. `ConfirmDeleteModal` with typed-name confirmation:
`account/components/AccountDelete.vue:133-146`. `components-next` `Dialog type="alert"`:
`integrations/Integration.vue:130-146`, `profile/MfaManagementActions.vue:155`. Inline two-step
`ConfirmButton`: `profile/AccessToken.vue:70-82`. Revoking a session
(`profile/ActiveSessions.vue:135-143`) has **no confirmation at all**. Severity: high — destructive
weight is not legible or predictable.

**V13 — Two filter-bar implementations of the same design.** `auditlogs/components/AuditLogFilters.vue`
and `templates/Index.vue:358-383` both build "icon + selected-label + chevron button that opens a
`DropdownMenu`", with near-identical markup (`AuditLogFilters.vue:195-212` vs
`templates/Index.vue:364-381`) — down to the same `bg-n-slate-9/10` open-state class. They diverge on
two details: the audit bar passes `:menu-sections` and positions with the logical `start-0`
(`AuditLogFilters.vue:209`), the templates bar passes `:menu-items` and positions with
`ltr:left-0 rtl:right-0` (`templates/Index.vue:378`). Severity: medium.

**V14 — Backup-code download/copy duplicated verbatim.** `profile/MfaSetupWizard.vue:95-110` and
`profile/MfaManagementActions.vue:39-54` are byte-identical `copyBackupCodes` + `downloadBackupCodes`
implementations, and the grid-plus-two-buttons block is duplicated too
(`MfaSetupWizard.vue:268-299` vs `MfaManagementActions.vue:244-275`). Severity: low (correctness risk if
only one is ever fixed).

**V15 — Horizontal table scrolling solved two ways.** `BaseTable` has a `scrollable` prop for exactly
this (`components-next/table/BaseTable.vue:51-54, 87`), but
`data/components/ImportLogSection.vue:90` wraps the table in its own
`<div class="overflow-x-auto">` instead. Severity: low.

**V16 — Dead code still shipping on this surface.** `integrations/ShowIntegration.vue:3` imports
`./IntegrationHelpText.vue`, which does not exist — the file cannot compile, and nothing imports it.
`integrations/hookMixin.js` is referenced only by its own spec
(`integrations/specs/hookMixin.spec.js:2`); `useIntegrationHook` replaced it.
`billing/components/PurchaseCreditsModal.vue`, `billing/components/CreditPackageCard.vue` and
`billing/components/BillingMeter.vue` are reachable from nothing (`PurchaseCreditsModal` imports
`CreditPackageCard`, and no third file imports either). `profile/Wrapper.vue` is unreferenced
(`profile/profile.routes.js:4` uses `../SettingsWrapper.vue`). `profile/NotificationCheckBox.vue` is
unreferenced. `account/components/AutoResolve.vue` lives under `account/` but is used only by
`conversationWorkflow/index.vue:9`. `components/BaseSettingsListItem.vue` is used by no page on this
surface. Severity: medium (an inventory baseline that includes dead UI will mislead the redesign).

### 3.4 Unclear CTAs

**V17 — Two sibling nav items both lead to billing, and one leaves the product.**
`Sidebar.vue:862-867` "Billing" → `billing_settings_index`, which for every non-Shopify account is
`billing/Index.vue:8-10`: an `onMounted` hard redirect to `https://lynomia.com/admin/subscriptions/{id}`
with a bare spinner (`billing/Index.vue:13-16`) and no heading, no explanation and no error path if the
host is unreachable. `Sidebar.vue:868-873` "Subscription" → `subscription_settings_index`, the real
in-app plan management page. An admin has no way to tell which one to click. The external URL is also
hardcoded with no config indirection. Severity: high.

**V18 — The paywall Upgrade button points at the page that redirects off-site.** All three paywalls route
to `billing_settings_index` (`Webhooks/WebhookPaywall.vue:10-13`, `sla/Index.vue:130-133`,
`security/components/SamlPaywall.vue:21-24`), which on a non-Shopify account immediately bounces the
admin to `lynomia.com` (V17). Severity: medium.

**V19 — Two adjacent nav items share an icon.** `Sidebar.vue:722` (Account Settings) and
`Sidebar.vue:853` (Audit Logs) are both `i-lucide-briefcase`. Severity: low.

**V20 — Add-button colour is arbitrary.** `blue` on `Webhooks/Index.vue:159` and
`account/Index.vue:241`; default on `MultipleIntegrationHooks.vue:94`,
`DashboardApps/Index.vue:129`, `sla/Index.vue:161`, `data/Index.vue:227`; `teal` on
`integrations/Shopify.vue:120`; `color="slate"` on `templates/Index.vue:397`. Severity: medium.

### 3.5 Empty-state quality

**V21 — Two tiers of empty state for the same situation.** `data/Index.vue:268-291` and `:243-266` are
designed: icon medallion, heading, description, and a CTA. `templates/Index.vue:336`, `sla/Index.vue:181`,
`Webhooks/Index.vue:132`, `DashboardApps/Index.vue:105` and `auditlogs/Index.vue:156-158` are a single
centred sentence from `SettingsLayout.vue:31-36` with no icon, no explanation and **no CTA**, even though
every one of those pages has an Add button sitting in the header. Severity: high.

**V22 — The templates page can show an empty state it cannot resolve.** `settings_templates` has no
feature flag or channel precondition (`templates/templates.routes.js:11-19`) and the nav item is
ungated (`Sidebar.vue:780-785`), so an admin with no WhatsApp inbox lands on
`WHATSAPP_TEMPLATE_MGMT.EMPTY` ("No WhatsApp templates found.") with a Sync button that is disabled
because `whatsappInboxes.length === 0` (`templates/Index.vue:400`). No link to Inboxes. Severity: medium.

**V23 — `SLA.LIST.EMPTY` exists but is never rendered.** `sla/Index.vue:181` uses `SLA.LIST.404`;
`i18n/locale/en/sla.json` defines both `404` and `EMPTY` under `SLA.LIST`. One of the two strings is
unreachable. Severity: low.

### 3.6 Table usability

**V24 — No table on this surface is sortable, and no header is scroll-safe.** `BaseTable` supports
`sortableColumns` / `sortBy` / `sortOrder` / `@sort` (`BaseTable.vue:22-36, 107-126`), `stickyHeader`
(`:38-41, 92`), `loading` skeleton rows (`:18-21, 42-46, 134-139`) and `scrollable` (`:51-54`).
A grep across `account auditlogs billing data integrations profile security sla subscription templates`
for `scrollable|sticky-header|sortable-columns|@sort|:loading=` returns nothing. The audit log is the
only place a sort exists, and it is a bespoke dropdown restricted to newest/oldest on one column
(`AuditLogFilters.vue:96-112`). SLA cannot be sorted by threshold; webhooks cannot be sorted by URL.
Severity: medium.

**V25 — Audit log is the only paginated list.** `auditlogs/Index.vue:236-242` uses
`PaginationFooter`. Webhooks, dashboard apps, SLAs, integration hooks, templates and data imports all
render their full result set (`Webhooks/Index.vue:177-186`, `templates/Index.vue:417-424`,
`data/Index.vue:293-369`). Severity: medium.

**V26 — Row-action discoverability varies by table.** Webhooks and dashboard apps expose edit + delete as
always-visible icon buttons (`WebhookRow.vue:60-82`, `DashboardAppsRow.vue:36-64`); SLA and integration
hooks expose delete only (`sla/Index.vue:284-297`, `MultipleIntegrationHooks.vue:127-141`); the
templates and data-import "tables" are clickable rows with one eye button
(`TemplateCard.vue:81-91`, `data/Index.vue:359-367`); and `BaseSettingsListItem.vue:44-49` — unused here
— puts actions in a `group-hover:flex` rail that is invisible until hover and unreachable by touch.
Severity: medium.

**V27 — Six-column SLA table has no responsive strategy.** `sla/Index.vue:238-284` fixes
`w-40` + `w-24` ×3 + `w-12` on five of six columns with no `scrollable`. Severity: medium (see V31).

### 3.7 Mobile behaviour

**V28 — Search is unavailable on phones across the entire surface.**
`components/BaseSettingsHeader.vue:107` applies `hidden sm:flex` to the search input. Every
`searchPlaceholder` consumer therefore loses search below 640px: integrations
(`integrations/Index.vue:39`), webhooks (`Webhooks/Index.vue:142-146`), dashboard apps
(`DashboardApps/Index.vue:113-115`), audit logs (`auditlogs/Index.vue:166`), SLA
(`sla/Index.vue:150-152`), templates (`templates/Index.vue:345-347`), integration hooks
(`MultipleIntegrationHooks.vue:86`). There is no mobile alternative — no search icon, no filter sheet.
Severity: high.

**V29 — The "Learn more" help link is also desktop-only.** `BaseSettingsHeader.vue:79`
(`hidden … sm:inline-flex`). On a phone there is no route to the documentation from any settings page.
Severity: medium.

**V30 — The data-import live indicator is hidden on mobile.** `data/Index.vue:208`
(`hidden … sm:inline-flex`) hides "Live, refreshing every 5s", while the pulsing dot per row
(`:328-334`) stays. On a phone the list silently mutates with no explanation. Severity: low.

**V31 — Tables overflow the page on phones.** `BaseTable` defaults `scrollable: false`
(`BaseTable.vue:51-54`), nothing on this surface opts in (V24), and the audit-log cells force
`whitespace-nowrap` on both the activity sentence and the timestamp
(`auditlogs/Index.vue:208, 216`). A long activity sentence therefore pushes the table wider than the
viewport with no horizontal scroll container. Severity: high.

**V32 — The notification matrix is implemented twice, once per breakpoint.**
`NotificationPreferences.vue:162-225` (desktop grid) and `:226-272` (mobile stacked lists) render the
same 8 notification types from the same data with separate markup — so the mobile layout loses the
column headings that explain which column is email and which is push, and any future type must be added
in two places. Severity: medium.

**V33 — Dynamic Tailwind column classes.** `NotificationPreferences.vue:213` builds
`` `col-span-${type === 'push' ? 3 : 2}` `` and `NotificationCheckBox.vue:44` builds
`` `col-span-${span}` ``. These only render because `col-span-2` and `col-span-3` happen to appear
literally in other scanned files (`components/widgets/TableHeaderCell.vue`,
`account/components/SectionLayout.vue:49`). Removing those literals elsewhere would silently break this
layout. Severity: low (fragility, not a current defect).

### 3.8 RTL behaviour

**V34 — Physical margins in the Slack warning card.** `integrations/Slack/SelectChannelWarning.vue:70`
`ml-3` (icon→text gap), `:81` `ml-8` (control indent) and `:94` `mr-4` (select→button gap) are all
physical. In Arabic the icon gap collapses to the wrong side and the indent hangs off the opposite edge.
`integrations/Webhooks/WebhookForm.vue:174` (`mr-2` on the event checkbox) and
`sla/SlaTimeInput.vue:107` (`pr-7` on the unit select, reserving space for the chevron) have the same
problem — in RTL the chevron overlaps the text. Severity: medium. These are the only four offenders:
a scan of `ml-|mr-|pl-|pr-` without an `ltr:`/`rtl:` prefix across the surface returns exactly
`SelectChannelWarning.vue` (3), `SlaTimeInput.vue` (1), `WebhookForm.vue` (1) and the dead
`billing/components/CreditPackageCard.vue` (1).

**V35 — An English connector is concatenated into a sentence.**
`profile/ActiveSessions.vue:54` builds the device label with `parts.join(' on ')` — "Chrome 120 on
macOS". Untranslatable, and in Arabic it injects a Latin word mid-sentence. Severity: medium.

**V36 — Dropdown anchoring uses logical properties in one filter bar and physical overrides in the
other.** `AuditLogFilters.vue:209` uses `start-0`; `templates/Index.vue:378` uses
`ltr:left-0 rtl:right-0` for the identical component. Both work; they should not differ. Severity: low.

**V37 — `BuildInfo` divider is direction-agnostic by luck.**
`account/components/BuildInfo.vue:45` uses `divide-x divide-n-slate-9` between version and build id;
the two items read in source order regardless of direction, so in RTL the build id leads. Severity: low.

### 3.9 Loading and error behaviour

**V38 — The data-imports list has no error state at all.** `data/Index.vue:81-84` `fetchImports` has no
`try/catch`, and `refresh` (`:119-133`) only resets flags in `finally`. If `DataImportsAPI.get()`
rejects, `dataImports` stays `[]`, `isLoading` goes false, and the page renders the **empty state**
(`:268-291`) — "No imports yet" with a "New import" CTA — for what is actually a failed request.
`data/Show.vue:50-78` has the same shape: `fetchImport` has a `finally` but no `catch`, so a failed
detail load leaves `dataImport` null and renders a blank body (`:231`). Severity: high.

**V39 — Two pages declare a loading message they can never show, and both borrow it from another
module.** `billing/ProviderIndex.vue:28` uses `$t('ATTRIBUTES_MGMT.LOADING')`, whose English value is
**"Fetching custom attributes"** (`i18n/locale/en/attributesMgmt.json`), as the billing page's loading
copy. `security/Index.vue:34` passes the same key as `:loading-message` but never sets `is-loading`, so
`SettingsLayout.vue:28` never renders it — the SAML page has no loading state while
`SamlSettings.vue:63-88` fetches (it relies on `hideContent` instead, `:175`). Severity: medium.

**V40 — Four error-reporting conventions.** Toast via `useAlert`: `auditlogs/Index.vue:58`,
`templates/Index.vue:294`, `sla/Index.vue:114`, `profile/ActiveSessions.vue:72`. Inline banner:
`subscription/Index.vue:381-386`, `integrations/Shopify.vue:126-133`,
`billing/ShopifyBilling.vue:190-203`. `SettingsLayout` `noRecordsFound` misused as an error slot:
`subscription/Index.vue:350-351`. Silent swallow: `profile/MfaSettings.vue:50-52`
(`// Handle error silently`), `account/Index.vue:126-128` (`// Ignore error`),
`MfaSetupWizard.vue:61-63` (QR generation returns `null`),
`NotificationPreferences.vue:102-104` (`// error`). A failed MFA status read shows the user the
"not enabled" card as if MFA were simply off. Severity: high.

**V41 — The MFA wizard advances past a rejected verification code.**
`MfaSetupWizard.vue:79-88` wraps `emit('verify', …)` in `try/catch`, but `emit` is synchronous and
returns `undefined` — the parent's `async verifyCode` (`MfaSettings.vue:79-93`) rejects later, on its own
promise. So line `:83` `setupStep.value = 'backup'` always runs. On a wrong code the user is moved to
step 2 and shown an **empty backup-codes grid** (`:268-279`, `backupCodes` is still `[]`), while the
error that `MfaSettings.vue:88-91` writes via `handleVerificationError` lands on the step-1 input that is
no longer rendered. The local `catch` at `:85-87` is unreachable. Severity: high.

**V42 — Only one download path reports failure.** `data/Show.vue:159-179` wraps both CSV downloads in
`try/finally` with no `catch`, so a failed export just stops the spinner. Compare
`:132-146` `retryImport`, which does catch and toast. Severity: medium.

**V43 — `abandonImport` cannot fail visibly.** `data/Show.vue:120-130` has `try/finally` and no
`catch`; a rejected abandon leaves the import running with no message. Severity: medium.

### 3.10 Accessibility

**V44 — Three table header cells expose their own source code as the accessible label.**
`NotificationPreferences.vue:168`, `:176` and `:184` pass `label` **unbound**:
`label="`${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE')}`"`. Without `:`, Vue treats this as a
static string, so the `label` prop that `TableHeaderCell` receives is the literal text
``` `${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE')}` ```. The visible text is correct (it comes
from the slot immediately below), but anything consuming the prop gets the template expression.
Severity: high.

**V45 — The notification matrix is not a table.** `NotificationPreferences.vue:162-225` builds the grid
from `div`s with `grid-cols-12`; the checkboxes at `:215-221` carry no `aria-label` and no `id`/`for`
pairing with the row's type name at `:205-207`, so a screen reader reads an unlabelled checkbox with no
column context. The mobile variant does pair them (`:237-242` `id` + adjacent text) but still has no
`label for=`. Severity: high.

**V46 — Bare English strings in user-visible positions.** Audio tone names
`'Ding' 'Bell' 'Chime' 'Magic' 'Ping'` (`profile/AudioAlertTone.vue:22-43`); SLA unit names
`'minutes' 'hours' 'days'` (`sla/SlaTimeInput.vue:32-37`); the Shopify URL validation message
`'Please enter a valid Shopify store URL (e.g., your-store.myshopify.com)'`
(`integrations/Shopify.vue:64-66`); the import source label `'File import'`
(`data/importSources.js:20`, rendered as the Source tile value via
`ImportSummaryTiles.vue:54`); hotkey card alt text `` `Light themed image for ${hotKey.title}` ``
(`profile/Index.vue:306, 311`); `alt="MFA QR Code"` (`MfaSetupWizard.vue:172`). Severity: medium — the
project rule is no bare strings in templates.

**V47 — The brand name is hardcoded in the MFA backup-code export, twice.**
`MfaSetupWizard.vue:102` and `MfaManagementActions.vue:46` both emit
`` `Chatwoot Two-Factor Authentication Backup Codes\n\n…\n\nKeep these codes in a safe place.` `` and
download it as `chatwoot-backup-codes.txt` (`:107`, `:51`). `account/components/BuildInfo.vue:40` renders
`GENERAL_SETTINGS.UPDATE_CHATWOOT` — "An update {v} for **Chatwoot** is available" — without
`replaceInstallationName`, unlike its neighbours (`integrations/Index.vue:42`,
`profile/Index.vue:118`). On a white-labelled install all four leak the upstream brand.
Severity: medium.

**V48 — A non-theme-aware colour on the SAML page.** `security/Index.vue:46` styles the
"SAML disabled" message `text-slate-600`. `tailwind.config.js:256-263` sets `theme.colors` (replacing,
not extending, the default palette), so `slate-600` resolves to the legacy fixed ramp
`slate.slate11` in `theme/colors.js:64` with no dark-mode variant — unlike every other body copy on the
surface, which uses `text-n-slate-11`. In dark mode this message renders mid-grey on a dark surface.
Severity: medium.

**V49 — Two profile rows use the `n-gray` ramp while the whole surface uses `n-slate`.**
`profile/FontSize.vue:36, 39` and `profile/UserLanguageSelect.vue:78, 81` use
`text-n-gray-12` / `text-n-gray-11`. Both ramps are defined and both have dark values
(`theme/colors.js:198-212`, `assets/scss/_next-colors.scss:94-95, 256-257`), but they are different
greys — so the two rows of the "Interface" section render in a slightly different colour from every
other label on the page. These are the only two `n-gray` users anywhere under `settings/`.
Severity: low.

**V50 — A global, unscoped stylesheet ships from a modal.**
`integrations/NewHook.vue:172-205` is a `<style lang="css">` block (not scoped) defining `.formkit-outer`,
`.formkit-form`, `.formkit-input`, `.formkit-message`, `.formkit-messages`, `.formkit-actions` and
`[data-invalid] .formkit-message`, including a raw `margin-bottom: 0px !important` (`:187`). It leaks to
every FormKit form in the application for as long as this component is loaded, and it is the only
`<style>` block on the surface. Severity: medium.

**V51 — The collapsible disclosure animates a property that cannot animate.**
`security/components/SamlAttributeMap.vue:34-35` sets `transition-[height]` then toggles
`h-auto` / `h-0`; `height: auto` is not interpolable, so the panel snaps. The same file's sibling
`data/components/ImportLogSection.vue:78-79` does it correctly with
`transition-[grid-template-rows]` + `grid-rows-[1fr]`/`grid-rows-[0fr]`, and
`account/components/SectionLayout.vue:16, 54-55` uses the `[interpolate-size:allow-keywords]` escape
hatch. Three approaches, one broken. Severity: low.

**V52 — `cursor-help` tooltips are mouse-only.** The SLA threshold explanations
(`sla/Index.vue:193-197, 205-209, 217-221`) and the SAML field hints
(`SamlInfoSection.vue:68-71, 84-87`) live entirely in `v-tooltip` on a non-focusable `<Icon>`/`<i>`, with
no `aria-label`, no `tabindex` and no text alternative. On touch and by keyboard, the only explanation of
what FRT / NRT / RT mean is unreachable. Severity: medium.

**V53 — Leftover debug logging.** `NotificationPreferences.vue:118-119` ships
`// eslint-disable-next-line no-console` + `console.log(error)`. Severity: low.

**V54 — Install-type gating is missing from the sidebar.**
`components-next/sidebar/provider.js:129-147` computes `resolveInstallationType` and `isAllowed` uses it,
but `components-next/sidebar/SidebarGroup.vue:245-249` passes only `:permissions` and `:feature-flag` to
`<Policy>` — even though `components/policy.vue:18-21` accepts `installationTypes`. For audit logs,
whose route requires `installationTypes: [CLOUD, ENTERPRISE]`
(`auditlogs/audit.routes.js:26-29`), the nav item is gated on flag + role only. In practice the feature
flag covers it, but the two gates have diverged. Severity: low.

**V55 — The subscription page bypasses vue-i18n entirely.**
`subscription/Index.vue:14-123` is a hand-written 110-line bilingual dictionary (`TEXT.en` / `TEXT.ar`)
with its own `t()` and `{param}` interpolation (`:129-135`), selected by sniffing
`String(locale.value).startsWith('ar')` (`:126-128`). No `SUBSCRIPTION.*` key exists anywhere under
`i18n/locale/en/`. Consequences: the page is hard-locked to two languages and falls back to English for
the other ~30 enabled locales; none of its copy reaches Crowdin; its plurals and currency wording cannot
use the i18n plural syntax every other page relies on (contrast
`i18n/locale/en/auditLogs.json` `COUNT: "{n} event | {n} events"`); and `formatMoney`
(`:190-199`) hardcodes `'ar'`/`'en'` as the `Intl` locale rather than the active one.
Severity: high — this is the largest single divergence on the surface.

---

## 4. What this surface already does well (must not be lost)

1. **`BaseSettingsHeader` is a genuinely good, complete header contract.** Title, description,
   help link, back button, search, tabs, count, actions and a free `#meta` slot
   (`components/BaseSettingsHeader.vue:43-130`), with sensible responsive reflow
   (`:93` `flex-wrap sm:flex-nowrap`, `:121` `flex-row-reverse sm:flex-row` so the primary action
   stays thumb-side on mobile). 14 of the pages on this surface already use it. Keep the slot shape.

2. **Audit log filter state lives in the URL.** `auditlogs/Index.vue:62-69` +
   `helper/auditlogHelper.js:266-288` make every filtered view shareable, bookmarkable and
   back-button-correct, and `route.meta.reuseOnQueryChange` (`audit.routes.js:24`,
   `SettingsWrapper.vue:16-18`) stops the page remounting on each keystroke. No other list on the
   surface does this; it is the pattern the others should grow toward, not away from.

3. **The search box is genuinely careful.** `auditlogs/Index.vue:118-136` debounces at 500 ms, ignores
   queries under 3 characters, tracks what it last pushed so a URL echo cannot clobber in-flight typing,
   and bails if the user has already navigated away (`:63-64`). That is three real bugs pre-empted.

4. **Data imports is the strongest page here.** Designed empty states with CTAs
   (`data/Index.vue:268-291`), a separate designed "coming soon" state (`:243-266`), polling that
   stops itself when work finishes (`:106-109`), pauses on a hidden tab (`:93-101`), and tears down on
   both `onDeactivated` and `onBeforeUnmount` (`:170-180`); request-versioning so a retry invalidates
   in-flight reads (`data/Show.vue:55-66`); sections auto-collapsed when empty (`data/Show.vue:192-194`);
   download buttons disabled at zero (`ImportLogSection.vue:72`); and a real progress model
   (`ImportProgress.vue:31-51`) that distinguishes "no total known" from "0%".

5. **Templates handles multi-source fetching honestly.** `Promise.allSettled` with distinct
   partial-failure and total-failure messages (`templates/Index.vue:290-299, 316-322`),
   `useAbortableRequest` with abort on deactivate (`:50-54, 327-328`), per-inbox cache pruned when an
   inbox disappears (`:262-267`), and filter values reset when the option they pointed at is gone
   (`:277-288`). Search tries exact substring before fuzzy (`:202-213`) — the right priority.

6. **Row activation is keyboard-accessible where it was hand-rolled.**
   `templates/TemplateCard.vue:36-43` and `data/Index.vue:297-302` both carry `role="button"`,
   `tabindex="0"`, `@keydown.enter` and `@keydown.space.prevent`, and their inner buttons use
   `@click.stop` (`TemplateCard.vue:90`, `data/Index.vue:366`) so the row and the button do not
   double-fire.

7. **Icon-only buttons consistently carry both a tooltip and an `aria-label`.**
   `WebhookRow.vue:63-64, 73-74`, `DashboardAppsRow.vue:39-44, 51-56`,
   `MultipleIntegrationHooks.vue:130-133`, `sla/Index.vue:287-288`,
   `TemplateCard.vue:82-89`, `data/Index.vue:223-224, 360-361`. This is done right nearly everywhere and
   is easy to lose in a rewrite.

8. **Secret handling is thoughtful.** Webhook secrets are masked by default with an explicit reveal
   (`WebhookForm.vue:128-157`), shown once in full immediately after creation with its own explanatory
   screen (`NewWebHook.vue:46-83`), and the access token uses a two-step inline confirm for reset rather
   than a modal (`AccessToken.vue:70-82`).

9. **The paywall is a single component with four correct audiences.**
   `components/BasePaywallModal.vue:56-77` distinguishes cloud-admin (upgrade button),
   cloud-non-admin (ask your admin), self-hosted-superadmin (`/super_admin` link) and
   self-hosted-non-superadmin (ask your admin). That matrix is easy to get wrong and is centralised here.

10. **`replaceInstallationName` is applied at most of the right call sites.**
    `integrations/Index.vue:42`, `IntegrationItem.vue:87`, `Integration.vue:85`,
    `SingleIntegrationHooks.vue:42`, `NewHook.vue:129`, `Webhooks/Index.vue:140`,
    `NewWebHook.vue:88`, `SlackMessageMode.vue:54-58`, `SlackIntegrationHelpText.vue:28-31`,
    `SelectChannelWarning.vue:35`, `ShopifyBilling.vue:172, 209`, `profile/Index.vue:118, 254`.

11. **Entitlement checks gate the fetch, not just the view.**
    `Webhooks/Index.vue:75-82` defers `webhooks/get` until `apiAndWebhooksEnabled` is known, so a
    paywalled account never issues the request; `SamlSettings.vue:64` returns early without a feature.

12. **Billing's Shopify path degrades in stages.** First read, then forced refresh
    (`ShopifyBilling.vue:123-154`), with three distinct outcomes: fresh, **stale-but-usable** with a
    warning banner (`:178-188`), and hard failure with a Retry (`:190-203`). It also cleans the
    OAuth return params out of the URL (`:118-121`). That stale tier is unusual and worth keeping.

13. **`BaseTable` already has the capabilities this surface needs.** Sorting with `aria-sort` and
    per-column opt-out, sticky header, skeleton loading rows, a `scrollable` container, and headers that
    survive the empty state (`BaseTable.vue:22-54, 65-66, 95-131`). The modernization does not need to
    build these — only to adopt them (V24).

14. **Field-level validation copy is specific, not generic.** `sla/SlaForm.vue:71-81` distinguishes
    "required" from "too short"; `SamlSettings.vue:45-61` gives each SAML field its own message;
    `DashboardAppModal.vue:126-130, 143-147` pairs each error with its field.

15. **Destructive confirmations name the object.** The webhook URL
    (`Webhooks/Index.vue:215-219`), the app title (`DashboardApps/Index.vue:170-174`), the SLA name
    (`sla/Index.vue:313`), and the account name typed out in full
    (`AccountDelete.vue:142-143`).
