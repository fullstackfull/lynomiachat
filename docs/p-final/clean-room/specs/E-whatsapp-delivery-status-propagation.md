# Feature package E — WhatsApp delivery outcomes reaching the records that need them

**Audience: the clean-room implementer.** This document states the behaviour the product must exhibit. It does
not describe any prior implementation, and no prior implementation may be consulted. Every fact cited is a
public contract: a route, a column, an upstream MIT extension point, or a product rule stated as a rule.

---

## 1. Purpose

Lynomia sends WhatsApp messages through **Meta's official WhatsApp Cloud API** and receives Meta's delivery
reports as webhooks. Two kinds of outbound message need those reports, and only one of them is already served:

| outbound message | has a `Message` record | report handled today by |
|---|---|---|
| an agent's reply in a conversation | yes | upstream Chatwoot (MIT), fully |
| a one-off campaign send | **no** | nothing — this package |

The second row is the gap this package closes. A campaign send is dispatched without a conversation and
without a `Message` row (the OSS send path is called with no message: `app/services/whatsapp/oneoff_campaign_service.rb:91-97`
passes `nil`), and upstream's status handler abandons a report whose message identifier matches no `Message`
(`app/services/whatsapp/incoming_message_base_service.rb:62-64`: `return unless find_message_by_source_id(...)`).
So without this package every campaign recipient stays at "sent" forever and the campaign analytics of
package D report nothing but sends.

Three files carry this package: the status-path extension, the provider-side error retention, and a one-method
channel override that keeps the provider instance alive across a template send so its error survives the call.
All three are yours to write.

There is a second, smaller gap on the send side. When the provider call fails, upstream records the error onto
the `Message` and returns nothing to the caller, and it skips that entirely when there is no message
(`app/services/whatsapp/providers/base_service.rb:42-54`: `return if message.blank?`). A campaign send has no
message, so Meta's error code and title are logged and discarded — and package D requires them to be stored on
the recipient. The send path must be able to learn why a send failed when there is no `Message` to carry it.

**Scope boundary:** official Meta WhatsApp Cloud API only. See §9 for what is explicitly out of scope.

---

## 2. Public / internal contract

### How a report arrives (all clean, all MIT or Lynomia-original — do not reimplement)

| step | where | what it already guarantees |
|---|---|---|
| Meta POSTs the webhook | `app/controllers/webhooks/whatsapp_controller.rb` | Meta's signature is verified before anything is enqueued; an inactive number is rejected; tracking-only payloads are acknowledged and dropped |
| the payload is queued | `Webhooks::WhatsappEventsJob` (`app/jobs/webhooks/whatsapp_events_job.rb`) | the channel — and therefore the **account and inbox** — is resolved from the payload's business/phone identifiers before any processing; album bursts are serialised per `(inbox, contact)` |
| the payload is interpreted | `Whatsapp::IncomingMessageBaseService` (`app/services/whatsapp/incoming_message_base_service.rb`) | a `statuses` payload is routed to status handling before any message handling; `prepend_mod_with` is declared at line 230 |

The implementer's work hangs off the last row. **The inbox is already known** by the time status handling runs,
which is what makes a tenant-safe lookup possible (§5.1).

### Meta's status payload — the fields that matter

A status entry carries at least:

| field | meaning |
|---|---|
| `id` | the identifier Meta assigned the outbound message (the `wamid...` value the send call returned) |
| `status` | one of `sent`, `delivered`, `read`, `failed` |
| `errors[]` | present on `failed`; each entry carries a numeric `code` and a human `title` |
| `timestamp` | when Meta recorded the event |

Upstream already composes a failure string as `"<code>: <title>"` for the `Message` path
(`incoming_message_base_service.rb:72-78`). Package D needs the code and the title **separately**
(`campaign_recipients.error_code`, `.error_title`), so the parts must be available, not only the joined string.

### What this package must expose

No new HTTP endpoint, no new route, no new serializer. The deliverable is behaviour reachable from:

1. the status path above, for each entry in a `statuses` payload;
2. the provider send path (`Whatsapp::Providers::BaseService`, extension point declared at line 136), so a
   failed send with no `Message` yields its code and title to the caller instead of only to the log.

---

## 3. Data contract

This package owns **no table**. It reads and writes rows owned by other packages:

| record | columns this package writes | owner |
|---|---|---|
| `campaign_recipients` | `status`, `sent_at`, `delivered_at`, `read_at`, `failed_at`, `error_code`, `error_title`, `error_message` | package D (`D-campaign-recipient-outcomes.md` §3, §4.2) |
| `messages` | nothing directly — the upstream path owns it | upstream Chatwoot |

The join between a Meta report and a Lynomia record is the **provider message identifier**:

| record | column | uniqueness |
|---|---|---|
| `messages` | `source_id` | upstream's lookup is `Message.find_by(source_id:)` |
| `campaign_recipients` | `source_id` | unique partial index `WHERE source_id IS NOT NULL` (`db/schema.rb:459`) |

A given identifier belongs to **at most one** of the two. A conversation message and a campaign recipient never
share one, because a campaign send creates no message.

`Message` states are upstream's enum `{ sent: 0, delivered: 1, read: 2, failed: 3 }` and the forward-only
transition rule already lives in `Messages::StatusUpdateService` (MIT, with a row lock and an explicit
"to or from failed" exception). Recipient states are package D's enum. **The two vocabularies overlap in name
but are not the same enum and must not be assumed interchangeable.**

---

## 4. Observable behaviour

### 4.1 A report for a conversation message

Unchanged from upstream, and must stay unchanged: the message's status advances, a failure stores the external
error, redelivery is a no-op, and the row is locked for the transition. This package must not alter it,
duplicate it, or wrap it in a way that changes when it runs.

### 4.2 A report for a campaign send

| report | required effect on the recipient |
|---|---|
| `sent` | state `sent`, `sent_at` recorded |
| `delivered` | state `delivered`, `delivered_at` recorded |
| `read` | state `read`, `read_at` recorded |
| `failed` | state `failed`, `failed_at` recorded, `error_code` = Meta's numeric code, `error_title` = Meta's title, and a reason readable in `error_message` |

Each of these is subject to package D §4.2 in full — forward-only, idempotent under redelivery, never demoting
a better outcome, and applied under a row lock. This package is the **transport**; package D owns the rule. The
implementer must not implement the rule twice, in two places, with two chances to disagree.

### 4.3 A report that matches nothing

If the identifier matches neither a message nor a recipient, the report is **acknowledged and dropped
silently**. This is a normal event, not an error: Meta sends reports for messages sent from other systems on
the same number, for messages predating this installation, and for messages whose records were deleted. It must
not raise, must not log at error level, and above all must not prevent the rest of the payload from being
processed. Meta retries a webhook that does not return success, so turning a harmless report into a failure
produces a retry storm.

### 4.4 A failed send with no message record

When the provider call for a campaign send fails:

| requirement | why |
|---|---|
| the caller learns the provider's error **code and title** | package D stores them separately on the recipient. Note the shape of the obstacle: upstream's channel delegates the template send straight to a freshly built provider instance (`app/models/channel/whatsapp.rb:147`), so the instance — and any error it holds — is gone by the time the send returns. Whatever you do about that is part of this package |
| the send path still continues to the next contact | package D §4.1: one unsendable contact must not abort the campaign |
| nothing is written to a `Message` | there is none; the current early return is correct and must stay |
| the error is not swallowed into a bare log line | the operator's only view of it is the recipient list's reason column |

### 4.5 Order, duplication and concurrency

Three properties of Meta's delivery that the implementation must survive, not merely tolerate:

1. **Reports for one message can arrive out of order**, including `read` before `delivered`. The record must end
   at the furthest state reported (package D §4.2 rule 1).
2. **Reports are redelivered** after any non-success response, and sometimes without one. Applying a report
   twice must be indistinguishable from applying it once.
3. **Several reports for the same record can be in flight at once**, in different workers. Resolution must be
   deterministic: the record is advanced under a lock on that row, and the forward-only rule decides the
   outcome rather than commit order.

A payload may also contain **several status entries at once**. Every entry must be applied; one entry that
cannot be applied must not discard the others.

### 4.6 Coexistence numbers

A WhatsApp Business App number connected through Meta Embedded Signup — marked
`provider_config['is_coexistence']` (`app/services/whatsapp/channel_creation_service.rb:59`) — is **the same
official Cloud API channel** with the same webhook shape and the same status reports. It needs no separate
status handling, and must not get any. The only coexistence-specific behaviour already lives upstream and in
clean Lynomia code: echoes of messages sent from the phone (`smb_message_echoes`), and recipients addressable
only by a business-scoped user id. Neither changes how a *status* report is matched: the match is on the message
identifier, never on the recipient's address.

### 4.7 Scenarios

| # | precondition | action | expected observable result |
|---|---|---|---|
| E-1 | a conversation message in state `sent` | Meta reports `delivered` for its identifier | the message is `delivered`; no campaign recipient changes |
| E-2 | a campaign recipient in state `sent` | Meta reports `delivered` for its identifier | the recipient is `delivered` with `delivered_at` set; no message is created |
| E-3 | the recipient from E-2 | Meta reports `read`, then (later) `delivered` again | the recipient ends `read`, with both timestamps set |
| E-4 | a campaign recipient in state `sent` | Meta reports `failed` with code and title | the recipient is `failed`, code and title stored separately, and the reason appears in the campaign's recipient list |
| E-5 | an identifier no record carries | the report is delivered | the webhook succeeds, nothing is written, nothing is logged as an error |
| E-6 | one payload carrying three status entries for three different recipients | the report is delivered | all three recipients advance |
| E-7 | the same payload as E-2 | it is delivered twice | the recipient is identical after the second delivery, including its timestamp value |
| E-8 | account A's recipient, and a report routed to account B's inbox carrying A's identifier | the report is delivered | A's recipient is **not** modified |
| E-9 | a campaign send whose provider call is rejected by Meta | the campaign run continues | that contact's recipient is `failed` with Meta's code and title; the remaining contacts are still attempted |
| E-10 | a coexistence number | Meta reports `delivered` for a campaign send from it | same as E-2; no coexistence-specific branch is needed |
| E-11 | a `statuses` payload | — | message *ingestion* does not run for it (upstream already returns early); no contact or conversation is created by a status report |

---

## 5. Security rules

### 5.1 The lookup must be tenant-scoped

The identifier in a status report is **attacker-supplied input** on a public endpoint. Meta's signature is
verified first, which is the real protection — but the lookup must still be narrowed to the inbox the webhook
was routed to, so that a report delivered for one account cannot advance another account's record. The account
and inbox are already resolved before status handling runs (§2), so this costs nothing but a scope.

Upstream's own message lookup is not scoped (`Message.find_by(source_id:)`). Do not take that as the pattern to
follow for the new path; the recipient lookup is new code and must be scoped. (The existing
`source_id` unique index makes a genuine collision unlikely; the rule is about not depending on that.)

### 5.2 Nothing from a report is trusted as content

A report carries a code, a title and a timestamp. The code and title are stored as the provider's own
diagnostic values and must be treated as untrusted text at the point of display, not interpolated into SQL,
log format strings, or anything executable. Message bodies never appear in a status report and must not be
invented from one.

### 5.3 No credential in any record

`source_id`, `error_code` and `error_title` are identifiers and diagnostics. No access token, app secret or
verify token may be written to a recipient, a message, a log line or an error payload on this path.

### 5.4 Do not weaken what already guards the entrance

Signature verification, the inactive-number rejection and the per-sender mutex are existing clean behaviour
with their own history (`docs/p11/00-p10-security-closure.md`, SC3). This package adds handling **after** them
and must not bypass, relax or re-order them.

---

## 6. Failure behaviour

| situation | required behaviour |
|---|---|
| the payload is malformed or a field is missing | log and move on. The webhook must still return success, or Meta retries it indefinitely |
| the record lookup raises | the webhook must not 500; Meta's retry would re-run the whole payload |
| a status value Meta sends that the product does not know | ignore that entry, keep the others. Do not store an unknown state |
| applying the outcome raises | the entry is lost rather than the payload. Prefer a retryable job over an inline write if the write is expensive, but never let one entry fail the request |
| the recipient's campaign or account was deleted | the report matches nothing; §4.3 applies |
| the provider send error has no code or title | record the failure with whatever is available; package D's reason chain (`error_message → error_title → error_code`) tolerates any one of the three |

---

## 7. Callers and dependents

| direction | counterpart | contract |
|---|---|---|
| inbound | OSS `Whatsapp::IncomingMessageBaseService` | extension point at line 230; `statuses` payloads already routed before message handling |
| inbound | OSS `Webhooks::WhatsappEventsJob`, `Webhooks::WhatsappController` | the channel, inbox and account are resolved and the signature verified before this package runs |
| outbound | OSS `Whatsapp::Providers::BaseService` | extension point at line 136; `process_response` returns the provider message identifier on success and `nil` on failure |
| outbound | OSS `Channel::Whatsapp` | extension point at the bottom of `app/models/channel/whatsapp.rb`; `delegate :send_template, to: :provider_service` at `:147` is what discards the provider instance |
| outbound | OSS `Whatsapp::OneoffCampaignService` | extension point at line 148; calls `channel.send_template(to, template_info, nil)` — no `Message` |
| writes to | package D's recipient record | `D-campaign-recipient-outcomes.md` §4.2 owns the advance rule |
| read by | P8 campaign analytics and the per-campaign analytics UI | through package D's record only; nothing reads this package directly |
| must not change | OSS `Messages::StatusUpdateService` | the conversation-message path, including its lock and its forward-only rule |

---

## 8. Acceptance criteria

1. A delivery report for a conversation message behaves exactly as it does today.
2. A delivery report for a campaign send advances that recipient, with the matching timestamp.
3. A failure report stores Meta's code and title separately, and a reason is visible in the recipient list.
4. A report whose identifier matches nothing succeeds, writes nothing, and logs no error.
5. A payload with several status entries applies all of them.
6. A redelivered report leaves the record byte-identical.
7. Out-of-order reports end at the furthest state, with both timestamps set.
8. A report routed to one account cannot modify another account's recipient.
9. A rejected campaign send yields its provider code and title to the recipient record, and the campaign
   continues with the remaining contacts.
10. A coexistence number needs no separate code path.
11. Signature verification, inactive-number rejection and the per-sender mutex are unchanged.
12. No status report creates a contact, a conversation or a message.

---

## 9. Non-requirements and explicit exclusions

**Out of scope, deliberately:**

- **Any unofficial WhatsApp transport.** No QR pairing, no Baileys, no Evolution API, no web-client
  automation. None of it exists in this repository — a search of the source for any of those names returns
  nothing, the product was deliberately taken no further than a discovery exercise, and this package must not
  introduce it. Coexistence through Meta Embedded Signup replaced that idea entirely and is the official
  Cloud API.
- **360dialog (`provider: 'default'`) status handling.** That provider does not send Meta's signed envelope and
  is not part of the campaign path, which requires `whatsapp_cloud` (`oneoff_campaign_service.rb:26-28`).
- **Re-sending, retrying or recovering a failed recipient.** Recording the outcome is the whole requirement.
- **Inbound message handling of any kind.** Contacts, conversations, echoes, identity rotation, media and
  coexistence companion syncs are all upstream's, and clean.
- **Read receipts or delivery indicators in the conversation UI.** Already upstream.
- **A new webhook route, a new verify token, or a change to how webhooks are registered at Meta.**
- **Per-message cost, pricing or conversation-category reporting.** Meta sends some of it on the same payloads;
  nothing in the product consumes it and nothing should start here.

**Recommended simplification:** this package is a router, and should stay one — given a reported state, its
timestamp and its diagnostics, find the one record that owns the identifier and hand the outcome to that
record's own advance rule. Both decisions it makes (which record owns the identifier, and "nothing owns it, so
stop") are one lookup each. All ordering, idempotency and locking belong to the records, where package D's
rule already has to live. If this package ends up containing a second copy of the forward-only rule, the design
has gone wrong.
