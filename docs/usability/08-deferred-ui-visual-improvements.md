# Deferred to the UI/UX modernization phase

**Nothing in this list was changed.** This phase added actions, links, shortcuts, validation, state preservation and
starter configurations; it replaced no typography, no colour, no card, no navigation and no page aesthetic. What
follows is what was seen while working through the product, recorded for the phase that comes next.

Each item says where it was seen, so the next phase does not have to rediscover it.

## 1. Empty states

| Where | What |
|---|---|
| Every `SettingsLayout` page | the empty state is one centred sentence with no illustration and no next action: `<p class="flex-1 py-20 …">{{ noRecordsMessage }}</p>`. Flow Builder and Automation were given their own CTA blocks **because the next action there is expensive**; Labels, Macros, Canned responses, Teams, Inboxes, Custom attributes, Agent bots, Integrations, Audit logs and Commerce still have the bare sentence |
| Contrast | Campaigns and Contacts already have illustrated empty states with copy and a CTA (`components-next/Campaigns/EmptyState/`, `Contacts/EmptyState/`). **The design already exists; it has simply not reached the settings pages** |
| Suggestion | give `SettingsLayout` an `empty` slot with the Campaigns treatment, and let the two CTA blocks added here collapse into it |

## 2. Settings list density and hierarchy

| Where | What |
|---|---|
| Flow Builder list, Automation list | `BaseTable` rows with icon-button action columns. The flow row now carries three icon buttons (open, duplicate, delete); a fourth would need an overflow menu rather than another icon |
| Settings sidebar | twenty-plus flat entries in one group (General, Agents, Teams, Inboxes, Templates, Labels, Custom Attributes, Automation, Agent Bots, Macros, Canned, Integrations, **Commerce**, **Flow Builder**, Data, Audit Logs, Conversation Workflow, Billing, Subscription). No grouping between channel setup, automation and account administration |

## 3. The recipe gallery

Built functionally, deliberately plain: a list of outlined rows with a name, a description and a button. The next
phase may want cards, category tabs or icons per category — the data is already there (`category` on every recipe,
one of five values) and nothing in the markup prevents it.

## 4. Flow Builder canvas

| Where | What |
|---|---|
| Status line | "Published · version 3 · Unpublished changes" is now a single text line; the three states (published, unsaved, unpublished) would read better as badges |
| Errors panel | a fixed `top-left` panel over the canvas, which overlaps nodes at small widths |
| Node palette | a fixed-width column; at 390px the canvas is barely usable. **The builder is an administrator's desktop tool and was not made responsive in this phase** |
| Zoom controls | three unlabelled icon buttons bottom-left, no zoom-level readout |

## 5. Right-to-left

Everything added here mirrors correctly, and the browser run asserts it ([07](07-e2e.md) §3). Two observations for
the next phase, neither caused by this one:

- The **flow canvas is forced `dir="ltr"`** (`FlowBuilder.vue`), deliberately, so the graph does not mirror. The
  panels around it are RTL, so the seam between them is visible.
- A Latin sentence inside an RTL paragraph puts its full stop on the left. Visible in the Arabic screenshots because
  the strings this phase added are English until Crowdin translates them. It resolves itself with translation; it is
  not a layout bug.

## 6. Mobile (390px)

| Where | What |
|---|---|
| Recipe gallery and wizard | verified: cards stack, buttons stay reachable, no horizontal overflow |
| Audience actions menu | verified: the dropdown is `w-60` and fits |
| Flow Builder | **not usable** at 390px, and not made so here |
| Settings tables | `BaseTable` scrolls horizontally on narrow screens rather than reflowing |

## 7. Localized values that are not localized

`{{flow.order.status}}` and the Commerce status badges render the **normalized** values (`shipped`, `partially_paid`,
`out_for_delivery`). The agent-facing panel translates them through `useCommerceLabels`; a flow message sent to a
**customer** does not, because `Flows::Variables` substitutes the raw value. An Arabic template therefore carries an
English status word until the merchant edits the wording.

This is a **Commerce/Flow concern, not a visual one**, and it is recorded here only because it is the thing most
likely to be noticed in an Arabic screenshot. Fixing it means localized status rendering inside
`Flows::Variables.render`, which is a backend change and out of scope for both this phase and the visual one.

## 8. Small things seen and left alone

| Where | What |
|---|---|
| `ContactMoreActions` | the menu now has a titled section and an untitled one; the untitled one has no heading by design, which reads slightly asymmetrically |
| Dialog footers | `RecipeDialog` overrides the Dialog footer to keep Create out of the gallery step. The base Dialog could support a two-step footer instead |
| `DropdownMenu` | a disabled item is used as a non-clickable information row (the audience usage line). A dedicated info-row variant would be cleaner than a disabled button |
| Settings headers | the flow and automation headers now hold two buttons in a flex row; the design system has no defined secondary-action slot in `BaseSettingsHeader` |

## 9. Recommended scope for the next phase

In the order that would deliver the most for the least risk:

1. **One empty-state treatment** across every `SettingsLayout` page, reusing the Campaigns design, absorbing the two
   CTA blocks this phase added.
2. **Group the settings sidebar** into channels, automation and administration. Twenty flat entries is the single
   biggest navigation complaint the audit found that is purely visual.
3. **Status as badges** in the flow list and the builder, replacing the dot-separated text line.
4. **A secondary-action slot** in `BaseSettingsHeader`, so pages with two actions stop composing their own flex row.
5. **The recipe gallery as cards**, with the five categories it already carries.
6. **Table reflow at mobile widths**, instead of horizontal scroll.
7. **Flow Builder at tablet width** — a real project, and the right place to stop before claiming the builder is
   responsive.

Explicitly **not** recommended for the next phase: changing the conversation loop's layout, the Commerce panel's
information architecture, or the filter builder. The audit found those functionally dense and well-ordered; a
redesign there would risk a lot to gain little.
