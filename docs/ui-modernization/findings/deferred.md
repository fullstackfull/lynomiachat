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

## 2. `z-60` generates no CSS

Tailwind's default `zIndex` scale stops at 50, so the `z-60` written at `DropdownMenu.vue:186,243`,
`LocaleCard.vue:137`, `CategoryCard.vue:123` and `InboxDisplayMenu.vue:140` resolves to nothing — those
menus have shipped with no z-index at all. Fixing it changes real stacking order.

**Lands in:** the overlay commit, where those surfaces have a before-capture to compare against.

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
