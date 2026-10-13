---
title: Dashboard apps
description: You will have your own web page appearing as a tab beside the conversation, you will know exactly what data the page is handed, and you will know what a dashboard app cannot do.
position: 40
tags: [integrations, dashboard-apps]
seo_description: "Dashboard apps in Lynomia Chat: add your own page as a tab next to a conversation, read the conversation context it is sent, and the limits of an iframe integration."
---
A dashboard app puts **a page of your own** in front of the agent, as a tab beside the conversation. When the
agent opens that tab, your page is loaded in a frame and handed the conversation it is looking at — who the
customer is, which conversation, which agent, and the account's custom attribute definitions.

It is the answer to "our agents need to see something from our own system while they answer". It is not a
plugin system: your page runs in your own frame, on your own server, and Lynomia Chat tells it only who is on
screen.

## When to use it

When the information your agents need lives in a system of yours and you can put a web page in front of it: an
order lookup, a warranty check, a delivery tracker, a loyalty balance. Anything your developers can render for
a given customer, agents can see without leaving the conversation.

## When not to use it

- **To write back into the conversation.** A dashboard app cannot send a message, change a status, add a label
  or assign anybody. It is read-only as far as Lynomia Chat is concerned. To act on a conversation from
  outside, use the API.
- **To see what a customer bought from a connected store.** That is already built — see
  [Customer 360](customer-360) and [what connecting a store gives you](commerce-overview). A dashboard app is
  for systems Lynomia Chat does not know about.
- **To react to events.** The page is told what is on screen when the agent opens the tab. If you need to be
  told *when something happens*, that is [webhooks](webhooks).
- **To replace the message view.** Opening the app tab hides the messages while it is open. An agent who needs
  both at once will be switching tabs.

## What you need first

- An **administrator** account to create one.
- A page served over **HTTPS**, reachable from your agents' browsers. Plain `http://` is accepted by the form,
  but the dashboard itself is served over HTTPS and a browser will refuse to load an insecure frame inside a
  secure page, so in practice HTTPS is required.
- A page that allows itself to be framed. If your server sends headers that forbid framing, the tab will be
  blank and nothing in Lynomia Chat can override that.

## Steps

1. Go to **Settings → Integrations → Dashboard Apps** and add one.
2. Give it a **title**. This is the tab label the agents will see, so name it for them, not for your
   infrastructure.
3. Give it the **URL** of your page.
4. Save. The tab appears in every conversation immediately, for every agent.

Add as many as you need; each becomes its own tab, in the order they were created.

## Where it appears

A row of tabs appears at the top of the conversation pane as soon as one dashboard app exists. The first tab is
**Messages**; after it, one tab per app, labelled with its title.

The tabs appear only when a conversation is open — there is nothing to show an app about an empty pane. The
frame is not loaded until an agent opens the tab for the first time, so an app nobody uses costs nothing.

## What your page is told

The handshake is yours to start. When your page is ready, post a message to the parent window:

```
chatwoot-dashboard-app:fetch-info
```

Lynomia Chat replies with a JSON string carrying an `appContext` event and a `data` object:

| Key | Contains |
|---|---|
| `conversation` | the conversation on screen, including its id, status, inbox, assignee, labels and custom attributes |
| `contact` | the customer — name, email, phone number, identifier, custom and additional attributes |
| `currentAgent` | the signed-in agent's `id`, `name` and `email`, and nothing else |
| `customAttributes` | the **definitions** of the account's custom attributes, not one contact's values |
| `theme` | `light` or `dark`, following the agent's dashboard |

The context is sent again when the agent returns to the tab, and the theme value tracks the dashboard, so a
page that redraws on `appContext` stays in step.

Two properties of this exchange matter to whoever writes the page:

- **The reply is posted without restricting the receiving origin.** Treat the message as untrusted input in
  your own page: check that it came from the window you expect before acting on it.
- **The payload is not configurable.** You get those five keys. You cannot ask for more, and you cannot ask
  for less.

## A worked example

A Kuwait retailer runs its own warehouse system, which Lynomia Chat knows nothing about. A developer puts up a
page at `https://tools.example.com/agent/delivery` that reads the customer's phone number, looks up their open
deliveries, and renders them as a short table.

An administrator adds a dashboard app titled **Deliveries** pointing at that page. From then on, every agent
answering "where is my order?" opens the **Deliveries** tab and reads the answer, in the conversation, without
asking the warehouse team on Slack.

## Who can do this

**Creating, editing and deleting** a dashboard app is administrators only. The custom role permission list has
no entry for integrations, so this cannot be delegated — see
[roles and permissions](roles-and-permissions).

**Seeing the tabs** is everybody in the account. There is no way to show an app to some agents and not others.

## Limits

- **It is an iframe, not a plugin.** Your page cannot call into the dashboard, read anything it was not sent,
  or change anything.
- **No per-inbox, per-team or per-role visibility.** An app is account-wide and visible to everybody.
- **The URL must start with `http://` or `https://`**, and in practice HTTPS, as above.
- **One URL per app.** To offer two pages, create two apps.
- **No authentication is passed.** Your page is not told who is signed in beyond the agent's name and email,
  and it receives no token. If your page needs to authenticate, it does so by itself.
- **No height control and no resizing API.** The frame fills the pane.
- **Opening a tab hides the messages.** They are not shown side by side.
- **A framing refusal looks like a blank tab.** Nothing reports it in the dashboard; your browser's console
  does.
- **Nothing is recorded.** A dashboard app's use does not appear in [audit logs](audit-logs) and creating one
  does not either.

## Related

- [Integrations](integrations) · [Webhooks](webhooks) · [Slack](slack)
- [Customer 360](customer-360) · [What connecting a store gives you](commerce-overview)
- [Custom attributes](custom-attributes)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**The tab is not there.** No dashboard app exists yet, or no conversation is open. The tab row appears only
with both.

**The tab is there but blank.** Almost always your page refusing to be framed, or an `http://` URL inside the
HTTPS dashboard. Check the browser console on the agent's machine.

**My page never receives the context.** It has to ask. Post `chatwoot-dashboard-app:fetch-info` to the parent
window once your page is ready; nothing is sent before that.

**The customer's custom attribute values are missing.** `customAttributes` carries the account's attribute
*definitions*. The values for this customer are on the `contact` object — see
[custom attributes](custom-attributes).

**Dashboard Apps is not in Settings → Integrations.** You are signed in as an agent or with a custom role. The
page is administrator-only.
