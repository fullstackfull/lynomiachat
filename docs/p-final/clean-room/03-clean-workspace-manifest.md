# Clean workspace manifest

**Audience: the engineering lead preparing the clean-room workspace.** This document is the recipe for the
sanitized export and is deliberately **not** part of it.

The sanitized workspace was built at **`/tmp/lynomia-cleanroom-source`**. This manifest states exactly what was
removed and why, so the build can be reproduced or audited.

Three different reasons for removal are kept apart, because they are not the same thing:

| reason | meaning |
|---|---|
| **PROVENANCE** | the file is Enterprise-derived (`00-affected-files.md`) and must not be seen or reused |
| **COUPLING** | the file is clean in itself, but its subject under test is a PROVENANCE file, so it cannot run and could carry that implementation's shape |
| **HYGIENE** | history, build output, logs, caches, environment files — removed because an export should not carry them, not because of provenance |

---

## 1. Removed for PROVENANCE — production code (39 files)

The complete list. Every path was confirmed to exist before removal.

### Audit trail — read surface (2)

- `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb`
- `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder`

### Audit trail — record and event registration (13)

- `custom/app/models/custom/audit_log.rb`
- `custom/app/models/custom/audit/account.rb`
- `custom/app/models/custom/audit/account_user.rb`
- `custom/app/models/custom/audit/agent_bot.rb`
- `custom/app/models/custom/audit/automation_rule.rb`
- `custom/app/models/custom/audit/conversation.rb`
- `custom/app/models/custom/audit/inbox.rb`
- `custom/app/models/custom/audit/inbox_member.rb`
- `custom/app/models/custom/audit/macro.rb`
- `custom/app/models/custom/audit/team.rb`
- `custom/app/models/custom/audit/team_member.rb`
- `custom/app/models/custom/audit/webhook.rb`
- `custom/app/models/custom/campaign.rb`

### Named permission sets (10)

- `custom/app/models/custom_role.rb`
- `custom/app/policies/custom_role_policy.rb`
- `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb`
- `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb`
- `custom/app/views/api/v1/accounts/custom_roles/index.json.jbuilder`
- `custom/app/views/api/v1/accounts/custom_roles/create.json.jbuilder`
- `custom/app/views/api/v1/accounts/custom_roles/show.json.jbuilder`
- `custom/app/views/api/v1/accounts/custom_roles/update.json.jbuilder`
- `custom/app/views/api/v1/models/_custom_role.json.jbuilder`
- `custom/app/views/api/v1/models/_account_user.json.jbuilder`

### Campaign recipient tracking (4)

- `custom/app/models/campaign_recipient.rb`
- `custom/app/jobs/campaigns/update_recipient_status_job.rb`
- `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb`
- `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`

### WhatsApp status and send extensions (2)

- `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`
- `custom/app/services/custom/whatsapp/providers/base_service.rb`

### Audit writers found by the re-sweep (4)

- `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb`
- `custom/app/controllers/custom/devise_overrides/sessions_controller.rb`
- `custom/app/jobs/custom/delete_object_job.rb`
- `custom/app/models/custom/channelable.rb`

### Declarations found by the sub-threshold sweep (4)

- `custom/app/models/custom/account_user.rb`
- `custom/app/models/custom/concerns/account_user.rb`
- `custom/app/models/custom/concerns/account.rb`
- `custom/app/models/custom/channel/whatsapp.rb`

Three of these directories become empty once their files go and are removed with them:
`custom/app/models/custom/audit/` keeps only `custom_filter.rb` (clean, retained),
`custom/app/views/api/v1/accounts/custom_roles/` and `custom/app/views/api/v1/accounts/audit_logs/` are emptied
entirely, as is `custom/app/views/api/v1/models/`.

---

## 2. Removed for PROVENANCE — specs (12 files)

These are the twelve Enterprise-derived specs. **None may be shown to the clean-room implementer, and none may
be used as the basis for a replacement spec.** `01-acceptance-test-plan.md` exists for that purpose.

- `spec/models/custom_role_spec.rb`
- `spec/controllers/api/v1/accounts/custom_roles_controller_spec.rb`
- `spec/controllers/custom/api/v1/accounts/agents_controller_spec.rb`
- `spec/policies/commerce/action_policy_custom_role_spec.rb`
- `spec/models/campaign_recipient_spec.rb`
- `spec/jobs/campaigns/update_recipient_status_job_spec.rb`
- `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb`
- `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb`
- `spec/services/custom/whatsapp/incoming_message_base_service_spec.rb`
- `spec/services/twilio/media_download_service_spec.rb`
- `spec/controllers/api/v1/profiles_controller_spec.rb`
- `spec/controllers/api/v1/accounts/contacts_controller_spec.rb`

The last three of those test **clean** code — only the test text is affected. Their subject matter is covered
by the acceptance plan, so the behaviour is not lost, only the text.

---

## 3. Removed for COUPLING — specs (7 files)

Each of these is clean-authored Lynomia work whose **subject under test is a PROVENANCE file above**. They
cannot load without the replacement and they encode the removed implementation's shape, so they go too. They
are listed separately because the reason is different: nothing about their own authorship is in question.

- `spec/models/custom/audit_log_spec.rb`
- `spec/models/custom/audit/conversation_spec.rb`
- `spec/models/custom/channelable_audit_spec.rb`
- `spec/jobs/custom/delete_object_job_audit_spec.rb`
- `spec/controllers/custom/devise_overrides/sessions_controller_spec.rb`
- `spec/controllers/custom/api/v1/accounts/conversations/messages_controller_audit_spec.rb`
- `spec/requests/custom/audit_log_reader_spec.rb`

**Specs deliberately NOT removed**, although they exercise the rewritten code: about thirty clean specs create
a permission set, a campaign recipient or an audit record in order to test something else — the P8 campaign
metrics service, the Commerce and Support policies, P10 contact merge, P11 billing, the analytics tenant
isolation suite. They test clean subjects and they are the implementer's regression net. Expect them to **fail
until the rewrite lands**: that is the intended signal, and `spec/services/analytics/campaigns/metrics_spec.rb`
in particular is the sharpest statement of package D's contract that exists in executable form.

---

## 4. Removed for PROVENANCE — documents

| path | why |
|---|---|
| `docs/enterprise-audit/` (4 files) | the subject of these documents is the Enterprise overlay: what depended on it, and how it was removed. They cite its paths throughout |
| `docs/p-final/04-code-provenance.md` | the provenance audit itself: measurements, diffs, git rename records and the licence analysis |
| `docs/p-final/P_FINAL_BLOCKER_REPORT.md` | quotes the Enterprise licence and names the affected files |
| `docs/p-final/clean-room/00-affected-files.md` | the affected-file register. It maps each current path to its historical Enterprise path — exactly the map a clean-room implementer must not have |
| `docs/p-final/clean-room/03-clean-workspace-manifest.md` | this document. It is the recipe, addressed to the lead |
| `docs/product-enablement/07-branding-audit.md` | quotes the Enterprise licence terms |
| `docs/p7/00-discovery-findings.md` | quotes the Enterprise licence terms at length |

### And the rest of `docs/`

The repository holds **1,652 documents**. Seventy-seven of them mention an `enterprise/` path — mostly as a
factual statement about where code used to live, which is not Enterprise source. Rather than warrant a
file-by-file judgement on 1,652 documents, the export carries **only an allowlist**:

| included | why |
|---|---|
| `docs/p-final/clean-room/specs/A…E` | the five feature specifications |
| `docs/p-final/clean-room/01-acceptance-test-plan.md` | the acceptance criteria |
| `docs/p-final/clean-room/02-safe-interfaces.md` | what the implementer may call |
| `docs/p-final/clean-room/04-integration-contract.md` | what must stay compatible. **A deliberate addition** beyond the brief's list of three: it contains only current public contracts — routes, response keys, columns, capability names — and without it an implementer would have to rediscover the seven clean callers of the audit record by reading the whole tree |
| `docs/p-final/03-migration-review.md` | the rules this release deploys migrations under. Verified to contain **zero** occurrences of "enterprise" |

Everything else under `docs/` is excluded. The lead can add any individual document after their own read; no
clean-room document depends on one.

**A known, accepted consequence:** code comments in the retained clean source cite `docs/...` paths that are not
in the export. Those references dangle. That is cosmetic, and the alternative — vetting 1,652 files — is not
something this package can stand behind.

---

## 5. Removed for HYGIENE

| path | reason |
|---|---|
| `.git/` | **the single most important removal.** The repository history contains the complete pre-removal `enterprise/` tree at 31 shallow-boundary commits, plus every diff of its removal. An export with `.git` in it is not a clean-room workspace whatever else was deleted |
| `node_modules/`, `vendor/` | installed dependencies, 1.1 GB; `pnpm install` and `bundle install` restore them |
| `public/vite/`, `public/packs/` | build output, 1.3 GB; gitignored and rebuilt |
| `log/`, `tmp/` | 6.5 GB of local logs and caches, which can contain request data |
| `.env`, `.env.*` except `.env.example` | environment files never leave the machine. (None but `.env.example` existed here; the exclusion is defensive) |
| `coverage/`, `.rspec_status`, `.byebug_history`, `*.log` | local test and debug residue |

`.github/`, `.circleci/`, `Dockerfile`, `Procfile*`, `deployment/` and the rest of the build and deploy
configuration are **retained** — the implementer needs to be able to run the suite.

---

## 6. Retained, and worth saying out loud

- The whole of `app/` — upstream Chatwoot, MIT. This is the implementer's substrate.
- The whole of `app/javascript/` — the shipped frontend, which is the wire-format contract.
- `custom/` **minus the 39 files above** — every other Lynomia subsystem: P8 analytics, P9 support and
  operations, P10 identity and channels, P11 billing, Commerce, Flow Builder, the WhatsApp Template Manager,
  the audience feature, and the seven clean audit writers.
- `db/schema.rb` and every migration — the database contract.
- `config/` in full — routes, capabilities, locales.
- `spec/` **minus the 19 files above**, including `spec/factories/custom_roles.rb` (upstream MIT) and
  `spec/requests/p_final/existing_account_compatibility_spec.rb`.
- `Gemfile`, `Gemfile.lock`, `package.json`, `pnpm-lock.yaml` — the dependency set, including `audited`.

---

## 7. How the export was actually built

Not with a copy-and-delete over the working tree, but from **the list of git-tracked files**, which is a
stronger definition: it excludes every gitignored artefact (build output, caches, logs, dependency trees)
without having to enumerate them, and it cannot pick up a stray local file.

```
1. rel = `git ls-files` , minus everything under `docs/`            → 9,195 paths
2. withhold the 58 paths in §1–§3                                   → 9,137 files copied
3. re-add the allowlisted documents of §4                           → 9,146 files, 225 MB
4. one redaction, §9 item 3
```

Each of the 58 withheld paths was asserted to have been present before removal — the build fails loudly rather
than silently withholding nothing. Three directories survive as tracked placeholders Rails needs (`log/.keep`,
`tmp/.keep`, `vendor/assets/**/.keep`), and `vendor/db/sentiment-analysis.onnx` (66 MB, an upstream tracked
asset) is retained because it is part of the product.

To verify an export, assert all of:

```
no  .git                      no  enterprise/            no  spec/enterprise/
0   occurrences of "Chatwoot Enterprise License"
0   occurrences of "valid Chatwoot Enterprise subscription"
0   occurrences of "forbidden to copy, merge, publish"
0   of the 58 withheld paths present
only .env.example among .env*
0   of: docs/enterprise-audit, docs/p-final/04-code-provenance.md,
       docs/p-final/P_FINAL_BLOCKER_REPORT.md, clean-room/00-affected-files.md,
       clean-room/03-clean-workspace-manifest.md
app/ and custom/ present
```

All of these were asserted against `/tmp/lynomia-cleanroom-source` and all passed.

---

## 8. What the implementer is told, and what they are not

**Told:** what the product must do (the five specifications), what to check (the acceptance plan), what they may
call (the safe interfaces), and what must stay compatible (the integration contract).

**Not told:** that any particular file used to exist elsewhere, what it contained, how it was structured, or
where to look for it. No historical path, no measurement, no diff, no licence text, and no git history.


---

## 9. Sanitisation review

Every clean-room document and the whole export were re-read against four questions: does this name a
historical Enterprise path; does it quote or paraphrase Enterprise source; does it reproduce licence text; does
it describe *how* rather than *what*.

| # | finding | disposition |
|---|---|---|
| 1 | `00-affected-files.md` maps every current path to its historical Enterprise path, and carries overlap measurements | **excluded from the export** (§4). It is the lead's document |
| 2 | This manifest lists the withheld paths | **excluded from the export** (§4) |
| 3 | `app/models/portal.rb` — a retained, clean, upstream file — carried a Lynomia comment quoting a four-element expression attributed to a removed Enterprise service | **redacted in the export copy only.** The comment now states the behaviour (onboarding derived a portal name from the account's name) without the expression. The repository itself was left unchanged, because editing product code is outside this package's remit; **recommended to the lead** as a one-line follow-up |
| 4 | `spec/requests/custom/tenant_help_center_removal_spec.rb` names `Enterprise::Api::V1::Accounts::PortalsController#ssl_status` in a comment | **retained.** A class and method name, with no description of what it did. Removing it would make the spec's own reason unreadable |
| 5 | Six other retained files mention "Chatwoot Enterprise" in prose, stating what it permitted (e.g. that a knowledge-base capability could edit portal settings) or that a feature of it is absent | **retained.** These are statements of externally observable behaviour and of absence, which is the category this whole package is built on. Two of the six are upstream's own comments |
| 6 | 351 files in the export contain the word "Enterprise" | **retained.** Overwhelmingly upstream MIT content: locale strings naming a plan tier, the upstream extension-loading initializer, upgrade buttons, test fixtures. None is Enterprise overlay source |
| 7 | The five specifications and the acceptance plan were checked for structural leakage — method names, decomposition, control flow, helper structure, comment wording or test structure traceable to a prior implementation | **none found.** Every contract in them is sourced from `db/schema.rb`, `config/routes.rb`, `config/features.yml`, `app/javascript/**`, upstream MIT services, or the clean `custom/` policies and analytics. Where a package's difficulty is named, it is named as a product rule (forward-only outcomes, idempotence under redelivery) rather than as a design |
| 8 | The acceptance plan was checked against the twelve Enterprise-derived specs it replaces | **independent.** Its 98 scenarios were written from the product's observable surfaces; it is not a translation, it is organised by product area rather than by file, and it adds coverage those specs did not have (the tenant-isolation sweep, the restored-database compatibility scenario, the credential-planting assertions) |
| 9 | No legal conclusion is stated or implied anywhere in this package | **confirmed.** The register, the specifications, the plan, the safe-interface list, the integration contract and this manifest describe code, measurements and product behaviour only |
