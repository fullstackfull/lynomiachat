# Deferred decisions

Things found during the phase that are real, that are not scope creep, and that are deliberately
handled in a later commit rather than the one that found them. Each entry says what, why it waits, and
where it lands.

## 1. Tables at narrow widths need a sticky action column, not just a scroll wrapper

**Found in:** the table-system commit, verified at 390px in the harness.

Fifteen tables render `min-w-full table-auto` with no overflow wrapper. At 390px the columns spill past
the card: in `labels-list-en-390` the edit and delete buttons draw *outside* the white panel, on the
page background. Wrapping the table in `overflow-x-auto` fixes the spill — and the before/after capture
showed it also pushes the action column out of view, reachable only by a horizontal swipe inside the
card.

That is a worse trade on a phone: a control that looked untidy became a control you have to discover.
The right answer is the scroll wrapper **plus** an action column stuck to the end edge, which needs the
row to carry a real background so the sticky cell can inherit it — and that depends on which surface
each table sits on.

**Status:** `BaseTable` gained a `scrollable` prop, off by default, so nothing regresses now.
**Lands in:** the responsive commit, where the settings list pages get a designed mobile treatment and
a per-page parity table.

## 2. The z-index ladder is migrated piecemeal, not in one sweep

**Done:** `z-60` generated no CSS — Tailwind's default scale stops at 50 — so the three menu *bodies*
written with it (`LocaleCard.vue:137`, `CategoryCard.vue:123`, `InboxDisplayMenu.vue:140`) had shipped
with no z-index at all, and now use `z-dropdown`. The two on `DropdownMenu`'s menu *items* were dead
either way and are deleted.

**Not done:** the rest of the ladder — `z-40 → z-50 → z-[100] → z-[1000] → z-[9990] → z-[9999] →
z-[10001]` — still runs on raw values. Collapsing it onto the five named steps means changing relative
order in at least one real case: a dropdown teleported to the body at `z-[1000]` currently paints
*above* a drawer, and would paint below it afterwards. Proving that is safe needs captures of an
overlay opened inside another overlay, which the harness does not have yet.

**Lands in:** a commit that first adds nested-overlay surfaces (a dropdown inside a drawer, a dialog
over a popover) to the capture set.

## 3. Two token-layer defects that change appearance when fixed

- `select/Select.vue:58` outlines errors with `outline-n-red-9`. There is no `n-red-*` ramp, so the error state renders nothing. Fixing it to `n-ruby-*` makes an invisible state visible.
- `spinner/Spinner.vue:18-20` passes `strokeWidth`, `strokeLinecap` and `strokeLinejoin` in camelCase, which are not valid SVG attribute names. All 89 spinners therefore render at the SVG default stroke width of 1 instead of 8.

**Lands in:** the forms commit and the loading-states commit respectively, each with a capture.

## 4. Discovered capability gaps — documented, not implemented

Per the phase's scope rule, these are written down and left alone:

- **Campaigns has no list controls at all** — no search, no sort, no filter — while every other first-class list has at least two.
- **Companies has search and sort but no filter**, although `CompanyHeader` is otherwise a copy of `ContactHeader`.
- **Settings search disappears below `sm`** on 18 pages with no replacement. The responsive commit restores a path to it; making search itself better is not this phase's job.
- **Conversations has no active-filter chips and no numeric filter count** — Contacts has both.
- **The sidebar's Segments and Tagged-with sub-groups have no sort menu**, while the four parallel sub-groups rendered by the same component do.
- **Empty sub-groups vanish silently** in the sidebar: an account with no teams has no Teams section at all, and the `SIDEBAR.NEW_TEAM` / `NEW_INBOX` / `NEW_LABEL` strings that would populate an empty state sit unused.

## 5. Settings list pages still have a bare-sentence empty state

`SettingsLayout` now exposes an `emptyState` slot, so a page can offer the action that fills the list
instead of only stating that it is empty — but no page uses it yet. Eighteen settings lists still fall
through to the default message. Giving each one an icon, a sentence and its primary action is page
work with an information-architecture decision attached (which action, and whether the search box
should still be there when there is nothing to search).

**Lands in:** the settings commit, against the parity manifest in `audit/surface-settings-crud.md`.

## 6. Six "Learn more" links have no help page to point at

`BaseSettingsHeader` resolves its help link through `FEATURE_HELP_URLS`. Six values passed by call
sites index nothing, so those pages silently have no link: `assignment-policy`,
`conversation-workflow`, `slack_integration`, `linear_integration`, `notion_integration` and
`shopify_integration` (the table has `shopify`, not `shopify_integration`).

The helper now normalises hyphens to underscores, so `assignment_policy` and `conversation_workflow`
will resolve the moment a URL exists for them; the four integration ones need a decision about whether
each integration gets its own help page or they all point at the integrations guide. That is content,
not code, so it is written down rather than guessed at.

Two were unambiguous and are fixed: `automation` passed a `linkText` that was translated and never
rendered, and **custom roles linked to the canned-responses help page** while its link read "Learn
more about custom roles". Both now have entries following the file's own slug pattern — worth a
confirmation that `chwt.app/hc/automations` and `chwt.app/hc/custom-roles` resolve.

## Status and priority icons carry hard-coded hex with no dark-mode form

`theme/icons.js:216-250` fills the four `priority-*` glyphs and `status-resolved` /
`status-snoozed` with literal hex (`#e5484d`, `#ffc53d`, `#e4e4e9`, `#0D9B8A`, `#FFBA1A`)
rather than `currentColor`. Only `priority-empty` uses `currentColor`. Two consequences:

- The status and priority columns of the conversation list keep their light-mode colours in
  dark mode, while every token-driven neighbour re-tones around them.
- A component cannot influence them, which is why `CardPriorityIcon.vue`'s `text-n-slate-5`
  has no effect on a real priority (and why audit finding H4 was withdrawn).

Not done in this phase: the fix is to replace the fills with `currentColor` in the icon set and
move the colour decision into the two components, which changes how these glyphs look on every
surface that renders them — the conversation list in both card forms, the conversation header,
search results and the reports. That needs its own before/after pass with captures of all of
them, and `conversation-card-expanded` is not in the capture set yet.

## Reachability gaps in the conversation workspace that are capability work, not presentation

Found while modernising the workspace. Each is a feature a mouse user has and a keyboard or touch user
does not. The ones that could be fixed without inventing new behaviour were fixed in that commit — the
row context menu's submenus now open on click and Enter, the SLA chip is a real button, the composer's
expand control is no longer behind the Captain flag, the bulk-select checkbox is revealed where there is
no hover, and the contact-field pencils are visible on touch. These three are what is left.

### Focusable conversation rows

`ConversationCard.vue` and `ConversationCardExpanded.vue` are `<div>`s with `@click` and no `tabindex`,
`role` or `@keydown`, so a keyboard user cannot Tab into the list at all. The product's answer today is
Alt+J / Alt+K, which navigate by querying `div.conversations-list div.conversation` and calling
`.click()` on the result. Giving a virtualised list a focus model has to be designed together with that
layer — two systems moving the same selection — and it is a new capability rather than a restyle.

### A real error state for the conversation list

Every fetch failure in `ChatList.vue` ends in a transient toast and the list then falls through to "There
are no active conversations in this group", so a failed load is indistinguishable from an empty inbox and
there is no retry anywhere in the panel. New copy and a new control.

### Telling "nothing matches your filter" from "this inbox is empty"

`CHAT_LIST.LIST.404` is one fixed string whatever the tab, folder or five advanced filters. The empty
state now renders through `EmptyStateLayout` so it is centred and has an icon, but the branch and a
second entry point to `resetAndFetchData` are new content and a new control, and the back chevron in the
header is the existing route to clearing a filter.

## Column headers for the expanded conversation list

`ConversationCardExpanded.vue` lays out ten semantic columns — three of them identical 16px icon slots —
with no header row anywhere, so the list cannot say what its columns are and cannot be sorted from them.
Whether that becomes a `BaseTable` is the open question, and answering it needs
`conversation-card-expanded` in the capture set first.

## A second design system in `_woot.scss`, keyed off Tailwind utility names

**Found while planning the Commerce panel; the blast radius is the whole product.**

`app/javascript/dashboard/assets/scss/_woot.scss` ends with ~120 hand-written lines inside the
`@layer utilities` block that attach styling to Tailwind's own class names and to bare element
selectors. Four of its five rules are defects whatever the brand intent, because they reach things that
never opted in:

| Selector | What it does | What it actually hits |
|---|---|---|
| `.bg-n-brand\/10` | `!important` navy→blue gradient, `text-transform: uppercase`, `color: white`, `display: block`, `margin: 10px`, `box-shadow: 0 0 20px #eee` | `components-next/button/Button.vue:106` — the **faded blue variant of the shared Button component** — plus the Captain FAQ chip, the inbox sort menu's active row and the context-menu hover tint. A 10%-alpha brand tint is a *subtle background*; it is being rendered as an uppercase white-on-gradient block. |
| `.bg-n-brand\/20:hover` | background-position + `color: #fff` | the same Button variant's hover state |
| `main` | `border: 2px solid`, `margin: 1rem`, `border-radius: 10px`, a 28px drop shadow | every `<main>` in the product — Help Center, Companies (list and detail), Campaigns (list and analytics), Contacts (list and detail), the gallery view |
| `button:has(span.sr-only)` | `background: #111 !important`, `width: 27px`, `height: 17px` | **any button in the product containing a screen-reader-only label.** Adding an `sr-only` name to a button — exactly what the accessibility work in this phase does — squashes it to 27×17px and paints it black. |

The fifth rule, `button.bg-n-brand, .bg-n-brand button`, is the "Lynomia brand gradient for primary
buttons" the comment names: a navy→blue gradient, white text, `font-family: Arial`, `font-size: 16px`,
`font-weight: bold`, `text-transform: uppercase`, `border-radius: 10px`, a sweeping `::before` overlay
and `transform: scale(1.05)` on hover.

**Not done in this phase, and deliberately not done silently.** The four defect rules are a
straightforward fix. The brand gradient is a product decision: it is plainly intentional, and it equally
plainly overrides the typography scale this phase is built on (`font-inter`, `text-button`, the nine
type utilities) and the radius, colour and elevation tokens. The right shape is a `brand` variant on
`components-next/button/Button.vue` that an author opts into, rather than a global rule triggered by a
background utility — but which primary buttons should carry it, and whether uppercase Arial is the
intended brand voice, is not mine to decide.

**Needs:** a yes/no from the product owner on the gradient, then one commit that removes the four defect
rules and moves whatever survives into the Button component. Its before/after is visible on nearly every
surface in the capture set, so it wants its own capture pass rather than riding inside another batch.
