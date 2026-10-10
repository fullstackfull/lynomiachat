# P-FINAL.2 / .44 — Code provenance audit

> **This document records technical provenance findings and risk classifications only.** It does not state a
> legal conclusion. It does not say that anything here is cleared, safe or unsafe to distribute. Whether any
> finding has legal effect — including whether the namespace changes, comment headers or behavioural edits
> matter under the terms quoted in §1 — is a question for qualified counsel, which is outside a repository
> audit. Where the technical question cannot be settled from the repository, the row says
> `LEGAL REVIEW REQUIRED` rather than guessing.

---

## 1. The two licences this audit turns on

Both are quoted from this repository, not from memory.

**`LICENSE` (repository root, present today):**

> Portions of this software are licensed as follows:
> * All content that resides under the "enterprise/" directory of this repository, **if that directory exists**,
>   is licensed under the license defined in "enterprise/LICENSE".
> * All third party components incorporated into the Chatwoot Software are licensed under the original license
>   provided by the owner of the applicable component.
> * Content outside of the above mentioned directories or restrictions above is available under the
>   **"MIT Expat"** license as defined below.

**`enterprise/LICENSE`, as it stood at `79ca68fb~1`** (`git show 79ca68fb~1:enterprise/LICENSE`) — the Chatwoot
Enterprise License, Copyright (c) 2017-2026 Chatwoot Inc:

> This software and associated documentation files (the "Software") may only be used in production, if you (and
> any entity that you represent) have agreed to, and are in compliance with, the Chatwoot Subscription Terms of
> Service … and otherwise have a valid Chatwoot Enterprise License for the correct number of user seats. …
> Notwithstanding the foregoing, **you may copy and modify the Software for development and testing purposes,
> without requiring a subscription.** … You are not granted any other rights beyond what is expressly stated
> herein. Subject to the foregoing, **it is forbidden to copy, merge, publish, distribute, sublicense, and/or
> sell the Software.**

So the governing question for every row below is factual and narrow: **did this file's content come from under
`enterprise/`?** The MIT grant covers everything else in the tree, including every file that only ever lived
under `app/`, `lib/`, `custom/` or `spec/`.

Two consequences of the root LICENSE's own wording are worth stating because they cut in opposite directions:

- The clause is conditional — *"if that directory exists"*. The directory does not exist in this tree.
- The Enterprise text's own carve-out permits copying and modification **for development and testing**. What it
  forbids is publishing, distributing and selling. A commercial release is exactly the forbidden column.

---

## 2. Method

Four independent passes, each repeatable:

1. **Git-recorded renames.** `git log --all -M --find-renames=40% --diff-filter=R --name-status` over the whole
   history, filtered to renames whose SOURCE path is `enterprise/` or `spec/enterprise/`. Rename detection is
   git's own, not a similarity heuristic of mine; the same rows appear at `--find-renames=25%` and `=50%`.
2. **Content overlap against three pre-relocation revisions.** For every tracked file under `custom/`, `app/`,
   `lib/` and `spec/`, compared by basename against every file under `enterprise/` and `spec/enterprise/` as
   those trees stood at `79ca68fb~1`, `fbc485a8~1` and `92211aba~1` — three revisions, because two relocations
   happened **before** the formal removal commit and are invisible to a sweep of the removal window alone.
   Comparison is on substantive lines (comments and `end`/`private`/brace-only lines stripped) with
   `Enterprise::` normalised to `Custom::`, so a namespace change does not hide a copy.
3. **Byte-identity check** on every candidate: is the current file byte-for-byte the Enterprise original?
4. **Per-file diff reading** on the material rows, to see *what* the difference consists of — a rewrite, or a
   header and a namespace.

Scale: 541 files existed under `enterprise/` at `79ca68fb~1`; 8,212 current tracked files were compared.

### Chronology, which matters

| commit | date | what it did |
|---|---|---|
| `fbc485a8` | 2026-10-07 | moved the Custom Roles subsystem out of `enterprise/` (14 git-recorded renames) |
| `92211aba` | 2026-10-07 | moved WhatsApp Campaign Recipients out of `enterprise/` (9 git-recorded renames) |
| `1e4a7250` | 2026-10-07 | moved `process_statuses` out of `enterprise/` into a new `custom/` file |
| `8f3a7891` | 2026-10-07 | brought the audit-log reader back (controller + view) |
| `dfc8bf6e` | 2026-10-07 | brought the sign-in / sign-out audit writer back |
| **`79ca68fb`** | **2026-10-07** | **"remove Chatwoot Enterprise from the codebase"** |
| `b9922355` | 2026-10-08 | brought three more audit writers back |

`git merge-base --is-ancestor fbc485a8 79ca68fb` → **true**. Three of the relocations therefore precede the
removal they are nominally part of, which is why a review keyed on the removal commit — or on the brief's
15-commit list, which omits `fbc485a8` and `92211aba` — understates the set.

---

## 3. What the sweep found

| classification | files | meaning |
|---|---|---|
| **TIER 1 — Enterprise-derived, high confidence** | 11 code files | byte-identical, or ≥90% of substantive lines shared with ≥15 lines in common, with the prior path under `enterprise/` |
| **TIER 2 — Enterprise-derived, partially modified** | 6 code files | 50-90% overlap with ≥10 shared lines; the difference is removal or a narrowing, not reimplementation |
| **TIER 3 — Enterprise-derived but structurally trivial** | 7 code files | git records an R100 rename out of `enterprise/`, but the file is 1-7 substantive lines of framework boilerplate (`json.partial!`, a one-line Administrate partial, an `audited` declaration) where any implementation converges |
| **TIER 4 — specs** | 12 spec files | moved from `spec/enterprise/`, or carrying Enterprise spec content |
| **NOT derived** | 5 candidates | basename collisions on framework boilerplate, and one upstream file |

### TIER 1 — Enterprise-derived, high confidence

| current path | overlap | shared/total | byte-identical | what the difference is |
|---|---|---|---|---|
| `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | **100%** | 24/24 | no | a 13-line Lynomia comment header; `Enterprise::`→`Custom::`. Verified: namespace-normalised `diff -u` yields exactly one hunk, the header |
| `custom/app/models/custom_role.rb` | **100%** | 31/31 | no | git records R091 |
| `custom/app/jobs/campaigns/update_recipient_status_job.rb` | **100%** | 11/11 | **yes** | nothing |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | **100%** | 10/10 | no | relocated by `1e4a7250`, which added a file and so shows as no rename |
| `custom/app/models/custom/audit/inbox_member.rb` | **100%** | 18/18 | no | namespace only |
| `custom/app/models/custom/audit/team_member.rb` | **100%** | 18/18 | no | namespace only |
| `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | 96% | 64/67 | no | git records R083 |
| `custom/app/models/campaign_recipient.rb` | 96% | 54/56 | no | git records R081 |
| `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | 96% | 25/26 | no | **one line removed** (`json.location`). Verified: `diff -u` produces a single one-line hunk |
| `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | 92% | 48/52 | no | git records R100 for the pre-edit move |
| `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` | 95% | 19/20 | no | git records R070 |

### TIER 2 — Enterprise-derived, partially modified

| current path | overlap | shared/total | what Lynomia actually changed |
|---|---|---|---|
| `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` | 90% | 36/40 | superclass `EnterpriseAccountsController`→`BaseController`, one helper inlined, a comment header. Verified: three hunks, no reimplementation |
| `custom/app/services/custom/whatsapp/providers/base_service.rb` | 94% | 15/16 | copied **before** the original was deleted, so invisible to the removal window |
| `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` | 82% | 9/11 | git records R073 |
| `custom/app/jobs/custom/delete_object_job.rb` | 69% | 11/16 | `SlaPolicy` dropped from the type list; the list extracted to a constant |
| `custom/app/models/custom/channelable.rb` | 67% | 16/24 | **mixed provenance.** The audit-row skeleton and the template-update suppression rule (including a StackOverflow citation comment) are carried over; the credential-redaction half (`FILTERED`, `CREDENTIAL_BLOBS`, `filter_credentials`) is genuine Lynomia work and a real security improvement |
| `custom/app/models/custom/audit_log.rb` | 57% | 20/35 | `log_additional_information`, `masked_remote_address` and four read scopes carried over into a file that already existed; the IP-geolocation hook deliberately dropped; the polymorphic-actor fix is Lynomia's |
| `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | 57% | 28/49 | `audit_event_rows` carried over verbatim apart from the namespace; the SAML guard and IP-lookup enqueue removed |

### TIER 3 — Enterprise-derived but structurally trivial

`custom/app/policies/custom_role_policy.rb` (byte-identical, 7 substantive lines),
`custom/app/views/api/v1/models/_custom_role.json.jbuilder` (byte-identical, 6 lines),
`custom/app/views/api/v1/models/_account_user.json.jbuilder` (byte-identical, 2 lines),
`custom/app/views/api/v1/accounts/custom_roles/{index,create,show,update}.json.jbuilder` (byte-identical, 1-2
lines each — `json.partial!` calls).

These are recorded because git records an R100 rename out of `enterprise/`, and omitted from TIER 1 because a
one-line `json.partial!` has no authorship to speak of: any implementation of "render this partial" is the same
text. The distinction matters for remediation effort, not for the inventory.

### TIER 4 — specs moved out of `spec/enterprise/`

| current path | overlap | byte-identical |
|---|---|---|
| `spec/models/custom_role_spec.rb` | 84% | **yes** |
| `spec/jobs/campaigns/update_recipient_status_job_spec.rb` | 91% | **yes** |
| `spec/models/campaign_recipient_spec.rb` | 83% | **yes** |
| `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | 83% | no |
| `spec/services/custom/whatsapp/incoming_message_base_service_spec.rb` | 88% | no |
| `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb` | 73% | no |
| `spec/controllers/custom/api/v1/accounts/agents_controller_spec.rb` | 78% | no |
| `spec/services/twilio/media_download_service_spec.rb` | 71% | no |
| `spec/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | 47% | no |
| `spec/policies/commerce/action_policy_custom_role_spec.rb` | R62 rename | no |
| `spec/controllers/api/v1/{profiles_controller,accounts/contacts_controller}_spec.rb` | 45-50%, 8-14 lines | no — lower confidence, may be shared boilerplate |

Specs are not shipped to customers in a Rails deployment, which changes the exposure but not the provenance.

### NOT derived — candidates the sweep raised and this audit rejects

| candidate | why it is not evidence |
|---|---|
| `app/views/devise/mailer/confirmation_instructions.html.erb` (66%, 58 lines) | an **upstream** file on an MIT path, unchanged since production `b03ea43d`, last touched by an upstream author (`34892987`, Shivam Mishra). Upstream itself kept a branded variant under `enterprise/`; the overlap is upstream's own duplication |
| `app/views/fields/count_field/_index.html.erb` and three sibling `_index.html.erb` partials (1/1 line) | basename collision on a one-line Administrate partial. Not copying |

---

## 4. The one fact that forces these classifications

Every file above arrived in this repository **under `enterprise/`**, authored upstream, before any Lynomia
commit touched it. That is not an inference from similarity; it is established three ways:

1. `git log --all --author=Claude --diff-filter=A -- 'enterprise/*'` is **empty**. No Lynomia commit ever added
   a file under `enterprise/`, so no relocation can be explained as Lynomia repatriating its own work.
2. `git blame` on the Enterprise originals attributes them to upstream authors and upstream pull requests
   (e.g. `channelable.rb` → Tanmay Deep Sharma, "feat: enable assignment v2 by default for new accounts
   (#14031)"; `delete_object_job.rb` → Aakash Bakhle, "fix: captain template message conflict (#13048)").
3. At every shallow boundary commit in this clone, `custom/` holds **zero** files.

Renaming `Enterprise::` to `Custom::`, adding a comment header that explains the relocation, and deleting a
line or a method are the changes actually present. Whether that is sufficient under the Enterprise terms is not
a question this document answers.

---

## 5. Per-file report in the format P-FINAL.44 asks for

`ACTION` below is the **technical** action this audit recommends, not a legal determination.

| path | current purpose | origin commit | origin classification | upstream relation | licence basis as it stands | ACTION |
|---|---|---|---|---|---|---|
| `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` | server side of Settings → Audit Logs | `8f3a7891` | POTENTIAL ENTERPRISE-DERIVED | was `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb` | Enterprise License at origin | LEGAL REVIEW REQUIRED, then REWRITE or REMOVE |
| `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | its JSON view | `8f3a7891` | POTENTIAL ENTERPRISE-DERIVED | same subsystem | same | LEGAL REVIEW REQUIRED, then REWRITE or REMOVE |
| `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | audit row on message delete | `b9922355` | POTENTIAL ENTERPRISE-DERIVED | was `enterprise/.../messages_controller.rb` | same | LEGAL REVIEW REQUIRED, then REWRITE |
| `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | sign-in / sign-out audit rows | `dfc8bf6e` | POTENTIAL ENTERPRISE-DERIVED | was `enterprise/.../sessions_controller.rb` | same | LEGAL REVIEW REQUIRED, then REWRITE |
| `custom/app/jobs/custom/delete_object_job.rb` | destroy audit row | `b9922355` | POTENTIAL ENTERPRISE-DERIVED | was `enterprise/app/jobs/enterprise/delete_object_job.rb` | same | LEGAL REVIEW REQUIRED, then REWRITE |
| `custom/app/models/custom/channelable.rb` | channel audit row + credential redaction | `b9922355` | MIXED (Enterprise skeleton + original Lynomia security work) | was `enterprise/app/models/enterprise/channelable.rb` | same for the carried part | LEGAL REVIEW REQUIRED for the skeleton; the redaction half is Lynomia's |
| `custom/app/models/custom/audit_log.rb` | the audit model | pre-existing, extended by `8f3a7891` | MIXED | partly `enterprise/app/models/enterprise/audit_log.rb` | same for the carried part | LEGAL REVIEW REQUIRED |
| `custom/app/models/custom/audit/{inbox_member,team_member}.rb` + 10 siblings | `audited` declarations | `79ca68fb` era | POTENTIAL ENTERPRISE-DERIVED (trivial) | `enterprise/app/models/enterprise/audit/*` | same | LEGAL REVIEW REQUIRED; trivial to re-derive from the schema |
| `custom/app/models/custom_role.rb`, `custom/app/policies/custom_role_policy.rb`, `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb`, `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb`, 6 custom-role views | Custom Roles — the permission system Commerce's order-management role depends on | `fbc485a8` | POTENTIAL ENTERPRISE-DERIVED | git-recorded renames R070-R100 | same | LEGAL REVIEW REQUIRED, then REWRITE or REMOVE |
| `custom/app/models/campaign_recipient.rb`, `custom/app/jobs/campaigns/update_recipient_status_job.rb`, `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb`, `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | WhatsApp campaign recipient tracking and its analytics | `92211aba` | POTENTIAL ENTERPRISE-DERIVED | git-recorded renames R081-R100 | same | LEGAL REVIEW REQUIRED, then REWRITE or REMOVE |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`, `custom/app/services/custom/whatsapp/providers/base_service.rb` | inbound WhatsApp status processing | `1e4a7250`, pre-`fbc485a8` | POTENTIAL ENTERPRISE-DERIVED | `enterprise/app/services/enterprise/whatsapp/*` | same | LEGAL REVIEW REQUIRED, then REWRITE |
| 12 spec files under `spec/` | tests for the above | `fbc485a8`, `92211aba`, removal era | POTENTIAL ENTERPRISE-DERIVED | `spec/enterprise/*` | same | LEGAL REVIEW REQUIRED; not distributed in a Rails deploy |
| everything else in the P8-P11 delta | analytics, support cases, operations, identity, billing | the 50 commits in `01-changeset-inventory.md` | **ORIGINAL LYNOMIA** | no `enterprise/` ancestry; no basename or content match above threshold | MIT (root LICENSE) | KEEP |

---

## 6. Why this audit did not simply rewrite the affected files

P-FINAL.3 requires an **independent clean implementation** from the product requirement, the OSS interfaces, the
schema and the specs — explicitly *not* a rename or a reformat. Two things stand in the way of doing that inside
this phase, and both are stated rather than worked around:

1. **This audit is no longer a clean-room implementer.** Establishing the findings required reading the
   Enterprise originals line by line and diffing them. Anything written afterwards by the same author, however
   carefully, is a derivative in substance even if the text differs — and the brief's own words are "do not
   simply rename/reformat it". A credible independent implementation has to be produced by someone who has not
   read the original, working from the requirement, the schema and the specs. That is a procedure the project
   can run; it is not something this audit can perform on itself after the fact.
2. **The scope and the right answer depend on a business fact this repository does not contain.** The Enterprise
   terms permit use with a valid Chatwoot Enterprise subscription. Whether Lynomia holds one, or intends to,
   decides whether anything needs doing at all — and if not, whether each subsystem should be rewritten, removed
   or replaced by its OSS equivalent. Rewriting 17 code files and 12 specs before that is answered risks
   discarding working, tested code for nothing, and risks removing features (Custom Roles, campaign recipient
   tracking, the audit log) that other parts of this product now depend on.

What this phase did instead: establish the inventory to file-level precision, classify every row with
repeatable evidence, say plainly which rows are trivial and which are substantial, and raise it as a release
blocker with the decision stated — `docs/p-final/P_FINAL_BLOCKER_REPORT.md`.

---

## 7. Residual uncertainty, stated rather than hidden

1. **The clone is shallow.** `.git/shallow` holds 31 boundary commits and several report no parents, so history
   earlier than those boundaries could not be walked, and upstream's own objects were not fetched to confirm the
   boundary SHAs. The conclusion that `enterprise/` content is upstream-authored rests on in-repo evidence
   (upstream author and committer metadata including PR numbers, zero `custom/` files at every boundary, and no
   Lynomia-authored addition under `enterprise/`) rather than on an external comparison.
2. **The sweep is basename-anchored.** A file copied out of `enterprise/` and renamed to a different basename,
   or rewritten below the 40% threshold, would not appear. The git-recorded renames in §2 pass 1 are
   threshold-independent; the overlap sweep is not.
3. **Non-Ruby copies were not swept.** The comparison covered `.rb`, `.jbuilder` and `.erb`. About 30 `.vue`,
   `.js`, `.liquid` and `.yml` files existed under `enterprise/`; the commits that removed Enterprise-gated
   frontend code added no files, so nothing entered the tree through them, but a copy made outside those
   commits would not have been caught. This is the main remaining gap.
4. **Whether any relocated text predates Chatwoot itself** cannot be distinguished for files whose blame is
   entirely a shallow boundary. No sign of a third-party licence header was found in any of them.
5. **No legal conclusion is drawn anywhere in this document.**

---

## Appendix A — the raw sweep output

Every pair the sweep returned, unfiltered, so the classification above can be checked against it. "byte-identical"
compares the current file with the Enterprise original as it stood at the revision named.

| current path | overlap | shared/total lines | byte-identical | enterprise original | seen at |
|---|---|---|---|---|---|
| `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` | 96% | 64/67 | no | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | `92211aba~1` |
| `app/views/devise/mailer/confirmation_instructions.html.erb` | 66% | 58/88 | no | `enterprise/app/views/devise/mailer/confirmation_instructions.html.erb` | `79ca68fb~1` |
| `custom/app/models/campaign_recipient.rb` | 96% | 54/56 | no | `enterprise/app/models/campaign_recipient.rb` | `92211aba~1` |
| `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | 92% | 48/52 | no | `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | `92211aba~1` |
| `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` | 90% | 36/40 | no | `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb` | `79ca68fb~1` |
| `custom/app/models/custom_role.rb` | 100% | 31/31 | no | `enterprise/app/models/custom_role.rb` | `fbc485a8~1` |
| `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | 57% | 28/49 | no | `enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb` | `79ca68fb~1` |
| `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | 96% | 25/26 | no | `enterprise/app/views/api/v1/accounts/audit_logs/show.json.jbuilder` | `79ca68fb~1` |
| `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | 100% | 24/24 | no | `enterprise/app/controllers/enterprise/api/v1/accounts/conversations/messages_controller.rb` | `79ca68fb~1` |
| `custom/app/models/custom/audit_log.rb` | 57% | 20/35 | no | `enterprise/app/models/enterprise/audit_log.rb` | `79ca68fb~1` |
| `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` | 95% | 19/20 | no | `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` | `fbc485a8~1` |
| `custom/app/models/custom/audit/inbox_member.rb` | 100% | 18/18 | no | `enterprise/app/models/enterprise/audit/inbox_member.rb` | `79ca68fb~1` |
| `custom/app/models/custom/audit/team_member.rb` | 100% | 18/18 | no | `enterprise/app/models/enterprise/audit/team_member.rb` | `79ca68fb~1` |
| `custom/app/models/custom/channelable.rb` | 67% | 16/24 | no | `enterprise/app/models/enterprise/channelable.rb` | `79ca68fb~1` |
| `custom/app/services/custom/whatsapp/providers/base_service.rb` | 94% | 15/16 | no | `enterprise/app/services/enterprise/whatsapp/providers/base_service.rb` | `fbc485a8~1` |
| `custom/app/jobs/custom/delete_object_job.rb` | 69% | 11/16 | no | `enterprise/app/jobs/enterprise/delete_object_job.rb` | `79ca68fb~1` |
| `custom/app/jobs/campaigns/update_recipient_status_job.rb` | 100% | 11/11 | **yes** | `enterprise/app/jobs/campaigns/update_recipient_status_job.rb` | `92211aba~1` |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | 100% | 10/10 | no | `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb` | `fbc485a8~1` |
| `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` | 82% | 9/11 | no | `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` | `fbc485a8~1` |
| `custom/app/policies/custom_role_policy.rb` | 64% | 7/11 | **yes** | `enterprise/app/policies/custom_role_policy.rb` | `fbc485a8~1` |
| `custom/app/views/api/v1/models/_custom_role.json.jbuilder` | 100% | 6/6 | **yes** | `enterprise/app/views/api/v1/models/_custom_role.json.jbuilder` | `fbc485a8~1` |
| `custom/app/views/api/v1/accounts/custom_roles/index.json.jbuilder` | 100% | 2/2 | **yes** | `enterprise/app/views/api/v1/accounts/custom_roles/index.json.jbuilder` | `fbc485a8~1` |
| `custom/app/views/api/v1/models/_account_user.json.jbuilder` | 100% | 2/2 | **yes** | `enterprise/app/views/api/v1/models/_account_user.json.jbuilder` | `fbc485a8~1` |
| `app/views/fields/count_field/_index.html.erb` | 100% | 1/1 | **yes** | `enterprise/app/views/fields/account_limits_field/_index.html.erb` | `79ca68fb~1` |
| `custom/app/views/fields/article_author_field/_index.html.erb` | 100% | 1/1 | **yes** | `enterprise/app/views/fields/account_limits_field/_index.html.erb` | `79ca68fb~1` |
| `custom/app/views/fields/article_meta_field/_index.html.erb` | 100% | 1/1 | **yes** | `enterprise/app/views/fields/account_limits_field/_index.html.erb` | `79ca68fb~1` |
| `custom/app/views/fields/billing_plan_limits_field/_index.html.erb` | 100% | 1/1 | **yes** | `enterprise/app/views/fields/account_limits_field/_index.html.erb` | `79ca68fb~1` |
| `custom/app/views/api/v1/accounts/custom_roles/create.json.jbuilder` | 100% | 1/1 | **yes** | `enterprise/app/views/api/v1/accounts/custom_roles/create.json.jbuilder` | `fbc485a8~1` |
| `custom/app/views/api/v1/accounts/custom_roles/show.json.jbuilder` | 100% | 1/1 | **yes** | `enterprise/app/views/api/v1/accounts/custom_roles/show.json.jbuilder` | `fbc485a8~1` |
| `custom/app/views/api/v1/accounts/custom_roles/update.json.jbuilder` | 100% | 1/1 | **yes** | `enterprise/app/views/api/v1/accounts/custom_roles/update.json.jbuilder` | `fbc485a8~1` |
| `spec/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | 47% | 48/103 | no | `spec/enterprise/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | `fbc485a8~1` |
| `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | 83% | 43/52 | no | `spec/enterprise/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | `92211aba~1` |
| `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb` | 73% | 38/52 | no | `spec/enterprise/services/enterprise/whatsapp/oneoff_campaign_service_spec.rb` | `92211aba~1` |
| `spec/models/custom_role_spec.rb` | 84% | 31/37 | **yes** | `spec/enterprise/models/custom_role_spec.rb` | `fbc485a8~1` |
| `spec/jobs/campaigns/update_recipient_status_job_spec.rb` | 91% | 31/34 | **yes** | `spec/enterprise/jobs/campaigns/update_recipient_status_job_spec.rb` | `92211aba~1` |
| `spec/models/campaign_recipient_spec.rb` | 83% | 30/36 | **yes** | `spec/enterprise/models/campaign_recipient_spec.rb` | `92211aba~1` |
| `spec/controllers/custom/api/v1/accounts/agents_controller_spec.rb` | 78% | 29/37 | no | `spec/enterprise/controllers/enterprise/api/v1/accounts/agents_controller_spec.rb` | `fbc485a8~1` |
| `spec/services/custom/whatsapp/incoming_message_base_service_spec.rb` | 88% | 28/32 | no | `spec/enterprise/services/enterprise/whatsapp/incoming_message_base_service_spec.rb` | `92211aba~1` |
| `spec/services/twilio/media_download_service_spec.rb` | 71% | 22/31 | no | `spec/enterprise/services/twilio/media_download_service_spec.rb` | `79ca68fb~1` |
| `spec/controllers/api/v1/accounts/articles/bulk_actions_controller_spec.rb` | 45% | 14/31 | no | `spec/enterprise/controllers/enterprise/api/v1/accounts/articles/bulk_actions_controller_spec.rb` | `79ca68fb~1` |
| `spec/controllers/api/v1/profiles_controller_spec.rb` | 50% | 9/18 | no | `spec/enterprise/controllers/api/v1/profiles_controller_spec.rb` | `79ca68fb~1` |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | 50% | 8/16 | no | `spec/enterprise/controllers/api/v1/accounts/contacts_controller_spec.rb` | `79ca68fb~1` |

rows: 42  (code: 30, spec: 12)

### git-recorded renames out of enterprise/ by Lynomia commits

| commit | similarity | from | to |
|---|---|---|---|
| `92211aba` | R100 | `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` |
| `92211aba` | R100 | `enterprise/app/jobs/campaigns/update_recipient_status_job.rb` | `custom/app/jobs/campaigns/update_recipient_status_job.rb` |
| `92211aba` | R100 | `spec/enterprise/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` |
| `92211aba` | R100 | `spec/enterprise/jobs/campaigns/update_recipient_status_job_spec.rb` | `spec/jobs/campaigns/update_recipient_status_job_spec.rb` |
| `92211aba` | R100 | `spec/enterprise/models/campaign_recipient_spec.rb` | `spec/models/campaign_recipient_spec.rb` |
| `92211aba` | R97 | `spec/enterprise/services/enterprise/whatsapp/oneoff_campaign_service_spec.rb` | `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb` |
| `92211aba` | R95 | `spec/enterprise/services/enterprise/whatsapp/incoming_message_base_service_spec.rb` | `spec/services/custom/whatsapp/incoming_message_base_service_spec.rb` |
| `92211aba` | R83 | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` |
| `92211aba` | R81 | `enterprise/app/models/campaign_recipient.rb` | `custom/app/models/campaign_recipient.rb` |
| `fbc485a8` | R100 | `enterprise/app/policies/custom_role_policy.rb` | `custom/app/policies/custom_role_policy.rb` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/accounts/custom_roles/create.json.jbuilder` | `custom/app/views/api/v1/accounts/custom_roles/create.json.jbuilder` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/accounts/custom_roles/index.json.jbuilder` | `custom/app/views/api/v1/accounts/custom_roles/index.json.jbuilder` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/accounts/custom_roles/show.json.jbuilder` | `custom/app/views/api/v1/accounts/custom_roles/show.json.jbuilder` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/accounts/custom_roles/update.json.jbuilder` | `custom/app/views/api/v1/accounts/custom_roles/update.json.jbuilder` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/models/_account_user.json.jbuilder` | `custom/app/views/api/v1/models/_account_user.json.jbuilder` |
| `fbc485a8` | R100 | `enterprise/app/views/api/v1/models/_custom_role.json.jbuilder` | `custom/app/views/api/v1/models/_custom_role.json.jbuilder` |
| `fbc485a8` | R100 | `spec/enterprise/controllers/api/v1/accounts/custom_roles_controller_spec.rb` | `spec/controllers/api/v1/accounts/custom_roles_controller_spec.rb` |
| `fbc485a8` | R100 | `spec/enterprise/models/custom_role_spec.rb` | `spec/models/custom_role_spec.rb` |
| `fbc485a8` | R97 | `spec/enterprise/controllers/enterprise/api/v1/accounts/agents_controller_spec.rb` | `spec/controllers/custom/api/v1/accounts/agents_controller_spec.rb` |
| `fbc485a8` | R91 | `enterprise/app/models/custom_role.rb` | `custom/app/models/custom_role.rb` |
| `fbc485a8` | R73 | `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` | `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` |
| `fbc485a8` | R70 | `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` | `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` |
| `fbc485a8` | R62 | `spec/enterprise/policies/commerce/action_policy_spec.rb` | `spec/policies/commerce/action_policy_custom_role_spec.rb` |

rename rows: 23

### Reproducing this

```
# pass 1: git-recorded renames out of enterprise/
git log --all -M --find-renames=40% --diff-filter=R --format=%h --name-status \
  | awk "/^R[0-9]+\tenterprise\//"

# pass 2/3: content overlap and byte-identity against the three pre-relocation revisions
#   79ca68fb~1 (before the removal), fbc485a8~1 (before the custom-role move),
#   92211aba~1 (before the campaign-recipient move)
# the script is in the P-FINAL completion material; it strips comments and
# end/private/brace-only lines, normalises Enterprise:: to Custom::, and reports
# shared substantive lines as a fraction of the enterprise side.
```
