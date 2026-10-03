# Surface audit — Commerce panel and Customer 360

Read-only audit. Baseline for the feature-preservation contract of the visual/interaction modernization
phase. Every assertion is anchored to `file:line` in the current tree. Nothing in this document proposes a
redesign; it records what exists.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`.

Files in scope (all paths relative to `app/javascript/dashboard/components/widgets/conversation/commerce/`):

| File | Lines | Role |
|---|---|---|
| `CommercePanel.vue` | 564 | Container: store list, view switch, link/unlink, customer search, orchestration |
| `CommerceOverview.vue` | 275 | Customer 360: cross-store KPIs, recent orders, per-store rows |
| `CommerceOrderItem.vue` | 190 | One order card (used in 3 contexts) |
| `CommerceOrderActions.vue` | 545 | Order action menu → form → review → confirm → result dialog |
| `CommerceOrderSearch.vue` | 134 | "Find an order" by order number |
| `CommerceCarts.vue` | 254 | Abandoned carts + recovery-message preparation |
| `commerceHelper.js` | 92 | URL sanitising, money/date/relative-time formatting, tracking message |
| `useCommerceLabels.js` | 155 | Code → string maps (statuses, errors, providers, states) |
| `useCommerceActionLabels.js` | 67 | Action types, unavailable reasons, refund/cancel reasons |

Supporting surfaces read for gating and context: `routes/dashboard/conversation/ContactPanel.vue`,
`components/widgets/conversation/ConversationSidebar.vue`, `components/Accordion/AccordionItem.vue`,
`composables/useUISettings.js`, `composables/useAdmin.js`, `composables/useAbortableRequest.js`,
`api/commerce.js`, `featureFlags.js`, `i18n/locale/en/commerce.json`.

---

## 1. Routes and primary task

### 1.1 How this surface is reached

The Commerce panel is **not a route of its own**. It is a draggable accordion section inside the
conversation contact sidebar:

```
ConversationView.vue:219-224  →  ConversationSidebar.vue:63-67  →  ContactPanel.vue:307-320  →  CommercePanel.vue
InboxView.vue:217-220         →  ConversationSidebar.vue:63-67  →  ContactPanel.vue:307-320  →  CommercePanel.vue
```

| Host | Mount site | Gate |
|---|---|---|
| Conversation workspace | `ConversationView.vue:219-224` | `shouldShowSidebar` = `currentChat.id` present AND `uiSettings.is_contact_sidebar_open` (`ConversationView.vue:84-91`) |
| Inbox (notifications) view | `InboxView.vue:217-220` | `isContactPanelOpen`, same two conditions (`InboxView.vue:69-75`) |

Inside `ContactPanel.vue` the section renders only when:

- the sidebar item `commerce` is in the agent's order list — default position **2 of 11**, right after
  `conversation_actions` (`useUISettings.js:5-17`), and
- `isCommerceEnabled` — `isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_COMMERCE)` = `lynomia_commerce`
  (`ContactPanel.vue:66-68`, `featureFlags.js:58`).

It is wrapped in `AccordionItem` with `compact` and title `COMMERCE.TITLE` ("Commerce"), open state stored
per agent under `is_commerce_open` in UI settings (`ContactPanel.vue:308-313`,
`useUISettings.js:76-78, 170-172`).

### 1.2 Routes on which the surface is reachable

Every route that renders `ConversationView`, plus the inbox detail route. Permissions for all conversation
routes: `['administrator','agent','conversation_manage','conversation_unassigned_manage','conversation_participating_manage']`
(`conversation.routes.js:6-12`).

- `/app/accounts/:accountId/dashboard` — `home` (`conversation.routes.js:49`)
- `/app/accounts/:accountId/conversations/:conversation_id` — `inbox_conversation` (`:60`)
- `/app/accounts/:accountId/inbox/:inbox_id` — `inbox_dashboard` (`:71`)
- `/app/accounts/:accountId/inbox/:inbox_id/conversations/:conversation_id` — `conversation_through_inbox` (`:84`)
- `/app/accounts/:accountId/label/:label` — `label_conversations` (`:98`)
- `/app/accounts/:accountId/label/:label/conversations/:conversation_id` — `conversations_through_label` (`:109`)
- `/app/accounts/:accountId/team/:teamId` — `team_conversations` (`:121`)
- `/app/accounts/:accountId/team/:teamId/conversations/:conversationId` — `conversations_through_team` (`:132`)
- `/app/accounts/:accountId/custom_view/:id` — `folder_conversations` (`:144`, guard `:23-29`)
- `/app/accounts/:accountId/custom_view/:id/conversations/:conversation_id` — `conversations_through_folders` (`:156`, guard `:31-43`)
- `/app/accounts/:accountId/mentions/conversations` — `conversation_mentions` (`:169`)
- `/app/accounts/:accountId/mentions/conversations/:conversationId` — `conversation_through_mentions` (`:180`)
- `/app/accounts/:accountId/unattended/conversations` — `conversation_unattended` (`:192`)
- `/app/accounts/:accountId/unattended/conversations/:conversationId` — `conversation_through_unattended` (`:203`)
- `/app/accounts/:accountId/participating/conversations` — `conversation_participating` (`:215`)
- `/app/accounts/:accountId/participating/conversations/:conversationId` — `conversation_through_participating` (`:226`)
- `/app/accounts/:accountId/inbox-view/:type/:id` — `inbox_view_conversation`, permissions `[...ROLES, ...CONVERSATION_PERMISSIONS]` (`inbox/routes.js:23-30`)

The only *outbound* route reference from this surface is the plain-text string "Connect a store in
Settings → Commerce." (`CommercePanel.vue:310`, `commerce.json` `PANEL.NO_STORES_ADMIN`). The real
destination is `settings_commerce_index` (`settings/commerce/commerce.routes.js:15`, reachable from
`components-next/sidebar/Sidebar.vue:828-833`), but the panel does **not** link to it.

### 1.3 Primary task

Let an agent answer an order question **inside the conversation thread**, without opening the merchant's
store admin: see which store customer this contact is (and link them if the match is not automatic), read
that customer's recent orders with payment and fulfilment state, hand the customer a tracking number or a
cart-recovery message through the reply box, and — where the store and the agent's permissions allow — run
a reviewed, confirmed write action on an order (status change, cancel, refund, resend invoice / payment
link). Customer 360 answers the same question across **all** connected stores at once.

Two views, one surface (`CommercePanel.vue:32-36, 75-77`):

- **Overview** (Customer 360) — aggregate across stores. Offered only when `stores.length > 1`.
- **Store** — one store: its link state, its customer search, its orders.

Default: the agent's remembered choice from `localStorage['lynomia.commerce.view']`, else Overview when the
contact is linked in more than one store, else Store (`CommercePanel.vue:35-52, 228-234`).

### 1.4 Honest terminology (contract-relevant)

The surface deliberately never claims lifetime figures. `CommerceOverview.vue:9-10` states the rule and the
copy follows it:

- `OVERVIEW.ORDERS_VALUE` = "{count} visible"; `ORDERS_HINT` = "Latest orders each store returned, not a
  lifetime total" (`CommerceOverview.vue:100, 109-115`)
- `OVERVIEW.SPEND_HINT` = "Paid orders among those shown, per currency" (`:139`)
- `OVERVIEW.STALE` = "Showing data from {time}" vs `UPDATED` = "Updated {time}" (`:55-61`)
- `PANEL.UPDATE_FAILED` = "Couldn't refresh store data right now." (`CommercePanel.vue:404`)
- Agent-sends-it-themselves wording on both insert flows: `PANEL.TRACKING_INSERTED`,
  `CARTS.PREPARED` ("Review it and send it yourself.")
- Refund consequence distinguishes gateway refunds from a store-recorded refund with no money moved
  (`CommerceOrderActions.vue:112-125`)
- `ACTIONS.RESULT.UNKNOWN` / `UNRESOLVED` never claim success (`:146-150`)

---

## 2. Feature parity manifest

Every control, state, message and affordance this surface renders today. **Kind** uses the vocabulary of
the structured summary. "Gates" is the literal condition in the code.

### 2.1 Container, mounting and section chrome

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 1 | "Commerce" accordion section | navigation | `ContactPanel.vue:307-320` | `lynomia_commerce` cloud flag (`ContactPanel.vue:66-68`) + `commerce` present in sidebar order |
| 2 | Collapse / expand the section (persisted per agent) | state | `AccordionItem.vue:36-54`; `ContactPanel.vue:310-313` | none; stored as `is_commerce_open` |
| 3 | Drag-reorder the Commerce section among sidebar sections | secondary | `ContactPanel.vue:156-165` (`handle=".drag-handle"`, `AccordionItem.vue:37`) | none; saved via `updateUISettings` |
| 4 | Section default position (2nd of 11) | state | `useUISettings.js:5-17` | none |
| 5 | Panel container width 320px (360px at 2xl), full-width overlay under 768px | mobile | `ConversationSidebar.vue:54` | viewport |
| 6 | Click-outside closes the whole sidebar on small screens | mobile | `ConversationSidebar.vue:28-39, 44-53` | `windowWidth < 768` (`globals.js:48`) |
| 7 | Panel padding `px-4 py-2`, single `gap-3` rhythm | state | `CommercePanel.vue:294-297` | none |

### 2.2 Panel-level states

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 8 | First-load spinner | loading | `CommercePanel.vue:298-303` | `isLoading && !panel && !overview` |
| 9 | "No store is connected yet." | empty-state | `CommercePanel.vue:305-311` | `!stores.length` |
| 10 | Admin-only second line "Connect a store in Settings → Commerce." | empty-state | `CommercePanel.vue:310` | `isAdmin` (`useAdmin.js:12`) |
| 11 | Store-view load error (plain ruby text) | error | `CommercePanel.vue:394-396` | `loadError` |
| 12 | Overview load error (plain ruby text) | error | `CommercePanel.vue:363-365` | `loadError` |
| 13 | Stale / update-failed amber banner | error | `CommercePanel.vue:399-409` | `panel.error` |
| 14 | Last-updated age inside that banner | status | `CommercePanel.vue:102-108, 405` | `panel.stale && panel.fetched_at` |
| 15 | Coded error sentence instead of the age | error | `CommercePanel.vue:406-408` | `!panel.stale` |
| 16 | 33 mapped backend error codes → safe sentences, generic fallback | error | `useCommerceLabels.js:43-78` | code present |
| 17 | `INVALID_STORE_URL` → 7 URL-reason sentences | error | `useCommerceLabels.js:80-94` | `error.reason` |
| 18 | Legacy-Shopify-integration conflict sentence | error | `useCommerceLabels.js:95-97` | `reason === 'legacy_shopify_integration'` |
| 19 | Abortable fetches (latest wins) for stores / panel / overview | state | `CommercePanel.vue:30, 126-128, 141-143, 223-225`; `useAbortableRequest.js` | none |

### 2.3 View switch and refresh

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 20 | "Overview" tab | tab | `CommercePanel.vue:321-330` | `hasOverview` = `stores.length > 1` (`:68`) |
| 21 | "Store" tab | tab | `CommercePanel.vue:331-340` | `hasOverview` |
| 22 | `role="tablist"` / `role="tab"` / `aria-selected` | state | `CommercePanel.vue:316-340` | `hasOverview` |
| 23 | Selected tab styling (`faded` vs `ghost`) | state | `CommercePanel.vue:324, 334` | `isOverview` |
| 24 | View choice remembered in `localStorage['lynomia.commerce.view']` | state | `CommercePanel.vue:35-52, 206-210` | try/catch, silent on failure |
| 25 | Opens on Overview when linked in >1 store | state | `CommercePanel.vue:231-233` | `linkedCount > 1` and no saved choice |
| 26 | Refresh button (icon + label + loading) | primary | `CommercePanel.vue:342-352` | always when `stores.length` |
| 27 | Refresh re-reads the open view only (overview or one store) | secondary | `CommercePanel.vue:184-190`; `api/commerce.js:60-66` | `isOverview` |
| 28 | Refresh cooldown notice with `retry_after` (default 30s) | status | `CommercePanel.vue:159, 192-197, 354-360` | HTTP 429 |
| 29 | Refresh failure falls back to the load-error text | error | `CommercePanel.vue:198-200` | non-429 |
| 30 | Store picker `<Select>` with label "Store" | filter | `CommercePanel.vue:381-392` | `stores.length > 1` |
| 31 | Store options from `/conversations/:id/commerce/stores` | filter | `CommercePanel.vue:79-81, 217-240` | — |
| 32 | Preferred store on load = first linked, else first | state | `CommercePanel.vue:228-230` | — |
| 33 | "Open store" from Overview switches to Store tab on that store | navigation | `CommercePanel.vue:212-215`; `CommerceOverview.vue:263-270` | state not in `NOT_OPENABLE_STATES` |

### 2.4 Customer link / unlink and candidate search (Store view)

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 34 | "Linked customer" block with the customer's name | status | `CommercePanel.vue:411-423`; name from first order (`:98-100`) | `panel.state === 'linked'` |
| 35 | Match-source line (verified phone / email / store customer ID / manual) | status | `useCommerceLabels.js:117-122`; `CommercePanel.vue:420-422` | `panel.link` |
| 36 | "Linked by {name}" attribution for manual links | status | `CommercePanel.vue:87-96` | `match_source === 'manual' && confirmed_by.name` |
| 37 | "Change" — reopens the candidate search | secondary | `CommercePanel.vue:425-431` | linked |
| 38 | "Unlink" (ruby ghost, no confirmation) | destructive | `CommercePanel.vue:432-438, 276-283` | linked |
| 39 | Match-state message: not found / possible match / several match | status | `useCommerceLabels.js:124-129`; `CommercePanel.vue:461-467` | state not `linked` and not `unavailable` |
| 40 | "Link customer" button | primary | `CommercePanel.vue:468-474` | not linked, `!isSearchOpen` |
| 41 | Search input, placeholder "Email or phone with country code" | filter | `CommercePanel.vue:479-485` | `isSearchOpen` |
| 42 | Enter in the search input runs the search | shortcut | `CommercePanel.vue:484` (`@enter`), `Input.vue:144` | `isSearchOpen` |
| 43 | "Search" button, disabled while the query is blank, loading state | primary | `CommercePanel.vue:486-492` | `query.trim()` |
| 44 | Search hint (exact email / international phone, names not searched) | state | `CommercePanel.vue:494-496` | `isSearchOpen` |
| 45 | Search error text | error | `CommercePanel.vue:497-499, 269-270` | `searchError` |
| 46 | "No store customer matches." | empty-state | `CommercePanel.vue:500-505` | `candidates && !candidates.length` |
| 47 | Candidate rows: name, email · phone (`dir="ltr"`), guest/registered | state | `CommercePanel.vue:513-539` | — |
| 48 | Backend-suggested candidates shown without searching | state | `CommercePanel.vue:83-85, 508-512` | `panel.candidates` |
| 49 | Per-row "Link" button with its own loading state | primary | `CommercePanel.vue:540-545, 259-274` | — |
| 50 | Search resets on store change / reload (not on silent refetch) | state | `CommercePanel.vue:110-124` | `!silent` |

### 2.5 Customer 360 overview

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 51 | "Some stores couldn't be refreshed" amber banner | error | `CommerceOverview.vue:66-72` | `overview.partial` |
| 52 | KPI tile — Stores: "{count} connected" | status | `CommerceOverview.vue:75-87` | — |
| 53 | KPI sub-value — "{count} linked" | status | `CommerceOverview.vue:88-96` | — |
| 54 | KPI tile — Orders: "{count} visible" | status | `CommerceOverview.vue:98-116` | — |
| 55 | Orders hint tooltip ("not a lifetime total") via native `title` | state | `CommerceOverview.vue:100` | hover only |
| 56 | Activity line "{active} active · {shipped} shipped" | status | `CommerceOverview.vue:117-124` | — |
| 57 | KPI tile — Last purchase (relative time) | status | `CommerceOverview.vue:30-34, 126-136` | `overview.last_order_at` |
| 58 | "No orders found" in the Last purchase tile | empty-state | `CommerceOverview.vue:33` | no `last_order_at` |
| 59 | KPI tile — Spend, one line per currency | status | `CommerceOverview.vue:25-29, 137-151` | `total_spend_visible` |
| 60 | Spend hint tooltip ("Paid orders among those shown, per currency") | state | `CommerceOverview.vue:139` | hover only |
| 61 | "No paid orders" | empty-state | `CommerceOverview.vue:152-154` | `!spend.length` |
| 62 | "Customer not linked" + "Open a store to find and link the customer." | empty-state | `CommerceOverview.vue:158-167` | `linked_stores_count === 0` |
| 63 | "Recent orders" collapsible section (local state, default open) | tab | `CommerceOverview.vue:22, 170-184` | `isLinked` |
| 64 | `aria-expanded` on the Recent orders toggle | state | `CommerceOverview.vue:173` | — |
| 65 | "No orders found" inside Recent orders | empty-state | `CommerceOverview.vue:186-190` | `!latest_orders.length` |
| 66 | Cross-store order cards, each labelled with its store | state | `CommerceOverview.vue:192-202` | `showOrders` |
| 67 | Per-order actions offered only for stores that allow them | contextual | `CommerceOverview.vue:198-200`; `CommercePanel.vue:69-71` | `actionStoreIds.includes(order.store.id)` |
| 68 | "Stores" collapsible section (local state, default open) | tab | `CommerceOverview.vue:23, 206-221` | always |
| 69 | Per-store row "{store} · {provider}" | state | `CommerceOverview.vue:229-237` | — |
| 70 | Provider display names (WooCommerce / Salla / Zid / Shopify, raw fallback) | state | `useCommerceLabels.js:101-107` | — |
| 71 | Per-store state label, 6 mapped states + "Couldn't refresh" fallback | status | `useCommerceLabels.js:132-140`; `CommerceOverview.vue:238-247` | — |
| 72 | Amber colouring for attention states / errors | status | `CommerceOverview.vue:37-41, 240-245` | state in `ATTENTION_STATES` or `entry.error` |
| 73 | Per-store identity line "Guest checkout / Registered customer · match source" | state | `CommerceOverview.vue:44-52, 248-253` | `entry.link` |
| 74 | Per-store freshness "Updated {time}" / "Showing data from {time}" | status | `CommerceOverview.vue:54-61, 254-261` | `entry.fetched_at` |
| 75 | Amber freshness when the copy is stale | status | `CommerceOverview.vue:257` | `entry.stale` |
| 76 | "Open store" per-store button | navigation | `CommerceOverview.vue:263-270` | state not `needs_reauth` / `provider_unavailable` (`:42`) |
| 77 | Order-search disclosure rendered under the overview (all stores) | filter | `CommercePanel.vue:374-377` | `overview` loaded |

### 2.6 Order card

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 78 | Order number rendered as `#{number}`, `dir="ltr"` | state | `CommerceOrderItem.vue:94-103` | — |
| 79 | Click the order number to copy it | secondary | `CommerceOrderItem.vue:70-77, 100` | — |
| 80 | "Copy the order number" tooltip (`v-tooltip.top`) | state | `CommerceOrderItem.vue:95` | hover/focus |
| 81 | "Order number copied" toast | status | `CommerceOrderItem.vue:73` | success |
| 82 | "Couldn't copy the order number." toast | error | `CommerceOrderItem.vue:75` | clipboard throw |
| 83 | Order total, `Intl.NumberFormat` currency | status | `CommerceOrderItem.vue:56-58, 105`; `commerceHelper.js:36-47` | — |
| 84 | Amount fallback `"{amount} {currency}"` on bad input or bad currency | state | `commerceHelper.js:38, 45` | NaN / Intl throw |
| 85 | Order-actions trigger (ellipsis icon button) | contextual | `CommerceOrderItem.vue:106-112`; `CommerceOrderActions.vue:319-328` | `actionsStoreId && conversationId` |
| 86 | Store · provider line on the card | state | `CommerceOrderItem.vue:115-126` | `store` prop (Overview, order search) |
| 87 | Order-status badge, 9 colour mappings | status | `CommerceOrderItem.vue:37-47, 128-133` | — |
| 88 | Order-status labels, 10 codes + "Other" fallback | status | `useCommerceLabels.js:8-20` | — |
| 89 | Payment-status badge, 4 colour mappings | status | `CommerceOrderItem.vue:48-53, 134-139` | — |
| 90 | Payment-status labels, 6 codes + "Unknown" fallback | status | `useCommerceLabels.js:22-30` | — |
| 91 | Neutral badge fallback for unmapped codes | status | `CommerceOrderItem.vue:54` | — |
| 92 | Created date, `Intl.DateTimeFormat` medium | state | `CommerceOrderItem.vue:59-61, 144` | — |
| 93 | Item count, pluralised | state | `CommerceOrderItem.vue:145-153` | `item_count != null` |
| 94 | Shipping method (raw store string) | state | `CommerceOrderItem.vue:154` | `order.shipping.method` |
| 95 | Shipment status as plain text, 7 codes + "Other" | status | `useCommerceLabels.js:32-41`; `CommerceOrderItem.vue:155-157` | `order.shipping.status` |
| 96 | "View order" deep link into the store admin, new tab | contextual | `CommerceOrderItem.vue:163-171` | `safeAdminUrl` non-null (`commerceHelper.js:23-34`) |
| 97 | "Track shipment" carrier link, new tab, https only | contextual | `CommerceOrderItem.vue:172-180` | `safeHttpsUrl` non-null (`commerceHelper.js:8-19`) |
| 98 | "Send tracking" — inserts a tracking message into the reply editor | primary | `CommerceOrderItem.vue:79-85, 181-187` | `canSend && hasTracking` (`:64-66`) |
| 99 | Tracking message, 3 shapes (number+url / url / number) | state | `commerceHelper.js:72-92` | — |
| 100 | "Tracking details added to the reply box…" toast | status | `CommerceOrderItem.vue:84` | — |
| 101 | Send-tracking suppressed for orders found by number | state | `CommerceOrderItem.vue:24-27`; `CommerceOrderSearch.vue:129` | `canSend === false` |
| 102 | "No orders yet." under a linked customer | empty-state | `CommercePanel.vue:441-447` | `panel.orders` present and empty |

### 2.7 Order actions dialog

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 103 | Dialog, width `md`, title "Order #{number}" | contextual | `CommerceOrderActions.vue:329-334` | trigger click |
| 104 | Dialog description = "{store} · {provider}" | state | `CommerceOrderActions.vue:91-98, 335-337` | `availability.store` |
| 105 | Availability loading row ("Reading the order from the store…") | loading | `CommerceOrderActions.vue:340-343` | `isLoading` |
| 106 | Availability load error | error | `CommerceOrderActions.vue:344-346, 176-181` | `loadError` |
| 107 | "An earlier action … couldn't be confirmed" amber warning | error | `CommerceOrderActions.vue:88-90, 348-355` | `last_run.status` in pending/running/unknown |
| 108 | "No action is possible on this order right now." | empty-state | `CommerceOrderActions.vue:356-358` | `!listedActions.length` |
| 109 | Fixed action order (status, invoice, payment link, cancel, partial, full) | state | `CommerceOrderActions.vue:26-33` | — |
| 110 | Unsupported actions hidden entirely | state | `CommerceOrderActions.vue:80-85` | `reason === 'unsupported'` |
| 111 | Unavailable actions listed but disabled | state | `CommerceOrderActions.vue:371, 376-381` | `!action.available` |
| 112 | Per-action reason text, 9 codes + "Not available right now." | state | `useCommerceActionLabels.js:19-30` | `!available` |
| 113 | Permission-denied reason (backend-decided) | state | `useCommerceActionLabels.js:21`; backend `commerce_order_manage` (`constants/permissions.js:8`) | agent permission |
| 114 | Destructive actions coloured ruby in the menu | destructive | `CommerceOrderActions.vue:34, 368` | cancel / refund_* |
| 115 | Action labels, 7 types, raw-code fallback | state | `useCommerceActionLabels.js:8-17` | — |
| 116 | Form step for the 4 actions that need input | state | `CommerceOrderActions.vue:35-40, 217-226, 386-429` | `NEEDS_FORM` |
| 117 | Actions without input skip straight to Review | state | `CommerceOrderActions.vue:224-225` | `resend_*` |
| 118 | Refund amount input, `inputmode="decimal"`, `dir="ltr"` | form | `CommerceOrderActions.vue:391-405` | `isRefund` |
| 119 | Amount prefilled and locked for "Refund in full" | form | `CommerceOrderActions.vue:220, 394` | `refund_full` |
| 120 | Amount hint "Up to {max}" | state | `CommerceOrderActions.vue:396-400` | `isRefund` |
| 121 | Amount validation: pattern, > 0, ≤ max → inline error | error | `CommerceOrderActions.vue:41, 196-209` | Review click |
| 122 | Reason select — 5 refund reasons | form | `useCommerceActionLabels.js:32-47`; `:407-417` | `isRefund` |
| 123 | Reason select — 5 cancel reasons | form | `useCommerceActionLabels.js:49-64`; `:407-417` | `cancel_order` |
| 124 | Default reason `customer_request` | state | `CommerceOrderActions.vue:222` | — |
| 125 | "New status" select from the store's allowed targets | form | `CommerceOrderActions.vue:101-106, 418-428` | `update_order_status` |
| 126 | Default target status = first allowed | state | `CommerceOrderActions.vue:223` | — |
| 127 | Review step: Store / Order / Action rows | state | `CommerceOrderActions.vue:431-454` | — |
| 128 | Review step: Amount row | state | `CommerceOrderActions.vue:455-465` | `isRefund` |
| 129 | Consequence sentence, 7 variants | state | `CommerceOrderActions.vue:108-140, 467-477` | action + capability |
| 130 | Consequence styled ruby for destructive, neutral otherwise | destructive | `CommerceOrderActions.vue:468-473` | `isDestructive` |
| 131 | Submit error: 401 → "You don't have permission for this." | error | `CommerceOrderActions.vue:294-295` | HTTP 401 |
| 132 | Submit error: 429 → "Too many actions … {seconds} s." (fallback 60) | error | `CommerceOrderActions.vue:44, 296-301` | HTTP 429 |
| 133 | Submit error: anything else → coded sentence | error | `CommerceOrderActions.vue:302-303` | — |
| 134 | Fresh idempotency key per confirmation | state | `CommerceOrderActions.vue:211-213` | Review entry |
| 135 | Optimistic-concurrency `version` sent with the request | state | `CommerceOrderActions.vue:283`; `api/commerce.js:113-118` | — |
| 136 | Double-submit guard | state | `CommerceOrderActions.vue:273, 538` | `isSubmitting` |
| 137 | "Confirm" button, ruby when destructive, loading + disabled | primary | `CommerceOrderActions.vue:531-541` | Review step |
| 138 | "Review" button | primary | `CommerceOrderActions.vue:524-530` | Form step |
| 139 | "Back" (Review → Form → Menu) | secondary | `CommerceOrderActions.vue:310-315, 504-513` | Form or Review step |
| 140 | "Close" | secondary | `CommerceOrderActions.vue:514-522, 193` | Menu or Result step |
| 141 | Enter never confirms — every button is `type="button"` | shortcut | `CommerceOrderActions.vue:15-17, 370, 509, 519, 528, 537` | by design |
| 142 | Result step with spinner while waiting | loading | `CommerceOrderActions.vue:483-499` | `isWaiting` |
| 143 | Run polling, 1.5 s × 40 attempts | loading | `CommerceOrderActions.vue:42-43, 254-270` | pending/running |
| 144 | Result messages: processing / succeeded / failed / unknown / unresolved / still processing | status | `CommerceOrderActions.vue:142-154` | `run.status`, `reconcile` |
| 145 | Result colour coding (teal / ruby / amber / slate) | status | `CommerceOrderActions.vue:489-495` | `run.status` |
| 146 | "Order #{number} updated in {store}." toast on success | status | `CommerceOrderActions.vue:243-252` | `status === 'succeeded'` |
| 147 | Success emits `done` → silent panel refetch | state | `CommerceOrderActions.vue:251`; `CommerceOrderItem.vue:111`; `CommercePanel.vue:456` | success only |
| 148 | Polling stops on dialog close and on unmount | state | `CommerceOrderActions.vue:160-164, 333` | — |
| 149 | Poll failures swallowed, run kept server-side | state | `CommerceOrderActions.vue:261-263` | — |

### 2.8 Find an order

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 150 | "Find an order" disclosure (collapsed by default) | tab | `CommerceOrderSearch.vue:22, 70-83` | — |
| 151 | `aria-expanded` on the toggle | state | `CommerceOrderSearch.vue:74` | — |
| 152 | Order-number input, `inputmode="numeric"` | filter | `CommerceOrderSearch.vue:86-94` | `isOpen` |
| 153 | Enter runs the search | shortcut | `CommerceOrderSearch.vue:93` | `isOpen` |
| 154 | "Search" button, disabled when blank, loading | primary | `CommerceOrderSearch.vue:95-102` | `number.trim()` |
| 155 | Hint: exact number; the order may belong to any customer | state | `CommerceOrderSearch.vue:104-106` | `isOpen` |
| 156 | 422 → "Enter an order number using digits only." | error | `CommerceOrderSearch.vue:52-54` | HTTP 422 |
| 157 | 429 → "Too many searches. Try again in {seconds} s." (fallback 60) | error | `CommerceOrderSearch.vue:20, 55-58` | HTTP 429 |
| 158 | Other failures → coded sentence | error | `CommerceOrderSearch.vue:59-60, 107` | — |
| 159 | Per-store notice "order search isn't available for this store" | status | `CommerceOrderSearch.vue:28-36, 109-116` | `state === 'unsupported'` |
| 160 | Per-store notice "{store}: couldn't be searched" | status | `CommerceOrderSearch.vue:34, 109-116` | other non-`searched` state |
| 161 | "No order with this number" | empty-state | `CommerceOrderSearch.vue:117-123` | `!result.orders.length` |
| 162 | Results as order cards with store label and no send action | state | `CommerceOrderSearch.vue:124-130` | — |
| 163 | Scope: one store (Store view, `:key="storeId"`) or all stores (Overview) | filter | `CommercePanel.vue:374-377, 549-553`; `api/commerce.js:69-74` | `storeId` prop |

### 2.9 Abandoned carts

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 164 | Carts component mounted only for cart-capable accounts | state | `CommercePanel.vue:72, 556-561` | `stores.some(s => s.carts)` |
| 165 | Section shown only when there are carts or failed stores | empty-state | `CommerceCarts.vue:119-123` | `carts.length \|\| failedStores.length` |
| 166 | "Abandoned carts" heading | state | `CommerceCarts.vue:124-126` | — |
| 167 | Store scope: that store's carts (Store view) or all (Overview) | filter | `CommerceCarts.vue:40-44`; `CommercePanel.vue:559` | `storeId` |
| 168 | Reload on live update / Refresh via `reloadKey` | state | `CommerceCarts.vue:19-21, 110-114`; `CommercePanel.vue:74, 153` | — |
| 169 | "Couldn't read {store}'s abandoned carts." per failed store | error | `CommerceCarts.vue:45-52, 127-133` | `state === 'unavailable'`, error ≠ `RECOVERY_DISABLED` |
| 170 | Cart total (currency formatted) | status | `CommerceCarts.vue:141-143` | — |
| 171 | Cart item count (summed quantities, pluralised) | status | `CommerceCarts.vue:55-56, 144-152` | — |
| 172 | "{store} · {provider} · left {time}" | state | `CommerceCarts.vue:154-162` | — |
| 173 | Match label: linked customer / verified phone / verified email | status | `CommerceCarts.vue:33-38, 163-165` | — |
| 174 | "View cart" / "Hide cart" per-cart item list | secondary | `CommerceCarts.vue:166-179, 216-230` | — |
| 175 | Item lines "{quantity} × {name}", "Item" when unnamed | state | `CommerceCarts.vue:171-178` | `expanded[cartKey]` |
| 176 | "Recovery message sent {time}" (teal) | status | `CommerceCarts.vue:180-186` | `recovery.sent_at` |
| 177 | "Recovery message prepared {time}, not sent yet" | status | `CommerceCarts.vue:187-196` | `recovery.prepared_at` |
| 178 | "Another recovery message is possible {time}." (amber) | status | `CommerceCarts.vue:59-61, 197-207` | `cooldown_until` in the future |
| 179 | Per-cart error notice | error | `CommerceCarts.vue:103-105, 208-214` | `notices[cartKey]` |
| 180 | "Prepare recovery message" → inserts into the reply box | primary | `CommerceCarts.vue:86-108, 231-239` | `!coolingDown(cart)` |
| 181 | Per-cart loading state while preparing | loading | `CommerceCarts.vue:236, 246` | `preparing === cartKey` |
| 182 | "Recovery message added to the reply box…" toast | status | `CommerceCarts.vue:101` | success |
| 183 | Reload carts after a successful prepare | state | `CommerceCarts.vue:102` | success |
| 184 | "Prepare anyway" — cooldown override | destructive | `CommerceCarts.vue:240-249`; `api/commerce.js:128-138` | `coolingDown && isAdmin` |
| 185 | Recovery template with / without the contact's first name | state | `CommerceCarts.vue:72-84` | `first_name` |
| 186 | Cart load failures swallowed to an empty list | error | `CommerceCarts.vue:67-69` | request throw |

### 2.10 Live data and cross-module wiring

| # | Feature | Kind | Where it lives today | Gated by |
|---|---|---|---|---|
| 187 | Live refetch on `COMMERCE_CUSTOMER_UPDATED`, debounced 500 ms | state | `CommercePanel.vue:157-172`; `helper/actionCable.js:349`; `busEvents.js:16` | event `contact_id` matches; in Store view also `store_id` |
| 188 | Silent refetch keeps the open search and shows no spinner | state | `CommercePanel.vue:117-124` | `silent: true` |
| 189 | Refetch of the open view on websocket reconnect | state | `CommercePanel.vue:173-176` | `stores.length` |
| 190 | Debounce timer cleared on unmount | state | `CommercePanel.vue:177` | — |
| 191 | Reload everything when the conversation changes | state | `CommercePanel.vue:290` | `conversationId` watch |
| 192 | Insert into the reply editor (`INSERT_INTO_RICH_EDITOR`) — tracking and cart recovery | contextual | `CommerceOrderItem.vue:80-83`; `CommerceCarts.vue:97-100` | — |
| 193 | Global toasts for copy / insert / action success / cart prepare | status | `composables/index.js:17-23` | — |
| 194 | Legacy Shopify orders accordion can be shown at the same time | navigation | `ContactPanel.vue:291-306` | `shopify` integration enabled |
| 195 | URL sanitising before any link is opened or sent | state | `commerceHelper.js:8-34` | https-only for customer-facing, http allowed for admin |
| 196 | Relative-time formatting, minutes → hours → days | state | `commerceHelper.js:56-67` | — |
| 197 | Arabic/RTL rendering of the whole panel | state | covered by `CommercePanel.spec.js:245` | `locale` |

### 2.11 Dead or unreachable today (record, do not resurrect blindly)

| Item | Evidence |
|---|---|
| `ORDER_LIMIT = 5` exported, no consumer | `commerceHelper.js:3` |
| `update_shipping` has a label but is not in `ACTION_ORDER`, so it is never listed | `useCommerceActionLabels.js:16` vs `CommerceOrderActions.vue:26-33` |
| `COMMERCE.PANEL.CANCEL` unused | `i18n/locale/en/commerce.json` |
| `COMMERCE.CARTS.STORE_LINE` unused (`STORE_AND_AGE` is used instead) | `CommerceCarts.vue:156` |
| `COMMERCE.ACTIONS.RESULT.FAILED` unused — failures render `errorMessage(run.error_code)` | `CommerceOrderActions.vue:145` |
| `storeStatus` / `urlError` exported from `useCommerceLabels` but only consumed by Settings → Commerce | `useCommerceLabels.js:109-115, 80-89` |

---

## 3. Visual and interaction audit

Severity is about agent task risk inside a 320 px panel, not aesthetics.

### 3.1 Hierarchy

**H1 (high) — the number an agent scans is weaker than the one they rarely read.** The order number is
`text-heading-3` (`CommerceOrderItem.vue:97`) while the order total is `text-body-main`
(`CommerceOrderItem.vue:105`). Status and payment badges are `text-label-small` (`:129, 135`). On a card
whose job is "what state is this order in and for how much", the identifier wins the hierarchy and the
state loses it.

**H2 (high) — three different heading treatments for peer sections.** "Abandoned carts" is
`text-heading-3` and not collapsible (`CommerceCarts.vue:124-126`); "Recent orders" and "Stores" are
`text-label-small text-n-slate-11` collapsible buttons (`CommerceOverview.vue:172, 209`); "Find an order"
is the same label-small button (`CommerceOrderSearch.vue:72`); "Linked customer" is a label-small caption
above a `text-heading-3` name (`CommercePanel.vue:414-419`). Four levels of prominence for four things at
the same level of the information architecture.

**H3 (medium) — no heading elements at all.** Every section title inside the panel is a `<span>` or
`<button>`; the only real heading is the accordion's `h5` "Commerce" (`AccordionItem.vue:43`). There is no
heading outline for the whole surface.

**H4 (medium) — the honest qualifier is hidden behind hover.** "not a lifetime total" and "Paid orders
among those shown, per currency" live only in native `title` attributes
(`CommerceOverview.vue:100, 139`). On touch and for keyboard users the Spend tile reads simply "Spend" with
a number. The Orders tile puts "visible" in the value itself (`:109-115`); Spend does not. The surface's
most important truth claim is the least visible thing on it.

**H5 (medium) — the `partial` banner names no store.** "Some stores couldn't be refreshed"
(`CommerceOverview.vue:66-72`) is 100+ px above the per-store rows that say which ones
(`CommerceOverview.vue:238-247`), and those rows sit inside a collapsible section that the agent may have
closed (`:206-221`).

### 3.2 Density and spacing

**D1 (high) — one spacing value for everything.** The panel root is `flex flex-col gap-3`
(`CommercePanel.vue:295`). Tabs, refresh notice, the store picker, the stale banner, the linked-customer
block, the order list, the search block, the candidate list, "Find an order" and "Abandoned carts" are all
separated by the same 12 px. Nothing groups; the panel reads as one undifferentiated column.

**D2 (medium) — a phantom gap under the panel.** `CommerceCarts.vue:117-123` always renders its outer
`<div>`, with the `<section>` inside it conditional. Because `CommercePanel.vue:556` mounts it on *store
capability* (`stores.some(s => s.carts)`), not on *cart presence*, a capable store with no carts — or the
Store tab filtered to a store with no carts (`CommerceCarts.vue:40-44`) — leaves an empty div plus its
12 px gap at the bottom of the panel.

**D3 (medium) — a 2-column KPI grid at 320 px.** `grid-cols-2` with no responsive step
(`CommerceOverview.vue:74`) gives each tile roughly 140 px of inner width after the panel's `px-4` and the
grid gap. "Last purchase" renders relative strings, and Spend renders a formatted currency amount per
currency (`:144-151`) — a multi-currency contact produces tiles of visibly unequal height inside a
`grid-cols-2` row.

**D4 (low) — nothing aligns the per-store action.** The store row is `items-start`
(`CommerceOverview.vue:226`) with a 2–4 line text block on one side and a 24 px `xs` button on the other
(`:263-270`), so "Open store" floats at the top of a tall row.

**D5 (medium) — empty text nodes take vertical space.** `matchLabel` returns `undefined` for an unmapped
cart match code (`CommerceCarts.vue:33-38`) and the `<span>` is rendered unconditionally
(`:163-165`), producing a blank line in the card. The same applies to `matchState` returning `''`
(`useCommerceLabels.js:129`) rendered at `CommercePanel.vue:461-467`, and to `matchLabel` returning `''`
at `CommercePanel.vue:420-422`.

### 3.3 Inconsistent and duplicated controls

**C1 (high) — links and buttons mixed in one row.** On the order card, "View order" and "Track shipment"
are raw `<a class="text-label-small text-n-blue-11 hover:underline">` (`CommerceOrderItem.vue:163-180`)
while "Send tracking" beside them is `<Button variant="link" size="xs">`
(`:181-187`), which renders at `text-xs` with the Button's own line box
(`button/Button.vue:171-180`). Three sibling actions, two implementations, two type scales, two hit areas.

**C2 (medium) — two tooltip mechanisms on one surface.** `v-tooltip.top` on the order number
(`CommerceOrderItem.vue:95`) and native `title` on the KPI tiles (`CommerceOverview.vue:100, 139`) and the
actions trigger (`CommerceOrderActions.vue:325`).

**C3 (medium) — the disclosure pattern is hand-rolled three times.** `CommerceOverview.vue:170-184`,
`CommerceOverview.vue:206-221` and `CommerceOrderSearch.vue:70-83` are the same button with the same
chevron ternary and the same `aria-expanded`, copied. Inside each, the chevron is a bare `<span>` carrying
`i-lucide-chevron-*` classes rather than the shared `Icon` component used everywhere else in
`components-next`.

**C4 (medium) — the full-width Select hack is repeated.** `class="!w-full [&>select]:w-full"` appears at
`CommercePanel.vue:388`, `CommerceOrderActions.vue:413` and `CommerceOrderActions.vue:425`, each one
fighting `Select.vue:49`'s `w-fit`.

**C5 (medium) — mixed emphasis within one cart action row.** `variant="link"` "View cart" sits next to
`variant="faded"` "Prepare recovery message" and `variant="faded" color="slate"` "Prepare anyway"
(`CommerceCarts.vue:216-249`), so the row has three visual weights and no clear primary.

**C6 (low) — three disclosure visual languages nest.** The surface sits inside an `AccordionItem` whose
toggle is a fluent `add`/`subtract` icon (`AccordionItem.vue:50-51`), containing lucide chevron
disclosures (`CommerceOverview.vue:178-183`), containing `faded`/`ghost` pseudo-tabs
(`CommercePanel.vue:321-340`).

**C7 (low) — the tabs are buttons wearing tab styling.** `role="tablist"`/`role="tab"` with
`aria-selected` but no `aria-controls`, no `tabpanel`, and no arrow-key handling
(`CommercePanel.vue:316-340`). Selection is communicated only by `faded` vs `ghost`
(`:324, 334`).

### 3.4 CTA clarity

**T1 (high) — the copy affordance is invisible.** The order number is the control that copies it
(`CommerceOrderItem.vue:68-69, 94-103`), signalled only by `hover:underline` and a tooltip. There is no
icon, no focus-visible affordance beyond the Button default, and the accessible name is just `#1234`.

**T2 (high) — "Unlink" has no confirmation.** `CommercePanel.vue:432-438` calls `unlink()` directly
(`:276-283`). It is an `xs` ghost ruby button 8 px from "Change" (`:424-439`), which merely toggles a
search panel. Destructive and benign sit adjacent, same size, same variant family.

**T3 (medium) — Refresh is the only recovery control, and it is not a retry.** When `loadError` is set the
panel shows a bare red sentence (`CommercePanel.vue:363-365, 394-396`) with no "Try again". The Refresh
button in the header (`:342-352`) hits a *different*, server-rate-limited endpoint
(`api/commerce.js:59-66`) and can itself answer 429.

**T4 (medium) — the primary action label does not fit its container.** "Prepare recovery message"
(`CommerceCarts.vue:233`) at `size="xs"` inside a bordered card inside a 320 px panel wraps or dominates
the row.

**T5 (low) — the only route out of the surface is not a link.** "Connect a store in Settings → Commerce."
is plain text (`CommercePanel.vue:310`) even though `settings_commerce_index` exists
(`settings/commerce/commerce.routes.js:15`). The admin empty state names a destination and does not go
there.

### 3.5 Empty states

**E1 (high) — the `unavailable` store state renders almost nothing.** `CommercePanel.vue:411` handles
`linked`, `:461` handles everything *except* `unavailable`. For `state === 'unavailable'` the only content
is the amber `panel.error` block (`:399-409`) — and if `panel.error` is absent, the Store view shows the
store picker, an empty `<ul data-test-id="commerce-candidates">` (`:508-512`, condition
`panel.state !== 'linked'` is true) and "Find an order". No sentence states that the store is unavailable,
and nothing offers a next step.

**E2 (medium) — switching to Overview shows a blank area, not a loading state.** The spinner condition is
`isLoading && !panel && !overview` (`CommercePanel.vue:299`). After `setView(VIEWS.OVERVIEW)`
(`:206-210`), `panel` is still truthy from the Store view, so the spinner is suppressed while `overview` is
still `null` — `CommerceOverview` and `CommerceOrderSearch` are both `v-if="overview"`
(`:366, 374`). The agent sees tabs, Refresh, and nothing else.

**E3 (medium) — the carts absence is silent and ambiguous.** `CommerceCarts.vue:119-123` renders nothing
when there are no carts, so "this store has no abandoned carts right now", "carts are disabled for this
store" (`RECOVERY_DISABLED` is filtered out at `:48`) and "no store offers carts" are
indistinguishable.

**E4 (low) — "No orders found" does one job twice.** `OVERVIEW.NO_ORDERS` is both the Last-purchase tile
value (`CommerceOverview.vue:33`) and the Recent-orders empty state (`:186-190`), so the same sentence
appears twice on one screen with two different meanings.

**E5 (low) — empty states are sentences only.** `PANEL.NO_ORDERS` (`CommercePanel.vue:441-447`),
`PANEL.NO_RESULTS` (`:500-505`), `ORDER_SEARCH.NO_RESULTS` (`CommerceOrderSearch.vue:117-123`),
`ACTIONS.NONE` (`CommerceOrderActions.vue:356-358`) and `OVERVIEW.NOT_LINKED`
(`CommerceOverview.vue:158-167`) are bare `text-n-slate-11` paragraphs with no illustration, container or
action — except `NOT_LINKED`, which has a hint but no button, although "Open store" exists 100 px below.

### 3.6 List and table usability

**L1 (medium) — the order list has no header, count, sort or scope statement.** `CommercePanel.vue:441-457`
and `CommerceOverview.vue:192-202` render `CommerceOrderItem` in a loop. Nothing says "5 most recent", and
the dead `ORDER_LIMIT = 5` (`commerceHelper.js:3`) shows the limit was once a frontend concern. In Overview
the orders are cross-store and only the per-card store line (`CommerceOrderItem.vue:115-126`) reveals it.

**L2 (medium) — cards separated only by a hairline.** `border-b border-n-weak last:border-b-0`
(`CommerceOrderItem.vue:90`) with no card container, while candidate rows
(`CommercePanel.vue:516`), store rows (`CommerceOverview.vue:226`) and cart rows
(`CommerceCarts.vue:137`) all use `rounded-lg border border-n-weak px-3 py-2`. Orders — the densest, most
important rows — are the only ones not in a container.

**L3 (medium) — candidate identity truncates to uselessness.** Email and phone are joined with `·` into one
`truncate` span (`CommercePanel.vue:521-531`). At 320 px minus panel padding, minus the row's `px-3`, minus
the "Link" button, a normal email consumes the line and the phone is never seen — on a row whose whole
purpose is picking the right customer.

**L4 (low) — three "status" fields, two visual languages.** Order status and payment status are badges
(`CommerceOrderItem.vue:128-139`); shipment status is plain text in the metadata row beside the date, the
item count and the shipping method (`:155-157`).

**L5 (low) — no non-colour signal on badges, and collisions.** `cancelled` and `refunded` both map to
`bg-n-slate-3 text-n-slate-11` (`CommerceOrderItem.vue:44-45`), identical to `NEUTRAL_BADGE` (`:54`), so
"cancelled", "refunded" and "unrecognised code" are visually the same chip. Payment `refunded` and
`partially_refunded` have labels (`useCommerceLabels.js:28-29`) but no entry in `PAYMENT_CLASSES`
(`CommerceOrderItem.vue:48-53`), so they render neutral too.

**L6 (low) — the secondary text scale is inconsistent inside one card.** The store line is
`text-label-small` (`CommerceOrderItem.vue:117`) and the metadata row below it is `text-body-main`
(`:142`), both `text-n-slate-11`.

### 3.7 Form behaviour (actions dialog)

**F1 (medium) — the amount message truncates.** `Input.vue:146-152` applies `truncate` to the message
paragraph. "Enter an amount above 0 and up to {amount}." (`ACTIONS.FORM.INVALID_AMOUNT`) carries a
formatted currency amount and is the only feedback for a rejected refund amount.

**F2 (medium) — unavailable actions consume the menu.** Each listed-but-disabled action renders a
full-width `faded` button plus its reason line (`CommerceOrderActions.vue:359-383`), so an order with one
possible action among six still shows six rows at equal weight inside a `max-w-md` dialog.

**F3 (medium) — the step machine has no progress or focus handling.** `step` moves
`MENU → FORM → REVIEW → RESULT` (`CommerceOrderActions.vue:46-51`) by swapping the dialog body. There is no
step indicator, no focus move on transition, and the footer buttons change identity in place
(`:502-543`).

**F4 (low) — "Back" and "Close" occupy the same slot at 50 % width each.** `:504-522` with `class="w-full"`
on both footer buttons inside `justify-between` — so a confirm step and a result step have identically
weighted side-by-side buttons.

### 3.8 Loading and error behaviour

**B1 (high) — store switching shows stale data with no indication.** `onStoreChange`
(`CommercePanel.vue:285-288`) calls `loadPanel()`, which sets `isLoading = true` (`:120`), but the spinner
is gated on `!panel` (`:299`). The previous store's linked customer and orders stay on screen, unchanged,
until the new response lands. Mislabelled data for another store is the worst possible failure mode here.

**B2 (medium) — no skeletons anywhere.** The only loading affordances are `Spinner`
(`CommercePanel.vue:302`, `CommerceOrderActions.vue:341, 488`) and the Button `isLoading` state
(`:349, 489`). Layout jumps on every load.

**B3 (medium) — errors are unstyled sentences.** `loadError` and `searchError` render as bare
`text-body-main text-n-ruby-11` paragraphs (`CommercePanel.vue:363, 394, 497`), while
warnings get an amber container (`:399-401`). Errors, the more severe class, are the less
contained one.

**B4 (medium) — the refresh cooldown notice never clears itself.** `refreshNotice`
(`CommercePanel.vue:180, 192-197`) renders as a `text-label-small` line under the header
(`:354-360`) and is reset only by the next refresh attempt — no timer, no dismiss.

**B5 (medium) — closing the dialog mid-run silently abandons the result.** `@close="stopPolling"`
(`CommerceOrderActions.vue:333`) and `finish()` acts only on `succeeded`
(`:243-252`). Closing while `pending` leaves the run in flight server-side, emits no `done`, and the order
card keeps its pre-action state until a live update or a manual Refresh. The `EARLIER_UNRESOLVED` banner
(`:348-355`) is the only trace, and only on reopening.

**B6 (low) — failed and unknown runs do not refresh the panel either.** `finish()` returns early for any
non-success status (`:244`), so a failed status change leaves the card showing the old status with no
prompt to refresh.

**B7 (low) — cart load failures are indistinguishable from "no carts".** `catch { views.value = []; }`
(`CommerceCarts.vue:67-69`) collapses a transport failure into the silent empty state of E3.

### 3.9 Mobile

**M1 (medium) — touch targets are 24 px.** Every control in the panel chrome and on the order card is
`size="xs"` → `h-6` (24 px) or `h-6 w-6` for icon-only (`button/Button.vue:159, 165`): the two view tabs
(`CommercePanel.vue:321-340`), Refresh (`:342-352`), Change / Unlink (`:425-438`), the per-candidate Link
(`:540-545`), "Open store" (`CommerceOverview.vue:263-270`), the cart buttons
(`CommerceCarts.vue:216-249`) and — most consequentially — the ellipsis that is the sole entry point to
every order write action (`CommerceOrderActions.vue:319-328`). Below 768 px this panel is the primary
interaction surface (`ConversationSidebar.vue:54`).

**M2 (medium) — nothing in this surface is responsive.** No `sm:`/`md:` utility appears in any of the six
components. The KPI grid stays `grid-cols-2` (`CommerceOverview.vue:74`); the review `dl` stays
`grid-cols-[auto_1fr]` (`CommerceOrderActions.vue:436`). The panel is simply the same 320 px-designed
column inside a `max-w-sm` overlay.

**M3 (medium) — hover-only content is unreachable on touch.** The two honesty tooltips
(`CommerceOverview.vue:100, 139`) and the copy-number tooltip (`CommerceOrderItem.vue:95`) have no touch
equivalent; the copy action itself still works, its explanation does not.

**M4 (low) — click-outside closes the whole sidebar.** `ConversationSidebar.vue:32-39` closes the panel on
any outside tap under 768 px; `ignore` covers ProseMirror and popovers (`:46-52`) but the action `Dialog`
is teleported to `body` (`Dialog.vue:117`) and is not listed — the sidebar may close behind an open action
dialog.

### 3.10 RTL

**R1 — done well, keep it.** Logical utilities throughout: `ms-auto` (`CommercePanel.vue:348`),
`text-start` (`CommerceOverview.vue:172, 209`; `CommerceOrderItem.vue:97`;
`CommerceOrderSearch.vue:72`), `gap-x-3` (`CommerceOrderItem.vue:142`). No physical `left`/`right`/`pl`/`pr`
in any of the six components. `dir="ltr"` pins the bidi-sensitive values: the order number
(`CommerceOrderItem.vue:98`), the candidate email/phone line (`CommercePanel.vue:524`), the refund amount
input (`CommerceOrderActions.vue:403`) and the order number in the review step (`:446`). Arabic rendering
is covered by `specs/CommercePanel.spec.js:245`.

**R2 (medium) — inherited: the Select arrow lands on the leading edge in RTL.** `Select.vue:54` uses
physical `pr-10` and `:92-93` positions the chevron at `right-0 pr-3`. Under `dir="rtl"` the arrow sits at
the reading-start edge, before the label, instead of the trailing edge. Affects all three Selects on this
surface (`CommercePanel.vue:386`, `CommerceOrderActions.vue:412, 424`). The fix belongs in the
design-system file, not here.

**R3 (low) — concatenated strings carry LTR separators.** `" · "` joins in
`CommercePanel.vue:527-530`, `CommerceOverview.vue:44-52` and the `ORDER_STORE` / `STORE_AND_AGE` /
`ACTIVITY` templates. Mixed-direction segments around a middle dot can order unexpectedly without
isolation marks.

### 3.11 Accessibility

**A1 (high) — the result of a write action is never announced.** `CommerceOrderActions.vue:483-499` swaps
the result text in with no `aria-live`, no `role="status"` and no focus move. A screen-reader user who
confirms a refund gets silence through the entire polling window. The companion toast
(`:245-250`) fires only on success.

**A2 (high) — the copy control's accessible name is the order number.** `CommerceOrderItem.vue:94-103`: the
button's name is `#1234`; "Copy the order number" exists only in `v-tooltip`. There is no `aria-label`.

**A3 (medium) — badges have no field names.** `CommerceOrderItem.vue:128-139` renders two bare spans, so
the card reads "…Shipped Paid…" with no indication of which axis each belongs to, and colour is the only
differentiator (see L5).

**A4 (medium) — incomplete tab semantics.** `role="tablist"` + `role="tab"` + `aria-selected`
(`CommercePanel.vue:316-340`) without `aria-controls`, a `role="tabpanel"` region, `tabindex` management or
arrow-key navigation. Assistive technology is told this is a tab set and then finds none of its structure.

**A5 (medium) — disclosures have no `aria-controls`.** All three toggles set `aria-expanded`
(`CommerceOverview.vue:173, 210`; `CommerceOrderSearch.vue:74`) but the revealed content is a sibling with
no id and no region role.

**A6 (medium) — the KPI grid's `dl` semantics are muddled.** `CommerceOverview.vue:74-156`: the Stores
tile has one `dt` and two `dd`s (`:76-96`), the Orders tile likewise (`:102-124`), and the Spend tile emits
one `dd` per currency (`:144-151`). Secondary values are read as additional definitions of the primary
term.

**A7 (medium) — no focus management on any step or view change.** Switching tabs
(`CommercePanel.vue:206-210`), opening the search (`:430, 473`), moving through the dialog steps
(`CommerceOrderActions.vue:217-226, 195-215, 310-315`) and landing on the result all leave focus where it
was.

**A8 (low) — errors are not associated with their controls.** `searchError`
(`CommercePanel.vue:497-499`) and the per-cart notices (`CommerceCarts.vue:208-214`) are plain paragraphs
with no `role="alert"` and no `aria-describedby` from the input or button that caused them. The dialog's
amount error is the one exception, routed through `Input`'s `message` (`CommerceOrderActions.vue:395-401`).

**A9 (low) — the amber warning colour is load-bearing.** Attention states
(`CommerceOverview.vue:240-245`), stale freshness (`:257`), cooldown (`CommerceCarts.vue:198-200`) and
search notices (`CommerceOrderSearch.vue:112`) are distinguished from normal secondary text by colour
alone — `text-n-amber-11` vs `text-n-slate-11`, same size, same weight, no icon.

**A10 (low) — the accordion header is a `cursor-grab` button.** `AccordionItem.vue:37` makes the section
header simultaneously the expand control and the drag handle, with no keyboard reorder path.

### 3.12 Navigation

**N1 (medium) — section order differs between the two views.** Store view: picker → status → linked
customer → orders → search block → candidates → Find an order → Abandoned carts
(`CommercePanel.vue:380-561`). Overview: KPIs → Recent orders → Stores → Find an order → Abandoned carts
(`:362-378`, `556-561`). "Find an order" lands in a different position relative to its neighbours in each
view, and the Store view's single store-level status has no equivalent to the Overview's per-store rows.

**N2 (low) — collapse state persistence is inconsistent across three mechanisms.** The accordion persists
to UI settings (`ContactPanel.vue:310-313`), the view tab persists to `localStorage`
(`CommercePanel.vue:35-52`), and the three in-panel disclosures are plain local refs that reset on every
remount (`CommerceOverview.vue:22-23`, `CommerceOrderSearch.vue:22`) — including on every conversation
change (`CommercePanel.vue:290`).

**N3 (low) — two order panels can be open at once.** `ContactPanel.vue:291-306` (legacy Shopify) and
`:307-320` (Commerce) are independently gated, so an account mid-migration shows two order sections; the
conflict is acknowledged in copy (`COMMERCE.ERRORS.LEGACY_SHOPIFY_CONNECTED`) but not in layout.

---

## 4. What this surface already does well — must not be lost

1. **Honest, qualified figures.** "{count} visible" rather than a lifetime count
   (`CommerceOverview.vue:109-115`), per-currency spend instead of a converted total
   (`:144-151`), "Showing data from {time}" for a stale copy (`:55-61`), "Couldn't refresh store data right
   now." instead of silently showing old numbers as current (`CommercePanel.vue:399-409`). The intent is
   documented in the component itself (`CommerceOverview.vue:9-10`). Any redesign must keep the qualifier
   attached to the number, and should make it *more* visible, not less (see H4).
2. **Per-store freshness, not one global timestamp.** Each store row carries its own `fetched_at` and its
   own stale flag (`CommerceOverview.vue:54-61, 254-261`), and the panel carries the store-level one
   (`CommercePanel.vue:102-108`). Agents can tell which store is lying.
3. **Lynomia never sends on the agent's behalf.** Both customer-facing flows insert into the reply editor
   and say so: tracking (`CommerceOrderItem.vue:79-85`, "Review and send it yourself.") and cart recovery
   (`CommerceCarts.vue:86-108`, `:13-15`). This is the product's safety story.
4. **Write actions are a reviewed, confirmed, idempotent four-step flow.** Nothing runs from the menu
   (`CommerceOrderActions.vue:15-17`): pick → fill → read the plain-language consequence → confirm with a
   button, never Enter (every button is `type="button"`). A fresh `idempotency_key` per confirmation
   (`:211-213`), the availability `version` sent with the request (`:283`), and a double-submit guard
   (`:273`).
5. **Consequences are spelled out in the store's own terms.** Gateway refund vs store-recorded refund with
   no money moved, cancel with and without restock, status change with the mail warning
   (`CommerceOrderActions.vue:108-140`). Seven variants, all concrete.
6. **Unresolved outcomes are stated, never guessed.** `UNKNOWN` / `UNRESOLVED` / `STILL_PROCESSING`
   (`:142-154`), the success toast only on `succeeded` (`:243-252`), and the `EARLIER_UNRESOLVED` banner on
   reopening (`:348-355`).
7. **Capability honesty in the action menu.** Unsupported actions are hidden; actions that exist but are
   impossible now are shown disabled with the reason (`:80-85, 376-381`, 9 mapped reasons).
8. **Never a raw provider error.** 33 backend codes map to safe sentences with a generic fallback
   (`useCommerceLabels.js:43-78`), asserted by `specs/CommercePanel.spec.js:264`.
9. **URL sanitising before anything is opened or sent.** https-only, credential-free for customer-facing
   links; http tolerated only for the admin deep link built from the connected store URL
   (`commerceHelper.js:8-34`, with the reason documented at `:21-22`).
10. **Live updates that do not disturb the agent.** `silent` refetch keeps the open search and suppresses
    the spinner (`CommercePanel.vue:117-124`), a 500 ms debounce collapses a burst of per-store events into
    one fetch (`:157-172`), events are filtered to this contact and this store, and the open view is re-read
    after a websocket reconnect because events are not replayed (`:173-176`).
11. **Latest-request-wins fetching.** `useAbortableRequest` on stores, panel and overview
    (`CommercePanel.vue:30, 126-128, 141-143, 223-225`) means a slow earlier response can never overwrite a
    newer store's data.
12. **The order number copies itself instead of adding a fourth button.** The reasoning is recorded at
    `CommerceOrderItem.vue:68-69`; the control is the thing the agent wants. Keep the behaviour, fix the
    affordance (T1, A2).
13. **Orders found by number cannot be used to message the wrong customer.** `canSend: false` removes "Send
    tracking" from search results, with the reason in the prop comment
    (`CommerceOrderItem.vue:24-27`, `CommerceOrderSearch.vue:10-11, 129`).
14. **Cross-store identity is always attributed.** Guest vs registered plus how the match was made, per
    store (`CommerceOverview.vue:44-52`), and "Linked by {name}" for manual links
    (`CommercePanel.vue:87-96`).
15. **Dead ends are not offered.** "Open store" is withheld for `needs_reauth` and `provider_unavailable`
    (`CommerceOverview.vue:42, 264`).
16. **The agent's own view choice wins over the default.** `localStorage` preference beats the
    linked-store heuristic (`CommercePanel.vue:228-234`), and a failed `localStorage` never breaks the panel
    (`:37-52`).
17. **Recovery cooldown is enforced in the UI and overridable only by admins.** `coolingDown`
    (`CommerceCarts.vue:59-61`) swaps "Prepare recovery message" for an admin-only "Prepare anyway"
    (`:231-249`).
18. **Every backend code is written out, not interpolated.** `useCommerceLabels.js:3-4` and
    `useCommerceActionLabels.js:3-4` state why: the i18n linter can then verify each key, and unknown codes
    fall back to a generic label rather than rendering a raw enum.
19. **RTL is handled deliberately, not accidentally.** Logical utilities throughout plus targeted
    `dir="ltr"` on the four values that need it (see R1).
20. **Admin-only guidance in the empty state.** Agents are not told to go to a settings page they cannot
    open (`CommercePanel.vue:310`).

---

## 5. Reading notes for whoever redesigns this

- The `data-test-id` attributes on this surface are the contract the 1,401 lines of spec in
  `commerce/specs/` assert against: `commerce-panel`, `commerce-views`, `commerce-view-overview`,
  `commerce-view-store`, `commerce-refresh`, `commerce-refresh-notice`, `commerce-stale`,
  `commerce-match-state`, `commerce-candidates`, `commerce-overview`, `commerce-overview-partial`,
  `commerce-overview-orders`, `commerce-overview-last-purchase`, `commerce-overview-spend`,
  `commerce-overview-not-linked`, `commerce-overview-store`, `commerce-overview-freshness`,
  `commerce-order`, `commerce-order-number`, `commerce-order-store`, `commerce-shipment`,
  `commerce-order-actions`, `commerce-action-dialog`, `commerce-action-unresolved`,
  `commerce-action-<type>`, `commerce-action-amount`, `commerce-action-review`,
  `commerce-action-review-button`, `commerce-action-amount-review`, `commerce-action-consequence`,
  `commerce-action-confirm`, `commerce-action-result`, `commerce-order-search`,
  `commerce-order-search-toggle`, `commerce-order-search-input`, `commerce-order-search-submit`,
  `commerce-order-search-notice`, `commerce-order-search-empty`, `commerce-carts`, `commerce-cart`,
  `commerce-cart-items`, `commerce-cart-sent`, `commerce-cart-cooldown`, `commerce-cart-notice`,
  `commerce-cart-prepare`, `commerce-cart-override`.
- `CommerceOrderItem` renders in three contexts with different capabilities: Store view (actions when the
  store allows, send tracking allowed, no store line), Overview (actions per store, send tracking allowed,
  store line shown), order search (no actions, no send tracking, store line shown). Any change to the card
  has to hold for all three (`CommercePanel.vue:448-457`, `CommerceOverview.vue:192-202`,
  `CommerceOrderSearch.vue:124-130`).
- `CommerceOrderSearch` is mounted twice with different scope and a `:key="storeId"` remount in the Store
  view (`CommercePanel.vue:374-377, 549-553`).
