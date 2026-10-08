# Lynomia Chat — zero-dependency readiness for removing the Chatwoot Enterprise overlay

**Status:** analysis only. Nothing under `enterprise/` was deleted, disabled, moved or edited for this
report, and no feature flag, licensing file or runtime behaviour was changed. Every claim below is
either a measurement taken in this container or a line-by-line reading with the file and line cited.

**Companion document:** `docs/enterprise-audit/00-enterprise-dependency-audit.md` (the structural
dependency map). This document verifies what that one classified structurally, and corrects it where
measurement disagreed (section 9).

---

## 1. Scope, method and evidence base

### 1.1 What was asked

Reach a factual zero-dependency readiness state before any removal decision: verify every remaining
Enterprise overlay behaviour line by line, design (not implement) the smallest replacement for the
known dependencies, map route, data-model and frontend impact, and prove by simulation that the
application boots and that every Lynomia feature still works with the `Enterprise::` namespace
unavailable.

### 1.2 How the overlay works, in one paragraph

`config/initializers/01_inject_enterprise_edition_module.rb` adds `prepend_mod_with`,
`include_mod_with` and `extend_mod_with` to every class. Each call looks up
`Enterprise::<Name>` and `Custom::<Name>` through `const_get_maybe_false`
(`01_inject_enterprise_edition_module.rb:82-86`, consumed by `yield(extension_module) if extension_module` on line 78), which returns `false` rather than raising when the
namespace is absent, so a missing overlay silently no-ops. `config/application.rb:42-49` adds
`enterprise/lib`, `enterprise/listeners` and `Dir[".../enterprise/app/**"]` to the eager-load paths —
the `Dir[]` glob returns `[]` when the directory is gone — and `:63-64` requires the enterprise
initializers only `if … exist?`. The overlay is removable by design; this document measures whether
*this installation* can take that removal.

One consequence matters for reading the rest: because `ChatwootApp.extensions` yields
`%w[enterprise custom]`, the ancestor chain is `[Custom::X, Enterprise::X, OSSClass]`. A `super`
inside a `Custom::` module falls through to `Enterprise::`, so "Custom wins" never means the
Enterprise override is dead.

### 1.3 The simulation environment

Phase 6 was run as a measurement, not an argument. A scratch git worktree was created from the
current branch head, `enterprise/` was renamed aside **in that worktree only**, and the primary
checkout was left untouched and verified clean:

```
git worktree add --detach <scratchpad>/noee HEAD      # 757436dd
mv <scratchpad>/noee/enterprise <scratchpad>/noee/.enterprise-removed
```

Everything in sections 2-8 marked *(measured)* was observed in that worktree, running Rails 7.2.3.1
on Ruby 3.4.4 in `RAILS_ENV=production` with eager loading, against a PostgreSQL database loaded
from `db/schema.rb` and a live Redis. A baseline run of each probe was taken in the primary checkout
(enterprise present) so that only the *delta* is attributed to removal.

### 1.4 What the overlay actually contains

| Measure | Count |
|:--|--:|
| `Enterprise::` overlay modules under `enterprise/` | 136 |
| …with a matching OSS `prepend_mod_with` / `include_mod_with` site | 106 |
| …nested or internal, with no OSS injection site | 30 |
| Methods defined across all 136 modules | 568 |
| Modules containing at least one `super` call | 66 |
| Modules with a `self.prepended` hook | 2 |
| Modules with a `self.included` hook | 0 |
| Lines of Ruby in the 136 modules | 5,327 |

---

## 2. Phase 1 — every overlay behaviour verified and classified

### 2.1 Method

Three passes, in this order:

1. **Mechanical inventory.** For every `Enterprise::` module under `enterprise/`: file, LOC, each
   method with its line and whether its body contains `super`, whether a `self.prepended` /
   `self.included` hook exists, and the matching OSS injection site. Result:
   `136` modules, `568` methods.
2. **Line-by-line reading.** All 106 modules with an OSS injection site were read in full (3,489
   lines). The 30 nested modules were swept for references from `app/`, `lib/`, `custom/`, `config/`
   and `db/`: **29 have zero references**; the one exception is `Enterprise::AuditLog`, with exactly
   6 (section 3.1).
3. **Breakage probe (measured).** For every method that does **not** call `super`, the OSS target
   class was asked — in the no-enterprise worktree — whether it still defines that method.
   **222 enterprise-only methods disappear across 56 OSS classes.** Each of the 217 distinct method
   names was then searched across `app/`, `lib/`, `custom/` and `config/` (PCRE, word-bounded,
   specs excluded). 31 names produced textual matches; every match was read.
   **Not one is a genuine call from OSS or Lynomia code into a method that only `enterprise/`
   defines.** The near-misses are worth recording because they are what a filename-level audit would
   have flagged:

   | Apparent caller | Reality |
   |:--|:--|
   | `app/models/concerns/channelable.rb:10` calls `create_audit_log_entry` | OSS defines it as an explicit no-op: `def create_audit_log_entry; end`. The channel `after_update` hook keeps firing and does nothing. |
   | `app/policies/inbox_policy.rb:91-103` define `enable_whatsapp_calling?`, `disable_whatsapp_calling?`, `set_inbound_calls?`, `set_call_recording?` | OSS policy methods for enterprise-only controller actions; the routes are enterprise-gated and vanish, leaving the policy methods unreachable (dead code to clean up). |
   | `app/services/shopify/subscription_fetcher.rb:26` mentions `billing_provider` / `signup_source` | Reads `billing_identity['billing_provider']`, a hash key, not `Account#billing_provider`. There is **no** `.billing_provider` method call anywhere in `app/`, `lib/` or `custom/`. |
   | `app/dashboards/account_dashboard.rb:129` mentions `manually_managed_features` | Permitted only `if ChatwootApp.chatwoot_cloud?`, so it is never submitted on this installation. |
   | `app/services/whatsapp/providers/*.rb` mention `template_info` | A local parameter name, not the enterprise `Whatsapp::OneoffCampaignService#template_info`. |
   | `app/builders/email/sender_name_builder.rb:43` defines `valid_locale?` | Its own private method; unrelated to the enterprise article-translation helper of the same name. |

   Three OSS constants could not be resolved reflectively (`Concerns::ActivityMessageHandler`,
   `Concerns::Channelable`, `Concerns::InboxAgentAvailability` are concern modules, not classes).
   All three were read by hand and closed: OSS defines
   `Channelable#create_audit_log_entry` (no-op, `channelable.rb:10`),
   `InboxAgentAvailability#member_ids_with_assignment_capacity` (returns `member_ids`,
   `inbox_agent_availability.rb:14-16`) and
   `ActivityMessageHandler#automation_status_change_activity_content`
   (`activity_message_handler.rb:94-100`). No gap remains.

### 2.2 Classification

| Class | Meaning | Count |
|:--|:--|--:|
| **A** | NO EFFECT — the behaviour cannot change anything on a path this installation reaches | 38 |
| **B** | ENTERPRISE-ONLY FEATURE — removal removes a feature Lynomia does not ship | 79 |
| **C** | LYNOMIA BEHAVIOR CHANGE — a Lynomia-reachable path behaves differently, but still correctly | 13 |
| **D** | REPLACEMENT REQUIRED — a Lynomia-shipped capability stops working | 6 |
| **E** | UNKNOWN | 0 |
| | **Total** | **136** |

All 13 **C** rows are the same two things: the audit trail (11 rows) and two single-point behaviour
reversions (`AccountUser#permissions`, which costs Lynomia the `commerce_order_manage` custom-role
grant, and the deletion/session audit writes). All 6 **D** rows are one capability:
**WhatsApp campaign recipient tracking**. There is no third dependency.

### 2.3 The full table

| # | Class | Enterprise module | Capability | Methods | LOC | Calls `super` | OSS injection site | Effect once `Enterprise::` is unavailable |
|--:|:--|:--|:--|--:|--:|:--|:--|:--|
| 1 | **A** | `Enterprise::ApplicationRecord` | SLA | 1 | 5 | yes | `app/models/application_record.rb:56` (prepend) | Only removes 'SlaPolicy' from the droppables list. |
| 2 | **A** | `Enterprise::ArticlePolicy` | Custom roles | 7 | 29 | yes | `app/policies/article_policy.rb:31` (prepend) | Every method is `custom_role&.permissions&.include?(...) \|\| super`. With no custom roles, super is already the deciding branch. |
| 3 | **A** | `Enterprise::Audit::User` | Audit log | 0 | 14 | no | `app/models/user.rb:229` (include) | `audited ... unless: proc { \|_u\| true }` - the gem never writes from this declaration; session events are written manually by the sessions controller. |
| 4 | **A** | `Enterprise::AutoAssignment::AssignmentService` | Assignment policies / agent capacity | 11 | 92 | yes | `app/services/auto_assignment/assignment_service.rb:144` (prepend) | Every override branches on `policy` (inbox.assignment_policy) or feature_enabled?('advanced_assignment'). OSS defines apply_age_exclusions, age_exclusion_hours and unassigned_conversations, so with no policy record the behaviour is already the OSS one. |
| 5 | **A** | `Enterprise::AutomationRule` | SLA | 1 | 5 | yes | `app/models/automation_rule.rb:163` (prepend) | Removes 'add_sla' from actions_attributes. AutomationRuleForm.vue:224-227 already hides that action unless isCloudFeatureEnabled('sla'). |
| 6 | **A** | `Enterprise::Captain::BaseTaskService` | Captain cloud quota | 4 | 32 | yes | `lib/captain/base_task_service.rb:238` (prepend) | Measured: OSS lib/captain/base_task_service.rb:43-44 already refuses unless account.feature_enabled?('captain_tasks') and an API key is configured. The EE wrapper only adds cloud response-quota accounting, so removing it does NOT open an ungated LLM path. |
| 7 | **A** | `Enterprise::Captain::ReplySuggestionService` | Captain search tool | 4 | 24 | yes | `lib/captain/reply_suggestion_service.rb:46` (prepend) | use_search_tool? is `chatwoot_cloud? \|\| self_hosted_paid?`; both false. |
| 8 | **A** | `Enterprise::CategoryPolicy` | Custom roles | 7 | 29 | yes | `app/policies/category_policy.rb:31` (prepend) | Same shape, same conclusion. |
| 9 | **A** | `Enterprise::Channelable` | Audit log | 2 | 45 | no | `app/models/concerns/channelable.rb:13` (prepend) | OSS app/models/concerns/channelable.rb:10 defines `def create_audit_log_entry; end` - an explicit no-op. Channel saves stop being audited; nothing raises. |
| 10 | **A** | `Enterprise::ChatwootHub` | Telemetry endpoint | 1 | 9 | no | `lib/chatwoot_hub.rb:133` (prepend) | OSS lib/chatwoot_hub.rb:3 already defines DEFAULT_BASE_URL = 'https://hub.2.chatwoot.com'; the override only adds a development ENV escape hatch. |
| 11 | **A** | `Enterprise::Concerns::ApplicationControllerConcern` | - | 0 | 3 | no | `app/controllers/application_controller.rb:29` (include) | Empty module (3 LOC, no methods). |
| 12 | **A** | `Enterprise::Concerns::Article` | Help Center embedding search / Captain | 8 | 91 | yes | `app/models/article.rb:238` (include) | `add_article_embedding` returns unless portal.feature_enabled?('help_center_embedding_search'), which is off and unreachable. Article.vector_search is only called from the two enterprise portal controllers. |
| 13 | **A** | `Enterprise::Concerns::AssignmentPolicy` | Balanced assignment | 0 | 7 | no | `app/models/assignment_policy.rb:41` (include) | Self-guarded: `enum ... if ChatwootApp.enterprise?`. |
| 14 | **A** | `Enterprise::Concerns::CustomAttributeDefinition` | Required conversation attributes | 1 | 16 | no | `app/models/custom_attribute_definition.rb:100` (include) | Only cleans up account.conversation_required_attributes, which is a premium store_accessor added by the same overlay. |
| 15 | **A** | `Enterprise::Concerns::Portal` | Cloudflare custom domains | 1 | 14 | no | `app/models/portal.rb:248` (include) | enqueue_cloudflare_verification returns unless ChatwootApp.chatwoot_cloud?. |
| 16 | **A** | `Enterprise::ContactPolicy` | Custom roles | 2 | 9 | yes | `app/policies/contact_policy.rb:60` (prepend) | Same shape (export?, import?). |
| 17 | **A** | `Enterprise::Contacts::ContactableInboxesService` | Twilio voice | 2 | 16 | yes | `app/services/contacts/contactable_inboxes_service.rb:75` (prepend) | Only branches for a voice-enabled TwilioSms inbox. |
| 18 | **A** | `Enterprise::ConversationFinder` | SLA | 1 | 7 | yes | `app/finders/conversation_finder.rb:210` (prepend) | Guarded by feature_enabled?('sla'); super already runs. |
| 19 | **A** | `Enterprise::ConversationPolicy` | Custom roles | 7 | 42 | yes | `app/policies/conversation_policy.rb:47` (prepend) | show? is `return false unless super; return true unless custom_role_permissions?` - identical to super when account_user.custom_role_id is nil. |
| 20 | **A** | `Enterprise::Conversations::EventDataPresenter` | SLA | 1 | 13 | yes | `app/presenters/conversations/event_data_presenter.rb:63` (prepend) | Guarded by feature_enabled?('sla'). |
| 21 | **A** | `Enterprise::Conversations::PermissionFilterService` | Custom roles | 6 | 45 | yes | `app/services/conversations/permission_filter_service.rb:48` (prepend) | `perform` returns super unless user_has_custom_role?. |
| 22 | **A** | `Enterprise::CsatSurveyResponsePolicy` | Custom roles | 4 | 17 | yes | `app/policies/csat_survey_response_policy.rb:15` (prepend) | index?/metrics?/download? are `... \|\| super`; update? has no super but its only route is enterprise-gated and vanishes. |
| 23 | **A** | `Enterprise::InboxAgentAvailability` | Agent capacity | 4 | 31 | no | `app/models/concerns/inbox_agent_availability.rb:28` (prepend) | Guarded by feature_enabled?('advanced_assignment') AND an existing agent_capacity_policy join; neither can exist without the overlay. |
| 24 | **A** | `Enterprise::Internal::CheckNewVersionsJob` | Cloud plan reconcile | 4 | 30 | yes | `app/jobs/internal/check_new_versions_job.rb:20` (prepend) | Removes `Internal::ReconcilePlanConfigService`, the daily writer that rebranded this installation back to Chatwoot until commit 68b1d5db worked around it. Removal retires that defect class permanently. |
| 25 | **A** | `Enterprise::Macros::ExecutionService` | Required conversation attributes | 4 | 32 | yes | `app/services/macros/execution_service.rb:72` (include) | required_attributes_missing? returns false unless feature_enabled?('conversation_required_attributes'). |
| 26 | **A** | `Enterprise::MessageFinder` | Voice calling | 1 | 5 | yes | `app/finders/message_finder.rb:69` (prepend) | Only adds `includes(call: ...)`; the association and model are enterprise-only. |
| 27 | **A** | `Enterprise::MessageTemplates::HookExecutionService` | Captain | 10 | 85 | yes | `app/services/message_templates/hook_execution_service.rb:66` (prepend) | Every method returns super when inbox.captain_assistant is nil. Greeting, out-of-office, e-mail-collect and CSAT templates behave identically. |
| 28 | **A** | `Enterprise::Messages::SearchDataPresenter` | Voice transcripts | 1 | 11 | yes | `app/presenters/messages/search_data_presenter.rb:61` (prepend) | Returns super when there is no Call transcript, which is always once Call is gone. |
| 29 | **A** | `Enterprise::Onboarding::WebWidgetCreationService` | Captain LLM tagline | 1 | 11 | yes | `app/services/onboarding/web_widget_creation_service.rb:75` (prepend) | Returns super when the LLM call is absent or fails. |
| 30 | **A** | `Enterprise::PortalPolicy` | Custom roles | 3 | 13 | yes | `app/policies/portal_policy.rb:39` (prepend) | Same shape. |
| 31 | **A** | `Enterprise::Public::Api::V1::Portals::ArticlesController` | Help Center embedding search | 1 | 11 | yes | `app/controllers/public/api/v1/portals/articles_controller.rb:114` (prepend) | Guarded by portal.feature_enabled?('help_center_embedding_search'), which is `enabled: false, premium: true, chatwoot_internal: true` in config/features.yml:136-140 and referenced nowhere else. super already runs. |
| 32 | **A** | `Enterprise::Public::Api::V1::Portals::SearchController` | Help Center embedding search | 1 | 9 | yes | `app/controllers/public/api/v1/portals/search_controller.rb:31` (prepend) | Same guard, same conclusion. |
| 33 | **A** | `Enterprise::ReportPolicy` | Custom roles | 1 | 5 | yes | `app/policies/report_policy.rb:7` (prepend) | Same shape. |
| 34 | **A** | `Enterprise::SearchService` | OpenSearch advanced search | 10 | 90 | no | `app/services/search_service.rb:208` (prepend) | Only reachable through ChatwootApp.advanced_search_allowed?, which is `enterprise? && OPENSEARCH_URL`. |
| 35 | **A** | `Enterprise::SuperAdmin::AccountsController` | Manually managed features | 2 | 26 | yes | `app/controllers/super_admin/accounts_controller.rb:161` (prepend) | Reads params[:account][:manually_managed_features], which app/dashboards/account_dashboard.rb:129 only permits when ChatwootApp.chatwoot_cloud?. Never submitted on this installation. |
| 36 | **A** | `Enterprise::SuperAdmin::AppConfigsController` | Premium Super Admin config groups | 7 | 78 | yes | `app/controllers/super_admin/app_configs_controller.rb:121` (prepend) | `allowed_configs` returns super unless ChatwootHub.pricing_plan != 'community'. This installation is community, so the OSS mapping is already the one in force; the custom_branding group is not reachable today either. |
| 37 | **A** | `Enterprise::WebsiteBrandingService` | context.dev brand lookup | 6 | 67 | yes | `app/services/website_branding_service.rb:149` (prepend) | Returns super unless CONTEXT_DEV_API_KEY is configured. |
| 38 | **A** | `Enterprise::WidgetsController` | Geo-restricted widget | 1 | 14 | no | `app/controllers/widgets_controller.rb:99` (prepend) | OSS widgets_controller.rb defines `ensure_location_is_supported`; the EE override only adds the allowed_countries check. |
| 39 | **B** | `Enterprise::Account` | Captain / SAML / cloud billing / assignment v2 | 14 | 126 | yes | `app/models/account.rb:239` (prepend) | mark_for_deletion and unmark_for_deletion have no OSS or custom caller (measured); api_and_webhooks_enabled? is defined by OSS; enable_default_features only adds Captain flags when self_hosted_paid?. |
| 40 | **B** | `Enterprise::Account::ConversationsResolutionSchedulerJob` | Captain | 2 | 23 | yes | `app/jobs/account/conversations_resolution_scheduler_job.rb:10` (prepend) | Stops the extra Captain pending-conversation resolution pass; the OSS pass still runs. |
| 41 | **B** | `Enterprise::Account::PlanUsageAndLimits` | Plan limits | 24 | 216 | no | `app/models/account.rb:240` (prepend) | OSS Account#usage_limits already returns {agents:, inboxes:} at ChatwootApp.max_limit. Agent/inbox/Captain quota enforcement reverts to unlimited, which is the OSS self-hosted default. |
| 42 | **B** | `Enterprise::AccountBillingIdentity` | Cloud billing identity | 7 | 49 | no | `app/models/account.rb:241` (include) | Removes Account#billing_provider / #signup_source. No OSS or custom code calls either method (measured: the only textual hits read a hash key in app/services/shopify/subscription_fetcher.rb:26). |
| 43 | **B** | `Enterprise::AccountPolicy` | Cloud billing | 1 | 5 | no | `app/policies/account_policy.rb:47` (prepend) | Removes billing_summary?, whose only route is the enterprise accounts controller. |
| 44 | **B** | `Enterprise::ActionCableListener` | Captain copilot | 1 | 11 | no | `app/listeners/action_cable_listener.rb:234` (prepend) | Drops the copilot_message_created broadcast. |
| 45 | **B** | `Enterprise::ActionService` | SLA | 1 | 15 | no | `app/services/action_service.rb:122` (include) | Removes the add_sla automation action implementation. |
| 46 | **B** | `Enterprise::ActivityMessageHandler` | Captain | 5 | 35 | yes | `app/models/concerns/activity_message_handler.rb:125` (prepend) | Guarded by Current.executed_by.instance_of?(Captain::Assistant); super otherwise. |
| 47 | **B** | `Enterprise::AgentBuilder` | SAML SSO | 3 | 26 | yes | `app/builders/agent_builder.rb:86` (prepend) | Blocks a multi-account invite and forces provider='saml' when account.saml_enabled?. `Account#saml_enabled?` is enterprise-only; agent invite reverts to OSS. |
| 48 | **B** | `Enterprise::AgentNotifications::ConversationNotificationsMailer` | SLA | 4 | 38 | yes | `app/mailers/agent_notifications/conversation_notifications_mailer.rb:74` (prepend) | Drops the three sla_missed_* mailers and the sla_policy liquid droppable. |
| 49 | **B** | `Enterprise::Api::V1::Accounts::AgentsController` | Custom roles | 3 | 23 | yes | `app/controllers/api/v1/accounts/agents_controller.rb:120` (prepend) | Stops writing account_user.custom_role_id. The column and CustomRole are enterprise-only. |
| 50 | **B** | `Enterprise::Api::V1::Accounts::Articles::BulkActionsController` | Captain article translation | 8 | 68 | no | `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:59` (prepend) | OSS #translate is `head :not_implemented`; the EE override is the only implementation. Route (routes.rb:451) stays and answers 501. |
| 51 | **B** | `Enterprise::Api::V1::Accounts::AssignableAgentsController` | Captain | 1 | 10 | yes | `app/controllers/api/v1/accounts/assignable_agents_controller.rb:29` (prepend) | Guarded by feature_enabled?('captain_integration'); reverts to super. |
| 52 | **B** | `Enterprise::Api::V1::Accounts::ContactsController` | Companies | 2 | 17 | yes | `app/controllers/api/v1/accounts/contacts_controller.rb:243` (prepend) | Guarded by feature_enabled?('companies'); company_id stops being permitted. |
| 53 | **B** | `Enterprise::Api::V1::Accounts::Conversations::AssignmentsController` | Captain assignment | 1 | 9 | yes | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 54 | **B** | `Enterprise::Api::V1::Accounts::ConversationsController` | Captain / SLA / reporting events | 4 | 30 | yes | `app/controllers/api/v1/accounts/conversations_controller.rb:239` (prepend) | #inbox_assistant and #reporting_events disappear (ungated routes -> 404). permitted_update_params drops sla_policy_id only when the sla feature is on. |
| 55 | **B** | `Enterprise::Api::V1::Accounts::CsatSurveyResponsesController` | CSAT review notes | 1 | 12 | no | `app/controllers/api/v1/accounts/csat_survey_responses_controller.rb:54` (prepend) | Route is enterprise-gated and vanishes; the UI is gated on the csat_review_notes feature. |
| 56 | **B** | `Enterprise::Api::V1::Accounts::InboxesController` | Voice calling / agent capacity | 14 | 135 | yes | `app/controllers/api/v1/accounts/inboxes_controller.rb:224` (prepend) | All call actions and their routes vanish together. `inbox_attributes` stops permitting auto_assignment_config[max_assignment_limit]; the UI block is behind `isEnterprise \|\| hasAssignmentV2` and hides itself. |
| 57 | **B** | `Enterprise::Api::V1::Accounts::Integrations::BaseController` | Shopify cloud billing | 2 | 17 | yes | `app/controllers/api/v1/accounts/integrations/base_controller.rb:11` (prepend) | Removes a guard that only fires for accounts with billing_provider='shopify', which is itself enterprise-only. |
| 58 | **B** | `Enterprise::Api::V1::Accounts::OnboardingsController` | Captain help-center generation | 10 | 59 | yes | `app/controllers/api/v1/accounts/onboardings_controller.rb:89` (prepend) | Lynomia removed tenant Help Center authoring; onboarding reverts to the OSS inbox-only flow. |
| 59 | **B** | `Enterprise::Api::V1::Accounts::PortalsController` | Cloudflare custom domains | 1 | 15 | no | `app/controllers/api/v1/accounts/portals_controller.rb:148` (prepend) | #ssl_status disappears; its route (ungated) answers 404. |
| 60 | **B** | `Enterprise::Api::V1::AccountsController` | Cloud billing / account lifecycle | 26 | 217 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 61 | **B** | `Enterprise::Api::V1::AccountsSettings` | Marketing attribution / cloud version banner / required attributes | 4 | 28 | yes | `app/controllers/api/v1/accounts_controller.rb:152` (prepend) | `latest_chatwoot_version` already calls super on self-hosted. permitted_settings_attributes stops permitting conversation_required_attributes (premium, UI paywalled). |
| 62 | **B** | `Enterprise::Api::V2::AccountsController` | Clearbit enrichment | 5 | 40 | yes | `app/controllers/api/v2/accounts_controller.rb:69` (prepend) | Signup stops calling Clearbit; account_attributes revert to super. |
| 63 | **B** | `Enterprise::AsyncDispatcher` | Captain | 1 | 8 | yes | `app/dispatchers/async_dispatcher.rb:27` (prepend) | Drops CaptainListener and Captain::ReportingEventListener from the async listener list. |
| 64 | **B** | `Enterprise::Audit::Account` | Audit log | 0 | 8 | no | `app/models/account.rb:243` (include) | Account updates stop being audited; `has_associated_audits` is only consumed by the enterprise audit-log controller. |
| 65 | **B** | `Enterprise::Audit::AccountUser` | Audit log | 0 | 13 | no | `app/models/account_user.rb:103` (include) | Membership changes stop being audited. |
| 66 | **B** | `Enterprise::Audit::Conversation` | Audit log | 0 | 7 | no | `app/models/conversation.rb:434` (include) | `audited only: [], on: [:destroy]` stops recording conversation deletions. |
| 67 | **B** | `Enterprise::AuditLogIpLocationBackfillJob` | Audit log geolocation | 2 | 30 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 68 | **B** | `Enterprise::AuditLogIpLookupJob` | Audit log geolocation | 1 | 10 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 69 | **B** | `Enterprise::AuditLogSessionIpLookupJob` | Audit log geolocation | 2 | 25 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 70 | **B** | `Enterprise::AutoAssignment::BalancedSelector` | Balanced assignment | 2 | 26 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 71 | **B** | `Enterprise::AutoAssignment::CapacityService` | Agent capacity | 1 | 25 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 72 | **B** | `Enterprise::Billing::CancelCloudSubscriptionsService` | Stripe cloud billing | 3 | 27 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 73 | **B** | `Enterprise::Billing::CreateSessionService` | Stripe cloud billing | 1 | 10 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 74 | **B** | `Enterprise::Billing::CreateStripeCustomerService` | Stripe cloud billing | 11 | 94 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 75 | **B** | `Enterprise::Billing::Currencies` | Stripe cloud billing | 7 | 55 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 76 | **B** | `Enterprise::Billing::HandleStripeEventService` | Stripe cloud billing | 22 | 189 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 77 | **B** | `Enterprise::Billing::PlanConfiguration` | Cloud billing plans | 10 | 85 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 78 | **B** | `Enterprise::Billing::ReconcilePlanFeaturesService` | Cloud billing plans | 11 | 115 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 79 | **B** | `Enterprise::Billing::ShopifyAppPricingUrl` | Shopify cloud billing | 6 | 46 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 80 | **B** | `Enterprise::Billing::ShopifyPlanConfiguration` | Shopify cloud billing | 7 | 66 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 81 | **B** | `Enterprise::Billing::ShopifySubscriptionReconciliationJob` | Shopify cloud billing | 2 | 21 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 82 | **B** | `Enterprise::Billing::ShopifySubscriptionSyncJob` | Shopify cloud billing | 1 | 12 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 83 | **B** | `Enterprise::Billing::ShopifySubscriptionSyncService` | Shopify cloud billing | 18 | 174 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 84 | **B** | `Enterprise::Billing::SummaryService` | Cloud billing | 10 | 113 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 85 | **B** | `Enterprise::Billing::TopupCheckoutService` | Cloud billing top-ups | 11 | 119 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 86 | **B** | `Enterprise::Billing::TopupFulfillmentService` | Cloud billing top-ups | 4 | 51 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 87 | **B** | `Enterprise::CancelCloudSubscriptionsJob` | Stripe cloud billing | 1 | 14 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 88 | **B** | `Enterprise::Captain::ConversationCompletionService` | Captain | 1 | 12 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 89 | **B** | `Enterprise::Channel::TwilioSms` | Twilio voice | 12 | 91 | yes | `app/models/channel/twilio_sms.rb:89` (prepend) | Drops voice provisioning, TwiML app setup and api_key_secret encryption. SMS behaviour comes from OSS. |
| 90 | **B** | `Enterprise::ClearbitLookupService` | Clearbit enrichment | 7 | 92 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 91 | **B** | `Enterprise::CloudflareVerificationJob` | Cloudflare custom domains | 3 | 22 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 92 | **B** | `Enterprise::Concerns::Account` | All enterprise associations | 0 | 27 | no | `app/models/account.rb:242` (include) | Drops 18 has_many/has_one declarations (SLA, custom roles, agent capacity, Captain, copilot, companies, calls, SAML) and their dependent: :destroy_async cascades. See section 5. |
| 93 | **B** | `Enterprise::Concerns::AccountUser` | Custom roles / agent capacity | 0 | 8 | no | `app/models/account_user.rb:104` (include) | Drops belongs_to :custom_role and :agent_capacity_policy. |
| 94 | **B** | `Enterprise::Concerns::Attachment` | Audio transcription | 2 | 34 | no | `app/models/attachment.rb:228` (include) | Drops Whisper transcription (Messages::AudioTranscriptionJob is enterprise) and the extra audio broadcast. Verified that WhatsApp inbound media attaches its blob in the same save (incoming_message_base_service.rb:151-160), so WhatsApp voice notes still render from the normal message_created event. |
| 95 | **B** | `Enterprise::Concerns::Conversation` | SLA / voice / Captain | 3 | 53 | no | `app/models/conversation.rb:435` (include) | Drops the SLA validation and applied-SLA creation hooks and the enterprise associations. |
| 96 | **B** | `Enterprise::Concerns::Inbox` | Captain / agent capacity / plan limits | 1 | 19 | no | `app/models/inbox.rb:283` (include) | Drops captain_inbox, inbox_capacity_limits, calls and `ensure_create_permitted` (the per-plan inbox cap). |
| 97 | **B** | `Enterprise::Concerns::Message` | Voice / Captain | 0 | 8 | no | `app/models/message.rb:463` (include) | Drops has_one :call and has_many :message_reports. |
| 98 | **B** | `Enterprise::Concerns::User` | Premium licence seat limit / Captain | 1 | 16 | yes | `app/models/user.rb:230` (include) | ensure_installation_pricing_plan_quantity returns unless ChatwootHub.pricing_plan == 'premium' (this installation is community). |
| 99 | **B** | `Enterprise::ContactInboxBuilder` | Twilio voice | 4 | 25 | yes | `app/builders/contact_inbox_builder.rb:107` (prepend) | Only branches when `channel.voice_enabled?` on a TwilioSms inbox; every other path already calls super. |
| 100 | **B** | `Enterprise::ContactMergeAction` | Voice calling | 1 | 7 | no | `app/actions/contact_merge_action.rb:69` (prepend) | Re-points Call rows on contact merge. `Call` is an enterprise model; nothing else reads it. |
| 101 | **B** | `Enterprise::Conversation` | SLA / voice / Captain | 7 | 69 | yes | `app/models/conversation.rb:436` (prepend) | determine_conversation_status reverts to super (Lynomia's bots are agent_bot, not Captain); allowed_keys? stops rebroadcasting on call_status/call_direction; sla_policy_id leaves list_of_keys. |
| 102 | **B** | `Enterprise::Conversations::AssignmentService` | Captain | 3 | 19 | yes | `app/services/conversations/assignment_service.rb:62` (prepend) | Only branches when assignee_type == 'Captain::Assistant'. |
| 103 | **B** | `Enterprise::CreateStripeCustomerJob` | Stripe cloud billing | 2 | 24 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 104 | **B** | `Enterprise::DeviseOverrides::OmniauthCallbacksController` | SAML SSO + marketing attribution | 15 | 109 | yes | `app/controllers/devise_overrides/omniauth_callbacks_controller.rb:111` (prepend) | `omniauth_success` falls through to super for every non-saml provider, so Google OAuth login is untouched. Verified line by line. |
| 105 | **B** | `Enterprise::DeviseOverrides::PasswordsController` | SAML SSO | 1 | 16 | yes | `app/controllers/devise_overrides/passwords_controller.rb:44` (prepend) | Removes the password-reset refusal for provider='saml' users; no SAML users exist without the overlay. |
| 106 | **B** | `Enterprise::Inbox` | Agent capacity / Captain | 6 | 41 | yes | `app/models/inbox.rb:281` (prepend) | member_ids_with_assignment_capacity and active_bot? revert to OSS. |
| 107 | **B** | `Enterprise::Internal::TriggerDailyScheduledItemsJob` | Captain document sync | 3 | 19 | yes | `app/jobs/internal/trigger_daily_scheduled_items_job.rb:27` (prepend) | Stops enqueueing Captain::Documents::ScheduleSyncsJob. |
| 108 | **B** | `Enterprise::Internal::TriggerHourlyScheduledItemsJob` | Shopify cloud billing | 1 | 9 | yes | `app/jobs/internal/trigger_hourly_scheduled_items_job.rb:9` (prepend) | Stops the Shopify subscription reconciliation job. |
| 109 | **B** | `Enterprise::Message` | Captain / voice | 8 | 84 | yes | `app/models/message.rb:462` (prepend) | OSS defines mark_pending_conversation_as_open_for_human_response and reopen_resolved_conversation; the EE versions only add Captain branches. push_event_data only adds call data for content_type='voice_call'. |
| 110 | **B** | `Enterprise::Messages::MessageBuilder` | Voice calling | 2 | 13 | yes | `app/builders/messages/message_builder.rb:237` (prepend) | Only branches for content_type='voice_call'; otherwise super. |
| 111 | **B** | `Enterprise::Shopify::UninstallationService` | Shopify cloud billing | 4 | 36 | yes | `app/services/shopify/uninstallation_service.rb:47` (prepend) | Returns super unless the account is Shopify-billed, which requires the enterprise billing identity. |
| 112 | **B** | `Enterprise::SyncDispatcher` | Captain | 1 | 7 | yes | `app/dispatchers/sync_dispatcher.rb:12` (prepend) | Drops Captain::ConversationOutcomeEventListener. |
| 113 | **B** | `Enterprise::TriggerScheduledItemsJob` | SLA | 1 | 11 | yes | `app/jobs/trigger_scheduled_items_job.rb:28` (prepend) | Stops Sla::TriggerSlasForAccountsJob; every SLA job lives in enterprise/. |
| 114 | **B** | `Enterprise::Webhooks::FirecrawlController` | Captain document crawling | 7 | 47 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 115 | **B** | `Enterprise::Webhooks::StripeController` | Stripe cloud billing | 1 | 21 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 116 | **B** | `Enterprise::Webhooks::WhatsappEventsJob` | WhatsApp calling | 7 | 60 | yes | `app/jobs/webhooks/whatsapp_events_job.rb:242` (prepend) | `handle_message_events` returns super for everything except field=='calls' and interactive.type=='call_permission_reply'. Lynomia's inbound WhatsApp messaging, statuses and templates are untouched. Verified line by line. |
| 117 | **B** | `Enterprise::Whatsapp::Providers::WhatsappCloudService` | WhatsApp calling | 15 | 122 | no | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:263` (prepend) | Adds only the Calls API and call_permission_request methods. Lynomia edited it once (commit 64156a71) to stop pinning its own Graph version; that change is moot once the file goes. |
| 118 | **C** | `Enterprise::AccountUser` | Custom roles | 1 | 5 | yes | `app/models/account_user.rb:102` (prepend) | `permissions` reverts to OSS (['administrator'] or ['agent']). Lynomia's Commerce::ActionPolicy reads this, so `commerce_order_manage` can no longer be granted and order status changes / e-mail resends become administrator-only. No crash. |
| 119 | **C** | `Enterprise::Api::V1::Accounts::Conversations::MessagesController` | Audit log | 3 | 39 | yes | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:132` (prepend) | Message deletion is no longer written to `audits`. Deletion itself is OSS and unchanged. |
| 120 | **C** | `Enterprise::Audit::AgentBot` | Audit log | 0 | 7 | no | `app/models/agent_bot.rb:72` (include) | AgentBot (Flow Builder bot) changes stop being audited. Lynomia's Flows::Audit is already guarded and silently no-ops. |
| 121 | **C** | `Enterprise::Audit::AutomationRule` | Audit log | 0 | 7 | no | `app/models/automation_rule.rb:162` (include) | Automation rule changes stop being audited. |
| 122 | **C** | `Enterprise::Audit::Inbox` | Audit log | 0 | 7 | no | `app/models/inbox.rb:282` (include) | Inbox create/update stops being audited. |
| 123 | **C** | `Enterprise::Audit::InboxMember` | Audit log | 3 | 31 | no | `app/models/inbox_member.rb:44` (include) | Inbox member add/remove stops being audited. |
| 124 | **C** | `Enterprise::Audit::Macro` | Audit log | 0 | 7 | no | `app/models/macro.rb:78` (include) | Macro changes stop being audited. |
| 125 | **C** | `Enterprise::Audit::Team` | Audit log | 0 | 7 | no | `app/models/team.rb:89` (include) | Team changes stop being audited. |
| 126 | **C** | `Enterprise::Audit::TeamMember` | Audit log | 3 | 31 | no | `app/models/team_member.rb:31` (include) | Team member add/remove stops being audited. |
| 127 | **C** | `Enterprise::Audit::Webhook` | Audit log | 0 | 7 | no | `app/models/webhook.rb:46` (include) | Webhook changes stop being audited. |
| 128 | **C** | `Enterprise::AuditLog` | Audit log | 6 | 87 | no | — (nested/internal) | Enterprise-internal: no OSS injection site and no reference from `app/`, `lib/`, `custom/`, `config/` or `db/` (measured). |
| 129 | **C** | `Enterprise::DeleteObjectJob` | Audit log + SLA | 3 | 26 | yes | `app/jobs/delete_object_job.rb:43` (prepend) | OSS defines `process_post_deletion_tasks`; deletions of Inbox/Conversation stop writing an audit entry. SlaPolicy heavy associations go with the model. |
| 130 | **C** | `Enterprise::DeviseOverrides::SessionsController` | SAML SSO + sign-in/out audit | 6 | 73 | yes | `app/controllers/devise_overrides/sessions_controller.rb:244` (prepend) | Sign-in and sign-out stop being written to `audits`. This is the only place session events are audited. Login itself is OSS. |
| 131 | **D** | `Enterprise::Campaign` | Campaign recipients | 0 | 7 | no | `app/models/campaign.rb:173` (include) | Removes has_many :campaign_recipients. See section 4 - this is the one Lynomia-shipped capability that needs replacing. |
| 132 | **D** | `Enterprise::Channel::Whatsapp` | Campaign recipients | 1 | 12 | no | `app/models/channel/whatsapp.rb:238` (prepend) | `send_template` wrapper that records last_provider_error. Measured: no OSS or custom code reads last_provider_error - only Enterprise::Whatsapp::OneoffCampaignService does, to mark a recipient failed. |
| 133 | **D** | `Enterprise::Concerns::Contact` | Companies + campaign recipients | 4 | 52 | no | `app/models/contact.rb:263` (include) | Company association is feature-gated (B), but this is also where has_many :campaign_recipients lives. |
| 134 | **D** | `Enterprise::Whatsapp::IncomingMessageBaseService` | Campaign recipients | 1 | 17 | yes | `app/services/whatsapp/incoming_message_base_service.rb:230` (prepend) | `process_statuses` updates CampaignRecipient from WhatsApp delivery statuses and enqueues Campaigns::UpdateRecipientStatusJob, then calls super. Ordinary message statuses are handled by super and are unaffected; campaign delivery/read/failed tracking stops. |
| 135 | **D** | `Enterprise::Whatsapp::OneoffCampaignService` | Campaign recipients | 9 | 110 | no | `app/services/whatsapp/oneoff_campaign_service.rb:148` (prepend) | Replaces #perform outright. OSS Whatsapp::OneoffCampaignService still sends the campaign (Lynomia's campaign.audience_contacts is in app/models/campaign.rb), but creates no CampaignRecipient rows, so per-recipient sent/skipped/failed state disappears. This file is also one of the six enterprise files Lynomia has edited (commit 7f9f053a). |
| 136 | **D** | `Enterprise::Whatsapp::Providers::BaseService` | Campaign recipients | 3 | 25 | yes | `app/services/whatsapp/providers/base_service.rb:136` (prepend) | Captures last_error for the campaign recipient failure message; no other reader. |

---

## 3. Phase 2 — the smallest safe replacement plan (design only, not implemented)

### 3.1 `Enterprise::AuditLog`

**What Lynomia actually depends on.** Exactly 6 lines, all of them guarded or in a config file
*(measured: `grep -rn 'Enterprise::AuditLog' app lib custom config db`)*:

| Site | Line |
|:--|:--|
| `custom/app/services/flows/audit.rb:11` | `return unless defined?(Enterprise::AuditLog)` |
| `custom/app/services/flows/audit.rb:13` | `Enterprise::AuditLog.create!(auditable: agent_bot, …)` |
| `custom/app/services/commerce/audit_trail.rb:27` | `return unless defined?(Enterprise::AuditLog)` |
| `custom/app/services/commerce/audit_trail.rb:29` | `Enterprise::AuditLog.create!(…)` |
| `custom/app/models/custom/audit/custom_filter.rb:8` | `audited associated_with: :account, if: :contact? if defined?(Enterprise::AuditLog)` |
| `config/initializers/audited.rb:4` | `config.audit_class = 'Enterprise::AuditLog'` |

**Why no new audit engine is needed.** The `audited` gem is an **OSS** dependency
(`Gemfile:184`, `audited (5.4.1)`), the `audits` table is created by an **OSS** migration
(`db/migrate/20230426130150_init_schema.rb`, plus `20260813000000_add_geo_location_to_audits.rb` and
`20260814000000_add_associated_created_at_index_to_audits.rb`, all under `db/migrate`) and is in
`db/schema.rb:264`. `Enterprise::AuditLog` is only `class Enterprise::AuditLog < Audited::Audit`
(`enterprise/app/models/enterprise/audit_log.rb:29`) — the *same* `audits` table.

**Measured, in the no-enterprise worktree:**

```
Audited.audit_class            = Audited::Audit
Audited.audit_class.table_name = audits
audits table exists            = true
models still declaring `audited`:
  Whatsapp::MessageTemplate   opts={associated_with: :account, on: [:create, :update, :touch, :destroy]}
```

`Audited.audit_class` resolves because the gem uses `safe_constantize` and then
`@audit_class ||= Audited::Audit` — the missing constant in `config/initializers/audited.rb` degrades
silently rather than raising. And **Lynomia's Template Manager audit trail keeps working unchanged**,
because `custom/app/models/whatsapp/message_template.rb:46` calls `audited` without a guard.

**The replacement, in full:**

1. `config/initializers/audited.rb` — either delete the file (the gem then uses `Audited::Audit`) or
   point it at a Lynomia-owned subclass, `Custom::AuditLog < Audited::Audit`, on the same table.
   Prefer the subclass: it keeps a Lynomia-owned place for the `auditable_finder` scope and the
   geolocation columns the enterprise class used, and it makes the audit class greppable.
2. `custom/app/services/flows/audit.rb` — drop the `defined?` guard on line 11 and replace the
   `Enterprise::AuditLog.create!` on line 13 with the Lynomia class.
3. `custom/app/services/commerce/audit_trail.rb` — the same two edits at lines 27 and 29.
4. `custom/app/models/custom/audit/custom_filter.rb:8` — make `audited` unconditional (dropping
   `if defined?(Enterprise::AuditLog)`), which *restores* audience auditing that the guard silently
   disables today once enterprise is gone.

**No migration. No new table. No new gem. No new engine.** Four files, roughly eight lines.

**What is consciously not replaced.** The 11 `Enterprise::Audit::*` concerns that audit Account,
AccountUser, AgentBot, AutomationRule, Conversation, Inbox, InboxMember, Macro, Team, TeamMember and
Webhook, and the manual sign-in/sign-out and deletion audit writes in
`Enterprise::DeviseOverrides::SessionsController` and `Enterprise::DeleteObjectJob`. Each is a
one-line `audited …` declaration that could be ported to `custom/` at any time; none is required for
any Lynomia feature to function. They are listed here so the loss is a decision rather than an
accident. If the audit trail is a compliance requirement, the cheapest restoration is to add the
same `audited` declarations under `custom/app/models/custom/audit/` — the table and gem are already
there.

### 3.2 The three unguarded Enterprise routes

The phase-0 audit flagged three route declarations in `config/routes.rb` that are **not** inside an
`if ChatwootApp.enterprise?` block even though their controllers exist only in `enterprise/`:

| Route | Line | Controller |
|:--|:--|:--|
| `resource :saml_settings, only: [:show, :create, :update, :destroy]` | `config/routes.rb:115` | `enterprise/app/controllers/api/v1/accounts/saml_settings_controller.rb` |
| `resource :audit_logs, only: [:show]` | `config/routes.rb:127` | `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb` |
| `post 'auth/saml_login', to: 'auth#saml_login'` | `config/routes.rb:473` | `enterprise/app/controllers/api/v1/auth_controller.rb` |

**Measured behaviour with `enterprise/` gone** — a Puma server was booted in the no-enterprise
worktree in production mode and each endpoint requested:

```
GET  /                                                    200
GET  /app/login                                           200
GET  /super_admin/sign_in                                 200
GET  /api/v1/accounts/1/saml_settings                     404
GET  /api/v1/accounts/1/audit_logs                        404
POST /api/v1/auth/saml_login                              404
GET  /api/v1/accounts/1/sla_policies                      404
GET  /api/v1/accounts/1/custom_roles                      404
GET  /api/v1/accounts/1/captain/assistants                404
GET  /api/v1/accounts/1/companies                         404
GET  /api/v1/accounts/1/portals/1/ssl_status              404
GET  /api/v1/accounts/1/conversations/1/inbox_assistant   404
GET  /api/v1/accounts/1/contacts                          401   (OSS path, auth required — healthy)
```

The log shows why: a missing controller raises `ActionController::RoutingError (uninitialized
constant …)`, which Rails maps to **404**; a missing action on a present OSS controller raises
`AbstractController::ActionNotFound`, also **404**. **No route produces a 500.** That changes the
decision: these three are hygiene, not blockers.

**Decision for each — REMOVE, not guard, not replace:**

* **`saml_settings`** — REMOVE. SAML SSO is an enterprise capability Lynomia does not ship; the
  frontend route that would consume it is already gated (`installationTypes: [CLOUD, ENTERPRISE]`),
  and `app/controllers/dashboard_controller.rb:105` already withholds the `saml` auth method unless
  `ChatwootHub.pricing_plan != 'community'`.
* **`audit_logs`** — REMOVE the route. Note that this is the *viewer*, not the writer: the `audits`
  table and Lynomia's own audit writes (section 3.1) are independent of it. If an audit viewer is
  wanted later it is a Lynomia controller over `audits`, not a restoration of this one.
* **`auth/saml_login`** — REMOVE, with `saml_settings`.

Guarding them with `if ChatwootApp.enterprise?` would be equally correct but leaves a conditional
whose condition can never be true once the directory is gone; removing the declarations is smaller
and does not change any status code a client sees (404 either way).

**And three more the phase-0 audit missed** — the measurement found 27 enterprise-only controllers
and 2 enterprise-added actions reachable through ungated route declarations, not 3. The two
*actions* deserve naming because they sit on OSS controllers and so cannot be found by looking for
missing controller files:

| Route | Target | Added only by |
|:--|:--|:--|
| `GET /api/v1/accounts/:id/portals/:id/ssl_status` | `Api::V1::Accounts::PortalsController#ssl_status` | `Enterprise::Api::V1::Accounts::PortalsController` |
| `GET /api/v1/accounts/:id/conversations/:id/inbox_assistant` | `Api::V1::Accounts::ConversationsController#inbox_assistant` | `Enterprise::Api::V1::Accounts::ConversationsController` |

Section 4 carries the complete list.

### 3.3 The cloud billing frontend

**What is actually there.** Lynomia owns its billing: `config/routes.rb:793` draws a Lynomia route
file, served by `custom/app/controllers/api/v1/accounts/billing_controller.rb` and
`custom/app/services/billing/plan_change.rb`, consumed by
`app/javascript/dashboard/api/billingSubscription.js` (whose own comment reads
*"Custom billing API: /api/v1/accounts/:accountId/billing"*). None of that touches `enterprise/`.

The *Chatwoot cloud* billing frontend is one API module and two consumers:

| File | What it calls |
|:--|:--|
| `app/javascript/dashboard/api/enterprise/account.js` | `POST …/subscription`, `GET …/billing_summary`, `POST …/checkout`, `POST …/toggle_deletion`, `…/limits`, `…/topup_*`, `…/select_billing_currency` |
| `app/javascript/dashboard/store/modules/accounts.js:6,124,147,156` | `toggleDeletion`, `checkout`, `subscription` actions |
| `app/javascript/dashboard/routes/dashboard/settings/billing/ShopifyBilling.vue:7` | Shopify plan management |

Every endpoint it calls lives under `/enterprise/api/v1/accounts/…`, drawn inside an
`if ChatwootApp.enterprise?` block, and all 16 of those route entries vanish on removal *(measured —
section 4)*.

**Decision: REMOVE, in this order.**

1. Delete `app/javascript/dashboard/routes/dashboard/settings/billing/ShopifyBilling.vue` and its
   route entry. Shopify-as-biller requires `Account#billing_provider`, which is
   `Enterprise::AccountBillingIdentity` and has no OSS or Lynomia caller.
2. Delete the three Vuex actions in `store/modules/accounts.js` (`checkout`, `subscription`,
   `toggleDeletion`) and the `EnterpriseAccountAPI` import, then delete
   `app/javascript/dashboard/api/enterprise/account.js` and the now-empty
   `app/javascript/dashboard/api/enterprise/` directory.
3. Leave `settings/billing/` and `settings/subscription/` alone apart from step 1 — they are
   Lynomia's own pages on Lynomia's own API.

`toggleDeletion` deserves one sentence: it is the only consumer of `Account#mark_for_deletion` /
`#unmark_for_deletion`, and the measurement confirmed those two methods have **no** caller in
`app/`, `lib/`, `custom/` or `config/`. Account self-deletion is an enterprise/cloud capability, not
a Lynomia one, and removing the frontend removes the only way to reach it.

---

## 4. Phase 3 — route impact map

### 4.1 Method and totals (measured)

The full route table was dumped from a booted application twice — once in the primary checkout with
`enterprise/` present, once in the no-enterprise worktree — and the two were diffed. Every route was
then resolved to its controller class and action, in both trees, so that "broken" means *measured
constant and action resolution*, not a guess from a filename.

| Measure | Count |
|--:|:--|
| 939 | route entries with `enterprise/` present |
| 896 | route entries with `enterprise/` absent |
| **43** | **route entries that vanish** — their declaration is inside an `if ChatwootApp.enterprise?` block |
| **119** | **route entries that newly fail to resolve** — ungated declarations whose controller or action lives only in `enterprise/` |
| **162** | **total enterprise-affected route entries** |
| 778 | route entries unaffected (KEEP, no change) |
| 52 | route entries that were already unresolvable *before* removal (pre-existing OSS artefacts: `new`/`edit` members on API-only `resources`, devise_token_auth registration actions, the `/app/accounts` shell routes). Identical in both runs, excluded from the 162. |

Of the 119 that newly fail, **117** are whole controllers that exist only under `enterprise/`
(27 distinct controller classes) and **2** are actions added to an existing OSS controller by an
`Enterprise::` overlay. All 162 produce **404**, never 500 (section 3.2).

The phase-0 audit reported 154 routes across 38 controllers. The measured figure is 162 route
entries across 27 missing controllers plus 2 missing actions plus 11 gated controller/action
targets. Section 9 records the correction.

### 4.2 Decisions by capability

| Capability | Enterprise routes | Guarded today | Behaviour once `enterprise/` is gone | Required by Lynomia | Action |
|:--|--:|:--|:--|:--|:--|
| Agent capacity | 13 | 0 gated / 13 ungated | 404 | no | **REMOVE** |
| Audit log | 1 | 0 gated / 1 ungated | 404 | no | **REMOVE** |
| CSAT review notes | 1 | 1 gated / 0 ungated | route disappears | no | **REMOVE** |
| Call recording | 2 | 2 gated / 0 ungated | route disappears | no | **REMOVE** |
| Campaign recipients — WhatsApp campaign analytics | 2 | 2 gated / 0 ungated | route disappears | **yes** | **REPLACE** |
| Captain | 1 | 0 gated / 1 ungated | 404 | no | **REMOVE** |
| Captain document crawling | 1 | 1 gated / 0 ungated | route disappears | no | **REMOVE** |
| Captain — assistants, copilot, documents, scenarios, tools, FAQ | 66 | 0 gated / 66 ungated | 404 | no | **REMOVE** |
| Cloud billing / account lifecycle | 16 | 16 gated / 0 ungated | route disappears | no | **REMOVE** |
| Cloudflare custom domains | 2 | 0 gated / 2 ungated | 404 | no | **REMOVE** |
| Companies CRM | 15 | 0 gated / 15 ungated | 404 | no | **REMOVE** |
| Conversation reporting events | 2 | 2 gated / 0 ungated | route disappears | no | **REMOVE** |
| Custom roles | 6 | 0 gated / 6 ungated | 404 | no | **REMOVE** |
| SAML SSO | 6 | 0 gated / 6 ungated | 404 | no | **REMOVE** |
| SLA | 9 | 0 gated / 9 ungated | 404 | no | **REMOVE** |
| Stripe cloud billing | 1 | 1 gated / 0 ungated | route disappears | no | **REMOVE** |
| Twilio voice conference | 4 | 4 gated / 0 ungated | route disappears | no | **REMOVE** |
| Twilio voice webhooks | 3 | 3 gated / 0 ungated | route disappears | no | **REMOVE** |
| WhatsApp / Twilio calling | 2 | 2 gated / 0 ungated | route disappears | no | **REMOVE** |
| WhatsApp calling | 8 | 8 gated / 0 ungated | route disappears | no | **REMOVE** |
| WhatsApp embedded-signup access request (cloud only) | 1 | 1 gated / 0 ungated | route disappears | no | **REMOVE** |

The one-route "Captain" row is `Api::V1::Accounts::ConversationsController#inbox_assistant`; the
66-route "Captain" row is the `captain/*` controller tree. The only **REPLACE** is the WhatsApp
campaign analytics pair, which is the subject of section 4.4.

**Nothing in this table is KEEP-with-changes and nothing needs GUARD.** Because every affected
route already answers 404 once the overlay is gone, guarding adds no safety; the action is to delete
the declarations as part of the removal commit so that `rails routes` tells the truth.

### 4.3 The complete route detail

Every one of the 162 affected route entries, in full:

| Route | Target | Guarded | Without `enterprise/` | Capability | Action |
|:--|:--|:--|:--|:--|:--|
| `/api/v1/accounts/:account_id/agent_capacity_policies` | `Api::V1::Accounts::AgentCapacityPoliciesController#create` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies` | `Api::V1::Accounts::AgentCapacityPoliciesController#index` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/inbox_limits` | `Api::V1::Accounts::AgentCapacityPolicies::InboxLimitsController#create` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/inbox_limits/:id` | `Api::V1::Accounts::AgentCapacityPolicies::InboxLimitsController#destroy` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/inbox_limits/:id` | `Api::V1::Accounts::AgentCapacityPolicies::InboxLimitsController#update` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/inbox_limits/:id` | `Api::V1::Accounts::AgentCapacityPolicies::InboxLimitsController#update` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/users` | `Api::V1::Accounts::AgentCapacityPolicies::UsersController#create` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/users` | `Api::V1::Accounts::AgentCapacityPolicies::UsersController#index` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:agent_capacity_policy_id/users/:id` | `Api::V1::Accounts::AgentCapacityPolicies::UsersController#destroy` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:id` | `Api::V1::Accounts::AgentCapacityPoliciesController#destroy` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:id` | `Api::V1::Accounts::AgentCapacityPoliciesController#show` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:id` | `Api::V1::Accounts::AgentCapacityPoliciesController#update` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/agent_capacity_policies/:id` | `Api::V1::Accounts::AgentCapacityPoliciesController#update` | ungated | 404 (RoutingError) | Agent capacity | REMOVE |
| `/api/v1/accounts/:account_id/audit_logs` | `Api::V1::Accounts::AuditLogsController#show` | ungated | 404 (RoutingError) | Audit log | REMOVE |
| `/api/v1/accounts/:account_id/csat_survey_responses/:id` | `api/v1/accounts/csat_survey_responses#update` | gated | already inert | CSAT review notes | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:id/set_call_recording` | `api/v1/accounts/inboxes#set_call_recording` | gated | already inert | Call recording | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:id/set_inbound_calls` | `api/v1/accounts/inboxes#set_inbound_calls` | gated | already inert | Call recording | REMOVE |
| `/api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/contacts` | `api/v1/accounts/campaigns/analytics#contacts` | gated | already inert | Campaign recipients — WhatsApp campaign analytics | REPLACE |
| `/api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/metrics` | `api/v1/accounts/campaigns/analytics#metrics` | gated | already inert | Campaign recipients — WhatsApp campaign analytics | REPLACE |
| `/api/v1/accounts/:account_id/conversations/:id/inbox_assistant` | `Api::V1::Accounts::ConversationsController#inbox_assistant` | ungated | 404 (ActionNotFound) | Captain | REMOVE |
| `/enterprise/webhooks/firecrawl` | `enterprise/webhooks/firecrawl#process_payload` | gated | already inert | Captain document crawling | REMOVE |
| `/api/v1/accounts/:account_id/captain/agent_sessions/:id` | `Api::V1::Accounts::Captain::AgentSessionsController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses` | `Api::V1::Accounts::Captain::AssistantResponsesController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses` | `Api::V1::Accounts::Captain::AssistantResponsesController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id` | `Api::V1::Accounts::Captain::AssistantResponsesController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id` | `Api::V1::Accounts::Captain::AssistantResponsesController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id` | `Api::V1::Accounts::Captain::AssistantResponsesController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id` | `Api::V1::Accounts::Captain::AssistantResponsesController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id/drilldown` | `Api::V1::Accounts::Captain::AssistantResponsesController#drilldown` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/:id/edit` | `Api::V1::Accounts::Captain::AssistantResponsesController#edit` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistant_responses/new` | `Api::V1::Accounts::Captain::AssistantResponsesController#new` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants` | `Api::V1::Accounts::Captain::AssistantsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants` | `Api::V1::Accounts::Captain::AssistantsController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/inboxes` | `Api::V1::Accounts::Captain::InboxesController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/inboxes` | `Api::V1::Accounts::Captain::InboxesController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/inboxes/:inbox_id` | `Api::V1::Accounts::Captain::InboxesController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios` | `Api::V1::Accounts::Captain::ScenariosController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios` | `Api::V1::Accounts::Captain::ScenariosController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/:id` | `Api::V1::Accounts::Captain::ScenariosController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/:id` | `Api::V1::Accounts::Captain::ScenariosController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/:id` | `Api::V1::Accounts::Captain::ScenariosController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/:id` | `Api::V1::Accounts::Captain::ScenariosController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/:id/edit` | `Api::V1::Accounts::Captain::ScenariosController#edit` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/scenarios/new` | `Api::V1::Accounts::Captain::ScenariosController#new` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/stats/overview` | `Api::V1::Accounts::Captain::AssistantStatsController#overview` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/stats/overview_summary` | `Api::V1::Accounts::Captain::AssistantStatsController#overview_summary` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/stats/resolution_flow` | `Api::V1::Accounts::Captain::AssistantStatsController#resolution_flow` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:assistant_id/stats/resolution_trend` | `Api::V1::Accounts::Captain::AssistantStatsController#resolution_trend` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id` | `Api::V1::Accounts::Captain::AssistantsController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id` | `Api::V1::Accounts::Captain::AssistantsController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id` | `Api::V1::Accounts::Captain::AssistantsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id` | `Api::V1::Accounts::Captain::AssistantsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/drilldown` | `Api::V1::Accounts::Captain::AssistantsController#drilldown` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/edit` | `Api::V1::Accounts::Captain::AssistantsController#edit` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/faq_stats` | `Api::V1::Accounts::Captain::AssistantsController#faq_stats` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/metrics` | `Api::V1::Accounts::Captain::AssistantsController#metrics` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/playground` | `Api::V1::Accounts::Captain::AssistantsController#playground` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/:id/summary` | `Api::V1::Accounts::Captain::AssistantsController#summary` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/new` | `Api::V1::Accounts::Captain::AssistantsController#new` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/assistants/tools` | `Api::V1::Accounts::Captain::AssistantsController#tools` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/bulk_actions` | `Api::V1::Accounts::Captain::BulkActionsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/copilot_threads` | `Api::V1::Accounts::Captain::CopilotThreadsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/copilot_threads` | `Api::V1::Accounts::Captain::CopilotThreadsController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/copilot_messages` | `Api::V1::Accounts::Captain::CopilotMessagesController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/copilot_messages` | `Api::V1::Accounts::Captain::CopilotMessagesController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools` | `Api::V1::Accounts::Captain::CustomToolsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools` | `Api::V1::Accounts::Captain::CustomToolsController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/:id` | `Api::V1::Accounts::Captain::CustomToolsController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/:id` | `Api::V1::Accounts::Captain::CustomToolsController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/:id` | `Api::V1::Accounts::Captain::CustomToolsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/:id` | `Api::V1::Accounts::Captain::CustomToolsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/:id/edit` | `Api::V1::Accounts::Captain::CustomToolsController#edit` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/new` | `Api::V1::Accounts::Captain::CustomToolsController#new` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/custom_tools/test` | `Api::V1::Accounts::Captain::CustomToolsController#test` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents` | `Api::V1::Accounts::Captain::DocumentsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents` | `Api::V1::Accounts::Captain::DocumentsController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents/:id` | `Api::V1::Accounts::Captain::DocumentsController#destroy` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents/:id` | `Api::V1::Accounts::Captain::DocumentsController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents/:id/drilldown` | `Api::V1::Accounts::Captain::DocumentsController#drilldown` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/documents/:id/sync` | `Api::V1::Accounts::Captain::DocumentsController#sync` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions` | `Api::V1::Accounts::Captain::FaqSuggestionsController#index` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions/:id` | `Api::V1::Accounts::Captain::FaqSuggestionsController#show` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions/:id` | `Api::V1::Accounts::Captain::FaqSuggestionsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions/:id` | `Api::V1::Accounts::Captain::FaqSuggestionsController#update` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions/:id/approve` | `Api::V1::Accounts::Captain::FaqSuggestionsController#approve` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/faq_suggestions/:id/dismiss` | `Api::V1::Accounts::Captain::FaqSuggestionsController#dismiss` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/api/v1/accounts/:account_id/captain/message_reports` | `Api::V1::Accounts::Captain::MessageReportsController#create` | ungated | 404 (RoutingError) | Captain — assistants, copilot, documents, scenarios, tools, FAQ | REMOVE |
| `/enterprise/api/v1/accounts` | `enterprise/api/v1/accounts#index` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts` | `enterprise/api/v1/accounts#create` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id` | `enterprise/api/v1/accounts#destroy` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id` | `enterprise/api/v1/accounts#show` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id` | `enterprise/api/v1/accounts#update` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id` | `enterprise/api/v1/accounts#update` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/billing_summary` | `enterprise/api/v1/accounts#billing_summary` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/checkout` | `enterprise/api/v1/accounts#checkout` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/edit` | `enterprise/api/v1/accounts#edit` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/limits` | `enterprise/api/v1/accounts#limits` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/select_billing_currency` | `enterprise/api/v1/accounts#select_billing_currency` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/subscription` | `enterprise/api/v1/accounts#subscription` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/toggle_deletion` | `enterprise/api/v1/accounts#toggle_deletion` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/topup_checkout` | `enterprise/api/v1/accounts#topup_checkout` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/:id/topup_options` | `enterprise/api/v1/accounts#topup_options` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/enterprise/api/v1/accounts/new` | `enterprise/api/v1/accounts#new` | gated | already inert | Cloud billing / account lifecycle | REMOVE |
| `/.well-known/cf-custom-hostname-challenge/:id` | `CustomDomainsController#verify` | ungated | 404 (RoutingError) | Cloudflare custom domains | REMOVE |
| `/api/v1/accounts/:account_id/portals/:id/ssl_status` | `Api::V1::Accounts::PortalsController#ssl_status` | ungated | 404 (ActionNotFound) | Cloudflare custom domains | REMOVE |
| `/api/v1/accounts/:account_id/companies` | `Api::V1::Accounts::CompaniesController#create` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies` | `Api::V1::Accounts::CompaniesController#index` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/contacts` | `Api::V1::Accounts::Companies::ContactsController#create` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/contacts` | `Api::V1::Accounts::Companies::ContactsController#index` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/contacts/:id` | `Api::V1::Accounts::Companies::ContactsController#destroy` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/contacts/search` | `Api::V1::Accounts::Companies::ContactsController#search` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/conversations` | `Api::V1::Accounts::Companies::ConversationsController#index` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:company_id/notes` | `Api::V1::Accounts::Companies::NotesController#index` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id` | `Api::V1::Accounts::CompaniesController#destroy` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id` | `Api::V1::Accounts::CompaniesController#show` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id` | `Api::V1::Accounts::CompaniesController#update` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id` | `Api::V1::Accounts::CompaniesController#update` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id/avatar` | `Api::V1::Accounts::CompaniesController#avatar` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/:id/destroy_custom_attributes` | `Api::V1::Accounts::CompaniesController#destroy_custom_attributes` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/companies/search` | `Api::V1::Accounts::CompaniesController#search` | ungated | 404 (RoutingError) | Companies CRM | REMOVE |
| `/api/v1/accounts/:account_id/conversations/:id/reporting_events` | `api/v1/accounts/conversations#reporting_events` | gated | already inert | Conversation reporting events | REMOVE |
| `/api/v1/accounts/:account_id/reporting_events` | `api/v1/accounts/reporting_events#index` | gated | already inert | Conversation reporting events | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles` | `Api::V1::Accounts::CustomRolesController#create` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles` | `Api::V1::Accounts::CustomRolesController#index` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles/:id` | `Api::V1::Accounts::CustomRolesController#destroy` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles/:id` | `Api::V1::Accounts::CustomRolesController#show` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles/:id` | `Api::V1::Accounts::CustomRolesController#update` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/custom_roles/:id` | `Api::V1::Accounts::CustomRolesController#update` | ungated | 404 (RoutingError) | Custom roles | REMOVE |
| `/api/v1/accounts/:account_id/saml_settings` | `Api::V1::Accounts::SamlSettingsController#create` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/accounts/:account_id/saml_settings` | `Api::V1::Accounts::SamlSettingsController#destroy` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/accounts/:account_id/saml_settings` | `Api::V1::Accounts::SamlSettingsController#show` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/accounts/:account_id/saml_settings` | `Api::V1::Accounts::SamlSettingsController#update` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/accounts/:account_id/saml_settings` | `Api::V1::Accounts::SamlSettingsController#update` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/auth/saml_login` | `Api::V1::AuthController#saml_login` | ungated | 404 (RoutingError) | SAML SSO | REMOVE |
| `/api/v1/accounts/:account_id/applied_slas` | `Api::V1::Accounts::AppliedSlasController#index` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/applied_slas/download` | `Api::V1::Accounts::AppliedSlasController#download` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/applied_slas/metrics` | `Api::V1::Accounts::AppliedSlasController#metrics` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies` | `Api::V1::Accounts::SlaPoliciesController#create` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies` | `Api::V1::Accounts::SlaPoliciesController#index` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies/:id` | `Api::V1::Accounts::SlaPoliciesController#destroy` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies/:id` | `Api::V1::Accounts::SlaPoliciesController#show` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies/:id` | `Api::V1::Accounts::SlaPoliciesController#update` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/api/v1/accounts/:account_id/sla_policies/:id` | `Api::V1::Accounts::SlaPoliciesController#update` | ungated | 404 (RoutingError) | SLA | REMOVE |
| `/enterprise/webhooks/stripe` | `enterprise/webhooks/stripe#process_payload` | gated | already inert | Stripe cloud billing | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:inbox_id/conference` | `api/v1/accounts/conference#destroy` | gated | already inert | Twilio voice conference | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:inbox_id/conference` | `api/v1/accounts/conference#create` | gated | already inert | Twilio voice conference | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:inbox_id/conference/token` | `api/v1/accounts/conference#token` | gated | already inert | Twilio voice conference | REMOVE |
| `/twilio/voice/conference_status/:phone` | `twilio/voice#conference_status` | gated | already inert | Twilio voice conference | REMOVE |
| `/twilio/voice/call/:phone` | `twilio/voice#call_twiml` | gated | already inert | Twilio voice webhooks | REMOVE |
| `/twilio/voice/recording_status/:phone` | `twilio/voice#recording_status` | gated | already inert | Twilio voice webhooks | REMOVE |
| `/twilio/voice/status/:phone` | `twilio/voice#status` | gated | already inert | Twilio voice webhooks | REMOVE |
| `/api/v1/accounts/:account_id/calls` | `api/v1/accounts/calls#index` | gated | already inert | WhatsApp / Twilio calling | REMOVE |
| `/api/v1/accounts/:account_id/contacts/:id/call` | `api/v1/accounts/contacts/calls#create` | gated | already inert | WhatsApp / Twilio calling | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:id/disable_whatsapp_calling` | `api/v1/accounts/inboxes#disable_whatsapp_calling` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/inboxes/:id/enable_whatsapp_calling` | `api/v1/accounts/inboxes#enable_whatsapp_calling` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/:id` | `api/v1/accounts/whatsapp_calls#show` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/:id/accept` | `api/v1/accounts/whatsapp_calls#accept` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/:id/reject` | `api/v1/accounts/whatsapp_calls#reject` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/:id/terminate` | `api/v1/accounts/whatsapp_calls#terminate` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/:id/upload_recording` | `api/v1/accounts/whatsapp_calls#upload_recording` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp_calls/initiate` | `api/v1/accounts/whatsapp_calls#initiate` | gated | already inert | WhatsApp calling | REMOVE |
| `/api/v1/accounts/:account_id/whatsapp/access_request` | `api/v1/accounts/whatsapp/access_requests#create` | gated | already inert | WhatsApp embedded-signup access request (cloud only) | REMOVE |

### 4.4 The one REPLACE: WhatsApp campaign analytics

This is the single Lynomia-shipped capability that stops working, and it is worth stating end to
end because its frontend route is gated on a flag Lynomia **does** enable.

| Layer | File | Note |
|:--|:--|:--|
| Page | `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:244,272` | Calls `analyticsMetrics` and `analyticsContacts` |
| Route | `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js:64-72` | `featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS` and **no** `installationTypes` — so it stays reachable |
| API | `app/javascript/dashboard/api/campaigns.js:10,19` | `GET …/campaigns/:id/analytics/metrics`, `GET …/campaigns/:id/analytics/contacts` |
| Controller | `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | enterprise-only |
| Model | `enterprise/app/models/campaign_recipient.rb` | enterprise-only |
| Writer (send) | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | creates the rows and marks `sent` / `skipped` / `failed` |
| Writer (status) | `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb` | updates them from Meta delivery statuses, enqueues `Campaigns::UpdateRecipientStatusJob` |
| Associations | `enterprise/app/models/enterprise/campaign.rb`, `enterprise/app/models/enterprise/concerns/contact.rb` | `has_many :campaign_recipients` |
| Table | `campaign_recipients` | created by an **OSS** migration, present in `db/schema.rb` |

**What survives removal.** The campaign still sends. OSS
`app/services/whatsapp/oneoff_campaign_service.rb` implements the whole send path — including
`campaign.audience_contacts`, which is Lynomia's shared-audience resolution in
`app/models/campaign.rb` — so recipients are selected and templates are delivered exactly as today. Shared-audience resolution in particular survives untouched: it comes from `Custom::CampaignAudience`, prepended at `app/models/campaign.rb:174`, whose `super` falls through to OSS `Campaign#audience_contacts` (`campaign.rb:70-73`) once `Enterprise::Campaign` — injected separately at `campaign.rb:173` — is gone.
What disappears is the per-recipient record: who was sent, who was skipped and why, who failed with
which Meta error, and who later reported delivered or read.

**Measured in the no-enterprise worktree**, which confirms every claim above rather than inferring
it from the files:

```
Campaign ancestors (top 2)               = Custom::CampaignAudience, Campaign
Campaign#campaign_recipients association = nil
Campaign#audience_contacts responds      = true
Campaign#audience_ids responds           = true     <- Custom::CampaignAudience survives
Whatsapp::OneoffCampaignService ancestors = Whatsapp::OneoffCampaignService, ...   (bare OSS class)
  defines #perform                       = true     <- the campaign still sends
  defines #create_recipients             = false    <- but writes no recipient rows
CampaignRecipient                        = nil
Channel::Whatsapp#last_provider_error    = false
```

**Smallest safe replacement (design only).** `campaign_recipients` is an OSS table with OSS foreign
keys and **no** inbound references from any other table *(measured, section 5)*. So the replacement
is a move, not a rebuild:

1. `custom/app/models/campaign_recipient.rb` — a Lynomia model on the existing table, carrying the
   `mark_sent!` / `mark_skipped!` / `mark_failed!` / `update_from_whatsapp_status!` helpers from the
   enterprise model.
2. `custom/app/models/custom/campaign.rb` and `custom/app/models/custom/concerns/contact.rb` (or the
   existing `Custom::` overlays) — re-declare `has_many :campaign_recipients`.
3. Port the recipient-creating `#perform` / `#process_recipient` / `#create_recipients` chain into
   `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` as a `Custom::` prepend on the
   OSS service. Lynomia has already edited this logic once (commit `7f9f053a`), so the change is
   a relocation of code Lynomia owns in practice.
4. Port the `process_statuses` recipient update into a `Custom::` prepend on
   `Whatsapp::IncomingMessageBaseService`, plus `custom/app/jobs/campaigns/update_recipient_status_job.rb`.
5. Port `last_provider_error` / `last_error` — `Enterprise::Channel::Whatsapp#send_template` and
   `Enterprise::Whatsapp::Providers::BaseService#parsed_error` — into `Custom::` prepends. They
   exist only to give a failed recipient a usable Meta error message, and nothing else reads them
   *(measured)*.
6. Port `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` to
   `custom/app/controllers/…` and move its two route declarations out of the
   `if ChatwootApp.enterprise?` block.

That is six files, all of them relocations of existing code onto an existing table, with no schema
change. **Alternative, if campaign delivery reporting is not wanted at launch:** delete
`WhatsAppCampaignAnalyticsPage.vue`, its route entry and the two methods in `campaigns.js`, and
accept that a WhatsApp campaign reports only its own `completed` status. That is a product decision,
not an engineering constraint, and this document does not make it.

---

## 5. Phase 4 — data model impact

**No table is dropped. No migration is removed. The schema does not change.**

### 5.1 The decisive structural facts (measured)

1. **There is no `enterprise/db` directory.** Every migration for every enterprise table lives in
   OSS `db/migrate`, and `config/application.rb:59` adds only `custom/db/migrate` on top. Removing
   `enterprise/` therefore removes **zero** migrations and leaves `db/schema.rb` byte-identical.
   A fresh `db:schema:load` after removal still creates all 25 tables below.
2. **Zero foreign keys point *at* an enterprise-owned table.** Enumerated by asking PostgreSQL for
   `foreign_keys` on every table in the database and filtering for enterprise targets: the result
   set is empty. Nothing in OSS or `custom/` references these tables at the database level.
3. **The only foreign keys *from* an enterprise table into OSS tables are on
   `campaign_recipients`** — `contacts`, `accounts`, `campaigns`, `inboxes`, all
   `on_delete: :cascade`. Those cascades are defined in the database, not in Ruby, so they keep
   working whether or not a model exists. Deleting a contact or a campaign still cleans up its
   recipient rows after removal.

### 5.2 The 25 enterprise-owned tables

"Enterprise-owned" was determined by reflection, not filenames: every `ApplicationRecord`
descendant was asked for `Object.const_source_location`, and those whose defining file sits under
`enterprise/` were collected with their table names. `audits` is added by hand because
`Enterprise::AuditLog` descends from `Audited::Audit` rather than `ApplicationRecord`.

| Table | Model (all under `enterprise/`) | Capability | Migration lives in | Inbound FKs from other tables | Action |
|:--|:--|:--|:--|--:|:--|
| `account_saml_settings` | `AccountSamlSettings` | SAML SSO | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `agent_capacity_policies` | `AgentCapacityPolicy` | Agent capacity | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `agent_sessions` | `Captain::AgentSession` | Captain agent sessions | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `applied_slas` | `AppliedSla` | SLA | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `article_embeddings` | `ArticleEmbedding` | Help Center embedding search | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `calls` | `Call` | Voice calling | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `campaign_recipients` | `CampaignRecipient` | **Campaign recipients (the one REPLACE)** | `db/migrate` (OSS) | 0 | **KEEP (replace the model)** |
| `captain_assistant_responses` | `Captain::AssistantResponse` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_assistants` | `Captain::Assistant` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_custom_tools` | `Captain::CustomTool` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_documents` | `Captain::Document` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_faq_observations` | `Captain::FaqObservation` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_faq_suggestions` | `Captain::FaqSuggestion` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_inboxes` | `CaptainInbox` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_message_reports` | `Captain::MessageReport` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `captain_scenarios` | `Captain::Scenario` | Captain | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `companies` | `Company` | Companies CRM | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `conversation_outcomes` | `ConversationOutcome` | Captain outcome tracking | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `copilot_messages` | `CopilotMessage` | Captain copilot | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `copilot_threads` | `CopilotThread` | Captain copilot | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `custom_roles` | `CustomRole` | Custom roles | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `inbox_capacity_limits` | `InboxCapacityLimit` | Agent capacity | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `sla_events` | `SlaEvent` | SLA | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `sla_policies` | `SlaPolicy` | SLA | `db/migrate` (OSS) | 0 | KEEP (leave in place) |
| `audits` | `Enterprise::AuditLog < Audited::Audit` | Audit log | `db/migrate` (OSS) | 0 | **KEEP (replace the model)** |

The phase-0 audit reported 14 tables. 25 is the measured figure; section 9 records the correction.

### 5.3 What happens to existing rows

| Situation | Consequence |
|:--|:--|
| Rows already in these tables | Become unreferenced data. No model loads them, no query reads them, no code writes them. They are not corrupted and nothing fails. |
| `dependent: :destroy_async` cascades declared in `Enterprise::Concerns::Account`, `::Conversation`, `::Inbox`, `::Message`, `::Contact` | Stop running. Deleting an account no longer enqueues destroys for its `sla_policies`, `custom_roles`, `agent_capacity_policies`, `captain_*`, `copilot_threads`, `companies`, `calls` or `saml_settings`. Those rows survive the account. |
| `campaign_recipients` rows | Keep cascading correctly via the database FKs (5.1.3) regardless of the model. |
| `audits` rows | Keep accumulating — `Whatsapp::MessageTemplate` is still audited through the OSS gem *(measured)*. Existing `Enterprise::AuditLog` rows are readable by `Audited::Audit` because it is the same table. |

The orphan cascades are the only genuine data consequence, and the fix is deliberately **not** in
scope here: whoever removes the overlay should decide separately whether to (a) leave the rows,
(b) add the `dependent:` declarations to a `custom/` overlay on `Account`, or (c) write a one-off
cleanup. Option (a) is safe; this document recommends it for the removal commit and a follow-up
decision afterwards.

Row counts were deliberately **not** used as evidence. The database in this container was loaded
from `db/schema.rb` for the simulation and every one of these tables reads 0 rows, which says
nothing about production. The structural conclusions above are schema-level and hold everywhere.
Before the removal commit, the operator should run the counts on production — a read-only
`SELECT count(*)` per table — to learn whether any of this data is worth migrating. The only table
where a non-zero count would change a decision is `campaign_recipients`.

---

## 6. Phase 5 — frontend impact

### 6.1 The one switch that does most of the work (measured)

`app/controllers/dashboard_controller.rb:88` ships `IS_ENTERPRISE: ChatwootApp.enterprise?` to the
browser. With `enterprise/` gone that becomes `false`, and
`app/javascript/dashboard/composables/usePolicy.js:39-51` then fails
`checkInstallationType` for every surface declaring `INSTALLATION_TYPES.ENTERPRISE`.

The sidebar does not carry its own gates: `components-next/sidebar/provider.js:117-146` resolves each
entry's `to` against the Vue router and reads `meta.featureFlag`, `meta.permissions` and
`meta.installationTypes` **from the route definition**, then calls the same `shouldShow`. So gating a
route gates its menu entry automatically.

One nuance worth recording, because it is load-bearing: Lynomia is a custom-branded instance, and
`usePolicy.js:75-78` short-circuits custom-branded instances to *"just use the feature flag as a
reference"*. Premium paywalls and upsells are therefore already switched off for Lynomia, and
`shouldShow` already decides purely on the account feature flag. Removing enterprise does not change
that branch; it only adds the `installationTypes` refusal.

### 6.2 Surfaces checked, one by one

| Surface | Gate | Verdict |
|:--|:--|:--|
| **Cloud billing** | `api/enterprise/account.js` + `store/modules/accounts.js` + `ShopifyBilling.vue` — no gate | **REMOVE** (section 3.3). Lynomia's own billing pages are separate and unaffected. |
| **SAML SSO** | `dashboard_controller.rb:105` already withholds the `saml` auth method unless `ChatwootHub.pricing_plan != 'community'` | no change |
| **Audit Logs** | `settings/auditlogs/audit.routes.js:25-30` — `featureFlag: AUDIT_LOGS`, `installationTypes: [CLOUD, ENTERPRISE]`, `permissions: ['administrator']` | hides itself; the sidebar entry inherits the gate through `provider.js` |
| **Captain** | `settings/captain/captain.routes.js:12-13`, `routes/dashboard/captain/captain.routes.js:31,42,48,165` — feature flag + `installationTypes` | hides itself |
| **SLA** | `settings/sla/sla.routes.js:9-11` — `featureFlag: SLA`, `installationTypes: [CLOUD, ENTERPRISE]` | hides itself |
| **Custom roles** | `settings/customRoles/customRole.routes.js:25` — `installationTypes` includes ENTERPRISE | hides itself |
| **Agent capacity / assignment policies** | `components-next/sidebar/Sidebar.vue:765-783` — `hasAdvancedAssignment` | hidden while the `advanced_assignment` account flag is off. See the note below on `assignment_v2`. |
| **Voice / calling** | `routes/dashboard/calls/routes.js:18` — `installationTypes` includes ENTERPRISE; the per-inbox call settings live behind `CollaboratorsPage.vue:410` `v-if="enableAutoAssignment && (isEnterprise \|\| hasAssignmentV2)"` | hides itself |
| **Advanced (OpenSearch) search** | `modules/search/components/SearchHeader.vue:46` — `installationTypes` includes ENTERPRISE; server side `ChatwootApp.advanced_search_allowed?` is `enterprise? && OPENSEARCH_URL` | hides itself |
| **Companies CRM** | `routes/dashboard/companies/routes.js:10` — `installationTypes: [CLOUD, ENTERPRISE]` | hides itself |
| **CSAT review notes** | `settings/reports/components/CsatExpandedRow.vue:29` — `isCloudFeatureEnabled('csat_review_notes')` | hidden while the premium flag is off |
| **Required conversation attributes** | `settings/conversationWorkflow/index.vue:44` passes `:is-enabled`, and the component paywalls itself | hidden |
| **`add_sla` automation action** | `settings/automation/AutomationRuleForm.vue:224-227` filters `add_sla` out unless `isCloudFeatureEnabled('sla')` | already filtered |
| **WhatsApp embedded-signup access request** | `settings/inbox/channels/Whatsapp.vue:88-92` requires `isOnChatwootCloud` | never shown on this installation |
| **`max_assignment_limit` inbox field** | `CollaboratorsPage.vue:639` — inside `<template v-else-if="isEnterprise">`, the pre-`assignment_v2` branch | never renders once `IS_ENTERPRISE` is false, so the param the server stops permitting is also never offered |
| **WhatsApp campaign analytics** | `campaigns.routes.js:64-72` — `featureFlag: WHATSAPP_CAMPAIGNS` and **no `installationTypes`** | ⚠️ **stays reachable and its API 404s.** The only frontend REPLACE. |

**One nuance on assignment, checked because it looked like a gap.** `assignment_v2` is
`enabled: true` and **not** premium (`config/features.yml`), unlike `advanced_assignment`
(`enabled: false, premium: true`). So `CollaboratorsPage.vue:410`
(`v-if="enableAutoAssignment && (isEnterprise || hasAssignmentV2)"`) keeps rendering after removal,
via `hasAssignmentV2` rather than `isEnterprise`. Inside that branch, with `advanced_assignment`
off: the policy card at `:417` is hidden (`showAdvancedAssignmentUI` is
`hasAdvancedAssignment && hasAssignmentV2`, `:91-93`), the `max_assignment_limit` input at `:639` is
in the `v-else-if="isEnterprise"` branch and is hidden, and what remains is the
"Upgrade to Business" prompt at `:622` — which renders today too, for the same reason. Crucially
`setDefaults` (`:344-353`) only calls `fetchAssignmentPolicy` / `fetchAvailablePolicies`
`if (showAdvancedAssignmentUI.value)`, so the page issues **no** request to the enterprise-only
`/assignment_policies` endpoints. And both fetchers already swallow a failure
(`:168-171`, `:181-182`). Nothing to do here.

### 6.3 Frontend work required

| # | Action | Files |
|--:|:--|:--|
| 1 | Resolve WhatsApp campaign analytics — port the backend (section 4.4) or delete the page, its route entry and the two `campaigns.js` methods | `campaigns.routes.js:64-72`, `pages/WhatsAppCampaignAnalyticsPage.vue`, `api/campaigns.js:10,19` |
| 2 | Remove the cloud billing frontend | `api/enterprise/account.js`, `store/modules/accounts.js:6,124,147,156`, `settings/billing/ShopifyBilling.vue` |
| 3 | Optional hygiene: delete the now-dead enterprise route modules and their sidebar entries rather than relying on `installationTypes` to hide them | `settings/{auditlogs,sla,captain,customRoles}/*.routes.js`, `routes/dashboard/{calls,companies,captain}/routes.js` |

Item 3 is genuinely optional: measured behaviour is that these surfaces are invisible and their
endpoints answer 404. Deleting them shrinks the bundle and removes dead code; keeping them costs
nothing at runtime.

---

## 7. Phase 6 — removal simulation

### 7.1 What was run

A scratch git worktree at the current branch head with `enterprise/` renamed aside (section 1.3).
The primary checkout was never modified. Each probe below was also run in the primary checkout, so
every number is a delta rather than an absolute.

### 7.2 Rails boots and eager-loads (measured)

```
RAILS_ENV=production  bundle exec rails runner 'Rails.application.eager_load!; …'

EAGER_LOAD_OK
enterprise?=false custom?=true extensions=["enterprise", "custom"]
routes=896
BOOT_OK
```

Production eager loading is the strongest available boot test: it loads every class in
`app/`, `lib/` and `custom/` and resolves every constant referenced at class-definition time.
It completed with no error and no warning beyond two pre-existing ones (a RubyLLM deprecation and
the GeoIP setup notice), both present in the baseline too.

`extensions` still reads `["enterprise", "custom"]` because `lib/chatwoot_app.rb:40-47` returns that
pair whenever `custom?` is true, without consulting `enterprise?`. Every injection site therefore
still *asks* for `Enterprise::X` and gets `false` from `const_get_maybe_false` — which is exactly
the designed no-op, and is why boot succeeds. It is cosmetic rather than harmful, but the removal
commit should drop `'enterprise'` from that list so the code says what it does.

### 7.3 Sidekiq boots and executes jobs (measured)

```
RAILS_ENV=production  bundle exec sidekiq -C config/sidekiq.yml      (ran 90s, then SIGTERM)

INFO  Booted Rails 7.2.3.1 application in production environment
INFO  Cron Jobs - added job with name internal_check_new_versions_job
INFO  Cron Jobs - added job with name trigger_scheduled_items_job
INFO  Cron Jobs - added job with name trigger_hourly_scheduled_items_job
INFO  Cron Jobs - added job with name trigger_imap_email_inboxes_job
INFO  Cron Jobs - added job with name remove_stale_contact_inboxes_job.rb
INFO  Cron Jobs - added job with name remove_stale_redis_keys_job.rb
INFO  Cron Jobs - added job with name delete_accounts_job
INFO  Cron Jobs - added job with name periodic_assignment_job
INFO  Cron Jobs - added job with name remove_old_notification_job
INFO  Cron Jobs - added job with name remove_orphan_conversations_job
INFO  Cron Jobs - added job with name commerce_action_sweep_job          <- Lynomia
INFO  Cron Jobs - added job with name lynomia_queue_health_job           <- Lynomia
```

It did more than boot: inside the 90 seconds it **ran** `Commerce::ActionSweepJob`,
`Lynomia::QueueHealthJob`, `TriggerScheduledItemsJob`,
`AutoAssignment::PeriodicAssignmentJob` and `Inboxes::FetchImapEmailInboxesJob` to completion, and
shut down cleanly on SIGTERM. No `NameError`, no `uninitialized constant`, one WARN line (the
RubyLLM deprecation, also in the baseline).

Both Lynomia cron jobs registered and the Commerce sweep executed, which is the single best
one-line evidence that the Lynomia scheduled surface survives.

### 7.4 Routes compile and resolve (measured)

896 route entries compile; 736 resolve to a live controller **and** action; 155 do not, of which 52
were already unresolvable with enterprise present (pre-existing OSS artefacts) and 119 are caused by
removal. Section 4 carries the breakdown. Critically, every unresolvable route answers **404**, not
500 (section 3.2).

### 7.5 Dashboard, login and Super Admin boot (measured)

A Puma server was booted in the worktree in production mode and the three shells were requested:

| Request | Status |
|:--|--:|
| `GET /` | 200 |
| `GET /app/login` | 200 |
| `GET /super_admin/sign_in` | 200 |

`app/dashboards/*.rb` loaded all 8 Administrate dashboards; `app/dashboards/account_dashboard.rb:11-26`
already wraps its enterprise attribute types in `if ChatwootApp.enterprise? … else {} end`, which is
why Super Admin renders.

### 7.6 Audit, policy and feature-flag resolution (measured)

```
Enterprise namespace defined          = no
Enterprise::AuditLog                  = nil   (safe_constantize)
Enterprise::Billing::HandleStripeEventService = nil
Enterprise::MessageTemplates::HookExecutionService = nil
Audited.audit_class                   = Audited::Audit
Audited.audit_class.table_name        = audits
features.yml entries loaded           = 72
Super Admin dashboards loaded         = 8
custom/app/services/flows/audit.rb         guard present
custom/app/services/commerce/audit_trail.rb guard present
```

### 7.7 Lynomia feature coverage: the specs

The full non-enterprise RSpec suite was run in the worktree with the `Enterprise::` namespace
absent (`--exclude-pattern "enterprise/**/*_spec.rb"`, since those specs test the removed code by
definition). This is the broadest per-feature evidence available, covering WhatsApp send/receive,
Contacts, Inbox and conversations, Commerce, audiences, automations, Flow Builder, campaigns,
Template Manager and the documentation engine through their own request, service, model and job
specs.

```
8585 examples, 46 failures, 73 pending          Finished in 37 minutes 22 seconds
```

Baseline for comparison: **11,269 examples, 1 failure, 70 pending in 46m40s** with enterprise
present (the one baseline failure is the OpenSearch environment gate, which cannot pass in this
container). The 2,684-example difference is `spec/enterprise/`, excluded by the pattern.

46 failures is not the delta. Every failing file was **re-run in the primary checkout with
enterprise present**, the same way every other probe in this document was baselined:

```
bundle exec rspec <the 9 failing files>        # primary checkout, enterprise PRESENT
98 examples, 21 failures
```

| File | Failures without `enterprise/` | Failures **with** `enterprise/` | Caused by removal |
|:--|--:|--:|:--|
| `spec/controllers/api/v1/accounts_controller_spec.rb` | 5 | 5 | no |
| `spec/controllers/api/v2/accounts_controller_spec.rb` | 5 | 5 | no |
| `spec/controllers/slack_uploads_controller_spec.rb` | 4 | 4 | no |
| `spec/controllers/devise/omniauth_callbacks_controller_spec.rb` | 3 | 3 | no |
| `spec/lib/vapid_service_spec.rb` | 2 | 2 | no |
| `spec/lib/global_config_service_spec.rb` | 1 | 1 | no |
| `spec/lib/config_loader_spec.rb` | 1 | 1 | no |
| `spec/models/campaign_audience_spec.rb` | 1 | **0** | **yes** |
| `spec/requests/custom/tenant_help_center_removal_spec.rb` | 24 | **0** | **yes** |
| | **46** | **21** | **25** |

**21 failures are pre-existing** — identical file, identical count, identical message with the
overlay in place. They are this container's test-database state, not the overlay: `ConfigLoader`
asserts `InstallationConfig.count == 0` and gets 4, `GlobalConfigService` finds a leftover
`ENABLE_ACCOUNT_SIGNUP = "false"` row (which is also why three `POST /api/v1/accounts` examples see
404 instead of success), `SlackUploadsController` raises
`ActionController::Redirecting::UnsafeRedirectError`, and the two `VapidService` examples expect an
`InstallationConfig.find_by` that the leftover rows short-circuit. They are reported here rather
than filtered out, because filtering them silently is how a 46 becomes a 25 without anyone being
able to check.

**25 failures are caused by removal, and they are two things:**

**1. `spec/models/campaign_audience_spec.rb` — 1 failure. This is the `D`, found independently.**

```
Campaign sending records and sends a WhatsApp campaign once to each contact of its labels and audiences
  Failure/Error: expect(campaign.campaign_recipients.pluck(:contact_id, :status))
                   .to contain_exactly([vip.id, 'sent'], [tagged.id, 'sent'])
  NoMethodError: undefined method 'campaign_recipients' for an instance of Campaign
```

This spec is Lynomia's own, added by commit `7f9f053a`, and it asserts exactly the capability
section 4.4 identified by reading: the campaign still *sends* (the example's own send assertions
pass up to this line) but writes no recipient rows. A Lynomia-authored test detecting the one
`D` without being told to look for it is the best corroboration available that the classification
is right and that it is the only one.

**2. `spec/requests/custom/tenant_help_center_removal_spec.rb` — 24 failures, all one line, in the
fixture rather than the product.**

```
Failure/Error: role = CustomRole.create!(account: account, name: 'everything',
                                         permissions: CustomRole::PERMISSIONS)
NameError: uninitialized constant CustomRole
```

All 24 are that single `before` block at `:20-23`, which every example inherits. The spec guards
Lynomia's removal of tenant Help Center authoring against three principals — administrator, agent,
and a custom role holding every permission *including* `knowledge_base_manage` — and its own comment
says why the third exists: *"which `Enterprise::{Portal,Article}Policy` would otherwise accept."*

So the third principal is there **because** of the enterprise policies. Remove the overlay and
`Enterprise::PortalPolicy` and `Enterprise::ArticlePolicy` go with it, so the attack the arm defends
against becomes unconstructible at the same moment the arm stops compiling. The behaviour under test
— the OSS/Lynomia policy refusal that returns 401 to administrators and agents — is untouched; it is
the fixture that reaches for an enterprise model. The fix during removal is to drop the `power_user`
arm and its `before` block, or to keep the arm against a Lynomia-owned permission source if one is
built (section 8). Either way it is a few lines in one spec file, and it is **spec work, not product
work**.

**Per-Lynomia-feature result.** Zero failures across WhatsApp send and receive, Contacts (including
bulk actions and import), Inbox and conversations, Commerce (stores, orders, carts, action runs,
Salla/Zid/Shopify token managers), audiences, automations, Flow Builder, Template Manager and the
documentation engine. Campaigns had exactly one failure, and it is the `D`.

### 7.8 Remaining runtime constant resolution

Searched for, and found: **nothing that fails**. The three categories that could have failed were
each closed by measurement rather than reasoning:

| Category | Probe | Result |
|:--|:--|:--|
| A constant referenced at class-definition time | production eager load | passes (7.2) |
| A method only `enterprise/` defines, called from OSS or `custom/` | 222 enterprise-only methods × 217 names swept across `app/`, `lib/`, `custom/`, `config/` | 0 genuine callers (2.1) |
| A route whose controller or action only `enterprise/` provides | full route resolution + live HTTP | 162 entries, all 404, no 500 (4, 3.2) |

The one residual item is not a failure but a silent change: `config/initializers/audited.rb` names a
constant that no longer exists. The gem's `safe_constantize` turns that into `Audited::Audit` rather
than an exception *(measured, 7.6)*. It should still be fixed as part of section 3.1, because
"works by virtue of a gem's rescue" is not a contract worth depending on.

---

## 8. Lynomia's own coupling to `enterprise/`

The phase-0 audit reported that Lynomia depends on the overlay in **3 files / 5 lines**. That is
true of *references to `Enterprise::` constants*, and it is confirmed again here (section 3.1). But
it is not the whole coupling, and this is the most important thing this phase found that the first
audit did not.

**Lynomia has edited files inside `enterprise/` — 7 commits across 6 files** *(measured:
`git log --author=Claude --name-only -- enterprise/`)*:

| Commit | Date | File | What it did | Consequence of removal |
|:--|:--|:--|:--|:--|
| `68b1d5db` | 2026-10-04 | `enterprise/config/premium_installation_config.yml` | Stopped the daily plan reconcile from reverting the installation's branding to "Chatwoot" | **The defect disappears with the overlay.** `Internal::ReconcilePlanConfigService` — the daily writer — lives in `enterprise/app/services/internal/`, and its only caller is `Enterprise::Internal::CheckNewVersionsJob`. Removal retires that whole failure mode; `ConfigLoader` becomes the sole writer by construction rather than by workaround. |
| `53ad423f` | 2026-10-04 | same | Gave the installation one authoritative product identity | same — the file and its reader go together |
| `75d06597` | 2026-10-05 | same | Fixed the product-name capitalization ("Lynomia Chat") | same |
| `64156a71` | 2026-10-04 | `enterprise/.../whatsapp/providers/whatsapp_cloud_service.rb` | Removed a locally pinned Graph API version in favour of the one global version | Moot: the file is WhatsApp **calling** only, and the OSS providers (which the same commit also fixed) are what Lynomia's messaging actually uses |
| `6d3feb53` | 2026-10-04 | `enterprise/app/models/enterprise/automation_rule.rb` | Removed an SLA automation *condition* that could never match | Moot: a removal inside an enterprise-only feature |
| `7f9f053a` | 2026-10-02 | `enterprise/.../whatsapp/oneoff_campaign_service.rb` | Made one-off campaigns resolve shared audiences | **Partly load-bearing.** The same commit made the identical change to OSS `app/services/whatsapp/oneoff_campaign_service.rb`, so audience resolution survives; what is lost is the `CampaignRecipient` bookkeeping in the enterprise copy (section 4.4) |
| `76ed1990` | 2026-10-01 | `enterprise/app/models/custom_role.rb` | Added the `commerce_order_manage` permission for Lynomia Commerce order actions | **Load-bearing, degrades gracefully.** `custom/app/policies/commerce/action_policy.rb:8,19-20` reads `@account_user.permissions`. OSS `AccountUser#permissions` returns `['administrator']` or `['agent']` (`app/models/account_user.rb:58-60`), so Commerce status changes and e-mail resends become **administrator-only**. Refunds and cancellations were already administrator-only. No crash, no error — a quieter permission model. |

Two of these are worth restating as decisions rather than facts:

* **Branding.** Three of the seven commits exist only to defend Lynomia's product identity against
  an enterprise service. Removing the overlay is the permanent version of that fix. Nothing about
  Lynomia's branding lives in `enterprise/` in a way that would be *lost* — the authoritative values
  are in `config/installation_config.yml`, and the overlay copy existed to stop a reconciler from
  overwriting them.
* **`commerce_order_manage`.** If granting agents order-management rights matters at launch, the
  cheapest replacement is **not** to rebuild custom roles. It is to add a Lynomia-owned permission
  source — e.g. a `Custom::AccountUser#permissions` overlay reading a Lynomia column or an account
  setting — consumed by the existing `Commerce::ActionPolicy`, which already asks only for
  `permissions.include?('commerce_order_manage')`. One overlay module, one storage decision, no new
  roles UI. If it does not matter at launch, administrator-only is a safe default and no work is
  needed.

---

## 9. Corrections to `00-enterprise-dependency-audit.md`

Measurement disagreed with the phase-0 structural audit in four places. Recording them here rather
than quietly restating the numbers:

| # | Phase-0 claim | Measured | Why the difference |
|--:|:--|:--|:--|
| 1 | "154 routes → 38 controllers" | **162 route entries**: 43 gated (vanish) + 119 ungated (404), across 27 enterprise-only controllers + 2 enterprise-added actions on OSS controllers | Phase 0 counted route *declarations* matched against enterprise controller files. The measurement resolves every route through a booted application in both trees and diffs, which catches the two enterprise-added *actions* (`PortalsController#ssl_status`, `ConversationsController#inbox_assistant`) that no filename scan can see, and counts verb-variant entries (`PATCH`/`PUT`) separately. |
| 2 | "14 tables" | **25 tables** (24 `ApplicationRecord` descendants defined under `enterprise/`, plus `audits`) | Phase 0 enumerated the tables named in enterprise migrations and models it had read. The measurement asks every loaded model for `Object.const_source_location` and collects the ones defined under `enterprise/`. |
| 3 | "Three unguarded enterprise routes (`saml_settings`, `audit_logs`, `auth/saml_login`)" | Those three are real, but they are **3 of 119** ungated entries. The other 116 are also unguarded and also 404. | Phase 0 looked for routes whose declaration lacked an `if ChatwootApp.enterprise?` *and* whose controller name it recognised as enterprise. The complete set only emerges from resolving every route. |
| 4 | "Lynomia depends on `enterprise/` in 3 files / 5 lines" | True for `Enterprise::` **constant references** (re-confirmed). Incomplete as a statement of coupling: Lynomia has also **edited 6 files inside `enterprise/` across 7 commits** (section 8). | Phase 0 searched for references *to* the namespace. It did not ask who had written *into* the directory. |

Phase 0's central conclusions all held: the overlay is removable by design, `Audited.audit_class`
degrades gracefully through `safe_constantize`, the Enterprise WhatsApp overlay is calling and
Captain rather than core messaging, and `app/dashboards/account_dashboard.rb` is correctly guarded.

---

## 10. Verdict and the ordered work list

### 10.1 Verdict

# READY AFTER SMALL REPLACEMENTS

The overlay is removable: the application boots, eager-loads, serves, schedules and runs jobs with
the `Enterprise::` namespace absent, every affected route degrades to 404 rather than 500, the
schema does not change, and no OSS or Lynomia code calls a method that only `enterprise/` provides.
The 8,585-example non-enterprise suite confirms it: of 46 failures, 21 fail identically *with* the
overlay in place, and the 25 that removal causes are one product capability (1 failure) and one
spec fixture (24 failures on a single line) — section 7.7.
Of 136 overlay behaviours, 117 are either inert (38) or enterprise features Lynomia does not ship
(79). What stands between here and removal is **one capability to relocate and four small edits**,
all of which move existing code onto existing tables.

This is not a recommendation to remove the overlay now. It is a statement that the removal is
bounded, measurable and reversible, and that the bound is known.

### 10.2 What must be done before removal

| # | Item | Size | Files | Why |
|--:|:--|:--|:--|:--|
| 1 | **Relocate WhatsApp campaign recipient tracking to `custom/`** — model, two associations, the recipient-creating send path, the status updater and its job, `last_provider_error`, the analytics controller and its two routes | 6 backend files + 2 route lines; no schema change | section 4.4 | The only Lynomia-shipped capability that stops working. Its frontend route is gated on `WHATSAPP_CAMPAIGNS`, which **is** enabled, so it would be user-visible breakage. |
| 2 | **Own the audit class** — a `Custom::AuditLog < Audited::Audit` on the existing `audits` table, the initializer pointed at it, and the three guarded Lynomia call sites unguarded | ~8 lines across 4 files; no migration | section 3.1 | Removes the last `Enterprise::` constant reference in Lynomia code and restores audience auditing that the `defined?` guard silently disables. |
| 3 | **Remove the cloud billing frontend** | 3 files | section 3.3 | It is the only frontend code that calls `/enterprise/api/v1/…`; those endpoints vanish. |
| 4 | **Delete the dead route declarations** — all 162 entries in section 4.3, both the gated blocks and the 119 ungated ones | `config/routes.rb` | section 4.2 | They answer 404 either way; deleting them makes `rails routes` honest and removes 29 phantom controller references. |
| 5 | **Drop `'enterprise'` from `ChatwootApp.extensions`** | `lib/chatwoot_app.rb:40-47` | section 7.2 | Today the list is returned unconditionally whenever `custom?` is true, so every injection site asks for a namespace that cannot exist. Harmless, but the code should say what it does. |

| 6 | **Adjust two specs** — drop the `CustomRole` arm of `spec/requests/custom/tenant_help_center_removal_spec.rb:20-23`, and point `spec/models/campaign_audience_spec.rb` at whatever item 1 decides | a few lines in 2 files | section 7.7 | They are the only two specs that removal breaks, and both break in the fixture, not the assertion. |

### 10.3 Decisions to take, not work to do

| Decision | Default if nothing is done | Where it is argued |
|:--|:--|:--|
| Should agents be able to manage store orders? | No — `commerce_order_manage` can no longer be granted, so order status changes and e-mail resends become administrator-only. Refunds and cancellations were already administrator-only. | section 8 |
| Is the audit trail a compliance requirement? | Lynomia's Template Manager stays audited; the 11 Chatwoot-side `audited` declarations (Account, AccountUser, AgentBot, AutomationRule, Conversation, Inbox, InboxMember, Macro, Team, TeamMember, Webhook) and the sign-in/sign-out and deletion writes stop. Each is a one-line declaration that can be ported to `custom/` at any time. | section 3.1 |
| What happens to rows in the 25 orphaned tables? | They stay, unreferenced and unread. Account deletion stops cascading to them. | section 5.3 |
| Keep or delete the now-invisible enterprise frontend modules? | Keep — they are hidden by `installationTypes` and cost nothing at runtime. | section 6.3 |

### 10.4 Before the removal commit, on production

Three read-only checks the operator should run on the real database, because this container's
schema-loaded database cannot answer them:

1. `SELECT count(*) FROM campaign_recipients;` — the only count that changes a decision. A non-zero
   count means item 1 is a migration of live data, not just code.
2. `SELECT count(*) FROM audits;` — tells you how much history the audit class rename inherits
   (it inherits all of it; same table).
3. A count across the other 23 tables — tells you whether any orphaned data is worth keeping. Most
   are expected to be empty on a self-hosted community installation that has never had SLA,
   Captain, custom roles, companies or voice.

And one flag check: `advanced_assignment` and `assignment_v2` on every account. With the overlay
gone, nothing disables premium feature flags any more (`Internal::ReconcilePlanConfigService` is
itself enterprise), so a flag that is set today stays set, and the Agent Assignment sidebar entry
is gated on it. If either is on, turn it off before removal.

### 10.5 What was explicitly not done

`enterprise/` was not removed, moved, disabled or edited. No feature flag, licensing file or route
was changed. No table was dropped. No test was deleted or rewritten. The simulation ran entirely in
a throwaway git worktree under the session scratchpad; the primary checkout carries only this
document.
