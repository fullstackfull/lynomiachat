# P-FINAL — production UAT runbook for the combined release

**This document is written to be executed on the production server by an operator, with the service owner
present, AFTER a go decision. Nothing in it has been executed. No step here was run during P-FINAL
development: production was not touched, no flag was activated, no WhatsApp message was sent, and no Stripe
configuration was changed.**

The release it covers is one deploy crossing five bodies of work:

| | what it adds |
|---|---|
| P8 | analytics: conversations, WhatsApp, campaigns, automation, flows, commerce; the contact activity timeline |
| P9 | support cases with SLA targets, and the Super Admin Operations Center |
| P10 | multi-valued contact identity, merge safety, channel capability and connection state |
| P11 | plans, entitlements, subscriptions, usage limits, the Super Admin override surface |
| P-FINAL.CR | the independently authored replacement for the audit trail, named permission sets, campaign recipient outcomes and WhatsApp delivery-report routing |

Read `docs/p-final/09-rollback-and-rollout.md` before starting: it holds the decision tree for whether a problem
is a lever or a rollback, and `deployment/ROLLBACK.md` holds the procedure.

---

## 0. Before anything

| | |
|---|---|
| who | the operator, with the service owner reachable for every GO/NO-GO marked below |
| when | a window with the lowest conversation volume for this installation's customers, and **not** inside a customer's campaign window |
| how long | allow 90 minutes for §1–§3 and a further 2 hours for §4–§12. §13 (the real WhatsApp send) needs a cooperating recipient |
| access | root on the application server; the Super Admin console; a browser signed in as an administrator of a real test account; a browser signed in as an agent of that same account |

Have these open and ready **before** the deploy:

```bash
# the revision you intend to ship, from the release branch, written down
git -C /home/chatwoot/chatwoot rev-parse @{u}

# the revision currently serving, written down -- this is what a rollback goes back to
git -C /home/chatwoot/chatwoot rev-parse HEAD

# the queues, before
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec rails runner \
  \"require 'sidekiq/api'; puts Sidekiq::Stats.new.queues.inspect\""
```

Write both revisions into `deployment/INCIDENT.md` now, not later.

**Create a test account for this runbook, or nominate one.** Several steps below write data. Do them on an
account whose conversations nobody is paid to answer. Note its id.

---

## 1. Deploy

```bash
# EXPECT_SHA makes the deploy refuse to run if the branch moved since you read it in §0.
EXPECT_SHA=<the revision from §0> bash /home/chatwoot/chatwoot/deployment/deploy.sh
```

The script prints the outgoing revision and the pre-deploy dump path at the start and at the end. **Write both
down.** A rollback needs them and `git reflog` is a poor substitute at 3am.

**GO/NO-GO 1.** If the script aborts, stop and read why before retrying. The two aborts that matter:

- an INVALID index — a previous `CREATE INDEX CONCURRENTLY` was interrupted. `docs/p-final/03-migration-review.md`
  §4 says how to drop and rebuild it. Do that, then re-run.
- a migration failure — **do not roll the code back first.** Read `deployment/ROLLBACK.md` → *What a rollback
  cannot undo*.

---

## 2. Does it serve at all

```bash
curl -fsS http://127.0.0.1:3000/api; echo
systemctl is-active chatwoot-web.1.service chatwoot-worker.1.service
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec rails runner \
  'puts ChatwootApp.extensions.inspect; puts ChatwootApp.enterprise?.inspect'"
```

Expected: `200` from the API, both units `active`, `[\"custom\"]` and `false`.

**GO/NO-GO 2.** Anything else is a rollback, now, per `deployment/ROLLBACK.md`.

---

## 3. The boot the test suite cannot prove

The one failure mode a green suite does not catch is a constant that only resolves in production's eager-load
mode. Force it:

```bash
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production \
  bundle exec rails runner 'Rails.application.eager_load!; puts \"eager load OK\"'"
```

Then open the dashboard in a browser and sign in as the administrator. The sign-in itself exercises the new
session audit path.

**GO/NO-GO 3.** A `NameError` or `LoadError` here is a rollback.

---

## 4. The audit trail — read (package A)

As the administrator of the test account, open **Settings → Audit Logs**.

| step | expected |
|---|---|
| the page loads | rows, newest first, with a total and a pager |
| your own sign-in from §3 appears | a `user: sign_in` row naming you |
| filter by type | only that type comes back, and the total changes with it |
| filter by a date range that excludes everything | an empty page with the page's own empty state, **not** an error |
| set the page to 50 beyond the end | an empty list, the real total, no error |
| sort oldest-first | the order reverses |

Then, as an **agent** of the same account, try to reach the same page. Expected: refused. The menu entry should
not be there, and the API should refuse even if the URL is typed by hand.

**If the account does not have the `audit_logs` capability**, the page must show its empty state rather than an
error. Confirm which it is for your test account in the Super Admin console before reading this as a defect.

---

## 5. The audit trail — capture (package B)

As the administrator, do each of these and then re-read the trail. Each must produce exactly one entry.

| do this | expect a row for |
|---|---|
| change an account setting | the account, with the field and both values |
| create an inbox, rename it, delete it | three rows, three different actions |
| add an agent to the inbox, then remove them | two rows naming the member and the inbox |
| create a team, add a member, remove them, delete the team | four rows |
| create and delete an automation rule, a macro, a webhook | six rows |
| delete a conversation | one row naming the conversation by the number the interface shows |
| delete a message whose text you will recognise | one row naming the conversation — **and the text must not appear anywhere in the row** |
| sign out, then sign in | two rows |

**The credential check, which matters most.** Change a non-credential field on a WhatsApp inbox's configuration
(its name). Expect a row. Then change the channel's API key. Expect either no row or a row that says the
credential changed — and in **neither** case may the old or the new value appear. Read the raw row to be sure:

```bash
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec rails runner \
  'puts Custom::AuditLog.where(auditable_type: \"Inbox\").order(id: :desc).limit(3).pluck(:audited_changes).inspect'"
```

**GO/NO-GO 4.** A credential value in `audited_changes` is a stop. It is readable by every administrator of the
account.

---

## 6. Named permission sets (package C)

As the administrator, **Settings → Agents / Roles**:

| step | expected |
|---|---|
| create a set with one capability | it is listed with that capability |
| create a set with no name | refused, with a message naming the problem |
| attach it to an existing agent | the agent's row shows it |
| sign in as that agent | they can do what the set grants and nothing else |
| detach it | the agent can no longer do it |
| delete a set that two members hold | **both members still exist, still belong to the account, and simply have no set** |

**GO/NO-GO 5.** If deleting a set removes or disables a member, stop. That is a data-loss defect.

Then the capability that reaches Commerce: attach a set holding `commerce_order_manage` to an agent and confirm
they can act on an order; remove it and confirm they cannot. Repeat for `support_ticket_manage` against a
support case, and `contact_manage` against contact administration.

---

## 7. P9 — support cases and the Operations Center

| step | expected |
|---|---|
| create a case from a conversation | it appears in the cases list with a reference number |
| set an SLA policy with a short resolution target, and let it pass | the case shows as overdue, and the Operations Center counts it |
| Super Admin → Operations | the account health page renders, each component with its own status, no "score" |
| an account with no inbox | its channels column reads as not configured rather than healthy |

The account health page is the one with a measured query budget. If it is visibly slow, note the page size and
say so; it should not grow a query per row.

---

## 8. P10 — identity, merge and channel state

| step | expected |
|---|---|
| add a second phone number to a contact | both are listed in the identities panel |
| send an inbound message from the second number | it lands on the same contact, not a new one |
| add an identity that already belongs to another contact | refused, naming the other contact |
| merge two contacts | conversations, orders, cases, campaign recipients and CSAT responses all survive on the surviving contact |
| read the trail afterwards | a `contact.merged` row naming who did it |
| Settings → Inboxes | each channel shows a connection state, and a channel that cannot report one says so rather than showing green |

**GO/NO-GO 6.** If a merge destroys a campaign recipient, an order, a case or a CSAT response, stop. That is
irreversible customer data.

---

## 9. P11 — plans, entitlements and billing

Do this **without** configuring production Stripe. The manual-subscription path is enough for UAT.

| step | expected |
|---|---|
| Super Admin → Plans | plans list with their features, limits and channel entitlements |
| try to narrow a plan an account is billed on | **refused**, with a message naming the account count and telling you to create a new plan or grant an override |
| widen the same plan | allowed |
| move an account's subscription to a smaller plan | allowed — this is how a downgrade happens |
| Super Admin → account → grant an override | the account gains the capability, and the trail shows a `billing.override_granted` row naming the Super Admin |
| revoke it | the capability goes, and a second row appears |
| as an administrator of a limited account, open the billing page | the plan, the usage and the limits shown honestly |
| as an **agent** of that account, open the same page | the commercial detail is not shown |

**Stripe stays unconfigured for this runbook.** When it is configured later, that is its own change with its own
go decision: live keys, the webhook endpoint and its signing secret, and a first real checkout against a test
card. Do not fold it into this deploy.

---

## 10. P8 — analytics and the timeline

| step | expected |
|---|---|
| open each analytics family (conversations, WhatsApp, campaigns, automation, flows, commerce) | each renders, with a date range and the filters |
| a range with no data | an honest empty state, not zeros presented as facts |
| a contact's activity timeline | events in order, paginated |
| the campaign analytics family, filtered to one campaign | its figures match that campaign's own page — see §11 |

---

## 11. Campaign recipient outcomes (packages D and E) — the careful part

**This section needs a real WhatsApp send to be complete. Do §11a and §11b first; §13 is the gated send.**

### 11a. Without sending anything

Open a campaign that has already run (if the installation has one) and compare its own analytics page against
the account-wide campaign analytics filtered to it over a window containing it. **The sent, delivered, read,
failed and skipped figures must match between the two views.** They are computed by different code and a
disagreement is a defect.

On the campaign's own page confirm: the audience total, the per-state tabs with their counts, the recipient
table paginating at 25, and a reason shown for each failed and each skipped recipient. No reason may contain a
phone number.

### 11b. The read-before-delivered rule, without a provider

```bash
# On the test account only. Creates one recipient, applies two reports out of order, then reports what the
# record says. Rolled back at the end -- nothing persists.
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec rails runner '
ActiveRecord::Base.transaction do
  a = Account.find(<TEST ACCOUNT ID>)
  c = a.contacts.first
  i = a.inboxes.first
  camp = a.campaigns.create!(title: \"UAT\", message: \"x\", inbox: i, campaign_type: :one_off)
  r = CampaignRecipient.create!(account: a, campaign: camp, contact: c, inbox: i,
                                source_id: \"uat.\#{SecureRandom.hex(4)}\", status: :sent, sent_at: Time.current)
  r.record_outcome!(\"read\", reported_at: Time.current)
  puts \"after read:      status=\#{r.reload.status} delivered_at=\#{r.delivered_at.inspect} read_at=\#{r.read_at.present?}\"
  r.record_outcome!(\"delivered\", reported_at: Time.current)
  puts \"after delivered: status=\#{r.reload.status} delivered_at=\#{r.delivered_at.present?}\"
  r.record_outcome!(\"failed\", reported_at: Time.current, error_code: \"131049\")
  puts \"after failure:   status=\#{r.reload.status} failed_at=\#{r.failed_at.inspect}\"
  raise ActiveRecord::Rollback
end'"
```

Expected, exactly:

```
after read:      status=read delivered_at=nil read_at=true
after delivered: status=read delivered_at=true
after failure:   status=read failed_at=nil
```

That is the whole rule: a read recipient stays read, a late delivery backfills its timestamp without demoting
it, and a failure reported after a delivery is dropped rather than recorded. If the third line shows
`status=failed`, the campaign failure count is wrong and this is a stop.

---

## 12. Tenant isolation, on the real installation

With two real accounts, A and B, and an administrator of A signed in, try to reach each of these with B's ids,
by typing the URL:

| surface | expected |
|---|---|
| the audit trail, with B's account id and B's members as the actor filter | nothing of B's, under any filter |
| a permission set of B's, read / update / delete / attach | refused |
| a campaign of B's, both analytics endpoints | `404` |
| the account-wide campaign analytics | no recipient of B's in any count, series or breakdown |
| a member of B's, update | refused |

**GO/NO-GO 7.** A single leak here is a stop, whatever else is green.

---

## 13. The real WhatsApp template send — GATED, and last

**Do not reach this step without the service owner's explicit go, and do not send to anyone who has not agreed
to receive it.** Meta has what is sent and no rollback recalls it.

Preconditions: an approved template on the test account's WhatsApp number, a cooperating recipient who has
messaged that number inside the last 24 hours or accepts a template, and the `whatsapp_campaign` capability on
the test account.

1. Create a one-off campaign on the test account, audience = one label containing only the cooperating contact.
2. Run it.
3. Immediately open the campaign's analytics page. Expect the recipient as **sent**, with the rendered text.
4. Wait for Meta's reports. Expect the recipient to reach **delivered**, then **read** once the recipient opens
   it. The page polls every five seconds while the campaign is processing.
5. Ask the recipient to tap a button or pick a list row if the template has them. Expect the inbound reply to
   land in the conversation, and — for a flow — to branch on the option's id.
6. Re-check §11a's cross-view comparison. The two views must agree on the new figures.

Then the failure path, which is worth seeing once: run a second campaign whose audience contains a contact with
a number that is not on WhatsApp. Expect that recipient **failed**, with Meta's own code and reason visible in
the recipient table.

**If a recipient stays at `sent` for more than fifteen minutes** while Meta's own Manager shows the message
delivered, the delivery-report routing is not reaching the recipient. That is a defect in package E; capture the
message id and the webhook log and raise it. It is not a rollback on its own — the message was delivered, only
the reporting is wrong.

---

## 14. After UAT

1. Record the outcome in `deployment/INCIDENT.md`: the revision, the dump path, every GO/NO-GO and its answer,
   and anything you noted.
2. Delete the test data you created on the test account, or say in the record that you left it.
3. Re-check the queues:

```bash
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec rails runner \
  \"require 'sidekiq/api'; puts Sidekiq::Stats.new.queues.inspect; puts Sidekiq::RetrySet.new.size\""
```

A growing retry set after the deploy is a signal: read what is retrying before calling the deploy done.

---

## 15. What is NOT in this runbook, and why

- **Stripe in production.** Its own change, its own go decision (§9).
- **Activating a capability for a real customer account.** Entitlements are commercial decisions, not UAT steps.
- **Load testing.** The query budgets were measured in development
  (`docs/p-final/06-clean-code-review.md` §performance). Production load behaviour is observed, not rehearsed.
- **Provider reconnection or callback changes at Meta.** A phone-level `override_callback_uri` takes precedence
  over the app-level callback and is invisible in the Meta dashboard; changing one is a deliberate, separate act.
- **Anything that mutates another customer's data.** Every write above is on the nominated test account.

---

## Before the restart: quiet the workers

`deployment/deploy.sh` stage 6b now quiets `chatwoot-worker.1.service` and waits for the in-flight set to
drain before the restart, up to 60 seconds. Watch it, and do not skip it.

Two reasons. A restart under load interrupts jobs mid-flight; Sidekiq pushes an interrupted job back for retry,
so nothing is lost, but a job that had already made a provider call is retried from the top — which for a
campaign send means a second WhatsApp message to a real person. And this release deletes
`Campaigns::UpdateRecipientStatusJob`, which the previous revision enqueued with a two-second delay and up to
five retries, so instances are sitting in the scheduled and retry sets at the moment of the restart. Draining
first lets the old code consume its own jobs; not draining leaves them raising `NameError` until they reach the
dead set.

**What to check**

```
# before the restart, expect: drained
# after the restart, expect dead to be unchanged from the pre-deploy number
sudo -u <app> RAILS_ENV=production bundle exec rails runner \
  "require 'sidekiq/api'; s = Sidekiq::Stats.new;
   puts({ busy: s.workers_size, enqueued: s.enqueued, scheduled: s.scheduled_size,
          retry: s.retry_size, dead: s.dead_size }.inspect)"
```

**If the dead set grew after the deploy**, list it and check what the entries are. Entries naming
`Campaigns::UpdateRecipientStatusJob` are expected and can be deleted: the class is gone on purpose, and
`Whatsapp::DeliveryReport` now resolves a report against the recipient row directly, so the case that job
covered no longer arises (`docs/p-final/03-migration-review.md` §8.1). Entries naming anything else are not
expected and are a reason to stop and read them before going further.
