---
agent: 033
scope: Roles and permissions — administrator/agent, custom roles and the permission vocabulary, server-side enforcement of each string, the plan-entitlement ceiling, inbox/team access limits, notification-feed ceiling
confidence: high
---

## 1. What the feature is

Every membership (`account_users`) carries exactly one built-in role — `agent` (0) or `administrator` (1),
`app/models/account_user.rb:34` — and optionally one `custom_role_id` pointing at a `CustomRole` row owned by the
same account (`db/schema.rb:1214-1223`). A custom role is a named list of capability strings on a Postgres
`text[]` column; there is no join table and no permission registry
(`custom/app/models/custom_role.rb:9-11`). There is no foreign key on `account_users.custom_role_id` or on
`custom_roles.account_id` (`custom/app/models/custom_role.rb:40,77`).

Three things follow, and they are the product's whole permission model:

1. **Administrator is the `role` column, never a capability.** Every administrator check in the product reads
   `account_user.administrator?`. A custom role cannot reach administrator, and holding every published
   capability still does not open an administrator endpoint
   (`custom/app/models/custom/account_user.rb:16-18,36-39`; `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:3-5`).
2. **A custom-role holder is always an agent.** The attach path forces `role = :agent` whenever a set id is
   supplied (`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:55-57`), and asking for
   `administrator` and a set in one request is refused
   (`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:79`).
3. **The effective capability list is one method.** `Custom::AccountUser#permissions` returns the set's
   capabilities plus a `'custom_role'` marker, or falls back to the built-in list `['agent']` / `['administrator']`
   (`custom/app/models/custom/account_user.rb:57-62`; OSS fallback `app/models/account_user.rb:58-60`). Every
   server-side capability reader goes through this one list.

### The permission vocabulary, exactly

`CustomRole::PERMISSIONS` is a closed, validated array of **eight** strings
(`custom/app/models/custom_role.rb:19-28`); the client offers **seven** of them
(`app/javascript/dashboard/constants/permissions.js:4-12`), `knowledge_base_manage` being retired but still
accepted so pre-existing rows stay saveable (`custom/app/models/custom_role.rb:30-34`).

| Permission string | Offered in UI | What it **actually** gates server-side | Where |
|---|---|---|---|
| `conversation_manage` | yes | widest conversation mode (`:base`) — no capability narrowing, ceiling still applies | `custom/app/services/conversations/capability_scope.rb:40,113` |
| `conversation_unassigned_manage` | yes | `:unassigned_and_mine` — `assignee_id = me OR (assignee_id IS NULL AND assignee_agent_bot_id IS NULL)` | `capability_scope.rb:51-52,80,114` |
| `conversation_participating_manage` | yes | `:mine` — `assignee_id = me` **only**. Participants are *not* included | `capability_scope.rb:81,100,115` |
| `contact_manage` | yes | `ContactPolicy#merge?` and `#manage_identities?` only | `custom/app/policies/custom/contact_policy.rb:15-27` |
| `report_manage` | yes | **nothing.** `ReportPolicy#view?` is administrator-only and has no overlay | `app/policies/report_policy.rb:2-4` |
| `commerce_order_manage` | yes | `Commerce::ActionPolicy#manage_orders?` → status change, resend invoice, resend payment link, update shipping | `custom/app/policies/commerce/action_policy.rb:8-21` |
| `support_ticket_manage` | yes | `Support::TicketPolicy` manage-all scope: every support case in the account | `custom/app/policies/support/ticket_policy.rb:15,24-26,37-50` |
| `knowledge_base_manage` | no (retired) | **nothing.** All portal/category/article policy methods are unconditionally `false` | `custom/app/policies/custom/{portal,category,article}_policy.rb` |

Two capabilities are therefore inert server-side (`report_manage`, `knowledge_base_manage`) and one more —
`contact_manage` — gates only two endpoints, not "contacts" generally (`ContactPolicy#index?/show?/update?/create?`
are all `true` for any member, `app/policies/contact_policy.rb:1-57`).

Three capability strings decide conversation access, and the rule is **widest wins**, resolved in one object
(`custom/app/services/conversations/capability_scope.rb:110-118`). A set naming none of the three means `:none`
— no conversation access at all — **unless** it is grandfathered.

### The grandfather column

`custom_roles.conversation_scope_enforced` (default `true`, `db/schema.rb:1221`) is `false` only for rows that
predate the release *and* name none of the three conversation capabilities; the migration backfills exactly that
complement with a Postgres array-overlap test
(`custom/db/migrate/20261011180000_add_conversation_scope_enforced_to_custom_roles.rb:31-41`). A `false` row
resolves to `:base`, not `:none` (`capability_scope.rb:117,137`). Editing the *conversation subset* of a set's
permissions flips the row to enforced, permanently and one-way
(`custom/app/models/custom_role.rb:53,98-111`); editing a non-conversation capability does not.

## 2. Surfaces and routes

| Surface | Path / endpoint | Code |
|---|---|---|
| Custom Roles settings page | `/accounts/:id/settings/custom-roles/list`, route `custom_roles_list` | `app/javascript/dashboard/routes/dashboard/settings/customRoles/customRole.routes.js:10-27`; page `.../customRoles/Index.vue` |
| Sidebar entry | Settings → Custom Roles (`i-lucide-shield-check`) | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:836-849` |
| Add/edit modal | `CustomRoleModal.vue` | `.../customRoles/component/CustomRoleModal.vue` |
| Plan notice | `CustomRolePaywall.vue` | `.../customRoles/component/CustomRolePaywall.vue:13-27` |
| Roles API | `GET/POST/PATCH/DELETE /api/v1/accounts/:id/custom_roles[/:id]` | `config/routes.rb:100`; `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:13-40` |
| Attach/detach a set | `POST/PATCH /api/v1/accounts/:id/agents[/:id]` with `agent[custom_role_id]` | `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:19-83`; UI `.../settings/agents/EditAgent.vue:88-137` |
| Role shown to the client | `permissions` + `custom_role_id` + `custom_role{id,name}` per membership | `app/views/api/v1/models/_user.json.jbuilder:33-41`; `custom/app/views/api/v1/models/_account_user.json.jbuilder:13-19` |
| Role payload for the roles table | `{id,name,description,permissions}` | `custom/app/views/api/v1/accounts/custom_roles/_custom_role.json.jbuilder:3-6` |

Enforcement sockets (no route of their own, but they are where the permissions bite):

| Socket | Role | Code |
|---|---|---|
| Conversation list / meta / filter / contact panels / bulk actions | capability narrowing after the inbox ceiling | `custom/app/services/custom/conversations/permission_filter_service.rb:20-22` over `app/services/conversations/permission_filter_service.rb:11-23` |
| Conversation record (and everything hanging off it: messages, attachments, labels, participants, assignments, drafts, transcript, macros) | ceiling + capability | `custom/app/policies/custom/conversation_policy.rb:40-41` over `app/policies/conversation_policy.rb:10-12` |
| Global search (`/search`, `/search/messages`) | capability narrowing, independent of the inbox-skip | `custom/app/services/custom/search_service.rb:17-35` |
| Unread counts | mode selection delegated to the one definition | `custom/app/services/custom/conversations/unread_counts/counter.rb:26-28` |
| Inbox/Team ceiling, as a record predicate **and** a relation | `Conversations::AccessCeiling` | `custom/app/services/conversations/access_ceiling.rb:49-69` |
| Notification feed, counts, websocket badge, by-id routes, delete-all | ceiling ∩ capability, plus a closed actor-type allow-list | `custom/app/services/notifications/conversation_visibility.rb`; `custom/app/finders/custom/notification_finder.rb:43-46`; `custom/app/controllers/custom/api/v1/accounts/notifications_controller.rb:48-67` |

## 3. User-visible states

**Custom Roles page.**
- *Not entitled* — `CustomRolePaywall` renders in place of the table and the "Add custom role" button is
  disabled; `openAddModal` also returns early (`Index.vue:70-75,105,174,182`). The sidebar entry is absent
  entirely, because `isAllowed` resolves the route's `featureFlag: CUSTOM_ROLES` meta
  (`Sidebar.vue:840-848`; `customRole.routes.js:23`).
- *Not an administrator* — the route's `permissions: ['administrator']` fails `routeIsAccessibleFor` and the
  router redirects to the member's default page (`customRole.routes.js:24`;
  `app/javascript/dashboard/helper/routeHelpers.js:14-51`).
- *Loading* — three skeleton rows, "Fetching custom roles..." (`Index.vue:189-191`).
- *Empty* — "There are no custom roles available in this account." (`Index.vue:154,198`).
- *Search with no match* — "No custom roles found matching your search" (`Index.vue:197`).
- *Populated* — sortable-by-name table of name / description / permissions / actions (`Index.vue:89-96,192`).

**Agent edit.** The role selector is two built-ins plus one option per custom role; choosing a custom role sends
`custom_role_id` only, choosing a built-in sends `role` plus an explicit `custom_role_id: null`
(`EditAgent.vue:74-95,131-136`). When the account is unentitled the roles list fetch is refused, so only the two
built-ins appear.

**Conversation inbox, as a custom-role holder.** The sidebar list is filtered client-side by `applyRoleFilter`
(`app/javascript/dashboard/store/modules/conversations/helpers.js:74-108`) and the assignee tabs by
`ASSIGNEE_TYPE_TAB_PERMISSIONS` (`constants/permissions.js:38-59`): `unassigned` needs `conversation_manage` or
`conversation_unassigned_manage`, `all` needs `conversation_manage` or `conversation_participating_manage`.
A set with **no** conversation capability puts the holder in `applyRoleFilter`'s final `return false` — an empty
inbox — and the conversation routes are not in their permission list, so the router redirects them away
(`conversation.routes.js:6-12,51`).

**Support cases.** Any custom-role holder can open the Tickets screen (route permits the `custom_role` marker,
`app/javascript/dashboard/routes/dashboard/tickets/tickets.routes.js:16`); without `support_ticket_manage` the
list contains only cases assigned to them, assigned to one of their teams, or that they opened
(`custom/app/policies/support/ticket_policy.rb:37-43`).

**Commerce order actions.** Each action is returned with `available: false, reason: 'permission_denied'` when the
policy refuses, so the menu renders the action greyed with a reason rather than hiding it
(`custom/app/services/commerce/order_actions.rb:130`).

## 4. Errors and validation messages

Server-side, all exact strings:

| Message | Key | `file:line` | Status |
|---|---|---|---|
| `These are not permissions this product defines: %{permissions}.` | `errors.custom_roles.unknown_permissions` | `config/locales/en.yml:227`, raised at `custom/app/models/custom_role.rb:118` | 422 |
| `Custom role not found` | `errors.custom_roles.not_found` | `config/locales/en.yml:228`, raised at `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:82` | 404 |
| `A member cannot be an administrator and hold a permission set at the same time. Choose one.` | `errors.custom_roles.administrator_conflict` | `config/locales/en.yml:229`, raised at `agents_controller.rb:79` | 422 |
| `You are not authorized to do this action` | hardcoded | `app/controllers/concerns/request_exception_handler.rb:26,38-40` | **401** (not 403) |
| `Support tickets are not enabled for this account.` | `errors.tickets.feature_disabled` | `config/locales/en.yml:248`; `custom/app/controllers/api/v1/accounts/support/base_controller.rb:20` | 404 |

`name` presence and `permissions` presence are validated (`custom/app/models/custom_role.rb:64-67`) and surface
as Rails' default `"Name can't be blank"` / `"Permissions can't be blank"` through `create!`/`update!` →
`render_could_not_create_error` (422). **`description` is not validated server-side.**

Client-side (`CustomRoleModal.vue:45-49` via Vuelidate):
- `Name is required.` / min length 2 — `CUSTOM_ROLE.FORM.NAME.ERROR`
- `Description is required.` — `CUSTOM_ROLE.FORM.DESCRIPTION.ERROR` (**no server counterpart**)
- `Permissions are required.` — `CUSTOM_ROLE.FORM.PERMISSIONS.ERROR`
- generic fallback `Could not connect to Woot server. Please try again.` — `CUSTOM_ROLE.FORM.API.ERROR_MESSAGE`
  (`CustomRoleModal.vue:143-144`), and the same string for delete (`Index.vue:137`)

Plan notice: `Custom roles are not included in your current plan.` + `View plans` —
`CUSTOM_ROLE.PLAN_NOTICE.{TEXT,VIEW_PLANS}` (`CustomRolePaywall.vue:17,25`).

Permission labels shown in the modal (`CUSTOM_ROLE.PERMISSIONS.*`, keyed by the uppercased string,
`CustomRoleModal.vue:88`) are the only place the product names a capability to a user. Note
`CONVERSATION_PARTICIPATING_MANAGE` reads "Manage participating conversations and those assigned to them" while
the code grants `assignee_id = me` only.

## 5. Failure paths

1. **`report_manage` grants nothing.** The Reports and Analytics routes accept it
   (`reports.routes.js:28`; `analytics.routes.js:18`), but every server read authorizes `ReportPolicy#view?`,
   which is `account_user.administrator?` with no overlay in `custom/`
   (`app/policies/report_policy.rb:2-4`; `app/controllers/api/v2/accounts/{reports,live_reports,summary_reports}_controller.rb`;
   `custom/app/controllers/api/v1/accounts/analytics_controller.rb:107-109`). A holder reaches the page and every
   panel returns 401 with "You are not authorized to do this action". The route comment at
   `analytics.routes.js:5-6` states the administrator-only server rule and ships the permission anyway. **This is
   the single largest permission defect in scope.**
2. **Entitlement lapse diverges client from server.** `Custom::AccountUser#permissions` falls back to
   `['agent']` when `Billing::Entitlements.allowed?(account, 'custom_roles')` is false
   (`custom/app/models/custom/account_user.rb:57-62`), and `CapabilityScope` keys off the marker in that list, so
   the server treats the holder as a plain agent — `:base` (`capability_scope.rb:126-128`). But the jbuilder still
   emits `custom_role_id` (`custom/app/views/api/v1/models/_account_user.json.jbuilder:13`) and
   `getUserRole` returns `'custom_role'` whenever that id is present
   (`app/javascript/dashboard/helper/permissionsHelper.js:19-26`). So after a lapse `applyRoleFilter` falls through
   to `return false` and the holder's inbox renders **empty** while the API would serve every conversation in
   their inboxes. The comment at `custom/app/models/custom/account_user.rb:12-14` claims the marker is what
   `getUserRole` reads; it is not.
3. **Grandfathered sets render empty too.** A `conversation_scope_enforced = false` set gets `:base` on the
   server (`capability_scope.rb:117`) but the browser has no notion of the column and returns `false` for every
   conversation (`helpers.js:107`). The whole point of the grandfather rule — holders keep the access they had —
   is invisible in the UI.
4. **Bot-assigned conversations.** The server's `:unassigned_and_mine` excludes a conversation with
   `assignee_agent_bot_id` set (`capability_scope.rb:51-52`); the client only checks `conversation.meta.assignee`
   (`helpers.js:94-95`), so it shows a bot-assigned conversation the server would withhold.
5. **Attaching a set is not entitlement-gated.** `CustomRolesController` refuses all five actions when the
   account lacks `custom_roles` (`custom_roles_controller.rb:52-54`), but
   `Custom::Api::V1::Accounts::AgentsController#validate_custom_role` only checks ownership, not entitlement
   (`agents_controller.rb:74-83`). An unentitled account can still attach an existing set over the API; it simply
   grants nothing. Benign, but it contradicts the AR article's claim (see §10).
6. **A deleted set silently widens its holders.** `before_destroy :detach_memberships` clears each attachment one
   row at a time so the visibility-cache invalidation runs (`custom/app/models/custom_role.rb:81-85`), and each
   holder reverts to the plain `agent` baseline — which is **wider** for conversations than a narrow set was. No
   warning anywhere says so; the delete modal only asks "Are you sure to delete <name>?" (`Index.vue:224-233`).
7. **Help Center is reachable and then refuses.** The helpcenter routes still accept `agent` and
   `knowledge_base_manage` (`helpcenter.routes.js:27,98,107`) while every portal/category/article policy method is
   unconditionally `false` (`custom/app/policies/custom/portal_policy.rb:25-34`). `help_center` ships
   `enabled: false` and is not marked deprecated (`config/features.yml:44-46`), so an account that has it on gets
   a navigable, uniformly-401 section.
8. **No 403 anywhere.** `Pundit::NotAuthorizedError` renders **401** (`request_exception_handler.rb:24-26,38-40`).
   Cross-account and unauthorized ids deliberately render **404** instead
   (`custom_roles_controller.rb:7-8`; `custom/app/controllers/custom/api/v1/accounts/notifications_controller.rb:31-34`;
   `custom/app/policies/platform_support/ticket_policy.rb:20-23`). Any troubleshooting article that says "403" or
   "Forbidden" is wrong.
9. **Stale notifications survive revocation in an open tab.** Authorization is read-time only, so a row already
   in the browser store keeps rendering — including its message body — until a filter change or reload
   (`docs/pre-deploy/05-notification-authorization-closure.md` §8.1).

## 6. Permissions — the full gating map

**Administrator-only, with no capability that can substitute** (each `account_user.administrator?`):
roles themselves (`custom_roles_controller.rb:14`), agents/invites (`app/policies/user_policy.rb:6-20`),
inboxes and every channel operation (`app/policies/inbox_policy.rb:51-105`), teams (`app/policies/team_policy.rb:6-19`),
reports and analytics (`app/policies/report_policy.rb:2-4`), contact import/export/destroy
(`app/policies/contact_policy.rb:10-21,55-57`), commerce store connect/rotate/disable
(`custom/app/policies/commerce/store_policy.rb:3-17`), WhatsApp template management
(`custom/app/policies/whatsapp/message_template_policy.rb:7-33`), support SLA policies
(`custom/app/controllers/api/v1/accounts/support/sla_policies_controller.rb:11`), commerce cancel and refund
(`custom/app/policies/commerce/action_policy.rb:23-28` — explicitly never delegable),
conversation destroy (`app/policies/conversation_policy.rb:6-8`), portal analytics config
(`app/controllers/api/v1/accounts/portals_controller.rb:107-109`).

**The three access limits, and how they compose.** Conversation access is an **intersection**, never a union:

```
reachable conversations = ACCESS CEILING (inbox OR team)  ∩  CAPABILITY SCOPE (the three conversation_*)
```

- *Ceiling*: `Conversations::AccessCeiling` — administrator or `AgentBot` is unrestricted; otherwise a
  conversation in an inbox the user belongs to (`inbox_members`) **or** whose `team_id` is a team they belong to
  (`team_members`), both scoped to the account (`custom/app/services/conversations/access_ceiling.rb:49-69,83-97`).
  **Being the assignee grants nothing on its own, and neither does being a participant** — `ConversationPolicy`
  defines `assigned_to_user?` and `participant?` and calls neither (`app/policies/conversation_policy.rb:38-44`;
  `access_ceiling.rb:25-28`).
- *Capability*: `Conversations::CapabilityScope`, narrowing only, never widening (`capability_scope.rb:25-29,77-84`).
- *A documented asymmetry*: the **list** ceiling is inbox-membership only
  (`app/services/conversations/permission_filter_service.rb:22`), while the **record** ceiling is inbox **or**
  team. A team member with no inbox membership can open by id a conversation the list will never return — asserted
  as intended (`custom/app/policies/custom/conversation_policy.rb:12-15`;
  `docs/pre-deploy/05-notification-authorization-closure.md` §8.6).

**Notification-feed ceiling.** `Notifications::ConversationVisibility` composes the two layers above and
translates them onto `notifications`, with a **closed positive allow-list** of two primary actor types —
`Conversation` and `PlatformSupport::Ticket` — refused for everyone including administrators if a type is not
named (`custom/app/services/notifications/conversation_visibility.rb:100,134-167`). `unrestricted?` requires both
layers to impose nothing, so a plain agent and a `conversation_manage` holder are both narrowed by the ceiling
(`conversation_visibility.rb:121-123`). Platform-support notifications have their own branch authorized by
`PlatformSupport::TicketPolicy::Scope`, which applies its own account predicate and gives an administrator their
account's tickets and an agent only the ones they reported — **a custom role grants nothing here, by decision**
(`custom/app/policies/platform_support/ticket_policy.rb:8-13,36-51`). Four consumers share the one definition:
the feed/counts/websocket badge (`custom/app/finders/custom/notification_finder.rb:43-46`), the by-id member
routes and `read_all` (`custom/app/controllers/custom/api/v1/accounts/notifications_controller.rb:48-67`), the
ActionCable listener and the delete-all job.

**Plan-entitlement ceiling.** `Billing::Entitlements.allowed?` is the one answer, in precedence order: system
feature → account override → the account's own feature bit (which is where `Billing::FeatureSync` writes what the
plan bought) (`custom/app/services/billing/entitlements.rb:28-36`). The ceiling is applied at exactly one choke
point — `Custom::AccountUser#permissions` (`custom/app/models/custom/account_user.rb:57-62`) — so:
effective permission = installation availability **AND** account entitlement **AND** member/role permission. A
lapse deletes no row and detaches no membership; the set starts granting again when the entitlement returns
(`custom/app/models/custom/account_user.rb:29-33`). Capabilities with their own feature gate keep it on top:
`lynomia_support_tickets` 404s the whole support surface
(`custom/app/controllers/api/v1/accounts/support/base_controller.rb:7,17-21`) and `lynomia_commerce` gates
commerce. `custom_roles` itself is `enabled: false` in `config/features.yml:155-157` and — having had its
`premium: true` key removed — **is now in `BillingPlan.assignable_features`**, i.e. a plan can sell it
(`custom/app/models/billing_plan.rb:41-47`, and the removal is explained at `config/features.yml:149-154`).

## 7. Contextual-help opportunities

| UI location | The question a user has there | Registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `customRoles/Index.vue:161-163` ("Learn more", `feature-name="custom_roles"`) | what can a custom role do? | `permissions` → `roles-and-permissions` | **yes**, via `featureHelper.js:17` |
| `CustomRoleModal.vue:74-91` (the permission checkbox list) | what does each of these seven actually grant? | `permissions` | yes — but the article's table lists only six (§9) |
| `CustomRolePaywall.vue:17` (plan notice) | which plan includes custom roles? | none | **no** — needs a plans/entitlements key |
| `EditAgent.vue:176-178` (role selector) | administrator vs agent vs a named set? | `permissions` | yes, but the selector carries no link |
| `Index.vue:224-233` (delete confirmation) | what happens to the people holding this role? | none | **no** — the widening in §5.6 is undocumented |
| Empty inbox for a holder with no conversation capability (`helpers.js:107`) | why is my inbox empty? | `permissions` or a troubleshooting key | partially — the article's "If it does not work" covers it, nothing links there |
| Reports/Analytics 401 for a `report_manage` holder (`analytics.routes.js:18`) | why am I told I am not authorized? | none | **no** — and the right fix is code, not a doc |
| Commerce action greyed with `permission_denied` (`order_actions.rb:130`) | who can refund? | `commerceStorePermissions` (`commerce-keys-cannot-do-that`) | yes, but that article is about store API keys, not agent roles — wrong destination for this reason code |
| Tickets list showing only own/team cases (`ticket_policy.rb:37-43`) | why can I not see my colleague's case? | none | **no** support-cases article in the corpus |
| Notification feed narrowing (`notification_finder.rb:43-46`) | why did a notification disappear? | none | **no** |

## 8. Current documentation coverage

- `custom/db/documentation/en/workspace/roles-and-permissions.md` (section `workspace`, position 30,
  `custom/db/documentation/manifest.yml:87-95`) is the primary article and is genuinely good: it leads with
  "exactly one role", gets the administrator/agent distinction right, states the widest-wins hierarchy
  (`:39`), states that a set with no conversation permission sees nothing (`:39-41`), states that refunds and
  cancellations are never delegable (`:43-45`), and has an explicit "What is not on the list" section (`:51-59`)
  that is accurate against §6 above.
- `custom/db/documentation/ar/workspace/roles-and-permissions.md` is a full parallel translation, not a stub,
  with the same structure and one extra claim (see §10).
- `custom/db/documentation/en/getting-started/invite-your-team.md:23-45` carries a second, shorter copy of the
  permission list and the refund caveat.
- `custom/db/documentation/en/workspace/teams-and-agents.md:31,85,95` correctly separates team membership from
  access ("Team membership grants no access") and links to the roles article.
- `custom/db/documentation/en/workspace/your-own-help-centre.md` is the referenced explanation for the retired
  `knowledge_base_manage`.

## 9. Missing or stale documentation

1. **`support_ticket_manage` is absent from both permission lists.** The EN article says "These are the six
   options" and tables six (`roles-and-permissions.md:27-37`); `invite-your-team.md:31-38` lists the same six.
   The product offers seven (`constants/permissions.js:4-12`) and the seventh is labelled "Manage every support
   case in the account". A reader planning a support-lead role cannot find it. Same omission in AR
   (`ar/.../roles-and-permissions.md:27-37`, "الخيارات الستّة").
2. **No article covers the inbox/team ceiling as an intersection.** Both articles say inbox membership matters,
   but neither says that team membership *also* grants record access, nor that the conversation **list** applies
   inbox membership only while opening by id applies inbox-or-team. A user who hands a conversation to a team
   and then finds the recipient cannot see it in their list has no article to read.
3. **No article on the notification feed's access rule.** Notifications disappear when access changes, and an
   open tab keeps showing stale ones until reload (§5.9). Nothing in the corpus mentions either.
4. **No support-cases article at all**, so `support_ticket_manage`, the own/team/reporter default scope and the
   administrator-only SLA policies are entirely undocumented.
5. **Nothing documents what deleting a role does to its holders** (§5.6) — they silently become plain agents,
   which for conversations is *wider*.
6. **Nothing documents the grandfather rule.** A pre-existing commerce-only or support-only set still grants
   full conversation access on the server, and the moment an administrator edits its conversation checkboxes that
   stops. This is a real behaviour change an administrator can trigger by accident and no article warns them.

## 10. Doc claims not proven by code

| Claim | Where the doc says it | What the code says |
|---|---|---|
| "the **six** options, named as the product names them" / "The permission list is fixed at the six entries above" | `en/workspace/roles-and-permissions.md:28,92`; `ar/...:28,90` | Seven are offered, eight validate (`custom/app/models/custom_role.rb:19-28`; `constants/permissions.js:4-12`) — **wrong** |
| "Manage reports \| reports, including satisfaction responses" | `en/workspace/roles-and-permissions.md:36`; `ar/...:36`; `invite-your-team.md:35` | `report_manage` gates nothing; `ReportPolicy#view?` is administrator-only (`app/policies/report_policy.rb:2-4`) — **wrong** |
| "Reports \| yes \| no" for administrator vs agent | `roles-and-permissions.md:19` | **confirmed** (same citation) |
| "Manage participating conversations and those assigned to them \| their own, plus ones they are a **participant** in" | `en/.../roles-and-permissions.md:34`; `ar/...:34`; `invite-your-team.md:33` | `:mine` is `assignee_id = user.id` only; `ConversationPolicy#participant?` is defined and never called (`capability_scope.rb:81,100`; `app/policies/conversation_policy.rb:42-44`) — **wrong** |
| "Manage all conversations \| every conversation in the inboxes they are a collaborator on" | `roles-and-permissions.md:32` | **confirmed**, and incomplete: team-assigned conversations are also reachable by id (`access_ceiling.rb:55-57`) |
| "granting all three is the same as granting the first" | `roles-and-permissions.md:39` | **confirmed** (`capability_scope.rb:113-115`); the modal also auto-ticks the other two (`CustomRoleModal.vue:77-86`) |
| "A custom role with **no** conversation permission sees no conversations at all" | `roles-and-permissions.md:40-41` | **confirmed for new/edited sets only**; a grandfathered row gets `:base` (`capability_scope.rb:117`) — incomplete |
| "A role created before that change keeps a Manage knowledge base entry on its record, where it now grants nothing" | `roles-and-permissions.md:47-49` | **confirmed** (`custom/app/policies/custom/{portal,category,article}_policy.rb`) |
| "Refunds and cancellations are administrator-only and cannot be granted to any custom role" | `roles-and-permissions.md:43-45,93`; `invite-your-team.md:40-41,82` | **confirmed** (`custom/app/policies/commerce/action_policy.rb:23-28`) |
| "A custom role replaces the agent role; it is not added on top of administrator" | `roles-and-permissions.md:90-91` | **confirmed** (`agents_controller.rb:55-57,79`) |
| "Permissions are account-wide, not per inbox" | `roles-and-permissions.md:94-95` | **confirmed** (`capability_scope.rb` has no inbox dimension) |
| "on a plan without them the Custom Roles page is not shown" | `roles-and-permissions.md:63-64` | **confirmed** for the sidebar/route (`Sidebar.vue:840-848`; `customRole.routes.js:23`), but the page itself renders a paywall notice rather than nothing if reached (`Index.vue:182`) — imprecise |
| AR only: "عند تخفيض الخطة يمكن إزالة دور مخصص مُسنَد لكن لا يمكن إسناده مجدداً" ("on downgrade an assigned custom role can be removed but cannot be reassigned") | `ar/workspace/roles-and-permissions.md:92` | `validate_custom_role` checks ownership only, not entitlement, so attaching still succeeds over the API (`agents_controller.rb:74-83`); the stored set and attachment are deliberately left untouched by a lapse (`custom/app/models/custom/account_user.rb:29-33`) — **unverified at best, and the EN article makes no such claim (EN/AR divergence)** |
| AR admin table adds rows for billing and canned responses/macros that EN omits | `ar/...:19-20` vs `en/...:14-19` | both are correct against the code; a **parity** difference, not an error |

Repository documents that are now stale in this area, for the orchestrator's awareness (not corpus):
`docs/pre-deploy/04-decisions-implemented.md:148-155` states that `custom_roles` is `premium: true`, is not in
`BillingPlan.assignable_features` and that "no plan sells it". The `premium` key has since been removed
(`config/features.yml:149-157`), so the capability **is** assignable to a plan
(`custom/app/models/billing_plan.rb:41-47`). `docs/pre-deploy/02-product-decisions.md:61-120` describes the
pre-DECISION-1 world (capabilities with no server effect) and must not be read as current.
