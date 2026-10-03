# Audit — Form and Action Primitives (`components-next`)

**Date:** 2026-10-03
**Scope:** `app/javascript/dashboard/components-next/{button, buttonGroup, input, inline-input, select, selectmenu, combobox, checkbox, switch, radioCard, colorpicker, phonenumberinput, label}`
**Mode:** read-only inventory. This file is the **baseline** that later modernization work is checked against. Everything below was read from source; every assertion carries a `file:line`.

Paths are relative to `/home/user/lynomiachat/app/javascript/dashboard/` unless stated otherwise.

---

## 1. File inventory

| Component | File | LOC | Story? |
|---|---|---|---|
| Button | `components-next/button/Button.vue` | 261 | `button/Button.story.vue` |
| Button tokens | `components-next/button/constants.js` | 17 | — |
| ConfirmButton | `components-next/button/ConfirmButton.vue` | 101 | `button/ConfirmButton.story.vue` |
| ButtonGroup | `components-next/buttonGroup/ButtonGroup.vue` | 20 | **none** |
| Input | `components-next/input/Input.vue` | 154 | `input/Input.story.vue` |
| Input tokens | `components-next/input/constants.js` | 5 | — |
| ChoiceToggle | `components-next/input/ChoiceToggle.vue` | 45 | **none** |
| DurationInput | `components-next/input/DurationInput.vue` | 97 | **none** |
| InlineInput | `components-next/inline-input/InlineInput.vue` | 129 | `inline-input/InlineInput.story.vue` |
| Select | `components-next/select/Select.vue` | 102 | **none** |
| SelectMenu | `components-next/selectmenu/SelectMenu.vue` | 85 | `selectmenu/SelectMenu.story.vue` |
| ComboBox | `components-next/combobox/ComboBox.vue` | 143 | `combobox/ComboBox.story.vue` |
| ComboBoxDropdown | `components-next/combobox/ComboBoxDropdown.vue` | 125 | **none** |
| TagMultiSelectComboBox | `components-next/combobox/TagMultiSelectComboBox.vue` | 183 | `combobox/TagMultiSelectComboxBox.story.vue` (filename typo: `Combox`) |
| ReorderableMultiSelect | `components-next/combobox/ReorderableMultiSelect.vue` | 297 | **none** |
| Checkbox | `components-next/checkbox/Checkbox.vue` | 63 | `checkbox/Checkbox.story.vue` |
| Switch | `components-next/switch/Switch.vue` | 42 | `switch/Switch.story.vue` |
| RadioCard | `components-next/radioCard/RadioCard.vue` | 91 | `radioCard/RadioCard.story.vue` |
| ColorPicker | `components-next/colorpicker/ColorPicker.vue` | 101 | **none** |
| PhoneNumberInput | `components-next/phonenumberinput/PhoneNumberInput.vue` | 225 | `phonenumberinput/PhoneNumberInput.story.vue` |
| Label | `components-next/label/Label.vue` | 71 | **none** |
| LabelItem | `components-next/label/LabelItem.vue` | 57 | **none** |
| AddLabel | `components-next/label/AddLabel.vue` | 49 | **none** |

### Adoption (dashboard tree, `*.vue`)

| Primitive | Call sites | Notes |
|---|---|---|
| `Button` / `NextButton` | **840** | 544 as `<Button>`, 296 as `<NextButton>` (same file, two import aliases) |
| `Input` | 150 | |
| `Select` | 21 (14 files) | |
| `ComboBox` | 35 (22 files) | |
| `Checkbox` | 29 (17 files) | |
| `Switch` | 16 files | |
| `InlineInput` | 20 (11 files) | |
| `Label` | 14 (9 files) | |
| `RadioCard` | 10 files | |
| `SelectMenu` | 3 files | |
| `ColorPicker` | 2 files | |
| `PhoneNumberInput` | 1 file (`components-next/Contacts/ContactsForm/ContactsForm.vue`) | |
| `ChoiceToggle` | 1 file (`components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue`) | |
| `ConfirmButton` | 2 real consumers (`components-next/dialog/Dialog.vue`, `routes/dashboard/settings/profile/AccessToken.vue`) | |

Legacy `woot-button` is fully gone (0 occurrences). The legacy global form CSS is **not** gone — see §6.

---

## 2. Button (`components-next/button/Button.vue`)

### 2.1 Props

| Prop | Type | Default | Validator | Line |
|---|---|---|---|---|
| `label` | `String \| Number` | `''` | — | 15 |
| `variant` | `String` | `null` | `VARIANT_OPTIONS.includes(v) \|\| v === null` | 16-20 |
| `color` | `String` | `null` | `COLOR_OPTIONS.includes(v) \|\| v === null` | 21-25 |
| `size` | `String` | `null` | `SIZE_OPTIONS.includes(v) \|\| v === null` | 26-30 |
| `justify` | `String` | `null` | `JUSTIFY_OPTIONS.includes(v) \|\| v === null` | 31-35 |
| `icon` | `String \| Object \| Function` | `''` | — | 36 |
| `trailingIcon` | `Boolean` | `false` | — | 37 |
| `isLoading` | `Boolean` | `false` | — | 38 |
| `noAnimation` | `Boolean` | `false` | — | 39 |

No `disabled`, `type`, `ariaLabel` or `tooltip` prop — all reach the `<button>` through attribute fallthrough (`filteredAttrs`, 49-59 / 241). `defineOptions({ inheritAttrs: false })` at 45-47.

### 2.2 Token tables (`button/constants.js`)

| Constant | Values | Line |
|---|---|---|
| `VARIANT_OPTIONS` | `solid`, `outline`, `faded`, `link`, `ghost` | 1 |
| `COLOR_OPTIONS` | `blue`, `ruby`, `amber`, `slate`, `teal` | 2 |
| `SIZE_OPTIONS` | `xs`, `sm`, `md`, `lg` | 3 |
| `JUSTIFY_OPTIONS` | `start`, `center`, `end` | 4 |
| `EXCLUDED_ATTRS` | `variant`, `color`, `size`, `icon`, `trailingIcon`, `isLoading` + all four lists above | 6-17 |

**Shorthand boolean attribute API.** Besides props, every variant / colour / size / justify name is also accepted as a bare attribute, resolved in `computedVariant` (61-70), `computedColor` (72-80), `computedSize` (82-89), `computedJustify` (91-98). `attrs.x === ''` is checked explicitly because `useAttrs()` yields `''` for valueless attributes (comment at 63). This is why `slate xs faded` works (e.g. `components-next/label/LabelItem.vue:49-52`, `components/ChatListHeader.vue:114-120`).
Resolution order is **prop wins, then first matching shorthand in list order, then default** — `solid` / `blue` / `md` / `center`.

The six non-shorthand entries in `EXCLUDED_ATTRS` (`variant`, `color`, `size`, `icon`, `trailingIcon`, `isLoading`, `constants.js:7-12`) are dead: they are declared props, so Vue never puts them in `$attrs`. Only the 17 shorthand names actually need filtering.

### 2.3 Variant × colour matrix (`STYLE_CONFIG.colors`, 100-156)

All 25 combinations are implemented. Full classes:

| Colour | solid | faded | outline | ghost | link |
|---|---|---|---|---|---|
| `blue` (103-110) | `bg-n-brand text-white hover:enabled:brightness-110 focus-visible:brightness-110 outline-transparent` | `bg-n-brand/10 text-n-blue-11 hover:enabled:bg-n-brand/20 focus-visible:bg-n-brand/20 outline-transparent` | `text-n-blue-11 outline-n-brand` | `text-n-blue-11 hover:enabled:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-transparent` | `text-n-blue-11 hover:enabled:underline focus-visible:underline outline-transparent` |
| `ruby` (112-122) | `bg-n-ruby-9 text-white hover:enabled:bg-n-ruby-10 …` | `bg-n-ruby-9/10 text-n-ruby-11 …` | `text-n-ruby-11 hover:enabled:bg-n-ruby-9/10 outline-n-ruby-8` | `text-n-ruby-11 hover:enabled:bg-n-alpha-2 …` | `text-n-ruby-9 dark:text-n-ruby-11 hover:enabled:underline …` |
| `amber` (123-133) | `bg-n-amber-9 text-n-amber-12 dark:text-n-amber-3 …` | `bg-n-amber-9/10 text-n-slate-12 …` | `text-n-amber-11 … outline-n-amber-9` | `text-n-amber-9 hover:enabled:bg-n-alpha-2 …` | `text-n-amber-9 hover:enabled:underline …` |
| `slate` (134-144) | `bg-n-button-color dark:hover:enabled:bg-n-solid-2 … text-n-slate-12 outline-n-container` | `bg-n-slate-9/10 text-n-slate-12 …` | `text-n-slate-11 outline-n-strong …` | `text-n-slate-12 hover:enabled:bg-n-alpha-2 …` | `text-n-slate-11 hover:enabled:text-n-slate-12 … underline` |
| `teal` (145-155) | `bg-n-teal-9 text-white …` | `bg-n-teal-9/10 text-n-teal-11 …` | `text-n-teal-11 … outline-n-teal-9` | `text-n-teal-9 hover:enabled:bg-n-alpha-2 …` | `text-n-teal-9 hover:enabled:underline …` |

Note `blue`/`amber`/`teal`/`blue` `outline` variants differ in whether they include a hover background: `blue.outline` (107) has **no** hover background, every other colour's `outline` does.

### 2.4 Sizes (157-188)

| Size | regular (160-163) | iconOnly (165-168) | link (171-174) | fontSize (178-181) | clickAnimation (184-187) |
|---|---|---|---|---|---|
| `xs` | `h-6 px-2` | `h-6 w-6 p-0` | `p-0` | `text-xs` | `active:enabled:scale-[0.97]` |
| `sm` | `h-8 px-3` | `h-8 w-8 p-0` | `p-0` | `text-sm` | `active:enabled:scale-[0.97]` |
| `md` | `h-10 px-4` | `h-10 w-10 p-0` | `p-0` | `text-sm font-medium` | `active:enabled:scale-[0.98]` |
| `lg` | `h-12 px-5` | `h-12 w-12 p-0` | `p-0` | `text-base` | `active:enabled:scale-[0.98]` |

`isIconOnly` is derived, not declared: `!props.label && !slots.default` (209). Size table selection at 213. `link` variant skips the size table entirely (216-217, 223-230) and is always `p-0`.

Base: `inline-flex items-center min-w-0 gap-2 transition-all duration-100 ease-out border-0 rounded-lg outline-1 outline disabled:opacity-50` (194). Justify map `justify-start / justify-center / justify-end` (189-193). `noAnimation` suppresses the active scale (232-236).

### 2.5 Slots and rendering (239-260)

| Slot | Fallback | Line |
|---|---|---|
| `icon` | `<Icon :icon="icon" class="flex-shrink-0" />`; rendered only when `(icon \|\| $slots.icon) && !isLoading` | 251-253 |
| `default` | `<span v-if="label" class="min-w-0 truncate">{{ label }}</span>` | 257-259 |

`isLoading` replaces the icon with `<Spinner class="!w-5 !h-5 flex-shrink-0" />` (255) but **keeps the label**. It does not set `disabled` — callers must pass both (see `components-next/dialog/Dialog.vue:167-168`).
`trailingIcon && !isIconOnly` → `flex-row-reverse` (248), which is direction-aware for free.

### 2.6 Accessible name

- No `ariaLabel` prop. `aria-label` is not in `EXCLUDED_ATTRS`, so it passes through `filteredAttrs` onto the `<button>`. That is the only mechanism.
- Icon-only buttons (`icon` set, no `label`, self-closing) across the dashboard: **248**. Of those **224 (90%) have no `aria-label`**.
  - 84 of the 224 carry only `v-tooltip` (e.g. `components/ChatListHeader.vue:114-115`, `:131-133`, `:146-148`, `:157-159`) — a visual-only name, not an accessible one.
  - **140 have neither `aria-label` nor a tooltip** — e.g. `components/table/Pagination.vue:124,133,158,167`; `components/widgets/TableFooterPagination.vue:54,66,86,98`; `components/widgets/conversation/components/GalleryView.vue:224,231,238,245`; `components/Modal.vue:89`; `components/ui/DatePicker/components/CalendarAction.vue:43,68`; `components/NetworkNotification.vue:117,128`; `components/widgets/WootWriter/ReplyTopPanel.vue:172,197`; `components/buttons/ResolveAction.vue:213`.

### 2.7 Focus state

The only focus affordance is `focus-visible:` colour change. Extracted from `Button.vue`: `focus-visible:bg-n-alpha-2` (×6), `focus-visible:underline` (×5), `focus-visible:brightness-110` (×1, the `blue solid` default), plus per-colour background tints. **No `focus-visible:outline-*`, no `ring`, no `outline-offset`.** Base (194) declares `outline-1 outline` and the `solid`/`faded`/`ghost`/`link` colour sets all pin `outline-transparent`, so the default primary button's entire keyboard-focus indicator is a 10% brightness bump.

### 2.8 RTL

Clean. No `ltr:`/`rtl:` and no physical `ml/mr/pl/pr/left/right` anywhere in `Button.vue`. Direction is handled structurally by `inline-flex` + `gap-2` + `flex-row-reverse`.

### 2.9 Button escape hatches in the wild

**147 of 544 `<Button>` call sites and 31 of 296 `<NextButton>` call sites (178 total, 21%) override the primitive with `!important` Tailwind classes** — e.g. `modules/search/components/SearchDateRangeSelector.vue:248,257`, `components/ChatListHeader.vue:81`, `components/auth/MfaVerification.vue:237,250,259`, `components-next/label/LabelItem.vue:46`, `components-next/selectmenu/SelectMenu.vue:54,79`, `components-next/phonenumberinput/PhoneNumberInput.vue:189`. The dominant need is a height/padding the 4-step size scale does not offer (`!h-7`, `!h-[1.875rem]`, `!px-2.5`) and partial corner rounding for grouped controls (`ltr:!rounded-r-none rtl:!rounded-l-none`).

### 2.10 ConfirmButton (`button/ConfirmButton.vue`)

Two-step destructive confirm. Props: `label` (`''`), `confirmLabel` (`''`), `color` (`'blue'`), `confirmColor` (`'ruby'`), `confirmHint` (`''`), `variant` (`null`), `size` (`null`), `justify` (`null`), `icon` (`''`), `trailingIcon` (`false`), `isLoading` (`false`), `disabled` (`false`) — 5-18. **No validators on `color`/`variant`/`size`**, unlike `Button`. Emits `click` only on the second press (37-45); auto-resets after 400 ms (43) and on `blur` (67). `confirmHint` renders as absolutely-positioned `text-[10px]` helper text (76-81).
Two deviations from house style: it has a `<style scoped>` block with a hand-written `@keyframes bounce-complete` (85-100), and it does **not** set `inheritAttrs: false`, so any `aria-label`, `data-test-id` or `type` a caller passes lands on the wrapping `<div class="relative">` (49) instead of the button.

### 2.11 ButtonGroup (`buttonGroup/ButtonGroup.vue`)

20 lines, one prop `noAnimation` (`false`). Pure wrapper that scales the group on child press via `has-[button:not(:disabled):active]:scale-[0.98]` (15). No segmented-control styling, no `role="group"`, no shared corner rounding — callers do corners themselves with `!rounded-*` overrides.

---

## 3. Text inputs

### 3.1 Input (`components-next/input/Input.vue`)

| Prop | Type | Default | Validator | Line |
|---|---|---|---|---|
| `modelValue` | `String \| Number` | `''` | — | 4 |
| `type` | `String` | `'text'` | — | 5 |
| `customInputClass` | `String \| Object \| Array` | `''` | — | 6 |
| `placeholder` | `String` | `''` | — | 7 |
| `label` | `String` | `''` | — | 8 |
| `id` | `String` | `''` | — | 9 |
| `size` | `String` | `'md'` | `['sm','md'].includes(v)` | 10-14 |
| `message` | `String` | `''` | — | 15 |
| `disabled` | `Boolean` | `false` | — | 16 |
| `messageType` | `String` | `'info'` | `['info','error','success'].includes(v)` | 17-21 |
| `min` | `String` | `''` | — | 22 |
| `max` | `String` | `''` | — | 23 |
| `autofocus` | `Boolean` | `false` | — | 24 |

Emits: `update:modelValue`, `blur`, `input`, `focus`, `enter` (27-33). Slot: `prefix` (116) — rendered **between** the label and the input, as a sibling, not inside the field.

| Aspect | Implementation |
|---|---|
| Sizes | `sm` → `h-8 !px-3 !py-2`; `md` (and fallback) → `h-10 !px-3 !py-2.5` (77-86) |
| Message colours | error `text-n-ruby-9 dark:text-n-ruby-9`; success `text-n-teal-10 dark:text-n-teal-10`; info `text-n-slate-11` (42-51) |
| Outline (non-error) | `outline-n-weak hover:outline-n-slate-6 disabled:outline-n-weak focus:outline-n-brand` (58) |
| Outline (error) | `outline-n-ruby-8 hover:outline-n-ruby-9 disabled:outline-n-ruby-8` (56) |
| Base field classes | `block w-full reset-base text-sm !mb-0 outline outline-1 border-none outline-offset-[-1px] rounded-lg bg-n-alpha-black2 … transition-all duration-500 ease-in-out [appearance:textfield]` + spin-button suppression (140) |
| Number coercion | `handleInput` casts to `Number` for `type="number"` when non-empty (62-70) |
| Autofocus | `onMounted` + `nextTick` → `inputRef.focus()` (97-103) |

**Accessible name.** `label` renders a real `<label :for="uniqueId">` (108-114). `uniqueId` falls back to `input-${uid}` from `getCurrentInstance()` when `id` is not passed (36-37), so the association always holds. This is the **only** primitive in this area with a correct auto-generated id. There is no `ariaLabel` prop; `aria-label` arrives via `$attrs`.

**Focus state.** `focus:outline-n-brand` exists only in the non-error branch (58). In `messageType="error"` the field has **no focus style at all** (56) — a keyboard user tabbing into an invalid field gets no visual change.

**`min` is dropped for `type="number"`.** `:min` is applied only for `date`/`datetime-local`/`time` (134); `:max` is applied for those **plus** `number` (135-139). `components-next/recipes/RecipeInputs.vue:117-122` passes `type="number"` with `:min="boundary(input.min)"` — the lower bound never reaches the DOM.

**`$attrs` double-application.** `v-bind="$attrs"` is on the inner `<input>` (119) but `inheritAttrs: false` is **not** declared. Vue therefore merges fallthrough attrs onto the root `<div class="relative flex flex-col min-w-0 gap-1">` (107) *and* `v-bind="$attrs"` applies them again to the input. A caller's `class` styles both the wrapper and the field; a caller's `aria-label` also lands as a stray `aria-label` on a plain `div`. This is the direct reason callers need the separate `customInputClass` prop plus `!important`: **23 of 150 `<Input>` call sites use `!important` overrides** (e.g. `components-next/HelpCenter/Pages/CategoryPage/CategoryForm.vue:206,249`, `components-next/HelpCenter/Pages/PortalSettingsPage/PortalBaseSettings.vue:204,222`, `components-next/phonenumberinput/PhoneNumberInput.vue:174`).

**RTL.** No `ltr:`/`rtl:` and no physical spacing utilities. `!px-3` is logical-equivalent (symmetric). Clean, *except* that the `prefix` slot sits outside the field box, so prefix placement is the caller's problem (see §3.5).

### 3.2 InlineInput (`components-next/inline-input/InlineInput.vue`)

| Prop | Type | Default | Line |
|---|---|---|---|
| `type` | `String` | `'text'` | 5-8 |
| `customInputClass` | `String \| Object \| Array` | `''` | 9-12 |
| `customLabelClass` | `String \| Object \| Array` | `''` | 13-16 |
| `placeholder` | `String` | `''` | 17-20 |
| `label` | `String` | `''` | 21-24 |
| `id` | `String` | `''` | 25-28 |
| `disabled` | `Boolean` | `false` | 29-32 |
| `readonly` | `Boolean` | `false` | 33-36 |
| `focusOnMount` | `Boolean` | `false` | 37-40 |
| `maxLength` | `Number` | `null` | 41-44 |

`defineModel` `String \| Number`, default `''` (55-58). Emits `enterPress`, `escapePress`, `input`, `blur`, `focus` (47-53) — note `input`/`blur`/`focus` emit `event.target.value`, **not** the event (70-81), the opposite of `Input.vue` which emits the event (69, 73, 89). Exposes `focus()` / `blur()` (91-94).
Classes: `flex w-full min-w-0 reset-base text-sm h-6 !mb-0 border-0 rounded-none outline-none outline-0 bg-transparent …` (121). Fixed `h-6`; no size prop; no `message`/`messageType`.

**Accessible name — broken by default.** `<label :for="id">` (101-103) with `id` defaulting to `''` and **no uid fallback**. Call sites that pass `label` but not `id` produce `<label for="">`: `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorProperties.vue:101-108`, `components-next/captain/assistant/AddNewRulesInput.vue:41-48`, `components-next/NewConversation/components/EmailOptions.vue:78-81`. Only `components-next/captain/assistant/PlaygroundTestSetup.vue:205-208` passes an `:id`.

**Focus state.** `outline-none outline-0` (121) — the focus indicator is deliberately removed and nothing replaces it. Inline rename fields are keyboard-invisible.

**`$attrs`.** No `v-bind="$attrs"` anywhere and no `inheritAttrs: false`, so every un-declared attribute (`name`, `autocomplete`, `inputmode`, `aria-label`, `data-test-id`) lands on the wrapper `<div>` (98-100) and never reaches the `<input>`.

**RTL.** Clean — no physical utilities.

### 3.3 ChoiceToggle (`components-next/input/ChoiceToggle.vue`)

Hard-coded boolean Yes/No segmented radio pair. One prop `modelValue: Boolean` (5-9, **no default**), emits `update:modelValue` (11). Options are built in-component from `CHOICE_TOGGLE.YES` / `CHOICE_TOGGLE.NO` (14-17) — it cannot express any other pair of choices.
Container: `flex gap-4 items-center px-4 py-2.5 w-full rounded-lg divide-x transition-colors bg-n-solid-1 outline outline-1 outline-n-weak hover:outline-n-slate-6 focus-within:outline-n-brand divide-n-weak` (26). Focus is handled at the group level via `focus-within:outline-n-brand` — the only primitive in this area that does this.
Inputs are native `<input type="radio" class="size-4 accent-n-blue-9 text-n-blue-9">` (34-40) with **no `name` attribute**, so the two radios are not a native radio group (no arrow-key navigation, no single-selection enforcement by the browser; correctness depends entirely on the `:checked` binding). Each radio is wrapped in a `<label>` with its text (33-42), so accessible names are fine.
RTL: `divide-x` is a physical-axis utility but symmetric here; no `ltr:`/`rtl:` needed.

### 3.4 DurationInput (`components-next/input/DurationInput.vue`)

Props: `min` (`Number`, `0`), `max` (`Number`, `Infinity`), `disabled` (`Boolean`, `false`) — 7-11. Two models: `modelValue` (`Number`, `null`, always **minutes**) and `unit` (`String`, `DURATION_UNITS.MINUTES`, with a `validate` member — note: `validate`, not `validator`, 15-21). Unit tokens in `input/constants.js:1-5`: `minutes`, `hours`, `days`.
Conversion in `convertToMinutes` (23-31) and `transformedValue` (33-51); `normalizeDuration` clamps on blur/Enter (53-57, 80); a `watch(unit)` re-rounds the stored minutes when the unit changes, with an explanatory comment (59-68).

Two structural problems:
- **Fragment root, and the unit picker is a raw `<select>`** (82-96) relying on the global `select` SCSS instead of `components-next/select/Select.vue`. Consumers must both supply the flex container and reach into it: `class="flex items-center gap-2 flex-1 [&>select]:!bg-n-alpha-2 [&>select]:!outline-none [&>select]:hover:brightness-110"` at `components-next/AssignmentPolicy/components/ExclusionRules.vue:137` and `components-next/AssignmentPolicy/components/FairDistribution.vue:88`.
- **Dangling Tailwind variant** `class="flex-grow w-full disabled:"` (78) — `disabled:` with no utility.

No label/`aria-label` plumbing on either control. Consumers label it externally (`routes/dashboard/settings/automation/components/AutomationWaitCondition.vue:405-407`).

### 3.5 PhoneNumberInput (`components-next/phonenumberinput/PhoneNumberInput.vue`)

Props: `placeholder` (`''`), `disabled` (`false`), `showBorder` (`Boolean`, **`true`**) — 17-30. `defineModel` `String \| Number`, `''` (32-35). Composed from `Input` + `Button` + `DropdownMenu` (13-15).
Validation is internal via `@vuelidate/core` (45-61): `phoneNumber` → `minLength(2)`, `numeric`; `activeDialCode` → `required` + membership in `shared/constants/countries.js`. Errors render from `PHONE_INPUT.DIAL_CODE_ERROR` / `PHONE_INPUT.ERROR` (108-113) in a `text-xs … text-n-ruby-9` paragraph (216-223). Country parsing uses `libphonenumber-js` (150-155) with `getActiveCountryCode` / `getActiveDialCode` from `shared/components/PhoneInput/helper` (8-11).
Border states are computed in `inputBorderClass` (91-106), including the `showBorder=false` transparent case with `has-[:focus]:outline-n-brand`.

- **Accessible name:** none. The country trigger is an icon/emoji `Button` with `:label="activeCountry?.emoji"` (180) and no `aria-label`, no `aria-expanded`, no `aria-haspopup`. The number field gets no label.
- **RTL:** handled, but entirely with `ltr:`/`rtl:` pairs rather than logical utilities — `ltr:!pl-1 rtl:!pr-1` (174), `ltr:ml-px rtl:mr-px … ltr:!rounded-r-none rtl:!rounded-l-none` (189), `ltr:!pl-1 rtl:!pr-1` (201), `ltr:left-0 rtl:right-0` (212). Line 201 also hard-codes `left-[38px] top-2.5` with no RTL counterpart.
- Only one consumer: `components-next/Contacts/ContactsForm/ContactsForm.vue`.

---

## 4. Choice primitives

### 4.1 Select (`components-next/select/Select.vue`) — native `<select>`

| Prop | Type | Default | Validator | Line |
|---|---|---|---|---|
| `options` | `Array` | `[]` | every item is an object with `value` and `label` | 5-12 |
| `groups` | `Array` | `[]` | every group has `label` + `options[]` each with `value`/`label` | 13-23 |
| `placeholder` | `String` | `''` | — | 24-27 |
| `disabled` | `Boolean` | `false` | — | 28-31 |
| `error` | `String` | `''` | — | 32-35 |
| `ariaLabel` | `String` | `''` | — | 36-39 |

`defineModel` `String \| Number \| Boolean`, `''` (42-45). Supports `optgroup` (65-80) and per-option `disabled` (75, 86). Placeholder renders as a `disabled` `<option value="">` (62-64). Chevron is a decorative `Icon` overlay (92-100).
**This is the only primitive in the area with a real `ariaLabel` prop** (53: `:aria-label="ariaLabel || undefined"`), used at `components-next/recipes/RecipeInputs.vue:105` and `components-next/captain/pageComponents/assistant/settings/DurationSelect.vue:81,88`.

Three concrete defects:

1. **The error state is a no-op.** Line 58 applies `outline-n-red-9 focus:outline-n-red-9`. There is **no `n-red-*` scale** in the theme — `theme/colors.js` defines `n-ruby-1…12`, and `red` only as the non-`n` legacy palette plus `n-solid-red`. `Select.vue:58` is the single occurrence of `n-red-` in `app/javascript`, so Tailwind emits nothing. `error` is passed at `components-next/recipes/RecipeInputs.vue:106` and `.../DurationSelect.vue:80,87` and is **invisible** at all three.
2. **The `error` text is never rendered.** Unlike `Input` (146-152) and `ComboBox` (131-140), `Select` has no message paragraph — the string is accepted and discarded.
3. **No RTL handling.** `pr-10` on the select and `right-0 … pr-3` on the chevron overlay (54, 93) are physical, with no `rtl:` counterpart and no `pe-*`/`end-*`. In RTL the arrow stays on the right while the text starts on the right, so they collide.

Separately, the root is `w-fit relative` (49) and the `<select>` carries no `v-bind="$attrs"`, so caller `class` lands on the wrapper. Every consumer that needs a full-width field repeats the same workaround — `class="!w-full [&>select]:w-full"` at `modules/conversations/components/ReportCaptainMessageDialog.vue:91`, `components/widgets/conversation/commerce/CommerceOrderActions.vue:412,423`, `components/widgets/conversation/commerce/CommercePanel.vue:386`, `routes/dashboard/settings/data/NewImportDialog.vue:188` (5 of 21 call sites).

### 4.2 SelectMenu (`components-next/selectmenu/SelectMenu.vue`) — custom popover

Props: `options` (`Array`, **required**), `modelValue` (`String`, **required**), `label` (`String`, **required**), `subMenuPosition` (`String`, `'right'`, validator `['right','left','bottom']`) — 5-25. Emits `update:modelValue` (27). Closes via the `v-on-clickaway` directive (45).
Trigger is a `Button` `size="sm" color="slate" variant="faded"` with `trailing-icon` and `i-lucide-chevron-down` (48-58), forced to `!w-fit max-w-40` and tinted when open. Items are `Button` `size="sm" variant="ghost" color="slate"` with `!justify-end !px-2.5 !h-7` (70-82) and a leading `i-lucide-check` on the selected row.
Accessibility: **no `role="menu"`/`listbox`, no `aria-expanded`, no `aria-haspopup`, no roving focus, no keyboard handling.** Items are reachable by Tab only because they are real buttons; Escape does not close.
RTL: handled with `ltr:`/`rtl:` pairs for all three positions (63-67). `labelValue` (31) is a pass-through computed with no purpose.
3 consumers: `components/widgets/conversation/ConversationBasicFilter.vue`, `components-next/Companies/CompaniesHeader/components/CompanySortMenu.vue`, `components-next/Contacts/ContactsHeader/components/ContactSortMenu.vue`.

### 4.3 ComboBox (`components-next/combobox/ComboBox.vue`)

| Prop | Type | Default | Validator | Line |
|---|---|---|---|---|
| `options` | `Array` | **required** | every option has `value` + `label` | 10-15 |
| `placeholder` | `String` | `''` | — | 16 |
| `displayLabel` | `String` | `''` | fallback label for lazily-loaded values (comment 17-18) | 19 |
| `modelValue` | `String \| Number` | `''` | — | 20 |
| `disabled` | `Boolean` | `false` | — | 21 |
| `searchPlaceholder` | `String` | `''` | — | 22 |
| `emptyState` | `String` | `''` | — | 23 |
| `message` | `String` | `''` | — | 24 |
| `hasError` | `Boolean` | `false` | — | 25 |
| `useApiResults` | `Boolean` | `false` | skips local filtering (comment 26) | 26 |

Emits `update:modelValue`, `search`, `open` (29). Selecting the already-selected value **clears** it (62-67). Local filtering is case-insensitive substring on `label` (39-50). Placeholder falls back to `COMBOBOX.PLACEHOLDER` (51-53).
Trigger is a `Button variant="outline"` whose colour encodes state — `ruby` on error, `blue` when open, else `slate` (104) — plus `no-animation` and a long `!px-3 !py-2.5 … focus:outline-n-brand` override string (109-114) including a bare `focused` class (111) that **matches no CSS rule anywhere in the codebase** (same for `focus` in `Input.vue:128`). Message paragraph at 131-140.

**ComboBoxDropdown** (`combobox/ComboBoxDropdown.vue`) props: `open` (required `Boolean`), `options` (required `Array`), `searchPlaceholder` (`''`), `emptyState` (`''`), `multiple` (`false`), `selectedValues` (`String|Number|Array`, `[]`), `loading` (`false`) — 7-36; `searchValue` as a named model (42-45); exposes `focus()` (61-63). Search field is a raw `<input type="search" class="reset-base w-full py-2 !ps-10 !pe-2 … focus:outline-none">` (82-89) with a `Spinner`/`i-lucide-search` swap (72-81).
Semantics are partial: `role="listbox"` + `aria-multiselectable` on the `<ul>` (93-94), `role="option"` + `aria-selected` on each `<li>` (103-104) — but the `<li>`s are not focusable, there is **no `aria-controls`/`aria-activedescendant` linking the input to the list, no `role="combobox"`, no `aria-expanded`, and no `@keydown` handler anywhere in either file**. Arrow-key navigation and Enter-to-select do not exist; selection is mouse-only.
RTL: `ComboBoxDropdown` is the **best-behaved file in this audit** — it uses logical utilities throughout (`start-3` at 75 and 80, `!ps-10 !pe-2` at 87).
**16 of 35 `ComboBox` call sites use `!important` overrides** (e.g. `components-next/HelpCenter/Pages/LocalePage/AddLocaleDialog.vue:129,141`, `components-next/Companies/CompanySelector.vue:131`), and `components-next/recipes/RecipeInputs.vue:114` reaches through two levels of DOM with `[&>div>button]:bg-n-alpha-black2`.

### 4.4 TagMultiSelectComboBox (`combobox/TagMultiSelectComboBox.vue`)

Props mirror `ComboBox` minus `displayLabel`/`useApiResults`, with `modelValue` as `Array` (8-43). Emits `update:modelValue` (45). Exposes `toggleDropdown`, `open`, `disabled` (107-111) — note `disabled: props.disabled` is captured once and will not stay reactive.
Trigger is a hand-built `div` chip well, not a `Button`: `flex flex-wrap w-full gap-2 px-3 py-2.5 border rounded-lg cursor-pointer bg-n-alpha-black2 min-h-[42px]` (126-134). **It is a `<div>` with `@click`, so it is not keyboard-focusable and has no `role`/`tabindex`.** Chip remove affordances are bare `<span class="… i-lucide-x …" @click>` (145-148) — also not buttons, also not reachable by keyboard. `border-*` is used for state here while `ComboBox` uses `outline-*` for the same semantic states.
`toggleOption` / `removeTag` mutate `selectedValues.value` in place with `push`/`splice` and then emit the same array reference (73-89), so parents holding the same array see mutations before the emit.

### 4.5 ReorderableMultiSelect (`combobox/ReorderableMultiSelect.vue`)

Drag-ordered, `max`-capped multi-select, well commented (10-11, 13-14, 43, 52). Props: `options` (`[]`), `max` (`Number`, `3`), `label` (`''`), `addLabel` (`''`), `searchPlaceholder` (`''`), `emptyState` (`''`), `fallbackIcon` (`'i-lucide-file-text'`), `loading` (`false`), `disabled` (`false`), `serverSearch` (`false`) — 12-57. Emits `search` (59); `defineModel` `Array` (61). Slots: `counter` (144), `note` (294).
Reorder is HTML5 drag only — `@dragstart`/`@dragover.prevent`/`@dragend` (206-208), `cursor-grab`, `i-lucide-grip-vertical` (210-212). **No keyboard reorder path.** Drag state styling `ring-1 ring-inset ring-n-brand` (201-205) is the only `ring` focus-like treatment in the area. Skeleton rows while loading with `aria-busy="true"` (165-189). Slot-count pips at 148-153.
`<label class="text-sm font-medium text-n-slate-12">` (141) has **no `for`** and there is no id plumbing, so the visible label is not associated with anything. RTL: clean (no physical utilities).

### 4.6 Checkbox (`components-next/checkbox/Checkbox.vue`)

| Prop | Type | Default | Line |
|---|---|---|---|
| `indeterminate` | `Boolean` | `false` | 3-6 |
| `disabled` | `Boolean` | `false` | 7-10 |

`defineModel('modelValue')` `Boolean`, `false` (15-18). Emits `change` with the raw DOM event (20-23).
Appearance: `appearance-none` native input plus two overlaid inline `<svg>`s driven by `peer-checked:` / `peer-indeterminate:` (37-61). Classes at 33: `peer absolute inset-0 z-10 h-4 w-4 disabled:opacity-50 appearance-none rounded border border-n-slate-6 ring-transparent transition-all duration-200 checked:border-n-brand checked:bg-n-brand dark:border-gray-600 dark:checked:border-n-brand indeterminate:border-n-brand indeterminate:bg-n-brand hover:enabled:bg-n-blue-border cursor-pointer`. Note `dark:border-gray-600` — a raw Tailwind grey, the only non-`n-` colour token in any primitive in this area. Size is fixed `w-4 h-4` (27) with no size prop.

- **No focus state.** `ring-transparent` (33) is set but no `focus:`/`focus-visible:` variant ever changes it. A focused checkbox is visually identical to an unfocused one.
- **No accessible-name path.** No `id`, `label`, `name`, `value` or `ariaLabel` prop; no `v-bind="$attrs"` and no `inheritAttrs: false`, so anything a caller passes lands on the wrapper `<div class="relative w-4 h-4">` (27), never on the input. Callers who want a name must wrap the component in a `<label>` — most do (`components/widgets/conversation/ConversationCard.vue:144-145`, `components-next/Contacts/ContactsCard/ContactsCard.vue:139-143`, `components-next/captain/pageComponents/customTool/ParamRow.vue:92-96`, `routes/dashboard/settings/flows/components/NodeConfigPanel.vue:490-495`, `routes/dashboard/settings/data/NewImportDialog.vue:228-242`, `components-next/captain/assistant/PlaygroundTestSetup.vue:294-295,414-415,429-435,541-545`), but several do not and are therefore unnamed: `components-next/HelpCenter/ArticleCard/ArticleCard.vue:205`, `components-next/captain/assistant/ResponseCard.vue:171`, `components-next/captain/assistant/RuleCard.vue:70`, `components-next/captain/assistant/DocumentCard.vue:195`, `components-next/captain/assistant/ScenariosCard.vue:157`, `components-next/Conversation/ConversationCard/CardAvatar.vue:53`, `components-next/Conversation/ConversationCard/ConversationCardExpanded.vue:88`, `components-next/Contacts/ContactsForm/CreateSegmentDialog.vue:103`.
- RTL: `left-1/2 … -translate-x-1/2` (40, 53) is physical but geometrically centred, so it is direction-safe in practice.

### 4.7 Switch (`components-next/switch/Switch.vue`)

**No props at all.** `defineModel` `Boolean`, `false` (8-11); emits `change` (4).
Root is a `<button type="button" role="switch" :aria-checked="modelValue">` (20-26) with `h-4 w-7` track, `bg-n-brand` / `bg-n-slate-6` (23) and a `h-3 w-3` knob that widens to `18px` while pressed (38). It is the **only** primitive here with a proper focus ring: `focus:outline-none focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2` (22).

Three defects:

1. **`change` emits the wrong value.** `updateValue` (13-16) sets `modelValue.value = !modelValue.value` and then emits `!modelValue.value` — i.e. the **pre-toggle** value. `components-next/CustomAttributes/CheckboxAttribute.vue:22-24` forwards that payload straight out as its `update` event, so the stale value propagates. Handlers that ignore the argument and read the model instead are unaffected (`routes/dashboard/settings/account/components/AudioTranscription.vue:32-36`), which is why this has not surfaced.
2. **No `disabled` prop and no disabled styling.** Four call sites pass `:disabled` — `components-next/captain/pageComponents/customTool/CustomToolCard.vue:116`, `components-next/captain/assistant/ScenariosCard.vue:179`, `routes/dashboard/settings/security/components/SamlSettings.vue:182`, `switch/Switch.story.vue:52`. Attribute fallthrough puts it on the root `<button>`, so interaction *is* blocked, but no class reacts to it: a disabled Switch is pixel-identical to an enabled one.
3. **One shared accessible name.** `<span class="sr-only">{{ t('SWITCH.TOGGLE') }}</span>` (28) — `"Toggle switch"` (`i18n/locale/en/components.json:37-39`). Every switch on a page announces the same name and there is no prop to change it.

RTL: handled with `ltr:`/`rtl:` pairs (30, 33-34); line 34 `'ltr:translate-x-0 rtl:translate-x-0'` is a redundant pair.

### 4.8 RadioCard (`components-next/radioCard/RadioCard.vue`)

| Prop | Type | Default | Line |
|---|---|---|---|
| `id` | `String` | **required** | 6-9 |
| `name` | `String` | `''` | 10-13 |
| `label` | `String` | **required** | 14-17 |
| `description` | `String` | **required** | 18-21 |
| `isActive` | `Boolean` | `false` | 22-25 |
| `disabled` | `Boolean` | `false` | 26-29 |
| `disabledLabel` | `String` | `''` | 30-33 |
| `disabledMessage` | `String` | `''` | 34-37 |
| `beta` | `Boolean` | `false` | 38-41 |

Emits `select` with `props.id`, suppressed when already active or disabled (44-52). Composes `Label` for the disabled badge (`color="amber" compact`) and the Beta badge (`color="blue" compact`, `GENERAL.BETA`) — 71-72. Default slot for extra content (88). `description` is replaced by `disabledMessage` when disabled (86).
Card: `rounded-xl outline outline-1 … bg-n-solid-1` with `outline-n-blue-9` active / `outline-n-weak` idle / `hover:outline-n-strong` (58-63) and `opacity-50 cursor-not-allowed` when disabled.
Accessible name: the whole card is a `<label :for="id">` wrapping a native `<input type="radio" :id="id">` (56-57, 74-83), so the name is the card content. Good.
Focus: `focus-within:has-[:focus-visible]:ring-2 focus-within:has-[:focus-visible]:ring-n-strong` (58) — works, but a doubled-up selector, and `ring-n-strong` is a neutral border colour rather than the brand focus colour used elsewhere.

**Radio grouping is broken by default.** `:name="name || id"` (78) means that without an explicit `name` every card becomes its own single-member group — no native single-selection, no arrow-key traversal. Of the 10 consumer files, **only** `components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue:195` passes `name="auto-resolve-mode"`. The others (`.../AssistantAudienceForm.vue:161,168`, `.../AssistantScheduleForm.vue:49`, `components-next/HelpCenter/Pages/PortalSettingsPage/PortalLayoutContentSettings.vue:165,185`, `routes/dashboard/settings/automation/components/AutomationRunTypeSelector.vue`, `routes/dashboard/settings/profile/Index.vue`, `routes/dashboard/settings/integrations/Slack/SlackMessageMode.vue`, `routes/dashboard/settings/assignmentPolicy/pages/components/AgentAssignmentPolicyForm.vue`, `routes/dashboard/settings/inbox/components/SenderNameExamplePreview.vue`, `.../LockToSingleConversationPreview.vue`) and `radioCard/RadioCard.story.vue:20-33` do not.

RTL: `ltr:pl-4 rtl:pr-4 ltr:pr-6 rtl:pl-6` (58) — correct but should be `ps-4 pe-6`; also redundant with the `p-4` on the same line.

### 4.9 ColorPicker (`components-next/colorpicker/ColorPicker.vue`)

One prop `modelValue` (`String`, `''`) (8-13); emits `update:modelValue` with `e.hex` (29-31). Wraps `Chrome` from `@lk77/vue3-color` (2) with `disable-alpha`, closed by `OnClickOutside` (38). Trigger is a `Button color="slate" icon="i-lucide-pipette" trailing-icon` overridden with `!px-3 !py-3 [&>svg]:w-4 [&>svg]:h-4` (39-53), showing a swatch `<span>` plus the hex string.
- No `disabled`, no `label`, no error/message, no `aria-label`, no `aria-expanded`.
- `pickerRef` (33) is declared and bound (37) but never read.
- Has a `<style scoped lang="scss">` block (65-100) of `:deep()` overrides for the third-party widget, including a physical `left-3 relative` (83) with no RTL counterpart. This and `ConfirmButton` are the only two scoped-style files in the area.
- 2 consumers: `components-next/HelpCenter/Pages/PortalSettingsPage/PortalBaseSettings.vue`, `routes/dashboard/settings/inbox/Settings.vue`.

---

## 5. Label family

### 5.1 Label (`components-next/label/Label.vue`)

| Prop | Type | Default | Validator | Line |
|---|---|---|---|---|
| `label` | `Object \| String` | **required** | — | 5-8 |
| `compact` | `Boolean` | `false` | — | 9-12 |
| `color` | `String` | `'slate'` | `['slate','amber','teal','ruby','blue','iris']` | 13-18 |

Colour map (21-28) — note this is a **sixth, independent colour vocabulary** from `Button`'s five (`iris` here, `teal` in both, no `iris` in Button):

| `color` | classes |
|---|---|
| `slate` | `bg-n-label-color outline-n-label-border text-n-slate-12` |
| `amber` | `bg-n-amber-2 outline-n-amber-4 text-n-amber-11` |
| `teal` | `bg-n-teal-2 outline-n-teal-4 text-n-teal-11` |
| `ruby` | `bg-n-ruby-2 outline-n-ruby-4 text-n-ruby-11` |
| `blue` | `bg-n-blue-2 outline-n-blue-4 text-n-blue-11` |
| `iris` | `bg-n-iris-2 outline-n-iris-4 text-n-iris-11` |

Polymorphic input: a `String` renders title only; an `Object` uses `.title`, `.description` (as the native `title` tooltip, 49) and `.color` (an arbitrary CSS colour rendered as an inline `:style` swatch, 60). Sizes: `compact` → `px-1.5 h-6 gap-1 rounded-md` + `text-label-small`; default → `px-2.5 h-8 gap-1.5 rounded-lg` + `text-label !font-420` (53, 65). Slots: `icon` (shown only when there is no `label.color`, 62) and `action` (69).
`:style="{ background: labelColor }"` (60) is one of the few places inline style is unavoidable (user-chosen colour). Not interactive, so no focus story. RTL: clean.

### 5.2 LabelItem (`components-next/label/LabelItem.vue`)

Props `label` (`Object`, `null`), `isHovered` (`Boolean`, `false`) (4-13); emits `remove`, `hover` (15). Hover state is lifted to the parent deliberately, with a comment explaining the flicker fix (22-26). The remove control is a `Button` with shorthand `slate xs faded` and heavy overrides including `ltr:rounded-r-md rtl:rounded-l-md ltr:rounded-l-none rtl:rounded-r-none` (45-54).
Reveal animation is `w-0` → `w-6` on the container (42-43), so the remove button is **width-clipped, not hidden**, and stays in the tab order while invisible. It has `icon="i-lucide-x"` and no `aria-label`. Does **not** reuse `Label.vue` — it re-implements the chip (31-39) with `bg-n-alpha-2 h-7` and a `:style` swatch.
RTL: `ltr:mr-px rtl:ml-px` (38), `ltr:left-1 rtl:right-1` (42) — pairs, not logical utilities.

### 5.3 AddLabel (`components-next/label/AddLabel.vue`)

One prop `labelMenuItems` (`Array`, `[]`) (7-12); emits `updateLabel` (14). **Trigger is a raw `<button>`** (23-32), not `Button`, with `outline-dashed outline-1 outline-n-slate-6 h-6 hover:bg-n-alpha-2` — a dashed "add" affordance the `Button` primitive cannot express. Text comes from `LABEL.TAG_BUTTON` = `"tag"` (`i18n/locale/en/components.json:40-42`). No `type="button"`, no `aria-expanded`, no focus style beyond the global `button` base. Delegates the menu to `DropdownMenu` with `show-search` and a `thumbnail` slot (33-47). RTL: `ltr:left-0 rtl:right-0` (38).

---

## 6. Design-system context the primitives sit in

| Thing | Where | Relevance |
|---|---|---|
| Typography utilities `.text-body-main`, `.text-body-para`, `.text-heading-1/2/3`, `.text-label`, `.text-label-small`, `.text-button`, `.text-button-small` | `assets/scss/_woot.scss:69-145` (documented in a table at 74-85) | **`text-button` / `text-button-small` exist and `Button.vue` does not use them** — `Button.vue:177-182` hand-rolls `text-xs` / `text-sm` / `text-sm font-medium` / `text-base` instead. `Input.vue:111` and `Label.vue:65` *do* use `text-heading-3` / `text-label`; `InlineInput.vue:105` hand-rolls `text-sm font-medium` for the same role. |
| `.field-base`, `.field-disabled`, `.field-error` | `assets/scss/_base.scss:66-78` | The canonical field appearance. `Input.vue:140` re-implements it inline rather than applying `.field-base`; `Input.vue:56-58` re-implements `.field-error`. |
| Global `input[type]` / `select` / `textarea` styling | `assets/scss/_base.scss:81-121` | Applies to every raw field that does not carry `.reset-base`. This is what the 134 raw `<input>`s and 17 raw `<select>`s render as. `Input.vue:140`, `InlineInput.vue:121` and `ComboBoxDropdown.vue:87` opt out with `reset-base`. |
| Global `button` base | `assets/scss/_base.scss:43-46` — `inline-block text-center align-middle cursor-pointer text-sm m-0 py-1 px-2.5 … rounded-lg disabled:opacity-50` | Every raw `<button>` in the dashboard inherits this, which is why raw buttons look roughly right and the bypasses have gone unnoticed. |
| Colour tokens | `theme/colors.js:105-290` — `n-slate`, `n-iris`, `n-blue`, `n-ruby`, `n-amber`, `n-teal`, `n-gray`, `n-violet` 1-12 scales, plus `n-brand`, `n-surface-*`, `n-solid-*`, `n-alpha-*`, `n-weak`/`n-container`/`n-strong`, `n-button-color/hover`, `n-label-color/border` | **There is no `n-red-*` scale** — see §4.1 defect 1. |
| Font weights `420/440/460/520/620` | `tailwind.config.js:49-55` | Used by the typography utilities and `Label.vue:65`. |

---

## 7. Raw-markup bypasses in the dashboard

Counts over `app/javascript/dashboard/**/*.vue`.

### 7.1 Raw `<button>` — 127 occurrences

Excluding the 7 that are the internals of a primitive (`switch/Switch.vue:20`, `label/AddLabel.vue:23`, `button/Button.vue:240`, plus `tabbar`, `breadcrumb`, `banner`, `vertical-tabs` which are separate primitives), these are real bypasses:

| Area | Files:lines |
|---|---|
| Settings — Lynomia extensions | `routes/dashboard/settings/flows/components/NodePalette.vue:34` (draggable palette item: `cursor-grab` + `draggable="true"`, not expressible via `Button`), `routes/dashboard/settings/flows/FlowBuilder.vue:354`, `routes/dashboard/settings/flows/Index.vue:226`, `routes/dashboard/settings/commerce/ProviderPicker.vue:70` (card-shaped radio-like option with `enabled:hover:border-n-strong disabled:opacity-60`), `routes/dashboard/settings/commerce/StoreDialog.vue:132`, `routes/dashboard/settings/data/components/ImportLogSection.vue:47` |
| Settings — core | `settings/macros/MacroProperties.vue:91,118`, `settings/profile/AudioAlertTone.vue:85`, `settings/profile/AccessToken.vue:49`, `settings/captain/components/ModelDropdown.vue:97`, `settings/canned/Index.vue:185`, `settings/inbox/settingsPage/components/CSATStarInput.vue:22`, `.../CSATEmojiInput.vue:25`, `settings/inbox/channels/Facebook.vue:178`, `settings/security/components/SamlAttributeMap.vue:18` |
| Onboarding | `onboarding/inbox-setup/InboxChannelsFooter.vue:61`, `.../InboxChannelsDialog.vue:161`, `.../ChannelRow.vue:49` |
| Help center | `helpcenter/components/ArticleSearch/ArticleSearchResultItem.vue:52` |
| `components/ui` (legacy) | `ui/Tabs/Tabs.vue:72,88`, `ui/DatePicker/components/CalendarAction.vue:52,59`, `.../CalendarDateRange.vue:28`, `.../CalendarMonth.vue:71`, `.../CalendarYear.vue:72`, `.../DatePickerButton.vue:61`, `ui/Dropdown/DropdownListItemButton.vue:23`, `ui/Label.vue:103` |
| Conversation / editor | `components/widgets/WootWriter/VideoEmbedInput.vue:140`, `.../SlashCommandMenu.vue:204`, `.../EditorModeToggle.vue:71`, `components/widgets/BackButton.vue:30`, `components/widgets/ShowMore.vue:38`, `components/widgets/conversation/ConversationHeader.vue:149`, `.../TagAgents.vue:135`, `.../conversationCardComponents/CardLabels.vue:82`, `.../conversation/LabelSuggestion.vue:169`, `.../WhatsappTemplates/TemplatesPicker.vue:102,119`, `.../ContentTemplates/ContentTemplatesPicker.vue:77,97` |
| Commerce (Lynomia) | `components/widgets/conversation/commerce/CommerceOverview.vue:170,207`, `.../CommerceOrderSearch.vue:70` (disclosure toggle with `:aria-expanded`), `.../CommerceOrderItem.vue:94` |
| Search / auth / app | `modules/search/components/MessageContent.vue:111,119`, `.../TranscribedText.vue:29,37`, `.../RecentSearches.vue:94`, `components/auth/SessionLimitOverlay.vue:116`, `components/auth/MfaVerification.vue:165`, `components/app/LowBackupCodesBanner.vue:102,110`, `components/ChannelSelector.vue:37`, `components/Accordion/AccordionItem.vue:36` |
| Widget preview | `modules/widget-preview/components/WidgetFooter.vue:45`, `.../Widget.vue:206` |
| Other primitives | `components-next/year-in-review` (11), `components-next/message` (11), `components-next/captain` (9), `components-next/sidebar` (8), `components-next/emoji-icon-picker` (5), `components-next/copilot` (3), `components-next/dropdown-menu` (2), `components-next/SharedAttachments` (2), `components-next/Companies` (2), `components-next/AssignmentPolicy` (2), 1 each in `filter`, `changelog-card`, `HelpCenter`, `Contacts`, `Accordion` |

The recurring reasons raw `<button>` is chosen: (a) a card/row/tile shape with its own border and multi-line content, which `Button`'s height-based size scale cannot express (`ProviderPicker.vue:70`, `ChannelRow.vue:49`, `ArticleSearchResultItem.vue:52`); (b) `draggable="true"` + `cursor-grab` (`NodePalette.vue:34`); (c) a disclosure toggle needing `:aria-expanded` (`CommerceOrderSearch.vue:70`).

### 7.2 Raw `<input>` — 134 occurrences, by `type`

| `type` | Count | Notable sites |
|---|---|---|
| `text` (explicit) | 57 | `settings/inbox/channels/Twilio.vue:124,142,159,173,190,203,215,229`; `.../BandwidthSms.vue:84,101,118,135,152,167`; `.../CloudWhatsapp.vue:99,114,131,150,169`; `.../Line.vue:86,103,117,131`; `.../Api.vue:83,100`; `.../360DialogWhatsapp.vue:77,92,109`; `.../Telegram.vue:80`; `settings/inbox/Settings.vue:981,1041,1241,1252,1263,1274`; `settings/inbox/ImapSettings.vue:115,160`; `settings/inbox/SmtpSettings.vue:167`; `settings/integrations/Webhooks/WebhookForm.vue:108,121,131,166`; `settings/agents/AddAgent.vue:115`; `conversation/contact/ContactForm.vue:326,336,430` |
| `checkbox` | 36 | **Inside `components-next` itself:** `captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue:134,138,142,146`; `captain/pageComponents/assistant/AssistantForm.vue:146,153,160`; `Campaigns/.../LiveChatCampaignForm.vue:282,289`. Elsewhere: `settings/profile/NotificationCheckBox.vue:46` (re-implements the whole checkbox with `checked:after:content-['✓']`), `settings/teams/TeamForm.vue:163`, `settings/labels/AddLabel.vue:107`, `settings/labels/EditLabel.vue:111`, `settings/customRoles/component/CustomRoleModal.vue:198`, `settings/profile/MfaSetupWizard.vue:304`, `components/CustomAttribute.vue:211` |
| `search` | 9 | `modules/search/components/SearchInput.vue:105`, `components/ui/Dropdown/DropdownSearch.vue:33`, `components-next/dropdown-menu/DropdownMenu.vue:146`, `components-next/Companies/CompanyDetail/CompanyCustomAttributes.vue:111`, `components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue:132`, `components-next/NewConversation/components/WhatsAppOptions.vue:95` |
| `file` | 7 | `components/widgets/AutomationFileInput.vue:52`, `components-next/avatar/Avatar.vue:293`, `components-next/captain/pageComponents/document/DocumentForm.vue:163`, `components-next/Contacts/ContactsForm/ContactImportDialog.vue:126` — no file-input primitive exists |
| `radio` | 7 | `components/widgets/conversation/EmailTranscriptModal.vue:115,133,145`, `settings/billing/components/CreditPackageCard.vue:49`, `settings/inbox/components/InputRadioGroup.vue:30` (legacy, with its own `<style lang="scss" scoped>`) |
| implicit text (no `type`) | 5 | `components-next/Contacts/ContactsForm/ContactsForm.vue:368`, `components-next/filter/inputs/{SingleSelect,MultiSelect,FilterSelect}.vue:163/166/123`, `components-next/captain/assistant/AssistantPlayground.vue:225` |
| `range` | 3 | `components-next/audio/AudioPlayer.vue:125`, `components-next/Calls/CallRecordingPlayer.vue:125`, `components-next/message/chips/Audio.vue:193` — no slider primitive exists |
| `:type` / `:inputType` (dynamic) | 4 | |
| `date` / `tel` / `number` / `email` / `hidden` | 1-2 each | |

The `text` cluster is one coherent pattern: every inbox-channel creation form uses the legacy `<label>{{ label }}<input v-model=…><span class="message">` idiom and relies on the global `_base.scss` field styling — e.g. `settings/inbox/channels/Twilio.vue:121-131`. 6 of the 134 are the legitimate internals of the primitives themselves (`input/Input.vue:117`, `inline-input/InlineInput.vue:111`, `checkbox/Checkbox.vue:28`, `input/ChoiceToggle.vue:34`, `radioCard/RadioCard.vue:74`, `combobox/ComboBoxDropdown.vue:82`).

### 7.3 Raw `<select>` — 17 occurrences

`settings/agents/AddAgent.vue:127`; `settings/agents/EditAgent.vue:175,189`; `settings/automation/components/AutomationInstantTrigger.vue:77`; `settings/account/Index.vue:193`; `settings/integrations/Slack/SelectChannelWarning.vue:92`; `settings/attributes/EditAttribute.vue:203`; `settings/attributes/AddAttribute.vue:172,219`; `settings/inbox/components/SingleSelectDropdown.vue:34`; `settings/inbox/channels/Website.vue:154`; `settings/inbox/channels/Sms.vue:29`; `settings/sla/SlaTimeInput.vue:105`; `onboarding/account-details/OnboardingFormSelect.vue:16`; `components/widgets/conversation/FilterItem.vue:41`; plus the two primitive internals (`select/Select.vue:50`, `input/DurationInput.vue:82`).

`settings/inbox/components/SingleSelectDropdown.vue:34` hard-codes `id="dropdown-select"`, so it emits duplicate DOM ids if rendered more than once on a page.

---

## 8. Cross-cutting inconsistencies

| # | Issue | Evidence |
|---|---|---|
| 1 | `Select`'s error outline uses a non-existent token, so the error state renders nothing | `select/Select.vue:58` (`outline-n-red-9`) vs `theme/colors.js:105-290` (only `n-ruby-*`); only occurrence of `n-red-` in `app/javascript` |
| 2 | `Select` accepts `error` text and never renders it | `select/Select.vue:32-35`; cf. `input/Input.vue:146-152`, `combobox/ComboBox.vue:131-140` |
| 3 | `Select` has no RTL handling; chevron overlaps text | `select/Select.vue:54` (`pr-10`), `:93` (`right-0 … pr-3`) |
| 4 | `Switch` emits the pre-toggle value on `change` | `switch/Switch.vue:13-16`; propagated by `components-next/CustomAttributes/CheckboxAttribute.vue:22-24` |
| 5 | `Switch` has no `disabled` prop and no disabled styling, yet 4 call sites pass `disabled` | `switch/Switch.vue:1-17`; `captain/pageComponents/customTool/CustomToolCard.vue:116`, `captain/assistant/ScenariosCard.vue:179`, `routes/dashboard/settings/security/components/SamlSettings.vue:182` |
| 6 | `Button`'s focus-visible state never draws an outline or ring | `button/Button.vue:104-155` (only `brightness`/`bg`/`underline`), `:194` (`outline-transparent` in 4 of 5 variants) |
| 7 | `Checkbox` has no focus indicator at all | `checkbox/Checkbox.vue:33` (`ring-transparent`, no `focus:` variant) |
| 8 | `Input` loses its focus outline in the error state | `input/Input.vue:56` vs `:58` |
| 9 | `InlineInput` removes the focus outline and replaces nothing | `inline-input/InlineInput.vue:121` (`outline-none outline-0`) |
| 10 | 224 of 248 icon-only `Button`s have no `aria-label`; 140 of those have no tooltip either | §2.6 |
| 11 | `Checkbox` cannot receive an accessible name — attrs land on the wrapper `div` | `checkbox/Checkbox.vue:27` (root) and no `inheritAttrs:false`; 8 unnamed call sites listed in §4.6 |
| 12 | `InlineInput`'s `<label for>` is empty unless the caller passes `id`; `Input` auto-generates one | `inline-input/InlineInput.vue:25-28,103` vs `input/Input.vue:36-37` |
| 13 | `Input` applies `$attrs` to both the wrapper and the field (no `inheritAttrs:false`) | `input/Input.vue:107,119` |
| 14 | `RadioCard` defaults `name` to `id`, so every card is its own radio group | `radioCard/RadioCard.vue:78`; only 1 of 10 consumers passes `name` |
| 15 | `ChoiceToggle`'s radios have no `name` | `input/ChoiceToggle.vue:34-40` |
| 16 | `ComboBox`/`TagMultiSelectComboBox`/`SelectMenu`/`ReorderableMultiSelect` have no keyboard operation (no `@keydown` anywhere), and `ComboBox` has no `role="combobox"`/`aria-expanded`/`aria-activedescendant` | `combobox/ComboBox.vue`, `combobox/ComboBoxDropdown.vue:91-123`, `selectmenu/SelectMenu.vue`, `combobox/ReorderableMultiSelect.vue:206-208` |
| 17 | `TagMultiSelectComboBox` trigger and chip-remove controls are `div`/`span` with `@click` — not focusable | `combobox/TagMultiSelectComboBox.vue:126-134,145-148` |
| 18 | `LabelItem`'s remove button is width-clipped (`w-0`), not hidden, so it stays in the tab order while invisible and has no `aria-label` | `label/LabelItem.vue:42-54` |
| 19 | Two state-styling idioms for the same semantics: `outline-*` in `Input`/`Select`/`ComboBox`/`RadioCard`, `border-*` in `TagMultiSelectComboBox`/`ReorderableMultiSelect` | `input/Input.vue:140`, `combobox/ComboBox.vue:109` vs `combobox/TagMultiSelectComboBox.vue:126-133`, `combobox/ReorderableMultiSelect.vue:159` |
| 20 | Dead `focused` / `focus` class names that match no CSS rule | `combobox/ComboBox.vue:111`, `input/Input.vue:128` |
| 21 | `Button` hand-rolls font sizes although `.text-button` / `.text-button-small` exist | `button/Button.vue:177-182` vs `assets/scss/_woot.scss:138-147` |
| 22 | `Input` re-implements `.field-base` / `.field-error` inline instead of applying them | `input/Input.vue:56-58,140` vs `assets/scss/_base.scss:66-78` |
| 23 | Scoped/custom CSS in two primitives, against the Tailwind-only house rule | `button/ConfirmButton.vue:85-100`, `colorpicker/ColorPicker.vue:65-100` |
| 24 | RTL is done with `ltr:`/`rtl:` pairs almost everywhere instead of logical utilities; `ComboBoxDropdown` is the one file that uses `start-*`/`ps-*`/`pe-*` | `ComboBoxDropdown.vue:75,80,87` vs `RadioCard.vue:58`, `LabelItem.vue:38,42`, `PhoneNumberInput.vue:174,189,201,212`, `Switch.vue:30,33`, `SelectMenu.vue:63-67`, `AddLabel.vue:38` |
| 25 | 21% of `Button` call sites (178/840), 46% of `ComboBox` (16/35), 24% of `Select` (5/21) and 15% of `Input` (23/150) need `!important` to get the geometry they want | §2.9, §3.1, §4.1, §4.3 |
| 26 | `Select` consumers all repeat the same width workaround because attrs hit the `w-fit` wrapper | `class="!w-full [&>select]:w-full"` at `ReportCaptainMessageDialog.vue:91`, `CommerceOrderActions.vue:412,423`, `CommercePanel.vue:386`, `NewImportDialog.vue:188` |
| 27 | `DurationInput` has a fragment root and a raw `<select>`, forcing `[&>select]:` hacks on consumers | `input/DurationInput.vue:71-96`; `AssignmentPolicy/components/ExclusionRules.vue:137`, `.../FairDistribution.vue:88` |
| 28 | `Input` drops `min` for `type="number"` while keeping `max` | `input/Input.vue:134-139`; live call site `components-next/recipes/RecipeInputs.vue:117-122` |
| 29 | `Input` emits DOM events for `input`/`blur`/`focus`; `InlineInput` emits `event.target.value` for the same event names | `input/Input.vue:62-95` vs `inline-input/InlineInput.vue:70-81` |
| 30 | `ConfirmButton` drops `Button`'s prop validators and does not set `inheritAttrs:false`, so caller attrs land on its wrapper `div` | `button/ConfirmButton.vue:5-18,49` |
| 31 | `Button.story.vue` documents a size that does not exist | `button/Button.story.vue:7` (`SIZES = ['default','sm','lg']`) vs `button/constants.js:3` (`['xs','sm','md','lg']`); `'default'` fails the validator and indexes nothing in `STYLE_CONFIG.sizes` |
| 32 | Six `EXCLUDED_ATTRS` entries are dead (declared props never appear in `$attrs`) | `button/constants.js:7-12` |
| 33 | No story for `Select`, `ColorPicker`, `Label`/`LabelItem`/`AddLabel`, `ButtonGroup`, `ChoiceToggle`, `DurationInput`, `ReorderableMultiSelect`, `ComboBoxDropdown`; story filename typo `Combox` | §1 |
| 34 | `components-next` bypasses its own `Checkbox` with raw `<input type="checkbox">` | `captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue:134,138,142,146`, `captain/pageComponents/assistant/AssistantForm.vue:146,153,160`, `Campaigns/.../LiveChatCampaignForm.vue:282,289` |
| 35 | Two colour vocabularies: `Button` = blue/ruby/amber/slate/teal; `Label` = slate/amber/teal/ruby/blue/iris | `button/constants.js:2` vs `label/Label.vue:17` |
| 36 | `Checkbox` uses a raw Tailwind grey, the only non-`n-` colour in the area | `checkbox/Checkbox.vue:33` (`dark:border-gray-600`) |
| 37 | `Button` sets no default `type`, so any `Button` inside a `<form>` without an explicit `type` is a submit button | `button/Button.vue:240`; 136 occurrences of `type="button"` in dashboard `.vue` files; 63 files contain both a `<form>` and a `Button`/`NextButton` |
| 38 | `ColorPicker` declares and binds `pickerRef` but never reads it | `colorpicker/ColorPicker.vue:33,37` |
| 39 | `SelectMenu` has a pass-through computed with no purpose | `selectmenu/SelectMenu.vue:31` |
| 40 | `TagMultiSelectComboBox` mutates the parent's array in place before emitting, and freezes `disabled` in `defineExpose` | `combobox/TagMultiSelectComboBox.vue:73-89,107-111` |
| 41 | `SingleSelectDropdown` emits a hard-coded DOM id | `routes/dashboard/settings/inbox/components/SingleSelectDropdown.vue:34` |
| 42 | `Button` is imported under two names (`Button`, `NextButton`) from the same file, splitting every grep | 544 `<Button>` + 296 `<NextButton>` call sites; e.g. `modules/search/components/SearchView.vue:21` |

---

## 9. What a modernization should reuse rather than rebuild

- **`Button`'s token tables.** `button/constants.js` + the `STYLE_CONFIG` maps (`Button.vue:100-195`) are a complete, exhaustive variant × colour × size matrix behind 840 call sites. Keep the five colours, five variants, four sizes and three justifies and keep the shorthand boolean attribute API — removing shorthands would silently change hundreds of buttons (`slate xs faded` at `label/LabelItem.vue:49-52` is the normal idiom, not an exception).
- **`Button`'s derived `isIconOnly` and the separate `iconOnly` size table** (`Button.vue:164-169,209,213`). This is how every square icon button in the product gets its dimensions.
- **The `icon` prop's `String | Object | Function` polymorphism plus `icon/Icon.vue`** (`icon/Icon.vue:8-14`) — call sites pass Iconify class strings, render functions and VNodes.
- **`Input`'s `uniqueId` fallback** (`input/Input.vue:36-37`). It is the one correct label-association pattern in the area; extend it to `InlineInput`, `Checkbox`, `Select` and `ReorderableMultiSelect` instead of inventing a new one.
- **`Input`'s `message` + `messageType` contract** (`input/Input.vue:15-21,42-51,146-152`). `info`/`error`/`success` is already the dashboard's validation-feedback vocabulary; `Select` should adopt it rather than keep its own dead `error` string.
- **`ComboBoxDropdown`** (`combobox/ComboBoxDropdown.vue`) is the shared dropdown body behind `ComboBox`, `TagMultiSelectComboBox` and `ReorderableMultiSelect`, and it is already the most RTL-correct and most `role`-annotated file here. Add keyboard navigation and `aria-activedescendant` **to this one file** and all three consumers improve at once.
- **`Switch`'s focus-ring recipe** (`switch/Switch.vue:22`: `focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2`). It is the only correct focus treatment in the area — promote it to a shared token and apply it to `Button`, `Checkbox`, `Input`, `Select`.
- **`RadioCard`'s full prop surface** (`radioCard/RadioCard.vue:5-42`), including `disabled` + `disabledLabel` + `disabledMessage` + `beta`. The disabled-with-reason and Beta-badge affordances are product behaviour across 10 settings surfaces and must survive.
- **`Label`'s polymorphic `label` prop** (`label/Label.vue:30-42`) — string or `{title, description, color}`, with the arbitrary user colour rendered as an inline swatch. Any chip redesign must keep both shapes and the `compact` size.
- **`PhoneNumberInput`'s validation and country plumbing** (`phonenumberinput/PhoneNumberInput.vue:45-61,120-159`): Vuelidate rules, `libphonenumber-js` round-tripping, `shared/constants/countries.js`, `getActiveCountryCode`/`getActiveDialCode`. Rebuild the chrome, not this.
- **`DurationInput`'s unit-rounding watcher** (`input/DurationInput.vue:59-68`) and `DURATION_UNITS` (`input/constants.js:1-5`). The comment explains a real data-loss bug it fixes.
- **`ReorderableMultiSelect`'s capped-ordered-selection model** (`combobox/ReorderableMultiSelect.vue:61,78-111`) and its loading skeleton with `aria-busy` (165-189). Add a keyboard reorder path alongside the drag handlers; do not replace them.
- **`ConfirmButton`'s two-step destructive flow** (`button/ConfirmButton.vue:22-45`) including the blur-reset and 400 ms auto-reset. Behind `Dialog.vue` and `AccessToken.vue`.
- **The existing typography and field utilities** — `.text-button`, `.text-button-small`, `.text-label`, `.text-heading-3`, `.field-base`, `.field-error`, `.field-disabled` (`assets/scss/_woot.scss:69-150`, `assets/scss/_base.scss:66-78`). The modernization's job here is to make the primitives *use* these, not to define a parallel scale.
- **The `n-*` colour token set** (`theme/colors.js:105-290`). Fix `Select.vue:58` to `n-ruby-*`; do not add a `n-red-*` scale.
- **`ButtonGroup`'s press-scale wrapper** (`buttonGroup/ButtonGroup.vue:12-16`) is the hook a real segmented control should grow from — `has-[button:not(:disabled):active]` already works; it just needs shared corner rounding so call sites stop writing `ltr:!rounded-r-none`.
- **`reset-base`** (`assets/scss/_base.scss:81`) is the opt-out from global form CSS that lets a primitive own its appearance. Any new field primitive must carry it.
