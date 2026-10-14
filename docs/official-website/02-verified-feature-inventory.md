# 02 — Verified feature inventory

**Date:** 2026-10-14 · **Repo base:** `lynomia-custom @ aa27e6f7` · **Companion:** `01-current-state-audit.md`

## The standard of proof used here

A feature is **AVAILABLE** only when all four hold: the model/service exists, a route or UI entry point reaches
it, no feature flag / plan entitlement / credential gate is off by default, and the flow is complete. If a gate
exists it is **CONDITIONAL** and the gate is named with its default. **BETA** means the product labels it so.
**INCOMPLETE** means code exists but the path cannot be completed. **NOT ESTABLISHED** means it could not be
proven, and what was checked is stated.

Three fork-wide facts govern every verdict below:

1. **`ChatwootApp.enterprise?` is hard-coded `false`** (`lib/chatwoot_app.rb:19-21`). So `chatwoot_cloud?` is
   permanently false, and every capability gated on it is dead on this installation.
2. **`premium: true` features cannot be sold at all** — `BillingPlan` excludes them from assignable features
   (`custom/app/models/billing_plan.rb:41-47`), so a `premium` flag is not "available on a higher plan"; it is
   unavailable, full stop.
3. **Account feature flags** (`config/features.yml`) and **plan channel entitlements**
   (`billing_plans.channel_entitlements`) are two independent gates, and several marketing-relevant features are
   off in both.

Counting the verdicts across the three inventory passes: **111 AVAILABLE, 51 CONDITIONAL, 5 BETA, 9 INCOMPLETE,
7 NOT ESTABLISHED**. The CONDITIONAL count is the headline number for a marketing site: a third of what the
product can do needs a named precondition stated on the page.

---

## 1. Channels — the honest count is **nine**, plus TikTok as beta

| Channel | Verdict | Condition the page must state | Page |
|---|---|---|---|
| WhatsApp Cloud API (manual keys) | **AVAILABLE** | customer supplies Cloud API credentials | `/channels/whatsapp` |
| WhatsApp Cloud API (Embedded Signup) | **CONDITIONAL** | `WHATSAPP_APP_ID` + `WHATSAPP_CONFIGURATION_ID` configured (`app/javascript/.../useWhatsappEmbeddedSignup.js:39-50`) | same page |
| WhatsApp Business coexistence | **CONDITIONAL** | same credentials (`Whatsapp.vue:78-86,113-124`) | same page |
| WhatsApp via Twilio | **AVAILABLE** | customer's Twilio credentials | same page |
| Website live chat | **AVAILABLE** | none (`config/features.yml:89-91`) | `/channels/live-chat` |
| Email — IMAP/SMTP + forwarding | **AVAILABLE** | none (`config/features.yml:20-23`) | `/channels/email` |
| Email — Gmail OAuth | **CONDITIONAL** | Google OAuth client configured | same page |
| Email — Microsoft 365 | **CONDITIONAL** | `AZURE_APP_ID` configured | same page |
| SMS — Twilio | **AVAILABLE** | customer's Twilio credentials | `/channels/sms` |
| SMS — Bandwidth | **AVAILABLE** | credentials + inbound callback basic-auth pair (`custom/app/models/custom/channel/sms.rb:25-36`) | same page |
| Telegram | **AVAILABLE** | bot token | `/channels/telegram` |
| LINE | **AVAILABLE** | three LINE credentials | `/channels/line` |
| Facebook Messenger | **CONDITIONAL** | `FB_APP_ID` set **and** `channel_facebook` on (`ChannelItem.vue:40-42`) | `/channels/facebook-messenger` |
| Instagram DM | **CONDITIONAL** | `INSTAGRAM_APP_ID` set **and** `channel_instagram` on (`ChannelItem.vue:47-51`) | `/channels/instagram` |
| API channel | **AVAILABLE** | none | fold into `/features/api-webhooks` |
| TikTok | **BETA** | tile exists only with `TIKTOK_APP_ID` (`ChannelList.vue:82`); carries a beta badge | mention only, labelled beta |
| WhatsApp via 360dialog | **INCOMPLETE** | backend and component exist but the provider is **not listed** in `availableProviders` (`Whatsapp.vue:98-125`) — reachable only via `?provider=360dialog` | **no page** |
| Twitter / X | **NOT ESTABLISHED as a product** | model and capability row exist; **no connect path, no webhook route** (`ChannelFactory.vue:14-26`) | **no page, no mention** |
| Voice / WhatsApp Calling | **NOT ESTABLISHED** | no `Channel::Voice`; tiles removed (`ChannelList.vue:96-98`); `channel_voice` is premium and therefore unsellable | **no page, no mention** |

**Safe headline: "nine channels", with TikTok named separately as beta.** If provider variants are counted
instead of tiles the honest phrasing is "9 channels, 13 provider routes". The current marketing page's channel
section must be rebuilt against this table — and must stop implying Twitter/X or voice.

---

## 2. Inbox, collaboration, routing, contacts — the strongest area

**AVAILABLE and safe to feature prominently:** conversation statuses (open/resolved/pending/snoozed) and
priorities; assignment to agent and team; labels; private notes; @mentions with notification; conversation
participants; search across conversations, messages, contacts and articles; filters and saved folders; bulk
actions; typing indicators; delivery/read status per channel; attachments (40 MB default,
`config/installation_config.yml:104-107`); voice notes in the reply box; WhatsApp templates in the reply box;
draft messages; message retry and translate; email transcript; command palette; keyboard shortcuts; CSAT
surveys; **Assignment Policies V2** with fair-distribution window and limit — which is a `SYSTEM_FEATURE`, so
no plan can withhold it (`config/features.yml:211-213`, `custom/app/models/billing_plan.rb:12`); agent
availability states; business hours per inbox; out-of-office.

**Contacts:** custom attributes, notes, import/export, merge, segments, and **`contact_identities`** —
multi-valued phone/email identity with deterministic matching — plus the Customer 360 panel.

**Must NOT be claimed:**

| Item | Why |
|---|---|
| Advanced search | `advanced_search` is `premium: true, enabled: false`, and `ChatwootApp.advanced_search_allowed?` is `enterprise? && …` → always false (`config/features.yml:218-221`, `lib/chatwoot_app.rb:46-48`) |
| Conversation SLA | `sla` is `premium: true, enabled: false` (`config/features.yml:131-135`) — unsellable. A real SLA engine exists, but only for **support tickets** (§5) |
| Per-agent capacity limits | needs `advanced_assignment`, which is `premium: true, enabled: false` (`config/features.yml:272-275`) |
| CSAT review notes | premium and off (`config/features.yml:248-251`) |

**Pages:** `/features/unified-inbox`, `/features/team-collaboration`, `/features/auto-assignment`,
`/features/contact-management`, `/features/custom-attributes`, `/features/canned-responses`,
`/features/macros`, `/features/business-hours`, `/features/customer-satisfaction`. All nine are supportable
today. `/features/sla-management` **must not be created** for conversations; SLA belongs on the support-desk
page if anywhere.

---

## 3. AI — the single largest over-claim on the current site

### 3.1 What does not exist

**There is no AI assistant, AI agent, copilot, AI knowledge base or chatbot product in this codebase.** The
trace: the `Captain` namespace in `config/routes.rb` is exactly one block (`:63-72`) containing
`resource :preferences` plus five task POSTs; there are **no** assistant, document, scenario, copilot-thread,
custom-tool, FAQ-suggestion or agent-session routes, although orphaned frontend API modules for them exist
under `app/javascript/dashboard/api/captain/`. No `Captain::Assistant` model is defined anywhere — the only
references are inside already-applied migrations, which are safe precisely because
`ChatwootApp.enterprise?` is `false` (`lib/chatwoet_app.rb:14-18` records the eight call sites). The Captain
settings page is additionally gated on `captain_integration`, which is `premium: true, enabled: false`
(`config/features.yml:144-147`) **and** on a cloud deployment this installation is not.

### 3.2 What does exist: five agent-assist actions, off by default

`POST .../captain/tasks/{rewrite,summarize,reply_suggestion,label_suggestion,follow_up}`
(`config/routes.rb:63-72`), each backed by a real service under `lib/captain/`. Both gates must pass
(`lib/captain/base_task_service.rb:40-44`):

1. `account.feature_enabled?('captain_tasks')` — **default OFF**. The default is deliberate and documented in
   the repo: `config/features.yml:252-267` states *"Lynomia does not sell or operate an AI assistant, so no
   account is created holding one"*, and `db/migrate/20261011160000_default_captain_tasks_off_for_new_accounts.rb:28-29`
   makes it real for new accounts.
2. An OpenAI credential — either the account's own `openai` integration hook or installation
   `CAPTAIN_OPEN_AI_API_KEY` (`lib/captain/base_task_service.rb:171-206`).

Translation and language detection are **CONDITIONAL** on a Google Translate hook with Google Cloud
credentials. Anthropic and Gemini models are declared `coming_soon: true` (`config/llm.yml:41,46,51,56`).
Customer-hosted **agent bots** are **AVAILABLE** (`agent_bots` default true).

### 3.3 Consequence for the website

The live page's AI section — `ذكاء اصطناعي يردّ بدالك` ("AI replies on your behalf", `home.html:~500`) and
`ردود آلية بالذكاء الاصطناعي 24/7` ("AI auto-replies 24/7", `:448`, `:546`, `:590`) — describes a product that
does not exist in a sellable state. **It must be removed or rewritten.**

What may honestly be said, with the gate stated: *"Optional AI assistance for your agents — rewrite, summarise,
suggest a reply, suggest labels and refine a follow-up — available when you connect your own OpenAI key."*
A `/features/ai-assistant` page is therefore **CONDITIONAL and must say so on the page**. `/features/ai-agents`
and `/features/chatbots` **must not be created**; `/features/translation` is CONDITIONAL.

---

## 4. Pricing — no plan, price or tier exists anywhere in the repository

**`/pricing` cannot publish numbers.** The trace: no seed creates a `BillingPlan` (`db/seeds.rb`, `db/seeds/`,
`lib/seeders/` and `lib/tasks/` contain **zero** `BillingPlan` references); no price literal exists —
`price_cents` ships `default: 0` (`db/schema.rb:347`); and a no-exclusion search for commercial tier names
(`starter|growth|professional|business|enterprise|basic|premium|pro`) across `*.rb,*.yml,*.json,*.vue,*.erb`
outside `docs/` and `spec/` returned ~50 hits, **none of which is a plan name** — they are upstream enterprise
guards, `premium:` flag keys, LLM tone words and prose. There is no tier concept in the schema at all.

| Safe to publish | Citation |
|---|---|
| That plans exist with per-plan feature sets and ceilings on **agents, inboxes and connected stores** | `custom/app/models/billing_plan.rb:9`, `custom/app/models/billing/resource_limit.rb:28-32` |
| Monthly or annual billing; flat or per-agent pricing models | `billing_plan.rb:4-5` |
| Card payment and an invoice/cancel portal via Stripe **once configured** | `custom/app/services/billing/{checkout,portal}.rb` |
| Plan changes previewed before they are charged | `custom/app/services/billing/plan_change.rb` |
| An account can see its usage against its ceilings | `custom/app/.../api_serializer.rb:69-75` |
| Channels can be sold per plan | `billing_plan.rb:87-93` |

**Must not be published:** any price, currency amount, "from $X", agent/inbox/store count, plan name, tier
ladder, or trial length as a promise. **And the current page's `تجربة مجانية · بدون بطاقة ائتمانية` must go**:
`BILLING_TRIAL_PLAN_ID` defaults to nil (`custom/app/models/billing/settings.rb:13`) and no plan row exists, so
the trial cannot start even though signup itself is enabled in production (doc 01 §10 D1).

**Therefore `/pricing` is a quote-request page** carrying the comparison *dimensions* (channels, agents,
inboxes, stores, modules) with a contact action. To publish a real table the prerequisites are: create plan
rows, configure Stripe, run `Billing::PlanSync`, then render from `BillingPlan.active.ordered` rather than
hand-written numbers. **No documentation article covers pricing** — the corpus has no billing section.

---

## 5. Support desk, documentation, operations

**Platform Support Desk — AVAILABLE for signed-in customers, ungated and never sold**
(`app/javascript/dashboard/routes/dashboard/help/help.routes.js:15-25`). Customer paths:
`/app/accounts/:accountId/help/tickets{,/new,/:id}`.

**But it cannot be a public link.** The path needs the visitor's own numeric account id, and there is **no
post-login return destination**: the SPA guard discards the requested path (`app/javascript/dashboard/routes/index.js:21-24`)
and `getLoginRedirectURL` always resolves to the dashboard (`app/javascript/v3/helpers/AuthHelper.js:40-53`).
A no-exclusion grep for `redirectTo|redirect_to=|returnTo|return_to|afterLogin|next=` across the login and auth
trees returns **zero** hits; the only deep-link mechanism is the SSO conversation pair, which targets a
conversation.

**So the website's support entry point is:** the public, indexable documentation article
`/docs/contact-lynomia-support` (`custom/db/documentation/en/troubleshooting/contact-lynomia-support.md`) plus
the site's own contact form, with "Open a ticket" shown as a sign-in-first action. A one-URL public ticket entry
point is **new work** — either an account-less redirect that resolves the signed-in user's account, or a
path-allowlisted `return_to` on `/app/login`. Neither exists; `raise_on_open_redirects` is on
(`config/application.rb:39`), so any new mechanism must be relative-path-only.

**Do not confuse the two desks.** `config/routes/support.rb` is the *tenant's own* helpdesk for *their* end
users (`/api/v1/accounts/:id/support/tickets`), gated off by default. A public "contact Lynomia" link must never
point there.

**Documentation V2 — AVAILABLE and live.** `/docs`, `/docs/:article_slug`, `/changelog` are stable named routes
(`config/routes/documentation.rb:56,59-61`) resolving to `/hc/lynomia-docs` and `/hc/lynomia-changelog`;
production serves 75 articles on the landing page with a 164-URL sitemap. The corpus is bilingual
(`LOCALES = %w[en ar]`, `custom/app/services/documentation/library.rb:14`). **The binding contract: tenants are
readers, Super Admin is the author, and the repository is the source of truth for seeded content** — the
website may link to it and must not author into it (`docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md:17-22`).

**Operations / Control Center — internal only.** Its own controller states it is not infrastructure monitoring
(`custom/app/controllers/super_admin/operations_controller.rb:4-6`). **No marketing page.** The requested
`/features/platform-support` page should describe the customer-facing support desk, not this console.

---

## 6. Claim verification — the removal list for the current page

This is the section `01-current-state-audit.md` §4 refers to.

| Claim (line in the served page) | Verdict | Required action |
|---|---|---|
| `uptime · last 90 days 99.98%` (`:768`) | **Fabricated.** No uptime measurement, no SLA with published values, no status page; `/status` and `/uptime` 404 | **Delete.** Do not substitute another number |
| `backups · daily 03:00 done` (`:767`) | **Unsubstantiated as a schedule.** `config/schedule.yml` has 0 backup/`pg_dump` entries; what exists is a pre-deploy `pg_dump -Fc`, verified readable, last 14 kept (`deployment/deploy.sh:36,126-130,214-224,449-450`) | Delete, or state the truth: a verified backup before every deployment, last 14 retained |
| `encryption · TLS 1.3 + AES-256 active` (`:766`) | **Overstated.** 22 `encrypts` attributes cover credentials and tokens only — not messages, conversations, contacts or attachments; most are conditional on three ENV keys that `.env.example:12-14` ships commented out, and `support_unencrypted_data = true` (`config/application.rb:80`). No disk- or database-level encryption is configured in the repo | Rewrite: "Encrypted in transit with HSTS. Channel credentials and store keys encrypted at rest." |
| `monitoring 24/7` (`:769`) | **Not established** | Delete, or describe the internal operations console |
| "audit log for **every action**" (`:754`, `:758`) | **Refuted by Lynomia's own documentation** — `custom/db/documentation/en/administration/audit-logs.md` tells customers that replying, resolving, labelling and macros leave no entry. The reader is in any case unreachable: `audit_logs` is premium | Delete. Reinstate only as "configuration changes and sign-ins" |
| "full encryption at rest" (`:756`) | **Refuted** (see above) | Rewrite as above |
| `ENTERPRISE SECURITY` / "enterprise-grade" (`:752-753`) | Puffery beside four fabricated readouts, and the Enterprise overlay is permanently absent (`lib/chatwoot_app.rb:19`) | Reword to the substantiated specifics |
| The status panel as a **live readout** (`:763-770`) | Static HTML with pulsing green dots (`:305`) | Remove the live-status framing entirely |
| `تجربة مجانية · بدون بطاقة ائتمانية` (`:784`) | Not deliverable: no plan row, trial plan id nil | Replace with a demo/quote request |
| AI auto-replies 24/7 (`:448`, `:546`, `:590`) | **Materially false** (§3) | Rewrite to the agent-assist truth with its gate |

### 6.1 What the security section CAN say, every clause sourced

Role-based access control with administrator, agent and optional custom permission sets; strict tenant
isolation, with cross-account requests answering 404 before any policy runs
(`docs/documentation-v2/P0-PRODUCTION-HARDENING.md:250-257`); HTTPS with HSTS; channel credentials and commerce
store keys encrypted at rest with Active Record Encryption; credentials never written to the audit trail; a
tamper-resistant audit trail of configuration changes and sign-ins that an audited party cannot switch off,
retained 365 days with a 30-day floor; IP addresses coarsened to a network and never geolocated; a verified
database backup taken and checked before every deployment with the last 14 retained; and a documented rollback
runbook (`deployment/ROLLBACK.md`, `deployment/INCIDENT.md`).

**No certification may be claimed** — no SOC 2, ISO 27001, GDPR-compliance, PCI or HIPAA artefact exists, there
is no DPA and no sub-processor list, and `SECURITY.md` is still upstream Chatwoot's disclosure policy pointing at
`security@chatwoot.com`. **No data-residency or hosting-region claim may be made** — nothing in the repository
states where the service runs. If a `/security` page is built it has **no documentation article to link to**;
writing one into the corpus is the honest prerequisite.

---

## 7. Growth, automation, analytics, commerce, developer

| Area | Verdict | The condition a page must state |
|---|---|---|
| Live-chat (ongoing) campaigns | **AVAILABLE** | website inbox; administrator |
| One-off SMS campaigns | **CONDITIONAL** | an SMS inbox exists |
| **WhatsApp template campaigns** | **CONDITIONAL** | `whatsapp_campaign` flag **default off** (`config/features.yml:204-206`) + WhatsApp **Cloud** provider + an approved template |
| Per-recipient delivery reporting | **AVAILABLE** once a campaign exists | — |
| Per-campaign send limits / suppression lists | **do not exist** — the corpus says so plainly | never imply them |
| Audiences (shared contact filters) | **AVAILABLE** | there is no `audiences` table; an audience is a shared contact filter |
| WhatsApp template manager (sync, submit, status, variables, starter gallery, multi-WABA) | **AVAILABLE** | a WhatsApp Cloud inbox |
| Automation rules (5 triggers, 19 conditions, 20 actions) | **AVAILABLE** | administrator |
| Delayed automation | **CONDITIONAL** | `delayed_automations` **default off** |
| **Flow Builder** (visual, 22 node types) | **CONDITIONAL** | `lynomia_flow_builder` **default off** + administrator + **WhatsApp Cloud only** |
| Analytics: Overview, Conversations, WhatsApp, Campaigns, Automations, Flows | **AVAILABLE** | `reports`; administrator or `report_manage` |
| Commerce + Tickets dashboards | **CONDITIONAL** | the underlying modules are off by default |
| Analytics CSV export | **does not exist** | never imply it |
| Revenue / GMV reporting | **does not exist by design** | never imply it |
| Contact activity timeline | **AVAILABLE** | any agent who may open the contact |
| CSAT | **AVAILABLE**; CSAT CSV export AVAILABLE | — |
| **Commerce: WooCommerce / Salla / Zid / Shopify** | **all CONDITIONAL**, three of four installation switches **off by default**, and order actions are **PRE-UAT-locked** with in-repo production verdicts of **NO-GO** for Salla, Zid and Shopify | an `/integrations` directory may list four providers; each page must state the gate, and **order actions must not be advertised** |
| REST API with OpenAPI 3.1 spec at `/swagger`, three auth schemes | **AVAILABLE** | — |
| Outbound webhooks, 12 events, HMAC-signed | **AVAILABLE** | — |
| Dashboard apps; widget/JS SDK | **AVAILABLE** | — |
| API docs for the Lynomia-specific endpoints (flows, commerce, templates, analytics, support, billing) | **do not exist** | an API page may promise the documented core only |
| Webhook events for commerce, campaigns, flows, templates, tickets | **do not exist** (`app/models/webhook.rb:32-34`) | never imply them |

---

## 8. Page decisions — what may be built, and what must not

**Build now (verified, no blocking gate):** `/features/unified-inbox`, `/features/team-collaboration`,
`/features/auto-assignment`, `/features/contact-management`, `/features/custom-attributes`,
`/features/canned-responses`, `/features/macros`, `/features/business-hours`,
`/features/customer-satisfaction`, `/features/automation`, `/features/campaigns`, `/features/audiences`,
`/features/analytics`, `/features/api-webhooks`, `/features/platform-support`, and the nine channel pages.

**Build with the condition stated on the page:** `/features/ai-assistant`, `/features/translation`,
`/features/chatbots` → rename to agent bots only, `/features/flow-builder`, `/integrations` plus four provider
pages, `/features/security` (built strictly from §6.1).

**Do not build:** `/features/ai-agents`, `/features/sla-management` (as a conversation feature),
a Twitter/X or voice channel page, a 360dialog page, a pricing page with numbers, any page implying analytics
export, revenue reporting, campaign suppression lists, or commerce order actions.

**Documentation links are available for most pages** — the corpus has 69 EN articles across 12 sections, and
each row above has its matching slugs recorded in the working notes. The two areas with **no** article to link
are **pricing/billing** and **security/trust**; both need corpus articles written before their pages can cite
anything.
