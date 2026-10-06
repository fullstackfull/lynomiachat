# 07 — Coexistence, and what P5 told us not to touch (P5 Parts L, Q)

P5's DO-NOT list names Coexistence twice: *"do not disconnect Coexistence"*, *"do not re-register the number"*.
Both constraints are correct, and the code explains why they matter more here than on a plain Cloud API number.

**Nothing in this phase changed any coexistence behaviour.** This document records what the behaviour is, so the
next operator does not reach for the destructive fix.

---

## 1. What a coexistence number is, in this codebase

A coexistence number is a number that stays live in the **WhatsApp Business app** on someone's phone while also
being reachable through the Cloud API. Lynomia records it as an ordinary `Channel::Whatsapp` with
`provider: 'whatsapp_cloud'` plus one marker:

```ruby
# app/services/whatsapp/channel_creation_service.rb
config[:is_coexistence] = true if @is_coexistence
```

The flag arrives from the embedded-signup FINISH event, is cast at the controller boundary
(`ActiveModel::Type::Boolean.new.cast(params[:is_coexistence])`), and changes exactly two things downstream.

## 2. Thing one: it suppresses `/register`

```ruby
def should_register_phone_number?
  return false if @is_coexistence
  return false if @is_coexistence.nil? && health_data[:is_on_biz_app]

  !phone_number_verified? || phone_number_needs_registration?
end
```

A coexistence number is **already registered** — that is what makes it work in the Business app — so calling
`/register` on it is not merely redundant. It is the call that takes the number *off* the phone. That is the whole
content of P5's "do not re-register the number", and the guard that implements it is three-valued on purpose:

| `is_coexistence` | Behaviour | Which caller |
|---|---|---|
| `true` | never register; no health call at all | embedded signup, FINISH event said coexistence |
| `false` | the front end positively ruled coexistence out, so trust it and skip the health probe | embedded signup, ordinary Cloud API number |
| `nil` | no signal — fall back to asking Meta `is_on_biz_app` | manual setup, the voice toggle, a direct webhook re-registration |

The `nil` branch is why the fallback exists at all: three callers reach `WebhookSetupService` without ever having
seen an embedded-signup event, and for them Meta's own answer is the only available signal. An explicit `false`
must **not** take that branch, because then every ordinary signup would pay for a health call whose answer the
front end already supplied.

## 3. Thing two: outbound from the phone comes back as an echo

When the business replies from the WhatsApp Business app, Meta sends the reply back to the webhook as
`field: 'smb_message_echoes'`, and the job routes it with `outgoing_echo: true`:

```ruby
def message_echo_event?(params)
  params.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
end
```

Echo payloads **reverse the direction fields** — `from` is the business number, `to` is the contact — which is why
`contact_sender_id_from_message_echoes` reads `to_parent_user_id` / `to_user_id` / `to`, while the inbound path
reads the `from_*` family. Getting that backwards would serialize an echo against the wrong contact's mutex and
let two webhooks create two conversations for one thread.

`smb_message_echoes` is in `WEBHOOK_DEFAULT_FIELDS`, so every subscription this product creates carries it:

```ruby
WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes message_template_status_update].freeze
```

## 4. Why this matters for the reported symptoms

Three consequences, all of which bear directly on `08`:

1. **`smb_message_echoes` and `messages` are separate fields on the same subscription.** If the subscription were
   the fault, echoes would stop too. The diagnosis prints the WABA's actually-subscribed field list, so this is
   one line to check rather than an inference.
2. **An echo is an inbound webhook for ingestion purposes.** It goes through the same `Webhooks::WhatsappEventsJob`
   and therefore through the same `ingestible?` gate. So the latch defect in `08` discarded the business's *own*
   replies from the Business app as well as the customer's messages — a coexistence account under the latch lost
   both halves of the conversation, not one.
3. **Coexistence raises the cost of a wrong fix.** On a plain Cloud API number, re-registering is wasteful. On a
   coexistence number, it is destructive and it is the user's phone that breaks. The P5 constraint is not
   conservatism; it is the difference between a configuration change and an outage for the person holding the
   handset.

## 5. The `unsupported` placeholder is a coexistence artefact

```ruby
# WhatsApp delivers messages it cannot render (e.g. coexistence companion-device syncs that
# fail with error 131060) as type: unsupported with no content. We still persist a placeholder
# so the contact/conversation isn't created "headless" and agents know to check the WhatsApp app.
def create_unsupported_message(message)
```

Worth naming because it is the one place where the product deliberately stores a message it cannot display. The
alternative — dropping it — produces an empty conversation with no explanation, which is the failure mode this
whole phase is about. The placeholder is the correct pattern, and §1 of `09` applies the same principle to the
latch: persist what you have, degrade the part you cannot do.

## 6. What the diagnosis reports, and what it does not do

`Whatsapp::Diagnosis` prints coexistence indicators by scanning `provider_config` for keys matching
`/coexist|smb|business_app|platform/i` and showing them with their values. Two deliberate properties:

- it is a **pattern scan, not a fixed key read**, because the marker's exact spelling has varied across signup
  paths and a missing key would otherwise read as "not coexistence" — the more dangerous wrong answer;
- it reports and stops. The diagnosis never calls `/register`, never writes `provider_config`, never touches the
  subscription. P5's read-only rule is enforced by the service having no write path to Meta or Redis at all,
  not by a flag — and by reading configuration with a plain SELECT, since the ordinary accessor is create-on-read
  (`10` §1).

## 7. What the live run adds

| Question | Answer needs |
|---|---|
| is this number actually on coexistence? | Meta's `is_on_biz_app` for the phone number — in the diagnosis output |
| are echoes arriving? | the `smb_message_echoes` field in the WABA's subscribed list, plus whether any message rows exist with an echo source |
| is the Business app still holding the number? | the operator's phone. Not something any command can answer, and the reason the DO-NOT list exists |
