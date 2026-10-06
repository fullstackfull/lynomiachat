---
title: Flow builder
description: Draw a conversation on a canvas that asks the customer a question, waits for the answer, and takes a different path depending on what they said.
position: 20
tags: [automation, whatsapp]
seo_description: "The Lynomia Chat flow builder: how a flow starts, the nodes it is built from, what publishing checks, and why it is WhatsApp Cloud only."
---
A flow is a conversation drawn as a diagram. Each box is one step — send this, ask that, check something, hand
over to a person — and the lines between them are the paths the conversation can take.

The thing that separates a flow from an [automation rule](automation-rules) is memory. A flow **waits**. It asks
the customer a question, stops, and when the reply arrives it picks up where it left off, knowing everything the
customer has already said.

## When to use one

When the next step depends on an answer you do not have yet. A menu of departments. An order-number lookup. A
complaint taken over WhatsApp. Anything where "it depends what they say" is the honest answer.

## When NOT to use one

- **On any channel other than WhatsApp Cloud.** This is a hard limit, not a default. See below.
- **When nothing needs to be asked.** Labelling, routing and priority on a fact you already have is an
  [automation rule](automation-rules), which is simpler and easier to read.
- **To start a conversation.** A flow cannot begin one. It only ever answers one.
- **For a store event, a schedule, a webhook or a campaign.** None of these can enter a flow.

## WhatsApp Cloud only

A flow runs on WhatsApp Cloud inboxes, and nothing else. Attach a flow to any other channel and publishing is
refused with *"Not supported on <inbox>"*. If a conversation on an unsupported channel somehow reaches a flow,
it goes straight to your team instead.

## How a flow is entered

One way only: **a customer's message on a conversation the flow owns.**

For that to happen, the flow must be the inbox's active bot, the conversation must be **pending**, and nobody
may be assigned to it. The message is then matched against the Start node's keywords and conditions, if you set
any. If it matches, a session begins. If not, the conversation goes to your team at once.

## What you need first

An **administrator** account, the flow builder enabled for your account, and a connected WhatsApp Cloud inbox
([Connect WhatsApp](connect-whatsapp)). Order lookups also need [Commerce](commerce-overview).

## The nodes

| Group | Nodes |
|---|---|
| **Messages** | Send message, Send WhatsApp template |
| **Ask and wait** | Question, Buttons, List, Delay |
| **Logic** | Condition, Audience, Commerce condition, Go to |
| **Customer** | Set contact attribute, Set conversation attribute, Add label, Remove label |
| **Commerce** | Order lookup |
| **Team** | Assign agent, Assign team, Human handoff |
| **Integration** | Webhook |
| **Flow** | Start, End |

Four of these wait for the customer: Question, Buttons, List and Delay. Everything else runs straight through.

A **Question** stores the answer — in the run, on the contact or on the conversation — for use later in message
text, and re-asks when the answer does not fit. An **Order lookup** finds the newest order of the contact's own
matched store customer, or the order number they quote; it never reads another customer's order, and never
changes one.

## Steps

1. **Settings → Flow Builder → New flow**, or **Start from a template**.
2. Build the canvas. **Save draft** as you go; nothing you save affects a customer.
3. Press **Test** to run the saved draft against a test contact. Nothing is sent or stored.
4. Press **Publish**. Problems are listed next to the nodes that caused them.
5. Attach the published flow to a WhatsApp Cloud inbox, as you would any bot.

## Templates

Eight ready-made flows: order tracking, order-issue intake, department routing, a FAQ menu, complaint intake, VIP
priority routing, an Arabic-or-English welcome, and a welcome that collects the request. Each asks for your teams,
labels and language, then creates a **draft** whose every message and branch is yours to edit.

## What publishing refuses

Publishing is the gate, and it checks the whole graph:

- exactly one **Start**, with nothing leading into it
- every required output **connected** — including every button and every list option
- every node **reachable** from Start
- **no loop that never waits** for the customer
- a **Go to** that points at a real node, not at itself or Start
- teams, agents, labels, attributes, audiences and stores that exist **in this account**, and known variables
- every attached inbox able to run **every node in the flow**

An **optional** output — a question's *invalid* or *timeout*, a menu's *other*, a lookup's *not found* — may be
left unconnected on purpose. If the conversation takes it, your team gets the conversation.

## Who can do this

Administrators only. Flows are not one of the permissions a custom role can be granted. See
[roles and permissions](roles-and-permissions).

## Limits

- **WhatsApp Cloud only.** No other channel, and no plan to accept one here.
- **Entered from a customer message only.** Not from an order change, a schedule, a webhook or a
  [campaign](whatsapp-campaigns).
- **WhatsApp's own shape applies.** At most 3 reply buttons, titles of 20 characters; one list of at most 10 rows;
  4,096 characters of text.
- **At most 300 nodes and 900 connections** per flow.
- **A handoff ends the flow.** Once a person takes the conversation it stops and does not resume. An agent's
  reply ends the session too, including one sent from the WhatsApp Business app on a coexistence number.
- **One published version at a time.** Conversations already running stay on the version they started on.
- **Disable before deleting.** Disabling stops new sessions and hands the live ones to your team.
- **Order lookups are capped** at ten per conversation per hour.
- Outside [the WhatsApp 24-hour window](the-whatsapp-24-hour-window) a flow cannot send ordinary text, so it
  hands over. An approved template still sends.

## Related

- [Automation or flow builder?](automation-or-flow-builder)
- [Automation rules](automation-rules)
- [Agent bots](agent-bots)
- [Connect WhatsApp](connect-whatsapp)

## If it does not work

**Publish is refused.** Read the list above the canvas. Each problem names its node.

**The flow never starts.** Check it is published, attached to a WhatsApp Cloud inbox, and that the conversation
arrives **pending** with nobody assigned. Then check the Start keywords — one the customer did not type sends
the conversation to your team.

**It stopped halfway.** Open **Sessions** on the flow. Each session shows where it ended and why.
