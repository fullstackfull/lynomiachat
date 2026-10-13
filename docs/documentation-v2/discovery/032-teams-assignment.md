---
agent: 032
scope: Teams, agents, assignment (manual + auto), availability/online status, assignment policies, business hours
confidence: high
---

## 1. What the feature is

Four different memberships decide who answers a conversation, and the product keeps them deliberately separate.

| Record | Table | What it decides |
|---|---|---|
| `AccountUser` | `account_users` | the person is in the account at all; carries `role`, `availability`, `auto_offline`, `custom_role_id` (`app/models/account_user.rb:27-45`) |
| `InboxMember` | `inbox_members` | which inbox's conversations the person can see and be assigned (`app/models/inbox_member.rb:17-27`) |
| `TeamMember` | `team_members` | which named group the person belongs to (`app/models/team_member.rb:17-22`) |
| `Team` | `teams` | a group a conversation can be handed to; carries `allow_auto_assign` (`app/models/team.rb:20-33`) |

Only inbox membership grants access. A team is a queue label with one behaviour attached (`allow_auto_assign`).
`inbox.assignable_agents` is `inbox members + all account administrators` (`app/models/inbox.rb:174-176`), so an
administrator is assignable everywhere without being a member — but auto-assignment only ever draws from
`inbox_members` (`app/models/concerns/inbox_agent_availability.rb:4-12`), so administrators are never auto-assigned.

**Two auto-assignment engines exist in the same tree and the choice is per-account.**
`inbox.auto_assignment_v2_enabled?` is `account.feature_enabled?('assignment_v2')`
(`app/models/inbox.rb:206-208`), and `assignment_v2` ships `enabled: true` (`config/features.yml:211-213`). So **V2 is
the live path on a default Lynomia install**, and V1 is dead code unless an operator turns the flag off:

- **V1 (legacy)** — `AutoAssignment::AgentAssignmentService` called inline from the conversation's own `before_save`
  on a status change to open, and post-save for new records (`app/models/concerns/auto_assignment_handler.rb:15-38`).
  Round-robin over a Redis list keyed per inbox (`app/services/auto_assignment/inbox_round_robin_service.rb`,
  key `ROUND_ROBIN_AGENTS:<inbox_id>`, `lib/redis/redis_keys.rb:4`). No rate limit, no priority, no staleness cut-off.
- **V2** — the conversation save only enqueues `AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox.id)`
  (`app/models/concerns/auto_assignment_handler.rb:29-33`), coalesced to one in-flight job per inbox by a Redis
  marker with a 5-minute TTL (`app/jobs/auto_assignment/assignment_job.rb:9-23`). The job then bulk-assigns up to
  `AUTO_ASSIGNMENT_BULK_LIMIT` (default 100) unassigned open conversations
  (`app/services/auto_assignment/assignment_service.rb:4-17`). V2 is additionally triggered when a conversation is
  **resolved or snoozed**, so freed capacity is redistributed (`app/models/concerns/auto_assignment_handler.rb:24-26`).

V2's selection order (`app/services/auto_assignment/assignment_service.rb:35-93`):
1. scope = `inbox.conversations.unassigned.open`;
2. drop conversations whose `last_activity_at` is older than `exclude_older_than_hours` (policy value, else the
   `AssignmentPolicy::DEFAULT_EXCLUDE_OLDER_THAN_HOURS = 168` constant, i.e. 7 days) — lines 52-66;
3. order by `created_at ASC`, or `last_activity_at ASC` when the policy says `longest_waiting` — lines 43-48;
4. candidate agents = `inbox.available_agents` (inbox members whose Redis status is exactly `online`);
5. if the conversation has a team, intersect with that team's members, and **abort entirely** if the team has
   `allow_auto_assign` false — lines 78-86;
6. drop agents over the fair-distribution rate limit (`app/services/auto_assignment/rate_limiter.rb`);
7. pick one by round robin (`app/services/auto_assignment/round_robin_selector.rb`);
8. claim the row with `FOR UPDATE SKIP LOCKED` and `update!(assignee:)` — lines 109-124.

**The rate limit's no-policy default is 5 conversations per 5 minutes**, not the policy default of 100/hour:
`limit` falls back to `5` and `window` to `5.minutes` when `inbox.assignment_policy` is nil
(`app/services/auto_assignment/rate_limiter.rb:20-30`). Each assignment is a Redis key with a TTL
(`ASSIGNMENT::<inbox>::AGENT::<agent>::CONVERSATION::<id>`, `lib/redis/redis_keys.rb:96-97`) and the count is a
`KEYS`-pattern count (`rate_limiter.rb:13-16`).

**A 30-minute sweep exists but only reaches inboxes that have a policy.** `AutoAssignment::PeriodicAssignmentJob`
runs at `*/30 * * * *` (`config/schedule.yml:59-62`) and iterates `account.inboxes.joins(:assignment_policy)`
(`app/jobs/auto_assignment/periodic_assignment_job.rb:9`). An inbox with no linked policy — the normal case, since
the policy UI is premium-gated — gets no sweep at all, so a conversation that found nobody online waits for the next
create/open/resolve/snooze event on that inbox.

**Team assignment has its own, separate assignment path.** `AssignmentHandler#ensure_assignee_is_from_team` is a
`before_save` on `Conversation` (`app/models/concerns/assignment_handler.rb:5-29`). When `team_id` changes it
(a) clears the assignee if that person is not a member of the new team (line 21), then (b) if the team allows auto
assign, picks one agent from `inbox.member_ids_with_assignment_capacity & team.members.ids` restricted to online
agents (lines 24-29). **This path never checks `inbox.enable_auto_assignment`** — setting a team auto-assigns a
member even on an inbox where auto-assignment is switched off. It also uses the V1 service regardless of the
`assignment_v2` flag, so an account on V2 has two different selectors in play. The whole block is skipped when
`ai_assignee_type` is present (line 14).

Manual assignment is `Conversations::AssignmentService` (`app/services/conversations/assignment_service.rb`):
assigning a bot clears the human assignee and forces status `pending` (lines 37-47); assigning a human clears
`ai_assignee` and, if the conversation was pending under a bot, reopens it and stamps `waiting_since` (lines 16-27).

Per-agent capacity does not exist in this tree. `Inbox#member_ids_with_assignment_capacity` returns every member
(`app/models/inbox.rb:202-204`), `InboxAgentAvailability#member_ids_with_assignment_capacity` likewise
(`app/models/concerns/inbox_agent_availability.rb:14-16`), and `Inbox#ensure_valid_max_assignment_limit` is an empty
stub whose comment says "overridden in enterprise/app/models/enterprise/inbox.rb"
(`app/models/inbox.rb:256-258`) — **a file that does not exist; there is no `enterprise/` tree in this repository.**
The `inboxes.auto_assignment_config` jsonb column is therefore inert: nothing reads or validates it.

Business hours are inbox-level only: `WorkingHour` `belongs_to :inbox` with a per-weekday open/close row
(`app/models/working_hour.rb:23-41`), plus `inboxes.working_hours_enabled`, `timezone` and `out_of_office_message`.
They feed exactly two things: the out-of-office auto-reply (`app/services/message_templates/hook_execution_service.rb:17,32`)
and business-hours-aware reporting (`app/helpers/reporting_event_helper.rb:3-9`). **Business hours have no effect on
assignment or on availability.**

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| Agents list / invite / edit / delete | `app/javascript/dashboard/routes/dashboard/settings/agents/{Index,AddAgent,EditAgent}.vue`; route `agent_list`, flag `AGENT_MANAGEMENT`, `permissions: ['administrator']` (`agents/agent.routes.js:19-26`) |
| Teams list + create/edit wizard | `settings/teams/{Index,TeamForm}.vue`, `Create/*`, `Edit/*`; routes `settings_teams_list`, `settings_teams_new`, `settings_teams_add_agents`, `settings_teams_edit`, `settings_teams_edit_members` (`teams/teams.routes.js:28-112`), all flag `TEAM_MANAGEMENT` + administrator |
| Inbox collaborators + auto-assignment toggle + policy linking | `settings/inbox/settingsPage/CollaboratorsPage.vue` (toggle at :234, policy block at :369-571) |
| Assignment policy screens | `settings/assignmentPolicy/{Index.vue,pages/*}`; routes `assignment_policy_index`, `agent_assignment_policy_{index,create,edit}` flagged `ASSIGNMENT_V2`; `agent_capacity_policy_{index,create,edit}` flagged `ADVANCED_ASSIGNMENT` (`assignmentPolicy/assignmentPolicy.routes.js:25-86`) |
| Sidebar nav | Agents `:814-819`, Teams `:820-835`, **Agent Assignment only when `advanced_assignment` is on** `:850-867` (`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`) |
| My own availability + auto-offline | `components-next/sidebar/SidebarProfileMenuStatus.vue:62-75, 117-120` |
| Per-conversation assignee / team pickers + "Assign to me" | `routes/dashboard/conversation/ConversationAction.vue:237-271` (self-assign button at :246) |
| Bulk assign agent/team | `components/widgets/conversation/conversationBulkActions/BulkAgentActions.vue` |
| Business hours editor | `settings/inbox/components/BusinessDay.vue`, `settings/inbox/helpers/businessHour.js` |

| API | Controller |
|---|---|
| `GET/POST/PATCH/DELETE /api/v1/accounts/:id/agents`, `POST .../agents/bulk_create` | `app/controllers/api/v1/accounts/agents_controller.rb:5-46` |
| `…/teams` CRUD | `app/controllers/api/v1/accounts/teams_controller.rb:5-23` |
| `…/teams/:team_id/team_members` index/create/update/destroy | `app/controllers/api/v1/accounts/team_members_controller.rb:6-30` |
| `…/inboxes/:inbox_id/inbox_members` | `app/controllers/api/v1/accounts/inbox_members_controller.rb:5-30` |
| `…/inboxes/:inbox_id/assignable_agents`, `…/assignable_agents?inbox_ids[]=` | `app/controllers/api/v1/accounts/inboxes_controller.rb:20-21`; `assignable_agents_controller.rb:4-16` |
| `POST …/conversations/:id/assignments` (agent, bot or team) | `app/controllers/api/v1/accounts/conversations/assignments_controller.rb:3-43` |
| `…/assignment_policies` CRUD, `…/assignment_policies/:id/inboxes`, `…/inboxes/:inbox_id/assignment_policy` | `assignment_policies_controller.rb`, `assignment_policies/inboxes_controller.rb`, `inboxes/assignment_policies_controller.rb` (`config/routes.rb:253-259`) |
| `PUT /api/v1/profile/availability`, `PUT /api/v1/profile/auto_offline` | `app/controllers/api/v1/profiles_controller.rb:23-29` |
| `agent_capacity_policies` (+ `/users`, `/inbox_limits`) | **no controller, no route, no model** — see §5 |

Lynomia overlay (`custom/app/**`): only two things touch this area. `Custom::Api::V1::Accounts::AgentsController`
prepends `custom_role_id` attach/detach onto agent create/update and forces `role = :agent` when a set is attached
(`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:28-58`). `Billing::AgentLimit` adds a
create-time validation to `AccountUser` (`custom/app/models/billing/agent_limit.rb:12-25`) counting
`account.account_users.count` against the plan entitlement under `account.lock!`
(`custom/app/models/billing/resource_limit.rb:28-48`). Audit capture exists for team, team member, inbox member and
account user (`custom/app/models/custom/audit/{team,team_member,inbox_member,account_user}.rb`). Flow nodes
`Flows::Nodes::AssignAgent` / `AssignTeam` call core `ActionService` and branch to `failed` when the assignment did
not stick (`custom/app/services/flows/nodes/assign_{agent,team}.rb`). The Platform Support Desk has a wholly separate
assignment model — `PlatformSupport::Agent` is a SuperAdmin-backed row, never an `AccountUser`
(`custom/app/models/platform_support/agent.rb:20-38`, `custom/app/services/platform_support/ticket_assignment.rb`);
that belongs to agent 048.

## 3. User-visible states

**Agents list** — skeleton while `agents/getUIFlags.isFetching`; `AGENT_MGMT.LIST.404` when empty;
`AGENT_MGMT.NO_RESULTS` when a search matches nothing. Each row shows a status chip of `Verified` or
`Verification Pending` (`AGENT_MGMT.LIST.VERIFIED` / `VERIFICATION_PENDING`) — this is Devise confirmation, **not
availability; the agents list never shows who is online.** Edit is hidden for yourself
(`agents/Index.vue:85-87`); delete is hidden for yourself and for the last verified administrator (`:89-102`).

**Availability** — three values (`online`, `busy`, `offline`; `app/models/account_user.rb:35`) plus the
`auto_offline` boolean. The effective value an API consumer sees is computed, not stored: with `auto_offline` true
it is `offline` unless Redis presence is fresh, and with `auto_offline` false it is the stored column
(`app/models/concerns/availability_statusable.rb:23-29`). Presence expires after `PRESENCE_DURATION`, default 20
seconds (`lib/online_status_tracker.rb:3`). The computed value is what `_agent.json.jbuilder:4` returns.

**Teams** — `TEAMS_SETTINGS.LIST.404` when none; `is_member` on each team drives the sidebar's team list, so an
agent sees only their own teams under Conversations (`app/views/api/v1/models/_team.json.jbuilder:8`,
`store/modules/teams/getters.js:11-16`).

**Inbox collaborators / assignment** — with `assignment_v2` only, the page shows a read-only "Default assignment
rules" panel listing "Earliest created conversations first" and "Round robin distribution"
(`CollaboratorsPage.vue:540-571`). With `advanced_assignment` as well, the policy linking UI appears (`:369-520`).
`fetchAssignmentPolicy` swallows the 404 for an unlinked inbox and renders the default state (`:101-114`).

**Conversation** — assignee and team pickers, each with a `None` option; the `None` agent is a synthetic row with
`id: 0` (`composables/useAgentsList.js:34-41`) and selecting the current assignee again unassigns
(`ConversationAction.vue:199-215`). An unassigned conversation shows an "Assign to me" banner above the reply box
(`components/widgets/conversation/ReplyBoxBanner.vue:130`).

## 4. Errors and validation messages

| Message | Key / source | Where |
|---|---|---|
| `Account limit exceeded. Please purchase more licenses` → HTTP 402 | literal `AgentBuilder::LIMIT_EXCEEDED_MESSAGE` | `app/builders/agent_builder.rb:5`; rendered `agents_controller.rb:21-22` |
| `Your plan allows up to %{limit} team members. Upgrade your plan to invite more.` → 422 | `errors.billing.limit_reached.agents` | `config/locales/en.yml:300`, raised from `custom/app/models/billing/agent_limit.rb:24` |
| `Agent email already in use, Please try another email address` (shown for **any** 422 that is not on `base`) | `AGENT_MGMT.ADD.API.EXIST_MESSAGE` | `agents/AddAgent.vue:95-96` |
| `Could not connect to Woot Server, Please try again later` | `AGENT_MGMT.{ADD,EDIT,DELETE}.API.ERROR_MESSAGE` | `agentMgmt.json:48,55,91` — **unbranded "Woot Server" leaks in three agent flows** |
| `Role is required` / `Availability is required` | `AGENT_MGMT.{ADD,EDIT}.FORM.AGENT_TYPE.ERROR`, `EDIT.FORM.AGENT_AVAILABILITY.ERROR` | `agentMgmt.json:37,83` |
| `Cannot change availability while impersonating a user` | `PROFILE_SETTINGS.FORM.AVAILABILITY.IMPERSONATING_ERROR` | `SidebarProfileMenuStatus.vue:64` |
| `Couldn't save the team details. Try again.` — the **only** team save error, for every cause | `TEAMS_SETTINGS.TEAM_FORM.ERROR_MESSAGE` | `teams/Create/CreateTeam.vue:32`, `teams/Edit/EditTeam.vue:52` |
| `Name has already been taken` (422, never shown) | `validates :name, uniqueness: { scope: :account_id }` | `app/models/team.rb:31-33` |
| `can't be blank` via `errors.validations.presence` | `app/models/team.rb:32` | server only |
| `Invalid User IDs` → **HTTP 401** | literal | `team_members_controller.rb:53` |
| `Assignment policy not found` → 404 | `errors.assignment_policy.not_found` | `config/locales/en.yml:103`; `inboxes/assignment_policies_controller.rb:44` |
| `Role is required` on custom-role conflict → 422 | `errors.custom_roles.administrator_conflict`, `errors.custom_roles.not_found` | `custom/.../agents_controller.rb:79-82` |
| Deleting a team requires typing its exact name | `TEAMS_SETTINGS.DELETE.CONFIRM.PLACE_HOLDER`, `confirm-value` | `teams/Index.vue:77-78, 227` |

Client validation: agent name and email are `required` + email format; **team name is validated as
`required, minLength(2)`** (`teams/helpers/validations.js:4-7`). The same file declares a rule for
`showOnSidebar`, a key that does not exist in the form state (`teams/TeamForm.vue:54-60`) — dead.

## 5. Failure paths

1. **Agent Capacity Policy has a complete frontend and no backend.** `api/agentCapacityPolicies.js`,
   `store/modules/agentCapacityPolicies.js`, three route pages and the `AGENT_CAPACITY_POLICY` i18n tree all exist,
   but there is no `agent_capacity_policies` route, controller or model anywhere in `app/`, `custom/` or `lib/`
   (the only Ruby trace is the `account_users.agent_capacity_policy_id` column comment,
   `app/models/account_user.rb:13`). The index page is reachable whenever `advanced_assignment` is enabled
   (`assignmentPolicy.routes.js:60-86`, landing card at `assignmentPolicy/Index.vue:53-75`) and every request would
   404. The feature ships `enabled: false, premium: true` (`config/features.yml:272-275`), so today nobody can reach
   it — **but enabling the premium flag that the UI is gated on breaks the page it unlocks.**
2. **"Balanced" assignment does not exist in the backend.** `AssignmentPolicy` declares
   `enum assignment_order: { round_robin: 0 }` (`app/models/assignment_policy.rb:38`), while the form offers
   `balanced` as a premium-badged radio (`assignmentPolicy/constants.js:3,18`;
   `pages/components/AgentAssignmentPolicyForm.vue:138-146`) and two places render a `balanced` label
   (`CollaboratorsPage.vue:108-110`, `inboxMgmt.json` `ASSIGNMENT.METHOD.BALANCED`). The controller passes
   `assignment_order` straight into `create!`/`update!` (`assignment_policies_controller.rb:12,16,30-36`) and nothing
   rescues `ArgumentError`, so a `balanced` value is an unhandled 500, not a 422 and not a round-robin fallback.
   `AutoAssignment::AssignmentService` has no load-based branch at all.
3. **Assignment policies are a premium capability enforced only in the browser.** `AssignmentPolicyPolicy` checks
   `administrator?` and nothing else (`app/policies/assignment_policy_policy.rb`), and
   `AutoAssignment::AssignmentService` honours `inbox.assignment_policy` whenever `assignment_v2` is on
   (`assignment_service.rb:39-66`, `rate_limiter.rb:28-30`). Any administrator can create and link a policy over the
   API without `advanced_assignment`, and it takes effect.
4. **Manual assignment accepts an agent with no access to the inbox.** `Conversations::AssignmentService#assignee` is
   `conversation.account.users.find_by(id: assignee_id)` (`app/services/conversations/assignment_service.rb:49-51`) —
   no inbox-membership and no administrator check — and `Conversation` has no validation on `assignee`
   (`app/models/conversation.rb:116`). The automation path *does* check (`ActionService#assign_agent` calls
   `agent_belongs_to_inbox?` and `confirmed?`, `app/services/action_service.rb:47-50`) and the UI only offers
   `assignable_agents`, but the REST endpoint does not. The non-member then silently loses the conversation on the
   next status change, because `should_run_auto_assignment?` treats `inbox.members.exclude?(assignee)` as
   reassignable (`app/models/concerns/auto_assignment_handler.rb:63-64`).
5. **`auto_offline: false` makes an agent permanently assignable.** `get_available_user_ids` unions Redis presence
   with every `account_user` where `auto_offline` is false, regardless of presence
   (`lib/online_status_tracker.rb:76-78`). An agent who turns off "Mark offline automatically" and leaves their
   status on Online keeps receiving auto-assigned conversations with the browser closed, overnight, on leave. The
   toggle's help text — "Let the system automatically mark you offline when you aren't using the app or dashboard"
   (`settings.json:412-414`) — does not say this.
6. **Removing an agent from an inbox leaves their conversations assigned to them.**
   `InboxMember`'s `after_destroy` only pops the round-robin queue (`app/models/inbox_member.rb:26,35-37`);
   nothing unassigns. Removing them from the **account** does unassign, via
   `AccountUser#remove_user_from_account → Agents::DestroyJob`, which destroys the notification setting, team
   memberships and inbox memberships and `update_all(assignee_id: nil)` on their conversations
   (`app/models/account_user.rb:54-56`, `app/jobs/agents/destroy_job.rb:4-40`). That job runs on the `low` queue,
   so the unassignment is eventually-consistent, and `update_all` fires no activity message and no
   `assignee.changed` event.
7. **Going offline does nothing to work already assigned.** There is no job, callback or sweep that reassigns or
   unassigns on an availability change — `after_save :update_presence_in_redis` only writes the Redis hash
   (`app/models/account_user.rb:41, 81-83`). A conversation assigned to someone who then goes offline, is set to
   busy, or closes the tab stays theirs indefinitely. V2's resolve/snooze trigger redistributes *unassigned* work
   only (`assignment_service.rb:30-33`).
8. **Deleting a team is a silent `UPDATE`.** `has_many :conversations, dependent: :nullify`
   (`app/models/team.rb:26`) nulls `team_id` with `update_all`, bypassing `AssignmentHandler`, so there is no
   `team.changed` event and no activity message on any of those conversations — they simply lose their team. The
   assignee is kept. `team_members` are `destroy_async` (`:24`), so membership rows disappear on a background queue.
9. **Removing a team from a conversation does not clear the assignee**, while *setting* one does.
   `validate_current_assignee_team` is `self.assignee_id = nil if team&.members&.exclude?(assignee)` — with `team`
   nil the safe-navigation yields nil and the branch is skipped (`app/models/concerns/assignment_handler.rb:20-22`).
10. **Two agent limits with two different messages.** `AgentBuilder#can_add_agent?` compares
    `account.usage_limits[:agents]` and raises a 402 with English hard-coded in Ruby
    (`app/builders/agent_builder.rb:5,40-42`); `Billing::AgentLimit` then re-checks the same thing through
    entitlements and fails the `AccountUser` save with a 422 and a translated message. A user can see either, for
    the same wall.
11. **Bulk invite is partially atomic and silently drops bad rows.** `bulk_create_agents` takes
    `Current.account.with_lock`, raises if `emails.count > available_agent_count`, then rescues
    `ActiveRecord::RecordInvalid` per email and only logs it (`agents_controller.rb:78-104`). The response is
    `head :ok` either way: the caller is not told which addresses were skipped.
12. **The in-flight coalescing marker can starve an inbox for 5 minutes.** `enqueue_for_inbox` returns false when a
    marker exists (`app/jobs/auto_assignment/assignment_job.rb:12`); if the worker dies after claiming without
    reaching `ensure`, the inbox assigns nothing until the TTL lapses — and with no policy linked, no periodic sweep
    covers it (see §1).
13. **Round-robin queue drift self-heals by resetting.** `validate_queue?` compares the Redis list to
    `inbox_members` and rebuilds the whole queue on any mismatch (`inbox_round_robin_service.rb:19-23, 52-54`), so
    every membership change discards the rotation position and the "in turn" guarantee restarts.

## 6. Permissions

| Surface | Gate | Citation |
|---|---|---|
| Agents settings page | `AGENT_MANAGEMENT` flag + `permissions: ['administrator']` | `agents/agent.routes.js:22-25` |
| Teams settings pages | `TEAM_MANAGEMENT` flag + administrator | `teams/teams.routes.js:31-34` and each child |
| Assignment policy pages | `ASSIGNMENT_V2` flag + administrator | `assignmentPolicy.routes.js:28-58` |
| Agent capacity pages | `ADVANCED_ASSIGNMENT` flag + administrator | `assignmentPolicy.routes.js:64-85` |
| Sidebar "Agent Assignment" entry | `advanced_assignment` only | `Sidebar.vue:79-84, 850` |
| Agent create / update / destroy / bulk_create | `UserPolicy#{create?,update?,destroy?,bulk_create?}` = administrator; `index?` = **true for everyone** | `app/policies/user_policy.rb` |
| Team create / update / destroy | `TeamPolicy` administrator; `index?` and `show?` = **true for everyone** | `app/policies/team_policy.rb` |
| Assignment policy CRUD | `AssignmentPolicyPolicy` administrator for every action; **no entitlement check** | `app/policies/assignment_policy_policy.rb` |
| Inbox members | `InboxPolicy#{create?,update?,destroy?}`; `assignable_agents?` separately | `app/policies/inbox_policy.rb:29` |
| Team membership add/remove | `check_authorization` against `TeamPolicy` (administrator) | `team_members_controller.rb:3` |
| Assign a conversation | only `authorize @conversation, :show?` — any agent who can see it can assign it to anyone | `conversations/base_controller.rb:6-9` |
| Own availability / auto-offline | the signed-in user's own `account_user` only | `profiles_controller.rb:23-29` |
| Custom-role capability list | `AccountUser#permissions`, overridden by `Custom::AccountUser#permissions` and bounded by `Billing::Entitlements` | `app/models/account_user.rb:58-60`; `custom/app/models/custom/account_user.rb:57-70` |

Feature-flag defaults: `agent_management` and `team_management` `enabled: true` (`config/features.yml:54-59`);
`assignment_v2` `enabled: true` (`:211-213`); `advanced_assignment` `enabled: false, premium: true` (`:272-275`).

## 7. Contextual-help opportunities

| UI location | The question a user has there | Registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `agents/Index.vue` header (`AGENT_MGMT.LEARN_MORE` "Learn about user roles") | what can an agent do that an administrator can't? | `rolesAndPermissions` | **no** — only `inviteYourTeam` and `teams` exist (`documentationLinks.js:15,81`) |
| `agents/AddAgent.vue` role selector (`:176`) | administrator vs agent vs a custom role | `inviteYourTeam` | yes (`:15`) |
| `agents/EditAgent.vue` availability select (`:188-202`) | why does setting someone Online not make them online? | new key, e.g. `agentAvailability` | **no** |
| `SidebarProfileMenuStatus.vue:117-120` auto-offline toggle | what happens to my assignments when I go offline? | new key, e.g. `agentAvailability` | **no** |
| `teams/TeamForm.vue:165` "Allow auto assign for this team" | what exactly does ticking this do? | `teams` | yes (`:81`) |
| `teams/Index.vue:224` delete confirmation | what happens to conversations in this team? | `teams` | yes |
| `CollaboratorsPage.vue:326` inbox agents picker | why can't I assign a colleague who is on the team? | `teams` | yes |
| `CollaboratorsPage.vue:369` auto-assignment toggle | who gets picked, in what order, how often? | `assignAndPrioritise` | yes (`:20`) |
| `CollaboratorsPage.vue:551-571` "Default assignment rules" panel | where do 5-per-5-minutes and 7 days come from? | `assignAndPrioritise` | yes |
| `AgentAssignmentPolicyForm.vue` fair-distribution + stale fields | what do these numbers mean against the defaults? | new key, e.g. `assignmentPolicies` | **no** |
| `AgentAssignmentPolicyForm.vue:141` Balanced premium badge | what is balanced assignment, and do I have it? | new key | **no** |
| `ConversationAction.vue:268` team picker | will assigning a team take it away from me? | `assignAndPrioritise` | yes |
| `settings/inbox/components/BusinessDay.vue` | do business hours stop auto-assignment? (no) | new key, e.g. `businessHours` | **no** |

## 8. Current documentation coverage

| File | Coverage of this scope |
|---|---|
| `custom/db/documentation/en/workspace/teams-and-agents.md` (968 words) | Strong. Role vs inbox vs team membership, `allow_auto_assign`, the assignee-cleared-on-team-change rule, lower-casing of names, delete semantics. Every structural claim I checked is correct. |
| `custom/db/documentation/en/conversations/assign-and-prioritise.md` (991 words) | Strong on the default behaviour: online-only, oldest-first, round robin, 5-per-5-minutes, 7-day staleness, team restriction, no sweep. |
| `custom/db/documentation/en/getting-started/invite-your-team.md` (890 words) | Correct on invite semantics, including that an existing login gets no email (`agent_builder.rb:62-64`) and that adding a person grants no inbox access. |
| `custom/db/documentation/en/workspace/roles-and-permissions.md` (935 words) | Agent 033's scope; referenced from here for role boundaries. |
| `custom/db/documentation/en/workspace/set-up-an-inbox.md` (909 words) | Covers collaborators; not read in depth here. |

Arabic counterparts exist for all four at the same paths under `custom/db/documentation/ar/`; semantic parity is
agent 061/094's call, not checked here. The `workspace` section is `position: 80` in
`custom/db/documentation/manifest.yml:87-95`.

## 9. Missing or stale documentation

1. **Availability has no article.** Nothing explains the three statuses, that the displayed status is derived from
   Redis presence rather than the stored value, that presence expires in 20 seconds, that `busy` is excluded from
   auto-assignment exactly like `offline`, or — the production trap — that turning off "Mark offline automatically"
   keeps you receiving conversations while your browser is shut. This is the single biggest gap in the scope.
2. **No article answers "what happens to my conversations when I go offline or leave".** The answer is: nothing on
   going offline or busy; on account removal, `Agents::DestroyJob` unassigns them, removes team and inbox
   memberships, and deletes the notification setting, asynchronously. Users ask this constantly and no file says it.
3. **Removing an agent from one inbox** (as opposed to the account) is undocumented, and its behaviour differs:
   assignments survive until the next status change.
4. **Assignment policies have no article at all.** `assign-and-prioritise.md` mentions them in one paragraph and
   says the screen is hidden without advanced assignment — true of the sidebar entry — but nothing documents
   `conversation_priority`, `fair_distribution_limit`/`fair_distribution_window`, `exclude_older_than_hours`, the
   one-policy-per-inbox rule (`InboxAssignmentPolicy` `validates :inbox_id, uniqueness: true`), or that linking a
   policy is what turns on the 30-minute sweep.
5. **Business hours have no article.** Inbox-level only, per weekday, one open/close window per day, requires
   `working_hours_enabled`, drives only the out-of-office reply and business-hours reporting, and has **no** effect
   on assignment or availability. `teams-and-agents.md` correctly says there is no team-level business-hours
   behaviour, but no file says what business hours *do*.
6. **`assign-and-prioritise.md` does not mention that setting a team auto-assigns even when the inbox's
   auto-assignment switch is off** (`app/models/concerns/assignment_handler.rb:24-29`), which contradicts the
   article's framing of the inbox switch as the master control.

## 10. Doc claims not proven by code

| Claim | Where | Verdict |
|---|---|---|
| "An administrator can replace these defaults … round robin or **balanced across current load**" and "**Balanced distribution is only honoured when advanced assignment is enabled.** A policy set to balanced falls back to round robin without it." | `en/conversations/assign-and-prioritise.md` §"Letting Lynomia Chat assign", §Limits | **Wrong.** No `balanced` enum value exists (`app/models/assignment_policy.rb:38`), no load-based selector exists, and there is no fallback code. A `balanced` value is an unrescued `ArgumentError`. The article has imported an upstream/enterprise capability this tree does not contain. |
| "the screen is hidden unless advanced assignment is enabled for your account" | same file | **Correct for the sidebar entry** (`Sidebar.vue:850`) and for the inbox policy UI (`CollaboratorsPage.vue:86-87`), but the routes themselves are gated on `assignment_v2` (`assignmentPolicy.routes.js:38`) and the API has no entitlement check, so the screen is reachable and functional by URL. Needs rewording, not deletion. |
| "An agent receives at most **five** new conversations from one channel in any five minutes." | same file | **Correct for an inbox with no policy** (`rate_limiter.rb:20-30`), but it is the fallback, not a setting, and the policy form's own help text says "Defaults to 100 per hour" (`settings.json` `FAIR_DISTRIBUTION.DESCRIPTION`), which is the *policy* default. Both numbers are true of different states; the docs state only one and the UI only the other. |
| "You can only assign an agent who is a member of that channel, or an administrator. Someone outside the channel cannot be given the conversation at all, and nothing is assigned." | same file | **True of the UI and of automations** (`action_service.rb:47-50`), **false of the REST endpoint** (`conversations/assignment_service.rb:49-51`). As written it describes an enforcement that does not exist at the API boundary. |
| "Without an assignment policy … There is no separate sweep." | same file §Limits | **Correct**, but only because `PeriodicAssignmentJob` joins `:assignment_policy` (`periodic_assignment_job.rb:9`). The sweep exists and is scheduled every 30 minutes; the article should say *policy-linked inboxes are swept*, not that no sweep exists. |
| "Conversations with no activity for more than seven days are left alone" | same file | **Correct** (`assignment_policy.rb:25`, `assignment_service.rb:52-66`), and correctly keyed on `last_activity_at`, not `created_at`. |
| "If the team allows auto-assignment, one member is then picked — but only from people who are both members of that team and collaborators on that inbox, and currently online." | `en/workspace/teams-and-agents.md` | **Correct** (`assignment_handler.rb:24-29`). Incomplete in one respect: it happens irrespective of the inbox's own auto-assignment switch. |
| "Removing a team from a conversation does not clear the assignee." | same file | **Correct** (`assignment_handler.rb:20-22`). |
| "Deleting a team does not delete its conversations. They are left with no team and keep their assignee." | same file | **Correct** (`app/models/team.rb:26`). |
| "Team names are stored in lower case and must be unique in the account." | same file | **Correct** (`app/models/team.rb:31-37`). |
| "Priority cannot be changed in bulk. The bulk bar covers status, snooze, agent, team and labels only." | `en/conversations/assign-and-prioritise.md` | Not verified here — bulk actions are agent 029's scope. Marked **unverified**. |
| "An administrator can also send a password-reset email to an agent from that agent's own page" | `en/getting-started/invite-your-team.md` | **Correct** (`agents/EditAgent.vue:146-151`). |
