# Surface audit — Flow Builder list and canvas

> Phase: UI modernization discovery (UI-1).
> Mode: read-only. Nothing under `app/`, `enterprise/`, `custom/`, `lib/`, `config/` or `spec/` was changed.
> Scope: `app/javascript/dashboard/routes/dashboard/settings/flows/**` plus the shared primitives, layout wrappers and
> navigation entries that this surface depends on.
>
> This document is the **feature-preservation baseline** for the Flow Builder. Section 2 is a literal inventory of what
> ships today, read out of the files. A later redesign is checked against it: a row that disappears, or a row whose
> control becomes materially harder to find, is a regression.
>
> Note on freshness: `Index.vue`, `NodeConfigPanel.vue` and `TestPanel.vue` were modified on disk while this audit was
> running (a parallel pass adding `aria-label` to icon-only buttons). Every line reference below was re-read against the
> current file contents; where accessible names are now present, the manifest says so, and the remaining gaps are listed
> in V-01.

---

## 1. Routes and primary task

### 1.1 Route list

| Path | Name | Component | Wrapper | File |
| --- | --- | --- | --- | --- |
| `/app/accounts/:accountId/settings/flows` | `settings_flows_index` | `Index.vue` | `SettingsWrapper.vue` (centred `max-w-5xl` settings column) | `flows.routes.js:16-22` |
| `/app/accounts/:accountId/settings/flows/:flowId` | `settings_flows_builder` | `FlowBuilder.vue` | **none** — mounted straight into the dashboard shell, full bleed | `flows.routes.js:23-28` |

Both routes share one `meta` object (`flows.routes.js:9-12`):

```js
const meta = {
  featureFlag: FEATURE_FLAGS.LYNOMIA_FLOW_BUILDER,   // 'lynomia_flow_builder'
  permissions: ['administrator'],
};
```

- Feature flag constant: `featureFlags.js:59`; backend flag definition: `config/features.yml:286`.
- The flag + permission pair is the *only* gate on this surface. Nothing inside the components re-checks either one,
  with one exception: the Commerce palette group and the Commerce node types are additionally gated on
  `LYNOMIA_COMMERCE` (`FlowBuilder.vue:83-85`, `NodePalette.vue:14-16`).
- The builder route deliberately sits outside the settings column — the file comment at `flows.routes.js:7-8` says so.
  Consequence for this audit: the list is a 1024-px-max settings page, the builder is a full-viewport app shell, and the
  two have no shared chrome at all (no breadcrumb, no shared header, no shared page title).

### 1.2 Entry points into the surface

| Entry point | Where | Gating | File |
| --- | --- | --- | --- |
| Sidebar → Settings → "Flow Builder" (`i-lucide-workflow`) | Account settings menu group | Route `meta` resolved by the sidebar provider: `resolvePermissions` + `resolveFeatureFlag` → `shouldShow` | `Sidebar.vue:834-839`; `sidebar/provider.js:111-146` |
| Command bar → "Go to Flow Builder" | `Cmd/Ctrl+K` palette, Settings section, `ICON_WORKFLOW` | Same route meta | `useGoToCommandHotKeys.js:195-200`; label `generalSettings.json:196` |
| Deep link to a flow | `router.push({ name: 'settings_flows_builder', params: { flowId } })` from the list and from both create paths | Same route meta | `Index.vue:57-58` |
| Builder → list | Back arrow in the builder header | none | `FlowBuilder.vue:331-338` |
| Builder → list (forced) | Load failure replaces the route | none | `FlowBuilder.vue:146-150` |

### 1.3 Primary task

**One task, two halves.**

1. *List* (`settings_flows_index`): see every flow bot the account has, what version is live, which inboxes it answers
   for, and whether it has edits that are saved but not published — then create one (blank, from a template, or as a
   duplicate), open one, or delete one.
2. *Builder* (`settings_flows_builder`): edit one flow's **draft** graph on a canvas — add nodes from a palette,
   wire outputs to targets, configure the selected node in a side panel — then save the draft, fix the server's
   validation errors, run it against the real runtime in Test Mode, connect it to a WhatsApp inbox, publish it as a new
   version, and inspect live sessions.

The load-bearing domain fact the whole surface is built around (`FlowBuilder.vue:34-36`, `flowGraph.js:1-3`): **the
server owns the graph contract.** Node types, their outputs, which outputs are optional, and the channel limits all
arrive in the `show` payload (`node_types`, `capabilities`, `variables`). The client renders them and never validates;
every save and publish is re-validated server-side and errors come back as `{ code, node_id, detail }`.

---

## 2. Feature parity manifest

Every control, state and affordance that exists today. 134 rows.

### 2.1 Navigation and surface-level affordances

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 1 | Sidebar entry "Flow Builder" | navigation | Settings menu group, `i-lucide-workflow` | `lynomia_flow_builder` + `administrator` (`Sidebar.vue:834-839`) |
| 2 | Command-bar entry "Go to Flow Builder" | navigation | `Cmd/Ctrl+K` → Settings | same route meta (`useGoToCommandHotKeys.js:195-200`) |
| 3 | Back arrow to the flow list | navigation | Builder header, leftmost (`rtl:rotate-180`) | none (`FlowBuilder.vue:331-338`) |
| 4 | Forced return to list when the flow cannot be loaded | state | `router.replace` + `LOAD_ERROR` alert | none (`FlowBuilder.vue:146-150`) |
| 5 | Row name opens the builder | primary | List, first cell is a `<button>` | none (`Index.vue:226-237`) |
| 6 | "Open builder" icon action | secondary | List, actions cell, `i-lucide-workflow` | none (`Index.vue:267-274`) |

### 2.2 Flow list — header (`Index.vue:169-191` via `BaseSettingsHeader.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 7 | Page title "Flow Builder" | state | `BaseSettingsHeader` `title` → `h1.text-heading-1` | none (`Index.vue:170`; `BaseSettingsHeader.vue:56-59`) |
| 8 | Page description (3-sentence explainer) | state | `BaseSettingsHeader` `description`, `line-clamp-5 sm:line-clamp-none max-w-3xl` | none (`Index.vue:171`; `BaseSettingsHeader.vue:66-72`; copy `flowBuilder.json:4`) |
| 9 | "Templates" button | secondary | Header actions, `size=sm color=slate variant=faded` | none (`Index.vue:175-182`) |
| 10 | "New flow" button | primary | Header actions, `size=sm`, default blue solid | none (`Index.vue:183-188`) |

Not used on this surface although `BaseSettingsHeader` offers them: `searchPlaceholder` (search box), `#tabs`,
`#count`, `linkText`/`featureName` (help-centre link), `backButtonLabel`. The header therefore has no search, no tabs,
no record count and no help link.

### 2.3 Flow list — table (`Index.vue:221-299` via `components-next/table`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 11 | Column header "Flow" | state | `BaseTable` `headers[0]` | none (`Index.vue:39`) |
| 12 | Column header "Status" | state | `headers[1]` | none (`Index.vue:40`) |
| 13 | Column header "Inboxes" | state | `headers[2]` | none (`Index.vue:41`) |
| 14 | Column header "Actions" | state | `headers[3]`, cell content is icon-only | none (`Index.vue:42`) |
| 15 | Flow name | state | Cell 1, `text-body-main text-n-slate-12 truncate` | none (`Index.vue:231-233`) |
| 16 | Flow description (second line) | state | Cell 1, `text-n-slate-11 truncate` | none (`Index.vue:234-236`) |
| 17 | Published status "Published · version N" | status | Cell 2 | `flow.published` present (`Index.vue:151-154`) |
| 18 | "Not published" status | status | Cell 2 | `flow.published` absent (`Index.vue:154`) |
| 19 | "Unpublished changes" badge (amber) | status | Cell 2, `text-xs text-n-amber-11`, `data-test-id="flow-unpublished"` | `flow.published && flow.draft` (`Index.vue:158, 243-249`) |
| 20 | Live-session count, pluralised | status | Cell 2, `text-xs text-n-slate-11` | `flow.live_sessions` truthy (`Index.vue:250-255`; copy `flowBuilder.json:13`) |
| 21 | Connected inbox names, comma-joined | state | Cell 3, truncated | none (`Index.vue:258-263`) |
| 22 | "Not connected" fallback | state | Cell 3 | `flow.inboxes` empty (`Index.vue:261`) |
| 23 | Row hover highlight | state | `BaseTableRow` default `hoverable` | none (`BaseTableRow.vue:184-191`) |
| 24 | "Open builder" tooltip + aria-label | contextual | Actions cell, `v-tooltip.top` | none (`Index.vue:268-269`) |
| 25 | "Duplicate" action | secondary | Actions cell, `i-lucide-copy` | none (`Index.vue:275-283`) |
| 26 | "Delete" action | destructive | Actions cell, `i-woot-bin` + ruby hover | none (`Index.vue:284-293`) |
| 27 | Delete **disabled** while published | state | `:disabled="Boolean(flow.published)"` | `flow.published` (`Index.vue:290`) |

Deliberately absent from the table (so a redesign must not be credited for "keeping" them): sorting
(`sortableColumns` not passed), sticky header (`stickyHeader` not passed), horizontal scroll container
(`scrollable` not passed — default `false`, `BaseTable.vue:47-54`), skeleton loading (`loading` not passed),
`noDataMessage`, row selection, bulk actions, pagination, per-row overflow menu.

### 2.4 Flow list — create / duplicate dialog (`Index.vue:302-325`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 28 | Dialog title "New flow" | state | `Dialog` `title` | `copyFrom === null` (`Index.vue:304-308`) |
| 29 | Dialog title "Duplicate this flow?" | state | same `Dialog`, swapped title | `copyFrom` set (`Index.vue:305-306`) |
| 30 | "Name" input | primary | Dialog body, `data-test-id="flow-name-input"` | none (`Index.vue:315-319`) |
| 31 | "Description" input | secondary | Dialog body | none (`Index.vue:320-323`) |
| 32 | Name prefilled as "{name} copy" | state | Set by `openDuplicate` | duplicate path (`Index.vue:71`) |
| 33 | Description prefilled from source | state | Set by `openDuplicate` | duplicate path (`Index.vue:72`) |
| 34 | "Create" confirm button | primary | `Dialog` footer | enabled only when `name.trim()` (`Index.vue:309-310`) |
| 35 | Confirm spinner while creating | state | `:is-loading="isCreating"` | `isCreating` (`Index.vue:311`) |
| 36 | "Cancel" button | secondary | `Dialog` default footer | none (`Dialog.vue:153-161`) |
| 37 | Click-outside / `Esc` closes dialog | shortcut | `OnClickOutside` + native `<dialog>` | none (`Dialog.vue:119-129`) |
| 38 | Duplicate copies the source graph into the new draft | state | `show` → `create` → `saveDraft`, in that order | duplicate path (`Index.vue:79-87`) |
| 39 | Copy starts unpublished and inbox-less | state | Consequence of create API; documented at `Index.vue:67-68` | duplicate path |
| 40 | Builder opens on the newly created flow | state | `openBuilder(data)` after create | both paths (`Index.vue:89`) |

### 2.5 Flow list — template gallery (`Index.vue:326-334` via `RecipeDialog.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 41 | Gallery title "Start from a flow template" | state | `RecipeDialog` `title` | none (`Index.vue:329`; copy `recipes.json` → `RECIPES.FLOW.TITLE`) |
| 42 | Gallery description | state | `RecipeDialog` `description` | none (`Index.vue:330`) |
| 43 | Six flow templates listed | state | `FLOW_TEMPLATES` | per-recipe requirements (`flowTemplates.js:72-...`: `commerce_order_tracking`, `commerce_after_sales`, `support_department_routing`, `vip_priority_routing`, `bilingual_welcome`, `whatsapp_welcome_menu`) |
| 44 | Per-template name + description | state | Gallery row | none (`RecipeDialog.vue:129-135`) |
| 45 | "Needs X first" requirement note (amber) | status | Gallery row | `recipe.status !== AVAILABLE` (`RecipeDialog.vue:136-142`) |
| 46 | "Use this" button | primary | Gallery row, right side | only when `status === AVAILABLE` (`RecipeDialog.vue:144-153`) |
| 47 | "Start from scratch instead" link | secondary | Gallery footer, `variant=link` | none (`RecipeDialog.vue:156-164`) → hands over to the create dialog (`Index.vue:130-133`) |
| 48 | Step 2: per-template input form | primary | Same dialog, after choosing | `selected.inputs.length` (`RecipeDialog.vue:168-173`) |
| 49 | "Nothing to choose" note | empty | Step 2 when a template takes no inputs | `!selected.inputs.length` (`RecipeDialog.vue:175-177`) |
| 50 | "Choose a different one" back link | secondary | Step 2 footer | `selected` (`RecipeDialog.vue:178-186`) |
| 51 | Input validation: required / range / URL | state | `validate()` before create | per-input `required`, `min`/`max`, `type` (`RecipeDialog.vue:67-97`) |
| 52 | "Create" button + spinner | primary | Dialog footer | `selected` (`RecipeDialog.vue:199-207`) |
| 53 | Template provenance written into the description | state | `RECIPES.FLOW.PROVENANCE` with name + version | template path (`Index.vue:113-117`) |
| 54 | Created flow is a plain draft, unpublished, inbox-less | state | documented at `Index.vue:106-108` | template path |
| 55 | Commerce options preloaded when the gallery opens | state | `loadCommerceOptions()` on `open` | none (`RecipeDialog.vue:38-46`) |

### 2.6 Flow list — delete confirmation (`Index.vue:335-342`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 56 | Alert dialog "Delete {name}?" | destructive | `Dialog type="alert"` (ruby confirm) | none (`Index.vue:336-338`) |
| 57 | Explanation that a published flow must be disabled first | state | Dialog description | none (`flowBuilder.json:33`) |
| 58 | "Delete" confirm | destructive | Dialog footer | none (`Index.vue:340`) |

### 2.7 Flow list — states

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 59 | Loading: centred spinner + "Loading flows..." | loading | `SettingsLayout` `#loading` → `woot-loading-state` | `isLoading` (`Index.vue:164-167`; `SettingsLayout.vue:28-30`) |
| 60 | Empty: "No flows yet…" headline | empty | `data-test-id="flow-empty-state"`, `py-16 text-center` | `!flows.length` (`Index.vue:194-201`) |
| 61 | Empty: "Start from a ready-made template…" hint | empty | `max-w-md text-sm` | same (`Index.vue:202-204`) |
| 62 | Empty: "Templates" button (**solid blue**) | primary | Empty state actions | same (`Index.vue:206-211`) |
| 63 | Empty: "New flow" button (**faded slate**) | secondary | Empty state actions | same (`Index.vue:212-218`) |
| 64 | Error: "The flows could not be loaded." toast | error | `useAlert` in `load()`'s `catch` | request failure (`Index.vue:50-52`) |
| 65 | Error: create failure toast | error | `useAlert(CREATE_ERROR)` | non-duplicate create failure (`Index.vue:90-97`) |
| 66 | Error: duplicate failure toast + list reload | error | `useAlert(DUPLICATE_ERROR)` then `load()` | duplicate failure (`Index.vue:93-98`) |
| 67 | Error: template create failure toast + list reload | error | `useAlert(RECIPES.CREATE_ERROR)` then `load()` | template failure (`Index.vue:122-124`) |
| 68 | Success: "The flow is deleted." toast | status | `useAlert(DELETED)` | delete success (`Index.vue:144`) |
| 69 | Error: delete failure toast | error | `useAlert(DELETE_ERROR)` | delete failure (`Index.vue:146-147`) |

### 2.8 Builder — header anatomy and action hierarchy (`FlowBuilder.vue:328-411`)

DOM order, left to right (`header.flex.flex-wrap.items-center.gap-3.px-4.py-3.border-b`):

1. back arrow → 2. title block (name + status line) → 3. `ms-auto` action group: inbox chips → connect select →
Sessions → Test → Save draft → Disable → Publish.

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 70 | Flow name as `h1` (truncated) | state | Title block, `text-base font-medium` | none (`FlowBuilder.vue:340-342`) |
| 71 | Status line | status | Title block, `text-xs text-n-slate-11`, `data-test-id="flow-status"` | none (`FlowBuilder.vue:343-345`) |
| 72 | Status: "Published · version N" | status | `statusLabel` | `flow.published` (`FlowBuilder.vue:109-114`) |
| 73 | Status: "Not published" | status | `statusLabel` | no published version (`FlowBuilder.vue:113-114`) |
| 74 | Status: " · Unsaved changes" suffix | status | `statusLabel` | `isDirty` (`FlowBuilder.vue:115-117`) |
| 75 | Status: " · Unpublished changes" suffix | status | `statusLabel` | `published && draft && !isDirty` (`FlowBuilder.vue:118-121`) |
| 76 | Connected-inbox chip (one per inbox) | state | `bg-n-alpha-2 px-2 py-1 rounded-lg text-xs` | `flow.inboxes` (`FlowBuilder.vue:348-360`) |
| 77 | Chip "×" disconnect button | destructive | Inside each chip, `i-lucide-x size-3`, `aria-label` = DISCONNECT | none; no confirmation (`FlowBuilder.vue:354-359`) |
| 78 | "Connect a WhatsApp inbox" select | primary | Header, native `<select>` with placeholder option | rendered only when `whatsappInboxes.length` (`FlowBuilder.vue:361-367`) |
| 79 | Connect list = WhatsApp inboxes minus already-connected | state | `whatsappInboxes` computed | `channel_type === 'Channel::Whatsapp'` (`FlowBuilder.vue:102-107`) |
| 80 | Connecting reloads the flow and toasts | status | `setAgentBot(inboxId, flowId)` → `load()` → `INBOX_CONNECTED` | none (`FlowBuilder.vue:205-211`) |
| 81 | Disconnecting reloads the flow (no toast) | state | `setAgentBot(inboxId, null)` → `load()` | none (`FlowBuilder.vue:213-216`) |
| 82 | "Sessions" action | secondary | `slate faded sm`, `i-lucide-activity` | none (`FlowBuilder.vue:368-375`) |
| 83 | "Test" action | secondary | `slate faded sm`, `i-lucide-flask-conical` | none (`FlowBuilder.vue:376-384`) |
| 84 | "Save draft" action | primary | `slate` solid `sm` | disabled unless `isDirty` (`FlowBuilder.vue:385-394`) |
| 85 | "Save the draft (Ctrl/Cmd + S)" tooltip | shortcut | `v-tooltip.bottom` on Save draft | none (`FlowBuilder.vue:386`) |
| 86 | Save spinner | state | `:is-loading="isSaving"` | `isSaving` (`FlowBuilder.vue:390`) |
| 87 | "Disable" action | destructive | `ruby faded sm` | **only when `flow.published`** (`FlowBuilder.vue:395-402`) |
| 88 | "Publish" action | primary | default blue solid `sm` | none — always enabled (`FlowBuilder.vue:403-409`) |
| 89 | Publish spinner | state | `:is-loading="isPublishing"` | `isPublishing` (`FlowBuilder.vue:407`) |
| 90 | Publish saves the draft first | state | `saveIfDirty()` then `publish` | `isDirty` (`FlowBuilder.vue:175-183`) |
| 91 | "Version N is published." toast | status | `useAlert(PUBLISHED, {version})` | publish success (`FlowBuilder.vue:186-188`) |
| 92 | Disable confirmation dialog | destructive | `Dialog type="alert"` at the root | triggered from Disable (`FlowBuilder.vue:514-521`) |
| 93 | "The flow is disabled." toast | status | `useAlert(DISABLED)` | disable success (`FlowBuilder.vue:202`) |

### 2.9 Builder — canvas (`FlowBuilder.vue:416-483`, `@vue-flow/core`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 94 | Pan / zoom canvas | primary | `VueFlow`, `min-zoom=0.2`, `max-zoom=2` | none (`FlowBuilder.vue:425-431`) |
| 95 | Canvas is forced LTR | state | `dir="ltr"` on the canvas wrapper | none (`FlowBuilder.vue:418-424`) |
| 96 | Drop a palette item onto the canvas at the cursor | primary | `@dragover.prevent` + `@drop`, MIME `application/lynomia-flow-node` | none (`FlowBuilder.vue:240-244`; `NodePalette.vue:18-21`) |
| 97 | Click a node to select it (opens config panel) | primary | `@node-click` → `selectNode` → `panel = CONFIG` | none (`FlowBuilder.vue:250-253, 434`) |
| 98 | Click the pane to deselect (closes config panel) | secondary | `@pane-click="selectNode(null)"` | none (`FlowBuilder.vue:435`) |
| 99 | Drag a node to move it | primary | Vue Flow default | none |
| 100 | Connect an output handle to a target node | primary | `@connect` → `connect()` | none (`FlowBuilder.vue:246-248`) |
| 101 | Reconnecting an output replaces its single edge | state | `connect()` filters the old edge | none (`flowGraph.js:151-165`) |
| 102 | Nothing may lead into Start; no self-edges | state | `connect()` early-return | none (`flowGraph.js:152`) |
| 103 | Edges whose output no longer exists are dropped on save | state | `fromCanvas` filter | none (`flowGraph.js:138-139`) |
| 104 | `Delete` / `Backspace` deletes the selection | shortcut | `:delete-key-code="['Delete','Backspace']"` | Start node is `deletable: false` (`FlowBuilder.vue:431`; `flowGraph.js:107`) |
| 105 | `Cmd/Ctrl+S` saves the draft | shortcut | `useKeyboardEvents`, `allowOnFocusedInput: true` | only when `isDirty && !isSaving` (`FlowBuilder.vue:308-316`) |
| 106 | View fits the loaded graph once, after nodes measure | state | `@nodes-initialized="fitLoadedGraph"`, `isFitted` guard, `maxZoom:1 padding:0.3` | first init only (`FlowBuilder.vue:67-74, 436`) |
| 107 | Zoom-in button | secondary | Vue Flow `Panel position="bottom-left"`, `xs faded slate`, `i-lucide-plus` | none (`FlowBuilder.vue:441-442`) |
| 108 | Zoom-out button | secondary | same panel, `i-lucide-minus` | none (`FlowBuilder.vue:443-449`) |
| 109 | Fit-view button | secondary | same panel, `i-lucide-maximize`, `data-test-id="flow-fit-view"` | none (`FlowBuilder.vue:450-457`) |
| 110 | Errors panel (top-left overlay) | error | `Panel position="top-left"`, `max-w-sm`, `outline-n-ruby-6`, `data-test-id="flow-errors"` | `flowErrors.length \|\| errors.length` (`FlowBuilder.vue:459-464`) |
| 111 | Errors panel title, pluralised count | error | "{n} problems to fix before publishing" | none (`FlowBuilder.vue:465-467`; copy `flowBuilder.json:72`) |
| 112 | Errors list, **first 8 only** | error | `errors.slice(0, 8)`, `dir="auto"` | none (`FlowBuilder.vue:468-480`) |
| 113 | Clicking a node-scoped error selects + centres that node | contextual | `selectNode(id)` + `focusNode(id)`, `cursor-pointer hover:underline` | only when `error.node_id` (`FlowBuilder.vue:471-477`) |
| 114 | Error wording names the node type and the option title | state | `errorLabel()` resolves option ids to titles | `unconnected_output` / `duplicate_output` (`flowGraph.js:209-226`) |
| 115 | 66 distinct error codes have human copy | error | `FLOW_BUILDER.ERRORS.*` | server code (`flowBuilder.json:253-321`) |

### 2.10 Builder — node palette (`NodePalette.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 116 | Palette rail, 7 grouped sections | primary | `aside.hidden.md:flex.w-56.border-e.overflow-y-auto` | **hidden below 768 px** (`NodePalette.vue:25-27`) |
| 117 | Group headings: Messages / Logic / Customer / Commerce / Team / Integration / Flow | state | `h3.text-xs.font-medium.uppercase` | none (`NodePalette.vue:28-31`; groups `flowGraph.js:5-25`) |
| 118 | 20 node types, each with a Lucide icon and label | primary | `li > button` rows | `NODE_ICONS` (`flowGraph.js:27-49`); labels `flowBuilder.json:82-104` |
| 119 | Commerce group hidden without the Commerce feature | state | `groups` filter | `LYNOMIA_COMMERCE` (`NodePalette.vue:14-16`; `FlowBuilder.vue:83-85`) |
| 120 | Drag a type onto the canvas (`cursor-grab`, `draggable="true"`) | primary | palette button | none (`NodePalette.vue:35-40`) |
| 121 | Click a type to place it at canvas centre-ish (`height/3`) | primary | `@click="emit('add', type)"` → `addAtCenter` | none (`NodePalette.vue:41`; `FlowBuilder.vue:229-238`) |
| 122 | New node arrives selected with its config panel open | state | `addNode` sets `selected`, `selectedId`, `panel = CONFIG` | none (`FlowBuilder.vue:219-227`) |
| 123 | New node gets type-specific default data | state | `DEFAULT_DATA` map (e.g. `buttons` starts with one option) | none (`flowGraph.js:59-82`) |

### 2.11 Builder — node on canvas (`FlowNode.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 124 | Fixed-width card (`w-60`) with type icon + type name | state | Node header | none (`FlowNode.vue:52, 68-72`) |
| 125 | Summary preview line (`line-clamp-2`, `dir="auto"`) | state | Node body | first match in the priority chain `text → name·language → labels → url → key → seconds → reason → conditions count` (`FlowNode.vue:27-40`) |
| 126 | One labelled output row + handle per output | state | Node footer, handles `Position.Right` | `nodeOutputs()` from the server contract (`FlowNode.vue:86-111`; `flowGraph.js:86-95`) |
| 127 | Option outputs labelled by option title, or "Untitled option" | state | `outputLabel` | choice nodes (`FlowNode.vue:42-48`) |
| 128 | Optional outputs dimmed (`text-n-slate-10`) | status | Output row class | `nodeTypes[type].optional` (`FlowNode.vue:94-99`; `flowGraph.js:97-98`) |
| 129 | Target handle on top, hidden on Start | state | `Handle type="target"` | `type !== 'start'` (`FlowNode.vue:62-67`) |
| 130 | Error outline (ruby) + alert icon | error | Node outline + `i-lucide-circle-alert` | node id in `errorNodeIds` (`FlowNode.vue:55, 73-77`) |
| 131 | Active-node outline (teal, 2 px) | status | Node outline | `activeNodeId` set by Test/Sessions focus (`FlowNode.vue:56`) |
| 132 | Selected outline (blue, 2 px) | status | Node outline | `selected && !error && !active` (`FlowNode.vue:57`) |
| 133 | `send_template` "failed" output relabelled "Not sent" | state | `outputLabel` special case | `type === 'send_template'` (`FlowNode.vue:45-46`) |

### 2.12 Builder — node config panel (`NodeConfigPanel.vue`)

Panel shell: `aside.absolute.inset-0.z-10.w-full.md:static.md:w-96` — full-screen overlay below 768 px, a 384 px right
rail at and above it (`NodeConfigPanel.vue:132-135`).

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 134 | Panel header: node icon + node type name | state | `header.flex.gap-2.px-4.py-3` | none (`NodeConfigPanel.vue:136-142`) |
| 135 | "Duplicate" node action | secondary | Panel header, tooltip + aria-label | `type !== 'start'` (`NodeConfigPanel.vue:143-152`) |
| 136 | "Delete" node action | destructive | Panel header, `ruby ghost` | `type !== 'start'` (`NodeConfigPanel.vue:153-163`) |
| 137 | Close panel | secondary | Panel header, `i-lucide-x` | none (`NodeConfigPanel.vue:164`) |
| 138 | Duplicate places a copy at +40/+40 with unconnected outputs | state | `duplicateNode` | none (`flowGraph.js:178-189`; `FlowBuilder.vue:272-279`) |
| 139 | Per-node server-error list (ruby block) | error | Top of panel body | `errors.length` (`NodeConfigPanel.vue:168-175`) |
| 140 | **Start**: explanatory hint | state | `START_HINT` paragraph | `type === 'start'` (`NodeConfigPanel.vue:177-180`) |
| 141 | **Start**: trigger keywords (`TagInput`) | primary | "Start only when the first message contains" | `type === 'start'` (`NodeConfigPanel.vue:181-190`) |
| 142 | **Start**: start conditions (optional) | primary | `ConditionsEditor optional` | `type === 'start'` (`NodeConfigPanel.vue:191-199`) |
| 143 | **Message-ish**: body text `TextArea` with character count against the channel limit | primary | `send_message`, `question`, `buttons`, `list` | `capabilities[type].body` / `capabilities.text.body` (`NodeConfigPanel.vue:45-49, 202-213`) |
| 144 | **Message-ish**: "Insert a variable" picker | secondary | A `<select>` acting as an append-command | `variables` (`NodeConfigPanel.vue:214-219`) |
| 145 | **Question**: expected-reply type (any / number / email / phone / keywords) | primary | `Select` | `type === 'question'` (`NodeConfigPanel.vue:73-78, 231-238`) |
| 146 | **Question**: accepted words (`TagInput`) | primary | Conditional sub-field | `reply_type === 'keywords'` (`NodeConfigPanel.vue:239-250`) |
| 147 | **Question**: "Save the reply" scope (none / flow / contact / conversation) | primary | `Select` | `type === 'question'` (`NodeConfigPanel.vue:79-84, 251-258`) |
| 148 | **Question**: flow-variable name input | primary | `Input` with `order_no` placeholder | `store_as.scope === 'context'` (`NodeConfigPanel.vue:259-265`) |
| 149 | **Question**: attribute picker | primary | `ComboBox` over the account's contact/conversation attributes | `store_as.scope` is contact/conversation (`NodeConfigPanel.vue:266-272`) |
| 150 | **Question**: attempts (1-5, default 3) | primary | 2-col grid | `type === 'question'` (`NodeConfigPanel.vue:273-281`) |
| 151 | **Question**: wait minutes (1-1440) | primary | 2-col grid | same (`NodeConfigPanel.vue:282-291`) |
| 152 | **Question**: retry text `TextArea` | secondary | "Ask again with (optional)" | same (`NodeConfigPanel.vue:293-299`) |
| 153 | **List**: list button label + max-chars hint | primary | `Input` with `message` | `type === 'list'` (`NodeConfigPanel.vue:303-311`) |
| 154 | **Buttons/List**: options editor | primary | `OptionsEditor` with channel limits | `['buttons','list']` (`NodeConfigPanel.vue:312-320`) |
| 155 | **Buttons/List**: wait minutes | primary | `Input` | same (`NodeConfigPanel.vue:321-330`) |
| 156 | **Buttons/List**: "each option has its own connection" hint | state | paragraph | same (`NodeConfigPanel.vue:331-333`) |
| 157 | **Condition nodes**: conditions editor, scope-narrowed | primary | `ConditionsEditor` with `scope` | `condition` / `audience_condition` / `commerce_condition` (`NodeConfigPanel.vue:113-121, 336-347`) |
| 158 | **Set attribute**: attribute `ComboBox` + value `Input` | primary | `set_contact_attribute`, `set_conversation_attribute` | `attributeModel` (`NodeConfigPanel.vue:122-128, 349-360`) |
| 159 | **Set attribute**: variable picker limited to `flow.*` | secondary | `Select` filtered | same (`NodeConfigPanel.vue:361-368`) |
| 160 | **Add/Remove label**: multi-select over account labels | primary | `TagMultiSelectComboBox` | `['add_label','remove_label']` (`NodeConfigPanel.vue:371-377`) |
| 161 | **Assign team**: team `ComboBox` | primary | — | `type === 'assign_team'` (`NodeConfigPanel.vue:379-385`) |
| 162 | **Assign agent**: verified-agent `ComboBox` + ownership hint | primary | — | `type === 'assign_agent'` (`NodeConfigPanel.vue:387-397`) |
| 163 | **Order lookup**: mode select (latest order / given order number) | primary | bare `Select`, no label | `type === 'commerce_lookup'` (`NodeConfigPanel.vue:89-92, 399-409`) |
| 164 | **Order lookup**: order-number field with `{{flow.reply}}` placeholder | primary | `Input` | `mode === 'order_number'` (`NodeConfigPanel.vue:410-416`) |
| 165 | **Order lookup**: "only the customer's own orders" hint | state | paragraph | `type === 'commerce_lookup'` (`NodeConfigPanel.vue:417-419`) |
| 166 | **Webhook**: URL input (`type="url"`, `https://` placeholder) + signing hint | primary | — | `type === 'webhook'` (`NodeConfigPanel.vue:422-433`) |
| 167 | **Delay**: seconds (1-86400, default 60) | primary | `Input type=number` | `type === 'delay'` (`NodeConfigPanel.vue:435-443`) |
| 168 | **Handoff**: optional team, optional agent | primary | two `ComboBox`es | `type === 'handoff'` (`NodeConfigPanel.vue:446-457`) |
| 169 | **Handoff**: priority select (keep / low / medium / high / urgent) | primary | bare `Select`, no label | same (`NodeConfigPanel.vue:85-88, 458-462`) |
| 170 | **Handoff**: labels multi-select | secondary | `TagMultiSelectComboBox` | same (`NodeConfigPanel.vue:463-470`) |
| 171 | **Handoff**: note for the team (255 chars) | secondary | `TextArea` | same (`NodeConfigPanel.vue:471-477`) |
| 172 | **Go to**: target node `ComboBox`, labelled "{Type} · {id}", excludes self and Start | primary | — | `type === 'goto'` (`NodeConfigPanel.vue:65-72, 480-486`) |
| 173 | **End**: "Resolve the conversation" checkbox | primary | `Checkbox` in a `<label>` | `type === 'end'` (`NodeConfigPanel.vue:488-497`) |
| 174 | Variable list = server suggestions + `flow.<key>` from every Question that stores to context | state | `flowVariables()` | none (`flowGraph.js:192-199`; `FlowBuilder.vue:99-101`) |

### 2.13 Builder — options editor (`OptionsEditor.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 175 | One card per option (`bg-n-alpha-1 rounded-lg p-2`) | state | — | none (`OptionsEditor.vue:32-36`) |
| 176 | Option title input | primary | — | none (`OptionsEditor.vue:38-49`) |
| 177 | Inline over-length error against the channel title limit | error | `message` + `messageType="error"` | `title.length > limits.title` (`OptionsEditor.vue:42-47`) |
| 178 | Option description input | secondary | — | `withDescription` → List nodes only (`OptionsEditor.vue:59-64`) |
| 179 | Remove option, **disabled at one option** | destructive | `i-lucide-trash-2 ghost slate` | `options.length === 1` (`OptionsEditor.vue:50-57`) |
| 180 | "Add option (up to N)" button, disabled at the channel max | secondary | `blue faded sm` | `options.length < limits.max` (`OptionsEditor.vue:15, 66-76`) |
| 181 | Option ids are stable, so renaming keeps the wiring | state | `newOption()` → `opt_<rand>`; documented at `OptionsEditor.vue:7-8` | none (`flowGraph.js:51-56`) |

### 2.14 Builder — conditions editor (`ConditionsEditor.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 182 | Reuses Automation's `ConditionRow` (attribute / operator / values) | primary | `ul.outline.rounded-xl.p-3` | none (`ConditionsEditor.vue:118-142`) |
| 183 | First row has no AND/OR; later rows do | state | `show-query-operator` branch | row index (`ConditionsEditor.vue:122-141`) |
| 184 | "Add condition" button | secondary | `blue faded sm` inside the `<ul>` | none (`ConditionsEditor.vue:143-152`) |
| 185 | Remove a condition row | destructive | `ConditionRow`'s own `@remove` | none (`ConditionsEditor.vue:130, 140`) |
| 186 | Field list narrowed by scope: all / audience / commerce | state | `SCOPES` map + `filterTypes` | `scope` prop from the node type (`ConditionsEditor.vue:25-29, 49-55`) |
| 187 | One empty row auto-added unless `optional` | state | `if (!rows.length && !optional) addRow()` | Start node passes `optional` (`ConditionsEditor.vue:105`) |
| 188 | Existing conditions decoded with Automation's own converter | state | `formatAutomation(...)` on mount | none (`ConditionsEditor.vue:93-107`) |
| 189 | Custom attributes and Lynomia conditions manifested before use | state | `loadLynomiaOptions` + `manifest*` | none (`ConditionsEditor.vue:94-96`) |

### 2.15 Builder — WhatsApp template editor (`TemplateEditor.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 190 | Template-sending explainer (24-hour window, "Failed" output) | state | `TEMPLATE_HINT` paragraph | none (`TemplateEditor.vue:166-168`) |
| 191 | "No approved template" amber warning | empty | `bg-n-amber-2` block | `!templateOptions.length` (`TemplateEditor.vue:169-174`) |
| 192 | Template `ComboBox`, labelled "{name} · {language}" | primary | — | none (`TemplateEditor.vue:175-185`) |
| 193 | Candidate list = approved/sendable templates of the flow's WhatsApp Cloud inboxes, or of all of them while none is connected | state | `templateInboxes` + `inboxes/getFilteredWhatsAppTemplates` | `provider === 'whatsapp_cloud'` (`TemplateEditor.vue:29-48`) |
| 194 | Stored label kept when the template is gone (`displayLabel`) | state | `storedLabel` | stored `name` (`TemplateEditor.vue:62-66, 180`) |
| 195 | "No longer available on these inboxes" ruby warning | error | paragraph | `modelValue.name && !template` (`TemplateEditor.vue:186-188`) |
| 196 | Rendered body preview with values substituted | state | `renderTemplatePreview`, `bg-n-alpha-2 rounded-xl`, `dir="auto"` | body component resolvable (`TemplateEditor.vue:79-82, 189-196`) |
| 197 | One field per template parameter: header vars, media URL, media file name, body vars, button values, copy-code | primary | `fields` computed | parameter shape from `buildTemplateParameters` (`TemplateEditor.vue:90-140, 197-208`) |
| 198 | Per-field "Insert a variable" picker | secondary | `Select` under each field | `field.variables?.length` (`TemplateEditor.vue:209-215`) |
| 199 | Copy-code buttons restricted to `flow.*` variables | state | `flowVariables` | `button.type === 'copy_code'` (`TemplateEditor.vue:84-86, 129-137`) |
| 200 | Fields read from stored values, so a deleted template still shows what the node holds | state | documented at `TemplateEditor.vue:88-89` | none |

### 2.16 Builder — Test panel (`TestPanel.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 201 | Panel shell, full-screen below 768 px / 384 px rail above | state | `aside.absolute.inset-0.z-10.md:static.md:w-96` | none (`TestPanel.vue:91-94`) |
| 202 | Title "Test the draft" | state | Panel header | none (`TestPanel.vue:96-98`) |
| 203 | "Start over" action | secondary | `i-lucide-rotate-ccw`, tooltip + aria-label | none (`TestPanel.vue:99-107`) |
| 204 | Close panel | secondary | `i-lucide-x` | none (`TestPanel.vue:108`) |
| 205 | Safety hint: "nothing is sent, saved or posted" | state | `TEST.HINT` paragraph | none (`TestPanel.vue:110-112`) |
| 206 | Chat transcript, customer right / bot left | state | `self-end` vs `self-start`, `max-w-[85%]`, `dir="auto"` | none (`TestPanel.vue:113-131`) |
| 207 | Customer bubble (blue), bot bubble (alpha), note bubble (amber, smaller) | state | bubble class map | `entry.from` (`TestPanel.vue:124-128`) |
| 208 | "Template: {name}" annotation under a bubble | state | `data-test-id="flow-test-template"` | `entry.template` (`TestPanel.vue:132-138`) |
| 209 | List-button label annotation | state | span | `entry.list_button` (`TestPanel.vue:139-141`) |
| 210 | Tappable reply options, sending the option id as WhatsApp does | primary | `blue faded xs` buttons | enabled only on the latest bot turn and when not running (`TestPanel.vue:142-154, 34-36`) |
| 211 | Session state line ("Waiting for the customer · …") | status | `data-test-id="flow-test-state"` | `result` present (`TestPanel.vue:37-47, 156-162`) |
| 212 | "The flow did not start…" state | status | `NOT_STARTED` | result with no session (`TestPanel.vue:39`) |
| 213 | End reason / failure code in words | status | `reasonLabel` | `end_reason` or `failure_code` (`TestPanel.vue:40-46`; `flowGraph.js:202-205`) |
| 214 | "Steps" collapsible trace (`node_id → result`, `dir="ltr"`) | state | native `<details>` | `path.length` (`TestPanel.vue:29-33, 163-170`) |
| 215 | Inline error text (ruby) | error | paragraph | `error` (`TestPanel.vue:171`) |
| 216 | "This test is too long. Start over." | error | client-side guard at 30 inputs | `next.length > MAX_INPUTS` (`TestPanel.vue:19, 50-53`) |
| 217 | Server error code mapped to `FLOW_BUILDER.ERRORS.*`, else "The test could not run." | error | `catch` in `run` | response shape (`TestPanel.vue:62-67`) |
| 218 | "Skip the wait" timer button | secondary | `slate faded sm`, `i-lucide-timer` | `session?.timer` (`TestPanel.vue:174-183`) |
| 219 | Message composer (input + submit) | primary | `<form @submit.prevent>` | submit disabled unless `draft.trim()` (`TestPanel.vue:184-197`) |
| 220 | Send spinner | state | `:is-loading="isRunning"` | `isRunning` (`TestPanel.vue:194`) |
| 221 | Every run saves the dirty draft first | state | `beforeRun` → `saveIfDirty` | `isDirty` (`TestPanel.vue:57`; `FlowBuilder.vue:175-177, 501`) |
| 222 | Each run replays the whole input list | state | `run([...inputs, next])` | none (`TestPanel.vue:72-81`; documented `TestPanel.vue:9-11`) |
| 223 | The reached node is highlighted on the canvas | contextual | `emit('node', current_node_id)` → `focusNode` | none (`TestPanel.vue:61`; `FlowBuilder.vue:281-285`) |
| 224 | "Start over" clears the canvas highlight too | state | `emit('node', null)` | none (`TestPanel.vue:86`) |

### 2.17 Builder — Sessions panel (`SessionsPanel.vue`)

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 225 | Panel shell, full-screen below 768 px / 384 px rail above | state | `aside.absolute.inset-0.z-10.md:static.md:w-96` | none (`SessionsPanel.vue:63-66`) |
| 226 | Title "Sessions" | state | Panel header | none (`SessionsPanel.vue:68-70`) |
| 227 | Refresh action | secondary | `i-lucide-refresh-cw`, `:is-loading` | none (`SessionsPanel.vue:71-78`) |
| 228 | Close panel | secondary | `i-lucide-x` | none (`SessionsPanel.vue:79`) |
| 229 | Status filter (All + 6 statuses) | filter | `Select`, reloads on change | none (`SessionsPanel.vue:19-37, 81-83`; `watch` at `:59`) |
| 230 | Session status label (Running / Waiting / Handed to the team / Completed / Failed / Cancelled) | status | Row heading | none (`SessionsPanel.vue:98-102`; copy `flowBuilder.json:220-227`) |
| 231 | "Node X · version N · M steps" detail line | state | Row | none (`SessionsPanel.vue:113-121`) |
| 232 | End reason / failure code in words | status | Row | `end_reason \|\| failure_code` (`SessionsPanel.vue:49-52, 122-124`) |
| 233 | Last-updated timestamp (`toLocaleString()`) | state | Row | none (`SessionsPanel.vue:125-127`) |
| 234 | **Contextual link out to the conversation** (`#id`, new tab) | contextual | Row, `target="_blank" rel="noopener noreferrer"`, `@click.stop` | none in this component; the conversation route enforces its own access (`SessionsPanel.vue:53-56, 103-111`) |
| 235 | Clicking a row centres that session's current node on the canvas | contextual | `emit('node', current_node_id)` → `focusNode` | none (`SessionsPanel.vue:95`) |
| 236 | "No sessions yet." empty text | empty | paragraph | `!sessions.length && !isLoading` (`SessionsPanel.vue:84-89`) |

### 2.18 Builder — states and guards

| # | Feature | Kind | Where it lives today | Gating |
| --- | --- | --- | --- | --- |
| 237 | Loading: bare centred `Spinner`, whole canvas area | loading | `v-if="isLoading"` branch | `isLoading` (`FlowBuilder.vue:413-415`) |
| 238 | Error: "The flows could not be loaded." + redirect to list | error | `load()` catch | request failure (`FlowBuilder.vue:146-150`) |
| 239 | Error: "The draft could not be saved." + server errors rendered | error | `save()` catch | save failure (`FlowBuilder.vue:166-169`) |
| 240 | Error: "The flow could not be published. Fix the problems shown on the canvas." | error | `publish()` catch | publish failure (`FlowBuilder.vue:189-193`) |
| 241 | Unsaved-changes route guard (native `window.confirm`) | state | `onBeforeRouteLeave` | `isDirty` (`FlowBuilder.vue:293-296`) |
| 242 | Unsaved-changes tab-close guard (browser prompt) | state | `beforeunload` listener | `isDirty` (`FlowBuilder.vue:300-304`) |
| 243 | Only one side panel open at a time | state | single `panel` ref; opening Test/Sessions clears `selectedId` | none (`FlowBuilder.vue:287-291`) |
| 244 | Closing the last panel clears the canvas highlight | state | `if (!panel.value) activeNodeId = null` | none (`FlowBuilder.vue:290`) |
| 245 | Config panel waits for `capabilities` before rendering | state | `v-if="… && capabilities"` | server payload (`FlowBuilder.vue:484-485`) |
| 246 | Config panel remounts per node (`:key="selectedNode.id"`) | state | — | none (`FlowBuilder.vue:486`) |
| 247 | Agents fetched on mount; labels/teams/inboxes/attributes reused from the sidebar's cache | state | `store.dispatch('agents/get')` only, by design | none (`FlowBuilder.vue:318-323`) |

**Not present anywhere on this surface** (recorded so a redesign is not credited for adding them back as "parity"):
undo/redo, copy/paste of nodes, multi-select of nodes, auto-layout, a minimap, a canvas dot-grid background, edge
labels or arrowheads, edge deletion by click, node search on the canvas, a palette search box, a version history view,
a diff between draft and published, publish confirmation, keyboard navigation of the canvas, and any mobile-specific
affordance of any kind.

---

## 3. Visual audit

Severity is about user impact on this surface. Each finding carries file:line evidence.

### V-01 — Nine icon-only controls still have no accessible name (high · a11y)

An `aria-label` pass has landed on some of these, which makes the remaining gaps sharper rather than softer. Still
unlabelled today:

- Builder back arrow — `FlowBuilder.vue:331-338` (no `label`, no tooltip, no `aria-label`).
- Zoom in / zoom out / fit view — `FlowBuilder.vue:442`, `:443-449`, `:450-457`.
- Config panel close — `NodeConfigPanel.vue:164`.
- Test panel close — `TestPanel.vue:108`.
- Sessions panel refresh and close — `SessionsPanel.vue:71-78`, `:79`.
- Test composer submit — `TestPanel.vue:191-197`.

`Button.vue:240-260` renders only an `Icon` when there is no `label`, so these are buttons whose entire accessible name
is empty. The three zoom controls are also the only way to reset a lost viewport, and they have neither a name nor a
tooltip.

### V-02 — Clickable `<li>` elements: errors and sessions are mouse-only (high · a11y)

- Error rows: `FlowBuilder.vue:469-477` — `<li :class="{'cursor-pointer hover:underline': error.node_id}" @click="…">`.
  No `tabindex`, no `role="button"`, no key handler. Jumping from a validation error to the offending node — the main
  repair loop of the whole surface — is unreachable by keyboard.
- Session rows: `SessionsPanel.vue:91-96` — `<li class="… cursor-pointer" @click="emit('node', …)">`. Same problem. The
  conversation `<a>` nested inside it (`:103-111`) *is* focusable, which makes the keyboard experience actively
  confusing: you can tab to the link but not to the row that the link sits in.

### V-03 — Five form controls on this surface have no label at all (high · form)

- Order-lookup mode: `NodeConfigPanel.vue:400-409` — a `Select` with neither `placeholder` nor surrounding text. The
  user sees "The customer's latest order" and has to infer the question.
- Handoff priority: `NodeConfigPanel.vue:458-462` — same pattern; the only cue is the first option, "Keep priority".
- Connect-inbox select: `FlowBuilder.vue:361-367` — a placeholder-as-label, and `Select.vue:36-39, 53` accepts an
  `ariaLabel` prop that is not passed.
- Sessions status filter: `SessionsPanel.vue:81-83` — no label, no `ariaLabel`; it is a bare select under a header.
- Every "Insert a variable" picker: `NodeConfigPanel.vue:214-219`, `:361-368`, `TemplateEditor.vue:209-215`.

### V-04 — A `<select>` is used as a command menu (high · consistency)

"Insert a variable" is implemented as `<Select model-value="" :placeholder="…" @update:model-value="appendVariable(…)">`
(`NodeConfigPanel.vue:214-219`). It is not a value the node stores; it is an action that appends `{{var}}` to a text
field. Consequences that are visible to users: the control never shows a selection, the placeholder option is
`disabled` (`Select.vue:62-64`) so re-inserting the same variable twice requires choosing something else first, and
screen readers announce a listbox where a menu belongs. In a template with five body variables this control is
repeated five times down the panel (`TemplateEditor.vue:197-216`).

### V-05 — Pseudo-labels: bare text in a `<div>` standing in for `<label>` (medium · form)

`NodeConfigPanel.vue:191-199` (Start conditions), `:312-320` (Options), `:336-347` (Conditions) and
`TemplateEditor.vue:175-185` (Template) all use `<div class="flex flex-col gap-1 text-sm text-n-slate-12">{{ text }}`
followed by the control. Visually it reads as a label; programmatically there is no association. Three sibling fields in
the same panel do it correctly with the primitive's own `label` prop (`:205-207`, `:262`, `:279`), so the panel is
inconsistent with itself.

### V-06 — Seven competing controls in one header row (high · density)

`FlowBuilder.vue:347-409` puts, in one `ms-auto` group: N inbox chips, a connect `<select>`, Sessions, Test,
Save draft, Disable, Publish. Four of the five buttons are `sm`; three different colour/variant pairs are in play
(`slate faded`, `slate solid`, `ruby faded`, blue solid). Nothing separates "inspect" (Sessions, Test) from "commit"
(Save, Publish) from "take offline" (Disable) — no divider, no grouping, no spacing change. The single most consequential
action on the page, Publish, is distinguished from the adjacent Save draft only by fill colour.

### V-07 — Publish is always enabled, including with known-blocking errors (high · cta-clarity)

`FlowBuilder.vue:403-409` has no `:disabled`. Save draft next to it *is* gated (`:391`). So the one button that cannot
succeed while the errors panel lists "3 problems to fix before publishing" is the one that stays bright blue and
clickable; the user's only feedback is a failed round-trip and the toast at `:192`. Disable, which is far less
destructive, gets a confirmation dialog (`:514-521`); Publish, which changes what customers receive, gets none.

### V-08 — The same state is coloured two different ways in two views (medium · consistency)

"Unpublished changes" is amber in the list — `Index.vue:245`, `class="block text-xs text-n-amber-11"` — and plain muted
grey in the builder, where it is concatenated into one sentence with a middle dot and loses all emphasis:
`FlowBuilder.vue:118-121` produces `Published · version 3 · Unpublished changes` rendered at
`text-xs text-n-slate-11` (`:343-345`). "Unsaved changes", the most urgent of the three states, gets exactly the same
muted treatment. A user who glances at the builder header cannot tell a saved flow from an unsaved one.

### V-09 — The status logic is written twice (medium · consistency)

`Index.vue:151-158` and `FlowBuilder.vue:108-122` independently derive published/not-published/unpublished from the same
payload fields. Any later change to the status vocabulary has to be made in both, and today they already disagree on
presentation (V-08).

### V-10 — The empty state inverts the button hierarchy of the header (medium · consistency)

Header: Templates is `color=slate variant=faded`, New flow is default blue solid (`Index.vue:175-188`).
Empty state: Templates is default blue solid, New flow is `slate faded` (`Index.vue:206-218`).
Same two actions, opposite emphasis, roughly 200 px apart vertically on the same screen. One of the two is wrong and
there is no comment explaining the intent.

### V-11 — The empty state is text-only and gives no sense of what a flow is (medium · empty-state)

`Index.vue:194-220`: two paragraphs and two buttons in a `py-16` centred column. No illustration, no example flow, no
node preview, no link to documentation — on a surface whose core object is a visual graph. `BaseSettingsHeader` has an
unused `linkText`/`featureName` pair that renders a help-centre link (`BaseSettingsHeader.vue:73-87`), and the page
passes neither.

### V-12 — A 4-column table with no horizontal scroll container (high · table)

`Index.vue:221` passes neither `scrollable` nor `stickyHeader`. `BaseTable.vue:47-54` documents the default explicitly:
"Off by default: on a phone it trades a control that is visible-but-escaping for one that needs a horizontal swipe."
Two of the four cells are `max-w-0` (`Index.vue:225`, `:257`) so they collapse, and the action cell is declared `w-24`
(96 px) for content that measures 3 × 32 px buttons + 2 × 12 px gaps = 120 px (`Index.vue:265-294`). At narrow widths
the table pushes `SettingsWrapper`'s `overflow-auto` (`SettingsWrapper.vue:23`) into a whole-page sideways scroll.

### V-13 — The list has no sorting, search, filter, pagination or bulk actions (medium · table)

`BaseTable` supports sorting (`sortableColumns`, `sortBy`, `sortOrder`, `@sort` — `BaseTable.vue:22-36, 107-126`) and
`BaseSettingsHeader` supports a search box, tabs and a count (`BaseSettingsHeader.vue:92-128`). None is wired. For an
account with twenty flows the only way to find one is to read the whole column. There is also no selection model at all,
so there are no bulk actions to preserve.

### V-14 — The disabled Delete button never says why (medium · cta-clarity)

`Index.vue:284-293`: when a flow is published, Delete is disabled and its tooltip still reads "Delete". The reason — a
published flow must be disabled first — lives only inside the confirmation dialog the user cannot reach
(`flowBuilder.json:33`) and in a server error string (`ERRORS.FLOW_ACTIVE`, `flowBuilder.json:311`). The same pattern
repeats in the options editor: the remove button is disabled at one option (`OptionsEditor.vue:50-57`) with no tooltip.

### V-15 — Three ways to open a flow, two of them on the same row (low · consistency)

`Index.vue:226-237` (name as button), `:267-274` ("Open builder" icon) and the implicit row affordance. The row itself is
not clickable — only the name text is — so the large hover highlight from `BaseTableRow` (`BaseTableRow.vue:187-189`)
suggests a click target that mostly does nothing.

### V-16 — The errors panel truncates silently at eight (high · loading-error)

`FlowBuilder.vue:466` counts `errors.length` in the title; `:470` renders `errors.slice(0, 8)`. A flow with fifteen
problems shows "15 problems to fix before publishing" above eight rows, with no "+7 more", no scroll and no way to see
the rest. The panel is also the only place flow-level (non-node) errors appear at all.

### V-17 — The errors-panel visibility condition is redundant (low · loading-error)

`FlowBuilder.vue:460`: `v-if="flowErrors.length || errors.length"`. `flowErrors` is defined at `:95` as a filtered
subset of `errors`, so the first clause can never be the deciding one. Harmless today, but it reads as if flow-level
errors were handled separately when they are not.

### V-18 — The errors panel sits on top of the graph (medium · spacing)

`Panel position="top-left"` with `max-w-sm` (`FlowBuilder.vue:459-462`) and Vue Flow's own `margin: 15px; z-index: 5`
(`@vue-flow/core/dist/style.css:217-221`). Nothing offsets the graph or the fit-view padding to account for it, so on a
freshly fitted flow the panel covers the Start node — which, since Start is the node most error messages are about, is
precisely the node the user is trying to look at.

### V-19 — Edges carry no direction, label or state (medium · hierarchy)

`flowGraph.js:110-115` builds edges with `{id, source, sourceHandle, target}` only — no `type`, no `markerEnd`, no
`animated`, no `label`. Vue Flow's default is an unmarked bezier. On a graph where a "Yes" and a "No" branch cross each
other, there is nothing on the wire itself that says which way it flows or which output it left from; the only cue is the
output label on the source node, which may be far off-screen.

### V-20 — No canvas background, so panning has no frame of reference (medium · hierarchy)

The pane is a flat fill: `class="bg-n-surface-2"` (`FlowBuilder.vue:432`). `@vue-flow/background` is not imported
(`FlowBuilder.vue:2, 6` import only core and its stylesheet). Without a dot or line grid there is no parallax and no
sense of scale while panning or zooming, and no minimap to recover from a lost viewport — only the unlabelled fit-view
button from V-01.

### V-21 — The native `window.confirm` breaks out of the design system (medium · consistency)

`FlowBuilder.vue:293-296` guards navigation with `window.confirm(t('FLOW_BUILDER.UNSAVED_CONFIRM'))` (with an
`eslint-disable no-alert` on the line above). Every other confirmation on this surface is a themed `Dialog` — delete
(`Index.vue:335-342`), disable (`FlowBuilder.vue:514-521`). So the highest-frequency confirmation on the surface is the
only one rendered as an OS dialog, with no theming, no RTL handling and no "Save and leave" option.

### V-22 — Four typographic dialects inside one surface (medium · consistency)

The repo convention (`CLAUDE.md`: "Use typography utilities instead of manually recreating font styles") is followed in
some places and not in others, within the same component tree:

- `text-heading-1` — list page title (`BaseSettingsHeader.vue:57`).
- `text-body-main` — list cells (`Index.vue:231, 234, 258`).
- `text-label-small` — node header on canvas (`FlowNode.vue:70`).
- Hand-rolled: `text-base font-medium` (builder `h1`, `FlowBuilder.vue:340`), `text-sm font-medium` (all three panel
  `h2`s — `NodeConfigPanel.vue:140`, `TestPanel.vue:96`, `SessionsPanel.vue:68`), `text-xs font-medium uppercase`
  (palette group headings, `NodePalette.vue:29`), and raw `text-xs` for every status and hint line.

The practical effect: the builder's own `h1` is visually smaller than the list's `h1`, and the three side panels'
headings are a size that exists nowhere in the token set.

### V-23 — The flow list and the builder share no chrome (medium · navigation)

The list is a `max-w-5xl` centred settings column (`SettingsWrapper.vue:23-25`); the builder is full-bleed with its own
header (`flows.routes.js:23-28`). There is no breadcrumb, no "Settings › Flow Builder › {name}" trail, and no visible
page title in the browser-chrome sense. The only way back is an unlabelled arrow (V-01). `BaseSettingsHeader` has a
`backButtonLabel` affordance (`BaseSettingsHeader.vue:45-50`) that this surface never uses.

### V-24 — Mobile (<768 px): nodes cannot be added at all (high · mobile)

`NodePalette.vue:25-27` is `class="hidden md:flex …"`. The palette is the **only** caller of the add path — the click
handler emits `add` (`:41`) into `addAtCenter` (`FlowBuilder.vue:229-238`), and the drag handler sets the drop MIME type
(`:18-21`) consumed by `onDrop` (`FlowBuilder.vue:240-244`). Below 768 px both are gone, and no replacement exists: no
long-press-to-add, no "+" FAB, no bottom sheet. The builder is therefore read / move / configure / test / publish only
on a phone. Everything else on the surface still works, which makes the single missing capability easy to miss in
testing.

### V-25 — Mobile (<768 px): the app's own floating buttons sit on top of the zoom controls (high · mobile)

- `MobileSidebarLauncher.vue:42` — `class="fixed bottom-4 ltr:left-4 rtl:right-4 z-40 … block md:hidden"`.
- The zoom/fit panel — `FlowBuilder.vue:441` `Panel position="bottom-left"`, i.e. `bottom: 0; left: 0; margin: 15px;
  z-index: 5` (`@vue-flow/core/dist/style.css:217-233`).

In LTR these occupy the same 16 px corner, and the launcher's `z-40` is above the panel's `z-index: 5`, so the sidebar
button covers the zoom controls. In RTL the launcher moves to the right and `CopilotLauncher.vue:55`
(`fixed bottom-4 ltr:right-4 rtl:left-4 z-50`) takes its place over the same corner — the collision survives the
direction flip, it just changes which button causes it.

### V-26 — Mobile (390 px): the header can consume a quarter of the viewport (high · mobile)

`FlowBuilder.vue:328-330` is `flex flex-wrap … gap-3 px-4 py-3`, and the action group at `:347` is itself
`flex flex-wrap … gap-2`. At 390 px there are ~358 px of usable width for: back arrow, title block, N inbox chips, the
connect `<select>` (`Select.vue:49` is `w-fit`, and "Connect a WhatsApp inbox" is ~210 px), plus five buttons —
Sessions (icon + label), Test (icon + label), Save draft, Disable, Publish. That wraps to roughly four or five rows:
header height lands near 170-200 px before any canvas is visible, on a viewport that is typically 664-844 px tall. The
title and the status line are the first things pushed into a cramped row, and the status line is the smallest text in
the header (V-08).

### V-27 — Mobile (390 px): the side panels become full-screen with no visible way back to the canvas (medium · mobile)

All three panels are `absolute inset-0 z-10 … md:static md:w-96` (`NodeConfigPanel.vue:133`, `TestPanel.vue:92`,
`SessionsPanel.vue:64`). Below 768 px they cover the canvas completely. The close affordance is the unlabelled
`i-lucide-x` from V-01, the panels keep their `border-s` (pointless when they are full-bleed), and there is no swipe-down,
no backdrop, no `Esc` handler — `useKeyboardEvents` registers only `$mod+KeyS` (`FlowBuilder.vue:308-316`). On a phone,
selecting a node means losing sight of the graph entirely.

### V-28 — Tablet (768-1024 px): chrome can exceed the canvas (medium · mobile)

At and above 768 px the palette is 224 px (`w-56`) and an open panel is 384 px (`w-96`) — 608 px of fixed chrome inside
the builder, before the dashboard sidebar (`Sidebar.vue:892`, `md:w-auto md:relative`, user-resizable). At 768 px with a
panel open there is less canvas than chrome, and `FlowNode` is a fixed `w-60` = 240 px (`FlowNode.vue:52`), so barely one
node fits across. Neither the palette nor the panels are collapsible at any width.

### V-29 — RTL: the graph reads left-to-right while the palette sits on the right (medium · rtl)

The app sets `dir` globally (`App.vue:141`). The builder root carries no `dir` override, so in Arabic the content row
(`FlowBuilder.vue:416`) reverses: NodePalette lands on the **right**, the config panel on the **left**. But the canvas
is hard-pinned LTR (`:418`, `dir="ltr"`), and `FlowNode` hard-codes `Position.Top` for inputs and `Position.Right` for
outputs (`FlowNode.vue:64, 106`). The result for an Arabic user: the source of nodes is on the right, the graph grows
away from it to the right, the zoom controls stay physically bottom-left (V-25), and the "Go to" / error links move the
viewport in a direction that does not match the reading order. The logical borders (`border-e` on the palette,
`border-s` on the panels) do flip correctly, so the layout looks intentional while the flow direction does not.

### V-30 — RTL: the Copilot launcher covers the panels' bottom-left (low · rtl)

`CopilotLauncher.vue:55` is `fixed bottom-4 ltr:right-4 rtl:left-4 z-50`. In RTL at ≥768 px the panels occupy the left
edge (V-29), so the launcher overlaps the bottom of whichever panel is open — in the Test panel's case, directly over
the composer row (`TestPanel.vue:184-197`).

### V-31 — The Sessions panel has no loading state and no error state (high · loading-error)

`SessionsPanel.vue:39-47`: `try { … } finally { isLoading = false }` — there is **no `catch`**. A failed
`FlowsAPI.sessions` call rejects unhandled, the list stays empty, and nothing is shown. Compounding it, the empty
message is gated on `!sessions.length && !isLoading` (`:85`), so during the first load the panel renders a title, a
filter and nothing else. The only loading cue is the spinner inside the refresh button (`:76`), which a user who did not
click refresh has no reason to look at.

### V-32 — Inbox connect / disconnect and Disable fail silently (high · loading-error)

Three mutations have no error path:

- `connectInbox` — `FlowBuilder.vue:205-211`, no `try/catch`. On failure the select has already been changed, nothing is
  reported, and `inboxToConnect` is never reset.
- `disconnectInbox` — `:213-216`, no `try/catch` and no success toast either, so a working disconnect and a failed one
  look identical (the chip disappears only because `load()` refetches).
- `disable` — `:198-203`, no `try/catch`; the dialog closes first (`:199`), so a failure leaves the user believing the
  flow is off while it is still answering customers.

Compare `save` (`:166-172`) and `publish` (`:189-194`), which do handle failure. Within one component, half the
mutations report errors and half do not.

### V-33 — The conditions editor pops in after mount with no placeholder (medium · loading-error)

`ConditionsEditor.vue:93-107` awaits `loadLynomiaOptions()` and only then fills `rows`. The template renders
immediately, so the user first sees an empty outlined box with just an "Add condition" button, and rows appear
afterwards. A `ready` flag exists (`:42, 106`) but gates only the write-back watcher (`:112`), not the rendering.

### V-34 — `<div>` as a direct child of `<ul>` (low · a11y)

`ConditionsEditor.vue:119-153`: the `<ul>` contains `ConditionRow` components (which render `<li>`, `ConditionRow.vue:184`)
**and** a bare `<div>` wrapping the Add button (`:143-152`). Invalid list content; assistive tech announcing "list, N
items" will miscount, and the add action is outside the list semantics it visually belongs to.

### V-35 — Disabled historical reply buttons with no explanation (low · cta-clarity)

`TestPanel.vue:142-153`: every bot turn keeps its option buttons, but they are
`:disabled="isRunning || index !== lastBotIndex"`. Scrolling up a transcript shows rows of greyed-out buttons that look
broken rather than historical. No tooltip, no visual distinction between "disabled because it is in the past" and
"disabled because a run is in flight".

### V-36 — Instrumentation is uneven (low · consistency)

`data-test-id` is applied to about half the interactive elements. Present: `flow-templates-button`, `flow-new-button`,
`flow-empty-templates`, `flow-duplicate-{id}`, `flow-name-input`, `flow-save-button`, `flow-publish-button`,
`flow-test-button`, `flow-fit-view`, `flow-errors`, `flow-status`, `flow-node-{id}`, `flow-handle-{id}-{output}`,
`flow-palette-{type}`, `flow-config-panel`, `flow-config-text`, `flow-node-delete`, `flow-test-panel`,
`flow-sessions-panel`, `flow-template-*`. Missing on comparable controls: the empty-state "New flow" button
(`Index.vue:212-218`), the list open/delete buttons (`:267-274`, `:284-293`), the Sessions and Disable header buttons
(`FlowBuilder.vue:368-375`, `:395-402`), the three zoom buttons (`:441-457`), and the inbox connect select (`:361-367`).

### V-37 — Tooltip coverage is arbitrary (low · consistency)

`v-tooltip.top` on list actions and the two node actions; `v-tooltip.bottom` on Save draft; nothing on the zoom
controls, panel closes, Sessions, Test, Disable, Publish or the back arrow (`FlowBuilder.vue:331-409`, `:441-457`). Two
tooltip placements and three different labelling strategies (tooltip-only, tooltip + aria-label, neither) coexist within
a 60-line header.

### V-38 — No undo (high · hierarchy)

There is no undo, no redo and no edit history anywhere on the surface — not in `FlowBuilder.vue`, not in `flowGraph.js`,
and `useKeyboardEvents` binds only `$mod+KeyS` (`FlowBuilder.vue:308-316`). Meanwhile `Delete`/`Backspace` deletes the
selected node outright with no confirmation (`:431`), and `deleteSelected` also drops every edge touching it
(`:263-270`). The only recovery is to leave without saving and accept the `window.confirm` from V-21, losing every other
edit in the session. On a direct-manipulation canvas this is the largest single gap in the surface.

---

## 4. What this surface already does well and must not be lost

1. **The server owns the contract, and the UI is honest about it.** Node types, their outputs, which outputs are
   optional, and the channel limits all come from the `show` payload and are rendered rather than re-implemented
   (`flowGraph.js:1-3, 86-98`; `FlowBuilder.vue:128-134`). Character limits in the config panel are the *actual* channel
   limits (`NodeConfigPanel.vue:45-49`), and option counts come from `capabilities[type]`
   (`NodeConfigPanel.vue:316`). A redesign must keep pulling these from the payload, never hard-code them.

2. **Validation errors are a navigable repair loop, not a wall of text.** The server returns `{code, node_id, detail}`;
   `errorLabel` turns it into "Buttons: Connect the output "Track my order"" by resolving the option id to its title
   (`flowGraph.js:209-226`). The error marks the node on the canvas (`FlowNode.vue:55, 73-77`), appears again inside that
   node's config panel (`NodeConfigPanel.vue:168-175`), and clicking the list entry selects **and** centres the node
   (`FlowBuilder.vue:471-477`). Three coordinated surfaces for one error. Keep all three.

3. **Dirty-state tracking is structural, not a flag.** `isDirty` compares a serialised `fromCanvas` snapshot against the
   last saved one (`FlowBuilder.vue:77-81`), so it is immune to Vue Flow's internal node churn — moving a node by one
   pixel and back is correctly *not* dirty. It then drives Save's disabled state, the status line, the route guard and
   the `beforeunload` guard from one source.

4. **Test Mode is the real runtime, and says so.** The draft is saved first (`TestPanel.vue:57`), run server-side and
   rolled back; the panel states plainly that "nothing is sent, saved or posted" (`flowBuilder.json:205`). The transcript
   renders actual WhatsApp affordances — tappable buttons that send the option **id** as WhatsApp does
   (`TestPanel.vue:142-153`), list button labels, template annotations, a "Skip the wait" control for timer nodes
   (`:174-183`) — and highlights the reached node on the canvas (`:61` → `FlowBuilder.vue:281-285`).

5. **Three safety nets around destructive and irreversible acts.** Route-leave guard, `beforeunload` guard
   (`FlowBuilder.vue:293-304`), delete-blocked-while-published (`Index.vue:290`), and a confirmation for Disable that
   explains the consequence in product terms — "conversations in it now go to your team" (`flowBuilder.json:38`).

6. **`Cmd/Ctrl+S` works while a config field has focus.** `allowOnFocusedInput: true` with a comment explaining why
   (`FlowBuilder.vue:306-315`): that is exactly the moment the draft is worth keeping. Keep the flag, and keep the
   tooltip that teaches the shortcut (`:386`).

7. **Option ids are stable, so renaming never breaks wiring.** `newOption()` mints `opt_<rand>`
   (`flowGraph.js:51-56`), routing is by id, and `fromCanvas` drops only edges whose output genuinely no longer exists
   (`:138-139`). The editor's comment states the contract (`OptionsEditor.vue:7-8`).

8. **The canvas tells three different stories with three different outlines.** Error (ruby), test/session-active (teal),
   selected (blue), with a deterministic precedence (`FlowNode.vue:54-59`). Optional outputs are dimmed rather than
   hidden (`:94-99`), which is how a user learns that leaving one unconnected hands the conversation to a human.

9. **Conditions are Automation's conditions, not a parallel engine.** `ConditionsEditor` reuses `ConditionRow`,
   `useAutomation`, `formatAutomation` and `generateAutomationPayload` (`ConditionsEditor.vue:1-13`), with `scope`
   narrowing the field list for Audience and Commerce nodes (`:25-29, 49-55`). Users carry one mental model across both
   modules.

10. **Templates and duplicates produce ordinary editable objects.** Both paths use the plain `create` + `saveDraft` calls
    and then open the builder (`Index.vue:76-128`); the result is unpublished and inbox-less, so nothing reaches a
    customer until the user publishes (`:106-108`). Provenance is written into the description (`:113-117`). A template
    whose requirements the account does not meet is shown with what is missing and no Create button
    (`RecipeDialog.vue:136-153`).

11. **Per-string direction handling where it matters.** `dir="auto"` on the node summary (`FlowNode.vue:81`), the error
    list (`FlowBuilder.vue:468`), chat bubbles (`TestPanel.vue:122`), the template preview
    (`TemplateEditor.vue:191`) and recipe descriptions (`RecipeDialog.vue:133`); `dir="ltr"` pinned on the step trace
    where node ids must read left-to-right (`TestPanel.vue:167`); `rtl:rotate-180` on the back arrow
    (`FlowBuilder.vue:336`). Mixed Arabic/English flow content renders correctly today — preserve this, and fix the
    structural RTL problems in V-29 without removing it.

12. **The copy is written for the person doing the job.** "Start only when the first message contains",
    "No reply in time", "Nothing connected to "{output}"", "The 24-hour WhatsApp window closed",
    "A published flow must be disabled first". 66 error codes and 24 session reasons all have plain-language strings
    (`flowBuilder.json:228-321`). This vocabulary is an asset; a redesign should re-use these keys rather than
    re-word them.

13. **Session inspection links out to the real conversation.** `SessionsPanel.vue:53-56, 103-111` builds a proper
    `conversationUrl` and opens it in a new tab with `rel="noopener noreferrer"` — the one contextual bridge from this
    module into the conversation workspace. Keep it, and keep the status filter beside it (`:19-37, 81-83`).

14. **The palette is keyboard-reachable and drag-capable at once.** Each item is a real `<button draggable="true">`
    (`NodePalette.vue:35-46`): click places the node in view, drag drops it at the cursor. Two input modalities, one
    control, no duplication — and a new node arrives already selected with its settings open
    (`FlowBuilder.vue:219-227`).
