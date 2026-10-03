# Synthesis — Cross-module visual/interaction audit

Read-only synthesis of the 19 audits in this directory. Nothing here is a plan; it is the
consolidated evidence those audits produced, arranged so the next phase can tell *unnecessary*
divergence from divergence a different workflow earns.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`. Paths are relative to
`app/javascript/dashboard/` unless stated otherwise.

**Scale of the baseline:** 11 surface audits, **2 771 feature-parity rows**, **734 visual findings**,
8 system audits. Per-surface totals in §5.

---

## 0. Freshness correction — the audits are already stale, and all in one direction

The system audits were written between 11:34 and 12:24; the surface audits ran until 14:07. Shared
tokens and primitives changed on disk in between. Everything below was re-read against the current
tree for this synthesis.

**A whole token layer has been added to `tailwind.config.js` since the token audit was written:**

| Token family | Added | Consumers today | Still-arbitrary values in the tree |
|---|---|---:|---|
| Elevation | `shadow-raised` / `shadow-overlay` / `shadow-modal`, backed by light+dark CSS vars promoted out of the private `--cw-*` block (`tailwind.config.js:69-73`; `_next-colors.scss:155-162, 319-323`) | **2 files** (`shadow-modal`) | 7 `shadow-[…]`, 33 raw `box-shadow` |
| Backdrop blur | `blur.panel: 100px` (`tailwind.config.js:74-77`) | **2 files** | **43** `backdrop-blur-[100px]`, plus `2px`/`4px`/`50px`/`0.01875rem` |
| Radius roles | `rounded-control` 6px / `rounded-surface` 8px / `rounded-overlay` 12px (`:62-68`) | **3 files** (`rounded-overlay`) | 16 arbitrary radii |
| Control heights | `h-control-xs/sm/md/lg` + matching `minHeight` (`:78-90`) | **0 files** | `h-[3.25rem]` ×8, `h-[2.5rem]` ×6 |
| Z-index ladder | `z-sticky` 10 / `z-dropdown` 50 / `z-drawer` 60 / `z-modal` 70 / `z-toast` 80 (`:91-98`) | **4 occurrences total** (`z-sticky` 1, `z-dropdown` 3, the other three **0**) | 23 arbitrary: `z-[100]`×9, `z-[9999]`×8, `z-[1000]`, `z-[9990]`, `z-[10001]`, `z-[5]`, `z-[1]`×2 |

**Primitives were upgraded too**, and the same gap appears:

| Claim in an audit | Current truth | Adoption |
|---|---|---|
| "`BaseTable` has no hover, no selected state, no sortable columns and no loading UI" (`system-data-display.md` §2.3, §11) | All four now exist, plus `stickyHeader`, `scrollable`, `loadingRows`, and the header row persists in the empty state (`BaseTable.vue:18-54, 59-63, 67`; `BaseTableRow.vue:11-21` with `hoverable` default `true`, `selected`, `aria-selected`) | `sortableColumns` / `stickyHeader` / `scrollable` grep to **exactly one file — `BaseTable.vue` itself** |
| "There is no skeleton component" (`system-data-display.md` §9.4) | `components-next/skeleton/Skeleton.vue` exists | **1 consumer** (`BaseTable`) |
| "`Button` focus-visible produces no outline — 843 instances"; "five competing focus conventions" (`system-a11y-rtl.md` §3 defect 1, §2.2) | One `.focus-ring` utility exists, documented as "the one keyboard-focus treatment", and `Button`'s base string applies it (`_base.scss:84-86`; `Button.vue:194`) | **5 consumers**: `Button`, `Checkbox`, `InlineInput`, `DropdownMenu`, `ComboBoxDropdown` |
| "Legacy `Modal` is 600px fixed with no `max-width` — overflows below 600px"; "no `role`, no `aria-modal`, no scroll lock, nameless close button" (`system-containers.md` #2, #4; `system-a11y-rtl.md` defect 7) | **Fixed**: `w-full max-w-[37.5rem]` (`components/Modal.vue:93`), `role="dialog"` + `aria-modal="true"` (`:89-90`), `useScrollLock` (`:24`), close button with `:aria-label="t('GENERAL.CLOSE')"` (`:102-109`) | still **no Teleport** (`:2` TODO) and **no focus trap** |
| "`Dialog` never locks body scroll"; "no `aria-labelledby`/`aria-describedby`" (`system-containers.md` #5, #11) | **Fixed**: `useScrollLock` (`Dialog.vue:4,73`), `:aria-labelledby`/`:aria-describedby` (`:132-133`) | — |

Verified **still true**: no `Badge` component (`ls components-next/badge` → nothing); `Spinner`'s
three stroke attributes are still camelCase and therefore inert across 89 call sites
(`components-next/spinner/Spinner.vue:18-20`); `Dialog` still has no close (X) control; `SidePanel`
still has no focus trap (no `trapFocus`/`useFocusTrap` import); 52 `<woot-modal>` tags across 40
files; 15 `EmptyStateLayout` consumers; 60 files importing `Dialog`.

**The conclusion that should shape this phase:** the gaps the audits named have largely been answered
in config and in the primitives, and almost nothing consumes the answers. The cheapest, lowest-risk
work available is *passing props and swapping class strings that already exist* — not building
anything new.

## 1. Cross-module consistency matrix

What each module does **today**. "Audience" = the segment/label/active variants of the Contacts
routes, which share one component tree but behave differently enough to be its own column.

### 1.1 Page header and primary CTA

| Pattern | Contacts | Audience | Automation | Flows | Campaigns | Commerce | Settings CRUD | Conversation |
|---|---|---|---|---|---|---|---|---|
| **Page header** | Bespoke `ContactHeader.vue` — 12 props, 13 emits, `sticky top-0 z-20 max-w-5xl py-6`; title computed from `route.name` (`ContactsIndex.vue:125-131`) | Same component; title = audience name; **search hidden** (`ContactsListLayout.vue:86`) | `BaseSettingsHeader` with title + description + help link + search + tabs + count + actions (`automation/Index.vue:332-365`) | List: `BaseSettingsHeader` (`flows/Index.vue:169-191`). **Builder: no shell header at all** — full-bleed hand-rolled (`flows.routes.js:23-28`, `FlowBuilder.vue:328-411`) | `CampaignLayout.vue:25-30` — `h-20 sticky`, title only; no description, search, count or tabs | `BaseSettingsHeader` title + description only; `#count`, `#tabs`, `searchPlaceholder`, help link all left unused (`commerce/Index.vue:271-285`) | `BaseSettingsHeader` on all 8 lists; wizard/detail pages switch to `Wrapper.vue` + `SettingsHeader` (`h-20`, hand-rolled `text-xl font-medium`, `max-w-7xl`) | `ChatListHeader.vue` — **no page-title pattern**; title becomes the contact name when contact-scoped (`:53-55`) |
| **Primary CTA** | "Message" solid blue (`ContactHeader.vue:136-140`). **"Add contact" is a row inside the ⋮ menu** (`ContactMoreActions.vue:152-158`) | None. An audience is created by a 32px icon-only save button (`ContactHeader.vue:92-104`) | "Create Automation" solid blue `sm` + "Recipes" faded slate (`Index.vue:353-365`) — **hierarchy inverts in the empty state** (`:389-401`) | Header primary; **empty state inverts the header's hierarchy** (`surface-flow-builder.md` V-10) | "Create campaign" solid blue `sm` + `i-lucide-plus` (`CampaignLayout.vue:39-45`) | "Add store" solid `sm`, `:disabled` at plan limit (`commerce/Index.vue:276-283`) | Per-page `#actions` slot; `BaseSettingsHeader.vue:128` | None at page level; the primary act is per-conversation Resolve (`ResolveAction.vue`) |
| **Header measure** | `max-w-5xl` + `px-6`, body `max-w-5xl`, footer `max-w-[67rem]` | same | `max-w-5xl` (`SettingsWrapper.vue:22-25`) | list `max-w-5xl`; builder full viewport | `max-w-5xl` (`CampaignLayout.vue:26,51-52`) | `max-w-5xl` | lists `max-w-5xl`; wizards `max-w-7xl`; forms `max-w-2xl` | n/a (three-pane) |

Five header components render "a page title" with five prop vocabularies and five type treatments
(`system-scaffolding.md` I-1), and **nine pages hand-roll a header entirely** (I-4), so they will not
inherit any header restyle. Heading level does not track visual level: `BaseSettingsHeader` uses `h1`,
`SettingsSubPageHeader` puts the same `text-heading-1` on an `h2`, `ReportHeader` uses a `<span>`, and
inbox detail pages have **no `h1` at all** (I-3).

### 1.2 Data presentation

| Pattern | Contacts | Audience | Automation | Flows | Campaigns | Commerce | Settings CRUD | Conversation |
|---|---|---|---|---|---|---|---|---|
| **Table** | **None.** 90px card rows, 15 per page; sorting is a menu detached from any visible column (`surface-contacts-list.md` V-18, V-20) | same | `BaseTable` 4 cols; action cell `align="end"`, **width unset** (`AutomationRuleRow.vue:74`) | `BaseTable` 4 cols, action cell `w-24`; **no scroll container** (V-12); no sort/search/filter/pagination/bulk (V-13) | Lists: cards, not tables. Analytics: `BaseTable` 4 cols + `PaginationFooter` (`CampaignDeliveryTable.vue:86`) | Hand-rolled divided rows (`commerce/Index.vue:332-338`) — a table in everything but markup | **4 of 8** on `BaseTable` (labels, canned, macros, agent bots); **4 hand-rolled `divide-y` stacks** (agents, teams, inboxes, attributes) | Card list; labels render as **dots** here and chips everywhere else (`CardLabels.vue:83-91`) |
| **Sort / sticky / h-scroll** | menu-only sort, no sticky, no h-scroll | same | none passed | none passed | none passed | none | none passed on any of the 8; canned hand-rolls its own sort in `header-0` with a different icon family (`canned/Index.vue:184-201`) | `ConversationBasicFilter` 5 statuses × 10 orders |
| **Status / badge** | **Blocked contacts are filterable and togglable but carry no badge** (V-48); presence dot only | same | Delay badge "Runs after 4h" (`AutomationRuleRow.vue:47-56`) + `Switch` for active | Same state coloured two different ways in two views (V-08); the status logic is written **twice** (V-09) | Neutral `h-6 px-2 rounded-md bg-n-alpha-2 text-xs` + tone-by-text (`CampaignCard.vue:108-113`); `DeliveryStatusBadge` 6 states on `bg-n-{c}-3/text-n-{c}-11` | 4-colour dot + label (`commerce/Index.vue:35-40, 350-357`); order chips `px-1.5 py-0.5 rounded-md text-label-small` | Inline per row; agent bots use the **legacy** `-5/-7/-12` ramp (`agentBots/Index.vue:154`) | `CallStatusBadge` fixed `w-20`; SLA chip differs between condensed and expanded cards (P1) |
| **Row actions** | Card-level; selection checkbox is **mouse-only** (V-02, V-23); delete styled as the least important control (V-07) | same | `Switch` + 3 icon buttons; per-row spinner wired **only** to delete (`Index.vue:243`) | 3 ways to open a flow, two on the same row (V-15); disabled Delete never says why (V-14) | 1–2 icon buttons in a `w-20` column; no duplicate, pause, send-now or inline toggle | Up to 5 contextual buttons per row + per-row busy spinner (`Index.vue:439-513`) | icon Edit + icon Delete, or `router-link` Settings + delete; action column `w-24` / `w-12` / unset | Context menu (`contextMenu/Index.vue`) + bulk bar |
| **Pagination** | `PaginationFooter` (15/page) **and** a "Load more" append model in search mode (V-05) | same | none | none | none on lists; `PaginationFooter` on analytics | none | none on any of the 8 | infinite scroll |

### 1.3 States

| Pattern | Contacts | Audience | Automation | Flows | Campaigns | Commerce | Settings CRUD | Conversation |
|---|---|---|---|---|---|---|---|---|
| **Empty state** | `EmptyStateLayout` hero with 5 ghosted demo cards — **only on 1 of the 4 list routes** (V-15); the demo cards call a function that does not exist (V-16) | one-line sentence (`ContactsIndex.vue:116-123`) | Bespoke centred stack + 2 buttons, inverted hierarchy (`Index.vue:377-403`); separate in-table no-data row with 3 different copies (`:104-108`) | Bespoke, **text-only, no icon** (V-11), inverted hierarchy (V-10) | `EmptyStateLayout` + 4 ongoing / 4 one-off fake campaigns, `pt-14` | Bordered card + `size-12 rounded-full` icon puck, `min-h-60` (`Index.vue:318-330`) | `SettingsLayout`'s **hard-coded** `<p class="py-20">` — not a slot, so no page can add an illustration or CTA (`system-scaffolding.md` I-8) | Own illustration + `FeaturePlaceholder` (`EmptyState.vue:88-95`) |
| **Loading** | **Five copies of a bare centred spinner, no skeletons** (V-14) | same | `woot-loading-state` message + spinner (`SettingsLayout.vue:28-30`) | List: same. **Sessions panel has no loading state at all** (V-31) | Centred `Spinner py-10`; metric cards have hand-rolled skeletons | `woot-loading-state` | `woot-loading-state` on all 8; `BaseTable`'s skeleton rows unused | Full-pane states (`EmptyState.vue:37-42, 69-72`) |
| **Error** | **None.** `get`/`search`/`active`/`filter` all swallow failures (`store/modules/contacts/actions.js:71-73, 86-88, 101-103, 318-320`) | same | Toasts; the panel correctly **stays open** on a failed save (`Index.vue:271-277`) | Inbox connect/disconnect and Disable **fail silently** (V-32); the errors panel truncates at 8 with no notice (V-16) | **None.** `// Ignore error` (`store/modules/campaigns.js:62-64`) — a failed fetch renders as "empty" | Toast only (`Index.vue:75-77`) | Toasts via `useAlert` | §3.11 of that audit |
| **Filters** | search + sort + condition panel + chips + clear-all + saved segments | search hidden; chips shown but **clear-all suppressed** (`ContactsActiveFiltersPreview.vue:86`); filter icon becomes `pen-line` | search + tabs only | **none** | **none** | **none** | search only, and it is `hidden sm:flex` (`BaseSettingsHeader.vue:107`) | no search, no chips, no count; clear-all is a back-chevron whose **tooltip** is the label (`ChatListHeader.vue:81-91`) |
| **Create flow** | `Dialog 3xl` (`CreateNewContactDialog.vue:42-74`) | `Dialog` reused for create **and** duplicate (`CreateSegmentDialog.vue:53-68`) — good | `SidePanel 3xl` (`AutomationRuleForm.vue:295`) | `Dialog lg` → full-bleed builder route | **Anchored popover `w-[25rem] absolute top-10`**, three copies with three different max-heights: `85vh` / `80vh` / **none** | `Dialog md`, `ProviderPicker` → per-provider dialog | **Four shapes**: legacy `woot-modal` 600px; child-renders-its-own-modal (double backdrop, double X, double Escape listener); next-gen `Dialog`; full-page wizard | `ComposeConversation` popover |
| **Dialog width** | `3xl` create / `lg` confirm; **merge and delete are `Popover`s, not modals** (`containers` #17) | `Dialog` | `SidePanel 3xl` | `lg`; recipes `2xl` | 400px popover | `md` | legacy `w-full max-w-[37.5rem]` (`components/Modal.vue:93`) — no Teleport, no focus trap | legacy `modal-big`, `full-width`, 900px shortcuts modal |
| **Mobile (390px)** | header stacks into a 6-control row (V-34); sort panel positioned off-screen (V-31); a 4rem invisible strip covers the detail page (V-32) | same | search + help link hidden below `sm` | **nodes cannot be added at all below 768px** (V-24); header can eat a quarter of the viewport (V-26) | `max-w-5xl` column collapses; popover is `w-[25rem]` = 400px on a 390px viewport | dialogs are `Dialog md` so they fit | search + help link hidden below `sm` on 18 pages (I-10); no sheet pattern, so a 600px dialog is the phone experience | panel covers the thread with **no in-panel way back** (`surface-contact-panel.md` V-22) |

**No sheet or bottom-drawer pattern exists anywhere.** Zero hits for `bottomsheet`, `bottom-sheet`,
`translate-y-full`, or a `fixed inset-x-0 bottom-0` overlay. The only responsive container in the
product is `Popover.vue`, which switches to a top-anchored centred card below `md`
(`popover/Popover.vue:40-43, 141-161`).

---

## 2. Top visual issues, most severe first

Each names the surfaces hit and the component a fix extends. Ordered by reach × user cost.

### 1. An entire token layer and five primitive upgrades exist and are unused
Elevation, blur, radius-role, control-height and z-index tokens were added to
`tailwind.config.js:62-98` with light/dark CSS vars behind them; `BaseTable` gained sorting, sticky
headers, horizontal scroll, hover, selection and skeleton rows; a `Skeleton` primitive and a single
`.focus-ring` utility were created. Adoption: `h-control-*` **0 files**, `z-drawer`/`z-modal`/`z-toast`
**0 occurrences**, `shadow-modal` **2 files**, `blur-panel` **2 files**, `rounded-overlay` **3 files**,
`Skeleton` **1 consumer**, `.focus-ring` **5 consumers**, and `sortableColumns`/`stickyHeader`/
`scrollable` **0 call sites**. Meanwhile the values they replace are still everywhere: 43
`backdrop-blur-[100px]`, 23 arbitrary z-indexes (`z-[9999]` ×8, `z-[100]` ×9), 33 raw `box-shadow`
declarations, `h-[3.25rem]` ×8, `h-[2.5rem]` ×6.
**Surfaces:** all eight columns, plus Reports, Help Center, Captain, Calls, the sidebar.
**Fix shape:** nothing to build. Swap class strings onto the existing tokens and pass the existing
`BaseTable` props. This is also the prerequisite for every other issue below — a badge system, a
table pass or a dialog migration done before the tokens land will bake the arbitrary values in again.
**Risk: low**, and it is the only item on this list that is purely mechanical.

### 2. Status is 60 ad-hoc treatments and no component — `Label.vue` is the seed
Every module shows state, and no two show it the same way: 6 colour ramps, 5 radii, 7 height
policies, 7 type classes, and two per-domain components (`CallStatusBadge` fixed `w-20`
`text-label-small`; `DeliveryStatusBadge` auto-width `text-xs font-medium`) that disagree with each
other while using the same `-3`/`-11` ramp (`system-data-display.md` §10). Three parallel
*availability* ramps exist for one semantic: `-9` dots (`SidebarProfileMenuStatus.vue:36`), `-10`
dots (`avatar/Avatar.vue:79-81`), `-11` text (`AccountHealth.vue:44-48`).
**Surfaces:** all eight columns, plus Reports, Help Center, Captain, Calls.
**Fix shape:** extend `components-next/label/Label.vue` (6 validated colours, 2 sizes, `icon` and
`action` slots, colour dot, token-backed `n-label-color`/`n-label-border`) with a `tone` vocabulary
encoding the consensus already implicit in ~20 maps — teal=success, amber=pending, ruby=failed,
blue=in-progress, slate=neutral, iris=read — and a `subtle` variant for the ~15 `bg-n-alpha-2`
tone-by-text chips. Default to `bg-n-{c}-3`/`text-n-{c}-11` so the largest group migrates with no
visual change. **Risk: medium** (touch count is large, but each site is a class-string swap).

### 3. `BaseTable` grew sort, sticky headers, h-scroll, hover, selection and skeletons — and no page passes any of them
`BaseTable.vue:18-54` declares `sortableColumns`/`sortBy`/`sortOrder`/`@sort`, `stickyHeader`,
`scrollable`, `loading`+`loadingRows`; `BaseTableRow.vue:11-21` has `hoverable` (default on),
`selected` and `aria-selected`. A grep for the first three props across the whole dashboard returns
only `BaseTable.vue`. Consequences on real pages: Flows has a 4-column table with no scroll container
(V-12) and no sorting at all (V-13); canned responses hand-rolls a sort control with the wrong icon
family and without the `aria-sort`/`TABLE.SORT_BY` it would have inherited (`canned/Index.vue:184-201`);
automation, labels, macros, SLA, webhooks and audit logs all show a bare spinner above a table that can
draw its own skeleton.
**Surfaces:** Automation, Flows, Settings CRUD (4 pages), Settings admin (SLA, webhooks, audit logs,
dashboard apps, integration hooks), Campaigns analytics.
**Fix shape:** pass the existing props. **Risk: low.**

### 4. Four tables, three paginations, four loading idioms — inside Reports alone
`components/table/Table.vue` + `table/Pagination.vue` (Agent/Team), the same table with no pagination
(`SummaryReports.vue:213`), hand-rolled `<table>` (`CsatTable.vue:150-241`), and CSS-grid pseudo-rows
(`SLATable.vue:57-105`). Three pagination systems with three default page sizes (16/10/25) and two
i18n namespaces. Three loading idioms on adjacent pages, two visually different spinners in one
viewport, three icons for one "info" affordance (`surface-inbox-view-reports.md` V-16 to V-19).
**Surfaces:** Reports (9 routes), CSAT, SLA, Overview.
**Fix shape:** `BaseTable` + `PaginationFooter`, after porting the two features only the legacy
pagination has (numbered page window and page-size select, already translated as
`REPORT.PAGINATION.PER_PAGE_TEMPLATE`) into `PaginationFooter`. Keep `CsatTable`'s hover/selected
classes and `CsatTableLoader`'s shape as the row-interaction and table-skeleton reference.
**Risk: high** (report tables carry drilldown and CSV export).

### 5. Two live modal engines and 14 centred widths for one job
`Dialog` (448/512/576/672/768) and legacy `Modal` (`max-w-[37.5rem]` / 900px / `modal-big` /
`full-width`) are both actively used across Settings — 52 `<woot-modal>` tags in 40 files against 60
`Dialog` files. The legacy one has been patched since the containers audit (it now has `w-full
max-w-[37.5rem]`, `role="dialog"`, `aria-modal`, `useScrollLock` and a named close button) but still
has **no Teleport** (`components/Modal.vue:2` is a standing TODO) and **no focus trap**, and it styles
its consumers' internals through descendant SCSS while two consumers style back with an identical
copy-pasted `!items-start [&>div]:!top-12 [&>div]:sticky` hack. Canned responses stacks two of them,
producing two backdrops, two close buttons and two Escape listeners (`canned/Index.vue:251-263` +
`AddCanned.vue:38,85`). `Dialog` has no close (X) control, so `:show-cancel-button="false"` leaves only
Escape and click-outside; and **0 of its 60 consumer files pass `overflowYAuto`**, so bodies clip
rather than scroll. `SidePanel` still has no focus trap. Three unrelated outside-click mechanisms
coexist (`OnClickOutside`, `vOnClickOutside`, `v-on-clickaway`).
**Surfaces:** Settings CRUD (agents, labels, canned, attributes), Settings admin (SLA, webhooks,
custom roles, dashboard apps, integration hooks), Conversation (template pickers, gallery, snooze,
Linear), Help Center.
**Fix shape:** migrate the 40 legacy files onto `Dialog` — keep both of its nested-overlay guards
(`:99-101`, `:103-108`), which encode bugs already fixed once — add an X control and a focus trap to
`SidePanel`, and seed a phone treatment from `Popover.vue`'s existing `md` switch, whose 244-line spec
already pins the contract. **Risk: medium-high** (40 files, several reaching into modal internals with
`:deep()`).

### 6. Two surfaces render a failed fetch as an empty list
Contacts swallows failures in all four list actions (`store/modules/contacts/actions.js:71-73, 86-88,
101-103, 318-320`); Campaigns has a literal `// Ignore error` (`store/modules/campaigns.js:62-64`).
An outage is indistinguishable from an empty account, and there is no retry. Flows is the same class
of bug in a different place: inbox connect/disconnect and Disable fail silently (V-32) and the errors
panel truncates at eight with no indication (V-16).
**Surfaces:** Contacts, Audience, Campaigns (×3 channels), Flows.
**Fix shape:** an `error` branch in `EmptyStateLayout` (it already has `actions` wrapped in `Policy`,
so a Retry button is a slot fill), plus surfacing the rejection the store already catches.
**Risk: low.**

### 7. Four empty-state languages, and the newest surfaces all bypass the shared one
`EmptyStateLayout` (15 consumers) renders the ghosted-real-content hero. Beside it: a bordered
icon-puck card (data imports, Commerce), a bare centred stack (Flows, Automation), a dashed
placeholder (`AssignmentPolicy/components/DataTable.vue:40-47`), plus `BaseTable`'s `td` row and
`SettingsLayout`'s hard-coded `<p class="py-20">`. The layout also hardcodes `text-3xl font-medium`
and `text-base tracking-[0.3px]` instead of the typography utilities, and has **no icon slot** — which
is exactly why the four bypasses exist. Contacts' good empty state reaches only 1 of its 4 list
routes, and its demo cards call a function that does not exist (V-15, V-16).
**Surfaces:** Contacts, Audience, Automation, Flows, Commerce, Settings CRUD, Settings admin, Captain.
**Fix shape:** add an icon/illustration slot and move `EmptyStateLayout` onto `text-heading-*`/
`text-body-*`; add the missing `emptyState` slot to `SettingsLayout` rather than replacing its
`noRecordsFound` prop. **Risk: low.**

### 8. Icon-only controls still have no accessible name, at scale
221 of 249 icon-only buttons expose no accessible name; 84 of those rely on `v-tooltip`, which emits
only `aria-describedby` while shown (`floating-vue.mjs:612,639`). `DropdownMenu` (41 consumer files)
has zero `role`/`aria-*` on its items and no arrow-key navigation. `ConversationCard` and seven other
`role="button"` divs are mouse-only. `woot-tabs` is a non-focusable `<a>`. Contacts' row-selection
checkbox has no name and a swallowed click (V-23); Flows still has nine unnamed controls (V-01) and
five form controls with no label at all (V-03).
**Surfaces:** every one.
**Fix shape:** hang the requirement off `Button`'s existing derived `isIconOnly`
(`Button.vue:209,213`); give `DropdownMenu` the listbox semantics `ComboBoxDropdown.vue:93-104`
already implements correctly; apply `TemplateCard.vue:37-41`'s `role="button"`+`tabindex`+Enter/Space
pattern verbatim to the 8 mouse-only divs; copy `Input.vue:36-37`'s `uniqueId` fallback into
`TextArea`, `Checkbox` and `InlineInput`. **Risk: low.**

### 9. Button hierarchy inverts between a page's header and its own empty state
Automation: header is Recipes `faded slate` + Create `solid blue`; empty state swaps them
(`Index.vue:353-365` vs `:389-401`). Flows does the same (V-10). Contacts goes further — the primary
way into a contact is a 12px text link inside a metadata run (V-04), "Add contact" hides in an ⋮
menu, destructive delete is styled as the least important control on the page (V-07), and the same
button means two different things depending on the route (V-08). Campaigns glues the title and its
status pill into a `w-fit` box so the card's primary identifier truncates while space to its right
stays empty (`CampaignCard.vue:102-113`).
**Surfaces:** Automation, Flows, Contacts, Audience, Campaigns, Commerce (§3.4 of that audit).
**Fix shape:** no new component — `Button`'s variant×colour matrix already expresses the intended
ranking; the fix is choosing one ranking per action and keeping it across header, row, empty state
and dialog footer. **Risk: low.**

### 10. Five page-header components, nine hand-rolled headers, two unreconciled "go up" affordances
`BaseSettingsHeader` (35 consumers), `SettingsSubPageHeader` (16), `SettingsHeader` (1 shell/12
routes), `ReportHeader` (10), `SettingIntroBanner` (1) — five prop vocabularies, five type
treatments, nothing shared. Nine pages bypass all of them (I-4). `BaseSettingsHeader` renders a
fragment with default `inheritAttrs`, so no parent can style it — and `captain/Index.vue:136` already
passes an `icon-name` that silently does nothing (I-2). Back-button and `Breadcrumb` coexist with no
reconciliation, and `AgentAssignmentCreatePage.vue:51-64` pushes a hard-coded URL string to work
around the breadcrumb API (I-5). The `#count` chip is copy-pasted verbatim into 17 pages with 17
different truthiness guards (I-21).
**Surfaces:** all of Settings (35+ pages), Reports, Captain, inbox detail.
**Fix shape:** re-skin `BaseSettingsHeader` and use `ImportDetailHeader.vue:76-146` — the one working
extension, which wraps it and overrides `#title`/`#description` — as the template for the nine
hand-rolled ones. Keep the slot set and `v-model:search-query`. **Risk: medium.**

### 11. Six near-identical page shells with no shared base, and six measures for one column
`CampaignLayout`, `CampaignAnalyticsLayout`, `ContactsListLayout`, `CompaniesListLayout`,
`HelpCenterLayout` and `captain/PageLayout` all render
`section` + `header.sticky.top-0.z-10.px-6` + `main.flex-1.px-6.overflow-y-auto` + a sticky
`PaginationFooter class="max-w-[67rem]"` — and disagree on header height (`h-20` / `py-6` / `py-7`),
z-index (`z-10` / `z-20`) and body padding (I-19). Contacts shows three different measures on one
surface: list `max-w-5xl`, its own pagination row `max-w-[67rem]` (V-10), detail `max-w-[40.625rem]`
with a hard-coded centring nudge (V-11).
**Fix shape:** extract the skeleton the six already share and have them consume it; promote
`max-w-5xl`+`px-6` (lists) and `max-w-2xl` (single-column forms) to the shell instead of per-page
classes. **Risk: medium.**

### 12. Mobile is unfinished in ways that remove function, not just polish
Flows: **nodes cannot be added at all below 768px** (V-24), the app's own floating buttons sit on top
of the zoom controls (V-25), and at 390px the header can consume a quarter of the viewport (V-26).
Settings: search **and** the help link vanish below `sm` on 18 pages with no replacement (I-10).
Contacts: the sort panel is positioned off-screen (V-31) and a 4rem invisible strip covers the detail
page (V-32). Contact panel and its edit drawer stack two full-screen overlays with no in-panel way
back (V-22, V-23). Sidebar: navigating does not close the flyout, there is no scrim, no focus
containment, and a closed sidebar's ~43 links stay tabbable (`system-navigation.md` 19-20).
**Fix shape:** `Popover.vue`'s `md` switch is the only existing precedent and the natural seed; the
`scrollable` prop on `BaseTable` is the table half of the answer. **Risk: medium.**

### 13. RTL is deliberate but done by hand, and the hand slips
649 `ltr:`/`rtl:` utility pairs, **241 bare physical utilities with no direction handling**, and four
different ways to read direction. Two dropdowns say `ltr:right-0 rtl:right-0` (pinned right in both
directions). `Avatar`'s presence badge uses physical `top`/`left`. Contacts' sidebar divider is a
physical border (V-27), its attribute search is physically padded (V-28), and it carries a fixed
140px label column in raw pixels (V-30).
**Fix shape:** `components-next/sidebar/SidebarGroupSeparator.vue` is already fully logical
(`ms-5`, `pe-14`, `end-2`, `border-s-2`, `rounded-es`, including pseudo-element positioning) — use it
as the conversion pattern. Keep the 14 deliberate `dir="ltr"` pins (order numbers, URLs, API keys, the
flow canvas): removing them inverts real data. **Risk: medium.**

---

## 3. Unnecessary divergence — patterns solved N ways

Each row: every variant named, one recommended target. Divergences that are *justified* are in §3.1.

| Pattern | N | Variants (all of them) | Recommended target |
|---|---|---|---|
| **Status / badge** | 60 treatments, 6 ramps, 5 radii, 7 heights, 7 type classes | `CallStatusBadge` (`w-20`, `text-label-small`, icon) · `DeliveryStatusBadge` (auto-width, `text-xs font-medium`, no icon) · commerce order status · commerce payment status · commerce neutral fallback · Shopify financial status (`rounded` 4px, the only one) · template status (`shrink-0` in one place, not the other) · import status dots · store status dots · availability `-9`/`-10`/`-11` · campaign card neutral chip · `UnreadBadge` (teal `h-4`, caps at 9) · `SidebarUnreadBadge` (slate `h-5`, caps at 99) · `SidebarGroupHeader` (byte-identical copy of the latter) · 45 more in `system-data-display.md` §10 | Extend `components-next/label/Label.vue` with `tone` + `variant="subtle"`; default ramp `bg-n-{c}-3`/`text-n-{c}-11`; `text-label-small` |
| **Tables** | 6 | `components-next/table/BaseTable.vue` (15 sites) · legacy TanStack `components/table/Table.vue` · `reports/CsatTable.vue` · `reports/SLA/SLATable.vue` (CSS grid) · `AssignmentPolicy/components/DataTable.vue` (CSS grid) · `TableHeaderCell.vue`+`TableFooter.vue` · 4 hand-rolled `divide-y` stacks in Settings CRUD | `BaseTable`, using the props it already has; lift `CsatTable.vue:167-171`'s hover/selected into `BaseTableRow` (already done) and `SortButton.vue:9-13`'s icon triplet (already done) |
| **Pagination** | 3 | `PaginationFooter` (14 sites, 16/page) · `components/table/Pagination.vue` (10/page, numbered window + page-size select) · `components/widgets/TableFooter.vue` (25/page) · plus `inbox/.../PaginationButton.vue` | `PaginationFooter`, after porting the numbered window and page-size select |
| **Paging model inside one list** | 2 | Contacts: `PaginationFooter` in normal mode, append-style "Load more" in search mode (V-05) | One model per list |
| **Modal / dialog engines** | 4 | native `<dialog>` `Dialog` (63 mounts) · legacy fixed-div `Modal` (52 tags) · Teleport+transition `SidePanel` (8) · measured-fixed `Popover` (8) | `Dialog` for modals, `SidePanel` for drawers, `Popover` for anchored panels; retire `Modal` |
| **Centred modal widths** | 14 | 384 (`max-w-sm`, dead) · 384 (`w-96`) · 448 · 512 · 576 · 600 (legacy `max-w-[37.5rem]`) · 672 · 720 · 768 · 900 · `modal-big` · `full-width` · 2× `fixed inset-0` | The `Dialog` scale; delete the legacy one |
| **Outside-click** | 3 | `OnClickOutside` component · `vOnClickOutside` directive · `v-on-clickaway` legacy | `vOnClickOutside` |
| **Direction source of truth** | 4 | Vuex getter · `document.querySelector('#app[dir]')` · Tailwind `ltr:`/`rtl:` variants · raw `[dir='rtl']` CSS | The Vuex getter (`store/modules/accounts.js:34-43`) + logical utilities |
| **Focus treatment** | was 5, now 6 | the new `.focus-ring` (5 consumers) · `Switch`'s ring · `Accordion`'s `focus-visible:ring-1` · `RadioCard`'s `focus-within:has-[:focus-visible]:ring-2` · `outline-transparent` no-op · two global rules that **delete** outlines (`_base.scss:60-64`, `_woot.scss:263`) | `.focus-ring`; delete the two global suppressions |
| **Spinners** | 5 | `components-next/spinner` SVG arc (89 sites, **inert stroke attrs**) · `shared/components/Spinner.vue` SCSS ring (22 files) · `CopilotLoader` dots · `MessageList` dots (different delays) · `AILoader` | `components-next/spinner`, with the three camelCase attributes fixed |
| **Skeletons** | 4 base colours, 2 animations, ~20 sites | `bg-n-slate-3 animate-pulse` · `bg-n-slate-4/dark:bg-n-slate-6` + `animate-loader-pulse` · `bg-n-alpha-3` · `bg-woot-100` | `components-next/skeleton/Skeleton.vue` (exists, 1 consumer) |
| **Empty states** | 6 | `EmptyStateLayout` hero · bordered icon-puck card · bare centred stack · dashed placeholder · `BaseTable` `td` row · `SettingsLayout`'s hard-coded `<p>` | `EmptyStateLayout` + an icon slot; add an `emptyState` slot to `SettingsLayout` |
| **Page headers** | 5 + 9 hand-rolled | `BaseSettingsHeader` · `SettingsSubPageHeader` · `SettingsHeader` · `ReportHeader` · `SettingIntroBanner` | `BaseSettingsHeader`, extended the `ImportDetailHeader` way |
| **Page shells** | 6 copies of one skeleton | `CampaignLayout` · `CampaignAnalyticsLayout` · `ContactsListLayout` · `CompaniesListLayout` · `HelpCenterLayout` · `captain/PageLayout` | Extract the shared skeleton once |
| **Delete confirmation** | 3, uncorrelated with danger | plain two-button (agents, labels, canned, macros) · type-the-name (attributes, teams, inboxes) · `Dialog type="alert"` (agent bots, contacts, commerce, flows) | `Dialog type="alert"`, with type-the-name reserved for genuinely irreversible objects — note deleting a label (detaches from every conversation) is currently one click while deleting an attribute needs the name typed |
| **Create flow** | 4 shapes | legacy `woot-modal` wrapping a child · child that renders **its own** modal (double backdrop) · next-gen `Dialog` · full page / wizard | `Dialog` for simple objects, a wizard route for heavy ones; never the self-rendering-modal shape |
| **Create popover** | 3 copies | live chat `max-h-[85vh]` · WhatsApp `max-h-[80vh]` · SMS **no max height, no scroll** | One popover component |
| **Form field vocabularies** | 4+ | raw `<input>`/`<select>` with `label.error` (57 text, 36 checkbox, 17 select) · deprecated `woot-input` (logs a dev warning) · `v3/components/Form/Input.vue` · `components-next/Input`/`TextArea`; `attributes/AddAttribute.vue` mixes two in one form; `components-next` bypasses its **own** `Checkbox` in 9 places | `components-next/input` family; `Input.vue:36-37`'s `uniqueId` as the label-association pattern |
| **Tabs** | 3 | next-gen segmented `TabBar` · legacy underlined `woot-tabs` (non-focusable `<a>`, no tab ARIA) · `components/ui/Tabs` | `TabBar` |
| **Sort controls** | 6 | `ContactSortMenu` · `CompanySortMenu` (the same 130-line component again) · `ConversationBasicFilter` (third copy of the `w-72` + two-`SelectMenu` layout) · `SidebarSortMenu` · `InboxDisplayMenu` nested popover · audit-log `DropdownMenu` whose label is the state | One sort control, plus `BaseTable`'s column sorting where a table exists |
| **Clear-all semantics** | 7 | Contacts (clears **and** refetches, panel stays open showing a reset row) · Conversations (resets local rows only, applied filter survives) · `ActiveFilterPreview` emit · `ChatListHeader` back-chevron (tooltip-only label) · Reports `clearAllFilters` · Calls (clears one dimension) · audit logs / Help Center / Inbox: **none** | One `clearFilters` contract |
| **Active-filter signalling** | 8 | brand dot · chip row · chip row with clear suppressed · header border + count pill + back-chevron · chip with count and `x` · `ActiveFilterChip` + "Clear all" · dropdown-label-as-state · checkbox checked state. **No surface shows a numeric count of active conditions** | `ActiveFilterPreview` + a condition count |
| **Filter chips** | 3 | `ActiveFilterPreview` (Contacts) · `Button variant="outline"` + `x` (Calls) · `ActiveFilterChip` (Reports/CSAT/SLA) | `ActiveFilterPreview`, with per-chip remove added |
| **Banners** | 5 | `components-next/banner` (28 sites, 5 colours) · legacy `components/ui/Banner.vue` (marked DEPRECIATED, 5 consumers, third ramp) · `LowBackupCodesBanner` · `CoverageBanner` · `InboxBanner` (two Captain siblings disagree: `bg-n-amber-2` vs `-3`) | `components-next/banner`; add the missing `iris` |
| **Label chips** | 2 + dots | `components-next/label/Label.vue` (17 sites) · legacy `components/ui/Label.vue` (4 files, different ramp) · conversation list renders the same data as **dots** (`CardLabels.vue:83-91`), and there are 3 `CardLabels` components | `Label.vue` |
| **`SLACardLabel`** | 3 | `components/widgets/conversation/components/` (116 lines) · `components-next/Conversation/Sla/` (61) · `components-next/Conversation/ConversationCard/` (67). Two differ in **behaviour**: one gates on `applied_sla.id`, the other also on a threshold, so one conversation shows an SLA chip in expanded view and none in condensed | One component |
| **Duplicated conversation sub-components** | 2–3 each | `InboxName` ×2 · `MessagePreview` ×2 · `VoiceCallStatus` ×2 · `CardLabels` ×3 · resolve-with-required-attributes implemented 3× | One each |
| **"Go to this conversation"** | 3 | raw `<a target="_blank">` (full page reload) · in-app `router-link` · `window.open` | `router-link` |
| **"Info" affordance** | 3 | `i-lucide-info` · `<fluent-icon icon="information" type="outline">` · `<fluent-icon icon="info">` | One icon, one size, one colour |
| **Date-range vocabulary** | 2 | Overview heatmaps: 7/14/30 days + this month + previous two · every other report: 8 `WootDatePicker` presets. "Last 14 days" exists only in one; "This week" and "Month to date" only in the other | One preset set |
| **Action-column width** | 3 | `w-24` (7 tables) · `w-12` (2) · unset (3) | Formalise `w-24` + `flex justify-end gap-3` as a `BaseTable` affordance |
| **Count chip** | 17 copies | the same `<span class="text-body-main text-n-slate-11">` with 17 different `v-if` guards | Extract it; it is already a de facto component |
| **Brand / accent colour** | 4 | `theme/colors.js:229` `#2781F6` · `_woot.scss:160` gradient · `_woot.scss:249` gradient · `Sidebar.vue:1075` `#2f6fe4` · `ConversationView.vue:239` `#6366f1` | `n-brand`, promoted to a CSS var so it can respond to dark mode and white-labelling |
| **Private token namespaces** | 2 | `--sb-*` (578 lines in `Sidebar.vue`) · `--cw-*` (489 lines in `ConversationView.vue`) — both duplicate colour, elevation and motion outside `n-*`, and `Sidebar.vue:1586-1607` **overrides `n-*` tokens from outside** | Fold into `n-*`; keep `--cw-shadow`/`--cw-shadow-hover` as the shape for a real elevation scale |
| **`99+` cap** | 2 implementations, 3 markup copies | `SidebarUnreadBadge.vue:13-15` · `SidebarGroupHeader.vue:23-25` (markup duplicated byte-for-byte) | One |
| **Overlay z-index** | 23 arbitrary values beside a 5-step semantic ladder | `z-[100]`×9 · `z-[9999]`×8 · `z-[1000]` · `z-[9990]` · `z-[10001]` · `z-[5]` · `z-[1]`×2, against `z-sticky`/`z-dropdown`/`z-drawer`/`z-modal`/`z-toast` (`tailwind.config.js:91-98`) which have **4 uses between them** | The ladder |
| **Elevation** | 3 | `shadow-raised`/`shadow-overlay`/`shadow-modal` tokens (2 files) · 7 `shadow-[…]` · 33 raw `box-shadow` · the private `--cw-shadow*` pair they were promoted from | The three tokens |
| **Backdrop blur** | 6 | `blur-panel` (2 files) · `backdrop-blur-[100px]` (**43**) · `[50px]` · `[4px]` · `[2px]` · `[0.01875rem]` | `blur-panel`, plus one small step |
| **Radius** | 5+ | `rounded-control`/`rounded-surface`/`rounded-overlay` roles (3 files) · `rounded` · `rounded-md` · `rounded-lg` · `rounded-xl` · 16 arbitrary radii (`ColorPicker.vue:67-79` alone mixes `8px/7px/8px/7px`) | The three role tokens |
| **Control height** | 2 scales | `h-control-xs/sm/md/lg` (**0 files**) · `Button`'s own `h-6/h-8/h-10/h-12` table · `h-[3.25rem]`×8 · `h-[2.5rem]`×6 | One ladder shared by buttons, inputs, selects, chips and badges |
| **Width scales** | 2 in parallel | t-shirt (`max-w-md`/`2xl`/`5xl`) · numeric (`max-w-80`/`64`/`56`) · plus 10 bespoke page measures (`max-w-[67rem]`, `[71rem]`, `[45rem]`, `[40rem]`, `[40.625rem]`, …) | `max-w-5xl` lists, `max-w-2xl` forms |

### 3.1 Divergence that is justified — leave it alone

- **Automation's builder is a `SidePanel 3xl`; Flows' builder is a full-bleed route; Commerce's connect flows are `Dialog md`.** Three different jobs: a long form you want to compare against the list behind it, a spatial graph editor that needs the whole viewport (`flows.routes.js:7-8` says so deliberately), and a short credential handshake. `surface-flow-builder.md` V-23 is right that the two Flows routes share no chrome, but the *container choice* is correct.
- **Campaigns has no search, sort, filter or pagination.** Accounts hold a handful of campaigns; the audit lists this as "absent by design today" rather than missing. Adding a filter bar for parity's sake would be uniformity for its own sake. The real campaigns gap is error state and the inverted card hierarchy.
- **Contacts and Conversations are cards, not tables, and should stay cards.** Both rows carry an avatar, a multi-line preview, labels and presence — data a 4-column table cannot hold. Contacts' real problems are the missing error state, the detached sort, the mouse-only selection and ~90px of vertical space per row (V-20) — not the absence of a table. Flows and Settings CRUD, which hold short uniform records, are the opposite case.
- **Type-the-name delete confirmation on teams, inboxes and attributes.** These cascade. The inconsistency worth fixing is the *inverse* case — one-click deletion of a label that detaches from every conversation.
- **Commerce's per-row capability lines and four status colours.** This looks like badge sprawl and is not: each line names a remedy, and each status unlocks a different action set (`surface-commerce-settings.md` §1.4). Collapsing it to one chip would delete information.
- **Contacts' segment view hiding search while showing an edit-pencil.** Inside a saved audience, free-text search over a defined set is a different question from editing the definition. Suppressing *clear-all* there (`ContactsActiveFiltersPreview.vue:86`) is correct too — there is no ad-hoc filter to clear. The bug is only the icon swap being unannounced.
- **The 14 `dir="ltr"` pins** on order numbers, URLs, API keys and the flow canvas. Load-bearing, not legacy.
- **The 6 raw `[dir='rtl']` CSS rules.** Each carries a comment explaining a third-party constraint (Vue `:global` compilation, Gmail/Outlook hard-coded `dir="ltr"`, ProseMirror internals).
- **`Popover` for contact merge and delete.** Flagged as an inconsistency (`containers` #17), but merge is a comparison against the row behind it. Worth revisiting for *delete*, not for merge.

---

## 4. What must NOT change

Things the audits found genuinely good. A redesign that loses any of these is a regression even if
every pixel improves.

### Architecture to extend, never replace
1. **The `n-*` CSS-variable token system.** 137 vars × light/dark, 8 Radix ramps + a semantic layer (`surface`, `solid`, `alpha`, `weak`/`strong`/`container`, `card`, `label`, `button`), `<alpha-value>` so opacity modifiers work, all flowing through one file (`theme/colors.js`). ~5 200 dashboard call sites. The gaps are elevation and blur, not colour.
2. **`Button`'s complete variant × colour × size matrix and its shorthand boolean attribute API.** 840 call sites; `slate xs faded` is the normal idiom, not an exception. Removing shorthands silently changes hundreds of buttons.
3. **`Dialog`'s native `<dialog>` + `showModal()` foundation**, including both nested-overlay guards (`:99-101`, `:103-108`) — those encode bugs already fixed once.
4. **`SidePanel`'s overlay choreography**: scroll-lock and focus deferred to `@after-enter` so they cost no frame of the slide, `afterLeave` for `v-if` consumers, `previousActiveElement?.isConnected` focus restore, `dialog[open]` Escape yield, and logical geometry `inset-y-3 end-3` + `rtl:translate-x-[calc(-100%-0.75rem)]`.
5. **`TeleportWithDirection.vue`** (28 lines) — the non-obvious fix for teleported content losing `[dir]`. Three surfaces depend on the `data-popover-content` / `data-popover-backdrop` / `data-dropdown-menu` attribute contract to avoid closing under their own teleported children.
6. **`useDropdownPosition.js`** — RTL align flipping, fit-aware vertical flipping, `maxHeight` derivation, `SAFE_MARGIN` viewport clamp, container constraint, relative and fixed modes.
7. **`Avatar.vue` wholesale** — 83 sites, deterministic per-name colour in both themes, 4-step image fallback, presence and channel badge slots, upload and delete affordances, a spec suite. Only the raw-hex palette and the physical badge offsets need touching.
8. **`BaseSettingsHeader`'s slot set and `v-model:search-query`.** 35 consumers, 17 bound search models. Keep the model name so no page has to change.
9. **`SettingsLayout`'s five-slot order** (`header`, `preBody`, `loading`, `body`, default-for-dialogs). 36 pages depend on it, including the unnamed default slot the file itself warns not to delete.
10. **The `BaseTable`/`BaseTableRow`/`BaseTableCell` slot contract.** 15 surfaces, 18 rows, 66 cells already speak it; every new capability lands behind a prop without touching a call site. Keep the positional `header-${index}` slot — SLA depends on indices 2/3/4 for column tooltips.
11. **`Popover.vue`'s responsive `md` switch** and its 244-line spec, which pins toggling, Escape with nested overlays, click-outside, `disableMobileView` and close-on-scroll thresholds.
12. **The logical-utility reference implementation** in `components-next/sidebar/SidebarGroupSeparator.vue` and `SidebarGroupLeaf.vue`, including pseudo-element positioning.
13. **`ComboBoxDropdown.vue`** — the only correct listbox in the repo (`role="listbox"`, `aria-multiselectable`, `role="option"`, `aria-selected`) and the shared body behind three consumers, so one fix improves all three.
14. **`RadioCard`'s full prop surface** — `disabled` + `disabledLabel` + `disabledMessage` + `beta`. Disabled-with-a-reason is product behaviour across 10 settings surfaces.
15. **`PhoneNumberInput`'s validation plumbing**, `DurationInput`'s unit-rounding watcher (its comment explains a real data-loss bug), and `ReorderableMultiSelect`'s capped-ordered-selection model with `aria-busy`.
16. **`ConfirmButton`'s two-step destructive flow** with blur-reset and 400ms auto-reset.
17. **The nine typography utilities and their documented use-case table** (`_woot.scss:69-148`). The job is finishing adoption, not authoring a new scale.
18. **`CustomBrandPolicyWrapper`** as the white-label gate, and `replaceInstallationName` as the string-level one.
19. **The new token layer itself** — `shadow-raised/overlay/modal` with light+dark vars, `blur-panel`, the `rounded-control/surface/overlay` role names, the `h-control-*` ladder and the `z-sticky/dropdown/drawer/modal/toast` ladder (`tailwind.config.js:62-98`, `_next-colors.scss:155-162, 319-323`). It is the correct answer to the four gaps the token audit named (elevation, blur, control height, z-index). Adopt it; do not re-derive it.
20. **The single `.focus-ring` utility** (`_base.scss:84-86`), expressed as an outline rather than a ring so it needs no background colour and works on any surface. It is the recipe from `Switch`, which was the one correct convention. The remaining work is deleting the two global rules that still suppress outlines (`_base.scss:60-64`, `_woot.scss:263`), not replacing this.

### Product behaviour that reads as craft
21. **Honest, qualified numbers.** Commerce says figures are *visible* orders, not lifetime totals; every backend code is written out rather than interpolated; a raw provider error is never shown. Campaigns' live server-side recipient count — the best idea on that surface — and its delivery breakdown doing arithmetic users get wrong. Reports' metric trends with correct polarity and unit-aware duration formatting.
22. **Every blocked state names its remedy, and the remedy is a button where it applies.** Commerce settings' per-store capability lines, per-provider disconnect consequences, and plan limits explained with a route out.
23. **"Processing" is a first-class state, not a spinner** (Campaigns analytics), and the analytics page distinguishes three different kinds of "nothing".
24. **Cross-module shortcuts that ask the destination for permission first.** `ContactMoreActions.vue:43-53` resolves the target route and checks its `featureFlag`, `permissions` and `installationTypes` before rendering itself — so a shortcut never offers a page the page would refuse. This is the model for every new cross-link.
25. **Dependency and consequence shown where the action is.** "Used by 2 automation rules · 1 campaign" sits in the menu that can delete the audience; the shared-audience notes explain read-only, editable and "saving changes what they match at once" inside the editor.
26. **One coherent audience model.** A filter, a saved audience and a preset all produce `{ payload: [conditions] }` through one create call; duplicating reuses the create dialog instead of inventing a second one; nothing is copied or frozen.
27. **Automation's delayed-rule editor as a plain-language abstraction**, its private-note guard, run-type drafts preserved across switching, saved connectors surviving edits, and recipes that create real rules **switched off** and open them for review.
28. **Flows' repair loop**: validation errors are navigable, not a wall of text; dirty-state tracking is structural rather than a flag; Test Mode is the real runtime and says so; option ids are stable so renaming never breaks wiring; the canvas tells three states with three outlines.
29. **Write actions as a reviewed, confirmed, idempotent four-step flow** (Commerce orders), with unresolved outcomes stated rather than guessed, and refund/cancel limited to administrators — said out loud on the row.
30. **Destructive confirmations that read the record's name back**, consistently permission-gated, with singular/plural-correct copy that states the consequence and that it cannot be undone.
31. **Specific error vocabulary on writes.** Duplicate email and duplicate phone get their own messages; server-supplied messages pass through; only the unknown case falls back to generic — in three separate call sites. Voice calling distinguishes four outcomes.
32. **Latest-request-wins fetching and request-race handling** — Contacts' condition search drops stale responses and resets rather than hanging; Campaigns handles it twice; Commerce has `useAbortableRequest`.
33. **Per-row, non-blocking validation** with inline errors and a wiggle, cleared the moment the row is edited, plus a whole-panel validation before apply.
34. **User-ordered, user-collapsed sidebar sections persisted server-side**, with attribute order shared between the contact panel and the contact detail page so one preference governs both.
35. **Context preserved in the URL.** Page and search in the query; opening a contact from inside an audience or a label keeps that context in the route; the detail breadcrumb prefers real history over a hard-coded path; audit-log filter state and report deep links are shareable; the audience deep link is idempotent.
36. **Selection survives paging but not context changes** — deliberate, so a user cannot act on records from a view they have left.
37. **Inbox two-pane triage** that keeps the queue in view, with prev/next walking and a position counter; both relative and exact timestamps; filter + sort surviving reloads; expressive snooze.
38. **Reports' chart→record drilldown** into cards that are genuine cross-module hubs; charts themed through design tokens; CSV export where it makes sense; page size remembered per user.
39. **The 10 header affordances that already exist at some breakpoint** and must not be dropped: per-page search, the "Learn more" link, the item count, the count/actions divider, the back button, the `meta` line (templates' last-sync time), `TabBar` tabs, audit-log filters in the header, assignment-policy breadcrumbs, and report download buttons.
40. **The load-bearing selectors and element ids** in `surface-conversation-workspace.md` §2.16 — `div.conversations-list div.conversation`, `.conversations-list`, `#conversationAttachment`, `ninja-keys`, `#saveFilterTeleportTarget`, `#conversationFilterTeleportTarget`, `.resizable-editor-body`, `.drag-handle`. These are queried from JavaScript. Renaming one breaks Alt+J/Alt+K navigation, "resolve and next", the attachment shortcut, snooze pickers, filter-panel anchoring, the composer clamp or sidebar reordering — with no test or type error.
41. **Keyboard infrastructure that already works**: `useKeyboardEvents.js`'s typeable-element guard, `useKeyboardNavigableList.js`, `Cmd/Ctrl+S` in the flow builder working while a config field has focus, keyboard-layout awareness in the conversation shortcuts, and the command palette's `goto_*` entries.
42. **Complete Arabic translation on the Lynomia surfaces**, locale-formatted money and time with safe fallbacks, and `data-test-id` hooks on the load-bearing controls.

---

## 5. Feature parity totals

| Surface audit | Parity rows | Visual findings |
|---|---:|---:|
| `surface-settings-admin.md` | 376 | 55 |
| `surface-settings-crud.md` | 338 | 62 |
| `surface-inbox-view-reports.md` | 316 | 75 |
| `surface-conversation-workspace.md` | 254 | 81 |
| `surface-campaigns.md` | 247 | 91 |
| `surface-flow-builder.md` | 247 | 38 |
| `surface-contacts-list.md` | 227 | 52 |
| `surface-contact-panel.md` | 225 | 33 |
| `surface-commerce-panel.md` | 197 | 64 |
| `surface-commerce-settings.md` | 176 | 102 |
| `surface-automation.md` | 168 | 81 |
| **Total** | **2 771** | **734** |

Counting method: parity rows are numbered rows in each audit's §2 manifest tables (`| 1 |` …, or
`| A1 |` … in `surface-settings-admin.md`). Findings are the labelled items in each §3 — `### V-nn`
headings in contacts-list, contact-panel and flow-builder; `**V-nn —**` / `**Vnn —**` labels in
inbox-view-reports, settings-admin and settings-crud; `**X-nn**` labels in conversation-workspace and
commerce-panel; `**3.n.n**` labels in automation and campaigns; numbered list items in
commerce-settings. Totals are controls, states and affordances — not files or lines.

The eight system audits are not counted here; they inventory shared primitives rather than
user-reachable features. For reference they establish: 840 `Button` call sites, 150 `Input`,
83 `Avatar`, 63 `Dialog` mounts, 52 `<woot-modal>` tags, 41 `DropdownMenu` consumer files,
35 `BaseSettingsHeader` consumers, 28 `Banner`, 21 `CardLayout`, 15 `EmptyStateLayout`,
15 `BaseTable` call sites, 14 `PaginationFooter`, 89 `Spinner`, ~43 sidebar nav entries,
60 distinct status treatments, 14 centred-modal widths, 137 colour tokens and 9 typography utilities.
