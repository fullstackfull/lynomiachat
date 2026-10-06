# 06 — Delivery status and failure visibility (P5 Parts J, K)

P5 asks what Lynomia does with Meta's `sent` / `delivered` / `read` / `failed` callbacks, whether a refusal is
visible to the agent who sent the message, and whether a retry tells the truth.

---

## 1. Statuses and customer messages share one subscription

A Cloud API delivery status arrives on the **`messages` webhook field** — the same field that carries inbound
customer messages:

```json
{ "object": "whatsapp_business_account",
  "entry": [{ "changes": [{ "field": "messages",
    "value": { "metadata": { "phone_number_id": "…" },
               "statuses": [{ "id": "wamid…", "status": "failed",
                              "errors": [{ "code": 131047, "title": "Re-engagement message" }] }] } }] }] }
```

This single fact is the most useful diagnostic lever in the whole phase, because it splits the reported symptoms
cleanly:

| What the operator sees | What it proves |
|---|---|
| outbound messages reach `delivered` / `read` in Lynomia, but no inbound appears | Meta **is** delivering to this host, the signature **is** valid, the `phone_number_id` **does** resolve — the fault is after step 8 of `04` |
| outbound messages stay on `sent` forever **and** no inbound appears | the `messages` field is not reaching ingestion at all — subscription, signature, callback override, or the latch defect in `08` |
| outbound reaches `delivered` and inbound appears, but one send failed | a genuine per-message refusal — read `external_error`, §3 |

The second row is what the reported production symptoms look like, and it is exactly what the latch defect
produces: `Webhooks::WhatsappEventsJob` is the single entry point for **every** WhatsApp webhook event, so the old
`channel_is_inactive?` guard discarded status callbacks along with customer messages. A latched channel therefore
shows outbound messages frozen at `sent` — never `delivered`, never `read` — while the message itself is sitting on
the recipient's phone. The ticks in the dashboard were lying in the same way, and for the same reason.

That row is now in the diagnosis output, which counts incoming messages per inbox and prints the reauthorization
flag beside it.

## 2. The status path, in full

```ruby
def perform
  processed_params
  return process_statuses if processed_params.try(:[], :statuses).present?
  …
end

def process_statuses
  status = @processed_params[:statuses].first
  return unless find_message_by_source_id(status[:id])

  update_whatsapp_identifiers_from_status(status)
  update_message_with_status(@message, status)
rescue ArgumentError => e
  Rails.logger.error "Error while processing whatsapp status update #{e.message}"
end
```

Three properties worth stating, because each one is a deliberate choice rather than an accident:

- **A status takes the early return, before `process_messages`.** So it never reaches the dedup lock. That is
  correct: status updates are idempotent and forward-only (§4), so there is nothing to serialize, and
  `contact_sender_id` returns nil for a status-only payload, which also bypasses the per-contact mutex. A status
  webhook is the cheapest event in the pipeline.
- **A status for an unknown `wamid` is dropped.** `find_message_by_source_id` returns nil and the method returns.
  There is nothing to update, so this is right — but it is also a signal: statuses arriving for ids this
  installation never stored means the *outbound* write failed, not the inbound one.
- **`ArgumentError` is caught and logged.** It comes from `update_whatsapp_identifiers_from_status` on a malformed
  identifier. A status we cannot parse must not retry forever.

## 3. A refusal reaches the agent

`update_message_with_status` flattens Meta's error into the field the UI reads:

```ruby
external_error = if status[:status] == 'failed' && status[:errors].present?
                   error = status[:errors]&.first
                   "#{error[:code]}: #{error[:title]}"
                 end
Messages::StatusUpdateService.new(message, status[:status], external_error).perform
```

So a failed send carries `external_error` = `"131047: Re-engagement message"` — Meta's own numeric code, which is
what makes a refusal diagnosable rather than merely red. The agent sees the failure on the bubble; the code is what
distinguishes "outside the 24-hour window" (131047) from "no such number" (131026) from a template rejection.

The locally-generated refusal in `05` takes the same route: `SendOnWhatsappService` writes
`status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window')` without Meta ever
being contacted. Both are visible in the same place, which is why symptom 4 was reported as "doesn't arrive" rather
than "shows an error" — it does show an error, and the error says exactly what `08` concluded.

## 4. Transitions are forward-only, under a row lock

```ruby
message.with_lock do
  next false unless valid_status_transition?
  update_message_status
end

# forward-only, except that failed is always reachable and always escapable
status == 'failed' || current_status == 'failed' || new_priority >= current_priority
```

`read` cannot be undone by a late-arriving `delivered`, which matters because Meta does not guarantee callback
order. The `with_lock` re-checks the guard **inside** the lock, so two concurrent status workers cannot both pass
it. `resolved_external_error` keeps the existing error when a new `failed` arrives without one.

## 5. What the retry fix changed here

Before this phase, pressing **Retry** on a failed message called `StatusUpdateService.new(message, 'sent')` —
permitted, because any transition out of `failed` is allowed — and `resolved_external_error` returns nil for a
non-failed status. The provider's reason was erased at the moment the operator most needed it, and
`content_attributes` was then replaced wholesale, taking the rest with it.

Now the reason is captured **before** the status change and kept on the message as
`content_attributes['previous_external_error']`, with `retried_at` marking it as historical so it cannot be read as
the current state (`09` §5). One slot, not an event store: the useful thing is the most recent real refusal.

## 6. What the live run adds

Everything above is static and test-covered. The real server supplies one thing this cannot: whether status
callbacks are arriving at all. The command in `10` reports, per inbox, the newest incoming message timestamp and
the current status distribution of recent outbound messages. A column of `sent` with no `delivered` is the second
row of §1's table, and it is the answer.
