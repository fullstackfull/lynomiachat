# Audit — Filters, Search and List Controls

**Scope:** `app/javascript/dashboard/components-next/filter/**` (the "next" condition builder), its two
providers and the Lynomia audience provider, the legacy filter-type registries
(`app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/`,
`app/javascript/dashboard/routes/dashboard/contacts/contactFilterItems/`,
`app/javascript/dashboard/components/widgets/FilterInput/FilterOperatorTypes.js`,
`app/javascript/shared/composables/useFilter.js`), every list surface that opens a filter
(Contacts, Conversations, Calls, Reports/CSAT/SLA, Audit logs, Inbox notifications, Search, Help Center,
Companies, Campaigns), the sort menus, and the saved-view (folder / segment / audience) UI.

**Status:** read-only baseline. This records *what exists today*, literally. It is the reference the
feature-preservation contract is checked against. **No redesign is proposed.**

All paths are relative to the repository root. All line numbers are from the files as read for this audit.
Breakpoints in this codebase (`tailwind.config.js:197–205`): `xs 480px`, `sm 640px`, `md 768px`,
`lg 1024px`, `xl 1280px`, `2xl 1536px`, `3xl 1900px`. **At 390px no responsive variant is active** —
every `xs:`/`sm:`/`lg:` class below is in its *unprefixed* state.

---

## 1. File inventory

### 1.1 The "next" condition builder — `components-next/filter/`

| File | Lines | Role |
| --- | --- | --- |
| `app/javascript/dashboard/components-next/filter/ContactsFilter.vue` | 244 | Contacts / audience condition panel. Segment-edit mode, shared-audience notes, Lynomia audience notes, Apply / Clear / Add / Update-segment footer |
| `app/javascript/dashboard/components-next/filter/ConversationFilter.vue` | 173 | Conversations / folder condition panel. Folder-edit mode, Apply / Clear / Add / Update-folder footer |
| `app/javascript/dashboard/components-next/filter/ConditionRow.vue` | 281 | One condition line: query operator + attribute + operator + value input + trash. Owns per-row validation, async option search and the value-reset-on-attribute-change rule |
| `app/javascript/dashboard/components-next/filter/ActiveFilterPreview.vue` | 119 | Applied-filter chip row with "+N more" and a Clear button. **Only consumer is Contacts** |
| `app/javascript/dashboard/components-next/filter/SaveCustomView.vue` | 125 | "Save this filter" panel for **conversation folders only**. Options API + `@vuelidate` |
| `app/javascript/dashboard/components-next/filter/provider.js` | 308 | `useConversationFilterContext()` — 13 standard conversation attributes + custom attributes, grouped |
| `app/javascript/dashboard/components-next/filter/contactProvider.js` | 215 | `useContactFilterContext()` — 11 standard contact attributes + custom attributes + audience fields, grouped |
| `app/javascript/dashboard/components-next/filter/audienceProvider.js` | 272 | Lynomia audience: 6 conversation fields + up to 9+N Commerce fields, `loadAudienceFields()`, `audienceValuesForEdit()` |
| `app/javascript/dashboard/components-next/filter/operators.js` | 164 | `useOperators()` — 10 operators, 6 named operator sets, `getOperatorTypes(displayType)` |
| `app/javascript/dashboard/components-next/filter/helper/filterHelper.js` | 103 | `DROPDOWN_SEARCH_THRESHOLD`, `CONVERSATION_ATTRIBUTES`, `CONTACT_ATTRIBUTES`, `getCustomAttributeInputType`, `buildAttributesFilterTypes`, `replaceUnderscoreWithSpace` |
| `app/javascript/dashboard/components-next/filter/helper/filterAttributeIcons.js` | 128 | 38-key icon table + 8 custom-type icons + `groupFilterTypes()` (5 ordered groups) |
| `app/javascript/dashboard/components-next/filter/inputs/FilterSelect.vue` | 155 | Attribute / operator / query-operator picker (single value, string model, section headers) |
| `app/javascript/dashboard/components-next/filter/inputs/MultiSelect.vue` | 218 | Multi-value picker. Chip-strip trigger, `maxChips` 3, tooltip for the overflow |
| `app/javascript/dashboard/components-next/filter/inputs/SingleSelect.vue` | 214 | Single-value picker, sync or async (`@search`) |
| `app/javascript/dashboard/components-next/filter/inputs/MultiTextInput.vue` | 77 | Free-text token input (Enter to add, `x` to remove) |
| `app/javascript/dashboard/components-next/filter/helper/filterHelper.spec.js` | 228 | Unit spec |
| `app/javascript/dashboard/components-next/filter/specs/audienceProvider.spec.js` | 171 | Unit spec |
| `app/javascript/dashboard/components-next/filter/fixtures/filterTypes.js` | 603 | Histoire fixtures (`filterTypes`, `sampleActiveFilters`) |
| `…/ActiveFilterPreview.story.vue` / `ConditionRow.story.vue` / `inputs/FilterSelect.story.vue` / `inputs/MultiSelect.story.vue` / `inputs/SingleSelect.story.vue` | 66 / 68 / 66 / 49 / 33 | Histoire stories under `Components/Filters/*` |

### 1.2 Consumers and sibling list controls

| File | Lines | Role |
| --- | --- | --- |
| `app/javascript/dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue` | 145 | Contacts page header: title, search, filter button + dot, save-segment, delete-segment, sort, overflow, Compose |
| `app/javascript/dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue` | 434 | All Contacts filter/segment/audience logic; mounts `ContactsFilter` in the header's `#filter` slot |
| `app/javascript/dashboard/components-next/Contacts/ContactsHeader/components/ContactsActiveFiltersPreview.vue` | 91 | Adapter that feeds `ActiveFilterPreview` from the store or the active segment |
| `app/javascript/dashboard/components-next/Contacts/ContactsHeader/components/ContactSortMenu.vue` | 134 | Contacts sort: 7 sort keys × 2 orders, two `SelectMenu`s in a `w-72` panel |
| `app/javascript/dashboard/components-next/Contacts/ContactsHeader/components/ContactMoreActions.vue` | 223 | Overflow menu: audience section (usage, use-in-automation, use-in-campaign, duplicate, copy link, from-preset) + contact section (add / export / import) |
| `app/javascript/dashboard/components-next/Contacts/ContactsListLayout.vue` | 130 | Decides whether the chip row renders; wires `openFilter` back into the header |
| `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue` | ~560 | Search ↔ filter ↔ segment ↔ label ↔ active-view fetch orchestration |
| `app/javascript/dashboard/components/ChatListHeader.vue` | 184 | Conversations list header: filter button, save-folder, edit-folder, delete-folder, basic filter, layout switch |
| `app/javascript/dashboard/components/ChatList.vue` | 990 | Conversations filter state, folder init, teleport targets for `ConversationFilter` and `SaveCustomView` |
| `app/javascript/dashboard/components/widgets/conversation/ConversationBasicFilter.vue` | 196 | Conversations status + order-by panel (10 sort orders), persisted in `ui_settings` |
| `app/javascript/dashboard/components-next/Calls/CallsFilterBar.vue` | 270 | Calls: inline chip bar — a 4th, unrelated filter idiom |
| `app/javascript/dashboard/routes/dashboard/settings/reports/components/Filters/v3/ActiveFilterChip.vue` | 78 | Reports chip (legacy `components/ui/Dropdown/*` primitives) |
| `app/javascript/dashboard/routes/dashboard/settings/reports/components/Filters/v3/AddFilterChip.vue` | 103 | Reports "Add filter" with a hover sub-menu |
| `app/javascript/dashboard/routes/dashboard/settings/auditlogs/components/AuditLogFilters.vue` | 214 | Audit logs: label-bearing dropdown buttons + conditional date picker |
| `app/javascript/dashboard/routes/dashboard/inbox/components/InboxDisplayMenu.vue` | 197 | Notification inbox "Display" menu: raw checkboxes + nested sort dropdown |
| `app/javascript/dashboard/modules/search/components/SearchFilters.vue` | 104 | Dedicated search page filter bar (date range / From / In) |
| `app/javascript/dashboard/components-next/Companies/CompaniesHeader/CompanyHeader.vue` | 57 | Companies header: search + sort + overflow. **No filter** |
| `app/javascript/dashboard/components-next/Campaigns/CampaignLayout.vue` | 57 | Campaigns shell: title + one button. **No search, no sort, no filter** |
| `app/javascript/dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue` | 131 | Settings-list header. Search only, and `hidden sm:flex` |

### 1.3 The legacy registry that still runs

| File | Lines | Still used by |
| --- | --- | --- |
| `app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/index.js` | 186 | `ChatList.vue:37` (`advancedFilterTypes`, used only for `setParamsForEditFolderModal`), and `useFilter.js:4` (`filterAttributeGroups`) |
| `app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/languages.js` | 751 | `provider.js:13` — the *current* browser-language option list |
| `app/javascript/dashboard/routes/dashboard/contacts/contactFilterItems/index.js` | 159 | `ContactListHeaderWrapper.vue:10,301` and `useFilter.js:5` |
| `app/javascript/dashboard/components/widgets/FilterInput/FilterOperatorTypes.js` | 90 | `advancedFilterItems/index.js`, `contactFilterItems/index.js`, `useFilter.js:6`. `OPERATOR_TYPES_1..5`, **English labels hardcoded** |
| `app/javascript/shared/composables/useFilter.js` | 181 | `ChatList.vue:24,127` — `initializeStatusAndAssigneeFilterToModal`, `initializeInboxTeamAndLabelFilterToModal`, `setFilterAttributes` |

---

## 2. Per-surface list-control matrix

| Surface | Search | Sort | Filter entry | Active-filter count | Chips | Clear-all | Saved views |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Contacts** (`contacts_dashboard_index`) | `type="search"` in header, `ContactHeader.vue:52–68` | `ContactSortMenu`, 7 keys × 2 orders | Ghost icon button `i-lucide-list-filter`, `ContactHeader.vue:74–89` → inline absolute panel | **No count.** A `w-2 h-2` brand dot, `ContactHeader.vue:85–88` | **Yes** — `ActiveFilterPreview`, max 2 + "+N more filters" | Ghost "Clear filters" text button at the end of the chip row, `ActiveFilterPreview.vue:110–117` | Segments; sidebar `Sidebar.vue:547–568`; save via `i-lucide-save` button, `ContactHeader.vue:92–104` |
| **Contacts — segment view** (`contacts_dashboard_segments_index`) | hidden (`ContactsListLayout.vue:86`) | same | Same button, **icon swaps to `i-lucide-pen-line`**, dot suppressed, `ContactHeader.vue:76–78, 86` | none | Yes, but `show-clear-button` false, `ContactsActiveFiltersPreview.vue:86` | **none** | Delete via `i-lucide-trash`, `ContactHeader.vue:105–117`; duplicate / use-in-automation / use-in-campaign / copy-link / from-preset in `ContactMoreActions` |
| **Contacts — label view** / **active view** | label: hidden; active: hidden | same | **Filter button hidden entirely** (`ContactHeader.vue:73`, `v-if="!isLabelView && !isActiveView"`) | n/a | hidden (`ContactsListLayout.vue:53–60`) | n/a | n/a |
| **Conversations** (`home`, inbox/team/label scopes) | **none in this header** (global search is a separate route) | `ConversationBasicFilter` (status + 10 order-by), `ChatListHeader.vue:172–177` | `xs faded` icon button `i-lucide-list-filter`, `ChatListHeader.vue:156–165` → teleported panel | **No count, no dot, nothing** | **No chips at all** | Back-chevron `i-lucide-chevron-left` whose tooltip *is* "Clear filters", `ChatListHeader.vue:81–91` | Folders; sidebar `Sidebar.vue:441–457`; save via `i-lucide-save` → `SaveCustomView`, `ChatListHeader.vue:112–128` |
| **Conversations — folder view** (`folder_conversations`) | none | same | Button icon becomes `i-lucide-pen-line` ("Edit Folder"), `ChatListHeader.vue:129–145` | A result count pill, `ChatListHeader.vue:95–103` | none | **none** | Delete via `i-lucide-trash-2` → `DeleteCustomViews` (legacy `woot-delete-modal`) |
| **Conversations — contact-scoped** (via `ViewAllConversations.vue`) | none | basic filter hidden (`ChatListHeader.vue:173`) | **Filter button hidden** (`ChatListHeader.vue:156`, `v-else-if="!isContactScoped"`) | contact name becomes the title, `ChatListHeader.vue:53–55` | none | Back chevron only | n/a |
| **Companies** | `type="search"`, `CompanyHeader.vue:28–44` | `CompanySortMenu`, 5 keys × 2 orders | **none** | n/a | n/a | n/a | n/a |
| **Campaigns** (LiveChat / SMS / WhatsApp) | **none** | **none** | **none** | n/a | n/a | n/a | Audience arrives only as a URL prefill, `WhatsAppCampaignsPage.vue:56–67` |
| **Calls** | none | none | Inline chip bar + "More filters" dropdown, `CallsFilterBar.vue:151–269` | Result count inside the active chip label, `CallsFilterBar.vue:66–69` | **Yes — a different chip** (`Button variant="outline"`, `x` icon) | Click the active chip (`setActivity(null)`), `CallsFilterBar.vue:168` | none |
| **Reports / CSAT / SLA** | none | `groupBy` chip | `AddFilterChip` with hover sub-menus | none | **Yes — a third chip** (`ActiveFilterChip`) | Text `FilterButton` "Clear all", `SLAFilter.vue:247–251`, `CsatFilters.vue:306–310` | none |
| **Audit logs** | none | `i-lucide-arrow-down-up` dropdown whose **label shows the selection** | `i-lucide-list-filter` dropdown whose **label shows the selection**, `AuditLogFilters.vue:195–212` | implicit, via the labels | none | **none** | none |
| **Inbox (notifications)** | none | nested dropdown inside the Display menu | "Display" labelled button → checkbox menu, `InboxListHeader.vue:89–105` | none | none | none (uncheck individually) | none |
| **Search page** (`search`) | the page *is* the search, `SearchInput.vue` (`/` shortcut, 500ms debounce) | none | Inline bar: date range, From, In, `SearchFilters.vue:44–103` | none | none | "Clear filter" button, **rendered twice** (`lg:hidden` at :56, `hidden lg:inline-flex` at :100) | Recent searches, `RecentSearches.vue` |
| **Help Center — articles** | `type="search"` in `#title-actions`, `ArticlesPage.vue:352–362` | none | Locale + Category dropdown buttons with `action: 'filter'`, `ArticleHeaderControls.vue:146–195`; status via `TabBar` | tab counts only, `ArticleHeaderControls.vue:54–60` | none | "All" entry prepended to the category menu, `ArticleHeaderControls.vue:84–100` | none |
| **Settings lists** (automation, macros, labels, teams, templates, agents, SLA, …) | `BaseSettingsHeader` `searchQuery` model, and it is **`hidden sm:flex`**, `BaseSettingsHeader.vue:107` | none | none (automation uses tabs; `Index.vue:47–68`) | none | none | clear the search box | none |

---

## 3. The condition builder, in detail

### 3.1 `ConditionRow.vue` — the one shared row

Rendered by `ContactsFilter`, `ConversationFilter`, the automation rule builder, the flow Condition node, and
the Captain audience group. Five consumers, one component:

| Consumer | File:line | Query-operator mode |
| --- | --- | --- |
| Contacts filter / audience | `ContactsFilter.vue:164–186` | row 0 `:show-query-operator="false"`, rows 1+ `show-query-operator` bound to `filters[index-1].queryOperator` |
| Conversations filter / folder | `ConversationFilter.vue:124–146` | identical shape |
| Automation rule conditions | `AutomationInstantTrigger.vue:120, 130` | identical shape |
| Automation wait conditions | `AutomationWaitCondition.vue:450` | — |
| Flow Condition node | `ConditionsEditor.vue:123, 132` | identical shape |
| Captain assistant audience | `AudienceGroup.vue:118–127` | always `false` (grouping is explicit, nested) |

Models (`ConditionRow.vue:25–45`): `attributeKey` (String, required), `values`
(String|Number|Array|Object, required), `filterOperator` (String, required), `queryOperator`
(String, optional, validator `['and','or']`).

Value-input dispatch (`ConditionRow.vue:221–266`), selected by `inputType = operator.inputOverride ?? filter.inputType`
(`ConditionRow.vue:70–75`):

| `inputType` | Component | Notes |
| --- | --- | --- |
| `multiSelect` | `MultiSelect` | `dropdown-max-height="max-h-72"` |
| `searchSelect` | `SingleSelect` | `dropdown-max-height="max-h-64"` |
| `asyncSearchSelect` | `SingleSelect` `async-search` | 300 ms debounce, stale-response guard, `null` = aborted (`ConditionRow.vue:118–140`) |
| `booleanSelect` | `SingleSelect` `disable-search` | options True/False from `FILTER.ATTRIBUTE_LABELS` |
| `multiText` | `MultiTextInput` | placeholder changes once a token exists (`ConditionRow.vue:253–257`) |
| `date` → `number` → else | `Input` (`type` date / number / text) | `ConditionRow.vue:108–112` |
| operator `is_present` / `is_not_present` | **no input** — the wrapper becomes `contents` | `ConditionRow.vue:214–220` |

Validation: `validateSingleFilter` (`app/javascript/dashboard/helper/validations.js:41–66`) returns one of
`ATTRIBUTE_KEY_REQUIRED`, `FILTER_OPERATOR_REQUIRED`, `VALUE_REQUIRED`,
`VALUE_MUST_BE_BETWEEN_1_AND_998`. Error display is opt-in: `showErrors` is set only by the exposed
`validate()` (`ConditionRow.vue:171–174`) and cleared on any model change (`:167–169`). The failing row
gets `animate-wiggle` (`ConditionRow.vue:188`) plus a `text-n-ruby-11` message (`:277–279`).

Attribute change resets the value to a shape the new input understands
(`ConditionRow.vue:142–165`): `[]` for multiSelect/multiText, `{}` for searchSelect/asyncSearchSelect/booleanSelect,
`''` otherwise; `asyncOptions` is cleared and the operator is snapped to the first legal one.

### 3.2 Operators — `operators.js`

Ten operators (`operators.js:27–38`), each carrying `value`, i18n `label` from `FILTER.OPERATOR_LABELS.<value>`,
`hasInput`, `inputOverride` and a Phosphor icon tinted `!text-n-blue-11` (`operators.js:77–90`):

| Operator | Icon | `hasInput` | `inputOverride` |
| --- | --- | --- | --- |
| `equal_to` | `i-ph-equals-bold` | yes | — |
| `not_equal_to` | `i-ph-not-equals-bold` | yes | — |
| `is_present` | `i-ph-member-of-bold` | **no** | — |
| `is_not_present` | `i-ph-not-member-of-bold` | **no** | — |
| `contains` | `i-ph-superset-of-bold` | yes | — |
| `does_not_contain` | `i-ph-not-superset-of-bold` | yes | — |
| `is_greater_than` | `i-ph-greater-than-bold` | yes | — |
| `is_less_than` | `i-ph-less-than-bold` | yes | — |
| `days_before` | `i-ph-calendar-minus-bold` | yes | **`plainText`** (overrides a `date` field) |
| `starts_with` | `i-ph-caret-line-right-bold` | yes | — |

Named sets (`operators.js:93–129`): `equalityOperators` (2), `presenceOperators` (4),
`containmentOperators` (4), `comparisonOperators` (6), `dateOperators` (3 — greater/less/days_before only,
**no equality**). `getOperatorTypes(displayType)` (`:136–153`) maps custom-attribute display types:
`list|number|link|checkbox|default → equality`, `text → containment`, `date → comparison`.

`starts_with` is defined and iconed but **no provider ever offers it**; only the automation layer can reach it
through `useConditionFilterTypes.filterOperatorsOf` (`useConditionFilterTypes.js:42–57`).

### 3.3 Attribute groups and icons — `filterAttributeIcons.js`

`groupFilterTypes(filterTypes, t, i18nKey = 'FILTER')` (`filterAttributeIcons.js:102–128`) emits a flat list
where each group is introduced by a `{ value: '__group_<model>', label, disabled: true }` entry that
`FilterSelect` renders as a non-clickable title (`FilterSelect.vue:132–137`).

| Order | `attributeModel` | Label key | Contacts label | Conversations label |
| --- | --- | --- | --- | --- |
| 1 | `standard` | `GROUPS.STANDARD_FILTERS` | "Standard Filters" | "Standard filters" |
| 2 | `additional` | `GROUPS.ADDITIONAL_FILTERS` | "Additional Filters" | "Additional filters" |
| 3 | `customAttributes` | `GROUPS.CUSTOM_ATTRIBUTES` | "Custom Attributes" | "Custom attributes" |
| 4 | `conversation` | `GROUPS.CONVERSATIONS` | "Conversations" | **key missing** |
| 5 | `commerce` | `GROUPS.COMMERCE` | "Commerce" | **key missing** |

Groups 4–5 only ever populate on Contacts (`contactProvider.js:211` passes `'CONTACTS_FILTER'`;
`provider.js:304` uses the `'FILTER'` default). `FILTER.GROUPS` in
`app/javascript/dashboard/i18n/locale/en/advancedFilters.json` has only the first three keys.
Unknown models are appended ungrouped rather than dropped (`filterAttributeIcons.js:122–127`).

Icon resolution (`getAttributeIcon`, `filterAttributeIcons.js:76–80`): custom display type → attribute key →
`commerce_spend_*` prefix → `i-lucide-tag` default. The table holds 38 attribute keys and 8 custom-type keys
(`:8–66`) and is **shared with the automation condition picker** (`useConditionFilterTypes.js:5, 74–77`).

### 3.4 Conversation attributes — `provider.js:112–300`

| # | `attributeKey` | Label key | `inputType` | Options source | Operators | Model |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `status` | `FILTER.ATTRIBUTES.STATUS` | `multiSelect` | open/resolved/pending/snoozed/**all** | equality | standard |
| 2 | `priority` | `…PRIORITY` | `multiSelect` | low/medium/high/urgent | equality | standard |
| 3 | `assignee_id` | `…ASSIGNEE_NAME` | `searchSelect` | `agents/getAgents` | presence | standard |
| 4 | `inbox_id` | `…INBOX_NAME` | `searchSelect` | `inboxes/getInboxes` + `useChannelIcon` | presence | standard |
| 5 | `team_id` | `…TEAM_NAME` | `searchSelect` | `teams/getTeams` + `EmojiIcon` | presence | standard |
| 6 | `contact_id` | `…CONTACT` | **`asyncSearchSelect`** | `createContactSearcher()`, `searchPlaceholder` `FILTER.CONTACT_SEARCH_PLACEHOLDER` | equality | standard |
| 7 | `display_id` | `…CONVERSATION_IDENTIFIER` | `number` | — | containment | standard |
| 8 | `campaign_id` | `…CAMPAIGN_NAME` | `searchSelect` | `campaigns/getAllCampaigns` | presence | standard |
| 9 | `labels` | `…LABELS` | `multiSelect` | `labels/getLabels` + 6px colour dot | presence | standard |
| 10 | `browser_language` | `…BROWSER_LANGUAGE` | `searchSelect` | `advancedFilterItems/languages.js` (751 lines) | equality | **additional** |
| 11 | `referer` | `…REFERER_LINK` | `plainText` | — | containment | **additional** |
| 12 | `created_at` | `…CREATED_AT` | `date` | — | date | standard |
| 13 | `last_activity_at` | `…LAST_ACTIVITY` | `date` | — | date | standard |
| + | custom conversation attributes | own display name | from display type | `attributeValues` for `list` | `getOperatorTypes` | `customAttributes` |

`inputType: 'number'` on `display_id` (`provider.js:215`) is not one of the five handled branches in
`ConditionRow`, so it falls through to the final `<Input>` where `inputFieldType` maps `'number'` → `number`
(`ConditionRow.vue:110`). It works, but it is the only attribute typed outside the documented
`'multiSelect'|'searchSelect'|'asyncSearchSelect'|'plainText'|'date'|'booleanSelect'` union
(`provider.js:36`).

### 3.5 Contact attributes — `contactProvider.js:79–207`

| # | `attributeKey` | Label key (**namespace varies**) | `inputType` | Operators | Model |
| --- | --- | --- | --- | --- | --- |
| 1 | `name` | `CONTACTS_LAYOUT.FILTER.NAME` | `plainText` | equality | standard |
| 2 | `email` | `CONTACTS_LAYOUT.FILTER.EMAIL` | `plainText` | containment | standard |
| 3 | `phone_number` | `CONTACTS_LAYOUT.FILTER.PHONE_NUMBER` | `plainText` | containment | standard |
| 4 | `identifier` | `CONTACTS_LAYOUT.FILTER.IDENTIFIER` | `plainText` (`dataType: 'number'`) | equality | standard |
| 5 | `country_code` | **`FILTER.ATTRIBUTES.COUNTRY_NAME`** | `searchSelect` (`shared/constants/countries.js`) | equality | **additional** |
| 6 | `city` | `CONTACTS_LAYOUT.FILTER.CITY` | `plainText` | containment | standard |
| 7 | `company_name` | `CONTACTS_LAYOUT.FILTER.COMPANY` | `plainText` | containment | standard |
| 8 | `created_at` | `CONTACTS_LAYOUT.FILTER.CREATED_AT` | `date` | date | standard |
| 9 | `last_activity_at` | `CONTACTS_LAYOUT.FILTER.LAST_ACTIVITY` | `date` | date | standard |
| 10 | `blocked` | `CONTACTS_LAYOUT.FILTER.BLOCKED` | `searchSelect` (`'true'`/`'false'` strings) | equality | standard |
| 11 | `labels` | **`CONTACTS_FILTER.ATTRIBUTES.LABELS`** | `multiSelect` | equality | standard |
| + | custom contact attributes | own display name | from display type | `getOperatorTypes` | `customAttributes` |
| + | `audienceFilterTypes` | see §3.6 | — | — | `conversation` / `commerce` |

`CONTACT_ATTRIBUTES` (`filterHelper.js:26–39`) also declares `REFERER: 'referer'`, which is used only to
*exclude* a same-named custom attribute (`buildAttributesFilterTypes`, `filterHelper.js:73–80`) — contacts
have no referer condition in the next builder.

### 3.6 Lynomia audience fields — `audienceProvider.js`

Conversation block (`audienceProvider.js:94–139`), all `multiSelect` + equality, model `conversation`:
`conversation_status`, `conversation_priority`, `conversation_inbox`, `conversation_assignee`,
`conversation_team`, `conversation_labels`.

Commerce block (`audienceProvider.js:141–224`), model `commerce`, gated on
`FEATURE_FLAGS.LYNOMIA_COMMERCE` and on `commerceFields.accountId === accountId`:

| `attributeKey` | `inputType` | Operators |
| --- | --- | --- |
| `commerce_store` | `multiSelect` (account's stores) | **presence** |
| `commerce_provider` | `multiSelect` (distinct providers) | equality |
| `commerce_orders_count` | `number` | `equal_to`, `is_greater_than`, `is_less_than` |
| `commerce_spend_<currency>` (one per currency) | `number` | `is_greater_than`, `is_less_than` |
| `commerce_last_purchase_at` | `date` | date set |
| `commerce_active_order` | `searchSelect` Yes/No | `equal_to` only |
| `commerce_order_status` | `multiSelect` (11 statuses, `:13–25`) | equality |
| `commerce_payment_status` | `multiSelect` (7 statuses, `:26–34`) | equality |
| `commerce_shipment_status` | `multiSelect` (8 statuses, `:35–44`) | equality |

Options are fetched once per account into a **module-level** `ref` (`audienceProvider.js:51`) by
`loadAudienceFields()`; a failed fetch silently yields no Commerce fields (`:74–77`). The fetch is kicked
twice — `ContactsFilter.vue:116` `onMounted` and `ContactListHeaderWrapper.vue:76` `onMounted` plus again in
`onToggleFilters` (`:342`) — and is idempotent by the `accountId` guard.

`audienceValuesForEdit(filterType, values)` (`audienceProvider.js:264–272`) rehydrates a saved condition into
the shape its row's input edits: matched options array for `multiSelect`, first match or `{}` for
`searchSelect`, first string otherwise.

### 3.7 Contextual notes inside `ContactsFilter` (Lynomia-only, no equivalent on Conversations)

| Note | Condition | Styling | Test id |
| --- | --- | --- | --- |
| Shared-audience note | `sharedSegment` prop | `bg-n-amber-2 text-n-amber-11` when segment-view **and** in use, else `bg-n-alpha-2 text-n-slate-11`; `ContactsFilter.vue:189–200` | `shared-audience-note` |
| Conversation-conditions note | any `conversation_*` key in use (`:104–106`) | `text-label-small text-n-slate-11` | `audience-notes` |
| Commerce-conditions note | any `commerce_*` key in use (`:107–109`) | same | `audience-notes` |
| Unread-contacts warning | a `COMMERCE_ORDER_KEY` field in use **and** `unreadContacts > 0` (`:110–114`) | `bg-n-amber-2 text-n-amber-11` | `audience-unread` |

The shared-audience text has three variants — `READ_ONLY` (member, cannot edit), `USED_BY` (admin, N rules /
M campaigns depend on it), `EDIT` (admin, unused) — selected at `ContactsFilter.vue:120–130`.

---

## 4. Opening, anchoring and closing each panel

| Panel | Trigger id | Mount strategy | Anchor classes | Outside-click |
| --- | --- | --- | --- | --- |
| `ContactsFilter` | `#toggleContactsFilterButton` (`ContactHeader.vue:75`) | `#filter` **slot** inside the header's `sm:relative` wrapper (`ContactHeader.vue:73, 90`), panel wrapped in `ContactListHeaderWrapper.vue:401–403` | `absolute mt-1 inset-x-0 sm:inset-x-auto sm:ltr:right-0 sm:rtl:left-0 top-full` | `vOnClickOutside` + `{ ignore: ['#toggleContactsFilterButton'] }` (`ContactsFilter.vue:139–142`) |
| `ConversationFilter` | `#toggleConversationFilterButton` — **declared 3×** (`ChatListHeader.vue:132, 147, 157`) | `TeleportWithDirection` → `#conversationFilterTeleportTarget` (`ChatList.vue:972–984`), target rendered **twice** (`ChatListHeader.vue:140–144, 166–170`) | target: `absolute z-50 mt-2` + `ltr:right-0 rtl:left-0` only when `isOnExpandedLayout` | `vOnClickOutside` + `{ ignore: ['#toggleConversationFilterButton'] }` (`ConversationFilter.vue:99–102`) |
| `SaveCustomView` (folders) | the `i-lucide-save` button | `TeleportWithDirection` → `#saveFilterTeleportTarget` (`ChatList.vue:902–912`, target `ChatListHeader.vue:122–126`) | `absolute z-50 mt-2`, right-aligned only on expanded layout | `vOnClickOutside` + `{ ignore: ['#saveFilterTeleportTarget'] }` (`SaveCustomView.vue:98–101`) |
| `ConversationBasicFilter` | — (no id) | sibling `absolute` div | `top-full`, `ltr:left-0` normally / `ltr:right-0` on expanded layout (`ConversationBasicFilter.vue:159–162`) | `vOnClickOutside` (`:157`) |
| `ContactSortMenu` | — | sibling `absolute` div | `top-full mt-1 ltr:-right-32 rtl:-left-32 sm:ltr:right-0 sm:rtl:left-0`, `w-72` (`ContactSortMenu.vue:108`) | `v-on-clickaway` (`:107`) |
| `ContactMoreActions` | — | `DropdownMenu` | `ltr:right-0 rtl:left-0 mt-1 w-60 top-full` (`ContactMoreActions.vue:219`) | `v-on-clickaway` on the wrapper (`:205`) |
| `CallsFilterBar` menus | — | three `OnClickOutside` wrappers, one `openMenu` ref | `mt-1 … top-full w-44 / w-56` | `OnClickOutside` component + a guard so sibling wrappers do not close the open menu (`CallsFilterBar.vue:60–62`) |
| `AuditLogFilters` menus | — | `DropdownMenu` per menu | `mt-2 min-w-52 max-h-80 top-full start-0` | one `vOnClickOutside` for the whole bar (`:174`) |
| Reports chips | — | legacy `DropdownList` | `top-10`, `left-0 md:right-0` | `v-on-clickaway` |
| `SidebarSortMenu` | — | `TeleportWithDirection` + `useDropdownPosition` | `!fixed` + computed style (`SidebarSortMenu.vue:186–207`) | `vOnClickOutside` with a trigger guard (`:155–158`) |

**Three different outside-click mechanisms coexist**: the `vOnClickOutside` directive from
`@vueuse/components`, the global `v-on-clickaway` directive, and the `OnClickOutside` component.

Closing semantics also differ. `ContactsFilter` and `ConversationFilter` both emit `close` from
`onBeforeUnmount` (`ContactsFilter.vue:138`, `ConversationFilter.vue:98`) — so unmount *is* close.
`ChatList.onToggleAdvanceFiltersModal` toggles (`ChatList.vue:551–567`), while
`ContactListHeaderWrapper.onToggleFilters` always opens and re-seeds (`:340–359`) — clicking the Contacts
filter button while the panel is open re-initialises it rather than closing it; only the
outside-click `ignore` keeps it from flickering.

---

## 5. Panel geometry, and what happens at 390px

| Panel / control | Classes | Rendered width at 390px |
| --- | --- | --- |
| `ContactsFilter` root | `w-full sm:w-[min(34rem,calc(100vw-2rem))] lg:w-[750px] … rounded-xl p-6 grid gap-6` (`ContactsFilter.vue:148`) | `w-full` of a wrapper that is `inset-x-0` across the header → ~390px minus the header's `px-6` (48px) ⇒ **342px**, with 24px internal padding on each side ⇒ **294px of content** |
| `ConversationFilter` root | `w-[min(34rem,calc(100vw-2rem))] lg:w-[750px] … p-6 grid gap-6` (`ConversationFilter.vue:108`) | `min(544, 358)` ⇒ **358px**; **no `w-full` branch**, so it is 358px regardless of the 340px list column it is anchored in and will overhang |
| `SaveCustomView` root | `max-w-3xl lg:w-[500px] overflow-visible w-full … p-6` (`SaveCustomView.vue:102`) | `w-full` of its teleport target ⇒ collapses to content width inside an `absolute` box |
| `ConditionRow` row | `flex flex-wrap gap-2` (`ConditionRow.vue:186`) | 4 controls (query-op, attribute, operator, value) + trash wrap onto **3–4 lines** per condition |
| `MultiTextInput` | `w-full min-w-64` (`MultiTextInput.vue:48`) | floor of **256px**, so it claims almost the whole 294px row and forces the trash button onto its own line |
| `MultiSelect` chip | `max-w-[100px]` per chip, `maxChips` 3 (`MultiSelect.vue:125, 20`) | 3 chips ⇒ ~300px + the `+` cell, wider than the row |
| `FilterSelect` dropdown | `min-w-56 z-50` (`FilterSelect.vue:117`) | 224px minimum; flips to `bottom-0` when `spaceBelow < menuHeight` (`:78–86`, `DROPDOWN_MAX_HEIGHT = 340`) |
| `SingleSelect` / `MultiSelect` dropdown | `top-0 min-w-56` / `top-0 min-w-48` (`SingleSelect.vue:160`, `MultiSelect.vue:163`) | **no flip logic at all** — always opens downward from `top-0` |
| `ContactSortMenu` panel | `ltr:-right-32 … w-72` (`ContactSortMenu.vue:108`) | 288px panel offset **128px past the right edge of its trigger**; the `sm:ltr:right-0` correction does not apply at 390px |
| `ContactHeader` action row | `flex items-start sm:items-center justify-between … flex-col sm:flex-row` (`ContactHeader.vue:45, 50`) | search stacks **above** a 4-button + divider + Compose row; the Compose label is untruncated |
| `BaseSettingsHeader` search | `hidden sm:flex` (`BaseSettingsHeader.vue:107`) | **the search box does not exist at 390px** on every settings list that relies on it |
| `BaseSettingsHeader` tabs/search wrapper | `hidden sm:flex` when there are no tabs (`:98–100`) | same — the whole left cluster disappears |
| `ChatListHeader` | `flex items-center justify-between gap-2 px-3 h-[3.25rem]` (`ChatListHeader.vue:75`) | no wrapping; title truncates, 3–4 `xs` buttons stay on one line |
| `CallsFilterBar` | `flex flex-wrap items-center justify-between gap-3` (`CallsFilterBar.vue:152`) | chips wrap; the assignee chip is `max-w-52` |
| `SearchFilters` | `flex flex-col lg:flex-row` (`SearchFilters.vue:46`) | stacks; the `lg:hidden` clear button is the one shown (`:56`) |
| `ArticleHeaderControls` | `flex flex-col items-start w-full gap-2 lg:flex-row` (`ArticleHeaderControls.vue:138`) | tabs stack above the locale/category/new-article row |
| `AuditLogFilters` | `flex flex-wrap sm:flex-nowrap items-center gap-2` (`AuditLogFilters.vue:175`) | wraps |
| `InboxDisplayMenu` | `max-w-64 min-w-[170px] w-fit` (`InboxDisplayMenu.vue:118`) | 170–256px; the nested sort popover is `min-w-20 max-w-32` |

Mobile-specific notes:

- The Contacts panel is *deliberately* header-anchored below `sm`: "Below sm the filter panel anchors to the
  header, so it spans the screen instead of the button" (`ContactHeader.vue:72`). The conversations panel has
  no such accommodation.
- `ContactsFilter`'s footer is `flex flex-wrap justify-between gap-2` (`:220`) so "Add filter" and the
  Clear/Apply pair wrap onto two lines; `ConversationFilter`'s footer is `flex gap-2 justify-between`
  (`:149`) with **no wrap**, so its three buttons compress on a narrow panel.
- No filter trigger is larger than 32px (`size="sm"` / `xs`); `ContactHeader`'s is `class="relative w-8"`
  (`:80`).

---

## 6. Active-filter signalling and clear-all

### 6.1 `ActiveFilterPreview.vue` — the only chip row in the product

Props (`ActiveFilterPreview.vue:6–12`): `appliedFilters` (Array), `maxVisibleFilters` (Number, default **2**),
`clearButtonLabel`, `moreFiltersLabel`, `showClearButton` (Boolean, default true).
Emits `clearFilters`, `openFilter` (`:14`).

Chip anatomy (`:54–88`): a bordered `h-7 max-w-72` box holding attribute name → operator phrase →
truncated value, with the whole chip clickable to **open the panel** — there is **no per-chip remove**.
Between the first and second chip the raw `queryOperator` string is printed uppercase (`:89–99`), so a chip
row of 3+ conditions shows "A and B · +1 more filters" and never reveals the third operator.
Overflow is a text affordance, also wired to `openFilter` (`:102–108`). A `w-px h-3` divider and a
`size="xs" variant="ghost"` Clear button close the row (`:109–117`).

Value formatting (`:36–48`) handles `null`, arrays (`item?.name ?? item`, joined by `, `), `{name}` objects
and primitives. Operator formatting (`:21–34`) maps nine operators to **hardcoded English phrases**
(`'is'`, `'is not'`, `'contains'`, …) and falls back to `replaceUnderscoreWithSpace`.

### 6.2 Who shows what

| Surface | Mechanism | File:line |
| --- | --- | --- |
| Contacts | brand dot on the trigger + chip row + ghost Clear | `ContactHeader.vue:85–88`; `ContactsListLayout.vue:103–109` |
| Contacts (segment) | chip row with Clear suppressed; no dot | `ContactsActiveFiltersPreview.vue:86`; `ContactHeader.vue:86` |
| Conversations | header gets `border-b border-n-strong`; a result-count pill replaces the status pill; a back-chevron appears | `ChatListHeader.vue:76–78, 95–109, 81–91` |
| Calls | the active chip carries `label (count)` and an `x`; "More filters" turns `color="blue"` | `CallsFilterBar.vue:66–69, 251` |
| Reports / CSAT / SLA | one `ActiveFilterChip` per active filter + "Clear all" | `SLAFilter.vue:206–251` |
| Audit logs | the dropdown button label *is* the state | `AuditLogFilters.vue:126–131` |
| Search | presence of a "Clear filter" button | `SearchFilters.vue:21–28` |
| Inbox notifications | checkbox checked state | `InboxDisplayMenu.vue:179–186` |

**No surface anywhere displays a numeric count of active filter conditions.**

### 6.3 Clear-all semantics diverge

| Panel | Function | What it does |
| --- | --- | --- |
| `ContactsFilter` | `resetFilter` (`:55–58`) | **emits `clearFilters`** *and* resets rows to one default (`name equal_to ''`). The parent chain `ContactListHeaderWrapper.clearFilters` (`:276–278`) → `ContactsListLayout` → `ContactsIndex` `@clear-filters="fetchContacts"` (`:521`) refetches immediately, while the panel stays open showing the reset row |
| `ConversationFilter` | `resetFilter` (`:45–47`) | **only** resets the local rows. Its `defineEmits` has no `clearFilters` (`:26`), so the applied conversation filter stays in effect until Apply is pressed |
| `ActiveFilterPreview` | `clearFilters` emit (`:116`) | Contacts only |
| `ChatListHeader` back-chevron | `resetFilters` → `ChatList.resetAndFetchData` | the real conversations clear-all, labelled only by a tooltip reading `FILTER.CLEAR_BUTTON_LABEL` |
| Reports / CSAT / SLA | `clearAllFilters` | removes every chip |
| `CallsFilterBar` | `setActivity(null)` | clears only the activity dimension; inbox and assignee need their own "All …" entries |
| Audit logs / Help Center / Inbox | — | **no clear-all** |

Removing the **last** condition is also inconsistent in effect though identical in code: both panels'
`removeFilter` calls `resetFilter` when `length === 1` (`ContactsFilter.vue:60–66`,
`ConversationFilter.vue:49–55`), which on Contacts silently clears the applied filter and refetches, and on
Conversations does not.

---

## 7. Saved views — folders, segments, audiences

One backend concept (`custom_views`, `filter_type` 0 = conversation folder, 1 = contact segment) behind two
entirely separate UIs.

| Step | Conversation folder | Contact segment / audience |
| --- | --- | --- |
| Create | `SaveCustomView.vue` — teleported panel, Options API, `@vuelidate` `required+minLength(1)`, dispatches `customViews/create` itself (`:67–71`), then `openLastSavedItem()` | `CreateSegmentDialog.vue` — `Dialog`, `<script setup>`, `required`, **emits** `create`; parent dispatches (`ContactListHeaderWrapper.vue:155–179`). Adds an admin-only "Share with the whole account" checkbox (`:98–116`) |
| Entry | `i-lucide-save` `xs faded` button, visible only when `hasAppliedFilters && !hasActiveFolders` (`ChatListHeader.vue:112–128`) | `i-lucide-save` ghost button, visible when `hasActiveFilters && !isSegmentsView && !isLabelView && !isActiveView` (`ContactHeader.vue:92–104`) |
| Edit | same `ConversationFilter` with `is-folder-view`; header gets a folder-name `Input` (`:113–121`) and the submit becomes "Update folder" | same `ContactsFilter` with `is-segment-view`; header gets an audience-name `Input` (`:153–161`) and the submit becomes "Update audience" |
| Rehydrate | `ChatList.initializeFolderToFilterModal` (`:515–545`) via `generateValuesForEditCustomViews` + the **legacy** `advancedFilterTypes` | `ContactListHeaderWrapper.initializeSegmentToFilterModal` (`:307–338`) — tries `audienceValuesForEdit` first, then `generateValuesForEditCustomViews` with the **legacy** `contactFilterItems` |
| Delete | `DeleteCustomViews.vue` (`routes/dashboard/customviews/`) — legacy `woot-delete-modal`, Options API | `DeleteSegmentDialog.vue` + a dedicated `i-lucide-trash` header button; surfaces the server's refusal reason for a shared audience in use (`ContactListHeaderWrapper.vue:197–208`) |
| Duplicate | **not offered** | `ContactMoreActions` → `duplicateSegment` reuses `CreateSegmentDialog` with a prefilled `"{name} copy"` (`ContactListHeaderWrapper.vue:215–229`) |
| Build from preset | **not offered** | `ContactMoreActions` → `RecipeDialog` over `AUDIENCE_PRESETS`, then the same create dialog (`:233–242`, `:425–432`) |
| Copy link | **not offered** | `copySegmentLink` (`:261–269`) |
| Cross-module use | **not offered** | "Use in a new automation rule" / "Use in a new WhatsApp campaign" via `?audience=<id>` (`:249–259`); the menu shows them only for a *shared* audience whose target route the user can reach (`ContactMoreActions.vue:41–53, 98–119`) |
| Usage disclosure | — | disabled menu row "Used by N automation rules · M campaigns" (`ContactMoreActions.vue:57–97`) |
| Sidebar presentation | `Folders` sub-group, `i-lucide-folder`, **has a sort menu** (`buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS)`, `Sidebar.vue:446`), unread badge per folder (`:452–454`) | `Segments` sub-group, `i-lucide-group`, **no sort menu**, no badge; a shared audience's label is wrapped in `SIDEBAR.SHARED_AUDIENCE` (`Sidebar.vue:547–568`) |

`SaveCustomView` receives `v-model="appliedFilter"` from `ChatList.vue:907` but declares no `modelValue`
prop and no `update:modelValue` emit (`SaveCustomView.vue:19–33`) — the binding is dead. Its `filterType`
prop (default `0`) is also never passed, so it can only ever create folders.

---

## 8. Search

| Surface | Component | Debounce | Clears filters? | Hidden at 390px? |
| --- | --- | --- | --- | --- |
| Contacts | `ContactHeader.vue:52–68` → `ContactsIndex` `searchContacts` | 500 ms (`ContactsIndex.vue:243`, `debounce` from `@chatwoot/utils`) | **Yes** — `contacts/clearContactFilters` on every search (`ContactsIndex.vue:254`), and again in `fetchContacts` (`:205`) | no (stacks above the actions) |
| Companies | `CompanyHeader.vue:28–44` | parent | n/a | no |
| Search page | `SearchInput.vue` | 500 ms, and ignores 1-character non-numeric queries (`:27–31`) | n/a | no |
| Settings lists | `BaseSettingsHeader.vue:103–117` | none (client-side `filteredRecords`) | n/a | **yes** (`hidden sm:flex`) |
| Help Center articles | `ArticlesPage.vue:352–362` | `debouncedSearch` | n/a | no |
| Inside filter dropdowns | `FilterSelect` / `MultiSelect` (over `DROPDOWN_SEARCH_THRESHOLD = 8` options) / `SingleSelect` (**always**) | none; `picoSearch` | n/a | no |

Search-in-dropdown behaviour differs by component:

| Component | Shows search when | Search key | Section headers while searching | Empty state |
| --- | --- | --- | --- | --- |
| `FilterSelect` | `options.length > 8` (`:52–54`) | `['label']` | **dropped** — `option.disabled` entries are filtered out (`:61–62`) | `COMBOBOX.EMPTY_SEARCH_RESULTS` / `COMBOBOX.EMPTY_STATE` |
| `MultiSelect` | `options.length > 8` (`:39`) | `['name']` | n/a | same two states |
| `SingleSelect` | **always**, unless `disable-search` (`:161`) | `['name']`, or bypassed entirely when `asyncSearch` (`:81–85`) | n/a | adds `DROPDOWN_MENU.SEARCHING` while `isSearching` (`:172–176`) |

`picoSearch` throws on a whitespace-only query, so `FilterSelect` and `MultiSelect` trim and short-circuit
(`FilterSelect.vue:57–59`, `MultiSelect.vue:42–44`); `SingleSelect` passes `searchTerm.value` straight
through (`:84`). All three re-focus their input through a local `vFocus` directive
(`FilterSelect.vue:46`, `MultiSelect.vue:29`, `SingleSelect.vue:71`) — three copies of the same directive.
All three clear the query on open via a `toggleDropdown` wrapper, except `SingleSelect`, which calls
`toggle` directly (`:133, 150`) and keeps the previous query.

---

## 9. Sort controls — five independent implementations

| Component | Shape | Options | Persistence |
| --- | --- | --- | --- |
| `ContactSortMenu.vue` | `i-lucide-arrow-down-up` ghost button → `w-72` panel, two `SelectMenu` rows ("Sort by" / "Ordering") | 7 sort keys × asc/desc (`:25–65`) | `ui_settings.contacts_sort_by` (`ContactsIndex.vue:403–405`) |
| `CompanySortMenu.vue` | **structurally identical** to the above | 5 sort keys × asc/desc (`:25–57`) | `ui_settings` |
| `ConversationBasicFilter.vue` | `i-lucide-arrow-up-down` faded button → `w-72` panel, two `SelectMenu` rows ("Status" / "Order by") | 5 statuses × 10 sort orders (`:45–109`) | `ui_settings.conversations_filter_by` (`:123–130`) + `setChatStatusFilter` / `setChatSortFilter` |
| `SidebarSortMenu.vue` | hover-opened `xs` button → teleported `DropdownMenu` with 3 titled sections | created / alphabetical / unread-count, asc+desc (`:28–47`) | `sidebarSortPreferences/setSectionSort` (`Sidebar.vue:308–313`) |
| `InboxDisplayMenu.vue` | nested popover inside the Display menu, hand-rolled rows | newest / oldest (`:38–49`) | `ui_settings.inbox_filter_by.sort_by` (`:90–97`) |
| Audit logs | a `DropdownMenu` whose button label is the selection | newest / oldest (`:96–112`) | URL query |

`ContactSortMenu` and `CompanySortMenu` are the same 130-line component twice. `ConversationBasicFilter` is a
third copy of the same `w-72` + two-`SelectMenu` layout, differing only in which store actions it dispatches.

---

## 10. The parallel legacy registry (still live)

Two complete, divergent descriptions of the same attributes exist:

| | Next (`components-next/filter/`) | Legacy (`advancedFilterItems/`, `contactFilterItems/`) |
| --- | --- | --- |
| Casing | camelCase (`multiSelect`, `searchSelect`, `plainText`) | snake_case (`multi_select`, `search_select`, `plain_text`) |
| Operators | `useOperators()`, i18n labels, icons, `hasInput`, `inputOverride` | `OPERATOR_TYPES_1..5`, **English labels baked in**, no icons |
| Labels | resolved in the provider | `attributeI18nKey`, resolved by the consumer |
| Icons / groups | `getAttributeIcon` + `groupFilterTypes` | `filterAttributeGroups` (name + `i18nGroup` + key/i18nKey pairs), no icons |
| Who reads it | `ContactsFilter`, `ConversationFilter`, automation, flows, Captain | `ChatList.setParamsForEditFolderModal` (`:461–490`), `ContactListHeaderWrapper.setParamsForEditSegmentModal` (`:298–305`), `useFilter.setFilterAttributes` |

Legacy-side defects visible in the files:

- `advancedFilterItems/index.js` declares **`referer` twice** — lines 89–96 (`OPERATOR_TYPES_3`,
  `additional`) and lines 113–120 (`OPERATOR_TYPES_5`, `standard`).
- `advancedFilterItems/filterAttributeGroups` (`:123–184`) **omits `priority`**, which exists in its own
  `filterTypes` (`:25–32`).
- `contactFilterItems/filterAttributeGroups` (`:106–157`) has **no "Additional Filters" group** and omits
  `referer`, which exists in its `filterTypes` (`:81–88`).
- `useFilter.customAttributeInputType` maps `checkbox → 'search_select'` (`:16–17`) while the next helper
  maps it to `'booleanSelect'` (`filterHelper.js:53–54`).
- `useFilter.getOperatorTypes` maps `date → OPERATOR_TYPES_4` (6 operators incl. equality) while the next
  one maps `date → comparisonOperators` (also 6) but the *providers* use `dateOperators` (3). Three answers
  for "which operators does a date take".

---

## 11. Analytics, store wiring and permissions

| Event / getter / action | Where | Note |
| --- | --- | --- |
| `CONTACTS_EVENTS.APPLY_FILTER` | `ContactsFilter.vue:92–98` | payload: key, operator, queryOperator per condition |
| `CONVERSATION_EVENTS.APPLY_FILTER` | `ConversationFilter.vue:83–89` | same payload shape |
| `CONTACTS_EVENTS.SAVE_FILTER` | `SaveCustomView.vue:78–80` | `type: 'folder' \| 'segment'` |
| `CONTACTS_EVENTS.DELETE_FILTER` | `DeleteCustomViews.vue:79–81` | reads `this.filterType` (undefined) instead of `this.activeFilterType` |
| `contacts/setContactFilters` | dispatched **from inside the panel** (`ContactsFilter.vue:87–90`) | panel writes to the store, then emits |
| `setConversationFilters` | dispatched from inside the panel (`ConversationFilter.vue:78–81`) | same |
| `contacts/getAppliedContactFiltersV4` | `store/modules/contacts/getters.js:34–36` | camelCased view of `appliedFilters`; read by `ContactListHeaderWrapper.vue:74` and `ContactsActiveFiltersPreview.vue:23` |
| `getAppliedConversationFiltersV2` / `…Query` / `getAppliedContactFilter` | `store/modules/conversations/getters.js:91, 104, 98` | three separate conversation-filter getters |
| `contacts/clearContactFilters` | `store/modules/contacts/actions.js:328` | called by search and by `fetchContacts` |
| Filter button permission | **none** — the Contacts filter button has no `Policy` wrapper | `ContactHeader.vue:73–91` |
| Segment edit permission | `canManageSegment = !isSharedSegment \|\| isAdmin` (`ContactListHeaderWrapper.vue:86–88`); drives `is-segment-view` so a member gets the plain filter panel on a shared audience | |
| Overflow permissions | `checkPermissions(['administrator','contact_manage'])` for duplicate/import/export; route-meta reachability check for the two cross-module actions (`ContactMoreActions.vue:34–53`) | |

---

## 12. Accessibility and keyboard, as it stands

| Fact | Evidence |
| --- | --- |
| No filter trigger carries `aria-expanded` or `aria-haspopup` | `ContactHeader.vue:74–89`, `ChatListHeader.vue:156–165`, `ConversationBasicFilter.vue:147–154`, `ContactSortMenu.vue:97–104`, `CallsFilterBar.vue:189–202` |
| The Contacts "has filters" dot has no text alternative | `ContactHeader.vue:85–88` |
| `ContactMoreActions` is the only menu trigger with an `aria-label` | `:211` |
| Icon-only filter / save / delete buttons rely on `v-tooltip` for their name on Conversations | `ChatListHeader.vue:83–84` (has both `v-tooltip` and `aria-label`), `:115, 133, 148, 159` (tooltip only) |
| `ActiveFilterPreview` chips are `div`s with `@click`, not buttons | `:54–61, 102–108` |
| `MultiTextInput` wrapper is a `div tabindex="0"` with `@focus`/`@click` | `:47–53` |
| `InboxDisplayMenu` sort rows are `div role="button"` without key handling | `:142–151` |
| `InboxDisplayMenu` uses a raw `<input type="checkbox">` with 11 utility classes emulating a checkbox instead of `components-next/checkbox/Checkbox.vue` | `:179–186` |
| `ConditionRow` section headers are `<li>` with `select-none`, not `role="presentation"`/`optgroup` | `FilterSelect.vue:132–137` |
| Keyboard shortcuts: `/` focuses the dedicated search input; `Escape` blurs it; `Alt+N` cycles conversation assignee tabs | `SearchInput.vue:17–25`, `ChatTypeTabs.vue:32–43` |
| **No keyboard route opens any filter panel** | — |
| `ContactsFilter` / `ConversationFilter` do not trap focus and do not close on `Escape` | `ContactsFilter.vue:139–142`, `ConversationFilter.vue:99–102` |
| Direction: `ContactHeader`'s active dot uses `right-0` rather than `end-0`; `ContactSortMenu` hand-pairs `ltr:`/`rtl:` offsets | `ContactHeader.vue:87`, `ContactSortMenu.vue:108` |
| `TeleportWithDirection` exists precisely because teleported panels lose `[dir]` | `TeleportWithDirection.vue:1–5` |

---

## 13. Design-system usage inside this area

| Primitive | Used by | Notes |
| --- | --- | --- |
| `next/button/Button.vue` | every panel, every trigger | two import spellings coexist: `next/button/Button.vue` (`ContactsFilter.vue:15`) and `dashboard/components-next/button/Button.vue` (`ActiveFilterPreview.vue:4`); and two prop styles — boolean shorthands (`sm faded slate`) vs named props (`size="sm" variant="ghost" color="slate"`) |
| `next/dropdown-menu/base/{DropdownContainer,DropdownBody,DropdownSection,DropdownItem}` | `FilterSelect`, `MultiSelect`, `SingleSelect` | the three filter inputs share the base layer |
| `components-next/dropdown-menu/DropdownMenu.vue` | `ContactMoreActions`, `CallsFilterBar`, `AuditLogFilters`, `SidebarSortMenu`, `ArticleHeaderControls` | the higher-level menu, with `show-search` and `menuSections` |
| `components-next/selectmenu/SelectMenu.vue` | `ContactSortMenu`, `CompanySortMenu`, `ConversationBasicFilter` | only ever inside sort panels |
| `components-next/input/Input.vue` | `ConditionRow` value input, folder/segment name, every list search | `ConditionRow` overrides its height with `[&>input]:h-8 [&>input]:py-1.5` (`:263`) |
| `components-next/inline-input/InlineInput.vue` | `MultiTextInput` | |
| `components-next/icon/Icon.vue`, `emoji-icon-picker/EmojiIcon.vue` | all three filter inputs | |
| `components-next/dialog/Dialog.vue` | `CreateSegmentDialog`, `DeleteSegmentDialog` | the segment path uses dialogs; the folder path uses teleported panels and `woot-delete-modal` |
| `components/ui/Dropdown/{DropdownButton,DropdownList,DropdownListItemButton,DropdownEmptyState}` | reports/CSAT/SLA chips only | the pre-`components-next` dropdown layer, still shipping |
| `woot-delete-modal`, `woot-tabs` | `DeleteCustomViews`, `ChatTypeTabs` | legacy globals |
| Panel surface recipe | `border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-lg rounded-xl p-6 grid gap-6` | repeated verbatim in `ContactsFilter.vue:148`, `ConversationFilter.vue:108`, `SaveCustomView.vue:102`; `ContactSortMenu.vue:108` and `ConversationBasicFilter.vue:158` use a `p-4 w-72` variant of it; `InboxDisplayMenu.vue:118` uses an `outline`-based variant instead of `border` |
| `text-base font-medium leading-6 text-n-slate-12` panel title | `ContactsFilter.vue:150`, `ConversationFilter.vue:110`, `SaveCustomView.vue:104` | not the `text-heading-*` typography utilities used elsewhere (`CampaignLayout.vue:28`, `BaseSettingsHeader.vue:56`) |

---

## 14. Inconsistencies, ranked

### High

1. **Conversations has no active-filter chips and no in-panel clear.** `ConversationFilter` never emits a
   clear (`:26`, `:45–47`); `ActiveFilterPreview` has exactly one consumer, Contacts
   (`ContactsActiveFiltersPreview.vue:8`). The only conversation clear-all is a back-chevron whose sole
   label is a tooltip (`ChatListHeader.vue:81–91`).
2. **No numeric active-filter count anywhere.** Contacts shows an unlabelled 8×8px dot
   (`ContactHeader.vue:85–88`); Conversations shows nothing on the trigger at all.
3. **Six unrelated filter idioms.** Header-anchored condition panel (Contacts), teleported condition panel
   (Conversations), inline outline-chip bar (`CallsFilterBar`), legacy chip + hover-sub-menu
   (`ActiveFilterChip`/`AddFilterChip`), label-bearing dropdown buttons (`AuditLogFilters`), checkbox menu
   (`InboxDisplayMenu`). Three different chip components, three different clear-all affordances.
4. **Two live filter-type registries.** camelCase next providers vs snake_case legacy arrays, both consumed
   in the same files (`ChatList.vue:37` + `ChatList.vue:487` beside `provider.js`;
   `ContactListHeaderWrapper.vue:10, 301` beside `contactProvider.js`).
5. **Duplicate DOM id.** `#toggleConversationFilterButton` is set on three buttons
   (`ChatListHeader.vue:132, 147, 157`) and `#conversationFilterTeleportTarget` on two divs
   (`:140, 166`) — the outside-click `ignore` and the teleport target both depend on uniqueness.

### Medium

6. **Chip operator phrases are hardcoded English** (`ActiveFilterPreview.vue:21–34`) while the panel's own
   operator labels come from `FILTER.OPERATOR_LABELS`.
7. **Three i18n namespaces in one attribute list**: `CONTACTS_LAYOUT.FILTER.*` for most contact fields,
   `FILTER.ATTRIBUTES.COUNTRY_NAME` for country (`contactProvider.js:123`),
   `CONTACTS_FILTER.ATTRIBUTES.LABELS` for labels (`:194`). `CONTACTS_FILTER.ATTRIBUTES` still carries a
   near-complete duplicate set the next builder no longer reads.
8. **Search and filters are mutually exclusive on Contacts but the UI does not say so.** Every search
   dispatches `contacts/clearContactFilters` (`ContactsIndex.vue:254`), yet the dot, the chip row and the
   panel's rows are all driven off state that has just been wiped.
9. **`SingleSelect` ignores `DROPDOWN_SEARCH_THRESHOLD`** and renders a search box over a 2-option
   Yes/No list (`:161`, reached from `commerce_active_order` and `blocked`), contradicting the
   "never disagree on when to show one" intent in `filterHelper.js:1–5`.
10. **`FilterSelect` discards group headers the moment a query is typed** (`:61–62`), so the grouped
    attribute picker silently flattens during search.
11. **Dropdown flip logic exists only in `FilterSelect`** (`:78–86`); `MultiSelect` and `SingleSelect`
    always open downward from `top-0`, so the lower rows of a tall condition list open off-screen.
12. **`ContactSortMenu`'s panel is offset 128px past its trigger below `sm`** (`ltr:-right-32`, `:108`),
    the only control in the area that positions itself this way at 390px.
13. **Settings-list search vanishes at 390px** (`BaseSettingsHeader.vue:98–100, 107`, `hidden sm:flex`) —
    automation, macros, labels, teams, templates, agents, SLA and the rest become unsearchable on a phone.
14. **Campaigns has no list controls at all** — no search, no sort, no filter (`CampaignLayout.vue:23–57`,
    `WhatsAppCampaignsPage.vue:83–119`), while every other first-class list has at least two.
15. **Companies has search and sort but no filter**, even though `CompanyHeader` is otherwise a copy of
    `ContactHeader`.
16. **Five sort implementations** (§9), two of which (`ContactSortMenu` / `CompanySortMenu`) are the same
    component duplicated.
17. **Three outside-click mechanisms** in one feature area (§4).
18. **Segments sidebar section has no sort menu** while Folders does (`Sidebar.vue:446` vs `:548–552`).
19. **Folder and segment lifecycles use different components at every step** (§7) — including a legacy
    `woot-delete-modal` on one side and `Dialog` on the other.
20. **`ConversationFilter` has no mobile width branch** (`:108`) while `ContactsFilter` does (`:148`), and
    its footer cannot wrap (`:149`).

### Low

21. `SaveCustomView` is the only Options API file in `components-next/filter/`, receives a dead
    `v-model` (`ChatList.vue:907` vs `SaveCustomView.vue:19–33`), assigns an undeclared
    `this.alertMessage` (`:72`), and has a precedence bug in its error branch
    (`errorMessage || this.filterType === 0 ? … : …`, `:83–86`).
22. `DeleteCustomViews` tracks `this.filterType` (never a prop) in its analytics call (`:80`) and returns a
    success message in the `catch` branch (`:83–89`).
23. `starts_with` is defined with an icon and a label but offered by no provider (`operators.js:37, 59`).
24. `provider.js:215` types `display_id` as `inputType: 'number'`, outside its own documented union
    (`:36`).
25. `vFocus` is re-declared in all three filter inputs (`FilterSelect.vue:46`, `MultiSelect.vue:29`,
    `SingleSelect.vue:71`).
26. `maxVisibleFilters` is `2` by default (`ActiveFilterPreview.vue:8`) **and** hardcoded at the call site,
    where the "more" label does its own `length - 2` arithmetic
    (`ContactsActiveFiltersPreview.vue:77–82`).
27. `ActiveFilterPreview` prints the raw `queryOperator` string uppercase (`:94–98`) rather than the
    translated `FILTER.QUERY_DROPDOWN_LABELS` used in the panel (`ConditionRow.vue:80, 86`).
28. `ContactHeader` is `sticky top-0 z-20` while `CompanyHeader` and `CampaignLayout` are `z-10`
    (`ContactHeader.vue:43`, `CompanyHeader.vue:19`, `CampaignLayout.vue:25`).
29. `SearchFilters` renders its "Clear filter" button twice, swapped by `lg:hidden` / `hidden lg:inline-flex`
    (`:49–58, 93–102`).
30. `CONTACTS_FILTER.AUDIENCE.SHARED.USED_BY` interpolates both `{rules}` and `{campaigns}` even when one is
    zero (`ContactsFilter.vue:123–127`), unlike `ContactMoreActions.usageLabel`, which omits the empty half
    and pluralises (`:57–84`).
31. Two import spellings for the same Button (`next/button/Button.vue` vs
    `dashboard/components-next/button/Button.vue`) inside the same directory.

---

## 15. What a modernization must reuse rather than rebuild

| Reuse | Why |
| --- | --- |
| `ConditionRow.vue` | Five consumers already depend on its exact model contract (`attributeKey` / `filterOperator` / `values` / `queryOperator`) and its exposed `validate()` / `resetValidation()`. Replacing it breaks Contacts, Conversations, automation rules, flow Condition nodes and Captain audiences at once. |
| `operators.js` (`useOperators`) | The single i18n + icon + `hasInput` + `inputOverride` source. The automation layer enriches its own operators through it (`useConditionFilterTypes.js:42–57`). |
| `filterAttributeIcons.js` (`getAttributeIcon`, `groupFilterTypes`, the 38-key table) | Shared by both providers **and** the automation condition picker. The 5-group order and the `__group_<model>` + `disabled: true` header convention is the contract `FilterSelect` renders against. |
| `filterHelper.js` (`DROPDOWN_SEARCH_THRESHOLD`, `CONVERSATION_ATTRIBUTES`, `CONTACT_ATTRIBUTES`, `buildAttributesFilterTypes`, `getCustomAttributeInputType`) | The custom-attribute → filter-type bridge and the standard-attribute de-duplication rule. |
| `provider.js` / `contactProvider.js` / `audienceProvider.js` | Every option list, every operator set, every data source for 13 + 11 + 6 + 9+N attributes. The `FilterType` shape they emit is what `ConditionRow` and `FilterSelect` consume. |
| `audienceProvider.audienceValuesForEdit` + `COMMERCE_ORDER_KEY` | The only correct rehydration path for saved Lynomia audience conditions; `generateValuesForEditCustomViews` cannot handle them. |
| The four `inputs/*` components | They encode the chip-strip trigger, the async-search contract (`@search`, `is-searching`, `null` = aborted), the icon/emoji/colour option rendering and the VNode-stripping on toggle (`MultiSelect.vue:92–97`, `SingleSelect.vue:107–112`) that keeps `JSON.parse(JSON.stringify())` from throwing on circular icon refs. |
| `ActiveFilterPreview.vue` | The only chip row with a working value formatter (arrays / `{name}` / primitives) and overflow handling. Extend it (per-chip remove, i18n operators, count) and adopt it on Conversations instead of inventing a second chip. |
| `ContactMoreActions.vue` saved-view action set and its gating | Six audience actions plus the route-reachability check (`:43–53`) and the usage disclosure (`:57–97`). All of this is Lynomia-specific and has no OSS equivalent. |
| `CreateSegmentDialog.vue` | Already doubles as the duplicate dialog and the preset-save dialog via its `open({ name, shared, title })` API (`:60–66`). Folder creation should converge on this, not the other way round. |
| `TeleportWithDirection.vue` | The RTL fix for teleported panels. Any new popover layer must keep it or reimplement its `[dir]` wrapper. |
| `useFilter.initializeStatusAndAssigneeFilterToModal` / `initializeInboxTeamAndLabelFilterToModal` | The "pre-seed the panel from the current list scope" behaviour on Conversations (`ChatList.vue:492–513`). Users rely on opening the filter inside a label or team view and finding that condition already there. |
| `SIDEBAR_SORT_SECTIONS` + `sidebarSort.js` + `SidebarSortMenu` | The only sort implementation with stored per-section preferences and a sections-with-check-mark menu; the right model to converge the other four sort menus onto. |
| `AUDIENCE_QUERY_PARAM` / `audienceHelper` | The cross-module contract (`?audience=<id>`) that Contacts → Automation and Contacts → Campaigns both read (`ContactListHeaderWrapper.vue:249–259`, `WhatsAppCampaignsPage.vue:56–67`, `automation/Index.vue:152–154`). |
| The Histoire stories and fixtures (`fixtures/filterTypes.js`, 5 `*.story.vue`) | A ready harness for visual review of every input variant; keep them in step rather than letting them rot. |
