# Implemented productivity features

Twelve improvements, each tied to a numbered friction row in
[02](02-friction-and-opportunity-map.md), plus three recipe catalogues. Click counts are counted against the actual
UI, not estimated: a pointer action is one, opening a dropdown is one, a keystroke is noted as such. Where a feature
prevents a mistake rather than removing a step, that is what is claimed — no invented time savings.

## P0-1 · Flow Builder and Commerce in the command bar

Friction 1. `composables/commands/useGoToCommandHotKeys.js`, two entries in the same `GO_TO_COMMANDS` array, plus two
icons.

| | |
|---|---|
| BEFORE | `Cmd/Ctrl+K` → not listed → Esc → open the sidebar's Settings group → find Flow Builder in a list of twenty → click. **2 clicks and a visual scan, after a failed keystroke.** |
| AFTER | `Cmd/Ctrl+K` → type "flow" → Enter. **0 clicks.** |

The entries are gated by the resolved route's `meta.featureFlag`, `meta.permissions` and `meta.installationTypes`,
exactly like the thirty already there, so nothing new decides who sees them.

## P0-2 · "Unpublished changes" on a flow

Friction 2. `settings/flows/Index.vue`, `settings/flows/FlowBuilder.vue`. **No API change**: `flows_controller`
already returned both `published` and `draft`.

Publishing turns a flow's draft into its published version and archives the previous one, so a flow that has **both**
has edits that are saved and not live. That is an exact signal, not a heuristic.

| | |
|---|---|
| BEFORE | The row read "Published · version 3" whether or not version 4 was sitting in the draft. Telling them apart meant opening the builder and comparing the graph against memory. **Not possible from the list at all.** |
| AFTER | The row says "Unpublished changes" under the status; the builder's status line says it too once the in-session graph is clean. |

Prevents the mistake in [00](00-role-and-workflow-map.md) §5 row 1: believing edits are live.

## P0-3 · Duplicate a flow

Friction 3. `settings/flows/Index.vue`. Reuses `POST /flows` and `PUT /flows/:id/draft`; **no new endpoint**.

| | |
|---|---|
| BEFORE | Open the source, read each node's panel, create a new flow, add each node from the palette, re-enter every field, drag every edge. For the 12-node order-tracking shape: **≈12 palette clicks + ≈25 field entries + 19 edge drags.** |
| AFTER | Duplicate → the name is prefilled "<name> copy" → Create. **2 clicks.** |

The source graph is read **first**, so a failed read creates nothing. The copy is unpublished and connected to no
inbox: an inbox holds exactly one bot, so connecting the copy would take the inbox away from the original.

## P0-4 · Six flow templates

Friction 4. `recipes/flowTemplates.js`, `recipes/starterCopy.js`, offered from the list header and the empty state.
Detail in [11](11-flow-templates.md).

| | |
|---|---|
| BEFORE (order tracking) | New flow → name → create → 12 nodes from the palette → ≈25 fields → 19 edges → Save → Publish. **≈59 interactions before the first customer sees anything.** |
| AFTER | Templates → Use this → team (preselected when the account has one) → language (starts at "Arabic and English") → Create → the builder opens on the full graph. **3–4 clicks.** |

## P0-5 · Flow list empty state

Friction 5. The page a first-time admin lands on said "No flows yet…" and nothing else; the only next action was a
button in the header they had to notice.

| | |
|---|---|
| BEFORE | One sentence. **The next action was not on the screen the eye was on.** |
| AFTER | The same sentence, a line explaining that either route stays a draft until published, and two buttons: Templates, New flow. |

## P0-6 · Audience actions, where the audience is

Frictions 8, 9, 10, 11, 12. `Contacts/ContactsHeader/components/ContactMoreActions.vue` (the overflow menu that
already existed and already gated its items), `ContactListHeaderWrapper.vue`, `helper/audienceHelper.js`.

| Action | BEFORE | AFTER |
|---|---|---|
| Use in a rule | sidebar Settings → Automation → Add → event → change the default condition's attribute → scroll to the Audience group → operator → find the audience **by name** → **≈11 clicks and a name lookup** | ⋮ → Use in a new automation rule → the panel opens with the "is in <audience>" condition already there. **2 clicks** |
| Use in a campaign | Campaigns → WhatsApp → New campaign → scroll to Recipients → open the audience picker → find it **by name** → **5 clicks and a name lookup** | ⋮ → Use in a new WhatsApp campaign → the dialog opens with it selected and the server-side recipient count already running. **2 clicks** |
| Duplicate | open the filter editor, read every condition, close, clear, rebuild each condition (≈5 clicks each), save, name, share → **≈10 clicks for one condition, ≈20 for three** | ⋮ → Duplicate → the name is prefilled → Save. **3 clicks** |
| Copy link | select the address bar, `Cmd+C`, and the URL carries `?page=1` | ⋮ → Copy link. **2 clicks, clean URL** |
| See what uses it | open the filter editor (1 click) — the one place the counts were shown | in the same menu you act from, as a line you cannot click |

"Use it there" is a route query naming the audience id. The target page reads it, prefills its own form and drops the
query, so the URL is shareable and a reload is an ordinary visit. **Nothing is created on the way.**

## P0-7 · Seven automation recipes

Friction 15. `recipes/automationRecipes.js`, offered from the list header and the empty state. Detail in
[12](12-automation-recipes.md).

| | |
|---|---|
| BEFORE (VIP priority) | Add → event → change the default condition's attribute → scroll to the Audience group → operator → audience → add action → priority → value → add action → assign team → team → Save. **≈21 clicks — and the rule is saved active, so it runs before anyone has read it.** |
| AFTER | Recipes → Use this → audience → team → priority (starts at High) → Create. **≈7 clicks, and the rule is created switched off and opened for review.** |

## P0-8 · Seven audience presets

Friction 13. `recipes/audiencePresets.js`, offered from the contacts overflow menu. Detail in
[13](13-audience-presets.md).

| | |
|---|---|
| BEFORE (high-value buyers) | Contacts → Filter → attribute picker → scroll to the Commerce group → "Visible spend (SAR)" → operator → amount → Apply → Save → name → share → Save. **≈11 clicks** |
| AFTER | ⋮ → New audience from a preset → Use this → currency → amount → Create → the name is prefilled → Save. **≈8 clicks** |

**Honest measurement: about three clicks.** What the preset actually removes is needing to know the Commerce field
model first — that spend is per currency and never converted, that "has an order with status X" grows with more data
while "has none" needs every linked customer read, and which of the nine fields answers the question you have. The
preset asks for the currency and the threshold and names itself after what it measures.

## P0-9 · Automation list empty state

Friction 14. As P0-5: the sentence, a line saying a recipe arrives switched off, and two buttons.

## P1-1 · `Cmd/Ctrl+S` saves the flow draft

Friction 6. `FlowBuilder.vue` via the existing `useKeyboardEvents`, with `allowOnFocusedInput` so it works while a
config field has focus — which is exactly when the draft is worth keeping. The hint is on the Save button
("Save the draft (Ctrl/Cmd + S)"), in context, rather than in the global shortcut list where a page-scoped key would
mislead.

| | |
|---|---|
| BEFORE | The keystroke opened the browser's save-page dialog; Esc, then move the pointer to Save. **1 wasted dialog + 1 click.** |
| AFTER | The keystroke saves. **0 clicks.** |

## P1-2 · A reload no longer discards a flow graph

Friction 7. A `beforeunload` listener via `useEventListener`, registered while the graph is dirty and removed on
unmount. `onBeforeRouteLeave` already guarded in-app navigation; a reload or a closed tab left the router out of it,
so nothing asked.

| | |
|---|---|
| BEFORE | The graph was gone, silently. |
| AFTER | The browser asks. |

## P1-3 · The Commerce order number copies itself

Friction 16. `CommerceOrderItem.vue` with the existing `copyTextToClipboard`.

| | |
|---|---|
| BEFORE | Select the text (and avoid the `#`), `Cmd+C`, or retype 8–12 characters. |
| AFTER | Click the number. **1 click**, with a tooltip and a confirmation. |

The number **is** the control, so the row keeps its three actions and gains no fourth button. A clipboard the browser
refuses says so and leaves the agent where they were.

## Totals

| | |
|---|---|
| Improvements | **12** (9 P0 + 3 P1), inside the 8–15 target |
| Recipes | **6 flow templates, 7 automation recipes, 7 audience presets** |
| New database tables | **0** |
| Migrations | **0** |
| New API endpoints | **0** |
| New Vue routes | **0** |
| New sidebar items | **0** |
| New engines, runtimes or bot models | **0** |
