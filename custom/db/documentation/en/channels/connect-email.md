---
title: Connect an email inbox
description: Turn a support mailbox into conversations, by forwarding or by connecting the mailbox directly.
position: 20
tags: [channels, email]
seo_description: Connecting an email channel in Lynomia Chat — forwarding, Google, Microsoft, and IMAP/SMTP — and what each route can and cannot do.
---
An email channel turns `support@yourcompany.com` into conversations. A customer writes to the address they
already have; the mail arrives in Conversations with the rest of your channels, and your agent's reply goes
back out as an email.

Email is the one channel with no time window and no template rules. It is also the one with the most ways
to connect it, and picking the wrong one is the usual reason an inbox half works.

## The three ways in

| Route | How mail arrives | How replies go out | Pick it when |
|---|---|---|---|
| **Forwarding** | your mail provider forwards to an address Lynomia Chat generates | from the installation's own mail server | you want it working in five minutes and you do not mind replies coming from the installation's sending domain |
| **Google / Microsoft** | you sign in once and authorise the mailbox | through the same account | the mailbox is on Google Workspace or Microsoft 365 |
| **IMAP and SMTP** | Lynomia Chat polls the mailbox | through your own SMTP server | any other provider, or a mailbox your IT team will not hand to an OAuth app |

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **Email**.
2. Give the channel a name and the email address your customers write to.
3. Finish. The last screen shows the **forwarding address** — a long, unique address on the installation's
   inbound domain. Anything forwarded to it becomes a conversation on this channel.
4. Either set up forwarding in your mail provider to that address, or open the channel's settings and
   configure **IMAP** (to receive) and **SMTP** (to send) instead.

IMAP and SMTP are two switches, not one, and they are independent. IMAP on with SMTP off receives mail and
sends replies through the installation's mail server; SMTP on with IMAP off sends from your server and
receives nothing. For a mailbox you own end to end, turn both on.

## What you need for IMAP and SMTP

Your provider publishes all of it. For IMAP: the server address, the port, the login, the password, and
whether SSL is on. For SMTP: the same plus the encryption (SSL/TLS or STARTTLS) and, on some providers, a
domain.

A mailbox protected by two-factor authentication usually needs an **app password** rather than the account
password. That is your provider's rule, not ours, and a wrong password shows up as an inbox that simply
never receives anything.

## Who the conversation belongs to

The sender's address becomes a contact. If that address already belongs to a contact — because they have
written before, or because someone imported them — the conversation joins that contact rather than making a
second one. This is why an email channel fills out your contact list faster than any other.

## Limits

- **Forwarding loses your sending domain.** Replies leave from the installation's mail server, so the
  customer sees that domain in the technical headers. Use Google, Microsoft or SMTP if that matters to you.
- **A forwarding address is a secret.** Anyone who knows it can post a conversation into your channel.
  Treat it like an API key, not like a mailbox.
- **IMAP polls.** Mail arrives within a minute or two, not instantly.
- **Attachments obey the installation's size limit**, which an administrator sets for the whole
  installation, not per channel.

## Who can do this

Administrators.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Set up an inbox](set-up-an-inbox)
- [Website live chat](website-live-chat)

## If it does not work

**Nothing arrives.** If you forward, send a test to the forwarding address itself rather than to your public
address — if that arrives, forwarding is the problem and your mail provider is where to fix it. If you use
IMAP, check the channel's settings for an authentication error, and confirm the mailbox allows IMAP at all:
some providers switch it off by default.

**Mail arrives but replies do not go out.** SMTP is off, or its credentials are wrong. Replies then queue
and fail silently from the agent's point of view, so check the channel's SMTP settings first.

**Replies land in the customer's spam folder.** That is the sending domain's reputation, not the product.
Connecting through your own SMTP server, with your own SPF and DKIM records, is the fix.

**Every reply starts a new conversation.** The customer's mail client is stripping the reference headers
Lynomia Chat puts on outgoing mail. Nothing in the dashboard can fix that; the usual cause is a forwarding
rule in the middle that rewrites the message.
