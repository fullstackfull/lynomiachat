# Lynomia usability: prioritized improvements

Derived from [02](02-friction-and-opportunity-map.md). **P0 and strong P1 are implemented; P2 is recorded, not built.**
Implementation detail and before/after step counts are in
[04](04-implemented-productivity-features.md).

## P0 — clear daily productivity win

| # | Improvement | Friction rows | Module extended | New module? |
|---|---|---|---|---|
| P0-1 | Flow Builder and Commerce added to the existing command bar | 1 | `useGoToCommandHotKeys.js` | no |
| P0-2 | "Unpublished changes" shown in the flow list and the builder status line | 2 | `flows/Index.vue`, existing API payload | no |
| P0-3 | Duplicate a flow (name + full graph copy, unpublished, no inboxes) | 3 | existing `POST /flows` + `PUT /flows/:id/draft` | no |
| P0-4 | Flow templates (6) behind "New flow → Start from a template" | 4 | `Flows::Versions` draft save; `AgentBot(bot_type: flow)` | no |
| P0-5 | Flow list empty state offers templates and "start from scratch" | 5 | `SettingsLayout`'s existing `preBody`/`body` slots | no |
| P0-6 | Audience actions menu: Use in Automation, Use in Campaign, Duplicate, Copy link, and the dependency counts | 8, 9, 10, 11, 12 | existing `ContactMoreActions` dropdown + `usePolicy` | no |
| P0-7 | Automation recipes (7) behind "New rule → Start from a recipe", created **disabled** | 15 | existing `POST /automation_rules` | no |
| P0-8 | Audience presets (7) behind "New audience → Start from a preset" | 13 | existing `POST /custom_filters` | no |
| P0-9 | Automation empty state offers recipes and "start from scratch" | 14 | `SettingsLayout` slots | no |

## P1 — useful common workflow (implemented)

| # | Improvement | Friction rows | Module extended |
|---|---|---|---|
| P1-1 | `Cmd/Ctrl+S` saves the flow draft, with the hint on the Save button | 6 | `useKeyboardEvents` (existing composable) |
| P1-2 | `beforeunload` warning while the flow graph is dirty | 7 | `FlowBuilder.vue`, registered only while dirty |
| P1-3 | Commerce order number is click-to-copy (the number itself, no new button) | 16 | `CommerceOrderItem.vue` + existing `copyTextToClipboard` |

## P2 — recorded, deliberately not built

| # | Item | Why not now |
|---|---|---|
| P2-1 | Customer 360 on the contact page | the panel API is conversation-scoped (`/conversations/:id/commerce/...`). Showing it without a conversation is a backend change with its own caching and permission questions — a Commerce phase item, not a convenience tweak |
| P2-2 | "Recently visited" list | the command bar, sidebar and browser history already return you to a record. A recents store is new persistent data purely for convenience — stop condition 7 |
| P2-3 | Favourites / pinning | the sidebar already lists every inbox, audience, team and segment. Pinning adds a concept without removing a step |
| P2-4 | Remembered last-used inbox / team / store in campaign and flow forms | real but thin: the forms are short and the wizards added here already preselect a sole candidate. A general "remember every form field" behaviour risks sending a campaign from the wrong inbox |
| P2-5 | Campaign starter templates | the Campaign builder is already short (title, inbox, template, schedule, recipients) and every field is account-specific, so a template would prefill almost nothing while adding a path to sending real messages. Deferred on value, not on capability — see [09a](09a-recipe-opportunity-study.md) §6 |
| P2-6 | Audience "entered / left" events | explicitly deferred by the Automation phase; unchanged here |
| P2-7 | Flow Builder: resume bot after handoff | explicitly deferred by the Flow Builder phase; unchanged here |

## Not implemented because the functionality already exists

Listed in full in [02](02-friction-and-opportunity-map.md) rows 20–30. Summary: conversation quick actions, global
search / command palette, keyboard shortcuts, bulk actions, the user-preference store, campaign recipient counting,
automation clone, the flow in-app unsaved guard, contacts list context preservation, contact copy/open actions, and
the Commerce panel's open-order / track-shipment / send-tracking / remembered-view behaviour.

## Count

9 P0 + 3 P1 = **12 implemented improvements**, inside the 8–15 target, each tied to a numbered friction row.
The three recipe catalogues (P0-4, P0-7, P0-8) deliver 6 flow templates, 7 automation recipes and 7 audience presets.
