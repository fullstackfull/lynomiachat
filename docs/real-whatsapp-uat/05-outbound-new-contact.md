# 05 — Outbound to a new contact (P5 Parts H, I)

**Status: the live send is BLOCKED** (no real token, no real recipient). What follows is traced from the code, and
it changes how symptom 3 should be read.

---

## 1. The headline: symptom 3 is probably not an outbound defect

The reported symptoms were:

2. outbound to an **old** test contact → arrives
3. outbound to a **new** contact → does not arrive

Read as two independent facts, that looks like a selective outbound fault. It almost certainly is not. Here is the
code that decides, in full:

```ruby
# app/services/whatsapp/send_on_whatsapp_service.rb
def perform_reply
  if template_params.present?
    tag_contact_info_template_request
    return send_template_message
  end
  return send_contact_info_request if contact_info_request?

  return send_session_message if message.conversation.can_reply?

  message.update!(status: :failed,
                  external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
end
```

and what `can_reply?` resolves to:

```ruby
# app/services/conversations/message_window_service.rb
when 'Channel::Whatsapp' then MESSAGING_WINDOW_24_HOURS      # always 24h, never blank

def last_message_in_messaging_window?(time)
  return false if last_incoming_message.nil?                 # ← no inbound ever ⇒ false
  Time.current < last_incoming_message.created_at + time
end

def last_incoming_message
  @last_incoming_message ||= @conversation.messages.where(account_id: …).incoming&.last
end
```

`last_incoming_message` reads **a persisted incoming message in Lynomia's own database**. So:

> **If inbound is broken, no incoming message is ever persisted, so `can_reply?` is false for every new
> conversation, so Lynomia fails a plain-text send locally — before Meta is ever contacted.**

That is symptom 3, exactly, and it is produced by symptom 1. The message is marked `failed` and
`external_error` is set to this exact string (`config/locales/en.yml:179`):

> Message not sent because the WhatsApp 24-hour customer service window is closed and no template parameters were
> provided. Send an approved template message instead.

and **no Graph request is made at all**. Looking for an outbound fault in Meta's logs would find nothing, because
nothing was sent. The string is also the thing to search the real database for — it is unambiguous, and it
distinguishes a locally-refused send from one Meta rejected.

### Why the old contact still works

Three explanations, and the diagnosis distinguishes them:

| Explanation | What the evidence looks like |
|---|---|
| that conversation has a persisted incoming message younger than 24h | `can_reply?=true`, `last_incoming=<recent>` — and inbound is therefore **not** globally broken, which points at routing or contact resolution rather than subscription |
| the sends to it are **templates** | `template_params.present?` is checked **first**, so a template never consults the window. Templates are supposed to work outside it |
| its window was opened before inbound broke | `last_incoming` older than 24h ⇒ `can_reply?=false` ⇒ plain text would now fail for the old contact too |

This is the single most informative question in the whole phase, and it is one command:

```bash
bundle exec rails whatsapp:diagnose INBOX_ID=<id> CONTACT=+<the old contact>
```

```
  conversation #<n>: last_incoming=<timestamp or NEVER> can_reply?=<true|false>
```

## 2. What P5 Part H asks for, and why it will succeed

Part H says not to test a new contact with a free-form message, and to use an approved template. The code above is
why that is right: a free-form send to a contact with no open window is refused by Lynomia itself. A template send
takes the first branch of `perform_reply` and never reaches the window check.

So the Part H test is expected to **pass even while symptom 3 persists** — and that result is diagnostic, not
incidental. A template arriving at a new contact while plain text fails confirms:

- the token, `phone_number_id` and WABA are correct
- the number is CONNECTED and able to send
- outbound is healthy
- the only thing wrong is that the window never opens, i.e. inbound

To run it the operator needs an approved template. The diagnosis lists them:

```
templates owned by this WABA (/<WABA_ID>/message_templates):
  templates: N total, M APPROVED
    APPROVED <name> (<language>, <category>)
  [PASS/FAIL] at least one APPROVED template exists to open a new conversation
```

If `M` is zero, a brand-new contact cannot be reached at all — and that is **correct WhatsApp policy, not a
defect**. It would still be worth saying out loud, because it is indistinguishable from a bug to whoever is trying
to message a customer.

## 3. How a Meta error reaches the agent (P5 Part I)

Part I insists that a specific Meta reason must not become a generic "message failed". It does not:

```ruby
# app/services/whatsapp/providers/base_service.rb
def handle_error(response, message)
  Rails.logger.error response.body
  return if message.blank?

  error_message = error_message(response)
  return if error_message.blank?

  message.external_error = error_message
  message.status = :failed
  message.save!
end

# app/services/whatsapp/providers/whatsapp_cloud_service.rb:161-163
def error_message(response)
  response.parsed_response.dig('error', 'message') if response.parsed_response.is_a?(Hash)
end
```

`external_error` carries **Meta's own `error.message` verbatim**, and the agent sees it on the failed message. So
`131047` arrives as its real sentence ("more than 24 hours have passed since the customer last replied…") rather
than as a shrug.

Two honest limits in that path:

1. **The numeric code is not kept.** Only `error.message` is read; `error.code`, `error_subcode` and
   `error_data.details` are discarded. The message text is usually enough to classify, but a code would be a
   better key than prose, and prose is what gets matched against today.
2. **An error with a blank `error.message` leaves the message's status untouched.** `return if error_message.blank?`
   happens *before* `message.status = :failed`, so a malformed error response produces a message that is neither
   sent nor marked failed. Narrow, but it is a real hole: the send silently did nothing.

Neither is this phase's reported symptom, and neither is changed here — P5 Rule 1 and Part G say to fix only the
proven defect. Both are recorded in `08` as observability findings.

## 4. A 200 from Meta is not proof of delivery

Worth stating because P5 Part H asks for the `wamid` and the initial status. The code's own comment records a case
where Meta returns success and drops the message anyway:

> WhatsApp coexistence / username migration: a contact may become addressable only by a Business-Scoped User ID
> (BSUID, e.g. "BR.123…"), with no phone number available. The Cloud API requires a BSUID to be passed in the
> `recipient` field (with `recipient_type: individual`), NOT in `to`. **Passing a BSUID in `to` returns HTTP 200
> with a message id but the message is silently dropped**: the "CC." prefix is stripped and the remainder is
> treated as a phone number (wa_id), which never resolves.

The code handles this correctly in `recipient_params`, switching to `recipient` for a BSUID and keeping `to` for a
phone number. The lesson for the UAT matrix is the general one: **`wamid` returned ≠ delivered.** Only a
`delivered` status webhook proves delivery, which is why Part L is a separate row and not a footnote.

## 5. The outbound classification, if the template test does fail

| Meta's reason | P5 Part I class |
|---|---|
| "more than 24 hours have passed since the customer last replied" (131047) | the window — expected for plain text, a real fault for a template |
| "Receiver is incapable of receiving this message" (131026) | `INVALID_RECIPIENT` — the number is not on WhatsApp, or cannot receive |
| template name/language not found | `TEMPLATE_NOT_APPROVED` or `TEMPLATE_LANGUAGE_MISMATCH` — the diagnosis prints each approved template with its language, so the two are distinguishable |
| "Invalid OAuth access token" / "Error validating application" (190) | `TOKEN_SCOPE` |
| "Unsupported post request. Object with ID … does not exist" | `WRONG_PHONE_NUMBER_ID` or `WRONG_WABA` |
| "(#131049) … healthy ecosystem engagement" | `QUALITY / MESSAGING_LIMIT` — the diagnosis prints `quality_rating` and `messaging_limit_tier` |
| "(#368) temporarily blocked for policies violations" | `BUSINESS_RESTRICTION` / `META_POLICY` |

The diagnosis prints the last five failed outbound messages with their `external_error` verbatim, so this table is
applied to real text rather than to a guess:

```
failed outgoing in the last 7 days: N
  <timestamp> failed: <Meta's own message, or the outside-window string>
```

If those errors read *"Message not sent because the WhatsApp 24-hour customer service window is closed…"* rather
than anything from Meta, that is the confirmation that the sends never left the building — and the investigation
belongs entirely in inbound.

---

## 6. What the continuation changed about this document

Nothing in the send path, and that is the finding. `SendOnWhatsappService` was read closely for a defect that would
explain symptom 4 and does not contain one: its refusal is correct WhatsApp policy, correctly reported, with the
window message and no call to Meta. Two things did change around it.

**The chain now completes.** Before the inbound fix, a new contact's message was discarded, so
`conversation.can_reply?` stayed false and a plain reply kept failing locally — which is exactly how a broken
inbound masquerades as an outbound fault. After the fix the chain is: new contact sends a message → the incoming
message persists → `can_reply?` is true → a plain reply is allowed. Two regressions pin the ends of it
(`opens reply eligibility for the conversation it creates`, and `leaves a conversation with no inbound message
outside the window`).

**The reason survives a retry.** §3's point — that Meta's specific error reaches the agent rather than a generic
"failed" — used to be undone by the Retry button, which cleared `external_error` before anything could read it.
`09` §5 keeps it as `content_attributes['previous_external_error']`.

The error wording in §3 was checked rather than assumed: `errors.whatsapp.message_outside_messaging_window` already
reads *"Message not sent because the WhatsApp 24-hour customer service window is closed and no template parameters
were provided. Send an approved template message instead."* It names the cause and the next action, and it is not
disguised as a Meta delivery failure, so it was left alone.
