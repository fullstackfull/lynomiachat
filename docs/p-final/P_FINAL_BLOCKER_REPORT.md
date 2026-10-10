# P-FINAL BLOCKER REPORT

**Branch** `claude/p-final-commercial-release-hardening` · **Base** P11 tip `8bb3b49e` · **Production unchanged**
`b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`

P-FINAL stopped at the provenance audit (P-FINAL.2). The audit found that seventeen shipped code files and
twelve spec files in this product are **relocated Chatwoot Enterprise code** — moved out of `enterprise/` into
`custom/`, re-namespaced, and in nine cases byte-identical. `enterprise/LICENSE` forbids publishing,
distributing and selling that code without a Chatwoot Enterprise subscription.

This is a TRUE BLOCKER under two of the criteria the brief lists — *"probable non-permitted code that cannot be
independently rewritten without clarification"* and *"license incompatibility requiring legal/business
decision"* — so the phase reports rather than continues. Everything P-FINAL completed before reaching it is
listed in §H and is committed and pushed.

**No legal conclusion is drawn anywhere in this report.** It states facts from the repository and the decision
they force.

---

## A. Exact evidence

### A.1 The licence, quoted from this repository

`git show 79ca68fb~1:enterprise/LICENSE` — the Chatwoot Enterprise License, Copyright (c) 2017-2026 Chatwoot Inc:

> This software … may only be used in production, if you (and any entity that you represent) have agreed to, and
> are in compliance with, the Chatwoot Subscription Terms of Service … and otherwise have a valid Chatwoot
> Enterprise License for the correct number of user seats. … Notwithstanding the foregoing, **you may copy and
> modify the Software for development and testing purposes, without requiring a subscription.** … Subject to the
> foregoing, **it is forbidden to copy, merge, publish, distribute, sublicense, and/or sell the Software.**

The repository root `LICENSE` places everything under `enterprise/` — *"if that directory exists"* — under that
licence, and everything else under MIT Expat.

### A.2 Git records the moves itself

`git log --all -M --find-renames=40% --diff-filter=R --name-status`, filtered to renames whose source is
`enterprise/`, returns **23 renames by two Lynomia commits**, nine of them at R100 (byte-identical):

```
fbc485a8  2026-10-07  feat(commerce): Lynomia owns the custom role that grants order management
  R091  enterprise/app/models/custom_role.rb                    -> custom/app/models/custom_role.rb
  R100  enterprise/app/policies/custom_role_policy.rb           -> custom/app/policies/custom_role_policy.rb
  R100  enterprise/app/views/api/v1/accounts/custom_roles/{index,create,show,update}.json.jbuilder -> custom/...
  R100  enterprise/app/views/api/v1/models/{_custom_role,_account_user}.json.jbuilder               -> custom/...
  R070  enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb -> custom/...
  R073  enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb -> custom/...
  + 4 spec files out of spec/enterprise/

92211aba  2026-10-07  feat(campaigns): Lynomia owns WhatsApp campaign recipient tracking
  R100  enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb -> custom/...
  R100  enterprise/app/jobs/campaigns/update_recipient_status_job.rb -> custom/...
  R081  enterprise/app/models/campaign_recipient.rb -> custom/app/models/campaign_recipient.rb
  R083  enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb -> custom/...
  + 5 spec files out of spec/enterprise/
```

Neither commit is in the relocation list the brief supplied, so a review scoped to that list would have missed
both subsystems entirely.

### A.3 Verified byte-level diffs on the files the brief named

Three run by hand, output quoted:

```
$ diff -u <(git show 79ca68fb~1:enterprise/app/views/api/v1/accounts/audit_logs/show.json.jbuilder) \
          custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder
@@ -25,7 +25,6 @@
-      json.location audit_log.location
```
**One line removed. Every other line identical.**

```
$ diff -u <(git show 79ca68fb~1:enterprise/.../conversations/messages_controller.rb | sed 's/Enterprise::/Custom::/g') \
          custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb
@@ -1,3 +1,16 @@
+# Lynomia keeps Chatwoot's audit row for a deleted message after the Enterprise overlay goes …
```
**One hunk: a 13-line comment header. The 39 executable lines are identical.**

```
$ diff -u <(git show 79ca68fb~1:enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb) \
          custom/app/controllers/api/v1/accounts/audit_logs_controller.rb
```
**Three hunks: a comment header, the superclass swapped from `EnterpriseAccountsController` to
`BaseController`, and one four-line helper inlined.** The filtering, search, sort, pagination and rescue are
identical.

### A.4 An independent content sweep

For every tracked file under `custom/`, `app/`, `lib/` and `spec/`, compared by basename against every file
under `enterprise/` and `spec/enterprise/` as those trees stood at **three** revisions — `79ca68fb~1`,
`fbc485a8~1` and `92211aba~1`, because two relocations happened *before* the formal removal commit. Comparison
on substantive lines with `Enterprise::` normalised to `Custom::`.

541 enterprise files vs 8,212 current files → **31 files at ≥40% overlap with ≥8 shared substantive lines**, of
which 17 are shipped code and 12 are specs. Nine are byte-identical. Full table, with every row's percentage,
shared-line count and source path: `docs/p-final/04-code-provenance.md` §3 and Appendix A.

### A.5 Why none of it can be explained as Lynomia's own work returning home

- `git log --all --author=Claude --diff-filter=A -- 'enterprise/*'` is **empty**. No Lynomia commit ever added a
  file under `enterprise/`.
- `git blame` on the originals attributes them to upstream authors and upstream PR numbers (e.g. `channelable.rb`
  → "feat: enable assignment v2 by default for new accounts (#14031)"; `delete_object_job.rb` → "fix: captain
  template message conflict (#13048)").
- At every shallow boundary commit in this clone, `custom/` holds zero files.

### A.6 What is NOT affected

The P8–P11 delta itself — 50 commits, 440 files: analytics, the contact timeline, support cases, SLA, the
Operations Center, contact identities, channel capability, and the whole billing and entitlement subsystem — is
**original Lynomia work**. Two independent scans found no `enterprise/` ancestry and no content match above
threshold for any of it. The blocker is older than this release; the release merely ships it.

---

## B. Severity

**RELEASE BLOCKER for commercial distribution. Not a security issue, not a data-integrity issue, and not an
operational one.** The code works, is tested and is safe to run. The exposure is created by *publishing,
distributing or selling* it, which is precisely what the next steps after P-FINAL are for.

Development and internal testing are explicitly carved out by the licence text in §A.1, so this does not block
continued development, a staging deployment, or internal UAT.

---

## C. Affected code

| subsystem | what it does in the product | files | strongest evidence |
|---|---|---|---|
| **Audit log reader** | the server side of Settings → Audit Logs: controller + JSON view | 2 | 90% and 96% overlap; the view differs by one line |
| **Audit writers** | audit rows for message delete, sign-in/out, object destroy, channel change | 4 | 100%, 57%, 69%, 67% overlap; one has a verbatim executable body |
| **Audit model and declarations** | `Custom::AuditLog` scopes + `masked_remote_address`; 12 `custom/app/models/custom/audit/*.rb` | 1 + 12 | two at 100%/18 lines; the rest trivial |
| **Custom Roles** | the permission system Commerce's order-management role depends on: model, policy, 2 controllers, 6 views | 10 | git-recorded renames R070–R100; 7 byte-identical |
| **WhatsApp campaign recipients** | recipient tracking, its analytics endpoint, the status job, the one-off campaign service | 4 | git-recorded renames R081–R100; 96%, 96%, 92%, 100% |
| **WhatsApp inbound status** | `process_statuses`, provider base service | 2 | 100% and 94%; one copied before the original was deleted |
| **Specs** | tests for all of the above | 12 | 3 byte-identical; not distributed in a Rails deploy |

Three of these are load-bearing for features this product sells: **Custom Roles** (Commerce order management),
**campaign recipient tracking** (WhatsApp campaign analytics, which P8 reads), and the **audit log** (which P9,
P10 and P11 all write to and which this phase's own brief requires).

---

## D. Release impact

| | |
|---|---|
| Merge into `lynomia-custom` | safe — merging does not publish |
| Controlled deployment to the operator's own server | **not blocked by this.** Deploying to infrastructure you control is use, not distribution; and the development/testing carve-out covers a pilot. Whether *production* use needs a subscription is the question in §G |
| Full production UAT | not blocked |
| **Commercial release — selling the product to customers** | **blocked** until §G is answered |
| Security, data integrity, operations | unaffected; see §B |

---

## E. Safe options

| # | option | what it costs | what it leaves |
|---|---|---|---|
| **1** | **Confirm a Chatwoot Enterprise subscription covers this installation and its seat count.** | a licence cost and counsel's reading of whether the subscription covers a derived, rebranded, resold product | nothing to rewrite. The fastest path if the answer is yes |
| **2** | **Clean-room rewrite.** A fresh implementer who has **not** read the Enterprise originals rewrites each file from the product requirement, the database schema, the OSS interfaces and the existing specs. | 17 code files and 12 specs. The audit-log reader, Custom Roles and campaign recipients are real work (~40-60 substantive lines each); the twelve `audited` declarations and six one-line views are near-mechanical re-derivation from the schema | full functionality, no Enterprise text. The only option that removes the exposure without removing features |
| **3** | **Remove the affected features.** | Settings → Audit Logs disappears; Custom Roles disappears, taking Commerce's order-management role with it; WhatsApp campaign recipient tracking and its analytics disappear, which P8's campaign screens read | a smaller product, and it conflicts with this project's own audit-coverage requirements |
| **4** | **Replace with OSS equivalents where one exists.** | investigation per subsystem; upstream OSS has no audit-log reader, no custom roles and no campaign recipients, so this is likely to collapse into option 2 or 3 | partial relief at best |
| **5** | **Ship only to installations the operator runs, and do not sell the software.** | no engineering cost | not a commercial release, so it does not satisfy the goal |

Options 1 and 2 are not exclusive: a subscription now plus a rewrite later is a legitimate sequence, and a
rewrite is the only one of the five that is durable if the subscription lapses.

### Why this phase did not simply do option 2

P-FINAL.3 requires an *independent clean implementation*, "not simply rename/reformat". Establishing these
findings required reading every Enterprise original line by line and diffing it. Anything this audit wrote
afterwards would be a derivative in substance however different the text — so the rewrite has to be produced by
someone who has not read the originals, from the requirement, the schema and the specs. That is a procedure the
project can run; it is not something the auditor can perform on itself after the fact, and claiming otherwise
would be the rename-and-reformat the brief forbids.

---

## F. Recommended option

**Option 1 first, as a question; option 2 as the plan.**

Ask counsel one question (§G) before spending engineering effort, because the answer changes the scope from
"nothing" to "29 files". If the answer does not clear it, run option 2 as a scoped work package in this order,
cheapest and least entangled first:

1. the twelve `custom/app/models/custom/audit/*.rb` declarations and the six one-line custom-role views —
   mechanical re-derivation from the schema, no behaviour to preserve beyond what the specs already state;
2. the four audit writers and `Custom::AuditLog`'s scopes — small, well-specified, each with passing specs that
   pin the behaviour;
3. the audit-log reader (controller + view) — filtering, search, sort, pagination; a genuine piece of work;
4. Custom Roles — model, policy, two controllers, six views; the most entangled, because Commerce depends on it;
5. WhatsApp campaign recipients — model, job, analytics controller, campaign service; P8's campaign analytics
   reads it, so the contract is already written down.

Each step keeps the existing specs as the acceptance criteria, which is what makes a clean-room rewrite
verifiable rather than hopeful.

---

## G. The smallest decision required

> **Does Lynomia hold, or will it obtain, a Chatwoot Enterprise subscription that its counsel accepts as
> covering this installation — a rebranded derivative of Chatwoot sold commercially to Lynomia's own customers —
> for the relevant seat count?**
>
> - **Yes** → P-FINAL resumes and finishes; the provenance finding is recorded with the subscription as its
>   basis, and the rewrite becomes an optional hardening item rather than a blocker.
> - **No, and the features must stay** → authorise the clean-room rewrite in §F, run by an implementer who has
>   not read the Enterprise originals. P-FINAL resumes after it, and the gates re-run on the result.
> - **No, and the features may go** → authorise removal of the audit-log reader, Custom Roles and WhatsApp
>   campaign recipient tracking, and say whether Commerce's order-management role and P8's campaign analytics
>   should be reshaped or dropped with them.
>
> Nothing else about P-FINAL depends on this answer.

---

## H. What P-FINAL completed before stopping

All committed and pushed on `claude/p-final-commercial-release-hardening`, five commits, `cd798c84..7d210e79`:

| | done | evidence |
|---|---|---|
| **PF.0** baseline | `docs/p-final/00-baseline.md` | branch, ancestry, toolchain, schema, flags, routes, jobs, dependencies and the 50 commits, each measured with the command shown |
| **PF.1** changeset inventory | `docs/p-final/01-changeset-inventory.md` | all 440 files classified by area and phase, zero unclassified |
| **PF.2** provenance | `docs/p-final/04-code-provenance.md` | this blocker's evidence, 343 lines, with the raw sweep as an appendix |
| **PF.3** commercial-correctness closure | commit `783af209` | five of P11's six known limitations closed: plan narrowing refused while subscribers are billed (10 new examples), one canonical writer for commercial entitlements, suspension consequences stated in the form, billing reads permissioned, the masking floor. The sixth, period metering, deliberately not built |
| **PF.4** migrations | `docs/p-final/03-migration-review.md` | all 8 reviewed; all 8 reverted and re-applied; byte-identical `db/schema.rb` round trip; the one lock-risk migration switched to `CREATE INDEX CONCURRENTLY` |
| **PF.5** dead code | commit `7d210e79` | the X inbound library and connect page removed, reachability proven per file; the voice subsystem and the empty `calls` table deliberately kept, with reasons |
| **PF.6** performance | same commit | a 10-account / 171k-message fixture; 20 paths measured; one real N+1 found and fixed (Operations account health, 40 → 13 queries) |
| **PF.7** rollout and rollback | `docs/p-final/09-rollback-and-rollout.md` | the seven-lever matrix with file:line, the rollback decision tree, NO-GO conditions, observation window; `deploy.sh` gained an optional `EXPECT_SHA` |
| **P-FINAL.34** existing-account compatibility | `spec/requests/p_final/existing_account_compatibility_spec.rb` | 11 examples, 0 failures: no 402 anywhere, new surfaces inert, nothing commercial invented |
| **P-FINAL.24** i18n / RTL | measured | **zero** parity gaps introduced: all 20 new EN keys have Arabic siblings; the 98 gaps that exist are pre-existing upstream ones, unchanged since production. 33 new Vue components, no raw user-facing text, every direction-sensitive class explicitly `ltr:`/`rtl:` paired |

**Not done, because the phase stopped:** the licence audit write-up (`02-license-audit.md` — the dependency
scan ran and found nothing added since production, but the per-package classification is unwritten), the
security audit write-up (`05-security-audit.md` — six of nine dimensions have landed), the clean-code review
(`06-clean-code-review.md`), the release gate's 71 questions (`07-release-gate.md`), the production UAT runbook
(`08-production-uat-runbook.md`), the dedicated adversarial security suite (P-FINAL.28), and the five final
gates on a clean tree (P-FINAL.35).

**Three verdicts are deliberately withheld.** With a licensing blocker open and the release gate unanswered,
`DEVELOPMENT`, `CONTROLLED DEPLOYMENT` and `COMMERCIAL RELEASE` cannot honestly be graded. What can be said:
nothing found so far blocks development or a controlled deployment, and **commercial release is blocked by this
report alone.**
