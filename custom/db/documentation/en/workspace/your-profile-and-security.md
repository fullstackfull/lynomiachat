---
title: Your profile and security
description: Your name, your picture, how you send messages, and the two-factor authentication that protects the account.
position: 70
tags: [workspace, profile, security]
seo_description: Profile settings in Lynomia Chat — name, picture, message hotkey, interface, notifications — and enabling two-factor authentication.
---
**Settings → Profile Settings**, or your own avatar at the bottom of the sidebar.

## What is yours to change

| Section | What is in it |
|---|---|
| **Profile** | your name, your picture, your email address |
| **Message signature** | the sign-off appended to your replies |
| **Hotkey to send** | Enter, or Cmd/Ctrl + Enter |
| **Interface** | font size, and the dashboard's appearance |
| **Audio notifications** | whether, when, and with what sound |
| **Access token** | your personal API token |
| **Active sessions** | where you are signed in |

**Your email address is your identity.** Changing it signs you out: the credentials you log in with have
changed, so you log in again with the new one.

**The send hotkey is worth a moment's thought.** On Enter, a stray return key sends a half-written reply to
a customer. On Cmd/Ctrl + Enter, Enter makes a new line and nothing goes out by accident. Teams that handle
long replies usually prefer the second.

**Your access token is a credential.** It can do what you can do. Treat it accordingly, and never put it in
a browser or a mobile app.

## Two-factor authentication

**Settings → Profile Settings → Two-Factor Authentication.**

Two-factor authentication means a password is not enough to get into your account: a code from an
authenticator app on your phone is needed as well. It uses TOTP, which is what Google Authenticator, Authy
and every other authenticator app produce.

Switching it on:

1. Scan the QR code with your authenticator app, or enter the code shown underneath it by hand.
2. Type the six-digit code the app gives you, to prove the pairing worked.
3. **Save the backup codes.** They are shown once. They are how you get in when your phone is lost, broken
   or replaced — and without them, a lost phone means an administrator has to intervene.

Store the backup codes somewhere that is not the phone running the authenticator. A password manager is
the right place; a note on the same phone is not.

## Limits

- **Two-factor is per person, not per account.** Switching it on protects you, not your colleagues.
- **Backup codes are shown once** and each works once.
- **Changing your email signs you out.**
- **Some installations lock profile editing**, in which case the fields are there but not editable.

## Related

- [Roles and permissions](roles-and-permissions)
- [Teams and agents](teams-and-agents)
- [Audit logs](audit-logs)
