# Surface audit — Commerce settings (stores)

Read-only audit. This document is the **baseline** for the feature-preservation contract of the
visual/interaction modernization phase. Every assertion is anchored to `file:line` in the current tree.
Nothing here proposes a redesign; it records what exists.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`.

## Files in scope

All paths relative to `app/javascript/dashboard/routes/dashboard/settings/commerce/` unless stated.

| File | Lines | Role |
|---|---|---|
| `commerce.routes.js` | 25 | Route definition, feature flag + permission gating |
| `Index.vue` | 563 | Store list, plan usage, per-store status/capabilities/actions, dialog orchestration |
| `ProviderPicker.vue` | 106 | Step 1 of "Add store": which platform, and how it connects |
| `StoreDialog.vue` | 207 | WooCommerce connect / replace API keys (access chooser + key form) |
| `SallaConnectDialog.vue` | 209 | Salla one-time connection code + polling |
| `ZidConnectDialog.vue` | 82 | Zid OAuth hand-off |
| `ShopifyConnectDialog.vue` | 110 | Shopify OAuth hand-off (domain input, optional write scope) |
| `CartQueue.vue` | 174 | Administrators' abandoned-cart recovery queue |

Supporting files read for gating, labels, chrome and contract:

- `app/javascript/dashboard/routes/dashboard/settings/SettingsWrapper.vue`
- `app/javascript/dashboard/routes/dashboard/settings/SettingsLayout.vue`
- `app/javascript/dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue`
- `app/javascript/dashboard/components-next/dialog/Dialog.vue`
- `app/javascript/dashboard/components-next/button/Button.vue`
- `app/javascript/dashboard/components-next/input/Input.vue`
- `app/javascript/dashboard/components-next/select/Select.vue`
- `app/javascript/dashboard/components-next/spinner/Spinner.vue`
- `app/javascript/dashboard/components-next/EmptyStateLayout.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, `SidebarGroupLeaf.vue`, `provider.js`
- `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js`
- `app/javascript/dashboard/components/widgets/conversation/commerce/useCommerceLabels.js`
- `app/javascript/dashboard/components/widgets/conversation/commerce/commerceHelper.js`
- `app/javascript/dashboard/api/commerce.js`
- `app/javascript/dashboard/featureFlags.js`
- `app/javascript/dashboard/i18n/locale/en/commerce.json`, `ar/commerce.json`, `en/settings.json`
- `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb`
- `custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb`
- `custom/app/views/api/v1/accounts/commerce/stores/_store.json.jbuilder`, `index.json.jbuilder`
- `custom/app/policies/commerce/store_policy.rb`

---

## 1. Routes and primary task

### 1.1 Routes

Exactly one route. `commerce.routes.js:7-25`:

```
/app/accounts/:accountId/settings/commerce      name: settings_commerce_index
  component:   SettingsWrapper (commerce.routes.js:11)  →  Index.vue (commerce.routes.js:16)
  meta.featureFlag:  FEATURE_FLAGS.LYNOMIA_COMMERCE  ('lynomia_commerce')  commerce.routes.js:18
  meta.permissions:  ['administrator']                                      commerce.routes.js:19
```

Registered into the settings route tree at `settings.routes.js:32,78`.

There are **no child routes**. Every sub-flow (provider picker, four connect dialogs, disconnect
confirmation) is a modal rendered by `Index.vue:520-560`. Consequence: no sub-flow is linkable,
bookmarkable, or restorable by browser back.

The route carries **query parameters** as a return channel for OAuth, consumed and then stripped
(`Index.vue:148-161`):

- `?zid=connected`, `?shopify=connected` → success toast
- `?zid_error=<CODE>`, `?shopify_error=<CODE>` → mapped error toast
- `RETURNING_PROVIDERS = ['zid', 'shopify']` (`Index.vue:33`)

`meta.reuseOnQueryChange` is **not** set on this route, so `SettingsWrapper.vue:16-18` keys the
`<keep-alive>` on `route.fullPath` — stripping the query remounts `Index.vue`.

### 1.2 How the surface is reached

| Entry | Evidence | Gate |
|---|---|---|
| Sidebar → Settings → Commerce (`i-lucide-store`) | `Sidebar.vue:828-833` | `SidebarGroupLeaf.vue:32-34` → `Policy` with route `meta.featureFlag` + `meta.permissions` resolved in `sidebar/provider.js:105-127` |
| Command palette "Go to Commerce" (`cmd`/`ctrl`+`K`) | `useGoToCommandHotKeys.js:203-209`; gating `:130-137` | same flag + permission, re-checked per command |
| Direct URL | `commerce.routes.js:10` | route meta |

Sidebar label: `SIDEBAR.COMMERCE` → "Commerce" (`en/settings.json:348`).
Palette label: `COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_COMMERCE` → "Go to Commerce"
(`en/generalSettings.json:197`).

### 1.3 Primary task

**An account administrator connects the account's e-commerce stores, sees for each one whether it is
working and what Lynomia may do with it, and repairs or removes a store that stopped working.**

A second, embedded task shares the page: **triage recent abandoned carts and jump to the linked
contact** (`CartQueue.vue`), rendered only when at least one connected store offers carts
(`Index.vue:518`, `Index.vue:43-45`).

Server-side authority for the whole surface: `Commerce::StorePolicy` — `index?`/`create?`/`update?`/
`destroy?` all require `@account_user.administrator?` (`store_policy.rb:3-17`); both controllers also
require the account feature flag (`stores_controller.rb:50-52`, `carts_controller.rb:25-27`).

### 1.4 The four store statuses (contract-critical)

From `_store.json.jbuilder:7` and `useCommerceLabels.js:109-115`:

| `status` | Label (`COMMERCE.SETTINGS.STATUS.*`) | Dot colour (`Index.vue:35-40`) | What the row offers |
|---|---|---|---|
| `active` | "Active" | `bg-n-teal-9` | capability lines; order-actions toggle; Disable; Replace keys (Woo); Disconnect |
| `disabled` | "Disabled" | `bg-n-slate-9` | Enable (only if `provider_enabled`); Replace keys (Woo); Disconnect |
| `needs_reauth` | "Needs re-authorization" | `bg-n-amber-9` | reauth hint; Reconnect (Zid/Shopify only); Replace keys (Woo); Disconnect |
| `disconnected` | "Disconnected" | `bg-n-ruby-9` | Reconnect (if `provider_enabled`); **no Disconnect, no removal** |

Capability/eligibility flags served per store (`_store.json.jbuilder:2-17`): `provider`,
`provider_enabled`, `name`, `base_url`, `status`, `verified_at`, `realtime_status`
(`active` / `read_only_key` / `null`), `order_actions` (admin opt-in), `order_actions_status`
(`available`, `read_only_key`, `write_access_unverified`, `missing_scope`, `actions_disabled`,
`provider_actions_disabled`, `unsupported`), `abandoned_carts`, `created_at`.

Provider-shape constants in the UI (`Index.vue:29-33`):
`KEY_PROVIDERS = ['woocommerce']`, `REAUTHORIZED_HERE = ['zid','shopify']`,
`RETURNING_PROVIDERS = ['zid','shopify']`. Salla is deliberately **not** re-authorized from here.

---

## 2. Feature parity manifest

Every row below exists today. A redesign that drops a row, or makes it materially harder to find, is a
regression under the contract.

### 2.1 Navigation and entry

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 1 | Sidebar item "Commerce" (`i-lucide-store`) | navigation | `Sidebar.vue:828-833` | `lynomia_commerce` flag + administrator (`provider.js:105-127`) |
| 2 | Command-palette command "Go to Commerce" | shortcut | `useGoToCommandHotKeys.js:203-209` | same, re-checked `:130-137` |
| 3 | `cmd`/`ctrl`+`K` opens the palette that holds #2 | shortcut | `Sidebar.vue:49,978` (`useKbd(['$mod','k'])`) | none |
| 4 | Route `settings_commerce_index` | navigation | `commerce.routes.js:10-21` | flag + administrator |
| 5 | OAuth return query consumed on this route | state | `Index.vue:148-161` | query `zid`/`shopify`/`*_error` present |
| 6 | Scrollable max-w-5xl settings shell | state | `SettingsWrapper.vue:22-33` | none |
| 7 | `<keep-alive>` keyed on `fullPath` (remount on query change) | state | `SettingsWrapper.vue:16-18,27-29` | `reuseOnQueryChange` absent in commerce meta |

### 2.2 Page header

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 8 | Title "Commerce" (`h1`) | state | `Index.vue:272`; rendered `BaseSettingsHeader.vue:55-59` | none |
| 9 | Description paragraph (order-actions promise) | state | `Index.vue:273`; `BaseSettingsHeader.vue:67-72` | none |
| 10 | **Add store** button, `i-lucide-plus`, `size="sm"`, `data-test-id="commerce-add-store"` | primary | `Index.vue:276-283` | administrator (route); `:disabled="limitReached"` (`Index.vue:52-54`) |
| 11 | Header `#count`, `#tabs`, `searchPlaceholder`, `linkText`/`featureName` help link all **unused** | state | available at `BaseSettingsHeader.vue:92-128,73-87`; not passed by `Index.vue:271-285` | n/a |

### 2.3 Plan limit

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 12 | Plan usage line "Stores on your plan: {used} of {limit}" | status | `Index.vue:289-301`, `data-test-id="commerce-store-plan"` | `storeLimit !== null` (`Index.vue:48,74`) |
| 13 | Local `connectedCount` (disconnected excluded) | state | `Index.vue:49-51`; server equivalent `index.json.jbuilder:6` (unused) | — |
| 14 | Limit-reached amber banner | status | `Index.vue:302-316` | `limitReached` (`Index.vue:52-54`) |
| 15 | **View plans** link → `subscription_settings_index` | navigation | `Index.vue:307-315` | shown with #14 |
| 16 | Add store disabled while at limit | state | `Index.vue:280` | `limitReached` |
| 17 | Unlimited plan shows no count at all | state | `Index.vue:290` (`v-if="storeLimit !== null"`) | `store_limit.limit == null` (`index.json.jbuilder:7`) |

### 2.4 Page-level states

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 18 | Loading: `woot-loading-state` with "Loading stores…" | state | `Index.vue:266-269`; `SettingsLayout.vue:28-30` | `isLoading` (`Index.vue:55,78`) |
| 19 | Empty state: circle `i-lucide-store` icon + "No store connected yet." | state | `Index.vue:318-330` | `!stores.length` |
| 20 | Fetch error: toast only (`useAlert(apiErrorMessage(error))`) | state | `Index.vue:75-77`; mapping `useCommerceLabels.js:92-99,43-78` | request failure |
| 21 | Store list container (divided rows, top border) | state | `Index.vue:332` | `stores.length` |
| 22 | Server list order: `created_at` ascending, no client sort | state | `stores_controller.rb:23` | — |
| 23 | Success toasts: "Store connected." / "Store updated." / "Store disconnected." | status | `Index.vue:165,178,181,190,231,250` | per action |

### 2.5 Store row — identity and status

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 24 | Row container, `data-test-id="commerce-store-row"` | state | `Index.vue:333-338` | per store |
| 25 | Avatar tile, **static** `i-lucide-shopping-bag` for every provider | state | `Index.vue:339-344` | none |
| 26 | Store name (truncated, `text-heading-3`) | state | `Index.vue:347-349` | none |
| 27 | Status dot, 4 colours | status | `Index.vue:350-357`, map `:35-40` | `store.status` |
| 28 | Status label, 4 strings | status | `Index.vue:357`; `useCommerceLabels.js:109-115` | `store.status` |
| 29 | Provider display name | state | `Index.vue:364`; `useCommerceLabels.js:101-107` | none |
| 30 | Store base URL, `dir="ltr"`, truncated | state | `Index.vue:360-366` | none |
| 31 | "Verified {relative time}" | status | `Index.vue:367-376`; `commerceHelper.js:56-67` | `store.verified_at` |

### 2.6 Store row — capability disclosure (active stores)

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 32 | "Read-only Commerce: on" | status | `Index.vue:377-383`, `data-test-id="commerce-store-read"` | `status === 'active'` |
| 33 | "Live order updates on" (teal) | status | `Index.vue:384-399`, `data-test-id="commerce-store-realtime"` | `active` + `realtime_status === 'active'` |
| 34 | "Live order updates off: this key is read-only…" (slate) | status | `Index.vue:384-399` | `active` + `realtime_status` truthy, not `active` |
| 35 | "Order actions: on" (teal) | status | `Index.vue:400-412`; `orderActionsText` `:200-206` | `active` + `order_actions_status === 'available'` + `order_actions` |
| 36 | "Order actions: off" (slate) | status | `Index.vue:400-412`; `:200-206` | `available` + not opted in |
| 37 | "Order actions require a Read/Write {provider} API key." | status | `orderActionsText` `:207-211` | `read_only_key` or `write_access_unverified` |
| 38 | "Additional {provider} permissions are required. Reconnect…" | status | `orderActionsText` `:212-215` | `missing_scope` |
| 39 | "Order actions are switched off on this installation." | status | `orderActionsText` `:216-218` | `actions_disabled` / `provider_actions_disabled` |
| 40 | No line at all for other statuses (e.g. `unsupported`) | state | `orderActionsText` `:219-220` returns `''` | default branch |
| 41 | "Refunds and cancellations stay limited to administrators." | status | `Index.vue:413-421` | `active` + `available` |
| 42 | Provider-off amber hint (per provider) | status | `Index.vue:422-428`, `data-test-id="commerce-store-hint"`; texts `:97-114` | `!store.provider_enabled` |
| 43 | Needs-reauth amber hint (per provider) | status | `Index.vue:429-435`, same test id; texts `:97-114` | `provider_enabled` + non-key provider + `needs_reauth` |

### 2.7 Store row — actions

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 44 | **Turn on order actions** / **Turn off order actions** toggle | contextual | `Index.vue:439-455`, `data-test-id="commerce-store-order-actions-toggle"`; `setOrderActions` `:224-237` | `active` + `order_actions_status === 'available'`; admin; server `change_order_actions` (`stores_controller.rb:66-70`) |
| 45 | **Reconnect for order actions** (Shopify/Zid write scope) | contextual | `Index.vue:456-468`, `data-test-id="commerce-store-reconnect-actions"`; `openConnect(provider, store, true)` `:132-140` | `active` + `missing_scope` + provider in `REAUTHORIZED_HERE` |
| 46 | **Disable** | secondary | `Index.vue:469-477`; `setStatus(store,'disabled')` `:185-196` | `status === 'active'` |
| 47 | **Enable** (brand-coloured `faded`, no `color` prop) | secondary | `Index.vue:478-485` | `disabled` + `provider_enabled` |
| 48 | **Replace keys** (WooCommerce, not disconnected) | secondary | `Index.vue:486-497`; `openReplaceKeys` `:169-172` | `usesKeys(store)` (`:88`) |
| 49 | **Reconnect** (WooCommerce, disconnected → same keys dialog) | secondary | `Index.vue:486-497` (label switches on `disconnected`) | `usesKeys(store)` |
| 50 | **Reconnect** (Zid/Shopify app re-authorization) | secondary | `Index.vue:498-505`; `canReconnect` `:90-94` | `provider_enabled` + (`disconnected` or (`needs_reauth` and provider in `REAUTHORIZED_HERE`)) |
| 51 | **Disconnect** (ruby) | destructive | `Index.vue:506-513`; `askDisconnect` `:239-242` | `status !== 'disconnected'` |
| 52 | Per-row busy spinner on #44, #46, #47 | state | `Index.vue:452,475,483` via `busyStoreId` (`:67`) | request in flight |
| 53 | Salla `needs_reauth` has **no** in-app reconnect (hint only) | state | `canReconnect` `:90-94` excludes `salla`; hint `:429-435` | by design |
| 54 | Disconnected row cannot be removed from the list | state | `Index.vue:507` excludes `disconnected` | by design |
| 55 | Store rename supported by API, **no UI control** | state | API `stores_controller.rb:36`; no caller in `Index.vue`/`StoreDialog.vue` | — |

### 2.8 Disconnect confirmation

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 56 | Alert dialog "Disconnect {name}?" | destructive | `Index.vue:544-560` (`type="alert"`) | `askDisconnect` |
| 57 | Description — WooCommerce (credentials + links deleted) | state | `disconnectDescription` `:116-119` → `DISCONNECT_CONFIRM.DESCRIPTION` | `usesKeys(store)` |
| 58 | Description — Salla (reinstall + new code) | state | `providerTexts` `:102` → `DESCRIPTION_APP` | provider `salla` |
| 59 | Description — Zid (access + webhooks + links) | state | `providerTexts` `:107` | provider `zid` |
| 60 | Description — Shopify (uninstall in Shopify admin) | state | `providerTexts` `:112` | provider `shopify` |
| 61 | Confirm button "Disconnect" (ruby, `type="alert"`) | destructive | `Index.vue:555-557`; `Dialog.vue:162-170` | — |
| 62 | Cancel button (default label) | secondary | `Dialog.vue:153-161` | `showCancelButton` default true |
| 63 | Confirm spinner bound to **any** busy store | state | `Index.vue:558` (`!!busyStoreId`) | — |
| 64 | Row flips to `disconnected` locally after success | state | `Index.vue:249` | — |
| 65 | `Esc` / click-outside close | shortcut | `Dialog.vue:101-108,127` | — |

### 2.9 Provider picker (step 1 of Add store)

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 66 | Dialog "Add a store" + description | state | `ProviderPicker.vue:62-63` | `show` prop (`Index.vue:127-129,520-525`) |
| 67 | WooCommerce option (`i-lucide-shopping-bag`) + hint | primary | `ProviderPicker.vue:24-28,70-100` | `providers` includes it (`:46`) |
| 68 | Salla option (`i-lucide-store`) + hint | primary | `ProviderPicker.vue:29-33` | same |
| 69 | Zid option (`i-lucide-store`) + hint | primary | `ProviderPicker.vue:34-38` | same |
| 70 | Shopify option (`i-lucide-shopping-cart`) + hint | primary | `ProviderPicker.vue:39-43` | same |
| 71 | Every platform always listed, even when unavailable | state | `ProviderPicker.vue:22-48` | — |
| 72 | "Not available yet" badge | status | `ProviderPicker.vue:89-94` | `!option.available` |
| 73 | Unavailable option disabled + `cursor-not-allowed opacity-60` | state | `ProviderPicker.vue:74,77` | `!option.available` |
| 74 | Footnote "Platforms marked … aren't offered on this workspace yet." | state | `ProviderPicker.vue:101-103` | `hasUnavailable` (`:49-51`) |
| 75 | Per-option `data-test-id="commerce-provider-<provider>"` | state | `ProviderPicker.vue:76` | — |
| 76 | Cancel; no confirm button | secondary | `ProviderPicker.vue:64-65` | — |
| 77 | Selection closes picker and opens the right connect dialog | state | `Index.vue:142-145,132-140` | — |
| 78 | Enabled providers come from the stores API | state | `Index.vue:73`; `index.json.jbuilder:3` | Super Admin provider switches |

### 2.10 WooCommerce store dialog (connect / replace keys)

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 79 | Title "Add a WooCommerce store" / "Replace API keys" | state | `StoreDialog.vue:108-112`, `isRotation` `:55` | `store` prop |
| 80 | Description (REST API key explanation) | state | `StoreDialog.vue:113` | — |
| 81 | Access chooser fieldset + legend "What should Lynomia be able to do?" | form | `StoreDialog.vue:128-131` | — |
| 82 | "Read/Write (recommended)" option + hint, default | form | `StoreDialog.vue:36-47,132-152`; default `:34` | — |
| 83 | "Read" option + hint | form | `StoreDialog.vue:41-46` | — |
| 84 | Selected option styled `border-n-brand bg-n-alpha-2`, `aria-pressed` | state | `StoreDialog.vue:137-142` | — |
| 85 | Per-option `data-test-id="commerce-store-access-<value>"` | state | `StoreDialog.vue:143` | — |
| 86 | WordPress steps block "Create the key in WordPress" | state | `StoreDialog.vue:154-166`, `data-test-id="commerce-store-steps"` | — |
| 87 | Step 2 permission word tracks the access choice | state | `StoreDialog.vue:163`; `permission` `:49-53` | `access` |
| 88 | Store URL input (`dir="ltr"`, `autocomplete="off"`, placeholder) | form | `StoreDialog.vue:168-174` | `!isRotation` |
| 89 | Display name input (optional) | form | `StoreDialog.vue:175-179` | `!isRotation` |
| 90 | Consumer key input (`type="password"`, `ck_…`) | form | `StoreDialog.vue:181-188` | always |
| 91 | Consumer secret input (`type="password"`, `cs_…`) + "Keys are encrypted and never shown again." | form | `StoreDialog.vue:189-197` | always |
| 92 | Inline error panel | state | `StoreDialog.vue:198-204`, `data-test-id="commerce-store-error"` | request failure (`:81`) |
| 93 | Confirm "Test and connect" / "Test and save" | primary | `StoreDialog.vue:114-118` | `canSave` (`:56-61`) |
| 94 | Confirm disabled until key + secret (+ URL when adding) | state | `StoreDialog.vue:120,56-61` | — |
| 95 | Confirm spinner | state | `StoreDialog.vue:121`, `isSaving` `:33` | — |
| 96 | Cancel | secondary | `StoreDialog.vue:119` | — |
| 97 | `overflow-y-auto` dialog body | state | `StoreDialog.vue:123`; `Dialog.vue:125` | — |
| 98 | All fields + error + access reset on close | state | `StoreDialog.vue:87-102` | — |
| 99 | `Enter` in any field submits (dialog `<form>`) | shortcut | `Dialog.vue:130-133` → `confirm` → `save` | — |
| 100 | New store appended / rotated store replaced in the list, with matching toast | state | `Index.vue:174-183` | — |
| 101 | Key format enforced server-side (`ck_`/`cs_` + 40 hex) | state | `stores_controller.rb:12,72-80` | — |

### 2.11 Salla connect dialog

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 102 | Title + "You never enter or see a Salla token here." | state | `SallaConnectDialog.vue:123-124` | — |
| 103 | Ordered 3 steps (code → install → paste in Salla) | state | `SallaConnectDialog.vue:131-137` | — |
| 104 | **Create connection code** / **Create a new code** button | primary | `SallaConnectDialog.vue:194-206`, `data-test-id="salla-create-code"`; `createCode` `:81-95` | hidden once `status === 'connected'` |
| 105 | Primary button variant flips `solid` → `faded` after first code | state | `SallaConnectDialog.vue:201` | `connection` |
| 106 | Code panel with label | state | `SallaConnectDialog.vue:139-145` | `connection` |
| 107 | Code shown `<code dir="ltr">`, `text-heading-2 tracking-wider` | state | `SallaConnectDialog.vue:147-153`, `data-test-id="salla-connection-code"` | `connection` |
| 108 | **Copy** button + "Code copied." toast | secondary | `SallaConnectDialog.vue:154-161`; `copyCode` `:97-100` | `connection` |
| 109 | "Works once, until {time}" (locale time format) | status | `SallaConnectDialog.vue:163-165`; `expiresAt` `:34-40` | `connection` |
| 110 | "Install the app in Salla" external link | navigation | `SallaConnectDialog.vue:166-176`, `data-test-id="salla-install-link"` | `safeHttpsUrl(install_url)` (`:33`; `commerceHelper.js:8-19`) |
| 111 | Status banner: Waiting | status | `SallaConnectDialog.vue:44,178-185`, `data-test-id="salla-connection-status"` | `status === 'waiting'` |
| 112 | Status banner: Claimed | status | `SallaConnectDialog.vue:45` | `claimed` |
| 113 | Status banner: Connected (teal) | status | `SallaConnectDialog.vue:46,55` | `connected` |
| 114 | Status banner: Conflict — other account (ruby) | status | `SallaConnectDialog.vue:47,56` | `conflict` |
| 115 | Status banner: Expired (amber) | status | `SallaConnectDialog.vue:48,57` | `expired` |
| 116 | Status banner: Plan store limit reached (amber) | status | `SallaConnectDialog.vue:49,58` | `limit_reached` |
| 117 | Inline error panel | state | `SallaConnectDialog.vue:186-192`, `data-test-id="salla-connection-error"` | `createCode`/`poll` failure |
| 118 | 5 s polling of the connection, stops on any terminal state | state | `SallaConnectDialog.vue:21-22,67-79,89` | `connection` created |
| 119 | Polling stopped and code forgotten on close / unmount | state | `SallaConnectDialog.vue:102-115,117` | — |
| 120 | `connected` → parent toast + store list refetch | state | `SallaConnectDialog.vue:74`; `Index.vue:163-167` | — |
| 121 | Close button labelled "Close" (not "Cancel") | secondary | `SallaConnectDialog.vue:126` | — |

### 2.12 Zid connect dialog

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 122 | Title + "You never enter or see a Zid token here." | state | `ZidConnectDialog.vue:54-55` | — |
| 123 | Hand-off explanation paragraph | state | `ZidConnectDialog.vue:62-64` | — |
| 124 | **Connect with Zid** (`i-lucide-external-link`), redirects the browser | primary | `ZidConnectDialog.vue:72-79`, `data-test-id="zid-connect"`; `connect` `:24-35` | — |
| 125 | Only `https` authorize URLs are followed | state | `ZidConnectDialog.vue:29-30`; `commerceHelper.js:8-19` | — |
| 126 | Inline error panel | state | `ZidConnectDialog.vue:65-71`, `data-test-id="zid-connection-error"` | request failure |
| 127 | Button spinner while starting | state | `ZidConnectDialog.vue:77` | `isStarting` |
| 128 | Cancel | secondary | `ZidConnectDialog.vue:57` | — |
| 129 | State reset on close | state | `ZidConnectDialog.vue:37-48` | — |
| 130 | No success handler: result arrives via `?zid=connected` | state | `Index.vue:531` (only `@close`), `:148-161` | — |

### 2.13 Shopify connect dialog

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 131 | Title "Connect with Shopify" | state | `ShopifyConnectDialog.vue:65-69` | `!orderActions` |
| 132 | Title "Reconnect Shopify to enable order actions" | state | `ShopifyConnectDialog.vue:66-67` | `orderActions` |
| 133 | Description — read-only promise | state | `ShopifyConnectDialog.vue:70-77` | `!orderActions` |
| 134 | Description — write access for cancellations/refunds | state | `ShopifyConnectDialog.vue:71-72` | `orderActions` |
| 135 | Store domain input (`dir="ltr"`, placeholder, "Find it in Shopify admin → Settings → Domains.") | form | `ShopifyConnectDialog.vue:81-88` | — |
| 136 | Domain prefilled from the store being reconnected | state | `ShopifyConnectDialog.vue:51`; host from `base_url` at `Index.vue:136` | `shop` prop |
| 137 | Hand-off explanation paragraph | state | `ShopifyConnectDialog.vue:89-91` | — |
| 138 | **Connect with Shopify** (`i-lucide-external-link`) | primary | `ShopifyConnectDialog.vue:99-107`, `data-test-id="shopify-connect"` | `:disabled="!shopDomain.trim()"` (`:103`) |
| 139 | `order_actions: true` sent only when reconnecting for actions | state | `ShopifyConnectDialog.vue:35-38`; `api/commerce.js:31-36` | `orderActions` prop |
| 140 | Only `https` authorize URLs followed | state | `ShopifyConnectDialog.vue:39-40` | — |
| 141 | Inline error panel | state | `ShopifyConnectDialog.vue:92-98`, `data-test-id="shopify-connection-error"` | request failure |
| 142 | Legacy Shopify integration conflict message | state | `useCommerceLabels.js:95-97` | `reason === 'legacy_shopify_integration'` |
| 143 | Button spinner while starting | state | `ShopifyConnectDialog.vue:105` | `isStarting` |
| 144 | Cancel; state reset on close | secondary | `ShopifyConnectDialog.vue:76,47-59` | — |

### 2.14 OAuth return handling

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 145 | "Store connected." toast on `?zid=connected` / `?shopify=connected` | status | `Index.vue:148-161` | query present on mount |
| 146 | Mapped error toast on `?<provider>_error=<CODE>` | status | `Index.vue:159`; 33 codes at `useCommerceLabels.js:43-78` | query present |
| 147 | URL-reason refinement for `INVALID_STORE_URL` (7 reasons) | status | `useCommerceLabels.js:80-94` | `error.reason` |
| 148 | Query stripped with `router.replace` | state | `Index.vue:160` | — |

### 2.15 Abandoned-cart queue (embedded section)

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 149 | Whole section rendered only when a store offers carts | state | `Index.vue:518`; `cartStores` `:43-45`; `abandoned_carts` flag `_store.json.jbuilder:16` | — |
| 150 | Section heading "Abandoned carts" (`h3`) + description | state | `CartQueue.vue:89-97`, `data-test-id="commerce-cart-queue"` | — |
| 151 | Store filter ("All stores" + one option per cart store) | filter | `CartQueue.vue:99,35-41` | stores passed from `Index.vue:518` |
| 152 | Age filter: Last 24 hours / 7 days / 30 days / Any age — default `7d` | filter | `CartQueue.vue:100,42-47`; default `:27` | server `AGES` `carts_controller.rb:10` |
| 153 | Status filter: Abandoned / Recovered / Any — default `abandoned` | filter | `CartQueue.vue:101,48-58`; default `:28` | server `:59` |
| 154 | Linked filter: Linked or not / Linked contact / No linked contact | filter | `CartQueue.vue:102,59-63` | server `:64` |
| 155 | Empty-string filters dropped from the request | state | `CartQueue.vue:72-75` | — |
| 156 | Refetch on every filter change | state | `CartQueue.vue:84` | — |
| 157 | Loading row: `Spinner` + "Reading abandoned carts…" | state | `CartQueue.vue:104-109` | `isLoading` |
| 158 | Inline error line (ruby) | state | `CartQueue.vue:110-112` | `loadError` (`:78`) |
| 159 | Empty line "No abandoned cart matches." | state | `CartQueue.vue:113-115` | `!rows.length` |
| 160 | Cart row list `<ul>/<li>`, `data-test-id="commerce-cart-queue-row"` | state | `CartQueue.vue:116-122` | rows present |
| 161 | Row line 1: localized total + item count | state | `CartQueue.vue:124-135`; `formatAmount` `commerceHelper.js:36-47` | — |
| 162 | Row line 2: store name + provider + relative age | state | `CartQueue.vue:136-144` | — |
| 163 | Row line 3: "Sent {time}" (teal) | status | `CartQueue.vue:145-157` | `row.recovery?.sent_at` |
| 164 | **Open contact** link (contact name or fallback label) | navigation | `CartQueue.vue:159-167`; path built at `:65-66` | `row.contact` present |
| 165 | "No linked contact" when unlinked | status | `CartQueue.vue:168-170` | `!row.contact` |
| 166 | Server prioritization: linked contacts first, then most recent | state | `carts_controller.rb:66-68` | — |
| 167 | Server caps: 50 carts/store, 200 rows total — not surfaced in UI | state | `carts_controller.rb:8-9,20` | — |
| 168 | API `provider` filter exists but is **not** exposed | state | `carts_controller.rb:32`; absent from `CartQueue.vue:25-30` | — |
| 169 | API response `stores` key ignored (options come from the prop) | state | `carts_controller.rb:20` vs `CartQueue.vue:76,35-41` | — |

### 2.16 Permission, flag and keyboard summary

| # | Control / feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 170 | Entire surface administrator-only | state | `commerce.routes.js:19`; `store_policy.rb:3-17` | `administrator` |
| 171 | Entire surface behind `lynomia_commerce` | state | `commerce.routes.js:18`; `stores_controller.rb:50-52`; `carts_controller.rb:25-27` | account feature flag |
| 172 | `Esc` closes any of the five dialogs | shortcut | native `<dialog>`; `Dialog.vue:90,101,127` | dialog open |
| 173 | Click-outside closes the topmost dialog | shortcut | `Dialog.vue:103-108,129` | dialog open |
| 174 | `Enter` submits the WooCommerce key form | shortcut | `Dialog.vue:130-133`; `StoreDialog.vue:124` | StoreDialog open |
| 175 | No bulk action, no multi-select, no row search/sort/pagination anywhere on the surface | bulk | absent from `Index.vue:332-516` | — |
| 176 | No mobile-specific affordance on this surface | state | no `sm:`/`md:` breakpoint class in `Index.vue`, `CartQueue.vue` | — |

**Feature count: 176.**

---

## 3. Visual and interaction audit

### 3.1 Hierarchy

1. **Heading levels skip h2, and store names are not headings.** The page title is `h1`
   (`BaseSettingsHeader.vue:56`), the cart-queue section is `h3` (`CartQueue.vue:91`), and each store
   name is a bare `<span class="text-heading-3">` (`Index.vue:347-349`). There is no `h2` on the page,
   and the store list — the page's main content — contributes nothing to the document outline.
   Severity: medium.
2. **The cart-queue title outranks every store.** `text-heading-2` (`CartQueue.vue:91`) is visually
   larger than the store names at `text-heading-3` (`Index.vue:347`), so the secondary section reads as
   the page's most important block. Severity: medium.
3. **Status severity is carried by an 8 px dot.** "Active" and "Disconnected" share
   `text-label-small text-n-slate-11` (`Index.vue:351`); only `STATUS_DOT` (`Index.vue:35-40`)
   distinguishes them. A broken store does not stand out in a list of healthy ones. Severity: high.
4. **Capability lines are a flat stack of identical small grey text.** Up to six lines render in one
   column with no grouping, label/value pairing or iconography: Read (`:377-383`), realtime
   (`:384-399`), order actions (`:400-412`), admin hint (`:413-421`), provider-off (`:422-428`),
   reauth (`:429-435`). The only differentiation is `text-n-teal-11` vs `text-n-slate-11` vs
   `text-n-amber-11`. Severity: high.
5. **Row avatar is vertically centred against a tall text column.** `items-center` on the left block
   (`Index.vue:339`) centres the 40 px tile against a 5–6 line stack, so the icon floats beside the
   middle of the body text rather than aligning with the store name. Severity: low.
6. **The destructive action is the only coloured control in the row.** `Disconnect` is `color="ruby"`
   (`Index.vue:510`) while every repair action is `variant="faded" color="slate"`
   (`:449-450,463-464,473-474,493-494,502-503`), so the most dangerous control is also the most
   visually prominent. Severity: medium.

### 3.2 Density and spacing

7. **Up to five same-weight buttons in one row.** For an active Shopify store with `missing_scope` the
   cluster is: order-actions toggle, "Reconnect for order actions", "Disable", "Reconnect",
   "Disconnect" (`Index.vue:439-513`), all `size="sm"`, four of them `faded`/`slate`. No overflow menu,
   no grouping. Severity: high.
8. **Row content and actions compete for one flex line.** `flex flex-wrap items-center
   justify-between gap-4` (`Index.vue:336`) with `flex flex-wrap gap-2` for actions (`:438`): at
   medium widths the action cluster wraps to a second and third line with no separator, so it is
   unclear which row the buttons belong to. Severity: high.
9. **Row height varies by 3–4× across statuses.** A `disconnected` row is name + status + URL; an
   `active` row with all capability lines plus hints is six text lines. Scanning the list is hard
   because there is no fixed rhythm (`Index.vue:345-436`). Severity: medium.
10. **Capability lines have no vertical separation from identity.** All of them live in the same
    `flex flex-col gap-1` (`Index.vue:345`), so "Verified 3 hours ago" and "Order actions: off" sit at
    the same indentation and spacing as the store URL. Severity: medium.
11. **Plan block, list and cart queue use three different spacing scales.** `mb-4` on the plan block
    (`Index.vue:291`), `py-4` per row (`:336`), `mt-8` on the cart queue (`:518`), `gap-3` inside it
    (`CartQueue.vue:89`). Severity: low.
12. **Filter row is a flat strip of four unlabelled selects.** `flex flex-wrap gap-2`
    (`CartQueue.vue:98-103`) with no grouping, no "Filters" label, no reset. Severity: medium.

### 3.3 Inconsistent controls and duplicated patterns

13. **Primary CTA placement differs across the five dialogs.** `StoreDialog` uses the `Dialog` footer
    confirm button (`StoreDialog.vue:114-121`), while Salla, Zid and Shopify put their primary action
    **in the body** (`SallaConnectDialog.vue:194-206`, `ZidConnectDialog.vue:72-79`,
    `ShopifyConnectDialog.vue:99-107`) and set `:show-confirm-button="false"`. The result: three
    dialogs show two bottom-area buttons — a body primary and a footer "Cancel"/"Close". Severity: high.
14. **Cancel label is inconsistent.** Salla's footer says "Close"
    (`SallaConnectDialog.vue:126` → `SALLA.CLOSE`); the other three say "Cancel"
    (`FORM.CANCEL` at `ProviderPicker.vue:65`, `ZidConnectDialog.vue:57`,
    `ShopifyConnectDialog.vue:76`, `StoreDialog.vue:119`). Severity: low.
15. **The store list uses `div`s; the cart queue uses `ul`/`li`.** `Index.vue:332-338` vs
    `CartQueue.vue:116-122` — two list implementations on the same page. Severity: medium.
16. **Empty states use two different patterns, neither of them the shared one.** The store list builds
    a bespoke icon-in-circle card (`Index.vue:318-330`); the cart queue is a bare paragraph
    (`CartQueue.vue:113-115`). The repo's shared `EmptyStateLayout.vue` (used by Contacts, Campaigns,
    Help Center, Captain — `EmptyStateLayout.vue:24-67`) is used by neither. Severity: high.
17. **Provider identity is iconographic in the picker and textual in the list.** The picker gives each
    platform an icon (`ProviderPicker.vue:26,31,36,41`); every list row shows the same
    `i-lucide-shopping-bag` (`Index.vue:343`). Severity: medium.
18. **Two providers share an icon in the picker.** Salla and Zid are both `i-lucide-store`
    (`ProviderPicker.vue:31,36`). Severity: low.
19. **"Reconnect" means three different flows behind one label.** Replace WooCommerce keys
    (`Index.vue:486-497`), restart Zid/Shopify OAuth (`:498-505`), and re-authorize with an extra
    scope ("Reconnect for order actions", `:456-468`). Nothing in the row distinguishes them. Severity: medium.
20. **"Enable" is the only row button without an explicit colour.** `Index.vue:478-485` omits
    `color`, so `Button.vue:72-80` defaults to `blue` — a brand-tinted faded button among slate ones.
    Severity: low.
21. **Error panels are duplicated verbatim five times.** Identical markup
    `rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11` at
    `StoreDialog.vue:198-204`, `SallaConnectDialog.vue:186-192`, `ZidConnectDialog.vue:65-71`,
    `ShopifyConnectDialog.vue:92-98`, and a variant at `CartQueue.vue:110-112`. Severity: medium.
22. **Icon-tile markup duplicated.** `grid size-10 shrink-0 place-items-center rounded-xl border
    border-n-strong bg-n-alpha-3` appears at `Index.vue:340-342` and `ProviderPicker.vue:79-82`.
    Severity: low.
23. **`data-test-id` coverage is uneven.** Add store, order-actions toggle and reconnect-for-actions
    have ids (`Index.vue:281,453,466`); Disable, Enable, Replace keys, Reconnect and Disconnect do not
    (`:469-513`). The two amber hints share one id (`:425,432`). Severity: low.
24. **The header's own affordances are bypassed.** No `featureName`/`linkText` (so no help-doc link,
    unlike other settings pages — `BaseSettingsHeader.vue:73-87`), no `#count` slot, no
    `searchPlaceholder`, no `#tabs` (`Index.vue:271-285`). Severity: medium.
25. **Plan usage is computed twice.** The server sends `store_limit.used`
    (`index.json.jbuilder:6`); the client recomputes it from the payload (`Index.vue:49-51`) and only
    reads `limit` (`:74`). Severity: low.
26. **Contact link is a hand-built path string.** `CartQueue.vue:65-66` builds
    `/app/accounts/${id}/contacts/${id}` directly, while `Index.vue:307-312` uses a named route and
    the repo has `frontendURL` (`helper/URLHelper`, imported by `commerce.routes.js:2`). Severity: low.

### 3.4 Unclear CTA

27. **"Add store" gives no reason when disabled.** `:disabled="limitReached"` (`Index.vue:280`) with
    no `title`, tooltip or `aria-describedby`; the explanation is a separate banner above the list
    (`:302-316`). Severity: medium.
28. **Unavailable platforms are disabled buttons with no reason on the control.** `ProviderPicker.vue:74,77`
    plus a badge (`:89-94`) and a footnote (`:101-103`), but the control itself is inert and
    unfocusable, so the reason is unreachable by keyboard. Severity: medium.
29. **The empty state has no call to action.** `Index.vue:318-330` is an icon and one sentence; the
    only way forward is the header button. No "Add store", no "learn more". Severity: high.
30. **"Test and connect" / "Test and save" promise a test with no visible result.** `StoreDialog.vue:114-118`
    — the outcome is a toast on the page behind the dialog (`Index.vue:178-182`), not a verification
    panel. Severity: low.
31. **Salla's primary CTA sits below the status and error panels.** `SallaConnectDialog.vue:194-206`
    renders after `:178-192`, so as status text accumulates the action moves down and can fall below
    the fold in a `max-w-md` dialog. Severity: medium.
32. **No way back from a connect dialog to the picker.** Picking the wrong platform means Cancel, then
    "Add store" again (`Index.vue:142-145`). Severity: medium.
33. **Severity is not encoded in the repair CTA.** A `needs_reauth` store's "Reconnect" — the action
    that restores a broken integration — is styled identically to "Replace keys" on a healthy store
    (`Index.vue:486-505`). Severity: medium.

### 3.5 Overcrowded areas

34. **The active-store row is the densest point on the surface.** Six capability/hint lines
    (`Index.vue:367-435`) beside up to five buttons (`:439-513`) inside one `py-4` row. Severity: high.
35. **`StoreDialog` stacks six blocks in a `max-w-md` modal.** Access fieldset, steps block, two
    optional inputs, two password inputs, error panel (`StoreDialog.vue:127-205`), which is why it
    needs `overflow-y-auto` (`:123`). Severity: medium.
36. **Salla dialog can show five stacked blocks.** Steps, code panel, status banner, error panel,
    primary button (`SallaConnectDialog.vue:130-206`). Severity: medium.

### 3.6 Empty-state quality

37. **Store-list empty state cannot be distinguished from a failed load.** On fetch failure
    `isLoading` is cleared and `stores` stays `[]` (`Index.vue:75-79`), so the user sees "No store
    connected yet." (`:318-330`) with only a transient toast to say otherwise. Severity: high.
38. **No retry affordance after a failed load.** `Index.vue:69-80` has no error state and no reload
    control; recovery is a browser refresh. Severity: high.
39. **Cart-queue empty state is a single grey sentence.** `CartQueue.vue:113-115` — no icon, no
    "clear filters", no hint that the default filters are already narrowing (age `7d` + status
    `abandoned`, `:27-28`). A user can read "No abandoned cart matches." without realising a filter
    caused it. Severity: medium.
40. **The whole cart section vanishes with no explanation.** `v-if="cartStores.length"`
    (`Index.vue:518`) — when no connected store offers carts, nothing says the feature exists.
    Severity: medium.
41. **Empty state carries no onboarding content.** No mention of the four supported platforms, no
    link to docs, in a surface whose entire purpose is a first-time connection (`Index.vue:318-330`).
    Severity: medium.

### 3.7 List / table usability

42. **No search, sort, filter or pagination over stores.** Server order is `created_at` ascending
    (`stores_controller.rb:23`); the client renders it unchanged (`Index.vue:334`). Broken stores sort
    wherever they were created. Severity: medium.
43. **No grouping by status.** `needs_reauth` and `disconnected` stores are interleaved with healthy
    ones (`Index.vue:332-338`). Severity: medium.
44. **No bulk action and no multi-select.** Disabling or disconnecting several stores is one row at a
    time (`Index.vue:439-513`). Severity: low.
45. **Row is not a single hit target and has no detail view.** The row is a `div` with no click
    handler, link or focus style (`Index.vue:333-338`); everything must be done through the inline
    buttons. Severity: low.
46. **Base URL truncation can hide the identifying part.** `truncate` on the URL span
    (`Index.vue:365`) inside a `min-w-0` column; with two stores on the same host the distinguishing
    path is what gets cut. No `title` attribute. Severity: medium.
47. **Disconnected rows accumulate forever.** No delete/archive once `status === 'disconnected'`
    (`Index.vue:507`); they keep taking list space while contributing nothing. Severity: medium.
48. **Cart rows are capped silently.** 50 per store, 200 total (`carts_controller.rb:8-9,20`) with no
    "showing first 200" notice and no pagination in `CartQueue.vue:116-172`. Severity: medium.
49. **Cart rows have no stable visual anchor.** Three lines of text at two type sizes with no store
    badge, no avatar and no amount alignment (`CartQueue.vue:123-158`); amounts cannot be compared
    down the column. Severity: medium.
50. **Cart row's only action is a text link at the row end.** `CartQueue.vue:159-167` — no "prepare
    recovery", no copy, no secondary action, and the link's label is the contact's name, so the action
    is not identifiable by its label. Severity: medium.

### 3.8 Mobile behaviour

51. **No breakpoint handling anywhere on the surface.** Neither `Index.vue` nor `CartQueue.vue`
    contains a single `sm:`/`md:`/`lg:` class. The only responsive behaviour is `flex-wrap`
    (`Index.vue:336,346,438`; `CartQueue.vue:98,120`). Severity: high.
52. **Five `size="sm"` buttons wrap into three or four lines at 375 px.** `Index.vue:438-513`
    (`h-8 px-3` each, `Button.vue:160`), under a text block that already wraps. Severity: high.
53. **Fixed 24 px side gutters on small screens.** `px-6` with no breakpoint on the settings shell
    (`SettingsWrapper.vue:23`), leaving ~327 px of content width on a 375 px device. Severity: medium.
54. **Four selects wrap unpredictably.** `CartQueue.vue:98-103` — each `Select` is `w-fit`
    (`Select.vue:49`) sized by its longest option, so the filter strip reflows into 2–4 ragged rows.
    Severity: medium.
55. **`max-w-md` dialogs with `p-6` are cramped on phones.** `Dialog.vue:121-132`; `StoreDialog`'s six
    blocks then scroll inside the modal (`StoreDialog.vue:123`). Severity: medium.
56. **Dialog footer buttons are both full width and equal weight.** `Dialog.vue:149-170` — "Cancel"
    and "Disconnect" are the same size side by side in the destructive dialog, which is the worst case
    for a thumb. Severity: medium.
57. **Header action row reverses on mobile.** `flex-row-reverse sm:flex-row` when no `#tabs` slot
    (`BaseSettingsHeader.vue:121`); harmless with one action today, but it means the header's action
    order is breakpoint-dependent. Severity: low.

### 3.9 RTL behaviour

58. **The cart-queue selects are physically positioned.** `Select.vue:54` uses `pr-10` and `:93` uses
    `right-0` — physical, not logical. In RTL the chevron stays on the right where the text begins, so
    the arrow overlaps the option label. This is the only filter control on the surface, and all four
    instances are affected (`CartQueue.vue:99-102`). Severity: high.
59. **`dir="ltr"` is applied to a span that also holds a translated provider name.**
    `Index.vue:360-366` wraps both `providerName(store.provider)` (Arabic "سلة", "زد" in
    `ar/commerce.json`) and `base_url` in one LTR span. The translated name is forced into LTR
    alongside the URL. Severity: medium.
60. **LTR-forced truncation in an RTL page.** The URL's `truncate` (`Index.vue:365`) clips at the LTR
    end inside an RTL layout, so the ellipsis appears on the side the RTL reader scans last.
    Severity: low.
61. **Status dot has no logical spacing concern but the row has no RTL verification hooks.** The row
    relies entirely on `flex` + `gap` (`Index.vue:336,339,346,351`), which is direction-safe; worth
    recording as the part that works. Severity: n/a (positive).
62. **Correctly handled, must not regress:** `ms-4 list-decimal` on the WordPress steps
    (`StoreDialog.vue:161`), `ps-5` on the Salla steps (`SallaConnectDialog.vue:132`), `text-start` on
    picker options (`ProviderPicker.vue:74`) and access options (`StoreDialog.vue:136`), and the
    `TeleportWithDirection` wrapper that keeps teleported dialogs in the account's direction
    (`Dialog.vue:118`; `TeleportWithDirection.vue:17-27`).
63. **Arabic coverage is complete for this surface** — all 21 `COMMERCE.SETTINGS` groups including
    `CART_QUEUE`, `PLAN`, `SHOPIFY` exist in `ar/commerce.json`, so RTL is a real, shipped path and
    not a theoretical one.

### 3.10 Loading and error behaviour

64. **One `busyStoreId` drives several unrelated buttons.** `Index.vue:67` is a single ref; both the
    order-actions toggle (`:452`) and Disable (`:475`) / Enable (`:483`) bind
    `busyStoreId === store.id`. Clicking "Disable" therefore puts a spinner on "Turn on order actions"
    in the same row. Severity: high.
65. **Nothing is disabled during a row request.** "Replace keys" (`:486-497`), "Reconnect"
    (`:498-505`) and "Disconnect" (`:506-513`) stay clickable while `setStatus`/`setOrderActions` is in
    flight (`:185-196,224-237`) — double submits and interleaved writes are reachable. Severity: high.
66. **The disconnect dialog shows a spinner for any busy store.** `:is-loading="!!busyStoreId"`
    (`Index.vue:558`) — toggling store A's status makes store B's confirm button spin before the user
    has confirmed anything. Severity: medium.
67. **Store-list load failure has no inline surface.** Toast only (`Index.vue:75-77`), then the empty
    state (see §3.6 #37). Severity: high.
68. **Returning from OAuth fetches the store list twice.** `onMounted` runs `showAuthorizationResult`
    then `fetchStores` (`Index.vue:259-262`); `router.replace({query})` (`:160`) changes
    `route.fullPath`, which is the `<keep-alive>` key (`SettingsWrapper.vue:16-18,27-29`) because the
    commerce route does not set `reuseOnQueryChange` — so the component remounts and fetches again.
    Severity: medium.
69. **The cart queue has no request cancellation.** `CartQueue.vue:68-82` fires on every filter change
    (`:84`) with no `AbortController` and no sequence guard, so a slow earlier response can overwrite a
    newer one. The repo has a shared abortable-request composable used by the conversation Commerce
    panel. Severity: high.
70. **No debounce or in-flight guard on the filters.** Four selects changed quickly issue four
    overlapping requests (`CartQueue.vue:84`), each of which fans out to every store server-side
    (`carts_controller.rb:18`). Severity: medium.
71. **Loading replaces the cart list instead of overlaying it.** `v-if="isLoading"` …
    `v-else-if`/`v-else` chain (`CartQueue.vue:104-116`) — the rows disappear on every filter change,
    so the list flickers to a one-line spinner and back. Severity: medium.
72. **Page loading state is an unstyled full-body spinner.** `woot-loading-state`
    (`SettingsLayout.vue:28-30`) — no skeleton of the row layout, so the page jumps from one centred
    spinner to a dense list. Severity: low.
73. **Salla polling has no visible progress or timeout.** `setInterval` every 5 s
    (`SallaConnectDialog.vue:21,89`) with the status banner as the only feedback; it keeps polling
    while the tab is hidden and gives no "still waiting" or "give up" affordance. Severity: medium.
74. **A failed poll silently ends polling.** `SallaConnectDialog.vue:75-78` sets an error and calls
    `stopPolling()`; the user must notice the error panel and press "Create a new code". Severity: medium.
75. **Error text is generic when the code is unmapped.** `useCommerceLabels.js:78` falls back to
    `COMMERCE.ERRORS.GENERIC` for any unknown code — correct, but it means a connect failure can
    surface with no actionable detail. Severity: low.

### 3.11 Form behaviour

76. **`Enter` does not submit the three OAuth dialogs.** `Button.vue:238` renders a bare `<button>`
    with no `type`, so inside `Dialog`'s `<form>` (`Dialog.vue:130`) it defaults to `submit`. The
    form's handler is `@submit.prevent="confirm"` which emits `confirm` — and Salla, Zid and Shopify
    bind no `@confirm` (`Index.vue:526-537`). Pressing `Enter` in the Shopify domain field therefore
    does nothing; only the click handler works (`ShopifyConnectDialog.vue:107`). Severity: high.
77. **Input hint text is truncated to one line.** `Input.vue:146-152` applies `truncate`, so
    "Keys are encrypted and never shown again." (`StoreDialog.vue:196`) and
    "Find it in Shopify admin → Settings → Domains." (`ShopifyConnectDialog.vue:87`) clip in a
    `max-w-md` dialog. Severity: medium.
78. **Click-outside discards typed credentials with no confirmation.** `Dialog.vue:103-108,129` closes
    on an outside click, and `StoreDialog.vue:87-102` then clears every field. Severity: high.
79. **No field-level validation or error attribution.** `StoreDialog` sends on confirm and renders one
    whole-form error panel (`:198-204`); the server's `INVALID_STORE_URL` reason (`useCommerceLabels.js:80-94`)
    is never attached to the URL input. No `messageType="error"` is used anywhere. Severity: medium.
80. **The access chooser is a pair of `aria-pressed` buttons, not a radio group.**
    `StoreDialog.vue:132-152` inside a `fieldset`/`legend` (`:128-131`). It is a single-select, so it
    should expose radio semantics; `aria-pressed` announces each as an independent toggle, and there is
    no arrow-key navigation. Severity: medium.
81. **No `autocomplete`/`name` semantics for the secret fields beyond `off`.**
    `StoreDialog.vue:183,191` use `autocomplete="off"` with `type="password"` and no visibility
    toggle, so a mistyped 40-char key cannot be checked before submitting. Severity: low.
82. **"Display name (optional)" is the only field marked optional, and there are no required markers.**
    `en/commerce.json` `FORM.NAME`; `StoreDialog.vue:168-197` — requiredness is only expressed by the
    disabled confirm button (`:120,56-61`). Severity: low.
83. **The Shopify domain is not validated client-side.** `:disabled="!shopDomain.trim()"`
    (`ShopifyConnectDialog.vue:103`) only checks non-emptiness; a wrong domain costs a round trip and
    returns a mapped `shopify_domain` URL error (`useCommerceLabels.js:88`). Severity: low.

### 3.12 Accessibility

84. **No dialog has an accessible name.** `Dialog.vue:119-128` sets no `aria-labelledby` /
    `aria-label`; the title is an `h3` inside the form (`:136-139`). All five commerce dialogs are
    announced as an unnamed dialog. Severity: high.
85. **Dialog headings are `h3` with no page context.** `Dialog.vue:137` — inside a page whose only
    other headings are `h1` and the cart queue's `h3`. Severity: low.
86. **Status changes are never announced.** No `role="status"`, `role="alert"` or `aria-live` on the
    Salla polling banner (`SallaConnectDialog.vue:178-185`), on any of the four inline error panels
    (`StoreDialog.vue:198-204`, `SallaConnectDialog.vue:186-192`, `ZidConnectDialog.vue:65-71`,
    `ShopifyConnectDialog.vue:92-98`), or on the cart-queue error/empty/loading lines
    (`CartQueue.vue:104-115`). A screen-reader user polling for a Salla connection hears nothing.
    Severity: high.
87. **The four cart-queue filters are unlabelled.** `Select.vue:36-39,53` supports `ariaLabel`, and
    `CartQueue.vue:99-102` passes none and renders no `<label>`. Four unnamed comboboxes. Severity: high.
88. **The status dot is not hidden from assistive tech.** `Index.vue:352-356` is a decorative
    `<span>` with no `aria-hidden="true"`, adjacent to the text label it duplicates. Severity: low.
89. **The store list has no list semantics.** `Index.vue:332-338` is nested `div`s, so there is no
    item count and no list navigation; the cart queue does this correctly (`CartQueue.vue:116-122`).
    Severity: medium.
90. **Disabled provider options are unreachable by keyboard.** `ProviderPicker.vue:74,77` — a
    `disabled` `<button>` is removed from the tab order, so the "Not available yet" badge and the
    footnote explaining it (`:89-103`) are never associated with the control. Severity: medium.
91. **Disabled "Add store" has no programmatic reason.** `Index.vue:280` — no `aria-describedby`
    pointing at the limit banner (`:302-316`). Severity: medium.
92. **Row buttons have no accessible context.** "Disable", "Reconnect", "Disconnect"
    (`Index.vue:469-513`) carry no `aria-label` naming the store, so a screen reader hears five
    identical button labels per row with nothing tying them to a store. Severity: high.
93. **Capability state is text-only with colour as the sole emphasis.** `Index.vue:386-391,403-408`
    switch between `text-n-teal-11` and `text-n-slate-11`; the string itself does carry the state
    ("on"/"off"), which is the correct fallback — record as a thing that works. Severity: n/a (positive).
94. **The "Open contact" link's accessible name is the contact's name.** `CartQueue.vue:159-167` — out
    of context a screen-reader link list reads a column of person names with no indication they are
    cart rows. Severity: medium.
95. **No skip/landmark structure inside the body.** `SettingsLayout.vue:26-40` provides a single
    `<main>`; the store list and the cart queue are not sections with accessible names (`CartQueue.vue:89`
    is a `<section>` but has no `aria-labelledby`). Severity: low.
96. **Focus is not managed after destructive actions.** `disconnect()` closes the dialog
    (`Index.vue:255`) without returning focus to a defined element; the row's Disconnect button no
    longer exists (`:507`). Severity: medium.
97. **`Spinner` has no accessible text.** `Spinner.vue:11-24` is a bare `<svg class="animate-spin">`
    with no `role`/`aria-label`; `CartQueue.vue:104-109` does pair it with a visible text label, which
    mitigates it there. Severity: low.

### 3.13 Navigation

98. **No sub-flow is addressable.** Picker and all four connect dialogs are local booleans
    (`Index.vue:56-59,63`); a half-finished connection cannot be linked, resumed or reached by back.
    Severity: medium.
99. **The browser back button does not close dialogs.** They are native `<dialog showModal()>` with no
    history integration (`Dialog.vue:88-97`). Severity: low.
100. **Two outbound links leave the surface, with different treatments.** "View plans" is a styled
     in-app `router-link` (`Index.vue:307-315`); "Install the app in Salla" is an external
     `target="_blank"` text link with no external-link icon (`SallaConnectDialog.vue:166-176`),
     whereas the Zid/Shopify buttons that also leave the app do carry `i-lucide-external-link`
     (`ZidConnectDialog.vue:74`, `ShopifyConnectDialog.vue:101`). Severity: low.
101. **No contextual link from a store to where its data appears.** Nothing links a connected store to
     the conversation Commerce panel, to contacts with that store's links, or to the audience filter
     that uses commerce fields (`api/commerce.js:39-41`). Severity: medium.
102. **The cart queue links out but nothing links in.** `CartQueue.vue:159-167` reaches a contact, but
     no conversation or contact surface links back to this queue. Severity: low.

---

## 4. What this surface already does well — must not be lost

1. **Honest, specific status language.** Four store statuses with distinct, non-euphemistic labels
   ("Needs re-authorization", not "Attention") — `useCommerceLabels.js:109-115`.
2. **Capability disclosure instead of a boolean.** The row states exactly what Lynomia can do with
   each store — read, live updates, order actions — and when it cannot, *why*: read-only key, missing
   scope, switched off at the installation (`Index.vue:377-421`; `orderActionsText` `:200-222`).
   This is the strongest thing on the surface and the hardest to rebuild.
3. **Every blocked state names its remedy.** `ORDER_ACTIONS_READ_ONLY_KEY` ("require a Read/Write
   {provider} API key"), `ORDER_ACTIONS_MISSING_SCOPE` ("Reconnect {provider} to enable order
   actions"), `REALTIME.READ_ONLY_KEY` ("Replace it with a Read/Write key"), and the provider-specific
   reauth hints (`Index.vue:429-435`; `en/commerce.json` `CAPABILITIES`, `REALTIME`, `*.REAUTH_HINT`).
4. **The remedy is also a button, exactly where it applies.** "Reconnect for order actions" appears
   only for `missing_scope` on a provider that can be re-authorized here (`Index.vue:456-468`), and it
   requests the extra scope rather than a plain re-auth (`:467` → `ShopifyConnectDialog.vue:35-38`).
5. **Platform-shape honesty.** Salla is excluded from in-app reconnect because it genuinely cannot be
   re-authorized from Lynomia; the hint sends the admin to the Salla dashboard instead of offering a
   button that would fail (`Index.vue:90-94,429-435`; `SALLA.REAUTH_HINT`).
6. **Every platform is listed, including the ones this installation does not offer.** The merchant
   finds their platform and learns it is not available yet, instead of silently not seeing it
   (`ProviderPicker.vue:8-10,22-48,89-103`).
7. **Each platform's hint says *how* it connects before the user commits.** Key vs app
   authorization, "No keys to copy" (`en/commerce.json` `PICKER.*_HINT`).
8. **Credentials never round-trip.** Write-only keys (`_store.json.jbuilder:1`), `type="password"`
   inputs, fields cleared on close (`StoreDialog.vue:87-102`), explicit "You never enter or see a
   {provider} token here" in all three app-provider dialogs
   (`SallaConnectDialog.vue:124`, `ZidConnectDialog.vue:55`, `ShopifyConnectDialog.vue:72`).
9. **`https`-only redirect and link guards.** `safeHttpsUrl` is applied before every hand-off and
   before rendering the Salla install link (`commerceHelper.js:8-19`; `ZidConnectDialog.vue:29-30`,
   `ShopifyConnectDialog.vue:39-40`, `SallaConnectDialog.vue:33`), with specs asserting it.
10. **The access chooser teaches the key before asking for it.** Choosing Read vs Read/Write rewrites
    the WordPress steps so the admin creates a key with the right permission the first time, and the
    copy is explicit that the choice is guidance and WooCommerce decides
    (`StoreDialog.vue:9-12,36-53,154-166`).
11. **Per-provider disconnect consequences.** Four different descriptions, each stating what is
    deleted, what is untouched in the store, and how to reconnect
    (`Index.vue:97-119`; `DISCONNECT_CONFIRM.DESCRIPTION`, `DESCRIPTION_APP`,
    `ZID.DISCONNECT_DESCRIPTION`, `SHOPIFY.DISCONNECT_DESCRIPTION`).
12. **Disconnect is confirmed, named and typed.** `type="alert"` dialog titled with the store's name
    (`Index.vue:544-560`).
13. **Disabling is separated from disconnecting.** A store can be paused without destroying its
    credentials and customer links (`Index.vue:469-485`).
14. **Order actions are opt-in per store and the limit is stated.** "Refunds and cancellations stay
    limited to administrators." is shown next to the toggle, not buried in docs (`Index.vue:413-421`).
15. **Plan limits are explained with a route out.** Usage line, amber banner with the number, and a
    "View plans" link to subscription settings; "Add store" is disabled rather than failing on submit
    (`Index.vue:289-316,280`).
16. **Salla's limit case is handled in the connect flow too.** `SALLA.STATUS.LIMIT_REACHED` explains
    the store was not connected and what to do (`SallaConnectDialog.vue:49`).
17. **The Salla flow is a real three-step wizard with live feedback.** Numbered steps, a copyable
    one-time code with its expiry, an official install link, six distinct polled states, and automatic
    refresh of the list on success (`SallaConnectDialog.vue:131-206`; `Index.vue:163-167`).
18. **OAuth results are surfaced on return and the URL is cleaned up.** Success and mapped error codes
    from `?zid=`/`?shopify=` are shown as toasts, then stripped from the query
    (`Index.vue:148-161`).
19. **Rich error vocabulary.** 33 commerce error codes and 7 URL reasons mapped to human strings, with
    a legacy-Shopify-integration special case (`useCommerceLabels.js:43-99`).
20. **Verification recency is shown.** "Verified {relative time}" in the viewer's locale
    (`Index.vue:367-376`; `commerceHelper.js:56-67`).
21. **The URL is forced LTR so it is readable in Arabic.** `dir="ltr"` on the identity line
    (`Index.vue:362`) — the intent is right even though it over-reaches onto the provider name.
22. **The cart queue is deliberately a triage list, not a CRM.** No contact details, no recovery
    links, no scores; it states that nothing is sent automatically and that messages are prepared from
    the conversation (`CART_QUEUE.DESCRIPTION`; `CartQueue.vue:14-16`; `carts_controller.rb:1-4`).
23. **Cart prioritization is deterministic and useful.** Linked contacts first, then most recently
    updated (`carts_controller.rb:66-68`).
24. **Cart filters have sensible defaults.** Last 7 days + Abandoned (`CartQueue.vue:27-28`) so the
    list opens on the actionable set.
25. **Money and time are locale-formatted with safe fallbacks.** `formatAmount` falls back to
    `"{amount} {currency}"` on an unknown currency rather than throwing
    (`commerceHelper.js:36-47`; `CartQueue.vue:126-135`).
26. **Logical Tailwind properties in the places that were thought about.** `ms-4`, `ps-5`,
    `text-start` (`StoreDialog.vue:136,161`; `SallaConnectDialog.vue:132`; `ProviderPicker.vue:74`).
27. **Dialogs keep the account's direction when teleported.** `TeleportWithDirection`
    (`Dialog.vue:118`).
28. **Complete Arabic translation for the surface**, including the cart queue and plan strings
    (`ar/commerce.json`).
29. **Gating is declared once and reused everywhere.** Route meta drives the sidebar item, the command
    palette and direct navigation (`commerce.routes.js:17-20`; `sidebar/provider.js:105-127`;
    `useGoToCommandHotKeys.js:130-137`), and the server enforces the same rule
    (`store_policy.rb:3-17`).
30. **Reachable by keyboard from anywhere.** `cmd`/`ctrl`+`K` → "Go to Commerce"
    (`useGoToCommandHotKeys.js:203-209`).
31. **Test hooks on the load-bearing controls.** `commerce-add-store`, `commerce-store-row`,
    `commerce-store-plan`, `commerce-store-read`, `commerce-store-realtime`,
    `commerce-store-order-actions`, `commerce-store-order-actions-toggle`,
    `commerce-store-reconnect-actions`, `commerce-store-hint`, `commerce-provider-<provider>`,
    `commerce-store-access-<value>`, `commerce-store-steps`, `commerce-store-error`,
    `salla-connection-code`, `salla-install-link`, `salla-connection-status`,
    `salla-connection-error`, `salla-create-code`, `zid-connect`, `zid-connection-error`,
    `shopify-connect`, `shopify-connection-error`, `commerce-cart-queue`,
    `commerce-cart-queue-row` — a redesign must keep these or update the five spec files under
    `specs/`.
32. **Polling and timers are cleaned up.** `stopPolling` on close and `onBeforeUnmount`
    (`SallaConnectDialog.vue:102-117`).

---

## 5. Reading notes for whoever redesigns this

- The row's value is its **capability disclosure** (§4.2–4.4). Any redesign that compresses the row
  into "name + status + menu" must find another home for all six lines and the six
  `order_actions_status` variants, or it breaks the contract.
- The five dialogs are **four different flows**, not one form with variants: key entry (WooCommerce),
  code + polling (Salla), straight OAuth (Zid), OAuth with a domain and an optional extra scope
  (Shopify). Their only shared chrome is `Dialog`.
- `Index.vue` owns all dialog state and all mutations; `CartQueue.vue` owns its own fetching and is
  the only component on the surface that fetches independently of the parent.
- The surface has **no tabs, no search, no sort, no pagination, no bulk actions and no mobile
  branches** today. Those are absences to design into, not features to preserve.
- `busyStoreId` (`Index.vue:67`) is a single shared lock for the whole list; several findings in
  §3.10 trace back to it.
