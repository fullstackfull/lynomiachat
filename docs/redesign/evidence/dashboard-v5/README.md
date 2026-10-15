# Dashboard, fifth pass: campaigns and the automation panel

Every image here is a real screenshot of a real page served by `bin/rails s` + `bin/vite dev` on this
machine, taken by `tools/visual/capture.mjs` against the same URLs at the same widths before and after
the change. Nothing is a mockup, a theme preview, or an edited image.

The account is the local `rails db:seed` account (`Acme Inc`, `john@acme.inc`) plus
`tools/visual/synthetic_fixtures.rb`. Every campaign, rule, inbox and contact name in these shots is
invented in that seed or that file. No customer data, address, phone number or token appears in any of
them.

## What is paired, and what is not

| Shot | before | after | note |
| --- | --- | --- | --- |
| `desktop/campaigns.png` (live chat) | yes | yes | |
| `desktop/campaigns-one-off.png` (SMS) | yes | yes | both shots are after the fixture fix below |
| `desktop/campaigns-whatsapp.png` | yes | yes | both shots are after the fixture fix below |
| `desktop/campaign-create.png` | yes | yes | the WhatsApp create flow, opened from the header button |
| `mobile/campaigns-whatsapp.png` | yes | yes | 390 x 844 |
| `mobile/campaign-create.png` | yes | yes | 390 x 844 |
| `desktop/automation-editor.png` | yes | yes | the two inputs changed; the rest of the panel did not |
| `desktop/automations.png` | yes | **no** | the list page was not changed in this pass, so there is no "after" to pair with it. It is here as the context the editor opens from. |

The two `before` mobile shots were taken by checking the pre-redesign components back out of git
(`df00ec6a`), capturing, and restoring. They are the old code running, not a reconstruction.

## The fixture fix that the campaign shots depend on

`Campaign#ensure_correct_campaign_attributes` derives `campaign_type` from the inbox, and each campaign
page filters on BOTH type and inbox channel. `synthetic_fixtures.rb` put its two one-off campaigns on the
**website** inbox, so they were forced back to `ongoing` and appeared on no page at all — which is why
the SMS and WhatsApp pages had nothing in them to design against. They sit on the SMS and WhatsApp
inboxes now, and there is a blocked WhatsApp campaign among them, a state no amount of seeding would
otherwise produce on a developer's machine.

So the `before` shots of those two pages are the old UI on the fixed data. That is the honest comparison
for a visual change: the same rows, drawn two ways.

## What the pairs show

**The page header.** Before: a `span` styled to look like a heading, and a button. After: an `h1`, the
count, a sentence saying what that channel's campaigns are, and a rule under it.

**The cards.** Before: title, chip, message, and a sentence assembled from translation fragments —
"Sent from PaperLayer Whatsapp on Oct 17, 5:10 PM" — on all three one-off campaigns, including the one
whose chip says it was never sent. After: a channel tile, a heading-rank title, and labelled facts whose
tense follows the status (Sends / Sent / Was due), plus the audience the campaign is addressed to.

**The create flow.** `before/desktop/campaign-create.png` is a 400px panel hanging off the header button
with no backdrop and its own Create button below the fold. `before/mobile/campaign-create.png` is the
same panel at 390px: it runs off the left edge of the screen, so the title reads "reate WhatsApp
campaign" and there is no Create button on screen at all. After: a native modal, body scrolling, title
and footer fixed, at both widths.

**The automation panel.** The two `woot-input`s are now the design system's `Input`. This is a small,
deliberate change and the pair shows a small difference — consistency of label, focus ring and error
treatment with every other control in the panel, not a new design.
