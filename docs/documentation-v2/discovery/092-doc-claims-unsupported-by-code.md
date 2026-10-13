---
agent: 092
scope: Hunt documentation claims unsupported by code, across all 126 corpus files
confidence: high
---

## What you attacked

I treated the corpus as a set of falsifiable assertions and tried to falsify each one against the code. The
corpus is 126 files (63 EN + 63 AR, `custom/db/documentation/{en,ar}/<section>/*.md`). An exhaustive pass over
every sentence is not possible in one agent, so I prioritised by failure mode, in this order:

1. **Negative and absolute claims.** `grep -rniE "there is no |there are no |is not recorded|only administrator|
   administrators only|never |cannot|automatic"` over the EN corpus returns 519 candidate lines. These are where
   the corpus is most often stale, because a negative claim is true on the day it is written and false the day
   the product gains the capability — and nothing in the pipeline re-checks it.
2. **Cross-area claims.** A claim about area A made inside an article owned by area B. Each feature agent read
   one area, so these are the claims nobody was looking at. Six of my strongest findings are of this shape.
3. **Numeric claims** — defaults, thresholds, page sizes, timeouts, counts — as the "implemented differently"
   direction.
4. **Self-contradiction inside one article**, which is a reliable smell that one half was written against code
   and the other against an older design record.

I verified a sample of twelve existing ledger entries to decide whether `_ARBITRATION.md` is trustworthy, then
spent the rest of the budget on claims no agent had an area for. The sample result is in §2.0, and two ledger
entries did not reproduce as worded.

Everything below cites both sides. Where a claim appears in EN and AR I give both line numbers, because a corpus
writer has to fix two files, not one.

---

## Refutations

### 2.0 Verification of the existing ledger

Twelve entries tested. **Ten reproduced exactly. Two did not reproduce as worded.**

| Entry | Verdict | Evidence re-checked |
|---|---|---|
| DC-03 (contact merge is audited) | reproduced | `custom/app/actions/custom/contact_merge_action.rb:26,74-80` writes `comment: 'contact.merged'` with `associated: @account`; `custom/app/models/custom/audit_log.rb:26` serves exactly that scope |
| DC-05 (balanced assignment) | reproduced | `app/models/assignment_policy.rb:38` is `enum assignment_order: { round_robin: 0 }` — no `balanced` member; `settings/assignmentPolicy/constants.js:3` exports `BALANCED = 'balanced'` |
| DC-17 (inbox health is not admin-only) | reproduced | `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:5` skips `check_authorization` for `:health`; `inboxes_controller.rb:87-89` `fetch_inbox` then does `authorize @inbox, :show?` (membership). `InboxPolicy#health?` at `app/policies/inbox_policy.rb:79-81` is dead code |
| DC-19 (six vs seven vs eight permissions) | reproduced | article says six (`roles-and-permissions.md:3,28,92`); `app/javascript/dashboard/constants/permissions.js:4-12` offers seven; `custom/app/models/custom_role.rb:19-28` holds eight |
| DC-22 (muting still creates the conversation) | reproduced | `app/models/conversation.rb:308` `self.status = :resolved and return if contact.blocked?`; `app/models/concerns/conversation_mute_helpers.rb:12-17` `unmute!` clears the flag and never reopens |
| DC-24 (undefined-variable confirm dialog) | reproduced | `ReplyBox.vue:936-947,1525-1526` blocks the send behind `CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES` |
| PD-08 (balanced is a 500) | reproduced | as DC-05; nothing rescues `ArgumentError` on the enum write |
| PD-10 (`report_manage` gates nothing) | reproduced | `app/policies/report_policy.rb:2-4` administrator-only, no overlay exists (`find -name '*report_policy*'` returns the OSS file and its spec only); `analytics.routes.js:18` admits `report_manage` and its own comment at `:4-6` documents the mismatch |
| PD-11 (`knowledge_base_manage` grants nothing) | reproduced; **already corrected by 096** — see R11 | `custom/app/policies/custom/portal_policy.rb:25-34` is unconditionally false for authoring; the permission opens the global-search Articles tab only where `help_center` is enabled, and `config/features.yml:44-46` ships it off |
| PD-36 (bulk actions unauthorized for conversations) | reproduced | `app/controllers/api/v1/accounts/bulk_actions_controller.rb:12-20`: the `'Contact'` branch calls `check_authorization_for_contact_action`, the `'Conversation'` branch calls nothing |
| XA-06 (fair-distribution defaults disagree) | reproduced | `app/services/auto_assignment/rate_limiter.rb:21,25` falls back to 5 per 5 minutes; `app/models/assignment_policy.rb:11-12` column defaults are 100 per 3600 s |
| **DC-06** | **NOT reproduced as worded** | see below |
| **PD-34** | reproduced, **evidence miscited** | see below |

**DC-06 is wrong as written.** The ledger says *"the analytics routes are explicitly not feature-gated"*. They
are. `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js:64-71` sets
`featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS` on `campaigns_whatsapp_analytics`, that constant is
`'whatsapp_campaign'` (`featureFlags.js:9`), and `config/features.yml:204-206` ships it `enabled: false`. The
corpus claim is still wrong, but for a different and more useful reason: the per-campaign results view is gated
by **the same flag as the WhatsApp campaign list itself**, and the `View analytics` button carries no gate of its
own beyond channel type and status (`CampaignList.vue:37-40`, `CampaignCard.vue:152-161`). So no installation
that can create a WhatsApp campaign can lack the results view, and the hedge "not available on every
installation" (`whatsapp-campaigns.md:145`) sends a reader looking for a switch that does not exist. **Agent 000
should re-word DC-06**, because a writer who acts on the current wording will write that analytics is never
gated, which is also false.

**PD-34's evidence is miscited.** The finding reproduces, but neither cited location is the guard. There is no
`upload_controller.rb` under `platform_support/`; the file is `app/controllers/api/v1/accounts/upload_controller.rb:1`,
and `custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:29-31` is the *exemption*, i.e.
the opposite side of the check. The actual guard is `custom/app/controllers/billing/access_guard.rb:21-22,50-52`,
where `billing_exempt?` is `is_a?(Api::V1::Accounts::BillingController)` — and `UploadController` is neither that
nor a `PlatformSupport::BaseController` subclass. Corrected citation matters here because the fix is one method
in `access_guard.rb`, not anything in the Platform Support tree. See R9 for the corpus consequence.

My conclusion on the ledger: **trustworthy.** Ten of twelve exact, one substantively right with wrong wording,
one right with wrong citations. Nothing I sampled was fabricated or unreproducible.

---

### R1 — "There is no account-wide timezone" · `blocker`-adjacent `major` · corpus fix **and** product defect

> `en/getting-started/set-up-your-account.md:50` — "**There is no account-wide timezone in Lynomia Chat**, and
> this is worth knowing before you plan around one."
> `en/getting-started/set-up-your-account.md:53` (table) — "| Reports | the timezone of the browser you are
> looking at them in |"
> `en/getting-started/set-up-your-account.md:79` — "There is no single account timezone. Business hours are per
> channel, and **reports follow your browser**."
> AR: `ar/getting-started/set-up-your-account.md:53`, and the article's own `description:3` and
> `seo_description:6` both promise to tell the reader "where the timezone that actually matters is set".

There is an account-wide timezone. `app/models/account.rb:59` declares
`store_accessor :settings, :reporting_timezone`, validated at `:52` and `:217-220`.

Every screen under **Analytics** interprets its date range and bucket boundaries in it:
`custom/app/services/analytics/date_range.rb:89-96` resolves `@account.reporting_timezone`, falling back to
`FALLBACK_TIMEZONE = 'UTC'` (`:27`), and `custom/app/controllers/api/v1/accounts/analytics_controller.rb:85-91`
returns that choice to the client with the explicit instruction *"Format timestamps in the viewer timezone if
preferred; **it must not change grouping**."* The daily rollup writer uses the same zone
(`app/services/reporting_events/rollup_service.rb:26,30`), and `custom/app/services/analytics/rollup_coverage.rb:43`
refuses the rollup entirely when the zone is blank.

The corpus sentence is right about the **legacy** Reports surface only, which does take the browser's offset:
`app/javascript/dashboard/api/reports.js:4,29,57,80,108` sends `timezone_offset`, and
`app/controllers/api/v2/accounts/reports_controller.rb:48-49` turns it into the report's zone. So the product has
**two** reporting surfaces with **two different** timezone rules, and the article describes one of them as though
it were the rule. For a Gulf account the practical effect is three hours of day-boundary drift on every Analytics
screen, with the documentation telling them their browser decides.

**The product defect underneath.** `reporting_timezone` is read in five places and **written nowhere**. It is
absent from `permitted_settings_attributes` (`app/controllers/api/v1/accounts_controller.rb:123-125` permits only
`auto_resolve_*` and `audio_transcriptions`), absent from the platform API's permitted params
(`app/controllers/platform/api/v1/accounts_controller.rb:57`), absent from the Super Admin account dashboard, and
absent from the onboarding payload — the timezone asked at first run goes to `custom_attributes`
(`accounts_controller.rb:115`), which is exactly what the article's third table row says. So on every account the
value is blank, Analytics always buckets in UTC, and the rollup optimisation can never engage. A writer cannot
fix this half: **the only honest article today says "Analytics groups by day in UTC and nothing in the product
changes that", which is a sentence about a defect.** Route to a Phase-5 owner alongside the corpus correction.

### R2 — "Automation rules leave nothing to inspect" · `major` · corpus fix

> `en/troubleshooting/troubleshooting.md:58` — "| Automation rules | **nothing.** There is no run history and no
> per-rule log in the product |"
> AR: `ar/troubleshooting/troubleshooting.md:57`, identical.

There is a per-rule run record and a screen built to read it.
`custom/app/services/analytics/automations/metrics.rb:18-29` reports `episodes_armed`, `executed`, `skipped`,
`execution_rate`, `awaiting_now` and `stranded_now` off the `automation_rule_pending_executions` table;
`app/javascript/dashboard/constants/analytics.js:53-57` breaks those down by **`rule`**, **`skip_reason`** and
**`status`**; `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsAutomations.vue:7-24` ships the three
series; the route is `analytics.routes.js:46-49`.

The claim is true of **immediate** rules only, and the code says so in its own header
(`metrics.rb:5-14`): a rule with no `execution_delay` runs inline and writes nothing, and the response carries a
warning rather than reporting zero. Terminal rows are purged after 30 days
(`AutomationRulePendingExecution::RETENTION_WINDOW`, cited at `metrics.rb:12`).

This is the single most costly line I found, because the article's whole purpose is to stop a reader hunting for
a log that does not exist — and here it sends them away from the screen built for exactly this question. The
correct sentence distinguishes delayed from immediate rules and names Analytics → Automations.

### R3 — "No priority escalation; nothing raises it as a conversation ages" · `major` · corpus fix

> `en/automation/automation-rules.md:92` — "**No priority escalation.** A rule sets a priority once. Nothing
> raises it as a conversation ages." (AR `ar/automation/automation-rules.md:87`)
> `en/automation/automation-or-flow-builder.md:67` — under the heading **"Neither of them can"**: "**Escalate a
> priority over time.** Both set a priority once. Nothing raises it as a conversation ages." (AR `:65`)

A delayed ("waiting") rule raising priority after N minutes is precisely priority escalation as a conversation
ages, and nothing forbids it. `app/models/automation_rule.rb:41-43` validates `execution_delay` against
`EXECUTION_DELAY_RANGE`, and the two delay validators (`:120-135`) constrain **conditions** — `status` and
`inbox_id` only, per `DELAYED_CONVERSATION_ATTRIBUTES` at `:26-28` — and say nothing at all about actions.
`change_priority` is a first-class action (`settings/automation/constants.js:803-807`), and the delayed triggers
(`constants.js:824-836`) include `conversation_status`, with delays from `MIN_DELAY_MINUTES = 10` to
`MAX_DELAY_MINUTES = 43200` (`constants.js:808-810`).

Both articles then document the mechanism themselves a few lines later —
`automation-rules.md:99-101` ("A rule can act only if something is *still* true after 10 minutes to 30 days") and
`automation-or-flow-builder.md:91-92` ("There **is** an optional **waiting** rule that handles exactly this
shape"). So each article contains both the claim and its refutation. That pattern is the signature of a Limits
list written against an older design record and never re-read against the body it sits under.

### R4 — "A rule cannot send a message to a customer on a Commerce trigger" · `major` · corpus fix

> `en/automation/automation-or-flow-builder.md:111-112` — "**I need an order change to start a conversation
> flow.** That combination does not exist. A store event can only start a rule, and **a rule cannot send a
> message to a customer on a Commerce trigger**."
> Same article `:70` — under **"Neither of them can"**: "**Start a conversation.** For that you need a
> [WhatsApp campaign]".

A Commerce-triggered rule can send an approved WhatsApp template, and that is a deliberate design decision
documented in the code twice. `app/javascript/dashboard/routes/dashboard/settings/automation/lynomiaAutomation.js:183-188`:

```
const actionAllowed = (event, actionKey) => {
  if (isCommerceEvent(event) && CUSTOMER_MESSAGE_ACTIONS.includes(actionKey)) return false;
  if (actionKey === TEMPLATE_ACTION) return whatsappInboxes.value.length > 0;
  return true;
};
```

`CUSTOMER_MESSAGE_ACTIONS` is `['send_message', 'send_attachment']` (`:28`) and `TEMPLATE_ACTION` is
`'send_whatsapp_template'` (`:30`). The comment at `:24-27` states the reason: *"`send_whatsapp_template` is
deliberately absent from this list — an approved template is the one thing WhatsApp permits outside that window,
so it stays available."* The server agrees: `custom/app/models/custom/automation_rule.rb:10-16` and the
`commerce_trigger_rules` validator at `:80-81` subtract only `CUSTOMER_MESSAGE_ACTIONS`, and
`custom/app/services/custom/automation_rules/action_service.rb:24-28` dispatches the template send.

So an order-refunded rule **can** message that customer outside the 24-hour window, which also refutes `:70`:
a product-initiated outbound template on a store event is starting a conversation without a campaign. The ledger
has IR-04 for the *internal* record that said this was impossible; the *public* corpus carries the same dead
claim in two places and nobody logged it.

### R5 — "One of twelve events" / "seven order events" · `minor` · corpus fix

> `en/automation/automation-or-flow-builder.md:22` (table) — "| **What starts it** | one of twelve events | … |"
> (AR `:22` "واحد من اثني عشر حدثاً")
> Same article `:29` — "| **Can start from a store event** | yes, seven order events | no |" and `:47` —
> "Seven order events, a conversation being resolved, a conversation being opened."

Thirteen. `app/models/automation_rule.rb:55` lists five base events; `custom/app/models/custom/automation_rule.rb:34-36`
adds `Automation::CommerceEvents::EVENTS`, which is `Commerce::OrderTransitions::EVENTS` (seven —
`custom/app/services/commerce/order_transitions.rb:29`) plus `CART_EVENTS` (one,
`custom/app/services/automation/commerce_events.rb:14-15`). The "seven order events" count is right about order
events and silently drops `commerce_cart_abandoned`, which is a startable store event and therefore belongs in
both `:29` and `:47`.

This is DC-09's miscount in a **file DC-09 does not name**. `automation-or-flow-builder.md` is the boundary
article the ledger flagged at XA-08 as verified from one side only; this is the evidence that both sides need
re-reading, not just one.

### R6 — "There is no condition anywhere that asks whether a contact carries a label" · `major` · corpus fix

> `en/audiences-and-campaigns/labels-or-shared-audiences.md:70-71` — "A rule can ask *is this conversation's
> contact in audience X*. **There is no condition anywhere that asks whether a contact carries a particular
> label.**" (AR `:69`)
> Same article `:61` — "**Lynomia Chat has no static audience.**"
> `en/conversations/labels.md:104` — "There is no automation trigger for a contact being created or changed, and
> **no automation condition on a contact label**." (AR `:104`)

A contact-label condition exists and is offered in the contact filter builder.
`app/javascript/dashboard/components-next/filter/contactProvider.js:191-204` declares an attribute keyed
`CONTACT_ATTRIBUTES.LABELS`, `inputType: 'multiSelect'`, options drawn from the account's label catalogue, with
`equalityOperators`. A shared audience **is** a saved contact filter —
`custom/app/models/custom/custom_filter.rb:1-9,20-22`, where `shared_only_for_contacts` permits sharing on
contact filters only — and an automation rule can test audience membership via `contact_audience`
(`lynomiaAutomation.js:101-112`). Composing those two gives an automation condition on a contact label, by a
route the corpus documents elsewhere.

The corpus refutes itself inside the same section: `en/audiences-and-campaigns/whatsapp-campaigns.md:94` tells
the reader to build *"Labels — not equal to — wholesale"* and **"Save it as a shared audience"**. And an audience
whose only condition is `labels equal_to vip` is a static-by-label set, which is what `:61` says the product does
not have.

This matters more than a typo because `:70-71` is the article's **central thesis** — it is the sentence that
tells a reader which of the two tools to reach for.

### R7 — "Contacts created, edited, merged or deleted leave no entry" · `major` · corpus fix

> `en/administration/audit-logs.md:35,39` — under **"What is not recorded … Nothing below leaves an entry"**:
> "Contacts created, edited, merged or deleted; [imports] and [bulk actions]."

A merge writes an audit row. `custom/app/actions/custom/contact_merge_action.rb:26` defines
`AUDIT_EVENT = 'contact.merged'`, and `:74-80` writes `Custom::AuditLog.create!(auditable: @base_contact,
associated: @account, user: Current.user, action: 'update', comment: AUDIT_EVENT, …)`. `associated: account` is
exactly the scope the reader serves (`custom/app/models/custom/audit_log.rb:26`), and the action's own header at
`:22-24` says so: *"written through Custom::AuditLog with `associated: account`, which is what puts it on Settings
→ Audit Logs with no new reader."*

The rest of line 39 — created, edited, deleted, imports, bulk actions — holds: there is no `audited` macro on
`Contact` (`grep -rn "^\s*audited" app/models custom/app/models` returns fourteen declarations, none of them
`Contact`).

This is DC-03's contradiction **in a second file that DC-03 does not name**. DC-03 is assigned to 051, who owns
`contacts`; `audit-logs.md` sits in `administration` and belongs to 059. A per-area ledger entry cannot catch a
claim that lives in another area's article, which is the structural reason this brief exists.

### R8 — The audit log's unlabelled-events list, and one active mislabel · `major` + `minor` · corpus fix

> `en/administration/audit-logs.md:43-44` — "Commerce store connections and order actions, and flow changes, are
> written to the same table, but the page has no label or filter for them, so they appear in the list **without a
> description**."
> Same article `:119` — "**Some entries have no description.** Those are the Commerce and flow events mentioned
> above."

Two families named; at least five exist. `app/javascript/dashboard/helper/auditlogHelper.js:12-49` is the
complete label map, and it has no key for:

| Unlabelled auditable | Writer | Reaches the account page because |
|---|---|---|
| `Contact` (`contact.merged`) | `custom/app/actions/custom/contact_merge_action.rb:74-80` | `associated: @account` |
| `Support::Ticket` | `custom/app/models/support/ticket.rb:23` `audited associated_with: :account` | the macro's `associated` |
| `AgentBot` (flows) | `custom/app/services/flows/audit.rb:11-12`, and `custom/app/models/custom/audit/agent_bot.rb:14` | `associated: agent_bot.account` |
| store / customer link | `custom/app/services/commerce/audit_trail.rb:27-30` | `associated: account` |

`:119`'s "Those are the Commerce and flow events" is therefore wrong as a diagnosis: the most likely
no-description row an administrator meets is a **contact merge**, which is also the one the article elsewhere
says is not recorded at all (R7).

**The mislabel is worse than the omission.** `custom/app/services/billing/override_grant.rb:131-135` writes
`auditable: @account, associated: @account, action: 'update'`. `generateLogActionKey` turns that into
`account:update` → `AUDIT_LOGS.ACCOUNT.EDIT` (`auditlogHelper.js:46,223-233`). So an operator's billing
entitlement override renders on the tenant's audit log as **"account settings were changed"**, attributed to the
operator. That is not a missing description; it is a wrong one, on the one page whose entire purpose is to answer
"who changed what". Flag to product as well as to the writer: the fix is one key in `auditlogHelper.js`.

### R9 — "You can still reach this desk" vs. "you may attach five files" · `major` · corpus fix **and** PD-34

> `en/troubleshooting/contact-lynomia-support.md:30` — "**You may attach up to five files of 10 MB each** —
> screenshots, a PDF invoice, a CSV or a plain-text log excerpt."
> Same article `:92-93` — "**You can still reach this desk.** Platform support is never gated and never sold: a
> locked account … can still open a ticket — **including a ticket about the lock itself**."

Both sentences are true in isolation and false together. The desk itself is billing-exempt
(`custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:16-19,29-31`), and the attachment
limits are exactly as stated (`custom/app/models/platform_support/message.rb:33-34` `MAX_FILE_BYTES = 10.megabytes`,
`MAX_FILES = 5`; `ALLOWED_CONTENT_TYPES` at `:32` is png/jpeg/gif/webp/pdf/plain/csv, matching the article's
sentence about archives).

But the blob is uploaded somewhere else first. `base_controller.rb:59-61` says the signed id "names a blob the
caller has just uploaded through the **account-scoped upload endpoint**", which is
`app/controllers/api/v1/accounts/upload_controller.rb:1` — an ordinary `Api::V1::Accounts::BaseController`
subclass. `custom/app/controllers/billing/access_guard.rb:14-15` installs `before_action :ensure_billing_access`
on that base, and `:50-52` exempts only `Api::V1::Accounts::BillingController`. A billing-locked account
therefore gets `402 subscription_required` on the upload and can open the ticket **but cannot attach the invoice
it is about** — the single most likely attachment for the single most likely locked-account ticket.

Corpus fix and product fix are both one line. The writer's half: say that attachments need an active
subscription. The product's half: add `UploadController` to the exemption, or widen the exemption to the
Platform Support upload path. See §2.0 for PD-34's corrected citations.

### R10 — "Manage reports grants reports, including satisfaction responses" · `major` · corpus fix

> `en/workspace/roles-and-permissions.md:36` (the custom-role table) — "| Manage reports | reports, including
> satisfaction responses |"

It grants neither. `app/policies/report_policy.rb:2-4` is `@account_user.administrator?` and has no overlay —
`find -name '*report_policy*'` returns the OSS file and its spec only, and the `prepend_mod_with` at `:7` finds
nothing. `app/policies/csat_survey_response_policy.rb:2-12` is administrator-only on all three actions, so
"including satisfaction responses" is specifically the part that cannot work.

The client admits it in a comment: `app/javascript/dashboard/routes/dashboard/analytics/analytics.routes.js:4-6`
reads *"ReportPolicy#view? is administrator-only on the server, and `report_manage` is the matching custom-role
permission the existing report routes declare"*, and `:18` admits the permission anyway. The holder reaches the
page and every panel 401s.

This is PD-10's defect expressed as a **corpus claim**, which the ledger does not carry. It also lands squarely
inside XA-13 ("UI offers what the server refuses"), and it is the strongest argument for the orchestrator's
stated position there: the corpus should describe the **server's** truth. This row is the corpus describing the
UI's offer, and a reader who plans a role around it builds a role that cannot work.

**Agent 096 reached this line independently** (Addendum 6, PD-10 row) and asks for a DC entry beside the PD
entry, with the warning that a writer must not reword it to "grants nothing" while the role editor still offers
it. I agree with the warning and record one thing 096 did not: `app/policies/csat_survey_response_policy.rb:2-12`
means the clause **"including satisfaction responses"** is independently refused by a second policy, so the row
is wrong twice over and will stay wrong even if `ReportPolicy` is widened to honour `report_manage`.

The same article also reproduces DC-19 three times — `:3` and `:28` and `:92` all say **six** permissions, while
`permissions.js:4-12` offers seven and `custom/app/models/custom_role.rb:19-28` holds eight. The missing seventh,
`support_ticket_manage`, is the permission that governs the **Support cases** desk — which `:53-56`'s "What is
not on the list" also omits, and for which the corpus has no article at all
(`contact-lynomia-support.md:14` is its only mention, one table row).

### R11 — "The article endpoints refuse a workspace request" · `minor` · corpus fix

> `en/workspace/your-own-help-centre.md:18` — "The same is true through the API: **the portal, category and
> article endpoints refuse a workspace request.**"
> Same article `:49-51` — "A role created before this change keeps the permission on its record, where it now
> grants nothing — you can leave it or edit the role to drop it, and **either way it changes nothing** about what
> that person can do."

The **authoring** endpoints refuse, unconditionally and by design:
`custom/app/policies/custom/portal_policy.rb:25-34` returns false for every method, and its header at `:8-14`
explains that one denial covers index, show, create, update, destroy, reorder, archive, logo, send_instructions,
ssl_status and all four bulk actions.

`GET /api/v1/accounts/:id/search/articles` does not. `app/controllers/api/v1/accounts/search_controller.rb:18-20`
calls `SearchService` with no `authorize` and no feature check — and the account base controller adds none
(`app/controllers/api/v1/accounts/base_controller.rb:4-5`) — so `SearchService#filter_articles`
(`app/services/search_service.rb:177-182`) returns `current_account.articles.text_search(...)` to **any member of
any account, in any role**. The `index` action's `'all'` branch (`search_service.rb:19`) includes articles too.
So a workspace article endpoint that does not refuse a workspace request exists, and the sentence is absolute
where it should be about authoring.

**On the permission half I defer to agent 096**, which has already corrected PD-11 in Addendum 6. My independent
check agrees with its correction and narrows it slightly. `app/javascript/dashboard/constants/permissions.js:34-36`
keeps `knowledge_base_manage` specifically so the global-search Articles tab stays reachable, and
`modules/search/components/SearchView.vue:116` gates that tab on `[...ROLES, PORTAL_PERMISSIONS]` — but `:117`
also sets `featureFlag: FEATURE_FLAGS.HELP_CENTER`, and the tab filter at `:132-141` requires **both**
`shouldShow(...)` and `isFeatureFlagEnabled(...)`. `config/features.yml:44-46` ships `help_center` as
`enabled: false`. So on a default installation the permission grants nothing in the UI and the corpus is right;
on an installation where an operator left `help_center` on — which is exactly the "workspace that published one
before this change" population the sentence is addressed to — the permission does grant that tab, and "either way
it changes nothing" is false for precisely the reader it is written for. `minor`, and a writer can fix it with a
clause rather than a rewrite.

### R12 — Customer 360's "up to ten recent orders" · `minor` · corpus fix

> `en/commerce/customer-360.md:21` (table) — "| **Recent orders** | up to ten, newest first, each labelled with
> the store it came from |"
> Same article `:24` — "**Stores are read at the same time**, and the tab answers after about fifteen seconds
> whatever is still running."

The ten is a ceiling that a single-store account can never reach.
`custom/app/services/commerce/customer360.rb:15,77` takes `.first(LATEST_ORDERS)` with `LATEST_ORDERS = 10`, but
the orders it sorts are whatever each store contributed, and each store contributes at most
`Commerce::ConversationPanel::ORDER_LIMIT = 5` (`conversation_panel.rb:9,60`) — a cap `customer360.rb:4` names in
its own header. One store ⇒ five orders, maximum, forever. Two stores ⇒ ten. The reader most likely to be
confused is the single-store merchant, which is most of them.

"At the same time" is also loose: `MAX_CONCURRENCY = 4` (`customer360.rb:16,82`), so a fifth store waits for a
slot and the fifteen-second budget (`STORE_TIMEOUT = 15`, `:17`) can expire with stores not yet started.

The fifteen seconds, the per-store error row and "one bad store never blanks the tab" all check out exactly
(`:6-8,82`), which is why this one is `minor` — the article is accurate about the hard part and loose about the
easy part.

### R13 — "Nothing is retried, nothing is queued, no delivery log" · `major` in two files, `minor` in a third

> `en/troubleshooting/troubleshooting.md:59` — "| Webhooks | **nothing.** No delivery log, no retry, no replay |"
> `en/automation/agent-bots.md:114` — "**Nothing is queued while your endpoint is down,** and there is no
> delivery log to read here. Log on your side."
> `en/integrations/webhooks.md:98,105,117` — "A webhook delivery is **attempted once**." / "Nothing is retried,
> nothing is queued, and nothing is shown to you" / "**No retries, no delivery history, no replay, and no test
> button.**"

Agent-bot deliveries **are** retried. `lib/webhooks/trigger.rb:3` defines
`RETRYABLE_AGENT_BOT_STATUSES = [429, 500]`, `:29` re-raises those as `RetryableError`, `:126-127` scopes that to
`:agent_bot_webhook`, and `app/jobs/agent_bots/webhook_job.rb:3-8` declares
`retry_on Webhooks::Trigger::RetryableError, wait: 3.seconds, attempts: 3`. A Sidekiq retry is a queued delivery
by any definition a reader would use.

`agent-bots.md:114` is therefore refuted **by its own article four lines earlier**, at `:109-110`: "**Retries are
limited.** A delivery your service answers with 429 or 500 is retried up to three times, a few seconds apart."
One Limits bullet contradicts the next.

`troubleshooting.md:59` is wrong on two counts — the agent-bot retry, and "no delivery log". Every account-webhook
failure writes an `OUTBOUND_WEBHOOK_FAILED` operator-log line with the account, event, endpoint host, digest,
delivery id and HTTP status (`custom/app/services/custom/webhooks/trigger.rb:45-57`) **and** an
`Operations::Signal` row per endpoint, visible in the Operations Center (`:29-35`). That log is not the tenant's
to read, which is a legitimate thing to say — and is different from saying it does not exist, because it changes
what a support ticket can ask for.

`webhooks.md` itself is scoped to account webhook subscriptions, where "attempted once" is correct
(`lib/webhooks/trigger.rb:26-32` swallows the failure, and `custom/.../trigger.rb:12-15` states that this is
deliberately unchanged). Its defect is narrower: the "Other things that POST to a URL" table at `:132-137` lists
four senders and omits the agent-bot webhook, the one sender with different delivery semantics.

### R14 — "A campaign cannot be edited after it is created" · `minor` · corpus fix

> `en/audiences-and-campaigns/whatsapp-campaigns.md:131` — "**A campaign cannot be edited after it is created.**
> Delete it and create another. Deleting is also the only way to cancel a scheduled campaign."

`PUT /api/v1/accounts/:id/campaigns/:id` exists, works, and permits title, description, message, enabled,
inbox_id, sender_id, `scheduled_at`, audience, trigger_rules and template_params
(`app/controllers/api/v1/accounts/campaigns_controller.rb:15-17,30-32`), authorized for administrators
(`app/policies/campaign_policy.rb:6-8`). An administrator with API access can reschedule or retarget a WhatsApp
campaign without deleting it.

It is the **UI** that has no edit path: `EditLiveChatCampaignDialog.vue` is the only campaign edit dialog in the
tree, and `CampaignCard.vue:163-171` renders the edit button under `v-if="isLiveChatType"`. So the claim is right
about the screen and wrong about the product. `minor`, because the UI is what the article is about — but worth
fixing, because the API is documented elsewhere as a supported surface and a reader who drives it by API will
believe their update was refused.

### R15 — "There is no alert when incoming messages stop" · `minor` · corpus fix

> `en/whatsapp-errors/whatsapp-nothing-arrives.md:56` — "**There is no alert** when incoming messages stop.
> Silence looks like a quiet day."

True for the article's stated cause (a missing webhook subscription), and false for the other common cause. When
a WhatsApp channel's token stops authorizing, `app/models/concerns/reauthorizable.rb:34` fires
`prompt_reauthorization!` at `AUTHORIZATION_ERROR_THRESHOLD` (2, `:16`), the handler map at `:87-94` routes
`Channel::Whatsapp` to `send_channel_reauthorization_email(:whatsapp_disconnect)`, and `:58-59` mails every
administrator. `custom/app/models/custom/reauthorizable.rb:16-24` additionally records a `:channel` operations
signal. So silence caused by a dead token **is** alerted; silence caused by a dropped webhook field is not. The
distinction is the useful content, and the absolute sentence hides it.

---

## Survived

Things I tried to break and could not. Listed because an unchecked "fine" is worthless and because these are the
claims a writer should not spend time re-verifying.

**Audit log.** The retention story is accurate in every particular: 365 days default
(`custom/app/jobs/audit_trail/retention_job.rb:30`), a 30-day floor (`:36`), a strict `<` on a UTC day boundary
so the effective window errs longer never shorter (`:22-25`), operator-only via `AUDIT_LOG_RETENTION_DAYS` on the
Super Admin general form with no account, administrator or agent reach (`:9-15`), and capture never gated by the
`audit_logs` feature — only reading is (`:3-7`, `custom/app/services/audit_trail/query.rb:52`), which is exactly
what `audit-logs.md:58-59` claims. "The filter offers exactly these fourteen" is right: 1 + 4 + 7 + 2 =
14 (`auditlogHelper.js:235-265`). "Paginated at 25" is right (`AuditTrail::Filters::PER_PAGE = 25`). Agent
availability changes are audited (`custom/app/models/custom/audit/account_user.rb:15`).

**Automation.** There is genuinely **no** business-hours, working-hours, time-of-day or day-of-week condition:
`conditions_attributes` (`app/models/automation_rule.rb:58-61` plus the Lynomia additions at
`custom/app/models/custom/automation_rule.rb:38-40`) contains nothing time-shaped, and grepping the client's
automation module for `business_hour|working_hour|time_of_day` returns nothing. So
`automation-or-flow-builder.md:65-66`, `set-up-an-inbox.md:53` and `troubleshooting.md:70` all hold — this is the
most-repeated negative claim in the corpus and it is true. `agent-bots.md:55` "There is no 'conversation created'
event for bots" holds: `app/listeners/agent_bot_listener.rb` defines seven handlers and no `conversation_created`.

**Assignment.** The seven-day exclusion is `DEFAULT_EXCLUDE_OLDER_THAN_HOURS = 168`
(`app/models/assignment_policy.rb:25`). "Without an assignment policy … there is no separate sweep"
(`assign-and-prioritise.md:94-96`) is correctly scoped — `AutoAssignment::PeriodicAssignmentJob:5-15` requires
both `assignment_v2` and an attached `assignment_policy`, so an account with neither really does depend on
channel events.

**Audiences and folders.** "A conversation folder is **yours alone**. There is no way to share one"
(`work-in-the-inbox.md:53`) holds by validation, not convention:
`custom/app/models/custom/custom_filter.rb:20-22` `shared_only_for_contacts` rejects a shared conversation
filter. "No membership is stored anywhere" (`shared-audiences.md:13`) holds — `#members` (`:13-16`) builds a
relation at read time. Canned responses are account-wide only, with no user column at all
(`app/models/canned_response.rb:3-11`).

**Commerce.** The HTTP bounds are exact: connect 3 s, read 8 s, whole body 10 s, 5 MB
(`custom/app/services/commerce/http_client.rb:15,18-19`), one retry for reads only and never for a timeout or an
action (`:8-9`), and the cache is fresh for 120 s and served stale for up to 24 h
(`custom/app/services/commerce/cache.rb:8-10`) — all as `commerce-store-unreachable.md:18-22` and
`commerce-overview.md:31` state. The 30-second refresh cooldown is `COOLDOWN = 30.seconds`
(`refreshes_controller.rb:8`). Cancel and refund are administrator-only and not grantable to any custom role
(`custom/app/policies/commerce/action_policy.rb:23-29`), as four separate articles claim.

**Contacts and bulk actions.** 10,000 per action, refusing rather than truncating
(`bulk_actions_controller.rb:8-10`, whose comment says exactly that). Fifteen rows per contacts page
(`contacts_controller.rb:14`).

**Integrations.** The whole "Which of them you will see" table (`integrations.md:35-40`) is correct, row by row,
against `app/models/integrations/app.rb:55-68,124-126`: Slack on `SLACK_CLIENT_SECRET`; Linear and Notion on a
credential **and** an account feature; LeadSquared on `crm_integration`; everything else unconditionally. Ten apps
exist (`config/integration/apps.yml`).

**Platform Support.** Five files, 10 MB each, images/PDF/text/CSV and no archives
(`custom/app/models/platform_support/message.rb:32-34`). A custom-role holder sees exactly what an agent sees —
only tickets they reported — and the policy's header at `:8-13` states that the absence of a permission is the
approved decision, not an omission (`custom/app/policies/platform_support/ticket_policy.rb:44-50`). That makes
`contact-lynomia-support.md:100-101` correct, and is worth recording because it is the one place where a
"custom roles get nothing here" claim is deliberate design rather than drift.

**WhatsApp.** "Templates refresh automatically every few hours" holds: a 5-minute scheduler picks channels stale
by 3 hours (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:7-8`,
`app/jobs/trigger_scheduled_items_job.rb:30`). "There is no alert when a template is paused or rejected; nobody
is emailed" holds — `custom/app/services/whatsapp/templates/status_update.rb:27-35` updates the row inside
`without_auditing` and notifies nobody. "There is no alert when a [number] status changes"
(`whatsapp-number-status.md:52`) holds for users: `Whatsapp::HealthService#log_risky_transition:213-223` writes a
`Rails.logger.warn` and nothing else. Coexistence history import really is unimplemented — the webhook field set
is `%w[messages smb_message_echoes message_template_status_update]`
(`app/services/whatsapp/facebook_api_client.rb:9`, `webhook_setup_service.rb:90`) with no history field.

**Campaigns.** Blocked contacts are not excluded: `app/models/campaign.rb:103-106` and
`custom/app/models/custom/campaign_audience.rb:12-19` filter on labels and audiences only, with no `blocked`
predicate anywhere. The three-day window is `SELECTION_WINDOW = 3.days`
(`app/jobs/trigger_scheduled_items_job.rb:8,16`).

**Macros.** Sixteen server actions and no commerce action (`app/models/macro.rb:33-35`), so
`macros.md:93` holds. Only administrators can edit a public macro
(`app/policies/macro_policy.rb:14-18`), and an agent cannot create one — `set_visibility` forces `:personal`
(`macro.rb:37-40`) — so `macros-or-automation.md:26` holds too.

---

## Not checkable

- **Arabic-only claims.** I checked AR line-for-line only where an EN finding needed its AR twin (R1, R2, R3, R5,
  R6). A claim present in AR and absent in EN would not have surfaced in my grep, which ran over `en/` for
  tractability. That residue is 094's, and it is the one systematic blind spot in this report.
- **The 500 or so remaining negative claims.** 519 candidate lines matched my pattern in EN alone; I verified on
  the order of eighty. The yield rate among the ones I chose was roughly one refutation per five claims checked,
  and I chose the cross-area and absolute ones first, so the remainder should yield less — but it will not yield
  nothing. A second pass is worth commissioning, and the pattern list in §1 is the tool for it.
- **Whether `reporting_timezone` is non-blank in production (R1).** Phase 1 forbids touching production data, and
  no code path writes it. If some operator set it by console on some account, that account's Analytics is
  correctly zoned and the others are not — which would make the user-visible symptom inconsistent between
  accounts rather than uniformly UTC. Needs one read-only query an owner can run:
  `Account.where("settings->>'reporting_timezone' IS NOT NULL").count`.
- **Whether a billing-locked account's upload really 402s end to end (R9).** I traced the guard, the exemption
  list and the controller ancestry statically and the conclusion follows from them, but I did not run a request.
  One request spec against `UploadController` with an inaccessible subscription would settle it.
- **Rendered strings.** Several refutations above turn on what a reader sees in the UI (the audit log's
  "account settings" row in R8, the Articles tab in R11). I read the i18n keys and the templates that reference
  them; I did not render a page. Where the key is unambiguous I have treated it as evidence, and where the
  rendering depends on data I have said so.
