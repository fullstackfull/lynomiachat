# Audit — Data Display: Tables, Badges, Cards, Avatars, States

**Date:** 2026-10-03
**Scope:** `components-next/table`, `components-next/pagination`, `components-next/avatar`, `components-next/label`, `components-next/banner`, `components-next/EmptyStateLayout.vue`, `components-next/CardLayout.vue`, `components-next/spinner`, every skeleton/loading component, and a whole-dashboard census of status-pill / badge markup.
**Mode:** read-only inventory. This file is the **baseline** that later modernization work is checked against. Nothing below is a proposal. Every assertion carries a `file:line` read from source.

Paths are relative to `/home/user/lynomiachat/app/javascript/dashboard/` unless prefixed otherwise.

---

## 0. Executive summary of what exists

| Area | Canonical component | Competing implementations | Verdict |
|---|---|---|---|
| Tables | `components-next/table/BaseTable.vue` (15 production call sites) | 5 others: legacy TanStack `components/table/Table.vue`, `reports/components/CsatTable.vue`, `reports/components/SLA/SLATable.vue`, `components-next/AssignmentPolicy/components/DataTable.vue`, `components/widgets/TableHeaderCell.vue` + `TableFooter.vue` | fragmented |
| Pagination | `components-next/pagination/PaginationFooter.vue` (14 call sites) | `components/table/Pagination.vue` (TanStack), `components/widgets/TableFooter.vue` | 3 systems |
| Avatars | `components-next/avatar/Avatar.vue` (83 call sites, 56 files) | none — fully consolidated | healthy |
| Label chips | `components-next/label/Label.vue` (17 call sites) | legacy `components/ui/Label.vue` (4 files, different color ramp) | 2 systems |
| Banners | `components-next/banner/Banner.vue` (28 call sites) | legacy `components/ui/Banner.vue` (marked DEPRECIATED, 5 files) + 3 hand-rolled banners | 2 + 3 |
| Cards | `components-next/CardLayout.vue` (21 call sites) | — | healthy |
| Empty states | `components-next/EmptyStateLayout.vue` (15 call sites) | ≥4 bespoke in-page empty states | fragmented |
| Spinner | `components-next/spinner/Spinner.vue` (89 call sites) | `shared/components/Spinner.vue` (22 files, SCSS) + 3 dot-bounce loaders | 2 + 3 |
| Skeletons | **none** — no skeleton component exists | ~20 hand-rolled `bg-n-slate-3 animate-pulse` blocks + `CsatTableLoader.vue` + `shared/components/ArticleSkeletonLoader.vue` | no system |
| **Status badges** | **none — there is no Badge component** | **60 distinct treatments** (section 10) | **no system** |

The single biggest finding: **status pills are not a component anywhere in this codebase.** There are exactly two small per-domain badge components (`CallStatusBadge`, `DeliveryStatusBadge`) and 58 other distinct inline treatments. Section 10 is the raw material for a unified badge system.

---

## 1. File inventory

| Component | File | LOC | Story | Spec |
|---|---|---|---|---|
| BaseTable | `components-next/table/BaseTable.vue` | 60 | `table/BaseTable.story.vue` | — |
| BaseTableRow | `components-next/table/BaseTableRow.vue` | 13 | (in story) | — |
| BaseTableCell | `components-next/table/BaseTableCell.vue` | 22 | (in story) | — |
| table barrel | `components-next/table/index.js` | 3 | — | — |
| PaginationFooter | `components-next/pagination/PaginationFooter.vue` | 130 | `pagination/PaginationFooter.story.vue` | — |
| Avatar | `components-next/avatar/Avatar.vue` | 304 | `avatar/Avatar.story.vue` | `avatar/specs/Avatar.spec.js` |
| Label | `components-next/label/Label.vue` | 71 | `label/story/Label.story.vue` | — |
| LabelItem | `components-next/label/LabelItem.vue` | 57 | — | — |
| AddLabel | `components-next/label/AddLabel.vue` | 49 | `label/story/AddLabel.story.vue` | — |
| Banner | `components-next/banner/Banner.vue` | 83 | **none** | — |
| EmptyStateLayout | `components-next/EmptyStateLayout.vue` | 68 | **none** | — |
| CardLayout | `components-next/CardLayout.vue` | 37 | **none** | — |
| Spinner | `components-next/spinner/Spinner.vue` | 25 | `spinner/Spinner.story.vue` | — |

### Adjacent / legacy files in scope

| File | Role |
|---|---|
| `components/table/Table.vue` | TanStack-driven table (sortable, sticky header, 2 densities) |
| `components/table/BaseCell.vue` | truncating cell with `---` fallback, RTL-aware |
| `components/table/SortButton.vue` | chevron sort indicator |
| `components/table/Pagination.vue` | TanStack pagination + page-size selector |
| `components/widgets/TableHeaderCell.vue` | grid-based header cell (`col-span-N`) |
| `components/widgets/TableFooter.vue` | legacy results + pagination footer |
| `components/ui/Label.vue` | legacy label chip, SCSS color schemes |
| `components/ui/Banner.vue` | **marked `<!-- DEPRECIATED -->`** at line 1 |
| `components-next/AssignmentPolicy/components/DataTable.vue` | CSS-grid "table" with its own loading + empty + hover |
| `routes/dashboard/settings/reports/components/CsatTable.vue` | bespoke `<table>` with hover + expandable rows |
| `routes/dashboard/settings/reports/components/CsatTableLoader.vue` | the only purpose-built table skeleton |
| `shared/components/Spinner.vue` | SCSS keyframe spinner, 3 sizes, 3 color schemes |
| `shared/components/ArticleSkeletonLoader.vue` | article skeleton (`animate-loader-pulse`) |

---

## 2. Tables — `components-next/table`

### 2.1 BaseTable anatomy (exact classes)

| Element | File:line | Classes |
|---|---|---|
| wrapper `div` | `table/BaseTable.vue:30` | `w-full` |
| `table` | `table/BaseTable.vue:31` | `min-w-full table-auto divide-y divide-n-weak` |
| `thead` | `table/BaseTable.vue:32` | `border-t border-n-weak` |
| `th` | `table/BaseTable.vue:37` | `py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12 capitalize` |
| `tbody` | `table/BaseTable.vue:45` | `divide-y divide-n-weak text-n-slate-11` |
| empty `td` | `table/BaseTable.vue:52` | `py-20 text-center text-body-main !text-base text-n-slate-11` |
| `tr` (BaseTableRow) | `table/BaseTableRow.vue:11` | **no classes at all** |
| `td` (BaseTableCell) | `table/BaseTableCell.vue:13` | `py-3 ltr:pr-4 rtl:pl-4 text-body-main` + one of `text-start` / `text-center` / `text-end` (`:15-17`) |

### 2.2 Props and slots

| Component | Prop | Type / default | File:line | Notes |
|---|---|---|---|---|
| BaseTable | `headers` | `Array` / `[]` | `BaseTable.vue:5-8` | plain strings, rendered with `capitalize` |
| BaseTable | `items` | `Array` / `[]` | `BaseTable.vue:9-12` | used only for `.length` checks |
| BaseTable | `noDataMessage` | `String` / `''` | `BaseTable.vue:13-16` | |
| BaseTable | `loading` | `Boolean` / `false` | `BaseTable.vue:17-20` | **dead prop — no call site passes it** (verified across `routes/` + `components-next/`) |
| BaseTableRow | `item` | `Object`, **required** | `BaseTableRow.vue:3-6` | passed straight back out through the default slot (`:12`); the component itself never reads it |
| BaseTableCell | `align` | `String` / `'start'`, validator `start\|center\|end` | `BaseTableCell.vue:3-7` | |

| Slot | File:line | Shape |
|---|---|---|
| `header-${index}` | `BaseTable.vue:39` | **0-indexed**, scoped `{ header }` |
| `row` | `BaseTable.vue:47` | scoped `{ items }` — the parent must do its own `v-for` |
| BaseTableRow default | `BaseTableRow.vue:12` | scoped `{ item }` |
| BaseTableCell default | `BaseTableCell.vue:20` | — |

### 2.3 Capability matrix — what BaseTable does and does not do

| Capability | State today | Evidence |
|---|---|---|
| **Header height** | Not fixed. `py-4` on `th` + `text-heading-3` (14px/21px line-height, `_woot.scss:116-120`) ⇒ ~53px content box. No `h-*`. | `BaseTable.vue:37` |
| **Row density** | One density only: `py-3` on every cell ⇒ ~45px for single-line content. No compact/relaxed switch (the legacy `Table.vue` *does* have one — `components/table/Table.vue:21`, `:66`). | `BaseTableCell.vue:13` |
| **Hover state** | **None.** `BaseTableRow` renders a bare `<tr>` with no classes, and no call site adds hover classes to it. | `BaseTableRow.vue:11`; verified across all 16 row-host files |
| **Selected / active row** | **None.** No `selected`/`active` prop, no `aria-selected`. The only selection UI is hand-built: `teams/AgentSelector.vue:99-106` puts a `Checkbox` in the first cell and `:85-94` puts a select-all `Checkbox` in `#header-0`, with the count rendered in a separate sticky bar (`:135-145`). Selecting a row produces **no visual change to the row**. | `teams/AgentSelector.vue` |
| **Sortable columns** | **None.** No sort prop, no sort emit, no indicator. Headers are inert strings. Sorting exists only in the legacy TanStack table: click handler `components/table/Table.vue:45`, indicator `components/table/SortButton.vue:9-13` (`i-lucide-chevrons-up-down` / `chevron-up` / `chevron-down`). | `BaseTable.vue:34-42` |
| **Action column** | Convention, not API. Every table hand-writes a last cell: `<BaseTableCell align="end" class="w-24">` wrapping `<div class="flex justify-end gap-3">` of icon `Button`s. Width varies: `w-24` (`canned/Index.vue:224`, `agentBots/Index.vue:172`, `flows/Index.vue:265`, `customRoles/component/CustomRoleTableBody.vue:55`, `macros/MacrosTableRow.vue:94`, `integrations/DashboardApps/DashboardAppsRow.vue:36`, `integrations/Webhooks/WebhookRow.vue:60`), `w-12` (`sla/Index.vue:284`, `integrations/MultipleIntegrationHooks.vue:127`), unset (`labels/Index.vue:165`, `automation/AutomationRuleRow.vue:74`). | as cited |
| **Empty row** | A single `<tr><td colspan>` rendered **only** when `noDataMessage` is truthy **and** `loading` is false. Padding `py-20`, centered, and it overrides its own type scale with `text-body-main !text-base`. | `BaseTable.vue:49-56` |
| **Header visibility when empty** | `showHeaders` requires `items.length > 0` (`:24-26`), so **the header row disappears entirely in the empty state**. The empty table is a bare centered sentence with a top border only. | `BaseTable.vue:24-26, 32` |
| **Loading handling** | BaseTable renders **no loading UI**. The `loading` prop only suppresses the empty row, and nothing passes it. Call sites handle loading *outside* the table — or not at all. The only table skeleton in the repo is `reports/components/CsatTableLoader.vue` (hand-built, not reusable by BaseTable). | `BaseTable.vue:17-20, 49` |
| **Narrow widths** | `min-w-full table-auto` with no wrapper overflow. **Only one of 15 call sites** wraps the table in a horizontal scroller: `data/components/ImportLogSection.vue:90` (`<div class="overflow-x-auto">`). Everywhere else the table squeezes `table-auto` columns until text wraps or the page scrolls. Cells opt into truncation ad hoc with `class="max-w-0"` + an inner `truncate` (`flows/Index.vue:225`, `macros/MacrosTableRow.vue:52`, `agentBots/Index.vue:139`, `canned/Index.vue:213`, `automation/AutomationRuleRow.vue:42`). There is no responsive column-hiding, no stacked-card fallback, no sticky first column. | as cited |
| **Sticky header** | **None** in BaseTable. The legacy table has it: `components/table/Table.vue:31` (`sticky top-0 z-10 bg-n-slate-1`). | — |
| **Row click / navigation** | Not an API. Where rows are clickable, the click target is a `<button>` *inside* a cell (`flows/Index.vue:226-238`), so the row itself is not a hit target and has no affordance. | `flows/Index.vue:226` |
| **Zebra striping** | None. Separation is `divide-y divide-n-weak` only. | `BaseTable.vue:31, 45` |

### 2.4 The 15 production BaseTable call sites

| Surface | File:line | Columns | Empty msg | Action col | Pagination |
|---|---|---|---|---|---|
| Agent bots | `routes/dashboard/settings/agentBots/Index.vue:129` | 3 | yes `:132` | `w-24` `:172` | no |
| Audit logs | `routes/dashboard/settings/auditlogs/Index.vue:198` | 3 | **no** | none | `PaginationFooter` `:236` (`class="!px-0"`) |
| Automation | `routes/dashboard/settings/automation/Index.vue:404` | 4 (row in `AutomationRuleRow.vue`) | yes `:408` | unset `:74` | no |
| Canned responses | `routes/dashboard/settings/canned/Index.vue:173` | 2 | yes `:176` | `w-24` `:224` | no |
| Custom roles | `routes/dashboard/settings/customRoles/Index.vue:166` | 4 (row in `CustomRoleTableBody.vue`) | yes `:170` | `w-24` `:55` | no |
| Import logs | `routes/dashboard/settings/data/components/ImportLogSection.vue:91` | slot-driven | handled outside `:85-90` | none | no |
| Flows (Lynomia) | `routes/dashboard/settings/flows/Index.vue:221` | 4 | bespoke empty state instead `:194` | `w-24` `:265` | no |
| Dashboard apps | `routes/dashboard/settings/integrations/DashboardApps/Index.vue:144` | 3 (row in `DashboardAppsRow.vue`) | handled outside | `w-24` `:36` | no |
| Integration hooks | `routes/dashboard/settings/integrations/MultipleIntegrationHooks.vue:103` | 2–3 (conditional col `:121`) | yes `:107` | `w-12` `:127` | no |
| Webhooks | `routes/dashboard/settings/integrations/Webhooks/Index.vue:169` | 2 (row in `WebhookRow.vue`) | yes `:173` | `w-24` `:60` | no |
| Labels | `routes/dashboard/settings/labels/Index.vue:131` | 4 | yes `:134` | unset `:165` | no |
| Macros | `routes/dashboard/settings/macros/Index.vue:102` | 5 (row in `MacrosTableRow.vue`) | yes `:105` | `w-24` `:94` | no |
| SLA | `routes/dashboard/settings/sla/Index.vue:176` | 7 | yes `:180` | `w-12` `:284` | no |
| Team agent picker | `routes/dashboard/settings/teams/AgentSelector.vue:84` | 3 + checkbox col | **no** | none (own sticky bar `:135`) | no |
| Campaign delivery | `components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue:86` | 4 | yes `:89` | none | parent page `WhatsAppCampaignAnalyticsPage.vue:491` |

Only **SLA** uses the `header-${index}` slot, and it uses three of them (`sla/Index.vue:189`, `:201`, `:213`) purely to attach an info tooltip to the column title.

Only **ImportLogSection** passes a `class` to `BaseTable`, and it does so to patch the component's internals from outside:
`[&_td:first-child]:ps-4 [&_th:first-child]:ps-4 [&_th]:text-n-slate-11 [&_thead]:border-t-0` — `data/components/ImportLogSection.vue:92`. That single string overrides the table's start padding, header color and top border, i.e. the component's defaults did not fit and there was no prop to express it.

### 2.5 Competing table implementations

| Implementation | File | Density | Hover | Sort | Sticky header | Loading | Empty |
|---|---|---|---|---|---|---|---|
| BaseTable | `components-next/table/BaseTable.vue` | one (`py-3`) | no | no | no | none | centered `td`, header hidden |
| Legacy TanStack | `components/table/Table.vue` | two — `relaxed` `py-4 px-5` / else `py-2 px-5` (`:66`) | no | **yes** (`:45`, `SortButton.vue`) | **yes** (`:31`) | caller | caller |
| CSAT table | `reports/components/CsatTable.vue:150-176` | `py-4 px-5` | **yes** `group hover:bg-n-slate-2 dark:hover:bg-n-solid-3 transition-colors` (`:168`) + expanded-row state `bg-n-slate-2 dark:bg-n-solid-3` (`:170`) | no | no | **`CsatTableLoader`** (`:147`) | `v-else-if="tableData.length"` (`:149`) |
| SLA report table | `reports/components/SLA/SLATable.vue` | custom | — | no | no | `shared/components/Spinner.vue` (`:5`) | `shouldShowFooter` logic (`:43-47`) |
| AssignmentPolicy DataTable | `components-next/AssignmentPolicy/components/DataTable.vue` | CSS grid, `h-[3.25rem]` rows (`:52`) | **yes** on the inner button `hover:bg-n-alpha-1 dark:hover:bg-n-alpha-2` (`:56`) + hover-revealed external-link icon (`:77-80`) + `group-hover:text-n-blue-11` (`:73`) | no | n/a | **`Spinner`** (`:34-39`) | **dashed-border block** `custom-dashed-border` (`:40-47`) |
| Grid header/footer pair | `components/widgets/TableHeaderCell.vue` / `TableFooter.vue` | `py-2`, `text-xs uppercase text-n-slate-11` (`TableHeaderCell.vue:32`) | — | no | no | — | `isFooterVisible` (`TableFooter.vue:26`) |

Three different header type treatments coexist: `text-heading-3 ... capitalize` (BaseTable), `font-medium text-sm text-n-slate-12` (legacy `Table.vue:43` and `CsatTable.vue:159`), and `text-xs font-medium uppercase text-n-slate-11` (`TableHeaderCell.vue:32`).

---

## 3. Pagination

### 3.1 `components-next/pagination/PaginationFooter.vue`

| Aspect | Detail | File:line |
|---|---|---|
| Props | `currentPage` (Number, required), `totalItems` (Number, required), `itemsPerPage` (Number, default **16**), `currentPageInfo` (String, i18n key override) | `:8-25` |
| Emit | `update:currentPage` | `:26` |
| Container | `flex justify-between h-[3.375rem] w-full border-t border-n-weak mx-auto bg-n-surface-1 py-3 px-6 items-center` | `:74` |
| Top fade | `before:absolute before:inset-x-0 before:-top-4 before:bg-gradient-to-t before:from-n-surface-1 before:from-0% before:to-transparent before:h-4 before:pointer-events-none` | `:74` |
| Controls | 4 ghost/slate/sm `Button`s forced to `!w-8 !h-6`: first, prev, next, last | `:82-127` |
| Current page token | `px-3 tabular-nums py-0.5 font-420 bg-n-input-background text-body-main text-n-slate-12 rounded-md` | `:102` |
| Number formatting | `useNumberFormatter` — `formatFullNumber` for page/range, `formatCompactNumber` for totals | `:28, 52-55, 65` |
| i18n | `PAGINATION_FOOTER.SHOWING` (pluralized on `totalItems`) and `PAGINATION_FOOTER.CURRENT_PAGE_INFO` | `:48, 62` |
| No page-number list | Only prev/next/first/last — no numbered pages | `:82-127` |
| No page-size selector | — | — |

14 call sites across 9 files (`Contacts/ContactsListLayout.vue:119`, `Companies/CompaniesListLayout.vue:47`, `Companies/CompanyDetail/CompanyContactsSidebar.vue:343`, `HelpCenter/HelpCenterLayout.vue:120`, `captain/PageLayout.vue:233`, `captain/pageComponents/document/DocumentDetails.vue:408`, `routes/dashboard/calls/pages/CallsIndex.vue:168`, `routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:491`, `routes/dashboard/settings/auditlogs/Index.vue:236`). Layout components gate it behind a `showPaginationFooter` prop (`Contacts/ContactsListLayout.vue:13`, `HelpCenter/HelpCenterLayout.vue:29`, `captain/PageLayout.vue:61`, `Companies/CompaniesListLayout.vue:12`).

### 3.2 `components/table/Pagination.vue` (legacy, TanStack)

Has what the next-gen one lacks: a **numbered page window** of 3 (`:60-68`), and an optional **page-size selector** 10/20/50/100 via `FilterSelect` (`:26-43`, `:115-122`). Active page is signalled by `:color="page == currentPage ? 'blue' : 'slate'"` plus `text-n-brand` (`:147`, `:153`). Copy key is a different namespace: `REPORT.PAGINATION.RESULTS` (`:112`) vs `PAGINATION_FOOTER.SHOWING`. Used by `reports/components/CsatTable.vue:9`, `reports/components/overview/AgentTable.vue:15`, `reports/components/overview/TeamTable.vue:15`.

### 3.3 `components/widgets/TableFooter.vue` (legacy, third system)

Props `currentPage` / `pageSize` (default 25) / `totalCount` (`:5-18`), container `flex items-center justify-between h-12 px-6` (`:35`), delegates to `TableFooterResults.vue` + `TableFooterPagination.vue`. Default page size differs from both others (25 vs 16 vs 10).

---

## 4. Avatar — `components-next/avatar/Avatar.vue`

### 4.1 Props

| Prop | Type / default | File:line |
|---|---|---|
| `src` | String / `''` | `:11-14` |
| `name` | String, **required** | `:15-18` — `''` is the sentinel for "no name" (`:84`) |
| `size` | Number / `32` | `:19-22` |
| `allowUpload` | Boolean / `false` | `:23-26` |
| `roundedFull` | Boolean / `false` | `:27-30` |
| `status` | String / `null`, validated against `wootConstants.AVAILABILITY_STATUS_KEYS` | `:31-36` |
| `inbox` | Object / `null` | `:37-40` |
| `iconName` | String / `null` | `:41-44` |
| `hideOfflineStatus` | Boolean / `false` | `:45-48` |

Emits `upload` (`{ file, url }`) and `delete` (`:51`, `:171`, `:182`). Slots: `badge({ size })` (`:204`), `overlay({ size, handleUpload, fileInputRef, handleImageUpload })` (`:274-281`).

### 4.2 Behaviour

| Feature | Implementation | File:line |
|---|---|---|
| Initials | 1 word ⇒ 1 letter, else first letter of first 2 words, uppercased, emoji stripped via `removeEmoji` | `:86-96` |
| Deterministic color | `name.length % 6` indexes a 6-pair palette; light + dark variants passed as `--dark-bg` / `--dark-text` CSS vars and applied with `dark:!bg-[var(--dark-bg)] dark:!text-[var(--dark-text)]` | `:58-76`, `:98-108`, `:138-139`, `:236-237` |
| Palette | 6 light pairs (`#FBDCEF/#C2298A`, `#FFE0BB/#99543A`, `#E8E8E8/#60646C`, `#CCF3EA/#008573`, `#EBEBFE/#4747C2`, `#E1E9FF/#3A5BC7`) + 6 dark pairs + a `default` `{bg:#E8E8E8,text:#60646C}` — **raw hex, not design tokens** | `:58-76` |
| Border radius ladder | `roundedFull` ⇒ `rounded-full`; else ≤16 `rounded`, ≤24 `rounded-md`, ≤32 `rounded-lg`, ≤48 `rounded-xl`, else `rounded-2xl` ("approximates 25% of size") | `:115-126` |
| Presence dot | `online: bg-n-teal-10`, `busy: bg-n-amber-10`, `offline: bg-n-slate-10` (offline omitted when `hideOfflineStatus`); `absolute z-20 border rounded-full border-n-slate-3` | `:78-82`, `:205-210` |
| Dot geometry | `max(size*0.35, 8)px`, positioned `top/left: size - badgeSize/1.1` | `:142-150` |
| Channel badge | When `inbox` is set and no `status`, a `ChannelIcon` in a `rounded-full bg-n-solid-1` puck at the same coords | `:211-217` |
| Image fallback chain | `img` → `error` sets `isImageValid=false` → initials → `iconName` icon → `i-lucide-user` with `THUMBNAIL.AUTHOR.NOT_AVAILABLE` title. `watch(src)` resets validity. | `:160-162`, `:190-195`, `:244-271` |
| Upload overlay | `absolute inset-0 z-10 ... invisible opacity-0 bg-n-alpha-black1 group-hover/avatar:visible group-hover/avatar:opacity-100`, upload icon at `size/2` | `:282-300` |
| Delete affordance | `-top-2 ltr:-right-2 rtl:-left-2` 24px puck, `rounded-xl bg-n-solid-3 outline outline-1 outline-n-container`, hover-revealed | `:220-227` |
| Hairline | `outline outline-1 -outline-offset-1 outline-[rgb(0_0_0_/_0.03)] dark:outline-[rgb(255_255_255_/_0.04)]` | `:232` |
| Accepted uploads | `image/png, image/jpeg, image/jpg, image/gif, image/webp` | `:296` |

Spec coverage (`avatar/specs/Avatar.spec.js`): initials from 1/2/4 words, emoji stripping, icon-over-initials precedence, user-icon fallback, `alt` text, broken-image fallback, retry on `src` change.

**Adoption:** 83 call sites in 56 files. Sizes actually used, by frequency: 16 (19×), 24 (17×), 20 (12×), 48 (11×), 32 (9×), 72 (6×), 40 (6×), 64 (2×), 42 (2×), 28 (2×), and one-offs 96, 68, 34, 30, 26, 14. `rounded-full` is passed in 30 files — i.e. the squared default is overridden roughly as often as it is kept.

---

## 5. Label chips

### 5.1 `components-next/label/Label.vue`

| Aspect | Detail | File:line |
|---|---|---|
| Props | `label` (`[Object, String]`, required), `compact` (Boolean), `color` (`slate\|amber\|teal\|ruby\|blue\|iris`, default `slate`) | `:4-19` |
| Color ramp | `-2` background + `-4` outline + `-11` text. `slate` is special-cased to `bg-n-label-color outline-n-label-border text-n-slate-12` | `:21-28` |
| `n-label-color` token | `theme/colors.js:286` → `rgb(var(--label-background))`; values `247 247 247` light (`_next-colors.scss:138`) / `36 38 45` dark (`:289`) | — |
| `n-label-border` token | `theme/colors.js:287` → `rgba(var(--label-border))`; `0,0,0,0.04` light (`:139`) / `255,255,255,0.03` dark (`:290`) | — |
| Shape | `rounded-lg -outline-offset-1 outline outline-1 inline-flex items-center flex-shrink-0` | `:50` |
| Sizes | compact `px-1.5 h-6 gap-1 rounded-md` + `text-label-small`; default `px-2.5 h-8 gap-1.5 rounded-lg` + `text-label !font-420` | `:53`, `:65` |
| Per-label color dot | When `label` is an Object with `.color`, renders a swatch `rounded-sm` at `size-1.5` (compact) / `size-2` | `:40-42`, `:56-61` |
| Slots | `icon` (only when there is no `labelColor`), `action` | `:62`, `:69` |
| Tooltip | native `title` from `label.description` | `:49`, `:36-38` |

**This is the only outline-based tinting in the codebase.** Every other pill uses a solid `-3` background with no outline. 17 call sites in 11 files, including `Conversation/ConversationCard/CardLabelsV5.vue`, `Conversation/Sla/SLACardLabel.vue`, `ConversationWorkflow/AttributeListItem.vue`, `CustomAttributes/AttributeBadge.vue`, `captain/assistant/PlaygroundTestSetup.vue`, `radioCard/RadioCard.vue`, `components/ChannelSelector.vue`, `routes/dashboard/settings/integrations/IntegrationItem.vue`, `routes/dashboard/settings/sla/Index.vue`.

### 5.2 `components-next/label/LabelItem.vue`

Different shape again: `rounded-md bg-n-alpha-2 h-7` with `px-1 py-1` (`:31`), 8px `rounded-sm` color dot (`:35-37`), `text-sm text-n-slate-12` (`:38`), and a width-animated hover-revealed remove button (`w-0` → `w-6`, `transition-[width] duration-300`, `:42-43`). Hover is lifted to the parent via a `hover` emit to stop flicker on the last item (`:21-26`).

### 5.3 `components-next/label/AddLabel.vue`

Dashed add affordance: `flex items-center gap-1 px-2 py-1 rounded-md outline-dashed h-6 outline-1 outline-n-slate-6 hover:bg-n-alpha-2` (`:24`), `i-lucide-plus` + `text-sm text-n-slate-11`, opens a `DropdownMenu` with `show-search` (`:33-39`) and a `thumbnail` slot rendering `rounded-sm size-2` swatches (`:41-46`).

### 5.4 Legacy `components/ui/Label.vue`

A **different color ramp entirely**: `-5` background + `-7` border + `-12` text, per colorScheme `primary`/`secondary`/`success`/`alert`/`warning` (`:135-184`), plus `smooth` (transparent + solid border) and `dashed` (transparent + dashed border) variants (`:186-192`). Base is `font-medium text-xs rounded-[4px] gap-1 p-1 bg-n-slate-3 text-n-slate-12 border border-solid border-n-strong h-6` (`:116`), `small` is `text-xs py-0.5 px-1 leading-tight h-5` (`:118-120`). Supports arbitrary `bgColor` with `getContrastingTextColor` (`:49-53`, `:59-68`), an `href` mode (`:102`) and a close button (`:103-110`). All of it is **scoped SCSS with `@apply`**, against the Tailwind-only rule. Still used by `components/widgets/conversation/conversation/LabelSuggestion.vue`, `components/widgets/conversation/conversationCardComponents/CardLabels.vue`, `components/widgets/conversation/linear/LinearIssueItem.vue`, `routes/dashboard/conversation/labels/LabelBox.vue`.

### 5.5 Labels in the conversation list are not chips at all

`components-next/Conversation/ConversationCard/CardLabels.vue:83-91` renders each label as a bare `size-1.5 rounded-full` dot plus `text-sm text-n-slate-10` text, with a `v-resize`-driven overflow calculation (`:70`). Same data, third visual language.

---

## 6. Banner — `components-next/banner/Banner.vue`

| Aspect | Detail | File:line |
|---|---|---|
| Props | `color` (`blue\|ruby\|amber\|slate\|teal`, default `slate`), `actionLabel` (String), `isLoading` (Boolean) | `:5-20` |
| Emit | `action`, suppressed while loading | `:22`, `:50-53` |
| Container ramp | `bg-n-{c}-3 border-n-{c}-4 text-n-{c}-11 [&_.link]:text-n-{c}-11` | `:24-36` |
| Button ramp | `bg-n-{c}-4 hover:bg-n-{c}-5 text-n-{c}-11` | `:38-48` |
| Shape | `text-sm rounded-xl flex items-center justify-between gap-2 border`; padding `py-2 px-3` without action, `pl-3 p-2` with | `:58-65` |
| Action button | `px-3 py-1 w-auto grid place-content-center rounded-lg whitespace-nowrap`, swaps to `Spinner :size="16"` while loading | `:71-80` |
| `iris` | **not supported** — Label has `iris`, Banner does not | `:9-11` vs `label/Label.vue:17` |

28 call sites in 22 files. Legacy `components/ui/Banner.vue` carries `<!-- DEPRECIATED -->` and a TODO pointing at the next-gen component (`:1-2`), yet is still used by `components/app/PaymentPendingBanner.vue`, `components/app/PendingEmailVerificationBanner.vue`, `components/app/UpdateBanner.vue`, `components/widgets/conversation/MessagesView.vue`, `components/widgets/conversation/ReplyBoxBanner.vue`. Its ramp is different again (`bg-n-ruby-3 text-n-ruby-12` / `bg-n-amber-5 text-n-amber-12`, `:134-145`) and it is a full-bleed `h-12` bar, not a rounded card (`:84`).

**Three banners bypass the component and re-implement its color map inline:**

| File:line | Classes |
|---|---|
| `components/app/LowBackupCodesBanner.vue:17` | `bg-n-amber-3 border-n-amber-4 text-n-amber-11` |
| `components/app/LowBackupCodesBanner.vue:22` | `bg-n-ruby-3 border-n-ruby-4 text-n-ruby-11` |
| `components-next/captain/pageComponents/overview/InboxBanner.vue:47` | `flex items-center justify-between gap-3 px-3 py-2 text-sm border rounded-xl bg-n-amber-3 border-n-amber-4 text-n-amber-11` |
| `components-next/captain/pageComponents/overview/CoverageBanner.vue:69` | same shape but `bg-n-amber-2` — two sibling banners, two different backgrounds |

---

## 7. CardLayout — `components-next/CardLayout.vue`

| Aspect | Detail | File:line |
|---|---|---|
| Props | `layout` (String, default `'col'`; no validator), `selectable` (Boolean) | `:2-11` |
| Emit | `click` (fired from the inner content div, not the outer shell) | `:13-17`, `:30` |
| Shell | `flex flex-col w-full outline-1 outline outline-n-container -outline-offset-1 group/cardLayout rounded-xl bg-n-solid-2` | `:22` |
| Content | `flex w-full gap-3 py-5` + (`flex-col` \| `flex-row justify-between items-center`) + (`px-10 py-6` when selectable \| `px-6`) | `:24-29` |
| Slots | default, `after` (rendered outside the padded content box) | `:32`, `:35` |
| Hover / selected | **none** — no hover, no focus ring, no selected state. The `group/cardLayout` name is exported for children to hook into. | `:22` |

21 call sites in 21 files. `layout="row"` in 4, `layout="col"` in 3, default in the rest. `selectable` is used by `HelpCenter/ArticleCard/ArticleCard.vue`, `captain/assistant/DocumentCard.vue`, `captain/assistant/ResponseCard.vue`, `captain/assistant/RuleCard.vue`, `captain/assistant/ScenariosCard.vue` — all of which render their own checkbox; `selectable` only widens padding. Several cards patch the padding back out from the call site: `class="[&>div]:px-5"` in `AssignmentPolicy/AgentCapacityPolicyCard/AgentCapacityPolicyCard.vue:48`, `AssignmentPolicy/AssignmentCard/AssignmentCard.vue:20`, `AssignmentPolicy/AssignmentPolicyCard/AssignmentPolicyCard.vue:64`.

Note `py-5` on `:25` and `py-6` on `:28` are both emitted when `selectable` is true; which wins depends on Tailwind's generated order, not on intent.

---

## 8. Empty states

### 8.1 `components-next/EmptyStateLayout.vue`

| Aspect | Detail | File:line |
|---|---|---|
| Props | `title` (String, **required**), `subtitle` (String, **required**), `actionPerms` (Array), `showBackdrop` (Boolean, default `true`) | `:4-21` |
| Slots | `empty-state-item` (the ghosted backdrop), `actions` (wrapped in `<Policy :permissions="actionPerms">`) | `:35`, `:61-63` |
| Outer | `relative flex flex-col items-center justify-center w-full h-full overflow-hidden` | `:25-27` |
| Frame | `relative w-full max-w-5xl mx-auto overflow-hidden h-full max-h-[28rem]` | `:29` |
| Backdrop | `w-full h-full space-y-4 overflow-y-hidden opacity-50 pointer-events-none` | `:32-34` |
| Scrim | `absolute inset-x-0 bottom-0 bg-gradient-to-t from-n-surface-1 from-25% to-transparent` — applied only when `showBackdrop` | `:40-41` |
| No-backdrop offset | `mt-48` pushed into a `max-h-[28rem] overflow-hidden` frame | `:46-48`, `:29` |
| Typography | **hardcoded, not the typography utilities**: `text-3xl font-medium text-center text-n-slate-12` for the title (`:51`) and `text-base text-center text-n-slate-11 tracking-[0.3px]` for the subtitle (`:56`) | `:51`, `:56` |
| No icon slot | there is no illustration/icon affordance; the "visual" is the ghosted real content behind the scrim | — |

15 call sites: `Calls/CallsEmptyState.vue:20`, `Campaigns/EmptyState/{LiveChat,SMS,WhatsApp}CampaignEmptyState.vue:20`, `Contacts/EmptyState/ContactEmptyState.vue:39`, `HelpCenter/EmptyState/Article/ArticleEmptyState.vue:34`, `HelpCenter/EmptyState/Category/CategoryEmptyState.vue:19`, `HelpCenter/EmptyState/Portal/PortalEmptyState.vue:26`, `HelpCenter/Pages/LocalePage/LocalesPage.vue:89`, `captain/pageComponents/emptyStates/{AssistantPage,CustomToolsPage,DocumentPage,InboxPage,ResponsePage}EmptyState.vue`, `routes/dashboard/captain/responses/FaqSuggestions.vue:216`.

### 8.2 Bespoke empty states that bypass it

| Surface | File:line | Shape |
|---|---|---|
| Data imports — export tab | `routes/dashboard/settings/data/Index.vue:244-266` | `flex min-h-80 flex-col items-center justify-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 px-6 py-16 text-center` + `size-12 rounded-full bg-n-alpha-2` icon puck + `text-heading-2` / `text-body-main` + a "coming soon" chip |
| Data imports — no imports | `routes/dashboard/settings/data/Index.vue:269-290` | same card shape, `i-lucide-database` |
| Commerce — no stores | `routes/dashboard/settings/commerce/Index.vue:319-330` | same pattern at `min-h-60` |
| Flows (Lynomia) — no flows | `routes/dashboard/settings/flows/Index.vue:194-220` | no card, no icon: `flex flex-col items-center gap-3 py-16 text-center` + `text-base` / `text-sm` + two buttons |
| Captain FAQ review | `components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue:243` | `flex min-h-[10rem] flex-col items-center justify-center gap-3 px-4 text-center` |
| AssignmentPolicy DataTable | `components-next/AssignmentPolicy/components/DataTable.vue:40-47` | `custom-dashed-border flex items-center justify-center py-6` + `text-sm text-n-slate-11` |
| Sidebar empty group | `components-next/sidebar/SidebarGroupEmptyLeaf.vue:9` | `py-1 pl-3 text-n-slate-10 border rounded-lg border-dashed border-n-alpha-2 text-xs h-8 grid place-content-center select-none pointer-events-none` |
| BaseTable | `components-next/table/BaseTable.vue:49-56` | `py-20 text-center text-body-main !text-base` inside a `td`, with the header row suppressed |

So the dashboard currently has (at least) **four** distinct empty-state visual languages: the backdrop+scrim hero, the bordered card with an icon puck, the bare centered stack, and the dashed placeholder.

---

## 9. Loading states

### 9.1 `components-next/spinner/Spinner.vue`

Single prop `size` (Number, default 24) (`:3-6`). Renders an inline SVG arc `M21 12a9 9 0 1 1-6.219-8.56` with `animate-spin` (`:11-24`). Color comes from `currentColor`.

The stroke attributes are authored in camelCase — `strokeWidth="8"`, `strokeLinecap="round"`, `strokeLinejoin="round"` (`:18-20`). These are not valid SVG attribute names (SVG wants `stroke-width`, `stroke-linecap`, `stroke-linejoin`), so they are set verbatim on the element and ignored; the arc renders at the SVG default stroke width of 1 rather than the authored 8. 89 call sites in 77 files are affected.

### 9.2 `shared/components/Spinner.vue` (second system)

Options-API + scoped SCSS. Props `size` (String: `small` / `tiny` / `message` / default) and `colorScheme` (`primary` → `before:!border-t-n-brand`, `warning` → `before:!border-t-n-amber-6`, `success` → `before:!border-t-n-teal-9`) (`:3-28`). The spinner itself is a `::before` ring: `border-n-slate-10 border-2 border-solid ... rounded-full border-t-n-strong ... animate-[spinner_0.9s_linear_infinite]` (`:48`). Sizes 24px default / 16px `small` / 10px `tiny` (`:45`, `:59-73`). Used in 22 files including `reports/components/SLA/SLATable.vue`, `reports/components/overview/AgentTable.vue`, `reports/components/overview/TeamTable.vue`, `reports/components/overview/MetricCard.vue`, `settings/billing/Index.vue`, `settings/teams/Edit/EditTeam.vue`.

### 9.3 Dot-bounce loaders (third family)

| File:line | Treatment |
|---|---|
| `components-next/copilot/CopilotLoader.vue:13-18` | 3× `w-2 h-2 rounded-full bg-n-iris-9 animate-bounce` with `[animation-delay:-0.3s]` / `-0.15s` / none |
| `components-next/captain/assistant/MessageList.vue:98-103` | 3× `w-2 h-2 rounded-full bg-n-iris-10 animate-bounce` with `0.2s` / `0.4s` delays |
| `components/widgets/AILoader.vue:33` | `bg-n-iris-11 inline-block size-1.5 ... rounded-full` (SCSS) |
| `components/widgets/conversation/copilot/CaptainLoader.vue` | separate copilot loader |

### 9.4 Skeletons — there is no skeleton component

The convention is `bg-n-slate-3 animate-pulse` on a sized `rounded` div, hand-written at each site.

| File:line | What is skeletonised |
|---|---|
| `reports/components/CsatTableLoader.vue:14-32` | the only table-shaped skeleton: a 5-cell header row + N body rows with `size-8 rounded-full` avatar placeholders and a `h-7 w-24 rounded-lg` chip placeholder |
| `reports/components/CsatMetricCard.vue:35` | `w-16 h-8 rounded-md` |
| `reports/components/CsatRatingDistribution.vue:48, 53` | `h-6 w-full rounded-full`, `h-4 w-20 rounded` |
| `reports/components/SLA/SLAMetricCard.vue:40` | `w-12 h-6 mb-0.5 rounded-md` |
| `Campaigns/.../CampaignMetricCard.vue:37-38` | `w-20 rounded h-9`, `w-10 h-5 rounded` |
| `Campaigns/.../CampaignDeliveryBreakdown.vue:105` | `w-full h-2 rounded-full` |
| `captain/pageComponents/overview/MetricCard.vue:134-135` | identical pair to CampaignMetricCard |
| `captain/pageComponents/overview/WelcomeCard.vue:86-90` | 4 text lines at `w-full` / `w-11/12` / `w-4/6` / `w-5/6` |
| `captain/.../overview/v2/OverviewSummaryCard.vue:116-117` | `h-4` lines |
| `captain/.../overview/v2/ProgressMetric.vue:42` | `h-[0.5625rem] rounded-full` |
| `captain/.../overview/v2/ResolutionFlowCard.vue:93, 122` | `h-[16.25rem] rounded-lg`, `h-[1.3125rem] rounded` |
| `captain/.../overview/v2/ResolutionTrendCard.vue:195` | `h-[14.5rem] rounded-lg` |
| `captain/.../response/FaqSuggestionReviewDialog.vue:219` | a whole card skeleton with `outline outline-1 outline-n-weak bg-n-solid-2 p-3` |
| `combobox/ReorderableMultiSelect.vue:179, 184` | `bg-n-alpha-3` (different base color) |
| `shared/components/ArticleSkeletonLoader.vue:3-24` | `bg-n-slate-4 dark:bg-n-slate-6` + **`animate-loader-pulse`** (a different animation) |
| `widget/components/pageComponents/Home/Article/SkeletonLoader.vue:3-11` | widget-side article skeleton |
| `superadmin_pages/views/dashboard/Index.vue:63, 73` | `bg-woot-100` (pre-token palette) |

Three skeleton base colors (`bg-n-slate-3`, `bg-n-slate-4/dark:bg-n-slate-6`, `bg-n-alpha-3`, `bg-woot-100`) and two animations (`animate-pulse`, `animate-loader-pulse`).

### 9.5 Progress bars

| File:line | Treatment |
|---|---|
| `routes/dashboard/settings/data/components/ImportProgress.vue:87-95` | track `h-1.5 w-full overflow-hidden rounded-full bg-n-alpha-2`, fill `h-full rounded-full bg-n-brand transition-all duration-500` |
| `Campaigns/.../CampaignDeliveryBreakdown.vue:117` | `w-full h-2 rounded-full bg-n-alpha-2` |
| `captain/.../overview/v2/ProgressMetric.vue:42` | `h-[0.5625rem] rounded-full` |
| `routes/dashboard/settings/billing/components/BillingMeter.vue` | third meter implementation |

---

## 10. Status / badge census — every distinct treatment

This is the exhaustive raw material for a unified badge system. Rows are grouped by how the treatment is built, not by domain.

### 10.A The two actual badge components

| # | Component | File:line | States rendered | Shape | Color ramp |
|---|---|---|---|---|---|
| 1 | `CallStatusBadge` | `components-next/Calls/CallStatusBadge.vue:16-41`, shape `:48` | `ongoing` teal, `incoming` slate, `outgoing` slate, `missed` ruby, `no_reply` amber, `failed` ruby — each with a phone icon | `inline-flex items-center justify-center w-20 gap-1.5 h-6 px-1 rounded-md text-label-small shrink-0` (**fixed `w-20`**) | `bg-n-{c}-3 text-n-{c}-11` |
| 2 | `DeliveryStatusBadge` | `components-next/Campaigns/Pages/CampaignAnalyticsPage/DeliveryStatusBadge.vue:14-21`, shape `:35` | `queued` slate, `sent` blue, `delivered` teal, `read` **iris**, `failed` ruby, `skipped` amber; unknown falls back to `queued` styling but shows the raw string (`:29`) | `inline-flex items-center h-6 px-2 rounded-md text-xs font-medium whitespace-nowrap` (no icon) | `bg-n-{c}-3 text-n-{c}-11` |

Both use the same `-3/-11` ramp but differ in width policy, padding, icon support and type class (`text-label-small` vs `text-xs font-medium`).

### 10.B Status maps defined in components / helpers

| # | Source | File:line | States and colors |
|---|---|---|---|
| 3 | Commerce order status | `components/widgets/conversation/commerce/CommerceOrderItem.vue:37-47` | `completed`/`delivered` teal-3, `processing`/`shipped` blue-3, `pending`/`on_hold` amber-3, `cancelled`/`refunded` slate-3, `failed` ruby-3; all `text-n-{c}-11` |
| 4 | Commerce payment status | `CommerceOrderItem.vue:48-53` | `paid` teal-3, `unpaid`/`partially_paid` amber-3, `failed` ruby-3 |
| 5 | Commerce neutral fallback | `CommerceOrderItem.vue:54` | `NEUTRAL_BADGE = bg-n-slate-3 text-n-slate-11`; rendered shape `px-1.5 py-0.5 rounded-md text-label-small` (`:129`, `:135`) |
| 6 | Shopify financial status | `components/widgets/conversation/ShopifyOrderItem.vue:26-31` | **only** `paid: bg-n-teal-5 text-n-teal-12` mapped; fallback `bg-n-solid-3 text-n-slate-12`. Shape `text-xs px-2 py-1 rounded capitalize truncate` (`:81`) — the only `rounded` (4px) pill |
| 7 | Shopify fulfillment status | `ShopifyOrderItem.vue:53-60` | text-only tone: `fulfilled` teal-9, `partial` amber-9, `unfulfilled` ruby-9, fallback slate-11 — **`-9` text on surface, not a pill** |
| 8 | WhatsApp template status | `routes/dashboard/settings/templates/templateUtils.js:119-129` | `approved` teal-3, `pending` amber-3, `rejected` ruby-3, `paused` amber-3, `disabled` `bg-n-alpha-2 text-n-slate-11`, fallback = `disabled` |
| 9 | …rendered in TemplateCard | `routes/dashboard/settings/templates/TemplateCard.vue:59-60` | `inline-flex shrink-0 px-2 py-0.5 text-xs font-medium rounded-md` |
| 10 | …rendered in TemplatePreviewDrawer | `routes/dashboard/settings/templates/TemplatePreviewDrawer.vue:96-97` | `inline-flex px-2 py-0.5 text-xs font-medium rounded-md` — same map, **shape differs by the missing `shrink-0`** |
| 11 | Data-import status (dot) | `routes/dashboard/settings/data/importStatus.js:81-91` | `pending` amber-9, `processing` blue-9, `completed` teal-9, `completed_with_errors` amber-9, `failed` ruby-9, `abandoned` slate-9, fallback slate-9 — **dot, not pill** |
| 12 | …rendered in the list | `routes/dashboard/settings/data/Index.vue:328-338` | `size-2 rounded-full` + `animate-pulse` while active (`:332`), label via `formatStatus` (`importStatus.js:66`) which just replaces `_` with spaces |
| 13 | …rendered in the detail header | `routes/dashboard/settings/data/components/ImportDetailHeader.vue:123-124` | same dot + `animate-pulse` |
| 14 | Active-import pulse | `routes/dashboard/settings/data/Index.vue:210` | `size-2 rounded-full bg-n-teal-9 animate-pulse` — a *fourth* hard-coded teal dot |
| 15 | Commerce store status (dot) | `routes/dashboard/settings/commerce/Index.vue:35-39`, rendered `:353-356` | `active` teal-9, `disabled` slate-9, `needs_reauth` amber-9, `disconnected` ruby-9; `size-2 rounded-full` inside `text-label-small text-n-slate-11` |
| 16 | Commerce realtime status | `routes/dashboard/settings/commerce/Index.vue:58-62` | text-only `text-n-teal-11` vs `text-n-slate-11` |
| 17 | Salla connection status | `routes/dashboard/settings/commerce/SallaConnectDialog.vue:52-61` | `connected` teal-2, `conflict` ruby-2, `expired` amber-2, `limit_reached` amber-2, fallback `bg-n-alpha-2 text-n-slate-11`; shape `rounded-lg px-3 py-2 text-body-main` (`:181-182`) — **block notice, `-2` ramp** |
| 18 | Agent availability | `components-next/sidebar/SidebarProfileMenuStatus.vue:36` | positional array `['bg-n-teal-9','bg-n-amber-9','bg-n-slate-9']` indexed by `AVAILABILITY_STATUS_KEYS`; rendered as `size-[12px] rounded` in the menu (`:43`) and `size-2 rounded-sm` in the trigger (`:97`) — **two sizes and two radii for one concept** |
| 19 | Avatar presence dot | `components-next/avatar/Avatar.vue:78-82` | `online` teal-**10**, `busy` amber-**10**, `offline` slate-**10**; `rounded-full border border-n-slate-3`, size `max(avatar*0.35, 8)px` — a *third* availability color ramp |
| 20 | WhatsApp account health — quality | `routes/dashboard/settings/inbox/components/AccountHealth.vue:36-41` | `GREEN` teal-11, `YELLOW` amber-11, `RED` ruby-11, `UNKNOWN` slate-12 — **text tone only** |
| 21 | WhatsApp account health — status | `AccountHealth.vue:43-58` | 13 keys: `APPROVED`/`CONNECTED`/`VERIFIED`/`STANDARD`/`ACTIVE` teal-11; `PENDING_REVIEW`/`EXPIRED`/`FLAGGED` amber-11; `AVAILABLE_WITHOUT_REVIEW` slate-11; `RESTRICTED`/`BANNED`/`DISCONNECTED`/`REJECTED`/`DECLINED` ruby-**9** (note: `-9`, not `-11`) |
| 22 | WhatsApp account health — mode | `AccountHealth.vue:60-63` | `LIVE` teal-11, `SANDBOX` slate-11 |
| 23 | …all three rendered as | `AccountHealth.vue:528, 593, 600, 607, 650, 657` | neutral chip `inline-flex items-center [gap-1.5] px-2 py-0.5 min-h-6 text-label-small rounded-md bg-n-alpha-2` + the tone class — **tone carried by text on a neutral background** |
| 24 | Twilio health — account status | `routes/dashboard/settings/inbox/components/TwilioHealth.vue:48-50` | `ACTIVE` teal-11, `SUSPENDED` ruby-11, `CLOSED` ruby-11 |
| 25 | Twilio health — account type | `TwilioHealth.vue:55-56` | `FULL` teal-11, `TRIAL` amber-11 |
| 26 | Twilio health — healthy/unhealthy | `TwilioHealth.vue:241-242` | `isHealthy ? text-n-teal-11 : text-n-amber-11` on the same neutral `bg-n-alpha-2` chip |
| 27 | Twilio health — capability | `TwilioHealth.vue:217-218` | available → teal-11; otherwise required → ruby-11, optional → slate-11; chips at `:375`, `:382` |
| 28 | Captain document sync | `components-next/captain/assistant/DocumentSyncStatus.vue:115-134` | states `syncing`, `stale_sync`, `failed`, `stale`, `never_synced`, `synced`; tone amber / amber / ruby / amber / slate; **no pill at all** — `flex gap-1.5 items-center text-sm truncate shrink-0 tabular-nums` (`:140`) with a `Spinner` or `i-lucide-circle-alert` / `i-lucide-refresh-cw` icon (`:143-144`) |
| 29 | Captain custom-tool validity | `components-next/captain/pageComponents/customTool/CustomToolForm.vue:302-306` | valid `bg-n-teal-2 text-n-teal-11` / invalid `bg-n-ruby-2 text-n-ruby-11` on `flex items-center gap-2 px-3 py-2 text-xs rounded-lg` — **`-2` ramp** |
| 30 | CSAT template utility | `routes/dashboard/settings/inbox/settingsPage/CustomerSatisfactionPage.vue:297-305`, rendered `:561-568` | `LIKELY_UTILITY` teal-3, `LIKELY_MARKETING` ruby-3, else amber-3; shape `px-2 py-0.5 text-xs font-medium rounded-full` — **the only `rounded-full` status pill** |
| 31 | Campaign active/complete | `components-next/Campaigns/CampaignCard/CampaignCard.vue:64-67`, rendered `:109` | active `text-n-teal-11` / inactive `text-n-slate-12` on neutral `text-xs font-medium inline-flex items-center h-6 px-2 py-0.5 rounded-md bg-n-alpha-2`; labels enabled/disabled/completed/processing/scheduled (`:69-85`) |
| 32 | Article status (card) | `components-next/HelpCenter/ArticleCard/ArticleCard.vue:135-144`, rendered `:230-232` | `archived` slate-12, `draft` amber-11, default (published) teal-11 on neutral `bg-n-alpha-2` chip |
| 33 | Article pending-edits | `ArticleCard.vue:224-227` | neutral chip + an inline `rounded-full size-1.5 bg-n-amber-9` dot — **dot inside a pill** |
| 34 | Article status (search result) | `modules/search/components/SearchResultArticleItem.vue:51-60`, rendered `:85-88` | identical tone map to #32, but shape `text-xs inline-flex items-center font-medium rounded-md whitespace-nowrap capitalize bg-n-alpha-2 px-2 h-6` (no `py`, adds `capitalize`) |
| 35 | Article category (search result) | `SearchResultArticleItem.vue:78-81` | same shape at `px-1.5` with `text-n-slate-12` |
| 36 | Flow published state (Lynomia) | `routes/dashboard/settings/flows/Index.vue:240-256` | **no pill**: plain `text-body-main text-n-slate-12` for the status word, `block text-xs text-n-amber-11` for `UNPUBLISHED`, `block text-xs text-n-slate-11` for live-session count |
| 37 | Message delivery status | `components-next/message/MessageStatus.vue:47-65` | `sent` / `delivered` `text-n-slate-10`, `read` **`text-[#7EB6FF]`** (raw hex, off-token), `progress` = 12-frame rotating clock icon (`:19-45`); icon-only, tooltip-labelled |
| 38 | Conversation status | `components-next/Conversation/ConversationCard/CardStatusIcon.vue:18-30` | `open` / `resolved` / `pending` / `snoozed` / `empty` as `i-woot-status-*` icons, `size-4`; color lives in the icon, no map, tooltip = the raw status string (`:36`) |
| 39 | SLA breach state | `components-next/Conversation/Sla/SLACardLabel.vue:54` | `Label compact` with `color="ruby"` when missed else `"amber"`, `i-lucide-flame` icon — the only status that reuses `Label` |
| 40 | Custom-attribute badge | `components-next/CustomAttributes/AttributeBadge.vue:17-30` | `pre-chat` / `resolution`; **`colorClass` (`text-n-blue-11` / `text-n-teal-11`) is computed but never bound** — the template passes `color: 'slate'` and hardcodes `text-n-slate-12` on the icon (`:37-40`), so both states render identically |
| 41 | Voice-call status | `components-next/message/bubbles/VoiceCall.vue:198-201` | `bg-n-teal-3 text-n-teal-11` for two separate branches |
| 42 | Captain error bubble | `components-next/captain/assistant/MessageList.vue:39` | `bg-n-ruby-3 text-n-ruby-11 rounded-es-sm rounded-ee-xl rounded-t-xl` |
| 43 | Message bubble variants | `components-next/message/bubbles/Base.vue:49, 53` | `USER` `bg-n-slate-4 text-n-slate-12`, `ERROR` `bg-n-ruby-4 text-n-ruby-12` — the **`-4/-12`** ramp |

### 10.C Neutral meta / count chips (the `bg-n-alpha-2` family)

| # | File:line | Classes | Carries |
|---|---|---|---|
| 44 | `routes/dashboard/settings/data/components/ImportLogSection.vue:56` | `rounded-md bg-n-alpha-2 px-1.5 text-label-small tabular-nums text-n-slate-11` (**no `py`**) | row count |
| 45 | `routes/dashboard/settings/data/Index.vue:261` | `inline-flex items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-label-small text-n-slate-11` | "coming soon" |
| 46 | `routes/dashboard/settings/commerce/ProviderPicker.vue:91` | `rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-label-small text-n-slate-11` | provider meta |
| 47 | `routes/dashboard/settings/automation/AutomationRuleRow.vue:49` | `text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 whitespace-nowrap flex-shrink-0` | event name |
| 48 | `components-next/Companies/CompanyDetail/CompanyContactsSidebar.vue:220` | `px-2 py-0.5 text-xs rounded-md text-n-amber-11 bg-n-alpha-2` | warning count |
| 49 | `components-next/HelpCenter/LocaleCard/LocaleCard.vue:90` | `bg-n-alpha-2 h-6 inline-flex items-center justify-center rounded-md text-xs border-px border-transparent text-n-blue-11 px-2 py-0.5` | default locale (`border-px` is not a Tailwind class) |
| 50 | `components-next/HelpCenter/LocaleCard/LocaleCard.vue:96` | same with `text-n-slate-11` | locale code |
| 51 | `routes/dashboard/settings/flows/FlowBuilder.vue:351` | `flex items-center gap-1 px-2 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-12` | builder meta (`rounded-lg`) |
| 52 | `routes/dashboard/settings/automation/components/AutomationWaitCondition.vue:446` | `flex items-center self-start h-8 px-3 text-sm font-medium rounded-md bg-n-alpha-2 text-n-slate-11` | `h-8`, `text-sm` — the tallest neutral chip |
| 53 | `components-next/captain/assistant/FaqSuggestionCard.vue:58` | `rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs font-medium text-n-slate-11` | language — **`rounded-full`** |
| 54 | `components-next/captain/assistant/FaqSuggestionCard.vue:51` | `inline-flex items-center gap-1.5 rounded-full bg-n-brand/10 px-2.5 py-1 text-xs font-medium text-n-blue-11` | source — **`bg-n-brand/10`**, the only brand-alpha chip |

### 10.D Other solid-background chips

| # | File:line | Classes | Carries |
|---|---|---|---|
| 55 | `routes/dashboard/settings/agentBots/Index.vue:154` | `text-xs text-n-slate-12 bg-n-blue-5 rounded-md py-0.5 px-1 flex-shrink-0` | bot type — **`-5` ramp** |
| 56 | `components/ChatListHeader.vue:99` and `:106` | `px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0` | list filter name — **`text-xxs`** |
| 57 | `routes/dashboard/settings/inbox/components/BusinessDay.vue:208` | `label bg-n-blue-3 text-n-blue-11 text-label-small inline-block px-2 py-1 rounded-lg cursor-default whitespace-nowrap` | business hours — carries a stray legacy `label` class |
| 58 | `routes/dashboard/settings/inbox/settingsPage/WhatsappBusinessManagementToken.vue:103-105` | `inline-flex w-fit items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-label-small text-n-teal-11` + `size-1.5 rounded-full bg-n-teal-9` | token valid |
| 59 | `components-next/HelpCenter/CategoryCard/CategoryCard.vue:99` | `inline-flex items-center justify-center h-6 px-2 py-1 text-xs text-center border rounded-lg bg-n-slate-1 whitespace-nowrap shrink-0 text-n-slate-11 border-n-slate-4` | article count — **the only `border` + `bg-n-slate-1` chip** |
| 60 | `routes/dashboard/settings/account/components/SectionLayout.vue:37` | `text-xs uppercase text-n-iris-11 border border-1 border-n-iris-10 leading-none rounded-lg px-1 py-0.5` | beta marker — outline-only, `uppercase`; `border-1` is not a Tailwind class |
| 61 | `routes/dashboard/settings/profile/ActiveSessions.vue:111` | `rounded-full bg-n-teal-3 px-2 py-0.5 text-caption text-n-teal-11` | current session — **`text-caption` is not in the typography set** (`_woot.scss:76-84`) |
| 62 | `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorHeader.vue:277` | `flex items-center gap-1.5 px-2 py-1 text-xs font-medium transition-colors rounded-lg cursor-pointer text-n-amber-11 bg-n-amber-3 outline outline-1 outline-n-amber-5 hover:bg-n-amber-4` | unsaved changes — the only pill with an outline **and** a hover state |
| 63 | `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue:129` | `size-2 rounded-full bg-n-amber-9 shrink-0` | pending change dot |
| 64 | `routes/dashboard/settings/subscription/Index.vue:365, 371, 377, 383, 389` | `px-4 py-3 text-sm rounded-lg` with teal-3 / `bg-n-alpha-2` / teal-3 / ruby-3 / amber-3 | subscription state — block notices |
| 65 | `components/widgets/conversation/commerce/CommerceOverview.vue:68`, `CommerceOrderActions.vue:351`, `CommercePanel.vue:401` | `rounded-lg bg-n-amber-2 px-3 py-2 text-body-main text-n-amber-11` | commerce warnings — **`-2` ramp block notices** |
| 66 | `components/widgets/conversation/commerce/CommerceOrderActions.vue:471` | `bg-n-ruby-2 text-n-ruby-11` | action error |
| 67 | `components-next/filter/ContactsFilter.vue:191` | `rounded-lg px-3 py-2 text-label-small` | filter notice |
| 68 | `components-next/recipes/RecipeDialog.vue:138` (Lynomia) | `text-label-small text-n-amber-11` | recipe warning — text only |

### 10.E Count / notification bubbles

| # | File:line | Classes | Notes |
|---|---|---|---|
| 69 | `components-next/Conversation/ConversationCard/UnreadBadge.vue:20` | `bg-n-teal-9 rounded-full h-4 min-w-4 max-w-5 px-1 w-fit font-medium text-xxs leading-3 text-white inline-grid place-items-center flex-shrink-0` | overflow at `>9` via `CHAT_LIST.UNREAD_COUNT_OVERFLOW` (`:12-14`); `text-white`, teal |
| 70 | `components-next/sidebar/SidebarUnreadBadge.vue:22` | `inline-grid h-5 min-w-5 place-items-center rounded-full bg-n-slate-4 px-1 text-xxs font-medium leading-3 text-n-slate-12 dark:bg-n-slate-5 flex-shrink-0` | overflow at `>99` → `99+` (`:13-15`); **slate, `h-5`** — different color *and* size *and* overflow threshold from #69 |
| 71 | `components-next/sidebar/SidebarGroupHeader.vue:74` | **byte-identical class string to #70**, inlined rather than reusing `SidebarUnreadBadge` | duplication |
| 72 | `components/ui/Tabs/TabsItem.vue:62-66` | `rounded-full h-5 flex items-center justify-center text-xs font-medium my-0 ltr:ml-1 rtl:mr-1 px-1.5 py-0 min-w-[20px]` + active `bg-n-blue-3 text-n-blue-11` | tab count |
| 73 | `components-next/copilot/CopilotThinkingGroup.vue:39` | `inline-flex items-center justify-center h-4 min-w-4 px-1 text-xs font-medium rounded-full bg-n-solid-3 text-n-slate-11` | step count |
| 74 | `components/widgets/ThumbnailGroup.vue:63` | `text-n-slate-11 bg-n-slate-4 outline outline-1 outline-n-background text-xs font-medium rounded-full px-2 inline-flex items-center shadow relative` | avatar overflow `+N` |
| 75 | `components-next/sidebar/SidebarGroupHeader.vue:57` | `size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2` | unread dot |
| 76 | `components-next/Contacts/ContactsHeader/ContactHeader.vue:87` | `absolute top-0 right-0 w-2 h-2 rounded-full bg-n-brand` | active-filter dot (**`right-0`, not logical**) |

### 10.F Chip-shaped non-status UI (same visual vocabulary, different job)

| # | File:line | Classes |
|---|---|---|
| 77 | `components-next/label/LabelItem.vue:31` | `flex items-center px-1 py-1 overflow-hidden transition-all duration-300 ease-out rounded-md bg-n-alpha-2 h-7` |
| 78 | `components-next/label/AddLabel.vue:24` | `flex items-center gap-1 px-2 py-1 rounded-md outline-dashed h-6 outline-1 outline-n-slate-6 hover:bg-n-alpha-2` |
| 79 | `components-next/filter/ActiveFilterPreview.vue:59` | `flex items-center h-full min-w-0 gap-1 px-2 py-1 text-xs border rounded-lg hover:bg-n-solid-2 max-w-72 border-n-weak hover:cursor-pointer` |
| 80 | `components-next/filter/ActiveFilterPreview.vue:95` | `content-center h-full px-1 text-xs font-medium uppercase rounded-lg text-n-slate-10` |
| 81 | `components-next/Calls/CallListItem.vue:106` and `:245` | `inline-flex items-center h-6 gap-1 px-2 text-label-small outline outline-1 -outline-offset-1 rounded-md outline-n-weak text-n-slate-11 hover:bg-n-alpha-1 shrink-0` (`:245` adds a contradictory `py-3.5` on an `h-6` box) |
| 82 | `components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue:129`, `:186` | `bg-n-slate-3 text-n-slate-12` at `rounded-lg` / `rounded` |
| 83 | `components/widgets/conversation/ContentTemplates/ContentTemplatesPicker.vue:108`, `:113` | `inline-block px-2 py-1 text-xs leading-none rounded-lg cursor-default bg-n-slate-3 text-n-slate-12` |
| 84 | `components/widgets/conversation/QuotedEmailPreview.vue:40` | `relative rounded-md px-3 py-2 text-xs text-n-slate-12 bg-n-slate-3 dark:bg-n-solid-3` |
| 85 | `components/widgets/conversation/ReplyToMessage.vue:17` | `reply-editor bg-n-slate-9/10 rounded-md py-1 ps-2 pe-1 text-xs tracking-wide` |
| 86 | `components/widgets/conversation/components/GalleryView.vue:356` | `rounded-md flex items-center justify-center px-3 py-1 bg-n-slate-3 text-n-slate-12 text-sm font-medium` |
| 87 | `components/widgets/conversation/MessagesView.vue:535` | `shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5` |
| 88 | `components/widgets/conversation/MessagesView.vue:562` | `flex py-2 pr-4 pl-5 shadow-md rounded-full bg-white dark:bg-n-solid-3 text-n-slate-11 text-xs font-semibold` |
| 89 | `components/widgets/conversation/TagAgents.vue:141` | `flex items-center min-w-0 gap-1 px-2 py-1 text-xs font-medium transition-colors rounded-md` |
| 90 | `components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue:38-62` | legend dots `bg-n-iris-9` / `bg-n-teal-9` / `bg-n-ruby-9` / `bg-n-amber-9` / `bg-n-slate-6` |
| 91 | `components-next/year-in-review/YearInReviewBanner.vue:78` | `w-full px-3 py-2 bg-white text-n-iris-9 text-xs font-medium **rounded-mdtracking-tight**` — two class names concatenated without a space, so neither `rounded-md` nor `tracking-tight` is emitted |

### 10.G Ramp census — the same semantic, six different scales

| Ramp | Where | Examples |
|---|---|---|
| `bg-n-{c}-2` + `outline-n-{c}-4` + `text-n-{c}-11` | `components-next/label/Label.vue:23-27` | the only outline-tinted family |
| `bg-n-{c}-2` + `text-n-{c}-11` | `SallaConnectDialog.vue:55-58`, `CustomToolForm.vue:305-306`, `CommerceOverview.vue:68` | `-2` solid |
| `bg-n-{c}-3` + `text-n-{c}-11` | `CallStatusBadge.vue:19-39`, `DeliveryStatusBadge.vue:15-20`, `CommerceOrderItem.vue:38-53`, `templateUtils.js:121-124`, `CustomerSatisfactionPage.vue:299-304`, `subscription/Index.vue:365-389` | the de facto default |
| `bg-n-{c}-3` + `border-n-{c}-4` + `text-n-{c}-11` | `banner/Banner.vue:27-32`, `LowBackupCodesBanner.vue:17-22`, `InboxBanner.vue:47` | bordered block |
| `bg-n-{c}-4` + `text-n-{c}-12` | `message/bubbles/Base.vue:49, 53` | bubbles |
| `bg-n-{c}-5` + `border-n-{c}-7` + `text-n-{c}-12` | legacy `components/ui/Label.vue:135-184`, `agentBots/Index.vue:154`, `ShopifyOrderItem.vue:28` | legacy |
| `bg-n-{c}-9` (dot) | `importStatus.js:82-87`, `commerce/Index.vue:36-39`, `SidebarProfileMenuStatus.vue:36`, `CampaignDeliveryBreakdown.vue:38-62`, `ArticleCard.vue:226` | dots |
| `bg-n-{c}-10` (dot) | `avatar/Avatar.vue:79-81` | avatar presence only |
| neutral `bg-n-alpha-2` + `text-n-{c}-11` | `AccountHealth.vue:528+`, `TwilioHealth.vue:241+`, `CampaignCard.vue:109`, `ArticleCard.vue:230`, `SearchResultArticleItem.vue:86`, `templateUtils.js:125` | tone-by-text |

### 10.H Shape census

| Radius | Count in census | Examples |
|---|---|---|
| `rounded` (4px) | 1 | `ShopifyOrderItem.vue:81` |
| `rounded-md` (6px) | majority | `CallStatusBadge.vue:48`, `DeliveryStatusBadge.vue:35`, `TemplateCard.vue:59`, `CommerceOrderItem.vue:129` |
| `rounded-lg` (8px) | 8 | `CategoryCard.vue:99`, `BusinessDay.vue:208`, `SectionLayout.vue:37`, `ArticleEditorHeader.vue:277`, `FlowBuilder.vue:351`, `CustomToolForm.vue:302`, `SallaConnectDialog.vue:181`, `subscription/Index.vue:365` |
| `rounded-full` | 6 | `CustomerSatisfactionPage.vue:562`, `FaqSuggestionCard.vue:51, 58`, `ActiveSessions.vue:111`, `UnreadBadge.vue:20`, `SidebarUnreadBadge.vue:22` |
| `rounded-xl` | banners | `banner/Banner.vue:58` |

| Height policy | Examples |
|---|---|
| explicit `h-6` | `CallStatusBadge.vue:48`, `DeliveryStatusBadge.vue:35`, `CampaignCard.vue:109`, `ArticleCard.vue:224, 230`, `CategoryCard.vue:99`, `LocaleCard.vue:90, 96`, `SearchResultArticleItem.vue:80, 86`, `label/Label.vue:53` (compact) |
| `min-h-6` | `AccountHealth.vue:528+`, `TwilioHealth.vue:241+` |
| `h-8` | `label/Label.vue:53` (default), `AutomationWaitCondition.vue:446` |
| `h-7` | `LabelItem.vue:31` |
| padding-only (`py-0.5` / `py-1` / `py-2`) | `TemplateCard.vue:59`, `CommerceOrderItem.vue:129`, `CustomerSatisfactionPage.vue:562`, `ActiveSessions.vue:111`, `FaqSuggestionCard.vue:51` |
| no vertical sizing at all | `ImportLogSection.vue:56` |

| Type class | Examples |
|---|---|
| `text-label-small` (12px/16, 440) | `CallStatusBadge.vue:48`, `CommerceOrderItem.vue:129`, `AccountHealth.vue:528+`, `ProviderPicker.vue:91`, `BusinessDay.vue:208`, `label/Label.vue:65` |
| `text-xs font-medium` | `DeliveryStatusBadge.vue:35`, `TemplateCard.vue:59`, `CampaignCard.vue:109`, `ArticleCard.vue:224`, `FaqSuggestionCard.vue:51`, `CustomerSatisfactionPage.vue:562` |
| `text-xs` (no weight) | `CompanyContactsSidebar.vue:220`, `LocaleCard.vue:90`, `CategoryCard.vue:99`, `FlowBuilder.vue:351`, `ShopifyOrderItem.vue:81` |
| `text-xxs` | `ChatListHeader.vue:99`, `UnreadBadge.vue:20`, `SidebarUnreadBadge.vue:22` |
| `text-sm` | `AutomationWaitCondition.vue:446`, `subscription/Index.vue:365`, `DocumentSyncStatus.vue:140` |
| `text-caption` (**undefined utility**) | `ActiveSessions.vue:111` |
| `text-body-main` | `SallaConnectDialog.vue:181`, `CommerceOverview.vue:68` |

---

## 11. Inconsistencies, ranked

| Sev | Issue | Evidence |
|---|---|---|
| high | **No badge component exists.** 60 distinct status/badge treatments across 6 color ramps, 5 radii, 7 height policies and 7 type classes. Two near-identical per-domain components (`CallStatusBadge`, `DeliveryStatusBadge`) prove the need and disagree with each other. | section 10 |
| high | **BaseTable has no hover, no selected state, no sortable columns and no loading UI.** Hover/selected exist only in `CsatTable.vue:168-171` and `AssignmentPolicy/components/DataTable.vue:56`; sorting only in the legacy `components/table/Table.vue:45` + `SortButton.vue`. | `BaseTableRow.vue:11`, `BaseTable.vue:17-20` |
| high | **Tables break at narrow widths.** `min-w-full table-auto` with no overflow wrapper; only 1 of 15 call sites wraps in `overflow-x-auto` (`ImportLogSection.vue:90`). No column hiding, no stacked fallback, no sticky column. | section 2.3 |
| high | **One semantic, three availability color ramps.** `-9` dots (`SidebarProfileMenuStatus.vue:36`), `-10` dots (`avatar/Avatar.vue:79-81`), and `-11` text (`AccountHealth.vue:44-48`). | as cited |
| high | **Three pagination systems with three default page sizes** (16 / 10 / 25) and two i18n namespaces (`PAGINATION_FOOTER.*` vs `REPORT.PAGINATION.*`). Only the legacy one has numbered pages and a page-size selector. | `PaginationFooter.vue:20, 48`; `components/table/Pagination.vue:14, 26-43, 112`; `TableFooter.vue:11` |
| medium | **`BaseTable`'s `loading` prop is dead** — declared at `:17-20`, read at `:49`, never passed by any of the 15 call sites. | verified repo-wide |
| medium | **The header row vanishes in the empty state** (`showHeaders` requires `items.length > 0`), so an empty table loses its column context. | `BaseTable.vue:24-26` |
| medium | **`Spinner.vue` stroke attributes are inert.** `strokeWidth="8"`, `strokeLinecap`, `strokeLinejoin` are camelCase and not valid SVG attribute names, so the arc renders at the SVG default width of 1 across all 89 call sites. | `spinner/Spinner.vue:18-20` |
| medium | **`AttributeBadge`'s two states are visually identical.** `config.colorClass` (`text-n-blue-11` / `text-n-teal-11`) is computed at `:19` and `:25` but never bound; the template passes `color: 'slate'` and hardcodes `text-n-slate-12` on the icon. | `CustomAttributes/AttributeBadge.vue:17-40` |
| medium | **`EmptyStateLayout` hardcodes type instead of using the typography utilities** — `text-3xl font-medium` and `text-base tracking-[0.3px]` rather than `text-heading-*` / `text-body-*`, against the stated frontend convention. | `EmptyStateLayout.vue:51, 56`; `_woot.scss:76-84` |
| medium | **Four distinct empty-state visual languages** coexist (backdrop hero, bordered icon card, bare centered stack, dashed placeholder), and the four biggest newer surfaces (data imports, commerce, flows, assignment policy) all bypass `EmptyStateLayout`. | section 8.2 |
| medium | **No skeleton primitive.** ~20 hand-rolled `animate-pulse` blocks with 4 base colors and 2 animations; the only table skeleton (`CsatTableLoader.vue`) cannot be used by `BaseTable`. | section 9.4 |
| medium | **`ImportLogSection` reaches into `BaseTable`'s internals from outside** with `[&_td:first-child]:ps-4 [&_th:first-child]:ps-4 [&_th]:text-n-slate-11 [&_thead]:border-t-0` — the component has no props for start padding, header color or top border. | `ImportLogSection.vue:92` |
| medium | **Same status map, two different shapes.** `templateStatusClasses` is rendered with `shrink-0` in `TemplateCard.vue:59` and without it in `TemplatePreviewDrawer.vue:96`. | as cited |
| medium | **Two count-bubble components with different color, height and overflow threshold**, plus a third copy inlined. `UnreadBadge.vue:20` is teal `h-4` overflowing at `>9`; `SidebarUnreadBadge.vue:22` is slate `h-5` overflowing at `>99`; `SidebarGroupHeader.vue:74` duplicates the latter's class string byte-for-byte instead of importing it. | as cited |
| medium | **`Banner` supports 5 colors, `Label` supports 6** — `iris` exists in `Label` and not in `Banner`, so iris states cannot be expressed as a banner. | `banner/Banner.vue:9-11` vs `label/Label.vue:17` |
| medium | **Three banners re-implement `Banner`'s color map inline**, and two sibling Captain banners disagree on background (`bg-n-amber-2` vs `bg-n-amber-3`). | `LowBackupCodesBanner.vue:17, 22`; `CoverageBanner.vue:69`; `InboxBanner.vue:47` |
| medium | **Legacy `components/ui/Banner.vue` is marked DEPRECIATED with a TODO to replace it**, yet still has 5 consumers and a third color ramp. | `components/ui/Banner.vue:1-2, 134-145` |
| medium | **Off-token colors in status code.** `avatar/Avatar.vue:58-76` carries 13 raw hex values; `message/MessageStatus.vue:61` uses `text-[#7EB6FF]`; `CsatTable.vue:157-159` builds a rating pill background from `${color}20` string concatenation. | as cited |
| low | **Broken utility class:** `rounded-mdtracking-tight` — two names concatenated without a space, so neither applies. | `year-in-review/YearInReviewBanner.vue:78` |
| low | **Non-existent utility classes** referenced as if real: `border-px` (`LocaleCard.vue:90, 96`), `border-1` (`SectionLayout.vue:37`), `text-caption` (`ActiveSessions.vue:111`). | as cited |
| low | **Contradictory sizing:** `h-6` with `py-3.5` on the same chip. | `Calls/CallListItem.vue:245` |
| low | **`CardLayout` emits both `py-5` and `py-6`** when `selectable` is true, so the resolved padding depends on Tailwind's output order rather than intent; `selectable` also only changes padding, while all 5 consumers supply their own checkbox. | `CardLayout.vue:25, 28` |
| low | **`CardLayout`'s padding is routinely patched out from the call site** with `class="[&>div]:px-5"` in 3 AssignmentPolicy cards — the `px-6` default does not fit that family. | `AgentCapacityPolicyCard.vue:48`, `AssignmentCard.vue:20`, `AssignmentPolicyCard.vue:64` |
| low | **`CardLayout.layout` has no validator** while `BaseTableCell.align`, `Avatar.status`, `Banner.color` and `Label.color` all do. | `CardLayout.vue:3-6` |
| low | **`PaginationFooter`'s gradient `::before` has no positioned ancestor.** The container at `:74` carries `before:absolute before:-top-4` but no `relative`, so the fade positions against whatever ancestor happens to be positioned. | `pagination/PaginationFooter.vue:74` |
| low | **`Avatar`'s presence/channel badge uses physical `top`/`left`**, so it does not mirror in RTL. Same for the filter dot at `ContactHeader.vue:87` (`right-0`). | `avatar/Avatar.vue:147-148`; `ContactHeader.vue:87` |
| low | **`BaseTable.story.vue` is stale** — it passes `:user="agent"` to `Avatar` (`:123`), which has no `user` prop and requires `name`. The story cannot render the avatar variant correctly. | `table/BaseTable.story.vue:123`; `avatar/Avatar.vue:15-18` |
| low | **No stories for `Banner`, `CardLayout`, `EmptyStateLayout`, `LabelItem`** — four of the most-reused display primitives have no visual documentation. | section 1 |
| low | **`BaseTableRow` requires an `item` it never uses** — it declares `item: { type: Object, required: true }` and passes it straight back out through the slot, forcing every call site to bind data the component ignores. | `BaseTableRow.vue:3-12` |
| low | **Header slots are positional** (`header-0`, `header-1`, …), so inserting a column silently re-targets every override. SLA already depends on indices 2/3/4. | `BaseTable.vue:39`; `sla/Index.vue:189, 201, 213` |
| low | **`BaseTable` empty cell overrides its own type scale** with `text-body-main !text-base`, an important-flag fight inside the component itself. | `BaseTable.vue:52` |
| low | **Three table header type treatments:** `text-heading-3 capitalize` (BaseTable), `font-medium text-sm` (legacy + CSAT), `text-xs font-medium uppercase` (`TableHeaderCell`). | `BaseTable.vue:37`; `components/table/Table.vue:43`; `TableHeaderCell.vue:32` |
| low | **Conversation labels render as dots in the list and as chips elsewhere** — `CardLabels.vue:83-91` vs `label/Label.vue`, same data, two visual languages. | as cited |

---

## 12. What a redesign should REUSE rather than rebuild

| Asset | Why it is worth keeping | File:line |
|---|---|---|
| The `BaseTable` / `BaseTableRow` / `BaseTableCell` slot contract | 15 surfaces, 18 rows and 66 cells already speak it, and the barrel export is stable. Capabilities (hover, selection, sort, loading, overflow) can be added behind props without touching a single call site. | `table/index.js`; section 2.4 |
| The `header-${index}` slot | Already carries real product behaviour (SLA tooltips). Extend it with a named form; do not remove the indexed form. | `BaseTable.vue:39`; `sla/Index.vue:189-224` |
| `BaseTableCell.align` | A working, validated 3-value API that every table relies on for the action column. | `BaseTableCell.vue:3-18` |
| The action-column convention | `<BaseTableCell align="end" class="w-24">` + `flex justify-end gap-3` of icon `Button`s is already uniform in 7 tables; it is the thing to formalise, not replace. | section 2.3 |
| `components-next/avatar/Avatar.vue` wholesale | 83 call sites, no competitor, a spec suite, a deterministic color function, a 4-step image fallback chain, the presence/channel badge slots and the upload/delete affordances. Only the raw-hex palette (`:58-76`) and the physical `top`/`left` badge offsets (`:147-148`) need touching. | `avatar/Avatar.vue` |
| `Avatar`'s `badge` and `overlay` slots | The extension points a unified presence/status system should plug into instead of adding props. | `avatar/Avatar.vue:204, 274-281` |
| `components-next/label/Label.vue` as the badge seed | It is the closest thing to a badge system that already exists: 6 validated colors, 2 sizes, an `icon` slot, an `action` slot, a per-label color dot, a `title` tooltip, and the only token-backed neutral (`n-label-color` / `n-label-border`). A unified badge should extend this component's API rather than start over — `SLACardLabel.vue:54` and `AttributeBadge.vue:37` already prove the pattern composes. | `label/Label.vue:4-69`; `theme/colors.js:285-287` |
| The `bg-n-{c}-3` / `text-n-{c}-11` ramp | The de facto majority ramp across the census (CallStatusBadge, DeliveryStatusBadge, Commerce, Templates, CSAT, Subscription). Make this the badge default so the largest group of call sites is a no-op migration. | section 10.G |
| The semantic→color mapping already agreed across domains | teal = success/active/delivered/paid/approved, amber = pending/warning/draft/queued-ish, ruby = failed/missed/rejected, blue = in-progress/sent, slate = neutral/inactive, iris = read. This consensus is implicit in ~20 independent maps; a badge system should encode it as named tones, not invent new ones. | `CallStatusBadge.vue:16-41`; `DeliveryStatusBadge.vue:14-21`; `CommerceOrderItem.vue:37-53`; `templateUtils.js:119-129`; `importStatus.js:81-88` |
| The `bg-n-alpha-2` neutral chip + tone-by-text pattern | ~15 call sites (AccountHealth, TwilioHealth, CampaignCard, ArticleCard, search results, meta chips) deliberately keep a neutral background and tint only the text. This is a distinct, intentional badge *variant* — keep it as `variant="subtle"` rather than flattening it into the solid ramp. | section 10.C |
| `components-next/banner/Banner.vue` color maps | Already consistent (`-3` bg / `-4` border / `-11` text / `-4`→`-5` button) and already carries the `[&_.link]` descendant hook. The 3 hand-rolled banners should be folded into it; only `iris` is missing. | `banner/Banner.vue:24-48` |
| `components-next/CardLayout.vue` shell | 21 call sites, a usable `after` slot, and the `group/cardLayout` hook children already depend on. Add hover/selected/focus to the shell; keep the slot and group names. | `CardLayout.vue:22, 35` |
| `components-next/EmptyStateLayout.vue`'s `empty-state-item` + `Policy`-wrapped `actions` slots | The ghosted-backdrop idea and the permission-gated action are genuinely good and used by 15 surfaces. What needs adding is an icon/illustration slot and the typography utilities, so the 4 bespoke empty states can migrate in. | `EmptyStateLayout.vue:35, 61-63` |
| `components-next/spinner/Spinner.vue` | 89 call sites, `currentColor`-driven so it inherits tone for free. Fix the three camelCase SVG attributes; do not replace the component. | `spinner/Spinner.vue` |
| The `bg-n-slate-3 animate-pulse` convention | Already the de facto skeleton in ~15 places. A `Skeleton` primitive should wrap exactly this, so existing blocks collapse into it without visual change. | section 9.4 |
| `reports/components/CsatTableLoader.vue` as the table-skeleton shape | The only worked example of a table skeleton (header row + avatar pucks + chip placeholder); it is the template for `BaseTable`'s loading state. | `CsatTableLoader.vue:10-35` |
| `CsatTable.vue`'s row interaction classes | The only existing hover+selected treatment for a table row: `group hover:bg-n-slate-2 dark:hover:bg-n-solid-3 transition-colors` and selected `bg-n-slate-2 dark:bg-n-solid-3`. Lift this into `BaseTableRow` rather than inventing a new one. | `CsatTable.vue:167-171` |
| `AssignmentPolicy/components/DataTable.vue`'s loading/empty/hover trio | Already demonstrates `Spinner` for loading, a dashed block for empty, and `group-hover` reveal for row actions — the behaviours `BaseTable` lacks. | `AssignmentPolicy/components/DataTable.vue:33-80` |
| `components/table/SortButton.vue` icon triplet | `i-lucide-chevrons-up-down` / `chevron-up` / `chevron-down` is a working sort indicator; reuse it when `BaseTable` gains sorting. | `components/table/SortButton.vue:9-13` |
| `components/table/Pagination.vue`'s page-size options and page window | The two features `PaginationFooter` lacks already exist, specified and translated (`REPORT.PAGINATION.PER_PAGE_TEMPLATE`). Port them into `PaginationFooter`; do not re-specify. | `components/table/Pagination.vue:26-43, 60-68` |
| `useNumberFormatter` in `PaginationFooter` | Compact/full number formatting and pluralised range copy are already locale-correct. | `pagination/PaginationFooter.vue:28, 47-69` |
| The typography utilities | `text-label-small`, `text-label`, `text-body-main`, `text-heading-3` are defined with explicit line-height and letter-spacing and are documented as the badge/tag scale. A badge system should use `text-label-small`, which is already the most common badge type class. | `app/javascript/dashboard/assets/scss/_woot.scss:71-148` (the use-case table is at `:76-84`) |
| `n-label-color` / `n-label-border` tokens | Already defined for both themes; the only token-backed neutral chip surface in the system. | `theme/colors.js:285-287`; `_next-colors.scss:138-139, 289-290` |

### Features that must survive any redesign (parity checklist)

Drawn from the inventory above; each is a behaviour a user can reach today.

- Table: per-column `align`, per-column width via class, custom header content with tooltips, truncation via `max-w-0` + `truncate`, row-level toggle switches, per-row loading on action buttons (`:is-loading="loading[id]"` in 4 tables), checkbox multi-select with select-all + indeterminate + count, paginated tables, collapsible table sections, horizontal scroll where present.
- Pagination: first/prev/next/last, current-page token, "showing X–Y of Z" with compact totals, numbered page window, page-size selection (10/20/50/100), hiding the footer when there is only one page.
- Avatar: initials from 1–2 words, emoji stripping, deterministic per-name color in both themes, image error fallback and retry, size-proportional radius ladder, `rounded-full` opt-in, presence dot with `hideOfflineStatus`, channel-icon badge, upload overlay, delete affordance, `title`/`alt` text.
- Labels: per-label hex color dot, description tooltip, compact and default sizes, hover-reveal remove, dashed add-label with searchable dropdown, overflow handling in the conversation list.
- Banners: 5 colors, optional action button with loading spinner, link styling hook, close button (legacy), full-bleed and rounded-card forms.
- Empty states: ghosted real-content backdrop, permission-gated actions, multiple actions side by side, icon puck + title + description + chip (the bespoke card form).
- Status: every state in section 10 — including the icon-only treatments (`CardStatusIcon`, `MessageStatus`, `DocumentSyncStatus`), the dot-only treatments (import status, store status, availability), the pulse on active imports, the fixed-width call badge, the retry button inside the sync status, and the unknown-status passthrough in `DeliveryStatusBadge.vue:29`.
