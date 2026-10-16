---
title: Website live chat
description: Put a chat widget on your own website, see what your visitors see, and answer them from the inbox you already use.
position: 10
tags: [channels, website, live-chat]
seo_description: Connecting the website channel in Lynomia Chat, installing the widget script, configuring what visitors see, and answering from the dashboard.
---
The website channel puts a chat bubble in the corner of your own site. A visitor clicks it, types, and the
message lands in Conversations next to your WhatsApp and your email — same inbox, same agents, same labels,
same reports.

It is the fastest channel to connect, because nothing outside Lynomia Chat has to approve it. There is no
business verification, no template review and no provider account: you create the channel, paste one script
tag into your site, and it is live.

This article shows both ends of it — the visitor's and yours.

## What you need

- An administrator account.
- The ability to add a `<script>` tag to your website. On a CMS that is usually a "custom code", "header
  scripts" or "tracking code" box; on a site you build yourself it goes before `</body>`.

## Steps

### 1. Create the channel

Go to **Settings → Inboxes**, choose to add an inbox, and pick **Website**. You are asked for five things,
and all five are visible to your visitors except the first:

| Field | What it is |
|---|---|
| **Website Name** | the inbox's name in your dashboard, and the name at the top of the widget |
| **Website Domain** | the address of the site the widget will live on, e.g. `paperlayer.test` |
| **Widget Color** | the colour of the bubble and of the visitor's own messages |
| **Welcome Heading** | the first line a visitor reads when they open the widget |
| **Welcome Tagline** | the sentence under it |

Then **Enable channel greeting**, and if you switch it on, the greeting itself. A greeting is sent
automatically when a visitor sends their first message — it is a message in the conversation, not a label on
the widget, so it appears in the thread and your agents can see it was sent.

### 2. Choose who works in it

The next step adds agents. An agent who is not a member of this channel sees nothing from it — not in their
list, not in search, not in their notifications. Administrators see every channel without being added.

### 3. Install the widget

The last step of setup shows you a script. It is also on the channel's own page afterwards: open
**Settings → Inboxes → your website channel**, and switch the preview panel on the right from **Preview** to
**Script**.

![The website channel's settings with the preview panel switched to Script, showing the install snippet](media:channels/website-script-en.png)

Copy it and paste it into your site's HTML, before the closing `</body>` tag, on every page you want the
chat to appear on. It looks like this, with your own installation address and your own website token:

```html
<script>
  (function(d,t) {
    var BASE_URL="https://chat.lynomia.com";
    var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
    g.src=BASE_URL+"/packs/js/sdk.js";
    g.async = true;
    s.parentNode.insertBefore(g,s);
    g.onload=function(){
      window.chatwootSDK.run({
        websiteToken: 'your-website-token',
        baseUrl: BASE_URL
      })
    }
  })(document,"script");
</script>
```

The script is `async`, so it never blocks your page from rendering. The **website token** in it is what
identifies the channel; it is not a secret in the sense a password is — it is in the source of every page
you put it on — but it is the only thing tying that widget to your account, so do not publish it anywhere
it does not need to be.

### 4. Check it from the visitor's side

Open your own site in a normal browser window. The bubble appears in the bottom corner, in the colour you
chose.

![A demo shop with the chat bubble in the bottom corner](media:channels/website-bubble-en.png)

Click it. The widget opens on your welcome heading, your tagline, whether anyone is available, and the reply
time you set — not on an empty composer. The visitor starts the conversation deliberately, with
**Start Conversation**.

![The widget open on the demo shop, showing the welcome heading, the tagline and the Start Conversation button](media:channels/website-widget-open-en.png)

### 5. Watch it arrive

Send yourself a message from that widget, then look at **Conversations** in the dashboard. It is there, on
the website channel, from a contact Lynomia Chat has just created for this visitor.

![The message from the widget, open in the agent's inbox on the website channel](media:channels/website-arrival-en.png)

A visitor who has not told you who they are gets an invented friendly name and no email address. That is not
a gap to be fixed — it is what you know about them so far. A pre-chat form, the email collect box, and
anything your own site passes to the widget all fill it in; each of those is below.

## What the visitor sees, and what controls it

Everything on the widget comes from one place: **Settings → Inboxes → your website channel**, and the
**Widget features** section on it. The panel on the right is a live preview — it changes as you type, before
you save.

| On the widget | The setting |
|---|---|
| the name at the top | the inbox's name |
| the first line, and the sentence under it | Welcome Heading, Welcome Tagline |
| the colour of the bubble and the visitor's messages | Widget Color |
| "Typically replies in a few minutes" | Reply time |
| "We are Online" / "We are away at the moment" | whether any agent of this channel is online right now |
| the first reply the visitor receives | the channel greeting |
| the paper-clip, the emoji button, "End conversation" | Features |

**Reply time is a promise you are making, not a measurement.** It says what you choose — a few minutes, a
few hours, or a day — and nothing in the product checks it against reality. Pick the one you can keep on your
worst day, not your best.

**Online and away is about people, not opening hours.** The widget says you are online when at least one
agent who is a member of this channel is signed in and set to online. Nobody signed in, or everybody set to
busy, and a visitor is told you are away. If you want the widget to follow your opening hours instead, that
is [business hours](set-up-an-inbox) on the same channel.

### Where the bubble sits, and what it says

**Bubble** (left or right, Standard or Expanded) and **Launcher Title** behave differently from everything
else on that page, and it is worth knowing why before you go looking for them on a colleague's screen.

They are not account settings. They are written into the snippet you copy:

```html
window.chatwootSettings = {"position":"left","type":"expanded_bubble","launcherTitle":"Chat with us"};
```

So the widget obeys whatever the snippet on your site says, and the controls in the dashboard only exist to
produce that snippet. They are remembered in your own browser, which means a colleague opening the same page
sees the defaults rather than your choices — and changing them in the dashboard changes nothing on your site
until you copy the snippet again and replace the one on your page.

### Asking who they are first

A **pre-chat form** puts a short form in front of the conversation: name, email, phone, or fields you add
yourself. Open the **Pre Chat Form** tab on the channel, switch it on, and choose which fields appear and
which are required.

![The Pre Chat Form tab: the switch, the message shown above the form, and the fields it asks for](media:channels/website-prechat-en.png)

It is a trade. Every field you ask for is a visitor who closes the widget instead of filling it in, and a
contact with an email address is worth a great deal — you can reply when they have gone, and the conversation
can continue over email. Asking for a name and an email is usually right; asking for a phone number, a
company and an order number usually is not.

If you do not use a pre-chat form, switch on the **email collect box** instead (in Widget features). It asks
for an email address inside the conversation, after the visitor has already started talking to you, which
costs far fewer of them.

## Making the channel yours

Three settings on the **Widget features** section decide how the conversation behaves rather than how it
looks:

- **Enable email collect box** — asks an anonymous visitor for their email address inside the chat.
- **Allow messages after conversation resolved** — lets a visitor reply to a conversation an agent has
  closed, instead of starting a new one.
- **Enable conversation continuity via email** — when you know the visitor's email address, a reply sent
  after they have left the page reaches them by email, and their reply comes back into the same
  conversation. This is what stops a live chat from being useless the moment the visitor closes the tab.

## Keeping it to your own site

The **Configuration** tab carries the three security settings, and a production installation should look at
all three:

![The Configuration tab: allowed domains, the mobile web view switch, and identity validation with its secret key masked](media:channels/website-configuration-en.png)

- **Allowed Domains.** The widget script works on any page it is pasted into, including somebody else's.
  List the domains you own — `example.com, www.example.com, shop.example.com` — and the widget refuses to run
  anywhere else. Left blank it runs everywhere, which is fine while you are testing and not fine afterwards.
- **Enable widget in mobile apps.** Mobile web views do not send a domain, so they are refused by the rule
  above. Switch this on only if you embed the widget inside an iOS or Android app.
- **Identity Validation.** A secret key your own servers use to sign a visitor you have already logged in,
  so that nobody can open your widget and claim to be one of your customers. If you set every signed-in
  customer's identity from your own backend, switch on **Require identity validation for all conversations**
  as well, and unsigned visitors cannot start a conversation at all. Rotating the key revokes the old one
  immediately, with no overlap, so change your servers first.

## Limits

- A new channel is on **UTC** time until you change it. Business hours and out-of-office replies will be out
  by your local offset until you do.
- The **bubble position, type and launcher title live in the snippet**, not in your account. Changing them
  in the dashboard changes the snippet it offers you; it does not change your site.
- **Reply time is a claim.** Nothing measures it.
- **Allowed Domains is empty on a new channel**, which allows every domain.
- A visitor who clears their browser storage is a **new visitor**: the widget identifies a returning one by
  what it stored in their browser, so the same person on a different device is a different contact until
  something — an email address, identity validation — tells you otherwise.

## Who can do this

Administrators create channels and change their settings. Agents work in the conversations the channel
produces and cannot see the Inboxes settings at all.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Set up an inbox](set-up-an-inbox)
- [Work in the inbox](work-in-the-inbox)
- [Assign and prioritise](assign-and-prioritise)
- [Live chat campaigns](live-chat-campaigns)

## If it does not work

**No bubble on your site.** Open your page's source and confirm the script is in it — a CMS that strips
`<script>` tags from a content box is the usual cause, and the fix is the theme's header or footer code box
rather than a page. Then check **Allowed Domains** on the Configuration tab: a domain list that does not
include the site you are looking at stops the widget before it draws anything.

**The bubble is in the wrong corner, or has no label.** Those come from `window.chatwootSettings` in the
snippet on your site, not from the dashboard. Copy the snippet again from the Script tab and replace the one
on your page.

**The widget says you are away while you are sitting in the dashboard.** You are not a member of that
channel — administrators see the inbox without being a member, and the widget counts members. Add yourself
on the channel's **Collaborators** tab, and check your own availability is set to online.

**Messages arrive but nobody is assigned.** Auto-assignment only hands conversations to agents whose
availability is **online**. With nobody online, conversations wait in the channel, unassigned and visible,
until someone takes them.

**A visitor says they replied and you see nothing.** Check whether the conversation was resolved: unless
**Allow messages after conversation resolved** is on, a visitor who returns to a closed conversation starts
a new one instead, and it will be at the top of your list as a separate thread.
