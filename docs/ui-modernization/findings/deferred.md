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
