# Lynomia Campaigns: shared audiences as recipients

A one-off campaign (SMS, Twilio SMS, WhatsApp) selects its recipients with labels, and now also with the account's
shared audiences. Everything else about the campaign is Chatwoot's ([00](00-existing-system-discovery.md)).

## 1. What a campaign stores

`campaigns.audience`, the existing jsonb column, in its existing `{ type, id }` shape:

```json
[
  { "type": "Label", "id": 12 },
  { "type": "Audience", "id": 7 }
]
```

`Audience` entries reference a shared contact audience (`custom_filters.id`, `filter_type: contact`, `shared: true`). The
campaign keeps the reference, never a copy of the conditions: editing the audience changes who a scheduled campaign
will reach. No column, table or migration was added.

## 2. Validation (create and update, 422)

`Custom::CampaignAudience#audiences_shared_in_account?` (prepended to `Campaign`), as a model validation:

| Entry | Accepted when |
|---|---|
| `Audience` | the campaign is one-off, the id is an integer, and it names a **shared contact** audience **of the campaign's account** |
| `Label` | as before: not validated, resolved inside the account at send time (a foreign or deleted label matches nobody) |

Refused (422, `errors.campaigns.audience_not_shared`): a personal filter, a conversation folder, another account's
audience, a string id, an `Audience` entry on a live chat campaign. The same check guards the preview endpoint
([05](05-preview-and-dedup.md)). Permissions are Chatwoot's `CampaignPolicy`: administrators only.

## 3. Resolution

One method resolves recipients for every sender: `Campaign#audience_contacts`.

- **Chatwoot (OSS)**, `app/models/campaign.rb`: the label relation the four senders used to build themselves,
  `account.contacts.tagged_with(<label titles>, any: true)`.
- **Lynomia**, `custom/app/models/custom/campaign_audience.rb`: when the campaign lists audiences, the union of the label
  relation and each audience's members:

  ```sql
  SELECT contacts.* FROM contacts
  WHERE contacts.account_id = :account
    AND (contacts.id IN (<label contacts>) OR contacts.id IN (<audience 1 members>) OR contacts.id IN (<audience 2 members>))
  ```

  Each audience's members come from `CustomFilter#members`: its saved `query.payload` through
  `Contacts::FilterService#relation`, evaluated as the account (no member's inbox scope). Automation's audience
  condition uses the same method.

The senders (`Whatsapp::OneoffCampaignService` + Enterprise's prepended module, `Sms::OneoffSmsCampaignService`,
`Twilio::OneoffSmsCampaignService`) call `campaign.audience_contacts` where they used to build the label relation. Their
per-contact checks, the template path and the provider calls are unchanged.

A label-only campaign returns exactly the relation it always did (`spec/models/campaign_audience_spec.rb` compares the
SQL).

## 4. Deduplication

A contact is one row of `contacts` whatever selects it: two labels, a label and an audience, three audiences. The union
is `contacts.id IN (…) OR contacts.id IN (…)` over the account's contacts, so the relation has each contact once and the
sender sends once. Enterprise's `campaign_recipients` unique `(campaign_id, contact_id)` stays the backstop for a retried
job. Proven by `spec/models/campaign_audience_spec.rb`, the preview request spec, and E2E check 6 (Layla, in the label and
the audience, receives one template).

## 5. When recipients are resolved

| Moment | What happens to the audience |
|---|---|
| Campaign created / edited | the reference is validated; nothing is resolved or stored |
| Preview | counted now ([05](05-preview-and-dedup.md)); a preview, not a promise |
| Before dispatch | edits to the audience's conditions and to contacts change who will receive it |
| Dispatch | the scheduler (`TriggerScheduledItemsJob`, every 5 minutes) picks the campaign at or after `scheduled_at`; `Campaign#trigger!` locks it to `processing`; the sender resolves labels and audiences **once**, in the same moment |
| During sending | the list is fixed: Enterprise WhatsApp writes every `campaign_recipients` row first, then sends; the SMS senders iterate one query |
| Per job | one job per campaign; no per-batch re-resolution with different results |

This is when labels were always resolved: an audience behaves like a label that holds a filter instead of a tag.

**Scheduled campaigns** are the normal case (the forms require a time). A campaign scheduled for next week reaches the
audience's members of next week. A campaign whose schedule passed more than 3 days before the scheduler sees it is
never picked (Chatwoot's window), whatever its recipients.

## 6. Eligibility, exclusions, compliance (unchanged)

| | |
|---|---|
| Channel eligibility | per sender, per contact, whatever selected it: SMS needs a phone number; WhatsApp a phone number or one BSUID identity on the inbox; template params must resolve; the authentication-template guard applies |
| WhatsApp templates | the form offers the inbox's approved templates; `Whatsapp::TemplateProcessorService` builds the components |
| Blocked contacts, opt-out | Chatwoot's campaign senders exclude neither, and there is no opt-out model. Unchanged: an audience can include **Blocked = false** like any contact filter. Adding an exclusion only for audiences would make the same contact behave differently by source |
| Unknown Commerce data | a contact whose Commerce figures are unknown is not a member of a Commerce condition; it is never counted as zero (docs/audience/03 §6) |

## 7. A referenced audience that is gone at dispatch

The API refuses to delete or unshare an audience a campaign still to send uses ([03](03-audience-dependency.md)). If one
is gone anyway (removed outside the API), `audience_contacts` raises `ActiveRecord::RecordNotFound` before the first
send: the campaign stays `processing` with the error in Sidekiq, like any sender error today. Nothing is sent to a guessed
or partial list.

## 8. Code

| File | |
|---|---|
| `app/models/campaign.rb` | `audience_contacts` (labels); `Campaign.prepend_mod_with('CampaignAudience')` |
| `custom/app/models/custom/campaign_audience.rb` | validation, union with shared audiences |
| `custom/app/models/custom/custom_filter.rb` | `CustomFilter#members` |
| `app/services/{whatsapp,sms,twilio}/…oneoff…_service.rb`, `enterprise/…/oneoff_campaign_service.rb` | read `campaign.audience_contacts` |
| `custom/app/services/automation/lynomia_condition.rb` | `member?` reads `audience.members` (same query as before) |
