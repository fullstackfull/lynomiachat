---
title: Agent bots
description: Connect a bot you host to an inbox, receive its conversation events over a webhook, and reply through the API as the bot.
position: 40
tags: [automation]
seo_description: "Agent bots in Lynomia Chat: the events your webhook receives, how deliveries are signed, and when a flow is the better choice."
---
An agent bot is a service **you** write and host. Lynomia Chat posts conversation events to a URL you give it,
and your service decides what to do and replies through the API using the bot's own credentials.

There is no canvas and no rule list — just events in, API calls out. It can do anything your code can do, and
nothing it cannot.

## When to use one

- **Your logic lives somewhere else already.** An order system, a CRM, a booking engine, a model you host.
- **You need to call something during the conversation** that the product has no node for.
- **You want a bot on a channel a flow cannot run on.** A flow is WhatsApp Cloud only; a bot receives events from
  whatever inbox you attach it to.

## When NOT to use one

- **When a [flow](flow-builder) would do.** A menu, a question, an order lookup and a handoff need no code, no
  server and no uptime from you. See **Agent bot or flow?** below.
- **When nothing has to be asked.** Routing and labelling on facts you already have is an
  [automation rule](automation-rules).
- **When you cannot keep a service up.** If your endpoint is down, conversations go unanswered.

## What you need first

An **administrator** account, and an HTTPS endpoint that accepts a POST and answers quickly.

## Steps

1. **Settings → Bots → Add Bot**.
2. Give it a name, a description and the **webhook URL**. An avatar is optional.
3. Save. You are shown an **access token** and a **webhook secret**. Copy both now; they stay available in the
   bot's settings, and either can be regenerated later.
4. Open the inbox you want the bot to answer, and select it under the inbox's bot setting. One bot per inbox.
5. Verify the signature on the first delivery, then start replying through the API with the access token.

## The events your webhook receives

| Event | Sent when |
|---|---|
| message created | a message is added to a conversation the bot can see |
| message updated | an existing message changes |
| conversation opened | a conversation moves into open |
| conversation resolved | a conversation moves into resolved |
| conversation status changed | its status changes, with what changed |
| conversation updated | something else about it changes, with what changed |

A website inbox also sends an event when a visitor triggers the widget.

**There is no "conversation created" event for bots.** The first thing your service hears about a new
conversation is its first message.

## How a delivery is signed

Each POST carries a JSON body, a unique delivery identifier, a timestamp, and a signature: HMAC-SHA256 over the
timestamp and the raw body, keyed with the bot's webhook secret. Recompute it over the raw bytes you received,
compare, and reject anything that does not match or carries an old timestamp. The delivery identifier is how you
make your handler idempotent, which matters because deliveries can repeat.

## A worked example

You want order status answered from your own warehouse system on a WhatsApp number.

1. Create the bot with your endpoint's URL and copy the secret and token.
2. Attach it to the WhatsApp inbox. New conversations arrive **pending**, and your endpoint gets each message.
3. Your service verifies the signature, looks the order up, and posts a reply through the API as the bot.
4. When it cannot answer, it assigns a team, and your people pick the conversation up as usual.

## Agent bot or flow?

| | Agent bot | Flow |
|---|---|---|
| **Who runs the logic** | your server | Lynomia Chat |
| **Who keeps it up** | you | nobody, it is hosted |
| **Channels** | any inbox you attach it to | WhatsApp Cloud only |
| **Built by** | a developer, in code | an administrator, on a canvas |
| **Reaching your own systems** | anything | a webhook node, and order lookups |
| **Buttons and lists** | you construct them | nodes for both, with WhatsApp's limits enforced |
| **Changing it** | deploy | edit the draft and publish |
| **Testing it first** | your own staging | built in, against a test contact |

Pick a flow unless you need to reach a system of your own, or a channel a flow cannot run on. A flow is less
work and has nothing to break on your side.

**Flows do not appear on the Bots page.** They are both bots underneath, but the page deliberately lists only
webhook bots, so each is managed in one place.

## Who can do this

| | Agent | Administrator |
|---|---|---|
| **See the bots list** | yes | yes |
| **Create, edit, delete** | no | yes |
| **Regenerate the token or secret** | no | yes |

Bots are not one of the permissions a custom role can be granted. See
[roles and permissions](roles-and-permissions).

## Limits

- **One active bot per inbox.** A flow and a webhook bot cannot both answer the same inbox.
- **A bot's type is fixed at creation.** A webhook bot cannot become a flow, or the reverse.
- **Deliveries time out quickly** — five seconds by default. Acknowledge fast and do the work afterwards.
- **Retries are limited.** A delivery your service answers with 429 or 500 is retried up to three times, a few
  seconds apart. Any other failure is not retried.
- **A failing bot releases the conversation.** If a message delivery keeps failing, the conversation moves from
  pending to open and a note is added, so a person picks it up — unless your account is configured to keep it
  pending.
- **Nothing is queued while your endpoint is down,** and there is no delivery log to read here. Log on your side.
- The bot's messages obey the channel's rules, including
  [the WhatsApp 24-hour window](the-whatsapp-24-hour-window).

## Related

- [Flow builder](flow-builder)
- [Automation or flow builder?](automation-or-flow-builder)
- [Automation rules](automation-rules)

## If it does not work

**No events arrive.** Check the bot is selected on the inbox, and that the URL is reachable from outside your
network over HTTPS.

**Signatures never match.** Sign the raw body exactly as received, before any parsing or re-serialising, and
include the timestamp in the signed string.

**Conversations keep jumping to open on their own.** That is the failure path above: your endpoint is erroring.

**I cannot see my flow on the Bots page.** Flows are listed in the flow builder.
