---
title: Reconnect a WhatsApp number
description: You will know the right order to reconnect in, what each refusal while reconnecting means, and the two things not to do.
position: 100
tags: [whatsapp, errors, connection]
seo_title: "Reconnect a WhatsApp number in Lynomia Chat"
seo_description: "How to reconnect a WhatsApp number after a token or permission failure, what each reconnection error means, and why deleting the inbox is not the fix."
---
A WhatsApp number needs reconnecting when its credential stopped being accepted — see
[error 190](whatsapp-error-190) for what causes that. The sequence matters, because the wrong first step can make
the number harder to recover.

## The order

1. **Settings → Inboxes → the inbox → Configuration.** Reconnect from here. For a number connected through the
   guided sign-up this re-runs it; for a manually connected number this is where you replace the token.
2. **Account Health.** Confirm the number now reports normally, and that the webhook is registered.
3. **Send one test message** from your own phone to the number, and check it appears in Conversations.
4. **Retry what failed.** Nothing re-sends by itself.

## What the refusals during reconnection mean

| What you see | What it means |
|---|---|
| Failed to exchange code for access token | the guided sign-up did not complete. Start it again; do not paste a token as a workaround |
| The access token does not have the required permissions | the authorisation was approved without everything WhatsApp needs. Re-run it and approve all of it |
| Failed to fetch phone number information | Meta accepted the credential but would not describe the number. Usually transient; try again |
| Channel already exists for this phone number | the number is connected somewhere else on this installation — see [the number is already connected](whatsapp-number-already-connected) |
| Reauthorization is not supported for this type of WhatsApp channel | this is not a Cloud API number. A number connected through another provider is reconnected through that provider's settings |

## The two things not to do

**Do not delete the inbox.** It does not reconnect anything, it loses the inbox's settings and collaborators, and
it can release the number from your Meta app — which turns a five-minute reconnection into a support case.

**Do not connect the number a second time as a new inbox.** A number can only be connected once across the whole
installation, so this fails, and the failure message is easy to mistake for something else.

## A worked example

An inbox shows the reauthorization banner on Monday morning. The administrator opens **Configuration**, reconnects
through the guided flow, approves the permissions, and checks **Account Health** — the number reports normally and
the webhook is registered. A test message arrives. They then go through Friday's three failed replies and press
Retry on each. Total time, about four minutes.

## Who can do this

**Administrators** only. Configuration and Account Health are not open to agents, and no custom role permission
covers inboxes — see [roles and permissions](roles-and-permissions).

## Limits

- **Messages that failed while the number was disconnected are not re-sent.** Retry each one.
- **Incoming messages during the outage were still stored**, which is why there is a queue to work through.
- **Lynomia Chat cannot tell you which permission was missing.** Meta reports a refusal, not a diff.
- **A hand-made token will expire again.** The guided sign-up is what stops this recurring.

## Related

- [Error 190](whatsapp-error-190)
- [The number is already connected](whatsapp-number-already-connected)
- [Nothing is arriving from WhatsApp](whatsapp-nothing-arrives)
- [Connect a WhatsApp number](connect-whatsapp)
- [WhatsApp Business coexistence](whatsapp-business-coexistence)
