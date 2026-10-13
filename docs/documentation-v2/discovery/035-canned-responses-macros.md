---
agent: 035
scope: Canned responses and macros — creation, short codes, insertion, variables; macro action list, ordering, execution, visibility, failure behaviour, and the Lynomia macro-starter library
confidence: high
---

## 1. What the feature is

Two separate objects that the dashboard presents side by side and that the corpus correctly treats as distinct.

**A canned response** is a row with exactly three meaningful columns — `account_id`, `short_code`, `content`
(`app/models/canned_response.rb:1-32`). It is account-wide, has no owner, no visibility flag, no category and no
per-user variant. `short_code` is unique per account (`app/models/canned_response.rb:19`) and both `content` and
`short_code` are required (`:16-18`). There is no format validation on `short_code` and no minimum length on the
server. Insertion is entirely a client-side operation: the composer substitutes `{{variables}}` and strips
formatting the channel's schema cannot carry, then parses the Markdown into the editor
(`app/javascript/dashboard/helper/editorHelper.js:566-575`). Nothing about the insertion reaches the server as a
"canned response" — what is sent is an ordinary message.

**A macro** is a name, a `visibility` enum (`personal: 0, global: 1`) and an `actions` jsonb array
(`app/models/macro.rb:1-29`), plus `created_by`/`updated_by` and attached `files`. It has no conditions column, no
trigger, no schedule and no enable/disable switch. `actions` is an ordered flat list, and execution is a flat
`send` loop over it (`app/services/macros/execution_service.rb:10-21`). A macro runs because a person pressed it,
on the conversations whose display ids the caller named.

The product distinction the corpus article `macros-or-automation` is built on is exactly right and is visible in
the code: `ActionService` (`app/services/action_service.rb`) is the shared action vocabulary, and
`AutomationRules::ActionService` and `Macros::ExecutionService` are its only two subclasses, both dispatching
dynamically by `action_name` (`app/services/automation_rules/action_service.rb:14`,
`app/services/macros/execution_service.rb:14`). So "add a label", "assign a team", "change priority" and "resolve"
behave identically in both systems. The difference is only the entry point: `MacrosExecutionJob` is enqueued by a
controller action a user hit (`app/controllers/api/v1/accounts/macros_controller.rb:50-54`), while an automation
rule is fired by an event and gated by conditions. `Macro` has no conditions attribute at all, which is the
hard-coded version of "every action runs every time".

### The action list

`Macro::ACTIONS_ATTRS` admits **sixteen** action names (`app/models/macro.rb:33-35`); the builder's
`MACRO_ACTION_TYPES` offers **fifteen** (`app/javascript/dashboard/routes/dashboard/settings/macros/constants.js:1-77`).
The missing one is `change_status`. A macro carrying `change_status` is accepted by the API and executes
(`app/services/action_service.rb:29-31`), but `MacroEditor.vue:55-57` does a bare
`.find(item => item.key === action.action_name).inputType` with no guard, so opening such a macro in the editor
throws on an undefined lookup. `useMacroExecution.js:8-18` already compensates for the same gap on the run path.

Three methods defined in `ActionService` are deliberately *not* in `ACTIONS_ATTRS` and are therefore rejected by
`json_actions_format`: `open_conversation` (`action_service.rb:21-23`), `pending_conversation` (`:25-27`), and
automation's `send_email_to_team`. No macro action touches a custom attribute, and no commerce action exists —
`Macros::ExecutionService.include_mod_with('Macros::ExecutionService')` (`execution_service.rb:72`) resolves to
nothing, because this repository has no `enterprise/` tree and `custom/` defines no
`Custom::Macros::ExecutionService` (verified: the only `execution_service.rb` in the tree is
`app/services/macros/execution_service.rb`). The one commerce-aware action override is prepended onto the
sibling `AutomationRules::ActionService` (`custom/app/services/custom/automation_rules/action_service.rb:9`).

Four macro-only behaviours worth documenting:

| Behaviour | Evidence |
|---|---|
| `assign_agent` accepts the literal `'self'` and swaps it for the executing user | `app/services/macros/execution_service.rb:25-28`; offered as `{ id: 'self', name: 'Self' }` in `app/javascript/dashboard/composables/useMacros.js:41-45` |
| `send_message` / `add_private_note` are sent by the executing user, not a bot | `execution_service.rb:30-48` (`Messages::MessageBuilder.new(@user, ...)`) |
| `send_attachment` only ever sends blobs already attached to the macro | `execution_service.rb:50-64` |
| `send_webhook_event` posts `event: 'macro.executed'` with no signature or secret | `execution_service.rb:66-69` |

`mute_conversation` is not a mute. `Conversation#mute!` resolves the conversation **and** sets
`contact.blocked = true` (`app/models/concerns/conversation_mute_helpers.rb:4-10`). `snooze_conversation` calls
`snoozed!` with no `snoozed_until`, so the snooze is open-ended (`app/services/action_service.rb:13-15`;
`app/models/conversation.rb:86,286`).

Macro message and note bodies are literal strings on the record. Variables in them are resolved server-side at
send time, not by the macro runtime: `Liquidable`'s `before_create` renders the content with the contact, agent,
conversation, inbox and account drops (`app/models/concerns/liquidable.rb:5,12-44`), and
`ContactDrop#custom_attribute` / `ConversationDrop#custom_attribute` make custom attributes available too
(`app/drops/contact_drop.rb:30-33`, `app/drops/conversation_drop.rb:60-63`).

### The starter library Lynomia added

`app/javascript/dashboard/recipes/macroStarters.js` defines six starters, each a pure `build(values)` returning an
`actions` array, created through the ordinary `POST /macros` endpoint. The design record is
`docs/product-enablement/17-macro-starters.md`.

| id | Actions, in order | Requires | Citation |
|---|---|---|---|
| `escalate_conversation` | `change_priority` high, `assign_team`, `add_label`, `add_private_note` | a team, a label | `macroStarters.js:79-92` |
| `take_conversation` | `assign_agent` `['self']`, `change_priority` medium | nothing | `:97-108` |
| `resolve_with_reason` | `add_label`, `resolve_conversation` | a label | `:112-123` |
| `hand_to_team` | `assign_team`, `remove_assigned_agent`, `add_private_note` | a team | `:126-138` |
| `waiting_on_customer` | `add_label`, `snooze_conversation` | a label | `:141-152` |
| `store_issue_handoff` | `add_label`, `change_priority` high, `assign_team`, `add_private_note` | a team, a label | `:157-170` |

Three server constraints the catalogue encodes and documents in its own header comment
(`macroStarters.js:10-22`): `action_params` is always a flat array of scalars because the controller permits
`action_params: []` and silently drops a hash (`macros_controller.rb:61`); label actions take label **titles**,
not ids (`action_service.rb:37-41`); and only builder-known action types are used, so the created macro stays
editable. `send_attachment` is deliberately absent because its parameter is a signed ActiveStorage blob id.
Private-note text is written as literal bilingual copy rather than an i18n key, because `build` is pure
(`macroStarters.js:29-45`). The starters' titles and descriptions are i18n keys under `RECIPES.MACRO.*`
(`app/javascript/dashboard/i18n/locale/en/recipes.json`).

Requirements are evaluated from data the dashboard already holds: `REQUIREMENTS.TEAM` is
`teams.length > 0`, `REQUIREMENTS.LABEL` is `labels.length > 0`
(`app/javascript/dashboard/recipes/useRecipeContext.js:40-58`). Both stores are populated unconditionally by the
sidebar (`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:283-290`), so five of the six starters read
"requires setup" only on an account that genuinely has no team or no label.

## 2. Surfaces and routes

**Canned responses**

| Surface | Path / component | Citation |
|---|---|---|
| Settings list, search, count, add/edit/delete | `settings/canned-response/list`, name `canned_list` | `routes/dashboard/settings/canned/canned.routes.js:13-31`; `canned/Index.vue:143-262` |
| Create modal | `AddCanned.vue` | `canned/AddCanned.vue:84-143` |
| Edit modal | `EditCanned.vue` | `canned/EditCanned.vue:91-147` |
| "Add to canned responses" from a sent message | message context menu reuses `AddCanned` as a modal | `modules/conversations/components/MessageContextMenu.vue:178,248-256`; enabled only for an outgoing, non-deleted message with text (`components-next/message/Message.vue:415`) |
| Composer insertion, trigger `/` | `CannedResponse.vue` picker, anchored at the caret | `components/widgets/WootWriter/Editor.vue:358-363`; `components/widgets/conversation/CannedResponse.vue:1-130` |
| Variable picker, trigger `{{` | `VariableList.vue` over `MESSAGE_VARIABLES` | `Editor.vue:364-369`; `shared/constants/messages.js:101-153`; `components/widgets/conversation/VariableList.vue:4,36` |
| Typed-variable input rule (resolves on the closing braces) | `createVariableInputRule` | `helper/editorHelper.js:493-508` |
| API | `GET/POST/PATCH/DELETE /api/v1/accounts/:id/canned_responses` | `config/routes.rb:93`; `app/controllers/api/v1/accounts/canned_responses_controller.rb:1-45` |

The `/` and `{{` pickers are both disabled inside a private note
(`Editor.vue:256-263`, `:361,367` — `isAllowed: () => !props.isPrivate`), and both are disabled in the canned-response
editors themselves (`AddCanned.vue:115`, `EditCanned.vue:119` pass `:enable-canned-responses="false"` while keeping
`enable-variables`).

**Macros**

| Surface | Path / component | Citation |
|---|---|---|
| Settings list, search, sort, count, starter button, delete | `settings/macros`, name `macros_wrapper` | `settings/macros/macros.routes.js:16-29`; `settings/macros/Index.vue:159-278` |
| Full-page editor (create and edit) | `macros_new`, `macros_edit` | `macros.routes.js:30-59`; `MacroEditor.vue`, `MacroForm.vue`, `MacroNodes.vue`, `MacroNode.vue`, `MacroProperties.vue` |
| Starter gallery | `RecipeDialog` over `MACRO_STARTERS` | `settings/macros/Index.vue:15-16,269-277` |
| Conversation sidebar panel: run, preview, drag to reorder | `conversation/Macros/List.vue`, `MacroItem.vue`, `MacroPreview.vue` | `routes/dashboard/conversation/Macros/List.vue:56-105` |
| Composer, trigger `#`, with an action preview | `MacroList.vue` | `Editor.vue:375-380,984-991`; `components/widgets/conversation/MacroList.vue:56-94` |
| Command bar, "Execute a macro" | `useMacroHotKeys` | `composables/commands/useMacroHotKeys.js:42-68` |
| API | `GET/POST/SHOW/PATCH/DELETE /macros` + `POST /macros/:id/execute` | `config/routes.rb:97-99`; `app/controllers/api/v1/accounts/macros_controller.rb` |
| Execution | `MacrosExecutionJob` (queue `medium`) → `Macros::ExecutionService` | `app/jobs/macros_execution_job.rb:1-41`; `app/services/macros/execution_service.rb` |
| Audit trail | `name`, `visibility`, `created_by_id`, `updated_by_id` only — `actions` deliberately excluded | `custom/app/models/custom/audit/macro.rb:1-13` |

The sidebar order is per-agent and stored in UI settings under `macros_display_order`
(`composables/useOrderedMacros.js:5,32-36`); every surface that lists macros reads the same composable, so the
composer picker, the sidebar and the command bar agree. The settings list, by contrast, uses the store's own order,
which is the API's `order(:id)` (`app/models/macro.rb:46`).

The macros index is not paginated. `Macro.current_page` (`app/models/macro.rb:48-50`) is dead code — nothing reads
it.

## 3. User-visible states

**Canned responses.** Fetching (`CANNED_MGMT.LOADING`, three skeleton rows, `canned/Index.vue:178-180`); empty
account (`CANNED_MGMT.LIST.404`, `:146,185-190`); search with no match (`CANNED_MGMT.NO_RESULTS`, `:188`);
populated, sorted by short code, two columns with a five-line content clamp rendered as plain text
(`:200-209`); per-row delete spinner (`:228`). The `/` picker has its own loading, empty and preview states
(`CannedResponse.vue:118-130`), and its preview shows the content with variables already resolved and unsupported
formatting already stripped, so what is previewed is what gets inserted (`CannedResponse.vue:66-73`).

**Macros.** Fetching (`MACROS.LOADING`); empty, with the two offers — "Start from a starter" and "Add a new macro"
(`MACROS.LIST.404` + `MACROS.LIST.EMPTY_HINT`, `macros/Index.vue:204-229`); search with no match
(`MACROS.NO_RESULTS`); populated with five columns, two of which are hidden below `sm` (`:140-146`). A global macro
viewed by a non-administrator is a **read-only editor**: `isPublicMacroReadOnly` sets `inert` on the action canvas,
`readonly` on the name, `disabled` on both visibility tiles and the save button, and swaps the edit tooltip for
`MACROS.VIEW.TOOLTIP` (`MacroEditor.vue:40-42,117,146`; `MacroForm.vue:123`; `MacroProperties.vue:34-48,82,95,123,158`;
`MacrosTableRow.vue:40-46`). The delete button is hidden entirely for that case (`MacrosTableRow.vue:110`).

Execution states: per-macro spinner while the request is in flight (`executingMacroId`,
`useMacroExecution.js:34,45,59`; `MacroItem.vue:58-59`); a success toast; and, when the macro resolves the
conversation and required conversation attributes are missing, a modal asking for them first
(`useMacroExecution.js:63-80`; `conversation/Macros/List.vue:41-49,99-103`).

## 4. Errors and validation messages

| Message | Key / source | Where it comes from |
|---|---|---|
| "Short Code is required." | `CANNED_MGMT.ADD.FORM.SHORT_CODE.ERROR` | `i18n/locale/en/cannedMgmt.json:30` — client-side only; the label gets an `error` class, the string itself is never rendered by `AddCanned.vue` |
| "Message is required." | `CANNED_MGMT.ADD.FORM.CONTENT.ERROR` | `cannedMgmt.json:35`, same |
| "Could not connect to Woot server. Please try again." | `CANNED_MGMT.{ADD,EDIT,DELETE}.API.ERROR_MESSAGE` | `cannedMgmt.json:41,63,70` — the fallback when the server returns no message. **Leaks the upstream brand** ("Woot server") into a Lynomia install |
| "Canned response added/updated/deleted successfully." | `cannedMgmt.json:40,62,69` | `AddCanned.vue:69`, `EditCanned.vue:74`, `canned/Index.vue:121` |
| Server-side uniqueness / presence failure | none — `save!`/`update!` raise and the generic rescue formats `ActiveRecord::RecordInvalid` | `canned_responses_controller.rb:10,15`; the error body is what the frontend surfaces via `error?.message` |
| "Name is required for creating a macro" | `MACROS.ADD.FORM.NAME.ERROR` | `i18n/locale/en/macros.json:19`; `MacroProperties.vue:80` |
| "Action parameters are required" (and the other six) | `MACROS.ERRORS.*` | `macros.json:89-97`; produced by `validateActions` (`helper/validations.js:150-162`) and rendered per node (`MacroNode.vue:34-37`) |
| "At least one action is required" | `MACROS.ERRORS.ATLEAST_ONE_ACTION_REQUIRED` | `macros.json:96`; `validations.js:151-153`. Unreachable from the UI — the editor seeds one node and hides the delete button when only one remains (`MacroForm.vue:84-88`; `MacroNode.vue:54,82`) |
| "Something went wrong. Please try again" | `MACROS.ERROR` | `macros.json:12`; the only message for a failed save **and** for a failed execution (`MacroEditor.vue:131`; `useMacroExecution.js:57`) |
| "Macro executed. The conversation was not resolved because required attributes are missing." | `MACROS.EXECUTE.EXECUTED_WITHOUT_RESOLVING` | `macros.json:87`. **This statement is false in this build** — see §10 |
| "Macro execution actions X not supported." | not i18n'd, English literal | `app/models/macro.rb:74` — the server's own validation message, returned verbatim to the API client |
| "Invalid attachment" | `errors.attachments.invalid` | `config/locales/en.yml:104-105`; raised by `validate_and_prepare_attachments` when a signed blob id cannot be resolved (`app/controllers/concerns/attachment_concern.rb:12`) |
| "Created from the {name} starter (v{version})." / "Starter created" / error | `RECIPES.MACRO.PROVENANCE`, `RECIPES.CREATED`, `RECIPES.CREATE_ERROR` | `i18n/locale/en/recipes.json`; `macros/Index.vue:38,46` |

`MACROS.DESCRIPTION` (`macros.json:4`) advertises "updating a custom attribute" as a macro action. **No such
action exists** in `ACTIONS_ATTRS` or in `MACRO_ACTION_TYPES`. The settings page prints this string as its own
description (`macros/Index.vue:168`).

## 5. Failure paths

**Execution is fire-and-forget and silently lossy.** `POST /macros/:id/execute` enqueues the job and returns
`head :ok` without touching a conversation (`macros_controller.rb:50-54`). The job then drops work quietly: a
blank conversation set returns with no log at all (`macros_execution_job.rb:9`); a missing account membership or a
conversation the user cannot `show?` is logged as a JSON `macro_execution_skipped` line and skipped
(`:11-23,30-40`). And inside the service, **every** action error is rescued per action and sent to
`ChatwootExceptionTracker`, after which the loop continues
(`app/services/macros/execution_service.rb:13-18`). So a macro whose team assignment, label or message all failed
still produces "Macro executed successfully" in the agent's toast. The agent has no run history, no partial-failure
indicator and no retry: the only trace is a Sentry event they cannot see.

**Several actions fail silently by design, not by exception.** `assign_agent` returns without assigning if the
agent is not a member of the conversation's inbox and not an administrator
(`action_service.rb:43-55,104-109`), or if the user is unconfirmed (`:50`). `assign_team` returns without
assigning if the team does not belong to the account (`:64-74,111-113`). `add_label` with an empty list returns
(`:37-39`). `send_email_transcript` returns if the account has email transcripts disabled, and stops mid-list when
the account's email rate limit is reached (`:84-96`). None of these produce an error for the executing agent.

**`send_message`, `add_private_note` and `send_attachment` are skipped entirely on a tweet conversation**
(`execution_service.rb:31,41,51` → `action_service.rb:115-119`) — dead weight on this installation, which has no
Twitter channel, but it means a macro's message action has one more silent exit than the UI suggests.

**Attachment handling is not transactional on create.** The controller saves the macro and then attaches blobs in
a separate, unguarded loop (`macros_controller.rb:25-26`), so a failed attach leaves a macro whose
`send_attachment` action references a blob it does not hold; the action then no-ops
(`execution_service.rb:53-57`). On update, the `rescue StandardError` sits **inside** the
`ActiveRecord::Base.transaction` block (`macros_controller.rb:33-42`), so the error is swallowed and the
transaction commits whatever was already applied before it, while the response reports failure.

**Canned responses have no server-side guard rails on the short code.** Minimum length 2 is client-side only
(`AddCanned.vue:42-45`, `EditCanned.vue:36-44`); the model validates presence and uniqueness only
(`canned_response.rb:16-19`). The API will accept a one-character short code, or one containing spaces, which the
`/` trigger then cannot be typed to reach — only found by searching the picker.

**The settings list is stale-tolerant but not error-tolerant.** `getCannedResponse` failures are swallowed into
an empty catch (`canned/Index.vue:76-80`), as are `macros/get` and `macros/getSingleMacro` failures
(`store/modules/macros.js:36-38,47-49`). A network failure on either list therefore looks exactly like an empty
account.

## 6. Permissions

| Surface | Gate | Citation |
|---|---|---|
| Settings → Canned responses | feature `canned_responses` (default on) + route permissions `agent`, `administrator`, or any of the three conversation custom-role permissions | `canned.routes.js:25-28`; `featureFlags.js:12`; `config/features.yml:75-78`; `constants/permissions.js:14-20` |
| Canned response create / update / destroy (API) | **nothing beyond account membership** — `canned_responses_controller.rb` makes no `authorize` call and there is no `CannedResponsePolicy` in the tree | `app/controllers/api/v1/accounts/canned_responses_controller.rb:1-45` |
| Settings → Macros | feature `macros` (default on) + the same route permission set | `macros.routes.js:23-26,43-46,53-56`; `featureFlags.js:21`; `config/features.yml:51-53` |
| Macro index / create | unconditional for any account member | `app/policies/macro_policy.rb:2-8` |
| Macro show / execute | global macro, or its author | `macro_policy.rb:10-12,26-28` |
| Macro update / destroy | administrator if global; otherwise author only | `macro_policy.rb:14-24` |
| Macro visibility | an agent's requested `global` is **overwritten**, not rejected | `app/models/macro.rb:37-40` |
| Composer `#` macro trigger | account feature flag `macros` only | `ReplyBox.vue:194-199,1397`; `Editor.vue:267,378` |

Two things worth stating plainly in documentation. First, `MacroPolicy` checks
`@account_user.administrator?`, so a **custom role holder is not an administrator** and cannot edit or delete a
public macro however broad their conversation permissions are; the frontend agrees
(`composables/useAdmin.js:11-12` reads `getCurrentRole === 'administrator'`). Second,
`Macro#set_visibility` overwrites silently: an agent who posts `visibility: 'global'` gets a `200` and a personal
macro, with no `422` and no warning. The macro starter page compensates by sending `global` only for an
administrator (`macros/Index.vue:38`).

Unlike macros, **canned responses have no authorization layer whatsoever** — any member who can reach the route
can edit or delete any canned response in the account. The composer `/` trigger is not feature-flagged either; it
is gated only by `enableCannedResponses` and the private-note check (`Editor.vue:260-263`).

## 7. Contextual-help opportunities

`DOC_ARTICLES` already holds all three keys: `cannedResponses`, `macros`, `macrosOrAutomation`
(`app/javascript/dashboard/helper/documentationLinks.js:22-24`), and `FEATURE_DOC_KEYS` maps the two feature names
onto the first two (`app/javascript/dashboard/helper/featureHelper.js:13,23`), so both settings pages' "Learn more"
links resolve on a branded install. The gaps are at the moment of use, not at the moment of configuration.

| UI location | The question a user has there | Registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `settings/canned/Index.vue:153` (header `LEARN_MORE`) | what a canned response is for | `cannedResponses` | yes, and wired via `feature-name="canned_responses"` |
| `settings/macros/Index.vue:169` (header `LEARN_MORE`) | what a macro is | `macros` | yes, wired via `feature-name="macros"` |
| **`settings/macros/Index.vue:204-229` (empty state)** | "should this be a macro or an automation rule?" — the first decision a user faces, at the only moment they have nothing to lose | `macrosOrAutomation` | **key exists but nothing in the product links to it** (grep for `macrosOrAutomation` returns only its own definition) |
| **`settings/macros/Index.vue:269-277` (starter gallery)** | "what do these six actually do, and can I change them after?" | `macros` | no link in the dialog |
| **`MacroProperties.vue:86-151` (visibility tiles)** | "what is the difference between Private and Public, and why is Public greyed out for me?" | `macros` | no link; only the three one-line descriptions at `macros.json:73-79` |
| **`AddCanned.vue:104-119` (content editor)** | "what variables can I use, and what happens if one is empty?" | `cannedResponses` | no link; the variable picker is the only affordance |
| **`MessageContextMenu.vue:248-256` ("Add to canned responses")** | "where does this go, and who else will see it?" | `cannedResponses` | no link |
| **`conversation/Macros/List.vue:58-71` (sidebar empty state)** | "why are there no macros, and can I make one?" | `macros` | links to the settings page, not to help |
| **`ConversationResolveAttributesModal` via `useMacroExecution.js:78-79`** | "why is this macro asking me for attributes?" | `macros` or an attributes article | no link |

## 8. Current documentation coverage

Three EN articles plus three AR counterparts, all in `conversations`:

| Article | EN | AR | EN words / AR words |
|---|---|---|---|
| Canned responses | `custom/db/documentation/en/conversations/canned-responses.md` (119 lines) | `custom/db/documentation/ar/conversations/canned-responses.md` (111 lines) | 964 / 775 |
| Macros | `custom/db/documentation/en/conversations/macros.md` (126 lines) | `custom/db/documentation/ar/conversations/macros.md` (117 lines) | ~1050 / ~850 |
| Macros or automation? | `custom/db/documentation/en/conversations/macros-or-automation.md` (130 lines) | `.../ar/conversations/macros-or-automation.md` (125 lines) | ~1100 / ~900 |

This is the strongest area of the corpus I have seen. The coverage is genuinely good and unusually honest:

- `canned-responses.md:17-24` opens with "when not to use one", correctly separating a canned response from a
  WhatsApp template and from a macro.
- `canned-responses.md:46-56` lists the variable table accurately against
  `shared/constants/messages.js:101-153`, including `inbox.*`, and correctly adds the custom-attribute forms that
  `getMessageVariables` produces (`@chatwoot/utils` `canned.ts:73-85`).
- `canned-responses.md:60-67` states three real behaviours: `{{agent.*}}` is the sender not the assignee (true —
  `ReplyBox.vue:465-478` overrides the upstream helper, which uses the assignee, with
  `getAgentVariables(currentUser)`); names are Ruby-capitalized per word (true —
  `editorHelper.js:470-481`, `contact_drop.rb:3,22-28`); an empty variable disappears with no warning (true —
  Liquid renders a missing drop value as an empty string).
- `canned-responses.md:69-73` is right that resolution and format-stripping both happen at insert time, in the
  composer (`editorHelper.js:566-575`; `CannedResponse.vue:66-73`).
- `canned-responses.md:93-99` correctly states that canned responses are account-wide with no private option,
  that both the `/` and `{{` pickers are off in a private note (`Editor.vue:361,367`), and that a canned response
  carries no attachment.
- `macros.md:29-37` groups the fifteen builder actions correctly; `:41-45` calls out `Self` and the untimed
  snooze, both verified; `:101-102` calls out that mute resolves **and** blocks, which is correct and is the
  single most surprising behaviour in the feature.
- `macros.md:77-87` gets the permission matrix right, including that an agent's "Public" choice is overridden on
  the server and that the sidebar order is per-agent.
- `macros-or-automation.md` is accurate on the one thing that matters: `:14` "A macro waits for a person. An
  automation rule waits for an event." Its action-exclusivity claims at `:75-79` check out — `send_email_to_team`,
  `open_conversation` and `pending_conversation` are absent from `ACTIONS_ATTRS` (`macro.rb:33-35`), and `Self` has
  no automation equivalent (`execution_service.rb:25-28`).

## 9. Missing or stale documentation

1. **"Add to canned responses" from a message is undocumented.** `canned-responses.md:30-36` describes only
   Settings → Add. The context-menu route (`MessageContextMenu.vue:248-256`) is how most agents will actually
   create one, and it carries its own rules: outgoing messages only, with text, not deleted
   (`components-next/message/Message.vue:415`). Nothing in the corpus mentions it.
2. **Short-code rules are not stated.** The article says "keep it short and guessable" but not that there is no
   server-side length or character validation, that a short code with a space cannot be typed after `/`, or that
   two-character minimum is a browser-only rule.
3. **The starter gallery is barely documented.** `macros.md:49-50` mentions "the starter gallery" in one clause.
   Six named starters exist, five of them need a team or a label to exist first, and the gallery says "requires
   setup" when they do not (`useRecipeContext.js:54-55`). A user who opens the gallery on a fresh account and sees
   five greyed-out cards has no article to read.
4. **No article covers the macro editor itself** — drag to reorder, the single-node floor, what "Start Flow" /
   "End Flow" mean on a thing that is not a flow (`MacroNodes.vue:53,105`), or that the action canvas goes inert
   for a public macro you cannot edit.
5. **`change_status` is a trap with no documentation.** A macro created through the API with `change_status`
   executes but cannot be opened in the editor (`MacroEditor.vue:55-57` throws). Nothing warns an API user.
6. **There is no documentation of what happens to a macro when its referent disappears** — a deleted label, a
   deleted team, an agent removed from the inbox. All three are silent no-ops
   (`action_service.rb:43-55,64-74`), and the corpus's troubleshooting entry (`macros.md:121-123`) gets close but
   frames it as a guess rather than as the documented behaviour.
7. **No API documentation for macros.** Canned responses have a full swagger path set
   (`swagger/paths/application/canned_responses/{index,create,update,delete}.yml`) and a resource definition;
   macros have none. The `action_params`-must-be-flat-scalars rule, which the starter catalogue had to discover and
   document in a source comment (`macroStarters.js:10-14`), is written down nowhere a developer would look.
8. **`MACROS.DESCRIPTION` is wrong in the product** (`i18n/locale/en/macros.json:4`, rendered at
   `macros/Index.vue:168`): it advertises "updating a custom attribute", an action macros do not have. Fixing the
   string is a product change, not a documentation change, but any article that quotes the page will inherit the
   error.

## 10. Doc claims not proven by code

**Blocker — the required-attributes claim is false.** `macros.md:103-105` says: "If a macro resolves the
conversation and your account requires certain conversation attributes before resolving, you are asked for them.
Dismissing that prompt still runs the macro, but leaves the conversation unresolved." The first sentence is true
and is client-side (`useMacroExecution.js:63-80`). The second is **not true in this repository**. `grep -rn
"conversation_required_attributes" app enterprise custom lib --include=*.rb` returns exactly one hit — the
account-settings JSON schema (`app/models/concerns/account_settings_schema.rb:19`). There is no server-side gate
anywhere: `resolve_conversation` calls `@conversation.resolved!` unconditionally
(`app/services/action_service.rb:17-19`), and the one historical gate,
`Enterprise::Macros::ExecutionService`, does not exist here — this repository has no `enterprise/` tree, and
`include_mod_with` resolves a missing extension module to a silent no-op
(`config/initializers/01_inject_enterprise_edition_module.rb:40-48,78-86`). So dismissing the modal
(`useMacroExecution.js:104-109`) runs the macro and the conversation **is** resolved, while the agent is told
"The conversation was not resolved because required attributes are missing"
(`i18n/locale/en/macros.json:87`). The source comment at `useMacroExecution.js:102-103` asserts the same false
thing, which is almost certainly where the article's claim came from. Both the article and the toast need
correcting, and the orchestrator should decide whether this is a documentation fix or a product bug to be filed.

**Major — the starter gallery does not open the editor on the result.** `docs/product-enablement/17-macro-starters.md:§5`
and the comment at `settings/macros/Index.vue:29-31` both state that after creating from a starter "the page opens
the editor on the result, because a starter is a starting point." The page reads
`const created = await store.dispatch('macros/create', ...)` and redirects only `if (created?.id)`
(`macros/Index.vue:35,42-44`). The Vuex action has **no return statement**
(`store/modules/macros.js:53-63`) — it commits `ADD_MACRO` and resolves to `undefined`. So the redirect never
fires: the dialog closes, the toast appears, the macro lands in the list, and the user is left on the index. The
store spec asserts only the commits (`store/modules/specs/macros/actions.spec.js:51-60`), so nothing catches it.
A documentation article describing the starter flow must not promise the editor opens.

**Minor — "They are switched off inside a private note, along with variables" (`canned-responses.md:95-96`) is
true for the two pickers but not for variable *resolution*.** The `/` and `{{` pickers are both gated on
`!isPrivate` (`Editor.vue:361,367`), and the typed-variable input rule also bails on a private note
(`editorHelper.js:495`). But a macro's `add_private_note` content still goes through `Liquidable`, whose
`liquid_processable_message?` tests only `message_type` (`app/models/concerns/liquidable.rb:22-24`), not `private`.
So variables typed into a macro's private-note action *do* resolve server-side. The article's statement is about
the composer and is correct there; an article about macro notes would get this wrong if it generalised.

**Minor — "Type `{{` in the composer to pick from the list" (`canned-responses.md:43-44`) is accurate, but the
custom-attribute variables the article lists two paragraphs later are not in that list.** `VariableList.vue:4,36`
renders `MESSAGE_VARIABLES` only — the fourteen standard keys (`shared/constants/messages.js:101-153`). Custom
attributes resolve (`@chatwoot/utils` `canned.ts:73-85`; `contact_drop.rb:30-33`) but must be typed by hand. The
article should say so, because "pick from the list instead of typing the name"
(`canned-responses.md:112-113`) is advice that cannot be followed for custom attributes.

**Not checked.** Whether a macro's `send_message` on a WhatsApp conversation outside the 24-hour window fails in
the way `macros.md:98-100` describes — that is agent 040's surface, and I did not trace the channel send path.
Whether `conversation_required_attributes` is enforced on `toggle_status` by some path outside the Ruby tree
(it is not enforced in the Ruby tree). The Arabic articles' semantic fidelity: I compared structure and length
only, not meaning — that is agents 061 and 094.
