# 00 — The design system Lynomia Chat already has

Phase 0 of the visual modernization. This is the inventory the rest of the phase builds on: what tokens
exist, what components exist, which of them are the real contract, and where the system contradicts
itself. The per-area evidence (file, line, call-site counts) lives in `audit/*.md`; this document is the
decision-grade summary.

**The headline: there is a real design system here, and it is younger than the product.** The `n-*`
colour layer, the `components-next/` primitives and the typography utilities are coherent and widely
adopted. What is missing is everything *between* colour and component — spacing, radius, elevation,
control height, z-index — and what is inconsistent is mostly the older layer that the new one has not
finished replacing. The modernization's job is to finish that replacement, not to start a third system.

---

## 1. Tokens

### 1.1 What is defined

| Layer | Where | State |
|---|---|---|
| Colour ramps | `_next-colors.scss` → `theme/colors.js` | **Complete.** 8 Radix 12-step ramps (`slate`, `iris`, `blue`, `ruby`, `amber`, `teal`, `gray`, `violet`), 137 CSS variables × light/dark, exposed to Tailwind with `<alpha-value>` so opacity modifiers work. ~5,200 call sites. |
| Semantic colour aliases | `theme/colors.js:105-290` | **Complete.** `n-surface-*`, `n-solid-*`, `n-alpha-*`, `n-weak`/`n-container`/`n-strong`, `n-button-color/hover`, `n-label-color/border`. |
| Typography | `_woot.scss:58-147` | **Defined, half-adopted.** 9 utilities (`text-heading-1/2/3`, `text-body-main/para`, `text-label`, `text-label-small`, `text-button`, `text-button-small`) with explicit line-height and letter-spacing. 635 call sites in 133 files — against 457 files still writing raw `text-xs`/`text-sm`. |
| Font weights | `tailwind.config.js:49-55` | Defined: `420/440/460/520/620`. |
| Breakpoints | `tailwind.config.js` | Defined, 7 steps including `xs:480` and `3xl:1900`. **Replaces** Tailwind's defaults. |
| Icons | `theme/icons.js` + `@egoist/tailwindcss-icons` | Defined: a 64-icon `woot` collection alongside Lucide and Phosphor. 1,861 call sites. |
| Animation | `tailwind.config.js` | 5 project keyframes. **Replaces** Tailwind's defaults. |
| Field appearance | `_base.scss:66-78` | `.field-base`, `.field-disabled`, `.field-error` — plus `reset-base` as the documented opt-out from the global `input`/`select`/`textarea` styling. |

### 1.2 What is **not** defined — the actual gap

`tailwind.config.js` configures `screens`, `fontSize`, `colors`, `keyframes` and `animation`. It says
nothing about:

**`spacing` · `borderRadius` · `boxShadow` · `lineHeight` · `letterSpacing` · `zIndex` · `maxWidth` · `container`**

All eight fall through to Tailwind's defaults, which means the product has **no spacing scale, no radius
scale, no elevation scale, no control-height scale and no z-index scale of its own.** Every consequence
below follows from that one fact:

| Symptom | Count | Evidence |
|---|---|---|
| `backdrop-blur-[100px]` repeated as a de-facto token | 45× in 41 files | `audit/system-tokens.md` |
| `h-[3.25rem]` as the header height, because no `h-13` exists | 8× | same |
| Arbitrary `size-[…]` that restate an existing step | 13 of 18 | same |
| Arbitrary radii | 16 | same |
| Bespoke `shadow-[…]` + raw `box-shadow` | 7 + 39 | same |
| Arbitrary z-index, up to `z-[99999]` | 8 | same; the ladder runs `z-40 → z-50 → z-60 → z-[100] → z-[1000] → z-[9990] → z-[9999] → z-[10001]` (`audit/system-containers.md` #15) |
| Raw hex literals | 269 in 39 files | `audit/system-tokens.md` |
| Distinct centred-modal widths across 3 engines | **14** | `audit/system-containers.md` §11 |
| Distinct status/badge treatments | **60**, over 6 ramps, 5 radii, 7 heights, 7 type classes | `audit/system-data-display.md` §10 |

### 1.3 Token-layer defects that are bugs, not debt

1. **`_woot.scss:155-176` overrides every primary button's font-size, weight, case, radius — and font family, to Arial.** A global rule defeating the component's own tokens.
2. **`.bg-n-brand/10` and `/20` are redefined as gradients**, which breaks the opacity modifier for those two values only.
3. **`n-brand` and `n-black` are literal hex, not CSS variables**, so they cannot respond to dark mode or to white-labelling.
4. **Four unrelated brand/accent colours coexist**: `#2781F6`, `#0d2148→#5185eb`, `#2c3e50→#3498db`, `#2f6fe4`, `#6366f1`.
5. **Two private token namespaces shadow the public one**: `--sb-*` (578 lines of scoped CSS in `Sidebar.vue`) and `--cw-*` (489 lines in `ConversationView.vue`). The sidebar's block also re-points `--text-n-slate-9/10/11/12` from outside, so the colour tokens do not mean the same thing inside it.
6. **`Select.vue:58` uses `outline-n-red-9`, a token that does not exist** — there is no `n-red-*` ramp — so the select's error state renders nothing.

---

## 2. Components

### 2.1 The two layers

`components-next/` is the modern layer and the one to build on. `components/` is legacy and is being
retired — but it is not dead: the legacy `<woot-modal>` still backs 29 settings dialogs, and the legacy
table, pagination and banner each still have consumers.

### 2.2 The primitives, and their adoption

| Primitive | Call sites | Verdict |
|---|---|---|
| `button/Button.vue` (imported as both `Button` and `NextButton`) | 840 | **The contract.** Keep the variant × colour × size matrix and the shorthand boolean API wholesale. |
| `input/Input.vue` | 150 | Keep the `uniqueId` label association and the `message`/`messageType` contract. |
| `combobox/ComboBoxDropdown.vue` | behind 3 components | The most RTL-correct, most `role`-annotated file in the area. Fix keyboard nav **here** and three consumers improve at once. |
| `select/Select.vue` | 21 | Smallest and most broken: dead error text, no RTL, a non-existent token. |
| `label/Label.vue` | — | **The badge seed.** 6 validated colours, 2 sizes, icon + action slots, per-label colour dot, the only token-backed neutral. |
| `table/BaseTable*` | 15 tables / 18 rows / 66 cells | The slot contract is right; the capabilities (hover, selection, sort, loading, overflow) are missing. |
| `avatar/Avatar.vue` | 83 | Keep wholesale. Only the raw-hex palette and the physical `top`/`left` badge offsets need touching. |
| `spinner/Spinner.vue` | 89 | Keep. Its three camelCase SVG attributes are inert, so every spinner renders at stroke width 1. |
| `dialog/Dialog.vue` | 63 | Native `<dialog>` + `showModal()`. Keep the foundation and both stacking guards. |
| `side-panel/SidePanel.vue` | 8 | Keep the overlay choreography; it needs a focus trap. |
| `dropdown-menu/` | 41 + 10 | **Two unrelated menu systems.** `base/*` is the better one; converge the data-driven `DropdownMenu` onto it. |
| `popover/Popover.vue` | 8 | The **only** component in the product with a mobile adaptation. |
| `TeleportWithDirection.vue` | 10 | 28 lines, and the single correct answer to "teleported content loses `[dir]`". |
| `BaseSettingsHeader.vue` | 35 | **The page-header contract.** Its slots already cover every header need in settings. |
| `SettingsLayout.vue` | 36 | The page contract: `header`, `preBody`, `loading`, `body`, default. |

### 2.3 Where the primitives are bypassed

| Raw element | Count | The three real reasons |
|---|---|---|
| `<button>` | 127 (120 genuine bypasses) | (a) card/row/tile shapes `Button`'s height-based sizes cannot express; (b) `draggable="true"`; (c) a disclosure toggle needing `aria-expanded`. |
| `<input>` | 134 (128 genuine) | The inbox-channel forms are one coherent legacy idiom (57 text inputs). **36 raw checkboxes — 9 of them inside `components-next` itself.** No file-input, slider or radio-group primitive exists. |
| `<select>` | 17 (15 genuine) | No searchable-select primitive that call sites trust. |

21% of `Button` call sites, 46% of `ComboBox`, 24% of `Select` and 15% of `Input` need `!important` to
get the geometry they want. That number is the measure of how much the primitives under-serve their
callers — and it is the number a redesign should be judged against.

---

## 3. The five structural contradictions

These are the things that make the product look like several products. Each is one decision, not a
long tail.

1. **Three modal engines, fourteen widths.** `Dialog` (448–768), legacy `Modal` (600 fixed, no `max-width`, so it overflows below 600px), and full-screen one-offs. Destructive contact confirmations are rendered as anchored *popovers*.
2. **Sixty status treatments, no badge component.** Two near-identical per-domain badges (`CallStatusBadge`, `DeliveryStatusBadge`) prove the need and disagree with each other. One semantic — agent availability — has three different colour ramps (`-9` dots, `-10` dots, `-11` text).
3. **Five page-header components with five prop vocabularies and five type treatments**, plus nine pages that hand-roll a header and so will not pick up any redesign. Heading levels do not follow visual level; inbox detail pages have no `<h1>` at all.
4. **Six filter idioms, three chip components, five sort implementations, two live filter-type registries** (camelCase `next` providers beside snake_case legacy arrays, both consumed in the same files).
5. **The sidebar is a 1,650-line component with 578 lines of scoped CSS** that re-declares its own dark theme in raw hex, overrides the colour tokens from outside, and forces `text-sm` to `1.1rem !important` — so the typography scale does not apply inside the primary navigation.

---

## 4. Accessibility and RTL, as measured

Not an opinion: these come from the audits and from the baseline capture in `baseline/inventory.json`
(18 surfaces × 2 locales × 4 widths).

| Finding | Measure |
|---|---|
| Controls with no accessible name | **528 of 1,258 captured controls (42%)** — overwhelmingly icon-only buttons. The most frequent are delete (`i-woot-bin`), edit (`i-woot-edit-pen`) and settings (`i-woot-settings`). |
| Icon-only `Button`s with no `aria-label` | 224 of 248; **140 of those have no tooltip either**. |
| `Button` focus-visible | Draws no outline or ring in any variant. |
| `Checkbox` focus | No indicator at all; and it cannot receive an accessible name, because attrs land on the wrapper `div`. |
| `Input` focus | The outline is lost in the error state. `InlineInput` removes it and replaces nothing. |
| The one correct focus treatment | `Switch.vue:22` — `focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2`. Promote it. |
| Keyboard operation of `ComboBox` / `TagMultiSelect` / `SelectMenu` / `ReorderableMultiSelect` | **None** — no `@keydown` anywhere, no `role="combobox"`, no `aria-activedescendant`. |
| `DropdownMenu` | No `role="menu"`/`menuitem`, no arrow-key navigation. |
| Collapsed sidebar | Child items are reachable by hover only; sorting is `pointer-events-none` until hover. |
| Mobile sidebar | No scrim, no focus containment, no `inert` — a closed flyout keeps ~43 links tabbable — and navigating does not close it. |
| RTL method | `ltr:`/`rtl:` pairs almost everywhere instead of logical utilities. `ComboBoxDropdown` is the one file using `start-*`/`ps-*`/`pe-*`. |
| Live RTL bugs | `ltr:right-0 rtl:right-0` pins two menus to the physical right in both directions; five Help Center dropdowns use physical `left-0`/`right-0` with no direction variant; `Avatar`'s presence badge and the contacts filter dot use physical offsets. |
| Two sources of truth for direction | the `accounts/isRTL` store getter (`TeleportWithDirection`) vs a DOM query (`useDropdownPosition`). |

The baseline capture found **0 horizontal overflow and 0 wrong-direction documents** across all 144
captures, so the RTL problems are local to specific components rather than systemic to the page shell.

---

## 5. Mobile, as measured

There is **no sheet or bottom-drawer pattern anywhere** — zero matches for `bottomsheet`, `sheet`,
or `translate-y-full` across `dashboard/` and `shared/`. `Popover` is the only component with a
responsive branch. Concretely, at 390px today:

- Settings search and the "Learn more" link are `hidden sm:*` on **18 settings pages**, with no replacement.
- Campaigns has no list controls at all; Companies has search and sort but no filter.
- The legacy 600px modal overflows the viewport.
- Tables have no overflow wrapper (1 of 15 call sites wraps), no column hiding, no stacked fallback.

---

## 6. What to reuse rather than rebuild

The full lists are at the end of each `audit/*.md`. The load-bearing ones:

**Keep and extend**
`theme/colors.js` as the single integration point · the `n-*` CSS-variable architecture · the 9
typography utilities · `.field-base`/`.field-error`/`.field-disabled` + `reset-base` · `Button`'s token
tables and its `isIconOnly` derivation · `Input`'s `uniqueId` and `message`/`messageType` contract ·
`Label` as the badge seed · `BaseTable`'s slot contract (including the positional `header-${index}`
slot, which carries real SLA behaviour) · `Avatar` wholesale · `Dialog`'s native-`<dialog>` foundation
and its two stacking guards · `SidePanel`'s overlay choreography · `useDropdownPosition` as the one
positioner · `TeleportWithDirection` · `dropdown-menu/base/*` as the primitive layer ·
`BaseSettingsHeader` + `SettingsLayout`'s five slots · `v-model:search-query` as the search contract ·
`menuItems` as the declarative navigation tree · the gating stack (`resolvePermissions` /
`resolveFeatureFlag` / `Policy` / `usePolicy`) · the sidebar's three-strategy active-state resolver ·
`ConditionRow` + `operators.js` + `filterAttributeIcons.js` + the three providers ·
`AUDIENCE_QUERY_PARAM` as the cross-module contract.

**Promote to a token**
`backdrop-blur-[100px]` · `--cw-shadow` / `--cw-shadow-hover` as the elevation starting shape ·
`Switch`'s focus-ring recipe · the `bg-n-{c}-3` / `text-n-{c}-11` badge ramp (the majority of the 60
treatments, so the largest group migrates as a no-op) · the `bg-n-alpha-2` neutral chip as a deliberate
`subtle` variant, not a thing to flatten away · `max-w-5xl` + `px-6` as the page measure and
`max-w-2xl` as the single-column form measure · the semantic tone mapping that ~20 independent maps
already agree on: **teal = success/active/delivered/paid/approved · amber = pending/warning/draft ·
ruby = failed/missed/rejected · blue = in-progress/sent · slate = neutral/inactive · iris = read**.

**Fix in place, do not replace**
`Select.vue:58` → `n-ruby-*` · `Spinner`'s three camelCase SVG attributes · `Switch`'s pre-toggle emit ·
`AttributeBadge`'s computed-but-unbound colour · the sidebar's mount-time width reset · the duplicate
`#toggleConversationFilterButton` DOM id · `Alt+V`'s wrong route name · `customRoles`' wrong
`featureName`.

---

## 7. What this means for the phase

The gap is not that the system is bad. It is that **the system stops at colour.** Three quarters of
the inconsistency register — the 14 modal widths, the 60 badges, the 5 headers, the 16 radii, the 8
z-indexes, the `!important` rate — is downstream of the missing spacing/radius/elevation/height/z-index
scales and of the absence of three components (badge, skeleton, sheet).

So the first implementation commit is tokens, and the second is the page shell; everything after is
migration onto them. No page is redesigned before its feature parity manifest exists
(`baseline/inventory.json` + the per-surface sections of `01-product-visual-audit.md`), and no control
in that baseline may disappear.
