# Lynomia Flow Builder: security and tenancy

## Who can do what

| Action | Who |
|---|---|
| list, create, edit, save, validate, publish, disable, delete flows; Test Mode; session inspector | account administrators (`AgentBotPolicy#update?`, Chatwoot's own bot permission), on accounts with `lynomia_flow_builder` |
| connect a flow to an inbox | administrators, through Chatwoot's `POST /inboxes/:id/set_agent_bot` (account-scoped bot lookup) |
| see what a flow said | everyone who can see the conversation: the flow's messages are ordinary Chatwoot messages |

Agents get `401` from the flows API; other accounts' flows are `404` (looked up in `Current.account.agent_bots.flow`).

## Switches

| Switch | Effect |
|---|---|
| `lynomia_flow_builder` (account feature, `config/features.yml`, independent of Commerce) | off: the builder and API refuse; sessions do not start or advance (conversations go to humans) |
| `LYNOMIA_FLOW_BUILDER_ENABLED` (installation config, else ENV, default on) | the emergency kill switch: off, no session starts or advances anywhere; conversations go to humans the next time the flow would act; WhatsApp, Automation and webhook bots carry on |

## Tenant isolation

- `FlowVersion` and `FlowSession` validate that the bot, version, conversation and account are one account.
- Every id a node names — label, team, agent, custom attribute, shared audience, order store — must be the account's at
  publish (`unknown_label`, `unknown_team`, `unknown_agent`, `unknown_attribute`, `invalid_conditions`); at runtime the
  actions go through `ActionService`, which checks again (inbox members, account teams), and deleted references are skipped
  or follow `failed`.
- Commerce lookups read only the conversation's own contact's matched store customers; by order number, only orders of
  that customer are kept (`Commerce::OrderSearch` `owners`): a guessed number of another customer's order is not found
  (WhatsApp E2E A6).
- Personal audiences are refused: only shared audiences (Automation's rule).
- WhatsApp templates are looked up only in the account's own inboxes (`Flows::TemplateValidator`): a template name that
  exists only in another account's channel is `template_not_found`; at runtime only the conversation's inbox is read.
- Connecting a flow to an inbox is Chatwoot's `set_agent_bot`, which finds the bot among the account's (and global)
  bots only: another account's flow bot is 404.
- A session only ever advances on its own conversation: a message or a timer of another conversation (another session id
  or token) is ignored (`Flows::Runner#messages` checks the trigger's conversation, `#wake` the session's).

## Input never becomes code

- Variables: an allow-list, no Liquid tags or filters (`{%` refused at publish). Flow values (`flow.*`) are substituted by
  the flow with `{{ }}` `{% %}` removed before Chatwoot renders its own drops, so a customer's answer or a store's data
  cannot become a template (`spec/services/flows/runner_security_spec.rb`).
- Conditions are Automation's validated conditions, evaluated by Automation's service; there is no expression language.
- Custom attribute patterns compile with a 0.1 s time limit (ReDoS-safe); numbers, dates, links and list values are cast
  against the definition.
- Graph size: 300 nodes, 900 edges, 512 KB; unknown node types and fields are refused.

## Webhooks

`SafeFetch` (Chatwoot's): private and loopback addresses refused unless the installation sets
`SAFE_FETCH_ALLOW_PRIVATE_NETWORK` (self-hosted n8n), with Chatwoot's webhook timeouts. Each delivery is signed with
the flow bot's own secret (rotate with Chatwoot's reset-secret). The payload holds the conversation's webhook data and the
run's values, never the secret, and **nothing the endpoint answers enters the flow** (no response-to-variable in Phase 1).

## Customers and humans first

- Blocked contacts never enter a flow (`flow_unavailable`).
- A human reply or assignment ends the bot phase at once; the flow never talks over an agent.
- Every failure hands the conversation to humans; nothing stays silently pending.
- WhatsApp's 24-hour window is respected (`window_closed`); after it only an approved template goes out, through
  Chatwoot's template path, and a free-form message is never turned into one. A message Meta rejects hands the
  conversation to humans (`message_rejected`).

## Audit and privacy

Named audit entries: `flow.created / updated / published / disabled / deleted`, `flow.execution.handed_off / failed`
(Enterprise audit log, with ids and codes only). Log lines (`[Lynomia::Flow]`) carry ids, node types, results and timings:
no phone number, message text, answer or token. The session inspector shows states and node ids, never the context's
values. Test Mode rolls everything back and keeps no test conversation.

## Tests

`spec/services/flows/runner_security_spec.rb` (template injection, catastrophic regex, size limits, cross-account
versions and sessions, another conversation's message or timer, webhook payload and variable allow-list), `spec/controllers/api/v1/accounts/flows_controller_spec.rb`
(roles, feature, foreign flows, another account's flow on an inbox, no secret or token in the flow JSON, Test Mode leaves
nothing), `spec/services/flows/template_validator_spec.rb` (another account's template, every connected inbox, missing
values, unsafe values), `spec/services/flows/nodes/send_template_spec.rb` (window, rejected, deleted / disabled /
language / authentication templates), `spec/services/flows/graph_validator_spec.rb` (another
account's labels, teams, agents, attributes and audiences), `spec/services/flows/nodes/commerce_lookup_spec.rb` (another
customer's order), and the WhatsApp E2E tenancy checks ([10](10-e2e.md)).
