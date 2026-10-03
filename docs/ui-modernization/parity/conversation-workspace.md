# Parity record — Conversation workspace

What changed on the highest-traffic surface in the product, and how each change was verified. The
manifest it is checked against is `audit/surface-conversation-workspace.md` §2 (124 features). The gate
is `harness/parity.mjs`, run over the 47-surface capture set in two locales at four widths.

## Verdict

| | |
|---|---|
| Features in the manifest | 124 |
| PRESERVED | 124 |
| MOVED WITH JUSTIFICATION | 0 |
| REMOVED | 0 |
| Newly reachable without a mouse | 5 |

Nothing on this surface moved, so this batch adds no entry to `parity-exceptions.json`.

## Capability restored, not added

Each of these is a feature the product already had and only a mouse could reach. Making it reachable is
parity work, not new scope — the contract's "reachable on desktop/mobile and LTR/RTL" applies to features
that already exist.

| Feature | Was | Is | Manifest |
|---|---|---|---|
| Priority / Label / Agent / Team from a row | revealed by CSS `:hover` only, submenu `hidden` | opens on click, Enter and Space; `aria-haspopup` + `aria-expanded`; Escape closes | §2.6, 77–86 |
| SLA breach history in the header | `hidden group-hover:flex` on a `<div>` with no handler, `tabindex` or `role` | a real `role="button"` with a name, opening on click and on focus | §2.8, 115 |
| Expand the composer | inside `v-if="captainTasksEnabled"` — gone on any account without the Captain flag | unconditional, named, beside the Copilot control | §2.10, 131 |
| Select a conversation for a bulk action | `v-if="hovered \|\| selected"` driven by `@mouseenter`, so absent on every touch device | revealed by hover, by keyboard focus, and always where there is no hover | §2.3, 52 |
| Edit a contact field in place | `opacity-0 group-hover/row:opacity-100` | the same, plus on focus and wherever there is no hover | §2.13, 108 |

The hover reveal is expressed as `[@media(hover:none)]:opacity-100` rather than a width breakpoint
deliberately: a 1024px tablet is a touch device and a 390px desktop window is not, so the capability
should follow the input, not the viewport.

## Named controls

Nine controls on this surface had no accessible name. The conversation header's overflow menu is the only
route to mute, unmute and send-transcript; the status chevron is the only route to snooze-until and
mark-pending. Both were nameless icon buttons with a tooltip, which gives `aria-describedby` and no name.

`CardStatusIcon` printed the raw enum as its tooltip — `open`, `snoozed` in lowercase English in every
locale — while the priority column beside it translated. Both now carry `role="img"` and a translated
name; `shoot.mjs` does not collect `role="img"`, so that half is verified by the DOM and the unit tests
rather than by the gate, which is stated here rather than implied.

Across the whole capture set the unnamed-control count is **0**, against **1042** in the pre-phase
baseline.

## The shell

`ConversationView.vue` carried a 490-line scoped stylesheet: `--cw-accent: #6366f1` and a parallel
indigo ramp with its own dark-mode block, six bespoke shadows, two absolutely-positioned blurred glow
divs with a hover parallax, panel radii of 16/13/0px, four keyframe animations and a `:deep(*)`
scrollbar override reaching every descendant of the busiest screen in the product. Roughly 200 of those
lines targeted `.cw-welcome-card`, `.cw-feature-grid`, `.cw-feature-card` and `.cw-feature-icon` —
classes no template in the repository renders.

It is now Tailwind utilities on the three panels: `md:rounded-overlay lg:rounded-2xl`, `md:shadow-raised`,
`md:hover:shadow-overlay`, `hover:border-n-brand/30` so the accent follows the brand token, `z-10/20/30`
keeping the panels' original relative order, `motion-safe:animate-fade-in-up` reusing the animation the
config already defines, and `[scrollbar-width:thin]` on the shell — an inherited property, so it reaches
descendants without a `*` selector. The file went from 719 lines to 234.

The sidebar's enter/leave transition moved onto `<Transition>`'s own class props, which also fixed it:
`translateX(16px)` slid the panel in from the wrong edge in Arabic.

## RTL

| File | Was | Now |
|---|---|---|
| `BackButton.vue` | `i-lucide-chevron-left -ml-1`, unmirrored, in six surfaces | `-ms-1 rtl:rotate-180` |
| `ChatListHeader.vue` | clear-filter chevron unmirrored | `rtl:rotate-180` |
| `contextMenu/menuItemWithSubmenu.vue` | side chosen from `windowWidth - right` — raw physical geometry | `isRTL ? left : windowWidth - right`, opening to `start-full` / `end-full`; chevron mirrored |
| `conversationBulkActions/Index.vue` | `left-1/2 -translate-x-1/2` | `start-1/2 ltr:-translate-x-1/2 rtl:translate-x-1/2` |
| `CardLabels.vue` | `mr-6 ml-0 rtl:ml-6 rtl:mr-0` | `me-6 ms-0` |
| `AccordionItem.vue` | `pr-2 pl-0` | `pe-2 ps-0` |

Direction is correct on all 376 captures.

## Density and loading

- The composer's bottom toolbar could hold eleven controls in a single non-wrapping flex row inside a
  340px panel, with Send competing for the same line. Both clusters now wrap.
- The conversation header was `h-24 xl:h-12` — double height from 768px to 1280px, the common laptop
  range, with the action cluster dropped to its own left-aligned row. It is now `h-24 lg:h-13`, and the
  three pane headers share one 52px baseline.
- The conversation list showed a blank panel with one spinner pinned to the bottom during its first
  fetch; it now draws six row-shaped skeletons. Those rows deliberately do **not** carry the
  `conversation` class: `div.conversations-list div.conversation` is read by `useChatListKeyboardEvents`
  and by resolve-and-next, and a placeholder answering that selector would silently make Alt+J / Alt+K
  navigate to nothing.
- The empty state was a bare top-aligned paragraph; it renders through `EmptyStateLayout` with a new
  `compact` variant. Telling "nothing matches your filter" from "this inbox is empty" is new copy and a
  new control, so it is in `findings/deferred.md`.

## A finding withdrawn

Audit H4 claimed `CardPriorityIcon`'s unconditional `text-n-slate-5` renders urgent at the lowest
contrast step. It does not: every priority glyph but `priority-empty` carries its own hard-coded `fill`
in `theme/icons.js`, so the class only ever tinted the empty placeholder. The edit was reverted, the
audit entry rewritten, and the real defect — raw hex with no dark-mode form in the icon set — recorded
in `findings/deferred.md`.

A second claim, that a `ContactInfoRow` with an `href` and no value renders the wrong branch, does not
reproduce: every caller gates `href` on the value.

## Dead code removed

`showSearchModal` with its two methods and a second copy of `toggleConversationLayout` in
`ConversationView.vue`; `isContactPanelOpen` and `showContactPanel` in `ConversationBox.vue`; `inboxId`
on `ContactPanel` and `is-compact` on `ChatTypeTabs`, neither declared by its receiver; `hovered` and its
two handlers on `ConversationCard`; `wrapClass`/`is-note-mode`, `.left-wrap` and `.right-wrap`;
`menu-with-submenu`, `min-width-calc` and `menu-icon`; and the hard-coded English fallback behind
`BULK_ACTION.RESOLVE.ALL_MISSING_ATTRIBUTES`, a key that ships.

The CSS hook classes the audit lists under P6 that are **not** removed — `border-line`,
`conversation--user`, `actions--container`, `resolve-actions`, `conversations-list-wrap`,
`total-watchers` — are left alone on purpose: they match no rule in this repository, but a self-hosted
install's own stylesheet can target them, and deleting them buys nothing a user can see.
