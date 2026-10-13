---
agent: 029
scope: Conversation and inbox lifecycle — creation, assignment, status transitions, the conversation list and its filters/folders/sorting, bulk actions, the conversation sidebar
confidence: high
---

## 1. What the feature is

A **conversation** is one thread between one contact and one inbox (channel) inside one account. It carries
exactly one `status` from a four-value enum — `open`, `resolved`, `pending`, `snoozed`
(`app/models/conversation.rb:86`) — one optional human `assignee`, one optional polymorphic `ai_assignee`
(agent bot or Captain assistant, `app/models/conversation.rb:117-121`), one optional `team`, an optional
`priority` from a five-value set (`none/low/medium/high/urgent`, `app/models/conversation.rb:87`), labels,
custom attributes, and a per-account human-facing number `display_id` assigned by a database trigger
(`app/models/conversation.rb:429-431`, read back at `:368-375`).

The **inbox** in the product's day-to-day sense is the conversation *list*: one Vue component
(`ConversationView.vue`) rendering a list panel, a message panel and a sidebar, reached through fifteen routes
that all mount the same component with different props (`conversation.routes.js:45-236`). The list is narrowed
by three independent stacked controls — assignee tab, status, sort order — plus optional advanced filters or a
saved folder, and by five route-level scopes (inbox, label, team, mentions, participating, unattended).

Lifecycle, as the code actually implements it:

| Transition | Where it is decided | Notes |
|---|---|---|
| created `resolved` | `conversation.rb:308` | contact is blocked → the conversation is created already resolved |
| created `pending` | `conversation.rb:312,319-325` | inbox has an active bot; the bot becomes `ai_assignee` |
| created `open` | default column value, `conversation.rb:18` | everything else |
| open → resolved | `toggle_status` endpoint, or `Conversation#toggle_status` (`:171-176`) | also clears `waiting_since` via `update_column` (`:276-283`) |
| any → snoozed | `toggle_status` with `snoozed_until` (`conversations_controller.rb:175-178`) | `snoozed_until` nil means "until next reply" |
| snoozed → open (timed) | `Conversations::ReopenSnoozedConversationsJob:5`, every 5 min (`config/schedule.yml:12-15`) | only `snoozed_until` within `3.days.ago..Time.current` |
| snoozed/resolved → open on reply | `app/models/message.rb:404-411` | skipped entirely when the contact is blocked |
| resolved → pending on reply | `app/models/message.rb:425-435` | when the inbox has an active bot |
| pending → open (bot handoff) | `conversation.rb:183-188`, `conversations_controller.rb:95-99` | only when `Current.user` is an `AgentBot` |
| open → resolved automatically | `Conversations::ResolutionJob:11-21` | account-level `auto_resolve_after` minutes |
| snoozed → nil `snoozed_until` | `conversation.rb:285-287` | any save that leaves the status not-snoozed clears the timer |

## 2. Surfaces and routes

| Surface | Frontend | API | Controller |
|---|---|---|---|
| Conversation list + panels | `conversation.routes.js:45-236` → `ConversationView.vue:160-204` | `GET conversations` | `conversations_controller.rb:12-16` |
| Counts only (tab badges) | `conversationStats` store | `GET conversations/meta` | `:18-21` |
| List panel, filters, folders, bulk bar | `ChatList.vue` (1048 lines) | — | — |
| List header: title, count chip, status chip | `ChatListHeader.vue:82-216` | — | — |
| Status + sort dropdown | `ConversationBasicFilter.vue:30-94` | — | — |
| Assignee tabs Mine/Unassigned/All | `ChatList.vue:967-972`, `ChatTypeTabs.vue` | — | `conversation_finder.rb:109-119` |
| Advanced filters | `next/filter/ConversationFilter.vue` via `ChatList.vue:1030-1042` | `POST conversations/filter` | `:51-60` → `Conversations::FilterService` |
| Folders (saved filters) | `SaveCustomView.vue`, `DeleteCustomViews.vue`; guards at `conversation.routes.js:14-43` | `/custom_filters` | `custom_filters_controller.rb:11-25` |
| Conversation search in list | `GET conversations/search` | `:23-27` | same finder with `params[:q]` (`conversation_finder.rb:135-143`) |
| Status change (open/resolve/pending) | `ResolveAction.vue:178-228` | `POST conversations/:id/toggle_status` | `:82-93` |
| Snooze | `ResolveAction.vue:235-246` → `CmdBarConversationSnooze.vue:31-42`, `CustomSnoozeModal.vue` | same endpoint with `snoozed_until` | `:175-178` |
| Priority | `ConversationAction.vue:36-61`; context menu `ChatList.vue:709-726` | `POST conversations/:id/toggle_priority` | `:101-104`, `:141-146` |
| Assignment (agent/team) | `ConversationAction.vue`, `ReplyBoxBanner.vue:28-44` | `POST conversations/:id/assignments` | `assignments_controller.rb:3-47` |
| Read / unread | opening a conversation; context menu | `POST .../update_last_seen`, `POST .../unread` | `:112-131` |
| Mute (labelled "Block Contact") / transcript | `MoreActions.vue:28-70` | `POST .../mute`, `/unmute`, `/transcript` | `:62-80` |
| Delete | `ChatList.vue:858-876`; context menu `contextMenu/Index.vue:440` | `DELETE conversations/:id` | `:133-137` |
| Bulk actions bar | `conversationBulkActions/Index.vue`, `useBulkActions.js` | `POST bulk_actions` | `bulk_actions_controller.rb:12-24` → `BulkActionsJob` |
| Sidebar | `ConversationSidebar.vue:42-70` → `ContactPanel.vue:137-320`; default panel order `useUISettings.js:5-17` | per-panel | — |
| Context menu (right-click a card) | `contextMenu/Index.vue:92-160, 300-441` | the endpoints above | — |

Server routes are declared at `config/routes.rb:111-145`.

## 3. User-visible states

**Conversation list.** Loading (`CHAT_LIST.LOADING`), loaded, loading-more, and "all loaded"
(`ChatList.vue:359-365`, `CHAT_LIST.EOF`). Four *distinct* empty states, chosen by
`conversationListEmptyStateKey` (`widgets/conversation/helpers/emptyStateHelper.js:17-28`) and rendered at
`ChatList.vue:974-994`:

| key | when | has a way out? |
|---|---|---|
| `FOLDER` | a folder is active | no action offered |
| `FILTERED` | advanced filters applied | "Clear filters" → `resetAndFetchData` |
| `STATUS_FILTERED` | status filter is anything but `all` | "Show all conversations" |
| `NO_CONVERSATIONS` | nothing applies | none — correct |

This is a deliberate Lynomia correction: the helper's own comment (`emptyStateHelper.js:13-16`) records that the
always-on default `open` filter is "how a queue of resolved conversations stays invisible to an agent who has
never opened the filter panel", and `ChatListHeader.vue:113-137` makes the status chip itself open the panel that
changes it.

**Conversation card** (`ConversationCard.vue`): unread badge (capped — see below), priority icon, assignee
(only when filters/folders are active or the All tab is selected, `ChatList.vue:193-198`), inbox name when the
account has more than one inbox, labels, SLA label, voice-call status row, bulk-select checkbox. **The card
shows no status indicator at all** — grep for `status` in `ConversationCard.vue` returns only contact
availability and voice-call status. Snoozed, pending and resolved cards are visually identical to open ones.

**Unread count is capped at 10 server-side.** `json.unread_count conversation.unread_incoming_messages.count`
(`_conversation.json.jbuilder:68`) and `unread_incoming_messages` is `unread_messages…incoming.last(10)`
(`conversation.rb:202-204`), so the number can never exceed 10; the badge then renders `9+` above 9
(`UnreadBadge.vue:12-14`). The `unread` sort order is *not* capped — it uses a real SQL `COUNT`
(`conversation.rb:234-252`), so sorting and the badge disagree past ten.

**Conversation panel.** No conversation selected → `EmptyState.vue:86-98` chooses between four messages:
loading, `NO_INBOX_AGENT` ("not part of any inbox"), `NO_MESSAGE_1`, or `conversationMissingMessage`, which is
`CONVERSATION.404` on the expanded layout and `SELECT_A_CONVERSATION` on the condensed one
(`EmptyState.vue:43-48`).

**Conversation header** (`ConversationHeader.vue:146-164`): `#<display_id>` as a copy button, inbox name,
unverified-session warning for web widget, and `Snoozed until <time>` / `Snoozed until next reply` — the only
place a status is spelled out. SLA label and the Resolve/Reopen/Open button group
(`ResolveAction.vue:178-228`), whose shape depends on status: Resolve + dropdown when open, Reopen + dropdown
when resolved, bare Open when pending or snoozed (`ResolveAction.vue:51-57`) — so **a snoozed or pending
conversation offers no snooze and no "mark pending"**.

**Reply box banners** (`ReplyBoxBanner.vue:53-69`): "This conversation is not assigned to you…" with an
*Assign to me* button, shown only once the agent starts typing a non-private message; and the bot-handoff
banner for a pending, bot-assigned conversation.

**Degraded reply state.** `can_reply` is computed per conversation from the channel's messaging window
(`_conversation.json.jbuilder:50`, `Conversations::MessageWindowService:9-13`); when false the composer refuses
free text and `CONVERSATION.CANNOT_REPLY` ("You cannot reply due to") is shown. WhatsApp is a fixed 24 hours.

**Bulk bar.** Appears when any card is selected; "N selected"; the status dropdown hides the action a selection
is already in (`ChatList.vue:999-1001` → `conversationBulkActions/Index.vue:189-191`, consumed at
`BulkUpdateActions.vue:32-63`). `BULK_ACTION.ALL_CONVERSATIONS_SELECTED_ALERT` tells the user that only the
visible page was selected.

## 4. Errors and validation messages

| String (EN) | i18n key | Shown from |
|---|---|---|
| "Couldn't load conversations. Please try again." | `CHAT_LIST.FETCH_ERROR` | `ChatList.vue:405,422,431` (filter/folder fetches only) |
| "Conversation status changed" | `CONVERSATION.CHANGE_STATUS` | `ChatList.vue:782`, `ResolveAction.vue:99`, `CmdBarConversationSnooze.vue:28` |
| "Conversation status change failed" | `CONVERSATION.CHANGE_STATUS_FAILED` | **nowhere** — dead string, see §5 |
| "Changed priority of conversation id {id} to {priority}" | `CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL` | `ChatList.vue:720-724` |
| "Couldn't change priority. Please try again." | `…CHANGE_PRIORITY.FAILED` | declared; the dispatch has no `.catch` (`ChatList.vue:714`) |
| "Conversation id {id} assigned to \"{agent}\"" / "Couldn't assign agent…" | `CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.{SUCCESFUL,FAILED}` | `useBulkActions.js:71-82` |
| "Couldn't assign team…" | `CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED` | `ChatList.vue:761` |
| "Conversation deleted successfully" / "Couldn't delete conversation! Try again" | `CONVERSATION.{SUCCESS,FAIL}_DELETE_CONVERSATION` | `ChatList.vue:867,869` |
| "Conversation status updated successfully." / "Failed to update conversations…" | `BULK_ACTION.UPDATE.UPDATE_{SUCCESFUL,FAILED}` | `useBulkActions.js:212,215` |
| "Cannot resolve conversations due to missing required attributes" | `BULK_ACTION.RESOLVE.ALL_MISSING_ATTRIBUTES` | `useBulkActions.js:190` |
| "Some conversations need required attributes before resolving and were skipped" | `BULK_ACTION.RESOLVE.PARTIAL_SUCCESS` | `useBulkActions.js:210` |
| "Conversations visible on this page are only selected." | `BULK_ACTION.ALL_CONVERSATIONS_SELECTED_ALERT` | bulk bar |
| "Sorry, we cannot find the conversation. Please try again" | `CONVERSATION.404` | `EmptyState.vue:47` (expanded layout only) |
| "This contact is blocked successfully. You will not be notified of any future conversations." | `CONTACT_PANEL.MUTED_SUCCESS` | mute action |

Server-side. The conversation model validates only presence of `account_id`, `inbox_id`, `contact_id`, jsonb
attribute length and `uuid` uniqueness (`conversation.rb:76-84`) — **no status machine, no guard on any
transition** (the code says so: `# FIXME: implement state machine with aasm`, `:172`). `toggle_priority`
rejects an unknown priority with `ActionController::ParameterMissing` (`conversations_controller.rb:143`).
`create` returns `422 {"error":"source_id should be unique"}` on a contact-inbox race (`:215-217`). Transcript
returns `422 {"error":"email param missing"}`, `402` off-plan, `429` over the mail rate limit (`:72-80`).
Filter errors come from `CustomExceptions::CustomFilter` and render via `render_could_not_create_error`
(`:55-59`); their strings are at `config/locales/en.yml:271-274`, e.g. `invalid_attribute`:
"Invalid attribute key - [%{key}]. The key should be one of [%{allowed_keys}]…". Folder limit:
"Limit reached. The maximum number of allowed custom filters for a user per account is 1000."
(`en.yml:268`, `lib/limits.rb:11`). Unread-counts endpoint returns `403` with
`errors.conversations.unread_counts.feature_not_enabled` when the flag is off
(`unread_counts_controller.rb:27-31`).

## 5. Failure paths

**A failed status change reports success.** `toggleStatus` catches and discards every error
(`store/modules/conversations/actions.js:387-389`), so the promise resolves; both call sites then show the
success alert unconditionally (`ResolveAction.vue:98-101`, `ChatList.vue:781-783`). The UI stops its spinner,
says "Conversation status changed", and the status does not change. `CONVERSATION.CHANGE_STATUS_FAILED` exists
in `en.json` and is referenced by nothing. Same swallow in `assignAgent` (`actions.js:325-327`), `assignTeam`
(`:344-346`) and `getConversation` (`:82-84`).

**A deep link to a conversation the agent may not see fails silently.** `ConversationView.fetchConversationIfUnavailable`
dispatches `getConversation` (`ConversationView.vue:118-126`), which swallows the 404/403. The panel then falls
through `EmptyState.vue:86-98`: on the condensed layout the agent is told "Please select a conversation from
left pane", and if their list happens to be empty they get "Uh oh! Looks like there are no messages from
customers in your inbox" — neither says the conversation does not exist or is not theirs.

**A conversation assigned to your team but in an inbox you are not a member of is reachable by URL and
invisible in every list.** The list narrows by inbox membership only (`permission_filter_service.rb:22`); the
record policy allows inbox **or** team (`conversation_policy.rb:16-18, 28-35`). The Lynomia overlay records this
asymmetry as deliberate and deliberately unchanged (`custom/app/policies/custom/conversation_policy.rb:12-15`).
The team route is the same narrowed relation plus `where(team:)` (`conversation_finder.rb:151-155`), so
`/team/:teamId` returns nothing for such an agent.

**Reopening someone else's conversation silently takes it over.** `toggle_status` calls `handle_human_open`
whenever the result is open and the actor is a `User` (`conversations_controller.rb:92`), and that method sets
`@conversation.assignee = Current.user if Current.user.agent?` with no check that the conversation was already
assigned (`:180-186`; `agent?` is the account membership role, `user_attribute_helpers.rb:38-40`). Any agent
pressing Reopen or Open on a colleague's conversation becomes its assignee. The response payload does not
include the assignee (`toggle_status.json.jbuilder:4-9`), so the browser only learns about it from the
`conversation.updated` websocket event.

**Required conversation attributes are enforced only in the browser.** The whole rule lives in
`useConversationRequiredAttributes.js:13-91` and its two call sites (`ResolveAction.vue:120-139`,
`useBulkActions.js:166-193`). A repo-wide grep for `conversation_required_attributes` in `app` and `custom`
finds it only in the settings schema (`app/models/concerns/account_settings_schema.rb:19`). The API, an
automation rule, a macro, and `Conversations::ResolutionJob` all resolve conversations without it.

**Conversation bulk actions are fire-and-forget and report success on enqueue.** The controller enqueues and
answers `head :ok` (`bulk_actions_controller.rb:32-38`); the job then calls `conversation.update(params)` —
no bang, return value discarded (`bulk_actions_job.rb:25-32`). The success alert fires at
`useBulkActions.js:212`. Contacts have a completion broadcast to wait on
(`helper/bulkActionCompletion.js:13-25`); conversations have none, so a bulk action that silently updates zero
rows is indistinguishable from one that worked.

**Snooze has a three-day recovery window.** `ReopenSnoozedConversationsJob` selects only
`snoozed_until: 3.days.ago..Time.current` (`reopen_snoozed_conversations_job.rb:5`) and runs from a 5-minute
cron (`config/schedule.yml:12-15`). If sidekiq-cron does not run for longer than three days, every conversation
whose snooze expired in that outage stays snoozed permanently with no operator signal.

**Re-snoozing a timed snooze "until next reply" keeps the old timer.** The client sends
`snoozed_until: null` (`api/inbox/conversation.js:58-62`); both writers guard on truthiness —
`conversations_controller.rb:177` and `bulk_actions_job.rb:51` — so the previously stored time survives and the
conversation reopens on it anyway. Not reachable from the header (no snooze control while snoozed,
`ResolveAction.vue:51-53`) or the card menu (`contextMenu/Index.vue:221-224`), but reachable from a mixed bulk
selection, where the snooze action is shown whenever not every selected conversation is already snoozed
(`conversationBulkActions/Index.vue:191`).

**Unblocking does not bring the conversation back.** `mute!` resolves the conversation *and* blocks the
contact; `unmute!` only clears `blocked` (`conversation_mute_helpers.rb:4-17`). The conversation stays resolved,
and while the contact is blocked, replies do not reopen it at all (`message.rb:405`) and new conversations are
created already resolved (`conversation.rb:308`).

**Auto-assignment can find nobody and say nothing.** Only agents whose Redis availability is `online` are
candidates (`auto_assignment/agent_assignment_service.rb:61-71`); the legacy path runs on save
(`auto_assignment_handler.rb:15-39`), and the periodic sweep exists only for accounts with the `assignment_v2`
feature **and** inboxes that have an assignment policy (`periodic_assignment_job.rb:4-18`). A conversation that
arrives when everyone is offline waits for the next status event on that inbox, with no indication anywhere that
assignment was attempted.

## 6. Permissions

| Surface | Gate | Evidence |
|---|---|---|
| Every conversation route | `administrator`, `agent`, or one of the three `conversation_*` capabilities | `conversation.routes.js:6-12` |
| The list relation (list, meta, filter, search, contact conversations, attachments, activity timeline, bulk, folder counts) | inbox membership; administrator short-circuits | `permission_filter_service.rb:11-23` |
| …then narrowed by capability | `conversation_manage` → all; `conversation_unassigned_manage` → unassigned + own; `conversation_participating_manage` → own; none, if enforced → nothing | `custom/.../permission_filter_service.rb:20-22` → `Conversations::CapabilityScope:39-137` |
| One conversation by id, and everything hanging off it (messages, attachments, labels, participants, assignments, drafts, transcript, macros) | `administrator? \|\| agent_bot? \|\| (inbox \|\| team)`, then the same capability scope | `conversation_policy.rb:10-12`; `custom/app/policies/custom/conversation_policy.rb:40-42` |
| Inbox-or-team ceiling, as a relation | one implementation shared with the notification feed | `custom/app/services/conversations/access_ceiling.rb:36-39` |
| Search and message-body search | capability-narrowed separately, because `SearchService` never calls the filter service | `custom/app/services/custom/search_service.rb:16-39` |
| Unread counts | same capability modes, plus feature flag | `custom/.../unread_counts/counter.rb:25-28`; `unread_counts_controller.rb:27-31` |
| Assignee tabs | `unassigned` tab needs `conversation_manage` or `conversation_unassigned_manage`; `all` tab needs `conversation_manage` or `conversation_participating_manage` | `constants/permissions.js:38-59` |
| Delete a conversation | administrator only | `conversation_policy.rb:6-8`; UI `contextMenu/Index.vue:440` |
| Bulk conversation action | **no `authorize` call at all** — the controller authorizes the Contact branch and not the Conversation branch (`bulk_actions_controller.rb:12-24, 81-88`); narrowing happens later in the job via the filter service (`bulk_actions_job.rb:61-67`) | as cited |
| Folders | per user, never shared: both the index and the lookup scope to `user: Current.user` | `custom_filters_controller.rb:30-40` |
| Grandfather rule | a capability set created before this release that names none of the three keeps full access (`conversation_scope_enforced = false`) | `capability_scope.rb:31-35,137`; `custom/db/migrate/20261011180000_add_conversation_scope_enforced_to_custom_roles.rb` |

Feature flags in scope: `conversation_unread_counts` (ships **disabled**, internal — `config/features.yml:28-31`),
`conversation_required_attributes` (disabled, premium — `:268-271`), `assignment_v2`, `sla`
(`_conversation.json.jbuilder:73-74`).

Note the honesty gap the tab permissions create: a `conversation_participating_manage` holder is shown the
**All** tab (`permissions.js:51-58`) while both the server scope (`capability_scope.rb:81`) and the browser's
own `applyRoleFilter` (`store/modules/conversations/helpers.js:103-105`) restrict it to their own conversations.
"All" shows exactly what "Mine" shows, and the Unassigned tab is hidden.

## 7. Contextual-help opportunities

`DOC_ARTICLES` already holds `conversations: 'work-in-the-inbox'` and
`assignAndPrioritise: 'assign-and-prioritise'` (`helper/documentationLinks.js:19-20`). **Neither is consumed
anywhere in the conversation or inbox UI** — the only dashboard consumers of `DocsLink` /
`documentationArticleUrl` today are the commerce panel, the commerce settings dialogs and the Platform Support
pages. There is no contextual help on any lifecycle surface.

| UI location | The question an agent has there | Registry key | Key exists? |
|---|---|---|---|
| `ChatList.vue:974-994` empty state, `STATUS_FILTERED` | "where did my resolved conversations go?" | `conversations` | yes, unused |
| `ChatListHeader.vue:116-137` status chip | "what do open / pending / snoozed / resolved mean?" | `conversations` | yes, unused |
| `ChatList.vue:967-972` assignee tabs | "why is Unassigned missing / why does All look like Mine?" | `permissions` | yes, unused |
| `ResolveAction.vue:235-246` snooze item | "what does *until next reply* do if they never reply?" | needed: `snooze-a-conversation` | **no** |
| `ConversationHeader.vue:160-163` "Snoozed until…" | "can I un-snooze it now?" | needed: `snooze-a-conversation` | **no** |
| `conversationBulkActions/Index.vue` bulk bar | "does this cover the conversations I have not scrolled to?" | needed: `bulk-actions-on-conversations` | **no** (`bulkActions` is contacts-only) |
| `ChatList.vue:1030-1042` filter panel / `SaveCustomView.vue` | "can my team see this folder?" | needed: `folders-and-saved-filters` | **no** |
| `ConversationFilter` attribute list | "what can I filter on?" | needed: `folders-and-saved-filters` | **no** |
| `ReplyBoxBanner.vue:128-130` not-assigned-to-you | "should I take this?" | `assignAndPrioritise` | yes, unused |
| `ReplyBoxBanner` bot-handoff banner | "what happens to the bot if I take over?" | `agentBots` | yes, unused |
| `ConversationAction.vue:36-61` priority picker | "does urgent actually do anything?" | `assignAndPrioritise` | yes, unused |
| `ConversationResolveAttributesModal` | "why can I not resolve this?" | needed: `required-attributes-before-resolving` | **no** |
| `MoreActions.vue:31-45` "Block Contact" | "what does blocking do to this conversation?" | needed: `block-a-contact` | **no** |
| `ContactPanel.vue:149-158` draggable sidebar | "can I reorder / hide these panels?" | `conversations` | yes, unused |
| `EmptyState.vue` `NO_INBOX_AGENT` | "how do I get added to a channel?" | `inboxes` / `teams` | yes, unused |
| `ChatList.vue:1017-1029` delete dialog | "is this reversible? what goes with it?" | needed: `delete-a-conversation` | **no** |

## 8. Current documentation coverage

Two articles in `custom/db/documentation/{en,ar}/conversations/` cover this scope, and both are unusually good
for this corpus — written against behaviour, with explicit limits and a troubleshooting section.

| File | Covers | Verdict for this scope |
|---|---|---|
| `work-in-the-inbox.md` (1067 EN words) | the four statuses and what reopens each; the three stacked filters; the four sidebar views; folders as private saved filters; private notes; mentions; bulk/folder/mute limits | the strongest coverage of lifecycle in the corpus; claims verified below |
| `assign-and-prioritise.md` (991 words) | agent vs team ownership; team assignment clearing a non-member assignee; auto-assignment defaults; priority as a marker, not a mechanism; bulk bar contents | accurate; numbers check out |
| `labels.md`, `macros.md`, `canned-responses.md`, `macros-or-automation.md` | adjacent, not lifecycle | out of scope here |
| `contacts/bulk-actions.md` | contacts only, and says so in its title | does **not** cover conversation bulk actions |

Claims I checked against code:

| Claim | Verdict | Evidence |
|---|---|---|
| resolved reopens as open on a customer reply; as pending on a bot channel | confirmed | `message.rb:404-411, 425-435` |
| "until next reply" sets no time and stays snoozed indefinitely | confirmed | `snoozeHelpers.js:47-58`, `CmdBarConversationSnooze.vue:37-41` |
| Unattended = never replied to, plus a customer message still unanswered | confirmed | `conversation.rb:95`, `conversation_finder.rb:129-130` |
| sort options are last activity, created, priority, longest waiting, unread | confirmed | `sort_service.rb:3-20`, `ConversationBasicFilter.vue:53-94` |
| a conversation folder is yours alone and cannot be shared | confirmed | `custom_filters_controller.rb:30-40` |
| bulk selection covers only the page in front of you | confirmed | `useBulkActions.js:42-53` over `conversationList`; no `all_matching` branch for Conversation in `bulk_actions_controller.rb:97-105` |
| bulk reaches status, snooze, agent, team, labels — not priority | confirmed | `bulk_actions_controller.rb:100-104` |
| only agents set `online` are auto-assignment candidates | confirmed | `agent_assignment_service.rb:61-71` |
| at most five new conversations per agent per inbox in five minutes | confirmed as the default | `auto_assignment/rate_limiter.rb:20-26` |
| conversations idle more than seven days are excluded from auto-assignment | confirmed | `AssignmentPolicy::DEFAULT_EXCLUDE_OLDER_THAN_HOURS = 168` (`assignment_policy.rb:25`), applied at `assignment_service.rb:52-60` |
| assigning a team clears an assignee outside that team | confirmed | `assignment_handler.rb:12-21` |
| priority does not affect assignment or notification | confirmed | `toggle_priority` is a bare save (`conversation.rb:178-181`); no priority term in `assignment_service.rb:35-50` |
| assigning a bot sets pending and clears the human assignee | partly | creation does (`conversation.rb:319-325`); on an existing conversation `reset_agent_bot_when_assignee_present` only clears the *bot* when a human is set (`:301-305`) — the inverse, and no status change, in `assignments_controller.rb:15-23` |
| "no separate sweep" for assignment | mostly | true for the default path; `AutoAssignment::PeriodicAssignmentJob` is a sweep, gated on `assignment_v2` + an inbox policy (`periodic_assignment_job.rb:4-18`) |

## 9. Missing or stale documentation

Missing — a stuck user cannot find these anywhere in the corpus:

1. **Snooze on its own terms.** Covered in five lines inside `work-in-the-inbox.md`. Nothing says the timed
   reopen is a background job on a five-minute cadence with a three-day recovery window
   (`reopen_snoozed_conversations_job.rb:5`), nothing explains that a snoozed conversation offers no snooze
   control (`ResolveAction.vue:51-53`), and nothing tells an agent how to un-snooze early.
2. **Folders and advanced filters as a subject.** No article names a single filterable attribute, the AND/OR
   query operator, the 1000-folder limit (`lib/limits.rb:11`), or the four error messages a bad filter produces
   (`en.yml:271-274`).
3. **Bulk actions on conversations.** The one bulk article is explicitly about contacts. Nothing documents that
   a conversation bulk action is queued rather than applied, that the alert fires on enqueue
   (`useBulkActions.js:212`), that there is no completion signal, or that resolving in bulk silently *skips*
   conversations missing required attributes (`:166-193`).
4. **Required attributes before resolving.** An entire premium feature (`features.yml:268-271`) with a modal, a
   bulk skip path and two alert strings, and no article at all.
5. **"Why is this conversation not in my list?"** The inbox-vs-team asymmetry (§5) is the single most likely
   invisible-conversation cause after the status filter, and no article mentions team membership as separate
   from channel membership.
6. **Unread semantics.** Nothing explains that *Mark as unread* produces a count of 1 regardless of how many
   messages were unread (`conversations_controller.rb:127-131`), that the badge caps at `9+`, or that read state
   is throttled to once an hour when there is nothing unread (`:112-125`).
7. **Deleting a conversation.** Administrator-only, asynchronous (`DeleteObjectJob`), audited on destroy only
   (`custom/app/models/custom/audit/conversation.rb:15`), and it takes messages, attachments, participants,
   notifications, reporting events and any CSAT response with it (`conversation.rb:127-134`). Undocumented.
8. **Auto-resolve.** `Conversations::ResolutionJob` can resolve a whole account's idle conversations, optionally
   posting a message and applying a label (`resolution_job.rb:11-21`, capped at
   `Limits::BULK_ACTIONS_LIMIT = 100` per run). No article mentions the setting or the cap.

Stale:

- `work-in-the-inbox.md:105-106` says "**Mute does more than mute.**" The control is no longer labelled mute:
  it reads **Block Contact** / **Unblock Contact** (`CONTACT_PANEL.MUTE_CONTACT`, surfaced at
  `MoreActions.vue:31-45`). A reader looking for "mute" finds nothing.
- `work-in-the-inbox.md:36` lists the sort orders but not `priority_desc_created_at_asc`
  ("Priority: Highest first, Created: Oldest first"), which the dropdown offers
  (`ConversationBasicFilter.vue:82-85`).

## 10. Doc claims not proven by code

1. **"Muting … blocks the contact, so nothing further from that person opens a conversation."**
   (`work-in-the-inbox.md:105-106`.) A conversation *is* opened: `determine_conversation_status` sets
   `status = :resolved` and returns (`conversation.rb:308`). The thread exists, holds the customer's messages,
   and appears under the Resolved and All status filters. The honest statement is that it arrives already
   resolved and that replies never reopen it (`message.rb:405`).
2. **"A snoozed conversation never came back. It was snoozed until next reply."**
   (`work-in-the-inbox.md:124-125`, offered as the only explanation.) A second cause exists: the reopen job's
   `3.days.ago..Time.current` window (`reopen_snoozed_conversations_job.rb:5`) permanently skips any snooze that
   expired during a scheduler outage longer than three days.
3. **"Any agent can … change the status of any conversation on a channel they belong to, or assigned to one of
   their teams."** (`work-in-the-inbox.md:93-96`.) True for the record path only. A team-only member can change
   the status of such a conversation via its URL, but it is absent from every list, every count and every search
   result (`permission_filter_service.rb:22` vs `conversation_policy.rb:16-18`) — so in practice they cannot
   find it. The article's own §"If it does not work" tells them to "check you are a member of that channel",
   which is the right advice and contradicts the permission paragraph above it.
4. **"Assigning a bot to a conversation sets it to pending and clears the human assignee."**
   (`assign-and-prioritise.md:102-103`.) Verified only for conversation *creation* on a bot inbox
   (`conversation.rb:319-325`). The assignments endpoint with `assignee_type: 'AgentBot'` goes through
   `Conversations::AssignmentService` and `assignments_controller.rb:15-23` with no status change; the model's
   `reset_agent_bot_when_assignee_present` implements the opposite direction only (`conversation.rb:301-305`).
   Unverified for the post-creation case; confirming it needs a read of
   `app/services/conversations/assignment_service.rb`, which Agent 032 owns.
5. **"Priority … does not notify anyone extra, and does not start any clock."**
   (`assign-and-prioritise.md:52-54`.) The notification half is confirmed. The "no clock" half is not checkable
   from this scope: SLA is applied per conversation (`_conversation.json.jbuilder:73-74`) and whether any SLA
   policy keys off priority lives outside the files in this brief. Recorded as **unverified**.
