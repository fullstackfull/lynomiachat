# Surface audit — Contacts list, audiences (segments) and contact detail

Read-only audit. 227 parity rows, 52 visual findings. This document is the **baseline** for the feature-preservation contract of the
visual/interaction modernization phase: every row of the parity manifest in §2 must still exist, and must
be no harder to find, after any redesign. Every assertion is anchored to `file:line` in the current tree.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`. All paths below are relative to
`app/javascript/dashboard/` unless stated otherwise.

---

## 1. Routes and primary task

### 1.1 Route list

All seven routes are declared in `routes/dashboard/contacts/routes.js` and share one `meta`
(`routes.js:6-9`):

```
featureFlag: FEATURE_FLAGS.CRM
permissions: ['administrator', 'agent', 'contact_manage']
```

| Path | Name | Component | File |
|---|---|---|---|
| `/app/accounts/:accountId/contacts` | `contacts_dashboard_index` | `ContactsIndex.vue` | `routes.js:17-22` |
| `/app/accounts/:accountId/contacts/segments/:segmentId` | `contacts_dashboard_segments_index` | `ContactsIndex.vue` | `routes.js:23-28` |
| `/app/accounts/:accountId/contacts/labels/:label` | `contacts_dashboard_labels_index` | `ContactsIndex.vue` | `routes.js:29-34` |
| `/app/accounts/:accountId/contacts/active` | `contacts_dashboard_active` | `ContactsIndex.vue` | `routes.js:35-40` |
| `/app/accounts/:accountId/contacts/:contactId` | `contacts_edit` | `ContactManageView.vue` | `routes.js:48-53` |
| `/app/accounts/:accountId/contacts/:contactId/segments/:segmentId` | `contacts_edit_segment` | `ContactManageView.vue` | `routes.js:54-59` |
| `/app/accounts/:accountId/contacts/:contactId/labels/:label` | `contacts_edit_label` | `ContactManageView.vue` | `routes.js:60-65` |

Supporting query parameters, all read by `ContactsIndex.vue`:

- `?page=N` — current page (`ContactsIndex.vue:39`, written by `updatePageParam` `:177-189`)
- `?search=…` — search mode (`ContactsIndex.vue:37, 70`)

One route-name-sensitive behaviour chain worth recording, because a redesign will have to preserve it:
`ContactsListLayout.vue:41-60` derives *show search*, *show the active-filter chips* and *is this a label
view* purely from `route.name`, and `ContactsList.vue:55-67` maps the current list route onto the matching
detail route so that opening a contact from inside an audience or a label keeps that context in the URL.

### 1.2 Entry points into the surface

| Entry | Where | Gate |
|---|---|---|
| Sidebar → Contacts → All Contacts | `components-next/sidebar/Sidebar.vue:531-540` | route meta (CRM flag + contact permissions) |
| Sidebar → Contacts → Active | `Sidebar.vue:541-546` | same |
| Sidebar → Contacts → Segments → *one child per saved audience* | `Sidebar.vue:547-568` | same |
| Sidebar → Contacts → Tagged With → *one child per label* | `Sidebar.vue:569-592` | same |
| Command bar → "Go to Contacts" | `composables/commands/useGoToCommandHotKeys.js:53-59` | same |

### 1.3 Primary task

**Find a set of people, act on that set, and keep the set.** Concretely: browse / search / filter the
account's contacts, promote a filter into a reusable *audience* (a saved `custom_filter`), act on many
contacts at once (labels, delete), act on one contact in depth (edit, label, call, message, merge, block,
delete, notes, attributes, media, conversation history), and push an audience into the modules that
consume it (automation rules, WhatsApp campaigns) or hand it to a colleague as a link.

---

## 2. Feature parity manifest

227 rows. Grouped by where they live. "Gate" is the permission, feature flag or condition that decides
whether the control exists at all.

### 2.1 Navigation into and around the surface

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 1 | Sidebar "All Contacts" link, resets `page=1` and clears `search` | navigation | `Sidebar.vue:531-540` | CRM flag + `administrator`/`agent`/`contact_manage` |
| 2 | Sidebar "Active" link | navigation | `Sidebar.vue:541-546` | same |
| 3 | Sidebar "Segments" collapsible group with tree line, one child per contact custom view | navigation | `Sidebar.vue:547-568` | same |
| 4 | Shared audiences labelled through `SIDEBAR.SHARED_AUDIENCE` in the sidebar | state | `Sidebar.vue:555-557` | `view.shared` |
| 5 | Sidebar "Tagged With" collapsible group, one child per label with a colour swatch | navigation | `Sidebar.vue:569-592` | same |
| 6 | Command-bar entry "Go to Contacts" | navigation | `useGoToCommandHotKeys.js:53-59` | route meta |
| 7 | Route-level gate: CRM feature flag + `administrator`/`agent`/`contact_manage` | state | `routes/dashboard/contacts/routes.js:6-9` | — |

### 2.2 List header (`ContactsHeader/ContactHeader.vue`, wired by `ContactListHeaderWrapper.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 8 | Context-dependent page title: Contacts / Search contacts / Active contacts / audience name / `#label` | state | computed `ContactsIndex.vue:125-131`; rendered `ContactHeader.vue:47-49` | — |
| 9 | Search field (`type="search"`, magnifier prefix), 300 ms debounce, page reset to 1 | primary | `ContactHeader.vue:51-68`; `ContactsIndex.vue:21, 243-272, 516-518` | — |
| 10 | Search hidden in audience and Active views | state | `ContactsListLayout.vue:86` | route name |
| 11 | Filter toggle button (`i-lucide-list-filter`) | primary | `ContactHeader.vue:74-89` | not label view, not Active view (`:73`) |
| 12 | Same button becomes `i-lucide-pen-line` ("edit audience") inside an audience | state | `ContactHeader.vue:76-78` | `isSegmentsView` |
| 13 | Brand dot badge on the filter button when ad-hoc filters are applied | status | `ContactHeader.vue:85-88` | `hasActiveFilters && !isSegmentsView` |
| 14 | "Save these filters as an audience" icon button (`i-lucide-save`) | primary | `ContactHeader.vue:92-104` | `hasActiveFilters` and not audience/label/Active view |
| 15 | "Delete this audience" icon button (`i-lucide-trash`) | destructive | `ContactHeader.vue:105-117` | audience view AND `canManageSegment` (`ContactListHeaderWrapper.vue:86-88`) |
| 16 | Shared audiences are read-only for non-administrators (no delete, no update) | state | `ContactListHeaderWrapper.vue:83-88, 380, 408` | `segment.shared && !isAdmin` |
| 17 | Sort menu trigger (`i-lucide-arrow-down-up`) | primary | `ContactSortMenu.vue:97-104` | — |
| 18 | Sort-by select: Name, Email, Company, Country, City, Last activity, Created at | filter | `ContactSortMenu.vue:25-54, 114-119` | — |
| 19 | Ordering select: Ascending / Descending | filter | `ContactSortMenu.vue:56-65, 125-130` | — |
| 20 | Chosen sort persisted per user in `ui_settings.contacts_sort_by` and re-read on mount | state | `ContactsIndex.vue:53-60, 400-406, 438-448` | — |
| 21 | Default sort `-last_activity_at` (the only index-backed order) | state | `ContactsIndex.vue:19-20` | — |
| 22 | Overflow "More actions" menu (`i-lucide-ellipsis-vertical`) with `aria-label` and active-state tint | secondary | `ContactMoreActions.vue:206-215` | — |
| 23 | Menu section header "Audience" | state | `ContactMoreActions.vue:181-187` | — |
| 24 | Disabled menu row "Used by N automation rules · N campaigns" | status | `ContactMoreActions.vue:57-97` | audience open AND a non-zero count |
| 25 | "Use in a new automation rule" | contextual | `ContactMoreActions.vue:98-109` | audience `shared` AND `automation_list` reachable (flag+perms+installation, `:43-53`) |
| 26 | "Use in a new WhatsApp campaign" | contextual | `ContactMoreActions.vue:110-119` | audience `shared` AND `campaigns_whatsapp_index` reachable |
| 27 | "Duplicate this audience" | contextual | `ContactMoreActions.vue:120-129` | audience open AND `administrator`/`contact_manage` (`:34-36`) |
| 28 | "Copy link to this audience" | contextual | `ContactMoreActions.vue:130-135` | audience open |
| 29 | "New audience from a preset" | secondary | `ContactMoreActions.vue:139-150` | — |
| 30 | "Add contact" | primary | `ContactMoreActions.vue:152-158` | — |
| 31 | "Export contacts" | secondary | `ContactMoreActions.vue:159-168` | `administrator`/`contact_manage` |
| 32 | "Import contacts" | secondary | `ContactMoreActions.vue:169-177` | `administrator`/`contact_manage` |
| 33 | "Message" primary CTA → `ComposeConversation` popover (no contact preselected) | primary | `ContactHeader.vue:136-140`; label `ContactListHeaderWrapper.vue:385` | — |
| 34 | Vertical rule separating the icon cluster from the primary CTA | state | `ContactHeader.vue:135` | — |

### 2.3 Filter / audience condition builder (`components-next/filter/ContactsFilter.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 35 | Popover anchored under the filter button; full-bleed (`inset-x-0`) below `sm` | state | `ContactListHeaderWrapper.vue:400-418` | `showFiltersModal` |
| 36 | Title "Filter contacts" / "Edit audience" | state | `ContactsFilter.vue:132-136, 150-152` | `isSegmentView` |
| 37 | Audience-name input inside an audience | primary | `ContactsFilter.vue:153-161` | `isSegmentView` |
| 38 | Condition row: attribute select → operator select → value input | primary | `ConditionRow.vue:193-266` | — |
| 39 | `and` / `or` query-operator select from the second row on | filter | `ConditionRow.vue:193-200`; wiring `ContactsFilter.vue:175-186` | row index > 0 |
| 40 | Grouped attribute picker with leading icons and disabled section headers: Standard Filters / Additional Filters / Custom Attributes / Conversations / Commerce | filter | `helper/filterAttributeIcons.js:84-128`; `contactProvider.js:209-212` | — |
| 41 | Standard contact conditions: name, email, phone number, identifier, country, city, company, created at, last activity, blocked, labels | filter | `contactProvider.js:79-204` | — |
| 42 | Every contact custom attribute as a condition | filter | `contactProvider.js:68-74` | account has contact custom attributes |
| 43 | Conversation conditions: status, priority, inbox, assigned agent, assigned team, conversation labels | filter | `audienceProvider.js:94-139` | — |
| 44 | Commerce conditions: linked store, store platform, visible orders, visible spend per currency, last visible purchase, has an active order, order / payment / shipment status | filter | `audienceProvider.js:141-224` | `FEATURE_FLAGS.LYNOMIA_COMMERCE` + `CommerceAPI.getAudienceFields()` succeeded (`:63-77`) |
| 45 | Seven value input types: multiSelect, searchSelect, asyncSearchSelect (debounced, stale-response safe), booleanSelect, multiText, text/number/date | filter | `ConditionRow.vue:118-140, 221-265` | per attribute `inputType` |
| 46 | Values and operator reset when the attribute type changes | state | `ConditionRow.vue:142-165` | — |
| 47 | Per-row validation: wiggle animation + inline message, errors cleared on edit | error | `ConditionRow.vue:97-106, 167-180, 186-191, 277-279` | — |
| 48 | Remove condition (trash), last row resets to the default condition instead of vanishing | secondary | `ContactsFilter.vue:55-66`; `ConditionRow.vue:267-274` | — |
| 49 | "Add filter" | secondary | `ContactsFilter.vue:221-223` | — |
| 50 | "Clear filters" inside the panel | secondary | `ContactsFilter.vue:225-227` | — |
| 51 | "Apply filters" | primary | `ContactsFilter.vue:238-240` | not `isSegmentView` |
| 52 | "Update audience", disabled without a name | primary | `ContactsFilter.vue:228-237` | `isSegmentView` |
| 53 | Shared-audience note, three variants: read-only (member), editable (admin), "used by N rules and N campaigns" (amber) | status | `ContactsFilter.vue:118-130, 189-200` | `sharedSegment` |
| 54 | Conversation-conditions explanation note | status | `ContactsFilter.vue:101-109, 206-208` | a `conversation_*` condition is in use |
| 55 | Commerce-conditions explanation note | status | `ContactsFilter.vue:209-211` | a `commerce_*` condition is in use |
| 56 | Amber "orders not read yet for N linked contacts" warning | status | `ContactsFilter.vue:110-114, 212-218` | an order-dependent condition + `unread_contacts > 0` |
| 57 | Applied filters written to the store and reported as an analytics event | state | `ContactsFilter.vue:84-99` | on Apply |
| 58 | Close on click-outside, ignoring `#toggleContactsFilterButton` | state | `ContactsFilter.vue:139-142, 147` | — |
| 59 | Close emitted on unmount so the parent's state cannot desync | state | `ContactsFilter.vue:138`; `ContactListHeaderWrapper.vue:271-274` | — |
| 60 | An audience's saved conditions rehydrated into editable rows, including Commerce/conversation option objects | state | `ContactListHeaderWrapper.vue:298-338, 340-359`; `audienceProvider.js:264-272` | audience open |
| 61 | Seed row (`name equal_to ''`) when opening the builder with nothing applied | state | `ContactListHeaderWrapper.vue:346-356` | no applied filters, no audience |

### 2.4 Active-filter chips (`ContactsActiveFiltersPreview.vue` → `ActiveFilterPreview.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 62 | Chip strip above the list showing at most 2 conditions as `attribute operator value` | status | `ActiveFilterPreview.vue:53-101`; `ContactsActiveFiltersPreview.vue:74-90` | — |
| 63 | `and`/`or` connector rendered between the two chips | status | `ActiveFilterPreview.vue:89-99` | ≥2 conditions |
| 64 | "+N more filters" overflow affordance | status | `ActiveFilterPreview.vue:102-108` | > 2 conditions |
| 65 | Clicking a chip or the overflow opens the filter panel | secondary | `ActiveFilterPreview.vue:60, 106`; `ContactsListLayout.vue:66-68`; `ContactHeader`'s `defineExpose` `ContactListHeaderWrapper.vue:367-369` | — |
| 66 | "Clear filters" button + divider, suppressed for a saved audience | secondary | `ActiveFilterPreview.vue:109-117`; `ContactsActiveFiltersPreview.vue:86` | not an audience |
| 67 | Chips hidden in label views, Active view, and while the list is fetching | state | `ContactsListLayout.vue:53-60` | — |
| 68 | Commerce / conversation condition names and option names resolved to human labels in the chips | state | `ContactsActiveFiltersPreview.vue:50-71` | — |
| 69 | Native `title` tooltip carrying the full value on a truncated chip | state | `ActiveFilterPreview.vue:78` | — |

### 2.5 List body and contact card (`Pages/ContactsList.vue`, `ContactsCard/ContactsCard.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 70 | One card per contact in a 16 px-gap column | state | `ContactsList.vue:89-110`; `CardLayout.vue:20-36` | — |
| 71 | 42 px avatar: image, else coloured initials, else user icon | state | `ContactsCard.vue:126-132`; `avatar/Avatar.vue:84-158, 244-271` | — |
| 72 | Availability dot on the avatar; offline deliberately shows no dot | status | `ContactsCard.vue:130-131`; `Avatar.vue:78-82, 203-210` | `availabilityStatus` |
| 73 | Selection checkbox revealed as an overlay on the avatar while hovered or selected | primary | `ContactsCard.vue:133-144`; `ContactsList.vue:75-85` | pointer hover over the avatar, or already selected |
| 74 | Selected card tinted (`!bg-n-slate-3` / dark `!bg-n-solid-3`) | state | `ContactsCard.vue:116-118` | `isSelected` |
| 75 | Contact name | state | `ContactsCard.vue:148-151` | — |
| 76 | Company name with a building glyph | state | `ContactsCard.vue:152-163` | `additionalAttributes.companyName` |
| 77 | Email with a native `title` tooltip, clamped to `max-w-72` | state | `ContactsCard.vue:168-172` | `email` |
| 78 | Phone number | state | `ContactsCard.vue:174-176` | `phoneNumber` |
| 79 | Country flag + "City, Country" | state | `ContactsCard.vue:178-184`; resolution `:54-85` | a resolvable `country` or `countryCode` |
| 80 | 1 px pipe separators between metadata items | state | `ContactsCard.vue:173, 177, 185` | per preceding value |
| 81 | "View details" link button → the contact detail route | navigation | `ContactsCard.vue:186-191`; `ContactsList.vue:55-67` | — |
| 82 | Detail navigation keeps the audience / label context and the current query string | navigation | `ContactsList.vue:56-66` | route name |
| 83 | Expand chevron (rotates 180° when open) | secondary | `ContactsCard.vue:196-203` | — |
| 84 | Inline expanded editor, animated grid-rows reveal, one card expanded at a time | primary | `ContactsCard.vue:205-241`; `ContactsList.vue:30, 69-71, 100` | — |
| 85 | Expanded card re-seeds its form from props on every open (discards unsaved edits) | state | `ContactsCard.vue:95-98` | — |
| 86 | "Update contact" button with loading state, disabled while updating or invalid | primary | `ContactsCard.vue:222-230` | — |
| 87 | Inline update success / duplicate-email / duplicate-phone / message / generic error toasts | error | `ContactsList.vue:35-53` | — |
| 88 | Collapsible "Delete contact" disclosure inside the expanded card | destructive | `ContactDeleteSection.vue:29-62` | `administrator` (`:28`) |
| 89 | "This action is permanent and irreversible." + "Delete now" | destructive | `ContactDeleteSection.vue:50-59` | disclosure open |
| 90 | Delete confirmation alert dialog with success / error toasts | destructive | `ConfirmContactDeleteDialog.vue:25-53` | — |

### 2.6 Contact form (shared by the card, the create dialog and the detail page)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 91 | First name — required | primary | `ContactsForm.vue:37, 87-92, 327-346` | — |
| 92 | Last name; first+last recombined into `name` | primary | `ContactsForm.vue:38, 219-223` | — |
| 93 | Email — format validated | primary | `ContactsForm.vue:39, 89` | — |
| 94 | Phone number via `PhoneNumberInput` (dial-code picker) | primary | `ContactsForm.vue:314-319` | — |
| 95 | City | primary | `ContactsForm.vue:41` | — |
| 96 | Country combobox; also stores the country *name* alongside the code | primary | `ContactsForm.vue:42, 168-170, 246-250, 301-313` | — |
| 97 | Bio / description | primary | `ContactsForm.vue:43` | — |
| 98 | Company name free-text | primary | `ContactsForm.vue:44` | Companies flag off, or no company linked |
| 99 | Company **selector** (links to a Companies record) replacing the free-text field | primary | `ContactsForm.vue:96-104, 320-326`; `Companies/CompanySelector.vue` | `FEATURE_FLAGS.COMPANIES` cloud feature |
| 100 | Eight social handles with brand icons: LinkedIn, Facebook, Instagram, WhatsApp, Telegram, TikTok, Twitter/X, GitHub | primary | `ContactsForm.vue:47-56, 350-378` | — |
| 101 | WhatsApp handle normalised (leading `@` stripped) on load and on input | state | `ContactsForm.vue:95, 141-143, 258-266` | — |
| 102 | Legacy `socialTelegramUserName` / `socialWhatsappUserName` migrated into `socialProfiles` | state | `ContactsForm.vue:134-143` | legacy attribute present |
| 103 | Two visual densities of the same form (card vs details view) | state | `ContactsForm.vue:21-24, 306-311, 318, 332-336, 359-362` | `isDetailsView` |
| 104 | `isFormInvalid`, `resetForm`, `resetValidation`, raw `state` exposed to parents | state | `ContactsForm.vue:268-290` | — |

### 2.7 Bulk selection and bulk actions

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 105 | Bulk bar appears above the list once ≥1 contact is selected; sticky with a fade mask | bulk | `ContactsBulkActionBar.vue:83-92`; `ContactsIndex.vue:532-542` | `hasSelection` |
| 106 | Select-all checkbox with an indeterminate state, scoped to the visible page | bulk | `BulkSelectBar.vue:39-65, 82-85`; `ContactsBulkActionBar.vue:60-71`; `ContactsIndex.vue:154-162` | — |
| 107 | "Select all (N)" label showing the page size | bulk | `ContactsBulkActionBar.vue:38-46` | — |
| 108 | "N selected" running count | status | `ContactsBulkActionBar.vue:48-52`; `BulkSelectBar.vue:92-94` | — |
| 109 | "Clear selection" | bulk | `ContactsBulkActionBar.vue:93-102`; `ContactsIndex.vue:145-147` | — |
| 110 | "Assign Labels" dropdown: multi-select label list, apply / dismiss | bulk | `ContactsBulkActionBar.vue:105-110`; `conversationBulkActions/BulkLabelActions.vue:82-117, 120-130` | — |
| 111 | "Remove Labels" dropdown (same component, `action="remove"`, tag-remove icon) | bulk | `ContactsBulkActionBar.vue:111-117`; `BulkLabelActions.vue:46-67, 125` | — |
| 112 | Bulk delete button: tooltip + `aria-label`, ruby ghost, text label hidden below `md` | destructive | `ContactsBulkActionBar.vue:119-133` | `administrator` only (`:119`) |
| 113 | Bulk delete confirmation dialog with singular / plural title, description and confirm label | destructive | `ContactsIndex.vue:76-92, 567-576` | ≥1 selected |
| 114 | All bulk controls disabled and spinnered while a bulk action is in flight | state | `ContactsIndex.vue:73, 536`; `ContactsBulkActionBar.vue:108, 115, 128-129` | — |
| 115 | Selection cleared on refetch and on view change, deliberately preserved across page changes | state | `ContactsIndex.vue:200-208, 290-294, 330-331` | — |
| 116 | Confirmation dialog auto-closes if the selection empties underneath it | state | `ContactsIndex.vue:432-436` | — |
| 117 | Assign / remove / delete success and failure toasts | error | `ContactsIndex.vue:345-349, 367-371, 389-394` | — |
| 118 | Bulk actions go through the generic `BulkActionsAPI` with `type: 'Contact'` | state | `ContactsIndex.vue:340-344, 362-366, 384-388` | — |

### 2.8 Pagination and load-more

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 119 | Sticky bottom pagination footer | navigation | `ContactsListLayout.vue:118-127`; `pagination/PaginationFooter.vue:72-129` | `showPagination` |
| 120 | "Showing x – y of N contacts" with compact-number formatting and pluralisation | status | `PaginationFooter.vue:47-58`; key `CONTACTS_LAYOUT.PAGINATION_FOOTER.SHOWING` | — |
| 121 | First / previous / next / last buttons with disabled end states | navigation | `PaginationFooter.vue:82-127` | — |
| 122 | Current-page pill + "of N pages" | status | `PaginationFooter.vue:100-109` | — |
| 123 | Page number mirrored into the URL (`router.replace`) | state | `ContactsIndex.vue:177-189` | — |
| 124 | Page size 15, matching `RESULTS_PER_PAGE` on the server | state | `ContactsListLayout.vue:16`; `app/controllers/api/v1/accounts/contacts_controller.rb:12` | — |
| 125 | Footer suppressed while fetching, when the list is empty, and in search mode | state | `ContactsIndex.vue:505`; `ContactsListLayout.vue:74-76` | — |
| 126 | Search mode replaces pagination with a "Load more" button (append paging) | navigation | `ContactsListLayout.vue:70-72, 111-115`; `ContactsLoadMore.vue:17-27`; `ContactsIndex.vue:274-288` | `isSearchView && hasMore` |
| 127 | Load-more spinner on the button; re-entry guarded | state | `ContactsLoadMore.vue:22`; `ContactsIndex.vue:42, 274-288` | — |

### 2.9 Create / import / export / audience dialogs

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 128 | Create-contact dialog, `3xl`, scrollable, hosting the full contact form | primary | `CreateNewContactDialog.vue:42-74` | — |
| 129 | Create dialog footer: "Cancel" (link) + "Save contact" (blue, disabled while invalid, loading) | primary | `CreateNewContactDialog.vue:54-73` | — |
| 130 | On success the form resets and the dialog closes | state | `CreateNewContactDialog.vue:30-33`; `ContactListHeaderWrapper.vue:101-107` | — |
| 131 | Create errors: duplicate email, duplicate phone, server message, generic | error | `ContactListHeaderWrapper.vue:108-121` | — |
| 132 | Import dialog with a "Download a sample csv." link to `/downloads/import-contacts-sample.csv` | secondary | `ContactImportDialog.vue:21, 68-83` | — |
| 133 | Import file picker: "Choose file" → truncated filename → "Change" / remove, `accept="text/csv"` | secondary | `ContactImportDialog.vue:23-47, 85-132` | — |
| 134 | Import confirm disabled + spinnered while importing | state | `ContactImportDialog.vue:64-66` | — |
| 135 | Import success ("notified via email") / failure toasts + `IMPORT_SUCCESS`/`IMPORT_FAILURE` analytics | error | `ContactListHeaderWrapper.vue:124-139` | — |
| 136 | Export dialog with title + description and an "Export" confirm | secondary | `ContactExportDialog.vue:52-65` | — |
| 137 | Export scope resolution: current audience query → else applied filters → else everything, always plus the active label | state | `ContactExportDialog.vue:29-42` | — |
| 138 | Export success ("notified on email") / error toasts | error | `ContactListHeaderWrapper.vue:141-153` | — |
| 139 | Create-audience dialog: required name with inline error | primary | `CreateSegmentDialog.vue:33-37, 85-97` | — |
| 140 | "Share with the whole account" checkbox plus explanatory hint | primary | `CreateSegmentDialog.vue:98-116` | `isAdmin` only |
| 141 | Same dialog reused as the **duplicate** dialog via `open({name, shared, title})` | contextual | `CreateSegmentDialog.vue:53-68`; `ContactListHeaderWrapper.vue:215-229` | — |
| 142 | Duplicate prefills "{name} copy" and only pre-ticks `shared` for an admin on a shared audience | state | `ContactListHeaderWrapper.vue:221-228` | — |
| 143 | Creating an audience navigates straight to it (`page=1`) | navigation | `ContactListHeaderWrapper.vue:166-173` | response has an id |
| 144 | Audience create success / error toasts | error | `ContactListHeaderWrapper.vue:162-178` | — |
| 145 | Delete-audience alert dialog ("Only its saved conditions are deleted; the contacts stay.") | destructive | `DeleteSegmentDialog.vue:28-42` | — |
| 146 | Deleting an audience returns to All Contacts | navigation | `ContactListHeaderWrapper.vue:187-192` | — |
| 147 | A refused shared-audience delete surfaces the server's own reason | error | `ContactListHeaderWrapper.vue:197-207` | `isSharedSegment && error.message` |
| 148 | Audience preset gallery (`RecipeDialog`): list of presets with name + description | secondary | `RecipeDialog.vue:121-155`; `ContactListHeaderWrapper.vue:425-432` | — |
| 149 | Unavailable presets shown with their missing requirements and no "Use" button | status | `RecipeDialog.vue:136-153` | `recipe.status !== AVAILABLE` |
| 150 | Preset input step with per-input validation (required / number range / URL) and "Back" | secondary | `RecipeDialog.vue:61-97, 167-187` | preset selected |
| 151 | "Start from scratch instead" → opens the ordinary condition builder | secondary | `RecipeDialog.vue:156-164`; `ContactListHeaderWrapper.vue:362-365` | — |
| 152 | Seven audience presets: high-value buyers, repeat buyers, recent buyers, active order, shipped order, store customers, linked commerce customers | secondary | `recipes/audiencePresets.js:35-130` | per-preset `requires` (Commerce flag, a store, a currency) |
| 153 | A preset feeds the normal create-audience dialog, prefilled with the preset's name | state | `ContactListHeaderWrapper.vue:235-242` | — |
| 154 | Commerce options for presets and conditions fetched once per account and shared | state | `audienceProvider.js:50-77, 237-248`; `ContactListHeaderWrapper.vue:76` | Commerce flag |

### 2.10 Empty, loading and error states (list)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 155 | Full empty state: 5 decorative demo contact cards behind a gradient, 3xl title, subtitle, "Add contact" | empty | `EmptyState/ContactEmptyState.vue:38-65`; `EmptyStateLayout.vue:24-67`; fixtures `contactEmptyStateContent.js` | no search, no filters, page 1 of `contacts_dashboard_index`, zero contacts (`ContactsIndex.vue:108-115`) |
| 156 | Empty-state CTA opens the create-contact dialog inline | empty | `ContactEmptyState.vue:33-35, 56-63` | — |
| 157 | One-line empty text for every other zero-result case | empty | `ContactsIndex.vue:116-123, 552-559` | — |
| 158 | Three distinct empty messages: search / this view / Active | empty | `ContactsIndex.vue:133-139`; `contact.json:605-607` | — |
| 159 | Centred spinner while the list (or the custom-views list) is fetching | loading | `ContactsIndex.vue:64-66, 524-529` | — |
| 160 | Spinner suppressed while appending a search page, so results do not disappear | loading | `ContactsIndex.vue:525` | `isSearchView && hasContacts` |
| 161 | Re-entrancy guard: a context refetch is skipped while one is already in flight | state | `ContactsIndex.vue:296, 459` | — |
| 162 | **No list error state.** `get` / `search` / `active` / `filter` swallow failures and only reset the flag | error | `store/modules/contacts/actions.js:71-73, 86-88, 101-103, 318-320` | — |

### 2.11 Contact detail shell (`ContactManageView.vue` + `ContactsDetailsLayout.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 163 | Breadcrumb "Contacts / {contact name}" | navigation | `ContactsDetailsLayout.vue:37-50, 86-89` | — |
| 164 | Breadcrumb click goes back: `router.back()` when there is history, else the list URL with `page=1` | navigation | `ContactManageView.vue:59-65` | — |
| 165 | "Block contact" / "Unblock contact" toggle with loading + disabled | destructive | `ContactsDetailsLayout.vue:91-102, 52-54, 60-62`; `ContactManageView.vue:95-120` | — |
| 166 | Block / unblock success and error toasts (four distinct strings) | error | `ContactManageView.vue:96-119` | — |
| 167 | "Call" button | primary | `Contacts/VoiceCallButton.vue:204-216`; mounted `ContactsDetailsLayout.vue:103-108` | a voice-capable inbox exists AND the contact has a phone (`VoiceCallButton.vue:49-69`) |
| 168 | Voice-inbox picker dialog when more than one voice inbox exists | contextual | `VoiceCallButton.vue:190-201, 218-243` | >1 voice inbox |
| 169 | Call disabled while any call is active, ringing or initiating | state | `VoiceCallButton.vue:71-83, 210` | — |
| 170 | WhatsApp call: permission-requested / permission-pending / initiated toasts and navigation to the conversation | error | `VoiceCallButton.vue:100-139` | WhatsApp voice provider |
| 171 | Twilio-style call: `contacts/initiateCall`, call registered in the calls store, navigate to the conversation | primary | `VoiceCallButton.vue:141-179` | non-WhatsApp voice inbox |
| 172 | "Send message" primary CTA with this contact preselected | primary | `ContactsDetailsLayout.vue:109-116` | — |
| 173 | Right sidebar docked as a column at `lg` and up | state | `ContactsDetailsLayout.vue:129-139` | `slots.sidebar` |
| 174 | Mobile sidebar as an off-canvas drawer with a rounded toggle pill (`panel-right-open` / `panel-right-close`) | mobile | `ContactsDetailsLayout.vue:142-197` | below `lg` |
| 175 | Drawer slide transition, direction-aware (LTR/RTL) | mobile | `ContactsDetailsLayout.vue:176-183` | — |
| 176 | Drawer closes on click-outside, ignoring its own content | mobile | `ContactsDetailsLayout.vue:68-71, 149-152` | drawer open |
| 177 | Content column nudged `2xl:ml-56` to centre against the nav rail | state | `ContactsDetailsLayout.vue:79` | ≥2xl |
| 178 | Detail spinner while fetching the contact or merging | loading | `ContactManageView.vue:34-36, 143-148` | — |
| 179 | On mount: fetch contact, contactable inboxes, notes, conversations and attribute definitions | loading | `ContactManageView.vue:67-93, 122-127` | — |

### 2.12 Contact detail body (`Pages/ContactDetails.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 180 | 72 px avatar with hover upload overlay and a hover "remove" badge | primary | `ContactDetails.vue:129-136`; `Avatar.vue:220-227, 274-301` | `allow-upload` |
| 181 | Avatar upload: optimistic local preview + multipart update, success / error toasts | primary | `ContactDetails.vue:32-34, 65-67, 91-105` | — |
| 182 | Avatar delete with success / error toasts | destructive | `ContactDetails.vue:107-123` | existing avatar |
| 183 | Contact name heading | state | `ContactDetails.vue:138-140` | — |
| 184 | Identifier line with a user-gear glyph | state | `ContactDetails.vue:142-148` | `identifier` |
| 185 | "Created {relative}" • "Last active {relative}", each with an exact-timestamp tooltip | state | `ContactDetails.vue:53-63, 149-177` | — |
| 186 | Contact labels: colour chips with hover-revealed remove, plus an "add label" picker with toggle semantics and selected-last sorting | primary | `ContactLabels/ContactLabels.vue:36-48, 57-91, 121-135` | — |
| 187 | Labels fetched on mount and whenever the contact changes | loading | `ContactLabels.vue:50-55, 93-105` | — |
| 188 | Full contact form in details density + "Update contact" with loading / invalid gating | primary | `ContactDetails.vue:183-195` | — |
| 189 | Update strips `customAttributes`, refetches contactable inboxes, toasts success / error | state | `ContactDetails.vue:73-85` | — |
| 190 | Danger zone: heading, "Permanently delete this contact…" description, ruby "Delete contact", confirm dialog, navigate back to the list | destructive | `ContactDetails.vue:197-220`; `ConfirmContactDeleteDialog.vue:36-40` | `administrator` only (`:197`) |

### 2.13 Contact detail sidebar (five tabs)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 191 | TabBar with Attributes / History / Notes / Media / Merge, animated active indicator, full-width in the sidebar | tab | `ContactManageView.vue:40-57, 154-163`; `tabbar/TabBar.vue:71-105` | — |
| 192 | Sidebar spinner while the contact loads | loading | `ContactManageView.vue:165-170` | `isFetchingItem` |
| 193 | **Attributes** — used attributes rendered as editable rows | primary | `ContactCustomAttributes.vue:110-119`; `ContactCustomAttributeItem.vue:76-94` | account has contact custom attributes |
| 194 | "N Unused attributes" divider | state | `ContactCustomAttributes.vue:120-128` | ≥1 unused |
| 195 | Attribute search box filtering the unused list | filter | `ContactCustomAttributes.vue:97-103, 130-139` | ≥1 unused |
| 196 | "No attributes found" when the search matches nothing | empty | `ContactCustomAttributes.vue:141-148` | — |
| 197 | Attribute order mirrors the conversation panel's saved order | state | `ContactCustomAttributes.vue:52-75` | `ui_settings.conversation_elements_order_conversation_contact_panel` |
| 198 | Per-type attribute editors: list, checkbox, date, other | primary | `ContactCustomAttributeItem.vue:62-73, 87-93` | attribute display type |
| 199 | Attribute update and delete with success / error toasts | primary | `ContactCustomAttributeItem.vue:28-60` | — |
| 200 | Attributes empty state pointing at settings | empty | `ContactCustomAttributes.vue:158-160` | no contact attributes in the account |
| 201 | **History** — previous conversations as `ConversationCard` rows with divider / hover treatment | navigation | `ContactHistory.vue:37-50` | — |
| 202 | History spinner and empty state | loading / empty | `ContactHistory.vue:30-36, 51-53` | — |
| 203 | **Notes** — rich-text editor, focused on mount, with a "Save note" action | primary | `ContactNotes.vue:59-79` | — |
| 204 | `Cmd`/`Ctrl` + `Enter` saves a note, including from inside the editor | shortcut | `ContactNotes.vue:48-54` | Notes tab mounted |
| 205 | Note rows: author avatar (bot fallback), "You"/name, "wrote {relative}" with an exact-timestamp tooltip, sanitized HTML body | state | `ContactNoteItem.vue:54-101`; `ContactNotes.vue:28-33` | — |
| 206 | Hover-revealed per-note delete | destructive | `ContactNoteItem.vue:84-92`; `ContactNotes.vue:42-46, 93-94` | `allowDelete` |
| 207 | Note collapse / expand for long notes (capability, unused in this panel) | secondary | `ContactNoteItem.vue:44-51, 102-117` | `collapsible` prop |
| 208 | Notes spinner and empty state | loading / empty | `ContactNotes.vue:80-99` | — |
| 209 | **Media** — media grid (peek 12) and files list (peek 6) | state | `ContactMedia.vue:16-17, 84-97` | attachments present |
| 210 | Gallery viewer with autoplay and all-media navigation | secondary | `ContactMedia.vue:38-50, 99-106` | a media item selected |
| 211 | Files open in a new tab (`noopener,noreferrer`) | secondary | `ContactMedia.vue:52-56` | `data_url` |
| 212 | "Jump to message" → that conversation at that message | contextual | `ContactMedia.vue:58-68, 88-96` | attachment has conversation + message id |
| 213 | Media spinner and empty state | loading / empty | `ContactMedia.vue:77-82` | — |
| 214 | **Merge** — title + explanation of precedence | state | `ContactMerge.vue:107-114` | — |
| 215 | Primary-contact search combobox: debounced API search, current contact excluded, "Searching…" / "No contacts found" states, `(ID: n) Name` option labels | primary | `ContactMerge.vue:46-74`; `ContactMergeForm.vue:51-70` | — |
| 216 | "To be saved" / "To be deleted" badges plus the arrow graphic between the two | state | `ContactMergeForm.vue:41-50, 72-91` | — |
| 217 | Card for the contact being merged away (avatar, name, email) | state | `ContactMergeForm.vue:93-110` | — |
| 218 | Required-selection validation message | error | `ContactMerge.vue:38-42, 120-125` | submitted empty |
| 219 | "Cancel" (resets; returns to Attributes when nothing was chosen) and "Merge contact" with loading | primary | `ContactMerge.vue:76-83, 128-143` | — |
| 220 | Merge success / error toasts, `MERGED_CONTACTS` analytics event, navigate back to the list | error | `ContactMerge.vue:85-102` | — |

### 2.14 Contextual links out of this surface

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 221 | Audience → Automations list with `?audience=<id>` | contextual | `ContactListHeaderWrapper.vue:249-253`; param `helper/audienceHelper.js` | shared audience + route reachable |
| 222 | Audience → WhatsApp campaigns with `?audience=<id>` | contextual | `ContactListHeaderWrapper.vue:255-259` | shared audience + route reachable |
| 223 | Audience → absolute shareable URL on the clipboard, with copy-failed fallback copy | contextual | `ContactListHeaderWrapper.vue:244-247, 261-269` | audience open |
| 224 | Contact → conversation (History card, Media jump-to-message) | contextual | `ContactHistory.vue:41-49`; `ContactMedia.vue:58-68` | — |
| 225 | Contact → Companies record through the company selector | contextual | `ContactsForm.vue:320-326` | `FEATURE_FLAGS.COMPANIES` |
| 226 | Contact → new conversation (list header "Message", detail "Send message") | contextual | `ContactHeader.vue:136-140`; `ContactsDetailsLayout.vue:109-116` | — |
| 227 | Contact → voice call, landing in the resulting conversation | contextual | `VoiceCallButton.vue:85-96, 174` | voice inbox + phone |

---

## 3. Visual audit

Severity is about user impact, not effort. Category names match the modernization findings taxonomy.

### V-01 — Almost every icon-only control on this surface has no accessible name (high · a11y)

`ContactMoreActions.vue:211` is the single control that sets `aria-label`. Everything else in the same
cluster ships an icon and nothing else: the filter toggle (`ContactHeader.vue:74-89`), "save as audience"
(`:92-104`), "delete audience" (`:105-117`), the sort trigger (`ContactSortMenu.vue:97-104`), the card
expand chevron (`ContactsCard.vue:196-203`), the import remove-file button
(`ContactImportDialog.vue:115-121`) and the note delete button (`ContactNoteItem.vue:84-92`). A screen
reader reads an unlabelled button; a new user reads nothing at all, because there is no tooltip either —
compare `ContactsBulkActionBar.vue:121-127`, which does set both a tooltip and an `aria-label`.

### V-02 — Row selection is reachable only with a mouse (high · a11y)

The checkbox exists only while the pointer is inside the avatar wrapper: `shouldShowSelection` is
`hoveredAvatarId === id || isSelected` (`ContactsList.vue:75-85`), and the overlay is rendered under
`v-if="selectable"` inside the avatar (`ContactsCard.vue:133-144`). The hover is bound to a plain `<div>`
with `@mouseenter`/`@mouseleave` (`ContactsCard.vue:121-125`), which is not focusable. There is therefore
**no keyboard path and no touch path** to multi-select — which gates the entire bulk-action feature set
(rows 105-118 of the manifest) behind a hover.

### V-03 — "Select all" only exists after you have already selected something (high · cta-clarity)

The bar that owns the select-all checkbox renders under `v-if="hasSelection"` (`ContactsIndex.vue:532`),
and `BulkSelectBar` itself renders its content under `v-if="hasSelected"` (`BulkSelectBar.vue:77`). The
cheapest way to act on a page of contacts is thus: hover one avatar, click its checkbox, then use
select-all. There is no select-all in the header or in a column head, because there is no column head.

### V-04 — The primary way into a contact is a 12 px text link buried in a metadata run (high · cta-clarity)

`ContactsCard.vue:186-191` renders "View details" as `variant="link" size="xs"` as the last item of the
pipe-separated metadata row that also holds email, phone and location (`:165-192`). The card itself is not
clickable: `CardLayout.vue:30` exposes `@click="handleClick"` and emits `click`, but `ContactsCard.vue:113-119`
never binds it, so clicking the row does nothing. The expand chevron (`:196-203`) opens an *edit form*, not
the contact — two different destinations, one of which looks like the obvious one.

### V-05 — One list, two paging models (high · consistency)

Browsing uses a numbered sticky footer (`ContactsListLayout.vue:118-127`); searching replaces it with a
"Load more" button (`:70-76, 111-115`) chosen by `useInfiniteScroll = isSearchView`
(`ContactsIndex.vue:512`). The footer is explicitly suppressed in search (`ContactsIndex.vue:505`). Typing
in the search box silently changes the navigation model of the page.

### V-06 — Search results have no count (medium · cta-clarity)

Because the footer is the only place that renders "Showing x – y of N contacts"
(`PaginationFooter.vue:47-58`) and it is hidden in search mode (`ContactsIndex.vue:505`), a search result
set has no visible size — the user cannot tell whether "Load more" will add 15 rows or 1,500.

### V-07 — A destructive action is styled as the least important control on the page (high · hierarchy)

"Delete this audience" is `icon="i-lucide-trash" color="slate" size="sm" variant="ghost"`, with no label
and no confirmation affordance in the button itself (`ContactHeader.vue:105-117`). It sits immediately
beside the save icon (`:92-104`) in the same slate-ghost treatment. Elsewhere in the very same surface
destructive actions are ruby (`ContactsBulkActionBar.vue:119-132`, `ContactDetails.vue:209-213`,
`ContactDeleteSection.vue:52-58`).

### V-08 — The same button means two different things depending on the route (high · consistency)

`ContactHeader.vue:76-78` swaps the filter icon for `i-lucide-pen-line` when `isSegmentsView`, so one
unlabelled button is "filter these contacts" on one route and "edit this audience's conditions" on
another. The panel it opens also changes title and primary action (`ContactsFilter.vue:132-136, 228-240`),
but the trigger communicates none of that.

### V-09 — Two Button prop dialects inside one surface (medium · consistency)

`ContactHeader.vue:79-83` and `ContactsCard.vue:197-200` use the explicit API
(`color` / `size` / `variant`); `ContactsBulkActionBar.vue:95-99`, `ContactDeleteSection.vue:32-38` and
`ContactsFilter.vue:221-240` use the boolean shorthand (`sm ghost slate`, `sm faded slate`,
`sm solid blue`). Same component, two spellings, in files that render next to each other.

### V-10 — The list column and its own pagination row are different widths (medium · alignment)

The header and the list body are `max-w-5xl` = 64 rem (`ContactHeader.vue:45`,
`ContactsListLayout.vue:102`), and the chips inherit the same (`ContactsActiveFiltersPreview.vue:87`). The
pagination footer is `max-w-[67rem]` (`ContactsListLayout.vue:123`). The footer is 3 rem wider than
everything it belongs to, so its left and right edges never line up with the cards above it.

### V-11 — A third measure in the detail view, plus a hard-coded centring nudge (medium · alignment)

The detail header and body are `max-w-[40.625rem]` (`ContactsDetailsLayout.vue:82, 122`) — an arbitrary
650 px — and the whole column is pushed with `ltr:2xl:ml-56 rtl:2xl:mr-56` (`:79`) to fake optical
centring against the nav rail. List (64 rem), footer (67 rem) and detail (40.625 rem) share no measure.

### V-12 — The list has no error state at all (high · loading-error)

Every list-producing action swallows its failure: `get` (`store/modules/contacts/actions.js:76-89`),
`search` (`:56-74`), `active` (`:91-104`) and `filter` (`:302-322`) each `catch` and only reset
`isFetching`, with no rethrow and no alert. `ContactsIndex.vue` has no error flag and the store's
`uiFlags` has none to offer (`store/modules/contacts/index.js:12-22`). A failed request therefore renders
the *empty* branch.

### V-13 — A failed request is indistinguishable from an empty view, and offers no retry (medium · loading-error)

The branch a failure lands in is `ContactsIndex.vue:552-559`: one centred grey sentence, "No contacts
available in this view 📋" (`contact.json:606`). No retry, no explanation, and an emoji where the recovery
action should be. The same is true of the detail view: `ContactManageView.vue:149-153` renders
`ContactDetails` only `v-else-if="selectedContact"`, so a failed `contacts/show` renders **nothing** —
no message, no spinner, no retry.

### V-14 — Loading is five copies of a bare centred spinner, with no skeletons (medium · loading-error)

`ContactsIndex.vue:524-529`, `ContactManageView.vue:143-148` and `:165-170`, `ContactHistory.vue:30-36`,
`ContactNotes.vue:80-85`, `ContactMedia.vue:77-79` all repeat
`flex items-center justify-center py-10 text-n-slate-11` + `<Spinner />`. Because the spinner *replaces*
the list rather than overlaying it, the page height collapses to ~40 px and then jumps back on every
page change, sort change and filter apply.

### V-15 — The good empty state is only available on one of the four list routes (medium · empty-state)

`showEmptyStateLayout` requires no search, no applied filters, zero contacts **and**
`route.name === 'contacts_dashboard_index' && page === 1` (`ContactsIndex.vue:100-115`). An empty
audience, an empty label view, page 2 of anything and the Active view all fall through to the one-line
text at `:552-559`, with no action — not even "clear filters", which exists only in the chip strip
(`ActiveFilterPreview.vue:110-117`) and is itself suppressed for audiences
(`ContactsActiveFiltersPreview.vue:86`).

### V-16 — The empty state's demo cards call a function that does not exist (high · empty-state)

`ContactEmptyState.vue:52` binds `@toggle="toggleExpanded(contact.id)"`, but no `toggleExpanded` is
defined anywhere in that component's `<script setup>` (`:1-36`). The adjacent
`:is-expanded="0 === contact.id"` (`:51`) can never be true — the fixture ids are 15-22
(`contactEmptyStateContent.js:20, 53, 84, 113, 141, 168, 195, 219`). So the one piece of interactivity the
empty state pretends to demonstrate is dead code that would throw if the wrapper's
`pointer-events-none` (`EmptyStateLayout.vue:33`) were ever removed.

### V-17 — The empty state mounts five full contact cards, each with a complete form (medium · empty-state)

`ContactEmptyState.vue:42-53` renders real `ContactsCard` instances, which each instantiate `ContactsForm`
(8 fields + 8 social inputs + country combobox) and `ContactDeleteSection`
(`ContactsCard.vue:216-238`) purely as wallpaper behind a 50 %-opacity gradient.

### V-18 — There is no table, so sorting is detached from anything visible (high · table)

Sort offers Name, Email, Company, Country, City, Last activity and Created at
(`ContactSortMenu.vue:25-54`). The card shows name and email unconditionally, company / phone / location
only when present (`ContactsCard.vue:148-184`), and **never** shows last activity or created-at — the
default sort key included (`ContactsIndex.vue:19-20`). Sorting by "Created at" reorders rows by a value
the row does not display, and there are no column headers to click instead.

### V-19 — The active sort is invisible until you open the menu (medium · table)

`ContactSortMenu.vue:97-104` is an icon-only trigger with no label, no badge and no tooltip; the current
sort and direction are only legible once the panel is open (`:110-131`). After a reload the list is
ordered by a persisted preference (`ContactsIndex.vue:438-448`) that nothing on screen states.

### V-20 — Roughly 90 px of vertical space per contact, 15 contacts per page (medium · density)

`CardLayout.vue:25` gives each row `py-5`, `ContactsList.vue:89` adds `gap-4` between rows, and the avatar
is 42 px (`ContactsCard.vue:129`). Page size is 15 (`ContactsListLayout.vue:16`;
`app/controllers/api/v1/accounts/contacts_controller.rb:12`). Browsing a CRM of any size means ~1,350 px
of scroll for 15 people, and no density option anywhere.

### V-21 — Data and navigation are mixed in one run of identical separators (medium · hierarchy)

`ContactsCard.vue:165-192` puts email, a pipe, phone, a pipe, location, a pipe and then the **action**
"View details" in a single `flex-wrap` row with the same `w-px h-3 bg-n-slate-6` divider between each.
Nothing distinguishes the one clickable item from the three read-only ones.

### V-22 — Separators are rendered per-value, so dangling pipes appear (low · spacing)

Each divider is conditioned on the value *before* it — `v-if="email"` (`ContactsCard.vue:173`),
`v-if="phoneNumber"` (`:177`), `v-if="countryDetails"` (`:185`) — not on whether anything follows. A
contact with an email but no phone and no resolvable country renders `email | View details`, and a contact
with only a name renders a bare "View details" with no leading separator: the row's rhythm changes per
contact.

### V-23 — The selection checkbox has no accessible name and a swallowed click (high · a11y)

`ContactsCard.vue:135-143` wraps the checkbox in a `<label>` carrying `@click.stop` and no text, and
`checkbox/Checkbox.vue:28-35` renders a bare `<input type="checkbox">` with no `aria-label` support at
all. The accessible name of "select this contact" is the empty string, and the `click.stop` on the label
means the label never forwards activation the way a label normally would.

### V-24 — The list search field has no label (medium · a11y)

`ContactHeader.vue:52-60` passes `placeholder` but not `label`, and `input/Input.vue:108-114` only renders
a `<label>` when `label` is set. The field's only name is placeholder text that disappears on input. The
sidebar's attribute search has the same problem in raw markup (`ContactCustomAttributes.vue:132-139`).

### V-25 — Invalid form fields turn red without saying why (medium · form)

`ContactsForm.vue:327-346` passes `:message-type="getMessageType(item.key)"` but never passes `:message`.
`Input.vue` only renders help text when `message` is non-empty (`:146-152`). So an empty required first
name or a malformed email produces a red outline and a disabled "Update contact" button
(`ContactsCard.vue:228`, `ContactDetails.vue:193`) with no error text and no indication of which of the
eight fields is at fault.

### V-26 — The social-handle block bypasses the design system entirely (medium · form)

`ContactsForm.vue:354-377` renders eight raw `<input>` elements in hand-built pill wrappers, sized with
`:size="item.placeholder.length"` and `min-w-[100px]`, with no labels, no validation, no error surface and
no `Input` component — inside a form whose other eight fields all use `Input` / `ComboBox` /
`PhoneNumberInput`.

### V-27 — The detail sidebar divider is a physical border (high · rtl)

`ContactsDetailsLayout.vue:131` uses `border-l` on the desktop sidebar. In Arabic the sidebar sits on the
left and its divider renders on its left edge — against the viewport, not against the content. The mobile
twin 56 lines below gets this right (`:187`, `ltr:border-l rtl:border-r`), which makes the desktop case a
clear oversight rather than a deliberate choice.

### V-28 — The sidebar attribute search is physically padded (high · rtl)

`ContactCustomAttributes.vue:131` positions the magnifier at `left-3` and `:138` pads the input
`pl-10 pr-2`. In RTL the icon lands on the left while the text starts from the right, and the text runs
under the icon.

### V-29 — Physical auto-margin in the bulk bar (medium · rtl)

`ContactsBulkActionBar.vue:104` uses `ml-auto` to push the action group to the end of the bar. In RTL the
group is pushed the wrong way. The surrounding file does use logical utilities elsewhere (`:91`,
`ltr:!pr-3 rtl:!pl-3`), so this is an inconsistency inside one component.

### V-30 — A fixed 140 px attribute label column in raw pixels (medium · rtl / tokens)

`ContactCustomAttributeItem.vue:78` sets `grid-cols-[140px,1fr]` on a row that lives in a sidebar whose
minimum width is `min-w-52` (13 rem, `ContactsDetailsLayout.vue:131`). The label column cannot shrink, it
is specified in px rather than rem (against the stated convention), and long translated attribute names —
German, Arabic — truncate at 140 px regardless of available space.

### V-31 — The sort panel is positioned off-screen on phones (medium · mobile)

`ContactSortMenu.vue:108` positions the 18 rem panel at `ltr:-right-32 rtl:-left-32` and only resets to
`right-0` at `sm`. Below 640 px the panel is deliberately pushed 8 rem past the trigger, i.e. mostly
outside the viewport, with no collision handling.

### V-32 — A 4 rem invisible strip covers the detail page on mobile (high · mobile)

`ContactsDetailsLayout.vue:142-146` renders, below `lg`, a `fixed top-0 … h-full z-50` container whose
width is `w-16` when the drawer is closed. It has no `pointer-events-none`, so a full-height 64 px column
pinned to the trailing edge of the viewport sits above the page at z-50 and intercepts every tap in it —
including the trailing edge of card rows and form fields underneath.

### V-33 — Five equal-width tabs in a 13 rem sidebar (medium · mobile)

`ContactManageView.vue:156-160` forces `class="w-full [&>button]:w-full"` onto a `TabBar` with five tabs,
whose buttons are `px-4 truncate` (`TabBar.vue:85`). In the narrowest allowed sidebar
(`min-w-52` = 208 px) each tab gets ~41 px minus 32 px of padding, so "Attributes" and "History"
truncate to a character or two — and the active-tab indicator is measured from those collapsed widths
(`TabBar.vue:33-44`).

### V-34 — The list header stacks into a six-control row on phones (medium · mobile)

`ContactHeader.vue:45-51` switches the right-hand group to `flex-col` below `sm`, so search sits above a
row containing filter, save, delete, sort, overflow, a divider and the "Message" CTA (`:70-141`) — seven
hit targets inside a `flex-shrink-0` container, next to a title that truncates to make room for them.

### V-35 — Filter chips print hardcoded English operators (medium · i18n / consistency)

`ActiveFilterPreview.vue:21-34` maps operators to literal English strings ("is", "is not", "does not
contain", "days before") with `replaceUnderscoreWithSpace` as the fallback — while
`CONTACTS_FILTER.OPERATOR_LABELS` already exists with translated equivalents
(`i18n/locale/en/contactFilters.json`). In Arabic the chips read right-to-left around English operators.

### V-36 — Chip values are lower-cased and then re-capitalised, mangling real data (medium · consistency)

`ActiveFilterPreview.vue:79-87` applies `class="lowercase …"` plus `first-letter:capitalize` to the value.
"ACME Inc" renders "Acme inc", "GB" renders "Gb", "iPhone" renders "Iphone". The attribute name gets the
same treatment when it has no resolved `attributeName` (`:62-72`).

### V-37 — Two "save this filter" dialogs and two near-identical filter panels coexist (medium · consistency)

Contacts save an audience through `ContactsForm/CreateSegmentDialog.vue`; conversations save a folder
through `components-next/filter/SaveCustomView.vue` (used at `components/ChatList.vue:906`). And
`filter/ContactsFilter.vue` vs `filter/ConversationFilter.vue` are structurally the same file — same
wrapper classes, same `ConditionRow` loop, same button row (compare `ContactsFilter.vue:145-242` with
`ConversationFilter.vue:105-173`) — diverging only in strings and in the contacts-only notes.

### V-38 — Two sources of truth for contact filter attributes, and one unreachable field (medium · consistency)

The live picker is built in `filter/contactProvider.js:79-207`. A second, older list survives at
`routes/dashboard/contacts/contactFilterItems/index.js` and is still imported — and used — to rehydrate a
saved audience's values (`ContactListHeaderWrapper.vue:10, 298-305`). The legacy list still carries
`referer` (`contactFilterItems/index.js:81-87`) and so does the i18n catalogue
(`contact.json:415`, `CONTACTS_LAYOUT.FILTER.REFERER_LINK`), but the live picker has no such attribute.
An audience saved on "Referer link" opens in the builder with no matching `FilterType`, which leaves
`currentFilter` undefined and the operator select empty (`ConditionRow.vue:50-52, 208-213`).

### V-39 — Pluralisation copy bug in the attributes divider (low · consistency)

`contact.json:545`: `"{count} Used attribute | {count} Unused attributes"`. The singular branch says
"Used", the plural says "Unused", and the string is consumed for the **unused** count
(`ContactCustomAttributes.vue:122-126`). One unused attribute reads "1 Used attribute".

### V-40 — The detail view passes three props the layout does not declare (medium · consistency)

`ContactManageView.vue:135-139` passes `:button-label`, `is-detail-view` and `:show-pagination-footer`.
`ContactsDetailsLayout.vue:12-21` declares only `selectedContact` and `isUpdating`. All three fall through
to the root `<section>` as stray DOM attributes (`ContactsDetailsLayout.vue:75`), and
`button-label` is dead — the layout hardcodes `CONTACTS_LAYOUT.HEADER.SEND_MESSAGE` at `:112`.

### V-41 — Stale `id="inbox"` on the merge combobox (low · a11y)

`ContactMergeForm.vue:52` gives the primary-contact combobox `id="inbox"`, a leftover from another form.
The adjacent `<label>` (`:42-44`) has no `for`, so the label is not associated with any control and the id
actively misdescribes it.

### V-42 — The pagination footer can claim a total it does not have (medium · loading-error)

`ContactsListLayout.vue:15` defaults `totalItems` to `100`. `ContactsIndex.vue:68` passes
`meta.value?.count`, which is `undefined` before the first response resolves — and passing `undefined`
activates the default. On first paint the footer can read "Showing 1 – 15 of 100 contacts" for an account
with three contacts.

### V-43 — Merge "Cancel" does two different things (medium · cta-clarity)

`ContactMerge.vue:76-83`: if no contact has been chosen, Cancel navigates away from the Merge tab back to
Attributes; if one has been chosen, the same button only clears the field and stays. The label is
identical in both cases.

### V-44 — Three near-equal buttons in the detail header, one of them semi-destructive (medium · hierarchy)

`ContactsDetailsLayout.vue:91-116` renders "Block contact" (`slate`, solid), "Call" and "Send message"
(default blue) at the same `size="sm"`. Blocking a contact is grouped with, and weighted like, the two
ways of contacting them, and it has no confirmation step (`ContactManageView.vue:95-120` fires
immediately).

### V-45 — The breadcrumb's first crumb is an anchor to `#` with the handler on the root (medium · a11y)

`ContactsDetailsLayout.vue:40-42` builds the first crumb with `link: '#'`, and `:86-89` binds `@click` on
the `Breadcrumb` component root rather than on the crumb. Keyboard activation of a real `href="#"` will
also change the URL fragment.

### V-46 — A keyboard shortcut nobody is told about, live for the whole tab's lifetime (low · a11y)

`ContactNotes.vue:48-54` registers `$mod+Enter` with `allowOnFocusedInput: true` for as long as the Notes
tab is mounted, and nothing in the UI mentions it — the "Save note" button carries no hint
(`:67-76`). The handler also fires when focus is outside the editor.

### V-47 — Note delete is hover-only (medium · a11y)

`ContactNoteItem.vue:90`: `opacity-0 group-hover/note:opacity-100`. The button stays in the tab order
while invisible, and on touch it is unreachable until something triggers the hover state. (The hover-only
pattern repeats at `ContactLabels` / `LabelItem` via `:is-hovered`, `ContactLabels.vue:123-130`.)

### V-48 — Blocked contacts are filterable and togglable but carry no badge in the list (medium · consistency)

`blocked` is a first-class filter (`contactProvider.js:171-190`) and a first-class detail action
(`ContactsDetailsLayout.vue:52-54, 91-102`), but `ContactsCard.vue:14-27` has no `blocked` prop and the
card renders no indicator. Filtering for blocked contacts produces a list that looks exactly like any
other.

### V-49 — The filter popover has no height limit (low · spacing)

`ContactsFilter.vue:148` sets `overflow-visible` with no `max-height`. Conditions are appended without
bound (`:68-70`), each row wraps onto multiple lines on narrow viewports
(`ConditionRow.vue:186`), and the popover is absolutely positioned under the header
(`ContactListHeaderWrapper.vue:400-403`) — so a six-condition audience runs past the bottom of the
viewport with its Apply button out of reach.

### V-50 — The filter popover has no close affordance (low · cta-clarity)

`ContactsFilter.vue:145-152` has a title and no close button. The only exits are click-outside
(`:139-142`) and Apply. The same is true of its conversation twin, so this is a system-level pattern gap,
not a contacts-only one.

### V-51 — The sticky bulk bar slides over the active-filter chips (medium · spacing)

`ContactsBulkActionBar.vue:83-85` is `sticky top-0 z-10` inside the scrolling `<main>`, while
`ContactsActiveFiltersPreview` is rendered *above* the default slot in the same scroll column
(`ContactsListLayout.vue:103-110`). With a selection active and the list scrolled, the bulk bar pins over
the chip strip, and the bar's gradient mask (`from-n-surface-1 from-90%`) only partly hides what is
underneath.

### V-52 — "No dot" silently means offline, with nothing to read it against (low · consistency)

`ContactsCard.vue:130-131` passes `hide-offline-status`, and `Avatar.vue:78-82` then drops the offline
class entirely. The list therefore encodes three states (online teal, busy amber, offline nothing) with
no legend and no text alternative — and `availabilityStatus` is not filterable or sortable, so the dot
cannot be acted on either.

---

## 4. What this surface already does well, and must not be lost

1. **The audience model is coherent and genuinely dynamic.** A filter, a saved audience and a preset all
   produce the same `{ payload: [conditions] }` and go through the same create call
   (`recipes/audiencePresets.js:1-33`, `ContactListHeaderWrapper.vue:155-179`). Duplicating an audience
   reuses the create dialog rather than inventing a second one (`CreateSegmentDialog.vue:53-68`). Nothing
   is copied or frozen, so an audience stays correct over time. Preserve this single path.

2. **Cross-module shortcuts ask the destination for permission before offering themselves.**
   `ContactMoreActions.vue:43-53` resolves the target route and checks its own `featureFlag`,
   `permissions` and `installationTypes` before rendering "Use in a new automation rule" / "campaign" —
   so a shortcut never offers a page the page itself would refuse. This is the right pattern and should
   be the model for any new cross-links.

3. **Dependency and consequence are surfaced where the action is.** "Used by 2 automation rules · 1
   campaign" appears in the menu that can delete or duplicate the audience
   (`ContactMoreActions.vue:57-97`), and the three shared-audience notes explain read-only, editable and
   "saving changes what they match at once" inside the editor (`ContactsFilter.vue:118-130`). Likewise the
   Commerce notes state plainly that figures are *visible* orders, not lifetime totals
   (`contactFilters.json`, `CONTACTS_FILTER.AUDIENCE.COMMERCE_NOTE`), and the amber unread warning says
   exactly which contacts cannot match and why.

4. **The grouped, icon-led attribute picker scales to ~40 conditions without a search box.** Standard /
   Additional / Custom Attributes / Conversations / Commerce sections with per-attribute icons
   (`helper/filterAttributeIcons.js:84-128`) keep a very long list legible, and unknown models are
   appended rather than silently dropped (`:122-127`).

5. **Context is preserved in the URL and in navigation.** Page and search live in the query
   (`ContactsIndex.vue:177-189`), opening a contact from inside an audience or a label keeps that context
   in the route (`ContactsList.vue:55-67`), and the detail breadcrumb prefers real history over a
   hardcoded path (`ContactManageView.vue:59-65`).

6. **Selection survives paging but not context changes.** `fetchContactsBasedOnContext` clears the
   selection by default and `onPageChange` opts out (`ContactsIndex.vue:290-294, 330-331`), so a user can
   build a selection across pages without being able to accidentally act on contacts from a view they
   have left.

7. **Audience-name and condition editing are one panel, not two.** Renaming an audience and changing its
   conditions happen together with a single "Update audience" (`ContactsFilter.vue:153-161, 228-237`),
   and the saved conditions — including Commerce and conversation option objects — are faithfully
   rehydrated into editable rows (`ContactListHeaderWrapper.vue:298-338`).

8. **Per-row filter validation is precise and non-blocking.** Errors are per condition, shown inline with
   a wiggle, and cleared the moment the row is edited (`ConditionRow.vue:97-106, 167-180, 277-279`); the
   panel validates every row before applying (`ContactsFilter.vue:74-82`).

9. **Async condition search is correctly ordered.** Stale responses are dropped by comparing against the
   last query, and a `null` result resets rather than leaving the row stuck "searching"
   (`ConditionRow.vue:114-140`).

10. **Destructive actions are consistently confirmed and consistently permission-gated.** Contact delete
    (card and detail), bulk delete and audience delete all route through a `type="alert"` dialog
    (`ConfirmContactDeleteDialog.vue:46-53`, `ContactsIndex.vue:567-576`, `DeleteSegmentDialog.vue:29-42`),
    and contact deletion is `administrator`-only in both places (`ContactDeleteSection.vue:28`,
    `ContactDetails.vue:197`, `ContactsBulkActionBar.vue:119`).

11. **Bulk delete copy is singular/plural correct and states the consequence.** Four strings, chosen by
    count, each saying what will happen and that it cannot be undone
    (`ContactsIndex.vue:76-92`, `contact.json:626-632`).

12. **Error handling on contact writes is specific.** Duplicate email and duplicate phone get their own
    messages, server-supplied messages are passed through, and only the unknown case falls back to a
    generic string — in three separate call sites (`ContactsList.vue:39-52`,
    `ContactListHeaderWrapper.vue:108-121`, `ContactDetails.vue:116-122`).

13. **Voice calling is honest about what happened.** Permission-requested, permission-already-pending,
    locked and initiated are four distinct outcomes with four distinct messages, and the button refuses to
    start a second call while one is live (`VoiceCallButton.vue:71-83, 100-139`).

14. **The detail sidebar is genuinely useful on mobile.** The off-canvas drawer with a direction-aware
    slide, a persistent toggle pill and click-outside-to-close (`ContactsDetailsLayout.vue:142-197`) is a
    real mobile pattern, not a hidden desktop panel — V-32 is a bug inside a good design, not a reason to
    drop it.

15. **Attribute ordering is shared with the conversation panel.** The contact detail attributes honour the
    same `ui_settings` order the agent arranged in the conversation sidebar
    (`ContactCustomAttributes.vue:52-75`), so one preference governs both surfaces.

16. **Sort is a persisted user preference, not a session accident**
    (`ContactsIndex.vue:400-406, 438-448`), and the default is deliberately the one order backed by an
    index, with a comment saying so (`:19-20`).

17. **Media and history are real cross-links, not dead ends.** "Jump to message" lands in the
    conversation at that message (`ContactMedia.vue:58-68`) and history rows are the same
    `ConversationCard` used in the inbox (`ContactHistory.vue:41-49`), so the contact record is a route
    into the work rather than a terminus.
