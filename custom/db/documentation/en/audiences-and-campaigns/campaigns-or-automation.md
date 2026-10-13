---
title: Campaigns or automation?
description: One goes out to a group you chose. The other reacts to something that happened. This article tells you which one your idea is, before you build it in the wrong place.
position: 50
tags: [campaigns, automation, audiences]
seo_description: "When to use a campaign and when to use an automation rule or flow in Lynomia Chat, and why a campaign cannot react to an event."
---
These two feel interchangeable and are not. The difference is **what starts them**.

- A **campaign** starts because *you decided to send it*. You choose the recipients and, for a WhatsApp or SMS
  campaign, the moment.
- An **automation rule** or a **flow** starts because *something happened*. A conversation was created, a
  message arrived, an order was paid. You never choose who; the event does.

Everything else — who it reaches, what it costs you in WhatsApp terms, what you can see afterwards — follows
from that one difference.

## The one-line test

Ask: **can I write down the list of people this should reach, today, before anything happens?**

- **Yes** → a campaign.
- **No, it depends on what they do** → automation.

If the answer is "both", you want two things, not one.

## Side by side

| | **Campaign** | **Automation rule / flow** |
|---|---|---|
| Starts because | you sent it | an event occurred |
| Who it reaches | the labels and [shared audiences](shared-audiences) you picked | whoever triggered the event |
| How many people at once | many | one conversation |
| Runs again | no — a WhatsApp or SMS campaign sends once | yes, every time the event happens |
| Timing | you choose it | the event chooses it |
| Needs an existing conversation | no | yes, for most triggers |
| On WhatsApp outside the 24-hour window | needs an approved [template](whatsapp-templates) | a message action simply will not deliver |
| Lives under | **Campaigns** | **Settings → Automation** |

## Which campaign type you are actually talking about

"Campaign" covers three things in Lynomia Chat, and only two of them behave the way the table above describes:

| | Starts because | Recipients |
|---|---|---|
| [**WhatsApp campaigns**](whatsapp-campaigns) | you send or schedule it | labels and shared audiences you picked |
| **SMS campaigns** | you send or schedule it | labels and shared audiences you picked |
| [**Live chat campaigns**](live-chat-campaigns) | a visitor lingered on a page | nobody chosen — whoever is on the page |

So a live chat campaign is the exception: it is reactive, like automation, but it reacts to **browsing**, which
no automation trigger can see. If your idea depends on what someone is looking at on your website right now,
that is the one tool for it, whatever it is filed under.

## Worked cases

**"Tell everyone who bought in Ramadan about the new range."** You can write the list down: a
[shared audience](shared-audiences) or a label. → A [WhatsApp campaign](whatsapp-campaigns), with an approved
template.

**"When someone's order ships, tell them."** You cannot write the list down; it depends on the orders. → An
[automation rule](automation-rules) on the order-shipped trigger.

**"Ask for feedback three days after a conversation is resolved."** Event-driven. → An
[automation rule](automation-rules) on conversation resolved. A rule can be set to run after a wait, from ten
minutes to thirty days, where delayed execution is enabled for your account.

**"Offer help to people stuck on the checkout page."** Depends on browsing. → A
[live chat campaign](live-chat-campaigns).

**"Chase the customers who did not reply to the Ramadan message."** This is two steps, and people try to make
it one. The campaign cannot know who replied. Label the non-repliers — by filtering conversations, or by a rule
that labels anyone who *does* reply and then excluding that label — and send a second campaign to what is
left.

**"Greet every new WhatsApp contact."** Event-driven, one conversation at a time. → An
[automation rule](automation-rules) on conversation created, or a [flow](flow-builder) if you want to ask
something and wait for the answer.

## Three things a campaign cannot do

Each of these is a real request people make, and each is automation's job:

- **React to anything.** A campaign has no triggers. There is no "send when".
- **Wait for a reply and branch on it.** That is a [flow](flow-builder).
- **Run on a schedule, repeatedly.** A WhatsApp or SMS campaign can be scheduled for *a* time, once. It is not
  a recurring job.

## Three things automation cannot do

- **Reach a group.** An automation rule acts on the one conversation that triggered it. Twenty people do not
  get a message because twenty rules did not fire.
- **Reach someone with no conversation.** Most triggers are conversation events, and a Commerce trigger acts on
  the contact's most recent conversation — if the contact has none, nothing runs. A campaign has no such
  requirement.
- **Send a WhatsApp template to a cold contact.** A campaign is built around that; a rule's message action is
  an ordinary message and is bound by
  [the 24-hour window](the-whatsapp-24-hour-window).

## Where WhatsApp's rules land differently

This is the costliest place to get the choice wrong.

A [WhatsApp campaign](whatsapp-campaigns) sends an **approved template**, which is the only thing WhatsApp
permits to a contact who has not written to you recently. A campaign is therefore the right shape for reaching
people who are not currently in conversation with you.

An automation rule's **send a message** action sends an ordinary message. Inside the 24-hour window that is
fine. Outside it, WhatsApp refuses it — and the rule does not warn you when you build it. If your rule has to
reach someone who may have gone quiet, the honest designs are a private note plus a person, or a campaign.

## Who can do this

Administrators, for both. Neither campaigns nor automation appears in the custom role permission list, so
neither can be delegated — see [roles and permissions](roles-and-permissions).

## Related

- [WhatsApp campaigns](whatsapp-campaigns) · [Live chat campaigns](live-chat-campaigns)
- [Shared audiences](shared-audiences) · [Labels or shared audiences?](labels-or-shared-audiences)
- [Automation rules](automation-rules) · [Flow builder](flow-builder) · [Automation or flow builder?](automation-or-flow-builder)
- [WhatsApp templates](whatsapp-templates) · [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)

## If it does not work

**My campaign did not reach the people I expected.** A campaign resolves its recipients when it is sent, from
the labels and shared audiences you picked. Check the audience, not the campaign — see
[shared audiences](shared-audiences).

**My rule's message never arrived on WhatsApp.** The conversation was outside the 24-hour window. Nothing in
the rule form says so; the message is refused at the channel.

**I want one thing that does both.** You want two things. A rule that labels people, and a campaign that sends
to that label, is the normal shape of this.
