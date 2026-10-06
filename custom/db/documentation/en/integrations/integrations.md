---
title: Integrations
description: You will know which integrations exist in Lynomia Chat, what each one actually does, and why your list is probably shorter than this one.
position: 10
tags: [integrations]
seo_description: "The real integration list in Lynomia Chat: webhooks, dashboard apps, Slack, Dialogflow, Google Translate, OpenAI, Linear, Notion, Shopify, LeadSquared."
---
**Settings → Integrations** is a catalogue of apps you can connect your account to. Eleven exist in the product.
Your page will usually show fewer, because several are switched on by whoever runs your installation rather than
by you.

Two things that feel like integrations are not on this page. Connecting a store is its own section — see
[what connecting a store gives you](commerce-overview). Bots live under Automation — see
[agent bots](agent-bots).

## What exists

| App | What it does | Connected per |
|---|---|---|
| **Webhooks** | posts account events to a URL you own | account, as many as you want |
| **Dashboard Apps** | shows a web page of yours as a tab next to the conversation | account, as many as you want |
| **Slack** | mirrors conversations into one Slack channel | account, one |
| **Dialogflow** | lets a Google Dialogflow agent answer in one inbox | inbox, one per inbox |
| **Google Translate** | translates one message on demand, and records the language the customer wrote in | account, one |
| **OpenAI** | holds your own OpenAI key for the AI writing features, and turns label suggestions on | account, one |
| **Cloudflare RealtimeKit** | starts a video or voice call from inside a conversation | account, one |
| **Linear** | creates a Linear issue from a conversation, or links an existing one | account, one |
| **Notion** | gives the AI assistant read access to your Notion content | account, one |
| **Shopify** | shows a Shopify customer's orders beside the conversation | account, one |
| **LeadSquared** | creates leads and logs conversation activity in LeadSquared | account, one |

## Which of them you will see

The list is filtered before it reaches you, so a missing app is not a fault.

| App | Shown when |
|---|---|
| Webhooks, Dashboard Apps, Dialogflow, Google Translate, OpenAI, Cloudflare RealtimeKit | always |
| Slack | your installation has Slack credentials configured |
| Linear, Notion | your installation has credentials **and** the feature is on for your account |
| Shopify | the same, plus the installation-wide Shopify switch |
| LeadSquared | the CRM feature is on for your account |

Nothing in your account turns these on. If an app you need is absent, that is a conversation with whoever runs
your installation.

## The four worth a sentence each

**Slack has two modes.** *Two-way* posts conversations into the channel and sends replies typed in the Slack
thread back to the customer. *Alert* posts them and sends nothing back — the thread is a notification, not a
reply box. Pick alert if people in that channel are not meant to answer customers.

**A dashboard app is an iframe, not a plugin.** You give it an HTTPS URL. It appears as a tab beside the
conversation, and the page is sent the current conversation, the contact, your account's custom attribute
definitions, the signed-in agent and the current theme. What it does with them is your code's business.

**Google Translate does two separate things.** It detects the language of the customer's first incoming message
and stores that on the conversation. Separately, it gives every message a **Translate** action, which translates
that one message into a language you pick. It does not translate the conversation as you read it, and it does not
translate what you send.

**There are two Shopifys.** This page's Shopify is the older orders panel. Commerce has its own Shopify, with its
own setup — see [Connect Shopify](connect-shopify). One shop can be connected through one of them, not both: each
path refuses a shop the other already holds. Choose Commerce unless you are already on the older one.

## What you need first

An administrator account. Every page under Integrations is administrator-only.

## A worked example

A Kuwait retailer wants its operations team notified in Slack without them replying to customers by accident. An
administrator connects Slack, picks the `#support-watch` channel, and sets the mode to **Alert**. Conversations
now appear in that channel as they arrive. A manager replying in the Slack thread changes nothing — the customer
never sees it, and the team answers in [the inbox](work-in-the-inbox) as before.

## Who can do this

Administrators only. The custom role permission list has **no** entry for integrations, so this cannot be
delegated — see [roles and permissions](roles-and-permissions).

## Limits

- **One connection per app**, except Webhooks and Dashboard Apps (as many as you like) and Dialogflow (one per
  inbox).
- **There is no generic connector for other tools.** The way to reach anything not on this list is
  [webhooks](webhooks), or the webhook action inside an automation rule or a flow.
- **The OpenAI entry is a key, not a feature.** It supplies the credential the AI writing features use and
  switches label suggestions on. It does not add anything by itself.
- **Language detection runs once per conversation**, on the first incoming message, and is skipped if the
  conversation already has a language recorded.
- **Dialogflow is per inbox.** A bot connected to one inbox does nothing in another, an inbox already connected
  is not offered again, and email inboxes cannot be connected at all.
- WooCommerce, Salla and Zid are not on this page at all. They are Commerce platforms — see
  [what each platform supports](commerce-provider-support).

## Related

- [Webhooks](webhooks)
- [What connecting a store gives you](commerce-overview) · [Connect Shopify](connect-shopify)
- [Agent bots](agent-bots) · [Automation rules](automation-rules)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**The app I want is not listed.** It is not switched on for your installation. The table above says what each one
needs.

**Integrations is not in Settings at all.** You are signed in as an agent, or with a custom role. The page is
administrator-only.

**Shopify refuses my shop, saying it is already connected through Commerce.** It is. Disconnect it in
Settings → Commerce first, or keep using it there.
