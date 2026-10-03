# Lynomia Campaigns: preview and one message per contact

## 1. The preview endpoint

```
POST /api/v1/accounts/:account_id/campaigns/audience_preview
{ "audience": [{ "type": "Label", "id": 12 }, { "type": "Audience", "id": 7 }] }
→ 200 { "count": 4 }
```

`Api::V1::Accounts::Campaigns::AudiencePreviewsController` (`custom/app/controllers/…`, route file
`config/routes/campaign_audiences.rb`):

| | |
|---|---|
| Permission | `CampaignPolicy#create?`: whoever may create campaigns (administrators). Agents and anonymous callers get 401 |
| Input | `audience` required and non-empty (missing or `[]` → 422); `Audience` entries must be shared contact audiences of the account (422 otherwise, the same check as the campaign) |
| What it counts | an unsaved one-off campaign of the account with that audience: `campaign.audience_contacts.count`, the **same relation the senders iterate** at dispatch |
| Output | `count` only. No contact list, ids or sample: a bounded sample would duplicate what opening the audience in Contacts already shows, with its own permissions |
| Provider calls | none (Commerce conditions read Lynomia's stored summaries; request spec and E2E assert zero outbound HTTP) |

The count is exact for now; the campaign resolves again when it is sent ([02 §5](02-recipients.md)). A contact without a
phone number is counted (it is a member) and then skipped by the channel check at send time; the E2E shows both (Ali).

## 2. Each contact once

| Case | Count | Sends |
|---|---|---|
| contact in two labels | 1 | 1 (Chatwoot's `EXISTS` per contact, unchanged) |
| contact in a label and an audience | 1 | 1 |
| contact in two audiences | 1 | 1 |
| contact in neither | 0 | 0 |
| contact of another account matching the conditions | 0 | 0 |

The union is a disjunction of `contacts.id IN (subquery)` over one `contacts` scan ([02 §4](02-recipients.md)), so the
database returns each contact once; nothing is deduplicated in Ruby.

Tests: `spec/models/campaign_audience_spec.rb` (union, SMS and WhatsApp sends once each),
`spec/controllers/api/v1/accounts/campaigns_audience_spec.rb` (counts 2 / 2 / 3 / 4 for label, audience, both, both + a
second audience; the preview equals what the campaign resolves), WhatsApp E2E checks 2 and 6.

## 3. Unknown is not zero

- A Commerce condition never matches a contact whose figures are unknown (the audience's own semantics).
- The UI shows a failed count as unknown, never `0` ([04 §2](04-ui.md)).
- A missing audience at dispatch fails the campaign rather than sending to an empty or partial list
  ([02 §7](02-recipients.md)).
