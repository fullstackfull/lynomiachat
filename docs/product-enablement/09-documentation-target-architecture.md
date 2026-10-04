# 09 — Lynomia Documentation Center: target architecture

Brief parts covered: **7** (Documentation Center) and **25** (can the existing Help Center serve global product docs?).
Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`. Discovery only — nothing in this
document has been built. Every claim carries a `path:line`; anything I could not verify in the repo is labelled
**UNVERIFIED**.

Classification vocabulary used throughout: **REUSE** / **EXTEND** / **PATCH** / **NEW PRIMITIVE REQUIRED** / **DO NOT CREATE**.

---

## 1. Part 25 answered

> **Can the existing Help Center (Portal → Category → Article) serve as global Lynomia product documentation, managed from Super Admin?**

### **YES, WITH EXTENSION — AND NO MIGRATION IS NEEDED.**

One Portal, owned by one internal Lynomia account, published at `/hc/<slug>`, authored through new
Administrate dashboards in Super Admin. Everything that path needs is a code change: routes, three
`Administrate::BaseDashboard` subclasses, two sidebar-icon entries, one slug-reservation validation, and one
hard-coded-string patch. No schema change, no data move, no new table.

The answer rests on two facts, both re-verified against the repo for this document.

### Decisive fact 1 — Portal is hard-scoped to an account, and that does not matter

`portals.account_id` is `t.integer "account_id", null: false` (db/schema.rb:1540), backed by `belongs_to :account`
(app/models/portal.rb:33) and `validates :account_id, presence: true` (app/models/portal.rb:42). Articles and
categories mirror it — `articles.account_id` NOT NULL (db/schema.rb:203), `categories.account_id` NOT NULL
(db/schema.rb:609) — and derive it from the portal rather than from the request
(`ensure_account_id`, app/models/article.rb:56,221).

So there is no accountless portal, and **there is no global/system portal concept anywhere**: the verifier's grep for
`global_portal|system_account|internal_account|docs_portal|is_global|system_owned` across `app`, `enterprise`,
`custom`, `config` and `lib` returns nothing (verdict-help-center-global-docs.json, decisive question 3). The only
accountless content record in the schema is `platform_banners` (db/schema.rb:1531-1537).

Building a *truly* accountless portal is the path we are rejecting. Its cost, itemised:

| Work item | Evidence |
|---|---|
| Migration to drop `NOT NULL` on three columns | db/schema.rb:1540 (portals), :203 (articles), :609 (categories) |
| Relax three presence validations | app/models/portal.rb:42, plus the account presence implied by `belongs_to` on Article/Category |
| Rework two `ensure_account_id` callbacks | app/models/article.rb:221-223, app/models/category.rb:88-90 |
| Rework six account-scoped lookups | portals_controller.rb:10, :19, :75; articles_controller.rb:91; categories_controller.rb:47; articles/bulk_actions_controller.rb:44 (all `Current.account.portals…`) |

**Classification: DO NOT CREATE.** An accountless portal buys nothing the single-internal-account design does not
already give, and it is the only variant that needs a migration.

### Decisive fact 2 — the public read path is already global, and is not blocked on a branded install

No account appears anywhere in the public URL space. Every `/hc` route is keyed on the portal slug
(config/routes.rb:649-661), and resolution is a bare global lookup:

```ruby
@portal ||= Portal.find_by!(slug: params[:slug], archived: false)   # app/controllers/public/api/v1/portals_controller.rb:26
```

The same global lookup is in `Public::Api::V1::Portals::BaseController` for article, category and search pages.
Uniqueness is what makes it safe: `portals.slug` UNIQUE (db/schema.rb:1556), `portals.custom_domain` UNIQUE
(db/schema.rb:1555), `articles.slug` **globally** UNIQUE (db/schema.rb:226).

The guard that the first inventory pass read as a blocker is not one. `ensure_custom_domain_request`
(app/controllers/public_controller.rb:9-20) returns early when `DomainHelper.chatwoot_domain?` is true, and that
predicate **does not test for a Chatwoot domain despite its name**:

```ruby
def self.chatwoot_domain?(domain = request.host)
  [URI.parse(ENV.fetch('FRONTEND_URL', '')).host, URI.parse(ENV.fetch('HELPCENTER_URL', '')).host].include?(domain)
end
# app/controllers/concerns/domain_helper.rb:2-4
```

It compares the request host against **this install's own** `FRONTEND_URL` / `HELPCENTER_URL`. A Lynomia-branded
install serving from its own configured host passes the guard. Nothing about the Lynomia brand blocks `/hc/<slug>`.

The flip side is a **deployment prerequisite, not a code gap**: if neither env var is set, or neither matches the
serving host, `URI.parse('').host` is `nil`, the list is `[nil, nil]`, and every portal page returns 401 with a
hard-coded `support@chatwoot.com` message (public_controller.rb:16-19). `HELPCENTER_URL` is already read in three
other places (lib/chatwoot_app.rb:36-37, app/mailers/portal_instructions_mailer.rb:26,
app/views/layouts/vueapp.html.erb:37), so this is an existing, documented knob.

The account feature gate is also not in the way on a self-hosted install: `ensure_portal_feature_enabled` returns
immediately `unless ChatwootApp.chatwoot_cloud?` (public_controller.rb:22-23), and `help_center` ships
`enabled: true` anyway (config/features.yml:42-45).

### What the extension actually consists of

| Piece | Classification | Why |
|---|---|---|
| One Portal + categories + articles in one internal account | **REUSE** | Account-scoped write path (config/routes.rb:439-459) and global read path (config/routes.rb:649-661) both already work |
| Super Admin Portal/Category/Article management | **EXTEND** | Administrate resource pattern is proven in-tree by `custom/` billing (§5) |
| Portal slug reservation | **EXTEND** | Mirrors `Article::RESERVED_SLUGS` (app/models/article.rb:61,67); no equivalent exists for Portal (§2) |
| `support@chatwoot.com` in the public 401 | **PATCH** | app/controllers/public_controller.rb:18 |
| `PATCH /portals/:id/archive` | **PATCH** | `@portal.update(archive: true)` vs column `archived` (app/controllers/api/v1/accounts/portals_controller.rb:44 vs db/schema.rb:1551) — only matters if Super Admin exposes archive |
| Article revision trail | **EXTEND** | `audits` table already exists; model change only (§6) |
| Accountless "global portal" | **DO NOT CREATE** | Needs the migration above and buys nothing |
| In-product changelog / release notes | **NEW PRIMITIVE REQUIRED** | No `changelog` or `release_note` table in db/schema.rb; a migration is required, so it is out of scope and left for approval (§7) |

---

## 2. The risk this design depends on: portal slugs are an unreserved global namespace

**This is the one finding that can break the recommendation, and it is not theoretical.**

Portal slug validation is a bare uniqueness check with no reservation list:

```ruby
validates :slug, presence: true, uniqueness: true    # app/models/portal.rb:44
```

There is no `Portal::RESERVED_SLUGS`. A repo-wide grep for `RESERVED_SLUGS` across `app`, `enterprise`, `custom`,
`lib` and `config` returns exactly two lines, both Article's:

```
app/models/article.rb:61:  RESERVED_SLUGS = %w[search articles categories].freeze
app/models/article.rb:67:  validates :slug, exclusion: { in: RESERVED_SLUGS }
```

Because `portals.slug` is globally unique (db/schema.rb:1556) and first-come-first-served, **any tenant account can
take the slug Lynomia wants for its product docs**. Worse, tenant onboarding reaches for exactly the obvious
candidates automatically:

```ruby
def slug_candidates
  base = @account.name.to_s.parameterize.presence
  return [] if base.blank?
  first_token = base.split('-').first
  [base, first_token, "#{first_token}-docs", "#{first_token}-help"].uniq
end
# enterprise/app/services/onboarding/help_center_creation_service.rb:117-124
```

`generate_slug` (:114-116) picks the first candidate for which `Portal.exists?(slug:)` is false, and
`@account.portals.create!` (:14) claims it, driven end to end from
`Enterprise::Api::V1::Accounts::OnboardingsController#create_help_center`
(enterprise/app/controllers/enterprise/api/v1/accounts/onboardings_controller.rb:9-23). An account named "Docs" or
"Help" will squat `docs` / `help` on its first onboarding run, with no human in the loop.

### What must be done

**Reserve the docs slug at the model, and teach the onboarding generator the same list.**

1. Add a `Portal::RESERVED_SLUGS` constant plus `validates :slug, exclusion: { in: RESERVED_SLUGS }`, mirroring
   app/models/article.rb:61,67 exactly. The model validation is the single shared entry point — all three creation
   paths (`Current.account.portals.build` at portals_controller.rb:19, onboarding's `create!` at
   help_center_creation_service.rb:14, and console) run through it, so no downstream guard is needed.
   **Classification: EXTEND.**
2. Filter `slug_candidates` against the same constant
   (enterprise/app/services/onboarding/help_center_creation_service.rb:117-124). This is **not** a duplicate guard:
   the generator *produces* the value, so without it an account named "Docs" would generate a reserved candidate and
   onboarding would raise `ActiveRecord::RecordInvalid` on `create!`. **Classification: PATCH** (the generator is
   currently correct only by accident).
3. Claim the slug before this ships. Until (1) lands, the only protection is that the row exists first.

**Do not** rely on `custom_domain` instead. It is unique (db/schema.rb:1555) and would sidestep the slug race, but
`PortalsController#update` has the `custom_domain` assignment commented out (portals_controller.rb:31), so it is
create-only from the API, and the DNS-instructions dialog prints the wrong hostname (§7).

### Two unguarded public endpoints

`ensure_custom_domain_request` is applied selectively, not to "the public path":

| Endpoint | Guard | Status |
|---|---|---|
| `portals#show` | `only: [:show]` (public/api/v1/portals_controller.rb:4) | guarded |
| `portals#sitemap` | not in the `only:` list (same line) | **serves on any host that reaches the app** |
| `articles#tracking_pixel` | `only: [:show, :index, :show_markdown]` (public/api/v1/portals/articles_controller.rb:2) | **unguarded** |

For a public docs portal this is low severity — the content is meant to be public — but it means the sitemap of the
docs portal is reachable from any host, including a tenant's custom domain. Note it in the runbook; no change
required for v1. **Classification: REUSE as-is.**

---

## 3. Part 7.2 — information architecture, derived from the capability inventory

Rule applied: **every area below maps to code that exists in this repo.** Areas the brief's example list implies but
the inventory does not support are listed as DO NOT CREATE at the end, because a docs tree that advertises a
non-existent capability is worse than one that omits it.

| # | Area | Anchored in | Classification |
|---|---|---|---|
| 1 | Getting started, roles and permissions | Pundit with a `{user, account, account_user}` context; two-value base role; 7 custom-role permissions at enterprise/app/models/custom_role.rb:37-48 | REUSE |
| 2 | Inboxes and channels | `Channel::Whatsapp::PROVIDERS = %w[default whatsapp_cloud]` — exactly two WhatsApp providers; channel flags in config/features.yml:17-289 | REUSE |
| 3 | Conversations: status, priority, assignment, handoff | `bot_handoff!`; assignment V1/V2; `Conversations::MessageWindowService` | REUSE |
| 4 | Contacts: list, search, import, bulk actions | `Contacts::ViewScope` (app/services/contacts/view_scope.rb:16-68); bulk vocabulary is exactly add-labels / remove-labels / delete (app/services/contacts/bulk_action_service.rb:42-48) | REUSE |
| 5 | Labels | `labels` table (db/schema.rb:1359) | REUSE |
| 6 | Audiences (saved shared contact filters) | `custom_filters.shared` (db/schema.rb:1113); membership re-evaluated, never stored | REUSE |
| 7 | Automations | 12 triggers, 20 actions (see §4 and AUTHORITATIVE-CORRECTIONS §1) | REUSE |
| 8 | Macros | `enum visibility: { personal: 0, global: 1 }` (app/models/macro.rb:29) | REUSE |
| 9 | Flows (Flow Builder) | 21 node types in `Flows::NodeTypes::TYPES` (custom/app/services/flows/node_types.rb:9-34); `flow_versions` (db/schema.rb:1254), `flow_sessions` (db/schema.rb:1232) | REUSE |
| 10 | Campaigns | `enum campaign_type: { ongoing: 0, one_off: 1 }` (app/models/campaign.rb:50); `campaigns` table (db/schema.rb:428) | REUSE |
| 11 | WhatsApp templates | `channel_whatsapp.message_templates` jsonb — no template table, no template model | REUSE |
| 12 | Commerce | four providers under `custom/`; `commerce_order_manage` permission (enterprise/app/models/custom_role.rb:26,44) | REUSE |
| 13 | The tenant's own Help Center | Portal/Category/Article as the **tenant** uses it — distinct from this docs portal, and the distinction must be stated in the article itself | REUSE |
| 14 | Reports | report flags in config/features.yml:17-289 | REUSE |
| 15 | Account administration and billing | `custom/app/models/billing_plan.rb`; Super Admin billing routes at config/routes/billing.rb:4-19 | REUSE |
| 16 | Starter library (audience presets, automation recipes, flow templates) | 22 recipes across three static client-side catalogues; no recipes table, endpoint or model anywhere | REUSE |
| 17 | Platform operations (Super Admin) | config/routes.rb:728-761 | **Internal-only area — not published in the tenant-facing tree** |

Three navigational rules fall out of the inventory and should be enforced in the tree itself, not left to authors:

- **Areas 6 and 5 must be adjacent and cross-linked**, because Label-vs-Audience is the top confusion (§4).
- **Areas 7, 8, 9 must be one cluster with a single disambiguation landing page**, not three sibling trees.
- **Area 13 must sit under Settings, not next to areas 1-12**, or readers will conflate "the Help Center you
  configure" with "the docs you are reading."

### Areas to DO NOT CREATE

| Proposed area | Why not | Evidence |
|---|---|---|
| Abandoned cart | **No capability exists.** Zero `cart` lines in db/schema.rb; cart is a `Data.define` cached in Redis only (FRESH_FOR 120s / KEEP_FOR 24h), the cache is **deleted** not staled on webhooks, and there is no transition engine, trigger or condition | AUTHORITATIVE-CORRECTIONS §9 (verified independently) |
| "Conversation Workflows" as an engine | Zero tables matching `/workflow/` in db/schema.rb; no `Workflow` class in `app`, `enterprise`, `custom` or `lib`. The settings page is a container rendering two unrelated, independently-flagged features | conversation_workflows.json |
| Changelog / release notes | No authoring storage; the sidebar card is a read-only consumer of `https://hub.2.chatwoot.com/changelogs`, additionally gated to `isOnChatwootCloud && !isACustomBrandedInstance`, so it does not render on Lynomia at all | help_center.json gaps; app/javascript/shared/constants/links.js:11 |
| Static audience membership / "add these contacts to an audience" | Architecturally impossible as a direct write: an audience stores only a `query` jsonb (db/schema.rb:1105-1116) and there is no contact `id` filter key | AUTHORITATIVE-CORRECTIONS §9 |

---

## 4. Part 7.3 — the per-feature article template

Nine sections, every one mandatory. An article that omits one is incomplete, because the omitted ones are precisely
where this product's sharp edges live.

```
# <Feature>

WHAT IT IS            One paragraph. The object, the table it lives in, who owns it.
WHEN TO USE           2-5 bullets, each a real situation.
WHEN NOT TO USE       The sibling feature that fits better, named and linked. MANDATORY.
HOW TO CONFIGURE      Numbered UI path from the dashboard root. No API-only steps in this section.
EXAMPLES              At least one worked end-to-end example with real field values.
LIMITATIONS           What silently does not work. Sourced from code and tests, not from intent.
PERMISSIONS           Base role AND the custom-role permission, if any. Both, always.
PROVIDER REQUIREMENTS What the channel/store must support. "None" is a valid answer and must be written.
RELATED               Links, including the one in WHEN NOT TO USE.
```

Two section-level rules:

- **LIMITATIONS is derived from code and tests, never from the feature's intent.** Half the live defects below are
  invisible from the UI.
- **PERMISSIONS always names both layers.** A custom role *replaces* the base role — `custom_role.present? ?
  (custom_role.permissions + ['custom_role']) : super`, with `super` **not** merged
  (enterprise/app/models/enterprise/account_user.rb:1-5). A custom-role member is therefore neither `agent` nor
  `administrator`, so any page gated `permissions: ['administrator']` is invisible to them regardless of which
  permissions the role holds. An article that lists only "Administrator" is wrong for every custom-role user.

### The eight confusion pairs: the exact WHEN NOT TO USE / LIMITATIONS copy each must carry

| Confusion | The discriminator to lead with | Evidence |
|---|---|---|
| **Label vs Shared Audience** | A label is **stored membership** you put on a contact. An audience is **a stored query** — membership is recomputed on every read and is never stored. Use a label when you need to pick contacts by hand; use an audience when the rule is the thing you want to keep. | `custom_filters.shared` is the whole of "shared" (db/schema.rb:1113); `labels` is a real table (db/schema.rb:1359). LIMITATIONS must say: you cannot add a selected set of contacts to an audience — there is no membership table and no contact `id` filter key. |
| **Automation vs Flow** | An automation fires **once, on an event, and finishes**. A flow is a **conversation that waits** — it holds a session and resumes on the contact's next reply. | `flow_sessions` with one live session per conversation (db/schema.rb:1232); `Flows::NodeTypes::TYPES` marks `wait: true` on `question`, `buttons`, `list`, `delay` (custom/app/services/flows/node_types.rb:12-20,29). |
| **Macro vs Automation** | A macro is **agent-invoked**; an automation is **event-invoked**. Same action vocabulary, opposite trigger model. | `enum visibility: { personal: 0, global: 1 }` (app/models/macro.rb:29); automations are driven by listeners (app/listeners/automation_rule_listener.rb). |
| **Bot vs Flow** | A flow **is** a bot: `AgentBot` with `bot_type: :flow`. A webhook bot posts to your URL; a flow runs in Lynomia. | `enum bot_type: { webhook: 0, flow: 1 }` (app/models/agent_bot.rb:42). LIMITATIONS: Settings → Agent Bots hides flow bots and always posts `bot_type: 'webhook'`, so a flow bot is creatable **only** from Flow Builder; and a flow answers nobody until it has a published `FlowVersion` **and** an `AgentBotInbox`. |
| **Campaign vs Automation** | A campaign is **outbound to a list you chose**. An automation is **reactive to one conversation**. | `enum campaign_type: { ongoing: 0, one_off: 1 }` (app/models/campaign.rb:50). LIMITATIONS: campaign audience is a jsonb list of `{type,id}` **references**, re-resolved at send time — the recipient set is not frozen when you schedule. |
| **Commerce trigger support** | **Read-driven, not webhook-driven.** A provider webhook only invalidates cache. The `commerce_order_*` event fires when something **re-reads** the order. | `Automation::CommerceEvents.dispatch` has exactly **one** call site: custom/app/models/commerce/contact_metric.rb:27. `ContactMetric.record` has exactly **two** callers: custom/app/services/commerce/realtime.rb:93 and custom/app/services/commerce/conversation_panel.rb:62. **The LIMITATIONS line must say: a commerce automation rule may not fire until an agent opens the conversation panel.** Anything softer than that is misleading. |
| **WhatsApp 24-hour window** | Hard-coded 24 hours from the **last inbound** message, for every WhatsApp inbox, with no per-inbox override. | `MESSAGING_WINDOW_24_HOURS = 24.hours` (app/services/conversations/message_window_service.rb:2) returned unconditionally for `Channel::Whatsapp` (:27-28); evaluated as `Time.current < last_incoming_message.created_at + time` (:34-36), and `false` when there is no inbound message at all (:35). Surfaced as `can_reply` (app/models/conversation.rb:149-150) and consumed at MessagesView.vue:488 and ReplyBox.vue:529. WHEN NOT TO USE → outside the window, a template is the only route. |
| **WhatsApp templates** | Templates are **Meta's objects, mirrored verbatim**, not Lynomia objects. One jsonb column, no table, no model. | `channel_whatsapp.message_templates` + `message_templates_last_updated`; `sync_templates` writes Meta's `data` array verbatim via `update_columns`, so the persisted shape is whatever that Graph version returns. |

### Facts the LIMITATIONS sections must carry, because the UI hides them

These are live defects or silent failures confirmed by the verifiers. An article that does not mention them will
generate support tickets.

| Must appear in | Fact | Evidence |
|---|---|---|
| Automations | **`event_name` is not validated.** There is no inclusion validation on `event_name` in app/models/automation_rule.rb — only DB `NOT NULL` (db/schema.rb:313). An arbitrary `event_name` saves successfully via the API and the rule simply never fires. | AUTHORITATIVE-CORRECTIONS §3 |
| Automations | **`attribute_changed` is satisfiable on `conversation_updated` only.** `conversation_created` passes `nil` (conversation.rb:328); opened/resolved pass `status_change` (:385); `message_created` dispatches no `changed_attributes` at all (app/models/message.rb:380) while the listener reads `event.data[:changed_attributes]` (app/listeners/automation_rule_listener.rb:24). Flow Builder rejects it outright (custom/app/services/flows/node_validator.rb:230). | AUTHORITATIVE-CORRECTIONS §4 |
| Automations | **`sla_policy_id` is a dead condition key.** Accepted by the EE model; no `filter_keys.yml` entry, no SQL branch, no UI. A rule using it never matches and is auto-disabled after two evaluations. | AUTHORITATIVE-CORRECTIONS §5 |
| Automations | **20 actions, not 14.** Including `send_message`, `send_attachment`, `send_webhook_event`, plus `add_sla` (enterprise/app/models/enterprise/automation_rule.rb:6-8, UI only when `isCloudFeatureEnabled('sla')`) and the Lynomia `send_webhook_event` override that adds a `commerce:{event,store_id,provider,order}` payload (custom/app/services/custom/automation_rules/action_service.rb:4-14). | AUTHORITATIVE-CORRECTIONS §1 |
| WhatsApp templates | **Deleting an approved template locks its name for 30 days** at Meta. The repo's CSAT delete-then-recreate path (`csat_template_management_service.rb:23-35` → `delete_existing_whatsapp_template:181-197`) can therefore strand the CSAT template for 30 days. Treat as a live defect; document it as a hard warning. | AUTHORITATIVE-CORRECTIONS §6 |
| WhatsApp templates | Editable parameters are **category, components and `message_send_ttl_seconds`** only, per Meta's normative template-management page. `sub_category` is a CREATE parameter, not merely readable. | AUTHORITATIVE-CORRECTIONS §6 |
| WhatsApp templates | Template sync pins Graph API **v14.0**, long past Meta's support window. | AUTHORITATIVE-CORRECTIONS §6 |
| WhatsApp templates | Header variable examples are mis-read: `TemplateNormalizer.extractWhatsAppVariables` reads `example.body_text_named_params` (:75) and `example.body_text[0][pos]` (:81) for **both** branches, but Meta's TEXT header uses `header_text_named_params` / `header_text`. | AUTHORITATIVE-CORRECTIONS §6 |
| Contacts | **Export from a search or the online list still exports the whole account.** app/javascript/dashboard/store/modules/contacts/actions.js:202 destructures only `{ payload, label }` and forwards only those, dropping the `q`/`active` that the dialog emits and the controller and job honour. | AUTHORITATIVE-CORRECTIONS §10 |
| Contacts | **"Select all N in this view" is unreachable on a search view.** app/controllers/api/v1/accounts/contacts_controller.rb:183 sets `@contacts_count = results.size` (page size, max 15) on the search path, so `totalItems <= 15` and `canSelectAllMatching` (`totalCount > visible`) can never be true. | AUTHORITATIVE-CORRECTIONS §10 |

**Never cite `quality_score` in any WhatsApp template article.** It was a fabricated citation in the first inventory
pass; `grep -rni quality_score app enterprise custom lib spec config db` returns zero hits. There is no template
quality score in this product.

---

## 5. Part 7.4 — Super Admin management

### Starting position: Super Admin has zero Help Center reach

`namespace :super_admin` (config/routes.rb:728-761) declares `app_config`, `push_diagnostics`, `accounts`, `users`,
`access_tokens`, `installation_configs`, `agent_bots`, `platform_apps`, `platform_banners`, `instance_status`,
`settings`, `account_users` — and nothing else. `app/dashboards/` holds 8 files, `custom/app/dashboards/` holds only
the two billing dashboards, and `enterprise/app/` has no `dashboards` directory at all. No `PortalDashboard`,
`ArticleDashboard` or `CategoryDashboard` exists.

### What Administrate gives for free

`administrate` 0.20.1 (Gemfile:97-99). Declaring a resource in routes plus an `Administrate::BaseDashboard`
subclass yields, with no further code:

| Free | Detail |
|---|---|
| Full CRUD | index / show / new / edit / destroy views |
| Field rendering and form inputs | `Field::String`, `Text`, `Number`, `Boolean`, `Select`, `DateTime`, `BelongsTo`, `HasMany` |
| Search and pagination | `Field::String.with_options(searchable: true)` drives the index search box |
| Sidebar entry | auto-derived from `Administrate::Namespace.new(namespace).resources` (app/views/super_admin/application/_navigation.html.erb:36) against a hard-coded skip list (:37) |
| Strong params | `resource_params` from the dashboard's `FORM_ATTRIBUTES`, overridable (pattern at app/controllers/super_admin/accounts_controller.rb:37-44) |
| Post-save hooks | `after_resource_created_path` / `after_resource_updated_path` (used for Stripe sync at custom/app/controllers/super_admin/billing_plans_controller.rb:22-30) |
| Custom field types | 7 in `app/fields/`, 4 in `enterprise/app/fields/`, 2 in `custom/app/fields/` |

The working in-tree proof is Lynomia's own: `custom/app/dashboards/billing_plan_dashboard.rb:5` +
`custom/app/controllers/super_admin/billing_plans_controller.rb:6` + `config/routes/billing.rb:4-19` (drawn at
config/routes.rb:782). That is the template to copy. **Classification: REUSE.**

### What must be added

| Addition | Classification | Note |
|---|---|---|
| `resources :portals`, `:categories`, `:articles` under `namespace :super_admin` | **EXTEND** | New `config/routes/docs.rb` + a `draw` line, following config/routes/billing.rb |
| `PortalDashboard`, `CategoryDashboard`, `ArticleDashboard` | **EXTEND** | `custom/app/dashboards/` keeps them out of the OSS tree, as billing does |
| Three entries in the `sidebar_icons` hash | **PATCH** | app/views/super_admin/application/_navigation.html.erb:14-21 — **the icon renders blank without this**, which is exactly how `billing_subscriptions` looks today |
| A rich-text or Markdown field for `articles.content` | **EXTEND** | Administrate's `Field::Text` is a bare textarea. The dashboard editor is a Vue component (`components-next/HelpCenter/Pages/ArticleEditorPage/`) and is not reachable from Administrate |
| Article `status` as `Field::Select` | **EXTEND** | Collection from `Article.statuses` — `enum status: { draft: 0, published: 1, archived: 2 }` (app/models/article.rb:73) |
| A docs-portal scope on the index | **EXTEND** | Override `scoped_resource` (the hook is documented at app/controllers/super_admin/accounts_controller.rb:22-30) so the Articles index shows the docs portal only, not all 12 areas × every tenant's Help Center |
| `PATCH /portals/:id/archive` fix | **PATCH** | app/controllers/api/v1/accounts/portals_controller.rb:44 — required only if the dashboard exposes archive as an action |

**Recommendation on the authoring surface:** author in **Super Admin only**, and treat the Administrate forms as the
sole write path for the docs portal. Do not also wire the Vue article editor to the docs portal. The Vue editor is
account-scoped by construction (`Current.account.portals.find_by!(slug:)` at articles_controller.rb:91), so reaching
it means giving someone an `AccountUser` row on the docs account — which is precisely the thing §5.1 says not to do.
A plain textarea is the price of not opening that door; a Markdown preview field is the mitigation.

### 5.1 The key question: Portal is account-scoped, so whoever owns the internal account can edit the docs

This is the real access-control problem, and Pundit does not solve it.

The write policies are account-membership-plus-role, nothing more:

```ruby
def index?;  @account.users.include?(@user); end   # app/policies/article_policy.rb:2-4
def update?; @account_user.administrator?;   end   # app/policies/article_policy.rb:6-8
```

`PortalPolicy` is the same shape (app/policies/portal_policy.rb:1-37), and EE widens Article and Category writes to
the `knowledge_base_manage` custom-role permission, with Portal widened only on `update?`/`edit?`/`logo?` —
`create?` and `destroy?` stay administrator-only (enterprise/app/policies/enterprise/portal_policy.rb:1-13).

So the exposure is exact and statable as an invariant:

> **Anyone holding an `AccountUser` row on the docs account with role `administrator`, or with the
> `knowledge_base_manage` custom-role permission, can edit global Lynomia product documentation.**
> Nobody else can, because every dashboard read and write resolves through `Current.account.portals`
> (portals_controller.rb:10,19,75; articles_controller.rb:91; categories_controller.rb:47;
> articles/bulk_actions_controller.rb:44).

The enforcement therefore is not a policy change. It is **membership**:

1. **Keep the docs account at zero `AccountUser` rows.** This is a legal state: `Account` validates only `name`
   presence (app/models/account.rb:44) and `has_many :users, through: :account_users`
   (app/models/account.rb:64,102) with no minimum. Super Admin's `accounts` resource is plain Administrate CRUD
   (config/routes.rb:737-740), so the account can be created without a member. With zero members, `index?` is false
   for every user on the planet and the tenant-facing Help Center UI is unreachable for the docs portal — by
   construction, not by convention. **Classification: REUSE** (an existing property of the model, used
   deliberately).
2. **Super Admin is the only authoring path**, which is consistent with (1): the Administrate controllers inherit
   `SuperAdmin::ApplicationController` with `before_action :authenticate_super_admin!`
   (app/controllers/super_admin/application_controller.rb:14) and do not consult `Current.account` at all.
3. **Make the zero-membership invariant explicit and checkable.** `resources :account_users, only: [:new, :create,
   :show, :destroy]` (config/routes.rb:761) is the one way an `AccountUser` row gets created from Super Admin, and
   it is deliberately absent from the sidebar (the `next if` skip list at
   app/views/super_admin/application/_navigation.html.erb:37). The invariant should be asserted by the docs runbook
   and, ideally, by a guard on the docs account. **Classification: EXTEND** — I am not proposing the guard's shape
   here; the operational invariant alone is sufficient for v1 and does not need code.

**The residual risk, stated plainly:** Super Admin has no finer-grained role. There is no Pundit and no per-resource
authorization anywhere in the `super_admin` namespace, `SuperAdmin` is an STI subclass of `User` in the same `users`
table, and Sidekiq Web is mounted behind the same single gate (config/routes.rb:762-764). **Every super admin can
edit the product documentation, and that cannot be narrowed without a new authorization layer.** For a small
internal team this is acceptable and is already the accepted risk for billing plans and installation configs. If it
is not acceptable, the required primitive is a super-admin role model — **NEW PRIMITIVE REQUIRED**, and it needs
storage, so it is out of scope and left for approval.

---

## 6. Part 7.5 — article versioning

### No migration is needed. The question is whether the model change is worth making.

The generic polymorphic `audits` table already exists, with everything a revision trail needs:

```
auditable_id / auditable_type      db/schema.rb:265-266
audited_changes  (jsonb)           db/schema.rb:273
version          (integer, def 0)  db/schema.rb:274
user_id / user_type / username     db/schema.rb:269-271
action, created_at                 db/schema.rb:272, :278
index (auditable_type, auditable_id, version)  db/schema.rb:286
```

The gem is in the Gemfile — `gem 'audited', '~> 5.4', '>= 5.4.1'` (Gemfile:184) — and the repo's own subclass is
`class Enterprise::AuditLog < Audited::Audit` (enterprise/app/models/enterprise/audit_log.rb:29). Twelve models are
already audited under `enterprise/app/models/enterprise/audit/`; `Article`, `Portal` and `Category` are not.

The established convention for adding one, from Lynomia's own tree:

```ruby
audited associated_with: :account, if: :contact? if defined?(Enterprise::AuditLog)
# custom/app/models/custom/audit/custom_filter.rb:8
```

### Verdict: worth it for the trail, with a column allow-list. Not worth it for restore in v1.

**Why yes.** It is one line in one concern, with no migration and no new UI, and it answers the only question that
actually gets asked about a docs change — *who changed this, when, and what did it say before*. The read surface
already exists: `Api::V1::Accounts::AuditLogsController` paginates `Current.account.associated_audits` with
auditable-type, user-search and date-window filters
(enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb:28-33). Adding
`audited associated_with: :account` to `Article` makes article changes appear there for free.
**Classification: EXTEND.**

**Why with an allow-list, not naively.** `articles` carries `content` (text) plus a `draft_content` autosave buffer
(db/schema.rb:209,221). Auditing all columns means every autosave writes a full copy of the article body into
`audits`. The audit should cover `title`, `content`, `status`, `category_id`, `locale` and `meta` on `update` and
`destroy`, and must **exclude** `draft_title` and `draft_content`. Without that, this is a storage-growth bug
dressed as a feature.

**Why not restore, in v1.** `audited` stores *changes*, not snapshots, and nothing in this repo reconstructs a prior
version: the audit-logs controller is read-only and paginated, and there is no restore endpoint, job or UI. A
"restore this version" button is therefore **new UI plus a reconstruction service** — not free, and not justified by
the volume of global docs edits one internal team will make. **Classification for restore-to-version: DO NOT CREATE
in v1.**

**One prerequisite the product owner must decide.** The audit-log read page is gated on
`Current.account.feature_enabled?(:audit_logs)`
(enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb:62-64), `audit_logs` is premium
(enterprise/config/premium_features.yml:2-10), and `Internal::ReconcilePlanConfigService` runs
`account.disable_features!(*premium_features)` over **every** account whenever
`ChatwootHub.pricing_plan == 'community'` — which is the seeded default
(enterprise/app/services/internal/reconcile_plan_config_service.rb:1-58, driven daily via
`Enterprise::Internal::CheckNewVersionsJob`). So on a community-plan install the audit rows would be written and
the viewer would be dark. The trail is still worth writing (it is the data that cannot be recovered later), but the
*viewer* depends on resolving the plan-reconciliation problem documented in `07-branding-audit.md`.

---

## 7. Part 7.6 — contextual help: replacing the hard-coded `chwt.app` table

### Today: two parallel tables, one dead, one pointing at Chatwoot

| Surface | State |
|---|---|
| `FEATURE_HELP_URLS` in app/javascript/dashboard/helper/featureHelper.js:2-29 | 25 entries, 24 on `chwt.app` + one `www.chatwoot.com` article link (:22-23). Read by `getHelpUrlForFeature` (:33-36) at exactly two call sites: BaseSettingsHeader.vue:42 and captain/pageComponents/overview/QuickLinks.vue:26 |
| `help_url` keys in config/features.yml (14 URLs, e.g. :45, :49) | Serialised by `ApplicationHelper#feature_help_urls` (app/helpers/application_helper.rb:6-11) into `window.chatwootConfig.helpUrls` (app/views/layouts/vueapp.html.erb:58) — and **`grep -rn "helpUrls" app/javascript` returns zero hits.** Emitted into the HTML of every dashboard page, read by nothing |

And the links that do exist are invisible on Lynomia. `BaseSettingsHeader` wraps the "Learn more" anchor in
`<CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">` (BaseSettingsHeader.vue:78-91), which hides its
slot when `isACustomBrandedInstance` — defined as `installationName !== 'Chatwoot'`
(app/javascript/shared/store/globalConfig.js:67) — is true. `INSTALLATION_NAME` is already `'Lynomia chat'`
(config/installation_config.yml:17-58). **Net effect today: Lynomia ships no contextual help links at all on
settings pages, and one ungated Chatwoot link on the Captain overview tile (QuickLinks.vue:26).**

### The mechanism to reuse

**Reuse the server-side pipe that already exists and is already wired to the browser:
`config/features.yml` `help_url` → `ApplicationHelper#feature_help_urls` (app/helpers/application_helper.rb:6-11) →
`window.chatwootConfig.helpUrls` (app/views/layouts/vueapp.html.erb:58).** It is built, shipped on every page load,
and currently has no consumer — which makes it free to repurpose.

| Step | Classification |
|---|---|
| Change `config/features.yml` `help_url` values from absolute `chwt.app` URLs to **docs slugs** (e.g. `help_url: automations`) | **PATCH** |
| Make `getHelpUrlForFeature` read `window.chatwootConfig.helpUrls` and compose `<docs base>/<slug>`, instead of a hard-coded table | **PATCH** — keep the existing hyphen→underscore key normalisation (featureHelper.js:31-35), which the code comments note is a real call-site mismatch |
| Delete `FEATURE_HELP_URLS` (featureHelper.js:2-29) once the consumer reads the server values | **PATCH** — removes the duplication defect; two tables that disagree is the current state |
| Hold the docs base in configuration, not in code | **REUSE** — `GlobalConfigService.load` / `InstallationConfig` is the existing mechanism (lib/global_config_service.rb, lib/global_config.rb), the same one that already carries all ten branding keys. `HELPCENTER_URL` (lib/chatwoot_app.rb:36-37) is the natural host source |
| Remove the `CustomBrandPolicyWrapper` suppression at BaseSettingsHeader.vue:78 | **PATCH** — it exists to hide *Chatwoot's* links from branded installs. Once the links are Lynomia's, the gate is actively harmful: it is what makes the product helpless today |
| Add the missing feature→article entries | **EXTEND** — the 25 existing keys do not cover Flows, Audiences, Commerce or Contacts bulk actions, i.e. four of Lynomia's own areas (featureHelper.js:2-29) |

### Two collateral items, both user-visible today

| Item | Evidence | Classification |
|---|---|---|
| The category Slug help text tells operators their portal lives on `app.chatwoot.com/hc/...` — 167 occurrences across locales | app/javascript/dashboard/i18n/locale/en/helpCenter.json:433, :464, :701 | **PATCH** (EN only; other locales via Crowdin) |
| The DNS dialog prints `chatwoot.help` as the CNAME target directly above the **real** computed value — 55 occurrences | string at helpCenter.json:937; dialog at DNSConfigurationDialog.vue:100-113 with the real value computed at :35-41 from `window.chatwootConfig.helpCenterURL \|\| hostURL`. The mailer does this correctly (app/mailers/portal_instructions_mailer.rb:21-29) | **PATCH** — interpolate the computed domain, as the mailer does |
| An E2E test asserts the old URL and will fail on the link change | `await expect(learnLink).toHaveAttribute('href', 'https://chwt.app/hc/agents')` — tests/playwright/tests/e2e/ui/agent-onboarding-flow-ui-validation.spec.ts:31 | **PATCH** — must be updated in the same change |

---

## 8. Copyright constraint on the implementation phase

**Lynomia product documentation must be written from this repository's current code, behaviour and tests. It must
never be copied, adapted or paraphrased from Chatwoot's documentation.**

This is a constraint on the implementation phase, not a style note, and it has three operational consequences:

1. **Every article's LIMITATIONS and PROVIDER REQUIREMENTS sections must be derived from a `path:line`.** Chatwoot's
   docs describe upstream Chatwoot. This install diverges materially — 21 Flow node types, 7 `commerce_order_*`
   triggers, read-driven commerce events, the `commerce_order_manage` permission, the Lynomia billing-plan feature
   layer, `custom_filters.shared` — none of which exists upstream. Copied text would be wrong, not just
   derivative.
2. **No `chwt.app` or `chatwoot.com/hc` link may be used as a source or a destination.** The whole point of §7 is
   to stop pointing at Chatwoot's documentation; replacing the links while copying the prose behind them defeats
   it.
3. **The work must be authored, not migrated.** There is no prior Help Center discovery doc in this repo — `ls docs/`
   returns `audience, automation, campaigns, chatwoot-upgrade, commerce, contacts, flow-builder,
   rails_upgrade_assessment.md, rails_upgrades, ui-modernization, usability, whatsapp-business, whatsapp-qr` — so
   there is no internal corpus to lift from either. Articles are new writing against verified behaviour, reviewed
   against a `path:line` the way this document is.

---

## 9. Items requiring approval, and what I did not verify

### Needs a migration — therefore out of scope, stated and left for approval

| Requirement | Why a migration | Evidence |
|---|---|---|
| In-product changelog / release notes | No `changelog` or `release_note` table exists in db/schema.rb. The only accountless content record is `platform_banners` (db/schema.rb:1531-1537) — a single plain-text message with an info/warning/error type, no title, no link, no scheduling, no per-account targeting and no read state | help_center.json gaps |
| Article scheduling or expiry | `articles` has no `publish_at` / `scheduled_at` / `expires_at` column (db/schema.rb:202-229); `status` is a bare 3-state integer flipped synchronously | app/models/article.rb:73 |
| A super-admin role model (to narrow who can edit docs) | No authorization layer exists in the `super_admin` namespace at all | app/controllers/super_admin/application_controller.rb:7-14 |

### UNVERIFIED

- **Restore-from-audit mechanics.** I verified that nothing in this repo reconstructs a prior article version. I did
  **not** verify what reconstruction helpers the `audited` 5.4 gem itself offers; §6's "restore is new work" verdict
  assumes the repo would have to build the UI either way, which holds regardless.
- **Administrate rich-text field support.** I verified that `custom/app/dashboards/billing_plan_dashboard.rb` uses
  only built-in and custom field types, and that `administrate-field-active_storage` and
  `administrate-field-belongs_to_search` are the only administrate field gems present (Gemfile:97-99). I did not
  establish whether a Markdown-preview field is best built as a custom `app/fields/` type or as a controller-level
  view override.
- **Whether the docs account should hold zero `AccountUser` rows in practice.** The model permits it
  (app/models/account.rb:44,64,102) and Super Admin can create an account without a member
  (config/routes.rb:737-740, plain Administrate CRUD). I did not boot the app to confirm that a zero-member account
  renders cleanly in every Super Admin view that joins on users.
- **The full 72-flag `config/features.yml` catalogue** cited in §3 row 14 and row 2 is from
  `permissions_telemetry.json` (config/features.yml:17-289). I verified the Help Center block directly
  (config/features.yml:42-45) and the `help_url` keys, but did not re-enumerate all 72 flags for this document.
- **No app boot and no spec run.** Every "already works" claim here is from reading the route → controller → model →
  view path, not from observed behaviour. The one behavioural risk this leaves is the archive bug
  (portals_controller.rb:44), which I read as a live defect but did not execute.
