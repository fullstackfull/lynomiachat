# 09 — Campaign integration

How a campaign picks a template now, what was wrong with how it did, and what was deliberately left alone. Read with
`10-flow-integration.md`, which shares this document's selection rule.

---

## 1. Selection: one rule, in one implementation

A template can be **offered** by a picker and **sent** by the send path, and those are not the same question. This
phase made the difference explicit instead of leaving it implied in two places.

| | Rule | Where |
|---|---|---|
| Offering a template (composer, campaign form, flow node, manager) | approved **and** the product rule: not an authentication template, not a CSAT template, no LIST / PRODUCT / CATALOG / CALL_PERMISSION_REQUEST component, no LOCATION header | `Flows::Template.sendable?` on the server, `isSendableTemplate` from `@chatwoot/utils` on the client — the same rule in two languages, already in lock-step |
| Sending a template | Meta's rule: the template exists in this channel's synced list for this name and language, and Meta says `APPROVED` | `Whatsapp::TemplateProcessorService#find_template` |

The send path stays laxer on purpose: an API client sending an authentication template to an ordinary phone number is
something Meta allows, and narrowing it would break those callers. What it is **not** allowed to do any more is send a
template Meta has not approved — that was the defect this phase fixed
(`00-current-system.md §6.1`).

`Whatsapp::Templates::Query#sendable_for(inbox)` is where a server-side caller asks the offering question, and it
answers from the channel's snapshot. A send must never wait on a projection having run, which is why the snapshot and
not the new table remains the live gate.

## 2. What changed for campaigns

One defect, one line. `WhatsAppCampaignForm.vue` keyed its template dropdown on `template.id` — Meta's id — and a
synced template that arrives without one (this repo's own factory has such entries) therefore had an option value of
`undefined`: picking it never resolved a template and the campaign could not be created. It now keys on
`name|language`, which is how Meta identifies a template and how every other consumer in this codebase matches one,
including the flow builder's own picker.

**Not changed:** the campaign runtime, the parameter parser, the payload shape, the audience round trip P2 added.
There is no campaign engine here, and no campaign draft is lost: the only visible difference is that a template
without a Meta id can now be chosen.
