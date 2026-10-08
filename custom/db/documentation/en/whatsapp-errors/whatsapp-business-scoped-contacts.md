---
title: Business-scoped WhatsApp contacts, and what cannot be sent to them
description: You will know why some WhatsApp customers have no phone number, what that prevents, and the two refusals specific to them.
position: 130
tags: [whatsapp, errors, contacts]
seo_title: "Business-scoped WhatsApp contacts in Lynomia Chat"
seo_description: "WhatsApp contacts with no phone number: what a business-scoped identifier is, and why authentication templates cannot be sent to them."
---
Most WhatsApp customers arrive with a phone number. Some arrive with a **business-scoped identifier** instead — an
id that identifies them to your business only, with no phone number attached. WhatsApp does this when the customer
reaches you through certain entry points, and it is normal rather than broken.

You can hold the whole conversation with such a contact. What you cannot do is anything that needs the number
itself.

## The two refusals you will meet

**Authentication templates require a phone number.** A one-time-passcode template is refused for a
business-scoped contact, because the passcode's whole purpose is to prove control of a number that is not there.
There is no workaround, and this is the right outcome: delivering a passcode to an identifier you cannot verify
would be worse than refusing.

**The template's category could not be verified.** Sending to a business-scoped contact requires knowing which
category the template is, and the category is read from the inbox's synced template list. If the template is not
in that list under that name and language, Lynomia Chat refuses rather than guess — a wrong guess here could send
an authentication template to a contact that must not receive one.

Clearing the second one is straightforward: open **Settings → Templates**, press **Sync templates**, and confirm
the template appears with the name and language you are sending. See
[WhatsApp templates](whatsapp-templates).

## Getting a phone number

You can ask for one — WhatsApp puts the request to the customer and they decide. The conditions are in
[a contact information request was refused](whatsapp-contact-info-requests).

Once a number is shared, the contact becomes an ordinary contact and these two refusals stop applying.

## Who can do this

Any agent can send and will see the refusals. Syncing templates and getting a template approved are
administrator work.

## Limits

- **You cannot convert a business-scoped contact yourself.** Only the customer sharing their number does that.
- **Authentication templates stay refused** for as long as there is no number. This is deliberate.
- **Merging such a contact with one that has a phone number** does not retrospectively make earlier messages
  sendable.
- **The identifier is scoped to your business.** It is not a WhatsApp account id you can use anywhere else.

## Related

- [A contact information request was refused](whatsapp-contact-info-requests)
- [WhatsApp templates](whatsapp-templates)
- [The template lifecycle](whatsapp-template-lifecycle)
- [Contacts](contacts)
