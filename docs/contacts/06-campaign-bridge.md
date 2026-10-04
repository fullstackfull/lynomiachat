# Contacts phase C3 — label and audience to campaign

A discoverability fix. The mechanism was already there; the way in was missing.

**No Ruby changed in this section.** The campaign backend, its recipient resolution, its validation and its
policies are exactly as they were.

---

## What the campaign engine actually accepts

| Source | Where | Status |
|---|---|---|
| `{ type: 'Label', id }` | `app/models/campaign.rb:70-73` — `account.contacts.tagged_with(account.labels.where(id: label_ids).pluck(:title), any: true)` | supported, OSS |
| `{ type: 'Audience', id }` | `custom/app/models/custom/campaign_audience.rb:12-19`, prepended over the OSS method, resolving each audience through its own saved filter | supported, Lynomia overlay |
| an arbitrary list of contact ids | — | **not supported**, and not invented here |

Reading only `app/` would have missed the second row entirely — the reason the brief insists on searching all
three trees. Both sources are already in the campaign form:
`buildCampaignAudience(labelIds, audienceIds)` (`shared/constants/campaign.js:12-15`), with a server-side
recipient count from `POST /campaigns/audience_preview`.

So a campaign from a label needed no recipient work at all.

---

## The gap

`ContactMoreActions.vue` built its audience section from `props.segment ? segmentActions : []`, and each
cross-module action additionally required `isShared`. A label page has no segment, so it offered nothing — not
even for `vip`, which is a perfectly good recipient source.

And the prefill helper only spoke about audiences: `?audience=<id>`, read by `WhatsAppCampaignsPage` on
activation.

---

## What was added

A label page now offers **Use in a new WhatsApp campaign**. It travels exactly as an audience does:

```
label page → ?label=<id> → campaigns_whatsapp_index → initialLabelIds → the recipient picker
```

- `audienceHelper.js` gained `LABEL_QUERY_PARAM`, `labelIdFromQuery` and `findAccountLabel`, beside the audience
  equivalents, sharing one id parser. A value that is not a single positive integer, or an id the account does
  not have, prefills nothing and the dialog opens empty — the server would refuse it anyway.
- `ContactMoreActions` reads an `activeLabel` prop; `ContactListHeaderWrapper` derives it from the route the way
  the create dialog does, and branches `useInCampaign` on which of the two is open. A label page has no active
  segment and a segment page has no label in its route, so exactly one applies.
- `WhatsAppCampaignsPage` reads either parameter and fills `initialLabelIds` or `initialSharedAudienceIds`;
  `WhatsAppCampaignDialog` and `WhatsAppCampaignForm` take the new prop into the picker they already had.

No contact ids are copied, no recipient table is stored, no campaign route or model is added.

---

## Where the action is, and where it deliberately is not

| Context | Campaign action | Why |
|---|---|---|
| A label page | **yes** | `{ type: 'Label', id }` is a recipient source |
| An open shared audience | **yes**, unchanged | `{ type: 'Audience', id }` is a recipient source |
| A personal (unshared) audience | no, unchanged | the server refuses a campaign that names one |
| The ordinary `/contacts` list | no | there is no "all contacts" recipient source, and inventing one would mean an arbitrary id list |
| An unsaved ad-hoc filter | no | nothing to reference; saving it as an audience first is the supported route, and the menu already offers that |
| A search result | no | same |
| A multi-selection of contacts | no | arbitrary contact ids are not a recipient source, and C3.2 says not to invent them |

### Automation is a separate question, answered separately

A label is **not** offered to automation, and this is the part of C3 that matters most.

The automation condition catalogue has exactly one audience-shaped condition: `contact_audience`, which names a
shared audience (`audienceHelper.js:audienceConditionFor`). There is no condition meaning "the contact carries
label X". Separately, `labels` as an automation condition means the **conversation's** labels, not the contact's,
and `ActionService#add_label` attaches a label to `@conversation` — never to the contact.

So exposing "Use in a new automation rule" from a label page would open a rule builder that cannot express what
the menu implied. The gating is therefore per capability rather than per context: the audience path keeps both
actions, the label path gets the campaign one only.

---

## Verification

| Gate | Result |
|---|---|
| `ContactMoreActions.spec.js` | **11 tests**, 3 new: the campaign action on a label page, no automation action beside it, nothing for a user the campaign route refuses, and the audience actions still winning when both are present |
| `audienceHelper.spec.js` | **12 tests**, 2 new groups: the label parameter does not read the audience one or vice versa, and an id the account does not have resolves to nothing |
| `WhatsAppCampaignsPage.spec.js` | **10 tests**, 4 new: the label prefill, an id that is not the account's, a non-integer value, and the prefill cleared on close |
| Campaigns + contacts frontend | **5 files, 59 tests, 0 failures** |
| `campaign_spec.rb` + campaigns controller + audience preview | **70 examples, 0 failures** — unchanged, as expected for a section that changed no Ruby |

Tenancy and permissions are the target route's own, unchanged: the menu item appears only when
`canReach('campaigns_whatsapp_index')` passes that route's feature flag, permissions and installation type — the
same question the command bar asks — and the campaign create itself is still gated by `CampaignPolicy`. A label
id from another account resolves to nothing in the picker, and `audience_contacts` scopes to
`account.labels.where(id:)` regardless.

---

## Known limitations

| | |
|---|---|
| Only the WhatsApp campaign builder is prefilled | It is the only one with prefill plumbing. The SMS and live-chat builders have no equivalent, which was already true for audiences. |
| The campaign opens with the label preselected but the dialog is not deep-linkable to a *saved* campaign | Unchanged: the query opens the create dialog, as it does for an audience. |
| A label page offers no recipient count before opening the campaign | The count comes from `POST /campaigns/audience_preview` inside the campaign form, where it already works for both sources. |
