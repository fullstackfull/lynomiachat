# Platform Support Desk — SLA and notifications

> Phase 0. Every "do not reuse" below names the line that makes reuse unsafe.

## 1. Why the tenant SLA machinery cannot simply be pointed at this module

| Piece | Status | Blocking line |
|---|---|---|
| `sla_policies` table | **Unusable** | `account_id` is `null: false` (`db/schema.rb:1742`) and `Support::SlaPolicy belongs_to :account` with no `optional:` (`custom/app/models/support/sla_policy.rb:16`). A Lynomia-owned policy has no account |
| `Support::Tickets::SlaClock` arithmetic | **Correct, worth copying by hand** | `#pause`/`#resume` (`custom/app/services/support/tickets/sla_clock.rb:41-59`) is the right algebra; the class is bound to `@ticket.sla_policy` of the tenant model |
| Business-hours calculation | **Not available** | `business_hours_applicable?` requires `@ticket.inbox.working_hours_enabled?` (`sla_clock.rb:62-69`); `configure_working_hours` is driven from `inbox.working_hours` and `inbox.timezone` (`:84-90`), and `working_hours` exists only on an inbox (`app/helpers/reporting_event_helper.rb:3-9,44`). This desk has no inbox |
| The SLA sweep job | **New, same shape** | The existing sweep is account-scoped and reads `support_tickets` |

So: new table, new clock class with the same algebra, calendar time in V1.

## 2. Policies and how a plan selects one, without naming a plan

`platform_support_sla_policies` (`02-data-model.md` §10). Resolution at ticket creation:

```
policy = PlatformSupport::SlaPolicy.active.find_by(billing_plan_id: account_plan_id)
      || PlatformSupport::SlaPolicy.active.find_by(billing_plan_id: nil)
```

**No plan name appears anywhere.** The key is `billing_plans.id`, which is the only stable key the table
offers: `billing_plans` has `name` (free text, mutable), `description`, `position`, `features` and
`channel_entitlements`, and **no tier or code column** (`db/schema.rb:341-359`). A string match on `name`
would silently stop matching the first time somebody renames a plan in Super Admin.

Two consequences worth stating:

- A plan with no policy row falls back to the default row. A desk with no default row applies **no SLA**, and
  the UI says "no target set" rather than displaying a zero (the same honesty rule `Support::SlaPolicy`
  enforces with `at_least_one_threshold`, `custom/app/models/support/sla_policy.rb:29-33`).
- `plan_id_at_creation` is snapshotted on the ticket, so an upgrade mid-ticket does not retroactively change a
  commitment Lynomia already made. The policy is resolved once, at creation.

Thresholds are integer **seconds** rather than the tenant table's `float` (`db/schema.rb:1739-1746`): sub-second
SLA precision is meaningless, and the float column already forced a `.round` in the existing clock
(`sla_clock.rb:89`).

## 3. Three clocks

| Clock | Starts | Stops | Pauses on `waiting_on_customer` |
|---|---|---|---|
| First response | ticket creation | the first **public** operator reply (an internal note does not satisfy it) | yes |
| Next response | each customer reply on an active ticket | the next public operator reply | yes |
| Resolution | ticket creation | `resolved_at` | **yes** |

Targets are measured from *now* when the policy attaches, never retroactively from an older `created_at` — the
existing module's rule, and its reason is the right one: *"a due time invented backwards is a commitment nobody
made"* (`sla_clock.rb:21-23`).

### Pausing — decided explicitly, as the brief required

**`waiting_on_customer` pauses all three clocks. `waiting_on_lynomia` pauses none.**

- Pausing resolution while waiting on the customer is the brief's expectation and is correct: the remaining
  time is not Lynomia's to spend.
- Pausing the response clocks too follows from the same logic — there is nothing to respond to.
- `waiting_on_lynomia` pausing nothing is the non-obvious half, and it is deliberate: waiting on ourselves is
  our own delay. That is the existing module's recorded reasoning (`custom/app/models/support/ticket.rb:29-30`)
  and `SLA_PAUSING_STATUSES = %w[waiting_on_customer]` (`:37`) is its one-element list. Same answer here.

Resume moves every outstanding due time forward by exactly the paused duration and accumulates the total into
`sla_paused_seconds`, so the pause is **visible rather than inferred from a gap** — the same shape as
`sla_clock.rb:47-58`. That column is what makes §6's analytics honest.

### Reopen

A customer replying to a `resolved` ticket reopens it. On reopen: a new resolution target from the reopen
instant, `resolution_breached_at` cleared (the new target has its own outcome), and a satisfied first response
stays satisfied. Identical to `SlaClock#restart_resolution` (`sla_clock.rb:30-37`), and for the same reason.

### Breach detection

A periodic job over the two partial indexes (`02-data-model.md` §2), writing
`sla_first_response_breached` / `sla_resolution_breached` events and stamping the breach columns. Idempotent by
construction: the partial index excludes rows whose breach is already recorded, so a re-run writes nothing —
the same arrangement the existing `overdue` scope relies on, with its recorded measurement
(23.697 ms → 12.826 ms at 500 000 rows, `custom/app/models/support/ticket.rb:74-86`).

**A warning event fires at 75% of the window** for `urgent` and `high` tickets only. Warning on every priority
turns the SLA-at-risk queue into noise, and the queue is the thing the warning exists to populate.

## 4. Tenant notifications: email plus a derived badge, and NOT the `notifications` table

The brief asked for in-app and email. The recommendation is **email through ActionMailer, plus an in-app
indicator derived from the ticket's own columns** (`04-customer-ux.md` §6) — and specifically **no rows in the
`notifications` table in V1**. Four reasons, each a line of code:

1. **`PRIMARY_ACTORS = ['Conversation']`** (`app/models/notification.rb:56`) and the index serializer calls
   `notification.primary_actor.push_event_data` **unconditionally**
   (`app/views/api/v1/accounts/notifications/index.json.jbuilder:17`). A new actor type must implement that
   method and be added to the constant — which is fine, but it is the *least* of it.
2. **The read-time narrowing passes a non-Conversation primary actor straight through, with zero
   authorization.** `Notifications::ConversationVisibility` returns the notification unchanged when the actor
   is neither a Conversation nor a Message (`custom/app/services/notifications/conversation_visibility.rb:60,86-88,98`).
   So a platform-support notification row would be delivered on the strength of its `user_id` column alone,
   bypassing the narrowing the previous phase was built to add. That is the exact class of hole that phase
   closed; reopening it for a convenience feature is not a trade worth making.
3. **`NotificationSetting` derives its email and push flag vocabularies from
   `Notification::NOTIFICATION_TYPES`** (`app/models/notification_setting.rb:31-35`). Adding types therefore
   adds preference flags to the tenant's notification-settings UI automatically — putting "Lynomia support
   reply" toggles into a list that is otherwise entirely about conversations, with no code asking for it.
4. **A feed row is a second copy of the truth.** The derived indicator reads
   `last_operator_message_at` vs `customer_last_viewed_at` on the ticket itself, so it cannot disagree with the
   thread. The `notifications` table has **no foreign keys at all** (`grep add_foreign_key db/schema.rb | grep -i notif`
   → empty) and its `uniq_primary_actor_per_account_notifications` index is **not unique** despite the name
   (`db/schema.rb:1590`), so orphaned and duplicated rows are both possible, and the dedup job keys on
   `user_id` + `primary_actor_id` while **ignoring type** (`app/jobs/notification/remove_duplicate_notification_job.rb:7-15`) —
   which means a platform ticket and a conversation sharing an id could deduplicate each other.

Reason 4 alone would be enough; reason 2 makes it a security decision rather than a design preference.

> **Decision D-6 needs your approval.** If you want these in the notification bell, that is Phase 2 and it
> carries a prerequisite: `ConversationVisibility` must stop passing unknown actor types through, replaced by a
> positive allow-list that authorizes each known type and denies the rest. That is a change to shipped
> notification code and should be its own reviewed phase, not a side effect of this module.

### Emails sent

| Trigger | To | Notes |
|---|---|---|
| Ticket created | the reporter | The receipt, carrying `LYN-000123` |
| Operator public reply | the reporter, and the account's administrators when the reporter is not one | The one email that matters |
| Status → `resolved` | the reporter | Includes "reply here if it is not fixed" |
| Status → `waiting_on_customer` | the reporter | This is the only status change that *asks* something of the customer |

Deliberately **not** emailed to the customer: assignment, priority change, category change, any SLA event,
internal notes, and `waiting_on_lynomia` (it asks nothing). An email per status change is how a support desk
teaches people to filter its mail.

### Operator emails

| Trigger | To |
|---|---|
| New ticket | the configured Lynomia support alias |
| New ticket, `urgent` | the alias, flagged in the subject |
| Customer reply | the assignee; the alias when unassigned |
| SLA warning (75%, urgent/high) | the assignee; the alias when unassigned |
| SLA breach | the assignee **and** the alias |

The alias is an `InstallationConfig` value, which is the existing store for installation-level configuration
(`/super_admin/installation_configs`) — not an ENV var, so it is changeable without a deploy.

The Super Admin surface has no notification feed of any kind, so operator in-app awareness is the queue counts
on the desk (`05-super-admin-operations.md` §2). That is sufficient for a surface an operator opens
deliberately.

### Deduplication and delivery

- Emails are enqueued from `after_create_commit` on the message, and from the status-change service — never
  from a model callback that could fire inside a failed transaction.
- One email per event; no digesting in V1. A burst is bounded by the write rate limits
  (`03-authorization-security.md` §8).
- Delivery failure is logged and does not fail the request: a bounced notification must never prevent a support
  reply from being saved.
- No push and no Slack in V1. Both are additive — a new delivery method against the same trigger set — which
  is why the trigger set above is defined independently of how it is delivered.

## 5. The business-hours limitation, stated plainly

V1 SLAs run on **calendar time**. The UI labels them as such ("resolution target: 8 calendar hours"), on both
surfaces.

Why it is not simply reused: the entire business-hours path is inbox-scoped. `WorkingHours::Config` is set from
`inbox.working_hours` and `inbox.timezone` (`sla_clock.rb:84-90`), the gem's day map comes from
`ReportingEventHelper#configure_working_hours` (`app/helpers/reporting_event_helper.rb:3-9,44`), and the rows live
in `working_hours` keyed on an inbox. Lynomia's desk has no inbox, and inventing one to hold a calendar is the
fake-infrastructure the brief forbids.

What Phase 2 would add: an installation-level support calendar (weekday windows, a timezone and a holiday
list) plus a calculator that takes those directly instead of an inbox. The clock class's `due_at` is the single
seam — one method, one branch — which is why the arithmetic is worth copying rather than wrapping.

> **Decision D-7 needs your approval.** Calendar time means a Thursday-evening ticket under an 8-hour target
> breaches by Friday morning regardless of whether anyone was working. Either the V1 thresholds are set
> generously enough to absorb that (e.g. first response in 24 calendar hours rather than 4 business hours), or
> the calendar moves into V1. Setting the thresholds generously is the recommendation: it is honest, it needs
> no new mechanism, and it can be tightened the day the calendar exists.

## 6. What the data model can and cannot measure honestly

The brief: *"Do not implement misleading averages if the data model cannot support them accurately."*

**Supportable accurately:**

| Metric | From |
|---|---|
| First response time | `first_responded_at - created_at`, minus the paused portion |
| Resolution time | `resolved_at - created_at`, minus `sla_paused_seconds` |
| First-response and resolution breach rate | the breach columns, which are stamped and never cleared except on reopen |
| Volume by category, priority, account, plan-at-creation | ticket columns, all indexed or snapshotted |
| Reopen rate | count of `reopened` events per ticket |
| Backlog age distribution | `last_activity_at` over active statuses |
| Tickets per account per period | the account scope |

Subtracting the pause is the whole reason `sla_paused_seconds` exists in V1 even though pausing is a small
feature: without it, every resolution-time average silently includes time spent waiting for the customer, and
the resulting number flatters or damns Lynomia at random.

**Not supportable, and therefore not built:**

| Metric | Why not |
|---|---|
| Average handle time | No time tracking. There is no record of how long an operator spent, only of elapsed wall time |
| CSAT / satisfaction | No survey exists. A "resolved" status is not satisfaction |
| Per-operator productivity | Reply counts measure typing, not resolution; attributing a resolution to one operator is wrong whenever a ticket was reassigned |
| "Time to first *human* response" distinct from first response | Every reply in V1 is human, so this is the same number. It would diverge only with automation, which does not exist here |
| Median anything, before enough tickets exist | A median over single digits is noise. The dashboard shows counts until a stated minimum is met, and says so |

The last row is a UI commitment, not a technical limit, and it is the one most likely to be dropped under time
pressure. It is listed as a review gate in `09-implementation-plan.md` §6.
