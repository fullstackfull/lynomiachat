---
title: Lynomia Chat, and where this changelog starts
description: The first published release note, what the product includes today, and why there is no history before this entry.
position: 10
release_date: '2026-10-05'
tags: [whatsapp, commerce, automation, audiences, documentation]
seo_description: The first Lynomia Chat release note - what the product includes today and why the changelog starts here.
---
This is the first published release note for Lynomia Chat.

## Why this changelog starts here

Everything in the product before this entry was built without versioned, dated releases. Rather than reconstruct a
history from development activity and present it as a release record, this changelog **starts from the first release
it can support** and goes forward from here. Nothing earlier has been back-dated or given a version it never had.

Future entries will carry a version and a release date.

## What Lynomia Chat includes today

### Messaging

A shared inbox for the whole team, with conversations from WhatsApp, a website widget, email and the other
connected channels in one list. Assignment to an agent or a team, priorities, private notes, labels, canned
responses and macros.

### WhatsApp

A WhatsApp Business connection, support for running the WhatsApp Business app and Lynomia Chat on the same number,
and a template manager that writes, submits, edits and deletes WhatsApp templates from inside the product rather
than from Meta's own tools. Template status comes back from WhatsApp automatically.

### Customers

Contacts with custom attributes, CSV import and a paste-a-list flow, bulk label actions, and **shared audiences** —
a saved set of conditions that is re-answered every time it is used, rather than a list that goes stale.

### Campaigns

One approved WhatsApp template, sent at a time you choose, to everyone in a set of labels and shared audiences.

### Automation

Rules that react to an event with conditions and actions, and a flow builder for conversations that wait for the
customer's reply. Both ship with starting points rather than an empty canvas.

### Commerce

Connect a WooCommerce, Salla, Zid or Shopify store and see a customer's orders beside the conversation. What each
provider supports differs, and the [provider support matrix](/docs/commerce-provider-support) says exactly how.

### Documentation

The documentation you are reading, in English and Arabic, with a "Learn more" link on the screens where it helps.

## Known limits worth knowing

- WhatsApp decides what you may send and when. [The 24-hour window](/docs/the-whatsapp-24-hour-window) explains it.
- A template is only sendable once **WhatsApp** has approved it. A draft in Lynomia Chat is not an approved template.
- Commerce providers differ in what they allow. Check the support matrix before promising a customer an action.
- The flow builder runs on WhatsApp Cloud numbers only.
