# Platform Support Desk — UAT, pilot controls, and the rollout/rollback runbook

> Written against the frozen contract in `12-refresh-against-product-refinement.md`, which supersedes `00`–`11`
> on any disagreement. It replaces `10-uat-plan.md` wherever the two differ, for the same reason: `10` was
> written before the contract froze and before three of its assumptions were cut (§B-6, §B-7, §B-8).
>
> **This document schedules nothing and touches nothing.** Account 21 is not touched now (§11.4). No policy row,
> no agent row and no support alias is created by any step below; each of those is an owner decision and the
> runbook says what the desk does until it arrives.

---

## 1. What UAT has to establish, and what it cannot

UAT is the last place a wrong answer is cheap. It is not a second test suite: the automated gate in §10 of the
contract already proves the properties that can be asserted, and repeating them by hand buys nothing. UAT
exists for the four things a spec cannot reach.

| # | What only a human can establish | Why the suite cannot |
|---|---|---|
| **U-1** | That a customer who is confused and annoyed can find the desk, raise a useful ticket and understand what each status means | The suite can prove the route renders; it cannot prove the copy is comprehensible, in English or in Arabic |
| **U-2** | That an operator can work the queue end to end without needing a second window — triage, reply, note, assign, read the account's billing context | The suite proves each endpoint; the workflow is the product |
| **U-3** | That nothing on either surface discloses what it must not: an operator's name, an internal note, an SLA target, another account's anything | Structural proofs exist. A human reading the rendered page is the check on the renderer, which is where a leak would look innocent |
| **U-4** | That the honest-emptiness states read as deliberate rather than broken: no SLA policy, no support alias, no agent row, no `DOCUMENTATION_URL` | These are the four states the installation is actually in on day one, and every one of them is a blank space somebody could mistake for a bug |

**Out of scope for UAT, stated so it is not attempted:** business-hours SLA (there is none in V1 — calendar time,
§B-6/D-7), the next-response clock (cut), the 75% warning (cut), ticket↔signal links (cut, §B-8), push
notifications and Slack (not built), malware scanning (none exists, and that is a recorded limitation, not a
gap to test), and any load testing against production data.

---

## 2. The environment UAT runs in

| Item | Decision |
|---|---|
| Where | A staging installation with its own database and its own Redis. **Not production, not Account 21, no production data copied in** |
| Accounts | Three accounts created for the purpose: **A** (plan with its own SLA policy row), **B** (plan with no policy row, so it falls back to the default), **C** (no subscription at all). Plus **D**, created and then deleted, for the orphan case |
| Users | Per account: one administrator, one agent who reports a ticket, one agent who reports nothing (the bystander every isolation check needs), one custom-role holder |
| Staff | Two `PlatformSupport::Agent` rows created **by an operator through the Super Admin surface**, one `agent` and one `lead`, plus one Super Admin left deliberately **without** a row |
| SLA policies | Created by the tester with **obviously synthetic** values — minutes, not hours — so a breach can be observed inside a session. These are test values and are never carried to production: production targets are owner data (D-7) |
| Support alias | Left **unset for the first pass** (U-4), then set to a staging mailbox for the second |
| Mail | Caught by a staging mail catcher. No message may leave the installation |

**The synthetic-values rule is load-bearing.** If a UAT policy row is ever copied into production, Lynomia has
committed to a target nobody chose. Every policy row created for UAT is named with a `UAT ` prefix, and step
R-0 of the rollout checklist is to confirm the production installation has none.

---

## 3. UAT scripts

Each script is a path through the product, with the state it must leave behind. A script fails if any step
needs an explanation that is not on the screen.

### S-1 — The customer path, English
1. Sign in as account A's **agent**. Find the desk from the sidebar without being told where it is.
2. Raise a ticket: pick a category, write a subject and a description, attach a screenshot.
3. Confirm the reference is shown, in the `LYN-000123` form, and that the receipt email arrives.
4. Read the thread. Confirm the status is `open` and that what each status means is discoverable.
5. Change the priority. Confirm it reads as a request, not a promise.
6. **Leaves behind:** one ticket with one attachment, owned by a non-administrator.

### S-2 — The customer path, Arabic and RTL
Repeat S-1 with the account locale set to Arabic. Every screen, the empty states, the attachment control, the
status labels and the contextual-help links. Mirrored layout, no clipped text, no Latin-only punctuation
sitting in the middle of an Arabic sentence.

### S-3 — The visibility rules, by hand
1. As account A's **administrator**: see the ticket S-1 created.
2. As account A's **bystander agent**: do not see it. The list is empty, not an error.
3. As the **custom-role holder**: identical to the bystander.
4. Paste the ticket's numeric id and then its `LYN-` reference into the URL as the bystander: **404 both times**,
   with the same page an id that never existed produces.
5. As account **B**'s administrator: paste account A's reference. 404.
6. **Leaves behind:** nothing. This script writes no data, which is itself the check.

### S-4 — The operator path
1. As the Super Admin **without** an agent row: open the desk. Confirm the explicit "you are not a support
   agent" state, and that no queue, no count and no ticket subject is visible behind it.
2. As the `agent`: work the queue. Triage the priority and category, assign to self, reply publicly, add an
   internal note, move the status, resolve.
3. Confirm the reply reaches the customer as **"Lynomia Support"** and the note does not reach them at all.
4. As the same `agent`: attempt to reassign the `lead`'s ticket. Refused.
5. As the `lead`: reassign it. Permitted.
6. Follow the Account 360 link both ways.
7. **Leaves behind:** one resolved ticket with a note and an internal event history.

### S-5 — The lifecycle
1. Reply as the customer to the resolved ticket from S-4. It **reopens**, the resolution clock restarts, and the
   first response stays satisfied.
2. Close it as the customer. Reply again: **422**, with the "open a new one" message.
3. Mark a ticket viewed; confirm the unread dot clears and does not come back on its own.

### S-6 — SLA, with synthetic minutes
1. Account A (own policy) and account B (default policy): confirm the two different targets attach at creation,
   and that both are labelled **calendar** time.
2. Account C (no subscription, and remove the default row): confirm **"No SLA policy applies"** rather than a
   zero or a dash.
3. Move a ticket to `waiting_on_customer`, wait, move it back: the due times have moved forward by the paused
   duration and the paused total is visible.
4. Move a ticket to `waiting_on_lynomia`: **nothing pauses**. This is the half a tester will assume is a bug;
   it is in the script so they ask.
5. Let one ticket pass its target. Confirm the sweep stamps the breach once, writes the `sla_*` event, that a
   re-run writes nothing, and that **the customer sees no trace of any of it**.

### S-7 — Notifications
1. As account A's agent, with the ticket from S-1 open in another tab, have an operator reply.
2. The bell count rises. Open the Inbox feed: the row is **not listed there** — by design (§5.6) — and the feed
   does not break, does not route anywhere wrong, and shows no other account's row.
3. Read the ticket on the Platform Support surface. Confirm the thread is the only place the reply appears.
4. Have the operator add an internal note: **no bell, no email, no event**.
5. Have the operator reply three times: the recipient ends with **one** row, not three.

### S-8 — The empty states (U-4)
Four passes, each with one thing unconfigured, confirming the surface says so rather than showing a blank:
no SLA policy row; no support alias; no `PlatformSupport::Agent` row; no `DOCUMENTATION_URL` (the help links
must render **nothing at all**, never a broken link).

### S-9 — Commercial states
1. Billing-lock account A. Confirm the desk still works: list, read, reply, attach, download.
2. Confirm the same account is still refused on an ordinary account endpoint, so the exemption is an exemption.
3. Administratively suspend account B. Confirm the desk is refused with the existing 401, unchanged.
4. Delete account D. Confirm its tickets survive for staff with the name snapshot, and that **no tenant can read
   them**.

### S-10 — Attachments, by hand
Upload each accepted type and one rejected type. Confirm the rejection names the limit and the accepted types.
Confirm an image displays inline and a text file downloads. Then, as the bystander agent and as account B,
paste the attachment URL: 404. Then paste the note attachment's URL as the ticket's own reporter: 404.

---

## 4. The exit criteria

UAT is complete when all ten scripts pass with no open defect in these classes, and **not otherwise**:

| Class | Rule |
|---|---|
| **Disclosure** | Zero. An operator name, an internal note, an SLA target, a `metadata` value or another account's data appearing anywhere on a tenant surface stops the release |
| **Authorization** | Zero. Any case where a bystander agent, another account, or a Super Admin without an agent row reaches something stops the release |
| **Honesty** | Zero invented values. A displayed SLA target with no policy row, a fallback support address, or a seeded agent stops the release |
| **Arabic/RTL** | Zero untranslated strings and zero broken layouts on the tenant surface. The staff surface is English-only by decision and is not a defect |
| **Workflow** | An operator completing S-4 without a second window. A step that needs a verbal explanation is a defect in the copy, logged and fixed before release |
| **Everything else** | Triaged. A cosmetic defect may ship with an owner's explicit note |

---

## 5. Pilot controls

**Account 21 is not touched now.** The pilot account is an owner decision (§11.4) and until it arrives nothing
is enabled for any real account.

What makes a pilot controllable here is a property of the design rather than a switch:

| Control | How it works |
|---|---|
| **No feature gate, deliberately** | The desk is never gated and never sold (§9), so there is no flag to flip per account. This is the right trade and it means the pilot control is **data**, not configuration |
| **The real control is the agent row** | With no `PlatformSupport::Agent` row, every staff action is refused. A desk nobody staffs collects tickets and answers none, which is worse than a desk nobody can see — so the pilot begins by creating the agent rows, not by enabling anything |
| **The second control is the navigation** | The two sidebar children are the only way a customer finds the desk. A pilot that is not ready to be seen is a pilot whose navigation entry has not shipped yet; the API being live without it is harmless because nothing links to it |
| **The third control is the bell** | Writing no `platform_support_reply` rows switches the in-app notification off entirely, with no other effect (§11.5). The ticket's own derived unread flag and the sidebar badge are independent of it |
| **The fourth control is the alias** | With no support alias configured, no operator email is sent. A pilot can therefore run queue-only, with operators working the desk deliberately rather than being paged |

**Pilot sequence, once the owner names the account:**
1. Create the `PlatformSupport::Agent` rows. Confirm the desk refuses staff actions before they exist and works
   after.
2. Create the SLA policy rows with the **owner's** values. Confirm a new ticket attaches the right one and that
   an account whose plan has no row falls back to the default.
3. Set the support alias. Confirm the first ticket's operator email arrives at it and nowhere else.
4. Ship the navigation entry for the pilot account's users.
5. Watch three things for the first week: the queue count, the breach count, and the log line
   `[LYNOMIA][PLATFORM_SUPPORT_OPERATOR_MAIL_UNDELIVERABLE]`, which means a message had no recipient.

**What the pilot must produce before a wider release:** a real first-response and resolution distribution, so
the owner's SLA values can be checked against what the desk actually does. Calendar time means a
Thursday-evening ticket under an eight-hour target breaches by Friday morning whether or not anybody was
working (D-7), and the pilot is where that becomes a number rather than a warning.

---

## 6. The rollout runbook

### R-0 — Before the deploy
| # | Check |
|---|---|
| 0.1 | The automated gate in §10 of the contract passes in full, on the merged branch, in one run |
| 0.2 | `bundle exec rails zeitwerk:check` → exit 0, and `bundle exec rubocop` → exit 0 |
| 0.3 | `rake lynomia:docs:seo_audit` → exit 0, 0 errors (the one new article, EN and AR) |
| 0.4 | `db/schema.rb` contains the six tables and **no change to any existing table** |
| 0.5 | `grep -rn "UAT " db/ config/` finds nothing, and the production installation has **zero** `platform_support_sla_policies` and **zero** `platform_support_agents` rows |
| 0.6 | `app/views/super_admin/application/_navigation.html.erb` has `"platform_support"` in the exclusion array **in the same commit** as the nav item, and the nav icon id exists in `_icons.html.erb` (§B-11 — omitting either breaks the sidebar on *every* Super Admin page) |
| 0.7 | No Platform Support string in `config/locales/*.yml` other than `en.yml`, and `platformSupport.json` is imported in both `en/index.js` and `ar/index.js` |

### R-1 — The deploy, in this order
1. **Migrations.** Six `CREATE TABLE`s, their indexes and their foreign keys. Additive only: no existing table
   is altered, so there is no lock on a hot table and no backfill.
2. **Code.** The models, policies, controllers, serializers, routes, SLA engine, mailer, notification changes
   and throttles ship together. **They cannot be split:** `Notifications::ConversationVisibility` resolves
   `PlatformSupport::TicketPolicy` on every notification-feed read, so code without the models would break the
   bell for every tenant. This is the single hardest ordering constraint in the release.
3. **The scheduled sweep.** Add the `PlatformSupport::SlaSweepJob` entry to `config/schedule.yml`. With no
   policy rows it finds nothing, so it is safe to enable before the targets exist.
4. **Nothing else.** No agent row, no policy row, no alias, no navigation for any account that is not the pilot.

### R-2 — The first ten minutes
| Watch | Healthy |
|---|---|
| `GET /api/v1/accounts/:id/notifications` error rate | Unchanged. This is the one existing endpoint the release touches, and a `NameError` here is the symptom of a split deploy (R-1.2) |
| The Super Admin sidebar, on any page | Renders. A failure here is §B-11 and is installation-wide |
| `[LYNOMIA][PLATFORM_SUPPORT_SLA_SWEEP]` | Absent, because there are no policy rows yet |
| Sidekiq `housekeeping` queue | Not growing |
| `platform_support_tickets` row count | Zero until the pilot opens one |

### R-3 — Rollback
Rollback is **code-only, and the data stays**. There are three cases and they are not the same.

| Case | Action |
|---|---|
| **Anything is wrong before a ticket exists** | Revert the code. The six tables are empty and additive; leaving them costs nothing and dropping them is the riskier operation. Remove the schedule entry |
| **Tickets exist and the desk must stop taking new ones** | Deactivate every `PlatformSupport::Agent` row (staff actions refuse) and remove the navigation entries (customers cannot reach the form). The existing tickets stay readable to staff through the Super Admin surface. **Do not drop a table and do not delete a ticket** — a customer's support history is theirs |
| **Something on the notification path is wrong** | Stop writing `platform_support_reply` rows. That alone switches the feature off (§11.5), with no effect on the ticket's own unread flag or the sidebar badge. Reverting `conversation_visibility.rb` and `notification.rb` **requires reverting the models with them**, for the reason in R-1.2 |

**What rollback must never do:**
- Drop a `platform_support_*` table that holds a row.
- Revert the `conversation_visibility.rb` branches while leaving the type in `Notification::PRIMARY_ACTORS`:
  that combination is a type on the allow-list with no rule, which is the one state the object must never be in.
- Revert `Notification::RemoveDuplicateNotificationJob` while Platform Support rows exist: the old key ignores
  `primary_actor_type` and would destroy conversation notifications that share a ticket id (§B-4).
- Re-add the `_navigation.html.erb` exclusion entry's removal without removing the nav item in the same commit.

### R-4 — After a week of the pilot
1. Read the real first-response and resolution distribution against the owner's targets (§5).
2. Read the breach count. A breach rate near zero means the targets are loose; near one means they are
   unreachable on calendar time. Either is a data answer, not a code change.
3. Confirm no `[LYNOMIA][PLATFORM_SUPPORT_OPERATOR_MAIL_UNDELIVERABLE]` lines remain.
4. Only then widen the navigation beyond the pilot account.

---

## 7. The owner decisions this document is still waiting on

Unchanged from §11 of the contract, repeated here because the runbook stops at each one:

| # | Decision | What the runbook does until it arrives |
|---|---|---|
| 1 | SLA target values per plan, in calendar hours | R-1.3 enables a sweep that finds nothing; both surfaces say "No SLA policy applies" |
| 2 | The Lynomia support alias | No operator email is sent; the staff desk states that none is configured |
| 3 | Who the first `PlatformSupport::Agent` rows are | Every staff action is refused, which is the correct fail-closed behaviour |
| 4 | The pilot account | Account 21 is untouched; §5's pilot sequence does not start |
| 5 | Whether the bell ships in V1 | Built with all six proofs; switched off by writing no rows |
