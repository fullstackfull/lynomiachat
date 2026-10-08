---
title: "\"Channel already exists for this phone number\""
description: You will know why this refusal is installation-wide rather than account-wide, and what to do when the other account is not yours.
position: 110
tags: [whatsapp, errors, connection]
seo_title: "WhatsApp number already connected — Lynomia Chat"
seo_description: "Why adding a WhatsApp number is refused as already existing, and what to do when the number is connected in another workspace."
---
You are adding a WhatsApp number and it is refused: a channel already exists for this phone number.

The refusal is exactly true and it is **wider than your workspace**. A WhatsApp number can be connected **once
across the whole installation**, not once per account. So the number may be in use somewhere you cannot see.

## Why it works that way

Incoming messages are delivered per number. If two inboxes claimed the same number, there would be no honest
answer to the question of which conversation an arriving message belongs to. The uniqueness is what keeps that
from happening.

## What to do

**If it is your own number, in your own workspace.** Look for it in **Settings → Inboxes** — including inboxes
you may have archived or forgotten. If it is there and broken, you want
[reconnect a WhatsApp number](whatsapp-reconnect-a-number), not a second inbox.

**If you cannot find it.** Then it is connected in another workspace on this installation. Only the operator can
see that, so this is a support request: give them the number and ask where it is connected. They can see it; you
cannot, and that is deliberate.

**If it was connected by a colleague who has left.** Same answer. The inbox still exists and still owns the
number; it needs to be found and either handed over or removed.

## What not to do

Do not try the number in a different format, with or without a leading `+`, or with the country code written
differently. The check is on the number, and working around it is not possible — the attempts only add noise to
whatever the operator has to read later.

## Who can do this

**Administrators** add inboxes. Finding a number connected in another workspace needs the operator of the
installation.

## Limits

- **Lynomia Chat will not tell you which account holds the number.** Naming another workspace to you would leak
  it; the refusal is deliberately plain.
- **Removing the other inbox is not something you can do** unless it is in your own account.
- **Deleting an inbox to free a number can release the number from the Meta app**, which is a second problem.
  Reconnecting is almost always what you actually want.

## Related

- [Reconnect a WhatsApp number](whatsapp-reconnect-a-number)
- [Connect a WhatsApp number](connect-whatsapp)
- [Set up an inbox](set-up-an-inbox)
