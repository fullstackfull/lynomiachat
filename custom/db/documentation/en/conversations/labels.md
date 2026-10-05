---
title: Labels
description: What a label is, how to keep a label set that stays useful, and the one case where a label is the wrong tool.
position: 30
tags: [conversations, contacts]
seo_description: Labels in Lynomia Chat: tagging conversations and contacts, naming rules, and when to use a shared audience instead.
---
A label is a decision somebody made, written down. You put it on, and it stays there until somebody takes it
off. Nothing in Lynomia Chat ever adds or removes one on its own.

That single property — a label is **stored**, not calculated — decides everything else about when to use one.

## Conversation labels and contact labels are different things

This is the most common misunderstanding, and it costs real money when it goes wrong.

| | What it describes | Where you set it | What reads it |
|---|---|---|---|
| **Conversation label** | this one exchange | the panel beside the conversation | the label views in the sidebar, conversation folders, reports |
| **Contact label** | this person, across all their conversations | the panel on their contact record, or the contacts list in bulk | the contact's label page, campaign recipients |

They draw from the same catalogue of labels, but they are stored separately. Tagging a conversation `vip` does
**not** make that person a `vip` contact. If you build a campaign to the `vip` label and the tag only ever went
on conversations, the campaign reaches nobody.

The same trap sits inside automation. An [automation rule's](automation-rules) "add label" action labels the
**conversation**, always. There is no action anywhere in Lynomia Chat that labels a contact.

## When to use one

Use a label when the answer is a judgement your team made and would otherwise be lost:

> `vip` · `wholesale` · `needs-follow-up` · `complaint-escalated` · `event-attendee` · `do-not-call`
> · `refund-issued` · `arabic-speaker`

A good test: could a new colleague work out this label from the data alone? If not, a label is exactly right,
because nothing else in the product can record it.

## When not to use one

**Do not use a label for anything that can change without anybody touching the contact.**

"Recent buyers" as a label is correct on the day you apply it and wrong a month later. Nothing will warn you. The
campaign you send to it goes to exactly the people who should no longer be in it.

Membership that works itself out belongs in a [shared audience](shared-audiences): a saved question about your
contacts that is answered again every time it is opened, counted or sent to.

| The thing you want | Use |
|---|---|
| customers who bought in the last 30 days | a shared audience |
| customers with an open order | a shared audience |
| customers who have spent over a threshold | a shared audience |
| customers of one store | a shared audience |
| customers we decided are VIP | a label |
| customers who asked not to be contacted | a label |

[Labels or shared audiences?](labels-or-shared-audiences) goes through the decision in more depth. Both are
first-class recipient sources for a campaign, so choosing correctly costs you nothing at the point of sending.

## Keeping a label set that stays useful

- **Fewer, sharper labels.** A set of twelve that everyone uses beats a set of eighty where three people each
  invented their own spelling.
- **Write the description.** The description field exists so the next person applies it the way you meant.
- **Only put the ones you navigate by on the sidebar.** Each sidebar label is a view with its own unread count;
  twenty of them is not a sidebar.
- **Rename rather than recreate.** Renaming a label updates every conversation and contact already carrying it.
  Creating `vip-customer` beside `vip` splits your data in half, permanently.

## Naming rules

Labels are stored in lower case, whatever you type. A label must be at least two characters, must start with a
letter or a number, and may then contain letters, numbers, hyphens and underscores. **Spaces are not allowed** —
write `needs-follow-up`, not `needs follow up`. Arabic letters are fine. Each label is unique in your account.

## Steps

To create one: **Settings → Labels → Add label**. Give it a name, a description, a colour, and decide whether it
belongs on the sidebar.

To apply one to a conversation: open the conversation and pick it in the panel beside it. To apply one to a
contact: open the contact, or tick contacts in the contacts list and use **Assign labels** in the bar that
appears.

## A worked example

You want to be able to message wholesale buyers about stock before anyone else.

1. Create a label `wholesale` with a description that says who qualifies.
2. In the contacts list, filter to the accounts that are wholesale, tick them, and **Assign labels → wholesale**.
3. In the sidebar, under **Contacts → Tagged with**, open `wholesale`. **Use in a new WhatsApp campaign** starts
   a campaign with those contacts as the recipients.

Note step 2 put the label on the **contacts**, which is what the campaign reads.

## Who can do this

Creating, renaming, recolouring and deleting labels is an **administrator** job. Any **agent** can apply and
remove existing labels on conversations and contacts they can see. That split is deliberate: it keeps the
catalogue coherent while letting the people doing the work use it.

## Limits

- Nothing maintains labels for you. There is no rule, job or schedule anywhere that adds or removes a contact
  label.
- There is no automation trigger for a contact being created or changed, and no automation condition on a contact
  label.
- **Labelling conversations in bulk covers only the page in front of you.** Labelling contacts in bulk can cover
  every contact matching the view you are looking at, up to 10,000 — above that Lynomia Chat refuses rather than
  silently doing part of the job.
- Deleting a label removes it from everything carrying it. There is no undo.

## Related

- [Labels or shared audiences?](labels-or-shared-audiences)
- [Shared audiences](shared-audiences)
- [Work in the inbox](work-in-the-inbox)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Contacts](contacts)

## If it does not work

**My campaign to a label found no recipients.** The label is on conversations, not on contacts. Open it under
**Contacts → Tagged with**: if that page is empty, that is the answer. Apply the label to the contacts from the
contacts list.

**I cannot save the label name.** It has a space in it, is one character long, or starts with a hyphen or
underscore.

**An agent cannot find the label.** It has not been created in Settings yet. Agents can only apply labels that
already exist.
