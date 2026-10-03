# Lynomia Campaigns: audiences in use

A campaign stores only an audience's id ([02](02-recipients.md)), so deleting or unsharing an audience a campaign still
needs would leave that campaign with nothing to resolve. The guard Automation already had for shared audiences
(docs/automation/02-shared-audiences.md) now counts campaigns too. No new mechanism.

## 1. What counts as "used"

`Audience::Usage` (`custom/app/services/audience/usage.rb`):

| | References the audience through | Counted |
|---|---|---|
| `rules(audience)` | an automation rule's `contact_audience` condition | every rule, active or not (unchanged) |
| `campaigns(audience)` | an `{ "type": "Audience", "id": … }` entry of a one-off campaign's `audience` (jsonb containment, in the audience's account) | campaigns **still to send**: `active` (scheduled) and `processing` (sending) |

## 2. Release

| Campaign state | Holds the audience? | Why |
|---|---|---|
| `active` (scheduled) | yes | it will resolve the audience at dispatch |
| `processing` | yes | it is resolving / sending now |
| `completed` | no | its recipients were resolved when it was sent; Enterprise's `campaign_recipients` keep who received it |
| deleted | no | the row is gone. Deleting a scheduled campaign is how Chatwoot cancels one |
| cancelled | — | Chatwoot has no cancelled status, and `enabled` is not read for one-off campaigns |

## 3. What is refused

`Custom::Api::V1::Accounts::CustomFiltersController` (the saved filters API the Contacts screen uses), for a shared
audience in use:

- `DELETE /custom_filters/:id` → 422
- `PATCH /custom_filters/:id` with `shared: false` → 422
- editing its conditions stays allowed: that is how a team changes who a scheduled campaign reaches (the note below says
  so)

Messages (`config/locales/en.yml`, `ar.yml`), one sentence per kind of user, joined when both apply:

- `This audience is used by %{count} automation rules. Remove it from those rules first.` (unchanged)
- `This audience is used by %{count} campaigns that have not been sent yet. Delete those campaigns or wait until they are sent first.`

## 4. What is reported

The audience JSON (`app/views/api/v1/models/_custom_filter.json.jbuilder`) carries, for shared audiences:

| Field | |
|---|---|
| `automation_rules_count`, `active_automation_rules_count` | unchanged |
| `campaigns_count` | campaigns still to send that use it |

The contacts filter shows administrators, on a shared audience in use:
"This shared audience is used by {rules} active automation rules and {campaigns} campaigns not yet sent. Saving changes
what they match at once." (en, ar). The automation E2E's check on "used by 2 active automation rules" still reads.

## 5. Account isolation and races

- Usage is counted inside the audience's account only (`custom_filter.account.campaigns`); a campaign of another
  account that somehow named the id never holds it (request spec "counts only the campaigns of the audience's own
  account").
- A campaign created in the same instant an audience is deleted can pass validation and then find the audience gone at
  dispatch: it fails loudly before sending ([02 §7](02-recipients.md)). No lock was added for this window.
