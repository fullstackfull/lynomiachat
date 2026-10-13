---
agent: 057
scope: Corpus audit of the `workspace` section (inboxes, teams and agents, roles and permissions, documentation and support) - verdicts, accuracy against code, permission claims checked in both directions, EN/AR parity
confidence: high
---

# 057 - Corpus audit: `workspace`

Read-only. I read all eight files (4 EN, 4 AR) in full, then traced every sentence that makes a permission, entitlement
or access claim to the policy, controller guard, capability check or plan ceiling that does - or does not - enforce
it. I did not run the app, so UI behaviour is from source, not from a browser. Where another agent's report already
holds the same finding I say so; every citation below is one I opened myself.

Two facts frame everything that follows.

1. **The section is not four articles about inboxes, teams and roles.** Three are. The fourth
   (`your-own-help-centre`, titled "Documentation and support") is about where Lynomia's own documentation lives and
   has no workspace subject matter.
2. **The roles article predates the enforcement it describes.** The four EN and four AR files were last touched on
   2026-10-06 (`3a5efd3a`, `60e6cda8`, `b3fe0b38`). The commits that made the three `conversation_*` permissions real
   server-side authorization and added the plan-entitlement ceiling landed on 2026-10-11 and 2026-10-12 (`ff15af0a`,
   `4c15603d`, `5954cb3f`) and changed no corpus file. Before them those permissions were a browser filter only
   (`custom/db/migrate/20261011180000_add_conversation_scope_enforced_to_custom_roles.rb:3-8`). Sentences in the roles
   article that hold today were written about the browser.

Word counts are body-only, whitespace tokens containing a word character (so table pipes do not inflate them).
Agents 061 and 062 report 853 / 910 / 893 / 535 EN and 826 / 767 / 804 / 426 AR for the same files; theirs count every
whitespace token including table pipes. The ranking is the same.

## 1. Inventory

| key | EN file | AR file | title (EN / AR) | position | EN words | AR words | links to it in product |
|---|---|---|---|---|---|---|---|
| `set-up-an-inbox` | `custom/db/documentation/en/workspace/set-up-an-inbox.md` | `custom/db/documentation/ar/workspace/set-up-an-inbox.md` | Set up an inbox / إعداد قناة تواصل | 10 | 811 | 753 | `inboxes` (`documentationLinks.js:80`; `featureHelper.js:19`) |
| `teams-and-agents` | `.../en/workspace/teams-and-agents.md` | `.../ar/workspace/teams-and-agents.md` | Teams and agents / الفرق ووكلاء الدعم | 20 | 867 | 722 | `teams` (`documentationLinks.js:81`), reused for `agents` and `team_management` (`featureHelper.js:8,29`) |
| `roles-and-permissions` | `.../en/workspace/roles-and-permissions.md` | `.../ar/workspace/roles-and-permissions.md` | Roles and permissions / الأدوار والصلاحيات | 30 | 813 | 715 | `permissions` (`documentationLinks.js:82`; `featureHelper.js:17`) |
| `your-own-help-centre` | `.../en/workspace/your-own-help-centre.md` | `.../ar/workspace/your-own-help-centre.md` | Documentation and support / التوثيق والدعم | 40 | 491 | 384 | none |

The section is `position: 80` in `custom/db/documentation/manifest.yml:87-95`. EN/AR presence is exact (4 + 4). The
fourth article's slug (`your-own-help-centre`) describes a product that was removed; the slug is a contract (it is the
`doc_key`, `content_seeder.rb:107`, and the target of two links in the roles article), so renaming it needs a redirect.

## 2. Per-article verdict

| key | verdict | one-sentence reason | evidence |
|---|---|---|---|
| `set-up-an-inbox` | **REWRITE**, then **SPLIT** business hours and greeting into their own article | Two statements are false (Voice and WhatsApp calling are offered "on your account"; business hours are "not available anywhere else"), "nine always offered" is imprecise, and despite the title it contains no procedure. | I-01, I-02, I-03 |
| `teams-and-agents` | **REWRITE** (targeted) + **EXPAND** | The assignment mechanics are accurate; the access model it states in two places ("a team gives nobody anything", "team membership grants no access") is contradicted by the record-level policy, and availability, which the whole article leans on ("online"), is explained nowhere. | A3, B8, T-02 |
| `roles-and-permissions` | **REWRITE** + **EXPAND** | It names six permissions where the product offers seven, describes `report_manage` as working when the server refuses it, describes "participating" as including participants when it means assigned-to-me only, and omits the entitlement, grandfathering and deletion behaviour that change what a role does. | A1, A2, A4, A5, A6, A7, B1-B6 |
| `your-own-help-centre` | **RELOCATE** (to `troubleshooting`, or **MERGE** into `contact-lynomia-support`) + **REWRITE** | It is not about the workspace, its slug is stale, it omits the in-product support desk the sidebar lists first, and it claims a canned-response variable that does not exist. | H-01 to H-04 |

Nothing here is a RETIRE: every one of the four answers a question a stuck user has.

## 3. Accuracy against the product

### 3.1 Every permission and access claim, checked

`confirmed | wrong | unverifiable`, plus `incomplete` where the sentence is true but leaves out the part that matters.
Doc cites are EN file:line; the AR file makes the same claim at the same structural position unless 6 says otherwise.

| # | Claim (doc) | Enforcement (code) | Verdict |
|---|---|---|---|
| 1 | One role per person; a custom role replaces agent and is never layered on administrator (`roles:8-10,90-91`) | role enum `app/models/account_user.rb:34`; attaching a set forces `role = :agent` `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:55-56`; administrator + set in one request is refused `:79` | confirmed |
| 2 | Administrator sees every conversation without being a collaborator (`roles:17,21-23`) | `app/policies/conversation_policy.rb:10-12`; list `app/services/conversations/permission_filter_service.rb:11-13` | confirmed |
| 3 | An agent sees only inboxes they collaborate on; "only inbox membership grants access" (`roles:17,21-23`; `teams:19`) | list is inbox-only `permission_filter_service.rb:22`, but the record policy is inbox **or team** `app/policies/conversation_policy.rb:16-18,32-36`, `custom/app/services/conversations/access_ceiling.rb:55-57,77-81` | **wrong** (A3) |
| 4 | Reports: administrator yes, agent no (`roles:19`) | `app/policies/report_policy.rb:2-4` | confirmed |
| 5 | Settings and billing: administrator all, agent none (`roles:16`) | billing admin-only `custom/app/controllers/api/v1/accounts/billing_controller.rb:33`; but an agent's Settings landing page is Canned Responses `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:36-52`, `canned/canned.routes.js:27` | incomplete (agents have a Settings area: canned responses, macros, profile) |
| 6 | Contacts, canned responses, macros: yes for both (`roles:18`) | contacts `app/policies/contact_policy.rb:2-4,31-33,43-49`; canned responses have no policy at all `app/controllers/api/v1/accounts/canned_responses_controller.rb:1-22`; macros `app/policies/macro_policy.rb:2-30` | confirmed, understated (B6, B7) |
| 7 | "The exact six permissions" / "fixed at the six entries" (`roles:3,28,92`) | client offers seven `app/javascript/dashboard/constants/permissions.js:4-12`; server validates eight `custom/app/models/custom_role.rb:19-28` | **wrong** (A5) |
| 8 | Manage all conversations = every conversation in inboxes they collaborate on (`roles:32`) | `:base` `custom/app/services/conversations/capability_scope.rb:113`; ceiling still inbox or team | confirmed, incomplete (A3) |
| 9 | Unassigned + own (`roles:33`) | `capability_scope.rb:51-52,80,114` | confirmed; "unassigned" means no human **and** no bot assignee `:48-52` (B5) |
| 10 | Participating = "their own, plus ones they are a participant in" (`roles:34`; `invite-your-team:35`) | `:mine` is `assignee_id = user.id` only `capability_scope.rb:81,99-101`; browser identical `app/javascript/dashboard/store/modules/conversations/helpers.js:112-114`; `participant?` is defined and never called `conversation_policy.rb:42-44`, `access_ceiling.rb:25-28` | **wrong** (A2) |
| 11 | Manage contacts = "contacts" (`roles:35`) | server effect is contact merge and identity linking only `custom/app/policies/custom/contact_policy.rb:17-27`, `.../actions/contact_merges_controller.rb:7-10`, `.../contacts/identities_controller.rb:22,32` | **wrong / misleading** (A6) |
| 12 | Manage reports = "reports, including satisfaction responses" (`roles:36`) | nothing: `report_policy.rb:2-4`, `csat_survey_response_policy.rb:2-12`, no `Custom::ReportPolicy` exists | **wrong** (A1) |
| 13 | Manage store orders = status changes and resending store emails; cancel and refund never delegable (`roles:37,43-45,93,113-114`) | `custom/app/policies/commerce/action_policy.rb:9-12,19-29` | confirmed (B12 for what it omits) |
| 14 | The three conversation permissions are a hierarchy; all three = the first (`roles:39-40`) | `capability_scope.rb:113-115`; the modal auto-ticks the other two `CustomRoleModal.vue:74-86` | confirmed |
| 15 | No conversation permission = no conversations at all (`roles:40-41,107-108`) | `capability_scope.rb:117,137`; grandfathered sets get `:base` | incomplete (A4) |
| 16 | Legacy "Manage knowledge base" grants nothing (`roles:47-49`; `help:49-52`) | `custom/app/policies/custom/portal_policy.rb:25-34`, `article_policy.rb:6-14`, `category_policy.rb:3-11` | confirmed on the server; client residue (H-04) |
| 17 | The "not on the list" items are administrator-only, no middle ground (`roles:51-59`; `inbox:71-72`) | see 3.2 per-item table | mostly confirmed; **three exceptions** (A7) |
| 18 | Custom roles are paid; without the plan the page is not shown (`roles:61-64`) | `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:52-54`; sidebar entry absent `Sidebar.vue:840-848`; direct URL shows a paywall page `Index.vue:70-75,105,174`; plan-sellable `custom/app/models/billing_plan.rb:36-47`, `config/features.yml:155-157` (default off) | confirmed (imprecise: the page exists behind a paywall) |
| 19 | Creating roles, changing anyone's role, managing agents are administrator jobs (`roles:84-86`) | `custom_roles_controller.rb:14`; `app/policies/user_policy.rb:6-20` | confirmed |
| 20 | Account-wide, not per inbox; no read-only role (`roles:94-96`) | `capability_scope.rb` has no inbox dimension; vocabulary `custom_role.rb:19-28` | confirmed |
| 21 | Steps: name and description, one conversation permission (`roles:66-72`) | description required in the client only `CustomRoleModal.vue:45-49`; server needs name and permissions `custom_role.rb:64-67`, permits description `custom_roles_controller.rb:56-58` | confirmed |
| 22 | Inbox settings are administrator-only; agents cannot open them (`inbox:25,69-72`) | writes `app/policies/inbox_policy.rb:51-61,63-105`; routes `settings/inbox/inbox.routes.js:32,60-101`; collaborators `app/controllers/api/v1/accounts/inbox_members_controller.rb:11,19,25`; secrets in the payload are administrator-only `app/views/api/v1/models/_inbox.json.jbuilder:48,82,145-146` | confirmed (agents can still read the inbox record, B11) |
| 23 | Administrators create/edit/delete teams and manage membership; any agent can assign a team to a conversation they can see (`teams:78-79`) | `app/policies/team_policy.rb:6-19`, `team_member_policy.rb:6-18`; `app/controllers/api/v1/accounts/conversations/assignments_controller.rb:36-43` over `conversations/base_controller.rb:6-9` | confirmed |
| 24 | Documentation, portal, category and article endpoints refuse a workspace (`help:16-18`) | every method `false`: `custom/app/policies/custom/portal_policy.rb:25-34` and siblings | confirmed |

### 3.2 The "administrator-only, no middle ground" list, item by item (`roles:55-59`)

| Item | Enforcement | Verdict |
|---|---|---|
| Inboxes and channels | `inbox_policy.rb:51-61`; OAuth channel base `app/controllers/api/v1/accounts/oauth_authorization_controller.rb:28-30`; Twilio and WhatsApp `.../channels/twilio_channels_controller.rb:5,17-19`, `.../whatsapp/authorizations_controller.rb:4-6`; **Facebook page registration has no guard** `app/controllers/api/v1/accounts/callbacks_controller.rb:4-24` | **one hole** (A7) |
| Campaigns | `app/policies/campaign_policy.rb:2-20` (every verb) | confirmed |
| WhatsApp templates | `custom/app/policies/whatsapp/message_template_policy.rb:7-33`; the per-inbox read that feeds the composer stays open to members (controller header, `custom/app/controllers/api/v1/accounts/whatsapp/message_templates_controller.rb:17-20`) | confirmed for management |
| Flows | `custom/app/controllers/api/v1/accounts/flows_controller.rb:22` -> `AgentBotPolicy#update?` `app/policies/agent_bot_policy.rb:6-8` | confirmed |
| Automation rules | `app/policies/automation_rule_policy.rb:2-26` (every verb including read) | confirmed |
| Audiences | shared: administrator only `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:6-23`; **personal audiences: any member** `app/policies/custom_filter_policy.rb:2-20` | **wrong as a blanket statement** (A7) |
| Labels | write `app/policies/label_policy.rb:6-20`; **agents may list** `:2-4` | confirmed for writes |
| Custom attributes | write `app/policies/custom_attribute_definition_policy.rb:10-20`; **agents may list and show** `:2-8` | confirmed for writes |
| Agents and roles | `user_policy.rb:6-20`; `custom_roles_controller.rb:14` | confirmed |
| Billing | `billing_controller.rb:33` (`entitlements` stays open to members with commercial particulars removed, `:28-31`) | confirmed |
| Audit logs | `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb:13` | confirmed |

### 3.3 Direction A - documented, but not enforced as documented

**A1 (major) - `report_manage` is advertised and inert.** `roles:36` (and AR:36, and `invite-your-team:35`) say the
permission grants "reports, including satisfaction responses". The server authorizes `:report, :view?` for the reports,
summary, live-reports and analytics controllers (`app/controllers/api/v2/accounts/reports_controller.rb:5,105-107`,
`summary_reports_controller.rb:2,29-31`, `live_reports_controller.rb:5,36-38`,
`custom/app/controllers/api/v1/accounts/analytics_controller.rb:107-109`) and `ReportPolicy#view?` is
`@account_user.administrator?` (`app/policies/report_policy.rb:2-4`); CSAT responses are administrator-only too
(`csat_survey_response_policy.rb:2-12`); drilldown re-checks administrator (`reports_controller.rb:55`). No overlay
exists: `custom/app/policies/custom/` holds only article, category, contact, conversation and portal, and
`ChatwootApp.extensions` is `['custom']` only (`lib/chatwoot_app.rb:42-44`). The routes accept the permission
(`settings/reports/reports.routes.js:28`, `analytics/analytics.routes.js:18`), so a holder reaches the page and every
panel returns 401. A reader who builds the report-only role the article implies gets a role whose one visible
permission does nothing. Corroborates 033 (PD-10).

**A2 (major) - "participating" does not include participants.** See row 10. The article, the product label
(`app/javascript/dashboard/i18n/locale/en/customRole.json:30`) and the `invite-your-team` copy all say "participating";
the code, the browser filter and the repo's own decision record agree it is assigned-to-me only
(`docs/pre-deploy/04-decisions-implemented.md:20`). Failure direction is narrower than documented, so it fails safe,
but a lead who adds participants to a conversation expecting the holder to see it will be wrong.

**A3 (major, security-relevant) - "team membership grants no access" is false at record level.** `teams:19` ("A team
gives nobody anything they did not already have") and `teams:85` ("Team membership grants no access. An agent still sees
nothing from an inbox they are not a collaborator on"; AR:19, 86). `ConversationPolicy#show?` is administrator, bot, or
`inbox_access? || team_access?` (`conversation_policy.rb:10-18,32-36`); `Custom::ConversationPolicy` only ever narrows
that (`custom/app/policies/custom/conversation_policy.rb:40-42,48-50`) and the repo records the asymmetry as intended
(`:12-15`; `docs/pre-deploy/04-decisions-implemented.md:31-35`). Consequences a reader cannot anticipate:

- A team member with no membership in the conversation's inbox can open that conversation by id and read its messages,
  because everything under a conversation hangs off `show?` (`custom/app/policies/custom/conversation_policy.rb:4-8`).
- They get its notifications (`app/builders/notification_builder.rb:31,42-55`).
- Support cases follow the same shape: a case assigned to one of your teams is visible to you
  (`custom/app/policies/support/ticket_policy.rb:40-43,54-56`).
- They do **not** see it in their conversation list or the team's sidebar view, because the list ceiling is inbox-only
  (`permission_filter_service.rb:22`; `app/finders/conversation_finder.rb:62-71,151-154` filters after it). So the surprise is
  quiet: the access exists, the listing does not show it.

The corpus contradicts itself: `conversations/work-in-the-inbox.md:93-94` says an agent can read "any conversation on a
channel they belong to, **or assigned to one of their teams**" - which is the code. An administrator who hands a
conversation to a team believing it exposes nothing beyond the inbox's collaborators is exposing it to the whole team.

**A4 (major) - "no conversation permission sees no conversations at all" has four exceptions** (`roles:39-41`;
`roles:107-108` repeats it as a troubleshooting cause):

1. *Grandfathered sets.* A set that predates 2026-10-11 and names none of the three resolves to `:base`, i.e. every
   conversation in its inboxes (`capability_scope.rb:117,137`; migration `20261011180000...:31-41`). Editing the
   conversation subset of such a set ends the exemption permanently (`custom_role.rb:50-53,98-111`). Nothing in the
   article tells an administrator either fact (B4).
2. *Realtime push.* `message_created` is broadcast to every inbox member and every administrator with the full message
   payload, ignoring the capability (`app/listeners/action_cable_listener.rb:41-47,202-206`;
   `app/models/message.rb:147-157` includes `content`). The repo lists this as a known gap deliberately left alone
   (`docs/pre-deploy/04-decisions-implemented.md:288-291`).
3. *Conversation creation.* `POST /conversations` is gated by inbox membership, not by a conversation capability
   (`app/controllers/api/v1/accounts/conversations_controller.rb:40-45,197`;
   `docs/pre-deploy/04-decisions-implemented.md:280-282`). A holder with no conversation permission can open a new
   conversation and send into an inbox they belong to.
4. *Entitlement lapse.* When the account stops being entitled to custom roles the holder silently becomes a plain agent,
   which for conversations is **wider** than a narrow set (`custom/app/models/custom/account_user.rb:57-62`;
   `capability_scope.rb:126-128`). Fails open by design; see B2.

**A5 (major) - six, not seven.** `roles:3,28,92` and AR:3,28,90 promise "the exact six permissions". The client offers
seven (`permissions.js:4-12`), labelled in `customRole.json:28-35`; the seventh, `support_ticket_manage`, "Manage every
support case in the account", is enforced (B1) and appears in neither language. A reader planning a support-lead role
cannot find it. Corroborates 033 and arbitration DC-19.

**A6 (minor to major) - `contact_manage` is not "contacts", and a custom role is not "an agent with a subset".**
`roles:35` and the worked example (`roles:76-82`: "Manage contacts ... so she can read the customer's record").
Server-side, every member - including a custom-role holder who lacks `contact_manage` - can list, read, search, create
and update contacts (`contact_policy.rb:2-4,23-33,43-49`); the only two things the permission opens are merging
(`custom/app/policies/custom/contact_policy.rb:17-19`, enforced at `.../actions/contact_merges_controller.rb:8`) and
linking extra identities (`:25-27`, `.../contacts/identities_controller.rb:22,32`). Omitting it hides the Contacts page
(`routes/dashboard/contacts/routes.js:9`) but does not stop the API. More generally `roles:27` ("an agent with a chosen
subset of permissions") describes the browser: `Custom::AccountUser#permissions` returns the set's list without
`'agent'` (`custom/app/models/custom/account_user.rb:61`), but the server's agent checks read the `role` column, which
stays `agent` (`label_policy.rb:2-4`, `custom_attribute_definition_policy.rb:2-8`, `canned_responses_controller.rb:1-22`).
At the API a custom-role holder keeps the agent baseline everywhere except the three conversation capabilities.

**A7 (major for the first, minor for the rest) - the administrator-only list has holes.**
(a) `CallbacksController` has no `check_authorization`, `authorize` or administrator check anywhere in the file, and no
global Pundit verification exists to catch it (`app/controllers/api/v1/accounts/callbacks_controller.rb:4-24,26-43,45-56`;
routes `config/routes.rb:85-92`; `app/controllers/api/base_controller.rb:12-22` defines only opt-in helpers, and no
controller in `app` or `custom` calls `verify_authorized`). Any account member can call
`register_facebook_page` and create a Facebook channel and inbox, which `InboxPolicy#create?` (`inbox_policy.rb:51-53`)
would refuse. Practical exploitation needs a Facebook page token, but the documented boundary ("a channel needs an
administrator", `roles:58-59`, `inbox:71-72`) is not the enforced one. Corroborates 041 (PD-03).
(b) Personal audiences: any member may create, edit and delete their own saved contact filters
(`custom_filter_policy.rb:2-20`; the administrator check applies only to shared ones,
`custom_filters_controller.rb:6-23`). (c) Read access to labels, custom attribute definitions, agent bots, teams, team
members and the agent list is open to every member (`label_policy.rb:2-4`, `custom_attribute_definition_policy.rb:2-8`,
`agent_bot_policy.rb:2-4,10-12`, `team_policy.rb:2-4,10-12`, `team_member_policy.rb:2-4`, `user_policy.rb:2-4`).

**A8 (minor, AR only) - "after a downgrade an assigned custom role can be removed but not reassigned"** (AR
`roles:62-63,92`; EN makes no such claim). The agents endpoint checks ownership of the set, not entitlement
(`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:74-83`), so an unentitled account can still attach
one over the API; it simply grants nothing. The UI cannot offer one only because the roles list endpoint refuses
(`custom_roles_controller.rb:52-54`; `settings/agents/Index.vue:57`). Corroborates 033, arbitration DC-20.

### 3.4 Direction B - enforced, but undocumented

| # | Severity | Enforced behaviour | Where | In the corpus? |
|---|---|---|---|---|
| B1 | major | `support_ticket_manage` lets an agent see **every** support case in the account; everyone else sees cases assigned to them, to one of their teams, or opened by them. The Support module is feature-gated (`lynomia_support_tickets`, 404 when off) | `custom/app/policies/support/ticket_policy.rb:7-15,24-26,37-43`; `custom/app/controllers/api/v1/accounts/support/base_controller.rb:7,17-21` | no article on in-account support cases exists; one table row in `troubleshooting/contact-lynomia-support.md:14` |
| B2 | major | Plan ceiling on every capability: if `custom_roles` stops being entitled, no row is deleted or detached, the holder reverts to the plain agent list (wider for conversations), and the set grants again the moment the entitlement returns | `custom/app/models/custom/account_user.rb:20-62`; `custom/app/services/billing/entitlements.rb:28-36` | no (EN); AR states something different (A8) |
| B3 | major | Deleting a custom role detaches every holder, one row at a time; each reverts to the agent baseline, which is wider for conversations than a narrow set | `custom_role.rb:38-49,81-85`; `custom_roles_controller.rb:37-40` | no |
| B4 | major | A set that predates 2026-10-11 and names no conversation permission is exempt from "none means none" until an administrator edits its conversation checkboxes; the edit is one-way | `custom_role.rb:50-53,98-111`; migration `20261011180000...:19-41` | no |
| B5 | minor | "Unassigned" means no human assignee **and** no bot assignee: conversations held by a flow or agent bot are invisible to `conversation_unassigned_manage` | `capability_scope.rb:48-52` | no |
| B6 | minor | Contact delete, import and export are administrator-only; merge and identity-linking need administrator or `contact_manage`. A plain agent cannot merge | `contact_policy.rb:10-21,55-57`; `custom/app/policies/custom/contact_policy.rb:17-27` | roles article silent; `contacts/contacts.md:94,96,127` is wrong on both (arbitration DC-01, DC-04) |
| B7 | minor | Canned responses are account-wide and writable and deletable by every member; global macros are administrator-only, personal macros are the author's | `canned_responses_controller.rb:1-22` (no policy); `macro_policy.rb:10-30` | roles says "yes / yes" only |
| B8 | minor | Setting a team auto-assigns whenever the team allows it, regardless of the inbox's own auto-assignment switch; and the picking step runs only when the assignee is blank after the "not a member" check, so an assignee who is a team member is kept | `app/models/concerns/assignment_handler.rb:12-29` | `teams:46-58` describes the order but not the switch independence; `inbox:84` presents the inbox switch as the control |
| B9 | minor | Plan ceilings on workspace objects: agent count, inbox count, and which channel types a plan sells (refused with "Your plan does not include the %{channel} channel") | `app/builders/agent_builder.rb:26`; `custom/app/models/billing/inbox_limit.rb:21-27,36-41`; `config/locales/en.yml:303` | agents: `invite-your-team.md:86` only; inboxes and channels: no |
| B10 | minor | The manual assignment endpoint accepts any account member, collaborator or not; only the UI list is restricted | `app/services/conversations/assignment_service.rb:49-51` vs `assignable_agents_controller.rb:7-14` | `teams:57-58` says such a member "cannot be chosen by hand" (true of the UI only; arbitration PD-06) |
| B11 | minor | Members can read inbox records and inbox member lists for their inboxes, and read all teams, team members and agents | `inbox_policy.rb:22-27`; `inbox_members_controller.rb:6`; `team_policy.rb:2-12`; `user_policy.rb:2-4` | no |
| B12 | minor | `commerce_order_manage` also covers `update_shipping`, and an action additionally needs the feature flag, the store's opt-in and write-capable credentials | `action_policy.rb:10-11`; `custom/app/controllers/api/v1/accounts/conversations/commerce/order_actions_controller.rb:32-34`; `custom/app/services/commerce/order_actions.rb:5-12` | `roles:43-45` names status and emails only |

### 3.5 The plan-entitlement ceiling, in one place

| Ceiling | Enforced at | Documented |
|---|---|---|
| `custom_roles` account flag (default off, plan-sellable) | API refuses all five role actions `custom_roles_controller.rb:52-54`; read-time bound on every capability `custom/app/models/custom/account_user.rb:57-62`; `features.yml:155-157`; `billing_plan.rb:36-47` | EN: "a paid capability", page absent. Not the lapse behaviour |
| Agent seats | `agent_builder.rb:26`; `agents_controller.rb:21-23,82` (402) | `invite-your-team:86` |
| Inbox count | `custom/app/models/billing/inbox_limit.rb:21-27` | no |
| Channel types per plan | `inbox_limit.rb:36-41` | no; `inbox:17` says nine are "always offered" |
| `lynomia_commerce` for order actions | `order_actions_controller.rb:32-34` | no |
| `lynomia_support_tickets` for cases | `support/base_controller.rb:7,17-21` | no |

One internal inconsistency worth the orchestrator's attention rather than the writers': the roles endpoint tests the raw
flag (`feature_enabled?`), while the permission ceiling tests `Billing::Entitlements.allowed?` (`custom_roles_controller.rb:53`
vs `custom/app/models/custom/account_user.rb:68-70`). They agree while overrides are applied to the flag
(`custom/app/services/billing/override_grant.rb`), so I record it as a risk, not a defect.

### 3.6 `set-up-an-inbox` - non-permission claims

| ID | Claim (doc) | Evidence | Verdict |
|---|---|---|---|
| I-01 | "**Voice** and **WhatsApp calling** depend on being switched on for your account" (`inbox:19-20`; AR:28-29 adds "they appear at the end"); tabs "**Voice** or **Calls** where calling is switched on" (`inbox:40`) | The cards were removed; the code says why: `settings/inbox/ChannelList.vue:96-98`. `channel_voice` is `premium: true` and off (`config/features.yml:189-192`); the four endpoints have no route (`docs/p11/00-p10-security-closure.md:209-215`); the tabs are gated on that dark flag (`settings/inbox/Settings.vue:270-300`) | **wrong** (major: promises a feature the product cannot deliver) |
| I-02 | Business hours "drive that one automatic reply and the hours shown on a website widget. They are **not** available anywhere else" (`inbox:52-54`; AR:60-62) | Also drive the business-hours variant of report metrics (`app/controllers/api/v2/accounts/reports_controller.rb:114,149`, `summary_reports_controller.rb:37,48`, `app/helpers/reporting_event_helper.rb:2-9`; toggle in `ReportFilters.vue`) and the live-chat campaign trigger "only during business hours" (`app/controllers/api/v1/accounts/campaigns_controller.rb:31`; `LiveChatCampaignForm.vue:141,168`) | **wrong** (major) |
| I-03 | "Nine are always offered" (`inbox:17`) | Facebook and Instagram tiles are disabled unless the installation has the Meta app id and the account flag (`app/javascript/dashboard/components/widgets/ChannelItem.vue:32-53,123`; `app/views/layouts/vueapp.html.erb:38-39`); a plan can refuse a channel type (B9). Agent 042 reads the Instagram settings tile as ungated; `ChannelItem.vue:48-52` gates it | imprecise (minor) |
| I-04 | Nine channel names; TikTok only when configured (`inbox:17-19`) | `ChannelList.vue:25-94` (website, facebook, whatsapp, sms, email, api, telegram, line, instagram; tiktok `:82-94`); SMS offers Twilio and Bandwidth `channels/Sms.vue:3-34` | confirmed |
| I-05 | Tabs: Settings, Collaborators, Business Hours, CSAT; plus Pre Chat Form (widget), Configuration, Bot Configuration, Account Health | `Settings.vue:187-301`; labels `inboxMgmt.json:783-796` | confirmed |
| I-06 | Business hours off, UTC, Mon-Fri 09-17, weekend closed (`inbox:44-46`); greeting off (`:58`) | `app/models/inbox.rb:17,23,24`; `app/models/concerns/out_of_offisable.rb:7-14` | confirmed |
| I-07 | Unavailable message at most once a day, not within five minutes of a public agent reply (`inbox:48-50`) | `app/services/message_templates/hook_execution_service.rb:30,32` | confirmed. Also skipped for campaign conversations `:23` (undocumented); "once a day" is "no template message yet today" `:32` |
| I-08 | Greeting only on the contact's first message, never on a campaign conversation; out of hours you get the unavailable message instead, not both (`inbox:58-60`) | `hook_execution_service.rb:17-18,35-47` (order of the two calls plus "no template yet" makes it exclusive) | confirmed |
| I-09 | Close must be after open; hours past midnight cannot be expressed; "all day" is 00:00-23:59 (`inbox:77-79`) | `app/models/working_hour.rb:74-78,80-87` | confirmed |
| I-10 | Unavailable message goes out on every channel though its help text says live chat (`inbox:80-81`) | no channel filter in `hook_execution_service.rb:22-33`; help text `inboxMgmt.json:1438,1444` | confirmed |
| I-11 | 10,000-character cap on both messages (`inbox:82`) | `lib/limits.rb:5-6`; `inbox.rb:55-56` | confirmed |
| I-12 | CSAT on WhatsApp needs a Meta-approved template (`inbox:83`) | `app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb` (create/analyze administrator-only `:12`) | confirmed in outline; Meta approval behaviour unverifiable here |
| I-13 | Auto-assignment on for a new inbox, only online agents (`inbox:84`) | `inbox.rb:15`; `app/services/auto_assignment/agent_assignment_service.rb:61-72` | confirmed |
| I-14 | No business-hours or time-of-day condition in automation rules (`inbox:52-54`) | `settings/automation/constants.js` has none; `custom/app/services/automation/lynomia_condition.rb` adds audience and commerce keys only | confirmed (agent 055's DC-10 concerns date attributes, a different thing) |

### 3.7 `teams-and-agents` - non-permission claims

| ID | Claim | Evidence | Verdict |
|---|---|---|---|
| T-01 | Setting a team clears an assignee who is not a member; removing a team does not clear the assignee (`teams:48-55`) | `assignment_handler.rb:12-22` (a nil team leaves `exclude?` as nil) | confirmed |
| T-02 | "If the team allows auto-assignment, one member is then picked" (`teams:50-52`) | picked only if the assignee is still blank: `self.assignee ||= find_assignee_from_team` `assignment_handler.rb:17`; a member-assignee is kept | incomplete |
| T-03 | Pool = team members **and** inbox collaborators **and** online (`teams:50-52,86`) | `assignment_handler.rb:27`; `agent_assignment_service.rb:61-72` | confirmed |
| T-04 | Assignee list = inbox collaborators plus administrators (`teams:57-58`) | `assignable_agents_controller.rb:7-14` (intersection across inboxes) | confirmed (UI only, B10) |
| T-05 | Sidebar shows only your teams (`teams:62`) | `Sidebar.vue:274` (`teams/getMyTeams`) | confirmed |
| T-06 | Automation can read the team, assign, remove, email a team; a macro can assign a team (`teams:63-64`) | `settings/automation/constants.js:54,96,104,116`; `app/models/macro.rb:33-35` | confirmed |
| T-07 | Names stored lower case and unique per account; delete leaves conversations with no team and their assignee (`teams:84,88`) | `app/models/team.rb:26,31-37` | confirmed |
| T-08 | Label "Allow auto assign for this team" (`teams:40`) | `teamsSettings.json:118-120` | confirmed |
| T-09 | Teams settings page administrator-only (`teams:78-79`) | `settings/teams/teams.routes.js:33,58-108` | confirmed |

### 3.8 `your-own-help-centre`

| ID | Claim | Evidence | Verdict |
|---|---|---|---|
| H-01 | No Help Center in the sidebar; the portal, category and article endpoints refuse a workspace; old pages stay online (`help:14-22`) | no portal entry in `Sidebar.vue`; policies `portal_policy.rb:25-34`; the public renderer is untouched (same file, header) | confirmed (public renderer not re-verified route by route) |
| H-02 | Canned responses "carry variables so the customer's name and **order number** fill themselves in" (`help:33-34`; AR:32-33) | the variable list has no order variable (`conversations/canned-responses.md:44-53`); `app/drops/` has contact, conversation, inbox, message, user and account only. Works only if a custom attribute holds it | **wrong** (minor) |
| H-03 | Where to find help: Documentation, Changelog, Contact Support (`help:36-42`) | The sidebar's Help & Support group lists **My tickets** and **New ticket** first, then Documentation and Contact Support (`Sidebar.vue:745-770`); the in-product desk is documented in `troubleshooting/contact-lynomia-support.md`. Documentation and Contact Support open in a new tab `SidebarGroupLeaf.vue:55-57` | incomplete (stale routing advice) |
| H-04 | A legacy `knowledge_base_manage` entry "changes nothing about what that person can do" (`help:49-52`; `roles:47-49`) | The client still reads it to show the Articles tab in global search (`permissions.js:34-36`; `modules/search/components/SearchView.vue:99,116,156,480`); the server gates nothing (`app/services/search_service.rb:177-182`). Help Center routes also still accept it (`helpcenter.routes.js:27,98,107`) | imprecise (minor) |

### 3.9 Conflicts with other reports - for arbitration

- **XA-1.** 032 (section 8) says every structural claim in `teams-and-agents` is correct, and 033 (section 8) says the
  article "correctly separates team membership from access". 033's own section 6 documents that the record ceiling is
  inbox or team. The article's two access sentences are wrong (A3).
- **XA-2.** 042 says the Instagram tile in the channel list is ungated; `ChannelItem.vue:48-52` disables it without the
  Instagram app id and flag. Not mine to settle; I record what I read.
- **XA-3.** AR `roles:62-63,92` makes a claim EN does not (A8); 061 and 094 own the parity ruling.
- **XA-4.** 062 classifies `set-up-an-inbox`, `teams-and-agents` and `your-own-help-centre` as KEEP. 062's scope is IA and
  link structure; it did not test the claims above. I rate them REWRITE / REWRITE / RELOCATE on I-01, I-02, A3 and H-02-H-03.
  058 (cross-section list, line 94) independently found I-01 false and assigned it to 057. 079 (section 1.7) hands the
  rename of `your-own-help-centre` to 057/062; my verdict is relocate and rename it, with a redirect from the old slug.
- **XA-5.** 051 (C15d) and the arbitration ledger (DC-01, DC-04) already own the two wrong contact permission claims in
  `contacts/contacts.md:94,96,127`; B6 here only records that the roles article is silent on the same facts.

## 4. Missing articles

| Candidate | The user question it answers | Evidence it is needed |
|---|---|---|
| Availability: online, busy, offline, and "mark me offline automatically" | "Why am I not getting conversations?" / "What does online mean in auto-assignment?" | three articles lean on "online" (`teams:51,86`, `inbox:84`, `assign-and-prioritise.md:35`); no article defines it; 032 section 9 item 1 |
| Remove or change an agent | "What happens to a person's conversations when I remove them?" | `Agents::DestroyJob` (`app/jobs/agents/destroy_job.rb`); no corpus coverage (032 section 9 items 2-3) |
| Business hours and the unavailable message (split out of the inbox article) | "Why did the away message send, or not send?" | I-02, I-07, I-08; distinct enough to search for |
| Inbox collaborators and auto-assignment, with assignment policies | "Why can't Fatima see this inbox?" / "How do I stop auto-assignment?" | tab exists (`Settings.vue:194`), only a table row documents it |
| CSAT survey per inbox | "How do I ask customers to rate us?" | tab exists; no CSAT article anywhere in the corpus (grep) |
| Website widget and pre-chat form | "How do I set up the chat widget?" | tabs exist; no article |
| Support cases (in-account module) and `support_ticket_manage` | "Who can see which cases, and how do I make a support lead?" | B1; the only mention is one table row |
| Who can do what - a reference matrix | "Can an agent do X?" | the same facts are scattered across `contacts`, `invite-your-team`, `roles` and `work-in-the-inbox`, and two of them disagree with the code (3.9, A3, B6) |
| What deleting a role, team or inbox does | "What happens if I delete this?" | B3, T-07 |
| Plan limits that apply to a workspace | "Why can't I add another inbox, channel type or person?" | B9 |

## 5. Quality

- **Structure.** All four use the corpus pattern (what it is, when to use it, what you need first, steps, worked example,
  who can do this, limits, related, if it does not work). `roles`, `teams` and `help` follow it fully. `set-up-an-inbox`
  has no numbered steps: it is a tour of tabs under a title that promises a procedure.
- **Task orientation.** Strongest in `teams` ("what assigning a team actually does") and the `roles` worked example.
  Weakest in `inbox`, where the reader is told what exists but not in what order to do it.
- **Screenshots.** None, in any of the eight files; the corpus has no media system to hold one
  (`01-current-system.md` section 9, item 8).
- **Length.** 491-867 EN words; appropriate. `inbox` (811) carries two topics and should be two articles.
- **Front matter.** `title`, `description`, `position`, `tags`, `seo_description` present in all eight; no `seo_title`, so
  the title is the SEO title (`content_seeder.rb:107-110`). EN titles 15-25 characters, EN `seo_description` 127-149,
  AR 99-135 - all inside the audit's 50-160 window.
- **Descriptions** all begin "You will know / understand ...", which reads as an outcome statement, not a search snippet;
  harmless because `seo_description` overrides it in the SEO path.
- **Tags** are `[workspace, <topic>]` only; nothing a search would match on beyond the title ("custom role", "away
  message", "business hours", "assign" are absent).
- **Links.** All 32 internal links in the AR files and 32 in the EN files are relative slugs that exist as corpus keys.
  EN links resolve; AR links do not land on the AR article (section 6, P-07).
- **Currency.** The roles article predates the enforcement it describes (see the framing above); the help-centre article
  describes a removal that happened before it and has not been revisited since.
- **Registry fit.** `agents` and `team_management` both link to `teams-and-agents` (`featureHelper.js:8,29`), but that
  article does not say how to add, edit or remove an agent; `invite-your-team` does. The Agents settings page's
  "Learn more" lands on the wrong article.

## 6. EN/AR parity

Presence is exact. Meaning is not. Findings, most serious first:

| ID | Severity | Finding |
|---|---|---|
| P-07 | **major, cross-corpus** | **Every internal link in an Arabic article points at the English article.** The seeder stores the body raw (`content_seeder.rb:70-81`); the Arabic sibling's slug is `<key>-ar` (`:85-87`); the portal route is `/hc/:slug/articles/:article_slug` with no locale segment and the article is found by slug alone (`config/routes.rb:519`; `app/controllers/public/api/v1/portals/articles_controller.rb:80-83`); no renderer or layout rewrites links (`lib/chatwoot_markdown_renderer.rb:14-21`, no `<base>` in `app/views`). A relative `(set-up-an-inbox)` in `.../articles/roles-and-permissions-ar` resolves to `.../articles/set-up-an-inbox`, the English page. 32 links in these four files; the same pattern holds across all 494 relative links in `ar/`. Confirmed by reading, not in a browser. Found independently in 049 (X1), 052 (W9), 056 (item 4) and 073 (D2); this section adds 32 more affected links. |
| P-01 | major | AR `roles:62-63,92` adds a claim EN lacks (A8): a downgrade lets an assigned role be removed "but not reassigned". Not enforced at the endpoint. |
| P-02 | major | **Inbox and channel collapse into one Arabic word.** EN separates "the channel is the connection; the inbox is the decisions about it" (`inbox:8-10`). AR uses القناة for both: it defines القناة as connection plus governing settings, then the next sentence says "the connection is the channel, and the settings are your decisions around it" (AR `inbox:8-10`). The same word names the inbox in the roles table (AR `roles:16`) and in the link text إعداد قناة تواصل. The distinction the English article is built on does not survive. |
| P-03 | major | **The Arabic roles article names the permissions "as the product names them" in Arabic; the Arabic product does not.** In `ar/customRole.json` only `COMMERCE_ORDER_MANAGE` and `SUPPORT_TICKET_MANAGE` are translated; the other six labels are English, and the AR sidebar entry is the English "Custom Roles". An Arabic reader comparing the article to the screen finds no matching text (AR `roles:27-37,67`). The Arabic label for the seventh permission exists (إدارة كل حالات الدعم في الحساب) and the article omits it. Corroborates 061 section 3.2. |
| P-04 | minor | Tab and field names differ from the Arabic UI: CSAT tab is تقييم رضاء العملاء (doc رضا العملاء); pre-chat is نموذج ما قبل الدردشة (doc ما قبل المحادثة); the Configuration tab is labelled الإعدادات, the same as the Settings tab (doc التهيئة); bot tab اعدادات البوت (doc تهيئة البوت); Account Health and Calls are English in the UI (doc سلامة الحساب, المكالمات); team auto-assign is السماح بالتكليف التلقائي (doc الإسناد); unavailable message is رسالة غير متاح للزائرين (doc رسالة عدم التوفّر); Agents menu is وكيل الدعم (doc الوكلاء). Source: `ar/inboxMgmt.json` TABS, `ar/settings.json` SIDEBAR, `ar/teamsSettings.json` FORM.AUTO_ASSIGN. Corroborates 061 section 3.1. |
| P-05 | minor | Content present in only one language: AR roles table has separate billing and canned/macros rows (EN merges them); AR roles example adds "does not get reports"; AR inbox example adds the two receptionists and auto-assignment; AR teams example adds that the coordinator sees it in her sidebar; AR channels are a table, EN prose. None contradicts the other; the Arabic is slightly fuller. |
| P-06 | minor | Terminology drift inside Arabic: ماكروس (`roles:19`, `teams:66`) against ماكرو / الماكرو (`help:29,54`). EN says "macro" throughout. |
| P-08 | - | Every defect in section 3 (A1-A7, I-01, I-02, H-02) is reproduced faithfully in Arabic; the translation did not introduce errors, it copied them. |

## Appendix - what I did not check

- No browser session: every UI statement (greyed tiles, paywall page, 401 panels) is from source.
- Meta's approval requirement for WhatsApp CSAT templates (`inbox:83`) is Meta behaviour; only the Lynomia side was read.
- `ChannelItem.vue` and the Instagram/Facebook gating were read for the settings list only, not the onboarding list.
- The public `/hc/*` renderer was not re-read route by route for `H-01`; I relied on the policy file's own header.
- Plan composition (which plans include `custom_roles`) is data in `billing_plans.features`, not code; "paid plans" is unverifiable from the repository.
