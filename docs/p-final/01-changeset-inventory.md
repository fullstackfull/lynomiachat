# P-FINAL.1 — Complete changeset inventory, production → P-FINAL

The audited delta is `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4..8bb3b49e`: **50 commits, 440 files,
+43,125/−799** (315 added, 114 modified, 11 deleted).

Every one of the 440 files is classified below. The classification is mechanical, not editorial: for an added
file, the phase is that of the commit that first added it (`git log --diff-filter=A -1`); for a modified or
deleted file, the commit that last touched it in this range. The commit→phase map is the 50-commit table in
`00-baseline.md` §9. **Zero files were left unclassified.**

`SC` is the P10 security closure that ran at the start of P11 — it is separated from P11 because its changes
are security fixes to pre-existing channel and webhook code, not commercialization.

---

## 1. Distribution

| area | P8 | P9 | P10 | SC | P11 | total |
|---|---|---|---|---|---|---|
| model | · | 8 | 5 | 3 | 10 | 26 |
| service | 30 | 22 | 4 | 6 | 11 | 73 |
| controller | 4 | 5 | 4 | 15 | 7 | 35 |
| job | · | 4 | · | 1 | · | 5 |
| policy | · | 1 | 1 | · | · | 2 |
| helper | · | · | · | 1 | · | 1 |
| lib | 2 | 1 | · | 2 | · | 5 |
| migration / schema | · | 2 | 2 | 3 | 2 | 9 |
| config (incl. routes, locales, features) | 1 | 4 | 1 | 2 | 2 | 10 |
| Super Admin (fields/dashboards) | · | · | · | · | 2 | 2 |
| view / jbuilder | · | 17 | · | · | 7 | 24 |
| frontend (JS/Vue) | 31 | 48 | 14 | 7 | 5 | 105 |
| spec | 22 | 22 | 18 | 16 | 17 | 95 |
| docs | 13 | 10 | 11 | 1 | 10 | 45 |
| other | · | · | 3 | · | · | 3 |
| **total** | **103** | **144** | **63** | **57** | **73** | **440** |

Three readings worth taking from that table:

- **P9 is the largest phase** (144 files), and the only one that added both a workspace UI and background
  jobs. It is therefore the phase with the most new runtime surface, and gets proportionate attention in the
  security, data-integrity and job audits.
- **P8 is service-heavy and schema-free** (30 services, 0 migrations), consistent with its design as a read
  projection — its risk is query shape and tenancy, not data.
- **SC is controller-heavy** (15 of 57 files), which is what a webhook-authentication closure looks like.

## 2. Cross-cutting facts that bound the audit

| Question | Answer, measured |
|---|---|
| New dependencies | **none** — `Gemfile`, `Gemfile.lock`, `package.json`, `pnpm-lock.yaml` are byte-identical to production |
| New public/unauthenticated endpoints | **none**; three were *removed* (`/webhooks/twitter` ×2, `/twitter/callback`, plus the authenticated `twitter/authorization`) |
| New feature flags | 2, both `enabled: false` (`lynomia_support_tickets`, `lynomia_unified_identity`) |
| New tables | 6 | 
| Migrations | 8, all append-only, all under `custom/db/migrate` |
| Deleted files | 11, of which 8 are the X/Twitter connect flow and its specs |
| New gems/npm packages with install scripts | n/a — nothing added |
| Changes to `db/migrate` (upstream migrations) | **none** |

## 3. Provider integrations touched

| Provider | Phase | What changed |
|---|---|---|
| Bandwidth (`Channel::Sms`) | SC | HTTP Basic authentication per channel; channel resolved from the path; replay dedup on provider message id |
| Twilio (SMS/WhatsApp) | SC | `X-Twilio-Signature` verification on inbound and on delivery status, using the channel's own auth token |
| Meta WhatsApp Cloud | SC | inbound routed by `phone_number_id`; payload can no longer waive its own signature check |
| Meta Facebook / Instagram | SC | app-secret verification can no longer be skipped when unconfigured (fail closed) |
| Slack integration webhook | SC | signature verification fail-closed; private-file fetch restricted to Slack-owned hosts |
| TikTok | SC | OAuth state bound in time (TTL) and to a person; secret-in-query-string method deleted |
| Stripe | P11/SC | blank webhook secret rejected; events idempotent on provider event id and order-safe; all API calls behind one layer |
| X / Twitter | SC | inbound webhook routes, controller and the whole OAuth connect flow removed (channel retired) |
| Email / IMAP | P9/P10 | `Custom::Channel::Email`, `Custom::Inboxes::FetchImapEmailsJob` |
| Commerce (Shopify / Salla / Zid) | P9/P10 | health signals and connection state only; no protocol change |

## 4. Authorization and policy changes

| File | Phase | Effect |
|---|---|---|
| `custom/app/policies/…` (2 files) | P9, P10 | ticket access and contact-merge authorization |
| `custom/app/models/custom_role.rb` | P9 | custom-role permission surface used by the tickets workspace |
| `custom/app/controllers/platform/api/v1/billing/*` | P11 | permissible-account scoping; credential keys excluded from the Platform API |
| `custom/app/controllers/super_admin/*` | P9, P11 | Operations Center and billing override actions, Super-Admin-only |

Full per-surface guard table with file:line evidence is in `05-security-audit.md`.

## 5. Complete file-by-file inventory

Status is `A`dded, `M`odified, `D`eleted. Phase is as defined above.

#### model (26)

| status | phase | path |
|---|---|---|
| M | P10 | `app/models/channel/email.rb` |
| M | P10 | `app/views/api/v1/models/_inbox.json.jbuilder` |
| A | P10 | `custom/app/models/contact_identity.rb` |
| A | P10 | `custom/app/models/custom/channel/email.rb` |
| M | P10 | `custom/app/models/custom/concerns/contact.rb` |
| M | P11 | `custom/app/models/billing/agent_limit.rb` |
| M | P11 | `custom/app/models/billing/api_serializer.rb` |
| M | P11 | `custom/app/models/billing/inbox_limit.rb` |
| D | P11 | `custom/app/models/billing/plan_limits.rb` |
| A | P11 | `custom/app/models/billing/resource_limit.rb` |
| A | P11 | `custom/app/models/billing_entitlement_override.rb` |
| M | P11 | `custom/app/models/billing_plan.rb` |
| M | P11 | `custom/app/models/billing_subscription.rb` |
| M | P11 | `custom/app/models/custom/account.rb` |
| M | P11 | `custom/app/models/custom/audit_log.rb` |
| M | P9 | `app/models/concerns/reauthorizable.rb` |
| A | P9 | `custom/app/models/custom/concerns/conversation.rb` |
| A | P9 | `custom/app/models/custom/reauthorizable.rb` |
| M | P9 | `custom/app/models/custom_role.rb` |
| A | P9 | `custom/app/models/operations/signal.rb` |
| A | P9 | `custom/app/models/support/sla_policy.rb` |
| A | P9 | `custom/app/models/support/ticket.rb` |
| A | P9 | `custom/app/models/support/ticket_event.rb` |
| M | SC | `app/models/channel/sms.rb` |
| A | SC | `custom/app/models/billing_webhook_event.rb` |
| A | SC | `custom/app/models/custom/channel/sms.rb` |

#### service (73)

| status | phase | path |
|---|---|---|
| A | P10 | `custom/app/services/channels/capability.rb` |
| A | P10 | `custom/app/services/channels/connection_state.rb` |
| A | P10 | `custom/app/services/contacts/identity_linker.rb` |
| A | P10 | `custom/app/services/contacts/merge_relocation.rb` |
| A | P11 | `custom/app/services/billing/entitlements.rb` |
| M | P11 | `custom/app/services/billing/feature_sync.rb` |
| A | P11 | `custom/app/services/billing/operations_signal.rb` |
| A | P11 | `custom/app/services/billing/override_grant.rb` |
| A | P11 | `custom/app/services/billing/plan_audit.rb` |
| M | P11 | `custom/app/services/billing/plan_change.rb` |
| M | P11 | `custom/app/services/billing/plan_sync.rb` |
| A | P11 | `custom/app/services/billing/portal.rb` |
| M | P11 | `custom/app/services/billing/settings.rb` |
| M | P11 | `custom/app/services/billing/trial_starter.rb` |
| M | P11 | `custom/app/services/commerce/store_connection.rb` |
| A | P8 | `custom/app/services/analytics/automations/metrics.rb` |
| A | P8 | `custom/app/services/analytics/automations/overview.rb` |
| A | P8 | `custom/app/services/analytics/breakdown.rb` |
| A | P8 | `custom/app/services/analytics/campaigns/metrics.rb` |
| A | P8 | `custom/app/services/analytics/campaigns/overview.rb` |
| A | P8 | `custom/app/services/analytics/commerce/metrics.rb` |
| A | P8 | `custom/app/services/analytics/commerce/overview.rb` |
| A | P8 | `custom/app/services/analytics/conversations/metrics.rb` |
| A | P8 | `custom/app/services/analytics/conversations/overview.rb` |
| A | P8 | `custom/app/services/analytics/date_range.rb` |
| A | P8 | `custom/app/services/analytics/filter_set.rb` |
| A | P8 | `custom/app/services/analytics/flows/metrics.rb` |
| A | P8 | `custom/app/services/analytics/flows/overview.rb` |
| A | P8 | `custom/app/services/analytics/metric_family.rb` |
| A | P8 | `custom/app/services/analytics/result.rb` |
| A | P8 | `custom/app/services/analytics/rollup_coverage.rb` |
| A | P8 | `custom/app/services/analytics/whatsapp/metrics.rb` |
| A | P8 | `custom/app/services/analytics/whatsapp/overview.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/automations_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/base_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/campaigns_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/commerce_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/conversation_events_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/csat_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/cursor.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/entry.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/flows_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/messages_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline/reporting_events_adapter.rb` |
| A | P8 | `custom/app/services/contacts/activity_timeline_query.rb` |
| A | P9 | `custom/app/services/analytics/tickets/metrics.rb` |
| A | P9 | `custom/app/services/analytics/tickets/overview.rb` |
| A | P9 | `custom/app/services/contacts/activity_timeline/tickets_adapter.rb` |
| A | P9 | `custom/app/services/contacts/activity_timeline/visibility.rb` |
| M | P9 | `custom/app/services/custom/webhooks/trigger.rb` |
| A | P9 | `custom/app/services/operations/account_health.rb` |
| A | P9 | `custom/app/services/operations/case_bridge.rb` |
| A | P9 | `custom/app/services/operations/computed_signals.rb` |
| A | P9 | `custom/app/services/operations/health.rb` |
| A | P9 | `custom/app/services/operations/overview.rb` |
| A | P9 | `custom/app/services/operations/probes.rb` |
| A | P9 | `custom/app/services/operations/signal_recorder.rb` |
| A | P9 | `custom/app/services/support/tickets/counts.rb` |
| A | P9 | `custom/app/services/support/tickets/create.rb` |
| A | P9 | `custom/app/services/support/tickets/event_recorder.rb` |
| A | P9 | `custom/app/services/support/tickets/first_response_detector.rb` |
| A | P9 | `custom/app/services/support/tickets/query.rb` |
| A | P9 | `custom/app/services/support/tickets/reference_allocator.rb` |
| A | P9 | `custom/app/services/support/tickets/sla_clock.rb` |
| A | P9 | `custom/app/services/support/tickets/sla_sweeper.rb` |
| A | P9 | `custom/app/services/support/tickets/status_transition.rb` |
| A | P9 | `custom/app/services/support/tickets/update.rb` |
| M | SC | `app/services/sms/incoming_message_service.rb` |
| M | SC | `app/services/tiktok/auth_client.rb` |
| D | SC | `app/services/twitter/webhook_subscribe_service.rb` |
| M | SC | `app/services/whatsapp/webhook_channel_finder_service.rb` |
| M | SC | `custom/app/services/billing/subscription_sync.rb` |
| M | SC | `custom/app/services/billing/webhook_handler.rb` |

#### controller (35)

| status | phase | path |
|---|---|---|
| M | P10 | `app/controllers/api/v1/accounts/actions/contact_merges_controller.rb` |
| M | P10 | `app/controllers/api/v1/accounts/inboxes_controller.rb` |
| A | P10 | `custom/app/controllers/api/v1/accounts/contacts/identities_controller.rb` |
| A | P10 | `custom/app/controllers/custom/api/v1/accounts/actions/contact_merges_controller.rb` |
| M | P11 | `custom/app/controllers/api/v1/accounts/billing_controller.rb` |
| M | P11 | `custom/app/controllers/billing/access_guard.rb` |
| M | P11 | `custom/app/controllers/platform/api/v1/billing/plans_controller.rb` |
| M | P11 | `custom/app/controllers/platform/api/v1/billing/settings_controller.rb` |
| M | P11 | `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb` |
| M | P11 | `custom/app/controllers/super_admin/billing_plans_controller.rb` |
| M | P11 | `custom/app/controllers/super_admin/billing_subscriptions_controller.rb` |
| A | P8 | `custom/app/controllers/analytics/request_scoped.rb` |
| A | P8 | `custom/app/controllers/api/v1/accounts/analytics_controller.rb` |
| M | P8 | `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` |
| A | P8 | `custom/app/controllers/api/v1/accounts/contacts/activity_controller.rb` |
| A | P9 | `custom/app/controllers/api/v1/accounts/support/base_controller.rb` |
| A | P9 | `custom/app/controllers/api/v1/accounts/support/events_controller.rb` |
| A | P9 | `custom/app/controllers/api/v1/accounts/support/sla_policies_controller.rb` |
| A | P9 | `custom/app/controllers/api/v1/accounts/support/tickets_controller.rb` |
| A | P9 | `custom/app/controllers/super_admin/operations_controller.rb` |
| M | SC | `app/controllers/api/v1/accounts/tiktok/authorizations_controller.rb` |
| D | SC | `app/controllers/api/v1/accounts/twitter/authorizations_controller.rb` |
| M | SC | `app/controllers/api/v1/integrations/webhooks_controller.rb` |
| D | SC | `app/controllers/api/v1/webhooks_controller.rb` |
| A | SC | `app/controllers/concerns/twilio_request_verification.rb` |
| D | SC | `app/controllers/concerns/twitter_concern.rb` |
| M | SC | `app/controllers/tiktok/callbacks_controller.rb` |
| M | SC | `app/controllers/twilio/callback_controller.rb` |
| M | SC | `app/controllers/twilio/delivery_status_controller.rb` |
| D | SC | `app/controllers/twitter/base_controller.rb` |
| D | SC | `app/controllers/twitter/callbacks_controller.rb` |
| M | SC | `app/controllers/webhooks/sms_controller.rb` |
| M | SC | `app/controllers/webhooks/tiktok_controller.rb` |
| M | SC | `app/controllers/webhooks/whatsapp_controller.rb` |
| M | SC | `custom/app/controllers/billing/webhooks_controller.rb` |

#### job (5)

| status | phase | path |
|---|---|---|
| M | P9 | `app/jobs/inboxes/fetch_imap_emails_job.rb` |
| A | P9 | `custom/app/jobs/custom/inboxes/fetch_imap_emails_job.rb` |
| M | P9 | `custom/app/jobs/lynomia/queue_health_job.rb` |
| A | P9 | `custom/app/jobs/support/sla_sweep_job.rb` |
| M | SC | `app/jobs/webhooks/sms_events_job.rb` |

#### policy (2)

| status | phase | path |
|---|---|---|
| A | P10 | `custom/app/policies/custom/contact_policy.rb` |
| A | P9 | `custom/app/policies/support/ticket_policy.rb` |

#### helper (1)

| status | phase | path |
|---|---|---|
| M | SC | `app/helpers/tiktok/integration_helper.rb` |

#### lib (5)

| status | phase | path |
|---|---|---|
| A | P8 | `lib/custom_exceptions/analytics.rb` |
| A | P8 | `lib/custom_exceptions/timeline.rb` |
| A | P9 | `lib/custom_exceptions/tickets.rb` |
| A | SC | `lib/integrations/slack/attachment_importer.rb` |
| M | SC | `lib/integrations/slack/slack_message_helper.rb` |

#### migration (9)

| status | phase | path |
|---|---|---|
| A | P10 | `custom/db/migrate/20261009120000_create_contact_identities.rb` |
| A | P10 | `custom/db/migrate/20261009130000_add_social_identity_index_to_contacts.rb` |
| A | P11 | `custom/db/migrate/20261010100000_create_billing_entitlement_overrides.rb` |
| A | P11 | `custom/db/migrate/20261010100100_add_channel_entitlements_to_billing_plans.rb` |
| A | P9 | `custom/db/migrate/20261009100000_create_support_tickets.rb` |
| A | P9 | `custom/db/migrate/20261009100100_create_operations_signals.rb` |
| A | SC | `custom/db/migrate/20261010110000_create_billing_webhook_events.rb` |
| A | SC | `custom/db/migrate/20261010110100_add_last_event_at_to_billing_subscriptions.rb` |
| M | SC | `db/schema.rb` |

#### config (10)

| status | phase | path |
|---|---|---|
| M | P10 | `config/features.yml` |
| M | P11 | `config/locales/en.yml` |
| M | P11 | `config/routes/billing.rb` |
| A | P8 | `config/routes/analytics.rb` |
| M | P9 | `config/initializers/rack_attack.rb` |
| A | P9 | `config/routes/operations.rb` |
| A | P9 | `config/routes/support.rb` |
| M | P9 | `config/schedule.yml` |
| M | SC | `config/initializers/facebook_messenger.rb` |
| M | SC | `config/routes.rb` |

#### super_admin (2)

| status | phase | path |
|---|---|---|
| M | P11 | `custom/app/dashboards/billing_plan_dashboard.rb` |
| A | P11 | `custom/app/fields/billing_plan_channels_field.rb` |

#### view (24)

| status | phase | path |
|---|---|---|
| M | P11 | `custom/app/views/api/v1/accounts/commerce/stores/index.json.jbuilder` |
| A | P11 | `custom/app/views/fields/billing_plan_channels_field/_form.html.erb` |
| A | P11 | `custom/app/views/fields/billing_plan_channels_field/_index.html.erb` |
| A | P11 | `custom/app/views/fields/billing_plan_channels_field/_show.html.erb` |
| M | P11 | `custom/app/views/fields/billing_plan_limits_field/_form.html.erb` |
| A | P11 | `custom/app/views/super_admin/billing_subscriptions/_override_form.html.erb` |
| M | P11 | `custom/app/views/super_admin/billing_subscriptions/show.html.erb` |
| M | P9 | `app/views/super_admin/application/_navigation.html.erb` |
| A | P9 | `app/views/super_admin/operations/_component.html.erb` |
| A | P9 | `app/views/super_admin/operations/_signals.html.erb` |
| A | P9 | `app/views/super_admin/operations/_status_badge.html.erb` |
| A | P9 | `app/views/super_admin/operations/_tabs.html.erb` |
| A | P9 | `app/views/super_admin/operations/accounts.html.erb` |
| A | P9 | `app/views/super_admin/operations/issues.html.erb` |
| A | P9 | `app/views/super_admin/operations/show.html.erb` |
| A | P9 | `custom/app/views/api/v1/accounts/support/events/_event.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/events/index.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/events/show.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/sla_policies/_sla_policy.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/sla_policies/index.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/sla_policies/show.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/tickets/_ticket.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/tickets/index.json.jbuilder` |
| A | P9 | `custom/app/views/api/v1/accounts/support/tickets/show.json.jbuilder` |

#### other (3)

| status | phase | path |
|---|---|---|
| M | P10 | `app/builders/contact_inbox_with_contact_builder.rb` |
| A | P10 | `custom/app/actions/custom/contact_merge_action.rb` |
| A | P10 | `custom/app/builders/custom/contact_inbox_with_contact_builder.rb` |

#### frontend (105)

| status | phase | path |
|---|---|---|
| M | P10 | `app/javascript/dashboard/api/contacts.js` |
| A | P10 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactIdentities.vue` |
| M | P10 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue` |
| A | P10 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/specs/ContactIdentities.spec.js` |
| M | P10 | `app/javascript/dashboard/featureFlags.js` |
| M | P10 | `app/javascript/dashboard/helper/inbox.js` |
| M | P10 | `app/javascript/dashboard/helper/specs/inbox.spec.js` |
| M | P10 | `app/javascript/dashboard/i18n/locale/ar/contact.json` |
| M | P10 | `app/javascript/dashboard/i18n/locale/en/contact.json` |
| M | P10 | `app/javascript/dashboard/modules/contact/components/MergeContactSummary.vue` |
| M | P10 | `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue` |
| M | P10 | `app/javascript/dashboard/routes/dashboard/settings/inbox/ImapSettings.vue` |
| M | P10 | `app/javascript/dashboard/routes/dashboard/settings/inbox/SmtpSettings.vue` |
| M | P10 | `app/javascript/dashboard/routes/dashboard/settings/inbox/specs/ImapSettings.spec.js` |
| M | P11 | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` |
| D | P11 | `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` |
| M | P11 | `app/javascript/dashboard/routes/dashboard/settings/billing/ProviderIndex.vue` |
| M | P11 | `app/javascript/dashboard/routes/dashboard/settings/billing/specs/Index.spec.js` |
| M | P11 | `app/javascript/dashboard/routes/dashboard/settings/subscription/Index.vue` |
| A | P8 | `app/javascript/dashboard/api/analytics.js` |
| A | P8 | `app/javascript/dashboard/api/contactActivity.js` |
| A | P8 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactActivity.vue` |
| A | P8 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactActivityEntry.vue` |
| A | P8 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/specs/ContactActivity.spec.js` |
| A | P8 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/specs/ContactActivityEntry.spec.js` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsBreakdownCard.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsKpiGrid.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsMetaNote.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsRangeControls.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsScreen.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/AnalyticsSeriesCard.vue` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/specs/AnalyticsBreakdownCard.spec.js` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/specs/AnalyticsKpiGrid.spec.js` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/specs/AnalyticsMetaNote.spec.js` |
| A | P8 | `app/javascript/dashboard/components-next/analytics/specs/AnalyticsSeriesCard.spec.js` |
| A | P8 | `app/javascript/dashboard/composables/spec/useAnalyticsQuery.spec.js` |
| A | P8 | `app/javascript/dashboard/composables/spec/useContactActivity.spec.js` |
| A | P8 | `app/javascript/dashboard/composables/useAnalyticsQuery.js` |
| A | P8 | `app/javascript/dashboard/composables/useContactActivity.js` |
| A | P8 | `app/javascript/dashboard/constants/analytics.js` |
| A | P8 | `app/javascript/dashboard/constants/contactActivity.js` |
| A | P8 | `app/javascript/dashboard/i18n/locale/ar/analytics.json` |
| A | P8 | `app/javascript/dashboard/i18n/locale/en/analytics.json` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsAutomations.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsCampaigns.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsCommerce.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsFlows.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsOverview.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsWhatsapp.vue` |
| A | P8 | `app/javascript/dashboard/routes/dashboard/analytics/analytics.routes.js` |
| A | P9 | `app/javascript/dashboard/api/supportTickets.js` |
| A | P9 | `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactCases.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/ConversationTicketsPanel.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketCompactList.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketCreateDialog.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketDetailHeader.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketEnumLabel.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketFilters.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketHistory.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketSidePanel.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketSlaLabel.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketViewTabs.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/TicketsTable.vue` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketCompactList.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketDetailHeader.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketFilters.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketHistory.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketSlaLabel.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketViewTabs.spec.js` |
| A | P9 | `app/javascript/dashboard/components-next/SupportTickets/specs/TicketsTable.spec.js` |
| A | P9 | `app/javascript/dashboard/composables/spec/useSupportTickets.spec.js` |
| A | P9 | `app/javascript/dashboard/composables/useSupportTickets.js` |
| M | P9 | `app/javascript/dashboard/composables/useUISettings.js` |
| M | P9 | `app/javascript/dashboard/constants/permissions.js` |
| M | P9 | `app/javascript/dashboard/constants/specs/permissions.spec.js` |
| A | P9 | `app/javascript/dashboard/constants/supportTickets.js` |
| A | P9 | `app/javascript/dashboard/helper/specs/supportTicketHelper.spec.js` |
| A | P9 | `app/javascript/dashboard/helper/supportTicketHelper.js` |
| M | P9 | `app/javascript/dashboard/i18n/locale/ar/customRole.json` |
| M | P9 | `app/javascript/dashboard/i18n/locale/ar/index.js` |
| M | P9 | `app/javascript/dashboard/i18n/locale/ar/settings.json` |
| A | P9 | `app/javascript/dashboard/i18n/locale/ar/supportTickets.json` |
| M | P9 | `app/javascript/dashboard/i18n/locale/en/customRole.json` |
| M | P9 | `app/javascript/dashboard/i18n/locale/en/index.js` |
| M | P9 | `app/javascript/dashboard/i18n/locale/en/settings.json` |
| A | P9 | `app/javascript/dashboard/i18n/locale/en/supportTickets.json` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsTickets.vue` |
| M | P9 | `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` |
| M | P9 | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` |
| M | P9 | `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/settings/supportSla/Index.vue` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/settings/supportSla/SlaPolicyDialog.vue` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/settings/supportSla/specs/SlaPolicyDialog.spec.js` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/settings/supportSla/supportSla.routes.js` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/tickets/pages/TicketDetailPage.vue` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/tickets/pages/TicketsIndexPage.vue` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/tickets/pages/TicketsRouteView.vue` |
| A | P9 | `app/javascript/dashboard/routes/dashboard/tickets/tickets.routes.js` |
| M | SC | `app/javascript/dashboard/i18n/locale/ar/inboxMgmt.json` |
| M | SC | `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` |
| M | SC | `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelFactory.vue` |
| M | SC | `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue` |
| M | SC | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BandwidthSms.vue` |
| M | SC | `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue` |
| M | SC | `app/javascript/shared/mixins/inboxMixin.js` |

#### spec (95)

| status | phase | path |
|---|---|---|
| A | P10 | `spec/actions/custom/contact_merge_action_spec.rb` |
| A | P10 | `spec/builders/contact_inbox_with_contact_builder_identity_spec.rb` |
| M | P10 | `spec/controllers/api/v1/accounts/actions/contact_merges_controller_spec.rb` |
| A | P10 | `spec/controllers/api/v1/accounts/contacts/identities_controller_spec.rb` |
| M | P10 | `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` |
| A | P10 | `spec/factories/contact_identities.rb` |
| M | P10 | `spec/models/account_spec.rb` |
| A | P10 | `spec/models/contact_identity_spec.rb` |
| A | P10 | `spec/models/contact_linked_identity_spec.rb` |
| A | P10 | `spec/requests/channels/p10_connection_state_spec.rb` |
| A | P10 | `spec/requests/channels/p10_credential_exposure_spec.rb` |
| A | P10 | `spec/requests/contacts/p10_identity_integration_spec.rb` |
| A | P10 | `spec/requests/contacts/p10_identity_isolation_spec.rb` |
| A | P10 | `spec/services/channels/capability_spec.rb` |
| A | P10 | `spec/services/channels/connection_state_spec.rb` |
| A | P10 | `spec/services/contacts/identity_linker_spec.rb` |
| A | P10 | `spec/services/contacts/merge_relocation_spec.rb` |
| A | P10 | `spec/services/operations/account_health_spec.rb` |
| M | P11 | `spec/controllers/api/v1/accounts/billing_controller_spec.rb` |
| A | P11 | `spec/controllers/super_admin/billing_overrides_spec.rb` |
| A | P11 | `spec/controllers/super_admin/billing_plans_spec.rb` |
| M | P11 | `spec/controllers/twilio/callbacks_controller_spec.rb` |
| M | P11 | `spec/controllers/twilio/delivery_status_controller_spec.rb` |
| A | P11 | `spec/factories/billing_entitlement_overrides.rb` |
| A | P11 | `spec/factories/billing_plans.rb` |
| A | P11 | `spec/factories/billing_subscriptions.rb` |
| A | P11 | `spec/models/billing/resource_limit_spec.rb` |
| A | P11 | `spec/requests/billing/account_authorization_spec.rb` |
| M | P11 | `spec/requests/platform/api/v1/billing/authorization_spec.rb` |
| A | P11 | `spec/services/billing/entitlements_spec.rb` |
| A | P11 | `spec/services/billing/feature_sync_spec.rb` |
| A | P11 | `spec/services/billing/plan_audit_spec.rb` |
| A | P11 | `spec/services/billing/plan_change_spec.rb` |
| A | P11 | `spec/services/billing/settings_spec.rb` |
| A | P11 | `spec/services/billing/trial_starter_spec.rb` |
| M | P8 | `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_automations_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_campaigns_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_commerce_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_flows_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_meta_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_overview_spec.rb` |
| A | P8 | `spec/requests/analytics/analytics_whatsapp_spec.rb` |
| A | P8 | `spec/requests/analytics/p8_tenant_isolation_spec.rb` |
| A | P8 | `spec/requests/contacts/contact_activity_spec.rb` |
| A | P8 | `spec/services/analytics/automations/metrics_spec.rb` |
| A | P8 | `spec/services/analytics/campaigns/metrics_spec.rb` |
| A | P8 | `spec/services/analytics/commerce/metrics_spec.rb` |
| A | P8 | `spec/services/analytics/conversations/metrics_spec.rb` |
| A | P8 | `spec/services/analytics/date_range_spec.rb` |
| A | P8 | `spec/services/analytics/filter_set_spec.rb` |
| A | P8 | `spec/services/analytics/flows/metrics_spec.rb` |
| A | P8 | `spec/services/analytics/result_spec.rb` |
| A | P8 | `spec/services/analytics/rollup_coverage_spec.rb` |
| A | P8 | `spec/services/analytics/whatsapp/metrics_spec.rb` |
| A | P8 | `spec/services/contacts/activity_timeline_query_spec.rb` |
| A | P8 | `spec/services/contacts/activity_timeline_spec.rb` |
| A | P9 | `spec/controllers/super_admin/operations_controller_spec.rb` |
| A | P9 | `spec/factories/support/tickets.rb` |
| A | P9 | `spec/jobs/custom/inboxes/fetch_imap_emails_job_spec.rb` |
| A | P9 | `spec/models/custom/reauthorizable_spec.rb` |
| A | P9 | `spec/models/operations/signal_spec.rb` |
| A | P9 | `spec/models/support/ticket_spec.rb` |
| A | P9 | `spec/policies/support/ticket_policy_spec.rb` |
| A | P9 | `spec/requests/analytics/analytics_tickets_spec.rb` |
| A | P9 | `spec/requests/operations/p9_hardening_spec.rb` |
| A | P9 | `spec/requests/support/p9_tenant_isolation_spec.rb` |
| A | P9 | `spec/requests/support/sla_policies_spec.rb` |
| A | P9 | `spec/requests/support/tickets_spec.rb` |
| A | P9 | `spec/services/analytics/tickets/metrics_spec.rb` |
| A | P9 | `spec/services/contacts/activity_timeline/tickets_adapter_spec.rb` |
| A | P9 | `spec/services/operations/computed_signals_spec.rb` |
| A | P9 | `spec/services/operations/signal_recorder_spec.rb` |
| A | P9 | `spec/services/support/tickets/query_spec.rb` |
| A | P9 | `spec/services/support/tickets/reference_allocator_spec.rb` |
| A | P9 | `spec/services/support/tickets/sla_clock_spec.rb` |
| A | P9 | `spec/services/support/tickets/sla_sweeper_spec.rb` |
| A | P9 | `spec/services/support/tickets/status_transition_spec.rb` |
| A | P9 | `spec/services/support/tickets/update_spec.rb` |
| M | SC | `spec/controllers/api/v1/accounts/tiktok/authorizations_controller_spec.rb` |
| D | SC | `spec/controllers/api/v1/accounts/twitter/authorizations_controller_spec.rb` |
| M | SC | `spec/controllers/tiktok/callbacks_controller_spec.rb` |
| D | SC | `spec/controllers/twitter/callbacks_controller_spec.rb` |
| M | SC | `spec/controllers/webhooks/sms_controller_spec.rb` |
| M | SC | `spec/factories/channel/channel_sms.rb` |
| M | SC | `spec/jobs/webhooks/sms_events_job_spec.rb` |
| M | SC | `spec/lib/integrations/slack/incoming_message_builder_spec.rb` |
| M | SC | `spec/requests/api/v1/integrations/webhooks_request_spec.rb` |
| A | SC | `spec/requests/billing/webhook_security_spec.rb` |
| A | SC | `spec/requests/tiktok/oauth_state_security_spec.rb` |
| A | SC | `spec/requests/webhooks/public_endpoint_authentication_spec.rb` |
| A | SC | `spec/requests/webhooks/sms_security_spec.rb` |
| A | SC | `spec/requests/webhooks/whatsapp_routing_isolation_spec.rb` |
| D | SC | `spec/services/twitter/webhook_subscribe_service_spec.rb` |
| M | SC | `spec/support/slack_stubs.rb` |

#### docs (45)

| status | phase | path |
|---|---|---|
| A | P10 | `docs/p10/00-discovery.md` |
| A | P10 | `docs/p10/01-architecture.md` |
| A | P10 | `docs/p10/02-channel-capability-matrix.md` |
| A | P10 | `docs/p10/03-unified-customer-identity.md` |
| A | P10 | `docs/p10/04-contact-merge-linking.md` |
| A | P10 | `docs/p10/05-omnichannel-customer-360.md` |
| A | P10 | `docs/p10/06-channel-lifecycle-health.md` |
| A | P10 | `docs/p10/07-security-performance.md` |
| A | P10 | `docs/p10/08-uat-runbook.md` |
| A | P10 | `docs/p10/P10_FINAL_COMPLETION_REPORT.md` |
| A | P10 | `docs/p10/P10_RELEASE_GATE.md` |
| A | P11 | `docs/p11/01-discovery.md` |
| A | P11 | `docs/p11/02-commercial-architecture.md` |
| A | P11 | `docs/p11/03-plans-entitlements.md` |
| A | P11 | `docs/p11/04-subscriptions-billing.md` |
| A | P11 | `docs/p11/05-usage-limits.md` |
| A | P11 | `docs/p11/06-rollout-compatibility.md` |
| A | P11 | `docs/p11/07-security-performance.md` |
| A | P11 | `docs/p11/08-uat-runbook.md` |
| A | P11 | `docs/p11/P11_FINAL_COMPLETION_REPORT.md` |
| A | P11 | `docs/p11/P11_RELEASE_GATE.md` |
| A | P8 | `docs/p8/00-discovery.md` |
| A | P8 | `docs/p8/00b-rollup-production-check.md` |
| A | P8 | `docs/p8/01-architecture.md` |
| A | P8 | `docs/p8/02-analytics.md` |
| A | P8 | `docs/p8/02a-overview-conversation-analytics.md` |
| A | P8 | `docs/p8/02b-whatsapp-campaign-analytics.md` |
| A | P8 | `docs/p8/02c-automation-flow-analytics.md` |
| A | P8 | `docs/p8/02d-commerce-analytics.md` |
| A | P8 | `docs/p8/03-contact-activity-timeline.md` |
| A | P8 | `docs/p8/04-security-performance.md` |
| A | P8 | `docs/p8/05-uat-runbook.md` |
| A | P8 | `docs/p8/P8_FINAL_COMPLETION_REPORT.md` |
| A | P8 | `docs/p8/P8_RELEASE_GATE.md` |
| A | P9 | `docs/p9/00-discovery.md` |
| A | P9 | `docs/p9/01-architecture.md` |
| A | P9 | `docs/p9/02-support-tickets.md` |
| A | P9 | `docs/p9/03-sla-workflow.md` |
| A | P9 | `docs/p9/04-operations-center.md` |
| A | P9 | `docs/p9/05-integration-health.md` |
| A | P9 | `docs/p9/06-security-performance.md` |
| A | P9 | `docs/p9/07-uat-runbook.md` |
| A | P9 | `docs/p9/P9_FINAL_COMPLETION_REPORT.md` |
| A | P9 | `docs/p9/P9_RELEASE_GATE.md` |
| A | SC | `docs/p11/00-p10-security-closure.md` |

---

Generated mechanically from `git diff --name-status b03ea43d..HEAD` plus per-file `git log`;
the script is recorded in the P-FINAL completion report so the table can be regenerated and checked.
