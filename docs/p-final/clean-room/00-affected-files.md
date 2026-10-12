# Clean-room step 1 — affected file register

**Audience: the engineering lead preparing the clean-room workspace. NOT the clean-room implementer.**
This document names historical Enterprise paths, so it is deliberately excluded from the sanitized export
(`03-clean-workspace-manifest.md` §4).

Product decision recorded: **Lynomia must not depend on Chatwoot Enterprise**, and no Enterprise subscription is
being relied on. Every row below therefore needs an independent implementation, a removal, or an explicit
"not required" — nothing stays as-is.

Provenance evidence is summarised per row; the full measurements are in `../04-code-provenance.md`.
No legal conclusion is stated here or anywhere in this package.

---

## 1. Production code — 39 files

### Family A — Audit trail: read surface (2 files)

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` | `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb` | serves the account's audit trail to Settings → Audit Logs | **yes** | `app/javascript/dashboard/api/auditLogs.js`, `store/modules/auditlogs.js`, `routes/dashboard/settings/auditlogs/*` | **REWRITE** | 90% substantive-line overlap, 36/40; difference is a header, a superclass swap, one inlined helper |
| `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | same path under `enterprise/` | renders each audit row and the page meta | **yes** | same frontend | **REWRITE** | 96%, 25/26; differs by one deleted line |

### Family B — Audit trail: record model and event registration (13 files)

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/models/custom/audit_log.rb` | `enterprise/app/models/enterprise/audit_log.rb` | the audit record: actor naming, address masking, read scopes | **yes** | the read surface; every writer in families B and D; P9/P10/P11 audit writers | **REWRITE (carried portion)** | 57%, 20/35. The polymorphic-actor fix and the deliberate omission of IP geolocation are Lynomia's |
| `custom/app/models/custom/audit/{account,account_user,agent_bot,automation_rule,conversation,inbox,inbox_member,macro,team,team_member,webhook}.rb` (11 files) | `enterprise/app/models/enterprise/audit/<same>.rb` | register which record types produce audit entries, and which of their fields are recorded | **yes** | the read surface and its event filter | **REWRITE (trivial)** | 2 at 100%/18 lines; the rest ≤5 substantive lines of declaration. Re-derivable from the schema and the event vocabulary |
| `custom/app/models/custom/campaign.rb` | `enterprise/app/models/enterprise/campaign.rb` | campaign-side association used by recipient tracking | **yes** | Family D | **REWRITE (trivial)** | 100%, 4/4 substantive lines |

`custom/app/models/custom/audit/custom_filter.rb` has **no** Enterprise counterpart — it is original Lynomia
work (audience auditing) and stays untouched.

### Family C — Role-based permissions beyond the built-in roles (10 files)

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/models/custom_role.rb` | `enterprise/app/models/custom_role.rb` | the named permission set an account defines | **yes** | `Custom::AccountUser#permissions` (Family G), Commerce and Support policies, the role UI | **REWRITE** | git rename R091; 100% overlap, 31/31 |
| `custom/app/policies/custom_role_policy.rb` | `enterprise/app/policies/custom_role_policy.rb` | who may administer roles | **yes** | the roles controller | **REWRITE** | git rename **R100**, byte-identical |
| `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` | `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` | role CRUD API | **yes** | `app/javascript/dashboard/api/customRole.js`, the agent and role settings pages | **REWRITE** | git rename R070; 95%, 19/20 |
| `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` | `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` | lets an agent be created or edited with a role attached | **yes** | `routes/dashboard/settings/agents/{AddAgent,EditAgent,Index}.vue` | **REWRITE** | git rename R073; 82%, 9/11 |
| `custom/app/views/api/v1/accounts/custom_roles/{index,create,show,update}.json.jbuilder` (4) | same paths under `enterprise/` | role API responses | **yes** | the role UI | **REWRITE (trivial)** | git renames **R100**, byte-identical; 1-2 substantive lines each |
| `custom/app/views/api/v1/models/_custom_role.json.jbuilder` | same under `enterprise/` | the role's serialised shape | **yes** | the role UI, the agent list | **REWRITE (trivial)** | git rename **R100**, byte-identical, 6 lines |
| `custom/app/views/api/v1/models/_account_user.json.jbuilder` | same under `enterprise/` | exposes a membership's attached role | **yes** | the agent list, `helper/permissionsHelper.js` | **REWRITE (trivial)** | git rename **R100**, byte-identical, 2 lines |

### Family D — Campaign recipient tracking (4 files)

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/models/campaign_recipient.rb` | `enterprise/app/models/campaign_recipient.rb` | one row per contact a campaign targeted, with its delivery outcome | **yes** | P8 campaign analytics, the campaign analytics API, Family E | **REWRITE** | git rename R081; 96%, 54/56 |
| `custom/app/jobs/campaigns/update_recipient_status_job.rb` | `enterprise/app/jobs/campaigns/update_recipient_status_job.rb` | applies a provider outcome to a recipient asynchronously | **yes** | Family E | **REWRITE** | git rename **R100**, byte-identical |
| `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | per-campaign delivery metrics and the recipient list | **yes** | the campaign analytics UI; routes `campaigns/:id/analytics/{metrics,contacts}` | **REWRITE** | git rename **R100** for the pre-edit move; 92%, 48/52 |
| `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | records recipients as a one-off WhatsApp campaign is sent | **yes** | the campaign run path; P8 | **REWRITE** | git rename R083; 96%, 64/67 |

### Family E — WhatsApp status and send extensions (2 files)

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb` | advances a campaign recipient when a Meta delivery-status webhook is processed | **yes** | Family D; P8 WhatsApp and campaign analytics | **REWRITE** | 100%, 10/10 |
| `custom/app/services/custom/whatsapp/providers/base_service.rb` | `enterprise/app/services/enterprise/whatsapp/providers/base_service.rb` | provider-side send behaviour the campaign path relies on | **yes** | Family D | **REWRITE** | 94%, 15/16. Copied **before** the Enterprise original was deleted |

### Family F — Audit writers found by the step-1 re-sweep (4 files)

These four were **missed by the provenance audit's first pass** and found by a systematic re-sweep run while this
register was being written (every current tracked file against all 848 files under `enterprise/` and
`spec/enterprise/` at the three pre-removal revisions, matched by basename and by normalised path). The first
pass had matched candidates differently and these fell outside it. Each one's own header comment already
described it as a port or a replacement of the pre-removal implementation, which is corroborating evidence
independent of the measurement.

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | `enterprise/app/controllers/enterprise/api/v1/accounts/conversations/messages_controller.rb` | writes the audit record when a message is deleted (capture point B13) | **yes** | the read surface; `auditlogHelper.js` `message:destroy` | **REWRITE** | 81%, 26/32 shared substantive lines @ `79ca68fb~1` |
| `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | `enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb` | writes the sign-in and sign-out audit records (B14) | **yes** | the read surface; `auditlogHelper.js` `user:sign_in` / `sign_out` | **REWRITE** | 74%, 28/38 @ `79ca68fb~1` |
| `custom/app/jobs/custom/delete_object_job.rb` | `enterprise/app/jobs/enterprise/delete_object_job.rb` | writes the audit record when the asynchronous deletion path destroys an inbox or conversation (B16) | **yes** | the read surface; the only writer of `inbox:destroy` | **REWRITE** | 65%, 11/17 @ `79ca68fb~1` |
| `custom/app/models/custom/channelable.rb` | `enterprise/app/models/enterprise/channelable.rb` | writes the audit record when a channel's configuration changes (B15) | **yes** | the read surface | **REWRITE** | 53%, 16/38 @ `79ca68fb~1`. Carries a Lynomia **security fix** the original did not have: channel credentials are redacted rather than recorded (see `specs/B-audit-event-capture.md` §5) |

### Family G — Declarations found by the sub-threshold sweep (4 files)

The two sweeps above narrow at **8 shared substantive lines**, which is deliberate — below that, two files can
coincide on language boilerplate alone. A third pass was therefore run at **3 shared lines and 50% overlap**,
producing 68 pairs. Sixty-four were boilerplate or already registered (§3); these four are real, and every one
of them is a declaration of one or two lines:

| current path | historical path | purpose | runtime required | dependents | action | evidence |
|---|---|---|---|---|---|---|
| `custom/app/models/custom/account_user.rb` | `enterprise/app/models/enterprise/account_user.rb` | **the integration point for role authorization**: a membership's capability list is its role's, else the built-in one | **yes** | all three capability policies, `_user.json.jbuilder`, `permissionsHelper.js` | **REWRITE (trivial)** | 60%, 3/5. The method body is **identical** — one line. This corrects an earlier claim that this file was original Lynomia work |
| `custom/app/models/custom/concerns/account_user.rb` | `enterprise/app/models/enterprise/concerns/account_user.rb` | declares that a membership may hold one role | **yes** | Family C throughout | **REWRITE (trivial)** | 67%, 4/6. One `belongs_to`; the Enterprise file declared a second association this product does not have |
| `custom/app/models/custom/concerns/account.rb` | `enterprise/app/models/enterprise/concerns/account.rb` | declares that an account owns the roles it defines | **yes** | Family C | **REWRITE (trivial)** | 67%, 4/6. One `has_many`; the Enterprise file declared nineteen more, none of them this product's |
| `custom/app/models/custom/channel/whatsapp.rb` | `enterprise/app/models/enterprise/channel/whatsapp.rb` | keeps the provider instance across a template send so the send error survives for the recipient record | **yes** | Family D, Family E | **REWRITE (trivial)** | 78%, 7/9. The method body is identical; the Enterprise file also mixed in a call-recording concern this product does not have |

All four are re-derivable from the schema (`account_users.custom_role_id`, `custom_roles.account_id`) and from
the behaviour package D §4.1 requires. They are registered because they exist, not because they are hard.

---

## 2. Specs — 12 files

Specs are not distributed in a Rails deployment, which changes the exposure but not the provenance. **None of
these may be shown to the clean-room implementer**, and none may be used as the basis for replacement specs
(`01-acceptance-test-plan.md` exists for that).

| current path | historical path | action | evidence |
|---|---|---|---|
| `spec/models/custom_role_spec.rb` | `spec/enterprise/models/custom_role_spec.rb` | **REMOVE; re-author from the acceptance plan** | byte-identical, 84% |
| `spec/jobs/campaigns/update_recipient_status_job_spec.rb` | `spec/enterprise/jobs/campaigns/update_recipient_status_job_spec.rb` | same | byte-identical, 91% |
| `spec/models/campaign_recipient_spec.rb` | `spec/enterprise/models/campaign_recipient_spec.rb` | same | byte-identical, 83% |
| `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | `spec/enterprise/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | same | 83% |
| `spec/services/custom/whatsapp/incoming_message_base_service_spec.rb` | `spec/enterprise/services/enterprise/whatsapp/incoming_message_base_service_spec.rb` | same | 88% |
| `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb` | `spec/enterprise/services/enterprise/whatsapp/oneoff_campaign_service_spec.rb` | same | 73% |
| `spec/controllers/custom/api/v1/accounts/agents_controller_spec.rb` | `spec/enterprise/controllers/enterprise/api/v1/accounts/agents_controller_spec.rb` | same | 78% |
| `spec/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | `spec/enterprise/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | same | 47% |
| `spec/policies/commerce/action_policy_custom_role_spec.rb` | `spec/enterprise/policies/commerce/action_policy_spec.rb` | same | git rename R62 |
| `spec/services/twilio/media_download_service_spec.rb` | `spec/enterprise/services/twilio/media_download_service_spec.rb` | ~~REMOVE; re-author~~ → **KEEP. This row was wrong** | 71% |
| `spec/controllers/api/v1/profiles_controller_spec.rb` | `spec/enterprise/controllers/api/v1/profiles_controller_spec.rb` | ~~REMOVE the Enterprise-derived portion~~ → **KEEP. This row was wrong** | 50% |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | `spec/enterprise/controllers/api/v1/accounts/contacts_controller_spec.rb` | same → **KEEP. This row was wrong** | 50% |

### The last three rows were a false positive, and the method that produced it

These three were removed with the rest on the strength of their similarity to a `spec/enterprise/` file, and
never re-authored — 1,825 lines of coverage for still-live production code, gone. The post-integration dead-code
audit found the gap, and checking it produced something more important than the gap itself.

**The arrow was pointing the wrong way.** All three sit at upstream OSS paths, and their history says they are
upstream Chatwoot files rather than Lynomia files that copied Enterprise ones:

| file | last commit before the removal | what that means |
|---|---|---|
| `spec/services/twilio/media_download_service_spec.rb` | Muhsin Keloth, upstream | never touched by this fork at all |
| `spec/controllers/api/v1/profiles_controller_spec.rb` | Shivam Mishra, upstream | never touched by this fork at all |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | this fork, on upstream OSS content | upstream file this fork later extended |

An upstream OSS file cannot be Enterprise-derived. Where an OSS spec and an Enterprise spec for the same
controller resemble each other, the derivation runs the other way, or both inherit the same upstream
boilerplate — which is exactly what the 50% figure and the register's own hedge ("may be shared boilerplate")
were saying. The sweep compared text and reported similarity; it had no notion of which side was the original.

All three are restored at `487276f2^`, unchanged, and **pass unchanged**: 137 examples, 0 failures, together
with the retained commerce policy spec. That they needed no edit is the second proof that they were never
coupled to the removed packages.

**The method correction, for anyone repeating this.** Textual similarity to an Enterprise file is not
provenance. Before classifying a file as Enterprise-derived, read its history: a file whose commits are
upstream authors' at an upstream path is upstream OSS, whatever it resembles. Applied to the 58 files this
removal deleted, that test flags exactly these three; the other 55 are Lynomia files under `custom/` and
`spec/**/custom/`, or specs of classes the removal deliberately retired, and none of them is at an upstream
OSS path. **The production removal is unaffected** — all 39 production files were under `custom/`.

`spec/policies/commerce/action_policy_custom_role_spec.rb` is a separate case and was correctly removed: it was
this fork's own spec, and the capability-gating cases it covered are now in
`spec/requests/custom_roles_spec.rb` under "C-10 each capability gates its own feature", which asserts the
holder, the non-holder, a holder of another capability, and that the capability never reaches a refund or a
cancellation. The retained policy spec's comment pointed at the deleted file and now points there instead.

---

## 3. Candidates examined and rejected

| candidate | why it is not affected |
|---|---|
| `app/views/devise/mailer/confirmation_instructions.html.erb` | upstream file on an MIT path, unchanged since production `b03ea43d`, last touched by an upstream author. Upstream kept a branded variant under `enterprise/`; the overlap is upstream's own duplication |
| `app/views/fields/count_field/_index.html.erb` and three sibling `_index.html.erb` partials | basename collision on a one-line Administrate partial |
| `custom/app/models/custom/audit/custom_filter.rb` | no Enterprise counterpart; original Lynomia work |
| `spec/jobs/internal/check_new_versions_job_spec.rb` | **false positive.** An Enterprise spec of the same basename existed, but this file is byte-identical to the OSS spec that sat beside it at `79ca68fb~1` and was last touched by an upstream author in 2024. The 8 shared lines are RSpec boilerplate |
| `custom/app/views/api/v1/accounts/support/sla_policies/{_sla_policy,index}.json.jbuilder` | the `sla_policies` table is an **upstream OSS table** present in the OSS schema before the removal (`79ca68fb~1:db/schema.rb:1661`), and `custom/app/models/support/sla_policy.rb` records the decision to reuse it. The shared lines are `json.<column> sla_policy.<column>` for that upstream table's own columns, plus the `json.payload do / json.array! / json.partial!` idiom that **57 files under `app/views` already use**. The current serializer also drops a column Enterprise emitted and adds two it did not. Disclosed rather than suppressed, for the engineering lead to overrule if they disagree |
| seven `index.json.jbuilder` files under `app/views/api/v1/accounts/` | the same three-line house idiom, matched against unrelated Enterprise index views (companies, captain inboxes, applied SLAs, reporting events) |
| seven `_form.html.erb` field partials under `app/views/fields/` and `custom/app/views/fields/` | four lines of Administrate form boilerplate, matched against one Enterprise field partial |
| `custom/app/models/custom/concerns/conversation.rb` | its one association (support cases) has no Enterprise counterpart; the three shared lines are `extend ActiveSupport::Concern`, `included do`, `end` |
| `app/actions/contact_merge_action.rb` | upstream MIT file; the Enterprise overlay of the same name added one method this product does not have. Three shared lines of module boilerplate |
| `spec/jobs/trigger_scheduled_items_job_spec.rb` | five shared lines: `require`, the `RSpec.describe` line naming the same OSS class, a `subject`, `described_class.perform_now`, `end` |
| the whole P8–P11 delta (50 commits, 440 files) | two independent scans found no `enterprise/` ancestry and no content match above threshold |

---

## 4. Totals

Every path in §1 was checked to exist on disk and the families were counted file by file: 2 + 13 + 10 + 4 + 2
+ 4 + 4 = **39**. (An earlier draft of this register stated 36 for families A–E; that was an arithmetic error
in the family subtotals, not a missing or an invented file. The corrected count is below.)

| | count |
|---|---|
| production files needing an independent implementation | **39** |
| of which substantial (≥10 shared substantive lines) | 18 |
| of which trivial declarations or one-line views | 21 |
| specs to remove and re-author | **12** |
| features that may simply be removed instead | **0** — see `04-integration-contract.md` §6 |
| candidates examined and rejected | 11 groups |
