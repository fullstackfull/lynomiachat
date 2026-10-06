---
title: Webhooks
description: You will have an endpoint of your own receiving account events as JSON, you will know how to verify that a delivery really came from us, and you will know exactly what happens when a delivery fails.
position: 20
tags: [integrations, webhooks]
seo_description: "Subscribe to Lynomia Chat events, read the payload, verify the signature, and understand that a failed delivery is not retried."
---
A webhook is a URL you own. You tell Lynomia Chat which events you care about, and each time one happens we POST
a JSON body to that URL. It is the way to make something outside the product react to what happens inside it.

## When to use it

When another system needs to know. A ticketing tool that should open a case when a conversation is created, a
dashboard that counts incoming messages, an automation tool that starts a workflow when a contact is added.

## When not to use it

- **To send messages or change anything.** Webhooks are outbound only. Use the API for writes.
- **To answer a conversation in line.** Whatever your endpoint returns is discarded. Nothing it sends back enters
  the conversation.
- **For one specific rule.** If you only want a POST when a particular condition is met, the webhook action in an
  [automation rule](automation-rules) or a [flow](flow-builder) is narrower and cheaper than subscribing to every
  message in the account.

## What you need first

An administrator account, and an endpoint that is reachable from the public internet over HTTP or HTTPS and
answers within a few seconds. On some plans, Webhooks shows an upgrade notice instead of the list.

## Steps

1. Go to **Settings → Integrations → Webhooks** and choose **Add new webhook**.
2. Enter the URL, give it a name, and tick the events you want. At least one event is required.
3. Save. The secret is shown once on the confirmation screen; copy it then. You can also reveal it later in the
   webhook's edit form.

## The events

Ten events are offered in the form. An eleventh, `inbox_updated`, appears only if your installation has inbox
events switched on.

| Event | Fires when |
|---|---|
| `conversation_created` | a conversation is opened |
| `conversation_updated` | any attribute of a conversation changes |
| `conversation_status_changed` | its status changes |
| `message_created` | a message is added |
| `message_updated` | a message changes |
| `contact_created` | a contact is added |
| `contact_updated` | a contact's attributes change |
| `webwidget_triggered` | a visitor opens the live chat widget |
| `conversation_typing_on` / `conversation_typing_off` | someone starts or stops typing |
| `inbox_updated` | an inbox's settings change |

Two things to expect. `conversation_updated` is noisy — it fires on changes you would not call an update, so
filter on `changed_attributes` rather than treating every one as news. And only incoming, outgoing and template
messages are sent; private notes and activity lines are not.

## The payload

Every body is a JSON object with an `event` key naming the event, plus the object the event is about.

| Event group | Body carries |
|---|---|
| Message events | the message — id, `content`, `content_type`, `message_type`, `private`, `source_id`, attachments when present — plus its `conversation`, `inbox`, `sender` and `account` |
| Conversation events | the conversation — `id`, `status`, `priority`, `labels`, `inbox_id`, `meta` with sender, assignee and team, `custom_attributes`, timestamps — its newest message, and `account` |
| Contact events | the contact — `id`, `name`, `email`, `phone_number`, `identifier`, `avatar`, `custom_attributes`, `additional_attributes`, `blocked` — and `account` |

The three "changed" events — `conversation_updated`, `conversation_status_changed` and `contact_updated` — add a
`changed_attributes` array describing what moved. `contact_updated` and `inbox_updated` are not sent at all when
nothing changed.

## Verifying a delivery

Each webhook has its own secret, and signed deliveries carry three request headers: a delivery id, a timestamp,
and a signature. The signature's value is `sha256=` followed by the HMAC-SHA256 of the timestamp, a full stop, and
the **raw** request body, keyed with the secret:

```
sha256=HMAC_SHA256(secret, "<timestamp>.<raw body>")
```

Compute it over the bytes you received, not over a re-serialised copy, and compare in constant time. Reject
anything that does not match, and treat the delivery id as the key for ignoring a repeat.

The three headers are named exactly:

| Header | Carries |
|---|---|
| `X-Chatwoot-Signature` | `sha256=` followed by the HMAC above |
| `X-Chatwoot-Timestamp` | the timestamp the signature was computed over |
| `X-Chatwoot-Delivery` | the delivery id, when one is available |

Those names are part of the wire format and do not change with the installation's branding.

## When a delivery fails

This is the part worth reading twice. A webhook delivery is **attempted once**.

| | What happens |
|---|---|
| Your endpoint is slow | the request is abandoned after the installation's webhook timeout, five seconds by default |
| Your endpoint answers 4xx or 5xx | the delivery is counted as failed |
| Your endpoint is down | the delivery is counted as failed |
| Any of the above | the failure is written to the server log. Nothing is retried, nothing is queued, and nothing is shown to you |

So events that occur while your endpoint is unavailable are gone. If you cannot afford to lose them, accept the
POST into a queue of your own, answer immediately, and process it afterwards.

## Who can do this

Administrators only. The custom role permission list has no entry for webhooks, so it cannot be delegated — see
[roles and permissions](roles-and-permissions).

## Limits

- **No retries, no delivery history, no replay, and no test button.** You verify a webhook by triggering a real
  event.
- **One webhook per URL per account.** To get the same events twice, use two URLs.
- **Private and internal addresses are refused.** A URL resolving to localhost or a private network is not
  delivered to. Your endpoint has to be publicly reachable.
- **`inbox_created` cannot be subscribed to in the form.** It exists in the API's event list only.
- **The response body is never read**, and the response's content type is not checked.
- **The payload is not configurable.** You cannot add fields, remove fields or choose a format.
- **Subscriptions are account-wide.** You cannot subscribe to one inbox's messages only; filter by `inbox` in
  your own code.

## Other things that POST to a URL

Webhooks are one of several. They are not interchangeable, and only some are signed.

| Sent by | `event` in the body | Signed |
|---|---|---|
| A webhook subscription | the event you subscribed to | yes, with the webhook's secret |
| The webhook action in an [automation rule](automation-rules) | `automation_event.<trigger>`, with a `commerce` block on a Commerce trigger | no |
| The webhook action in a [macro](macros) | `macro.executed` | no |
| The webhook node in a [flow](flow-builder) | `flow_webhook`, with the flow, session and the values the flow collected | yes, with the flow bot's secret |

## Related

- [Integrations](integrations)
- [Automation rules](automation-rules) · [Macros](macros) · [Flow builder](flow-builder)
- [Roles and permissions](roles-and-permissions)
- [When something is not working](troubleshooting)

## If it does not work

**Nothing arrives.** Check in this order: the endpoint is publicly reachable, it answers within five seconds, and
the event you expect is actually ticked. A URL on a private network never receives anything.

**Some events arrive and others do not.** Private notes and activity lines are not sent as messages, and
`contact_updated` is suppressed when nothing changed.

**My signature check fails.** You are almost certainly hashing a re-serialised body. Hash the raw bytes, and
include the timestamp and the full stop before them.

**I lost events during an outage.** There is no backfill. Read the API for the period you missed.

**The Webhooks page shows an upgrade notice.** API and webhooks are not included on your plan.
