# Lynomia Automation: runtime, security and tenancy

What runs, what can fail and how, who may do what, and what never crosses an account. Everything here is Chatwoot's
existing runtime (`EventDispatcherJob`, `AutomationRuleListener`, `ActionService`, `WebhookJob`, Sidekiq) with the
additions named.

## Tenancy

| Path | Scope |
|---|---|
| Rules | `Current.account.automation_rules` (Chatwoot): another account's rule is 401 / 404 |
| Audience condition, save time | the id must be a shared contact audience of the rule's account (`audience_not_shared`) |
| Audience condition, run time | read from `account.custom_filters.contact.where(shared: true)`: an id that is not (any more) the account's shared audience makes the evaluation fail closed |
| Audience membership | the audience's filter as the account, restricted to the event's contact (`contacts.id = :id`, `contacts.account_id = account`) |
| Commerce conditions | `Audience::CommerceCondition` over the account's links and its active stores of enabled platforms |
| Store conditions | ids must be the account's stores (`invalid_store`), at save time; at run time the SQL joins only the account's links |
| Commerce events | dispatched with the link's contact; the listener loads that contact's account's rules only; conversation = the contact's latest **in that account** |
| `assign_team`, `assign_agent` | Chatwoot's `ActionService` checks: the team must be the account's, the agent a member with access |
| `send_email_to_team` | **patched**: `@account.teams.where(id:)` (was `Team.where(id:)`, any account) |
| Labels | label names, applied to the account's conversation |
| Webhook | the URL in the rule; the payload is the account's conversation |

A rule can be saved through the API with another account's team or agent id (Chatwoot does not validate action ids at
save time, and changing that would refuse rules Chatwoot accepts today); such an action is never applied: the run-time
checks above skip it. The E2E saves a rule with Demo B's team and agent on Demo A and shows Omar's conversation keeps
its team and assignee ([08](08-e2e.md)).

Tests: `spec/services/automation_rules/action_service_tenancy_spec.rb`, the foreign-audience and foreign-store
examples of the condition specs, `spec/controllers/api/v1/accounts/custom_filters_shared_spec.rb`, the E2E's API and Demo B checks ([08](08-e2e.md)).

## Permissions

No new permission. Chatwoot's `AutomationRulePolicy` (administrators only, for every rule action) applies to rules with
Lynomia triggers and conditions. Shared audiences: administrators share, change and delete; agents open them
([02](02-shared-audiences.md)). Commerce triggers need the account's Lynomia Commerce feature; the rule builder shows
them only then.

## Webhook and n8n: SSRF review

*Send Webhook Event* is Chatwoot's action: `WebhookJob` (queue `medium`) → `Webhooks::Trigger` → `SafeFetch`.

- **Destination**: `ssrf_filter` resolves the host and refuses private, loopback, link-local and metadata addresses
  (`127.0.0.0/8`, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `::1`, …), on every redirect too. The E2E shows a
  rule's webhook to `http://127.0.0.1:3901` refused on the worker as shipped, and the RSpec suite the same for
  `169.254.169.254`.
- **Self-hosted n8n on a private network**: Chatwoot's existing installation switch `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`
  opens private addresses for every SafeFetch use (webhooks, media downloads). Set it only where every administrator
  is trusted with the internal network; prefer a public n8n URL with an unguessable path.
- **Who sets the URL**: administrators only (rules policy). Agents cannot create or change rules.
- **Timeout**: `WEBHOOK_TIMEOUT` (default 5 s), open and read. A slow receiver holds one `medium` worker thread for at
  most that long.
- **Payload**: Chatwoot's conversation `webhook_data` (as every automation webhook today: it includes the contact's
  name, e-mail and phone, which is what n8n flows need) plus, on Commerce triggers, the event's ids, platform, order
  number and normalized statuses ([04](04-commerce-triggers.md)). Never a store credential, token or secret: the E2E
  checks the received body for the store key and secret.
- **Authenticity**: automation webhooks are not signed (Chatwoot sends no secret for them). A receiver should use an
  unguessable URL path and HTTPS. Signing them is a Chatwoot-wide change, out of scope.
- **Failure**: logged (`Exception: Invalid webhook URL …`), not retried.

## WhatsApp safety

- **Commerce triggers never message the customer**: `send_message` and `send_attachment` are not offered and are
  refused by the API (`no_customer_message`). A store event is not a customer message, and the contact's latest
  conversation may be on WhatsApp outside its 24-hour window.
- **Conversation triggers** keep Chatwoot's behaviour: automation `send_message` on a WhatsApp conversation goes through
  `Whatsapp::SendOnWhatsappService`; outside the 24-hour window a free-form message is marked failed ("outside messaging
  window") and nothing is sent. Automation has no template parameters, so it can never send a template or bypass the
  window. Lynomia's audience and Commerce conditions only decide whether a rule matches; they add no send path.
- **WhatsApp API and WhatsApp Business (coexistence)** inboxes are the same channel class for automation; nothing in
  this phase touches them (regression harnesses in [08](08-e2e.md)).

## Loop protection

Chatwoot's: every change an action makes is dispatched with `performed_by` = the rule, and the listener ignores
conversation and message events performed by a rule. A Commerce rule's label or note therefore never triggers another
rule. Commerce events are produced only by reads of a store, never by an automation action (no automation action writes
to a store), so no rule can cause a Commerce event. Chain depth stays 0. Spec: "never chains".

## Deduplication

- Transitions: computed under the summary row lock, from reads newer than the stored one only; cached and stale reads
  change nothing ([04](04-commerce-triggers.md)).
- Rule runs: one per rule and Commerce event id (`LYNOMIA::AUTOMATION::RUN::<rule>::<event id>`, Redis `SET NX`, 7 days).
- Conversation triggers: unchanged (Chatwoot has no per-event deduplication for immediate rules).

## Retries, by step

| Step | On failure | Retried? |
|---|---|---|
| Commerce read (`RefreshJob`, panel) | Commerce's own handling: last data marked stale, provider backoff | Commerce's rules; a stale read emits nothing |
| Transition + summary write | the transaction rolls back; nothing dispatched | the next read computes the same transition again |
| `EventDispatcherJob` | Sidekiq | up to 3 times (`config/sidekiq.yml`); Commerce rules already claimed are not run again (`duplicate`) |
| Condition evaluation | exception logged, rule does not match (fail closed) | no |
| Each action (`ActionService`) | exception captured (`ChatwootExceptionTracker`), next action runs | no |
| `add_label`, `remove_label`, `assign_*`, `change_priority`, status actions, `add_private_note` | database write in the job | no |
| `send_email_to_team`, `send_email_transcript` | `deliver_later` mail job, account e-mail rate limit | the mail job: Sidekiq retries |
| `send_webhook_event` | `WebhookJob`: logged | no |

A Commerce rule is therefore **at most once** per event: a worker killed between the claim and the actions loses that
run rather than risking a double label, note or webhook. The read that caused it is still recorded; the execution log
has no `executed` line for that rule and event.

## Execution log (no PII)

One structured line per Lynomia evaluation, through `Rails.logger` (the worker's log, collected like the rest):

```text
[Lynomia::Automation] {"event":"lynomia.automation.rule","account_id":1,"rule_id":1,"trigger":"commerce_order_paid",
"outcome":"executed","correlation_id":"88214:819dff4f981ad966e970cf18:commerce_order_paid:1790897007",
"duration_ms":759.7,"actions":["add_label","send_webhook_event"]}
```

| Field | |
|---|---|
| outcome | Commerce triggers: `executed`, `skipped` (conditions did not match), `duplicate` (event already ran this rule), `no_conversation`. Lynomia conditions on Chatwoot triggers: `matched`, `skipped` |
| correlation_id | the Commerce event id (link id, hashed order key, event, read time), or `conversation:<id>` |
| duration_ms | conditions and actions |
| actions | action names that ran |

Ids only: no contact name, e-mail, phone, order amount, address, token or payload. The E2E greps the lines for Omar's
name, e-mail and phone.

## Kill switch

`LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED` (installation config `InstallationConfig`, else the environment variable;
default on). Off:

- audience and Commerce conditions evaluate `FALSE`: rules using them stop matching (whatever the operator);
- Commerce events are not dispatched (transitions are still recorded, so turning it on again does not replay history);
- rules with Lynomia conditions or Commerce triggers cannot be saved (`extensions_disabled`);
- everything else is untouched: plain Chatwoot rules save and run as before (E2E check), shared audiences stay
  audiences, the Commerce and Audience features keep working.

Turning Lynomia Commerce off for an account has the same effect on its Commerce conditions and triggers.
