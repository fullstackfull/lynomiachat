---
title: Set up your account
description: You will have named your business, chosen the language your team works in, and know where the timezone that actually matters is set.
position: 20
tags: [getting-started]
seo_description: Name your business, set the account language, and learn which timezone Lynomia Chat uses for business hours and for reports.
---
Your account is the workspace your whole business shares. Contacts, channels, labels, templates and reports all
belong to it, and everyone you add works inside it.

Two things live in **Account Settings → General**, and an administrator normally sets them once: your **business
name** and your **account language**. Everything else you set up — channels, people, labels, automation — lives on
its own page and changes often.

## What you need first

An administrator account. The page is not reachable by an agent, so if you cannot open Account Settings, ask whoever
set the account up.

## Your business name

The name is required. It is the name your colleagues see, and it is the name in the invitation email that goes to
every person you add: *"You are invited to join &lt;your business&gt;"*. You can change it whenever you like, and
nothing else breaks when you do.

## Your account language

Also required. The account language decides three separate things:

- the dashboard language for anyone who has not chosen their own
- the language of the notification emails Lynomia Chat sends
- the language the website live-chat widget loads in

## Which language is which

Three different languages are at work, and keeping them apart saves a lot of confusion.

| Language | Where it is set | What it changes | Who it affects |
|---|---|---|---|
| Account language | Account Settings → General | default dashboard, system emails, live-chat widget | everyone in the business |
| Your own language | Profile Settings | your dashboard | only you |
| Template language | on each WhatsApp template | what the customer receives | that one message |

Your own choice wins over the account default **for your dashboard**. It does not change the emails Lynomia Chat
sends — those follow the account language, whoever receives them. If you set your personal language to
**Use account default**, you follow whatever the account is set to.

## Where the timezone really is

There is no account-wide timezone in Lynomia Chat, and this is worth knowing before you plan around one. Three
different mechanisms use time, and they read it from three different places:

| What | Timezone it uses |
|---|---|
| Business hours and out-of-office replies | the timezone on each channel, set per channel |
| Reports | the timezone of the browser you are looking at them in |
| The timezone asked during first-run setup | recorded as a business detail; it does not drive either of the above |

A new channel is created with its timezone set to **UTC**. For the Gulf that is three hours behind local time, so
"we are open 9 to 6" will behave wrongly until you set it. Open the channel, go to its business hours, and choose
your own zone — for example `Asia/Kuwait` or `Asia/Riyadh`.

## A worked example

A furniture retailer in Kuwait sets the business name to *Al Manar Furnishings* and the account language to Arabic,
because most of the team reads Arabic. One agent handles English-speaking customers and sets her own language to
English in her profile; her dashboard turns English, and everyone else's stays Arabic.

The retailer then opens its WhatsApp channel, turns on business hours, and sets the channel timezone to
`Asia/Kuwait`. Only now does "closed after 6pm" mean 6pm in Kuwait.

## Who can do this

Administrators only, for both the name and the account language. Any person can set their own dashboard language in
their own profile without help.

## Limits

- There is no single account timezone. Business hours are per channel, and reports follow your browser.
- A custom reply domain and a support email address appear on this page only if inbound email is enabled for your
  installation. If you do not see those fields, that is why.
- Changing the account language does not retranslate anything that has already been written: canned responses,
  labels, templates and past messages keep the words you typed.

## Related

- [Invite your team](invite-your-team)
- [Connect your first channel](connect-your-first-channel)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**The form refuses to save.** Both the business name and the language are required. An empty name is the usual
cause.

**You changed the account language and your own dashboard did not change.** You have a personal language set in your
profile, and it takes priority. Set it to *Use account default*.

**Business hours fire at the wrong time.** Check the timezone on that specific channel, not the account.
