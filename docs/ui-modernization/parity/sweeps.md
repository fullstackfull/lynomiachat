# Sweeps — responsive, RTL, accessibility

Three passes across the whole dashboard rather than one surface: what each one looked for, what it found,
what was fixed and what was left. Each is checked by the same gate as every other batch —
`harness/parity.mjs` over the 68-surface capture set, two locales, four widths.

---

## 11 — Responsive

### What it looked for

- **A control a phone cannot reach.** Any interactive element carrying `hidden` with a breakpoint variant
  that brings it back only above a width. This is the contract's own test: a feature that still exists but
  cannot be reached on a phone has been removed for everyone on a phone.
- **A width a phone cannot fit.** Any fixed `w-[…]` or `min-w-[…]` wider than a 390px viewport.
- **Measured overflow**, from the capture itself.

### What it found

**Controls hidden below a breakpoint: 4, none of them a loss.**

| Control | Why it is not a loss |
|---|---|
| `Sidebar.vue:979`, `:1000` — collapse / expand the sidebar | already `v-if="!isMobile"`; on a phone the sidebar is a drawer, so there is nothing to collapse |
| `SearchFilters.vue:93` — clear all search filters | the same page carries a second clear button at `lg:hidden` (`:55`), so the phone has its own |
| `SwitchLayout.vue:24` — switch the conversation layout | the expanded layout does not exist below `md`; the control would toggle nothing |

**Fixed widths wider than 390px: 34**, all on overlays — dialogs, popovers, filter panels, the date picker.
The capture measures **0 horizontal overflow in all 544 captures**, including at 390px, because each of
these sits inside a parent that clamps it. The one overlay no capture reached was the widest in the
product, `DatePicker` at `w-[880px]`; it now has a surface of its own (`auditlogs-date-range`, reached by
clicking the audit log's date-range button) and measures no overflow either.

### What changed

Nothing in the product. The sweep's finding is that the responsive strategy already holds; the one gap was
in the evidence, and that is now a capture.

---

## 12 — RTL

### What it looked for

Every class token in `dashboard/` and `shared/` that names a physical side — `ml`, `mr`, `pl`, `pr`,
`left`, `right`, `text-left`, `text-right`, `border-l/r`, `rounded-l/r` and the four corners, `float-left/right`
— and carries no `ltr:` or `rtl:` variant. Those are the ones that do not mirror: in Arabic they put the
gap, the border or the alignment on the wrong side.

Tokens were read out of `class` / `:class` attributes and `@apply` rules only, so a tooltip modifier
(`v-tooltip.left-start`) and a string literal (`'right-aligned'`) are not mistaken for utilities.

### What it found

**210 physical direction tokens** across `dashboard/` and `shared/` templates. 148 were rewritten, 62 were
left physical.

**148 were rewritten to the logical equivalent** — `ms`, `me`, `ps`, `pe`, `start`, `end`, `text-start`,
`text-end`, `border-s/e`, `rounded-s/e`, `rounded-ss/se/es/ee`, `float-start/end`.

**50 the scan itself proves direction-agnostic**, in three groups:

| Group | Count | Why it reads the same in either direction |
|---|---|---|
| symmetric pair | 40 | `left-0 right-0`, `ml-0 mr-0`, `border-l-0 border-r-0` — both edges at once |
| centring | 6 | an edge at 50% pulled back by half the element's own width |
| CSS triangle | 4 | `border-l-transparent` **and** `border-r-transparent` draw one arrow |

**12 more were deliberately left physical** on an explicit keep list, because the left edge of the screen
is the left edge of the screen whatever the language:

| File | Why |
|---|---|
| `DraggableReorderList.vue` ×3 | the dragged element's position is written by JS in pixels from the viewport origin; a logical inset would move that origin in Arabic and break the arithmetic |
| `IframeLoader.vue` ×3, `SearchPopover.vue`, `Modal.vue` | a full-viewport overlay anchored at the physical origin — `top-0 left-0` plus `w-full h-full` or `w-screen h-screen` |
| `Spinner.vue` ×3 | centred by half its own width. (Its fourth physical token, `-ml-2.5`, is counted under *centring* above. `shared/components/Spinner.vue` was not modified by this phase at all — its physical CSS is pre-existing and was read, judged agnostic, and left.) |
| `ReplyBox.vue` | `left-[unset]` resets a physical property something else sets physically |

148 + 50 + 12 = 210.

### Two real defects, not just drift

- **`Wizard.vue:39`** drew its step connector on both sides at once in Arabic. The `after:` segment was
  correctly written `ltr:after:left-4 rtl:after:right-4`, but the `before:` segment had a bare
  `before:left-4` with only an `rtl:before:right-4` beside it — so in Arabic the line appeared on the left
  *and* the right. Both segments are now `start-4`, with no overrides.
- **`MetricCard.vue:36`** removed the gap between the status dot and its label in Arabic
  (`mr-1 rtl:mr-0 rtl:ml-0`) rather than mirroring it. It is now `me-1`, which mirrors.

### 17 collisions cleaned up

Rewriting a physical utility next to a hand-written `ltr:`/`rtl:` pair leaves the same property declared
twice. Sixteen were redundant and the override was removed; one — `ArticleEditor.vue:215` — genuinely used
different values per direction (`pl-4` / `pr-3`) and is now `ps-4 rtl:ps-3`. These 17 are separate from the
210 above: they are overrides removed, not tokens rewritten.

---

## 13 — Accessibility

### What it looked for

The checks the control inventory cannot make: an element announced as a control that no keyboard can
reach, a disclosure that does not say whether it is open, a control named only by a tooltip, and a form
control with no name source at all.

### What the capture already proves

**0 unnamed controls in all 544 captures**, against 1578 in the pre-phase baseline. Every button, link,
input, select, textarea and ARIA widget on 68 surfaces, in English and Arabic, at four widths, has an
accessible name.

### What changed

**Six controls a keyboard could not reach.** A `div` carrying `role="button"` and a `@click` handler is
announced as a button and cannot be focused or activated:

| Control | Fix |
|---|---|
| `ConversationCard.vue:97` — the Inbox view's conversation card, the primary way into a conversation from that view | `tabindex="0"`, Enter and Space, and a focus ring |
| `InboxCard.vue:159` — the Inbox view's notification card | same |
| `ResponseCard.vue:294` — the link from a Captain response to its conversation | same |
| `InboxDisplayMenu.vue:145` — the sort options | now real `<button role="menuitemradio" :aria-checked>` elements |
| `MenuItem.vue:12` — the inbox option menu's rows, which the parent binds `@click` to | now a real `<button>`, so the listener keeps working and Enter and Space come with it |
| `SidebarGroupHeader.vue:42` — renders `<a href>` or a `<div>` by prop | a third shape: it relies on native semantics rather than `tabindex` + a key handler. `role="button"` overrode the link's own role in the `to` branch and described an unfocusable element in the other. **The sweep's removal only half-fixed it** — the no-`to` branch was left a bare `div` with a click handler. It became a real `<button>` in the follow-up commit, below |

**Six disclosures that did not announce their state.** The two filter bars (audit logs, WhatsApp
templates), the SAML attribute map, `SelectMenu`, and the inbox display and sort menus now carry
`aria-expanded`, and the menu triggers `aria-haspopup`.

### What was left

29 further chevron triggers have no `aria-expanded`, most of them in Help Center and Captain, which no
surface captures yet. They are listed in `findings/deferred.md`.

---

## Gate result

```
compared 544 captures
  lost 0   moved-with-reason 8   added 598   newly-named 1466   regressions 0
```

0 unnamed controls, 0 horizontal overflow, 0 wrong direction and 0 page errors across all 544 captures.
The eight moved-with-reason entries are the canned-responses exception from an earlier batch.

### Two things the gate caught before the sweep was done

**32 unnamed controls, all on the surface the responsive sweep had just added.** `DatePicker`'s calendar
navigation arrows were nameless icon buttons — a defect that had been there all along and that nothing
measured, because no capture had ever opened the date picker. They are now named "Show earlier dates" /
"Show later dates": the step is a month in the day grid and a year in the month grid, so a name saying
"month" would be wrong in half the views.

**80 lost controls on `sidebar-settings`** — the whole Settings navigation group. The accessibility sweep
had removed `role="button"` from `SidebarGroupHeader`, and the capture surface reached the Settings group
through exactly that attribute (`nav > ul > li > [role="button"][title="Settings"]`), so the group never
expanded and twenty links went missing from the inventory.

The harness selector was wrong to depend on an ARIA attribute, and it now matches on `title`. But the
removal was half a fix too. The header is an `<a href>` whose plain click toggles the group and whose
Cmd-click opens the page; `role="button"` hid the link role, so a screen reader never learned the group
could be opened in a new tab. Removing the role fixed that branch and left the other one worse: when the
group has no page behind it the element rendered a bare `div` with a click handler, announced as nothing
and reachable by no keyboard. It now renders a real `<button>` in that branch, carries `aria-expanded` when
it is expandable, and has a focus ring.
