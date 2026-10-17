# Campaign send throttling — safety verification

Verification of the eight safety properties required before the throttling increment closes.
Each states what was checked, what was found, and where the evidence is. Two of the eight were
found **broken** and are fixed here; one more was found broken in adjacent code while testing
them and is fixed here too.

Code under verification:

| File | Role |
| --- | --- |
| `custom/app/services/campaigns/throttle.rb` | operational pacing |
| `custom/app/services/campaigns/send_guard.rb` | the final eligibility gate |
| `custom/app/services/campaigns/outbound.rb` | the kill switch |
| `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | WhatsApp sender |
| `app/services/sms/oneoff_sms_campaign_service.rb` | SMS sender |
| `app/services/twilio/oneoff_sms_campaign_service.rb` | Twilio SMS sender |

---

## 1. Pacing, provider limits and commercial quotas are three different things — PASS

They are now named and distinguished in the module docblock, because conflating them is how a
courtesy ceiling ends up being relied on as a quota.

| | What it is | Who enforces it | Failure mode |
| --- | --- | --- | --- |
| **Pacing** | a courtesy ceiling on how fast *we* dial, so a merchant stays inside their messaging tier | `Campaigns::Throttle`, best effort | fails **open** |
| **Provider limit** | the provider's own 429 and messaging tier | the provider | provider refuses |
| **Commercial quota** | "this plan allows N sends this period" | `Billing::MeteredUsage` (P5G) | fails **closed** |

The commercial quota is explicitly recorded in the docblock as something that **must not** be
routed through this module, because a quota that fails open is not a quota. It belongs with
`Billing::ResourceLimit.exceeded`, which takes a lock and refuses.

**That requirement was honoured when P5G built it.** `Billing::MeteredUsage` is a separate
module, takes the same `account.lock!` as `Billing::ResourceLimit#exceeded`, reads its
ceiling from `Billing::Entitlements` so overrides and bundled grants are both honoured, and
raises rather than permitting when it cannot reach its counter. It is taken **after** the
pacing and **after** the final eligibility re-check, so a unit of a paid allowance is never
spent on somebody the next line would have refused.

## 2. Redis failure never bypasses provider restrictions or hard subscription limits — PASS

A degraded throttle returns `:degraded`, lets the send through, and records it. This is safe
only because of what it is *not* protecting:

- **Provider restrictions** are not enforced here at all. The provider's 429, its messaging
  tier, template approval, the 24-hour window and the authentication-template guard are all
  enforced by the provider or by the sender that owns the channel. A throttle that stopped
  working cannot relax any of them, because it never enforced any of them.
- **Hard subscription limits** are not enforced here either, and P5G is instructed not to put
  them here. Nothing in the send path reads this module for authorization.
- **Authorization is consent**, and consent fails **closed** in `Campaigns::SendGuard`. A
  degraded throttle does not touch it: `clear_to_send` still refuses a withdrawn, suppressed,
  blocked or revoked recipient when Redis is unreachable.

Evidence: `spec/services/campaigns/throttle_spec.rb` — "lets the send through when Redis
cannot be read", "records an operations signal when its counter is unreachable";
`spec/services/campaigns/send_guard_spec.rb` — "still refuses a withdrawn recipient when the
throttle is degraded", "lets an eligible recipient through when the throttle is degraded".

## 3. Pacing cannot bypass the kill switch, consent withdrawal or installation revocation — **WAS BROKEN, FIXED**

**The defect.** The senders called `Campaigns::SendGuard.refusal` and *then*
`Campaigns::Throttle.pace`, in that order. Pacing sleeps — up to `MAX_WAIT` per recipient, and
a large audience spends most of its wall-clock time inside those sleeps. So the answer was
taken **before** the wait and acted on **after** it: a withdrawal, a kill switch or a
revocation landing during the wait was read, found nothing left to stop, and the message went
out anyway. This was a regression introduced with the throttle itself, and it undid the entire
point of asking late.

**The fix.** `Campaigns::SendGuard.clear_to_send(contact, campaign, channel)` is now the whole
gate and the only caller of `pace`. It asks, paces, and asks again, in that order. All three
senders call it; `Campaigns::Throttle.pace` has no other caller anywhere in the codebase.

Two details are deliberate:

- **It asks before pacing as well.** Not a duplicate: it keeps an already-refused recipient
  from claiming a slot in the ceiling. A mostly-suppressed audience would otherwise pace
  itself against its own skips.
- **The second ask is conditional.** `pace` reports whether it actually slept (`:clear` /
  `:waited` / `:degraded`). When no time passed, the second ask would re-run the same queries
  for the same answer at a per-recipient cost across the whole audience. When it slept, the
  first answer is stale by construction and is re-taken.

Everything `refusal` can return is re-asked after the wait: the kill switch (step 1),
installation revocation (step 2), blocking and withdrawal in both consent stores (steps 3–7)
and the missing promotional grant (step 8).

**Campaign cancellation** did not exist when this note was written: `campaign_status` was
`active / completed / processing / blocked`, and `blocked` is only ever set *before* a run
begins, so a check for a cancellation would have been unreachable code.

**P5D added it and enforced it here, as this note promised.** `campaign_status: cancelled` is
terminal and is read at step 2 of the precedence — from the live row, not the campaign object
the run started with, because cancelling is something an operator does *while* a campaign is
running. A run in flight stops at its next recipient
(`spec/models/campaign_cancellation_spec.rb`).

Evidence: `spec/services/campaigns/send_guard_spec.rb` → `.clear_to_send` — "honours a
withdrawal that lands during the throttle wait", "honours a kill switch thrown during the
throttle wait", "honours an installation revoked during the throttle wait", "refuses before
pacing, so a refused recipient never claims a slot in the ceiling", "does not re-ask when
pacing did not actually wait".

## 4. Eligibility is revalidated immediately before provider submission, including after waiting — **WAS BROKEN, FIXED**

Property 3 covers the ordering. Testing it surfaced a second, independent defect in the same
boundary.

**The defect.** The consent *tables* were always queried fresh, so a withdrawal arriving
mid-run was honoured. Three other inputs were not, because they are **attributes of objects
loaded before the loop began**:

| Input | Where it was read from | Consequence |
| --- | --- | --- |
| `account.settings` | `campaign.account`, a memoised association held for the whole job | the **per-account kill switch** did nothing until the next job |
| `store.status` | `campaign.commerce_store`, likewise memoised | an **installation revoked mid-run** did nothing until the next job |
| `contact.blocked` | each contact, out of the audience relation resolved at dispatch | an **agent blocking a shopper mid-run** did nothing until the next job |

These are exactly three of the four cases `Campaigns::SendGuard`'s docblock promises to
honour. The docblock was a false claim.

**The fix.** `Campaigns::SendGuard#live` re-reads each record by primary key at the gate. A
narrow `find_by` rather than `reload`, because `reload` raises on a deleted row and a contact
deleted mid-run must *refuse that recipient*, not abort a run that has already handed messages
to the provider. `Commerce::MessagingEligibility` reads a nil contact as
`:contact_unavailable`, which is the right answer for somebody who no longer exists.

Cost: three primary-key lookups per recipient, against a path already doing several consent
queries per recipient and capped by the pacing ceiling at 10 sends/second by default.

A deleted *store* cannot reach the gate — `campaigns` has a foreign key to `commerce_stores`,
so the database refuses the delete. That case is therefore not guarded and not tested.

Evidence: `spec/services/campaigns/send_guard_spec.rb` → "reading live rows rather than the
objects the run started with". Every example changes the row **through a different object**
than the one the campaign holds, because that is what reproduces the defect; mutating
`campaign.account` directly would pass against the broken implementation.

## 5. Interrupted workers, retries and concurrent workers cannot double-send or exceed the ceiling — PASS

Three independent protections, each now verified under real contention rather than by
inspection:

1. **One execution per campaign.** `Campaign#mark_processing!` flips the status inside
   `with_lock`, so losers find it already `processing` and return without executing. Verified
   with four threads on four connections racing `trigger!` on the same campaign row: the
   sender is constructed exactly once.
2. **One outcome row per recipient.** `index_campaign_recipients_on_campaign_id_and_contact_id`
   is UNIQUE. Even if two workers both reached the loop, a recipient cannot acquire two
   outcome rows, so the analytics denominator stays the audience.
   (`index_campaign_recipients_on_source_id` is additionally unique where non-null, so one
   provider message id cannot be recorded twice either.)
3. **The ceiling holds under contention.** The count is INCR's own return value, never a
   separate read. A read-then-write would let several threads read the same number, each
   decide there was room, and overshoot by exactly the number of workers — the failure mode
   that makes a ceiling decorative under the only conditions it is needed. Verified with eight
   concurrent claims taking eight distinct slots.

This file opts out of transactional fixtures: under them both threads share one connection
inside one transaction and cannot contend for a row lock at all.

Evidence: `spec/models/campaign_send_concurrency_spec.rb` (3 examples).

## 6. No unbounded worker sleeping — PASS

`MAX_WAIT = 2.0` bounds a single `pace` call, and the loop checks `waited < MAX_WAIT` on every
iteration, so a clock jump, a pathological ceiling or a stuck counter cannot park a worker
indefinitely. A window is one second, so two seconds is already generous.

The sleep is **per recipient inside a single-threaded campaign loop**, not a job-level wait: a
paced campaign takes longer, it does not occupy a worker waiting for an external event. There
is no case here where the work should be re-enqueued instead — re-enqueueing per recipient
would replace a 100ms sleep with a queue round-trip and a redelivery risk, which is worse on
both counts.

Evidence: `spec/services/campaigns/throttle_spec.rb` — "never blocks a worker for longer than
its own ceiling on waiting".

## 7. Throttling failures are recorded in logs and monitoring — PASS, after a fix

A degraded throttle writes a `warn` line *and* an `Operations::Signal`, so it is visible on
the health surface an operator actually watches rather than only to whoever greps the logs
afterwards.

**It was silently not recording.** `Operations::Signal` validates `source` and `signal`
against allow-lists and `Operations::SignalRecorder::DETAIL_KEYS` drops any other detail key,
and the recorder never raises into its caller. The first version used `source: 'campaigns'`
(the allow-list has `campaign`) and `detail: { error: ... }` (the allow-list has `code`), so
the signal was dropped and nothing was ever written. Both are corrected, the reason why is
recorded next to the call so the next edit does not repeat it, and the spec now asserts the
row exists with its source, signal, reason and detail.

Evidence: `spec/services/campaigns/throttle_spec.rb` — "records an operations signal when its
counter is unreachable".

## 8. The four-sender regression coverage is intact — PASS

All three sender services and the WhatsApp custom overlay still route through the gate, and
`Campaigns::Throttle.pace` has exactly one caller in the codebase
(`Campaigns::SendGuard.clear_to_send`), which is what keeps a future sender from reintroducing
the ordering defect by calling them separately.

```
495 examples, 0 failures
```

`spec/services/campaigns spec/services/partners spec/services/consents spec/services/contacts
spec/contracts spec/requests/platform spec/services/whatsapp/oneoff_campaign_service_spec.rb
spec/services/sms/oneoff_sms_campaign_service_spec.rb
spec/services/twilio/oneoff_sms_campaign_service_spec.rb spec/models/campaign_spec.rb
spec/models/campaign_blocked_spec.rb spec/models/campaign_send_concurrency_spec.rb`

---

## Summary

| # | Property | Outcome |
| --- | --- | --- |
| 1 | pacing ≠ provider limit ≠ commercial quota | PASS; the quota exists as of P5G and is a separate, fail-closed module. P5H fixed its lock (it spanned nothing) and moved where it is taken (it charged for unsent messages) — see §1 |
| 2 | Redis failure bypasses no provider or subscription limit | PASS |
| 3 | pacing cannot bypass kill switch / withdrawal / revocation / **cancellation** | **WAS BROKEN — FIXED**; cancellation added in P5D |
| 4 | eligibility revalidated after the wait | **WAS BROKEN — FIXED** |
| 5 | no double-send, no ceiling overshoot under concurrency | PASS (now verified under contention) |
| 6 | no unbounded sleeping | PASS |
| 7 | failures in logs and monitoring | PASS (signal was being dropped; fixed) |
| 8 | four-sender regression intact | PASS |

Campaign cancellation (part of property 3) was **deferred to P5D** and has since been
delivered: the state exists, the gate reads it live, and a run in flight stops at its next
recipient. The commercial quota named in property 1 was **deferred to P5G** and has since been
delivered as `Billing::MeteredUsage`, outside this module and failing closed, exactly as this
note required. Both deferrals are closed; neither was silently dropped.
