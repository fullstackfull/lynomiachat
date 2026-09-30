# New feature flags from Chatwoot 4.18 and Lynomia billing plans (Phase 4, item 18)

**No production plan was changed.** This is a review for a product decision.

## How Lynomia plans pick up features

- `BillingPlan.assignable_features` (`custom/app/models/billing_plan.rb:34`) offers every flag in `config/features.yml` except the internal, deprecated, premium and system ones.
- `Billing::FeatureSync` (`custom/app/services/billing/feature_sync.rb`) runs when a plan is saved or a subscription is synced. It:
  - **enables** the plan's features;
  - **disables every other assignable feature** on the subscribed accounts.
- So with 4.18, six new flags become plan-managed. A flag enabled by hand in Super Admin on a subscribed account is switched off at the next sync unless the plan includes it.
- **State after the migration** (checked on the migrated staging DB):
  - the six flags are **off** on every existing account, because the new `feature_flags_ext_1` column starts at 0;
  - accounts created after the upgrade get the `enabled:` defaults below;
  - `ChatwootApp.chatwoot_cloud?` is **false** (no `DEPLOYMENT_ENV=cloud`).

Two more new flags are **not** assignable, so they cannot appear in plans:
- `audit_log_ip_address` (premium);
- `unread_count_for_filters` (Chatwoot internal).

## The six assignable flags

| Feature (display name) | Upstream purpose | Default for new accounts | Does it gate anything on Lynomia (self-hosted, Enterprise overlay)? | Currently enabled (existing accounts) | Customer visible | Billing impact | Recommended Lynomia plan |
|---|---|---|---|---|---|---|---|
| `api_and_webhooks` (API and Webhooks) | Chatwoot Cloud plan gate for API access tokens and outbound account webhooks | `true` | **No.** `Enterprise::Account#api_and_webhooks_enabled?` returns `true` unless `chatwoot_cloud?`, and the Webhooks page shows it when not on Cloud (`Webhooks/Index.vue:49`) | off (inert) | no | None today. It would cut API and webhook access for plans without it **if** `DEPLOYMENT_ENV=cloud` were ever set | **Include in every plan**, so behaviour cannot change if the deployment env changes |
| `branded_email_templates` (Branded Email Templates) | Branded HTML layout for outgoing conversation emails, per account and per email inbox | `false` | **Yes:** `BrandedEmailLayoutsController`, `InboxesController#update_branded_email_layout`, `ConversationReplyMailer`, `EmailTemplates::DbResolverService` | off | yes: Settings → Templates, and inbox email layout | New paid capability | Higher plans (Pro / Business) |
| `data_import` (Data Import) | Import contacts and conversations from other tools (Settings → Data), with background jobs | `false` | **Yes:** `DataImportsController` (Pundit) and the Settings → Data sidebar entry | off | yes: Settings → Data | New capability. Heavy background jobs and DB load | **Keep OFF** until it is tested on Lynomia data and support is ready. Later, higher plans only |
| `delayed_automations` (Delayed Automations) | Automation rules with a wait before execution (`execution_delay`) | `false` | **Yes:** `AutomationRulesController` rejects delays without it, and the automation form hides the option | off | yes: Automations → rule form | New capability. Scheduled jobs | Pro / Business |
| `whatsapp_manual_transfer` (WhatsApp Manual Transfer) | Lets an admin move an Embedded Signup WhatsApp inbox to manual token setup. Shown only when the number is **not** on the Business app and health is fine | `false` | **Yes** (inbox settings button) | off | admins only | Support tool, not a sellable feature | **Not in any plan.** Note that a plan sync switches it off again if support enables it by hand. It is never shown for WhatsApp Business (Coexistence) numbers (`is_on_biz_app` must be false) |
| `whatsapp_embedded_signup_inbox_creation` (WhatsApp Embedded Signup Flow) | Chatwoot Cloud gate for creating WhatsApp inboxes through Embedded Signup | `false` | **No.** The backend check returns early unless `chatwoot_cloud?`, and the frontend is `!isOnChatwootCloud \|\| flag` | off (inert) | no | None | Leave out of plans. It does **not** control WhatsApp Business on Lynomia. The real controls are the Super Admin WhatsApp Embedded config and the administrator role (Phase 4 commit C) |

## Decisions needed before production

1. Add `api_and_webhooks` to every existing plan. It has no effect today; it is a safety net.
2. Choose plans for `branded_email_templates` and `delayed_automations`, or leave them off.
3. Keep `data_import` and `whatsapp_manual_transfer` out of plans for now.
4. Review the plans in Super Admin → Billing Plans after the upgrade. Saving a plan triggers `FeatureSync` for all its subscribers.
