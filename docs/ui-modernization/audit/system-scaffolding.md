# Audit — Page shells and headers (system scaffolding)

**Area:** page shells, page wrappers, and page headers across the dashboard, with an exhaustive
per-settings-page matrix of *which shell* and *which header* each page uses.

**Status:** baseline record of what exists in the code today (Lynomia Chat, Chatwoot 4.18 fork).
Read-only audit — no application file was changed. Every claim below cites `file:line`.

**Method:** read every file named `*Layout.vue` / `*Wrapper.vue` / `*Header.vue` under
`app/javascript/dashboard`, then every `*.routes.js` under
`app/javascript/dashboard/routes/dashboard/settings/`, then every page component those routes name.
There is no `enterprise/` Vue overlay in this repo (`find enterprise -name "*.vue"` returns nothing),
so the OSS tree is the whole story for this area.

Paths in tables are relative to `app/javascript/dashboard/` unless stated otherwise.

---

## 1. The shell stack, top to bottom

Settings pages are nested three or four levels deep. Nothing in the stack is optional-by-config; the
level is chosen by which component the route mounts.

| Level | Component | What it contributes |
|---|---|---|
| 0 | `routes/dashboard/Dashboard.vue:131-177` | `div.flex.flex-grow.overflow-hidden.text-n-slate-12` + `NextSidebar` + `main.flex.flex-1.h-full.w-full.min-h-0.px-0.overflow-hidden.bg-n-surface-1`. This `main` is the scroll/overflow boundary every page shell sits inside. |
| 1 | `routes/dashboard/settings/SettingsWrapper.vue` **or** `routes/dashboard/settings/Wrapper.vue` **or** `routes/dashboard/settings/reports/components/ReportsWrapper.vue` | route-level column: page padding, max width, `keep-alive`, `router-view` |
| 2 | `routes/dashboard/settings/SettingsLayout.vue` | per-page `header` / `preBody` / `loading` / `body` slot frame + loading and empty states |
| 3 | `routes/dashboard/settings/components/BaseSettingsHeader.vue` | the header anatomy (title, description, help link, meta, search, tabs, count, actions, back) |
| 3' | `routes/dashboard/settings/SettingsSubPageHeader.vue`, `routes/dashboard/settings/SettingsHeader.vue`, `reports/components/ReportHeader.vue`, `data/components/ImportDetailHeader.vue`, `billing/components/BillingHeader.vue` | alternative / older headers |
| 4 | `routes/dashboard/settings/account/components/SectionLayout.vue`, `components-next/Settings/SettingsFieldSection.vue`, `components-next/Settings/SettingsToggleSection.vue`, `components-next/Settings/SettingsAccordion.vue` | in-page section headings |

---

## 2. Route-level shells (level 1)

### 2.1 `SettingsWrapper.vue` — the main settings column

`routes/dashboard/settings/SettingsWrapper.vue`

| Aspect | Value | Evidence |
|---|---|---|
| Props | `keepAlive: Boolean = true` — **the only declared prop** | `SettingsWrapper.vue:5-10` |
| Slots | none (renders `router-view` directly) | `SettingsWrapper.vue:26-31` |
| Outer classes | `flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1` | `SettingsWrapper.vue:22-24` |
| Inner classes | `flex items-start w-full max-w-5xl mx-auto` | `SettingsWrapper.vue:25` |
| Max width | `max-w-5xl` (64rem / 1024px) | `SettingsWrapper.vue:25` |
| Gutter | `px-6` (1.5rem), vertical `pt-4` / `pb-8` | `SettingsWrapper.vue:23` |
| Scroll owner | this element (`overflow-auto`) | `SettingsWrapper.vue:23` |
| Remount key | `route.meta.reuseOnQueryChange ? route.path : route.fullPath` | `SettingsWrapper.vue:16-18` |
| `keep-alive` | wraps the page when `keepAlive` (default true) | `SettingsWrapper.vue:27-30` |

Notes that matter for a redesign:

- `items-start` on the inner flex row (`SettingsWrapper.vue:25`) means the page component is **not
  stretched to full height**. A page that declares `h-full` (e.g. `SettingsLayout.vue:23`) gets its
  height from a parent with no explicit height. Any change to this line changes every settings page.
- The only route using `meta.reuseOnQueryChange` is Audit logs (`auditlogs/audit.routes.js:24`), so
  only that page survives a query-string change without a remount.

### 2.2 `Wrapper.vue` (imported as `SettingsContent`) — the wide sub-page column with a title bar

`routes/dashboard/settings/Wrapper.vue`

| Aspect | Value | Evidence |
|---|---|---|
| Props | `headerTitle: String = ''`, `icon: String = ''`, `keepAlive: Boolean = true`, `showBackButton: Boolean = false`, `backUrl: [String, Object] = ''` | `Wrapper.vue:5-11` |
| Slots | none | — |
| Header | renders `SettingsHeader.vue` only when `headerTitle \|\| icon \|\| showBackButton` | `Wrapper.vue:15-17, 22-29` |
| Header classes | `z-20 max-w-7xl w-full mx-auto` | `Wrapper.vue:28` |
| Title i18n | the title is `t(headerTitle)` — routes pass **i18n keys**, not strings | `Wrapper.vue:24` |
| Outer classes | `flex flex-col h-full m-0 bg-n-surface-1 w-full` | `Wrapper.vue:21` |
| `router-view` classes | `px-4 overflow-hidden` (merged onto the rendered page's root by vue-router 4.4) | `Wrapper.vue:31` |
| Max width | `max-w-7xl` (80rem) for the header bar; the body max width is each page's own | `Wrapper.vue:28` |

Imported as `SettingsContent` by three route files only: `inbox/inbox.routes.js:5`,
`macros/macros.routes.js:8`, `teams/teams.routes.js:12`.

### 2.3 `SettingsHeader.vue` — the legacy title bar used only by `Wrapper.vue`

`routes/dashboard/settings/SettingsHeader.vue`

| Aspect | Value | Evidence |
|---|---|---|
| API style | Options API (`export default`), the only shell in this area not using `<script setup>` | `SettingsHeader.vue:1-39` |
| Props | `headerTitle`, `icon`, `showBackButton`, `backUrl`, `backButtonLabel` | `SettingsHeader.vue:9-27` |
| Slots | one default slot, placed between the back button and the title | `SettingsHeader.vue:54` |
| Bar classes | `flex justify-between items-center h-20 min-h-[3.5rem] px-6 py-2 bg-n-surface-1` | `SettingsHeader.vue:43-45` |
| Title markup | `h1.flex.items-center.mb-0.text-2xl.text-n-slate-12` wrapping `span.text-xl.font-medium.text-n-slate-12` | `SettingsHeader.vue:46, 55-57` |
| Dead code | `iconClass` computed (`icon ${icon} header--icon`) is never rendered; `icon` prop is accepted and ignored | `SettingsHeader.vue:34-38` vs `:42-59` |
| Dead code | `useAdmin()` / `isAdmin` is exposed but never used in the template | `SettingsHeader.vue:28-33` |
| Back button | `BackButton` with `ltr:mr-4 rtl:ml-4` | `SettingsHeader.vue:47-52` |

Only consumer: `Wrapper.vue:4, 22`.

### 2.4 `ReportsWrapper.vue` — the reports column

`routes/dashboard/settings/reports/components/ReportsWrapper.vue` (7 lines, template only)

| Aspect | Value | Evidence |
|---|---|---|
| Props / slots | none | whole file |
| Outer classes | `overflow-auto bg-n-surface-1 w-full px-6` | `ReportsWrapper.vue:2` |
| Inner classes | `max-w-5xl mx-auto pb-12` | `ReportsWrapper.vue:3` |
| Notes | no `keep-alive`, no `pt-*` (pages supply their own top padding via `ReportHeader`'s `pt-6`) | `ReportsWrapper.vue:2-5`, `ReportHeader.vue:21` |

### 2.5 `profile/Wrapper.vue` — dead shell

`routes/dashboard/settings/profile/Wrapper.vue` declares `keepAlive` and wraps a `router-view` in
`flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1`
(`profile/Wrapper.vue:11-20`). **Nothing imports it** — `grep -rn "profile/Wrapper"` over
`app/javascript` returns no hit; `profile/profile.routes.js:4` mounts `SettingsWrapper` instead.

---

## 3. `SettingsLayout.vue` — the per-page frame (level 2)

`routes/dashboard/settings/SettingsLayout.vue`

| Aspect | Value | Evidence |
|---|---|---|
| Props | `isLoading: Boolean = false`, `noRecordsFound: Boolean = false`, `loadingMessage: String = ''`, `noRecordsMessage: String = ''` | `SettingsLayout.vue:2-19` |
| Root classes | `flex flex-col w-full h-full gap-4 font-inter` | `SettingsLayout.vue:23` |
| Spacing | the only spacing it owns is `gap-4` between header and `main`; `main` has **no padding** | `SettingsLayout.vue:23, 26` |
| Max width | none — inherited from the route-level shell | — |

Slots, in render order:

| Slot | Rendered | Evidence |
|---|---|---|
| `header` | always, above `main` | `SettingsLayout.vue:24` |
| `preBody` | always, first child of `main` ("templates that should be rendered before body") | `SettingsLayout.vue:27` |
| `loading` | when `isLoading`; falls back to `<woot-loading-state :message="loadingMessage" />` | `SettingsLayout.vue:28-30` |
| (empty state) | when `!isLoading && noRecordsFound`: a `<p>` with `flex-1 py-20 text-n-slate-12 flex items-center justify-center text-base` showing `noRecordsMessage` — **not a slot, not overridable** | `SettingsLayout.vue:31-36` |
| `body` | when neither loading nor empty | `SettingsLayout.vue:37` |
| default | always, after `body`, with an in-code warning not to delete it (pages put dialogs here) | `SettingsLayout.vue:38-39` |

Consumers: 36 page components (see §6). Four pass a `class` to override layout:
`assignmentPolicy/Index.vue:86` and `conversationWorkflow/index.vue:32` use `class="gap-10"`;
`assignmentPolicy/pages/AgentAssignmentCreatePage.vue:91`,
`AgentAssignmentEditPage.vue:259`, `AgentCapacityCreatePage.vue:70`, `AgentCapacityEditPage.vue:199`
use `class="w-full max-w-2xl ltr:mr-auto rtl:ml-auto"`.

---

## 4. Header anatomy

### 4.1 `BaseSettingsHeader.vue` — the canonical settings header

`routes/dashboard/settings/components/BaseSettingsHeader.vue` (131 lines)

**Props** (`BaseSettingsHeader.vue:9-34`)

| Prop | Type / default | Effect |
|---|---|---|
| `title` | `String`, **required** | renders `h1.text-heading-1.text-n-slate-12`; the whole title row is `v-if="title"` (`:52-60`) |
| `description` | `String = ''` | renders `p.mb-0.line-clamp-5.sm:line-clamp-none.max-w-3xl.text-body-main` (`:67-72`) |
| `linkText` | `String = ''` | label of the help link; link renders only if `helpURL && linkText` (`:74-80`) |
| `featureName` | `String = ''` | resolved **once at setup** via `getHelpUrlForFeature` → `helpURL` (`:40`) |
| `backButtonLabel` | `String = ''` | renders `BackButton compact` above the title, `class="my-1"` (`:45-50`) |
| `searchPlaceholder` | `String = ''` | presence of this string is what makes the search input exist (`:103-117`) |

**Model:** `searchQuery = defineModel('searchQuery', { type: String, default: '' })`
(`BaseSettingsHeader.vue:38`) — consumers bind `v-model:search-query`.

**Slots**

| Slot | Position | Fallback | Evidence |
|---|---|---|---|
| `title` | replaces the `h1` inside the title row | the `h1` with `{{ title }}` | `:55-59` |
| `description` | inside the description `<p>` | `{{ description }}` | `:67-72` |
| `meta` | after the help link, inside the description column | none | `:88` |
| `tabs` | first item of the controls row's left group | none | `:102` |
| `count` | first item of the controls row's right group | none | `:123` |
| `actions` | last item of the right group | none | `:128` |

**Structure** — this component renders **two sibling root nodes** (a fragment):

1. `div.flex.flex-col.items-start.w-full` — back button, title row, description block
   (`BaseSettingsHeader.vue:44-90`)
2. `div.gap-3.flex.flex-wrap.sm:flex-nowrap.justify-between.sm:mt-4.min-w-0` — the controls row,
   rendered only when `searchPlaceholder || slots.actions || slots.tabs`
   (`BaseSettingsHeader.vue:91-130`)

Because the root is a fragment and the component does not set `inheritAttrs: false`, a `class` or any
other attribute passed from a parent **cannot fall through**. No page passes a `class`; one page does
pass an undeclared prop (see §7, finding I-1).

**Spacing inside the header**

| Element | Classes | Evidence |
|---|---|---|
| Title row | `flex items-center justify-between w-full gap-4 min-h-8 mb-2` | `:52-54` |
| Description column | `flex flex-col w-full gap-1.5 text-n-slate-11` | `:61-66` |
| Description `<p>` | `mb-0 line-clamp-5 sm:line-clamp-none max-w-3xl text-body-main` | `:69` |
| Help link | `items-center hidden gap-1 text-sm font-medium sm:inline-flex w-fit text-n-blue-11 hover:underline mb-2` + `Icon i-lucide-chevron-right size-4` | `:79-86` |
| Controls row | `gap-3 flex flex-wrap sm:flex-nowrap justify-between sm:mt-4 min-w-0` | `:93` |
| Left group | `flex items-center gap-3 min-w-0`, plus `hidden sm:flex` when there is no `tabs` slot | `:96-101` |
| Right group | `flex items-center gap-3 shrink-0`, plus `flex-row-reverse sm:flex-row` when there is no `tabs` slot | `:119-121` |
| Count/actions divider | `w-px h-3 rounded-lg bg-n-weak ltr:ml-1 ltr:mr-2 rtl:ml-2 rtl:mr-1 flex-shrink-0`, only when **both** `count` and `actions` slots are filled | `:124-127` |
| Search input | `Input size="sm" type="search"`, `group w-56 min-w-0 hidden sm:flex [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8 [&>input]:!rounded-[0.625rem]`, prefixed with an absolutely positioned `i-lucide-search` | `:103-117` |

**Responsive behaviour that is part of today's baseline** (a redesign that changes any of these changes
feature discoverability):

| Below `sm` (<640px) | Where |
|---|---|
| The help / "Learn more" link is **hidden** (`hidden … sm:inline-flex`) | `:79` |
| The search input is **hidden** (`hidden sm:flex`) | `:107` |
| When a page has no `tabs`, the whole left group (i.e. search) is **hidden** | `:98-100` |
| The description is clamped to 5 lines (`line-clamp-5 sm:line-clamp-none`) | `:69` |
| The controls row loses its top margin (`sm:mt-4`) and wraps (`flex-wrap sm:flex-nowrap`) | `:93` |
| Count/actions order is reversed when there are no tabs (`flex-row-reverse sm:flex-row`) | `:121` |

**Branding:** the help link is wrapped in
`CustomBrandPolicyWrapper :show-on-custom-branded-instance="false"` (`:73-87`), so it disappears
entirely on custom-branded installs.

### 4.2 `SettingsSubPageHeader.vue` — wizard-step header

`routes/dashboard/settings/SettingsSubPageHeader.vue` (21 lines)

| Aspect | Value | Evidence |
|---|---|---|
| Props | `headerTitle: String = ''`, `headerContent: String = ''` | `:4-6` |
| Slots | none | — |
| Root | `flex flex-col gap-1.5 w-full items-start mb-4` | `:11` |
| Title | `h2.text-heading-1.text-n-slate-12.break-words` — an `h2` carrying the **page-title** token | `:12-14` |
| Description | `p.text-body-main.w-full.text-n-slate-11` rendered through `v-dompurify-html` (so it accepts HTML) | `:15-18` |

Imported 17 times, always aliased to `PageHeader` except in `OAuthChannel.vue` (see §6.2).

### 4.3 `ReportHeader.vue` — reports header

`routes/dashboard/settings/reports/components/ReportHeader.vue`

| Aspect | Value | Evidence |
|---|---|---|
| Props | `headerTitle: String` **required**, `headerDescription: String = ''`, `hasBackButton: Boolean = false` | `:4-17` |
| Slots | one default slot, right-aligned in a `flex-shrink-0` box (used for the download button) | `:41-43` |
| Root | `section.flex.flex-col.gap-1.pt-6.pb-5` — owns the reports column's top padding | `:21` |
| Title | `span.text-heading-1.text-n-slate-12.min-h-10.flex.items-center` — a `span`, not a heading element | `:28-32` |
| Description | `p.text-n-slate-11.mb-0.line-clamp-5.sm:line-clamp-none.text-body-main` | `:33-38` |
| Back button | `BackButton compact` in its own row above the title | `:22-24` |
| No search / tabs / count | — | whole file |

### 4.4 `ImportDetailHeader.vue` — the one composition over `BaseSettingsHeader`

`routes/dashboard/settings/data/components/ImportDetailHeader.vue` is the only component in the
codebase that wraps `BaseSettingsHeader` to build a richer header instead of re-implementing one.

| Aspect | Value | Evidence |
|---|---|---|
| Props | `dataImport: Object = null`, `isRefreshing`, `isRetrying`, `isAbandoning`, `isPolling` (all `Boolean = false`) | `:15-36` |
| Emits | `refresh`, `retry`, `abandon` | `:38` |
| Passes down | `:title="title"`, `:back-button-label="$t('DATA_IMPORTS.DETAIL.BACK')"` | `:76-79` |
| Uses `#title` | to put a truncating `h1.min-w-0.truncate.text-heading-1.text-n-slate-12` next to a `shrink-0` action cluster (refresh / retry / abandon buttons) — i.e. it moves the actions **into the title row** rather than using the `actions` slot | `:80-98`, `:97-121` |
| Uses `#description` | for a live status line: a colour-coded `size-2 rounded-full` status dot, the stage label, a `h-3 w-px` divider and a polling indicator | `:120-145` |

**This is the pattern a redesign should reuse** when a page needs more than the stock header.

### 4.5 Other header-ish components in scope

| Component | Props | Slots | Shape | Evidence |
|---|---|---|---|---|
| `billing/components/BillingHeader.vue` | `title` req., `description` req. | default (right cell) | `div.grid.grid-cols-[1fr_auto].gap-5`; title is `span.text-base.font-medium`, desc `p.text-sm.mt-1` — hand-rolled type, not the typography tokens | whole file |
| `components/widgets/SettingIntroBanner.vue` | `headerTitle`, `headerIdentifier`, `headerContent` (all `String = ''`) | default (below the text, used for tabs) | `div.border-b.border-n-weak/60` > `div.max-w-7xl.w-full.mx-auto.pt-4.pb-0.px-6`; title is `h2.text-2xl.font-medium`, identifier `p.text-n-slate-9.text-sm` inside a `<bdi dir="auto">` | `:18-38` |
| `account/components/SectionLayout.vue` | `title` req., `description` req., `withBorder`, `hideContent`, `beta` | `title`, `description`, `headerActions`, default | `section.grid.grid-cols-1.pt-8.gap-5` + `header.grid.grid-cols-4` (3/1 split); heading is `h4.text-heading-2`; animates height via `[interpolate-size:allow-keywords]` | whole file |
| `components-next/Settings/SettingsFieldSection.vue` | `label` req., `helpText` | default, `extra` | `grid lg:grid-cols-8` with a 2/6 label-field split; label is `label.text-heading-3` | whole file |
| `components-next/Settings/SettingsToggleSection.vue` | (`header`, `description`, `hideToggle`, `compact`, model) | default, `editor`, `hiddenToggle` | bordered `rounded-xl` card, header is `span.text-heading-3` | `:1-29` of template |
| `components-next/SidebarActionsHeader.vue` | `title` req., `buttons: Array` | none | `flex items-center justify-between px-4 py-2 border-b border-n-weak h-12`; title `span.font-medium.text-sm` | whole file |
| `components/widgets/BackButton.vue` | `backUrl: [String, Object]`, `buttonLabel`, `compact` | none | `button.flex.items-center.p-0.font-normal.cursor-pointer.text-n-slate-11` + `i.i-lucide-chevron-left.-ml-1.text-lg`; `compact` → `text-sm` else `text-base`; falls back to `router.go(-1)` and to `$t('GENERAL_SETTINGS.BACK')` | whole file |

---

## 5. Non-settings page shells (for consistency comparison)

These are the shells the rest of the dashboard uses. They share a recognisable skeleton —
`section.flex.flex-col.w-full.h-full.overflow-hidden.bg-n-surface-1` + `header.sticky.top-0.z-10.px-6`
+ `main.flex-1.px-6.overflow-y-auto` + optional sticky `footer` — but **none of them share code**.

| Shell | Props | Slots | Container | Header height | Evidence |
|---|---|---|---|---|---|
| `components-next/Campaigns/CampaignLayout.vue` | `headerTitle`, `buttonLabel` | `action`, `default` | `max-w-5xl` header and body | `h-20` | `:5-14, 24-56` |
| `components-next/Campaigns/CampaignAnalyticsLayout.vue` | `breadcrumbItems: Array` | default | `max-w-5xl` | `h-20` | whole file |
| `components-next/Contacts/ContactsListLayout.vue` | 15 props (`searchValue`, `headerTitle`, `showPaginationFooter`, `currentPage`, `totalItems`, `itemsPerPage`, `activeSort`, `activeOrdering`, `activeSegment`, `segmentsId`, `hasAppliedFilters`, `isFetchingList`, `useInfiniteScroll`, `hasMore`, `isLoadingMore`) | `default` | `main` inner `max-w-5xl`; footer `max-w-[67rem]` | header delegated to `ContactListHeaderWrapper` | `:10-26, 79-129` |
| `components-next/Contacts/ContactsHeader/ContactHeader.vue` | 12 props, 13 emits | `filter` | `max-w-5xl`, `py-6` | `sticky top-0 z-20 px-6` | `:8-38`, template `:2-103` |
| `components-next/Contacts/ContactsDetailsLayout.vue` | `selectedContact`, `isUpdating` | `default`, `sidebar`, `sidebarHeader` | `max-w-[40.625rem]`, `py-7`, `ltr:2xl:ml-56` | breadcrumb row | `:12-21, 74-198` |
| `components-next/Companies/CompaniesListLayout.vue` | 7 props | `default` | `max-w-5xl`; footer `max-w-[67rem]`, hard-coded `:items-per-page="25"` | delegated to `CompanyHeader` | whole file |
| `components-next/Companies/CompaniesDetailsLayout.vue` | `breadcrumbItems` | default, `sidebar`, `sidebarHeader` | `max-w-[40.625rem]` | breadcrumb row | `:8-13, 33-55` |
| `components-next/HelpCenter/HelpCenterLayout.vue` | `currentPage`, `totalItems`, `itemsPerPage`, `showHeaderTitle`, `showPaginationFooter`, `breadcrumbLabel` | `title-actions`, `header-actions`, `content`, default | `max-w-5xl`; footer `max-w-[67rem]` | `h-20` | `:12-37, 65-131` |
| `components-next/captain/PageLayout.vue` | 13 props incl. `containerClass = 'max-w-[71rem]'`, `buttonPolicy`, `featureFlag`, `isEmpty`, `showKnowMore` | `knowMore`, `headerActions`, `search`, `action`, `subHeader`, `controls`, `paywall`, `emptyState`, `body`, default | `containerClass` (default `max-w-[71rem]`); footer `max-w-[67rem]` | `lg:h-20`, stacks below `lg` | `:16-73, 121-243` |
| `components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue` | `heading` req., `description` | default | `VerticalTabs content-class="max-w-[45rem] pb-8"` inside `PageLayout` | — | whole file |
| `components-next/captain/pageComponents/settings/SettingsHeader.vue` | `heading` req., `description` | none | `header.flex.flex-col.items-start.gap-2`; `h2.text-base.font-medium` + `p.text-sm` (hand-rolled type) | — | whole file |
| `components-next/EmptyStateLayout.vue` | `title` req., `subtitle` req., `actionPerms`, `showBackdrop` | `empty-state-item`, `actions` | `max-w-5xl`, `max-h-[28rem]` | — | whole file |
| `components-next/CardLayout.vue` | `layout = 'col'`, `selectable` | default, `after` | `rounded-xl bg-n-solid-2 outline-1 outline-n-container` | — | whole file |
| `routes/dashboard/onboarding/shared/OnboardingLayout.vue` | `greeting` req., `subtitle`, `continueLabel`, `skipLabel`, `isLoading`, `disabled` | `greeting-icon`, default | `max-w-[40rem]` on `bg-n-surface-2`, decorative inline SVG timeline | `h1.text-heading-1` | whole file |

---

## 6. Per-page matrix — every settings page

Legend for **Header**: `BSH` = `BaseSettingsHeader`, `SSPH` = `SettingsSubPageHeader`,
`RH` = `ReportHeader`, `hand-rolled` = header markup written inline in the page.

### 6.1 Routes mounted on `SettingsWrapper` (the `max-w-5xl` column)

| Route name | Path (after `/app/accounts/:accountId/`) | Page component | Page shell | Header | Header features used |
|---|---|---|---|---|---|
| `settings_home` | `settings` | — (redirect to `general_settings_index` or `canned_list`) | — | — | `settings.routes.js:37-53` |
| `general_settings_index` | `settings/general` | `account/Index.vue` | **none** — own root `div.flex.flex-col.w-full.max-w-2xl.ltr:mr-auto.rtl:ml-auto` (`:160`) | BSH (`:161`) | title only |
| `agent_list` | `settings/agents/list` | `agents/Index.vue` | `SettingsLayout` (`:148-153`) | BSH (`:155-175`) | title, description, linkText, search, `count`, `actions` |
| `assignment_policy_index` | `settings/assignment-policy/index` | `assignmentPolicy/Index.vue` | `SettingsLayout class="gap-10"` (`:86`) | BSH (`:88-92`) | title, description, featureName |
| `agent_assignment_policy_index` | `settings/assignment-policy/assignment` | `assignmentPolicy/pages/AgentAssignmentIndexPage.vue` | `SettingsLayout` (`:91-97`) | **hand-rolled** `div.flex.items-center.gap-2.w-full.justify-between.min-h-10` with `Breadcrumb` + create `Button` (`:99-108`) | — |
| `agent_assignment_policy_create` | `.../assignment/create` | `pages/AgentAssignmentCreatePage.vue` | `SettingsLayout class="w-full max-w-2xl …"` (`:91`) | **hand-rolled** `Breadcrumb` row (`:93-95`) | — |
| `agent_assignment_policy_edit` | `.../assignment/edit/:id` | `pages/AgentAssignmentEditPage.vue` | `SettingsLayout class="w-full max-w-2xl …"` (`:257-259`) | **hand-rolled** `Breadcrumb` row (`:262`) | — |
| `agent_capacity_policy_index` | `.../capacity` | `pages/AgentCapacityIndexPage.vue` | `SettingsLayout` | **hand-rolled** `Breadcrumb` + create `Button` row (`AgentCapacityIndexPage.vue:97-106`) | — |
| `agent_capacity_policy_create` | `.../capacity/create` | `pages/AgentCapacityCreatePage.vue` | `SettingsLayout class="w-full max-w-2xl …"` (`:70`) | **hand-rolled** `Breadcrumb` row (`:72`) | — |
| `agent_capacity_policy_edit` | `.../capacity/edit/:id` | `pages/AgentCapacityEditPage.vue` | `SettingsLayout class="w-full max-w-2xl …"` (`:197-199`) | **hand-rolled** `Breadcrumb` row (`:202`) | — |
| `agent_bots` | `settings/agent-bots` | `agentBots/Index.vue` | `SettingsLayout` (`:99-104`) | BSH (`:106-126`) | title, description, linkText, search, `count`, `actions` |
| `attributes_list` | `settings/custom-attributes/list` | `attributes/Index.vue` | `SettingsLayout` | BSH (`:169-196`) | title, description, linkText, search, `count`, **`tabs` (`TabBar`)**, `actions` |
| `automation_list` | `settings/automation/list` | `automation/Index.vue` | `SettingsLayout` | BSH (`:331-368`) | title, description, linkText (never rendered — see I-11), search, **`tabs` (`TabBar`, conditional, `:339`)**, `count` (`:346`), `actions` |
| `auditlogs_list` | `settings/audit-logs/list` (`meta.reuseOnQueryChange`) | `auditlogs/Index.vue` | `SettingsLayout` | BSH (`:161-194`) | title, description, linkText, search, **`tabs` used for `AuditLogFilters`, not tabs (`:169`)**, `count` (`:179`, keyed off `meta.totalEntries`) |
| `billing_settings_index` | `settings/billing` | `billing/ProviderIndex.vue` → `ShopifyBilling.vue` or `billing/Index.vue` | `SettingsLayout` (`ProviderIndex.vue:25, 31`; `ShopifyBilling.vue:164`) | BSH (`ProviderIndex.vue:37-42`; `ShopifyBilling.vue:169-174`) | title, description only. The Stripe branch (`billing/Index.vue`) is a **headerless redirect spinner** (`billing/Index.vue:8-16`) |
| `canned_list` | `settings/canned-response/list` | `canned/Index.vue` | `SettingsLayout` | BSH (`:149-169`) | title, description, linkText, search, `count`, `actions` |
| `settings_inbox_list` | `settings/inboxes/list` | `inbox/Index.vue` | `SettingsLayout` | BSH (`:101-119`) | title, description, linkText, search, `count`, `actions` (admin-gated router-link) |
| `settings_templates` | `settings/templates` | `templates/Index.vue` | `SettingsLayout` | BSH (`:339-404`) | title, description, linkText, conditional search, **`meta` (last-sync line, `:349`)**, **`tabs` (filter menus, `:358`)**, `count` (`:384`), `actions` |
| `settings_applications` | `settings/integrations` | `integrations/Index.vue` | `SettingsLayout` | BSH (`:38-47`) | title, description (branded), linkText, search |
| `settings_integrations_dashboard_apps` | `settings/integrations/dashboard_apps` | `integrations/DashboardApps/Index.vue` | `SettingsLayout` | BSH (`:108-135`) | title, description, linkText, search, **`backButtonLabel`**, `count`, `actions` |
| `settings_integrations_webhook` | `settings/integrations/webhook` | `integrations/Webhooks/Index.vue` | `SettingsLayout` | BSH (`:136-165`) | title/description from the integration record, linkText, conditional search, `backButtonLabel`, `count`, `actions` |
| `settings_integrations_slack` | `settings/integrations/slack` | `integrations/Slack.vue` | `SettingsLayout` (`:87`) | BSH (`:88-93`) | title, empty description, `backButtonLabel` |
| `settings_integrations_linear` | `settings/integrations/linear` | `integrations/Linear.vue` | `SettingsLayout` | BSH (`:41-46`) | title, empty description, `backButtonLabel` |
| `settings_integrations_notion` | `settings/integrations/notion` | `integrations/Notion.vue` | `SettingsLayout` | BSH (`:55-60`) | title, empty description, `backButtonLabel` |
| `settings_integrations_shopify` | `settings/integrations/shopify` | `integrations/Shopify.vue` | `SettingsLayout` | BSH (`:97-102`) | title, empty description, `backButtonLabel` |
| `settings_applications_integration` | `settings/integrations/:integration_id` | `integrations/IntegrationHooks.vue` (renders `MultipleIntegrationHooks.vue` for multi-hook apps) | `SettingsLayout` (`:120`) / plain `div.flex.flex-col.flex-1.gap-4.overflow-auto` (`MultipleIntegrationHooks.vue:74`) | BSH (`:121-126`) / BSH (`MultipleIntegrationHooks.vue:75-101`) | title, `backButtonLabel`; the multi variant adds search, `count`, `actions` |
| `settings_data_imports` | `settings/data` | `data/Index.vue` | `SettingsLayout` | BSH (`:189-239`) | title, description, **`tabs` (`TabBar`, `:193`)**, `count` (`:200`), `actions`. No linkText / featureName / search |
| `settings_data_import_show` | `settings/data/:dataImportId` | `data/Show.vue` | `SettingsLayout` (`:213-216`) | **`ImportDetailHeader`** wrapping BSH (`:218-227`) | title, `backButtonLabel`, `#title` override, `#description` override |
| `labels_list` | `settings/labels/list` | `labels/Index.vue` | `SettingsLayout` | BSH (`:108-128`) | title, description, linkText, search, `count`, `actions` |
| `macros_wrapper` | `settings/macros` | `macros/Index.vue` | `SettingsLayout` (`:73-79`) | BSH (`:81-99`) | title, description, linkText, search, `count`, `actions` |
| `sla_list` | `settings/sla/list` | `sla/Index.vue` | `SettingsLayout` | BSH (`:145-167`) | title, description, linkText, paywall-conditional search / `count` / `actions` |
| `settings_teams_list` | `settings/teams/list` | `teams/Index.vue` | `SettingsLayout` | BSH (`:91-109`) | title, description, linkText, search, `count`, `actions` |
| `custom_roles_list` | `settings/custom-roles/list` | `customRoles/Index.vue` | `SettingsLayout` | BSH (`:140-161`) | title, description, linkText, search, `count`, `actions` |
| `profile_settings_index` | `profile/settings` | `profile/Index.vue` | **none** — own root `div.grid.max-w-2xl.ltr:mr-auto.rtl:ml-auto` (`:231`) | BSH (`:232`) | title, `description=""` |
| `profile_settings_mfa` | `profile/mfa` | `profile/MfaSettings.vue` | **none** — own root `div.grid.w-full` (`:139`) | BSH (`:140-144`) | title, description, `backButtonLabel` |
| `security_settings_index` | `settings/security` | `security/Index.vue` | `SettingsLayout` (`:35`) | BSH (`:36-41`) | title, description, linkText, featureName |
| `conversation_workflow_index` | `settings/conversation-workflow` | `conversationWorkflow/index.vue` | `SettingsLayout class="gap-10"` (`:32`) | BSH (`:34-38`) | title, description, featureName |
| `captain_settings_index` | `settings/captain` | `captain/Index.vue` | `SettingsLayout` (+ `SectionLayout` inside) | BSH (`:132-138`) | title, description, linkText, featureName, **plus an undeclared `icon-name` attr** |
| `subscription_settings_index` | `settings/subscription` | `subscription/Index.vue` | `SettingsLayout` (`:347-352`) | **hand-rolled** `div.flex.flex-col.gap-1` > `h1.text-xl.font-medium.text-n-slate-12` + `p.text-sm.text-n-slate-11` (`:353-358`) | — |
| `settings_commerce_index` | `settings/commerce` | `commerce/Index.vue` | `SettingsLayout` | BSH (`:271-285`) | title, description, `actions` (no linkText / featureName / search) |
| `settings_flows_index` | `settings/flows` | `flows/Index.vue` | `SettingsLayout` | BSH (`:169-191`) | title, description, `actions` (no linkText / featureName / search) |

### 6.2 Routes mounted on `Wrapper.vue` (`SettingsContent`, `max-w-7xl` + `SettingsHeader` bar)

Route-level props supplied to `Wrapper.vue`:
- inboxes: `headerTitle: 'INBOX_MGMT.HEADER'`, `icon: 'mail-inbox-all'`, `showBackButton`, `fullWidth` (`inbox/inbox.routes.js:40-49`)
- macros: `headerTitle: 'MACROS.HEADER'`, `icon: 'flash-settings'`, `showBackButton: true` (`macros/macros.routes.js:33-39`)
- teams: `headerTitle: 'TEAMS_SETTINGS.HEADER'`, `icon: 'people-team'`, `showBackButton: true` (`teams/teams.routes.js:41-47`)

| Route name | Path | Page component | Page shell | Header |
|---|---|---|---|---|
| `settings_inbox_new` | `settings/inboxes/new` | `inbox/InboxChannels.vue` → `inbox/ChannelList.vue` | `div.mx-auto.flex.flex-col.gap-6.mb-8.max-w-7xl.w-full.!px-6` + `woot-wizard` grid (`InboxChannels.vue:62-76`) | `SSPH` as `PageHeader`, **mobile-only** (`class="block lg:hidden !mb-0"`, `:63`); the step list is the desktop header. `ChannelList.vue` itself has **no header** (`:2-13`) |
| `settings_inbox_finish` | `.../new/:inbox_id/finish` | `inbox/FinishSetup.vue` | `div.overflow-auto.col-span-6.p-6.w-full.h-full` | **none** — uses `EmptyState` with its own title |
| `settings_inboxes_page_channel` | `.../new/:sub_page` | `inbox/ChannelFactory.vue` → `inbox/channels/*` | per-channel | see §6.3 |
| `settings_inboxes_add_agents` | `.../new/:inbox_id/agents` | `inbox/AddAgents.vue` | `div.h-full.w-full.p-6.col-span-6` | `SSPH` as `PageHeader` with `headerTitle` + `headerContent` (`:5-10` of template) |
| `settings_inbox_show` | `settings/inboxes/:inboxId/:tab?` | `inbox/Settings.vue` | `div.grid.grid-rows-[auto_1fr].h-full…settings` (`:781-784`) | **`SettingIntroBanner`** (avatar + name + identifier) with `woot-tabs` in its default slot (`:785-805`); body `section.w-full.overflow-auto.py-8` > `div.max-w-7xl.mx-auto.w-full` (`:806-807`); content max width is computed per channel (`max-w-7xl` / `max-w-4xl` / `max-w-2xl`, `:324-326, 888, 1413`). Note the leftover `settings` class, which has no CSS rule anywhere under `assets/scss/` |
| `macros_edit` / `macros_new` | `settings/macros/:macroId/edit`, `settings/macros/new` | `macros/MacroEditor.vue` | `div.flex.flex-col.gap-6.mb-8.max-w-7xl.mx-auto.h-full.w-full.!px-6` (`:137`) | **none** in the page — the only title is the `Wrapper`/`SettingsHeader` bar |
| `settings_teams_new` | `settings/teams/new` | `teams/Create/Index.vue` → `Create/CreateTeam.vue` | step wrapper `div.flex.flex-col.gap-6.mb-8.max-w-7xl.mx-auto.w-full.!px-6` + `woot-wizard` grid (`Create/Index.vue:26-36`); page root `div.h-full.w-full.p-6.col-span-6.overflow-y-auto` | `SSPH` as `PageHeader` |
| `settings_teams_add_agents` | `.../new/:teamId/agents` | `teams/Create/AddAgents.vue` | `div.h-full.w-full.px-8.pt-8.col-span-6.overflow-auto` | `SSPH` as `PageHeader` |
| `settings_teams_finish` | `.../new/:teamId/finish` | `teams/FinishSetup.vue` | `div.h-full.w-full.p-6.col-span-6` | **none** — `EmptyState` |
| `settings_teams_edit` | `settings/teams/:teamId/edit` | `teams/Edit/Index.vue` → `Edit/EditTeam.vue` | step wrapper as above (`Edit/Index.vue:30-40`); page root `div.h-full.w-full.p-8.col-span-6.overflow-y-auto` | `SSPH` as `PageHeader` |
| `settings_teams_edit_members` | `.../edit/agents` | `teams/Edit/EditAgents.vue` | `div.h-full.w-full.px-8.pt-8.col-span-6.overflow-auto` | `SSPH` as `PageHeader` |
| `settings_teams_edit_finish` | `.../edit/finish` | `teams/FinishSetup.vue` | as above | **none** |

### 6.3 Inbox channel creation pages (`ChannelFactory.vue:17-31` and the manual-setup variants)

| Channel page | Header |
|---|---|
| `inbox/channels/Api.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Email.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Facebook.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Line.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Sms.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Telegram.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Voice.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/Website.vue` | `SSPH` as `PageHeader` (`:80-83`) |
| `inbox/channels/emailChannels/ForwardToOption.vue` | `SSPH` as `PageHeader` |
| `inbox/channels/emailChannels/OAuthChannel.vue` | `SettingsSubPageHeader` **imported under its own name** (`:6, 64`) — the one place the `PageHeader` alias is not used |
| `inbox/channels/360DialogWhatsapp.vue` | **none** — bare `<form class="flex flex-wrap flex-col mx-0">` |
| `inbox/channels/BandwidthSms.vue` | **none** — bare form |
| `inbox/channels/CloudWhatsapp.vue` | **none** — bare form |
| `inbox/channels/Twilio.vue` | **none** — bare form |
| `inbox/channels/Instagram.vue` | **none** — centred card, errors shown in a bare `<h5>` (`:5-7`) |
| `inbox/channels/Tiktok.vue` | **none** — centred card, bare `<h5>` |
| `inbox/channels/Twitter.vue` | **none** — `div.h-full.w-full.p-6.col-span-6` with a sign-in button |
| `inbox/channels/WhatsappCall.vue` | **none** — bordered card wrapping `CloudWhatsapp` |
| `inbox/channels/Whatsapp.vue` | **hand-rolled** — `span.text-heading-2` (`:177`) and `h1.mb-2.text-lg.font-medium.text-n-slate-12` (`:235`) |
| `inbox/channels/WhatsappEmbeddedSignup.vue` | **hand-rolled** — `h3.mb-2.text-base.font-medium.text-n-slate-12` (`:207`) |
| `inbox/channels/WhatsappManualSetup.vue` | **hand-rolled** — `h1.text-heading-1` (`:315`) and two `h2.text-heading-2` (`:350, :423`) |
| `inbox/channels/emailChannels/EmailInboxFinish.vue`, `Google.vue`, `Microsoft.vue` | **none** |

### 6.4 Routes mounted on `ReportsWrapper` (files live under `settings/reports/`, routes are at `/reports`)

| Route name | Path | Page component | Header |
|---|---|---|---|
| `account_overview_reports` | `reports/overview` | `reports/LiveReports.vue` | `RH` title only (`:11`) |
| `conversation_reports` | `reports/conversation` | `reports/Index.vue` | `RH` title + default-slot download button (`:110-117`) |
| `agent_reports` | `reports/agent` | `reports/AgentReports.vue` → `components/WootReports.vue` | `RH` via `WootReports.vue:168-175` |
| `inbox_reports` | `reports/inboxes` | `reports/InboxReports.vue` → `WootReports` | `RH` |
| `label_reports` | `reports/label` | `reports/LabelReports.vue` → `WootReports` | `RH` |
| `team_reports` | `reports/teams` | `reports/TeamReports.vue` → `WootReports` | `RH` |
| `agent_reports_index` | `reports/agents_overview` | `reports/AgentReportsIndex.vue` | `RH` title + **description** + download button (`:15-25`) |
| `agent_reports_show` | `reports/agents/:id` | `reports/AgentReportsShow.vue` → `WootReports` | `RH` with `has-back-button` (`:26`) |
| `inbox_reports_index` | `reports/inboxes_overview` | `reports/InboxReportsIndex.vue` | `RH` title + description + action |
| `inbox_reports_show` | `reports/inboxes/:id` | `reports/InboxReportsShow.vue` → `WootReports` | `RH` with `has-back-button` |
| `team_reports_index` | `reports/teams_overview` | `reports/TeamReportsIndex.vue` | `RH` title + description + action |
| `team_reports_show` | `reports/teams/:id` | `reports/TeamReportsShow.vue` → `WootReports` | `RH` with `has-back-button` |
| `label_reports_index` | `reports/labels_overview` | `reports/LabelReportsIndex.vue` | `RH` title + description + action |
| `label_reports_show` | `reports/labels/:id` | `reports/LabelReportsShow.vue` → `WootReports` | `RH` with `has-back-button` |
| `sla_reports` | `reports/sla` | `reports/SLAReports.vue` | `RH` title + action (`:84-91`) |
| `csat_reports` | `reports/csat` | `reports/CsatResponses.vue` | `RH` title + action (`:118-125`) |
| `bot_reports` | `reports/bot` | `reports/BotReports.vue` | `RH` title only (`:89`) |

### 6.5 Settings route with no shell at all

| Route name | Path | Page component | Header |
|---|---|---|---|
| `settings_flows_builder` | `settings/flows/:flowId` | `flows/FlowBuilder.vue` | **fully hand-rolled, full-bleed**: `div.flex.flex-col.w-full.h-full.bg-n-surface-1` > `header.flex.flex-wrap.items-center.gap-3.px-4.py-3.border-b.border-n-weak.shrink-0` with a back icon-button, `h1.m-0.text-base.font-medium.text-n-slate-12.truncate`, a status `span.text-xs`, inbox chips and an action cluster (`FlowBuilder.vue` template `:1-60`). Mounted at the top level of the route tree, deliberately outside the settings column (`flows/flows.routes.js:7-8, 23-28`) |

### 6.6 Roll-up

| Header approach | Count | Pages |
|---|---|---|
| `BaseSettingsHeader` | **35** components render `<BaseSettingsHeader` (`grep -rl` over `settings/`, excluding specs) | §6.1, plus `MultipleIntegrationHooks.vue`, `ShopifyBilling.vue`, `ImportDetailHeader.vue` |
| `SettingsSubPageHeader` (as `PageHeader`) | **16** | §6.2 / §6.3 |
| `ReportHeader` | **10** direct consumers (incl. `components/WootReports.vue`, which fronts the 6 `*Reports.vue` / `*ReportsShow.vue` pages) | §6.4 |
| `SettingsHeader` (via `Wrapper.vue`) | **1** shell serving 12 routes | §6.2 |
| `SettingIntroBanner` | **1** (inbox detail) | `inbox/Settings.vue:785` |
| **Hand-rolled page header** | **9** | `subscription/Index.vue:354-358`; the six `assignmentPolicy/pages/*` breadcrumb rows; `flows/FlowBuilder.vue`; `inbox/channels/Whatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `WhatsappManualSetup.vue` |
| **No header at all** | **10** | `billing/Index.vue`, `macros/MacroEditor.vue`, `inbox/ChannelList.vue`, `inbox/FinishSetup.vue`, `teams/FinishSetup.vue`, `inbox/channels/{360DialogWhatsapp,BandwidthSms,CloudWhatsapp,Twilio,Twitter,Instagram,Tiktok,WhatsappCall}.vue`, `emailChannels/{EmailInboxFinish,Google,Microsoft}.vue` |

---

## 7. Spacing, max-width and typography reference

### 7.1 Container widths actually in use

| Width | Where | Evidence |
|---|---|---|
| `max-w-5xl` (64rem) | settings column, reports column, campaigns, contacts list, companies list, help center, empty states | `SettingsWrapper.vue:25`, `ReportsWrapper.vue:3`, `CampaignLayout.vue:26,52`, `ContactsListLayout.vue:102`, `CompaniesListLayout.vue:42`, `HelpCenterLayout.vue:68,115`, `EmptyStateLayout.vue:29` |
| `max-w-7xl` (80rem) | `Wrapper.vue` header bar, inbox/team/macro wizard pages, `SettingIntroBanner`, inbox detail body | `Wrapper.vue:28`, `InboxChannels.vue:62`, `teams/Create/Index.vue:26`, `teams/Edit/Index.vue:30`, `macros/MacroEditor.vue:137`, `SettingIntroBanner.vue:20`, `inbox/Settings.vue:807` |
| `max-w-3xl` (48rem) | header description line length | `BaseSettingsHeader.vue:69` |
| `max-w-2xl` (42rem) | single-column forms: general settings, profile, SAML, assignment-policy create/edit | `account/Index.vue:160`, `profile/Index.vue:231`, `security/components/SamlSettings.vue:176`, the four `assignmentPolicy/pages/*{Create,Edit}Page.vue` |
| `max-w-[40.625rem]` (650px) | contact and company detail columns | `ContactsDetailsLayout.vue:82,122`, `CompaniesDetailsLayout.vue:41,51` |
| `max-w-[67rem]` | every `PaginationFooter` | `ContactsListLayout.vue:123`, `CompaniesListLayout.vue:52`, `HelpCenterLayout.vue:124`, `captain/PageLayout.vue:237` |
| `max-w-[71rem]` | captain `PageLayout` default `containerClass` | `captain/PageLayout.vue:71` |
| `max-w-[45rem]` | captain assistant settings content | `SettingsPageLayout.vue:105` |
| `max-w-[40rem]` | onboarding | `OnboardingLayout.vue:24` |
| `max-w-4xl` | inbox detail for non-widget channels | `inbox/Settings.vue:324-326, 1413` |

### 7.2 Gutters and header heights

| Token | Value | Where |
|---|---|---|
| Page side gutter | `px-6` | `SettingsWrapper.vue:23`, `ReportsWrapper.vue:2`, every `components-next` shell's `header`/`main` |
| Wizard page gutter | `!px-6` on the page root **on top of** `px-4` from `Wrapper.vue`'s `router-view` | `Wrapper.vue:31` vs `InboxChannels.vue:62`, `teams/Create/Index.vue:26`, `macros/MacroEditor.vue:137` |
| Settings column vertical padding | `pt-4` / `pb-8` | `SettingsWrapper.vue:23` |
| Header→body gap | `gap-4` (`gap-10` on two pages) | `SettingsLayout.vue:23`; `assignmentPolicy/Index.vue:86`, `conversationWorkflow/index.vue:32` |
| Header bar height | `h-20 min-h-[3.5rem]` (`SettingsHeader`), `h-20` (campaign / help center / captain), `py-6` (contacts/companies list), `py-7` (contacts/companies detail), `pt-6 pb-5` (reports) | `SettingsHeader.vue:44`, `CampaignLayout.vue:27`, `HelpCenterLayout.vue:71`, `captain/PageLayout.vue:126`, `ContactHeader.vue:4`, `ContactsDetailsLayout.vue:84`, `ReportHeader.vue:21` |
| Title row min-height | `min-h-8` (`BaseSettingsHeader`), `min-h-10` (`ReportHeader` title span, assignment-policy breadcrumb rows) | `BaseSettingsHeader.vue:53`, `ReportHeader.vue:29`, `AgentAssignmentIndexPage.vue:99` |

### 7.3 Typography tokens the headers use

Defined as `@apply`-based utilities in `app/javascript/dashboard/assets/scss/_woot.scss:70-140`
(not in `tailwind.config.js`).

| Utility | Definition | Used by |
|---|---|---|
| `.text-heading-1` | `font-inter text-lg font-520`, `line-height: 24px`, `letter-spacing: -0.27px` | `BaseSettingsHeader.vue:56`, `SettingsSubPageHeader.vue:12`, `ReportHeader.vue:29`, `CampaignLayout.vue:28`, `OnboardingLayout.vue:54`, `ImportDetailHeader.vue:82` |
| `.text-heading-2` | `font-inter text-base font-medium`, `lh 24px` | `account/components/SectionLayout.vue:31`, `inbox/channels/WhatsappManualSetup.vue:350,423` |
| `.text-heading-3` | `font-inter text-sm font-medium`, `lh 21px` | `SettingsFieldSection.vue:19`, `SettingsToggleSection.vue` header span |
| `.text-body-main` | `font-inter text-sm font-420`, `lh 21px`, `ls -0.28px` | `BaseSettingsHeader.vue:69`, `SettingsSubPageHeader.vue:17`, `ReportHeader.vue:35`, every `#count` span |
| `.text-label-small` | `font-inter text-xs font-440` | `SettingsFieldSection.vue:30` |

**Headers that bypass the tokens and hand-roll font classes:**
`SettingsHeader.vue:46,55` (`text-2xl`, `text-xl font-medium`),
`SettingIntroBanner.vue:21` (`text-2xl … font-medium`),
`ContactHeader.vue:6` and `CompanyHeader.vue` (`text-xl font-medium`),
`captain/PageLayout.vue:137,175` (`text-xl font-medium`),
`HelpCenterLayout.vue:75,102` (`text-lg font-medium`),
`BillingHeader.vue:17,20` (`text-base font-medium`, `text-sm`),
`captain/pageComponents/settings/SettingsHeader.vue:16-17` (`text-base font-medium`, `text-sm`),
`subscription/Index.vue:354-358` (`text-xl font-medium`, `text-sm`),
`flows/FlowBuilder.vue` (`text-base font-medium`, `text-xs`),
`EmptyStateLayout.vue:51` (`text-3xl font-medium`).

---

## 8. Inconsistencies found

Severity is about the risk a visual/interaction redesign introduces if the issue is not understood
first, not about user-facing severity today.

| ID | Severity | Issue | Evidence |
|---|---|---|---|
| I-1 | high | **Four header components and one banner all render "a page title", with five different type treatments and five different prop vocabularies.** `BaseSettingsHeader` uses `title`/`description`/`linkText`; `SettingsSubPageHeader` uses `headerTitle`/`headerContent`; `SettingsHeader` uses `headerTitle`/`icon`; `ReportHeader` uses `headerTitle`/`headerDescription`/`hasBackButton`; `SettingIntroBanner` uses `headerTitle`/`headerIdentifier`/`headerContent`. Nothing is shared. | `BaseSettingsHeader.vue:9-34`; `SettingsSubPageHeader.vue:4-6`; `SettingsHeader.vue:9-27`; `ReportHeader.vue:4-17`; `SettingIntroBanner.vue:2-15` |
| I-2 | high | **`BaseSettingsHeader` renders a fragment (two sibling roots) with default `inheritAttrs`**, so no parent can style or extend it from the outside. `captain/Index.vue` already passes `icon-name="captain"` — an undeclared prop that cannot be inherited and that the component never reads, so the icon silently never renders (and Vue warns in dev). | `BaseSettingsHeader.vue:44` + `:91` (two roots, no `inheritAttrs: false`); `captain/Index.vue:136` |
| I-3 | high | **The heading level does not follow the visual level.** `BaseSettingsHeader` uses `<h1>`; `SettingsSubPageHeader` puts the same `text-heading-1` token on an `<h2>`; `ReportHeader` uses a `<span>` for the page title; `SettingIntroBanner` uses `<h2>`; `SectionLayout` uses `<h4>` for a section. Inbox detail pages therefore have **no `h1` at all**. | `BaseSettingsHeader.vue:56`; `SettingsSubPageHeader.vue:12`; `ReportHeader.vue:28`; `SettingIntroBanner.vue:21`; `account/components/SectionLayout.vue:29` |
| I-4 | high | **Nine pages hand-roll a header instead of using any shell header**, so they will not pick up a redesign of `BaseSettingsHeader`. The six `assignmentPolicy/pages/*` pages put a `Breadcrumb` directly into `SettingsLayout`'s `#header`; `subscription/Index.vue` writes its own `h1`+`p`; three WhatsApp channel pages write their own headings. | `AgentAssignmentIndexPage.vue:98-109`, `AgentAssignmentCreatePage.vue:92-96`, `AgentAssignmentEditPage.vue:262`, `AgentCapacityCreatePage.vue:72`, `AgentCapacityEditPage.vue:202`, `AgentCapacityIndexPage.vue:97`; `subscription/Index.vue:353-358`; `inbox/channels/Whatsapp.vue:177,235`, `WhatsappEmbeddedSignup.vue:207`, `WhatsappManualSetup.vue:315,350,423` |
| I-5 | high | **Breadcrumb and back-button are two unreconciled "go up" affordances.** `BaseSettingsHeader` offers `backButtonLabel` → `BackButton`; the six assignment-policy pages use `components-next/breadcrumb/Breadcrumb.vue` with hand-written `routeName` click handlers instead; `AgentAssignmentCreatePage.vue:51-64` even pushes a hard-coded URL string to work around the breadcrumb API. | `BaseSettingsHeader.vue:45-50`; `AgentAssignmentIndexPage.vue:26-43`; `AgentAssignmentCreatePage.vue:51-64` |
| I-6 | medium | **Two route-level shells and two inner shells all define page padding**, so the gutter is applied twice on wizard pages: `Wrapper.vue` puts `px-4` on the `router-view` and each wizard page root re-declares `!px-6` with `!important` to win. | `Wrapper.vue:31` vs `InboxChannels.vue:62`, `teams/Create/Index.vue:26`, `teams/Edit/Index.vue:30`, `macros/MacroEditor.vue:137` |
| I-7 | medium | **Route files pass props the shells do not declare.** `SettingsWrapper` declares only `keepAlive`, yet four route files pass `headerTitle`, `icon` and `showNewButton` to it — these land as DOM attributes on its root `div` and do nothing. `inbox.routes.js` computes and passes `fullWidth` to `Wrapper.vue`, which does not declare it either. Reading these routes gives a false impression that the shells render a title. | `SettingsWrapper.vue:5-10` vs `billing/billing.routes.js:13-17`, `captain/captain.routes.js:16-20`, `security/security.routes.js:19-23`, `subscription/subscription.routes.js:14-18`; `Wrapper.vue:5-11` vs `inbox/inbox.routes.js:40-49` |
| I-8 | medium | **`SettingsLayout`'s empty state is hard-coded, not a slot.** `isLoading` has a `loading` slot override, but the "no records" branch is a fixed `<p class="flex-1 py-20 … text-base">`, so no page can give an empty state an illustration or a call to action without bypassing the prop entirely — which is why `EmptyStateLayout.vue` and page-level empty states exist in parallel. | `SettingsLayout.vue:28-36`; `components-next/EmptyStateLayout.vue` |
| I-9 | medium | **The `tabs` slot is used for three different things.** Real tabs (`TabBar`) in attributes/automation/data; a filter bar in audit logs; a row of dropdown filter buttons in templates. Its presence also silently changes the responsive behaviour of the whole controls row (`hidden sm:flex` and `flex-row-reverse sm:flex-row` keyed off `slots.tabs`). | `attributes/Index.vue:182-187`, `automation/Index.vue:339-344`, `data/Index.vue:193-198`; `auditlogs/Index.vue:169-177`; `templates/Index.vue:358-373`; `BaseSettingsHeader.vue:96-101, 119-121` |
| I-10 | medium | **Search is hidden below `sm` on every settings page, and the help link too.** With no `tabs` slot the entire left group (search) is `hidden sm:flex`; the "Learn more" link is `hidden … sm:inline-flex`. On a phone, 18 settings pages lose both affordances with no replacement. | `BaseSettingsHeader.vue:79, 98-100, 107` |
| I-11 | medium | **`featureName` silently decides whether the help link exists, and seven of the values passed are not keys in the lookup table.** `FEATURE_HELP_URLS` has 24 keys; these passed values are absent: `automation`, `assignment-policy`, `conversation-workflow`, `slack_integration`, `linear_integration`, `notion_integration`, `shopify_integration` (the table has `shopify`, not `shopify_integration`), plus whatever `:feature-name="integrationId"` resolves to. **Automation is the live bug**: it is the only one of the seven that also passes `linkText`, so `AUTOMATION.LEARN_MORE` is translated and then never rendered. The lookup also runs once in `setup()` (`const helpURL = getHelpUrlForFeature(props.featureName)`), so it is not reactive to a `featureName` bound to async data. | `helper/featureHelper.js:1-32`; `BaseSettingsHeader.vue:40`, `:62-64, 74-80`; `automation/Index.vue:335-337`; `assignmentPolicy/Index.vue:91`, `conversationWorkflow/index.vue:37`, `integrations/Slack.vue:91`, `Linear.vue:44`, `Notion.vue:58`, `Shopify.vue:100`, `IntegrationHooks.vue:124`, `MultipleIntegrationHooks.vue:84` |
| I-12 | medium | **Wrong `featureName` on Custom roles** — it passes `feature-name="canned_responses"`, so the Custom-roles "Learn more" link points at the canned-responses help page. | `customRoles/Index.vue:142-146` |
| I-13 | low | **Wrong `loadingMessage` i18n key in two places** — billing and security reuse `ATTRIBUTES_MGMT.LOADING` for their loading copy. | `billing/ProviderIndex.vue:28`; `security/Index.vue:35` |
| I-14 | low | **`SettingsHeader.vue` carries dead code**: an `icon` prop and an `iconClass` computed that the template never renders, and `useAdmin()`/`isAdmin` that it never uses — while three route files keep passing `icon` values (`mail-inbox-all`, `flash-settings`, `people-team`). | `SettingsHeader.vue:14-17, 28-38` vs template `:42-59`; `inbox/inbox.routes.js:45`, `macros/macros.routes.js:36`, `teams/teams.routes.js:44` |
| I-15 | low | **`profile/Wrapper.vue` is dead** — no file imports it; profile routes mount `SettingsWrapper`. | `profile/Wrapper.vue`; `profile/profile.routes.js:4, 16` |
| I-16 | low | **`feature-name="macros"` is passed to `SettingsLayout`**, which declares no such prop — a copy-paste from the header below it. | `macros/Index.vue:78` vs `SettingsLayout.vue:2-19` |
| I-17 | low | **Two pages reach into `SettingsLayout` with a `class` to change its spacing or width**, instead of the layout exposing that as an option: `gap-10` on two pages, `max-w-2xl ltr:mr-auto rtl:ml-auto` on four. A redesign that changes `SettingsLayout`'s root classes silently changes those six pages. | `assignmentPolicy/Index.vue:86`, `conversationWorkflow/index.vue:32`, `AgentAssignmentCreatePage.vue:91`, `AgentAssignmentEditPage.vue:259`, `AgentCapacityCreatePage.vue:70`, `AgentCapacityEditPage.vue:199` |
| I-18 | low | **`SettingsWrapper`'s inner row is `items-start`**, so pages that declare `h-full` (every `SettingsLayout` page) are not actually stretched. Any shell that later wants a sticky footer or a full-height body has to fight this one class. | `SettingsWrapper.vue:25` vs `SettingsLayout.vue:23` |
| I-19 | low | **Six near-identical `components-next` shells duplicate the same skeleton** (`section.flex.flex-col.w-full.h-full.overflow-hidden.bg-n-surface-1` + `header.sticky.top-0.z-10.px-6` + `main.flex-1.px-6.overflow-y-auto` + sticky `PaginationFooter class="max-w-[67rem]"`) with no shared base, and they disagree on header height (`h-20` vs `py-6` vs `py-7`), z-index (`z-10` vs `z-20`) and body padding (`py-3` vs `py-4`). | `CampaignLayout.vue:24-56`, `CampaignAnalyticsLayout.vue:15-31`, `HelpCenterLayout.vue:66-131`, `captain/PageLayout.vue:122-243`, `ContactsListLayout.vue:80-129`, `CompaniesListLayout.vue:28-57`; `ContactHeader.vue:2` uses `z-20` |
| I-20 | low | **`inbox/Settings.vue` keeps a `settings` class on its root that has no CSS rule** anywhere under `assets/scss/`, and computes its own content max width per channel type (`max-w-7xl` / `max-w-4xl` / `max-w-2xl`) rather than using a shell prop. | `inbox/Settings.vue:783, 324-326, 888, 1413` |
| I-21 | low | **The `#count` pattern is copy-pasted verbatim into 17 pages** (`<span class="text-body-main text-n-slate-11">{{ $t('X.COUNT', { n: … }) }}</span>`), each guarded by its own hand-written `v-if` with a different truthiness test (`records?.length`, `meta.totalEntries`, `activeTab === 'import' && dataImports.length`, `!isBehindAPaywall && records?.length`). It is a de facto component that was never extracted. | `agents/Index.vue:163`, `agentBots/Index.vue:114`, `attributes/Index.vue:177`, `auditlogs/Index.vue:179`, `automation/Index.vue:346`, `canned/Index.vue:157`, `customRoles/Index.vue:148`, `data/Index.vue:200`, `inbox/Index.vue:109`, `labels/Index.vue:116`, `macros/Index.vue:89`, `sla/Index.vue:155`, `teams/Index.vue:99`, `templates/Index.vue:384`, `integrations/Webhooks/Index.vue:150`, `integrations/DashboardApps/Index.vue:119`, `integrations/MultipleIntegrationHooks.vue:88` |

---

## 9. What a redesign should reuse rather than rebuild

1. **`BaseSettingsHeader` is the real page-header contract** — 35 components already drive it, and
   its slot set (`title`, `description`, `meta`, `tabs`, `count`, `actions`) plus props
   (`title`, `description`, `linkText`, `featureName`, `backButtonLabel`, `searchPlaceholder`) already
   cover every header need found in settings. Re-skin this component; do not introduce a second one.
   (`routes/dashboard/settings/components/BaseSettingsHeader.vue`)
2. **`v-model:search-query` is the established search contract.** 17 pages bind it
   (`BaseSettingsHeader.vue:38`) and filter locally. Keep the model name so no page has to change.
3. **`ImportDetailHeader.vue` is the extension pattern that works** — wrap `BaseSettingsHeader` and
   override `#title` / `#description` for richer headers (live status dot, truncating title, action
   cluster). Use it as the template for the WhatsApp channel pages and the assignment-policy pages
   instead of letting them hand-roll.
   (`routes/dashboard/settings/data/components/ImportDetailHeader.vue:76-146`)
4. **`SettingsLayout`'s slot order is the page contract** — `header`, `preBody`, `loading`, `body`,
   default (dialogs). 36 pages depend on it, including the un-named default slot that the file itself
   warns not to delete. Keep all five, and add the missing `emptyState` slot rather than replacing the
   `noRecordsFound` prop. (`SettingsLayout.vue:24-39`)
5. **The typography utilities already exist** — `.text-heading-1/2/3`, `.text-body-main`,
   `.text-label`, `.text-label-small`, `.text-button` in `assets/scss/_woot.scss:70-140`. Every
   hand-rolled `text-xl font-medium` / `text-2xl` in a header (listed in §7.3) should move onto these
   instead of new one-off classes.
6. **`max-w-5xl` + `px-6` is the settled settings/reports/list page measure** and
   `max-w-2xl ltr:mr-auto rtl:ml-auto` is the settled single-column form measure. Both already appear
   in six-plus places each; a redesign should promote them to the shell rather than keep them as
   per-page classes.
7. **`BackButton`, `Breadcrumb`, `TabBar`, `PaginationFooter`, `EmptyStateLayout`, `CardLayout`,
   `SectionLayout` and `components-next/Settings/*` already exist** and are the primitives the shells
   compose. `BackButton` already handles both an explicit `backUrl` and `router.go(-1)`, and already
   falls back to `$t('GENERAL_SETTINGS.BACK')`. (`components/widgets/BackButton.vue:18-36`)
8. **`CustomBrandPolicyWrapper` is the existing white-label gate** used by the header's help link;
   any new header affordance that mentions the product should reuse it, not a new flag.
   (`BaseSettingsHeader.vue:73-87`)
9. **The six `components-next` shells share one skeleton already** — a redesign should extract that
   skeleton (`section` + sticky `header` + scrolling `main` + sticky footer, `max-w-5xl`,
   `max-w-[67rem]` footer) once and have `CampaignLayout`, `CampaignAnalyticsLayout`,
   `ContactsListLayout`, `CompaniesListLayout`, `HelpCenterLayout` and `captain/PageLayout` consume
   it, rather than restyling six copies.
10. **Do not drop any of these at any breakpoint, because they already exist today:** per-page search,
    per-page "Learn more" help link, per-page item count, the count/actions divider, the back button,
    the `meta` line (templates' last-sync time), `TabBar` tabs, audit-log filters in the header,
    the assignment-policy breadcrumbs, the inbox-detail tab strip in `SettingIntroBanner`, the
    report download buttons, and the `has-back-button` affordance on the six `*ReportsShow` pages.
