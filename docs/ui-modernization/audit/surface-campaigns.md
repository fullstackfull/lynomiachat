# Surface audit — Campaigns (live chat, SMS, WhatsApp) and WhatsApp campaign analytics

Read-only audit. This document is the **baseline** for the feature-preservation contract of the
visual/interaction modernization phase. Every assertion is anchored to `file:line` in the current tree.
Nothing here proposes a redesign; it records what exists.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`.

Files in scope (paths relative to `app/javascript/dashboard/` unless stated):

| File | Lines | Role |
|---|---|---|
| `routes/dashboard/campaigns/campaigns.routes.js` | 78 | Route tree, two legacy redirects, feature flags, permission gate |
| `routes/dashboard/campaigns/pages/CampaignsPageRouteView.vue` | 28 | Parent route view: keep-alive wrapper, campaigns + labels fetch |
| `routes/dashboard/campaigns/pages/LiveChatCampaignsPage.vue` | 87 | Live chat list page: create popover, edit dialog, delete dialog, empty state |
| `routes/dashboard/campaigns/pages/SMSCampaignsPage.vue` | 72 | SMS list page: create popover, delete dialog, empty state |
| `routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue` | 120 | WhatsApp list page + `?audience=` prefill + analytics navigation |
| `routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue` | 503 | Analytics page: banner, metrics, breakdown, status tabs, table, pagination, polling |
| `routes/dashboard/campaigns/pages/specs/WhatsAppCampaignsPage.spec.js` | 80+ | Only spec on the surface; pins the audience prefill |
| `components-next/Campaigns/CampaignLayout.vue` | 57 | List page shell: title, "Create campaign" button, popover anchor, click-outside close |
| `components-next/Campaigns/CampaignAnalyticsLayout.vue` | 32 | Analytics shell: breadcrumb header + scrolling main |
| `components-next/Campaigns/Pages/CampaignPage/CampaignList.vue` | 49 | Card list; decides which card actions exist |
| `components-next/Campaigns/CampaignCard/CampaignCard.vue` | 165 | One campaign row-card: title, status pill, message preview, details, 1–2 actions |
| `components-next/Campaigns/CampaignCard/LiveChatCampaignDetails.vue` | 56 | "Sent by <sender> from <inbox>" meta line |
| `components-next/Campaigns/CampaignCard/SMSCampaignDetails.vue` | 41 | "Sent from <inbox> on <date>" meta line |
| `components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue` | 54 | Create popover (live chat) |
| `components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignForm.vue` | 323 | Live chat form: title, editor, inbox, sender, URL, time on page, 2 checkboxes |
| `components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/EditLiveChatCampaignDialog.vue` | 74 | Edit modal (live chat only) |
| `components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue` | 49 | Create popover (SMS) |
| `components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignForm.vue` | 181 | SMS form: title, textarea, inbox, recipients, schedule |
| `components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue` | 58 | Create popover (WhatsApp) |
| `components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue` | 268 | WhatsApp form: title, inbox, template, parser, recipients, schedule |
| `components-next/Campaigns/Pages/CampaignPage/CampaignRecipients.vue` | 126 | Shared recipients fieldset: labels + shared audiences + live server-side count |
| `components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue` | 49 | Destructive confirm (all three channels) |
| `components-next/Campaigns/EmptyState/CampaignEmptyStateContent.js` | 212 | 4 ongoing + 4 one-off fake campaigns used as empty-state wallpaper |
| `components-next/Campaigns/EmptyState/LiveChatCampaignEmptyState.vue` | 38 | Live chat empty state |
| `components-next/Campaigns/EmptyState/SMSCampaignEmptyState.vue` | 37 | SMS empty state |
| `components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue` | 37 | WhatsApp empty state (reuses the SMS fixtures) |
| `components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignMetricCard.vue` | 54 | One metric tile: label, hover hint, value, rate, skeleton |
| `components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue` | 134 | Percentage bar + 5-segment legend + delivery rate |
| `components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue` | 165 | Deliveries card: title, filter slot, 4-column table, footer slot |
| `components-next/Campaigns/Pages/CampaignAnalyticsPage/DeliveryStatusBadge.vue` | 40 | 6 status badges |
| `components-next/whatsapp/WhatsAppTemplateParser.vue` | 355 | Template preview + per-variable inputs (shared with the conversation composer) |
| `store/modules/campaigns.js` | 125 | Records, 3 channel getters, ui flags, CRUD actions |
| `api/campaigns.js` | 26 | CRUD + `analyticsMetrics`, `analyticsContacts`, `audiencePreview` |
| `i18n/locale/en/campaign.json` | 324 | All copy for the surface |

Shared components read for this surface: `components-next/CardLayout.vue`,
`components-next/EmptyStateLayout.vue`, `components-next/dialog/Dialog.vue`,
`components-next/button/Button.vue`, `components-next/input/Input.vue`,
`components-next/textarea/TextArea.vue`, `components-next/Editor/Editor.vue`,
`components-next/combobox/{ComboBox,ComboBoxDropdown,TagMultiSelectComboBox}.vue`,
`components-next/table/{BaseTable,BaseTableRow,BaseTableCell}.vue`,
`components-next/tabbar/TabBar.vue`, `components-next/pagination/PaginationFooter.vue`,
`components-next/banner/Banner.vue`, `components-next/breadcrumb/Breadcrumb.vue`,
`components-next/spinner/Spinner.vue`, `components-next/avatar/Avatar.vue`,
`components-next/icon/Icon.vue`, `components-next/sidebar/{Sidebar,SidebarGroup,provider}.vue|js`,
`components-next/Contacts/ContactsHeader/{ContactListHeaderWrapper.vue,components/ContactMoreActions.vue}`,
`composables/{useConfig,useAbortableRequest}.js`, `composables/commands/useGoToCommandHotKeys.js`,
`helper/{audienceHelper,inbox,templateHelper,routeHelpers,permissionsHelper}.js`,
`shared/constants/campaign.js`, `shared/helpers/timeHelper.js`,
`app/views/api/v1/models/_campaign.json.jbuilder`.

---

## 1. Routes and the primary task

### 1.1 Routes

| Path | Name | Component | Gate |
|---|---|---|---|
| `/app/accounts/:accountId/campaigns` | — | `CampaignsPageRouteView` | none on the parent itself (`campaigns.routes.js:18-19`) |
| `…/campaigns` (empty child) | — | redirect → `campaigns_ongoing_index` | no `meta`, so **ungated** (`campaigns.routes.js:21-26`) |
| `…/campaigns/ongoing` | `campaigns_ongoing_index` | redirect → `campaigns_livechat_index` | `campaigns` flag + `administrator` (`:27-34`) |
| `…/campaigns/one_off` | `campaigns_one_off_index` | redirect → `campaigns_sms_index` | `campaigns` flag + `administrator` (`:35-42`) |
| `…/campaigns/live_chat` | `campaigns_livechat_index` | `LiveChatCampaignsPage` | `campaigns` flag + `administrator` (`:43-48`) |
| `…/campaigns/sms` | `campaigns_sms_index` | `SMSCampaignsPage` | `campaigns` flag + `administrator` (`:49-54`) |
| `…/campaigns/whatsapp` | `campaigns_whatsapp_index` | `WhatsAppCampaignsPage` | `whatsapp_campaign` flag + `administrator` (`:55-63`) |
| `…/campaigns/whatsapp/:campaignId/analytics` | `campaigns_whatsapp_analytics` | `WhatsAppCampaignAnalyticsPage` | `whatsapp_campaign` flag + `administrator` (`:64-72`) |

`meta` is one shared object (`campaigns.routes.js:10-13`): `featureFlag: FEATURE_FLAGS.CAMPAIGNS`
(`'campaigns'`, `featureFlags.js:8`) and `permissions: ['administrator']`. The WhatsApp routes override
only the flag with `FEATURE_FLAGS.WHATSAPP_CAMPAIGNS` (`'whatsapp_campaign'`, `featureFlags.js:9`).
Permission enforcement is the global router guard: `routeIsAccessibleFor` reads `meta.permissions` and
redirects elsewhere when the account's permissions do not include one of them
(`helper/routeHelpers.js:15-18, 40-54`). **There is no agent-visible read-only mode for campaigns** —
either you are an administrator and get the full surface including delete, or you never reach it.

`campaigns_ongoing_index` and `campaigns_one_off_index` exist only as redirects for the pre-split URLs;
nothing in the app links to them any more (`campaigns.routes.js:27-42`).

### 1.2 Primary task

Create and supervise outbound/proactive messaging per channel. Concretely: (a) on each of three sibling
pages, read a flat list of that channel's campaigns with their status, (b) create a new campaign through a
popover form anchored to the page's single primary button, (c) delete any campaign, edit only a live chat
one, and (d) for a WhatsApp campaign that has started, open a per-campaign analytics page and inspect
per-contact delivery.

The three list pages are **not tabs of one page**. They are three routes with three components, reached
only from the sidebar; the pages themselves have no switcher between channels
(`CampaignLayout.vue:23-56` has a title and one button and nothing else).

### 1.3 Layout chain

`CampaignsPageRouteView` is the parent for all four leaf pages: a column flex container,
`overflow-auto bg-n-surface-1`, holding a `<router-view>` whose component is wrapped in `<keep-alive>`
by default (`CampaignsPageRouteView.vue:5-7, 18-26`). Consequences that the later work must preserve:

- All four pages stay mounted once visited. The WhatsApp page relies on this and uses `onActivated`, not
  `onMounted`, for the `?audience=` prefill (`WhatsAppCampaignsPage.vue:51-67`), and the analytics page
  keys its full refresh on `campaignId` rather than mount (`WhatsAppCampaignAnalyticsPage.vue:328-353`)
  and starts/stops polling in `onActivated`/`onDeactivated` (`:369-377`).
- The campaigns list and the account's labels are fetched **once, on parent mount**
  (`CampaignsPageRouteView.vue:11-14`). There is no refetch when you return to a page, and no refresh
  control anywhere on the surface.
- Shared audiences are *not* fetched here. `CampaignRecipients` reads
  `customViews/getContactCustomViews` (`CampaignRecipients.vue:29`) which the Sidebar populates
  (`Sidebar.vue:268-269`); the WhatsApp page additionally dispatches `customViews/get` only on the
  audience-prefill path (`WhatsAppCampaignsPage.vue:60`).

List pages then use `CampaignLayout` (sticky header + `max-w-5xl` centred main, `CampaignLayout.vue:24-55`)
and the analytics page uses `CampaignAnalyticsLayout` (same shell with a breadcrumb instead of a title,
`CampaignAnalyticsLayout.vue:15-31`).

### 1.4 Entry points into the surface

- Sidebar group "Campaigns", icon `i-lucide-megaphone`, with three children: Live chat, SMS, WhatsApp
  (`Sidebar.vue:645-666`). Each child is hidden when its route's flag/permission check fails
  (`components-next/sidebar/provider.js:117-147`). The analytics route has no sidebar entry; the WhatsApp
  child still highlights on it through the path-prefix fallback (`SidebarGroup.vue:189-193`).
- Command palette: "Go to Campaigns" → `campaigns_livechat_index`, icon megaphone, section General
  (`composables/commands/useGoToCommandHotKeys.js:68-74`), hidden unless flag + permission + paywall
  checks pass (same file, `isAvailable`).
- Cross-module: the Contacts audience header's "…" menu offers **"Use in a new WhatsApp campaign"**
  (`ContactMoreActions.vue:110-119`, label `CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USE_IN_CAMPAIGN`,
  icon `i-lucide-megaphone`), which pushes `campaigns_whatsapp_index?audience=<id>`
  (`ContactListHeaderWrapper.vue:255-259`). Gated on the filter being *shared* and on the user being able
  to reach `campaigns_whatsapp_index`.

---

## 2. FEATURE PARITY MANIFEST

Every control, action, state and affordance on this surface. **This table is the baseline a later
redesign is checked against.** "Gate" is the permission, feature flag or condition that makes it appear.

### 2.1 Entry points and shell

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 1 | Sidebar group "Campaigns" (`i-lucide-megaphone`), collapsible | navigation | `Sidebar.vue:645-649` | at least one child allowed |
| 2 | Sidebar child "Live chat" | navigation | `Sidebar.vue:651-655` | `campaigns` flag + `administrator` |
| 3 | Sidebar child "SMS" | navigation | `Sidebar.vue:656-660` | `campaigns` flag + `administrator` |
| 4 | Sidebar child "WhatsApp" | navigation | `Sidebar.vue:661-665` | `whatsapp_campaign` flag + `administrator` |
| 5 | Command palette item "Go to Campaigns" → live chat page | shortcut | `useGoToCommandHotKeys.js:68-74` | flag + permission + not paywalled |
| 6 | Contacts action "Use in a new WhatsApp campaign" | navigation | `ContactMoreActions.vue:110-119`, `ContactListHeaderWrapper.vue:255-259` | filter is shared **and** `campaigns_whatsapp_index` reachable |
| 7 | Deep link `?audience=<id>` opens the WhatsApp create dialog prefilled | contextual | `WhatsAppCampaignsPage.vue:56-67`, `helper/audienceHelper.js:14-21` | id must resolve to a *shared* contact view of this account |
| 8 | Query parameter deliberately left in the URL (shareable, survives reload) | state | `WhatsAppCampaignsPage.vue:51-55` | none |
| 9 | Unknown/foreign/personal audience id → ordinary empty dialog, silently | state | `WhatsAppCampaignsPage.vue:63-66`, `audienceHelper.js:38-39` | none |
| 10 | Legacy redirect `/campaigns` → `/campaigns/ongoing` → live chat | navigation | `campaigns.routes.js:21-34` | none on the first hop |
| 11 | Legacy redirect `/campaigns/one_off` → SMS | navigation | `campaigns.routes.js:35-42` | flag + permission |
| 12 | All four pages kept alive (state survives channel switching) | state | `CampaignsPageRouteView.vue:5-7, 22-24` | `keepAlive` prop, default `true` |
| 13 | Campaigns fetched once on parent mount | state | `CampaignsPageRouteView.vue:12` | none |
| 14 | Account labels fetched once on parent mount (for the recipients picker) | state | `CampaignsPageRouteView.vue:13` | none |

### 2.2 List page shell (`CampaignLayout`, all three channels)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 15 | Page title, `text-heading-1` (`"Live chat campaigns"` / `"SMS campaigns"` / `"WhatsApp campaigns"`) | navigation | `CampaignLayout.vue:28-30`; `campaign.json:4, 83, 137` | none |
| 16 | Fixed 5rem (`h-20`) header band, `sticky top-0 z-10` | state | `CampaignLayout.vue:25-27` | none |
| 17 | `max-w-5xl` centred content column, 24px gutters | state | `CampaignLayout.vue:26, 51-52` | none |
| 18 | Primary button "Create campaign" with `i-lucide-plus`, `size=sm`, hover brightness | primary | `CampaignLayout.vue:39-45`; label `campaign.json:5, 84, 138` | none (page already requires administrator) |
| 19 | Create form rendered as a popover anchored under the button (`#action` slot) | contextual | `CampaignLayout.vue:46`; pages `LiveChatCampaignsPage.vue:52-57`, `SMSCampaignsPage.vue:44-49`, `WhatsAppCampaignsPage.vue:90-96` | `v-if` on the local toggle |
| 20 | Click outside the button+popover closes the popover | contextual | `CampaignLayout.vue:32-37` (`v-on-click-outside`) | none |
| 21 | Click-outside ignores the ProseMirror "create link" prompt backdrop | state | `CampaignLayout.vue:34-35` | live chat editor only |
| 22 | Scrolling body (`overflow-y-auto`) with `py-4` | state | `CampaignLayout.vue:51-53` | none |
| 23 | Cards stacked in a single column, `gap-4` | state | `CampaignList.vue:27` | none |
| 24 | List order: ascending campaign id (oldest first), no sort control | state | `store/modules/campaigns.js:37` | none |
| — | *Absent by design today:* no search, no filter, no sort, no tabs, no bulk select, no pagination, no per-page count, no refresh, no export on any of the three list pages | — | `CampaignLayout.vue:23-56` | — |

### 2.3 List body states (per page)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 25 | Loading state: centred `Spinner`, `py-10`, `text-n-slate-11` | state (loading) | `LiveChatCampaignsPage.vue:59-64`, `SMSCampaignsPage.vue:50-55`, `WhatsAppCampaignsPage.vue:97-102` | `campaigns/getUIFlags.isFetching` |
| 26 | Populated state: `CampaignList` of cards | state | `LiveChatCampaignsPage.vue:65-71`, `SMSCampaignsPage.vue:56-60`, `WhatsAppCampaignsPage.vue:103-108` | `!hasNo…Campaigns` |
| 27 | Empty state (live chat), `pt-14` | state (empty) | `LiveChatCampaignsPage.vue:72-77`; copy `campaign.json:18-21` | `length === 0 && !isFetching` |
| 28 | Empty state (SMS), `pt-14` | state (empty) | `SMSCampaignsPage.vue:61-66`; copy `campaign.json:85-88` | same |
| 29 | Empty state (WhatsApp), `pt-14` | state (empty) | `WhatsAppCampaignsPage.vue:109-114`; copy `campaign.json:139-142` | same |
| 30 | Channel scoping: live chat = `ongoing` + `Channel::WebWidget` | state | `store/modules/campaigns.js:47-50` | none |
| 31 | Channel scoping: SMS = `one_off` + `Channel::Sms` **or** `Channel::TwilioSms` | state | `store/modules/campaigns.js:39-42` | none |
| 32 | Channel scoping: WhatsApp = `one_off` + `Channel::Whatsapp` | state | `store/modules/campaigns.js:43-46` | none |
| 33 | **No error state**: a failed list fetch is swallowed and renders as "empty" | state (error) | `store/modules/campaigns.js:62-64` (`// Ignore error`) | always |

### 2.4 Campaign card (`CampaignCard`, shared by all three channels and all three empty states)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 34 | Card container: `rounded-xl`, `bg-n-solid-2`, 1px inset outline, row layout, `px-6 py-5 gap-3` | state | `CardLayout.vue:22-31` (`layout="row"` from `CampaignCard.vue:100`) | none |
| 35 | Campaign title, `text-base font-medium`, `capitalize`, `line-clamp-1` | state | `CampaignCard.vue:103-107` | none |
| 36 | Status pill, `h-6 px-2 rounded-md bg-n-alpha-2`, `text-xs` | status | `CampaignCard.vue:108-113` | none |
| 37 | Live chat status text "Enabled" / "Disabled" | status | `CampaignCard.vue:69-74`; `campaign.json:7-10` | `isLiveChatType` |
| 38 | One-off status text "Processing" / "Completed" / "Scheduled" (fallback) | status | `CampaignCard.vue:76-85`; `campaign.json:90-94, 145-149` | `!isLiveChatType` |
| 39 | Status colour: teal when "active", slate-12 otherwise | status | `CampaignCard.vue:60-67` | `enabled` (live chat) / `status !== 'completed'` (one-off) |
| 40 | Message preview: sanitised rich HTML, `line-clamp-1`, fixed `h-6` | state | `CampaignCard.vue:115-118` (`v-dompurify-html` + `formatMessage`) | none |
| 41 | Live chat meta line "Sent by {avatar}{sender} from {icon}{inbox}" | state | `LiveChatCampaignDetails.vue:32-55`; `campaign.json:11-16` | `isLiveChatType` |
| 42 | Sender falls back to "Bot" when the campaign has no sender | state | `LiveChatCampaignDetails.vue:25-27` | `!sender?.name` |
| 43 | 16px sender avatar with thumbnail | state | `LiveChatCampaignDetails.vue:37-42` | none |
| 44 | One-off meta line "Sent from {icon}{inbox} on {date}" (`LLL d, h:mm a`) | state | `SMSCampaignDetails.vue:24-40`; `campaign.json:95-98, 150-153` | `!isLiveChatType` |
| 45 | Channel icon derived from `channel_type`/`medium`/`voice_enabled` | state | `CampaignCard.vue:89-96` → `helper/inbox.js` | none |
| 46 | Action column, fixed `w-20`, right aligned | state | `CampaignCard.vue:134` | none |
| 47 | "View analytics" icon button (`i-lucide-chart-no-axes-column`, faded slate) with tooltip + `aria-label` + `title` | contextual | `CampaignCard.vue:135-145`; `campaign.json:144` | `isEnterprise` **and** inbox is WhatsApp **and** status ∈ {`processing`,`completed`} (`CampaignList.vue:18-19, 39-43`) |
| 48 | "Edit campaign" icon button (`i-lucide-sliders-vertical`, faded slate), `aria-label` only | secondary | `CampaignCard.vue:146-154`; `campaign.json:320` | `isLiveChatType` |
| 49 | "Delete campaign" icon button (`i-lucide-trash`, faded **ruby**), `aria-label` only | destructive | `CampaignCard.vue:155-162`; `campaign.json:321` | always |
| 50 | Card body click emits `click` from `CardLayout` (unused here — no card-level navigation) | state | `CardLayout.vue:13-16, 30` | none |
| — | *Absent:* no duplicate, no pause/resume, no "send now", no inline enable toggle, no per-card menu, no trigger-URL/time-on-page/business-hours display, no audience display, no recipient count, no `description` field display | — | — | — |

### 2.5 Create popovers (three variants of the same pattern)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 51 | Popover: `w-[25rem]`, `absolute top-10`, `ltr:right-0 rtl:left-0`, `z-50`, `bg-n-alpha-3 backdrop-blur-[100px]`, `rounded-xl border border-n-weak shadow-md` | state | `LiveChatCampaignDialog.vue:42-44`, `SMSCampaignDialog.vue:41-43`, `WhatsAppCampaignDialog.vue:44-46` | popover open |
| 52 | Popover heading `h3`, `text-base font-medium` ("Create a live chat campaign" / "Create SMS campaign" / "Create WhatsApp campaign") | state | `LiveChatCampaignDialog.vue:45-47`, `SMSCampaignDialog.vue:44-46`, `WhatsAppCampaignDialog.vue:48-50`; `campaign.json:23, 101, 156` | none |
| 53 | Live chat popover scrolls internally at `max-h-[85vh]` | state | `LiveChatCampaignDialog.vue:43` | none |
| 54 | WhatsApp popover scrolls internally at `max-h-[80vh]`, padding moved to an inner wrapper | state | `WhatsAppCampaignDialog.vue:45-47` | none |
| 55 | SMS popover has **no** max height and **no** internal scroll | state | `SMSCampaignDialog.vue:42` | none |
| 56 | Success toast per channel | status | `LiveChatCampaignDialog.vue:24`, `SMSCampaignDialog.vue:24`, `WhatsAppCampaignDialog.vue:27`; `campaign.json:67, 130, 191` | create resolved |
| 57 | Error toast: server message if present, else generic copy | status (error) | `LiveChatCampaignDialog.vue:25-30`, `SMSCampaignDialog.vue:25-30`, `WhatsAppCampaignDialog.vue:28-33`; `campaign.json:68, 131, 192` | create rejected |
| 58 | Analytics event `CREATE_CAMPAIGN` with `type: ongoing` / `one_off` | state | `LiveChatCampaignDialog.vue:19-22`, `SMSCampaignDialog.vue:19-22`, `WhatsAppCampaignDialog.vue:23-26` | create resolved |
| 59 | Live chat popover closes immediately on submit (optimistic) | state | `LiveChatCampaignDialog.vue:35-38` | none |
| 60 | SMS/WhatsApp popovers close via the form's own `cancel` emit after reset | state | `SMSCampaignForm.vue:103-110`, `WhatsAppCampaignForm.vue:166-173` | valid submit |
| 61 | WhatsApp popover close also clears the audience prefill | state | `WhatsAppCampaignsPage.vue:69-73` | none |

### 2.6 Live chat campaign form (`LiveChatCampaignForm`, create **and** edit)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 62 | `mode` prop validated to `create` \| `edit`; drives the submit label | state | `LiveChatCampaignForm.vue:16-20, 312-316` | none |
| 63 | "Title" text input + placeholder + required error | state | `:209-215`; `campaign.json:27-31` | none |
| 64 | "Message" rich editor (ProseMirror) with placeholder, canned responses enabled by default | state | `:217-223`; `Editor.vue:99-119` | none |
| 65 | Character counter `N / 200` under the editor (advisory only, not enforced, no validation) | status | `Editor.vue:120-131` (`maxLength` default 200, `showCharacterCount` default true) | none |
| 66 | "Select Inbox" combobox, options = website inboxes only | state | `:225-238`; `store/modules/inboxes.js:101-103` | none |
| 67 | "Sent by" combobox, disabled until an inbox is chosen | state | `:240-254` | `!state.inboxId` disables |
| 68 | Sender list = hardcoded `{value: 0, label: 'Bot'}` + that inbox's members | state | `:94-97`, fetched `:117-133` (`inboxMembers/get`) | inbox selected |
| 69 | Sender-fetch failure shows a toast and empties the list | status (error) | `:123-132` | request rejected |
| 70 | "URL" input `type=url` + placeholder | state | `:256-263`; `campaign.json:47-51` | none |
| 71 | URL validation: valid `URLPattern` **and** starts with `http://`/`https://` | state | `:56-68, 75` | none |
| 72 | "Time on page(Seconds)" numeric input, default `10` | state | `:265-274`, default `:51`; `campaign.json:52-56` | none |
| 73 | "Other preferences" fieldset legend | state | `:276-279`; `campaign.json:57-61` | none |
| 74 | Native checkbox "Enable campaign", default checked | state | `:281-286`, default `:49` | none |
| 75 | Native checkbox "Trigger only during business hours", default unchecked | state | `:288-297`, default `:50` | none |
| 76 | Per-field inline error messages from Vuelidate (`$error`-gated) | state (error) | `:99-111` | field touched/invalid |
| 77 | Submit button disabled while `$invalid` or creating; shows spinner | state | `:312-320` | `v$.$invalid \|\| isCreating` |
| 78 | Cancel button (faded slate, blue text, full width) | secondary | `:304-311`; `campaign.json:64` | `showActionButtons` |
| 79 | Action-button row hidden in edit mode (`show-action-buttons=false`) | state | `:300-303`; `EditLiveChatCampaignDialog.vue:70` | `mode="edit"` |
| 80 | Form state reset + close after a successful create | state | `:148-157` | `mode === 'create'` |
| 81 | Edit hydration from the selected campaign (title, message, inbox, sender→0 for bot, enabled, business hours, URL, time on page) | state | `:159-182, 194-202` | `mode === 'edit'` |
| 82 | Payload shape: `trigger_rules: {url, time_on_page}`, `sender_id` null for bot | state | `:135-146` | none |

### 2.7 SMS campaign form (`SMSCampaignForm`, create only)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 83 | "Title" input + required error | state | `SMSCampaignForm.vue:115-121`; `campaign.json:105-109` | none |
| 84 | "Message" textarea with character counter `N / 200` — **hard capped** at 200 chars | state | `:123-130`; `TextArea.vue:171, 189-196` | `show-character-count` sets `maxlength` |
| 85 | "Select Inbox" combobox, options = SMS + Twilio-SMS inboxes | state | `:132-145`; `store/modules/inboxes.js:109-115` | none |
| 86 | Recipients fieldset (labels + shared audiences + live count) | state | `:147-151` → `CampaignRecipients.vue` | none |
| 87 | "Scheduled time" `datetime-local` input with `min` = now (local) | state | `:153-161`, `min` computed `:49-54`; `campaign.json:120-124` | none |
| 88 | Audience required unless a shared audience is chosen (`requiredIf`) | state (error) | `:40-42, 76-78` | neither selected |
| 89 | Submit disabled while `$invalid` or creating, spinner while creating | state | `:172-178` | none |
| 90 | Cancel button | secondary | `:164-171` | none |
| 91 | Payload: `scheduled_at` converted to a UTC ISO string | state | `:83-84, 96` | none |
| 92 | Payload: `audience` = `[{id,type:'Label'}…, {id,type:'Audience'}…]` | state | `:97-100`; `shared/constants/campaign.js:12-15` | none |
| 93 | Form reset + close after a valid submit | state | `:103-110` | none |

### 2.8 WhatsApp campaign form (`WhatsAppCampaignForm`, create only)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 94 | "Title" input + required error | state | `WhatsAppCampaignForm.vue:186-192`; `campaign.json:160-164` | none |
| 95 | "Select Inbox" combobox, options = WhatsApp inboxes | state | `:194-207`; `store/modules/inboxes.js:116-120` | none |
| 96 | "WhatsApp Template" combobox; empty until an inbox is chosen | state | `:209-221`, `:80-82` | `state.inboxId` |
| 97 | Template labels humanised: `_`→space, title-cased, language in parentheses | state | `:83-94` | none |
| 98 | Only "sendable" (approved) templates are offered | state | `store/modules/inboxes.js:53-73` (`isSendableTemplate`) | none |
| 99 | Hint under the picker: "Select a template to use for this campaign." | state | `:222-224`; `campaign.json:173` | none |
| 100 | Template selection resets when the inbox changes | state | `:176-181` | none |
| 101 | Template parser rendered once a template is selected | state | `:227-232` | `selectedTemplate` |
| 102 | Submit additionally blocked until every template parameter is filled | state | `:118-124` (`isFormInvalid === false` via `isWhatsAppComplete`) | none |
| 103 | Recipients fieldset, prefilled from `initialSharedAudienceIds` | state | `:234-238`, `:43-46` | prefill only via `?audience=` |
| 104 | "Scheduled time" `datetime-local` with `min` = now | state | `:240-248`; `campaign.json:181-185` | none |
| 105 | Payload: `message` = rendered template body; `template_params` = `{name, namespace, category, language, processed_params}` with `UTILITY`/`en_US` fallbacks | state | `:136-164` | none |
| 106 | Vuelidate reset on form reset | state | `:129-132` | none |
| 107 | Submit/cancel pair identical to SMS | primary / secondary | `:250-266` | none |

### 2.9 Recipients fieldset (`CampaignRecipients`, shared by SMS + WhatsApp)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 108 | `fieldset` + legend "Recipients" | state | `CampaignRecipients.vue:84-87`; `campaign.json:301` | none |
| 109 | "Labels" tag multi-select with search + removable tag chips | filter | `:92-99`; `TagMultiSelectComboBox.vue:114-169` | none |
| 110 | "Shared audiences" tag multi-select | filter | `:105-113`; `campaign.json:306-309` | none |
| 111 | Only **shared** contact views are offered as audiences | state | `:35-38` | `view.shared` |
| 112 | Audiences empty state: "No shared audiences yet. Save a contact filter as a shared audience in Contacts." | state (empty) | `:109`; `campaign.json:309` | no shared views |
| 113 | Live server-side recipient count, debounced 300ms, abortable | status | `:40-57`; `composables/useAbortableRequest.js:25-62`; `api/campaigns.js:15-17` | at least one label/audience selected |
| 114 | Count copy "Counting matching contacts…" while pending | state (loading) | `:72-73`; `campaign.json:313` | `isPending \|\| count === null` |
| 115 | Count copy pluralised: "No contacts match now." / "1 contact matches now." / "{n} contacts match now." | status | `:74-78`; `campaign.json:314` | count resolved |
| 116 | Dedup note appended: "Each contact receives the campaign once, and recipients are selected again when it is sent." | status | `:79`; `campaign.json:315` | count resolved |
| 117 | Count failure copy: "The number of matching contacts could not be loaded." (never shows 0) | state (error) | `:51-56, 71`; `campaign.json:316` | request rejected |
| 118 | Count cleared and request aborted when the selection becomes empty | state | `:59-67` | none |
| 119 | Validation error "Select at least one label or shared audience" replaces the count note | state (error) | `:115-117`; `campaign.json:311` | `message` prop set |
| 120 | Both pickers turn red together when the recipients error is present | state (error) | `:96, 110` (`:has-error="!!message"`) | same |
| 121 | Test hooks `campaign-recipients`, `campaign-recipient-labels`, `campaign-recipient-audiences`, `campaign-recipient-count` | state | `:84, 98, 112, 121` | none |

### 2.10 WhatsApp template parser (`WhatsAppTemplateParser`, as used by the campaign form)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 122 | Preview card `bg-n-alpha-black2 rounded-lg p-4` | state | `WhatsAppTemplateParser.vue:210` | none |
| 123 | Raw template name as `h3` + "Language: xx" on the same row | state | `:211-218, 51-53` | none |
| 124 | Live-rendered header text (variables substituted) | state | `:222-227, 102-107` | text header exists |
| 125 | Live-rendered body text, `whitespace-pre-wrap` | state | `:228-230, 109-114` | none |
| 126 | "Category: UTILITY/…" footnote | state | `:234-236, 55-57` | none |
| 127 | Media header section: URL input, label "{Type} Header" | state | `:239-260` | header format ∈ `MEDIA_FORMATS` |
| 128 | Document templates also ask for a document name | state | `:261-271, 86-88` | format = document |
| 129 | "Header variables" section, one input per placeholder | state | `:274-295` | header has `{{…}}` |
| 130 | "Variables" (body) section, one input per placeholder | state | `:297-318` | body params exist |
| 131 | "Button parameters" section, one input per button | state | `:320-337` | button params exist |
| 132 | Placeholder text per input: "Enter value for {variable}" | state | `:288-292, 311-315` | none |
| 133 | Block-level error "…fill all variables…" after a touch | state (error) | `:338-343` | `v$.$dirty && v$.$invalid` |
| 134 | Completeness shared with the mobile app (`isWhatsAppComplete`) | state | `:116-119` | none |
| 135 | Params rebuilt (and validation reset) whenever the template changes | state | `:131-136, 181-188` | none |
| 136 | `actions` slot exposing `sendMessage`/`resetTemplate`/`goBack`/`isValid`/`disabled` — **not used by the campaign form** | state | `:346-353`; no slot passed at `WhatsAppCampaignForm.vue:227-232` | none |

### 2.11 Edit live chat campaign (`EditLiveChatCampaignDialog`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 137 | Centred native `<dialog>` modal with backdrop blur, `max-w-lg`, Esc-closable, click-outside-closable | state | `EditLiveChatCampaignDialog.vue:57-65`; `Dialog.vue:117-177` | opened from the card |
| 138 | Title "Edit live chat campaign" | state | `:60`; `campaign.json:73` | none |
| 139 | The same live chat form, in `edit` mode, without its own buttons | state | `:66-72` | none |
| 140 | Dialog Confirm/Cancel footer supplied by `Dialog` | primary / secondary | `Dialog.vue:148-172` | none |
| 141 | Confirm disabled while updating or while the form is invalid | state | `:26-28, 62` | `isUpdating \|\| isSubmitDisabled` |
| 142 | Confirm shows a spinner while updating | state (loading) | `:61`; `Dialog.vue:167` | `campaigns/getUIFlags.isUpdating` |
| 143 | Success toast + dialog close | status | `:39-40`; `campaign.json:76` | update resolved |
| 144 | Error toast (server message or generic), dialog stays open | status (error) | `:41-46`; `campaign.json:77` | update rejected |
| 145 | `UPDATE_CAMPAIGN` analytics event | state | `store/modules/campaigns.js:83` | update resolved |
| 146 | Dialog content mounted only while open (form re-hydrates each time) | state | `Dialog.vue:146` (`<slot v-if="isOpen">`) | none |

### 2.12 Delete campaign (`ConfirmDeleteCampaignDialog`, all three channels)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 147 | Alert-type dialog, ruby confirm button | destructive | `ConfirmDeleteCampaignDialog.vue:41-48`; `Dialog.vue:164` | opened from a card |
| 148 | Title "Are you sure to delete?" — campaign name **not** shown | destructive | `:44`; `campaign.json:292` | none |
| 149 | Description "The delete action is permanent and cannot be reversed." | state | `:45`; `campaign.json:293` | none |
| 150 | Confirm label "Delete" | destructive | `:46`; `campaign.json:294` | none |
| 151 | Success toast "Campaign deleted successfully" | status | `:26`; `campaign.json:296` | delete resolved |
| 152 | Error toast (generic only, server message ignored) | status (error) | `:27-29`; `campaign.json:297` | delete rejected |
| 153 | `DELETE_CAMPAIGN` analytics event | state | `store/modules/campaigns.js:95` | delete resolved |
| 154 | Dialog closes after the attempt either way | state | `:32-35` | none |

### 2.13 Empty states (three pages)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 155 | `EmptyStateLayout`: `max-w-5xl`, `max-h-[28rem]`, centred, `overflow-hidden` | state (empty) | `EmptyStateLayout.vue:25-30` | none |
| 156 | Wallpaper of 4 fake campaign cards at `opacity-50`, `pointer-events-none` | state (empty) | `EmptyStateLayout.vue:31-36`; `LiveChatCampaignEmptyState.vue:22-35` | `showBackdrop` (default true) |
| 157 | Bottom-up gradient fade from `n-surface-1` over the wallpaper | state (empty) | `EmptyStateLayout.vue:37-42` | `showBackdrop` |
| 158 | Title `text-3xl font-medium`, e.g. "No live chat campaigns are available" | state (empty) | `EmptyStateLayout.vue:50-53`; `campaign.json:19, 86, 140` | none |
| 159 | Subtitle `max-w-xl`, ends with "Click 'Create campaign' to get started." | state (empty) | `EmptyStateLayout.vue:54-59`; `campaign.json:20, 87, 141` | none |
| 160 | `actions` slot behind a `Policy` gate — **no campaign empty state passes one**, so there is no CTA in the empty state | state (empty) | `EmptyStateLayout.vue:61-63`; call sites `LiveChatCampaignEmptyState.vue:20-37` etc. | none |
| 161 | Live chat wallpaper fixtures: 4 ongoing campaigns, 2 enabled / 2 disabled, website inbox "PaperLayer Website" | state (empty) | `CampaignEmptyStateContent.js:1-103` | none |
| 162 | One-off wallpaper fixtures: 4 SMS campaigns, 2 active / 2 completed, inbox "PaperLayer Mobile" with a phone number | state (empty) | `CampaignEmptyStateContent.js:105-212` | none |
| 163 | WhatsApp empty state **reuses the SMS (one-off) fixtures** | state (empty) | `WhatsAppCampaignEmptyState.vue:2, 24` | none |
| 164 | Fixture copy contains Chatwoot brand/URLs ("Chatwoot here", `chatwoot.com/pricings`, `chwt.app/g2-review`) | state (empty) | `CampaignEmptyStateContent.js:15, 21, 45, 65, 70, 117` | none |

### 2.14 Analytics page shell and header (`WhatsAppCampaignAnalyticsPage` + `CampaignAnalyticsLayout`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 165 | Breadcrumb "Campaigns › WhatsApp › {campaign title}" | navigation | `WhatsAppCampaignAnalyticsPage.vue:86-90`; `campaign.json:228-231` | none |
| 166 | Both non-final crumbs are buttons and both navigate to the WhatsApp list | navigation | `:324-326`, `:384-386`; `Breadcrumb.vue:42-48` | none |
| 167 | Last crumb is plain text, truncated | state | `Breadcrumb.vue:51-62` | none |
| 168 | Title falls back to `#<id>` when the campaign is not in the store | state | `:67-69` | campaign missing |
| 169 | Amber processing banner with a spinning `i-lucide-loader-circle` | status | `:388-398`; `Banner.vue:56-66` | `campaign_status === 'processing'` |
| 170 | Banner text, 7 hand-written variants (queued only / awaiting only / both, with singular forms, plus default and "completing") | status | `:94-143`; `campaign.json:215-224` | depends on `status_counts` |
| 171 | Inbox strip: channel icon + inbox name + divider + "Sent on {LLL d, h:mm a}" | state | `:400-418`; `campaign.json:226` | `campaign?.inbox` present |
| 172 | Scrolling `max-w-5xl` main with `gap-6 pb-8` | state | `CampaignAnalyticsLayout.vue:26-29`, `:387` | none |
| — | *Absent:* no edit, no delete, no duplicate, no manual refresh, no export, no link back to the campaign's own settings from this page | — | — | — |

### 2.15 Analytics metrics

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 173 | 6 metric tiles in a `gap-px` grid (1 / 2 / 3 columns), hairline dividers via background | state | `:456-469` | `showAnalytics` |
| 174 | Metric "Audience" (no rate) | status | `:188-200`; `campaign.json:236-239` | none |
| 175 | Metric "Submitted to WhatsApp" | status | `campaign.json:240-243` | none |
| 176 | Metric "Delivered" | status | `campaign.json:244-247` | none |
| 177 | Metric "Read" | status | `campaign.json:248-251` | none |
| 178 | Metric "Failed" | status | `campaign.json:252-255` | none |
| 179 | Metric "Skipped" | status | `campaign.json:256-259` | none |
| 180 | Per-metric "{n}% of audience" rate, rounded | status | `:180-186, 197`; `campaign.json:225` | `audience > 0` and key ≠ audience |
| 181 | Per-metric hint tooltip on an `i-lucide-info` that appears only on card hover | contextual | `CampaignMetricCard.vue:28-35` | `hint` present |
| 182 | Value typography: `text-3xl font-semibold tabular-nums` | state | `CampaignMetricCard.vue:40-45` | none |
| 183 | Metric skeleton (two pulsing blocks) | state (loading) | `CampaignMetricCard.vue:36-39` | `loading` — **unreachable**, see 3.13.2 |

### 2.16 Analytics delivery breakdown (`CampaignDeliveryBreakdown`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 184 | Card "Delivery breakdown" + "{n}% delivered" on the right | state | `CampaignDeliveryBreakdown.vue:88-102`; `campaign.json:269-271` | `showAnalytics` |
| 185 | `PercentageChart` stacked bar, `bar-height 8`, `bar-radius 999`, legend and tooltip **off** | state | `:107-116` | `audience > 0` |
| 186 | Segment "Read" (iris) | status | `:34-39`; `campaign.json:273` | none |
| 187 | Segment "Delivered" = delivered − read, floored at 0 (teal) | status | `:25, 40-45`; `campaign.json:274` | none |
| 188 | Segment "Failed" (ruby) | status | `:46-51`; `campaign.json:275` | none |
| 189 | Segment "Skipped" (amber) | status | `:52-57`; `campaign.json:276` | none |
| 190 | Segment "Queued or awaiting update" = audience − everything else, floored at 0 (slate) | status | `:28-31, 58-63`; `campaign.json:277` | none |
| 191 | Custom legend: coloured dot + label + `tabular-nums` value, 2 / 3 / 5 columns | state | `:118-132` | none |
| 192 | Loading placeholder: pulsing `h-2` bar | state (loading) | `:103-106` | `loading` — **unreachable**, see 3.13.2 |
| 193 | Zero-audience placeholder: flat `bg-n-alpha-2` bar | state (empty) | `:117` | `audience === 0` |

### 2.17 Analytics deliveries table, filters and pagination

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 194 | Card "Deliveries" with `text-heading-2` title | state | `CampaignDeliveryTable.vue:65-70`; `campaign.json:281` | `showAnalytics` |
| 195 | Status tab bar in the card header, horizontally scrollable with hidden scrollbar | filter | `:71-73`, `WhatsAppCampaignAnalyticsPage.vue:483-489` | none |
| 196 | Tab "All" (count = audience) | tab | `:202-215`; `campaign.json:233` | none |
| 197 | Tabs "Awaiting delivery update" (`sent`), "Delivered", "Read", "Failed", "Skipped" with counts from `status_counts` | tab | `:29-36, 202-215`; `campaign.json:261-268` | none |
| 198 | A tab whose count is 0 shows no count at all | tab | `TabBar.vue:93` | `count` falsy |
| 199 | Changing a tab resets to page 1 and refetches | filter | `:313-318, 355-365` | tab changed |
| 200 | Active tab tracked by index with a sliding indicator | state | `:217`, `TabBar.vue:33-49, 75-79` | none |
| 201 | 4 columns: Contact, Status, Message, Reason (`capitalize`d by `BaseTable`) | table | `:32-37`; `BaseTable.vue:95-130`; `campaign.json:282-286` | none |
| 202 | Contact cell: name as a link to `contacts_edit`, opening in a **new tab**, with an `i-lucide-arrow-up-right` glyph | contextual | `:100-114, 52-58` | always |
| 203 | Contact cell second line: phone number, `tabular-nums`, `-` when absent | state | `:115-119` | none |
| 204 | Link `title` reuses `CONTACTS_LAYOUT.CARD.VIEW_DETAILS` from the Contacts module | state | `:105` | none |
| 205 | Status cell: one of 6 coloured badges, unknown status rendered raw | status | `:122-124`; `DeliveryStatusBadge.vue:14-39` | none |
| 206 | Message cell: `line-clamp-2`, `whitespace-pre-line`, width-capped (`max-w-48 lg:max-w-md`) | table | `:125-136` | none |
| 207 | Message fallback "Not generated", italic + dimmer | state (empty) | `:48-50, 128-132`; `campaign.json:285` | no `message_content` |
| 208 | Reason cell: `error_message` → `error_title` → `error_code`, `line-clamp-2` | state (error) | `:39-41, 137-145` | any present |
| 209 | Reason cell second line "Code {code}", suppressed when identical to the reason | state (error) | `:42-46, 145-154`; `campaign.json:287` | distinct code |
| 210 | Reason cell `-` when there is nothing to report | state | `:156` | none |
| 211 | Row hover highlight | state | `BaseTableRow.vue:22-29` | `hoverable` default |
| 212 | Rows keyed by contact id | state | `:95` | none |
| 213 | Table body horizontally scrollable, first/last cells padded to `5` | table | `:81-85` | none |
| 214 | Table loading state: centred spinner, `py-20`, top border | state (loading) | `:75-80` | `state.isFetchingDeliveries` |
| 215 | In-table no-data row with `colspan` and 80px padding | state (empty) | `BaseTable.vue:152-159` | no rows + message |
| 216 | No-data copy "No delivery records found." | state (empty) | `:221-233`; `campaign.json:198` | tab = All |
| 217 | No-data copy "No {status} delivery records found." (status lower-cased) | state (empty) | `:228-232`; `campaign.json:199` | a status tab |
| 218 | No-data copy "Delivery records couldn't be loaded. Refresh the page to try again." | state (error) | `:222-224`; `campaign.json:200` | `deliveriesError` |
| 219 | Pagination footer with first/prev/next/last buttons and a page pill | state | `:490-499`; `PaginationFooter.vue:72-129` | `total_count > 25` |
| 220 | Page info "Showing {a} - {b} of {n} contacts" (pluralised) | status | `:495`; `campaign.json:227` | same |
| 221 | Footer restyled by the page (`!bg-transparent !px-5 rounded-b-xl before:hidden`) | state | `:496` | same |
| 222 | Page size fixed at 25, not user-changeable | state | `:26` (`DELIVERIES_PER_PAGE`) | none |
| — | *Absent:* no sorting (the `sortableColumns` capability of `BaseTable` is unused), no row selection, no bulk action, no per-row retry/resend, no CSV export, no sticky header | — | `BaseTable.vue:22-46` | — |

### 2.18 Analytics data lifecycle, loading and error states

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 223 | Metrics request `GET campaigns/:id/analytics/metrics` | state | `api/campaigns.js:10-12`, `:244` | none |
| 224 | Deliveries request `GET campaigns/:id/analytics/contacts?status&page` | state | `api/campaigns.js:19-23`, `:272-275` | `status='all'` sends no status |
| 225 | Stale-response guard: both fetchers compare a request id and the current campaign id | state | `:239-258, 261-292` | none |
| 226 | Full page loading state: bordered box, `min-h-64`, spinning icon, `role=status aria-live=polite`, `sr-only` "Loading analytics..." | state (loading) | `:420-433`; `campaign.json:197` | `isFetchingMetrics` |
| 227 | Empty/error panel: round icon tile + title + description, `min-h-64`, centred | state | `:435-454` | `analyticsEmptyState` |
| 228 | Error variant: `i-lucide-triangle-alert`, "Analytics couldn't be loaded" | state (error) | `:147-155`; `campaign.json:202-205` | `metricsError` and audience 0 |
| 229 | Pending variant: `i-lucide-clock-3`, "Delivery data will appear once sending begins" | state (empty) | `:157-165`; `campaign.json:206-209` | campaign processing |
| 230 | Unavailable variant: `i-lucide-chart-no-axes-column`, "Analytics aren't available for this campaign" | state (empty) | `:167-173`; `campaign.json:210-213` | neither of the above |
| 231 | Metrics/breakdown/table shown only when metrics loaded **and** audience > 0 | state | `:144-178` | `showAnalytics` |
| 232 | 5s polling of metrics + deliveries + the campaigns list while the campaign is processing | state | `:27, 294-311` | `isCampaignProcessing` |
| 233 | Polling silent (no spinners) — `showLoading: false` | state | `:304-307` | none |
| 234 | Polling stops on deactivate and before unmount; restarts on activate | state | `:369-379` | none |
| 235 | Polling re-evaluated when the processing flag flips | state | `:367` | none |
| 236 | Switching campaign id wipes metrics/deliveries/errors, resets the filter to All and page 1 | state | `:328-353` | id change |
| 237 | A filter reset caused by a campaign switch does not fire a second fetch (`skipNextFilterRefresh`) | state | `:59, 345, 355-365` | none |

### 2.19 Gating summary

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 238 | Whole surface requires the `campaigns` feature flag | state | `campaigns.routes.js:11` | account feature |
| 239 | Whole surface requires the `administrator` permission (no agent/custom-role access at all) | state | `campaigns.routes.js:12`; `helper/routeHelpers.js:15-18` | account role |
| 240 | WhatsApp list + analytics additionally require the `whatsapp_campaign` flag | state | `campaigns.routes.js:58-71` | account feature |
| 241 | The analytics **button** additionally requires an enterprise build, so on a community build with the flag on the analytics page is reachable only by typing the URL | state | `CampaignList.vue:19, 39-43`; `composables/useConfig.js:30` | `isEnterprise` |
| 242 | Sidebar children hidden (not disabled) when their gate fails | navigation | `components-next/sidebar/provider.js:141-147` | none |
| 243 | Command-palette entry hidden when gates fail or the account is paywalled | shortcut | `useGoToCommandHotKeys.js` (`isAvailable`) | none |

### 2.20 Keyboard affordances that exist today

There are **no surface-specific keyboard shortcuts**. Everything keyboard-operable here is inherited from
shared components:

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 244 | Esc closes the edit and delete dialogs | shortcut | `Dialog.vue:101, 127` (native `<dialog>` cancel) | dialog open |
| 245 | Click-outside closes the edit and delete dialogs, but only when topmost | shortcut | `Dialog.vue:103-108, 129` | dialog open |
| 246 | Enter submits the create forms (native `<form submit>`) | shortcut | `LiveChatCampaignForm.vue:208`, `SMSCampaignForm.vue:114`, `WhatsAppCampaignForm.vue:185` | form focused |
| 247 | Enter/Space on the dialog footer's submit button confirms an edit or a delete | shortcut | `Dialog.vue:133, 162-170` | dialog open |
| — | *Absent:* the create popovers have **no** Esc handler and no focus trap (`CampaignLayout.vue:32-37`) | — | — | — |

**Feature count: 247 rows** (excluding the "*Absent*" notes, which are recorded so that a redesign is not
credited with removing something that was never there).

### 2.21 Mobile and RTL affordances that exist today

There are **no mobile-specific affordances** on this surface. The only responsive rules in the whole
campaigns tree are four: the metrics grid (`WhatsAppCampaignAnalyticsPage.vue:458`), the breakdown legend
(`CampaignDeliveryBreakdown.vue:118`), the deliveries card header (`CampaignDeliveryTable.vue:66`) and two
message/reason width caps (`CampaignDeliveryTable.vue:127, 140`). The list pages, the cards and all three
create popovers contain no breakpoint at all.

RTL-aware styling that exists: popover side (`ltr:right-0 rtl:left-0`, `LiveChatCampaignDialog.vue:43`,
`SMSCampaignDialog.vue:42`, `WhatsAppCampaignDialog.vue:45`), logical table padding
(`CampaignDeliveryTable.vue:83` `ps-5`/`pe-5`), `text-start` on the banner (`:389`), and the shared
table's `ltr:pr-4 rtl:pl-4` (`BaseTableCell.vue:13`).

---

## 3. Visual audit

### 3.1 Hierarchy

**3.1.1 The campaign title and its status pill are glued together inside a `w-fit` box, so the title
cannot use the card's width.** `CampaignCard.vue:102` wraps both in
`flex justify-between gap-3 w-fit`; the title is `line-clamp-1` (`:105`) and the pill is a sibling. The
row-card is as wide as `max-w-5xl`, but the title's clamp is computed inside a shrink-to-fit box, so the
primary identifier of a card truncates while a large amount of horizontal space to its right stays empty.
Severity: high.

**3.1.2 All three status values for a one-off campaign are the same colour except "Completed".**
`isActive` is `status !== 'completed'` (`CampaignCard.vue:61`), and `statusTextColor` maps that to
`text-n-teal-11` (`:64-67`). So "Scheduled" (nothing sent yet) and "Processing" (sending right now) are
visually identical, while "Completed" is `text-n-slate-12` — the *same colour as the card title*. The
only state that is genuinely finished is also the only one that reads as emphasised text rather than as a
status. Severity: medium.

**3.1.3 The status pill's background never changes.** Every state uses `bg-n-alpha-2` (`:109`) and varies
only the text colour. Scanning a list of 30 campaigns for the failed/completed ones means reading text,
not spotting shape or colour. Severity: medium.

**3.1.4 The empty state's heading is `text-3xl`, larger than the page's own `text-heading-1` title.**
`EmptyStateLayout.vue:51` vs `CampaignLayout.vue:28`. On a first visit the largest text on the page is
the sentence explaining that there is nothing on the page. Severity: low.

**3.1.5 The analytics page has three card-level headings at three different scales.** "Delivery
breakdown" is `text-sm font-medium` (`CampaignDeliveryBreakdown.vue:92`), "Deliveries" is
`text-heading-2` (`CampaignDeliveryTable.vue:68`), and the metric labels are `text-sm font-medium
text-n-slate-11` (`CampaignMetricCard.vue:29`) — the same recipe as the breakdown's card title but in a
dimmer colour. Three peers, three treatments. Severity: medium.

**3.1.6 The metric value hierarchy inverts inside the tile.** The number is `text-3xl font-semibold`
(`CampaignMetricCard.vue:42`) and the share of audience is `text-sm` in slate-11 (`:48`), yet for
"Delivered"/"Read"/"Failed" the percentage is the number people compare across campaigns. Severity: low.

### 3.2 Density

**3.2.1 The card reserves three fixed-height rows regardless of content.** Title row, message row with
`h-6` (`CampaignCard.vue:117`), details row with `h-6` (`:119`), inside `py-5` (`CardLayout.vue:25`).
Every card is ~116px tall, so eight campaigns fill a laptop viewport. With no search and no filter
(§2.2), the only way to find a campaign in a long list is to scroll. Severity: medium.

**3.2.2 The action column is a magic `w-20` that exactly fits two `size=sm` icon buttons.**
`CampaignCard.vue:134` is `flex items-center justify-end w-20 gap-2`. Today no card has three actions
(analytics is WhatsApp-only, edit is live-chat-only), so the number holds by coincidence. Any third
action overflows a fixed width. Severity: low (as a fragility, not a current defect).

**3.2.3 The create popover packs 7–9 controls into a 400px column with a flat `gap-4`.** Live chat:
title, rich editor, inbox, sender, URL, number, two checkboxes, two buttons
(`LiveChatCampaignForm.vue:208-321`). There is no grouping beyond one `fieldset` at the bottom, and the
popover is `max-h-[85vh] overflow-y-auto` (`LiveChatCampaignDialog.vue:43`) — on a 800px-tall screen the
form scrolls inside a floating panel while the page behind it also scrolls. Severity: high.

**3.2.4 Six status tabs with counts sit inside the deliveries card header.** `TabBar` is `w-fit`
(`TabBar.vue:73`) with `px-4` per tab; six labels including "Awaiting delivery update" easily exceed the
card width, which is why the header wraps the slot in `overflow-x-auto no-scrollbar`
(`CampaignDeliveryTable.vue:71`). The filter is therefore a hidden horizontal scroll area. Severity: high.

### 3.3 Alignment

**3.3.1 The card's meta row and the action column are vertically centred against a left column that is
`justify-between`.** `CampaignCard.vue:101` is `flex-col items-start justify-between`, the action column
is `items-center` (`:134`). With the fixed heights of 3.2.1 this currently lines up, but the two columns
are aligned by two different rules. Severity: low.

**3.3.2 The metrics grid relies on `gap-px` over a background to fake dividers, so the last row of a
3-column grid holding 6 items has no bottom hairline and no filler cells.**
`WhatsAppCampaignAnalyticsPage.vue:458` (`grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-px bg-n-weak`).
At the `sm` breakpoint this is 3 rows of 2; at `lg`, 2 rows of 3; at `xs`, 6 stacked tiles each with a
hairline above. The divider pattern changes meaning at every breakpoint. Severity: low.

**3.3.3 The inbox strip mixes a 3.5 icon, 12px divider and nowrap text with `flex-wrap`.**
`WhatsAppCampaignAnalyticsPage.vue:400-418`: when it wraps, the `w-px h-3` divider (`:410`) can end up at
the start of the second line. Severity: low.

### 3.4 Spacing

**3.4.1 `pt-14` is applied to the empty state from outside the component, three times.**
`LiveChatCampaignsPage.vue:76`, `SMSCampaignsPage.vue:65`, `WhatsAppCampaignsPage.vue:113`. The layout
already centres itself and adds `pb-20` internally (`EmptyStateLayout.vue:38`), so the final vertical
position is the sum of three unrelated decisions. Severity: low.

**3.4.2 The WhatsApp popover moves its padding inside while the other two keep it on the panel.**
`WhatsAppCampaignDialog.vue:45-47` has `rounded-xl` on the panel and `p-6 flex flex-col gap-6` on an inner
div; the SMS and live chat panels put `p-6 … gap-6` on the panel itself
(`SMSCampaignDialog.vue:42`, `LiveChatCampaignDialog.vue:43`). Same visual result, two structures.
Severity: low.

**3.4.3 Three different gaps describe the same "stack of form fields".** `gap-4` between form fields
(`LiveChatCampaignForm.vue:208`), `gap-3` inside the recipients fieldset
(`CampaignRecipients.vue:84`), `gap-1` between a label and its control (`:88`), plus a `mb-1` on the
legend (`:85`) and `mb-0.5` on field labels (`LiveChatCampaignForm.vue:226`). Severity: low.

**3.4.4 The sticky header is a no-op.** `CampaignLayout.vue:25` declares `sticky top-0 z-10` on a
`<header>` that is a flex sibling of the scroll container `<main>` (`:51`), so it never scrolls and never
needed to be sticky — and it has no background, which would have shown content through it if it ever did
stick. Same in `CampaignAnalyticsLayout.vue:16`. Dead styling that a redesign will otherwise faithfully
reproduce. Severity: low.

### 3.5 Inconsistent controls

**3.5.1 Creating and editing use two different interaction models.** Create is an unlabelled `div`
popover anchored under the button (`LiveChatCampaignDialog.vue:42-53`); edit is a centred native
`<dialog>` with a backdrop (`EditLiveChatCampaignDialog.vue:57-73`, `Dialog.vue:117-177`). The same form
component renders in both (`LiveChatCampaignForm.vue`), with its own buttons in one case and the dialog's
footer in the other (`:300-303`, `Dialog.vue:148-172`). Severity: high.

**3.5.2 The three create popovers disagree about overflow.** `max-h-[85vh] overflow-y-auto` (live chat),
`max-h-[80vh] overflow-y-auto` (WhatsApp), **nothing** (SMS) — `LiveChatCampaignDialog.vue:43`,
`WhatsAppCampaignDialog.vue:45`, `SMSCampaignDialog.vue:42`. The SMS form is the one that grows (the
recipients block adds two pickers and a count line), so the one panel without a scroll ceiling is the one
most likely to need it. Severity: high.

**3.5.3 Two different message inputs for two channels, with two different cap behaviours.** Live chat uses
the rich `Editor` whose `N / 200` counter is advisory — nothing enforces it and no validator checks length
(`Editor.vue:120-131`, rules at `LiveChatCampaignForm.vue:70-77`). SMS uses `TextArea` with
`show-character-count`, which sets a real `maxlength=200` that silently stops typing
(`SMSCampaignForm.vue:123-130`, `TextArea.vue:171`). Same number, two meanings, no explanation of either.
Severity: high.

**3.5.4 Checkboxes are raw `<input type="checkbox">` while every other control on the surface is a design
system component.** `LiveChatCampaignForm.vue:282, 289`. There is a `components-next/switch/Switch.vue`
used by comparable settings surfaces. Severity: medium.

**3.5.5 The inbox/sender/template comboboxes each carry a 1-line arbitrary class override to repair their
own appearance.** The identical string
`[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6`
appears 5 times: `LiveChatCampaignForm.vue:236, 251`, `SMSCampaignForm.vue:143`,
`WhatsAppCampaignForm.vue:205, 220`; the recipients pickers use a shortened variant
(`CampaignRecipients.vue:97, 111`). Severity: medium.

**3.5.6 Field labels are written three ways.** `Input`/`TextArea`/`Editor` take a `label` prop
(`LiveChatCampaignForm.vue:211`); comboboxes get a hand-written `<label for>` + wrapper div
(`:226-228`); the recipients pickers get a `<span class="text-label-small">` with no `for` at all
(`CampaignRecipients.vue:89-91, 102-104`). Three label recipes in one 400px form. Severity: medium.

**3.5.7 The analytics button carries three overlapping labels.** `v-tooltip.top`, `aria-label` and
`title` all set to `CAMPAIGN.WHATSAPP.CARD.ANALYTICS` (`CampaignCard.vue:137-143`), which produces both a
custom tooltip and the browser's native one. The neighbouring edit and delete buttons have `aria-label`
only, and therefore no visible tooltip at all (`:152, 160`). Severity: medium.

**3.5.8 "Create campaign" is the same label on all three pages.** `campaign.json:5, 84, 138` are three
separate keys with identical copy; nothing in the button says which channel it creates
(`CampaignLayout.vue:39-45`). Since the three pages are reached from a sidebar group whose children are
"Live chat / SMS / WhatsApp", the page title is the only channel cue. Severity: low.

### 3.6 Duplicated and competing patterns

**3.6.1 Three near-identical dialog components.** `LiveChatCampaignDialog.vue`, `SMSCampaignDialog.vue`
and `WhatsAppCampaignDialog.vue` differ only in the form they host, the i18n prefix, the tracked campaign
type and the overflow rules — `addCampaign`, the toast handling and the panel markup are copy-pasted three
times (compare `LiveChatCampaignDialog.vue:15-38` with `SMSCampaignDialog.vue:15-37` and
`WhatsAppCampaignDialog.vue:19-40`). Severity: medium.

**3.6.2 Three near-identical empty-state components.** `LiveChatCampaignEmptyState.vue`,
`SMSCampaignEmptyState.vue` and `WhatsAppCampaignEmptyState.vue` are the same 37 lines with one import
changed — and the WhatsApp one does not even change it (3.10.2). Severity: low.

**3.6.3 Three near-identical list pages.** `LiveChatCampaignsPage.vue`, `SMSCampaignsPage.vue`,
`WhatsAppCampaignsPage.vue` repeat the same uiFlags/toggle/getter/`hasNo…`/delete-ref/loading-empty-list
skeleton. Severity: low.

**3.6.4 Four different loading vocabularies inside the analytics page alone.** `Spinner` svg in the
deliveries card (`CampaignDeliveryTable.vue:75-80`), a spinning `Icon` in the page-level box
(`WhatsAppCampaignAnalyticsPage.vue:420-433`), pulsing skeleton blocks in the metric tile
(`CampaignMetricCard.vue:36-39`) and a pulsing bar in the breakdown
(`CampaignDeliveryBreakdown.vue:103-106`) — while `BaseTable` already ships skeleton rows that are never
used here (`BaseTable.vue:134-148`). Severity: medium.

**3.6.5 The deliveries table re-implements a capability of its own table component.**
`CampaignDeliveryTable.vue:83` wraps `BaseTable` in `overflow-x-auto`; `BaseTable` has a `scrollable`
prop that does exactly this (`BaseTable.vue:51-54, 87`). Severity: low.

**3.6.6 The processing banner hand-writes seven message variants where the surface elsewhere uses i18n
pluralisation.** `WhatsAppCampaignAnalyticsPage.vue:94-143` with `campaign.json:215-224` has
`BOTH`, `BOTH_SINGLE`, `BOTH_QUEUED_SINGLE`, `BOTH_AWAITING_SINGLE`, `QUEUED`, `AWAITING_UPDATE`,
`COMPLETING` + `DEFAULT`; two lines away, `PAGE_INFO` and the recipients count use the `|` plural form
(`campaign.json:227, 314`). Severity: medium.

**3.6.7 Two names for one state on the same screen.** The metric tile for `sent` is labelled "Submitted
to WhatsApp" (`campaign.json:241`) while the tab and badge for the same key read "Awaiting delivery
update" (`campaign.json:263`, used at `WhatsAppCampaignAnalyticsPage.vue:206-209` and
`DeliveryStatusBadge.vue:28-29`). A user comparing the "Submitted to WhatsApp = 40" tile with the tabs
finds no tab of that name. Severity: medium.

### 3.7 CTA clarity

**3.7.1 The empty state tells the user to click a button instead of offering one.** All three subtitles
end with "Click 'Create campaign' to get started" (`campaign.json:20, 87, 141`) while
`EmptyStateLayout` has an `actions` slot, already permission-wrapped, that none of the three campaign
empty states fills (`EmptyStateLayout.vue:61-63`; `LiveChatCampaignEmptyState.vue:20-37`,
`SMSCampaignEmptyState.vue:20-37`, `WhatsAppCampaignEmptyState.vue:20-37`). The real button is 400px away
in the header, at `size=sm`, while the empty state's own copy is `text-3xl`. Severity: high.

**3.7.2 The destructive confirmation never names what it will delete.** Title "Are you sure to delete?",
description "The delete action is permanent and cannot be reversed."
(`ConfirmDeleteCampaignDialog.vue:44-45`, `campaign.json:292-293`) — no campaign title, no channel, no
mention that a *scheduled* campaign will therefore never send. The dialog is opened from a card whose
identity is then hidden behind a backdrop. Severity: high.

**3.7.3 Clicking anywhere outside the create popover discards a half-filled form with no warning.**
`CampaignLayout.vue:32-37` closes on click-outside and the page then `v-if`-destroys the dialog
(`LiveChatCampaignsPage.vue:53-56`), taking all typed state with it; the only guard in the handler is for
the editor's own link prompt (`:34-35`). The live chat form at that point can hold a title, a rich
message, an inbox, a sender, a URL and a time. Severity: high.

**3.7.4 Both submit buttons are disabled on open and give no reason.** `isSubmitDisabled` is
`v$.$invalid` (`LiveChatCampaignForm.vue:82`, `SMSCampaignForm.vue:81`,
`WhatsAppCampaignForm.vue:122-124`), which is true for an untouched form, so "Create" is greyed out from
the first paint with no hint of what is missing until a field is touched. In the WhatsApp form the extra
`hasRequiredTemplateParams` term means the button also stays disabled while the user is filling template
variables, with the explanation living in a separate error block inside the parser
(`WhatsAppTemplateParser.vue:338-343`) that only appears after a `$touch` the campaign form never
triggers. Severity: high.

**3.7.5 Cancel and Create are the same size, side by side, at equal width.** `w-full` on both inside
`justify-between` (`LiveChatCampaignForm.vue:302-320`, `SMSCampaignForm.vue:163-179`,
`WhatsAppCampaignForm.vue:250-266`), with Cancel additionally tinted `text-n-blue-11` — the brand colour
otherwise reserved for the primary action. Severity: medium.

**3.7.6 The analytics page's primary affordance is a filter.** Nothing on that page acts on the campaign:
no retry of failed deliveries, no resend, no edit, no delete, no export, not even a refresh
(`WhatsAppCampaignAnalyticsPage.vue:382-502`). The only interactive controls are the breadcrumb, the six
tabs and the pager. Severity: medium (a gap, recorded so the redesign does not "discover" it as a loss).

### 3.8 Overcrowded areas

**3.8.1 The card's meta row is a single-line flex that hides its own overflow.**
`CampaignCard.vue:119` is `flex items-center w-full h-6 gap-2 overflow-hidden`; inside it every live chat
segment is `flex-shrink-0` (`LiveChatCampaignDetails.vue:33, 36, 47, 50`). With a long sender name and a
long inbox name, the inbox simply disappears past the edge rather than truncating. The SMS variant at
least gives the date `flex-1 truncate` (`SMSCampaignDetails.vue:38`). Severity: medium.

**3.8.2 The 400px popover hosts the full WhatsApp flow.** Title, inbox, template picker + hint, a
template preview card, up to three groups of variable inputs, two recipient pickers with chips, a count
line, a datetime field and two buttons — `WhatsAppCampaignForm.vue:185-266` plus
`WhatsAppTemplateParser.vue:208-353`. A template with a media header and three body variables adds five
more inputs inside the same 400px column. Severity: high.

**3.8.3 The deliveries row can carry four truncated blocks at once.** Contact name (`truncate`) + phone
(`truncate`) + message (`line-clamp-2`, capped at `max-w-48`) + reason (`line-clamp-2`, capped at
`max-w-40`) — `CampaignDeliveryTable.vue:107-119, 126-135, 139-145`. Below `lg` the two caps are 12rem and
10rem, so an error message is cut at roughly five words with no way to read the rest (no tooltip, no
expand, no detail view). Severity: high.

### 3.9 Table usability (deliveries table)

**3.9.1 No sorting, although the table component supports it.** `CampaignDeliveryTable.vue:86-90` passes
`headers`/`items`/`noDataMessage` only; `BaseTable` implements `sortableColumns`, `aria-sort` and a sort
button (`BaseTable.vue:22-36, 69-83, 107-126`). A campaign with 2000 recipients cannot be ordered by
status or by failure. Severity: medium.

**3.9.2 The only way to narrow 2000 rows is the six status tabs.** No contact search, no phone lookup, no
error-code filter, no date filter (`WhatsAppCampaignAnalyticsPage.vue:483-489`). To find out whether one
customer received the message you page through 25 at a time. Severity: high.

**3.9.3 The header row does not stick.** `stickyHeader` defaults to false and is not passed
(`BaseTable.vue:37-41, 92`), so after one screen of scrolling the four columns are unlabelled. Severity:
medium.

**3.9.4 Row density is set by the cell component, not by the data.** `BaseTableCell` is `py-3`
(`BaseTableCell.vue:13`) while the contact cell adds its own `py-1` wrapper
(`CampaignDeliveryTable.vue:99`), so the contact column is 8px taller than its neighbours' content box
and sets the row height. Severity: low.

**3.9.5 Every contact link opens a new browser tab.** `target="_blank" rel="noopener noreferrer"`
(`CampaignDeliveryTable.vue:101-103`). Checking five failed contacts leaves five tabs; the rest of the
dashboard navigates in place. Severity: medium.

**3.9.6 Page size is fixed at 25 and the pager is hidden below that threshold.**
`WhatsAppCampaignAnalyticsPage.vue:26, 490`. With exactly 25 rows there is no footer at all, so the total
count disappears — the only place the surface states "of {n} contacts" is that same footer
(`campaign.json:227`). Severity: medium.

**3.9.7 The footer is restyled with four `!important` overrides to sit inside the card.**
`!bg-transparent !px-5 rounded-b-xl before:hidden` (`:496`) fights `PaginationFooter`'s own
`bg-n-surface-1 px-6` and gradient pseudo-element (`PaginationFooter.vue:74`). Severity: low.

**3.9.8 Headers are force-`capitalize`d.** `BaseTable.vue:98`. Harmless for "Contact"/"Status" but it is
a transform applied to translated strings. Severity: low.

### 3.10 Empty-state quality

**3.10.1 The empty state is wallpapered with four fake campaigns at 50% opacity.**
`EmptyStateLayout.vue:31-36` renders the fixtures behind a gradient. They are real `CampaignCard`s with
real status pills and plausible titles ("Customer Feedback Request", "Welcome New Customer"), dimmed and
`pointer-events-none`. A first-time administrator sees what reads as a half-loaded list of campaigns they
did not create. Severity: medium.

**3.10.2 The WhatsApp empty state shows SMS campaigns.** `WhatsAppCampaignEmptyState.vue:2` imports
`ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT`, whose four fixtures all carry
`inbox.channel_type: 'Channel::Sms'`, the inbox name "PaperLayer Mobile" and a phone number
(`CampaignEmptyStateContent.js:108-115`). `CampaignCard` resolves the channel icon from that field
(`CampaignCard.vue:89-96`), so the WhatsApp page's empty state displays four SMS-iconed campaigns.
Severity: high.

**3.10.3 The fixtures carry Chatwoot branding into a white-labelled product.** "Hi! Chatwoot here. Need
help setting up?" (`CampaignEmptyStateContent.js:65`), sender name "Chatwoot" (`:63`),
`https://www.chatwoot.com/features/chatbot/` (`:20`), `https://www.chatwoot.com/pricings` (`:45`),
`https://{*.}?chatwoot.com/apps/account/*/settings/inboxes/new/` (`:70`) and
`https://chwt.app/g2-review` (`:117`). The repo's own guidance is to route such strings through
`replaceInstallationName` (`CLAUDE.md`, "Branding / White-labeling note"). Severity: high.

**3.10.4 The empty state is capped at `max-h-[28rem]` and anchored `justify-end … pb-20` inside it.**
`EmptyStateLayout.vue:29, 38`. Combined with the external `pt-14` (3.4.1) the copy lands at a fixed
offset that ignores the real viewport height; on a tall screen it sits in the upper third with empty space
below. Severity: low.

**3.10.5 The subtitle is a wall of one-size text.** `max-w-xl text-base text-center … tracking-[0.3px]`
(`EmptyStateLayout.vue:54-58`) for sentences as long as "Launch an SMS campaign to reach your customers
directly. Send offers or make announcements with ease. Click 'Create campaign' to get started."
(`campaign.json:87`). Severity: low.

**3.10.6 There is no "no results" state, because there is no search.** The only empty state on the list
pages is the first-run one (`LiveChatCampaignsPage.vue:31-33`), so a redesign that adds filtering has no
baseline copy to reuse. Severity: low (recorded as a gap).

### 3.11 Mobile behaviour

**3.11.1 The create popover is wider than a phone and is clipped by its own ancestor.** The panel is
`w-[25rem]` (400px) absolutely positioned `top-10 ltr:right-0` inside the header's button wrapper
(`LiveChatCampaignDialog.vue:43`, `CampaignLayout.vue:31-47`). The available width on a 360px device is
360 − 48 (the layout's `px-6`) = 312px, and the surrounding `<section>` is `overflow-hidden`
(`CampaignLayout.vue:24`). The left ~88px of every create form — which is where the labels are in LTR — is
cut off, and there is no breakpoint anywhere in the three dialogs to prevent it. **Creating a campaign is
effectively impossible on a phone.** Severity: high.

**3.11.2 The SMS popover has no height ceiling, so on a short viewport its buttons are unreachable.**
`SMSCampaignDialog.vue:42` has neither `max-h` nor `overflow-y-auto`, while the panel starts at
`top-10` below a 5rem header. The SMS form is title + textarea + inbox + two recipient pickers + count +
datetime + buttons (`SMSCampaignForm.vue:114-179`). Severity: high.

**3.11.3 The campaign card never reflows.** `CardLayout.vue:26-27` chooses `flex-row justify-between
items-center` purely from the `layout` prop, with no breakpoint; the meta row is a single `overflow-hidden`
line (`CampaignCard.vue:119`) and the action column is a fixed `w-20` (`:134`). On a narrow screen the
title truncates to a few characters and the sender/inbox/date information is silently clipped rather than
stacked. Severity: high.

**3.11.4 The status filter is a hidden horizontal scroller.** `overflow-x-auto no-scrollbar`
(`CampaignDeliveryTable.vue:71`) with a `w-fit` `TabBar` (`TabBar.vue:73`). On a phone, "Failed" and
"Skipped" are off-screen with no visual indication that the strip scrolls. Severity: high.

**3.11.5 The deliveries table scrolls horizontally with no sticky first column.** `overflow-x-auto`
(`CampaignDeliveryTable.vue:83`); `BaseTable` explicitly defers the sticky action column to "the
responsive phase" (`BaseTable.vue:47-54`). Scrolling right to read a failure reason loses the contact's
name. Severity: medium.

**3.11.6 The pagination footer puts six controls plus two text blocks in one `justify-between` row with no
breakpoint.** `PaginationFooter.vue:72-129`, fixed height `h-[3.375rem]`. Severity: medium.

**3.11.7 Metric hints are hover-only.** The `i-lucide-info` is `opacity-0 … group-hover:opacity-100`
(`CampaignMetricCard.vue:30-34`) and the hint is a `v-tooltip`. On a touch device the definitions of
"Submitted to WhatsApp", "Skipped" etc. are unreachable. Severity: high.

### 3.12 RTL behaviour

**3.12.1 The breadcrumb separator is a hard-coded right chevron.** `i-lucide-chevron-right` with
`mx-2` (`Breadcrumb.vue:35-39`). In Arabic the trail reads right-to-left while every separator still
points right. Severity: medium.

**3.12.2 The pager's arrows do not mirror.** `i-lucide-chevrons-left`, `chevron-left`, `chevron-right`,
`chevrons-right` in fixed DOM order (`PaginationFooter.vue:82-127`). In RTL the row visually reverses, so
"first page" ends up on the right while still showing a left-pointing glyph. Severity: medium.

**3.12.3 The tab indicator is positioned with a physical `left`.** `indicatorStyle` is
`{left: offsetLeft, width: offsetWidth}` (`TabBar.vue:37-40`) applied as an inline style (`:78`). It is
computed from live geometry so it lands correctly, but it is a physical property in an inline style, which
a direction-aware redesign cannot simply re-token. Severity: low.

**3.12.4 The contact cell's external-link glyph is a fixed `i-lucide-arrow-up-right`.**
`CampaignDeliveryTable.vue:110-113`. In RTL the "goes outward" metaphor points inward. Severity: low.

**3.12.5 Card internals use physical-neutral utilities but the message preview injects arbitrary HTML.**
`CampaignCard.vue:116` renders `formatMessage(...)` through `v-dompurify-html` with
`[&>p]:mb-0`; any direction handling for user content is inherited, with no `dir="auto"` on the preview,
so a mixed-language campaign message is rendered in the dashboard's direction. Severity: medium.

**3.12.6 Three positive cases worth keeping.** The popovers flip side correctly
(`ltr:right-0 rtl:left-0`, `LiveChatCampaignDialog.vue:43`), the deliveries table uses logical padding
(`ps-5`/`pe-5`, `CampaignDeliveryTable.vue:83`) and the banner forces `text-start` (`:389`).

### 3.13 Loading and error behaviour

**3.13.1 A failed campaigns fetch is indistinguishable from an empty account.** `campaigns/get` catches
and discards (`store/modules/campaigns.js:62-64`, literally `// Ignore error`) and then clears
`isFetching`. The pages compute "empty" as `length === 0 && !isFetching`
(`LiveChatCampaignsPage.vue:31-33`, `SMSCampaignsPage.vue:27-29`, `WhatsAppCampaignsPage.vue:42-44`), so a
500 or an offline device renders the first-run empty state, complete with the fake wallpaper campaigns and
"Click 'Create campaign' to get started". There is no retry, and the fetch happens once on parent mount
(`CampaignsPageRouteView.vue:12`), so the only recovery is a full page reload. Severity: high.

**3.13.2 Two skeleton states on the analytics page can never render.** `CampaignMetricCard`'s skeleton is
gated on `loading` (`CampaignMetricCard.vue:36-39`), and the page passes
`:loading="state.isFetchingMetrics"` (`WhatsAppCampaignAnalyticsPage.vue:467`) — but that whole grid lives
in the `v-else` of `v-if="state.isFetchingMetrics"` (`:420-421, 456-457`), so the prop is always false
there. The same is true of the breakdown's pulsing bar (`CampaignDeliveryBreakdown.vue:103-106`), gated on
`loading` but rendered only when `showAnalytics` is true, which requires `!isFetchingMetrics`
(`:176-178, 471-475`). Dead loading code that a redesign will faithfully port. Severity: medium.

**3.13.3 The list pages' loading state is announced to nobody.** A bare `Spinner` inside a `div` with no
`role`, no `aria-live`, no text (`LiveChatCampaignsPage.vue:59-64`; `Spinner.vue:10-24` has no `aria-*`).
The analytics page does this correctly two files away (`role="status" aria-live="polite"` + `sr-only`,
`WhatsAppCampaignAnalyticsPage.vue:420-433`). Severity: medium.

**3.13.4 Create/update/delete failures are reported only as transient toasts.** `useAlert` in all five
mutation paths (`LiveChatCampaignDialog.vue:29`, `SMSCampaignDialog.vue:29`,
`WhatsAppCampaignDialog.vue:31`, `EditLiveChatCampaignDialog.vue:45`,
`ConfirmDeleteCampaignDialog.vue:28`). The live chat create popover closes *before* the request resolves
(`LiveChatCampaignDialog.vue:35-38`), so a failure arrives as a toast over a page that shows no new
campaign and no form to retry from — all typed content is gone. Severity: high.

**3.13.5 The delete error path drops the server's message.** `ConfirmDeleteCampaignDialog.vue:27-29` uses
a fixed string, where the three create paths prefer `error.response.message`. A campaign that cannot be
deleted for a stated reason reports "There was an error. Please try again." Severity: medium.

**3.13.6 The store's declared ui flags do not match the ones it sets.** `state.uiFlags` declares only
`isFetching` and `isCreating` (`store/modules/campaigns.js:11-14`) while actions set `isUpdating` and
`isDeleting` (`:80, 92`). `EditLiveChatCampaignDialog.vue:24` reads `isUpdating`, which is therefore
`undefined` until the first update begins; nothing reads `isDeleting`, so the delete dialog's confirm
button never shows a spinner and can be clicked twice (`ConfirmDeleteCampaignDialog.vue:41-48` passes
neither `is-loading` nor `disable-confirm-button`). Severity: medium.

**3.13.7 The recipient count can sit in "Counting…" permanently.** `fetchCount` only assigns when the
abortable runner returns a value (`CampaignRecipients.vue:52-54`); a superseded request resolves to
`undefined` (`useAbortableRequest.js:44-45`), leaving `count === null`, which `countNote` renders as
`COUNT.LOADING` (`:72-73`). In the normal path a newer request replaces it, but there is no timeout and no
"unknown" terminal state other than the explicit failure one. Severity: low.

**3.13.8 Polling has no failure budget.** Every 5s while processing, three requests fire
(`WhatsAppCampaignAnalyticsPage.vue:303-310`); a persistently failing endpoint keeps the error empty state
on screen and keeps retrying silently forever, with no backoff and no "last updated" timestamp anywhere on
the page. Severity: medium.

**3.13.9 The surface has one spec.** `routes/dashboard/campaigns/pages/specs/WhatsAppCampaignsPage.spec.js`
covers only the audience prefill; there is no test for the cards, the forms, the recipients count, the
analytics page or any of the states above, and no Playwright journey (`tests/playwright/tests/e2e/ui/`
contains login, onboarding and inbox-creation only). A redesign has almost no automated parity net here;
the four `data-test-id`s in `CampaignRecipients.vue:84, 98, 112, 121` are the only stable hooks.
Severity: medium (process risk, recorded deliberately).

### 3.14 Accessibility

**3.14.1 The create popovers are not dialogs.** A plain `<div>` with `z-50` and a blur
(`LiveChatCampaignDialog.vue:42`, `SMSCampaignDialog.vue:41`, `WhatsAppCampaignDialog.vue:44`): no
`role="dialog"`, no `aria-modal`, no `aria-labelledby` pointing at the `h3` (`:45`), no focus move on
open, no focus trap, no focus restore on close, and **no Esc to close** — only click-outside
(`CampaignLayout.vue:32-37`). A keyboard user who opens "Create campaign" must tab through the whole
form and cannot dismiss it from the keyboard. Severity: high.

**3.14.2 The three card actions are icon-only buttons.** Analytics, edit and delete carry `aria-label`s
(`CampaignCard.vue:138, 152, 160`) so they are announced, but sighted users get no text for edit and
delete (no tooltip — only the analytics button has one, 3.5.7), and an `i-lucide-sliders-vertical` glyph
is a weak signifier for "edit campaign". Severity: medium.

**3.14.3 Error messages are not programmatically tied to their fields.** `Input` renders the message as a
sibling `<p>` with no `id`, and the `<input>` has no `aria-describedby` and no `aria-invalid`
(`Input.vue:117-152`); the same is true of `TextArea.vue:166-204` and `Editor.vue:133-139`. A screen
reader user hears the label and value but not "Title is required". Severity: high.

**3.14.4 Error messages are truncated to one line.** `truncate` on the message paragraph in
`Input.vue:148`, `TextArea.vue:200`, `Editor.vue:135`, and in the recipients note
(`TagMultiSelectComboBox.vue:173`). "Please enter a valid URL" fits; a server-side message would not.
Severity: medium.

**3.14.5 The SMS message textarea has no usable label association.** `TextArea` renders
`<label :for="id">` and `<textarea :id="id">` (`TextArea.vue:143-149, 167`), but `SMSCampaignForm.vue:123-130`
never passes `id`, so both resolve to the empty string and the label points at nothing. Severity: high.

**3.14.6 The recipients pickers have no labels at all.** Their captions are `<span>`s
(`CampaignRecipients.vue:89-91, 102-104`) and the control itself is a `<div>` with a click handler, not a
`<button>` or a `combobox` role (`TagMultiSelectComboBox.vue:125-135`). It is not reachable by Tab, cannot
be opened by Enter or Space, and announces nothing. The chips' remove affordance is a `<span>` with
`cursor-pointer` and no label (`:145-148`). "Recipients" is the one required decision in an SMS or
WhatsApp campaign and it is keyboard-inoperable. Severity: high.

**3.14.7 Combobox options are non-interactive list items.** `ComboBoxDropdown` gives the list
`role="listbox"` and each item `role="option"` + `aria-selected` (`ComboBoxDropdown.vue:91-105`), but the
options are `<li>` with `@click` only — no `tabindex`, no key handling, no `aria-activedescendant`, and the
search input has no `aria-controls`/`aria-expanded`. Choosing an inbox or a template requires a mouse.
This governs 5 of the surface's selects (`LiveChatCampaignForm.vue:229, 244`, `SMSCampaignForm.vue:136`,
`WhatsAppCampaignForm.vue:198, 213`). Severity: high.

**3.14.8 The status tabs are not tabs.** `TabBar` renders bare `<button>`s with no `role="tab"`, no
`aria-selected`, no `tablist` container and no arrow-key navigation (`TabBar.vue:71-105`); the active state
is colour plus a decorative sliding `div` (`:75-79`). The deliveries table they filter has no
`aria-live`, so the result of switching tabs is not announced. Severity: medium.

**3.14.9 Status is conveyed by colour and text that is not associated with the row.** The card pill has no
`role="status"` (`CampaignCard.vue:108-113`) and `DeliveryStatusBadge` is a bare `<span>`
(`DeliveryStatusBadge.vue:34-39`); an unknown status falls through to the raw server string
(`:29`), e.g. a literal `queued_retry`. Severity: low.

**3.14.10 The breakdown chart is a bar with no accessible numbers.** `PercentageChart` gets an
`aria-label` of just the card title and has `show-legend`/`show-tooltip` disabled
(`CampaignDeliveryBreakdown.vue:107-116`); the real values live in a sibling `div` grid with no
association to the chart (`:118-132`). The colour dots are `<span>`s with no text alternative, so the
mapping from colour to segment is visual only. Severity: medium.

**3.14.11 The metric hint is in a `v-tooltip` on a `<span>` with `cursor-help`.**
`CampaignMetricCard.vue:30-34`: not focusable, no `aria-describedby`, invisible until hover. The six
metric definitions — the only explanation of what "Skipped" or "Submitted to WhatsApp" mean
(`campaign.json:236-259`) — are unavailable to keyboard and touch users. Severity: high.

**3.14.12 Native checkboxes are unstyled and get no focus treatment.**
`LiveChatCampaignForm.vue:282, 289` are raw inputs inside a `<label>` (so the hit area is fine) but they
inherit nothing from the design system and show the browser default focus ring, which differs from the
`focus:outline-n-brand` used by every other control on the surface. Severity: low.

**3.14.13 The card's message preview injects user HTML into the a11y tree.**
`v-dompurify-html="formatMessage(message, false, false, false)"` inside a `line-clamp-1 h-6` div
(`CampaignCard.vue:115-118`): sanitised, but a multi-paragraph campaign message is announced in full while
being visually clipped to one line, with no `aria-label` summarising it. Severity: low.

**3.14.14 Breadcrumb buttons lack a current-page marker.** `Breadcrumb.vue:28-62` renders an `ol` with
`nav aria-label`, but the last item is a `<span>` with no `aria-current="page"`. Severity: low.

---

## 4. What this surface already does well and must not be lost

**4.1 The recipient count is the best idea on the surface.** Selecting labels or audiences asks the server
how many distinct contacts that actually selects, debounced at 300ms and cancelled through a shared
abortable-request composable so an older answer can never overwrite a newer one
(`CampaignRecipients.vue:40-57`, `composables/useAbortableRequest.js:25-62`, `api/campaigns.js:15-17`). The
copy is pluralised down to zero ("No contacts match now.", `campaign.json:314`), it explains the two things
a user would otherwise get wrong — each contact is messaged once, and recipients are resolved again at
send time (`campaign.json:315`) — and a failed count says it is **unknown** rather than showing a
misleading 0 (`:51-56`, `campaign.json:316`, with the reasoning recorded in the file header comment
`CampaignRecipients.vue:2-4`). Keep all four behaviours.

**4.2 Shared audiences cross modules without inventing a record.** "Use in a new WhatsApp campaign"
carries only an id in the URL; the campaigns page resolves it against the account's own shared contact
views and prefills the picker, and an id that is not one of them simply opens an empty dialog
(`ContactListHeaderWrapper.vue:255-259`, `WhatsAppCampaignsPage.vue:56-67`,
`helper/audienceHelper.js:1-39`). The query is intentionally left in the URL so the link stays shareable
and a reload reopens the same dialog, and the handler is `onActivated` precisely because the page is kept
alive — both decisions are documented in comments at the point of use
(`WhatsAppCampaignsPage.vue:51-55, 69-70`) and pinned by the surface's only spec.

**4.3 The analytics page is honest about three different kinds of "nothing".** It distinguishes "we could
not load this" from "this campaign has not started sending yet" from "this campaign predates analytics",
each with its own icon, title and description (`WhatsAppCampaignAnalyticsPage.vue:144-174`,
`campaign.json:201-213`). The last one is a genuinely thoughtful answer to a question users would
otherwise file as a bug.

**4.4 Processing is a first-class state, not a spinner.** An amber banner says what is still outstanding —
how many messages are queued versus awaiting a delivery receipt from WhatsApp — and the page then polls
metrics, deliveries and the campaign record every 5s *without* flashing loading states
(`:94-143, 294-311, 304-307`), stopping when the page is deactivated or unmounted and restarting on
activation (`:369-379`). The distinction between "we sent it" and "WhatsApp has not told us yet" is
expressed in the status vocabulary itself ("Awaiting delivery update", `campaign.json:263`).

**4.5 Request races are handled properly, twice.** Both analytics fetchers increment a request id, capture
it, and discard their own response if either the id or the campaign id has moved on
(`:235-292`); switching campaigns wipes derived state and deliberately suppresses the extra fetch that the
filter reset would otherwise cause (`:328-365`, `skipNextFilterRefresh`). The comment at `:328-329`
explains why the campaign id, not the mount hook, is the trigger.

**4.6 The delivery breakdown does arithmetic the user would get wrong.** "Delivered" is shown as
delivered-minus-read so the segments sum to the audience instead of double-counting, "pending" is the
remainder floored at zero, and both are labelled in plain language ("Queued or awaiting update")
(`CampaignDeliveryBreakdown.vue:23-70`, `campaign.json:277`).

**4.7 Failure reasons degrade gracefully and never show a bare code twice.** The reason cell prefers
`error_message`, then `error_title`, then the code, and suppresses the "Code {n}" second line when it
would merely repeat what is already shown (`CampaignDeliveryTable.vue:39-46, 137-154`). An ungenerated
message is labelled "Not generated" in italics rather than left blank (`:48-50, 128-132`).

**4.8 Every metric has a definition.** All six tiles carry a hint explaining what the number counts,
including the two that are genuinely ambiguous — that "Delivered" includes read messages, and that
"Skipped" means a contact was dropped before sending, usually for a missing or invalid phone number
(`campaign.json:236-259`). The content is right even though its delivery mechanism is not (3.14.11).

**4.9 Template handling is shared with the rest of the product rather than re-implemented.** The campaign
form reuses `WhatsAppTemplateParser` — the same component the conversation composer uses — for the preview
and the per-variable inputs, offers only templates the shared `isSendableTemplate` helper considers
sendable (`store/modules/inboxes.js:53-73`), humanises the raw template names into readable labels with the
language appended (`WhatsAppCampaignForm.vue:83-94`), resets the choice when the inbox changes
(`:176-181`), and blocks submission through the same `isWhatsAppComplete` check the mobile app uses
(`WhatsAppTemplateParser.vue:116-119`).

**4.10 The scheduling inputs refuse the past.** Both one-off forms compute a timezone-corrected `min` for
the `datetime-local` field and convert to UTC on submit, with a comment saying why
(`SMSCampaignForm.vue:49-54, 83-84`, `WhatsAppCampaignForm.vue:63-68, 126-127`).

**4.11 The live chat sender picker is honest about the bot.** "Sent by" always offers `Bot` as the first
option and maps it to a null `sender_id` on the way out, and hydration maps a missing sender back to it
(`LiveChatCampaignForm.vue:94-97, 139, 176`); the card then shows the same word with an avatar
(`LiveChatCampaignDetails.vue:25-27`). One concept, one name, three places.

**4.12 URL triggers are validated as patterns, not as strings.** The live chat form accepts anything
`URLPattern` can parse but still insists on an `http`/`https` scheme
(`LiveChatCampaignForm.vue:56-68`) — which is what makes wildcard triggers like
`https://{*.}?example.com/apps/*` usable at all.

**4.13 The analytics entry point is state-aware.** The chart button appears only for a WhatsApp campaign
that has actually started — `processing` or `completed` — so a scheduled campaign does not offer a page
that would have nothing to show (`CampaignList.vue:18, 39-43`).

**4.14 The contact column of the deliveries table is a real cross-module link.** Name plus phone number,
linking to that contact's page with an explicit outward glyph (`CampaignDeliveryTable.vue:98-119`). The
analytics page is consequently the one place in campaigns that leads back into Contacts, which is the
natural next step after reading a failure.

**4.15 Click-outside already knows about the editor's own nested dialog.** The live chat popover's
click-outside handler ignores the ProseMirror link prompt's backdrop
(`CampaignLayout.vue:32-37`), and `Dialog` closes only when it is the topmost open `<dialog>`
(`Dialog.vue:99-108`). Both are fixes for real bugs and both are easy to lose in a rewrite.
