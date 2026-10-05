---
title: The template lifecycle
description: You will know what each template state means, what you can change in it, and what happens when you edit or delete a template WhatsApp already holds.
position: 50
tags: [whatsapp, templates]
seo_description: "Draft, submitted, in review, approved, rejected, paused, disabled: what each WhatsApp template state allows in Lynomia Chat, and the 30-day name block."
---
A template passes through two different worlds. It starts in Lynomia Chat as a draft only you can see. Once you
submit it, WhatsApp owns its state, and everything after that is WhatsApp's decision reported back to you. Knowing
where that line falls explains most of what the template manager will and will not let you do.

**Before you submit**, the template is a draft in Lynomia Chat. WhatsApp has never heard of it. You can rewrite it
as often as you like, nothing is reviewed, and deleting it affects nothing anywhere. The list says so plainly:
*Not submitted for WhatsApp approval.*

**After you submit**, WhatsApp holds the template. Its state is whatever WhatsApp says it is. Lynomia Chat reads
that state — immediately when WhatsApp sends an update, and otherwise on the refresh that runs every few hours.
Nothing in Lynomia Chat can set a template to approved.

## The states, and what you can change in each

| State | What it means | Content | Category | Delete | Submit |
|---|---|---|---|---|---|
| **Not submitted for WhatsApp approval** | a draft, local only | yes | yes | yes, locally | yes |
| **Submitting to WhatsApp** | handed over, no answer yet | yes, locally | yes | yes | no |
| **WhatsApp did not accept the submission** | WhatsApp refused the request itself | yes | yes | yes | yes, again |
| **In review at WhatsApp** | WhatsApp is reading it | no | no | yes | no |
| **Approved** | sendable | yes — it goes back into review | no | yes | no |
| **Rejected by WhatsApp** | refused, with a reason | yes | yes | yes | no |
| **Paused by WhatsApp** | temporarily unusable, usually over quality | yes | yes | yes | no |
| **Disabled by WhatsApp** | WhatsApp has taken it out of service | no | no | **no** | no |
| **No longer at WhatsApp** | the last refresh did not find it | as its last state allowed | as its last state allowed | as its last state allowed | no |

A few others come straight from WhatsApp — under appeal, archived, being deleted, deleted, and template limit
reached. None of them can be edited from here, and *No longer at WhatsApp* is Lynomia Chat's own observation rather
than a state WhatsApp reports: the last refresh saw that business account's other templates and not this one. Its
detail panel tells you when it was last seen and suggests duplicating it.

Whatever the state, **Duplicate** always works. It makes a brand-new draft with a new name, carrying none of
WhatsApp's status or history.

## What never changes

WhatsApp treats a template's **name** and **language** as its identity, so neither can be edited — not here, not in
WhatsApp Manager. There is no rename. If you need a different name, duplicate the template, edit the copy and
submit it. And a template in `en_US` and the "same" template in `ar` are two separate templates to WhatsApp, each
reviewed on its own. Both fields are locked in the builder when you edit, with the reason beneath them, rather than
quietly ignored.

## Editing an approved template costs you something

Saving a change to an approved template sends it back to WhatsApp for review. While it is in review it may not be
sendable, so a campaign or flow depending on it can stop working for a while. WhatsApp also limits how often you may
do this: **one change every 24 hours, and ten every 30 days** for an approved template. Lynomia Chat warns you
before you save.

Only the content and, where WhatsApp allows it, the category go to WhatsApp. WhatsApp replaces all of the
template's parts with what you send, so there is no partial edit — the complete template goes every time.

The category is the awkward one: WhatsApp will not change the category of an approved template. You can only change
it while the template is rejected or paused. To move a template from MARKETING to UTILITY, create a new one.

## Deleting, and the 30-day name block

Deleting a **draft** removes a row in Lynomia Chat and nothing else.

Deleting a template **WhatsApp holds** is a real deletion at WhatsApp:

- campaigns and flows that use it stop working, immediately and without warning;
- **WhatsApp blocks the name for 30 days.** You cannot recreate `order_shipped` under that name for a month, in any
  language;
- if the template has been sent but not yet delivered, WhatsApp may hold it as *being deleted* for 30 days. When
  that happens the next refresh brings the template back into your list carrying that state — which is the truth,
  not an error.

A disabled template cannot be deleted at all. That is WhatsApp's rule, and the Delete action is not offered.

## A worked example

Your `order_shipped` template is approved and used by a flow, and you want to add a tracking button. Edit it, add
the button, fill in its sample value and save; Lynomia Chat warns you it goes back into review and you accept. The
template now reads **In review at WhatsApp**, and the flow's Send template node cannot use it while it is there, so
it follows its failure path. WhatsApp approves it an hour later and the state updates on its own.

Had you instead deleted it and made a new one, the name would have been blocked for 30 days and the flow would have
needed editing.

## Who can do this

**Administrators** only — submitting, editing, deleting and duplicating. Each action is checked on the server as
well as hidden in the interface, so an action a state does not allow cannot be forced.

## Limits

- **A draft is not a submission.** Nothing reaches WhatsApp until you submit it.
- **Submitting twice is not possible.** A submit already in flight is refused rather than creating a second
  template at WhatsApp.
- **A template is per language.** There is no bundle, and no way to submit several languages at once.
- **There is no revision history.** Lynomia Chat does not keep previous versions of a template's text.
- **Lynomia Chat cannot appeal a rejection.** Appeals happen in WhatsApp Manager; while one is open, the state
  reads *Under appeal* here.

## Related

- [WhatsApp templates](whatsapp-templates)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp campaigns](whatsapp-campaigns)
- [When WhatsApp does not work](whatsapp-troubleshooting)

## If it does not work

**Submit is not offered.** The template is already at WhatsApp, or a submit is still in flight.

**Edit is not offered.** WhatsApp only allows edits while a template is approved, rejected or paused.

**The category field is locked.** The template is approved. Change the category only while it is rejected or
paused, or create a new template.

**It has been in review for hours.** That is WhatsApp's queue. **Sync templates** will fetch the current state, but
it cannot hurry the review.
