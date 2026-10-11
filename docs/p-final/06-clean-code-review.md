# P-FINAL — clean-code, dead-code and performance review

Every entry below names a reason. P-FINAL's rule is that a change must reduce release risk, not diff size, so a
file that could be refactored but has no defect is left alone and is not listed. The permitted reasons are
SECURITY, CORRECTNESS, LICENSING, PROVENANCE, MAINTAINABILITY, DEAD CODE, PERFORMANCE and RELEASE SAFETY.

---

## 1. What was removed, and why each removal was safe

### 1.1 The Enterprise-derived implementation — PROVENANCE

39 production files and 19 specs, listed per file in `docs/p-final/clean-room/00-affected-files.md` and
`03-clean-workspace-manifest.md`. 34 of the 39 are replaced at the same path by the independent
implementation; 5 are gone for good:

| removed, not replaced | why it is not needed |
|---|---|
| `custom/app/policies/custom_role_policy.rb` | authorization moved to the boundary the codebase already uses — `check_admin_authorization?` on the account base controller plus an account-capability gate. A policy class for a resource only administrators may touch held no decision |
| `custom/app/views/api/v1/accounts/custom_roles/create.json.jbuilder` | the controller renders `:show` with `status: :created` |
| `custom/app/views/api/v1/accounts/custom_roles/update.json.jbuilder` | the controller renders `:show` |
| `custom/app/views/api/v1/models/_custom_role.json.jbuilder` | the partial now lives beside the views that render it; nothing else rendered it |
| `custom/app/jobs/campaigns/update_recipient_status_job.rb` | the report is applied where the webhook is already being processed. The deferral the job existed for is unnecessary: the write is one guarded update under a row lock |

**Verified before removal:** every reference to those five, across the whole tree, is in a document or a
comment — never in live code. The one live comment that named two removed methods
(`custom/app/services/analytics/campaigns/metrics.rb`) was corrected by the clean-room implementer in the same
change, and two P8 documents that cited them are annotated rather than silently left wrong.

### 1.2 Two Lynomia behaviours that were removed by mistake and restored — CORRECTNESS

Both removed WhatsApp files carried a second, unrelated Lynomia Flow Builder behaviour beside the campaign
behaviour that made them Enterprise-derived, and the register classified each file whole. The consequence was a
regression that the retained clean suite caught: inbound `interactive_reply` capture, and the outbound WhatsApp
list payload with its own button label.

Neither is Enterprise-derived, and that is measured rather than asserted: a search for `interactive_reply`,
`list_button` and `create_payload_based_on_items` across the entire pre-removal overlay at all three revisions
returns nothing, and the Enterprise originals of both files contain neither method. They are restored verbatim
from this project's own history. Full detail in `docs/p-final/04-code-provenance.md` §8 and commit `8ef4ab5e`.

**The lesson, recorded so it is not repeated:** a file-level provenance classification is not safe when a file
can hold two behaviours of different origin. The register should have been per-method where a file mixed them.

### 1.3 The X/Twitter channel — DEAD CODE

Removed earlier in P-FINAL, listed here for completeness: 4 controllers, 1 concern, 1 service, 1 webhook
handler, 3 parser/service files, 3 factories, 4 specs, 2 frontend files, and 4 route declarations. The channel
was not connectable: upstream removed the credential path and nothing in the product could create a Twitter
inbox. Zero importers for every file removed, checked individually.

### 1.4 Two comment redactions — PROVENANCE

`app/models/portal.rb` quoted a four-element expression attributed to a removed overlay service;
`custom/app/models/whatsapp/message_template.rb` named one historical overlay path and characterised its
content. Both are comment-only changes. No executable line moved.

---

## 2. What was deliberately NOT removed

Listed because "why is this still here" is a fair question at a release gate, and because each of these was
examined and left on purpose.

| left in place | reason |
|---|---|
| the voice/call frontend subsystem | its components are imported by the live conversation view, the contact panel and the message bubbles. Removing it means editing the product's most important screen for zero release-risk reduction |
| the empty `calls` table | dropping it is a destructive migration this release otherwise does not have. An empty table costs nothing |
| `account_users.agent_capacity_policy_id` | an orphaned column from the overlay era. Additive, nullable, unread. Dropping a column is destructive and buys nothing |
| the four LLM gems and the `openai` integration entry | inert without a key; both are dependency or tenant-visible changes whose risk at the gate exceeds the gain (`docs/p-final/02-license-audit.md` §4) |
| the upstream Captain controllers, services and policies under `app/` | upstream MIT files, complete in themselves, gated per account and inert without a key. Removing upstream files raises future merge friction for no behaviour change |
| `config/initializers/01_inject_enterprise_edition_module.rb` | upstream MIT, attributed to GitLab in its own header. It is the generic extension mechanism that makes `custom/` load at all; without it the application does not boot |
| the three `Audit::*` include sites upstream declares that nothing claims | upstream's own extension points. An unclaimed one is a no-op |

---

## 3. Orphan sweep after the exchange

Each of these was searched for across the whole tree, and every hit classified:

| symbol | live code hits | where the hits are |
|---|---|---|
| `CustomRolePolicy` | 0 | one historical audit document |
| `Campaigns::UpdateRecipientStatusJob` | 0 | historical audit and discovery documents |
| `update_from_whatsapp_status!` | 0 | two P8 documents, now annotated |
| `mark_skipped!` / `mark_sent!` / `mark_failed!` | 0 | the same documents |
| `last_provider_error` | 0 | historical audit documents only; the replacement reader is `last_send_failure` |
| `api/v1/models/_custom_role` | 0 | nothing renders it |
| `custom_roles/create`, `custom_roles/update` | 0 | the provenance and manifest documents |

Nothing in live code references anything that was removed. The application boots in production eager-load mode,
which is the check a green test suite does not give you — see `docs/p-final/08-production-uat-runbook.md` §3.

---

## 4. Performance — measured, not reasoned

Measured on the integrated tree against a real Postgres, counting the SQL each path issues after two warm-up
iterations. The harness is in the P-FINAL working material; it subscribes to `sql.active_record` and filters
only transaction and schema statements.

| path | queries | wall clock | note |
|---|---|---|---|
| **A** audit trail: one page of entries plus its meta | 3 | 2.0 ms | |
| **A** audit trail: the same page fully rendered through jbuilder | 3 → **5 on a 12-type page** | 10.2 ms | **re-measured.** The 3 was a page whose entries shared few auditable types. `includes(:auditable)` costs one query per DISTINCT type, and the trail's vocabulary is 14, so a mixed page cost up to 14 — loading whole Account and Inbox rows to read one integer. The preload is gone; a mixed page of 12 types now measures 5, selecting two columns per type (`perf` commit) |
| **B** capture cost on one audited inbox update | 3 | 6.3 ms | |
| **C** the capability list, 200 consecutive reads on one membership | **2** | 2.1 ms | |
| **D** campaign metrics endpoint service | 4 → **1** | 2.2 ms | **re-measured after the fix.** The 4 was right and was the defect: four passes over the campaign's recipients, three on predicates no index serves, on an endpoint the page polls every five seconds. One aggregate with `FILTER` clauses now, verified to agree with an independently computed value on all six counters |
| **D** recipient page of 25 with contacts | **2** | 2.3 ms | the query count was right; the ORDER BY had no index behind it and top-N sorted the whole campaign. Two indexes added, both chosen by the planner with no sort step |
| **D** `record_outcome!` applied 50 times, a row lock each | 50 → **100 when a report advances** | 57.6 ms | **corrected.** 50 is the idempotent case, where `progress_changes` returns `{}` and nothing is written. `with_lock` is `transaction { lock!; yield }`, so an advancing report is a `SELECT … FOR UPDATE` plus an `UPDATE`: 2 per report, not 1. The harness filters BEGIN/COMMIT, which is why the write was invisible |
| **E** delivery report whose identifier matches a recipient | 2 → **3 when it advances** | 2.1 ms | **corrected**, same reason: the `find_by` plus the two above |
| **E** delivery report whose identifier matches nothing | **1** | 0.3 ms | |

What those numbers establish:

- **No N+1 anywhere in the new code**, in the sense that no cost grows with the number of ROWS on a page: the
  recipient page costs 2 queries for 25 rows and the capability list 2 for 200 reads. The audit page's cost
  did grow with the number of distinct auditable TYPES on the page, which is bounded by the vocabulary rather
  than the page size and so is not an N+1 in rows — but it was a real cost for no benefit, and the table above
  records what replaced it.

- **Three of the figures in the first version of this table were measured correctly and read wrongly.** The
  two `record_outcome!` rows counted the idempotent case and were presented as the general one, and the
  metrics row counted four passes and did not ask whether four was right. A query count is only evidence if
  the case it was taken in is stated, which is why every row above now says which case it is.
- **The webhook path is cheapest in its commonest case.** A delivery report for an ordinary conversation
  message — which is most of them — costs one query to establish that no recipient owns the identifier.
- **`record_outcome!` is O(1) per report**, about 1.2 ms including the row lock. A burst of provider webhooks
  for one campaign contends per recipient row, not per campaign, because the lock is on the recipient.

Also re-verified: `custom/app/services/operations/account_health.rb` still memoizes `billing_enforced?`, so the
Super Admin account-health page reads the installation's billing settings once per page rather than once per
row. That was 30 of the 40 queries for a page of 10 before it was fixed.

### 4.1 Index coverage for the new queries

| query the new code issues | index |
|---|---|
| audit page, scoped and ordered by time | `audits` on `(associated_type, associated_id, created_at)` |
| audit filtered by actor | `audits` on `(user_id, user_type)` |
| recipients of one campaign, by state | `campaign_recipients` on `(campaign_id, status)` |
| recipients of one account | `campaign_recipients` on `(account_id, campaign_id)` |
| a recipient by provider identifier | `campaign_recipients` unique partial on `source_id WHERE source_id IS NOT NULL` |
| one role of one account | `custom_roles` on `account_id` |
| a membership's role | `account_users` on `custom_role_id` |

No query in the new code scans `audits` or `campaign_recipients` without one of those.

### 4.2 No new cache

The replacement adds no cache, and bypasses none. The one cache interaction it must not break is the cached
conversation-visibility flag that `app/models/account_user.rb:85-87` invalidates when `custom_role_id` changes;
the replacement detaches memberships **through the model** rather than with a bulk update, so that callback
still runs. That is asserted by an example in `spec/models/custom_role_spec.rb`.
