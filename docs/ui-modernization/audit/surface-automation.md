# Surface audit — Automation rules list and rule builder

Read-only audit. This document is the **baseline** for the feature-preservation contract of the
visual/interaction modernization phase. Every assertion is anchored to `file:line` in the current tree.
Nothing here proposes a redesign; it records what exists.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`.

Files in scope (paths relative to `app/javascript/dashboard/` unless stated):

| File | Lines | Role |
|---|---|---|
| `routes/dashboard/settings/automation/automation.routes.js` | 30 | Route definition, feature flag, permission gate |
| `routes/dashboard/settings/automation/Index.vue` | 459 | List page: header, tabs, search, count, table, empty state, banner, all dialogs |
| `routes/dashboard/settings/automation/AutomationRuleRow.vue` | 105 | One table row: name, delay badge, description, toggle, created-on, 3 icon actions |
| `routes/dashboard/settings/automation/AddAutomationRule.vue` | 110 | Create wrapper: start value, Lynomia manifest, audience prefill |
| `routes/dashboard/settings/automation/EditAutomationRule.vue` | 89 | Edit wrapper: hydration from the saved rule |
| `routes/dashboard/settings/automation/AutomationRuleForm.vue` | 385 | The builder side panel: name/description, run type, trigger, conditions, actions, footer, validation |
| `routes/dashboard/settings/automation/components/AutomationRunTypeSelector.vue` | 35 | Two radio cards: run instantly / run after a wait |
| `routes/dashboard/settings/automation/components/AutomationInstantTrigger.vue` | 155 | Event `<select>` with `<optgroup>`s + conditions group |
| `routes/dashboard/settings/automation/components/AutomationWaitCondition.vue` | 476 | Delayed-rule editor: trigger, status, duration, inbox, explanation, extra conditions |
| `routes/dashboard/settings/automation/components/AutomationActions.vue` | 93 | Actions group container |
| `routes/dashboard/settings/automation/constants.js` | 832 | `AUTOMATIONS` per-event conditions/actions, `AUTOMATION_RULE_EVENTS`, `AUTOMATION_ACTION_TYPES`, delay bounds, `DELAYED_TRIGGERS` |
| `routes/dashboard/settings/automation/operators.js` | 113 | `OPERATOR_TYPES_1..6` |
| `routes/dashboard/settings/automation/lynomiaAutomation.js` | 184 | Commerce triggers, Audience + Commerce condition groups, action suppression |
| `routes/dashboard/settings/automation/useConditionFilterTypes.js` | 86 | Maps automation condition definitions onto the filter `ConditionRow` contract |

Shared components read for this surface: `routes/dashboard/settings/SettingsWrapper.vue`,
`routes/dashboard/settings/SettingsLayout.vue`, `routes/dashboard/settings/components/BaseSettingsHeader.vue`,
`components-next/table/{BaseTable,BaseTableRow,BaseTableCell}.vue`, `components-next/tabbar/TabBar.vue`,
`components-next/side-panel/SidePanel.vue`, `components-next/switch/Switch.vue`,
`components-next/radioCard/RadioCard.vue`, `components-next/button/Button.vue`,
`components-next/input/{Input,DurationInput,constants}.vue|js`,
`components-next/filter/ConditionRow.vue`, `components-next/filter/inputs/{FilterSelect,MultiSelect,SingleSelect}.vue`,
`components-next/recipes/{RecipeDialog,RecipeInputs}.vue`,
`components/widgets/{AutomationActionInput,AutomationActionTeamMessageInput,AutomationFileInput}.vue`,
`components/widgets/forms/Input.vue`, `components/widgets/modal/{DeleteModal,ConfirmationModal}.vue`,
`components/widgets/LoadingState.vue`, `composables/{useAutomation,useAutomationValues,useEditableAutomation,useAccount}.js`,
`helper/{automationHelper,validations,audienceHelper}.js`, `store/modules/automations.js`,
`recipes/automationRecipes.js`, `i18n/locale/en/automation.json`, `i18n/locale/en/recipes.json`,
`assets/scss/_base.scss`.

---

## 1. Routes and the primary task

### 1.1 Routes

| Route | Name | Component | Gate |
|---|---|---|---|
| `/app/accounts/:accountId/settings/automation` | — | `SettingsWrapper` → redirect | redirects to `automation_list` (`automation.routes.js:13-18`) |
| `/app/accounts/:accountId/settings/automation/list` | `automation_list` | `Index.vue` | `featureFlag: FEATURE_FLAGS.AUTOMATIONS` (`'automations'`, `featureFlags.js:7`) **and** `permissions: ['administrator']` (`automation.routes.js:19-27`) |

There is **no** route for a single rule: create and edit both happen in a `SidePanel` rendered by
`Index.vue` (`Index.vue:425`, `Index.vue:448`). Consequence: a rule being edited is **not addressable by
URL** and survives no reload.

The one deep link into this surface is the audience query parameter:

- `?audience=<id>` on `automation_list` opens the create panel prefilled with that shared audience
  (`Index.vue:152-155`, `helper/audienceHelper.js:14-21`, `AddAutomationRule.vue:63-75`).
- It is produced by the contacts/audience header action "use in a new automation rule"
  (`components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue:250-254`).
- The query is deliberately **left in the URL** so the link stays shareable (`Index.vue:149-151`); the
  panel re-opens on reload because `SettingsWrapper` keys the page by `route.fullPath`
  (`SettingsWrapper.vue:16-18`).
- A non-shared or foreign id resolves to `undefined` and the panel opens blank — silently, with no notice
  (`audienceHelper.js:38-39`, `AddAutomationRule.vue:73-74`).

Sidebar entry: "Automation", icon `i-lucide-repeat`, under the settings group
(`components-next/sidebar/Sidebar.vue:799-803`).

### 1.2 Primary task

An administrator maintains the account's automation rules: scan the list, see at a glance which are on,
turn one on or off, clone, delete, and open the builder to create or change a rule made of
**one trigger + N conditions + N actions**, optionally **delayed** by a wait. The list is also the entry
point for recipes (ready-made rules created switched off).

### 1.3 Layout chain

```
SettingsWrapper.vue:22-33   (px-6 pt-4 pb-8, overflow-auto, max-w-5xl mx-auto, keep-alive keyed by fullPath)
  Index.vue → SettingsLayout.vue:22-41   (#header / #body / default slots, loading + noRecords states)
    #header → BaseSettingsHeader.vue     (title, description, help link, tabs slot, search, count, actions)
    #body   → banner | empty state | BaseTable → AutomationRuleRow
    default → AddAutomationRule, RecipeDialog, woot-delete-modal, EditAutomationRule, woot-confirm-modal
```

The builder is teleported to `<body>` by `SidePanel` (`SidePanel.vue:93`), width `3xl`
(`AutomationRuleForm.vue:295` → `max-w-3xl`, `SidePanel.vue:31-37`), and all dropdowns inside it are
teleported too via `provideDropdownTeleport()` (`AutomationRuleForm.vue:78`).

---

## 2. FEATURE PARITY MANIFEST

Every control, action, state and affordance on this surface. **This table is the baseline a later redesign
is checked against.** "Gate" is the permission, feature flag or condition that makes it appear.

### 2.1 Page scaffolding and header

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 1 | Settings page container (scroll, 24px gutter, `max-w-5xl` centred) | state | `SettingsWrapper.vue:22-25` | none |
| 2 | Page kept alive and keyed by full path (remount on a new `?audience=`) | state | `SettingsWrapper.vue:16-18, 27-29` | none |
| 3 | Page title "Automation" (`AUTOMATION.HEADER`, `text-heading-1`) | navigation | `Index.vue:333` → `BaseSettingsHeader.vue:51-60` | none |
| 4 | Page description paragraph (`AUTOMATION.DESCRIPTION`, clamped to 5 lines below `sm`) | state | `Index.vue:334` → `BaseSettingsHeader.vue:67-72` | none |
| 5 | "Learn more about automation" external help link + chevron | navigation | `Index.vue:335` → `BaseSettingsHeader.vue:73-87`, URL from `getHelpUrlForFeature('automation')` | hidden below `sm`; hidden entirely on a custom-branded instance (`CustomBrandPolicyWrapper`) |
| 6 | Search box, placeholder `AUTOMATION.SEARCH_PLACEHOLDER`, magnifier prefix, `type="search"` | filter | `Index.vue:332, 336` → `BaseSettingsHeader.vue:103-117` | `hidden sm:flex` — **not available below `sm`** |
| 7 | Fuzzy search over `name` + `description` via `picoSearch` | filter | `Index.vue:47-51` | none |
| 8 | Tab bar "Runs instantly" / "Runs after a wait" with per-tab counts and sliding indicator | tab | `Index.vue:339-345`, tabs built `Index.vue:80-91`, component `TabBar.vue:71-105` | `showTabs` = `delayed_automations` enabled **or** at least one existing delayed rule (`Index.vue:72-76`) |
| 9 | Record count pill `AUTOMATION.COUNT` (pluralised) | status | `Index.vue:346-350` | only when `visibleRecords.length` |
| 10 | Vertical divider between count and actions | state | `BaseSettingsHeader.vue:124-127` | count **and** actions slots both filled |
| 11 | "Recipes" button (`size=sm`, `color=slate`, `variant=faded`) | secondary | `Index.vue:353-360`, `data-test-id="automation-recipes-button"` | none |
| 12 | "Create Automation" button (`size=sm`, default solid blue) | primary | `Index.vue:361-365` | none |

### 2.2 List body states

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 13 | Loading state: centred spinner + "Fetching automation rules" | state (loading) | `Index.vue:327-328` → `SettingsLayout.vue:28-30` → `LoadingState.vue:9-19` | `uiFlags.isFetching` (`store/modules/automations.js:27, 34`) |
| 14 | Amber banner: delayed execution turned off but delayed rules exist | status | `Index.vue:371-376` (`bg-n-amber-3 text-n-amber-12`), condition `Index.vue:143-147` | `!delayed_automations` **and** some rule has `execution_delay` |
| 15 | First-run empty state: title `AUTOMATION.LIST.404`, hint `AUTOMATION.LIST.EMPTY_HINT`, two buttons | state (empty) | `Index.vue:377-403`, `data-test-id="automation-empty-state"` | `!records.length` (account has no rules at all) |
| 16 | Empty-state "Recipes" button (solid blue — **primary** here) | primary | `Index.vue:389-394`, `data-test-id="automation-empty-recipes"` | same as 15 |
| 17 | Empty-state "Create Automation" button (faded slate — **secondary** here) | secondary | `Index.vue:395-401` | same as 15 |
| 18 | In-table no-data row, `colspan` = header count, 80px vertical padding | state (empty) | `Index.vue:408` → `BaseTable.vue:49-56` | `records.length` but `visibleRecords` empty |
| 19 | No-data copy "No automation rules found matching your search" | state (empty) | `Index.vue:104-105` (`AUTOMATION.NO_RESULTS`) | `searchQuery` non-empty |
| 20 | No-data copy "No rules run after a wait yet" | state (empty) | `Index.vue:106-108` (`AUTOMATION.LIST.404_DELAYED`) | delayed tab active, no search |
| 21 | No-data copy "No automation rules found" | state (empty) | `Index.vue:108` (`AUTOMATION.LIST.404`) | instant tab / no tabs, no search |
| 22 | Table header row (`Name`, `Active`, `Created on`, `Actions`), hidden when no rows | table | `Index.vue:315-322, 406` → `BaseTable.vue:32-44` | `items.length > 0` (`BaseTable.vue:24-26`) |
| 23 | Row divider lines (`divide-y divide-n-weak`) | state | `BaseTable.vue:31, 45` | none |

### 2.3 Row-level controls (`AutomationRuleRow.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 24 | Rule name, truncated, `text-n-slate-12` | state | `AutomationRuleRow.vue:44-46` | none |
| 25 | Delay badge "Runs after 4h" (`AUTOMATION.LIST.DELAY_BADGE` + `formatDelay`) | status | `AutomationRuleRow.vue:47-56`, formatter `helper/automationHelper.js:265-269` | `automation.execution_delay` truthy |
| 26 | 1px vertical separator between name and description | state | `AutomationRuleRow.vue:57` | none |
| 27 | Rule description, truncated, `text-n-slate-11` | state | `AutomationRuleRow.vue:58-60` | none |
| 28 | Active toggle switch (`role="switch"`, `aria-checked`) | primary | `AutomationRuleRow.vue:64-66`, computed `:26-36`, component `Switch.vue:20-41` | none |
| 29 | Created-on date `LLL d, yyyy` | state | `AutomationRuleRow.vue:68-72`, `readableDate :22` | none |
| 30 | Native `title` tooltip with date **and time** on the created-on cell | contextual | `AutomationRuleRow.vue:68`, `readableDateWithTime :23-24` | none |
| 31 | Edit icon button (`i-woot-edit-pen`) with hover tooltip `AUTOMATION.FORM.EDIT` | secondary | `AutomationRuleRow.vue:76-83` | none |
| 32 | Clone icon button (`i-woot-clone`) with hover tooltip `AUTOMATION.CLONE.TOOLTIP` | secondary | `AutomationRuleRow.vue:84-91` | none |
| 33 | Delete icon button (`i-woot-bin`) with hover tooltip `AUTOMATION.FORM.DELETE`, ruby hover tint | destructive | `AutomationRuleRow.vue:92-100` | none |
| 34 | Per-row spinner on the three icon buttons while a row operation runs | state (loading) | `AutomationRuleRow.vue:81, 89, 95`; flag set `Index.vue:243`, cleared `:239, :255` | `loading[automation.id]` — set **only** by delete (see §3.9) |
| 35 | Actions cell right-aligned | state | `AutomationRuleRow.vue:74-75` (`align="end"`) | none |

### 2.4 List-level flows

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 36 | Toggle confirmation dialog, title switches activate/deactivate | contextual | `Index.vue:279-297, 453-457` → `ConfirmationModal.vue:55-64` | always on toggle |
| 37 | Toggle dialog description names the rule (`{automationName}`) | state | `Index.vue:283-287, 292-296` | always |
| 38 | Toggle success toast (activated / deactivated) | status | `Index.vue:305-308` | confirmation accepted |
| 39 | Toggle failure toast — reuses `AUTOMATION.EDIT.API.ERROR_MESSAGE` | state (error) | `Index.vue:310-312` | dispatch throws |
| 40 | Delete confirmation modal with rule name in the body and in **both** button labels | destructive | `Index.vue:437-446`, labels `:115-123` → `DeleteModal.vue:18-29` | opened from row delete |
| 41 | Delete modal title borrowed from the Labels module (`LABEL_MGMT.DELETE.CONFIRM.TITLE`) | state | `Index.vue:441` | — |
| 42 | Delete success / failure toasts | status | `Index.vue:235, 237` | — |
| 43 | Clone success / failure toasts, then a full list refetch | status | `Index.vue:250-253` | — |
| 44 | Create success / failure toasts; server error message preferred over the generic one | status | `Index.vue:264-266, 272-276` | — |
| 45 | Update success / failure toasts | status | `Index.vue:264-266, 272-276` | `mode === 'edit'` |
| 46 | Panel closes on a successful save (both add and edit refs closed) | state | `Index.vue:269-270` | save resolved |
| 47 | Panel **stays open** on a failed save | state | `Index.vue:271-277` (no close in catch) | save rejected |
| 48 | On mount, prefetch inboxes, agents, contacts, teams, labels, campaigns, automations | state (loading) | `Index.vue:157-166` | none |
| 49 | SLA options fetched when the `sla` feature flag arrives (watcher, `immediate`) | state | `Index.vue:125-141` | `sla` enabled on account |
| 50 | Edit waits for account UI flags and the SLA fetch before opening | state (loading) | `Index.vue:180-188` (`until(...).toBe(false)`) | `sla` enabled |
| 51 | New rule opened from the delayed tab starts as a wait rule (240 min) | state | `Index.vue:168-174`, `DEFAULT_DELAY_MINUTES` `constants.js:810` | `delayed_automations` **and** delayed tab active |
| 52 | Create panel opened on a shared audience from `?audience=` | contextual | `Index.vue:152-155, 165`, `AddAutomationRule.vue:63-75` | valid shared audience id |

### 2.5 Recipes dialog (`RecipeDialog.vue` + `automationRecipes.js`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 53 | Recipe dialog, width `2xl`, `overflow-y-auto`, title/description swap when a recipe is chosen | navigation | `Index.vue:427-435`, `RecipeDialog.vue:110-120` | opened from 11 or 16 |
| 54 | Recipe list: name, description (`dir="auto"`), per-recipe "Use this" button | primary | `RecipeDialog.vue:121-155`, `data-test-id="recipe-<id>"`, `-use` | — |
| 55 | Unavailable recipe shows "Needs {what} first" in amber and **no** Use button | state | `RecipeDialog.vue:136-143, 144` | `recipe.status !== AVAILABLE` |
| 56 | "Start from scratch instead" link → closes dialog, opens blank builder | secondary | `RecipeDialog.vue:156-164`, handler `Index.vue:195-198` | — |
| 57 | Step 2 inputs form, per-type controls (select / tag multiselect / number / url) | primary | `RecipeInputs.vue:85-137` | recipe has inputs |
| 58 | "Nothing to choose — this one is ready to create." | state (empty) | `RecipeDialog.vue:175-177` | recipe has no inputs |
| 59 | "Choose a different one" back link | navigation | `RecipeDialog.vue:178-186`, `data-test-id="recipe-back"` | a recipe is selected |
| 60 | Required / range / URL validation per input with inline messages | state (error) | `RecipeDialog.vue:61-97`, rendered `RecipeInputs.vue:106, 114, 124-125, 133-134` | — |
| 61 | Create button with loading spinner and disabled-while-creating | primary | `RecipeDialog.vue:199-207`, `Index.vue:432` (`isCreatingFromRecipe`) | a recipe is selected |
| 62 | Cancel button (full-width, faded slate) | secondary | `RecipeDialog.vue:191-198` | — |
| 63 | Recipe-created rule is `active: false` and named + described with provenance ("Created from the X recipe (v1).") | state | `automationRecipes.js:51-57`, `Index.vue:206-213` | — |
| 64 | After a recipe create, the new rule's edit panel opens for review | contextual | `Index.vue:216` | create returned a record |
| 65 | Recipe create toast success / failure; dialog kept open on failure | status | `Index.vue:215, 218`, comment `:104-105` of `RecipeDialog.vue` | — |
| 66 | 7 automation recipes: new-order routing, shipped label, refund escalation, event webhook, audience priority, high-value spend routing, active-order routing | primary | `automationRecipes.js:72-211` | each has its own `requires` (Commerce, store, team, label, webhooks, shared audience, currency) |

### 2.6 Builder: identity and run type (`AutomationRuleForm.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 67 | Side panel, `3xl`, slide-in from the inline end, dimmed overlay | navigation | `AutomationRuleForm.vue:295`, `SidePanel.vue:92-124` | — |
| 68 | Panel title "Add Automation Rule" / "Edit Automation Rule" | state | `AutomationRuleForm.vue:181-183` | `mode` |
| 69 | Close "X" button with `aria-label` from `GENERAL.CLOSE` | secondary | `SidePanel.vue:141-148` | — |
| 70 | **Escape closes the panel** (deferred to any open `<dialog>`) | shortcut | `SidePanel.vue:76-83` | no `dialog[open]` present |
| 71 | **Click on the overlay closes the panel** | secondary | `SidePanel.vue:72-74, 100-105` | `closeOnClickOutside` default true |
| 72 | Body scroll locked while the panel is open; focus moved into the panel, restored on close | state | `SidePanel.vue:41, 47-70` | — |
| 73 | `role="dialog"`, `aria-modal="true"`, `aria-label` = panel title | state | `SidePanel.vue:117-121` | — |
| 74 | Rule Name field + required error "Name is required" | primary | `AutomationRuleForm.vue:298-305`; validation `helper/validations.js:78-91` | — |
| 75 | Description field + required error "Description is required" | primary | `AutomationRuleForm.vue:306-315` | — |
| 76 | Run-type radio cards: "Run instantly" / "Run after a wait", each with a description | primary | `AutomationRuleForm.vue:317-320` → `AutomationRunTypeSelector.vue:16-34`, `RadioCard.vue:55-91` | `delayed_automations` on the account (`AutomationRuleForm.vue:87-89`) |
| 77 | Run-type cards stack on mobile, 2-up from `sm` | mobile | `AutomationRunTypeSelector.vue:21` | — |
| 78 | Trigger + condition draft kept per run type, restored when switching back | state | `AutomationRuleForm.vue:91-98, 119-133, 155-172` | — |
| 79 | Wait section remounted on each `open()` via a bumped key | state | `AutomationRuleForm.vue:100-101, 147, 323` | — |
| 80 | Delay reflected into `automation.execution_delay`; param deleted from the payload when the feature is off | state | `AutomationRuleForm.vue:174-179, 286` | — |
| 81 | Footer: Cancel (faded slate) + Create/Update (solid blue), right-aligned | primary | `AutomationRuleForm.vue:366-383`, labels `:184-191` | — |
| 82 | Errors cleared as soon as any part of the rule changes (deep watcher) | state | `AutomationRuleForm.vue:233-241` | some error present |
| 83 | Validation reset on open and on close | state | `AutomationRuleForm.vue:247-251, 266, 272` | — |

### 2.7 Builder: instant trigger and conditions (`AutomationInstantTrigger.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 84 | Event picker — native `<select>` inside its `<label>` | primary | `AutomationInstantTrigger.vue:75-95` | shown when **not** delayed (`AutomationRuleForm.vue:336-337`) |
| 85 | Events grouped into `<optgroup>`s by `group` label | state | `AutomationInstantTrigger.vue:44-51, 78-90` | — |
| 86 | 5 conversation events: Conversation Created / Updated / Resolved / Opened, Message Created, under group "Conversations" | primary | `constants.js:689-711`, grouped `AutomationRuleForm.vue:201-208` | — |
| 87 | 7 Commerce events: order created / updated / paid / shipped / delivered / cancelled / refunded, under group "Commerce" | primary | `lynomiaAutomation.js:13-21, 62-70` | `lynomia_commerce` enabled |
| 88 | Event error message "Event is required" + `.error` tint on the label | state (error) | `AutomationInstantTrigger.vue:75, 92-94` | `errors.event_name` |
| 89 | Commerce trigger note (what fires it, and that customer messages are unavailable) | contextual | `AutomationRuleForm.vue:345-349` → `AutomationInstantTrigger.vue:96-102`, `data-test-id="commerce-trigger-note"` | event is a Commerce event (`lynomiaAutomation.js:26`) |
| 90 | Reset warning "Changing event type will reset the conditions and events you have added below" | status | `AutomationInstantTrigger.vue:103-105`, gate `AutomationRuleForm.vue:344` + `:212-217` | create mode **and** first condition has a value or first action has params |
| 91 | Changing the event **wipes** all conditions and actions back to defaults | destructive | `composables/useAutomation.js:51-54` (`onEventChange`) | on `@change` of the event select |
| 92 | Conditions group box with "Conditions" label, rounded outline | state | `AutomationInstantTrigger.vue:107-118` | — |
| 93 | Conditions box turns ruby (outline + 50% ruby tint) when any `condition_N` error exists | state (error) | `AutomationInstantTrigger.vue:56-58, 113-117` | — |
| 94 | First condition row renders **without** an AND/OR selector | state | `AutomationInstantTrigger.vue:120-129` | `i === 0` |
| 95 | Subsequent rows render an AND/OR selector bound to the **previous** row's `query_operator` | primary | `AutomationInstantTrigger.vue:130-140` | `i > 0` |
| 96 | "Add Condition" button (`i-lucide-plus`, blue faded, `sm`) | primary | `AutomationInstantTrigger.vue:142-151` | — |
| 97 | New condition appended with the event's default condition | primary | `useAutomation.js:59-65`, defaults `helper/automationHelper.js:223-234` | — |
| 98 | Each condition row: attribute picker, operator picker, value input, trash button | primary | `ConditionRow.vue:193-275` | — |
| 99 | Attribute picker searchable once > 8 options; group headers dropped while searching | filter | `FilterSelect.vue:52-63`, threshold `components-next/filter/helper/filterHelper.js:5` | — |
| 100 | Non-selectable group header rows inside the attribute picker | state | `FilterSelect.vue:131-137`, produced `useConditionFilterTypes.js:65-67` | attribute has `disabled: true` |
| 101 | Per-attribute operator list from `OPERATOR_TYPES_1..6` (equal/not equal, contains, present, greater/less, days before, starts with) | primary | `operators.js:1-113` (`OPERATOR_TYPES_1` line 1, `_2` 12, `_3` 31, `_4` 50, `_5` 77, `_6` 92), applied `constants.js` per condition |
| 102 | Operator icons and labels from the shared filter operator registry | state | `useConditionFilterTypes.js:42-57` | — |
| 103 | Value input switches by type: multi-select, single select, async search select, boolean select, multi-text, plain/number/date input | primary | `ConditionRow.vue:221-265` | `currentOperator.hasInput` |
| 104 | Operators with no input (`is_present`, `is_not_present`) hide the value control | state | `ConditionRow.vue:214-221`, `validations.js:50-52` | — |
| 105 | Changing a condition's attribute resets its value to the right empty shape and re-picks the operator | state | `ConditionRow.vue:142-165` | — |
| 106 | Per-row inline validation message (`FILTER.ERRORS.*`) + `animate-wiggle` shake | state (error) | `ConditionRow.vue:171-180, 186-189, 277-279` | `validate()` called on save |
| 107 | Trash button removes the condition | destructive | `ConditionRow.vue:267-274` → `removeFilter(i)` | — |
| 108 | Removing the **last** condition is refused with a toast "You need to have atleast one condition to save" | state (error) | `useAutomation.js:79-87` | `conditions.length <= 1` |
| 109 | Custom-attribute condition groups ("Conversation Custom Attributes", "Contact Custom Attributes") appended per event | primary | `useAutomation.js:142-186`, headers `helper/automationHelper.js:275-306` | account has such attributes; only for the 4 conversation/message events |
| 110 | `custom_attribute_type` resynced from the picked attribute right before save | state | `AutomationRuleForm.vue:253-263, 277` | — |

### 2.8 Builder: Lynomia Audience and Commerce condition groups (`lynomiaAutomation.js`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 111 | "Audience" non-selectable group header inside the attribute picker | state | `lynomiaAutomation.js:92-95, 72-78` | always (every trigger) |
| 112 | "Contact audience" condition, multi-select of **shared** audiences only | primary | `lynomiaAutomation.js:96-105`, options `:166`, filter `:45-49` | always |
| 113 | Audience operators relabelled "Is in" / "Is not in" | state | `lynomiaAutomation.js:99-103`, applied `useConditionFilterTypes.js:42-49` | always |
| 114 | "Commerce" non-selectable group header | state | `lynomiaAutomation.js:109-111` | `lynomia_commerce` |
| 115 | "Order store" + "Order store platform" conditions | primary | `lynomiaAutomation.js:112-127`, options `:167-170` | `lynomia_commerce` **and** the trigger is a Commerce event |
| 116 | Every Commerce contact field appended as a condition (store, provider, orders count, spend per currency, last purchase, active order, order/payment/shipment status) | primary | `lynomiaAutomation.js:128-137`, source `components-next/filter/audienceProvider.js:141-225` | `lynomia_commerce` |
| 117 | Commerce triggers borrow the `conversation_updated` condition set (their rules act on the contact's latest conversation) | state | `lynomiaAutomation.js:146-154` | `lynomia_commerce` |
| 118 | Shared audiences + Commerce options loaded asynchronously; the groups are re-manifested when they land | state (loading) | `AddAutomationRule.vue:65-70`, `EditAutomationRule.vue:54-58`, `lynomiaAutomation.js:56-60` | — |
| 119 | "Send a Message" and "Send Attachment" **removed** from the action list on Commerce triggers | state | `AutomationRuleForm.vue:224`, rule `lynomiaAutomation.js:24, 173-174` | event is a Commerce event |

### 2.9 Builder: delayed rules / wait condition (`AutomationWaitCondition.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 120 | "Wait condition" section box with rounded outline | state | `AutomationWaitCondition.vue:378-389` | `isDelayed` (`AutomationRuleForm.vue:321-322`) |
| 121 | "When" trigger picker: "Conversation stays in a status" / "Customer hasn't replied" / "No teammate has replied" | primary | `AutomationWaitCondition.vue:392-397`, `triggerOptions :88-93`, source `constants.js:815-831` | — |
| 122 | Each trigger maps to an `event_name` + a preset condition (`message_type` outgoing/incoming, or `status`) | state | `constants.js:815-831`, applied `AutomationWaitCondition.vue:268-311` | — |
| 123 | "Status is" picker, shown only for the status trigger; statuses minus "all" | primary | `AutomationWaitCondition.vue:398-403`, options `AutomationRuleForm.vue:107-111` | `selectedTrigger === 'conversation_status'` |
| 124 | "For" duration: number input + unit select (minutes / hours / days) | primary | `AutomationWaitCondition.vue:404-416` → `DurationInput.vue:71-96` | — |
| 125 | Unit auto-chosen on open to the largest whole unit (240 min → 4 hours) | state | `AutomationRuleForm.vue:135-147` | — |
| 126 | Minimum clamped to the larger of 10 minutes and one whole unit | state | `AutomationWaitCondition.vue:101-105`, `MIN_DELAY_MINUTES` `constants.js:811` | — |
| 127 | Maximum 43 200 minutes (30 days) | state | `AutomationWaitCondition.vue:413`, `constants.js:812` | — |
| 128 | Value clamped on blur and on Enter; rounded to the nearest whole unit when the unit changes | state | `DurationInput.vue:53-68, 80-81` | — |
| 129 | "Inbox" multi-select; empty means every inbox | primary | `AutomationWaitCondition.vue:417-422`, comment `:55-56` | — |
| 130 | Info aside: plain-language explanation of the chosen trigger, interpolating the duration in the chosen unit | contextual | `AutomationWaitCondition.vue:424-434`, `explanation :117-122`, `durationLabel :108-115` | — |
| 131 | Info aside footnote: only new activity starts a clock | contextual | `AutomationWaitCondition.vue:430-432` | — |
| 132 | Saved wait hydrated back into trigger / status / inboxes from its conditions | state | `AutomationWaitCondition.vue:126-160, 352` | `isSavedWait` |
| 133 | A rule not saved as a wait has its instant conditions discarded on mount | destructive | `AutomationWaitCondition.vue:354-359` | `!isSavedWait` |
| 134 | Private-note `false` condition auto-added for the "customer hasn't replied" trigger | state | `AutomationWaitCondition.vue:230-245, 292-296` | `messageType === 'outgoing'` |
| 135 | Additional free conditions below a divider, each preceded by its AND/OR connector as a **read-only chip** | state | `AutomationWaitCondition.vue:436-460`, `connectorLabel :177-180` | at least one additional condition |
| 136 | Additional-condition attribute list excludes the wait-managed keys | filter | `AutomationWaitCondition.vue:63-77` | — |
| 137 | Status waits allow **no** additional conditions at all (list empty → Add button hidden) | state | `AutomationWaitCondition.vue:71-72, 461` | `isStatusTrigger` |
| 138 | "Add Condition" in the wait section, defaulting to `status` or the first selectable filter | primary | `AutomationWaitCondition.vue:313-340, 461-470` | `additionalFilterTypes.length` |
| 139 | Additional conditions preserved across message-wait trigger changes, dropped when switching to a status wait | state | `AutomationWaitCondition.vue:268-311, 361-372` | — |
| 140 | Existing OR connectors preserved; new conditions joined with AND | state | `AutomationWaitCondition.vue:170-180, 305-309, 322-328` | — |
| 141 | Wait box turns ruby and shows "The wait must be between 10 minutes and 30 days" | state (error) | `AutomationWaitCondition.vue:384-388, 472-474`, flag `AutomationRuleForm.vue:103-105, 280-282` | delay is not a finite number |
| 142 | Wait rows stack on mobile; the info aside drops below the controls | mobile | `AutomationWaitCondition.vue:390, 425` (`md:grid-cols-[minmax(0,1fr)_20rem]`, `md:self-start`) | — |

### 2.10 Builder: actions (`AutomationActions.vue` + `AutomationActionInput.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 143 | Actions group box with "Actions" label, rounded outline | state | `AutomationActions.vue:53-64` | — |
| 144 | Actions box turns ruby when any `action_N` error exists | state (error) | `AutomationActions.vue:47-49, 59-63` | — |
| 145 | Action picker — `SingleSelect` with leading per-action icon, deselect disabled | primary | `AutomationActionInput.vue:151-158`, icons `helper/automationHelper.js:88-118` | — |
| 146 | 19 action types: assign agent / team, remove assigned agent / team, add / remove label, email to team, email transcript, mute, snooze, resolve, open, pending, webhook, attachment, message, private note, change priority, add SLA | primary | `constants.js:712-809` | — |
| 147 | "Add SLA" hidden unless the `sla` feature is on | state | `AutomationRuleForm.vue:220-223` | `sla` enabled |
| 148 | "Assign to Agent" list prefixed with "None" and "Last Responding Agent" | state | `useAutomationValues.js:124-133`, `addNoneToList :85-91` | action is `assign_agent` |
| 149 | Changing the action **resets its parameters** | destructive | `AutomationActionInput.vue:123-126`, `useAutomation.js:127-135` | — |
| 150 | Action input by type: single select, multi select, URL input, file upload, email input, team+message, rich-text editor | primary | `AutomationActionInput.vue:159-225` | `showActionInput` (`helper/automationHelper.js:397-401`) |
| 151 | Email transcript input + "Use contact's email" button inserting `{{contact.email}}` once | secondary | `AutomationActionInput.vue:195-211`, logic `:127-139` | `inputType === 'email'` |
| 152 | Team email action: team multi-select + plain textarea | primary | `AutomationActionTeamMessageInput.vue:36-51` | `inputType === 'team_message'` |
| 153 | Message / private-note action: rich editor with variables enabled, menubar hidden, 4 rows | primary | `AutomationActionInput.vue:218-225` | `inputType === 'textarea'` |
| 154 | Attachment upload with 4 visual states (idle / uploading / uploaded / failed) + icons | primary | `AutomationFileInput.vue:50-75`, labels `i18n automation.json:163-169` | `inputType === 'attachment'` |
| 155 | Attachment upload failure toast | state (error) | `AutomationFileInput.vue:40-44` | upload throws |
| 156 | Saved attachment's filename shown when editing | state | `AutomationActions.vue:77`, resolver `helper/automationHelper.js:213-221` | `mode === 'edit'` |
| 157 | Trash button removes the action | destructive | `AutomationActionInput.vue:185-193` | `!isMacro` |
| 158 | Removing the **last** action is refused with a toast "You need to have atleast one action to save" | state (error) | `useAutomation.js:93-101` | `actions.length <= 1` |
| 159 | "Add Action" button (`i-lucide-plus`, blue faded, `sm`) | primary | `AutomationActions.vue:81-90` | — |
| 160 | Per-action inline error from `AUTOMATION.ERRORS.*` + `animate-wiggle` shake | state (error) | `AutomationActions.vue:72-76`, render `AutomationActionInput.vue:148, 227-229` | `errors.action_N` |
| 161 | "Action parameters are required" for any action outside the 7 no-param actions | state (error) | `helper/validations.js:123-141` | — |

### 2.11 Cross-module links and gating summary

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 162 | Inbound: audience → "use in a new automation rule" | navigation | `ContactListHeaderWrapper.vue:249-253` → `Index.vue:152-155` | shared audience selected |
| 163 | Outbound: help-centre article on automation | navigation | `BaseSettingsHeader.vue:74-86` | not a custom-branded instance; `sm` and up |
| 164 | Whole surface requires the `administrator` role | state | `automation.routes.js:24` | — |
| 165 | Whole surface requires the `automations` feature flag | state | `automation.routes.js:23` | — |
| 166 | Delayed rules require the `delayed_automations` flag | state | `Index.vue:57-62`, `AutomationRuleForm.vue:87-89` | — |
| 167 | Commerce triggers and the Commerce condition group require `lynomia_commerce` | state | `lynomiaAutomation.js:42-44` | — |
| 168 | SLA action requires `sla` | state | `AutomationRuleForm.vue:220-223` | — |

**Keyboard shortcuts on this surface:** exactly one — `Escape` closes the builder panel
(`SidePanel.vue:76-83`). There is no row-level keyboard navigation, no shortcut for create, search, delete
or tab switching, and no shortcut-help entry for the surface.

**Bulk actions on this surface:** none. There is no row selection, no select-all, no bulk enable /
disable / delete. Every operation is single-record. This is a true gap, not an omission in this audit.

**Mobile-specific affordances:** none added. Three things are *removed* below `sm` (search, help link,
see §3.11) and nothing replaces them.

---

## 3. Visual audit

### 3.1 Hierarchy

**3.1.1 The same two actions carry inverted visual priority in the header and the empty state.** In the
header, "Recipes" is `color=slate variant=faded` and "Create Automation" is the default solid blue
(`Index.vue:353-365`). In the empty state the pair is swapped: "Recipes" is solid blue (primary) and
"Create Automation" is faded slate (`Index.vue:389-401`). A user who learns the header's hierarchy meets
the opposite one the first time they see the page. Severity: medium.

**3.1.2 Three section labels are rendered as `<label>` elements with no control.** "Conditions"
(`AutomationInstantTrigger.vue:108-110`), "Actions" (`AutomationActions.vue:54-56`), "Wait condition"
(`AutomationWaitCondition.vue:379-381`) and "When should this rule run?"
(`AutomationRunTypeSelector.vue:18-20`) are all `<label>`s used as headings. They inherit the global form
label styling rather than any heading scale, so the builder's five sections (identity, run type, trigger,
conditions, actions) all read at the same visual weight as a field label. The panel has no visual
step/section structure above the field level. Severity: medium.

**3.1.3 The rule's name and its description sit at the same size in the row, separated only by a 1px
tick.** `AutomationRuleRow.vue:44-60` renders both with `text-body-main`, differing only in colour
(`text-n-slate-12` vs `text-n-slate-11`), both `truncate`, inside a single `max-w-0 w-full` cell. With two
long strings, the name and the description each get roughly half the available width and both get cut, so
the primary identifier of the row can be truncated to make room for secondary text. Severity: high.

**3.1.4 The Commerce trigger note and the event-reset warning compete in the same place with different
treatments.** The note is left-aligned `text-label-small text-n-slate-11`
(`AutomationInstantTrigger.vue:96-102`); the reset warning is right-aligned `text-xs text-n-teal-10`
(`:138-140`). Two advisory messages immediately below one control, in two alignments, two sizes and two
colours — and teal is used nowhere else on this surface. Severity: medium.

### 3.2 Density

**3.2.1 The builder stacks five sections at a flat `gap-6` with no internal rhythm.**
`AutomationRuleForm.vue:296` is `flex flex-col w-full gap-6`; name and description are glued together in a
nested `flex flex-col` with **no** gap (`:297`), relying entirely on the legacy input's own margins from
`_base.scss`. So the two text fields are tighter than everything else by accident rather than by design.
Severity: low.

**3.2.2 A long condition list is an undifferentiated vertical stack.** `AutomationInstantTrigger.vue:111-152`
renders every row at `gap-4` inside one box; there is no grouping, no numbering, no collapse and no scroll
container of its own. The panel's single scroll area is `SidePanel.vue:151`, so with eight conditions and
four actions the trigger, the conditions and the actions all scroll together and the user loses sight of
which event the conditions belong to. Severity: medium.

**3.2.3 Actions are padded differently from conditions.** The conditions `<ul>` uses `grid gap-4 p-3`
(`AutomationInstantTrigger.vue:77`); the actions `<ul>` uses `grid p-3` with **no** gap and relies on each
row's own `py-2 first:pt-0 last:pb-0` (`AutomationActions.vue:58`, `AutomationActionInput.vue:145`). Two
visually identical boxes, two unrelated spacing mechanisms. Severity: low.

### 3.3 Alignment

**3.3.1 The "Actions" column header is start-aligned while its cell content is end-aligned.**
`BaseTable.vue:37` applies `text-start` to every `<th>`; the actions cell is `align="end"`
(`AutomationRuleRow.vue:74`). The header word sits at the far left of a column whose three buttons sit at
the far right. Severity: medium.

**3.3.2 The wait section's four rows do not share a control width or a control height.** The labels are a
fixed `w-20` with `shrink-0` (`AutomationWaitCondition.vue:393, 399, 405, 418`). The controls next to them
are: a `FilterSelect` button sized to its label, another `FilterSelect`, a `w-64` box holding a **40px**
`DurationInput` plus a 40px native unit select, and a `MultiSelect` sized to its chips. Rows are
`min-h-8` (32px) but the "For" row is 40px tall, so the four-row stack has one row taller than the rest and
four different right edges. Severity: medium.

**3.3.3 The wait section's connector chip is left-aligned above a full-width condition row.**
`AutomationWaitCondition.vue:445-449` renders the AND/OR chip as a `self-start` `<li>` on its own line,
then the condition row below it — whereas in the instant editor the same connector is an inline
`FilterSelect` on the **same** line as the condition (`ConditionRow.vue:193-200`). The same logical
construct has two different geometries in one product. Severity: medium.

### 3.4 Spacing

**3.4.1 Spacing inside the builder comes from three unrelated systems.** Tailwind gaps on the wrappers,
legacy SCSS `margin-bottom` on the native inputs and selects (`_base.scss:83-93, 100-113`), and
`!important` overrides keyed off `:has()` (`_base.scss:132-134, 156-162`). The name/description pair, the
event select and the duration unit select are all spaced by the SCSS layer; everything else by Tailwind.
Severity: medium.

**3.4.2 The error message slot changes the layout.** `_base.scss:156-162` injects
`margin-bottom: 0.25rem !important` on inputs only when a sibling `.message` exists, so showing the
"Name is required" message shifts the description field down. The same is true for the event select.
Severity: low.

### 3.5 Inconsistent controls

**3.5.1 Two deprecated `woot-input` fields in an otherwise `components-next` panel.** Name and description
use `woot-input` (`AutomationRuleForm.vue:298-315`), which is explicitly marked
`@deprecated` and logs a console warning in dev (`components/widgets/forms/Input.vue:1-5, 42-49`). Its
height is 40px from `_base.scss:83-84`, its label is a bare `<span class="text-heading-3">`, and its error
is the global `.message` class — none of which match `components-next/input/Input.vue`. Severity: high.

**3.5.2 Three different select idioms in one panel.** The event picker is a **native `<select>`** with
`<optgroup>` (`AutomationInstantTrigger.vue:77-91`); the duration unit is a **native `<select>`**
(`DurationInput.vue:82-96`); every condition attribute, operator, value and action uses the
**design-system dropdowns** `FilterSelect` / `MultiSelect` / `SingleSelect`. The native selects are 40px
with the SCSS triangle background image (`_base.scss:100-113`); the dropdowns are 32px buttons with Lucide
icons, search and keyboard-free click interaction. Severity: high.

**3.5.3 Error text colour is not consistent.** `text-n-ruby-11` in `ConditionRow.vue:277` and
`AutomationActionInput.vue:227`; `text-n-ruby-9` in `AutomationWaitCondition.vue:472` and in the global
`.message` rule used by the name/description/event errors (`_base.scss:164-166`). Three error presentations
on one screen: inline ruby-11 text, inline ruby-9 text, and a container tint with no text at all (§3.6.2).
Severity: medium.

**3.5.4 Two unrelated plain textareas.** The team-email action uses a raw `<textarea>` styled by SCSS
(`AutomationActionTeamMessageInput.vue:44-50`, `_base.scss:116-122`), while the message / private-note
action uses the rich `WootMessageEditor` with its menubar hidden and hand-written outline classes
(`AutomationActionInput.vue:218-225`). Two "write a message" controls, two appearances. Severity: medium.

**3.5.5 The attachment input is the only control on the surface with scoped CSS.**
`AutomationFileInput.vue:77-97` is a `<style scoped>` block — dashed border, custom states, `fluent-icon`
glyphs — against this repo's Tailwind-only rule. It is also the only place `fluent-icon` appears on the
surface; everything else is Lucide/woot icon classes. Severity: medium.

**3.5.6 The row's icon buttons mix icon families.** `i-woot-edit-pen`, `i-woot-clone`, `i-woot-bin`
(`AutomationRuleRow.vue:78, 86, 96`) versus `i-lucide-trash` for removing a condition or action
(`ConditionRow.vue:271`, `AutomationActionInput.vue:190`). Two "delete" glyphs with different shapes.
Severity: low.

### 3.6 Duplicated and competing patterns

**3.6.1 Two editors for the same object.** `AutomationInstantTrigger.vue` and
`AutomationWaitCondition.vue` both edit `event_name` + `conditions`, with different mental models
(raw event vs. named trigger), different condition lists, different connector rendering and different
"Add Condition" defaults. Switching the run-type radio replaces one with the other in place
(`AutomationRuleForm.vue:321-353`), which is why the form has to keep two drafts
(`AutomationRuleForm.vue:91-98, 155-172`). Severity: medium (this is deliberate, but it is the largest
duplication on the surface and any redesign must preserve both).

**3.6.2 Conditions are validated twice, and reported in two mismatched ways.** `validateAutomation`
produces `condition_N` / `action_N` keys (`helper/validations.js:99-115, 145-162`), and each `ConditionRow`
separately runs `validateSingleFilter` through its own `validate()` (`ConditionRow.vue:97-106, 171-174`).
The former is rendered **only** as a container tint (`AutomationInstantTrigger.vue:56-58, 113-117`); the
latter as inline text. So a missing condition value produces a red box *and* a red line, from two code
paths. Meanwhile `errors.conditions` / `errors.actions`
(`ATLEAST_ONE_CONDITION_REQUIRED` / `ATLEAST_ONE_ACTION_REQUIRED`, `validations.js:103, 152`) have **no
renderer at all** — if they were ever produced, save would fail in silence. Severity: high.

**3.6.3 The empty state and the table's no-data row both print `AUTOMATION.LIST.404`.**
`Index.vue:382-384` and `Index.vue:108`. The two are mutually exclusive in practice (`!records.length` vs.
`records.length && !visibleRecords.length`), but the same sentence is styled two ways: `text-base
text-n-slate-12` centred in a `py-16` block, versus `text-body-main !text-base text-n-slate-11` in a
`py-20` table cell. Severity: low.

**3.6.4 Two confirmation dialog components for two destructive-ish operations.** Toggle uses
`woot-confirm-modal` (`ConfirmationModal.vue`, promise-based, `showConfirmation()`); delete uses
`woot-delete-modal` (`DeleteModal.vue`, prop-driven with `v-model:show`). Different button orders,
different label sources, different APIs (`Index.vue:437-446` vs `:453-457`). Severity: medium.

### 3.7 CTA clarity

**3.7.1 The submit button has no busy state, so the builder can be submitted twice.**
`AutomationRuleForm.vue:375-381` passes neither `:is-loading` nor `:disabled`, and the store's
`isCreating` / `isUpdating` flags (`store/modules/automations.js:38, 51`) are never read by the panel. A
slow create can be fired repeatedly. Severity: high.

**3.7.2 The clone button never shows that it is working.** `cloneAutomation` sets
`loading[selectedAutomation.value.id] = false` in its `finally`
(`Index.vue:247-257`) but never sets any flag to `true`, and `selectedAutomation` is not even set by the
clone path — so the `finally` clears an unrelated (or empty) id. The three row buttons stay idle through
the whole clone + refetch. Severity: high.

**3.7.3 The active toggle has no pending state.** `Index.vue:279-313` awaits the confirmation and then the
dispatch with no flag; `AutomationRuleRow.vue:64-66` renders the switch with no `disabled` and no spinner.
The switch stays in its old position for the whole round trip with no indication that anything is
happening, then jumps. Severity: medium.

**3.7.4 `is-loading` on the row buttons does not disable them.** `Button.vue:240-260` only styles
`disabled:opacity-50`; it never sets the attribute itself. `AutomationRuleRow.vue:76-100` passes
`:is-loading` without `:disabled`, so during a delete all three buttons show spinners and remain
clickable. Severity: high.

**3.7.5 Destructive confirmation buttons carry the record name, so they grow without bound.**
`Index.vue:115-121` builds `"Yes, Delete  {name}"` and `"No, Keep {name}"` (note the double space from
`AUTOMATION.DELETE.CONFIRM.YES` ending in a space, `automation.json:107`). A rule named
"Escalate refunded orders to the after-sales team" produces a ~50-character button label. `Button.vue:258`
truncates, so the confirm button can read "Yes, Delete  Escalate refunded orders to the after-sa…".
Severity: medium.

**3.7.6 The toggle dialog's buttons are hardcoded untranslated English.** `Index.vue:453-457` passes only
`title` and `description`; `ConfirmationModal.vue:19-26` defaults `confirmLabel` to the literal `'Yes'`
and `cancelLabel` to `'No'`. The translated keys **exist** — `AUTOMATION.TOGGLE.CONFIRMATION_LABEL` and
`CANCEL_LABEL` (`automation.json:160-161`) — and are never passed. In Arabic the enable/disable dialog
shows "Yes"/"No" in Latin script. Severity: high.

**3.7.7 The delete modal borrows the Labels module's title.** `Index.vue:441` uses
`LABEL_MGMT.DELETE.CONFIRM.TITLE` while `AUTOMATION.DELETE.CONFIRM.TITLE` exists with identical copy
(`automation.json:104-105`, `labelsMgmt.json:81-82`). Cross-module string coupling: a Labels copy change
silently changes the Automation dialog. Severity: low.

**3.7.8 Changing the event destroys the whole rule body with no confirmation.**
`useAutomation.js:51-54` replaces `conditions` and `actions` outright on `@change`
(`AutomationInstantTrigger.vue:77`). The only mitigation is an advisory line, in create mode only, shown
*before* the change in small teal right-aligned text (`AutomationInstantTrigger.vue:103-105`,
`AutomationRuleForm.vue:344`). In **edit** mode there is no warning at all and no undo. Severity: high.

**3.7.9 Switching the run type to "Run after a wait" silently discards the instant conditions on first
switch.** `AutomationWaitCondition.vue:354-359` calls `applyTrigger({ preserveAdditional: false })` on
mount for any rule that was not saved as a wait. The draft mechanism restores them if the user switches
back (`AutomationRuleForm.vue:155-172`), but nothing on screen says the conditions were replaced.
Severity: medium.

### 3.8 Overcrowded areas

**3.8.1 A condition row can hold six controls on one wrap-prone line.** `ConditionRow.vue:185-275`:
connector select, attribute select, operator select, value control, and the trash button — in
`flex flex-wrap gap-2`. In a `max-w-3xl` panel minus 48px of padding minus the `p-3` box, a multi-select
with three chips plus three label-bearing dropdowns exceeds the line and wraps mid-row, putting the trash
button on its own line under the attribute name. Severity: medium.

**3.8.2 The wait section packs four labelled rows, a 20rem info aside, a divider, N connector-chipped
condition rows and an Add button into one outlined box.**
`AutomationWaitCondition.vue:382-471`. On a `max-w-3xl` panel the two-column grid leaves roughly 24rem for
the controls column, which is where the mixed widths of §3.3.2 bite. Severity: medium.

**3.8.3 The header row can hold tabs, search, count, a divider and two buttons.**
`BaseSettingsHeader.vue:91-130` is `flex flex-wrap sm:flex-nowrap justify-between`. With tabs shown, the
left group is `TabBar` + a `w-56` search and the right group is the count + divider + two buttons. At
`sm`-to-`md` widths `sm:flex-nowrap` forbids wrapping, so `TabBar.vue:85` (`truncate`) starts truncating
the tab labels — "Runs after a wait (3)" becomes "Runs after a wa…". Severity: medium.

### 3.9 Table usability

**3.9.1 No horizontal scroll container.** `BaseTable.vue:30-31` is `<div class="w-full"><table
class="min-w-full table-auto">` — no `overflow-x-auto`. The only scroller is the whole settings page
(`SettingsWrapper.vue:23`), so a four-column table that cannot fit squeezes the name cell (which is
`max-w-0 w-full`, `AutomationRuleRow.vue:42`) until name and description are both a few characters, rather
than offering a scroll. Severity: high.

**3.9.2 No sorting, no column control, no pagination.** Rows are always ordered by ascending id
(`store/modules/automations.js:17-19`); the headers are plain `<th>` text with no affordance
(`BaseTable.vue:34-42`). There is no way to sort by name, by active state or by creation date, no way to
hide the description, and no pagination or virtualisation — every rule renders. Severity: medium.

**3.9.3 No row selection and no bulk actions.** Confirmed absent across `Index.vue` and
`AutomationRuleRow.vue`: no checkbox column, no `selected` state, no bulk bar. Turning off ten rules is ten
toggles and ten confirmation dialogs. Severity: medium.

**3.9.4 The row is not clickable and the whole row is not a link.** Editing requires hitting the 32px
pen button at the far end of the row (`AutomationRuleRow.vue:76-83`); `BaseTableRow.vue:11-13` renders a
plain `<tr>` with no click handler, no `cursor-pointer` and no hover state. There is also **no row hover
feedback at all** — `BaseTableRow` adds no `hover:` class — so nothing indicates the row is interactive.
Severity: medium.

**3.9.5 Only four columns for a rule's identity; the trigger and the action are not shown.** The table
shows name, active, created-on and actions (`Index.vue:315-322`). What the rule *does* — its event,
condition count and actions — is invisible until the panel is opened, and the free-text description is the
only hint. The delay badge (`AutomationRuleRow.vue:47-56`) is the single piece of rule mechanics surfaced
in the list. Severity: medium.

**3.9.6 Created-on detail is only reachable by hovering.** The date+time is a native `title`
(`AutomationRuleRow.vue:68`) — unavailable on touch, and unstyled. Severity: low.

### 3.10 Empty-state quality

**3.10.1 The first-run empty state is good** — title, hint explaining that recipes arrive switched off, and
two actions (`Index.vue:377-403`). It is the strongest empty state on the surface.

**3.10.2 Every other empty state is a bare sentence with no action.** The search-miss, the empty delayed
tab and the empty instant tab all render one centred line in a `py-20` table cell with no "clear search",
no "create one", no "switch tab" (`Index.vue:104-109` → `BaseTable.vue:49-56`). The delayed tab is the
sharpest case: a user who clicks "Runs after a wait" on an account with no delayed rules sees "No rules
run after a wait yet" and nothing else, even though the header's Create button would start one correctly
(`Index.vue:168-174`). Severity: medium.

**3.10.3 The table header disappears when there are no rows**, so the no-data message floats under nothing
(`BaseTable.vue:24-26, 32`). The user loses the column context that would explain what is missing.
Severity: low.

**3.10.4 A search miss does not say what was searched or offer to clear it.** `AUTOMATION.NO_RESULTS` is
"No automation rules found matching your search" with no echo of the query and no reset
(`automation.json:10`), while the shared dropdowns do interpolate the term
(`COMBOBOX.EMPTY_SEARCH_RESULTS`, `FilterSelect.vue:148`). Inconsistent within the same product.
Severity: low.

### 3.11 Mobile behaviour

**3.11.1 Search is removed below `sm`.** `BaseSettingsHeader.vue:107` puts `hidden sm:flex` on the search
input. On a phone there is no way to filter the rules; the only navigation is the tab bar and scrolling.
Severity: high.

**3.11.2 The help link is removed below `sm`.** `BaseSettingsHeader.vue:79` — `hidden ... sm:inline-flex`.
Severity: low.

**3.11.3 The 4-column table has no mobile treatment.** No card layout, no column hiding, no stacked rows;
see §3.9.1. The row's name cell plus three 32px buttons plus a date is ~200px of fixed content before the
name gets any width. Severity: high.

**3.11.4 The builder panel is usable but its internals are not adapted.** `SidePanel.vue:122` is
`w-[calc(100%-1.5rem)] max-w-3xl` so the panel itself fits. Inside, the run-type cards
(`AutomationRunTypeSelector.vue:21`) and the wait grid (`AutomationWaitCondition.vue:390`) do stack, but
the condition row (§3.8.1) just wraps, the wait section's fixed `w-20` label column and `w-64` duration box
do not shrink (`AutomationWaitCondition.vue:393, 408`), and the dropdown bodies are `min-w-56` / `min-w-48`
with `max-h-72` (`FilterSelect.vue:117, 130`, `MultiSelect.vue:163`) teleported to `<body>` — they can
exceed a 360px viewport. Severity: medium.

**3.11.5 Icon-only row actions are 32px targets.** `Button.vue:166` gives `sm` icon-only buttons
`h-8 w-8`, below the 44px touch-target guidance, with `gap-3` (12px) between three of them and a
destructive delete as the last one (`AutomationRuleRow.vue:75`). Severity: medium.

**3.11.6 Every tooltip on this surface is hover-only.** The row's three actions carry `v-tooltip.top`
(`AutomationRuleRow.vue:77, 85, 93`) and the created-on cell a native `title`. On touch, none of the four
is reachable and none of them has a visible text alternative, so a touch user meets three unlabelled icons.
Severity: high.

### 3.12 RTL behaviour

**3.12.1 The shared dropdown's search field is hardcoded LTR.** `FilterSelect.vue:122` positions the
magnifier with `left-2` and `:126` pads the input with `pl-8`. In Arabic the icon sits at the left while
the text starts from the right, and the 2rem of padding is on the wrong side — so the icon overlaps the end
of the typed query. `MultiSelect.vue:165, 169` gets this right with `start-2` / `ps-8`, which proves the
inconsistency is an oversight. This is the attribute, operator, connector **and** wait-trigger picker on
this surface. Severity: high.

**3.12.2 The event-reset warning is physically right-aligned.**
`AutomationInstantTrigger.vue:103` uses `text-right` instead of `text-end`, so in Arabic the message hugs
the far end of the line away from the text direction. It is the only non-logical directional utility inside
`routes/dashboard/settings/automation/`. Severity: medium.

**3.12.3 The side panel's slide direction is handled, the dropdown teleport relies on a wrapper.**
`SidePanel.vue:109-111` has explicit `rtl:` translate variants and `end-3`, and dropdowns are teleported
through `TeleportWithDirection` (`SidePanel.vue:93`). Those are correct; the risk is that
`provideDropdownTeleport()` (`AutomationRuleForm.vue:78`) moves menus to `<body>`, so any RTL bug in a
dropdown body (3.12.1) shows up detached from the panel's own direction context.

**3.12.4 Fixed-width label columns will not hold Arabic.** `AutomationWaitCondition.vue:393, 399, 405, 418`
use `w-20 shrink-0` (80px) with no `truncate`. Arabic "Status is" / "Inbox" are longer strings; they wrap
inside the 80px box and push the row taller, breaking the four-row alignment further (§3.3.2).
Severity: medium.

**3.12.5 The native `<select>` arrow and padding are RTL-handled by the SCSS layer only.**
`_base.scss:102-105` flips the background position and the padding with `ltr:`/`rtl:` variants. This works,
but it means the event picker's RTL correctness lives in a global stylesheet rather than in the component
— worth recording because the stylesheet is shared with every other native select in the app.

**3.12.6 Delay badge and formatted duration are Latin-suffixed.** `formatDelay`
(`helper/automationHelper.js:265-269`) returns `"4h"`, `"30m"`, `"2d"` — untranslated unit letters
interpolated into the Arabic `AUTOMATION.LIST.DELAY_BADGE` string (`AutomationRuleRow.vue:51-55`).
The wait section's own `durationLabel` does use pluralised i18n (`AutomationWaitCondition.vue:108-115`), so
the list and the builder describe the same delay in two different ways. Severity: medium.

### 3.13 Loading and error behaviour

**3.13.1 A failed list fetch is indistinguishable from an empty account.**
`store/modules/automations.js:31-33` swallows the error (`// Ignore error`) and leaves `records` as it was.
A 500 on `automations/get` therefore renders the first-run empty state — "No automation rules found" plus
"Start from a ready-made recipe" — with no error, no retry and no toast. There is **no error state** on this
surface's list at all. Severity: high.

**3.13.2 The loading state is a centred line of text plus a spinner, not a skeleton.**
`LoadingState.vue:9-19`, with the message "Fetching automation rules". The header (title, description,
tabs, search, buttons) renders immediately while the body is replaced wholesale
(`SettingsLayout.vue:26-37`), so the page jumps when the data arrives. Severity: low.

**3.13.3 The seven prefetches on mount are silent and unguarded.** `Index.vue:157-166` fires inboxes,
agents, contacts, teams, labels, campaigns and automations with no error handling. If `labels/get` fails,
the "Add a Label" action's dropdown is simply empty (`useAutomationValues.js:28`,
`helper/automationHelper.js:162-163`) with no explanation. `agents/get`, `teams/get`, `inboxes/get` and
`campaigns/get` are dispatched a second time by `AddAutomationRule.vue:82-89`. Severity: medium.

**3.13.4 Opening the edit panel can stall with no feedback.** `Index.vue:180-188` awaits
`until(() => accountUiFlags.isFetchingItem).toBe(false)` and then the SLA fetch before calling
`editDialogRef.open()`. There is no spinner on the clicked row during that wait (the `loading` map is not
touched by `openEditPopup`), and `until(...)` has no timeout, so a stuck flag means the pen button does
nothing, forever, silently. Severity: high.

**3.13.5 `EditAutomationRule.open()` awaits the Lynomia options before showing anything.**
`EditAutomationRule.vue:54-58` `await loadLynomiaOptions()` precedes `formRef.open()`. Two network calls
(`customViews/get` and `loadAudienceFields`, `lynomiaAutomation.js:56-60`) must settle before the panel
appears — again with no row-level or global progress indication. Severity: medium.

**3.13.6 The toggle failure message is the wrong copy.** `Index.vue:311` reports
`AUTOMATION.EDIT.API.ERROR_MESSAGE` ("Could not update automation rule…") while
`AUTOMATION.TOGGLE.ACTIVATION_ERROR` and `DEACTIVATION_ERROR` exist and are never used
(`automation.json:158-159`). The same `catch` also swallows an error thrown by the confirmation dialog
itself. Severity: medium.

**3.13.7 The delay error copy does not match the behaviour it reports.** The message is "The wait must be
between 10 minutes and 30 days" (`automation.json:50`) but `executionDelayInvalid`
(`AutomationRuleForm.vue:103-105`) is true **only** when the value is not a finite number, i.e. when the
field is empty. Out-of-range values are silently clamped by `DurationInput.vue:53-57`, so the user never
sees the message in the case it describes. Severity: medium.

**3.13.8 Eleven i18n keys for this surface are defined and unreferenced**, which means the strings a
redesign would reach for are already drifting: `AUTOMATION.DELETE.TITLE`, `DELETE.SUBMIT`,
`DELETE.CANCEL_BUTTON_TEXT`, `DELETE.CONFIRM.TITLE`, `FORM.CREATE`, `FORM.CANCEL`,
`ADD.FORM.EVENT.PLACEHOLDER`, `ACTION.TEAM_DROPDOWN_PLACEHOLDER`, `TOGGLE.ACTIVATION_ERROR`,
`TOGGLE.DEACTIVATION_ERROR`, `TOGGLE.CONFIRMATION_LABEL`, `TOGGLE.CANCEL_LABEL`, and
`ERRORS.ATLEAST_ONE_CONDITION_REQUIRED` / `ATLEAST_ONE_ACTION_REQUIRED` (verified by grep across `.vue`
and `.js` outside `i18n/`). Severity: low.

### 3.14 Accessibility

**3.14.1 The row's three icon buttons have no accessible name.** `AutomationRuleRow.vue:76-100` passes
`v-tooltip.top` and an `icon`, never `aria-label`. `Button.vue:240-260` emits no label of its own and
`Icon` is decorative. A screen-reader user hears three unnamed buttons per row. `SidePanel.vue:141-148`
shows the correct pattern (`:aria-label="$t('GENERAL.CLOSE')"`), so this is an omission, not a platform
limit. Severity: high.

**3.14.2 Every condition and action trash button is likewise unnamed** — and has no tooltip either.
`ConditionRow.vue:267-274` and `AutomationActionInput.vue:185-193` are icon-only with no `aria-label`,
no `title` and no `v-tooltip`. In a rule with five conditions and three actions there are eight identical
unnamed destructive buttons. Severity: high.

**3.14.3 The active toggle announces only "Toggle".** `Switch.vue:28` is a generic
`<span class="sr-only">{{ t('SWITCH.TOGGLE') }}</span>`, and `AutomationRuleRow.vue:65` passes no
`aria-label` or `aria-labelledby`. Every row's switch has the same name, so a screen-reader user cannot
tell which rule they are about to enable — in a confirmation flow whose dialog *does* name the rule.
Severity: high.

**3.14.4 The four section labels label nothing.** The `<label>` elements at
`AutomationRunTypeSelector.vue:18-20`, `AutomationInstantTrigger.vue:108-110`,
`AutomationActions.vue:54-56` and `AutomationWaitCondition.vue:379-381` carry no `for` and wrap no
control. Assistive technology gets four orphan labels and no programmatic association between the group
heading and its contents. Severity: high.

**3.14.5 The run-type radios are not a group.** Two `RadioCard`s share a `name` derived from each card's own
`id` (`RadioCard.vue:78` — `:name="name || id"`, and `AutomationRunTypeSelector.vue:22-32` never passes
`name`), so the two radios are in **two separate radio groups**. They are also not wrapped in a
`<fieldset>` or `role="radiogroup"`, so arrow-key navigation between the two options does not work.
Severity: high.

**3.14.6 The wait section's four rows use `<span>` as field labels.**
`AutomationWaitCondition.vue:393-396, 399-402, 405-407, 418-421`: a `<span>` of text followed by a
`FilterSelect` / `DurationInput` / `MultiSelect`, with no `aria-label`, no `id`/`aria-labelledby` pair.
"When", "Status is", "For" and "Inbox" are visual-only labels. Severity: high.

**3.14.7 The condition and action rows' controls are unlabelled.** `ConditionRow.vue:193-213` renders three
`FilterSelect` buttons with no accessible name beyond their current value, and the value control
(`:221-265`) has only a placeholder. `AutomationActionInput.vue:151-158` likewise. A rule read aloud is a
sequence of bare values. Severity: high.

**3.14.8 Invalid markup inside both group lists.** `AutomationInstantTrigger.vue:111-152` and
`AutomationActions.vue:57-91` are `<ul>` elements whose last child is a `<div>` wrapping the Add button —
a non-`<li>` child of a list. `AutomationWaitCondition.vue:440-459` goes further and renders **one `<ul>`
per condition**, each containing a `<li>` connector chip plus the `<li>` from `ConditionRow`, so N
conditions become N two-item lists. Screen readers announce "list of 2" repeatedly. Severity: medium.

**3.14.9 The dropdown bodies are not ARIA comboboxes.** `FilterSelect.vue:98-154` and
`MultiSelect.vue:114-217` build a `Button` trigger plus a teleported `DropdownBody` with no
`aria-haspopup`, `aria-expanded`, `aria-controls`, `role="listbox"`/`option` or `aria-selected`. Selection
state inside `MultiSelect` is conveyed by a check **icon** only (`MultiSelect.vue:197-201`). Severity: high.

**3.14.10 `animate-wiggle` is the primary error signal for a row, with no `aria-live` and no
`aria-invalid`.** `ConditionRow.vue:186-189` and `AutomationActionInput.vue:148` shake the row; the error
text that follows is a plain `<span>` with no `role="alert"` and is not referenced by `aria-describedby`.
`prefers-reduced-motion` is not consulted. Severity: medium.

**3.14.11 The container-tint-only error has no text equivalent.** When `errors.condition_N` is set, the
conditions box turns ruby (`AutomationInstantTrigger.vue:113-117`) and that is the whole message —
colour as the sole carrier of meaning. Same for the actions box (`AutomationActions.vue:59-63`) and the
wait box (`AutomationWaitCondition.vue:384-388`, which at least adds text at `:472-474`). Severity: high.

**3.14.12 Validation errors do not move focus.** `AutomationRuleForm.vue:276-289` computes the errors and
returns; nothing focuses the first invalid field and nothing scrolls it into view. In a `3xl` panel whose
single scroller is `SidePanel.vue:151`, a name error at the top is off-screen when the user presses Create
at the bottom. Severity: high.

**3.14.13 The side panel does not trap focus.** `SidePanel.vue:58-61` focuses the panel container once on
enter and restores the previous element on close, but there is no focus trap — Tab walks out of the
`aria-modal="true"` dialog into the page behind it. Severity: medium.

**3.14.14 The tab bar is not an ARIA tablist.** `TabBar.vue:71-105` renders plain `<button>`s with no
`role="tab"`, no `aria-selected`, no `role="tabpanel"` on the table, and the active state is carried by
colour and a sliding indicator only. Arrow-key navigation between tabs does not work. Severity: medium.

**3.14.15 The amber "delayed execution is off" banner is not announced.** `Index.vue:371-376` is a plain
`<div>` with no `role="status"`/`role="alert"` and no icon — colour plus text only. It is also the one
amber surface on the page and carries no dismissal or link to where the feature is enabled. Severity: medium.

**3.14.16 Toasts are the only confirmation channel for 8 of the surface's outcomes.** Create, update,
delete, clone, toggle on, toggle off, recipe-create and the two "need at least one" refusals all report
through `useAlert` (`Index.vue:235-237, 250-253, 264-276, 305-312`; `useAutomation.js:81, 95`). Severity:
low (worth recording: a redesign must keep every one of these nine messages).

**3.14.17 The attachment upload has no accessible state announcement.** `AutomationFileInput.vue:50-75`
changes an icon and a `<p>` label through four states with no `aria-live`, and the `<input type="file">` is
hidden by CSS inside the `<label>` with no visible name of its own. Severity: medium.

---

## 4. What this surface already does well and must not be lost

**4.1 The delayed-rule editor is a genuine plain-language abstraction.** `AutomationWaitCondition.vue`
turns `event_name: message_created` + `message_type: outgoing` + `private_note: false` into one choice
called "Customer hasn't replied" (`constants.js:815-831`), then explains the resulting behaviour in prose
that interpolates the user's own duration in the user's own unit — including what happens when the
condition stops being true (`automation.json:61-66`, `AutomationWaitCondition.vue:108-122`). The footnote
about only new activity starting a clock (`automation.json:66`) answers the single most likely wrong
assumption. This is the best writing on the surface and the hardest thing to rebuild.

**4.2 The private-note guard is invisible correctness.** Choosing "Customer hasn't replied" silently adds
`private_note = false`, because an internal note is an outgoing message and would otherwise arm the wait
(`AutomationWaitCondition.vue:230-245, 292-296`). The user never sees it and never has to know. Keep it.

**4.3 Run-type drafts are preserved across switching.** Toggling between "Run instantly" and "Run after a
wait" does not lose a trigger or conditions the user already configured; each run type keeps its own draft
and restores it (`AutomationRuleForm.vue:91-98, 119-133, 155-172`), with a comment explaining why. Three
specs cover it (`AutomationRuleForm.spec.js:149, 171`).

**4.4 Saved connectors survive edits.** The wait editor preserves an existing `OR` between conditions,
preserves condition order when an inbox is added, and joins only *new* conditions with `AND`
(`AutomationWaitCondition.vue:170-180, 182-221, 305-309, 322-328`), with eight specs pinning the behaviour
(`AutomationWaitCondition.spec.js:144, 247, 312, 365, 433, 482`).

**4.5 Lynomia's condition groups extend the picker instead of forking it.** `lynomiaAutomation.js:146-163`
appends the Audience and Commerce groups to **every** trigger using the same disabled-header convention as
the custom-attribute groups (`helper/automationHelper.js:275-306`), and `useConditionFilterTypes.js`
translates all of it onto one `ConditionRow` contract. One condition row component serves conversation
fields, custom attributes, audiences and Commerce fields.

**4.6 Audience operators read as English, not as machine operators.** `equal_to` / `not_equal_to` are
relabelled "Is in" / "Is not in" for the audience condition only
(`lynomiaAutomation.js:99-103`, `useConditionFilterTypes.js:42-49`) — a targeted relabel that does not
disturb the shared operator registry.

**4.7 Commerce triggers refuse the actions they cannot honour, and say so.** `send_message` and
`send_attachment` are filtered out of the action list on Commerce events
(`AutomationRuleForm.vue:224`, `lynomiaAutomation.js:24, 173-174`) and a note under the event picker
explains both what fires the trigger and why messaging is unavailable
(`automation.json:258`, `AutomationInstantTrigger.vue:96-102`). Removing an impossible option is better
than letting it fail at runtime.

**4.8 Recipes create real rules, switched off, and open them for review.** `automationRecipes.js:51-57`
sets `active: false`; `Index.vue:203-222` creates through the ordinary `automations/create` (so ordinary
validation and the ordinary audit trail apply), names the rule, records its provenance and version in the
description, and then opens the edit panel on it. A recipe whose requirements the account does not meet is
shown with what is missing and **no** Create button (`RecipeDialog.vue:136-153`) rather than letting
someone build something that cannot work. A failed create leaves the dialog, the recipe and the values
exactly as they were (`RecipeDialog.vue:104-106`, `Index.vue:217-221`).

**4.9 The first-run empty state teaches rather than just reporting.** `AUTOMATION.LIST.EMPTY_HINT`
explains both routes *and* that a recipe arrives switched off, with the two matching buttons right there
(`Index.vue:377-403`, `automation.json:98`).

**4.10 The delay-disabled banner is honest.** Rather than hiding delayed rules when the feature is off, the
page keeps showing them, keeps the tabs visible (`Index.vue:72-76`) and states plainly that they are paused
(`Index.vue:143-147, 371-376`). The payload also drops `execution_delay` instead of sending a value the API
would reject, preserving the stored value server-side (`AutomationRuleForm.vue:286` with its comment).

**4.11 Enable and disable both require confirmation, and the dialog names the rule.**
`Index.vue:279-313` builds a different title and a rule-specific description for each direction before
awaiting the promise-based confirm (`ConfirmationModal.vue:35-50`). Turning a rule on is treated as
consequential, which it is.

**4.12 Delete confirmation puts the rule name in the body *and* in both buttons.** `Index.vue:115-123` —
"Yes, Delete <name>" / "No, Keep <name>". Verbose (§3.7.5) but unmistakable; the user cannot confirm the
wrong rule by muscle memory.

**4.13 "At least one" is enforced as a refusal with an explanation, not a disabled button.**
`useAutomation.js:79-101` toasts "You need to have atleast one condition to save" instead of silently
disabling the trash button, so the user learns the rule.

**4.14 Changing a condition's attribute resets the value to the correct empty shape.**
`ConditionRow.vue:142-165` picks `[]`, `{}` or `''` per the new input type and re-resolves the operator, so
switching from a text field to a multi-select cannot leave a malformed value behind.

**4.15 The surface is correctly gated at the route.** Feature flag plus `administrator` permission in one
place (`automation.routes.js:22-25`) rather than scattered guards; the feature-specific gates
(`delayed_automations`, `lynomia_commerce`, `sla`) are each read once and flow down as props.

**4.16 Dropdowns inside the panel are teleported.** `provideDropdownTeleport()`
(`AutomationRuleForm.vue:78`, `components-next/dropdown-menu/base/provider.js:22-28`) means a condition's
attribute menu is never clipped by the panel's scroll container — a real class of bug, solved once.

**4.17 Attribute pickers become searchable exactly when they need to.** `FilterSelect.vue:52-63` shows a
search box past 8 options and drops the non-selectable group headers while a query is active, so searching
a long Commerce attribute list returns only selectable rows.

**4.18 The side panel's modal basics are right.** `role="dialog"`, `aria-modal`, `aria-label` from the
title, Escape-to-close that defers to a nested `<dialog>`, overlay click, body scroll lock, and focus
restored to the element that opened it (`SidePanel.vue:47-83, 117-121`).

**4.19 The row's delay badge and its native date tooltip add information without adding columns.**
`AutomationRuleRow.vue:47-56, 68`.

**4.20 The audience deep link is shareable and idempotent.** The query is left in the URL on purpose, the
page is keyed by `fullPath` so arriving with a different audience remounts cleanly, and an id that is not
one of this account's shared audiences simply opens a blank panel instead of erroring
(`Index.vue:149-155`, `audienceHelper.js:38-39`, `AddAutomationRule.vue:71-74`).

**4.21 Action pickers carry per-action icons, shared with macros.** `helper/automationHelper.js:88-118`
with a sensible `i-lucide-zap` fallback, so the action list scans visually rather than as 19 lines of text.

**4.22 There is real spec coverage to protect behaviour.** `specs/Index.spec.js` (6 cases, including the
audience deep link and the recipe payload), `AutomationRuleForm.spec.js` (3 cases on draft preservation),
`components/AutomationWaitCondition.spec.js` (9 cases on hydration, connectors and condition preservation),
`lynomiaAutomation.spec.js` (5 cases on the condition groups and action suppression). Any redesign can lean
on these.
