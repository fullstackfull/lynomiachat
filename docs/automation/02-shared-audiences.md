# Lynomia Automation: shared audiences

A Lynomia audience is a Chatwoot saved contact filter (`custom_filters`, `filter_type: contact`; see
[Audience 00–03](../audience/)). Until this phase every saved filter belonged to the user who saved it. Automation rules
belong to the account, so a rule may only point at an audience that also belongs to the account: a **shared audience**.
Shared is a flag on the same row, not a new model.

```text
custom_filters
  shared   boolean, not null, default false        (20261003100000_add_shared_to_custom_filters)
  user_id  now nullable: a shared filter keeps working when its creator is deleted
```

## Personal and shared

| | Personal (default) | Shared |
|---|---|---|
| Who sees it | its creator | every member of the account |
| Who changes or deletes it | its creator | administrators |
| Usable in automation rules | no | yes (`Contact audience is in / is not in`) |
| When its creator is deleted | deleted with the user (Chatwoot's existing `dependent: :destroy_async`) | stays, `user_id` set to null |
| Filter type | contact or conversation folder | contact only |

- **Sharing is explicit.** An administrator ticks *Share with the whole account* when saving an audience (Contacts →
  Filter → Save audience), or sends `shared: true`. Nothing converts a personal audience automatically, and a rule
  that names a personal audience is refused (`audience_not_shared`, 422).
- **Agents** see shared audiences in Contacts → Audiences marked *Name · Shared*, open them and adjust the filter for
  themselves (*Apply filters*), but get no save, rename or delete for them. The API refuses the same (401): an agent
  cannot share, change or delete a shared audience.
- **Administrators** see in the filter panel how many active rules use the shared audience they are editing
  ("This shared audience is used by N active automation rules. Saving changes what they match at once."). A rule stores
  only the audience id: editing the audience changes what every rule using it matches, immediately.

## Dependency blocking

`Audience::Usage.rules(custom_filter)` finds the account's rules (active or not) whose conditions contain a
`contact_audience` condition naming the audience (jsonb containment `conditions @> [{"attribute_key":
"contact_audience"}]`, then the id in `values`).

- Deleting a shared audience that rules use → **422** `This audience is used by X automation rules. Remove it from those
  rules first.` The dashboard shows the same message.
- Making it personal (`shared: false`) while rules use it → the same 422.
- Deleting or unsharing an unused shared audience works as before.

A rule whose audience disappears anyway (deleted through the console) stops matching: the condition reads the audience
from the account's shared audiences and finds none (fail closed, see [03](03-audience-and-commerce-conditions.md)).

## API

`/api/v1/accounts/:id/custom_filters` (Chatwoot's existing endpoint):

- `GET` (index, show): the user's own filters plus the account's shared contact filters (`CustomFilter.visible_to`).
- `POST` / `PATCH`: `custom_filter[shared]` accepted; sharing, and any change to a shared filter, needs an
  administrator.
- `DELETE`: a shared filter needs an administrator and must be unused.
- Response: `shared`, and for shared filters `automation_rules_count` and `active_automation_rules_count`.

Everything goes through `Current.account.custom_filters`: an id of another account is 404 there, and is refused as a
rule condition (`audience_not_shared`).

## Audit

Contact filters are already audited where the audit log exists (`Custom::Audit::CustomFilter`, Audience phase,
Enterprise `audited`): sharing, unsharing, edits and deletes of an audience are recorded with their author, the
`shared` column among the audited changes, and listed on the account's audit log page as audience changes.

## Files

| Change | File |
|---|---|
| column, nullable user | `custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb`, `db/schema.rb` |
| validations, `visible_to` | `custom/app/models/custom/custom_filter.rb` (prepended through `CustomFilter.prepend_mod_with`) |
| `belongs_to :user, optional: true` | `app/models/custom_filter.rb` |
| creator deletion | `custom/app/models/custom/concerns/user.rb` |
| permissions, dependency blocking | `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb` |
| usage | `custom/app/services/audience/usage.rb` |
| response | `app/views/api/v1/models/_custom_filter.json.jbuilder` |
| UI | `CreateSegmentDialog.vue` (share checkbox), `Sidebar.vue` (· Shared), `ContactListHeaderWrapper.vue` / `ContactHeader.vue` (agents: no save / delete), `ContactsFilter.vue` (shared and in-use notes) |
| strings | `contact.json`, `contactFilters.json`, `settings.json`, `auditLogs.json` (en, ar); `config/locales/{en,ar}.yml` `errors.custom_filters.used_by_automation` |
| tests | `spec/controllers/api/v1/accounts/custom_filters_shared_spec.rb`; E2E [08](08-e2e.md) |
