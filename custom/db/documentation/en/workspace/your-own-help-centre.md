---
title: Your own help centre
description: You will understand how to publish a public help centre for your own customers, how it is structured, and what you cannot change about it.
position: 40
tags: [workspace, help-centre]
seo_description: Publish a public help centre for your customers from Lynomia Chat, in one or more languages, on your own domain.
---
A **help centre** is a public website of articles that **you** write for **your** customers: your brand, your
language, your address. It is not the documentation you are reading now — these pages are Lynomia Chat's own product
documentation, they belong to the platform, and nothing in your account can edit them or pull them into your help
centre. The two never mix.

Most businesses publish one for the same reason: the same six questions arrive on WhatsApp every week, and a page you
can link to beats retyping the answer.

## How it is structured

Three levels, and the middle one has a rule worth knowing:

| | What it is |
|---|---|
| **Help centre** | the site. Has a name, logo, brand colour and a public address |
| **Category** | a section — Delivery, Returns, Payment. **A category belongs to one language** |
| **Article** | the page itself, written in Markdown |

An article takes the language of its category. To offer Returns in Arabic and English, create the category twice —
once per language — and write an article in each.

## When not to use it

A help centre is public. Anything meant for one customer belongs in a conversation, and anything your agents need
but customers should not read belongs in [canned responses](canned-responses).

## What you need first

An administrator account, and the questions you actually get asked — taken from your conversation history, not an
imagined list.

## Steps

1. Go to **Help Center** and create one. Give it a name and a **slug** — the word in its public address.
2. On the **Locales** page, confirm the default language and add any others. A language is either **Draft**, meaning
   not public yet, or **Published**.
3. On the **Categories** page, create your sections for that language, then write articles. A new article starts as a
   **draft**. Publish it when it is ready.
4. In **Settings → Appearance**, choose a layout — **Classic** for a welcoming home page with search and featured
   topics, **Documentation** for side-by-side navigation — and add your logo, brand colour and header text.
5. In **Settings → Domain**, optionally add a custom domain such as `help.yourdomain.com` by pointing a CNAME record
   at the address shown. It goes live once verified.
6. Back in **Settings → Inboxes**, attach the help centre to an inbox. Agents can then search it from the reply box
   and drop a link into an answer; without the attachment, the search does not appear.

## Publishing and editing

An article has three states: **draft**, **published** and **archived**. Editing one that is already published behaves
differently: your changes are **staged**, the live page keeps the old text, and you can compare the two before
publishing. That is one pending draft per article — useful for a careful correction, but **not** a revision history.
Earlier versions are not kept and cannot be restored.

You can also act on several articles at once: change status, move category, or delete.

## A worked example

A pharmacy chain in Doha publishes a help centre with Arabic as the default language and English added, creates two
categories per language — Delivery and Prescriptions — and attaches it to its WhatsApp inbox. When a customer asks
about delivery times, the agent searches "delivery" in the reply box, inserts the link, and answers in one message
instead of five.

English is left as **Draft** for two weeks while translations are checked, so visitors see only Arabic until then.

## Who can do this

Administrators, and an agent whose custom role grants **Manage knowledge base** — which covers writing articles and
categories and changing the help centre's settings, but **not** creating one, deleting one, or setting analytics
ids. See [Roles and permissions](roles-and-permissions).

## Limits

- **Slugs are unique across the whole installation**, not just your account, so a common word may be taken. These
  are reserved and refused: `docs`, `documentation`, `help`, `helpcenter`, `support`, `status`, `api`, `changelog`,
  `releases`, `release-notes`, and names beginning with `lynomia`. Article slugs are globally unique too.
- **There is no revision history.** One pending draft per published article, and no way back to an earlier version.
- The default language cannot be set to Draft.
- The home page can feature at most **3 categories and 6 articles** per language.
- Analytics ids — Google Tag Manager, GA4, Hotjar, Plausible, Amplitude, Clarity and the Meta pixel — are
  **administrator-only**, because they inject tracking into every public page.
- Folders appear in the underlying data but cannot be created or used. Categories are the only grouping.
- Deleting a help centre is permanent and takes its articles with it.
- Article bodies are Markdown. There is no visual page builder and no custom template.

## Related

- [Set up an inbox](set-up-an-inbox)
- [Roles and permissions](roles-and-permissions)
- [Canned responses](canned-responses)

## If it does not work

**The slug is refused.** It is reserved, or another account on the installation already has it. Add a word —
`yourbrand-help` rather than `help`.

**An article is published but not on the public site.** Check its language. If that locale is still marked Draft,
nothing in it is public.

**My edit is not showing on the live page.** On a published article, edits are staged. Publish the pending draft.

**The reply box has no article search.** The inbox has no help centre attached.

**The custom domain is not working.** It stays pending until the CNAME record is verified.
