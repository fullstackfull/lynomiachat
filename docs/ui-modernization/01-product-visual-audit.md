# 01 — Product-wide visual audit

Phase 1. Eleven surface audits and eight system audits, read against the running product in a browser
at four widths in two locales. The evidence lives in `audit/`; `audit/synthesis.md` is the
cross-module reading of it. This document is the front door: what was audited, what the audit found,
and what the baseline it produced commits the rest of the phase to.

**Scale:** 11 surfaces · **2,771 feature-parity rows** · **734 visual findings** · 8 system areas.
Plus a captured baseline of 23 surfaces × 2 locales × 4 widths = **184 captures, 1,756 controls**.

---

## 1. The surfaces, and what each audit produced

Each surface audit has the same four parts: the routes and the primary task; a **feature parity
manifest** enumerating every control, state and affordance a user can reach; a visual audit; and an
explicit list of what the surface already does well and must not lose.

| Surface | Audit | Parity rows | Findings |
|---|---|---:|---:|
| Settings — admin (SLA, webhooks, custom roles, audit logs, integrations, dashboard apps) | `audit/surface-settings-admin.md` | 376 | 55 |
| Settings — CRUD (agents, teams, inboxes, labels, canned, macros, attributes, agent bots) | `audit/surface-settings-crud.md` | 338 | 62 |
| Inbox view and Reports | `audit/surface-inbox-view-reports.md` | 316 | 75 |
| Conversation workspace | `audit/surface-conversation-workspace.md` | 254 | 81 |
| Campaigns | `audit/surface-campaigns.md` | 247 | 91 |
| Flow Builder | `audit/surface-flow-builder.md` | 247 | 38 |
| Contacts list and audiences | `audit/surface-contacts-list.md` | 227 | 52 |
| Contact panel | `audit/surface-contact-panel.md` | 225 | 33 |
| Commerce — conversation panel | `audit/surface-commerce-panel.md` | 197 | 64 |
| Commerce — settings | `audit/surface-commerce-settings.md` | 176 | 102 |
| Automation | `audit/surface-automation.md` | 168 | 81 |
| **Total** | | **2,771** | **734** |

The eight system audits — tokens, form and action primitives, containers, scaffolding, data display,
navigation, filters and search, accessibility and RTL — inventory the shared layer those surfaces are
built from. Their findings are summarised in `00-existing-design-system.md`.

---

## 2. What the audit actually found

The product is not inconsistent because its parts were designed badly. It is inconsistent because a
good newer system was built beside an older one and the migration stopped half way, and because that
newer system stops at colour. Six patterns account for most of the 734 findings.

### 2.1 One job, several answers

| Job | How many ways it is solved today |
|---|---|
| Render a page title | **5 header components**, 5 prop vocabularies, 5 type treatments — plus 9 pages that hand-roll one and so inherit no restyle |
| Show a status | **60 treatments**, 6 colour ramps, 5 radii, 7 height policies, 7 type classes, and no badge component |
| Open a modal | **2 live engines**, 14 distinct centred widths; destructive contact confirmations are anchored *popovers* |
| Show a list | `BaseTable` on 15 surfaces, hand-rolled `divide-y` stacks on 4 settings pages, card rows on Contacts and Campaigns, CSS-grid pseudo-rows in SLA reports |
| Paginate | **3 systems**, 3 default page sizes (16/10/25), 2 i18n namespaces; only the legacy one has numbered pages and a page-size selector |
| Say "nothing here" | **4 visual languages**, and the four newest surfaces all bypass the shared one |
| Sort | **5 implementations**, two of which are the same component duplicated |
| Filter | **6 idioms**, 3 chip components, 2 live filter-type registries consumed in the same files |
| Say "loading" | 4 idioms, ~20 hand-rolled `animate-pulse` blocks with 4 base colours, and no skeleton primitive |

Some divergence is earned: a flow canvas is not a settings list, and a three-pane conversation
workspace is not a CRUD page. None of the rows above are that.

### 2.2 The system stops at colour

`tailwind.config.js` configured screens, type, colour, keyframes and animation — and nothing else. No
spacing, radius, elevation, control-height or z-index scale existed. That one gap is upstream of the
14 modal widths, the 16 arbitrary radii, the 46 hand-written shadows, the z-index ladder running to
`99999`, and the `h-[3.25rem]` repeated in eight files as a de-facto token. Detail in
`00-existing-design-system.md` §1.

### 2.3 Accessibility was measured, not estimated

Across the captured baseline, **700 of 1,756 controls — 40% — had no accessible name**, and the single
most frequent nameless icon in the product was the delete bin. 221 of 249 icon-only buttons (89%) had
no name; 84 of them relied on a tooltip, which floating-vue exposes only as `aria-describedby` and only
while the popper is showing, so a disabled button had neither. Focus had five competing conventions and
two places that removed the indicator without replacing it. `Dialog` had no accessible name at all.
Four combobox-family components had no keyboard operation whatsoever.

### 2.4 Mobile has no vocabulary

There is **no sheet or bottom-drawer pattern anywhere** — zero matches for `bottomsheet`, `sheet`, or
`translate-y-full` across `dashboard/` and `shared/`. `Popover` is the only component with a responsive
branch. The consequences are concrete: settings search and the help link vanish below `sm` on 18 pages
with no replacement; flow nodes cannot be added at all below 768px; the contact panel covers the thread
with no in-panel way back; a 400px-wide popover is the campaign-creation UI on a 390px viewport.

### 2.5 Two surfaces render a failed fetch as an empty list

Contacts swallows failures in all four list actions; Campaigns has a literal `// Ignore error`. An
outage is indistinguishable from an empty account, and there is no retry.

### 2.6 Several load-bearing things are quietly dead

A `z-60` that Tailwind never generated, on menu bodies that have therefore shipped with no z-index.
Three camelCase SVG attributes that made all 89 spinners draw at stroke width 1. `Select`'s error
outline painted with a token that does not exist. An `AttributeBadge` whose two states compute
different colours and bind neither. A `BaseTable` `loading` prop no call site passed. Seven
`featureName` values that index nothing, so seven "Learn more" links are silently absent and one
translated string is never rendered.

---

## 3. What must not change

`audit/synthesis.md` §4 lists 42 things the audits found genuinely good — 20 pieces of architecture to
extend rather than replace, and 22 pieces of product behaviour that read as craft. A redesign that
loses any of them is a regression even if every pixel improves. The ones most easily lost by accident:

- **Load-bearing selectors queried from JavaScript** — `div.conversations-list div.conversation`, `#conversationAttachment`, `#conversationFilterTeleportTarget`, `.resizable-editor-body`, `.drag-handle` and the rest in `audit/surface-conversation-workspace.md` §2.16. Renaming one breaks Alt+J/Alt+K, "resolve and next", the attachment shortcut or sidebar reordering, with no test failure and no type error.
- **The positional `header-${index}` slot on `BaseTable`** — SLA depends on indices 2, 3 and 4 for its column tooltips.
- **`Button`'s shorthand boolean attributes** — `slate xs faded` is the normal idiom at 840 call sites, not an exception.
- **`v-model:search-query` on `BaseSettingsHeader`** and `SettingsLayout`'s five-slot order, including the unnamed default slot the file itself warns not to delete.
- **Honest, qualified numbers** — Commerce says *visible* orders, never lifetime totals; Campaigns' live server-side recipient count; Reports' unit-aware duration formatting.
- **Cross-module shortcuts that ask the destination for permission first** (`ContactMoreActions.vue:43-53`), so a shortcut never offers a page the page would refuse.
- **Dependency shown where the action is** — "Used by 2 automation rules · 1 campaign" sits in the menu that can delete the audience.
- **Automation recipes that create real rules switched off** and open them for review.
- **The 10 header affordances** that exist at some breakpoint: per-page search, the help link, the item count, the count/actions divider, the back button, the `meta` line, tabs, audit-log filters, assignment-policy breadcrumbs, report download buttons.

---

## 4. The baseline this produced

`baseline/` is the before-reference, captured from the pre-phase commit in a git worktree so it stays
true as the phase proceeds:

- **23 surfaces × 2 locales × 4 widths = 184 captures**, 1,756 controls, 72 screenshots.
- Each control recorded with the accessible name a screen reader would announce, its `data-test-id`, its icon, whether it is disabled, whether it is visible, and whether it is in the accessibility tree at all.
- Each capture also records the document's `direction`, its horizontal overflow in pixels, and both page errors and console errors — Vue swallows a failing render into `console.error`, so a surface can lose an entire section and raise no page error.
- Two consecutive runs are byte-identical, so a screenshot difference means a real difference.

`harness/parity.mjs` diffs a new capture against it and exits non-zero on a lost control, a newly
unnamed one, new overflow, a new error or a flipped direction. A control that genuinely moved is
declared in `harness/parity-exceptions.json` with where it went and why. That is what turns "no
capability may disappear" into something a build fails on rather than something a reviewer squints at.

---

## 5. Where this leads

`02-design-principles.md` sets the rules; `03-token-normalization.md` records the scales that filled
the gap in §2.2. The implementation order follows the synthesis's own ranking, which puts adoption of
what already exists ahead of anything new:

1. Tokens, then the primitives that consume them — the prerequisite for everything else, because a badge pass or a dialog migration done first bakes the arbitrary values back in.
2. Status badges onto one component with a tone vocabulary.
3. The table capabilities onto the pages that need them.
4. Dialogs: the 40 legacy files onto `Dialog`, a focus trap on `SidePanel`, a phone treatment seeded from `Popover`.
5. Empty, loading and error states, including the two surfaces that render a failed fetch as an empty list.
6. Page shell, header and settings information architecture.
7. The per-surface work, each against its own parity manifest.
8. Responsive, RTL and accessibility sweeps for whatever the per-surface work did not reach.

Every one of those runs `parity.mjs` against `baseline/` before it lands.
