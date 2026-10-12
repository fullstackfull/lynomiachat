# The final authorization gap — read-time conversation authorization on the notification feed

`04-decisions-implemented.md` records the six approved product decisions. This document records the one gap
DECISION 1 left behind and the owner's decision of 2026-10-12 closing it.

---

## 1. Root cause

DECISION 1 made the three `conversation_*` capabilities real server-side authorization on the conversation
list, the conversation record, global search and the unread counts. It did not reach the notification feed, and
the notification feed is not metadata.

Two facts together produced the gap:

1. **Authorization was checked at WRITE time only.** `NotificationBuilder#build_notification` returns early
   unless `user_can_access_conversation?` (`app/builders/notification_builder.rb:31`, method at `:42-53`),
   which asks `ConversationPolicy#show?` (`:49`) — and that policy *does* carry DECISION 1's narrowing. So a
   notification cannot be *born* unauthorized.
2. **Nothing revisits a row once written.** The only cleanup anywhere is
   `has_many :notifications, as: :primary_actor, dependent: :destroy_async`
   (`app/models/conversation.rb:131`), and it fires when the **conversation** is destroyed, never when access
   changes. `InboxMember` destroy invalidates a count cache and nothing more
   (`app/models/inbox_member.rb:39-41`).

So every event that narrows access after the fact — an administrator editing a permission set, the
`custom_roles` entitlement lapsing, a conversation being reassigned — left the member a feed over conversations
they could no longer open.

**What the feed exposes.** `app/views/api/v1/accounts/notifications/index.json.jbuilder` emits, per row:

| line | field | what it actually contains |
| --- | --- | --- |
| 13 | `push_message_body` | the message text, via `Notification#push_message_body` |
| 17 | `primary_actor.push_event_data` | `Conversations::EventDataPresenter#push_data` — the **last chat message in full** (`:34-36`) and the contact's name, email and phone (`:42-50`), plus labels, assignee, team, status and custom attributes |
| 20 | `secondary_actor.push_event_data` | a `Message`, serialized from `attributes.symbolize_keys` (`app/models/message.rb:148`) — the whole body again, plus attachments and sender |

The same payload is pushed over ActionCable as `notification.push_event_data`
(`app/listeners/action_cable_listener.rb:7` and `:13`).

---

## 2. Read-time authorization architecture

**One definition, four consumers** — the DECISION 1 architecture repeated one level down.

`custom/app/services/notifications/conversation_visibility.rb` (`Notifications::ConversationVisibility`) is the
only place that decides whether a membership may see a notification. It does **not** restate the capability
rule: it asks `Conversations::CapabilityScope`, in the shape that object already offers, and only translates
the answer onto the `notifications` table. Grandfathering, widest-wins, the administrator short-circuit and
DECISION 2's entitlement bound are therefore whatever DECISION 1 says they are, now and after any future change
to that file.

| Consumer | Socket | What it covers |
| --- | --- | --- |
| `Custom::NotificationFinder` | `NotificationFinder.prepend_mod_with` (added) | the feed, `unread_count`, `count`, and through `BaseListener#extract_notification_and_account` (`app/listeners/base_listener.rb:9-15`) the websocket badge |
| `Custom::Api::V1::Accounts::NotificationsController` | `prepend_mod_with` (added) | the four member routes by id: `update`, `destroy`, `snooze`, `unread` |
| `Custom::ActionCableListener` | `prepend_mod_with` (already existed) | the `notification.created` and `notification.updated` socket payloads |
| `Custom::Notification::DeleteNotificationJob` | `prepend_mod_with` (added) | `destroy_all`, so it cannot destroy what it is not allowed to show |

`narrow` (relation) and `permits?` (record) are the same pair of shapes `CapabilityScope` offers and are derived
from the same object, so the list answer and the record answer cannot drift. That agreement is asserted for
every mode rather than assumed.

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
byte-identical whether the id is wrong, somebody else's, or real-but-unauthorized — asserted directly.

**The ActionCable path needed its own gate** because one writer is not a request at all.
`Notification::ReopenSnoozedNotificationsJob` (`app/jobs/notification/reopen_snoozed_notifications_job.rb:17`)
is a cron that unsnoozes every expired notification with `update!`, firing
`after_update_commit :dispatch_update_event` (`app/models/notification.rb:54`) and re-pushing the whole
conversation payload to the recipient whatever their access is now. `notification.deleted` is deliberately
**not** gated: its payload is `{ id: }` only and its counts come from the narrowed finder, so suppressing it
would strand a hidden-then-deleted notification in the browser's local store.

---

## 3. Historical notification behaviour — stated plainly

**No row is purged, rewritten or deleted by this change.** There is no migration and no backfill.
Authorization is asked fresh on every read. The consequence is intended and is the decision:

> **Permission removed → the notification disappears from the feed, the counts, the member routes and the
> socket.
> Permission restored → the same untouched row becomes visible again.**

Both directions are asserted, for a capability edit and for a DECISION 2 entitlement lapse and return.

One consequence worth stating because an operator will meet it: **`destroy_all` is narrowed too.** Before this,
"delete all notifications" destroyed every row the member had in the account. Once the feed is narrowed, that
button would have permanently destroyed rows the member was no longer shown — which would make "permission
restored → visible again" impossible for them. So the job now destroys exactly the set the feed would have
shown, and leaves the rest. A member who presses "delete all" while narrowed, and whose capability is later
widened, will see the previously hidden notifications reappear.

---

## 4. Endpoints covered

| Route | Action | Behaviour now |
| --- | --- | --- |
| `GET /api/v1/accounts/:id/notifications` | `index` | narrowed; `meta.count` and `meta.unread_count` describe the narrowed set |
| `GET …/notifications/unread_count` | `unread_count` | narrowed (same relation) |
| `PATCH …/notifications/:id` | `update` | 404 when the conversation is unauthorized; `read_at` unchanged |
| `DELETE …/notifications/:id` | `destroy` | 404; the row survives |
| `POST …/notifications/:id/snooze` | `snooze` | 404 |
| `POST …/notifications/:id/unread` | `unread` | 404 |
| `POST …/notifications/destroy_all` | `destroy_all` | destroys only the authorized set |
| ActionCable `notification.created` / `.updated` | listener | payload suppressed when unauthorized |
| ActionCable `notification.deleted` | listener | unchanged by design (id only; counts already narrowed) |
| `POST …/notifications/read_all` | `read_all` | narrowed — see below |

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

## 5. Query shape

The narrowing is a single uncorrelated subselect. For an unrestricted membership it is not added at all.

```sql
-- :mine
… AND (notifications.primary_actor_type NOT IN ('Conversation','Message')
       OR notifications.primary_actor_type = 'Conversation'
          AND notifications.primary_actor_id IN
              (SELECT conversations.id FROM conversations
                WHERE conversations.account_id = ? AND conversations.assignee_id = ?))
```

* **One statement per page**, asserted: the measured query count for a narrowed member equals the count for an
  unrestricted one.
* **Evaluated once, not per row**, asserted from the plan: Postgres reports `hashed SubPlan`, and there is no
  `Nested Loop`.
* **`:base`** adds nothing — `unrestricted?` returns before any subquery is built.
* **`:none`** renders `1=0`, so no conversation notification is returned and no conversation rows are scanned.

**The schema fact that makes the shape safe.** `notifications.primary_actor_type` is `null: false`
(`db/schema.rb:1578`). The `NOT IN` leg relies on three-valued logic, and on a nullable column
`NULL NOT IN (...)` evaluates to NULL rather than true — which would have silently dropped every row with no
actor type. It is non-null, so there is no hazard.

**Measured cost of the record-path gate**, which the socket listener pays per broadcast: **1 query** for an
unrestricted membership (the `account_users` lookup) and **4** for a narrowed one (membership, the user reload,
the permission set, and the entitlement override — the last because `Custom::AccountUser#permissions` is not
memoized, which this task was told not to change). One indexed lookup on a path that already performs an
`INSERT`, two `COUNT`s and up to three job enqueues is why both socket events are gated rather than only the
unsafe one.

**Why the narrowing had to go INSIDE the relation, not after the fetch.** The dashboard treats a short page as
the end of the feed: `app/javascript/dashboard/store/modules/notifications/actions.js:21` commits
`SET_ALL_NOTIFICATIONS_LOADED` whenever `payload.length < 15`, and that flag is never cleared for the session.
A post-fetch reject — load 15, drop the unauthorized ones, return 9 — would therefore have silently truncated
the feed for the rest of the session, and the member would never see page 2. Narrowing before `.page`/`.per`
keeps pages full and keeps `count` describing the same set, which is asserted (19 authorized notifications
yield a full page of 15 and a count of 19).

Indexes that serve it, from `db/schema.rb` — **no new index is required**:

| Side | Index | Note |
| --- | --- | --- |
| notifications (driving) | `idx_notifications_performance` on `(user_id, account_id, snoozed_until, read_at)` (`:1592`) | exactly the four conditions the finder applies before the narrowing |
| notifications (`IN` probe) | `(primary_actor_type, primary_actor_id)` (`:1590`) | named `uniq_…` but **not** a unique index |
| conversations, `:mine` | `(assignee_id, account_id)` (`:1109`) | exact match for the predicate |
| conversations, `:unassigned_and_mine` | `(assignee_id, account_id)` + `(account_id)` (`:1108`) | the bot-nullity term has no index (`assignee_agent_bot_id`, `:1101`) and is a filter, never a seek |

**Why a relation and not a policy call per row.** A per-record `ConversationPolicy#show?` costs 2–3 queries
steady state (inbox membership, plus an un-memoized entitlement-override read through
`Billing::Entitlements`), i.e. roughly 30–45 extra queries for one 15-row page. The relation shape costs one
subselect.

**Pre-existing and not changed by this work:** the notification index is already an N+1 before any of this.
The jbuilder calls `primary_actor.push_event_data`, `secondary_actor&.push_event_data` and
`push_message_body` per row, and the finder preloads nothing. This change neither worsens nor fixes that; see §6.

---

## 6. Known limitations, stated rather than hidden

1. **A browser that already fetched a notification keeps rendering it.** This is a read-time design, so
   nothing on the server can evict a row from a store the client already holds. `CLEAR_NOTIFICATIONS`
   (`app/javascript/dashboard/store/modules/notifications/mutations.js:10-13`) is the only thing that empties
   `$state.records`, and a reconnect refetches page 1 and *merges* rather than replaces. So after a permission
   is revoked mid-session the stale row — including its `pushMessageBody` — stays on screen until the user
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
   notification now also pays the 1–4 query gate above. Both fan-outs pre-date this change — the counts and the
   broadcasts were already per row — but each unit is now slightly more expensive. Neither is on a request
   path: `destroy_all` and the cron both run on Sidekiq.
4. **`set_primary_actor` resolves a conversation id without account scoping**
   (`notifications_controller.rb:64-69`). The resolved record is only used as a filter on the caller's own
   rows, so it is an oracle at worst rather than a data leak. Pre-existing; not touched.
5. **The inbox/team ceiling is not applied to the feed.** This closure narrows by the *capability*, which is
   what the decision named. A member removed from an inbox still sees notifications for that inbox's
   conversations. That is a distinct, pre-existing gap that predates DECISION 1, and closing it would require
   expressing `ConversationPolicy#show?`'s inbox-**or**-team ceiling as a relation — a second interpretation of
   a rule this work was told not to reinterpret. Recorded for a separate decision.
6. **The notification index's pre-existing N+1** (§5). Fixing it means adding preloads to an OSS finder and
   would change query counts other specs may assert; it is unrelated to authorization.
7. **Deliveries are not read surfaces and were not gated.** Push/FCM and e-mail fire from
   `after_create_commit` (`app/models/notification.rb:52`), at which point `NotificationBuilder` has already
   established authorization. A member narrowed *after* creation will not receive a new delivery, because no
   new notification is created for them.
8. **A notification about something that is neither a Conversation nor a Message passes through, and the index
   cannot render it.** `Notification#push_message_title` calls `display_id` on the primary actor
   unconditionally, so such a row raises `NoMethodError` in `index.json.jbuilder` — before and after this
   change alike, since the unnarrowed finder returned it too. The pass-through is what the decision asks for
   ("notifications not associated with a Conversation must remain unaffected") and nothing creates such a row
   today; the renderer fragility is pre-existing and separate.

9. **A correction to `04-decisions-implemented.md`.** That document's architecture notes asserted that no OSS
   `app/` file references a constant defined only under `custom/`. That is **wrong**, and the real invariant is
   narrower: no `app/` file names a `Custom::`-prefixed constant. Four unprefixed `custom/` constants are
   already referenced from `app/` — `Audience::Usage` (`app/views/api/v1/models/_custom_filter.json.jbuilder`),
   `Channels::ConnectionState` (`app/views/api/v1/models/_inbox.json.jbuilder`), `Operations::SignalRecorder`
   (`app/models/campaign.rb`) and `Whatsapp::DeliveryFailure`
   (`app/controllers/api/v1/accounts/conversations/messages_controller.rb`). This closure needs no such
   reference — all four consumers live under `custom/` — but the earlier claim should not stand.
