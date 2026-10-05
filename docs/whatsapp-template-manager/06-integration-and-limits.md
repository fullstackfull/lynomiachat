# 06 — Campaigns, flows, coexistence, several business accounts, and what fails how

How the rest of the product picks a template now, what is deliberately unchanged, and what a user sees when something
goes wrong.

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

## 3. What changed for flows

Nothing. `TemplateEditor.vue` already keyed on `name|language`, already filtered through the shared rule, and
`Flows::TemplateValidator` already refuses to publish a flow whose connected inbox cannot send the chosen template —
which is the "prevent an invalid publish rather than fail at run time" the brief asks for, and it predates this phase.
There is no flow-specific template store, and none was added.

## 4. Coexistence

A coexistence inbox (`provider_config['is_coexistence']`) is an ordinary `Channel::Whatsapp` with a WABA, so its
templates are managed by the same manager, mirrored into the same table and offered by the same rule. One manager, one
lifecycle; nothing in this phase branches on coexistence.

The one coexistence-specific rule in the product is older than this phase and untouched:
`Whatsapp::AuthenticationTemplateGuard` blocks an AUTHENTICATION-category template to a BSUID-only recipient. P3 does
not author authentication templates at all (`01-meta-api-contract.md §5`), so it cannot create one for that guard to
catch.

## 5. Several WhatsApp Business Accounts

Assumed throughout, never special-cased:

- a template row is keyed on `(account, WABA, name, lower(language))`, so the same template name on two business
  accounts is two independent rows and neither can overwrite the other;
- the manager reports every business account the account has connected, each with the inboxes on it and when its
  templates were last read, and a template says which inboxes can send it — because a template belongs to a business
  account and several inboxes can share one;
- a lifecycle call resolves a channel from the template's WABA
  (`provider_config->>'business_account_id'`, the query the webhook setup already uses), so the credentials used are
  always that business account's;
- the status webhook is routed by the WABA id in the payload, which is the only tenant key a template event carries.

Proven in the request specs: two business accounts under one account keep the same template name separate, each
reports its own inboxes, and both are listed with their own last-read time.

## 6. Errors: what a person sees, and what the log keeps

One error type, `Whatsapp::Templates::Error`, carrying a code, an optional safe reason and optional per-field details.
The UI translates the code; the server never builds an English sentence.

| Code | When | What the user is told |
|---|---|---|
| `INVALID_TEMPLATE` | the published WhatsApp rules are not met | the per-field problems, with "passing them is not approval" |
| `NAME_TAKEN` | Meta's code 100 / subcode 2388024 | this account already has that name in that language |
| `NOT_EDITABLE`, `CATEGORY_NOT_EDITABLE`, `NOT_DELETABLE`, `NOT_SUBMITTABLE` | Meta's lifecycle rules | what Meta allows, in words |
| `ALREADY_AT_META`, `SUBMIT_IN_FLIGHT` | a second submit | that it is already there, or already going |
| `CSAT_MANAGED_ELSEWHERE` | a survey template | where it is managed instead |
| `NO_WHATSAPP_INBOX` | the WABA has no connected channel left | that the inbox is gone |
| `AUTH_INVALID` | Graph code 190 | reconnect the inbox |
| `RATE_LIMITED` | HTTP 429 | try again shortly |
| `META_UNAVAILABLE` | HTTP 5xx | try again shortly |
| `META_REJECTED_REQUEST` | anything else | Meta's own `error_user_msg` when it wrote one, and nothing invented when it did not |

**What never reaches a message:** an access token, a request header, a raw Graph body. The full response and its
`fbtrace_id` go to `Rails.logger` instead, which is also where a developer looks when a user reports a code.

A failed submit is also *kept*: the code and reason are stored on the draft, so reloading the page still explains why,
instead of leaving a draft that looks half-submitted for no reason.

## 7. Retries, and the absence of a polling loop

- **No new job, scheduler or queue.** Status moves on the sync that already runs (at most every three hours per
  channel, 25 channels per five-minute tick) and on the webhook.
- **No per-template polling and no status-watching loop.** Nothing waits on Meta.
- **Transport retries** stay with Sidekiq and `ApplicationJob`, as for every other job in this product.
- A submit, edit or delete is a user action in a request: it either succeeds or returns a code the user can act on.
  Nothing retries behind their back, because a silent retry of a template create is how duplicates happen.
