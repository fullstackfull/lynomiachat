# Notification authorization — the final rule: the conversation access ceiling AND the capability scope

`04-decisions-implemented.md` records the six approved product decisions. This document records the two gaps
DECISION 1 left behind on the **notification feed**, and the owner's decisions of 2026-10-12 closing both.

They were closed in that order and the second subsumes the first, so the rule to read off this document is the
final one:

> **A conversation notification is visible to a membership if and only if that membership can CURRENTLY access
> that conversation — the canonical Inbox/Team/account access ceiling AND the `conversation_*` capability
> scope. Both must permit. Neither replaces the other.**
>
> **No notification row is ever purged, rewritten or migrated.** Access removed means hidden on the next server
> read; access restored means visible again, from the same untouched row.

---

## 1. Root cause

DECISION 1 made the three `conversation_*` capabilities real server-side authorization on the conversation
list, the conversation record, global search and the unread counts. It did not reach the notification feed, and
the notification feed is not metadata.

### 1a. Authorization was asked at write time only

1. **`NotificationBuilder` checks, and it checks the right thing.**
   `build_notification` returns early unless `user_can_access_conversation?`
   (`app/builders/notification_builder.rb:31`, method at `:42-53`), which asks `ConversationPolicy#show?`
   (`:49-52`). So a notification cannot be *born* unauthorized — under either layer, then or now.
2. **Nothing revisits a row once written.** The only cleanup anywhere is
   `has_many :notifications, as: :primary_actor, dependent: :destroy_async`
   (`app/models/conversation.rb:131`), and it fires when the **conversation** is destroyed, never when access
   changes. `InboxMember` and `TeamMember` each invalidate one count cache on create/destroy and do nothing
   else (`app/models/inbox_member.rb:27,39-41`; `app/models/team_member.rb:22,26-28`).

So every event that narrows access after the fact left the member a feed over conversations they could no
longer open: an administrator editing a permission set, the `custom_roles` entitlement lapsing, a conversation
being reassigned — and, the second gap, **an inbox membership being removed, a team membership being removed,
or a conversation's `team_id` changing**.

### 1b. The ceiling had no relation form, so the feed did not apply it

The first closure narrowed by the *capability* only. The Inbox/Team ceiling was never applied, because it did
not exist in a shape a list could use: it lived as three private methods of a policy
(`app/policies/conversation_policy.rb:16-36`), each a predicate over one `record`. That is correct for
authorizing one conversation and useless for authorizing a page of notifications, and the feed must not ask a
policy per row. So a member removed from an inbox kept the historical notifications of that inbox's
conversations — with their message bodies — even after the capability narrowing landed.

### What the feed exposes

`app/views/api/v1/accounts/notifications/index.json.jbuilder` emits, per row:

| line | field | what it actually contains |
| --- | --- | --- |
| 13 | `push_message_body` | the message text, via `Notification#push_message_body` |
| 17 | `primary_actor.push_event_data` | `Conversations::EventDataPresenter#push_data` — the **last chat message in full** (`:34-36`) and the contact's name, email and phone (`:42-50`), plus labels, assignee, team, status and custom attributes |
| 20 | `secondary_actor.push_event_data` | a `Message`, serialized from `attributes.symbolize_keys` (`app/models/message.rb:148`) — the whole body again, plus attachments and sender |

The same payload is pushed over ActionCable as `notification.push_event_data`
(`app/listeners/action_cable_listener.rb:7` and `:13`).

---

## 2. The canonical Inbox/Team rule, and why this one

Two different objects answer "which conversations may this member see", and they do **not** agree:

| | `ConversationPolicy#show?` | `Conversations::PermissionFilterService#perform` |
| --- | --- | --- |
| shape | record predicate | relation filter |
| administrator | unrestricted (`:11`) | unrestricted (`:12`) |
| agent bot | unrestricted (`:11`) | not considered |
| rule | `inbox_access? **or** team_access?` (`:16-18`) | inbox membership **only** (`:22`) |

The asymmetry is deliberate and pre-existing: `spec/policies/conversation_policy_spec.rb:54-63` asserts that a
team member with no inbox membership may open the conversation, while the list would never return it.

**The ceiling reused here is `ConversationPolicy#show?`.** It is the canonical one — it is what
`NotificationBuilder` already asks at write time, what every conversation record read in the product is
authorized by, and what the required behaviour of this closure names: a notification must be visible on team
access per existing semantics, which the inbox-only list filter would have denied. Choosing the list filter
would have *narrowed* the product; choosing the policy preserves it exactly.

**The rule, inspected rather than guessed** (`app/policies/conversation_policy.rb`):

| case | behaviour | how it is decided |
| --- | --- | --- |
| account administrator | every conversation in the account | `account_user&.administrator?` (`:20-22`) — the `role` column on the membership |
| agent bot | every conversation | `user.is_a?(AgentBot)` (`:24-26`); a bot is not a membership |
| inbox membership | conversations in an inbox the user belongs to | `user.inboxes` → `inbox_members` (`app/models/user.rb:99-100`), scoped `account_id` (`:28-30`) |
| team membership | conversations whose `team_id` is set **and** is a team the user belongs to | `user.teams` → `team_members` (`app/models/user.rb:112-113`), scoped `account_id` (`:32-36`) |
| inbox **vs** team | either is sufficient; neither is required | `inbox_access? \|\| team_access?` (`:17`) |
| assigned agent | **grants nothing on its own** | `assigned_to_user?` is defined (`:38-40`) and is **never called from `show?`** |
| participant | **grants nothing on its own** | `participant?` is defined (`:42-44`) and is **never called from `show?`** |
| unassigned conversation | not a special case | the ceiling never reads `assignee_id`; that is the capability layer's question |
| `account` nil | denies both legs | `where(account_id: account&.id)` matches nothing; preserved rather than guarded |

The two "grants nothing" rows are the load-bearing ones, and they are asserted directly: an assignee of a
conversation in an inbox they do not belong to, with no team, is refused
(`spec/services/conversations/access_ceiling_spec.rb`).

---

## 3. The final architecture — one interpretation, two shapes, four consumers

```
Notifications::ConversationVisibility          "may this membership see this notification"
  ├── Conversations::AccessCeiling             the Inbox/Team/account ceiling      ── ALSO the policy's own
  └── Conversations::CapabilityScope           the conversation_* capability          implementation
            intersected, never substituted
```

**`custom/app/services/conversations/access_ceiling.rb` (`Conversations::AccessCeiling`) holds the ceiling, and
`ConversationPolicy` delegates to it.** The rule was *moved*, not copied:
`Custom::ConversationPolicy#agent_can_view_conversation?` now reads
`access_ceiling.agent_can_view?(record)` and nothing else. So the product has **one** implementation of
Inbox/Team conversation visibility. The policy remains the authority on conversation access; it simply no
longer also stores the rule.

The object offers that one rule in the two shapes the product needs:

* `agent_can_view?(conversation)` — the record answer. Verbatim `inbox_access? || team_access?`, same two
  queries. This is what the policy calls.
* `narrow(relation)` — the same rule as SQL: `unrestricted?` returns the relation untouched for an
  administrator or an agent bot, otherwise
  `relation.where(inbox_id: <inbox ids>).or(relation.where(team_id: <team ids>))`.
  `team_id IN (<subquery>)` carries the policy's `return false if record.team_id.blank?` for free, because
  `NULL IN (...)` is never true.

**They cannot drift, and that is tested rather than asserted in prose.**
`spec/services/conversations/access_ceiling_spec.rb` walks six conversations (my inbox × no team / my team /
another team, and another inbox × the same three) for both an agent and an administrator, and requires
`narrow`'s membership and `ConversationPolicy#show?`'s answer to agree on every one, naming the disagreement if
they ever do not.

**`Notifications::ConversationVisibility` composes the two layers and translates them onto `notifications`.**
It restates neither rule. Its own two shapes:

* `narrow(relation)` — intersects *inside* the conversation subselect:
  `access_ceiling.narrow(capability_scope.narrow(account.conversations, user:)).select(:id)`. Both narrowings
  land on the same relation, so the result is the conversations satisfying ceiling **AND** capability, and the
  notifications relation stays a single `IN (SELECT …)`.
* `permits?(notification)` — asks **`ConversationPolicy#show?`**. Not the two layers separately: the policy
  already composes them (administrator/bot short-circuit → ceiling via the delegation → capability via
  `Custom::ConversationPolicy`), and it is the product's canonical record answer. The record path is therefore
  the canonical answer rather than a copy of it, and it stays correct if either layer changes.

Write time and read time are now literally the same expression: `NotificationBuilder` asks
`ConversationPolicy#show?`, and so does `permits?`.

| Consumer | Socket | What it covers |
| --- | --- | --- |
| `Custom::NotificationFinder` | `NotificationFinder.prepend_mod_with` | the feed, `unread_count`, `count`, and through `BaseListener#extract_notification_and_account` (`app/listeners/base_listener.rb:9-15`) the websocket badge |
| `Custom::Api::V1::Accounts::NotificationsController` | `prepend_mod_with` | the member routes by id — `update`, `destroy`, `snooze`, `unread` — and `read_all` |
| `Custom::ActionCableListener` | `prepend_mod_with` | the `notification.created` and `notification.updated` socket payloads |
| `Custom::Notification::DeleteNotificationJob` | `prepend_mod_with` | `destroy_all`, so it cannot destroy what it is not allowed to show |

**Why `find_all_notifications` is the insertion point.** It is the one place every answer the finder gives
derives from: `notifications`, `unread_count` and `count` all read `@notifications`
(`app/finders/notification_finder.rb:13-31`). The page and the two counts are therefore the same relation and
cannot disagree.

**Which notifications are "about a conversation".**

* `Conversation` — every notification this product creates. All **six** `NotificationBuilder.new` call sites
  pass one (`app/listeners/notification_listener.rb:7,21,42`;
  `app/services/messages/new_message_notification_service.rb:20,36`;
  `app/services/messages/mention_service.rb:55`) and `Notification::PRIMARY_ACTORS` names only this one
  (`app/models/notification.rb:56`). Narrowed by the subselect.
* `Message` — **historical**. `Message` still declares `has_many :notifications, as: :primary_actor`
  (`app/models/message.rb:136`) and `Migration::RemoveMessageNotifications` exists to delete the rows
  (`app/jobs/migration/remove_message_notifications.rb:6`), so one could survive a lost enqueue. Such a row is
  about a conversation but the notifications row does not say which, so it cannot be authorized from the
  relation. It is **excluded while narrowing is active** rather than passed through — failing closed on a row we
  cannot authorize — and this costs nothing, because the feed cannot render one anyway
  (`Notification#push_message_title` calls `display_id` on the primary actor and `Message` has no such method).
* **Anything else** — left alone, as the decision requires. Nothing creates one today; the three `sla_missed_*`
  enum values (`app/models/notification.rb:44-46`) are declared and have no creation site anywhere in `app/`,
  `custom/` or `lib/`.

**404, not 403**, on the member routes. That is what an unknown id already produces, and what the custom-roles
endpoint chose for the same reason: a 403 would confirm the id exists and belongs to this user. The response is
byte-identical whether the id is wrong, somebody else's, or real-but-unauthorized — asserted directly, which is
also the answer to "does a sequential notification id become an oracle": it does not.

**The ActionCable path needed its own gate** because one writer is not a request at all.
`Notification::ReopenSnoozedNotificationsJob` (`app/jobs/notification/reopen_snoozed_notifications_job.rb:17`)
is a cron that unsnoozes every expired notification with `update!`, firing
`after_update_commit :dispatch_update_event` (`app/models/notification.rb:54`) and re-pushing the whole
conversation payload to the recipient whatever their access is now. `notification.deleted` is deliberately
**not** gated: its payload is `{ id: }` only and its counts come from the narrowed finder, so suppressing it
would strand a hidden-then-deleted notification in the browser's local store.

---

## 4. Historical notification behaviour — stated plainly

**No row is purged, rewritten or deleted by either closure.** There is no migration and no backfill.
Authorization is asked fresh on every read. The consequence is intended and is the decision:

> **Access removed → the notification disappears from the feed, the counts, the member routes and the socket.
> Access restored → the same untouched row becomes visible again.**

Both directions are asserted for all three ways access moves: a capability edit, a DECISION 2 entitlement lapse
and return, and — added by this closure — **inbox membership granted and removed, and team membership granted
and removed**. The row's `read_at` is still `nil` when it comes back, because nothing touched it.

One consequence worth stating because an operator will meet it: **`destroy_all` is narrowed too.** Before this,
"delete all notifications" destroyed every row the member had in the account. Once the feed is narrowed, that
button would have permanently destroyed rows the member was no longer shown — which would make "access
restored → visible again" impossible for them. So the job now destroys exactly the set the feed would have
shown, and leaves the rest. A member who presses "delete all" while narrowed, and whose access is later
restored, will see the previously hidden notifications reappear.

---

## 5. Endpoints and socket surfaces covered

| Route | Action | Behaviour now |
| --- | --- | --- |
| `GET /api/v1/accounts/:id/notifications` | `index` | narrowed; `meta.count` and `meta.unread_count` describe the narrowed set |
| `GET …/notifications/unread_count` | `unread_count` | narrowed (same relation) |
| `PATCH …/notifications/:id` | `update` | 404 when the conversation is unauthorized; `read_at` unchanged |
| `DELETE …/notifications/:id` | `destroy` | 404; the row survives |
| `POST …/notifications/:id/snooze` | `snooze` | 404 |
| `POST …/notifications/:id/unread` | `unread` | 404 |
| `POST …/notifications/destroy_all` | `destroy_all` | destroys only the authorized set |
| `POST …/notifications/read_all` | `read_all` | narrowed — see below |
| ActionCable `notification.created` / `.updated` | listener | payload suppressed when unauthorized |
| ActionCable `notification.deleted` | listener | unchanged by design (id only; counts already narrowed) |

Every row above now applies **both** layers, because both consumers of the rule — the relation and the record —
went through `Notifications::ConversationVisibility`, and that is where the intersection was formed.

**`read_all` deserves its own note, because it is not what its name suggests.** It is the dashboard's
*per-notification* "mark read": `NotificationsAPI#read(primaryActorType, primaryActorId)`
(`app/javascript/dashboard/api/notifications.js:29-34`) POSTs to `read_all` with one conversation's actor, and
the store calls it on every notification click
(`app/javascript/dashboard/store/modules/notifications/actions.js:38-51`). So the route that looks like a bulk
mutation is the hot path for a single row. It discloses nothing — `head :ok` either way, and `update_all` skips
callbacks so no socket fires — but unnarrowed it would set `read_at` on rows the member cannot see, and a
notification hidden at the time of "mark all read" would return **already read** if access were restored. It is
narrowed for that reason, and an unrestricted membership returns to `super` before any extra SQL is built.

---

## 6. Query shape and measured evidence

The narrowing is a single uncorrelated subselect. For an unrestricted membership — administrator or agent bot,
i.e. `capability_scope.unrestricted? && access_ceiling.unrestricted?` — it is not added at all.

Generated SQL, for a `conversation_participating_manage` holder who is an inbox member (`:mine` capability
mode, ceiling applied), reproduced from `to_sql`:

```sql
… AND (notifications.primary_actor_type NOT IN ('Conversation','Message')
       OR notifications.primary_actor_type = 'Conversation'
          AND notifications.primary_actor_id IN (
            SELECT conversations.id FROM conversations
             WHERE conversations.account_id = ? AND conversations.assignee_id = ?
               AND (conversations.inbox_id IN (SELECT inboxes.id FROM inboxes
                      INNER JOIN inbox_members ON inbox_members.inbox_id = inboxes.id
                       WHERE inbox_members.user_id = ? AND inboxes.account_id = ?)
                 OR conversations.team_id IN (SELECT teams.id FROM teams
                      INNER JOIN team_members ON team_members.team_id = teams.id
                       WHERE team_members.user_id = ? AND teams.account_id = ?))))
```

Two layers, one statement. The capability predicate (`assignee_id = ?`) and the ceiling predicate
(`inbox_id IN … OR team_id IN …`) are `AND`ed inside the conversation subselect, so the ceiling's `OR` group
cannot interleave with the capability's and the notifications relation stays a single `IN (SELECT …)`.

**The measured plan** (`EXPLAIN` over the real finder relation, asserted in
`spec/finders/notification_finder_authorization_spec.rb`):

```
Index Scan using index_notifications_on_user_id on notifications
  Filter: (… AND (primary_actor_type NOT IN (…) OR (hashed SubPlan 3)))
  SubPlan 3 (hashed)
    -> Index Scan using index_conversations_on_assignee_id_and_account_id on conversations
         Filter: ((hashed SubPlan 1) OR (hashed SubPlan 2))
         SubPlan 1 (hashed)  -> inboxes ⋈ inbox_members
         SubPlan 2 (hashed)  -> teams   ⋈ team_members
```

* **Every subselect is `hashed`**, which is the property that matters and the one asserted: Postgres evaluates
  an uncorrelated subplan **once** and the outer node probes a hash. A bare `SubPlan N` would be re-executed
  per row. The assertion is written as "every declared SubPlan id also appears as a hashed SubPlan", so a
  regression to a correlated subplan fails the test.
* The two `Nested Loop`s (inboxes ⋈ inbox_members, teams ⋈ team_members) sit **inside** hashed subplans, so
  each runs once over the member's own handful of memberships. Their absence is deliberately **not** asserted;
  asserting it would assert the wrong thing.
* **One statement per page**, asserted: exactly one statement reads `FROM "notifications"` with a `LIMIT`, and
  **zero** statements start with `SELECT "conversations"` — the conversations table is reached only as a
  subselect. That is what "no per-row authorization query" means here.
* **The ids are never loaded into Ruby.** `authorized_conversation_ids` is a relation, so Rails renders it as
  `IN (SELECT …)`; the answer is not bounded by how many conversations, inboxes or teams the member can reach.
* **Fixed per-request cost, measured across construction** (the authorization lookups happen in
  `NotificationFinder#initialize`, not on `.to_a`): **≤ 4 extra statements** for a narrowed membership versus
  an unrestricted one — the membership, the user reload, the permission set and the entitlement override.
  Fixed per request, never per row. Index usage is deliberately not asserted: at test row counts a sequential
  scan is the correct plan and the planner picks it.
* **`:none` capability mode** renders `1=0`, so no conversation notification is returned and no conversation
  rows are scanned.

**The schema fact that makes the shape safe.** `notifications.primary_actor_type` is `null: false`
(`db/schema.rb:1578`). The `NOT IN` leg relies on three-valued logic, and on a nullable column
`NULL NOT IN (...)` evaluates to NULL rather than true — which would have silently dropped every row with no
actor type. It is non-null, so there is no hazard.

**Measured cost of the record-path gate**, which the socket listener pays per broadcast: **1 query** for an
unrestricted membership (the `account_users` lookup) and **4** for a narrowed one (membership, the user reload,
the permission set, and the entitlement override — the last because `Custom::AccountUser#permissions` is not
memoized, which this task was told not to change). The ceiling adds at most its two `exists?` queries on that
path, both short-circuiting (`inbox_access?` first, and `team_access?` not run at all when the inbox grants).
One indexed lookup on a path that already performs an `INSERT`, two `COUNT`s and up to three job enqueues is
why both socket events are gated rather than only the unsafe one.

**Why the narrowing had to go INSIDE the relation, not after the fetch.** The dashboard treats a short page as
the end of the feed: `app/javascript/dashboard/store/modules/notifications/actions.js:21` commits
`SET_ALL_NOTIFICATIONS_LOADED` whenever `payload.length < 15`, and that flag is never cleared for the session.
A post-fetch reject — load 15, drop the unauthorized ones, return 9 — would therefore have silently truncated
the feed for the rest of the session, and the member would never see page 2. Narrowing before `.page`/`.per`
keeps pages full and keeps `count` describing the same set, which is asserted (19 authorized notifications
yield a full page of 15 and a count of 19, while the inaccessible ones are absent from both).

### Indexes — **no new index is required**

`EXPLAIN` does not demonstrate a need for one, so none was added. From `db/schema.rb`:

| Side | Index | Note |
| --- | --- | --- |
| notifications (driving) | `idx_notifications_performance` on `(user_id, account_id, snoozed_until, read_at)` (`:1592`) | exactly the four conditions the finder applies before the narrowing |
| notifications (`IN` probe) | `(primary_actor_type, primary_actor_id)` (`:1590`) | named `uniq_…` but **not** a unique index |
| conversations, capability `:mine` | `(assignee_id, account_id)` (`:1109`) | exact match for the predicate |
| conversations, capability `:unassigned_and_mine` | `(assignee_id, account_id)` + `(account_id)` (`:1108-1109`) | the bot-nullity term has no index and is a filter, never a seek |
| conversations, ceiling inbox leg | `index_conversations_on_inbox_id` (`:1116`), and `conv_acid_inbid_stat_asgnid_idx` on `(account_id, inbox_id, status, assignee_id)` (`:1106`) | the composite covers account + inbox together |
| conversations, ceiling team leg | `index_conversations_on_team_id` (`:1120`) | |
| ceiling, team membership subselect | `index_team_members_on_user_id` (`:1835`) | the subselect's own predicate is `team_members.user_id = ?` |
| ceiling, inbox membership subselect | **none on `user_id` alone** — only `(inbox_id, user_id)` unique and `(inbox_id)` (`:1386-1387`) | see below |

**The one honest gap.** `inbox_members` has no index with `user_id` as its leading column, so
`WHERE inbox_members.user_id = ?` cannot seek; Postgres scans or uses the composite as a skip scan. This is
**pre-existing and shared**: `ConversationPolicy#inbox_access?` has always run `user.inboxes.where(...)`, and
`Conversations::PermissionFilterService` runs the same membership lookup on every conversation list request.
No index was added because (a) `inbox_members` is small — one row per agent per inbox, so hundreds of rows for
a large account, not millions — (b) the subselect is hashed and runs once per request, and (c) `EXPLAIN` shows
no cost justifying it, which is the standard this task set. If it ever matters it will matter first on the
conversation list, which is the hotter path, and the fix belongs there.

**Why a relation and not a policy call per row.** A per-record `ConversationPolicy#show?` costs 2–3 queries
steady state (inbox membership, team membership, plus an un-memoized entitlement-override read through
`Billing::Entitlements`), i.e. roughly 30–45 extra queries for one 15-row page. The relation shape costs one
subselect.

**Pre-existing and not changed by this work:** the notification index is already an N+1 before any of this.
The jbuilder calls `primary_actor.push_event_data`, `secondary_actor&.push_event_data` and
`push_message_body` per row, and the finder preloads nothing. This change neither worsens nor fixes that, and
it was explicitly out of scope; see §8.

---

## 7. The three existing specs the narrowing required, and why the specs were the thing that was wrong

Applying the ceiling turned 12 examples red in three OSS spec files. Every one of them had planted a
notification for a member with **no inbox or team access to its conversation** — or with no conversation at
all — a state the product cannot produce, because `NotificationBuilder` asks the same
`ConversationPolicy#show?` at write time. The fixtures were corrected rather than the rule:

| file | what it was doing | fix |
| --- | --- | --- |
| `spec/finders/notification_finder_spec.rb` | six notifications on the factory default actor, for a user with no memberships; the file is about status filtering, ordering and counts | added an inbox, an `inbox_member` for the user, and a conversation in that inbox as `primary_actor` on all three creates |
| `spec/listeners/action_cable_listener_spec.rb` | `notification_deleted` and `notification_updated` each created a notification with no conversation | both now use the existing `conversation`, which is in the existing `inbox` the existing `agent` is a member of |
| `spec/jobs/notification/delete_notification_job_spec.rb` | the user had no `account_user` at all, and the notifications had no reachable conversation | added the `account_user`, an inbox, a membership, and an accessible conversation as `primary_actor` |

A deliberate choice recorded here because it is the kind of thing that should not be silent: **no production
code was relaxed to make a spec pass.** The non-vacuity of the new tests was checked the other way round too —
with the intersection neutralised in `ConversationVisibility`, 15 of the 22 new ceiling examples fail.

---

## 8. Known limitations, stated rather than hidden

1. **A browser that already fetched a notification keeps rendering it.** This is a read-time design, so
   nothing on the server can evict a row from a store the client already holds. `CLEAR_NOTIFICATIONS`
   (`app/javascript/dashboard/store/modules/notifications/mutations.js:10-13`) is the only thing that empties
   `$state.records`, and a reconnect refetches page 1 and *merges* rather than replaces. So after access is
   revoked mid-session the stale row — including its `pushMessageBody` — stays on screen until the user
   changes a filter or reloads. Gating the socket does not help, because the row is already local. This is the
   residual consequence of read-time-only enforcement and the one case where the operator should expect a
   reload to be needed.
2. **A suppressed socket event also suppresses its count refresh.** The listener returns before `super`, and
   `super` is what carries `unread_count`/`count`. Benign today — a hidden row does not change the narrowed
   counts — but it is a coupling worth knowing, because the socket is the only thing that writes `meta`
   between fetches.
3. **Per-row fan-out on two existing paths costs more than it did.** `destroy_all` destroys row by row and each
   `after_destroy_commit` builds a `NotificationFinder` for the counts, so N destroyed rows means roughly 2N
   now-narrowed counts; and `ReopenSnoozedNotificationsJob` calls `update!` per row, so each unsnoozed
   notification now also pays the record-path gate above. Both fan-outs pre-date this change — the counts and
   the broadcasts were already per row — but each unit is now slightly more expensive. Neither is on a request
   path: `destroy_all` and the cron both run on Sidekiq.
4. **`set_primary_actor` resolves a conversation id without account scoping**
   (`notifications_controller.rb:64-69`). The resolved record is only used as a filter on the caller's own
   rows, so it is an oracle at worst rather than a data leak. Pre-existing; not touched.
5. **`inbox_members` has no `user_id`-leading index.** Pre-existing, shared with the conversation list, and
   `EXPLAIN` shows no need; recorded in full in §6.
6. **The list/record asymmetry in the rest of the product is unchanged.** A team member with no inbox
   membership can open a conversation the conversation *list* will not return
   (`Conversations::PermissionFilterService` is inbox-only). The notification feed now matches the **record**
   rule, which is the canonical one and the one this closure was told to reuse. Making the list match is a
   product decision about the conversation list, not about notifications, and was explicitly out of scope.
7. **The notification index's pre-existing N+1** (§6). Fixing it means adding preloads to an OSS finder and
   would change query counts other specs may assert; it is unrelated to authorization and was out of scope.
8. **Deliveries are not read surfaces and were not gated.** Push/FCM and e-mail fire from
   `after_create_commit` (`app/models/notification.rb:52`), at which point `NotificationBuilder` has already
   established authorization under both layers. A member narrowed *after* creation will not receive a new
   delivery, because no new notification is created for them.
9. **A notification about something that is neither a Conversation nor a Message passes through, and the index
   cannot render it.** `Notification#push_message_title` calls `display_id` on the primary actor
   unconditionally, so such a row raises `NoMethodError` in `index.json.jbuilder` — before and after this
   change alike, since the unnarrowed finder returned it too. The pass-through is what the decision asks for
   ("notifications not associated with a Conversation must remain unaffected") and nothing creates such a row
   today; the renderer fragility is pre-existing and separate.
10. **A correction to `04-decisions-implemented.md`.** That document's architecture notes asserted that no OSS
    `app/` file references a constant defined only under `custom/`. That is **wrong**, and the real invariant is
    narrower: no `app/` file names a `Custom::`-prefixed constant. Four unprefixed `custom/` constants are
    already referenced from `app/` — `Audience::Usage` (`app/views/api/v1/models/_custom_filter.json.jbuilder`),
    `Channels::ConnectionState` (`app/views/api/v1/models/_inbox.json.jbuilder`),
    `Operations::SignalRecorder` (`app/models/campaign.rb`) and `Whatsapp::DeliveryFailure`
    (`app/controllers/api/v1/accounts/conversations/messages_controller.rb`). This closure adds a fifth kind of
    coupling that should be named explicitly: `app/policies/conversation_policy.rb` does not reference
    `Conversations::AccessCeiling`, but its prepended override does, so the OSS policy's behaviour now depends
    on a `custom/` service **through the existing `prepend_mod_with` socket** (`conversation_policy.rb:47`) and
    only when the `custom` extension is present — which is the sanctioned mechanism, not a new hard fork.
