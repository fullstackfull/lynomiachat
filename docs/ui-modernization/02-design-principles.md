# 02 — Design principles for Lynomia Chat

Phase 2. These are the rules the implementation phases are held to, and the scales they implement.
They are derived from what the product already is (`00-existing-design-system.md`) and from the
feature-preservation contract governing this phase.

---

## 0. The rule that outranks the rest

> **Design quality goes up. User effort goes down. Feature count does not go down.**

A redesign is not accepted if a capability still technically exists but became materially harder to
find. Parity includes **discoverability**, not just reachability. Every control present in
`baseline/inventory.json` must be present in the after-capture, at the same four widths and in both
locales, or be accounted for in that page's parity table with an explicit, justified new location.

"Clean" is never a reason to hide a function. Lynomia is an operational tool used all day by agents
and supervisors; the goal is **structured density**, not empty screens with everything behind a
kebab menu.

---

## 1. Hierarchy: the action priority system

Every control on every redesigned surface is classified, and the classification decides placement.

| Tier | Definition | Placement rule |
|---|---|---|
| **Primary** | The one thing this page exists for | Always visible, at every width, without scrolling. One per surface. |
| **Secondary** | Frequent, supports the primary task | Visible, or at most one click away. Never below the fold on desktop. |
| **Contextual** | Per-row, per-item, occasional | An overflow menu is allowed — but the menu's trigger must carry an accessible name, and the row must not be the only way to reach the action. |
| **Destructive** | Deletes or disconnects | Visually separated from its neighbours, never adjacent to a primary action, and confirmed. Never the default focus target. |

Today the product violates this in two systematic ways the phase must fix:

- **Destructive actions are the most common unnamed control in the product.** `i-woot-bin` is the single most frequent icon with no accessible name in the baseline. A delete button a screen reader announces as "button" is the worst case of this, and it is the most frequent one.
- **Destructive confirmations are rendered as anchored popovers** on contact delete and merge, while every other confirmation is a modal.

**Button-safety rule.** No control is removed or relocated until four questions are answered in the
page's parity table: what backend action it calls, which roles can see it, what depends on it, and
where its replacement lives. Every removed DOM control maps to an intentional replacement.

---

## 2. Density

Dense is correct here. The principles are about *structure*, not emptiness:

1. **Group before you hide.** A row of twelve controls becomes three labelled groups of four, not one button and a menu.
2. **Scan path first.** Identity → state → metadata → actions, in that order, left-to-right in LTR and start-to-end in RTL.
3. **One alignment grid per surface.** Action columns align; status chips align; the eye travels one vertical line, not five.
4. **Truncate with a tooltip, never clip silently.**
5. **Empty does not mean blank.** An empty list keeps its column headers (today `BaseTable` drops them, so an empty table loses its column context) and offers the action that fills it.

---

## 3. Tokens: the scales this phase adds

The product has colour, type, breakpoints, icons and motion. It has **no** spacing, radius, elevation,
control-height or z-index scale — which is the direct cause of 14 modal widths, 16 arbitrary radii,
8 ad-hoc z-indexes and 46 bespoke shadows. Phase 3 adds exactly these, as Tailwind theme extensions,
and nothing else.

**Rule: no arbitrary values for a dimension a scale covers.** No `13px`, `17px`, `7px`, `11px`.
`rem` for arbitrary CSS dimensions; native numeric values stay native where chart and SVG APIs require
them.

### 3.1 Spacing

Keep Tailwind's 4px base — it is what 5,000+ existing classes already use — and name only what the
product repeatedly reaches for and cannot express:

| Token | Value | Replaces |
|---|---|---|
| `13` | 3.25rem (52px) | `h-[3.25rem]`, used 8× as the header height |

Everything else already exists in the default scale. The work is removing the arbitrary values that
restate steps that are already there — 13 of the 18 arbitrary `size-[…]` do exactly that.

### 3.2 Radius

| Token | Value | Use |
|---|---|---|
| `rounded-sm` | 4px | chips inside chips, swatches |
| `rounded-md` | 6px | badges, status pills, inputs, menu items |
| `rounded-lg` | 8px | buttons, cards, dropdown bodies |
| `rounded-xl` | 12px | dialogs, drawers, popovers |
| `rounded-full` | — | avatars, presence dots, count bubbles |

Five steps, which is what the 16 arbitrary radii collapse to.

### 3.3 Elevation

Derived from the two shadows the conversation view already defines (`--cw-shadow`,
`--cw-shadow-hover`), promoted out of the private `--cw-*` namespace:

| Token | Use |
|---|---|
| `shadow-raised` | cards and rows on hover |
| `shadow-overlay` | dropdowns, popovers, menus |
| `shadow-modal` | dialogs and drawers |

Plus `blur-panel` for the `backdrop-blur-[100px]` that appears 45× in 41 files as an unnamed token.

### 3.4 Control height

One ladder, shared by buttons, inputs, selects, chips and badges — this is what makes a filter bar line
up with the button beside it:

| Token | Height | Used by |
|---|---|---|
| `xs` | 24px | badges, count bubbles, compact chips |
| `sm` | 32px | dense table-row actions, toolbar buttons |
| `md` | 36px | the default: buttons, inputs, selects |
| `lg` | 40px | primary page actions, mobile tap targets |

Mobile tap targets are never below 40px, whatever the token.

### 3.5 Z-index

The current ladder runs `z-40 → z-50 → z-60 → z-[100] → z-[1000] → z-[9990] → z-[9999] → z-[10001]`.
It becomes five named steps:

| Token | For |
|---|---|
| `z-sticky` | sticky headers and pagination footers |
| `z-dropdown` | menus, popovers, comboboxes |
| `z-drawer` | side panels |
| `z-modal` | dialogs (the native top layer already wins; this is for the non-native ones) |
| `z-toast` | alerts |

### 3.6 What Phase 3 does **not** do

It does not renumber colours, rename typography utilities, change breakpoints, or touch
`theme/colors.js`'s public names. Those are adopted, not re-specified.

---

## 4. Component policy

**Reuse → extend → patch → only then create.** Do not create a second design system inside Chatwoot.

Concretely, for this phase:

| Need | Answer |
|---|---|
| A badge | **Extend `Label`.** It already has 6 validated colours, 2 sizes, icon and action slots and the only token-backed neutral. Default to the `bg-n-{c}-3` / `text-n-{c}-11` ramp so the largest group of the 60 existing treatments migrates with no visual change; keep `bg-n-alpha-2` tone-by-text as a deliberate `subtle` variant. |
| Table hover / selection / sort / loading | **Add to `BaseTable` behind props.** The slot contract is already right and 15 surfaces speak it. Lift `CsatTable`'s hover/selected classes and `CsatTableLoader`'s shape rather than inventing new ones. |
| A skeleton | **Wrap the existing `bg-n-slate-3 animate-pulse` convention**, so the ~20 hand-rolled blocks collapse into it without visual change. |
| A page header | **Re-skin `BaseSettingsHeader`.** 35 components already drive it; `ImportDetailHeader` is the proven extension pattern. Do not introduce a sixth header. |
| Dropdown positioning | **Route `DropdownMenu`'s 41 consumers through `useDropdownPosition`.** It already handles RTL flipping, fit-aware vertical flipping, max-height derivation and viewport clamping. |
| A mobile sheet | This is the one genuinely missing component. Grow it from `Popover`'s existing responsive switch — the only mobile adaptation in the product — and keep its 244-line spec green. |
| A second modal engine | No. Migrate the 29 legacy `<woot-modal>` mounts onto `Dialog`. |

---

## 5. Accessibility: non-negotiable

Accessibility is not traded for aesthetics. Every interactive control, after this phase:

1. **Has an accessible name.** An icon-only control has `aria-label` *and* a tooltip. This is the single largest defect in the product — 42% of captured controls have no name — and the parity harness fails the build on it.
2. **Is reachable by keyboard**, in a sensible order, with a **visible** focus state. The product has exactly one correct focus treatment today (`Switch.vue:22`); it becomes the shared token and is applied to `Button`, `Checkbox`, `Input` and `Select`.
3. **Is a semantic control.** A `div` with `@click` is not a button. `TagMultiSelectComboBox`'s trigger and chip-remove controls are the live examples.
4. **Announces its role and state.** Menus get `role="menu"`/`menuitem` and arrow keys; comboboxes get `role="combobox"`, `aria-expanded` and `aria-activedescendant`; dialogs get `aria-labelledby`.
5. **Meets contrast** in both themes.
6. **Is not invisibly tabbable.** `LabelItem`'s remove button is width-clipped rather than hidden; a closed mobile sidebar keeps ~43 links in the tab order.

---

## 6. RTL is first-class

Arabic is a primary locale, not a mirror applied afterwards.

- **Logical utilities by default**: `ms`/`me`/`ps`/`pe`/`start`/`end`/`border-s`/`rounded-es`. `ltr:`/`rtl:` pairs only where the two directions genuinely differ, not as the normal way to express an offset.
- **One source of direction truth**: the `accounts/isRTL` store getter, through `TeleportWithDirection`. Not a DOM query.
- **Every overlay keeps its direction context** — a raw `<Teleport>` loses it.
- **Icons that encode direction flip; icons that encode an object do not.** A back chevron mirrors; a trash can does not.
- **Numbers, dates, currencies and phone numbers stay LTR inside RTL text.**
- **A canvas may stay LTR where graph semantics require it** — the flow builder's left-to-right execution order is meaning, not layout — but its panels, toolbars and dialogs are RTL.
- Verified at every width in the harness: the baseline already asserts `direction` and zero horizontal overflow per capture.

---

## 7. Mobile is a different design, not a smaller one

Every desktop capability has a reachable mobile path, or is documented as desktop-only with a reason.

- **Nothing is hidden at a breakpoint without a replacement.** Today settings search and the help link simply vanish below `sm` on 18 pages. Either they adapt, or they move — they do not disappear.
- **Overlays adapt**: a dialog becomes a sheet, a wide drawer becomes full-width, a hover popover becomes a tap target.
- **Tables adapt**: horizontal scroll with a sticky first column, or a stacked row — not a clipped grid.
- **Tap targets ≥ 40px**, and hover is never the only way to reach anything.
- **Navigating closes the mobile navigation**, which it currently does not.

---

## 8. Motion

Motion explains a change of state; it is never decoration.

| Change | Duration |
|---|---|
| Hover, focus, colour | 100ms |
| Dropdown, popover, tooltip | 150ms |
| Dialog, drawer, sheet | 200ms |

Easing is `ease-out` entering and `ease-in` leaving. The existing `prefers-reduced-motion` block is
honoured and extended — it is already the inventory of what must stay suppressible.

---

## 9. Scope discipline

This phase changes how the product looks and how its controls are organised. It does **not** add
features. If the work surfaces a useful missing capability, it is written down in
`findings/missing-features.md` and left unimplemented.

Out of scope, explicitly: CRM, SLA expansion, AI, new Commerce features, new Automation features, new
Flow nodes, a new Campaign engine, a new Audience engine. No framework migration, no second CSS
framework, no rewrite of a working system. Routes are preserved, deep links are preserved, permissions
are preserved.
