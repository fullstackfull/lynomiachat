# Lynomia usability: roles and workflow map

What this phase is: **remove steps from the product that exists**. No visual redesign, no new module. The visual
pass is a separate later phase; its findings are collected in [08](08-deferred-ui-visual-improvements.md).

Roles below are the ones the repository actually supports. They come from `app/javascript/dashboard/constants/permissions.js` and `helper/permissionsHelper.js`
and the route `meta.permissions` of every page, not from an invented persona list.

## 1. Roles the repository defines

| Role | Where it comes from | Pages it can reach |
|---|---|---|
| **Account owner / administrator** | `administrator` in `account_users.role`; `useAdmin()`, `checkPermissions(['administrator'])` | everything, including all of `/settings` (Commerce, Flow Builder, Automation, Campaigns, Agents, Teams, Inboxes, Labels, Custom Attributes, Integrations, Audit Logs, Billing) |
| **Support agent** | `agent` role | Conversations, Inbox view, Contacts (`contact_manage`), Reports (if granted), own profile. **No** settings pages |
| **Custom role holder** | `custom_role` + permission list (`conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`, `contact_manage`, `report_manage`, `knowledge_base_manage`) | whatever the permission list allows |

Two further *product* roles exist in practice but are **not** separate repository roles — they are an administrator or
an agent doing a particular job. They are listed because their workflows differ, not because they are new permissions:

| Product role | Repository role it really is | Why it matters here |
|---|---|---|
| **Support manager** | `administrator`, or `agent` + `report_manage` | lives in Reports + Conversations + Teams; routes between people |
| **Commerce / customer-care agent** | `agent` (+ `contact_manage`) | lives in one conversation with the Commerce panel open |
| **Automation / Flow admin** | `administrator` (Flow Builder and Automation are `permissions: ['administrator']`) | lives in `/settings/flows`, `/settings/automation`, Contacts → Audiences |

Role claims in this document are **observed in code**. Frequency claims are marked **expected** — see
[02](02-friction-and-opportunity-map.md) §0 for why no usage data exists.

## 2. Workflows

### 2.1 Support agent — the conversation loop (expected: the highest-frequency loop in the product)

```text
Sidebar → Conversations (home) → pick conversation
  → read → reply → assign / label / set priority / resolve
  → next conversation
```

Observed in code:

- Assign agent, assign team, add/remove label, priority, status, snooze, mark read/unread, open in new tab,
  **copy link**, delete are all already on the conversation card context menu
  (`components/widgets/conversation/contextMenu/Index.vue`) **and** in the command bar
  (`composables/commands/useConversationHotKeys.js`).
- Bulk assign agent / team / label / status / priority already exist
  (`components/widgets/conversation/conversationBulkActions/`).
- The contact panel already has: open contact page (new tab), copy email, copy phone, new message,
  view all conversations, call, edit, merge, delete (`routes/dashboard/conversation/contact/ContactInfo.vue`).

Conclusion: **this loop is already dense in convenience features.** Adding buttons here would violate
"reduce cognitive load". Nothing was added to it.

### 2.2 Commerce / customer-care agent — order question in a conversation

```text
Conversation → Commerce panel (sidebar)
  → Customer 360 (several stores) or one store's view
  → find order → read status / payment / shipment
  → "Open order" (provider admin) | "Track shipment" | "Send tracking" (inserts a reply)
  → order actions (where the store allows them)
```

Observed in code: `components/widgets/conversation/commerce/`. Already present: per-store and cross-store views,
a remembered view choice (`localStorage` `lynomia.commerce.view`), live refresh, abortable requests
(`useAbortableRequest`), open-provider-order, track-shipment, insert-tracking-into-reply, order search by number,
order actions, carts.

Gap: the **order number itself** is the one value an agent retypes — into the provider admin, into a reply, into a
ticket. It is rendered as plain text with no copy affordance, while email and phone in the contact panel both have one.

### 2.3 Automation / Flow admin — build a bot

```text
Settings → Flow Builder → New → name it → builder opens on a Start → End graph
  → drag every node from the palette
  → configure every node (text, options, team, labels, store, lookup mode)
  → connect every required output
  → Save → Publish → connect a WhatsApp inbox
```

Observed in code: `routes/dashboard/settings/flows/`. `Flows::Versions::STARTER` is a two-node graph, so **every flow
starts blank**. A realistic order-tracking bot is ~14 nodes and ~18 edges, each configured by hand.

Gaps (all confirmed by reading the code):

- No flow duplicate. Node duplicate exists (`duplicateSelected`), flow duplicate does not.
- No templates.
- The list's empty state is a plain sentence (`SettingsLayout`'s `noRecordsMessage`), no next action.
- The list shows `published` version only. A saved-but-unpublished draft is invisible there, so an admin who edited
  and saved yesterday sees "Published v3" and cannot tell that v4 is sitting unpublished.
- `onBeforeRouteLeave` guards in-app navigation, but a browser reload or tab close loses an unsaved graph.
- `Ctrl/Cmd+S` is not bound, so the reflex keystroke opens the browser's "save page" dialog.

### 2.4 Automation / Flow admin — build a rule

```text
Settings → Automation → Add → choose event → build conditions → build actions → Save (active immediately)
```

Observed in code: `routes/dashboard/settings/automation/`. Already present: **clone** (`automations/clone`), search,
instant/delayed tabs, activate/deactivate with a confirmation, delete with a typed confirmation, and the Lynomia
condition groups (shared audience, Commerce fields) plus the seven Commerce triggers
(`settings/automation/lynomiaAutomation.js`).

Gaps: the empty state is a plain sentence; and a new rule starts from `START_VALUE` — `conversation_created` +
an empty `status` condition + an empty `assign_agent` action — which is never the rule anyone wants.

### 2.5 Automation / Flow admin — build an audience, then use it

```text
Contacts → Filter → add conditions → Apply → Save (segment) → tick "Share"
  → it appears under Sidebar → Contacts → Segments
Then, to act on it:
  → Settings → Automation → Add → event → scroll to the Audience group → pick it again by name
  → Campaigns → WhatsApp → New → scroll to Recipients → pick it again by name
```

Observed in code: audiences are `CustomFilter(filter_type: contact, shared: true)`; automation references them with a
`contact_audience` condition; campaigns with an `{ type: "Audience", id }` entry. `Audience::Usage` already reports
both, and `_custom_filter.json.jbuilder` already exposes `active_automation_rules_count` and `campaigns_count`.

Gaps:

- Those counts are shown **only inside the filter-editor popover** (`ContactsFilter.vue`), which you open to *edit*
  conditions — not where you decide whether an audience is safe to touch.
- From an open audience there is **no way to go to the thing you want to do with it**. The header offers exactly
  two segment actions: edit conditions, delete. To use an audience you leave, navigate to another module, and
  re-find it in a dropdown by name.
- No duplicate. "VIP SAR" and "VIP AED" must be rebuilt condition by condition.
- No "copy link", although `/contacts/segments/:segmentId` is a perfectly good deep link.

### 2.6 Administrator — connect a store

```text
Settings → Commerce → Connect → provider → credentials/OAuth → store appears
```

Observed in code: `routes/dashboard/settings/commerce/Index.vue`, four provider dialogs, OAuth callbacks. Mature.
The only gap in reach is navigational: see §3.

## 3. Navigation friction common to every role

`Cmd/Ctrl+K` opens a real command bar (`@chatwoot/ninja-keys`) whose go-to list is built from
`composables/commands/useGoToCommandHotKeys.js` and gated per entry by the target route's `meta.featureFlag`,
`meta.permissions` and `meta.installationTypes`. It covers 30 destinations.

It does **not** cover the two modules Lynomia added: `settings_flows_index` and `settings_commerce_index`. Both have
correct route `meta`, so they are omissions in one array, not a permissions problem. An admin who works in Flow
Builder all day cannot reach it by keyboard; everyone else's settings page can be reached that way.

## 4. What each role repeatedly retypes or re-finds (expected)

| Role | Re-entered by hand | Already solved? |
|---|---|---|
| Commerce agent | order number | **no** — plain text |
| Commerce agent | tracking URL | yes — "Send tracking" composes the reply |
| Agent | contact email / phone | yes — copy buttons |
| Agent | conversation link | yes — context menu |
| Flow admin | a whole flow graph, to make a variant | **no** — no duplicate, no templates |
| Flow admin | an audience's conditions, to make a currency/threshold variant | **no** — no duplicate, no presets |
| Flow admin | an audience's **name**, in two other modules' dropdowns | **no** — no cross-module action |
| Flow admin | the same rule shape for each Commerce event | partly — clone exists, but the first one is built blank |

## 5. Error opportunities per role (observed)

| Mistake | Who | Prevented today? |
|---|---|---|
| Thinking a saved flow draft is live | Flow admin | **no** — list shows the published version only |
| Losing an unsaved graph to a reload or `Cmd+S` | Flow admin | partly — SPA navigation is guarded, reload is not |
| Deleting an audience that a rule or a scheduled campaign needs | Flow admin | yes — refused, with the reason |
| Sending a campaign to nobody | Admin | yes — server-side recipient count, "unknown" never shown as `0` |
| Publishing an invalid flow | Flow admin | yes — `Flows::GraphValidator`, errors clickable to the node |
| Building a flow that references another account's team/label/store | Flow admin | yes — `Flows::NodeValidator` checks every id against the account |
| Enabling a rule accidentally | Flow admin | yes — toggle asks for confirmation |

The remaining prevention gap is the first two rows, both in Flow Builder, both about **draft state**.
