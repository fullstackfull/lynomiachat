# Lynomia Campaigns: reuse map

Decision, from [00](00-existing-system-discovery.md): **Lynomia Campaigns are Chatwoot's one-off campaigns.** A shared
audience becomes one more recipient source in the same `campaigns.audience` column, resolved by the same senders at the
same moment as labels. Nothing new sends, schedules or stores recipients.

## Matrix

| Capability | Existing | Classification | What this phase does |
|---|---|---|---|
| Campaign persistence | `campaigns` row, `audience` jsonb `[{ type, id }]` | **REUSE** | one more entry type, `{ "type": "Audience", "id": <shared audience id> }` (the shape fixed in docs/audience/06 §5). A reference, never a copy of the conditions. No column, no table, no migration |
| Label recipients | `tagged_with(titles, any: true)`, written in 4 senders | **PATCH** | the 4 copies become one `Campaign#audience_contacts` (same relation, same result); Label campaigns are otherwise unchanged |
| Audience recipients | none | **EXTEND** | `Custom::CampaignAudience` (prepended to `Campaign`): labels ∪ shared audiences as one relation of distinct contacts; each audience through its own saved filter (`CustomFilter#contacts` → `Contacts::FilterService#relation`) |
| Audience evaluation | `Contacts::FilterService#relation`, written inline in Automation | **EXTEND** (shared entry point) | `CustomFilter#contacts`: the audience's members now, as the account. Automation's membership check uses it too (same query) |
| Shared / account checks | `CustomFilter.shared`, Automation's `audience_not_shared` | **REUSE** | campaign validation: each `Audience` entry is a shared contact audience of the campaign's account; personal and foreign ids are refused (422) |
| Validation of entries | none (labels resolved in the account at send time) | **EXTEND** | only `Audience` entries are validated, and only on one-off campaigns; `Label` entries keep today's behaviour |
| Scheduling | `TriggerScheduledItemsJob` → `TriggerOneoffCampaignJob` → `trigger!` | **REUSE** | unchanged |
| Dispatch lock, status | `mark_processing!`, `completed!` | **REUSE** | unchanged |
| Senders (WhatsApp, Enterprise WhatsApp, SMS, Twilio) | 4 services | **REUSE** | they iterate `campaign.audience_contacts` instead of their own label lookup; every per-contact check, the template path and the provider call are untouched |
| Recipient records | Enterprise `campaign_recipients` | **REUSE** | audience contacts get the same rows, statuses and analytics |
| Deduplication | `EXISTS` per contact across labels | **REUSE** + **EXTEND** | the union is `contacts.id IN (labels) OR contacts.id IN (audience 1) OR …` over the account's contacts: a contact in two labels and three audiences is one row, sent once; `campaign_recipients`' unique `(campaign_id, contact_id)` stays the backstop |
| Channel eligibility | per sender (phone / BSUID, template params, Liquid, auth guard) | **REUSE** | unchanged, applied to every recipient whatever its source |
| Blocked / opt-out | not excluded by any sender; no opt-out model | **NOT PRESENT** | unchanged: an audience can include `Blocked = false` like any contact filter; no exclusion is added (Label campaigns would otherwise change) |
| WhatsApp template compliance | the form's approved templates, `TemplateProcessorService` | **REUSE** | unchanged |
| Preview / count | the contacts filter's count for one audience | **EXTEND** | `POST campaigns/audience_preview`: the deduplicated count of labels ∪ audiences now, server side, under `CampaignPolicy#create?`. No sample: the audience opens in Contacts for that |
| Dependency on audiences | `Audience::Usage.rules`, 422 on delete / unshare | **EXTEND** | `Audience::Usage.campaigns`: one-off campaigns still to send (`active`, `processing`) that reference the audience. Delete / unshare refused while any rule or such campaign uses it ("This audience is used by X campaigns…"); `campaigns_count` in the audience JSON; the contacts filter note says "used by N automation rules and M campaigns" |
| Release | — | decision | `completed` releases (recipients were resolved at dispatch); deleting the campaign releases (Chatwoot's only way to cancel a scheduled campaign; there is no cancelled status, and `enabled` is not read for one-off campaigns) |
| Permissions | `CampaignPolicy` (administrators) | **REUSE** | the preview authorizes `create?`; no new permission |
| Builder UI | `WhatsAppCampaignForm`, `SMSCampaignForm` (labels multi-select) | **EXTEND** | one `CampaignRecipients` block in both forms: Labels + Shared audiences, at least one of either, and the live count |
| Audit | contact filters audited; campaigns not | **REUSE** | audience changes stay in the existing audience audit; no campaign audit stream is added |
| Analytics | Enterprise WhatsApp analytics on `campaign_recipients` | **REUSE** | no new analytics |
| Automation, Flow Builder | — | not changed | no Campaign → Flow, no entered / left audience events |

## Not created

- no campaign model, table, sender, runtime, scheduler or job
- no contact list, no `audience_members`, no recipient snapshot table (Enterprise `campaign_recipients` is Chatwoot's)
- no migration
- no change to how a Label campaign selects, deduplicates or sends
- no new analytics, permission or feature flag

## Semantics fixed here

| Question | Answer |
|---|---|
| When is an audience resolved? | Exactly when labels are: once, when the scheduler dispatches the campaign (`Campaign#trigger!` → sender). Before that, edits to the audience or to contacts change who will receive it; after the sender starts, the recipient list is fixed (Enterprise WhatsApp writes all `campaign_recipients` rows first; the other senders iterate one query) |
| A scheduled campaign | resolves at its scheduled dispatch (the next 5-minute scheduler run at or after `scheduled_at`), not at creation |
| A contact in a label and an audience | one recipient, one message |
| Unknown Commerce data | not a member (the audience's three-valued semantics); the count never counts it as zero |
| Audience deleted or unshared while referenced | refused at the API while the campaign is `active` or `processing`; a referenced audience that is somehow gone at dispatch fails the campaign before anything is sent (it stays `processing`, like any sender error today) |
