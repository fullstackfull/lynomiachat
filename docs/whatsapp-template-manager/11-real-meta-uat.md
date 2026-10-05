# 11 — Real Meta UAT

This phase is only honestly finished when a real template is created, submitted, approved, edited and deleted at a
real WhatsApp Business Account from inside Lynomia Chat. This document records what was attempted, what blocks it,
and the exact script to run the moment a real WABA is available.

**Verdict: SOFTWARE COMPLETE / REAL META UAT BLOCKED.** No Meta template was created, edited or deleted. Nothing
below is reported as passed.

---

## 1. Why it is blocked, with the evidence

The blocker is credentials, not code and not the network.

**There is no real WhatsApp Business Account connected to this installation.** The only WhatsApp channel is the
development fixture:

```
inbox="WhatsApp Support" provider=whatsapp_cloud phone=+96590000001
waba="WABA_LYNOMIA" phone_id="555000111" token_len=11 token_prefix="fixtur"
```

`WABA_LYNOMIA` is not a Meta business account id, `555000111` is not a phone number id, and the access token is the
eleven-character string the seed script writes. No environment variable carries a Meta credential either:

```
ENV WHATSAPP/FB_/FACEBOOK keys: []
```

**The network is not the problem.** An unauthenticated probe reaches Graph v24.0 and is refused for the only reason
it should be:

```
GET https://graph.facebook.com/v24.0/me  →  400
{"error":{"message":"An active access token must be used to query information about the current user.",
          "type":"OAuthException","code":2500,...}}
```

So the path from this container to Meta is open; what is missing is a business account, a system user token with
`whatsapp_business_management`, and a phone number. Those are account-level assets that cannot be fabricated, and
borrowing someone else's production WABA to run a destructive script is exactly what the brief forbids.

**A second, independent blocker applies to the webhook half.** Template status webhooks are delivered only to the
Meta App Dashboard's default callback URL for the app — Meta's own documentation states that these webhooks "do not
support callback overrides" (`01-meta-api-contract.md §8`). Pointing them at this installation means editing the
callback URL of a real Meta app, which is configuration outside this repository and outside this container, and which
would redirect a live app's webhooks away from wherever they currently go.

---

## 2. What stands in for it, and what that does and does not prove

| Substitute | Proves | Does not prove |
|---|---|---|
| Request specs with stubbed Graph calls | the request Lynomia builds, the parameters it sends, the node it sends them to, and what it does with each documented response and error | that Meta accepts that request |
| `01-meta-api-contract.md`, quoted from Meta's current documentation with citations | the contract the stubs encode is the published one at v24.0 | that the published contract matches the live behaviour of a specific WABA |
| Constructed webhook payloads in Meta's documented shape | the route, the signature check, the branch, the WABA resolution, the language fallback and the row update | that Meta delivers to this installation |
| Browser journeys against the built bundle | every screen, state and confirmation a person sees | any remote state transition |

The honest summary: **everything up to the wire is verified; nothing across it is.**

---

## 3. The UAT script, to run when a real WABA exists

### Before starting

- Use a **sandbox or staging WABA**, never a production one.
- Every template created below uses a **throwaway name** carrying a run marker, e.g. `lyn_uat_20261005_a`. Never a
  name a real business would want: an approved template's name **cannot be reused for 30 days after deletion**
  (`01-meta-api-contract.md §7`), so burning a real name is not reversible within the phase.
- **Do not delete any template this script did not create.** If the WABA holds production templates, the delete steps
  apply only to rows whose name starts with the run marker.
- Have the Meta WhatsApp Manager open in another tab, as the independent observer. Lynomia's claims are only
  believable where Meta agrees with them.

### Setup

| # | Step | Expected in Lynomia | Expected at Meta |
|---|---|---|---|
| S1 | Connect the WABA to an inbox (Settings → Inboxes → WhatsApp) | the inbox saves; Templates lists the WABA's existing templates after the first sync | the list matches WhatsApp Manager exactly, name for name and language for language |
| S2 | Set `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN` and point the Meta app's callback URL at `/webhooks/whatsapp` | the `GET` handshake returns the challenge | the app shows the callback verified |
| S3 | Confirm `message_template_status_update` is subscribed | — | `GET /{WABA}/subscribed_apps` lists it alongside `messages` and `smb_message_echoes` |

### Lifecycle

| # | Step | Expected in Lynomia | Expected at Meta |
|---|---|---|---|
| L1 | Create a draft from a starting point, name `lyn_uat_<date>_a`, Utility, one body variable with a sample | the row reads **Not sent to WhatsApp for approval**; no Graph call is made | the template does **not** exist |
| L2 | Edit the draft's body and save | the row stays a draft; still no Graph call | still absent |
| L3 | Submit | the confirmation states what WhatsApp does next; after it, the row reads **In review at WhatsApp** | the template appears with status `PENDING`, the same name, language, category and components |
| L4 | Double-click Submit on a second draft | exactly **one** template is created | exactly one row, not two |
| L5 | Wait for the decision | the row moves to **Approved** (or **Rejected by WhatsApp** with the reason) without a manual sync — the webhook carries it | the same status, at the same time |
| L6 | Press Sync | nothing changes | — |
| L7 | Edit the approved template's body | the edit is accepted; Meta returns `{"success": true}` | WhatsApp Manager shows the new body and the status returns to `PENDING` |
| L8 | Try to change the category of the approved template | the control is **not offered** | — (the API would refuse it) |
| L9 | Try to edit a template while it is in review | the control is **not offered** | — |
| L10 | Duplicate the approved template | a **new local draft** with a new name and no Meta identifiers | nothing is created |
| L11 | Send a campaign or a flow message using the approved template | the message is delivered | the message arrives on a real handset with the variable filled |
| L12 | Delete a template created by this run | the confirmation states the 30-day name lockout; the row goes | the template is gone from WhatsApp Manager |
| L13 | Delete the same template a second time (via a stale tab) | the error is readable and the row is not resurrected | — |
| L14 | Delete a template in WhatsApp Manager, then press Sync in Lynomia | the row reads **no longer at WhatsApp**, and is not silently removed | — |

### Failure paths worth forcing

| # | Step | Expected |
|---|---|---|
| F1 | Submit a draft whose name already exists in that WABA and language | the draft **survives** with Meta's reason stored and shown; nothing is lost |
| F2 | Submit with an expired or revoked token | a readable message naming the credential as the problem; the draft survives |
| F3 | Submit a body whose variable has no sample value | refused **before** any Graph call |
| F4 | Two WABAs on one account, same template name | the two rows stay separate, each listing only its own inboxes |

### What to record

For each row: the Lynomia screen, the Meta screen, and the timestamp. A step passes only when both agree. Anything
that disagrees is a defect against `01-meta-api-contract.md`, and the contract document is the thing to re-verify
first — Meta's rules move, and this phase's whole design is pinned to them.

---

## 4. The one thing to re-check before trusting any of this again

`01-meta-api-contract.md` was written from Meta's documentation as published in **October 2026** and every claim in it
is cited. Meta has already removed one parameter this repository still assumed (`allow_category_change`, removed
2025-04-09, `§10`). Before the UAT above is run, re-read the five endpoint pages and confirm §§2–8 still hold. If one
of them has moved, fix the contract document first and the code second — in that order, because the code's shape is
derived from the document.
