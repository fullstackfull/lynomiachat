---
title: Custom attributes
description: How to add your own fields to contacts and conversations, where the values are used, and what the product will not do with them.
position: 20
tags: [contacts, workspace]
seo_description: "Custom attributes in Lynomia Chat: defining fields on contacts and conversations, filtering on them, and using them as message variables."
---
A custom attribute is a field you invent. Lynomia Chat ships with the fields everybody needs — name, phone
number, city, status, priority — and a custom attribute is how you add the one your business needs and nobody
else does: a policy number, a delivery zone, a subscription tier, the date a warranty ends.

An attribute has two halves, and keeping them apart makes the rest obvious. The **definition** is created once,
in Settings, and belongs to the account. The **value** is set per contact or per conversation. Creating a
definition stores no data; it creates a field that can now hold data.

## Contact attributes and conversation attributes

You choose which one an attribute is when you create it, and the choice cannot be changed afterwards.

| | Describes | Where the value is set |
|---|---|---|
| **Contact attribute** | the person, for as long as they are a customer | the **Attributes** tab on the contact |
| **Conversation attribute** | this one exchange | the panel beside the conversation |

A delivery zone is a property of the person. An order number is a property of this conversation. Getting it wrong
is not fatal, but it is tedious to undo, because the type and the model are fixed once the attribute exists.

## When to use one

Use a custom attribute when the answer is a **value you will need to read back, filter on, or put in a message**,
and no other field already holds it.

- **The answer is not yes or no.** A delivery zone, a contract tier, a preferred branch, a reference number from
  another system. A label can only say *this is true of them*; an attribute says *this is what it is*.
- **You want to filter or segment on the value.** Attributes are available as conditions in a contact filter and
  therefore in a [shared audience](shared-audiences), and as conditions in an [automation rule](automation-rules).
- **You want it in a WhatsApp template.** A template's variables can be filled from a contact attribute, which is
  how one approved template serves every customer without a separate draft each.
- **Agents need it in front of them.** The value sits in the panel beside the conversation, so nobody has to open
  another tool to find the customer's account number.

If you cannot name the question the attribute answers, you do not need the attribute yet. An unused definition is
one more empty field every agent sees on every contact.

## When not to use one

- **When a [label](labels) would do.** A label is a yes/no decision you can filter and send campaigns to, and it
  costs nothing to define. A checkbox attribute that is only ever true is a label written the long way.
- **When Lynomia Chat already knows.** Order history, spend and store membership arrive from a connected shop and
  stay current. An attribute you type by hand is correct on the day you type it and never again.
- **For anything secret.** Attribute values are visible to every agent who can open the contact, and they travel
  in exports.

## What you need first

Only an administrator can create, rename or delete definitions. Any agent can then fill them in.

## Creating one

Go to **Settings → Custom attributes → Add custom attribute**.

| Field | Notes |
|---|---|
| Display name | What agents see. Required. |
| Key | The machine name, used in imports, filters and variables. No spaces. Letters of any alphabet, numbers, `_`, `.` and `-`. Unique within its model. |
| Description | Required. It is the hint shown when the attribute is offered as a message variable, so write it for the next person. |
| Applies to | Contact or Conversation. Fixed afterwards. |
| Type | Text, Number, Link, Date, List or Checkbox. Fixed afterwards. |
| List values | For the List type, the options an agent may pick from. |
| Regex pattern and cue | Text type only. A pattern the value must match, and the hint shown when it does not. |

A key may not be one of the built-in field names — `phone_number`, `status`, `priority` and the rest are taken,
and Lynomia Chat refuses rather than shadowing them.

## What you can do with the values

This is the part worth planning before you define anything, because it is what makes an attribute more than a
note.

- **Filter.** Contacts and conversations can both be filtered on their own custom attributes, with operators
  suited to the type — greater than for a number, before a date, is present for anything.
- **Save the filter.** A contact filter saved as a [shared audience](shared-audiences) becomes a reusable
  recipient source for a [campaign](whatsapp-campaigns), re-counted every time it is opened.
- **Condition an [automation rule](automation-rules).** Rules can read both conversation and contact custom
  attributes as conditions.
- **Insert into a message.** Type `{{` in the reply editor and the attribute appears in the list.
  `{{contact.custom_attribute.policy_number}}` and `{{conversation.custom_attribute.order_number}}` are the
  forms.

## A worked example

You deliver, and the driver needs to know the zone.

1. **Settings → Custom attributes → Add custom attribute.** Display name "Delivery zone", key
   `delivery_zone`, applies to Contact, type List, values Salmiya / Hawalli / Jahra / Farwaniya.
2. On a contact, open **Attributes** and pick the zone. Agents can do this while the conversation is open.
3. In the contacts list, filter on **Delivery zone is Jahra**, and save it as a shared audience called
   "Jahra customers".
4. When a road closes, send a campaign to that audience.

Step 3 is the payoff. The attribute was worth defining because it made step 4 a question you can ask rather than
a list you have to keep.

## Limits

- **Type and model are fixed once created.** The key is read-only after creation too. To change any of them,
  create a new attribute and move the values.
- **The regex pattern is checked in the form, not on the data.** A value written by an import or through the API
  is stored as given, whether or not it matches.
- **A value can exist without a definition.** An import stores every column it does not recognise as a custom
  attribute value on the contact. It will not appear in the Attributes panel unless an attribute with exactly
  that key exists.
- **Deleting a definition does not erase the values.** They stop being displayed. Re-creating an attribute with
  the same key brings them back into view.
- **No automation action writes an attribute.** Rules can read attributes; nothing in Lynomia Chat sets one for
  you. Every value is typed by a person, imported, or written through the API.
- There is no bulk editor for attribute values. Set them on the contact, or bring them in with an
  [import](import-contacts).

## Related

- [Contacts](contacts)
- [Import contacts](import-contacts)
- [Labels](labels)
- [Shared audiences](shared-audiences)
- [Automation rules](automation-rules)

## If it does not work

**The attribute is not in the contact's Attributes tab.** It was created as a conversation attribute. Check
**Applies to** in Settings.

**I cannot save the key.** It contains a space, or it is the name of a built-in field.

**The values I imported are nowhere.** The column header and the attribute key must match exactly, including
case. Fix the key or re-import with the right header.

**Settings has no Custom attributes page.** You are signed in as an agent. Definitions are an administrator
job.
