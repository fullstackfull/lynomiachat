# Clean implementation record

**This is technical process evidence only. It makes no claim of legal clearance.**

It records, for every file written as part of the clean-room replacement implementation, what the file is for,
what it was written from, and which already-present interfaces it depends on.

## How this implementation was produced

The implementer was given one sanitized source tree (`lynomia-cleanroom-source-20261011.tar.gz`, reassembled
from five parts, SHA-256 `cb9739abfa23b2d68942e8ef68beca35543ef4bdc0b798e23090a27a192bbd3d`, 108,294,487
bytes) and nothing else. Before any file was copied, the tree was verified to contain:

| checked | result |
|---|---|
| any `.git` directory, at any depth | none |
| any `enterprise/` directory | none |
| `spec/enterprise/` | absent |
| `*.patch`, `*.diff`, `*.bundle`, `*.rej`, `*.orig` | none |
| absolute or `../` paths in the archive | none |
| symlinks leaving the tree | none |
| clean-room specifications | present under `docs/p-final/clean-room/` |
| `app/`, `custom/`, `config/`, `db/`, `spec/`, `docs/` | present |

The repository's history begins at the commit that imported that tree. No earlier commit is reachable from it.

### Authorized sources, and only these

1. the sanitized source tree itself (upstream Chatwoot under `app/`, `lib/`, `config/`, and the clean Lynomia
   overlay under `custom/`);
2. `docs/p-final/clean-room/specs/A`–`E`;
3. `docs/p-final/clean-room/01-acceptance-test-plan.md`, `02-safe-interfaces.md`, `04-integration-contract.md`;
4. the shipped frontend under `app/javascript/`, read as the specification of the wire format it consumes;
5. the retained clean test suite, read as a statement of what clean code outside the rewrite calls;
6. third-party gem source already vendored by `bundle install` (`audited`, `devise_token_auth`, Rails), read to
   establish what those libraries actually do.

### Nothing else was consulted

No original Lynomia repository, branch, commit, patch, diff or bundle. No Chatwoot Enterprise source. No
provenance report and no blocker report. No web or GitHub search for any prior implementation. Where a
specification referenced a removed file's internals — `custom/app/models/campaign_recipient.rb:53-57`,
`:70-72`, `#update_from_whatsapp_status!`, `#mark_skipped!` — those references were treated as evidence that a
behaviour had existed, never as a design to reproduce; the line ranges named code that is not in the workspace
and was not sought out. Method names, class names, module boundaries and query shapes in this implementation
were chosen independently, which is why the one retained spec that called a removed method by name had to be
adapted rather than satisfied (see the final section).

---

## A — Audit trail: the read surface

| | |
|---|---|
| **CLEAN SPECIFICATION USED** | `specs/A-audit-trail-read.md`; `01-acceptance-test-plan.md` §A; `04-integration-contract.md` §1, §3.1, §5 |
| **NO ENTERPRISE SOURCE CONSULTED** | YES |

| PATH | PURPOSE | AUTHORING BASIS | SAFE INTERFACES USED |
|---|---|---|---|
| `custom/app/models/custom/audit_log.rb` | The audit record. The `audited` gem's audit class (named by `config/initializers/audited.rb`), plus the account-trail read scopes, the actor display-name capture, and the rule that no credential reaches `audited_changes`. | Spec A §2–§6, spec B §2–§5; the gem's own `Audited::Audit` read from vendored source. | DEPENDENCY `audited ~> 5.4` (`Audited::Audit`, `as_user`, `auditable_finder`); DATABASE CONTRACT `audits`; OSS `User#available_name` |
| `custom/app/services/audit_trail/secrets.rb` | The one definition of "this change describes a credential", applied on write and again on read. | Spec A §5, spec B §5 (a matching field is omitted, not masked or hashed). | OSS `Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS` (as the list of names to recognise) |
| `custom/app/services/audit_trail/filters.rb` | Parses the trail's filter surface from a request, leniently, so a stale URL yields a page rather than a 500. | Spec A §2 (the documented parameters) and the shipped client's actual spelling in `dashboard/helper/auditlogHelper.js:272-287`. | OSS request params; `Time.zone` |
| `custom/app/services/audit_trail/query.rb` | One page of one account's trail: account scope first, capability gate, filters, order, pagination. | Spec A §2, §4; `04` §5 (capability off ⇒ empty page, not an error). | DEPENDENCY `kaminari`; OSS `Account#feature_enabled?`; `Custom::AuditLog` scopes |
| `custom/app/services/audit_trail/disclosure.rb` | What one account may see of its own trail: address coarseness and credential withholding. The column either holds an address or holds nothing shown, in both configurations. | Spec A §5 ("a blank or unparseable stored address must produce a null", stated unconditionally), §6; `config/features.yml:277`. | Ruby stdlib `IPAddr`; OSS `Account#feature_enabled?`; `AuditTrail::Secrets` |
| `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` | The endpoint. Administrator-only. | Spec A §2; `config/routes.rb:84`. | OSS `Api::V1::Accounts::BaseController`, `Api::BaseController#check_admin_authorization?`, `Current` |
| `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | The four meta keys the store reads by name. | `dashboard/store/modules/auditlogs.js:40-51`. | DEPENDENCY `jbuilder` |
| `custom/app/views/api/v1/accounts/audit_logs/_audit_log.json.jbuilder` | One entry, including the nested `auditable` the browser tests with `=== null`. | `dashboard/helper/auditlogHelper.js:103,181-189,212-220`; `settings/auditlogs/Index.vue:229,239`. | DEPENDENCY `jbuilder` |

---

## B — Audit trail: event capture

| | |
|---|---|
| **CLEAN SPECIFICATION USED** | `specs/B-audit-event-capture.md`; `01-acceptance-test-plan.md` §B; `02-safe-interfaces.md` §1 (the thirteen declared include sites) |
| **NO ENTERPRISE SOURCE CONSULTED** | YES |

| PATH | PURPOSE | AUTHORING BASIS | SAFE INTERFACES USED |
|---|---|---|---|
| `custom/app/models/custom/audit/capture.rb` | What every macro-declared capture point shares: a savepoint so a failed audit cannot roll back the product action, and suppression of a cascade. | Spec B §6, §8 criterion 9; the gem's `write_audit` read from vendored source. | DEPENDENCY `audited`; OSS `ChatwootExceptionTracker` |
| `custom/app/services/audit_trail/capture.rb` | The actor and the suppression flag for paths that run outside a request. | Spec B §4 (asynchronous deletion names the requester), §8 criterion 9. | DEPENDENCY `audited` (`Audited.store`, an `ActiveSupport::CurrentAttributes` store) |
| `custom/app/services/audit_trail/event.rb` | The write entry point for the events that are not row changes: sign-in, sign-out, a message deletion, a channel configuration change. The actor is never a parameter. | Spec B §2, §5 ("the actor is recorded, not asserted"), §6; the call shape the six clean Lynomia writers already use. | `Custom::AuditLog`, DEPENDENCY `audited` (`as_user`, the request store); OSS `ChatwootExceptionTracker` |
| `custom/app/models/custom/audit/account.rb` | B1 — an account's settings change. | Spec B B1. `feature_flags` deliberately excluded: P11 already records capability moves with their reason. | OSS include site `app/models/account.rb:243` |
| `custom/app/models/custom/audit/account_user.rb` | B2 — a membership is created or changed, with the role, the availability and the attached set. | Spec B B2; `auditlogHelper.js:58-77,218`. | OSS include site `app/models/account_user.rb:103` |
| `custom/app/models/custom/audit/inbox.rb` | B3 — inbox lifecycle. | Spec B B3. | OSS include site `app/models/inbox.rb:282` |
| `custom/app/models/custom/audit/inbox_member.rb` | B4 — inbox membership. | Spec B B4; `auditlogHelper.js:135-140`. | OSS include site `app/models/inbox_member.rb:44` |
| `custom/app/models/custom/audit/team.rb` | B5 — team lifecycle. | Spec B B5. | OSS include site `app/models/team.rb:89` |
| `custom/app/models/custom/audit/team_member.rb` | B6 — team membership. | Spec B B6; `auditlogHelper.js:128-133`. | OSS include site `app/models/team_member.rb:31` |
| `custom/app/models/custom/audit/automation_rule.rb` | B7 — automation rule lifecycle, identifying fields only. | Spec B B7, §6 (context reduced rather than stored wholesale). | OSS include site `app/models/automation_rule.rb:162` |
| `custom/app/models/custom/audit/macro.rb` | B8 — macro lifecycle, identifying fields only. | Spec B B8, §6. | OSS include site `app/models/macro.rb:78` |
| `custom/app/models/custom/audit/webhook.rb` | B9 — webhook lifecycle, with the signing secret excluded by construction. | Spec B B9, §5. | OSS include site `app/models/webhook.rb:46` |
| `custom/app/models/custom/audit/agent_bot.rb` | B10 — agent bot lifecycle. A global bot has no account and so is not recorded. | Spec B B10, §5 (an entry with no account must not be written). | OSS include site `app/models/agent_bot.rb:72` |
| `custom/app/models/custom/audit/conversation.rb` | B12 — a conversation removal, named by the number a person recognises. | Spec B B12; `auditlogHelper.js:181-184`. | OSS include site `app/models/conversation.rb:434` |
| `custom/app/models/custom/audit/user.rb` | Claims the declared include site and states why B14 is recorded from the session instead. | `02-safe-interfaces.md` §1 (either route satisfies B14). | OSS include site `app/models/user.rb:229` |
| `custom/app/models/custom/channelable.rb` | B15 — a channel configuration change, recorded as an inbox update, with credentials named but never valued and the product's own bookkeeping excluded. | Spec B B15, §5; `01` B-17, B-18; the empty hook upstream declares. | OSS extension point `app/models/concerns/channelable.rb:7,10,13`; `AuditTrail::{Event,Secrets}` |
| `custom/app/jobs/custom/delete_object_job.rb` | B16 — the asynchronous deletion names the person who asked, and the cascade is not audited. | Spec B B16, §8 criterion 9; the two upstream call sites that already thread the user and the address. | OSS extension point `app/jobs/delete_object_job.rb:43`; `AuditTrail::Capture` |
| `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | B14 — sign-in and sign-out, on the trail of the account the session is for. | Spec B B14, §9 (no failed-authentication recording); `auditlogHelper.js:22-23`; DTA's `destroy`, which yields the user. | OSS extension point `app/controllers/devise_overrides/sessions_controller.rb:244`; DEPENDENCY `devise_token_auth` |
| `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | B13 — a message deletion that names its conversation and never its content, recorded once under concurrency. | Spec B B13, §5; `01` B-13, B-14. | OSS extension point `.../messages_controller.rb:132`; `AuditTrail::Event` |

---

## C — Named permission sets for account members

| | |
|---|---|
| **CLEAN SPECIFICATION USED** | `specs/C-account-role-permissions.md`; `01-acceptance-test-plan.md` §C; `04-integration-contract.md` §2.2, §3.2 |
| **NO ENTERPRISE SOURCE CONSULTED** | YES |

| PATH | PURPOSE | AUTHORING BASIS | SAFE INTERFACES USED |
|---|---|---|---|
| `custom/app/models/custom_role.rb` | The role: a name, a description and a validated set of capability identifiers from a closed vocabulary. Deleting it detaches each membership through the model -- not through `update_all` -- so the callback that invalidates a member's cached conversation visibility still runs. | Spec C §2 (the published vocabulary), §3, §5, §6, §9 (a plain array, no join table); OSS `app/models/account_user.rb:85-87`, which declares `custom_role_id` a visibility-affecting column. | DATABASE CONTRACT `custom_roles`; ORIGINAL LYNOMIA capability strings in the three clean policies; `dashboard/constants/permissions.js` |
| `custom/app/models/custom/account_user.rb` | The one list every capability check reads: the attached set's capabilities plus a marker, or Chatwoot's role-derived list. | Spec C §4 (stated as the rule, written here independently); `dashboard/helper/permissionsHelper.js:19-26`. | OSS extension point `app/models/account_user.rb:102`; OSS `AccountUser#permissions` (reached by `super`) |
| `custom/app/models/custom/concerns/account.rb` | An account owns the sets it defines. | Spec C §4 (dictated by `custom_roles.account_id`). | OSS include site `app/models/account.rb:242` |
| `custom/app/models/custom/concerns/account_user.rb` | A membership may hold one set. | Spec C §4 (dictated by `account_users.custom_role_id`). | OSS include site `app/models/account_user.rb:104` |
| `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` | The five endpoints, administrator-only, account-scoped, with the account capability checked at the boundary. | Spec C §2, §5; `config/routes.rb:100`. | OSS `Api::V1::Accounts::BaseController`, `check_admin_authorization?`, `Pundit::NotAuthorizedError`; OSS `Account#feature_enabled?` |
| `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` | Attaching and detaching a set on the agent endpoints, scoped to the asking account, with a detachment that survives upstream's `.compact`. | Spec C §2, §5; `settings/agents/{AddAgent,EditAgent}.vue`. | OSS extension point `app/controllers/api/v1/accounts/agents_controller.rb:120` |
| `custom/app/views/api/v1/accounts/custom_roles/{_custom_role,index,show}.json.jbuilder` | The role's four keys; the list is a bare array. | `dashboard/store/modules/customRole.js:30,41,57`. | DEPENDENCY `jbuilder` |
| `custom/app/views/api/v1/models/_account_user.json.jbuilder` | The membership's role attachment, at the path the OSS user view renders by name — both the id and the nested name the account switcher reads unguarded. | `04` §3.2, §8; `app/views/api/v1/models/_user.json.jbuilder:41`; `components-next/sidebar/SidebarAccountSwitcher.vue:121-124`. | DEPENDENCY `jbuilder` |

---

## D — Per-recipient outcome of a one-off WhatsApp campaign

| | |
|---|---|
| **CLEAN SPECIFICATION USED** | `specs/D-campaign-recipient-outcomes.md`; `01-acceptance-test-plan.md` §D; `04-integration-contract.md` §2.3, §3.3, §7 |
| **NO ENTERPRISE SOURCE CONSULTED** | YES |

| PATH | PURPOSE | AUTHORING BASIS | SAFE INTERFACES USED |
|---|---|---|---|
| `custom/app/models/campaign_recipient.rb` | The record, and the forward-only ladder: one guarded write under a row lock that takes a reported state plus its timestamp, never demotes, refuses a failure over a delivery, and treats a failure as terminal so no row can carry both a delivery and a failure timestamp. | Spec D §3, §4.2 ("`failed` is terminal once reached"), §4.3, §9 (recommended as one guarded write rather than a branch per state). | DATABASE CONTRACT `campaign_recipients`; OSS `Account`, `Campaign`, `Contact`, `Inbox` |
| `custom/app/models/custom/campaign.rb` | A campaign owns its recipient snapshot. | Spec D §3; the mirror of the clean association a contact already has. | OSS include site `app/models/campaign.rb:(tail)` |
| `custom/app/services/campaigns/recipient_snapshot.rb` | The snapshot writer: one row per addressed contact, idempotent across a re-run, with a closed set of data-free skip reasons. | Spec D §4.1, §4.4, §5.2; P8's skip-reason grouping. | OSS `Campaign`; DATABASE CONTRACT the unique `(campaign_id, contact_id)` index |
| `custom/app/services/campaigns/rendered_template_text.rb` | The text one contact was sent, reassembled from the template body and that contact's resolved values. | Spec D §3 (`message_content` is the rendered template). | OSS `Whatsapp::TemplateContentRendererService`, `Whatsapp::TemplateParameterConverterService`, `Channel::Whatsapp#message_templates` |
| `custom/app/services/campaigns/recipient_metrics.rb` | The campaign's funnel, counted with P8's own definitions so the two views cannot disagree. | Spec D §2, §4.3, §8 criteria 2 and 3. | P8 `Analytics::Campaigns::Metrics::DELIVERED_SQL`; `CampaignRecipient` |
| `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | Records each outcome where upstream already decides it, without re-expressing upstream's send loop. | Spec D §4.1 (the table of what the send path does and what the record must say). | OSS extension point `app/services/whatsapp/oneoff_campaign_service.rb:148`; OSS `Channel::Whatsapp#send_template`; `Custom::Channel::Whatsapp#last_send_failure` |
| `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | The two endpoints, under the campaign's own authorization, account-scoped, with an invalid `status` refused at the boundary. | Spec D §2, §5; `config/routes.rb:104-105`. | OSS `Api::V1::Accounts::BaseController`, `CampaignPolicy`; DEPENDENCY `kaminari` |
| `custom/app/views/api/v1/accounts/campaigns/analytics/contacts.json.jbuilder` | `payload` and `meta.total_count`, and every key the recipient table reads per row. | `WhatsAppCampaignAnalyticsPage.vue:278-279`; `CampaignDeliveryTable.vue:38-49,89-113`. | DEPENDENCY `jbuilder` |

---

## E — WhatsApp delivery outcomes reaching the records that need them

| | |
|---|---|
| **CLEAN SPECIFICATION USED** | `specs/E-whatsapp-delivery-status-propagation.md`; `01-acceptance-test-plan.md` §E |
| **NO ENTERPRISE SOURCE CONSULTED** | YES |

| PATH | PURPOSE | AUTHORING BASIS | SAFE INTERFACES USED |
|---|---|---|---|
| `custom/app/services/whatsapp/delivery_report.rb` | The router: which record owns this identifier, or nothing does. It holds no copy of the advance rule. | Spec E §4.2, §4.3, §5.1, §9 (recommended to stay a router). | DATABASE CONTRACT the unique partial `source_id` index; `CampaignRecipient#record_outcome!`; OSS `Inbox` |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | Offers every entry of a `statuses` payload to the router, after upstream's conversation-message path has run unchanged. | Spec E §2, §4.1, §4.5, §6. | OSS extension point `app/services/whatsapp/incoming_message_base_service.rb:230`; OSS `ChatwootExceptionTracker` |
| `custom/app/services/whatsapp/send_failure.rb` | Meta's refusal of a send, in the three parts a recipient stores it in. | Spec E §2, §4.4, §5.2, §6. | OSS `Whatsapp::Providers::WhatsappCloudService` response shape; Meta's documented error body |
| `custom/app/services/custom/whatsapp/providers/base_service.rb` | Keeps the refusal on the provider instance that saw it, so a send with no `Message` is not the one case whose reason is lost. | Spec E §4.4. | OSS extension point `app/services/whatsapp/providers/base_service.rb:136` |
| `custom/app/models/custom/channel/whatsapp.rb` | One provider instance, kept alive across a template send, so its refusal survives the call. | Spec E §4.4 (names this obstacle explicitly and leaves the remedy to the implementer). | OSS extension point `app/models/channel/whatsapp.rb:238`; OSS `Channel::Whatsapp#provider_service` |

---

## Files outside the five packages that were changed, and why

Each of these is clean code that is **not** part of the rewrite. Changing it was a declared decision, not a
side effect.

| PATH | CHANGE | WHY |
|---|---|---|
| `custom/app/services/analytics/campaigns/metrics.rb` | Comments only. Four references to a removed writer's method names and line numbers now name the methods that exist. | The file's comments cited `#update_from_whatsapp_status!`, `#mark_skipped!` and `campaign_recipient.rb:53-57`/`:70-72`. Those name code that is not in this workspace. The rewrite chose its own method names, as `04-integration-contract.md` §2.4 permits, so the comments were pointing at nothing. No executable line changed. |
| `spec/services/analytics/campaigns/metrics_spec.rb` | One example's two calls now use `#record_outcome!(state, reported_at:)` instead of `#update_from_whatsapp_status!(status:, timestamp:)`. The assertions are unchanged. | A retained clean spec called a removed method by name. `04` §2.4 states that "the names, arity and decomposition of every method inside your packages" may be redesigned, and the clean-room brief asks for an independent implementation rather than a reproduction of the previous interface — so the test was adapted to the new writer rather than the writer named to suit the test. What the example asserts (read-before-delivered ends as read, with both timestamps set, and the analytics agreeing) is unchanged. |
| `config/locales/en.yml` | Three new keys under `errors.custom_roles` and `errors.campaigns`. | Validation and refusal copy for the two new request boundaries. English only; other locales are Crowdin's. |
| `app/javascript/dashboard/i18n/locale/en/customRole.json` | Removed the dead `CUSTOM_ROLE.PAYWALL.*` and `CUSTOM_ROLE.ENTERPRISE_PAYWALL.*` subtrees. | `specs/C` §9 asks for the upgrade copy to stop living under another vendor's paywall name. The clean frontend had already moved to `CUSTOM_ROLE.PLAN_NOTICE.*` (`CustomRolePaywall.vue`), leaving both subtrees unreferenced. English only. |

## Schema

No migration was added. Every table, column, enum value and index the five packages use already exists in
`db/schema.rb`: `audits`, `custom_roles`, `account_users.custom_role_id`, `campaign_recipients` (including the
unique `(campaign_id, contact_id)`, the unique partial `source_id` and `(campaign_id, status)` indexes), and
`messages.source_id`/`.status`/`.external_error`. `audits.city`, `.country` and `.country_code` remain unwritten
and unread.

## Retained clean tests that still fail, and why

Four examples fail on the finished tree. Each was verified against a git worktree checked out at the sanitized
snapshot commit — the tree as it arrived, before any of this work — with its own database, so "pre-existing"
below means reproduced there, not inferred.

| Example | Verified | Why it is not one of the five packages |
| --- | --- | --- |
| `spec/services/commerce/store_connection_spec.rb:143` | Fails identically on the snapshot. | P11's `BillingPlan` refuses to narrow a plan that an account is billed on, while this clean Commerce spec narrows one. A disagreement between two retained clean components, neither of them in A–E. |
| `spec/services/whatsapp/incoming_message_whatsapp_cloud_service_interactive_reply_spec.rb:19` | Fails identically on the snapshot. | The inbound capture of `content_attributes['interactive_reply']` is absent from the sanitized tree. `specs/E` §9 excludes inbound message handling of any kind. |
| `spec/services/flows/nodes/choice_spec.rb:89` | All five examples in the file fail on the snapshot, inside `Flows::Audit.record`. Package B's capture surface fixed four of them; this one then fails further on, in `app/services/whatsapp/providers/whatsapp_cloud_service.rb`, which is byte-identical to the snapshot. | Flow Builder's outbound WhatsApp **list** payload: the clean Flows code sets `interactive_type: 'list'` and `list_button`, and upstream's `create_payload_based_on_items` does not translate them into `action.sections[].rows`. An outbound payload shape, not delivery or status propagation; no clean specification describes it. |
| `spec/models/conversation_spec.rb:1144` | Flaky on both trees: 2 failures in 5 runs here, and it fails on the snapshot with the identical value. | A wall-clock assertion with a one-second tolerance (`expect(...).to be_within(1.second).of(1.hour)`) that measures `3602.0` on a loaded container. Load-dependent, and unrelated to A–E. |

None was repaired by reconstructing removed code from its retained test, which the brief forbids.
