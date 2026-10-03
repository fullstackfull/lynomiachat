# Lynomia usability: page friction audit

One row per page actually present in the repository. "Clicks" counts pointer actions from a cold start on that page
(opening a dropdown counts as one). Everything in the **Already solved** column was read in the code, not assumed.

Legend for the last column: **GAP** = acted on or considered in this phase; **ok** = no gap worth spending this
phase on; **visual** = deferred to [08](08-deferred-ui-visual-improvements.md).

## 1. Conversations

### 1.1 Conversation list (`home`, `ChatList`)

| | |
|---|---|
| First seen | inbox/filter header, conversation cards, status tabs |
| Primary task | pick the next conversation to answer |
| Already solved | right-click card → mark read/unread, status, snooze, priority, label (searchable), assign agent (availability-sorted), assign team, open in new tab, **copy link**, delete. Bulk bar: agent, team, label, status, priority, snooze. Command bar: all of the above. Hotkeys for next/previous, resolve, snooze |
| Friction | none that a convenience feature should fix |
| Verdict | **ok** — adding anything here increases clutter without removing a step |

### 1.2 Conversation detail + contact panel

| | |
|---|---|
| Primary task | answer the customer |
| Secondary | identify them, check their orders, route them |
| Already solved | contact panel: open contact page in new tab, copy email, copy phone, new message, all conversations, call, edit, merge, delete. Sidebar panels are reorderable and their open/closed state persists in `ui_settings` (`conversationSidebarItemsOrder`, `isContactSidebarItemOpen`) |
| Friction | the action row already holds 6 icon buttons at `sm` |
| Verdict | **ok** |

### 1.3 Commerce panel inside a conversation

| | |
|---|---|
| Primary task | answer "where is my order?" |
| Already solved | Customer 360 across stores + per-store view; remembered view choice; live refresh on `commerce.customer.updated`; `useAbortableRequest`; order search by number; "Open order" (provider admin, URL-sanitised); "Track shipment"; "Send tracking" → composes the reply; order actions gated per store; carts |
| Friction | the **order number** is plain text. It is the one identifier an agent moves by hand into the provider admin, a reply, or a note. Email and phone one panel above both have copy buttons — the inconsistency is the tell |
| Clicks today | select text → `Cmd+C`, or retype 8–12 characters |
| Verdict | **GAP** (small, zero new UI if the number itself becomes the control) |

## 2. Contacts

### 2.1 Contacts list (`contacts_dashboard_index`)

| | |
|---|---|
| Already solved | search, sort (persisted in `ui_settings.contacts_sort_by`), filter builder, save-as-segment, bulk label add/remove, bulk delete, import, export, add — and the overflow menu `ContactMoreActions` already exists and already gates its items with `usePolicy().checkPermissions` |
| Context on return | `ContactsList` pushes `{ name, params, query: route.query }` and `ContactManageView` uses `router.back()`, so search / page / filter survive opening a contact and coming back |
| Friction | none |
| Verdict | **ok** — context preservation is already correct; the overflow menu is the right host for new audience actions |

### 2.2 Audience / segment view (`contacts_dashboard_segments_index`)

This is the page with the most friction in the product.

| | |
|---|---|
| First seen | the audience's name and its current members |
| Primary task | check who is in it — works well |
| Secondary task | **do something with it** — not supported at all |
| Segment actions offered | edit conditions (pencil), delete (trash). That is the complete list |
| Already solved | membership is live; `active_automation_rules_count` + `campaigns_count` are already in the API payload; delete/unshare is refused with the reason naming rules and campaigns |
| Friction 1 | to use an audience in a rule: leave the page → Settings → Automation → Add → pick an event → scroll to the Audience condition group → find the audience **by name** in a multi-select. **6+ clicks and a name lookup**, after you were already looking at it |
| Friction 2 | same again for a campaign: Campaigns → WhatsApp → New → scroll to Recipients → find it by name |
| Friction 3 | no duplicate. A currency or threshold variant ("VIP SAR" → "VIP AED") is rebuilt condition by condition |
| Friction 4 | no copy link, although the route is a clean deep link |
| Friction 5 | the dependency counts are only visible **inside the edit popover**, i.e. only if you were already editing |
| Verdict | **GAP** — highest-value cross-module work in this phase |

### 2.3 Contact detail (`contacts_edit`)

| | |
|---|---|
| Already solved | attributes, labels, notes, media, history, merge, previous conversations; deep-linkable; `router.back()` |
| Friction | no Commerce / Customer 360 here — it lives only inside a conversation |
| Verdict | **deferred** — Customer 360 needs a conversation id for its panel API (`/conversations/:id/commerce/...`). Surfacing it on a contact without a conversation is a backend change, not a convenience tweak. Recorded in [03](03-prioritized-improvements.md) as P2 |

## 3. Settings → Flow Builder

### 3.1 Flow list (`settings_flows_index`)

| | |
|---|---|
| First seen | table: name, status, inboxes, actions |
| Already solved | status shows the published version and live session count; delete is blocked while published; row opens the builder |
| Friction 1 | **empty state is one sentence** (`SettingsLayout` `noRecordsMessage`) with no next action, on the page where a first-time admin lands |
| Friction 2 | **no duplicate.** A variant of a 14-node flow is rebuilt from scratch |
| Friction 3 | **a saved unpublished draft is invisible.** The row renders `flow.published` only, although the API payload already carries `draft`. An admin who saved yesterday reads "Published v3" and believes v4 is live |
| Friction 4 | no templates — every flow starts from `Flows::Versions::STARTER` (Start → End) |
| Verdict | **GAP** on all four |

### 3.2 Flow builder canvas (`settings_flows_builder`)

| | |
|---|---|
| Already solved | palette, drag/drop, edges, zoom/pan/fit, node config panel, node duplicate, server validation with clickable errors, Test Mode on the real runtime, session inspector, publish/disable, inbox connect/disconnect, `"· Unsaved"` in the status line, `onBeforeRouteLeave` confirmation, canvas forced `dir="ltr"` so RTL does not mirror the graph |
| Friction 1 | `Cmd/Ctrl+S` is unbound → the browser's save-page dialog opens instead of saving the draft |
| Friction 2 | a browser **reload or tab close** discards an unsaved graph with no warning; only in-app navigation is guarded |
| Friction 3 | no way to start from a known-good graph |
| Verdict | **GAP** on all three |

## 4. Settings → Automation

| | |
|---|---|
| Already solved | **clone**, search, instant/delayed tabs, enable/disable with confirmation, delete with typed confirmation, Lynomia audience + Commerce condition groups, seven Commerce triggers, Commerce-unsafe actions hidden on Commerce triggers (`CUSTOMER_MESSAGE_ACTIONS`) |
| Friction 1 | empty state is one sentence, no next action |
| Friction 2 | a new rule opens on `conversation_created` + an empty `status` condition + an empty `assign_agent` action — a shape nobody wants, so the first act is always to clear it |
| Friction 3 | no way to start from a known-good rule |
| Verdict | **GAP** on 1 and 3; 2 is addressed by 3 rather than by changing the blank default |

## 5. Settings → Commerce

| | |
|---|---|
| Already solved | four providers, OAuth and credential dialogs, per-store status (`active` / `disabled` / `needs_reauth` / `disconnected`), capability flags per store (`actions`, `carts`), cart queue, installation-level provider switch (`Commerce::Providers.enabled`) |
| Friction | reachable only by mouse through the settings list (not in the command bar) |
| Verdict | **GAP** (command bar entry only) |

## 6. Settings → Campaigns

| | |
|---|---|
| Already solved | per-channel pages; shared audiences as a recipient source next to labels; **server-side recipient count before sending**, debounced, abortable, "unknown" never rendered as `0`; illustrated empty states with copy; template parser with required-parameter validation; delete confirmation |
| Friction | cannot be entered from the audience you are looking at (see §2.2) |
| Verdict | **ok in itself**; the entry point is the gap, and it belongs to §2.2 |

## 7. Other settings pages

| Page | Already solved | Verdict |
|---|---|---|
| Agents, Teams, Inboxes, Labels, Custom Attributes, Canned, Macros, Integrations, Audit Logs | CRUD, search where the list can be long, all in the command bar | **ok** |
| Agent Bots | CRUD; flow bots appear here too as `bot_type: flow` | **ok** |
| General settings | account settings, features | **ok** |

## 8. Cross-cutting

| Area | State | Verdict |
|---|---|---|
| Global search / command palette | real, `@chatwoot/ninja-keys`, 30 destinations, per-entry permission + feature-flag gating via route `meta` | **ok — do not build a second one.** Two entries are missing from the array |
| Keyboard shortcuts | `useConversationHotKeys`, `useGoToCommandHotKeys`, `useBulkActionsHotKeys`, `useMacroHotKeys`, `useAppearanceHotKeys`, `useInboxHotKeys`, `useSidebarKeyboardShortcuts`, discoverable in `WootKeyShortcutModal` (`Cmd+/`) | **ok** — extend, never replace. One gap: the builder has none |
| User preferences | `ui_settings` on the user, via `useUISettings().updateUISettings`, already holding sort order, sidebar order, panel open state, signature flags, layout | **ok — do not build a second preference store** |
| Request hygiene | `useAbortableRequest` is the shared cancellation utility and is already used by the Commerce panel and the campaign recipient count | **ok** — reuse it |
| Deep links | conversations, contacts, segments, flows, automations (list), campaigns all have addressable routes and resolve their own state on load | **ok** |
| Empty states | rich and illustrated in Campaigns and Contacts; a bare sentence on every `SettingsLayout` page, including Flow Builder and Automation | **GAP**, scoped to the two pages where the next action is expensive |
| Action feedback | `useAlert` everywhere; flow publish/save surface server error codes next to the node; audience delete surfaces the real reason; campaign count failure says "unknown" | **ok** |
| Telemetry | Amplitude only when a token is configured, and it records nothing about navigation; audit logs record mutations only | no usage data — see [02](02-friction-and-opportunity-map.md) §0 |
