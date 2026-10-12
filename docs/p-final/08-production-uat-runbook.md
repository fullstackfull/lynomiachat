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

### 0.1 The host precondition this release adds

**Check this first, before the window opens.** This release moves Rails from 7.2.3.1 to 7.2.3.2 to carry the
fix for CVE-2026-66066 (Active Storage). That fix makes Active Storage **refuse to load** unless libvips is
8.13 or later and `ruby-vips` is 2.2.1 or later: it raises on `require`, so every Rails process aborts — web
and worker alike. The lockfile moves `ruby-vips` 2.1.4 → 2.3.0, which settles the gem half. The libvips half is
a system package on this host and nothing in the release can install it.

```bash
# the gem's view of the system library -- this is the number Active Storage checks
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec ruby -rvips -e \
  'puts [Vips.version(0), Vips.version(1), Vips.version(2)].join(%q(.))'"

# and, if the bundle is not installed yet, the package
dpkg-query -W -f='${Version}\n' libvips42 libvips42t64 2>/dev/null
```

If libvips is older than 8.13, upgrade it **before** the deploy window
(`apt-get install --only-upgrade libvips42`). `deploy.sh` stage 4b checks this after the bundle install and
before the migrations, so an old library aborts the deploy at a safe point rather than taking the restart down
— but finding out at 3am is worse than finding out now.

### 0.2 Revisions and baselines

Have these open and ready **before** the deploy:

```bash
# the revision you intend to ship, from the release branch, written down
git -C /home/chatwoot/chatwoot rev-parse @{u}

# the revision currently serving, written down -- this is what a rollback goes back to
git -C /home/chatwoot/chatwoot rev-parse HEAD
```

Write both revisions into `deployment/INCIDENT.md` now, not later.

**Then take the baselines.** `09-rollback-and-rollout.md` §4 names ten signals and reads every one of them as a
change from before the deploy; §16 of this document and `deploy.sh` stage 8 both compare the dead set against
"the pre-deploy number". Without this capture none of those comparisons can be made, and a post-restart sample
is not a baseline. Paste the output into `deployment/INCIDENT.md`.

```bash
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner \
  \"require 'sidekiq/api'
    s = Sidekiq::Stats.new
    puts 'queues:      ' + s.queues.inspect
    puts 'enqueued:    ' + s.enqueued.to_s
    puts 'scheduled:   ' + s.scheduled_size.to_s
    puts 'retry:       ' + s.retry_size.to_s
    puts 'dead:        ' + s.dead_size.to_s
    puts 'processed:   ' + s.processed.to_s
    puts 'failed:      ' + s.failed.to_s
    puts 'signals(24h):' + (defined?(Custom::OperationsSignal) ? Custom::OperationsSignal.where('created_at > ?', 24.hours.ago).count.to_s : 'n/a')
    puts 'billing_wh:  ' + (defined?(Custom::BillingWebhookEvent) ? Custom::BillingWebhookEvent.where('created_at > ?', 24.hours.ago).count.to_s : 'n/a')
    puts 'inbound(24h):' + Message.where(message_type: :incoming).where('created_at > ?', 24.hours.ago).group(:inbox_id).count.inspect
    puts 'audits(24h): ' + (ActiveRecord::Base.connection.table_exists?('audits') ? Audited::Audit.where('created_at > ?', 24.hours.ago).count.to_s : 'n/a')\""

# the request-error rate, from whatever this installation already uses -- note the 5xx rate for the last hour
```

**Create a test account for this runbook, or nominate one.** Several steps below write data. Do them on an
account whose conversations nobody is paid to answer. Note its id.

### 0.3 How this document maps onto the rollout

`09-rollback-and-rollout.md` §6 says to "work `08-production-uat-runbook.md` from PHASE 2 onwards" and to
"enable nothing until PHASE 6". This document has no phases — it has numbered sections — so read that
instruction through this table:

| 09 calls it | here it is | levers |
|---|---|---|
| PHASE 1 — deploy with every lever off | §0, §1 | none; `config/features.yml` defaults stand |
| PHASE 2 — prove the deploy | §2, §3 | none |
| PHASE 3 — prove what is on by default | §5, §10, §11, §12 | none |
| PHASE 4 — the first pilot lever | §4, §6 (`audit_logs`, `custom_roles`) | one account |
| PHASE 5 — the remaining pilot levers | §7, §8, §9, §9a (`lynomia_support_tickets`, `lynomia_unified_identity`, billing) | one account each |
| PHASE 6 — the real send | §13 | the WhatsApp send, gated separately |

**Sections §4, §6, §7, §8 and §9a do not pass on a freshly created test account.** Each needs a capability the
account does not carry by default, and until it does the surface does not merely look empty — it refuses. Note
what `config/features.yml` actually controls: its `enabled:` value seeds the `ACCOUNT_LEVEL_FEATURE_DEFAULTS`
row applied to **new** accounts (`app/models/concerns/featurable.rb:13,53,115-121`); the real gate is the
account's own `feature_flags` bitfield read by `feature_enabled?` (`:95-97`). So check the account rather than
assume from the file — an older nominated account may already carry some of these. §0.4 is how to grant one,
for one account, and how to put it back.

### 0.4 Enabling one lever for one account, and undoing it

Every flag below ships off. Enable it for the test account only, never globally, and turn it off again at the
end of the section that used it.

| section | flag | `config/features.yml` | what it refuses while off |
|---|---|---|---|
| §4 | `audit_logs` | :112–115 | `AuditTrail::Query` returns `Custom::AuditLog.none`, so the page loads with zero rows whatever the table holds (`custom/app/services/audit_trail/query.rb:52`) |
| §6 | `custom_roles` | :148–151 | all five permission-set endpoints raise `Pundit::NotAuthorizedError` |
| §7 | `lynomia_support_tickets` | :304–307 | every support endpoint 404s (`custom/app/controllers/api/v1/accounts/support/base_controller.rb:17–21`) |
| §8 | `lynomia_unified_identity` | :308–311 | both identity writers refuse (`custom/app/services/contacts/identity_linker.rb:34`) |

```bash
# what the account carries NOW -- write this down before changing anything
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner \
  \"puts Account.find(<test account id>).enabled_features.keys.sort.inspect\""

# on, for ONE account
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner \
  \"a = Account.find(<test account id>); a.enable_features!('audit_logs'); puts a.enabled_features.keys.sort.inspect\""

# off again
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner \
  \"a = Account.find(<test account id>); a.disable_features!('audit_logs'); puts a.enabled_features.keys.sort.inspect\""
```

For the two non-premium ones — `lynomia_support_tickets` and `lynomia_unified_identity` — the Super Admin
override surface §9 already exercises does the same thing through the UI, and leaves an audited
`billing.override_granted` row. Either route is fine; the override route is the one a customer would get.

**GO/NO-GO 0.** Capture also means capture *back*: write the account's `enabled_features` keys down before you
change them, so the end state is checkable rather than remembered.

---

## 0.5 Before the restart: quiet the workers

This used to sit at the end of the document, after §15, which meant the one instruction that has to be read
*before* the restart was read after it. It is now part of §1; see **§16** for what to do when the drain does not
confirm.

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

## 5a. The audit trail — retention (DECISION 5)

Capture is still ungated and must stay that way: an audited account cannot stop its own trail from a settings
page. What this release adds is a bound on growth. **Read-only checks, as the app user:**

```bash
# the setting and its default
RAILS_ENV=production bundle exec rails runner \
  'puts GlobalConfigService.load("AUDIT_LOG_RETENTION_DAYS", 365)'

# the sweep is scheduled (sidekiq-cron), and the oldest row still present
RAILS_ENV=production bundle exec rails runner \
  'require "sidekiq/cron"; puts Sidekiq::Cron::Job.find("audit_trail_retention_job")&.to_hash&.slice("name","cron","klass","queue").inspect'
RAILS_ENV=production bundle exec rails runner 'puts Audited::Audit.minimum(:created_at)'
```

| step | expected |
|---|---|
| the setting reads back | `365` unless an operator has changed it |
| the cron entry exists | name `audit_trail_retention_job`, cron `15 3 * * *`, queue `housekeeping` |
| turn `audit_logs` **off** for a pilot account, then act as its administrator | the action **still appears** in `audits` (query as the app user; the UI is what the flag hides) |
| after the first nightly run, read the operator log | one `AUDIT_RETENTION_SWEEP` line with `retention_days`, `cutoff`, `deleted`, `capped`, and **no audited content in it** |

**GO/NO-GO 5a.** If turning `audit_logs` off stops rows being written, stop: the capture gate has been
reintroduced and the trail is defeatable by the party it audits.

Changing the window is Super Admin → Settings → `AUDIT_LOG_RETENTION_DAYS`. It takes effect on the next sweep,
needs no deploy, and a value below 30 is refused rather than obeyed (the run logs
`AUDIT_RETENTION_MISCONFIGURED` and deletes nothing).

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

## 6a. The conversation capabilities, now enforced (DECISIONS 1 and 2)

**This is the behaviour change in this release that an existing customer is most likely to notice, so it gets
its own pass.** Until now the three `conversation_*` capabilities were enforced only by the browser. They are
now enforced by the server, on the list, on one conversation, in global search and in the unread counts.

Do this with **three** agents in a pilot account, each holding a set with exactly one of the three
capabilities, and with at least one conversation of each shape present (assigned to that agent, unassigned,
assigned to somebody else).

| step | expected |
|---|---|
| sign in as the holder of `conversation_manage` | sees all three conversations |
| holder of `conversation_unassigned_manage` | sees their own and the unassigned one; **not** the one assigned to somebody else |
| holder of `conversation_participating_manage` | sees only their own |
| each of them: open the conversation list and compare the sidebar counts with the rows | the count equals the number of rows, for every one of the three |
| each of them: paste the URL of a conversation the list did **not** return | refused, not shown — and its messages, attachments and transcript are refused with it |
| each of them: search for a word that appears in a hidden conversation's messages | no result; no message body from a hidden conversation appears |
| the holder of `conversation_unassigned_manage`: take the unassigned conversation | allowed — reaching and taking unassigned work is what that capability is for |

**GO/NO-GO 6a.** If a holder can open, search or count a conversation the list refuses them, stop. The list and
the record must agree.

### The existing sets on the real installation

Before the window, list what is actually attached, because the grandfather clause only matters if such a set
exists:

```bash
RAILS_ENV=production bundle exec rails runner '
  CustomRole.find_each { |r| puts [r.account_id, r.id, r.name, r.permissions.inspect,
                                   r.conversation_scope_enforced].join(" | ") }'
```

| step | expected |
|---|---|
| a pre-existing set naming none of the three | `conversation_scope_enforced` is **false**, and its holders see exactly what they saw before the deploy |
| edit that set's conversation capabilities in Settings, then re-read it | the flag is now **true** and the new scope applies |
| edit only its non-conversation capabilities | the flag stays **false** |
| create a new set with no conversation capability, attach it to a test agent | that agent sees **no** conversations — absence means none for anything configured from now on |

**GO/NO-GO 6b.** If a pre-existing set's holders lose conversation access on the deploy, stop and roll back the
code: the grandfather clause has not worked, and that is an access regression for live agents.

### The entitlement bound (DECISION 2)

On a pilot account only, and with its administrator warned:

| step | expected |
|---|---|
| turn the account's `custom_roles` feature **off** | the set's holders become **plain agents**: they see what an agent sees, they are **not** locked out, and they are **not** administrators |
| check the set and the attachment | both still exist — nothing was deleted |
| turn `custom_roles` back **on** | every capability is granted again immediately, with no restore step |
| as a holder during the lapse, try an administrator-only action (delete a conversation, open Settings → Roles) | refused |

**GO/NO-GO 6c.** If a lapse grants anything it did not grant before — above all administrator — stop. A lapse
must only ever narrow.

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

**Production Stripe stays unconfigured for this runbook.** Live keys, a live webhook endpoint and a real
checkout are their own change with their own go decision. Do not fold them into this deploy.

But "unconfigured" leaves the enforcement path unexercised, and that path only wakes when Stripe keys exist
(`09-rollback-and-rollout.md` §1). §9a exercises it in **test mode**, where a mistake costs nothing.

---

## 9a. P11 — the Stripe path, in TEST MODE only

Stripe test mode is not production Stripe. Test keys (`sk_test_…`, `pk_test_…`) cannot move money, cannot
charge a real card, and are a different object space from live keys: nothing created here exists in the live
account. This section is what makes the difference between "the billing tables look right" and "the webhook,
the signature check and the enforcement path all work".

**Preconditions.** A Stripe account in test mode; its test secret key, test publishable key, and a webhook
endpoint pointing at this installation with its **test** signing secret. Do not reuse a live secret for any of
the three. Note every value you set, because step 7 puts them all back.

| step | expected |
|---|---|
| 1. set the three test values in Super Admin → Settings (or the installation config they live in) | saved; the page shows them set |
| 2. confirm you are in test mode | every key begins `sk_test_`/`pk_test_`/`whsec_` from the test endpoint. **If any begins `sk_live_`, stop.** |
| 3. Stripe dashboard → send a test `customer.subscription.updated` to the endpoint | `billing_webhook_events` gains one row; the response is 2xx |
| 4. replay the same event | the second delivery is recognised as a duplicate and changes nothing — idempotency, not a second subscription change |
| 5. send one event with a **deliberately wrong** signature (edit a byte of the header) | **rejected**, no `billing_webhook_events` row, and the log says signature verification failed. A 2xx here is a stop. |
| 6. drive the test account past a plan limit it is subscribed to | the limit is enforced server-side, and the message names the limit rather than failing opaquely |
| 7. remove the three test values and confirm the billing surfaces fall back to the manual-subscription behaviour of §9 | §9's table still passes |

**GO/NO-GO 9a.** Step 5 is the one that matters. An endpoint that accepts an unsigned or wrongly signed webhook
lets anyone who knows the URL change a subscription. If step 5 returns 2xx, stop the rollout and raise it: this
is a security defect, not a billing inconvenience.

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

### 11c. A scheduled WhatsApp campaign when the capability is unavailable (DECISION 6)

On a pilot account, with a **test contact you own**:

| step | expected |
|---|---|
| schedule a one-off WhatsApp campaign a few minutes out, then turn the account's `whatsapp_campaign` feature off before it fires | **nothing is sent** |
| look at the campaign | status **blocked**, with the explicit "not sent — WhatsApp unavailable" label; its recipients and content are intact |
| read the campaign over the API | `blocked_reason` is `FEATURE_DISABLED` |
| Operations Center | **exactly one** unresolved `feature_disabled` signal for that campaign, however many minutes have passed |
| wait several more scheduler ticks and look again | still one signal, still blocked, still nothing sent — and it is not silently abandoned after three days |
| turn `whatsapp_campaign` back on and resume the campaign | it sends, and if its original time has aged out the schedule moves forward so that resuming means something |
| schedule an **SMS** campaign with SMS available | it behaves exactly as it did before this release |

**GO/NO-GO 11c.** If a message reaches a real recipient while the capability is off, or if the campaign sits
`active` with no reason recorded, stop.

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

### 13a. First: a genuinely new inbound contact

Every other WhatsApp step in this runbook, and §11b's simulation, runs through a contact that **already
exists**. That leaves the one path this release changed most — inbound arriving from a number the installation
has never seen — untested, and `09-rollback-and-rollout.md` §5 makes inbound mis-routing a code rollback with
no lever of its own. P10 put `contact_identities` in front of contact resolution, so "which contact does this
number belong to" is new code on the first message from a new number, not on the second.

Ask the cooperating recipient to message the test account's WhatsApp number **from a number that is not already
a contact on this installation**. Confirm first, in the dashboard search, that the number returns nothing.

| expected | why it is the interesting case |
|---|---|
| a new conversation appears on the test account, in the WhatsApp inbox | the inbound route resolves to the right account and inbox |
| a **new** contact is created, with that number | `Contacts::IdentityLinker` found no match and created rather than merged |
| exactly one contact, not two | a duplicate means the identity matcher and the legacy phone lookup disagreed |
| the contact's identities panel lists the number once | `contact_identities` was written alongside `contacts.phone_number`, not instead of it |
| an agent reply reaches the recipient | the outbound leg uses the conversation the inbound leg created |
| the contact's activity timeline shows the inbound message | P8's timeline adapter sees a contact created by this path |

**GO/NO-GO 7a.** Two contacts for one number, or a conversation on the wrong account, is a code rollback —
not a lever. Stop and read `deployment/ROLLBACK.md`.

### 13b. Then the template send

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

## 16. The worker drain, and what to do when it does not confirm

**Read this before §1, not after §15.** §0.5 points here.

`deployment/deploy.sh` stage 6b quiets `chatwoot-worker.1.service` and waits for the in-flight set to
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

**If the drain does not confirm.** Stage 6b prints one of two lines when it gives up, and neither is a
success:

- `note: could not read sidekiq's in-flight set (attempt n/30)` — the probe itself failed, so the in-flight set
  is unknown rather than empty. Check Redis before anything else: if Redis is unreachable the restart is not
  the problem you have.
- `WARNING: sidekiq did not confirm an empty in-flight set within 60s. Restarting anyway.` — a job is still
  running. The script does not stop, because stopping is a judgement the operator owns.

In either case you are at a coherent hold point: the release is checked out and migrated, and the **old code is
still serving**. The migrations in this release are additive, so the old code runs against the new schema
(`docs/p-final/03-migration-review.md`). You therefore have three options, in order of preference:

1. **Wait and re-check.** Run the command above. Campaign sends are the long jobs; if `busy` is falling, let it
   finish and then `systemctl restart <target>` by hand.
2. **Find out what is running** — `Sidekiq::Workers.new.map { |_, _, w| w['payload']['class'] }` — and decide
   from the class. Anything that is not a provider send can be interrupted safely; a campaign send is the case
   stage 6b exists for.
3. **Restart anyway**, accepting that a job which had already called Meta will be retried from the top. Note in
   `deployment/INCIDENT.md` that you did, so a duplicate message later has an explanation.

Set `REQUIRE_DRAIN=1` on the deploy to turn this into a refusal instead of a warning. Use it for an unattended
deploy; leave it unset when you are watching.

**If the dead set grew after the deploy**, list it and check what the entries are. Entries naming
`Campaigns::UpdateRecipientStatusJob` are expected and can be deleted: the class is gone on purpose, and
`Whatsapp::DeliveryReport` now resolves a report against the recipient row directly, so the case that job
covered no longer arises (`docs/p-final/03-migration-review.md` §8.1). Entries naming anything else are not
expected and are a reason to stop and read them before going further.
