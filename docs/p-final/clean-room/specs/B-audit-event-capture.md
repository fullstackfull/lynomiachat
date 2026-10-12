# Feature package B — Audit trail: event capture

> Clean-room specification. It states which events Lynomia must record and what each record must contain. It
> does not describe any previous implementation, and the grouping below is by *event*, not by code structure —
> how capture is arranged in code is the implementer's decision.

## 1. Purpose

Package A can only answer "who changed this?" if the change was recorded. Lynomia needs capture for four
reasons:

- **Attribution of operator actions.** Lynomia's own subsystems already record their own events (support case
  transitions, contact merges, commercial entitlement overrides, store connections, WhatsApp template changes).
  They expect a shared record format and a shared read surface, not one of their own.
- **Explaining destructive actions.** When a conversation, a message or an inbox is gone, the trail is the only
  remaining evidence of who removed it.
- **Session accountability.** Sign-in and sign-out are the events that let an administrator reconstruct who was
  present when something happened.
- **Configuration change history.** A channel's configuration changing is the commonest cause of "it stopped
  working", and the trail is where that is diagnosed.

## 2. Public / internal contract

There is no HTTP surface in this package. The contract is the **record** it produces, which package A reads and
which Lynomia's existing writers already produce.

### What one record must carry

| element | requirement |
|---|---|
| affected record | its type and its id |
| associated account | the account the record belongs to, so the trail can be scoped per tenant |
| actor | the person or machine credential responsible, when one is known; null when the cause is the system |
| actor display name | a durable name, captured at write time, so the record stays attributable after the actor's own record is deleted |
| action | one of a small closed vocabulary: a record was created, changed, or removed |
| context | a structured object holding the before/after or the identifying details a reader needs (§4) |
| time | when it happened |
| originating address | the request's remote address, when the event came from a request |

### Required capture points

Grouped by the **product event**, because that is what must be true; the implementer decides where each hook
belongs.

| # | event | what the record must make answerable |
|---|---|---|
| B1 | an account's settings change | which account, which fields, old and new values |
| B2 | a membership is created or changed | which person, which account, and specifically a change of role or of availability; and whether the actor was editing themselves or someone else |
| B3 | an inbox is created, changed or removed | which inbox |
| B4 | a member is added to or removed from an inbox | which member, which inbox |
| B5 | a team is created, changed or removed | which team |
| B6 | a member is added to or removed from a team | which member, which team |
| B7 | an automation rule is created, changed or removed | which rule |
| B8 | a macro is created, changed or removed | which macro |
| B9 | a webhook is created, changed or removed | which webhook |
| B10 | an agent bot is created, changed or removed | which bot |
| B11 | an audience definition is created, changed or removed | which definition. *(This capture point is already original Lynomia work and is NOT part of the rewrite; it is listed so the vocabulary is complete.)* |
| B12 | a conversation is removed | which conversation, named by the number a human would recognise rather than only its internal id |
| B13 | a message is removed | which message, and which conversation it belonged to — **never the message body or its attachments** |
| B14 | a user signs in, and signs out | which user, which account context |
| B15 | a channel's configuration changes | which channel and which fields — **with credentials excluded, see §5** |
| B16 | an inbox or a conversation is destroyed by the asynchronous deletion path | which record, and the actor who requested the deletion rather than the worker that performed it |

The exact `type:action` pairs that package A's frontend has labels for are enumerated in
`app/javascript/dashboard/helper/auditlogHelper.js`. That file is the authority on the vocabulary; an event
captured outside it will display unlabelled.

### Errors

Capture is a side effect of a product action. It must never turn a successful product action into a failure:

- if a record cannot be written, the product action still succeeds;
- the failure is reported where operators look (the application log, and the exception tracker the codebase
  already uses) rather than silently dropped;
- a failure to record must not be reported to the end user.

### Authorization and tenant scope

Capture inherits the authorization of the action that caused it — it grants nothing and checks nothing of its
own. Every record must carry the account of the affected record so that package A's tenant scoping is possible;
a record that cannot be attributed to an account is a defect, not an acceptable edge case.

## 3. Data contract

The `audits` table described in package A §3 is the store. No new table or column is required.

Two columns deserve explicit mention:

- The actor is **polymorphic**: both a person and a machine credential must be storable, and the display-name
  capture must work for either without raising. This is a real production case — a machine credential
  administering an account must not be the one actor whose actions go unrecorded.
- `comment` is available for a short event name where the closed `action` vocabulary is not specific enough.
  Lynomia's existing writers already use it this way; reuse rather than invention is preferred.

## 4. Observable behaviour

Behaviour is observable through package A's read surface. "An entry appears" below means "a request to the read
surface returns it".

- Given an administrator changes an account setting, when the trail is read, then an entry appears naming the
  account, the actor and the changed field with its old and new values.
- Given an administrator changes another member's role, when the trail is read, then an entry appears that
  distinguishes it from a member editing themselves, and carries the old and new role.
- Given a member edits their own membership, when the trail is read, then the entry is distinguishable from the
  previous case.
- Given a membership whose user record has since been deleted is edited, when the trail is read, then the entry
  still renders and remains attributable.
- Given an inbox is created, changed and then removed, when the trail is read, then three entries appear with
  the three different actions.
- Given a member is added to and then removed from a team, when the trail is read, then two entries appear.
- Given a conversation is deleted, when the trail is read, then an entry appears carrying the conversation
  number a human would recognise.
- Given a message is deleted, when the trail is read, then an entry appears naming the conversation, **and no
  part of the message body or its attachments appears anywhere in the entry**.
- Given two people delete the same message at the same moment, when the trail is read, then exactly one entry
  exists for that deletion.
- Given a user signs in and later signs out, when the trail is read, then two entries appear for that user.
- Given a sign-in fails, when the trail is read, then no success entry appears. *(Recording failures is not
  required; see §9.)*
- Given a channel's configuration is changed, when the trail is read, then an entry appears naming the changed
  fields, **and no credential value appears in it**.
- Given a channel's configuration change consists only of internal bookkeeping that no operator asked for, when
  the trail is read, then **no entry appears** — the trail must not be filled with noise the product generates
  about itself.
- Given an inbox is deleted through the asynchronous deletion path, when the trail is read, then an entry
  appears naming the person who requested it rather than the background worker.
- Given the audit store is unavailable, when a product action is performed, then the action still succeeds and
  the failure is visible in the log.

## 5. Security rules

- **No credential, ever** — and note this is an existing Lynomia security property that must not be lost in the
  rewrite, not a new ambition. A channel's configuration holds provider credentials — access tokens, signing
  secrets, API keys, auth tokens, passwords. The capture must exclude them by construction, and the test for it
  must be positive (plant a credential-shaped field, assert its value is absent from the stored record) rather
  than a review. Partial values, masked values and hashes of credentials are also excluded: the field is
  omitted, not transformed.
- **No message or conversation content.** A deletion entry identifies what was deleted. It does not preserve it.
  This is stricter than the behaviour shipping today, deliberately: today a deleted message's body reaches the
  stored record and is withheld again by the read surface, so the body's safety rests on one serializer rule.
  Store the identifying context only (which conversation, by its human-facing number, and which inbox and
  sender) and the read surface needs no special case at all — which also removes the only reason package A
  treats one record type differently from the rest.
- **Rotating a credential is a decision to take deliberately.** Changing a channel's signing secret through the
  reset-secret endpoint produces no entry today. Either outcome is defensible — recording that it was rotated is
  arguably better — but it must be a decision, and in neither case may the value be recorded.
- **No customer payment data.**
- **Tenant attribution is mandatory** so the read surface can scope. An entry with no account cannot be shown
  safely and must not be written.
- **The actor is recorded, not asserted.** It comes from the authenticated request context, never from a
  parameter the caller supplies.
- **Concurrency.** Two simultaneous attempts to record the same single event must not produce two entries.

## 6. Failure behaviour

| situation | required behaviour |
|---|---|
| the audit store rejects the write | the product action succeeds; the failure is logged and reported to the exception tracker |
| the actor cannot be determined | the entry is written with a null actor rather than skipped |
| the actor is a machine credential | the entry is written and the display name is captured without raising |
| the affected record is deleted in the same operation | the identifying context is captured before it becomes unavailable |
| the context object would exceed a sane size | it is reduced to identifying fields; a large payload is never stored wholesale |
| the same event is delivered twice | one entry |

## 7. Callers and dependents

| component | relationship |
|---|---|
| package A (read surface) | the only reader; depends on the record shape and the event vocabulary |
| `app/javascript/dashboard/helper/auditlogHelper.js` | depends on the `type:action` vocabulary and on the context keys named in §4 |
| P9 support-case transitions, P10 contact merge and identity linking, P11 entitlement overrides and plan edits, Commerce store connections, the WhatsApp Template Manager | already write records of their own in the same store and expect the same shape; **none of these writers is part of the rewrite** |
| `custom/app/services/operations/*` (P9 Operations Center) | unaffected; a separate operational-signal store |
| the asynchronous object-deletion path in OSS | the extension point for B16 |

## 8. Acceptance criteria

1. Every scenario in §4 passes through the read surface.
2. For each of B1–B16 (except B11, which already exists) an entry is produced with the elements in §2.
3. A planted credential-shaped field in a channel configuration change is absent from the stored record.
4. A deleted message's entry contains no substring of the message body, **in the stored record** and not only
   in the response.
5. A machine-credential actor produces a readable, attributable entry.
6. A forced failure of the audit write leaves the product action successful and the failure logged.
7. A duplicate single event produces one entry.
8. Every produced entry carries an account, verified by asserting the read surface's tenant scoping returns it
   for the right account and not for another.
9. Recording adds no query that scales with the size of the affected record's associations.

## 9. Non-requirements

- **No event for every model.** Only B1–B16. A long tail of record types is explicitly not wanted.
- **No field-level configuration surface** for choosing which events are captured.
- **No retention, archival or purge.**
- **No tamper-evidence** (no signing, hash chaining or append-only enforcement).
- **No failed-authentication recording.** Sign-in failures are out of scope here.
- **No capture of reads.** Only changes.
- **No geolocation** of the originating address (package A §9).
- **No separate store.** The existing table is the store; a parallel audit system is not wanted.
- **No reuse of the previous arrangement.** Whether capture is expressed as model declarations, controller
  hooks, service calls or something else is entirely the implementer's choice, provided §4 holds.
