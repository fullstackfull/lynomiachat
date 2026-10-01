# Lynomia Audience: Automation and Campaign integration contract

**Design only.** Phase 1 changes nothing in automation rules or campaigns. This document fixes what Phase 2 can rely on
and recommends how to build on it.

## 1. What is stable today (the contract)

| | Contract |
|---|---|
| Identity | an audience is a `CustomFilter` with `filter_type: contact`, identified by its id, in one account |
| Definition | `query.payload`: Chatwoot conditions `{ attribute_key, filter_operator, values, query_operator }`, keys and operators as in [02 §2](02-audience-architecture.md) |
| Evaluation | `Contacts::FilterService.new(account, user, { payload: query['payload'] }).perform[:contacts]`: an `ActiveRecord::Relation` of the account's contacts, SQL only, no provider call |
| Semantics | three-valued for Commerce: a contact is a member only when its data proves it; unknown is never member through a zero ([03 §6](03-commerce-query-model.md)) |
| Conversation scope | conversation conditions see the conversations the evaluating user may see |
| Validation | invalid conditions raise `CustomExceptions::CustomFilter::*` before any SQL |
| Freshness hook | every new order read passes through `Commerce::ContactMetric.record(link, result)`; it changes the row only when figures come from a newer read |
| Guard | Audience keys are **not** in `lib/filters/filter_keys.yml`, so automation rules cannot save or evaluate them yet |

## 2. Conditions: "contact is / is not in audience"

Automation conditions use the same condition shape, so the new condition is one more key:

```json
{ "attribute_key": "contact_audience", "filter_operator": "equal_to", "values": [12], "query_operator": null }
```

- `equal_to [ids]`: the conversation's contact is in at least one of these audiences; `not_equal_to [ids]`: in none.
- Evaluation for one conversation is the audience's SQL restricted to that contact:
  `Contacts::FilterService…perform[:contacts].where(id: conversation.contact_id).exists?`. It reads only that contact's
  links, summaries and conversations through the same indexes as the per-contact subplan in [05](05-performance.md), so
  it costs milliseconds and never calls a store.
- In `AutomationRules::ConditionsFilterService` it becomes `contacts.id IN (<audience SQL>)` (or the `exists?` above when
  conditions are evaluated in Ruby), joined into the rule's existing chain with its `query_operator`.
- `AutomationRules::ConditionValidationService` must accept `contact_audience` **explicitly** and check that every id is
  a contact audience of the rule's account. It must not be added under `contacts:` in `filter_keys.yml`, which renders
  keys as `contacts.<column>`.
- "Not in audience" means "not proven to be in it": a linked contact whose orders were never read is **not in**
  "visible spend (SAR) > 1000". Rules that act on "not in audience" should say so in their UI.

## 3. Ownership: account-level audiences first

Chatwoot saved filters belong to one user, and conversation conditions are scoped by that user's permissions. Automation
rules belong to the account and run without a user. Before automation or campaigns can reference audiences, Phase 2
needs **account-level audiences**:

- an administrator-managed "shared with the account" flag on `CustomFilter` (contact type only), listed for every agent;
- automation and campaigns may reference shared audiences only;
- they are evaluated with account scope (an administrator-equivalent evaluator for conversation conditions), stated in
  the UI;
- private audiences keep today's behaviour.

## 4. Events: "entered audience" / "left audience"

Not built, and no audience membership is materialized today. Recommendation:

1. **Watch only what is used.** Keep a membership snapshot only for shared audiences referenced by an active rule with
   an entered/left event: `audience_memberships (account_id, custom_filter_id, contact_id, entered_at)`, unique on
   `(custom_filter_id, contact_id)`. Every other audience stays purely dynamic.
2. **Re-evaluate one contact, not the audience,** when something about that contact can change membership, using the
   events and hooks that already exist:

   | Change | Existing signal |
   |---|---|
   | contact attributes, labels | `contact.updated` (EventDispatcher) |
   | conversation status, assignee, team, priority, labels, new conversation | `conversation.created`, `conversation.updated`, `conversation.status_changed` |
   | Commerce figures | `Commerce::ContactMetric.record` when it writes (new read: panel, webhook refresh, action completion) |
   | link created, suppressed, re-pointed, deleted | `Commerce::CustomerLink` callbacks (the summary drop already lives there) |

   A listener (for example `AudienceMembershipListener`) computes membership of that contact for the watched audiences
   (one indexed `exists?` each), diffs it with the snapshot, writes the change, and dispatches `contact.entered_audience`
   / `contact.left_audience` through Chatwoot's existing dispatcher for the automation listener. Bursts coalesce per
   contact, as `Commerce::RefreshJob` already does.
3. **Time and account-wide changes** (a `days_before` or date condition crossing midnight, a store disconnected, a provider
   switched off for the installation) re-evaluate the watched audiences of that account in one batch job: the same SQL
   as a preview, diffed against the snapshot.
4. **Idempotent and quiet:** events only on real transitions, never on re-evaluation that changes nothing; no audit row
   per membership change.
5. **Open point for Phase 2:** automation actions act on a conversation (message, assign, label). A contact-level event
   needs a rule for which conversation it acts on (latest open one, or a new outbound one), or contact-level actions only.

## 5. Campaigns: minimum integration

Today campaigns do not read segments: `Campaign.audience` holds `[{ type: 'Label', id }]`, resolved at send time by
`Sms::OneoffSmsCampaignService`, `Twilio::OneoffSmsCampaignService` and `Whatsapp::OneoffCampaignService`
(`contacts.tagged_with(labels, any: true)`); Enterprise WhatsApp writes `campaign_recipients` while sending. Minimum
change, later:

- accept `{ type: 'Audience', id: <shared contact audience id> }` entries in `Campaign.audience`, validated against the
  account;
- at send time, resolve them with the audience's relation (dynamic membership at that moment), union with label
  recipients, keep each channel's own eligibility filter (phone number, opt-out), iterate in batches
  (`find_each`), never load the list in the browser;
- record recipients through the existing `campaign_recipients` path;
- show the audience's current count when the campaign is created (the existing preview).

No bulk campaign change was made in this phase.

## 6. Recommended Phase 2 order

1. Shared (account-level) contact audiences, administrator-managed (§3).
2. Automation condition `contact_audience` equal_to / not_equal_to, validated explicitly, evaluated per contact (§2).
3. Campaign audience source for one-off campaigns (§5).
4. Only then entered/left events, with snapshots limited to watched audiences (§4).
