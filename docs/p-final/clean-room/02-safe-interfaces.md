# Clean interfaces available to the implementer

**Audience: the clean-room implementer.**

Everything listed here is in the workspace you were given and is **yours to call, extend and depend on**. Each
entry is classified by where it comes from, because that is what makes it safe to use:

| class | meaning |
|---|---|
| **OSS CHATWOOT** | upstream Chatwoot, MIT-licensed, in the repository's main tree |
| **DEPENDENCY** | a third-party library already in `Gemfile` / `package.json` |
| **ORIGINAL LYNOMIA** | written for this product; no upstream or third-party ancestry |
| **DATABASE CONTRACT** | a table, column, enum value or index that already holds production data |
| **P8** / **P9** / **P10** / **P11** | an original Lynomia subsystem delivered in that phase |

Nothing in this document is part of the rewrite. If something you need is missing here, it is either one of the
five packages you are implementing, or it does not exist — do not assume a third possibility.

---

## 1. The extension mechanism

**OSS CHATWOOT.** Upstream declares explicit extension points and this installation has exactly one overlay.

| fact | where |
|---|---|
| the overlay list is `["custom"]` on any install with a `custom/` directory | `lib/chatwoot_app.rb:40-43` |
| `custom/` is appended to the autoload and view paths | `config/application.rb:51-57` |
| a class or module asks for its overlay with `prepend_mod_with` / `include_mod_with` at the bottom of its own file | throughout `app/` |
| because `custom` is the only overlay, `super` from a `Custom::` module reaches the upstream implementation directly | `lib/chatwoot_app.rb:40-43` |

The extension points the five packages need, each **already declared upstream**:

| extension point | file:line |
|---|---|
| `Whatsapp::IncomingMessageBaseService` | `app/services/whatsapp/incoming_message_base_service.rb:230` |
| `Whatsapp::Providers::BaseService` | `app/services/whatsapp/providers/base_service.rb:136` |
| `Whatsapp::OneoffCampaignService` | `app/services/whatsapp/oneoff_campaign_service.rb:148` |
| `Messages::StatusUpdateService` | `app/services/messages/status_update_service.rb:48` |
| `Channelable` (channel configuration changes) | `app/models/concerns/channelable.rb:13`, with the `after_update` hook declared at `:7` and its body deliberately empty at `:10` |
| `DeleteObjectJob` (asynchronous destruction) | `app/jobs/delete_object_job.rb:43`, with `process_post_deletion_tasks(object, user, ip)` called after the destroy and its body empty at `:16`. Two upstream call sites already thread the acting user and the request address to it: `app/controllers/api/v1/accounts/inboxes_controller.rb:81`, `app/services/conversations/delete_service.rb:6` |
| `Api::V1::Accounts::Conversations::MessagesController` | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:132` |
| `DeviseOverrides::SessionsController` | `app/controllers/devise_overrides/sessions_controller.rb:244` |
| `Channel::Whatsapp` | `app/models/channel/whatsapp.rb:238`. Note `delegate :send_template, to: :provider_service` at `:147` |
| `Account` | `app/models/account.rb:239-243` — five separate requests, including `Concerns::Account` and `Audit::Account` |
| `AccountUser` | `app/models/account_user.rb:102-104` — `AccountUser`, `Audit::AccountUser` and `Concerns::AccountUser`, which is how a membership gains both its role association and its capability list |
| `ReportPolicy`, `SuperAdmin::AccountsController`, `Inboxes::FetchImapEmailsJob` | each declares its own at the bottom of its file |

**Use these rather than editing upstream files.** An empty hook body with a live `prepend_mod_with` beneath it is
an invitation, not an accident.

### The thirteen audit include sites upstream already declares

Package B needs somewhere to register each auditable record type. Upstream has already named all of them, one
per model, each with `include_mod_with('Audit::<Model>')` at the bottom of the model's own file:

| model | file:line | model | file:line |
|---|---|---|---|
| `Account` | `app/models/account.rb:243` | `Macro` | `app/models/macro.rb:78` |
| `AccountUser` | `app/models/account_user.rb:103` | `Team` | `app/models/team.rb:89` |
| `AgentBot` | `app/models/agent_bot.rb:72` | `TeamMember` | `app/models/team_member.rb:31` |
| `AutomationRule` | `app/models/automation_rule.rb:162` | `Webhook` | `app/models/webhook.rb:46` |
| `Conversation` | `app/models/conversation.rb:434` | `Inbox` | `app/models/inbox.rb:282` |
| `CustomFilter` | `app/models/custom_filter.rb:55` | `InboxMember` | `app/models/inbox_member.rb:44` |
| `User` | `app/models/user.rb:229` | | |

Two things worth knowing:

- `Audit::CustomFilter` is **already filled, cleanly** — see §4. Use it as the pattern for the others.
- `Audit::User` is declared upstream and **nothing claims it today**; sign-in and sign-out are recorded from the
  session controller instead. Either route satisfies package B's B14; the choice is yours.

---

## 2. Dependencies you should prefer over hand-rolling

| capability | library | version | notes |
|---|---|---|---|
| audit records | `audited` | `~> 5.4` (`Gemfile:184`) | the `audits` table is this gem's. Its model is `Audited::Audit`; a subclass is the normal way to add scopes. Its `audited` class macro is the documented way to register a model (`audited associated_with: :account, if: :contact?` — see the clean example in §4). `Audited.store[:current_remote_address]` and `[:current_request_uuid]` carry the request context the gem's own middleware sets |
| pagination | `kaminari` | in `Gemfile` | `.page(n).per(n)`, `total_count`, `current_page` — the whole of what packages A and D need for paging |
| JSON responses | `jbuilder` | in `Gemfile` | the established way responses are built in this codebase; every view path under `app/views/api/` uses it |
| policy objects | `pundit` | in `Gemfile` | `authorize`, `policy_scope`, `ApplicationPolicy` |
| value initialisers | `attr_extras` (`pattr_initialize`) | in `Gemfile` | used by most services in this codebase |
| test factories | `factory_bot_rails` | in `Gemfile` | see §4 for the factories that already exist |
| HTTP | `httparty` | in `Gemfile` | already used by the provider services |

CLAUDE.md's rule applies: prefer an existing dependency over hand-rolled protocol code.

---

## 3. OSS Chatwoot interfaces (MIT)

### Request and tenancy

| interface | path | what it gives you |
|---|---|---|
| `Api::V1::Accounts::BaseController` | `app/controllers/api/v1/accounts/base_controller.rb` | authentication, `Current.account`, `Current.user`, `Current.account_user`, and the account scoping every account endpoint inherits |
| `Current` | `lib/current.rb` | the request-scoped actor and account. **This is where an actor comes from** — never a parameter |
| `ApplicationPolicy` and the policies beside it | `app/policies/` | the refusal shape the product already returns |
| `config/routes.rb` | — | all five packages' routes already exist; see `04-integration-contract.md` §2 |
| `config/features.yml` | — | the capability registry. A capability is read with `account.feature_enabled?('name')` and set with `enable_features!` / `disable_features!` |

### Models and enums

| interface | path | the part you need |
|---|---|---|
| `Account` | `app/models/account.rb` | `feature_enabled?`, `enable_features!`, `status` (`active` / `suspended`) |
| `AccountUser` | `app/models/account_user.rb` | the built-in roles enum (`agent: 0`, `administrator: 1`), `administrator?`, and the role-derived capability list that `Custom::AccountUser#permissions` falls through to |
| `User` | `app/models/user.rb` | the person; `SuperAdmin` is a subclass on the same table, which is why an actor reference must tolerate both |
| `Campaign` | `app/models/campaign.rb` | `campaign_type` (`ongoing: 0`, `one_off: 1`), `campaign_status` (`active: 0`, `completed: 1`, `processing: 2`), `audience_contacts`, `completed!`, `template_params`, `scheduled_at` |
| `Message` | `app/models/message.rb` | the status enum `sent: 0, delivered: 1, read: 2, failed: 3`, `source_id`, `external_error` |
| `Contact`, `ContactInbox`, `Inbox`, `Channel::Whatsapp` | `app/models/` | `Channel::Whatsapp#provider` (`whatsapp_cloud` or `default`), `provider_config`, `send_template`, and `SECRET_PROVIDER_CONFIG_KEYS` (`app/models/channel/whatsapp.rb:32`) which names the credential keys never sent to a browser |
| `CustomFilter` | `app/models/custom_filter.rb` | the saved segment; `contact?` distinguishes an audience from a conversation folder |

### WhatsApp (everything packages D and E sit on)

| interface | path | what it already does |
|---|---|---|
| `Webhooks::WhatsappController` | `app/controllers/webhooks/whatsapp_controller.rb` | verifies Meta's signature before anything is enqueued, rejects inactive numbers, drops tracking-only payloads |
| `Webhooks::WhatsappEventsJob` | `app/jobs/webhooks/whatsapp_events_job.rb` | resolves the channel — hence the account and inbox — from the payload, and serialises concurrent webhooks per `(inbox, sender)` |
| `Whatsapp::IncomingMessageBaseService` | `app/services/whatsapp/incoming_message_base_service.rb` | routes a `statuses` payload to status handling before any message handling (`:14`); for a conversation message, finds it by provider id, updates identifiers, and hands the outcome to `Messages::StatusUpdateService` (`:62-78`) |
| `Messages::StatusUpdateService` | `app/services/messages/status_update_service.rb` | the forward-only status rule for a conversation message, under a row lock, with the "to or from failed" exception |
| `Whatsapp::Providers::BaseService` | `app/services/whatsapp/providers/base_service.rb` | `process_response` returns the provider's message id on success and `nil` on failure (`:34-40`); `recipient_params` handles business-scoped ids correctly (`:62-68`) |
| `Whatsapp::Providers::WhatsappCloudService` | `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | the Cloud API calls themselves |
| `Whatsapp::OneoffCampaignService` | `app/services/whatsapp/oneoff_campaign_service.rb` | validates the campaign, resolves the audience, renders the template per contact, and sends — continuing past a per-contact failure |
| `Whatsapp::TemplateProcessorService`, `Whatsapp::LiquidTemplateProcessorService`, `Whatsapp::AuthenticationTemplateGuard` | `app/services/whatsapp/` | template rendering and the rules on which templates may be sent to whom |
| `Whatsapp::ChannelCreationService` | `app/services/whatsapp/channel_creation_service.rb:59` | sets `provider_config['is_coexistence']` for a business-app number — the marker that says a number came through coexistence |

### Frontend (clean, and it is your contract)

Everything under `app/javascript/` is in the main tree and is **not** part of the rewrite. The pages, stores,
API clients and helpers listed in `04-integration-contract.md` §4 define the response keys your endpoints must
return. Treat them as the specification of the wire format they already consume:

`dashboard/api/auditLogs.js`, `dashboard/store/modules/auditlogs.js`, `dashboard/helper/auditlogHelper.js`,
`dashboard/routes/dashboard/settings/auditlogs/`, `dashboard/api/customRole.js`,
`dashboard/helper/permissionsHelper.js`, `dashboard/routes/dashboard/settings/agents/`,
`dashboard/api/campaigns.js`, `dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue`,
`dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/`.

---

## 4. Original Lynomia interfaces (clean)

### The one integration point for authorization

| interface | path | contract |
|---|---|---|
| `Custom::AccountUser#permissions` | `custom/app/models/custom/account_user.rb` | a membership's capability list is its attached role's capabilities plus a marker, or Chatwoot's role-derived list when it has none. **Every capability check in the product reads this one list** |
| `Commerce::ActionPolicy::MANAGE_PERMISSION` | `custom/app/policies/commerce/action_policy.rb:8` | `'commerce_order_manage'` |
| `Support::TicketPolicy::MANAGE_PERMISSION` | `custom/app/policies/support/ticket_policy.rb:15` | `'support_ticket_manage'` |
| `Custom::ContactPolicy::MANAGE_PERMISSION` | `custom/app/policies/custom/contact_policy.rb:15` | `'contact_manage'` |

All four are clean and none is being rewritten. The capability **strings** are therefore fixed.

### The audit store's existing clean callers

Seven pieces of clean Lynomia code already write to the audit store, and **none of them is part of the
rewrite**. They are both a working example of the record shape and a hard constraint — see
`04-integration-contract.md` §3:

| caller | path | phase |
|---|---|---|
| audience auditing | `custom/app/models/custom/audit/custom_filter.rb` | pre-P8. **The cleanest example in the tree**: one `audited associated_with: :account, if: :contact?` line |
| contact merge | `custom/app/actions/custom/contact_merge_action.rb:75` | P10 |
| commerce store connections | `custom/app/services/commerce/audit_trail.rb:27` | Commerce |
| flow lifecycle | `custom/app/services/flows/audit.rb:11` | Flow Builder |
| plan entitlement edits | `custom/app/services/billing/plan_audit.rb:24` | P11 |
| entitlement overrides | `custom/app/services/billing/override_grant.rb:132` | P11 |
| plan-sync revocations | `custom/app/services/billing/feature_sync.rb:54` | P11 |

### P8 — analytics

| interface | path | what you need it for |
|---|---|---|
| `Analytics::Campaigns::Metrics` | `custom/app/services/analytics/campaigns/metrics.rb` | the cross-campaign reader of package D's records. Its `DELIVERED_SQL`, metric vocabulary and timestamp semantics are a contract |
| `Analytics::DateRange`, `Analytics::FilterSet` | `custom/app/services/analytics/` | the window and the validated filter set every analytics family shares |
| `Contacts::ActivityTimelineQuery` | `custom/app/services/contacts/` | the contact timeline; reads the audit store among other sources |

### P9 — support cases and operations

| interface | path |
|---|---|
| `Support::Ticket`, `Support::Tickets::Query`, `Support::Tickets::Counts` | `custom/app/models/support/`, `custom/app/services/support/tickets/` |
| `Operations::Signal`, `Operations::Health`, `Operations::Overview`, `Operations::AccountHealth` | `custom/app/models/operations/`, `custom/app/services/operations/` |

### P10 — identity and channels

| interface | path |
|---|---|
| `ContactIdentity` | `custom/app/models/contact_identity.rb` |
| `Channels::Capability`, `Channels::ConnectionState` | `custom/app/services/channels/` |
| `Contacts::MergeRelocation` | `custom/app/services/contacts/merge_relocation.rb` |

### P11 — entitlements and billing

| interface | path | contract |
|---|---|---|
| `Billing::Entitlements` | `custom/app/services/billing/entitlements.rb` | `allowed?(account, name)`, `limit(account, key)`, `channel_allowed?(account, class_name)` — the one place a capability question is answered when billing is enforced |
| `Billing::Settings` | `custom/app/services/billing/settings.rb` | `enforced?`, and the masked read of installation settings |
| `BillingPlan`, `BillingSubscription`, `BillingEntitlementOverride` | `custom/app/models/` | `BillingSubscription::BILLED_STATUSES`, `#accessible?` |

**Note for package C:** if a named permission set should be gated on the customer's plan, ask
`Billing::Entitlements`; do not invent a second entitlement path.

---

## 5. Database contracts

These tables already hold production data. Columns, enum values and indexes are fixed unless
`04-integration-contract.md` says otherwise.

| table | owner | what is fixed |
|---|---|---|
| `audits` | the `audited` gem | every column named in `specs/A-audit-trail-read.md` §3, and the six indexes listed there. `city`, `country`, `country_code` stay unwritten |
| `custom_roles` | package C | `account_id`, `name`, `description`, `permissions` (string array) |
| `account_users.custom_role_id` | package C | the attachment column |
| `campaign_recipients` | package D | every column, the status enum's numeric values, and the three behaviour-carrying indexes — `specs/D-campaign-recipient-outcomes.md` §3 |
| `messages.source_id`, `messages.status`, `messages.external_error` | OSS | package E's join and the conversation-message path |
| `campaigns` | OSS | `campaign_type`, `campaign_status`, `audience` |

No migration is expected for any of the five packages. If you believe one is needed, it must be additive and
justified in writing — `docs/p-final/03-migration-review.md` is in the workspace and states the rules this
release deploys under.

---

## 6. Test fixtures already available

| factory | path | note |
|---|---|---|
| `:custom_role` | `spec/factories/custom_roles.rb` | **upstream MIT, unchanged, clean.** It references `CustomRole::PERMISSIONS`, so either keep that constant or update this factory |
| `:account`, `:user`, `:account_user`, `:inbox`, `:channel_whatsapp`, `:contact`, `:contact_inbox`, `:conversation`, `:message`, `:campaign` | `spec/factories/` | the standard set |
| `spec/requests/p_final/existing_account_compatibility_spec.rb` | — | a working example of an end-to-end request spec that proves an existing account still works. Useful as a shape for section F of the acceptance plan |
| `with_modified_env` | `spec/support/` | the repo's preferred way to set environment variables in a spec (CLAUDE.md) |

There is **no factory for a campaign recipient**. Nothing was removed — one never existed.

---

## 7. What is deliberately absent

So you do not go looking:

| absent | why |
|---|---|
| `enterprise/` | the directory does not exist in this product. `ChatwootApp.extensions` is `["custom"]` and `ChatwootApp.enterprise?` is false |
| any AI, assistant or autonomous-agent subsystem | not part of this product, and not to be added |
| any unofficial WhatsApp transport | official Meta Cloud API only (`specs/E-whatsapp-delivery-status-propagation.md` §9) |
| a campaign execution engine beyond the one-off send path | there is one send path and one recipient table |
| a second audit store, cache or rollup | one table answers every audit read |
| IP geolocation | deliberately not implemented (`specs/A-audit-trail-read.md` §9) |
