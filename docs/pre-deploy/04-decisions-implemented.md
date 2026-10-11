# Pre-deploy condition 3, closed — what the six approved decisions actually do

`02-product-decisions.md` is the dossier the six decisions were taken from. This document is the record of
what was then **implemented**, decision by decision, with the file that holds each rule and the exact semantics
an operator and a reviewer need. Nothing here is a plan; every statement describes code on this branch.

The six were approved as written in the owner's message of 2026-10-11, with one override: RULE 3's
recommendation was replaced by a sanitized structured allowlist.

---

## DECISION 1 — The three `conversation_*` capabilities are now server-side authorization

### The exact three capability names, and their final semantics

| Capability (stored in `custom_roles.permissions`) | Mode | A holder may read |
| --- | --- | --- |
| `conversation_manage` | `:base` | every conversation the holder could already reach |
| `conversation_unassigned_manage` | `:unassigned_and_mine` | conversations assigned to them, plus unassigned ones |
| `conversation_participating_manage` | `:mine` | conversations assigned to them |
| none of the three, on an enforced set | `:none` | nothing |
| none of the three, on a grandfathered set | `:base` | as before — see the next section |

Three rules govern the table:

* **Widest wins.** A set naming more than one of the three gets the widest. That is what the browser has
  always done (`app/javascript/dashboard/store/modules/conversations/helpers.js:85-106`) and what the unread
  counter already did, so it is the behaviour an administrator has been shown.
* **Unassigned means no human assignee AND no bot assignee**, which is the product's own definition
  (`app/models/conversation.rb:89`). A bot-assigned conversation is not unassigned.
* **It narrows, it never widens.** Every existing ceiling still applies and is intersected with this: inbox
  membership in the list, inbox-or-team in the record policy, the account in search. In particular the
  pre-existing inbox/team asymmetry (a team member with no inbox membership can open a conversation the list
  would not return, asserted at `spec/policies/conversation_policy_spec.rb`) is deliberately unchanged;
  moving that ceiling was not part of this decision.

`administrator` is untouched. An administrator's reach is the `role` column everywhere in this product and is
never decided by a capability list, so an administrator is `:base` by construction.

### One definition, four consumers

`custom/app/services/conversations/capability_scope.rb` is the only place that decides the rule. It answers in
three shapes — a relation (`narrow`), a record (`permits?`) and a mode name (`mode`) — because that is what its
callers need. Before this, the rule had four independent expressions and none was authoritative; a fifth would
have made the drift worse.

| Surface | Socket | What it closes |
| --- | --- | --- |
| list, meta counts, filter endpoint, contact conversations/attachments, activity timeline, bulk actions, saved-filter counters | `custom/app/services/custom/conversations/permission_filter_service.rb` | the relation almost every conversation read goes through |
| one conversation, and everything hanging off it: messages and their bodies, attachments, labels, participants, assignments, drafts, commerce overview, transcript, macros | `custom/app/policies/custom/conversation_policy.rb` | direct access by display id, which a narrowed list invites |
| `GET /search`, `/search/conversations`, `/search/messages` | `custom/app/services/custom/search_service.rb` | `SearchService` never called the filter service at all, so search returned conversations and message bodies with no narrowing whatsoever |
| filtered unread counts | `custom/app/services/custom/conversations/unread_counts/counter.rb` | the one surface that *did* have a server-side reader, now reading the same definition instead of its own copy |

All four are the existing `prepend_mod_with` extension points. No new authorization framework was introduced.

Counts agree with lists because Kaminari's `total_count` re-runs the same relation without its limit:
narrowing the relation narrows the count with it, rather than paging a wider set.

### Backward compatibility: the mechanism, exactly

The problem the decision names: these capabilities were not enforcing, so an administrator who left all three
unticked did not thereby choose "no conversation access" — they chose nothing. Reading that absence as a denial
on upgrade would remove access nobody withheld.

The vehicle is one server-derived column, `custom_roles.conversation_scope_enforced`, added by
`custom/db/migrate/20261011180000_add_conversation_scope_enforced_to_custom_roles.rb`:

1. The column is added with `default: true, null: false`, so **every set created from now on is enforced**.
2. The same migration then sets it to `false` for exactly the pre-existing sets that name **none** of the three
   capabilities. A set that already names one was always going to be enforced at that scope, so it needs no
   exemption.
3. `custom/app/models/custom_role.rb` flips it back to `true` on `before_update` when, and only when, an
   operator's edit **changes the conversation subset** of the permission list. The comparison is set-based, so
   reordering the same capabilities is not an edit, and an edit that touches only non-conversation capabilities
   leaves the exemption alone.

So: new sets are enforced; an existing set is enforced the moment an operator revisits its conversation
capabilities; and an existing set nobody has revisited keeps working. Absence is never read as unrestricted
access for anything configured from now on.

The column is deliberately invisible to the API: it is not in the controller's strong params (which permit only
`name`, `description`, `permissions`) and not in the jbuilder, so no client can set it and the response shape
is unchanged.

### The browser, which is UX and not enforcement

`applyRoleFilter` (`app/javascript/dashboard/store/modules/conversations/helpers.js:74`) already implemented
exactly these semantics, and it was the only thing narrowing anything. It is unchanged, and it is now
redundant rather than load-bearing: the server returns a narrowed list, and the browser filters the same list
the same way.

One asymmetry is left deliberately. For a **grandfathered** set the server returns every conversation, while
`applyRoleFilter` returns `false` for a custom-role holder naming none of the three and therefore hides them
all. That is not a regression: such a holder's dashboard list was already empty before this change, for the
same reason. Grandfathering protects the surfaces the browser filter never covered — search, the API, the
counts, the contact timeline — and keeps server behaviour identical for everyone. Teaching the browser about
the exemption would mean publishing `conversation_scope_enforced` to clients, which the decision does not ask
for and which would hand a client a server-derived authorization flag. The conservative direction is the safe
one: the UI can only ever show less than the server allows, never more.

---

## DECISION 2 — Account entitlement is a hard upper bound

### Precedence

```
effective permission  =  installation/product availability
                      AND account entitlement
                      AND member/role permission
```

The first two are what `Billing::Entitlements.allowed?` already answers, in the product's own precedence:
system feature → operator override → the account's feature bits, which is where `Billing::FeatureSync` writes
what the plan bought. The third is the permission set.

The bound is applied in exactly one place: `Custom::AccountUser#permissions`
(`custom/app/models/custom/account_user.rb`), which is the single list every capability check in the product
reads — the three Lynomia policies, the user jbuilder that tells the browser what to offer, and
`Conversations::CapabilityScope`. Nothing was scattered into controllers, and there is no second way to ask the
question.

### What a lapse does, and what it must never do

* **Nothing is deleted.** No permission set row is destroyed and no membership is detached. The set is still
  there, still attached, and starts granting again the moment the entitlement returns — reactivation with no
  restore step.
* **The fallback is the member's built-in role list**, which for a membership holding a set is always `agent`:
  the attachment path forces the column, and a set could only ever have *added* to the agent baseline. So the
  fallback is strictly the least-privileged compatible behaviour.
* **It cannot escalate to administrator.** `administrator?` reads the `role` column, which this never touches,
  and the permission list is not consulted for any administrator check anywhere in the product. Asserted
  directly, both as a unit and over HTTP (an attempted `DELETE` of a conversation after the lapse is refused).
* **Capabilities with their own gate keep it.** `commerce_order_manage` is still gated by `lynomia_commerce` at
  its own controller and `support_ticket_manage` by `lynomia_support_tickets` at its own base controller. This
  bound sits above those, not instead of them.
* **Contact management and merge get no new paid feature.** `contact_manage` remains the authoritative control.

### The interaction with DECISION 1, which matters

`Conversations::CapabilityScope` keys "is this a custom-role agent?" off the **marker in the permission list**,
not off `custom_role_id`. That is deliberate: once the entitlement lapses, the membership arrives with its
built-in agent list and no marker, so its members are treated as plain agents — not denied every conversation
by a capability the account is no longer entitled to hold. Reading `custom_role_id` would have failed closed in
the wrong direction, withholding access the account still pays the base plan for.

### The operator lever for this particular capability

`custom_roles` is `premium: true` in `config/features.yml`, so it is not in `BillingPlan.assignable_features`:
no plan sells it and `Billing::FeatureSync` never writes it. For such a capability
`Billing::OverrideGrant#write_features!` applies the account flag directly and records the audit row; there is
deliberately no override row, because an override exists to contradict a plan and no plan has an opinion here.
The account's own `custom_roles` flag therefore *is* the entitlement answer, and Super Admin → Account
features, or the Platform API routed through that writer, is how an operator changes it.

### Why deploying this changes nothing today

While commercial enforcement is off, every subscription is accessible and no plan withholds anything, so
`allowed?` returns the account's own flag — which is exactly what decided whether the set could be administered
in the first place. The behaviour diverges only for an account that has actually lost the flag, which is the
case this exists for.

---

## DECISION 3 — Sanitized structured allowlist for Meta send errors (override applied)

`app/services/whatsapp/providers/base_service.rb` logged `response.body` in full on a failed send. The
recommendation in the dossier was overridden: diagnostics are kept, the raw body is not.

`app/services/whatsapp/provider_error_log.rb` emits one line:

```
WHATSAPP_PROVIDER_ERROR code=131049 error_subcode=2655007 type=OAuthException fbtrace_id=A1B2C3 message=... status=400 classification=provider_refused
```

**Allowlisted, and nothing else:** `code`, `error_subcode`, `type`, `fbtrace_id`, a length-capped sanitized
`message`, the HTTP `status`, and a derived `classification`
(`provider_refused` 4xx / `provider_error` 5xx / `provider_rejected` / `unparseable_body`).

**Never logged:** access tokens, authorization headers, the customer's message body, the recipient's phone
number, arbitrary nested provider payload, or any credential-shaped value. Three defences, because Meta's
payload is not a contract this code controls:

1. **Allowlist, not denylist.** An unknown field is not logged, so a payload that grows a new key cannot leak
   it. The four identity fields are additionally required to be identifier-shaped scalars.
2. **Credential-pattern redaction** over the message text, matching a secret-ish key with any word prefix
   (`access_token=…` as well as `token=…`) and URL userinfo.
3. **Contact-shape redaction** over the message text: a digit run of nine or more digits across separators, or
   any leading `+`, plus e-mail addresses.

The two bugs this design produced were both caught by its own tests before commit: `\btoken` could not match
inside `access_token`, and a seven-digit phone threshold redacted Meta's seven-digit `error_subcode` — one of
the five values the log exists to preserve. `spec/services/whatsapp/provider_error_log_spec.rb` feeds
deliberately credential- and PII-shaped values through the formatter and asserts they do not reach the line.

---

## DECISION 4 — Package identity

`package.json` now declares `"name": "lynomia-chat"` and `"private": true`. The repository publishes no npm
artifact, so `private` is the honest value and it also prevents an accidental publish under any name.

No licence conclusion was drawn. The `LICENSE`/`NOTICE` discrepancy keeps P-FINAL's classification: **a matter
for qualified legal review**, recorded in `01-license-closure.md`. No third-party notice was removed.

---

## DECISION 5 — Audit capture stays ungated; retention is 365 days

**Capture is not gated and this change does not gate it.** `audit_logs` gates *reading*
(`custom/app/services/audit_trail/query.rb:52`); every writer — the twelve `Custom::Audit::*` modules, the
seven direct services, and the `audited` macro — writes unconditionally. An audited party cannot switch off
their own trail from a settings page. What was missing was any bound at all.

| Property | Value |
| --- | --- |
| Job | `custom/app/jobs/audit_trail/retention_job.rb` |
| Schedule | `config/schedule.yml`, `15 3 * * *`, queue `housekeeping` (sidekiq-cron, the existing scheduler) |
| Setting | `AUDIT_LOG_RETENTION_DAYS` in `config/installation_config.yml`, `type: number`, `locked: false` |
| Default | **365 days** |
| Minimum accepted | 30 days |
| Batch size | 1 000 rows per statement |
| Per-run ceiling | 200 000 rows, then it stops and says so |

**How an operator changes the period.** Super Admin → Settings → `AUDIT_LOG_RETENTION_DAYS`, or by seeding the
installation config. The value is read on every run, so a change takes effect on the next sweep with no deploy.
It is a system setting: not a browser setting, not a plan feature, and unreachable by any account,
administrator or agent. A value below the 30-day minimum, or a non-integer, is **refused rather than obeyed** —
the run logs `AUDIT_RETENTION_MISCONFIGURED` with the reason and deletes nothing, because deleting the whole
trail on a typo is not recoverable.

**Correctness properties.** The cutoff is `days.days.ago.utc.beginning_of_day` and the predicate is a strict
`<`, so the effective retention is the configured days plus up to one day — erring longer, never shorter, with
explicit UTC day-boundary semantics. A row whose `created_at` is `NULL` matches no comparison and is never
deleted. The deletable set is defined entirely by the clock, so the job is idempotent, safe to run twice, and
safe to overlap: two concurrent runs race only over rows that are already condemned. Deletion is scoped to the
audit table and bounded per batch.

**Observability without logging audit contents.** Each run emits one `AUDIT_RETENTION_SWEEP` operator line
carrying `retention_days`, the `cutoff`, the number `deleted` and whether the run was `capped`. No audited
content, and no identifiers of deleted rows, appear in it.

---

## DECISION 6 — A scheduled WhatsApp campaign whose capability is unavailable blocks explicitly

Previously `Campaign#trigger!` returned silently when the channel feature was off. The campaign stayed
`active` with its original `scheduled_at`, so `TriggerScheduledItemsJob` re-selected it every minute for three
days — and then, once `scheduled_at` fell out of the selection window, stopped selecting it. Nothing was sent
and nothing said so.

| Aspect | Behaviour now |
| --- | --- |
| Send | Does not happen. |
| State | `campaign_status: :blocked` — a new, explicit fourth state on the existing enum (value `3`). |
| Machine-readable reason | `blocked_reason = 'FEATURE_DISABLED'` (`Campaign::BLOCKED_FEATURE_DISABLED`), added by `custom/db/migrate/20261011170000`. |
| Operator visibility | Exposed on the campaign API payload, shown on the campaign card with a `danger` tone and an explicit label in EN and AR. |
| Operations signal | Exactly **one**, deduplicated: source `campaign`, signal `feature_disabled`, subject the campaign, written through `Operations::SignalRecorder`, whose partial unique index on the unresolved identity makes a repeat execution a no-op rather than a second row. |
| Retries | None. The campaign is no longer selected while blocked, so there is no active retry loop and no three-day silent abandonment. |
| Data | Campaign and recipient data are preserved untouched. |
| Resume | `Campaign#unblock!` returns it to `active`, clears the reason, and moves `scheduled_at` forward to now if the original time has fallen outside `TriggerScheduledItemsJob::SELECTION_WINDOW` — so a restored feature resumes under the existing resume semantics instead of being stranded by its own timestamp. |
| Cancellation | Unchanged: an operator can still cancel or edit the campaign. |

**SMS is unaffected.** `trigger!` is shared with SMS campaigns, and the block is reached only through the
same channel-feature check that already guarded the send, so an SMS campaign's behaviour is identical to
before. `spec/models/campaign_blocked_spec.rb` includes the SMS regression alongside the WhatsApp cases,
the idempotency of repeated execution, the single-signal assertion, and the re-enable/resume round trip.

---

## What was deliberately left alone

Per the brief's "do not broaden scope", the following were found during this work, are **reported rather than
fixed**, and are not regressions introduced here:

1. `POST /api/v1/accounts/:id/conversations` (conversation creation) is gated by inbox authorization but by
   none of the three `conversation_*` capabilities. Narrowing creation was not part of DECISION 1.
2. `SearchService#should_skip_inbox_filtering?` drops the message inbox filter not only for an administrator
   but for any user who happens to belong to every inbox in the account — an ordinary agent on a small
   installation. The capability narrowing is applied independently of that skip, so DECISION 1 holds either
   way, but the inbox ceiling itself is weaker than it looks.
3. `direct_uploads` and the Linear integration reach conversation data by paths that do not come through
   either socket.
4. The ActionCable `BroadcastScope` reaches every inbox member, so a narrowed holder can still be pushed an
   event about a conversation they may not read. This is a push, not a read endpoint, and closing it means
   touching the broadcast fan-out, which is a change of a different size.
