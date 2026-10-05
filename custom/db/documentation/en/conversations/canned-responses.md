---
title: Canned responses
description: Save the replies your team types every day, insert them with a keystroke, and fill in the customer's details automatically.
position: 40
tags: [conversations]
seo_description: Saved replies in Lynomia Chat, the short code that inserts them, and the variables that personalise them.
---
A canned response is a reply you have written once and saved under a short code. When an agent types `/` in the
composer, they can find it and drop it into the message in a keystroke or two.

It is for the sentences your team types every single day — opening hours, delivery timescales, how a refund
works, what documents you need. Saving them does two things: it makes answering faster, and it makes every agent
answer the same way.

## When not to use one

- **It is not a WhatsApp template.** A canned response is ordinary message text, so it is only sendable when you
  are allowed to send ordinary text. Outside the 24-hour window you can send nothing but an approved template,
  and a canned response will not go. See [the WhatsApp 24-hour window](the-whatsapp-24-hour-window) and
  [WhatsApp templates](whatsapp-templates).
- **Not for a reply that needs real thought.** A customer who can tell they received a stock paragraph to a
  specific question is a customer who feels unheard.
- **Not for a sequence of actions.** If the reply always comes with assigning, labelling and resolving, that is a
  [macro](macros), and a macro can send the message too.

## What you need first

Nothing. Canned responses work on every channel and need no setup beyond writing one.

## Steps

1. Go to **Settings → Canned responses → Add canned response**.
2. Give it a **short code** — the word you will type after `/`. Keep it short and guessable: `hours`,
   `delivery`, `refund-policy`. Each short code is unique in your account.
3. Write the **message**. Use variables where the text should change per customer.
4. Save it.

To use it: in the composer, type `/`, then start typing. Search matches both the short code and the body, with
short-code matches ranked first. Pick one and it is inserted.

## Variables

A variable is a placeholder in `{{double braces}}` that is replaced with real values. Type `{{` in the composer
to pick from the list.

| Variable | Becomes |
|---|---|
| `{{contact.name}}` | the customer's full name |
| `{{contact.first_name}}`, `{{contact.last_name}}` | the first or last word of their name |
| `{{contact.email}}`, `{{contact.phone}}` | their email address, their phone number |
| `{{contact.id}}`, `{{conversation.id}}` | the contact's and the conversation's numbers |
| `{{agent.name}}`, `{{agent.first_name}}`, `{{agent.last_name}}`, `{{agent.email}}` | the person sending the message |
| `{{inbox.name}}`, `{{inbox.id}}` | the channel the conversation came in on |

Any custom attribute you have defined on contacts or conversations is also available, as
`{{contact.custom_attribute.your_key}}` or `{{conversation.custom_attribute.your_key}}`.

Three details that matter:

**`{{agent.*}}` is whoever is sending, not whoever is assigned.** If you reply on a colleague's conversation, the
signature says your name.

**Names are tidied up.** Each word of a name has its first letter capitalised and the rest lowercased, so a
contact saved as `AHMED al-sabah` arrives as `Ahmed Al-sabah`.

**A variable with no value disappears.** If a contact has no name, `Hello {{contact.name}},` sends as `Hello ,`.
Nothing warns you. Write around it — `Hello,` on its own line is safer than a greeting that can break.

When you insert a canned response the variables are filled in immediately, with the real values, right in the
composer. What you see before pressing send is what the customer gets. Read it.

Formatting the channel cannot carry is removed at the same time, so a bulleted list saved for an email channel
arrives as plain lines on WhatsApp.

## A worked example

Your team answers "when will my order arrive?" twenty times a day.

1. Short code: `delivery`.
2. Message: `Hello {{contact.first_name}}, orders inside Kuwait arrive in 2 to 3 working days. You will get a
   message from us the moment yours ships.`
3. In a conversation, type `/delivery` and pick it. The composer shows `Hello Fatima, orders inside Kuwait…`
   before you send.

## Who can do this

Any **agent** can create, edit, delete and use canned responses. They are not personal — every one is shared by
the whole account, and anyone editing one changes it for everybody. Agree the set with your team rather than
each inventing your own.

## Limits

- **Canned responses are account-wide only.** There is no such thing as a private one for just you. (Macros do
  have a private option — see [macros](macros).)
- **They are switched off inside a private note**, along with variables. Both exist to compose a message to a
  customer.
- A canned response is plain text and attachments are not part of it. A macro's "send attachment" action can
  send a file; a canned response cannot.
- Nothing checks that your variables are spelled correctly. A typo in a variable name is simply rendered as
  nothing.

## Related

- [Work in the inbox](work-in-the-inbox)
- [Macros](macros)
- [WhatsApp templates](whatsapp-templates)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)

## If it does not work

**Typing `/` does nothing.** You are on the private note tab. Switch back to the reply tab.

**The customer received `{{contact.name}}` as literal text.** The variable name is misspelled, or it is not one
of the variables above. Type `{{` and pick from the list instead of typing the name.

**A sentence arrived with a gap in it.** The variable had no value for that contact — most often a contact with
a phone number but no name.

**I can only send a template on this conversation.** More than 24 hours have passed since the customer last
wrote. That is WhatsApp's rule, and no canned response gets around it.
